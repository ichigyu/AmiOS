//! 内核核心基础设施
//!
//! 职责：提供内核运行时基础设施，包括 panic handler 和 `kernel_main` 入口。
//!
//! 调用关系：
//! - `arch/aarch64/boot.S`（`_start`）→ `kernel_main()` → `drivers::uart::init()`

mod console;

// #[macro_export] 宏在子模块中不自动可见，必须显式 use；
// rustc 对宏的 use 会误报 unused_imports，故需 allow
#[allow(unused_imports)]
use crate::{print, println};
use crate::bsp::BOARD_NAME;
use crate::psci;

/// 内核 panic 处理函数
///
/// 输出 panic 位置（文件名:行号）和错误消息，然后通过 PSCI 关机。
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    print!("\n\n[KERNEL PANIC]");

    if let Some(location) = info.location() {
        print!(" at {}:{}", location.file(), location.line());
    }

    print!("\n{}\n", info.message());

    psci::system_off()
}

/// # Safety
///
/// 调用者必须确保链接脚本正确导出了 `_start_bss` 和 `_end_bss`，
/// 且在任何静态变量被访问之前调用此函数。
unsafe fn clear_bss() {
    extern "C" {
        static mut _start_bss: u64;
        static _end_bss: u64;
    }
    let start = core::ptr::addr_of_mut!(_start_bss) as *mut u8;
    let end = core::ptr::addr_of!(_end_bss) as *const u8;
    let len = end as usize - start as usize;
    core::ptr::write_bytes(start, 0, len);
}

/// 内核 Rust 层入口函数
///
/// 由汇编启动代码（arch/aarch64/boot.S 中的 _start）在完成以下工作后调用：
///   1. EL 检测与系统寄存器初始化
///   2. 栈指针初始化
///
/// 此函数标注为 `-> !`（发散函数），永不返回
#[no_mangle]
pub extern "C" fn kernel_main() -> ! {
    // BSS 段清零必须在任何静态变量使用之前完成
    unsafe { clear_bss() }

    crate::drivers::uart::init();
    crate::arch::aarch64::trap::init();

    println!("================================================");
    println!("  AmiOS -- ARMv8 OS Kernel");
    println!("  Arch:    AArch64 (ARMv8-A)");
    println!("  Board:   {}", BOARD_NAME);
    println!("================================================");
    println!("Kernel booted successfully.");

    let mgr = &crate::batch::APP_MANAGER;
    mgr.list_apps();
    unsafe { mgr.load_and_run(0) }
}