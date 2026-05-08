#![no_std]
#![no_main]

#[macro_use]
extern crate amios_user;

use amios_user::sys_shutdown;

#[no_mangle]
fn main() -> i32 {
    println!("[power_off] shutting down...");
    sys_shutdown();
}
