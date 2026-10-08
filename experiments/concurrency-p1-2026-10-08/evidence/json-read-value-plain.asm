
.mylang-cache/concurrency-p1/tax-rows/plain/json_transform:     file format elf64-x86-64


Disassembly of section .text:

00000000010426a0 <my.json::read_value>:
 10426a0:	55                   	push   %rbp
 10426a1:	41 57                	push   %r15
 10426a3:	41 56                	push   %r14
 10426a5:	41 55                	push   %r13
 10426a7:	41 54                	push   %r12
 10426a9:	53                   	push   %rbx
 10426aa:	48 81 ec 88 01 00 00 	sub    $0x188,%rsp
 10426b1:	49 89 d2             	mov    %rdx,%r10
 10426b4:	49 89 f4             	mov    %rsi,%r12
 10426b7:	48 89 4c 24 58       	mov    %rcx,0x58(%rsp)
 10426bc:	48 83 f9 40          	cmp    $0x40,%rcx
 10426c0:	0f 8f 1f 12 00 00    	jg     10438e5 <my.json::read_value+0x1245>
 10426c6:	48 89 7c 24 18       	mov    %rdi,0x18(%rsp)
 10426cb:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 10426d0:	49 39 d2             	cmp    %rdx,%r10
 10426d3:	0f 8d 63 00 00 00    	jge    104273c <my.json::read_value+0x9c>
 10426d9:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 10426e0:	00 00 00
 10426e3:	4c 89 e6             	mov    %r12,%rsi
 10426e6:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10426ed:	0f 1f 84 00 00 00 00
 10426f4:	00
 10426f5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 10426fc:	00 00 00 00
 1042700:	4c 89 d7             	mov    %r10,%rdi
 1042703:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1042707:	48 21 d7             	and    %rdx,%rdi
 104270a:	4e 8d 04 17          	lea    (%rdi,%r10,1),%r8
 104270e:	49 39 d0             	cmp    %rdx,%r8
 1042711:	0f 83 2e 1d 00 00    	jae    1044445 <my.json::read_value+0x1da5>
 1042717:	48 01 fe             	add    %rdi,%rsi
 104271a:	41 0f b6 54 32 20    	movzbl 0x20(%r10,%rsi,1),%edx
 1042720:	48 83 fa 20          	cmp    $0x20,%rdx
 1042724:	77 16                	ja     104273c <my.json::read_value+0x9c>
 1042726:	48 0f a3 d0          	bt     %rdx,%rax
 104272a:	73 10                	jae    104273c <my.json::read_value+0x9c>
 104272c:	49 ff c2             	inc    %r10
 104272f:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042734:	4c 89 e6             	mov    %r12,%rsi
 1042737:	49 39 d2             	cmp    %rdx,%r10
 104273a:	7c c4                	jl     1042700 <my.json::read_value+0x60>
 104273c:	4d 89 e5             	mov    %r12,%r13
 104273f:	4c 89 d2             	mov    %r10,%rdx
 1042742:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 1042747:	49 39 c2             	cmp    %rax,%r10
 104274a:	0f 8d d0 11 00 00    	jge    1043920 <my.json::read_value+0x1280>
 1042750:	4c 89 d6             	mov    %r10,%rsi
 1042753:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1042757:	48 21 c6             	and    %rax,%rsi
 104275a:	4c 01 d6             	add    %r10,%rsi
 104275d:	48 39 c6             	cmp    %rax,%rsi
 1042760:	0f 83 eb 1d 00 00    	jae    1044551 <my.json::read_value+0x1eb1>
 1042766:	41 0f b6 74 35 20    	movzbl 0x20(%r13,%rsi,1),%esi
 104276c:	40 0f b6 fe          	movzbl %sil,%edi
 1042770:	44 8d 47 a5          	lea    -0x5b(%rdi),%r8d
 1042774:	41 83 f8 20          	cmp    $0x20,%r8d
 1042778:	0f 87 97 03 00 00    	ja     1042b15 <my.json::read_value+0x475>
 104277e:	48 8d 3d 5b 43 fc ff 	lea    -0x3bca5(%rip),%rdi        # 1006ae0 <core_number_pairs+0x110>
 1042785:	4e 63 04 87          	movslq (%rdi,%r8,4),%r8
 1042789:	49 01 f8             	add    %rdi,%r8
 104278c:	41 ff e0             	jmp    *%r8
 104278f:	49 8d 52 01          	lea    0x1(%r10),%rdx
 1042793:	48 8d 0d b6 50 03 00 	lea    0x350b6(%rip),%rcx        # 1077850 <myl_core_free_lists>
 104279a:	48 8b 59 08          	mov    0x8(%rcx),%rbx
 104279e:	48 85 db             	test   %rbx,%rbx
 10427a1:	0f 84 6c 1c 00 00    	je     1044413 <my.json::read_value+0x1d73>
 10427a7:	48 8b 03             	mov    (%rbx),%rax
 10427aa:	48 89 41 08          	mov    %rax,0x8(%rcx)
 10427ae:	48 b8 01 00 00 00 00 	movabs $0x100000000000001,%rax
 10427b5:	00 00 01
 10427b8:	48 89 03             	mov    %rax,(%rbx)
 10427bb:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
 10427bf:	c5 fa 7f 43 08       	vmovdqu %xmm0,0x8(%rbx)
 10427c4:	48 c7 43 18 00 00 00 	movq   $0x0,0x18(%rbx)
 10427cb:	00
 10427cc:	48 8d 05 61 65 fc ff 	lea    -0x39a9f(%rip),%rax        # 1008d34 <core_number_pairs+0x2364>
 10427d3:	48 89 43 18          	mov    %rax,0x18(%rbx)
 10427d7:	49 8b 45 08          	mov    0x8(%r13),%rax
 10427db:	48 39 c2             	cmp    %rax,%rdx
 10427de:	7d 6a                	jge    104284a <my.json::read_value+0x1aa>
 10427e0:	48 bf 00 26 00 00 01 	movabs $0x100002600,%rdi
 10427e7:	00 00 00
 10427ea:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10427f1:	0f 1f 84 00 00 00 00
 10427f8:	00
 10427f9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1042800:	49 8d 72 01          	lea    0x1(%r10),%rsi
 1042804:	49 89 f0             	mov    %rsi,%r8
 1042807:	49 c1 f8 3f          	sar    $0x3f,%r8
 104280b:	49 21 c0             	and    %rax,%r8
 104280e:	4f 8d 0c 02          	lea    (%r10,%r8,1),%r9
 1042812:	49 ff c1             	inc    %r9
 1042815:	49 39 c1             	cmp    %rax,%r9
 1042818:	0f 83 c6 1c 00 00    	jae    10444e4 <my.json::read_value+0x1e44>
 104281e:	4d 01 c5             	add    %r8,%r13
 1042821:	43 0f b6 44 2a 21    	movzbl 0x21(%r10,%r13,1),%eax
 1042827:	48 83 f8 20          	cmp    $0x20,%rax
 104282b:	77 1d                	ja     104284a <my.json::read_value+0x1aa>
 104282d:	48 0f a3 c7          	bt     %rax,%rdi
 1042831:	73 17                	jae    104284a <my.json::read_value+0x1aa>
 1042833:	4c 89 d2             	mov    %r10,%rdx
 1042836:	48 83 c2 02          	add    $0x2,%rdx
 104283a:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 104283f:	49 89 f2             	mov    %rsi,%r10
 1042842:	4d 89 e5             	mov    %r12,%r13
 1042845:	48 39 c2             	cmp    %rax,%rdx
 1042848:	7c b6                	jl     1042800 <my.json::read_value+0x160>
 104284a:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 104284f:	48 39 c2             	cmp    %rax,%rdx
 1042852:	0f 8d 41 17 00 00    	jge    1043f99 <my.json::read_value+0x18f9>
 1042858:	48 89 d1             	mov    %rdx,%rcx
 104285b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 104285f:	48 21 c1             	and    %rax,%rcx
 1042862:	48 01 d1             	add    %rdx,%rcx
 1042865:	48 39 c1             	cmp    %rax,%rcx
 1042868:	0f 83 88 1d 00 00    	jae    10445f6 <my.json::read_value+0x1f56>
 104286e:	41 80 7c 0c 20 5d    	cmpb   $0x5d,0x20(%r12,%rcx,1)
 1042874:	0f 84 50 11 00 00    	je     10439ca <my.json::read_value+0x132a>
 104287a:	48 ff 44 24 58       	incq   0x58(%rsp)
 104287f:	48 bd 00 26 00 00 01 	movabs $0x100002600,%rbp
 1042886:	00 00 00
 1042889:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1042890:	48 8d 7c 24 78       	lea    0x78(%rsp),%rdi
 1042895:	4c 89 e6             	mov    %r12,%rsi
 1042898:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 104289d:	e8 fe fd ff ff       	call   10426a0 <my.json::read_value>
 10428a2:	4c 8b 74 24 78       	mov    0x78(%rsp),%r14
 10428a7:	4c 8b bc 24 80 00 00 	mov    0x80(%rsp),%r15
 10428ae:	00
 10428af:	41 0f b6 c6          	movzbl %r14b,%eax
 10428b3:	4c 8b a4 24 90 00 00 	mov    0x90(%rsp),%r12
 10428ba:	00
 10428bb:	48 8b 94 24 98 00 00 	mov    0x98(%rsp),%rdx
 10428c2:	00
 10428c3:	83 f8 01             	cmp    $0x1,%eax
 10428c6:	0f 84 c7 15 00 00    	je     1043e93 <my.json::read_value+0x17f3>
 10428cc:	4c 8b ac 24 88 00 00 	mov    0x88(%rsp),%r13
 10428d3:	00
 10428d4:	41 80 ff 06          	cmp    $0x6,%r15b
 10428d8:	74 0e                	je     10428e8 <my.json::read_value+0x248>
 10428da:	41 0f b6 c7          	movzbl %r15b,%eax
 10428de:	83 f8 05             	cmp    $0x5,%eax
 10428e1:	74 05                	je     10428e8 <my.json::read_value+0x248>
 10428e3:	83 f8 04             	cmp    $0x4,%eax
 10428e6:	75 21                	jne    1042909 <my.json::read_value+0x269>
 10428e8:	41 8b 45 00          	mov    0x0(%r13),%eax
 10428ec:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 10428f1:	77 0d                	ja     1042900 <my.json::read_value+0x260>
 10428f3:	ff c0                	inc    %eax
 10428f5:	41 89 45 00          	mov    %eax,0x0(%r13)
 10428f9:	eb 0e                	jmp    1042909 <my.json::read_value+0x269>
 10428fb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1042900:	83 f8 ff             	cmp    $0xffffffff,%eax
 1042903:	0f 85 bb 01 00 00    	jne    1042ac4 <my.json::read_value+0x424>
 1042909:	48 8b 43 08          	mov    0x8(%rbx),%rax
 104290d:	48 3b 43 10          	cmp    0x10(%rbx),%rax
 1042911:	0f 83 ca 01 00 00    	jae    1042ae1 <my.json::read_value+0x441>
 1042917:	48 89 c1             	mov    %rax,%rcx
 104291a:	48 c1 e1 04          	shl    $0x4,%rcx
 104291e:	41 0f b6 f7          	movzbl %r15b,%esi
 1042922:	48 89 74 0b 20       	mov    %rsi,0x20(%rbx,%rcx,1)
 1042927:	4c 89 6c 0b 28       	mov    %r13,0x28(%rbx,%rcx,1)
 104292c:	48 ff c0             	inc    %rax
 104292f:	48 89 43 08          	mov    %rax,0x8(%rbx)
 1042933:	41 80 fe 01          	cmp    $0x1,%r14b
 1042937:	74 47                	je     1042980 <my.json::read_value+0x2e0>
 1042939:	41 0f b6 c6          	movzbl %r14b,%eax
 104293d:	85 c0                	test   %eax,%eax
 104293f:	0f 85 fb 00 00 00    	jne    1042a40 <my.json::read_value+0x3a0>
 1042945:	41 80 ff 06          	cmp    $0x6,%r15b
 1042949:	74 6b                	je     10429b6 <my.json::read_value+0x316>
 104294b:	41 0f b6 c7          	movzbl %r15b,%eax
 104294f:	83 f8 05             	cmp    $0x5,%eax
 1042952:	74 4d                	je     10429a1 <my.json::read_value+0x301>
 1042954:	83 f8 04             	cmp    $0x4,%eax
 1042957:	0f 85 e3 00 00 00    	jne    1042a40 <my.json::read_value+0x3a0>
 104295d:	41 8b 45 00          	mov    0x0(%r13),%eax
 1042961:	85 c0                	test   %eax,%eax
 1042963:	78 63                	js     10429c8 <my.json::read_value+0x328>
 1042965:	ff c8                	dec    %eax
 1042967:	0f 84 9d 00 00 00    	je     1042a0a <my.json::read_value+0x36a>
 104296d:	41 89 45 00          	mov    %eax,0x0(%r13)
 1042971:	e9 ca 00 00 00       	jmp    1042a40 <my.json::read_value+0x3a0>
 1042976:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 104297d:	00 00 00
 1042980:	41 8b 07             	mov    (%r15),%eax
 1042983:	85 c0                	test   %eax,%eax
 1042985:	78 0c                	js     1042993 <my.json::read_value+0x2f3>
 1042987:	ff c8                	dec    %eax
 1042989:	74 52                	je     10429dd <my.json::read_value+0x33d>
 104298b:	41 89 07             	mov    %eax,(%r15)
 104298e:	e9 ad 00 00 00       	jmp    1042a40 <my.json::read_value+0x3a0>
 1042993:	83 f8 ff             	cmp    $0xffffffff,%eax
 1042996:	0f 84 a4 00 00 00    	je     1042a40 <my.json::read_value+0x3a0>
 104299c:	4c 89 ff             	mov    %r15,%rdi
 104299f:	eb 2f                	jmp    10429d0 <my.json::read_value+0x330>
 10429a1:	41 8b 45 00          	mov    0x0(%r13),%eax
 10429a5:	85 c0                	test   %eax,%eax
 10429a7:	78 1f                	js     10429c8 <my.json::read_value+0x328>
 10429a9:	ff c8                	dec    %eax
 10429ab:	74 5d                	je     1042a0a <my.json::read_value+0x36a>
 10429ad:	41 89 45 00          	mov    %eax,0x0(%r13)
 10429b1:	e9 8a 00 00 00       	jmp    1042a40 <my.json::read_value+0x3a0>
 10429b6:	41 8b 45 00          	mov    0x0(%r13),%eax
 10429ba:	85 c0                	test   %eax,%eax
 10429bc:	78 0a                	js     10429c8 <my.json::read_value+0x328>
 10429be:	ff c8                	dec    %eax
 10429c0:	74 48                	je     1042a0a <my.json::read_value+0x36a>
 10429c2:	41 89 45 00          	mov    %eax,0x0(%r13)
 10429c6:	eb 78                	jmp    1042a40 <my.json::read_value+0x3a0>
 10429c8:	83 f8 ff             	cmp    $0xffffffff,%eax
 10429cb:	74 73                	je     1042a40 <my.json::read_value+0x3a0>
 10429cd:	4c 89 ef             	mov    %r13,%rdi
 10429d0:	49 89 d6             	mov    %rdx,%r14
 10429d3:	e8 68 e1 ff ff       	call   1040b40 <myl_core_release_slow>
 10429d8:	4c 89 f2             	mov    %r14,%rdx
 10429db:	eb 63                	jmp    1042a40 <my.json::read_value+0x3a0>
 10429dd:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 10429e2:	48 85 c0             	test   %rax,%rax
 10429e5:	0f 84 15 01 00 00    	je     1042b00 <my.json::read_value+0x460>
 10429eb:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 10429f0:	0f 85 0a 01 00 00    	jne    1042b00 <my.json::read_value+0x460>
 10429f6:	48 8d 35 53 4e 03 00 	lea    0x34e53(%rip),%rsi        # 1077850 <myl_core_free_lists>
 10429fd:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1042a01:	49 89 0f             	mov    %rcx,(%r15)
 1042a04:	4c 89 3c c6          	mov    %r15,(%rsi,%rax,8)
 1042a08:	eb 36                	jmp    1042a40 <my.json::read_value+0x3a0>
 1042a0a:	41 0f b6 45 07       	movzbl 0x7(%r13),%eax
 1042a0f:	48 85 c0             	test   %rax,%rax
 1042a12:	0f 84 ed 00 00 00    	je     1042b05 <my.json::read_value+0x465>
 1042a18:	49 83 7d 18 00       	cmpq   $0x0,0x18(%r13)
 1042a1d:	0f 85 e2 00 00 00    	jne    1042b05 <my.json::read_value+0x465>
 1042a23:	48 8d 35 26 4e 03 00 	lea    0x34e26(%rip),%rsi        # 1077850 <myl_core_free_lists>
 1042a2a:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1042a2e:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 1042a32:	4c 89 2c c6          	mov    %r13,(%rsi,%rax,8)
 1042a36:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 1042a3d:	00 00 00
 1042a40:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 1042a45:	48 39 c2             	cmp    %rax,%rdx
 1042a48:	7d 36                	jge    1042a80 <my.json::read_value+0x3e0>
 1042a4a:	48 89 d1             	mov    %rdx,%rcx
 1042a4d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1042a51:	48 21 c1             	and    %rax,%rcx
 1042a54:	48 8d 34 11          	lea    (%rcx,%rdx,1),%rsi
 1042a58:	48 39 c6             	cmp    %rax,%rsi
 1042a5b:	0f 83 d2 19 00 00    	jae    1044433 <my.json::read_value+0x1d93>
 1042a61:	4c 01 e1             	add    %r12,%rcx
 1042a64:	0f b6 44 0a 20       	movzbl 0x20(%rdx,%rcx,1),%eax
 1042a69:	48 83 f8 20          	cmp    $0x20,%rax
 1042a6d:	77 11                	ja     1042a80 <my.json::read_value+0x3e0>
 1042a6f:	48 0f a3 c5          	bt     %rax,%rbp
 1042a73:	73 0b                	jae    1042a80 <my.json::read_value+0x3e0>
 1042a75:	48 ff c2             	inc    %rdx
 1042a78:	eb c6                	jmp    1042a40 <my.json::read_value+0x3a0>
 1042a7a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1042a80:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 1042a85:	48 39 c2             	cmp    %rax,%rdx
 1042a88:	0f 8d 76 12 00 00    	jge    1043d04 <my.json::read_value+0x1664>
 1042a8e:	48 89 d1             	mov    %rdx,%rcx
 1042a91:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1042a95:	48 21 c1             	and    %rax,%rcx
 1042a98:	48 01 d1             	add    %rdx,%rcx
 1042a9b:	48 39 c1             	cmp    %rax,%rcx
 1042a9e:	0f 83 75 1a 00 00    	jae    1044519 <my.json::read_value+0x1e79>
 1042aa4:	41 0f b6 4c 0c 20    	movzbl 0x20(%r12,%rcx,1),%ecx
 1042aaa:	83 f9 2c             	cmp    $0x2c,%ecx
 1042aad:	0f 85 0e 0f 00 00    	jne    10439c1 <my.json::read_value+0x1321>
 1042ab3:	48 ff c2             	inc    %rdx
 1042ab6:	48 39 c2             	cmp    %rax,%rdx
 1042ab9:	0f 8c d1 fd ff ff    	jl     1042890 <my.json::read_value+0x1f0>
 1042abf:	e9 b1 14 00 00       	jmp    1043f75 <my.json::read_value+0x18d5>
 1042ac4:	4c 89 ef             	mov    %r13,%rdi
 1042ac7:	4c 89 64 24 38       	mov    %r12,0x38(%rsp)
 1042acc:	49 89 d4             	mov    %rdx,%r12
 1042acf:	e8 2c e0 ff ff       	call   1040b00 <myl_core_retain_slow>
 1042ad4:	4c 89 e2             	mov    %r12,%rdx
 1042ad7:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 1042adc:	e9 28 fe ff ff       	jmp    1042909 <my.json::read_value+0x269>
 1042ae1:	be 10 00 00 00       	mov    $0x10,%esi
 1042ae6:	48 89 df             	mov    %rbx,%rdi
 1042ae9:	48 89 d3             	mov    %rdx,%rbx
 1042aec:	e8 cf 10 fd ff       	call   1013bc0 <myl_core_list_grow>
 1042af1:	48 89 da             	mov    %rbx,%rdx
 1042af4:	48 89 c3             	mov    %rax,%rbx
 1042af7:	48 8b 40 08          	mov    0x8(%rax),%rax
 1042afb:	e9 17 fe ff ff       	jmp    1042917 <my.json::read_value+0x277>
 1042b00:	4c 89 ff             	mov    %r15,%rdi
 1042b03:	eb 03                	jmp    1042b08 <my.json::read_value+0x468>
 1042b05:	4c 89 ef             	mov    %r13,%rdi
 1042b08:	49 89 d6             	mov    %rdx,%r14
 1042b0b:	e8 b0 e0 ff ff       	call   1040bc0 <myl_core_free_block>
 1042b10:	e9 c3 fe ff ff       	jmp    10429d8 <my.json::read_value+0x338>
 1042b15:	83 ff 22             	cmp    $0x22,%edi
 1042b18:	0f 84 6e 0d 00 00    	je     104388c <my.json::read_value+0x11ec>
 1042b1e:	83 ff 2d             	cmp    $0x2d,%edi
 1042b21:	74 0d                	je     1042b30 <my.json::read_value+0x490>
 1042b23:	8d 7e d0             	lea    -0x30(%rsi),%edi
 1042b26:	40 80 ff 0a          	cmp    $0xa,%dil
 1042b2a:	0f 83 0a 10 00 00    	jae    1043b3a <my.json::read_value+0x149a>
 1042b30:	49 8d 7a 01          	lea    0x1(%r10),%rdi
 1042b34:	40 80 fe 2d          	cmp    $0x2d,%sil
 1042b38:	4d 89 d6             	mov    %r10,%r14
 1042b3b:	4c 0f 44 f7          	cmove  %rdi,%r14
 1042b3f:	48 0f 44 d7          	cmove  %rdi,%rdx
 1042b43:	49 39 c6             	cmp    %rax,%r14
 1042b46:	0f 8d db 0e 00 00    	jge    1043a27 <my.json::read_value+0x1387>
 1042b4c:	4c 89 f6             	mov    %r14,%rsi
 1042b4f:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1042b53:	48 21 c6             	and    %rax,%rsi
 1042b56:	4c 01 f6             	add    %r14,%rsi
 1042b59:	48 39 c6             	cmp    %rax,%rsi
 1042b5c:	0f 83 78 1a 00 00    	jae    10445da <my.json::read_value+0x1f3a>
 1042b62:	41 0f b6 74 35 20    	movzbl 0x20(%r13,%rsi,1),%esi
 1042b68:	8d 7e d0             	lea    -0x30(%rsi),%edi
 1042b6b:	40 80 ff 0a          	cmp    $0xa,%dil
 1042b6f:	0f 83 b2 0e 00 00    	jae    1043a27 <my.json::read_value+0x1387>
 1042b75:	40 80 fe 30          	cmp    $0x30,%sil
 1042b79:	0f 85 ab 0c 00 00    	jne    104382a <my.json::read_value+0x118a>
 1042b7f:	49 8d 76 01          	lea    0x1(%r14),%rsi
 1042b83:	bb 01 00 00 00       	mov    $0x1,%ebx
 1042b88:	48 39 c6             	cmp    %rax,%rsi
 1042b8b:	7d 26                	jge    1042bb3 <my.json::read_value+0x513>
 1042b8d:	31 d2                	xor    %edx,%edx
 1042b8f:	49 83 fe ff          	cmp    $0xffffffffffffffff,%r14
 1042b93:	48 0f 4c d0          	cmovl  %rax,%rdx
 1042b97:	48 01 f2             	add    %rsi,%rdx
 1042b9a:	48 39 c2             	cmp    %rax,%rdx
 1042b9d:	0f 83 ab 1a 00 00    	jae    104464e <my.json::read_value+0x1fae>
 1042ba3:	41 0f b6 44 15 20    	movzbl 0x20(%r13,%rdx,1),%eax
 1042ba9:	04 d0                	add    $0xd0,%al
 1042bab:	3c 0a                	cmp    $0xa,%al
 1042bad:	0f 82 79 12 00 00    	jb     1043e2c <my.json::read_value+0x178c>
 1042bb3:	31 c0                	xor    %eax,%eax
 1042bb5:	49 89 f6             	mov    %rsi,%r14
 1042bb8:	3c 01                	cmp    $0x1,%al
 1042bba:	0f 84 ad 0d 00 00    	je     104396d <my.json::read_value+0x12cd>
 1042bc0:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042bc5:	49 39 d6             	cmp    %rdx,%r14
 1042bc8:	0f 8d c1 00 00 00    	jge    1042c8f <my.json::read_value+0x5ef>
 1042bce:	4c 89 f0             	mov    %r14,%rax
 1042bd1:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042bd5:	48 21 d0             	and    %rdx,%rax
 1042bd8:	4c 01 f0             	add    %r14,%rax
 1042bdb:	48 39 d0             	cmp    %rdx,%rax
 1042bde:	0f 83 33 1a 00 00    	jae    1044617 <my.json::read_value+0x1f77>
 1042be4:	41 80 7c 04 20 2e    	cmpb   $0x2e,0x20(%r12,%rax,1)
 1042bea:	0f 85 9f 00 00 00    	jne    1042c8f <my.json::read_value+0x5ef>
 1042bf0:	4d 8d 7e 01          	lea    0x1(%r14),%r15
 1042bf4:	49 39 d7             	cmp    %rdx,%r15
 1042bf7:	0f 8d fc 0f 00 00    	jge    1043bf9 <my.json::read_value+0x1559>
 1042bfd:	31 c0                	xor    %eax,%eax
 1042bff:	49 83 fe ff          	cmp    $0xffffffffffffffff,%r14
 1042c03:	48 0f 4c c2          	cmovl  %rdx,%rax
 1042c07:	4c 01 f8             	add    %r15,%rax
 1042c0a:	48 39 d0             	cmp    %rdx,%rax
 1042c0d:	0f 83 4a 1a 00 00    	jae    104465d <my.json::read_value+0x1fbd>
 1042c13:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 1042c19:	04 d0                	add    $0xd0,%al
 1042c1b:	3c 09                	cmp    $0x9,%al
 1042c1d:	0f 87 d6 0f 00 00    	ja     1043bf9 <my.json::read_value+0x1559>
 1042c23:	bb 01 00 00 00       	mov    $0x1,%ebx
 1042c28:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042c2f:	0f 1f 84 00 00 00 00
 1042c36:	00
 1042c37:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1042c3e:	00 00
 1042c40:	49 8d 76 01          	lea    0x1(%r14),%rsi
 1042c44:	48 89 f0             	mov    %rsi,%rax
 1042c47:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042c4b:	48 21 d0             	and    %rdx,%rax
 1042c4e:	49 8d 3c 06          	lea    (%r14,%rax,1),%rdi
 1042c52:	48 ff c7             	inc    %rdi
 1042c55:	48 39 d7             	cmp    %rdx,%rdi
 1042c58:	0f 83 05 19 00 00    	jae    1044563 <my.json::read_value+0x1ec3>
 1042c5e:	4c 89 e2             	mov    %r12,%rdx
 1042c61:	48 01 c2             	add    %rax,%rdx
 1042c64:	41 0f b6 44 16 21    	movzbl 0x21(%r14,%rdx,1),%eax
 1042c6a:	04 d0                	add    $0xd0,%al
 1042c6c:	3c 0a                	cmp    $0xa,%al
 1042c6e:	73 14                	jae    1042c84 <my.json::read_value+0x5e4>
 1042c70:	4d 89 f7             	mov    %r14,%r15
 1042c73:	49 83 c7 02          	add    $0x2,%r15
 1042c77:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042c7c:	49 89 f6             	mov    %rsi,%r14
 1042c7f:	49 39 d7             	cmp    %rdx,%r15
 1042c82:	7c bc                	jl     1042c40 <my.json::read_value+0x5a0>
 1042c84:	31 c0                	xor    %eax,%eax
 1042c86:	3c 01                	cmp    $0x1,%al
 1042c88:	75 14                	jne    1042c9e <my.json::read_value+0x5fe>
 1042c8a:	e9 9b 0f 00 00       	jmp    1043c2a <my.json::read_value+0x158a>
 1042c8f:	31 c0                	xor    %eax,%eax
 1042c91:	31 db                	xor    %ebx,%ebx
 1042c93:	4d 89 f7             	mov    %r14,%r15
 1042c96:	3c 01                	cmp    $0x1,%al
 1042c98:	0f 84 8c 0f 00 00    	je     1043c2a <my.json::read_value+0x158a>
 1042c9e:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042ca3:	49 39 d7             	cmp    %rdx,%r15
 1042ca6:	0f 8d dd 00 00 00    	jge    1042d89 <my.json::read_value+0x6e9>
 1042cac:	4c 89 f8             	mov    %r15,%rax
 1042caf:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042cb3:	48 21 d0             	and    %rdx,%rax
 1042cb6:	4c 01 f8             	add    %r15,%rax
 1042cb9:	48 39 d0             	cmp    %rdx,%rax
 1042cbc:	0f 83 64 19 00 00    	jae    1044626 <my.json::read_value+0x1f86>
 1042cc2:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 1042cc8:	83 c8 20             	or     $0x20,%eax
 1042ccb:	83 f8 65             	cmp    $0x65,%eax
 1042cce:	0f 85 b5 00 00 00    	jne    1042d89 <my.json::read_value+0x6e9>
 1042cd4:	4d 8d 77 01          	lea    0x1(%r15),%r14
 1042cd8:	49 39 d6             	cmp    %rdx,%r14
 1042cdb:	7d 2d                	jge    1042d0a <my.json::read_value+0x66a>
 1042cdd:	31 c0                	xor    %eax,%eax
 1042cdf:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 1042ce3:	48 0f 4c c2          	cmovl  %rdx,%rax
 1042ce7:	4c 01 f0             	add    %r14,%rax
 1042cea:	48 39 d0             	cmp    %rdx,%rax
 1042ced:	0f 83 79 19 00 00    	jae    104466c <my.json::read_value+0x1fcc>
 1042cf3:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 1042cf9:	83 f8 2d             	cmp    $0x2d,%eax
 1042cfc:	74 05                	je     1042d03 <my.json::read_value+0x663>
 1042cfe:	83 f8 2b             	cmp    $0x2b,%eax
 1042d01:	75 07                	jne    1042d0a <my.json::read_value+0x66a>
 1042d03:	49 83 c7 02          	add    $0x2,%r15
 1042d07:	4d 89 fe             	mov    %r15,%r14
 1042d0a:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042d0f:	49 39 d6             	cmp    %rdx,%r14
 1042d12:	0f 8d 46 0e 00 00    	jge    1043b5e <my.json::read_value+0x14be>
 1042d18:	4c 89 f0             	mov    %r14,%rax
 1042d1b:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042d1f:	48 21 d0             	and    %rdx,%rax
 1042d22:	4c 01 f0             	add    %r14,%rax
 1042d25:	48 39 d0             	cmp    %rdx,%rax
 1042d28:	0f 83 11 19 00 00    	jae    104463f <my.json::read_value+0x1f9f>
 1042d2e:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 1042d34:	04 d0                	add    $0xd0,%al
 1042d36:	3c 09                	cmp    $0x9,%al
 1042d38:	0f 87 20 0e 00 00    	ja     1043b5e <my.json::read_value+0x14be>
 1042d3e:	66 90                	xchg   %ax,%ax
 1042d40:	4c 89 f0             	mov    %r14,%rax
 1042d43:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042d47:	48 21 d0             	and    %rdx,%rax
 1042d4a:	4a 8d 34 30          	lea    (%rax,%r14,1),%rsi
 1042d4e:	48 39 d6             	cmp    %rdx,%rsi
 1042d51:	0f 83 eb 17 00 00    	jae    1044542 <my.json::read_value+0x1ea2>
 1042d57:	4c 89 e2             	mov    %r12,%rdx
 1042d5a:	48 01 c2             	add    %rax,%rdx
 1042d5d:	41 0f b6 54 16 20    	movzbl 0x20(%r14,%rdx,1),%edx
 1042d63:	80 c2 d0             	add    $0xd0,%dl
 1042d66:	b8 01 00 00 00       	mov    $0x1,%eax
 1042d6b:	80 fa 0a             	cmp    $0xa,%dl
 1042d6e:	73 0d                	jae    1042d7d <my.json::read_value+0x6dd>
 1042d70:	49 ff c6             	inc    %r14
 1042d73:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042d78:	49 39 d6             	cmp    %rdx,%r14
 1042d7b:	7c c3                	jl     1042d40 <my.json::read_value+0x6a0>
 1042d7d:	31 d2                	xor    %edx,%edx
 1042d7f:	80 fa 01             	cmp    $0x1,%dl
 1042d82:	75 15                	jne    1042d99 <my.json::read_value+0x6f9>
 1042d84:	e9 04 0e 00 00       	jmp    1043b8d <my.json::read_value+0x14ed>
 1042d89:	31 d2                	xor    %edx,%edx
 1042d8b:	31 c0                	xor    %eax,%eax
 1042d8d:	4d 89 fe             	mov    %r15,%r14
 1042d90:	80 fa 01             	cmp    $0x1,%dl
 1042d93:	0f 84 f4 0d 00 00    	je     1043b8d <my.json::read_value+0x14ed>
 1042d99:	08 d8                	or     %bl,%al
 1042d9b:	a8 01                	test   $0x1,%al
 1042d9d:	75 24                	jne    1042dc3 <my.json::read_value+0x723>
 1042d9f:	4c 89 e7             	mov    %r12,%rdi
 1042da2:	4c 89 d6             	mov    %r10,%rsi
 1042da5:	4c 89 d3             	mov    %r10,%rbx
 1042da8:	4c 89 f2             	mov    %r14,%rdx
 1042dab:	e8 10 87 fe ff       	call   102b4c0 <myl_core_parse_int_range>
 1042db0:	49 89 da             	mov    %rbx,%r10
 1042db3:	3c 01                	cmp    $0x1,%al
 1042db5:	75 0c                	jne    1042dc3 <my.json::read_value+0x723>
 1042db7:	bb 02 00 00 00       	mov    $0x2,%ebx
 1042dbc:	31 c0                	xor    %eax,%eax
 1042dbe:	e9 d9 0f 00 00       	jmp    1043d9c <my.json::read_value+0x16fc>
 1042dc3:	4c 89 e7             	mov    %r12,%rdi
 1042dc6:	4c 89 d6             	mov    %r10,%rsi
 1042dc9:	4c 89 f2             	mov    %r14,%rdx
 1042dcc:	e8 0f 87 00 00       	call   104b4e0 <myl_core_parse_float_range>
 1042dd1:	3c 01                	cmp    $0x1,%al
 1042dd3:	0f 85 f8 0c 00 00    	jne    1043ad1 <my.json::read_value+0x1431>
 1042dd9:	c4 e1 f9 7e c2       	vmovq  %xmm0,%rdx
 1042dde:	bb 03 00 00 00       	mov    $0x3,%ebx
 1042de3:	31 c0                	xor    %eax,%eax
 1042de5:	e9 b2 0f 00 00       	jmp    1043d9c <my.json::read_value+0x16fc>
 1042dea:	48 8d 0d 4f 54 fc ff 	lea    -0x3abb1(%rip),%rcx        # 1008240 <core_number_pairs+0x1870>
 1042df1:	48 8d bc 24 38 01 00 	lea    0x138(%rsp),%rdi
 1042df8:	00
 1042df9:	4c 89 e6             	mov    %r12,%rsi
 1042dfc:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 1042e02:	45 31 c9             	xor    %r9d,%r9d
 1042e05:	e8 36 29 00 00       	call   1045740 <my.json::read_literal>
 1042e0a:	0f b6 84 24 38 01 00 	movzbl 0x138(%rsp),%eax
 1042e11:	00
 1042e12:	c5 fa 6f 84 24 40 01 	vmovdqu 0x140(%rsp),%xmm0
 1042e19:	00 00
 1042e1b:	48 8b 8c 24 50 01 00 	mov    0x150(%rsp),%rcx
 1042e22:	00
 1042e23:	4c 8b b4 24 58 01 00 	mov    0x158(%rsp),%r14
 1042e2a:	00
 1042e2b:	48 83 f8 01          	cmp    $0x1,%rax
 1042e2f:	0f 85 aa 00 00 00    	jne    1042edf <my.json::read_value+0x83f>
 1042e35:	48 8d 3d c4 f3 00 00 	lea    0xf3c4(%rip),%rdi        # 1052200 <core_io_file_error.verbs+0x560>
 1042e3c:	e9 82 0d 00 00       	jmp    1043bc3 <my.json::read_value+0x1523>
 1042e41:	48 8d 0d 38 54 fc ff 	lea    -0x3abc8(%rip),%rcx        # 1008280 <core_number_pairs+0x18b0>
 1042e48:	48 8d bc 24 10 01 00 	lea    0x110(%rsp),%rdi
 1042e4f:	00
 1042e50:	4c 89 e6             	mov    %r12,%rsi
 1042e53:	45 31 c0             	xor    %r8d,%r8d
 1042e56:	45 31 c9             	xor    %r9d,%r9d
 1042e59:	e8 e2 28 00 00       	call   1045740 <my.json::read_literal>
 1042e5e:	0f b6 84 24 10 01 00 	movzbl 0x110(%rsp),%eax
 1042e65:	00
 1042e66:	c5 fa 6f 84 24 18 01 	vmovdqu 0x118(%rsp),%xmm0
 1042e6d:	00 00
 1042e6f:	48 8b 8c 24 28 01 00 	mov    0x128(%rsp),%rcx
 1042e76:	00
 1042e77:	4c 8b b4 24 30 01 00 	mov    0x130(%rsp),%r14
 1042e7e:	00
 1042e7f:	48 83 f8 01          	cmp    $0x1,%rax
 1042e83:	75 5a                	jne    1042edf <my.json::read_value+0x83f>
 1042e85:	48 8d 3d a4 f3 00 00 	lea    0xf3a4(%rip),%rdi        # 1052230 <core_io_file_error.verbs+0x590>
 1042e8c:	e9 32 0d 00 00       	jmp    1043bc3 <my.json::read_value+0x1523>
 1042e91:	48 8d 0d 68 53 fc ff 	lea    -0x3ac98(%rip),%rcx        # 1008200 <core_number_pairs+0x1830>
 1042e98:	48 8d bc 24 60 01 00 	lea    0x160(%rsp),%rdi
 1042e9f:	00
 1042ea0:	41 b9 01 00 00 00    	mov    $0x1,%r9d
 1042ea6:	4c 89 e6             	mov    %r12,%rsi
 1042ea9:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 1042eaf:	e8 8c 28 00 00       	call   1045740 <my.json::read_literal>
 1042eb4:	0f b6 84 24 60 01 00 	movzbl 0x160(%rsp),%eax
 1042ebb:	00
 1042ebc:	c5 fa 6f 84 24 68 01 	vmovdqu 0x168(%rsp),%xmm0
 1042ec3:	00 00
 1042ec5:	48 8b 8c 24 78 01 00 	mov    0x178(%rsp),%rcx
 1042ecc:	00
 1042ecd:	4c 8b b4 24 80 01 00 	mov    0x180(%rsp),%r14
 1042ed4:	00
 1042ed5:	48 83 f8 01          	cmp    $0x1,%rax
 1042ed9:	0f 84 dd 0c 00 00    	je     1043bbc <my.json::read_value+0x151c>
 1042edf:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 1042ee4:	48 89 02             	mov    %rax,(%rdx)
 1042ee7:	48 89 d0             	mov    %rdx,%rax
 1042eea:	c5 fa 7f 42 08       	vmovdqu %xmm0,0x8(%rdx)
 1042eef:	48 89 4a 18          	mov    %rcx,0x18(%rdx)
 1042ef3:	e9 e5 13 00 00       	jmp    10442dd <my.json::read_value+0x1c3d>
 1042ef8:	4c 89 d3             	mov    %r10,%rbx
 1042efb:	4d 8d 7a 01          	lea    0x1(%r10),%r15
 1042eff:	48 8d 35 52 fc 00 00 	lea    0xfc52(%rip),%rsi        # 1052b58 <core_io_file_error.verbs+0xeb8>
 1042f06:	31 ff                	xor    %edi,%edi
 1042f08:	e8 f3 77 fd ff       	call   101a700 <myl_core_dict_new>
 1042f0d:	48 89 c5             	mov    %rax,%rbp
 1042f10:	49 8b 55 08          	mov    0x8(%r13),%rdx
 1042f14:	49 39 d7             	cmp    %rdx,%r15
 1042f17:	7d 71                	jge    1042f8a <my.json::read_value+0x8ea>
 1042f19:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 1042f20:	00 00 00
 1042f23:	48 89 d9             	mov    %rbx,%rcx
 1042f26:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042f2d:	0f 1f 84 00 00 00 00
 1042f34:	00
 1042f35:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 1042f3c:	00 00 00 00
 1042f40:	48 8d 71 01          	lea    0x1(%rcx),%rsi
 1042f44:	48 89 f7             	mov    %rsi,%rdi
 1042f47:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1042f4b:	48 21 d7             	and    %rdx,%rdi
 1042f4e:	4c 8d 04 39          	lea    (%rcx,%rdi,1),%r8
 1042f52:	49 ff c0             	inc    %r8
 1042f55:	49 39 d0             	cmp    %rdx,%r8
 1042f58:	0f 83 95 15 00 00    	jae    10444f3 <my.json::read_value+0x1e53>
 1042f5e:	49 01 fd             	add    %rdi,%r13
 1042f61:	42 0f b6 54 29 21    	movzbl 0x21(%rcx,%r13,1),%edx
 1042f67:	48 83 fa 20          	cmp    $0x20,%rdx
 1042f6b:	77 1d                	ja     1042f8a <my.json::read_value+0x8ea>
 1042f6d:	48 0f a3 d0          	bt     %rdx,%rax
 1042f71:	73 17                	jae    1042f8a <my.json::read_value+0x8ea>
 1042f73:	49 89 cf             	mov    %rcx,%r15
 1042f76:	49 83 c7 02          	add    $0x2,%r15
 1042f7a:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042f7f:	48 89 f1             	mov    %rsi,%rcx
 1042f82:	4d 89 e5             	mov    %r12,%r13
 1042f85:	49 39 d7             	cmp    %rdx,%r15
 1042f88:	7c b6                	jl     1042f40 <my.json::read_value+0x8a0>
 1042f8a:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1042f8f:	49 39 d7             	cmp    %rdx,%r15
 1042f92:	0f 8d 5f 0b 00 00    	jge    1043af7 <my.json::read_value+0x1457>
 1042f98:	4c 89 f8             	mov    %r15,%rax
 1042f9b:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042f9f:	48 21 d0             	and    %rdx,%rax
 1042fa2:	4c 01 f8             	add    %r15,%rax
 1042fa5:	48 39 d0             	cmp    %rdx,%rax
 1042fa8:	0f 83 5a 16 00 00    	jae    1044608 <my.json::read_value+0x1f68>
 1042fae:	41 80 7c 04 20 7d    	cmpb   $0x7d,0x20(%r12,%rax,1)
 1042fb4:	0f 84 b2 0a 00 00    	je     1043a6c <my.json::read_value+0x13cc>
 1042fba:	48 ff 44 24 58       	incq   0x58(%rsp)
 1042fbf:	49 bd 00 26 00 00 01 	movabs $0x100002600,%r13
 1042fc6:	00 00 00
 1042fc9:	4d 89 e6             	mov    %r12,%r14
 1042fcc:	0f 1f 40 00          	nopl   0x0(%rax)
 1042fd0:	49 39 d7             	cmp    %rdx,%r15
 1042fd3:	7d 38                	jge    104300d <my.json::read_value+0x96d>
 1042fd5:	4c 89 f8             	mov    %r15,%rax
 1042fd8:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042fdc:	48 21 d0             	and    %rdx,%rax
 1042fdf:	4a 8d 0c 38          	lea    (%rax,%r15,1),%rcx
 1042fe3:	48 39 d1             	cmp    %rdx,%rcx
 1042fe6:	0f 83 68 14 00 00    	jae    1044454 <my.json::read_value+0x1db4>
 1042fec:	49 01 c4             	add    %rax,%r12
 1042fef:	43 0f b6 44 27 20    	movzbl 0x20(%r15,%r12,1),%eax
 1042ff5:	48 83 f8 20          	cmp    $0x20,%rax
 1042ff9:	77 12                	ja     104300d <my.json::read_value+0x96d>
 1042ffb:	49 0f a3 c5          	bt     %rax,%r13
 1042fff:	73 0c                	jae    104300d <my.json::read_value+0x96d>
 1043001:	49 ff c7             	inc    %r15
 1043004:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1043008:	4d 89 f4             	mov    %r14,%r12
 104300b:	eb c3                	jmp    1042fd0 <my.json::read_value+0x930>
 104300d:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1043011:	49 39 d7             	cmp    %rdx,%r15
 1043014:	0f 8d 9e 0d 00 00    	jge    1043db8 <my.json::read_value+0x1718>
 104301a:	4c 89 f8             	mov    %r15,%rax
 104301d:	48 c1 f8 3f          	sar    $0x3f,%rax
 1043021:	48 21 d0             	and    %rdx,%rax
 1043024:	4c 01 f8             	add    %r15,%rax
 1043027:	48 39 d0             	cmp    %rdx,%rax
 104302a:	0f 83 3f 15 00 00    	jae    104456f <my.json::read_value+0x1ecf>
 1043030:	41 80 7c 06 20 22    	cmpb   $0x22,0x20(%r14,%rax,1)
 1043036:	0f 85 7c 0d 00 00    	jne    1043db8 <my.json::read_value+0x1718>
 104303c:	48 8d bc 24 c0 00 00 	lea    0xc0(%rsp),%rdi
 1043043:	00
 1043044:	4c 89 f6             	mov    %r14,%rsi
 1043047:	4c 89 fa             	mov    %r15,%rdx
 104304a:	e8 81 1a 00 00       	call   1044ad0 <my.json::read_string>
 104304f:	48 8b bc 24 c8 00 00 	mov    0xc8(%rsp),%rdi
 1043056:	00
 1043057:	4c 8b bc 24 d8 00 00 	mov    0xd8(%rsp),%r15
 104305e:	00
 104305f:	4c 8b b4 24 d0 00 00 	mov    0xd0(%rsp),%r14
 1043066:	00
 1043067:	0f b6 84 24 c0 00 00 	movzbl 0xc0(%rsp),%eax
 104306e:	00
 104306f:	3c 01                	cmp    $0x1,%al
 1043071:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 1043076:	0f 84 e5 10 00 00    	je     1044161 <my.json::read_value+0x1ac1>
 104307c:	48 89 7c 24 70       	mov    %rdi,0x70(%rsp)
 1043081:	f6 47 05 02          	testb  $0x2,0x5(%rdi)
 1043085:	88 44 24 07          	mov    %al,0x7(%rsp)
 1043089:	75 07                	jne    1043092 <my.json::read_value+0x9f2>
 104308b:	e8 f0 8a fd ff       	call   101bb80 <myl_core_str_hash>
 1043090:	eb 03                	jmp    1043095 <my.json::read_value+0x9f5>
 1043092:	8b 47 18             	mov    0x18(%rdi),%eax
 1043095:	89 c0                	mov    %eax,%eax
 1043097:	48 b9 15 7c 4a 7f b9 	movabs $0x9e3779b97f4a7c15,%rcx
 104309e:	79 37 9e
 10430a1:	48 0f af c1          	imul   %rcx,%rax
 10430a5:	48 89 c6             	mov    %rax,%rsi
 10430a8:	48 c1 ee 20          	shr    $0x20,%rsi
 10430ac:	48 31 c6             	xor    %rax,%rsi
 10430af:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 10430b4:	48 8b 4d 18          	mov    0x18(%rbp),%rcx
 10430b8:	48 8b 41 08          	mov    0x8(%rcx),%rax
 10430bc:	48 85 c0             	test   %rax,%rax
 10430bf:	48 89 74 24 08       	mov    %rsi,0x8(%rsp)
 10430c4:	0f 84 c2 00 00 00    	je     104318c <my.json::read_value+0xaec>
 10430ca:	8b 08                	mov    (%rax),%ecx
 10430cc:	f3 0f bc d1          	tzcnt  %ecx,%edx
 10430d0:	f6 da                	neg    %dl
 10430d2:	c4 62 eb f7 ee       	shrx   %rdx,%rsi,%r13
 10430d7:	c4 a1 7a 6f 4c 28 10 	vmovdqu 0x10(%rax,%r13,1),%xmm1
 10430de:	89 f2                	mov    %esi,%edx
 10430e0:	80 e2 7f             	and    $0x7f,%dl
 10430e3:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 10430e7:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10430ec:	c5 f9 7f 4c 24 40    	vmovdqa %xmm1,0x40(%rsp)
 10430f2:	c5 f1 74 c0          	vpcmpeqb %xmm0,%xmm1,%xmm0
 10430f6:	c5 f9 d7 d0          	vpmovmskb %xmm0,%edx
 10430fa:	85 d2                	test   %edx,%edx
 10430fc:	74 76                	je     1043174 <my.json::read_value+0xad4>
 10430fe:	8d 69 ff             	lea    -0x1(%rcx),%ebp
 1043101:	83 c1 1e             	add    $0x1e,%ecx
 1043104:	83 e1 f0             	and    $0xfffffff0,%ecx
 1043107:	48 8d 1c 08          	lea    (%rax,%rcx,1),%rbx
 104310b:	48 83 c3 10          	add    $0x10,%rbx
 104310f:	44 0f b7 e2          	movzwl %dx,%r12d
 1043113:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104311a:	0f 1f 84 00 00 00 00
 1043121:	00
 1043122:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043129:	0f 1f 84 00 00 00 00
 1043130:	00
 1043131:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043138:	0f 1f 84 00 00 00 00
 104313f:	00
 1043140:	f3 41 0f bc c4       	tzcnt  %r12d,%eax
 1043145:	44 01 e8             	add    %r13d,%eax
 1043148:	21 e8                	and    %ebp,%eax
 104314a:	8b 04 83             	mov    (%rbx,%rax,4),%eax
 104314d:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 1043151:	48 8b 4c 24 20       	mov    0x20(%rsp),%rcx
 1043156:	48 8b 7c c1 20       	mov    0x20(%rcx,%rax,8),%rdi
 104315b:	48 8b 74 24 70       	mov    0x70(%rsp),%rsi
 1043160:	e8 9b 8b fd ff       	call   101bd00 <myl_core_str_eq>
 1043165:	84 c0                	test   %al,%al
 1043167:	0f 85 0e 09 00 00    	jne    1043a7b <my.json::read_value+0x13db>
 104316d:	c4 c2 18 f3 cc       	blsr   %r12d,%r12d
 1043172:	75 cc                	jne    1043140 <my.json::read_value+0xaa0>
 1043174:	c5 f9 6f 44 24 40    	vmovdqa 0x40(%rsp),%xmm0
 104317a:	c5 f9 74 05 5e 0c fc 	vpcmpeqb -0x3f3a2(%rip),%xmm0,%xmm0        # 1003de0 <__anon_2214+0x50>
 1043181:	ff
 1043182:	c5 f9 d7 c0          	vpmovmskb %xmm0,%eax
 1043186:	85 c0                	test   %eax,%eax
 1043188:	75 2d                	jne    10431b7 <my.json::read_value+0xb17>
 104318a:	eb 0b                	jmp    1043197 <my.json::read_value+0xaf7>
 104318c:	48 83 79 18 00       	cmpq   $0x0,0x18(%rcx)
 1043191:	0f 84 f5 03 00 00    	je     104358c <my.json::read_value+0xeec>
 1043197:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 104319c:	48 8d 74 24 70       	lea    0x70(%rsp),%rsi
 10431a1:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 10431a6:	e8 95 71 fd ff       	call   101a340 <myl_core_dict_find>
 10431ab:	49 89 c5             	mov    %rax,%r13
 10431ae:	4d 85 ed             	test   %r13,%r13
 10431b1:	0f 89 c4 08 00 00    	jns    1043a7b <my.json::read_value+0x13db>
 10431b7:	49 8b 56 08          	mov    0x8(%r14),%rdx
 10431bb:	49 39 d7             	cmp    %rdx,%r15
 10431be:	0f 8d 76 00 00 00    	jge    104323a <my.json::read_value+0xb9a>
 10431c4:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 10431c9:	48 be 00 26 00 00 01 	movabs $0x100002600,%rsi
 10431d0:	00 00 00
 10431d3:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10431da:	0f 1f 84 00 00 00 00
 10431e1:	00
 10431e2:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10431e9:	0f 1f 84 00 00 00 00
 10431f0:	00
 10431f1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10431f8:	0f 1f 84 00 00 00 00
 10431ff:	00
 1043200:	4c 89 f8             	mov    %r15,%rax
 1043203:	48 c1 f8 3f          	sar    $0x3f,%rax
 1043207:	48 21 d0             	and    %rdx,%rax
 104320a:	4a 8d 0c 38          	lea    (%rax,%r15,1),%rcx
 104320e:	48 39 d1             	cmp    %rdx,%rcx
 1043211:	0f 83 4c 12 00 00    	jae    1044463 <my.json::read_value+0x1dc3>
 1043217:	4c 01 f0             	add    %r14,%rax
 104321a:	41 0f b6 44 07 20    	movzbl 0x20(%r15,%rax,1),%eax
 1043220:	48 83 f8 20          	cmp    $0x20,%rax
 1043224:	77 19                	ja     104323f <my.json::read_value+0xb9f>
 1043226:	48 0f a3 c6          	bt     %rax,%rsi
 104322a:	73 13                	jae    104323f <my.json::read_value+0xb9f>
 104322c:	49 ff c7             	inc    %r15
 104322f:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1043233:	49 39 d7             	cmp    %rdx,%r15
 1043236:	7c c8                	jl     1043200 <my.json::read_value+0xb60>
 1043238:	eb 05                	jmp    104323f <my.json::read_value+0xb9f>
 104323a:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 104323f:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1043243:	49 39 d7             	cmp    %rdx,%r15
 1043246:	0f 8d 8f 0b 00 00    	jge    1043ddb <my.json::read_value+0x173b>
 104324c:	4c 89 f8             	mov    %r15,%rax
 104324f:	48 c1 f8 3f          	sar    $0x3f,%rax
 1043253:	48 21 d0             	and    %rdx,%rax
 1043256:	4c 01 f8             	add    %r15,%rax
 1043259:	48 39 d0             	cmp    %rdx,%rax
 104325c:	0f 83 1c 13 00 00    	jae    104457e <my.json::read_value+0x1ede>
 1043262:	41 80 7c 06 20 3a    	cmpb   $0x3a,0x20(%r14,%rax,1)
 1043268:	0f 85 6d 0b 00 00    	jne    1043ddb <my.json::read_value+0x173b>
 104326e:	49 ff c7             	inc    %r15
 1043271:	48 8d 7c 24 78       	lea    0x78(%rsp),%rdi
 1043276:	4c 89 f6             	mov    %r14,%rsi
 1043279:	4c 89 fa             	mov    %r15,%rdx
 104327c:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 1043281:	e8 1a f4 ff ff       	call   10426a0 <my.json::read_value>
 1043286:	48 8b 4c 24 78       	mov    0x78(%rsp),%rcx
 104328b:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 1043292:	00
 1043293:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 1043298:	0f b6 c1             	movzbl %cl,%eax
 104329b:	4c 8b b4 24 90 00 00 	mov    0x90(%rsp),%r14
 10432a2:	00
 10432a3:	4c 8b bc 24 98 00 00 	mov    0x98(%rsp),%r15
 10432aa:	00
 10432ab:	83 f8 01             	cmp    $0x1,%eax
 10432ae:	0f 84 16 0f 00 00    	je     10441ca <my.json::read_value+0x1b2a>
 10432b4:	48 89 8c 24 a0 00 00 	mov    %rcx,0xa0(%rsp)
 10432bb:	00
 10432bc:	48 8b 84 24 88 00 00 	mov    0x88(%rsp),%rax
 10432c3:	00
 10432c4:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
 10432c9:	83 7d 00 01          	cmpl   $0x1,0x0(%rbp)
 10432cd:	75 0c                	jne    10432db <my.json::read_value+0xc3b>
 10432cf:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 10432d4:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 10432d9:	eb 34                	jmp    104330f <my.json::read_value+0xc6f>
 10432db:	48 89 ef             	mov    %rbp,%rdi
 10432de:	e8 5d 80 fd ff       	call   101b340 <myl_core_dict_copy>
 10432e3:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 10432e8:	8b 45 00             	mov    0x0(%rbp),%eax
 10432eb:	85 c0                	test   %eax,%eax
 10432ed:	78 12                	js     1043301 <my.json::read_value+0xc61>
 10432ef:	ff c8                	dec    %eax
 10432f1:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 10432f6:	0f 84 92 03 00 00    	je     104368e <my.json::read_value+0xfee>
 10432fc:	89 45 00             	mov    %eax,0x0(%rbp)
 10432ff:	eb 0e                	jmp    104330f <my.json::read_value+0xc6f>
 1043301:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043304:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043309:	0f 85 ed 04 00 00    	jne    10437fc <my.json::read_value+0x115c>
 104330f:	48 89 7c 24 68       	mov    %rdi,0x68(%rsp)
 1043314:	f6 47 05 02          	testb  $0x2,0x5(%rdi)
 1043318:	75 07                	jne    1043321 <my.json::read_value+0xc81>
 104331a:	e8 61 88 fd ff       	call   101bb80 <myl_core_str_hash>
 104331f:	eb 03                	jmp    1043324 <my.json::read_value+0xc84>
 1043321:	8b 47 18             	mov    0x18(%rdi),%eax
 1043324:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
 1043329:	89 c0                	mov    %eax,%eax
 104332b:	48 b9 15 7c 4a 7f b9 	movabs $0x9e3779b97f4a7c15,%rcx
 1043332:	79 37 9e
 1043335:	48 0f af c1          	imul   %rcx,%rax
 1043339:	48 89 c2             	mov    %rax,%rdx
 104333c:	48 c1 ea 20          	shr    $0x20,%rdx
 1043340:	48 31 c2             	xor    %rax,%rdx
 1043343:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 1043348:	48 8b 48 18          	mov    0x18(%rax),%rcx
 104334c:	48 8b 41 08          	mov    0x8(%rcx),%rax
 1043350:	48 85 c0             	test   %rax,%rax
 1043353:	0f 84 c4 00 00 00    	je     104341d <my.json::read_value+0xd7d>
 1043359:	8b 08                	mov    (%rax),%ecx
 104335b:	f3 0f bc f1          	tzcnt  %ecx,%esi
 104335f:	40 f6 de             	neg    %sil
 1043362:	c4 e2 cb f7 ea       	shrx   %rsi,%rdx,%rbp
 1043367:	44 8d 69 ff          	lea    -0x1(%rcx),%r13d
 104336b:	c5 fa 6f 4c 28 10    	vmovdqu 0x10(%rax,%rbp,1),%xmm1
 1043371:	48 89 54 24 60       	mov    %rdx,0x60(%rsp)
 1043376:	80 e2 7f             	and    $0x7f,%dl
 1043379:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 104337d:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1043382:	c5 f9 7f 8c 24 00 01 	vmovdqa %xmm1,0x100(%rsp)
 1043389:	00 00
 104338b:	c5 f1 74 c0          	vpcmpeqb %xmm0,%xmm1,%xmm0
 104338f:	c5 f9 d7 d0          	vpmovmskb %xmm0,%edx
 1043393:	85 d2                	test   %edx,%edx
 1043395:	74 5a                	je     10433f1 <my.json::read_value+0xd51>
 1043397:	83 c1 1e             	add    $0x1e,%ecx
 104339a:	83 e1 f0             	and    $0xfffffff0,%ecx
 104339d:	4c 8d 34 08          	lea    (%rax,%rcx,1),%r14
 10433a1:	49 83 c6 10          	add    $0x10,%r14
 10433a5:	44 0f b7 e2          	movzwl %dx,%r12d
 10433a9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10433b0:	0f 1f 84 00 00 00 00
 10433b7:	00
 10433b8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 10433bf:	00
 10433c0:	f3 41 0f bc c4       	tzcnt  %r12d,%eax
 10433c5:	01 e8                	add    %ebp,%eax
 10433c7:	44 21 e8             	and    %r13d,%eax
 10433ca:	41 8b 1c 86          	mov    (%r14,%rax,4),%ebx
 10433ce:	48 8d 04 5b          	lea    (%rbx,%rbx,2),%rax
 10433d2:	48 8b 4c 24 20       	mov    0x20(%rsp),%rcx
 10433d7:	48 8b 7c c1 20       	mov    0x20(%rcx,%rax,8),%rdi
 10433dc:	48 8b 74 24 68       	mov    0x68(%rsp),%rsi
 10433e1:	e8 1a 89 fd ff       	call   101bd00 <myl_core_str_eq>
 10433e6:	84 c0                	test   %al,%al
 10433e8:	75 50                	jne    104343a <my.json::read_value+0xd9a>
 10433ea:	c4 c2 18 f3 cc       	blsr   %r12d,%r12d
 10433ef:	75 cf                	jne    10433c0 <my.json::read_value+0xd20>
 10433f1:	c5 f9 6f 84 24 00 01 	vmovdqa 0x100(%rsp),%xmm0
 10433f8:	00 00
 10433fa:	c5 f9 74 05 de 09 fc 	vpcmpeqb -0x3f622(%rip),%xmm0,%xmm0        # 1003de0 <__anon_2214+0x50>
 1043401:	ff
 1043402:	c5 f9 d7 c0          	vpmovmskb %xmm0,%eax
 1043406:	85 c0                	test   %eax,%eax
 1043408:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 104340d:	74 19                	je     1043428 <my.json::read_value+0xd88>
 104340f:	f3 0f bc d8          	tzcnt  %eax,%ebx
 1043413:	01 eb                	add    %ebp,%ebx
 1043415:	44 21 eb             	and    %r13d,%ebx
 1043418:	48 f7 d3             	not    %rbx
 104341b:	eb 1d                	jmp    104343a <my.json::read_value+0xd9a>
 104341d:	48 83 79 18 00       	cmpq   $0x0,0x18(%rcx)
 1043422:	0f 84 ca 01 00 00    	je     10435f2 <my.json::read_value+0xf52>
 1043428:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 104342d:	48 8d 74 24 68       	lea    0x68(%rsp),%rsi
 1043432:	e8 09 6f fd ff       	call   101a340 <myl_core_dict_find>
 1043437:	48 89 c3             	mov    %rax,%rbx
 104343a:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 104343f:	8b 01                	mov    (%rcx),%eax
 1043441:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043446:	77 1f                	ja     1043467 <my.json::read_value+0xdc7>
 1043448:	ff c0                	inc    %eax
 104344a:	89 01                	mov    %eax,(%rcx)
 104344c:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 1043451:	49 bd 00 26 00 00 01 	movabs $0x100002600,%r13
 1043458:	00 00 00
 104345b:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 1043460:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 1043465:	eb 22                	jmp    1043489 <my.json::read_value+0xde9>
 1043467:	83 f8 ff             	cmp    $0xffffffff,%eax
 104346a:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 104346f:	49 bd 00 26 00 00 01 	movabs $0x100002600,%r13
 1043476:	00 00 00
 1043479:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 104347e:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 1043483:	0f 85 39 03 00 00    	jne    10437c2 <my.json::read_value+0x1122>
 1043489:	44 0f b6 f2          	movzbl %dl,%r14d
 104348d:	41 80 fe 06          	cmp    $0x6,%r14b
 1043491:	74 0c                	je     104349f <my.json::read_value+0xdff>
 1043493:	41 83 fe 05          	cmp    $0x5,%r14d
 1043497:	74 06                	je     104349f <my.json::read_value+0xdff>
 1043499:	41 83 fe 04          	cmp    $0x4,%r14d
 104349d:	75 18                	jne    10434b7 <my.json::read_value+0xe17>
 104349f:	8b 06                	mov    (%rsi),%eax
 10434a1:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 10434a6:	77 06                	ja     10434ae <my.json::read_value+0xe0e>
 10434a8:	ff c0                	inc    %eax
 10434aa:	89 06                	mov    %eax,(%rsi)
 10434ac:	eb 09                	jmp    10434b7 <my.json::read_value+0xe17>
 10434ae:	83 f8 ff             	cmp    $0xffffffff,%eax
 10434b1:	0f 85 27 03 00 00    	jne    10437de <my.json::read_value+0x113e>
 10434b7:	48 89 8c 24 a8 00 00 	mov    %rcx,0xa8(%rsp)
 10434be:	00
 10434bf:	0f b6 c2             	movzbl %dl,%eax
 10434c2:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
 10434c9:	00
 10434ca:	48 89 b4 24 b8 00 00 	mov    %rsi,0xb8(%rsp)
 10434d1:	00
 10434d2:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 10434d7:	48 89 de             	mov    %rbx,%rsi
 10434da:	48 89 cb             	mov    %rcx,%rbx
 10434dd:	48 8d 94 24 a8 00 00 	lea    0xa8(%rsp),%rdx
 10434e4:	00
 10434e5:	48 8d 8c 24 b0 00 00 	lea    0xb0(%rsp),%rcx
 10434ec:	00
 10434ed:	45 31 c0             	xor    %r8d,%r8d
 10434f0:	e8 8b 74 fd ff       	call   101a980 <myl_core_dict_insert>
 10434f5:	48 89 c5             	mov    %rax,%rbp
 10434f8:	80 7c 24 07 00       	cmpb   $0x0,0x7(%rsp)
 10434fd:	74 56                	je     1043555 <my.json::read_value+0xeb5>
 10434ff:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
 1043506:	00
 1043507:	3c 01                	cmp    $0x1,%al
 1043509:	74 63                	je     104356e <my.json::read_value+0xece>
 104350b:	0f b6 c0             	movzbl %al,%eax
 104350e:	85 c0                	test   %eax,%eax
 1043510:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
 1043515:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 104351a:	0f 85 20 02 00 00    	jne    1043740 <my.json::read_value+0x10a0>
 1043520:	3c 06                	cmp    $0x6,%al
 1043522:	0f 84 d3 01 00 00    	je     10436fb <my.json::read_value+0x105b>
 1043528:	41 83 fe 05          	cmp    $0x5,%r14d
 104352c:	0f 84 bb 01 00 00    	je     10436ed <my.json::read_value+0x104d>
 1043532:	41 83 fe 04          	cmp    $0x4,%r14d
 1043536:	0f 85 04 02 00 00    	jne    1043740 <my.json::read_value+0x10a0>
 104353c:	8b 07                	mov    (%rdi),%eax
 104353e:	85 c0                	test   %eax,%eax
 1043540:	0f 88 c3 01 00 00    	js     1043709 <my.json::read_value+0x1069>
 1043546:	ff c8                	dec    %eax
 1043548:	0f 84 c7 01 00 00    	je     1043715 <my.json::read_value+0x1075>
 104354e:	89 07                	mov    %eax,(%rdi)
 1043550:	e9 eb 01 00 00       	jmp    1043740 <my.json::read_value+0x10a0>
 1043555:	8b 03                	mov    (%rbx),%eax
 1043557:	85 c0                	test   %eax,%eax
 1043559:	48 89 df             	mov    %rbx,%rdi
 104355c:	0f 88 19 01 00 00    	js     104367b <my.json::read_value+0xfdb>
 1043562:	ff c8                	dec    %eax
 1043564:	0f 84 54 01 00 00    	je     10436be <my.json::read_value+0x101e>
 104356a:	89 07                	mov    %eax,(%rdi)
 104356c:	eb 91                	jmp    10434ff <my.json::read_value+0xe5f>
 104356e:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1043573:	8b 07                	mov    (%rdi),%eax
 1043575:	85 c0                	test   %eax,%eax
 1043577:	0f 88 8c 01 00 00    	js     1043709 <my.json::read_value+0x1069>
 104357d:	ff c8                	dec    %eax
 104357f:	0f 84 90 01 00 00    	je     1043715 <my.json::read_value+0x1075>
 1043585:	89 07                	mov    %eax,(%rdi)
 1043587:	e9 b4 01 00 00       	jmp    1043740 <my.json::read_value+0x10a0>
 104358c:	4c 8b 61 20          	mov    0x20(%rcx),%r12
 1043590:	4d 85 e4             	test   %r12,%r12
 1043593:	0f 84 1e fc ff ff    	je     10431b7 <my.json::read_value+0xb17>
 1043599:	48 8b 59 10          	mov    0x10(%rcx),%rbx
 104359d:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 10435a2:	48 8d 68 20          	lea    0x20(%rax),%rbp
 10435a6:	45 31 ed             	xor    %r13d,%r13d
 10435a9:	eb 25                	jmp    10435d0 <my.json::read_value+0xf30>
 10435ab:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10435b2:	0f 1f 84 00 00 00 00
 10435b9:	00
 10435ba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 10435c0:	49 ff c5             	inc    %r13
 10435c3:	48 83 c5 18          	add    $0x18,%rbp
 10435c7:	4d 39 ec             	cmp    %r13,%r12
 10435ca:	0f 84 e7 fb ff ff    	je     10431b7 <my.json::read_value+0xb17>
 10435d0:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
 10435d5:	4a 39 04 eb          	cmp    %rax,(%rbx,%r13,8)
 10435d9:	75 e5                	jne    10435c0 <my.json::read_value+0xf20>
 10435db:	48 8b 7d 00          	mov    0x0(%rbp),%rdi
 10435df:	48 8b 74 24 70       	mov    0x70(%rsp),%rsi
 10435e4:	e8 17 87 fd ff       	call   101bd00 <myl_core_str_eq>
 10435e9:	84 c0                	test   %al,%al
 10435eb:	74 d3                	je     10435c0 <my.json::read_value+0xf20>
 10435ed:	e9 bc fb ff ff       	jmp    10431ae <my.json::read_value+0xb0e>
 10435f2:	48 8b 71 20          	mov    0x20(%rcx),%rsi
 10435f6:	48 c7 c3 ff ff ff ff 	mov    $0xffffffffffffffff,%rbx
 10435fd:	48 85 f6             	test   %rsi,%rsi
 1043600:	0f 84 34 fe ff ff    	je     104343a <my.json::read_value+0xd9a>
 1043606:	4c 8b 71 10          	mov    0x10(%rcx),%r14
 104360a:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 104360f:	4c 8d 60 20          	lea    0x20(%rax),%r12
 1043613:	31 ed                	xor    %ebp,%ebp
 1043615:	48 89 74 24 60       	mov    %rsi,0x60(%rsp)
 104361a:	eb 34                	jmp    1043650 <my.json::read_value+0xfb0>
 104361c:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043623:	0f 1f 84 00 00 00 00
 104362a:	00
 104362b:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043632:	0f 1f 84 00 00 00 00
 1043639:	00
 104363a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1043640:	48 ff c5             	inc    %rbp
 1043643:	49 83 c4 18          	add    $0x18,%r12
 1043647:	48 39 ee             	cmp    %rbp,%rsi
 104364a:	0f 84 ea fd ff ff    	je     104343a <my.json::read_value+0xd9a>
 1043650:	49 39 14 ee          	cmp    %rdx,(%r14,%rbp,8)
 1043654:	75 ea                	jne    1043640 <my.json::read_value+0xfa0>
 1043656:	49 8b 3c 24          	mov    (%r12),%rdi
 104365a:	48 8b 74 24 68       	mov    0x68(%rsp),%rsi
 104365f:	49 89 d5             	mov    %rdx,%r13
 1043662:	e8 99 86 fd ff       	call   101bd00 <myl_core_str_eq>
 1043667:	48 8b 74 24 60       	mov    0x60(%rsp),%rsi
 104366c:	4c 89 ea             	mov    %r13,%rdx
 104366f:	84 c0                	test   %al,%al
 1043671:	74 cd                	je     1043640 <my.json::read_value+0xfa0>
 1043673:	48 89 eb             	mov    %rbp,%rbx
 1043676:	e9 bf fd ff ff       	jmp    104343a <my.json::read_value+0xd9a>
 104367b:	83 f8 ff             	cmp    $0xffffffff,%eax
 104367e:	0f 84 7b fe ff ff    	je     10434ff <my.json::read_value+0xe5f>
 1043684:	e8 b7 d4 ff ff       	call   1040b40 <myl_core_release_slow>
 1043689:	e9 71 fe ff ff       	jmp    10434ff <my.json::read_value+0xe5f>
 104368e:	0f b6 45 07          	movzbl 0x7(%rbp),%eax
 1043692:	48 85 c0             	test   %rax,%rax
 1043695:	0f 84 78 01 00 00    	je     1043813 <my.json::read_value+0x1173>
 104369b:	48 83 7d 18 00       	cmpq   $0x0,0x18(%rbp)
 10436a0:	0f 85 6d 01 00 00    	jne    1043813 <my.json::read_value+0x1173>
 10436a6:	48 8d 15 a3 41 03 00 	lea    0x341a3(%rip),%rdx        # 1077850 <myl_core_free_lists>
 10436ad:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 10436b1:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 10436b5:	48 89 2c c2          	mov    %rbp,(%rdx,%rax,8)
 10436b9:	e9 16 fc ff ff       	jmp    10432d4 <my.json::read_value+0xc34>
 10436be:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 10436c2:	48 85 c0             	test   %rax,%rax
 10436c5:	0f 84 55 01 00 00    	je     1043820 <my.json::read_value+0x1180>
 10436cb:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 10436d0:	0f 85 4a 01 00 00    	jne    1043820 <my.json::read_value+0x1180>
 10436d6:	48 8d 15 73 41 03 00 	lea    0x34173(%rip),%rdx        # 1077850 <myl_core_free_lists>
 10436dd:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 10436e1:	48 89 0f             	mov    %rcx,(%rdi)
 10436e4:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 10436e8:	e9 12 fe ff ff       	jmp    10434ff <my.json::read_value+0xe5f>
 10436ed:	8b 07                	mov    (%rdi),%eax
 10436ef:	85 c0                	test   %eax,%eax
 10436f1:	78 16                	js     1043709 <my.json::read_value+0x1069>
 10436f3:	ff c8                	dec    %eax
 10436f5:	74 1e                	je     1043715 <my.json::read_value+0x1075>
 10436f7:	89 07                	mov    %eax,(%rdi)
 10436f9:	eb 45                	jmp    1043740 <my.json::read_value+0x10a0>
 10436fb:	8b 07                	mov    (%rdi),%eax
 10436fd:	85 c0                	test   %eax,%eax
 10436ff:	78 08                	js     1043709 <my.json::read_value+0x1069>
 1043701:	ff c8                	dec    %eax
 1043703:	74 10                	je     1043715 <my.json::read_value+0x1075>
 1043705:	89 07                	mov    %eax,(%rdi)
 1043707:	eb 37                	jmp    1043740 <my.json::read_value+0x10a0>
 1043709:	83 f8 ff             	cmp    $0xffffffff,%eax
 104370c:	74 32                	je     1043740 <my.json::read_value+0x10a0>
 104370e:	e8 2d d4 ff ff       	call   1040b40 <myl_core_release_slow>
 1043713:	eb 2b                	jmp    1043740 <my.json::read_value+0x10a0>
 1043715:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1043719:	48 85 c0             	test   %rax,%rax
 104371c:	0f 84 e7 00 00 00    	je     1043809 <my.json::read_value+0x1169>
 1043722:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 1043727:	0f 85 dc 00 00 00    	jne    1043809 <my.json::read_value+0x1169>
 104372d:	48 8d 15 1c 41 03 00 	lea    0x3411c(%rip),%rdx        # 1077850 <myl_core_free_lists>
 1043734:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043738:	48 89 0f             	mov    %rcx,(%rdi)
 104373b:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 104373f:	90                   	nop
 1043740:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1043745:	49 39 d7             	cmp    %rdx,%r15
 1043748:	7d 31                	jge    104377b <my.json::read_value+0x10db>
 104374a:	4c 89 f8             	mov    %r15,%rax
 104374d:	48 c1 f8 3f          	sar    $0x3f,%rax
 1043751:	48 21 d0             	and    %rdx,%rax
 1043754:	4a 8d 0c 38          	lea    (%rax,%r15,1),%rcx
 1043758:	48 39 d1             	cmp    %rdx,%rcx
 104375b:	0f 83 11 0d 00 00    	jae    1044472 <my.json::read_value+0x1dd2>
 1043761:	4c 01 e0             	add    %r12,%rax
 1043764:	41 0f b6 44 07 20    	movzbl 0x20(%r15,%rax,1),%eax
 104376a:	48 83 f8 20          	cmp    $0x20,%rax
 104376e:	77 0b                	ja     104377b <my.json::read_value+0x10db>
 1043770:	49 0f a3 c5          	bt     %rax,%r13
 1043774:	73 05                	jae    104377b <my.json::read_value+0x10db>
 1043776:	49 ff c7             	inc    %r15
 1043779:	eb c5                	jmp    1043740 <my.json::read_value+0x10a0>
 104377b:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1043780:	49 39 d7             	cmp    %rdx,%r15
 1043783:	0f 8d c7 06 00 00    	jge    1043e50 <my.json::read_value+0x17b0>
 1043789:	4c 89 f8             	mov    %r15,%rax
 104378c:	48 c1 f8 3f          	sar    $0x3f,%rax
 1043790:	48 21 d0             	and    %rdx,%rax
 1043793:	4c 01 f8             	add    %r15,%rax
 1043796:	48 39 d0             	cmp    %rdx,%rax
 1043799:	0f 83 ee 0d 00 00    	jae    104458d <my.json::read_value+0x1eed>
 104379f:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 10437a5:	83 f8 2c             	cmp    $0x2c,%eax
 10437a8:	0f 85 b5 02 00 00    	jne    1043a63 <my.json::read_value+0x13c3>
 10437ae:	49 ff c7             	inc    %r15
 10437b1:	4d 89 e6             	mov    %r12,%r14
 10437b4:	49 39 d7             	cmp    %rdx,%r15
 10437b7:	0f 8c 13 f8 ff ff    	jl     1042fd0 <my.json::read_value+0x930>
 10437bd:	e9 35 03 00 00       	jmp    1043af7 <my.json::read_value+0x1457>
 10437c2:	48 89 cf             	mov    %rcx,%rdi
 10437c5:	e8 36 d3 ff ff       	call   1040b00 <myl_core_retain_slow>
 10437ca:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 10437cf:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 10437d4:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 10437d9:	e9 ab fc ff ff       	jmp    1043489 <my.json::read_value+0xde9>
 10437de:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 10437e3:	e8 18 d3 ff ff       	call   1040b00 <myl_core_retain_slow>
 10437e8:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 10437ed:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 10437f2:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 10437f7:	e9 bb fc ff ff       	jmp    10434b7 <my.json::read_value+0xe17>
 10437fc:	48 89 ef             	mov    %rbp,%rdi
 10437ff:	e8 3c d3 ff ff       	call   1040b40 <myl_core_release_slow>
 1043804:	e9 cb fa ff ff       	jmp    10432d4 <my.json::read_value+0xc34>
 1043809:	e8 b2 d3 ff ff       	call   1040bc0 <myl_core_free_block>
 104380e:	e9 2d ff ff ff       	jmp    1043740 <my.json::read_value+0x10a0>
 1043813:	48 89 ef             	mov    %rbp,%rdi
 1043816:	e8 a5 d3 ff ff       	call   1040bc0 <myl_core_free_block>
 104381b:	e9 b4 fa ff ff       	jmp    10432d4 <my.json::read_value+0xc34>
 1043820:	e8 9b d3 ff ff       	call   1040bc0 <myl_core_free_block>
 1043825:	e9 d5 fc ff ff       	jmp    10434ff <my.json::read_value+0xe5f>
 104382a:	bb 01 00 00 00       	mov    $0x1,%ebx
 104382f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043836:	0f 1f 84 00 00 00 00
 104383d:	00
 104383e:	66 90                	xchg   %ax,%ax
 1043840:	4c 89 f6             	mov    %r14,%rsi
 1043843:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1043847:	48 21 c6             	and    %rax,%rsi
 104384a:	4a 8d 3c 36          	lea    (%rsi,%r14,1),%rdi
 104384e:	48 39 c7             	cmp    %rax,%rdi
 1043851:	0f 83 7b 0c 00 00    	jae    10444d2 <my.json::read_value+0x1e32>
 1043857:	49 01 f5             	add    %rsi,%r13
 104385a:	43 0f b6 44 2e 20    	movzbl 0x20(%r14,%r13,1),%eax
 1043860:	04 d0                	add    $0xd0,%al
 1043862:	3c 0a                	cmp    $0xa,%al
 1043864:	0f 83 f6 00 00 00    	jae    1043960 <my.json::read_value+0x12c0>
 104386a:	49 ff c6             	inc    %r14
 104386d:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 1043872:	4d 89 e5             	mov    %r12,%r13
 1043875:	4c 89 f2             	mov    %r14,%rdx
 1043878:	49 39 c6             	cmp    %rax,%r14
 104387b:	7c c3                	jl     1043840 <my.json::read_value+0x11a0>
 104387d:	31 c0                	xor    %eax,%eax
 104387f:	3c 01                	cmp    $0x1,%al
 1043881:	0f 85 39 f3 ff ff    	jne    1042bc0 <my.json::read_value+0x520>
 1043887:	e9 e1 00 00 00       	jmp    104396d <my.json::read_value+0x12cd>
 104388c:	48 8d bc 24 e0 00 00 	lea    0xe0(%rsp),%rdi
 1043893:	00
 1043894:	4c 89 e6             	mov    %r12,%rsi
 1043897:	e8 34 12 00 00       	call   1044ad0 <my.json::read_string>
 104389c:	48 8b 9c 24 e8 00 00 	mov    0xe8(%rsp),%rbx
 10438a3:	00
 10438a4:	4c 8b b4 24 f8 00 00 	mov    0xf8(%rsp),%r14
 10438ab:	00
 10438ac:	4c 8b bc 24 f0 00 00 	mov    0xf0(%rsp),%r15
 10438b3:	00
 10438b4:	0f b6 ac 24 e0 00 00 	movzbl 0xe0(%rsp),%ebp
 10438bb:	00
 10438bc:	40 80 fd 01          	cmp    $0x1,%bpl
 10438c0:	0f 84 12 04 00 00    	je     1043cd8 <my.json::read_value+0x1638>
 10438c6:	8b 03                	mov    (%rbx),%eax
 10438c8:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 10438cd:	0f 87 21 01 00 00    	ja     10439f4 <my.json::read_value+0x1354>
 10438d3:	ff c0                	inc    %eax
 10438d5:	89 03                	mov    %eax,(%rbx)
 10438d7:	40 84 ed             	test   %bpl,%bpl
 10438da:	0f 85 26 01 00 00    	jne    1043a06 <my.json::read_value+0x1366>
 10438e0:	e9 13 07 00 00       	jmp    1043ff8 <my.json::read_value+0x1958>
 10438e5:	48 8d 15 b4 48 fc ff 	lea    -0x3b74c(%rip),%rdx        # 10081a0 <core_number_pairs+0x17d0>
 10438ec:	48 89 fb             	mov    %rdi,%rbx
 10438ef:	4c 89 e7             	mov    %r12,%rdi
 10438f2:	4c 89 d6             	mov    %r10,%rsi
 10438f5:	4d 89 d6             	mov    %r10,%r14
 10438f8:	e8 83 0d 00 00       	call   1044680 <my.json::fail>
 10438fd:	48 8d 3d 0c e8 00 00 	lea    0xe80c(%rip),%rdi        # 1052110 <core_io_file_error.verbs+0x470>
 1043904:	e8 77 d6 ff ff       	call   1040f80 <myl_core_err_trace_origin_preserve_most>
 1043909:	48 c7 03 01 00 00 00 	movq   $0x1,(%rbx)
 1043910:	48 89 43 08          	mov    %rax,0x8(%rbx)
 1043914:	48 89 d8             	mov    %rbx,%rax
 1043917:	4c 89 63 18          	mov    %r12,0x18(%rbx)
 104391b:	e9 bd 09 00 00       	jmp    10442dd <my.json::read_value+0x1c3d>
 1043920:	48 8d 05 99 49 fc ff 	lea    -0x3b667(%rip),%rax        # 10082c0 <core_number_pairs+0x18f0>
 1043927:	4c 89 e7             	mov    %r12,%rdi
 104392a:	48 89 d6             	mov    %rdx,%rsi
 104392d:	4d 89 d6             	mov    %r10,%r14
 1043930:	48 89 c2             	mov    %rax,%rdx
 1043933:	e8 48 0d 00 00       	call   1044680 <my.json::fail>
 1043938:	48 8d 3d 51 e9 00 00 	lea    0xe951(%rip),%rdi        # 1052290 <core_io_file_error.verbs+0x5f0>
 104393f:	e8 3c d6 ff ff       	call   1040f80 <myl_core_err_trace_origin_preserve_most>
 1043944:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 1043949:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 1043950:	48 89 41 08          	mov    %rax,0x8(%rcx)
 1043954:	48 89 c8             	mov    %rcx,%rax
 1043957:	4c 89 69 18          	mov    %r13,0x18(%rcx)
 104395b:	e9 7d 09 00 00       	jmp    10442dd <my.json::read_value+0x1c3d>
 1043960:	31 c0                	xor    %eax,%eax
 1043962:	49 89 d6             	mov    %rdx,%r14
 1043965:	3c 01                	cmp    $0x1,%al
 1043967:	0f 85 53 f2 ff ff    	jne    1042bc0 <my.json::read_value+0x520>
 104396d:	48 8d 3d ac ec 00 00 	lea    0xecac(%rip),%rdi        # 1052620 <core_io_file_error.verbs+0x980>
 1043974:	e8 47 d6 ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 1043979:	8b 03                	mov    (%rbx),%eax
 104397b:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043980:	0f 87 53 02 00 00    	ja     1043bd9 <my.json::read_value+0x1539>
 1043986:	ff c0                	inc    %eax
 1043988:	89 03                	mov    %eax,(%rbx)
 104398a:	ff c8                	dec    %eax
 104398c:	0f 85 23 02 00 00    	jne    1043bb5 <my.json::read_value+0x1515>
 1043992:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043996:	48 85 c0             	test   %rax,%rax
 1043999:	0f 84 f9 0a 00 00    	je     1044498 <my.json::read_value+0x1df8>
 104399f:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 10439a4:	0f 85 ee 0a 00 00    	jne    1044498 <my.json::read_value+0x1df8>
 10439aa:	48 8d 0d 9f 3e 03 00 	lea    0x33e9f(%rip),%rcx        # 1077850 <myl_core_free_lists>
 10439b1:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 10439b5:	48 89 13             	mov    %rdx,(%rbx)
 10439b8:	48 89 1c c1          	mov    %rbx,(%rcx,%rax,8)
 10439bc:	e9 ca 03 00 00       	jmp    1043d8b <my.json::read_value+0x16eb>
 10439c1:	83 f9 5d             	cmp    $0x5d,%ecx
 10439c4:	0f 85 3a 03 00 00    	jne    1043d04 <my.json::read_value+0x1664>
 10439ca:	48 ff c2             	inc    %rdx
 10439cd:	41 bf 05 00 00 00    	mov    $0x5,%r15d
 10439d3:	31 c0                	xor    %eax,%eax
 10439d5:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 10439da:	48 89 01             	mov    %rax,(%rcx)
 10439dd:	48 89 c8             	mov    %rcx,%rax
 10439e0:	4c 89 79 08          	mov    %r15,0x8(%rcx)
 10439e4:	48 89 59 10          	mov    %rbx,0x10(%rcx)
 10439e8:	4c 89 61 18          	mov    %r12,0x18(%rcx)
 10439ec:	49 89 d6             	mov    %rdx,%r14
 10439ef:	e9 e9 08 00 00       	jmp    10442dd <my.json::read_value+0x1c3d>
 10439f4:	83 f8 ff             	cmp    $0xffffffff,%eax
 10439f7:	0f 85 ea 05 00 00    	jne    1043fe7 <my.json::read_value+0x1947>
 10439fd:	40 84 ed             	test   %bpl,%bpl
 1043a00:	0f 84 f2 05 00 00    	je     1043ff8 <my.json::read_value+0x1958>
 1043a06:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 1043a0b:	48 c7 00 00 00 00 00 	movq   $0x0,(%rax)
 1043a12:	48 c7 40 08 04 00 00 	movq   $0x4,0x8(%rax)
 1043a19:	00
 1043a1a:	48 89 58 10          	mov    %rbx,0x10(%rax)
 1043a1e:	4c 89 78 18          	mov    %r15,0x18(%rax)
 1043a22:	e9 b6 08 00 00       	jmp    10442dd <my.json::read_value+0x1c3d>
 1043a27:	4d 89 d7             	mov    %r10,%r15
 1043a2a:	48 8d 05 af 50 fc ff 	lea    -0x3af51(%rip),%rax        # 1008ae0 <core_number_pairs+0x2110>
 1043a31:	4c 89 e7             	mov    %r12,%rdi
 1043a34:	49 89 d6             	mov    %rdx,%r14
 1043a37:	48 89 d6             	mov    %rdx,%rsi
 1043a3a:	48 89 c2             	mov    %rax,%rdx
 1043a3d:	e8 3e 0c 00 00       	call   1044680 <my.json::fail>
 1043a42:	48 89 c3             	mov    %rax,%rbx
 1043a45:	48 8d 3d d4 ee 00 00 	lea    0xeed4(%rip),%rdi        # 1052920 <core_io_file_error.verbs+0xc80>
 1043a4c:	b0 01                	mov    $0x1,%al
 1043a4e:	e8 2d d5 ff ff       	call   1040f80 <myl_core_err_trace_origin_preserve_most>
 1043a53:	4d 89 fa             	mov    %r15,%r10
 1043a56:	3c 01                	cmp    $0x1,%al
 1043a58:	0f 85 62 f1 ff ff    	jne    1042bc0 <my.json::read_value+0x520>
 1043a5e:	e9 0a ff ff ff       	jmp    104396d <my.json::read_value+0x12cd>
 1043a63:	83 f8 7d             	cmp    $0x7d,%eax
 1043a66:	0f 85 e4 03 00 00    	jne    1043e50 <my.json::read_value+0x17b0>
 1043a6c:	49 ff c7             	inc    %r15
 1043a6f:	ba 06 00 00 00       	mov    $0x6,%edx
 1043a74:	31 c0                	xor    %eax,%eax
 1043a76:	e9 48 08 00 00       	jmp    10442c3 <my.json::read_value+0x1c23>
 1043a7b:	80 7c 24 07 00       	cmpb   $0x0,0x7(%rsp)
 1043a80:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 1043a85:	0f 85 c5 05 00 00    	jne    1044050 <my.json::read_value+0x19b0>
 1043a8b:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043a90:	8b 07                	mov    (%rdi),%eax
 1043a92:	85 c0                	test   %eax,%eax
 1043a94:	0f 88 be 02 00 00    	js     1043d58 <my.json::read_value+0x16b8>
 1043a9a:	ff c8                	dec    %eax
 1043a9c:	0f 85 ac 05 00 00    	jne    104404e <my.json::read_value+0x19ae>
 1043aa2:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1043aa6:	48 85 c0             	test   %rax,%rax
 1043aa9:	0f 84 7c 0a 00 00    	je     104452b <my.json::read_value+0x1e8b>
 1043aaf:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 1043ab4:	0f 85 71 0a 00 00    	jne    104452b <my.json::read_value+0x1e8b>
 1043aba:	48 8d 15 8f 3d 03 00 	lea    0x33d8f(%rip),%rdx        # 1077850 <myl_core_free_lists>
 1043ac1:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043ac5:	48 89 0f             	mov    %rcx,(%rdi)
 1043ac8:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 1043acc:	e9 7f 05 00 00       	jmp    1044050 <my.json::read_value+0x19b0>
 1043ad1:	48 8d 15 e8 4c fc ff 	lea    -0x3b318(%rip),%rdx        # 10087c0 <core_number_pairs+0x1df0>
 1043ad8:	4c 89 e7             	mov    %r12,%rdi
 1043adb:	4c 89 f6             	mov    %r14,%rsi
 1043ade:	e8 9d 0b 00 00       	call   1044680 <my.json::fail>
 1043ae3:	48 89 c3             	mov    %rax,%rbx
 1043ae6:	48 8d 3d c3 eb 00 00 	lea    0xebc3(%rip),%rdi        # 10526b0 <core_io_file_error.verbs+0xa10>
 1043aed:	e8 8e d4 ff ff       	call   1040f80 <myl_core_err_trace_origin_preserve_most>
 1043af2:	e9 94 02 00 00       	jmp    1043d8b <my.json::read_value+0x16eb>
 1043af7:	8b 45 00             	mov    0x0(%rbp),%eax
 1043afa:	85 c0                	test   %eax,%eax
 1043afc:	0f 88 6e 02 00 00    	js     1043d70 <my.json::read_value+0x16d0>
 1043b02:	ff c8                	dec    %eax
 1043b04:	0f 85 31 06 00 00    	jne    104413b <my.json::read_value+0x1a9b>
 1043b0a:	0f b6 45 07          	movzbl 0x7(%rbp),%eax
 1043b0e:	48 85 c0             	test   %rax,%rax
 1043b11:	0f 84 1e 0a 00 00    	je     1044535 <my.json::read_value+0x1e95>
 1043b17:	48 83 7d 18 00       	cmpq   $0x0,0x18(%rbp)
 1043b1c:	0f 85 13 0a 00 00    	jne    1044535 <my.json::read_value+0x1e95>
 1043b22:	48 8d 0d 27 3d 03 00 	lea    0x33d27(%rip),%rcx        # 1077850 <myl_core_free_lists>
 1043b29:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1043b2d:	48 89 55 00          	mov    %rdx,0x0(%rbp)
 1043b31:	48 89 2c c1          	mov    %rbp,(%rcx,%rax,8)
 1043b35:	e9 04 06 00 00       	jmp    104413e <my.json::read_value+0x1a9e>
 1043b3a:	48 8d 05 bf 47 fc ff 	lea    -0x3b841(%rip),%rax        # 1008300 <core_number_pairs+0x1930>
 1043b41:	4c 89 e7             	mov    %r12,%rdi
 1043b44:	48 89 d6             	mov    %rdx,%rsi
 1043b47:	4d 89 d6             	mov    %r10,%r14
 1043b4a:	48 89 c2             	mov    %rax,%rdx
 1043b4d:	e8 2e 0b 00 00       	call   1044680 <my.json::fail>
 1043b52:	48 8d 3d 67 e7 00 00 	lea    0xe767(%rip),%rdi        # 10522c0 <core_io_file_error.verbs+0x620>
 1043b59:	e9 e1 fd ff ff       	jmp    104393f <my.json::read_value+0x129f>
 1043b5e:	48 8d 15 3b 50 fc ff 	lea    -0x3afc5(%rip),%rdx        # 1008ba0 <core_number_pairs+0x21d0>
 1043b65:	4c 89 e7             	mov    %r12,%rdi
 1043b68:	4c 89 f6             	mov    %r14,%rsi
 1043b6b:	4d 89 d7             	mov    %r10,%r15
 1043b6e:	e8 0d 0b 00 00       	call   1044680 <my.json::fail>
 1043b73:	4d 89 fa             	mov    %r15,%r10
 1043b76:	b2 01                	mov    $0x1,%dl
 1043b78:	48 8d 3d 31 ee 00 00 	lea    0xee31(%rip),%rdi        # 10529b0 <core_io_file_error.verbs+0xd10>
 1043b7f:	e8 fc d3 ff ff       	call   1040f80 <myl_core_err_trace_origin_preserve_most>
 1043b84:	80 fa 01             	cmp    $0x1,%dl
 1043b87:	0f 85 0c f2 ff ff    	jne    1042d99 <my.json::read_value+0x6f9>
 1043b8d:	48 8d 3d ec ea 00 00 	lea    0xeaec(%rip),%rdi        # 1052680 <core_io_file_error.verbs+0x9e0>
 1043b94:	e8 27 d4 ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 1043b99:	48 89 c3             	mov    %rax,%rbx
 1043b9c:	8b 00                	mov    (%rax),%eax
 1043b9e:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043ba3:	0f 87 fe 00 00 00    	ja     1043ca7 <my.json::read_value+0x1607>
 1043ba9:	ff c0                	inc    %eax
 1043bab:	89 03                	mov    %eax,(%rbx)
 1043bad:	ff c8                	dec    %eax
 1043baf:	0f 84 dd fd ff ff    	je     1043992 <my.json::read_value+0x12f2>
 1043bb5:	89 03                	mov    %eax,(%rbx)
 1043bb7:	e9 cf 01 00 00       	jmp    1043d8b <my.json::read_value+0x16eb>
 1043bbc:	48 8d 3d 0d e6 00 00 	lea    0xe60d(%rip),%rdi        # 10521d0 <core_io_file_error.verbs+0x530>
 1043bc3:	c5 f9 7f 44 24 20    	vmovdqa %xmm0,0x20(%rsp)
 1043bc9:	e8 f2 d3 ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 1043bce:	c5 f9 6f 44 24 20    	vmovdqa 0x20(%rsp),%xmm0
 1043bd4:	e9 06 f3 ff ff       	jmp    1042edf <my.json::read_value+0x83f>
 1043bd9:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043bdc:	0f 84 a9 01 00 00    	je     1043d8b <my.json::read_value+0x16eb>
 1043be2:	48 89 df             	mov    %rbx,%rdi
 1043be5:	e8 16 cf ff ff       	call   1040b00 <myl_core_retain_slow>
 1043bea:	8b 03                	mov    (%rbx),%eax
 1043bec:	85 c0                	test   %eax,%eax
 1043bee:	0f 89 96 fd ff ff    	jns    104398a <my.json::read_value+0x12ea>
 1043bf4:	e9 c9 00 00 00       	jmp    1043cc2 <my.json::read_value+0x1622>
 1043bf9:	48 8d 15 60 4f fc ff 	lea    -0x3b0a0(%rip),%rdx        # 1008b60 <core_number_pairs+0x2190>
 1043c00:	4c 89 e7             	mov    %r12,%rdi
 1043c03:	4c 89 fe             	mov    %r15,%rsi
 1043c06:	4c 89 d3             	mov    %r10,%rbx
 1043c09:	e8 72 0a 00 00       	call   1044680 <my.json::fail>
 1043c0e:	49 89 da             	mov    %rbx,%r10
 1043c11:	48 89 c3             	mov    %rax,%rbx
 1043c14:	b0 01                	mov    $0x1,%al
 1043c16:	48 8d 3d 63 ed 00 00 	lea    0xed63(%rip),%rdi        # 1052980 <core_io_file_error.verbs+0xce0>
 1043c1d:	e8 5e d3 ff ff       	call   1040f80 <myl_core_err_trace_origin_preserve_most>
 1043c22:	3c 01                	cmp    $0x1,%al
 1043c24:	0f 85 74 f0 ff ff    	jne    1042c9e <my.json::read_value+0x5fe>
 1043c2a:	48 8d 3d 1f ea 00 00 	lea    0xea1f(%rip),%rdi        # 1052650 <core_io_file_error.verbs+0x9b0>
 1043c31:	e8 8a d3 ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 1043c36:	8b 03                	mov    (%rbx),%eax
 1043c38:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043c3d:	77 3b                	ja     1043c7a <my.json::read_value+0x15da>
 1043c3f:	ff c0                	inc    %eax
 1043c41:	89 03                	mov    %eax,(%rbx)
 1043c43:	ff c8                	dec    %eax
 1043c45:	0f 85 3b 01 00 00    	jne    1043d86 <my.json::read_value+0x16e6>
 1043c4b:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043c4f:	48 85 c0             	test   %rax,%rax
 1043c52:	0f 84 6d 08 00 00    	je     10444c5 <my.json::read_value+0x1e25>
 1043c58:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043c5d:	0f 85 62 08 00 00    	jne    10444c5 <my.json::read_value+0x1e25>
 1043c63:	48 8d 0d e6 3b 03 00 	lea    0x33be6(%rip),%rcx        # 1077850 <myl_core_free_lists>
 1043c6a:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1043c6e:	48 89 13             	mov    %rdx,(%rbx)
 1043c71:	48 89 1c c1          	mov    %rbx,(%rcx,%rax,8)
 1043c75:	e9 0e 01 00 00       	jmp    1043d88 <my.json::read_value+0x16e8>
 1043c7a:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043c7d:	0f 84 05 01 00 00    	je     1043d88 <my.json::read_value+0x16e8>
 1043c83:	48 89 df             	mov    %rbx,%rdi
 1043c86:	e8 75 ce ff ff       	call   1040b00 <myl_core_retain_slow>
 1043c8b:	8b 03                	mov    (%rbx),%eax
 1043c8d:	85 c0                	test   %eax,%eax
 1043c8f:	79 b2                	jns    1043c43 <my.json::read_value+0x15a3>
 1043c91:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043c94:	0f 84 ee 00 00 00    	je     1043d88 <my.json::read_value+0x16e8>
 1043c9a:	48 89 df             	mov    %rbx,%rdi
 1043c9d:	e8 9e ce ff ff       	call   1040b40 <myl_core_release_slow>
 1043ca2:	e9 e1 00 00 00       	jmp    1043d88 <my.json::read_value+0x16e8>
 1043ca7:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043caa:	0f 84 db 00 00 00    	je     1043d8b <my.json::read_value+0x16eb>
 1043cb0:	48 89 df             	mov    %rbx,%rdi
 1043cb3:	e8 48 ce ff ff       	call   1040b00 <myl_core_retain_slow>
 1043cb8:	8b 03                	mov    (%rbx),%eax
 1043cba:	85 c0                	test   %eax,%eax
 1043cbc:	0f 89 eb fe ff ff    	jns    1043bad <my.json::read_value+0x150d>
 1043cc2:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043cc5:	0f 84 c0 00 00 00    	je     1043d8b <my.json::read_value+0x16eb>
 1043ccb:	48 89 df             	mov    %rbx,%rdi
 1043cce:	e8 6d ce ff ff       	call   1040b40 <myl_core_release_slow>
 1043cd3:	e9 b3 00 00 00       	jmp    1043d8b <my.json::read_value+0x16eb>
 1043cd8:	48 8d 3d c1 e4 00 00 	lea    0xe4c1(%rip),%rdi        # 10521a0 <core_io_file_error.verbs+0x500>
 1043cdf:	e8 dc d2 ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 1043ce4:	8b 03                	mov    (%rbx),%eax
 1043ce6:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043ceb:	0f 87 1c 02 00 00    	ja     1043f0d <my.json::read_value+0x186d>
 1043cf1:	ff c0                	inc    %eax
 1043cf3:	89 03                	mov    %eax,(%rbx)
 1043cf5:	ff c8                	dec    %eax
 1043cf7:	0f 84 35 02 00 00    	je     1043f32 <my.json::read_value+0x1892>
 1043cfd:	89 03                	mov    %eax,(%rbx)
 1043cff:	e9 58 02 00 00       	jmp    1043f5c <my.json::read_value+0x18bc>
 1043d04:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043d08:	48 85 c0             	test   %rax,%rax
 1043d0b:	0f 84 a1 07 00 00    	je     10444b2 <my.json::read_value+0x1e12>
 1043d11:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043d16:	0f 85 96 07 00 00    	jne    10444b2 <my.json::read_value+0x1e12>
 1043d1c:	48 8d 35 2d 3b 03 00 	lea    0x33b2d(%rip),%rsi        # 1077850 <myl_core_free_lists>
 1043d23:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1043d27:	48 89 0b             	mov    %rcx,(%rbx)
 1043d2a:	48 89 1c c6          	mov    %rbx,(%rsi,%rax,8)
 1043d2e:	48 8d 05 0b 49 fc ff 	lea    -0x3b6f5(%rip),%rax        # 1008640 <core_number_pairs+0x1c70>
 1043d35:	4c 89 e7             	mov    %r12,%rdi
 1043d38:	48 89 d6             	mov    %rdx,%rsi
 1043d3b:	48 89 d3             	mov    %rdx,%rbx
 1043d3e:	48 89 c2             	mov    %rax,%rdx
 1043d41:	e8 3a 09 00 00       	call   1044680 <my.json::fail>
 1043d46:	48 89 da             	mov    %rbx,%rdx
 1043d49:	49 89 c7             	mov    %rax,%r15
 1043d4c:	48 8d 3d bd e6 00 00 	lea    0xe6bd(%rip),%rdi        # 1052410 <core_io_file_error.verbs+0x770>
 1043d53:	e9 74 02 00 00       	jmp    1043fcc <my.json::read_value+0x192c>
 1043d58:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043d5b:	0f 84 ef 02 00 00    	je     1044050 <my.json::read_value+0x19b0>
 1043d61:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043d66:	e8 d5 cd ff ff       	call   1040b40 <myl_core_release_slow>
 1043d6b:	e9 e0 02 00 00       	jmp    1044050 <my.json::read_value+0x19b0>
 1043d70:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043d73:	0f 84 c5 03 00 00    	je     104413e <my.json::read_value+0x1a9e>
 1043d79:	48 89 ef             	mov    %rbp,%rdi
 1043d7c:	e8 bf cd ff ff       	call   1040b40 <myl_core_release_slow>
 1043d81:	e9 b8 03 00 00       	jmp    104413e <my.json::read_value+0x1a9e>
 1043d86:	89 03                	mov    %eax,(%rbx)
 1043d88:	4d 89 fe             	mov    %r15,%r14
 1043d8b:	48 8d 3d ce e4 00 00 	lea    0xe4ce(%rip),%rdi        # 1052260 <core_io_file_error.verbs+0x5c0>
 1043d92:	e8 29 d2 ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 1043d97:	b8 01 00 00 00       	mov    $0x1,%eax
 1043d9c:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 1043da1:	48 89 01             	mov    %rax,(%rcx)
 1043da4:	48 89 c8             	mov    %rcx,%rax
 1043da7:	48 89 59 08          	mov    %rbx,0x8(%rcx)
 1043dab:	48 89 51 10          	mov    %rdx,0x10(%rcx)
 1043daf:	4c 89 61 18          	mov    %r12,0x18(%rcx)
 1043db3:	e9 25 05 00 00       	jmp    10442dd <my.json::read_value+0x1c3d>
 1043db8:	48 8d 15 61 4b fc ff 	lea    -0x3b49f(%rip),%rdx        # 1008920 <core_number_pairs+0x1f50>
 1043dbf:	4c 89 f7             	mov    %r14,%rdi
 1043dc2:	4c 89 fe             	mov    %r15,%rsi
 1043dc5:	e8 b6 08 00 00       	call   1044680 <my.json::fail>
 1043dca:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 1043dcf:	48 8d 3d 6a e9 00 00 	lea    0xe96a(%rip),%rdi        # 1052740 <core_io_file_error.verbs+0xaa0>
 1043dd6:	e9 93 02 00 00       	jmp    104406e <my.json::read_value+0x19ce>
 1043ddb:	80 7c 24 07 00       	cmpb   $0x0,0x7(%rsp)
 1043de0:	0f 85 42 05 00 00    	jne    1044328 <my.json::read_value+0x1c88>
 1043de6:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1043deb:	8b 07                	mov    (%rdi),%eax
 1043ded:	85 c0                	test   %eax,%eax
 1043def:	0f 88 7a 04 00 00    	js     104426f <my.json::read_value+0x1bcf>
 1043df5:	ff c8                	dec    %eax
 1043df7:	0f 85 29 05 00 00    	jne    1044326 <my.json::read_value+0x1c86>
 1043dfd:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1043e01:	48 85 c0             	test   %rax,%rax
 1043e04:	0f 84 e2 07 00 00    	je     10445ec <my.json::read_value+0x1f4c>
 1043e0a:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 1043e0f:	0f 85 d7 07 00 00    	jne    10445ec <my.json::read_value+0x1f4c>
 1043e15:	48 8d 15 34 3a 03 00 	lea    0x33a34(%rip),%rdx        # 1077850 <myl_core_free_lists>
 1043e1c:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043e20:	48 89 0f             	mov    %rcx,(%rdi)
 1043e23:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 1043e27:	e9 fc 04 00 00       	jmp    1044328 <my.json::read_value+0x1c88>
 1043e2c:	4d 89 d7             	mov    %r10,%r15
 1043e2f:	48 8d 15 ea 4c fc ff 	lea    -0x3b316(%rip),%rdx        # 1008b20 <core_number_pairs+0x2150>
 1043e36:	4c 89 e7             	mov    %r12,%rdi
 1043e39:	49 89 f6             	mov    %rsi,%r14
 1043e3c:	e8 3f 08 00 00       	call   1044680 <my.json::fail>
 1043e41:	48 89 c3             	mov    %rax,%rbx
 1043e44:	48 8d 3d 05 eb 00 00 	lea    0xeb05(%rip),%rdi        # 1052950 <core_io_file_error.verbs+0xcb0>
 1043e4b:	e9 fc fb ff ff       	jmp    1043a4c <my.json::read_value+0x13ac>
 1043e50:	8b 45 00             	mov    0x0(%rbp),%eax
 1043e53:	85 c0                	test   %eax,%eax
 1043e55:	0f 88 c0 03 00 00    	js     104421b <my.json::read_value+0x1b7b>
 1043e5b:	ff c8                	dec    %eax
 1043e5d:	0f 85 24 04 00 00    	jne    1044287 <my.json::read_value+0x1be7>
 1043e63:	0f b6 45 07          	movzbl 0x7(%rbp),%eax
 1043e67:	48 85 c0             	test   %rax,%rax
 1043e6a:	0f 84 49 07 00 00    	je     10445b9 <my.json::read_value+0x1f19>
 1043e70:	48 83 7d 18 00       	cmpq   $0x0,0x18(%rbp)
 1043e75:	0f 85 3e 07 00 00    	jne    10445b9 <my.json::read_value+0x1f19>
 1043e7b:	48 8d 15 ce 39 03 00 	lea    0x339ce(%rip),%rdx        # 1077850 <myl_core_free_lists>
 1043e82:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043e86:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 1043e8a:	48 89 2c c2          	mov    %rbp,(%rdx,%rax,8)
 1043e8e:	e9 f7 03 00 00       	jmp    104428a <my.json::read_value+0x1bea>
 1043e93:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043e97:	48 85 c0             	test   %rax,%rax
 1043e9a:	0f 84 5f 06 00 00    	je     10444ff <my.json::read_value+0x1e5f>
 1043ea0:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043ea5:	0f 85 54 06 00 00    	jne    10444ff <my.json::read_value+0x1e5f>
 1043eab:	4c 8d 35 9e 39 03 00 	lea    0x3399e(%rip),%r14        # 1077850 <myl_core_free_lists>
 1043eb2:	49 8b 0c c6          	mov    (%r14,%rax,8),%rcx
 1043eb6:	48 89 0b             	mov    %rcx,(%rbx)
 1043eb9:	49 89 1c c6          	mov    %rbx,(%r14,%rax,8)
 1043ebd:	48 8d 3d 1c e5 00 00 	lea    0xe51c(%rip),%rdi        # 10523e0 <core_io_file_error.verbs+0x740>
 1043ec4:	e8 f7 d0 ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 1043ec9:	41 8b 07             	mov    (%r15),%eax
 1043ecc:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1043ed1:	0f 87 53 03 00 00    	ja     104422a <my.json::read_value+0x1b8a>
 1043ed7:	ff c0                	inc    %eax
 1043ed9:	41 89 07             	mov    %eax,(%r15)
 1043edc:	ff c8                	dec    %eax
 1043ede:	0f 85 70 03 00 00    	jne    1044254 <my.json::read_value+0x1bb4>
 1043ee4:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 1043ee9:	48 85 c0             	test   %rax,%rax
 1043eec:	0f 84 b7 06 00 00    	je     10445a9 <my.json::read_value+0x1f09>
 1043ef2:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 1043ef7:	0f 85 ac 06 00 00    	jne    10445a9 <my.json::read_value+0x1f09>
 1043efd:	49 8b 0c c6          	mov    (%r14,%rax,8),%rcx
 1043f01:	49 89 0f             	mov    %rcx,(%r15)
 1043f04:	4d 89 3c c6          	mov    %r15,(%r14,%rax,8)
 1043f08:	e9 c4 00 00 00       	jmp    1043fd1 <my.json::read_value+0x1931>
 1043f0d:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043f10:	74 4a                	je     1043f5c <my.json::read_value+0x18bc>
 1043f12:	4d 89 f4             	mov    %r14,%r12
 1043f15:	48 89 df             	mov    %rbx,%rdi
 1043f18:	e8 e3 cb ff ff       	call   1040b00 <myl_core_retain_slow>
 1043f1d:	8b 03                	mov    (%rbx),%eax
 1043f1f:	85 c0                	test   %eax,%eax
 1043f21:	0f 88 d0 04 00 00    	js     10443f7 <my.json::read_value+0x1d57>
 1043f27:	4d 89 e6             	mov    %r12,%r14
 1043f2a:	ff c8                	dec    %eax
 1043f2c:	0f 85 cb fd ff ff    	jne    1043cfd <my.json::read_value+0x165d>
 1043f32:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043f36:	48 85 c0             	test   %rax,%rax
 1043f39:	0f 84 5d 06 00 00    	je     104459c <my.json::read_value+0x1efc>
 1043f3f:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043f44:	0f 85 52 06 00 00    	jne    104459c <my.json::read_value+0x1efc>
 1043f4a:	48 8d 0d ff 38 03 00 	lea    0x338ff(%rip),%rcx        # 1077850 <myl_core_free_lists>
 1043f51:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1043f55:	48 89 13             	mov    %rdx,(%rbx)
 1043f58:	48 89 1c c1          	mov    %rbx,(%rcx,%rax,8)
 1043f5c:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 1043f61:	48 c7 00 01 00 00 00 	movq   $0x1,(%rax)
 1043f68:	48 89 58 08          	mov    %rbx,0x8(%rax)
 1043f6c:	4c 89 78 18          	mov    %r15,0x18(%rax)
 1043f70:	e9 68 03 00 00       	jmp    10442dd <my.json::read_value+0x1c3d>
 1043f75:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043f79:	48 85 c0             	test   %rax,%rax
 1043f7c:	48 8d 35 cd 38 03 00 	lea    0x338cd(%rip),%rsi        # 1077850 <myl_core_free_lists>
 1043f83:	74 14                	je     1043f99 <my.json::read_value+0x18f9>
 1043f85:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043f8a:	75 0d                	jne    1043f99 <my.json::read_value+0x18f9>
 1043f8c:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1043f90:	48 89 0b             	mov    %rcx,(%rbx)
 1043f93:	48 89 1c c6          	mov    %rbx,(%rsi,%rax,8)
 1043f97:	eb 0e                	jmp    1043fa7 <my.json::read_value+0x1907>
 1043f99:	49 89 d6             	mov    %rdx,%r14
 1043f9c:	48 89 df             	mov    %rbx,%rdi
 1043f9f:	e8 1c cc ff ff       	call   1040bc0 <myl_core_free_block>
 1043fa4:	4c 89 f2             	mov    %r14,%rdx
 1043fa7:	48 8d 05 52 46 fc ff 	lea    -0x3b9ae(%rip),%rax        # 1008600 <core_number_pairs+0x1c30>
 1043fae:	4c 89 e7             	mov    %r12,%rdi
 1043fb1:	48 89 d6             	mov    %rdx,%rsi
 1043fb4:	48 89 d3             	mov    %rdx,%rbx
 1043fb7:	48 89 c2             	mov    %rax,%rdx
 1043fba:	e8 c1 06 00 00       	call   1044680 <my.json::fail>
 1043fbf:	48 89 da             	mov    %rbx,%rdx
 1043fc2:	49 89 c7             	mov    %rax,%r15
 1043fc5:	48 8d 3d e4 e3 00 00 	lea    0xe3e4(%rip),%rdi        # 10523b0 <core_io_file_error.verbs+0x710>
 1043fcc:	e8 af cf ff ff       	call   1040f80 <myl_core_err_trace_origin_preserve_most>
 1043fd1:	48 8d 3d 98 e1 00 00 	lea    0xe198(%rip),%rdi        # 1052170 <core_io_file_error.verbs+0x4d0>
 1043fd8:	e8 e3 cf ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 1043fdd:	b8 01 00 00 00       	mov    $0x1,%eax
 1043fe2:	e9 ee f9 ff ff       	jmp    10439d5 <my.json::read_value+0x1335>
 1043fe7:	48 89 df             	mov    %rbx,%rdi
 1043fea:	e8 11 cb ff ff       	call   1040b00 <myl_core_retain_slow>
 1043fef:	40 84 ed             	test   %bpl,%bpl
 1043ff2:	0f 85 0e fa ff ff    	jne    1043a06 <my.json::read_value+0x1366>
 1043ff8:	8b 03                	mov    (%rbx),%eax
 1043ffa:	85 c0                	test   %eax,%eax
 1043ffc:	78 0b                	js     1044009 <my.json::read_value+0x1969>
 1043ffe:	ff c8                	dec    %eax
 1044000:	74 1d                	je     104401f <my.json::read_value+0x197f>
 1044002:	89 03                	mov    %eax,(%rbx)
 1044004:	e9 fd f9 ff ff       	jmp    1043a06 <my.json::read_value+0x1366>
 1044009:	83 f8 ff             	cmp    $0xffffffff,%eax
 104400c:	0f 84 f4 f9 ff ff    	je     1043a06 <my.json::read_value+0x1366>
 1044012:	48 89 df             	mov    %rbx,%rdi
 1044015:	e8 26 cb ff ff       	call   1040b40 <myl_core_release_slow>
 104401a:	e9 e7 f9 ff ff       	jmp    1043a06 <my.json::read_value+0x1366>
 104401f:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1044023:	48 85 c0             	test   %rax,%rax
 1044026:	0f 84 5f 04 00 00    	je     104448b <my.json::read_value+0x1deb>
 104402c:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1044031:	0f 85 54 04 00 00    	jne    104448b <my.json::read_value+0x1deb>
 1044037:	48 8d 0d 12 38 03 00 	lea    0x33812(%rip),%rcx        # 1077850 <myl_core_free_lists>
 104403e:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1044042:	48 89 13             	mov    %rdx,(%rbx)
 1044045:	48 89 1c c1          	mov    %rbx,(%rcx,%rax,8)
 1044049:	e9 b8 f9 ff ff       	jmp    1043a06 <my.json::read_value+0x1366>
 104404e:	89 07                	mov    %eax,(%rdi)
 1044050:	48 8d 15 29 49 fc ff 	lea    -0x3b6d7(%rip),%rdx        # 1008980 <core_number_pairs+0x1fb0>
 1044057:	4c 89 f7             	mov    %r14,%rdi
 104405a:	4c 89 fe             	mov    %r15,%rsi
 104405d:	e8 1e 06 00 00       	call   1044680 <my.json::fail>
 1044062:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 1044067:	48 8d 3d 32 e7 00 00 	lea    0xe732(%rip),%rdi        # 10527a0 <core_io_file_error.verbs+0xb00>
 104406e:	e8 0d cf ff ff       	call   1040f80 <myl_core_err_trace_origin_preserve_most>
 1044073:	8b 45 00             	mov    0x0(%rbp),%eax
 1044076:	85 c0                	test   %eax,%eax
 1044078:	78 31                	js     10440ab <my.json::read_value+0x1a0b>
 104407a:	ff c8                	dec    %eax
 104407c:	75 3c                	jne    10440ba <my.json::read_value+0x1a1a>
 104407e:	0f b6 45 07          	movzbl 0x7(%rbp),%eax
 1044082:	48 85 c0             	test   %rax,%rax
 1044085:	0f 84 1a 04 00 00    	je     10444a5 <my.json::read_value+0x1e05>
 104408b:	48 83 7d 18 00       	cmpq   $0x0,0x18(%rbp)
 1044090:	0f 85 0f 04 00 00    	jne    10444a5 <my.json::read_value+0x1e05>
 1044096:	48 8d 15 b3 37 03 00 	lea    0x337b3(%rip),%rdx        # 1077850 <myl_core_free_lists>
 104409d:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 10440a1:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 10440a5:	48 89 2c c2          	mov    %rbp,(%rdx,%rax,8)
 10440a9:	eb 12                	jmp    10440bd <my.json::read_value+0x1a1d>
 10440ab:	83 f8 ff             	cmp    $0xffffffff,%eax
 10440ae:	74 0d                	je     10440bd <my.json::read_value+0x1a1d>
 10440b0:	48 89 ef             	mov    %rbp,%rdi
 10440b3:	e8 88 ca ff ff       	call   1040b40 <myl_core_release_slow>
 10440b8:	eb 03                	jmp    10440bd <my.json::read_value+0x1a1d>
 10440ba:	89 45 00             	mov    %eax,0x0(%rbp)
 10440bd:	48 8d 3d 8c e2 00 00 	lea    0xe28c(%rip),%rdi        # 1052350 <core_io_file_error.verbs+0x6b0>
 10440c4:	e8 f7 ce ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 10440c9:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10440ce:	8b 07                	mov    (%rdi),%eax
 10440d0:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 10440d5:	77 34                	ja     104410b <my.json::read_value+0x1a6b>
 10440d7:	ff c0                	inc    %eax
 10440d9:	89 07                	mov    %eax,(%rdi)
 10440db:	ff c8                	dec    %eax
 10440dd:	75 52                	jne    1044131 <my.json::read_value+0x1a91>
 10440df:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 10440e3:	48 85 c0             	test   %rax,%rax
 10440e6:	0f 84 95 03 00 00    	je     1044481 <my.json::read_value+0x1de1>
 10440ec:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 10440f1:	0f 85 8a 03 00 00    	jne    1044481 <my.json::read_value+0x1de1>
 10440f7:	48 8d 15 52 37 03 00 	lea    0x33752(%rip),%rdx        # 1077850 <myl_core_free_lists>
 10440fe:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1044102:	48 89 0f             	mov    %rcx,(%rdi)
 1044105:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 1044109:	eb 28                	jmp    1044133 <my.json::read_value+0x1a93>
 104410b:	83 f8 ff             	cmp    $0xffffffff,%eax
 104410e:	74 23                	je     1044133 <my.json::read_value+0x1a93>
 1044110:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1044115:	e8 e6 c9 ff ff       	call   1040b00 <myl_core_retain_slow>
 104411a:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 104411f:	8b 07                	mov    (%rdi),%eax
 1044121:	85 c0                	test   %eax,%eax
 1044123:	79 b6                	jns    10440db <my.json::read_value+0x1a3b>
 1044125:	83 f8 ff             	cmp    $0xffffffff,%eax
 1044128:	74 09                	je     1044133 <my.json::read_value+0x1a93>
 104412a:	e8 11 ca ff ff       	call   1040b40 <myl_core_release_slow>
 104412f:	eb 02                	jmp    1044133 <my.json::read_value+0x1a93>
 1044131:	89 07                	mov    %eax,(%rdi)
 1044133:	4d 89 f4             	mov    %r14,%r12
 1044136:	e9 72 01 00 00       	jmp    10442ad <my.json::read_value+0x1c0d>
 104413b:	89 45 00             	mov    %eax,0x0(%rbp)
 104413e:	48 8d 15 1b 44 fc ff 	lea    -0x3bbe5(%rip),%rdx        # 1008560 <core_number_pairs+0x1b90>
 1044145:	4c 89 e7             	mov    %r12,%rdi
 1044148:	4c 89 fe             	mov    %r15,%rsi
 104414b:	e8 30 05 00 00       	call   1044680 <my.json::fail>
 1044150:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 1044155:	48 8d 3d c4 e1 00 00 	lea    0xe1c4(%rip),%rdi        # 1052320 <core_io_file_error.verbs+0x680>
 104415c:	e9 47 01 00 00       	jmp    10442a8 <my.json::read_value+0x1c08>
 1044161:	48 89 f8             	mov    %rdi,%rax
 1044164:	48 8d 3d 05 e6 00 00 	lea    0xe605(%rip),%rdi        # 1052770 <core_io_file_error.verbs+0xad0>
 104416b:	e8 50 ce ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 1044170:	48 89 c7             	mov    %rax,%rdi
 1044173:	8b 00                	mov    (%rax),%eax
 1044175:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 104417a:	0f 87 dc 00 00 00    	ja     104425c <my.json::read_value+0x1bbc>
 1044180:	ff c0                	inc    %eax
 1044182:	89 07                	mov    %eax,(%rdi)
 1044184:	ff c8                	dec    %eax
 1044186:	0f 85 67 01 00 00    	jne    10442f3 <my.json::read_value+0x1c53>
 104418c:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1044190:	48 85 c0             	test   %rax,%rax
 1044193:	0f 84 2d 04 00 00    	je     10445c6 <my.json::read_value+0x1f26>
 1044199:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 104419e:	0f 85 22 04 00 00    	jne    10445c6 <my.json::read_value+0x1f26>
 10441a4:	48 8d 15 a5 36 03 00 	lea    0x336a5(%rip),%rdx        # 1077850 <myl_core_free_lists>
 10441ab:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 10441af:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10441b4:	48 89 0e             	mov    %rcx,(%rsi)
 10441b7:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 10441bc:	48 89 0c c2          	mov    %rcx,(%rdx,%rax,8)
 10441c0:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 10441c5:	e9 9b 00 00 00       	jmp    1044265 <my.json::read_value+0x1bc5>
 10441ca:	80 7c 24 07 00       	cmpb   $0x0,0x7(%rsp)
 10441cf:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 10441d4:	0f 85 94 01 00 00    	jne    104436e <my.json::read_value+0x1cce>
 10441da:	8b 07                	mov    (%rdi),%eax
 10441dc:	85 c0                	test   %eax,%eax
 10441de:	0f 88 67 01 00 00    	js     104434b <my.json::read_value+0x1cab>
 10441e4:	ff c8                	dec    %eax
 10441e6:	0f 85 80 01 00 00    	jne    104436c <my.json::read_value+0x1ccc>
 10441ec:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 10441f0:	48 85 c0             	test   %rax,%rax
 10441f3:	0f 84 3c 04 00 00    	je     1044635 <my.json::read_value+0x1f95>
 10441f9:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 10441fe:	0f 85 31 04 00 00    	jne    1044635 <my.json::read_value+0x1f95>
 1044204:	48 8d 15 45 36 03 00 	lea    0x33645(%rip),%rdx        # 1077850 <myl_core_free_lists>
 104420b:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 104420f:	48 89 0f             	mov    %rcx,(%rdi)
 1044212:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 1044216:	e9 53 01 00 00       	jmp    104436e <my.json::read_value+0x1cce>
 104421b:	83 f8 ff             	cmp    $0xffffffff,%eax
 104421e:	74 6a                	je     104428a <my.json::read_value+0x1bea>
 1044220:	48 89 ef             	mov    %rbp,%rdi
 1044223:	e8 18 c9 ff ff       	call   1040b40 <myl_core_release_slow>
 1044228:	eb 60                	jmp    104428a <my.json::read_value+0x1bea>
 104422a:	83 f8 ff             	cmp    $0xffffffff,%eax
 104422d:	0f 84 9e fd ff ff    	je     1043fd1 <my.json::read_value+0x1931>
 1044233:	48 89 d3             	mov    %rdx,%rbx
 1044236:	4c 89 ff             	mov    %r15,%rdi
 1044239:	e8 c2 c8 ff ff       	call   1040b00 <myl_core_retain_slow>
 104423e:	41 8b 07             	mov    (%r15),%eax
 1044241:	85 c0                	test   %eax,%eax
 1044243:	0f 88 0e 01 00 00    	js     1044357 <my.json::read_value+0x1cb7>
 1044249:	48 89 da             	mov    %rbx,%rdx
 104424c:	ff c8                	dec    %eax
 104424e:	0f 84 90 fc ff ff    	je     1043ee4 <my.json::read_value+0x1844>
 1044254:	41 89 07             	mov    %eax,(%r15)
 1044257:	e9 75 fd ff ff       	jmp    1043fd1 <my.json::read_value+0x1931>
 104425c:	83 f8 ff             	cmp    $0xffffffff,%eax
 104425f:	0f 85 9a 00 00 00    	jne    10442ff <my.json::read_value+0x1c5f>
 1044265:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
 104426a:	e9 04 fe ff ff       	jmp    1044073 <my.json::read_value+0x19d3>
 104426f:	83 f8 ff             	cmp    $0xffffffff,%eax
 1044272:	0f 84 b0 00 00 00    	je     1044328 <my.json::read_value+0x1c88>
 1044278:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 104427d:	e8 be c8 ff ff       	call   1040b40 <myl_core_release_slow>
 1044282:	e9 a1 00 00 00       	jmp    1044328 <my.json::read_value+0x1c88>
 1044287:	89 45 00             	mov    %eax,0x0(%rbp)
 104428a:	48 8d 15 0f 43 fc ff 	lea    -0x3bcf1(%rip),%rdx        # 10085a0 <core_number_pairs+0x1bd0>
 1044291:	4c 89 e7             	mov    %r12,%rdi
 1044294:	4c 89 fe             	mov    %r15,%rsi
 1044297:	e8 e4 03 00 00       	call   1044680 <my.json::fail>
 104429c:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 10442a1:	48 8d 3d d8 e0 00 00 	lea    0xe0d8(%rip),%rdi        # 1052380 <core_io_file_error.verbs+0x6e0>
 10442a8:	e8 d3 cc ff ff       	call   1040f80 <myl_core_err_trace_origin_preserve_most>
 10442ad:	48 8d 3d 8c de 00 00 	lea    0xde8c(%rip),%rdi        # 1052140 <core_io_file_error.verbs+0x4a0>
 10442b4:	e8 07 cd ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 10442b9:	b8 01 00 00 00       	mov    $0x1,%eax
 10442be:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 10442c3:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 10442c8:	48 89 01             	mov    %rax,(%rcx)
 10442cb:	48 89 c8             	mov    %rcx,%rax
 10442ce:	48 89 51 08          	mov    %rdx,0x8(%rcx)
 10442d2:	48 89 69 10          	mov    %rbp,0x10(%rcx)
 10442d6:	4c 89 61 18          	mov    %r12,0x18(%rcx)
 10442da:	4d 89 fe             	mov    %r15,%r14
 10442dd:	4c 89 70 20          	mov    %r14,0x20(%rax)
 10442e1:	48 81 c4 88 01 00 00 	add    $0x188,%rsp
 10442e8:	5b                   	pop    %rbx
 10442e9:	41 5c                	pop    %r12
 10442eb:	41 5d                	pop    %r13
 10442ed:	41 5e                	pop    %r14
 10442ef:	41 5f                	pop    %r15
 10442f1:	5d                   	pop    %rbp
 10442f2:	c3                   	ret
 10442f3:	89 07                	mov    %eax,(%rdi)
 10442f5:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
 10442fa:	e9 74 fd ff ff       	jmp    1044073 <my.json::read_value+0x19d3>
 10442ff:	e8 fc c7 ff ff       	call   1040b00 <myl_core_retain_slow>
 1044304:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1044309:	8b 07                	mov    (%rdi),%eax
 104430b:	85 c0                	test   %eax,%eax
 104430d:	0f 89 71 fe ff ff    	jns    1044184 <my.json::read_value+0x1ae4>
 1044313:	83 f8 ff             	cmp    $0xffffffff,%eax
 1044316:	0f 84 49 ff ff ff    	je     1044265 <my.json::read_value+0x1bc5>
 104431c:	e8 1f c8 ff ff       	call   1040b40 <myl_core_release_slow>
 1044321:	e9 9a fe ff ff       	jmp    10441c0 <my.json::read_value+0x1b20>
 1044326:	89 07                	mov    %eax,(%rdi)
 1044328:	48 8d 15 91 46 fc ff 	lea    -0x3b96f(%rip),%rdx        # 10089c0 <core_number_pairs+0x1ff0>
 104432f:	4c 89 f7             	mov    %r14,%rdi
 1044332:	4c 89 fe             	mov    %r15,%rsi
 1044335:	e8 46 03 00 00       	call   1044680 <my.json::fail>
 104433a:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 104433f:	48 8d 3d 8a e4 00 00 	lea    0xe48a(%rip),%rdi        # 10527d0 <core_io_file_error.verbs+0xb30>
 1044346:	e9 23 fd ff ff       	jmp    104406e <my.json::read_value+0x19ce>
 104434b:	83 f8 ff             	cmp    $0xffffffff,%eax
 104434e:	74 1e                	je     104436e <my.json::read_value+0x1cce>
 1044350:	e8 eb c7 ff ff       	call   1040b40 <myl_core_release_slow>
 1044355:	eb 17                	jmp    104436e <my.json::read_value+0x1cce>
 1044357:	83 f8 ff             	cmp    $0xffffffff,%eax
 104435a:	74 08                	je     1044364 <my.json::read_value+0x1cc4>
 104435c:	4c 89 ff             	mov    %r15,%rdi
 104435f:	e8 dc c7 ff ff       	call   1040b40 <myl_core_release_slow>
 1044364:	48 89 da             	mov    %rbx,%rdx
 1044367:	e9 65 fc ff ff       	jmp    1043fd1 <my.json::read_value+0x1931>
 104436c:	89 07                	mov    %eax,(%rdi)
 104436e:	48 8d 3d 8b e4 00 00 	lea    0xe48b(%rip),%rdi        # 1052800 <core_io_file_error.verbs+0xb60>
 1044375:	e8 46 cc ff ff       	call   1040fc0 <myl_core_err_trace_append_preserve_most>
 104437a:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 104437f:	8b 07                	mov    (%rdi),%eax
 1044381:	3d fd ff ff 7f       	cmp    $0x7ffffffd,%eax
 1044386:	77 37                	ja     10443bf <my.json::read_value+0x1d1f>
 1044388:	ff c0                	inc    %eax
 104438a:	89 07                	mov    %eax,(%rdi)
 104438c:	ff c8                	dec    %eax
 104438e:	75 60                	jne    10443f0 <my.json::read_value+0x1d50>
 1044390:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1044394:	48 85 c0             	test   %rax,%rax
 1044397:	0f 84 33 02 00 00    	je     10445d0 <my.json::read_value+0x1f30>
 104439d:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 10443a2:	0f 85 28 02 00 00    	jne    10445d0 <my.json::read_value+0x1f30>
 10443a8:	48 8d 15 a1 34 03 00 	lea    0x334a1(%rip),%rdx        # 1077850 <myl_core_free_lists>
 10443af:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 10443b3:	48 89 0f             	mov    %rcx,(%rdi)
 10443b6:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 10443ba:	e9 b4 fc ff ff       	jmp    1044073 <my.json::read_value+0x19d3>
 10443bf:	83 f8 ff             	cmp    $0xffffffff,%eax
 10443c2:	0f 84 ab fc ff ff    	je     1044073 <my.json::read_value+0x19d3>
 10443c8:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10443cd:	e8 2e c7 ff ff       	call   1040b00 <myl_core_retain_slow>
 10443d2:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10443d7:	8b 07                	mov    (%rdi),%eax
 10443d9:	85 c0                	test   %eax,%eax
 10443db:	79 af                	jns    104438c <my.json::read_value+0x1cec>
 10443dd:	83 f8 ff             	cmp    $0xffffffff,%eax
 10443e0:	0f 84 8d fc ff ff    	je     1044073 <my.json::read_value+0x19d3>
 10443e6:	e8 55 c7 ff ff       	call   1040b40 <myl_core_release_slow>
 10443eb:	e9 83 fc ff ff       	jmp    1044073 <my.json::read_value+0x19d3>
 10443f0:	89 07                	mov    %eax,(%rdi)
 10443f2:	e9 7c fc ff ff       	jmp    1044073 <my.json::read_value+0x19d3>
 10443f7:	83 f8 ff             	cmp    $0xffffffff,%eax
 10443fa:	4d 89 e6             	mov    %r12,%r14
 10443fd:	0f 84 59 fb ff ff    	je     1043f5c <my.json::read_value+0x18bc>
 1044403:	48 89 df             	mov    %rbx,%rdi
 1044406:	e8 35 c7 ff ff       	call   1040b40 <myl_core_release_slow>
 104440b:	4d 89 e6             	mov    %r12,%r14
 104440e:	e9 49 fb ff ff       	jmp    1043f5c <my.json::read_value+0x18bc>
 1044413:	be 10 00 00 00       	mov    $0x10,%esi
 1044418:	31 ff                	xor    %edi,%edi
 104441a:	4c 89 d3             	mov    %r10,%rbx
 104441d:	49 89 d6             	mov    %rdx,%r14
 1044420:	e8 1b f7 fc ff       	call   1013b40 <myl_core_list_new_slow>
 1044425:	4c 89 f2             	mov    %r14,%rdx
 1044428:	49 89 da             	mov    %rbx,%r10
 104442b:	48 89 c3             	mov    %rax,%rbx
 104442e:	e9 99 e3 ff ff       	jmp    10427cc <my.json::read_value+0x12c>
 1044433:	48 8d 3d b6 de 00 00 	lea    0xdeb6(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104443a:	48 89 d6             	mov    %rdx,%rsi
 104443d:	48 89 c2             	mov    %rax,%rdx
 1044440:	e8 bb 02 fd ff       	call   1014700 <myl_core_trap>
 1044445:	48 8d 3d a4 de 00 00 	lea    0xdea4(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104444c:	4c 89 d6             	mov    %r10,%rsi
 104444f:	e8 ac 02 fd ff       	call   1014700 <myl_core_trap>
 1044454:	48 8d 3d 95 de 00 00 	lea    0xde95(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104445b:	4c 89 fe             	mov    %r15,%rsi
 104445e:	e8 9d 02 fd ff       	call   1014700 <myl_core_trap>
 1044463:	48 8d 3d 86 de 00 00 	lea    0xde86(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104446a:	4c 89 fe             	mov    %r15,%rsi
 104446d:	e8 8e 02 fd ff       	call   1014700 <myl_core_trap>
 1044472:	48 8d 3d 77 de 00 00 	lea    0xde77(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044479:	4c 89 fe             	mov    %r15,%rsi
 104447c:	e8 7f 02 fd ff       	call   1014700 <myl_core_trap>
 1044481:	e8 3a c7 ff ff       	call   1040bc0 <myl_core_free_block>
 1044486:	e9 a8 fc ff ff       	jmp    1044133 <my.json::read_value+0x1a93>
 104448b:	48 89 df             	mov    %rbx,%rdi
 104448e:	e8 2d c7 ff ff       	call   1040bc0 <myl_core_free_block>
 1044493:	e9 6e f5 ff ff       	jmp    1043a06 <my.json::read_value+0x1366>
 1044498:	48 89 df             	mov    %rbx,%rdi
 104449b:	e8 20 c7 ff ff       	call   1040bc0 <myl_core_free_block>
 10444a0:	e9 e6 f8 ff ff       	jmp    1043d8b <my.json::read_value+0x16eb>
 10444a5:	48 89 ef             	mov    %rbp,%rdi
 10444a8:	e8 13 c7 ff ff       	call   1040bc0 <myl_core_free_block>
 10444ad:	e9 0b fc ff ff       	jmp    10440bd <my.json::read_value+0x1a1d>
 10444b2:	48 89 df             	mov    %rbx,%rdi
 10444b5:	48 89 d3             	mov    %rdx,%rbx
 10444b8:	e8 03 c7 ff ff       	call   1040bc0 <myl_core_free_block>
 10444bd:	48 89 da             	mov    %rbx,%rdx
 10444c0:	e9 69 f8 ff ff       	jmp    1043d2e <my.json::read_value+0x168e>
 10444c5:	48 89 df             	mov    %rbx,%rdi
 10444c8:	e8 f3 c6 ff ff       	call   1040bc0 <myl_core_free_block>
 10444cd:	e9 b6 f8 ff ff       	jmp    1043d88 <my.json::read_value+0x16e8>
 10444d2:	48 8d 3d 17 de 00 00 	lea    0xde17(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10444d9:	4c 89 f6             	mov    %r14,%rsi
 10444dc:	48 89 c2             	mov    %rax,%rdx
 10444df:	e8 1c 02 fd ff       	call   1014700 <myl_core_trap>
 10444e4:	48 8d 3d 05 de 00 00 	lea    0xde05(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10444eb:	48 89 c2             	mov    %rax,%rdx
 10444ee:	e8 0d 02 fd ff       	call   1014700 <myl_core_trap>
 10444f3:	48 8d 3d f6 dd 00 00 	lea    0xddf6(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10444fa:	e8 01 02 fd ff       	call   1014700 <myl_core_trap>
 10444ff:	48 89 df             	mov    %rbx,%rdi
 1044502:	48 89 d3             	mov    %rdx,%rbx
 1044505:	e8 b6 c6 ff ff       	call   1040bc0 <myl_core_free_block>
 104450a:	48 89 da             	mov    %rbx,%rdx
 104450d:	4c 8d 35 3c 33 03 00 	lea    0x3333c(%rip),%r14        # 1077850 <myl_core_free_lists>
 1044514:	e9 a4 f9 ff ff       	jmp    1043ebd <my.json::read_value+0x181d>
 1044519:	48 8d 3d d0 dd 00 00 	lea    0xddd0(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044520:	48 89 d6             	mov    %rdx,%rsi
 1044523:	48 89 c2             	mov    %rax,%rdx
 1044526:	e8 d5 01 fd ff       	call   1014700 <myl_core_trap>
 104452b:	e8 90 c6 ff ff       	call   1040bc0 <myl_core_free_block>
 1044530:	e9 1b fb ff ff       	jmp    1044050 <my.json::read_value+0x19b0>
 1044535:	48 89 ef             	mov    %rbp,%rdi
 1044538:	e8 83 c6 ff ff       	call   1040bc0 <myl_core_free_block>
 104453d:	e9 fc fb ff ff       	jmp    104413e <my.json::read_value+0x1a9e>
 1044542:	48 8d 3d a7 dd 00 00 	lea    0xdda7(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044549:	4c 89 f6             	mov    %r14,%rsi
 104454c:	e8 af 01 fd ff       	call   1014700 <myl_core_trap>
 1044551:	48 8d 3d 98 dd 00 00 	lea    0xdd98(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044558:	4c 89 d6             	mov    %r10,%rsi
 104455b:	48 89 c2             	mov    %rax,%rdx
 104455e:	e8 9d 01 fd ff       	call   1014700 <myl_core_trap>
 1044563:	48 8d 3d 86 dd 00 00 	lea    0xdd86(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104456a:	e8 91 01 fd ff       	call   1014700 <myl_core_trap>
 104456f:	48 8d 3d 7a dd 00 00 	lea    0xdd7a(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044576:	4c 89 fe             	mov    %r15,%rsi
 1044579:	e8 82 01 fd ff       	call   1014700 <myl_core_trap>
 104457e:	48 8d 3d 6b dd 00 00 	lea    0xdd6b(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044585:	4c 89 fe             	mov    %r15,%rsi
 1044588:	e8 73 01 fd ff       	call   1014700 <myl_core_trap>
 104458d:	48 8d 3d 5c dd 00 00 	lea    0xdd5c(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044594:	4c 89 fe             	mov    %r15,%rsi
 1044597:	e8 64 01 fd ff       	call   1014700 <myl_core_trap>
 104459c:	48 89 df             	mov    %rbx,%rdi
 104459f:	e8 1c c6 ff ff       	call   1040bc0 <myl_core_free_block>
 10445a4:	e9 b3 f9 ff ff       	jmp    1043f5c <my.json::read_value+0x18bc>
 10445a9:	4c 89 ff             	mov    %r15,%rdi
 10445ac:	48 89 d3             	mov    %rdx,%rbx
 10445af:	e8 0c c6 ff ff       	call   1040bc0 <myl_core_free_block>
 10445b4:	e9 ab fd ff ff       	jmp    1044364 <my.json::read_value+0x1cc4>
 10445b9:	48 89 ef             	mov    %rbp,%rdi
 10445bc:	e8 ff c5 ff ff       	call   1040bc0 <myl_core_free_block>
 10445c1:	e9 c4 fc ff ff       	jmp    104428a <my.json::read_value+0x1bea>
 10445c6:	e8 f5 c5 ff ff       	call   1040bc0 <myl_core_free_block>
 10445cb:	e9 f0 fb ff ff       	jmp    10441c0 <my.json::read_value+0x1b20>
 10445d0:	e8 eb c5 ff ff       	call   1040bc0 <myl_core_free_block>
 10445d5:	e9 99 fa ff ff       	jmp    1044073 <my.json::read_value+0x19d3>
 10445da:	48 8d 3d 0f dd 00 00 	lea    0xdd0f(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10445e1:	4c 89 f6             	mov    %r14,%rsi
 10445e4:	48 89 c2             	mov    %rax,%rdx
 10445e7:	e8 14 01 fd ff       	call   1014700 <myl_core_trap>
 10445ec:	e8 cf c5 ff ff       	call   1040bc0 <myl_core_free_block>
 10445f1:	e9 32 fd ff ff       	jmp    1044328 <my.json::read_value+0x1c88>
 10445f6:	48 8d 3d f3 dc 00 00 	lea    0xdcf3(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 10445fd:	48 89 d6             	mov    %rdx,%rsi
 1044600:	48 89 c2             	mov    %rax,%rdx
 1044603:	e8 f8 00 fd ff       	call   1014700 <myl_core_trap>
 1044608:	48 8d 3d e1 dc 00 00 	lea    0xdce1(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104460f:	4c 89 fe             	mov    %r15,%rsi
 1044612:	e8 e9 00 fd ff       	call   1014700 <myl_core_trap>
 1044617:	48 8d 3d d2 dc 00 00 	lea    0xdcd2(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104461e:	4c 89 f6             	mov    %r14,%rsi
 1044621:	e8 da 00 fd ff       	call   1014700 <myl_core_trap>
 1044626:	48 8d 3d c3 dc 00 00 	lea    0xdcc3(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 104462d:	4c 89 fe             	mov    %r15,%rsi
 1044630:	e8 cb 00 fd ff       	call   1014700 <myl_core_trap>
 1044635:	e8 86 c5 ff ff       	call   1040bc0 <myl_core_free_block>
 104463a:	e9 2f fd ff ff       	jmp    104436e <my.json::read_value+0x1cce>
 104463f:	48 8d 3d aa dc 00 00 	lea    0xdcaa(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044646:	4c 89 f6             	mov    %r14,%rsi
 1044649:	e8 b2 00 fd ff       	call   1014700 <myl_core_trap>
 104464e:	48 8d 3d 9b dc 00 00 	lea    0xdc9b(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044655:	48 89 c2             	mov    %rax,%rdx
 1044658:	e8 a3 00 fd ff       	call   1014700 <myl_core_trap>
 104465d:	48 8d 3d 8c dc 00 00 	lea    0xdc8c(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044664:	4c 89 fe             	mov    %r15,%rsi
 1044667:	e8 94 00 fd ff       	call   1014700 <myl_core_trap>
 104466c:	48 8d 3d 7d dc 00 00 	lea    0xdc7d(%rip),%rdi        # 10522f0 <core_io_file_error.verbs+0x650>
 1044673:	4c 89 f6             	mov    %r14,%rsi
 1044676:	e8 85 00 fd ff       	call   1014700 <myl_core_trap>

Disassembly of section .plt:
