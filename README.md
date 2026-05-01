# AmiOS

参考 [rCore-Tutorial](https://rcore-os.cn/rCore-Tutorial-Book-v3/) 在 ARMv8 架构上从零构建操作系统内核的个人学习项目。

原版基于 RISC-V + QEMU，本项目移植到 **Rust + ARMv8 + QEMU**，最终目标适配飞腾 D2000 真实硬件。

## 快速开始

```bash
# 安装依赖
sudo apt install qemu-system-arm gdb-multiarch

# 编译
make build

# 在 QEMU 中运行（Ctrl+A X 退出）
make run

# 调试（另开终端运行 gdb-multiarch）
make debug
```

## 构建命令

| 命令 | 说明 |
|---|---|
| `make build` | 编译内核，生成 ELF 和裸机二进制 |
| `make run` | 在 QEMU virt 中运行 |
| `make debug` | 启动 QEMU 等待 GDB 连接（端口 1234） |
| `make objdump` | 反汇编查看生成代码 |
| `make clean` | 清理构建产物 |

## 平台支持

| Feature | 目标平台 | UART 基地址 |
|---|---|---|
| `qemu-virt`（默认） | QEMU virt 虚拟机 | `0x09000000` |
| `phytium-d2000` | 飞腾 D2000 | `0x28001000` |

切换平台：`cargo build --no-default-features --features phytium-d2000`

## 项目结构

```
AmiOS/
├── src/
│   ├── main.rs          内核主入口、panic handler、print! 宏
│   ├── boot.rs          ARMv8 汇编启动代码（EL 切换、BSS 清零）
│   ├── uart.rs          PL011 UART 驱动
│   └── platform/
│       └── mod.rs       各平台 MMIO 地址常量
├── linker.ld            内核内存布局链接脚本
├── Makefile             构建与运行脚本
├── Cargo.toml           Rust 项目配置
├── rust-toolchain.toml  固定 nightly 工具链版本
└── .cargo/
    └── config.toml      编译目标与链接器配置
```

## 更新记录

### 第一章：应用程序与基本执行环境（2026-05-01）

- 建立 ARMv8 裸机项目骨架（Cargo 配置、链接脚本、工具链固定）
- 实现 EL2 → EL1 异常级别切换（ARMv8 特有，RISC-V 原版无此步骤）
- 实现 PL011 UART 驱动与 `print!`/`println!` 宏
- 实现 `panic handler` 与基础运行时（`no_std`/`no_main`）
- 实现全局分配器占位（当前不支持堆分配）
- 通过 Cargo feature 区分 QEMU virt 与飞腾 D2000 平台
