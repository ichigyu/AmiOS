//! UART 驱动模块入口
//!
//! 职责：聚合 PL011 UART 实现，对外暴露统一的驱动接口。
//!
//! 调用关系：
//! - `kernel::kernel_main` → `init()` 初始化串口
//! - `kernel::io`（`print!`/`println!`）→ `Uart`（`fmt::Write` 写入器）

mod pl011;

pub use pl011::init;
pub use pl011::putchar;
pub use pl011::Uart;
