
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/lox/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

000000000105b485 <my.vm::run+0x915>:
 105b485:	4c 89 ee             	mov    %r13,%rsi
 105b488:	48 ff ce             	dec    %rsi
 105b48b:	0f 80 34 21 00 00    	jo     105d5c5 <my.vm::run+0x2a55>
 105b491:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105b498:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b49c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b4a0:	48 89 f1             	mov    %rsi,%rcx
 105b4a3:	48 39 d6             	cmp    %rdx,%rsi
 105b4a6:	0f 83 93 16 00 00    	jae    105cb3f <my.vm::run+0x1fcf>
 105b4ac:	49 89 f5             	mov    %rsi,%r13
 105b4af:	49 ff cd             	dec    %r13
 105b4b2:	0f 80 ac 22 00 00    	jo     105d764 <my.vm::run+0x2bf4>
 105b4b8:	48 c1 e1 04          	shl    $0x4,%rcx
 105b4bc:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105b4c2:	48 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%rdi
 105b4c7:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105b4ce:	4c 89 e9             	mov    %r13,%rcx
 105b4d1:	49 39 d5             	cmp    %rdx,%r13
 105b4d4:	0f 83 67 17 00 00    	jae    105cc41 <my.vm::run+0x20d1>
 105b4da:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105b4de:	48 c1 e1 04          	shl    $0x4,%rcx
 105b4e2:	44 0f b6 0c 0a       	movzbl (%rdx,%rcx,1),%r9d
 105b4e7:	48 8b 74 0a 08       	mov    0x8(%rdx,%rcx,1),%rsi
 105b4ec:	41 83 f9 02          	cmp    $0x2,%r9d
 105b4f0:	0f 84 84 13 00 00    	je     105c87a <my.vm::run+0x1d0a>
 105b4f6:	41 83 f9 01          	cmp    $0x1,%r9d
 105b4fa:	0f 84 6c 13 00 00    	je     105c86c <my.vm::run+0x1cfc>
 105b500:	45 85 c9             	test   %r9d,%r9d
 105b503:	0f 85 a1 13 00 00    	jne    105c8aa <my.vm::run+0x1d3a>
 105b509:	45 84 c0             	test   %r8b,%r8b
 105b50c:	40 0f 94 c6          	sete   %sil
 105b510:	e9 a7 13 00 00       	jmp    105c8bc <my.vm::run+0x1d4c>
