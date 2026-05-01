# ============================================================
# AmiOS 内核构建系统
#
# 用法：
#   make build    编译内核，生成 ELF 和裸机二进制
#   make run      在 QEMU 中运行内核
#   make debug    启动 QEMU 等待 GDB 连接（端口 1234）
#   make objdump  反汇编内核，查看生成的机器码
#   make clean    清理所有构建产物
# ============================================================

# ── 工具链配置 ────────────────────────────────────────────────
# 使用 LLVM 工具链，与 Rust 工具链配套，无需单独安装交叉编译器
OBJCOPY := llvm-objcopy   # 将 ELF 转换为裸机二进制
OBJDUMP := llvm-objdump   # 反汇编 ELF 文件

# ── 编译目标与产物路径 ────────────────────────────────────────
TARGET  := aarch64-unknown-none
KERNEL_ELF := target/$(TARGET)/release/amios
KERNEL_BIN := target/$(TARGET)/release/amios.bin

# ── 默认目标 ──────────────────────────────────────────────────
.PHONY: all build run debug objdump clean

all: build

# ── 编译内核 ──────────────────────────────────────────────────
# 使用 release 模式编译（优化体积），然后用 objcopy 去掉 ELF 头
# 生成纯二进制文件（.bin），某些加载方式需要纯二进制
build:
	# 编译 Rust 内核（release 模式，优化体积）
	cargo build --release
	# 将 ELF 转换为裸机二进制（去掉 ELF 头，只保留代码和数据）
	$(OBJCOPY) -O binary $(KERNEL_ELF) $(KERNEL_BIN)
	@echo "构建完成："
	@echo "  ELF: $(KERNEL_ELF)"
	@echo "  BIN: $(KERNEL_BIN)"

# ── 在 QEMU 中运行 ────────────────────────────────────────────
# QEMU 参数说明：
#   -machine virt        使用 virt 虚拟机（通用 ARMv8 板，外设地址固定）
#   -cpu cortex-a57      模拟 Cortex-A57 处理器（ARMv8-A，支持 EL0~EL3）
#   -m 128M              分配 128MB 内存（RAM 从 0x40000000 开始）
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
#   终端2：gdb-multiarch target/aarch64-unknown-none/release/amios
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
#   1. _start 符号是否位于 0x40080000
#   2. EL 切换汇编代码是否正确生成
#   3. 函数调用关系是否符合预期
objdump: build
	$(OBJDUMP) \
		--arch-name=aarch64 \
		-d \
		$(KERNEL_ELF) | less

# ── 清理构建产物 ──────────────────────────────────────────────
clean:
	cargo clean
	@echo "清理完成"
