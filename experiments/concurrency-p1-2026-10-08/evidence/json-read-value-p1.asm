
.mylang-cache/concurrency-p1/tax-rows/p1/json_transform:     file format elf64-x86-64


Disassembly of section .text:

00000000010426e0 <my.json::read_value>:
 10426e0:	55                   	push   %rbp
 10426e1:	41 57                	push   %r15
 10426e3:	41 56                	push   %r14
 10426e5:	41 55                	push   %r13
 10426e7:	41 54                	push   %r12
 10426e9:	53                   	push   %rbx
 10426ea:	48 81 ec 88 01 00 00 	sub    $0x188,%rsp
 10426f1:	49 89 d2             	mov    %rdx,%r10
 10426f4:	49 89 f4             	mov    %rsi,%r12
 10426f7:	48 89 4c 24 58       	mov    %rcx,0x58(%rsp)
 10426fc:	48 83 f9 40          	cmp    $0x40,%rcx
 1042700:	0f 8f 1f 12 00 00    	jg     1043925 <my.json::read_value+0x1245>
 1042706:	48 89 7c 24 18       	mov    %rdi,0x18(%rsp)
 104270b:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042710:	49 39 d2             	cmp    %rdx,%r10
 1042713:	0f 8d 63 00 00 00    	jge    104277c <my.json::read_value+0x9c>
 1042719:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 1042720:	00 00 00
 1042723:	4c 89 e6             	mov    %r12,%rsi
 1042726:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104272d:	0f 1f 84 00 00 00 00
 1042734:	00
 1042735:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 104273c:	00 00 00 00
 1042740:	4c 89 d7             	mov    %r10,%rdi
 1042743:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1042747:	48 21 d7             	and    %rdx,%rdi
 104274a:	4e 8d 04 17          	lea    (%rdi,%r10,1),%r8
 104274e:	49 39 d0             	cmp    %rdx,%r8
 1042751:	0f 83 30 1d 00 00    	jae    1044487 <my.json::read_value+0x1da7>
 1042757:	48 01 fe             	add    %rdi,%rsi
 104275a:	41 0f b6 54 32 20    	movzbl 0x20(%r10,%rsi,1),%edx
 1042760:	48 83 fa 20          	cmp    $0x20,%rdx
 1042764:	77 16                	ja     104277c <my.json::read_value+0x9c>
 1042766:	48 0f a3 d0          	bt     %rdx,%rax
 104276a:	73 10                	jae    104277c <my.json::read_value+0x9c>
 104276c:	49 ff c2             	inc    %r10
 104276f:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042774:	4c 89 e6             	mov    %r12,%rsi
 1042777:	49 39 d2             	cmp    %rdx,%r10
 104277a:	7c c4                	jl     1042740 <my.json::read_value+0x60>
 104277c:	4d 89 e5             	mov    %r12,%r13
 104277f:	4c 89 d2             	mov    %r10,%rdx
 1042782:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 1042787:	49 39 c2             	cmp    %rax,%r10
 104278a:	0f 8d d0 11 00 00    	jge    1043960 <my.json::read_value+0x1280>
 1042790:	4c 89 d6             	mov    %r10,%rsi
 1042793:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1042797:	48 21 c6             	and    %rax,%rsi
 104279a:	4c 01 d6             	add    %r10,%rsi
 104279d:	48 39 c6             	cmp    %rax,%rsi
 10427a0:	0f 83 f0 1d 00 00    	jae    1044596 <my.json::read_value+0x1eb6>
 10427a6:	41 0f b6 74 35 20    	movzbl 0x20(%r13,%rsi,1),%esi
 10427ac:	40 0f b6 fe          	movzbl %sil,%edi
 10427b0:	44 8d 47 a5          	lea    -0x5b(%rdi),%r8d
 10427b4:	41 83 f8 20          	cmp    $0x20,%r8d
 10427b8:	0f 87 97 03 00 00    	ja     1042b55 <my.json::read_value+0x475>
 10427be:	48 8d 3d 1b 43 fc ff 	lea    -0x3bce5(%rip),%rdi        # 1006ae0 <core_number_pairs+0x110>
 10427c5:	4e 63 04 87          	movslq (%rdi,%r8,4),%r8
 10427c9:	49 01 f8             	add    %rdi,%r8
 10427cc:	41 ff e0             	jmp    *%r8
 10427cf:	49 8d 52 01          	lea    0x1(%r10),%rdx
 10427d3:	48 8d 0d 76 50 03 00 	lea    0x35076(%rip),%rcx        # 1077850 <myl_core_free_lists>
 10427da:	48 8b 59 08          	mov    0x8(%rcx),%rbx
 10427de:	48 85 db             	test   %rbx,%rbx
 10427e1:	0f 84 6e 1c 00 00    	je     1044455 <my.json::read_value+0x1d75>
 10427e7:	48 8b 03             	mov    (%rbx),%rax
 10427ea:	48 89 41 08          	mov    %rax,0x8(%rcx)
 10427ee:	48 b8 01 00 00 00 00 	movabs $0x100000000000001,%rax
 10427f5:	00 00 01
 10427f8:	48 89 03             	mov    %rax,(%rbx)
 10427fb:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
 10427ff:	c5 fa 7f 43 08       	vmovdqu %xmm0,0x8(%rbx)
 1042804:	48 c7 43 18 00 00 00 	movq   $0x0,0x18(%rbx)
 104280b:	00
 104280c:	48 8d 05 21 65 fc ff 	lea    -0x39adf(%rip),%rax        # 1008d34 <core_number_pairs+0x2364>
 1042813:	48 89 43 18          	mov    %rax,0x18(%rbx)
 1042817:	49 8b 45 08          	mov    0x8(%r13),%rax
 104281b:	48 39 c2             	cmp    %rax,%rdx
 104281e:	7d 6a                	jge    104288a <my.json::read_value+0x1aa>
 1042820:	48 bf 00 26 00 00 01 	movabs $0x100002600,%rdi
 1042827:	00 00 00
 104282a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042831:	0f 1f 84 00 00 00 00
 1042838:	00
 1042839:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1042840:	49 8d 72 01          	lea    0x1(%r10),%rsi
 1042844:	49 89 f0             	mov    %rsi,%r8
 1042847:	49 c1 f8 3f          	sar    $0x3f,%r8
 104284b:	49 21 c0             	and    %rax,%r8
 104284e:	4f 8d 0c 02          	lea    (%r10,%r8,1),%r9
 1042852:	49 ff c1             	inc    %r9
 1042855:	49 39 c1             	cmp    %rax,%r9
 1042858:	0f 83 bb 1c 00 00    	jae    1044519 <my.json::read_value+0x1e39>
 104285e:	4d 01 c5             	add    %r8,%r13
 1042861:	43 0f b6 44 2a 21    	movzbl 0x21(%r10,%r13,1),%eax
 1042867:	48 83 f8 20          	cmp    $0x20,%rax
 104286b:	77 1d                	ja     104288a <my.json::read_value+0x1aa>
 104286d:	48 0f a3 c7          	bt     %rax,%rdi
 1042871:	73 17                	jae    104288a <my.json::read_value+0x1aa>
 1042873:	4c 89 d2             	mov    %r10,%rdx
 1042876:	48 83 c2 02          	add    $0x2,%rdx
 104287a:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 104287f:	49 89 f2             	mov    %rsi,%r10
 1042882:	4d 89 e5             	mov    %r12,%r13
 1042885:	48 39 c2             	cmp    %rax,%rdx
 1042888:	7c b6                	jl     1042840 <my.json::read_value+0x160>
 104288a:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 104288f:	48 39 c2             	cmp    %rax,%rdx
 1042892:	0f 8d a4 16 00 00    	jge    1043f3c <my.json::read_value+0x185c>
 1042898:	48 89 d1             	mov    %rdx,%rcx
 104289b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 104289f:	48 21 c1             	and    %rax,%rcx
 10428a2:	48 01 d1             	add    %rdx,%rcx
 10428a5:	48 39 c1             	cmp    %rax,%rcx
 10428a8:	0f 83 8d 1d 00 00    	jae    104463b <my.json::read_value+0x1f5b>
 10428ae:	41 80 7c 0c 20 5d    	cmpb   $0x5d,0x20(%r12,%rcx,1)
 10428b4:	0f 84 1e 11 00 00    	je     10439d8 <my.json::read_value+0x12f8>
 10428ba:	48 ff 44 24 58       	incq   0x58(%rsp)
 10428bf:	48 bd 00 26 00 00 01 	movabs $0x100002600,%rbp
 10428c6:	00 00 00
 10428c9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 10428d0:	48 8d 7c 24 78       	lea    0x78(%rsp),%rdi
 10428d5:	4c 89 e6             	mov    %r12,%rsi
 10428d8:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 10428dd:	e8 fe fd ff ff       	call   10426e0 <my.json::read_value>
 10428e2:	4c 8b 74 24 78       	mov    0x78(%rsp),%r14
 10428e7:	4c 8b bc 24 80 00 00 	mov    0x80(%rsp),%r15
 10428ee:	00
 10428ef:	41 0f b6 c6          	movzbl %r14b,%eax
 10428f3:	4c 8b a4 24 90 00 00 	mov    0x90(%rsp),%r12
 10428fa:	00
 10428fb:	48 8b 94 24 98 00 00 	mov    0x98(%rsp),%rdx
 1042902:	00
 1042903:	83 f8 01             	cmp    $0x1,%eax
 1042906:	0f 84 a8 15 00 00    	je     1043eb4 <my.json::read_value+0x17d4>
 104290c:	4c 8b ac 24 88 00 00 	mov    0x88(%rsp),%r13
 1042913:	00
 1042914:	41 80 ff 06          	cmp    $0x6,%r15b
 1042918:	74 0e                	je     1042928 <my.json::read_value+0x248>
 104291a:	41 0f b6 c7          	movzbl %r15b,%eax
 104291e:	83 f8 05             	cmp    $0x5,%eax
 1042921:	74 05                	je     1042928 <my.json::read_value+0x248>
 1042923:	83 f8 04             	cmp    $0x4,%eax
 1042926:	75 21                	jne    1042949 <my.json::read_value+0x269>
 1042928:	41 8b 45 00          	mov    0x0(%r13),%eax
 104292c:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1042931:	77 0d                	ja     1042940 <my.json::read_value+0x260>
 1042933:	ff c0                	inc    %eax
 1042935:	41 89 45 00          	mov    %eax,0x0(%r13)
 1042939:	eb 0e                	jmp    1042949 <my.json::read_value+0x269>
 104293b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1042940:	83 f8 ff             	cmp    $0xffffffff,%eax
 1042943:	0f 85 bb 01 00 00    	jne    1042b04 <my.json::read_value+0x424>
 1042949:	48 8b 43 08          	mov    0x8(%rbx),%rax
 104294d:	48 3b 43 10          	cmp    0x10(%rbx),%rax
 1042951:	0f 83 ca 01 00 00    	jae    1042b21 <my.json::read_value+0x441>
 1042957:	48 89 c1             	mov    %rax,%rcx
 104295a:	48 c1 e1 04          	shl    $0x4,%rcx
 104295e:	41 0f b6 f7          	movzbl %r15b,%esi
 1042962:	48 89 74 0b 20       	mov    %rsi,0x20(%rbx,%rcx,1)
 1042967:	4c 89 6c 0b 28       	mov    %r13,0x28(%rbx,%rcx,1)
 104296c:	48 ff c0             	inc    %rax
 104296f:	48 89 43 08          	mov    %rax,0x8(%rbx)
 1042973:	41 80 fe 01          	cmp    $0x1,%r14b
 1042977:	74 47                	je     10429c0 <my.json::read_value+0x2e0>
 1042979:	41 0f b6 c6          	movzbl %r14b,%eax
 104297d:	85 c0                	test   %eax,%eax
 104297f:	0f 85 fb 00 00 00    	jne    1042a80 <my.json::read_value+0x3a0>
 1042985:	41 80 ff 06          	cmp    $0x6,%r15b
 1042989:	74 6b                	je     10429f6 <my.json::read_value+0x316>
 104298b:	41 0f b6 c7          	movzbl %r15b,%eax
 104298f:	83 f8 05             	cmp    $0x5,%eax
 1042992:	74 4d                	je     10429e1 <my.json::read_value+0x301>
 1042994:	83 f8 04             	cmp    $0x4,%eax
 1042997:	0f 85 e3 00 00 00    	jne    1042a80 <my.json::read_value+0x3a0>
 104299d:	41 8b 45 00          	mov    0x0(%r13),%eax
 10429a1:	85 c0                	test   %eax,%eax
 10429a3:	78 63                	js     1042a08 <my.json::read_value+0x328>
 10429a5:	ff c8                	dec    %eax
 10429a7:	0f 84 9d 00 00 00    	je     1042a4a <my.json::read_value+0x36a>
 10429ad:	41 89 45 00          	mov    %eax,0x0(%r13)
 10429b1:	e9 ca 00 00 00       	jmp    1042a80 <my.json::read_value+0x3a0>
 10429b6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 10429bd:	00 00 00
 10429c0:	41 8b 07             	mov    (%r15),%eax
 10429c3:	85 c0                	test   %eax,%eax
 10429c5:	78 0c                	js     10429d3 <my.json::read_value+0x2f3>
 10429c7:	ff c8                	dec    %eax
 10429c9:	74 52                	je     1042a1d <my.json::read_value+0x33d>
 10429cb:	41 89 07             	mov    %eax,(%r15)
 10429ce:	e9 ad 00 00 00       	jmp    1042a80 <my.json::read_value+0x3a0>
 10429d3:	83 f8 ff             	cmp    $0xffffffff,%eax
 10429d6:	0f 84 a4 00 00 00    	je     1042a80 <my.json::read_value+0x3a0>
 10429dc:	4c 89 ff             	mov    %r15,%rdi
 10429df:	eb 2f                	jmp    1042a10 <my.json::read_value+0x330>
 10429e1:	41 8b 45 00          	mov    0x0(%r13),%eax
 10429e5:	85 c0                	test   %eax,%eax
 10429e7:	78 1f                	js     1042a08 <my.json::read_value+0x328>
 10429e9:	ff c8                	dec    %eax
 10429eb:	74 5d                	je     1042a4a <my.json::read_value+0x36a>
 10429ed:	41 89 45 00          	mov    %eax,0x0(%r13)
 10429f1:	e9 8a 00 00 00       	jmp    1042a80 <my.json::read_value+0x3a0>
 10429f6:	41 8b 45 00          	mov    0x0(%r13),%eax
 10429fa:	85 c0                	test   %eax,%eax
 10429fc:	78 0a                	js     1042a08 <my.json::read_value+0x328>
 10429fe:	ff c8                	dec    %eax
 1042a00:	74 48                	je     1042a4a <my.json::read_value+0x36a>
 1042a02:	41 89 45 00          	mov    %eax,0x0(%r13)
 1042a06:	eb 78                	jmp    1042a80 <my.json::read_value+0x3a0>
 1042a08:	83 f8 ff             	cmp    $0xffffffff,%eax
 1042a0b:	74 73                	je     1042a80 <my.json::read_value+0x3a0>
 1042a0d:	4c 89 ef             	mov    %r13,%rdi
 1042a10:	49 89 d6             	mov    %rdx,%r14
 1042a13:	e8 68 e1 ff ff       	call   1040b80 <myl_core_release_slow>
 1042a18:	4c 89 f2             	mov    %r14,%rdx
 1042a1b:	eb 63                	jmp    1042a80 <my.json::read_value+0x3a0>
 1042a1d:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 1042a22:	48 85 c0             	test   %rax,%rax
 1042a25:	0f 84 15 01 00 00    	je     1042b40 <my.json::read_value+0x460>
 1042a2b:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 1042a30:	0f 85 0a 01 00 00    	jne    1042b40 <my.json::read_value+0x460>
 1042a36:	48 8d 35 13 4e 03 00 	lea    0x34e13(%rip),%rsi        # 1077850 <myl_core_free_lists>
 1042a3d:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1042a41:	49 89 0f             	mov    %rcx,(%r15)
 1042a44:	4c 89 3c c6          	mov    %r15,(%rsi,%rax,8)
 1042a48:	eb 36                	jmp    1042a80 <my.json::read_value+0x3a0>
 1042a4a:	41 0f b6 45 07       	movzbl 0x7(%r13),%eax
 1042a4f:	48 85 c0             	test   %rax,%rax
 1042a52:	0f 84 ed 00 00 00    	je     1042b45 <my.json::read_value+0x465>
 1042a58:	49 83 7d 18 00       	cmpq   $0x0,0x18(%r13)
 1042a5d:	0f 85 e2 00 00 00    	jne    1042b45 <my.json::read_value+0x465>
 1042a63:	48 8d 35 e6 4d 03 00 	lea    0x34de6(%rip),%rsi        # 1077850 <myl_core_free_lists>
 1042a6a:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1042a6e:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 1042a72:	4c 89 2c c6          	mov    %r13,(%rsi,%rax,8)
 1042a76:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 1042a7d:	00 00 00
 1042a80:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 1042a85:	48 39 c2             	cmp    %rax,%rdx
 1042a88:	7d 36                	jge    1042ac0 <my.json::read_value+0x3e0>
 1042a8a:	48 89 d1             	mov    %rdx,%rcx
 1042a8d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1042a91:	48 21 c1             	and    %rax,%rcx
 1042a94:	48 8d 34 11          	lea    (%rcx,%rdx,1),%rsi
 1042a98:	48 39 c6             	cmp    %rax,%rsi
 1042a9b:	0f 83 d4 19 00 00    	jae    1044475 <my.json::read_value+0x1d95>
 1042aa1:	4c 01 e1             	add    %r12,%rcx
 1042aa4:	0f b6 44 0a 20       	movzbl 0x20(%rdx,%rcx,1),%eax
 1042aa9:	48 83 f8 20          	cmp    $0x20,%rax
 1042aad:	77 11                	ja     1042ac0 <my.json::read_value+0x3e0>
 1042aaf:	48 0f a3 c5          	bt     %rax,%rbp
 1042ab3:	73 0b                	jae    1042ac0 <my.json::read_value+0x3e0>
 1042ab5:	48 ff c2             	inc    %rdx
 1042ab8:	eb c6                	jmp    1042a80 <my.json::read_value+0x3a0>
 1042aba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1042ac0:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 1042ac5:	48 39 c2             	cmp    %rax,%rdx
 1042ac8:	0f 8d 74 12 00 00    	jge    1043d42 <my.json::read_value+0x1662>
 1042ace:	48 89 d1             	mov    %rdx,%rcx
 1042ad1:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1042ad5:	48 21 c1             	and    %rax,%rcx
 1042ad8:	48 01 d1             	add    %rdx,%rcx
 1042adb:	48 39 c1             	cmp    %rax,%rcx
 1042ade:	0f 83 6a 1a 00 00    	jae    104454e <my.json::read_value+0x1e6e>
 1042ae4:	41 0f b6 4c 0c 20    	movzbl 0x20(%r12,%rcx,1),%ecx
 1042aea:	83 f9 2c             	cmp    $0x2c,%ecx
 1042aed:	0f 85 dc 0e 00 00    	jne    10439cf <my.json::read_value+0x12ef>
 1042af3:	48 ff c2             	inc    %rdx
 1042af6:	48 39 c2             	cmp    %rax,%rdx
 1042af9:	0f 8c d1 fd ff ff    	jl     10428d0 <my.json::read_value+0x1f0>
 1042aff:	e9 14 14 00 00       	jmp    1043f18 <my.json::read_value+0x1838>
 1042b04:	4c 89 ef             	mov    %r13,%rdi
 1042b07:	4c 89 64 24 38       	mov    %r12,0x38(%rsp)
 1042b0c:	49 89 d4             	mov    %rdx,%r12
 1042b0f:	e8 2c e0 ff ff       	call   1040b40 <myl_core_retain_slow>
 1042b14:	4c 89 e2             	mov    %r12,%rdx
 1042b17:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 1042b1c:	e9 28 fe ff ff       	jmp    1042949 <my.json::read_value+0x269>
 1042b21:	be 10 00 00 00       	mov    $0x10,%esi
 1042b26:	48 89 df             	mov    %rbx,%rdi
 1042b29:	48 89 d3             	mov    %rdx,%rbx
 1042b2c:	e8 8f 10 fd ff       	call   1013bc0 <myl_core_list_grow>
 1042b31:	48 89 da             	mov    %rbx,%rdx
 1042b34:	48 89 c3             	mov    %rax,%rbx
 1042b37:	48 8b 40 08          	mov    0x8(%rax),%rax
 1042b3b:	e9 17 fe ff ff       	jmp    1042957 <my.json::read_value+0x277>
 1042b40:	4c 89 ff             	mov    %r15,%rdi
 1042b43:	eb 03                	jmp    1042b48 <my.json::read_value+0x468>
 1042b45:	4c 89 ef             	mov    %r13,%rdi
 1042b48:	49 89 d6             	mov    %rdx,%r14
 1042b4b:	e8 b0 e0 ff ff       	call   1040c00 <myl_core_free_block>
 1042b50:	e9 c3 fe ff ff       	jmp    1042a18 <my.json::read_value+0x338>
 1042b55:	83 ff 22             	cmp    $0x22,%edi
 1042b58:	0f 84 6e 0d 00 00    	je     10438cc <my.json::read_value+0x11ec>
 1042b5e:	83 ff 2d             	cmp    $0x2d,%edi
 1042b61:	74 0d                	je     1042b70 <my.json::read_value+0x490>
 1042b63:	8d 7e d0             	lea    -0x30(%rsi),%edi
 1042b66:	40 80 ff 0a          	cmp    $0xa,%dil
 1042b6a:	0f 83 d8 0f 00 00    	jae    1043b48 <my.json::read_value+0x1468>
 1042b70:	49 8d 7a 01          	lea    0x1(%r10),%rdi
 1042b74:	40 80 fe 2d          	cmp    $0x2d,%sil
 1042b78:	4d 89 d6             	mov    %r10,%r14
 1042b7b:	4c 0f 44 f7          	cmove  %rdi,%r14
 1042b7f:	48 0f 44 d7          	cmove  %rdi,%rdx
 1042b83:	49 39 c6             	cmp    %rax,%r14
 1042b86:	0f 8d a9 0e 00 00    	jge    1043a35 <my.json::read_value+0x1355>
 1042b8c:	4c 89 f6             	mov    %r14,%rsi
 1042b8f:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1042b93:	48 21 c6             	and    %rax,%rsi
 1042b96:	4c 01 f6             	add    %r14,%rsi
 1042b99:	48 39 c6             	cmp    %rax,%rsi
 1042b9c:	0f 83 69 1a 00 00    	jae    104460b <my.json::read_value+0x1f2b>
 1042ba2:	41 0f b6 74 35 20    	movzbl 0x20(%r13,%rsi,1),%esi
 1042ba8:	8d 7e d0             	lea    -0x30(%rsi),%edi
 1042bab:	40 80 ff 0a          	cmp    $0xa,%dil
 1042baf:	0f 83 80 0e 00 00    	jae    1043a35 <my.json::read_value+0x1355>
 1042bb5:	40 80 fe 30          	cmp    $0x30,%sil
 1042bb9:	0f 85 ab 0c 00 00    	jne    104386a <my.json::read_value+0x118a>
 1042bbf:	49 8d 76 01          	lea    0x1(%r14),%rsi
 1042bc3:	bb 01 00 00 00       	mov    $0x1,%ebx
 1042bc8:	48 39 c6             	cmp    %rax,%rsi
 1042bcb:	7d 26                	jge    1042bf3 <my.json::read_value+0x513>
 1042bcd:	31 d2                	xor    %edx,%edx
 1042bcf:	49 83 fe ff          	cmp    $0xffffffffffffffff,%r14
 1042bd3:	48 0f 4c d0          	cmovl  %rax,%rdx
 1042bd7:	48 01 f2             	add    %rsi,%rdx
 1042bda:	48 39 c2             	cmp    %rax,%rdx
 1042bdd:	0f 83 b0 1a 00 00    	jae    1044693 <my.json::read_value+0x1fb3>
 1042be3:	41 0f b6 44 15 20    	movzbl 0x20(%r13,%rdx,1),%eax
 1042be9:	04 d0                	add    $0xd0,%al
 1042beb:	3c 0a                	cmp    $0xa,%al
 1042bed:	0f 82 5a 12 00 00    	jb     1043e4d <my.json::read_value+0x176d>
 1042bf3:	31 c0                	xor    %eax,%eax
 1042bf5:	49 89 f6             	mov    %rsi,%r14
 1042bf8:	3c 01                	cmp    $0x1,%al
 1042bfa:	0f 84 ad 0d 00 00    	je     10439ad <my.json::read_value+0x12cd>
 1042c00:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042c05:	49 39 d6             	cmp    %rdx,%r14
 1042c08:	0f 8d c1 00 00 00    	jge    1042ccf <my.json::read_value+0x5ef>
 1042c0e:	4c 89 f0             	mov    %r14,%rax
 1042c11:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042c15:	48 21 d0             	and    %rdx,%rax
 1042c18:	4c 01 f0             	add    %r14,%rax
 1042c1b:	48 39 d0             	cmp    %rdx,%rax
 1042c1e:	0f 83 38 1a 00 00    	jae    104465c <my.json::read_value+0x1f7c>
 1042c24:	41 80 7c 04 20 2e    	cmpb   $0x2e,0x20(%r12,%rax,1)
 1042c2a:	0f 85 9f 00 00 00    	jne    1042ccf <my.json::read_value+0x5ef>
 1042c30:	4d 8d 7e 01          	lea    0x1(%r14),%r15
 1042c34:	49 39 d7             	cmp    %rdx,%r15
 1042c37:	0f 8d f2 0f 00 00    	jge    1043c2f <my.json::read_value+0x154f>
 1042c3d:	31 c0                	xor    %eax,%eax
 1042c3f:	49 83 fe ff          	cmp    $0xffffffffffffffff,%r14
 1042c43:	48 0f 4c c2          	cmovl  %rdx,%rax
 1042c47:	4c 01 f8             	add    %r15,%rax
 1042c4a:	48 39 d0             	cmp    %rdx,%rax
 1042c4d:	0f 83 4f 1a 00 00    	jae    10446a2 <my.json::read_value+0x1fc2>
 1042c53:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 1042c59:	04 d0                	add    $0xd0,%al
 1042c5b:	3c 09                	cmp    $0x9,%al
 1042c5d:	0f 87 cc 0f 00 00    	ja     1043c2f <my.json::read_value+0x154f>
 1042c63:	bb 01 00 00 00       	mov    $0x1,%ebx
 1042c68:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042c6f:	0f 1f 84 00 00 00 00
 1042c76:	00
 1042c77:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1042c7e:	00 00
 1042c80:	49 8d 76 01          	lea    0x1(%r14),%rsi
 1042c84:	48 89 f0             	mov    %rsi,%rax
 1042c87:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042c8b:	48 21 d0             	and    %rdx,%rax
 1042c8e:	49 8d 3c 06          	lea    (%r14,%rax,1),%rdi
 1042c92:	48 ff c7             	inc    %rdi
 1042c95:	48 39 d7             	cmp    %rdx,%rdi
 1042c98:	0f 83 0a 19 00 00    	jae    10445a8 <my.json::read_value+0x1ec8>
 1042c9e:	4c 89 e2             	mov    %r12,%rdx
 1042ca1:	48 01 c2             	add    %rax,%rdx
 1042ca4:	41 0f b6 44 16 21    	movzbl 0x21(%r14,%rdx,1),%eax
 1042caa:	04 d0                	add    $0xd0,%al
 1042cac:	3c 0a                	cmp    $0xa,%al
 1042cae:	73 14                	jae    1042cc4 <my.json::read_value+0x5e4>
 1042cb0:	4d 89 f7             	mov    %r14,%r15
 1042cb3:	49 83 c7 02          	add    $0x2,%r15
 1042cb7:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042cbc:	49 89 f6             	mov    %rsi,%r14
 1042cbf:	49 39 d7             	cmp    %rdx,%r15
 1042cc2:	7c bc                	jl     1042c80 <my.json::read_value+0x5a0>
 1042cc4:	31 c0                	xor    %eax,%eax
 1042cc6:	3c 01                	cmp    $0x1,%al
 1042cc8:	75 14                	jne    1042cde <my.json::read_value+0x5fe>
 1042cca:	e9 91 0f 00 00       	jmp    1043c60 <my.json::read_value+0x1580>
 1042ccf:	31 c0                	xor    %eax,%eax
 1042cd1:	31 db                	xor    %ebx,%ebx
 1042cd3:	4d 89 f7             	mov    %r14,%r15
 1042cd6:	3c 01                	cmp    $0x1,%al
 1042cd8:	0f 84 82 0f 00 00    	je     1043c60 <my.json::read_value+0x1580>
 1042cde:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042ce3:	49 39 d7             	cmp    %rdx,%r15
 1042ce6:	0f 8d dd 00 00 00    	jge    1042dc9 <my.json::read_value+0x6e9>
 1042cec:	4c 89 f8             	mov    %r15,%rax
 1042cef:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042cf3:	48 21 d0             	and    %rdx,%rax
 1042cf6:	4c 01 f8             	add    %r15,%rax
 1042cf9:	48 39 d0             	cmp    %rdx,%rax
 1042cfc:	0f 83 69 19 00 00    	jae    104466b <my.json::read_value+0x1f8b>
 1042d02:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 1042d08:	83 c8 20             	or     $0x20,%eax
 1042d0b:	83 f8 65             	cmp    $0x65,%eax
 1042d0e:	0f 85 b5 00 00 00    	jne    1042dc9 <my.json::read_value+0x6e9>
 1042d14:	4d 8d 77 01          	lea    0x1(%r15),%r14
 1042d18:	49 39 d6             	cmp    %rdx,%r14
 1042d1b:	7d 2d                	jge    1042d4a <my.json::read_value+0x66a>
 1042d1d:	31 c0                	xor    %eax,%eax
 1042d1f:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 1042d23:	48 0f 4c c2          	cmovl  %rdx,%rax
 1042d27:	4c 01 f0             	add    %r14,%rax
 1042d2a:	48 39 d0             	cmp    %rdx,%rax
 1042d2d:	0f 83 7e 19 00 00    	jae    10446b1 <my.json::read_value+0x1fd1>
 1042d33:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 1042d39:	83 f8 2d             	cmp    $0x2d,%eax
 1042d3c:	74 05                	je     1042d43 <my.json::read_value+0x663>
 1042d3e:	83 f8 2b             	cmp    $0x2b,%eax
 1042d41:	75 07                	jne    1042d4a <my.json::read_value+0x66a>
 1042d43:	49 83 c7 02          	add    $0x2,%r15
 1042d47:	4d 89 fe             	mov    %r15,%r14
 1042d4a:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042d4f:	49 39 d6             	cmp    %rdx,%r14
 1042d52:	0f 8d 14 0e 00 00    	jge    1043b6c <my.json::read_value+0x148c>
 1042d58:	4c 89 f0             	mov    %r14,%rax
 1042d5b:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042d5f:	48 21 d0             	and    %rdx,%rax
 1042d62:	4c 01 f0             	add    %r14,%rax
 1042d65:	48 39 d0             	cmp    %rdx,%rax
 1042d68:	0f 83 16 19 00 00    	jae    1044684 <my.json::read_value+0x1fa4>
 1042d6e:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 1042d74:	04 d0                	add    $0xd0,%al
 1042d76:	3c 09                	cmp    $0x9,%al
 1042d78:	0f 87 ee 0d 00 00    	ja     1043b6c <my.json::read_value+0x148c>
 1042d7e:	66 90                	xchg   %ax,%ax
 1042d80:	4c 89 f0             	mov    %r14,%rax
 1042d83:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042d87:	48 21 d0             	and    %rdx,%rax
 1042d8a:	4a 8d 34 30          	lea    (%rax,%r14,1),%rsi
 1042d8e:	48 39 d6             	cmp    %rdx,%rsi
 1042d91:	0f 83 f0 17 00 00    	jae    1044587 <my.json::read_value+0x1ea7>
 1042d97:	4c 89 e2             	mov    %r12,%rdx
 1042d9a:	48 01 c2             	add    %rax,%rdx
 1042d9d:	41 0f b6 54 16 20    	movzbl 0x20(%r14,%rdx,1),%edx
 1042da3:	80 c2 d0             	add    $0xd0,%dl
 1042da6:	b8 01 00 00 00       	mov    $0x1,%eax
 1042dab:	80 fa 0a             	cmp    $0xa,%dl
 1042dae:	73 0d                	jae    1042dbd <my.json::read_value+0x6dd>
 1042db0:	49 ff c6             	inc    %r14
 1042db3:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042db8:	49 39 d6             	cmp    %rdx,%r14
 1042dbb:	7c c3                	jl     1042d80 <my.json::read_value+0x6a0>
 1042dbd:	31 d2                	xor    %edx,%edx
 1042dbf:	80 fa 01             	cmp    $0x1,%dl
 1042dc2:	75 15                	jne    1042dd9 <my.json::read_value+0x6f9>
 1042dc4:	e9 d2 0d 00 00       	jmp    1043b9b <my.json::read_value+0x14bb>
 1042dc9:	31 d2                	xor    %edx,%edx
 1042dcb:	31 c0                	xor    %eax,%eax
 1042dcd:	4d 89 fe             	mov    %r15,%r14
 1042dd0:	80 fa 01             	cmp    $0x1,%dl
 1042dd3:	0f 84 c2 0d 00 00    	je     1043b9b <my.json::read_value+0x14bb>
 1042dd9:	08 d8                	or     %bl,%al
 1042ddb:	a8 01                	test   $0x1,%al
 1042ddd:	75 1f                	jne    1042dfe <my.json::read_value+0x71e>
 1042ddf:	4c 89 e7             	mov    %r12,%rdi
 1042de2:	4c 89 d6             	mov    %r10,%rsi
 1042de5:	4c 89 d3             	mov    %r10,%rbx
 1042de8:	4c 89 f2             	mov    %r14,%rdx
 1042deb:	e8 d0 86 fe ff       	call   102b4c0 <myl_core_parse_int_range>
 1042df0:	49 89 da             	mov    %rbx,%r10
 1042df3:	3c 01                	cmp    $0x1,%al
 1042df5:	75 07                	jne    1042dfe <my.json::read_value+0x71e>
 1042df7:	bb 02 00 00 00       	mov    $0x2,%ebx
 1042dfc:	eb 20                	jmp    1042e1e <my.json::read_value+0x73e>
 1042dfe:	4c 89 e7             	mov    %r12,%rdi
 1042e01:	4c 89 d6             	mov    %r10,%rsi
 1042e04:	4c 89 f2             	mov    %r14,%rdx
 1042e07:	e8 d4 86 00 00       	call   104b4e0 <myl_core_parse_float_range>
 1042e0c:	3c 01                	cmp    $0x1,%al
 1042e0e:	0f 85 cb 0c 00 00    	jne    1043adf <my.json::read_value+0x13ff>
 1042e14:	c4 e1 f9 7e c2       	vmovq  %xmm0,%rdx
 1042e19:	bb 03 00 00 00       	mov    $0x3,%ebx
 1042e1e:	31 c0                	xor    %eax,%eax
 1042e20:	e9 e2 11 00 00       	jmp    1044007 <my.json::read_value+0x1927>
 1042e25:	48 8d 0d 14 54 fc ff 	lea    -0x3abec(%rip),%rcx        # 1008240 <core_number_pairs+0x1870>
 1042e2c:	48 8d bc 24 38 01 00 	lea    0x138(%rsp),%rdi
 1042e33:	00
 1042e34:	4c 89 e6             	mov    %r12,%rsi
 1042e37:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 1042e3d:	45 31 c9             	xor    %r9d,%r9d
 1042e40:	e8 1b 29 00 00       	call   1045760 <my.json::read_literal>
 1042e45:	0f b6 84 24 38 01 00 	movzbl 0x138(%rsp),%eax
 1042e4c:	00
 1042e4d:	c5 fa 6f 84 24 40 01 	vmovdqu 0x140(%rsp),%xmm0
 1042e54:	00 00
 1042e56:	48 8b 8c 24 50 01 00 	mov    0x150(%rsp),%rcx
 1042e5d:	00
 1042e5e:	4c 8b b4 24 58 01 00 	mov    0x158(%rsp),%r14
 1042e65:	00
 1042e66:	48 83 f8 01          	cmp    $0x1,%rax
 1042e6a:	0f 85 aa 00 00 00    	jne    1042f1a <my.json::read_value+0x83a>
 1042e70:	48 8d 3d 89 f3 00 00 	lea    0xf389(%rip),%rdi        # 1052200 <core_io_file_error.verbs+0x560>
 1042e77:	e9 4b 0d 00 00       	jmp    1043bc7 <my.json::read_value+0x14e7>
 1042e7c:	48 8d 0d fd 53 fc ff 	lea    -0x3ac03(%rip),%rcx        # 1008280 <core_number_pairs+0x18b0>
 1042e83:	48 8d bc 24 10 01 00 	lea    0x110(%rsp),%rdi
 1042e8a:	00
 1042e8b:	4c 89 e6             	mov    %r12,%rsi
 1042e8e:	45 31 c0             	xor    %r8d,%r8d
 1042e91:	45 31 c9             	xor    %r9d,%r9d
 1042e94:	e8 c7 28 00 00       	call   1045760 <my.json::read_literal>
 1042e99:	0f b6 84 24 10 01 00 	movzbl 0x110(%rsp),%eax
 1042ea0:	00
 1042ea1:	c5 fa 6f 84 24 18 01 	vmovdqu 0x118(%rsp),%xmm0
 1042ea8:	00 00
 1042eaa:	48 8b 8c 24 28 01 00 	mov    0x128(%rsp),%rcx
 1042eb1:	00
 1042eb2:	4c 8b b4 24 30 01 00 	mov    0x130(%rsp),%r14
 1042eb9:	00
 1042eba:	48 83 f8 01          	cmp    $0x1,%rax
 1042ebe:	75 5a                	jne    1042f1a <my.json::read_value+0x83a>
 1042ec0:	48 8d 3d 69 f3 00 00 	lea    0xf369(%rip),%rdi        # 1052230 <core_io_file_error.verbs+0x590>
 1042ec7:	e9 fb 0c 00 00       	jmp    1043bc7 <my.json::read_value+0x14e7>
 1042ecc:	48 8d 0d 2d 53 fc ff 	lea    -0x3acd3(%rip),%rcx        # 1008200 <core_number_pairs+0x1830>
 1042ed3:	48 8d bc 24 60 01 00 	lea    0x160(%rsp),%rdi
 1042eda:	00
 1042edb:	41 b9 01 00 00 00    	mov    $0x1,%r9d
 1042ee1:	4c 89 e6             	mov    %r12,%rsi
 1042ee4:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 1042eea:	e8 71 28 00 00       	call   1045760 <my.json::read_literal>
 1042eef:	0f b6 84 24 60 01 00 	movzbl 0x160(%rsp),%eax
 1042ef6:	00
 1042ef7:	c5 fa 6f 84 24 68 01 	vmovdqu 0x168(%rsp),%xmm0
 1042efe:	00 00
 1042f00:	48 8b 8c 24 78 01 00 	mov    0x178(%rsp),%rcx
 1042f07:	00
 1042f08:	4c 8b b4 24 80 01 00 	mov    0x180(%rsp),%r14
 1042f0f:	00
 1042f10:	48 83 f8 01          	cmp    $0x1,%rax
 1042f14:	0f 84 a6 0c 00 00    	je     1043bc0 <my.json::read_value+0x14e0>
 1042f1a:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 1042f1f:	48 89 02             	mov    %rax,(%rdx)
 1042f22:	48 89 d0             	mov    %rdx,%rax
 1042f25:	c5 fa 7f 42 08       	vmovdqu %xmm0,0x8(%rdx)
 1042f2a:	48 89 4a 18          	mov    %rcx,0x18(%rdx)
 1042f2e:	e9 e1 13 00 00       	jmp    1044314 <my.json::read_value+0x1c34>
 1042f33:	4c 89 d3             	mov    %r10,%rbx
 1042f36:	4d 8d 7a 01          	lea    0x1(%r10),%r15
 1042f3a:	48 8d 35 17 fc 00 00 	lea    0xfc17(%rip),%rsi        # 1052b58 <core_io_file_error.verbs+0xeb8>
 1042f41:	31 ff                	xor    %edi,%edi
 1042f43:	e8 b8 77 fd ff       	call   101a700 <myl_core_dict_new>
 1042f48:	48 89 c5             	mov    %rax,%rbp
 1042f4b:	49 8b 55 08          	mov    0x8(%r13),%rdx
 1042f4f:	49 39 d7             	cmp    %rdx,%r15
 1042f52:	7d 76                	jge    1042fca <my.json::read_value+0x8ea>
 1042f54:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 1042f5b:	00 00 00
 1042f5e:	48 89 d9             	mov    %rbx,%rcx
 1042f61:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042f68:	0f 1f 84 00 00 00 00
 1042f6f:	00
 1042f70:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042f77:	0f 1f 84 00 00 00 00
 1042f7e:	00
 1042f7f:	90                   	nop
 1042f80:	48 8d 71 01          	lea    0x1(%rcx),%rsi
 1042f84:	48 89 f7             	mov    %rsi,%rdi
 1042f87:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1042f8b:	48 21 d7             	and    %rdx,%rdi
 1042f8e:	4c 8d 04 39          	lea    (%rcx,%rdi,1),%r8
 1042f92:	49 ff c0             	inc    %r8
 1042f95:	49 39 d0             	cmp    %rdx,%r8
 1042f98:	0f 83 8a 15 00 00    	jae    1044528 <my.json::read_value+0x1e48>
 1042f9e:	49 01 fd             	add    %rdi,%r13
 1042fa1:	42 0f b6 54 29 21    	movzbl 0x21(%rcx,%r13,1),%edx
 1042fa7:	48 83 fa 20          	cmp    $0x20,%rdx
 1042fab:	77 1d                	ja     1042fca <my.json::read_value+0x8ea>
 1042fad:	48 0f a3 d0          	bt     %rdx,%rax
 1042fb1:	73 17                	jae    1042fca <my.json::read_value+0x8ea>
 1042fb3:	49 89 cf             	mov    %rcx,%r15
 1042fb6:	49 83 c7 02          	add    $0x2,%r15
 1042fba:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042fbf:	48 89 f1             	mov    %rsi,%rcx
 1042fc2:	4d 89 e5             	mov    %r12,%r13
 1042fc5:	49 39 d7             	cmp    %rdx,%r15
 1042fc8:	7c b6                	jl     1042f80 <my.json::read_value+0x8a0>
 1042fca:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042fcf:	49 39 d7             	cmp    %rdx,%r15
 1042fd2:	0f 8d 2d 0b 00 00    	jge    1043b05 <my.json::read_value+0x1425>
 1042fd8:	4c 89 f8             	mov    %r15,%rax
 1042fdb:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042fdf:	48 21 d0             	and    %rdx,%rax
 1042fe2:	4c 01 f8             	add    %r15,%rax
 1042fe5:	48 39 d0             	cmp    %rdx,%rax
 1042fe8:	0f 83 5f 16 00 00    	jae    104464d <my.json::read_value+0x1f6d>
 1042fee:	41 80 7c 04 20 7d    	cmpb   $0x7d,0x20(%r12,%rax,1)
 1042ff4:	0f 84 80 0a 00 00    	je     1043a7a <my.json::read_value+0x139a>
 1042ffa:	48 ff 44 24 58       	incq   0x58(%rsp)
 1042fff:	49 bd 00 26 00 00 01 	movabs $0x100002600,%r13
 1043006:	00 00 00
 1043009:	4d 89 e6             	mov    %r12,%r14
 104300c:	0f 1f 40 00          	nopl   0x0(%rax)
 1043010:	49 39 d7             	cmp    %rdx,%r15
 1043013:	7d 38                	jge    104304d <my.json::read_value+0x96d>
 1043015:	4c 89 f8             	mov    %r15,%rax
 1043018:	48 c1 f8 3f          	sar    $0x3f,%rax
 104301c:	48 21 d0             	and    %rdx,%rax
 104301f:	4a 8d 0c 38          	lea    (%rax,%r15,1),%rcx
 1043023:	48 39 d1             	cmp    %rdx,%rcx
 1043026:	0f 83 6a 14 00 00    	jae    1044496 <my.json::read_value+0x1db6>
 104302c:	49 01 c4             	add    %rax,%r12
 104302f:	43 0f b6 44 27 20    	movzbl 0x20(%r15,%r12,1),%eax
 1043035:	48 83 f8 20          	cmp    $0x20,%rax
 1043039:	77 12                	ja     104304d <my.json::read_value+0x96d>
 104303b:	49 0f a3 c5          	bt     %rax,%r13
 104303f:	73 0c                	jae    104304d <my.json::read_value+0x96d>
 1043041:	49 ff c7             	inc    %r15
 1043044:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1043048:	4d 89 f4             	mov    %r14,%r12
 104304b:	eb c3                	jmp    1043010 <my.json::read_value+0x930>
 104304d:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1043051:	49 39 d7             	cmp    %rdx,%r15
 1043054:	0f 8d 7f 0d 00 00    	jge    1043dd9 <my.json::read_value+0x16f9>
 104305a:	4c 89 f8             	mov    %r15,%rax
 104305d:	48 c1 f8 3f          	sar    $0x3f,%rax
 1043061:	48 21 d0             	and    %rdx,%rax
 1043064:	4c 01 f8             	add    %r15,%rax
 1043067:	48 39 d0             	cmp    %rdx,%rax
 104306a:	0f 83 44 15 00 00    	jae    10445b4 <my.json::read_value+0x1ed4>
 1043070:	41 80 7c 06 20 22    	cmpb   $0x22,0x20(%r14,%rax,1)
 1043076:	0f 85 5d 0d 00 00    	jne    1043dd9 <my.json::read_value+0x16f9>
 104307c:	48 8d bc 24 c0 00 00 	lea    0xc0(%rsp),%rdi
 1043083:	00
 1043084:	4c 89 f6             	mov    %r14,%rsi
 1043087:	4c 89 fa             	mov    %r15,%rdx
 104308a:	e8 81 1a 00 00       	call   1044b10 <my.json::read_string>
 104308f:	48 8b bc 24 c8 00 00 	mov    0xc8(%rsp),%rdi
 1043096:	00
 1043097:	4c 8b bc 24 d8 00 00 	mov    0xd8(%rsp),%r15
 104309e:	00
 104309f:	4c 8b b4 24 d0 00 00 	mov    0xd0(%rsp),%r14
 10430a6:	00
 10430a7:	0f b6 84 24 c0 00 00 	movzbl 0xc0(%rsp),%eax
 10430ae:	00
 10430af:	3c 01                	cmp    $0x1,%al
 10430b1:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 10430b6:	0f 84 7c 10 00 00    	je     1044138 <my.json::read_value+0x1a58>
 10430bc:	48 89 7c 24 70       	mov    %rdi,0x70(%rsp)
 10430c1:	f6 47 05 02          	testb  $0x2,0x5(%rdi)
 10430c5:	88 44 24 07          	mov    %al,0x7(%rsp)
 10430c9:	75 07                	jne    10430d2 <my.json::read_value+0x9f2>
 10430cb:	e8 b0 8a fd ff       	call   101bb80 <myl_core_str_hash>
 10430d0:	eb 03                	jmp    10430d5 <my.json::read_value+0x9f5>
 10430d2:	8b 47 18             	mov    0x18(%rdi),%eax
 10430d5:	89 c0                	mov    %eax,%eax
 10430d7:	48 b9 15 7c 4a 7f b9 	movabs $0x9e3779b97f4a7c15,%rcx
 10430de:	79 37 9e
 10430e1:	48 0f af c1          	imul   %rcx,%rax
 10430e5:	48 89 c6             	mov    %rax,%rsi
 10430e8:	48 c1 ee 20          	shr    $0x20,%rsi
 10430ec:	48 31 c6             	xor    %rax,%rsi
 10430ef:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 10430f4:	48 8b 4d 18          	mov    0x18(%rbp),%rcx
 10430f8:	48 8b 41 08          	mov    0x8(%rcx),%rax
 10430fc:	48 85 c0             	test   %rax,%rax
 10430ff:	48 89 74 24 08       	mov    %rsi,0x8(%rsp)
 1043104:	0f 84 c2 00 00 00    	je     10431cc <my.json::read_value+0xaec>
 104310a:	8b 08                	mov    (%rax),%ecx
 104310c:	f3 0f bc d1          	tzcnt  %ecx,%edx
 1043110:	f6 da                	neg    %dl
 1043112:	c4 62 eb f7 ee       	shrx   %rdx,%rsi,%r13
 1043117:	c4 a1 7a 6f 4c 28 10 	vmovdqu 0x10(%rax,%r13,1),%xmm1
 104311e:	89 f2                	mov    %esi,%edx
 1043120:	80 e2 7f             	and    $0x7f,%dl
 1043123:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 1043127:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 104312c:	c5 f9 7f 4c 24 40    	vmovdqa %xmm1,0x40(%rsp)
 1043132:	c5 f1 74 c0          	vpcmpeqb %xmm0,%xmm1,%xmm0
 1043136:	c5 f9 d7 d0          	vpmovmskb %xmm0,%edx
 104313a:	85 d2                	test   %edx,%edx
 104313c:	74 76                	je     10431b4 <my.json::read_value+0xad4>
 104313e:	8d 69 ff             	lea    -0x1(%rcx),%ebp
 1043141:	83 c1 1e             	add    $0x1e,%ecx
 1043144:	83 e1 f0             	and    $0xfffffff0,%ecx
 1043147:	48 8d 1c 08          	lea    (%rax,%rcx,1),%rbx
 104314b:	48 83 c3 10          	add    $0x10,%rbx
 104314f:	44 0f b7 e2          	movzwl %dx,%r12d
 1043153:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104315a:	0f 1f 84 00 00 00 00
 1043161:	00
 1043162:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043169:	0f 1f 84 00 00 00 00
 1043170:	00
 1043171:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043178:	0f 1f 84 00 00 00 00
 104317f:	00
 1043180:	f3 41 0f bc c4       	tzcnt  %r12d,%eax
 1043185:	44 01 e8             	add    %r13d,%eax
 1043188:	21 e8                	and    %ebp,%eax
 104318a:	8b 04 83             	mov    (%rbx,%rax,4),%eax
 104318d:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 1043191:	48 8b 4c 24 20       	mov    0x20(%rsp),%rcx
 1043196:	48 8b 7c c1 20       	mov    0x20(%rcx,%rax,8),%rdi
 104319b:	48 8b 74 24 70       	mov    0x70(%rsp),%rsi
 10431a0:	e8 5b 8b fd ff       	call   101bd00 <myl_core_str_eq>
 10431a5:	84 c0                	test   %al,%al
 10431a7:	0f 85 dc 08 00 00    	jne    1043a89 <my.json::read_value+0x13a9>
 10431ad:	c4 c2 18 f3 cc       	blsr   %r12d,%r12d
 10431b2:	75 cc                	jne    1043180 <my.json::read_value+0xaa0>
 10431b4:	c5 f9 6f 44 24 40    	vmovdqa 0x40(%rsp),%xmm0
 10431ba:	c5 f9 74 05 1e 0c fc 	vpcmpeqb -0x3f3e2(%rip),%xmm0,%xmm0        # 1003de0 <__anon_2214+0x50>
 10431c1:	ff
 10431c2:	c5 f9 d7 c0          	vpmovmskb %xmm0,%eax
 10431c6:	85 c0                	test   %eax,%eax
 10431c8:	75 2d                	jne    10431f7 <my.json::read_value+0xb17>
 10431ca:	eb 0b                	jmp    10431d7 <my.json::read_value+0xaf7>
 10431cc:	48 83 79 18 00       	cmpq   $0x0,0x18(%rcx)
 10431d1:	0f 84 f5 03 00 00    	je     10435cc <my.json::read_value+0xeec>
 10431d7:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 10431dc:	48 8d 74 24 70       	lea    0x70(%rsp),%rsi
 10431e1:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 10431e6:	e8 55 71 fd ff       	call   101a340 <myl_core_dict_find>
 10431eb:	49 89 c5             	mov    %rax,%r13
 10431ee:	4d 85 ed             	test   %r13,%r13
 10431f1:	0f 89 92 08 00 00    	jns    1043a89 <my.json::read_value+0x13a9>
 10431f7:	49 8b 56 08          	mov    0x8(%r14),%rdx
 10431fb:	49 39 d7             	cmp    %rdx,%r15
 10431fe:	0f 8d 76 00 00 00    	jge    104327a <my.json::read_value+0xb9a>
 1043204:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 1043209:	48 be 00 26 00 00 01 	movabs $0x100002600,%rsi
 1043210:	00 00 00
 1043213:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104321a:	0f 1f 84 00 00 00 00
 1043221:	00
 1043222:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043229:	0f 1f 84 00 00 00 00
 1043230:	00
 1043231:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043238:	0f 1f 84 00 00 00 00
 104323f:	00
 1043240:	4c 89 f8             	mov    %r15,%rax
 1043243:	48 c1 f8 3f          	sar    $0x3f,%rax
 1043247:	48 21 d0             	and    %rdx,%rax
 104324a:	4a 8d 0c 38          	lea    (%rax,%r15,1),%rcx
 104324e:	48 39 d1             	cmp    %rdx,%rcx
 1043251:	0f 83 4e 12 00 00    	jae    10444a5 <my.json::read_value+0x1dc5>
 1043257:	4c 01 f0             	add    %r14,%rax
 104325a:	41 0f b6 44 07 20    	movzbl 0x20(%r15,%rax,1),%eax
 1043260:	48 83 f8 20          	cmp    $0x20,%rax
 1043264:	77 19                	ja     104327f <my.json::read_value+0xb9f>
 1043266:	48 0f a3 c6          	bt     %rax,%rsi
 104326a:	73 13                	jae    104327f <my.json::read_value+0xb9f>
 104326c:	49 ff c7             	inc    %r15
 104326f:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1043273:	49 39 d7             	cmp    %rdx,%r15
 1043276:	7c c8                	jl     1043240 <my.json::read_value+0xb60>
 1043278:	eb 05                	jmp    104327f <my.json::read_value+0xb9f>
 104327a:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 104327f:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1043283:	49 39 d7             	cmp    %rdx,%r15
 1043286:	0f 8d 70 0b 00 00    	jge    1043dfc <my.json::read_value+0x171c>
 104328c:	4c 89 f8             	mov    %r15,%rax
 104328f:	48 c1 f8 3f          	sar    $0x3f,%rax
 1043293:	48 21 d0             	and    %rdx,%rax
 1043296:	4c 01 f8             	add    %r15,%rax
 1043299:	48 39 d0             	cmp    %rdx,%rax
 104329c:	0f 83 21 13 00 00    	jae    10445c3 <my.json::read_value+0x1ee3>
 10432a2:	41 80 7c 06 20 3a    	cmpb   $0x3a,0x20(%r14,%rax,1)
 10432a8:	0f 85 4e 0b 00 00    	jne    1043dfc <my.json::read_value+0x171c>
 10432ae:	49 ff c7             	inc    %r15
 10432b1:	48 8d 7c 24 78       	lea    0x78(%rsp),%rdi
 10432b6:	4c 89 f6             	mov    %r14,%rsi
 10432b9:	4c 89 fa             	mov    %r15,%rdx
 10432bc:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 10432c1:	e8 1a f4 ff ff       	call   10426e0 <my.json::read_value>
 10432c6:	48 8b 4c 24 78       	mov    0x78(%rsp),%rcx
 10432cb:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 10432d2:	00
 10432d3:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 10432d8:	0f b6 c1             	movzbl %cl,%eax
 10432db:	4c 8b b4 24 90 00 00 	mov    0x90(%rsp),%r14
 10432e2:	00
 10432e3:	4c 8b bc 24 98 00 00 	mov    0x98(%rsp),%r15
 10432ea:	00
 10432eb:	83 f8 01             	cmp    $0x1,%eax
 10432ee:	0f 84 6c 0e 00 00    	je     1044160 <my.json::read_value+0x1a80>
 10432f4:	48 89 8c 24 a0 00 00 	mov    %rcx,0xa0(%rsp)
 10432fb:	00
 10432fc:	48 8b 84 24 88 00 00 	mov    0x88(%rsp),%rax
 1043303:	00
 1043304:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
 1043309:	83 7d 00 01          	cmpl   $0x1,0x0(%rbp)
 104330d:	75 0c                	jne    104331b <my.json::read_value+0xc3b>
 104330f:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 1043314:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043319:	eb 34                	jmp    104334f <my.json::read_value+0xc6f>
 104331b:	48 89 ef             	mov    %rbp,%rdi
 104331e:	e8 1d 80 fd ff       	call   101b340 <myl_core_dict_copy>
 1043323:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 1043328:	8b 45 00             	mov    0x0(%rbp),%eax
 104332b:	85 c0                	test   %eax,%eax
 104332d:	78 12                	js     1043341 <my.json::read_value+0xc61>
 104332f:	ff c8                	dec    %eax
 1043331:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043336:	0f 84 92 03 00 00    	je     10436ce <my.json::read_value+0xfee>
 104333c:	89 45 00             	mov    %eax,0x0(%rbp)
 104333f:	eb 0e                	jmp    104334f <my.json::read_value+0xc6f>
 1043341:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043344:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043349:	0f 85 ed 04 00 00    	jne    104383c <my.json::read_value+0x115c>
 104334f:	48 89 7c 24 68       	mov    %rdi,0x68(%rsp)
 1043354:	f6 47 05 02          	testb  $0x2,0x5(%rdi)
 1043358:	75 07                	jne    1043361 <my.json::read_value+0xc81>
 104335a:	e8 21 88 fd ff       	call   101bb80 <myl_core_str_hash>
 104335f:	eb 03                	jmp    1043364 <my.json::read_value+0xc84>
 1043361:	8b 47 18             	mov    0x18(%rdi),%eax
 1043364:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
 1043369:	89 c0                	mov    %eax,%eax
 104336b:	48 b9 15 7c 4a 7f b9 	movabs $0x9e3779b97f4a7c15,%rcx
 1043372:	79 37 9e
 1043375:	48 0f af c1          	imul   %rcx,%rax
 1043379:	48 89 c2             	mov    %rax,%rdx
 104337c:	48 c1 ea 20          	shr    $0x20,%rdx
 1043380:	48 31 c2             	xor    %rax,%rdx
 1043383:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 1043388:	48 8b 48 18          	mov    0x18(%rax),%rcx
 104338c:	48 8b 41 08          	mov    0x8(%rcx),%rax
 1043390:	48 85 c0             	test   %rax,%rax
 1043393:	0f 84 c4 00 00 00    	je     104345d <my.json::read_value+0xd7d>
 1043399:	8b 08                	mov    (%rax),%ecx
 104339b:	f3 0f bc f1          	tzcnt  %ecx,%esi
 104339f:	40 f6 de             	neg    %sil
 10433a2:	c4 e2 cb f7 ea       	shrx   %rsi,%rdx,%rbp
 10433a7:	44 8d 69 ff          	lea    -0x1(%rcx),%r13d
 10433ab:	c5 fa 6f 4c 28 10    	vmovdqu 0x10(%rax,%rbp,1),%xmm1
 10433b1:	48 89 54 24 60       	mov    %rdx,0x60(%rsp)
 10433b6:	80 e2 7f             	and    $0x7f,%dl
 10433b9:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 10433bd:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10433c2:	c5 f9 7f 8c 24 00 01 	vmovdqa %xmm1,0x100(%rsp)
 10433c9:	00 00
 10433cb:	c5 f1 74 c0          	vpcmpeqb %xmm0,%xmm1,%xmm0
 10433cf:	c5 f9 d7 d0          	vpmovmskb %xmm0,%edx
 10433d3:	85 d2                	test   %edx,%edx
 10433d5:	74 5a                	je     1043431 <my.json::read_value+0xd51>
 10433d7:	83 c1 1e             	add    $0x1e,%ecx
 10433da:	83 e1 f0             	and    $0xfffffff0,%ecx
 10433dd:	4c 8d 34 08          	lea    (%rax,%rcx,1),%r14
 10433e1:	49 83 c6 10          	add    $0x10,%r14
 10433e5:	44 0f b7 e2          	movzwl %dx,%r12d
 10433e9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10433f0:	0f 1f 84 00 00 00 00
 10433f7:	00
 10433f8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 10433ff:	00
 1043400:	f3 41 0f bc c4       	tzcnt  %r12d,%eax
 1043405:	01 e8                	add    %ebp,%eax
 1043407:	44 21 e8             	and    %r13d,%eax
 104340a:	41 8b 1c 86          	mov    (%r14,%rax,4),%ebx
 104340e:	48 8d 04 5b          	lea    (%rbx,%rbx,2),%rax
 1043412:	48 8b 4c 24 20       	mov    0x20(%rsp),%rcx
 1043417:	48 8b 7c c1 20       	mov    0x20(%rcx,%rax,8),%rdi
 104341c:	48 8b 74 24 68       	mov    0x68(%rsp),%rsi
 1043421:	e8 da 88 fd ff       	call   101bd00 <myl_core_str_eq>
 1043426:	84 c0                	test   %al,%al
 1043428:	75 50                	jne    104347a <my.json::read_value+0xd9a>
 104342a:	c4 c2 18 f3 cc       	blsr   %r12d,%r12d
 104342f:	75 cf                	jne    1043400 <my.json::read_value+0xd20>
 1043431:	c5 f9 6f 84 24 00 01 	vmovdqa 0x100(%rsp),%xmm0
 1043438:	00 00
 104343a:	c5 f9 74 05 9e 09 fc 	vpcmpeqb -0x3f662(%rip),%xmm0,%xmm0        # 1003de0 <__anon_2214+0x50>
 1043441:	ff
 1043442:	c5 f9 d7 c0          	vpmovmskb %xmm0,%eax
 1043446:	85 c0                	test   %eax,%eax
 1043448:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 104344d:	74 19                	je     1043468 <my.json::read_value+0xd88>
 104344f:	f3 0f bc d8          	tzcnt  %eax,%ebx
 1043453:	01 eb                	add    %ebp,%ebx
 1043455:	44 21 eb             	and    %r13d,%ebx
 1043458:	48 f7 d3             	not    %rbx
 104345b:	eb 1d                	jmp    104347a <my.json::read_value+0xd9a>
 104345d:	48 83 79 18 00       	cmpq   $0x0,0x18(%rcx)
 1043462:	0f 84 ca 01 00 00    	je     1043632 <my.json::read_value+0xf52>
 1043468:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 104346d:	48 8d 74 24 68       	lea    0x68(%rsp),%rsi
 1043472:	e8 c9 6e fd ff       	call   101a340 <myl_core_dict_find>
 1043477:	48 89 c3             	mov    %rax,%rbx
 104347a:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 104347f:	8b 01                	mov    (%rcx),%eax
 1043481:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043486:	77 1f                	ja     10434a7 <my.json::read_value+0xdc7>
 1043488:	ff c0                	inc    %eax
 104348a:	89 01                	mov    %eax,(%rcx)
 104348c:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 1043491:	49 bd 00 26 00 00 01 	movabs $0x100002600,%r13
 1043498:	00 00 00
 104349b:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 10434a0:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 10434a5:	eb 22                	jmp    10434c9 <my.json::read_value+0xde9>
 10434a7:	83 f8 ff             	cmp    $0xffffffff,%eax
 10434aa:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 10434af:	49 bd 00 26 00 00 01 	movabs $0x100002600,%r13
 10434b6:	00 00 00
 10434b9:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 10434be:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 10434c3:	0f 85 39 03 00 00    	jne    1043802 <my.json::read_value+0x1122>
 10434c9:	44 0f b6 f2          	movzbl %dl,%r14d
 10434cd:	41 80 fe 06          	cmp    $0x6,%r14b
 10434d1:	74 0c                	je     10434df <my.json::read_value+0xdff>
 10434d3:	41 83 fe 05          	cmp    $0x5,%r14d
 10434d7:	74 06                	je     10434df <my.json::read_value+0xdff>
 10434d9:	41 83 fe 04          	cmp    $0x4,%r14d
 10434dd:	75 18                	jne    10434f7 <my.json::read_value+0xe17>
 10434df:	8b 06                	mov    (%rsi),%eax
 10434e1:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 10434e6:	77 06                	ja     10434ee <my.json::read_value+0xe0e>
 10434e8:	ff c0                	inc    %eax
 10434ea:	89 06                	mov    %eax,(%rsi)
 10434ec:	eb 09                	jmp    10434f7 <my.json::read_value+0xe17>
 10434ee:	83 f8 ff             	cmp    $0xffffffff,%eax
 10434f1:	0f 85 27 03 00 00    	jne    104381e <my.json::read_value+0x113e>
 10434f7:	48 89 8c 24 a8 00 00 	mov    %rcx,0xa8(%rsp)
 10434fe:	00
 10434ff:	0f b6 c2             	movzbl %dl,%eax
 1043502:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
 1043509:	00
 104350a:	48 89 b4 24 b8 00 00 	mov    %rsi,0xb8(%rsp)
 1043511:	00
 1043512:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 1043517:	48 89 de             	mov    %rbx,%rsi
 104351a:	48 89 cb             	mov    %rcx,%rbx
 104351d:	48 8d 94 24 a8 00 00 	lea    0xa8(%rsp),%rdx
 1043524:	00
 1043525:	48 8d 8c 24 b0 00 00 	lea    0xb0(%rsp),%rcx
 104352c:	00
 104352d:	45 31 c0             	xor    %r8d,%r8d
 1043530:	e8 4b 74 fd ff       	call   101a980 <myl_core_dict_insert>
 1043535:	48 89 c5             	mov    %rax,%rbp
 1043538:	80 7c 24 07 00       	cmpb   $0x0,0x7(%rsp)
 104353d:	74 56                	je     1043595 <my.json::read_value+0xeb5>
 104353f:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
 1043546:	00
 1043547:	3c 01                	cmp    $0x1,%al
 1043549:	74 63                	je     10435ae <my.json::read_value+0xece>
 104354b:	0f b6 c0             	movzbl %al,%eax
 104354e:	85 c0                	test   %eax,%eax
 1043550:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
 1043555:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 104355a:	0f 85 20 02 00 00    	jne    1043780 <my.json::read_value+0x10a0>
 1043560:	3c 06                	cmp    $0x6,%al
 1043562:	0f 84 d3 01 00 00    	je     104373b <my.json::read_value+0x105b>
 1043568:	41 83 fe 05          	cmp    $0x5,%r14d
 104356c:	0f 84 bb 01 00 00    	je     104372d <my.json::read_value+0x104d>
 1043572:	41 83 fe 04          	cmp    $0x4,%r14d
 1043576:	0f 85 04 02 00 00    	jne    1043780 <my.json::read_value+0x10a0>
 104357c:	8b 07                	mov    (%rdi),%eax
 104357e:	85 c0                	test   %eax,%eax
 1043580:	0f 88 c3 01 00 00    	js     1043749 <my.json::read_value+0x1069>
 1043586:	ff c8                	dec    %eax
 1043588:	0f 84 c7 01 00 00    	je     1043755 <my.json::read_value+0x1075>
 104358e:	89 07                	mov    %eax,(%rdi)
 1043590:	e9 eb 01 00 00       	jmp    1043780 <my.json::read_value+0x10a0>
 1043595:	8b 03                	mov    (%rbx),%eax
 1043597:	85 c0                	test   %eax,%eax
 1043599:	48 89 df             	mov    %rbx,%rdi
 104359c:	0f 88 19 01 00 00    	js     10436bb <my.json::read_value+0xfdb>
 10435a2:	ff c8                	dec    %eax
 10435a4:	0f 84 54 01 00 00    	je     10436fe <my.json::read_value+0x101e>
 10435aa:	89 07                	mov    %eax,(%rdi)
 10435ac:	eb 91                	jmp    104353f <my.json::read_value+0xe5f>
 10435ae:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10435b3:	8b 07                	mov    (%rdi),%eax
 10435b5:	85 c0                	test   %eax,%eax
 10435b7:	0f 88 8c 01 00 00    	js     1043749 <my.json::read_value+0x1069>
 10435bd:	ff c8                	dec    %eax
 10435bf:	0f 84 90 01 00 00    	je     1043755 <my.json::read_value+0x1075>
 10435c5:	89 07                	mov    %eax,(%rdi)
 10435c7:	e9 b4 01 00 00       	jmp    1043780 <my.json::read_value+0x10a0>
 10435cc:	4c 8b 61 20          	mov    0x20(%rcx),%r12
 10435d0:	4d 85 e4             	test   %r12,%r12
 10435d3:	0f 84 1e fc ff ff    	je     10431f7 <my.json::read_value+0xb17>
 10435d9:	48 8b 59 10          	mov    0x10(%rcx),%rbx
 10435dd:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 10435e2:	48 8d 68 20          	lea    0x20(%rax),%rbp
 10435e6:	45 31 ed             	xor    %r13d,%r13d
 10435e9:	eb 25                	jmp    1043610 <my.json::read_value+0xf30>
 10435eb:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10435f2:	0f 1f 84 00 00 00 00
 10435f9:	00
 10435fa:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1043600:	49 ff c5             	inc    %r13
 1043603:	48 83 c5 18          	add    $0x18,%rbp
 1043607:	4d 39 ec             	cmp    %r13,%r12
 104360a:	0f 84 e7 fb ff ff    	je     10431f7 <my.json::read_value+0xb17>
 1043610:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
 1043615:	4a 39 04 eb          	cmp    %rax,(%rbx,%r13,8)
 1043619:	75 e5                	jne    1043600 <my.json::read_value+0xf20>
 104361b:	48 8b 7d 00          	mov    0x0(%rbp),%rdi
 104361f:	48 8b 74 24 70       	mov    0x70(%rsp),%rsi
 1043624:	e8 d7 86 fd ff       	call   101bd00 <myl_core_str_eq>
 1043629:	84 c0                	test   %al,%al
 104362b:	74 d3                	je     1043600 <my.json::read_value+0xf20>
 104362d:	e9 bc fb ff ff       	jmp    10431ee <my.json::read_value+0xb0e>
 1043632:	48 8b 71 20          	mov    0x20(%rcx),%rsi
 1043636:	48 c7 c3 ff ff ff ff 	mov    $0xffffffffffffffff,%rbx
 104363d:	48 85 f6             	test   %rsi,%rsi
 1043640:	0f 84 34 fe ff ff    	je     104347a <my.json::read_value+0xd9a>
 1043646:	4c 8b 71 10          	mov    0x10(%rcx),%r14
 104364a:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 104364f:	4c 8d 60 20          	lea    0x20(%rax),%r12
 1043653:	31 ed                	xor    %ebp,%ebp
 1043655:	48 89 74 24 60       	mov    %rsi,0x60(%rsp)
 104365a:	eb 34                	jmp    1043690 <my.json::read_value+0xfb0>
 104365c:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043663:	0f 1f 84 00 00 00 00
 104366a:	00
 104366b:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043672:	0f 1f 84 00 00 00 00
 1043679:	00
 104367a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1043680:	48 ff c5             	inc    %rbp
 1043683:	49 83 c4 18          	add    $0x18,%r12
 1043687:	48 39 ee             	cmp    %rbp,%rsi
 104368a:	0f 84 ea fd ff ff    	je     104347a <my.json::read_value+0xd9a>
 1043690:	49 39 14 ee          	cmp    %rdx,(%r14,%rbp,8)
 1043694:	75 ea                	jne    1043680 <my.json::read_value+0xfa0>
 1043696:	49 8b 3c 24          	mov    (%r12),%rdi
 104369a:	48 8b 74 24 68       	mov    0x68(%rsp),%rsi
 104369f:	49 89 d5             	mov    %rdx,%r13
 10436a2:	e8 59 86 fd ff       	call   101bd00 <myl_core_str_eq>
 10436a7:	48 8b 74 24 60       	mov    0x60(%rsp),%rsi
 10436ac:	4c 89 ea             	mov    %r13,%rdx
 10436af:	84 c0                	test   %al,%al
 10436b1:	74 cd                	je     1043680 <my.json::read_value+0xfa0>
 10436b3:	48 89 eb             	mov    %rbp,%rbx
 10436b6:	e9 bf fd ff ff       	jmp    104347a <my.json::read_value+0xd9a>
 10436bb:	83 f8 ff             	cmp    $0xffffffff,%eax
 10436be:	0f 84 7b fe ff ff    	je     104353f <my.json::read_value+0xe5f>
 10436c4:	e8 b7 d4 ff ff       	call   1040b80 <myl_core_release_slow>
 10436c9:	e9 71 fe ff ff       	jmp    104353f <my.json::read_value+0xe5f>
 10436ce:	0f b6 45 07          	movzbl 0x7(%rbp),%eax
 10436d2:	48 85 c0             	test   %rax,%rax
 10436d5:	0f 84 78 01 00 00    	je     1043853 <my.json::read_value+0x1173>
 10436db:	48 83 7d 18 00       	cmpq   $0x0,0x18(%rbp)
 10436e0:	0f 85 6d 01 00 00    	jne    1043853 <my.json::read_value+0x1173>
 10436e6:	48 8d 15 63 41 03 00 	lea    0x34163(%rip),%rdx        # 1077850 <myl_core_free_lists>
 10436ed:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 10436f1:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 10436f5:	48 89 2c c2          	mov    %rbp,(%rdx,%rax,8)
 10436f9:	e9 16 fc ff ff       	jmp    1043314 <my.json::read_value+0xc34>
 10436fe:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1043702:	48 85 c0             	test   %rax,%rax
 1043705:	0f 84 55 01 00 00    	je     1043860 <my.json::read_value+0x1180>
 104370b:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 1043710:	0f 85 4a 01 00 00    	jne    1043860 <my.json::read_value+0x1180>
 1043716:	48 8d 15 33 41 03 00 	lea    0x34133(%rip),%rdx        # 1077850 <myl_core_free_lists>
 104371d:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043721:	48 89 0f             	mov    %rcx,(%rdi)
 1043724:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 1043728:	e9 12 fe ff ff       	jmp    104353f <my.json::read_value+0xe5f>
 104372d:	8b 07                	mov    (%rdi),%eax
 104372f:	85 c0                	test   %eax,%eax
 1043731:	78 16                	js     1043749 <my.json::read_value+0x1069>
 1043733:	ff c8                	dec    %eax
 1043735:	74 1e                	je     1043755 <my.json::read_value+0x1075>
 1043737:	89 07                	mov    %eax,(%rdi)
 1043739:	eb 45                	jmp    1043780 <my.json::read_value+0x10a0>
 104373b:	8b 07                	mov    (%rdi),%eax
 104373d:	85 c0                	test   %eax,%eax
 104373f:	78 08                	js     1043749 <my.json::read_value+0x1069>
 1043741:	ff c8                	dec    %eax
 1043743:	74 10                	je     1043755 <my.json::read_value+0x1075>
 1043745:	89 07                	mov    %eax,(%rdi)
 1043747:	eb 37                	jmp    1043780 <my.json::read_value+0x10a0>
 1043749:	83 f8 ff             	cmp    $0xffffffff,%eax
 104374c:	74 32                	je     1043780 <my.json::read_value+0x10a0>
 104374e:	e8 2d d4 ff ff       	call   1040b80 <myl_core_release_slow>
 1043753:	eb 2b                	jmp    1043780 <my.json::read_value+0x10a0>
 1043755:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1043759:	48 85 c0             	test   %rax,%rax
 104375c:	0f 84 e7 00 00 00    	je     1043849 <my.json::read_value+0x1169>
 1043762:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 1043767:	0f 85 dc 00 00 00    	jne    1043849 <my.json::read_value+0x1169>
 104376d:	48 8d 15 dc 40 03 00 	lea    0x340dc(%rip),%rdx        # 1077850 <myl_core_free_lists>
 1043774:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043778:	48 89 0f             	mov    %rcx,(%rdi)
 104377b:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 104377f:	90                   	nop
 1043780:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1043785:	49 39 d7             	cmp    %rdx,%r15
 1043788:	7d 31                	jge    10437bb <my.json::read_value+0x10db>
 104378a:	4c 89 f8             	mov    %r15,%rax
 104378d:	48 c1 f8 3f          	sar    $0x3f,%rax
 1043791:	48 21 d0             	and    %rdx,%rax
 1043794:	4a 8d 0c 38          	lea    (%rax,%r15,1),%rcx
 1043798:	48 39 d1             	cmp    %rdx,%rcx
 104379b:	0f 83 13 0d 00 00    	jae    10444b4 <my.json::read_value+0x1dd4>
 10437a1:	4c 01 e0             	add    %r12,%rax
 10437a4:	41 0f b6 44 07 20    	movzbl 0x20(%r15,%rax,1),%eax
 10437aa:	48 83 f8 20          	cmp    $0x20,%rax
 10437ae:	77 0b                	ja     10437bb <my.json::read_value+0x10db>
 10437b0:	49 0f a3 c5          	bt     %rax,%r13
 10437b4:	73 05                	jae    10437bb <my.json::read_value+0x10db>
 10437b6:	49 ff c7             	inc    %r15
 10437b9:	eb c5                	jmp    1043780 <my.json::read_value+0x10a0>
 10437bb:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 10437c0:	49 39 d7             	cmp    %rdx,%r15
 10437c3:	0f 8d a8 06 00 00    	jge    1043e71 <my.json::read_value+0x1791>
 10437c9:	4c 89 f8             	mov    %r15,%rax
 10437cc:	48 c1 f8 3f          	sar    $0x3f,%rax
 10437d0:	48 21 d0             	and    %rdx,%rax
 10437d3:	4c 01 f8             	add    %r15,%rax
 10437d6:	48 39 d0             	cmp    %rdx,%rax
 10437d9:	0f 83 f3 0d 00 00    	jae    10445d2 <my.json::read_value+0x1ef2>
 10437df:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 10437e5:	83 f8 2c             	cmp    $0x2c,%eax
 10437e8:	0f 85 83 02 00 00    	jne    1043a71 <my.json::read_value+0x1391>
 10437ee:	49 ff c7             	inc    %r15
 10437f1:	4d 89 e6             	mov    %r12,%r14
 10437f4:	49 39 d7             	cmp    %rdx,%r15
 10437f7:	0f 8c 13 f8 ff ff    	jl     1043010 <my.json::read_value+0x930>
 10437fd:	e9 03 03 00 00       	jmp    1043b05 <my.json::read_value+0x1425>
 1043802:	48 89 cf             	mov    %rcx,%rdi
 1043805:	e8 36 d3 ff ff       	call   1040b40 <myl_core_retain_slow>
 104380a:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 104380f:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 1043814:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 1043819:	e9 ab fc ff ff       	jmp    10434c9 <my.json::read_value+0xde9>
 104381e:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1043823:	e8 18 d3 ff ff       	call   1040b40 <myl_core_retain_slow>
 1043828:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 104382d:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 1043832:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 1043837:	e9 bb fc ff ff       	jmp    10434f7 <my.json::read_value+0xe17>
 104383c:	48 89 ef             	mov    %rbp,%rdi
 104383f:	e8 3c d3 ff ff       	call   1040b80 <myl_core_release_slow>
 1043844:	e9 cb fa ff ff       	jmp    1043314 <my.json::read_value+0xc34>
 1043849:	e8 b2 d3 ff ff       	call   1040c00 <myl_core_free_block>
 104384e:	e9 2d ff ff ff       	jmp    1043780 <my.json::read_value+0x10a0>
 1043853:	48 89 ef             	mov    %rbp,%rdi
 1043856:	e8 a5 d3 ff ff       	call   1040c00 <myl_core_free_block>
 104385b:	e9 b4 fa ff ff       	jmp    1043314 <my.json::read_value+0xc34>
 1043860:	e8 9b d3 ff ff       	call   1040c00 <myl_core_free_block>
 1043865:	e9 d5 fc ff ff       	jmp    104353f <my.json::read_value+0xe5f>
 104386a:	bb 01 00 00 00       	mov    $0x1,%ebx
 104386f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043876:	0f 1f 84 00 00 00 00
 104387d:	00
 104387e:	66 90                	xchg   %ax,%ax
 1043880:	4c 89 f6             	mov    %r14,%rsi
 1043883:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1043887:	48 21 c6             	and    %rax,%rsi
 104388a:	4a 8d 3c 36          	lea    (%rsi,%r14,1),%rdi
 104388e:	48 39 c7             	cmp    %rax,%rdi
 1043891:	0f 83 70 0c 00 00    	jae    1044507 <my.json::read_value+0x1e27>
 1043897:	49 01 f5             	add    %rsi,%r13
 104389a:	43 0f b6 44 2e 20    	movzbl 0x20(%r14,%r13,1),%eax
 10438a0:	04 d0                	add    $0xd0,%al
 10438a2:	3c 0a                	cmp    $0xa,%al
 10438a4:	0f 83 f6 00 00 00    	jae    10439a0 <my.json::read_value+0x12c0>
 10438aa:	49 ff c6             	inc    %r14
 10438ad:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 10438b2:	4d 89 e5             	mov    %r12,%r13
 10438b5:	4c 89 f2             	mov    %r14,%rdx
 10438b8:	49 39 c6             	cmp    %rax,%r14
 10438bb:	7c c3                	jl     1043880 <my.json::read_value+0x11a0>
 10438bd:	31 c0                	xor    %eax,%eax
 10438bf:	3c 01                	cmp    $0x1,%al
 10438c1:	0f 85 39 f3 ff ff    	jne    1042c00 <my.json::read_value+0x520>
 10438c7:	e9 e1 00 00 00       	jmp    10439ad <my.json::read_value+0x12cd>
 10438cc:	48 8d bc 24 e0 00 00 	lea    0xe0(%rsp),%rdi
 10438d3:	00
 10438d4:	4c 89 e6             	mov    %r12,%rsi
 10438d7:	e8 34 12 00 00       	call   1044b10 <my.json::read_string>
 10438dc:	48 8b 9c 24 e8 00 00 	mov    0xe8(%rsp),%rbx
 10438e3:	00
 10438e4:	4c 8b b4 24 f8 00 00 	mov    0xf8(%rsp),%r14
 10438eb:	00
 10438ec:	4c 8b bc 24 f0 00 00 	mov    0xf0(%rsp),%r15
 10438f3:	00
 10438f4:	0f b6 ac 24 e0 00 00 	movzbl 0xe0(%rsp),%ebp
 10438fb:	00
 10438fc:	40 80 fd 01          	cmp    $0x1,%bpl
 1043900:	0f 84 06 04 00 00    	je     1043d0c <my.json::read_value+0x162c>
 1043906:	8b 03                	mov    (%rbx),%eax
 1043908:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 104390d:	0f 87 ef 00 00 00    	ja     1043a02 <my.json::read_value+0x1322>
 1043913:	ff c0                	inc    %eax
 1043915:	89 03                	mov    %eax,(%rbx)
 1043917:	40 84 ed             	test   %bpl,%bpl
 104391a:	0f 85 f4 00 00 00    	jne    1043a14 <my.json::read_value+0x1334>
 1043920:	e9 76 06 00 00       	jmp    1043f9b <my.json::read_value+0x18bb>
 1043925:	48 8d 15 74 48 fc ff 	lea    -0x3b78c(%rip),%rdx        # 10081a0 <core_number_pairs+0x17d0>
 104392c:	48 89 fb             	mov    %rdi,%rbx
 104392f:	4c 89 e7             	mov    %r12,%rdi
 1043932:	4c 89 d6             	mov    %r10,%rsi
 1043935:	4d 89 d6             	mov    %r10,%r14
 1043938:	e8 83 0d 00 00       	call   10446c0 <my.json::fail>
 104393d:	48 8d 3d cc e7 00 00 	lea    0xe7cc(%rip),%rdi        # 1052110 <core_io_file_error.verbs+0x470>
 1043944:	e8 77 d6 ff ff       	call   1040fc0 <myl_core_err_trace_origin_preserve_most>
 1043949:	48 c7 03 01 00 00 00 	movq   $0x1,(%rbx)
 1043950:	48 89 43 08          	mov    %rax,0x8(%rbx)
 1043954:	48 89 d8             	mov    %rbx,%rax
 1043957:	4c 89 63 18          	mov    %r12,0x18(%rbx)
 104395b:	e9 b4 09 00 00       	jmp    1044314 <my.json::read_value+0x1c34>
 1043960:	48 8d 05 59 49 fc ff 	lea    -0x3b6a7(%rip),%rax        # 10082c0 <core_number_pairs+0x18f0>
 1043967:	4c 89 e7             	mov    %r12,%rdi
 104396a:	48 89 d6             	mov    %rdx,%rsi
 104396d:	4d 89 d6             	mov    %r10,%r14
 1043970:	48 89 c2             	mov    %rax,%rdx
 1043973:	e8 48 0d 00 00       	call   10446c0 <my.json::fail>
 1043978:	48 8d 3d 11 e9 00 00 	lea    0xe911(%rip),%rdi        # 1052290 <core_io_file_error.verbs+0x5f0>
 104397f:	e8 3c d6 ff ff       	call   1040fc0 <myl_core_err_trace_origin_preserve_most>
 1043984:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 1043989:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 1043990:	48 89 41 08          	mov    %rax,0x8(%rcx)
 1043994:	48 89 c8             	mov    %rcx,%rax
 1043997:	4c 89 69 18          	mov    %r13,0x18(%rcx)
 104399b:	e9 74 09 00 00       	jmp    1044314 <my.json::read_value+0x1c34>
 10439a0:	31 c0                	xor    %eax,%eax
 10439a2:	49 89 d6             	mov    %rdx,%r14
 10439a5:	3c 01                	cmp    $0x1,%al
 10439a7:	0f 85 53 f2 ff ff    	jne    1042c00 <my.json::read_value+0x520>
 10439ad:	48 8d 3d 6c ec 00 00 	lea    0xec6c(%rip),%rdi        # 1052620 <core_io_file_error.verbs+0x980>
 10439b4:	e8 47 d6 ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 10439b9:	8b 03                	mov    (%rbx),%eax
 10439bb:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 10439c0:	0f 87 17 02 00 00    	ja     1043bdd <my.json::read_value+0x14fd>
 10439c6:	ff c0                	inc    %eax
 10439c8:	89 03                	mov    %eax,(%rbx)
 10439ca:	e9 1f 02 00 00       	jmp    1043bee <my.json::read_value+0x150e>
 10439cf:	83 f9 5d             	cmp    $0x5d,%ecx
 10439d2:	0f 85 6a 03 00 00    	jne    1043d42 <my.json::read_value+0x1662>
 10439d8:	48 ff c2             	inc    %rdx
 10439db:	41 bf 05 00 00 00    	mov    $0x5,%r15d
 10439e1:	31 c0                	xor    %eax,%eax
 10439e3:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 10439e8:	48 89 01             	mov    %rax,(%rcx)
 10439eb:	48 89 c8             	mov    %rcx,%rax
 10439ee:	4c 89 79 08          	mov    %r15,0x8(%rcx)
 10439f2:	48 89 59 10          	mov    %rbx,0x10(%rcx)
 10439f6:	4c 89 61 18          	mov    %r12,0x18(%rcx)
 10439fa:	49 89 d6             	mov    %rdx,%r14
 10439fd:	e9 12 09 00 00       	jmp    1044314 <my.json::read_value+0x1c34>
 1043a02:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043a05:	0f 85 7f 05 00 00    	jne    1043f8a <my.json::read_value+0x18aa>
 1043a0b:	40 84 ed             	test   %bpl,%bpl
 1043a0e:	0f 84 87 05 00 00    	je     1043f9b <my.json::read_value+0x18bb>
 1043a14:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 1043a19:	48 c7 00 00 00 00 00 	movq   $0x0,(%rax)
 1043a20:	48 c7 40 08 04 00 00 	movq   $0x4,0x8(%rax)
 1043a27:	00
 1043a28:	48 89 58 10          	mov    %rbx,0x10(%rax)
 1043a2c:	4c 89 78 18          	mov    %r15,0x18(%rax)
 1043a30:	e9 df 08 00 00       	jmp    1044314 <my.json::read_value+0x1c34>
 1043a35:	4d 89 d7             	mov    %r10,%r15
 1043a38:	48 8d 05 a1 50 fc ff 	lea    -0x3af5f(%rip),%rax        # 1008ae0 <core_number_pairs+0x2110>
 1043a3f:	4c 89 e7             	mov    %r12,%rdi
 1043a42:	49 89 d6             	mov    %rdx,%r14
 1043a45:	48 89 d6             	mov    %rdx,%rsi
 1043a48:	48 89 c2             	mov    %rax,%rdx
 1043a4b:	e8 70 0c 00 00       	call   10446c0 <my.json::fail>
 1043a50:	48 89 c3             	mov    %rax,%rbx
 1043a53:	48 8d 3d c6 ee 00 00 	lea    0xeec6(%rip),%rdi        # 1052920 <core_io_file_error.verbs+0xc80>
 1043a5a:	b0 01                	mov    $0x1,%al
 1043a5c:	e8 5f d5 ff ff       	call   1040fc0 <myl_core_err_trace_origin_preserve_most>
 1043a61:	4d 89 fa             	mov    %r15,%r10
 1043a64:	3c 01                	cmp    $0x1,%al
 1043a66:	0f 85 94 f1 ff ff    	jne    1042c00 <my.json::read_value+0x520>
 1043a6c:	e9 3c ff ff ff       	jmp    10439ad <my.json::read_value+0x12cd>
 1043a71:	83 f8 7d             	cmp    $0x7d,%eax
 1043a74:	0f 85 f7 03 00 00    	jne    1043e71 <my.json::read_value+0x1791>
 1043a7a:	49 ff c7             	inc    %r15
 1043a7d:	ba 06 00 00 00       	mov    $0x6,%edx
 1043a82:	31 c0                	xor    %eax,%eax
 1043a84:	e9 71 08 00 00       	jmp    10442fa <my.json::read_value+0x1c1a>
 1043a89:	80 7c 24 07 00       	cmpb   $0x0,0x7(%rsp)
 1043a8e:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 1043a93:	0f 85 8c 05 00 00    	jne    1044025 <my.json::read_value+0x1945>
 1043a99:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043a9e:	8b 07                	mov    (%rdi),%eax
 1043aa0:	85 c0                	test   %eax,%eax
 1043aa2:	0f 88 03 03 00 00    	js     1043dab <my.json::read_value+0x16cb>
 1043aa8:	ff c8                	dec    %eax
 1043aaa:	0f 85 73 05 00 00    	jne    1044023 <my.json::read_value+0x1943>
 1043ab0:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1043ab4:	48 85 c0             	test   %rax,%rax
 1043ab7:	0f 84 b3 0a 00 00    	je     1044570 <my.json::read_value+0x1e90>
 1043abd:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 1043ac2:	0f 85 a8 0a 00 00    	jne    1044570 <my.json::read_value+0x1e90>
 1043ac8:	48 8d 15 81 3d 03 00 	lea    0x33d81(%rip),%rdx        # 1077850 <myl_core_free_lists>
 1043acf:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043ad3:	48 89 0f             	mov    %rcx,(%rdi)
 1043ad6:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 1043ada:	e9 46 05 00 00       	jmp    1044025 <my.json::read_value+0x1945>
 1043adf:	48 8d 15 da 4c fc ff 	lea    -0x3b326(%rip),%rdx        # 10087c0 <core_number_pairs+0x1df0>
 1043ae6:	4c 89 e7             	mov    %r12,%rdi
 1043ae9:	4c 89 f6             	mov    %r14,%rsi
 1043aec:	e8 cf 0b 00 00       	call   10446c0 <my.json::fail>
 1043af1:	48 89 c3             	mov    %rax,%rbx
 1043af4:	48 8d 3d b5 eb 00 00 	lea    0xebb5(%rip),%rdi        # 10526b0 <core_io_file_error.verbs+0xa10>
 1043afb:	e8 c0 d4 ff ff       	call   1040fc0 <myl_core_err_trace_origin_preserve_most>
 1043b00:	e9 f1 04 00 00       	jmp    1043ff6 <my.json::read_value+0x1916>
 1043b05:	8b 45 00             	mov    0x0(%rbp),%eax
 1043b08:	85 c0                	test   %eax,%eax
 1043b0a:	0f 88 b3 02 00 00    	js     1043dc3 <my.json::read_value+0x16e3>
 1043b10:	ff c8                	dec    %eax
 1043b12:	0f 85 fa 05 00 00    	jne    1044112 <my.json::read_value+0x1a32>
 1043b18:	0f b6 45 07          	movzbl 0x7(%rbp),%eax
 1043b1c:	48 85 c0             	test   %rax,%rax
 1043b1f:	0f 84 55 0a 00 00    	je     104457a <my.json::read_value+0x1e9a>
 1043b25:	48 83 7d 18 00       	cmpq   $0x0,0x18(%rbp)
 1043b2a:	0f 85 4a 0a 00 00    	jne    104457a <my.json::read_value+0x1e9a>
 1043b30:	48 8d 0d 19 3d 03 00 	lea    0x33d19(%rip),%rcx        # 1077850 <myl_core_free_lists>
 1043b37:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1043b3b:	48 89 55 00          	mov    %rdx,0x0(%rbp)
 1043b3f:	48 89 2c c1          	mov    %rbp,(%rcx,%rax,8)
 1043b43:	e9 cd 05 00 00       	jmp    1044115 <my.json::read_value+0x1a35>
 1043b48:	48 8d 05 b1 47 fc ff 	lea    -0x3b84f(%rip),%rax        # 1008300 <core_number_pairs+0x1930>
 1043b4f:	4c 89 e7             	mov    %r12,%rdi
 1043b52:	48 89 d6             	mov    %rdx,%rsi
 1043b55:	4d 89 d6             	mov    %r10,%r14
 1043b58:	48 89 c2             	mov    %rax,%rdx
 1043b5b:	e8 60 0b 00 00       	call   10446c0 <my.json::fail>
 1043b60:	48 8d 3d 59 e7 00 00 	lea    0xe759(%rip),%rdi        # 10522c0 <core_io_file_error.verbs+0x620>
 1043b67:	e9 13 fe ff ff       	jmp    104397f <my.json::read_value+0x129f>
 1043b6c:	48 8d 15 2d 50 fc ff 	lea    -0x3afd3(%rip),%rdx        # 1008ba0 <core_number_pairs+0x21d0>
 1043b73:	4c 89 e7             	mov    %r12,%rdi
 1043b76:	4c 89 f6             	mov    %r14,%rsi
 1043b79:	4d 89 d7             	mov    %r10,%r15
 1043b7c:	e8 3f 0b 00 00       	call   10446c0 <my.json::fail>
 1043b81:	4d 89 fa             	mov    %r15,%r10
 1043b84:	b2 01                	mov    $0x1,%dl
 1043b86:	48 8d 3d 23 ee 00 00 	lea    0xee23(%rip),%rdi        # 10529b0 <core_io_file_error.verbs+0xd10>
 1043b8d:	e8 2e d4 ff ff       	call   1040fc0 <myl_core_err_trace_origin_preserve_most>
 1043b92:	80 fa 01             	cmp    $0x1,%dl
 1043b95:	0f 85 3e f2 ff ff    	jne    1042dd9 <my.json::read_value+0x6f9>
 1043b9b:	48 8d 3d de ea 00 00 	lea    0xeade(%rip),%rdi        # 1052680 <core_io_file_error.verbs+0x9e0>
 1043ba2:	e8 59 d4 ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 1043ba7:	48 89 c3             	mov    %rax,%rbx
 1043baa:	8b 00                	mov    (%rax),%eax
 1043bac:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043bb1:	0f 87 19 01 00 00    	ja     1043cd0 <my.json::read_value+0x15f0>
 1043bb7:	ff c0                	inc    %eax
 1043bb9:	89 03                	mov    %eax,(%rbx)
 1043bbb:	e9 21 01 00 00       	jmp    1043ce1 <my.json::read_value+0x1601>
 1043bc0:	48 8d 3d 09 e6 00 00 	lea    0xe609(%rip),%rdi        # 10521d0 <core_io_file_error.verbs+0x530>
 1043bc7:	c5 f9 7f 44 24 20    	vmovdqa %xmm0,0x20(%rsp)
 1043bcd:	e8 2e d4 ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 1043bd2:	c5 f9 6f 44 24 20    	vmovdqa 0x20(%rsp),%xmm0
 1043bd8:	e9 3d f3 ff ff       	jmp    1042f1a <my.json::read_value+0x83a>
 1043bdd:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043be0:	0f 84 10 04 00 00    	je     1043ff6 <my.json::read_value+0x1916>
 1043be6:	48 89 df             	mov    %rbx,%rdi
 1043be9:	e8 52 cf ff ff       	call   1040b40 <myl_core_retain_slow>
 1043bee:	8b 03                	mov    (%rbx),%eax
 1043bf0:	85 c0                	test   %eax,%eax
 1043bf2:	0f 88 fe 00 00 00    	js     1043cf6 <my.json::read_value+0x1616>
 1043bf8:	ff c8                	dec    %eax
 1043bfa:	0f 85 ef 00 00 00    	jne    1043cef <my.json::read_value+0x160f>
 1043c00:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043c04:	48 85 c0             	test   %rax,%rax
 1043c07:	0f 84 ed 08 00 00    	je     10444fa <my.json::read_value+0x1e1a>
 1043c0d:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043c12:	0f 85 e2 08 00 00    	jne    10444fa <my.json::read_value+0x1e1a>
 1043c18:	48 8d 0d 31 3c 03 00 	lea    0x33c31(%rip),%rcx        # 1077850 <myl_core_free_lists>
 1043c1f:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1043c23:	48 89 13             	mov    %rdx,(%rbx)
 1043c26:	48 89 1c c1          	mov    %rbx,(%rcx,%rax,8)
 1043c2a:	e9 c7 03 00 00       	jmp    1043ff6 <my.json::read_value+0x1916>
 1043c2f:	48 8d 15 2a 4f fc ff 	lea    -0x3b0d6(%rip),%rdx        # 1008b60 <core_number_pairs+0x2190>
 1043c36:	4c 89 e7             	mov    %r12,%rdi
 1043c39:	4c 89 fe             	mov    %r15,%rsi
 1043c3c:	4c 89 d3             	mov    %r10,%rbx
 1043c3f:	e8 7c 0a 00 00       	call   10446c0 <my.json::fail>
 1043c44:	49 89 da             	mov    %rbx,%r10
 1043c47:	48 89 c3             	mov    %rax,%rbx
 1043c4a:	b0 01                	mov    $0x1,%al
 1043c4c:	48 8d 3d 2d ed 00 00 	lea    0xed2d(%rip),%rdi        # 1052980 <core_io_file_error.verbs+0xce0>
 1043c53:	e8 68 d3 ff ff       	call   1040fc0 <myl_core_err_trace_origin_preserve_most>
 1043c58:	3c 01                	cmp    $0x1,%al
 1043c5a:	0f 85 7e f0 ff ff    	jne    1042cde <my.json::read_value+0x5fe>
 1043c60:	48 8d 3d e9 e9 00 00 	lea    0xe9e9(%rip),%rdi        # 1052650 <core_io_file_error.verbs+0x9b0>
 1043c67:	e8 94 d3 ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 1043c6c:	8b 03                	mov    (%rbx),%eax
 1043c6e:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043c73:	77 06                	ja     1043c7b <my.json::read_value+0x159b>
 1043c75:	ff c0                	inc    %eax
 1043c77:	89 03                	mov    %eax,(%rbx)
 1043c79:	eb 11                	jmp    1043c8c <my.json::read_value+0x15ac>
 1043c7b:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043c7e:	0f 84 1f 01 00 00    	je     1043da3 <my.json::read_value+0x16c3>
 1043c84:	48 89 df             	mov    %rbx,%rdi
 1043c87:	e8 b4 ce ff ff       	call   1040b40 <myl_core_retain_slow>
 1043c8c:	8b 03                	mov    (%rbx),%eax
 1043c8e:	85 c0                	test   %eax,%eax
 1043c90:	0f 88 00 01 00 00    	js     1043d96 <my.json::read_value+0x16b6>
 1043c96:	ff c8                	dec    %eax
 1043c98:	0f 85 53 03 00 00    	jne    1043ff1 <my.json::read_value+0x1911>
 1043c9e:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043ca2:	48 85 c0             	test   %rax,%rax
 1043ca5:	0f 84 b5 08 00 00    	je     1044560 <my.json::read_value+0x1e80>
 1043cab:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043cb0:	0f 85 aa 08 00 00    	jne    1044560 <my.json::read_value+0x1e80>
 1043cb6:	48 8d 0d 93 3b 03 00 	lea    0x33b93(%rip),%rcx        # 1077850 <myl_core_free_lists>
 1043cbd:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1043cc1:	48 89 13             	mov    %rdx,(%rbx)
 1043cc4:	48 89 1c c1          	mov    %rbx,(%rcx,%rax,8)
 1043cc8:	4d 89 fe             	mov    %r15,%r14
 1043ccb:	e9 26 03 00 00       	jmp    1043ff6 <my.json::read_value+0x1916>
 1043cd0:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043cd3:	0f 84 1d 03 00 00    	je     1043ff6 <my.json::read_value+0x1916>
 1043cd9:	48 89 df             	mov    %rbx,%rdi
 1043cdc:	e8 5f ce ff ff       	call   1040b40 <myl_core_retain_slow>
 1043ce1:	8b 03                	mov    (%rbx),%eax
 1043ce3:	85 c0                	test   %eax,%eax
 1043ce5:	78 0f                	js     1043cf6 <my.json::read_value+0x1616>
 1043ce7:	ff c8                	dec    %eax
 1043ce9:	0f 84 11 ff ff ff    	je     1043c00 <my.json::read_value+0x1520>
 1043cef:	89 03                	mov    %eax,(%rbx)
 1043cf1:	e9 00 03 00 00       	jmp    1043ff6 <my.json::read_value+0x1916>
 1043cf6:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043cf9:	0f 84 f7 02 00 00    	je     1043ff6 <my.json::read_value+0x1916>
 1043cff:	48 89 df             	mov    %rbx,%rdi
 1043d02:	e8 79 ce ff ff       	call   1040b80 <myl_core_release_slow>
 1043d07:	e9 ea 02 00 00       	jmp    1043ff6 <my.json::read_value+0x1916>
 1043d0c:	48 8d 3d 8d e4 00 00 	lea    0xe48d(%rip),%rdi        # 10521a0 <core_io_file_error.verbs+0x500>
 1043d13:	e8 e8 d2 ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 1043d18:	8b 03                	mov    (%rbx),%eax
 1043d1a:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043d1f:	0f 87 dd 01 00 00    	ja     1043f02 <my.json::read_value+0x1822>
 1043d25:	ff c0                	inc    %eax
 1043d27:	89 03                	mov    %eax,(%rbx)
 1043d29:	8b 03                	mov    (%rbx),%eax
 1043d2b:	85 c0                	test   %eax,%eax
 1043d2d:	0f 88 e3 04 00 00    	js     1044216 <my.json::read_value+0x1b36>
 1043d33:	ff c8                	dec    %eax
 1043d35:	0f 84 ef 05 00 00    	je     104432a <my.json::read_value+0x1c4a>
 1043d3b:	89 03                	mov    %eax,(%rbx)
 1043d3d:	e9 12 06 00 00       	jmp    1044354 <my.json::read_value+0x1c74>
 1043d42:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043d46:	48 85 c0             	test   %rax,%rax
 1043d49:	0f 84 8e 07 00 00    	je     10444dd <my.json::read_value+0x1dfd>
 1043d4f:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043d54:	0f 85 83 07 00 00    	jne    10444dd <my.json::read_value+0x1dfd>
 1043d5a:	48 8d 35 ef 3a 03 00 	lea    0x33aef(%rip),%rsi        # 1077850 <myl_core_free_lists>
 1043d61:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1043d65:	48 89 0b             	mov    %rcx,(%rbx)
 1043d68:	48 89 1c c6          	mov    %rbx,(%rsi,%rax,8)
 1043d6c:	48 8d 05 cd 48 fc ff 	lea    -0x3b733(%rip),%rax        # 1008640 <core_number_pairs+0x1c70>
 1043d73:	4c 89 e7             	mov    %r12,%rdi
 1043d76:	48 89 d6             	mov    %rdx,%rsi
 1043d79:	48 89 d3             	mov    %rdx,%rbx
 1043d7c:	48 89 c2             	mov    %rax,%rdx
 1043d7f:	e8 3c 09 00 00       	call   10446c0 <my.json::fail>
 1043d84:	48 89 da             	mov    %rbx,%rdx
 1043d87:	49 89 c7             	mov    %rax,%r15
 1043d8a:	48 8d 3d 7f e6 00 00 	lea    0xe67f(%rip),%rdi        # 1052410 <core_io_file_error.verbs+0x770>
 1043d91:	e9 d9 01 00 00       	jmp    1043f6f <my.json::read_value+0x188f>
 1043d96:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043d99:	74 08                	je     1043da3 <my.json::read_value+0x16c3>
 1043d9b:	48 89 df             	mov    %rbx,%rdi
 1043d9e:	e8 dd cd ff ff       	call   1040b80 <myl_core_release_slow>
 1043da3:	4d 89 fe             	mov    %r15,%r14
 1043da6:	e9 4b 02 00 00       	jmp    1043ff6 <my.json::read_value+0x1916>
 1043dab:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043dae:	0f 84 71 02 00 00    	je     1044025 <my.json::read_value+0x1945>
 1043db4:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043db9:	e8 c2 cd ff ff       	call   1040b80 <myl_core_release_slow>
 1043dbe:	e9 62 02 00 00       	jmp    1044025 <my.json::read_value+0x1945>
 1043dc3:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043dc6:	0f 84 49 03 00 00    	je     1044115 <my.json::read_value+0x1a35>
 1043dcc:	48 89 ef             	mov    %rbp,%rdi
 1043dcf:	e8 ac cd ff ff       	call   1040b80 <myl_core_release_slow>
 1043dd4:	e9 3c 03 00 00       	jmp    1044115 <my.json::read_value+0x1a35>
 1043dd9:	48 8d 15 40 4b fc ff 	lea    -0x3b4c0(%rip),%rdx        # 1008920 <core_number_pairs+0x1f50>
 1043de0:	4c 89 f7             	mov    %r14,%rdi
 1043de3:	4c 89 fe             	mov    %r15,%rsi
 1043de6:	e8 d5 08 00 00       	call   10446c0 <my.json::fail>
 1043deb:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 1043df0:	48 8d 3d 49 e9 00 00 	lea    0xe949(%rip),%rdi        # 1052740 <core_io_file_error.verbs+0xaa0>
 1043df7:	e9 47 02 00 00       	jmp    1044043 <my.json::read_value+0x1963>
 1043dfc:	80 7c 24 07 00       	cmpb   $0x0,0x7(%rsp)
 1043e01:	0f 85 86 05 00 00    	jne    104438d <my.json::read_value+0x1cad>
 1043e07:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043e0c:	8b 07                	mov    (%rdi),%eax
 1043e0e:	85 c0                	test   %eax,%eax
 1043e10:	0f 88 90 04 00 00    	js     10442a6 <my.json::read_value+0x1bc6>
 1043e16:	ff c8                	dec    %eax
 1043e18:	0f 85 6d 05 00 00    	jne    104438b <my.json::read_value+0x1cab>
 1043e1e:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1043e22:	48 85 c0             	test   %rax,%rax
 1043e25:	0f 84 f2 07 00 00    	je     104461d <my.json::read_value+0x1f3d>
 1043e2b:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 1043e30:	0f 85 e7 07 00 00    	jne    104461d <my.json::read_value+0x1f3d>
 1043e36:	48 8d 15 13 3a 03 00 	lea    0x33a13(%rip),%rdx        # 1077850 <myl_core_free_lists>
 1043e3d:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043e41:	48 89 0f             	mov    %rcx,(%rdi)
 1043e44:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 1043e48:	e9 40 05 00 00       	jmp    104438d <my.json::read_value+0x1cad>
 1043e4d:	4d 89 d7             	mov    %r10,%r15
 1043e50:	48 8d 15 c9 4c fc ff 	lea    -0x3b337(%rip),%rdx        # 1008b20 <core_number_pairs+0x2150>
 1043e57:	4c 89 e7             	mov    %r12,%rdi
 1043e5a:	49 89 f6             	mov    %rsi,%r14
 1043e5d:	e8 5e 08 00 00       	call   10446c0 <my.json::fail>
 1043e62:	48 89 c3             	mov    %rax,%rbx
 1043e65:	48 8d 3d e4 ea 00 00 	lea    0xeae4(%rip),%rdi        # 1052950 <core_io_file_error.verbs+0xcb0>
 1043e6c:	e9 e9 fb ff ff       	jmp    1043a5a <my.json::read_value+0x137a>
 1043e71:	8b 45 00             	mov    0x0(%rbp),%eax
 1043e74:	85 c0                	test   %eax,%eax
 1043e76:	0f 88 35 03 00 00    	js     10441b1 <my.json::read_value+0x1ad1>
 1043e7c:	ff c8                	dec    %eax
 1043e7e:	0f 85 3a 04 00 00    	jne    10442be <my.json::read_value+0x1bde>
 1043e84:	0f b6 45 07          	movzbl 0x7(%rbp),%eax
 1043e88:	48 85 c0             	test   %rax,%rax
 1043e8b:	0f 84 50 07 00 00    	je     10445e1 <my.json::read_value+0x1f01>
 1043e91:	48 83 7d 18 00       	cmpq   $0x0,0x18(%rbp)
 1043e96:	0f 85 45 07 00 00    	jne    10445e1 <my.json::read_value+0x1f01>
 1043e9c:	48 8d 15 ad 39 03 00 	lea    0x339ad(%rip),%rdx        # 1077850 <myl_core_free_lists>
 1043ea3:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043ea7:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 1043eab:	48 89 2c c2          	mov    %rbp,(%rdx,%rax,8)
 1043eaf:	e9 0d 04 00 00       	jmp    10442c1 <my.json::read_value+0x1be1>
 1043eb4:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043eb8:	48 85 c0             	test   %rax,%rax
 1043ebb:	0f 84 73 06 00 00    	je     1044534 <my.json::read_value+0x1e54>
 1043ec1:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043ec6:	0f 85 68 06 00 00    	jne    1044534 <my.json::read_value+0x1e54>
 1043ecc:	4c 8d 35 7d 39 03 00 	lea    0x3397d(%rip),%r14        # 1077850 <myl_core_free_lists>
 1043ed3:	49 8b 0c c6          	mov    (%r14,%rax,8),%rcx
 1043ed7:	48 89 0b             	mov    %rcx,(%rbx)
 1043eda:	49 89 1c c6          	mov    %rbx,(%r14,%rax,8)
 1043ede:	48 8d 3d fb e4 00 00 	lea    0xe4fb(%rip),%rdi        # 10523e0 <core_io_file_error.verbs+0x740>
 1043ee5:	e8 16 d1 ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 1043eea:	41 8b 07             	mov    (%r15),%eax
 1043eed:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043ef2:	0f 87 cf 02 00 00    	ja     10441c7 <my.json::read_value+0x1ae7>
 1043ef8:	ff c0                	inc    %eax
 1043efa:	41 89 07             	mov    %eax,(%r15)
 1043efd:	e9 dc 02 00 00       	jmp    10441de <my.json::read_value+0x1afe>
 1043f02:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043f05:	0f 84 49 04 00 00    	je     1044354 <my.json::read_value+0x1c74>
 1043f0b:	48 89 df             	mov    %rbx,%rdi
 1043f0e:	e8 2d cc ff ff       	call   1040b40 <myl_core_retain_slow>
 1043f13:	e9 11 fe ff ff       	jmp    1043d29 <my.json::read_value+0x1649>
 1043f18:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043f1c:	48 85 c0             	test   %rax,%rax
 1043f1f:	48 8d 35 2a 39 03 00 	lea    0x3392a(%rip),%rsi        # 1077850 <myl_core_free_lists>
 1043f26:	74 14                	je     1043f3c <my.json::read_value+0x185c>
 1043f28:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043f2d:	75 0d                	jne    1043f3c <my.json::read_value+0x185c>
 1043f2f:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1043f33:	48 89 0b             	mov    %rcx,(%rbx)
 1043f36:	48 89 1c c6          	mov    %rbx,(%rsi,%rax,8)
 1043f3a:	eb 0e                	jmp    1043f4a <my.json::read_value+0x186a>
 1043f3c:	49 89 d6             	mov    %rdx,%r14
 1043f3f:	48 89 df             	mov    %rbx,%rdi
 1043f42:	e8 b9 cc ff ff       	call   1040c00 <myl_core_free_block>
 1043f47:	4c 89 f2             	mov    %r14,%rdx
 1043f4a:	48 8d 05 af 46 fc ff 	lea    -0x3b951(%rip),%rax        # 1008600 <core_number_pairs+0x1c30>
 1043f51:	4c 89 e7             	mov    %r12,%rdi
 1043f54:	48 89 d6             	mov    %rdx,%rsi
 1043f57:	48 89 d3             	mov    %rdx,%rbx
 1043f5a:	48 89 c2             	mov    %rax,%rdx
 1043f5d:	e8 5e 07 00 00       	call   10446c0 <my.json::fail>
 1043f62:	48 89 da             	mov    %rbx,%rdx
 1043f65:	49 89 c7             	mov    %rax,%r15
 1043f68:	48 8d 3d 41 e4 00 00 	lea    0xe441(%rip),%rdi        # 10523b0 <core_io_file_error.verbs+0x710>
 1043f6f:	e8 4c d0 ff ff       	call   1040fc0 <myl_core_err_trace_origin_preserve_most>
 1043f74:	48 8d 3d f5 e1 00 00 	lea    0xe1f5(%rip),%rdi        # 1052170 <core_io_file_error.verbs+0x4d0>
 1043f7b:	e8 80 d0 ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 1043f80:	b8 01 00 00 00       	mov    $0x1,%eax
 1043f85:	e9 59 fa ff ff       	jmp    10439e3 <my.json::read_value+0x1303>
 1043f8a:	48 89 df             	mov    %rbx,%rdi
 1043f8d:	e8 ae cb ff ff       	call   1040b40 <myl_core_retain_slow>
 1043f92:	40 84 ed             	test   %bpl,%bpl
 1043f95:	0f 85 79 fa ff ff    	jne    1043a14 <my.json::read_value+0x1334>
 1043f9b:	8b 03                	mov    (%rbx),%eax
 1043f9d:	85 c0                	test   %eax,%eax
 1043f9f:	78 0b                	js     1043fac <my.json::read_value+0x18cc>
 1043fa1:	ff c8                	dec    %eax
 1043fa3:	74 1d                	je     1043fc2 <my.json::read_value+0x18e2>
 1043fa5:	89 03                	mov    %eax,(%rbx)
 1043fa7:	e9 68 fa ff ff       	jmp    1043a14 <my.json::read_value+0x1334>
 1043fac:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043faf:	0f 84 5f fa ff ff    	je     1043a14 <my.json::read_value+0x1334>
 1043fb5:	48 89 df             	mov    %rbx,%rdi
 1043fb8:	e8 c3 cb ff ff       	call   1040b80 <myl_core_release_slow>
 1043fbd:	e9 52 fa ff ff       	jmp    1043a14 <my.json::read_value+0x1334>
 1043fc2:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043fc6:	48 85 c0             	test   %rax,%rax
 1043fc9:	0f 84 f4 04 00 00    	je     10444c3 <my.json::read_value+0x1de3>
 1043fcf:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043fd4:	0f 85 e9 04 00 00    	jne    10444c3 <my.json::read_value+0x1de3>
 1043fda:	48 8d 0d 6f 38 03 00 	lea    0x3386f(%rip),%rcx        # 1077850 <myl_core_free_lists>
 1043fe1:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1043fe5:	48 89 13             	mov    %rdx,(%rbx)
 1043fe8:	48 89 1c c1          	mov    %rbx,(%rcx,%rax,8)
 1043fec:	e9 23 fa ff ff       	jmp    1043a14 <my.json::read_value+0x1334>
 1043ff1:	89 03                	mov    %eax,(%rbx)
 1043ff3:	4d 89 fe             	mov    %r15,%r14
 1043ff6:	48 8d 3d 63 e2 00 00 	lea    0xe263(%rip),%rdi        # 1052260 <core_io_file_error.verbs+0x5c0>
 1043ffd:	e8 fe cf ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 1044002:	b8 01 00 00 00       	mov    $0x1,%eax
 1044007:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 104400c:	48 89 01             	mov    %rax,(%rcx)
 104400f:	48 89 c8             	mov    %rcx,%rax
 1044012:	48 89 59 08          	mov    %rbx,0x8(%rcx)
 1044016:	48 89 51 10          	mov    %rdx,0x10(%rcx)
 104401a:	4c 89 61 18          	mov    %r12,0x18(%rcx)
 104401e:	e9 f1 02 00 00       	jmp    1044314 <my.json::read_value+0x1c34>
 1044023:	89 07                	mov    %eax,(%rdi)
 1044025:	48 8d 15 54 49 fc ff 	lea    -0x3b6ac(%rip),%rdx        # 1008980 <core_number_pairs+0x1fb0>
 104402c:	4c 89 f7             	mov    %r14,%rdi
 104402f:	4c 89 fe             	mov    %r15,%rsi
 1044032:	e8 89 06 00 00       	call   10446c0 <my.json::fail>
 1044037:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 104403c:	48 8d 3d 5d e7 00 00 	lea    0xe75d(%rip),%rdi        # 10527a0 <core_io_file_error.verbs+0xb00>
 1044043:	e8 78 cf ff ff       	call   1040fc0 <myl_core_err_trace_origin_preserve_most>
 1044048:	8b 45 00             	mov    0x0(%rbp),%eax
 104404b:	85 c0                	test   %eax,%eax
 104404d:	78 31                	js     1044080 <my.json::read_value+0x19a0>
 104404f:	ff c8                	dec    %eax
 1044051:	75 3c                	jne    104408f <my.json::read_value+0x19af>
 1044053:	0f b6 45 07          	movzbl 0x7(%rbp),%eax
 1044057:	48 85 c0             	test   %rax,%rax
 104405a:	0f 84 70 04 00 00    	je     10444d0 <my.json::read_value+0x1df0>
 1044060:	48 83 7d 18 00       	cmpq   $0x0,0x18(%rbp)
 1044065:	0f 85 65 04 00 00    	jne    10444d0 <my.json::read_value+0x1df0>
 104406b:	48 8d 15 de 37 03 00 	lea    0x337de(%rip),%rdx        # 1077850 <myl_core_free_lists>
 1044072:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1044076:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 104407a:	48 89 2c c2          	mov    %rbp,(%rdx,%rax,8)
 104407e:	eb 12                	jmp    1044092 <my.json::read_value+0x19b2>
 1044080:	83 f8 ff             	cmp    $0xffffffff,%eax
 1044083:	74 0d                	je     1044092 <my.json::read_value+0x19b2>
 1044085:	48 89 ef             	mov    %rbp,%rdi
 1044088:	e8 f3 ca ff ff       	call   1040b80 <myl_core_release_slow>
 104408d:	eb 03                	jmp    1044092 <my.json::read_value+0x19b2>
 104408f:	89 45 00             	mov    %eax,0x0(%rbp)
 1044092:	48 8d 3d b7 e2 00 00 	lea    0xe2b7(%rip),%rdi        # 1052350 <core_io_file_error.verbs+0x6b0>
 1044099:	e8 62 cf ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 104409e:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10440a3:	8b 07                	mov    (%rdi),%eax
 10440a5:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 10440aa:	77 06                	ja     10440b2 <my.json::read_value+0x19d2>
 10440ac:	ff c0                	inc    %eax
 10440ae:	89 07                	mov    %eax,(%rdi)
 10440b0:	eb 14                	jmp    10440c6 <my.json::read_value+0x19e6>
 10440b2:	83 f8 ff             	cmp    $0xffffffff,%eax
 10440b5:	74 53                	je     104410a <my.json::read_value+0x1a2a>
 10440b7:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10440bc:	e8 7f ca ff ff       	call   1040b40 <myl_core_retain_slow>
 10440c1:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10440c6:	8b 07                	mov    (%rdi),%eax
 10440c8:	85 c0                	test   %eax,%eax
 10440ca:	78 30                	js     10440fc <my.json::read_value+0x1a1c>
 10440cc:	ff c8                	dec    %eax
 10440ce:	75 38                	jne    1044108 <my.json::read_value+0x1a28>
 10440d0:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 10440d4:	48 85 c0             	test   %rax,%rax
 10440d7:	0f 84 13 04 00 00    	je     10444f0 <my.json::read_value+0x1e10>
 10440dd:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 10440e2:	0f 85 08 04 00 00    	jne    10444f0 <my.json::read_value+0x1e10>
 10440e8:	48 8d 15 61 37 03 00 	lea    0x33761(%rip),%rdx        # 1077850 <myl_core_free_lists>
 10440ef:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 10440f3:	48 89 0f             	mov    %rcx,(%rdi)
 10440f6:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 10440fa:	eb 0e                	jmp    104410a <my.json::read_value+0x1a2a>
 10440fc:	83 f8 ff             	cmp    $0xffffffff,%eax
 10440ff:	74 09                	je     104410a <my.json::read_value+0x1a2a>
 1044101:	e8 7a ca ff ff       	call   1040b80 <myl_core_release_slow>
 1044106:	eb 02                	jmp    104410a <my.json::read_value+0x1a2a>
 1044108:	89 07                	mov    %eax,(%rdi)
 104410a:	4d 89 f4             	mov    %r14,%r12
 104410d:	e9 d2 01 00 00       	jmp    10442e4 <my.json::read_value+0x1c04>
 1044112:	89 45 00             	mov    %eax,0x0(%rbp)
 1044115:	48 8d 15 44 44 fc ff 	lea    -0x3bbbc(%rip),%rdx        # 1008560 <core_number_pairs+0x1b90>
 104411c:	4c 89 e7             	mov    %r12,%rdi
 104411f:	4c 89 fe             	mov    %r15,%rsi
 1044122:	e8 99 05 00 00       	call   10446c0 <my.json::fail>
 1044127:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 104412c:	48 8d 3d ed e1 00 00 	lea    0xe1ed(%rip),%rdi        # 1052320 <core_io_file_error.verbs+0x680>
 1044133:	e9 a7 01 00 00       	jmp    10442df <my.json::read_value+0x1bff>
 1044138:	48 89 f8             	mov    %rdi,%rax
 104413b:	48 8d 3d 2e e6 00 00 	lea    0xe62e(%rip),%rdi        # 1052770 <core_io_file_error.verbs+0xad0>
 1044142:	e8 b9 ce ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 1044147:	48 89 c7             	mov    %rax,%rdi
 104414a:	8b 00                	mov    (%rax),%eax
 104414c:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1044151:	0f 87 f1 00 00 00    	ja     1044248 <my.json::read_value+0x1b68>
 1044157:	ff c0                	inc    %eax
 1044159:	89 07                	mov    %eax,(%rdi)
 104415b:	e9 fb 00 00 00       	jmp    104425b <my.json::read_value+0x1b7b>
 1044160:	80 7c 24 07 00       	cmpb   $0x0,0x7(%rsp)
 1044165:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 104416a:	0f 85 5a 02 00 00    	jne    10443ca <my.json::read_value+0x1cea>
 1044170:	8b 07                	mov    (%rdi),%eax
 1044172:	85 c0                	test   %eax,%eax
 1044174:	0f 88 36 02 00 00    	js     10443b0 <my.json::read_value+0x1cd0>
 104417a:	ff c8                	dec    %eax
 104417c:	0f 85 46 02 00 00    	jne    10443c8 <my.json::read_value+0x1ce8>
 1044182:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1044186:	48 85 c0             	test   %rax,%rax
 1044189:	0f 84 eb 04 00 00    	je     104467a <my.json::read_value+0x1f9a>
 104418f:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 1044194:	0f 85 e0 04 00 00    	jne    104467a <my.json::read_value+0x1f9a>
 104419a:	48 8d 15 af 36 03 00 	lea    0x336af(%rip),%rdx        # 1077850 <myl_core_free_lists>
 10441a1:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 10441a5:	48 89 0f             	mov    %rcx,(%rdi)
 10441a8:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 10441ac:	e9 19 02 00 00       	jmp    10443ca <my.json::read_value+0x1cea>
 10441b1:	83 f8 ff             	cmp    $0xffffffff,%eax
 10441b4:	0f 84 07 01 00 00    	je     10442c1 <my.json::read_value+0x1be1>
 10441ba:	48 89 ef             	mov    %rbp,%rdi
 10441bd:	e8 be c9 ff ff       	call   1040b80 <myl_core_release_slow>
 10441c2:	e9 fa 00 00 00       	jmp    10442c1 <my.json::read_value+0x1be1>
 10441c7:	83 f8 ff             	cmp    $0xffffffff,%eax
 10441ca:	0f 84 a4 fd ff ff    	je     1043f74 <my.json::read_value+0x1894>
 10441d0:	4c 89 ff             	mov    %r15,%rdi
 10441d3:	48 89 d3             	mov    %rdx,%rbx
 10441d6:	e8 65 c9 ff ff       	call   1040b40 <myl_core_retain_slow>
 10441db:	48 89 da             	mov    %rbx,%rdx
 10441de:	41 8b 07             	mov    (%r15),%eax
 10441e1:	85 c0                	test   %eax,%eax
 10441e3:	78 47                	js     104422c <my.json::read_value+0x1b4c>
 10441e5:	ff c8                	dec    %eax
 10441e7:	0f 85 96 01 00 00    	jne    1044383 <my.json::read_value+0x1ca3>
 10441ed:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 10441f2:	48 85 c0             	test   %rax,%rax
 10441f5:	0f 84 00 04 00 00    	je     10445fb <my.json::read_value+0x1f1b>
 10441fb:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 1044200:	0f 85 f5 03 00 00    	jne    10445fb <my.json::read_value+0x1f1b>
 1044206:	49 8b 0c c6          	mov    (%r14,%rax,8),%rcx
 104420a:	49 89 0f             	mov    %rcx,(%r15)
 104420d:	4d 89 3c c6          	mov    %r15,(%r14,%rax,8)
 1044211:	e9 5e fd ff ff       	jmp    1043f74 <my.json::read_value+0x1894>
 1044216:	83 f8 ff             	cmp    $0xffffffff,%eax
 1044219:	0f 84 35 01 00 00    	je     1044354 <my.json::read_value+0x1c74>
 104421f:	48 89 df             	mov    %rbx,%rdi
 1044222:	e8 59 c9 ff ff       	call   1040b80 <myl_core_release_slow>
 1044227:	e9 28 01 00 00       	jmp    1044354 <my.json::read_value+0x1c74>
 104422c:	83 f8 ff             	cmp    $0xffffffff,%eax
 104422f:	0f 84 3f fd ff ff    	je     1043f74 <my.json::read_value+0x1894>
 1044235:	4c 89 ff             	mov    %r15,%rdi
 1044238:	48 89 d3             	mov    %rdx,%rbx
 104423b:	e8 40 c9 ff ff       	call   1040b80 <myl_core_release_slow>
 1044240:	48 89 da             	mov    %rbx,%rdx
 1044243:	e9 2c fd ff ff       	jmp    1043f74 <my.json::read_value+0x1894>
 1044248:	83 f8 ff             	cmp    $0xffffffff,%eax
 104424b:	0f 84 28 01 00 00    	je     1044379 <my.json::read_value+0x1c99>
 1044251:	e8 ea c8 ff ff       	call   1040b40 <myl_core_retain_slow>
 1044256:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 104425b:	8b 07                	mov    (%rdi),%eax
 104425d:	85 c0                	test   %eax,%eax
 104425f:	0f 88 05 01 00 00    	js     104436a <my.json::read_value+0x1c8a>
 1044265:	ff c8                	dec    %eax
 1044267:	0f 85 4f 01 00 00    	jne    10443bc <my.json::read_value+0x1cdc>
 104426d:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1044271:	48 85 c0             	test   %rax,%rax
 1044274:	0f 84 ad 03 00 00    	je     1044627 <my.json::read_value+0x1f47>
 104427a:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 104427f:	0f 85 a2 03 00 00    	jne    1044627 <my.json::read_value+0x1f47>
 1044285:	48 8d 15 c4 35 03 00 	lea    0x335c4(%rip),%rdx        # 1077850 <myl_core_free_lists>
 104428c:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1044290:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1044295:	48 89 0e             	mov    %rcx,(%rsi)
 1044298:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 104429d:	48 89 0c c2          	mov    %rcx,(%rdx,%rax,8)
 10442a1:	e9 ce 00 00 00       	jmp    1044374 <my.json::read_value+0x1c94>
 10442a6:	83 f8 ff             	cmp    $0xffffffff,%eax
 10442a9:	0f 84 de 00 00 00    	je     104438d <my.json::read_value+0x1cad>
 10442af:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 10442b4:	e8 c7 c8 ff ff       	call   1040b80 <myl_core_release_slow>
 10442b9:	e9 cf 00 00 00       	jmp    104438d <my.json::read_value+0x1cad>
 10442be:	89 45 00             	mov    %eax,0x0(%rbp)
 10442c1:	48 8d 15 d8 42 fc ff 	lea    -0x3bd28(%rip),%rdx        # 10085a0 <core_number_pairs+0x1bd0>
 10442c8:	4c 89 e7             	mov    %r12,%rdi
 10442cb:	4c 89 fe             	mov    %r15,%rsi
 10442ce:	e8 ed 03 00 00       	call   10446c0 <my.json::fail>
 10442d3:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 10442d8:	48 8d 3d a1 e0 00 00 	lea    0xe0a1(%rip),%rdi        # 1052380 <core_io_file_error.verbs+0x6e0>
 10442df:	e8 dc cc ff ff       	call   1040fc0 <myl_core_err_trace_origin_preserve_most>
 10442e4:	48 8d 3d 55 de 00 00 	lea    0xde55(%rip),%rdi        # 1052140 <core_io_file_error.verbs+0x4a0>
 10442eb:	e8 10 cd ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 10442f0:	b8 01 00 00 00       	mov    $0x1,%eax
 10442f5:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 10442fa:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 10442ff:	48 89 01             	mov    %rax,(%rcx)
 1044302:	48 89 c8             	mov    %rcx,%rax
 1044305:	48 89 51 08          	mov    %rdx,0x8(%rcx)
 1044309:	48 89 69 10          	mov    %rbp,0x10(%rcx)
 104430d:	4c 89 61 18          	mov    %r12,0x18(%rcx)
 1044311:	4d 89 fe             	mov    %r15,%r14
 1044314:	4c 89 70 20          	mov    %r14,0x20(%rax)
 1044318:	48 81 c4 88 01 00 00 	add    $0x188,%rsp
 104431f:	5b                   	pop    %rbx
 1044320:	41 5c                	pop    %r12
 1044322:	41 5d                	pop    %r13
 1044324:	41 5e                	pop    %r14
 1044326:	41 5f                	pop    %r15
 1044328:	5d                   	pop    %rbp
 1044329:	c3                   	ret
 104432a:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 104432e:	48 85 c0             	test   %rax,%rax
 1044331:	0f 84 b7 02 00 00    	je     10445ee <my.json::read_value+0x1f0e>
 1044337:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 104433c:	0f 85 ac 02 00 00    	jne    10445ee <my.json::read_value+0x1f0e>
 1044342:	48 8d 0d 07 35 03 00 	lea    0x33507(%rip),%rcx        # 1077850 <myl_core_free_lists>
 1044349:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 104434d:	48 89 13             	mov    %rdx,(%rbx)
 1044350:	48 89 1c c1          	mov    %rbx,(%rcx,%rax,8)
 1044354:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 1044359:	48 c7 00 01 00 00 00 	movq   $0x1,(%rax)
 1044360:	48 89 58 08          	mov    %rbx,0x8(%rax)
 1044364:	4c 89 78 18          	mov    %r15,0x18(%rax)
 1044368:	eb aa                	jmp    1044314 <my.json::read_value+0x1c34>
 104436a:	83 f8 ff             	cmp    $0xffffffff,%eax
 104436d:	74 0a                	je     1044379 <my.json::read_value+0x1c99>
 104436f:	e8 0c c8 ff ff       	call   1040b80 <myl_core_release_slow>
 1044374:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1044379:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
 104437e:	e9 c5 fc ff ff       	jmp    1044048 <my.json::read_value+0x1968>
 1044383:	41 89 07             	mov    %eax,(%r15)
 1044386:	e9 e9 fb ff ff       	jmp    1043f74 <my.json::read_value+0x1894>
 104438b:	89 07                	mov    %eax,(%rdi)
 104438d:	48 8d 15 2c 46 fc ff 	lea    -0x3b9d4(%rip),%rdx        # 10089c0 <core_number_pairs+0x1ff0>
 1044394:	4c 89 f7             	mov    %r14,%rdi
 1044397:	4c 89 fe             	mov    %r15,%rsi
 104439a:	e8 21 03 00 00       	call   10446c0 <my.json::fail>
 104439f:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 10443a4:	48 8d 3d 25 e4 00 00 	lea    0xe425(%rip),%rdi        # 10527d0 <core_io_file_error.verbs+0xb30>
 10443ab:	e9 93 fc ff ff       	jmp    1044043 <my.json::read_value+0x1963>
 10443b0:	83 f8 ff             	cmp    $0xffffffff,%eax
 10443b3:	74 15                	je     10443ca <my.json::read_value+0x1cea>
 10443b5:	e8 c6 c7 ff ff       	call   1040b80 <myl_core_release_slow>
 10443ba:	eb 0e                	jmp    10443ca <my.json::read_value+0x1cea>
 10443bc:	89 07                	mov    %eax,(%rdi)
 10443be:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
 10443c3:	e9 80 fc ff ff       	jmp    1044048 <my.json::read_value+0x1968>
 10443c8:	89 07                	mov    %eax,(%rdi)
 10443ca:	48 8d 3d 2f e4 00 00 	lea    0xe42f(%rip),%rdi        # 1052800 <core_io_file_error.verbs+0xb60>
 10443d1:	e8 2a cc ff ff       	call   1041000 <myl_core_err_trace_append_preserve_most>
 10443d6:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10443db:	8b 07                	mov    (%rdi),%eax
 10443dd:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 10443e2:	77 06                	ja     10443ea <my.json::read_value+0x1d0a>
 10443e4:	ff c0                	inc    %eax
 10443e6:	89 07                	mov    %eax,(%rdi)
 10443e8:	eb 18                	jmp    1044402 <my.json::read_value+0x1d22>
 10443ea:	83 f8 ff             	cmp    $0xffffffff,%eax
 10443ed:	0f 84 55 fc ff ff    	je     1044048 <my.json::read_value+0x1968>
 10443f3:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10443f8:	e8 43 c7 ff ff       	call   1040b40 <myl_core_retain_slow>
 10443fd:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1044402:	8b 07                	mov    (%rdi),%eax
 1044404:	85 c0                	test   %eax,%eax
 1044406:	78 33                	js     104443b <my.json::read_value+0x1d5b>
 1044408:	ff c8                	dec    %eax
 104440a:	75 42                	jne    104444e <my.json::read_value+0x1d6e>
 104440c:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1044410:	48 85 c0             	test   %rax,%rax
 1044413:	0f 84 18 02 00 00    	je     1044631 <my.json::read_value+0x1f51>
 1044419:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 104441e:	0f 85 0d 02 00 00    	jne    1044631 <my.json::read_value+0x1f51>
 1044424:	48 8d 15 25 34 03 00 	lea    0x33425(%rip),%rdx        # 1077850 <myl_core_free_lists>
 104442b:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 104442f:	48 89 0f             	mov    %rcx,(%rdi)
 1044432:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 1044436:	e9 0d fc ff ff       	jmp    1044048 <my.json::read_value+0x1968>
 104443b:	83 f8 ff             	cmp    $0xffffffff,%eax
 104443e:	0f 84 04 fc ff ff    	je     1044048 <my.json::read_value+0x1968>
 1044444:	e8 37 c7 ff ff       	call   1040b80 <myl_core_release_slow>
 1044449:	e9 fa fb ff ff       	jmp    1044048 <my.json::read_value+0x1968>
 104444e:	89 07                	mov    %eax,(%rdi)
 1044450:	e9 f3 fb ff ff       	jmp    1044048 <my.json::read_value+0x1968>
 1044455:	be 10 00 00 00       	mov    $0x10,%esi
 104445a:	31 ff                	xor    %edi,%edi
 104445c:	4c 89 d3             	mov    %r10,%rbx
 104445f:	49 89 d6             	mov    %rdx,%r14
 1044462:	e8 d9 f6 fc ff       	call   1013b40 <myl_core_list_new_slow>
 1044467:	4c 89 f2             	mov    %r14,%rdx
 104446a:	49 89 da             	mov    %rbx,%r10
 104446d:	48 89 c3             	mov    %rax,%rbx
 1044470:	e9 97 e3 ff ff       	jmp    104280c <my.json::read_value+0x12c>
 1044475:	48 8d 3d 74 de 00 00 	lea    0xde74(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104447c:	48 89 d6             	mov    %rdx,%rsi
 104447f:	48 89 c2             	mov    %rax,%rdx
 1044482:	e8 79 02 fd ff       	call   1014700 <myl_core_trap>
 1044487:	48 8d 3d 62 de 00 00 	lea    0xde62(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104448e:	4c 89 d6             	mov    %r10,%rsi
 1044491:	e8 6a 02 fd ff       	call   1014700 <myl_core_trap>
 1044496:	48 8d 3d 53 de 00 00 	lea    0xde53(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104449d:	4c 89 fe             	mov    %r15,%rsi
 10444a0:	e8 5b 02 fd ff       	call   1014700 <myl_core_trap>
 10444a5:	48 8d 3d 44 de 00 00 	lea    0xde44(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10444ac:	4c 89 fe             	mov    %r15,%rsi
 10444af:	e8 4c 02 fd ff       	call   1014700 <myl_core_trap>
 10444b4:	48 8d 3d 35 de 00 00 	lea    0xde35(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10444bb:	4c 89 fe             	mov    %r15,%rsi
 10444be:	e8 3d 02 fd ff       	call   1014700 <myl_core_trap>
 10444c3:	48 89 df             	mov    %rbx,%rdi
 10444c6:	e8 35 c7 ff ff       	call   1040c00 <myl_core_free_block>
 10444cb:	e9 44 f5 ff ff       	jmp    1043a14 <my.json::read_value+0x1334>
 10444d0:	48 89 ef             	mov    %rbp,%rdi
 10444d3:	e8 28 c7 ff ff       	call   1040c00 <myl_core_free_block>
 10444d8:	e9 b5 fb ff ff       	jmp    1044092 <my.json::read_value+0x19b2>
 10444dd:	48 89 df             	mov    %rbx,%rdi
 10444e0:	48 89 d3             	mov    %rdx,%rbx
 10444e3:	e8 18 c7 ff ff       	call   1040c00 <myl_core_free_block>
 10444e8:	48 89 da             	mov    %rbx,%rdx
 10444eb:	e9 7c f8 ff ff       	jmp    1043d6c <my.json::read_value+0x168c>
 10444f0:	e8 0b c7 ff ff       	call   1040c00 <myl_core_free_block>
 10444f5:	e9 10 fc ff ff       	jmp    104410a <my.json::read_value+0x1a2a>
 10444fa:	48 89 df             	mov    %rbx,%rdi
 10444fd:	e8 fe c6 ff ff       	call   1040c00 <myl_core_free_block>
 1044502:	e9 ef fa ff ff       	jmp    1043ff6 <my.json::read_value+0x1916>
 1044507:	48 8d 3d e2 dd 00 00 	lea    0xdde2(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104450e:	4c 89 f6             	mov    %r14,%rsi
 1044511:	48 89 c2             	mov    %rax,%rdx
 1044514:	e8 e7 01 fd ff       	call   1014700 <myl_core_trap>
 1044519:	48 8d 3d d0 dd 00 00 	lea    0xddd0(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044520:	48 89 c2             	mov    %rax,%rdx
 1044523:	e8 d8 01 fd ff       	call   1014700 <myl_core_trap>
 1044528:	48 8d 3d c1 dd 00 00 	lea    0xddc1(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104452f:	e8 cc 01 fd ff       	call   1014700 <myl_core_trap>
 1044534:	48 89 df             	mov    %rbx,%rdi
 1044537:	48 89 d3             	mov    %rdx,%rbx
 104453a:	e8 c1 c6 ff ff       	call   1040c00 <myl_core_free_block>
 104453f:	48 89 da             	mov    %rbx,%rdx
 1044542:	4c 8d 35 07 33 03 00 	lea    0x33307(%rip),%r14        # 1077850 <myl_core_free_lists>
 1044549:	e9 90 f9 ff ff       	jmp    1043ede <my.json::read_value+0x17fe>
 104454e:	48 8d 3d 9b dd 00 00 	lea    0xdd9b(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044555:	48 89 d6             	mov    %rdx,%rsi
 1044558:	48 89 c2             	mov    %rax,%rdx
 104455b:	e8 a0 01 fd ff       	call   1014700 <myl_core_trap>
 1044560:	48 89 df             	mov    %rbx,%rdi
 1044563:	e8 98 c6 ff ff       	call   1040c00 <myl_core_free_block>
 1044568:	4d 89 fe             	mov    %r15,%r14
 104456b:	e9 86 fa ff ff       	jmp    1043ff6 <my.json::read_value+0x1916>
 1044570:	e8 8b c6 ff ff       	call   1040c00 <myl_core_free_block>
 1044575:	e9 ab fa ff ff       	jmp    1044025 <my.json::read_value+0x1945>
 104457a:	48 89 ef             	mov    %rbp,%rdi
 104457d:	e8 7e c6 ff ff       	call   1040c00 <myl_core_free_block>
 1044582:	e9 8e fb ff ff       	jmp    1044115 <my.json::read_value+0x1a35>
 1044587:	48 8d 3d 62 dd 00 00 	lea    0xdd62(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104458e:	4c 89 f6             	mov    %r14,%rsi
 1044591:	e8 6a 01 fd ff       	call   1014700 <myl_core_trap>
 1044596:	48 8d 3d 53 dd 00 00 	lea    0xdd53(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104459d:	4c 89 d6             	mov    %r10,%rsi
 10445a0:	48 89 c2             	mov    %rax,%rdx
 10445a3:	e8 58 01 fd ff       	call   1014700 <myl_core_trap>
 10445a8:	48 8d 3d 41 dd 00 00 	lea    0xdd41(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10445af:	e8 4c 01 fd ff       	call   1014700 <myl_core_trap>
 10445b4:	48 8d 3d 35 dd 00 00 	lea    0xdd35(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10445bb:	4c 89 fe             	mov    %r15,%rsi
 10445be:	e8 3d 01 fd ff       	call   1014700 <myl_core_trap>
 10445c3:	48 8d 3d 26 dd 00 00 	lea    0xdd26(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10445ca:	4c 89 fe             	mov    %r15,%rsi
 10445cd:	e8 2e 01 fd ff       	call   1014700 <myl_core_trap>
 10445d2:	48 8d 3d 17 dd 00 00 	lea    0xdd17(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10445d9:	4c 89 fe             	mov    %r15,%rsi
 10445dc:	e8 1f 01 fd ff       	call   1014700 <myl_core_trap>
 10445e1:	48 89 ef             	mov    %rbp,%rdi
 10445e4:	e8 17 c6 ff ff       	call   1040c00 <myl_core_free_block>
 10445e9:	e9 d3 fc ff ff       	jmp    10442c1 <my.json::read_value+0x1be1>
 10445ee:	48 89 df             	mov    %rbx,%rdi
 10445f1:	e8 0a c6 ff ff       	call   1040c00 <myl_core_free_block>
 10445f6:	e9 59 fd ff ff       	jmp    1044354 <my.json::read_value+0x1c74>
 10445fb:	4c 89 ff             	mov    %r15,%rdi
 10445fe:	48 89 d3             	mov    %rdx,%rbx
 1044601:	e8 fa c5 ff ff       	call   1040c00 <myl_core_free_block>
 1044606:	e9 35 fc ff ff       	jmp    1044240 <my.json::read_value+0x1b60>
 104460b:	48 8d 3d de dc 00 00 	lea    0xdcde(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044612:	4c 89 f6             	mov    %r14,%rsi
 1044615:	48 89 c2             	mov    %rax,%rdx
 1044618:	e8 e3 00 fd ff       	call   1014700 <myl_core_trap>
 104461d:	e8 de c5 ff ff       	call   1040c00 <myl_core_free_block>
 1044622:	e9 66 fd ff ff       	jmp    104438d <my.json::read_value+0x1cad>
 1044627:	e8 d4 c5 ff ff       	call   1040c00 <myl_core_free_block>
 104462c:	e9 43 fd ff ff       	jmp    1044374 <my.json::read_value+0x1c94>
 1044631:	e8 ca c5 ff ff       	call   1040c00 <myl_core_free_block>
 1044636:	e9 0d fa ff ff       	jmp    1044048 <my.json::read_value+0x1968>
 104463b:	48 8d 3d ae dc 00 00 	lea    0xdcae(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044642:	48 89 d6             	mov    %rdx,%rsi
 1044645:	48 89 c2             	mov    %rax,%rdx
 1044648:	e8 b3 00 fd ff       	call   1014700 <myl_core_trap>
 104464d:	48 8d 3d 9c dc 00 00 	lea    0xdc9c(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044654:	4c 89 fe             	mov    %r15,%rsi
 1044657:	e8 a4 00 fd ff       	call   1014700 <myl_core_trap>
 104465c:	48 8d 3d 8d dc 00 00 	lea    0xdc8d(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044663:	4c 89 f6             	mov    %r14,%rsi
 1044666:	e8 95 00 fd ff       	call   1014700 <myl_core_trap>
 104466b:	48 8d 3d 7e dc 00 00 	lea    0xdc7e(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044672:	4c 89 fe             	mov    %r15,%rsi
 1044675:	e8 86 00 fd ff       	call   1014700 <myl_core_trap>
 104467a:	e8 81 c5 ff ff       	call   1040c00 <myl_core_free_block>
 104467f:	e9 46 fd ff ff       	jmp    10443ca <my.json::read_value+0x1cea>
 1044684:	48 8d 3d 65 dc 00 00 	lea    0xdc65(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104468b:	4c 89 f6             	mov    %r14,%rsi
 104468e:	e8 6d 00 fd ff       	call   1014700 <myl_core_trap>
 1044693:	48 8d 3d 56 dc 00 00 	lea    0xdc56(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104469a:	48 89 c2             	mov    %rax,%rdx
 104469d:	e8 5e 00 fd ff       	call   1014700 <myl_core_trap>
 10446a2:	48 8d 3d 47 dc 00 00 	lea    0xdc47(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10446a9:	4c 89 fe             	mov    %r15,%rsi
 10446ac:	e8 4f 00 fd ff       	call   1014700 <myl_core_trap>
 10446b1:	48 8d 3d 38 dc 00 00 	lea    0xdc38(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10446b8:	4c 89 f6             	mov    %r14,%rsi
 10446bb:	e8 40 00 fd ff       	call   1014700 <myl_core_trap>

Disassembly of section .plt:
