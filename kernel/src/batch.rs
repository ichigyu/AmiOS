//! 批处理系统：用户程序加载与执行
//!
//! 将编译时嵌入内核的用户程序二进制复制到固定加载地址，然后跳转执行。
//! 用户程序链接到 `APP_BASE_ADDRESS`，内核加载时直接 memcpy 到此地址。

// 引入 build.rs 生成的应用列表（APP_NAMES, APP_BINARIES）
include!(concat!(env!("OUT_DIR"), "/app_list.rs"));

/// 用户程序加载地址（与 user/src/linker.ld 中的 BASE_ADDRESS 一致）
const APP_BASE_ADDRESS: usize = 0x40400000;

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
        use crate::println;
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

        // SAFETY: APP_BASE_ADDRESS 处已写入合法的用户程序二进制，入口为 _start
        let entry: extern "C" fn() -> ! = core::mem::transmute(APP_BASE_ADDRESS);
        entry()
    }

    pub fn app_count(&self) -> usize {
        APP_NAMES.len()
    }
}

pub static APP_MANAGER: AppManager = AppManager;
