/* QEMU mps2-an385: the vector table at 0 (where a Cortex-M3 reads it at reset), everything else in 264 KiB at
   0x20000000, so the limits are the RP2040's. RAM: image, then the heap, then a 16 KiB stack at the top.
   The code of the `@freestanding(ram)` functions (`.ramfunc`) goes first in `.data`, where a device that boots from flash
   copies it to RAM (bringup/selka-flash/link.ld in selka-rp): QEMU loads the whole image into RAM already, and the
   compiler's image check (src/core/ram_image.zig) treats `.text` and `.rodata` here as a device's flash. */
MEMORY {
  BOOT (rx) : ORIGIN = 0x00000000, LENGTH = 1K
  RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 264K
}
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
__stack_limit = __stack_top - 16K;
ENTRY(myl_bare_reset)
SECTIONS {
  .vectors : { KEEP(*(.vectors)) } > BOOT
  .text : { *(.text*) *(.rodata*) } > RAM
  .data : { . = ALIGN(4); __data_start = .; *(.ramfunc*) . = ALIGN(4); *(.data*) . = ALIGN(4); __data_end = .; } > RAM
  __data_load = __data_start;
  .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > RAM
  __heap_start = .;
  __heap_end = __stack_limit;
  ASSERT(__heap_start + 4K <= __heap_end, "the image leaves no heap")
  /DISCARD/ : { *(.ARM.exidx*) *(.ARM.extab*) *(.comment) *(.note*) }
}
