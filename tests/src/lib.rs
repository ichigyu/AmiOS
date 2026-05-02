// ┌─────────────────────────────────────────────────────────────┐
// │  tests/src/lib.rs — AmiOS 测试套件                          │
// │                                                             │
// │  测试策略：                                                  │
// │                                                             │
// │  【Host 单元测试】（本文件，cargo test -p amios-tests）       │
// │    测试可在 x86_64 host 上运行的纯逻辑：                     │
// │      - 编译期常量计算（波特率 IBRD/FBRD）                    │
// │      - 平台地址常量正确性                                    │
// │      - 纯算法逻辑（不依赖 MMIO 或 no_std 特性）              │
// │                                                             │
// │  【QEMU 集成测试】（后续章节，make test）                     │
// │    需要启动 QEMU 并捕获串口输出：                            │
// │      - UART 初始化和输出验证                                 │
// │      - 内存管理正确性                                        │
// │      - 进程调度行为                                          │
// └─────────────────────────────────────────────────────────────┘

// ── QEMU virt 平台常量验证 ────────────────────────────────────
// 验证波特率计算公式在 QEMU virt 平台（24MHz 时钟）下的结果
// 公式：IBRD = CLK / (16 * BAUD)，FBRD = round((CLK % (16*BAUD)) * 64 / (16*BAUD))
#[cfg(test)]
mod platform_constants {
    #[test]
    fn qemu_virt_uart_baud_rate_divisors() {
        const CLK: u32 = 24_000_000; // QEMU virt PL011 参考时钟 24MHz
        const BAUD: u32 = 115200;
        const IBRD: u32 = CLK / (16 * BAUD);
        const FBRD: u32 = ((CLK % (16 * BAUD)) * 64 + 8 * BAUD) / (16 * BAUD);

        // QEMU virt 24MHz / (16 * 115200) = 13.02 → IBRD=13, FBRD=1
        assert_eq!(IBRD, 13, "QEMU virt IBRD 应为 13");
        assert_eq!(FBRD, 1, "QEMU virt FBRD 应为 1");
    }

    #[test]
    fn phytium_d2000_uart_baud_rate_divisors() {
        const CLK: u32 = 48_000_000; // 飞腾 D2000 PL011 参考时钟 48MHz
        const BAUD: u32 = 115200;
        const IBRD: u32 = CLK / (16 * BAUD);
        const FBRD: u32 = ((CLK % (16 * BAUD)) * 64 + 8 * BAUD) / (16 * BAUD);

        // 飞腾 D2000 48MHz / (16 * 115200) = 26.04 → IBRD=26, FBRD=3
        assert_eq!(IBRD, 26, "飞腾 D2000 IBRD 应为 26");
        assert_eq!(FBRD, 3, "飞腾 D2000 FBRD 应为 3");
    }

    #[test]
    fn qemu_virt_mmio_addresses_are_nonzero() {
        // 基本健全性检查：地址常量不应为 0
        const UART0_BASE: usize = 0x0900_0000;
        const RAM_BASE: usize = 0x4000_0000;
        const KERNEL_BASE: usize = 0x4008_0000;

        assert_ne!(UART0_BASE, 0);
        assert_ne!(RAM_BASE, 0);
        // 内核加载地址应在 RAM 范围内
        assert!(KERNEL_BASE > RAM_BASE, "内核加载地址应在 RAM 起始地址之后");
    }
}
