
.tmp/lox-eda-parity/P1/call-env-001/baseline-lox:     file format elf64-x86-64


Disassembly of section .text:

0000000001070db0 <my.heap::env_enclosing>:
 1070db0:	50                   	push   %rax
 1070db1:	48 8b 07             	mov    (%rdi),%rax
 1070db4:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1070db8:	48 39 d6             	cmp    %rdx,%rsi
 1070dbb:	73 1d                	jae    1070dda <my.heap::env_enclosing+0x2a>
 1070dbd:	48 89 f1             	mov    %rsi,%rcx
 1070dc0:	48 6b d1 38          	imul   $0x38,%rcx,%rdx
 1070dc4:	8b 4c 10 20          	mov    0x20(%rax,%rdx,1),%ecx
 1070dc8:	83 f9 09             	cmp    $0x9,%ecx
 1070dcb:	75 2b                	jne    1070df8 <my.heap::env_enclosing+0x48>
 1070dcd:	48 01 d0             	add    %rdx,%rax
 1070dd0:	48 83 c0 20          	add    $0x20,%rax
 1070dd4:	48 8b 40 08          	mov    0x8(%rax),%rax
 1070dd8:	59                   	pop    %rcx
 1070dd9:	c3                   	ret
 1070dda:	48 89 f1             	mov    %rsi,%rcx
 1070ddd:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1070de1:	48 21 d1             	and    %rdx,%rcx
 1070de4:	48 01 f1             	add    %rsi,%rcx
 1070de7:	48 39 d1             	cmp    %rdx,%rcx
 1070dea:	72 d4                	jb     1070dc0 <my.heap::env_enclosing+0x10>
 1070dec:	48 8d 3d fd 71 01 00 	lea    0x171fd(%rip),%rdi        # 1087ff0 <core_durable_error.verbs+0x7fe0>
 1070df3:	e8 48 3e fb ff       	call   1024c40 <myl_core_trap>
 1070df8:	73 7e                	jae    1070e78 <my.heap::env_enclosing+0xc8>
 1070dfa:	89 c8                	mov    %ecx,%eax
 1070dfc:	48 8d 0d 79 6f f9 ff 	lea    -0x69087(%rip),%rcx        # 1007d7c <core_number_pairs+0xb1c>
 1070e03:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 1070e07:	48 01 c8             	add    %rcx,%rax
 1070e0a:	ff e0                	jmp    *%rax
 1070e0c:	48 8d 3d 0d 72 01 00 	lea    0x1720d(%rip),%rdi        # 1088020 <core_durable_error.verbs+0x8010>
 1070e13:	e8 a8 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
 1070e18:	48 8d 3d c1 72 01 00 	lea    0x172c1(%rip),%rdi        # 10880e0 <core_durable_error.verbs+0x80d0>
 1070e1f:	e8 9c 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
 1070e24:	48 8d 3d 55 72 01 00 	lea    0x17255(%rip),%rdi        # 1088080 <core_durable_error.verbs+0x8070>
 1070e2b:	e8 90 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
 1070e30:	48 8d 3d 79 72 01 00 	lea    0x17279(%rip),%rdi        # 10880b0 <core_durable_error.verbs+0x80a0>
 1070e37:	e8 84 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
 1070e3c:	48 8d 3d 2d 73 01 00 	lea    0x1732d(%rip),%rdi        # 1088170 <core_durable_error.verbs+0x8160>
 1070e43:	e8 78 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
 1070e48:	48 8d 3d 01 72 01 00 	lea    0x17201(%rip),%rdi        # 1088050 <core_durable_error.verbs+0x8040>
 1070e4f:	e8 6c 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
 1070e54:	48 8d 3d b5 72 01 00 	lea    0x172b5(%rip),%rdi        # 1088110 <core_durable_error.verbs+0x8100>
 1070e5b:	e8 60 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
 1070e60:	48 8d 3d d9 72 01 00 	lea    0x172d9(%rip),%rdi        # 1088140 <core_durable_error.verbs+0x8130>
 1070e67:	e8 54 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
 1070e6c:	48 8d 3d 2d 73 01 00 	lea    0x1732d(%rip),%rdi        # 10881a0 <core_durable_error.verbs+0x8190>
 1070e73:	e8 48 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
 1070e78:	48 8d 3d 51 73 01 00 	lea    0x17351(%rip),%rdi        # 10881d0 <core_durable_error.verbs+0x81c0>
 1070e7f:	e8 3c 91 fb ff       	call   1029fc0 <myl_core_assert_fail>
