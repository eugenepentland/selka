
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/lox/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

000000000105c8aa <my.vm::run+0x1d3a>:
 105c8aa:	41 80 f8 03          	cmp    $0x3,%r8b
 105c8ae:	41 0f 94 c0          	sete   %r8b
 105c8b2:	48 39 fe             	cmp    %rdi,%rsi
 105c8b5:	40 0f 94 c6          	sete   %sil
 105c8b9:	44 20 c6             	and    %r8b,%sil
 105c8bc:	48 01 ca             	add    %rcx,%rdx
 105c8bf:	48 c7 02 01 00 00 00 	movq   $0x1,(%rdx)
 105c8c6:	40 80 e6 01          	and    $0x1,%sil
 105c8ca:	40 88 72 08          	mov    %sil,0x8(%rdx)
 105c8ce:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c8d2:	49 ff c5             	inc    %r13
 105c8d5:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
