
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/lox/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

000000000105c940 <my.vm::run+0x1dd0>:
 105c940:	48 89 de             	mov    %rbx,%rsi
 105c943:	48 ff ce             	dec    %rsi
 105c946:	0f 80 ce 07 00 00    	jo     105d11a <my.vm::run+0x25aa>
 105c94c:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105c953:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c957:	48 39 d6             	cmp    %rdx,%rsi
 105c95a:	0f 82 90 e2 ff ff    	jb     105abf0 <my.vm::run+0x80>
 105c960:	48 89 f0             	mov    %rsi,%rax
 105c963:	48 c1 f8 3f          	sar    $0x3f,%rax
 105c967:	48 21 d0             	and    %rdx,%rax
 105c96a:	48 01 f0             	add    %rsi,%rax
 105c96d:	48 39 d0             	cmp    %rdx,%rax
 105c970:	0f 82 7a e2 ff ff    	jb     105abf0 <my.vm::run+0x80>
 105c976:	e9 9b 10 00 00       	jmp    105da16 <my.vm::run+0x2ea6>
