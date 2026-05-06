// ┌─────────────────────────────────────────────────────────────┐
// │  arch/aarch64/bsp/mod.rs — AArch64 板级支持包入口           │
// │                                                             │
// │  职责：根据 Cargo feature 选择对应的板级子模块，             │
// │        并将其内容重新导出为统一的 crate::bsp 路径            │
// │                                                             │
// │  子模块：                                                    │
// │    qemu/          QEMU virt 虚拟机（默认，用于开发调试）     │
// │    phytium_d2000/ 飞腾 D2000 真实硬件                       │
// └─────────────────────────────────────────────────────────────┘

#[cfg(feature = "qemu-virt")]
mod qemu;
#[cfg(feature = "qemu-virt")]
pub use qemu::*;

#[cfg(feature = "phytium-d2000")]
mod phytium_d2000;
#[cfg(feature = "phytium-d2000")]
pub use phytium_d2000::*;
