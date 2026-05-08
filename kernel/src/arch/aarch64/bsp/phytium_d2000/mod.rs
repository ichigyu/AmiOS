//! 飞腾 D2000 板级常量
//!
//! 地址来源：飞腾 D2000 处理器技术参考手册。

pub mod mmio {
    /// 飞腾 D2000 UART1 基地址（调试串口 ttyAMA0）
    /// D2000 使用 PL011 兼容 UART，寄存器布局与 QEMU virt 相同
    pub const UART0_BASE: usize = 0x2800_1000;

    /// 飞腾 D2000 物理内存起始地址
    pub const RAM_BASE: usize = 0x8000_0000;

    /// 用户程序加载地址（与 user/src/linker.ld 中的 BASE_ADDRESS 一致）
    /// 用户空间位于内核之后
    pub const APP_BASE_ADDRESS: usize = 0x8010_0000;

    /// 内核加载地址，与链接脚本 linker.lds.S 保持一致
    /// 内核空间位于高地址
    pub const KERNEL_BASE: usize = 0x8008_0000;

    /// PL011 UART 参考时钟频率（Hz）
    /// 飞腾 D2000 UART 时钟为 48MHz（见飞腾 D2000 处理器技术参考手册）
    pub const UART_CLK_HZ: u32 = 48_000_000;
}

pub const BOARD_NAME: &str = "Phytium D2000";
