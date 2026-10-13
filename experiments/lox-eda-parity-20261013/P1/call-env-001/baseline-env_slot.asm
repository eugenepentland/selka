
.tmp/lox-eda-parity/P1/call-env-001/baseline-lox:     file format elf64-x86-64


Disassembly of section .text:

000000000106c7f0 <my.heap::env_slot>:
 106c7f0:	50                   	push   %rax
 106c7f1:	48 8b 0f             	mov    (%rdi),%rcx
 106c7f4:	48 8b 41 08          	mov    0x8(%rcx),%rax
 106c7f8:	48 39 c6             	cmp    %rax,%rsi
 106c7fb:	73 38                	jae    106c835 <my.heap::env_slot+0x45>
 106c7fd:	48 89 f7             	mov    %rsi,%rdi
 106c800:	48 6b f7 38          	imul   $0x38,%rdi,%rsi
 106c804:	8b 44 31 20          	mov    0x20(%rcx,%rsi,1),%eax
 106c808:	83 f8 09             	cmp    $0x9,%eax
 106c80b:	75 6d                	jne    106c87a <my.heap::env_slot+0x8a>
 106c80d:	48 8d 04 31          	lea    (%rcx,%rsi,1),%rax
 106c811:	48 83 c0 20          	add    $0x20,%rax
 106c815:	48 8b 48 10          	mov    0x10(%rax),%rcx
 106c819:	48 8b 41 08          	mov    0x8(%rcx),%rax
 106c81d:	48 39 c2             	cmp    %rax,%rdx
 106c820:	73 34                	jae    106c856 <my.heap::env_slot+0x66>
 106c822:	48 89 d6             	mov    %rdx,%rsi
 106c825:	48 c1 e6 04          	shl    $0x4,%rsi
 106c829:	0f b6 44 31 20       	movzbl 0x20(%rcx,%rsi,1),%eax
 106c82e:	48 8b 54 31 28       	mov    0x28(%rcx,%rsi,1),%rdx
 106c833:	59                   	pop    %rcx
 106c834:	c3                   	ret
 106c835:	48 89 f7             	mov    %rsi,%rdi
 106c838:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106c83c:	48 21 c7             	and    %rax,%rdi
 106c83f:	48 01 f7             	add    %rsi,%rdi
 106c842:	48 39 c7             	cmp    %rax,%rdi
 106c845:	72 b9                	jb     106c800 <my.heap::env_slot+0x10>
 106c847:	48 8d 3d 32 9d 01 00 	lea    0x19d32(%rip),%rdi        # 1086580 <core_durable_error.verbs+0x6570>
 106c84e:	48 89 c2             	mov    %rax,%rdx
 106c851:	e8 ea 83 fb ff       	call   1024c40 <myl_core_trap>
 106c856:	48 89 d6             	mov    %rdx,%rsi
 106c859:	48 c1 fe 3f          	sar    $0x3f,%rsi
 106c85d:	48 21 c6             	and    %rax,%rsi
 106c860:	48 01 d6             	add    %rdx,%rsi
 106c863:	48 39 c6             	cmp    %rax,%rsi
 106c866:	72 bd                	jb     106c825 <my.heap::env_slot+0x35>
 106c868:	48 8d 3d 41 9d 01 00 	lea    0x19d41(%rip),%rdi        # 10865b0 <core_durable_error.verbs+0x65a0>
 106c86f:	48 89 d6             	mov    %rdx,%rsi
 106c872:	48 89 c2             	mov    %rax,%rdx
 106c875:	e8 c6 83 fb ff       	call   1024c40 <myl_core_trap>
 106c87a:	73 7e                	jae    106c8fa <my.heap::env_slot+0x10a>
 106c87c:	89 c0                	mov    %eax,%eax
 106c87e:	48 8d 0d c7 b3 f9 ff 	lea    -0x64c39(%rip),%rcx        # 1007c4c <core_number_pairs+0x9ec>
 106c885:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 106c889:	48 01 c8             	add    %rcx,%rax
 106c88c:	ff e0                	jmp    *%rax
 106c88e:	48 8d 3d 4b 9d 01 00 	lea    0x19d4b(%rip),%rdi        # 10865e0 <core_durable_error.verbs+0x65d0>
 106c895:	e8 26 d7 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c89a:	48 8d 3d ff 9d 01 00 	lea    0x19dff(%rip),%rdi        # 10866a0 <core_durable_error.verbs+0x6690>
 106c8a1:	e8 1a d7 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c8a6:	48 8d 3d 93 9d 01 00 	lea    0x19d93(%rip),%rdi        # 1086640 <core_durable_error.verbs+0x6630>
 106c8ad:	e8 0e d7 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c8b2:	48 8d 3d b7 9d 01 00 	lea    0x19db7(%rip),%rdi        # 1086670 <core_durable_error.verbs+0x6660>
 106c8b9:	e8 02 d7 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c8be:	48 8d 3d 6b 9e 01 00 	lea    0x19e6b(%rip),%rdi        # 1086730 <core_durable_error.verbs+0x6720>
 106c8c5:	e8 f6 d6 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c8ca:	48 8d 3d 3f 9d 01 00 	lea    0x19d3f(%rip),%rdi        # 1086610 <core_durable_error.verbs+0x6600>
 106c8d1:	e8 ea d6 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c8d6:	48 8d 3d f3 9d 01 00 	lea    0x19df3(%rip),%rdi        # 10866d0 <core_durable_error.verbs+0x66c0>
 106c8dd:	e8 de d6 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c8e2:	48 8d 3d 17 9e 01 00 	lea    0x19e17(%rip),%rdi        # 1086700 <core_durable_error.verbs+0x66f0>
 106c8e9:	e8 d2 d6 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c8ee:	48 8d 3d 6b 9e 01 00 	lea    0x19e6b(%rip),%rdi        # 1086760 <core_durable_error.verbs+0x6750>
 106c8f5:	e8 c6 d6 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c8fa:	48 8d 3d 8f 9e 01 00 	lea    0x19e8f(%rip),%rdi        # 1086790 <core_durable_error.verbs+0x6780>
 106c901:	e8 ba d6 fb ff       	call   1029fc0 <myl_core_assert_fail>
