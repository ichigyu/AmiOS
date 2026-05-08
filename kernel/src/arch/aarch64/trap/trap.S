// AArch64 异常向量表 + 上下文保存/恢复
//
// AArch64 向量表结构（每项 128 字节，共 16 项，总计 2KB，需 2KB 对齐）：
//   偏移 0x000: Current EL, SP_EL0 — Sync / IRQ / FIQ / SError
//   偏移 0x200: Current EL, SP_ELx — Sync / IRQ / FIQ / SError
//   偏移 0x400: Lower EL, AArch64  — Sync / IRQ / FIQ / SError
//   偏移 0x600: Lower EL, AArch32  — Sync / IRQ / FIQ / SError
//
// 当前阶段内核与用户程序均运行在同一 EL（EL1 或 EL2），
// SVC 触发 "Current EL with SP_ELx, Synchronous" 异常（偏移 0x200）。

    .section .text
    .global exception_vector_table

// ── 辅助宏 ────────────────────────────────────────────────────────────────────

// 保存所有通用寄存器到栈上（TrapContext 布局，共 31 个 x 寄存器 + sp + pc + pstate）
.macro SAVE_ALL
    // 在当前栈上分配 TrapContext（34 × 8 = 272 字节）
    sub     sp, sp, #34 * 8
    // 保存 x0-x29（成对保存）
    stp     x0,  x1,  [sp, #0  * 8]
    stp     x2,  x3,  [sp, #2  * 8]
    stp     x4,  x5,  [sp, #4  * 8]
    stp     x6,  x7,  [sp, #6  * 8]
    stp     x8,  x9,  [sp, #8  * 8]
    stp     x10, x11, [sp, #10 * 8]
    stp     x12, x13, [sp, #12 * 8]
    stp     x14, x15, [sp, #14 * 8]
    stp     x16, x17, [sp, #16 * 8]
    stp     x18, x19, [sp, #18 * 8]
    stp     x20, x21, [sp, #20 * 8]
    stp     x22, x23, [sp, #22 * 8]
    stp     x24, x25, [sp, #24 * 8]
    stp     x26, x27, [sp, #26 * 8]
    stp     x28, x29, [sp, #28 * 8]
    // 保存 x30（lr）和异常前的 sp（加上已分配的帧大小还原）
    add     x9, sp, #34 * 8
    stp     x30, x9,  [sp, #30 * 8]
    // 保存 ELR（异常返回地址）和 SPSR
    mrs     x9,  elr_el1
    mrs     x10, spsr_el1
    stp     x9,  x10, [sp, #32 * 8]
.endm

.macro RESTORE_ALL
    // 恢复 ELR 和 SPSR
    ldp     x9,  x10, [sp, #32 * 8]
    msr     elr_el1,  x9
    msr     spsr_el1, x10
    // 恢复 x0-x29
    ldp     x0,  x1,  [sp, #0  * 8]
    ldp     x2,  x3,  [sp, #2  * 8]
    ldp     x4,  x5,  [sp, #4  * 8]
    ldp     x6,  x7,  [sp, #6  * 8]
    ldp     x8,  x9,  [sp, #8  * 8]
    ldp     x10, x11, [sp, #10 * 8]
    ldp     x12, x13, [sp, #12 * 8]
    ldp     x14, x15, [sp, #14 * 8]
    ldp     x16, x17, [sp, #16 * 8]
    ldp     x18, x19, [sp, #18 * 8]
    ldp     x20, x21, [sp, #20 * 8]
    ldp     x22, x23, [sp, #22 * 8]
    ldp     x24, x25, [sp, #24 * 8]
    ldp     x26, x27, [sp, #26 * 8]
    ldp     x28, x29, [sp, #28 * 8]
    ldp     x30, xzr, [sp, #30 * 8]   // sp 由 eret 自动恢复，丢弃
    add     sp, sp, #34 * 8
.endm

// ── 向量表（必须 2KB 对齐）────────────────────────────────────────────────────
    .balign 0x800
exception_vector_table:

// Current EL, SP_EL0（不使用，跳到默认处理）
    .balign 0x80; b default_handler   // Sync
    .balign 0x80; b default_handler   // IRQ
    .balign 0x80; b default_handler   // FIQ
    .balign 0x80; b default_handler   // SError

// Current EL, SP_ELx（内核态 SVC 走这里）
    .balign 0x80; b sync_handler      // Sync  ← SVC from EL1
    .balign 0x80; b default_handler   // IRQ
    .balign 0x80; b default_handler   // FIQ
    .balign 0x80; b default_handler   // SError

// Lower EL, AArch64（用户态 EL0 SVC 走这里，后续切换 EL0 后使用）
    .balign 0x80; b sync_handler      // Sync  ← SVC from EL0
    .balign 0x80; b default_handler   // IRQ
    .balign 0x80; b default_handler   // FIQ
    .balign 0x80; b default_handler   // SError

// Lower EL, AArch32（不支持）
    .balign 0x80; b default_handler
    .balign 0x80; b default_handler
    .balign 0x80; b default_handler
    .balign 0x80; b default_handler

// ── 同步异常处理（SVC）────────────────────────────────────────────────────────
sync_handler:
    SAVE_ALL
    mov     x0, sp                    // 第一个参数：TrapContext 指针
    bl      trap_handler              // 调用 Rust 处理函数，返回值写入 x0
    // trap_handler 直接修改 TrapContext.x0，此处只需恢复上下文
    RESTORE_ALL
    eret

// ── 默认处理（未实现的异常：打印后停机）──────────────────────────────────────
default_handler:
    SAVE_ALL
    mov     x0, sp
    bl      default_trap_handler
    // 不返回
1:  b       1b
