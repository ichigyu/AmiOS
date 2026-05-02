// ┌─────────────────────────────────────────────────────────────┐
// │  arch/aarch64/boot.S — ARMv8 裸机启动汇编                   │
// │                                                             │
// │  职责：从固件上电到进入 Rust kernel_main 的完整引导链        │
// │                                                             │
// │  支持的入口异常级别：                                        │
// │    EL2（QEMU virt 默认）→ 切换到 EL1 后继续                 │
// │    EL1（部分固件直接交接）→ 直接继续                         │
// │    EL3 → 停机（死循环），不支持从 EL3 启动                   │
// │           EL3 通常由 ARM Trusted Firmware 持有，             │
// │           正常启动链不应在 EL3 交接内核                      │
// │                                                             │
// │  执行流程：                                                  │
// │    固件加载内核到 KERNEL_BASE                               │
// │      └─→ _start（本文件，汇编入口）                          │
// │            ├─→ 检测当前异常级别（EL）                        │
// │            ├─→ EL3：跳转到 .el3_halt 死循环（GDB 可定位）   │
// │            ├─→ EL2：切换到 EL1                              │
// │            ├─→ EL1：直接继续                                 │
// │            ├─→ 设置栈指针 SP_EL1                            │
// │            ├─→ 清零 BSS 段                                  │
// │            └─→ 跳转到 kernel_main                           │
// └─────────────────────────────────────────────────────────────┘

// 将 _start 放入 .text.boot 段，链接脚本保证它位于 KERNEL_BASE
.section .text.boot
.global _start          // 导出 _start 符号，链接脚本的 ENTRY 指向它

// ── 内核入口 ──────────────────────────────────────────────────
// 固件加载内核后，所有 CPU 核心都会从这里开始执行
// 我们只让 CPU0 继续，其余核心进入低功耗等待状态
_start:
    // 读取当前 CPU 编号（MPIDR_EL1 寄存器的低 8 位是 CPU ID）
    mrs     x0, mpidr_el1       // 读取多处理器亲和寄存器
    and     x0, x0, #0xFF       // 提取 Aff0 字段（CPU 编号）
    cbnz    x0, .cpu_idle       // 若不是 CPU0，跳转到空闲循环

    // ── 检测当前异常级别 ──────────────────────────────────────
    // ARMv8 有 EL0（用户态）、EL1（内核态）、EL2（虚拟机监控）、EL3（安全监控）
    // QEMU virt 默认从 EL2 启动；部分真实硬件固件在 EL1 交接
    mrs     x0, CurrentEL       // 读取当前异常级别寄存器
    lsr     x0, x0, #2          // CurrentEL[3:2] 是 EL 值，右移 2 位提取
    and     x0, x0, #3          // 屏蔽高位，只保留 EL 值（0~3）
    cmp     x0, #3              // 判断是否在 EL3
    b.eq    .el3_halt            // EL3 不支持，跳转到停机循环
    cmp     x0, #2              // 判断是否在 EL2
    b.eq    .el2_to_el1         // 若在 EL2，执行降级切换
    // 若已在 EL1（某些固件直接在 EL1 交接），直接跳到 EL1 初始化
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

// ── UART 直写辅助宏（仅用于启动阶段调试）─────────────────────
// 在 Rust 运行时就绪之前，通过直接写 MMIO 寄存器输出单个字符
// x20 保存 UART 基地址（callee-saved，不会被后续指令破坏）
// 使用前需先执行 .uart_debug_init，之后用 .uart_putc 输出字符
.macro uart_debug_init
    ldr     x20, =0x28001000    // D2000 PL011 UART1 基地址
.endm

// 输出单个 ASCII 字符，\c 为立即数（如 '1'、'2'）
// 轮询 UARTFR[5]（TXFF）等待发送 FIFO 不满，再写 UARTDR
.macro uart_putc c
    mov     w19, #\c
99: ldr     w18, [x20, #0x18]   // 读 UARTFR
    tbnz    w18, #5, 99b        // TXFF=1 则等待
    str     w19, [x20, #0x00]   // 写 UARTDR
.endm

// ── EL1 初始化 ────────────────────────────────────────────────
// 此时已在 EL1 运行，完成进入 Rust 前的最后准备工作
.el1_init:
    // 初始化调试用 UART 基地址寄存器
    uart_debug_init

    // 显式初始化 SCTLR_EL1（System Control Register）
    // UEFI 固件可能在 EL1 留下了开启 MMU、缓存或对齐检查的状态，
    // 不清零会导致内核在没有页表/异常向量的情况下触发异常后卡死。
    // 写入 0：关闭 MMU（M=0）、关闭 D-cache（C=0）、关闭 I-cache（I=0）、
    //         关闭对齐检查（A=0）、关闭 SP 对齐检查（SA=0）
    msr     sctlr_el1, xzr     // 清零 SCTLR_EL1，确保 MMU/cache 全部关闭
    isb                         // 指令同步屏障：确保 SCTLR_EL1 写入立即生效
    uart_putc '1'               // 输出 '1'：SCTLR_EL1 初始化完成

    // 设置 EL1 栈指针
    // _stack_top 由链接脚本定义，指向 BSS 段之后的栈顶
    // ARMv8 栈向低地址增长，SP 初始化为栈顶（高地址）
    ldr     x0, =_stack_top     // 加载栈顶地址
    mov     sp, x0              // 设置栈指针
    uart_putc '2'               // 输出 '2'：栈指针设置完成

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
    uart_putc '3'               // 输出 '3'：BSS 清零完成

    // ── 跳转到 Rust 内核主函数 ────────────────────────────────
    // kernel_main 在 kernel/src/kernel/mod.rs 中定义，标注为 -> ! 不会返回
    uart_putc '4'               // 输出 '4'：即将跳转 kernel_main
    bl      kernel_main         // 调用 kernel_main（Branch with Link）

    // 理论上不会执行到这里，但以防万一加一个无限循环
    b       .

// ── 非 CPU0 的空闲循环 ────────────────────────────────────────
// 多核系统中，只有 CPU0 执行内核初始化
// 其余核心执行 WFE（Wait For Event）进入低功耗状态
.cpu_idle:
    wfe                         // 等待事件（低功耗等待）
    b       .cpu_idle           // 被唤醒后继续等待（后续章节实现多核调度）

// ── EL3 停机 ──────────────────────────────────────────────────
// AmiOS 不支持从 EL3 启动（EL3 由 ARM Trusted Firmware 持有）
// 若固件在 EL3 交接，在此死循环，GDB 可通过 PC 值定位到此处
// 调试方法：make debug，GDB 连接后 `info registers pc` 确认卡在此处
.el3_halt:
    wfe                         // 低功耗等待，避免空转消耗功率
    b       .el3_halt           // 死循环，永不退出
