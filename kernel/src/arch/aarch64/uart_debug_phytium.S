// ┌─────────────────────────────────────────────────────────────┐
// │  arch/aarch64/uart_debug_phytium.S — 飞腾 D2000 启动期 UART │
// │                                                             │
// │  职责：定义 uart_debug_init / uart_putc 宏，供 boot.S 使用  │
// │        在 Rust 运行时就绪之前通过直接写 MMIO 输出调试字符    │
// │                                                             │
// │  调用关系：                                                  │
// │    boot.rs（phytium-d2000 feature）                         │
// │      └─→ global_asm!(本文件, boot.S)                        │
// │            boot.S 中的 uart_debug_init / uart_putc 调用     │
// │            展开为本文件定义的真实实现                         │
// └─────────────────────────────────────────────────────────────┘

// uart_debug_init：将 D2000 PL011 UART1 基地址加载到 x20
// x20 作为 UART 基地址寄存器，后续所有 uart_putc 调用依赖它
.macro uart_debug_init
    ldr     x20, =0x28001000    // D2000 PL011 UART1 基地址（ttyAMA0）
.endm

// uart_putc：轮询 TXFF（bit5），等待发送 FIFO 有空间后写入字符
// 使用 x19/x18 作为临时寄存器，x20 须已由 uart_debug_init 初始化
// 用 \@ 生成每次展开唯一的标号，避免重复定义错误
.macro uart_putc c
    mov     w19, #\c
.Ltxwait_\@:
    ldr     w18, [x20, #0x18]   // 读取 UARTFR 寄存器（Flag Register）
    tbnz    w18, #5, .Ltxwait_\@ // bit5 = TXFF：发送 FIFO 满，继续等待
    str     w19, [x20, #0x00]   // 写入 UARTDR 寄存器（Data Register）
.endm
