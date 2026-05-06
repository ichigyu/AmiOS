// SPDX-License-Identifier: MIT
// arch/aarch64/boot/boot.S — ARMv8 裸机启动汇编
//
// 职责：从固件上电到进入 Rust kernel_main 的完整引导链
//
// 支持的入口异常级别：
//   EL3 → 停机（死循环）；EL3 由 ARM Trusted Firmware 持有，正常启动链不应在此交接
//   EL2 → 直接在 EL2 运行（VHE 模式）
//         飞腾 D2000：固件锁定 HCR_EL2.TGE=1，eret 降级被静默忽略，故放弃切换
//   EL1 → 直接继续
//
// 执行流程：
//   _start → [非 CPU0 → cpu_idle]
//          → EL 检测 → [EL3 → el3_halt]
//          → init_el1 / init_el2
//          → init_common → kernel_main

.arch    armv8-a
.section .text.boot
.global  _start

// ── 内核入口 ──────────────────────────────────────────────────────────────────
// 所有核心上电后均从此处开始；仅允许 CPU0 继续，其余进入低功耗等待
_start:
    mrs     x0, mpidr_el1
    and     x0, x0, #0xFF          // Aff0 字段 = CPU 编号
    cbnz    x0, cpu_idle

    // 读取当前异常级别（CurrentEL[3:2]）
    mrs     x0, CurrentEL
    ubfx    x0, x0, #2, #2         // 提取 [3:2]，结果为 1/2/3
    cmp     x0, #3
    b.eq    el3_halt
    cmp     x0, #2
    b.eq    init_el2
    // 否则为 EL1，fall-through

// ── EL1 初始化 ────────────────────────────────────────────────────────────────
// 禁用 MMU / 对齐检查 / D-cache / I-cache；开启 FP/SIMD 访问
init_el1:
    mrs     x0, sctlr_el1
    // 清除 M[0] A[1] C[2] I[12]
    mov     x1, #((1 << 0) | (1 << 1) | (1 << 2) | (1 << 12))
    bic     x0, x0, x1
    msr     sctlr_el1, x0
    isb

    mov     x0, #(3 << 20)         // FPEN[21:20]=11：允许 EL0/EL1 访问 FP/SIMD
    msr     cpacr_el1, x0
    isb
    b       init_common

// ── EL2 初始化 ────────────────────────────────────────────────────────────────
// 飞腾 D2000 VHE 模式：CPACR_EL1 映射到 EL2 的 FP/SIMD 控制寄存器
init_el2:
    mrs     x0, cpacr_el1
    orr     x0, x0, #(3 << 20)    // FPEN[21:20]=11
    msr     cpacr_el1, x0
    isb
    // fall-through

// ── 公共初始化（EL1 / EL2 共用）──────────────────────────────────────────────
init_common:
    ldr     x0, =_stack_top        // _stack_top 由链接脚本定义；栈向低地址增长
    mov     sp, x0

    bl      kernel_main
    // kernel_main 永不返回；此处作为防御性停机
    b       .

// ── 非 CPU0 空闲循环 ──────────────────────────────────────────────────────────
cpu_idle:
    wfe
    b       cpu_idle

// ── EL3 停机 ──────────────────────────────────────────────────────────────────
// GDB 可通过 PC 值定位到此处
el3_halt:
    wfe
    b       el3_halt
