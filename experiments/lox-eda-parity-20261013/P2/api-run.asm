
.tmp/lox-eda-parity/P2/api:     file format elf64-x86-64


Disassembly of section .text:

000000000105b530 <my.vm::run>:
 105b530:	55                   	push   %rbp
 105b531:	41 57                	push   %r15
 105b533:	41 56                	push   %r14
 105b535:	41 55                	push   %r13
 105b537:	41 54                	push   %r12
 105b539:	53                   	push   %rbx
 105b53a:	48 81 ec f8 09 00 00 	sub    $0x9f8,%rsp
 105b541:	48 89 8c 24 90 00 00 	mov    %rcx,0x90(%rsp)
 105b548:	00 
 105b549:	48 89 54 24 40       	mov    %rdx,0x40(%rsp)
 105b54e:	49 89 f6             	mov    %rsi,%r14
 105b551:	48 89 7c 24 48       	mov    %rdi,0x48(%rsp)
 105b556:	48 8b ae 90 00 00 00 	mov    0x90(%rsi),%rbp
 105b55d:	48 89 ee             	mov    %rbp,%rsi
 105b560:	48 ff ce             	dec    %rsi
 105b563:	0f 80 3d 38 00 00    	jo     105eda6 <my.vm::run+0x3876>
 105b569:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105b570:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105b577:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b57b:	48 39 d6             	cmp    %rdx,%rsi
 105b57e:	0f 83 96 30 00 00    	jae    105e61a <my.vm::run+0x30ea>
 105b584:	48 89 f1             	mov    %rsi,%rcx
 105b587:	48 c1 e1 05          	shl    $0x5,%rcx
 105b58b:	4c 8b 5c 08 20       	mov    0x20(%rax,%rcx,1),%r11
 105b590:	4c 8b 64 08 28       	mov    0x28(%rax,%rcx,1),%r12
 105b595:	4c 8b 44 08 30       	mov    0x30(%rax,%rcx,1),%r8
 105b59a:	4c 8b 4c 08 38       	mov    0x38(%rax,%rcx,1),%r9
 105b59f:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105b5a4:	4c 89 b4 24 98 00 00 	mov    %r14,0x98(%rsp)
 105b5ab:	00 
 105b5ac:	0f 1f 40 00          	nopl   0x0(%rax)
 105b5b0:	48 89 df             	mov    %rbx,%rdi
 105b5b3:	4c 89 f6             	mov    %r14,%rsi
 105b5b6:	4c 89 da             	mov    %r11,%rdx
 105b5b9:	4c 89 e1             	mov    %r12,%rcx
 105b5bc:	e8 bf 85 00 00       	call   1063b80 <my.vm::read_byte>
 105b5c1:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105b5c8:	49 89 ea             	mov    %rbp,%r10
 105b5cb:	4c 8d 6d ff          	lea    -0x1(%rbp),%r13
 105b5cf:	4c 89 ea             	mov    %r13,%rdx
 105b5d2:	48 85 ed             	test   %rbp,%rbp
 105b5d5:	7f 07                	jg     105b5de <my.vm::run+0xae>
 105b5d7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b5db:	4c 01 ea             	add    %r13,%rdx
 105b5de:	48 8b 4c 24 60       	mov    0x60(%rsp),%rcx
 105b5e3:	4c 8b 5c 24 68       	mov    0x68(%rsp),%r11
 105b5e8:	4c 8b 64 24 70       	mov    0x70(%rsp),%r12
 105b5ed:	4c 8b 44 24 78       	mov    0x78(%rsp),%r8
 105b5f2:	4c 8b 8c 24 80 00 00 	mov    0x80(%rsp),%r9
 105b5f9:	00 
 105b5fa:	48 c1 e2 05          	shl    $0x5,%rdx
 105b5fe:	4c 89 5c 10 20       	mov    %r11,0x20(%rax,%rdx,1)
 105b603:	4c 89 64 10 28       	mov    %r12,0x28(%rax,%rdx,1)
 105b608:	4c 89 44 10 30       	mov    %r8,0x30(%rax,%rdx,1)
 105b60d:	4c 89 4c 10 38       	mov    %r9,0x38(%rax,%rdx,1)
 105b612:	49 89 86 88 00 00 00 	mov    %rax,0x88(%r14)
 105b619:	48 83 f9 24          	cmp    $0x24,%rcx
 105b61d:	0f 87 cd 26 00 00    	ja     105dcf0 <my.vm::run+0x27c0>
 105b623:	48 8d 15 82 bd fa ff 	lea    -0x5427e(%rip),%rdx        # 10073ac <core_number_pairs+0x14c>
 105b62a:	48 63 04 8a          	movslq (%rdx,%rcx,4),%rax
 105b62e:	48 01 d0             	add    %rdx,%rax
 105b631:	ff e0                	jmp    *%rax
 105b633:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105b63a:	48 89 c6             	mov    %rax,%rsi
 105b63d:	48 ff ce             	dec    %rsi
 105b640:	0f 80 79 30 00 00    	jo     105e6bf <my.vm::run+0x318f>
 105b646:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b64a:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b64e:	48 89 f7             	mov    %rsi,%rdi
 105b651:	48 39 d6             	cmp    %rdx,%rsi
 105b654:	0f 83 b0 27 00 00    	jae    105de0a <my.vm::run+0x28da>
 105b65a:	48 c1 e7 04          	shl    $0x4,%rdi
 105b65e:	80 7c 38 20 02       	cmpb   $0x2,0x20(%rax,%rdi,1)
 105b663:	75 5b                	jne    105b6c0 <my.vm::run+0x190>
 105b665:	49 89 f7             	mov    %rsi,%r15
 105b668:	49 ff cf             	dec    %r15
 105b66b:	0f 80 be 31 00 00    	jo     105e82f <my.vm::run+0x32ff>
 105b671:	c5 fb 10 44 38 28    	vmovsd 0x28(%rax,%rdi,1),%xmm0
 105b677:	4c 89 fe             	mov    %r15,%rsi
 105b67a:	49 39 d7             	cmp    %rdx,%r15
 105b67d:	0f 83 a2 27 00 00    	jae    105de25 <my.vm::run+0x28f5>
 105b683:	48 83 c0 20          	add    $0x20,%rax
 105b687:	48 c1 e6 04          	shl    $0x4,%rsi
 105b68b:	80 3c 30 02          	cmpb   $0x2,(%rax,%rsi,1)
 105b68f:	75 2f                	jne    105b6c0 <my.vm::run+0x190>
 105b691:	48 01 f0             	add    %rsi,%rax
 105b694:	c5 fb 10 48 08       	vmovsd 0x8(%rax),%xmm1
 105b699:	48 83 c1 f0          	add    $0xfffffffffffffff0,%rcx
 105b69d:	48 83 f9 04          	cmp    $0x4,%rcx
 105b6a1:	0f 87 d0 24 00 00    	ja     105db77 <my.vm::run+0x2647>
 105b6a7:	48 8d 15 de bd fa ff 	lea    -0x54222(%rip),%rdx        # 100748c <core_number_pairs+0x22c>
 105b6ae:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 105b6b2:	48 01 d1             	add    %rdx,%rcx
 105b6b5:	ff e1                	jmp    *%rcx
 105b6b7:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 105b6bb:	e9 a4 24 00 00       	jmp    105db64 <my.vm::run+0x2634>
 105b6c0:	4c 89 dd             	mov    %r11,%rbp
 105b6c3:	4c 89 c3             	mov    %r8,%rbx
 105b6c6:	4d 89 cd             	mov    %r9,%r13
 105b6c9:	48 8d 0d 10 75 fb ff 	lea    -0x48af0(%rip),%rcx        # 1012be0 <core_number_pairs+0xb980>
 105b6d0:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105b6d7:	00 
 105b6d8:	4c 89 f6             	mov    %r14,%rsi
 105b6db:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105b6e0:	e8 1b 80 00 00       	call   1063700 <my.vm::runtime_error>
 105b6e5:	f6 84 24 a0 00 00 00 	testb  $0x1,0xa0(%rsp)
 105b6ec:	01 
 105b6ed:	0f 84 dd 2e 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105b6f3:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105b6fa:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105b701:	4d 89 e9             	mov    %r13,%r9
 105b704:	49 89 d8             	mov    %rbx,%r8
 105b707:	49 89 eb             	mov    %rbp,%r11
 105b70a:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105b70f:	e9 dc 25 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105b714:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105b71b:	48 89 f0             	mov    %rsi,%rax
 105b71e:	48 ff c8             	dec    %rax
 105b721:	0f 80 fc 32 00 00    	jo     105ea23 <my.vm::run+0x34f3>
 105b727:	48 89 c6             	mov    %rax,%rsi
 105b72a:	48 ff ce             	dec    %rsi
 105b72d:	0f 80 0c 32 00 00    	jo     105e93f <my.vm::run+0x340f>
 105b733:	4d 8b 6e 78          	mov    0x78(%r14),%r13
 105b737:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105b73b:	48 39 d6             	cmp    %rdx,%rsi
 105b73e:	48 89 44 24 38       	mov    %rax,0x38(%rsp)
 105b743:	0f 83 b9 28 00 00    	jae    105e002 <my.vm::run+0x2ad2>
 105b749:	48 89 f0             	mov    %rsi,%rax
 105b74c:	48 c1 e0 04          	shl    $0x4,%rax
 105b750:	41 80 7c 05 20 03    	cmpb   $0x3,0x20(%r13,%rax,1)
 105b756:	0f 85 f6 1e 00 00    	jne    105d652 <my.vm::run+0x2122>
 105b75c:	49 8b 74 05 28       	mov    0x28(%r13,%rax,1),%rsi
 105b761:	4d 8b 3e             	mov    (%r14),%r15
 105b764:	49 8b 47 08          	mov    0x8(%r15),%rax
 105b768:	48 89 f1             	mov    %rsi,%rcx
 105b76b:	48 39 c6             	cmp    %rax,%rsi
 105b76e:	0f 83 a6 2b 00 00    	jae    105e31a <my.vm::run+0x2dea>
 105b774:	48 6b c1 38          	imul   $0x38,%rcx,%rax
 105b778:	41 83 7c 07 20 06    	cmpl   $0x6,0x20(%r15,%rax,1)
 105b77e:	0f 85 ce 1e 00 00    	jne    105d652 <my.vm::run+0x2122>
 105b784:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 105b789:	48 89 c8             	mov    %rcx,%rax
 105b78c:	48 39 d1             	cmp    %rdx,%rcx
 105b78f:	0f 83 5d 2c 00 00    	jae    105e3f2 <my.vm::run+0x2ec2>
 105b795:	4c 89 5c 24 08       	mov    %r11,0x8(%rsp)
 105b79a:	4c 89 44 24 20       	mov    %r8,0x20(%rsp)
 105b79f:	4c 89 4c 24 18       	mov    %r9,0x18(%rsp)
 105b7a4:	49 8d 55 20          	lea    0x20(%r13),%rdx
 105b7a8:	48 c1 e0 04          	shl    $0x4,%rax
 105b7ac:	0f b6 0c 02          	movzbl (%rdx,%rax,1),%ecx
 105b7b0:	83 f9 03             	cmp    $0x3,%ecx
 105b7b3:	0f 85 6e 35 00 00    	jne    105ed27 <my.vm::run+0x37f7>
 105b7b9:	4c 89 64 24 10       	mov    %r12,0x10(%rsp)
 105b7be:	48 8b 6c 02 08       	mov    0x8(%rdx,%rax,1),%rbp
 105b7c3:	4c 89 f7             	mov    %r14,%rdi
 105b7c6:	e8 75 14 01 00       	call   106cc40 <my.heap::class_obj>
 105b7cb:	49 89 d4             	mov    %rdx,%r12
 105b7ce:	4c 89 f7             	mov    %r14,%rdi
 105b7d1:	48 89 ee             	mov    %rbp,%rsi
 105b7d4:	e8 67 14 01 00       	call   106cc40 <my.heap::class_obj>
 105b7d9:	49 8b 5c 24 08       	mov    0x8(%r12),%rbx
 105b7de:	48 85 db             	test   %rbx,%rbx
 105b7e1:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
 105b7e6:	4c 89 64 24 58       	mov    %r12,0x58(%rsp)
 105b7eb:	0f 84 ac 23 00 00    	je     105db9d <my.vm::run+0x266d>
 105b7f1:	49 83 c4 38          	add    $0x38,%r12
 105b7f5:	eb 16                	jmp    105b80d <my.vm::run+0x2dd>
 105b7f7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 105b7fe:	00 00 
 105b800:	49 83 c4 20          	add    $0x20,%r12
 105b804:	48 ff cb             	dec    %rbx
 105b807:	0f 84 90 23 00 00    	je     105db9d <my.vm::run+0x266d>
 105b80d:	49 8b 44 24 e8       	mov    -0x18(%r12),%rax
 105b812:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 105b816:	74 e8                	je     105b800 <my.vm::run+0x2d0>
 105b818:	4d 8b 0c 24          	mov    (%r12),%r9
 105b81c:	45 8b 54 24 f0       	mov    -0x10(%r12),%r10d
 105b821:	45 8b 44 24 f8       	mov    -0x8(%r12),%r8d
 105b826:	48 89 d7             	mov    %rdx,%rdi
 105b829:	48 89 ce             	mov    %rcx,%rsi
 105b82c:	48 89 c2             	mov    %rax,%rdx
 105b82f:	44 89 d1             	mov    %r10d,%ecx
 105b832:	e8 89 ef 00 00       	call   106a7c0 <my.table::set>
 105b837:	eb c7                	jmp    105b800 <my.vm::run+0x2d0>
 105b839:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105b840:	00 
 105b841:	4c 89 f6             	mov    %r14,%rsi
 105b844:	4c 89 da             	mov    %r11,%rdx
 105b847:	4c 89 e1             	mov    %r12,%rcx
 105b84a:	e8 f1 83 00 00       	call   1063c40 <my.vm::read_constant>
 105b84f:	0f b6 84 24 a0 00 00 	movzbl 0xa0(%rsp),%eax
 105b856:	00 
 105b857:	83 f8 03             	cmp    $0x3,%eax
 105b85a:	0f 85 e7 2e 00 00    	jne    105e747 <my.vm::run+0x3217>
 105b860:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105b867:	49 89 f2             	mov    %rsi,%r10
 105b86a:	49 ff ca             	dec    %r10
 105b86d:	0f 80 35 33 00 00    	jo     105eba8 <my.vm::run+0x3678>
 105b873:	4c 89 d6             	mov    %r10,%rsi
 105b876:	48 ff ce             	dec    %rsi
 105b879:	0f 80 4e 33 00 00    	jo     105ebcd <my.vm::run+0x369d>
 105b87f:	48 8b 8c 24 c8 00 00 	mov    0xc8(%rsp),%rcx
 105b886:	00 
 105b887:	48 8b bc 24 c0 00 00 	mov    0xc0(%rsp),%rdi
 105b88e:	00 
 105b88f:	4c 8b 84 24 b8 00 00 	mov    0xb8(%rsp),%r8
 105b896:	00 
 105b897:	4c 8b 9c 24 a8 00 00 	mov    0xa8(%rsp),%r11
 105b89e:	00 
 105b89f:	4c 8b 8c 24 b0 00 00 	mov    0xb0(%rsp),%r9
 105b8a6:	00 
 105b8a7:	4d 8b 6e 78          	mov    0x78(%r14),%r13
 105b8ab:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105b8af:	48 39 d6             	cmp    %rdx,%rsi
 105b8b2:	0f 83 b8 28 00 00    	jae    105e170 <my.vm::run+0x2c40>
 105b8b8:	48 89 f0             	mov    %rsi,%rax
 105b8bb:	4c 89 54 24 38       	mov    %r10,0x38(%rsp)
 105b8c0:	4c 89 4c 24 08       	mov    %r9,0x8(%rsp)
 105b8c5:	48 89 7c 24 20       	mov    %rdi,0x20(%rsp)
 105b8ca:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 105b8cf:	48 c1 e0 04          	shl    $0x4,%rax
 105b8d3:	41 0f b6 4c 05 20    	movzbl 0x20(%r13,%rax,1),%ecx
 105b8d9:	83 f9 03             	cmp    $0x3,%ecx
 105b8dc:	0f 85 9f 2e 00 00    	jne    105e781 <my.vm::run+0x3251>
 105b8e2:	4c 89 44 24 10       	mov    %r8,0x10(%rsp)
 105b8e7:	4d 8b 7c 05 28       	mov    0x28(%r13,%rax,1),%r15
 105b8ec:	4c 89 f7             	mov    %r14,%rdi
 105b8ef:	4c 89 de             	mov    %r11,%rsi
 105b8f2:	4c 89 5c 24 58       	mov    %r11,0x58(%rsp)
 105b8f7:	e8 e4 ed 00 00       	call   106a6e0 <my.heap::string_hash>
 105b8fc:	89 c5                	mov    %eax,%ebp
 105b8fe:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105b902:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 105b907:	48 89 c8             	mov    %rcx,%rax
 105b90a:	48 39 d1             	cmp    %rdx,%rcx
 105b90d:	0f 83 b3 28 00 00    	jae    105e1c6 <my.vm::run+0x2c96>
 105b913:	49 8d 4d 20          	lea    0x20(%r13),%rcx
 105b917:	48 c1 e0 04          	shl    $0x4,%rax
 105b91b:	4c 8b 64 01 08       	mov    0x8(%rcx,%rax,1),%r12
 105b920:	8b 1c 01             	mov    (%rcx,%rax,1),%ebx
 105b923:	4c 89 f7             	mov    %r14,%rdi
 105b926:	4c 89 fe             	mov    %r15,%rsi
 105b929:	e8 12 13 01 00       	call   106cc40 <my.heap::class_obj>
 105b92e:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
 105b933:	48 89 d7             	mov    %rdx,%rdi
 105b936:	48 89 ce             	mov    %rcx,%rsi
 105b939:	48 8b 54 24 58       	mov    0x58(%rsp),%rdx
 105b93e:	89 e9                	mov    %ebp,%ecx
 105b940:	41 89 d8             	mov    %ebx,%r8d
 105b943:	4d 89 e1             	mov    %r12,%r9
 105b946:	e8 75 ee 00 00       	call   106a7c0 <my.table::set>
 105b94b:	49 8b 36             	mov    (%r14),%rsi
 105b94e:	48 8b 46 08          	mov    0x8(%rsi),%rax
 105b952:	49 39 c7             	cmp    %rax,%r15
 105b955:	0f 83 8b 28 00 00    	jae    105e1e6 <my.vm::run+0x2cb6>
 105b95b:	4c 89 ff             	mov    %r15,%rdi
 105b95e:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105b963:	4c 6b d7 38          	imul   $0x38,%rdi,%r10
 105b967:	46 0f b6 44 16 20    	movzbl 0x20(%rsi,%r10,1),%r8d
 105b96d:	4a 8b 7c 16 28       	mov    0x28(%rsi,%r10,1),%rdi
 105b972:	4e 8b 4c 16 30       	mov    0x30(%rsi,%r10,1),%r9
 105b977:	4a 8b 44 16 38       	mov    0x38(%rsi,%r10,1),%rax
 105b97c:	4a 8b 5c 16 40       	mov    0x40(%rsi,%r10,1),%rbx
 105b981:	4e 8b 7c 16 48       	mov    0x48(%rsi,%r10,1),%r15
 105b986:	4a c7 44 16 20 06 00 	movq   $0x6,0x20(%rsi,%r10,1)
 105b98d:	00 00 
 105b98f:	4c 8b 64 24 50       	mov    0x50(%rsp),%r12
 105b994:	4e 89 64 16 28       	mov    %r12,0x28(%rsi,%r10,1)
 105b999:	4a 89 54 16 30       	mov    %rdx,0x30(%rsi,%r10,1)
 105b99e:	4a 89 4c 16 38       	mov    %rcx,0x38(%rsi,%r10,1)
 105b9a3:	41 83 f8 09          	cmp    $0x9,%r8d
 105b9a7:	4c 8b 64 24 10       	mov    0x10(%rsp),%r12
 105b9ac:	77 1c                	ja     105b9ca <my.vm::run+0x49a>
 105b9ae:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105b9b3:	44 0f a3 c1          	bt     %r8d,%ecx
 105b9b7:	0f 83 d4 1f 00 00    	jae    105d991 <my.vm::run+0x2461>
 105b9bd:	4c 89 cf             	mov    %r9,%rdi
 105b9c0:	e8 3b 89 fc ff       	call   1024300 <myl_core_drop_owned>
 105b9c5:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105b9ca:	4c 8b 7c 24 38       	mov    0x38(%rsp),%r15
 105b9cf:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105b9d6:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105b9da:	49 39 d7             	cmp    %rdx,%r15
 105b9dd:	0f 83 23 28 00 00    	jae    105e206 <my.vm::run+0x2cd6>
 105b9e3:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105b9ea:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105b9ef:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105b9f4:	e9 53 1e 00 00       	jmp    105d84c <my.vm::run+0x231c>
 105b9f9:	48 8d bc 24 08 02 00 	lea    0x208(%rsp),%rdi
 105ba00:	00 
 105ba01:	4c 89 f6             	mov    %r14,%rsi
 105ba04:	4c 89 da             	mov    %r11,%rdx
 105ba07:	4c 89 e1             	mov    %r12,%rcx
 105ba0a:	e8 f1 87 00 00       	call   1064200 <my.vm::read_short>
 105ba0f:	4c 89 fe             	mov    %r15,%rsi
 105ba12:	48 ff ce             	dec    %rsi
 105ba15:	0f 80 9c 30 00 00    	jo     105eab7 <my.vm::run+0x3587>
 105ba1b:	48 8b 94 24 08 02 00 	mov    0x208(%rsp),%rdx
 105ba22:	00 
 105ba23:	4c 8b 9c 24 10 02 00 	mov    0x210(%rsp),%r11
 105ba2a:	00 
 105ba2b:	4c 8b a4 24 18 02 00 	mov    0x218(%rsp),%r12
 105ba32:	00 
 105ba33:	4c 8b 84 24 20 02 00 	mov    0x220(%rsp),%r8
 105ba3a:	00 
 105ba3b:	4c 8b 8c 24 28 02 00 	mov    0x228(%rsp),%r9
 105ba42:	00 
 105ba43:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105ba47:	48 8b 41 08          	mov    0x8(%rcx),%rax
 105ba4b:	48 39 c6             	cmp    %rax,%rsi
 105ba4e:	0f 83 58 24 00 00    	jae    105deac <my.vm::run+0x297c>
 105ba54:	48 89 f7             	mov    %rsi,%rdi
 105ba57:	49 89 ea             	mov    %rbp,%r10
 105ba5a:	48 c1 e7 04          	shl    $0x4,%rdi
 105ba5e:	0f b6 44 39 20       	movzbl 0x20(%rcx,%rdi,1),%eax
 105ba63:	85 c0                	test   %eax,%eax
 105ba65:	74 1b                	je     105ba82 <my.vm::run+0x552>
 105ba67:	83 f8 01             	cmp    $0x1,%eax
 105ba6a:	0f 85 80 22 00 00    	jne    105dcf0 <my.vm::run+0x27c0>
 105ba70:	48 8d 04 39          	lea    (%rcx,%rdi,1),%rax
 105ba74:	48 83 c0 20          	add    $0x20,%rax
 105ba78:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105ba7c:	0f 85 6e 22 00 00    	jne    105dcf0 <my.vm::run+0x27c0>
 105ba82:	4c 89 c0             	mov    %r8,%rax
 105ba85:	48 01 d0             	add    %rdx,%rax
 105ba88:	0f 80 f8 32 00 00    	jo     105ed86 <my.vm::run+0x3856>
 105ba8e:	49 89 c0             	mov    %rax,%r8
 105ba91:	e9 5a 22 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105ba96:	48 8d bc 24 e0 01 00 	lea    0x1e0(%rsp),%rdi
 105ba9d:	00 
 105ba9e:	4c 89 f6             	mov    %r14,%rsi
 105baa1:	4c 89 da             	mov    %r11,%rdx
 105baa4:	4c 89 e1             	mov    %r12,%rcx
 105baa7:	e8 54 87 00 00       	call   1064200 <my.vm::read_short>
 105baac:	48 8b 94 24 e0 01 00 	mov    0x1e0(%rsp),%rdx
 105bab3:	00 
 105bab4:	48 8b b4 24 f8 01 00 	mov    0x1f8(%rsp),%rsi
 105babb:	00 
 105babc:	49 89 f0             	mov    %rsi,%r8
 105babf:	49 29 d0             	sub    %rdx,%r8
 105bac2:	0f 80 73 30 00 00    	jo     105eb3b <my.vm::run+0x360b>
 105bac8:	4c 8b 9c 24 e8 01 00 	mov    0x1e8(%rsp),%r11
 105bacf:	00 
 105bad0:	4c 8b a4 24 f0 01 00 	mov    0x1f0(%rsp),%r12
 105bad7:	00 
 105bad8:	4c 8b 8c 24 00 02 00 	mov    0x200(%rsp),%r9
 105badf:	00 
 105bae0:	49 89 ea             	mov    %rbp,%r10
 105bae3:	e9 08 22 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105bae8:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105baef:	00 
 105baf0:	4c 89 f6             	mov    %r14,%rsi
 105baf3:	4c 89 da             	mov    %r11,%rdx
 105baf6:	4c 89 e1             	mov    %r12,%rcx
 105baf9:	e8 42 81 00 00       	call   1063c40 <my.vm::read_constant>
 105bafe:	0f b6 84 24 a0 00 00 	movzbl 0xa0(%rsp),%eax
 105bb05:	00 
 105bb06:	83 f8 03             	cmp    $0x3,%eax
 105bb09:	0f 85 c4 2b 00 00    	jne    105e6d3 <my.vm::run+0x31a3>
 105bb0f:	48 8b 84 24 c8 00 00 	mov    0xc8(%rsp),%rax
 105bb16:	00 
 105bb17:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105bb1c:	48 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%rax
 105bb23:	00 
 105bb24:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105bb29:	48 8b 84 24 b8 00 00 	mov    0xb8(%rsp),%rax
 105bb30:	00 
 105bb31:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105bb36:	4c 8b a4 24 a8 00 00 	mov    0xa8(%rsp),%r12
 105bb3d:	00 
 105bb3e:	48 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%rbp
 105bb45:	00 
 105bb46:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105bb4d:	00 
 105bb4e:	ba 30 00 00 00       	mov    $0x30,%edx
 105bb53:	4c 89 f6             	mov    %r14,%rsi
 105bb56:	e8 f5 65 00 00       	call   1062150 <my.heap::reserve_object>
 105bb5b:	4c 8b bc 24 a0 00 00 	mov    0xa0(%rsp),%r15
 105bb62:	00 
 105bb63:	64 48 8b 04 25 c8 fe 	mov    %fs:0xfffffffffffffec8,%rax
 105bb6a:	ff ff 
 105bb6c:	48 85 c0             	test   %rax,%rax
 105bb6f:	0f 84 39 25 00 00    	je     105e0ae <my.vm::run+0x2b7e>
 105bb75:	48 8b 08             	mov    (%rax),%rcx
 105bb78:	64 48 89 0c 25 c8 fe 	mov    %rcx,%fs:0xfffffffffffffec8
 105bb7f:	ff ff 
 105bb81:	c7 00 00 00 00 01    	movl   $0x1000000,(%rax)
 105bb87:	c5 f9 57 c0          	vxorpd %xmm0,%xmm0,%xmm0
 105bb8b:	c5 f9 11 40 08       	vmovupd %xmm0,0x8(%rax)
 105bb90:	48 c7 40 18 00 00 00 	movq   $0x0,0x18(%rax)
 105bb97:	00 
 105bb98:	49 8b 36             	mov    (%r14),%rsi
 105bb9b:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105bb9f:	4c 89 f9             	mov    %r15,%rcx
 105bba2:	49 39 d7             	cmp    %rdx,%r15
 105bba5:	49 89 eb             	mov    %rbp,%r11
 105bba8:	0f 83 11 25 00 00    	jae    105e0bf <my.vm::run+0x2b8f>
 105bbae:	4c 6b c9 38          	imul   $0x38,%rcx,%r9
 105bbb2:	42 0f b6 54 0e 20    	movzbl 0x20(%rsi,%r9,1),%edx
 105bbb8:	4a 8b 7c 0e 28       	mov    0x28(%rsi,%r9,1),%rdi
 105bbbd:	4e 8b 44 0e 30       	mov    0x30(%rsi,%r9,1),%r8
 105bbc2:	4a 8b 4c 0e 38       	mov    0x38(%rsi,%r9,1),%rcx
 105bbc7:	4a 8b 5c 0e 40       	mov    0x40(%rsi,%r9,1),%rbx
 105bbcc:	4e 8b 6c 0e 48       	mov    0x48(%rsi,%r9,1),%r13
 105bbd1:	4a c7 44 0e 20 06 00 	movq   $0x6,0x20(%rsi,%r9,1)
 105bbd8:	00 00 
 105bbda:	4e 89 64 0e 28       	mov    %r12,0x28(%rsi,%r9,1)
 105bbdf:	4a 89 44 0e 30       	mov    %rax,0x30(%rsi,%r9,1)
 105bbe4:	4a c7 44 0e 38 00 00 	movq   $0x0,0x38(%rsi,%r9,1)
 105bbeb:	00 00 
 105bbed:	83 fa 09             	cmp    $0x9,%edx
 105bbf0:	4c 8b 64 24 10       	mov    0x10(%rsp),%r12
 105bbf5:	77 19                	ja     105bc10 <my.vm::run+0x6e0>
 105bbf7:	b8 d0 02 00 00       	mov    $0x2d0,%eax
 105bbfc:	0f a3 d0             	bt     %edx,%eax
 105bbff:	0f 83 62 1d 00 00    	jae    105d967 <my.vm::run+0x2437>
 105bc05:	4c 89 c7             	mov    %r8,%rdi
 105bc08:	e8 f3 86 fc ff       	call   1024300 <myl_core_drop_owned>
 105bc0d:	49 89 eb             	mov    %rbp,%r11
 105bc10:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bc14:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105bc1b:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bc1f:	48 39 d6             	cmp    %rdx,%rsi
 105bc22:	0f 83 b2 24 00 00    	jae    105e0da <my.vm::run+0x2baa>
 105bc28:	48 89 f1             	mov    %rsi,%rcx
 105bc2b:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105bc30:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105bc35:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105bc3a:	48 c1 e1 04          	shl    $0x4,%rcx
 105bc3e:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 105bc45:	00 00 
 105bc47:	4c 89 7c 08 28       	mov    %r15,0x28(%rax,%rcx,1)
 105bc4c:	49 89 46 78          	mov    %rax,0x78(%r14)
 105bc50:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105bc57:	49 89 f7             	mov    %rsi,%r15
 105bc5a:	49 ff c7             	inc    %r15
 105bc5d:	0f 81 27 1f 00 00    	jno    105db8a <my.vm::run+0x265a>
 105bc63:	e9 2e 30 00 00       	jmp    105ec96 <my.vm::run+0x3766>
 105bc68:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105bc6f:	00 
 105bc70:	4c 89 f6             	mov    %r14,%rsi
 105bc73:	4c 89 da             	mov    %r11,%rdx
 105bc76:	4c 89 e1             	mov    %r12,%rcx
 105bc79:	e8 c2 7f 00 00       	call   1063c40 <my.vm::read_constant>
 105bc7e:	0f b6 84 24 a0 00 00 	movzbl 0xa0(%rsp),%eax
 105bc85:	00 
 105bc86:	83 f8 03             	cmp    $0x3,%eax
 105bc89:	0f 85 83 2b 00 00    	jne    105e812 <my.vm::run+0x32e2>
 105bc8f:	4c 89 fe             	mov    %r15,%rsi
 105bc92:	48 ff ce             	dec    %rsi
 105bc95:	0f 80 e7 2f 00 00    	jo     105ec82 <my.vm::run+0x3752>
 105bc9b:	48 89 dd             	mov    %rbx,%rbp
 105bc9e:	4c 8b ac 24 c8 00 00 	mov    0xc8(%rsp),%r13
 105bca5:	00 
 105bca6:	48 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%rax
 105bcad:	00 
 105bcae:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105bcb3:	4c 8b a4 24 b8 00 00 	mov    0xb8(%rsp),%r12
 105bcba:	00 
 105bcbb:	4c 8b 84 24 a8 00 00 	mov    0xa8(%rsp),%r8
 105bcc2:	00 
 105bcc3:	48 8b 9c 24 b0 00 00 	mov    0xb0(%rsp),%rbx
 105bcca:	00 
 105bccb:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105bcd2:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bcd6:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bcda:	48 39 d6             	cmp    %rdx,%rsi
 105bcdd:	0f 83 3c 24 00 00    	jae    105e11f <my.vm::run+0x2bef>
 105bce3:	48 89 f1             	mov    %rsi,%rcx
 105bce6:	48 c1 e1 04          	shl    $0x4,%rcx
 105bcea:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 105bcef:	83 fa 03             	cmp    $0x3,%edx
 105bcf2:	0f 85 c3 2a 00 00    	jne    105e7bb <my.vm::run+0x328b>
 105bcf8:	48 01 c8             	add    %rcx,%rax
 105bcfb:	48 83 c0 20          	add    $0x20,%rax
 105bcff:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105bd03:	48 8d bc 24 08 09 00 	lea    0x908(%rsp),%rdi
 105bd0a:	00 
 105bd0b:	4c 89 f6             	mov    %r14,%rsi
 105bd0e:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105bd13:	e8 08 80 00 00       	call   1063d20 <my.vm::bind_method>
 105bd18:	f6 84 24 08 09 00 00 	testb  $0x1,0x908(%rsp)
 105bd1f:	01 
 105bd20:	0f 84 aa 28 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105bd26:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105bd2d:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105bd34:	4d 89 e9             	mov    %r13,%r9
 105bd37:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105bd3c:	49 89 db             	mov    %rbx,%r11
 105bd3f:	48 89 eb             	mov    %rbp,%rbx
 105bd42:	e9 a9 1f 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105bd47:	4c 89 fe             	mov    %r15,%rsi
 105bd4a:	48 ff ce             	dec    %rsi
 105bd4d:	0f 80 d1 2e 00 00    	jo     105ec24 <my.vm::run+0x36f4>
 105bd53:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105bd5a:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bd5e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bd62:	48 39 d6             	cmp    %rdx,%rsi
 105bd65:	0f 83 5f 21 00 00    	jae    105deca <my.vm::run+0x299a>
 105bd6b:	48 89 f1             	mov    %rsi,%rcx
 105bd6e:	48 c1 e1 04          	shl    $0x4,%rcx
 105bd72:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105bd78:	c5 f9 29 44 24 20    	vmovapd %xmm0,0x20(%rsp)
 105bd7e:	4c 89 f7             	mov    %r14,%rdi
 105bd81:	4d 89 cf             	mov    %r9,%r15
 105bd84:	4c 89 ce             	mov    %r9,%rsi
 105bd87:	e8 24 8e 00 00       	call   1064bb0 <my.vm::close_upvalues>
 105bd8c:	49 8b b6 90 00 00 00 	mov    0x90(%r14),%rsi
 105bd93:	49 89 f2             	mov    %rsi,%r10
 105bd96:	49 ff ca             	dec    %r10
 105bd99:	0f 80 a8 2d 00 00    	jo     105eb47 <my.vm::run+0x3617>
 105bd9f:	4d 89 96 90 00 00 00 	mov    %r10,0x90(%r14)
 105bda6:	0f 84 43 28 00 00    	je     105e5ef <my.vm::run+0x30bf>
 105bdac:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105bdb3:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bdb7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bdbb:	4c 89 f9             	mov    %r15,%rcx
 105bdbe:	49 39 d7             	cmp    %rdx,%r15
 105bdc1:	0f 83 90 24 00 00    	jae    105e257 <my.vm::run+0x2d27>
 105bdc7:	48 c1 e1 04          	shl    $0x4,%rcx
 105bdcb:	c5 f9 28 44 24 20    	vmovapd 0x20(%rsp),%xmm0
 105bdd1:	c5 f9 54 05 07 86 fa 	vandpd -0x579f9(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105bdd8:	ff 
 105bdd9:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 105bddf:	49 89 46 78          	mov    %rax,0x78(%r14)
 105bde3:	49 ff c7             	inc    %r15
 105bde6:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105bded:	4c 89 d6             	mov    %r10,%rsi
 105bdf0:	48 ff ce             	dec    %rsi
 105bdf3:	0f 80 e6 2e 00 00    	jo     105ecdf <my.vm::run+0x37af>
 105bdf9:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105be00:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105be04:	48 39 d6             	cmp    %rdx,%rsi
 105be07:	0f 82 af 18 00 00    	jb     105d6bc <my.vm::run+0x218c>
 105be0d:	48 89 f1             	mov    %rsi,%rcx
 105be10:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105be14:	48 21 d1             	and    %rdx,%rcx
 105be17:	48 01 f1             	add    %rsi,%rcx
 105be1a:	48 39 d1             	cmp    %rdx,%rcx
 105be1d:	0f 82 9c 18 00 00    	jb     105d6bf <my.vm::run+0x218f>
 105be23:	e9 39 33 00 00       	jmp    105f161 <my.vm::run+0x3c31>
 105be28:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105be2f:	00 
 105be30:	4c 89 f6             	mov    %r14,%rsi
 105be33:	4c 89 da             	mov    %r11,%rdx
 105be36:	4c 89 e1             	mov    %r12,%rcx
 105be39:	e8 42 7d 00 00       	call   1063b80 <my.vm::read_byte>
 105be3e:	48 8b 94 24 a0 00 00 	mov    0xa0(%rsp),%rdx
 105be45:	00 
 105be46:	48 8b b4 24 a8 00 00 	mov    0xa8(%rsp),%rsi
 105be4d:	00 
 105be4e:	4c 8b a4 24 b0 00 00 	mov    0xb0(%rsp),%r12
 105be55:	00 
 105be56:	48 8b 84 24 b8 00 00 	mov    0xb8(%rsp),%rax
 105be5d:	00 
 105be5e:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105be63:	4c 8b ac 24 c0 00 00 	mov    0xc0(%rsp),%r13
 105be6a:	00 
 105be6b:	4c 89 f7             	mov    %r14,%rdi
 105be6e:	48 89 f5             	mov    %rsi,%rbp
 105be71:	e8 3a ed 00 00       	call   106abb0 <my.heap::closure_upvalue>
 105be76:	48 89 c3             	mov    %rax,%rbx
 105be79:	48 8d bc 24 40 03 00 	lea    0x340(%rsp),%rdi
 105be80:	00 
 105be81:	4c 89 f6             	mov    %r14,%rsi
 105be84:	48 89 c2             	mov    %rax,%rdx
 105be87:	e8 24 ec 00 00       	call   106aab0 <my.heap::upvalue_obj>
 105be8c:	48 8b 84 24 40 03 00 	mov    0x340(%rsp),%rax
 105be93:	00 
 105be94:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105be98:	49 8b 8e 80 00 00 00 	mov    0x80(%r14),%rcx
 105be9f:	48 89 ce             	mov    %rcx,%rsi
 105bea2:	48 ff ce             	dec    %rsi
 105bea5:	0f 90 c2             	seto   %dl
 105bea8:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 105beac:	0f 84 d9 18 00 00    	je     105d78b <my.vm::run+0x225b>
 105beb2:	84 d2                	test   %dl,%dl
 105beb4:	0f 85 a7 2e 00 00    	jne    105ed61 <my.vm::run+0x3831>
 105beba:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105bebe:	48 39 d6             	cmp    %rdx,%rsi
 105bec1:	4d 89 e9             	mov    %r13,%r9
 105bec4:	49 89 eb             	mov    %rbp,%r11
 105bec7:	0f 83 fc 23 00 00    	jae    105e2c9 <my.vm::run+0x2d99>
 105becd:	48 89 f1             	mov    %rsi,%rcx
 105bed0:	48 c1 e1 04          	shl    $0x4,%rcx
 105bed4:	c5 f9 10 44 0f 20    	vmovupd 0x20(%rdi,%rcx,1),%xmm0
 105beda:	48 39 d0             	cmp    %rdx,%rax
 105bedd:	0f 83 01 24 00 00    	jae    105e2e4 <my.vm::run+0x2db4>
 105bee3:	48 89 c1             	mov    %rax,%rcx
 105bee6:	48 83 c7 20          	add    $0x20,%rdi
 105beea:	48 c1 e1 04          	shl    $0x4,%rcx
 105beee:	c5 f9 54 05 ea 84 fa 	vandpd -0x57b16(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105bef5:	ff 
 105bef6:	c5 f9 11 04 0f       	vmovupd %xmm0,(%rdi,%rcx,1)
 105befb:	e9 39 19 00 00       	jmp    105d839 <my.vm::run+0x2309>
 105bf00:	4c 89 fe             	mov    %r15,%rsi
 105bf03:	48 ff ce             	dec    %rsi
 105bf06:	0f 80 4c 2c 00 00    	jo     105eb58 <my.vm::run+0x3628>
 105bf0c:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105bf13:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bf17:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bf1b:	48 39 d6             	cmp    %rdx,%rsi
 105bf1e:	0f 83 c1 1f 00 00    	jae    105dee5 <my.vm::run+0x29b5>
 105bf24:	49 89 f7             	mov    %rsi,%r15
 105bf27:	e9 c4 1d 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105bf2c:	4c 89 64 24 10       	mov    %r12,0x10(%rsp)
 105bf31:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105bf38:	49 89 f2             	mov    %rsi,%r10
 105bf3b:	49 ff ca             	dec    %r10
 105bf3e:	0f 80 04 2b 00 00    	jo     105ea48 <my.vm::run+0x3518>
 105bf44:	4d 8b 66 78          	mov    0x78(%r14),%r12
 105bf48:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 105bf4d:	4d 89 d5             	mov    %r10,%r13
 105bf50:	49 39 d2             	cmp    %rdx,%r10
 105bf53:	0f 83 a7 1f 00 00    	jae    105df00 <my.vm::run+0x29d0>
 105bf59:	49 c1 e5 04          	shl    $0x4,%r13
 105bf5d:	43 80 7c 2c 20 03    	cmpb   $0x3,0x20(%r12,%r13,1)
 105bf63:	0f 85 8b 16 00 00    	jne    105d5f4 <my.vm::run+0x20c4>
 105bf69:	4b 8b 5c 2c 28       	mov    0x28(%r12,%r13,1),%rbx
 105bf6e:	49 8b 06             	mov    (%r14),%rax
 105bf71:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bf75:	48 89 d9             	mov    %rbx,%rcx
 105bf78:	48 39 d3             	cmp    %rdx,%rbx
 105bf7b:	0f 83 7e 23 00 00    	jae    105e2ff <my.vm::run+0x2dcf>
 105bf81:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105bf85:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 105bf8a:	0f 85 64 16 00 00    	jne    105d5f4 <my.vm::run+0x20c4>
 105bf90:	4c 89 d5             	mov    %r10,%rbp
 105bf93:	48 8d bc 24 48 05 00 	lea    0x548(%rsp),%rdi
 105bf9a:	00 
 105bf9b:	4c 89 f6             	mov    %r14,%rsi
 105bf9e:	4c 89 da             	mov    %r11,%rdx
 105bfa1:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105bfa6:	e8 95 7c 00 00       	call   1063c40 <my.vm::read_constant>
 105bfab:	0f b6 84 24 48 05 00 	movzbl 0x548(%rsp),%eax
 105bfb2:	00 
 105bfb3:	83 f8 03             	cmp    $0x3,%eax
 105bfb6:	0f 85 88 2d 00 00    	jne    105ed44 <my.vm::run+0x3814>
 105bfbc:	48 8b 84 24 70 05 00 	mov    0x570(%rsp),%rax
 105bfc3:	00 
 105bfc4:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105bfc9:	48 8b 84 24 68 05 00 	mov    0x568(%rsp),%rax
 105bfd0:	00 
 105bfd1:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105bfd6:	48 8b 84 24 60 05 00 	mov    0x560(%rsp),%rax
 105bfdd:	00 
 105bfde:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105bfe3:	4c 8b bc 24 50 05 00 	mov    0x550(%rsp),%r15
 105bfea:	00 
 105bfeb:	48 8b 84 24 58 05 00 	mov    0x558(%rsp),%rax
 105bff2:	00 
 105bff3:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 105bff8:	4c 89 f7             	mov    %r14,%rdi
 105bffb:	4c 89 fe             	mov    %r15,%rsi
 105bffe:	e8 dd e6 00 00       	call   106a6e0 <my.heap::string_hash>
 105c003:	4c 89 f7             	mov    %r14,%rdi
 105c006:	48 89 de             	mov    %rbx,%rsi
 105c009:	4c 89 fa             	mov    %r15,%rdx
 105c00c:	89 c1                	mov    %eax,%ecx
 105c00e:	e8 ad ec 00 00       	call   106acc0 <my.heap::instance_field>
 105c013:	3c 01                	cmp    $0x1,%al
 105c015:	0f 85 13 1d 00 00    	jne    105dd2e <my.vm::run+0x27fe>
 105c01b:	4b 8d 04 2c          	lea    (%r12,%r13,1),%rax
 105c01f:	48 83 c0 20          	add    $0x20,%rax
 105c023:	0f b6 d2             	movzbl %dl,%edx
 105c026:	48 89 10             	mov    %rdx,(%rax)
 105c029:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105c02d:	49 89 ef             	mov    %rbp,%r15
 105c030:	49 ff c7             	inc    %r15
 105c033:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105c03a:	e9 f3 15 00 00       	jmp    105d632 <my.vm::run+0x2102>
 105c03f:	48 8d bc 24 60 03 00 	lea    0x360(%rsp),%rdi
 105c046:	00 
 105c047:	4c 89 f6             	mov    %r14,%rsi
 105c04a:	4c 89 da             	mov    %r11,%rdx
 105c04d:	4c 89 e1             	mov    %r12,%rcx
 105c050:	e8 eb 7b 00 00       	call   1063c40 <my.vm::read_constant>
 105c055:	0f b6 84 24 60 03 00 	movzbl 0x360(%rsp),%eax
 105c05c:	00 
 105c05d:	83 f8 03             	cmp    $0x3,%eax
 105c060:	0f 85 38 27 00 00    	jne    105e79e <my.vm::run+0x326e>
 105c066:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105c06d:	48 89 c6             	mov    %rax,%rsi
 105c070:	48 ff ce             	dec    %rsi
 105c073:	0f 80 97 2b 00 00    	jo     105ec10 <my.vm::run+0x36e0>
 105c079:	4c 8b ac 24 88 03 00 	mov    0x388(%rsp),%r13
 105c080:	00 
 105c081:	48 8b 8c 24 80 03 00 	mov    0x380(%rsp),%rcx
 105c088:	00 
 105c089:	48 8b bc 24 78 03 00 	mov    0x378(%rsp),%rdi
 105c090:	00 
 105c091:	48 8b 9c 24 68 03 00 	mov    0x368(%rsp),%rbx
 105c098:	00 
 105c099:	4c 8b 84 24 70 03 00 	mov    0x370(%rsp),%r8
 105c0a0:	00 
 105c0a1:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c0a5:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c0a9:	48 39 d6             	cmp    %rdx,%rsi
 105c0ac:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105c0b1:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 105c0b6:	4c 89 44 24 08       	mov    %r8,0x8(%rsp)
 105c0bb:	0f 83 79 20 00 00    	jae    105e13a <my.vm::run+0x2c0a>
 105c0c1:	48 89 f1             	mov    %rsi,%rcx
 105c0c4:	48 c1 e1 04          	shl    $0x4,%rcx
 105c0c8:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105c0cd:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 105c0d1:	4c 89 f7             	mov    %r14,%rdi
 105c0d4:	48 89 de             	mov    %rbx,%rsi
 105c0d7:	e8 04 e6 00 00       	call   106a6e0 <my.heap::string_hash>
 105c0dc:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105c0e0:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105c0e4:	48 89 da             	mov    %rbx,%rdx
 105c0e7:	89 c1                	mov    %eax,%ecx
 105c0e9:	41 89 e8             	mov    %ebp,%r8d
 105c0ec:	4d 89 f9             	mov    %r15,%r9
 105c0ef:	e8 cc e6 00 00       	call   106a7c0 <my.table::set>
 105c0f4:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105c0f8:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105c0fc:	a8 01                	test   $0x1,%al
 105c0fe:	0f 84 99 00 00 00    	je     105c19d <my.vm::run+0xc6d>
 105c104:	49 89 d7             	mov    %rdx,%r15
 105c107:	49 89 cc             	mov    %rcx,%r12
 105c10a:	4c 89 f7             	mov    %r14,%rdi
 105c10d:	48 89 de             	mov    %rbx,%rsi
 105c110:	e8 cb e5 00 00       	call   106a6e0 <my.heap::string_hash>
 105c115:	4c 89 ff             	mov    %r15,%rdi
 105c118:	4c 89 e6             	mov    %r12,%rsi
 105c11b:	48 89 da             	mov    %rbx,%rdx
 105c11e:	89 c1                	mov    %eax,%ecx
 105c120:	e8 8b e8 00 00       	call   106a9b0 <my.table::delete>
 105c125:	49 89 46 30          	mov    %rax,0x30(%r14)
 105c129:	49 89 56 38          	mov    %rdx,0x38(%r14)
 105c12d:	4c 89 f7             	mov    %r14,%rdi
 105c130:	48 89 de             	mov    %rbx,%rsi
 105c133:	e8 b8 e3 00 00       	call   106a4f0 <my.heap::string_chars>
 105c138:	48 89 c3             	mov    %rax,%rbx
 105c13b:	48 8d 3d 9e 69 fb ff 	lea    -0x49662(%rip),%rdi        # 1012ae0 <core_number_pairs+0xb880>
 105c142:	48 89 c6             	mov    %rax,%rsi
 105c145:	e8 b6 35 fd ff       	call   102f700 <myl_core_bytes_concat>
 105c14a:	49 89 c7             	mov    %rax,%r15
 105c14d:	48 89 df             	mov    %rbx,%rdi
 105c150:	e8 ab 81 fc ff       	call   1024300 <myl_core_drop_owned>
 105c155:	48 8d 35 c4 69 fb ff 	lea    -0x4963c(%rip),%rsi        # 1012b20 <core_number_pairs+0xb8c0>
 105c15c:	4c 89 ff             	mov    %r15,%rdi
 105c15f:	e8 9c 35 fd ff       	call   102f700 <myl_core_bytes_concat>
 105c164:	48 89 c3             	mov    %rax,%rbx
 105c167:	4c 89 ff             	mov    %r15,%rdi
 105c16a:	e8 91 81 fc ff       	call   1024300 <myl_core_drop_owned>
 105c16f:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105c176:	00 
 105c177:	4c 89 f6             	mov    %r14,%rsi
 105c17a:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105c17f:	48 89 d9             	mov    %rbx,%rcx
 105c182:	e8 79 75 00 00       	call   1063700 <my.vm::runtime_error>
 105c187:	48 89 df             	mov    %rbx,%rdi
 105c18a:	e8 71 81 fc ff       	call   1024300 <myl_core_drop_owned>
 105c18f:	f6 84 24 a0 00 00 00 	testb  $0x1,0xa0(%rsp)
 105c196:	01 
 105c197:	0f 84 33 24 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105c19d:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105c1a4:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105c1ab:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105c1b0:	4d 89 e9             	mov    %r13,%r9
 105c1b3:	e9 8b 14 00 00       	jmp    105d643 <my.vm::run+0x2113>
 105c1b8:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c1bc:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c1c0:	4c 89 f9             	mov    %r15,%rcx
 105c1c3:	49 39 d7             	cmp    %rdx,%r15
 105c1c6:	0f 83 74 1c 00 00    	jae    105de40 <my.vm::run+0x2910>
 105c1cc:	48 c1 e1 04          	shl    $0x4,%rcx
 105c1d0:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105c1d7:	00 00 
 105c1d9:	c6 44 08 28 01       	movb   $0x1,0x28(%rax,%rcx,1)
 105c1de:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c1e2:	4c 89 f8             	mov    %r15,%rax
 105c1e5:	48 ff c0             	inc    %rax
 105c1e8:	0f 81 c9 03 00 00    	jno    105c5b7 <my.vm::run+0x1087>
 105c1ee:	e9 41 28 00 00       	jmp    105ea34 <my.vm::run+0x3504>
 105c1f3:	4c 89 fe             	mov    %r15,%rsi
 105c1f6:	48 ff ce             	dec    %rsi
 105c1f9:	0f 80 a4 28 00 00    	jo     105eaa3 <my.vm::run+0x3573>
 105c1ff:	49 89 dd             	mov    %rbx,%r13
 105c202:	4c 89 db             	mov    %r11,%rbx
 105c205:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105c20c:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c210:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c214:	48 89 f1             	mov    %rsi,%rcx
 105c217:	48 39 d6             	cmp    %rdx,%rsi
 105c21a:	0f 83 fb 1c 00 00    	jae    105df1b <my.vm::run+0x29eb>
 105c220:	49 89 f7             	mov    %rsi,%r15
 105c223:	49 ff cf             	dec    %r15
 105c226:	0f 80 52 28 00 00    	jo     105ea7e <my.vm::run+0x354e>
 105c22c:	4d 89 c3             	mov    %r8,%r11
 105c22f:	4d 89 ca             	mov    %r9,%r10
 105c232:	48 c1 e1 04          	shl    $0x4,%rcx
 105c236:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105c23c:	48 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%rdi
 105c241:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105c248:	4c 89 f9             	mov    %r15,%rcx
 105c24b:	49 39 d7             	cmp    %rdx,%r15
 105c24e:	0f 83 c9 1d 00 00    	jae    105e01d <my.vm::run+0x2aed>
 105c254:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105c258:	48 c1 e1 04          	shl    $0x4,%rcx
 105c25c:	44 0f b6 0c 0a       	movzbl (%rdx,%rcx,1),%r9d
 105c261:	48 8b 74 0a 08       	mov    0x8(%rdx,%rcx,1),%rsi
 105c266:	41 83 f9 02          	cmp    $0x2,%r9d
 105c26a:	0f 84 86 18 00 00    	je     105daf6 <my.vm::run+0x25c6>
 105c270:	41 83 f9 01          	cmp    $0x1,%r9d
 105c274:	0f 84 64 18 00 00    	je     105dade <my.vm::run+0x25ae>
 105c27a:	45 85 c9             	test   %r9d,%r9d
 105c27d:	0f 85 a6 18 00 00    	jne    105db29 <my.vm::run+0x25f9>
 105c283:	45 84 c0             	test   %r8b,%r8b
 105c286:	40 0f 94 c6          	sete   %sil
 105c28a:	e9 da 19 00 00       	jmp    105dc69 <my.vm::run+0x2739>
 105c28f:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c293:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c297:	4c 89 f9             	mov    %r15,%rcx
 105c29a:	49 39 d7             	cmp    %rdx,%r15
 105c29d:	0f 83 b8 1b 00 00    	jae    105de5b <my.vm::run+0x292b>
 105c2a3:	48 c1 e1 04          	shl    $0x4,%rcx
 105c2a7:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105c2ae:	00 00 
 105c2b0:	c6 44 08 28 00       	movb   $0x0,0x28(%rax,%rcx,1)
 105c2b5:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c2b9:	4c 89 f8             	mov    %r15,%rax
 105c2bc:	48 ff c0             	inc    %rax
 105c2bf:	0f 81 f2 02 00 00    	jno    105c5b7 <my.vm::run+0x1087>
 105c2c5:	e9 7f 29 00 00       	jmp    105ec49 <my.vm::run+0x3719>
 105c2ca:	48 8d bc 24 60 03 00 	lea    0x360(%rsp),%rdi
 105c2d1:	00 
 105c2d2:	4c 89 f6             	mov    %r14,%rsi
 105c2d5:	4c 89 da             	mov    %r11,%rdx
 105c2d8:	4c 89 e1             	mov    %r12,%rcx
 105c2db:	e8 60 79 00 00       	call   1063c40 <my.vm::read_constant>
 105c2e0:	0f b6 84 24 60 03 00 	movzbl 0x360(%rsp),%eax
 105c2e7:	00 
 105c2e8:	83 f8 03             	cmp    $0x3,%eax
 105c2eb:	0f 85 1c 24 00 00    	jne    105e70d <my.vm::run+0x31dd>
 105c2f1:	48 8b 84 24 88 03 00 	mov    0x388(%rsp),%rax
 105c2f8:	00 
 105c2f9:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105c2fe:	48 8b 84 24 80 03 00 	mov    0x380(%rsp),%rax
 105c305:	00 
 105c306:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105c30b:	48 8b 84 24 78 03 00 	mov    0x378(%rsp),%rax
 105c312:	00 
 105c313:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105c318:	48 8b 9c 24 68 03 00 	mov    0x368(%rsp),%rbx
 105c31f:	00 
 105c320:	4c 8b ac 24 70 03 00 	mov    0x370(%rsp),%r13
 105c327:	00 
 105c328:	4d 8b 7e 30          	mov    0x30(%r14),%r15
 105c32c:	4d 8b 66 38          	mov    0x38(%r14),%r12
 105c330:	4c 89 f7             	mov    %r14,%rdi
 105c333:	48 89 de             	mov    %rbx,%rsi
 105c336:	e8 a5 e3 00 00       	call   106a6e0 <my.heap::string_hash>
 105c33b:	4c 89 ff             	mov    %r15,%rdi
 105c33e:	4c 89 e6             	mov    %r12,%rsi
 105c341:	48 89 da             	mov    %rbx,%rdx
 105c344:	89 c1                	mov    %eax,%ecx
 105c346:	e8 85 e2 00 00       	call   106a5d0 <my.table::get>
 105c34b:	3c 01                	cmp    $0x1,%al
 105c34d:	0f 85 9e 13 00 00    	jne    105d6f1 <my.vm::run+0x21c1>
 105c353:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105c357:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105c35e:	48 8b 47 08          	mov    0x8(%rdi),%rax
 105c362:	49 89 f0             	mov    %rsi,%r8
 105c365:	48 39 c6             	cmp    %rax,%rsi
 105c368:	0f 83 c7 1f 00 00    	jae    105e335 <my.vm::run+0x2e05>
 105c36e:	49 c1 e0 04          	shl    $0x4,%r8
 105c372:	0f b6 c2             	movzbl %dl,%eax
 105c375:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 105c37a:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 105c37f:	49 89 f7             	mov    %rsi,%r15
 105c382:	49 ff c7             	inc    %r15
 105c385:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105c38a:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105c38f:	0f 80 00 2a 00 00    	jo     105ed95 <my.vm::run+0x3865>
 105c395:	4d 89 eb             	mov    %r13,%r11
 105c398:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105c39f:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105c3a6:	e9 a9 18 00 00       	jmp    105dc54 <my.vm::run+0x2724>
 105c3ab:	48 8d bc 24 d0 02 00 	lea    0x2d0(%rsp),%rdi
 105c3b2:	00 
 105c3b3:	4c 89 f6             	mov    %r14,%rsi
 105c3b6:	4c 89 da             	mov    %r11,%rdx
 105c3b9:	4c 89 e1             	mov    %r12,%rcx
 105c3bc:	e8 7f 78 00 00       	call   1063c40 <my.vm::read_constant>
 105c3c1:	c5 f9 28 84 24 d0 02 	vmovapd 0x2d0(%rsp),%xmm0
 105c3c8:	00 00 
 105c3ca:	4c 8b 9c 24 e0 02 00 	mov    0x2e0(%rsp),%r11
 105c3d1:	00 
 105c3d2:	4c 8b a4 24 e8 02 00 	mov    0x2e8(%rsp),%r12
 105c3d9:	00 
 105c3da:	4c 8b 84 24 f0 02 00 	mov    0x2f0(%rsp),%r8
 105c3e1:	00 
 105c3e2:	4c 8b 8c 24 f8 02 00 	mov    0x2f8(%rsp),%r9
 105c3e9:	00 
 105c3ea:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c3ee:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c3f2:	4c 89 f9             	mov    %r15,%rcx
 105c3f5:	49 39 d7             	cmp    %rdx,%r15
 105c3f8:	0f 83 78 1a 00 00    	jae    105de76 <my.vm::run+0x2946>
 105c3fe:	48 c1 e1 04          	shl    $0x4,%rcx
 105c402:	c5 f9 54 05 d6 7f fa 	vandpd -0x5802a(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c409:	ff 
 105c40a:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 105c410:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c414:	4c 89 f8             	mov    %r15,%rax
 105c417:	48 ff c0             	inc    %rax
 105c41a:	0f 80 99 27 00 00    	jo     105ebb9 <my.vm::run+0x3689>
 105c420:	49 89 ea             	mov    %rbp,%r10
 105c423:	e9 8f 01 00 00       	jmp    105c5b7 <my.vm::run+0x1087>
 105c428:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c42c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c430:	4c 89 f9             	mov    %r15,%rcx
 105c433:	49 39 d7             	cmp    %rdx,%r15
 105c436:	0f 83 55 1a 00 00    	jae    105de91 <my.vm::run+0x2961>
 105c43c:	48 c1 e1 04          	shl    $0x4,%rcx
 105c440:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105c447:	00 00 
 105c449:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c44d:	4c 89 f8             	mov    %r15,%rax
 105c450:	48 ff c0             	inc    %rax
 105c453:	0f 81 5e 01 00 00    	jno    105c5b7 <my.vm::run+0x1087>
 105c459:	e9 81 26 00 00       	jmp    105eadf <my.vm::run+0x35af>
 105c45e:	48 8d bc 24 30 02 00 	lea    0x230(%rsp),%rdi
 105c465:	00 
 105c466:	4c 89 f6             	mov    %r14,%rsi
 105c469:	4c 89 da             	mov    %r11,%rdx
 105c46c:	4c 89 e1             	mov    %r12,%rcx
 105c46f:	e8 8c 7d 00 00       	call   1064200 <my.vm::read_short>
 105c474:	48 8b 94 24 30 02 00 	mov    0x230(%rsp),%rdx
 105c47b:	00 
 105c47c:	48 8b b4 24 48 02 00 	mov    0x248(%rsp),%rsi
 105c483:	00 
 105c484:	49 89 f0             	mov    %rsi,%r8
 105c487:	49 01 d0             	add    %rdx,%r8
 105c48a:	0f 80 74 27 00 00    	jo     105ec04 <my.vm::run+0x36d4>
 105c490:	4c 8b 9c 24 38 02 00 	mov    0x238(%rsp),%r11
 105c497:	00 
 105c498:	4c 8b a4 24 40 02 00 	mov    0x240(%rsp),%r12
 105c49f:	00 
 105c4a0:	4c 8b 8c 24 50 02 00 	mov    0x250(%rsp),%r9
 105c4a7:	00 
 105c4a8:	49 89 ea             	mov    %rbp,%r10
 105c4ab:	e9 40 18 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105c4b0:	4c 89 fb             	mov    %r15,%rbx
 105c4b3:	48 ff cb             	dec    %rbx
 105c4b6:	0f 80 48 26 00 00    	jo     105eb04 <my.vm::run+0x35d4>
 105c4bc:	4c 89 5c 24 08       	mov    %r11,0x8(%rsp)
 105c4c1:	4c 89 44 24 20       	mov    %r8,0x20(%rsp)
 105c4c6:	4d 89 cd             	mov    %r9,%r13
 105c4c9:	49 89 9e 80 00 00 00 	mov    %rbx,0x80(%r14)
 105c4d0:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c4d4:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c4d8:	48 89 de             	mov    %rbx,%rsi
 105c4db:	48 39 d3             	cmp    %rdx,%rbx
 105c4de:	0f 83 52 1a 00 00    	jae    105df36 <my.vm::run+0x2a06>
 105c4e4:	48 c1 e6 04          	shl    $0x4,%rsi
 105c4e8:	48 8b 4c 30 28       	mov    0x28(%rax,%rsi,1),%rcx
 105c4ed:	8b 54 30 20          	mov    0x20(%rax,%rsi,1),%edx
 105c4f1:	4c 89 f7             	mov    %r14,%rdi
 105c4f4:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 105c4f9:	e8 42 7a 00 00       	call   1063f40 <my.output::print_value>
 105c4fe:	49 89 df             	mov    %rbx,%r15
 105c501:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105c506:	4d 89 e9             	mov    %r13,%r9
 105c509:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105c50e:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105c513:	49 89 ea             	mov    %rbp,%r10
 105c516:	e9 d5 17 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105c51b:	48 8d bc 24 80 02 00 	lea    0x280(%rsp),%rdi
 105c522:	00 
 105c523:	4c 89 f6             	mov    %r14,%rsi
 105c526:	4c 89 da             	mov    %r11,%rdx
 105c529:	4c 89 e1             	mov    %r12,%rcx
 105c52c:	e8 4f 76 00 00       	call   1063b80 <my.vm::read_byte>
 105c531:	48 8b 94 24 80 02 00 	mov    0x280(%rsp),%rdx
 105c538:	00 
 105c539:	4c 8b 8c 24 a0 02 00 	mov    0x2a0(%rsp),%r9
 105c540:	00 
 105c541:	4c 89 ce             	mov    %r9,%rsi
 105c544:	48 01 d6             	add    %rdx,%rsi
 105c547:	0f 80 94 26 00 00    	jo     105ebe1 <my.vm::run+0x36b1>
 105c54d:	4c 8b 9c 24 88 02 00 	mov    0x288(%rsp),%r11
 105c554:	00 
 105c555:	4c 8b a4 24 90 02 00 	mov    0x290(%rsp),%r12
 105c55c:	00 
 105c55d:	4c 8b 84 24 98 02 00 	mov    0x298(%rsp),%r8
 105c564:	00 
 105c565:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c569:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c56d:	48 39 d6             	cmp    %rdx,%rsi
 105c570:	0f 83 db 19 00 00    	jae    105df51 <my.vm::run+0x2a21>
 105c576:	48 89 f1             	mov    %rsi,%rcx
 105c579:	49 89 ea             	mov    %rbp,%r10
 105c57c:	48 c1 e1 04          	shl    $0x4,%rcx
 105c580:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105c586:	4c 89 f9             	mov    %r15,%rcx
 105c589:	49 39 d7             	cmp    %rdx,%r15
 105c58c:	0f 83 16 1a 00 00    	jae    105dfa8 <my.vm::run+0x2a78>
 105c592:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105c596:	48 c1 e1 04          	shl    $0x4,%rcx
 105c59a:	c5 f9 54 05 3e 7e fa 	vandpd -0x581c2(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c5a1:	ff 
 105c5a2:	c5 f9 11 04 0a       	vmovupd %xmm0,(%rdx,%rcx,1)
 105c5a7:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c5ab:	4c 89 f8             	mov    %r15,%rax
 105c5ae:	48 ff c0             	inc    %rax
 105c5b1:	0f 80 39 26 00 00    	jo     105ebf0 <my.vm::run+0x36c0>
 105c5b7:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105c5be:	49 89 c7             	mov    %rax,%r15
 105c5c1:	e9 2a 17 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105c5c6:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105c5cd:	49 89 f7             	mov    %rsi,%r15
 105c5d0:	49 ff cf             	dec    %r15
 105c5d3:	0f 80 1a 25 00 00    	jo     105eaf3 <my.vm::run+0x35c3>
 105c5d9:	4c 89 f9             	mov    %r15,%rcx
 105c5dc:	48 ff c9             	dec    %rcx
 105c5df:	0f 80 aa 24 00 00    	jo     105ea8f <my.vm::run+0x355f>
 105c5e5:	4c 89 5c 24 08       	mov    %r11,0x8(%rsp)
 105c5ea:	4c 89 44 24 20       	mov    %r8,0x20(%rsp)
 105c5ef:	4d 89 cd             	mov    %r9,%r13
 105c5f2:	49 8b 5e 78          	mov    0x78(%r14),%rbx
 105c5f6:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105c5fa:	48 89 c8             	mov    %rcx,%rax
 105c5fd:	48 89 4c 24 38       	mov    %rcx,0x38(%rsp)
 105c602:	48 39 d1             	cmp    %rdx,%rcx
 105c605:	0f 83 2d 1a 00 00    	jae    105e038 <my.vm::run+0x2b08>
 105c60b:	48 c1 e0 04          	shl    $0x4,%rax
 105c60f:	0f b6 4c 03 20       	movzbl 0x20(%rbx,%rax,1),%ecx
 105c614:	85 c9                	test   %ecx,%ecx
 105c616:	0f 84 24 15 00 00    	je     105db40 <my.vm::run+0x2610>
 105c61c:	83 f9 01             	cmp    $0x1,%ecx
 105c61f:	0f 84 f7 14 00 00    	je     105db1c <my.vm::run+0x25ec>
 105c625:	83 f9 03             	cmp    $0x3,%ecx
 105c628:	0f 85 1f 15 00 00    	jne    105db4d <my.vm::run+0x261d>
 105c62e:	48 8b 4c 03 28       	mov    0x28(%rbx,%rax,1),%rcx
 105c633:	49 8b 2e             	mov    (%r14),%rbp
 105c636:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105c63a:	48 89 c8             	mov    %rcx,%rax
 105c63d:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
 105c642:	48 39 d1             	cmp    %rdx,%rcx
 105c645:	4d 89 e9             	mov    %r13,%r9
 105c648:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105c64d:	48 8b 4c 24 08       	mov    0x8(%rsp),%rcx
 105c652:	0f 83 ba 1d 00 00    	jae    105e412 <my.vm::run+0x2ee2>
 105c658:	48 6b c0 38          	imul   $0x38,%rax,%rax
 105c65c:	83 7c 05 20 07       	cmpl   $0x7,0x20(%rbp,%rax,1)
 105c661:	0f 85 33 16 00 00    	jne    105dc9a <my.vm::run+0x276a>
 105c667:	48 8d bc 24 90 01 00 	lea    0x190(%rsp),%rdi
 105c66e:	00 
 105c66f:	4c 89 f6             	mov    %r14,%rsi
 105c672:	48 89 ca             	mov    %rcx,%rdx
 105c675:	4c 89 e1             	mov    %r12,%rcx
 105c678:	e8 c3 75 00 00       	call   1063c40 <my.vm::read_constant>
 105c67d:	0f b6 84 24 90 01 00 	movzbl 0x190(%rsp),%eax
 105c684:	00 
 105c685:	83 f8 03             	cmp    $0x3,%eax
 105c688:	0f 85 51 27 00 00    	jne    105eddf <my.vm::run+0x38af>
 105c68e:	48 8b 84 24 b8 01 00 	mov    0x1b8(%rsp),%rax
 105c695:	00 
 105c696:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105c69b:	48 8b 84 24 b0 01 00 	mov    0x1b0(%rsp),%rax
 105c6a2:	00 
 105c6a3:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105c6a8:	4c 8b a4 24 a8 01 00 	mov    0x1a8(%rsp),%r12
 105c6af:	00 
 105c6b0:	48 8b b4 24 98 01 00 	mov    0x198(%rsp),%rsi
 105c6b7:	00 
 105c6b8:	48 8b 84 24 a0 01 00 	mov    0x1a0(%rsp),%rax
 105c6bf:	00 
 105c6c0:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 105c6c5:	4c 89 f7             	mov    %r14,%rdi
 105c6c8:	48 89 b4 24 d8 01 00 	mov    %rsi,0x1d8(%rsp)
 105c6cf:	00 
 105c6d0:	e8 0b e0 00 00       	call   106a6e0 <my.heap::string_hash>
 105c6d5:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105c6d9:	4c 89 ff             	mov    %r15,%rdi
 105c6dc:	49 39 d7             	cmp    %rdx,%r15
 105c6df:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 105c6e4:	0f 83 a4 1d 00 00    	jae    105e48e <my.vm::run+0x2f5e>
 105c6ea:	4c 89 64 24 10       	mov    %r12,0x10(%rsp)
 105c6ef:	48 8d 4b 20          	lea    0x20(%rbx),%rcx
 105c6f3:	48 c1 e7 04          	shl    $0x4,%rdi
 105c6f7:	44 0f b6 2c 39       	movzbl (%rcx,%rdi,1),%r13d
 105c6fc:	4c 8b 44 39 08       	mov    0x8(%rcx,%rdi,1),%r8
 105c701:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105c705:	48 89 f7             	mov    %rsi,%rdi
 105c708:	48 39 d6             	cmp    %rdx,%rsi
 105c70b:	0f 83 98 1d 00 00    	jae    105e4a9 <my.vm::run+0x2f79>
 105c711:	4c 89 84 24 d0 01 00 	mov    %r8,0x1d0(%rsp)
 105c718:	00 
 105c719:	89 84 24 8c 00 00 00 	mov    %eax,0x8c(%rsp)
 105c720:	48 89 4c 24 58       	mov    %rcx,0x58(%rsp)
 105c725:	4c 8d 65 20          	lea    0x20(%rbp),%r12
 105c729:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 105c72d:	41 8b 0c 04          	mov    (%r12,%rax,1),%ecx
 105c731:	83 f9 07             	cmp    $0x7,%ecx
 105c734:	0f 85 06 21 00 00    	jne    105e840 <my.vm::run+0x3310>
 105c73a:	4c 01 e0             	add    %r12,%rax
 105c73d:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105c741:	48 89 8c 24 c8 01 00 	mov    %rcx,0x1c8(%rsp)
 105c748:	00 
 105c749:	48 8b 78 10          	mov    0x10(%rax),%rdi
 105c74d:	48 8b 40 18          	mov    0x18(%rax),%rax
 105c751:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
 105c758:	00 
 105c759:	be 20 00 00 00       	mov    $0x20,%esi
 105c75e:	e8 5d 7a fc ff       	call   10241c0 <myl_core_list_copy>
 105c763:	45 0f b6 c5          	movzbl %r13b,%r8d
 105c767:	48 89 c7             	mov    %rax,%rdi
 105c76a:	48 8b b4 24 c0 01 00 	mov    0x1c0(%rsp),%rsi
 105c771:	00 
 105c772:	48 8b 94 24 d8 01 00 	mov    0x1d8(%rsp),%rdx
 105c779:	00 
 105c77a:	8b 8c 24 8c 00 00 00 	mov    0x8c(%rsp),%ecx
 105c781:	4c 8b 8c 24 d0 01 00 	mov    0x1d0(%rsp),%r9
 105c788:	00 
 105c789:	e8 32 e0 00 00       	call   106a7c0 <my.table::set>
 105c78e:	48 8b 45 08          	mov    0x8(%rbp),%rax
 105c792:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 105c797:	48 39 c6             	cmp    %rax,%rsi
 105c79a:	0f 83 3f 1d 00 00    	jae    105e4df <my.vm::run+0x2faf>
 105c7a0:	48 89 f7             	mov    %rsi,%rdi
 105c7a3:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105c7a8:	4c 6b cf 38          	imul   $0x38,%rdi,%r9
 105c7ac:	43 0f b6 34 0c       	movzbl (%r12,%r9,1),%esi
 105c7b1:	4b 8b 7c 0c 08       	mov    0x8(%r12,%r9,1),%rdi
 105c7b6:	4f 8b 44 0c 10       	mov    0x10(%r12,%r9,1),%r8
 105c7bb:	4b 8b 44 0c 18       	mov    0x18(%r12,%r9,1),%rax
 105c7c0:	4f 8b 6c 0c 20       	mov    0x20(%r12,%r9,1),%r13
 105c7c5:	4b 8b 6c 0c 28       	mov    0x28(%r12,%r9,1),%rbp
 105c7ca:	4b c7 04 0c 07 00 00 	movq   $0x7,(%r12,%r9,1)
 105c7d1:	00 
 105c7d2:	4c 8b 94 24 c8 01 00 	mov    0x1c8(%rsp),%r10
 105c7d9:	00 
 105c7da:	4f 89 54 0c 08       	mov    %r10,0x8(%r12,%r9,1)
 105c7df:	4b 89 54 0c 10       	mov    %rdx,0x10(%r12,%r9,1)
 105c7e4:	4b 89 4c 0c 18       	mov    %rcx,0x18(%r12,%r9,1)
 105c7e9:	83 fe 09             	cmp    $0x9,%esi
 105c7ec:	4c 8b 64 24 10       	mov    0x10(%rsp),%r12
 105c7f1:	77 1b                	ja     105c80e <my.vm::run+0x12de>
 105c7f3:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105c7f8:	0f a3 f1             	bt     %esi,%ecx
 105c7fb:	0f 83 df 15 00 00    	jae    105dde0 <my.vm::run+0x28b0>
 105c801:	4c 89 c7             	mov    %r8,%rdi
 105c804:	e8 f7 7a fc ff       	call   1024300 <myl_core_drop_owned>
 105c809:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105c80e:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105c812:	49 39 d7             	cmp    %rdx,%r15
 105c815:	0f 83 e4 1c 00 00    	jae    105e4ff <my.vm::run+0x2fcf>
 105c81b:	4c 89 f8             	mov    %r15,%rax
 105c81e:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105c823:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105c828:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105c82d:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 105c832:	48 c1 e0 04          	shl    $0x4,%rax
 105c836:	c5 f9 10 04 01       	vmovupd (%rcx,%rax,1),%xmm0
 105c83b:	4c 8b 7c 24 38       	mov    0x38(%rsp),%r15
 105c840:	4c 89 f8             	mov    %r15,%rax
 105c843:	49 39 d7             	cmp    %rdx,%r15
 105c846:	0f 83 e2 1c 00 00    	jae    105e52e <my.vm::run+0x2ffe>
 105c84c:	c5 f9 54 05 8c 7b fa 	vandpd -0x58474(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c853:	ff 
 105c854:	48 c1 e0 04          	shl    $0x4,%rax
 105c858:	c5 f9 11 04 01       	vmovupd %xmm0,(%rcx,%rax,1)
 105c85d:	e9 25 13 00 00       	jmp    105db87 <my.vm::run+0x2657>
 105c862:	48 8d bc 24 58 02 00 	lea    0x258(%rsp),%rdi
 105c869:	00 
 105c86a:	4c 89 f6             	mov    %r14,%rsi
 105c86d:	4c 89 da             	mov    %r11,%rdx
 105c870:	4c 89 e1             	mov    %r12,%rcx
 105c873:	e8 08 73 00 00       	call   1063b80 <my.vm::read_byte>
 105c878:	4c 89 fe             	mov    %r15,%rsi
 105c87b:	48 ff ce             	dec    %rsi
 105c87e:	0f 80 e3 20 00 00    	jo     105e967 <my.vm::run+0x3437>
 105c884:	48 8b 84 24 58 02 00 	mov    0x258(%rsp),%rax
 105c88b:	00 
 105c88c:	4c 8b 9c 24 60 02 00 	mov    0x260(%rsp),%r11
 105c893:	00 
 105c894:	4c 8b a4 24 68 02 00 	mov    0x268(%rsp),%r12
 105c89b:	00 
 105c89c:	4c 8b 84 24 70 02 00 	mov    0x270(%rsp),%r8
 105c8a3:	00 
 105c8a4:	4c 8b 8c 24 78 02 00 	mov    0x278(%rsp),%r9
 105c8ab:	00 
 105c8ac:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105c8b0:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105c8b4:	48 39 d6             	cmp    %rdx,%rsi
 105c8b7:	0f 83 b2 16 00 00    	jae    105df6f <my.vm::run+0x2a3f>
 105c8bd:	48 89 f7             	mov    %rsi,%rdi
 105c8c0:	49 89 ea             	mov    %rbp,%r10
 105c8c3:	4c 89 ce             	mov    %r9,%rsi
 105c8c6:	48 01 c6             	add    %rax,%rsi
 105c8c9:	0f 80 ea 23 00 00    	jo     105ecb9 <my.vm::run+0x3789>
 105c8cf:	48 c1 e7 04          	shl    $0x4,%rdi
 105c8d3:	c5 f9 10 44 39 20    	vmovupd 0x20(%rcx,%rdi,1),%xmm0
 105c8d9:	48 39 d6             	cmp    %rdx,%rsi
 105c8dc:	0f 83 76 17 00 00    	jae    105e058 <my.vm::run+0x2b28>
 105c8e2:	48 89 f0             	mov    %rsi,%rax
 105c8e5:	48 8d 51 20          	lea    0x20(%rcx),%rdx
 105c8e9:	48 c1 e0 04          	shl    $0x4,%rax
 105c8ed:	c5 f9 54 05 eb 7a fa 	vandpd -0x58515(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c8f4:	ff 
 105c8f5:	c5 f9 11 04 02       	vmovupd %xmm0,(%rdx,%rax,1)
 105c8fa:	49 89 4e 78          	mov    %rcx,0x78(%r14)
 105c8fe:	e9 ed 13 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105c903:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105c90a:	00 
 105c90b:	4c 89 f6             	mov    %r14,%rsi
 105c90e:	4c 89 da             	mov    %r11,%rdx
 105c911:	4c 89 e1             	mov    %r12,%rcx
 105c914:	e8 67 72 00 00       	call   1063b80 <my.vm::read_byte>
 105c919:	48 8b 94 24 a0 00 00 	mov    0xa0(%rsp),%rdx
 105c920:	00 
 105c921:	48 8b b4 24 a8 00 00 	mov    0xa8(%rsp),%rsi
 105c928:	00 
 105c929:	4c 8b a4 24 b0 00 00 	mov    0xb0(%rsp),%r12
 105c930:	00 
 105c931:	4c 8b ac 24 b8 00 00 	mov    0xb8(%rsp),%r13
 105c938:	00 
 105c939:	4c 8b bc 24 c0 00 00 	mov    0xc0(%rsp),%r15
 105c940:	00 
 105c941:	4c 89 f7             	mov    %r14,%rdi
 105c944:	48 89 f3             	mov    %rsi,%rbx
 105c947:	e8 64 e2 00 00       	call   106abb0 <my.heap::closure_upvalue>
 105c94c:	48 8d bc 24 00 03 00 	lea    0x300(%rsp),%rdi
 105c953:	00 
 105c954:	4c 89 f6             	mov    %r14,%rsi
 105c957:	48 89 c2             	mov    %rax,%rdx
 105c95a:	e8 51 e1 00 00       	call   106aab0 <my.heap::upvalue_obj>
 105c95f:	48 8b b4 24 00 03 00 	mov    0x300(%rsp),%rsi
 105c966:	00 
 105c967:	48 83 fe ff          	cmp    $0xffffffffffffffff,%rsi
 105c96b:	0f 84 e5 0e 00 00    	je     105d856 <my.vm::run+0x2326>
 105c971:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c975:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c979:	48 39 d6             	cmp    %rdx,%rsi
 105c97c:	0f 83 08 19 00 00    	jae    105e28a <my.vm::run+0x2d5a>
 105c982:	48 89 f1             	mov    %rsi,%rcx
 105c985:	4d 89 f9             	mov    %r15,%r9
 105c988:	4d 89 e8             	mov    %r13,%r8
 105c98b:	49 89 db             	mov    %rbx,%r11
 105c98e:	48 c1 e1 04          	shl    $0x4,%rcx
 105c992:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105c998:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105c99f:	48 89 f1             	mov    %rsi,%rcx
 105c9a2:	48 39 d6             	cmp    %rdx,%rsi
 105c9a5:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105c9aa:	0f 83 fe 18 00 00    	jae    105e2ae <my.vm::run+0x2d7e>
 105c9b0:	48 83 c0 20          	add    $0x20,%rax
 105c9b4:	48 c1 e1 04          	shl    $0x4,%rcx
 105c9b8:	c5 f9 54 05 20 7a fa 	vandpd -0x585e0(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c9bf:	ff 
 105c9c0:	c5 f9 11 04 08       	vmovupd %xmm0,(%rax,%rcx,1)
 105c9c5:	49 89 f7             	mov    %rsi,%r15
 105c9c8:	49 ff c7             	inc    %r15
 105c9cb:	0f 81 b9 11 00 00    	jno    105db8a <my.vm::run+0x265a>
 105c9d1:	e9 9f 23 00 00       	jmp    105ed75 <my.vm::run+0x3845>
 105c9d6:	4c 89 fe             	mov    %r15,%rsi
 105c9d9:	48 ff ce             	dec    %rsi
 105c9dc:	0f 80 8c 22 00 00    	jo     105ec6e <my.vm::run+0x373e>
 105c9e2:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c9e6:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c9ea:	48 39 d6             	cmp    %rdx,%rsi
 105c9ed:	0f 83 9a 15 00 00    	jae    105df8d <my.vm::run+0x2a5d>
 105c9f3:	48 89 f1             	mov    %rsi,%rcx
 105c9f6:	48 c1 e1 04          	shl    $0x4,%rcx
 105c9fa:	48 8b 5c 08 20       	mov    0x20(%rax,%rcx,1),%rbx
 105c9ff:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105ca04:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105ca0b:	00 
 105ca0c:	4c 89 f6             	mov    %r14,%rsi
 105ca0f:	4c 89 da             	mov    %r11,%rdx
 105ca12:	4c 89 e1             	mov    %r12,%rcx
 105ca15:	e8 26 72 00 00       	call   1063c40 <my.vm::read_constant>
 105ca1a:	0f b6 84 24 a0 00 00 	movzbl 0xa0(%rsp),%eax
 105ca21:	00 
 105ca22:	83 f8 03             	cmp    $0x3,%eax
 105ca25:	0f 85 39 1d 00 00    	jne    105e764 <my.vm::run+0x3234>
 105ca2b:	48 8b 84 24 c8 00 00 	mov    0xc8(%rsp),%rax
 105ca32:	00 
 105ca33:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105ca38:	48 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%rax
 105ca3f:	00 
 105ca40:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105ca45:	48 8b 84 24 b8 00 00 	mov    0xb8(%rsp),%rax
 105ca4c:	00 
 105ca4d:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105ca52:	4c 8b a4 24 a8 00 00 	mov    0xa8(%rsp),%r12
 105ca59:	00 
 105ca5a:	4c 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%r13
 105ca61:	00 
 105ca62:	4c 89 f7             	mov    %r14,%rdi
 105ca65:	4c 89 e6             	mov    %r12,%rsi
 105ca68:	e8 73 dc 00 00       	call   106a6e0 <my.heap::string_hash>
 105ca6d:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105ca71:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105ca75:	4c 89 e2             	mov    %r12,%rdx
 105ca78:	89 c1                	mov    %eax,%ecx
 105ca7a:	41 89 d8             	mov    %ebx,%r8d
 105ca7d:	4d 89 f9             	mov    %r15,%r9
 105ca80:	e8 3b dd 00 00       	call   106a7c0 <my.table::set>
 105ca85:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105ca89:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105ca8d:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105ca94:	49 89 f7             	mov    %rsi,%r15
 105ca97:	49 ff cf             	dec    %r15
 105ca9a:	0f 80 bd 21 00 00    	jo     105ec5d <my.vm::run+0x372d>
 105caa0:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105caa7:	49 8b 46 78          	mov    0x78(%r14),%rax
 105caab:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105cab2:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cab6:	49 39 d7             	cmp    %rdx,%r15
 105cab9:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105cabe:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105cac3:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105cac8:	4d 89 eb             	mov    %r13,%r11
 105cacb:	0f 83 ba 16 00 00    	jae    105e18b <my.vm::run+0x2c5b>
 105cad1:	4c 8b 64 24 10       	mov    0x10(%rsp),%r12
 105cad6:	e9 15 12 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105cadb:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105cae2:	00 
 105cae3:	4c 89 f6             	mov    %r14,%rsi
 105cae6:	4c 89 da             	mov    %r11,%rdx
 105cae9:	4c 89 e1             	mov    %r12,%rcx
 105caec:	e8 4f 71 00 00       	call   1063c40 <my.vm::read_constant>
 105caf1:	0f b6 84 24 a0 00 00 	movzbl 0xa0(%rsp),%eax
 105caf8:	00 
 105caf9:	83 f8 03             	cmp    $0x3,%eax
 105cafc:	0f 85 28 1c 00 00    	jne    105e72a <my.vm::run+0x31fa>
 105cb02:	48 8b bc 24 c8 00 00 	mov    0xc8(%rsp),%rdi
 105cb09:	00 
 105cb0a:	4c 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%r8
 105cb11:	00 
 105cb12:	4c 8b a4 24 b8 00 00 	mov    0xb8(%rsp),%r12
 105cb19:	00 
 105cb1a:	4c 8b 8c 24 a8 00 00 	mov    0xa8(%rsp),%r9
 105cb21:	00 
 105cb22:	48 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%rbp
 105cb29:	00 
 105cb2a:	49 8b 06             	mov    (%r14),%rax
 105cb2d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cb31:	4c 89 c9             	mov    %r9,%rcx
 105cb34:	49 39 d1             	cmp    %rdx,%r9
 105cb37:	0f 83 c7 15 00 00    	jae    105e104 <my.vm::run+0x2bd4>
 105cb3d:	4c 89 44 24 20       	mov    %r8,0x20(%rsp)
 105cb42:	48 89 7c 24 18       	mov    %rdi,0x18(%rsp)
 105cb47:	48 6b d1 38          	imul   $0x38,%rcx,%rdx
 105cb4b:	8b 4c 10 20          	mov    0x20(%rax,%rdx,1),%ecx
 105cb4f:	83 f9 02             	cmp    $0x2,%ecx
 105cb52:	0f 85 16 1b 00 00    	jne    105e66e <my.vm::run+0x313e>
 105cb58:	48 01 d0             	add    %rdx,%rax
 105cb5b:	48 83 c0 20          	add    $0x20,%rax
 105cb5f:	48 8b 70 10          	mov    0x10(%rax),%rsi
 105cb63:	4c 89 cf             	mov    %r9,%rdi
 105cb66:	48 89 74 24 10       	mov    %rsi,0x10(%rsp)
 105cb6b:	e8 40 e6 ff ff       	call   105b1b0 <my.object::new_closure>
 105cb70:	49 89 c5             	mov    %rax,%r13
 105cb73:	48 89 d3             	mov    %rdx,%rbx
 105cb76:	be 08 00 00 00       	mov    $0x8,%esi
 105cb7b:	48 89 d7             	mov    %rdx,%rdi
 105cb7e:	e8 3d 76 fc ff       	call   10241c0 <myl_core_list_copy>
 105cb83:	49 89 c7             	mov    %rax,%r15
 105cb86:	48 c7 84 24 38 06 00 	movq   $0x4,0x638(%rsp)
 105cb8d:	00 04 00 00 00 
 105cb92:	4c 89 ac 24 40 06 00 	mov    %r13,0x640(%rsp)
 105cb99:	00 
 105cb9a:	48 89 84 24 48 06 00 	mov    %rax,0x648(%rsp)
 105cba1:	00 
 105cba2:	48 8d bc 24 60 03 00 	lea    0x360(%rsp),%rdi
 105cba9:	00 
 105cbaa:	48 8d 94 24 38 06 00 	lea    0x638(%rsp),%rdx
 105cbb1:	00 
 105cbb2:	4c 89 f6             	mov    %r14,%rsi
 105cbb5:	e8 a6 e1 ff ff       	call   105ad60 <my.heap::allocate>
 105cbba:	4c 89 ff             	mov    %r15,%rdi
 105cbbd:	e8 3e 77 fc ff       	call   1024300 <myl_core_drop_owned>
 105cbc2:	48 8b bc 24 60 03 00 	mov    0x360(%rsp),%rdi
 105cbc9:	00 
 105cbca:	49 8b 46 78          	mov    0x78(%r14),%rax
 105cbce:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105cbd5:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cbd9:	48 89 f1             	mov    %rsi,%rcx
 105cbdc:	48 39 d6             	cmp    %rdx,%rsi
 105cbdf:	0f 83 3c 16 00 00    	jae    105e221 <my.vm::run+0x2cf1>
 105cbe5:	48 c1 e1 04          	shl    $0x4,%rcx
 105cbe9:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 105cbf0:	00 00 
 105cbf2:	48 89 7c 24 50       	mov    %rdi,0x50(%rsp)
 105cbf7:	48 89 7c 08 28       	mov    %rdi,0x28(%rax,%rcx,1)
 105cbfc:	48 89 f0             	mov    %rsi,%rax
 105cbff:	48 ff c0             	inc    %rax
 105cc02:	0f 80 10 1f 00 00    	jo     105eb18 <my.vm::run+0x35e8>
 105cc08:	4c 89 6c 24 58       	mov    %r13,0x58(%rsp)
 105cc0d:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105cc14:	be 08 00 00 00       	mov    $0x8,%esi
 105cc19:	48 89 df             	mov    %rbx,%rdi
 105cc1c:	e8 9f 75 fc ff       	call   10241c0 <myl_core_list_copy>
 105cc21:	48 89 44 24 38       	mov    %rax,0x38(%rsp)
 105cc26:	48 89 df             	mov    %rbx,%rdi
 105cc29:	e8 d2 76 fc ff       	call   1024300 <myl_core_drop_owned>
 105cc2e:	48 83 7c 24 10 00    	cmpq   $0x0,0x10(%rsp)
 105cc34:	0f 8e 7b 0c 00 00    	jle    105d8b5 <my.vm::run+0x2385>
 105cc3a:	45 31 ed             	xor    %r13d,%r13d
 105cc3d:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105cc42:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105cc47:	49 89 eb             	mov    %rbp,%r11
 105cc4a:	eb 3e                	jmp    105cc8a <my.vm::run+0x175a>
 105cc4c:	49 89 9e 98 00 00 00 	mov    %rbx,0x98(%r14)
 105cc53:	48 8b 44 24 38       	mov    0x38(%rsp),%rax
 105cc58:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cc5c:	49 39 d5             	cmp    %rdx,%r13
 105cc5f:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105cc64:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105cc69:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105cc6e:	0f 83 2d 1a 00 00    	jae    105e6a1 <my.vm::run+0x3171>
 105cc74:	4a 89 5c e8 20       	mov    %rbx,0x20(%rax,%r13,8)
 105cc79:	49 ff c5             	inc    %r13
 105cc7c:	4c 3b 6c 24 10       	cmp    0x10(%rsp),%r13
 105cc81:	49 89 ec             	mov    %rbp,%r12
 105cc84:	0f 84 38 0c 00 00    	je     105d8c2 <my.vm::run+0x2392>
 105cc8a:	48 8d bc 24 90 01 00 	lea    0x190(%rsp),%rdi
 105cc91:	00 
 105cc92:	4c 89 f6             	mov    %r14,%rsi
 105cc95:	4c 89 da             	mov    %r11,%rdx
 105cc98:	4c 89 e1             	mov    %r12,%rcx
 105cc9b:	e8 e0 6e 00 00       	call   1063b80 <my.vm::read_byte>
 105cca0:	48 8b 9c 24 90 01 00 	mov    0x190(%rsp),%rbx
 105cca7:	00 
 105cca8:	48 8b 94 24 98 01 00 	mov    0x198(%rsp),%rdx
 105ccaf:	00 
 105ccb0:	48 8b 8c 24 a0 01 00 	mov    0x1a0(%rsp),%rcx
 105ccb7:	00 
 105ccb8:	4c 8b 84 24 a8 01 00 	mov    0x1a8(%rsp),%r8
 105ccbf:	00 
 105ccc0:	4c 8b 8c 24 b0 01 00 	mov    0x1b0(%rsp),%r9
 105ccc7:	00 
 105ccc8:	48 8d bc 24 a8 02 00 	lea    0x2a8(%rsp),%rdi
 105cccf:	00 
 105ccd0:	4c 89 f6             	mov    %r14,%rsi
 105ccd3:	e8 a8 6e 00 00       	call   1063b80 <my.vm::read_byte>
 105ccd8:	48 8b 94 24 a8 02 00 	mov    0x2a8(%rsp),%rdx
 105ccdf:	00 
 105cce0:	48 8b 84 24 b0 02 00 	mov    0x2b0(%rsp),%rax
 105cce7:	00 
 105cce8:	48 8b ac 24 b8 02 00 	mov    0x2b8(%rsp),%rbp
 105ccef:	00 
 105ccf0:	4c 8b a4 24 c0 02 00 	mov    0x2c0(%rsp),%r12
 105ccf7:	00 
 105ccf8:	48 8b b4 24 c8 02 00 	mov    0x2c8(%rsp),%rsi
 105ccff:	00 
 105cd00:	48 83 fb 01          	cmp    $0x1,%rbx
 105cd04:	0f 85 e6 00 00 00    	jne    105cdf0 <my.vm::run+0x18c0>
 105cd0a:	49 89 f7             	mov    %rsi,%r15
 105cd0d:	49 01 d7             	add    %rdx,%r15
 105cd10:	0f 80 7f 19 00 00    	jo     105e695 <my.vm::run+0x3165>
 105cd16:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
 105cd1b:	4c 89 64 24 20       	mov    %r12,0x20(%rsp)
 105cd20:	48 89 74 24 18       	mov    %rsi,0x18(%rsp)
 105cd25:	49 8b 9e 98 00 00 00 	mov    0x98(%r14),%rbx
 105cd2c:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105cd30:	0f 84 f6 00 00 00    	je     105ce2c <my.vm::run+0x18fc>
 105cd36:	48 8d bc 24 28 05 00 	lea    0x528(%rsp),%rdi
 105cd3d:	00 
 105cd3e:	4c 89 f6             	mov    %r14,%rsi
 105cd41:	48 89 da             	mov    %rbx,%rdx
 105cd44:	e8 67 dd 00 00       	call   106aab0 <my.heap::upvalue_obj>
 105cd49:	49 c7 c4 ff ff ff ff 	mov    $0xffffffffffffffff,%r12
 105cd50:	4c 39 bc 24 28 05 00 	cmp    %r15,0x528(%rsp)
 105cd57:	00 
 105cd58:	7e 6b                	jle    105cdc5 <my.vm::run+0x1895>
 105cd5a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105cd61:	0f 1f 84 00 00 00 00 
 105cd68:	00 
 105cd69:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105cd70:	0f 1f 84 00 00 00 00 
 105cd77:	00 
 105cd78:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 105cd7f:	00 
 105cd80:	49 89 dc             	mov    %rbx,%r12
 105cd83:	48 8d bc 24 08 05 00 	lea    0x508(%rsp),%rdi
 105cd8a:	00 
 105cd8b:	4c 89 f6             	mov    %r14,%rsi
 105cd8e:	48 89 da             	mov    %rbx,%rdx
 105cd91:	e8 1a dd 00 00       	call   106aab0 <my.heap::upvalue_obj>
 105cd96:	48 8b 9c 24 20 05 00 	mov    0x520(%rsp),%rbx
 105cd9d:	00 
 105cd9e:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105cda2:	0f 84 94 00 00 00    	je     105ce3c <my.vm::run+0x190c>
 105cda8:	48 8d bc 24 e8 04 00 	lea    0x4e8(%rsp),%rdi
 105cdaf:	00 
 105cdb0:	4c 89 f6             	mov    %r14,%rsi
 105cdb3:	48 89 da             	mov    %rbx,%rdx
 105cdb6:	e8 f5 dc 00 00       	call   106aab0 <my.heap::upvalue_obj>
 105cdbb:	4c 39 bc 24 e8 04 00 	cmp    %r15,0x4e8(%rsp)
 105cdc2:	00 
 105cdc3:	7f bb                	jg     105cd80 <my.vm::run+0x1850>
 105cdc5:	48 8d bc 24 c8 04 00 	lea    0x4c8(%rsp),%rdi
 105cdcc:	00 
 105cdcd:	4c 89 f6             	mov    %r14,%rsi
 105cdd0:	48 89 da             	mov    %rbx,%rdx
 105cdd3:	e8 d8 dc 00 00       	call   106aab0 <my.heap::upvalue_obj>
 105cdd8:	4c 39 bc 24 c8 04 00 	cmp    %r15,0x4c8(%rsp)
 105cddf:	00 
 105cde0:	0f 84 6d fe ff ff    	je     105cc53 <my.vm::run+0x1723>
 105cde6:	eb 5b                	jmp    105ce43 <my.vm::run+0x1913>
 105cde8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 105cdef:	00 
 105cdf0:	49 89 f7             	mov    %rsi,%r15
 105cdf3:	4c 89 f7             	mov    %r14,%rdi
 105cdf6:	49 89 c6             	mov    %rax,%r14
 105cdf9:	48 89 c6             	mov    %rax,%rsi
 105cdfc:	e8 af dd 00 00       	call   106abb0 <my.heap::closure_upvalue>
 105ce01:	48 89 c3             	mov    %rax,%rbx
 105ce04:	48 8b 44 24 38       	mov    0x38(%rsp),%rax
 105ce09:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ce0d:	49 39 d5             	cmp    %rdx,%r13
 105ce10:	0f 83 9a 18 00 00    	jae    105e6b0 <my.vm::run+0x3180>
 105ce16:	4d 89 f9             	mov    %r15,%r9
 105ce19:	4d 89 e0             	mov    %r12,%r8
 105ce1c:	4d 89 f3             	mov    %r14,%r11
 105ce1f:	4c 8b b4 24 98 00 00 	mov    0x98(%rsp),%r14
 105ce26:	00 
 105ce27:	e9 48 fe ff ff       	jmp    105cc74 <my.vm::run+0x1744>
 105ce2c:	48 c7 c3 ff ff ff ff 	mov    $0xffffffffffffffff,%rbx
 105ce33:	49 c7 c4 ff ff ff ff 	mov    $0xffffffffffffffff,%r12
 105ce3a:	eb 07                	jmp    105ce43 <my.vm::run+0x1913>
 105ce3c:	48 c7 c3 ff ff ff ff 	mov    $0xffffffffffffffff,%rbx
 105ce43:	48 c7 84 24 48 05 00 	movq   $0x5,0x548(%rsp)
 105ce4a:	00 05 00 00 00 
 105ce4f:	4c 89 bc 24 50 05 00 	mov    %r15,0x550(%rsp)
 105ce56:	00 
 105ce57:	48 c7 84 24 58 05 00 	movq   $0x0,0x558(%rsp)
 105ce5e:	00 00 00 00 00 
 105ce63:	48 89 9c 24 68 05 00 	mov    %rbx,0x568(%rsp)
 105ce6a:	00 
 105ce6b:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105ce72:	00 
 105ce73:	48 8d 94 24 48 05 00 	lea    0x548(%rsp),%rdx
 105ce7a:	00 
 105ce7b:	4c 89 f6             	mov    %r14,%rsi
 105ce7e:	e8 dd de ff ff       	call   105ad60 <my.heap::allocate>
 105ce83:	48 8b 9c 24 a0 00 00 	mov    0xa0(%rsp),%rbx
 105ce8a:	00 
 105ce8b:	49 83 fc ff          	cmp    $0xffffffffffffffff,%r12
 105ce8f:	0f 84 b7 fd ff ff    	je     105cc4c <my.vm::run+0x171c>
 105ce95:	48 8d bc 24 20 03 00 	lea    0x320(%rsp),%rdi
 105ce9c:	00 
 105ce9d:	4c 89 f6             	mov    %r14,%rsi
 105cea0:	4c 89 e2             	mov    %r12,%rdx
 105cea3:	e8 08 dc 00 00       	call   106aab0 <my.heap::upvalue_obj>
 105cea8:	48 8b b4 24 30 03 00 	mov    0x330(%rsp),%rsi
 105ceaf:	00 
 105ceb0:	44 0f b6 8c 24 28 03 	movzbl 0x328(%rsp),%r9d
 105ceb7:	00 00 
 105ceb9:	4c 8b 94 24 20 03 00 	mov    0x320(%rsp),%r10
 105cec0:	00 
 105cec1:	4d 8b 06             	mov    (%r14),%r8
 105cec4:	49 8b 50 08          	mov    0x8(%r8),%rdx
 105cec8:	49 39 d4             	cmp    %rdx,%r12
 105cecb:	0f 83 86 00 00 00    	jae    105cf57 <my.vm::run+0x1a27>
 105ced1:	4c 89 e0             	mov    %r12,%rax
 105ced4:	4c 6b d8 38          	imul   $0x38,%rax,%r11
 105ced8:	43 0f b6 54 18 20    	movzbl 0x20(%r8,%r11,1),%edx
 105cede:	4b 8b 44 18 28       	mov    0x28(%r8,%r11,1),%rax
 105cee3:	4b 8b 7c 18 30       	mov    0x30(%r8,%r11,1),%rdi
 105cee8:	4b 8b 4c 18 38       	mov    0x38(%r8,%r11,1),%rcx
 105ceed:	4f 8b 7c 18 40       	mov    0x40(%r8,%r11,1),%r15
 105cef2:	4f 8b 64 18 48       	mov    0x48(%r8,%r11,1),%r12
 105cef7:	4b c7 44 18 20 05 00 	movq   $0x5,0x20(%r8,%r11,1)
 105cefe:	00 00 
 105cf00:	4f 89 54 18 28       	mov    %r10,0x28(%r8,%r11,1)
 105cf05:	45 0f b6 c9          	movzbl %r9b,%r9d
 105cf09:	4f 89 4c 18 30       	mov    %r9,0x30(%r8,%r11,1)
 105cf0e:	4b 89 74 18 38       	mov    %rsi,0x38(%r8,%r11,1)
 105cf13:	4b 89 5c 18 40       	mov    %rbx,0x40(%r8,%r11,1)
 105cf18:	ff ca                	dec    %edx
 105cf1a:	83 fa 08             	cmp    $0x8,%edx
 105cf1d:	0f 87 30 fd ff ff    	ja     105cc53 <my.vm::run+0x1723>
 105cf23:	48 8d 35 3e a5 fa ff 	lea    -0x55ac2(%rip),%rsi        # 1007468 <core_number_pairs+0x208>
 105cf2a:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105cf2e:	48 01 f2             	add    %rsi,%rdx
 105cf31:	ff e2                	jmp    *%rdx
 105cf33:	e8 c8 73 fc ff       	call   1024300 <myl_core_drop_owned>
 105cf38:	e9 16 fd ff ff       	jmp    105cc53 <my.vm::run+0x1723>
 105cf3d:	48 89 cf             	mov    %rcx,%rdi
 105cf40:	e8 bb 73 fc ff       	call   1024300 <myl_core_drop_owned>
 105cf45:	4c 89 ff             	mov    %r15,%rdi
 105cf48:	e8 b3 73 fc ff       	call   1024300 <myl_core_drop_owned>
 105cf4d:	4c 89 e7             	mov    %r12,%rdi
 105cf50:	eb e1                	jmp    105cf33 <my.vm::run+0x1a03>
 105cf52:	48 89 c7             	mov    %rax,%rdi
 105cf55:	eb dc                	jmp    105cf33 <my.vm::run+0x1a03>
 105cf57:	4c 89 e0             	mov    %r12,%rax
 105cf5a:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cf5e:	48 21 d0             	and    %rdx,%rax
 105cf61:	4c 01 e0             	add    %r12,%rax
 105cf64:	48 39 d0             	cmp    %rdx,%rax
 105cf67:	0f 82 67 ff ff ff    	jb     105ced4 <my.vm::run+0x19a4>
 105cf6d:	e9 41 20 00 00       	jmp    105efb3 <my.vm::run+0x3a83>
 105cf72:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105cf79:	48 89 c6             	mov    %rax,%rsi
 105cf7c:	48 ff ce             	dec    %rsi
 105cf7f:	0f 80 0f 1c 00 00    	jo     105eb94 <my.vm::run+0x3664>
 105cf85:	4d 89 cd             	mov    %r9,%r13
 105cf88:	4c 89 44 24 20       	mov    %r8,0x20(%rsp)
 105cf8d:	49 8b 46 78          	mov    0x78(%r14),%rax
 105cf91:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cf95:	49 89 f1             	mov    %rsi,%r9
 105cf98:	49 c1 f9 3f          	sar    $0x3f,%r9
 105cf9c:	49 21 d1             	and    %rdx,%r9
 105cf9f:	48 89 f1             	mov    %rsi,%rcx
 105cfa2:	48 39 d6             	cmp    %rdx,%rsi
 105cfa5:	0f 83 18 10 00 00    	jae    105dfc3 <my.vm::run+0x2a93>
 105cfab:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105cfaf:	48 c1 e1 04          	shl    $0x4,%rcx
 105cfb3:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105cfb9:	48 8b 44 08 28       	mov    0x28(%rax,%rcx,1),%rax
 105cfbe:	41 83 f8 02          	cmp    $0x2,%r8d
 105cfc2:	0f 84 27 0a 00 00    	je     105d9ef <my.vm::run+0x24bf>
 105cfc8:	41 83 f8 03          	cmp    $0x3,%r8d
 105cfcc:	0f 85 7b 0a 00 00    	jne    105da4d <my.vm::run+0x251d>
 105cfd2:	4d 8b 16             	mov    (%r14),%r10
 105cfd5:	49 8b 4a 08          	mov    0x8(%r10),%rcx
 105cfd9:	48 39 c8             	cmp    %rcx,%rax
 105cfdc:	0f 83 da 13 00 00    	jae    105e3bc <my.vm::run+0x2e8c>
 105cfe2:	49 89 c0             	mov    %rax,%r8
 105cfe5:	49 6b c0 38          	imul   $0x38,%r8,%rax
 105cfe9:	41 83 7c 02 20 01    	cmpl   $0x1,0x20(%r10,%rax,1)
 105cfef:	0f 85 58 0a 00 00    	jne    105da4d <my.vm::run+0x251d>
 105cff5:	48 89 f0             	mov    %rsi,%rax
 105cff8:	48 ff c8             	dec    %rax
 105cffb:	0f 80 3c 1e 00 00    	jo     105ee3d <my.vm::run+0x390d>
 105d001:	49 89 c0             	mov    %rax,%r8
 105d004:	48 39 d0             	cmp    %rdx,%rax
 105d007:	0f 83 66 14 00 00    	jae    105e473 <my.vm::run+0x2f43>
 105d00d:	49 c1 e0 04          	shl    $0x4,%r8
 105d011:	42 80 3c 07 03       	cmpb   $0x3,(%rdi,%r8,1)
 105d016:	0f 85 31 0a 00 00    	jne    105da4d <my.vm::run+0x251d>
 105d01c:	4c 89 db             	mov    %r11,%rbx
 105d01f:	4e 8b 44 07 08       	mov    0x8(%rdi,%r8,1),%r8
 105d024:	49 39 c8             	cmp    %rcx,%r8
 105d027:	0f 83 1c 15 00 00    	jae    105e549 <my.vm::run+0x3019>
 105d02d:	4d 89 c3             	mov    %r8,%r11
 105d030:	49 83 c2 20          	add    $0x20,%r10
 105d034:	49 6b cb 38          	imul   $0x38,%r11,%rcx
 105d038:	41 83 3c 0a 01       	cmpl   $0x1,(%r10,%rcx,1)
 105d03d:	49 89 db             	mov    %rbx,%r11
 105d040:	0f 85 07 0a 00 00    	jne    105da4d <my.vm::run+0x251d>
 105d046:	48 39 d6             	cmp    %rdx,%rsi
 105d049:	0f 83 15 15 00 00    	jae    105e564 <my.vm::run+0x3034>
 105d04f:	49 89 f1             	mov    %rsi,%r9
 105d052:	49 c1 e1 04          	shl    $0x4,%r9
 105d056:	42 0f b6 0c 0f       	movzbl (%rdi,%r9,1),%ecx
 105d05b:	83 f9 03             	cmp    $0x3,%ecx
 105d05e:	0f 85 5c 1e 00 00    	jne    105eec0 <my.vm::run+0x3990>
 105d064:	4a 8b 4c 0f 08       	mov    0x8(%rdi,%r9,1),%rcx
 105d069:	48 39 d0             	cmp    %rdx,%rax
 105d06c:	0f 83 03 15 00 00    	jae    105e575 <my.vm::run+0x3045>
 105d072:	48 89 c6             	mov    %rax,%rsi
 105d075:	48 c1 e6 04          	shl    $0x4,%rsi
 105d079:	0f b6 04 37          	movzbl (%rdi,%rsi,1),%eax
 105d07d:	83 f8 03             	cmp    $0x3,%eax
 105d080:	0f 85 57 1e 00 00    	jne    105eedd <my.vm::run+0x39ad>
 105d086:	48 01 f7             	add    %rsi,%rdi
 105d089:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105d08d:	48 8d bc 24 60 03 00 	lea    0x360(%rsp),%rdi
 105d094:	00 
 105d095:	4c 89 f6             	mov    %r14,%rsi
 105d098:	e8 a3 1a 01 00       	call   106eb40 <my.lox_strings::concat>
 105d09d:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105d0a4:	48 89 c6             	mov    %rax,%rsi
 105d0a7:	48 ff ce             	dec    %rsi
 105d0aa:	0f 80 93 1e 00 00    	jo     105ef43 <my.vm::run+0x3a13>
 105d0b0:	48 8b 84 24 60 03 00 	mov    0x360(%rsp),%rax
 105d0b7:	00 
 105d0b8:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105d0bc:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105d0c0:	48 39 d6             	cmp    %rdx,%rsi
 105d0c3:	4d 89 e9             	mov    %r13,%r9
 105d0c6:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105d0cb:	49 89 db             	mov    %rbx,%r11
 105d0ce:	0f 83 bc 14 00 00    	jae    105e590 <my.vm::run+0x3060>
 105d0d4:	49 89 f7             	mov    %rsi,%r15
 105d0d7:	49 ff cf             	dec    %r15
 105d0da:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105d0df:	0f 80 4d 1e 00 00    	jo     105ef32 <my.vm::run+0x3a02>
 105d0e5:	4c 89 fe             	mov    %r15,%rsi
 105d0e8:	49 39 d7             	cmp    %rdx,%r15
 105d0eb:	0f 83 ba 14 00 00    	jae    105e5ab <my.vm::run+0x307b>
 105d0f1:	48 c1 e6 04          	shl    $0x4,%rsi
 105d0f5:	48 c7 44 31 20 03 00 	movq   $0x3,0x20(%rcx,%rsi,1)
 105d0fc:	00 00 
 105d0fe:	48 89 44 31 28       	mov    %rax,0x28(%rcx,%rsi,1)
 105d103:	e9 7f 0a 00 00       	jmp    105db87 <my.vm::run+0x2657>
 105d108:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105d10f:	00 
 105d110:	4c 89 f6             	mov    %r14,%rsi
 105d113:	4c 89 da             	mov    %r11,%rdx
 105d116:	4c 89 e1             	mov    %r12,%rcx
 105d119:	e8 22 6b 00 00       	call   1063c40 <my.vm::read_constant>
 105d11e:	0f b6 84 24 a0 00 00 	movzbl 0xa0(%rsp),%eax
 105d125:	00 
 105d126:	83 f8 03             	cmp    $0x3,%eax
 105d129:	0f 85 a9 16 00 00    	jne    105e7d8 <my.vm::run+0x32a8>
 105d12f:	4c 8b 8c 24 c8 00 00 	mov    0xc8(%rsp),%r9
 105d136:	00 
 105d137:	4c 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%r8
 105d13e:	00 
 105d13f:	48 8b 8c 24 b8 00 00 	mov    0xb8(%rsp),%rcx
 105d146:	00 
 105d147:	48 8b 9c 24 a8 00 00 	mov    0xa8(%rsp),%rbx
 105d14e:	00 
 105d14f:	48 8b 94 24 b0 00 00 	mov    0xb0(%rsp),%rdx
 105d156:	00 
 105d157:	48 8d bc 24 50 04 00 	lea    0x450(%rsp),%rdi
 105d15e:	00 
 105d15f:	4c 89 f6             	mov    %r14,%rsi
 105d162:	e8 19 6a 00 00       	call   1063b80 <my.vm::read_byte>
 105d167:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d16e:	48 85 ed             	test   %rbp,%rbp
 105d171:	7f 04                	jg     105d177 <my.vm::run+0x1c47>
 105d173:	4c 03 68 08          	add    0x8(%rax),%r13
 105d177:	4c 8b 8c 24 50 04 00 	mov    0x450(%rsp),%r9
 105d17e:	00 
 105d17f:	48 8b 8c 24 68 04 00 	mov    0x468(%rsp),%rcx
 105d186:	00 
 105d187:	49 c1 e5 05          	shl    $0x5,%r13
 105d18b:	4a 89 4c 28 30       	mov    %rcx,0x30(%rax,%r13,1)
 105d190:	49 89 86 88 00 00 00 	mov    %rax,0x88(%r14)
 105d197:	4c 89 fe             	mov    %r15,%rsi
 105d19a:	48 ff ce             	dec    %rsi
 105d19d:	0f 80 dd 19 00 00    	jo     105eb80 <my.vm::run+0x3650>
 105d1a3:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105d1aa:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d1ae:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d1b2:	48 39 d6             	cmp    %rdx,%rsi
 105d1b5:	0f 83 9a 0f 00 00    	jae    105e155 <my.vm::run+0x2c25>
 105d1bb:	48 89 f1             	mov    %rsi,%rcx
 105d1be:	48 c1 e1 04          	shl    $0x4,%rcx
 105d1c2:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 105d1c7:	83 fa 03             	cmp    $0x3,%edx
 105d1ca:	0f 85 20 15 00 00    	jne    105e6f0 <my.vm::run+0x31c0>
 105d1d0:	48 01 c8             	add    %rcx,%rax
 105d1d3:	48 83 c0 20          	add    $0x20,%rax
 105d1d7:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105d1db:	48 8d bc 24 28 07 00 	lea    0x728(%rsp),%rdi
 105d1e2:	00 
 105d1e3:	4c 89 f6             	mov    %r14,%rsi
 105d1e6:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105d1eb:	49 89 d8             	mov    %rbx,%r8
 105d1ee:	e8 9d 78 00 00       	call   1064a90 <my.vm::invoke_from_class>
 105d1f3:	f6 84 24 28 07 00 00 	testb  $0x1,0x728(%rsp)
 105d1fa:	01 
 105d1fb:	0f 84 cf 13 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105d201:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105d208:	4c 89 d6             	mov    %r10,%rsi
 105d20b:	48 ff ce             	dec    %rsi
 105d20e:	0f 80 f3 1a 00 00    	jo     105ed07 <my.vm::run+0x37d7>
 105d214:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105d21b:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d222:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d226:	48 39 d6             	cmp    %rdx,%rsi
 105d229:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105d22e:	0f 82 88 04 00 00    	jb     105d6bc <my.vm::run+0x218c>
 105d234:	48 89 f1             	mov    %rsi,%rcx
 105d237:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d23b:	48 21 d1             	and    %rdx,%rcx
 105d23e:	48 01 f1             	add    %rsi,%rcx
 105d241:	48 39 d1             	cmp    %rdx,%rcx
 105d244:	0f 82 75 04 00 00    	jb     105d6bf <my.vm::run+0x218f>
 105d24a:	e9 1e 1f 00 00       	jmp    105f16d <my.vm::run+0x3c3d>
 105d24f:	4c 89 fe             	mov    %r15,%rsi
 105d252:	48 ff ce             	dec    %rsi
 105d255:	0f 80 0f 18 00 00    	jo     105ea6a <my.vm::run+0x353a>
 105d25b:	4c 89 dd             	mov    %r11,%rbp
 105d25e:	4c 89 c3             	mov    %r8,%rbx
 105d261:	4d 89 cd             	mov    %r9,%r13
 105d264:	4c 89 f7             	mov    %r14,%rdi
 105d267:	e8 44 79 00 00       	call   1064bb0 <my.vm::close_upvalues>
 105d26c:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105d273:	49 89 f7             	mov    %rsi,%r15
 105d276:	49 ff cf             	dec    %r15
 105d279:	0f 80 da 17 00 00    	jo     105ea59 <my.vm::run+0x3529>
 105d27f:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105d286:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d28a:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105d291:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d295:	49 39 d7             	cmp    %rdx,%r15
 105d298:	4d 89 e9             	mov    %r13,%r9
 105d29b:	49 89 d8             	mov    %rbx,%r8
 105d29e:	49 89 eb             	mov    %rbp,%r11
 105d2a1:	0f 83 cc 0d 00 00    	jae    105e073 <my.vm::run+0x2b43>
 105d2a7:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105d2ac:	e9 3f 0a 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105d2b1:	4c 89 fe             	mov    %r15,%rsi
 105d2b4:	48 ff ce             	dec    %rsi
 105d2b7:	0f 80 0e 18 00 00    	jo     105eacb <my.vm::run+0x359b>
 105d2bd:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105d2c4:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d2c8:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d2cc:	48 89 f1             	mov    %rsi,%rcx
 105d2cf:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d2d3:	48 21 d1             	and    %rdx,%rcx
 105d2d6:	48 89 f7             	mov    %rsi,%rdi
 105d2d9:	48 39 d6             	cmp    %rdx,%rsi
 105d2dc:	0f 83 f3 0c 00 00    	jae    105dfd5 <my.vm::run+0x2aa5>
 105d2e2:	48 c1 e7 04          	shl    $0x4,%rdi
 105d2e6:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 105d2eb:	4d 89 c2             	mov    %r8,%r10
 105d2ee:	85 d2                	test   %edx,%edx
 105d2f0:	0f 84 a7 07 00 00    	je     105da9d <my.vm::run+0x256d>
 105d2f6:	83 fa 01             	cmp    $0x1,%edx
 105d2f9:	0f 85 a2 07 00 00    	jne    105daa1 <my.vm::run+0x2571>
 105d2ff:	48 8d 14 38          	lea    (%rax,%rdi,1),%rdx
 105d303:	48 83 c2 20          	add    $0x20,%rdx
 105d307:	0f b6 52 08          	movzbl 0x8(%rdx),%edx
 105d30b:	f6 d2                	not    %dl
 105d30d:	80 e2 01             	and    $0x1,%dl
 105d310:	e9 8e 07 00 00       	jmp    105daa3 <my.vm::run+0x2573>
 105d315:	48 8d bc 24 a0 04 00 	lea    0x4a0(%rsp),%rdi
 105d31c:	00 
 105d31d:	4c 89 f6             	mov    %r14,%rsi
 105d320:	4c 89 da             	mov    %r11,%rdx
 105d323:	4c 89 e1             	mov    %r12,%rcx
 105d326:	4d 89 d4             	mov    %r10,%r12
 105d329:	e8 52 68 00 00       	call   1063b80 <my.vm::read_byte>
 105d32e:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d335:	4d 85 e4             	test   %r12,%r12
 105d338:	7f 04                	jg     105d33e <my.vm::run+0x1e0e>
 105d33a:	4c 03 68 08          	add    0x8(%rax),%r13
 105d33e:	4c 8b 8c 24 a0 04 00 	mov    0x4a0(%rsp),%r9
 105d345:	00 
 105d346:	48 8b 8c 24 b8 04 00 	mov    0x4b8(%rsp),%rcx
 105d34d:	00 
 105d34e:	49 c1 e5 05          	shl    $0x5,%r13
 105d352:	4a 89 4c 28 30       	mov    %rcx,0x30(%rax,%r13,1)
 105d357:	49 89 86 88 00 00 00 	mov    %rax,0x88(%r14)
 105d35e:	4c 89 f8             	mov    %r15,%rax
 105d361:	48 ff c8             	dec    %rax
 105d364:	0f 80 02 18 00 00    	jo     105eb6c <my.vm::run+0x363c>
 105d36a:	48 89 c6             	mov    %rax,%rsi
 105d36d:	4c 29 ce             	sub    %r9,%rsi
 105d370:	0f 80 b3 17 00 00    	jo     105eb29 <my.vm::run+0x35f9>
 105d376:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d37a:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d37e:	48 39 d6             	cmp    %rdx,%rsi
 105d381:	0f 83 0c 0d 00 00    	jae    105e093 <my.vm::run+0x2b63>
 105d387:	48 89 f1             	mov    %rsi,%rcx
 105d38a:	48 c1 e1 04          	shl    $0x4,%rcx
 105d38e:	4c 8b 44 08 28       	mov    0x28(%rax,%rcx,1),%r8
 105d393:	8b 4c 08 20          	mov    0x20(%rax,%rcx,1),%ecx
 105d397:	48 8b 84 24 90 00 00 	mov    0x90(%rsp),%rax
 105d39e:	00 
 105d39f:	48 89 04 24          	mov    %rax,(%rsp)
 105d3a3:	48 8d bc 24 18 08 00 	lea    0x818(%rsp),%rdi
 105d3aa:	00 
 105d3ab:	4c 89 f6             	mov    %r14,%rsi
 105d3ae:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105d3b3:	e8 18 70 00 00       	call   10643d0 <my.vm::call_value>
 105d3b8:	f6 84 24 18 08 00 00 	testb  $0x1,0x818(%rsp)
 105d3bf:	01 
 105d3c0:	0f 84 0a 12 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105d3c6:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105d3cd:	4c 89 d6             	mov    %r10,%rsi
 105d3d0:	48 ff ce             	dec    %rsi
 105d3d3:	0f 80 1a 19 00 00    	jo     105ecf3 <my.vm::run+0x37c3>
 105d3d9:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105d3e0:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d3e7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d3eb:	48 39 d6             	cmp    %rdx,%rsi
 105d3ee:	0f 82 c8 02 00 00    	jb     105d6bc <my.vm::run+0x218c>
 105d3f4:	48 89 f1             	mov    %rsi,%rcx
 105d3f7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d3fb:	48 21 d1             	and    %rdx,%rcx
 105d3fe:	48 01 f1             	add    %rsi,%rcx
 105d401:	48 39 d1             	cmp    %rdx,%rcx
 105d404:	0f 82 b5 02 00 00    	jb     105d6bf <my.vm::run+0x218f>
 105d40a:	e9 88 1d 00 00       	jmp    105f197 <my.vm::run+0x3c67>
 105d40f:	4c 89 e1             	mov    %r12,%rcx
 105d412:	4c 8d a4 24 a0 00 00 	lea    0xa0(%rsp),%r12
 105d419:	00 
 105d41a:	4c 89 e7             	mov    %r12,%rdi
 105d41d:	4c 89 f6             	mov    %r14,%rsi
 105d420:	4c 89 da             	mov    %r11,%rdx
 105d423:	e8 18 68 00 00       	call   1063c40 <my.vm::read_constant>
 105d428:	0f b6 84 24 a0 00 00 	movzbl 0xa0(%rsp),%eax
 105d42f:	00 
 105d430:	83 f8 03             	cmp    $0x3,%eax
 105d433:	0f 85 bc 13 00 00    	jne    105e7f5 <my.vm::run+0x32c5>
 105d439:	4c 8b 8c 24 c8 00 00 	mov    0xc8(%rsp),%r9
 105d440:	00 
 105d441:	4c 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%r8
 105d448:	00 
 105d449:	48 8b 8c 24 b8 00 00 	mov    0xb8(%rsp),%rcx
 105d450:	00 
 105d451:	48 8b 84 24 a8 00 00 	mov    0xa8(%rsp),%rax
 105d458:	00 
 105d459:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105d45e:	48 8b 94 24 b0 00 00 	mov    0xb0(%rsp),%rdx
 105d465:	00 
 105d466:	48 8d bc 24 78 04 00 	lea    0x478(%rsp),%rdi
 105d46d:	00 
 105d46e:	4c 89 f6             	mov    %r14,%rsi
 105d471:	e8 0a 67 00 00       	call   1063b80 <my.vm::read_byte>
 105d476:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d47d:	48 85 ed             	test   %rbp,%rbp
 105d480:	7f 04                	jg     105d486 <my.vm::run+0x1f56>
 105d482:	4c 03 68 08          	add    0x8(%rax),%r13
 105d486:	48 8b 9c 24 78 04 00 	mov    0x478(%rsp),%rbx
 105d48d:	00 
 105d48e:	48 8b 8c 24 90 04 00 	mov    0x490(%rsp),%rcx
 105d495:	00 
 105d496:	49 c1 e5 05          	shl    $0x5,%r13
 105d49a:	4a 89 4c 28 30       	mov    %rcx,0x30(%rax,%r13,1)
 105d49f:	49 89 86 88 00 00 00 	mov    %rax,0x88(%r14)
 105d4a6:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105d4ad:	4c 89 f8             	mov    %r15,%rax
 105d4b0:	48 ff c8             	dec    %rax
 105d4b3:	0f 80 9a 14 00 00    	jo     105e953 <my.vm::run+0x3423>
 105d4b9:	48 89 c6             	mov    %rax,%rsi
 105d4bc:	48 29 de             	sub    %rbx,%rsi
 105d4bf:	0f 80 e2 17 00 00    	jo     105eca7 <my.vm::run+0x3777>
 105d4c5:	4d 8b 6e 78          	mov    0x78(%r14),%r13
 105d4c9:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105d4cd:	48 39 d6             	cmp    %rdx,%rsi
 105d4d0:	0f 83 d5 0c 00 00    	jae    105e1ab <my.vm::run+0x2c7b>
 105d4d6:	48 89 f0             	mov    %rsi,%rax
 105d4d9:	48 c1 e0 04          	shl    $0x4,%rax
 105d4dd:	41 80 7c 05 20 03    	cmpb   $0x3,0x20(%r13,%rax,1)
 105d4e3:	0f 85 7e 01 00 00    	jne    105d667 <my.vm::run+0x2137>
 105d4e9:	49 8b 6c 05 28       	mov    0x28(%r13,%rax,1),%rbp
 105d4ee:	49 8b 06             	mov    (%r14),%rax
 105d4f1:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d4f5:	48 89 e9             	mov    %rbp,%rcx
 105d4f8:	48 39 d5             	cmp    %rdx,%rbp
 105d4fb:	0f 83 4f 0e 00 00    	jae    105e350 <my.vm::run+0x2e20>
 105d501:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105d505:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 105d50a:	0f 85 57 01 00 00    	jne    105d667 <my.vm::run+0x2137>
 105d510:	4c 89 f7             	mov    %r14,%rdi
 105d513:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 105d518:	4c 89 e6             	mov    %r12,%rsi
 105d51b:	e8 c0 d1 00 00       	call   106a6e0 <my.heap::string_hash>
 105d520:	4c 89 f7             	mov    %r14,%rdi
 105d523:	48 89 ee             	mov    %rbp,%rsi
 105d526:	4c 89 e2             	mov    %r12,%rdx
 105d529:	89 c1                	mov    %eax,%ecx
 105d52b:	e8 90 d7 00 00       	call   106acc0 <my.heap::instance_field>
 105d530:	3c 01                	cmp    $0x1,%al
 105d532:	0f 85 2d 08 00 00    	jne    105dd65 <my.vm::run+0x2835>
 105d538:	4c 89 f8             	mov    %r15,%rax
 105d53b:	48 29 d8             	sub    %rbx,%rax
 105d53e:	0f 80 6a 19 00 00    	jo     105eeae <my.vm::run+0x397e>
 105d544:	48 89 c6             	mov    %rax,%rsi
 105d547:	48 ff ce             	dec    %rsi
 105d54a:	0f 80 c2 19 00 00    	jo     105ef12 <my.vm::run+0x39e2>
 105d550:	49 89 c8             	mov    %rcx,%r8
 105d553:	49 8b 45 08          	mov    0x8(%r13),%rax
 105d557:	48 39 c6             	cmp    %rax,%rsi
 105d55a:	0f 83 64 0f 00 00    	jae    105e4c4 <my.vm::run+0x2f94>
 105d560:	48 89 f1             	mov    %rsi,%rcx
 105d563:	49 83 c5 20          	add    $0x20,%r13
 105d567:	48 c1 e1 04          	shl    $0x4,%rcx
 105d56b:	0f b6 c2             	movzbl %dl,%eax
 105d56e:	49 89 44 0d 00       	mov    %rax,0x0(%r13,%rcx,1)
 105d573:	4d 89 44 0d 08       	mov    %r8,0x8(%r13,%rcx,1)
 105d578:	48 8b 84 24 90 00 00 	mov    0x90(%rsp),%rax
 105d57f:	00 
 105d580:	48 89 04 24          	mov    %rax,(%rsp)
 105d584:	0f b6 ca             	movzbl %dl,%ecx
 105d587:	4c 8d a4 24 a0 00 00 	lea    0xa0(%rsp),%r12
 105d58e:	00 
 105d58f:	4c 89 e7             	mov    %r12,%rdi
 105d592:	4c 89 f6             	mov    %r14,%rsi
 105d595:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105d59a:	49 89 d9             	mov    %rbx,%r9
 105d59d:	e8 2e 6e 00 00       	call   10643d0 <my.vm::call_value>
 105d5a2:	e9 d7 00 00 00       	jmp    105d67e <my.vm::run+0x214e>
 105d5a7:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105d5ae:	49 89 f7             	mov    %rsi,%r15
 105d5b1:	49 ff cf             	dec    %r15
 105d5b4:	0f 80 7e 16 00 00    	jo     105ec38 <my.vm::run+0x3708>
 105d5ba:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d5be:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d5c2:	4c 89 f9             	mov    %r15,%rcx
 105d5c5:	49 39 d7             	cmp    %rdx,%r15
 105d5c8:	0f 83 19 0a 00 00    	jae    105dfe7 <my.vm::run+0x2ab7>
 105d5ce:	48 c1 e1 04          	shl    $0x4,%rcx
 105d5d2:	80 7c 08 20 02       	cmpb   $0x2,0x20(%rax,%rcx,1)
 105d5d7:	0f 85 ff 00 00 00    	jne    105d6dc <my.vm::run+0x21ac>
 105d5dd:	48 01 c8             	add    %rcx,%rax
 105d5e0:	48 83 c0 20          	add    $0x20,%rax
 105d5e4:	48 c7 00 02 00 00 00 	movq   $0x2,(%rax)
 105d5eb:	80 70 0f 80          	xorb   $0x80,0xf(%rax)
 105d5ef:	e9 93 05 00 00       	jmp    105db87 <my.vm::run+0x2657>
 105d5f4:	4c 89 5c 24 08       	mov    %r11,0x8(%rsp)
 105d5f9:	4c 89 44 24 20       	mov    %r8,0x20(%rsp)
 105d5fe:	4c 89 4c 24 18       	mov    %r9,0x18(%rsp)
 105d603:	48 8d 0d 56 55 fb ff 	lea    -0x4aaaa(%rip),%rcx        # 1012b60 <core_number_pairs+0xb900>
 105d60a:	48 8d 9c 24 60 03 00 	lea    0x360(%rsp),%rbx
 105d611:	00 
 105d612:	48 89 df             	mov    %rbx,%rdi
 105d615:	4c 89 f6             	mov    %r14,%rsi
 105d618:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105d61d:	e8 de 60 00 00       	call   1063700 <my.vm::runtime_error>
 105d622:	f6 03 01             	testb  $0x1,(%rbx)
 105d625:	0f 84 a5 0f 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105d62b:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105d632:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105d639:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105d63e:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105d643:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105d648:	4c 8b 64 24 10       	mov    0x10(%rsp),%r12
 105d64d:	e9 8b 06 00 00       	jmp    105dcdd <my.vm::run+0x27ad>
 105d652:	4c 89 dd             	mov    %r11,%rbp
 105d655:	4c 89 c3             	mov    %r8,%rbx
 105d658:	4d 89 cd             	mov    %r9,%r13
 105d65b:	48 8d 0d fe 56 fb ff 	lea    -0x4a902(%rip),%rcx        # 1012d60 <core_number_pairs+0xbb00>
 105d662:	e9 69 e0 ff ff       	jmp    105b6d0 <my.vm::run+0x1a0>
 105d667:	48 8d 0d b2 56 fb ff 	lea    -0x4a94e(%rip),%rcx        # 1012d20 <core_number_pairs+0xbac0>
 105d66e:	4c 89 e7             	mov    %r12,%rdi
 105d671:	4c 89 f6             	mov    %r14,%rsi
 105d674:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105d679:	e8 82 60 00 00       	call   1063700 <my.vm::runtime_error>
 105d67e:	41 f6 04 24 01       	testb  $0x1,(%r12)
 105d683:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105d688:	0f 84 42 0f 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105d68e:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105d695:	4c 89 d6             	mov    %r10,%rsi
 105d698:	48 ff ce             	dec    %rsi
 105d69b:	0f 80 2a 16 00 00    	jo     105eccb <my.vm::run+0x379b>
 105d6a1:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105d6a8:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d6af:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d6b3:	48 39 d6             	cmp    %rdx,%rsi
 105d6b6:	0f 83 b3 0b 00 00    	jae    105e26f <my.vm::run+0x2d3f>
 105d6bc:	48 89 f1             	mov    %rsi,%rcx
 105d6bf:	48 c1 e1 05          	shl    $0x5,%rcx
 105d6c3:	4c 8b 5c 08 20       	mov    0x20(%rax,%rcx,1),%r11
 105d6c8:	4c 8b 64 08 28       	mov    0x28(%rax,%rcx,1),%r12
 105d6cd:	4c 8b 44 08 30       	mov    0x30(%rax,%rcx,1),%r8
 105d6d2:	4c 8b 4c 08 38       	mov    0x38(%rax,%rcx,1),%r9
 105d6d7:	e9 14 06 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105d6dc:	4c 89 dd             	mov    %r11,%rbp
 105d6df:	4c 89 c3             	mov    %r8,%rbx
 105d6e2:	4d 89 cd             	mov    %r9,%r13
 105d6e5:	48 8d 0d 94 55 fb ff 	lea    -0x4aa6c(%rip),%rcx        # 1012c80 <core_number_pairs+0xba20>
 105d6ec:	e9 df df ff ff       	jmp    105b6d0 <my.vm::run+0x1a0>
 105d6f1:	4c 89 f7             	mov    %r14,%rdi
 105d6f4:	48 89 de             	mov    %rbx,%rsi
 105d6f7:	e8 f4 cd 00 00       	call   106a4f0 <my.heap::string_chars>
 105d6fc:	48 89 c3             	mov    %rax,%rbx
 105d6ff:	48 8d 3d da 53 fb ff 	lea    -0x4ac26(%rip),%rdi        # 1012ae0 <core_number_pairs+0xb880>
 105d706:	48 89 c6             	mov    %rax,%rsi
 105d709:	e8 f2 1f fd ff       	call   102f700 <myl_core_bytes_concat>
 105d70e:	49 89 c7             	mov    %rax,%r15
 105d711:	48 89 df             	mov    %rbx,%rdi
 105d714:	e8 e7 6b fc ff       	call   1024300 <myl_core_drop_owned>
 105d719:	48 8d 35 00 54 fb ff 	lea    -0x4ac00(%rip),%rsi        # 1012b20 <core_number_pairs+0xb8c0>
 105d720:	4c 89 ff             	mov    %r15,%rdi
 105d723:	e8 d8 1f fd ff       	call   102f700 <myl_core_bytes_concat>
 105d728:	48 89 c3             	mov    %rax,%rbx
 105d72b:	4c 89 ff             	mov    %r15,%rdi
 105d72e:	e8 cd 6b fc ff       	call   1024300 <myl_core_drop_owned>
 105d733:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105d73a:	00 
 105d73b:	4c 89 f6             	mov    %r14,%rsi
 105d73e:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105d743:	48 89 d9             	mov    %rbx,%rcx
 105d746:	e8 b5 5f 00 00       	call   1063700 <my.vm::runtime_error>
 105d74b:	48 89 df             	mov    %rbx,%rdi
 105d74e:	e8 ad 6b fc ff       	call   1024300 <myl_core_drop_owned>
 105d753:	f6 84 24 a0 00 00 00 	testb  $0x1,0xa0(%rsp)
 105d75a:	01 
 105d75b:	0f 84 6f 0e 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105d761:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105d768:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105d76f:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105d774:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105d779:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105d77e:	4c 8b 64 24 10       	mov    0x10(%rsp),%r12
 105d783:	4d 89 eb             	mov    %r13,%r11
 105d786:	e9 65 05 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105d78b:	84 d2                	test   %dl,%dl
 105d78d:	0f 85 27 16 00 00    	jne    105edba <my.vm::run+0x388a>
 105d793:	4c 8b 84 24 58 03 00 	mov    0x358(%rsp),%r8
 105d79a:	00 
 105d79b:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105d79f:	48 39 d6             	cmp    %rdx,%rsi
 105d7a2:	49 89 eb             	mov    %rbp,%r11
 105d7a5:	0f 83 db 0b 00 00    	jae    105e386 <my.vm::run+0x2e56>
 105d7ab:	48 89 f0             	mov    %rsi,%rax
 105d7ae:	48 c1 e0 04          	shl    $0x4,%rax
 105d7b2:	c5 f9 10 44 07 20    	vmovupd 0x20(%rdi,%rax,1),%xmm0
 105d7b8:	49 8b 36             	mov    (%r14),%rsi
 105d7bb:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105d7bf:	48 39 d3             	cmp    %rdx,%rbx
 105d7c2:	0f 83 d9 0b 00 00    	jae    105e3a1 <my.vm::run+0x2e71>
 105d7c8:	48 89 d8             	mov    %rbx,%rax
 105d7cb:	4c 6b c8 38          	imul   $0x38,%rax,%r9
 105d7cf:	42 0f b6 54 0e 20    	movzbl 0x20(%rsi,%r9,1),%edx
 105d7d5:	4a 8b 44 0e 28       	mov    0x28(%rsi,%r9,1),%rax
 105d7da:	4a 8b 7c 0e 30       	mov    0x30(%rsi,%r9,1),%rdi
 105d7df:	4a 8b 4c 0e 38       	mov    0x38(%rsi,%r9,1),%rcx
 105d7e4:	4e 8b 7c 0e 40       	mov    0x40(%rsi,%r9,1),%r15
 105d7e9:	4a 8b 5c 0e 48       	mov    0x48(%rsi,%r9,1),%rbx
 105d7ee:	4a c7 44 0e 20 05 00 	movq   $0x5,0x20(%rsi,%r9,1)
 105d7f5:	00 00 
 105d7f7:	4a c7 44 0e 28 ff ff 	movq   $0xffffffffffffffff,0x28(%rsi,%r9,1)
 105d7fe:	ff ff 
 105d800:	c5 f9 54 05 d8 6b fa 	vandpd -0x59428(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105d807:	ff 
 105d808:	c4 a1 79 11 44 0e 30 	vmovupd %xmm0,0x30(%rsi,%r9,1)
 105d80f:	4e 89 44 0e 40       	mov    %r8,0x40(%rsi,%r9,1)
 105d814:	ff ca                	dec    %edx
 105d816:	83 fa 08             	cmp    $0x8,%edx
 105d819:	4d 89 e9             	mov    %r13,%r9
 105d81c:	77 1b                	ja     105d839 <my.vm::run+0x2309>
 105d81e:	48 8d 35 a3 9c fa ff 	lea    -0x5635d(%rip),%rsi        # 10074c8 <core_number_pairs+0x268>
 105d825:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105d829:	48 01 f2             	add    %rsi,%rdx
 105d82c:	ff e2                	jmp    *%rdx
 105d82e:	e8 cd 6a fc ff       	call   1024300 <myl_core_drop_owned>
 105d833:	49 89 eb             	mov    %rbp,%r11
 105d836:	4d 89 e9             	mov    %r13,%r9
 105d839:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105d840:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105d847:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105d84c:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105d851:	e9 9a 04 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105d856:	48 8b 84 24 10 03 00 	mov    0x310(%rsp),%rax
 105d85d:	00 
 105d85e:	0f b6 bc 24 08 03 00 	movzbl 0x308(%rsp),%edi
 105d865:	00 
 105d866:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105d86a:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105d871:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105d875:	49 89 f0             	mov    %rsi,%r8
 105d878:	48 39 d6             	cmp    %rdx,%rsi
 105d87b:	0f 83 ea 0a 00 00    	jae    105e36b <my.vm::run+0x2e3b>
 105d881:	49 c1 e0 04          	shl    $0x4,%r8
 105d885:	40 0f b6 d7          	movzbl %dil,%edx
 105d889:	4a 89 54 01 20       	mov    %rdx,0x20(%rcx,%r8,1)
 105d88e:	4a 89 44 01 28       	mov    %rax,0x28(%rcx,%r8,1)
 105d893:	48 89 f0             	mov    %rsi,%rax
 105d896:	48 ff c0             	inc    %rax
 105d899:	4d 89 f9             	mov    %r15,%r9
 105d89c:	49 89 c7             	mov    %rax,%r15
 105d89f:	4d 89 e8             	mov    %r13,%r8
 105d8a2:	49 89 db             	mov    %rbx,%r11
 105d8a5:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105d8aa:	0f 81 da 02 00 00    	jno    105db8a <my.vm::run+0x265a>
 105d8b0:	e9 19 15 00 00       	jmp    105edce <my.vm::run+0x389e>
 105d8b5:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105d8ba:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105d8bf:	49 89 eb             	mov    %rbp,%r11
 105d8c2:	49 8b 0e             	mov    (%r14),%rcx
 105d8c5:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105d8c9:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 105d8ce:	4d 89 c5             	mov    %r8,%r13
 105d8d1:	48 39 d6             	cmp    %rdx,%rsi
 105d8d4:	0f 83 62 09 00 00    	jae    105e23c <my.vm::run+0x2d0c>
 105d8da:	48 89 f0             	mov    %rsi,%rax
 105d8dd:	4c 6b c0 38          	imul   $0x38,%rax,%r8
 105d8e1:	42 0f b6 54 01 20    	movzbl 0x20(%rcx,%r8,1),%edx
 105d8e7:	4a 8b 7c 01 28       	mov    0x28(%rcx,%r8,1),%rdi
 105d8ec:	4a 8b 74 01 30       	mov    0x30(%rcx,%r8,1),%rsi
 105d8f1:	4a 8b 44 01 38       	mov    0x38(%rcx,%r8,1),%rax
 105d8f6:	4a 8b 5c 01 40       	mov    0x40(%rcx,%r8,1),%rbx
 105d8fb:	4e 8b 7c 01 48       	mov    0x48(%rcx,%r8,1),%r15
 105d900:	4a c7 44 01 20 04 00 	movq   $0x4,0x20(%rcx,%r8,1)
 105d907:	00 00 
 105d909:	4c 8b 54 24 58       	mov    0x58(%rsp),%r10
 105d90e:	4e 89 54 01 28       	mov    %r10,0x28(%rcx,%r8,1)
 105d913:	4c 8b 54 24 38       	mov    0x38(%rsp),%r10
 105d918:	4e 89 54 01 30       	mov    %r10,0x30(%rcx,%r8,1)
 105d91d:	83 fa 09             	cmp    $0x9,%edx
 105d920:	77 2a                	ja     105d94c <my.vm::run+0x241c>
 105d922:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105d927:	0f a3 d1             	bt     %edx,%ecx
 105d92a:	0f 83 8d 00 00 00    	jae    105d9bd <my.vm::run+0x248d>
 105d930:	48 89 f7             	mov    %rsi,%rdi
 105d933:	4c 89 cb             	mov    %r9,%rbx
 105d936:	4d 89 de             	mov    %r11,%r14
 105d939:	e8 c2 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d93e:	4d 89 f3             	mov    %r14,%r11
 105d941:	4c 8b b4 24 98 00 00 	mov    0x98(%rsp),%r14
 105d948:	00 
 105d949:	49 89 d9             	mov    %rbx,%r9
 105d94c:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105d953:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105d95a:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105d95f:	4d 89 e8             	mov    %r13,%r8
 105d962:	e9 89 03 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105d967:	83 fa 01             	cmp    $0x1,%edx
 105d96a:	0f 84 98 e2 ff ff    	je     105bc08 <my.vm::run+0x6d8>
 105d970:	83 fa 02             	cmp    $0x2,%edx
 105d973:	0f 85 97 e2 ff ff    	jne    105bc10 <my.vm::run+0x6e0>
 105d979:	48 89 cf             	mov    %rcx,%rdi
 105d97c:	e8 7f 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d981:	48 89 df             	mov    %rbx,%rdi
 105d984:	e8 77 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d989:	4c 89 ef             	mov    %r13,%rdi
 105d98c:	e9 77 e2 ff ff       	jmp    105bc08 <my.vm::run+0x6d8>
 105d991:	41 83 f8 01          	cmp    $0x1,%r8d
 105d995:	0f 84 25 e0 ff ff    	je     105b9c0 <my.vm::run+0x490>
 105d99b:	41 83 f8 02          	cmp    $0x2,%r8d
 105d99f:	0f 85 25 e0 ff ff    	jne    105b9ca <my.vm::run+0x49a>
 105d9a5:	48 89 c7             	mov    %rax,%rdi
 105d9a8:	e8 53 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d9ad:	48 89 df             	mov    %rbx,%rdi
 105d9b0:	e8 4b 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d9b5:	4c 89 ff             	mov    %r15,%rdi
 105d9b8:	e9 03 e0 ff ff       	jmp    105b9c0 <my.vm::run+0x490>
 105d9bd:	83 fa 01             	cmp    $0x1,%edx
 105d9c0:	0f 84 6d ff ff ff    	je     105d933 <my.vm::run+0x2403>
 105d9c6:	83 fa 02             	cmp    $0x2,%edx
 105d9c9:	75 81                	jne    105d94c <my.vm::run+0x241c>
 105d9cb:	48 89 c7             	mov    %rax,%rdi
 105d9ce:	4c 89 cd             	mov    %r9,%rbp
 105d9d1:	4d 89 de             	mov    %r11,%r14
 105d9d4:	e8 27 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d9d9:	48 89 df             	mov    %rbx,%rdi
 105d9dc:	e8 1f 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d9e1:	4d 89 f3             	mov    %r14,%r11
 105d9e4:	49 89 e9             	mov    %rbp,%r9
 105d9e7:	4c 89 ff             	mov    %r15,%rdi
 105d9ea:	e9 44 ff ff ff       	jmp    105d933 <my.vm::run+0x2403>
 105d9ef:	49 89 f7             	mov    %rsi,%r15
 105d9f2:	49 ff cf             	dec    %r15
 105d9f5:	0f 80 01 14 00 00    	jo     105edfc <my.vm::run+0x38cc>
 105d9fb:	4c 89 f9             	mov    %r15,%rcx
 105d9fe:	49 39 d7             	cmp    %rdx,%r15
 105da01:	0f 83 d0 09 00 00    	jae    105e3d7 <my.vm::run+0x2ea7>
 105da07:	48 c1 e1 04          	shl    $0x4,%rcx
 105da0b:	80 3c 0f 02          	cmpb   $0x2,(%rdi,%rcx,1)
 105da0f:	75 3c                	jne    105da4d <my.vm::run+0x251d>
 105da11:	48 01 cf             	add    %rcx,%rdi
 105da14:	c4 e1 f9 6e c0       	vmovq  %rax,%xmm0
 105da19:	c5 fb 58 47 08       	vaddsd 0x8(%rdi),%xmm0,%xmm0
 105da1e:	48 c7 07 02 00 00 00 	movq   $0x2,(%rdi)
 105da25:	c5 fb 11 47 08       	vmovsd %xmm0,0x8(%rdi)
 105da2a:	49 ff c7             	inc    %r15
 105da2d:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105da34:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105da3b:	4d 89 e9             	mov    %r13,%r9
 105da3e:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105da43:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105da48:	e9 a3 02 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105da4d:	4c 89 db             	mov    %r11,%rbx
 105da50:	48 8d 0d c9 51 fb ff 	lea    -0x4ae37(%rip),%rcx        # 1012c20 <core_number_pairs+0xb9c0>
 105da57:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 105da5e:	00 
 105da5f:	4c 89 f6             	mov    %r14,%rsi
 105da62:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105da67:	e8 94 5c 00 00       	call   1063700 <my.vm::runtime_error>
 105da6c:	f6 84 24 a0 00 00 00 	testb  $0x1,0xa0(%rsp)
 105da73:	01 
 105da74:	0f 84 56 0b 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105da7a:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105da81:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105da88:	4d 89 e9             	mov    %r13,%r9
 105da8b:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105da90:	49 89 db             	mov    %rbx,%r11
 105da93:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105da98:	e9 53 02 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105da9d:	b2 01                	mov    $0x1,%dl
 105da9f:	eb 02                	jmp    105daa3 <my.vm::run+0x2573>
 105daa1:	31 d2                	xor    %edx,%edx
 105daa3:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105daa7:	49 89 f0             	mov    %rsi,%r8
 105daaa:	49 c1 e0 04          	shl    $0x4,%r8
 105daae:	49 01 f8             	add    %rdi,%r8
 105dab1:	48 c1 e1 04          	shl    $0x4,%rcx
 105dab5:	4a c7 04 01 01 00 00 	movq   $0x1,(%rcx,%r8,1)
 105dabc:	00 
 105dabd:	42 88 54 01 08       	mov    %dl,0x8(%rcx,%r8,1)
 105dac2:	49 89 46 78          	mov    %rax,0x78(%r14)
 105dac6:	48 ff c6             	inc    %rsi
 105dac9:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105dad0:	49 89 f7             	mov    %rsi,%r15
 105dad3:	4d 89 d0             	mov    %r10,%r8
 105dad6:	49 89 ea             	mov    %rbp,%r10
 105dad9:	e9 12 02 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105dade:	41 80 f8 01          	cmp    $0x1,%r8b
 105dae2:	4d 89 d1             	mov    %r10,%r9
 105dae5:	0f 85 78 01 00 00    	jne    105dc63 <my.vm::run+0x2733>
 105daeb:	31 fe                	xor    %edi,%esi
 105daed:	40 80 f6 01          	xor    $0x1,%sil
 105daf1:	e9 76 01 00 00       	jmp    105dc6c <my.vm::run+0x273c>
 105daf6:	41 80 f8 02          	cmp    $0x2,%r8b
 105dafa:	0f 85 67 01 00 00    	jne    105dc67 <my.vm::run+0x2737>
 105db00:	c4 e1 f9 6e c6       	vmovq  %rsi,%xmm0
 105db05:	c4 e1 f9 6e cf       	vmovq  %rdi,%xmm1
 105db0a:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 105db0f:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 105db14:	83 e6 01             	and    $0x1,%esi
 105db17:	e9 4d 01 00 00       	jmp    105dc69 <my.vm::run+0x2739>
 105db1c:	48 8d 9c 24 48 05 00 	lea    0x548(%rsp),%rbx
 105db23:	00 
 105db24:	e9 79 01 00 00       	jmp    105dca2 <my.vm::run+0x2772>
 105db29:	41 80 f8 03          	cmp    $0x3,%r8b
 105db2d:	41 0f 94 c0          	sete   %r8b
 105db31:	48 39 fe             	cmp    %rdi,%rsi
 105db34:	40 0f 94 c6          	sete   %sil
 105db38:	44 20 c6             	and    %r8b,%sil
 105db3b:	e9 29 01 00 00       	jmp    105dc69 <my.vm::run+0x2739>
 105db40:	48 8d 9c 24 60 03 00 	lea    0x360(%rsp),%rbx
 105db47:	00 
 105db48:	e9 55 01 00 00       	jmp    105dca2 <my.vm::run+0x2772>
 105db4d:	48 8d 9c 24 38 06 00 	lea    0x638(%rsp),%rbx
 105db54:	00 
 105db55:	e9 48 01 00 00       	jmp    105dca2 <my.vm::run+0x2772>
 105db5a:	c5 f3 5c c0          	vsubsd %xmm0,%xmm1,%xmm0
 105db5e:	eb 1b                	jmp    105db7b <my.vm::run+0x264b>
 105db60:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
 105db64:	48 c7 00 01 00 00 00 	movq   $0x1,(%rax)
 105db6b:	0f 97 40 08          	seta   0x8(%rax)
 105db6f:	eb 16                	jmp    105db87 <my.vm::run+0x2657>
 105db71:	c5 fb 59 c1          	vmulsd %xmm1,%xmm0,%xmm0
 105db75:	eb 04                	jmp    105db7b <my.vm::run+0x264b>
 105db77:	c5 f3 5e c0          	vdivsd %xmm0,%xmm1,%xmm0
 105db7b:	48 c7 00 02 00 00 00 	movq   $0x2,(%rax)
 105db82:	c5 fb 11 40 08       	vmovsd %xmm0,0x8(%rax)
 105db87:	49 ff c7             	inc    %r15
 105db8a:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105db91:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105db98:	e9 53 01 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105db9d:	48 89 cb             	mov    %rcx,%rbx
 105dba0:	49 89 d4             	mov    %rdx,%r12
 105dba3:	48 8b 7c 24 58       	mov    0x58(%rsp),%rdi
 105dba8:	e8 53 67 fc ff       	call   1024300 <myl_core_drop_owned>
 105dbad:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105dbb1:	48 39 d5             	cmp    %rdx,%rbp
 105dbb4:	0f 83 78 08 00 00    	jae    105e432 <my.vm::run+0x2f02>
 105dbba:	48 89 e8             	mov    %rbp,%rax
 105dbbd:	4d 89 e0             	mov    %r12,%r8
 105dbc0:	48 89 de             	mov    %rbx,%rsi
 105dbc3:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105dbc8:	49 83 c7 20          	add    $0x20,%r15
 105dbcc:	4c 6b c8 38          	imul   $0x38,%rax,%r9
 105dbd0:	43 0f b6 0c 0f       	movzbl (%r15,%r9,1),%ecx
 105dbd5:	4b 8b 7c 0f 08       	mov    0x8(%r15,%r9,1),%rdi
 105dbda:	4b 8b 54 0f 10       	mov    0x10(%r15,%r9,1),%rdx
 105dbdf:	4b 8b 44 0f 18       	mov    0x18(%r15,%r9,1),%rax
 105dbe4:	4b 8b 5c 0f 20       	mov    0x20(%r15,%r9,1),%rbx
 105dbe9:	4f 8b 64 0f 28       	mov    0x28(%r15,%r9,1),%r12
 105dbee:	4b c7 04 0f 06 00 00 	movq   $0x6,(%r15,%r9,1)
 105dbf5:	00 
 105dbf6:	4c 8b 54 24 50       	mov    0x50(%rsp),%r10
 105dbfb:	4f 89 54 0f 08       	mov    %r10,0x8(%r15,%r9,1)
 105dc00:	4f 89 44 0f 10       	mov    %r8,0x10(%r15,%r9,1)
 105dc05:	4b 89 74 0f 18       	mov    %rsi,0x18(%r15,%r9,1)
 105dc0a:	83 f9 09             	cmp    $0x9,%ecx
 105dc0d:	4c 8b 7c 24 38       	mov    0x38(%rsp),%r15
 105dc12:	77 1b                	ja     105dc2f <my.vm::run+0x26ff>
 105dc14:	be d0 02 00 00       	mov    $0x2d0,%esi
 105dc19:	0f a3 ce             	bt     %ecx,%esi
 105dc1c:	0f 83 74 01 00 00    	jae    105dd96 <my.vm::run+0x2866>
 105dc22:	48 89 d7             	mov    %rdx,%rdi
 105dc25:	e8 d6 66 fc ff       	call   1024300 <myl_core_drop_owned>
 105dc2a:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105dc2f:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105dc36:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105dc3a:	49 39 d7             	cmp    %rdx,%r15
 105dc3d:	0f 83 15 08 00 00    	jae    105e458 <my.vm::run+0x2f28>
 105dc43:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105dc4a:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105dc4f:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105dc54:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105dc59:	4c 8b 64 24 10       	mov    0x10(%rsp),%r12
 105dc5e:	e9 8d 00 00 00       	jmp    105dcf0 <my.vm::run+0x27c0>
 105dc63:	31 f6                	xor    %esi,%esi
 105dc65:	eb 05                	jmp    105dc6c <my.vm::run+0x273c>
 105dc67:	31 f6                	xor    %esi,%esi
 105dc69:	4d 89 d1             	mov    %r10,%r9
 105dc6c:	4d 89 d8             	mov    %r11,%r8
 105dc6f:	49 89 ea             	mov    %rbp,%r10
 105dc72:	48 01 ca             	add    %rcx,%rdx
 105dc75:	48 c7 02 01 00 00 00 	movq   $0x1,(%rdx)
 105dc7c:	40 80 e6 01          	and    $0x1,%sil
 105dc80:	40 88 72 08          	mov    %sil,0x8(%rdx)
 105dc84:	49 89 46 78          	mov    %rax,0x78(%r14)
 105dc88:	49 ff c7             	inc    %r15
 105dc8b:	4d 89 be 80 00 00 00 	mov    %r15,0x80(%r14)
 105dc92:	49 89 db             	mov    %rbx,%r11
 105dc95:	4c 89 eb             	mov    %r13,%rbx
 105dc98:	eb 56                	jmp    105dcf0 <my.vm::run+0x27c0>
 105dc9a:	48 8d 9c 24 a0 00 00 	lea    0xa0(%rsp),%rbx
 105dca1:	00 
 105dca2:	48 8d 0d f7 4e fb ff 	lea    -0x4b109(%rip),%rcx        # 1012ba0 <core_number_pairs+0xb940>
 105dca9:	48 89 df             	mov    %rbx,%rdi
 105dcac:	4c 89 f6             	mov    %r14,%rsi
 105dcaf:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105dcb4:	e8 47 5a 00 00       	call   1063700 <my.vm::runtime_error>
 105dcb9:	f6 03 01             	testb  $0x1,(%rbx)
 105dcbc:	0f 84 0e 09 00 00    	je     105e5d0 <my.vm::run+0x30a0>
 105dcc2:	4d 8b be 80 00 00 00 	mov    0x80(%r14),%r15
 105dcc9:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105dcd0:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105dcd5:	4d 89 e9             	mov    %r13,%r9
 105dcd8:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105dcdd:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105dce2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105dce9:	1f 84 00 00 00 00 00 
 105dcf0:	4c 89 d6             	mov    %r10,%rsi
 105dcf3:	48 ff ce             	dec    %rsi
 105dcf6:	0f 80 40 09 00 00    	jo     105e63c <my.vm::run+0x310c>
 105dcfc:	4c 89 d5             	mov    %r10,%rbp
 105dcff:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105dd06:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dd0a:	48 39 d6             	cmp    %rdx,%rsi
 105dd0d:	0f 82 9d d8 ff ff    	jb     105b5b0 <my.vm::run+0x80>
 105dd13:	48 89 f0             	mov    %rsi,%rax
 105dd16:	48 c1 f8 3f          	sar    $0x3f,%rax
 105dd1a:	48 21 d0             	and    %rdx,%rax
 105dd1d:	48 01 f0             	add    %rsi,%rax
 105dd20:	48 39 d0             	cmp    %rdx,%rax
 105dd23:	0f 82 87 d8 ff ff    	jb     105b5b0 <my.vm::run+0x80>
 105dd29:	e9 6d 12 00 00       	jmp    105ef9b <my.vm::run+0x3a6b>
 105dd2e:	4c 89 f7             	mov    %r14,%rdi
 105dd31:	48 89 de             	mov    %rbx,%rsi
 105dd34:	e8 77 d0 00 00       	call   106adb0 <my.heap::instance_class>
 105dd39:	48 8d 9c 24 a0 00 00 	lea    0xa0(%rsp),%rbx
 105dd40:	00 
 105dd41:	48 89 df             	mov    %rbx,%rdi
 105dd44:	4c 89 f6             	mov    %r14,%rsi
 105dd47:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105dd4c:	48 89 c1             	mov    %rax,%rcx
 105dd4f:	4d 89 f8             	mov    %r15,%r8
 105dd52:	e8 c9 5f 00 00       	call   1063d20 <my.vm::bind_method>
 105dd57:	f6 03 01             	testb  $0x1,(%rbx)
 105dd5a:	0f 85 cb f8 ff ff    	jne    105d62b <my.vm::run+0x20fb>
 105dd60:	e9 6b 08 00 00       	jmp    105e5d0 <my.vm::run+0x30a0>
 105dd65:	4c 89 f7             	mov    %r14,%rdi
 105dd68:	48 89 ee             	mov    %rbp,%rsi
 105dd6b:	e8 40 d0 00 00       	call   106adb0 <my.heap::instance_class>
 105dd70:	4d 89 e0             	mov    %r12,%r8
 105dd73:	4c 8d a4 24 a0 00 00 	lea    0xa0(%rsp),%r12
 105dd7a:	00 
 105dd7b:	4c 89 e7             	mov    %r12,%rdi
 105dd7e:	4c 89 f6             	mov    %r14,%rsi
 105dd81:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 105dd86:	48 89 c1             	mov    %rax,%rcx
 105dd89:	49 89 d9             	mov    %rbx,%r9
 105dd8c:	e8 ff 6c 00 00       	call   1064a90 <my.vm::invoke_from_class>
 105dd91:	e9 e8 f8 ff ff       	jmp    105d67e <my.vm::run+0x214e>
 105dd96:	83 f9 01             	cmp    $0x1,%ecx
 105dd99:	0f 84 86 fe ff ff    	je     105dc25 <my.vm::run+0x26f5>
 105dd9f:	83 f9 02             	cmp    $0x2,%ecx
 105dda2:	0f 85 87 fe ff ff    	jne    105dc2f <my.vm::run+0x26ff>
 105dda8:	48 89 c7             	mov    %rax,%rdi
 105ddab:	e8 50 65 fc ff       	call   1024300 <myl_core_drop_owned>
 105ddb0:	48 89 df             	mov    %rbx,%rdi
 105ddb3:	e8 48 65 fc ff       	call   1024300 <myl_core_drop_owned>
 105ddb8:	4c 89 e7             	mov    %r12,%rdi
 105ddbb:	e9 65 fe ff ff       	jmp    105dc25 <my.vm::run+0x26f5>
 105ddc0:	48 89 cf             	mov    %rcx,%rdi
 105ddc3:	e8 38 65 fc ff       	call   1024300 <myl_core_drop_owned>
 105ddc8:	4c 89 ff             	mov    %r15,%rdi
 105ddcb:	e8 30 65 fc ff       	call   1024300 <myl_core_drop_owned>
 105ddd0:	48 89 df             	mov    %rbx,%rdi
 105ddd3:	e9 56 fa ff ff       	jmp    105d82e <my.vm::run+0x22fe>
 105ddd8:	48 89 c7             	mov    %rax,%rdi
 105dddb:	e9 4e fa ff ff       	jmp    105d82e <my.vm::run+0x22fe>
 105dde0:	83 fe 01             	cmp    $0x1,%esi
 105dde3:	0f 84 1b ea ff ff    	je     105c804 <my.vm::run+0x12d4>
 105dde9:	83 fe 02             	cmp    $0x2,%esi
 105ddec:	0f 85 1c ea ff ff    	jne    105c80e <my.vm::run+0x12de>
 105ddf2:	48 89 c7             	mov    %rax,%rdi
 105ddf5:	e8 06 65 fc ff       	call   1024300 <myl_core_drop_owned>
 105ddfa:	4c 89 ef             	mov    %r13,%rdi
 105ddfd:	e8 fe 64 fc ff       	call   1024300 <myl_core_drop_owned>
 105de02:	48 89 ef             	mov    %rbp,%rdi
 105de05:	e9 fa e9 ff ff       	jmp    105c804 <my.vm::run+0x12d4>
 105de0a:	48 89 f7             	mov    %rsi,%rdi
 105de0d:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105de11:	48 21 d7             	and    %rdx,%rdi
 105de14:	48 01 f7             	add    %rsi,%rdi
 105de17:	48 39 d7             	cmp    %rdx,%rdi
 105de1a:	0f 82 3a d8 ff ff    	jb     105b65a <my.vm::run+0x12a>
 105de20:	e9 82 11 00 00       	jmp    105efa7 <my.vm::run+0x3a77>
 105de25:	4c 89 fe             	mov    %r15,%rsi
 105de28:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105de2c:	48 21 d6             	and    %rdx,%rsi
 105de2f:	4c 01 fe             	add    %r15,%rsi
 105de32:	48 39 d6             	cmp    %rdx,%rsi
 105de35:	0f 82 48 d8 ff ff    	jb     105b683 <my.vm::run+0x153>
 105de3b:	e9 82 11 00 00       	jmp    105efc2 <my.vm::run+0x3a92>
 105de40:	4c 89 f9             	mov    %r15,%rcx
 105de43:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105de47:	48 21 d1             	and    %rdx,%rcx
 105de4a:	4c 01 f9             	add    %r15,%rcx
 105de4d:	48 39 d1             	cmp    %rdx,%rcx
 105de50:	0f 82 76 e3 ff ff    	jb     105c1cc <my.vm::run+0xc9c>
 105de56:	e9 d8 11 00 00       	jmp    105f033 <my.vm::run+0x3b03>
 105de5b:	4c 89 f9             	mov    %r15,%rcx
 105de5e:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105de62:	48 21 d1             	and    %rdx,%rcx
 105de65:	4c 01 f9             	add    %r15,%rcx
 105de68:	48 39 d1             	cmp    %rdx,%rcx
 105de6b:	0f 82 32 e4 ff ff    	jb     105c2a3 <my.vm::run+0xd73>
 105de71:	e9 5b 11 00 00       	jmp    105efd1 <my.vm::run+0x3aa1>
 105de76:	4c 89 f9             	mov    %r15,%rcx
 105de79:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105de7d:	48 21 d1             	and    %rdx,%rcx
 105de80:	4c 01 f9             	add    %r15,%rcx
 105de83:	48 39 d1             	cmp    %rdx,%rcx
 105de86:	0f 82 72 e5 ff ff    	jb     105c3fe <my.vm::run+0xece>
 105de8c:	e9 7c 12 00 00       	jmp    105f10d <my.vm::run+0x3bdd>
 105de91:	4c 89 f9             	mov    %r15,%rcx
 105de94:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105de98:	48 21 d1             	and    %rdx,%rcx
 105de9b:	4c 01 f9             	add    %r15,%rcx
 105de9e:	48 39 d1             	cmp    %rdx,%rcx
 105dea1:	0f 82 95 e5 ff ff    	jb     105c43c <my.vm::run+0xf0c>
 105dea7:	e9 10 12 00 00       	jmp    105f0bc <my.vm::run+0x3b8c>
 105deac:	48 89 f7             	mov    %rsi,%rdi
 105deaf:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105deb3:	48 21 c7             	and    %rax,%rdi
 105deb6:	48 01 f7             	add    %rsi,%rdi
 105deb9:	48 39 c7             	cmp    %rax,%rdi
 105debc:	49 89 ea             	mov    %rbp,%r10
 105debf:	0f 82 95 db ff ff    	jb     105ba5a <my.vm::run+0x52a>
 105dec5:	e9 5a 11 00 00       	jmp    105f024 <my.vm::run+0x3af4>
 105deca:	48 89 f1             	mov    %rsi,%rcx
 105decd:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ded1:	48 21 d1             	and    %rdx,%rcx
 105ded4:	48 01 f1             	add    %rsi,%rcx
 105ded7:	48 39 d1             	cmp    %rdx,%rcx
 105deda:	0f 82 8e de ff ff    	jb     105bd6e <my.vm::run+0x83e>
 105dee0:	e9 ba 11 00 00       	jmp    105f09f <my.vm::run+0x3b6f>
 105dee5:	48 89 f0             	mov    %rsi,%rax
 105dee8:	48 c1 f8 3f          	sar    $0x3f,%rax
 105deec:	48 21 d0             	and    %rdx,%rax
 105deef:	48 01 f0             	add    %rsi,%rax
 105def2:	48 39 d0             	cmp    %rdx,%rax
 105def5:	0f 82 29 e0 ff ff    	jb     105bf24 <my.vm::run+0x9f4>
 105defb:	e9 fd 12 00 00       	jmp    105f1fd <my.vm::run+0x3ccd>
 105df00:	4d 89 d5             	mov    %r10,%r13
 105df03:	49 c1 fd 3f          	sar    $0x3f,%r13
 105df07:	49 21 d5             	and    %rdx,%r13
 105df0a:	4d 01 d5             	add    %r10,%r13
 105df0d:	49 39 d5             	cmp    %rdx,%r13
 105df10:	0f 82 43 e0 ff ff    	jb     105bf59 <my.vm::run+0xa29>
 105df16:	e9 01 12 00 00       	jmp    105f11c <my.vm::run+0x3bec>
 105df1b:	48 89 f1             	mov    %rsi,%rcx
 105df1e:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105df22:	48 21 d1             	and    %rdx,%rcx
 105df25:	48 01 f1             	add    %rsi,%rcx
 105df28:	48 39 d1             	cmp    %rdx,%rcx
 105df2b:	0f 82 ef e2 ff ff    	jb     105c220 <my.vm::run+0xcf0>
 105df31:	e9 6d 12 00 00       	jmp    105f1a3 <my.vm::run+0x3c73>
 105df36:	48 89 de             	mov    %rbx,%rsi
 105df39:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105df3d:	48 21 d6             	and    %rdx,%rsi
 105df40:	48 01 de             	add    %rbx,%rsi
 105df43:	48 39 d6             	cmp    %rdx,%rsi
 105df46:	0f 82 98 e5 ff ff    	jb     105c4e4 <my.vm::run+0xfb4>
 105df4c:	e9 28 12 00 00       	jmp    105f179 <my.vm::run+0x3c49>
 105df51:	48 89 f1             	mov    %rsi,%rcx
 105df54:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105df58:	48 21 d1             	and    %rdx,%rcx
 105df5b:	48 01 f1             	add    %rsi,%rcx
 105df5e:	48 39 d1             	cmp    %rdx,%rcx
 105df61:	49 89 ea             	mov    %rbp,%r10
 105df64:	0f 82 12 e6 ff ff    	jb     105c57c <my.vm::run+0x104c>
 105df6a:	e9 5c 11 00 00       	jmp    105f0cb <my.vm::run+0x3b9b>
 105df6f:	48 89 f7             	mov    %rsi,%rdi
 105df72:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105df76:	48 21 d7             	and    %rdx,%rdi
 105df79:	48 01 f7             	add    %rsi,%rdi
 105df7c:	48 39 d7             	cmp    %rdx,%rdi
 105df7f:	49 89 ea             	mov    %rbp,%r10
 105df82:	0f 82 3b e9 ff ff    	jb     105c8c3 <my.vm::run+0x1393>
 105df88:	e9 49 12 00 00       	jmp    105f1d6 <my.vm::run+0x3ca6>
 105df8d:	48 89 f1             	mov    %rsi,%rcx
 105df90:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105df94:	48 21 d1             	and    %rdx,%rcx
 105df97:	48 01 f1             	add    %rsi,%rcx
 105df9a:	48 39 d1             	cmp    %rdx,%rcx
 105df9d:	0f 82 53 ea ff ff    	jb     105c9f6 <my.vm::run+0x14c6>
 105dfa3:	e9 9e 11 00 00       	jmp    105f146 <my.vm::run+0x3c16>
 105dfa8:	4c 89 f9             	mov    %r15,%rcx
 105dfab:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105dfaf:	48 21 d1             	and    %rdx,%rcx
 105dfb2:	4c 01 f9             	add    %r15,%rcx
 105dfb5:	48 39 d1             	cmp    %rdx,%rcx
 105dfb8:	0f 82 d4 e5 ff ff    	jb     105c592 <my.vm::run+0x1062>
 105dfbe:	e9 3b 11 00 00       	jmp    105f0fe <my.vm::run+0x3bce>
 105dfc3:	49 8d 0c 31          	lea    (%r9,%rsi,1),%rcx
 105dfc7:	48 39 d1             	cmp    %rdx,%rcx
 105dfca:	0f 82 db ef ff ff    	jb     105cfab <my.vm::run+0x1a7b>
 105dfd0:	e9 56 11 00 00       	jmp    105f12b <my.vm::run+0x3bfb>
 105dfd5:	48 8d 3c 0e          	lea    (%rsi,%rcx,1),%rdi
 105dfd9:	48 39 d7             	cmp    %rdx,%rdi
 105dfdc:	0f 82 00 f3 ff ff    	jb     105d2e2 <my.vm::run+0x1db2>
 105dfe2:	e9 5b 10 00 00       	jmp    105f042 <my.vm::run+0x3b12>
 105dfe7:	4c 89 f9             	mov    %r15,%rcx
 105dfea:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105dfee:	48 21 d1             	and    %rdx,%rcx
 105dff1:	4c 01 f9             	add    %r15,%rcx
 105dff4:	48 39 d1             	cmp    %rdx,%rcx
 105dff7:	0f 82 d1 f5 ff ff    	jb     105d5ce <my.vm::run+0x209e>
 105dffd:	e9 e0 11 00 00       	jmp    105f1e2 <my.vm::run+0x3cb2>
 105e002:	48 89 f0             	mov    %rsi,%rax
 105e005:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e009:	48 21 d0             	and    %rdx,%rax
 105e00c:	48 01 f0             	add    %rsi,%rax
 105e00f:	48 39 d0             	cmp    %rdx,%rax
 105e012:	0f 82 34 d7 ff ff    	jb     105b74c <my.vm::run+0x21c>
 105e018:	e9 d4 11 00 00       	jmp    105f1f1 <my.vm::run+0x3cc1>
 105e01d:	4c 89 f9             	mov    %r15,%rcx
 105e020:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e024:	48 21 d1             	and    %rdx,%rcx
 105e027:	4c 01 f9             	add    %r15,%rcx
 105e02a:	48 39 d1             	cmp    %rdx,%rcx
 105e02d:	0f 82 21 e2 ff ff    	jb     105c254 <my.vm::run+0xd24>
 105e033:	e9 8f 11 00 00       	jmp    105f1c7 <my.vm::run+0x3c97>
 105e038:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 105e03d:	48 89 c8             	mov    %rcx,%rax
 105e040:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e044:	48 21 d0             	and    %rdx,%rax
 105e047:	48 01 c8             	add    %rcx,%rax
 105e04a:	48 39 d0             	cmp    %rdx,%rax
 105e04d:	0f 82 b8 e5 ff ff    	jb     105c60b <my.vm::run+0x10db>
 105e053:	e9 53 10 00 00       	jmp    105f0ab <my.vm::run+0x3b7b>
 105e058:	48 89 f0             	mov    %rsi,%rax
 105e05b:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e05f:	48 21 d0             	and    %rdx,%rax
 105e062:	48 01 f0             	add    %rsi,%rax
 105e065:	48 39 d0             	cmp    %rdx,%rax
 105e068:	0f 82 77 e8 ff ff    	jb     105c8e5 <my.vm::run+0x13b5>
 105e06e:	e9 a5 0f 00 00       	jmp    105f018 <my.vm::run+0x3ae8>
 105e073:	4c 89 f8             	mov    %r15,%rax
 105e076:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e07a:	48 21 d0             	and    %rdx,%rax
 105e07d:	4c 01 f8             	add    %r15,%rax
 105e080:	48 39 d0             	cmp    %rdx,%rax
 105e083:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105e088:	0f 82 62 fc ff ff    	jb     105dcf0 <my.vm::run+0x27c0>
 105e08e:	e9 cd 0f 00 00       	jmp    105f060 <my.vm::run+0x3b30>
 105e093:	48 89 f1             	mov    %rsi,%rcx
 105e096:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e09a:	48 21 d1             	and    %rdx,%rcx
 105e09d:	48 01 f1             	add    %rsi,%rcx
 105e0a0:	48 39 d1             	cmp    %rdx,%rcx
 105e0a3:	0f 82 e1 f2 ff ff    	jb     105d38a <my.vm::run+0x1e5a>
 105e0a9:	e9 35 10 00 00       	jmp    105f0e3 <my.vm::run+0x3bb3>
 105e0ae:	be 20 00 00 00       	mov    $0x20,%esi
 105e0b3:	31 ff                	xor    %edi,%edi
 105e0b5:	e8 86 54 fc ff       	call   1023540 <myl_core_list_new_slow>
 105e0ba:	e9 d9 da ff ff       	jmp    105bb98 <my.vm::run+0x668>
 105e0bf:	4c 89 f9             	mov    %r15,%rcx
 105e0c2:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e0c6:	48 21 d1             	and    %rdx,%rcx
 105e0c9:	4c 01 f9             	add    %r15,%rcx
 105e0cc:	48 39 d1             	cmp    %rdx,%rcx
 105e0cf:	0f 82 d9 da ff ff    	jb     105bbae <my.vm::run+0x67e>
 105e0d5:	e9 ae 10 00 00       	jmp    105f188 <my.vm::run+0x3c58>
 105e0da:	48 89 f1             	mov    %rsi,%rcx
 105e0dd:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e0e1:	48 21 d1             	and    %rdx,%rcx
 105e0e4:	48 01 f1             	add    %rsi,%rcx
 105e0e7:	48 39 d1             	cmp    %rdx,%rcx
 105e0ea:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105e0ef:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105e0f4:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105e0f9:	0f 82 3b db ff ff    	jb     105bc3a <my.vm::run+0x70a>
 105e0ff:	e9 f7 0e 00 00       	jmp    105effb <my.vm::run+0x3acb>
 105e104:	4c 89 c9             	mov    %r9,%rcx
 105e107:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e10b:	48 21 d1             	and    %rdx,%rcx
 105e10e:	4c 01 c9             	add    %r9,%rcx
 105e111:	48 39 d1             	cmp    %rdx,%rcx
 105e114:	0f 82 23 ea ff ff    	jb     105cb3d <my.vm::run+0x160d>
 105e11a:	e9 33 10 00 00       	jmp    105f152 <my.vm::run+0x3c22>
 105e11f:	48 89 f1             	mov    %rsi,%rcx
 105e122:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e126:	48 21 d1             	and    %rdx,%rcx
 105e129:	48 01 f1             	add    %rsi,%rcx
 105e12c:	48 39 d1             	cmp    %rdx,%rcx
 105e12f:	0f 82 b1 db ff ff    	jb     105bce6 <my.vm::run+0x7b6>
 105e135:	e9 81 10 00 00       	jmp    105f1bb <my.vm::run+0x3c8b>
 105e13a:	48 89 f1             	mov    %rsi,%rcx
 105e13d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e141:	48 21 d1             	and    %rdx,%rcx
 105e144:	48 01 f1             	add    %rsi,%rcx
 105e147:	48 39 d1             	cmp    %rdx,%rcx
 105e14a:	0f 82 74 df ff ff    	jb     105c0c4 <my.vm::run+0xb94>
 105e150:	e9 3e 0f 00 00       	jmp    105f093 <my.vm::run+0x3b63>
 105e155:	48 89 f1             	mov    %rsi,%rcx
 105e158:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e15c:	48 21 d1             	and    %rdx,%rcx
 105e15f:	48 01 f1             	add    %rsi,%rcx
 105e162:	48 39 d1             	cmp    %rdx,%rcx
 105e165:	0f 82 53 f0 ff ff    	jb     105d1be <my.vm::run+0x1c8e>
 105e16b:	e9 0b 0f 00 00       	jmp    105f07b <my.vm::run+0x3b4b>
 105e170:	48 89 f0             	mov    %rsi,%rax
 105e173:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e177:	48 21 d0             	and    %rdx,%rax
 105e17a:	48 01 f0             	add    %rsi,%rax
 105e17d:	48 39 d0             	cmp    %rdx,%rax
 105e180:	0f 82 35 d7 ff ff    	jb     105b8bb <my.vm::run+0x38b>
 105e186:	e9 24 10 00 00       	jmp    105f1af <my.vm::run+0x3c7f>
 105e18b:	4c 89 f8             	mov    %r15,%rax
 105e18e:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e192:	48 21 d0             	and    %rdx,%rax
 105e195:	4c 01 f8             	add    %r15,%rax
 105e198:	48 39 d0             	cmp    %rdx,%rax
 105e19b:	4c 8b 64 24 10       	mov    0x10(%rsp),%r12
 105e1a0:	0f 82 4a fb ff ff    	jb     105dcf0 <my.vm::run+0x27c0>
 105e1a6:	e9 35 0e 00 00       	jmp    105efe0 <my.vm::run+0x3ab0>
 105e1ab:	48 89 f0             	mov    %rsi,%rax
 105e1ae:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e1b2:	48 21 d0             	and    %rdx,%rax
 105e1b5:	48 01 f0             	add    %rsi,%rax
 105e1b8:	48 39 d0             	cmp    %rdx,%rax
 105e1bb:	0f 82 18 f3 ff ff    	jb     105d4d9 <my.vm::run+0x1fa9>
 105e1c1:	e9 c1 0e 00 00       	jmp    105f087 <my.vm::run+0x3b57>
 105e1c6:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 105e1cb:	48 89 c8             	mov    %rcx,%rax
 105e1ce:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e1d2:	48 21 d0             	and    %rdx,%rax
 105e1d5:	48 01 c8             	add    %rcx,%rax
 105e1d8:	48 39 d0             	cmp    %rdx,%rax
 105e1db:	0f 82 32 d7 ff ff    	jb     105b913 <my.vm::run+0x3e3>
 105e1e1:	e9 21 0e 00 00       	jmp    105f007 <my.vm::run+0x3ad7>
 105e1e6:	4c 89 ff             	mov    %r15,%rdi
 105e1e9:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e1ed:	48 21 c7             	and    %rax,%rdi
 105e1f0:	4c 01 ff             	add    %r15,%rdi
 105e1f3:	48 39 c7             	cmp    %rax,%rdi
 105e1f6:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105e1fb:	0f 82 62 d7 ff ff    	jb     105b963 <my.vm::run+0x433>
 105e201:	e9 48 0e 00 00       	jmp    105f04e <my.vm::run+0x3b1e>
 105e206:	4c 89 f8             	mov    %r15,%rax
 105e209:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e20d:	48 21 d0             	and    %rdx,%rax
 105e210:	4c 01 f8             	add    %r15,%rax
 105e213:	48 39 d0             	cmp    %rdx,%rax
 105e216:	0f 82 c7 d7 ff ff    	jb     105b9e3 <my.vm::run+0x4b3>
 105e21c:	e9 16 0f 00 00       	jmp    105f137 <my.vm::run+0x3c07>
 105e221:	48 89 f1             	mov    %rsi,%rcx
 105e224:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e228:	48 21 d1             	and    %rdx,%rcx
 105e22b:	48 01 f1             	add    %rsi,%rcx
 105e22e:	48 39 d1             	cmp    %rdx,%rcx
 105e231:	0f 82 ae e9 ff ff    	jb     105cbe5 <my.vm::run+0x16b5>
 105e237:	e9 33 0e 00 00       	jmp    105f06f <my.vm::run+0x3b3f>
 105e23c:	48 89 f0             	mov    %rsi,%rax
 105e23f:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e243:	48 21 d0             	and    %rdx,%rax
 105e246:	48 01 f0             	add    %rsi,%rax
 105e249:	48 39 d0             	cmp    %rdx,%rax
 105e24c:	0f 82 8b f6 ff ff    	jb     105d8dd <my.vm::run+0x23ad>
 105e252:	e9 80 0e 00 00       	jmp    105f0d7 <my.vm::run+0x3ba7>
 105e257:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e25b:	48 21 d1             	and    %rdx,%rcx
 105e25e:	4c 01 f9             	add    %r15,%rcx
 105e261:	48 39 d1             	cmp    %rdx,%rcx
 105e264:	0f 82 5d db ff ff    	jb     105bdc7 <my.vm::run+0x897>
 105e26a:	e9 80 0e 00 00       	jmp    105f0ef <my.vm::run+0x3bbf>
 105e26f:	48 89 f1             	mov    %rsi,%rcx
 105e272:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e276:	48 21 d1             	and    %rdx,%rcx
 105e279:	48 01 f1             	add    %rsi,%rcx
 105e27c:	48 39 d1             	cmp    %rdx,%rcx
 105e27f:	0f 82 3a f4 ff ff    	jb     105d6bf <my.vm::run+0x218f>
 105e285:	e9 65 0d 00 00       	jmp    105efef <my.vm::run+0x3abf>
 105e28a:	48 89 f1             	mov    %rsi,%rcx
 105e28d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e291:	48 21 d1             	and    %rdx,%rcx
 105e294:	48 01 f1             	add    %rsi,%rcx
 105e297:	48 39 d1             	cmp    %rdx,%rcx
 105e29a:	4d 89 f9             	mov    %r15,%r9
 105e29d:	4d 89 e8             	mov    %r13,%r8
 105e2a0:	49 89 db             	mov    %rbx,%r11
 105e2a3:	0f 82 e5 e6 ff ff    	jb     105c98e <my.vm::run+0x145e>
 105e2a9:	e9 5b 0f 00 00       	jmp    105f209 <my.vm::run+0x3cd9>
 105e2ae:	48 89 f1             	mov    %rsi,%rcx
 105e2b1:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e2b5:	48 21 d1             	and    %rdx,%rcx
 105e2b8:	48 01 f1             	add    %rsi,%rcx
 105e2bb:	48 39 d1             	cmp    %rdx,%rcx
 105e2be:	0f 82 ec e6 ff ff    	jb     105c9b0 <my.vm::run+0x1480>
 105e2c4:	e9 87 0f 00 00       	jmp    105f250 <my.vm::run+0x3d20>
 105e2c9:	48 89 f1             	mov    %rsi,%rcx
 105e2cc:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e2d0:	48 21 d1             	and    %rdx,%rcx
 105e2d3:	48 01 f1             	add    %rsi,%rcx
 105e2d6:	48 39 d1             	cmp    %rdx,%rcx
 105e2d9:	0f 82 f1 db ff ff    	jb     105bed0 <my.vm::run+0x9a0>
 105e2df:	e9 31 0f 00 00       	jmp    105f215 <my.vm::run+0x3ce5>
 105e2e4:	48 89 c1             	mov    %rax,%rcx
 105e2e7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e2eb:	48 21 d1             	and    %rdx,%rcx
 105e2ee:	48 01 c1             	add    %rax,%rcx
 105e2f1:	48 39 d1             	cmp    %rdx,%rcx
 105e2f4:	0f 82 ec db ff ff    	jb     105bee6 <my.vm::run+0x9b6>
 105e2fa:	e9 42 0f 00 00       	jmp    105f241 <my.vm::run+0x3d11>
 105e2ff:	48 89 d9             	mov    %rbx,%rcx
 105e302:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e306:	48 21 d1             	and    %rdx,%rcx
 105e309:	48 01 d9             	add    %rbx,%rcx
 105e30c:	48 39 d1             	cmp    %rdx,%rcx
 105e30f:	0f 82 6c dc ff ff    	jb     105bf81 <my.vm::run+0xa51>
 105e315:	e9 6f 0f 00 00       	jmp    105f289 <my.vm::run+0x3d59>
 105e31a:	48 89 f1             	mov    %rsi,%rcx
 105e31d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e321:	48 21 c1             	and    %rax,%rcx
 105e324:	48 01 f1             	add    %rsi,%rcx
 105e327:	48 39 c1             	cmp    %rax,%rcx
 105e32a:	0f 82 44 d4 ff ff    	jb     105b774 <my.vm::run+0x244>
 105e330:	e9 d8 0f 00 00       	jmp    105f30d <my.vm::run+0x3ddd>
 105e335:	49 89 f0             	mov    %rsi,%r8
 105e338:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e33c:	49 21 c0             	and    %rax,%r8
 105e33f:	49 01 f0             	add    %rsi,%r8
 105e342:	49 39 c0             	cmp    %rax,%r8
 105e345:	0f 82 23 e0 ff ff    	jb     105c36e <my.vm::run+0xe3e>
 105e34b:	e9 0c 0f 00 00       	jmp    105f25c <my.vm::run+0x3d2c>
 105e350:	48 89 e9             	mov    %rbp,%rcx
 105e353:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e357:	48 21 d1             	and    %rdx,%rcx
 105e35a:	48 01 e9             	add    %rbp,%rcx
 105e35d:	48 39 d1             	cmp    %rdx,%rcx
 105e360:	0f 82 9b f1 ff ff    	jb     105d501 <my.vm::run+0x1fd1>
 105e366:	e9 25 10 00 00       	jmp    105f390 <my.vm::run+0x3e60>
 105e36b:	49 89 f0             	mov    %rsi,%r8
 105e36e:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e372:	49 21 d0             	and    %rdx,%r8
 105e375:	49 01 f0             	add    %rsi,%r8
 105e378:	49 39 d0             	cmp    %rdx,%r8
 105e37b:	0f 82 00 f5 ff ff    	jb     105d881 <my.vm::run+0x2351>
 105e381:	e9 7b 0f 00 00       	jmp    105f301 <my.vm::run+0x3dd1>
 105e386:	48 89 f0             	mov    %rsi,%rax
 105e389:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e38d:	48 21 d0             	and    %rdx,%rax
 105e390:	48 01 f0             	add    %rsi,%rax
 105e393:	48 39 d0             	cmp    %rdx,%rax
 105e396:	0f 82 12 f4 ff ff    	jb     105d7ae <my.vm::run+0x227e>
 105e39c:	e9 27 0f 00 00       	jmp    105f2c8 <my.vm::run+0x3d98>
 105e3a1:	48 89 d8             	mov    %rbx,%rax
 105e3a4:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e3a8:	48 21 d0             	and    %rdx,%rax
 105e3ab:	48 01 d8             	add    %rbx,%rax
 105e3ae:	48 39 d0             	cmp    %rdx,%rax
 105e3b1:	0f 82 14 f4 ff ff    	jb     105d7cb <my.vm::run+0x229b>
 105e3b7:	e9 27 0f 00 00       	jmp    105f2e3 <my.vm::run+0x3db3>
 105e3bc:	49 89 c0             	mov    %rax,%r8
 105e3bf:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e3c3:	49 21 c8             	and    %rcx,%r8
 105e3c6:	49 01 c0             	add    %rax,%r8
 105e3c9:	49 39 c8             	cmp    %rcx,%r8
 105e3cc:	0f 82 13 ec ff ff    	jb     105cfe5 <my.vm::run+0x1ab5>
 105e3d2:	e9 c1 0e 00 00       	jmp    105f298 <my.vm::run+0x3d68>
 105e3d7:	4c 89 f9             	mov    %r15,%rcx
 105e3da:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e3de:	48 21 d1             	and    %rdx,%rcx
 105e3e1:	4c 01 f9             	add    %r15,%rcx
 105e3e4:	48 39 d1             	cmp    %rdx,%rcx
 105e3e7:	0f 82 1a f6 ff ff    	jb     105da07 <my.vm::run+0x24d7>
 105e3ed:	e9 2f 0e 00 00       	jmp    105f221 <my.vm::run+0x3cf1>
 105e3f2:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 105e3f7:	48 89 c8             	mov    %rcx,%rax
 105e3fa:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e3fe:	48 21 d0             	and    %rdx,%rax
 105e401:	48 01 c8             	add    %rcx,%rax
 105e404:	48 39 d0             	cmp    %rdx,%rax
 105e407:	0f 82 88 d3 ff ff    	jb     105b795 <my.vm::run+0x265>
 105e40d:	e9 61 0f 00 00       	jmp    105f373 <my.vm::run+0x3e43>
 105e412:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 105e417:	48 89 f0             	mov    %rsi,%rax
 105e41a:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e41e:	48 21 d0             	and    %rdx,%rax
 105e421:	48 01 f0             	add    %rsi,%rax
 105e424:	48 39 d0             	cmp    %rdx,%rax
 105e427:	0f 82 2b e2 ff ff    	jb     105c658 <my.vm::run+0x1128>
 105e42d:	e9 fe 0d 00 00       	jmp    105f230 <my.vm::run+0x3d00>
 105e432:	48 89 e8             	mov    %rbp,%rax
 105e435:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e439:	48 21 d0             	and    %rdx,%rax
 105e43c:	48 01 e8             	add    %rbp,%rax
 105e43f:	48 39 d0             	cmp    %rdx,%rax
 105e442:	4d 89 e0             	mov    %r12,%r8
 105e445:	48 89 de             	mov    %rbx,%rsi
 105e448:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105e44d:	0f 82 75 f7 ff ff    	jb     105dbc8 <my.vm::run+0x2698>
 105e453:	e9 52 0e 00 00       	jmp    105f2aa <my.vm::run+0x3d7a>
 105e458:	4c 89 f8             	mov    %r15,%rax
 105e45b:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e45f:	48 21 d0             	and    %rdx,%rax
 105e462:	4c 01 f8             	add    %r15,%rax
 105e465:	48 39 d0             	cmp    %rdx,%rax
 105e468:	0f 82 d5 f7 ff ff    	jb     105dc43 <my.vm::run+0x2713>
 105e46e:	e9 e2 0e 00 00       	jmp    105f355 <my.vm::run+0x3e25>
 105e473:	49 89 c0             	mov    %rax,%r8
 105e476:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e47a:	49 21 d0             	and    %rdx,%r8
 105e47d:	49 01 c0             	add    %rax,%r8
 105e480:	49 39 d0             	cmp    %rdx,%r8
 105e483:	0f 82 84 eb ff ff    	jb     105d00d <my.vm::run+0x1add>
 105e489:	e9 46 0e 00 00       	jmp    105f2d4 <my.vm::run+0x3da4>
 105e48e:	4c 89 ff             	mov    %r15,%rdi
 105e491:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e495:	48 21 d7             	and    %rdx,%rdi
 105e498:	4c 01 ff             	add    %r15,%rdi
 105e49b:	48 39 d7             	cmp    %rdx,%rdi
 105e49e:	0f 82 46 e2 ff ff    	jb     105c6ea <my.vm::run+0x11ba>
 105e4a4:	e9 49 0e 00 00       	jmp    105f2f2 <my.vm::run+0x3dc2>
 105e4a9:	48 89 f7             	mov    %rsi,%rdi
 105e4ac:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e4b0:	48 21 d7             	and    %rdx,%rdi
 105e4b3:	48 01 f7             	add    %rsi,%rdi
 105e4b6:	48 39 d7             	cmp    %rdx,%rdi
 105e4b9:	0f 82 52 e2 ff ff    	jb     105c711 <my.vm::run+0x11e1>
 105e4bf:	e9 58 0e 00 00       	jmp    105f31c <my.vm::run+0x3dec>
 105e4c4:	48 89 f1             	mov    %rsi,%rcx
 105e4c7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e4cb:	48 21 c1             	and    %rax,%rcx
 105e4ce:	48 01 f1             	add    %rsi,%rcx
 105e4d1:	48 39 c1             	cmp    %rax,%rcx
 105e4d4:	0f 82 89 f0 ff ff    	jb     105d563 <my.vm::run+0x2033>
 105e4da:	e9 da 0d 00 00       	jmp    105f2b9 <my.vm::run+0x3d89>
 105e4df:	48 89 f7             	mov    %rsi,%rdi
 105e4e2:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e4e6:	48 21 c7             	and    %rax,%rdi
 105e4e9:	48 01 f7             	add    %rsi,%rdi
 105e4ec:	48 39 c7             	cmp    %rax,%rdi
 105e4ef:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 105e4f4:	0f 82 ae e2 ff ff    	jb     105c7a8 <my.vm::run+0x1278>
 105e4fa:	e9 6c 0d 00 00       	jmp    105f26b <my.vm::run+0x3d3b>
 105e4ff:	4c 89 f8             	mov    %r15,%rax
 105e502:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e506:	48 21 d0             	and    %rdx,%rax
 105e509:	4c 01 f8             	add    %r15,%rax
 105e50c:	48 39 d0             	cmp    %rdx,%rax
 105e50f:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
 105e514:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 105e519:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 105e51e:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 105e523:	0f 82 09 e3 ff ff    	jb     105c832 <my.vm::run+0x1302>
 105e529:	e9 fa 0d 00 00       	jmp    105f328 <my.vm::run+0x3df8>
 105e52e:	4c 89 f8             	mov    %r15,%rax
 105e531:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e535:	48 21 d0             	and    %rdx,%rax
 105e538:	4c 01 f8             	add    %r15,%rax
 105e53b:	48 39 d0             	cmp    %rdx,%rax
 105e53e:	0f 82 08 e3 ff ff    	jb     105c84c <my.vm::run+0x131c>
 105e544:	e9 1b 0e 00 00       	jmp    105f364 <my.vm::run+0x3e34>
 105e549:	4d 89 c3             	mov    %r8,%r11
 105e54c:	49 c1 fb 3f          	sar    $0x3f,%r11
 105e550:	49 21 cb             	and    %rcx,%r11
 105e553:	4d 01 c3             	add    %r8,%r11
 105e556:	49 39 cb             	cmp    %rcx,%r11
 105e559:	0f 82 d1 ea ff ff    	jb     105d030 <my.vm::run+0x1b00>
 105e55f:	e9 d3 0d 00 00       	jmp    105f337 <my.vm::run+0x3e07>
 105e564:	49 01 f1             	add    %rsi,%r9
 105e567:	49 39 d1             	cmp    %rdx,%r9
 105e56a:	0f 82 e2 ea ff ff    	jb     105d052 <my.vm::run+0x1b22>
 105e570:	e9 0f 0e 00 00       	jmp    105f384 <my.vm::run+0x3e54>
 105e575:	48 89 c6             	mov    %rax,%rsi
 105e578:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e57c:	48 21 d6             	and    %rdx,%rsi
 105e57f:	48 01 c6             	add    %rax,%rsi
 105e582:	48 39 d6             	cmp    %rdx,%rsi
 105e585:	0f 82 ea ea ff ff    	jb     105d075 <my.vm::run+0x1b45>
 105e58b:	e9 ea 0c 00 00       	jmp    105f27a <my.vm::run+0x3d4a>
 105e590:	48 89 f7             	mov    %rsi,%rdi
 105e593:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e597:	48 21 d7             	and    %rdx,%rdi
 105e59a:	48 01 f7             	add    %rsi,%rdi
 105e59d:	48 39 d7             	cmp    %rdx,%rdi
 105e5a0:	0f 82 2e eb ff ff    	jb     105d0d4 <my.vm::run+0x1ba4>
 105e5a6:	e9 9e 0d 00 00       	jmp    105f349 <my.vm::run+0x3e19>
 105e5ab:	4c 89 fe             	mov    %r15,%rsi
 105e5ae:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e5b2:	48 21 d6             	and    %rdx,%rsi
 105e5b5:	4c 01 fe             	add    %r15,%rsi
 105e5b8:	48 39 d6             	cmp    %rdx,%rsi
 105e5bb:	0f 82 30 eb ff ff    	jb     105d0f1 <my.vm::run+0x1bc1>
 105e5c1:	48 8d 3d 38 6e 02 00 	lea    0x26e38(%rip),%rdi        # 1085400 <core_durable_error.verbs+0x4a70>
 105e5c8:	4c 89 fe             	mov    %r15,%rsi
 105e5cb:	e8 b0 6a fc ff       	call   1025080 <myl_core_trap>
 105e5d0:	b9 02 00 00 00       	mov    $0x2,%ecx
 105e5d5:	48 8b 44 24 48       	mov    0x48(%rsp),%rax
 105e5da:	48 89 08             	mov    %rcx,(%rax)
 105e5dd:	48 81 c4 f8 09 00 00 	add    $0x9f8,%rsp
 105e5e4:	5b                   	pop    %rbx
 105e5e5:	41 5c                	pop    %r12
 105e5e7:	41 5d                	pop    %r13
 105e5e9:	41 5e                	pop    %r14
 105e5eb:	41 5f                	pop    %r15
 105e5ed:	5d                   	pop    %rbp
 105e5ee:	c3                   	ret
 105e5ef:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e5f6:	48 89 c6             	mov    %rax,%rsi
 105e5f9:	48 ff ce             	dec    %rsi
 105e5fc:	0f 80 85 09 00 00    	jo     105ef87 <my.vm::run+0x3a57>
 105e602:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e609:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e60d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e611:	48 39 d6             	cmp    %rdx,%rsi
 105e614:	73 3a                	jae    105e650 <my.vm::run+0x3120>
 105e616:	31 c9                	xor    %ecx,%ecx
 105e618:	eb bb                	jmp    105e5d5 <my.vm::run+0x30a5>
 105e61a:	48 89 f1             	mov    %rsi,%rcx
 105e61d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e621:	48 21 d1             	and    %rdx,%rcx
 105e624:	48 01 f1             	add    %rsi,%rcx
 105e627:	48 39 d1             	cmp    %rdx,%rcx
 105e62a:	0f 82 57 cf ff ff    	jb     105b587 <my.vm::run+0x57>
 105e630:	48 8d 3d 49 27 02 00 	lea    0x22749(%rip),%rdi        # 1080d80 <core_durable_error.verbs+0x3f0>
 105e637:	e8 44 6a fc ff       	call   1025080 <myl_core_trap>
 105e63c:	48 8d 3d 0d 2a 02 00 	lea    0x22a0d(%rip),%rdi        # 1081050 <core_durable_error.verbs+0x6c0>
 105e643:	ba 01 00 00 00       	mov    $0x1,%edx
 105e648:	4c 89 d6             	mov    %r10,%rsi
 105e64b:	e8 30 6a fc ff       	call   1025080 <myl_core_trap>
 105e650:	48 89 f0             	mov    %rsi,%rax
 105e653:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e657:	48 21 d0             	and    %rdx,%rax
 105e65a:	48 01 f0             	add    %rsi,%rax
 105e65d:	48 39 d0             	cmp    %rdx,%rax
 105e660:	72 b4                	jb     105e616 <my.vm::run+0x30e6>
 105e662:	48 8d 3d 67 31 02 00 	lea    0x23167(%rip),%rdi        # 10817d0 <core_durable_error.verbs+0xe40>
 105e669:	e8 12 6a fc ff       	call   1025080 <myl_core_trap>
 105e66e:	83 f9 09             	cmp    $0x9,%ecx
 105e671:	0f 87 a4 06 00 00    	ja     105ed1b <my.vm::run+0x37eb>
 105e677:	89 c8                	mov    %ecx,%eax
 105e679:	48 8d 0d c0 8d fa ff 	lea    -0x57240(%rip),%rcx        # 1007440 <core_number_pairs+0x1e0>
 105e680:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105e684:	48 01 c8             	add    %rcx,%rax
 105e687:	ff e0                	jmp    *%rax
 105e689:	48 8d 3d 90 74 02 00 	lea    0x27490(%rip),%rdi        # 1085b20 <core_durable_error.verbs+0x5190>
 105e690:	e8 6b bd fc ff       	call   102a400 <myl_core_assert_fail>
 105e695:	48 8d 3d a4 4b 02 00 	lea    0x24ba4(%rip),%rdi        # 1083240 <core_durable_error.verbs+0x28b0>
 105e69c:	e8 df 69 fc ff       	call   1025080 <myl_core_trap>
 105e6a1:	48 8d 3d c8 4b 02 00 	lea    0x24bc8(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x28e0>
 105e6a8:	4c 89 ee             	mov    %r13,%rsi
 105e6ab:	e8 d0 69 fc ff       	call   1025080 <myl_core_trap>
 105e6b0:	48 8d 3d e9 4b 02 00 	lea    0x24be9(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2910>
 105e6b7:	4c 89 ee             	mov    %r13,%rsi
 105e6ba:	e8 c1 69 fc ff       	call   1025080 <myl_core_trap>
 105e6bf:	48 8d 3d da 45 02 00 	lea    0x245da(%rip),%rdi        # 1082ca0 <core_durable_error.verbs+0x2310>
 105e6c6:	ba 01 00 00 00       	mov    $0x1,%edx
 105e6cb:	48 89 c6             	mov    %rax,%rsi
 105e6ce:	e8 ad 69 fc ff       	call   1025080 <myl_core_trap>
 105e6d3:	83 f8 01             	cmp    $0x1,%eax
 105e6d6:	0f 84 eb 01 00 00    	je     105e8c7 <my.vm::run+0x3397>
 105e6dc:	85 c0                	test   %eax,%eax
 105e6de:	0f 85 ef 01 00 00    	jne    105e8d3 <my.vm::run+0x33a3>
 105e6e4:	48 8d 3d 65 44 02 00 	lea    0x24465(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e6eb:	e8 10 bd fc ff       	call   102a400 <myl_core_assert_fail>
 105e6f0:	83 fa 01             	cmp    $0x1,%edx
 105e6f3:	0f 84 e6 01 00 00    	je     105e8df <my.vm::run+0x33af>
 105e6f9:	85 d2                	test   %edx,%edx
 105e6fb:	0f 85 ea 01 00 00    	jne    105e8eb <my.vm::run+0x33bb>
 105e701:	48 8d 3d 48 44 02 00 	lea    0x24448(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e708:	e8 f3 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e70d:	83 f8 01             	cmp    $0x1,%eax
 105e710:	0f 84 e1 01 00 00    	je     105e8f7 <my.vm::run+0x33c7>
 105e716:	85 c0                	test   %eax,%eax
 105e718:	0f 85 e5 01 00 00    	jne    105e903 <my.vm::run+0x33d3>
 105e71e:	48 8d 3d 2b 44 02 00 	lea    0x2442b(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e725:	e8 d6 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e72a:	83 f8 01             	cmp    $0x1,%eax
 105e72d:	0f 84 dc 01 00 00    	je     105e90f <my.vm::run+0x33df>
 105e733:	85 c0                	test   %eax,%eax
 105e735:	0f 85 e0 01 00 00    	jne    105e91b <my.vm::run+0x33eb>
 105e73b:	48 8d 3d 0e 44 02 00 	lea    0x2440e(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e742:	e8 b9 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e747:	83 f8 01             	cmp    $0x1,%eax
 105e74a:	0f 84 d7 01 00 00    	je     105e927 <my.vm::run+0x33f7>
 105e750:	85 c0                	test   %eax,%eax
 105e752:	0f 85 db 01 00 00    	jne    105e933 <my.vm::run+0x3403>
 105e758:	48 8d 3d f1 43 02 00 	lea    0x243f1(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e75f:	e8 9c bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e764:	83 f8 01             	cmp    $0x1,%eax
 105e767:	0f 84 0e 02 00 00    	je     105e97b <my.vm::run+0x344b>
 105e76d:	85 c0                	test   %eax,%eax
 105e76f:	0f 85 12 02 00 00    	jne    105e987 <my.vm::run+0x3457>
 105e775:	48 8d 3d d4 43 02 00 	lea    0x243d4(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e77c:	e8 7f bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e781:	83 f9 01             	cmp    $0x1,%ecx
 105e784:	0f 84 09 02 00 00    	je     105e993 <my.vm::run+0x3463>
 105e78a:	85 c9                	test   %ecx,%ecx
 105e78c:	0f 85 0d 02 00 00    	jne    105e99f <my.vm::run+0x346f>
 105e792:	48 8d 3d b7 43 02 00 	lea    0x243b7(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e799:	e8 62 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e79e:	83 f8 01             	cmp    $0x1,%eax
 105e7a1:	0f 84 04 02 00 00    	je     105e9ab <my.vm::run+0x347b>
 105e7a7:	85 c0                	test   %eax,%eax
 105e7a9:	0f 85 08 02 00 00    	jne    105e9b7 <my.vm::run+0x3487>
 105e7af:	48 8d 3d 9a 43 02 00 	lea    0x2439a(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e7b6:	e8 45 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e7bb:	83 fa 01             	cmp    $0x1,%edx
 105e7be:	0f 84 ff 01 00 00    	je     105e9c3 <my.vm::run+0x3493>
 105e7c4:	85 d2                	test   %edx,%edx
 105e7c6:	0f 85 03 02 00 00    	jne    105e9cf <my.vm::run+0x349f>
 105e7cc:	48 8d 3d 7d 43 02 00 	lea    0x2437d(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e7d3:	e8 28 bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e7d8:	83 f8 01             	cmp    $0x1,%eax
 105e7db:	0f 84 fa 01 00 00    	je     105e9db <my.vm::run+0x34ab>
 105e7e1:	85 c0                	test   %eax,%eax
 105e7e3:	0f 85 0a 02 00 00    	jne    105e9f3 <my.vm::run+0x34c3>
 105e7e9:	48 8d 3d 60 43 02 00 	lea    0x24360(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e7f0:	e8 0b bc fc ff       	call   102a400 <myl_core_assert_fail>
 105e7f5:	83 f8 01             	cmp    $0x1,%eax
 105e7f8:	0f 84 e9 01 00 00    	je     105e9e7 <my.vm::run+0x34b7>
 105e7fe:	85 c0                	test   %eax,%eax
 105e800:	0f 85 f9 01 00 00    	jne    105e9ff <my.vm::run+0x34cf>
 105e806:	48 8d 3d 43 43 02 00 	lea    0x24343(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e80d:	e8 ee bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e812:	83 f8 01             	cmp    $0x1,%eax
 105e815:	0f 84 f0 01 00 00    	je     105ea0b <my.vm::run+0x34db>
 105e81b:	85 c0                	test   %eax,%eax
 105e81d:	0f 85 f4 01 00 00    	jne    105ea17 <my.vm::run+0x34e7>
 105e823:	48 8d 3d 26 43 02 00 	lea    0x24326(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105e82a:	e8 d1 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e82f:	48 8d 3d ca 44 02 00 	lea    0x244ca(%rip),%rdi        # 1082d00 <core_durable_error.verbs+0x2370>
 105e836:	ba 01 00 00 00       	mov    $0x1,%edx
 105e83b:	e8 40 68 fc ff       	call   1025080 <myl_core_trap>
 105e840:	83 f9 09             	cmp    $0x9,%ecx
 105e843:	0f 87 dd 06 00 00    	ja     105ef26 <my.vm::run+0x39f6>
 105e849:	89 c8                	mov    %ecx,%eax
 105e84b:	48 8d 0d 4e 8c fa ff 	lea    -0x573b2(%rip),%rcx        # 10074a0 <core_number_pairs+0x240>
 105e852:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105e856:	48 01 c8             	add    %rcx,%rax
 105e859:	ff e0                	jmp    *%rax
 105e85b:	48 8d 3d 6e 98 02 00 	lea    0x2986e(%rip),%rdi        # 10880d0 <core_durable_error.verbs+0x7740>
 105e862:	e8 99 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e867:	48 8d 3d e2 72 02 00 	lea    0x272e2(%rip),%rdi        # 1085b50 <core_durable_error.verbs+0x51c0>
 105e86e:	e8 8d bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e873:	48 8d 3d 06 73 02 00 	lea    0x27306(%rip),%rdi        # 1085b80 <core_durable_error.verbs+0x51f0>
 105e87a:	e8 81 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e87f:	48 8d 3d 2a 73 02 00 	lea    0x2732a(%rip),%rdi        # 1085bb0 <core_durable_error.verbs+0x5220>
 105e886:	e8 75 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e88b:	48 8d 3d 4e 73 02 00 	lea    0x2734e(%rip),%rdi        # 1085be0 <core_durable_error.verbs+0x5250>
 105e892:	e8 69 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e897:	48 8d 3d 72 73 02 00 	lea    0x27372(%rip),%rdi        # 1085c10 <core_durable_error.verbs+0x5280>
 105e89e:	e8 5d bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8a3:	48 8d 3d 96 73 02 00 	lea    0x27396(%rip),%rdi        # 1085c40 <core_durable_error.verbs+0x52b0>
 105e8aa:	e8 51 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8af:	48 8d 3d ba 73 02 00 	lea    0x273ba(%rip),%rdi        # 1085c70 <core_durable_error.verbs+0x52e0>
 105e8b6:	e8 45 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8bb:	48 8d 3d de 73 02 00 	lea    0x273de(%rip),%rdi        # 1085ca0 <core_durable_error.verbs+0x5310>
 105e8c2:	e8 39 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8c7:	48 8d 3d b2 42 02 00 	lea    0x242b2(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e8ce:	e8 2d bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8d3:	48 8d 3d d6 42 02 00 	lea    0x242d6(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e8da:	e8 21 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8df:	48 8d 3d 9a 42 02 00 	lea    0x2429a(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e8e6:	e8 15 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8eb:	48 8d 3d be 42 02 00 	lea    0x242be(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e8f2:	e8 09 bb fc ff       	call   102a400 <myl_core_assert_fail>
 105e8f7:	48 8d 3d 82 42 02 00 	lea    0x24282(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e8fe:	e8 fd ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e903:	48 8d 3d a6 42 02 00 	lea    0x242a6(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e90a:	e8 f1 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e90f:	48 8d 3d 6a 42 02 00 	lea    0x2426a(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e916:	e8 e5 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e91b:	48 8d 3d 8e 42 02 00 	lea    0x2428e(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e922:	e8 d9 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e927:	48 8d 3d 52 42 02 00 	lea    0x24252(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e92e:	e8 cd ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e933:	48 8d 3d 76 42 02 00 	lea    0x24276(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e93a:	e8 c1 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e93f:	48 8d 3d da 4a 02 00 	lea    0x24ada(%rip),%rdi        # 1083420 <core_durable_error.verbs+0x2a90>
 105e946:	ba 01 00 00 00       	mov    $0x1,%edx
 105e94b:	48 89 c6             	mov    %rax,%rsi
 105e94e:	e8 2d 67 fc ff       	call   1025080 <myl_core_trap>
 105e953:	48 8d 3d 56 48 02 00 	lea    0x24856(%rip),%rdi        # 10831b0 <core_durable_error.verbs+0x2820>
 105e95a:	ba 01 00 00 00       	mov    $0x1,%edx
 105e95f:	4c 89 fe             	mov    %r15,%rsi
 105e962:	e8 19 67 fc ff       	call   1025080 <myl_core_trap>
 105e967:	48 8d 3d b2 29 02 00 	lea    0x229b2(%rip),%rdi        # 1081320 <core_durable_error.verbs+0x990>
 105e96e:	ba 01 00 00 00       	mov    $0x1,%edx
 105e973:	4c 89 fe             	mov    %r15,%rsi
 105e976:	e8 05 67 fc ff       	call   1025080 <myl_core_trap>
 105e97b:	48 8d 3d fe 41 02 00 	lea    0x241fe(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e982:	e8 79 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e987:	48 8d 3d 22 42 02 00 	lea    0x24222(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e98e:	e8 6d ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e993:	48 8d 3d e6 41 02 00 	lea    0x241e6(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e99a:	e8 61 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e99f:	48 8d 3d 0a 42 02 00 	lea    0x2420a(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e9a6:	e8 55 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9ab:	48 8d 3d ce 41 02 00 	lea    0x241ce(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e9b2:	e8 49 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9b7:	48 8d 3d f2 41 02 00 	lea    0x241f2(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e9be:	e8 3d ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9c3:	48 8d 3d b6 41 02 00 	lea    0x241b6(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e9ca:	e8 31 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9cf:	48 8d 3d da 41 02 00 	lea    0x241da(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e9d6:	e8 25 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9db:	48 8d 3d 9e 41 02 00 	lea    0x2419e(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e9e2:	e8 19 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9e7:	48 8d 3d 92 41 02 00 	lea    0x24192(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105e9ee:	e8 0d ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9f3:	48 8d 3d b6 41 02 00 	lea    0x241b6(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105e9fa:	e8 01 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9ff:	48 8d 3d aa 41 02 00 	lea    0x241aa(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105ea06:	e8 f5 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea0b:	48 8d 3d 6e 41 02 00 	lea    0x2416e(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105ea12:	e8 e9 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea17:	48 8d 3d 92 41 02 00 	lea    0x24192(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105ea1e:	e8 dd b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea23:	48 8d 3d c6 49 02 00 	lea    0x249c6(%rip),%rdi        # 10833f0 <core_durable_error.verbs+0x2a60>
 105ea2a:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea2f:	e8 4c 66 fc ff       	call   1025080 <myl_core_trap>
 105ea34:	48 8d 3d 65 27 02 00 	lea    0x22765(%rip),%rdi        # 10811a0 <core_durable_error.verbs+0x810>
 105ea3b:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea40:	4c 89 fe             	mov    %r15,%rsi
 105ea43:	e8 38 66 fc ff       	call   1025080 <myl_core_trap>
 105ea48:	48 8d 3d 81 3f 02 00 	lea    0x23f81(%rip),%rdi        # 10829d0 <core_durable_error.verbs+0x2040>
 105ea4f:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea54:	e8 27 66 fc ff       	call   1025080 <myl_core_trap>
 105ea59:	48 8d 3d 50 2c 02 00 	lea    0x22c50(%rip),%rdi        # 10816b0 <core_durable_error.verbs+0xd20>
 105ea60:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea65:	e8 16 66 fc ff       	call   1025080 <myl_core_trap>
 105ea6a:	48 8d 3d 7f 25 02 00 	lea    0x2257f(%rip),%rdi        # 1080ff0 <core_durable_error.verbs+0x660>
 105ea71:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea76:	4c 89 fe             	mov    %r15,%rsi
 105ea79:	e8 02 66 fc ff       	call   1025080 <myl_core_trap>
 105ea7e:	48 8d 3d 9b 2e 02 00 	lea    0x22e9b(%rip),%rdi        # 1081920 <core_durable_error.verbs+0xf90>
 105ea85:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea8a:	e8 f1 65 fc ff       	call   1025080 <myl_core_trap>
 105ea8f:	48 8d 3d ca 3f 02 00 	lea    0x23fca(%rip),%rdi        # 1082a60 <core_durable_error.verbs+0x20d0>
 105ea96:	ba 01 00 00 00       	mov    $0x1,%edx
 105ea9b:	4c 89 fe             	mov    %r15,%rsi
 105ea9e:	e8 dd 65 fc ff       	call   1025080 <myl_core_trap>
 105eaa3:	48 8d 3d 96 29 02 00 	lea    0x22996(%rip),%rdi        # 1081440 <core_durable_error.verbs+0xab0>
 105eaaa:	ba 01 00 00 00       	mov    $0x1,%edx
 105eaaf:	4c 89 fe             	mov    %r15,%rsi
 105eab2:	e8 c9 65 fc ff       	call   1025080 <myl_core_trap>
 105eab7:	48 8d 3d a2 2a 02 00 	lea    0x22aa2(%rip),%rdi        # 1081560 <core_durable_error.verbs+0xbd0>
 105eabe:	ba 01 00 00 00       	mov    $0x1,%edx
 105eac3:	4c 89 fe             	mov    %r15,%rsi
 105eac6:	e8 b5 65 fc ff       	call   1025080 <myl_core_trap>
 105eacb:	48 8d 3d ce 29 02 00 	lea    0x229ce(%rip),%rdi        # 10814a0 <core_durable_error.verbs+0xb10>
 105ead2:	ba 01 00 00 00       	mov    $0x1,%edx
 105ead7:	4c 89 fe             	mov    %r15,%rsi
 105eada:	e8 a1 65 fc ff       	call   1025080 <myl_core_trap>
 105eadf:	48 8d 3d 5a 26 02 00 	lea    0x2265a(%rip),%rdi        # 1081140 <core_durable_error.verbs+0x7b0>
 105eae6:	ba 01 00 00 00       	mov    $0x1,%edx
 105eaeb:	4c 89 fe             	mov    %r15,%rsi
 105eaee:	e8 8d 65 fc ff       	call   1025080 <myl_core_trap>
 105eaf3:	48 8d 3d 36 3f 02 00 	lea    0x23f36(%rip),%rdi        # 1082a30 <core_durable_error.verbs+0x20a0>
 105eafa:	ba 01 00 00 00       	mov    $0x1,%edx
 105eaff:	e8 7c 65 fc ff       	call   1025080 <myl_core_trap>
 105eb04:	48 8d 3d f5 29 02 00 	lea    0x229f5(%rip),%rdi        # 1081500 <core_durable_error.verbs+0xb70>
 105eb0b:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb10:	4c 89 fe             	mov    %r15,%rsi
 105eb13:	e8 68 65 fc ff       	call   1025080 <myl_core_trap>
 105eb18:	48 8d 3d 11 48 02 00 	lea    0x24811(%rip),%rdi        # 1083330 <core_durable_error.verbs+0x29a0>
 105eb1f:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb24:	e8 57 65 fc ff       	call   1025080 <myl_core_trap>
 105eb29:	48 8d 3d c0 2a 02 00 	lea    0x22ac0(%rip),%rdi        # 10815f0 <core_durable_error.verbs+0xc60>
 105eb30:	48 89 c6             	mov    %rax,%rsi
 105eb33:	4c 89 ca             	mov    %r9,%rdx
 105eb36:	e8 45 65 fc ff       	call   1025080 <myl_core_trap>
 105eb3b:	48 8d 3d 5e 23 02 00 	lea    0x2235e(%rip),%rdi        # 1080ea0 <core_durable_error.verbs+0x510>
 105eb42:	e8 39 65 fc ff       	call   1025080 <myl_core_trap>
 105eb47:	48 8d 3d c2 2b 02 00 	lea    0x22bc2(%rip),%rdi        # 1081710 <core_durable_error.verbs+0xd80>
 105eb4e:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb53:	e8 28 65 fc ff       	call   1025080 <myl_core_trap>
 105eb58:	48 8d 3d d1 26 02 00 	lea    0x226d1(%rip),%rdi        # 1081230 <core_durable_error.verbs+0x8a0>
 105eb5f:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb64:	4c 89 fe             	mov    %r15,%rsi
 105eb67:	e8 14 65 fc ff       	call   1025080 <myl_core_trap>
 105eb6c:	48 8d 3d 4d 2a 02 00 	lea    0x22a4d(%rip),%rdi        # 10815c0 <core_durable_error.verbs+0xc30>
 105eb73:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb78:	4c 89 fe             	mov    %r15,%rsi
 105eb7b:	e8 00 65 fc ff       	call   1025080 <myl_core_trap>
 105eb80:	48 8d 3d c9 2a 02 00 	lea    0x22ac9(%rip),%rdi        # 1081650 <core_durable_error.verbs+0xcc0>
 105eb87:	ba 01 00 00 00       	mov    $0x1,%edx
 105eb8c:	4c 89 fe             	mov    %r15,%rsi
 105eb8f:	e8 ec 64 fc ff       	call   1025080 <myl_core_trap>
 105eb94:	48 8d 3d c5 41 02 00 	lea    0x241c5(%rip),%rdi        # 1082d60 <core_durable_error.verbs+0x23d0>
 105eb9b:	ba 01 00 00 00       	mov    $0x1,%edx
 105eba0:	48 89 c6             	mov    %rax,%rsi
 105eba3:	e8 d8 64 fc ff       	call   1025080 <myl_core_trap>
 105eba8:	48 8d 3d 31 49 02 00 	lea    0x24931(%rip),%rdi        # 10834e0 <core_durable_error.verbs+0x2b50>
 105ebaf:	ba 01 00 00 00       	mov    $0x1,%edx
 105ebb4:	e8 c7 64 fc ff       	call   1025080 <myl_core_trap>
 105ebb9:	48 8d 3d 20 25 02 00 	lea    0x22520(%rip),%rdi        # 10810e0 <core_durable_error.verbs+0x750>
 105ebc0:	ba 01 00 00 00       	mov    $0x1,%edx
 105ebc5:	4c 89 fe             	mov    %r15,%rsi
 105ebc8:	e8 b3 64 fc ff       	call   1025080 <myl_core_trap>
 105ebcd:	48 8d 3d 3c 49 02 00 	lea    0x2493c(%rip),%rdi        # 1083510 <core_durable_error.verbs+0x2b80>
 105ebd4:	ba 01 00 00 00       	mov    $0x1,%edx
 105ebd9:	4c 89 d6             	mov    %r10,%rsi
 105ebdc:	e8 9f 64 fc ff       	call   1025080 <myl_core_trap>
 105ebe1:	48 8d 3d c8 21 02 00 	lea    0x221c8(%rip),%rdi        # 1080db0 <core_durable_error.verbs+0x420>
 105ebe8:	4c 89 ce             	mov    %r9,%rsi
 105ebeb:	e8 90 64 fc ff       	call   1025080 <myl_core_trap>
 105ebf0:	48 8d 3d c9 26 02 00 	lea    0x226c9(%rip),%rdi        # 10812c0 <core_durable_error.verbs+0x930>
 105ebf7:	ba 01 00 00 00       	mov    $0x1,%edx
 105ebfc:	4c 89 fe             	mov    %r15,%rsi
 105ebff:	e8 7c 64 fc ff       	call   1025080 <myl_core_trap>
 105ec04:	48 8d 3d 35 22 02 00 	lea    0x22235(%rip),%rdi        # 1080e40 <core_durable_error.verbs+0x4b0>
 105ec0b:	e8 70 64 fc ff       	call   1025080 <myl_core_trap>
 105ec10:	48 8d 3d 49 3b 02 00 	lea    0x23b49(%rip),%rdi        # 1082760 <core_durable_error.verbs+0x1dd0>
 105ec17:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec1c:	48 89 c6             	mov    %rax,%rsi
 105ec1f:	e8 5c 64 fc ff       	call   1025080 <myl_core_trap>
 105ec24:	48 8d 3d 15 2b 02 00 	lea    0x22b15(%rip),%rdi        # 1081740 <core_durable_error.verbs+0xdb0>
 105ec2b:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec30:	4c 89 fe             	mov    %r15,%rsi
 105ec33:	e8 48 64 fc ff       	call   1025080 <myl_core_trap>
 105ec38:	48 8d 3d 41 42 02 00 	lea    0x24241(%rip),%rdi        # 1082e80 <core_durable_error.verbs+0x24f0>
 105ec3f:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec44:	e8 37 64 fc ff       	call   1025080 <myl_core_trap>
 105ec49:	48 8d 3d b0 25 02 00 	lea    0x225b0(%rip),%rdi        # 1081200 <core_durable_error.verbs+0x870>
 105ec50:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec55:	4c 89 fe             	mov    %r15,%rsi
 105ec58:	e8 23 64 fc ff       	call   1025080 <myl_core_trap>
 105ec5d:	48 8d 3d 5c 2c 02 00 	lea    0x22c5c(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0xf30>
 105ec64:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec69:	e8 12 64 fc ff       	call   1025080 <myl_core_trap>
 105ec6e:	48 8d 3d 0b 27 02 00 	lea    0x2270b(%rip),%rdi        # 1081380 <core_durable_error.verbs+0x9f0>
 105ec75:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec7a:	4c 89 fe             	mov    %r15,%rsi
 105ec7d:	e8 fe 63 fc ff       	call   1025080 <myl_core_trap>
 105ec82:	48 8d 3d 57 27 02 00 	lea    0x22757(%rip),%rdi        # 10813e0 <core_durable_error.verbs+0xa50>
 105ec89:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec8e:	4c 89 fe             	mov    %r15,%rsi
 105ec91:	e8 ea 63 fc ff       	call   1025080 <myl_core_trap>
 105ec96:	48 8d 3d f3 2b 02 00 	lea    0x22bf3(%rip),%rdi        # 1081890 <core_durable_error.verbs+0xf00>
 105ec9d:	ba 01 00 00 00       	mov    $0x1,%edx
 105eca2:	e8 d9 63 fc ff       	call   1025080 <myl_core_trap>
 105eca7:	48 8d 3d 32 45 02 00 	lea    0x24532(%rip),%rdi        # 10831e0 <core_durable_error.verbs+0x2850>
 105ecae:	48 89 c6             	mov    %rax,%rsi
 105ecb1:	48 89 da             	mov    %rbx,%rdx
 105ecb4:	e8 c7 63 fc ff       	call   1025080 <myl_core_trap>
 105ecb9:	48 8d 3d 30 26 02 00 	lea    0x22630(%rip),%rdi        # 10812f0 <core_durable_error.verbs+0x960>
 105ecc0:	4c 89 ce             	mov    %r9,%rsi
 105ecc3:	48 89 c2             	mov    %rax,%rdx
 105ecc6:	e8 b5 63 fc ff       	call   1025080 <myl_core_trap>
 105eccb:	48 8d 3d 5e 22 02 00 	lea    0x2225e(%rip),%rdi        # 1080f30 <core_durable_error.verbs+0x5a0>
 105ecd2:	ba 01 00 00 00       	mov    $0x1,%edx
 105ecd7:	4c 89 d6             	mov    %r10,%rsi
 105ecda:	e8 a1 63 fc ff       	call   1025080 <myl_core_trap>
 105ecdf:	48 8d 3d 1a 2b 02 00 	lea    0x22b1a(%rip),%rdi        # 1081800 <core_durable_error.verbs+0xe70>
 105ece6:	ba 01 00 00 00       	mov    $0x1,%edx
 105eceb:	4c 89 d6             	mov    %r10,%rsi
 105ecee:	e8 8d 63 fc ff       	call   1025080 <myl_core_trap>
 105ecf3:	48 8d 3d d6 21 02 00 	lea    0x221d6(%rip),%rdi        # 1080ed0 <core_durable_error.verbs+0x540>
 105ecfa:	ba 01 00 00 00       	mov    $0x1,%edx
 105ecff:	4c 89 d6             	mov    %r10,%rsi
 105ed02:	e8 79 63 fc ff       	call   1025080 <myl_core_trap>
 105ed07:	48 8d 3d 82 22 02 00 	lea    0x22282(%rip),%rdi        # 1080f90 <core_durable_error.verbs+0x600>
 105ed0e:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed13:	4c 89 d6             	mov    %r10,%rsi
 105ed16:	e8 65 63 fc ff       	call   1025080 <myl_core_trap>
 105ed1b:	48 8d 3d ae 6f 02 00 	lea    0x26fae(%rip),%rdi        # 1085cd0 <core_durable_error.verbs+0x5340>
 105ed22:	e8 d9 b6 fc ff       	call   102a400 <myl_core_assert_fail>
 105ed27:	83 f9 01             	cmp    $0x1,%ecx
 105ed2a:	0f 84 dd 00 00 00    	je     105ee0d <my.vm::run+0x38dd>
 105ed30:	85 c9                	test   %ecx,%ecx
 105ed32:	0f 85 e1 00 00 00    	jne    105ee19 <my.vm::run+0x38e9>
 105ed38:	48 8d 3d 11 3e 02 00 	lea    0x23e11(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105ed3f:	e8 bc b6 fc ff       	call   102a400 <myl_core_assert_fail>
 105ed44:	83 f8 01             	cmp    $0x1,%eax
 105ed47:	0f 84 d8 00 00 00    	je     105ee25 <my.vm::run+0x38f5>
 105ed4d:	85 c0                	test   %eax,%eax
 105ed4f:	0f 85 dc 00 00 00    	jne    105ee31 <my.vm::run+0x3901>
 105ed55:	48 8d 3d f4 3d 02 00 	lea    0x23df4(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105ed5c:	e8 9f b6 fc ff       	call   102a400 <myl_core_assert_fail>
 105ed61:	48 8d 3d a8 3b 02 00 	lea    0x23ba8(%rip),%rdi        # 1082910 <core_durable_error.verbs+0x1f80>
 105ed68:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed6d:	48 89 ce             	mov    %rcx,%rsi
 105ed70:	e8 0b 63 fc ff       	call   1025080 <myl_core_trap>
 105ed75:	48 8d 3d 04 3b 02 00 	lea    0x23b04(%rip),%rdi        # 1082880 <core_durable_error.verbs+0x1ef0>
 105ed7c:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed81:	e8 fa 62 fc ff       	call   1025080 <myl_core_trap>
 105ed86:	48 8d 3d e3 20 02 00 	lea    0x220e3(%rip),%rdi        # 1080e70 <core_durable_error.verbs+0x4e0>
 105ed8d:	4c 89 c6             	mov    %r8,%rsi
 105ed90:	e8 eb 62 fc ff       	call   1025080 <myl_core_trap>
 105ed95:	48 8d 3d 94 39 02 00 	lea    0x23994(%rip),%rdi        # 1082730 <core_durable_error.verbs+0x1da0>
 105ed9c:	ba 01 00 00 00       	mov    $0x1,%edx
 105eda1:	e8 da 62 fc ff       	call   1025080 <myl_core_trap>
 105eda6:	48 8d 3d a3 1f 02 00 	lea    0x21fa3(%rip),%rdi        # 1080d50 <core_durable_error.verbs+0x3c0>
 105edad:	ba 01 00 00 00       	mov    $0x1,%edx
 105edb2:	48 89 ee             	mov    %rbp,%rsi
 105edb5:	e8 c6 62 fc ff       	call   1025080 <myl_core_trap>
 105edba:	48 8d 3d af 3b 02 00 	lea    0x23baf(%rip),%rdi        # 1082970 <core_durable_error.verbs+0x1fe0>
 105edc1:	ba 01 00 00 00       	mov    $0x1,%edx
 105edc6:	48 89 ce             	mov    %rcx,%rsi
 105edc9:	e8 b2 62 fc ff       	call   1025080 <myl_core_trap>
 105edce:	48 8d 3d 4b 3a 02 00 	lea    0x23a4b(%rip),%rdi        # 1082820 <core_durable_error.verbs+0x1e90>
 105edd5:	ba 01 00 00 00       	mov    $0x1,%edx
 105edda:	e8 a1 62 fc ff       	call   1025080 <myl_core_trap>
 105eddf:	83 f8 01             	cmp    $0x1,%eax
 105ede2:	0f 84 12 01 00 00    	je     105eefa <my.vm::run+0x39ca>
 105ede8:	85 c0                	test   %eax,%eax
 105edea:	0f 85 16 01 00 00    	jne    105ef06 <my.vm::run+0x39d6>
 105edf0:	48 8d 3d 59 3d 02 00 	lea    0x23d59(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105edf7:	e8 04 b6 fc ff       	call   102a400 <myl_core_assert_fail>
 105edfc:	48 8d 3d 1d 40 02 00 	lea    0x2401d(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x2490>
 105ee03:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee08:	e8 73 62 fc ff       	call   1025080 <myl_core_trap>
 105ee0d:	48 8d 3d 6c 3d 02 00 	lea    0x23d6c(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105ee14:	e8 e7 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee19:	48 8d 3d 90 3d 02 00 	lea    0x23d90(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105ee20:	e8 db b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee25:	48 8d 3d 54 3d 02 00 	lea    0x23d54(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105ee2c:	e8 cf b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee31:	48 8d 3d 78 3d 02 00 	lea    0x23d78(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105ee38:	e8 c3 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee3d:	48 8d 3d 7c 3f 02 00 	lea    0x23f7c(%rip),%rdi        # 1082dc0 <core_durable_error.verbs+0x2430>
 105ee44:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee49:	e8 32 62 fc ff       	call   1025080 <myl_core_trap>
 105ee4e:	48 8d 3d ab 92 02 00 	lea    0x292ab(%rip),%rdi        # 1088100 <core_durable_error.verbs+0x7770>
 105ee55:	e8 a6 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee5a:	48 8d 3d cf 92 02 00 	lea    0x292cf(%rip),%rdi        # 1088130 <core_durable_error.verbs+0x77a0>
 105ee61:	e8 9a b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee66:	48 8d 3d f3 92 02 00 	lea    0x292f3(%rip),%rdi        # 1088160 <core_durable_error.verbs+0x77d0>
 105ee6d:	e8 8e b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee72:	48 8d 3d 17 93 02 00 	lea    0x29317(%rip),%rdi        # 1088190 <core_durable_error.verbs+0x7800>
 105ee79:	e8 82 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee7e:	48 8d 3d 3b 93 02 00 	lea    0x2933b(%rip),%rdi        # 10881c0 <core_durable_error.verbs+0x7830>
 105ee85:	e8 76 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee8a:	48 8d 3d 5f 93 02 00 	lea    0x2935f(%rip),%rdi        # 10881f0 <core_durable_error.verbs+0x7860>
 105ee91:	e8 6a b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105ee96:	48 8d 3d 83 93 02 00 	lea    0x29383(%rip),%rdi        # 1088220 <core_durable_error.verbs+0x7890>
 105ee9d:	e8 5e b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eea2:	48 8d 3d a7 93 02 00 	lea    0x293a7(%rip),%rdi        # 1088250 <core_durable_error.verbs+0x78c0>
 105eea9:	e8 52 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eeae:	48 8d 3d 6b 42 02 00 	lea    0x2426b(%rip),%rdi        # 1083120 <core_durable_error.verbs+0x2790>
 105eeb5:	4c 89 fe             	mov    %r15,%rsi
 105eeb8:	48 89 da             	mov    %rbx,%rdx
 105eebb:	e8 c0 61 fc ff       	call   1025080 <myl_core_trap>
 105eec0:	83 f9 01             	cmp    $0x1,%ecx
 105eec3:	0f 84 8e 00 00 00    	je     105ef57 <my.vm::run+0x3a27>
 105eec9:	85 c9                	test   %ecx,%ecx
 105eecb:	0f 85 92 00 00 00    	jne    105ef63 <my.vm::run+0x3a33>
 105eed1:	48 8d 3d 78 3c 02 00 	lea    0x23c78(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105eed8:	e8 23 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eedd:	83 f8 01             	cmp    $0x1,%eax
 105eee0:	0f 84 89 00 00 00    	je     105ef6f <my.vm::run+0x3a3f>
 105eee6:	85 c0                	test   %eax,%eax
 105eee8:	0f 85 8d 00 00 00    	jne    105ef7b <my.vm::run+0x3a4b>
 105eeee:	48 8d 3d 5b 3c 02 00 	lea    0x23c5b(%rip),%rdi        # 1082b50 <core_durable_error.verbs+0x21c0>
 105eef5:	e8 06 b5 fc ff       	call   102a400 <myl_core_assert_fail>
 105eefa:	48 8d 3d 7f 3c 02 00 	lea    0x23c7f(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105ef01:	e8 fa b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef06:	48 8d 3d a3 3c 02 00 	lea    0x23ca3(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105ef0d:	e8 ee b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef12:	48 8d 3d 37 42 02 00 	lea    0x24237(%rip),%rdi        # 1083150 <core_durable_error.verbs+0x27c0>
 105ef19:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef1e:	48 89 c6             	mov    %rax,%rsi
 105ef21:	e8 5a 61 fc ff       	call   1025080 <myl_core_trap>
 105ef26:	48 8d 3d 53 93 02 00 	lea    0x29353(%rip),%rdi        # 1088280 <core_durable_error.verbs+0x78f0>
 105ef2d:	e8 ce b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef32:	48 8d 3d 97 64 02 00 	lea    0x26497(%rip),%rdi        # 10853d0 <core_durable_error.verbs+0x4a40>
 105ef39:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef3e:	e8 3d 61 fc ff       	call   1025080 <myl_core_trap>
 105ef43:	48 8d 3d 26 64 02 00 	lea    0x26426(%rip),%rdi        # 1085370 <core_durable_error.verbs+0x49e0>
 105ef4a:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef4f:	48 89 c6             	mov    %rax,%rsi
 105ef52:	e8 29 61 fc ff       	call   1025080 <myl_core_trap>
 105ef57:	48 8d 3d 22 3c 02 00 	lea    0x23c22(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105ef5e:	e8 9d b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef63:	48 8d 3d 46 3c 02 00 	lea    0x23c46(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105ef6a:	e8 91 b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef6f:	48 8d 3d 0a 3c 02 00 	lea    0x23c0a(%rip),%rdi        # 1082b80 <core_durable_error.verbs+0x21f0>
 105ef76:	e8 85 b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef7b:	48 8d 3d 2e 3c 02 00 	lea    0x23c2e(%rip),%rdi        # 1082bb0 <core_durable_error.verbs+0x2220>
 105ef82:	e8 79 b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105ef87:	48 8d 3d 12 28 02 00 	lea    0x22812(%rip),%rdi        # 10817a0 <core_durable_error.verbs+0xe10>
 105ef8e:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef93:	48 89 c6             	mov    %rax,%rsi
 105ef96:	e8 e5 60 fc ff       	call   1025080 <myl_core_trap>
 105ef9b:	48 8d 3d de 20 02 00 	lea    0x220de(%rip),%rdi        # 1081080 <core_durable_error.verbs+0x6f0>
 105efa2:	e8 d9 60 fc ff       	call   1025080 <myl_core_trap>
 105efa7:	48 8d 3d 22 3d 02 00 	lea    0x23d22(%rip),%rdi        # 1082cd0 <core_durable_error.verbs+0x2340>
 105efae:	e8 cd 60 fc ff       	call   1025080 <myl_core_trap>
 105efb3:	48 8d 3d 46 6d 02 00 	lea    0x26d46(%rip),%rdi        # 1085d00 <core_durable_error.verbs+0x5370>
 105efba:	4c 89 e6             	mov    %r12,%rsi
 105efbd:	e8 be 60 fc ff       	call   1025080 <myl_core_trap>
 105efc2:	48 8d 3d 67 3d 02 00 	lea    0x23d67(%rip),%rdi        # 1082d30 <core_durable_error.verbs+0x23a0>
 105efc9:	4c 89 fe             	mov    %r15,%rsi
 105efcc:	e8 af 60 fc ff       	call   1025080 <myl_core_trap>
 105efd1:	48 8d 3d f8 21 02 00 	lea    0x221f8(%rip),%rdi        # 10811d0 <core_durable_error.verbs+0x840>
 105efd8:	4c 89 fe             	mov    %r15,%rsi
 105efdb:	e8 a0 60 fc ff       	call   1025080 <myl_core_trap>
 105efe0:	48 8d 3d 09 29 02 00 	lea    0x22909(%rip),%rdi        # 10818f0 <core_durable_error.verbs+0xf60>
 105efe7:	4c 89 fe             	mov    %r15,%rsi
 105efea:	e8 91 60 fc ff       	call   1025080 <myl_core_trap>
 105efef:	48 8d 3d 6a 1f 02 00 	lea    0x21f6a(%rip),%rdi        # 1080f60 <core_durable_error.verbs+0x5d0>
 105eff6:	e8 85 60 fc ff       	call   1025080 <myl_core_trap>
 105effb:	48 8d 3d 5e 28 02 00 	lea    0x2285e(%rip),%rdi        # 1081860 <core_durable_error.verbs+0xed0>
 105f002:	e8 79 60 fc ff       	call   1025080 <myl_core_trap>
 105f007:	48 8d 3d 62 45 02 00 	lea    0x24562(%rip),%rdi        # 1083570 <core_durable_error.verbs+0x2be0>
 105f00e:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 105f013:	e8 68 60 fc ff       	call   1025080 <myl_core_trap>
 105f018:	48 8d 3d f1 1d 02 00 	lea    0x21df1(%rip),%rdi        # 1080e10 <core_durable_error.verbs+0x480>
 105f01f:	e8 5c 60 fc ff       	call   1025080 <myl_core_trap>
 105f024:	48 8d 3d 65 25 02 00 	lea    0x22565(%rip),%rdi        # 1081590 <core_durable_error.verbs+0xc00>
 105f02b:	48 89 c2             	mov    %rax,%rdx
 105f02e:	e8 4d 60 fc ff       	call   1025080 <myl_core_trap>
 105f033:	48 8d 3d 36 21 02 00 	lea    0x22136(%rip),%rdi        # 1081170 <core_durable_error.verbs+0x7e0>
 105f03a:	4c 89 fe             	mov    %r15,%rsi
 105f03d:	e8 3e 60 fc ff       	call   1025080 <myl_core_trap>
 105f042:	48 8d 3d 87 24 02 00 	lea    0x22487(%rip),%rdi        # 10814d0 <core_durable_error.verbs+0xb40>
 105f049:	e8 32 60 fc ff       	call   1025080 <myl_core_trap>
 105f04e:	48 8d 3d 3b 6d 02 00 	lea    0x26d3b(%rip),%rdi        # 1085d90 <core_durable_error.verbs+0x5400>
 105f055:	4c 89 fe             	mov    %r15,%rsi
 105f058:	48 89 c2             	mov    %rax,%rdx
 105f05b:	e8 20 60 fc ff       	call   1025080 <myl_core_trap>
 105f060:	48 8d 3d 79 26 02 00 	lea    0x22679(%rip),%rdi        # 10816e0 <core_durable_error.verbs+0xd50>
 105f067:	4c 89 fe             	mov    %r15,%rsi
 105f06a:	e8 11 60 fc ff       	call   1025080 <myl_core_trap>
 105f06f:	48 8d 3d 8a 42 02 00 	lea    0x2428a(%rip),%rdi        # 1083300 <core_durable_error.verbs+0x2970>
 105f076:	e8 05 60 fc ff       	call   1025080 <myl_core_trap>
 105f07b:	48 8d 3d fe 25 02 00 	lea    0x225fe(%rip),%rdi        # 1081680 <core_durable_error.verbs+0xcf0>
 105f082:	e8 f9 5f fc ff       	call   1025080 <myl_core_trap>
 105f087:	48 8d 3d 82 41 02 00 	lea    0x24182(%rip),%rdi        # 1083210 <core_durable_error.verbs+0x2880>
 105f08e:	e8 ed 5f fc ff       	call   1025080 <myl_core_trap>
 105f093:	48 8d 3d f6 36 02 00 	lea    0x236f6(%rip),%rdi        # 1082790 <core_durable_error.verbs+0x1e00>
 105f09a:	e8 e1 5f fc ff       	call   1025080 <myl_core_trap>
 105f09f:	48 8d 3d ca 26 02 00 	lea    0x226ca(%rip),%rdi        # 1081770 <core_durable_error.verbs+0xde0>
 105f0a6:	e8 d5 5f fc ff       	call   1025080 <myl_core_trap>
 105f0ab:	48 8d 3d de 39 02 00 	lea    0x239de(%rip),%rdi        # 1082a90 <core_durable_error.verbs+0x2100>
 105f0b2:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 105f0b7:	e8 c4 5f fc ff       	call   1025080 <myl_core_trap>
 105f0bc:	48 8d 3d 4d 20 02 00 	lea    0x2204d(%rip),%rdi        # 1081110 <core_durable_error.verbs+0x780>
 105f0c3:	4c 89 fe             	mov    %r15,%rsi
 105f0c6:	e8 b5 5f fc ff       	call   1025080 <myl_core_trap>
 105f0cb:	48 8d 3d 0e 1d 02 00 	lea    0x21d0e(%rip),%rdi        # 1080de0 <core_durable_error.verbs+0x450>
 105f0d2:	e8 a9 5f fc ff       	call   1025080 <myl_core_trap>
 105f0d7:	48 8d 3d f2 41 02 00 	lea    0x241f2(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2940>
 105f0de:	e8 9d 5f fc ff       	call   1025080 <myl_core_trap>
 105f0e3:	48 8d 3d 36 25 02 00 	lea    0x22536(%rip),%rdi        # 1081620 <core_durable_error.verbs+0xc90>
 105f0ea:	e8 91 5f fc ff       	call   1025080 <myl_core_trap>
 105f0ef:	48 8d 3d 3a 27 02 00 	lea    0x2273a(%rip),%rdi        # 1081830 <core_durable_error.verbs+0xea0>
 105f0f6:	4c 89 fe             	mov    %r15,%rsi
 105f0f9:	e8 82 5f fc ff       	call   1025080 <myl_core_trap>
 105f0fe:	48 8d 3d 8b 21 02 00 	lea    0x2218b(%rip),%rdi        # 1081290 <core_durable_error.verbs+0x900>
 105f105:	4c 89 fe             	mov    %r15,%rsi
 105f108:	e8 73 5f fc ff       	call   1025080 <myl_core_trap>
 105f10d:	48 8d 3d 9c 1f 02 00 	lea    0x21f9c(%rip),%rdi        # 10810b0 <core_durable_error.verbs+0x720>
 105f114:	4c 89 fe             	mov    %r15,%rsi
 105f117:	e8 64 5f fc ff       	call   1025080 <myl_core_trap>
 105f11c:	48 8d 3d dd 38 02 00 	lea    0x238dd(%rip),%rdi        # 1082a00 <core_durable_error.verbs+0x2070>
 105f123:	4c 89 d6             	mov    %r10,%rsi
 105f126:	e8 55 5f fc ff       	call   1025080 <myl_core_trap>
 105f12b:	48 8d 3d 5e 3c 02 00 	lea    0x23c5e(%rip),%rdi        # 1082d90 <core_durable_error.verbs+0x2400>
 105f132:	e8 49 5f fc ff       	call   1025080 <myl_core_trap>
 105f137:	48 8d 3d 62 44 02 00 	lea    0x24462(%rip),%rdi        # 10835a0 <core_durable_error.verbs+0x2c10>
 105f13e:	4c 89 fe             	mov    %r15,%rsi
 105f141:	e8 3a 5f fc ff       	call   1025080 <myl_core_trap>
 105f146:	48 8d 3d 63 22 02 00 	lea    0x22263(%rip),%rdi        # 10813b0 <core_durable_error.verbs+0xa20>
 105f14d:	e8 2e 5f fc ff       	call   1025080 <myl_core_trap>
 105f152:	48 8d 3d 97 69 02 00 	lea    0x26997(%rip),%rdi        # 1085af0 <core_durable_error.verbs+0x5160>
 105f159:	4c 89 ce             	mov    %r9,%rsi
 105f15c:	e8 1f 5f fc ff       	call   1025080 <myl_core_trap>
 105f161:	48 8d 3d b8 1e 02 00 	lea    0x21eb8(%rip),%rdi        # 1081020 <core_durable_error.verbs+0x690>
 105f168:	e8 13 5f fc ff       	call   1025080 <myl_core_trap>
 105f16d:	48 8d 3d 4c 1e 02 00 	lea    0x21e4c(%rip),%rdi        # 1080fc0 <core_durable_error.verbs+0x630>
 105f174:	e8 07 5f fc ff       	call   1025080 <myl_core_trap>
 105f179:	48 8d 3d b0 23 02 00 	lea    0x223b0(%rip),%rdi        # 1081530 <core_durable_error.verbs+0xba0>
 105f180:	48 89 de             	mov    %rbx,%rsi
 105f183:	e8 f8 5e fc ff       	call   1025080 <myl_core_trap>
 105f188:	48 8d 3d 31 42 02 00 	lea    0x24231(%rip),%rdi        # 10833c0 <core_durable_error.verbs+0x2a30>
 105f18f:	4c 89 fe             	mov    %r15,%rsi
 105f192:	e8 e9 5e fc ff       	call   1025080 <myl_core_trap>
 105f197:	48 8d 3d 62 1d 02 00 	lea    0x21d62(%rip),%rdi        # 1080f00 <core_durable_error.verbs+0x570>
 105f19e:	e8 dd 5e fc ff       	call   1025080 <myl_core_trap>
 105f1a3:	48 8d 3d c6 22 02 00 	lea    0x222c6(%rip),%rdi        # 1081470 <core_durable_error.verbs+0xae0>
 105f1aa:	e8 d1 5e fc ff       	call   1025080 <myl_core_trap>
 105f1af:	48 8d 3d 8a 43 02 00 	lea    0x2438a(%rip),%rdi        # 1083540 <core_durable_error.verbs+0x2bb0>
 105f1b6:	e8 c5 5e fc ff       	call   1025080 <myl_core_trap>
 105f1bb:	48 8d 3d 4e 22 02 00 	lea    0x2224e(%rip),%rdi        # 1081410 <core_durable_error.verbs+0xa80>
 105f1c2:	e8 b9 5e fc ff       	call   1025080 <myl_core_trap>
 105f1c7:	48 8d 3d 82 27 02 00 	lea    0x22782(%rip),%rdi        # 1081950 <core_durable_error.verbs+0xfc0>
 105f1ce:	4c 89 fe             	mov    %r15,%rsi
 105f1d1:	e8 aa 5e fc ff       	call   1025080 <myl_core_trap>
 105f1d6:	48 8d 3d 73 21 02 00 	lea    0x22173(%rip),%rdi        # 1081350 <core_durable_error.verbs+0x9c0>
 105f1dd:	e8 9e 5e fc ff       	call   1025080 <myl_core_trap>
 105f1e2:	48 8d 3d c7 3c 02 00 	lea    0x23cc7(%rip),%rdi        # 1082eb0 <core_durable_error.verbs+0x2520>
 105f1e9:	4c 89 fe             	mov    %r15,%rsi
 105f1ec:	e8 8f 5e fc ff       	call   1025080 <myl_core_trap>
 105f1f1:	48 8d 3d 58 42 02 00 	lea    0x24258(%rip),%rdi        # 1083450 <core_durable_error.verbs+0x2ac0>
 105f1f8:	e8 83 5e fc ff       	call   1025080 <myl_core_trap>
 105f1fd:	48 8d 3d 5c 20 02 00 	lea    0x2205c(%rip),%rdi        # 1081260 <core_durable_error.verbs+0x8d0>
 105f204:	e8 77 5e fc ff       	call   1025080 <myl_core_trap>
 105f209:	48 8d 3d b0 35 02 00 	lea    0x235b0(%rip),%rdi        # 10827c0 <core_durable_error.verbs+0x1e30>
 105f210:	e8 6b 5e fc ff       	call   1025080 <myl_core_trap>
 105f215:	48 8d 3d 24 37 02 00 	lea    0x23724(%rip),%rdi        # 1082940 <core_durable_error.verbs+0x1fb0>
 105f21c:	e8 5f 5e fc ff       	call   1025080 <myl_core_trap>
 105f221:	48 8d 3d 28 3c 02 00 	lea    0x23c28(%rip),%rdi        # 1082e50 <core_durable_error.verbs+0x24c0>
 105f228:	4c 89 fe             	mov    %r15,%rsi
 105f22b:	e8 50 5e fc ff       	call   1025080 <myl_core_trap>
 105f230:	48 8d 3d 19 5a 02 00 	lea    0x25a19(%rip),%rdi        # 1084c50 <core_durable_error.verbs+0x42c0>
 105f237:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 105f23c:	e8 3f 5e fc ff       	call   1025080 <myl_core_trap>
 105f241:	48 8d 3d 68 36 02 00 	lea    0x23668(%rip),%rdi        # 10828b0 <core_durable_error.verbs+0x1f20>
 105f248:	48 89 c6             	mov    %rax,%rsi
 105f24b:	e8 30 5e fc ff       	call   1025080 <myl_core_trap>
 105f250:	48 8d 3d f9 35 02 00 	lea    0x235f9(%rip),%rdi        # 1082850 <core_durable_error.verbs+0x1ec0>
 105f257:	e8 24 5e fc ff       	call   1025080 <myl_core_trap>
 105f25c:	48 8d 3d 9d 34 02 00 	lea    0x2349d(%rip),%rdi        # 1082700 <core_durable_error.verbs+0x1d70>
 105f263:	48 89 c2             	mov    %rax,%rdx
 105f266:	e8 15 5e fc ff       	call   1025080 <myl_core_trap>
 105f26b:	48 8d 3d 2e 5e 02 00 	lea    0x25e2e(%rip),%rdi        # 10850a0 <core_durable_error.verbs+0x4710>
 105f272:	48 89 c2             	mov    %rax,%rdx
 105f275:	e8 06 5e fc ff       	call   1025080 <myl_core_trap>
 105f27a:	48 8d 3d bf 60 02 00 	lea    0x260bf(%rip),%rdi        # 1085340 <core_durable_error.verbs+0x49b0>
 105f281:	48 89 c6             	mov    %rax,%rsi
 105f284:	e8 f7 5d fc ff       	call   1025080 <myl_core_trap>
 105f289:	48 8d 3d c0 59 02 00 	lea    0x259c0(%rip),%rdi        # 1084c50 <core_durable_error.verbs+0x42c0>
 105f290:	48 89 de             	mov    %rbx,%rsi
 105f293:	e8 e8 5d fc ff       	call   1025080 <myl_core_trap>
 105f298:	48 8d 3d 41 60 02 00 	lea    0x26041(%rip),%rdi        # 10852e0 <core_durable_error.verbs+0x4950>
 105f29f:	48 89 c6             	mov    %rax,%rsi
 105f2a2:	48 89 ca             	mov    %rcx,%rdx
 105f2a5:	e8 d6 5d fc ff       	call   1025080 <myl_core_trap>
 105f2aa:	48 8d 3d af 6a 02 00 	lea    0x26aaf(%rip),%rdi        # 1085d60 <core_durable_error.verbs+0x53d0>
 105f2b1:	48 89 ee             	mov    %rbp,%rsi
 105f2b4:	e8 c7 5d fc ff       	call   1025080 <myl_core_trap>
 105f2b9:	48 8d 3d c0 3e 02 00 	lea    0x23ec0(%rip),%rdi        # 1083180 <core_durable_error.verbs+0x27f0>
 105f2c0:	48 89 c2             	mov    %rax,%rdx
 105f2c3:	e8 b8 5d fc ff       	call   1025080 <myl_core_trap>
 105f2c8:	48 8d 3d d1 36 02 00 	lea    0x236d1(%rip),%rdi        # 10829a0 <core_durable_error.verbs+0x2010>
 105f2cf:	e8 ac 5d fc ff       	call   1025080 <myl_core_trap>
 105f2d4:	48 8d 3d 15 3b 02 00 	lea    0x23b15(%rip),%rdi        # 1082df0 <core_durable_error.verbs+0x2460>
 105f2db:	48 89 c6             	mov    %rax,%rsi
 105f2de:	e8 9d 5d fc ff       	call   1025080 <myl_core_trap>
 105f2e3:	48 8d 3d f6 35 02 00 	lea    0x235f6(%rip),%rdi        # 10828e0 <core_durable_error.verbs+0x1f50>
 105f2ea:	48 89 de             	mov    %rbx,%rsi
 105f2ed:	e8 8e 5d fc ff       	call   1025080 <myl_core_trap>
 105f2f2:	48 8d 3d c7 37 02 00 	lea    0x237c7(%rip),%rdi        # 1082ac0 <core_durable_error.verbs+0x2130>
 105f2f9:	4c 89 fe             	mov    %r15,%rsi
 105f2fc:	e8 7f 5d fc ff       	call   1025080 <myl_core_trap>
 105f301:	48 8d 3d e8 34 02 00 	lea    0x234e8(%rip),%rdi        # 10827f0 <core_durable_error.verbs+0x1e60>
 105f308:	e8 73 5d fc ff       	call   1025080 <myl_core_trap>
 105f30d:	48 8d 3d 1c 6a 02 00 	lea    0x26a1c(%rip),%rdi        # 1085d30 <core_durable_error.verbs+0x53a0>
 105f314:	48 89 c2             	mov    %rax,%rdx
 105f317:	e8 64 5d fc ff       	call   1025080 <myl_core_trap>
 105f31c:	48 8d 3d 7d 8d 02 00 	lea    0x28d7d(%rip),%rdi        # 10880a0 <core_durable_error.verbs+0x7710>
 105f323:	e8 58 5d fc ff       	call   1025080 <myl_core_trap>
 105f328:	48 8d 3d c1 37 02 00 	lea    0x237c1(%rip),%rdi        # 1082af0 <core_durable_error.verbs+0x2160>
 105f32f:	4c 89 fe             	mov    %r15,%rsi
 105f332:	e8 49 5d fc ff       	call   1025080 <myl_core_trap>
 105f337:	48 8d 3d a2 5f 02 00 	lea    0x25fa2(%rip),%rdi        # 10852e0 <core_durable_error.verbs+0x4950>
 105f33e:	4c 89 c6             	mov    %r8,%rsi
 105f341:	48 89 ca             	mov    %rcx,%rdx
 105f344:	e8 37 5d fc ff       	call   1025080 <myl_core_trap>
 105f349:	48 8d 3d 50 60 02 00 	lea    0x26050(%rip),%rdi        # 10853a0 <core_durable_error.verbs+0x4a10>
 105f350:	e8 2b 5d fc ff       	call   1025080 <myl_core_trap>
 105f355:	48 8d 3d 54 41 02 00 	lea    0x24154(%rip),%rdi        # 10834b0 <core_durable_error.verbs+0x2b20>
 105f35c:	4c 89 fe             	mov    %r15,%rsi
 105f35f:	e8 1c 5d fc ff       	call   1025080 <myl_core_trap>
 105f364:	48 8d 3d b5 37 02 00 	lea    0x237b5(%rip),%rdi        # 1082b20 <core_durable_error.verbs+0x2190>
 105f36b:	4c 89 fe             	mov    %r15,%rsi
 105f36e:	e8 0d 5d fc ff       	call   1025080 <myl_core_trap>
 105f373:	48 8d 3d 06 41 02 00 	lea    0x24106(%rip),%rdi        # 1083480 <core_durable_error.verbs+0x2af0>
 105f37a:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 105f37f:	e8 fc 5c fc ff       	call   1025080 <myl_core_trap>
 105f384:	48 8d 3d 85 5f 02 00 	lea    0x25f85(%rip),%rdi        # 1085310 <core_durable_error.verbs+0x4980>
 105f38b:	e8 f0 5c fc ff       	call   1025080 <myl_core_trap>
 105f390:	48 8d 3d b9 58 02 00 	lea    0x258b9(%rip),%rdi        # 1084c50 <core_durable_error.verbs+0x42c0>
 105f397:	48 89 ee             	mov    %rbp,%rsi
 105f39a:	e8 e1 5c fc ff       	call   1025080 <myl_core_trap>

Disassembly of section .plt:
