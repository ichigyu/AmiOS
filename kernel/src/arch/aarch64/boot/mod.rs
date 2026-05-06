//! AArch64 启动模块入口
//!
//! 职责：通过 `mod boot` 引入 `boot.rs`，触发 `global_asm!` 将 `boot.S` 嵌入编译单元。

mod boot;
