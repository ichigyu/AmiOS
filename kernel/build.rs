// build.rs — 生成汇编平台标志 include 文件
//
// LLVM 汇编器不支持 GAS 的 -Wa,--defsym 语法。
// 改用 build.rs 将平台标志写入 OUT_DIR/platform.inc，
// boot.S 通过绝对路径 .include 引入，再用 .ifdef 做条件汇编。

use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let inc_path = out_dir.join("platform.inc");

    let content = if cfg!(feature = "phytium-d2000") {
        // 飞腾 D2000：定义 PHYTIUM_D2000 符号，boot.S 的 .ifdef 块生效
        ".set PHYTIUM_D2000, 1\n"
    } else {
        // QEMU virt 或其他平台：空文件，.ifdef PHYTIUM_D2000 块不生效
        "// qemu-virt: no platform-specific symbols\n"
    };

    fs::write(&inc_path, content).unwrap();

    // 将 OUT_DIR 路径暴露为环境变量，供 build.rs 自身引用（调试用）
    println!("cargo:rustc-env=PLATFORM_INC={}", inc_path.display());
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=CARGO_FEATURE_PHYTIUM_D2000");
}
