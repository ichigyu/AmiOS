// ┌─────────────────────────────────────────────────────────────┐
// │  src/boot.rs — ARMv8 裸机启动代码                           │
// │                                                             │
// │  职责：从 QEMU 上电到进入 Rust kernel_main 的完整引导链      │
// │                                                             │
// │  执行流程：                                                  │
// │    QEMU 加载内核到 0x40080000                               │
// │      └─→ _start（本文件，汇编入口）                          │
// │            ├─→ 检测当前异常级别（EL）                        │
// │            ├─→ 若在 EL2，切换到 EL1                         │
// │            ├─→ 设置栈指针 SP_EL1                            │
// │            ├─→ 清零 BSS 段                                  │
// │            └─→ 跳转到 kernel_main（src/main.rs）            │
// └─────────────────────────────────────────────────────────────┘

// global_asm! 宏：将汇编代码直接嵌入到当前编译单元
// 这段汇编会被放入 .text.boot 段（链接脚本中排在最前面）
use core::arch::global_asm;

global_asm!(
    r#"
// 将 _start 放入 .text.boot 段，链接脚本保证它位于 0x40080000
.section .text.boot
.global _start          // 导出 _start 符号，链接脚本的 ENTRY 指向它

// ── 内核入口 ──────────────────────────────────────────────────
// QEMU 加载内核后，所有 CPU 核心都会从这里开始执行
// 我们只让 CPU0 继续，其余核心进入低功耗等待状态
_start:
    // 读取当前 CPU 编号（MPIDR_EL1 寄存器的低 8 位是 CPU ID）
    mrs     x0, mpidr_el1       // 读取多处理器亲和寄存器
    and     x0, x0, #0xFF       // 提取 Aff0 字段（CPU 编号）
    cbnz    x0, .cpu_idle       // 若不是 CPU0，跳转到空闲循环

    // ── 检测当前异常级别 ──────────────────────────────────────
    // ARMv8 有 EL0（用户态）、EL1（内核态）、EL2（虚拟机监控）、EL3（安全监控）
    // QEMU virt 默认从 EL2 启动，内核需要运行在 EL1
    mrs     x0, CurrentEL       // 读取当前异常级别寄存器
    lsr     x0, x0, #2          // CurrentEL[3:2] 是 EL 值，右移 2 位提取
    and     x0, x0, #3          // 屏蔽高位，只保留 EL 值（0~3）
    cmp     x0, #2              // 判断是否在 EL2
    b.eq    .el2_to_el1         // 若在 EL2，执行降级切换
    // 若已在 EL1（某些配置下），直接跳到 EL1 初始化
    b       .el1_init

// ── EL2 → EL1 切换 ───────────────────────────────────────────
// 通过配置系统寄存器后执行 ERET 指令，模拟从 EL2 异常返回到 EL1
.el2_to_el1:
    // 配置 HCR_EL2（Hypervisor Configuration Register）
    // bit31 (RW) = 1：EL1 运行在 AArch64 模式（而非 AArch32）
    mov     x0, #(1 << 31)      // RW=1，EL1 使用 64 位模式
    msr     hcr_el2, x0         // 写入 HCR_EL2

    // 配置 SPSR_EL2（Saved Program Status Register）
    // 这是 ERET 后 PSTATE 的值：
    //   bit9 (D) = 1：调试异常屏蔽
    //   bit8 (A) = 1：SError 异常屏蔽
    //   bit7 (I) = 1：IRQ 中断屏蔽（暂时关闭，后续章节开启）
    //   bit6 (F) = 1：FIQ 中断屏蔽
    //   bit4 (M[4]) = 0：AArch64 模式
    //   bit3:0 (M[3:0]) = 0101：EL1h（EL1 使用 SP_EL1 作为栈指针）
    mov     x0, #0x5            // EL1h 模式（0b0101：EL1 使用 SP_EL1）
    orr     x0, x0, #0x1C0     // 屏蔽所有中断（D/A/I/F 位，bit6~9）
    msr     spsr_el2, x0        // 写入 SPSR_EL2

    // 配置 ELR_EL2（Exception Link Register）
    // ERET 执行后，PC 跳转到 ELR_EL2 指向的地址
    adr     x0, .el1_init       // 计算 .el1_init 标签的绝对地址
    msr     elr_el2, x0         // 设置返回地址为 EL1 初始化代码

    // 执行异常返回：CPU 切换到 EL1，PC 跳转到 .el1_init
    eret

// ── EL1 初始化 ────────────────────────────────────────────────
// 此时已在 EL1 运行，完成进入 Rust 前的最后准备工作
.el1_init:
    // 设置 EL1 栈指针
    // _stack_top 由链接脚本定义，指向 BSS 段之后的栈顶
    // ARMv8 栈向低地址增长，SP 初始化为栈顶（高地址）
    ldr     x0, =_stack_top     // 加载栈顶地址
    mov     sp, x0              // 设置栈指针

    // ── 清零 BSS 段 ───────────────────────────────────────────
    // BSS 段存放未初始化的全局变量，C/Rust 语义要求它们初始值为 0
    // 但硬件上电后内存内容不确定，必须手动清零
    ldr     x0, =_start_bss     // BSS 段起始地址
    ldr     x1, =_end_bss       // BSS 段结束地址
    cmp     x0, x1              // 检查 BSS 段是否为空
    b.ge    .bss_done            // 若起始 >= 结束，跳过清零
.bss_loop:
    str     xzr, [x0], #8      // 将 0 写入当前地址，然后地址 +8（按 8 字节清零）
    cmp     x0, x1              // 检查是否到达 BSS 段末尾
    b.lt    .bss_loop            // 若未到末尾，继续循环
.bss_done:

    // ── 跳转到 Rust 内核主函数 ────────────────────────────────
    // kernel_main 在 src/main.rs 中定义，标注为 -> ! 不会返回
    bl      kernel_main         // 调用 kernel_main（Branch with Link）

    // 理论上不会执行到这里，但以防万一加一个无限循环
    b       .

// ── 非 CPU0 的空闲循环 ────────────────────────────────────────
// 多核系统中，只有 CPU0 执行内核初始化
// 其余核心执行 WFE（Wait For Event）进入低功耗状态
.cpu_idle:
    wfe                         // 等待事件（低功耗等待）
    b       .cpu_idle           // 被唤醒后继续等待（后续章节实现多核调度）
"#
);
