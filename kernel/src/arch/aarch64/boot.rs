// ┌─────────────────────────────────────────────────────────────┐
// │  arch/aarch64/boot.rs — 引入汇编启动文件                    │
// │                                                             │
// │  职责：通过 global_asm! 将平台 UART 宏文件和 boot.S 嵌入    │
// │        编译单元，汇编逻辑全部在对应 .S 文件中               │
// │                                                             │
// │  平台选择：                                                  │
// │    phytium-d2000 feature → uart_debug_phytium.S（真实实现） │
// │    其他（qemu-virt）     → uart_debug_qemu.S（空实现）      │
// │    宏文件必须与 boot.S 在同一 global_asm! 调用中，           │
// │    否则宏定义跨 translation unit 不可见                      │
// └─────────────────────────────────────────────────────────────┘

use core::arch::global_asm;

#[cfg(feature = "phytium-d2000")]
global_asm!(
    include_str!("uart_debug_phytium.S"),
    include_str!("boot.S")
);

#[cfg(not(feature = "phytium-d2000"))]
global_asm!(
    include_str!("uart_debug_qemu.S"),
    include_str!("boot.S")
);
