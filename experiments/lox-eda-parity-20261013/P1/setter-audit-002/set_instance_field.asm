
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/lox/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

0000000001069a90 <my.heap::set_instance_field>:
 1069a90:	41 57                	push   %r15
 1069a92:	41 56                	push   %r14
 1069a94:	41 54                	push   %r12
 1069a96:	53                   	push   %rbx
 1069a97:	50                   	push   %rax
 1069a98:	48 85 f6             	test   %rsi,%rsi
 1069a9b:	0f 88 d9 00 00 00    	js     1069b7a <my.heap::set_instance_field+0xea>
 1069aa1:	48 89 f3             	mov    %rsi,%rbx
 1069aa4:	4c 8b 27             	mov    (%rdi),%r12
 1069aa7:	49 3b 74 24 08       	cmp    0x8(%r12),%rsi
 1069aac:	0f 8d c8 00 00 00    	jge    1069b7a <my.heap::set_instance_field+0xea>
 1069ab2:	48 6b c3 38          	imul   $0x38,%rbx,%rax
 1069ab6:	41 83 7c 04 20 07    	cmpl   $0x7,0x20(%r12,%rax,1)
 1069abc:	0f 85 c4 00 00 00    	jne    1069b86 <my.heap::set_instance_field+0xf6>
 1069ac2:	4d 8d 34 04          	lea    (%r12,%rax,1),%r14
 1069ac6:	49 83 c6 20          	add    $0x20,%r14
 1069aca:	4d 8b 7e 08          	mov    0x8(%r14),%r15
 1069ace:	49 8b 7e 10          	mov    0x10(%r14),%rdi
 1069ad2:	49 8b 76 18          	mov    0x18(%r14),%rsi
 1069ad6:	49 c7 06 00 00 00 00 	movq   $0x0,(%r14)
 1069add:	45 0f b6 c0          	movzbl %r8b,%r8d
 1069ae1:	e8 da f8 ff ff       	call   10693c0 <my.table::set>
 1069ae6:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 1069aeb:	48 39 c3             	cmp    %rax,%rbx
 1069aee:	73 78                	jae    1069b68 <my.heap::set_instance_field+0xd8>
 1069af0:	41 0f b6 36          	movzbl (%r14),%esi
 1069af4:	49 8b 7e 08          	mov    0x8(%r14),%rdi
 1069af8:	4d 8b 46 10          	mov    0x10(%r14),%r8
 1069afc:	49 8b 46 18          	mov    0x18(%r14),%rax
 1069b00:	49 8b 5e 20          	mov    0x20(%r14),%rbx
 1069b04:	4d 8b 66 28          	mov    0x28(%r14),%r12
 1069b08:	49 c7 06 07 00 00 00 	movq   $0x7,(%r14)
 1069b0f:	4d 89 7e 08          	mov    %r15,0x8(%r14)
 1069b13:	49 89 56 10          	mov    %rdx,0x10(%r14)
 1069b17:	49 89 4e 18          	mov    %rcx,0x18(%r14)
 1069b1b:	83 fe 09             	cmp    $0x9,%esi
 1069b1e:	77 3c                	ja     1069b5c <my.heap::set_instance_field+0xcc>
 1069b20:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 1069b25:	0f a3 f1             	bt     %esi,%ecx
 1069b28:	73 13                	jae    1069b3d <my.heap::set_instance_field+0xad>
 1069b2a:	4c 89 c7             	mov    %r8,%rdi
 1069b2d:	48 83 c4 08          	add    $0x8,%rsp
 1069b31:	5b                   	pop    %rbx
 1069b32:	41 5c                	pop    %r12
 1069b34:	41 5e                	pop    %r14
 1069b36:	41 5f                	pop    %r15
 1069b38:	e9 43 9e fb ff       	jmp    1023980 <myl_core_drop_owned>
 1069b3d:	83 fe 01             	cmp    $0x1,%esi
 1069b40:	74 eb                	je     1069b2d <my.heap::set_instance_field+0x9d>
 1069b42:	83 fe 02             	cmp    $0x2,%esi
 1069b45:	75 15                	jne    1069b5c <my.heap::set_instance_field+0xcc>
 1069b47:	48 89 c7             	mov    %rax,%rdi
 1069b4a:	e8 31 9e fb ff       	call   1023980 <myl_core_drop_owned>
 1069b4f:	48 89 df             	mov    %rbx,%rdi
 1069b52:	e8 29 9e fb ff       	call   1023980 <myl_core_drop_owned>
 1069b57:	4c 89 e7             	mov    %r12,%rdi
 1069b5a:	eb d1                	jmp    1069b2d <my.heap::set_instance_field+0x9d>
 1069b5c:	48 83 c4 08          	add    $0x8,%rsp
 1069b60:	5b                   	pop    %rbx
 1069b61:	41 5c                	pop    %r12
 1069b63:	41 5e                	pop    %r14
 1069b65:	41 5f                	pop    %r15
 1069b67:	c3                   	ret
 1069b68:	48 8d 3d 01 a4 01 00 	lea    0x1a401(%rip),%rdi        # 1083f70 <core_durable_error.verbs+0x4860>
 1069b6f:	48 89 de             	mov    %rbx,%rsi
 1069b72:	48 89 c2             	mov    %rax,%rdx
 1069b75:	e8 86 ab fb ff       	call   1024700 <myl_core_trap>
 1069b7a:	48 8d 3d bf df 01 00 	lea    0x1dfbf(%rip),%rdi        # 1087b40 <core_durable_error.verbs+0x8430>
 1069b81:	e8 fa fe fb ff       	call   1029a80 <myl_core_assert_fail>
 1069b86:	48 8d 3d 33 cf 01 00 	lea    0x1cf33(%rip),%rdi        # 1086ac0 <core_durable_error.verbs+0x73b0>
 1069b8d:	e8 ee fe fb ff       	call   1029a80 <myl_core_assert_fail>

Disassembly of section .plt:
