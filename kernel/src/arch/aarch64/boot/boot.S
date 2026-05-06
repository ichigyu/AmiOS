// ┌─────────────────────────────────────────────────────────────┐
// │  arch/aarch64/boot/boot.S — ARMv8 裸机启动汇编              │
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
// │            ├─→ EL2：初始化 CPACR_EL1，直接运行              │
// │            ├─→ EL1：初始化 SCTLR_EL1/CPACR_EL1             │
// │            ├─→ 设置栈指针 SP                                │
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

    // 检测当前异常级别，x1 保存结果供后续分支使用
    mrs     x1, CurrentEL
    lsr     x1, x1, #2
    and     x1, x1, #3
    cmp     x1, #3
    b.eq    .el3_halt
    cmp     x1, #2
    b.eq    .init_el2

// ── 已在 EL1：初始化 EL1 系统寄存器 ─────────────────────────
.init_el1:
    // 清除 SCTLR_EL1 中的 M/A/C/I 位：禁用 MMU、对齐检查、数据缓存、指令缓存
    // 裸机启动阶段不需要这些功能，保持关闭状态直到后续章节显式启用
    mrs     x0, sctlr_el1
    bic     x0, x0, #(1 << 0)  // M：MMU 使能位
    bic     x0, x0, #(1 << 1)  // A：对齐检查使能位
    bic     x0, x0, #(1 << 2)  // C：数据缓存使能位
    bic     x0, x0, #(1 << 12) // I：指令缓存使能位
    msr     sctlr_el1, x0
    isb
    // FPEN[21:20]=11：允许 EL0/EL1 访问 FP/SIMD 寄存器，避免陷入
    mov     x0, #(3 << 20)
    msr     cpacr_el1, x0
    isb
    b       .init_common

// ── 在 EL2：飞腾 D2000 UEFI 固件锁定 HCR_EL2.TGE=1，eret 无法降级到 EL1 ──
// 根本原因：飞腾 EDK2 在 EL2 安装了自己的 VBAR_EL2，且 HCR_EL2 写入被静默忽略。
// 策略：放弃 EL2→EL1 切换，直接在 EL2 运行内核（VHE 模式）。
.init_el2:
    // VHE 模式下 CPACR_EL1 映射到 EL2 的 FP/SIMD 控制寄存器
    // FPEN[21:20]=11：允许 EL0/EL1（即 EL2/EL0 in VHE）访问 FP/SIMD，避免陷入
    mrs     x0, cpacr_el1
    orr     x0, x0, #(3 << 20)
    msr     cpacr_el1, x0
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

// ── 非 CPU0 的空闲循环 ────────────────────────────────────────
// 多核系统中，只有 CPU0 执行内核初始化
// 其余核心执行 WFE（Wait For Event）进入低功耗状态
.cpu_idle:
    wfe                         // 等待事件（低功耗等待）
    b       .cpu_idle

// ── EL3 停机 ──────────────────────────────────────────────────
// AmiOS 不支持从 EL3 启动（EL3 由 ARM Trusted Firmware 持有）
// 若固件在 EL3 交接，在此死循环，GDB 可通过 PC 值定位到此处
.el3_halt:
    wfe
    b       .el3_halt
