/* ============================================================
 * AmiOS 内核链接脚本模板 linker.lds.S
 *
 * 职责：定义内核在内存中的布局，告诉链接器各段放在哪里
 *       通过 C 预处理器宏区分平台，与 Linux 内核 / U-Boot 惯例一致
 *
 * 使用方式（由 Makefile 执行）：
 *   $(CC) -E -P -x c -DPLATFORM_QEMU_VIRT    linker.lds.S -o linker.lds
 *   $(CC) -E -P -x c -DPLATFORM_PHYTIUM_D2000 linker.lds.S -o linker.lds
 *
 * 内存布局：
 *
 *   QEMU virt 板：
 *     0x40000000  RAM 起始
 *     0x40080000  内核加载地址（_start 入口）
 *
 *   飞腾 D2000：
 *     0x80000000  RAM 起始
 *     0x80080000  内核加载地址（与 U-Boot fatload 目标地址一致）
 *
 *   通用段布局（两平台相同）：
 *     KERNEL_BASE  .text   代码段
 *                  .rodata 只读数据段
 *                  .data   已初始化全局变量
 *                  .bss    未初始化全局变量（运行时清零）
 *                  _stack_top  栈顶（向低地址增长，512KB）
 * ============================================================ */

/* 内核入口符号，链接器从这里开始 */
ENTRY(_start)

SECTIONS
{
#ifdef PLATFORM_PHYTIUM_D2000
    /* 飞腾 D2000：RAM 从 0x80000000 开始，内核加载到 0x80080000
     * 低于此地址的空间留给 U-Boot 传递的参数和设备树 */
    . = 0x80080000;
#else
    /* QEMU virt（默认）：RAM 从 0x40000000 开始，
     * 0x40080000 是 QEMU 默认加载 Linux 内核的地址，
     * 低于此地址的空间留给设备树（DTB）等固件数据 */
    . = 0x40080000;
#endif

    /* .text 段：存放所有可执行代码
     * KEEP(.text.boot) 确保启动代码不被链接器优化掉 */
    .text : {
        KEEP(*(.text.boot))   /* 启动汇编代码，必须放在最前面 */
        *(.text .text.*)      /* 其余所有代码段 */
    }

    /* .rodata 段：只读数据，如字符串字面量、常量表
     * ALIGN(4096) 对齐到页边界，为后续设置内存保护做准备 */
    .rodata : ALIGN(4096) {
        *(.rodata .rodata.*)
    }

    /* .data 段：已初始化的全局变量和静态变量
     * 这些数据在 ELF 文件中有初始值，加载时复制到 RAM */
    .data : ALIGN(4096) {
        *(.data .data.*)
    }

    /* .bss 段：未初始化的全局变量（Block Started by Symbol）
     * ELF 文件中不存储这些数据，但运行时必须清零
     * 导出 _start_bss 和 _end_bss 供启动汇编代码使用 */
    .bss : ALIGN(4096) {
        _start_bss = .;       /* BSS 段起始地址 */
        *(.bss .bss.*)
        *(COMMON)             /* 未初始化的公共符号 */
        _end_bss = .;         /* BSS 段结束地址 */
    }

    /* 栈空间：紧跟在 BSS 段之后，预留 512KB
     * ARMv8 栈向低地址增长，所以栈顶是高地址 */
    . = ALIGN(4096);
    . += 0x80000;             /* 预留 512KB 栈空间 */
    _stack_top = .;           /* 栈顶地址，启动时将 SP 设置到这里 */

    /* 丢弃调试信息和注释段，减小二进制体积 */
    /DISCARD/ : {
        *(.comment)
        *(.note*)
    }
}
