
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-001/lox/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

0000000001063790 <my.vm::read_short>:
 1063790:	41 56                	push   %r14
 1063792:	53                   	push   %rbx
 1063793:	50                   	push   %rax
 1063794:	4d 89 c2             	mov    %r8,%r10
 1063797:	49 83 c2 02          	add    $0x2,%r10
 106379b:	0f 80 6f 01 00 00    	jo     1063910 <my.vm::read_short+0x180>
 10637a1:	4c 8b 1e             	mov    (%rsi),%r11
 10637a4:	49 8b 43 08          	mov    0x8(%r11),%rax
 10637a8:	48 89 ce             	mov    %rcx,%rsi
 10637ab:	48 39 c1             	cmp    %rax,%rcx
 10637ae:	0f 83 bf 00 00 00    	jae    1063873 <my.vm::read_short+0xe3>
 10637b4:	4c 6b c6 38          	imul   $0x38,%rsi,%r8
 10637b8:	43 83 7c 03 20 02    	cmpl   $0x2,0x20(%r11,%r8,1)
 10637be:	0f 85 60 01 00 00    	jne    1063924 <my.vm::read_short+0x194>
 10637c4:	49 8d 72 fe          	lea    -0x2(%r10),%rsi
 10637c8:	4d 01 d8             	add    %r11,%r8
 10637cb:	49 83 c0 20          	add    $0x20,%r8
 10637cf:	49 8b 58 18          	mov    0x18(%r8),%rbx
 10637d3:	4c 8b 43 08          	mov    0x8(%rbx),%r8
 10637d7:	4c 39 c6             	cmp    %r8,%rsi
 10637da:	0f 83 bb 00 00 00    	jae    106389b <my.vm::read_short+0x10b>
 10637e0:	49 89 f6             	mov    %rsi,%r14
 10637e3:	4a 8b 74 f3 20       	mov    0x20(%rbx,%r14,8),%rsi
 10637e8:	49 b8 00 00 00 00 00 	movabs $0xff80000000000000,%r8
 10637ef:	00 80 ff 
 10637f2:	49 01 f0             	add    %rsi,%r8
 10637f5:	49 c1 e8 38          	shr    $0x38,%r8
 10637f9:	41 81 f8 fe 00 00 00 	cmp    $0xfe,%r8d
 1063800:	0f 86 2a 01 00 00    	jbe    1063930 <my.vm::read_short+0x1a0>
 1063806:	49 89 c8             	mov    %rcx,%r8
 1063809:	48 39 c1             	cmp    %rax,%rcx
 106380c:	0f 83 af 00 00 00    	jae    10638c1 <my.vm::read_short+0x131>
 1063812:	49 83 c3 20          	add    $0x20,%r11
 1063816:	4d 6b c0 38          	imul   $0x38,%r8,%r8
 106381a:	43 83 3c 03 02       	cmpl   $0x2,(%r11,%r8,1)
 106381f:	0f 85 1c 01 00 00    	jne    1063941 <my.vm::read_short+0x1b1>
 1063825:	49 8d 42 ff          	lea    -0x1(%r10),%rax
 1063829:	4d 01 c3             	add    %r8,%r11
 106382c:	4d 8b 5b 18          	mov    0x18(%r11),%r11
 1063830:	4d 8b 43 08          	mov    0x8(%r11),%r8
 1063834:	4c 39 c0             	cmp    %r8,%rax
 1063837:	0f 83 ac 00 00 00    	jae    10638e9 <my.vm::read_short+0x159>
 106383d:	48 89 c3             	mov    %rax,%rbx
 1063840:	48 c1 e6 08          	shl    $0x8,%rsi
 1063844:	49 8b 44 db 20       	mov    0x20(%r11,%rbx,8),%rax
 1063849:	49 89 f0             	mov    %rsi,%r8
 106384c:	49 01 c0             	add    %rax,%r8
 106384f:	0f 80 f8 00 00 00    	jo     106394d <my.vm::read_short+0x1bd>
 1063855:	4c 89 07             	mov    %r8,(%rdi)
 1063858:	48 89 57 08          	mov    %rdx,0x8(%rdi)
 106385c:	48 89 4f 10          	mov    %rcx,0x10(%rdi)
 1063860:	4c 89 57 18          	mov    %r10,0x18(%rdi)
 1063864:	4c 89 4f 20          	mov    %r9,0x20(%rdi)
 1063868:	48 89 f8             	mov    %rdi,%rax
 106386b:	48 83 c4 08          	add    $0x8,%rsp
 106386f:	5b                   	pop    %rbx
 1063870:	41 5e                	pop    %r14
 1063872:	c3                   	ret
 1063873:	48 89 ce             	mov    %rcx,%rsi
 1063876:	48 c1 fe 3f          	sar    $0x3f,%rsi
 106387a:	48 21 c6             	and    %rax,%rsi
 106387d:	48 01 ce             	add    %rcx,%rsi
 1063880:	48 39 c6             	cmp    %rax,%rsi
 1063883:	0f 82 2b ff ff ff    	jb     10637b4 <my.vm::read_short+0x24>
 1063889:	48 8d 3d d0 01 02 00 	lea    0x201d0(%rip),%rdi        # 1083a60 <core_durable_error.verbs+0x3a50>
 1063890:	48 89 ce             	mov    %rcx,%rsi
 1063893:	48 89 c2             	mov    %rax,%rdx
 1063896:	e8 a5 13 fc ff       	call   1024c40 <myl_core_trap>
 106389b:	45 31 f6             	xor    %r14d,%r14d
 106389e:	49 83 fa 02          	cmp    $0x2,%r10
 10638a2:	4d 0f 4c f0          	cmovl  %r8,%r14
 10638a6:	49 01 f6             	add    %rsi,%r14
 10638a9:	4d 39 c6             	cmp    %r8,%r14
 10638ac:	0f 82 31 ff ff ff    	jb     10637e3 <my.vm::read_short+0x53>
 10638b2:	48 8d 3d 07 02 02 00 	lea    0x20207(%rip),%rdi        # 1083ac0 <core_durable_error.verbs+0x3ab0>
 10638b9:	4c 89 c2             	mov    %r8,%rdx
 10638bc:	e8 7f 13 fc ff       	call   1024c40 <myl_core_trap>
 10638c1:	49 89 c8             	mov    %rcx,%r8
 10638c4:	49 c1 f8 3f          	sar    $0x3f,%r8
 10638c8:	49 21 c0             	and    %rax,%r8
 10638cb:	49 01 c8             	add    %rcx,%r8
 10638ce:	49 39 c0             	cmp    %rax,%r8
 10638d1:	0f 82 3b ff ff ff    	jb     1063812 <my.vm::read_short+0x82>
 10638d7:	48 8d 3d 82 01 02 00 	lea    0x20182(%rip),%rdi        # 1083a60 <core_durable_error.verbs+0x3a50>
 10638de:	48 89 ce             	mov    %rcx,%rsi
 10638e1:	48 89 c2             	mov    %rax,%rdx
 10638e4:	e8 57 13 fc ff       	call   1024c40 <myl_core_trap>
 10638e9:	31 db                	xor    %ebx,%ebx
 10638eb:	4d 85 d2             	test   %r10,%r10
 10638ee:	49 0f 4e d8          	cmovle %r8,%rbx
 10638f2:	48 01 c3             	add    %rax,%rbx
 10638f5:	4c 39 c3             	cmp    %r8,%rbx
 10638f8:	0f 82 42 ff ff ff    	jb     1063840 <my.vm::read_short+0xb0>
 10638fe:	48 8d 3d bb 01 02 00 	lea    0x201bb(%rip),%rdi        # 1083ac0 <core_durable_error.verbs+0x3ab0>
 1063905:	48 89 c6             	mov    %rax,%rsi
 1063908:	4c 89 c2             	mov    %r8,%rdx
 106390b:	e8 30 13 fc ff       	call   1024c40 <myl_core_trap>
 1063910:	48 8d 3d 79 ec 01 00 	lea    0x1ec79(%rip),%rdi        # 1082590 <core_durable_error.verbs+0x2580>
 1063917:	ba 02 00 00 00       	mov    $0x2,%edx
 106391c:	4c 89 c6             	mov    %r8,%rsi
 106391f:	e8 1c 13 fc ff       	call   1024c40 <myl_core_trap>
 1063924:	48 8d 3d 65 01 02 00 	lea    0x20165(%rip),%rdi        # 1083a90 <core_durable_error.verbs+0x3a80>
 106392b:	e8 90 66 fc ff       	call   1029fc0 <myl_core_assert_fail>
 1063930:	48 8d 3d 89 ec 01 00 	lea    0x1ec89(%rip),%rdi        # 10825c0 <core_durable_error.verbs+0x25b0>
 1063937:	ba 00 01 00 00       	mov    $0x100,%edx
 106393c:	e8 ff 12 fc ff       	call   1024c40 <myl_core_trap>
 1063941:	48 8d 3d 48 01 02 00 	lea    0x20148(%rip),%rdi        # 1083a90 <core_durable_error.verbs+0x3a80>
 1063948:	e8 73 66 fc ff       	call   1029fc0 <myl_core_assert_fail>
 106394d:	48 8d 3d 9c ec 01 00 	lea    0x1ec9c(%rip),%rdi        # 10825f0 <core_durable_error.verbs+0x25e0>
 1063954:	48 89 c2             	mov    %rax,%rdx
 1063957:	e8 e4 12 fc ff       	call   1024c40 <myl_core_trap>

Disassembly of section .plt:
