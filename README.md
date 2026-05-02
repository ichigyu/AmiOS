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
| `make loader` | 编译 UEFI 加载器（飞腾 D2000 用，产物 `loader.efi`） |
| `make run` | 在 QEMU virt 中运行 |
| `make debug` | 启动 QEMU 等待 GDB 连接（端口 1234） |
| `make objdump` | 反汇编查看生成代码 |
| `make test` | 运行 host 单元测试（波特率常量等纯逻辑验证） |
| `make clean` | 清理构建产物 |

## 平台支持

| Feature | 目标平台 | UART 基地址 | 内核加载地址 |
|---|---|---|---|
| `qemu-virt`（默认） | QEMU virt 虚拟机 | `0x09000000` | `0x40080000` |
| `phytium-d2000` | 飞腾 D2000 | `0x28001000` | `0x80080000` |

切换平台：`make build PLATFORM=PHYTIUM_D2000`

## 飞腾 D2000 — UEFI 加载器启动流程

飞腾 D2000 通过 UEFI 固件启动，UEFI Shell 只能执行 `.efi` 文件，无法直接加载裸机二进制。`loader/` crate 提供一个极简 UEFI 加载器解决此问题。

### 编译

```bash
make build PLATFORM=PHYTIUM_D2000   # 编译内核二进制
make loader                          # 编译 UEFI 加载器
```

产物：
- `target/aarch64-unknown-none/release/amios-kernel-d2000.bin`
- `target/aarch64-unknown-uefi/release/loader.efi`

### 通过 TFTP 启动

在开发机上启动 TFTP 服务，将两个产物放入 TFTP 根目录：

```bash
cp target/aarch64-unknown-none/release/amios-kernel-d2000.bin /srv/tftp/
cp target/aarch64-unknown-uefi/release/loader.efi /srv/tftp/
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
│       │       ├── boot.S   ARMv8 汇编启动代码（EL 切换、BSS 清零）
│       │       └── boot.rs  引入 boot.S（global_asm!）
│       ├── bsp/
│       │   └── mod.rs       板级支持包：各平台 MMIO 地址常量、板名（feature 条件编译）
│       ├── drivers/
│       │   └── uart/
│       │       ├── mod.rs   UART 驱动对外接口
│       │       └── pl011.rs PL011 UART 寄存器操作实现
│       └── kernel/
│           ├── mod.rs       panic handler、全局分配器占位、kernel_main
│           └── io.rs        print!/println! 宏
├── loader/                  UEFI 加载器 crate（飞腾 D2000 用）
│   ├── Cargo.toml           依赖 uefi crate，目标 aarch64-unknown-uefi
│   ├── .cargo/config.toml   默认编译目标 aarch64-unknown-uefi
│   └── src/
│       └── main.rs          UEFI 入口：读取内核 → 复制到 0x80080000 → 跳转执行
├── user/                    用户态程序（第五章实现，当前占位）
├── tests/                   host 单元测试 crate
│   └── src/lib.rs           波特率常量等纯逻辑验证
├── Cargo.toml               workspace 根（含 profile 配置）
├── Makefile                 构建与运行脚本（PLATFORM 变量控制目标平台）
└── rust-toolchain.toml      固定 nightly 工具链版本
```

## 更新记录

### 第一章：应用程序与基本执行环境（2026-05-01）

- 建立 ARMv8 裸机项目
- 实现 EL2 → EL1 异常级别切换（ARMv8 特有，RISC-V 原版无此步骤）
- 实现 PL011 UART 驱动与 `print!`/`println!` 宏
- 实现 `panic handler` 与基础运行时（`no_std`/`no_main`）
- 实现全局分配器占位（当前不支持堆分配）
- 通过 Cargo feature 区分 QEMU virt 与飞腾 D2000 平台

### 飞腾 D2000 适配与 BSP 层重构（2026-05-02）

- 将 `platform/` 模块重命名为 `bsp/`（Board Support Package），确立板级支持包层规范
- 链接脚本改为预处理模板 `linker.lds.S`（与 Linux 内核 / U-Boot 惯例一致），通过 `#ifdef` 区分平台加载地址
- 修正 PL011 初始化：移除 `UARTCR_CTSEN` 命名错误（bit0 是 UARTEN 非 CTS），明确不启用 CTS 硬件流控（D2000 调试串口无 CTS 引脚）
- boot.S 新增 EL3 检测分支，EL3 入口跳转到死循环停机，避免静默跑飞（ARMv8 特有）
- 启动横幅和 panic 消息改为纯 ASCII 英文，平台名称改用 `bsp::BOARD_NAME` 常量
- Makefile 引入 `PLATFORM` 变量统一控制 feature flag、链接脚本预处理宏，`make build PLATFORM=PHYTIUM_D2000` 产出 D2000 裸机二进制

- 建立 Cargo workspace 顶层结构，区分 `kernel/`（内核）、`user/`（用户态占位）、`tests/`（测试）
- 内核 `src/` 按职责分层：`arch/aarch64/`（启动代码）、`drivers/uart/`（UART 驱动）、`kernel/`（核心基础设施）、`platform/`（MMIO 常量）
- 将启动汇编从 `global_asm!` 字符串提取为独立 `boot.S` 文件（`global_asm!(include_str!("boot.S"))`）
- 将 `print!`/`println!` 宏迁移到 `kernel/io.rs`，与 UART 驱动解耦
- 建立 `tests/` crate，实现波特率常量编译期验证测试（`make test`）

- 修正飞腾 D2000 平台 UART 波特率配置：D2000 UART 时钟为 48MHz（QEMU virt 为 24MHz），对应 IBRD/FBRD 应为 26/3 而非 13/1
- 在 `platform/mod.rs` 各平台分支中新增 `UART_CLK_HZ` 时钟常量
- 重构 `uart::init()`：改为编译期由 `UART_CLK_HZ` 计算 IBRD/FBRD，切换平台时自动得到正确值

### UEFI 加载器（2026-05-02）

- 新增 `loader/` crate，编译目标 `aarch64-unknown-uefi`，产物为 `loader.efi`（PE/COFF 格式）
- 实现从 EFI 简单文件系统读取 `amios-kernel-d2000.bin`，复制到 `0x80080000`，调用 `ExitBootServices()` 后跳转执行内核
- Makefile 新增 `make loader` 构建目标
- 新增 UEFI Shell 启动流程文档（`FS0:\loader.efi` 一键启动）
