/* ============================================================
 * AmiOS 内核链接脚本 — 飞腾 D2000 平台
 *
 * 内存布局：
 *   0x80000000  RAM 起始
 *   0x80080000  内核加载地址（_start 入口）
 *               低于此地址的空间留给 UEFI 传递的参数和设备树
 *
 *   KERNEL_BASE  .text   代码段
 *                .rodata 只读数据段
 *                .data   已初始化全局变量
 *                .bss         未初始化全局变量（运行时清零）
 *                _stack_bottom  栈底（低地址边界，溢出检测 / guard page 用）
 *                _stack_top     栈顶（向低地址增长，512KB）
 * ============================================================ */

ENTRY(_start)

SECTIONS
{
    . = 0x80080000;

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
