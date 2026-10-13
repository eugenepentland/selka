
.tmp/lox-eda-parity/P2/direct:     file format elf64-x86-64


Disassembly of section .text:

000000000105b530 <my.vm::run>:
 105b530:	55                   	push   %rbp
 105b531:	41 57                	push   %r15
 105b533:	41 56                	push   %r14
 105b535:	41 55                	push   %r13
 105b537:	41 54                	push   %r12
 105b539:	53                   	push   %rbx
 105b53a:	48 81 ec d8 09 00 00 	sub    $0x9d8,%rsp
 105b541:	48 89 4c 24 78       	mov    %rcx,0x78(%rsp)
 105b546:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
 105b54b:	49 89 f6             	mov    %rsi,%r14
 105b54e:	48 89 7c 24 50       	mov    %rdi,0x50(%rsp)
 105b553:	48 8b 9e 90 00 00 00 	mov    0x90(%rsi),%rbx
 105b55a:	48 89 de             	mov    %rbx,%rsi
 105b55d:	48 ff ce             	dec    %rsi
 105b560:	0f 80 8e 38 00 00    	jo     105edf4 <my.vm::run+0x38c4>
 105b566:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105b56d:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105b574:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b578:	48 39 d6             	cmp    %rdx,%rsi
 105b57b:	0f 83 ca 30 00 00    	jae    105e64b <my.vm::run+0x311b>
 105b581:	48 89 f1             	mov    %rsi,%rcx
 105b584:	48 c1 e1 05          	shl    $0x5,%rcx
 105b588:	4c 8b 54 08 20       	mov    0x20(%rax,%rcx,1),%r10
 105b58d:	4c 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%r11
 105b592:	48 8b 74 08 30       	mov    0x30(%rax,%rcx,1),%rsi
 105b597:	4c 8b 4c 08 38       	mov    0x38(%rax,%rcx,1),%r9
 105b59c:	4c 8d 25 09 be fa ff 	lea    -0x541f7(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105b5a3:	4c 89 b4 24 80 00 00 	mov    %r14,0x80(%rsp)
 105b5aa:	00 
 105b5ab:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 105b5b0:	49 8b 06             	mov    (%r14),%rax
 105b5b3:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b5b7:	4c 89 d9             	mov    %r11,%rcx
 105b5ba:	49 39 d3             	cmp    %rdx,%r11
 105b5bd:	0f 83 8a 28 00 00    	jae    105de4d <my.vm::run+0x291d>
 105b5c3:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105b5c7:	83 7c 08 20 02       	cmpl   $0x2,0x20(%rax,%rcx,1)
 105b5cc:	0f 85 9b 30 00 00    	jne    105e66d <my.vm::run+0x313d>
 105b5d2:	48 01 c8             	add    %rcx,%rax
 105b5d5:	48 83 c0 20          	add    $0x20,%rax
 105b5d9:	48 8b 40 18          	mov    0x18(%rax),%rax
 105b5dd:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b5e1:	48 89 f1             	mov    %rsi,%rcx
 105b5e4:	48 39 d6             	cmp    %rdx,%rsi
 105b5e7:	0f 83 7b 28 00 00    	jae    105de68 <my.vm::run+0x2938>
 105b5ed:	49 89 f7             	mov    %rsi,%r15
 105b5f0:	49 ff c7             	inc    %r15
 105b5f3:	0f 80 80 30 00 00    	jo     105e679 <my.vm::run+0x3149>
 105b5f9:	49 8b 96 88 00 00 00 	mov    0x88(%r14),%rdx
 105b600:	48 8d 6b ff          	lea    -0x1(%rbx),%rbp
 105b604:	48 89 ee             	mov    %rbp,%rsi
 105b607:	48 85 db             	test   %rbx,%rbx
 105b60a:	7f 07                	jg     105b613 <my.vm::run+0xe3>
 105b60c:	48 8b 72 08          	mov    0x8(%rdx),%rsi
 105b610:	48 01 ee             	add    %rbp,%rsi
 105b613:	48 8b 4c c8 20       	mov    0x20(%rax,%rcx,8),%rcx
 105b618:	48 c1 e6 05          	shl    $0x5,%rsi
 105b61c:	4c 89 54 32 20       	mov    %r10,0x20(%rdx,%rsi,1)
 105b621:	4c 89 5c 32 28       	mov    %r11,0x28(%rdx,%rsi,1)
 105b626:	4c 89 7c 32 30       	mov    %r15,0x30(%rdx,%rsi,1)
 105b62b:	4c 89 4c 32 38       	mov    %r9,0x38(%rdx,%rsi,1)
 105b630:	49 89 96 88 00 00 00 	mov    %rdx,0x88(%r14)
 105b637:	48 83 f9 24          	cmp    $0x24,%rcx
 105b63b:	0f 87 df 26 00 00    	ja     105dd20 <my.vm::run+0x27f0>
 105b641:	49 63 04 8c          	movslq (%r12,%rcx,4),%rax
 105b645:	4c 01 e0             	add    %r12,%rax
 105b648:	ff e0                	jmp    *%rax
 105b64a:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105b651:	48 89 c6             	mov    %rax,%rsi
 105b654:	48 ff ce             	dec    %rsi
 105b657:	0f 80 b0 30 00 00    	jo     105e70d <my.vm::run+0x31dd>
 105b65d:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b661:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b665:	48 89 f7             	mov    %rsi,%rdi
 105b668:	48 39 d6             	cmp    %rdx,%rsi
 105b66b:	0f 83 12 28 00 00    	jae    105de83 <my.vm::run+0x2953>
 105b671:	48 c1 e7 04          	shl    $0x4,%rdi
 105b675:	80 7c 38 20 02       	cmpb   $0x2,0x20(%rax,%rdi,1)
 105b67a:	75 5b                	jne    105b6d7 <my.vm::run+0x1a7>
 105b67c:	49 89 f5             	mov    %rsi,%r13
 105b67f:	49 ff cd             	dec    %r13
 105b682:	0f 80 f5 31 00 00    	jo     105e87d <my.vm::run+0x334d>
 105b688:	c5 fb 10 44 38 28    	vmovsd 0x28(%rax,%rdi,1),%xmm0
 105b68e:	4c 89 ee             	mov    %r13,%rsi
 105b691:	49 39 d5             	cmp    %rdx,%r13
 105b694:	0f 83 04 28 00 00    	jae    105de9e <my.vm::run+0x296e>
 105b69a:	48 83 c0 20          	add    $0x20,%rax
 105b69e:	48 c1 e6 04          	shl    $0x4,%rsi
 105b6a2:	80 3c 30 02          	cmpb   $0x2,(%rax,%rsi,1)
 105b6a6:	75 2f                	jne    105b6d7 <my.vm::run+0x1a7>
 105b6a8:	48 01 f0             	add    %rsi,%rax
 105b6ab:	c5 fb 10 48 08       	vmovsd 0x8(%rax),%xmm1
 105b6b0:	48 83 c1 f0          	add    $0xfffffffffffffff0,%rcx
 105b6b4:	48 83 f9 04          	cmp    $0x4,%rcx
 105b6b8:	0f 87 f7 24 00 00    	ja     105dbb5 <my.vm::run+0x2685>
 105b6be:	48 8d 15 c7 bd fa ff 	lea    -0x54239(%rip),%rdx        # 100748c <core_number_pairs+0x22c>
 105b6c5:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 105b6c9:	48 01 d1             	add    %rdx,%rcx
 105b6cc:	ff e1                	jmp    *%rcx
 105b6ce:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 105b6d2:	e9 cb 24 00 00       	jmp    105dba2 <my.vm::run+0x2672>
 105b6d7:	4c 89 e3             	mov    %r12,%rbx
 105b6da:	4d 89 d5             	mov    %r10,%r13
 105b6dd:	4d 89 dc             	mov    %r11,%r12
 105b6e0:	4c 89 cd             	mov    %r9,%rbp
 105b6e3:	48 8d 0d f6 74 fb ff 	lea    -0x48b0a(%rip),%rcx        # 1012be0 <core_number_pairs+0xb980>
 105b6ea:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105b6f1:	00 
 105b6f2:	4c 89 f6             	mov    %r14,%rsi
 105b6f5:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105b6fa:	e8 41 80 00 00       	call   1063740 <my.vm::runtime_error>
 105b6ff:	f6 84 24 88 00 00 00 	testb  $0x1,0x88(%rsp)
 105b706:	01 
 105b707:	0f 84 f4 2e 00 00    	je     105e601 <my.vm::run+0x30d1>
 105b70d:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105b714:	49 8b 8e 90 00 00 00 	mov    0x90(%r14),%rcx
 105b71b:	49 89 e9             	mov    %rbp,%r9
 105b71e:	4d 89 e3             	mov    %r12,%r11
 105b721:	4d 89 ea             	mov    %r13,%r10
 105b724:	49 89 c5             	mov    %rax,%r13
 105b727:	49 89 dc             	mov    %rbx,%r12
 105b72a:	48 89 cb             	mov    %rcx,%rbx
 105b72d:	e9 ee 25 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105b732:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105b739:	49 89 f5             	mov    %rsi,%r13
 105b73c:	49 ff cd             	dec    %r13
 105b73f:	0f 80 44 35 00 00    	jo     105ec89 <my.vm::run+0x3759>
 105b745:	4c 89 ee             	mov    %r13,%rsi
 105b748:	48 ff ce             	dec    %rsi
 105b74b:	0f 80 eb 34 00 00    	jo     105ec3c <my.vm::run+0x370c>
 105b751:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105b755:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105b759:	48 39 d6             	cmp    %rdx,%rsi
 105b75c:	0f 83 10 29 00 00    	jae    105e072 <my.vm::run+0x2b42>
 105b762:	48 89 f0             	mov    %rsi,%rax
 105b765:	48 c1 e0 04          	shl    $0x4,%rax
 105b769:	80 7c 07 20 03       	cmpb   $0x3,0x20(%rdi,%rax,1)
 105b76e:	0f 85 1e 1f 00 00    	jne    105d692 <my.vm::run+0x2162>
 105b774:	48 8b 74 07 28       	mov    0x28(%rdi,%rax,1),%rsi
 105b779:	49 8b 1e             	mov    (%r14),%rbx
 105b77c:	48 8b 43 08          	mov    0x8(%rbx),%rax
 105b780:	48 89 f1             	mov    %rsi,%rcx
 105b783:	48 39 c6             	cmp    %rax,%rsi
 105b786:	0f 83 cc 2b 00 00    	jae    105e358 <my.vm::run+0x2e28>
 105b78c:	48 6b c1 38          	imul   $0x38,%rcx,%rax
 105b790:	83 7c 03 20 06       	cmpl   $0x6,0x20(%rbx,%rax,1)
 105b795:	0f 85 f7 1e 00 00    	jne    105d692 <my.vm::run+0x2162>
 105b79b:	4c 89 e8             	mov    %r13,%rax
 105b79e:	49 39 d5             	cmp    %rdx,%r13
 105b7a1:	0f 83 89 2c 00 00    	jae    105e430 <my.vm::run+0x2f00>
 105b7a7:	4c 89 54 24 10       	mov    %r10,0x10(%rsp)
 105b7ac:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 105b7b1:	4c 89 4c 24 18       	mov    %r9,0x18(%rsp)
 105b7b6:	48 89 7c 24 58       	mov    %rdi,0x58(%rsp)
 105b7bb:	48 8d 57 20          	lea    0x20(%rdi),%rdx
 105b7bf:	48 c1 e0 04          	shl    $0x4,%rax
 105b7c3:	0f b6 0c 02          	movzbl (%rdx,%rax,1),%ecx
 105b7c7:	83 f9 03             	cmp    $0x3,%ecx
 105b7ca:	0f 85 a5 35 00 00    	jne    105ed75 <my.vm::run+0x3845>
 105b7d0:	4c 8b 64 02 08       	mov    0x8(%rdx,%rax,1),%r12
 105b7d5:	4c 89 f7             	mov    %r14,%rdi
 105b7d8:	e8 a3 14 01 00       	call   106cc80 <my.heap::class_obj>
 105b7dd:	4c 89 f7             	mov    %r14,%rdi
 105b7e0:	4c 89 64 24 40       	mov    %r12,0x40(%rsp)
 105b7e5:	4c 89 e6             	mov    %r12,%rsi
 105b7e8:	49 89 d4             	mov    %rdx,%r12
 105b7eb:	e8 90 14 01 00       	call   106cc80 <my.heap::class_obj>
 105b7f0:	49 8b 6c 24 08       	mov    0x8(%r12),%rbp
 105b7f5:	48 85 ed             	test   %rbp,%rbp
 105b7f8:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
 105b7fd:	4c 89 64 24 68       	mov    %r12,0x68(%rsp)
 105b802:	0f 84 d3 23 00 00    	je     105dbdb <my.vm::run+0x26ab>
 105b808:	49 83 c4 38          	add    $0x38,%r12
 105b80c:	eb 3f                	jmp    105b84d <my.vm::run+0x31d>
 105b80e:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105b815:	0f 1f 84 00 00 00 00 
 105b81c:	00 
 105b81d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105b824:	0f 1f 84 00 00 00 00 
 105b82b:	00 
 105b82c:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105b833:	0f 1f 84 00 00 00 00 
 105b83a:	00 
 105b83b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 105b840:	49 83 c4 20          	add    $0x20,%r12
 105b844:	48 ff cd             	dec    %rbp
 105b847:	0f 84 8e 23 00 00    	je     105dbdb <my.vm::run+0x26ab>
 105b84d:	49 8b 44 24 e8       	mov    -0x18(%r12),%rax
 105b852:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 105b856:	74 e8                	je     105b840 <my.vm::run+0x310>
 105b858:	4d 8b 0c 24          	mov    (%r12),%r9
 105b85c:	45 8b 54 24 f0       	mov    -0x10(%r12),%r10d
 105b861:	45 8b 44 24 f8       	mov    -0x8(%r12),%r8d
 105b866:	48 89 d7             	mov    %rdx,%rdi
 105b869:	48 89 ce             	mov    %rcx,%rsi
 105b86c:	48 89 c2             	mov    %rax,%rdx
 105b86f:	44 89 d1             	mov    %r10d,%ecx
 105b872:	e8 89 ef 00 00       	call   106a800 <my.table::set>
 105b877:	eb c7                	jmp    105b840 <my.vm::run+0x310>
 105b879:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105b880:	00 
 105b881:	4c 89 f6             	mov    %r14,%rsi
 105b884:	4c 89 d2             	mov    %r10,%rdx
 105b887:	4c 89 d9             	mov    %r11,%rcx
 105b88a:	4d 89 f8             	mov    %r15,%r8
 105b88d:	e8 2e 83 00 00       	call   1063bc0 <my.vm::read_constant>
 105b892:	0f b6 84 24 88 00 00 	movzbl 0x88(%rsp),%eax
 105b899:	00 
 105b89a:	83 f8 03             	cmp    $0x3,%eax
 105b89d:	0f 85 49 2f 00 00    	jne    105e7ec <my.vm::run+0x32bc>
 105b8a3:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105b8aa:	49 89 f5             	mov    %rsi,%r13
 105b8ad:	49 ff cd             	dec    %r13
 105b8b0:	0f 80 ef 30 00 00    	jo     105e9a5 <my.vm::run+0x3475>
 105b8b6:	4c 89 ee             	mov    %r13,%rsi
 105b8b9:	48 ff ce             	dec    %rsi
 105b8bc:	0f 80 29 32 00 00    	jo     105eaeb <my.vm::run+0x35bb>
 105b8c2:	48 8b 8c 24 b0 00 00 	mov    0xb0(%rsp),%rcx
 105b8c9:	00 
 105b8ca:	4c 8b bc 24 a8 00 00 	mov    0xa8(%rsp),%r15
 105b8d1:	00 
 105b8d2:	48 8b bc 24 a0 00 00 	mov    0xa0(%rsp),%rdi
 105b8d9:	00 
 105b8da:	4c 8b 8c 24 90 00 00 	mov    0x90(%rsp),%r9
 105b8e1:	00 
 105b8e2:	4c 8b 84 24 98 00 00 	mov    0x98(%rsp),%r8
 105b8e9:	00 
 105b8ea:	49 8b 5e 78          	mov    0x78(%r14),%rbx
 105b8ee:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105b8f2:	48 39 d6             	cmp    %rdx,%rsi
 105b8f5:	0f 83 d8 28 00 00    	jae    105e1d3 <my.vm::run+0x2ca3>
 105b8fb:	48 89 f0             	mov    %rsi,%rax
 105b8fe:	4c 89 44 24 10       	mov    %r8,0x10(%rsp)
 105b903:	48 89 7c 24 20       	mov    %rdi,0x20(%rsp)
 105b908:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 105b90d:	48 c1 e0 04          	shl    $0x4,%rax
 105b911:	0f b6 4c 03 20       	movzbl 0x20(%rbx,%rax,1),%ecx
 105b916:	83 f9 03             	cmp    $0x3,%ecx
 105b919:	0f 85 41 2f 00 00    	jne    105e860 <my.vm::run+0x3330>
 105b91f:	4c 8b 64 03 28       	mov    0x28(%rbx,%rax,1),%r12
 105b924:	4c 89 f7             	mov    %r14,%rdi
 105b927:	4c 89 ce             	mov    %r9,%rsi
 105b92a:	4c 89 4c 24 60       	mov    %r9,0x60(%rsp)
 105b92f:	e8 ec ed 00 00       	call   106a720 <my.heap::string_hash>
 105b934:	89 44 24 68          	mov    %eax,0x68(%rsp)
 105b938:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105b93c:	4c 89 e8             	mov    %r13,%rax
 105b93f:	49 39 d5             	cmp    %rdx,%r13
 105b942:	0f 83 c1 28 00 00    	jae    105e209 <my.vm::run+0x2cd9>
 105b948:	48 89 5c 24 58       	mov    %rbx,0x58(%rsp)
 105b94d:	48 8d 4b 20          	lea    0x20(%rbx),%rcx
 105b951:	48 c1 e0 04          	shl    $0x4,%rax
 105b955:	48 8b 5c 01 08       	mov    0x8(%rcx,%rax,1),%rbx
 105b95a:	8b 2c 01             	mov    (%rcx,%rax,1),%ebp
 105b95d:	4c 89 f7             	mov    %r14,%rdi
 105b960:	4c 89 e6             	mov    %r12,%rsi
 105b963:	e8 18 13 01 00       	call   106cc80 <my.heap::class_obj>
 105b968:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
 105b96d:	48 89 d7             	mov    %rdx,%rdi
 105b970:	48 89 ce             	mov    %rcx,%rsi
 105b973:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 105b978:	8b 4c 24 68          	mov    0x68(%rsp),%ecx
 105b97c:	41 89 e8             	mov    %ebp,%r8d
 105b97f:	49 89 d9             	mov    %rbx,%r9
 105b982:	e8 79 ee 00 00       	call   106a800 <my.table::set>
 105b987:	49 8b 36             	mov    (%r14),%rsi
 105b98a:	48 8b 46 08          	mov    0x8(%rsi),%rax
 105b98e:	49 39 c4             	cmp    %rax,%r12
 105b991:	0f 83 8d 28 00 00    	jae    105e224 <my.vm::run+0x2cf4>
 105b997:	4c 89 e7             	mov    %r12,%rdi
 105b99a:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105b99f:	4c 6b d7 38          	imul   $0x38,%rdi,%r10
 105b9a3:	46 0f b6 44 16 20    	movzbl 0x20(%rsi,%r10,1),%r8d
 105b9a9:	4a 8b 7c 16 28       	mov    0x28(%rsi,%r10,1),%rdi
 105b9ae:	4e 8b 4c 16 30       	mov    0x30(%rsi,%r10,1),%r9
 105b9b3:	4a 8b 44 16 38       	mov    0x38(%rsi,%r10,1),%rax
 105b9b8:	4a 8b 5c 16 40       	mov    0x40(%rsi,%r10,1),%rbx
 105b9bd:	4e 8b 64 16 48       	mov    0x48(%rsi,%r10,1),%r12
 105b9c2:	4a c7 44 16 20 06 00 	movq   $0x6,0x20(%rsi,%r10,1)
 105b9c9:	00 00 
 105b9cb:	48 8b 6c 24 40       	mov    0x40(%rsp),%rbp
 105b9d0:	4a 89 6c 16 28       	mov    %rbp,0x28(%rsi,%r10,1)
 105b9d5:	4a 89 54 16 30       	mov    %rdx,0x30(%rsi,%r10,1)
 105b9da:	4a 89 4c 16 38       	mov    %rcx,0x38(%rsi,%r10,1)
 105b9df:	41 83 f8 09          	cmp    $0x9,%r8d
 105b9e3:	77 1c                	ja     105ba01 <my.vm::run+0x4d1>
 105b9e5:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105b9ea:	44 0f a3 c1          	bt     %r8d,%ecx
 105b9ee:	0f 83 e1 1f 00 00    	jae    105d9d5 <my.vm::run+0x24a5>
 105b9f4:	4c 89 cf             	mov    %r9,%rdi
 105b9f7:	e8 04 89 fc ff       	call   1024300 <myl_core_drop_owned>
 105b9fc:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105ba01:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105ba08:	48 8b 44 24 58       	mov    0x58(%rsp),%rax
 105ba0d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ba11:	49 39 d5             	cmp    %rdx,%r13
 105ba14:	0f 83 2a 28 00 00    	jae    105e244 <my.vm::run+0x2d14>
 105ba1a:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105ba21:	4c 8d 25 84 b9 fa ff 	lea    -0x5467c(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105ba28:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105ba2d:	e9 e4 22 00 00       	jmp    105dd16 <my.vm::run+0x27e6>
 105ba32:	48 8d bc 24 e8 01 00 	lea    0x1e8(%rsp),%rdi
 105ba39:	00 
 105ba3a:	4c 89 f6             	mov    %r14,%rsi
 105ba3d:	4c 89 d2             	mov    %r10,%rdx
 105ba40:	4c 89 d9             	mov    %r11,%rcx
 105ba43:	4d 89 f8             	mov    %r15,%r8
 105ba46:	e8 f5 87 00 00       	call   1064240 <my.vm::read_short>
 105ba4b:	4c 89 ee             	mov    %r13,%rsi
 105ba4e:	48 ff ce             	dec    %rsi
 105ba51:	0f 80 a8 30 00 00    	jo     105eaff <my.vm::run+0x35cf>
 105ba57:	48 8b 94 24 e8 01 00 	mov    0x1e8(%rsp),%rdx
 105ba5e:	00 
 105ba5f:	4c 8b 94 24 f0 01 00 	mov    0x1f0(%rsp),%r10
 105ba66:	00 
 105ba67:	4c 8b 9c 24 f8 01 00 	mov    0x1f8(%rsp),%r11
 105ba6e:	00 
 105ba6f:	48 8b 8c 24 00 02 00 	mov    0x200(%rsp),%rcx
 105ba76:	00 
 105ba77:	4c 8b 8c 24 08 02 00 	mov    0x208(%rsp),%r9
 105ba7e:	00 
 105ba7f:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105ba83:	48 8b 47 08          	mov    0x8(%rdi),%rax
 105ba87:	48 39 c6             	cmp    %rax,%rsi
 105ba8a:	0f 83 95 24 00 00    	jae    105df25 <my.vm::run+0x29f5>
 105ba90:	49 89 f0             	mov    %rsi,%r8
 105ba93:	49 89 cf             	mov    %rcx,%r15
 105ba96:	49 c1 e0 04          	shl    $0x4,%r8
 105ba9a:	42 0f b6 44 07 20    	movzbl 0x20(%rdi,%r8,1),%eax
 105baa0:	85 c0                	test   %eax,%eax
 105baa2:	74 1b                	je     105babf <my.vm::run+0x58f>
 105baa4:	83 f8 01             	cmp    $0x1,%eax
 105baa7:	0f 85 73 22 00 00    	jne    105dd20 <my.vm::run+0x27f0>
 105baad:	4a 8d 04 07          	lea    (%rdi,%r8,1),%rax
 105bab1:	48 83 c0 20          	add    $0x20,%rax
 105bab5:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105bab9:	0f 85 61 22 00 00    	jne    105dd20 <my.vm::run+0x27f0>
 105babf:	48 01 d1             	add    %rdx,%rcx
 105bac2:	0f 80 0c 33 00 00    	jo     105edd4 <my.vm::run+0x38a4>
 105bac8:	49 89 cf             	mov    %rcx,%r15
 105bacb:	e9 50 22 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105bad0:	48 8d bc 24 c0 01 00 	lea    0x1c0(%rsp),%rdi
 105bad7:	00 
 105bad8:	4c 89 f6             	mov    %r14,%rsi
 105badb:	4c 89 d2             	mov    %r10,%rdx
 105bade:	4c 89 d9             	mov    %r11,%rcx
 105bae1:	4d 89 f8             	mov    %r15,%r8
 105bae4:	e8 57 87 00 00       	call   1064240 <my.vm::read_short>
 105bae9:	48 8b 94 24 c0 01 00 	mov    0x1c0(%rsp),%rdx
 105baf0:	00 
 105baf1:	48 8b b4 24 d8 01 00 	mov    0x1d8(%rsp),%rsi
 105baf8:	00 
 105baf9:	49 89 f7             	mov    %rsi,%r15
 105bafc:	49 29 d7             	sub    %rdx,%r15
 105baff:	0f 80 e0 31 00 00    	jo     105ece5 <my.vm::run+0x37b5>
 105bb05:	4c 8b 94 24 c8 01 00 	mov    0x1c8(%rsp),%r10
 105bb0c:	00 
 105bb0d:	4c 8b 9c 24 d0 01 00 	mov    0x1d0(%rsp),%r11
 105bb14:	00 
 105bb15:	4c 8b 8c 24 e0 01 00 	mov    0x1e0(%rsp),%r9
 105bb1c:	00 
 105bb1d:	e9 fe 21 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105bb22:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105bb29:	00 
 105bb2a:	4c 89 f6             	mov    %r14,%rsi
 105bb2d:	4c 89 d2             	mov    %r10,%rdx
 105bb30:	4c 89 d9             	mov    %r11,%rcx
 105bb33:	4d 89 f8             	mov    %r15,%r8
 105bb36:	e8 85 80 00 00       	call   1063bc0 <my.vm::read_constant>
 105bb3b:	0f b6 84 24 88 00 00 	movzbl 0x88(%rsp),%eax
 105bb42:	00 
 105bb43:	83 f8 03             	cmp    $0x3,%eax
 105bb46:	0f 85 66 2c 00 00    	jne    105e7b2 <my.vm::run+0x3282>
 105bb4c:	48 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%rax
 105bb53:	00 
 105bb54:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105bb59:	4c 8b bc 24 a8 00 00 	mov    0xa8(%rsp),%r15
 105bb60:	00 
 105bb61:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
 105bb68:	00 
 105bb69:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105bb6e:	48 8b 84 24 90 00 00 	mov    0x90(%rsp),%rax
 105bb75:	00 
 105bb76:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105bb7b:	48 8b ac 24 98 00 00 	mov    0x98(%rsp),%rbp
 105bb82:	00 
 105bb83:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105bb8a:	00 
 105bb8b:	ba 30 00 00 00       	mov    $0x30,%edx
 105bb90:	4c 89 f6             	mov    %r14,%rsi
 105bb93:	e8 f8 65 00 00       	call   1062190 <my.heap::reserve_object>
 105bb98:	48 8b 9c 24 88 00 00 	mov    0x88(%rsp),%rbx
 105bb9f:	00 
 105bba0:	64 48 8b 04 25 c8 fe 	mov    %fs:0xfffffffffffffec8,%rax
 105bba7:	ff ff 
 105bba9:	48 85 c0             	test   %rax,%rax
 105bbac:	0f 84 69 25 00 00    	je     105e11b <my.vm::run+0x2beb>
 105bbb2:	48 8b 08             	mov    (%rax),%rcx
 105bbb5:	64 48 89 0c 25 c8 fe 	mov    %rcx,%fs:0xfffffffffffffec8
 105bbbc:	ff ff 
 105bbbe:	c7 00 00 00 00 01    	movl   $0x1000000,(%rax)
 105bbc4:	c5 f9 57 c0          	vxorpd %xmm0,%xmm0,%xmm0
 105bbc8:	c5 f9 11 40 08       	vmovupd %xmm0,0x8(%rax)
 105bbcd:	48 c7 40 18 00 00 00 	movq   $0x0,0x18(%rax)
 105bbd4:	00 
 105bbd5:	49 8b 36             	mov    (%r14),%rsi
 105bbd8:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105bbdc:	48 89 d9             	mov    %rbx,%rcx
 105bbdf:	48 39 d3             	cmp    %rdx,%rbx
 105bbe2:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105bbe7:	49 89 ea             	mov    %rbp,%r10
 105bbea:	0f 83 3c 25 00 00    	jae    105e12c <my.vm::run+0x2bfc>
 105bbf0:	4c 6b c9 38          	imul   $0x38,%rcx,%r9
 105bbf4:	42 0f b6 54 0e 20    	movzbl 0x20(%rsi,%r9,1),%edx
 105bbfa:	4a 8b 7c 0e 28       	mov    0x28(%rsi,%r9,1),%rdi
 105bbff:	4e 8b 44 0e 30       	mov    0x30(%rsi,%r9,1),%r8
 105bc04:	4a 8b 4c 0e 38       	mov    0x38(%rsi,%r9,1),%rcx
 105bc09:	4e 8b 64 0e 40       	mov    0x40(%rsi,%r9,1),%r12
 105bc0e:	4e 8b 6c 0e 48       	mov    0x48(%rsi,%r9,1),%r13
 105bc13:	4c 89 6c 24 58       	mov    %r13,0x58(%rsp)
 105bc18:	4a c7 44 0e 20 06 00 	movq   $0x6,0x20(%rsi,%r9,1)
 105bc1f:	00 00 
 105bc21:	4c 8b 6c 24 10       	mov    0x10(%rsp),%r13
 105bc26:	4e 89 6c 0e 28       	mov    %r13,0x28(%rsi,%r9,1)
 105bc2b:	4a 89 44 0e 30       	mov    %rax,0x30(%rsi,%r9,1)
 105bc30:	4a c7 44 0e 38 00 00 	movq   $0x0,0x38(%rsi,%r9,1)
 105bc37:	00 00 
 105bc39:	83 fa 09             	cmp    $0x9,%edx
 105bc3c:	77 1e                	ja     105bc5c <my.vm::run+0x72c>
 105bc3e:	b8 d0 02 00 00       	mov    $0x2d0,%eax
 105bc43:	0f a3 d0             	bt     %edx,%eax
 105bc46:	0f 83 5d 1d 00 00    	jae    105d9a9 <my.vm::run+0x2479>
 105bc4c:	4c 89 c7             	mov    %r8,%rdi
 105bc4f:	e8 ac 86 fc ff       	call   1024300 <myl_core_drop_owned>
 105bc54:	49 89 ea             	mov    %rbp,%r10
 105bc57:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105bc5c:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bc60:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105bc67:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bc6b:	48 39 d6             	cmp    %rdx,%rsi
 105bc6e:	4c 8d 25 37 b7 fa ff 	lea    -0x548c9(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105bc75:	0f 83 cc 24 00 00    	jae    105e147 <my.vm::run+0x2c17>
 105bc7b:	48 89 f1             	mov    %rsi,%rcx
 105bc7e:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105bc83:	48 c1 e1 04          	shl    $0x4,%rcx
 105bc87:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 105bc8e:	00 00 
 105bc90:	48 89 5c 08 28       	mov    %rbx,0x28(%rax,%rcx,1)
 105bc95:	49 89 46 78          	mov    %rax,0x78(%r14)
 105bc99:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105bca0:	49 89 f5             	mov    %rsi,%r13
 105bca3:	49 ff c5             	inc    %r13
 105bca6:	0f 81 1c 1f 00 00    	jno    105dbc8 <my.vm::run+0x2698>
 105bcac:	e9 66 2f 00 00       	jmp    105ec17 <my.vm::run+0x36e7>
 105bcb1:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105bcb8:	00 
 105bcb9:	4c 89 f6             	mov    %r14,%rsi
 105bcbc:	4c 89 d2             	mov    %r10,%rdx
 105bcbf:	4c 89 d9             	mov    %r11,%rcx
 105bcc2:	4d 89 f8             	mov    %r15,%r8
 105bcc5:	e8 f6 7e 00 00       	call   1063bc0 <my.vm::read_constant>
 105bcca:	0f b6 84 24 88 00 00 	movzbl 0x88(%rsp),%eax
 105bcd1:	00 
 105bcd2:	83 f8 03             	cmp    $0x3,%eax
 105bcd5:	0f 85 2e 2b 00 00    	jne    105e809 <my.vm::run+0x32d9>
 105bcdb:	4c 89 ee             	mov    %r13,%rsi
 105bcde:	48 ff ce             	dec    %rsi
 105bce1:	0f 80 d0 2e 00 00    	jo     105ebb7 <my.vm::run+0x3687>
 105bce7:	48 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%rbp
 105bcee:	00 
 105bcef:	4c 8b bc 24 a8 00 00 	mov    0xa8(%rsp),%r15
 105bcf6:	00 
 105bcf7:	4c 8b a4 24 a0 00 00 	mov    0xa0(%rsp),%r12
 105bcfe:	00 
 105bcff:	4c 8b 84 24 90 00 00 	mov    0x90(%rsp),%r8
 105bd06:	00 
 105bd07:	48 8b bc 24 98 00 00 	mov    0x98(%rsp),%rdi
 105bd0e:	00 
 105bd0f:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105bd16:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bd1a:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bd1e:	48 39 d6             	cmp    %rdx,%rsi
 105bd21:	0f 83 5b 24 00 00    	jae    105e182 <my.vm::run+0x2c52>
 105bd27:	48 89 f1             	mov    %rsi,%rcx
 105bd2a:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 105bd2f:	48 c1 e1 04          	shl    $0x4,%rcx
 105bd33:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 105bd38:	83 fa 03             	cmp    $0x3,%edx
 105bd3b:	0f 85 e0 29 00 00    	jne    105e721 <my.vm::run+0x31f1>
 105bd41:	48 01 c8             	add    %rcx,%rax
 105bd44:	48 83 c0 20          	add    $0x20,%rax
 105bd48:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105bd4c:	48 8d bc 24 e8 08 00 	lea    0x8e8(%rsp),%rdi
 105bd53:	00 
 105bd54:	4c 89 f6             	mov    %r14,%rsi
 105bd57:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105bd5c:	e8 ff 7f 00 00       	call   1063d60 <my.vm::bind_method>
 105bd61:	f6 84 24 e8 08 00 00 	testb  $0x1,0x8e8(%rsp)
 105bd68:	01 
 105bd69:	0f 84 92 28 00 00    	je     105e601 <my.vm::run+0x30d1>
 105bd6f:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105bd76:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105bd7d:	49 89 e9             	mov    %rbp,%r9
 105bd80:	4d 89 e3             	mov    %r12,%r11
 105bd83:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105bd88:	4c 8d 25 1d b6 fa ff 	lea    -0x549e3(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105bd8f:	e9 8c 1f 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105bd94:	4c 89 ee             	mov    %r13,%rsi
 105bd97:	48 ff ce             	dec    %rsi
 105bd9a:	0f 80 e2 2c 00 00    	jo     105ea82 <my.vm::run+0x3552>
 105bda0:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105bda7:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bdab:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bdaf:	48 39 d6             	cmp    %rdx,%rsi
 105bdb2:	0f 83 88 21 00 00    	jae    105df40 <my.vm::run+0x2a10>
 105bdb8:	48 89 f1             	mov    %rsi,%rcx
 105bdbb:	48 c1 e1 04          	shl    $0x4,%rcx
 105bdbf:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105bdc5:	c5 f9 29 44 24 20    	vmovapd %xmm0,0x20(%rsp)
 105bdcb:	4c 89 f7             	mov    %r14,%rdi
 105bdce:	4d 89 cd             	mov    %r9,%r13
 105bdd1:	4c 89 ce             	mov    %r9,%rsi
 105bdd4:	e8 17 8e 00 00       	call   1064bf0 <my.vm::close_upvalues>
 105bdd9:	49 8b b6 90 00 00 00 	mov    0x90(%r14),%rsi
 105bde0:	48 89 f3             	mov    %rsi,%rbx
 105bde3:	48 ff cb             	dec    %rbx
 105bde6:	0f 80 60 2c 00 00    	jo     105ea4c <my.vm::run+0x351c>
 105bdec:	49 89 9e 90 00 00 00 	mov    %rbx,0x90(%r14)
 105bdf3:	0f 84 27 28 00 00    	je     105e620 <my.vm::run+0x30f0>
 105bdf9:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105be00:	49 8b 46 78          	mov    0x78(%r14),%rax
 105be04:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105be08:	4c 89 e9             	mov    %r13,%rcx
 105be0b:	49 39 d5             	cmp    %rdx,%r13
 105be0e:	0f 83 81 24 00 00    	jae    105e295 <my.vm::run+0x2d65>
 105be14:	48 c1 e1 04          	shl    $0x4,%rcx
 105be18:	c5 f9 28 44 24 20    	vmovapd 0x20(%rsp),%xmm0
 105be1e:	c5 f9 54 05 ba 85 fa 	vandpd -0x57a46(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105be25:	ff 
 105be26:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 105be2c:	49 89 46 78          	mov    %rax,0x78(%r14)
 105be30:	49 ff c5             	inc    %r13
 105be33:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105be3a:	48 89 de             	mov    %rbx,%rsi
 105be3d:	48 ff ce             	dec    %rsi
 105be40:	0f 80 d3 2e 00 00    	jo     105ed19 <my.vm::run+0x37e9>
 105be46:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105be4d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105be51:	48 39 d6             	cmp    %rdx,%rsi
 105be54:	0f 82 a7 18 00 00    	jb     105d701 <my.vm::run+0x21d1>
 105be5a:	48 89 f1             	mov    %rsi,%rcx
 105be5d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105be61:	48 21 d1             	and    %rdx,%rcx
 105be64:	48 01 f1             	add    %rsi,%rcx
 105be67:	48 39 d1             	cmp    %rdx,%rcx
 105be6a:	0f 82 94 18 00 00    	jb     105d704 <my.vm::run+0x21d4>
 105be70:	e9 3c 32 00 00       	jmp    105f0b1 <my.vm::run+0x3b81>
 105be75:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105be7c:	00 
 105be7d:	4c 89 f6             	mov    %r14,%rsi
 105be80:	4c 89 d2             	mov    %r10,%rdx
 105be83:	4c 89 d9             	mov    %r11,%rcx
 105be86:	4d 89 f8             	mov    %r15,%r8
 105be89:	e8 12 7e 00 00       	call   1063ca0 <my.vm::read_byte>
 105be8e:	48 8b 94 24 88 00 00 	mov    0x88(%rsp),%rdx
 105be95:	00 
 105be96:	48 8b b4 24 90 00 00 	mov    0x90(%rsp),%rsi
 105be9d:	00 
 105be9e:	48 8b ac 24 98 00 00 	mov    0x98(%rsp),%rbp
 105bea5:	00 
 105bea6:	4c 8b bc 24 a0 00 00 	mov    0xa0(%rsp),%r15
 105bead:	00 
 105beae:	4c 8b ac 24 a8 00 00 	mov    0xa8(%rsp),%r13
 105beb5:	00 
 105beb6:	4c 89 f7             	mov    %r14,%rdi
 105beb9:	49 89 f4             	mov    %rsi,%r12
 105bebc:	e8 2f ed 00 00       	call   106abf0 <my.heap::closure_upvalue>
 105bec1:	48 89 c3             	mov    %rax,%rbx
 105bec4:	48 8d bc 24 20 03 00 	lea    0x320(%rsp),%rdi
 105becb:	00 
 105becc:	4c 89 f6             	mov    %r14,%rsi
 105becf:	48 89 c2             	mov    %rax,%rdx
 105bed2:	e8 19 ec 00 00       	call   106aaf0 <my.heap::upvalue_obj>
 105bed7:	48 8b 84 24 20 03 00 	mov    0x320(%rsp),%rax
 105bede:	00 
 105bedf:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105bee3:	49 8b 8e 80 00 00 00 	mov    0x80(%r14),%rcx
 105beea:	48 89 ce             	mov    %rcx,%rsi
 105beed:	48 ff ce             	dec    %rsi
 105bef0:	0f 90 c2             	seto   %dl
 105bef3:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 105bef7:	0f 84 d3 18 00 00    	je     105d7d0 <my.vm::run+0x22a0>
 105befd:	84 d2                	test   %dl,%dl
 105beff:	0f 85 aa 2e 00 00    	jne    105edaf <my.vm::run+0x387f>
 105bf05:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105bf09:	48 39 d6             	cmp    %rdx,%rsi
 105bf0c:	4d 89 e9             	mov    %r13,%r9
 105bf0f:	49 89 eb             	mov    %rbp,%r11
 105bf12:	4d 89 e2             	mov    %r12,%r10
 105bf15:	0f 83 ec 23 00 00    	jae    105e307 <my.vm::run+0x2dd7>
 105bf1b:	48 89 f1             	mov    %rsi,%rcx
 105bf1e:	48 c1 e1 04          	shl    $0x4,%rcx
 105bf22:	c5 f9 10 44 0f 20    	vmovupd 0x20(%rdi,%rcx,1),%xmm0
 105bf28:	48 39 d0             	cmp    %rdx,%rax
 105bf2b:	0f 83 f1 23 00 00    	jae    105e322 <my.vm::run+0x2df2>
 105bf31:	48 89 c1             	mov    %rax,%rcx
 105bf34:	48 83 c7 20          	add    $0x20,%rdi
 105bf38:	48 c1 e1 04          	shl    $0x4,%rcx
 105bf3c:	c5 f9 54 05 9c 84 fa 	vandpd -0x57b64(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105bf43:	ff 
 105bf44:	c5 f9 11 04 0f       	vmovupd %xmm0,(%rdi,%rcx,1)
 105bf49:	e9 41 1a 00 00       	jmp    105d98f <my.vm::run+0x245f>
 105bf4e:	4c 89 ee             	mov    %r13,%rsi
 105bf51:	48 ff ce             	dec    %rsi
 105bf54:	0f 80 1b 2d 00 00    	jo     105ec75 <my.vm::run+0x3745>
 105bf5a:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105bf61:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bf65:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bf69:	48 39 d6             	cmp    %rdx,%rsi
 105bf6c:	0f 83 e9 1f 00 00    	jae    105df5b <my.vm::run+0x2a2b>
 105bf72:	49 89 f5             	mov    %rsi,%r13
 105bf75:	e9 a6 1d 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105bf7a:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105bf81:	49 89 f5             	mov    %rsi,%r13
 105bf84:	49 ff cd             	dec    %r13
 105bf87:	0f 80 d7 2c 00 00    	jo     105ec64 <my.vm::run+0x3734>
 105bf8d:	49 8b 6e 78          	mov    0x78(%r14),%rbp
 105bf91:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105bf95:	4d 89 ec             	mov    %r13,%r12
 105bf98:	49 39 d5             	cmp    %rdx,%r13
 105bf9b:	0f 83 d5 1f 00 00    	jae    105df76 <my.vm::run+0x2a46>
 105bfa1:	49 c1 e4 04          	shl    $0x4,%r12
 105bfa5:	42 80 7c 25 20 03    	cmpb   $0x3,0x20(%rbp,%r12,1)
 105bfab:	0f 85 8b 16 00 00    	jne    105d63c <my.vm::run+0x210c>
 105bfb1:	4a 8b 74 25 28       	mov    0x28(%rbp,%r12,1),%rsi
 105bfb6:	49 8b 06             	mov    (%r14),%rax
 105bfb9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bfbd:	48 89 f1             	mov    %rsi,%rcx
 105bfc0:	48 39 d6             	cmp    %rdx,%rsi
 105bfc3:	0f 83 74 23 00 00    	jae    105e33d <my.vm::run+0x2e0d>
 105bfc9:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105bfcd:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 105bfd2:	0f 85 64 16 00 00    	jne    105d63c <my.vm::run+0x210c>
 105bfd8:	48 89 74 24 58       	mov    %rsi,0x58(%rsp)
 105bfdd:	48 8d bc 24 28 05 00 	lea    0x528(%rsp),%rdi
 105bfe4:	00 
 105bfe5:	4c 89 f6             	mov    %r14,%rsi
 105bfe8:	4c 89 d2             	mov    %r10,%rdx
 105bfeb:	4c 89 d9             	mov    %r11,%rcx
 105bfee:	4d 89 f8             	mov    %r15,%r8
 105bff1:	e8 ca 7b 00 00       	call   1063bc0 <my.vm::read_constant>
 105bff6:	0f b6 84 24 28 05 00 	movzbl 0x528(%rsp),%eax
 105bffd:	00 
 105bffe:	83 f8 03             	cmp    $0x3,%eax
 105c001:	0f 85 8b 2d 00 00    	jne    105ed92 <my.vm::run+0x3862>
 105c007:	48 8b 84 24 50 05 00 	mov    0x550(%rsp),%rax
 105c00e:	00 
 105c00f:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105c014:	4c 8b bc 24 48 05 00 	mov    0x548(%rsp),%r15
 105c01b:	00 
 105c01c:	48 8b 84 24 40 05 00 	mov    0x540(%rsp),%rax
 105c023:	00 
 105c024:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105c029:	48 8b 9c 24 30 05 00 	mov    0x530(%rsp),%rbx
 105c030:	00 
 105c031:	48 8b 84 24 38 05 00 	mov    0x538(%rsp),%rax
 105c038:	00 
 105c039:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105c03e:	4c 89 f7             	mov    %r14,%rdi
 105c041:	48 89 de             	mov    %rbx,%rsi
 105c044:	e8 d7 e6 00 00       	call   106a720 <my.heap::string_hash>
 105c049:	4c 89 f7             	mov    %r14,%rdi
 105c04c:	48 8b 74 24 58       	mov    0x58(%rsp),%rsi
 105c051:	48 89 5c 24 40       	mov    %rbx,0x40(%rsp)
 105c056:	48 89 da             	mov    %rbx,%rdx
 105c059:	89 c1                	mov    %eax,%ecx
 105c05b:	e8 a0 ec 00 00       	call   106ad00 <my.heap::instance_field>
 105c060:	3c 01                	cmp    $0x1,%al
 105c062:	0f 85 f9 1c 00 00    	jne    105dd61 <my.vm::run+0x2831>
 105c068:	49 8d 04 2c          	lea    (%r12,%rbp,1),%rax
 105c06c:	48 83 c0 20          	add    $0x20,%rax
 105c070:	0f b6 d2             	movzbl %dl,%edx
 105c073:	48 89 10             	mov    %rdx,(%rax)
 105c076:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105c07a:	49 ff c5             	inc    %r13
 105c07d:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105c084:	e9 68 01 00 00       	jmp    105c1f1 <my.vm::run+0xcc1>
 105c089:	48 8d bc 24 40 03 00 	lea    0x340(%rsp),%rdi
 105c090:	00 
 105c091:	4c 89 f6             	mov    %r14,%rsi
 105c094:	4c 89 d2             	mov    %r10,%rdx
 105c097:	4c 89 d9             	mov    %r11,%rcx
 105c09a:	4d 89 f8             	mov    %r15,%r8
 105c09d:	e8 1e 7b 00 00       	call   1063bc0 <my.vm::read_constant>
 105c0a2:	0f b6 84 24 40 03 00 	movzbl 0x340(%rsp),%eax
 105c0a9:	00 
 105c0aa:	83 f8 03             	cmp    $0x3,%eax
 105c0ad:	0f 85 e2 26 00 00    	jne    105e795 <my.vm::run+0x3265>
 105c0b3:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105c0ba:	48 89 c6             	mov    %rax,%rsi
 105c0bd:	48 ff ce             	dec    %rsi
 105c0c0:	0f 80 11 2a 00 00    	jo     105ead7 <my.vm::run+0x35a7>
 105c0c6:	48 8b 8c 24 68 03 00 	mov    0x368(%rsp),%rcx
 105c0cd:	00 
 105c0ce:	4c 8b bc 24 60 03 00 	mov    0x360(%rsp),%r15
 105c0d5:	00 
 105c0d6:	48 8b bc 24 58 03 00 	mov    0x358(%rsp),%rdi
 105c0dd:	00 
 105c0de:	48 8b 9c 24 48 03 00 	mov    0x348(%rsp),%rbx
 105c0e5:	00 
 105c0e6:	4c 8b 84 24 50 03 00 	mov    0x350(%rsp),%r8
 105c0ed:	00 
 105c0ee:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c0f2:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c0f6:	48 39 d6             	cmp    %rdx,%rsi
 105c0f9:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 105c0fe:	48 89 7c 24 20       	mov    %rdi,0x20(%rsp)
 105c103:	4c 89 44 24 10       	mov    %r8,0x10(%rsp)
 105c108:	0f 83 8f 20 00 00    	jae    105e19d <my.vm::run+0x2c6d>
 105c10e:	48 89 f1             	mov    %rsi,%rcx
 105c111:	48 c1 e1 04          	shl    $0x4,%rcx
 105c115:	4c 8b 64 08 28       	mov    0x28(%rax,%rcx,1),%r12
 105c11a:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 105c11e:	4c 89 f7             	mov    %r14,%rdi
 105c121:	48 89 de             	mov    %rbx,%rsi
 105c124:	e8 f7 e5 00 00       	call   106a720 <my.heap::string_hash>
 105c129:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105c12d:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105c131:	48 89 da             	mov    %rbx,%rdx
 105c134:	89 c1                	mov    %eax,%ecx
 105c136:	41 89 e8             	mov    %ebp,%r8d
 105c139:	4d 89 e1             	mov    %r12,%r9
 105c13c:	e8 bf e6 00 00       	call   106a800 <my.table::set>
 105c141:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105c145:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105c149:	a8 01                	test   $0x1,%al
 105c14b:	0f 84 99 00 00 00    	je     105c1ea <my.vm::run+0xcba>
 105c151:	49 89 d4             	mov    %rdx,%r12
 105c154:	49 89 cd             	mov    %rcx,%r13
 105c157:	4c 89 f7             	mov    %r14,%rdi
 105c15a:	48 89 de             	mov    %rbx,%rsi
 105c15d:	e8 be e5 00 00       	call   106a720 <my.heap::string_hash>
 105c162:	4c 89 e7             	mov    %r12,%rdi
 105c165:	4c 89 ee             	mov    %r13,%rsi
 105c168:	48 89 da             	mov    %rbx,%rdx
 105c16b:	89 c1                	mov    %eax,%ecx
 105c16d:	e8 7e e8 00 00       	call   106a9f0 <my.table::delete>
 105c172:	49 89 46 30          	mov    %rax,0x30(%r14)
 105c176:	49 89 56 38          	mov    %rdx,0x38(%r14)
 105c17a:	4c 89 f7             	mov    %r14,%rdi
 105c17d:	48 89 de             	mov    %rbx,%rsi
 105c180:	e8 ab e3 00 00       	call   106a530 <my.heap::string_chars>
 105c185:	48 89 c3             	mov    %rax,%rbx
 105c188:	48 8d 3d 51 69 fb ff 	lea    -0x496af(%rip),%rdi        # 1012ae0 <core_number_pairs+0xb880>
 105c18f:	48 89 c6             	mov    %rax,%rsi
 105c192:	e8 69 35 fd ff       	call   102f700 <myl_core_bytes_concat>
 105c197:	49 89 c4             	mov    %rax,%r12
 105c19a:	48 89 df             	mov    %rbx,%rdi
 105c19d:	e8 5e 81 fc ff       	call   1024300 <myl_core_drop_owned>
 105c1a2:	48 8d 35 77 69 fb ff 	lea    -0x49689(%rip),%rsi        # 1012b20 <core_number_pairs+0xb8c0>
 105c1a9:	4c 89 e7             	mov    %r12,%rdi
 105c1ac:	e8 4f 35 fd ff       	call   102f700 <myl_core_bytes_concat>
 105c1b1:	48 89 c3             	mov    %rax,%rbx
 105c1b4:	4c 89 e7             	mov    %r12,%rdi
 105c1b7:	e8 44 81 fc ff       	call   1024300 <myl_core_drop_owned>
 105c1bc:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105c1c3:	00 
 105c1c4:	4c 89 f6             	mov    %r14,%rsi
 105c1c7:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105c1cc:	48 89 d9             	mov    %rbx,%rcx
 105c1cf:	e8 6c 75 00 00       	call   1063740 <my.vm::runtime_error>
 105c1d4:	48 89 df             	mov    %rbx,%rdi
 105c1d7:	e8 24 81 fc ff       	call   1024300 <myl_core_drop_owned>
 105c1dc:	f6 84 24 88 00 00 00 	testb  $0x1,0x88(%rsp)
 105c1e3:	01 
 105c1e4:	0f 84 17 24 00 00    	je     105e601 <my.vm::run+0x30d1>
 105c1ea:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105c1f1:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105c1f8:	4c 8d 25 ad b1 fa ff 	lea    -0x54e53(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105c1ff:	e9 84 14 00 00       	jmp    105d688 <my.vm::run+0x2158>
 105c204:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c208:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c20c:	4c 89 e9             	mov    %r13,%rcx
 105c20f:	49 39 d5             	cmp    %rdx,%r13
 105c212:	0f 83 a1 1c 00 00    	jae    105deb9 <my.vm::run+0x2989>
 105c218:	48 c1 e1 04          	shl    $0x4,%rcx
 105c21c:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105c223:	00 00 
 105c225:	c6 44 08 28 01       	movb   $0x1,0x28(%rax,%rcx,1)
 105c22a:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c22e:	4c 89 e8             	mov    %r13,%rax
 105c231:	48 ff c0             	inc    %rax
 105c234:	0f 81 af 03 00 00    	jno    105c5e9 <my.vm::run+0x10b9>
 105c23a:	e9 b2 29 00 00       	jmp    105ebf1 <my.vm::run+0x36c1>
 105c23f:	4c 89 ee             	mov    %r13,%rsi
 105c242:	48 ff ce             	dec    %rsi
 105c245:	0f 80 58 29 00 00    	jo     105eba3 <my.vm::run+0x3673>
 105c24b:	4c 89 e5             	mov    %r12,%rbp
 105c24e:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105c255:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c259:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c25d:	48 89 f1             	mov    %rsi,%rcx
 105c260:	48 39 d6             	cmp    %rdx,%rsi
 105c263:	0f 83 28 1d 00 00    	jae    105df91 <my.vm::run+0x2a61>
 105c269:	49 89 f5             	mov    %rsi,%r13
 105c26c:	49 ff cd             	dec    %r13
 105c26f:	0f 80 c6 27 00 00    	jo     105ea3b <my.vm::run+0x350b>
 105c275:	4d 89 d4             	mov    %r10,%r12
 105c278:	4d 89 ca             	mov    %r9,%r10
 105c27b:	48 c1 e1 04          	shl    $0x4,%rcx
 105c27f:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105c285:	48 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%rdi
 105c28a:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105c291:	4c 89 e9             	mov    %r13,%rcx
 105c294:	49 39 d5             	cmp    %rdx,%r13
 105c297:	0f 83 f0 1d 00 00    	jae    105e08d <my.vm::run+0x2b5d>
 105c29d:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105c2a1:	48 c1 e1 04          	shl    $0x4,%rcx
 105c2a5:	44 0f b6 0c 0a       	movzbl (%rdx,%rcx,1),%r9d
 105c2aa:	48 8b 74 0a 08       	mov    0x8(%rdx,%rcx,1),%rsi
 105c2af:	41 83 f9 02          	cmp    $0x2,%r9d
 105c2b3:	0f 84 7b 18 00 00    	je     105db34 <my.vm::run+0x2604>
 105c2b9:	41 83 f9 01          	cmp    $0x1,%r9d
 105c2bd:	0f 84 59 18 00 00    	je     105db1c <my.vm::run+0x25ec>
 105c2c3:	45 85 c9             	test   %r9d,%r9d
 105c2c6:	0f 85 9b 18 00 00    	jne    105db67 <my.vm::run+0x2637>
 105c2cc:	45 84 c0             	test   %r8b,%r8b
 105c2cf:	40 0f 94 c6          	sete   %sil
 105c2d3:	e9 d5 19 00 00       	jmp    105dcad <my.vm::run+0x277d>
 105c2d8:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c2dc:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c2e0:	4c 89 e9             	mov    %r13,%rcx
 105c2e3:	49 39 d5             	cmp    %rdx,%r13
 105c2e6:	0f 83 e8 1b 00 00    	jae    105ded4 <my.vm::run+0x29a4>
 105c2ec:	48 c1 e1 04          	shl    $0x4,%rcx
 105c2f0:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105c2f7:	00 00 
 105c2f9:	c6 44 08 28 00       	movb   $0x0,0x28(%rax,%rcx,1)
 105c2fe:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c302:	4c 89 e8             	mov    %r13,%rax
 105c305:	48 ff c0             	inc    %rax
 105c308:	0f 81 db 02 00 00    	jno    105c5e9 <my.vm::run+0x10b9>
 105c30e:	e9 de 29 00 00       	jmp    105ecf1 <my.vm::run+0x37c1>
 105c313:	48 8d bc 24 40 03 00 	lea    0x340(%rsp),%rdi
 105c31a:	00 
 105c31b:	4c 89 f6             	mov    %r14,%rsi
 105c31e:	4c 89 d2             	mov    %r10,%rdx
 105c321:	4c 89 d9             	mov    %r11,%rcx
 105c324:	4d 89 f8             	mov    %r15,%r8
 105c327:	e8 94 78 00 00       	call   1063bc0 <my.vm::read_constant>
 105c32c:	0f b6 84 24 40 03 00 	movzbl 0x340(%rsp),%eax
 105c333:	00 
 105c334:	83 f8 03             	cmp    $0x3,%eax
 105c337:	0f 85 3b 24 00 00    	jne    105e778 <my.vm::run+0x3248>
 105c33d:	48 8b 84 24 68 03 00 	mov    0x368(%rsp),%rax
 105c344:	00 
 105c345:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105c34a:	4c 8b bc 24 60 03 00 	mov    0x360(%rsp),%r15
 105c351:	00 
 105c352:	48 8b 84 24 58 03 00 	mov    0x358(%rsp),%rax
 105c359:	00 
 105c35a:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105c35f:	48 8b 9c 24 48 03 00 	mov    0x348(%rsp),%rbx
 105c366:	00 
 105c367:	48 8b ac 24 50 03 00 	mov    0x350(%rsp),%rbp
 105c36e:	00 
 105c36f:	4d 8b 66 30          	mov    0x30(%r14),%r12
 105c373:	4d 8b 6e 38          	mov    0x38(%r14),%r13
 105c377:	4c 89 f7             	mov    %r14,%rdi
 105c37a:	48 89 de             	mov    %rbx,%rsi
 105c37d:	e8 9e e3 00 00       	call   106a720 <my.heap::string_hash>
 105c382:	4c 89 e7             	mov    %r12,%rdi
 105c385:	4c 89 ee             	mov    %r13,%rsi
 105c388:	48 89 da             	mov    %rbx,%rdx
 105c38b:	89 c1                	mov    %eax,%ecx
 105c38d:	e8 7e e2 00 00       	call   106a610 <my.table::get>
 105c392:	3c 01                	cmp    $0x1,%al
 105c394:	0f 85 9f 13 00 00    	jne    105d739 <my.vm::run+0x2209>
 105c39a:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105c39e:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105c3a5:	48 8b 47 08          	mov    0x8(%rdi),%rax
 105c3a9:	49 89 f0             	mov    %rsi,%r8
 105c3ac:	48 39 c6             	cmp    %rax,%rsi
 105c3af:	0f 83 be 1f 00 00    	jae    105e373 <my.vm::run+0x2e43>
 105c3b5:	49 c1 e0 04          	shl    $0x4,%r8
 105c3b9:	0f b6 c2             	movzbl %dl,%eax
 105c3bc:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 105c3c1:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 105c3c6:	49 89 f5             	mov    %rsi,%r13
 105c3c9:	49 ff c5             	inc    %r13
 105c3cc:	4c 8d 25 d9 af fa ff 	lea    -0x55027(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105c3d3:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105c3d8:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105c3dd:	0f 80 00 2a 00 00    	jo     105ede3 <my.vm::run+0x38b3>
 105c3e3:	49 89 ea             	mov    %rbp,%r10
 105c3e6:	e9 dd 17 00 00       	jmp    105dbc8 <my.vm::run+0x2698>
 105c3eb:	48 8d bc 24 b0 02 00 	lea    0x2b0(%rsp),%rdi
 105c3f2:	00 
 105c3f3:	4c 89 f6             	mov    %r14,%rsi
 105c3f6:	4c 89 d2             	mov    %r10,%rdx
 105c3f9:	4c 89 d9             	mov    %r11,%rcx
 105c3fc:	4d 89 f8             	mov    %r15,%r8
 105c3ff:	e8 bc 77 00 00       	call   1063bc0 <my.vm::read_constant>
 105c404:	c5 f9 28 84 24 b0 02 	vmovapd 0x2b0(%rsp),%xmm0
 105c40b:	00 00 
 105c40d:	4c 8b 94 24 c0 02 00 	mov    0x2c0(%rsp),%r10
 105c414:	00 
 105c415:	4c 8b 9c 24 c8 02 00 	mov    0x2c8(%rsp),%r11
 105c41c:	00 
 105c41d:	4c 8b bc 24 d0 02 00 	mov    0x2d0(%rsp),%r15
 105c424:	00 
 105c425:	4c 8b 8c 24 d8 02 00 	mov    0x2d8(%rsp),%r9
 105c42c:	00 
 105c42d:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c431:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c435:	4c 89 e9             	mov    %r13,%rcx
 105c438:	49 39 d5             	cmp    %rdx,%r13
 105c43b:	0f 83 ae 1a 00 00    	jae    105deef <my.vm::run+0x29bf>
 105c441:	48 c1 e1 04          	shl    $0x4,%rcx
 105c445:	c5 f9 54 05 93 7f fa 	vandpd -0x5806d(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c44c:	ff 
 105c44d:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 105c453:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c457:	4c 89 e8             	mov    %r13,%rax
 105c45a:	48 ff c0             	inc    %rax
 105c45d:	0f 81 86 01 00 00    	jno    105c5e9 <my.vm::run+0x10b9>
 105c463:	e9 ff 26 00 00       	jmp    105eb67 <my.vm::run+0x3637>
 105c468:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c46c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c470:	4c 89 e9             	mov    %r13,%rcx
 105c473:	49 39 d5             	cmp    %rdx,%r13
 105c476:	0f 83 8e 1a 00 00    	jae    105df0a <my.vm::run+0x29da>
 105c47c:	48 c1 e1 04          	shl    $0x4,%rcx
 105c480:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105c487:	00 00 
 105c489:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c48d:	4c 89 e8             	mov    %r13,%rax
 105c490:	48 ff c0             	inc    %rax
 105c493:	0f 81 50 01 00 00    	jno    105c5e9 <my.vm::run+0x10b9>
 105c499:	e9 67 28 00 00       	jmp    105ed05 <my.vm::run+0x37d5>
 105c49e:	48 8d bc 24 10 02 00 	lea    0x210(%rsp),%rdi
 105c4a5:	00 
 105c4a6:	4c 89 f6             	mov    %r14,%rsi
 105c4a9:	4c 89 d2             	mov    %r10,%rdx
 105c4ac:	4c 89 d9             	mov    %r11,%rcx
 105c4af:	4d 89 f8             	mov    %r15,%r8
 105c4b2:	e8 89 7d 00 00       	call   1064240 <my.vm::read_short>
 105c4b7:	48 8b 94 24 10 02 00 	mov    0x210(%rsp),%rdx
 105c4be:	00 
 105c4bf:	48 8b b4 24 28 02 00 	mov    0x228(%rsp),%rsi
 105c4c6:	00 
 105c4c7:	49 89 f7             	mov    %rsi,%r15
 105c4ca:	49 01 d7             	add    %rdx,%r15
 105c4cd:	0f 80 40 26 00 00    	jo     105eb13 <my.vm::run+0x35e3>
 105c4d3:	4c 8b 94 24 18 02 00 	mov    0x218(%rsp),%r10
 105c4da:	00 
 105c4db:	4c 8b 9c 24 20 02 00 	mov    0x220(%rsp),%r11
 105c4e2:	00 
 105c4e3:	4c 8b 8c 24 30 02 00 	mov    0x230(%rsp),%r9
 105c4ea:	00 
 105c4eb:	e9 30 18 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105c4f0:	4d 89 ec             	mov    %r13,%r12
 105c4f3:	49 ff cc             	dec    %r12
 105c4f6:	0f 80 02 25 00 00    	jo     105e9fe <my.vm::run+0x34ce>
 105c4fc:	4c 89 54 24 10       	mov    %r10,0x10(%rsp)
 105c501:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 105c506:	4c 89 cd             	mov    %r9,%rbp
 105c509:	4d 89 a6 80 00 00 00 	mov    %r12,0x80(%r14)
 105c510:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c514:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c518:	4c 89 e6             	mov    %r12,%rsi
 105c51b:	49 39 d4             	cmp    %rdx,%r12
 105c51e:	0f 83 88 1a 00 00    	jae    105dfac <my.vm::run+0x2a7c>
 105c524:	48 c1 e6 04          	shl    $0x4,%rsi
 105c528:	48 8b 4c 30 28       	mov    0x28(%rax,%rsi,1),%rcx
 105c52d:	8b 54 30 20          	mov    0x20(%rax,%rsi,1),%edx
 105c531:	4c 89 f7             	mov    %r14,%rdi
 105c534:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 105c539:	e8 42 7a 00 00       	call   1063f80 <my.output::print_value>
 105c53e:	4d 89 e5             	mov    %r12,%r13
 105c541:	4c 8d 25 64 ae fa ff 	lea    -0x5519c(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105c548:	e9 c1 17 00 00       	jmp    105dd0e <my.vm::run+0x27de>
 105c54d:	48 8d bc 24 60 02 00 	lea    0x260(%rsp),%rdi
 105c554:	00 
 105c555:	4c 89 f6             	mov    %r14,%rsi
 105c558:	4c 89 d2             	mov    %r10,%rdx
 105c55b:	4c 89 d9             	mov    %r11,%rcx
 105c55e:	4d 89 f8             	mov    %r15,%r8
 105c561:	e8 3a 77 00 00       	call   1063ca0 <my.vm::read_byte>
 105c566:	48 8b 94 24 60 02 00 	mov    0x260(%rsp),%rdx
 105c56d:	00 
 105c56e:	4c 8b 8c 24 80 02 00 	mov    0x280(%rsp),%r9
 105c575:	00 
 105c576:	4c 89 ce             	mov    %r9,%rsi
 105c579:	48 01 d6             	add    %rdx,%rsi
 105c57c:	0f 80 9d 25 00 00    	jo     105eb1f <my.vm::run+0x35ef>
 105c582:	4c 8b 94 24 68 02 00 	mov    0x268(%rsp),%r10
 105c589:	00 
 105c58a:	4c 8b 9c 24 70 02 00 	mov    0x270(%rsp),%r11
 105c591:	00 
 105c592:	4c 8b bc 24 78 02 00 	mov    0x278(%rsp),%r15
 105c599:	00 
 105c59a:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c59e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c5a2:	48 39 d6             	cmp    %rdx,%rsi
 105c5a5:	0f 83 1c 1a 00 00    	jae    105dfc7 <my.vm::run+0x2a97>
 105c5ab:	48 89 f1             	mov    %rsi,%rcx
 105c5ae:	48 c1 e1 04          	shl    $0x4,%rcx
 105c5b2:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105c5b8:	4c 89 e9             	mov    %r13,%rcx
 105c5bb:	49 39 d5             	cmp    %rdx,%r13
 105c5be:	0f 83 54 1a 00 00    	jae    105e018 <my.vm::run+0x2ae8>
 105c5c4:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105c5c8:	48 c1 e1 04          	shl    $0x4,%rcx
 105c5cc:	c5 f9 54 05 0c 7e fa 	vandpd -0x581f4(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c5d3:	ff 
 105c5d4:	c5 f9 11 04 0a       	vmovupd %xmm0,(%rdx,%rcx,1)
 105c5d9:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c5dd:	4c 89 e8             	mov    %r13,%rax
 105c5e0:	48 ff c0             	inc    %rax
 105c5e3:	0f 80 92 25 00 00    	jo     105eb7b <my.vm::run+0x364b>
 105c5e9:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105c5f0:	49 89 c5             	mov    %rax,%r13
 105c5f3:	e9 28 17 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105c5f8:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105c5ff:	48 89 f3             	mov    %rsi,%rbx
 105c602:	48 ff cb             	dec    %rbx
 105c605:	0f 80 23 25 00 00    	jo     105eb2e <my.vm::run+0x35fe>
 105c60b:	49 89 dd             	mov    %rbx,%r13
 105c60e:	49 ff cd             	dec    %r13
 105c611:	0f 80 78 25 00 00    	jo     105eb8f <my.vm::run+0x365f>
 105c617:	4c 89 54 24 10       	mov    %r10,0x10(%rsp)
 105c61c:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 105c621:	4c 89 cd             	mov    %r9,%rbp
 105c624:	49 8b 76 78          	mov    0x78(%r14),%rsi
 105c628:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105c62c:	4c 89 e8             	mov    %r13,%rax
 105c62f:	49 39 d5             	cmp    %rdx,%r13
 105c632:	0f 83 70 1a 00 00    	jae    105e0a8 <my.vm::run+0x2b78>
 105c638:	48 c1 e0 04          	shl    $0x4,%rax
 105c63c:	0f b6 4c 06 20       	movzbl 0x20(%rsi,%rax,1),%ecx
 105c641:	85 c9                	test   %ecx,%ecx
 105c643:	0f 84 35 15 00 00    	je     105db7e <my.vm::run+0x264e>
 105c649:	83 f9 01             	cmp    $0x1,%ecx
 105c64c:	0f 84 08 15 00 00    	je     105db5a <my.vm::run+0x262a>
 105c652:	83 f9 03             	cmp    $0x3,%ecx
 105c655:	0f 85 30 15 00 00    	jne    105db8b <my.vm::run+0x265b>
 105c65b:	48 8b 7c 06 28       	mov    0x28(%rsi,%rax,1),%rdi
 105c660:	4d 8b 16             	mov    (%r14),%r10
 105c663:	49 8b 52 08          	mov    0x8(%r10),%rdx
 105c667:	48 89 f8             	mov    %rdi,%rax
 105c66a:	48 39 d7             	cmp    %rdx,%rdi
 105c66d:	49 89 e9             	mov    %rbp,%r9
 105c670:	48 8b 4c 24 20       	mov    0x20(%rsp),%rcx
 105c675:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 105c67a:	0f 83 cb 1d 00 00    	jae    105e44b <my.vm::run+0x2f1b>
 105c680:	48 6b c0 38          	imul   $0x38,%rax,%rax
 105c684:	41 83 7c 02 20 07    	cmpl   $0x7,0x20(%r10,%rax,1)
 105c68a:	0f 85 48 16 00 00    	jne    105dcd8 <my.vm::run+0x27a8>
 105c690:	4d 89 d4             	mov    %r10,%r12
 105c693:	48 89 7c 24 40       	mov    %rdi,0x40(%rsp)
 105c698:	48 89 74 24 58       	mov    %rsi,0x58(%rsp)
 105c69d:	48 8d bc 24 78 01 00 	lea    0x178(%rsp),%rdi
 105c6a4:	00 
 105c6a5:	4c 89 f6             	mov    %r14,%rsi
 105c6a8:	4c 89 c2             	mov    %r8,%rdx
 105c6ab:	4d 89 f8             	mov    %r15,%r8
 105c6ae:	e8 0d 75 00 00       	call   1063bc0 <my.vm::read_constant>
 105c6b3:	0f b6 84 24 78 01 00 	movzbl 0x178(%rsp),%eax
 105c6ba:	00 
 105c6bb:	83 f8 03             	cmp    $0x3,%eax
 105c6be:	0f 85 58 27 00 00    	jne    105ee1c <my.vm::run+0x38ec>
 105c6c4:	48 8b 84 24 a0 01 00 	mov    0x1a0(%rsp),%rax
 105c6cb:	00 
 105c6cc:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105c6d1:	4c 8b bc 24 98 01 00 	mov    0x198(%rsp),%r15
 105c6d8:	00 
 105c6d9:	48 8b 84 24 90 01 00 	mov    0x190(%rsp),%rax
 105c6e0:	00 
 105c6e1:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105c6e6:	48 8b b4 24 80 01 00 	mov    0x180(%rsp),%rsi
 105c6ed:	00 
 105c6ee:	48 8b 84 24 88 01 00 	mov    0x188(%rsp),%rax
 105c6f5:	00 
 105c6f6:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105c6fb:	4c 89 f7             	mov    %r14,%rdi
 105c6fe:	48 89 74 24 60       	mov    %rsi,0x60(%rsp)
 105c703:	e8 18 e0 00 00       	call   106a720 <my.heap::string_hash>
 105c708:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 105c70d:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105c711:	48 89 de             	mov    %rbx,%rsi
 105c714:	48 39 d3             	cmp    %rdx,%rbx
 105c717:	0f 83 a7 1d 00 00    	jae    105e4c4 <my.vm::run+0x2f94>
 105c71d:	48 8d 69 20          	lea    0x20(%rcx),%rbp
 105c721:	48 c1 e6 04          	shl    $0x4,%rsi
 105c725:	44 0f b6 4c 35 00    	movzbl 0x0(%rbp,%rsi,1),%r9d
 105c72b:	4c 8b 44 35 08       	mov    0x8(%rbp,%rsi,1),%r8
 105c730:	4c 89 e6             	mov    %r12,%rsi
 105c733:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 105c738:	48 8b 4c 24 40       	mov    0x40(%rsp),%rcx
 105c73d:	48 89 cf             	mov    %rcx,%rdi
 105c740:	48 39 d1             	cmp    %rdx,%rcx
 105c743:	0f 83 96 1d 00 00    	jae    105e4df <my.vm::run+0x2faf>
 105c749:	44 88 4c 24 4f       	mov    %r9b,0x4f(%rsp)
 105c74e:	4c 89 84 24 b8 01 00 	mov    %r8,0x1b8(%rsp)
 105c755:	00 
 105c756:	89 44 24 68          	mov    %eax,0x68(%rsp)
 105c75a:	48 89 6c 24 70       	mov    %rbp,0x70(%rsp)
 105c75f:	4c 8d 66 20          	lea    0x20(%rsi),%r12
 105c763:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 105c767:	41 8b 0c 04          	mov    (%r12,%rax,1),%ecx
 105c76b:	83 f9 07             	cmp    $0x7,%ecx
 105c76e:	0f 85 1a 21 00 00    	jne    105e88e <my.vm::run+0x335e>
 105c774:	48 89 f5             	mov    %rsi,%rbp
 105c777:	4c 01 e0             	add    %r12,%rax
 105c77a:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105c77e:	48 89 8c 24 b0 01 00 	mov    %rcx,0x1b0(%rsp)
 105c785:	00 
 105c786:	48 8b 78 10          	mov    0x10(%rax),%rdi
 105c78a:	48 8b 40 18          	mov    0x18(%rax),%rax
 105c78e:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
 105c795:	00 
 105c796:	be 20 00 00 00       	mov    $0x20,%esi
 105c79b:	e8 20 7a fc ff       	call   10241c0 <myl_core_list_copy>
 105c7a0:	44 0f b6 44 24 4f    	movzbl 0x4f(%rsp),%r8d
 105c7a6:	48 89 c7             	mov    %rax,%rdi
 105c7a9:	48 8b b4 24 a8 01 00 	mov    0x1a8(%rsp),%rsi
 105c7b0:	00 
 105c7b1:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 105c7b6:	8b 4c 24 68          	mov    0x68(%rsp),%ecx
 105c7ba:	4c 8b 8c 24 b8 01 00 	mov    0x1b8(%rsp),%r9
 105c7c1:	00 
 105c7c2:	e8 39 e0 00 00       	call   106a800 <my.table::set>
 105c7c7:	48 8b 45 08          	mov    0x8(%rbp),%rax
 105c7cb:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 105c7d0:	48 39 c7             	cmp    %rax,%rdi
 105c7d3:	0f 83 3c 1d 00 00    	jae    105e515 <my.vm::run+0x2fe5>
 105c7d9:	48 89 fe             	mov    %rdi,%rsi
 105c7dc:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105c7e1:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105c7e6:	4c 6b ce 38          	imul   $0x38,%rsi,%r9
 105c7ea:	43 0f b6 34 0c       	movzbl (%r12,%r9,1),%esi
 105c7ef:	4b 8b 7c 0c 08       	mov    0x8(%r12,%r9,1),%rdi
 105c7f4:	4f 8b 44 0c 10       	mov    0x10(%r12,%r9,1),%r8
 105c7f9:	4b 8b 44 0c 18       	mov    0x18(%r12,%r9,1),%rax
 105c7fe:	4b 8b 6c 0c 20       	mov    0x20(%r12,%r9,1),%rbp
 105c803:	48 89 6c 24 60       	mov    %rbp,0x60(%rsp)
 105c808:	4b 8b 6c 0c 28       	mov    0x28(%r12,%r9,1),%rbp
 105c80d:	48 89 6c 24 40       	mov    %rbp,0x40(%rsp)
 105c812:	4b c7 04 0c 07 00 00 	movq   $0x7,(%r12,%r9,1)
 105c819:	00 
 105c81a:	48 8b ac 24 b0 01 00 	mov    0x1b0(%rsp),%rbp
 105c821:	00 
 105c822:	4b 89 6c 0c 08       	mov    %rbp,0x8(%r12,%r9,1)
 105c827:	4b 89 54 0c 10       	mov    %rdx,0x10(%r12,%r9,1)
 105c82c:	4b 89 4c 0c 18       	mov    %rcx,0x18(%r12,%r9,1)
 105c831:	83 fe 09             	cmp    $0x9,%esi
 105c834:	4c 8d 25 71 ab fa ff 	lea    -0x5548f(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105c83b:	77 20                	ja     105c85d <my.vm::run+0x132d>
 105c83d:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105c842:	0f a3 f1             	bt     %esi,%ecx
 105c845:	0f 83 d4 15 00 00    	jae    105de1f <my.vm::run+0x28ef>
 105c84b:	4c 89 c7             	mov    %r8,%rdi
 105c84e:	e8 ad 7a fc ff       	call   1024300 <myl_core_drop_owned>
 105c853:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105c858:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105c85d:	48 8b 44 24 58       	mov    0x58(%rsp),%rax
 105c862:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c866:	48 39 d3             	cmp    %rdx,%rbx
 105c869:	0f 83 cb 1c 00 00    	jae    105e53a <my.vm::run+0x300a>
 105c86f:	48 89 d8             	mov    %rbx,%rax
 105c872:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105c877:	48 8b 6c 24 70       	mov    0x70(%rsp),%rbp
 105c87c:	48 c1 e0 04          	shl    $0x4,%rax
 105c880:	c5 f9 10 44 05 00    	vmovupd 0x0(%rbp,%rax,1),%xmm0
 105c886:	4c 89 e8             	mov    %r13,%rax
 105c889:	49 39 d5             	cmp    %rdx,%r13
 105c88c:	0f 83 cd 1c 00 00    	jae    105e55f <my.vm::run+0x302f>
 105c892:	c5 f9 54 05 46 7b fa 	vandpd -0x584ba(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c899:	ff 
 105c89a:	48 c1 e0 04          	shl    $0x4,%rax
 105c89e:	c5 f9 11 44 05 00    	vmovupd %xmm0,0x0(%rbp,%rax,1)
 105c8a4:	e9 1c 13 00 00       	jmp    105dbc5 <my.vm::run+0x2695>
 105c8a9:	48 8d bc 24 38 02 00 	lea    0x238(%rsp),%rdi
 105c8b0:	00 
 105c8b1:	4c 89 f6             	mov    %r14,%rsi
 105c8b4:	4c 89 d2             	mov    %r10,%rdx
 105c8b7:	4c 89 d9             	mov    %r11,%rcx
 105c8ba:	4d 89 f8             	mov    %r15,%r8
 105c8bd:	e8 de 73 00 00       	call   1063ca0 <my.vm::read_byte>
 105c8c2:	4c 89 ee             	mov    %r13,%rsi
 105c8c5:	48 ff ce             	dec    %rsi
 105c8c8:	0f 80 0f 23 00 00    	jo     105ebdd <my.vm::run+0x36ad>
 105c8ce:	48 8b 84 24 38 02 00 	mov    0x238(%rsp),%rax
 105c8d5:	00 
 105c8d6:	4c 8b 94 24 40 02 00 	mov    0x240(%rsp),%r10
 105c8dd:	00 
 105c8de:	4c 8b 9c 24 48 02 00 	mov    0x248(%rsp),%r11
 105c8e5:	00 
 105c8e6:	4c 8b bc 24 50 02 00 	mov    0x250(%rsp),%r15
 105c8ed:	00 
 105c8ee:	4c 8b 8c 24 58 02 00 	mov    0x258(%rsp),%r9
 105c8f5:	00 
 105c8f6:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105c8fa:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105c8fe:	48 39 d6             	cmp    %rdx,%rsi
 105c901:	0f 83 db 16 00 00    	jae    105dfe2 <my.vm::run+0x2ab2>
 105c907:	48 89 f7             	mov    %rsi,%rdi
 105c90a:	4c 89 ce             	mov    %r9,%rsi
 105c90d:	48 01 c6             	add    %rax,%rsi
 105c910:	0f 80 b5 22 00 00    	jo     105ebcb <my.vm::run+0x369b>
 105c916:	48 c1 e7 04          	shl    $0x4,%rdi
 105c91a:	c5 f9 10 44 39 20    	vmovupd 0x20(%rcx,%rdi,1),%xmm0
 105c920:	48 39 d6             	cmp    %rdx,%rsi
 105c923:	0f 83 9a 17 00 00    	jae    105e0c3 <my.vm::run+0x2b93>
 105c929:	48 89 f0             	mov    %rsi,%rax
 105c92c:	48 8d 51 20          	lea    0x20(%rcx),%rdx
 105c930:	48 c1 e0 04          	shl    $0x4,%rax
 105c934:	c5 f9 54 05 a4 7a fa 	vandpd -0x5855c(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c93b:	ff 
 105c93c:	c5 f9 11 04 02       	vmovupd %xmm0,(%rdx,%rax,1)
 105c941:	49 89 4e 78          	mov    %rcx,0x78(%r14)
 105c945:	e9 d6 13 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105c94a:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105c951:	00 
 105c952:	4c 89 f6             	mov    %r14,%rsi
 105c955:	4c 89 d2             	mov    %r10,%rdx
 105c958:	4c 89 d9             	mov    %r11,%rcx
 105c95b:	4d 89 f8             	mov    %r15,%r8
 105c95e:	e8 3d 73 00 00       	call   1063ca0 <my.vm::read_byte>
 105c963:	48 8b 94 24 88 00 00 	mov    0x88(%rsp),%rdx
 105c96a:	00 
 105c96b:	48 8b b4 24 90 00 00 	mov    0x90(%rsp),%rsi
 105c972:	00 
 105c973:	48 8b ac 24 98 00 00 	mov    0x98(%rsp),%rbp
 105c97a:	00 
 105c97b:	4c 8b bc 24 a0 00 00 	mov    0xa0(%rsp),%r15
 105c982:	00 
 105c983:	48 8b 9c 24 a8 00 00 	mov    0xa8(%rsp),%rbx
 105c98a:	00 
 105c98b:	4c 89 f7             	mov    %r14,%rdi
 105c98e:	49 89 f4             	mov    %rsi,%r12
 105c991:	e8 5a e2 00 00       	call   106abf0 <my.heap::closure_upvalue>
 105c996:	48 8d bc 24 e0 02 00 	lea    0x2e0(%rsp),%rdi
 105c99d:	00 
 105c99e:	4c 89 f6             	mov    %r14,%rsi
 105c9a1:	48 89 c2             	mov    %rax,%rdx
 105c9a4:	e8 47 e1 00 00       	call   106aaf0 <my.heap::upvalue_obj>
 105c9a9:	48 8b b4 24 e0 02 00 	mov    0x2e0(%rsp),%rsi
 105c9b0:	00 
 105c9b1:	48 83 fe ff          	cmp    $0xffffffffffffffff,%rsi
 105c9b5:	0f 84 dc 0e 00 00    	je     105d897 <my.vm::run+0x2367>
 105c9bb:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c9bf:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c9c3:	48 39 d6             	cmp    %rdx,%rsi
 105c9c6:	0f 83 fc 18 00 00    	jae    105e2c8 <my.vm::run+0x2d98>
 105c9cc:	48 89 f1             	mov    %rsi,%rcx
 105c9cf:	49 89 d9             	mov    %rbx,%r9
 105c9d2:	49 89 eb             	mov    %rbp,%r11
 105c9d5:	4d 89 e2             	mov    %r12,%r10
 105c9d8:	48 c1 e1 04          	shl    $0x4,%rcx
 105c9dc:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105c9e2:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105c9e9:	48 89 f1             	mov    %rsi,%rcx
 105c9ec:	48 39 d6             	cmp    %rdx,%rsi
 105c9ef:	4c 8d 25 b6 a9 fa ff 	lea    -0x5564a(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105c9f6:	0f 83 f0 18 00 00    	jae    105e2ec <my.vm::run+0x2dbc>
 105c9fc:	48 83 c0 20          	add    $0x20,%rax
 105ca00:	48 c1 e1 04          	shl    $0x4,%rcx
 105ca04:	c5 f9 54 05 d4 79 fa 	vandpd -0x5862c(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105ca0b:	ff 
 105ca0c:	c5 f9 11 04 08       	vmovupd %xmm0,(%rax,%rcx,1)
 105ca11:	49 89 f5             	mov    %rsi,%r13
 105ca14:	49 ff c5             	inc    %r13
 105ca17:	0f 81 ab 11 00 00    	jno    105dbc8 <my.vm::run+0x2698>
 105ca1d:	e9 a1 23 00 00       	jmp    105edc3 <my.vm::run+0x3893>
 105ca22:	4c 89 ee             	mov    %r13,%rsi
 105ca25:	48 ff ce             	dec    %rsi
 105ca28:	0f 80 40 20 00 00    	jo     105ea6e <my.vm::run+0x353e>
 105ca2e:	49 8b 46 78          	mov    0x78(%r14),%rax
 105ca32:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ca36:	48 39 d6             	cmp    %rdx,%rsi
 105ca39:	0f 83 be 15 00 00    	jae    105dffd <my.vm::run+0x2acd>
 105ca3f:	48 89 f1             	mov    %rsi,%rcx
 105ca42:	48 c1 e1 04          	shl    $0x4,%rcx
 105ca46:	48 8b 5c 08 20       	mov    0x20(%rax,%rcx,1),%rbx
 105ca4b:	4c 8b 64 08 28       	mov    0x28(%rax,%rcx,1),%r12
 105ca50:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105ca57:	00 
 105ca58:	4c 89 f6             	mov    %r14,%rsi
 105ca5b:	4c 89 d2             	mov    %r10,%rdx
 105ca5e:	4c 89 d9             	mov    %r11,%rcx
 105ca61:	4d 89 f8             	mov    %r15,%r8
 105ca64:	e8 57 71 00 00       	call   1063bc0 <my.vm::read_constant>
 105ca69:	0f b6 84 24 88 00 00 	movzbl 0x88(%rsp),%eax
 105ca70:	00 
 105ca71:	83 f8 03             	cmp    $0x3,%eax
 105ca74:	0f 85 55 1d 00 00    	jne    105e7cf <my.vm::run+0x329f>
 105ca7a:	48 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%rax
 105ca81:	00 
 105ca82:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105ca87:	4c 8b bc 24 a8 00 00 	mov    0xa8(%rsp),%r15
 105ca8e:	00 
 105ca8f:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
 105ca96:	00 
 105ca97:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105ca9c:	4c 8b ac 24 90 00 00 	mov    0x90(%rsp),%r13
 105caa3:	00 
 105caa4:	48 8b ac 24 98 00 00 	mov    0x98(%rsp),%rbp
 105caab:	00 
 105caac:	4c 89 f7             	mov    %r14,%rdi
 105caaf:	4c 89 ee             	mov    %r13,%rsi
 105cab2:	e8 69 dc 00 00       	call   106a720 <my.heap::string_hash>
 105cab7:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105cabb:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105cabf:	4c 89 ea             	mov    %r13,%rdx
 105cac2:	89 c1                	mov    %eax,%ecx
 105cac4:	41 89 d8             	mov    %ebx,%r8d
 105cac7:	4d 89 e1             	mov    %r12,%r9
 105caca:	e8 31 dd 00 00       	call   106a800 <my.table::set>
 105cacf:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105cad3:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105cad7:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105cade:	49 89 f5             	mov    %rsi,%r13
 105cae1:	49 ff cd             	dec    %r13
 105cae4:	0f 80 40 1f 00 00    	jo     105ea2a <my.vm::run+0x34fa>
 105caea:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105caf1:	49 8b 46 78          	mov    0x78(%r14),%rax
 105caf5:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105cafc:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cb00:	49 39 d5             	cmp    %rdx,%r13
 105cb03:	4c 8d 25 a2 a8 fa ff 	lea    -0x5575e(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105cb0a:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105cb0f:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105cb14:	49 89 ea             	mov    %rbp,%r10
 105cb17:	0f 82 03 12 00 00    	jb     105dd20 <my.vm::run+0x27f0>
 105cb1d:	4c 89 e8             	mov    %r13,%rax
 105cb20:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cb24:	48 21 d0             	and    %rdx,%rax
 105cb27:	4c 01 e8             	add    %r13,%rax
 105cb2a:	48 39 d0             	cmp    %rdx,%rax
 105cb2d:	0f 82 ed 11 00 00    	jb     105dd20 <my.vm::run+0x27f0>
 105cb33:	e9 1b 26 00 00       	jmp    105f153 <my.vm::run+0x3c23>
 105cb38:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105cb3f:	00 
 105cb40:	4c 89 f6             	mov    %r14,%rsi
 105cb43:	4c 89 d2             	mov    %r10,%rdx
 105cb46:	4c 89 d9             	mov    %r11,%rcx
 105cb49:	4d 89 f8             	mov    %r15,%r8
 105cb4c:	e8 6f 70 00 00       	call   1063bc0 <my.vm::read_constant>
 105cb51:	0f b6 84 24 88 00 00 	movzbl 0x88(%rsp),%eax
 105cb58:	00 
 105cb59:	83 f8 03             	cmp    $0x3,%eax
 105cb5c:	0f 85 c4 1c 00 00    	jne    105e826 <my.vm::run+0x32f6>
 105cb62:	4c 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%r13
 105cb69:	00 
 105cb6a:	4c 8b bc 24 a8 00 00 	mov    0xa8(%rsp),%r15
 105cb71:	00 
 105cb72:	48 8b ac 24 a0 00 00 	mov    0xa0(%rsp),%rbp
 105cb79:	00 
 105cb7a:	4c 8b 84 24 90 00 00 	mov    0x90(%rsp),%r8
 105cb81:	00 
 105cb82:	48 8b bc 24 98 00 00 	mov    0x98(%rsp),%rdi
 105cb89:	00 
 105cb8a:	49 8b 06             	mov    (%r14),%rax
 105cb8d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cb91:	4c 89 c1             	mov    %r8,%rcx
 105cb94:	49 39 d0             	cmp    %rdx,%r8
 105cb97:	0f 83 ca 15 00 00    	jae    105e167 <my.vm::run+0x2c37>
 105cb9d:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 105cba2:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 105cba7:	48 6b d1 38          	imul   $0x38,%rcx,%rdx
 105cbab:	8b 4c 10 20          	mov    0x20(%rax,%rdx,1),%ecx
 105cbaf:	83 f9 02             	cmp    $0x2,%ecx
 105cbb2:	0f 85 04 1b 00 00    	jne    105e6bc <my.vm::run+0x318c>
 105cbb8:	48 01 d0             	add    %rdx,%rax
 105cbbb:	48 83 c0 20          	add    $0x20,%rax
 105cbbf:	48 8b 70 10          	mov    0x10(%rax),%rsi
 105cbc3:	4c 89 c7             	mov    %r8,%rdi
 105cbc6:	48 89 74 24 58       	mov    %rsi,0x58(%rsp)
 105cbcb:	e8 e0 e5 ff ff       	call   105b1b0 <my.object::new_closure>
 105cbd0:	48 89 c3             	mov    %rax,%rbx
 105cbd3:	48 89 d5             	mov    %rdx,%rbp
 105cbd6:	be 08 00 00 00       	mov    $0x8,%esi
 105cbdb:	48 89 d7             	mov    %rdx,%rdi
 105cbde:	e8 dd 75 fc ff       	call   10241c0 <myl_core_list_copy>
 105cbe3:	49 89 c4             	mov    %rax,%r12
 105cbe6:	48 c7 84 24 18 06 00 	movq   $0x4,0x618(%rsp)
 105cbed:	00 04 00 00 00 
 105cbf2:	48 89 5c 24 60       	mov    %rbx,0x60(%rsp)
 105cbf7:	48 89 9c 24 20 06 00 	mov    %rbx,0x620(%rsp)
 105cbfe:	00 
 105cbff:	48 89 84 24 28 06 00 	mov    %rax,0x628(%rsp)
 105cc06:	00 
 105cc07:	48 8d bc 24 40 03 00 	lea    0x340(%rsp),%rdi
 105cc0e:	00 
 105cc0f:	48 8d 94 24 18 06 00 	lea    0x618(%rsp),%rdx
 105cc16:	00 
 105cc17:	4c 89 f6             	mov    %r14,%rsi
 105cc1a:	e8 41 e1 ff ff       	call   105ad60 <my.heap::allocate>
 105cc1f:	4c 89 e7             	mov    %r12,%rdi
 105cc22:	e8 d9 76 fc ff       	call   1024300 <myl_core_drop_owned>
 105cc27:	48 8b bc 24 40 03 00 	mov    0x340(%rsp),%rdi
 105cc2e:	00 
 105cc2f:	49 8b 46 78          	mov    0x78(%r14),%rax
 105cc33:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105cc3a:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cc3e:	48 89 f1             	mov    %rsi,%rcx
 105cc41:	48 39 d6             	cmp    %rdx,%rsi
 105cc44:	0f 83 15 16 00 00    	jae    105e25f <my.vm::run+0x2d2f>
 105cc4a:	48 c1 e1 04          	shl    $0x4,%rcx
 105cc4e:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 105cc55:	00 00 
 105cc57:	48 89 7c 08 28       	mov    %rdi,0x28(%rax,%rcx,1)
 105cc5c:	48 89 f0             	mov    %rsi,%rax
 105cc5f:	48 ff c0             	inc    %rax
 105cc62:	0f 80 46 1e 00 00    	jo     105eaae <my.vm::run+0x357e>
 105cc68:	48 89 7c 24 68       	mov    %rdi,0x68(%rsp)
 105cc6d:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105cc74:	be 08 00 00 00       	mov    $0x8,%esi
 105cc79:	48 89 ef             	mov    %rbp,%rdi
 105cc7c:	e8 3f 75 fc ff       	call   10241c0 <myl_core_list_copy>
 105cc81:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
 105cc86:	48 89 ef             	mov    %rbp,%rdi
 105cc89:	e8 72 76 fc ff       	call   1024300 <myl_core_drop_owned>
 105cc8e:	48 83 7c 24 58 00    	cmpq   $0x0,0x58(%rsp)
 105cc94:	0f 8e 5b 0c 00 00    	jle    105d8f5 <my.vm::run+0x23c5>
 105cc9a:	45 31 e4             	xor    %r12d,%r12d
 105cc9d:	4d 89 e9             	mov    %r13,%r9
 105cca0:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105cca5:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105ccaa:	eb 3b                	jmp    105cce7 <my.vm::run+0x17b7>
 105ccac:	49 89 9e 98 00 00 00 	mov    %rbx,0x98(%r14)
 105ccb3:	48 8b 44 24 40       	mov    0x40(%rsp),%rax
 105ccb8:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ccbc:	49 39 d4             	cmp    %rdx,%r12
 105ccbf:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105ccc4:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105ccc9:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105ccce:	0f 83 0f 1a 00 00    	jae    105e6e3 <my.vm::run+0x31b3>
 105ccd4:	4a 89 5c e0 20       	mov    %rbx,0x20(%rax,%r12,8)
 105ccd9:	49 ff c4             	inc    %r12
 105ccdc:	4c 3b 64 24 58       	cmp    0x58(%rsp),%r12
 105cce1:	0f 84 1b 0c 00 00    	je     105d902 <my.vm::run+0x23d2>
 105cce7:	48 8d bc 24 78 01 00 	lea    0x178(%rsp),%rdi
 105ccee:	00 
 105ccef:	4c 89 f6             	mov    %r14,%rsi
 105ccf2:	4c 89 d2             	mov    %r10,%rdx
 105ccf5:	4c 89 d9             	mov    %r11,%rcx
 105ccf8:	4d 89 f8             	mov    %r15,%r8
 105ccfb:	e8 a0 6f 00 00       	call   1063ca0 <my.vm::read_byte>
 105cd00:	48 8b 9c 24 78 01 00 	mov    0x178(%rsp),%rbx
 105cd07:	00 
 105cd08:	48 8b 94 24 80 01 00 	mov    0x180(%rsp),%rdx
 105cd0f:	00 
 105cd10:	48 8b 8c 24 88 01 00 	mov    0x188(%rsp),%rcx
 105cd17:	00 
 105cd18:	4c 8b 84 24 90 01 00 	mov    0x190(%rsp),%r8
 105cd1f:	00 
 105cd20:	4c 8b 8c 24 98 01 00 	mov    0x198(%rsp),%r9
 105cd27:	00 
 105cd28:	48 8d bc 24 88 02 00 	lea    0x288(%rsp),%rdi
 105cd2f:	00 
 105cd30:	4c 89 f6             	mov    %r14,%rsi
 105cd33:	e8 68 6f 00 00       	call   1063ca0 <my.vm::read_byte>
 105cd38:	48 8b 94 24 88 02 00 	mov    0x288(%rsp),%rdx
 105cd3f:	00 
 105cd40:	48 8b 84 24 90 02 00 	mov    0x290(%rsp),%rax
 105cd47:	00 
 105cd48:	48 8b ac 24 98 02 00 	mov    0x298(%rsp),%rbp
 105cd4f:	00 
 105cd50:	4c 8b bc 24 a0 02 00 	mov    0x2a0(%rsp),%r15
 105cd57:	00 
 105cd58:	48 8b b4 24 a8 02 00 	mov    0x2a8(%rsp),%rsi
 105cd5f:	00 
 105cd60:	48 83 fb 01          	cmp    $0x1,%rbx
 105cd64:	0f 85 c6 00 00 00    	jne    105ce30 <my.vm::run+0x1900>
 105cd6a:	49 89 f5             	mov    %rsi,%r13
 105cd6d:	49 01 d5             	add    %rdx,%r13
 105cd70:	0f 80 8b 19 00 00    	jo     105e701 <my.vm::run+0x31d1>
 105cd76:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105cd7b:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 105cd80:	48 89 74 24 18       	mov    %rsi,0x18(%rsp)
 105cd85:	49 8b 9e 98 00 00 00 	mov    0x98(%r14),%rbx
 105cd8c:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105cd90:	0f 84 d6 00 00 00    	je     105ce6c <my.vm::run+0x193c>
 105cd96:	48 8d bc 24 08 05 00 	lea    0x508(%rsp),%rdi
 105cd9d:	00 
 105cd9e:	4c 89 f6             	mov    %r14,%rsi
 105cda1:	48 89 da             	mov    %rbx,%rdx
 105cda4:	e8 47 dd 00 00       	call   106aaf0 <my.heap::upvalue_obj>
 105cda9:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 105cdb0:	4c 39 ac 24 08 05 00 	cmp    %r13,0x508(%rsp)
 105cdb7:	00 
 105cdb8:	7e 4b                	jle    105ce05 <my.vm::run+0x18d5>
 105cdba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 105cdc0:	48 89 dd             	mov    %rbx,%rbp
 105cdc3:	48 8d bc 24 e8 04 00 	lea    0x4e8(%rsp),%rdi
 105cdca:	00 
 105cdcb:	4c 89 f6             	mov    %r14,%rsi
 105cdce:	48 89 da             	mov    %rbx,%rdx
 105cdd1:	e8 1a dd 00 00       	call   106aaf0 <my.heap::upvalue_obj>
 105cdd6:	48 8b 9c 24 00 05 00 	mov    0x500(%rsp),%rbx
 105cddd:	00 
 105cdde:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105cde2:	0f 84 94 00 00 00    	je     105ce7c <my.vm::run+0x194c>
 105cde8:	48 8d bc 24 c8 04 00 	lea    0x4c8(%rsp),%rdi
 105cdef:	00 
 105cdf0:	4c 89 f6             	mov    %r14,%rsi
 105cdf3:	48 89 da             	mov    %rbx,%rdx
 105cdf6:	e8 f5 dc 00 00       	call   106aaf0 <my.heap::upvalue_obj>
 105cdfb:	4c 39 ac 24 c8 04 00 	cmp    %r13,0x4c8(%rsp)
 105ce02:	00 
 105ce03:	7f bb                	jg     105cdc0 <my.vm::run+0x1890>
 105ce05:	48 8d bc 24 a8 04 00 	lea    0x4a8(%rsp),%rdi
 105ce0c:	00 
 105ce0d:	4c 89 f6             	mov    %r14,%rsi
 105ce10:	48 89 da             	mov    %rbx,%rdx
 105ce13:	e8 d8 dc 00 00       	call   106aaf0 <my.heap::upvalue_obj>
 105ce18:	4c 39 ac 24 a8 04 00 	cmp    %r13,0x4a8(%rsp)
 105ce1f:	00 
 105ce20:	0f 84 8d fe ff ff    	je     105ccb3 <my.vm::run+0x1783>
 105ce26:	eb 5b                	jmp    105ce83 <my.vm::run+0x1953>
 105ce28:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 105ce2f:	00 
 105ce30:	49 89 f5             	mov    %rsi,%r13
 105ce33:	4c 89 f7             	mov    %r14,%rdi
 105ce36:	49 89 c6             	mov    %rax,%r14
 105ce39:	48 89 c6             	mov    %rax,%rsi
 105ce3c:	e8 af dd 00 00       	call   106abf0 <my.heap::closure_upvalue>
 105ce41:	48 89 c3             	mov    %rax,%rbx
 105ce44:	48 8b 44 24 40       	mov    0x40(%rsp),%rax
 105ce49:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ce4d:	49 39 d4             	cmp    %rdx,%r12
 105ce50:	0f 83 9c 18 00 00    	jae    105e6f2 <my.vm::run+0x31c2>
 105ce56:	4d 89 e9             	mov    %r13,%r9
 105ce59:	49 89 eb             	mov    %rbp,%r11
 105ce5c:	4d 89 f2             	mov    %r14,%r10
 105ce5f:	4c 8b b4 24 80 00 00 	mov    0x80(%rsp),%r14
 105ce66:	00 
 105ce67:	e9 68 fe ff ff       	jmp    105ccd4 <my.vm::run+0x17a4>
 105ce6c:	48 c7 c3 ff ff ff ff 	mov    $0xffffffffffffffff,%rbx
 105ce73:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 105ce7a:	eb 07                	jmp    105ce83 <my.vm::run+0x1953>
 105ce7c:	48 c7 c3 ff ff ff ff 	mov    $0xffffffffffffffff,%rbx
 105ce83:	48 c7 84 24 28 05 00 	movq   $0x5,0x528(%rsp)
 105ce8a:	00 05 00 00 00 
 105ce8f:	4c 89 ac 24 30 05 00 	mov    %r13,0x530(%rsp)
 105ce96:	00 
 105ce97:	48 c7 84 24 38 05 00 	movq   $0x0,0x538(%rsp)
 105ce9e:	00 00 00 00 00 
 105cea3:	48 89 9c 24 48 05 00 	mov    %rbx,0x548(%rsp)
 105ceaa:	00 
 105ceab:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105ceb2:	00 
 105ceb3:	48 8d 94 24 28 05 00 	lea    0x528(%rsp),%rdx
 105ceba:	00 
 105cebb:	4c 89 f6             	mov    %r14,%rsi
 105cebe:	e8 9d de ff ff       	call   105ad60 <my.heap::allocate>
 105cec3:	48 8b 9c 24 88 00 00 	mov    0x88(%rsp),%rbx
 105ceca:	00 
 105cecb:	48 83 fd ff          	cmp    $0xffffffffffffffff,%rbp
 105cecf:	0f 84 d7 fd ff ff    	je     105ccac <my.vm::run+0x177c>
 105ced5:	48 8d bc 24 00 03 00 	lea    0x300(%rsp),%rdi
 105cedc:	00 
 105cedd:	4c 89 f6             	mov    %r14,%rsi
 105cee0:	48 89 ea             	mov    %rbp,%rdx
 105cee3:	e8 08 dc 00 00       	call   106aaf0 <my.heap::upvalue_obj>
 105cee8:	48 8b b4 24 10 03 00 	mov    0x310(%rsp),%rsi
 105ceef:	00 
 105cef0:	44 0f b6 8c 24 08 03 	movzbl 0x308(%rsp),%r9d
 105cef7:	00 00 
 105cef9:	4c 8b 94 24 00 03 00 	mov    0x300(%rsp),%r10
 105cf00:	00 
 105cf01:	4d 8b 06             	mov    (%r14),%r8
 105cf04:	49 8b 50 08          	mov    0x8(%r8),%rdx
 105cf08:	48 39 d5             	cmp    %rdx,%rbp
 105cf0b:	0f 83 86 00 00 00    	jae    105cf97 <my.vm::run+0x1a67>
 105cf11:	48 89 e8             	mov    %rbp,%rax
 105cf14:	4c 6b d8 38          	imul   $0x38,%rax,%r11
 105cf18:	43 0f b6 54 18 20    	movzbl 0x20(%r8,%r11,1),%edx
 105cf1e:	4b 8b 44 18 28       	mov    0x28(%r8,%r11,1),%rax
 105cf23:	4b 8b 7c 18 30       	mov    0x30(%r8,%r11,1),%rdi
 105cf28:	4b 8b 4c 18 38       	mov    0x38(%r8,%r11,1),%rcx
 105cf2d:	4b 8b 6c 18 40       	mov    0x40(%r8,%r11,1),%rbp
 105cf32:	4f 8b 6c 18 48       	mov    0x48(%r8,%r11,1),%r13
 105cf37:	4b c7 44 18 20 05 00 	movq   $0x5,0x20(%r8,%r11,1)
 105cf3e:	00 00 
 105cf40:	4f 89 54 18 28       	mov    %r10,0x28(%r8,%r11,1)
 105cf45:	45 0f b6 c9          	movzbl %r9b,%r9d
 105cf49:	4f 89 4c 18 30       	mov    %r9,0x30(%r8,%r11,1)
 105cf4e:	4b 89 74 18 38       	mov    %rsi,0x38(%r8,%r11,1)
 105cf53:	4b 89 5c 18 40       	mov    %rbx,0x40(%r8,%r11,1)
 105cf58:	ff ca                	dec    %edx
 105cf5a:	83 fa 08             	cmp    $0x8,%edx
 105cf5d:	0f 87 50 fd ff ff    	ja     105ccb3 <my.vm::run+0x1783>
 105cf63:	48 8d 35 fe a4 fa ff 	lea    -0x55b02(%rip),%rsi        # 1007468 <core_number_pairs+0x208>
 105cf6a:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105cf6e:	48 01 f2             	add    %rsi,%rdx
 105cf71:	ff e2                	jmp    *%rdx
 105cf73:	e8 88 73 fc ff       	call   1024300 <myl_core_drop_owned>
 105cf78:	e9 36 fd ff ff       	jmp    105ccb3 <my.vm::run+0x1783>
 105cf7d:	48 89 cf             	mov    %rcx,%rdi
 105cf80:	e8 7b 73 fc ff       	call   1024300 <myl_core_drop_owned>
 105cf85:	48 89 ef             	mov    %rbp,%rdi
 105cf88:	e8 73 73 fc ff       	call   1024300 <myl_core_drop_owned>
 105cf8d:	4c 89 ef             	mov    %r13,%rdi
 105cf90:	eb e1                	jmp    105cf73 <my.vm::run+0x1a43>
 105cf92:	48 89 c7             	mov    %rax,%rdi
 105cf95:	eb dc                	jmp    105cf73 <my.vm::run+0x1a43>
 105cf97:	48 89 e8             	mov    %rbp,%rax
 105cf9a:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cf9e:	48 21 d0             	and    %rdx,%rax
 105cfa1:	48 01 e8             	add    %rbp,%rax
 105cfa4:	48 39 d0             	cmp    %rdx,%rax
 105cfa7:	0f 82 67 ff ff ff    	jb     105cf14 <my.vm::run+0x19e4>
 105cfad:	e9 5d 20 00 00       	jmp    105f00f <my.vm::run+0x3adf>
 105cfb2:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105cfb9:	48 89 c6             	mov    %rax,%rsi
 105cfbc:	48 ff ce             	dec    %rsi
 105cfbf:	0f 80 7a 1b 00 00    	jo     105eb3f <my.vm::run+0x360f>
 105cfc5:	4c 89 cd             	mov    %r9,%rbp
 105cfc8:	49 8b 46 78          	mov    0x78(%r14),%rax
 105cfcc:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cfd0:	49 89 f1             	mov    %rsi,%r9
 105cfd3:	49 c1 f9 3f          	sar    $0x3f,%r9
 105cfd7:	49 21 d1             	and    %rdx,%r9
 105cfda:	48 89 f1             	mov    %rsi,%rcx
 105cfdd:	48 39 d6             	cmp    %rdx,%rsi
 105cfe0:	0f 83 4d 10 00 00    	jae    105e033 <my.vm::run+0x2b03>
 105cfe6:	4c 89 54 24 10       	mov    %r10,0x10(%rsp)
 105cfeb:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105cfef:	48 c1 e1 04          	shl    $0x4,%rcx
 105cff3:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105cff9:	48 8b 44 08 28       	mov    0x28(%rax,%rcx,1),%rax
 105cffe:	41 83 f8 02          	cmp    $0x2,%r8d
 105d002:	0f 84 31 0a 00 00    	je     105da39 <my.vm::run+0x2509>
 105d008:	41 83 f8 03          	cmp    $0x3,%r8d
 105d00c:	0f 85 7b 0a 00 00    	jne    105da8d <my.vm::run+0x255d>
 105d012:	4d 8b 16             	mov    (%r14),%r10
 105d015:	49 8b 4a 08          	mov    0x8(%r10),%rcx
 105d019:	48 39 c8             	cmp    %rcx,%rax
 105d01c:	0f 83 d8 13 00 00    	jae    105e3fa <my.vm::run+0x2eca>
 105d022:	49 89 c0             	mov    %rax,%r8
 105d025:	49 6b c0 38          	imul   $0x38,%r8,%rax
 105d029:	41 83 7c 02 20 01    	cmpl   $0x1,0x20(%r10,%rax,1)
 105d02f:	0f 85 58 0a 00 00    	jne    105da8d <my.vm::run+0x255d>
 105d035:	48 89 f0             	mov    %rsi,%rax
 105d038:	48 ff c8             	dec    %rax
 105d03b:	0f 80 4a 1e 00 00    	jo     105ee8b <my.vm::run+0x395b>
 105d041:	49 89 c0             	mov    %rax,%r8
 105d044:	48 39 d0             	cmp    %rdx,%rax
 105d047:	0f 83 5c 14 00 00    	jae    105e4a9 <my.vm::run+0x2f79>
 105d04d:	49 c1 e0 04          	shl    $0x4,%r8
 105d051:	42 80 3c 07 03       	cmpb   $0x3,(%rdi,%r8,1)
 105d056:	0f 85 31 0a 00 00    	jne    105da8d <my.vm::run+0x255d>
 105d05c:	4c 89 db             	mov    %r11,%rbx
 105d05f:	4e 8b 44 07 08       	mov    0x8(%rdi,%r8,1),%r8
 105d064:	49 39 c8             	cmp    %rcx,%r8
 105d067:	0f 83 0d 15 00 00    	jae    105e57a <my.vm::run+0x304a>
 105d06d:	4d 89 c3             	mov    %r8,%r11
 105d070:	49 83 c2 20          	add    $0x20,%r10
 105d074:	49 6b cb 38          	imul   $0x38,%r11,%rcx
 105d078:	41 83 3c 0a 01       	cmpl   $0x1,(%r10,%rcx,1)
 105d07d:	49 89 db             	mov    %rbx,%r11
 105d080:	0f 85 07 0a 00 00    	jne    105da8d <my.vm::run+0x255d>
 105d086:	48 39 d6             	cmp    %rdx,%rsi
 105d089:	0f 83 06 15 00 00    	jae    105e595 <my.vm::run+0x3065>
 105d08f:	49 89 f1             	mov    %rsi,%r9
 105d092:	49 c1 e1 04          	shl    $0x4,%r9
 105d096:	42 0f b6 0c 0f       	movzbl (%rdi,%r9,1),%ecx
 105d09b:	83 f9 03             	cmp    $0x3,%ecx
 105d09e:	0f 85 7e 1e 00 00    	jne    105ef22 <my.vm::run+0x39f2>
 105d0a4:	4a 8b 4c 0f 08       	mov    0x8(%rdi,%r9,1),%rcx
 105d0a9:	48 39 d0             	cmp    %rdx,%rax
 105d0ac:	0f 83 f4 14 00 00    	jae    105e5a6 <my.vm::run+0x3076>
 105d0b2:	48 89 c6             	mov    %rax,%rsi
 105d0b5:	48 c1 e6 04          	shl    $0x4,%rsi
 105d0b9:	0f b6 04 37          	movzbl (%rdi,%rsi,1),%eax
 105d0bd:	83 f8 03             	cmp    $0x3,%eax
 105d0c0:	0f 85 89 1e 00 00    	jne    105ef4f <my.vm::run+0x3a1f>
 105d0c6:	48 01 f7             	add    %rsi,%rdi
 105d0c9:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105d0cd:	48 8d bc 24 40 03 00 	lea    0x340(%rsp),%rdi
 105d0d4:	00 
 105d0d5:	4c 89 f6             	mov    %r14,%rsi
 105d0d8:	e8 a3 1a 01 00       	call   106eb80 <my.lox_strings::concat>
 105d0dd:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105d0e4:	48 89 c6             	mov    %rax,%rsi
 105d0e7:	48 ff ce             	dec    %rsi
 105d0ea:	0f 80 91 1e 00 00    	jo     105ef81 <my.vm::run+0x3a51>
 105d0f0:	48 8b 84 24 40 03 00 	mov    0x340(%rsp),%rax
 105d0f7:	00 
 105d0f8:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105d0fc:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105d100:	48 39 d6             	cmp    %rdx,%rsi
 105d103:	49 89 e9             	mov    %rbp,%r9
 105d106:	49 89 db             	mov    %rbx,%r11
 105d109:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105d10e:	0f 83 ad 14 00 00    	jae    105e5c1 <my.vm::run+0x3091>
 105d114:	49 89 f5             	mov    %rsi,%r13
 105d117:	49 ff cd             	dec    %r13
 105d11a:	0f 80 50 1e 00 00    	jo     105ef70 <my.vm::run+0x3a40>
 105d120:	4c 89 ee             	mov    %r13,%rsi
 105d123:	49 39 d5             	cmp    %rdx,%r13
 105d126:	0f 83 b0 14 00 00    	jae    105e5dc <my.vm::run+0x30ac>
 105d12c:	48 c1 e6 04          	shl    $0x4,%rsi
 105d130:	48 c7 44 31 20 03 00 	movq   $0x3,0x20(%rcx,%rsi,1)
 105d137:	00 00 
 105d139:	48 89 44 31 28       	mov    %rax,0x28(%rcx,%rsi,1)
 105d13e:	e9 82 0a 00 00       	jmp    105dbc5 <my.vm::run+0x2695>
 105d143:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105d14a:	00 
 105d14b:	4c 89 f6             	mov    %r14,%rsi
 105d14e:	4c 89 d2             	mov    %r10,%rdx
 105d151:	4c 89 d9             	mov    %r11,%rcx
 105d154:	4d 89 f8             	mov    %r15,%r8
 105d157:	e8 64 6a 00 00       	call   1063bc0 <my.vm::read_constant>
 105d15c:	0f b6 84 24 88 00 00 	movzbl 0x88(%rsp),%eax
 105d163:	00 
 105d164:	83 f8 03             	cmp    $0x3,%eax
 105d167:	0f 85 d1 15 00 00    	jne    105e73e <my.vm::run+0x320e>
 105d16d:	4c 8b 8c 24 b0 00 00 	mov    0xb0(%rsp),%r9
 105d174:	00 
 105d175:	4c 8b 84 24 a8 00 00 	mov    0xa8(%rsp),%r8
 105d17c:	00 
 105d17d:	48 8b 8c 24 a0 00 00 	mov    0xa0(%rsp),%rcx
 105d184:	00 
 105d185:	4c 8b bc 24 90 00 00 	mov    0x90(%rsp),%r15
 105d18c:	00 
 105d18d:	48 8b 94 24 98 00 00 	mov    0x98(%rsp),%rdx
 105d194:	00 
 105d195:	48 8d bc 24 30 04 00 	lea    0x430(%rsp),%rdi
 105d19c:	00 
 105d19d:	4c 89 f6             	mov    %r14,%rsi
 105d1a0:	e8 fb 6a 00 00       	call   1063ca0 <my.vm::read_byte>
 105d1a5:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d1ac:	48 85 db             	test   %rbx,%rbx
 105d1af:	7f 04                	jg     105d1b5 <my.vm::run+0x1c85>
 105d1b1:	48 03 68 08          	add    0x8(%rax),%rbp
 105d1b5:	4c 8b 8c 24 30 04 00 	mov    0x430(%rsp),%r9
 105d1bc:	00 
 105d1bd:	48 8b 8c 24 48 04 00 	mov    0x448(%rsp),%rcx
 105d1c4:	00 
 105d1c5:	48 c1 e5 05          	shl    $0x5,%rbp
 105d1c9:	48 89 4c 28 30       	mov    %rcx,0x30(%rax,%rbp,1)
 105d1ce:	49 89 86 88 00 00 00 	mov    %rax,0x88(%r14)
 105d1d5:	4c 89 ee             	mov    %r13,%rsi
 105d1d8:	48 ff ce             	dec    %rsi
 105d1db:	0f 80 6f 1a 00 00    	jo     105ec50 <my.vm::run+0x3720>
 105d1e1:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105d1e8:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d1ec:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d1f0:	48 39 d6             	cmp    %rdx,%rsi
 105d1f3:	0f 83 bf 0f 00 00    	jae    105e1b8 <my.vm::run+0x2c88>
 105d1f9:	48 89 f1             	mov    %rsi,%rcx
 105d1fc:	48 c1 e1 04          	shl    $0x4,%rcx
 105d200:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 105d205:	83 fa 03             	cmp    $0x3,%edx
 105d208:	0f 85 4d 15 00 00    	jne    105e75b <my.vm::run+0x322b>
 105d20e:	48 01 c8             	add    %rcx,%rax
 105d211:	48 83 c0 20          	add    $0x20,%rax
 105d215:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105d219:	48 8d bc 24 08 07 00 	lea    0x708(%rsp),%rdi
 105d220:	00 
 105d221:	4c 89 f6             	mov    %r14,%rsi
 105d224:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105d229:	4d 89 f8             	mov    %r15,%r8
 105d22c:	e8 9f 78 00 00       	call   1064ad0 <my.vm::invoke_from_class>
 105d231:	f6 84 24 08 07 00 00 	testb  $0x1,0x708(%rsp)
 105d238:	01 
 105d239:	0f 84 c2 13 00 00    	je     105e601 <my.vm::run+0x30d1>
 105d23f:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105d246:	48 89 de             	mov    %rbx,%rsi
 105d249:	48 ff ce             	dec    %rsi
 105d24c:	0f 80 db 1a 00 00    	jo     105ed2d <my.vm::run+0x37fd>
 105d252:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105d259:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d260:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d264:	48 39 d6             	cmp    %rdx,%rsi
 105d267:	0f 82 94 04 00 00    	jb     105d701 <my.vm::run+0x21d1>
 105d26d:	48 89 f1             	mov    %rsi,%rcx
 105d270:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d274:	48 21 d1             	and    %rdx,%rcx
 105d277:	48 01 f1             	add    %rsi,%rcx
 105d27a:	48 39 d1             	cmp    %rdx,%rcx
 105d27d:	0f 82 81 04 00 00    	jb     105d704 <my.vm::run+0x21d4>
 105d283:	e9 35 1e 00 00       	jmp    105f0bd <my.vm::run+0x3b8d>
 105d288:	4c 89 e8             	mov    %r13,%rax
 105d28b:	4c 89 ee             	mov    %r13,%rsi
 105d28e:	48 ff ce             	dec    %rsi
 105d291:	0f 80 3a 1a 00 00    	jo     105ecd1 <my.vm::run+0x37a1>
 105d297:	4d 89 d5             	mov    %r10,%r13
 105d29a:	4d 89 dc             	mov    %r11,%r12
 105d29d:	4c 89 cd             	mov    %r9,%rbp
 105d2a0:	4c 89 f7             	mov    %r14,%rdi
 105d2a3:	e8 48 79 00 00       	call   1064bf0 <my.vm::close_upvalues>
 105d2a8:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105d2af:	48 89 f1             	mov    %rsi,%rcx
 105d2b2:	48 ff c9             	dec    %rcx
 105d2b5:	0f 80 05 1a 00 00    	jo     105ecc0 <my.vm::run+0x3790>
 105d2bb:	49 89 8e 80 00 00 00 	mov    %rcx,0x80(%r14)
 105d2c2:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d2c6:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105d2cd:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d2d1:	48 89 c8             	mov    %rcx,%rax
 105d2d4:	48 39 d1             	cmp    %rdx,%rcx
 105d2d7:	49 89 e9             	mov    %rbp,%r9
 105d2da:	4d 89 e3             	mov    %r12,%r11
 105d2dd:	4d 89 ea             	mov    %r13,%r10
 105d2e0:	0f 83 f8 0d 00 00    	jae    105e0de <my.vm::run+0x2bae>
 105d2e6:	49 89 c5             	mov    %rax,%r13
 105d2e9:	4c 8d 25 bc a0 fa ff 	lea    -0x55f44(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105d2f0:	e9 2b 0a 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105d2f5:	4c 89 ee             	mov    %r13,%rsi
 105d2f8:	48 ff ce             	dec    %rsi
 105d2fb:	0f 80 52 18 00 00    	jo     105eb53 <my.vm::run+0x3623>
 105d301:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105d308:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d30c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d310:	48 89 f1             	mov    %rsi,%rcx
 105d313:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d317:	48 21 d1             	and    %rdx,%rcx
 105d31a:	48 89 f7             	mov    %rsi,%rdi
 105d31d:	48 39 d6             	cmp    %rdx,%rsi
 105d320:	0f 83 1f 0d 00 00    	jae    105e045 <my.vm::run+0x2b15>
 105d326:	48 c1 e7 04          	shl    $0x4,%rdi
 105d32a:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 105d32f:	85 d2                	test   %edx,%edx
 105d331:	0f 84 aa 07 00 00    	je     105dae1 <my.vm::run+0x25b1>
 105d337:	83 fa 01             	cmp    $0x1,%edx
 105d33a:	0f 85 a5 07 00 00    	jne    105dae5 <my.vm::run+0x25b5>
 105d340:	48 8d 14 38          	lea    (%rax,%rdi,1),%rdx
 105d344:	48 83 c2 20          	add    $0x20,%rdx
 105d348:	0f b6 52 08          	movzbl 0x8(%rdx),%edx
 105d34c:	f6 d2                	not    %dl
 105d34e:	80 e2 01             	and    $0x1,%dl
 105d351:	e9 91 07 00 00       	jmp    105dae7 <my.vm::run+0x25b7>
 105d356:	48 8d bc 24 80 04 00 	lea    0x480(%rsp),%rdi
 105d35d:	00 
 105d35e:	4c 89 f6             	mov    %r14,%rsi
 105d361:	4c 89 d2             	mov    %r10,%rdx
 105d364:	4c 89 d9             	mov    %r11,%rcx
 105d367:	4d 89 f8             	mov    %r15,%r8
 105d36a:	e8 31 69 00 00       	call   1063ca0 <my.vm::read_byte>
 105d36f:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d376:	48 85 db             	test   %rbx,%rbx
 105d379:	7f 04                	jg     105d37f <my.vm::run+0x1e4f>
 105d37b:	48 03 68 08          	add    0x8(%rax),%rbp
 105d37f:	4c 8b 8c 24 80 04 00 	mov    0x480(%rsp),%r9
 105d386:	00 
 105d387:	48 8b 8c 24 98 04 00 	mov    0x498(%rsp),%rcx
 105d38e:	00 
 105d38f:	48 c1 e5 05          	shl    $0x5,%rbp
 105d393:	48 89 4c 28 30       	mov    %rcx,0x30(%rax,%rbp,1)
 105d398:	49 89 86 88 00 00 00 	mov    %rax,0x88(%r14)
 105d39f:	4c 89 e8             	mov    %r13,%rax
 105d3a2:	48 ff c8             	dec    %rax
 105d3a5:	0f 80 01 19 00 00    	jo     105ecac <my.vm::run+0x377c>
 105d3ab:	48 89 c6             	mov    %rax,%rsi
 105d3ae:	4c 29 ce             	sub    %r9,%rsi
 105d3b1:	0f 80 e3 18 00 00    	jo     105ec9a <my.vm::run+0x376a>
 105d3b7:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d3bb:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d3bf:	48 39 d6             	cmp    %rdx,%rsi
 105d3c2:	0f 83 38 0d 00 00    	jae    105e100 <my.vm::run+0x2bd0>
 105d3c8:	48 89 f1             	mov    %rsi,%rcx
 105d3cb:	48 c1 e1 04          	shl    $0x4,%rcx
 105d3cf:	4c 8b 44 08 28       	mov    0x28(%rax,%rcx,1),%r8
 105d3d4:	8b 4c 08 20          	mov    0x20(%rax,%rcx,1),%ecx
 105d3d8:	48 8b 44 24 78       	mov    0x78(%rsp),%rax
 105d3dd:	48 89 04 24          	mov    %rax,(%rsp)
 105d3e1:	48 8d bc 24 f8 07 00 	lea    0x7f8(%rsp),%rdi
 105d3e8:	00 
 105d3e9:	4c 89 f6             	mov    %r14,%rsi
 105d3ec:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105d3f1:	e8 1a 70 00 00       	call   1064410 <my.vm::call_value>
 105d3f6:	f6 84 24 f8 07 00 00 	testb  $0x1,0x7f8(%rsp)
 105d3fd:	01 
 105d3fe:	0f 84 fd 11 00 00    	je     105e601 <my.vm::run+0x30d1>
 105d404:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105d40b:	48 89 de             	mov    %rbx,%rsi
 105d40e:	48 ff ce             	dec    %rsi
 105d411:	0f 80 2a 19 00 00    	jo     105ed41 <my.vm::run+0x3811>
 105d417:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105d41e:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d425:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d429:	48 39 d6             	cmp    %rdx,%rsi
 105d42c:	0f 82 cf 02 00 00    	jb     105d701 <my.vm::run+0x21d1>
 105d432:	48 89 f1             	mov    %rsi,%rcx
 105d435:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d439:	48 21 d1             	and    %rdx,%rcx
 105d43c:	48 01 f1             	add    %rsi,%rcx
 105d43f:	48 39 d1             	cmp    %rdx,%rcx
 105d442:	0f 82 bc 02 00 00    	jb     105d704 <my.vm::run+0x21d4>
 105d448:	e9 7c 1c 00 00       	jmp    105f0c9 <my.vm::run+0x3b99>
 105d44d:	4c 8d a4 24 88 00 00 	lea    0x88(%rsp),%r12
 105d454:	00 
 105d455:	4c 89 e7             	mov    %r12,%rdi
 105d458:	4c 89 f6             	mov    %r14,%rsi
 105d45b:	4c 89 d2             	mov    %r10,%rdx
 105d45e:	4c 89 d9             	mov    %r11,%rcx
 105d461:	4d 89 f8             	mov    %r15,%r8
 105d464:	e8 57 67 00 00       	call   1063bc0 <my.vm::read_constant>
 105d469:	0f b6 84 24 88 00 00 	movzbl 0x88(%rsp),%eax
 105d470:	00 
 105d471:	83 f8 03             	cmp    $0x3,%eax
 105d474:	0f 85 c9 13 00 00    	jne    105e843 <my.vm::run+0x3313>
 105d47a:	4c 8b 8c 24 b0 00 00 	mov    0xb0(%rsp),%r9
 105d481:	00 
 105d482:	4c 8b 84 24 a8 00 00 	mov    0xa8(%rsp),%r8
 105d489:	00 
 105d48a:	48 8b 8c 24 a0 00 00 	mov    0xa0(%rsp),%rcx
 105d491:	00 
 105d492:	48 8b 84 24 90 00 00 	mov    0x90(%rsp),%rax
 105d499:	00 
 105d49a:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105d49f:	48 8b 94 24 98 00 00 	mov    0x98(%rsp),%rdx
 105d4a6:	00 
 105d4a7:	48 8d bc 24 58 04 00 	lea    0x458(%rsp),%rdi
 105d4ae:	00 
 105d4af:	4c 89 f6             	mov    %r14,%rsi
 105d4b2:	e8 e9 67 00 00       	call   1063ca0 <my.vm::read_byte>
 105d4b7:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d4be:	48 85 db             	test   %rbx,%rbx
 105d4c1:	7f 04                	jg     105d4c7 <my.vm::run+0x1f97>
 105d4c3:	48 03 68 08          	add    0x8(%rax),%rbp
 105d4c7:	48 8b 9c 24 58 04 00 	mov    0x458(%rsp),%rbx
 105d4ce:	00 
 105d4cf:	48 8b 8c 24 70 04 00 	mov    0x470(%rsp),%rcx
 105d4d6:	00 
 105d4d7:	48 c1 e5 05          	shl    $0x5,%rbp
 105d4db:	48 89 4c 28 30       	mov    %rcx,0x30(%rax,%rbp,1)
 105d4e0:	49 89 86 88 00 00 00 	mov    %rax,0x88(%r14)
 105d4e7:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105d4ee:	4c 89 e8             	mov    %r13,%rax
 105d4f1:	48 ff c8             	dec    %rax
 105d4f4:	0f 80 2e 17 00 00    	jo     105ec28 <my.vm::run+0x36f8>
 105d4fa:	48 89 c6             	mov    %rax,%rsi
 105d4fd:	48 29 de             	sub    %rbx,%rsi
 105d500:	0f 80 ff 16 00 00    	jo     105ec05 <my.vm::run+0x36d5>
 105d506:	4d 8b 7e 78          	mov    0x78(%r14),%r15
 105d50a:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105d50e:	48 39 d6             	cmp    %rdx,%rsi
 105d511:	0f 83 d7 0c 00 00    	jae    105e1ee <my.vm::run+0x2cbe>
 105d517:	48 89 f0             	mov    %rsi,%rax
 105d51a:	48 c1 e0 04          	shl    $0x4,%rax
 105d51e:	41 80 7c 07 20 03    	cmpb   $0x3,0x20(%r15,%rax,1)
 105d524:	0f 85 80 01 00 00    	jne    105d6aa <my.vm::run+0x217a>
 105d52a:	49 8b 6c 07 28       	mov    0x28(%r15,%rax,1),%rbp
 105d52f:	49 8b 06             	mov    (%r14),%rax
 105d532:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d536:	48 89 e9             	mov    %rbp,%rcx
 105d539:	48 39 d5             	cmp    %rdx,%rbp
 105d53c:	0f 83 4c 0e 00 00    	jae    105e38e <my.vm::run+0x2e5e>
 105d542:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105d546:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 105d54b:	0f 85 59 01 00 00    	jne    105d6aa <my.vm::run+0x217a>
 105d551:	4c 89 f7             	mov    %r14,%rdi
 105d554:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 105d559:	4c 89 e6             	mov    %r12,%rsi
 105d55c:	e8 bf d1 00 00       	call   106a720 <my.heap::string_hash>
 105d561:	4c 89 f7             	mov    %r14,%rdi
 105d564:	48 89 ee             	mov    %rbp,%rsi
 105d567:	4c 89 e2             	mov    %r12,%rdx
 105d56a:	89 c1                	mov    %eax,%ecx
 105d56c:	e8 8f d7 00 00       	call   106ad00 <my.heap::instance_field>
 105d571:	3c 01                	cmp    $0x1,%al
 105d573:	0f 85 1a 08 00 00    	jne    105dd93 <my.vm::run+0x2863>
 105d579:	4c 89 e8             	mov    %r13,%rax
 105d57c:	48 29 d8             	sub    %rbx,%rax
 105d57f:	0f 80 8b 19 00 00    	jo     105ef10 <my.vm::run+0x39e0>
 105d585:	48 89 c6             	mov    %rax,%rsi
 105d588:	48 ff ce             	dec    %rsi
 105d58b:	0f 80 6b 19 00 00    	jo     105eefc <my.vm::run+0x39cc>
 105d591:	49 89 c8             	mov    %rcx,%r8
 105d594:	49 8b 47 08          	mov    0x8(%r15),%rax
 105d598:	48 39 c6             	cmp    %rax,%rsi
 105d59b:	0f 83 59 0f 00 00    	jae    105e4fa <my.vm::run+0x2fca>
 105d5a1:	48 89 f1             	mov    %rsi,%rcx
 105d5a4:	49 83 c7 20          	add    $0x20,%r15
 105d5a8:	48 c1 e1 04          	shl    $0x4,%rcx
 105d5ac:	0f b6 c2             	movzbl %dl,%eax
 105d5af:	49 89 04 0f          	mov    %rax,(%r15,%rcx,1)
 105d5b3:	4d 89 44 0f 08       	mov    %r8,0x8(%r15,%rcx,1)
 105d5b8:	48 8b 44 24 78       	mov    0x78(%rsp),%rax
 105d5bd:	48 89 04 24          	mov    %rax,(%rsp)
 105d5c1:	0f b6 ca             	movzbl %dl,%ecx
 105d5c4:	4c 8d a4 24 88 00 00 	lea    0x88(%rsp),%r12
 105d5cb:	00 
 105d5cc:	4c 89 e7             	mov    %r12,%rdi
 105d5cf:	4c 89 f6             	mov    %r14,%rsi
 105d5d2:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105d5d7:	49 89 d9             	mov    %rbx,%r9
 105d5da:	e8 31 6e 00 00       	call   1064410 <my.vm::call_value>
 105d5df:	41 f6 04 24 01       	testb  $0x1,(%r12)
 105d5e4:	0f 85 e2 00 00 00    	jne    105d6cc <my.vm::run+0x219c>
 105d5ea:	e9 12 10 00 00       	jmp    105e601 <my.vm::run+0x30d1>
 105d5ef:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105d5f6:	49 89 f5             	mov    %rsi,%r13
 105d5f9:	49 ff cd             	dec    %r13
 105d5fc:	0f 80 5b 14 00 00    	jo     105ea5d <my.vm::run+0x352d>
 105d602:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d606:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d60a:	4c 89 e9             	mov    %r13,%rcx
 105d60d:	49 39 d5             	cmp    %rdx,%r13
 105d610:	0f 83 41 0a 00 00    	jae    105e057 <my.vm::run+0x2b27>
 105d616:	48 c1 e1 04          	shl    $0x4,%rcx
 105d61a:	80 7c 08 20 02       	cmpb   $0x2,0x20(%rax,%rcx,1)
 105d61f:	0f 85 fc 00 00 00    	jne    105d721 <my.vm::run+0x21f1>
 105d625:	48 01 c8             	add    %rcx,%rax
 105d628:	48 83 c0 20          	add    $0x20,%rax
 105d62c:	48 c7 00 02 00 00 00 	movq   $0x2,(%rax)
 105d633:	80 70 0f 80          	xorb   $0x80,0xf(%rax)
 105d637:	e9 89 05 00 00       	jmp    105dbc5 <my.vm::run+0x2695>
 105d63c:	4c 89 54 24 10       	mov    %r10,0x10(%rsp)
 105d641:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 105d646:	4c 89 4c 24 18       	mov    %r9,0x18(%rsp)
 105d64b:	48 8d 0d 0e 55 fb ff 	lea    -0x4aaf2(%rip),%rcx        # 1012b60 <core_number_pairs+0xb900>
 105d652:	48 8d 9c 24 40 03 00 	lea    0x340(%rsp),%rbx
 105d659:	00 
 105d65a:	48 89 df             	mov    %rbx,%rdi
 105d65d:	4c 89 f6             	mov    %r14,%rsi
 105d660:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105d665:	e8 d6 60 00 00       	call   1063740 <my.vm::runtime_error>
 105d66a:	f6 03 01             	testb  $0x1,(%rbx)
 105d66d:	4c 8d 25 38 9d fa ff 	lea    -0x562c8(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105d674:	0f 84 87 0f 00 00    	je     105e601 <my.vm::run+0x30d1>
 105d67a:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105d681:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105d688:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105d68d:	e9 7f 06 00 00       	jmp    105dd11 <my.vm::run+0x27e1>
 105d692:	4c 89 e3             	mov    %r12,%rbx
 105d695:	4d 89 d5             	mov    %r10,%r13
 105d698:	4d 89 dc             	mov    %r11,%r12
 105d69b:	4c 89 cd             	mov    %r9,%rbp
 105d69e:	48 8d 0d bb 56 fb ff 	lea    -0x4a945(%rip),%rcx        # 1012d60 <core_number_pairs+0xbb00>
 105d6a5:	e9 40 e0 ff ff       	jmp    105b6ea <my.vm::run+0x1ba>
 105d6aa:	48 8d 0d 6f 56 fb ff 	lea    -0x4a991(%rip),%rcx        # 1012d20 <core_number_pairs+0xbac0>
 105d6b1:	4c 89 e7             	mov    %r12,%rdi
 105d6b4:	4c 89 f6             	mov    %r14,%rsi
 105d6b7:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105d6bc:	e8 7f 60 00 00       	call   1063740 <my.vm::runtime_error>
 105d6c1:	41 f6 04 24 01       	testb  $0x1,(%r12)
 105d6c6:	0f 84 35 0f 00 00    	je     105e601 <my.vm::run+0x30d1>
 105d6cc:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105d6d3:	48 89 de             	mov    %rbx,%rsi
 105d6d6:	48 ff ce             	dec    %rsi
 105d6d9:	0f 80 76 16 00 00    	jo     105ed55 <my.vm::run+0x3825>
 105d6df:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105d6e6:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d6ed:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d6f1:	48 39 d6             	cmp    %rdx,%rsi
 105d6f4:	4c 8d 25 b1 9c fa ff 	lea    -0x5634f(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105d6fb:	0f 83 ac 0b 00 00    	jae    105e2ad <my.vm::run+0x2d7d>
 105d701:	48 89 f1             	mov    %rsi,%rcx
 105d704:	48 c1 e1 05          	shl    $0x5,%rcx
 105d708:	4c 8b 54 08 20       	mov    0x20(%rax,%rcx,1),%r10
 105d70d:	4c 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%r11
 105d712:	4c 8b 7c 08 30       	mov    0x30(%rax,%rcx,1),%r15
 105d717:	4c 8b 4c 08 38       	mov    0x38(%rax,%rcx,1),%r9
 105d71c:	e9 ff 05 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105d721:	4c 89 e3             	mov    %r12,%rbx
 105d724:	4d 89 d5             	mov    %r10,%r13
 105d727:	4d 89 dc             	mov    %r11,%r12
 105d72a:	4c 89 cd             	mov    %r9,%rbp
 105d72d:	48 8d 0d 4c 55 fb ff 	lea    -0x4aab4(%rip),%rcx        # 1012c80 <core_number_pairs+0xba20>
 105d734:	e9 b1 df ff ff       	jmp    105b6ea <my.vm::run+0x1ba>
 105d739:	4c 89 f7             	mov    %r14,%rdi
 105d73c:	48 89 de             	mov    %rbx,%rsi
 105d73f:	e8 ec cd 00 00       	call   106a530 <my.heap::string_chars>
 105d744:	48 89 c3             	mov    %rax,%rbx
 105d747:	48 8d 3d 92 53 fb ff 	lea    -0x4ac6e(%rip),%rdi        # 1012ae0 <core_number_pairs+0xb880>
 105d74e:	48 89 c6             	mov    %rax,%rsi
 105d751:	e8 aa 1f fd ff       	call   102f700 <myl_core_bytes_concat>
 105d756:	49 89 c4             	mov    %rax,%r12
 105d759:	48 89 df             	mov    %rbx,%rdi
 105d75c:	e8 9f 6b fc ff       	call   1024300 <myl_core_drop_owned>
 105d761:	48 8d 35 b8 53 fb ff 	lea    -0x4ac48(%rip),%rsi        # 1012b20 <core_number_pairs+0xb8c0>
 105d768:	4c 89 e7             	mov    %r12,%rdi
 105d76b:	e8 90 1f fd ff       	call   102f700 <myl_core_bytes_concat>
 105d770:	48 89 c3             	mov    %rax,%rbx
 105d773:	4c 89 e7             	mov    %r12,%rdi
 105d776:	e8 85 6b fc ff       	call   1024300 <myl_core_drop_owned>
 105d77b:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105d782:	00 
 105d783:	4c 89 f6             	mov    %r14,%rsi
 105d786:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105d78b:	48 89 d9             	mov    %rbx,%rcx
 105d78e:	e8 ad 5f 00 00       	call   1063740 <my.vm::runtime_error>
 105d793:	48 89 df             	mov    %rbx,%rdi
 105d796:	e8 65 6b fc ff       	call   1024300 <myl_core_drop_owned>
 105d79b:	f6 84 24 88 00 00 00 	testb  $0x1,0x88(%rsp)
 105d7a2:	01 
 105d7a3:	0f 84 58 0e 00 00    	je     105e601 <my.vm::run+0x30d1>
 105d7a9:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105d7b0:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105d7b7:	4c 8d 25 ee 9b fa ff 	lea    -0x56412(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105d7be:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105d7c3:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105d7c8:	49 89 ea             	mov    %rbp,%r10
 105d7cb:	e9 50 05 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105d7d0:	84 d2                	test   %dl,%dl
 105d7d2:	0f 85 30 16 00 00    	jne    105ee08 <my.vm::run+0x38d8>
 105d7d8:	4c 8b 84 24 38 03 00 	mov    0x338(%rsp),%r8
 105d7df:	00 
 105d7e0:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105d7e4:	48 39 d6             	cmp    %rdx,%rsi
 105d7e7:	49 89 eb             	mov    %rbp,%r11
 105d7ea:	4d 89 e2             	mov    %r12,%r10
 105d7ed:	0f 83 d1 0b 00 00    	jae    105e3c4 <my.vm::run+0x2e94>
 105d7f3:	48 89 f0             	mov    %rsi,%rax
 105d7f6:	48 c1 e0 04          	shl    $0x4,%rax
 105d7fa:	c5 f9 10 44 07 20    	vmovupd 0x20(%rdi,%rax,1),%xmm0
 105d800:	49 8b 36             	mov    (%r14),%rsi
 105d803:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105d807:	48 39 d3             	cmp    %rdx,%rbx
 105d80a:	0f 83 cf 0b 00 00    	jae    105e3df <my.vm::run+0x2eaf>
 105d810:	48 89 d8             	mov    %rbx,%rax
 105d813:	4c 6b c8 38          	imul   $0x38,%rax,%r9
 105d817:	42 0f b6 54 0e 20    	movzbl 0x20(%rsi,%r9,1),%edx
 105d81d:	4a 8b 44 0e 28       	mov    0x28(%rsi,%r9,1),%rax
 105d822:	4a 8b 7c 0e 30       	mov    0x30(%rsi,%r9,1),%rdi
 105d827:	4a 8b 4c 0e 38       	mov    0x38(%rsi,%r9,1),%rcx
 105d82c:	4a 8b 5c 0e 40       	mov    0x40(%rsi,%r9,1),%rbx
 105d831:	48 89 5c 24 10       	mov    %rbx,0x10(%rsp)
 105d836:	4a 8b 5c 0e 48       	mov    0x48(%rsi,%r9,1),%rbx
 105d83b:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
 105d840:	4a c7 44 0e 20 05 00 	movq   $0x5,0x20(%rsi,%r9,1)
 105d847:	00 00 
 105d849:	4a c7 44 0e 28 ff ff 	movq   $0xffffffffffffffff,0x28(%rsi,%r9,1)
 105d850:	ff ff 
 105d852:	c5 f9 54 05 86 6b fa 	vandpd -0x5947a(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105d859:	ff 
 105d85a:	c4 a1 79 11 44 0e 30 	vmovupd %xmm0,0x30(%rsi,%r9,1)
 105d861:	4e 89 44 0e 40       	mov    %r8,0x40(%rsi,%r9,1)
 105d866:	ff ca                	dec    %edx
 105d868:	83 fa 08             	cmp    $0x8,%edx
 105d86b:	4d 89 e9             	mov    %r13,%r9
 105d86e:	0f 87 1b 01 00 00    	ja     105d98f <my.vm::run+0x245f>
 105d874:	48 8d 35 4d 9c fa ff 	lea    -0x563b3(%rip),%rsi        # 10074c8 <core_number_pairs+0x268>
 105d87b:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105d87f:	48 01 f2             	add    %rsi,%rdx
 105d882:	ff e2                	jmp    *%rdx
 105d884:	e8 77 6a fc ff       	call   1024300 <myl_core_drop_owned>
 105d889:	4d 89 e2             	mov    %r12,%r10
 105d88c:	49 89 eb             	mov    %rbp,%r11
 105d88f:	4d 89 e9             	mov    %r13,%r9
 105d892:	e9 f8 00 00 00       	jmp    105d98f <my.vm::run+0x245f>
 105d897:	48 8b 84 24 f0 02 00 	mov    0x2f0(%rsp),%rax
 105d89e:	00 
 105d89f:	0f b6 bc 24 e8 02 00 	movzbl 0x2e8(%rsp),%edi
 105d8a6:	00 
 105d8a7:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105d8ab:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105d8b2:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105d8b6:	49 89 f0             	mov    %rsi,%r8
 105d8b9:	48 39 d6             	cmp    %rdx,%rsi
 105d8bc:	0f 83 e7 0a 00 00    	jae    105e3a9 <my.vm::run+0x2e79>
 105d8c2:	49 c1 e0 04          	shl    $0x4,%r8
 105d8c6:	40 0f b6 d7          	movzbl %dil,%edx
 105d8ca:	4a 89 54 01 20       	mov    %rdx,0x20(%rcx,%r8,1)
 105d8cf:	4a 89 44 01 28       	mov    %rax,0x28(%rcx,%r8,1)
 105d8d4:	49 89 f5             	mov    %rsi,%r13
 105d8d7:	49 ff c5             	inc    %r13
 105d8da:	49 89 d9             	mov    %rbx,%r9
 105d8dd:	49 89 eb             	mov    %rbp,%r11
 105d8e0:	4d 89 e2             	mov    %r12,%r10
 105d8e3:	4c 8d 25 c2 9a fa ff 	lea    -0x5653e(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105d8ea:	0f 81 d8 02 00 00    	jno    105dbc8 <my.vm::run+0x2698>
 105d8f0:	e9 44 15 00 00       	jmp    105ee39 <my.vm::run+0x3909>
 105d8f5:	4d 89 e9             	mov    %r13,%r9
 105d8f8:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105d8fd:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105d902:	49 8b 0e             	mov    (%r14),%rcx
 105d905:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105d909:	48 8b 74 24 68       	mov    0x68(%rsp),%rsi
 105d90e:	48 39 d6             	cmp    %rdx,%rsi
 105d911:	0f 83 63 09 00 00    	jae    105e27a <my.vm::run+0x2d4a>
 105d917:	48 89 f0             	mov    %rsi,%rax
 105d91a:	4c 6b c0 38          	imul   $0x38,%rax,%r8
 105d91e:	42 0f b6 54 01 20    	movzbl 0x20(%rcx,%r8,1),%edx
 105d924:	4a 8b 7c 01 28       	mov    0x28(%rcx,%r8,1),%rdi
 105d929:	4a 8b 74 01 30       	mov    0x30(%rcx,%r8,1),%rsi
 105d92e:	4a 8b 44 01 38       	mov    0x38(%rcx,%r8,1),%rax
 105d933:	4a 8b 5c 01 40       	mov    0x40(%rcx,%r8,1),%rbx
 105d938:	4e 8b 64 01 48       	mov    0x48(%rcx,%r8,1),%r12
 105d93d:	4a c7 44 01 20 04 00 	movq   $0x4,0x20(%rcx,%r8,1)
 105d944:	00 00 
 105d946:	4c 8b 6c 24 60       	mov    0x60(%rsp),%r13
 105d94b:	4e 89 6c 01 28       	mov    %r13,0x28(%rcx,%r8,1)
 105d950:	4c 8b 6c 24 40       	mov    0x40(%rsp),%r13
 105d955:	4e 89 6c 01 30       	mov    %r13,0x30(%rcx,%r8,1)
 105d95a:	83 fa 09             	cmp    $0x9,%edx
 105d95d:	77 30                	ja     105d98f <my.vm::run+0x245f>
 105d95f:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105d964:	0f a3 d1             	bt     %edx,%ecx
 105d967:	0f 83 94 00 00 00    	jae    105da01 <my.vm::run+0x24d1>
 105d96d:	48 89 f7             	mov    %rsi,%rdi
 105d970:	4c 89 cb             	mov    %r9,%rbx
 105d973:	4d 89 dc             	mov    %r11,%r12
 105d976:	4d 89 d6             	mov    %r10,%r14
 105d979:	e8 82 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d97e:	4d 89 f2             	mov    %r14,%r10
 105d981:	4c 8b b4 24 80 00 00 	mov    0x80(%rsp),%r14
 105d988:	00 
 105d989:	4d 89 e3             	mov    %r12,%r11
 105d98c:	49 89 d9             	mov    %rbx,%r9
 105d98f:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105d996:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105d99d:	4c 8d 25 08 9a fa ff 	lea    -0x565f8(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105d9a4:	e9 77 03 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105d9a9:	83 fa 01             	cmp    $0x1,%edx
 105d9ac:	0f 84 9d e2 ff ff    	je     105bc4f <my.vm::run+0x71f>
 105d9b2:	83 fa 02             	cmp    $0x2,%edx
 105d9b5:	0f 85 a1 e2 ff ff    	jne    105bc5c <my.vm::run+0x72c>
 105d9bb:	48 89 cf             	mov    %rcx,%rdi
 105d9be:	e8 3d 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d9c3:	4c 89 e7             	mov    %r12,%rdi
 105d9c6:	e8 35 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d9cb:	48 8b 7c 24 58       	mov    0x58(%rsp),%rdi
 105d9d0:	e9 7a e2 ff ff       	jmp    105bc4f <my.vm::run+0x71f>
 105d9d5:	41 83 f8 01          	cmp    $0x1,%r8d
 105d9d9:	0f 84 18 e0 ff ff    	je     105b9f7 <my.vm::run+0x4c7>
 105d9df:	41 83 f8 02          	cmp    $0x2,%r8d
 105d9e3:	0f 85 18 e0 ff ff    	jne    105ba01 <my.vm::run+0x4d1>
 105d9e9:	48 89 c7             	mov    %rax,%rdi
 105d9ec:	e8 0f 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d9f1:	48 89 df             	mov    %rbx,%rdi
 105d9f4:	e8 07 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d9f9:	4c 89 e7             	mov    %r12,%rdi
 105d9fc:	e9 f6 df ff ff       	jmp    105b9f7 <my.vm::run+0x4c7>
 105da01:	83 fa 01             	cmp    $0x1,%edx
 105da04:	0f 84 66 ff ff ff    	je     105d970 <my.vm::run+0x2440>
 105da0a:	83 fa 02             	cmp    $0x2,%edx
 105da0d:	75 80                	jne    105d98f <my.vm::run+0x245f>
 105da0f:	48 89 c7             	mov    %rax,%rdi
 105da12:	4d 89 cd             	mov    %r9,%r13
 105da15:	4c 89 dd             	mov    %r11,%rbp
 105da18:	4d 89 d6             	mov    %r10,%r14
 105da1b:	e8 e0 68 fc ff       	call   1024300 <myl_core_drop_owned>
 105da20:	48 89 df             	mov    %rbx,%rdi
 105da23:	e8 d8 68 fc ff       	call   1024300 <myl_core_drop_owned>
 105da28:	4d 89 f2             	mov    %r14,%r10
 105da2b:	49 89 eb             	mov    %rbp,%r11
 105da2e:	4d 89 e9             	mov    %r13,%r9
 105da31:	4c 89 e7             	mov    %r12,%rdi
 105da34:	e9 37 ff ff ff       	jmp    105d970 <my.vm::run+0x2440>
 105da39:	49 89 f5             	mov    %rsi,%r13
 105da3c:	49 ff cd             	dec    %r13
 105da3f:	0f 80 05 14 00 00    	jo     105ee4a <my.vm::run+0x391a>
 105da45:	4c 89 e9             	mov    %r13,%rcx
 105da48:	49 39 d5             	cmp    %rdx,%r13
 105da4b:	0f 83 c4 09 00 00    	jae    105e415 <my.vm::run+0x2ee5>
 105da51:	48 c1 e1 04          	shl    $0x4,%rcx
 105da55:	80 3c 0f 02          	cmpb   $0x2,(%rdi,%rcx,1)
 105da59:	75 32                	jne    105da8d <my.vm::run+0x255d>
 105da5b:	48 01 cf             	add    %rcx,%rdi
 105da5e:	c4 e1 f9 6e c0       	vmovq  %rax,%xmm0
 105da63:	c5 fb 58 47 08       	vaddsd 0x8(%rdi),%xmm0,%xmm0
 105da68:	48 c7 07 02 00 00 00 	movq   $0x2,(%rdi)
 105da6f:	c5 fb 11 47 08       	vmovsd %xmm0,0x8(%rdi)
 105da74:	49 ff c5             	inc    %r13
 105da77:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105da7e:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105da85:	49 89 e9             	mov    %rbp,%r9
 105da88:	e9 89 02 00 00       	jmp    105dd16 <my.vm::run+0x27e6>
 105da8d:	4c 89 e3             	mov    %r12,%rbx
 105da90:	4d 89 dc             	mov    %r11,%r12
 105da93:	48 8d 0d 86 51 fb ff 	lea    -0x4ae7a(%rip),%rcx        # 1012c20 <core_number_pairs+0xb9c0>
 105da9a:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105daa1:	00 
 105daa2:	4c 89 f6             	mov    %r14,%rsi
 105daa5:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105daaa:	e8 91 5c 00 00       	call   1063740 <my.vm::runtime_error>
 105daaf:	f6 84 24 88 00 00 00 	testb  $0x1,0x88(%rsp)
 105dab6:	01 
 105dab7:	0f 84 44 0b 00 00    	je     105e601 <my.vm::run+0x30d1>
 105dabd:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105dac4:	49 8b 86 90 00 00 00 	mov    0x90(%r14),%rax
 105dacb:	49 89 e9             	mov    %rbp,%r9
 105dace:	4d 89 e3             	mov    %r12,%r11
 105dad1:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105dad6:	49 89 dc             	mov    %rbx,%r12
 105dad9:	48 89 c3             	mov    %rax,%rbx
 105dadc:	e9 3f 02 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105dae1:	b2 01                	mov    $0x1,%dl
 105dae3:	eb 02                	jmp    105dae7 <my.vm::run+0x25b7>
 105dae5:	31 d2                	xor    %edx,%edx
 105dae7:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105daeb:	49 89 f0             	mov    %rsi,%r8
 105daee:	49 c1 e0 04          	shl    $0x4,%r8
 105daf2:	49 01 f8             	add    %rdi,%r8
 105daf5:	48 c1 e1 04          	shl    $0x4,%rcx
 105daf9:	4a c7 04 01 01 00 00 	movq   $0x1,(%rcx,%r8,1)
 105db00:	00 
 105db01:	42 88 54 01 08       	mov    %dl,0x8(%rcx,%r8,1)
 105db06:	49 89 46 78          	mov    %rax,0x78(%r14)
 105db0a:	48 ff c6             	inc    %rsi
 105db0d:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105db14:	49 89 f5             	mov    %rsi,%r13
 105db17:	e9 04 02 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105db1c:	41 80 f8 01          	cmp    $0x1,%r8b
 105db20:	4d 89 d1             	mov    %r10,%r9
 105db23:	0f 85 7e 01 00 00    	jne    105dca7 <my.vm::run+0x2777>
 105db29:	31 fe                	xor    %edi,%esi
 105db2b:	40 80 f6 01          	xor    $0x1,%sil
 105db2f:	e9 7c 01 00 00       	jmp    105dcb0 <my.vm::run+0x2780>
 105db34:	41 80 f8 02          	cmp    $0x2,%r8b
 105db38:	0f 85 6d 01 00 00    	jne    105dcab <my.vm::run+0x277b>
 105db3e:	c4 e1 f9 6e c6       	vmovq  %rsi,%xmm0
 105db43:	c4 e1 f9 6e cf       	vmovq  %rdi,%xmm1
 105db48:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 105db4d:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 105db52:	83 e6 01             	and    $0x1,%esi
 105db55:	e9 53 01 00 00       	jmp    105dcad <my.vm::run+0x277d>
 105db5a:	48 8d 9c 24 28 05 00 	lea    0x528(%rsp),%rbx
 105db61:	00 
 105db62:	e9 79 01 00 00       	jmp    105dce0 <my.vm::run+0x27b0>
 105db67:	41 80 f8 03          	cmp    $0x3,%r8b
 105db6b:	41 0f 94 c0          	sete   %r8b
 105db6f:	48 39 fe             	cmp    %rdi,%rsi
 105db72:	40 0f 94 c6          	sete   %sil
 105db76:	44 20 c6             	and    %r8b,%sil
 105db79:	e9 2f 01 00 00       	jmp    105dcad <my.vm::run+0x277d>
 105db7e:	48 8d 9c 24 40 03 00 	lea    0x340(%rsp),%rbx
 105db85:	00 
 105db86:	e9 55 01 00 00       	jmp    105dce0 <my.vm::run+0x27b0>
 105db8b:	48 8d 9c 24 18 06 00 	lea    0x618(%rsp),%rbx
 105db92:	00 
 105db93:	e9 48 01 00 00       	jmp    105dce0 <my.vm::run+0x27b0>
 105db98:	c5 f3 5c c0          	vsubsd %xmm0,%xmm1,%xmm0
 105db9c:	eb 1b                	jmp    105dbb9 <my.vm::run+0x2689>
 105db9e:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
 105dba2:	48 c7 00 01 00 00 00 	movq   $0x1,(%rax)
 105dba9:	0f 97 40 08          	seta   0x8(%rax)
 105dbad:	eb 16                	jmp    105dbc5 <my.vm::run+0x2695>
 105dbaf:	c5 fb 59 c1          	vmulsd %xmm1,%xmm0,%xmm0
 105dbb3:	eb 04                	jmp    105dbb9 <my.vm::run+0x2689>
 105dbb5:	c5 f3 5e c0          	vdivsd %xmm0,%xmm1,%xmm0
 105dbb9:	48 c7 00 02 00 00 00 	movq   $0x2,(%rax)
 105dbc0:	c5 fb 11 40 08       	vmovsd %xmm0,0x8(%rax)
 105dbc5:	49 ff c5             	inc    %r13
 105dbc8:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105dbcf:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105dbd6:	e9 45 01 00 00       	jmp    105dd20 <my.vm::run+0x27f0>
 105dbdb:	49 89 cc             	mov    %rcx,%r12
 105dbde:	48 89 d5             	mov    %rdx,%rbp
 105dbe1:	48 8b 7c 24 68       	mov    0x68(%rsp),%rdi
 105dbe6:	e8 15 67 fc ff       	call   1024300 <myl_core_drop_owned>
 105dbeb:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105dbef:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 105dbf4:	48 39 d6             	cmp    %rdx,%rsi
 105dbf7:	0f 83 69 08 00 00    	jae    105e466 <my.vm::run+0x2f36>
 105dbfd:	48 89 f0             	mov    %rsi,%rax
 105dc00:	49 89 e8             	mov    %rbp,%r8
 105dc03:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105dc08:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105dc0d:	48 83 c3 20          	add    $0x20,%rbx
 105dc11:	4c 6b c8 38          	imul   $0x38,%rax,%r9
 105dc15:	42 0f b6 0c 0b       	movzbl (%rbx,%r9,1),%ecx
 105dc1a:	4a 8b 7c 0b 08       	mov    0x8(%rbx,%r9,1),%rdi
 105dc1f:	4a 8b 54 0b 10       	mov    0x10(%rbx,%r9,1),%rdx
 105dc24:	4a 8b 44 0b 18       	mov    0x18(%rbx,%r9,1),%rax
 105dc29:	4a 8b 6c 0b 20       	mov    0x20(%rbx,%r9,1),%rbp
 105dc2e:	4a 8b 74 0b 28       	mov    0x28(%rbx,%r9,1),%rsi
 105dc33:	48 89 74 24 40       	mov    %rsi,0x40(%rsp)
 105dc38:	4a c7 04 0b 06 00 00 	movq   $0x6,(%rbx,%r9,1)
 105dc3f:	00 
 105dc40:	48 8b 74 24 60       	mov    0x60(%rsp),%rsi
 105dc45:	4a 89 74 0b 08       	mov    %rsi,0x8(%rbx,%r9,1)
 105dc4a:	4e 89 44 0b 10       	mov    %r8,0x10(%rbx,%r9,1)
 105dc4f:	4e 89 64 0b 18       	mov    %r12,0x18(%rbx,%r9,1)
 105dc54:	83 f9 09             	cmp    $0x9,%ecx
 105dc57:	77 20                	ja     105dc79 <my.vm::run+0x2749>
 105dc59:	be d0 02 00 00       	mov    $0x2d0,%esi
 105dc5e:	0f a3 ce             	bt     %ecx,%esi
 105dc61:	0f 83 68 01 00 00    	jae    105ddcf <my.vm::run+0x289f>
 105dc67:	48 89 d7             	mov    %rdx,%rdi
 105dc6a:	e8 91 66 fc ff       	call   1024300 <myl_core_drop_owned>
 105dc6f:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105dc74:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105dc79:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105dc80:	48 8b 44 24 58       	mov    0x58(%rsp),%rax
 105dc85:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dc89:	49 39 d5             	cmp    %rdx,%r13
 105dc8c:	0f 83 fc 07 00 00    	jae    105e48e <my.vm::run+0x2f5e>
 105dc92:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105dc99:	4c 8d 25 0c 97 fa ff 	lea    -0x568f4(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105dca0:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105dca5:	eb 79                	jmp    105dd20 <my.vm::run+0x27f0>
 105dca7:	31 f6                	xor    %esi,%esi
 105dca9:	eb 05                	jmp    105dcb0 <my.vm::run+0x2780>
 105dcab:	31 f6                	xor    %esi,%esi
 105dcad:	4d 89 d1             	mov    %r10,%r9
 105dcb0:	4d 89 e2             	mov    %r12,%r10
 105dcb3:	48 01 ca             	add    %rcx,%rdx
 105dcb6:	48 c7 02 01 00 00 00 	movq   $0x1,(%rdx)
 105dcbd:	40 80 e6 01          	and    $0x1,%sil
 105dcc1:	40 88 72 08          	mov    %sil,0x8(%rdx)
 105dcc5:	49 89 46 78          	mov    %rax,0x78(%r14)
 105dcc9:	49 ff c5             	inc    %r13
 105dccc:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105dcd3:	49 89 ec             	mov    %rbp,%r12
 105dcd6:	eb 48                	jmp    105dd20 <my.vm::run+0x27f0>
 105dcd8:	48 8d 9c 24 88 00 00 	lea    0x88(%rsp),%rbx
 105dcdf:	00 
 105dce0:	48 8d 0d b9 4e fb ff 	lea    -0x4b147(%rip),%rcx        # 1012ba0 <core_number_pairs+0xb940>
 105dce7:	48 89 df             	mov    %rbx,%rdi
 105dcea:	4c 89 f6             	mov    %r14,%rsi
 105dced:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105dcf2:	e8 49 5a 00 00       	call   1063740 <my.vm::runtime_error>
 105dcf7:	f6 03 01             	testb  $0x1,(%rbx)
 105dcfa:	0f 84 01 09 00 00    	je     105e601 <my.vm::run+0x30d1>
 105dd00:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105dd07:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105dd0e:	49 89 e9             	mov    %rbp,%r9
 105dd11:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105dd16:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105dd1b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 105dd20:	48 89 d8             	mov    %rbx,%rax
 105dd23:	48 ff c8             	dec    %rax
 105dd26:	0f 80 5e 09 00 00    	jo     105e68a <my.vm::run+0x315a>
 105dd2c:	49 8b 8e 88 00 00 00 	mov    0x88(%r14),%rcx
 105dd33:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105dd37:	4c 89 fe             	mov    %r15,%rsi
 105dd3a:	48 39 d0             	cmp    %rdx,%rax
 105dd3d:	0f 82 6d d8 ff ff    	jb     105b5b0 <my.vm::run+0x80>
 105dd43:	48 89 c1             	mov    %rax,%rcx
 105dd46:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105dd4a:	48 21 d1             	and    %rdx,%rcx
 105dd4d:	48 01 c1             	add    %rax,%rcx
 105dd50:	4c 89 fe             	mov    %r15,%rsi
 105dd53:	48 39 d1             	cmp    %rdx,%rcx
 105dd56:	0f 82 54 d8 ff ff    	jb     105b5b0 <my.vm::run+0x80>
 105dd5c:	e9 93 12 00 00       	jmp    105eff4 <my.vm::run+0x3ac4>
 105dd61:	4c 89 f7             	mov    %r14,%rdi
 105dd64:	48 8b 74 24 58       	mov    0x58(%rsp),%rsi
 105dd69:	e8 82 d0 00 00       	call   106adf0 <my.heap::instance_class>
 105dd6e:	48 8d 9c 24 88 00 00 	lea    0x88(%rsp),%rbx
 105dd75:	00 
 105dd76:	48 89 df             	mov    %rbx,%rdi
 105dd79:	4c 89 f6             	mov    %r14,%rsi
 105dd7c:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105dd81:	48 89 c1             	mov    %rax,%rcx
 105dd84:	4c 8b 44 24 40       	mov    0x40(%rsp),%r8
 105dd89:	e8 d2 5f 00 00       	call   1063d60 <my.vm::bind_method>
 105dd8e:	e9 d7 f8 ff ff       	jmp    105d66a <my.vm::run+0x213a>
 105dd93:	4c 89 f7             	mov    %r14,%rdi
 105dd96:	48 89 ee             	mov    %rbp,%rsi
 105dd99:	e8 52 d0 00 00       	call   106adf0 <my.heap::instance_class>
 105dd9e:	4d 89 e0             	mov    %r12,%r8
 105dda1:	4c 8d a4 24 88 00 00 	lea    0x88(%rsp),%r12
 105dda8:	00 
 105dda9:	4c 89 e7             	mov    %r12,%rdi
 105ddac:	4c 89 f6             	mov    %r14,%rsi
 105ddaf:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 105ddb4:	48 89 c1             	mov    %rax,%rcx
 105ddb7:	49 89 d9             	mov    %rbx,%r9
 105ddba:	e8 11 6d 00 00       	call   1064ad0 <my.vm::invoke_from_class>
 105ddbf:	41 f6 04 24 01       	testb  $0x1,(%r12)
 105ddc4:	0f 85 02 f9 ff ff    	jne    105d6cc <my.vm::run+0x219c>
 105ddca:	e9 32 08 00 00       	jmp    105e601 <my.vm::run+0x30d1>
 105ddcf:	83 f9 01             	cmp    $0x1,%ecx
 105ddd2:	0f 84 92 fe ff ff    	je     105dc6a <my.vm::run+0x273a>
 105ddd8:	83 f9 02             	cmp    $0x2,%ecx
 105dddb:	0f 85 98 fe ff ff    	jne    105dc79 <my.vm::run+0x2749>
 105dde1:	48 89 c7             	mov    %rax,%rdi
 105dde4:	e8 17 65 fc ff       	call   1024300 <myl_core_drop_owned>
 105dde9:	48 89 ef             	mov    %rbp,%rdi
 105ddec:	e8 0f 65 fc ff       	call   1024300 <myl_core_drop_owned>
 105ddf1:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 105ddf6:	e9 6f fe ff ff       	jmp    105dc6a <my.vm::run+0x273a>
 105ddfb:	48 89 cf             	mov    %rcx,%rdi
 105ddfe:	e8 fd 64 fc ff       	call   1024300 <myl_core_drop_owned>
 105de03:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 105de08:	e8 f3 64 fc ff       	call   1024300 <myl_core_drop_owned>
 105de0d:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 105de12:	e9 6d fa ff ff       	jmp    105d884 <my.vm::run+0x2354>
 105de17:	48 89 c7             	mov    %rax,%rdi
 105de1a:	e9 65 fa ff ff       	jmp    105d884 <my.vm::run+0x2354>
 105de1f:	83 fe 01             	cmp    $0x1,%esi
 105de22:	0f 84 26 ea ff ff    	je     105c84e <my.vm::run+0x131e>
 105de28:	83 fe 02             	cmp    $0x2,%esi
 105de2b:	0f 85 2c ea ff ff    	jne    105c85d <my.vm::run+0x132d>
 105de31:	48 89 c7             	mov    %rax,%rdi
 105de34:	e8 c7 64 fc ff       	call   1024300 <myl_core_drop_owned>
 105de39:	48 8b 7c 24 60       	mov    0x60(%rsp),%rdi
 105de3e:	e8 bd 64 fc ff       	call   1024300 <myl_core_drop_owned>
 105de43:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 105de48:	e9 01 ea ff ff       	jmp    105c84e <my.vm::run+0x131e>
 105de4d:	4c 89 d9             	mov    %r11,%rcx
 105de50:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105de54:	48 21 d1             	and    %rdx,%rcx
 105de57:	4c 01 d9             	add    %r11,%rcx
 105de5a:	48 39 d1             	cmp    %rdx,%rcx
 105de5d:	0f 82 60 d7 ff ff    	jb     105b5c3 <my.vm::run+0x93>
 105de63:	e9 71 11 00 00       	jmp    105efd9 <my.vm::run+0x3aa9>
 105de68:	48 89 f1             	mov    %rsi,%rcx
 105de6b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105de6f:	48 21 d1             	and    %rdx,%rcx
 105de72:	48 01 f1             	add    %rsi,%rcx
 105de75:	48 39 d1             	cmp    %rdx,%rcx
 105de78:	0f 82 6f d7 ff ff    	jb     105b5ed <my.vm::run+0xbd>
 105de7e:	e9 65 11 00 00       	jmp    105efe8 <my.vm::run+0x3ab8>
 105de83:	48 89 f7             	mov    %rsi,%rdi
 105de86:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105de8a:	48 21 d7             	and    %rdx,%rdi
 105de8d:	48 01 f7             	add    %rsi,%rdi
 105de90:	48 39 d7             	cmp    %rdx,%rdi
 105de93:	0f 82 d8 d7 ff ff    	jb     105b671 <my.vm::run+0x141>
 105de99:	e9 65 11 00 00       	jmp    105f003 <my.vm::run+0x3ad3>
 105de9e:	4c 89 ee             	mov    %r13,%rsi
 105dea1:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105dea5:	48 21 d6             	and    %rdx,%rsi
 105dea8:	4c 01 ee             	add    %r13,%rsi
 105deab:	48 39 d6             	cmp    %rdx,%rsi
 105deae:	0f 82 e6 d7 ff ff    	jb     105b69a <my.vm::run+0x16a>
 105deb4:	e9 65 11 00 00       	jmp    105f01e <my.vm::run+0x3aee>
 105deb9:	4c 89 e9             	mov    %r13,%rcx
 105debc:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105dec0:	48 21 d1             	and    %rdx,%rcx
 105dec3:	4c 01 e9             	add    %r13,%rcx
 105dec6:	48 39 d1             	cmp    %rdx,%rcx
 105dec9:	0f 82 49 e3 ff ff    	jb     105c218 <my.vm::run+0xce8>
 105decf:	e9 c1 12 00 00       	jmp    105f195 <my.vm::run+0x3c65>
 105ded4:	4c 89 e9             	mov    %r13,%rcx
 105ded7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105dedb:	48 21 d1             	and    %rdx,%rcx
 105dede:	4c 01 e9             	add    %r13,%rcx
 105dee1:	48 39 d1             	cmp    %rdx,%rcx
 105dee4:	0f 82 02 e4 ff ff    	jb     105c2ec <my.vm::run+0xdbc>
 105deea:	e9 73 12 00 00       	jmp    105f162 <my.vm::run+0x3c32>
 105deef:	4c 89 e9             	mov    %r13,%rcx
 105def2:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105def6:	48 21 d1             	and    %rdx,%rcx
 105def9:	4c 01 e9             	add    %r13,%rcx
 105defc:	48 39 d1             	cmp    %rdx,%rcx
 105deff:	0f 82 3c e5 ff ff    	jb     105c441 <my.vm::run+0xf11>
 105df05:	e9 10 12 00 00       	jmp    105f11a <my.vm::run+0x3bea>
 105df0a:	4c 89 e9             	mov    %r13,%rcx
 105df0d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105df11:	48 21 d1             	and    %rdx,%rcx
 105df14:	4c 01 e9             	add    %r13,%rcx
 105df17:	48 39 d1             	cmp    %rdx,%rcx
 105df1a:	0f 82 5c e5 ff ff    	jb     105c47c <my.vm::run+0xf4c>
 105df20:	e9 06 13 00 00       	jmp    105f22b <my.vm::run+0x3cfb>
 105df25:	49 89 f0             	mov    %rsi,%r8
 105df28:	49 c1 f8 3f          	sar    $0x3f,%r8
 105df2c:	49 21 c0             	and    %rax,%r8
 105df2f:	49 01 f0             	add    %rsi,%r8
 105df32:	49 39 c0             	cmp    %rax,%r8
 105df35:	0f 82 58 db ff ff    	jb     105ba93 <my.vm::run+0x563>
 105df3b:	e9 7f 12 00 00       	jmp    105f1bf <my.vm::run+0x3c8f>
 105df40:	48 89 f1             	mov    %rsi,%rcx
 105df43:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105df47:	48 21 d1             	and    %rdx,%rcx
 105df4a:	48 01 f1             	add    %rsi,%rcx
 105df4d:	48 39 d1             	cmp    %rdx,%rcx
 105df50:	0f 82 65 de ff ff    	jb     105bdbb <my.vm::run+0x88b>
 105df56:	e9 ee 12 00 00       	jmp    105f249 <my.vm::run+0x3d19>
 105df5b:	48 89 f0             	mov    %rsi,%rax
 105df5e:	48 c1 f8 3f          	sar    $0x3f,%rax
 105df62:	48 21 d0             	and    %rdx,%rax
 105df65:	48 01 f0             	add    %rsi,%rax
 105df68:	48 39 d0             	cmp    %rdx,%rax
 105df6b:	0f 82 01 e0 ff ff    	jb     105bf72 <my.vm::run+0xa42>
 105df71:	e9 b7 10 00 00       	jmp    105f02d <my.vm::run+0x3afd>
 105df76:	4d 89 ec             	mov    %r13,%r12
 105df79:	49 c1 fc 3f          	sar    $0x3f,%r12
 105df7d:	49 21 d4             	and    %rdx,%r12
 105df80:	4d 01 ec             	add    %r13,%r12
 105df83:	49 39 d4             	cmp    %rdx,%r12
 105df86:	0f 82 15 e0 ff ff    	jb     105bfa1 <my.vm::run+0xa71>
 105df8c:	e9 f6 10 00 00       	jmp    105f087 <my.vm::run+0x3b57>
 105df91:	48 89 f1             	mov    %rsi,%rcx
 105df94:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105df98:	48 21 d1             	and    %rdx,%rcx
 105df9b:	48 01 f1             	add    %rsi,%rcx
 105df9e:	48 39 d1             	cmp    %rdx,%rcx
 105dfa1:	0f 82 c2 e2 ff ff    	jb     105c269 <my.vm::run+0xd39>
 105dfa7:	e9 8d 10 00 00       	jmp    105f039 <my.vm::run+0x3b09>
 105dfac:	4c 89 e6             	mov    %r12,%rsi
 105dfaf:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105dfb3:	48 21 d6             	and    %rdx,%rsi
 105dfb6:	4c 01 e6             	add    %r12,%rsi
 105dfb9:	48 39 d6             	cmp    %rdx,%rsi
 105dfbc:	0f 82 62 e5 ff ff    	jb     105c524 <my.vm::run+0xff4>
 105dfc2:	e9 0e 11 00 00       	jmp    105f0d5 <my.vm::run+0x3ba5>
 105dfc7:	48 89 f1             	mov    %rsi,%rcx
 105dfca:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105dfce:	48 21 d1             	and    %rdx,%rcx
 105dfd1:	48 01 f1             	add    %rsi,%rcx
 105dfd4:	48 39 d1             	cmp    %rdx,%rcx
 105dfd7:	0f 82 d1 e5 ff ff    	jb     105c5ae <my.vm::run+0x107e>
 105dfdd:	e9 73 12 00 00       	jmp    105f255 <my.vm::run+0x3d25>
 105dfe2:	48 89 f7             	mov    %rsi,%rdi
 105dfe5:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105dfe9:	48 21 d7             	and    %rdx,%rdi
 105dfec:	48 01 f7             	add    %rsi,%rdi
 105dfef:	48 39 d7             	cmp    %rdx,%rdi
 105dff2:	0f 82 12 e9 ff ff    	jb     105c90a <my.vm::run+0x13da>
 105dff8:	e9 2c 11 00 00       	jmp    105f129 <my.vm::run+0x3bf9>
 105dffd:	48 89 f1             	mov    %rsi,%rcx
 105e000:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e004:	48 21 d1             	and    %rdx,%rcx
 105e007:	48 01 f1             	add    %rsi,%rcx
 105e00a:	48 39 d1             	cmp    %rdx,%rcx
 105e00d:	0f 82 2f ea ff ff    	jb     105ca42 <my.vm::run+0x1512>
 105e013:	e9 cc 10 00 00       	jmp    105f0e4 <my.vm::run+0x3bb4>
 105e018:	4c 89 e9             	mov    %r13,%rcx
 105e01b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e01f:	48 21 d1             	and    %rdx,%rcx
 105e022:	4c 01 e9             	add    %r13,%rcx
 105e025:	48 39 d1             	cmp    %rdx,%rcx
 105e028:	0f 82 96 e5 ff ff    	jb     105c5c4 <my.vm::run+0x1094>
 105e02e:	e9 39 10 00 00       	jmp    105f06c <my.vm::run+0x3b3c>
 105e033:	49 8d 0c 31          	lea    (%r9,%rsi,1),%rcx
 105e037:	48 39 d1             	cmp    %rdx,%rcx
 105e03a:	0f 82 a6 ef ff ff    	jb     105cfe6 <my.vm::run+0x1ab6>
 105e040:	e9 ab 10 00 00       	jmp    105f0f0 <my.vm::run+0x3bc0>
 105e045:	48 8d 3c 0e          	lea    (%rsi,%rcx,1),%rdi
 105e049:	48 39 d7             	cmp    %rdx,%rdi
 105e04c:	0f 82 d4 f2 ff ff    	jb     105d326 <my.vm::run+0x1df6>
 105e052:	e9 77 11 00 00       	jmp    105f1ce <my.vm::run+0x3c9e>
 105e057:	4c 89 e9             	mov    %r13,%rcx
 105e05a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e05e:	48 21 d1             	and    %rdx,%rcx
 105e061:	4c 01 e9             	add    %r13,%rcx
 105e064:	48 39 d1             	cmp    %rdx,%rcx
 105e067:	0f 82 a9 f5 ff ff    	jb     105d616 <my.vm::run+0x20e6>
 105e06d:	e9 d2 10 00 00       	jmp    105f144 <my.vm::run+0x3c14>
 105e072:	48 89 f0             	mov    %rsi,%rax
 105e075:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e079:	48 21 d0             	and    %rdx,%rax
 105e07c:	48 01 f0             	add    %rsi,%rax
 105e07f:	48 39 d0             	cmp    %rdx,%rax
 105e082:	0f 82 dd d6 ff ff    	jb     105b765 <my.vm::run+0x235>
 105e088:	e9 e4 10 00 00       	jmp    105f171 <my.vm::run+0x3c41>
 105e08d:	4c 89 e9             	mov    %r13,%rcx
 105e090:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e094:	48 21 d1             	and    %rdx,%rcx
 105e097:	4c 01 e9             	add    %r13,%rcx
 105e09a:	48 39 d1             	cmp    %rdx,%rcx
 105e09d:	0f 82 fa e1 ff ff    	jb     105c29d <my.vm::run+0xd6d>
 105e0a3:	e9 8d 10 00 00       	jmp    105f135 <my.vm::run+0x3c05>
 105e0a8:	4c 89 e8             	mov    %r13,%rax
 105e0ab:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e0af:	48 21 d0             	and    %rdx,%rax
 105e0b2:	4c 01 e8             	add    %r13,%rax
 105e0b5:	48 39 d0             	cmp    %rdx,%rax
 105e0b8:	0f 82 7a e5 ff ff    	jb     105c638 <my.vm::run+0x1108>
 105e0be:	e9 77 11 00 00       	jmp    105f23a <my.vm::run+0x3d0a>
 105e0c3:	48 89 f0             	mov    %rsi,%rax
 105e0c6:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e0ca:	48 21 d0             	and    %rdx,%rax
 105e0cd:	48 01 f0             	add    %rsi,%rax
 105e0d0:	48 39 d0             	cmp    %rdx,%rax
 105e0d3:	0f 82 53 e8 ff ff    	jb     105c92c <my.vm::run+0x13fc>
 105e0d9:	e9 ab 10 00 00       	jmp    105f189 <my.vm::run+0x3c59>
 105e0de:	49 89 c5             	mov    %rax,%r13
 105e0e1:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e0e5:	48 21 d0             	and    %rdx,%rax
 105e0e8:	4c 01 e8             	add    %r13,%rax
 105e0eb:	48 39 d0             	cmp    %rdx,%rax
 105e0ee:	4c 8d 25 b7 92 fa ff 	lea    -0x56d49(%rip),%r12        # 10073ac <core_number_pairs+0x14c>
 105e0f5:	0f 82 25 fc ff ff    	jb     105dd20 <my.vm::run+0x27f0>
 105e0fb:	e9 e6 10 00 00       	jmp    105f1e6 <my.vm::run+0x3cb6>
 105e100:	48 89 f1             	mov    %rsi,%rcx
 105e103:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e107:	48 21 d1             	and    %rdx,%rcx
 105e10a:	48 01 f1             	add    %rsi,%rcx
 105e10d:	48 39 d1             	cmp    %rdx,%rcx
 105e110:	0f 82 b5 f2 ff ff    	jb     105d3cb <my.vm::run+0x1e9b>
 105e116:	e9 7b 0f 00 00       	jmp    105f096 <my.vm::run+0x3b66>
 105e11b:	be 20 00 00 00       	mov    $0x20,%esi
 105e120:	31 ff                	xor    %edi,%edi
 105e122:	e8 19 54 fc ff       	call   1023540 <myl_core_list_new_slow>
 105e127:	e9 a9 da ff ff       	jmp    105bbd5 <my.vm::run+0x6a5>
 105e12c:	48 89 d9             	mov    %rbx,%rcx
 105e12f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e133:	48 21 d1             	and    %rdx,%rcx
 105e136:	48 01 d9             	add    %rbx,%rcx
 105e139:	48 39 d1             	cmp    %rdx,%rcx
 105e13c:	0f 82 ae da ff ff    	jb     105bbf0 <my.vm::run+0x6c0>
 105e142:	e9 fe 0e 00 00       	jmp    105f045 <my.vm::run+0x3b15>
 105e147:	48 89 f1             	mov    %rsi,%rcx
 105e14a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e14e:	48 21 d1             	and    %rdx,%rcx
 105e151:	48 01 f1             	add    %rsi,%rcx
 105e154:	48 39 d1             	cmp    %rdx,%rcx
 105e157:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105e15c:	0f 82 21 db ff ff    	jb     105bc83 <my.vm::run+0x753>
 105e162:	e9 3d 10 00 00       	jmp    105f1a4 <my.vm::run+0x3c74>
 105e167:	4c 89 c1             	mov    %r8,%rcx
 105e16a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e16e:	48 21 d1             	and    %rdx,%rcx
 105e171:	4c 01 c1             	add    %r8,%rcx
 105e174:	48 39 d1             	cmp    %rdx,%rcx
 105e177:	0f 82 20 ea ff ff    	jb     105cb9d <my.vm::run+0x166d>
 105e17d:	e9 7a 0f 00 00       	jmp    105f0fc <my.vm::run+0x3bcc>
 105e182:	48 89 f1             	mov    %rsi,%rcx
 105e185:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e189:	48 21 d1             	and    %rdx,%rcx
 105e18c:	48 01 f1             	add    %rsi,%rcx
 105e18f:	48 39 d1             	cmp    %rdx,%rcx
 105e192:	0f 82 92 db ff ff    	jb     105bd2a <my.vm::run+0x7fa>
 105e198:	e9 c3 0e 00 00       	jmp    105f060 <my.vm::run+0x3b30>
 105e19d:	48 89 f1             	mov    %rsi,%rcx
 105e1a0:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e1a4:	48 21 d1             	and    %rdx,%rcx
 105e1a7:	48 01 f1             	add    %rsi,%rcx
 105e1aa:	48 39 d1             	cmp    %rdx,%rcx
 105e1ad:	0f 82 5e df ff ff    	jb     105c111 <my.vm::run+0xbe1>
 105e1b3:	e9 22 10 00 00       	jmp    105f1da <my.vm::run+0x3caa>
 105e1b8:	48 89 f1             	mov    %rsi,%rcx
 105e1bb:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e1bf:	48 21 d1             	and    %rdx,%rcx
 105e1c2:	48 01 f1             	add    %rsi,%rcx
 105e1c5:	48 39 d1             	cmp    %rdx,%rcx
 105e1c8:	0f 82 2e f0 ff ff    	jb     105d1fc <my.vm::run+0x1ccc>
 105e1ce:	e9 22 10 00 00       	jmp    105f1f5 <my.vm::run+0x3cc5>
 105e1d3:	48 89 f0             	mov    %rsi,%rax
 105e1d6:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e1da:	48 21 d0             	and    %rdx,%rax
 105e1dd:	48 01 f0             	add    %rsi,%rax
 105e1e0:	48 39 d0             	cmp    %rdx,%rax
 105e1e3:	0f 82 15 d7 ff ff    	jb     105b8fe <my.vm::run+0x3ce>
 105e1e9:	e9 66 0e 00 00       	jmp    105f054 <my.vm::run+0x3b24>
 105e1ee:	48 89 f0             	mov    %rsi,%rax
 105e1f1:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e1f5:	48 21 d0             	and    %rdx,%rax
 105e1f8:	48 01 f0             	add    %rsi,%rax
 105e1fb:	48 39 d0             	cmp    %rdx,%rax
 105e1fe:	0f 82 16 f3 ff ff    	jb     105d51a <my.vm::run+0x1fea>
 105e204:	e9 f8 0f 00 00       	jmp    105f201 <my.vm::run+0x3cd1>
 105e209:	4c 89 e8             	mov    %r13,%rax
 105e20c:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e210:	48 21 d0             	and    %rdx,%rax
 105e213:	4c 01 e8             	add    %r13,%rax
 105e216:	48 39 d0             	cmp    %rdx,%rax
 105e219:	0f 82 29 d7 ff ff    	jb     105b948 <my.vm::run+0x418>
 105e21f:	e9 8c 0f 00 00       	jmp    105f1b0 <my.vm::run+0x3c80>
 105e224:	4c 89 e7             	mov    %r12,%rdi
 105e227:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e22b:	48 21 c7             	and    %rax,%rdi
 105e22e:	4c 01 e7             	add    %r12,%rdi
 105e231:	48 39 c7             	cmp    %rax,%rdi
 105e234:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105e239:	0f 82 60 d7 ff ff    	jb     105b99f <my.vm::run+0x46f>
 105e23f:	e9 c9 0f 00 00       	jmp    105f20d <my.vm::run+0x3cdd>
 105e244:	4c 89 e8             	mov    %r13,%rax
 105e247:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e24b:	48 21 d0             	and    %rdx,%rax
 105e24e:	4c 01 e8             	add    %r13,%rax
 105e251:	48 39 d0             	cmp    %rdx,%rax
 105e254:	0f 82 c0 d7 ff ff    	jb     105ba1a <my.vm::run+0x4ea>
 105e25a:	e9 43 0e 00 00       	jmp    105f0a2 <my.vm::run+0x3b72>
 105e25f:	48 89 f1             	mov    %rsi,%rcx
 105e262:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e266:	48 21 d1             	and    %rdx,%rcx
 105e269:	48 01 f1             	add    %rsi,%rcx
 105e26c:	48 39 d1             	cmp    %rdx,%rcx
 105e26f:	0f 82 d5 e9 ff ff    	jb     105cc4a <my.vm::run+0x171a>
 105e275:	e9 a5 0f 00 00       	jmp    105f21f <my.vm::run+0x3cef>
 105e27a:	48 89 f0             	mov    %rsi,%rax
 105e27d:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e281:	48 21 d0             	and    %rdx,%rax
 105e284:	48 01 f0             	add    %rsi,%rax
 105e287:	48 39 d0             	cmp    %rdx,%rax
 105e28a:	0f 82 8a f6 ff ff    	jb     105d91a <my.vm::run+0x23ea>
 105e290:	e9 e6 0d 00 00       	jmp    105f07b <my.vm::run+0x3b4b>
 105e295:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e299:	48 21 d1             	and    %rdx,%rcx
 105e29c:	4c 01 e9             	add    %r13,%rcx
 105e29f:	48 39 d1             	cmp    %rdx,%rcx
 105e2a2:	0f 82 6c db ff ff    	jb     105be14 <my.vm::run+0x8e4>
 105e2a8:	e9 5e 0e 00 00       	jmp    105f10b <my.vm::run+0x3bdb>
 105e2ad:	48 89 f1             	mov    %rsi,%rcx
 105e2b0:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e2b4:	48 21 d1             	and    %rdx,%rcx
 105e2b7:	48 01 f1             	add    %rsi,%rcx
 105e2ba:	48 39 d1             	cmp    %rdx,%rcx
 105e2bd:	0f 82 41 f4 ff ff    	jb     105d704 <my.vm::run+0x21d4>
 105e2c3:	e9 b5 0e 00 00       	jmp    105f17d <my.vm::run+0x3c4d>
 105e2c8:	48 89 f1             	mov    %rsi,%rcx
 105e2cb:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e2cf:	48 21 d1             	and    %rdx,%rcx
 105e2d2:	48 01 f1             	add    %rsi,%rcx
 105e2d5:	48 39 d1             	cmp    %rdx,%rcx
 105e2d8:	49 89 d9             	mov    %rbx,%r9
 105e2db:	49 89 eb             	mov    %rbp,%r11
 105e2de:	4d 89 e2             	mov    %r12,%r10
 105e2e1:	0f 82 f1 e6 ff ff    	jb     105c9d8 <my.vm::run+0x14a8>
 105e2e7:	e9 41 10 00 00       	jmp    105f32d <my.vm::run+0x3dfd>
 105e2ec:	48 89 f1             	mov    %rsi,%rcx
 105e2ef:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e2f3:	48 21 d1             	and    %rdx,%rcx
 105e2f6:	48 01 f1             	add    %rsi,%rcx
 105e2f9:	48 39 d1             	cmp    %rdx,%rcx
 105e2fc:	0f 82 fa e6 ff ff    	jb     105c9fc <my.vm::run+0x14cc>
 105e302:	e9 62 10 00 00       	jmp    105f369 <my.vm::run+0x3e39>
 105e307:	48 89 f1             	mov    %rsi,%rcx
 105e30a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e30e:	48 21 d1             	and    %rdx,%rcx
 105e311:	48 01 f1             	add    %rsi,%rcx
 105e314:	48 39 d1             	cmp    %rdx,%rcx
 105e317:	0f 82 01 dc ff ff    	jb     105bf1e <my.vm::run+0x9ee>
 105e31d:	e9 53 10 00 00       	jmp    105f375 <my.vm::run+0x3e45>
 105e322:	48 89 c1             	mov    %rax,%rcx
 105e325:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e329:	48 21 d1             	and    %rdx,%rcx
 105e32c:	48 01 c1             	add    %rax,%rcx
 105e32f:	48 39 d1             	cmp    %rdx,%rcx
 105e332:	0f 82 fc db ff ff    	jb     105bf34 <my.vm::run+0xa04>
 105e338:	e9 44 10 00 00       	jmp    105f381 <my.vm::run+0x3e51>
 105e33d:	48 89 f1             	mov    %rsi,%rcx
 105e340:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e344:	48 21 d1             	and    %rdx,%rcx
 105e347:	48 01 f1             	add    %rsi,%rcx
 105e34a:	48 39 d1             	cmp    %rdx,%rcx
 105e34d:	0f 82 76 dc ff ff    	jb     105bfc9 <my.vm::run+0xa99>
 105e353:	e9 83 10 00 00       	jmp    105f3db <my.vm::run+0x3eab>
 105e358:	48 89 f1             	mov    %rsi,%rcx
 105e35b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e35f:	48 21 c1             	and    %rax,%rcx
 105e362:	48 01 f1             	add    %rsi,%rcx
 105e365:	48 39 c1             	cmp    %rax,%rcx
 105e368:	0f 82 1e d4 ff ff    	jb     105b78c <my.vm::run+0x25c>
 105e36e:	e9 51 0f 00 00       	jmp    105f2c4 <my.vm::run+0x3d94>
 105e373:	49 89 f0             	mov    %rsi,%r8
 105e376:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e37a:	49 21 c0             	and    %rax,%r8
 105e37d:	49 01 f0             	add    %rsi,%r8
 105e380:	49 39 c0             	cmp    %rax,%r8
 105e383:	0f 82 2c e0 ff ff    	jb     105c3b5 <my.vm::run+0xe85>
 105e389:	e9 ab 0f 00 00       	jmp    105f339 <my.vm::run+0x3e09>
 105e38e:	48 89 e9             	mov    %rbp,%rcx
 105e391:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e395:	48 21 d1             	and    %rdx,%rcx
 105e398:	48 01 e9             	add    %rbp,%rcx
 105e39b:	48 39 d1             	cmp    %rdx,%rcx
 105e39e:	0f 82 9e f1 ff ff    	jb     105d542 <my.vm::run+0x2012>
 105e3a4:	e9 75 0f 00 00       	jmp    105f31e <my.vm::run+0x3dee>
 105e3a9:	49 89 f0             	mov    %rsi,%r8
 105e3ac:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e3b0:	49 21 d0             	and    %rdx,%r8
 105e3b3:	49 01 f0             	add    %rsi,%r8
 105e3b6:	49 39 d0             	cmp    %rdx,%r8
 105e3b9:	0f 82 03 f5 ff ff    	jb     105d8c2 <my.vm::run+0x2392>
 105e3bf:	e9 ea 0f 00 00       	jmp    105f3ae <my.vm::run+0x3e7e>
 105e3c4:	48 89 f0             	mov    %rsi,%rax
 105e3c7:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e3cb:	48 21 d0             	and    %rdx,%rax
 105e3ce:	48 01 f0             	add    %rsi,%rax
 105e3d1:	48 39 d0             	cmp    %rdx,%rax
 105e3d4:	0f 82 1c f4 ff ff    	jb     105d7f6 <my.vm::run+0x22c6>
 105e3da:	e9 82 0e 00 00       	jmp    105f261 <my.vm::run+0x3d31>
 105e3df:	48 89 d8             	mov    %rbx,%rax
 105e3e2:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e3e6:	48 21 d0             	and    %rdx,%rax
 105e3e9:	48 01 d8             	add    %rbx,%rax
 105e3ec:	48 39 d0             	cmp    %rdx,%rax
 105e3ef:	0f 82 1e f4 ff ff    	jb     105d813 <my.vm::run+0x22e3>
 105e3f5:	e9 91 0e 00 00       	jmp    105f28b <my.vm::run+0x3d5b>
 105e3fa:	49 89 c0             	mov    %rax,%r8
 105e3fd:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e401:	49 21 c8             	and    %rcx,%r8
 105e404:	49 01 c0             	add    %rax,%r8
 105e407:	49 39 c8             	cmp    %rcx,%r8
 105e40a:	0f 82 15 ec ff ff    	jb     105d025 <my.vm::run+0x1af5>
 105e410:	e9 a5 0f 00 00       	jmp    105f3ba <my.vm::run+0x3e8a>
 105e415:	4c 89 e9             	mov    %r13,%rcx
 105e418:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e41c:	48 21 d1             	and    %rdx,%rcx
 105e41f:	4c 01 e9             	add    %r13,%rcx
 105e422:	48 39 d1             	cmp    %rdx,%rcx
 105e425:	0f 82 26 f6 ff ff    	jb     105da51 <my.vm::run+0x2521>
 105e42b:	e9 6f 0f 00 00       	jmp    105f39f <my.vm::run+0x3e6f>
 105e430:	4c 89 e8             	mov    %r13,%rax
 105e433:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e437:	48 21 d0             	and    %rdx,%rax
 105e43a:	4c 01 e8             	add    %r13,%rax
 105e43d:	48 39 d0             	cmp    %rdx,%rax
 105e440:	0f 82 61 d3 ff ff    	jb     105b7a7 <my.vm::run+0x277>
 105e446:	e9 b8 0e 00 00       	jmp    105f303 <my.vm::run+0x3dd3>
 105e44b:	48 89 f8             	mov    %rdi,%rax
 105e44e:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e452:	48 21 d0             	and    %rdx,%rax
 105e455:	48 01 f8             	add    %rdi,%rax
 105e458:	48 39 d0             	cmp    %rdx,%rax
 105e45b:	0f 82 1f e2 ff ff    	jb     105c680 <my.vm::run+0x1150>
 105e461:	e9 e2 0e 00 00       	jmp    105f348 <my.vm::run+0x3e18>
 105e466:	48 89 f0             	mov    %rsi,%rax
 105e469:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e46d:	48 21 d0             	and    %rdx,%rax
 105e470:	48 01 f0             	add    %rsi,%rax
 105e473:	48 39 d0             	cmp    %rdx,%rax
 105e476:	49 89 e8             	mov    %rbp,%r8
 105e479:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105e47e:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105e483:	0f 82 84 f7 ff ff    	jb     105dc0d <my.vm::run+0x26dd>
 105e489:	e9 59 0f 00 00       	jmp    105f3e7 <my.vm::run+0x3eb7>
 105e48e:	4c 89 e8             	mov    %r13,%rax
 105e491:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e495:	48 21 d0             	and    %rdx,%rax
 105e498:	4c 01 e8             	add    %r13,%rax
 105e49b:	48 39 d0             	cmp    %rdx,%rax
 105e49e:	0f 82 ee f7 ff ff    	jb     105dc92 <my.vm::run+0x2762>
 105e4a4:	e9 3c 0e 00 00       	jmp    105f2e5 <my.vm::run+0x3db5>
 105e4a9:	49 89 c0             	mov    %rax,%r8
 105e4ac:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e4b0:	49 21 d0             	and    %rdx,%r8
 105e4b3:	49 01 c0             	add    %rax,%r8
 105e4b6:	49 39 d0             	cmp    %rdx,%r8
 105e4b9:	0f 82 8e eb ff ff    	jb     105d04d <my.vm::run+0x1b1d>
 105e4bf:	e9 a9 0d 00 00       	jmp    105f26d <my.vm::run+0x3d3d>
 105e4c4:	48 89 de             	mov    %rbx,%rsi
 105e4c7:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e4cb:	48 21 d6             	and    %rdx,%rsi
 105e4ce:	48 01 de             	add    %rbx,%rsi
 105e4d1:	48 39 d6             	cmp    %rdx,%rsi
 105e4d4:	0f 82 43 e2 ff ff    	jb     105c71d <my.vm::run+0x11ed>
 105e4da:	e9 9d 0d 00 00       	jmp    105f27c <my.vm::run+0x3d4c>
 105e4df:	48 89 cf             	mov    %rcx,%rdi
 105e4e2:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e4e6:	48 21 d7             	and    %rdx,%rdi
 105e4e9:	48 01 cf             	add    %rcx,%rdi
 105e4ec:	48 39 d7             	cmp    %rdx,%rdi
 105e4ef:	0f 82 54 e2 ff ff    	jb     105c749 <my.vm::run+0x1219>
 105e4f5:	e9 bb 0d 00 00       	jmp    105f2b5 <my.vm::run+0x3d85>
 105e4fa:	48 89 f1             	mov    %rsi,%rcx
 105e4fd:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e501:	48 21 c1             	and    %rax,%rcx
 105e504:	48 01 f1             	add    %rsi,%rcx
 105e507:	48 39 c1             	cmp    %rax,%rcx
 105e50a:	0f 82 94 f0 ff ff    	jb     105d5a4 <my.vm::run+0x2074>
 105e510:	e9 b7 0e 00 00       	jmp    105f3cc <my.vm::run+0x3e9c>
 105e515:	48 89 fe             	mov    %rdi,%rsi
 105e518:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e51c:	48 21 c6             	and    %rax,%rsi
 105e51f:	48 01 fe             	add    %rdi,%rsi
 105e522:	48 39 c6             	cmp    %rax,%rsi
 105e525:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 105e52a:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 105e52f:	0f 82 b1 e2 ff ff    	jb     105c7e6 <my.vm::run+0x12b6>
 105e535:	e9 1d 0e 00 00       	jmp    105f357 <my.vm::run+0x3e27>
 105e53a:	48 89 d8             	mov    %rbx,%rax
 105e53d:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e541:	48 21 d0             	and    %rdx,%rax
 105e544:	48 01 d8             	add    %rbx,%rax
 105e547:	48 39 d0             	cmp    %rdx,%rax
 105e54a:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105e54f:	48 8b 6c 24 70       	mov    0x70(%rsp),%rbp
 105e554:	0f 82 22 e3 ff ff    	jb     105c87c <my.vm::run+0x134c>
 105e55a:	e9 3b 0d 00 00       	jmp    105f29a <my.vm::run+0x3d6a>
 105e55f:	4c 89 e8             	mov    %r13,%rax
 105e562:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e566:	48 21 d0             	and    %rdx,%rax
 105e569:	4c 01 e8             	add    %r13,%rax
 105e56c:	48 39 d0             	cmp    %rdx,%rax
 105e56f:	0f 82 1d e3 ff ff    	jb     105c892 <my.vm::run+0x1362>
 105e575:	e9 7a 0d 00 00       	jmp    105f2f4 <my.vm::run+0x3dc4>
 105e57a:	4d 89 c3             	mov    %r8,%r11
 105e57d:	49 c1 fb 3f          	sar    $0x3f,%r11
 105e581:	49 21 cb             	and    %rcx,%r11
 105e584:	4d 01 c3             	add    %r8,%r11
 105e587:	49 39 cb             	cmp    %rcx,%r11
 105e58a:	0f 82 e0 ea ff ff    	jb     105d070 <my.vm::run+0x1b40>
 105e590:	e9 3e 0d 00 00       	jmp    105f2d3 <my.vm::run+0x3da3>
 105e595:	49 01 f1             	add    %rsi,%r9
 105e598:	49 39 d1             	cmp    %rdx,%r9
 105e59b:	0f 82 f1 ea ff ff    	jb     105d092 <my.vm::run+0x1b62>
 105e5a1:	e9 6c 0d 00 00       	jmp    105f312 <my.vm::run+0x3de2>
 105e5a6:	48 89 c6             	mov    %rax,%rsi
 105e5a9:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e5ad:	48 21 d6             	and    %rdx,%rsi
 105e5b0:	48 01 c6             	add    %rax,%rsi
 105e5b3:	48 39 d6             	cmp    %rdx,%rsi
 105e5b6:	0f 82 f9 ea ff ff    	jb     105d0b5 <my.vm::run+0x1b85>
 105e5bc:	e9 cf 0d 00 00       	jmp    105f390 <my.vm::run+0x3e60>
 105e5c1:	48 89 f7             	mov    %rsi,%rdi
 105e5c4:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e5c8:	48 21 d7             	and    %rdx,%rdi
 105e5cb:	48 01 f7             	add    %rsi,%rdi
 105e5ce:	48 39 d7             	cmp    %rdx,%rdi
 105e5d1:	0f 82 3d eb ff ff    	jb     105d114 <my.vm::run+0x1be4>
 105e5d7:	e9 cd 0c 00 00       	jmp    105f2a9 <my.vm::run+0x3d79>
 105e5dc:	4c 89 ee             	mov    %r13,%rsi
 105e5df:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e5e3:	48 21 d6             	and    %rdx,%rsi
 105e5e6:	4c 01 ee             	add    %r13,%rsi
 105e5e9:	48 39 d6             	cmp    %rdx,%rsi
 105e5ec:	0f 82 3a eb ff ff    	jb     105d12c <my.vm::run+0x1bfc>
 105e5f2:	48 8d 3d 77 6e 02 00 	lea    0x26e77(%rip),%rdi        # 1085470 <core_durable_error.verbs+0x4aa0>
 105e5f9:	4c 89 ee             	mov    %r13,%rsi
 105e5fc:	e8 7f 6a fc ff       	call   1025080 <myl_core_trap>
 105e601:	b9 02 00 00 00       	mov    $0x2,%ecx
 105e606:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
 105e60b:	48 89 08             	mov    %rcx,(%rax)
 105e60e:	48 81 c4 d8 09 00 00 	add    $0x9d8,%rsp
 105e615:	5b                   	pop    %rbx
 105e616:	41 5c                	pop    %r12
 105e618:	41 5d                	pop    %r13
 105e61a:	41 5e                	pop    %r14
 105e61c:	41 5f                	pop    %r15
 105e61e:	5d                   	pop    %rbp
 105e61f:	c3                   	ret
 105e620:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e627:	48 89 c6             	mov    %rax,%rsi
 105e62a:	48 ff ce             	dec    %rsi
 105e62d:	0f 80 92 09 00 00    	jo     105efc5 <my.vm::run+0x3a95>
 105e633:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e63a:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e63e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e642:	48 39 d6             	cmp    %rdx,%rsi
 105e645:	73 57                	jae    105e69e <my.vm::run+0x316e>
 105e647:	31 c9                	xor    %ecx,%ecx
 105e649:	eb bb                	jmp    105e606 <my.vm::run+0x30d6>
 105e64b:	48 89 f1             	mov    %rsi,%rcx
 105e64e:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e652:	48 21 d1             	and    %rdx,%rcx
 105e655:	48 01 f1             	add    %rsi,%rcx
 105e658:	48 39 d1             	cmp    %rdx,%rcx
 105e65b:	0f 82 23 cf ff ff    	jb     105b584 <my.vm::run+0x54>
 105e661:	48 8d 3d 58 27 02 00 	lea    0x22758(%rip),%rdi        # 1080dc0 <core_durable_error.verbs+0x3f0>
 105e668:	e8 13 6a fc ff       	call   1025080 <myl_core_trap>
 105e66d:	48 8d 3d fc 40 02 00 	lea    0x240fc(%rip),%rdi        # 1082770 <core_durable_error.verbs+0x1da0>
 105e674:	e8 87 bd fc ff       	call   102a400 <myl_core_assert_fail>
 105e679:	48 8d 3d 70 27 02 00 	lea    0x22770(%rip),%rdi        # 1080df0 <core_durable_error.verbs+0x420>
 105e680:	ba 01 00 00 00       	mov    $0x1,%edx
 105e685:	e8 f6 69 fc ff       	call   1025080 <myl_core_trap>
 105e68a:	48 8d 3d 2f 2a 02 00 	lea    0x22a2f(%rip),%rdi        # 10810c0 <core_durable_error.verbs+0x6f0>
 105e691:	ba 01 00 00 00       	mov    $0x1,%edx
 105e696:	48 89 de             	mov    %rbx,%rsi
 105e699:	e8 e2 69 fc ff       	call   1025080 <myl_core_trap>
 105e69e:	48 89 f0             	mov    %rsi,%rax
 105e6a1:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e6a5:	48 21 d0             	and    %rdx,%rax
 105e6a8:	48 01 f0             	add    %rsi,%rax
 105e6ab:	48 39 d0             	cmp    %rdx,%rax
 105e6ae:	72 97                	jb     105e647 <my.vm::run+0x3117>
 105e6b0:	48 8d 3d 89 31 02 00 	lea    0x23189(%rip),%rdi        # 1081840 <core_durable_error.verbs+0xe70>
 105e6b7:	e8 c4 69 fc ff       	call   1025080 <myl_core_trap>
 105e6bc:	83 f9 09             	cmp    $0x9,%ecx
 105e6bf:	0f 87 a4 06 00 00    	ja     105ed69 <my.vm::run+0x3839>
 105e6c5:	89 c8                	mov    %ecx,%eax
 105e6c7:	48 8d 0d 72 8d fa ff 	lea    -0x5728e(%rip),%rcx        # 1007440 <core_number_pairs+0x1e0>
 105e6ce:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105e6d2:	48 01 c8             	add    %rcx,%rax
 105e6d5:	ff e0                	jmp    *%rax
 105e6d7:	48 8d 3d b2 74 02 00 	lea    0x274b2(%rip),%rdi        # 1085b90 <core_durable_error.verbs+0x51c0>
 105e6de:	e8 1d bd fc ff       	call   102a400 <myl_core_assert_fail>
 105e6e3:	48 8d 3d 86 4c 02 00 	lea    0x24c86(%rip),%rdi        # 1083370 <core_durable_error.verbs+0x29a0>
 105e6ea:	4c 89 e6             	mov    %r12,%rsi
 105e6ed:	e8 8e 69 fc ff       	call   1025080 <myl_core_trap>
 105e6f2:	48 8d 3d a7 4c 02 00 	lea    0x24ca7(%rip),%rdi        # 10833a0 <core_durable_error.verbs+0x29d0>
 105e6f9:	4c 89 e6             	mov    %r12,%rsi
 105e6fc:	e8 7f 69 fc ff       	call   1025080 <myl_core_trap>
 105e701:	48 8d 3d 38 4c 02 00 	lea    0x24c38(%rip),%rdi        # 1083340 <core_durable_error.verbs+0x2970>
 105e708:	e8 73 69 fc ff       	call   1025080 <myl_core_trap>
 105e70d:	48 8d 3d 8c 46 02 00 	lea    0x2468c(%rip),%rdi        # 1082da0 <core_durable_error.verbs+0x23d0>
 105e714:	ba 01 00 00 00       	mov    $0x1,%edx
 105e719:	48 89 c6             	mov    %rax,%rsi
 105e71c:	e8 5f 69 fc ff       	call   1025080 <myl_core_trap>
 105e721:	83 fa 01             	cmp    $0x1,%edx
 105e724:	0f 84 eb 01 00 00    	je     105e915 <my.vm::run+0x33e5>
 105e72a:	85 d2                	test   %edx,%edx
 105e72c:	0f 85 ef 01 00 00    	jne    105e921 <my.vm::run+0x33f1>
 105e732:	48 8d 3d 17 45 02 00 	lea    0x24517(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e739:	e8 c2 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e73e:	83 f8 01             	cmp    $0x1,%eax
 105e741:	0f 84 e6 01 00 00    	je     105e92d <my.vm::run+0x33fd>
 105e747:	85 c0                	test   %eax,%eax
 105e749:	0f 85 ea 01 00 00    	jne    105e939 <my.vm::run+0x3409>
 105e74f:	48 8d 3d fa 44 02 00 	lea    0x244fa(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e756:	e8 a5 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e75b:	83 fa 01             	cmp    $0x1,%edx
 105e75e:	0f 84 e1 01 00 00    	je     105e945 <my.vm::run+0x3415>
 105e764:	85 d2                	test   %edx,%edx
 105e766:	0f 85 e5 01 00 00    	jne    105e951 <my.vm::run+0x3421>
 105e76c:	48 8d 3d dd 44 02 00 	lea    0x244dd(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e773:	e8 88 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e778:	83 f8 01             	cmp    $0x1,%eax
 105e77b:	0f 84 dc 01 00 00    	je     105e95d <my.vm::run+0x342d>
 105e781:	85 c0                	test   %eax,%eax
 105e783:	0f 85 e0 01 00 00    	jne    105e969 <my.vm::run+0x3439>
 105e789:	48 8d 3d c0 44 02 00 	lea    0x244c0(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e790:	e8 6b bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e795:	83 f8 01             	cmp    $0x1,%eax
 105e798:	0f 84 d7 01 00 00    	je     105e975 <my.vm::run+0x3445>
 105e79e:	85 c0                	test   %eax,%eax
 105e7a0:	0f 85 db 01 00 00    	jne    105e981 <my.vm::run+0x3451>
 105e7a6:	48 8d 3d a3 44 02 00 	lea    0x244a3(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e7ad:	e8 4e bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e7b2:	83 f8 01             	cmp    $0x1,%eax
 105e7b5:	0f 84 d2 01 00 00    	je     105e98d <my.vm::run+0x345d>
 105e7bb:	85 c0                	test   %eax,%eax
 105e7bd:	0f 85 d6 01 00 00    	jne    105e999 <my.vm::run+0x3469>
 105e7c3:	48 8d 3d 86 44 02 00 	lea    0x24486(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e7ca:	e8 31 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e7cf:	83 f8 01             	cmp    $0x1,%eax
 105e7d2:	0f 84 de 01 00 00    	je     105e9b6 <my.vm::run+0x3486>
 105e7d8:	85 c0                	test   %eax,%eax
 105e7da:	0f 85 e2 01 00 00    	jne    105e9c2 <my.vm::run+0x3492>
 105e7e0:	48 8d 3d 69 44 02 00 	lea    0x24469(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e7e7:	e8 14 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e7ec:	83 f8 01             	cmp    $0x1,%eax
 105e7ef:	0f 84 d9 01 00 00    	je     105e9ce <my.vm::run+0x349e>
 105e7f5:	85 c0                	test   %eax,%eax
 105e7f7:	0f 85 dd 01 00 00    	jne    105e9da <my.vm::run+0x34aa>
 105e7fd:	48 8d 3d 4c 44 02 00 	lea    0x2444c(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e804:	e8 f7 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e809:	83 f8 01             	cmp    $0x1,%eax
 105e80c:	0f 84 d4 01 00 00    	je     105e9e6 <my.vm::run+0x34b6>
 105e812:	85 c0                	test   %eax,%eax
 105e814:	0f 85 f8 01 00 00    	jne    105ea12 <my.vm::run+0x34e2>
 105e81a:	48 8d 3d 2f 44 02 00 	lea    0x2442f(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e821:	e8 da bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e826:	83 f8 01             	cmp    $0x1,%eax
 105e829:	0f 84 c3 01 00 00    	je     105e9f2 <my.vm::run+0x34c2>
 105e82f:	85 c0                	test   %eax,%eax
 105e831:	0f 85 e7 01 00 00    	jne    105ea1e <my.vm::run+0x34ee>
 105e837:	48 8d 3d 12 44 02 00 	lea    0x24412(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e83e:	e8 bd bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e843:	83 f8 01             	cmp    $0x1,%eax
 105e846:	0f 84 4a 02 00 00    	je     105ea96 <my.vm::run+0x3566>
 105e84c:	85 c0                	test   %eax,%eax
 105e84e:	0f 85 4e 02 00 00    	jne    105eaa2 <my.vm::run+0x3572>
 105e854:	48 8d 3d f5 43 02 00 	lea    0x243f5(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e85b:	e8 a0 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e860:	83 f9 01             	cmp    $0x1,%ecx
 105e863:	0f 84 56 02 00 00    	je     105eabf <my.vm::run+0x358f>
 105e869:	85 c9                	test   %ecx,%ecx
 105e86b:	0f 85 5a 02 00 00    	jne    105eacb <my.vm::run+0x359b>
 105e871:	48 8d 3d d8 43 02 00 	lea    0x243d8(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105e878:	e8 83 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e87d:	48 8d 3d 7c 45 02 00 	lea    0x2457c(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x2430>
 105e884:	ba 01 00 00 00       	mov    $0x1,%edx
 105e889:	e8 f2 67 fc ff       	call   1025080 <myl_core_trap>
 105e88e:	83 f9 09             	cmp    $0x9,%ecx
 105e891:	0f 87 cd 06 00 00    	ja     105ef64 <my.vm::run+0x3a34>
 105e897:	89 c8                	mov    %ecx,%eax
 105e899:	48 8d 0d 00 8c fa ff 	lea    -0x57400(%rip),%rcx        # 10074a0 <core_number_pairs+0x240>
 105e8a0:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105e8a4:	48 01 c8             	add    %rcx,%rax
 105e8a7:	ff e0                	jmp    *%rax
 105e8a9:	48 8d 3d 90 98 02 00 	lea    0x29890(%rip),%rdi        # 1088140 <core_durable_error.verbs+0x7770>
 105e8b0:	e8 4b bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8b5:	48 8d 3d 04 73 02 00 	lea    0x27304(%rip),%rdi        # 1085bc0 <core_durable_error.verbs+0x51f0>
 105e8bc:	e8 3f bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8c1:	48 8d 3d 28 73 02 00 	lea    0x27328(%rip),%rdi        # 1085bf0 <core_durable_error.verbs+0x5220>
 105e8c8:	e8 33 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8cd:	48 8d 3d ac 73 02 00 	lea    0x273ac(%rip),%rdi        # 1085c80 <core_durable_error.verbs+0x52b0>
 105e8d4:	e8 27 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8d9:	48 8d 3d 40 73 02 00 	lea    0x27340(%rip),%rdi        # 1085c20 <core_durable_error.verbs+0x5250>
 105e8e0:	e8 1b bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8e5:	48 8d 3d 64 73 02 00 	lea    0x27364(%rip),%rdi        # 1085c50 <core_durable_error.verbs+0x5280>
 105e8ec:	e8 0f bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8f1:	48 8d 3d b8 73 02 00 	lea    0x273b8(%rip),%rdi        # 1085cb0 <core_durable_error.verbs+0x52e0>
 105e8f8:	e8 03 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8fd:	48 8d 3d dc 73 02 00 	lea    0x273dc(%rip),%rdi        # 1085ce0 <core_durable_error.verbs+0x5310>
 105e904:	e8 f7 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e909:	48 8d 3d 00 74 02 00 	lea    0x27400(%rip),%rdi        # 1085d10 <core_durable_error.verbs+0x5340>
 105e910:	e8 eb ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e915:	48 8d 3d 64 43 02 00 	lea    0x24364(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e91c:	e8 df ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e921:	48 8d 3d 88 43 02 00 	lea    0x24388(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105e928:	e8 d3 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e92d:	48 8d 3d 4c 43 02 00 	lea    0x2434c(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e934:	e8 c7 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e939:	48 8d 3d 70 43 02 00 	lea    0x24370(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105e940:	e8 bb ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e945:	48 8d 3d 34 43 02 00 	lea    0x24334(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e94c:	e8 af ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e951:	48 8d 3d 58 43 02 00 	lea    0x24358(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105e958:	e8 a3 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e95d:	48 8d 3d 1c 43 02 00 	lea    0x2431c(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e964:	e8 97 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e969:	48 8d 3d 40 43 02 00 	lea    0x24340(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105e970:	e8 8b ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e975:	48 8d 3d 04 43 02 00 	lea    0x24304(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e97c:	e8 7f ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e981:	48 8d 3d 28 43 02 00 	lea    0x24328(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105e988:	e8 73 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e98d:	48 8d 3d ec 42 02 00 	lea    0x242ec(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e994:	e8 67 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e999:	48 8d 3d 10 43 02 00 	lea    0x24310(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105e9a0:	e8 5b ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9a5:	48 8d 3d 34 4c 02 00 	lea    0x24c34(%rip),%rdi        # 10835e0 <core_durable_error.verbs+0x2c10>
 105e9ac:	ba 01 00 00 00       	mov    $0x1,%edx
 105e9b1:	e8 ca 66 fc ff       	call   1025080 <myl_core_trap>
 105e9b6:	48 8d 3d c3 42 02 00 	lea    0x242c3(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e9bd:	e8 3e ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9c2:	48 8d 3d e7 42 02 00 	lea    0x242e7(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105e9c9:	e8 32 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9ce:	48 8d 3d ab 42 02 00 	lea    0x242ab(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e9d5:	e8 26 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9da:	48 8d 3d cf 42 02 00 	lea    0x242cf(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105e9e1:	e8 1a ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9e6:	48 8d 3d 93 42 02 00 	lea    0x24293(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e9ed:	e8 0e ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9f2:	48 8d 3d 87 42 02 00 	lea    0x24287(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105e9f9:	e8 02 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9fe:	48 8d 3d 6b 2b 02 00 	lea    0x22b6b(%rip),%rdi        # 1081570 <core_durable_error.verbs+0xba0>
 105ea05:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea0a:	4c 89 ee             	mov    %r13,%rsi
 105ea0d:	e8 6e 66 fc ff       	call   1025080 <myl_core_trap>
 105ea12:	48 8d 3d 97 42 02 00 	lea    0x24297(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105ea19:	e8 e2 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea1e:	48 8d 3d 8b 42 02 00 	lea    0x2428b(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105ea25:	e8 d6 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea2a:	48 8d 3d ff 2e 02 00 	lea    0x22eff(%rip),%rdi        # 1081930 <core_durable_error.verbs+0xf60>
 105ea31:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea36:	e8 45 66 fc ff       	call   1025080 <myl_core_trap>
 105ea3b:	48 8d 3d 4e 2f 02 00 	lea    0x22f4e(%rip),%rdi        # 1081990 <core_durable_error.verbs+0xfc0>
 105ea42:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea47:	e8 34 66 fc ff       	call   1025080 <myl_core_trap>
 105ea4c:	48 8d 3d 2d 2d 02 00 	lea    0x22d2d(%rip),%rdi        # 1081780 <core_durable_error.verbs+0xdb0>
 105ea53:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea58:	e8 23 66 fc ff       	call   1025080 <myl_core_trap>
 105ea5d:	48 8d 3d 1c 45 02 00 	lea    0x2451c(%rip),%rdi        # 1082f80 <core_durable_error.verbs+0x25b0>
 105ea64:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea69:	e8 12 66 fc ff       	call   1025080 <myl_core_trap>
 105ea6e:	48 8d 3d 7b 29 02 00 	lea    0x2297b(%rip),%rdi        # 10813f0 <core_durable_error.verbs+0xa20>
 105ea75:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea7a:	4c 89 ee             	mov    %r13,%rsi
 105ea7d:	e8 fe 65 fc ff       	call   1025080 <myl_core_trap>
 105ea82:	48 8d 3d 27 2d 02 00 	lea    0x22d27(%rip),%rdi        # 10817b0 <core_durable_error.verbs+0xde0>
 105ea89:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea8e:	4c 89 ee             	mov    %r13,%rsi
 105ea91:	e8 ea 65 fc ff       	call   1025080 <myl_core_trap>
 105ea96:	48 8d 3d e3 41 02 00 	lea    0x241e3(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105ea9d:	e8 5e b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105eaa2:	48 8d 3d 07 42 02 00 	lea    0x24207(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105eaa9:	e8 52 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105eaae:	48 8d 3d 7b 49 02 00 	lea    0x2497b(%rip),%rdi        # 1083430 <core_durable_error.verbs+0x2a60>
 105eab5:	ba 01 00 00 00       	mov    $0x1,%edx
 105eaba:	e8 c1 65 fc ff       	call   1025080 <myl_core_trap>
 105eabf:	48 8d 3d ba 41 02 00 	lea    0x241ba(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105eac6:	e8 35 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105eacb:	48 8d 3d de 41 02 00 	lea    0x241de(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105ead2:	e8 29 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ead7:	48 8d 3d 82 3d 02 00 	lea    0x23d82(%rip),%rdi        # 1082860 <core_durable_error.verbs+0x1e90>
 105eade:	ba 01 00 00 00       	mov    $0x1,%edx
 105eae3:	48 89 c6             	mov    %rax,%rsi
 105eae6:	e8 95 65 fc ff       	call   1025080 <myl_core_trap>
 105eaeb:	48 8d 3d 1e 4b 02 00 	lea    0x24b1e(%rip),%rdi        # 1083610 <core_durable_error.verbs+0x2c40>
 105eaf2:	ba 01 00 00 00       	mov    $0x1,%edx
 105eaf7:	4c 89 ee             	mov    %r13,%rsi
 105eafa:	e8 81 65 fc ff       	call   1025080 <myl_core_trap>
 105eaff:	48 8d 3d ca 2a 02 00 	lea    0x22aca(%rip),%rdi        # 10815d0 <core_durable_error.verbs+0xc00>
 105eb06:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb0b:	4c 89 ee             	mov    %r13,%rsi
 105eb0e:	e8 6d 65 fc ff       	call   1025080 <myl_core_trap>
 105eb13:	48 8d 3d 96 23 02 00 	lea    0x22396(%rip),%rdi        # 1080eb0 <core_durable_error.verbs+0x4e0>
 105eb1a:	e8 61 65 fc ff       	call   1025080 <myl_core_trap>
 105eb1f:	48 8d 3d fa 22 02 00 	lea    0x222fa(%rip),%rdi        # 1080e20 <core_durable_error.verbs+0x450>
 105eb26:	4c 89 ce             	mov    %r9,%rsi
 105eb29:	e8 52 65 fc ff       	call   1025080 <myl_core_trap>
 105eb2e:	48 8d 3d fb 3f 02 00 	lea    0x23ffb(%rip),%rdi        # 1082b30 <core_durable_error.verbs+0x2160>
 105eb35:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb3a:	e8 41 65 fc ff       	call   1025080 <myl_core_trap>
 105eb3f:	48 8d 3d 1a 43 02 00 	lea    0x2431a(%rip),%rdi        # 1082e60 <core_durable_error.verbs+0x2490>
 105eb46:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb4b:	48 89 c6             	mov    %rax,%rsi
 105eb4e:	e8 2d 65 fc ff       	call   1025080 <myl_core_trap>
 105eb53:	48 8d 3d b6 29 02 00 	lea    0x229b6(%rip),%rdi        # 1081510 <core_durable_error.verbs+0xb40>
 105eb5a:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb5f:	4c 89 ee             	mov    %r13,%rsi
 105eb62:	e8 19 65 fc ff       	call   1025080 <myl_core_trap>
 105eb67:	48 8d 3d e2 25 02 00 	lea    0x225e2(%rip),%rdi        # 1081150 <core_durable_error.verbs+0x780>
 105eb6e:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb73:	4c 89 ee             	mov    %r13,%rsi
 105eb76:	e8 05 65 fc ff       	call   1025080 <myl_core_trap>
 105eb7b:	48 8d 3d ae 27 02 00 	lea    0x227ae(%rip),%rdi        # 1081330 <core_durable_error.verbs+0x960>
 105eb82:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb87:	4c 89 ee             	mov    %r13,%rsi
 105eb8a:	e8 f1 64 fc ff       	call   1025080 <myl_core_trap>
 105eb8f:	48 8d 3d ca 3f 02 00 	lea    0x23fca(%rip),%rdi        # 1082b60 <core_durable_error.verbs+0x2190>
 105eb96:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb9b:	48 89 de             	mov    %rbx,%rsi
 105eb9e:	e8 dd 64 fc ff       	call   1025080 <myl_core_trap>
 105eba3:	48 8d 3d 06 29 02 00 	lea    0x22906(%rip),%rdi        # 10814b0 <core_durable_error.verbs+0xae0>
 105ebaa:	ba 01 00 00 00       	mov    $0x1,%edx
 105ebaf:	4c 89 ee             	mov    %r13,%rsi
 105ebb2:	e8 c9 64 fc ff       	call   1025080 <myl_core_trap>
 105ebb7:	48 8d 3d 92 28 02 00 	lea    0x22892(%rip),%rdi        # 1081450 <core_durable_error.verbs+0xa80>
 105ebbe:	ba 01 00 00 00       	mov    $0x1,%edx
 105ebc3:	4c 89 ee             	mov    %r13,%rsi
 105ebc6:	e8 b5 64 fc ff       	call   1025080 <myl_core_trap>
 105ebcb:	48 8d 3d 8e 27 02 00 	lea    0x2278e(%rip),%rdi        # 1081360 <core_durable_error.verbs+0x990>
 105ebd2:	4c 89 ce             	mov    %r9,%rsi
 105ebd5:	48 89 c2             	mov    %rax,%rdx
 105ebd8:	e8 a3 64 fc ff       	call   1025080 <myl_core_trap>
 105ebdd:	48 8d 3d ac 27 02 00 	lea    0x227ac(%rip),%rdi        # 1081390 <core_durable_error.verbs+0x9c0>
 105ebe4:	ba 01 00 00 00       	mov    $0x1,%edx
 105ebe9:	4c 89 ee             	mov    %r13,%rsi
 105ebec:	e8 8f 64 fc ff       	call   1025080 <myl_core_trap>
 105ebf1:	48 8d 3d 18 26 02 00 	lea    0x22618(%rip),%rdi        # 1081210 <core_durable_error.verbs+0x840>
 105ebf8:	ba 01 00 00 00       	mov    $0x1,%edx
 105ebfd:	4c 89 ee             	mov    %r13,%rsi
 105ec00:	e8 7b 64 fc ff       	call   1025080 <myl_core_trap>
 105ec05:	48 8d 3d d4 46 02 00 	lea    0x246d4(%rip),%rdi        # 10832e0 <core_durable_error.verbs+0x2910>
 105ec0c:	48 89 c6             	mov    %rax,%rsi
 105ec0f:	48 89 da             	mov    %rbx,%rdx
 105ec12:	e8 69 64 fc ff       	call   1025080 <myl_core_trap>
 105ec17:	48 8d 3d e2 2c 02 00 	lea    0x22ce2(%rip),%rdi        # 1081900 <core_durable_error.verbs+0xf30>
 105ec1e:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec23:	e8 58 64 fc ff       	call   1025080 <myl_core_trap>
 105ec28:	48 8d 3d 81 46 02 00 	lea    0x24681(%rip),%rdi        # 10832b0 <core_durable_error.verbs+0x28e0>
 105ec2f:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec34:	4c 89 ee             	mov    %r13,%rsi
 105ec37:	e8 44 64 fc ff       	call   1025080 <myl_core_trap>
 105ec3c:	48 8d 3d dd 48 02 00 	lea    0x248dd(%rip),%rdi        # 1083520 <core_durable_error.verbs+0x2b50>
 105ec43:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec48:	4c 89 ee             	mov    %r13,%rsi
 105ec4b:	e8 30 64 fc ff       	call   1025080 <myl_core_trap>
 105ec50:	48 8d 3d 69 2a 02 00 	lea    0x22a69(%rip),%rdi        # 10816c0 <core_durable_error.verbs+0xcf0>
 105ec57:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec5c:	4c 89 ee             	mov    %r13,%rsi
 105ec5f:	e8 1c 64 fc ff       	call   1025080 <myl_core_trap>
 105ec64:	48 8d 3d 65 3e 02 00 	lea    0x23e65(%rip),%rdi        # 1082ad0 <core_durable_error.verbs+0x2100>
 105ec6b:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec70:	e8 0b 64 fc ff       	call   1025080 <myl_core_trap>
 105ec75:	48 8d 3d 24 26 02 00 	lea    0x22624(%rip),%rdi        # 10812a0 <core_durable_error.verbs+0x8d0>
 105ec7c:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec81:	4c 89 ee             	mov    %r13,%rsi
 105ec84:	e8 f7 63 fc ff       	call   1025080 <myl_core_trap>
 105ec89:	48 8d 3d 60 48 02 00 	lea    0x24860(%rip),%rdi        # 10834f0 <core_durable_error.verbs+0x2b20>
 105ec90:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec95:	e8 e6 63 fc ff       	call   1025080 <myl_core_trap>
 105ec9a:	48 8d 3d bf 29 02 00 	lea    0x229bf(%rip),%rdi        # 1081660 <core_durable_error.verbs+0xc90>
 105eca1:	48 89 c6             	mov    %rax,%rsi
 105eca4:	4c 89 ca             	mov    %r9,%rdx
 105eca7:	e8 d4 63 fc ff       	call   1025080 <myl_core_trap>
 105ecac:	48 8d 3d 7d 29 02 00 	lea    0x2297d(%rip),%rdi        # 1081630 <core_durable_error.verbs+0xc60>
 105ecb3:	ba 01 00 00 00       	mov    $0x1,%edx
 105ecb8:	4c 89 ee             	mov    %r13,%rsi
 105ecbb:	e8 c0 63 fc ff       	call   1025080 <myl_core_trap>
 105ecc0:	48 8d 3d 59 2a 02 00 	lea    0x22a59(%rip),%rdi        # 1081720 <core_durable_error.verbs+0xd50>
 105ecc7:	ba 01 00 00 00       	mov    $0x1,%edx
 105eccc:	e8 af 63 fc ff       	call   1025080 <myl_core_trap>
 105ecd1:	48 8d 3d 88 23 02 00 	lea    0x22388(%rip),%rdi        # 1081060 <core_durable_error.verbs+0x690>
 105ecd8:	ba 01 00 00 00       	mov    $0x1,%edx
 105ecdd:	48 89 c6             	mov    %rax,%rsi
 105ece0:	e8 9b 63 fc ff       	call   1025080 <myl_core_trap>
 105ece5:	48 8d 3d 24 22 02 00 	lea    0x22224(%rip),%rdi        # 1080f10 <core_durable_error.verbs+0x540>
 105ecec:	e8 8f 63 fc ff       	call   1025080 <myl_core_trap>
 105ecf1:	48 8d 3d 78 25 02 00 	lea    0x22578(%rip),%rdi        # 1081270 <core_durable_error.verbs+0x8a0>
 105ecf8:	ba 01 00 00 00       	mov    $0x1,%edx
 105ecfd:	4c 89 ee             	mov    %r13,%rsi
 105ed00:	e8 7b 63 fc ff       	call   1025080 <myl_core_trap>
 105ed05:	48 8d 3d a4 24 02 00 	lea    0x224a4(%rip),%rdi        # 10811b0 <core_durable_error.verbs+0x7e0>
 105ed0c:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed11:	4c 89 ee             	mov    %r13,%rsi
 105ed14:	e8 67 63 fc ff       	call   1025080 <myl_core_trap>
 105ed19:	48 8d 3d 50 2b 02 00 	lea    0x22b50(%rip),%rdi        # 1081870 <core_durable_error.verbs+0xea0>
 105ed20:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed25:	48 89 de             	mov    %rbx,%rsi
 105ed28:	e8 53 63 fc ff       	call   1025080 <myl_core_trap>
 105ed2d:	48 8d 3d cc 22 02 00 	lea    0x222cc(%rip),%rdi        # 1081000 <core_durable_error.verbs+0x630>
 105ed34:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed39:	48 89 de             	mov    %rbx,%rsi
 105ed3c:	e8 3f 63 fc ff       	call   1025080 <myl_core_trap>
 105ed41:	48 8d 3d f8 21 02 00 	lea    0x221f8(%rip),%rdi        # 1080f40 <core_durable_error.verbs+0x570>
 105ed48:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed4d:	48 89 de             	mov    %rbx,%rsi
 105ed50:	e8 2b 63 fc ff       	call   1025080 <myl_core_trap>
 105ed55:	48 8d 3d 44 22 02 00 	lea    0x22244(%rip),%rdi        # 1080fa0 <core_durable_error.verbs+0x5d0>
 105ed5c:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed61:	48 89 de             	mov    %rbx,%rsi
 105ed64:	e8 17 63 fc ff       	call   1025080 <myl_core_trap>
 105ed69:	48 8d 3d d0 6f 02 00 	lea    0x26fd0(%rip),%rdi        # 1085d40 <core_durable_error.verbs+0x5370>
 105ed70:	e8 8b b6 fc ff       	call   102a400 <myl_core_assert_fail>
 105ed75:	83 f9 01             	cmp    $0x1,%ecx
 105ed78:	0f 84 dd 00 00 00    	je     105ee5b <my.vm::run+0x392b>
 105ed7e:	85 c9                	test   %ecx,%ecx
 105ed80:	0f 85 e1 00 00 00    	jne    105ee67 <my.vm::run+0x3937>
 105ed86:	48 8d 3d c3 3e 02 00 	lea    0x23ec3(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105ed8d:	e8 6e b6 fc ff       	call   102a400 <myl_core_assert_fail>
 105ed92:	83 f8 01             	cmp    $0x1,%eax
 105ed95:	0f 84 d8 00 00 00    	je     105ee73 <my.vm::run+0x3943>
 105ed9b:	85 c0                	test   %eax,%eax
 105ed9d:	0f 85 dc 00 00 00    	jne    105ee7f <my.vm::run+0x394f>
 105eda3:	48 8d 3d a6 3e 02 00 	lea    0x23ea6(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105edaa:	e8 51 b6 fc ff       	call   102a400 <myl_core_assert_fail>
 105edaf:	48 8d 3d 5a 3c 02 00 	lea    0x23c5a(%rip),%rdi        # 1082a10 <core_durable_error.verbs+0x2040>
 105edb6:	ba 01 00 00 00       	mov    $0x1,%edx
 105edbb:	48 89 ce             	mov    %rcx,%rsi
 105edbe:	e8 bd 62 fc ff       	call   1025080 <myl_core_trap>
 105edc3:	48 8d 3d b6 3b 02 00 	lea    0x23bb6(%rip),%rdi        # 1082980 <core_durable_error.verbs+0x1fb0>
 105edca:	ba 01 00 00 00       	mov    $0x1,%edx
 105edcf:	e8 ac 62 fc ff       	call   1025080 <myl_core_trap>
 105edd4:	48 8d 3d 05 21 02 00 	lea    0x22105(%rip),%rdi        # 1080ee0 <core_durable_error.verbs+0x510>
 105eddb:	4c 89 fe             	mov    %r15,%rsi
 105edde:	e8 9d 62 fc ff       	call   1025080 <myl_core_trap>
 105ede3:	48 8d 3d 46 3a 02 00 	lea    0x23a46(%rip),%rdi        # 1082830 <core_durable_error.verbs+0x1e60>
 105edea:	ba 01 00 00 00       	mov    $0x1,%edx
 105edef:	e8 8c 62 fc ff       	call   1025080 <myl_core_trap>
 105edf4:	48 8d 3d 95 1f 02 00 	lea    0x21f95(%rip),%rdi        # 1080d90 <core_durable_error.verbs+0x3c0>
 105edfb:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee00:	48 89 de             	mov    %rbx,%rsi
 105ee03:	e8 78 62 fc ff       	call   1025080 <myl_core_trap>
 105ee08:	48 8d 3d 61 3c 02 00 	lea    0x23c61(%rip),%rdi        # 1082a70 <core_durable_error.verbs+0x20a0>
 105ee0f:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee14:	48 89 ce             	mov    %rcx,%rsi
 105ee17:	e8 64 62 fc ff       	call   1025080 <myl_core_trap>
 105ee1c:	83 f8 01             	cmp    $0x1,%eax
 105ee1f:	0f 84 12 01 00 00    	je     105ef37 <my.vm::run+0x3a07>
 105ee25:	85 c0                	test   %eax,%eax
 105ee27:	0f 85 16 01 00 00    	jne    105ef43 <my.vm::run+0x3a13>
 105ee2d:	48 8d 3d 1c 3e 02 00 	lea    0x23e1c(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105ee34:	e8 c7 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee39:	48 8d 3d e0 3a 02 00 	lea    0x23ae0(%rip),%rdi        # 1082920 <core_durable_error.verbs+0x1f50>
 105ee40:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee45:	e8 36 62 fc ff       	call   1025080 <myl_core_trap>
 105ee4a:	48 8d 3d cf 40 02 00 	lea    0x240cf(%rip),%rdi        # 1082f20 <core_durable_error.verbs+0x2550>
 105ee51:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee56:	e8 25 62 fc ff       	call   1025080 <myl_core_trap>
 105ee5b:	48 8d 3d 1e 3e 02 00 	lea    0x23e1e(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105ee62:	e8 99 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee67:	48 8d 3d 42 3e 02 00 	lea    0x23e42(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105ee6e:	e8 8d b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee73:	48 8d 3d 06 3e 02 00 	lea    0x23e06(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105ee7a:	e8 81 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee7f:	48 8d 3d 2a 3e 02 00 	lea    0x23e2a(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105ee86:	e8 75 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee8b:	48 8d 3d 2e 40 02 00 	lea    0x2402e(%rip),%rdi        # 1082ec0 <core_durable_error.verbs+0x24f0>
 105ee92:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee97:	e8 e4 61 fc ff       	call   1025080 <myl_core_trap>
 105ee9c:	48 8d 3d cd 92 02 00 	lea    0x292cd(%rip),%rdi        # 1088170 <core_durable_error.verbs+0x77a0>
 105eea3:	e8 58 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eea8:	48 8d 3d f1 92 02 00 	lea    0x292f1(%rip),%rdi        # 10881a0 <core_durable_error.verbs+0x77d0>
 105eeaf:	e8 4c b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eeb4:	48 8d 3d 15 93 02 00 	lea    0x29315(%rip),%rdi        # 10881d0 <core_durable_error.verbs+0x7800>
 105eebb:	e8 40 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eec0:	48 8d 3d 39 93 02 00 	lea    0x29339(%rip),%rdi        # 1088200 <core_durable_error.verbs+0x7830>
 105eec7:	e8 34 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eecc:	48 8d 3d 5d 93 02 00 	lea    0x2935d(%rip),%rdi        # 1088230 <core_durable_error.verbs+0x7860>
 105eed3:	e8 28 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eed8:	48 8d 3d 81 93 02 00 	lea    0x29381(%rip),%rdi        # 1088260 <core_durable_error.verbs+0x7890>
 105eedf:	e8 1c b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eee4:	48 8d 3d a5 93 02 00 	lea    0x293a5(%rip),%rdi        # 1088290 <core_durable_error.verbs+0x78c0>
 105eeeb:	e8 10 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eef0:	48 8d 3d c9 93 02 00 	lea    0x293c9(%rip),%rdi        # 10882c0 <core_durable_error.verbs+0x78f0>
 105eef7:	e8 04 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eefc:	48 8d 3d 4d 43 02 00 	lea    0x2434d(%rip),%rdi        # 1083250 <core_durable_error.verbs+0x2880>
 105ef03:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef08:	48 89 c6             	mov    %rax,%rsi
 105ef0b:	e8 70 61 fc ff       	call   1025080 <myl_core_trap>
 105ef10:	48 8d 3d 09 43 02 00 	lea    0x24309(%rip),%rdi        # 1083220 <core_durable_error.verbs+0x2850>
 105ef17:	4c 89 ee             	mov    %r13,%rsi
 105ef1a:	48 89 da             	mov    %rbx,%rdx
 105ef1d:	e8 5e 61 fc ff       	call   1025080 <myl_core_trap>
 105ef22:	83 f9 01             	cmp    $0x1,%ecx
 105ef25:	74 6e                	je     105ef95 <my.vm::run+0x3a65>
 105ef27:	85 c9                	test   %ecx,%ecx
 105ef29:	75 76                	jne    105efa1 <my.vm::run+0x3a71>
 105ef2b:	48 8d 3d 1e 3d 02 00 	lea    0x23d1e(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105ef32:	e8 c9 b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef37:	48 8d 3d 42 3d 02 00 	lea    0x23d42(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105ef3e:	e8 bd b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef43:	48 8d 3d 66 3d 02 00 	lea    0x23d66(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105ef4a:	e8 b1 b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef4f:	83 f8 01             	cmp    $0x1,%eax
 105ef52:	74 59                	je     105efad <my.vm::run+0x3a7d>
 105ef54:	85 c0                	test   %eax,%eax
 105ef56:	75 61                	jne    105efb9 <my.vm::run+0x3a89>
 105ef58:	48 8d 3d f1 3c 02 00 	lea    0x23cf1(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2280>
 105ef5f:	e8 9c b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef64:	48 8d 3d 85 93 02 00 	lea    0x29385(%rip),%rdi        # 10882f0 <core_durable_error.verbs+0x7920>
 105ef6b:	e8 90 b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef70:	48 8d 3d c9 64 02 00 	lea    0x264c9(%rip),%rdi        # 1085440 <core_durable_error.verbs+0x4a70>
 105ef77:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef7c:	e8 ff 60 fc ff       	call   1025080 <myl_core_trap>
 105ef81:	48 8d 3d 58 64 02 00 	lea    0x26458(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x4a10>
 105ef88:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef8d:	48 89 c6             	mov    %rax,%rsi
 105ef90:	e8 eb 60 fc ff       	call   1025080 <myl_core_trap>
 105ef95:	48 8d 3d e4 3c 02 00 	lea    0x23ce4(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105ef9c:	e8 5f b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105efa1:	48 8d 3d 08 3d 02 00 	lea    0x23d08(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105efa8:	e8 53 b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105efad:	48 8d 3d cc 3c 02 00 	lea    0x23ccc(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x22b0>
 105efb4:	e8 47 b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105efb9:	48 8d 3d f0 3c 02 00 	lea    0x23cf0(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x22e0>
 105efc0:	e8 3b b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105efc5:	48 8d 3d 44 28 02 00 	lea    0x22844(%rip),%rdi        # 1081810 <core_durable_error.verbs+0xe40>
 105efcc:	ba 01 00 00 00       	mov    $0x1,%edx
 105efd1:	48 89 c6             	mov    %rax,%rsi
 105efd4:	e8 a7 60 fc ff       	call   1025080 <myl_core_trap>
 105efd9:	48 8d 3d 60 37 02 00 	lea    0x23760(%rip),%rdi        # 1082740 <core_durable_error.verbs+0x1d70>
 105efe0:	4c 89 de             	mov    %r11,%rsi
 105efe3:	e8 98 60 fc ff       	call   1025080 <myl_core_trap>
 105efe8:	48 8d 3d b1 37 02 00 	lea    0x237b1(%rip),%rdi        # 10827a0 <core_durable_error.verbs+0x1dd0>
 105efef:	e8 8c 60 fc ff       	call   1025080 <myl_core_trap>
 105eff4:	48 8d 3d f5 20 02 00 	lea    0x220f5(%rip),%rdi        # 10810f0 <core_durable_error.verbs+0x720>
 105effb:	48 89 c6             	mov    %rax,%rsi
 105effe:	e8 7d 60 fc ff       	call   1025080 <myl_core_trap>
 105f003:	48 8d 3d c6 3d 02 00 	lea    0x23dc6(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x2400>
 105f00a:	e8 71 60 fc ff       	call   1025080 <myl_core_trap>
 105f00f:	48 8d 3d 5a 6d 02 00 	lea    0x26d5a(%rip),%rdi        # 1085d70 <core_durable_error.verbs+0x53a0>
 105f016:	48 89 ee             	mov    %rbp,%rsi
 105f019:	e8 62 60 fc ff       	call   1025080 <myl_core_trap>
 105f01e:	48 8d 3d 0b 3e 02 00 	lea    0x23e0b(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2460>
 105f025:	4c 89 ee             	mov    %r13,%rsi
 105f028:	e8 53 60 fc ff       	call   1025080 <myl_core_trap>
 105f02d:	48 8d 3d 9c 22 02 00 	lea    0x2229c(%rip),%rdi        # 10812d0 <core_durable_error.verbs+0x900>
 105f034:	e8 47 60 fc ff       	call   1025080 <myl_core_trap>
 105f039:	48 8d 3d a0 24 02 00 	lea    0x224a0(%rip),%rdi        # 10814e0 <core_durable_error.verbs+0xb10>
 105f040:	e8 3b 60 fc ff       	call   1025080 <myl_core_trap>
 105f045:	48 8d 3d 74 44 02 00 	lea    0x24474(%rip),%rdi        # 10834c0 <core_durable_error.verbs+0x2af0>
 105f04c:	48 89 de             	mov    %rbx,%rsi
 105f04f:	e8 2c 60 fc ff       	call   1025080 <myl_core_trap>
 105f054:	48 8d 3d e5 45 02 00 	lea    0x245e5(%rip),%rdi        # 1083640 <core_durable_error.verbs+0x2c70>
 105f05b:	e8 20 60 fc ff       	call   1025080 <myl_core_trap>
 105f060:	48 8d 3d 19 24 02 00 	lea    0x22419(%rip),%rdi        # 1081480 <core_durable_error.verbs+0xab0>
 105f067:	e8 14 60 fc ff       	call   1025080 <myl_core_trap>
 105f06c:	48 8d 3d 8d 22 02 00 	lea    0x2228d(%rip),%rdi        # 1081300 <core_durable_error.verbs+0x930>
 105f073:	4c 89 ee             	mov    %r13,%rsi
 105f076:	e8 05 60 fc ff       	call   1025080 <myl_core_trap>
 105f07b:	48 8d 3d 4e 43 02 00 	lea    0x2434e(%rip),%rdi        # 10833d0 <core_durable_error.verbs+0x2a00>
 105f082:	e8 f9 5f fc ff       	call   1025080 <myl_core_trap>
 105f087:	48 8d 3d 72 3a 02 00 	lea    0x23a72(%rip),%rdi        # 1082b00 <core_durable_error.verbs+0x2130>
 105f08e:	4c 89 ee             	mov    %r13,%rsi
 105f091:	e8 ea 5f fc ff       	call   1025080 <myl_core_trap>
 105f096:	48 8d 3d f3 25 02 00 	lea    0x225f3(%rip),%rdi        # 1081690 <core_durable_error.verbs+0xcc0>
 105f09d:	e8 de 5f fc ff       	call   1025080 <myl_core_trap>
 105f0a2:	48 8d 3d f7 45 02 00 	lea    0x245f7(%rip),%rdi        # 10836a0 <core_durable_error.verbs+0x2cd0>
 105f0a9:	4c 89 ee             	mov    %r13,%rsi
 105f0ac:	e8 cf 5f fc ff       	call   1025080 <myl_core_trap>
 105f0b1:	48 8d 3d d8 1f 02 00 	lea    0x21fd8(%rip),%rdi        # 1081090 <core_durable_error.verbs+0x6c0>
 105f0b8:	e8 c3 5f fc ff       	call   1025080 <myl_core_trap>
 105f0bd:	48 8d 3d 6c 1f 02 00 	lea    0x21f6c(%rip),%rdi        # 1081030 <core_durable_error.verbs+0x660>
 105f0c4:	e8 b7 5f fc ff       	call   1025080 <myl_core_trap>
 105f0c9:	48 8d 3d a0 1e 02 00 	lea    0x21ea0(%rip),%rdi        # 1080f70 <core_durable_error.verbs+0x5a0>
 105f0d0:	e8 ab 5f fc ff       	call   1025080 <myl_core_trap>
 105f0d5:	48 8d 3d c4 24 02 00 	lea    0x224c4(%rip),%rdi        # 10815a0 <core_durable_error.verbs+0xbd0>
 105f0dc:	4c 89 e6             	mov    %r12,%rsi
 105f0df:	e8 9c 5f fc ff       	call   1025080 <myl_core_trap>
 105f0e4:	48 8d 3d 35 23 02 00 	lea    0x22335(%rip),%rdi        # 1081420 <core_durable_error.verbs+0xa50>
 105f0eb:	e8 90 5f fc ff       	call   1025080 <myl_core_trap>
 105f0f0:	48 8d 3d 99 3d 02 00 	lea    0x23d99(%rip),%rdi        # 1082e90 <core_durable_error.verbs+0x24c0>
 105f0f7:	e8 84 5f fc ff       	call   1025080 <myl_core_trap>
 105f0fc:	48 8d 3d 5d 6a 02 00 	lea    0x26a5d(%rip),%rdi        # 1085b60 <core_durable_error.verbs+0x5190>
 105f103:	4c 89 c6             	mov    %r8,%rsi
 105f106:	e8 75 5f fc ff       	call   1025080 <myl_core_trap>
 105f10b:	48 8d 3d 8e 27 02 00 	lea    0x2278e(%rip),%rdi        # 10818a0 <core_durable_error.verbs+0xed0>
 105f112:	4c 89 ee             	mov    %r13,%rsi
 105f115:	e8 66 5f fc ff       	call   1025080 <myl_core_trap>
 105f11a:	48 8d 3d ff 1f 02 00 	lea    0x21fff(%rip),%rdi        # 1081120 <core_durable_error.verbs+0x750>
 105f121:	4c 89 ee             	mov    %r13,%rsi
 105f124:	e8 57 5f fc ff       	call   1025080 <myl_core_trap>
 105f129:	48 8d 3d 90 22 02 00 	lea    0x22290(%rip),%rdi        # 10813c0 <core_durable_error.verbs+0x9f0>
 105f130:	e8 4b 5f fc ff       	call   1025080 <myl_core_trap>
 105f135:	48 8d 3d 84 28 02 00 	lea    0x22884(%rip),%rdi        # 10819c0 <core_durable_error.verbs+0xff0>
 105f13c:	4c 89 ee             	mov    %r13,%rsi
 105f13f:	e8 3c 5f fc ff       	call   1025080 <myl_core_trap>
 105f144:	48 8d 3d 65 3e 02 00 	lea    0x23e65(%rip),%rdi        # 1082fb0 <core_durable_error.verbs+0x25e0>
 105f14b:	4c 89 ee             	mov    %r13,%rsi
 105f14e:	e8 2d 5f fc ff       	call   1025080 <myl_core_trap>
 105f153:	48 8d 3d 06 28 02 00 	lea    0x22806(%rip),%rdi        # 1081960 <core_durable_error.verbs+0xf90>
 105f15a:	4c 89 ee             	mov    %r13,%rsi
 105f15d:	e8 1e 5f fc ff       	call   1025080 <myl_core_trap>
 105f162:	48 8d 3d d7 20 02 00 	lea    0x220d7(%rip),%rdi        # 1081240 <core_durable_error.verbs+0x870>
 105f169:	4c 89 ee             	mov    %r13,%rsi
 105f16c:	e8 0f 5f fc ff       	call   1025080 <myl_core_trap>
 105f171:	48 8d 3d d8 43 02 00 	lea    0x243d8(%rip),%rdi        # 1083550 <core_durable_error.verbs+0x2b80>
 105f178:	e8 03 5f fc ff       	call   1025080 <myl_core_trap>
 105f17d:	48 8d 3d 4c 1e 02 00 	lea    0x21e4c(%rip),%rdi        # 1080fd0 <core_durable_error.verbs+0x600>
 105f184:	e8 f7 5e fc ff       	call   1025080 <myl_core_trap>
 105f189:	48 8d 3d f0 1c 02 00 	lea    0x21cf0(%rip),%rdi        # 1080e80 <core_durable_error.verbs+0x4b0>
 105f190:	e8 eb 5e fc ff       	call   1025080 <myl_core_trap>
 105f195:	48 8d 3d 44 20 02 00 	lea    0x22044(%rip),%rdi        # 10811e0 <core_durable_error.verbs+0x810>
 105f19c:	4c 89 ee             	mov    %r13,%rsi
 105f19f:	e8 dc 5e fc ff       	call   1025080 <myl_core_trap>
 105f1a4:	48 8d 3d 25 27 02 00 	lea    0x22725(%rip),%rdi        # 10818d0 <core_durable_error.verbs+0xf00>
 105f1ab:	e8 d0 5e fc ff       	call   1025080 <myl_core_trap>
 105f1b0:	48 8d 3d b9 44 02 00 	lea    0x244b9(%rip),%rdi        # 1083670 <core_durable_error.verbs+0x2ca0>
 105f1b7:	4c 89 ee             	mov    %r13,%rsi
 105f1ba:	e8 c1 5e fc ff       	call   1025080 <myl_core_trap>
 105f1bf:	48 8d 3d 3a 24 02 00 	lea    0x2243a(%rip),%rdi        # 1081600 <core_durable_error.verbs+0xc30>
 105f1c6:	48 89 c2             	mov    %rax,%rdx
 105f1c9:	e8 b2 5e fc ff       	call   1025080 <myl_core_trap>
 105f1ce:	48 8d 3d 6b 23 02 00 	lea    0x2236b(%rip),%rdi        # 1081540 <core_durable_error.verbs+0xb70>
 105f1d5:	e8 a6 5e fc ff       	call   1025080 <myl_core_trap>
 105f1da:	48 8d 3d af 36 02 00 	lea    0x236af(%rip),%rdi        # 1082890 <core_durable_error.verbs+0x1ec0>
 105f1e1:	e8 9a 5e fc ff       	call   1025080 <myl_core_trap>
 105f1e6:	48 8d 3d 63 25 02 00 	lea    0x22563(%rip),%rdi        # 1081750 <core_durable_error.verbs+0xd80>
 105f1ed:	4c 89 ee             	mov    %r13,%rsi
 105f1f0:	e8 8b 5e fc ff       	call   1025080 <myl_core_trap>
 105f1f5:	48 8d 3d f4 24 02 00 	lea    0x224f4(%rip),%rdi        # 10816f0 <core_durable_error.verbs+0xd20>
 105f1fc:	e8 7f 5e fc ff       	call   1025080 <myl_core_trap>
 105f201:	48 8d 3d 08 41 02 00 	lea    0x24108(%rip),%rdi        # 1083310 <core_durable_error.verbs+0x2940>
 105f208:	e8 73 5e fc ff       	call   1025080 <myl_core_trap>
 105f20d:	48 8d 3d ec 6b 02 00 	lea    0x26bec(%rip),%rdi        # 1085e00 <core_durable_error.verbs+0x5430>
 105f214:	4c 89 e6             	mov    %r12,%rsi
 105f217:	48 89 c2             	mov    %rax,%rdx
 105f21a:	e8 61 5e fc ff       	call   1025080 <myl_core_trap>
 105f21f:	48 8d 3d da 41 02 00 	lea    0x241da(%rip),%rdi        # 1083400 <core_durable_error.verbs+0x2a30>
 105f226:	e8 55 5e fc ff       	call   1025080 <myl_core_trap>
 105f22b:	48 8d 3d 4e 1f 02 00 	lea    0x21f4e(%rip),%rdi        # 1081180 <core_durable_error.verbs+0x7b0>
 105f232:	4c 89 ee             	mov    %r13,%rsi
 105f235:	e8 46 5e fc ff       	call   1025080 <myl_core_trap>
 105f23a:	48 8d 3d 4f 39 02 00 	lea    0x2394f(%rip),%rdi        # 1082b90 <core_durable_error.verbs+0x21c0>
 105f241:	4c 89 ee             	mov    %r13,%rsi
 105f244:	e8 37 5e fc ff       	call   1025080 <myl_core_trap>
 105f249:	48 8d 3d 90 25 02 00 	lea    0x22590(%rip),%rdi        # 10817e0 <core_durable_error.verbs+0xe10>
 105f250:	e8 2b 5e fc ff       	call   1025080 <myl_core_trap>
 105f255:	48 8d 3d f4 1b 02 00 	lea    0x21bf4(%rip),%rdi        # 1080e50 <core_durable_error.verbs+0x480>
 105f25c:	e8 1f 5e fc ff       	call   1025080 <myl_core_trap>
 105f261:	48 8d 3d 38 38 02 00 	lea    0x23838(%rip),%rdi        # 1082aa0 <core_durable_error.verbs+0x20d0>
 105f268:	e8 13 5e fc ff       	call   1025080 <myl_core_trap>
 105f26d:	48 8d 3d 7c 3c 02 00 	lea    0x23c7c(%rip),%rdi        # 1082ef0 <core_durable_error.verbs+0x2520>
 105f274:	48 89 c6             	mov    %rax,%rsi
 105f277:	e8 04 5e fc ff       	call   1025080 <myl_core_trap>
 105f27c:	48 8d 3d 3d 39 02 00 	lea    0x2393d(%rip),%rdi        # 1082bc0 <core_durable_error.verbs+0x21f0>
 105f283:	48 89 de             	mov    %rbx,%rsi
 105f286:	e8 f5 5d fc ff       	call   1025080 <myl_core_trap>
 105f28b:	48 8d 3d 4e 37 02 00 	lea    0x2374e(%rip),%rdi        # 10829e0 <core_durable_error.verbs+0x2010>
 105f292:	48 89 de             	mov    %rbx,%rsi
 105f295:	e8 e6 5d fc ff       	call   1025080 <myl_core_trap>
 105f29a:	48 8d 3d 4f 39 02 00 	lea    0x2394f(%rip),%rdi        # 1082bf0 <core_durable_error.verbs+0x2220>
 105f2a1:	48 89 de             	mov    %rbx,%rsi
 105f2a4:	e8 d7 5d fc ff       	call   1025080 <myl_core_trap>
 105f2a9:	48 8d 3d 60 61 02 00 	lea    0x26160(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x4a40>
 105f2b0:	e8 cb 5d fc ff       	call   1025080 <myl_core_trap>
 105f2b5:	48 89 ce             	mov    %rcx,%rsi
 105f2b8:	48 8d 3d 51 8e 02 00 	lea    0x28e51(%rip),%rdi        # 1088110 <core_durable_error.verbs+0x7740>
 105f2bf:	e8 bc 5d fc ff       	call   1025080 <myl_core_trap>
 105f2c4:	48 8d 3d d5 6a 02 00 	lea    0x26ad5(%rip),%rdi        # 1085da0 <core_durable_error.verbs+0x53d0>
 105f2cb:	48 89 c2             	mov    %rax,%rdx
 105f2ce:	e8 ad 5d fc ff       	call   1025080 <myl_core_trap>
 105f2d3:	48 8d 3d 76 60 02 00 	lea    0x26076(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x4980>
 105f2da:	4c 89 c6             	mov    %r8,%rsi
 105f2dd:	48 89 ca             	mov    %rcx,%rdx
 105f2e0:	e8 9b 5d fc ff       	call   1025080 <myl_core_trap>
 105f2e5:	48 8d 3d c4 42 02 00 	lea    0x242c4(%rip),%rdi        # 10835b0 <core_durable_error.verbs+0x2be0>
 105f2ec:	4c 89 ee             	mov    %r13,%rsi
 105f2ef:	e8 8c 5d fc ff       	call   1025080 <myl_core_trap>
 105f2f4:	48 8d 3d 25 39 02 00 	lea    0x23925(%rip),%rdi        # 1082c20 <core_durable_error.verbs+0x2250>
 105f2fb:	4c 89 ee             	mov    %r13,%rsi
 105f2fe:	e8 7d 5d fc ff       	call   1025080 <myl_core_trap>
 105f303:	48 8d 3d 76 42 02 00 	lea    0x24276(%rip),%rdi        # 1083580 <core_durable_error.verbs+0x2bb0>
 105f30a:	4c 89 ee             	mov    %r13,%rsi
 105f30d:	e8 6e 5d fc ff       	call   1025080 <myl_core_trap>
 105f312:	48 8d 3d 67 60 02 00 	lea    0x26067(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x49b0>
 105f319:	e8 62 5d fc ff       	call   1025080 <myl_core_trap>
 105f31e:	48 8d 3d 9b 59 02 00 	lea    0x2599b(%rip),%rdi        # 1084cc0 <core_durable_error.verbs+0x42f0>
 105f325:	48 89 ee             	mov    %rbp,%rsi
 105f328:	e8 53 5d fc ff       	call   1025080 <myl_core_trap>
 105f32d:	48 8d 3d 8c 35 02 00 	lea    0x2358c(%rip),%rdi        # 10828c0 <core_durable_error.verbs+0x1ef0>
 105f334:	e8 47 5d fc ff       	call   1025080 <myl_core_trap>
 105f339:	48 8d 3d c0 34 02 00 	lea    0x234c0(%rip),%rdi        # 1082800 <core_durable_error.verbs+0x1e30>
 105f340:	48 89 c2             	mov    %rax,%rdx
 105f343:	e8 38 5d fc ff       	call   1025080 <myl_core_trap>
 105f348:	48 89 fe             	mov    %rdi,%rsi
 105f34b:	48 8d 3d 6e 59 02 00 	lea    0x2596e(%rip),%rdi        # 1084cc0 <core_durable_error.verbs+0x42f0>
 105f352:	e8 29 5d fc ff       	call   1025080 <myl_core_trap>
 105f357:	48 89 fe             	mov    %rdi,%rsi
 105f35a:	48 8d 3d af 5d 02 00 	lea    0x25daf(%rip),%rdi        # 1085110 <core_durable_error.verbs+0x4740>
 105f361:	48 89 c2             	mov    %rax,%rdx
 105f364:	e8 17 5d fc ff       	call   1025080 <myl_core_trap>
 105f369:	48 8d 3d e0 35 02 00 	lea    0x235e0(%rip),%rdi        # 1082950 <core_durable_error.verbs+0x1f80>
 105f370:	e8 0b 5d fc ff       	call   1025080 <myl_core_trap>
 105f375:	48 8d 3d c4 36 02 00 	lea    0x236c4(%rip),%rdi        # 1082a40 <core_durable_error.verbs+0x2070>
 105f37c:	e8 ff 5c fc ff       	call   1025080 <myl_core_trap>
 105f381:	48 8d 3d 28 36 02 00 	lea    0x23628(%rip),%rdi        # 10829b0 <core_durable_error.verbs+0x1fe0>
 105f388:	48 89 c6             	mov    %rax,%rsi
 105f38b:	e8 f0 5c fc ff       	call   1025080 <myl_core_trap>
 105f390:	48 8d 3d 19 60 02 00 	lea    0x26019(%rip),%rdi        # 10853b0 <core_durable_error.verbs+0x49e0>
 105f397:	48 89 c6             	mov    %rax,%rsi
 105f39a:	e8 e1 5c fc ff       	call   1025080 <myl_core_trap>
 105f39f:	48 8d 3d aa 3b 02 00 	lea    0x23baa(%rip),%rdi        # 1082f50 <core_durable_error.verbs+0x2580>
 105f3a6:	4c 89 ee             	mov    %r13,%rsi
 105f3a9:	e8 d2 5c fc ff       	call   1025080 <myl_core_trap>
 105f3ae:	48 8d 3d 3b 35 02 00 	lea    0x2353b(%rip),%rdi        # 10828f0 <core_durable_error.verbs+0x1f20>
 105f3b5:	e8 c6 5c fc ff       	call   1025080 <myl_core_trap>
 105f3ba:	48 8d 3d 8f 5f 02 00 	lea    0x25f8f(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x4980>
 105f3c1:	48 89 c6             	mov    %rax,%rsi
 105f3c4:	48 89 ca             	mov    %rcx,%rdx
 105f3c7:	e8 b4 5c fc ff       	call   1025080 <myl_core_trap>
 105f3cc:	48 8d 3d ad 3e 02 00 	lea    0x23ead(%rip),%rdi        # 1083280 <core_durable_error.verbs+0x28b0>
 105f3d3:	48 89 c2             	mov    %rax,%rdx
 105f3d6:	e8 a5 5c fc ff       	call   1025080 <myl_core_trap>
 105f3db:	48 8d 3d de 58 02 00 	lea    0x258de(%rip),%rdi        # 1084cc0 <core_durable_error.verbs+0x42f0>
 105f3e2:	e8 99 5c fc ff       	call   1025080 <myl_core_trap>
 105f3e7:	48 8d 3d e2 69 02 00 	lea    0x269e2(%rip),%rdi        # 1085dd0 <core_durable_error.verbs+0x5400>
 105f3ee:	e8 8d 5c fc ff       	call   1025080 <myl_core_trap>

Disassembly of section .plt:
