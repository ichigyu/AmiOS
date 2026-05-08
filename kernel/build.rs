use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let workspace_root = manifest_dir.parent().unwrap();
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    // 用户程序列表（与 user/Cargo.toml 中的 [[bin]] 对应）
    let apps = ["hello_world", "store_fault", "power_off"];

    // 用户程序 .bin 由 Makefile 的 build-user 目标预先生成
    // build.rs 只负责复制到 OUT_DIR 并生成 app_list.rs，不重复 objcopy
    let user_bin_dir = workspace_root.join("target/aarch64-unknown-none/release");

    for app in &apps {
        let src_bin = user_bin_dir.join(format!("{}.bin", app));
        assert!(
            src_bin.exists(),
            "user app binary '{}' not found at {}. Run `make build-user` first.",
            app,
            src_bin.display()
        );

        let dst_bin = out_dir.join(format!("{}.bin", app));
        fs::copy(&src_bin, &dst_bin)
            .expect(&format!("failed to copy {}", app));

        // .bin 变化时重新运行 build.rs
        println!("cargo:rerun-if-changed={}", src_bin.display());
    }

    // 生成 app_list.rs：APP_NAMES 和 APP_BINARIES 两个常量
    let mut code = String::from("// 自动生成，勿手动修改\n");
    code.push_str("pub const APP_NAMES: &[&str] = &[\n");
    for app in &apps {
        code.push_str(&format!("    \"{}\",\n", app));
    }
    code.push_str("];\n\n");
    code.push_str("pub const APP_BINARIES: &[&[u8]] = &[\n");
    for app in &apps {
        code.push_str(&format!(
            "    include_bytes!(concat!(env!(\"OUT_DIR\"), \"/{}.bin\")),\n",
            app
        ));
    }
    code.push_str("];\n");

    fs::write(out_dir.join("app_list.rs"), code).unwrap();

    println!(
        "cargo:rerun-if-changed={}",
        workspace_root.join("user/src").display()
    );
}
