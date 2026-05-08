//! 系统调用封装
//!
//! 通过 `svc #0` 指令发起系统调用，调用约定与 Linux AArch64 一致：
//! x8 = 调用号，x0-x2 = 参数，x0 = 返回值。

/// 系统调用号（与内核 syscall 表对应）
pub const SYS_WRITE: usize = 64;
pub const SYS_EXIT: usize = 93;
pub const SYS_SHUTDOWN: usize = 200;

/// 底层 syscall 封装：最多 3 个参数，返回 isize
///
/// AArch64 Linux syscall 约定：
///   x8 = syscall 号
///   x0-x5 = 参数
///   x0 = 返回值
#[inline(always)]
pub fn syscall(id: usize, args: [usize; 3]) -> isize {
    let ret: isize;
    // SAFETY: svc #0 是合法的系统调用指令，寄存器约定与内核 trap_handler 匹配
    unsafe {
        core::arch::asm!(
            "svc #0",
            inlateout("x0") args[0] => ret,
            in("x1") args[1],
            in("x2") args[2],
            in("x8") id,
            options(nostack),
        );
    }
    ret
}

/// 向文件描述符写入数据
///
/// fd=1 为标准输出，fd=2 为标准错误
pub fn sys_write(fd: usize, buf: &[u8]) -> isize {
    syscall(SYS_WRITE, [fd, buf.as_ptr() as usize, buf.len()])
}

/// 退出当前进程
pub fn sys_exit(exit_code: i32) -> ! {
    syscall(SYS_EXIT, [exit_code as usize, 0, 0]);
    unreachable!("sys_exit returned")
}

/// 关闭系统（自定义 syscall，内核通过 PSCI 实现）
pub fn sys_shutdown() -> ! {
    syscall(SYS_SHUTDOWN, [0, 0, 0]);
    unreachable!("sys_shutdown returned")
}
