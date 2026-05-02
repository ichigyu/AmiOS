// ┌─────────────────────────────────────────────────────────────┐
// │  main.rs — 内核 crate 根                                    │
// │                                                             │
// │  职责：声明 no_std 裸机环境、注册全局分配器、聚合子模块       │
// │        具体逻辑分散在各子模块中，此文件只做顶层声明           │
// │                                                             │
// │  模块结构：                                                  │
// │    main.rs                                                  │
// │      ├─→ arch/       架构相关（启动汇编、异常向量等）         │
// │      ├─→ drivers/    硬件驱动（UART、GIC 等）                │
// │      ├─→ kernel/     内核核心（panic、allocator、入口）       │
// │      └─→ bsp/        板级支持包（MMIO 地址常量、板名等）       │
// └─────────────────────────────────────────────────────────────┘

// 裸机环境：不链接标准库（std），使用 core 库替代
#![no_std]
// 不使用 Rust 默认的 main 入口，由链接脚本和汇编指定入口 _start
#![no_main]

// 架构相关代码（启动汇编通过 arch/aarch64/boot.rs 引入）
mod arch;
// 硬件驱动层
pub mod drivers;
// 内核核心基础设施（panic handler、allocator、kernel_main、print! 宏）
mod kernel;
// 板级支持包（MMIO 地址常量、板名等）
pub mod bsp;

use kernel::NoHeapAllocator;

/// 注册全局分配器
/// 只要不调用 Box::new / Vec::new 等堆分配操作，此占位不会触发
#[global_allocator]
static ALLOCATOR: NoHeapAllocator = NoHeapAllocator;
