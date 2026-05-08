//! AArch64 架构模块入口
//!
//! 职责：聚合 AArch64 架构相关子模块，并将板级支持包重新导出为 crate 级别的 `bsp` 路径。
//!
//! 子模块：
//! - `boot`：汇编启动代码（EL 检测、栈初始化、跳转入口）
//! - `bsp`：板级支持包（MMIO 地址常量、板名等）

mod boot;
pub mod bsp;
pub mod psci;
pub mod trap;
