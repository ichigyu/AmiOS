fn main() {
    let dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    println!("cargo:rustc-link-arg=-T{}/src/linker.ld", dir);
    println!("cargo:rerun-if-changed={}/src/linker.ld", dir);
}
