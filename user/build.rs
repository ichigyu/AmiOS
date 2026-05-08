use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let out_dir = env::var("OUT_DIR").unwrap();

    let linker_src = PathBuf::from(&dir).join("src/linker.ld.S");
    let linker_out = PathBuf::from(&out_dir).join("linker.ld");

    // 根据 Cargo feature 确定预处理器定义
    let mut cpp_defs = Vec::new();
    if cfg!(feature = "phytium-d2000") {
        cpp_defs.push("-DPHYTIUM_D2000".to_string());
    }

    // 调用 C 预处理器生成最终的链接脚本
    let cc = env::var("CC").unwrap_or_else(|_| "gcc".to_string());
    let mut cmd = Command::new(&cc);
    cmd.arg("-E")
        .arg("-P")
        .arg("-x")
        .arg("c");

    for def in cpp_defs {
        cmd.arg(def);
    }

    cmd.arg(&linker_src);

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
