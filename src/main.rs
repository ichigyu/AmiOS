// ┌─────────────────────────────────────────────────────────────┐
// │  src/main.rs — 内核主入口与基础运行时                        │
// │                                                             │
// │  职责：提供 no_std 裸机运行时基础设施，包括：               │
// │    - panic handler（崩溃处理）                              │
// │    - 全局分配器占位（当前不支持堆分配）                      │
// │    - kernel_main（Rust 层内核入口）                          │
// │    - print! / println! 宏（格式化串口输出）                  │
// │                                                             │
// │  调用关系：                                                  │
// │    boot.rs (_start)                                         │
// │      └─→ kernel_main()          Rust 入口                   │
// │            ├─→ uart::init()     初始化串口                   │
// │            └─→ println!(...)    输出启动信息                 │
// └─────────────────────────────────────────────────────────────┘

// 裸机环境：不链接标准库（std），使用 core 库替代
#![no_std]
// 不使用 Rust 默认的 main 入口，由链接脚本和汇编指定入口 _start
#![no_main]

// 引入启动代码模块（包含 global_asm! 的汇编启动代码）
mod boot;
// 引入平台 MMIO 地址常量模块
mod platform;
// 引入 PL011 UART 驱动模块
mod uart;

use core::fmt::Write;

// ── print! / println! 宏 ──────────────────────────────────────
// 这两个宏是内核调试输出的主要接口，底层调用 UART 驱动
// 接口与标准库的 print!/println! 完全兼容

/// 格式化输出到串口，不换行
/// 用法：print!("x = {}", x)
#[macro_export]
macro_rules! print {
    ($($arg:tt)*) => {
        // 创建临时 Uart 写入器，调用 write_fmt 完成格式化
        $crate::uart::Uart.write_fmt(format_args!($($arg)*)).unwrap()
    };
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

// ── Panic Handler ─────────────────────────────────────────────
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
    // 使用 wfe（Wait For Event）降低功耗，但保持 CPU 停止状态
    loop {
        // aarch64 的低功耗等待指令，避免空转浪费功耗
        core::hint::spin_loop();
    }
}

// ── 全局分配器占位 ────────────────────────────────────────────
// 当前阶段不支持堆内存分配（Box、Vec 等）
// 此占位实现会在调用时触发 panic，给出明确的错误提示
// 后续章节（内存管理）将替换为真实的堆分配器

use core::alloc::{GlobalAlloc, Layout};

/// 占位全局分配器：当前阶段不支持堆分配
struct NoHeapAllocator;

// SAFETY: 此分配器的 alloc 和 dealloc 都会 panic，
// 不会真正分配内存，因此实现是安全的（虽然无用）
unsafe impl GlobalAlloc for NoHeapAllocator {
    unsafe fn alloc(&self, _layout: Layout) -> *mut u8 {
        // 堆分配被调用时触发 panic，提示开发者当前阶段不支持
        // 后续章节实现内存管理后，此处将替换为真实分配逻辑
        panic!("堆内存分配尚未实现（后续章节将添加内存管理）")
    }

    unsafe fn dealloc(&self, _ptr: *mut u8, _layout: Layout) {
        // 同上，释放操作也不支持
        panic!("堆内存释放尚未实现（后续章节将添加内存管理）")
    }
}

/// 注册全局分配器
/// 只要不调用 Box::new / Vec::new 等堆分配操作，此占位不会触发
#[global_allocator]
static ALLOCATOR: NoHeapAllocator = NoHeapAllocator;

// ── 内核主函数 ────────────────────────────────────────────────

/// 内核 Rust 层入口函数
///
/// 由汇编启动代码（src/boot.rs 中的 _start）在完成以下工作后调用：
///   1. EL2 → EL1 异常级别切换
///   2. 栈指针初始化
///   3. BSS 段清零
///
/// 此函数标注为 `-> !`（发散函数），永不返回
#[no_mangle]
pub extern "C" fn kernel_main() -> ! {
    // 初始化 PL011 UART 串口，之后才能使用 print!/println!
    uart::init();

    // 输出启动横幅，确认内核成功进入 Rust 执行环境
    println!("================================================");
    println!("  AmiOS — ARMv8 操作系统内核");
    println!("  架构：AArch64 (ARMv8-A)");
    println!("  平台：QEMU virt");
    println!("  参考：rCore-Tutorial (RISC-V → ARMv8 移植)");
    println!("================================================");
    println!("内核启动成功，进入主循环...");

    // 主循环：当前阶段内核没有任务可做，进入低功耗等待
    // 后续章节将在此处添加：进程调度、系统调用处理等
    loop {
        // 等待中断或事件（后续章节开启中断后此处会被唤醒）
        core::hint::spin_loop();
    }
}
