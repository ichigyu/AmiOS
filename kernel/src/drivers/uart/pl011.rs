// ┌─────────────────────────────────────────────────────────────┐
// │  drivers/uart/pl011.rs — ARM PL011 UART 寄存器操作实现      │
// │                                                             │
// │  职责：封装 PL011 UART 控制器的 MMIO 寄存器操作，提供        │
// │        初始化、字符输出和 fmt::Write 接口                    │
// │                                                             │
// │  调用关系：                                                  │
// │    drivers::uart (mod.rs)                                   │
// │      └─→ pl011::init()         初始化串口控制器             │
// │      └─→ pl011::putchar()      单字符写入                   │
// │      └─→ pl011::Uart           fmt::Write 实现              │
// │            └─→ MMIO 寄存器操作（bsp::mmio 常量）              │
// └─────────────────────────────────────────────────────────────┘

use core::fmt;
use crate::bsp::mmio::{UART0_BASE, UART_CLK_HZ};

// ── PL011 寄存器偏移量 ────────────────────────────────────────
// 来源：ARM PrimeCell UART (PL011) 技术参考手册 r1p5
// 所有偏移量相对于 UART0_BASE

/// 数据寄存器：写入发送字符，读取接收字符
const UARTDR: usize = 0x000;

/// 标志寄存器：包含 UART 状态位
const UARTFR: usize = 0x018;

/// 整数波特率除数寄存器（Integer Baud Rate Divisor）
/// 波特率 = 参考时钟 / (16 * (IBRD + FBRD/64))
const UARTIBRD: usize = 0x024;

/// 小数波特率除数寄存器（Fractional Baud Rate Divisor）
const UARTFBRD: usize = 0x028;

/// 线控寄存器（Line Control Register）：配置数据格式
const UARTLCR_H: usize = 0x02C;

/// 控制寄存器（Control Register）：启用/禁用 UART 和收发功能
const UARTCR: usize = 0x030;

// ── UARTFR 标志位 ─────────────────────────────────────────────
/// 发送 FIFO 满标志（Transmit FIFO Full）
/// 为 1 时不能写入新数据，需要等待
const UARTFR_TXFF: u32 = 1 << 5;

// ── UARTCR 控制位 ─────────────────────────────────────────────
/// UART 使能位（bit0）：为 1 时启用 UART
const UARTCR_UARTEN: u32 = 1 << 0;
/// 发送使能位（bit8）：为 1 时启用发送功能
const UARTCR_TXE: u32 = 1 << 8;
/// 接收使能位（bit9）：为 1 时启用接收功能
const UARTCR_RXE: u32 = 1 << 9;
// 注：CTS 硬件流控使能位为 bit15（CTSEN），此处不启用
// D2000 调试串口排针通常无 CTS 线，启用后会导致发送永久阻塞

// ── UARTLCR_H 线控位 ──────────────────────────────────────────
/// 使能 FIFO（bit4）：为 1 时启用发送/接收 FIFO 缓冲
const UARTLCR_H_FEN: u32 = 1 << 4;
/// 字长配置（bit5:6）= 0b11：8 位数据位
const UARTLCR_H_WLEN_8BIT: u32 = 0b11 << 5;

// ── MMIO 读写辅助函数 ─────────────────────────────────────────

/// 向 MMIO 地址写入 32 位值
/// 使用 volatile 写入，防止编译器优化掉对硬件寄存器的写操作
#[inline]
fn mmio_write(addr: usize, val: u32) {
    // SAFETY: addr 是有效的 MMIO 地址，volatile 写入不会被优化
    unsafe { core::ptr::write_volatile(addr as *mut u32, val) }
}

/// 从 MMIO 地址读取 32 位值
/// 使用 volatile 读取，确保每次都真正读取硬件寄存器
#[inline]
fn mmio_read(addr: usize) -> u32 {
    // SAFETY: addr 是有效的 MMIO 地址，volatile 读取不会被优化
    unsafe { core::ptr::read_volatile(addr as *const u32) }
}

// ── UART 初始化 ───────────────────────────────────────────────

/// 初始化 PL011 UART 控制器
///
/// 配置参数：波特率 115200，8 位数据位，无奇偶校验，1 位停止位（8N1）
///
/// 波特率计算公式：BRD = UART_CLK_HZ / (16 * 115200)
///   QEMU virt（24MHz）：BRD = 13.02  → IBRD=13, FBRD=round(0.02*64)=1
///   飞腾 D2000（48MHz）：BRD = 26.04 → IBRD=26, FBRD=round(0.04*64)=3
/// IBRD/FBRD 由平台时钟常量在编译期计算，无需手动维护两套魔法数字
pub fn init() {
    // 编译期计算波特率除数，避免平台切换时遗漏更新
    const BAUD: u32 = 115200;
    const IBRD: u32 = UART_CLK_HZ / (16 * BAUD);
    // FBRD = round((BRD 小数部分) * 64) = round((UART_CLK_HZ % (16*BAUD)) * 64 / (16*BAUD))
    // 用整数运算等价：(余数 * 64 + 半个除数) / 除数，实现四舍五入
    const FBRD: u32 = ((UART_CLK_HZ % (16 * BAUD)) * 64 + 8 * BAUD) / (16 * BAUD);

    // 第一步：禁用 UART，在修改配置前必须先关闭
    mmio_write(UART0_BASE + UARTCR, 0);

    // 第二步：设置波特率
    mmio_write(UART0_BASE + UARTIBRD, IBRD);
    mmio_write(UART0_BASE + UARTFBRD, FBRD);

    // 第三步：配置数据格式（8N1）并启用 FIFO
    // WLEN=0b11（8位数据）| FEN=1（启用FIFO）
    mmio_write(UART0_BASE + UARTLCR_H, UARTLCR_H_WLEN_8BIT | UARTLCR_H_FEN);

    // 第四步：启用 UART、发送和接收功能
    // 不启用 CTS 硬件流控（bit15 CTSEN）：D2000 调试串口无 CTS 引脚，
    // QEMU virt 也不需要流控，统一不启用以保持两平台行为一致
    mmio_write(UART0_BASE + UARTCR, UARTCR_UARTEN | UARTCR_TXE | UARTCR_RXE);
}

// ── 字符输出 ──────────────────────────────────────────────────

/// 通过 UART 发送单个字节
///
/// 使用轮询方式：等待发送 FIFO 有空间后再写入数据
/// 这是最简单的发送方式，不需要中断，适合早期启动阶段
pub fn putchar(c: u8) {
    // 轮询等待：检查 UARTFR 的 TXFF 位
    // TXFF=1 表示发送 FIFO 已满，需要等待
    while mmio_read(UART0_BASE + UARTFR) & UARTFR_TXFF != 0 {}

    // 发送 FIFO 有空间了，写入字符到数据寄存器
    mmio_write(UART0_BASE + UARTDR, c as u32);
}

// ── core::fmt::Write 实现 ─────────────────────────────────────
// 实现此 trait 后，UART 可以配合 write! 宏使用格式化输出

/// UART 写入器，实现 core::fmt::Write 以支持格式化输出
pub struct Uart;

impl fmt::Write for Uart {
    /// 将字符串逐字节写入 UART
    /// 将 '\n' 转换为 '\r\n'，确保终端正确换行
    fn write_str(&mut self, s: &str) -> fmt::Result {
        for byte in s.bytes() {
            if byte == b'\n' {
                // 发送回车符（\r），将光标移到行首
                putchar(b'\r');
            }
            putchar(byte);
        }
        Ok(())
    }
}
