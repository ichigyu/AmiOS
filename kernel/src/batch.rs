//! 批处理系统：用户程序加载与执行
//!
//! 将编译时嵌入内核的用户程序二进制复制到固定加载地址，然后跳转执行。
//! 用户程序链接到 `APP_BASE_ADDRESS`，内核加载时直接 memcpy 到此地址。

use crate::println;

// 引入 build.rs 生成的应用列表（APP_NAMES, APP_BINARIES）
include!(concat!(env!("OUT_DIR"), "/app_list.rs"));

/// 用户程序加载地址（与 user/src/linker.ld 中的 BASE_ADDRESS 一致）
/// 从 BSP 获取平台特定的应用基地址
const APP_BASE_ADDRESS: usize = crate::bsp::mmio::APP_BASE_ADDRESS;

pub struct AppManager;

impl AppManager {
    /// 打印所有内嵌应用的名称和大小
    pub fn list_apps(&self) {
        use crate::println;
        println!("[batch] {} app(s) embedded:", APP_NAMES.len());
        for (i, name) in APP_NAMES.iter().enumerate() {
            println!("  [{}] {} ({} bytes)", i, name, APP_BINARIES[i].len());
        }
    }

    /// 将第 `index` 个应用加载到 APP_BASE_ADDRESS 并跳转执行
    ///
    /// # Safety
    /// 调用者必须确保：
    /// - `index` 在有效范围内
    /// - APP_BASE_ADDRESS 处的内存可写且足够大
    /// - 跳转后内核栈不会被用户程序破坏（后续需要隔离）
    pub unsafe fn load_and_run(&self, index: usize) -> ! {
        assert!(index < APP_NAMES.len(), "app index out of range");

        let bin = APP_BINARIES[index];
        let dst = APP_BASE_ADDRESS as *mut u8;

        println!(
            "[batch] loading '{}' ({} bytes) -> {:#x}",
            APP_NAMES[index],
            bin.len(),
            APP_BASE_ADDRESS
        );

        // SAFETY: bin 来自 include_bytes!，指针有效；dst 指向已知可写的 RAM 区域
        core::ptr::copy_nonoverlapping(bin.as_ptr(), dst, bin.len());
        println!("[batch] app binary copied to memory");

        // 验证应用二进制是否正确加载
        let loaded_bin = unsafe { core::slice::from_raw_parts(dst, bin.len()) };
        if loaded_bin == bin {
            println!("[batch] app binary verification: OK");
        } else {
            println!("[batch] app binary verification: FAILED!");
            println!("[batch] first 16 bytes of source: {:02x?}", &bin[..16.min(bin.len())]);
            println!("[batch] first 16 bytes of loaded: {:02x?}", &loaded_bin[..16.min(loaded_bin.len())]);
        }

        // 清除缓存以确保指令一致性
        // 在某些平台（如 Phytium D2000）上，加载应用后需要清除缓存
        // 否则 I-cache 可能包含旧数据，导致执行错误的指令
        println!("[batch] flushing caches for range {:#x}-{:#x}", APP_BASE_ADDRESS, APP_BASE_ADDRESS + bin.len());
        Self::flush_cache(APP_BASE_ADDRESS, bin.len());
        println!("[batch] cache flush complete");

        // 为应用分配栈空间：在应用代码之后 1MB 处
        let app_stack_top = APP_BASE_ADDRESS + 0x10_0000;
        println!("[batch] app stack top: {:#x}", app_stack_top);

        println!("[batch] jumping to app entry at {:#x}", APP_BASE_ADDRESS);
        println!("[batch] app stack range: {:#x} - {:#x}", APP_BASE_ADDRESS + 0x10_0000 - 0x10000, APP_BASE_ADDRESS + 0x10_0000);

        // SAFETY: APP_BASE_ADDRESS 处已写入合法的用户程序二进制，入口为 _start
        // 使用内联汇编设置 sp 并跳转到应用入口
        core::arch::asm!(
            "mov sp, {stack_top}",
            "br {entry}",
            stack_top = in(reg) app_stack_top,
            entry = in(reg) APP_BASE_ADDRESS,
            options(noreturn)
        );
    }

    /// 清除指定范围的缓存
    /// 确保 D-cache 和 I-cache 一致
    unsafe fn flush_cache(addr: usize, size: usize) {
        // 获取缓存行大小（通常是 64 字节）
        let cache_line_size = 64usize;

        // 清除 D-cache
        let mut current = addr;
        let end = addr + size;
        let mut count = 0usize;
        while current < end {
            core::arch::asm!("dc cvau, {}", in(reg) current);
            current += cache_line_size;
            count += 1;
        }
        println!("[batch] D-cache: cleared {} lines", count);

        // 数据同步屏障
        core::arch::asm!("dsb sy");

        // 清除 I-cache
        current = addr;
        count = 0;
        while current < end {
            core::arch::asm!("ic ivau, {}", in(reg) current);
            current += cache_line_size;
            count += 1;
        }
        println!("[batch] I-cache: cleared {} lines", count);

        // 指令同步屏障
        core::arch::asm!("dsb sy");
        core::arch::asm!("isb");
    }

    pub fn app_count(&self) -> usize {
        APP_NAMES.len()
    }
}

pub static APP_MANAGER: AppManager = AppManager;
