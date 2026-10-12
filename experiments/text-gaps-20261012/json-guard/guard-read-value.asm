
/home/epentland/ai/canopy/mylang-text-gaps-json-final-20261012/.tmp/text-gaps/json-guard/text-runtime:     file format elf64-x86-64


Disassembly of section .text:

00000000010507c0 <my.json::read_value>:
 10507c0:	55                   	push   %rbp
 10507c1:	41 57                	push   %r15
 10507c3:	41 56                	push   %r14
 10507c5:	41 55                	push   %r13
 10507c7:	41 54                	push   %r12
 10507c9:	53                   	push   %rbx
 10507ca:	48 81 ec d8 00 00 00 	sub    $0xd8,%rsp
 10507d1:	49 89 d7             	mov    %rdx,%r15
 10507d4:	49 89 f6             	mov    %rsi,%r14
 10507d7:	49 89 fd             	mov    %rdi,%r13
 10507da:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
 10507df:	48 83 f9 40          	cmp    $0x40,%rcx
 10507e3:	0f 8f 34 09 00 00    	jg     105111d <my.json::read_value+0x95d>
 10507e9:	4d 85 ff             	test   %r15,%r15
 10507ec:	78 2d                	js     105081b <my.json::read_value+0x5b>
 10507ee:	4d 3b 7e 08          	cmp    0x8(%r14),%r15
 10507f2:	7d 27                	jge    105081b <my.json::read_value+0x5b>
 10507f4:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 10507fb:	00 00 00 
 10507fe:	66 90                	xchg   %ax,%ax
 1050800:	43 0f b6 4c 3e 20    	movzbl 0x20(%r14,%r15,1),%ecx
 1050806:	48 83 f9 20          	cmp    $0x20,%rcx
 105080a:	77 0f                	ja     105081b <my.json::read_value+0x5b>
 105080c:	48 0f a3 c8          	bt     %rcx,%rax
 1050810:	73 09                	jae    105081b <my.json::read_value+0x5b>
 1050812:	49 ff c7             	inc    %r15
 1050815:	4d 3b 7e 08          	cmp    0x8(%r14),%r15
 1050819:	7c e5                	jl     1050800 <my.json::read_value+0x40>
 105081b:	4d 85 ff             	test   %r15,%r15
 105081e:	0f 88 52 02 00 00    	js     1050a76 <my.json::read_value+0x2b6>
 1050824:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1050828:	49 39 d7             	cmp    %rdx,%r15
 105082b:	0f 8d 45 02 00 00    	jge    1050a76 <my.json::read_value+0x2b6>
 1050831:	49 8d 7e 20          	lea    0x20(%r14),%rdi
 1050835:	43 0f b6 4c 3e 20    	movzbl 0x20(%r14,%r15,1),%ecx
 105083b:	0f b6 c1             	movzbl %cl,%eax
 105083e:	8d 70 a5             	lea    -0x5b(%rax),%esi
 1050841:	83 fe 20             	cmp    $0x20,%esi
 1050844:	0f 87 bd 01 00 00    	ja     1050a07 <my.json::read_value+0x247>
 105084a:	48 8d 05 bf 6b fb ff 	lea    -0x49441(%rip),%rax        # 1007410 <core_number_pairs+0x170>
 1050851:	48 63 34 b0          	movslq (%rax,%rsi,4),%rsi
 1050855:	48 01 c6             	add    %rax,%rsi
 1050858:	ff e6                	jmp    *%rsi
 105085a:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
 105085f:	49 8d 57 01          	lea    0x1(%r15),%rdx
 1050863:	64 4c 8b 2c 25 c8 fe 	mov    %fs:0xfffffffffffffec8,%r13
 105086a:	ff ff 
 105086c:	4d 85 ed             	test   %r13,%r13
 105086f:	0f 84 cb 0e 00 00    	je     1051740 <my.json::read_value+0xf80>
 1050875:	49 8b 45 00          	mov    0x0(%r13),%rax
 1050879:	64 48 89 04 25 c8 fe 	mov    %rax,%fs:0xfffffffffffffec8
 1050880:	ff ff 
 1050882:	41 c7 45 00 00 00 00 	movl   $0x1000000,0x0(%r13)
 1050889:	01 
 105088a:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
 105088e:	c4 c1 7a 7f 45 08    	vmovdqu %xmm0,0x8(%r13)
 1050894:	49 c7 45 18 00 00 00 	movq   $0x0,0x18(%r13)
 105089b:	00 
 105089c:	48 8d 05 75 9f fb ff 	lea    -0x4608b(%rip),%rax        # 100a818 <core_number_pairs+0x3578>
 10508a3:	49 89 45 18          	mov    %rax,0x18(%r13)
 10508a7:	49 3b 56 08          	cmp    0x8(%r14),%rdx
 10508ab:	7d 32                	jge    10508df <my.json::read_value+0x11f>
 10508ad:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 10508b4:	00 00 00 
 10508b7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10508be:	00 00 
 10508c0:	43 0f b6 4c 3e 21    	movzbl 0x21(%r14,%r15,1),%ecx
 10508c6:	48 83 f9 20          	cmp    $0x20,%rcx
 10508ca:	77 13                	ja     10508df <my.json::read_value+0x11f>
 10508cc:	48 0f a3 c8          	bt     %rcx,%rax
 10508d0:	73 0d                	jae    10508df <my.json::read_value+0x11f>
 10508d2:	49 8d 57 02          	lea    0x2(%r15),%rdx
 10508d6:	49 ff c7             	inc    %r15
 10508d9:	49 3b 56 08          	cmp    0x8(%r14),%rdx
 10508dd:	7c e1                	jl     10508c0 <my.json::read_value+0x100>
 10508df:	49 3b 56 08          	cmp    0x8(%r14),%rdx
 10508e3:	7d 0c                	jge    10508f1 <my.json::read_value+0x131>
 10508e5:	41 80 7c 16 20 5d    	cmpb   $0x5d,0x20(%r14,%rdx,1)
 10508eb:	0f 84 1d 08 00 00    	je     105110e <my.json::read_value+0x94e>
 10508f1:	4d 8b 7d 08          	mov    0x8(%r13),%r15
 10508f5:	49 3b 56 08          	cmp    0x8(%r14),%rdx
 10508f9:	0f 8d aa 0a 00 00    	jge    10513a9 <my.json::read_value+0xbe9>
 10508ff:	48 ff 44 24 28       	incq   0x28(%rsp)
 1050904:	49 8b 6d 10          	mov    0x10(%r13),%rbp
 1050908:	48 8d 5c 24 40       	lea    0x40(%rsp),%rbx
 105090d:	49 bc 00 26 00 00 01 	movabs $0x100002600,%r12
 1050914:	00 00 00 
 1050917:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 105091e:	00 00 
 1050920:	48 89 df             	mov    %rbx,%rdi
 1050923:	4c 89 f6             	mov    %r14,%rsi
 1050926:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 105092b:	e8 90 fe ff ff       	call   10507c0 <my.json::read_value>
 1050930:	4c 8b 74 24 58       	mov    0x58(%rsp),%r14
 1050935:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 105093a:	80 7c 24 40 01       	cmpb   $0x1,0x40(%rsp)
 105093f:	0f 84 93 0d 00 00    	je     10516d8 <my.json::read_value+0xf18>
 1050945:	c5 fa 6f 44 24 48    	vmovdqu 0x48(%rsp),%xmm0
 105094b:	49 39 ef             	cmp    %rbp,%r15
 105094e:	0f 83 86 00 00 00    	jae    10509da <my.json::read_value+0x21a>
 1050954:	4c 89 f8             	mov    %r15,%rax
 1050957:	48 c1 e0 04          	shl    $0x4,%rax
 105095b:	c5 f9 db 05 dd 3a fb 	vpand  -0x4c523(%rip),%xmm0,%xmm0        # 1004440 <__anon_2214+0xb0>
 1050962:	ff 
 1050963:	c4 c1 7a 7f 44 05 20 	vmovdqu %xmm0,0x20(%r13,%rax,1)
 105096a:	48 85 d2             	test   %rdx,%rdx
 105096d:	78 32                	js     10509a1 <my.json::read_value+0x1e1>
 105096f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050976:	0f 1f 84 00 00 00 00 
 105097d:	00 
 105097e:	66 90                	xchg   %ax,%ax
 1050980:	49 3b 56 08          	cmp    0x8(%r14),%rdx
 1050984:	7d 1b                	jge    10509a1 <my.json::read_value+0x1e1>
 1050986:	41 0f b6 44 16 20    	movzbl 0x20(%r14,%rdx,1),%eax
 105098c:	48 83 f8 20          	cmp    $0x20,%rax
 1050990:	77 0f                	ja     10509a1 <my.json::read_value+0x1e1>
 1050992:	49 0f a3 c4          	bt     %rax,%r12
 1050996:	73 09                	jae    10509a1 <my.json::read_value+0x1e1>
 1050998:	48 ff c2             	inc    %rdx
 105099b:	49 3b 56 08          	cmp    0x8(%r14),%rdx
 105099f:	7c e5                	jl     1050986 <my.json::read_value+0x1c6>
 10509a1:	49 ff c7             	inc    %r15
 10509a4:	48 85 d2             	test   %rdx,%rdx
 10509a7:	0f 88 cf 09 00 00    	js     105137c <my.json::read_value+0xbbc>
 10509ad:	49 8b 46 08          	mov    0x8(%r14),%rax
 10509b1:	48 39 c2             	cmp    %rax,%rdx
 10509b4:	0f 8d c2 09 00 00    	jge    105137c <my.json::read_value+0xbbc>
 10509ba:	41 0f b6 4c 16 20    	movzbl 0x20(%r14,%rdx,1),%ecx
 10509c0:	83 f9 2c             	cmp    $0x2c,%ecx
 10509c3:	0f 85 38 07 00 00    	jne    1051101 <my.json::read_value+0x941>
 10509c9:	48 ff c2             	inc    %rdx
 10509cc:	48 39 c2             	cmp    %rax,%rdx
 10509cf:	0f 82 4b ff ff ff    	jb     1050920 <my.json::read_value+0x160>
 10509d5:	e9 cf 09 00 00       	jmp    10513a9 <my.json::read_value+0xbe9>
 10509da:	4d 89 7d 08          	mov    %r15,0x8(%r13)
 10509de:	be 10 00 00 00       	mov    $0x10,%esi
 10509e3:	4c 89 ef             	mov    %r13,%rdi
 10509e6:	49 89 d5             	mov    %rdx,%r13
 10509e9:	c5 f9 7f 04 24       	vmovdqa %xmm0,(%rsp)
 10509ee:	e8 4d 64 fc ff       	call   1016e40 <myl_core_list_grow>
 10509f3:	c5 f9 6f 04 24       	vmovdqa (%rsp),%xmm0
 10509f8:	4c 89 ea             	mov    %r13,%rdx
 10509fb:	49 89 c5             	mov    %rax,%r13
 10509fe:	48 8b 68 10          	mov    0x10(%rax),%rbp
 1050a02:	e9 4d ff ff ff       	jmp    1050954 <my.json::read_value+0x194>
 1050a07:	83 f8 22             	cmp    $0x22,%eax
 1050a0a:	0f 84 9b 06 00 00    	je     10510ab <my.json::read_value+0x8eb>
 1050a10:	83 f8 2d             	cmp    $0x2d,%eax
 1050a13:	74 0b                	je     1050a20 <my.json::read_value+0x260>
 1050a15:	8d 41 d0             	lea    -0x30(%rcx),%eax
 1050a18:	3c 0a                	cmp    $0xa,%al
 1050a1a:	0f 83 e9 09 00 00    	jae    1051409 <my.json::read_value+0xc49>
 1050a20:	45 31 e4             	xor    %r12d,%r12d
 1050a23:	80 f9 2d             	cmp    $0x2d,%cl
 1050a26:	41 0f 94 c4          	sete   %r12b
 1050a2a:	4d 01 fc             	add    %r15,%r12
 1050a2d:	49 39 d4             	cmp    %rdx,%r12
 1050a30:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
 1050a35:	0f 83 12 09 00 00    	jae    105134d <my.json::read_value+0xb8d>
 1050a3b:	42 0f b6 04 27       	movzbl (%rdi,%r12,1),%eax
 1050a40:	8d 70 d0             	lea    -0x30(%rax),%esi
 1050a43:	40 80 fe 0a          	cmp    $0xa,%sil
 1050a47:	0f 83 00 09 00 00    	jae    105134d <my.json::read_value+0xb8d>
 1050a4d:	3c 30                	cmp    $0x30,%al
 1050a4f:	0f 85 65 05 00 00    	jne    1050fba <my.json::read_value+0x7fa>
 1050a55:	49 ff c4             	inc    %r12
 1050a58:	49 39 d4             	cmp    %rdx,%r12
 1050a5b:	73 0f                	jae    1050a6c <my.json::read_value+0x2ac>
 1050a5d:	42 0f b6 04 27       	movzbl (%rdi,%r12,1),%eax
 1050a62:	04 d0                	add    $0xd0,%al
 1050a64:	3c 0a                	cmp    $0xa,%al
 1050a66:	0f 82 94 0c 00 00    	jb     1051700 <my.json::read_value+0xf40>
 1050a6c:	45 31 ed             	xor    %r13d,%r13d
 1050a6f:	31 db                	xor    %ebx,%ebx
 1050a71:	e9 f9 06 00 00       	jmp    105116f <my.json::read_value+0x9af>
 1050a76:	48 8d 15 e3 93 fb ff 	lea    -0x46c1d(%rip),%rdx        # 1009e60 <core_number_pairs+0x2bc0>
 1050a7d:	4c 89 f7             	mov    %r14,%rdi
 1050a80:	4c 89 fe             	mov    %r15,%rsi
 1050a83:	e8 38 0d 00 00       	call   10517c0 <my.json::parse_error>
 1050a88:	48 8d 3d 11 ee 00 00 	lea    0xee11(%rip),%rdi        # 105f8a0 <core_durable_error.verbs+0x12f0>
 1050a8f:	e9 a2 06 00 00       	jmp    1051136 <my.json::read_value+0x976>
 1050a94:	4c 89 fb             	mov    %r15,%rbx
 1050a97:	48 83 c3 05          	add    $0x5,%rbx
 1050a9b:	0f 80 c8 0c 00 00    	jo     1051769 <my.json::read_value+0xfa9>
 1050aa1:	48 39 d3             	cmp    %rdx,%rbx
 1050aa4:	0f 87 ed 09 00 00    	ja     1051497 <my.json::read_value+0xcd7>
 1050aaa:	49 39 d7             	cmp    %rdx,%r15
 1050aad:	49 0f 42 d7          	cmovb  %r15,%rdx
 1050ab1:	48 89 d8             	mov    %rbx,%rax
 1050ab4:	48 29 d0             	sub    %rdx,%rax
 1050ab7:	48 89 c1             	mov    %rax,%rcx
 1050aba:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050abe:	c4 e2 f0 f2 f0       	andn   %rax,%rcx,%rsi
 1050ac3:	48 01 d7             	add    %rdx,%rdi
 1050ac6:	48 8d 15 b3 92 fb ff 	lea    -0x46d4d(%rip),%rdx        # 1009d80 <core_number_pairs+0x2ae0>
 1050acd:	b9 05 00 00 00       	mov    $0x5,%ecx
 1050ad2:	e8 a9 16 fd ff       	call   1022180 <myl_core_span_eq>
 1050ad7:	84 c0                	test   %al,%al
 1050ad9:	0f 84 eb 09 00 00    	je     10514ca <my.json::read_value+0xd0a>
 1050adf:	b8 01 00 00 00       	mov    $0x1,%eax
 1050ae4:	31 c9                	xor    %ecx,%ecx
 1050ae6:	49 89 df             	mov    %rbx,%r15
 1050ae9:	e9 38 0a 00 00       	jmp    1051526 <my.json::read_value+0xd66>
 1050aee:	4c 89 fb             	mov    %r15,%rbx
 1050af1:	48 83 c3 04          	add    $0x4,%rbx
 1050af5:	0f 80 82 0c 00 00    	jo     105177d <my.json::read_value+0xfbd>
 1050afb:	48 39 d3             	cmp    %rdx,%rbx
 1050afe:	0f 87 a3 09 00 00    	ja     10514a7 <my.json::read_value+0xce7>
 1050b04:	49 39 d7             	cmp    %rdx,%r15
 1050b07:	49 0f 42 d7          	cmovb  %r15,%rdx
 1050b0b:	48 89 d8             	mov    %rbx,%rax
 1050b0e:	48 29 d0             	sub    %rdx,%rax
 1050b11:	48 89 c1             	mov    %rax,%rcx
 1050b14:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050b18:	c4 e2 f0 f2 f0       	andn   %rax,%rcx,%rsi
 1050b1d:	48 01 d7             	add    %rdx,%rdi
 1050b20:	48 8d 15 d9 91 fb ff 	lea    -0x46e27(%rip),%rdx        # 1009d00 <core_number_pairs+0x2a60>
 1050b27:	b9 04 00 00 00       	mov    $0x4,%ecx
 1050b2c:	e8 4f 16 fd ff       	call   1022180 <myl_core_span_eq>
 1050b31:	84 c0                	test   %al,%al
 1050b33:	0f 84 bb 09 00 00    	je     10514f4 <my.json::read_value+0xd34>
 1050b39:	31 c9                	xor    %ecx,%ecx
 1050b3b:	49 89 df             	mov    %rbx,%r15
 1050b3e:	31 c0                	xor    %eax,%eax
 1050b40:	e9 e1 09 00 00       	jmp    1051526 <my.json::read_value+0xd66>
 1050b45:	4c 89 fb             	mov    %r15,%rbx
 1050b48:	48 83 c3 04          	add    $0x4,%rbx
 1050b4c:	0f 80 3f 0c 00 00    	jo     1051791 <my.json::read_value+0xfd1>
 1050b52:	48 39 d3             	cmp    %rdx,%rbx
 1050b55:	0f 87 5c 09 00 00    	ja     10514b7 <my.json::read_value+0xcf7>
 1050b5b:	49 39 d7             	cmp    %rdx,%r15
 1050b5e:	49 0f 42 d7          	cmovb  %r15,%rdx
 1050b62:	48 89 d8             	mov    %rbx,%rax
 1050b65:	48 29 d0             	sub    %rdx,%rax
 1050b68:	48 89 c1             	mov    %rax,%rcx
 1050b6b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050b6f:	c4 e2 f0 f2 f0       	andn   %rax,%rcx,%rsi
 1050b74:	48 01 d7             	add    %rdx,%rdi
 1050b77:	48 8d 15 c2 91 fb ff 	lea    -0x46e3e(%rip),%rdx        # 1009d40 <core_number_pairs+0x2aa0>
 1050b7e:	b9 04 00 00 00       	mov    $0x4,%ecx
 1050b83:	e8 f8 15 fd ff       	call   1022180 <myl_core_span_eq>
 1050b88:	84 c0                	test   %al,%al
 1050b8a:	0f 84 af 09 00 00    	je     105153f <my.json::read_value+0xd7f>
 1050b90:	b8 01 00 00 00       	mov    $0x1,%eax
 1050b95:	31 c9                	xor    %ecx,%ecx
 1050b97:	49 89 df             	mov    %rbx,%r15
 1050b9a:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 1050b9e:	49 89 45 08          	mov    %rax,0x8(%r13)
 1050ba2:	49 c7 45 10 01 00 00 	movq   $0x1,0x10(%r13)
 1050ba9:	00 
 1050baa:	e9 87 09 00 00       	jmp    1051536 <my.json::read_value+0xd76>
 1050baf:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
 1050bb4:	4d 8d 6f 01          	lea    0x1(%r15),%r13
 1050bb8:	48 8d 35 29 f7 00 00 	lea    0xf729(%rip),%rsi        # 10602e8 <core_durable_error.verbs+0x1d38>
 1050bbf:	31 ff                	xor    %edi,%edi
 1050bc1:	e8 ba d7 fc ff       	call   101e380 <myl_core_dict_new>
 1050bc6:	48 89 04 24          	mov    %rax,(%rsp)
 1050bca:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050bce:	7d 4f                	jge    1050c1f <my.json::read_value+0x45f>
 1050bd0:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 1050bd7:	00 00 00 
 1050bda:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050be1:	0f 1f 84 00 00 00 00 
 1050be8:	00 
 1050be9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050bf0:	0f 1f 84 00 00 00 00 
 1050bf7:	00 
 1050bf8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1050bff:	00 
 1050c00:	43 0f b6 4c 3e 21    	movzbl 0x21(%r14,%r15,1),%ecx
 1050c06:	48 83 f9 20          	cmp    $0x20,%rcx
 1050c0a:	77 13                	ja     1050c1f <my.json::read_value+0x45f>
 1050c0c:	48 0f a3 c8          	bt     %rcx,%rax
 1050c10:	73 0d                	jae    1050c1f <my.json::read_value+0x45f>
 1050c12:	4d 8d 6f 02          	lea    0x2(%r15),%r13
 1050c16:	49 ff c7             	inc    %r15
 1050c19:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050c1d:	7c e1                	jl     1050c00 <my.json::read_value+0x440>
 1050c1f:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050c23:	7d 0c                	jge    1050c31 <my.json::read_value+0x471>
 1050c25:	43 80 7c 2e 20 7d    	cmpb   $0x7d,0x20(%r14,%r13,1)
 1050c2b:	0f 84 c7 06 00 00    	je     10512f8 <my.json::read_value+0xb38>
 1050c31:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050c35:	0f 8d ec 07 00 00    	jge    1051427 <my.json::read_value+0xc67>
 1050c3b:	48 ff 44 24 28       	incq   0x28(%rsp)
 1050c40:	48 bb 00 26 00 00 01 	movabs $0x100002600,%rbx
 1050c47:	00 00 00 
 1050c4a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1050c50:	43 0f b6 44 2e 20    	movzbl 0x20(%r14,%r13,1),%eax
 1050c56:	48 83 f8 20          	cmp    $0x20,%rax
 1050c5a:	77 0f                	ja     1050c6b <my.json::read_value+0x4ab>
 1050c5c:	48 0f a3 c3          	bt     %rax,%rbx
 1050c60:	73 09                	jae    1050c6b <my.json::read_value+0x4ab>
 1050c62:	49 ff c5             	inc    %r13
 1050c65:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050c69:	7c e5                	jl     1050c50 <my.json::read_value+0x490>
 1050c6b:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050c6f:	0f 8d 42 0a 00 00    	jge    10516b7 <my.json::read_value+0xef7>
 1050c75:	43 80 7c 2e 20 22    	cmpb   $0x22,0x20(%r14,%r13,1)
 1050c7b:	0f 85 36 0a 00 00    	jne    10516b7 <my.json::read_value+0xef7>
 1050c81:	48 8d bc 24 80 00 00 	lea    0x80(%rsp),%rdi
 1050c88:	00 
 1050c89:	4c 89 f6             	mov    %r14,%rsi
 1050c8c:	4c 89 ea             	mov    %r13,%rdx
 1050c8f:	e8 0c 0d 00 00       	call   10519a0 <my.json::read_string>
 1050c94:	4c 8b bc 24 88 00 00 	mov    0x88(%rsp),%r15
 1050c9b:	00 
 1050c9c:	4c 8b ac 24 98 00 00 	mov    0x98(%rsp),%r13
 1050ca3:	00 
 1050ca4:	4c 8b b4 24 90 00 00 	mov    0x90(%rsp),%r14
 1050cab:	00 
 1050cac:	80 bc 24 80 00 00 00 	cmpb   $0x1,0x80(%rsp)
 1050cb3:	01 
 1050cb4:	0f 84 64 0a 00 00    	je     105171e <my.json::read_value+0xf5e>
 1050cba:	4c 89 7c 24 38       	mov    %r15,0x38(%rsp)
 1050cbf:	41 f6 47 01 02       	testb  $0x2,0x1(%r15)
 1050cc4:	75 0a                	jne    1050cd0 <my.json::read_value+0x510>
 1050cc6:	4c 89 ff             	mov    %r15,%rdi
 1050cc9:	e8 32 eb fc ff       	call   101f800 <myl_core_str_hash>
 1050cce:	eb 04                	jmp    1050cd4 <my.json::read_value+0x514>
 1050cd0:	41 8b 47 18          	mov    0x18(%r15),%eax
 1050cd4:	4c 89 7c 24 20       	mov    %r15,0x20(%rsp)
 1050cd9:	89 c0                	mov    %eax,%eax
 1050cdb:	48 b9 15 7c 4a 7f b9 	movabs $0x9e3779b97f4a7c15,%rcx
 1050ce2:	79 37 9e 
 1050ce5:	48 0f af c1          	imul   %rcx,%rax
 1050ce9:	49 89 c7             	mov    %rax,%r15
 1050cec:	49 c1 ef 20          	shr    $0x20,%r15
 1050cf0:	49 31 c7             	xor    %rax,%r15
 1050cf3:	48 8b 04 24          	mov    (%rsp),%rax
 1050cf7:	48 8b 48 18          	mov    0x18(%rax),%rcx
 1050cfb:	48 8b 41 08          	mov    0x8(%rcx),%rax
 1050cff:	48 85 c0             	test   %rax,%rax
 1050d02:	0f 84 d8 00 00 00    	je     1050de0 <my.json::read_value+0x620>
 1050d08:	8b 08                	mov    (%rax),%ecx
 1050d0a:	f3 0f bc d1          	tzcnt  %ecx,%edx
 1050d0e:	f6 da                	neg    %dl
 1050d10:	c4 c2 eb f7 df       	shrx   %rdx,%r15,%rbx
 1050d15:	44 8d 61 ff          	lea    -0x1(%rcx),%r12d
 1050d19:	c5 fa 6f 4c 18 10    	vmovdqu 0x10(%rax,%rbx,1),%xmm1
 1050d1f:	4c 89 7c 24 30       	mov    %r15,0x30(%rsp)
 1050d24:	44 89 fa             	mov    %r15d,%edx
 1050d27:	80 e2 7f             	and    $0x7f,%dl
 1050d2a:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 1050d2e:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1050d33:	c5 f9 7f 8c 24 c0 00 	vmovdqa %xmm1,0xc0(%rsp)
 1050d3a:	00 00 
 1050d3c:	c5 f1 74 c0          	vpcmpeqb %xmm0,%xmm1,%xmm0
 1050d40:	c5 f9 d7 d0          	vpmovmskb %xmm0,%edx
 1050d44:	85 d2                	test   %edx,%edx
 1050d46:	74 6c                	je     1050db4 <my.json::read_value+0x5f4>
 1050d48:	83 c1 1e             	add    $0x1e,%ecx
 1050d4b:	83 e1 f0             	and    $0xfffffff0,%ecx
 1050d4e:	48 8d 2c 08          	lea    (%rax,%rcx,1),%rbp
 1050d52:	48 83 c5 10          	add    $0x10,%rbp
 1050d56:	44 0f b7 fa          	movzwl %dx,%r15d
 1050d5a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050d61:	0f 1f 84 00 00 00 00 
 1050d68:	00 
 1050d69:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050d70:	0f 1f 84 00 00 00 00 
 1050d77:	00 
 1050d78:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1050d7f:	00 
 1050d80:	f3 41 0f bc c7       	tzcnt  %r15d,%eax
 1050d85:	01 d8                	add    %ebx,%eax
 1050d87:	44 21 e0             	and    %r12d,%eax
 1050d8a:	8b 44 85 00          	mov    0x0(%rbp,%rax,4),%eax
 1050d8e:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 1050d92:	48 8b 0c 24          	mov    (%rsp),%rcx
 1050d96:	48 8b 7c c1 20       	mov    0x20(%rcx,%rax,8),%rdi
 1050d9b:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 1050da0:	e8 db eb fc ff       	call   101f980 <myl_core_str_eq>
 1050da5:	84 c0                	test   %al,%al
 1050da7:	0f 85 5b 05 00 00    	jne    1051308 <my.json::read_value+0xb48>
 1050dad:	c4 c2 00 f3 cf       	blsr   %r15d,%r15d
 1050db2:	75 cc                	jne    1050d80 <my.json::read_value+0x5c0>
 1050db4:	c5 f9 6f 84 24 c0 00 	vmovdqa 0xc0(%rsp),%xmm0
 1050dbb:	00 00 
 1050dbd:	c5 f9 74 05 1b 36 fb 	vpcmpeqb -0x4c9e5(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0x50>
 1050dc4:	ff 
 1050dc5:	c5 f9 d7 c0          	vpmovmskb %xmm0,%eax
 1050dc9:	85 c0                	test   %eax,%eax
 1050dcb:	4c 8b 7c 24 30       	mov    0x30(%rsp),%r15
 1050dd0:	74 19                	je     1050deb <my.json::read_value+0x62b>
 1050dd2:	f3 0f bc e8          	tzcnt  %eax,%ebp
 1050dd6:	01 dd                	add    %ebx,%ebp
 1050dd8:	44 21 e5             	and    %r12d,%ebp
 1050ddb:	48 f7 d5             	not    %rbp
 1050dde:	eb 2b                	jmp    1050e0b <my.json::read_value+0x64b>
 1050de0:	48 83 79 18 00       	cmpq   $0x0,0x18(%rcx)
 1050de5:	0f 84 6c 01 00 00    	je     1050f57 <my.json::read_value+0x797>
 1050deb:	48 8b 3c 24          	mov    (%rsp),%rdi
 1050def:	48 8d 74 24 38       	lea    0x38(%rsp),%rsi
 1050df4:	4c 89 fa             	mov    %r15,%rdx
 1050df7:	e8 c4 d1 fc ff       	call   101dfc0 <myl_core_dict_find>
 1050dfc:	48 89 c3             	mov    %rax,%rbx
 1050dff:	48 89 dd             	mov    %rbx,%rbp
 1050e02:	48 85 db             	test   %rbx,%rbx
 1050e05:	0f 89 fd 04 00 00    	jns    1051308 <my.json::read_value+0xb48>
 1050e0b:	4d 85 ed             	test   %r13,%r13
 1050e0e:	78 4d                	js     1050e5d <my.json::read_value+0x69d>
 1050e10:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050e14:	48 bb 00 26 00 00 01 	movabs $0x100002600,%rbx
 1050e1b:	00 00 00 
 1050e1e:	7d 47                	jge    1050e67 <my.json::read_value+0x6a7>
 1050e20:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 1050e25:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050e2c:	0f 1f 84 00 00 00 00 
 1050e33:	00 
 1050e34:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050e3b:	00 00 00 00 00 
 1050e40:	43 0f b6 44 2e 20    	movzbl 0x20(%r14,%r13,1),%eax
 1050e46:	48 83 f8 20          	cmp    $0x20,%rax
 1050e4a:	77 20                	ja     1050e6c <my.json::read_value+0x6ac>
 1050e4c:	48 0f a3 c3          	bt     %rax,%rbx
 1050e50:	73 1a                	jae    1050e6c <my.json::read_value+0x6ac>
 1050e52:	49 ff c5             	inc    %r13
 1050e55:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050e59:	7c e5                	jl     1050e40 <my.json::read_value+0x680>
 1050e5b:	eb 0f                	jmp    1050e6c <my.json::read_value+0x6ac>
 1050e5d:	48 bb 00 26 00 00 01 	movabs $0x100002600,%rbx
 1050e64:	00 00 00 
 1050e67:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 1050e6c:	4d 85 ed             	test   %r13,%r13
 1050e6f:	0f 88 01 07 00 00    	js     1051576 <my.json::read_value+0xdb6>
 1050e75:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050e79:	0f 8d f7 06 00 00    	jge    1051576 <my.json::read_value+0xdb6>
 1050e7f:	43 80 7c 2e 20 3a    	cmpb   $0x3a,0x20(%r14,%r13,1)
 1050e85:	0f 85 eb 06 00 00    	jne    1051576 <my.json::read_value+0xdb6>
 1050e8b:	49 ff c5             	inc    %r13
 1050e8e:	48 8d 7c 24 40       	lea    0x40(%rsp),%rdi
 1050e93:	4c 89 f6             	mov    %r14,%rsi
 1050e96:	4c 89 ea             	mov    %r13,%rdx
 1050e99:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 1050e9e:	e8 1d f9 ff ff       	call   10507c0 <my.json::read_value>
 1050ea3:	4c 8b 7c 24 48       	mov    0x48(%rsp),%r15
 1050ea8:	4c 8b 74 24 58       	mov    0x58(%rsp),%r14
 1050ead:	4c 8b 6c 24 60       	mov    0x60(%rsp),%r13
 1050eb2:	80 7c 24 40 01       	cmpb   $0x1,0x40(%rsp)
 1050eb7:	0f 84 6a 08 00 00    	je     1051727 <my.json::read_value+0xf67>
 1050ebd:	4c 89 64 24 68       	mov    %r12,0x68(%rsp)
 1050ec2:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
 1050ec7:	41 0f b6 cf          	movzbl %r15b,%ecx
 1050ecb:	48 89 4c 24 70       	mov    %rcx,0x70(%rsp)
 1050ed0:	48 89 44 24 78       	mov    %rax,0x78(%rsp)
 1050ed5:	48 8b 3c 24          	mov    (%rsp),%rdi
 1050ed9:	48 89 ee             	mov    %rbp,%rsi
 1050edc:	48 8d 54 24 68       	lea    0x68(%rsp),%rdx
 1050ee1:	48 8d 4c 24 70       	lea    0x70(%rsp),%rcx
 1050ee6:	45 31 c0             	xor    %r8d,%r8d
 1050ee9:	e8 52 d7 fc ff       	call   101e640 <myl_core_dict_insert>
 1050eee:	48 89 04 24          	mov    %rax,(%rsp)
 1050ef2:	4d 85 ed             	test   %r13,%r13
 1050ef5:	78 2a                	js     1050f21 <my.json::read_value+0x761>
 1050ef7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1050efe:	00 00 
 1050f00:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050f04:	7d 1b                	jge    1050f21 <my.json::read_value+0x761>
 1050f06:	43 0f b6 44 2e 20    	movzbl 0x20(%r14,%r13,1),%eax
 1050f0c:	48 83 f8 20          	cmp    $0x20,%rax
 1050f10:	77 0f                	ja     1050f21 <my.json::read_value+0x761>
 1050f12:	48 0f a3 c3          	bt     %rax,%rbx
 1050f16:	73 09                	jae    1050f21 <my.json::read_value+0x761>
 1050f18:	49 ff c5             	inc    %r13
 1050f1b:	4d 3b 6e 08          	cmp    0x8(%r14),%r13
 1050f1f:	7c e5                	jl     1050f06 <my.json::read_value+0x746>
 1050f21:	4d 85 ed             	test   %r13,%r13
 1050f24:	0f 88 75 06 00 00    	js     105159f <my.json::read_value+0xddf>
 1050f2a:	49 8b 46 08          	mov    0x8(%r14),%rax
 1050f2e:	49 39 c5             	cmp    %rax,%r13
 1050f31:	0f 8d 68 06 00 00    	jge    105159f <my.json::read_value+0xddf>
 1050f37:	43 0f b6 4c 2e 20    	movzbl 0x20(%r14,%r13,1),%ecx
 1050f3d:	83 f9 2c             	cmp    $0x2c,%ecx
 1050f40:	0f 85 a9 03 00 00    	jne    10512ef <my.json::read_value+0xb2f>
 1050f46:	49 ff c5             	inc    %r13
 1050f49:	49 39 c5             	cmp    %rax,%r13
 1050f4c:	0f 82 fe fc ff ff    	jb     1050c50 <my.json::read_value+0x490>
 1050f52:	e9 d0 04 00 00       	jmp    1051427 <my.json::read_value+0xc67>
 1050f57:	48 8b 51 20          	mov    0x20(%rcx),%rdx
 1050f5b:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 1050f62:	48 85 d2             	test   %rdx,%rdx
 1050f65:	0f 84 a0 fe ff ff    	je     1050e0b <my.json::read_value+0x64b>
 1050f6b:	4c 8b 61 10          	mov    0x10(%rcx),%r12
 1050f6f:	48 8b 04 24          	mov    (%rsp),%rax
 1050f73:	48 8d 68 20          	lea    0x20(%rax),%rbp
 1050f77:	31 db                	xor    %ebx,%ebx
 1050f79:	48 89 54 24 30       	mov    %rdx,0x30(%rsp)
 1050f7e:	eb 0c                	jmp    1050f8c <my.json::read_value+0x7cc>
 1050f80:	48 ff c3             	inc    %rbx
 1050f83:	48 83 c5 18          	add    $0x18,%rbp
 1050f87:	48 39 da             	cmp    %rbx,%rdx
 1050f8a:	74 22                	je     1050fae <my.json::read_value+0x7ee>
 1050f8c:	4d 39 3c dc          	cmp    %r15,(%r12,%rbx,8)
 1050f90:	75 ee                	jne    1050f80 <my.json::read_value+0x7c0>
 1050f92:	48 8b 7d 00          	mov    0x0(%rbp),%rdi
 1050f96:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 1050f9b:	e8 e0 e9 fc ff       	call   101f980 <myl_core_str_eq>
 1050fa0:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 1050fa5:	84 c0                	test   %al,%al
 1050fa7:	74 d7                	je     1050f80 <my.json::read_value+0x7c0>
 1050fa9:	e9 51 fe ff ff       	jmp    1050dff <my.json::read_value+0x63f>
 1050fae:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 1050fb5:	e9 51 fe ff ff       	jmp    1050e0b <my.json::read_value+0x64b>
 1050fba:	45 31 c0             	xor    %r8d,%r8d
 1050fbd:	80 f9 2d             	cmp    $0x2d,%cl
 1050fc0:	41 0f 94 c0          	sete   %r8b
 1050fc4:	49 b9 34 33 33 33 33 	movabs $0xf333333333333334,%r9
 1050fcb:	33 33 f3 
 1050fce:	49 83 c0 07          	add    $0x7,%r8
 1050fd2:	b3 01                	mov    $0x1,%bl
 1050fd4:	45 31 ed             	xor    %r13d,%r13d
 1050fd7:	eb 35                	jmp    105100e <my.json::read_value+0x84e>
 1050fd9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050fe0:	0f 1f 84 00 00 00 00 
 1050fe7:	00 
 1050fe8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050fef:	0f 1f 84 00 00 00 00 
 1050ff6:	00 
 1050ff7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1050ffe:	00 00 
 1051000:	31 db                	xor    %ebx,%ebx
 1051002:	49 ff c4             	inc    %r12
 1051005:	4c 39 e2             	cmp    %r12,%rdx
 1051008:	0f 84 3e 01 00 00    	je     105114c <my.json::read_value+0x98c>
 105100e:	4c 89 e0             	mov    %r12,%rax
 1051011:	48 c1 f8 3f          	sar    $0x3f,%rax
 1051015:	48 21 d0             	and    %rdx,%rax
 1051018:	4a 8d 34 20          	lea    (%rax,%r12,1),%rsi
 105101c:	48 39 d6             	cmp    %rdx,%rsi
 105101f:	0f 83 35 07 00 00    	jae    105175a <my.json::read_value+0xf9a>
 1051025:	48 01 f8             	add    %rdi,%rax
 1051028:	41 0f b6 04 04       	movzbl (%r12,%rax,1),%eax
 105102d:	8d 70 c6             	lea    -0x3a(%rax),%esi
 1051030:	40 80 fe f5          	cmp    $0xf5,%sil
 1051034:	0f 86 15 01 00 00    	jbe    105114f <my.json::read_value+0x98f>
 105103a:	49 8d 71 ff          	lea    -0x1(%r9),%rsi
 105103e:	49 39 f5             	cmp    %rsi,%r13
 1051041:	40 0f 9f c6          	setg   %sil
 1051045:	40 84 f3             	test   %sil,%bl
 1051048:	74 b6                	je     1051000 <my.json::read_value+0x840>
 105104a:	48 83 c0 d0          	add    $0xffffffffffffffd0,%rax
 105104e:	4d 39 cd             	cmp    %r9,%r13
 1051051:	75 2d                	jne    1051080 <my.json::read_value+0x8c0>
 1051053:	44 39 c0             	cmp    %r8d,%eax
 1051056:	7e 28                	jle    1051080 <my.json::read_value+0x8c0>
 1051058:	31 db                	xor    %ebx,%ebx
 105105a:	4d 89 cd             	mov    %r9,%r13
 105105d:	eb a3                	jmp    1051002 <my.json::read_value+0x842>
 105105f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1051066:	0f 1f 84 00 00 00 00 
 105106d:	00 
 105106e:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1051075:	0f 1f 84 00 00 00 00 
 105107c:	00 
 105107d:	0f 1f 00             	nopl   (%rax)
 1051080:	4d 01 ed             	add    %r13,%r13
 1051083:	4a 8d 34 ad 00 00 00 	lea    0x0(,%r13,4),%rsi
 105108a:	00 
 105108b:	4c 01 ee             	add    %r13,%rsi
 105108e:	49 89 f5             	mov    %rsi,%r13
 1051091:	49 29 c5             	sub    %rax,%r13
 1051094:	b3 01                	mov    $0x1,%bl
 1051096:	0f 81 66 ff ff ff    	jno    1051002 <my.json::read_value+0x842>
 105109c:	48 8d 3d 7d ef 00 00 	lea    0xef7d(%rip),%rdi        # 1060020 <core_durable_error.verbs+0x1a70>
 10510a3:	48 89 c2             	mov    %rax,%rdx
 10510a6:	e8 15 78 fc ff       	call   10188c0 <myl_core_trap>
 10510ab:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 10510b2:	00 
 10510b3:	4c 89 f6             	mov    %r14,%rsi
 10510b6:	4c 89 fa             	mov    %r15,%rdx
 10510b9:	e8 e2 08 00 00       	call   10519a0 <my.json::read_string>
 10510be:	48 8b 84 24 a8 00 00 	mov    0xa8(%rsp),%rax
 10510c5:	00 
 10510c6:	4c 8b bc 24 b8 00 00 	mov    0xb8(%rsp),%r15
 10510cd:	00 
 10510ce:	48 8b 8c 24 b0 00 00 	mov    0xb0(%rsp),%rcx
 10510d5:	00 
 10510d6:	80 bc 24 a0 00 00 00 	cmpb   $0x1,0xa0(%rsp)
 10510dd:	01 
 10510de:	0f 84 53 05 00 00    	je     1051637 <my.json::read_value+0xe77>
 10510e4:	49 c7 45 00 00 00 00 	movq   $0x0,0x0(%r13)
 10510eb:	00 
 10510ec:	49 c7 45 08 04 00 00 	movq   $0x4,0x8(%r13)
 10510f3:	00 
 10510f4:	49 89 45 10          	mov    %rax,0x10(%r13)
 10510f8:	49 89 4d 18          	mov    %rcx,0x18(%r13)
 10510fc:	e9 9d 05 00 00       	jmp    105169e <my.json::read_value+0xede>
 1051101:	83 f9 5d             	cmp    $0x5d,%ecx
 1051104:	0f 85 72 02 00 00    	jne    105137c <my.json::read_value+0xbbc>
 105110a:	4d 89 7d 08          	mov    %r15,0x8(%r13)
 105110e:	48 ff c2             	inc    %rdx
 1051111:	b8 05 00 00 00       	mov    $0x5,%eax
 1051116:	31 c9                	xor    %ecx,%ecx
 1051118:	e9 cd 02 00 00       	jmp    10513ea <my.json::read_value+0xc2a>
 105111d:	48 8d 15 dc 8c fb ff 	lea    -0x47324(%rip),%rdx        # 1009e00 <core_number_pairs+0x2b60>
 1051124:	4c 89 f7             	mov    %r14,%rdi
 1051127:	4c 89 fe             	mov    %r15,%rsi
 105112a:	e8 91 06 00 00       	call   10517c0 <my.json::parse_error>
 105112f:	48 8d 3d ea e5 00 00 	lea    0xe5ea(%rip),%rdi        # 105f720 <core_durable_error.verbs+0x1170>
 1051136:	e8 45 9b ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 105113b:	49 c7 45 00 01 00 00 	movq   $0x1,0x0(%r13)
 1051142:	00 
 1051143:	49 89 45 08          	mov    %rax,0x8(%r13)
 1051147:	e9 ea 03 00 00       	jmp    1051536 <my.json::read_value+0xd76>
 105114c:	49 89 d4             	mov    %rdx,%r12
 105114f:	80 f9 2d             	cmp    $0x2d,%cl
 1051152:	0f 94 c0             	sete   %al
 1051155:	80 f3 01             	xor    $0x1,%bl
 1051158:	08 d8                	or     %bl,%al
 105115a:	a8 01                	test   $0x1,%al
 105115c:	75 11                	jne    105116f <my.json::read_value+0x9af>
 105115e:	4c 89 e8             	mov    %r13,%rax
 1051161:	48 f7 d8             	neg    %rax
 1051164:	0f 80 3b 06 00 00    	jo     10517a5 <my.json::read_value+0xfe5>
 105116a:	31 db                	xor    %ebx,%ebx
 105116c:	49 89 c5             	mov    %rax,%r13
 105116f:	49 39 d4             	cmp    %rdx,%r12
 1051172:	0f 9d c0             	setge  %al
 1051175:	4d 85 e4             	test   %r12,%r12
 1051178:	0f 98 c1             	sets   %cl
 105117b:	08 c1                	or     %al,%cl
 105117d:	75 69                	jne    10511e8 <my.json::read_value+0xa28>
 105117f:	42 80 3c 27 2e       	cmpb   $0x2e,(%rdi,%r12,1)
 1051184:	75 62                	jne    10511e8 <my.json::read_value+0xa28>
 1051186:	49 8d 6c 24 01       	lea    0x1(%r12),%rbp
 105118b:	48 39 d5             	cmp    %rdx,%rbp
 105118e:	0f 8d 69 04 00 00    	jge    10515fd <my.json::read_value+0xe3d>
 1051194:	0f b6 04 2f          	movzbl (%rdi,%rbp,1),%eax
 1051198:	04 d0                	add    $0xd0,%al
 105119a:	3c 09                	cmp    $0x9,%al
 105119c:	0f 87 5b 04 00 00    	ja     10515fd <my.json::read_value+0xe3d>
 10511a2:	b8 01 00 00 00       	mov    $0x1,%eax
 10511a7:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10511ae:	0f 1f 84 00 00 00 00 
 10511b5:	00 
 10511b6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 10511bd:	00 00 00 
 10511c0:	43 0f b6 4c 26 21    	movzbl 0x21(%r14,%r12,1),%ecx
 10511c6:	80 c1 d0             	add    $0xd0,%cl
 10511c9:	80 f9 0a             	cmp    $0xa,%cl
 10511cc:	73 0e                	jae    10511dc <my.json::read_value+0xa1c>
 10511ce:	49 8d 6c 24 02       	lea    0x2(%r12),%rbp
 10511d3:	49 ff c4             	inc    %r12
 10511d6:	49 3b 6e 08          	cmp    0x8(%r14),%rbp
 10511da:	7c e4                	jl     10511c0 <my.json::read_value+0xa00>
 10511dc:	31 c9                	xor    %ecx,%ecx
 10511de:	80 f9 01             	cmp    $0x1,%cl
 10511e1:	75 15                	jne    10511f8 <my.json::read_value+0xa38>
 10511e3:	e9 3e 04 00 00       	jmp    1051626 <my.json::read_value+0xe66>
 10511e8:	31 c9                	xor    %ecx,%ecx
 10511ea:	31 c0                	xor    %eax,%eax
 10511ec:	4c 89 e5             	mov    %r12,%rbp
 10511ef:	80 f9 01             	cmp    $0x1,%cl
 10511f2:	0f 84 2e 04 00 00    	je     1051626 <my.json::read_value+0xe66>
 10511f8:	49 8b 4e 08          	mov    0x8(%r14),%rcx
 10511fc:	48 39 cd             	cmp    %rcx,%rbp
 10511ff:	0f 9d c2             	setge  %dl
 1051202:	48 85 ed             	test   %rbp,%rbp
 1051205:	40 0f 98 c6          	sets   %sil
 1051209:	40 08 d6             	or     %dl,%sil
 105120c:	0f 85 91 00 00 00    	jne    10512a3 <my.json::read_value+0xae3>
 1051212:	41 0f b6 54 2e 20    	movzbl 0x20(%r14,%rbp,1),%edx
 1051218:	83 ca 20             	or     $0x20,%edx
 105121b:	83 fa 65             	cmp    $0x65,%edx
 105121e:	0f 85 7f 00 00 00    	jne    10512a3 <my.json::read_value+0xae3>
 1051224:	4c 8d 65 01          	lea    0x1(%rbp),%r12
 1051228:	49 39 cc             	cmp    %rcx,%r12
 105122b:	7d 17                	jge    1051244 <my.json::read_value+0xa84>
 105122d:	43 0f b6 4c 26 20    	movzbl 0x20(%r14,%r12,1),%ecx
 1051233:	83 f9 2d             	cmp    $0x2d,%ecx
 1051236:	74 05                	je     105123d <my.json::read_value+0xa7d>
 1051238:	83 f9 2b             	cmp    $0x2b,%ecx
 105123b:	75 07                	jne    1051244 <my.json::read_value+0xa84>
 105123d:	48 83 c5 02          	add    $0x2,%rbp
 1051241:	49 89 ec             	mov    %rbp,%r12
 1051244:	4d 3b 66 08          	cmp    0x8(%r14),%r12
 1051248:	0f 8d 03 02 00 00    	jge    1051451 <my.json::read_value+0xc91>
 105124e:	43 0f b6 4c 26 20    	movzbl 0x20(%r14,%r12,1),%ecx
 1051254:	80 c1 d0             	add    $0xd0,%cl
 1051257:	80 f9 09             	cmp    $0x9,%cl
 105125a:	0f 87 f1 01 00 00    	ja     1051451 <my.json::read_value+0xc91>
 1051260:	b9 01 00 00 00       	mov    $0x1,%ecx
 1051265:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105126c:	0f 1f 84 00 00 00 00 
 1051273:	00 
 1051274:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 105127b:	00 00 00 00 00 
 1051280:	43 0f b6 54 26 20    	movzbl 0x20(%r14,%r12,1),%edx
 1051286:	80 c2 d0             	add    $0xd0,%dl
 1051289:	80 fa 0a             	cmp    $0xa,%dl
 105128c:	73 09                	jae    1051297 <my.json::read_value+0xad7>
 105128e:	49 ff c4             	inc    %r12
 1051291:	4d 3b 66 08          	cmp    0x8(%r14),%r12
 1051295:	7c e9                	jl     1051280 <my.json::read_value+0xac0>
 1051297:	31 d2                	xor    %edx,%edx
 1051299:	80 fa 01             	cmp    $0x1,%dl
 105129c:	75 15                	jne    10512b3 <my.json::read_value+0xaf3>
 105129e:	e9 e0 01 00 00       	jmp    1051483 <my.json::read_value+0xcc3>
 10512a3:	31 d2                	xor    %edx,%edx
 10512a5:	31 c9                	xor    %ecx,%ecx
 10512a7:	49 89 ec             	mov    %rbp,%r12
 10512aa:	80 fa 01             	cmp    $0x1,%dl
 10512ad:	0f 84 d0 01 00 00    	je     1051483 <my.json::read_value+0xcc3>
 10512b3:	09 c1                	or     %eax,%ecx
 10512b5:	08 cb                	or     %cl,%bl
 10512b7:	f6 c3 01             	test   $0x1,%bl
 10512ba:	74 27                	je     10512e3 <my.json::read_value+0xb23>
 10512bc:	4c 89 f7             	mov    %r14,%rdi
 10512bf:	4c 89 fe             	mov    %r15,%rsi
 10512c2:	4c 89 e2             	mov    %r12,%rdx
 10512c5:	e8 66 69 00 00       	call   1057c30 <myl_core_parse_float_range>
 10512ca:	3c 01                	cmp    $0x1,%al
 10512cc:	0f 85 83 03 00 00    	jne    1051655 <my.json::read_value+0xe95>
 10512d2:	c4 c1 f9 7e c5       	vmovq  %xmm0,%r13
 10512d7:	b8 03 00 00 00       	mov    $0x3,%eax
 10512dc:	31 c9                	xor    %ecx,%ecx
 10512de:	e9 a1 03 00 00       	jmp    1051684 <my.json::read_value+0xec4>
 10512e3:	b8 02 00 00 00       	mov    $0x2,%eax
 10512e8:	31 c9                	xor    %ecx,%ecx
 10512ea:	e9 95 03 00 00       	jmp    1051684 <my.json::read_value+0xec4>
 10512ef:	83 f9 7d             	cmp    $0x7d,%ecx
 10512f2:	0f 85 a7 02 00 00    	jne    105159f <my.json::read_value+0xddf>
 10512f8:	49 ff c5             	inc    %r13
 10512fb:	41 bf 06 00 00 00    	mov    $0x6,%r15d
 1051301:	31 c0                	xor    %eax,%eax
 1051303:	e9 d2 02 00 00       	jmp    10515da <my.json::read_value+0xe1a>
 1051308:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 105130d:	e8 2e 68 fc ff       	call   1017b40 <myl_core_drop_owned>
 1051312:	48 8d 15 47 91 fb ff 	lea    -0x46eb9(%rip),%rdx        # 100a460 <core_number_pairs+0x31c0>
 1051319:	4c 89 f7             	mov    %r14,%rdi
 105131c:	4c 89 ee             	mov    %r13,%rsi
 105131f:	e8 9c 04 00 00       	call   10517c0 <my.json::parse_error>
 1051324:	49 89 c7             	mov    %rax,%r15
 1051327:	48 8d 3d 22 ea 00 00 	lea    0xea22(%rip),%rdi        # 105fd50 <core_durable_error.verbs+0x17a0>
 105132e:	e8 4d 99 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 1051333:	48 8b 3c 24          	mov    (%rsp),%rdi
 1051337:	e8 04 68 fc ff       	call   1017b40 <myl_core_drop_owned>
 105133c:	48 8d 3d ed e5 00 00 	lea    0xe5ed(%rip),%rdi        # 105f930 <core_durable_error.verbs+0x1380>
 1051343:	e8 78 99 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 1051348:	e9 7c 02 00 00       	jmp    10515c9 <my.json::read_value+0xe09>
 105134d:	48 8d 15 6c 92 fb ff 	lea    -0x46d94(%rip),%rdx        # 100a5c0 <core_number_pairs+0x3320>
 1051354:	4c 89 f7             	mov    %r14,%rdi
 1051357:	4c 89 e6             	mov    %r12,%rsi
 105135a:	e8 61 04 00 00       	call   10517c0 <my.json::parse_error>
 105135f:	48 8d 3d 2a ec 00 00 	lea    0xec2a(%rip),%rdi        # 105ff90 <core_durable_error.verbs+0x19e0>
 1051366:	e8 15 99 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 105136b:	48 8d 3d 5e e8 00 00 	lea    0xe85e(%rip),%rdi        # 105fbd0 <core_durable_error.verbs+0x1620>
 1051372:	e8 49 99 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 1051377:	e9 f7 02 00 00       	jmp    1051673 <my.json::read_value+0xeb3>
 105137c:	4d 89 7d 08          	mov    %r15,0x8(%r13)
 1051380:	4c 89 ef             	mov    %r13,%rdi
 1051383:	49 89 d7             	mov    %rdx,%r15
 1051386:	e8 b5 67 fc ff       	call   1017b40 <myl_core_drop_owned>
 105138b:	48 8d 15 4e 8e fb ff 	lea    -0x471b2(%rip),%rdx        # 100a1e0 <core_number_pairs+0x2f40>
 1051392:	4c 89 f7             	mov    %r14,%rdi
 1051395:	4c 89 fb             	mov    %r15,%rbx
 1051398:	4c 89 fe             	mov    %r15,%rsi
 105139b:	e8 20 04 00 00       	call   10517c0 <my.json::parse_error>
 10513a0:	48 8d 3d 49 e6 00 00 	lea    0xe649(%rip),%rdi        # 105f9f0 <core_durable_error.verbs+0x1440>
 10513a7:	eb 28                	jmp    10513d1 <my.json::read_value+0xc11>
 10513a9:	48 89 d3             	mov    %rdx,%rbx
 10513ac:	4d 89 7d 08          	mov    %r15,0x8(%r13)
 10513b0:	4c 89 ef             	mov    %r13,%rdi
 10513b3:	e8 88 67 fc ff       	call   1017b40 <myl_core_drop_owned>
 10513b8:	48 8d 15 e1 8d fb ff 	lea    -0x4721f(%rip),%rdx        # 100a1a0 <core_number_pairs+0x2f00>
 10513bf:	4c 89 f7             	mov    %r14,%rdi
 10513c2:	48 89 de             	mov    %rbx,%rsi
 10513c5:	e8 f6 03 00 00       	call   10517c0 <my.json::parse_error>
 10513ca:	48 8d 3d bf e5 00 00 	lea    0xe5bf(%rip),%rdi        # 105f990 <core_durable_error.verbs+0x13e0>
 10513d1:	e8 aa 98 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 10513d6:	48 8d 3d a3 e3 00 00 	lea    0xe3a3(%rip),%rdi        # 105f780 <core_durable_error.verbs+0x11d0>
 10513dd:	e8 de 98 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 10513e2:	b9 01 00 00 00       	mov    $0x1,%ecx
 10513e7:	48 89 da             	mov    %rbx,%rdx
 10513ea:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 10513ef:	48 89 0e             	mov    %rcx,(%rsi)
 10513f2:	48 89 46 08          	mov    %rax,0x8(%rsi)
 10513f6:	4c 89 6e 10          	mov    %r13,0x10(%rsi)
 10513fa:	49 89 f5             	mov    %rsi,%r13
 10513fd:	4c 89 76 18          	mov    %r14,0x18(%rsi)
 1051401:	49 89 d7             	mov    %rdx,%r15
 1051404:	e9 95 02 00 00       	jmp    105169e <my.json::read_value+0xede>
 1051409:	48 8d 15 90 8a fb ff 	lea    -0x47570(%rip),%rdx        # 1009ea0 <core_number_pairs+0x2c00>
 1051410:	4c 89 f7             	mov    %r14,%rdi
 1051413:	4c 89 fe             	mov    %r15,%rsi
 1051416:	e8 a5 03 00 00       	call   10517c0 <my.json::parse_error>
 105141b:	48 8d 3d ae e4 00 00 	lea    0xe4ae(%rip),%rdi        # 105f8d0 <core_durable_error.verbs+0x1320>
 1051422:	e9 0f fd ff ff       	jmp    1051136 <my.json::read_value+0x976>
 1051427:	48 8b 3c 24          	mov    (%rsp),%rdi
 105142b:	e8 10 67 fc ff       	call   1017b40 <myl_core_drop_owned>
 1051430:	48 8d 15 c9 8c fb ff 	lea    -0x47337(%rip),%rdx        # 100a100 <core_number_pairs+0x2e60>
 1051437:	4c 89 f7             	mov    %r14,%rdi
 105143a:	4c 89 ee             	mov    %r13,%rsi
 105143d:	e8 7e 03 00 00       	call   10517c0 <my.json::parse_error>
 1051442:	49 89 c7             	mov    %rax,%r15
 1051445:	48 8d 3d b4 e4 00 00 	lea    0xe4b4(%rip),%rdi        # 105f900 <core_durable_error.verbs+0x1350>
 105144c:	e9 73 01 00 00       	jmp    10515c4 <my.json::read_value+0xe04>
 1051451:	48 8d 15 28 92 fb ff 	lea    -0x46dd8(%rip),%rdx        # 100a680 <core_number_pairs+0x33e0>
 1051458:	4c 89 f7             	mov    %r14,%rdi
 105145b:	4c 89 e6             	mov    %r12,%rsi
 105145e:	48 89 c5             	mov    %rax,%rbp
 1051461:	e8 5a 03 00 00       	call   10517c0 <my.json::parse_error>
 1051466:	48 89 c1             	mov    %rax,%rcx
 1051469:	48 89 e8             	mov    %rbp,%rax
 105146c:	b2 01                	mov    $0x1,%dl
 105146e:	48 8d 3d 3b ec 00 00 	lea    0xec3b(%rip),%rdi        # 10600b0 <core_durable_error.verbs+0x1b00>
 1051475:	e8 06 98 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 105147a:	80 fa 01             	cmp    $0x1,%dl
 105147d:	0f 85 30 fe ff ff    	jne    10512b3 <my.json::read_value+0xaf3>
 1051483:	48 8d 3d a6 e7 00 00 	lea    0xe7a6(%rip),%rdi        # 105fc30 <core_durable_error.verbs+0x1680>
 105148a:	e8 31 98 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 105148f:	48 89 c8             	mov    %rcx,%rax
 1051492:	e9 dc 01 00 00       	jmp    1051673 <my.json::read_value+0xeb3>
 1051497:	48 8d 1d d2 e6 00 00 	lea    0xe6d2(%rip),%rbx        # 105fb70 <core_durable_error.verbs+0x15c0>
 105149e:	48 8d 15 3b 8e fb ff 	lea    -0x471c5(%rip),%rdx        # 100a2e0 <core_number_pairs+0x3040>
 10514a5:	eb 31                	jmp    10514d8 <my.json::read_value+0xd18>
 10514a7:	48 8d 1d c2 e6 00 00 	lea    0xe6c2(%rip),%rbx        # 105fb70 <core_durable_error.verbs+0x15c0>
 10514ae:	48 8d 15 2b 8e fb ff 	lea    -0x471d5(%rip),%rdx        # 100a2e0 <core_number_pairs+0x3040>
 10514b5:	eb 4b                	jmp    1051502 <my.json::read_value+0xd42>
 10514b7:	48 8d 1d b2 e6 00 00 	lea    0xe6b2(%rip),%rbx        # 105fb70 <core_durable_error.verbs+0x15c0>
 10514be:	48 8d 15 1b 8e fb ff 	lea    -0x471e5(%rip),%rdx        # 100a2e0 <core_number_pairs+0x3040>
 10514c5:	e9 83 00 00 00       	jmp    105154d <my.json::read_value+0xd8d>
 10514ca:	48 8d 1d cf e6 00 00 	lea    0xe6cf(%rip),%rbx        # 105fba0 <core_durable_error.verbs+0x15f0>
 10514d1:	48 8d 15 48 8e fb ff 	lea    -0x471b8(%rip),%rdx        # 100a320 <core_number_pairs+0x3080>
 10514d8:	4c 89 f7             	mov    %r14,%rdi
 10514db:	4c 89 fe             	mov    %r15,%rsi
 10514de:	e8 dd 02 00 00       	call   10517c0 <my.json::parse_error>
 10514e3:	48 89 df             	mov    %rbx,%rdi
 10514e6:	e8 95 97 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 10514eb:	48 8d 3d 1e e3 00 00 	lea    0xe31e(%rip),%rdi        # 105f810 <core_durable_error.verbs+0x1260>
 10514f2:	eb 28                	jmp    105151c <my.json::read_value+0xd5c>
 10514f4:	48 8d 1d a5 e6 00 00 	lea    0xe6a5(%rip),%rbx        # 105fba0 <core_durable_error.verbs+0x15f0>
 10514fb:	48 8d 15 1e 8e fb ff 	lea    -0x471e2(%rip),%rdx        # 100a320 <core_number_pairs+0x3080>
 1051502:	4c 89 f7             	mov    %r14,%rdi
 1051505:	4c 89 fe             	mov    %r15,%rsi
 1051508:	e8 b3 02 00 00       	call   10517c0 <my.json::parse_error>
 105150d:	48 89 df             	mov    %rbx,%rdi
 1051510:	e8 6b 97 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 1051515:	48 8d 3d 24 e3 00 00 	lea    0xe324(%rip),%rdi        # 105f840 <core_durable_error.verbs+0x1290>
 105151c:	e8 9f 97 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 1051521:	b9 01 00 00 00       	mov    $0x1,%ecx
 1051526:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 105152a:	49 89 45 08          	mov    %rax,0x8(%r13)
 105152e:	49 c7 45 10 00 00 00 	movq   $0x0,0x10(%r13)
 1051535:	00 
 1051536:	4d 89 75 18          	mov    %r14,0x18(%r13)
 105153a:	e9 5f 01 00 00       	jmp    105169e <my.json::read_value+0xede>
 105153f:	48 8d 1d 5a e6 00 00 	lea    0xe65a(%rip),%rbx        # 105fba0 <core_durable_error.verbs+0x15f0>
 1051546:	48 8d 15 d3 8d fb ff 	lea    -0x4722d(%rip),%rdx        # 100a320 <core_number_pairs+0x3080>
 105154d:	4c 89 f7             	mov    %r14,%rdi
 1051550:	4c 89 fe             	mov    %r15,%rsi
 1051553:	e8 68 02 00 00       	call   10517c0 <my.json::parse_error>
 1051558:	48 89 df             	mov    %rbx,%rdi
 105155b:	e8 20 97 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 1051560:	48 8d 3d 79 e2 00 00 	lea    0xe279(%rip),%rdi        # 105f7e0 <core_durable_error.verbs+0x1230>
 1051567:	e8 54 97 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 105156c:	b9 01 00 00 00       	mov    $0x1,%ecx
 1051571:	e9 24 f6 ff ff       	jmp    1050b9a <my.json::read_value+0x3da>
 1051576:	4c 89 e7             	mov    %r12,%rdi
 1051579:	e8 c2 65 fc ff       	call   1017b40 <myl_core_drop_owned>
 105157e:	48 8d 15 1b 8f fb ff 	lea    -0x470e5(%rip),%rdx        # 100a4a0 <core_number_pairs+0x3200>
 1051585:	4c 89 f7             	mov    %r14,%rdi
 1051588:	4c 89 ee             	mov    %r13,%rsi
 105158b:	e8 30 02 00 00       	call   10517c0 <my.json::parse_error>
 1051590:	49 89 c7             	mov    %rax,%r15
 1051593:	48 8d 3d e6 e7 00 00 	lea    0xe7e6(%rip),%rdi        # 105fd80 <core_durable_error.verbs+0x17d0>
 105159a:	e9 8f fd ff ff       	jmp    105132e <my.json::read_value+0xb6e>
 105159f:	48 8b 3c 24          	mov    (%rsp),%rdi
 10515a3:	e8 98 65 fc ff       	call   1017b40 <myl_core_drop_owned>
 10515a8:	48 8d 15 91 8b fb ff 	lea    -0x4746f(%rip),%rdx        # 100a140 <core_number_pairs+0x2ea0>
 10515af:	4c 89 f7             	mov    %r14,%rdi
 10515b2:	4c 89 ee             	mov    %r13,%rsi
 10515b5:	e8 06 02 00 00       	call   10517c0 <my.json::parse_error>
 10515ba:	49 89 c7             	mov    %rax,%r15
 10515bd:	48 8d 3d 9c e3 00 00 	lea    0xe39c(%rip),%rdi        # 105f960 <core_durable_error.verbs+0x13b0>
 10515c4:	e8 b7 96 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 10515c9:	48 8d 3d 80 e1 00 00 	lea    0xe180(%rip),%rdi        # 105f750 <core_durable_error.verbs+0x11a0>
 10515d0:	e8 eb 96 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 10515d5:	b8 01 00 00 00       	mov    $0x1,%eax
 10515da:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 10515df:	48 89 01             	mov    %rax,(%rcx)
 10515e2:	4c 89 79 08          	mov    %r15,0x8(%rcx)
 10515e6:	48 8b 04 24          	mov    (%rsp),%rax
 10515ea:	48 89 41 10          	mov    %rax,0x10(%rcx)
 10515ee:	4c 89 71 18          	mov    %r14,0x18(%rcx)
 10515f2:	4d 89 ef             	mov    %r13,%r15
 10515f5:	49 89 cd             	mov    %rcx,%r13
 10515f8:	e9 a1 00 00 00       	jmp    105169e <my.json::read_value+0xede>
 10515fd:	48 8d 15 3c 90 fb ff 	lea    -0x46fc4(%rip),%rdx        # 100a640 <core_number_pairs+0x33a0>
 1051604:	4c 89 f7             	mov    %r14,%rdi
 1051607:	48 89 ee             	mov    %rbp,%rsi
 105160a:	e8 b1 01 00 00       	call   10517c0 <my.json::parse_error>
 105160f:	b1 01                	mov    $0x1,%cl
 1051611:	48 8d 3d 68 ea 00 00 	lea    0xea68(%rip),%rdi        # 1060080 <core_durable_error.verbs+0x1ad0>
 1051618:	e8 63 96 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 105161d:	80 f9 01             	cmp    $0x1,%cl
 1051620:	0f 85 d2 fb ff ff    	jne    10511f8 <my.json::read_value+0xa38>
 1051626:	48 8d 3d d3 e5 00 00 	lea    0xe5d3(%rip),%rdi        # 105fc00 <core_durable_error.verbs+0x1650>
 105162d:	e8 8e 96 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 1051632:	49 89 ec             	mov    %rbp,%r12
 1051635:	eb 3c                	jmp    1051673 <my.json::read_value+0xeb3>
 1051637:	48 8d 3d 72 e1 00 00 	lea    0xe172(%rip),%rdi        # 105f7b0 <core_durable_error.verbs+0x1200>
 105163e:	e8 7d 96 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 1051643:	49 c7 45 00 01 00 00 	movq   $0x1,0x0(%r13)
 105164a:	00 
 105164b:	49 89 45 08          	mov    %rax,0x8(%r13)
 105164f:	49 89 4d 18          	mov    %rcx,0x18(%r13)
 1051653:	eb 49                	jmp    105169e <my.json::read_value+0xede>
 1051655:	48 8d 15 04 8d fb ff 	lea    -0x472fc(%rip),%rdx        # 100a360 <core_number_pairs+0x30c0>
 105165c:	4c 89 f7             	mov    %r14,%rdi
 105165f:	4c 89 e6             	mov    %r12,%rsi
 1051662:	e8 59 01 00 00       	call   10517c0 <my.json::parse_error>
 1051667:	48 8d 3d f2 e5 00 00 	lea    0xe5f2(%rip),%rdi        # 105fc60 <core_durable_error.verbs+0x16b0>
 105166e:	e8 0d 96 ff ff       	call   104ac80 <myl_core_err_trace_origin_preserve_most>
 1051673:	48 8d 3d f6 e1 00 00 	lea    0xe1f6(%rip),%rdi        # 105f870 <core_durable_error.verbs+0x12c0>
 105167a:	e8 41 96 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 105167f:	b9 01 00 00 00       	mov    $0x1,%ecx
 1051684:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 1051689:	48 89 0a             	mov    %rcx,(%rdx)
 105168c:	48 89 42 08          	mov    %rax,0x8(%rdx)
 1051690:	4c 89 6a 10          	mov    %r13,0x10(%rdx)
 1051694:	49 89 d5             	mov    %rdx,%r13
 1051697:	4c 89 72 18          	mov    %r14,0x18(%rdx)
 105169b:	4d 89 e7             	mov    %r12,%r15
 105169e:	4d 89 7d 20          	mov    %r15,0x20(%r13)
 10516a2:	4c 89 e8             	mov    %r13,%rax
 10516a5:	48 81 c4 d8 00 00 00 	add    $0xd8,%rsp
 10516ac:	5b                   	pop    %rbx
 10516ad:	41 5c                	pop    %r12
 10516af:	41 5d                	pop    %r13
 10516b1:	41 5e                	pop    %r14
 10516b3:	41 5f                	pop    %r15
 10516b5:	5d                   	pop    %rbp
 10516b6:	c3                   	ret
 10516b7:	48 8d 15 42 8d fb ff 	lea    -0x472be(%rip),%rdx        # 100a400 <core_number_pairs+0x3160>
 10516be:	4c 89 f7             	mov    %r14,%rdi
 10516c1:	4c 89 ee             	mov    %r13,%rsi
 10516c4:	e8 f7 00 00 00       	call   10517c0 <my.json::parse_error>
 10516c9:	49 89 c7             	mov    %rax,%r15
 10516cc:	48 8d 3d 1d e6 00 00 	lea    0xe61d(%rip),%rdi        # 105fcf0 <core_durable_error.verbs+0x1740>
 10516d3:	e9 56 fc ff ff       	jmp    105132e <my.json::read_value+0xb6e>
 10516d8:	48 89 d3             	mov    %rdx,%rbx
 10516db:	4c 8b 64 24 48       	mov    0x48(%rsp),%r12
 10516e0:	4d 89 7d 08          	mov    %r15,0x8(%r13)
 10516e4:	4c 89 ef             	mov    %r13,%rdi
 10516e7:	e8 54 64 fc ff       	call   1017b40 <myl_core_drop_owned>
 10516ec:	4c 89 e0             	mov    %r12,%rax
 10516ef:	48 8d 3d ca e2 00 00 	lea    0xe2ca(%rip),%rdi        # 105f9c0 <core_durable_error.verbs+0x1410>
 10516f6:	e8 c5 95 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 10516fb:	e9 d6 fc ff ff       	jmp    10513d6 <my.json::read_value+0xc16>
 1051700:	48 8d 15 f9 8e fb ff 	lea    -0x47107(%rip),%rdx        # 100a600 <core_number_pairs+0x3360>
 1051707:	4c 89 f7             	mov    %r14,%rdi
 105170a:	4c 89 e6             	mov    %r12,%rsi
 105170d:	e8 ae 00 00 00       	call   10517c0 <my.json::parse_error>
 1051712:	48 8d 3d a7 e8 00 00 	lea    0xe8a7(%rip),%rdi        # 105ffc0 <core_durable_error.verbs+0x1a10>
 1051719:	e9 48 fc ff ff       	jmp    1051366 <my.json::read_value+0xba6>
 105171e:	48 8d 3d fb e5 00 00 	lea    0xe5fb(%rip),%rdi        # 105fd20 <core_durable_error.verbs+0x1770>
 1051725:	eb 0f                	jmp    1051736 <my.json::read_value+0xf76>
 1051727:	4c 89 e7             	mov    %r12,%rdi
 105172a:	e8 11 64 fc ff       	call   1017b40 <myl_core_drop_owned>
 105172f:	48 8d 3d 7a e6 00 00 	lea    0xe67a(%rip),%rdi        # 105fdb0 <core_durable_error.verbs+0x1800>
 1051736:	e8 85 95 ff ff       	call   104acc0 <myl_core_err_trace_append_preserve_most>
 105173b:	e9 f3 fb ff ff       	jmp    1051333 <my.json::read_value+0xb73>
 1051740:	be 10 00 00 00       	mov    $0x10,%esi
 1051745:	31 ff                	xor    %edi,%edi
 1051747:	48 89 d3             	mov    %rdx,%rbx
 105174a:	e8 31 56 fc ff       	call   1016d80 <myl_core_list_new_slow>
 105174f:	48 89 da             	mov    %rbx,%rdx
 1051752:	49 89 c5             	mov    %rax,%r13
 1051755:	e9 42 f1 ff ff       	jmp    105089c <my.json::read_value+0xdc>
 105175a:	48 8d 3d 8f e8 00 00 	lea    0xe88f(%rip),%rdi        # 105fff0 <core_durable_error.verbs+0x1a40>
 1051761:	4c 89 e6             	mov    %r12,%rsi
 1051764:	e8 57 71 fc ff       	call   10188c0 <myl_core_trap>
 1051769:	48 8d 3d d0 e3 00 00 	lea    0xe3d0(%rip),%rdi        # 105fb40 <core_durable_error.verbs+0x1590>
 1051770:	ba 05 00 00 00       	mov    $0x5,%edx
 1051775:	4c 89 fe             	mov    %r15,%rsi
 1051778:	e8 43 71 fc ff       	call   10188c0 <myl_core_trap>
 105177d:	48 8d 3d bc e3 00 00 	lea    0xe3bc(%rip),%rdi        # 105fb40 <core_durable_error.verbs+0x1590>
 1051784:	ba 04 00 00 00       	mov    $0x4,%edx
 1051789:	4c 89 fe             	mov    %r15,%rsi
 105178c:	e8 2f 71 fc ff       	call   10188c0 <myl_core_trap>
 1051791:	48 8d 3d a8 e3 00 00 	lea    0xe3a8(%rip),%rdi        # 105fb40 <core_durable_error.verbs+0x1590>
 1051798:	ba 04 00 00 00       	mov    $0x4,%edx
 105179d:	4c 89 fe             	mov    %r15,%rsi
 10517a0:	e8 1b 71 fc ff       	call   10188c0 <myl_core_trap>
 10517a5:	48 8d 3d a4 e8 00 00 	lea    0xe8a4(%rip),%rdi        # 1060050 <core_durable_error.verbs+0x1aa0>
 10517ac:	31 f6                	xor    %esi,%esi
 10517ae:	4c 89 ea             	mov    %r13,%rdx
 10517b1:	e8 0a 71 fc ff       	call   10188c0 <myl_core_trap>

Disassembly of section .plt:
