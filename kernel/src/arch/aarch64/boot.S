// ┌─────────────────────────────────────────────────────────────┐
// │  arch/aarch64/boot.S — ARMv8 裸机启动汇编                   │
// │                                                             │
// │  职责：从固件上电到进入 Rust kernel_main 的完整引导链        │
// │                                                             │
// │  支持的入口异常级别：                                        │
// │    EL2（QEMU virt / 飞腾 D2000 UEFI 默认交接）              │
// │      → 直接在 EL2 运行（VHE 模式）                          │
// │      → 飞腾 D2000 平台设计如此：固件始终在 EL2 交接，        │
// │            原生 Linux 也在 EL2 运行（dmesg: started at EL2） │
// │            HCR_EL2.TGE=1 由固件设置，写入被静默忽略          │
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
// │            ├─→ EL2：初始化 CPACR_EL1/VBAR_EL2，直接运行    │
// │            ├─→ EL1：初始化 SCTLR_EL1/VBAR_EL1/CPACR_EL1   │
// │            ├─→ 设置栈指针 SP                                │
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
// uart_putc：轮询 TXFF（bit5），等待发送 FIFO 有空间后写入字符
// 使用 x19/x18 作为临时寄存器，x20 须已由 uart_debug_init 初始化
// 用 \@ 生成每次展开唯一的标号，避免重复定义错误
.macro uart_putc c
    mov     w19, #\c
.Ltxwait_\@:
    ldr     w18, [x20, #0x18]
    tbnz    w18, #5, .Ltxwait_\@
    str     w19, [x20, #0x00]
.endm
.else
.macro uart_debug_init
.endm
.macro uart_putc c
.endm
.endif

// ── 内核入口 ──────────────────────────────────────────────────
// 固件加载内核后，所有 CPU 核心都会从这里开始执行
// 我们只让 CPU0 继续，其余核心进入低功耗等待状态
_start:
    // 最先初始化调试 UART 基地址寄存器（x20），后续所有 uart_putc 依赖它
    // 必须在任何 uart_putc 调用之前执行，包括 .el2_to_el1 中的探针
    uart_debug_init

    // 读取当前 CPU 编号（MPIDR_EL1 寄存器的低 8 位是 CPU ID）
    mrs     x0, mpidr_el1       // 读取多处理器亲和寄存器
    and     x0, x0, #0xFF       // 提取 Aff0 字段（CPU 编号）
    cbnz    x0, .cpu_idle       // 若不是 CPU0，跳转到空闲循环

    // ── 检测当前异常级别 ──────────────────────────────────────
    // QEMU virt 和 D2000 固件均在 EL2 交接
    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    and     x0, x0, #3
    cmp     x0, #3
    b.eq    .el3_halt
    b       .el_init            // EL2 或 EL1：进入初始化流程

// ── 内核初始化入口 ────────────────────────────────────────────
.el_init:
    mrs     x1, CurrentEL
    lsr     x1, x1, #2
    and     x1, x1, #3
    cmp     x1, #2
    b.eq    .init_el2_to_el1

// ── 已在 EL1：直接初始化 EL1 系统寄存器 ─────────────────────
.init_el1:
    mrs     x0, sctlr_el1
    bic     x0, x0, #(1 << 0)
    bic     x0, x0, #(1 << 1)
    bic     x0, x0, #(1 << 2)
    bic     x0, x0, #(1 << 12)
    msr     sctlr_el1, x0
    isb
    adr     x0, .simple_vectors
    msr     vbar_el1, x0
    isb
    mov     x0, #(3 << 20)
    msr     cpacr_el1, x0
    isb
    b       .init_common

// ── 在 EL2：飞腾 D2000 UEFI 固件锁定 HCR_EL2.TGE=1，eret 无法降级到 EL1 ──
// 根本原因：飞腾 EDK2 在 EL2 安装了自己的 VBAR_EL2，且 HCR_EL2 写入被静默忽略。
// 策略：放弃 EL2→EL1 切换，直接在 EL2 运行内核（VHE 模式）。
.init_el2_to_el1:
    // VHE 模式下 CPACR_EL1 映射到 EL2 的 FP/SIMD 控制寄存器
    // FPEN[21:20]=11：允许 EL0/EL1（即 EL2/EL0 in VHE）访问 FP/SIMD，避免陷入
    mrs     x0, cpacr_el1
    orr     x0, x0, #(3 << 20)
    msr     cpacr_el1, x0
    isb

    // 设置 EL2 异常向量表，防止任何异常跳到已失效的 UEFI 向量表
    adr     x0, .simple_vectors
    msr     vbar_el2, x0
    isb

    b       .init_common

// ── 公共初始化（EL1/EL2 共用）────────────────────────────────
.init_common:
    // 设置栈指针（_stack_top 由链接脚本定义，ARMv8 栈向低地址增长）
    ldr     x0, =_stack_top
    mov     sp, x0

    // 清零 BSS 段（未初始化全局变量，C/Rust 语义要求初始值为 0）
    ldr     x0, =_start_bss
    ldr     x1, =_end_bss
    cmp     x0, x1
    b.ge    .bss_done
.bss_loop:
    str     xzr, [x0], #8
    cmp     x0, x1
    b.lt    .bss_loop
.bss_done:

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
