// ┌─────────────────────────────────────────────────────────────┐
// │  kernel/io.rs — 内核格式化输出宏                            │
// │                                                             │
// │  职责：提供 print!/println! 宏，封装 UART 格式化输出         │
// │        宏通过 #[macro_export] 导出到 crate 根，              │
// │        所有子模块可直接使用，无需显式路径                    │
// │                                                             │
// │  调用关系：                                                  │
// │    任意模块                                                  │
// │      └─→ print! / println!                                  │
// │            └─→ drivers::uart::Uart (fmt::Write)             │
// │                  └─→ drivers::uart::putchar()               │
// └─────────────────────────────────────────────────────────────┘

/// 格式化输出到串口，不换行
/// 用法：print!("x = {}", x)
#[macro_export]
macro_rules! print {
    ($($arg:tt)*) => {{
        // Write trait 必须在作用域内，write_fmt 才能被调用
        use core::fmt::Write as _;
        $crate::drivers::uart::Uart.write_fmt(format_args!($($arg)*)).unwrap()
    }};
}

/// 格式化输出到串口，末尾自动添加换行
/// 用法：println!("Hello, {}!", name)
#[macro_export]
macro_rules! println {
    () => ($crate::print!("\n"));
    ($($arg:tt)*) => {
        $crate::print!("{}\n", format_args!($($arg)*))
    };
}

