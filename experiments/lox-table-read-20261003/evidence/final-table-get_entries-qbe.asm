
/home/epentland/ai/canopy/mylang-worktrees/codex-lox-ownership-inline-20261003/.tmp-lox-table-read-20261003/bin/final-table-entries-qbe:     file format elf64-x86-64


Disassembly of section .text:

000000000111bc60 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f>:
 111bc60:	f3 0f 1e fa          	endbr64
 111bc64:	55                   	push   %rbp
 111bc65:	48 89 e5             	mov    %rsp,%rbp
 111bc68:	48 83 ec 48          	sub    $0x48,%rsp
 111bc6c:	53                   	push   %rbx
 111bc6d:	48 89 f8             	mov    %rdi,%rax
 111bc70:	48 89 f7             	mov    %rsi,%rdi
 111bc73:	48 83 f9 00          	cmp    $0x0,%rcx
 111bc77:	0f 84 89 02 00 00    	je     111bf06 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x2a6>
 111bc7d:	48 8b 32             	mov    (%rdx),%rsi
 111bc80:	48 b9 ff ff ff ff ff 	movabs $0x7fffffffffffffff,%rcx
 111bc87:	ff ff 7f 
 111bc8a:	48 39 ce             	cmp    %rcx,%rsi
 111bc8d:	0f 87 67 02 00 00    	ja     111befa <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x29a>
 111bc93:	48 b9 01 00 00 00 00 	movabs $0x8000000000000001,%rcx
 111bc9a:	00 00 80 
 111bc9d:	48 39 ce             	cmp    %rcx,%rsi
 111bca0:	0f 8c 3a 02 00 00    	jl     111bee0 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x280>
 111bca6:	48 89 f1             	mov    %rsi,%rcx
 111bca9:	48 83 e9 01          	sub    $0x1,%rcx
 111bcad:	48 83 f9 00          	cmp    $0x0,%rcx
 111bcb1:	41 0f 9c c2          	setl   %r10b
 111bcb5:	4d 0f b6 d2          	movzbq %r10b,%r10
 111bcb9:	41 bb ff ff ff ff    	mov    $0xffffffff,%r11d
 111bcbf:	4c 39 d9             	cmp    %r11,%rcx
 111bcc2:	41 0f 9f c3          	setg   %r11b
 111bcc6:	4d 0f b6 db          	movzbq %r11b,%r11
 111bcca:	4d 09 da             	or     %r11,%r10
 111bccd:	0f 85 fe 01 00 00    	jne    111bed1 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x271>
 111bcd3:	49 21 c9             	and    %rcx,%r9
 111bcd6:	49 c1 e1 20          	shl    $0x20,%r9
 111bcda:	49 c1 e9 20          	shr    $0x20,%r9
 111bcde:	48 87 f7             	xchg   %rsi,%rdi
 111bce1:	48 97                	xchg   %rax,%rdi
 111bce3:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 111bcea:	00 00 00 
 111bced:	0f 1f 00             	nopl   (%rax)
 111bcf0:	49 39 c1             	cmp    %rax,%r9
 111bcf3:	0f 82 93 00 00 00    	jb     111bd8c <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x12c>
 111bcf9:	49 83 f9 00          	cmp    $0x0,%r9
 111bcfd:	7c 05                	jl     111bd04 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xa4>
 111bcff:	4d 89 cb             	mov    %r9,%r11
 111bd02:	eb 2d                	jmp    111bd31 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xd1>
 111bd04:	49 ba ff ff ff ff ff 	movabs $0x7fffffffffffffff,%r10
 111bd0b:	ff ff 7f 
 111bd0e:	4c 39 d0             	cmp    %r10,%rax
 111bd11:	77 64                	ja     111bd77 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x117>
 111bd13:	4d 89 ca             	mov    %r9,%r10
 111bd16:	49 01 c2             	add    %rax,%r10
 111bd19:	4d 89 d3             	mov    %r10,%r11
 111bd1c:	49 31 c3             	xor    %rax,%r11
 111bd1f:	4c 89 d3             	mov    %r10,%rbx
 111bd22:	4c 31 cb             	xor    %r9,%rbx
 111bd25:	49 21 db             	and    %rbx,%r11
 111bd28:	49 83 fb 00          	cmp    $0x0,%r11
 111bd2c:	7c 28                	jl     111bd56 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xf6>
 111bd2e:	4d 89 d3             	mov    %r10,%r11
 111bd31:	4c 8b 12             	mov    (%rdx),%r10
 111bd34:	4d 39 d3             	cmp    %r10,%r11
 111bd37:	73 0d                	jae    111bd46 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xe6>
 111bd39:	4c 8b 52 20          	mov    0x20(%rdx),%r10
 111bd3d:	4d 6b db 20          	imul   $0x20,%r11,%r11
 111bd41:	4d 01 da             	add    %r11,%r10
 111bd44:	eb 51                	jmp    111bd97 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x137>
 111bd46:	4c 89 d2             	mov    %r10,%rdx
 111bd49:	48 89 f7             	mov    %rsi,%rdi
 111bd4c:	4c 89 de             	mov    %r11,%rsi
 111bd4f:	e8 2c f6 03 00       	call   115b380 <myl_qbe_fail_normalized_index_bounds>
 111bd54:	0f 0b                	ud2
 111bd56:	4c 89 ca             	mov    %r9,%rdx
 111bd59:	48 89 f7             	mov    %rsi,%rdi
 111bd5c:	48 89 c6             	mov    %rax,%rsi
 111bd5f:	41 b8 40 00 00 00    	mov    $0x40,%r8d
 111bd65:	48 89 d1             	mov    %rdx,%rcx
 111bd68:	48 89 f2             	mov    %rsi,%rdx
 111bd6b:	be 00 00 00 00       	mov    $0x0,%esi
 111bd70:	e8 1b f8 03 00       	call   115b590 <myl_qbe_fail_overflow_op>
 111bd75:	0f 0b                	ud2
 111bd77:	48 89 f7             	mov    %rsi,%rdi
 111bd7a:	48 89 c6             	mov    %rax,%rsi
 111bd7d:	ba 40 01 00 00       	mov    $0x140,%edx
 111bd82:	48 89 f0             	mov    %rsi,%rax
 111bd85:	e8 46 f9 03 00       	call   115b6d0 <myl_qbe_fail_cast>
 111bd8a:	0f 0b                	ud2
 111bd8c:	4c 8b 52 20          	mov    0x20(%rdx),%r10
 111bd90:	4d 6b d9 20          	imul   $0x20,%r9,%r11
 111bd94:	4d 01 da             	add    %r11,%r10
 111bd97:	4d 8b 1a             	mov    (%r10),%r11
 111bd9a:	49 83 fb ff          	cmp    $0xffffffffffffffff,%r11
 111bd9e:	74 42                	je     111bde2 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x182>
 111bda0:	4d 39 d8             	cmp    %r11,%r8
 111bda3:	0f 85 cd 00 00 00    	jne    111be76 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x216>
 111bda9:	48 89 f8             	mov    %rdi,%rax
 111bdac:	c7 45 e0 01 00 00 00 	movl   $0x1,-0x20(%rbp)
 111bdb3:	49 8b 4a 10          	mov    0x10(%r10),%rcx
 111bdb7:	48 89 4d e8          	mov    %rcx,-0x18(%rbp)
 111bdbb:	49 8b 4a 18          	mov    0x18(%r10),%rcx
 111bdbf:	48 89 4d f0          	mov    %rcx,-0x10(%rbp)
 111bdc3:	48 8b 4d e0          	mov    -0x20(%rbp),%rcx
 111bdc7:	48 89 08             	mov    %rcx,(%rax)
 111bdca:	48 8b 4d e8          	mov    -0x18(%rbp),%rcx
 111bdce:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111bdd2:	48 8b 4d f0          	mov    -0x10(%rbp),%rcx
 111bdd6:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111bdda:	48 89 c3             	mov    %rax,%rbx
 111bddd:	e9 42 01 00 00       	jmp    111bf24 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x2c4>
 111bde2:	4d 8b 1a             	mov    (%r10),%r11
 111bde5:	4c 89 5d e0          	mov    %r11,-0x20(%rbp)
 111bde9:	4d 8b 5a 08          	mov    0x8(%r10),%r11
 111bded:	4c 89 5d e8          	mov    %r11,-0x18(%rbp)
 111bdf1:	4d 8b 5a 10          	mov    0x10(%r10),%r11
 111bdf5:	4c 89 5d f0          	mov    %r11,-0x10(%rbp)
 111bdf9:	4d 8b 52 18          	mov    0x18(%r10),%r10
 111bdfd:	4c 89 55 f8          	mov    %r10,-0x8(%rbp)
 111be01:	44 8b 55 f0          	mov    -0x10(%rbp),%r10d
 111be05:	49 83 fa 00          	cmp    $0x0,%r10
 111be09:	74 5f                	je     111be6a <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x20a>
 111be0b:	49 83 fa 01          	cmp    $0x1,%r10
 111be0f:	74 51                	je     111be62 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x202>
 111be11:	49 83 fa 02          	cmp    $0x2,%r10
 111be15:	74 43                	je     111be5a <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x1fa>
 111be17:	49 83 fa 03          	cmp    $0x3,%r10
 111be1b:	75 08                	jne    111be25 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x1c5>
 111be1d:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 111be23:	eb 4b                	jmp    111be70 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x210>
 111be25:	48 89 fb             	mov    %rdi,%rbx
 111be28:	ba 18 00 00 00       	mov    $0x18,%edx
 111be2d:	be 00 00 00 00       	mov    $0x0,%esi
 111be32:	48 8d 7d c8          	lea    -0x38(%rbp),%rdi
 111be36:	e8 f5 bc 05 00       	call   1177b30 <compiler_rt.fastMemset>
 111be3b:	48 89 d8             	mov    %rbx,%rax
 111be3e:	48 8b 4d c8          	mov    -0x38(%rbp),%rcx
 111be42:	48 89 08             	mov    %rcx,(%rax)
 111be45:	48 8b 4d d0          	mov    -0x30(%rbp),%rcx
 111be49:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111be4d:	48 8b 4d d8          	mov    -0x28(%rbp),%rcx
 111be51:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111be55:	e9 ca 00 00 00       	jmp    111bf24 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x2c4>
 111be5a:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 111be60:	eb 0e                	jmp    111be70 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x210>
 111be62:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 111be68:	eb 06                	jmp    111be70 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x210>
 111be6a:	41 ba 00 00 00 00    	mov    $0x0,%r10d
 111be70:	49 83 f2 01          	xor    $0x1,%r10
 111be74:	75 38                	jne    111beae <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x24e>
 111be76:	49 ba fe ff ff ff ff 	movabs $0x7ffffffffffffffe,%r10
 111be7d:	ff ff 7f 
 111be80:	4d 39 d1             	cmp    %r10,%r9
 111be83:	7f 0c                	jg     111be91 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x231>
 111be85:	49 83 c1 01          	add    $0x1,%r9
 111be89:	49 21 c9             	and    %rcx,%r9
 111be8c:	e9 5f fe ff ff       	jmp    111bcf0 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x90>
 111be91:	4c 89 ca             	mov    %r9,%rdx
 111be94:	48 89 f7             	mov    %rsi,%rdi
 111be97:	41 b8 40 00 00 00    	mov    $0x40,%r8d
 111be9d:	b9 01 00 00 00       	mov    $0x1,%ecx
 111bea2:	be 00 00 00 00       	mov    $0x0,%esi
 111bea7:	e8 e4 f6 03 00       	call   115b590 <myl_qbe_fail_overflow_op>
 111beac:	0f 0b                	ud2
 111beae:	48 89 f8             	mov    %rdi,%rax
 111beb1:	c7 45 e0 00 00 00 00 	movl   $0x0,-0x20(%rbp)
 111beb8:	48 8b 4d e0          	mov    -0x20(%rbp),%rcx
 111bebc:	48 89 08             	mov    %rcx,(%rax)
 111bebf:	48 8b 4d e8          	mov    -0x18(%rbp),%rcx
 111bec3:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111bec7:	48 8b 4d f0          	mov    -0x10(%rbp),%rcx
 111becb:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111becf:	eb 53                	jmp    111bf24 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x2c4>
 111bed1:	48 89 ce             	mov    %rcx,%rsi
 111bed4:	ba 20 00 00 00       	mov    $0x20,%edx
 111bed9:	e8 f2 f7 03 00       	call   115b6d0 <myl_qbe_fail_cast>
 111bede:	0f 0b                	ud2
 111bee0:	41 b8 40 00 00 00    	mov    $0x40,%r8d
 111bee6:	b9 01 00 00 00       	mov    $0x1,%ecx
 111beeb:	48 89 f2             	mov    %rsi,%rdx
 111beee:	be 01 00 00 00       	mov    $0x1,%esi
 111bef3:	e8 98 f6 03 00       	call   115b590 <myl_qbe_fail_overflow_op>
 111bef8:	0f 0b                	ud2
 111befa:	ba 40 01 00 00       	mov    $0x140,%edx
 111beff:	e8 cc f7 03 00       	call   115b6d0 <myl_qbe_fail_cast>
 111bf04:	0f 0b                	ud2
 111bf06:	c7 45 e0 00 00 00 00 	movl   $0x0,-0x20(%rbp)
 111bf0d:	48 8b 4d e0          	mov    -0x20(%rbp),%rcx
 111bf11:	48 89 08             	mov    %rcx,(%rax)
 111bf14:	48 8b 4d e8          	mov    -0x18(%rbp),%rcx
 111bf18:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111bf1c:	48 8b 4d f0          	mov    -0x10(%rbp),%rcx
 111bf20:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111bf24:	5b                   	pop    %rbx
 111bf25:	c9                   	leave
 111bf26:	c3                   	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
