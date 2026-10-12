<myl_core_ir_str_append_char>:
 1020800:	55                   	push   %rbp
 1020801:	48 89 e5             	mov    %rsp,%rbp
 1020804:	41 57                	push   %r15
 1020806:	41 56                	push   %r14
 1020808:	41 55                	push   %r13
 102080a:	41 54                	push   %r12
 102080c:	53                   	push   %rbx
 102080d:	48 83 ec 18          	sub    $0x18,%rsp
 1020811:	48 3b 56 08          	cmp    0x8(%rsi),%rdx
 1020815:	0f 83 4a 03 00 00    	jae    1020b65 <myl_core_ir_str_append_char+0x365>
 102081b:	48 89 fb             	mov    %rdi,%rbx
 102081e:	0f b6 44 16 20       	movzbl 0x20(%rsi,%rdx,1),%eax
 1020823:	84 c0                	test   %al,%al
 1020825:	78 4c                	js     1020873 <myl_core_ir_str_append_char+0x73>
 1020827:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 102082b:	48 85 c9             	test   %rcx,%rcx
 102082e:	78 74                	js     10208a4 <myl_core_ir_str_append_char+0xa4>
 1020830:	48 3b 4b 10          	cmp    0x10(%rbx),%rcx
 1020834:	0f 9c c2             	setl   %dl
 1020837:	8b 3b                	mov    (%rbx),%edi
 1020839:	f7 c7 00 18 80 00    	test   $0x801800,%edi
 102083f:	40 0f 94 c6          	sete   %sil
 1020843:	40 20 d6             	and    %dl,%sil
 1020846:	40 80 fe 01          	cmp    $0x1,%sil
 102084a:	75 5a                	jne    10208a6 <myl_core_ir_str_append_char+0xa6>
 102084c:	48 8d 51 01          	lea    0x1(%rcx),%rdx
 1020850:	88 44 0b 20          	mov    %al,0x20(%rbx,%rcx,1)
 1020854:	48 89 53 08          	mov    %rdx,0x8(%rbx)
 1020858:	c6 44 0b 21 00       	movb   $0x0,0x21(%rbx,%rcx,1)
 102085d:	b8 ff f8 ff ff       	mov    $0xfffff8ff,%eax
 1020862:	23 03                	and    (%rbx),%eax
 1020864:	81 e7 00 01 00 00    	and    $0x100,%edi
 102086a:	09 f8                	or     %edi,%eax
 102086c:	89 03                	mov    %eax,(%rbx)
 102086e:	e9 d3 02 00 00       	jmp    1020b46 <myl_core_ir_str_append_char+0x346>
 1020873:	48 8d 0c 16          	lea    (%rsi,%rdx,1),%rcx
 1020877:	48 83 c1 20          	add    $0x20,%rcx
 102087b:	41 bc 02 00 00 00    	mov    $0x2,%r12d
 1020881:	3c e0                	cmp    $0xe0,%al
 1020883:	72 0a                	jb     102088f <myl_core_ir_str_append_char+0x8f>
 1020885:	41 bc 03 00 00 00    	mov    $0x3,%r12d
 102088b:	3c f0                	cmp    $0xf0,%al
 102088d:	73 28                	jae    10208b7 <myl_core_ir_str_append_char+0xb7>
 102088f:	0f b7 01             	movzwl (%rcx),%eax
 1020892:	42 0f b7 4c 21 fe    	movzwl -0x2(%rcx,%r12,1),%ecx
 1020898:	66 89 45 d4          	mov    %ax,-0x2c(%rbp)
 102089c:	66 42 89 4c 25 d2    	mov    %cx,-0x2e(%rbp,%r12,1)
 10208a2:	eb 1e                	jmp    10208c2 <myl_core_ir_str_append_char+0xc2>
 10208a4:	8b 3b                	mov    (%rbx),%edi
 10208a6:	88 45 d4             	mov    %al,-0x2c(%rbp)
 10208a9:	c1 ef 08             	shr    $0x8,%edi
 10208ac:	83 e7 01             	and    $0x1,%edi
 10208af:	41 bc 01 00 00 00    	mov    $0x1,%r12d
 10208b5:	eb 0d                	jmp    10208c4 <myl_core_ir_str_append_char+0xc4>
 10208b7:	8b 01                	mov    (%rcx),%eax
 10208b9:	89 45 d4             	mov    %eax,-0x2c(%rbp)
 10208bc:	41 bc 04 00 00 00    	mov    $0x4,%r12d
 10208c2:	31 ff                	xor    %edi,%edi
 10208c4:	48 8b 43 08          	mov    0x8(%rbx),%rax
 10208c8:	48 89 c1             	mov    %rax,%rcx
 10208cb:	48 c1 e9 3f          	shr    $0x3f,%rcx
 10208cf:	0f 85 8b 02 00 00    	jne    1020b60 <myl_core_ir_str_append_char+0x360>
 10208d5:	48 b9 ff ff ff ff ff 	movabs $0x7fffffffffffffff,%rcx
 10208dc:	ff ff 7f 
 10208df:	48 31 c1             	xor    %rax,%rcx
 10208e2:	49 39 cc             	cmp    %rcx,%r12
 10208e5:	0f 87 75 02 00 00    	ja     1020b60 <myl_core_ir_str_append_char+0x360>
 10208eb:	4e 8d 04 20          	lea    (%rax,%r12,1),%r8
 10208ef:	44 8b 2b             	mov    (%rbx),%r13d
 10208f2:	41 f7 c5 00 00 80 00 	test   $0x800000,%r13d
 10208f9:	75 29                	jne    1020924 <myl_core_ir_str_append_char+0x124>
 10208fb:	44 89 e9             	mov    %r13d,%ecx
 10208fe:	81 e1 00 18 00 00    	and    $0x1800,%ecx
 1020904:	44 89 ea             	mov    %r13d,%edx
 1020907:	81 e2 ff e7 7f ff    	and    $0xff7fe7ff,%edx
 102090d:	81 f9 00 08 00 00    	cmp    $0x800,%ecx
 1020913:	0f 85 c4 00 00 00    	jne    10209dd <myl_core_ir_str_append_char+0x1dd>
 1020919:	48 89 43 10          	mov    %rax,0x10(%rbx)
 102091d:	89 13                	mov    %edx,(%rbx)
 102091f:	48 89 c1             	mov    %rax,%rcx
 1020922:	eb 04                	jmp    1020928 <myl_core_ir_str_append_char+0x128>
 1020924:	48 8b 4b 10          	mov    0x10(%rbx),%rcx
 1020928:	89 7d d0             	mov    %edi,-0x30(%rbp)
 102092b:	48 8d 04 09          	lea    (%rcx,%rcx,1),%rax
 102092f:	48 85 c9             	test   %rcx,%rcx
 1020932:	be 10 00 00 00       	mov    $0x10,%esi
 1020937:	48 0f 4f f0          	cmovg  %rax,%rsi
 102093b:	4c 39 c6             	cmp    %r8,%rsi
 102093e:	49 0f 4e f0          	cmovle %r8,%rsi
 1020942:	48 b8 ff ff ff ff ff 	movabs $0x3fffffffffffffff,%rax
 1020949:	ff ff 3f 
 102094c:	48 39 c1             	cmp    %rax,%rcx
 102094f:	4c 89 45 c8          	mov    %r8,-0x38(%rbp)
 1020953:	49 0f 4f f0          	cmovg  %r8,%rsi
 1020957:	48 85 f6             	test   %rsi,%rsi
 102095a:	0f 88 00 02 00 00    	js     1020b60 <myl_core_ir_str_append_char+0x360>
 1020960:	48 ff c6             	inc    %rsi
 1020963:	48 8d 55 c0          	lea    -0x40(%rbp),%rdx
 1020967:	bf 01 00 00 00       	mov    $0x1,%edi
 102096c:	e8 0f 31 02 00       	call   1043a80 <block_alloc>
 1020971:	49 89 c6             	mov    %rax,%r14
 1020974:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 1020978:	48 ff c8             	dec    %rax
 102097b:	49 89 46 10          	mov    %rax,0x10(%r14)
 102097f:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1020983:	49 89 56 08          	mov    %rdx,0x8(%r14)
 1020987:	4d 8d 7e 20          	lea    0x20(%r14),%r15
 102098b:	48 8d 73 20          	lea    0x20(%rbx),%rsi
 102098f:	4c 89 ff             	mov    %r15,%rdi
 1020992:	e8 99 cb 03 00       	call   105d530 <memcpy@plt>
 1020997:	4c 03 7b 08          	add    0x8(%rbx),%r15
 102099b:	41 83 fc 04          	cmp    $0x4,%r12d
 102099f:	72 14                	jb     10209b5 <myl_core_ir_str_append_char+0x1b5>
 10209a1:	8b 45 d4             	mov    -0x2c(%rbp),%eax
 10209a4:	41 89 07             	mov    %eax,(%r15)
 10209a7:	41 f7 c5 00 00 80 00 	test   $0x800000,%r13d
 10209ae:	74 67                	je     1020a17 <myl_core_ir_str_append_char+0x217>
 10209b0:	e9 68 01 00 00       	jmp    1020b1d <myl_core_ir_str_append_char+0x31d>
 10209b5:	41 83 fc 02          	cmp    $0x2,%r12d
 10209b9:	72 48                	jb     1020a03 <myl_core_ir_str_append_char+0x203>
 10209bb:	0f b7 45 d4          	movzwl -0x2c(%rbp),%eax
 10209bf:	42 0f b7 4c 25 d2    	movzwl -0x2e(%rbp,%r12,1),%ecx
 10209c5:	66 41 89 07          	mov    %ax,(%r15)
 10209c9:	66 43 89 4c 27 fe    	mov    %cx,-0x2(%r15,%r12,1)
 10209cf:	41 f7 c5 00 00 80 00 	test   $0x800000,%r13d
 10209d6:	74 3f                	je     1020a17 <myl_core_ir_str_append_char+0x217>
 10209d8:	e9 40 01 00 00       	jmp    1020b1d <myl_core_ir_str_append_char+0x31d>
 10209dd:	48 8b 4b 10          	mov    0x10(%rbx),%rcx
 10209e1:	89 13                	mov    %edx,(%rbx)
 10209e3:	49 39 c8             	cmp    %rcx,%r8
 10209e6:	0f 8f 3c ff ff ff    	jg     1020928 <myl_core_ir_str_append_char+0x128>
 10209ec:	48 01 d8             	add    %rbx,%rax
 10209ef:	48 83 c0 20          	add    $0x20,%rax
 10209f3:	41 83 fc 04          	cmp    $0x4,%r12d
 10209f7:	72 4c                	jb     1020a45 <myl_core_ir_str_append_char+0x245>
 10209f9:	8b 4d d4             	mov    -0x2c(%rbp),%ecx
 10209fc:	89 08                	mov    %ecx,(%rax)
 10209fe:	e9 24 01 00 00       	jmp    1020b27 <myl_core_ir_str_append_char+0x327>
 1020a03:	0f b6 45 d4          	movzbl -0x2c(%rbp),%eax
 1020a07:	41 88 07             	mov    %al,(%r15)
 1020a0a:	41 f7 c5 00 00 80 00 	test   $0x800000,%r13d
 1020a11:	0f 85 06 01 00 00    	jne    1020b1d <myl_core_ir_str_append_char+0x31d>
 1020a17:	0f b6 43 03          	movzbl 0x3(%rbx),%eax
 1020a1b:	64 48 83 3c 25 e0 ff 	cmpq   $0x0,%fs:0xffffffffffffffe0
 1020a22:	ff ff 00 
 1020a25:	74 47                	je     1020a6e <myl_core_ir_str_append_char+0x26e>
 1020a27:	85 c0                	test   %eax,%eax
 1020a29:	74 4c                	je     1020a77 <myl_core_ir_str_append_char+0x277>
 1020a2b:	64 48 8b 0c c5 c0 fe 	mov    %fs:-0x140(,%rax,8),%rcx
 1020a32:	ff ff 
 1020a34:	48 89 0b             	mov    %rcx,(%rbx)
 1020a37:	64 48 89 1c c5 c0 fe 	mov    %rbx,%fs:-0x140(,%rax,8)
 1020a3e:	ff ff 
 1020a40:	e9 d8 00 00 00       	jmp    1020b1d <myl_core_ir_str_append_char+0x31d>
 1020a45:	41 83 fc 02          	cmp    $0x2,%r12d
 1020a49:	72 18                	jb     1020a63 <myl_core_ir_str_append_char+0x263>
 1020a4b:	0f b7 4d d4          	movzwl -0x2c(%rbp),%ecx
 1020a4f:	42 0f b7 54 25 d2    	movzwl -0x2e(%rbp,%r12,1),%edx
 1020a55:	66 89 08             	mov    %cx,(%rax)
 1020a58:	66 42 89 54 20 fe    	mov    %dx,-0x2(%rax,%r12,1)
 1020a5e:	e9 c4 00 00 00       	jmp    1020b27 <myl_core_ir_str_append_char+0x327>
 1020a63:	0f b6 4d d4          	movzbl -0x2c(%rbp),%ecx
 1020a67:	88 08                	mov    %cl,(%rax)
 1020a69:	e9 b9 00 00 00       	jmp    1020b27 <myl_core_ir_str_append_char+0x327>
 1020a6e:	e8 cd a3 02 00       	call   104ae40 <core_thread_register_slow>
 1020a73:	85 c0                	test   %eax,%eax
 1020a75:	75 b4                	jne    1020a2b <myl_core_ir_str_append_char+0x22b>
 1020a77:	0f b6 05 4a 4e 06 00 	movzbl 0x64e4a(%rip),%eax        # 10858c8 <core_pool_started>
 1020a7e:	84 c0                	test   %al,%al
 1020a80:	74 14                	je     1020a96 <myl_core_ir_str_append_char+0x296>
 1020a82:	f0 48 ff 0d 7e 4e 06 	lock decq 0x64e7e(%rip)        # 1085908 <live_blocks>
 1020a89:	00 
 1020a8a:	48 83 3d 3e 23 04 00 	cmpq   $0x0,0x4233e(%rip)        # 1062dd0 <heap_ceiling>
 1020a91:	00 
 1020a92:	75 13                	jne    1020aa7 <myl_core_ir_str_append_char+0x2a7>
 1020a94:	eb 7f                	jmp    1020b15 <myl_core_ir_str_append_char+0x315>
 1020a96:	48 ff 0d 6b 4e 06 00 	decq   0x64e6b(%rip)        # 1085908 <live_blocks>
 1020a9d:	48 83 3d 2b 23 04 00 	cmpq   $0x0,0x4232b(%rip)        # 1062dd0 <heap_ceiling>
 1020aa4:	00 
 1020aa5:	74 6e                	je     1020b15 <myl_core_ir_str_append_char+0x315>
 1020aa7:	48 89 df             	mov    %rbx,%rdi
 1020aaa:	e8 f1 ca 03 00       	call   105d5a0 <malloc_usable_size@plt>
 1020aaf:	48 83 3d 19 23 04 00 	cmpq   $0x0,0x42319(%rip)        # 1062dd0 <heap_ceiling>
 1020ab6:	00 
 1020ab7:	74 5c                	je     1020b15 <myl_core_ir_str_append_char+0x315>
 1020ab9:	48 89 c1             	mov    %rax,%rcx
 1020abc:	48 8b 05 4d 4e 06 00 	mov    0x64e4d(%rip),%rax        # 1085910 <heap_held>
 1020ac3:	31 d2                	xor    %edx,%edx
 1020ac5:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1020acc:	0f 1f 84 00 00 00 00 
 1020ad3:	00 
 1020ad4:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1020adb:	0f 1f 84 00 00 00 00 
 1020ae2:	00 
 1020ae3:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1020aea:	0f 1f 84 00 00 00 00 
 1020af1:	00 
 1020af2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1020af9:	1f 84 00 00 00 00 00 
 1020b00:	48 89 c6             	mov    %rax,%rsi
 1020b03:	48 29 ce             	sub    %rcx,%rsi
 1020b06:	48 0f 42 f2          	cmovb  %rdx,%rsi
 1020b0a:	f0 48 0f b1 35 fd 4d 	lock cmpxchg %rsi,0x64dfd(%rip)        # 1085910 <heap_held>
 1020b11:	06 00 
 1020b13:	75 eb                	jne    1020b00 <myl_core_ir_str_append_char+0x300>
 1020b15:	48 89 df             	mov    %rbx,%rdi
 1020b18:	e8 a3 ca 03 00       	call   105d5c0 <free@plt>
 1020b1d:	4c 89 f3             	mov    %r14,%rbx
 1020b20:	8b 7d d0             	mov    -0x30(%rbp),%edi
 1020b23:	4c 8b 45 c8          	mov    -0x38(%rbp),%r8
 1020b27:	4c 89 43 08          	mov    %r8,0x8(%rbx)
 1020b2b:	42 c6 44 03 20 00    	movb   $0x0,0x20(%rbx,%r8,1)
 1020b31:	b8 ff f8 ff ff       	mov    $0xfffff8ff,%eax
 1020b36:	23 03                	and    (%rbx),%eax
 1020b38:	8d 88 00 01 00 00    	lea    0x100(%rax),%ecx
 1020b3e:	40 84 ff             	test   %dil,%dil
 1020b41:	0f 44 c8             	cmove  %eax,%ecx
 1020b44:	89 0b                	mov    %ecx,(%rbx)
 1020b46:	48 c7 43 18 00 00 00 	movq   $0x0,0x18(%rbx)
 1020b4d:	00 
 1020b4e:	48 89 d8             	mov    %rbx,%rax
 1020b51:	48 83 c4 18          	add    $0x18,%rsp
 1020b55:	5b                   	pop    %rbx
 1020b56:	41 5c                	pop    %r12
 1020b58:	41 5d                	pop    %r13
 1020b5a:	41 5e                	pop    %r14
 1020b5c:	41 5f                	pop    %r15
 1020b5e:	5d                   	pop    %rbp
 1020b5f:	c3                   	ret
 1020b60:	e8 5b 66 ff ff       	call   10171c0 <out_of_memory>
 1020b65:	bf ff ff ff ff       	mov    $0xffffffff,%edi
 1020b6a:	e8 11 a2 02 00       	call   104ad80 <myl_core_s2_unsupported>
 1020b6f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1020b76:	0f 1f 84 00 00 00 00 
 1020b7d:	00 
 1020b7e:	66 90                	xchg   %ax,%ax
