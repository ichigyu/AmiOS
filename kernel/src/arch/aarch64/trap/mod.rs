//! AArch64 异常/陷阱处理
//!
//! 职责：
//! - 设置 VBAR_EL1 指向异常向量表
//! - 定义 TrapContext（保存的寄存器布局，与 trap.S 中的 SAVE_ALL 宏对应）
//! - 提供 trap_handler 和 default_trap_handler 供汇编调用

use core::arch::global_asm;

global_asm!(include_str!("trap.S"));

extern "C" {
    fn exception_vector_table();
}

/// 初始化异常向量表：将 VBAR_EL1 指向 exception_vector_table
pub fn init() {
    // SAFETY: exception_vector_table 是 2KB 对齐的合法向量表地址
    unsafe {
        core::arch::asm!(
            "msr vbar_el1, {vbar}",
            "isb",
            vbar = in(reg) exception_vector_table as *const () as usize,
        );
    }
}

/// 陷阱上下文：与 trap.S 中 SAVE_ALL/RESTORE_ALL 的栈布局严格对应
///
/// 布局（从低地址到高地址，每项 8 字节）：
///   [0..30]  x0-x29
///   [30]     x30 (lr)
///   [31]     sp（异常前）
///   [32]     elr_el1（异常返回地址，即 svc 后的下一条指令）
///   [33]     spsr_el1
#[repr(C)]
pub struct TrapContext {
    pub x: [usize; 31],  // x0-x30
    pub sp: usize,
    pub elr: usize,
    pub spsr: usize,
}

/// 同步异常处理入口（由 trap.S 的 sync_handler 调用）
///
/// 判断异常类型：ESR_EL1.EC == 0x15 表示 SVC（AArch64）
#[no_mangle]
pub extern "C" fn trap_handler(ctx: &mut TrapContext) {
    let esr: u64;
    // SAFETY: ESR_EL1 是只读系统寄存器，读取无副作用
    unsafe {
        core::arch::asm!("mrs {}, esr_el1", out(reg) esr);
    }
    let ec = (esr >> 26) & 0x3f;

    match ec {
        0x15 => {
            // SVC（AArch64）：x8 = syscall 号，x0-x2 = 参数，返回值写回 x0
            let ret = crate::syscall::syscall(
                ctx.x[8],
                [ctx.x[0], ctx.x[1], ctx.x[2]],
            );
            ctx.x[0] = ret as usize;
        }
        _ => {
            use crate::println;
            println!("[trap] unhandled sync exception: EC={:#x} ESR={:#x}", ec, esr);
            crate::psci::system_off();
        }
    }
}

/// 未实现异常的默认处理（由 trap.S 的 default_handler 调用）
#[no_mangle]
pub extern "C" fn default_trap_handler(ctx: &TrapContext) -> ! {
    use crate::println;
    let esr: u64;
    let far: u64;
    // SAFETY: ESR_EL1、FAR_EL1 是只读系统寄存器，读取无副作用
    unsafe {
        core::arch::asm!("mrs {}, esr_el1", out(reg) esr);
        core::arch::asm!("mrs {}, far_el1", out(reg) far);
    }
    println!("[trap] unhandled exception");
    println!("  ESR_EL1 = {:#018x}  EC={:#x}", esr, (esr >> 26) & 0x3f);
    println!("  FAR_EL1 = {:#018x}", far);
    println!("  ELR     = {:#018x}", ctx.elr);
    println!("  SPSR    = {:#018x}", ctx.spsr);
    crate::psci::system_off()
}
