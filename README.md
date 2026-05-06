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
| `make build` | 编译内核（QEMU virt，默认） |
| `make build PLATFORM=PHYTIUM_D2000` | 编译内核（飞腾 D2000） |
| `make run` | 在 QEMU virt 中运行 |
| `make debug` | 启动 QEMU 等待 GDB 连接（端口 1234） |
| `make objdump` | 反汇编查看生成代码 |
| `make clean` | 清理构建产物 |

## 平台支持

| Feature | 目标平台 | UART 基地址 | 内核加载地址 |
|---|---|---|---|
| `qemu-virt`（默认） | QEMU virt 虚拟机 | `0x09000000` | `0x40080000` |
| `phytium-d2000` | 飞腾 D2000 | `0x28001000` | `0x80080000` |

切换平台：`make build PLATFORM=PHYTIUM_D2000`

## 飞腾 D2000 — UEFI 加载器启动流程

飞腾 D2000 通过 UEFI 固件启动，UEFI Shell 只能执行 `.efi` 文件，无法直接加载裸机二进制。UEFI 加载器已独立为 [Amiboot](https://github.com/ichigyu/Amiboot) 仓库。

### 编译

```bash
make build PLATFORM=PHYTIUM_D2000   # 编译内核二进制
# 加载器编译见 Amiboot 仓库
```

产物：
- `target/aarch64-unknown-none/release/amios-kernel-d2000.bin`

### 通过 TFTP 启动

在开发机上启动 TFTP 服务，将内核二进制和 Amiboot 产物放入 TFTP 根目录：

```bash
cp target/aarch64-unknown-none/release/amios-kernel-d2000.bin /srv/tftp/
```

在 UEFI Shell 中配置网络并下载文件：

```
# 初始化网卡（接口编号视实际情况而定）
ifconfig -s eth0 dhcp

# 从 TFTP 服务器下载加载器和内核（将 <TFTP_SERVER_IP> 替换为实际地址）
tftp <TFTP_SERVER_IP> loader.efi
tftp <TFTP_SERVER_IP> amios-kernel-d2000.bin

# 执行加载器
loader.efi
```

加载器自动完成：读取内核 → 复制到 `0x80080000` → 退出 Boot Services → 跳转执行。内核启动后串口输出启动信息。

## 项目结构

```
AmiOS/
├── kernel/                  内核 crate
│   ├── Cargo.toml
│   ├── linker.lds.S         内核链接脚本模板（C 预处理器宏区分平台）
│   ├── .cargo/config.toml   aarch64 编译目标与链接器配置
│   └── src/
│       ├── main.rs          crate 根：模块声明、全局分配器注册
│       ├── arch/
│       │   └── aarch64/
│       │       ├── boot.S                ARMv8 汇编启动代码（EL 切换、BSS 清零）
│       │       ├── boot.rs               引入平台宏文件与 boot.S（global_asm!）
│       │       ├── uart_debug_phytium.S  飞腾 D2000 启动期 UART 宏（真实实现）
│       │       └── uart_debug_qemu.S     QEMU virt 启动期 UART 宏（空实现）
│       ├── bsp/
│       │   └── mod.rs       板级支持包：各平台 MMIO 地址常量、板名（feature 条件编译）
│       ├── drivers/
│       │   └── uart/
│       │       ├── mod.rs   UART 驱动对外接口
│       │       └── pl011.rs PL011 UART 寄存器操作实现
│       └── kernel/
│           ├── mod.rs       panic handler、全局分配器占位、kernel_main
│           └── io.rs        print!/println! 宏
├── user/                    用户态程序（第五章实现，当前占位）
├── Cargo.toml               workspace 根（含 profile 配置）
├── Makefile                 构建与运行脚本（PLATFORM 变量控制目标平台）
└── rust-toolchain.toml      固定 nightly 工具链版本
```




