
.tmp/lox-eda-parity/P1/call-env-001/candidate-lox:     file format elf64-x86-64


Disassembly of section .text:

0000000001070e30 <my.heap::env_enclosing>:
 1070e30:	50                   	push   %rax
 1070e31:	48 8b 07             	mov    (%rdi),%rax
 1070e34:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1070e38:	48 39 d6             	cmp    %rdx,%rsi
 1070e3b:	73 1d                	jae    1070e5a <my.heap::env_enclosing+0x2a>
 1070e3d:	48 89 f1             	mov    %rsi,%rcx
 1070e40:	48 6b d1 38          	imul   $0x38,%rcx,%rdx
 1070e44:	8b 4c 10 20          	mov    0x20(%rax,%rdx,1),%ecx
 1070e48:	83 f9 09             	cmp    $0x9,%ecx
 1070e4b:	75 2b                	jne    1070e78 <my.heap::env_enclosing+0x48>
 1070e4d:	48 01 d0             	add    %rdx,%rax
 1070e50:	48 83 c0 20          	add    $0x20,%rax
 1070e54:	48 8b 40 08          	mov    0x8(%rax),%rax
 1070e58:	59                   	pop    %rcx
 1070e59:	c3                   	ret
 1070e5a:	48 89 f1             	mov    %rsi,%rcx
 1070e5d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1070e61:	48 21 d1             	and    %rdx,%rcx
 1070e64:	48 01 f1             	add    %rsi,%rcx
 1070e67:	48 39 d1             	cmp    %rdx,%rcx
 1070e6a:	72 d4                	jb     1070e40 <my.heap::env_enclosing+0x10>
 1070e6c:	48 8d 3d 7d 74 01 00 	lea    0x1747d(%rip),%rdi        # 10882f0 <core_durable_error.verbs+0x7fe0>
 1070e73:	e8 48 3f fb ff       	call   1024dc0 <myl_core_trap>
 1070e78:	73 7e                	jae    1070ef8 <my.heap::env_enclosing+0xc8>
 1070e7a:	89 c8                	mov    %ecx,%eax
 1070e7c:	48 8d 0d f9 6e f9 ff 	lea    -0x69107(%rip),%rcx        # 1007d7c <core_number_pairs+0xb1c>
 1070e83:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 1070e87:	48 01 c8             	add    %rcx,%rax
 1070e8a:	ff e0                	jmp    *%rax
 1070e8c:	48 8d 3d 8d 74 01 00 	lea    0x1748d(%rip),%rdi        # 1088320 <core_durable_error.verbs+0x8010>
 1070e93:	e8 a8 92 fb ff       	call   102a140 <myl_core_assert_fail>
 1070e98:	48 8d 3d 41 75 01 00 	lea    0x17541(%rip),%rdi        # 10883e0 <core_durable_error.verbs+0x80d0>
 1070e9f:	e8 9c 92 fb ff       	call   102a140 <myl_core_assert_fail>
 1070ea4:	48 8d 3d d5 74 01 00 	lea    0x174d5(%rip),%rdi        # 1088380 <core_durable_error.verbs+0x8070>
 1070eab:	e8 90 92 fb ff       	call   102a140 <myl_core_assert_fail>
 1070eb0:	48 8d 3d f9 74 01 00 	lea    0x174f9(%rip),%rdi        # 10883b0 <core_durable_error.verbs+0x80a0>
 1070eb7:	e8 84 92 fb ff       	call   102a140 <myl_core_assert_fail>
 1070ebc:	48 8d 3d ad 75 01 00 	lea    0x175ad(%rip),%rdi        # 1088470 <core_durable_error.verbs+0x8160>
 1070ec3:	e8 78 92 fb ff       	call   102a140 <myl_core_assert_fail>
 1070ec8:	48 8d 3d 81 74 01 00 	lea    0x17481(%rip),%rdi        # 1088350 <core_durable_error.verbs+0x8040>
 1070ecf:	e8 6c 92 fb ff       	call   102a140 <myl_core_assert_fail>
 1070ed4:	48 8d 3d 35 75 01 00 	lea    0x17535(%rip),%rdi        # 1088410 <core_durable_error.verbs+0x8100>
 1070edb:	e8 60 92 fb ff       	call   102a140 <myl_core_assert_fail>
 1070ee0:	48 8d 3d 59 75 01 00 	lea    0x17559(%rip),%rdi        # 1088440 <core_durable_error.verbs+0x8130>
 1070ee7:	e8 54 92 fb ff       	call   102a140 <myl_core_assert_fail>
 1070eec:	48 8d 3d ad 75 01 00 	lea    0x175ad(%rip),%rdi        # 10884a0 <core_durable_error.verbs+0x8190>
 1070ef3:	e8 48 92 fb ff       	call   102a140 <myl_core_assert_fail>
 1070ef8:	48 8d 3d d1 75 01 00 	lea    0x175d1(%rip),%rdi        # 10884d0 <core_durable_error.verbs+0x81c0>
 1070eff:	e8 3c 92 fb ff       	call   102a140 <myl_core_assert_fail>
