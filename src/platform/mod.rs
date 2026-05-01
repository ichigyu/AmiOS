// ┌─────────────────────────────────────────────────────────────┐
// │  src/platform/mod.rs — 硬件平台 MMIO 地址常量               │
// │                                                             │
// │  职责：集中定义各平台的内存映射 I/O 地址，避免代码中出现     │
// │        魔法数字，并通过 Cargo feature 区分不同硬件平台       │
// │                                                             │
// │  支持平台：                                                  │
// │    qemu-virt     QEMU virt 虚拟机（默认，用于开发调试）      │
// │    phytium-d2000 飞腾 D2000 真实硬件（后续章节适配）         │
// └─────────────────────────────────────────────────────────────┘

// ── QEMU virt 平台地址定义 ────────────────────────────────────
// 地址来源：QEMU 源码 hw/arm/virt.c 中的 a15memmap[] 数组
#[cfg(feature = "qemu-virt")]
pub mod mmio {
    /// PL011 UART0 基地址
    /// QEMU virt 板第一个串口，用于内核调试输出
    pub const UART0_BASE: usize = 0x0900_0000;

    /// GIC（通用中断控制器）分发器基地址
    /// GICv2 架构，后续章节实现中断时使用
    pub const GIC_DIST_BASE: usize = 0x0800_0000;

    /// GIC CPU 接口基地址
    /// 每个 CPU 核心通过此地址与 GIC 交互
    pub const GIC_CPU_BASE: usize = 0x0801_0000;

    /// 物理内存（RAM）起始地址
    /// QEMU virt 板的 RAM 从此地址开始
    pub const RAM_BASE: usize = 0x4000_0000;

    /// 内核加载地址（_start 入口）
    /// 与链接脚本 linker.ld 中的起始地址保持一致
    pub const KERNEL_BASE: usize = 0x4008_0000;

    /// PL011 UART 参考时钟频率（Hz）
    /// QEMU virt 板固定为 24MHz（见 QEMU hw/arm/virt.c pl011_create）
    pub const UART_CLK_HZ: u32 = 24_000_000;
}

// ── 飞腾 D2000 平台地址定义 ───────────────────────────────────
// 地址来源：飞腾 D2000 处理器技术参考手册
// 注意：D2000 有多个 UART 控制器，UART1 通常作为调试串口
#[cfg(feature = "phytium-d2000")]
pub mod mmio {
    /// 飞腾 D2000 UART1 基地址（调试串口）
    /// D2000 使用 PL011 兼容 UART，寄存器布局与 QEMU virt 相同
    pub const UART0_BASE: usize = 0x2800_1000;

    /// 飞腾 D2000 物理内存起始地址
    pub const RAM_BASE: usize = 0x8000_0000;

    /// 飞腾 D2000 内核加载地址（待确认，参考 BSP 文档）
    pub const KERNEL_BASE: usize = 0x8008_0000;

    /// PL011 UART 参考时钟频率（Hz）
    /// 飞腾 D2000 UART 时钟为 48MHz（见飞腾 D2000 处理器技术参考手册）
    pub const UART_CLK_HZ: u32 = 48_000_000;
}
