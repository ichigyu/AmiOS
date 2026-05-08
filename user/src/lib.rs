//! 用户态运行时库
//!
//! 提供系统调用封装、控制台输出宏和 panic handler，供各用户程序 `extern crate` 引入。
#![no_std]
#![no_main]

pub mod console;
pub mod lang_items;
pub mod syscall;

use core::arch::global_asm;

global_asm!(include_str!("entry.S"));

pub use syscall::{sys_exit, sys_shutdown, sys_write};
