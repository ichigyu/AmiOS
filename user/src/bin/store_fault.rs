#![no_std]
#![no_main]

#[macro_use]
extern crate amios_user;

#[no_mangle]
fn main() -> i32 {
    println!("[store_fault] attempting to write to illegal address, triggering Store Fault...");
    // SAFETY: intentionally write to address 0 to trigger kernel Store Fault exception, for testing
    unsafe {
        let ptr = 0x0 as *mut u8;
        ptr.write_volatile(0xde);
    }
    // should not reach here
    println!("[store_fault] error: kernel did not catch exception");
    1
}
