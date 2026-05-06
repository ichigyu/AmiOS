//! 内核核心基础设施
//!
//! 职责：提供内核运行时基础设施，包括 panic handler 和 `kernel_main` 入口。
//!
//! 调用关系：
//! - `arch/aarch64/boot.S`（`_start`）→ `kernel_main()` → `drivers::uart::init()`

mod io;

// #[macro_export] 宏在子模块中不自动可见，必须显式 use；
// rustc 对宏的 use 会误报 unused_imports，故需 allow
#[allow(unused_imports)]
use crate::{print, println};
use crate::bsp::BOARD_NAME;
// 当代码触发 panic（如数组越界、unwrap None 等）时，此函数被调用
// 裸机环境无法展开栈，只能输出错误信息后停机

/// 内核 panic 处理函数
/// 输出 panic 位置（文件名:行号）和错误消息，然后进入无限循环
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    // 输出 panic 标题，醒目提示内核崩溃
    print!("\n\n[KERNEL PANIC]");

    // 输出 panic 发生的源码位置（文件名和行号）
    if let Some(location) = info.location() {
        print!(" at {}:{}", location.file(), location.line());
    }

    // 输出 panic 消息（如 panic!("msg") 中的字符串）
    print!("\n{}\n", info.message());

    // 进入无限循环，停止 CPU 执行
    loop {
        // aarch64 的低功耗等待指令，避免空转浪费功耗
        core::hint::spin_loop();
    }
}

// ── Panic Handler ─────────────────────────────────────────────

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

    // 初始化 PL011 UART 串口，之后才能使用 print!/println!
    crate::drivers::uart::init();

    // 输出启动横幅，确认内核成功进入 Rust 执行环境
    println!("================================================");
    println!("  AmiOS -- ARMv8 OS Kernel");
    println!("  Arch:    AArch64 (ARMv8-A)");
    println!("  Board:   {}", BOARD_NAME);
    println!("================================================");
    println!("Kernel booted successfully. Entering main loop...");

    // 主循环：当前阶段内核没有任务可做，进入低功耗等待
    // 后续章节将在此处添加：进程调度、系统调用处理等
    loop {
        core::hint::spin_loop();
    }
}
