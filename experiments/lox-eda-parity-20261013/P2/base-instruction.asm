
.tmp/lox-eda-parity/P2/base:     file format elf64-x86-64


Disassembly of section .text:

000000000106ad30 <my.heap::function_instruction>:
 106ad30:	50                   	push   %rax
 106ad31:	48 8b 0f             	mov    (%rdi),%rcx
 106ad34:	48 8b 41 08          	mov    0x8(%rcx),%rax
 106ad38:	48 39 c6             	cmp    %rax,%rsi
 106ad3b:	73 2f                	jae    106ad6c <my.heap::function_instruction+0x3c>
 106ad3d:	48 89 f7             	mov    %rsi,%rdi
 106ad40:	48 6b f7 38          	imul   $0x38,%rdi,%rsi
 106ad44:	8b 44 31 20          	mov    0x20(%rcx,%rsi,1),%eax
 106ad48:	83 f8 02             	cmp    $0x2,%eax
 106ad4b:	75 64                	jne    106adb1 <my.heap::function_instruction+0x81>
 106ad4d:	48 8d 04 31          	lea    (%rcx,%rsi,1),%rax
 106ad51:	48 83 c0 20          	add    $0x20,%rax
 106ad55:	48 8b 48 18          	mov    0x18(%rax),%rcx
 106ad59:	48 8b 41 08          	mov    0x8(%rcx),%rax
 106ad5d:	48 39 c2             	cmp    %rax,%rdx
 106ad60:	73 2b                	jae    106ad8d <my.heap::function_instruction+0x5d>
 106ad62:	48 89 d6             	mov    %rdx,%rsi
 106ad65:	48 8b 44 f1 20       	mov    0x20(%rcx,%rsi,8),%rax
 106ad6a:	59                   	pop    %rcx
 106ad6b:	c3                   	ret
 106ad6c:	48 89 f7             	mov    %rsi,%rdi
 106ad6f:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106ad73:	48 21 c7             	and    %rax,%rdi
 106ad76:	48 01 f7             	add    %rsi,%rdi
 106ad79:	48 39 c7             	cmp    %rax,%rdi
 106ad7c:	72 c2                	jb     106ad40 <my.heap::function_instruction+0x10>
 106ad7e:	48 8d 3d 5b a2 01 00 	lea    0x1a25b(%rip),%rdi        # 1084fe0 <core_durable_error.verbs+0x3f90>
 106ad85:	48 89 c2             	mov    %rax,%rdx
 106ad88:	e8 f3 a7 fb ff       	call   1025580 <myl_core_trap>
 106ad8d:	48 89 d6             	mov    %rdx,%rsi
 106ad90:	48 c1 fe 3f          	sar    $0x3f,%rsi
 106ad94:	48 21 c6             	and    %rax,%rsi
 106ad97:	48 01 d6             	add    %rdx,%rsi
 106ad9a:	48 39 c6             	cmp    %rax,%rsi
 106ad9d:	72 c6                	jb     106ad65 <my.heap::function_instruction+0x35>
 106ad9f:	48 8d 3d 6a a2 01 00 	lea    0x1a26a(%rip),%rdi        # 1085010 <core_durable_error.verbs+0x3fc0>
 106ada6:	48 89 d6             	mov    %rdx,%rsi
 106ada9:	48 89 c2             	mov    %rax,%rdx
 106adac:	e8 cf a7 fb ff       	call   1025580 <myl_core_trap>
 106adb1:	83 f8 09             	cmp    $0x9,%eax
 106adb4:	77 7e                	ja     106ae34 <my.heap::function_instruction+0x104>
 106adb6:	89 c0                	mov    %eax,%eax
 106adb8:	48 8d 0d b9 cd f9 ff 	lea    -0x63247(%rip),%rcx        # 1007b78 <core_number_pairs+0x918>
 106adbf:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 106adc3:	48 01 c8             	add    %rcx,%rax
 106adc6:	ff e0                	jmp    *%rax
 106adc8:	48 8d 3d 71 a2 01 00 	lea    0x1a271(%rip),%rdi        # 1085040 <core_durable_error.verbs+0x3ff0>
 106adcf:	e8 2c fb fb ff       	call   102a900 <myl_core_assert_fail>
 106add4:	48 8d 3d 95 a2 01 00 	lea    0x1a295(%rip),%rdi        # 1085070 <core_durable_error.verbs+0x4020>
 106addb:	e8 20 fb fb ff       	call   102a900 <myl_core_assert_fail>
 106ade0:	48 8d 3d 49 a3 01 00 	lea    0x1a349(%rip),%rdi        # 1085130 <core_durable_error.verbs+0x40e0>
 106ade7:	e8 14 fb fb ff       	call   102a900 <myl_core_assert_fail>
 106adec:	48 8d 3d ad a2 01 00 	lea    0x1a2ad(%rip),%rdi        # 10850a0 <core_durable_error.verbs+0x4050>
 106adf3:	e8 08 fb fb ff       	call   102a900 <myl_core_assert_fail>
 106adf8:	48 8d 3d d1 a2 01 00 	lea    0x1a2d1(%rip),%rdi        # 10850d0 <core_durable_error.verbs+0x4080>
 106adff:	e8 fc fa fb ff       	call   102a900 <myl_core_assert_fail>
 106ae04:	48 8d 3d 55 a3 01 00 	lea    0x1a355(%rip),%rdi        # 1085160 <core_durable_error.verbs+0x4110>
 106ae0b:	e8 f0 fa fb ff       	call   102a900 <myl_core_assert_fail>
 106ae10:	48 8d 3d e9 a2 01 00 	lea    0x1a2e9(%rip),%rdi        # 1085100 <core_durable_error.verbs+0x40b0>
 106ae17:	e8 e4 fa fb ff       	call   102a900 <myl_core_assert_fail>
 106ae1c:	48 8d 3d 6d a3 01 00 	lea    0x1a36d(%rip),%rdi        # 1085190 <core_durable_error.verbs+0x4140>
 106ae23:	e8 d8 fa fb ff       	call   102a900 <myl_core_assert_fail>
 106ae28:	48 8d 3d 91 a3 01 00 	lea    0x1a391(%rip),%rdi        # 10851c0 <core_durable_error.verbs+0x4170>
 106ae2f:	e8 cc fa fb ff       	call   102a900 <myl_core_assert_fail>
 106ae34:	48 8d 3d b5 a3 01 00 	lea    0x1a3b5(%rip),%rdi        # 10851f0 <core_durable_error.verbs+0x41a0>
 106ae3b:	e8 c0 fa fb ff       	call   102a900 <myl_core_assert_fail>

Disassembly of section .plt:
