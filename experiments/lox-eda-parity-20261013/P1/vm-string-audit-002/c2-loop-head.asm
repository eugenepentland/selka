
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/lox/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

000000000105abf0 <my.vm::run+0x80>:
 105abf0:	4c 89 f7             	mov    %r14,%rdi
 105abf3:	4c 89 de             	mov    %r11,%rsi
 105abf6:	4c 89 d2             	mov    %r10,%rdx
 105abf9:	4c 89 dd             	mov    %r11,%rbp
 105abfc:	e8 3f 79 00 00       	call   1062540 <my.vm::read_byte>
 105ac01:	49 89 d2             	mov    %rdx,%r10
 105ac04:	49 8b 8e 88 00 00 00 	mov    0x88(%r14),%rcx
 105ac0b:	4c 8d 63 ff          	lea    -0x1(%rbx),%r12
 105ac0f:	4c 89 e2             	mov    %r12,%rdx
 105ac12:	48 85 db             	test   %rbx,%rbx
 105ac15:	7f 07                	jg     105ac1e <my.vm::run+0xae>
 105ac17:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105ac1b:	4c 01 e2             	add    %r12,%rdx
 105ac1e:	48 c1 e2 05          	shl    $0x5,%rdx
 105ac22:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 105ac27:	48 89 74 11 20       	mov    %rsi,0x20(%rcx,%rdx,1)
 105ac2c:	48 89 6c 11 28       	mov    %rbp,0x28(%rcx,%rdx,1)
 105ac31:	4c 89 54 11 30       	mov    %r10,0x30(%rcx,%rdx,1)
 105ac36:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105ac3b:	48 89 74 11 38       	mov    %rsi,0x38(%rcx,%rdx,1)
 105ac40:	49 89 8e 88 00 00 00 	mov    %rcx,0x88(%r14)
 105ac47:	48 83 f8 24          	cmp    $0x24,%rax
 105ac4b:	49 89 eb             	mov    %rbp,%r11
 105ac4e:	0f 87 ec 1c 00 00    	ja     105c940 <my.vm::run+0x1dd0>
 105ac54:	49 63 0c 87          	movslq (%r15,%rax,4),%rcx
 105ac58:	4c 01 f9             	add    %r15,%rcx
 105ac5b:	ff e1                	jmp    *%rcx
