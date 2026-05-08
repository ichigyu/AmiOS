# ============================================================
# AmiOS 内核构建系统
#
# 用法：
#   make build                        编译内核（QEMU virt，默认）
#   make build PLATFORM=PHYTIUM_D2000 编译内核（飞腾 D2000）
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
  CARGO_FEATURES  := --no-default-features --features phytium-d2000
  KERNEL_BIN_NAME := amios-kernel-d2000.bin
  CPP_DEFS        := -DPHYTIUM_D2000
else
  CARGO_FEATURES  :=
  KERNEL_BIN_NAME := amios-kernel-qemu.bin
  CPP_DEFS        := -DQEMU_VIRT
endif

# 生成的链接脚本（由 linker.lds.S 预处理而来，已加入 .gitignore）
LINKER_SCRIPT     := kernel/linker.lds
LINKER_SCRIPT_SRC := kernel/linker.lds.S
# 平台戳文件：记录上次构建的平台，切换平台时触发链接脚本重新生成
PLATFORM_STAMP    := kernel/.platform_stamp

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

# ── 用户态应用程序配置 ────────────────────────────────────────
USER_APPS       := hello_world store_fault power_off
USER_TARGET     := aarch64-unknown-none
USER_BUILD_DIR  := target/$(USER_TARGET)/release
USER_BINS       := $(patsubst %,$(USER_BUILD_DIR)/%.bin,$(USER_APPS))

# ── 默认目标 ──────────────────────────────────────────────────
.PHONY: all build build-user run debug objdump clean

all: build

# ── 编译内核 ──────────────────────────────────────────────────
# 先编译用户程序（build.rs 需要 ELF 已存在），再编译内核
# -E：只做预处理  -P：去掉行号注释  -x c：以 C 语法解析（支持 // 注释）
build: build-user $(LINKER_SCRIPT)
	RUSTFLAGS="-C link-arg=-T$(LINKER_SCRIPT)" \
		cargo build --release $(CARGO_FLAGS) $(CARGO_FEATURES)
	$(OBJCOPY) -O binary $(KERNEL_ELF) $(KERNEL_BIN)
	@echo "Build complete (PLATFORM=$(PLATFORM)):"
	@echo "  ELF: $(KERNEL_ELF)"
	@echo "  BIN: $(KERNEL_BIN)"

# ── 编译用户态应用程序 ────────────────────────────────────────
# 每个应用独立链接到平台特定的 BASE_ADDRESS，生成裸二进制
build-user:
	cargo build --release --manifest-path user/Cargo.toml $(CARGO_FEATURES)
	@for app in $(USER_APPS); do \
		$(OBJCOPY) -O binary $(USER_BUILD_DIR)/$$app $(USER_BUILD_DIR)/$$app.bin; \
		echo "  BIN: $(USER_BUILD_DIR)/$$app.bin"; \
	done

# 预处理链接脚本模板，生成平台对应的 linker.lds
# 依赖平台戳文件：切换 PLATFORM 时戳文件内容变化，触发重新预处理
$(LINKER_SCRIPT): $(LINKER_SCRIPT_SRC) $(PLATFORM_STAMP)
	$(CC) -E -P -x c $(CPP_DEFS) $< -o $@

# 平台戳文件：内容为当前 PLATFORM 值，切换平台时由 shell 比较后更新
$(PLATFORM_STAMP): FORCE
	@if [ "$$(cat $@ 2>/dev/null)" != "$(PLATFORM)" ]; then \
		echo "$(PLATFORM)" > $@; \
	fi

.PHONY: FORCE

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

# ── 清理构建产物 ──────────────────────────────────────────────
clean:
	cargo clean $(CARGO_FLAGS)
	cargo clean --manifest-path user/Cargo.toml
	rm -f $(LINKER_SCRIPT) $(PLATFORM_STAMP)
	@echo "Clean complete"
