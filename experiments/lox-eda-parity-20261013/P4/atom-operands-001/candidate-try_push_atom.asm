
.tmp/lox-eda-parity/P4/atom-operands-001/candidate/lox:     file format elf64-x86-64


Disassembly of section .text:

000000000106f780 <my.interpreter::try_push_atom>:
 106f780:	50                   	push   %rax
 106f781:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 106f786:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 106f78a:	48 39 d0             	cmp    %rdx,%rax
 106f78d:	0f 83 92 01 00 00    	jae    106f925 <my.interpreter::try_push_atom+0x1a5>
 106f793:	48 89 c1             	mov    %rax,%rcx
 106f796:	48 6b c9 70          	imul   $0x70,%rcx,%rcx
 106f79a:	48 8d 04 0e          	lea    (%rsi,%rcx,1),%rax
 106f79e:	48 83 c0 20          	add    $0x20,%rax
 106f7a2:	8b 4c 0e 20          	mov    0x20(%rsi,%rcx,1),%ecx
 106f7a6:	83 f9 05             	cmp    $0x5,%ecx
 106f7a9:	0f 84 9e 00 00 00    	je     106f84d <my.interpreter::try_push_atom+0xcd>
 106f7af:	83 f9 0b             	cmp    $0xb,%ecx
 106f7b2:	0f 85 8e 00 00 00    	jne    106f846 <my.interpreter::try_push_atom+0xc6>
 106f7b8:	4c 8b 40 38          	mov    0x38(%rax),%r8
 106f7bc:	49 83 f8 ff          	cmp    $0xffffffffffffffff,%r8
 106f7c0:	0f 84 80 00 00 00    	je     106f846 <my.interpreter::try_push_atom+0xc6>
 106f7c6:	48 8b 70 40          	mov    0x40(%rax),%rsi
 106f7ca:	49 8b 09             	mov    (%r9),%rcx
 106f7cd:	49 8b 81 a8 00 00 00 	mov    0xa8(%r9),%rax
 106f7d4:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 106f7d8:	4d 85 c0             	test   %r8,%r8
 106f7db:	0f 8e bb 00 00 00    	jle    106f89c <my.interpreter::try_push_atom+0x11c>
 106f7e1:	4c 8d 51 20          	lea    0x20(%rcx),%r10
 106f7e5:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 106f7ec:	0f 1f 84 00 00 00 00 
 106f7f3:	00 
 106f7f4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 106f7fb:	00 00 00 00 00 
 106f800:	48 39 d0             	cmp    %rdx,%rax
 106f803:	73 20                	jae    106f825 <my.interpreter::try_push_atom+0xa5>
 106f805:	49 89 c3             	mov    %rax,%r11
 106f808:	49 6b c3 38          	imul   $0x38,%r11,%rax
 106f80c:	41 83 3c 02 09       	cmpl   $0x9,(%r10,%rax,1)
 106f811:	0f 85 be 01 00 00    	jne    106f9d5 <my.interpreter::try_push_atom+0x255>
 106f817:	4c 01 d0             	add    %r10,%rax
 106f81a:	48 8b 40 08          	mov    0x8(%rax),%rax
 106f81e:	49 ff c8             	dec    %r8
 106f821:	75 dd                	jne    106f800 <my.interpreter::try_push_atom+0x80>
 106f823:	eb 77                	jmp    106f89c <my.interpreter::try_push_atom+0x11c>
 106f825:	49 89 c3             	mov    %rax,%r11
 106f828:	49 c1 fb 3f          	sar    $0x3f,%r11
 106f82c:	49 21 d3             	and    %rdx,%r11
 106f82f:	49 01 c3             	add    %rax,%r11
 106f832:	49 39 d3             	cmp    %rdx,%r11
 106f835:	72 d1                	jb     106f808 <my.interpreter::try_push_atom+0x88>
 106f837:	48 8d 3d 62 61 01 00 	lea    0x16162(%rip),%rdi        # 10859a0 <core_durable_error.verbs+0x5cd0>
 106f83e:	48 89 c6             	mov    %rax,%rsi
 106f841:	e8 ba 4f fb ff       	call   1024800 <myl_core_trap>
 106f846:	31 c0                	xor    %eax,%eax
 106f848:	e9 d1 00 00 00       	jmp    106f91e <my.interpreter::try_push_atom+0x19e>
 106f84d:	c5 f8 10 40 08       	vmovups 0x8(%rax),%xmm0
 106f852:	49 8b 41 78          	mov    0x78(%r9),%rax
 106f856:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 106f85d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106f861:	48 89 f1             	mov    %rsi,%rcx
 106f864:	48 39 d6             	cmp    %rdx,%rsi
 106f867:	0f 83 dd 00 00 00    	jae    106f94a <my.interpreter::try_push_atom+0x1ca>
 106f86d:	48 c1 e1 04          	shl    $0x4,%rcx
 106f871:	c5 f8 54 05 67 4b f9 	vandps -0x6b499(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 106f878:	ff 
 106f879:	c5 f8 11 44 08 20    	vmovups %xmm0,0x20(%rax,%rcx,1)
 106f87f:	48 89 f0             	mov    %rsi,%rax
 106f882:	48 ff c0             	inc    %rax
 106f885:	0f 81 8a 00 00 00    	jno    106f915 <my.interpreter::try_push_atom+0x195>
 106f88b:	48 8d 3d 1e 81 01 00 	lea    0x1811e(%rip),%rdi        # 10879b0 <core_durable_error.verbs+0x7ce0>
 106f892:	ba 01 00 00 00       	mov    $0x1,%edx
 106f897:	e8 64 4f fb ff       	call   1024800 <myl_core_trap>
 106f89c:	48 39 d0             	cmp    %rdx,%rax
 106f89f:	0f 83 c7 00 00 00    	jae    106f96c <my.interpreter::try_push_atom+0x1ec>
 106f8a5:	49 89 c0             	mov    %rax,%r8
 106f8a8:	49 6b c0 38          	imul   $0x38,%r8,%rax
 106f8ac:	83 7c 01 20 09       	cmpl   $0x9,0x20(%rcx,%rax,1)
 106f8b1:	0f 85 2a 01 00 00    	jne    106f9e1 <my.interpreter::try_push_atom+0x261>
 106f8b7:	48 01 c8             	add    %rcx,%rax
 106f8ba:	48 83 c0 20          	add    $0x20,%rax
 106f8be:	48 8b 40 10          	mov    0x10(%rax),%rax
 106f8c2:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106f8c6:	48 39 d6             	cmp    %rdx,%rsi
 106f8c9:	0f 83 c2 00 00 00    	jae    106f991 <my.interpreter::try_push_atom+0x211>
 106f8cf:	48 89 f1             	mov    %rsi,%rcx
 106f8d2:	48 c1 e1 04          	shl    $0x4,%rcx
 106f8d6:	c5 f8 10 44 08 20    	vmovups 0x20(%rax,%rcx,1),%xmm0
 106f8dc:	49 8b 41 78          	mov    0x78(%r9),%rax
 106f8e0:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 106f8e7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106f8eb:	48 89 f1             	mov    %rsi,%rcx
 106f8ee:	48 39 d6             	cmp    %rdx,%rsi
 106f8f1:	0f 83 bc 00 00 00    	jae    106f9b3 <my.interpreter::try_push_atom+0x233>
 106f8f7:	48 c1 e1 04          	shl    $0x4,%rcx
 106f8fb:	c5 f8 54 05 dd 4a f9 	vandps -0x6b523(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 106f902:	ff 
 106f903:	c5 f8 11 44 08 20    	vmovups %xmm0,0x20(%rax,%rcx,1)
 106f909:	48 89 f0             	mov    %rsi,%rax
 106f90c:	48 ff c0             	inc    %rax
 106f90f:	0f 80 d8 00 00 00    	jo     106f9ed <my.interpreter::try_push_atom+0x26d>
 106f915:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 106f91c:	b0 01                	mov    $0x1,%al
 106f91e:	88 07                	mov    %al,(%rdi)
 106f920:	48 89 f8             	mov    %rdi,%rax
 106f923:	59                   	pop    %rcx
 106f924:	c3                   	ret
 106f925:	48 89 c1             	mov    %rax,%rcx
 106f928:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106f92c:	48 21 d1             	and    %rdx,%rcx
 106f92f:	48 01 c1             	add    %rax,%rcx
 106f932:	48 39 d1             	cmp    %rdx,%rcx
 106f935:	0f 82 5b fe ff ff    	jb     106f796 <my.interpreter::try_push_atom+0x16>
 106f93b:	48 8d 3d 0e 80 01 00 	lea    0x1800e(%rip),%rdi        # 1087950 <core_durable_error.verbs+0x7c80>
 106f942:	48 89 c6             	mov    %rax,%rsi
 106f945:	e8 b6 4e fb ff       	call   1024800 <myl_core_trap>
 106f94a:	48 89 f1             	mov    %rsi,%rcx
 106f94d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106f951:	48 21 d1             	and    %rdx,%rcx
 106f954:	48 01 f1             	add    %rsi,%rcx
 106f957:	48 39 d1             	cmp    %rdx,%rcx
 106f95a:	0f 82 0d ff ff ff    	jb     106f86d <my.interpreter::try_push_atom+0xed>
 106f960:	48 8d 3d 19 80 01 00 	lea    0x18019(%rip),%rdi        # 1087980 <core_durable_error.verbs+0x7cb0>
 106f967:	e8 94 4e fb ff       	call   1024800 <myl_core_trap>
 106f96c:	49 89 c0             	mov    %rax,%r8
 106f96f:	49 c1 f8 3f          	sar    $0x3f,%r8
 106f973:	49 21 d0             	and    %rdx,%r8
 106f976:	49 01 c0             	add    %rax,%r8
 106f979:	49 39 d0             	cmp    %rdx,%r8
 106f97c:	0f 82 26 ff ff ff    	jb     106f8a8 <my.interpreter::try_push_atom+0x128>
 106f982:	48 8d 3d e7 32 01 00 	lea    0x132e7(%rip),%rdi        # 1082c70 <core_durable_error.verbs+0x2fa0>
 106f989:	48 89 c6             	mov    %rax,%rsi
 106f98c:	e8 6f 4e fb ff       	call   1024800 <myl_core_trap>
 106f991:	48 89 f1             	mov    %rsi,%rcx
 106f994:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106f998:	48 21 d1             	and    %rdx,%rcx
 106f99b:	48 01 f1             	add    %rsi,%rcx
 106f99e:	48 39 d1             	cmp    %rdx,%rcx
 106f9a1:	0f 82 2b ff ff ff    	jb     106f8d2 <my.interpreter::try_push_atom+0x152>
 106f9a7:	48 8d 3d 22 33 01 00 	lea    0x13322(%rip),%rdi        # 1082cd0 <core_durable_error.verbs+0x3000>
 106f9ae:	e8 4d 4e fb ff       	call   1024800 <myl_core_trap>
 106f9b3:	48 89 f1             	mov    %rsi,%rcx
 106f9b6:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106f9ba:	48 21 d1             	and    %rdx,%rcx
 106f9bd:	48 01 f1             	add    %rsi,%rcx
 106f9c0:	48 39 d1             	cmp    %rdx,%rcx
 106f9c3:	0f 82 2e ff ff ff    	jb     106f8f7 <my.interpreter::try_push_atom+0x177>
 106f9c9:	48 8d 3d 10 80 01 00 	lea    0x18010(%rip),%rdi        # 10879e0 <core_durable_error.verbs+0x7d10>
 106f9d0:	e8 2b 4e fb ff       	call   1024800 <myl_core_trap>
 106f9d5:	48 8d 3d f4 5f 01 00 	lea    0x15ff4(%rip),%rdi        # 10859d0 <core_durable_error.verbs+0x5d00>
 106f9dc:	e8 9f a1 fb ff       	call   1029b80 <myl_core_assert_fail>
 106f9e1:	48 8d 3d b8 32 01 00 	lea    0x132b8(%rip),%rdi        # 1082ca0 <core_durable_error.verbs+0x2fd0>
 106f9e8:	e8 93 a1 fb ff       	call   1029b80 <myl_core_assert_fail>
 106f9ed:	48 8d 3d 1c 80 01 00 	lea    0x1801c(%rip),%rdi        # 1087a10 <core_durable_error.verbs+0x7d40>
 106f9f4:	ba 01 00 00 00       	mov    $0x1,%edx
 106f9f9:	e8 02 4e fb ff       	call   1024800 <myl_core_trap>

Disassembly of section .plt:
