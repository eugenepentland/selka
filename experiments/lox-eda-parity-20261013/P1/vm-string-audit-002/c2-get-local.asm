
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/lox/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

000000000105b6f7 <my.vm::run+0xb87>:
 105b6f7:	4c 89 f7             	mov    %r14,%rdi
 105b6fa:	4d 89 dc             	mov    %r11,%r12
 105b6fd:	4c 89 de             	mov    %r11,%rsi
 105b700:	4c 89 d2             	mov    %r10,%rdx
 105b703:	e8 38 6e 00 00       	call   1062540 <my.vm::read_byte>
 105b708:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 105b70d:	48 89 ce             	mov    %rcx,%rsi
 105b710:	48 01 c6             	add    %rax,%rsi
 105b713:	0f 80 39 20 00 00    	jo     105d752 <my.vm::run+0x2be2>
 105b719:	49 89 d2             	mov    %rdx,%r10
 105b71c:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b720:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b724:	48 39 d6             	cmp    %rdx,%rsi
 105b727:	0f 83 48 14 00 00    	jae    105cb75 <my.vm::run+0x2005>
 105b72d:	48 89 f1             	mov    %rsi,%rcx
 105b730:	4d 89 e3             	mov    %r12,%r11
 105b733:	48 c1 e1 04          	shl    $0x4,%rcx
 105b737:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105b73d:	4c 89 e9             	mov    %r13,%rcx
 105b740:	49 39 d5             	cmp    %rdx,%r13
 105b743:	0f 83 83 14 00 00    	jae    105cbcc <my.vm::run+0x205c>
 105b749:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105b74d:	48 c1 e1 04          	shl    $0x4,%rcx
 105b751:	c5 f9 54 05 87 8c fa 	vandpd -0x57379(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105b758:	ff 
 105b759:	c5 f9 11 04 0a       	vmovupd %xmm0,(%rdx,%rcx,1)
 105b75e:	49 89 46 78          	mov    %rax,0x78(%r14)
 105b762:	4c 89 e8             	mov    %r13,%rax
 105b765:	48 ff c0             	inc    %rax
 105b768:	0f 80 99 1f 00 00    	jo     105d707 <my.vm::run+0x2b97>
 105b76e:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
