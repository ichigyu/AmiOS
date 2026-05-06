//! AArch64 汇编启动文件嵌入
//!
//! 职责：通过 `global_asm!` 将 `boot.S` 嵌入编译单元。

use core::arch::global_asm;

global_asm!(include_str!("boot.S"));
