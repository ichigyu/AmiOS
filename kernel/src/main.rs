//! 内核 crate 根
//!
//! 职责：声明 no_std 裸机环境、聚合子模块。具体逻辑分散在各子模块中，此文件只做顶层声明。
//!
//! 模块结构：
//! - `arch/`：架构相关（启动汇编、异常向量等）
//!   - `aarch64/bsp/`：板级支持包（MMIO 地址常量等）
//! - `drivers/`：硬件驱动（UART、GIC 等）
//! - `kernel/`：内核核心（panic、入口）

// 裸机环境：不链接标准库（std），使用 core 库替代
#![no_std]
// 不使用 Rust 默认的 main 入口，由链接脚本和汇编指定入口 _start
#![no_main]
#![deny(warnings)]

// 架构相关代码（启动汇编、板级支持包均在 arch/ 下）
mod arch;
// 将 arch::aarch64::bsp 重新导出为 crate 级别的 bsp，
// 使 drivers 和 kernel 子模块可以用 crate::bsp 访问板级常量
#[cfg(target_arch = "aarch64")]
pub use arch::aarch64::bsp;
#[cfg(target_arch = "aarch64")]
pub use arch::aarch64::psci;
// 硬件驱动层
pub mod drivers;
// 系统调用分发
pub mod syscall;
// 用户程序批处理加载器
pub mod batch;
// 内核核心基础设施（panic handler、kernel_main、print! 宏）
mod kernel;
