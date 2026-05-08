//! QEMU virt 板级常量
//!
//! 地址来源：QEMU 源码 `hw/arm/virt.c` 中的 `a15memmap[]` 数组。

pub mod mmio {
    /// PL011 UART0 基地址（QEMU virt 板第一个串口）
    pub const UART0_BASE: usize = 0x0900_0000;

    /// 物理内存（RAM）起始地址
    pub const RAM_BASE: usize = 0x4000_0000;

    /// 用户程序加载地址（与 user/src/linker.ld 中的 BASE_ADDRESS 一致）
    /// 用户空间位于内核之后
    pub const APP_BASE_ADDRESS: usize = 0x4010_0000;

    /// 内核加载地址，与链接脚本 linker.lds.S 保持一致
    /// 内核空间位于高地址
    pub const KERNEL_BASE: usize = 0x4008_0000;

    /// PL011 UART 参考时钟频率（Hz）
    /// QEMU virt 板固定为 24MHz（见 QEMU hw/arm/virt.c pl011_create）
    pub const UART_CLK_HZ: u32 = 24_000_000;
}

pub const BOARD_NAME: &str = "QEMU virt";
