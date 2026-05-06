//! PSCI（Power State Coordination Interface）
//!
//! ARM 标准固件电源管理接口，等价于 RISC-V 的 SBI system_reset 扩展。
//! 规范：ARM DEN0022D（https://developer.arm.com/documentation/den0022）
//!
//! 调用约定：
//! - QEMU virt：内核运行在 EL1，通过 HVC 陷入 EL2 hypervisor（QEMU 内置 PSCI）
//! - 飞腾 D2000：内核运行在 EL1/EL2，通过 SMC 陷入 EL3 ATF

// PSCI 函数 ID（32-bit 调用约定，SMC32/HVC32）
const PSCI_SYSTEM_OFF: u64 = 0x8400_0008;
const PSCI_SYSTEM_RESET: u64 = 0x8400_0009;

/// 通过 HVC 调用 PSCI（QEMU virt：EL1 → EL2）
#[cfg(feature = "qemu-virt")]
#[inline]
unsafe fn psci_call(func_id: u64) {
    core::arch::asm!(
        "hvc #0",
        in("x0") func_id,
        options(nostack, nomem)
    );
}

/// 通过 SMC 调用 PSCI（飞腾 D2000：EL1/EL2 → EL3 ATF）
#[cfg(feature = "phytium-d2000")]
#[inline]
unsafe fn psci_call(func_id: u64) {
    core::arch::asm!(
        "smc #0",
        in("x0") func_id,
        options(nostack, nomem)
    );
}

/// 关闭系统电源（等价于 SBI `system_reset` 中的 SHUTDOWN 类型）
pub fn system_off() -> ! {
    unsafe { psci_call(PSCI_SYSTEM_OFF) };
    // PSCI 调用成功后 CPU 不会继续执行，此处仅满足编译器的发散要求
    loop {
        core::hint::spin_loop();
    }
}

/// 重启系统（等价于 SBI `system_reset` 中的 COLD_REBOOT 类型）
pub fn system_reset() -> ! {
    unsafe { psci_call(PSCI_SYSTEM_RESET) };
    loop {
        core::hint::spin_loop();
    }
}
