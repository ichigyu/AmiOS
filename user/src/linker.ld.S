/* ============================================================
 * AmiOS 用户态应用程序链接脚本模板
 *
 * 每个用户程序独立链接，加载到平台特定的基地址。
 * 内核负责将程序加载到此地址并跳转执行。
 *
 * 内存布局（从低到高）：
 *   BASE_ADDRESS    .text          代码段（入口 _start 在最前）
 *                   .rodata        只读数据段（页对齐）
 *                   .data          已初始化全局变量（页对齐）
 *                   .bss           未初始化全局变量（运行时清零，页对齐）
 *   栈：由内核在加载时分配，SP 指向用户栈顶
 * ============================================================ */

OUTPUT_ARCH(aarch64)
ENTRY(_start)

#ifdef PHYTIUM_D2000
BASE_ADDRESS = 0x80100000;
#else
/* QEMU_VIRT (default) */
BASE_ADDRESS = 0x40100000;
#endif

SECTIONS
{
    . = BASE_ADDRESS;

    /* 代码段：_start 必须位于最开头，确保跳转入口正确 */
    .text : {
        *(.text.entry)
        *(.text .text.*)
    }

    /* 只读数据：字符串字面量、常量表等 */
    .rodata : ALIGN(4096) {
        *(.rodata .rodata.*)
    }

    /* 已初始化全局变量 */
    .data : ALIGN(4096) {
        *(.data .data.*)
    }

    /* 未初始化全局变量：链接器填零，运行时无需额外清零 */
    .bss : ALIGN(4096) {
        *(.bss.stack)
        _start_bss = .;
        *(.bss .bss.*)
        *(COMMON)
        _end_bss = .;
    }

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}
