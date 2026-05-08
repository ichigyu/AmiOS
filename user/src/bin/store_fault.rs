#![no_std]
#![no_main]

#[macro_use]
extern crate amios_user;

#[no_mangle]
fn main() -> i32 {
    println!("[store_fault] 即将向非法地址写入，触发 Store Fault...");
    // SAFETY: 故意向地址 0 写入以触发内核 Store Fault 异常处理，测试用途
    unsafe {
        let ptr = 0x0 as *mut u8;
        ptr.write_volatile(0xde);
    }
    // 不应到达此处
    println!("[store_fault] 错误：内核未捕获异常");
    1
}
