
.tmp/lox-eda-parity/P1/call-env-001/candidate-lox:     file format elf64-x86-64


Disassembly of section .text:

000000000106c870 <my.heap::env_slot>:
 106c870:	50                   	push   %rax
 106c871:	48 8b 0f             	mov    (%rdi),%rcx
 106c874:	48 8b 41 08          	mov    0x8(%rcx),%rax
 106c878:	48 39 c6             	cmp    %rax,%rsi
 106c87b:	73 38                	jae    106c8b5 <my.heap::env_slot+0x45>
 106c87d:	48 89 f7             	mov    %rsi,%rdi
 106c880:	48 6b f7 38          	imul   $0x38,%rdi,%rsi
 106c884:	8b 44 31 20          	mov    0x20(%rcx,%rsi,1),%eax
 106c888:	83 f8 09             	cmp    $0x9,%eax
 106c88b:	75 6d                	jne    106c8fa <my.heap::env_slot+0x8a>
 106c88d:	48 8d 04 31          	lea    (%rcx,%rsi,1),%rax
 106c891:	48 83 c0 20          	add    $0x20,%rax
 106c895:	48 8b 48 10          	mov    0x10(%rax),%rcx
 106c899:	48 8b 41 08          	mov    0x8(%rcx),%rax
 106c89d:	48 39 c2             	cmp    %rax,%rdx
 106c8a0:	73 34                	jae    106c8d6 <my.heap::env_slot+0x66>
 106c8a2:	48 89 d6             	mov    %rdx,%rsi
 106c8a5:	48 c1 e6 04          	shl    $0x4,%rsi
 106c8a9:	0f b6 44 31 20       	movzbl 0x20(%rcx,%rsi,1),%eax
 106c8ae:	48 8b 54 31 28       	mov    0x28(%rcx,%rsi,1),%rdx
 106c8b3:	59                   	pop    %rcx
 106c8b4:	c3                   	ret
 106c8b5:	48 89 f7             	mov    %rsi,%rdi
 106c8b8:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106c8bc:	48 21 c7             	and    %rax,%rdi
 106c8bf:	48 01 f7             	add    %rsi,%rdi
 106c8c2:	48 39 c7             	cmp    %rax,%rdi
 106c8c5:	72 b9                	jb     106c880 <my.heap::env_slot+0x10>
 106c8c7:	48 8d 3d b2 9f 01 00 	lea    0x19fb2(%rip),%rdi        # 1086880 <core_durable_error.verbs+0x6570>
 106c8ce:	48 89 c2             	mov    %rax,%rdx
 106c8d1:	e8 ea 84 fb ff       	call   1024dc0 <myl_core_trap>
 106c8d6:	48 89 d6             	mov    %rdx,%rsi
 106c8d9:	48 c1 fe 3f          	sar    $0x3f,%rsi
 106c8dd:	48 21 c6             	and    %rax,%rsi
 106c8e0:	48 01 d6             	add    %rdx,%rsi
 106c8e3:	48 39 c6             	cmp    %rax,%rsi
 106c8e6:	72 bd                	jb     106c8a5 <my.heap::env_slot+0x35>
 106c8e8:	48 8d 3d c1 9f 01 00 	lea    0x19fc1(%rip),%rdi        # 10868b0 <core_durable_error.verbs+0x65a0>
 106c8ef:	48 89 d6             	mov    %rdx,%rsi
 106c8f2:	48 89 c2             	mov    %rax,%rdx
 106c8f5:	e8 c6 84 fb ff       	call   1024dc0 <myl_core_trap>
 106c8fa:	73 7e                	jae    106c97a <my.heap::env_slot+0x10a>
 106c8fc:	89 c0                	mov    %eax,%eax
 106c8fe:	48 8d 0d 47 b3 f9 ff 	lea    -0x64cb9(%rip),%rcx        # 1007c4c <core_number_pairs+0x9ec>
 106c905:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 106c909:	48 01 c8             	add    %rcx,%rax
 106c90c:	ff e0                	jmp    *%rax
 106c90e:	48 8d 3d cb 9f 01 00 	lea    0x19fcb(%rip),%rdi        # 10868e0 <core_durable_error.verbs+0x65d0>
 106c915:	e8 26 d8 fb ff       	call   102a140 <myl_core_assert_fail>
 106c91a:	48 8d 3d 7f a0 01 00 	lea    0x1a07f(%rip),%rdi        # 10869a0 <core_durable_error.verbs+0x6690>
 106c921:	e8 1a d8 fb ff       	call   102a140 <myl_core_assert_fail>
 106c926:	48 8d 3d 13 a0 01 00 	lea    0x1a013(%rip),%rdi        # 1086940 <core_durable_error.verbs+0x6630>
 106c92d:	e8 0e d8 fb ff       	call   102a140 <myl_core_assert_fail>
 106c932:	48 8d 3d 37 a0 01 00 	lea    0x1a037(%rip),%rdi        # 1086970 <core_durable_error.verbs+0x6660>
 106c939:	e8 02 d8 fb ff       	call   102a140 <myl_core_assert_fail>
 106c93e:	48 8d 3d eb a0 01 00 	lea    0x1a0eb(%rip),%rdi        # 1086a30 <core_durable_error.verbs+0x6720>
 106c945:	e8 f6 d7 fb ff       	call   102a140 <myl_core_assert_fail>
 106c94a:	48 8d 3d bf 9f 01 00 	lea    0x19fbf(%rip),%rdi        # 1086910 <core_durable_error.verbs+0x6600>
 106c951:	e8 ea d7 fb ff       	call   102a140 <myl_core_assert_fail>
 106c956:	48 8d 3d 73 a0 01 00 	lea    0x1a073(%rip),%rdi        # 10869d0 <core_durable_error.verbs+0x66c0>
 106c95d:	e8 de d7 fb ff       	call   102a140 <myl_core_assert_fail>
 106c962:	48 8d 3d 97 a0 01 00 	lea    0x1a097(%rip),%rdi        # 1086a00 <core_durable_error.verbs+0x66f0>
 106c969:	e8 d2 d7 fb ff       	call   102a140 <myl_core_assert_fail>
 106c96e:	48 8d 3d eb a0 01 00 	lea    0x1a0eb(%rip),%rdi        # 1086a60 <core_durable_error.verbs+0x6750>
 106c975:	e8 c6 d7 fb ff       	call   102a140 <myl_core_assert_fail>
 106c97a:	48 8d 3d 0f a1 01 00 	lea    0x1a10f(%rip),%rdi        # 1086a90 <core_durable_error.verbs+0x6780>
 106c981:	e8 ba d7 fb ff       	call   102a140 <myl_core_assert_fail>
