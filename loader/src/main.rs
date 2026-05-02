// ┌─────────────────────────────────────────────────────────────────────┐
// │  loader/src/main.rs — AmiOS UEFI 加载器                              │
// │                                                                      │
// │  职责：在 UEFI 环境中将裸机内核二进制加载到目标物理地址并跳转执行       │
// │                                                                      │
// │  调用关系：                                                           │
// │    UEFI 固件                                                          │
// │      └─→ efi_main()              UEFI 入口                           │
// │            └─→ get_image_file_system()  获取加载器所在文件系统        │
// │            └─→ open_volume()     打开 FAT 根目录                      │
// │            └─→ dir.open()        打开内核二进制文件                   │
// │            └─→ file.get_info()   读取文件大小                         │
// │            └─→ allocate_pages()  在目标地址分配物理内存               │
// │            └─→ file.read()       读取内核到目标地址                   │
// │            └─→ exit_boot_services()  退出 UEFI Boot Services         │
// │            └─→ jump_to_kernel()  跳转到 0x80080000 执行内核           │
// └─────────────────────────────────────────────────────────────────────┘

#![no_main]
#![no_std]

use uefi::boot::{self, AllocateType, MemoryType};
use uefi::prelude::*;
use uefi::proto::media::file::{File, FileAttribute, FileInfo, FileMode};
use uefi::{cstr16, helpers, CStr16};

// 内核加载地址：与 D2000 平台链接脚本中的 KERNEL_BASE 一致
const KERNEL_LOAD_ADDR: u64 = 0x80080000;

// 内核文件名：与 Makefile 中 KERNEL_BIN_NAME 一致
const KERNEL_FILE_NAME: &CStr16 = cstr16!("amios-kernel-d2000.bin");

// FileInfo 结构体最大尺寸：固定文件名部分 + 最长文件名（255 个 UCS-2 字符 + null）
// FileInfo 固定部分约 80 字节，文件名最多 256 * 2 = 512 字节
const FILE_INFO_BUF_SIZE: usize = 600;

// UEFI 环境下的 panic handler：通过 uefi::println! 输出错误信息后停机
// Boot Services 退出前 uefi::println! 可用；退出后无法输出，只能死循环
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    uefi::println!("[LOADER PANIC] {}", info);
    loop {}
}

#[entry]
fn efi_main() -> Status {
    // 初始化 uefi crate 内部状态（日志等，若启用相关 feature）
    helpers::init().expect("helpers::init failed");
    uefi::println!("[loader] step 1/6: helpers init ok");

    // 获取加载器所在设备的 SimpleFileSystem 协议句柄
    // get_image_file_system 内部通过 LoadedImage 协议找到加载器所在分区
    let image = boot::image_handle();
    let mut fs = boot::get_image_file_system(image).expect("Failed to get image file system");
    uefi::println!("[loader] step 2/6: got image file system");

    // 打开 FAT 分区根目录
    let mut root = fs.open_volume().expect("Failed to open root volume");
    uefi::println!("[loader] step 3/6: opened root volume");

    // 打开内核二进制文件（只读模式）
    let kernel_handle = root
        .open(KERNEL_FILE_NAME, FileMode::Read, FileAttribute::empty())
        .expect("Failed to open kernel file: amios-kernel-d2000.bin not found");

    // 将文件句柄转换为 RegularFile 类型以支持读操作
    let mut kernel_file = match kernel_handle.into_type().expect("into_type failed") {
        uefi::proto::media::file::FileType::Regular(f) => f,
        uefi::proto::media::file::FileType::Dir(_) => {
            panic!("amios-kernel-d2000.bin is a directory, not a file")
        }
    };

    // 读取文件元信息以获取文件大小
    // get_info 使用栈上缓冲区，避免堆分配依赖
    let mut info_buf = [0u8; FILE_INFO_BUF_SIZE];
    let file_info: &FileInfo = kernel_file
        .get_info::<FileInfo>(&mut info_buf)
        .expect("Failed to get kernel file info");
    let kernel_size = file_info.file_size() as usize;
    uefi::println!("[loader] step 4/6: kernel file size = {} bytes", kernel_size);

    // 计算需要的内存页数（UEFI 页大小为 4096 字节，向上取整）
    let page_count = (kernel_size + 0xFFF) / 0x1000;

    // 在目标物理地址 0x80080000 分配连续物理内存页
    // AllocateType::Address 要求固件在指定地址分配，与链接脚本加载地址一致
    // MemoryType::LOADER_DATA 是 UEFI 规范推荐的 OS 加载器数据类型
    let kernel_dest = boot::allocate_pages(
        AllocateType::Address(KERNEL_LOAD_ADDR),
        MemoryType::LOADER_DATA,
        page_count,
    )
    .expect("Failed to allocate pages at 0x80080000");
    uefi::println!("[loader] step 5/6: allocated {} pages at {:p}", page_count, kernel_dest.as_ptr());

    // 将内核文件内容直接读入目标物理地址
    // 避免二次复制：直接读到最终执行地址，减少内存占用
    let kernel_slice =
        unsafe { core::slice::from_raw_parts_mut(kernel_dest.as_ptr(), kernel_size) };
    let bytes_read = kernel_file.read(kernel_slice).expect("Failed to read kernel file");

    // 验证读取字节数与文件大小一致
    assert_eq!(bytes_read, kernel_size, "Kernel read size mismatch");
    uefi::println!("[loader] step 6/6: kernel loaded ({} bytes), jumping to 0x{:x}...", bytes_read, KERNEL_LOAD_ADDR);

    // 退出 UEFI Boot Services：此后不能再调用任何 Boot Services 函数
    // exit_boot_services 内部处理内存映射 key 失效重试，调用后 UEFI 运行时不再可用
    // 返回的 MemoryMapOwned 被丢弃：内核自行管理内存，不需要 UEFI 内存映射
    unsafe { let _ = boot::exit_boot_services(MemoryType::LOADER_DATA); };

    // 跳转到内核入口地址执行
    // 内核入口约定：无参数、无返回（裸机入口 _start）
    // transmute 将整数地址转换为函数指针，属于 unsafe 操作
    unsafe {
        let entry: extern "C" fn() -> ! = core::mem::transmute(KERNEL_LOAD_ADDR as usize);
        entry();
    }
}
