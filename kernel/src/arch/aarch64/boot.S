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
// │                                                             │
// │  平台标志：由 boot.rs 通过 concat!(include_str!(env!(...)))  │
// │            将 build.rs 生成的 platform.inc 内联到本文件前    │
// │            phytium-d2000 → PHYTIUM_D2000 符号已定义         │
// │            qemu-virt     → 无符号定义                        │
// └─────────────────────────────────────────────────────────────┘

// 将 _start 放入 .text.boot 段，链接脚本保证它位于 KERNEL_BASE
.section .text.boot
.global _start          // 导出 _start 符号，链接脚本的 ENTRY 指向它

// ── UART 直写辅助宏（仅用于启动阶段调试）─────────────────────
// 在 Rust 运行时就绪之前，通过直接写 MMIO 寄存器输出单个字符
// 由 build.rs 生成的 platform.inc 控制是否定义 PHYTIUM_D2000，
// 避免 QEMU 上访问 D2000 的 UART 地址（0x28001000）触发异常卡死
.ifdef PHYTIUM_D2000
.macro uart_debug_init
    ldr     x20, =0x28001000    // D2000 PL011 UART1 基地址（ttyAMA0）
.endm
.macro uart_putc c
    mov     w19, #\c
99: ldr     w18, [x20, #0x18]   // 读 UARTFR
    tbnz    w18, #5, 99b        // TXFF（bit5）=1 则等待发送 FIFO 有空间
    str     w19, [x20, #0x00]   // 写 UARTDR，发送字符
.endm
.else
// QEMU 或其他平台：调试宏展开为空，不产生任何指令
.macro uart_debug_init
.endm
.macro uart_putc c
.endm
.endif

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
    // 读-改-写，保留 UEFI 设置的其他位，只确保 RW=1
    // 同时清除可能导致 EL1 系统寄存器访问陷入的位：
    //   bit31 (RW)   = 1：EL1 运行在 AArch64 模式（而非 AArch32）
    //   bit30 (TRVM) = 0：不陷入 EL1 读取虚拟内存控制寄存器（如 SCTLR_EL1）
    //   bit26 (TVM)  = 0：不陷入 EL1 写入虚拟内存控制寄存器
    // D2000 固件可能设置了 TRVM/TVM，导致 EL1 执行 mrs SCTLR_EL1 时陷入 EL2
    mrs     x0, hcr_el2
    orr     x0, x0, #(1 << 31)     // RW=1，EL1 使用 64 位模式
    bic     x0, x0, #(1 << 30)     // TRVM=0：允许 EL1 读取虚拟内存控制寄存器
    bic     x0, x0, #(1 << 26)     // TVM=0：允许 EL1 写入虚拟内存控制寄存器
    msr     hcr_el2, x0

    // 配置 SPSR_EL2（Saved Program Status Register）
    // 这是 ERET 后 PSTATE 的值：
    //   bit9 (D) = 1：调试异常屏蔽（防止固件开启的调试异常在 EL1 触发）
    //   bit8 (A) = 1：SError 异常屏蔽
    //   bit7 (I) = 1：IRQ 中断屏蔽（暂时关闭，后续章节开启）
    //   bit6 (F) = 1：FIQ 中断屏蔽
    //   bit4 (M[4]) = 0：AArch64 模式
    //   bit3:0 (M[3:0]) = 0101：EL1h（EL1 使用 SP_EL1 作为栈指针）
    // 0x3C5 = 0b1111000101：D/A/I/F 全部屏蔽（bit6~9），EL1h 模式
    mov     x0, #0x3C5          // EL1h 模式 + D/A/I/F 全部屏蔽
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
    // 第一件事：初始化 SCTLR_EL1，必须在任何内存访问之前执行
    // 不能直接写 0：SCTLR_EL1 有 RES1 位（ARMv8 规范要求必须为 1），
    // 写 0 会导致 UNPREDICTABLE 行为，在 QEMU 和真实硬件上都可能卡死。
    // 正确做法：先读出当前值，再清除需要关闭的位，保留 RES1 位。
    // 关闭：M(0)=MMU, A(1)=对齐检查, C(2)=D-cache, I(12)=I-cache
    mrs     x0, sctlr_el1
    bic     x0, x0, #(1 << 0)   // M=0：关闭 MMU
    bic     x0, x0, #(1 << 1)   // A=0：关闭对齐检查
    bic     x0, x0, #(1 << 2)   // C=0：关闭 D-cache
    bic     x0, x0, #(1 << 12)  // I=0：关闭 I-cache
    msr     sctlr_el1, x0
    isb                          // 指令同步屏障：确保立即生效

    // 设置临时异常向量表
    // UEFI 退出后 VBAR_EL1 仍指向已失效的 UEFI 异常向量表。
    // 内核在 EL1 执行时，任何异常都会跳到无效地址卡死且无输出。
    // 在栈和 BSS 就绪之前，先设置一个简单的死循环向量表兜底。
    adr     x0, .simple_vectors
    msr     vbar_el1, x0
    isb

    // 允许 EL1 访问 FP/SIMD（CPACR_EL1.FPEN = 0b11）
    // Rust 编译器优化可能生成 NEON 指令，若 FPEN=0 则触发陷入异常。
    // 陷入后因 VBAR_EL1 无效（上一步已修复）或向量表未完善而卡死。
    mov     x0, #(3 << 20)      // FPEN[21:20]=11：EL0/EL1 均可访问 FP/SIMD
    msr     cpacr_el1, x0
    isb

    // 初始化调试用 UART 基地址寄存器（D2000 平台有效，其他平台为空操作）
    uart_debug_init
    uart_putc '1'                // 输出 '1'：系统寄存器初始化完成

    // 设置 EL1 栈指针
    // _stack_top 由链接脚本定义，指向 BSS 段之后的栈顶
    // ARMv8 栈向低地址增长，SP 初始化为栈顶（高地址）
    ldr     x0, =_stack_top
    mov     sp, x0
    uart_putc '2'               // 输出 '2'：栈指针设置完成

    // ── 清零 BSS 段 ───────────────────────────────────────────
    // BSS 段存放未初始化的全局变量，C/Rust 语义要求它们初始值为 0
    // 但硬件上电后内存内容不确定，必须手动清零
    ldr     x0, =_start_bss
    ldr     x1, =_end_bss
    cmp     x0, x1
    b.ge    .bss_done
.bss_loop:
    str     xzr, [x0], #8
    cmp     x0, x1
    b.lt    .bss_loop
.bss_done:
    uart_putc '3'               // 输出 '3'：BSS 清零完成

    uart_putc '4'               // 输出 '4'：即将跳转 kernel_main
    bl      kernel_main

    b       .

// ── 临时异常向量表 ────────────────────────────────────────────
// ARMv8 异常向量表必须 2KB 对齐（VBAR_EL1[10:0] 必须为 0）
// 每个入口 128 字节（32 条指令），共 16 个入口（4 类 × 4 种异常）
// 当前阶段没有异常处理能力，所有入口均为死循环，防止跳飞
.balign 2048
.simple_vectors:
    // Current EL with SP0: Synchronous
    b       .simple_vectors + 0x000
    .balign 128
    // Current EL with SP0: IRQ
    b       .simple_vectors + 0x080
    .balign 128
    // Current EL with SP0: FIQ
    b       .simple_vectors + 0x100
    .balign 128
    // Current EL with SP0: SError
    b       .simple_vectors + 0x180
    .balign 128
    // Current EL with SPx: Synchronous
    b       .simple_vectors + 0x200
    .balign 128
    // Current EL with SPx: IRQ
    b       .simple_vectors + 0x280
    .balign 128
    // Current EL with SPx: FIQ
    b       .simple_vectors + 0x300
    .balign 128
    // Current EL with SPx: SError
    b       .simple_vectors + 0x380
    .balign 128
    // Lower EL AArch64: Synchronous
    b       .simple_vectors + 0x400
    .balign 128
    // Lower EL AArch64: IRQ
    b       .simple_vectors + 0x480
    .balign 128
    // Lower EL AArch64: FIQ
    b       .simple_vectors + 0x500
    .balign 128
    // Lower EL AArch64: SError
    b       .simple_vectors + 0x580
    .balign 128
    // Lower EL AArch32: Synchronous
    b       .simple_vectors + 0x600
    .balign 128
    // Lower EL AArch32: IRQ
    b       .simple_vectors + 0x680
    .balign 128
    // Lower EL AArch32: FIQ
    b       .simple_vectors + 0x700
    .balign 128
    // Lower EL AArch32: SError
    b       .simple_vectors + 0x780
    .balign 128

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
