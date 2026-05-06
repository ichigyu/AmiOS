/* ============================================================
 * AmiOS 内核链接脚本模板
 *
 * 此文件由 C 预处理器处理后生成 linker.lds，不可直接使用。
 * 构建时由 Makefile 执行：$(CC) -E -P -D<PLATFORM> linker.lds.S -o linker.lds
 *
 * 平台基地址：
 *   QEMU_VIRT      0x40080000  （RAM 起始 0x40000000，低地址留给 DTB）
 *   PHYTIUM_D2000  0x80080000  （RAM 起始 0x80000000，低地址留给 UEFI 参数）
 *
 * 内存布局（从低到高）：
 *   KERNEL_BASE  .text          代码段
 *                .rodata        只读数据段
 *                .data          已初始化全局变量
 *                .bss           未初始化全局变量（运行时清零）
 *                _stack_bottom  栈底（低地址边界，溢出检测 / guard page 用）
 *                _stack_top     栈顶（向低地址增长，512KB）
 * ============================================================ */

#if defined(PHYTIUM_D2000)
  #define KERNEL_BASE 0x80080000
#else
  /* 默认：QEMU virt */
  #define KERNEL_BASE 0x40080000
#endif

ENTRY(_start)

SECTIONS
{
    . = KERNEL_BASE;

    /* .text 段：存放所有可执行代码
     * KEEP(.text.boot) 确保启动代码不被链接器优化掉 */
    .text : {
        KEEP(*(.text.boot))
        *(.text .text.*)
    }

    /* .rodata 段：只读数据，如字符串字面量、常量表
     * ALIGN(4096) 对齐到页边界，为后续设置内存保护做准备 */
    .rodata : ALIGN(4096) {
        *(.rodata .rodata.*)
    }

    /* .data 段：已初始化的全局变量和静态变量 */
    .data : ALIGN(4096) {
        *(.data .data.*)
    }

    /* .bss 段：未初始化的全局变量，运行时必须清零
     * 导出 _start_bss 和 _end_bss 供启动汇编代码使用 */
    .bss : ALIGN(4096) {
        _start_bss = .;
        *(.bss .bss.*)
        *(COMMON)
        _end_bss = .;
    }

    /* 栈空间：紧跟在 BSS 段之后，预留 512KB
     * ARMv8 栈向低地址增长，所以 _stack_bottom 是低地址边界，_stack_top 是高地址起始点
     * _stack_bottom 供后续 MMU guard page 和运行时溢出检测使用 */
    . = ALIGN(4096);
    _stack_bottom = .;
    . += 0x80000;
    _stack_top = .;

    /DISCARD/ : {
        *(.comment)
        *(.note*)
    }
}
