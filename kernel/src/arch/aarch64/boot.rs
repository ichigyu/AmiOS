// ┌─────────────────────────────────────────────────────────────┐
// │  arch/aarch64/boot.rs — 引入汇编启动文件                    │
// │                                                             │
// │  职责：通过 global_asm! 将 boot.S 嵌入编译单元              │
// │        汇编逻辑全部在 boot.S 中，此文件只做引用              │
// │                                                             │
// │  平台标志注入：                                              │
// │    build.rs 根据 Cargo feature 生成 OUT_DIR/platform.inc    │
// │    此处用 concat! + include_str! 将其内联到汇编字符串前缀    │
// │    替代 LLVM 不支持的 -Wa,--defsym 和 .include 指令         │
// └─────────────────────────────────────────────────────────────┘

use core::arch::global_asm;

// 将 platform.inc（由 build.rs 生成）内联到 boot.S 之前：
//   phytium-d2000 feature → ".set PHYTIUM_D2000, 1\n"
//   qemu-virt feature     → "// qemu-virt: no platform-specific symbols\n"
// boot.S 中的 .ifdef PHYTIUM_D2000 块据此决定是否展开调试探针
global_asm!(
    include_str!(concat!(env!("PLATFORM_INC"), "")),
    include_str!("boot.S")
);
