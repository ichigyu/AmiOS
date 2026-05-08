//! 语言运行时支持
//!
//! 提供裸机环境所需的 `#[panic_handler]`。
use core::panic::PanicInfo;
use crate::println;
use crate::syscall::sys_exit;

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    if let Some(loc) = info.location() {
        println!(
            "[user panic] at {}:{}: {}",
            loc.file(),
            loc.line(),
            info.message()
        );
    } else {
        println!("[user panic]: {}", info.message());
    }
    sys_exit(1);
    loop {}
}
