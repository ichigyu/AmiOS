use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let out_dir = env::var("OUT_DIR").unwrap();

    let linker_src = PathBuf::from(&dir).join("src/linker.ld.S");
    let linker_out = PathBuf::from(&out_dir).join("linker.ld");

    // 根据 Cargo feature 确定平台特定的地址常量
    // APP_BASE_ADDRESS = KERNEL_BASE + KERNEL_RESERVED_SIZE
    let (platform_def, app_base_address) = if cfg!(feature = "phytium-d2000") {
        // Phytium D2000: KERNEL_BASE=0x80080000, KERNEL_RESERVED_SIZE=0x80000
        ("-DPHYTIUM_D2000", "0x80100000")
    } else {
        // QEMU virt (default): KERNEL_BASE=0x40080000, KERNEL_RESERVED_SIZE=0x80000
        ("-DQEMU_VIRT", "0x40100000")
    };

    // 调用 C 预处理器生成最终的链接脚本
    let cc = env::var("CC").unwrap_or_else(|_| "gcc".to_string());
    let mut cmd = Command::new(&cc);
    cmd.arg("-E")
        .arg("-P")
        .arg("-x")
        .arg("c")
        .arg(platform_def)
        .arg(format!("-DAPP_BASE_ADDRESS={}", app_base_address))
        .arg(&linker_src);

    let output = cmd.output().expect("Failed to preprocess linker script");

    if !output.status.success() {
        panic!(
            "Linker script preprocessing failed:\n{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    std::fs::write(&linker_out, output.stdout)
        .expect("Failed to write linker script");

    println!("cargo:rustc-link-arg=-T{}", linker_out.display());
    println!("cargo:rerun-if-changed={}", linker_src.display());
}
