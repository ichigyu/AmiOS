# ============================================================
# AmiOS 内核构建系统
#
# 用法：
#   make build                        编译内核（QEMU virt，默认）
#   make build PLATFORM=PHYTIUM_D2000 编译内核（飞腾 D2000）
#   make loader                       编译 UEFI 加载器（D2000 用）
#   make run                          在 QEMU 中运行内核
#   make debug                        启动 QEMU 等待 GDB 连接（端口 1234）
#   make objdump                      反汇编查看生成代码
#   make clean                        清理所有构建产物
# ============================================================

# ── 平台选择 ──────────────────────────────────────────────────
# 通过 PLATFORM 变量选择目标硬件，影响链接脚本和 Cargo feature
# 新增平台：在此添加条件分支，并在 linker.lds.S 中添加对应 #ifdef
PLATFORM ?= QEMU_VIRT

ifeq ($(PLATFORM),PHYTIUM_D2000)
  CARGO_FEATURES := --no-default-features --features phytium-d2000
  KERNEL_BIN_NAME := amios-kernel-d2000.bin
  LINKER_SCRIPT := kernel/linker-d2000.lds
  ASM_DEFS :=
else
  CARGO_FEATURES :=
  KERNEL_BIN_NAME := amios-kernel-qemu.bin
  LINKER_SCRIPT := kernel/linker-qemu.lds
  ASM_DEFS :=
endif

# ── 工具链配置 ────────────────────────────────────────────────
# 链接脚本预处理用系统 C 编译器（gcc/clang 均可，只用 -E 预处理功能）
# objcopy/objdump 用 LLVM 工具链，与 Rust 工具链配套
CC      := $(shell which clang 2>/dev/null || which gcc)
OBJCOPY := rust-objcopy
OBJDUMP := rust-objdump

# ── 编译目标与产物路径 ────────────────────────────────────────
TARGET      := aarch64-unknown-none
KERNEL_ELF  := target/$(TARGET)/release/amios-kernel
KERNEL_BIN  := target/$(TARGET)/release/$(KERNEL_BIN_NAME)
CARGO_FLAGS := --manifest-path kernel/Cargo.toml

# ── 默认目标 ──────────────────────────────────────────────────
.PHONY: all build loader run debug objdump clean

all: build

# ── 编译内核 ──────────────────────────────────────────────────
# 直接用平台对应的链接脚本，不需要预处理
# RUSTFLAGS 通过环境变量传入链接脚本路径，覆盖 .cargo/config.toml 中的默认值
build:
	RUSTFLAGS="-C link-arg=-T$(LINKER_SCRIPT) $(ASM_DEFS)" \
		cargo build --release $(CARGO_FLAGS) $(CARGO_FEATURES)
	$(OBJCOPY) -O binary $(KERNEL_ELF) $(KERNEL_BIN)
	@echo "Build complete (PLATFORM=$(PLATFORM)):"
	@echo "  ELF: $(KERNEL_ELF)"
	@echo "  BIN: $(KERNEL_BIN)"

# ── 编译 UEFI 加载器（飞腾 D2000 用）────────────────────────────
# 产物：target/aarch64-unknown-uefi/release/loader.efi
# 使用方法：将 loader.efi 和 amios-kernel-d2000.bin 复制到 FAT 分区，
#           在 UEFI Shell 中执行 FS0:\loader.efi 即可启动内核
LOADER_EFI := target/aarch64-unknown-uefi/release/loader.efi

loader:
	# 显式指定目标覆盖 workspace 根 .cargo/config.toml 中的 aarch64-unknown-none 默认值
	cargo build --release --manifest-path loader/Cargo.toml --target aarch64-unknown-uefi
	@echo "Loader build complete:"
	@echo "  EFI: $(LOADER_EFI)"

# ── 在 QEMU 中运行 ────────────────────────────────────────────
# QEMU 参数说明：
#   -machine virt        使用 virt 虚拟机（通用 ARMv8 板，外设地址固定）
#   -cpu cortex-a57      模拟 Cortex-A57 处理器（ARMv8-A，支持 EL0~EL3）
#   -m 128M              分配 128MB 内存
#   -nographic           禁用图形界面，串口输出重定向到终端
#   -kernel $(KERNEL_ELF) 加载 ELF 内核（QEMU 自动解析入口地址）
run: build
	qemu-system-aarch64 \
		-machine virt \
		-cpu cortex-a57 \
		-m 128M \
		-nographic \
		-kernel $(KERNEL_ELF)

# ── 调试模式（等待 GDB 连接）─────────────────────────────────
# 额外参数：
#   -s   在 localhost:1234 开启 GDB 服务器（等效于 -gdb tcp::1234）
#   -S   启动后立即暂停，等待 GDB 发送 continue 命令
#
# 使用方法：
#   终端1：make debug
#   终端2：gdb-multiarch target/aarch64-unknown-none/release/amios-kernel
#          (gdb) target remote :1234
#          (gdb) break _start
#          (gdb) continue
debug: build
	qemu-system-aarch64 \
		-machine virt \
		-cpu cortex-a57 \
		-m 128M \
		-nographic \
		-kernel $(KERNEL_ELF) \
		-s -S

# ── 反汇编内核 ────────────────────────────────────────────────
# 用于验证：
#   1. _start 符号是否位于预期的内核加载地址
#   2. EL 切换汇编代码是否正确生成
#   3. 函数调用关系是否符合预期
objdump: build
	$(OBJDUMP) \
		--arch-name=aarch64 \
		-d \
		$(KERNEL_ELF) | less

# ── 运行 host 单元测试 ────────────────────────────────────────
# tests crate 在 host 上运行，需要显式指定 host 目标覆盖 aarch64 默认值
# 测试内容：波特率常量计算、MMIO 地址健全性检查等纯逻辑验证
test:
	cargo test --manifest-path tests/Cargo.toml --target x86_64-unknown-linux-gnu

# ── 清理构建产物 ──────────────────────────────────────────────
clean:
	cargo clean $(CARGO_FLAGS)
	cargo clean --manifest-path loader/Cargo.toml
	@echo "Clean complete"
