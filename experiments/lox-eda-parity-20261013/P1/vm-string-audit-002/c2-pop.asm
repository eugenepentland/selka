
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/lox/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

000000000105b212 <my.vm::run+0x6a2>:
 105b212:	4c 89 ee             	mov    %r13,%rsi
 105b215:	48 ff ce             	dec    %rsi
 105b218:	0f 80 bb 23 00 00    	jo     105d5d9 <my.vm::run+0x2a69>
 105b21e:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105b225:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b229:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b22d:	48 39 d6             	cmp    %rdx,%rsi
 105b230:	0f 83 d3 18 00 00    	jae    105cb09 <my.vm::run+0x1f99>
 105b236:	49 89 f5             	mov    %rsi,%r13
 105b239:	e9 02 17 00 00       	jmp    105c940 <my.vm::run+0x1dd0>
