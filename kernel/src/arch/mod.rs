//! 架构抽象层入口
//!
//! 职责：通过条件编译选择目标架构的实现模块，为未来支持多架构（x86_64、RISC-V 等）预留扩展点。

// 当前仅支持 AArch64，通过 cfg 隔离架构相关代码
#[cfg(target_arch = "aarch64")]
pub mod aarch64;
