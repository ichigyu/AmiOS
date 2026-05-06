// ┌─────────────────────────────────────────────────────────────┐
// │  arch/aarch64/uart_debug_qemu.S — QEMU virt 启动期 UART     │
// │                                                             │
// │  职责：定义 uart_debug_init / uart_putc 宏的空实现           │
// │        QEMU virt 启动阶段不需要汇编级 UART 调试探针          │
// │        （Rust 运行时就绪后直接使用 0x09000000 的 PL011）     │
// │                                                             │
// │  调用关系：                                                  │
// │    boot.rs（qemu-virt feature，即非 phytium-d2000）          │
// │      └─→ global_asm!(本文件, boot.S)                        │
// │            boot.S 中的 uart_debug_init / uart_putc 调用     │
// │            展开为空（零开销）                                 │
// └─────────────────────────────────────────────────────────────┘

// 空实现：boot.S 中的调用点展开为零指令
.macro uart_debug_init
.endm

.macro uart_putc c
.endm
