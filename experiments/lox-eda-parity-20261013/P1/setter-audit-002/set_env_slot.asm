
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/lox/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

000000000106bd40 <my.heap::set_env_slot>:
 106bd40:	41 56                	push   %r14
 106bd42:	53                   	push   %rbx
 106bd43:	50                   	push   %rax
 106bd44:	48 85 f6             	test   %rsi,%rsi
 106bd47:	0f 88 f7 00 00 00    	js     106be44 <my.heap::set_env_slot+0x104>
 106bd4d:	48 8b 07             	mov    (%rdi),%rax
 106bd50:	48 3b 70 08          	cmp    0x8(%rax),%rsi
 106bd54:	0f 8d ea 00 00 00    	jge    106be44 <my.heap::set_env_slot+0x104>
 106bd5a:	48 6b f6 38          	imul   $0x38,%rsi,%rsi
 106bd5e:	83 7c 30 20 09       	cmpl   $0x9,0x20(%rax,%rsi,1)
 106bd63:	0f 85 e7 00 00 00    	jne    106be50 <my.heap::set_env_slot+0x110>
 106bd69:	48 01 c6             	add    %rax,%rsi
 106bd6c:	48 83 c6 20          	add    $0x20,%rsi
 106bd70:	4c 8b 4e 10          	mov    0x10(%rsi),%r9
 106bd74:	49 8b 41 08          	mov    0x8(%r9),%rax
 106bd78:	48 89 c7             	mov    %rax,%rdi
 106bd7b:	48 f7 df             	neg    %rdi
 106bd7e:	48 39 fa             	cmp    %rdi,%rdx
 106bd81:	0f 8c d5 00 00 00    	jl     106be5c <my.heap::set_env_slot+0x11c>
 106bd87:	48 39 c2             	cmp    %rax,%rdx
 106bd8a:	0f 8d cc 00 00 00    	jge    106be5c <my.heap::set_env_slot+0x11c>
 106bd90:	4c 8b 56 08          	mov    0x8(%rsi),%r10
 106bd94:	48 c7 06 00 00 00 00 	movq   $0x0,(%rsi)
 106bd9b:	73 7f                	jae    106be1c <my.heap::set_env_slot+0xdc>
 106bd9d:	48 89 d7             	mov    %rdx,%rdi
 106bda0:	48 c1 e7 04          	shl    $0x4,%rdi
 106bda4:	0f b6 c1             	movzbl %cl,%eax
 106bda7:	49 89 44 39 20       	mov    %rax,0x20(%r9,%rdi,1)
 106bdac:	4d 89 44 39 28       	mov    %r8,0x28(%r9,%rdi,1)
 106bdb1:	0f b6 0e             	movzbl (%rsi),%ecx
 106bdb4:	48 8b 7e 08          	mov    0x8(%rsi),%rdi
 106bdb8:	48 8b 56 10          	mov    0x10(%rsi),%rdx
 106bdbc:	48 8b 46 18          	mov    0x18(%rsi),%rax
 106bdc0:	48 8b 5e 20          	mov    0x20(%rsi),%rbx
 106bdc4:	4c 8b 76 28          	mov    0x28(%rsi),%r14
 106bdc8:	48 c7 06 09 00 00 00 	movq   $0x9,(%rsi)
 106bdcf:	4c 89 56 08          	mov    %r10,0x8(%rsi)
 106bdd3:	4c 89 4e 10          	mov    %r9,0x10(%rsi)
 106bdd7:	83 f9 09             	cmp    $0x9,%ecx
 106bdda:	77 38                	ja     106be14 <my.heap::set_env_slot+0xd4>
 106bddc:	be d0 02 00 00       	mov    $0x2d0,%esi
 106bde1:	0f a3 ce             	bt     %ecx,%esi
 106bde4:	73 0f                	jae    106bdf5 <my.heap::set_env_slot+0xb5>
 106bde6:	48 89 d7             	mov    %rdx,%rdi
 106bde9:	48 83 c4 08          	add    $0x8,%rsp
 106bded:	5b                   	pop    %rbx
 106bdee:	41 5e                	pop    %r14
 106bdf0:	e9 8b 7b fb ff       	jmp    1023980 <myl_core_drop_owned>
 106bdf5:	83 f9 01             	cmp    $0x1,%ecx
 106bdf8:	74 ef                	je     106bde9 <my.heap::set_env_slot+0xa9>
 106bdfa:	83 f9 02             	cmp    $0x2,%ecx
 106bdfd:	75 15                	jne    106be14 <my.heap::set_env_slot+0xd4>
 106bdff:	48 89 c7             	mov    %rax,%rdi
 106be02:	e8 79 7b fb ff       	call   1023980 <myl_core_drop_owned>
 106be07:	48 89 df             	mov    %rbx,%rdi
 106be0a:	e8 71 7b fb ff       	call   1023980 <myl_core_drop_owned>
 106be0f:	4c 89 f7             	mov    %r14,%rdi
 106be12:	eb d5                	jmp    106bde9 <my.heap::set_env_slot+0xa9>
 106be14:	48 83 c4 08          	add    $0x8,%rsp
 106be18:	5b                   	pop    %rbx
 106be19:	41 5e                	pop    %r14
 106be1b:	c3                   	ret
 106be1c:	48 89 d7             	mov    %rdx,%rdi
 106be1f:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106be23:	48 21 c7             	and    %rax,%rdi
 106be26:	48 01 d7             	add    %rdx,%rdi
 106be29:	48 39 c7             	cmp    %rax,%rdi
 106be2c:	0f 82 6e ff ff ff    	jb     106bda0 <my.heap::set_env_slot+0x60>
 106be32:	48 8d 3d 77 95 01 00 	lea    0x19577(%rip),%rdi        # 10853b0 <core_durable_error.verbs+0x5ca0>
 106be39:	48 89 d6             	mov    %rdx,%rsi
 106be3c:	48 89 c2             	mov    %rax,%rdx
 106be3f:	e8 bc 88 fb ff       	call   1024700 <myl_core_trap>
 106be44:	48 8d 3d f5 bc 01 00 	lea    0x1bcf5(%rip),%rdi        # 1087b40 <core_durable_error.verbs+0x8430>
 106be4b:	e8 30 dc fb ff       	call   1029a80 <myl_core_assert_fail>
 106be50:	48 8d 3d d9 b4 01 00 	lea    0x1b4d9(%rip),%rdi        # 1087330 <core_durable_error.verbs+0x7c20>
 106be57:	e8 24 dc fb ff       	call   1029a80 <myl_core_assert_fail>
 106be5c:	48 8d 3d fd b4 01 00 	lea    0x1b4fd(%rip),%rdi        # 1087360 <core_durable_error.verbs+0x7c50>
 106be63:	e8 18 dc fb ff       	call   1029a80 <myl_core_assert_fail>

Disassembly of section .plt:
