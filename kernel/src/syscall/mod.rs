//! 系统调用分发
//!
//! 用户程序通过 `svc #0` 触发异常，trap_handler 读取 x8（syscall 号）后调用此模块。
//! 调用约定与 Linux AArch64 一致：x8=号，x0-x2=参数，x0=返回值。

const SYS_WRITE: usize = 64;
const SYS_EXIT: usize = 93;
const SYS_SHUTDOWN: usize = 200;

/// 系统调用分发入口
pub fn syscall(id: usize, args: [usize; 3]) -> isize {
    match id {
        SYS_WRITE    => sys_write(args[0], args[1] as *const u8, args[2]),
        SYS_EXIT     => sys_exit(args[0] as i32),
        SYS_SHUTDOWN => sys_shutdown(),
        _ => {
            use crate::println;
            println!("[syscall] unknown syscall id={}", id);
            -1
        }
    }
}

/// 向文件描述符写入数据（fd=1 标准输出，fd=2 标准错误，均输出到 UART）
fn sys_write(fd: usize, buf: *const u8, len: usize) -> isize {
    if fd != 1 && fd != 2 {
        return -1;
    }
    // SAFETY: 用户程序传入的指针，当前阶段无 MMU 隔离，直接信任其有效性
    let s = unsafe { core::slice::from_raw_parts(buf, len) };
    if let Ok(s) = core::str::from_utf8(s) {
        use crate::print;
        print!("{}", s);
        len as isize
    } else {
        -1
    }
}

/// 进程退出：当前阶段直接关机（批处理系统只有一个应用）
fn sys_exit(exit_code: i32) -> ! {
    use crate::println;
    println!("[syscall] sys_exit({})", exit_code);
    crate::psci::system_off()
}

/// 系统关机
fn sys_shutdown() -> ! {
    use crate::println;
    println!("[syscall] sys_shutdown");
    crate::psci::system_off()
}
