
.tmp/lox-eda-parity/P2/ip:     file format elf64-x86-64


Disassembly of section .text:

000000000105b530 <my.vm::run>:
 105b530:	55                   	push   %rbp
 105b531:	41 57                	push   %r15
 105b533:	41 56                	push   %r14
 105b535:	41 55                	push   %r13
 105b537:	41 54                	push   %r12
 105b539:	53                   	push   %rbx
 105b53a:	48 81 ec f8 09 00 00 	sub    $0x9f8,%rsp
 105b541:	48 89 8c 24 a0 00 00 	mov    %rcx,0xa0(%rsp)
 105b548:	00 
 105b549:	48 89 54 24 48       	mov    %rdx,0x48(%rsp)
 105b54e:	48 89 7c 24 50       	mov    %rdi,0x50(%rsp)
 105b553:	48 89 74 24 10       	mov    %rsi,0x10(%rsp)
 105b558:	4c 8b b6 90 00 00 00 	mov    0x90(%rsi),%r14
 105b55f:	4c 89 f6             	mov    %r14,%rsi
 105b562:	48 ff ce             	dec    %rsi
 105b565:	0f 80 c8 3a 00 00    	jo     105f033 <my.vm::run+0x3b03>
 105b56b:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105b570:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105b577:	48 8b 80 88 00 00 00 	mov    0x88(%rax),%rax
 105b57e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b582:	48 39 d6             	cmp    %rdx,%rsi
 105b585:	0f 83 22 33 00 00    	jae    105e8ad <my.vm::run+0x337d>
 105b58b:	48 89 f1             	mov    %rsi,%rcx
 105b58e:	48 c1 e1 05          	shl    $0x5,%rcx
 105b592:	4c 8b 5c 08 20       	mov    0x20(%rax,%rcx,1),%r11
 105b597:	48 8b 6c 08 28       	mov    0x28(%rax,%rcx,1),%rbp
 105b59c:	4c 8b 44 08 30       	mov    0x30(%rax,%rcx,1),%r8
 105b5a1:	4c 8b 4c 08 38       	mov    0x38(%rax,%rcx,1),%r9
 105b5a6:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105b5ab:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 105b5b0:	4c 89 ef             	mov    %r13,%rdi
 105b5b3:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 105b5b8:	48 89 de             	mov    %rbx,%rsi
 105b5bb:	4c 89 da             	mov    %r11,%rdx
 105b5be:	48 89 e9             	mov    %rbp,%rcx
 105b5c1:	e8 3a 88 00 00       	call   1063e00 <my.vm::read_byte>
 105b5c6:	48 8b 83 88 00 00 00 	mov    0x88(%rbx),%rax
 105b5cd:	49 8d 5e ff          	lea    -0x1(%r14),%rbx
 105b5d1:	48 89 da             	mov    %rbx,%rdx
 105b5d4:	4d 85 f6             	test   %r14,%r14
 105b5d7:	7f 07                	jg     105b5e0 <my.vm::run+0xb0>
 105b5d9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b5dd:	48 01 da             	add    %rbx,%rdx
 105b5e0:	48 8b 4c 24 78       	mov    0x78(%rsp),%rcx
 105b5e5:	4c 8b 9c 24 80 00 00 	mov    0x80(%rsp),%r11
 105b5ec:	00 
 105b5ed:	48 8b ac 24 88 00 00 	mov    0x88(%rsp),%rbp
 105b5f4:	00 
 105b5f5:	4c 8b 84 24 90 00 00 	mov    0x90(%rsp),%r8
 105b5fc:	00 
 105b5fd:	4d 89 c4             	mov    %r8,%r12
 105b600:	4c 8b 8c 24 98 00 00 	mov    0x98(%rsp),%r9
 105b607:	00 
 105b608:	48 c1 e2 05          	shl    $0x5,%rdx
 105b60c:	4c 89 44 10 30       	mov    %r8,0x30(%rax,%rdx,1)
 105b611:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105b616:	48 89 82 88 00 00 00 	mov    %rax,0x88(%rdx)
 105b61d:	48 83 f9 24          	cmp    $0x24,%rcx
 105b621:	0f 87 a9 28 00 00    	ja     105ded0 <my.vm::run+0x29a0>
 105b627:	48 8d 15 7e bd fa ff 	lea    -0x54282(%rip),%rdx        # 10073ac <core_number_pairs+0x14c>
 105b62e:	48 63 04 8a          	movslq (%rdx,%rcx,4),%rax
 105b632:	48 01 d0             	add    %rdx,%rax
 105b635:	ff e0                	jmp    *%rax
 105b637:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105b63c:	48 8b 80 80 00 00 00 	mov    0x80(%rax),%rax
 105b643:	48 89 c6             	mov    %rax,%rsi
 105b646:	48 ff ce             	dec    %rsi
 105b649:	0f 80 fd 32 00 00    	jo     105e94c <my.vm::run+0x341c>
 105b64f:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105b654:	48 8b 40 78          	mov    0x78(%rax),%rax
 105b658:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b65c:	48 89 f7             	mov    %rsi,%rdi
 105b65f:	48 39 d6             	cmp    %rdx,%rsi
 105b662:	0f 83 68 2a 00 00    	jae    105e0d0 <my.vm::run+0x2ba0>
 105b668:	48 c1 e7 04          	shl    $0x4,%rdi
 105b66c:	80 7c 38 20 02       	cmpb   $0x2,0x20(%rax,%rdi,1)
 105b671:	75 5b                	jne    105b6ce <my.vm::run+0x19e>
 105b673:	49 89 f7             	mov    %rsi,%r15
 105b676:	49 ff cf             	dec    %r15
 105b679:	0f 80 3d 34 00 00    	jo     105eabc <my.vm::run+0x358c>
 105b67f:	c5 fb 10 44 38 28    	vmovsd 0x28(%rax,%rdi,1),%xmm0
 105b685:	4c 89 fe             	mov    %r15,%rsi
 105b688:	49 39 d7             	cmp    %rdx,%r15
 105b68b:	0f 83 5a 2a 00 00    	jae    105e0eb <my.vm::run+0x2bbb>
 105b691:	48 83 c0 20          	add    $0x20,%rax
 105b695:	48 c1 e6 04          	shl    $0x4,%rsi
 105b699:	80 3c 30 02          	cmpb   $0x2,(%rax,%rsi,1)
 105b69d:	75 2f                	jne    105b6ce <my.vm::run+0x19e>
 105b69f:	48 01 f0             	add    %rsi,%rax
 105b6a2:	c5 fb 10 48 08       	vmovsd 0x8(%rax),%xmm1
 105b6a7:	48 83 c1 f0          	add    $0xfffffffffffffff0,%rcx
 105b6ab:	48 83 f9 04          	cmp    $0x4,%rcx
 105b6af:	0f 87 63 27 00 00    	ja     105de18 <my.vm::run+0x28e8>
 105b6b5:	48 8d 15 d0 bd fa ff 	lea    -0x54230(%rip),%rdx        # 100748c <core_number_pairs+0x22c>
 105b6bc:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 105b6c0:	48 01 d1             	add    %rdx,%rcx
 105b6c3:	ff e1                	jmp    *%rcx
 105b6c5:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 105b6c9:	e9 37 27 00 00       	jmp    105de05 <my.vm::run+0x28d5>
 105b6ce:	4d 89 c6             	mov    %r8,%r14
 105b6d1:	49 89 ef             	mov    %rbp,%r15
 105b6d4:	4c 89 e5             	mov    %r12,%rbp
 105b6d7:	4d 89 ec             	mov    %r13,%r12
 105b6da:	4d 89 dd             	mov    %r11,%r13
 105b6dd:	4c 89 cb             	mov    %r9,%rbx
 105b6e0:	48 8d 0d f9 74 fb ff 	lea    -0x48b07(%rip),%rcx        # 1012be0 <core_number_pairs+0xb980>
 105b6e7:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105b6ee:	00 
 105b6ef:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105b6f4:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105b6f9:	e8 82 82 00 00       	call   1063980 <my.vm::runtime_error>
 105b6fe:	f6 84 24 a8 00 00 00 	testb  $0x1,0xa8(%rsp)
 105b705:	01 
 105b706:	0f 84 4d 31 00 00    	je     105e859 <my.vm::run+0x3329>
 105b70c:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105b711:	48 8b 81 80 00 00 00 	mov    0x80(%rcx),%rax
 105b718:	48 8b 89 90 00 00 00 	mov    0x90(%rcx),%rcx
 105b71f:	49 89 d9             	mov    %rbx,%r9
 105b722:	4d 89 eb             	mov    %r13,%r11
 105b725:	4d 89 e5             	mov    %r12,%r13
 105b728:	49 89 ec             	mov    %rbp,%r12
 105b72b:	4c 89 fd             	mov    %r15,%rbp
 105b72e:	49 89 c7             	mov    %rax,%r15
 105b731:	4d 89 f0             	mov    %r14,%r8
 105b734:	49 89 ce             	mov    %rcx,%r14
 105b737:	e9 94 27 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105b73c:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105b741:	48 8b b0 80 00 00 00 	mov    0x80(%rax),%rsi
 105b748:	49 89 f2             	mov    %rsi,%r10
 105b74b:	49 ff ca             	dec    %r10
 105b74e:	0f 80 dd 35 00 00    	jo     105ed31 <my.vm::run+0x3801>
 105b754:	4c 89 d6             	mov    %r10,%rsi
 105b757:	48 ff ce             	dec    %rsi
 105b75a:	0f 80 97 35 00 00    	jo     105ecf7 <my.vm::run+0x37c7>
 105b760:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105b765:	48 8b 78 78          	mov    0x78(%rax),%rdi
 105b769:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105b76d:	48 39 d6             	cmp    %rdx,%rsi
 105b770:	0f 83 49 2b 00 00    	jae    105e2bf <my.vm::run+0x2d8f>
 105b776:	48 89 f0             	mov    %rsi,%rax
 105b779:	48 c1 e0 04          	shl    $0x4,%rax
 105b77d:	80 7c 07 20 03       	cmpb   $0x3,0x20(%rdi,%rax,1)
 105b782:	0f 85 f6 20 00 00    	jne    105d87e <my.vm::run+0x234e>
 105b788:	48 8b 74 07 28       	mov    0x28(%rdi,%rax,1),%rsi
 105b78d:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105b792:	48 8b 18             	mov    (%rax),%rbx
 105b795:	48 8b 43 08          	mov    0x8(%rbx),%rax
 105b799:	48 89 f1             	mov    %rsi,%rcx
 105b79c:	48 39 c6             	cmp    %rax,%rsi
 105b79f:	0f 83 0d 2e 00 00    	jae    105e5b2 <my.vm::run+0x3082>
 105b7a5:	48 6b c1 38          	imul   $0x38,%rcx,%rax
 105b7a9:	83 7c 03 20 06       	cmpl   $0x6,0x20(%rbx,%rax,1)
 105b7ae:	0f 85 ca 20 00 00    	jne    105d87e <my.vm::run+0x234e>
 105b7b4:	4c 89 d0             	mov    %r10,%rax
 105b7b7:	49 39 d2             	cmp    %rdx,%r10
 105b7ba:	0f 83 ca 2e 00 00    	jae    105e68a <my.vm::run+0x315a>
 105b7c0:	4c 89 44 24 18       	mov    %r8,0x18(%rsp)
 105b7c5:	4c 89 5c 24 30       	mov    %r11,0x30(%rsp)
 105b7ca:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
 105b7cf:	4c 89 4c 24 20       	mov    %r9,0x20(%rsp)
 105b7d4:	48 8d 57 20          	lea    0x20(%rdi),%rdx
 105b7d8:	48 c1 e0 04          	shl    $0x4,%rax
 105b7dc:	0f b6 0c 02          	movzbl (%rdx,%rax,1),%ecx
 105b7e0:	83 f9 03             	cmp    $0x3,%ecx
 105b7e3:	0f 85 cb 37 00 00    	jne    105efb4 <my.vm::run+0x3a84>
 105b7e9:	48 89 7c 24 58       	mov    %rdi,0x58(%rsp)
 105b7ee:	4c 89 54 24 60       	mov    %r10,0x60(%rsp)
 105b7f3:	4c 8b 7c 02 08       	mov    0x8(%rdx,%rax,1),%r15
 105b7f8:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105b7fd:	4c 89 f7             	mov    %r14,%rdi
 105b800:	e8 bb 16 01 00       	call   106cec0 <my.heap::class_obj>
 105b805:	4c 89 f7             	mov    %r14,%rdi
 105b808:	4d 89 fe             	mov    %r15,%r14
 105b80b:	49 89 d7             	mov    %rdx,%r15
 105b80e:	4c 89 f6             	mov    %r14,%rsi
 105b811:	e8 aa 16 01 00       	call   106cec0 <my.heap::class_obj>
 105b816:	4d 8b 6f 08          	mov    0x8(%r15),%r13
 105b81a:	4d 85 ed             	test   %r13,%r13
 105b81d:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
 105b822:	0f 84 66 27 00 00    	je     105df8e <my.vm::run+0x2a5e>
 105b828:	4c 89 fd             	mov    %r15,%rbp
 105b82b:	49 83 c7 38          	add    $0x38,%r15
 105b82f:	eb 1c                	jmp    105b84d <my.vm::run+0x31d>
 105b831:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105b838:	0f 1f 84 00 00 00 00 
 105b83f:	00 
 105b840:	49 83 c7 20          	add    $0x20,%r15
 105b844:	49 ff cd             	dec    %r13
 105b847:	0f 84 44 27 00 00    	je     105df91 <my.vm::run+0x2a61>
 105b84d:	49 8b 47 e8          	mov    -0x18(%r15),%rax
 105b851:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 105b855:	74 e9                	je     105b840 <my.vm::run+0x310>
 105b857:	4d 8b 0f             	mov    (%r15),%r9
 105b85a:	45 8b 57 f0          	mov    -0x10(%r15),%r10d
 105b85e:	45 8b 47 f8          	mov    -0x8(%r15),%r8d
 105b862:	48 89 d7             	mov    %rdx,%rdi
 105b865:	48 89 ce             	mov    %rcx,%rsi
 105b868:	48 89 c2             	mov    %rax,%rdx
 105b86b:	44 89 d1             	mov    %r10d,%ecx
 105b86e:	e8 cd f1 00 00       	call   106aa40 <my.table::set>
 105b873:	eb cb                	jmp    105b840 <my.vm::run+0x310>
 105b875:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105b87c:	00 
 105b87d:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105b882:	4c 89 da             	mov    %r11,%rdx
 105b885:	48 89 e9             	mov    %rbp,%rcx
 105b888:	e8 33 86 00 00       	call   1063ec0 <my.vm::read_constant>
 105b88d:	0f b6 84 24 a8 00 00 	movzbl 0xa8(%rsp),%eax
 105b894:	00 
 105b895:	83 f8 03             	cmp    $0x3,%eax
 105b898:	0f 85 c7 31 00 00    	jne    105ea65 <my.vm::run+0x3535>
 105b89e:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105b8a3:	48 8b b0 80 00 00 00 	mov    0x80(%rax),%rsi
 105b8aa:	48 89 f5             	mov    %rsi,%rbp
 105b8ad:	48 ff cd             	dec    %rbp
 105b8b0:	0f 80 a0 34 00 00    	jo     105ed56 <my.vm::run+0x3826>
 105b8b6:	48 89 ee             	mov    %rbp,%rsi
 105b8b9:	48 ff ce             	dec    %rsi
 105b8bc:	0f 80 a5 34 00 00    	jo     105ed67 <my.vm::run+0x3837>
 105b8c2:	48 8b 8c 24 d0 00 00 	mov    0xd0(%rsp),%rcx
 105b8c9:	00 
 105b8ca:	4c 8b 84 24 c8 00 00 	mov    0xc8(%rsp),%r8
 105b8d1:	00 
 105b8d2:	48 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%rax
 105b8d9:	00 
 105b8da:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
 105b8df:	4c 8b 8c 24 b0 00 00 	mov    0xb0(%rsp),%r9
 105b8e6:	00 
 105b8e7:	48 8b bc 24 b8 00 00 	mov    0xb8(%rsp),%rdi
 105b8ee:	00 
 105b8ef:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105b8f4:	4c 8b 68 78          	mov    0x78(%rax),%r13
 105b8f8:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105b8fc:	48 39 d6             	cmp    %rdx,%rsi
 105b8ff:	0f 83 2b 2b 00 00    	jae    105e430 <my.vm::run+0x2f00>
 105b905:	48 89 f0             	mov    %rsi,%rax
 105b908:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
 105b90d:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105b912:	48 c1 e0 04          	shl    $0x4,%rax
 105b916:	41 0f b6 4c 05 20    	movzbl 0x20(%r13,%rax,1),%ecx
 105b91c:	83 f9 03             	cmp    $0x3,%ecx
 105b91f:	0f 85 cc 30 00 00    	jne    105e9f1 <my.vm::run+0x34c1>
 105b925:	4c 89 44 24 18       	mov    %r8,0x18(%rsp)
 105b92a:	4d 8b 7c 05 28       	mov    0x28(%r13,%rax,1),%r15
 105b92f:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 105b934:	4c 89 ce             	mov    %r9,%rsi
 105b937:	4c 89 4c 24 58       	mov    %r9,0x58(%rsp)
 105b93c:	e8 1f f0 00 00       	call   106a960 <my.heap::string_hash>
 105b941:	89 44 24 68          	mov    %eax,0x68(%rsp)
 105b945:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105b949:	48 89 e8             	mov    %rbp,%rax
 105b94c:	48 39 d5             	cmp    %rdx,%rbp
 105b94f:	0f 83 11 2b 00 00    	jae    105e466 <my.vm::run+0x2f36>
 105b955:	49 8d 4d 20          	lea    0x20(%r13),%rcx
 105b959:	48 c1 e0 04          	shl    $0x4,%rax
 105b95d:	4c 8b 64 01 08       	mov    0x8(%rcx,%rax,1),%r12
 105b962:	8b 1c 01             	mov    (%rcx,%rax,1),%ebx
 105b965:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105b96a:	4c 89 f7             	mov    %r14,%rdi
 105b96d:	4c 89 fe             	mov    %r15,%rsi
 105b970:	e8 4b 15 01 00       	call   106cec0 <my.heap::class_obj>
 105b975:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
 105b97a:	48 89 d7             	mov    %rdx,%rdi
 105b97d:	48 89 ce             	mov    %rcx,%rsi
 105b980:	48 8b 54 24 58       	mov    0x58(%rsp),%rdx
 105b985:	8b 4c 24 68          	mov    0x68(%rsp),%ecx
 105b989:	41 89 d8             	mov    %ebx,%r8d
 105b98c:	4d 89 e1             	mov    %r12,%r9
 105b98f:	e8 ac f0 00 00       	call   106aa40 <my.table::set>
 105b994:	49 8b 36             	mov    (%r14),%rsi
 105b997:	48 8b 46 08          	mov    0x8(%rsi),%rax
 105b99b:	49 39 c7             	cmp    %rax,%r15
 105b99e:	0f 83 dd 2a 00 00    	jae    105e481 <my.vm::run+0x2f51>
 105b9a4:	4c 89 ff             	mov    %r15,%rdi
 105b9a7:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105b9ac:	4c 6b d7 38          	imul   $0x38,%rdi,%r10
 105b9b0:	46 0f b6 44 16 20    	movzbl 0x20(%rsi,%r10,1),%r8d
 105b9b6:	4a 8b 7c 16 28       	mov    0x28(%rsi,%r10,1),%rdi
 105b9bb:	4e 8b 4c 16 30       	mov    0x30(%rsi,%r10,1),%r9
 105b9c0:	4a 8b 44 16 38       	mov    0x38(%rsi,%r10,1),%rax
 105b9c5:	4a 8b 5c 16 40       	mov    0x40(%rsi,%r10,1),%rbx
 105b9ca:	4e 8b 7c 16 48       	mov    0x48(%rsi,%r10,1),%r15
 105b9cf:	4a c7 44 16 20 06 00 	movq   $0x6,0x20(%rsi,%r10,1)
 105b9d6:	00 00 
 105b9d8:	4c 8b 5c 24 60       	mov    0x60(%rsp),%r11
 105b9dd:	4e 89 5c 16 28       	mov    %r11,0x28(%rsi,%r10,1)
 105b9e2:	4a 89 54 16 30       	mov    %rdx,0x30(%rsi,%r10,1)
 105b9e7:	4a 89 4c 16 38       	mov    %rcx,0x38(%rsi,%r10,1)
 105b9ec:	41 83 f8 09          	cmp    $0x9,%r8d
 105b9f0:	77 17                	ja     105ba09 <my.vm::run+0x4d9>
 105b9f2:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105b9f7:	44 0f a3 c1          	bt     %r8d,%ecx
 105b9fb:	0f 83 34 22 00 00    	jae    105dc35 <my.vm::run+0x2705>
 105ba01:	4c 89 cf             	mov    %r9,%rdi
 105ba04:	e8 f7 88 fc ff       	call   1024300 <myl_core_drop_owned>
 105ba09:	49 89 ef             	mov    %rbp,%r15
 105ba0c:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105ba11:	48 89 a8 80 00 00 00 	mov    %rbp,0x80(%rax)
 105ba18:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105ba1c:	48 39 d5             	cmp    %rdx,%rbp
 105ba1f:	0f 83 7c 2a 00 00    	jae    105e4a1 <my.vm::run+0x2f71>
 105ba25:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105ba2a:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105ba31:	4d 89 e0             	mov    %r12,%r8
 105ba34:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105ba39:	e9 31 1e 00 00       	jmp    105d86f <my.vm::run+0x233f>
 105ba3e:	48 8d bc 24 08 02 00 	lea    0x208(%rsp),%rdi
 105ba45:	00 
 105ba46:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105ba4b:	4c 89 da             	mov    %r11,%rdx
 105ba4e:	48 89 e9             	mov    %rbp,%rcx
 105ba51:	e8 2a 8a 00 00       	call   1064480 <my.vm::read_short>
 105ba56:	4c 89 fe             	mov    %r15,%rsi
 105ba59:	48 ff ce             	dec    %rsi
 105ba5c:	0f 80 64 34 00 00    	jo     105eec6 <my.vm::run+0x3996>
 105ba62:	48 8b 94 24 08 02 00 	mov    0x208(%rsp),%rdx
 105ba69:	00 
 105ba6a:	4c 8b 9c 24 10 02 00 	mov    0x210(%rsp),%r11
 105ba71:	00 
 105ba72:	48 8b ac 24 18 02 00 	mov    0x218(%rsp),%rbp
 105ba79:	00 
 105ba7a:	4c 8b 84 24 20 02 00 	mov    0x220(%rsp),%r8
 105ba81:	00 
 105ba82:	4c 8b 8c 24 28 02 00 	mov    0x228(%rsp),%r9
 105ba89:	00 
 105ba8a:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105ba8f:	48 8b 48 78          	mov    0x78(%rax),%rcx
 105ba93:	48 8b 41 08          	mov    0x8(%rcx),%rax
 105ba97:	48 39 c6             	cmp    %rax,%rsi
 105ba9a:	0f 83 d2 26 00 00    	jae    105e172 <my.vm::run+0x2c42>
 105baa0:	48 89 f7             	mov    %rsi,%rdi
 105baa3:	4d 89 c4             	mov    %r8,%r12
 105baa6:	48 c1 e7 04          	shl    $0x4,%rdi
 105baaa:	0f b6 44 39 20       	movzbl 0x20(%rcx,%rdi,1),%eax
 105baaf:	85 c0                	test   %eax,%eax
 105bab1:	74 1b                	je     105bace <my.vm::run+0x59e>
 105bab3:	83 f8 01             	cmp    $0x1,%eax
 105bab6:	0f 85 14 24 00 00    	jne    105ded0 <my.vm::run+0x29a0>
 105babc:	48 8d 04 39          	lea    (%rcx,%rdi,1),%rax
 105bac0:	48 83 c0 20          	add    $0x20,%rax
 105bac4:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105bac8:	0f 85 02 24 00 00    	jne    105ded0 <my.vm::run+0x29a0>
 105bace:	49 01 d0             	add    %rdx,%r8
 105bad1:	0f 80 3c 35 00 00    	jo     105f013 <my.vm::run+0x3ae3>
 105bad7:	4d 89 c4             	mov    %r8,%r12
 105bada:	e9 f1 23 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105badf:	48 8d bc 24 e0 01 00 	lea    0x1e0(%rsp),%rdi
 105bae6:	00 
 105bae7:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105baec:	4c 89 da             	mov    %r11,%rdx
 105baef:	48 89 e9             	mov    %rbp,%rcx
 105baf2:	e8 89 89 00 00       	call   1064480 <my.vm::read_short>
 105baf7:	48 8b 94 24 e0 01 00 	mov    0x1e0(%rsp),%rdx
 105bafe:	00 
 105baff:	48 8b b4 24 f8 01 00 	mov    0x1f8(%rsp),%rsi
 105bb06:	00 
 105bb07:	49 89 f0             	mov    %rsi,%r8
 105bb0a:	49 29 d0             	sub    %rdx,%r8
 105bb0d:	0f 80 ef 33 00 00    	jo     105ef02 <my.vm::run+0x39d2>
 105bb13:	4c 8b 9c 24 e8 01 00 	mov    0x1e8(%rsp),%r11
 105bb1a:	00 
 105bb1b:	48 8b ac 24 f0 01 00 	mov    0x1f0(%rsp),%rbp
 105bb22:	00 
 105bb23:	4c 8b 8c 24 00 02 00 	mov    0x200(%rsp),%r9
 105bb2a:	00 
 105bb2b:	4d 89 c4             	mov    %r8,%r12
 105bb2e:	e9 9d 23 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105bb33:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105bb3a:	00 
 105bb3b:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105bb40:	4c 89 da             	mov    %r11,%rdx
 105bb43:	48 89 e9             	mov    %rbp,%rcx
 105bb46:	e8 75 83 00 00       	call   1063ec0 <my.vm::read_constant>
 105bb4b:	0f b6 84 24 a8 00 00 	movzbl 0xa8(%rsp),%eax
 105bb52:	00 
 105bb53:	83 f8 03             	cmp    $0x3,%eax
 105bb56:	0f 85 21 2e 00 00    	jne    105e97d <my.vm::run+0x344d>
 105bb5c:	48 8b 84 24 d0 00 00 	mov    0xd0(%rsp),%rax
 105bb63:	00 
 105bb64:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105bb69:	48 8b ac 24 c8 00 00 	mov    0xc8(%rsp),%rbp
 105bb70:	00 
 105bb71:	48 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%rax
 105bb78:	00 
 105bb79:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
 105bb7e:	4c 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%r13
 105bb85:	00 
 105bb86:	48 8b 84 24 b8 00 00 	mov    0xb8(%rsp),%rax
 105bb8d:	00 
 105bb8e:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 105bb93:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105bb9a:	00 
 105bb9b:	ba 30 00 00 00       	mov    $0x30,%edx
 105bba0:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105bba5:	e8 26 68 00 00       	call   10623d0 <my.heap::reserve_object>
 105bbaa:	48 8b 9c 24 a8 00 00 	mov    0xa8(%rsp),%rbx
 105bbb1:	00 
 105bbb2:	64 48 8b 04 25 c8 fe 	mov    %fs:0xfffffffffffffec8,%rax
 105bbb9:	ff ff 
 105bbbb:	48 85 c0             	test   %rax,%rax
 105bbbe:	0f 84 ac 27 00 00    	je     105e370 <my.vm::run+0x2e40>
 105bbc4:	48 8b 08             	mov    (%rax),%rcx
 105bbc7:	64 48 89 0c 25 c8 fe 	mov    %rcx,%fs:0xfffffffffffffec8
 105bbce:	ff ff 
 105bbd0:	c7 00 00 00 00 01    	movl   $0x1000000,(%rax)
 105bbd6:	c5 f9 57 c0          	vxorpd %xmm0,%xmm0,%xmm0
 105bbda:	c5 f9 11 40 08       	vmovupd %xmm0,0x8(%rax)
 105bbdf:	48 c7 40 18 00 00 00 	movq   $0x0,0x18(%rax)
 105bbe6:	00 
 105bbe7:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105bbec:	48 8b 31             	mov    (%rcx),%rsi
 105bbef:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105bbf3:	48 89 d9             	mov    %rbx,%rcx
 105bbf6:	48 39 d3             	cmp    %rdx,%rbx
 105bbf9:	49 89 e8             	mov    %rbp,%r8
 105bbfc:	0f 83 7f 27 00 00    	jae    105e381 <my.vm::run+0x2e51>
 105bc02:	4c 6b c9 38          	imul   $0x38,%rcx,%r9
 105bc06:	42 0f b6 54 0e 20    	movzbl 0x20(%rsi,%r9,1),%edx
 105bc0c:	4a 8b 7c 0e 28       	mov    0x28(%rsi,%r9,1),%rdi
 105bc11:	4e 8b 54 0e 30       	mov    0x30(%rsi,%r9,1),%r10
 105bc16:	4a 8b 4c 0e 38       	mov    0x38(%rsi,%r9,1),%rcx
 105bc1b:	4e 8b 7c 0e 40       	mov    0x40(%rsi,%r9,1),%r15
 105bc20:	4e 8b 74 0e 48       	mov    0x48(%rsi,%r9,1),%r14
 105bc25:	4a c7 44 0e 20 06 00 	movq   $0x6,0x20(%rsi,%r9,1)
 105bc2c:	00 00 
 105bc2e:	4e 89 6c 0e 28       	mov    %r13,0x28(%rsi,%r9,1)
 105bc33:	4a 89 44 0e 30       	mov    %rax,0x30(%rsi,%r9,1)
 105bc38:	4a c7 44 0e 38 00 00 	movq   $0x0,0x38(%rsi,%r9,1)
 105bc3f:	00 00 
 105bc41:	83 fa 09             	cmp    $0x9,%edx
 105bc44:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105bc49:	4c 8b 64 24 28       	mov    0x28(%rsp),%r12
 105bc4e:	77 19                	ja     105bc69 <my.vm::run+0x739>
 105bc50:	b8 d0 02 00 00       	mov    $0x2d0,%eax
 105bc55:	0f a3 d0             	bt     %edx,%eax
 105bc58:	0f 83 ad 1f 00 00    	jae    105dc0b <my.vm::run+0x26db>
 105bc5e:	4c 89 d7             	mov    %r10,%rdi
 105bc61:	e8 9a 86 fc ff       	call   1024300 <myl_core_drop_owned>
 105bc66:	49 89 e8             	mov    %rbp,%r8
 105bc69:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105bc6e:	48 8b 41 78          	mov    0x78(%rcx),%rax
 105bc72:	48 8b b1 80 00 00 00 	mov    0x80(%rcx),%rsi
 105bc79:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bc7d:	48 39 d6             	cmp    %rdx,%rsi
 105bc80:	0f 83 16 27 00 00    	jae    105e39c <my.vm::run+0x2e6c>
 105bc86:	48 89 f1             	mov    %rsi,%rcx
 105bc89:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105bc8e:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105bc93:	4c 89 e5             	mov    %r12,%rbp
 105bc96:	48 c1 e1 04          	shl    $0x4,%rcx
 105bc9a:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 105bca1:	00 00 
 105bca3:	48 89 5c 08 28       	mov    %rbx,0x28(%rax,%rcx,1)
 105bca8:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105bcad:	48 89 41 78          	mov    %rax,0x78(%rcx)
 105bcb1:	48 8b b1 80 00 00 00 	mov    0x80(%rcx),%rsi
 105bcb8:	49 89 f7             	mov    %rsi,%r15
 105bcbb:	49 ff c7             	inc    %r15
 105bcbe:	0f 80 fd 2f 00 00    	jo     105ecc1 <my.vm::run+0x3791>
 105bcc4:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105bcc9:	4c 89 b8 80 00 00 00 	mov    %r15,0x80(%rax)
 105bcd0:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105bcd7:	4d 89 c4             	mov    %r8,%r12
 105bcda:	e9 f1 21 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105bcdf:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105bce6:	00 
 105bce7:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105bcec:	4c 89 da             	mov    %r11,%rdx
 105bcef:	48 89 e9             	mov    %rbp,%rcx
 105bcf2:	e8 c9 81 00 00       	call   1063ec0 <my.vm::read_constant>
 105bcf7:	0f b6 84 24 a8 00 00 	movzbl 0xa8(%rsp),%eax
 105bcfe:	00 
 105bcff:	83 f8 03             	cmp    $0x3,%eax
 105bd02:	0f 85 af 2c 00 00    	jne    105e9b7 <my.vm::run+0x3487>
 105bd08:	4c 89 fe             	mov    %r15,%rsi
 105bd0b:	48 ff ce             	dec    %rsi
 105bd0e:	0f 80 cf 2f 00 00    	jo     105ece3 <my.vm::run+0x37b3>
 105bd14:	48 8b 9c 24 d0 00 00 	mov    0xd0(%rsp),%rbx
 105bd1b:	00 
 105bd1c:	4c 8b a4 24 c8 00 00 	mov    0xc8(%rsp),%r12
 105bd23:	00 
 105bd24:	48 8b ac 24 c0 00 00 	mov    0xc0(%rsp),%rbp
 105bd2b:	00 
 105bd2c:	4c 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%r8
 105bd33:	00 
 105bd34:	48 8b 84 24 b8 00 00 	mov    0xb8(%rsp),%rax
 105bd3b:	00 
 105bd3c:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 105bd41:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105bd46:	48 89 b0 80 00 00 00 	mov    %rsi,0x80(%rax)
 105bd4d:	48 8b 40 78          	mov    0x78(%rax),%rax
 105bd51:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bd55:	48 39 d6             	cmp    %rdx,%rsi
 105bd58:	0f 83 81 26 00 00    	jae    105e3df <my.vm::run+0x2eaf>
 105bd5e:	48 89 f1             	mov    %rsi,%rcx
 105bd61:	48 c1 e1 04          	shl    $0x4,%rcx
 105bd65:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 105bd6a:	83 fa 03             	cmp    $0x3,%edx
 105bd6d:	0f 85 9b 2c 00 00    	jne    105ea0e <my.vm::run+0x34de>
 105bd73:	48 01 c8             	add    %rcx,%rax
 105bd76:	48 83 c0 20          	add    $0x20,%rax
 105bd7a:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105bd7e:	48 8d bc 24 08 09 00 	lea    0x908(%rsp),%rdi
 105bd85:	00 
 105bd86:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105bd8b:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105bd90:	e8 0b 82 00 00       	call   1063fa0 <my.vm::bind_method>
 105bd95:	f6 84 24 08 09 00 00 	testb  $0x1,0x908(%rsp)
 105bd9c:	01 
 105bd9d:	0f 84 b6 2a 00 00    	je     105e859 <my.vm::run+0x3329>
 105bda3:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105bda8:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105bdaf:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105bdb6:	4d 89 e0             	mov    %r12,%r8
 105bdb9:	49 89 d9             	mov    %rbx,%r9
 105bdbc:	e9 40 1e 00 00       	jmp    105dc01 <my.vm::run+0x26d1>
 105bdc1:	4c 89 fe             	mov    %r15,%rsi
 105bdc4:	48 ff ce             	dec    %rsi
 105bdc7:	0f 80 bb 2e 00 00    	jo     105ec88 <my.vm::run+0x3758>
 105bdcd:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105bdd2:	48 89 b0 80 00 00 00 	mov    %rsi,0x80(%rax)
 105bdd9:	48 8b 40 78          	mov    0x78(%rax),%rax
 105bddd:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bde1:	48 39 d6             	cmp    %rdx,%rsi
 105bde4:	0f 83 a3 23 00 00    	jae    105e18d <my.vm::run+0x2c5d>
 105bdea:	48 89 f1             	mov    %rsi,%rcx
 105bded:	48 c1 e1 04          	shl    $0x4,%rcx
 105bdf1:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105bdf7:	c5 f9 29 44 24 30    	vmovapd %xmm0,0x30(%rsp)
 105bdfd:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105be02:	4c 89 f7             	mov    %r14,%rdi
 105be05:	4d 89 cf             	mov    %r9,%r15
 105be08:	4c 89 ce             	mov    %r9,%rsi
 105be0b:	e8 20 90 00 00       	call   1064e30 <my.vm::close_upvalues>
 105be10:	49 8b b6 90 00 00 00 	mov    0x90(%r14),%rsi
 105be17:	49 89 f6             	mov    %rsi,%r14
 105be1a:	49 ff ce             	dec    %r14
 105be1d:	0f 80 ff 30 00 00    	jo     105ef22 <my.vm::run+0x39f2>
 105be23:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105be28:	4c 89 b0 90 00 00 00 	mov    %r14,0x90(%rax)
 105be2f:	0f 84 43 2a 00 00    	je     105e878 <my.vm::run+0x3348>
 105be35:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105be3a:	4c 89 b8 80 00 00 00 	mov    %r15,0x80(%rax)
 105be41:	48 8b 40 78          	mov    0x78(%rax),%rax
 105be45:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105be49:	4c 89 f9             	mov    %r15,%rcx
 105be4c:	49 39 d7             	cmp    %rdx,%r15
 105be4f:	0f 83 9d 26 00 00    	jae    105e4f2 <my.vm::run+0x2fc2>
 105be55:	48 c1 e1 04          	shl    $0x4,%rcx
 105be59:	c5 f9 28 44 24 30    	vmovapd 0x30(%rsp),%xmm0
 105be5f:	c5 f9 54 05 79 85 fa 	vandpd -0x57a87(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105be66:	ff 
 105be67:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 105be6d:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105be72:	48 89 41 78          	mov    %rax,0x78(%rcx)
 105be76:	49 ff c7             	inc    %r15
 105be79:	4c 89 b9 80 00 00 00 	mov    %r15,0x80(%rcx)
 105be80:	4c 89 f6             	mov    %r14,%rsi
 105be83:	48 ff ce             	dec    %rsi
 105be86:	0f 80 cc 30 00 00    	jo     105ef58 <my.vm::run+0x3a28>
 105be8c:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105be91:	48 8b 80 88 00 00 00 	mov    0x88(%rax),%rax
 105be98:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105be9c:	48 39 d6             	cmp    %rdx,%rsi
 105be9f:	0f 82 58 1a 00 00    	jb     105d8fd <my.vm::run+0x23cd>
 105bea5:	48 89 f1             	mov    %rsi,%rcx
 105bea8:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105beac:	48 21 d1             	and    %rdx,%rcx
 105beaf:	48 01 f1             	add    %rsi,%rcx
 105beb2:	48 39 d1             	cmp    %rdx,%rcx
 105beb5:	0f 82 45 1a 00 00    	jb     105d900 <my.vm::run+0x23d0>
 105bebb:	e9 fe 34 00 00       	jmp    105f3be <my.vm::run+0x3e8e>
 105bec0:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105bec7:	00 
 105bec8:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105becd:	4c 89 f6             	mov    %r14,%rsi
 105bed0:	4c 89 da             	mov    %r11,%rdx
 105bed3:	48 89 e9             	mov    %rbp,%rcx
 105bed6:	e8 25 7f 00 00       	call   1063e00 <my.vm::read_byte>
 105bedb:	48 8b 94 24 a8 00 00 	mov    0xa8(%rsp),%rdx
 105bee2:	00 
 105bee3:	48 8b b4 24 b0 00 00 	mov    0xb0(%rsp),%rsi
 105beea:	00 
 105beeb:	48 8b 84 24 b8 00 00 	mov    0xb8(%rsp),%rax
 105bef2:	00 
 105bef3:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
 105bef8:	48 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%rax
 105beff:	00 
 105bf00:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105bf05:	4c 8b a4 24 c8 00 00 	mov    0xc8(%rsp),%r12
 105bf0c:	00 
 105bf0d:	4c 89 f7             	mov    %r14,%rdi
 105bf10:	48 89 f5             	mov    %rsi,%rbp
 105bf13:	e8 18 ef 00 00       	call   106ae30 <my.heap::closure_upvalue>
 105bf18:	48 89 c3             	mov    %rax,%rbx
 105bf1b:	48 8d bc 24 40 03 00 	lea    0x340(%rsp),%rdi
 105bf22:	00 
 105bf23:	4c 89 f6             	mov    %r14,%rsi
 105bf26:	48 89 c2             	mov    %rax,%rdx
 105bf29:	e8 02 ee 00 00       	call   106ad30 <my.heap::upvalue_obj>
 105bf2e:	48 8b 84 24 40 03 00 	mov    0x340(%rsp),%rax
 105bf35:	00 
 105bf36:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105bf3a:	49 8b 8e 80 00 00 00 	mov    0x80(%r14),%rcx
 105bf41:	48 89 ce             	mov    %rcx,%rsi
 105bf44:	48 ff ce             	dec    %rsi
 105bf47:	0f 90 c2             	seto   %dl
 105bf4a:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 105bf4e:	0f 84 b3 1a 00 00    	je     105da07 <my.vm::run+0x24d7>
 105bf54:	84 d2                	test   %dl,%dl
 105bf56:	0f 85 92 30 00 00    	jne    105efee <my.vm::run+0x3abe>
 105bf5c:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105bf60:	48 39 d6             	cmp    %rdx,%rsi
 105bf63:	4d 89 e1             	mov    %r12,%r9
 105bf66:	49 89 eb             	mov    %rbp,%r11
 105bf69:	0f 83 f2 25 00 00    	jae    105e561 <my.vm::run+0x3031>
 105bf6f:	48 89 f1             	mov    %rsi,%rcx
 105bf72:	48 c1 e1 04          	shl    $0x4,%rcx
 105bf76:	c5 f9 10 44 0f 20    	vmovupd 0x20(%rdi,%rcx,1),%xmm0
 105bf7c:	48 39 d0             	cmp    %rdx,%rax
 105bf7f:	0f 83 f7 25 00 00    	jae    105e57c <my.vm::run+0x304c>
 105bf85:	48 89 c1             	mov    %rax,%rcx
 105bf88:	48 83 c7 20          	add    $0x20,%rdi
 105bf8c:	48 c1 e1 04          	shl    $0x4,%rcx
 105bf90:	c5 f9 54 05 48 84 fa 	vandpd -0x57bb8(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105bf97:	ff 
 105bf98:	c5 f9 11 04 0f       	vmovupd %xmm0,(%rdi,%rcx,1)
 105bf9d:	e9 18 1b 00 00       	jmp    105daba <my.vm::run+0x258a>
 105bfa2:	4c 89 fe             	mov    %r15,%rsi
 105bfa5:	48 ff ce             	dec    %rsi
 105bfa8:	0f 80 2c 2f 00 00    	jo     105eeda <my.vm::run+0x39aa>
 105bfae:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105bfb3:	48 89 b0 80 00 00 00 	mov    %rsi,0x80(%rax)
 105bfba:	48 8b 40 78          	mov    0x78(%rax),%rax
 105bfbe:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bfc2:	48 39 d6             	cmp    %rdx,%rsi
 105bfc5:	0f 83 dd 21 00 00    	jae    105e1a8 <my.vm::run+0x2c78>
 105bfcb:	49 89 f7             	mov    %rsi,%r15
 105bfce:	e9 fd 1e 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105bfd3:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
 105bfd8:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105bfdd:	48 8b b0 80 00 00 00 	mov    0x80(%rax),%rsi
 105bfe4:	48 89 f0             	mov    %rsi,%rax
 105bfe7:	48 ff c8             	dec    %rax
 105bfea:	0f 80 b4 2e 00 00    	jo     105eea4 <my.vm::run+0x3974>
 105bff0:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105bff5:	4c 8b 69 78          	mov    0x78(%rcx),%r13
 105bff9:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105bffd:	49 89 c7             	mov    %rax,%r15
 105c000:	48 89 c5             	mov    %rax,%rbp
 105c003:	48 39 d0             	cmp    %rdx,%rax
 105c006:	0f 83 b7 21 00 00    	jae    105e1c3 <my.vm::run+0x2c93>
 105c00c:	49 c1 e7 04          	shl    $0x4,%r15
 105c010:	43 80 7c 3d 20 03    	cmpb   $0x3,0x20(%r13,%r15,1)
 105c016:	0f 85 01 18 00 00    	jne    105d81d <my.vm::run+0x22ed>
 105c01c:	4b 8b 5c 3d 28       	mov    0x28(%r13,%r15,1),%rbx
 105c021:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c026:	48 8b 00             	mov    (%rax),%rax
 105c029:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c02d:	48 89 d9             	mov    %rbx,%rcx
 105c030:	48 39 d3             	cmp    %rdx,%rbx
 105c033:	0f 83 5e 25 00 00    	jae    105e597 <my.vm::run+0x3067>
 105c039:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105c03d:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 105c042:	0f 85 d5 17 00 00    	jne    105d81d <my.vm::run+0x22ed>
 105c048:	48 8d bc 24 48 05 00 	lea    0x548(%rsp),%rdi
 105c04f:	00 
 105c050:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105c055:	4c 89 da             	mov    %r11,%rdx
 105c058:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 105c05d:	e8 5e 7e 00 00       	call   1063ec0 <my.vm::read_constant>
 105c062:	0f b6 84 24 48 05 00 	movzbl 0x548(%rsp),%eax
 105c069:	00 
 105c06a:	83 f8 03             	cmp    $0x3,%eax
 105c06d:	0f 85 5e 2f 00 00    	jne    105efd1 <my.vm::run+0x3aa1>
 105c073:	48 8b 84 24 70 05 00 	mov    0x570(%rsp),%rax
 105c07a:	00 
 105c07b:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105c080:	48 8b 84 24 68 05 00 	mov    0x568(%rsp),%rax
 105c087:	00 
 105c088:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105c08d:	48 8b 84 24 60 05 00 	mov    0x560(%rsp),%rax
 105c094:	00 
 105c095:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
 105c09a:	4c 8b a4 24 50 05 00 	mov    0x550(%rsp),%r12
 105c0a1:	00 
 105c0a2:	48 8b 84 24 58 05 00 	mov    0x558(%rsp),%rax
 105c0a9:	00 
 105c0aa:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 105c0af:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105c0b4:	4c 89 f7             	mov    %r14,%rdi
 105c0b7:	4c 89 e6             	mov    %r12,%rsi
 105c0ba:	e8 a1 e8 00 00       	call   106a960 <my.heap::string_hash>
 105c0bf:	4c 89 f7             	mov    %r14,%rdi
 105c0c2:	48 89 de             	mov    %rbx,%rsi
 105c0c5:	4c 89 e2             	mov    %r12,%rdx
 105c0c8:	89 c1                	mov    %eax,%ecx
 105c0ca:	e8 71 ee 00 00       	call   106af40 <my.heap::instance_field>
 105c0cf:	3c 01                	cmp    $0x1,%al
 105c0d1:	0f 85 3b 1e 00 00    	jne    105df12 <my.vm::run+0x29e2>
 105c0d7:	4b 8d 04 2f          	lea    (%r15,%r13,1),%rax
 105c0db:	48 83 c0 20          	add    $0x20,%rax
 105c0df:	0f b6 d2             	movzbl %dl,%edx
 105c0e2:	48 89 10             	mov    %rdx,(%rax)
 105c0e5:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105c0e9:	49 89 ef             	mov    %rbp,%r15
 105c0ec:	49 ff c7             	inc    %r15
 105c0ef:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c0f4:	4c 89 b8 80 00 00 00 	mov    %r15,0x80(%rax)
 105c0fb:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105c102:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105c107:	e9 25 f9 ff ff       	jmp    105ba31 <my.vm::run+0x501>
 105c10c:	48 8d bc 24 60 03 00 	lea    0x360(%rsp),%rdi
 105c113:	00 
 105c114:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105c119:	4c 89 da             	mov    %r11,%rdx
 105c11c:	48 89 e9             	mov    %rbp,%rcx
 105c11f:	e8 9c 7d 00 00       	call   1063ec0 <my.vm::read_constant>
 105c124:	0f b6 84 24 60 03 00 	movzbl 0x360(%rsp),%eax
 105c12b:	00 
 105c12c:	83 f8 03             	cmp    $0x3,%eax
 105c12f:	0f 85 65 28 00 00    	jne    105e99a <my.vm::run+0x346a>
 105c135:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c13a:	48 8b 80 80 00 00 00 	mov    0x80(%rax),%rax
 105c141:	48 89 c6             	mov    %rax,%rsi
 105c144:	48 ff ce             	dec    %rsi
 105c147:	0f 80 4f 2a 00 00    	jo     105eb9c <my.vm::run+0x366c>
 105c14d:	48 8b 8c 24 88 03 00 	mov    0x388(%rsp),%rcx
 105c154:	00 
 105c155:	4c 8b 84 24 80 03 00 	mov    0x380(%rsp),%r8
 105c15c:	00 
 105c15d:	4c 8b 8c 24 78 03 00 	mov    0x378(%rsp),%r9
 105c164:	00 
 105c165:	48 8b 9c 24 68 03 00 	mov    0x368(%rsp),%rbx
 105c16c:	00 
 105c16d:	48 8b bc 24 70 03 00 	mov    0x370(%rsp),%rdi
 105c174:	00 
 105c175:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c17a:	48 8b 40 78          	mov    0x78(%rax),%rax
 105c17e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c182:	48 39 d6             	cmp    %rdx,%rsi
 105c185:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105c18a:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
 105c18f:	4c 89 44 24 18       	mov    %r8,0x18(%rsp)
 105c194:	4c 89 4c 24 28       	mov    %r9,0x28(%rsp)
 105c199:	0f 83 5b 22 00 00    	jae    105e3fa <my.vm::run+0x2eca>
 105c19f:	48 89 f1             	mov    %rsi,%rcx
 105c1a2:	48 c1 e1 04          	shl    $0x4,%rcx
 105c1a6:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105c1ab:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 105c1af:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105c1b4:	4c 89 f7             	mov    %r14,%rdi
 105c1b7:	48 89 de             	mov    %rbx,%rsi
 105c1ba:	e8 a1 e7 00 00       	call   106a960 <my.heap::string_hash>
 105c1bf:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105c1c3:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105c1c7:	48 89 da             	mov    %rbx,%rdx
 105c1ca:	89 c1                	mov    %eax,%ecx
 105c1cc:	41 89 e8             	mov    %ebp,%r8d
 105c1cf:	4d 89 f9             	mov    %r15,%r9
 105c1d2:	e8 69 e8 00 00       	call   106aa40 <my.table::set>
 105c1d7:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105c1db:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105c1df:	a8 01                	test   $0x1,%al
 105c1e1:	0f 84 f1 17 00 00    	je     105d9d8 <my.vm::run+0x24a8>
 105c1e7:	49 89 d7             	mov    %rdx,%r15
 105c1ea:	49 89 cc             	mov    %rcx,%r12
 105c1ed:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105c1f2:	4c 89 f7             	mov    %r14,%rdi
 105c1f5:	48 89 de             	mov    %rbx,%rsi
 105c1f8:	e8 63 e7 00 00       	call   106a960 <my.heap::string_hash>
 105c1fd:	4c 89 ff             	mov    %r15,%rdi
 105c200:	4c 89 e6             	mov    %r12,%rsi
 105c203:	48 89 da             	mov    %rbx,%rdx
 105c206:	89 c1                	mov    %eax,%ecx
 105c208:	e8 23 ea 00 00       	call   106ac30 <my.table::delete>
 105c20d:	49 89 46 30          	mov    %rax,0x30(%r14)
 105c211:	49 89 56 38          	mov    %rdx,0x38(%r14)
 105c215:	4c 89 f7             	mov    %r14,%rdi
 105c218:	48 89 de             	mov    %rbx,%rsi
 105c21b:	e8 50 e5 00 00       	call   106a770 <my.heap::string_chars>
 105c220:	48 89 c3             	mov    %rax,%rbx
 105c223:	48 8d 3d b6 68 fb ff 	lea    -0x4974a(%rip),%rdi        # 1012ae0 <core_number_pairs+0xb880>
 105c22a:	48 89 c6             	mov    %rax,%rsi
 105c22d:	e8 ce 34 fd ff       	call   102f700 <myl_core_bytes_concat>
 105c232:	49 89 c7             	mov    %rax,%r15
 105c235:	48 89 df             	mov    %rbx,%rdi
 105c238:	e8 c3 80 fc ff       	call   1024300 <myl_core_drop_owned>
 105c23d:	48 8d 35 dc 68 fb ff 	lea    -0x49724(%rip),%rsi        # 1012b20 <core_number_pairs+0xb8c0>
 105c244:	4c 89 ff             	mov    %r15,%rdi
 105c247:	e8 b4 34 fd ff       	call   102f700 <myl_core_bytes_concat>
 105c24c:	48 89 c3             	mov    %rax,%rbx
 105c24f:	4c 89 ff             	mov    %r15,%rdi
 105c252:	e8 a9 80 fc ff       	call   1024300 <myl_core_drop_owned>
 105c257:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105c25e:	00 
 105c25f:	4c 89 f6             	mov    %r14,%rsi
 105c262:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105c267:	48 89 d9             	mov    %rbx,%rcx
 105c26a:	e8 11 77 00 00       	call   1063980 <my.vm::runtime_error>
 105c26f:	48 89 df             	mov    %rbx,%rdi
 105c272:	e8 89 80 fc ff       	call   1024300 <myl_core_drop_owned>
 105c277:	f6 84 24 a8 00 00 00 	testb  $0x1,0xa8(%rsp)
 105c27e:	01 
 105c27f:	48 8b 6c 24 28       	mov    0x28(%rsp),%rbp
 105c284:	0f 85 29 17 00 00    	jne    105d9b3 <my.vm::run+0x2483>
 105c28a:	e9 ca 25 00 00       	jmp    105e859 <my.vm::run+0x3329>
 105c28f:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c294:	48 8b 40 78          	mov    0x78(%rax),%rax
 105c298:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c29c:	4c 89 f9             	mov    %r15,%rcx
 105c29f:	49 39 d7             	cmp    %rdx,%r15
 105c2a2:	0f 83 5e 1e 00 00    	jae    105e106 <my.vm::run+0x2bd6>
 105c2a8:	48 c1 e1 04          	shl    $0x4,%rcx
 105c2ac:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105c2b3:	00 00 
 105c2b5:	c6 44 08 28 01       	movb   $0x1,0x28(%rax,%rcx,1)
 105c2ba:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105c2bf:	48 89 41 78          	mov    %rax,0x78(%rcx)
 105c2c3:	4c 89 f8             	mov    %r15,%rax
 105c2c6:	48 ff c0             	inc    %rax
 105c2c9:	0f 81 95 02 00 00    	jno    105c564 <my.vm::run+0x1034>
 105c2cf:	e9 bc 2b 00 00       	jmp    105ee90 <my.vm::run+0x3960>
 105c2d4:	4c 89 fe             	mov    %r15,%rsi
 105c2d7:	48 ff ce             	dec    %rsi
 105c2da:	0f 80 53 2c 00 00    	jo     105ef33 <my.vm::run+0x3a03>
 105c2e0:	4c 89 c3             	mov    %r8,%rbx
 105c2e3:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c2e8:	48 89 b0 80 00 00 00 	mov    %rsi,0x80(%rax)
 105c2ef:	48 8b 40 78          	mov    0x78(%rax),%rax
 105c2f3:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c2f7:	48 89 f1             	mov    %rsi,%rcx
 105c2fa:	48 39 d6             	cmp    %rdx,%rsi
 105c2fd:	0f 83 db 1e 00 00    	jae    105e1de <my.vm::run+0x2cae>
 105c303:	49 89 f7             	mov    %rsi,%r15
 105c306:	49 ff cf             	dec    %r15
 105c309:	0f 80 a6 2b 00 00    	jo     105eeb5 <my.vm::run+0x3985>
 105c30f:	4d 89 ca             	mov    %r9,%r10
 105c312:	48 c1 e1 04          	shl    $0x4,%rcx
 105c316:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105c31c:	48 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%rdi
 105c321:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105c326:	4c 89 b9 80 00 00 00 	mov    %r15,0x80(%rcx)
 105c32d:	4c 89 f9             	mov    %r15,%rcx
 105c330:	49 39 d7             	cmp    %rdx,%r15
 105c333:	0f 83 a1 1f 00 00    	jae    105e2da <my.vm::run+0x2daa>
 105c339:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105c33d:	48 c1 e1 04          	shl    $0x4,%rcx
 105c341:	44 0f b6 0c 0a       	movzbl (%rdx,%rcx,1),%r9d
 105c346:	48 8b 74 0a 08       	mov    0x8(%rdx,%rcx,1),%rsi
 105c34b:	41 83 f9 02          	cmp    $0x2,%r9d
 105c34f:	0f 84 45 1a 00 00    	je     105dd9a <my.vm::run+0x286a>
 105c355:	41 83 f9 01          	cmp    $0x1,%r9d
 105c359:	0f 84 23 1a 00 00    	je     105dd82 <my.vm::run+0x2852>
 105c35f:	45 85 c9             	test   %r9d,%r9d
 105c362:	0f 85 65 1a 00 00    	jne    105ddcd <my.vm::run+0x289d>
 105c368:	45 84 c0             	test   %r8b,%r8b
 105c36b:	40 0f 94 c6          	sete   %sil
 105c36f:	e9 d5 1a 00 00       	jmp    105de49 <my.vm::run+0x2919>
 105c374:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c379:	48 8b 40 78          	mov    0x78(%rax),%rax
 105c37d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c381:	4c 89 f9             	mov    %r15,%rcx
 105c384:	49 39 d7             	cmp    %rdx,%r15
 105c387:	0f 83 94 1d 00 00    	jae    105e121 <my.vm::run+0x2bf1>
 105c38d:	48 c1 e1 04          	shl    $0x4,%rcx
 105c391:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105c398:	00 00 
 105c39a:	c6 44 08 28 00       	movb   $0x0,0x28(%rax,%rcx,1)
 105c39f:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105c3a4:	48 89 41 78          	mov    %rax,0x78(%rcx)
 105c3a8:	4c 89 f8             	mov    %r15,%rax
 105c3ab:	48 ff c0             	inc    %rax
 105c3ae:	0f 81 b0 01 00 00    	jno    105c564 <my.vm::run+0x1034>
 105c3b4:	e9 f4 28 00 00       	jmp    105ecad <my.vm::run+0x377d>
 105c3b9:	48 8d bc 24 60 03 00 	lea    0x360(%rsp),%rdi
 105c3c0:	00 
 105c3c1:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105c3c6:	4c 89 da             	mov    %r11,%rdx
 105c3c9:	48 89 e9             	mov    %rbp,%rcx
 105c3cc:	e8 ef 7a 00 00       	call   1063ec0 <my.vm::read_constant>
 105c3d1:	0f b6 84 24 60 03 00 	movzbl 0x360(%rsp),%eax
 105c3d8:	00 
 105c3d9:	83 f8 03             	cmp    $0x3,%eax
 105c3dc:	0f 85 7e 25 00 00    	jne    105e960 <my.vm::run+0x3430>
 105c3e2:	48 8b 84 24 88 03 00 	mov    0x388(%rsp),%rax
 105c3e9:	00 
 105c3ea:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105c3ef:	48 8b 84 24 80 03 00 	mov    0x380(%rsp),%rax
 105c3f6:	00 
 105c3f7:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105c3fc:	48 8b ac 24 78 03 00 	mov    0x378(%rsp),%rbp
 105c403:	00 
 105c404:	48 8b 9c 24 68 03 00 	mov    0x368(%rsp),%rbx
 105c40b:	00 
 105c40c:	48 8b 84 24 70 03 00 	mov    0x370(%rsp),%rax
 105c413:	00 
 105c414:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 105c419:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 105c41e:	4c 8b 7f 30          	mov    0x30(%rdi),%r15
 105c422:	4c 8b 67 38          	mov    0x38(%rdi),%r12
 105c426:	48 89 de             	mov    %rbx,%rsi
 105c429:	e8 32 e5 00 00       	call   106a960 <my.heap::string_hash>
 105c42e:	4c 89 ff             	mov    %r15,%rdi
 105c431:	4c 89 e6             	mov    %r12,%rsi
 105c434:	48 89 da             	mov    %rbx,%rdx
 105c437:	89 c1                	mov    %eax,%ecx
 105c439:	e8 12 e4 00 00       	call   106a850 <my.table::get>
 105c43e:	3c 01                	cmp    $0x1,%al
 105c440:	0f 85 f8 14 00 00    	jne    105d93e <my.vm::run+0x240e>
 105c446:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c44b:	48 8b 78 78          	mov    0x78(%rax),%rdi
 105c44f:	48 8b b0 80 00 00 00 	mov    0x80(%rax),%rsi
 105c456:	48 8b 47 08          	mov    0x8(%rdi),%rax
 105c45a:	49 89 f0             	mov    %rsi,%r8
 105c45d:	48 39 c6             	cmp    %rax,%rsi
 105c460:	0f 83 67 21 00 00    	jae    105e5cd <my.vm::run+0x309d>
 105c466:	49 c1 e0 04          	shl    $0x4,%r8
 105c46a:	0f b6 c2             	movzbl %dl,%eax
 105c46d:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 105c472:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 105c477:	49 89 f7             	mov    %rsi,%r15
 105c47a:	49 ff c7             	inc    %r15
 105c47d:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105c482:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105c487:	0f 80 95 2b 00 00    	jo     105f022 <my.vm::run+0x3af2>
 105c48d:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c492:	4c 89 b8 80 00 00 00 	mov    %r15,0x80(%rax)
 105c499:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105c4a0:	e9 59 17 00 00       	jmp    105dbfe <my.vm::run+0x26ce>
 105c4a5:	48 8d bc 24 d0 02 00 	lea    0x2d0(%rsp),%rdi
 105c4ac:	00 
 105c4ad:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 105c4b2:	48 89 de             	mov    %rbx,%rsi
 105c4b5:	4c 89 da             	mov    %r11,%rdx
 105c4b8:	48 89 e9             	mov    %rbp,%rcx
 105c4bb:	e8 00 7a 00 00       	call   1063ec0 <my.vm::read_constant>
 105c4c0:	c5 f9 28 84 24 d0 02 	vmovapd 0x2d0(%rsp),%xmm0
 105c4c7:	00 00 
 105c4c9:	4c 8b 9c 24 e0 02 00 	mov    0x2e0(%rsp),%r11
 105c4d0:	00 
 105c4d1:	48 8b ac 24 e8 02 00 	mov    0x2e8(%rsp),%rbp
 105c4d8:	00 
 105c4d9:	4c 8b 84 24 f0 02 00 	mov    0x2f0(%rsp),%r8
 105c4e0:	00 
 105c4e1:	4c 8b 8c 24 f8 02 00 	mov    0x2f8(%rsp),%r9
 105c4e8:	00 
 105c4e9:	48 8b 43 78          	mov    0x78(%rbx),%rax
 105c4ed:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c4f1:	4c 89 f9             	mov    %r15,%rcx
 105c4f4:	49 39 d7             	cmp    %rdx,%r15
 105c4f7:	0f 83 3f 1c 00 00    	jae    105e13c <my.vm::run+0x2c0c>
 105c4fd:	48 c1 e1 04          	shl    $0x4,%rcx
 105c501:	c5 f9 54 05 d7 7e fa 	vandpd -0x58129(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c508:	ff 
 105c509:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 105c50f:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105c514:	48 89 41 78          	mov    %rax,0x78(%rcx)
 105c518:	4c 89 f8             	mov    %r15,%rax
 105c51b:	48 ff c0             	inc    %rax
 105c51e:	0f 81 bb 01 00 00    	jno    105c6df <my.vm::run+0x11af>
 105c524:	e9 d1 28 00 00       	jmp    105edfa <my.vm::run+0x38ca>
 105c529:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c52e:	48 8b 40 78          	mov    0x78(%rax),%rax
 105c532:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c536:	4c 89 f9             	mov    %r15,%rcx
 105c539:	49 39 d7             	cmp    %rdx,%r15
 105c53c:	0f 83 15 1c 00 00    	jae    105e157 <my.vm::run+0x2c27>
 105c542:	48 c1 e1 04          	shl    $0x4,%rcx
 105c546:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105c54d:	00 00 
 105c54f:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105c554:	48 89 41 78          	mov    %rax,0x78(%rcx)
 105c558:	4c 89 f8             	mov    %r15,%rax
 105c55b:	48 ff c0             	inc    %rax
 105c55e:	0f 80 17 28 00 00    	jo     105ed7b <my.vm::run+0x384b>
 105c564:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105c569:	48 89 81 80 00 00 00 	mov    %rax,0x80(%rcx)
 105c570:	49 89 c7             	mov    %rax,%r15
 105c573:	e9 58 19 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105c578:	48 8d bc 24 30 02 00 	lea    0x230(%rsp),%rdi
 105c57f:	00 
 105c580:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105c585:	4c 89 da             	mov    %r11,%rdx
 105c588:	48 89 e9             	mov    %rbp,%rcx
 105c58b:	e8 f0 7e 00 00       	call   1064480 <my.vm::read_short>
 105c590:	48 8b 94 24 30 02 00 	mov    0x230(%rsp),%rdx
 105c597:	00 
 105c598:	48 8b b4 24 48 02 00 	mov    0x248(%rsp),%rsi
 105c59f:	00 
 105c5a0:	49 89 f0             	mov    %rsi,%r8
 105c5a3:	49 01 d0             	add    %rdx,%r8
 105c5a6:	0f 80 e3 27 00 00    	jo     105ed8f <my.vm::run+0x385f>
 105c5ac:	4c 8b 9c 24 38 02 00 	mov    0x238(%rsp),%r11
 105c5b3:	00 
 105c5b4:	48 8b ac 24 40 02 00 	mov    0x240(%rsp),%rbp
 105c5bb:	00 
 105c5bc:	4c 8b 8c 24 50 02 00 	mov    0x250(%rsp),%r9
 105c5c3:	00 
 105c5c4:	4d 89 c4             	mov    %r8,%r12
 105c5c7:	e9 04 19 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105c5cc:	4c 89 fb             	mov    %r15,%rbx
 105c5cf:	48 ff cb             	dec    %rbx
 105c5d2:	0f 80 0e 28 00 00    	jo     105ede6 <my.vm::run+0x38b6>
 105c5d8:	4c 89 44 24 18       	mov    %r8,0x18(%rsp)
 105c5dd:	4c 89 5c 24 30       	mov    %r11,0x30(%rsp)
 105c5e2:	4c 89 4c 24 20       	mov    %r9,0x20(%rsp)
 105c5e7:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c5ec:	48 89 98 80 00 00 00 	mov    %rbx,0x80(%rax)
 105c5f3:	48 8b 40 78          	mov    0x78(%rax),%rax
 105c5f7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c5fb:	48 89 de             	mov    %rbx,%rsi
 105c5fe:	48 39 d3             	cmp    %rdx,%rbx
 105c601:	0f 83 f2 1b 00 00    	jae    105e1f9 <my.vm::run+0x2cc9>
 105c607:	48 c1 e6 04          	shl    $0x4,%rsi
 105c60b:	48 8b 4c 30 28       	mov    0x28(%rax,%rsi,1),%rcx
 105c610:	8b 54 30 20          	mov    0x20(%rax,%rsi,1),%edx
 105c614:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 105c619:	48 8b 74 24 48       	mov    0x48(%rsp),%rsi
 105c61e:	e8 9d 7b 00 00       	call   10641c0 <my.output::print_value>
 105c623:	49 89 df             	mov    %rbx,%r15
 105c626:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105c62b:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105c630:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105c635:	e9 88 18 00 00       	jmp    105dec2 <my.vm::run+0x2992>
 105c63a:	48 8d bc 24 80 02 00 	lea    0x280(%rsp),%rdi
 105c641:	00 
 105c642:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105c647:	4c 89 da             	mov    %r11,%rdx
 105c64a:	48 89 e9             	mov    %rbp,%rcx
 105c64d:	e8 ae 77 00 00       	call   1063e00 <my.vm::read_byte>
 105c652:	48 8b 94 24 80 02 00 	mov    0x280(%rsp),%rdx
 105c659:	00 
 105c65a:	4c 8b 8c 24 a0 02 00 	mov    0x2a0(%rsp),%r9
 105c661:	00 
 105c662:	4c 89 ce             	mov    %r9,%rsi
 105c665:	48 01 d6             	add    %rdx,%rsi
 105c668:	0f 80 a0 27 00 00    	jo     105ee0e <my.vm::run+0x38de>
 105c66e:	4c 8b 9c 24 88 02 00 	mov    0x288(%rsp),%r11
 105c675:	00 
 105c676:	48 8b ac 24 90 02 00 	mov    0x290(%rsp),%rbp
 105c67d:	00 
 105c67e:	4c 8b 84 24 98 02 00 	mov    0x298(%rsp),%r8
 105c685:	00 
 105c686:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c68b:	48 8b 40 78          	mov    0x78(%rax),%rax
 105c68f:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c693:	48 39 d6             	cmp    %rdx,%rsi
 105c696:	0f 83 78 1b 00 00    	jae    105e214 <my.vm::run+0x2ce4>
 105c69c:	48 89 f1             	mov    %rsi,%rcx
 105c69f:	48 c1 e1 04          	shl    $0x4,%rcx
 105c6a3:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105c6a9:	4c 89 f9             	mov    %r15,%rcx
 105c6ac:	49 39 d7             	cmp    %rdx,%r15
 105c6af:	0f 83 b0 1b 00 00    	jae    105e265 <my.vm::run+0x2d35>
 105c6b5:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105c6b9:	48 c1 e1 04          	shl    $0x4,%rcx
 105c6bd:	c5 f9 54 05 1b 7d fa 	vandpd -0x582e5(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c6c4:	ff 
 105c6c5:	c5 f9 11 04 0a       	vmovupd %xmm0,(%rdx,%rcx,1)
 105c6ca:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105c6cf:	48 89 41 78          	mov    %rax,0x78(%rcx)
 105c6d3:	4c 89 f8             	mov    %r15,%rax
 105c6d6:	48 ff c0             	inc    %rax
 105c6d9:	0f 80 52 27 00 00    	jo     105ee31 <my.vm::run+0x3901>
 105c6df:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105c6e4:	48 89 81 80 00 00 00 	mov    %rax,0x80(%rcx)
 105c6eb:	49 89 c7             	mov    %rax,%r15
 105c6ee:	4d 89 c4             	mov    %r8,%r12
 105c6f1:	e9 da 17 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105c6f6:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c6fb:	48 8b b0 80 00 00 00 	mov    0x80(%rax),%rsi
 105c702:	49 89 f7             	mov    %rsi,%r15
 105c705:	49 ff cf             	dec    %r15
 105c708:	0f 80 39 28 00 00    	jo     105ef47 <my.vm::run+0x3a17>
 105c70e:	4c 89 f9             	mov    %r15,%rcx
 105c711:	48 ff c9             	dec    %rcx
 105c714:	0f 80 f4 27 00 00    	jo     105ef0e <my.vm::run+0x39de>
 105c71a:	4c 89 44 24 18       	mov    %r8,0x18(%rsp)
 105c71f:	4c 89 5c 24 30       	mov    %r11,0x30(%rsp)
 105c724:	4c 89 4c 24 20       	mov    %r9,0x20(%rsp)
 105c729:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c72e:	48 8b 58 78          	mov    0x78(%rax),%rbx
 105c732:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105c736:	48 89 c8             	mov    %rcx,%rax
 105c739:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
 105c73e:	48 39 d1             	cmp    %rdx,%rcx
 105c741:	0f 83 ae 1b 00 00    	jae    105e2f5 <my.vm::run+0x2dc5>
 105c747:	48 c1 e0 04          	shl    $0x4,%rax
 105c74b:	0f b6 4c 03 20       	movzbl 0x20(%rbx,%rax,1),%ecx
 105c750:	85 c9                	test   %ecx,%ecx
 105c752:	0f 84 89 16 00 00    	je     105dde1 <my.vm::run+0x28b1>
 105c758:	83 f9 01             	cmp    $0x1,%ecx
 105c75b:	0f 84 5f 16 00 00    	je     105ddc0 <my.vm::run+0x2890>
 105c761:	83 f9 03             	cmp    $0x3,%ecx
 105c764:	0f 85 84 16 00 00    	jne    105ddee <my.vm::run+0x28be>
 105c76a:	4c 8b 74 03 28       	mov    0x28(%rbx,%rax,1),%r14
 105c76f:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105c774:	4c 8b 28             	mov    (%rax),%r13
 105c777:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105c77b:	4c 89 f0             	mov    %r14,%rax
 105c77e:	49 39 d6             	cmp    %rdx,%r14
 105c781:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105c786:	4c 8b 54 24 30       	mov    0x30(%rsp),%r10
 105c78b:	4c 8b 44 24 18       	mov    0x18(%rsp),%r8
 105c790:	0f 83 0f 1f 00 00    	jae    105e6a5 <my.vm::run+0x3175>
 105c796:	48 6b c0 38          	imul   $0x38,%rax,%rax
 105c79a:	41 83 7c 05 20 07    	cmpl   $0x7,0x20(%r13,%rax,1)
 105c7a0:	0f 85 d0 16 00 00    	jne    105de76 <my.vm::run+0x2946>
 105c7a6:	48 8d bc 24 98 01 00 	lea    0x198(%rsp),%rdi
 105c7ad:	00 
 105c7ae:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105c7b3:	4c 89 d2             	mov    %r10,%rdx
 105c7b6:	48 89 e9             	mov    %rbp,%rcx
 105c7b9:	e8 02 77 00 00       	call   1063ec0 <my.vm::read_constant>
 105c7be:	0f b6 84 24 98 01 00 	movzbl 0x198(%rsp),%eax
 105c7c5:	00 
 105c7c6:	83 f8 03             	cmp    $0x3,%eax
 105c7c9:	0f 85 8c 28 00 00    	jne    105f05b <my.vm::run+0x3b2b>
 105c7cf:	48 8b 84 24 c0 01 00 	mov    0x1c0(%rsp),%rax
 105c7d6:	00 
 105c7d7:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105c7dc:	4c 8b a4 24 b8 01 00 	mov    0x1b8(%rsp),%r12
 105c7e3:	00 
 105c7e4:	48 8b 84 24 b0 01 00 	mov    0x1b0(%rsp),%rax
 105c7eb:	00 
 105c7ec:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
 105c7f1:	48 8b b4 24 a0 01 00 	mov    0x1a0(%rsp),%rsi
 105c7f8:	00 
 105c7f9:	48 8b 84 24 a8 01 00 	mov    0x1a8(%rsp),%rax
 105c800:	00 
 105c801:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 105c806:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 105c80b:	48 89 74 24 68       	mov    %rsi,0x68(%rsp)
 105c810:	e8 4b e1 00 00       	call   106a960 <my.heap::string_hash>
 105c815:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105c819:	4c 89 f9             	mov    %r15,%rcx
 105c81c:	49 39 d7             	cmp    %rdx,%r15
 105c81f:	0f 83 f7 1e 00 00    	jae    105e71c <my.vm::run+0x31ec>
 105c825:	4c 89 64 24 18       	mov    %r12,0x18(%rsp)
 105c82a:	48 8d 73 20          	lea    0x20(%rbx),%rsi
 105c82e:	48 c1 e1 04          	shl    $0x4,%rcx
 105c832:	44 0f b6 04 0e       	movzbl (%rsi,%rcx,1),%r8d
 105c837:	48 8b 6c 0e 08       	mov    0x8(%rsi,%rcx,1),%rbp
 105c83c:	49 8b 55 08          	mov    0x8(%r13),%rdx
 105c840:	4c 89 f1             	mov    %r14,%rcx
 105c843:	49 39 d6             	cmp    %rdx,%r14
 105c846:	4c 89 ef             	mov    %r13,%rdi
 105c849:	0f 83 e8 1e 00 00    	jae    105e737 <my.vm::run+0x3207>
 105c84f:	4c 89 74 24 70       	mov    %r14,0x70(%rsp)
 105c854:	48 89 74 24 58       	mov    %rsi,0x58(%rsp)
 105c859:	41 89 c6             	mov    %eax,%r14d
 105c85c:	4c 8d 67 20          	lea    0x20(%rdi),%r12
 105c860:	48 6b c1 38          	imul   $0x38,%rcx,%rax
 105c864:	41 8b 0c 04          	mov    (%r12,%rax,1),%ecx
 105c868:	83 f9 07             	cmp    $0x7,%ecx
 105c86b:	48 89 bc 24 d8 01 00 	mov    %rdi,0x1d8(%rsp)
 105c872:	00 
 105c873:	0f 85 54 22 00 00    	jne    105eacd <my.vm::run+0x359d>
 105c879:	45 89 c5             	mov    %r8d,%r13d
 105c87c:	4c 01 e0             	add    %r12,%rax
 105c87f:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105c883:	48 89 8c 24 d0 01 00 	mov    %rcx,0x1d0(%rsp)
 105c88a:	00 
 105c88b:	48 8b 78 10          	mov    0x10(%rax),%rdi
 105c88f:	48 8b 40 18          	mov    0x18(%rax),%rax
 105c893:	48 89 84 24 c8 01 00 	mov    %rax,0x1c8(%rsp)
 105c89a:	00 
 105c89b:	be 20 00 00 00       	mov    $0x20,%esi
 105c8a0:	e8 1b 79 fc ff       	call   10241c0 <myl_core_list_copy>
 105c8a5:	45 0f b6 c5          	movzbl %r13b,%r8d
 105c8a9:	48 89 c7             	mov    %rax,%rdi
 105c8ac:	48 8b b4 24 c8 01 00 	mov    0x1c8(%rsp),%rsi
 105c8b3:	00 
 105c8b4:	48 8b 54 24 68       	mov    0x68(%rsp),%rdx
 105c8b9:	44 89 f1             	mov    %r14d,%ecx
 105c8bc:	49 89 e9             	mov    %rbp,%r9
 105c8bf:	e8 7c e1 00 00       	call   106aa40 <my.table::set>
 105c8c4:	48 8b 84 24 d8 01 00 	mov    0x1d8(%rsp),%rax
 105c8cb:	00 
 105c8cc:	48 8b 40 08          	mov    0x8(%rax),%rax
 105c8d0:	48 8b 74 24 70       	mov    0x70(%rsp),%rsi
 105c8d5:	48 39 c6             	cmp    %rax,%rsi
 105c8d8:	0f 83 8f 1e 00 00    	jae    105e76d <my.vm::run+0x323d>
 105c8de:	48 89 f7             	mov    %rsi,%rdi
 105c8e1:	4c 6b cf 38          	imul   $0x38,%rdi,%r9
 105c8e5:	43 0f b6 34 0c       	movzbl (%r12,%r9,1),%esi
 105c8ea:	4b 8b 7c 0c 08       	mov    0x8(%r12,%r9,1),%rdi
 105c8ef:	4f 8b 44 0c 10       	mov    0x10(%r12,%r9,1),%r8
 105c8f4:	4b 8b 44 0c 18       	mov    0x18(%r12,%r9,1),%rax
 105c8f9:	4f 8b 6c 0c 20       	mov    0x20(%r12,%r9,1),%r13
 105c8fe:	4f 8b 74 0c 28       	mov    0x28(%r12,%r9,1),%r14
 105c903:	4b c7 04 0c 07 00 00 	movq   $0x7,(%r12,%r9,1)
 105c90a:	00 
 105c90b:	4c 8b 94 24 d0 01 00 	mov    0x1d0(%rsp),%r10
 105c912:	00 
 105c913:	4f 89 54 0c 08       	mov    %r10,0x8(%r12,%r9,1)
 105c918:	4b 89 54 0c 10       	mov    %rdx,0x10(%r12,%r9,1)
 105c91d:	4b 89 4c 0c 18       	mov    %rcx,0x18(%r12,%r9,1)
 105c922:	83 fe 09             	cmp    $0x9,%esi
 105c925:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105c92a:	77 16                	ja     105c942 <my.vm::run+0x1412>
 105c92c:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105c931:	0f a3 f1             	bt     %esi,%ecx
 105c934:	0f 83 51 17 00 00    	jae    105e08b <my.vm::run+0x2b5b>
 105c93a:	4c 89 c7             	mov    %r8,%rdi
 105c93d:	e8 be 79 fc ff       	call   1024300 <myl_core_drop_owned>
 105c942:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105c946:	49 39 d7             	cmp    %rdx,%r15
 105c949:	0f 83 39 1e 00 00    	jae    105e788 <my.vm::run+0x3258>
 105c94f:	4c 89 f8             	mov    %r15,%rax
 105c952:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105c957:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105c95c:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105c961:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 105c966:	48 c1 e0 04          	shl    $0x4,%rax
 105c96a:	c5 f9 10 04 01       	vmovupd (%rcx,%rax,1),%xmm0
 105c96f:	4c 8b 7c 24 60       	mov    0x60(%rsp),%r15
 105c974:	4c 89 f8             	mov    %r15,%rax
 105c977:	49 39 d7             	cmp    %rdx,%r15
 105c97a:	48 8b 6c 24 28       	mov    0x28(%rsp),%rbp
 105c97f:	0f 83 32 1e 00 00    	jae    105e7b7 <my.vm::run+0x3287>
 105c985:	c5 f9 54 05 53 7a fa 	vandpd -0x585ad(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c98c:	ff 
 105c98d:	48 c1 e0 04          	shl    $0x4,%rax
 105c991:	c5 f9 11 04 01       	vmovupd %xmm0,(%rcx,%rax,1)
 105c996:	49 ff c7             	inc    %r15
 105c999:	e9 98 11 00 00       	jmp    105db36 <my.vm::run+0x2606>
 105c99e:	48 8d bc 24 58 02 00 	lea    0x258(%rsp),%rdi
 105c9a5:	00 
 105c9a6:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105c9ab:	4c 89 da             	mov    %r11,%rdx
 105c9ae:	48 89 e9             	mov    %rbp,%rcx
 105c9b1:	e8 4a 74 00 00       	call   1063e00 <my.vm::read_byte>
 105c9b6:	4c 89 fe             	mov    %r15,%rsi
 105c9b9:	48 ff ce             	dec    %rsi
 105c9bc:	0f 80 ba 24 00 00    	jo     105ee7c <my.vm::run+0x394c>
 105c9c2:	48 8b 84 24 58 02 00 	mov    0x258(%rsp),%rax
 105c9c9:	00 
 105c9ca:	4c 8b 9c 24 60 02 00 	mov    0x260(%rsp),%r11
 105c9d1:	00 
 105c9d2:	48 8b ac 24 68 02 00 	mov    0x268(%rsp),%rbp
 105c9d9:	00 
 105c9da:	4c 8b 84 24 70 02 00 	mov    0x270(%rsp),%r8
 105c9e1:	00 
 105c9e2:	4c 8b 8c 24 78 02 00 	mov    0x278(%rsp),%r9
 105c9e9:	00 
 105c9ea:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105c9ef:	48 8b 49 78          	mov    0x78(%rcx),%rcx
 105c9f3:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105c9f7:	48 39 d6             	cmp    %rdx,%rsi
 105c9fa:	0f 83 2f 18 00 00    	jae    105e22f <my.vm::run+0x2cff>
 105ca00:	48 89 f7             	mov    %rsi,%rdi
 105ca03:	4c 89 ce             	mov    %r9,%rsi
 105ca06:	48 01 c6             	add    %rax,%rsi
 105ca09:	0f 80 47 24 00 00    	jo     105ee56 <my.vm::run+0x3926>
 105ca0f:	48 c1 e7 04          	shl    $0x4,%rdi
 105ca13:	c5 f9 10 44 39 20    	vmovupd 0x20(%rcx,%rdi,1),%xmm0
 105ca19:	48 39 d6             	cmp    %rdx,%rsi
 105ca1c:	0f 83 f3 18 00 00    	jae    105e315 <my.vm::run+0x2de5>
 105ca22:	48 89 f0             	mov    %rsi,%rax
 105ca25:	48 8d 51 20          	lea    0x20(%rcx),%rdx
 105ca29:	48 c1 e0 04          	shl    $0x4,%rax
 105ca2d:	c5 f9 54 05 ab 79 fa 	vandpd -0x58655(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105ca34:	ff 
 105ca35:	c5 f9 11 04 02       	vmovupd %xmm0,(%rdx,%rax,1)
 105ca3a:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105ca3f:	48 89 48 78          	mov    %rcx,0x78(%rax)
 105ca43:	4d 89 c4             	mov    %r8,%r12
 105ca46:	e9 85 14 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105ca4b:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105ca52:	00 
 105ca53:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105ca58:	4c 89 f6             	mov    %r14,%rsi
 105ca5b:	4c 89 da             	mov    %r11,%rdx
 105ca5e:	48 89 e9             	mov    %rbp,%rcx
 105ca61:	e8 9a 73 00 00       	call   1063e00 <my.vm::read_byte>
 105ca66:	48 8b 94 24 a8 00 00 	mov    0xa8(%rsp),%rdx
 105ca6d:	00 
 105ca6e:	48 8b b4 24 b0 00 00 	mov    0xb0(%rsp),%rsi
 105ca75:	00 
 105ca76:	48 8b ac 24 b8 00 00 	mov    0xb8(%rsp),%rbp
 105ca7d:	00 
 105ca7e:	4c 8b a4 24 c0 00 00 	mov    0xc0(%rsp),%r12
 105ca85:	00 
 105ca86:	48 8b 9c 24 c8 00 00 	mov    0xc8(%rsp),%rbx
 105ca8d:	00 
 105ca8e:	4c 89 f7             	mov    %r14,%rdi
 105ca91:	49 89 f7             	mov    %rsi,%r15
 105ca94:	e8 97 e3 00 00       	call   106ae30 <my.heap::closure_upvalue>
 105ca99:	48 8d bc 24 00 03 00 	lea    0x300(%rsp),%rdi
 105caa0:	00 
 105caa1:	4c 89 f6             	mov    %r14,%rsi
 105caa4:	48 89 c2             	mov    %rax,%rdx
 105caa7:	e8 84 e2 00 00       	call   106ad30 <my.heap::upvalue_obj>
 105caac:	48 8b b4 24 00 03 00 	mov    0x300(%rsp),%rsi
 105cab3:	00 
 105cab4:	48 83 fe ff          	cmp    $0xffffffffffffffff,%rsi
 105cab8:	0f 84 21 10 00 00    	je     105dadf <my.vm::run+0x25af>
 105cabe:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105cac3:	48 8b 40 78          	mov    0x78(%rax),%rax
 105cac7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cacb:	48 39 d6             	cmp    %rdx,%rsi
 105cace:	0f 83 51 1a 00 00    	jae    105e525 <my.vm::run+0x2ff5>
 105cad4:	48 89 f1             	mov    %rsi,%rcx
 105cad7:	49 89 d9             	mov    %rbx,%r9
 105cada:	4d 89 fb             	mov    %r15,%r11
 105cadd:	48 c1 e1 04          	shl    $0x4,%rcx
 105cae1:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105cae7:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105caec:	48 8b b1 80 00 00 00 	mov    0x80(%rcx),%rsi
 105caf3:	48 89 f1             	mov    %rsi,%rcx
 105caf6:	48 39 d6             	cmp    %rdx,%rsi
 105caf9:	0f 83 47 1a 00 00    	jae    105e546 <my.vm::run+0x3016>
 105caff:	48 83 c0 20          	add    $0x20,%rax
 105cb03:	48 c1 e1 04          	shl    $0x4,%rcx
 105cb07:	c5 f9 54 05 d1 78 fa 	vandpd -0x5872f(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105cb0e:	ff 
 105cb0f:	c5 f9 11 04 08       	vmovupd %xmm0,(%rax,%rcx,1)
 105cb14:	49 89 f7             	mov    %rsi,%r15
 105cb17:	49 ff c7             	inc    %r15
 105cb1a:	0f 81 16 10 00 00    	jno    105db36 <my.vm::run+0x2606>
 105cb20:	e9 dd 24 00 00       	jmp    105f002 <my.vm::run+0x3ad2>
 105cb25:	4c 89 fe             	mov    %r15,%rsi
 105cb28:	48 ff ce             	dec    %rsi
 105cb2b:	0f 80 ec 21 00 00    	jo     105ed1d <my.vm::run+0x37ed>
 105cb31:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105cb36:	48 8b 40 78          	mov    0x78(%rax),%rax
 105cb3a:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cb3e:	48 89 e9             	mov    %rbp,%rcx
 105cb41:	48 39 d6             	cmp    %rdx,%rsi
 105cb44:	0f 83 00 17 00 00    	jae    105e24a <my.vm::run+0x2d1a>
 105cb4a:	48 89 f7             	mov    %rsi,%rdi
 105cb4d:	48 c1 e7 04          	shl    $0x4,%rdi
 105cb51:	48 8b 6c 38 20       	mov    0x20(%rax,%rdi,1),%rbp
 105cb56:	4c 8b 7c 38 28       	mov    0x28(%rax,%rdi,1),%r15
 105cb5b:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105cb62:	00 
 105cb63:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105cb68:	4c 89 da             	mov    %r11,%rdx
 105cb6b:	e8 50 73 00 00       	call   1063ec0 <my.vm::read_constant>
 105cb70:	0f b6 84 24 a8 00 00 	movzbl 0xa8(%rsp),%eax
 105cb77:	00 
 105cb78:	83 f8 03             	cmp    $0x3,%eax
 105cb7b:	0f 85 53 1e 00 00    	jne    105e9d4 <my.vm::run+0x34a4>
 105cb81:	48 8b 84 24 d0 00 00 	mov    0xd0(%rsp),%rax
 105cb88:	00 
 105cb89:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105cb8e:	4c 8b a4 24 c8 00 00 	mov    0xc8(%rsp),%r12
 105cb95:	00 
 105cb96:	48 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%rax
 105cb9d:	00 
 105cb9e:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
 105cba3:	4c 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%r13
 105cbaa:	00 
 105cbab:	48 8b 9c 24 b8 00 00 	mov    0xb8(%rsp),%rbx
 105cbb2:	00 
 105cbb3:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105cbb8:	4c 89 f7             	mov    %r14,%rdi
 105cbbb:	4c 89 ee             	mov    %r13,%rsi
 105cbbe:	e8 9d dd 00 00       	call   106a960 <my.heap::string_hash>
 105cbc3:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105cbc7:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105cbcb:	4c 89 ea             	mov    %r13,%rdx
 105cbce:	89 c1                	mov    %eax,%ecx
 105cbd0:	41 89 e8             	mov    %ebp,%r8d
 105cbd3:	4d 89 f9             	mov    %r15,%r9
 105cbd6:	e8 65 de 00 00       	call   106aa40 <my.table::set>
 105cbdb:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105cbdf:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105cbe3:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105cbea:	49 89 f7             	mov    %rsi,%r15
 105cbed:	49 ff cf             	dec    %r15
 105cbf0:	0f 80 dc 20 00 00    	jo     105ecd2 <my.vm::run+0x37a2>
 105cbf6:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105cbfb:	4c 89 b9 80 00 00 00 	mov    %r15,0x80(%rcx)
 105cc02:	48 8b 41 78          	mov    0x78(%rcx),%rax
 105cc06:	4c 8b b1 90 00 00 00 	mov    0x90(%rcx),%r14
 105cc0d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cc11:	49 39 d7             	cmp    %rdx,%r15
 105cc14:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105cc19:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105cc1e:	49 89 db             	mov    %rbx,%r11
 105cc21:	0f 82 ab 0e 00 00    	jb     105dad2 <my.vm::run+0x25a2>
 105cc27:	4c 89 f8             	mov    %r15,%rax
 105cc2a:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cc2e:	48 21 d0             	and    %rdx,%rax
 105cc31:	4c 01 f8             	add    %r15,%rax
 105cc34:	48 39 d0             	cmp    %rdx,%rax
 105cc37:	48 8b 6c 24 28       	mov    0x28(%rsp),%rbp
 105cc3c:	0f 83 3f 26 00 00    	jae    105f281 <my.vm::run+0x3d51>
 105cc42:	4d 89 e0             	mov    %r12,%r8
 105cc45:	e9 86 12 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105cc4a:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105cc51:	00 
 105cc52:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105cc57:	4c 89 da             	mov    %r11,%rdx
 105cc5a:	48 89 e9             	mov    %rbp,%rcx
 105cc5d:	e8 5e 72 00 00       	call   1063ec0 <my.vm::read_constant>
 105cc62:	0f b6 84 24 a8 00 00 	movzbl 0xa8(%rsp),%eax
 105cc69:	00 
 105cc6a:	83 f8 03             	cmp    $0x3,%eax
 105cc6d:	0f 85 2c 1e 00 00    	jne    105ea9f <my.vm::run+0x356f>
 105cc73:	48 8b ac 24 d0 00 00 	mov    0xd0(%rsp),%rbp
 105cc7a:	00 
 105cc7b:	4c 8b a4 24 c8 00 00 	mov    0xc8(%rsp),%r12
 105cc82:	00 
 105cc83:	48 8b 84 24 c0 00 00 	mov    0xc0(%rsp),%rax
 105cc8a:	00 
 105cc8b:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
 105cc90:	4c 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%r8
 105cc97:	00 
 105cc98:	48 8b bc 24 b8 00 00 	mov    0xb8(%rsp),%rdi
 105cc9f:	00 
 105cca0:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105cca5:	48 8b 00             	mov    (%rax),%rax
 105cca8:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ccac:	4c 89 c1             	mov    %r8,%rcx
 105ccaf:	49 39 d0             	cmp    %rdx,%r8
 105ccb2:	0f 83 0c 17 00 00    	jae    105e3c4 <my.vm::run+0x2e94>
 105ccb8:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
 105ccbd:	48 6b d1 38          	imul   $0x38,%rcx,%rdx
 105ccc1:	8b 4c 10 20          	mov    0x20(%rax,%rdx,1),%ecx
 105ccc5:	83 f9 02             	cmp    $0x2,%ecx
 105ccc8:	0f 85 33 1c 00 00    	jne    105e901 <my.vm::run+0x33d1>
 105ccce:	48 01 d0             	add    %rdx,%rax
 105ccd1:	48 83 c0 20          	add    $0x20,%rax
 105ccd5:	48 8b 70 10          	mov    0x10(%rax),%rsi
 105ccd9:	4c 89 c7             	mov    %r8,%rdi
 105ccdc:	48 89 74 24 60       	mov    %rsi,0x60(%rsp)
 105cce1:	e8 ca e4 ff ff       	call   105b1b0 <my.object::new_closure>
 105cce6:	49 89 c6             	mov    %rax,%r14
 105cce9:	48 89 d3             	mov    %rdx,%rbx
 105ccec:	be 08 00 00 00       	mov    $0x8,%esi
 105ccf1:	48 89 d7             	mov    %rdx,%rdi
 105ccf4:	e8 c7 74 fc ff       	call   10241c0 <myl_core_list_copy>
 105ccf9:	49 89 c7             	mov    %rax,%r15
 105ccfc:	48 c7 84 24 38 06 00 	movq   $0x4,0x638(%rsp)
 105cd03:	00 04 00 00 00 
 105cd08:	4c 89 74 24 68       	mov    %r14,0x68(%rsp)
 105cd0d:	4c 89 b4 24 40 06 00 	mov    %r14,0x640(%rsp)
 105cd14:	00 
 105cd15:	48 89 84 24 48 06 00 	mov    %rax,0x648(%rsp)
 105cd1c:	00 
 105cd1d:	48 8d bc 24 60 03 00 	lea    0x360(%rsp),%rdi
 105cd24:	00 
 105cd25:	48 8d 94 24 38 06 00 	lea    0x638(%rsp),%rdx
 105cd2c:	00 
 105cd2d:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105cd32:	4c 89 f6             	mov    %r14,%rsi
 105cd35:	e8 26 e0 ff ff       	call   105ad60 <my.heap::allocate>
 105cd3a:	4c 89 ff             	mov    %r15,%rdi
 105cd3d:	e8 be 75 fc ff       	call   1024300 <myl_core_drop_owned>
 105cd42:	48 8b bc 24 60 03 00 	mov    0x360(%rsp),%rdi
 105cd49:	00 
 105cd4a:	49 8b 46 78          	mov    0x78(%r14),%rax
 105cd4e:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105cd55:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cd59:	48 89 f1             	mov    %rsi,%rcx
 105cd5c:	48 39 d6             	cmp    %rdx,%rsi
 105cd5f:	0f 83 57 17 00 00    	jae    105e4bc <my.vm::run+0x2f8c>
 105cd65:	48 c1 e1 04          	shl    $0x4,%rcx
 105cd69:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 105cd70:	00 00 
 105cd72:	48 89 7c 08 28       	mov    %rdi,0x28(%rax,%rcx,1)
 105cd77:	48 89 f0             	mov    %rsi,%rax
 105cd7a:	48 ff c0             	inc    %rax
 105cd7d:	0f 80 52 20 00 00    	jo     105edd5 <my.vm::run+0x38a5>
 105cd83:	48 89 7c 24 70       	mov    %rdi,0x70(%rsp)
 105cd88:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105cd8d:	48 89 81 80 00 00 00 	mov    %rax,0x80(%rcx)
 105cd94:	be 08 00 00 00       	mov    $0x8,%esi
 105cd99:	48 89 df             	mov    %rbx,%rdi
 105cd9c:	e8 1f 74 fc ff       	call   10241c0 <myl_core_list_copy>
 105cda1:	48 89 44 24 58       	mov    %rax,0x58(%rsp)
 105cda6:	48 89 df             	mov    %rbx,%rdi
 105cda9:	e8 52 75 fc ff       	call   1024300 <myl_core_drop_owned>
 105cdae:	48 83 7c 24 60 00    	cmpq   $0x0,0x60(%rsp)
 105cdb4:	0f 8e 97 0d 00 00    	jle    105db51 <my.vm::run+0x2621>
 105cdba:	31 f6                	xor    %esi,%esi
 105cdbc:	49 89 e9             	mov    %rbp,%r9
 105cdbf:	48 8b 44 24 30       	mov    0x30(%rsp),%rax
 105cdc4:	48 8b 6c 24 28       	mov    0x28(%rsp),%rbp
 105cdc9:	eb 48                	jmp    105ce13 <my.vm::run+0x18e3>
 105cdcb:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105cdd0:	48 89 98 98 00 00 00 	mov    %rbx,0x98(%rax)
 105cdd7:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 105cddc:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105cde0:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105cde5:	48 39 d6             	cmp    %rdx,%rsi
 105cde8:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105cded:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105cdf2:	48 8b 44 24 30       	mov    0x30(%rsp),%rax
 105cdf7:	0f 83 37 1b 00 00    	jae    105e934 <my.vm::run+0x3404>
 105cdfd:	48 89 5c f1 20       	mov    %rbx,0x20(%rcx,%rsi,8)
 105ce02:	48 ff c6             	inc    %rsi
 105ce05:	48 3b 74 24 60       	cmp    0x60(%rsp),%rsi
 105ce0a:	4c 89 fd             	mov    %r15,%rbp
 105ce0d:	0f 84 4b 0d 00 00    	je     105db5e <my.vm::run+0x262e>
 105ce13:	48 89 74 24 28       	mov    %rsi,0x28(%rsp)
 105ce18:	48 8d bc 24 98 01 00 	lea    0x198(%rsp),%rdi
 105ce1f:	00 
 105ce20:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105ce25:	4c 89 f6             	mov    %r14,%rsi
 105ce28:	48 89 c2             	mov    %rax,%rdx
 105ce2b:	48 89 e9             	mov    %rbp,%rcx
 105ce2e:	4d 89 e0             	mov    %r12,%r8
 105ce31:	e8 ca 6f 00 00       	call   1063e00 <my.vm::read_byte>
 105ce36:	48 8b 9c 24 98 01 00 	mov    0x198(%rsp),%rbx
 105ce3d:	00 
 105ce3e:	48 8b 94 24 a0 01 00 	mov    0x1a0(%rsp),%rdx
 105ce45:	00 
 105ce46:	48 8b 8c 24 a8 01 00 	mov    0x1a8(%rsp),%rcx
 105ce4d:	00 
 105ce4e:	4c 8b 84 24 b0 01 00 	mov    0x1b0(%rsp),%r8
 105ce55:	00 
 105ce56:	4c 8b 8c 24 b8 01 00 	mov    0x1b8(%rsp),%r9
 105ce5d:	00 
 105ce5e:	48 8d bc 24 a8 02 00 	lea    0x2a8(%rsp),%rdi
 105ce65:	00 
 105ce66:	4c 89 f6             	mov    %r14,%rsi
 105ce69:	e8 92 6f 00 00       	call   1063e00 <my.vm::read_byte>
 105ce6e:	48 8b 94 24 a8 02 00 	mov    0x2a8(%rsp),%rdx
 105ce75:	00 
 105ce76:	48 8b 84 24 b0 02 00 	mov    0x2b0(%rsp),%rax
 105ce7d:	00 
 105ce7e:	4c 8b bc 24 b8 02 00 	mov    0x2b8(%rsp),%r15
 105ce85:	00 
 105ce86:	4c 8b a4 24 c0 02 00 	mov    0x2c0(%rsp),%r12
 105ce8d:	00 
 105ce8e:	48 8b b4 24 c8 02 00 	mov    0x2c8(%rsp),%rsi
 105ce95:	00 
 105ce96:	48 83 fb 01          	cmp    $0x1,%rbx
 105ce9a:	0f 85 d0 00 00 00    	jne    105cf70 <my.vm::run+0x1a40>
 105cea0:	48 89 f5             	mov    %rsi,%rbp
 105cea3:	48 01 d5             	add    %rdx,%rbp
 105cea6:	0f 80 7c 1a 00 00    	jo     105e928 <my.vm::run+0x33f8>
 105ceac:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 105ceb1:	48 89 74 24 20       	mov    %rsi,0x20(%rsp)
 105ceb6:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105cebb:	48 8b 98 98 00 00 00 	mov    0x98(%rax),%rbx
 105cec2:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105cec6:	0f 84 ec 00 00 00    	je     105cfb8 <my.vm::run+0x1a88>
 105cecc:	48 8d bc 24 28 05 00 	lea    0x528(%rsp),%rdi
 105ced3:	00 
 105ced4:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105ced9:	48 89 da             	mov    %rbx,%rdx
 105cedc:	e8 4f de 00 00       	call   106ad30 <my.heap::upvalue_obj>
 105cee1:	49 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%r13
 105cee8:	48 39 ac 24 28 05 00 	cmp    %rbp,0x528(%rsp)
 105ceef:	00 
 105cef0:	7e 57                	jle    105cf49 <my.vm::run+0x1a19>
 105cef2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105cef9:	1f 84 00 00 00 00 00 
 105cf00:	49 89 dd             	mov    %rbx,%r13
 105cf03:	48 8d bc 24 08 05 00 	lea    0x508(%rsp),%rdi
 105cf0a:	00 
 105cf0b:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105cf10:	48 89 da             	mov    %rbx,%rdx
 105cf13:	e8 18 de 00 00       	call   106ad30 <my.heap::upvalue_obj>
 105cf18:	48 8b 9c 24 20 05 00 	mov    0x520(%rsp),%rbx
 105cf1f:	00 
 105cf20:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105cf24:	0f 84 9e 00 00 00    	je     105cfc8 <my.vm::run+0x1a98>
 105cf2a:	48 8d bc 24 e8 04 00 	lea    0x4e8(%rsp),%rdi
 105cf31:	00 
 105cf32:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105cf37:	48 89 da             	mov    %rbx,%rdx
 105cf3a:	e8 f1 dd 00 00       	call   106ad30 <my.heap::upvalue_obj>
 105cf3f:	48 39 ac 24 e8 04 00 	cmp    %rbp,0x4e8(%rsp)
 105cf46:	00 
 105cf47:	7f b7                	jg     105cf00 <my.vm::run+0x19d0>
 105cf49:	48 8d bc 24 c8 04 00 	lea    0x4c8(%rsp),%rdi
 105cf50:	00 
 105cf51:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105cf56:	48 89 da             	mov    %rbx,%rdx
 105cf59:	e8 d2 dd 00 00       	call   106ad30 <my.heap::upvalue_obj>
 105cf5e:	48 39 ac 24 c8 04 00 	cmp    %rbp,0x4c8(%rsp)
 105cf65:	00 
 105cf66:	0f 84 6b fe ff ff    	je     105cdd7 <my.vm::run+0x18a7>
 105cf6c:	eb 61                	jmp    105cfcf <my.vm::run+0x1a9f>
 105cf6e:	66 90                	xchg   %ax,%ax
 105cf70:	4c 89 64 24 18       	mov    %r12,0x18(%rsp)
 105cf75:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 105cf7a:	4d 89 ec             	mov    %r13,%r12
 105cf7d:	49 89 f5             	mov    %rsi,%r13
 105cf80:	48 89 c5             	mov    %rax,%rbp
 105cf83:	48 89 c6             	mov    %rax,%rsi
 105cf86:	e8 a5 de 00 00       	call   106ae30 <my.heap::closure_upvalue>
 105cf8b:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 105cf90:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105cf94:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105cf99:	48 39 d6             	cmp    %rdx,%rsi
 105cf9c:	0f 83 9e 19 00 00    	jae    105e940 <my.vm::run+0x3410>
 105cfa2:	48 89 c3             	mov    %rax,%rbx
 105cfa5:	4d 89 e9             	mov    %r13,%r9
 105cfa8:	48 89 e8             	mov    %rbp,%rax
 105cfab:	4d 89 e5             	mov    %r12,%r13
 105cfae:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105cfb3:	e9 45 fe ff ff       	jmp    105cdfd <my.vm::run+0x18cd>
 105cfb8:	48 c7 c3 ff ff ff ff 	mov    $0xffffffffffffffff,%rbx
 105cfbf:	49 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%r13
 105cfc6:	eb 07                	jmp    105cfcf <my.vm::run+0x1a9f>
 105cfc8:	48 c7 c3 ff ff ff ff 	mov    $0xffffffffffffffff,%rbx
 105cfcf:	48 c7 84 24 48 05 00 	movq   $0x5,0x548(%rsp)
 105cfd6:	00 05 00 00 00 
 105cfdb:	48 89 ac 24 50 05 00 	mov    %rbp,0x550(%rsp)
 105cfe2:	00 
 105cfe3:	48 c7 84 24 58 05 00 	movq   $0x0,0x558(%rsp)
 105cfea:	00 00 00 00 00 
 105cfef:	48 89 9c 24 68 05 00 	mov    %rbx,0x568(%rsp)
 105cff6:	00 
 105cff7:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105cffe:	00 
 105cfff:	48 8d 94 24 48 05 00 	lea    0x548(%rsp),%rdx
 105d006:	00 
 105d007:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105d00c:	e8 4f dd ff ff       	call   105ad60 <my.heap::allocate>
 105d011:	48 8b 9c 24 a8 00 00 	mov    0xa8(%rsp),%rbx
 105d018:	00 
 105d019:	49 83 fd ff          	cmp    $0xffffffffffffffff,%r13
 105d01d:	0f 84 a8 fd ff ff    	je     105cdcb <my.vm::run+0x189b>
 105d023:	48 8d bc 24 20 03 00 	lea    0x320(%rsp),%rdi
 105d02a:	00 
 105d02b:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105d030:	4c 89 f6             	mov    %r14,%rsi
 105d033:	4c 89 ea             	mov    %r13,%rdx
 105d036:	e8 f5 dc 00 00       	call   106ad30 <my.heap::upvalue_obj>
 105d03b:	48 8b b4 24 30 03 00 	mov    0x330(%rsp),%rsi
 105d042:	00 
 105d043:	44 0f b6 8c 24 28 03 	movzbl 0x328(%rsp),%r9d
 105d04a:	00 00 
 105d04c:	4c 8b 94 24 20 03 00 	mov    0x320(%rsp),%r10
 105d053:	00 
 105d054:	4d 8b 06             	mov    (%r14),%r8
 105d057:	49 8b 50 08          	mov    0x8(%r8),%rdx
 105d05b:	49 39 d5             	cmp    %rdx,%r13
 105d05e:	0f 83 86 00 00 00    	jae    105d0ea <my.vm::run+0x1bba>
 105d064:	4c 89 e8             	mov    %r13,%rax
 105d067:	4c 6b d8 38          	imul   $0x38,%rax,%r11
 105d06b:	43 0f b6 54 18 20    	movzbl 0x20(%r8,%r11,1),%edx
 105d071:	4b 8b 44 18 28       	mov    0x28(%r8,%r11,1),%rax
 105d076:	4b 8b 7c 18 30       	mov    0x30(%r8,%r11,1),%rdi
 105d07b:	4b 8b 4c 18 38       	mov    0x38(%r8,%r11,1),%rcx
 105d080:	4b 8b 6c 18 40       	mov    0x40(%r8,%r11,1),%rbp
 105d085:	4f 8b 6c 18 48       	mov    0x48(%r8,%r11,1),%r13
 105d08a:	4b c7 44 18 20 05 00 	movq   $0x5,0x20(%r8,%r11,1)
 105d091:	00 00 
 105d093:	4f 89 54 18 28       	mov    %r10,0x28(%r8,%r11,1)
 105d098:	45 0f b6 c9          	movzbl %r9b,%r9d
 105d09c:	4f 89 4c 18 30       	mov    %r9,0x30(%r8,%r11,1)
 105d0a1:	4b 89 74 18 38       	mov    %rsi,0x38(%r8,%r11,1)
 105d0a6:	4b 89 5c 18 40       	mov    %rbx,0x40(%r8,%r11,1)
 105d0ab:	ff ca                	dec    %edx
 105d0ad:	83 fa 08             	cmp    $0x8,%edx
 105d0b0:	0f 87 21 fd ff ff    	ja     105cdd7 <my.vm::run+0x18a7>
 105d0b6:	48 8d 35 ab a3 fa ff 	lea    -0x55c55(%rip),%rsi        # 1007468 <core_number_pairs+0x208>
 105d0bd:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105d0c1:	48 01 f2             	add    %rsi,%rdx
 105d0c4:	ff e2                	jmp    *%rdx
 105d0c6:	e8 35 72 fc ff       	call   1024300 <myl_core_drop_owned>
 105d0cb:	e9 07 fd ff ff       	jmp    105cdd7 <my.vm::run+0x18a7>
 105d0d0:	48 89 cf             	mov    %rcx,%rdi
 105d0d3:	e8 28 72 fc ff       	call   1024300 <myl_core_drop_owned>
 105d0d8:	48 89 ef             	mov    %rbp,%rdi
 105d0db:	e8 20 72 fc ff       	call   1024300 <myl_core_drop_owned>
 105d0e0:	4c 89 ef             	mov    %r13,%rdi
 105d0e3:	eb e1                	jmp    105d0c6 <my.vm::run+0x1b96>
 105d0e5:	48 89 c7             	mov    %rax,%rdi
 105d0e8:	eb dc                	jmp    105d0c6 <my.vm::run+0x1b96>
 105d0ea:	4c 89 e8             	mov    %r13,%rax
 105d0ed:	48 c1 f8 3f          	sar    $0x3f,%rax
 105d0f1:	48 21 d0             	and    %rdx,%rax
 105d0f4:	4c 01 e8             	add    %r13,%rax
 105d0f7:	48 39 d0             	cmp    %rdx,%rax
 105d0fa:	0f 82 67 ff ff ff    	jb     105d067 <my.vm::run+0x1b37>
 105d100:	e9 2b 21 00 00       	jmp    105f230 <my.vm::run+0x3d00>
 105d105:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d10a:	48 8b 80 80 00 00 00 	mov    0x80(%rax),%rax
 105d111:	48 89 c6             	mov    %rax,%rsi
 105d114:	48 ff ce             	dec    %rsi
 105d117:	0f 80 00 1d 00 00    	jo     105ee1d <my.vm::run+0x38ed>
 105d11d:	4c 89 cb             	mov    %r9,%rbx
 105d120:	4c 89 5c 24 30       	mov    %r11,0x30(%rsp)
 105d125:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d12a:	48 8b 40 78          	mov    0x78(%rax),%rax
 105d12e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d132:	49 89 f1             	mov    %rsi,%r9
 105d135:	49 c1 f9 3f          	sar    $0x3f,%r9
 105d139:	49 21 d1             	and    %rdx,%r9
 105d13c:	48 89 f1             	mov    %rsi,%rcx
 105d13f:	48 39 d6             	cmp    %rdx,%rsi
 105d142:	0f 83 38 11 00 00    	jae    105e280 <my.vm::run+0x2d50>
 105d148:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105d14c:	48 c1 e1 04          	shl    $0x4,%rcx
 105d150:	44 0f b6 54 08 20    	movzbl 0x20(%rax,%rcx,1),%r10d
 105d156:	48 8b 44 08 28       	mov    0x28(%rax,%rcx,1),%rax
 105d15b:	41 83 fa 02          	cmp    $0x2,%r10d
 105d15f:	0f 84 2c 0b 00 00    	je     105dc91 <my.vm::run+0x2761>
 105d165:	41 83 fa 03          	cmp    $0x3,%r10d
 105d169:	0f 85 7b 0b 00 00    	jne    105dcea <my.vm::run+0x27ba>
 105d16f:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105d174:	4c 8b 11             	mov    (%rcx),%r10
 105d177:	49 8b 4a 08          	mov    0x8(%r10),%rcx
 105d17b:	48 39 c8             	cmp    %rcx,%rax
 105d17e:	0f 83 d0 14 00 00    	jae    105e654 <my.vm::run+0x3124>
 105d184:	49 89 c3             	mov    %rax,%r11
 105d187:	49 6b c3 38          	imul   $0x38,%r11,%rax
 105d18b:	41 83 7c 02 20 01    	cmpl   $0x1,0x20(%r10,%rax,1)
 105d191:	0f 85 53 0b 00 00    	jne    105dcea <my.vm::run+0x27ba>
 105d197:	48 89 f0             	mov    %rsi,%rax
 105d19a:	48 ff c8             	dec    %rax
 105d19d:	0f 80 27 1f 00 00    	jo     105f0ca <my.vm::run+0x3b9a>
 105d1a3:	49 89 c3             	mov    %rax,%r11
 105d1a6:	48 39 d0             	cmp    %rdx,%rax
 105d1a9:	0f 83 52 15 00 00    	jae    105e701 <my.vm::run+0x31d1>
 105d1af:	49 c1 e3 04          	shl    $0x4,%r11
 105d1b3:	42 80 3c 1f 03       	cmpb   $0x3,(%rdi,%r11,1)
 105d1b8:	0f 85 2c 0b 00 00    	jne    105dcea <my.vm::run+0x27ba>
 105d1be:	4d 89 c7             	mov    %r8,%r15
 105d1c1:	4e 8b 44 1f 08       	mov    0x8(%rdi,%r11,1),%r8
 105d1c6:	49 39 c8             	cmp    %rcx,%r8
 105d1c9:	0f 83 03 16 00 00    	jae    105e7d2 <my.vm::run+0x32a2>
 105d1cf:	4d 89 c3             	mov    %r8,%r11
 105d1d2:	49 83 c2 20          	add    $0x20,%r10
 105d1d6:	49 6b cb 38          	imul   $0x38,%r11,%rcx
 105d1da:	41 83 3c 0a 01       	cmpl   $0x1,(%r10,%rcx,1)
 105d1df:	4d 89 f8             	mov    %r15,%r8
 105d1e2:	0f 85 02 0b 00 00    	jne    105dcea <my.vm::run+0x27ba>
 105d1e8:	48 39 d6             	cmp    %rdx,%rsi
 105d1eb:	0f 83 fc 15 00 00    	jae    105e7ed <my.vm::run+0x32bd>
 105d1f1:	49 89 f1             	mov    %rsi,%r9
 105d1f4:	49 c1 e1 04          	shl    $0x4,%r9
 105d1f8:	42 0f b6 0c 0f       	movzbl (%rdi,%r9,1),%ecx
 105d1fd:	83 f9 03             	cmp    $0x3,%ecx
 105d200:	0f 85 5b 1f 00 00    	jne    105f161 <my.vm::run+0x3c31>
 105d206:	4a 8b 4c 0f 08       	mov    0x8(%rdi,%r9,1),%rcx
 105d20b:	48 39 d0             	cmp    %rdx,%rax
 105d20e:	0f 83 ea 15 00 00    	jae    105e7fe <my.vm::run+0x32ce>
 105d214:	48 89 c6             	mov    %rax,%rsi
 105d217:	48 c1 e6 04          	shl    $0x4,%rsi
 105d21b:	0f b6 04 37          	movzbl (%rdi,%rsi,1),%eax
 105d21f:	83 f8 03             	cmp    $0x3,%eax
 105d222:	0f 85 4e 1f 00 00    	jne    105f176 <my.vm::run+0x3c46>
 105d228:	48 01 f7             	add    %rsi,%rdi
 105d22b:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105d22f:	48 8d bc 24 60 03 00 	lea    0x360(%rsp),%rdi
 105d236:	00 
 105d237:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105d23c:	4c 89 f6             	mov    %r14,%rsi
 105d23f:	e8 7c 1b 01 00       	call   106edc0 <my.lox_strings::concat>
 105d244:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105d24b:	48 89 c6             	mov    %rax,%rsi
 105d24e:	48 ff ce             	dec    %rsi
 105d251:	0f 80 69 1f 00 00    	jo     105f1c0 <my.vm::run+0x3c90>
 105d257:	48 8b 84 24 60 03 00 	mov    0x360(%rsp),%rax
 105d25e:	00 
 105d25f:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105d264:	48 8b 49 78          	mov    0x78(%rcx),%rcx
 105d268:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105d26c:	48 39 d6             	cmp    %rdx,%rsi
 105d26f:	49 89 d9             	mov    %rbx,%r9
 105d272:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105d277:	4d 89 f8             	mov    %r15,%r8
 105d27a:	0f 83 99 15 00 00    	jae    105e819 <my.vm::run+0x32e9>
 105d280:	49 89 f7             	mov    %rsi,%r15
 105d283:	49 ff cf             	dec    %r15
 105d286:	0f 80 23 1f 00 00    	jo     105f1af <my.vm::run+0x3c7f>
 105d28c:	4c 89 fe             	mov    %r15,%rsi
 105d28f:	49 39 d7             	cmp    %rdx,%r15
 105d292:	0f 83 9c 15 00 00    	jae    105e834 <my.vm::run+0x3304>
 105d298:	48 c1 e6 04          	shl    $0x4,%rsi
 105d29c:	48 c7 44 31 20 03 00 	movq   $0x3,0x20(%rcx,%rsi,1)
 105d2a3:	00 00 
 105d2a5:	48 89 44 31 28       	mov    %rax,0x28(%rcx,%rsi,1)
 105d2aa:	e9 79 0b 00 00       	jmp    105de28 <my.vm::run+0x28f8>
 105d2af:	4d 89 f4             	mov    %r14,%r12
 105d2b2:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105d2b9:	00 
 105d2ba:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105d2bf:	4c 89 da             	mov    %r11,%rdx
 105d2c2:	48 89 e9             	mov    %rbp,%rcx
 105d2c5:	e8 f6 6b 00 00       	call   1063ec0 <my.vm::read_constant>
 105d2ca:	0f b6 84 24 a8 00 00 	movzbl 0xa8(%rsp),%eax
 105d2d1:	00 
 105d2d2:	83 f8 03             	cmp    $0x3,%eax
 105d2d5:	0f 85 50 17 00 00    	jne    105ea2b <my.vm::run+0x34fb>
 105d2db:	4c 8b 8c 24 d0 00 00 	mov    0xd0(%rsp),%r9
 105d2e2:	00 
 105d2e3:	4c 8b 84 24 c8 00 00 	mov    0xc8(%rsp),%r8
 105d2ea:	00 
 105d2eb:	48 8b 8c 24 c0 00 00 	mov    0xc0(%rsp),%rcx
 105d2f2:	00 
 105d2f3:	48 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%rbp
 105d2fa:	00 
 105d2fb:	48 8b 94 24 b8 00 00 	mov    0xb8(%rsp),%rdx
 105d302:	00 
 105d303:	48 8d bc 24 50 04 00 	lea    0x450(%rsp),%rdi
 105d30a:	00 
 105d30b:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105d310:	4c 89 f6             	mov    %r14,%rsi
 105d313:	e8 e8 6a 00 00       	call   1063e00 <my.vm::read_byte>
 105d318:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d31f:	4d 85 e4             	test   %r12,%r12
 105d322:	7f 04                	jg     105d328 <my.vm::run+0x1df8>
 105d324:	48 03 58 08          	add    0x8(%rax),%rbx
 105d328:	4c 8b 8c 24 50 04 00 	mov    0x450(%rsp),%r9
 105d32f:	00 
 105d330:	48 8b 8c 24 68 04 00 	mov    0x468(%rsp),%rcx
 105d337:	00 
 105d338:	48 c1 e3 05          	shl    $0x5,%rbx
 105d33c:	48 89 4c 18 30       	mov    %rcx,0x30(%rax,%rbx,1)
 105d341:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105d346:	48 89 81 88 00 00 00 	mov    %rax,0x88(%rcx)
 105d34d:	4c 89 fe             	mov    %r15,%rsi
 105d350:	48 ff ce             	dec    %rsi
 105d353:	0f 80 42 1a 00 00    	jo     105ed9b <my.vm::run+0x386b>
 105d359:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d35e:	48 89 b0 80 00 00 00 	mov    %rsi,0x80(%rax)
 105d365:	48 8b 40 78          	mov    0x78(%rax),%rax
 105d369:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d36d:	48 39 d6             	cmp    %rdx,%rsi
 105d370:	0f 83 9f 10 00 00    	jae    105e415 <my.vm::run+0x2ee5>
 105d376:	48 89 f1             	mov    %rsi,%rcx
 105d379:	48 c1 e1 04          	shl    $0x4,%rcx
 105d37d:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 105d382:	83 fa 03             	cmp    $0x3,%edx
 105d385:	0f 85 f7 16 00 00    	jne    105ea82 <my.vm::run+0x3552>
 105d38b:	48 01 c8             	add    %rcx,%rax
 105d38e:	48 83 c0 20          	add    $0x20,%rax
 105d392:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105d396:	48 8d bc 24 28 07 00 	lea    0x728(%rsp),%rdi
 105d39d:	00 
 105d39e:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105d3a3:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105d3a8:	49 89 e8             	mov    %rbp,%r8
 105d3ab:	e8 60 79 00 00       	call   1064d10 <my.vm::invoke_from_class>
 105d3b0:	f6 84 24 28 07 00 00 	testb  $0x1,0x728(%rsp)
 105d3b7:	01 
 105d3b8:	0f 84 9b 14 00 00    	je     105e859 <my.vm::run+0x3329>
 105d3be:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d3c3:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105d3ca:	4c 89 f6             	mov    %r14,%rsi
 105d3cd:	48 ff ce             	dec    %rsi
 105d3d0:	0f 80 aa 1b 00 00    	jo     105ef80 <my.vm::run+0x3a50>
 105d3d6:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d3db:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105d3e2:	48 8b 80 88 00 00 00 	mov    0x88(%rax),%rax
 105d3e9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d3ed:	48 39 d6             	cmp    %rdx,%rsi
 105d3f0:	0f 82 07 05 00 00    	jb     105d8fd <my.vm::run+0x23cd>
 105d3f6:	48 89 f1             	mov    %rsi,%rcx
 105d3f9:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d3fd:	48 21 d1             	and    %rdx,%rcx
 105d400:	48 01 f1             	add    %rsi,%rcx
 105d403:	48 39 d1             	cmp    %rdx,%rcx
 105d406:	0f 82 f4 04 00 00    	jb     105d900 <my.vm::run+0x23d0>
 105d40c:	e9 fe 1f 00 00       	jmp    105f40f <my.vm::run+0x3edf>
 105d411:	4c 89 64 24 18       	mov    %r12,0x18(%rsp)
 105d416:	4c 89 fe             	mov    %r15,%rsi
 105d419:	48 ff ce             	dec    %rsi
 105d41c:	0f 80 46 1a 00 00    	jo     105ee68 <my.vm::run+0x3938>
 105d422:	4d 89 c4             	mov    %r8,%r12
 105d425:	4d 89 dd             	mov    %r11,%r13
 105d428:	4c 89 cb             	mov    %r9,%rbx
 105d42b:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105d430:	4c 89 f7             	mov    %r14,%rdi
 105d433:	e8 f8 79 00 00       	call   1064e30 <my.vm::close_upvalues>
 105d438:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105d43f:	49 89 f7             	mov    %rsi,%r15
 105d442:	49 ff cf             	dec    %r15
 105d445:	0f 80 fa 19 00 00    	jo     105ee45 <my.vm::run+0x3915>
 105d44b:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105d450:	4c 89 b9 80 00 00 00 	mov    %r15,0x80(%rcx)
 105d457:	48 8b 41 78          	mov    0x78(%rcx),%rax
 105d45b:	4c 8b b1 90 00 00 00 	mov    0x90(%rcx),%r14
 105d462:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d466:	49 39 d7             	cmp    %rdx,%r15
 105d469:	49 89 d9             	mov    %rbx,%r9
 105d46c:	4d 89 eb             	mov    %r13,%r11
 105d46f:	4d 89 e0             	mov    %r12,%r8
 105d472:	0f 83 b8 0e 00 00    	jae    105e330 <my.vm::run+0x2e00>
 105d478:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105d47d:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105d482:	e9 49 0a 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105d487:	4c 89 fe             	mov    %r15,%rsi
 105d48a:	48 ff ce             	dec    %rsi
 105d48d:	0f 80 5b 1a 00 00    	jo     105eeee <my.vm::run+0x39be>
 105d493:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d498:	48 89 b0 80 00 00 00 	mov    %rsi,0x80(%rax)
 105d49f:	48 8b 40 78          	mov    0x78(%rax),%rax
 105d4a3:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d4a7:	48 89 f1             	mov    %rsi,%rcx
 105d4aa:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d4ae:	48 21 d1             	and    %rdx,%rcx
 105d4b1:	48 89 f7             	mov    %rsi,%rdi
 105d4b4:	48 39 d6             	cmp    %rdx,%rsi
 105d4b7:	0f 83 d5 0d 00 00    	jae    105e292 <my.vm::run+0x2d62>
 105d4bd:	48 c1 e7 04          	shl    $0x4,%rdi
 105d4c1:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 105d4c6:	4d 89 da             	mov    %r11,%r10
 105d4c9:	85 d2                	test   %edx,%edx
 105d4cb:	0f 84 6e 08 00 00    	je     105dd3f <my.vm::run+0x280f>
 105d4d1:	83 fa 01             	cmp    $0x1,%edx
 105d4d4:	0f 85 69 08 00 00    	jne    105dd43 <my.vm::run+0x2813>
 105d4da:	48 8d 14 38          	lea    (%rax,%rdi,1),%rdx
 105d4de:	48 83 c2 20          	add    $0x20,%rdx
 105d4e2:	0f b6 52 08          	movzbl 0x8(%rdx),%edx
 105d4e6:	f6 d2                	not    %dl
 105d4e8:	80 e2 01             	and    $0x1,%dl
 105d4eb:	e9 55 08 00 00       	jmp    105dd45 <my.vm::run+0x2815>
 105d4f0:	48 8d bc 24 a0 04 00 	lea    0x4a0(%rsp),%rdi
 105d4f7:	00 
 105d4f8:	4d 89 f4             	mov    %r14,%r12
 105d4fb:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105d500:	4c 89 f6             	mov    %r14,%rsi
 105d503:	4c 89 da             	mov    %r11,%rdx
 105d506:	48 89 e9             	mov    %rbp,%rcx
 105d509:	e8 f2 68 00 00       	call   1063e00 <my.vm::read_byte>
 105d50e:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d515:	4d 85 e4             	test   %r12,%r12
 105d518:	7f 04                	jg     105d51e <my.vm::run+0x1fee>
 105d51a:	48 03 58 08          	add    0x8(%rax),%rbx
 105d51e:	4c 8b 8c 24 a0 04 00 	mov    0x4a0(%rsp),%r9
 105d525:	00 
 105d526:	48 8b 8c 24 b8 04 00 	mov    0x4b8(%rsp),%rcx
 105d52d:	00 
 105d52e:	48 c1 e3 05          	shl    $0x5,%rbx
 105d532:	48 89 4c 18 30       	mov    %rcx,0x30(%rax,%rbx,1)
 105d537:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105d53c:	48 89 81 88 00 00 00 	mov    %rax,0x88(%rcx)
 105d543:	4c 89 f8             	mov    %r15,%rax
 105d546:	48 ff c8             	dec    %rax
 105d549:	0f 80 60 18 00 00    	jo     105edaf <my.vm::run+0x387f>
 105d54f:	48 89 c6             	mov    %rax,%rsi
 105d552:	4c 29 ce             	sub    %r9,%rsi
 105d555:	0f 80 68 18 00 00    	jo     105edc3 <my.vm::run+0x3893>
 105d55b:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d560:	48 8b 40 78          	mov    0x78(%rax),%rax
 105d564:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d568:	48 39 d6             	cmp    %rdx,%rsi
 105d56b:	0f 83 e4 0d 00 00    	jae    105e355 <my.vm::run+0x2e25>
 105d571:	48 89 f1             	mov    %rsi,%rcx
 105d574:	48 c1 e1 04          	shl    $0x4,%rcx
 105d578:	4c 8b 44 08 28       	mov    0x28(%rax,%rcx,1),%r8
 105d57d:	8b 4c 08 20          	mov    0x20(%rax,%rcx,1),%ecx
 105d581:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
 105d588:	00 
 105d589:	48 89 04 24          	mov    %rax,(%rsp)
 105d58d:	48 8d bc 24 18 08 00 	lea    0x818(%rsp),%rdi
 105d594:	00 
 105d595:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105d59a:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105d59f:	e8 ac 70 00 00       	call   1064650 <my.vm::call_value>
 105d5a4:	f6 84 24 18 08 00 00 	testb  $0x1,0x818(%rsp)
 105d5ab:	01 
 105d5ac:	0f 84 a7 12 00 00    	je     105e859 <my.vm::run+0x3329>
 105d5b2:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d5b7:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105d5be:	4c 89 f6             	mov    %r14,%rsi
 105d5c1:	48 ff ce             	dec    %rsi
 105d5c4:	0f 80 a2 19 00 00    	jo     105ef6c <my.vm::run+0x3a3c>
 105d5ca:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d5cf:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105d5d6:	48 8b 80 88 00 00 00 	mov    0x88(%rax),%rax
 105d5dd:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d5e1:	48 39 d6             	cmp    %rdx,%rsi
 105d5e4:	0f 82 13 03 00 00    	jb     105d8fd <my.vm::run+0x23cd>
 105d5ea:	48 89 f1             	mov    %rsi,%rcx
 105d5ed:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d5f1:	48 21 d1             	and    %rdx,%rcx
 105d5f4:	48 01 f1             	add    %rsi,%rcx
 105d5f7:	48 39 d1             	cmp    %rdx,%rcx
 105d5fa:	0f 82 00 03 00 00    	jb     105d900 <my.vm::run+0x23d0>
 105d600:	e9 25 1e 00 00       	jmp    105f42a <my.vm::run+0x3efa>
 105d605:	4d 89 f7             	mov    %r14,%r15
 105d608:	4c 8d ac 24 a8 00 00 	lea    0xa8(%rsp),%r13
 105d60f:	00 
 105d610:	4c 89 ef             	mov    %r13,%rdi
 105d613:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105d618:	4c 89 da             	mov    %r11,%rdx
 105d61b:	48 89 e9             	mov    %rbp,%rcx
 105d61e:	e8 9d 68 00 00       	call   1063ec0 <my.vm::read_constant>
 105d623:	0f b6 84 24 a8 00 00 	movzbl 0xa8(%rsp),%eax
 105d62a:	00 
 105d62b:	83 f8 03             	cmp    $0x3,%eax
 105d62e:	0f 85 14 14 00 00    	jne    105ea48 <my.vm::run+0x3518>
 105d634:	4c 8b 8c 24 d0 00 00 	mov    0xd0(%rsp),%r9
 105d63b:	00 
 105d63c:	4c 8b 84 24 c8 00 00 	mov    0xc8(%rsp),%r8
 105d643:	00 
 105d644:	48 8b 8c 24 c0 00 00 	mov    0xc0(%rsp),%rcx
 105d64b:	00 
 105d64c:	48 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%rax
 105d653:	00 
 105d654:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 105d659:	48 8b 94 24 b8 00 00 	mov    0xb8(%rsp),%rdx
 105d660:	00 
 105d661:	48 8d bc 24 78 04 00 	lea    0x478(%rsp),%rdi
 105d668:	00 
 105d669:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105d66e:	4c 89 f6             	mov    %r14,%rsi
 105d671:	e8 8a 67 00 00       	call   1063e00 <my.vm::read_byte>
 105d676:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105d67d:	4d 85 ff             	test   %r15,%r15
 105d680:	7f 04                	jg     105d686 <my.vm::run+0x2156>
 105d682:	48 03 58 08          	add    0x8(%rax),%rbx
 105d686:	4c 8b a4 24 78 04 00 	mov    0x478(%rsp),%r12
 105d68d:	00 
 105d68e:	48 8b 8c 24 90 04 00 	mov    0x490(%rsp),%rcx
 105d695:	00 
 105d696:	48 c1 e3 05          	shl    $0x5,%rbx
 105d69a:	48 89 4c 18 30       	mov    %rcx,0x30(%rax,%rbx,1)
 105d69f:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105d6a4:	48 89 81 88 00 00 00 	mov    %rax,0x88(%rcx)
 105d6ab:	4c 8b b9 80 00 00 00 	mov    0x80(%rcx),%r15
 105d6b2:	4c 89 f8             	mov    %r15,%rax
 105d6b5:	48 ff c8             	dec    %rax
 105d6b8:	0f 80 84 16 00 00    	jo     105ed42 <my.vm::run+0x3812>
 105d6be:	48 89 c6             	mov    %rax,%rsi
 105d6c1:	4c 29 e6             	sub    %r12,%rsi
 105d6c4:	0f 80 41 16 00 00    	jo     105ed0b <my.vm::run+0x37db>
 105d6ca:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d6cf:	48 8b 58 78          	mov    0x78(%rax),%rbx
 105d6d3:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105d6d7:	48 39 d6             	cmp    %rdx,%rsi
 105d6da:	0f 83 6b 0d 00 00    	jae    105e44b <my.vm::run+0x2f1b>
 105d6e0:	48 89 f0             	mov    %rsi,%rax
 105d6e3:	48 c1 e0 04          	shl    $0x4,%rax
 105d6e7:	80 7c 03 20 03       	cmpb   $0x3,0x20(%rbx,%rax,1)
 105d6ec:	0f 85 aa 01 00 00    	jne    105d89c <my.vm::run+0x236c>
 105d6f2:	48 8b 6c 03 28       	mov    0x28(%rbx,%rax,1),%rbp
 105d6f7:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d6fc:	48 8b 00             	mov    (%rax),%rax
 105d6ff:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d703:	48 89 e9             	mov    %rbp,%rcx
 105d706:	48 39 d5             	cmp    %rdx,%rbp
 105d709:	0f 83 d9 0e 00 00    	jae    105e5e8 <my.vm::run+0x30b8>
 105d70f:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105d713:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 105d718:	0f 85 7e 01 00 00    	jne    105d89c <my.vm::run+0x236c>
 105d71e:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105d723:	4c 89 f7             	mov    %r14,%rdi
 105d726:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 105d72b:	4c 89 ee             	mov    %r13,%rsi
 105d72e:	e8 2d d2 00 00       	call   106a960 <my.heap::string_hash>
 105d733:	4c 89 f7             	mov    %r14,%rdi
 105d736:	48 89 ee             	mov    %rbp,%rsi
 105d739:	4c 89 ea             	mov    %r13,%rdx
 105d73c:	89 c1                	mov    %eax,%ecx
 105d73e:	e8 fd d7 00 00       	call   106af40 <my.heap::instance_field>
 105d743:	3c 01                	cmp    $0x1,%al
 105d745:	0f 85 02 08 00 00    	jne    105df4d <my.vm::run+0x2a1d>
 105d74b:	4c 89 f8             	mov    %r15,%rax
 105d74e:	4c 29 e0             	sub    %r12,%rax
 105d751:	0f 80 f8 19 00 00    	jo     105f14f <my.vm::run+0x3c1f>
 105d757:	48 89 c6             	mov    %rax,%rsi
 105d75a:	48 ff ce             	dec    %rsi
 105d75d:	0f 80 d8 19 00 00    	jo     105f13b <my.vm::run+0x3c0b>
 105d763:	49 89 c8             	mov    %rcx,%r8
 105d766:	48 8b 43 08          	mov    0x8(%rbx),%rax
 105d76a:	48 39 c6             	cmp    %rax,%rsi
 105d76d:	0f 83 df 0f 00 00    	jae    105e752 <my.vm::run+0x3222>
 105d773:	48 89 f1             	mov    %rsi,%rcx
 105d776:	48 83 c3 20          	add    $0x20,%rbx
 105d77a:	48 c1 e1 04          	shl    $0x4,%rcx
 105d77e:	0f b6 c2             	movzbl %dl,%eax
 105d781:	48 89 04 0b          	mov    %rax,(%rbx,%rcx,1)
 105d785:	4c 89 44 0b 08       	mov    %r8,0x8(%rbx,%rcx,1)
 105d78a:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
 105d791:	00 
 105d792:	48 89 04 24          	mov    %rax,(%rsp)
 105d796:	0f b6 ca             	movzbl %dl,%ecx
 105d799:	4c 8d ac 24 a8 00 00 	lea    0xa8(%rsp),%r13
 105d7a0:	00 
 105d7a1:	4c 89 ef             	mov    %r13,%rdi
 105d7a4:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105d7a9:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105d7ae:	4d 89 e1             	mov    %r12,%r9
 105d7b1:	e8 9a 6e 00 00       	call   1064650 <my.vm::call_value>
 105d7b6:	41 f6 45 00 01       	testb  $0x1,0x0(%r13)
 105d7bb:	0f 85 ff 00 00 00    	jne    105d8c0 <my.vm::run+0x2390>
 105d7c1:	e9 93 10 00 00       	jmp    105e859 <my.vm::run+0x3329>
 105d7c6:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d7cb:	48 8b b0 80 00 00 00 	mov    0x80(%rax),%rsi
 105d7d2:	49 89 f7             	mov    %rsi,%r15
 105d7d5:	49 ff cf             	dec    %r15
 105d7d8:	0f 80 be 14 00 00    	jo     105ec9c <my.vm::run+0x376c>
 105d7de:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d7e3:	48 8b 40 78          	mov    0x78(%rax),%rax
 105d7e7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d7eb:	4c 89 f9             	mov    %r15,%rcx
 105d7ee:	49 39 d7             	cmp    %rdx,%r15
 105d7f1:	0f 83 ad 0a 00 00    	jae    105e2a4 <my.vm::run+0x2d74>
 105d7f7:	48 c1 e1 04          	shl    $0x4,%rcx
 105d7fb:	80 7c 08 20 02       	cmpb   $0x2,0x20(%rax,%rcx,1)
 105d800:	0f 85 1a 01 00 00    	jne    105d920 <my.vm::run+0x23f0>
 105d806:	48 01 c8             	add    %rcx,%rax
 105d809:	48 83 c0 20          	add    $0x20,%rax
 105d80d:	48 c7 00 02 00 00 00 	movq   $0x2,(%rax)
 105d814:	80 70 0f 80          	xorb   $0x80,0xf(%rax)
 105d818:	e9 0b 06 00 00       	jmp    105de28 <my.vm::run+0x28f8>
 105d81d:	4c 89 5c 24 30       	mov    %r11,0x30(%rsp)
 105d822:	4c 89 4c 24 20       	mov    %r9,0x20(%rsp)
 105d827:	48 8d 0d 32 53 fb ff 	lea    -0x4acce(%rip),%rcx        # 1012b60 <core_number_pairs+0xb900>
 105d82e:	48 8d 9c 24 60 03 00 	lea    0x360(%rsp),%rbx
 105d835:	00 
 105d836:	48 89 df             	mov    %rbx,%rdi
 105d839:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105d83e:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105d843:	4d 89 c6             	mov    %r8,%r14
 105d846:	e8 35 61 00 00       	call   1063980 <my.vm::runtime_error>
 105d84b:	4d 89 f0             	mov    %r14,%r8
 105d84e:	f6 03 01             	testb  $0x1,(%rbx)
 105d851:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105d856:	0f 84 fd 0f 00 00    	je     105e859 <my.vm::run+0x3329>
 105d85c:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d861:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105d868:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105d86f:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105d874:	48 8b 6c 24 28       	mov    0x28(%rsp),%rbp
 105d879:	e9 83 03 00 00       	jmp    105dc01 <my.vm::run+0x26d1>
 105d87e:	4d 89 c6             	mov    %r8,%r14
 105d881:	49 89 ef             	mov    %rbp,%r15
 105d884:	4c 89 e5             	mov    %r12,%rbp
 105d887:	4d 89 ec             	mov    %r13,%r12
 105d88a:	4d 89 dd             	mov    %r11,%r13
 105d88d:	4c 89 cb             	mov    %r9,%rbx
 105d890:	48 8d 0d c9 54 fb ff 	lea    -0x4ab37(%rip),%rcx        # 1012d60 <core_number_pairs+0xbb00>
 105d897:	e9 4b de ff ff       	jmp    105b6e7 <my.vm::run+0x1b7>
 105d89c:	48 8d 0d 7d 54 fb ff 	lea    -0x4ab83(%rip),%rcx        # 1012d20 <core_number_pairs+0xbac0>
 105d8a3:	4c 89 ef             	mov    %r13,%rdi
 105d8a6:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105d8ab:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105d8b0:	e8 cb 60 00 00       	call   1063980 <my.vm::runtime_error>
 105d8b5:	41 f6 45 00 01       	testb  $0x1,0x0(%r13)
 105d8ba:	0f 84 99 0f 00 00    	je     105e859 <my.vm::run+0x3329>
 105d8c0:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d8c5:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105d8cc:	4c 89 f6             	mov    %r14,%rsi
 105d8cf:	48 ff ce             	dec    %rsi
 105d8d2:	0f 80 bc 16 00 00    	jo     105ef94 <my.vm::run+0x3a64>
 105d8d8:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d8dd:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105d8e4:	48 8b 80 88 00 00 00 	mov    0x88(%rax),%rax
 105d8eb:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d8ef:	48 39 d6             	cmp    %rdx,%rsi
 105d8f2:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105d8f7:	0f 83 0d 0c 00 00    	jae    105e50a <my.vm::run+0x2fda>
 105d8fd:	48 89 f1             	mov    %rsi,%rcx
 105d900:	48 c1 e1 05          	shl    $0x5,%rcx
 105d904:	4c 8b 5c 08 20       	mov    0x20(%rax,%rcx,1),%r11
 105d909:	48 8b 6c 08 28       	mov    0x28(%rax,%rcx,1),%rbp
 105d90e:	4c 8b 44 08 30       	mov    0x30(%rax,%rcx,1),%r8
 105d913:	4c 8b 4c 08 38       	mov    0x38(%rax,%rcx,1),%r9
 105d918:	4d 89 c4             	mov    %r8,%r12
 105d91b:	e9 b0 05 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105d920:	4d 89 c6             	mov    %r8,%r14
 105d923:	49 89 ef             	mov    %rbp,%r15
 105d926:	4c 89 e5             	mov    %r12,%rbp
 105d929:	4d 89 ec             	mov    %r13,%r12
 105d92c:	4d 89 dd             	mov    %r11,%r13
 105d92f:	4c 89 cb             	mov    %r9,%rbx
 105d932:	48 8d 0d 47 53 fb ff 	lea    -0x4acb9(%rip),%rcx        # 1012c80 <core_number_pairs+0xba20>
 105d939:	e9 a9 dd ff ff       	jmp    105b6e7 <my.vm::run+0x1b7>
 105d93e:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105d943:	4c 89 f7             	mov    %r14,%rdi
 105d946:	48 89 de             	mov    %rbx,%rsi
 105d949:	e8 22 ce 00 00       	call   106a770 <my.heap::string_chars>
 105d94e:	48 89 c3             	mov    %rax,%rbx
 105d951:	48 8d 3d 88 51 fb ff 	lea    -0x4ae78(%rip),%rdi        # 1012ae0 <core_number_pairs+0xb880>
 105d958:	48 89 c6             	mov    %rax,%rsi
 105d95b:	e8 a0 1d fd ff       	call   102f700 <myl_core_bytes_concat>
 105d960:	49 89 c7             	mov    %rax,%r15
 105d963:	48 89 df             	mov    %rbx,%rdi
 105d966:	e8 95 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d96b:	48 8d 35 ae 51 fb ff 	lea    -0x4ae52(%rip),%rsi        # 1012b20 <core_number_pairs+0xb8c0>
 105d972:	4c 89 ff             	mov    %r15,%rdi
 105d975:	e8 86 1d fd ff       	call   102f700 <myl_core_bytes_concat>
 105d97a:	48 89 c3             	mov    %rax,%rbx
 105d97d:	4c 89 ff             	mov    %r15,%rdi
 105d980:	e8 7b 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d985:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105d98c:	00 
 105d98d:	4c 89 f6             	mov    %r14,%rsi
 105d990:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105d995:	48 89 d9             	mov    %rbx,%rcx
 105d998:	e8 e3 5f 00 00       	call   1063980 <my.vm::runtime_error>
 105d99d:	48 89 df             	mov    %rbx,%rdi
 105d9a0:	e8 5b 69 fc ff       	call   1024300 <myl_core_drop_owned>
 105d9a5:	f6 84 24 a8 00 00 00 	testb  $0x1,0xa8(%rsp)
 105d9ac:	01 
 105d9ad:	0f 84 a6 0e 00 00    	je     105e859 <my.vm::run+0x3329>
 105d9b3:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d9b8:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105d9bf:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105d9c6:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105d9cb:	4d 89 e0             	mov    %r12,%r8
 105d9ce:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105d9d3:	e9 29 02 00 00       	jmp    105dc01 <my.vm::run+0x26d1>
 105d9d8:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105d9dd:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105d9e4:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105d9eb:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105d9f0:	4d 89 e0             	mov    %r12,%r8
 105d9f3:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105d9f8:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105d9fd:	48 8b 6c 24 28       	mov    0x28(%rsp),%rbp
 105da02:	e9 c9 04 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105da07:	84 d2                	test   %dl,%dl
 105da09:	0f 85 38 16 00 00    	jne    105f047 <my.vm::run+0x3b17>
 105da0f:	4c 8b 84 24 58 03 00 	mov    0x358(%rsp),%r8
 105da16:	00 
 105da17:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105da1b:	48 39 d6             	cmp    %rdx,%rsi
 105da1e:	0f 83 fa 0b 00 00    	jae    105e61e <my.vm::run+0x30ee>
 105da24:	48 89 f0             	mov    %rsi,%rax
 105da27:	48 c1 e0 04          	shl    $0x4,%rax
 105da2b:	c5 f9 10 44 07 20    	vmovupd 0x20(%rdi,%rax,1),%xmm0
 105da31:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105da36:	48 8b 30             	mov    (%rax),%rsi
 105da39:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105da3d:	48 39 d3             	cmp    %rdx,%rbx
 105da40:	0f 83 f3 0b 00 00    	jae    105e639 <my.vm::run+0x3109>
 105da46:	48 89 d8             	mov    %rbx,%rax
 105da49:	4c 6b c8 38          	imul   $0x38,%rax,%r9
 105da4d:	42 0f b6 54 0e 20    	movzbl 0x20(%rsi,%r9,1),%edx
 105da53:	4a 8b 44 0e 28       	mov    0x28(%rsi,%r9,1),%rax
 105da58:	4a 8b 7c 0e 30       	mov    0x30(%rsi,%r9,1),%rdi
 105da5d:	4a 8b 4c 0e 38       	mov    0x38(%rsi,%r9,1),%rcx
 105da62:	4e 8b 7c 0e 40       	mov    0x40(%rsi,%r9,1),%r15
 105da67:	4a 8b 5c 0e 48       	mov    0x48(%rsi,%r9,1),%rbx
 105da6c:	4a c7 44 0e 20 05 00 	movq   $0x5,0x20(%rsi,%r9,1)
 105da73:	00 00 
 105da75:	4a c7 44 0e 28 ff ff 	movq   $0xffffffffffffffff,0x28(%rsi,%r9,1)
 105da7c:	ff ff 
 105da7e:	c5 f9 54 05 5a 69 fa 	vandpd -0x596a6(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105da85:	ff 
 105da86:	c4 a1 79 11 44 0e 30 	vmovupd %xmm0,0x30(%rsi,%r9,1)
 105da8d:	4e 89 44 0e 40       	mov    %r8,0x40(%rsi,%r9,1)
 105da92:	ff ca                	dec    %edx
 105da94:	83 fa 08             	cmp    $0x8,%edx
 105da97:	4d 89 e1             	mov    %r12,%r9
 105da9a:	49 89 eb             	mov    %rbp,%r11
 105da9d:	77 1b                	ja     105daba <my.vm::run+0x258a>
 105da9f:	48 8d 35 22 9a fa ff 	lea    -0x565de(%rip),%rsi        # 10074c8 <core_number_pairs+0x268>
 105daa6:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105daaa:	48 01 f2             	add    %rsi,%rdx
 105daad:	ff e2                	jmp    *%rdx
 105daaf:	e8 4c 68 fc ff       	call   1024300 <myl_core_drop_owned>
 105dab4:	49 89 eb             	mov    %rbp,%r11
 105dab7:	4d 89 e1             	mov    %r12,%r9
 105daba:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105dabf:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105dac6:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105dacd:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105dad2:	4d 89 e0             	mov    %r12,%r8
 105dad5:	48 8b 6c 24 28       	mov    0x28(%rsp),%rbp
 105dada:	e9 f1 03 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105dadf:	48 8b 84 24 10 03 00 	mov    0x310(%rsp),%rax
 105dae6:	00 
 105dae7:	0f b6 bc 24 08 03 00 	movzbl 0x308(%rsp),%edi
 105daee:	00 
 105daef:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105daf4:	48 8b 4a 78          	mov    0x78(%rdx),%rcx
 105daf8:	48 8b b2 80 00 00 00 	mov    0x80(%rdx),%rsi
 105daff:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105db03:	49 89 f0             	mov    %rsi,%r8
 105db06:	48 39 d6             	cmp    %rdx,%rsi
 105db09:	0f 83 f4 0a 00 00    	jae    105e603 <my.vm::run+0x30d3>
 105db0f:	49 c1 e0 04          	shl    $0x4,%r8
 105db13:	40 0f b6 d7          	movzbl %dil,%edx
 105db17:	4a 89 54 01 20       	mov    %rdx,0x20(%rcx,%r8,1)
 105db1c:	4a 89 44 01 28       	mov    %rax,0x28(%rcx,%r8,1)
 105db21:	48 89 f0             	mov    %rsi,%rax
 105db24:	48 ff c0             	inc    %rax
 105db27:	49 89 d9             	mov    %rbx,%r9
 105db2a:	4d 89 fb             	mov    %r15,%r11
 105db2d:	49 89 c7             	mov    %rax,%r15
 105db30:	0f 80 42 15 00 00    	jo     105f078 <my.vm::run+0x3b48>
 105db36:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105db3b:	4c 89 b8 80 00 00 00 	mov    %r15,0x80(%rax)
 105db42:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105db49:	4d 89 e0             	mov    %r12,%r8
 105db4c:	e9 7f 03 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105db51:	49 89 e9             	mov    %rbp,%r9
 105db54:	48 8b 44 24 30       	mov    0x30(%rsp),%rax
 105db59:	48 8b 6c 24 28       	mov    0x28(%rsp),%rbp
 105db5e:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105db63:	48 8b 09             	mov    (%rcx),%rcx
 105db66:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105db6a:	48 8b 74 24 70       	mov    0x70(%rsp),%rsi
 105db6f:	48 39 d6             	cmp    %rdx,%rsi
 105db72:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 105db77:	4c 89 64 24 18       	mov    %r12,0x18(%rsp)
 105db7c:	0f 83 55 09 00 00    	jae    105e4d7 <my.vm::run+0x2fa7>
 105db82:	48 89 f0             	mov    %rsi,%rax
 105db85:	4c 6b c0 38          	imul   $0x38,%rax,%r8
 105db89:	42 0f b6 54 01 20    	movzbl 0x20(%rcx,%r8,1),%edx
 105db8f:	4a 8b 7c 01 28       	mov    0x28(%rcx,%r8,1),%rdi
 105db94:	4a 8b 74 01 30       	mov    0x30(%rcx,%r8,1),%rsi
 105db99:	4a 8b 44 01 38       	mov    0x38(%rcx,%r8,1),%rax
 105db9e:	4a 8b 5c 01 40       	mov    0x40(%rcx,%r8,1),%rbx
 105dba3:	4e 8b 64 01 48       	mov    0x48(%rcx,%r8,1),%r12
 105dba8:	4a c7 44 01 20 04 00 	movq   $0x4,0x20(%rcx,%r8,1)
 105dbaf:	00 00 
 105dbb1:	4c 8b 54 24 68       	mov    0x68(%rsp),%r10
 105dbb6:	4e 89 54 01 28       	mov    %r10,0x28(%rcx,%r8,1)
 105dbbb:	4c 8b 54 24 58       	mov    0x58(%rsp),%r10
 105dbc0:	4e 89 54 01 30       	mov    %r10,0x30(%rcx,%r8,1)
 105dbc5:	83 fa 09             	cmp    $0x9,%edx
 105dbc8:	77 1c                	ja     105dbe6 <my.vm::run+0x26b6>
 105dbca:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105dbcf:	0f a3 d1             	bt     %edx,%ecx
 105dbd2:	0f 83 89 00 00 00    	jae    105dc61 <my.vm::run+0x2731>
 105dbd8:	48 89 f7             	mov    %rsi,%rdi
 105dbdb:	4c 89 cb             	mov    %r9,%rbx
 105dbde:	e8 1d 67 fc ff       	call   1024300 <myl_core_drop_owned>
 105dbe3:	49 89 d9             	mov    %rbx,%r9
 105dbe6:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105dbeb:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105dbf2:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105dbf9:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105dbfe:	4d 89 e0             	mov    %r12,%r8
 105dc01:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105dc06:	e9 c5 02 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105dc0b:	83 fa 01             	cmp    $0x1,%edx
 105dc0e:	0f 84 4d e0 ff ff    	je     105bc61 <my.vm::run+0x731>
 105dc14:	83 fa 02             	cmp    $0x2,%edx
 105dc17:	0f 85 4c e0 ff ff    	jne    105bc69 <my.vm::run+0x739>
 105dc1d:	48 89 cf             	mov    %rcx,%rdi
 105dc20:	e8 db 66 fc ff       	call   1024300 <myl_core_drop_owned>
 105dc25:	4c 89 ff             	mov    %r15,%rdi
 105dc28:	e8 d3 66 fc ff       	call   1024300 <myl_core_drop_owned>
 105dc2d:	4c 89 f7             	mov    %r14,%rdi
 105dc30:	e9 2c e0 ff ff       	jmp    105bc61 <my.vm::run+0x731>
 105dc35:	41 83 f8 01          	cmp    $0x1,%r8d
 105dc39:	0f 84 c5 dd ff ff    	je     105ba04 <my.vm::run+0x4d4>
 105dc3f:	41 83 f8 02          	cmp    $0x2,%r8d
 105dc43:	0f 85 c0 dd ff ff    	jne    105ba09 <my.vm::run+0x4d9>
 105dc49:	48 89 c7             	mov    %rax,%rdi
 105dc4c:	e8 af 66 fc ff       	call   1024300 <myl_core_drop_owned>
 105dc51:	48 89 df             	mov    %rbx,%rdi
 105dc54:	e8 a7 66 fc ff       	call   1024300 <myl_core_drop_owned>
 105dc59:	4c 89 ff             	mov    %r15,%rdi
 105dc5c:	e9 a3 dd ff ff       	jmp    105ba04 <my.vm::run+0x4d4>
 105dc61:	83 fa 01             	cmp    $0x1,%edx
 105dc64:	0f 84 71 ff ff ff    	je     105dbdb <my.vm::run+0x26ab>
 105dc6a:	83 fa 02             	cmp    $0x2,%edx
 105dc6d:	0f 85 73 ff ff ff    	jne    105dbe6 <my.vm::run+0x26b6>
 105dc73:	48 89 c7             	mov    %rax,%rdi
 105dc76:	4d 89 cf             	mov    %r9,%r15
 105dc79:	e8 82 66 fc ff       	call   1024300 <myl_core_drop_owned>
 105dc7e:	48 89 df             	mov    %rbx,%rdi
 105dc81:	e8 7a 66 fc ff       	call   1024300 <myl_core_drop_owned>
 105dc86:	4d 89 f9             	mov    %r15,%r9
 105dc89:	4c 89 e7             	mov    %r12,%rdi
 105dc8c:	e9 4a ff ff ff       	jmp    105dbdb <my.vm::run+0x26ab>
 105dc91:	49 89 f7             	mov    %rsi,%r15
 105dc94:	49 ff cf             	dec    %r15
 105dc97:	0f 80 ec 13 00 00    	jo     105f089 <my.vm::run+0x3b59>
 105dc9d:	4c 89 f9             	mov    %r15,%rcx
 105dca0:	49 39 d7             	cmp    %rdx,%r15
 105dca3:	0f 83 c6 09 00 00    	jae    105e66f <my.vm::run+0x313f>
 105dca9:	48 c1 e1 04          	shl    $0x4,%rcx
 105dcad:	80 3c 0f 02          	cmpb   $0x2,(%rdi,%rcx,1)
 105dcb1:	75 37                	jne    105dcea <my.vm::run+0x27ba>
 105dcb3:	48 01 cf             	add    %rcx,%rdi
 105dcb6:	c4 e1 f9 6e c0       	vmovq  %rax,%xmm0
 105dcbb:	c5 fb 58 47 08       	vaddsd 0x8(%rdi),%xmm0,%xmm0
 105dcc0:	48 c7 07 02 00 00 00 	movq   $0x2,(%rdi)
 105dcc7:	c5 fb 11 47 08       	vmovsd %xmm0,0x8(%rdi)
 105dccc:	49 ff c7             	inc    %r15
 105dccf:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105dcd4:	4c 89 b8 80 00 00 00 	mov    %r15,0x80(%rax)
 105dcdb:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105dce2:	49 89 d9             	mov    %rbx,%r9
 105dce5:	e9 17 ff ff ff       	jmp    105dc01 <my.vm::run+0x26d1>
 105dcea:	4d 89 c6             	mov    %r8,%r14
 105dced:	48 8d 0d 2c 4f fb ff 	lea    -0x4b0d4(%rip),%rcx        # 1012c20 <core_number_pairs+0xb9c0>
 105dcf4:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
 105dcfb:	00 
 105dcfc:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105dd01:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105dd06:	e8 75 5c 00 00       	call   1063980 <my.vm::runtime_error>
 105dd0b:	f6 84 24 a8 00 00 00 	testb  $0x1,0xa8(%rsp)
 105dd12:	01 
 105dd13:	0f 84 40 0b 00 00    	je     105e859 <my.vm::run+0x3329>
 105dd19:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105dd1e:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105dd25:	48 8b 80 90 00 00 00 	mov    0x90(%rax),%rax
 105dd2c:	49 89 d9             	mov    %rbx,%r9
 105dd2f:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105dd34:	4d 89 f0             	mov    %r14,%r8
 105dd37:	49 89 c6             	mov    %rax,%r14
 105dd3a:	e9 91 01 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105dd3f:	b2 01                	mov    $0x1,%dl
 105dd41:	eb 02                	jmp    105dd45 <my.vm::run+0x2815>
 105dd43:	31 d2                	xor    %edx,%edx
 105dd45:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105dd49:	49 89 f3             	mov    %rsi,%r11
 105dd4c:	49 c1 e3 04          	shl    $0x4,%r11
 105dd50:	49 01 fb             	add    %rdi,%r11
 105dd53:	48 c1 e1 04          	shl    $0x4,%rcx
 105dd57:	4a c7 04 19 01 00 00 	movq   $0x1,(%rcx,%r11,1)
 105dd5e:	00 
 105dd5f:	42 88 54 19 08       	mov    %dl,0x8(%rcx,%r11,1)
 105dd64:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105dd69:	48 89 41 78          	mov    %rax,0x78(%rcx)
 105dd6d:	48 ff c6             	inc    %rsi
 105dd70:	48 89 b1 80 00 00 00 	mov    %rsi,0x80(%rcx)
 105dd77:	49 89 f7             	mov    %rsi,%r15
 105dd7a:	4d 89 d3             	mov    %r10,%r11
 105dd7d:	e9 4e 01 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105dd82:	41 80 f8 01          	cmp    $0x1,%r8b
 105dd86:	4d 89 d1             	mov    %r10,%r9
 105dd89:	0f 85 b4 00 00 00    	jne    105de43 <my.vm::run+0x2913>
 105dd8f:	31 fe                	xor    %edi,%esi
 105dd91:	40 80 f6 01          	xor    $0x1,%sil
 105dd95:	e9 b2 00 00 00       	jmp    105de4c <my.vm::run+0x291c>
 105dd9a:	41 80 f8 02          	cmp    $0x2,%r8b
 105dd9e:	0f 85 a3 00 00 00    	jne    105de47 <my.vm::run+0x2917>
 105dda4:	c4 e1 f9 6e c6       	vmovq  %rsi,%xmm0
 105dda9:	c4 e1 f9 6e cf       	vmovq  %rdi,%xmm1
 105ddae:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 105ddb3:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 105ddb8:	83 e6 01             	and    $0x1,%esi
 105ddbb:	e9 89 00 00 00       	jmp    105de49 <my.vm::run+0x2919>
 105ddc0:	48 8d 9c 24 48 05 00 	lea    0x548(%rsp),%rbx
 105ddc7:	00 
 105ddc8:	e9 b6 00 00 00       	jmp    105de83 <my.vm::run+0x2953>
 105ddcd:	41 80 f8 03          	cmp    $0x3,%r8b
 105ddd1:	41 0f 94 c0          	sete   %r8b
 105ddd5:	48 39 fe             	cmp    %rdi,%rsi
 105ddd8:	40 0f 94 c6          	sete   %sil
 105dddc:	44 20 c6             	and    %r8b,%sil
 105dddf:	eb 68                	jmp    105de49 <my.vm::run+0x2919>
 105dde1:	48 8d 9c 24 60 03 00 	lea    0x360(%rsp),%rbx
 105dde8:	00 
 105dde9:	e9 95 00 00 00       	jmp    105de83 <my.vm::run+0x2953>
 105ddee:	48 8d 9c 24 38 06 00 	lea    0x638(%rsp),%rbx
 105ddf5:	00 
 105ddf6:	e9 88 00 00 00       	jmp    105de83 <my.vm::run+0x2953>
 105ddfb:	c5 f3 5c c0          	vsubsd %xmm0,%xmm1,%xmm0
 105ddff:	eb 1b                	jmp    105de1c <my.vm::run+0x28ec>
 105de01:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
 105de05:	48 c7 00 01 00 00 00 	movq   $0x1,(%rax)
 105de0c:	0f 97 40 08          	seta   0x8(%rax)
 105de10:	eb 16                	jmp    105de28 <my.vm::run+0x28f8>
 105de12:	c5 fb 59 c1          	vmulsd %xmm1,%xmm0,%xmm0
 105de16:	eb 04                	jmp    105de1c <my.vm::run+0x28ec>
 105de18:	c5 f3 5e c0          	vdivsd %xmm0,%xmm1,%xmm0
 105de1c:	48 c7 00 02 00 00 00 	movq   $0x2,(%rax)
 105de23:	c5 fb 11 40 08       	vmovsd %xmm0,0x8(%rax)
 105de28:	49 ff c7             	inc    %r15
 105de2b:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105de30:	4c 89 b8 80 00 00 00 	mov    %r15,0x80(%rax)
 105de37:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105de3e:	e9 8d 00 00 00       	jmp    105ded0 <my.vm::run+0x29a0>
 105de43:	31 f6                	xor    %esi,%esi
 105de45:	eb 05                	jmp    105de4c <my.vm::run+0x291c>
 105de47:	31 f6                	xor    %esi,%esi
 105de49:	4d 89 d1             	mov    %r10,%r9
 105de4c:	48 01 ca             	add    %rcx,%rdx
 105de4f:	48 c7 02 01 00 00 00 	movq   $0x1,(%rdx)
 105de56:	40 80 e6 01          	and    $0x1,%sil
 105de5a:	40 88 72 08          	mov    %sil,0x8(%rdx)
 105de5e:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105de63:	48 89 41 78          	mov    %rax,0x78(%rcx)
 105de67:	49 ff c7             	inc    %r15
 105de6a:	4c 89 b9 80 00 00 00 	mov    %r15,0x80(%rcx)
 105de71:	49 89 d8             	mov    %rbx,%r8
 105de74:	eb 5a                	jmp    105ded0 <my.vm::run+0x29a0>
 105de76:	48 8d 9c 24 a8 00 00 	lea    0xa8(%rsp),%rbx
 105de7d:	00 
 105de7e:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105de83:	48 8d 0d 16 4d fb ff 	lea    -0x4b2ea(%rip),%rcx        # 1012ba0 <core_number_pairs+0xb940>
 105de8a:	48 89 df             	mov    %rbx,%rdi
 105de8d:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105de92:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105de97:	e8 e4 5a 00 00       	call   1063980 <my.vm::runtime_error>
 105de9c:	f6 03 01             	testb  $0x1,(%rbx)
 105de9f:	0f 84 b4 09 00 00    	je     105e859 <my.vm::run+0x3329>
 105dea5:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105deaa:	4c 8b b8 80 00 00 00 	mov    0x80(%rax),%r15
 105deb1:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105deb8:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105debd:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105dec2:	4c 8b 44 24 18       	mov    0x18(%rsp),%r8
 105dec7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 105dece:	00 00 
 105ded0:	4c 89 f6             	mov    %r14,%rsi
 105ded3:	48 ff ce             	dec    %rsi
 105ded6:	0f 80 f3 09 00 00    	jo     105e8cf <my.vm::run+0x339f>
 105dedc:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105dee1:	48 8b 80 88 00 00 00 	mov    0x88(%rax),%rax
 105dee8:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105deec:	48 39 d6             	cmp    %rdx,%rsi
 105deef:	0f 83 c0 01 00 00    	jae    105e0b5 <my.vm::run+0x2b85>
 105def5:	48 89 f1             	mov    %rsi,%rcx
 105def8:	48 c1 e1 05          	shl    $0x5,%rcx
 105defc:	4c 89 64 08 30       	mov    %r12,0x30(%rax,%rcx,1)
 105df01:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 105df06:	48 89 81 88 00 00 00 	mov    %rax,0x88(%rcx)
 105df0d:	e9 9e d6 ff ff       	jmp    105b5b0 <my.vm::run+0x80>
 105df12:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 105df17:	4c 89 f7             	mov    %r14,%rdi
 105df1a:	48 89 de             	mov    %rbx,%rsi
 105df1d:	e8 0e d1 00 00       	call   106b030 <my.heap::instance_class>
 105df22:	48 8d 9c 24 a8 00 00 	lea    0xa8(%rsp),%rbx
 105df29:	00 
 105df2a:	48 89 df             	mov    %rbx,%rdi
 105df2d:	4c 89 f6             	mov    %r14,%rsi
 105df30:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105df35:	48 89 c1             	mov    %rax,%rcx
 105df38:	4d 89 e0             	mov    %r12,%r8
 105df3b:	e8 60 60 00 00       	call   1063fa0 <my.vm::bind_method>
 105df40:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105df45:	4d 89 e0             	mov    %r12,%r8
 105df48:	e9 01 f9 ff ff       	jmp    105d84e <my.vm::run+0x231e>
 105df4d:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 105df52:	48 89 df             	mov    %rbx,%rdi
 105df55:	48 89 ee             	mov    %rbp,%rsi
 105df58:	e8 d3 d0 00 00       	call   106b030 <my.heap::instance_class>
 105df5d:	4d 89 e8             	mov    %r13,%r8
 105df60:	4c 8d ac 24 a8 00 00 	lea    0xa8(%rsp),%r13
 105df67:	00 
 105df68:	4c 89 ef             	mov    %r13,%rdi
 105df6b:	48 89 de             	mov    %rbx,%rsi
 105df6e:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105df73:	48 89 c1             	mov    %rax,%rcx
 105df76:	4d 89 e1             	mov    %r12,%r9
 105df79:	e8 92 6d 00 00       	call   1064d10 <my.vm::invoke_from_class>
 105df7e:	41 f6 45 00 01       	testb  $0x1,0x0(%r13)
 105df83:	0f 85 37 f9 ff ff    	jne    105d8c0 <my.vm::run+0x2390>
 105df89:	e9 cb 08 00 00       	jmp    105e859 <my.vm::run+0x3329>
 105df8e:	4c 89 fd             	mov    %r15,%rbp
 105df91:	49 89 cf             	mov    %rcx,%r15
 105df94:	49 89 d5             	mov    %rdx,%r13
 105df97:	48 89 ef             	mov    %rbp,%rdi
 105df9a:	e8 61 63 fc ff       	call   1024300 <myl_core_drop_owned>
 105df9f:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105dfa3:	49 39 d6             	cmp    %rdx,%r14
 105dfa6:	0f 83 14 07 00 00    	jae    105e6c0 <my.vm::run+0x3190>
 105dfac:	4c 89 f0             	mov    %r14,%rax
 105dfaf:	4d 89 ea             	mov    %r13,%r10
 105dfb2:	4c 89 fe             	mov    %r15,%rsi
 105dfb5:	4c 8b 44 24 18       	mov    0x18(%rsp),%r8
 105dfba:	48 83 c3 20          	add    $0x20,%rbx
 105dfbe:	4c 6b c8 38          	imul   $0x38,%rax,%r9
 105dfc2:	42 0f b6 0c 0b       	movzbl (%rbx,%r9,1),%ecx
 105dfc7:	4a 8b 7c 0b 08       	mov    0x8(%rbx,%r9,1),%rdi
 105dfcc:	4a 8b 54 0b 10       	mov    0x10(%rbx,%r9,1),%rdx
 105dfd1:	4a 8b 44 0b 18       	mov    0x18(%rbx,%r9,1),%rax
 105dfd6:	4e 8b 6c 0b 20       	mov    0x20(%rbx,%r9,1),%r13
 105dfdb:	4e 8b 7c 0b 28       	mov    0x28(%rbx,%r9,1),%r15
 105dfe0:	4a c7 04 0b 06 00 00 	movq   $0x6,(%rbx,%r9,1)
 105dfe7:	00 
 105dfe8:	4c 8b 5c 24 68       	mov    0x68(%rsp),%r11
 105dfed:	4e 89 5c 0b 08       	mov    %r11,0x8(%rbx,%r9,1)
 105dff2:	4e 89 54 0b 10       	mov    %r10,0x10(%rbx,%r9,1)
 105dff7:	4a 89 74 0b 18       	mov    %rsi,0x18(%rbx,%r9,1)
 105dffc:	83 f9 09             	cmp    $0x9,%ecx
 105dfff:	77 17                	ja     105e018 <my.vm::run+0x2ae8>
 105e001:	be d0 02 00 00       	mov    $0x2d0,%esi
 105e006:	0f a3 ce             	bt     %ecx,%esi
 105e009:	73 41                	jae    105e04c <my.vm::run+0x2b1c>
 105e00b:	48 89 d7             	mov    %rdx,%rdi
 105e00e:	e8 ed 62 fc ff       	call   1024300 <myl_core_drop_owned>
 105e013:	4c 8b 44 24 18       	mov    0x18(%rsp),%r8
 105e018:	4c 8b 7c 24 60       	mov    0x60(%rsp),%r15
 105e01d:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105e022:	4c 89 b8 80 00 00 00 	mov    %r15,0x80(%rax)
 105e029:	48 8b 44 24 58       	mov    0x58(%rsp),%rax
 105e02e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e032:	49 39 d7             	cmp    %rdx,%r15
 105e035:	0f 83 ab 06 00 00    	jae    105e6e6 <my.vm::run+0x31b6>
 105e03b:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105e040:	4c 8b b0 90 00 00 00 	mov    0x90(%rax),%r14
 105e047:	e9 e8 d9 ff ff       	jmp    105ba34 <my.vm::run+0x504>
 105e04c:	83 f9 01             	cmp    $0x1,%ecx
 105e04f:	74 bd                	je     105e00e <my.vm::run+0x2ade>
 105e051:	83 f9 02             	cmp    $0x2,%ecx
 105e054:	75 c2                	jne    105e018 <my.vm::run+0x2ae8>
 105e056:	48 89 c7             	mov    %rax,%rdi
 105e059:	e8 a2 62 fc ff       	call   1024300 <myl_core_drop_owned>
 105e05e:	4c 89 ef             	mov    %r13,%rdi
 105e061:	e8 9a 62 fc ff       	call   1024300 <myl_core_drop_owned>
 105e066:	4c 89 ff             	mov    %r15,%rdi
 105e069:	eb a3                	jmp    105e00e <my.vm::run+0x2ade>
 105e06b:	48 89 cf             	mov    %rcx,%rdi
 105e06e:	e8 8d 62 fc ff       	call   1024300 <myl_core_drop_owned>
 105e073:	4c 89 ff             	mov    %r15,%rdi
 105e076:	e8 85 62 fc ff       	call   1024300 <myl_core_drop_owned>
 105e07b:	48 89 df             	mov    %rbx,%rdi
 105e07e:	e9 2c fa ff ff       	jmp    105daaf <my.vm::run+0x257f>
 105e083:	48 89 c7             	mov    %rax,%rdi
 105e086:	e9 24 fa ff ff       	jmp    105daaf <my.vm::run+0x257f>
 105e08b:	83 fe 01             	cmp    $0x1,%esi
 105e08e:	0f 84 a9 e8 ff ff    	je     105c93d <my.vm::run+0x140d>
 105e094:	83 fe 02             	cmp    $0x2,%esi
 105e097:	0f 85 a5 e8 ff ff    	jne    105c942 <my.vm::run+0x1412>
 105e09d:	48 89 c7             	mov    %rax,%rdi
 105e0a0:	e8 5b 62 fc ff       	call   1024300 <myl_core_drop_owned>
 105e0a5:	4c 89 ef             	mov    %r13,%rdi
 105e0a8:	e8 53 62 fc ff       	call   1024300 <myl_core_drop_owned>
 105e0ad:	4c 89 f7             	mov    %r14,%rdi
 105e0b0:	e9 88 e8 ff ff       	jmp    105c93d <my.vm::run+0x140d>
 105e0b5:	48 89 f1             	mov    %rsi,%rcx
 105e0b8:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e0bc:	48 21 d1             	and    %rdx,%rcx
 105e0bf:	48 01 f1             	add    %rsi,%rcx
 105e0c2:	48 39 d1             	cmp    %rdx,%rcx
 105e0c5:	0f 82 2d fe ff ff    	jb     105def8 <my.vm::run+0x29c8>
 105e0cb:	e9 48 11 00 00       	jmp    105f218 <my.vm::run+0x3ce8>
 105e0d0:	48 89 f7             	mov    %rsi,%rdi
 105e0d3:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e0d7:	48 21 d7             	and    %rdx,%rdi
 105e0da:	48 01 f7             	add    %rsi,%rdi
 105e0dd:	48 39 d7             	cmp    %rdx,%rdi
 105e0e0:	0f 82 82 d5 ff ff    	jb     105b668 <my.vm::run+0x138>
 105e0e6:	e9 39 11 00 00       	jmp    105f224 <my.vm::run+0x3cf4>
 105e0eb:	4c 89 fe             	mov    %r15,%rsi
 105e0ee:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e0f2:	48 21 d6             	and    %rdx,%rsi
 105e0f5:	4c 01 fe             	add    %r15,%rsi
 105e0f8:	48 39 d6             	cmp    %rdx,%rsi
 105e0fb:	0f 82 90 d5 ff ff    	jb     105b691 <my.vm::run+0x161>
 105e101:	e9 39 11 00 00       	jmp    105f23f <my.vm::run+0x3d0f>
 105e106:	4c 89 f9             	mov    %r15,%rcx
 105e109:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e10d:	48 21 d1             	and    %rdx,%rcx
 105e110:	4c 01 f9             	add    %r15,%rcx
 105e113:	48 39 d1             	cmp    %rdx,%rcx
 105e116:	0f 82 8c e1 ff ff    	jb     105c2a8 <my.vm::run+0xd78>
 105e11c:	e9 d2 11 00 00       	jmp    105f2f3 <my.vm::run+0x3dc3>
 105e121:	4c 89 f9             	mov    %r15,%rcx
 105e124:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e128:	48 21 d1             	and    %rdx,%rcx
 105e12b:	4c 01 f9             	add    %r15,%rcx
 105e12e:	48 39 d1             	cmp    %rdx,%rcx
 105e131:	0f 82 56 e2 ff ff    	jb     105c38d <my.vm::run+0xe5d>
 105e137:	e9 54 11 00 00       	jmp    105f290 <my.vm::run+0x3d60>
 105e13c:	4c 89 f9             	mov    %r15,%rcx
 105e13f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e143:	48 21 d1             	and    %rdx,%rcx
 105e146:	4c 01 f9             	add    %r15,%rcx
 105e149:	48 39 d1             	cmp    %rdx,%rcx
 105e14c:	0f 82 ab e3 ff ff    	jb     105c4fd <my.vm::run+0xfcd>
 105e152:	e9 73 12 00 00       	jmp    105f3ca <my.vm::run+0x3e9a>
 105e157:	4c 89 f9             	mov    %r15,%rcx
 105e15a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e15e:	48 21 d1             	and    %rdx,%rcx
 105e161:	4c 01 f9             	add    %r15,%rcx
 105e164:	48 39 d1             	cmp    %rdx,%rcx
 105e167:	0f 82 d5 e3 ff ff    	jb     105c542 <my.vm::run+0x1012>
 105e16d:	e9 dd 11 00 00       	jmp    105f34f <my.vm::run+0x3e1f>
 105e172:	48 89 f7             	mov    %rsi,%rdi
 105e175:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e179:	48 21 c7             	and    %rax,%rdi
 105e17c:	48 01 f7             	add    %rsi,%rdi
 105e17f:	48 39 c7             	cmp    %rax,%rdi
 105e182:	0f 82 1b d9 ff ff    	jb     105baa3 <my.vm::run+0x573>
 105e188:	e9 12 11 00 00       	jmp    105f29f <my.vm::run+0x3d6f>
 105e18d:	48 89 f1             	mov    %rsi,%rcx
 105e190:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e194:	48 21 d1             	and    %rdx,%rcx
 105e197:	48 01 f1             	add    %rsi,%rcx
 105e19a:	48 39 d1             	cmp    %rdx,%rcx
 105e19d:	0f 82 4a dc ff ff    	jb     105bded <my.vm::run+0x8bd>
 105e1a3:	e9 72 11 00 00       	jmp    105f31a <my.vm::run+0x3dea>
 105e1a8:	48 89 f0             	mov    %rsi,%rax
 105e1ab:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e1af:	48 21 d0             	and    %rdx,%rax
 105e1b2:	48 01 f0             	add    %rsi,%rax
 105e1b5:	48 39 d0             	cmp    %rdx,%rax
 105e1b8:	0f 82 0d de ff ff    	jb     105bfcb <my.vm::run+0xa9b>
 105e1be:	e9 7f 12 00 00       	jmp    105f442 <my.vm::run+0x3f12>
 105e1c3:	49 89 ef             	mov    %rbp,%r15
 105e1c6:	49 c1 ff 3f          	sar    $0x3f,%r15
 105e1ca:	49 21 d7             	and    %rdx,%r15
 105e1cd:	49 01 ef             	add    %rbp,%r15
 105e1d0:	49 39 d7             	cmp    %rdx,%r15
 105e1d3:	0f 82 33 de ff ff    	jb     105c00c <my.vm::run+0xadc>
 105e1d9:	e9 d1 11 00 00       	jmp    105f3af <my.vm::run+0x3e7f>
 105e1de:	48 89 f1             	mov    %rsi,%rcx
 105e1e1:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e1e5:	48 21 d1             	and    %rdx,%rcx
 105e1e8:	48 01 f1             	add    %rsi,%rcx
 105e1eb:	48 39 d1             	cmp    %rdx,%rcx
 105e1ee:	0f 82 0f e1 ff ff    	jb     105c303 <my.vm::run+0xdd3>
 105e1f4:	e9 3d 12 00 00       	jmp    105f436 <my.vm::run+0x3f06>
 105e1f9:	48 89 de             	mov    %rbx,%rsi
 105e1fc:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e200:	48 21 d6             	and    %rdx,%rsi
 105e203:	48 01 de             	add    %rbx,%rsi
 105e206:	48 39 d6             	cmp    %rdx,%rsi
 105e209:	0f 82 f8 e3 ff ff    	jb     105c607 <my.vm::run+0x10d7>
 105e20f:	e9 07 12 00 00       	jmp    105f41b <my.vm::run+0x3eeb>
 105e214:	48 89 f1             	mov    %rsi,%rcx
 105e217:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e21b:	48 21 d1             	and    %rdx,%rcx
 105e21e:	48 01 f1             	add    %rsi,%rcx
 105e221:	48 39 d1             	cmp    %rdx,%rcx
 105e224:	0f 82 75 e4 ff ff    	jb     105c69f <my.vm::run+0x116f>
 105e22a:	e9 2f 11 00 00       	jmp    105f35e <my.vm::run+0x3e2e>
 105e22f:	48 89 f7             	mov    %rsi,%rdi
 105e232:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e236:	48 21 d7             	and    %rdx,%rdi
 105e239:	48 01 f7             	add    %rsi,%rdi
 105e23c:	48 39 d7             	cmp    %rdx,%rdi
 105e23f:	0f 82 be e7 ff ff    	jb     105ca03 <my.vm::run+0x14d3>
 105e245:	e9 04 10 00 00       	jmp    105f24e <my.vm::run+0x3d1e>
 105e24a:	48 89 f7             	mov    %rsi,%rdi
 105e24d:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e251:	48 21 d7             	and    %rdx,%rdi
 105e254:	48 01 f7             	add    %rsi,%rdi
 105e257:	48 39 d7             	cmp    %rdx,%rdi
 105e25a:	0f 82 ed e8 ff ff    	jb     105cb4d <my.vm::run+0x161d>
 105e260:	e9 74 11 00 00       	jmp    105f3d9 <my.vm::run+0x3ea9>
 105e265:	4c 89 f9             	mov    %r15,%rcx
 105e268:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e26c:	48 21 d1             	and    %rdx,%rcx
 105e26f:	4c 01 f9             	add    %r15,%rcx
 105e272:	48 39 d1             	cmp    %rdx,%rcx
 105e275:	0f 82 3a e4 ff ff    	jb     105c6b5 <my.vm::run+0x1185>
 105e27b:	e9 20 11 00 00       	jmp    105f3a0 <my.vm::run+0x3e70>
 105e280:	49 8d 0c 31          	lea    (%r9,%rsi,1),%rcx
 105e284:	48 39 d1             	cmp    %rdx,%rcx
 105e287:	0f 82 bb ee ff ff    	jb     105d148 <my.vm::run+0x1c18>
 105e28d:	e9 02 11 00 00       	jmp    105f394 <my.vm::run+0x3e64>
 105e292:	48 8d 3c 0e          	lea    (%rsi,%rcx,1),%rdi
 105e296:	48 39 d7             	cmp    %rdx,%rdi
 105e299:	0f 82 1e f2 ff ff    	jb     105d4bd <my.vm::run+0x1f8d>
 105e29f:	e9 1c 10 00 00       	jmp    105f2c0 <my.vm::run+0x3d90>
 105e2a4:	4c 89 f9             	mov    %r15,%rcx
 105e2a7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e2ab:	48 21 d1             	and    %rdx,%rcx
 105e2ae:	4c 01 f9             	add    %r15,%rcx
 105e2b1:	48 39 d1             	cmp    %rdx,%rcx
 105e2b4:	0f 82 3d f5 ff ff    	jb     105d7f7 <my.vm::run+0x22c7>
 105e2ba:	e9 8f 11 00 00       	jmp    105f44e <my.vm::run+0x3f1e>
 105e2bf:	48 89 f0             	mov    %rsi,%rax
 105e2c2:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e2c6:	48 21 d0             	and    %rdx,%rax
 105e2c9:	48 01 f0             	add    %rsi,%rax
 105e2cc:	48 39 d0             	cmp    %rdx,%rax
 105e2cf:	0f 82 a4 d4 ff ff    	jb     105b779 <my.vm::run+0x249>
 105e2d5:	e9 83 11 00 00       	jmp    105f45d <my.vm::run+0x3f2d>
 105e2da:	4c 89 f9             	mov    %r15,%rcx
 105e2dd:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e2e1:	48 21 d1             	and    %rdx,%rcx
 105e2e4:	4c 01 f9             	add    %r15,%rcx
 105e2e7:	48 39 d1             	cmp    %rdx,%rcx
 105e2ea:	0f 82 49 e0 ff ff    	jb     105c339 <my.vm::run+0xe09>
 105e2f0:	e9 74 11 00 00       	jmp    105f469 <my.vm::run+0x3f39>
 105e2f5:	48 8b 4c 24 60       	mov    0x60(%rsp),%rcx
 105e2fa:	48 89 c8             	mov    %rcx,%rax
 105e2fd:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e301:	48 21 d0             	and    %rdx,%rax
 105e304:	48 01 c8             	add    %rcx,%rax
 105e307:	48 39 d0             	cmp    %rdx,%rax
 105e30a:	0f 82 37 e4 ff ff    	jb     105c747 <my.vm::run+0x1217>
 105e310:	e9 11 10 00 00       	jmp    105f326 <my.vm::run+0x3df6>
 105e315:	48 89 f0             	mov    %rsi,%rax
 105e318:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e31c:	48 21 d0             	and    %rdx,%rax
 105e31f:	48 01 f0             	add    %rsi,%rax
 105e322:	48 39 d0             	cmp    %rdx,%rax
 105e325:	0f 82 fa e6 ff ff    	jb     105ca25 <my.vm::run+0x14f5>
 105e32b:	e9 9c 0f 00 00       	jmp    105f2cc <my.vm::run+0x3d9c>
 105e330:	4c 89 f8             	mov    %r15,%rax
 105e333:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e337:	48 21 d0             	and    %rdx,%rax
 105e33a:	4c 01 f8             	add    %r15,%rax
 105e33d:	48 39 d0             	cmp    %rdx,%rax
 105e340:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105e345:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105e34a:	0f 82 80 fb ff ff    	jb     105ded0 <my.vm::run+0x29a0>
 105e350:	e9 83 0f 00 00       	jmp    105f2d8 <my.vm::run+0x3da8>
 105e355:	48 89 f1             	mov    %rsi,%rcx
 105e358:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e35c:	48 21 d1             	and    %rdx,%rcx
 105e35f:	48 01 f1             	add    %rsi,%rcx
 105e362:	48 39 d1             	cmp    %rdx,%rcx
 105e365:	0f 82 09 f2 ff ff    	jb     105d574 <my.vm::run+0x2044>
 105e36b:	e9 fa 0f 00 00       	jmp    105f36a <my.vm::run+0x3e3a>
 105e370:	be 20 00 00 00       	mov    $0x20,%esi
 105e375:	31 ff                	xor    %edi,%edi
 105e377:	e8 c4 51 fc ff       	call   1023540 <myl_core_list_new_slow>
 105e37c:	e9 66 d8 ff ff       	jmp    105bbe7 <my.vm::run+0x6b7>
 105e381:	48 89 d9             	mov    %rbx,%rcx
 105e384:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e388:	48 21 d1             	and    %rdx,%rcx
 105e38b:	48 01 d9             	add    %rbx,%rcx
 105e38e:	48 39 d1             	cmp    %rdx,%rcx
 105e391:	0f 82 6b d8 ff ff    	jb     105bc02 <my.vm::run+0x6d2>
 105e397:	e9 49 10 00 00       	jmp    105f3e5 <my.vm::run+0x3eb5>
 105e39c:	48 89 f1             	mov    %rsi,%rcx
 105e39f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e3a3:	48 21 d1             	and    %rdx,%rcx
 105e3a6:	48 01 f1             	add    %rsi,%rcx
 105e3a9:	48 39 d1             	cmp    %rdx,%rcx
 105e3ac:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105e3b1:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105e3b6:	4c 89 e5             	mov    %r12,%rbp
 105e3b9:	0f 82 d7 d8 ff ff    	jb     105bc96 <my.vm::run+0x766>
 105e3bf:	e9 96 0e 00 00       	jmp    105f25a <my.vm::run+0x3d2a>
 105e3c4:	4c 89 c1             	mov    %r8,%rcx
 105e3c7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e3cb:	48 21 d1             	and    %rdx,%rcx
 105e3ce:	4c 01 c1             	add    %r8,%rcx
 105e3d1:	48 39 d1             	cmp    %rdx,%rcx
 105e3d4:	0f 82 de e8 ff ff    	jb     105ccb8 <my.vm::run+0x1788>
 105e3da:	e9 15 10 00 00       	jmp    105f3f4 <my.vm::run+0x3ec4>
 105e3df:	48 89 f1             	mov    %rsi,%rcx
 105e3e2:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e3e6:	48 21 d1             	and    %rdx,%rcx
 105e3e9:	48 01 f1             	add    %rsi,%rcx
 105e3ec:	48 39 d1             	cmp    %rdx,%rcx
 105e3ef:	0f 82 6c d9 ff ff    	jb     105bd61 <my.vm::run+0x831>
 105e3f5:	e9 7e 10 00 00       	jmp    105f478 <my.vm::run+0x3f48>
 105e3fa:	48 89 f1             	mov    %rsi,%rcx
 105e3fd:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e401:	48 21 d1             	and    %rdx,%rcx
 105e404:	48 01 f1             	add    %rsi,%rcx
 105e407:	48 39 d1             	cmp    %rdx,%rcx
 105e40a:	0f 82 92 dd ff ff    	jb     105c1a2 <my.vm::run+0xc72>
 105e410:	e9 22 0f 00 00       	jmp    105f337 <my.vm::run+0x3e07>
 105e415:	48 89 f1             	mov    %rsi,%rcx
 105e418:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e41c:	48 21 d1             	and    %rdx,%rcx
 105e41f:	48 01 f1             	add    %rsi,%rcx
 105e422:	48 39 d1             	cmp    %rdx,%rcx
 105e425:	0f 82 4e ef ff ff    	jb     105d379 <my.vm::run+0x1e49>
 105e42b:	e9 d2 0e 00 00       	jmp    105f302 <my.vm::run+0x3dd2>
 105e430:	48 89 f0             	mov    %rsi,%rax
 105e433:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e437:	48 21 d0             	and    %rdx,%rax
 105e43a:	48 01 f0             	add    %rsi,%rax
 105e43d:	48 39 d0             	cmp    %rdx,%rax
 105e440:	0f 82 c2 d4 ff ff    	jb     105b908 <my.vm::run+0x3d8>
 105e446:	e9 b8 0f 00 00       	jmp    105f403 <my.vm::run+0x3ed3>
 105e44b:	48 89 f0             	mov    %rsi,%rax
 105e44e:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e452:	48 21 d0             	and    %rdx,%rax
 105e455:	48 01 f0             	add    %rsi,%rax
 105e458:	48 39 d0             	cmp    %rdx,%rax
 105e45b:	0f 82 82 f2 ff ff    	jb     105d6e3 <my.vm::run+0x21b3>
 105e461:	e9 a8 0e 00 00       	jmp    105f30e <my.vm::run+0x3dde>
 105e466:	48 89 e8             	mov    %rbp,%rax
 105e469:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e46d:	48 21 d0             	and    %rdx,%rax
 105e470:	48 01 e8             	add    %rbp,%rax
 105e473:	48 39 d0             	cmp    %rdx,%rax
 105e476:	0f 82 d9 d4 ff ff    	jb     105b955 <my.vm::run+0x425>
 105e47c:	e9 e5 0d 00 00       	jmp    105f266 <my.vm::run+0x3d36>
 105e481:	4c 89 ff             	mov    %r15,%rdi
 105e484:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e488:	48 21 c7             	and    %rax,%rdi
 105e48b:	4c 01 ff             	add    %r15,%rdi
 105e48e:	48 39 c7             	cmp    %rax,%rdi
 105e491:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 105e496:	0f 82 10 d5 ff ff    	jb     105b9ac <my.vm::run+0x47c>
 105e49c:	e9 0d 0e 00 00       	jmp    105f2ae <my.vm::run+0x3d7e>
 105e4a1:	4c 89 f8             	mov    %r15,%rax
 105e4a4:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e4a8:	48 21 d0             	and    %rdx,%rax
 105e4ab:	4c 01 f8             	add    %r15,%rax
 105e4ae:	48 39 d0             	cmp    %rdx,%rax
 105e4b1:	0f 82 6e d5 ff ff    	jb     105ba25 <my.vm::run+0x4f5>
 105e4b7:	e9 ba 0e 00 00       	jmp    105f376 <my.vm::run+0x3e46>
 105e4bc:	48 89 f1             	mov    %rsi,%rcx
 105e4bf:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e4c3:	48 21 d1             	and    %rdx,%rcx
 105e4c6:	48 01 f1             	add    %rsi,%rcx
 105e4c9:	48 39 d1             	cmp    %rdx,%rcx
 105e4cc:	0f 82 93 e8 ff ff    	jb     105cd65 <my.vm::run+0x1835>
 105e4d2:	e9 10 0e 00 00       	jmp    105f2e7 <my.vm::run+0x3db7>
 105e4d7:	48 89 f0             	mov    %rsi,%rax
 105e4da:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e4de:	48 21 d0             	and    %rdx,%rax
 105e4e1:	48 01 f0             	add    %rsi,%rax
 105e4e4:	48 39 d0             	cmp    %rdx,%rax
 105e4e7:	0f 82 98 f6 ff ff    	jb     105db85 <my.vm::run+0x2655>
 105e4ed:	e9 51 0e 00 00       	jmp    105f343 <my.vm::run+0x3e13>
 105e4f2:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e4f6:	48 21 d1             	and    %rdx,%rcx
 105e4f9:	4c 01 f9             	add    %r15,%rcx
 105e4fc:	48 39 d1             	cmp    %rdx,%rcx
 105e4ff:	0f 82 50 d9 ff ff    	jb     105be55 <my.vm::run+0x925>
 105e505:	e9 7b 0e 00 00       	jmp    105f385 <my.vm::run+0x3e55>
 105e50a:	48 89 f1             	mov    %rsi,%rcx
 105e50d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e511:	48 21 d1             	and    %rdx,%rcx
 105e514:	48 01 f1             	add    %rsi,%rcx
 105e517:	48 39 d1             	cmp    %rdx,%rcx
 105e51a:	0f 82 e0 f3 ff ff    	jb     105d900 <my.vm::run+0x23d0>
 105e520:	e9 50 0d 00 00       	jmp    105f275 <my.vm::run+0x3d45>
 105e525:	48 89 f1             	mov    %rsi,%rcx
 105e528:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e52c:	48 21 d1             	and    %rdx,%rcx
 105e52f:	48 01 f1             	add    %rsi,%rcx
 105e532:	48 39 d1             	cmp    %rdx,%rcx
 105e535:	49 89 d9             	mov    %rbx,%r9
 105e538:	4d 89 fb             	mov    %r15,%r11
 105e53b:	0f 82 9c e5 ff ff    	jb     105cadd <my.vm::run+0x15ad>
 105e541:	e9 3e 0f 00 00       	jmp    105f484 <my.vm::run+0x3f54>
 105e546:	48 89 f1             	mov    %rsi,%rcx
 105e549:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e54d:	48 21 d1             	and    %rdx,%rcx
 105e550:	48 01 f1             	add    %rsi,%rcx
 105e553:	48 39 d1             	cmp    %rdx,%rcx
 105e556:	0f 82 a3 e5 ff ff    	jb     105caff <my.vm::run+0x15cf>
 105e55c:	e9 59 0f 00 00       	jmp    105f4ba <my.vm::run+0x3f8a>
 105e561:	48 89 f1             	mov    %rsi,%rcx
 105e564:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e568:	48 21 d1             	and    %rdx,%rcx
 105e56b:	48 01 f1             	add    %rsi,%rcx
 105e56e:	48 39 d1             	cmp    %rdx,%rcx
 105e571:	0f 82 fb d9 ff ff    	jb     105bf72 <my.vm::run+0xa42>
 105e577:	e9 14 0f 00 00       	jmp    105f490 <my.vm::run+0x3f60>
 105e57c:	48 89 c1             	mov    %rax,%rcx
 105e57f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e583:	48 21 d1             	and    %rdx,%rcx
 105e586:	48 01 c1             	add    %rax,%rcx
 105e589:	48 39 d1             	cmp    %rdx,%rcx
 105e58c:	0f 82 f6 d9 ff ff    	jb     105bf88 <my.vm::run+0xa58>
 105e592:	e9 2f 0f 00 00       	jmp    105f4c6 <my.vm::run+0x3f96>
 105e597:	48 89 d9             	mov    %rbx,%rcx
 105e59a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e59e:	48 21 d1             	and    %rdx,%rcx
 105e5a1:	48 01 d9             	add    %rbx,%rcx
 105e5a4:	48 39 d1             	cmp    %rdx,%rcx
 105e5a7:	0f 82 8c da ff ff    	jb     105c039 <my.vm::run+0xb09>
 105e5ad:	e9 71 0f 00 00       	jmp    105f523 <my.vm::run+0x3ff3>
 105e5b2:	48 89 f1             	mov    %rsi,%rcx
 105e5b5:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e5b9:	48 21 c1             	and    %rax,%rcx
 105e5bc:	48 01 f1             	add    %rsi,%rcx
 105e5bf:	48 39 c1             	cmp    %rax,%rcx
 105e5c2:	0f 82 dd d1 ff ff    	jb     105b7a5 <my.vm::run+0x275>
 105e5c8:	e9 7d 0f 00 00       	jmp    105f54a <my.vm::run+0x401a>
 105e5cd:	49 89 f0             	mov    %rsi,%r8
 105e5d0:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e5d4:	49 21 c0             	and    %rax,%r8
 105e5d7:	49 01 f0             	add    %rsi,%r8
 105e5da:	49 39 c0             	cmp    %rax,%r8
 105e5dd:	0f 82 83 de ff ff    	jb     105c466 <my.vm::run+0xf36>
 105e5e3:	e9 ed 0e 00 00       	jmp    105f4d5 <my.vm::run+0x3fa5>
 105e5e8:	48 89 e9             	mov    %rbp,%rcx
 105e5eb:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e5ef:	48 21 d1             	and    %rdx,%rcx
 105e5f2:	48 01 e9             	add    %rbp,%rcx
 105e5f5:	48 39 d1             	cmp    %rdx,%rcx
 105e5f8:	0f 82 11 f1 ff ff    	jb     105d70f <my.vm::run+0x21df>
 105e5fe:	e9 f8 0f 00 00       	jmp    105f5fb <my.vm::run+0x40cb>
 105e603:	49 89 f0             	mov    %rsi,%r8
 105e606:	49 c1 f8 3f          	sar    $0x3f,%r8
 105e60a:	49 21 d0             	and    %rdx,%r8
 105e60d:	49 01 f0             	add    %rsi,%r8
 105e610:	49 39 d0             	cmp    %rdx,%r8
 105e613:	0f 82 f6 f4 ff ff    	jb     105db0f <my.vm::run+0x25df>
 105e619:	e9 14 0f 00 00       	jmp    105f532 <my.vm::run+0x4002>
 105e61e:	48 89 f0             	mov    %rsi,%rax
 105e621:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e625:	48 21 d0             	and    %rdx,%rax
 105e628:	48 01 f0             	add    %rsi,%rax
 105e62b:	48 39 d0             	cmp    %rdx,%rax
 105e62e:	0f 82 f3 f3 ff ff    	jb     105da27 <my.vm::run+0x24f7>
 105e634:	e9 05 0f 00 00       	jmp    105f53e <my.vm::run+0x400e>
 105e639:	48 89 d8             	mov    %rbx,%rax
 105e63c:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e640:	48 21 d0             	and    %rdx,%rax
 105e643:	48 01 d8             	add    %rbx,%rax
 105e646:	48 39 d0             	cmp    %rdx,%rax
 105e649:	0f 82 fa f3 ff ff    	jb     105da49 <my.vm::run+0x2519>
 105e64f:	e9 23 0f 00 00       	jmp    105f577 <my.vm::run+0x4047>
 105e654:	49 89 c3             	mov    %rax,%r11
 105e657:	49 c1 fb 3f          	sar    $0x3f,%r11
 105e65b:	49 21 cb             	and    %rcx,%r11
 105e65e:	49 01 c3             	add    %rax,%r11
 105e661:	49 39 cb             	cmp    %rcx,%r11
 105e664:	0f 82 1d eb ff ff    	jb     105d187 <my.vm::run+0x1c57>
 105e66a:	e9 93 0e 00 00       	jmp    105f502 <my.vm::run+0x3fd2>
 105e66f:	4c 89 f9             	mov    %r15,%rcx
 105e672:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e676:	48 21 d1             	and    %rdx,%rcx
 105e679:	4c 01 f9             	add    %r15,%rcx
 105e67c:	48 39 d1             	cmp    %rdx,%rcx
 105e67f:	0f 82 24 f6 ff ff    	jb     105dca9 <my.vm::run+0x2779>
 105e685:	e9 80 0f 00 00       	jmp    105f60a <my.vm::run+0x40da>
 105e68a:	4c 89 d0             	mov    %r10,%rax
 105e68d:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e691:	48 21 d0             	and    %rdx,%rax
 105e694:	4c 01 d0             	add    %r10,%rax
 105e697:	48 39 d0             	cmp    %rdx,%rax
 105e69a:	0f 82 20 d1 ff ff    	jb     105b7c0 <my.vm::run+0x290>
 105e6a0:	e9 2c 0f 00 00       	jmp    105f5d1 <my.vm::run+0x40a1>
 105e6a5:	4c 89 f0             	mov    %r14,%rax
 105e6a8:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e6ac:	48 21 d0             	and    %rdx,%rax
 105e6af:	4c 01 f0             	add    %r14,%rax
 105e6b2:	48 39 d0             	cmp    %rdx,%rax
 105e6b5:	0f 82 db e0 ff ff    	jb     105c796 <my.vm::run+0x1266>
 105e6bb:	e9 dc 0d 00 00       	jmp    105f49c <my.vm::run+0x3f6c>
 105e6c0:	4c 89 f0             	mov    %r14,%rax
 105e6c3:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e6c7:	48 21 d0             	and    %rdx,%rax
 105e6ca:	4c 01 f0             	add    %r14,%rax
 105e6cd:	48 39 d0             	cmp    %rdx,%rax
 105e6d0:	4d 89 ea             	mov    %r13,%r10
 105e6d3:	4c 89 fe             	mov    %r15,%rsi
 105e6d6:	4c 8b 44 24 18       	mov    0x18(%rsp),%r8
 105e6db:	0f 82 d9 f8 ff ff    	jb     105dfba <my.vm::run+0x2a8a>
 105e6e1:	e9 0d 0e 00 00       	jmp    105f4f3 <my.vm::run+0x3fc3>
 105e6e6:	4c 89 f8             	mov    %r15,%rax
 105e6e9:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e6ed:	48 21 d0             	and    %rdx,%rax
 105e6f0:	4c 01 f8             	add    %r15,%rax
 105e6f3:	48 39 d0             	cmp    %rdx,%rax
 105e6f6:	0f 82 3f f9 ff ff    	jb     105e03b <my.vm::run+0x2b0b>
 105e6fc:	e9 85 0e 00 00       	jmp    105f586 <my.vm::run+0x4056>
 105e701:	49 89 c3             	mov    %rax,%r11
 105e704:	49 c1 fb 3f          	sar    $0x3f,%r11
 105e708:	49 21 d3             	and    %rdx,%r11
 105e70b:	49 01 c3             	add    %rax,%r11
 105e70e:	49 39 d3             	cmp    %rdx,%r11
 105e711:	0f 82 98 ea ff ff    	jb     105d1af <my.vm::run+0x1c7f>
 105e717:	e9 3d 0e 00 00       	jmp    105f559 <my.vm::run+0x4029>
 105e71c:	4c 89 f9             	mov    %r15,%rcx
 105e71f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e723:	48 21 d1             	and    %rdx,%rcx
 105e726:	4c 01 f9             	add    %r15,%rcx
 105e729:	48 39 d1             	cmp    %rdx,%rcx
 105e72c:	0f 82 f3 e0 ff ff    	jb     105c825 <my.vm::run+0x12f5>
 105e732:	e9 31 0e 00 00       	jmp    105f568 <my.vm::run+0x4038>
 105e737:	4c 89 f1             	mov    %r14,%rcx
 105e73a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e73e:	48 21 d1             	and    %rdx,%rcx
 105e741:	4c 01 f1             	add    %r14,%rcx
 105e744:	48 39 d1             	cmp    %rdx,%rcx
 105e747:	0f 82 02 e1 ff ff    	jb     105c84f <my.vm::run+0x131f>
 105e74d:	e9 43 0e 00 00       	jmp    105f595 <my.vm::run+0x4065>
 105e752:	48 89 f1             	mov    %rsi,%rcx
 105e755:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e759:	48 21 c1             	and    %rax,%rcx
 105e75c:	48 01 f1             	add    %rsi,%rcx
 105e75f:	48 39 c1             	cmp    %rax,%rcx
 105e762:	0f 82 0e f0 ff ff    	jb     105d776 <my.vm::run+0x2246>
 105e768:	e9 a7 0d 00 00       	jmp    105f514 <my.vm::run+0x3fe4>
 105e76d:	48 89 f7             	mov    %rsi,%rdi
 105e770:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e774:	48 21 c7             	and    %rax,%rdi
 105e777:	48 01 f7             	add    %rsi,%rdi
 105e77a:	48 39 c7             	cmp    %rax,%rdi
 105e77d:	0f 82 5e e1 ff ff    	jb     105c8e1 <my.vm::run+0x13b1>
 105e783:	e9 5c 0d 00 00       	jmp    105f4e4 <my.vm::run+0x3fb4>
 105e788:	4c 89 f8             	mov    %r15,%rax
 105e78b:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e78f:	48 21 d0             	and    %rdx,%rax
 105e792:	4c 01 f8             	add    %r15,%rax
 105e795:	48 39 d0             	cmp    %rdx,%rax
 105e798:	4c 8d 6c 24 78       	lea    0x78(%rsp),%r13
 105e79d:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105e7a2:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 105e7a7:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 105e7ac:	0f 82 b4 e1 ff ff    	jb     105c966 <my.vm::run+0x1436>
 105e7b2:	e9 ed 0d 00 00       	jmp    105f5a4 <my.vm::run+0x4074>
 105e7b7:	4c 89 f8             	mov    %r15,%rax
 105e7ba:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e7be:	48 21 d0             	and    %rdx,%rax
 105e7c1:	4c 01 f8             	add    %r15,%rax
 105e7c4:	48 39 d0             	cmp    %rdx,%rax
 105e7c7:	0f 82 b8 e1 ff ff    	jb     105c985 <my.vm::run+0x1455>
 105e7cd:	e9 0e 0e 00 00       	jmp    105f5e0 <my.vm::run+0x40b0>
 105e7d2:	4d 89 c3             	mov    %r8,%r11
 105e7d5:	49 c1 fb 3f          	sar    $0x3f,%r11
 105e7d9:	49 21 cb             	and    %rcx,%r11
 105e7dc:	4d 01 c3             	add    %r8,%r11
 105e7df:	49 39 cb             	cmp    %rcx,%r11
 105e7e2:	0f 82 ea e9 ff ff    	jb     105d1d2 <my.vm::run+0x1ca2>
 105e7e8:	e9 c6 0d 00 00       	jmp    105f5b3 <my.vm::run+0x4083>
 105e7ed:	49 01 f1             	add    %rsi,%r9
 105e7f0:	49 39 d1             	cmp    %rdx,%r9
 105e7f3:	0f 82 fb e9 ff ff    	jb     105d1f4 <my.vm::run+0x1cc4>
 105e7f9:	e9 f1 0d 00 00       	jmp    105f5ef <my.vm::run+0x40bf>
 105e7fe:	48 89 c6             	mov    %rax,%rsi
 105e801:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e805:	48 21 d6             	and    %rdx,%rsi
 105e808:	48 01 c6             	add    %rax,%rsi
 105e80b:	48 39 d6             	cmp    %rdx,%rsi
 105e80e:	0f 82 03 ea ff ff    	jb     105d217 <my.vm::run+0x1ce7>
 105e814:	e9 92 0c 00 00       	jmp    105f4ab <my.vm::run+0x3f7b>
 105e819:	48 89 f7             	mov    %rsi,%rdi
 105e81c:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e820:	48 21 d7             	and    %rdx,%rdi
 105e823:	48 01 f7             	add    %rsi,%rdi
 105e826:	48 39 d7             	cmp    %rdx,%rdi
 105e829:	0f 82 51 ea ff ff    	jb     105d280 <my.vm::run+0x1d50>
 105e82f:	e9 91 0d 00 00       	jmp    105f5c5 <my.vm::run+0x4095>
 105e834:	4c 89 fe             	mov    %r15,%rsi
 105e837:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105e83b:	48 21 d6             	and    %rdx,%rsi
 105e83e:	4c 01 fe             	add    %r15,%rsi
 105e841:	48 39 d6             	cmp    %rdx,%rsi
 105e844:	0f 82 4e ea ff ff    	jb     105d298 <my.vm::run+0x1d68>
 105e84a:	48 8d 3d 2f 6e 02 00 	lea    0x26e2f(%rip),%rdi        # 1085680 <core_durable_error.verbs+0x4a70>
 105e851:	4c 89 fe             	mov    %r15,%rsi
 105e854:	e8 27 68 fc ff       	call   1025080 <myl_core_trap>
 105e859:	b9 02 00 00 00       	mov    $0x2,%ecx
 105e85e:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
 105e863:	48 89 08             	mov    %rcx,(%rax)
 105e866:	48 81 c4 f8 09 00 00 	add    $0x9f8,%rsp
 105e86d:	5b                   	pop    %rbx
 105e86e:	41 5c                	pop    %r12
 105e870:	41 5d                	pop    %r13
 105e872:	41 5e                	pop    %r14
 105e874:	41 5f                	pop    %r15
 105e876:	5d                   	pop    %rbp
 105e877:	c3                   	ret
 105e878:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105e87d:	48 8b 80 80 00 00 00 	mov    0x80(%rax),%rax
 105e884:	48 89 c6             	mov    %rax,%rsi
 105e887:	48 ff ce             	dec    %rsi
 105e88a:	0f 80 74 09 00 00    	jo     105f204 <my.vm::run+0x3cd4>
 105e890:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105e895:	48 89 b0 80 00 00 00 	mov    %rsi,0x80(%rax)
 105e89c:	48 8b 40 78          	mov    0x78(%rax),%rax
 105e8a0:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e8a4:	48 39 d6             	cmp    %rdx,%rsi
 105e8a7:	73 3a                	jae    105e8e3 <my.vm::run+0x33b3>
 105e8a9:	31 c9                	xor    %ecx,%ecx
 105e8ab:	eb b1                	jmp    105e85e <my.vm::run+0x332e>
 105e8ad:	48 89 f1             	mov    %rsi,%rcx
 105e8b0:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105e8b4:	48 21 d1             	and    %rdx,%rcx
 105e8b7:	48 01 f1             	add    %rsi,%rcx
 105e8ba:	48 39 d1             	cmp    %rdx,%rcx
 105e8bd:	0f 82 cb cc ff ff    	jb     105b58e <my.vm::run+0x5e>
 105e8c3:	48 8d 3d 36 27 02 00 	lea    0x22736(%rip),%rdi        # 1081000 <core_durable_error.verbs+0x3f0>
 105e8ca:	e8 b1 67 fc ff       	call   1025080 <myl_core_trap>
 105e8cf:	48 8d 3d fa 29 02 00 	lea    0x229fa(%rip),%rdi        # 10812d0 <core_durable_error.verbs+0x6c0>
 105e8d6:	ba 01 00 00 00       	mov    $0x1,%edx
 105e8db:	4c 89 f6             	mov    %r14,%rsi
 105e8de:	e8 9d 67 fc ff       	call   1025080 <myl_core_trap>
 105e8e3:	48 89 f0             	mov    %rsi,%rax
 105e8e6:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e8ea:	48 21 d0             	and    %rdx,%rax
 105e8ed:	48 01 f0             	add    %rsi,%rax
 105e8f0:	48 39 d0             	cmp    %rdx,%rax
 105e8f3:	72 b4                	jb     105e8a9 <my.vm::run+0x3379>
 105e8f5:	48 8d 3d 54 31 02 00 	lea    0x23154(%rip),%rdi        # 1081a50 <core_durable_error.verbs+0xe40>
 105e8fc:	e8 7f 67 fc ff       	call   1025080 <myl_core_trap>
 105e901:	83 f9 09             	cmp    $0x9,%ecx
 105e904:	0f 87 9e 06 00 00    	ja     105efa8 <my.vm::run+0x3a78>
 105e90a:	89 c8                	mov    %ecx,%eax
 105e90c:	48 8d 0d 2d 8b fa ff 	lea    -0x574d3(%rip),%rcx        # 1007440 <core_number_pairs+0x1e0>
 105e913:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105e917:	48 01 c8             	add    %rcx,%rax
 105e91a:	ff e0                	jmp    *%rax
 105e91c:	48 8d 3d 7d 74 02 00 	lea    0x2747d(%rip),%rdi        # 1085da0 <core_durable_error.verbs+0x5190>
 105e923:	e8 d8 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e928:	48 8d 3d 91 4b 02 00 	lea    0x24b91(%rip),%rdi        # 10834c0 <core_durable_error.verbs+0x28b0>
 105e92f:	e8 4c 67 fc ff       	call   1025080 <myl_core_trap>
 105e934:	48 8d 3d b5 4b 02 00 	lea    0x24bb5(%rip),%rdi        # 10834f0 <core_durable_error.verbs+0x28e0>
 105e93b:	e8 40 67 fc ff       	call   1025080 <myl_core_trap>
 105e940:	48 8d 3d d9 4b 02 00 	lea    0x24bd9(%rip),%rdi        # 1083520 <core_durable_error.verbs+0x2910>
 105e947:	e8 34 67 fc ff       	call   1025080 <myl_core_trap>
 105e94c:	48 8d 3d cd 45 02 00 	lea    0x245cd(%rip),%rdi        # 1082f20 <core_durable_error.verbs+0x2310>
 105e953:	ba 01 00 00 00       	mov    $0x1,%edx
 105e958:	48 89 c6             	mov    %rax,%rsi
 105e95b:	e8 20 67 fc ff       	call   1025080 <myl_core_trap>
 105e960:	83 f8 01             	cmp    $0x1,%eax
 105e963:	0f 84 eb 01 00 00    	je     105eb54 <my.vm::run+0x3624>
 105e969:	85 c0                	test   %eax,%eax
 105e96b:	0f 85 ef 01 00 00    	jne    105eb60 <my.vm::run+0x3630>
 105e971:	48 8d 3d 58 44 02 00 	lea    0x24458(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105e978:	e8 83 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e97d:	83 f8 01             	cmp    $0x1,%eax
 105e980:	0f 84 e6 01 00 00    	je     105eb6c <my.vm::run+0x363c>
 105e986:	85 c0                	test   %eax,%eax
 105e988:	0f 85 ea 01 00 00    	jne    105eb78 <my.vm::run+0x3648>
 105e98e:	48 8d 3d 3b 44 02 00 	lea    0x2443b(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105e995:	e8 66 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e99a:	83 f8 01             	cmp    $0x1,%eax
 105e99d:	0f 84 e1 01 00 00    	je     105eb84 <my.vm::run+0x3654>
 105e9a3:	85 c0                	test   %eax,%eax
 105e9a5:	0f 85 e5 01 00 00    	jne    105eb90 <my.vm::run+0x3660>
 105e9ab:	48 8d 3d 1e 44 02 00 	lea    0x2441e(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105e9b2:	e8 49 ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9b7:	83 f8 01             	cmp    $0x1,%eax
 105e9ba:	0f 84 f0 01 00 00    	je     105ebb0 <my.vm::run+0x3680>
 105e9c0:	85 c0                	test   %eax,%eax
 105e9c2:	0f 85 f4 01 00 00    	jne    105ebbc <my.vm::run+0x368c>
 105e9c8:	48 8d 3d 01 44 02 00 	lea    0x24401(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105e9cf:	e8 2c ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9d4:	83 f8 01             	cmp    $0x1,%eax
 105e9d7:	0f 84 eb 01 00 00    	je     105ebc8 <my.vm::run+0x3698>
 105e9dd:	85 c0                	test   %eax,%eax
 105e9df:	0f 85 ef 01 00 00    	jne    105ebd4 <my.vm::run+0x36a4>
 105e9e5:	48 8d 3d e4 43 02 00 	lea    0x243e4(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105e9ec:	e8 0f ba fc ff       	call   102a400 <myl_core_assert_fail>
 105e9f1:	83 f9 01             	cmp    $0x1,%ecx
 105e9f4:	0f 84 e6 01 00 00    	je     105ebe0 <my.vm::run+0x36b0>
 105e9fa:	85 c9                	test   %ecx,%ecx
 105e9fc:	0f 85 ea 01 00 00    	jne    105ebec <my.vm::run+0x36bc>
 105ea02:	48 8d 3d c7 43 02 00 	lea    0x243c7(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105ea09:	e8 f2 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea0e:	83 fa 01             	cmp    $0x1,%edx
 105ea11:	0f 84 e1 01 00 00    	je     105ebf8 <my.vm::run+0x36c8>
 105ea17:	85 d2                	test   %edx,%edx
 105ea19:	0f 85 f1 01 00 00    	jne    105ec10 <my.vm::run+0x36e0>
 105ea1f:	48 8d 3d aa 43 02 00 	lea    0x243aa(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105ea26:	e8 d5 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea2b:	83 f8 01             	cmp    $0x1,%eax
 105ea2e:	0f 84 d0 01 00 00    	je     105ec04 <my.vm::run+0x36d4>
 105ea34:	85 c0                	test   %eax,%eax
 105ea36:	0f 85 e0 01 00 00    	jne    105ec1c <my.vm::run+0x36ec>
 105ea3c:	48 8d 3d 8d 43 02 00 	lea    0x2438d(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105ea43:	e8 b8 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea48:	83 f8 01             	cmp    $0x1,%eax
 105ea4b:	0f 84 d7 01 00 00    	je     105ec28 <my.vm::run+0x36f8>
 105ea51:	85 c0                	test   %eax,%eax
 105ea53:	0f 85 db 01 00 00    	jne    105ec34 <my.vm::run+0x3704>
 105ea59:	48 8d 3d 70 43 02 00 	lea    0x24370(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105ea60:	e8 9b b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea65:	83 f8 01             	cmp    $0x1,%eax
 105ea68:	0f 84 d2 01 00 00    	je     105ec40 <my.vm::run+0x3710>
 105ea6e:	85 c0                	test   %eax,%eax
 105ea70:	0f 85 d6 01 00 00    	jne    105ec4c <my.vm::run+0x371c>
 105ea76:	48 8d 3d 53 43 02 00 	lea    0x24353(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105ea7d:	e8 7e b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea82:	83 fa 01             	cmp    $0x1,%edx
 105ea85:	0f 84 cd 01 00 00    	je     105ec58 <my.vm::run+0x3728>
 105ea8b:	85 d2                	test   %edx,%edx
 105ea8d:	0f 85 d1 01 00 00    	jne    105ec64 <my.vm::run+0x3734>
 105ea93:	48 8d 3d 36 43 02 00 	lea    0x24336(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105ea9a:	e8 61 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105ea9f:	83 f8 01             	cmp    $0x1,%eax
 105eaa2:	0f 84 c8 01 00 00    	je     105ec70 <my.vm::run+0x3740>
 105eaa8:	85 c0                	test   %eax,%eax
 105eaaa:	0f 85 cc 01 00 00    	jne    105ec7c <my.vm::run+0x374c>
 105eab0:	48 8d 3d 19 43 02 00 	lea    0x24319(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105eab7:	e8 44 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105eabc:	48 8d 3d bd 44 02 00 	lea    0x244bd(%rip),%rdi        # 1082f80 <core_durable_error.verbs+0x2370>
 105eac3:	ba 01 00 00 00       	mov    $0x1,%edx
 105eac8:	e8 b3 65 fc ff       	call   1025080 <myl_core_trap>
 105eacd:	83 f9 09             	cmp    $0x9,%ecx
 105ead0:	0f 87 cd 06 00 00    	ja     105f1a3 <my.vm::run+0x3c73>
 105ead6:	89 c8                	mov    %ecx,%eax
 105ead8:	48 8d 0d c1 89 fa ff 	lea    -0x5763f(%rip),%rcx        # 10074a0 <core_number_pairs+0x240>
 105eadf:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105eae3:	48 01 c8             	add    %rcx,%rax
 105eae6:	ff e0                	jmp    *%rax
 105eae8:	48 8d 3d 61 98 02 00 	lea    0x29861(%rip),%rdi        # 1088350 <core_durable_error.verbs+0x7740>
 105eaef:	e8 0c b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105eaf4:	48 8d 3d d5 72 02 00 	lea    0x272d5(%rip),%rdi        # 1085dd0 <core_durable_error.verbs+0x51c0>
 105eafb:	e8 00 b9 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb00:	48 8d 3d 89 73 02 00 	lea    0x27389(%rip),%rdi        # 1085e90 <core_durable_error.verbs+0x5280>
 105eb07:	e8 f4 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb0c:	48 8d 3d ed 72 02 00 	lea    0x272ed(%rip),%rdi        # 1085e00 <core_durable_error.verbs+0x51f0>
 105eb13:	e8 e8 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb18:	48 8d 3d 11 73 02 00 	lea    0x27311(%rip),%rdi        # 1085e30 <core_durable_error.verbs+0x5220>
 105eb1f:	e8 dc b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb24:	48 8d 3d 35 73 02 00 	lea    0x27335(%rip),%rdi        # 1085e60 <core_durable_error.verbs+0x5250>
 105eb2b:	e8 d0 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb30:	48 8d 3d 89 73 02 00 	lea    0x27389(%rip),%rdi        # 1085ec0 <core_durable_error.verbs+0x52b0>
 105eb37:	e8 c4 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb3c:	48 8d 3d ad 73 02 00 	lea    0x273ad(%rip),%rdi        # 1085ef0 <core_durable_error.verbs+0x52e0>
 105eb43:	e8 b8 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb48:	48 8d 3d d1 73 02 00 	lea    0x273d1(%rip),%rdi        # 1085f20 <core_durable_error.verbs+0x5310>
 105eb4f:	e8 ac b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb54:	48 8d 3d a5 42 02 00 	lea    0x242a5(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105eb5b:	e8 a0 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb60:	48 8d 3d c9 42 02 00 	lea    0x242c9(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105eb67:	e8 94 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb6c:	48 8d 3d 8d 42 02 00 	lea    0x2428d(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105eb73:	e8 88 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb78:	48 8d 3d b1 42 02 00 	lea    0x242b1(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105eb7f:	e8 7c b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb84:	48 8d 3d 75 42 02 00 	lea    0x24275(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105eb8b:	e8 70 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb90:	48 8d 3d 99 42 02 00 	lea    0x24299(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105eb97:	e8 64 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105eb9c:	48 8d 3d 3d 3e 02 00 	lea    0x23e3d(%rip),%rdi        # 10829e0 <core_durable_error.verbs+0x1dd0>
 105eba3:	ba 01 00 00 00       	mov    $0x1,%edx
 105eba8:	48 89 c6             	mov    %rax,%rsi
 105ebab:	e8 d0 64 fc ff       	call   1025080 <myl_core_trap>
 105ebb0:	48 8d 3d 49 42 02 00 	lea    0x24249(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105ebb7:	e8 44 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105ebbc:	48 8d 3d 6d 42 02 00 	lea    0x2426d(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105ebc3:	e8 38 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105ebc8:	48 8d 3d 31 42 02 00 	lea    0x24231(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105ebcf:	e8 2c b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105ebd4:	48 8d 3d 55 42 02 00 	lea    0x24255(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105ebdb:	e8 20 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105ebe0:	48 8d 3d 19 42 02 00 	lea    0x24219(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105ebe7:	e8 14 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105ebec:	48 8d 3d 3d 42 02 00 	lea    0x2423d(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105ebf3:	e8 08 b8 fc ff       	call   102a400 <myl_core_assert_fail>
 105ebf8:	48 8d 3d 01 42 02 00 	lea    0x24201(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105ebff:	e8 fc b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec04:	48 8d 3d f5 41 02 00 	lea    0x241f5(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105ec0b:	e8 f0 b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec10:	48 8d 3d 19 42 02 00 	lea    0x24219(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105ec17:	e8 e4 b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec1c:	48 8d 3d 0d 42 02 00 	lea    0x2420d(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105ec23:	e8 d8 b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec28:	48 8d 3d d1 41 02 00 	lea    0x241d1(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105ec2f:	e8 cc b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec34:	48 8d 3d f5 41 02 00 	lea    0x241f5(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105ec3b:	e8 c0 b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec40:	48 8d 3d b9 41 02 00 	lea    0x241b9(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105ec47:	e8 b4 b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec4c:	48 8d 3d dd 41 02 00 	lea    0x241dd(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105ec53:	e8 a8 b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec58:	48 8d 3d a1 41 02 00 	lea    0x241a1(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105ec5f:	e8 9c b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec64:	48 8d 3d c5 41 02 00 	lea    0x241c5(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105ec6b:	e8 90 b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec70:	48 8d 3d 89 41 02 00 	lea    0x24189(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105ec77:	e8 84 b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec7c:	48 8d 3d ad 41 02 00 	lea    0x241ad(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105ec83:	e8 78 b7 fc ff       	call   102a400 <myl_core_assert_fail>
 105ec88:	48 8d 3d 31 2d 02 00 	lea    0x22d31(%rip),%rdi        # 10819c0 <core_durable_error.verbs+0xdb0>
 105ec8f:	ba 01 00 00 00       	mov    $0x1,%edx
 105ec94:	4c 89 fe             	mov    %r15,%rsi
 105ec97:	e8 e4 63 fc ff       	call   1025080 <myl_core_trap>
 105ec9c:	48 8d 3d 5d 44 02 00 	lea    0x2445d(%rip),%rdi        # 1083100 <core_durable_error.verbs+0x24f0>
 105eca3:	ba 01 00 00 00       	mov    $0x1,%edx
 105eca8:	e8 d3 63 fc ff       	call   1025080 <myl_core_trap>
 105ecad:	48 8d 3d cc 27 02 00 	lea    0x227cc(%rip),%rdi        # 1081480 <core_durable_error.verbs+0x870>
 105ecb4:	ba 01 00 00 00       	mov    $0x1,%edx
 105ecb9:	4c 89 fe             	mov    %r15,%rsi
 105ecbc:	e8 bf 63 fc ff       	call   1025080 <myl_core_trap>
 105ecc1:	48 8d 3d 48 2e 02 00 	lea    0x22e48(%rip),%rdi        # 1081b10 <core_durable_error.verbs+0xf00>
 105ecc8:	ba 01 00 00 00       	mov    $0x1,%edx
 105eccd:	e8 ae 63 fc ff       	call   1025080 <myl_core_trap>
 105ecd2:	48 8d 3d 67 2e 02 00 	lea    0x22e67(%rip),%rdi        # 1081b40 <core_durable_error.verbs+0xf30>
 105ecd9:	ba 01 00 00 00       	mov    $0x1,%edx
 105ecde:	e8 9d 63 fc ff       	call   1025080 <myl_core_trap>
 105ece3:	48 8d 3d 76 29 02 00 	lea    0x22976(%rip),%rdi        # 1081660 <core_durable_error.verbs+0xa50>
 105ecea:	ba 01 00 00 00       	mov    $0x1,%edx
 105ecef:	4c 89 fe             	mov    %r15,%rsi
 105ecf2:	e8 89 63 fc ff       	call   1025080 <myl_core_trap>
 105ecf7:	48 8d 3d a2 49 02 00 	lea    0x249a2(%rip),%rdi        # 10836a0 <core_durable_error.verbs+0x2a90>
 105ecfe:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed03:	4c 89 d6             	mov    %r10,%rsi
 105ed06:	e8 75 63 fc ff       	call   1025080 <myl_core_trap>
 105ed0b:	48 8d 3d 4e 47 02 00 	lea    0x2474e(%rip),%rdi        # 1083460 <core_durable_error.verbs+0x2850>
 105ed12:	48 89 c6             	mov    %rax,%rsi
 105ed15:	4c 89 e2             	mov    %r12,%rdx
 105ed18:	e8 63 63 fc ff       	call   1025080 <myl_core_trap>
 105ed1d:	48 8d 3d dc 28 02 00 	lea    0x228dc(%rip),%rdi        # 1081600 <core_durable_error.verbs+0x9f0>
 105ed24:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed29:	4c 89 fe             	mov    %r15,%rsi
 105ed2c:	e8 4f 63 fc ff       	call   1025080 <myl_core_trap>
 105ed31:	48 8d 3d 38 49 02 00 	lea    0x24938(%rip),%rdi        # 1083670 <core_durable_error.verbs+0x2a60>
 105ed38:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed3d:	e8 3e 63 fc ff       	call   1025080 <myl_core_trap>
 105ed42:	48 8d 3d e7 46 02 00 	lea    0x246e7(%rip),%rdi        # 1083430 <core_durable_error.verbs+0x2820>
 105ed49:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed4e:	4c 89 fe             	mov    %r15,%rsi
 105ed51:	e8 2a 63 fc ff       	call   1025080 <myl_core_trap>
 105ed56:	48 8d 3d 03 4a 02 00 	lea    0x24a03(%rip),%rdi        # 1083760 <core_durable_error.verbs+0x2b50>
 105ed5d:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed62:	e8 19 63 fc ff       	call   1025080 <myl_core_trap>
 105ed67:	48 8d 3d 22 4a 02 00 	lea    0x24a22(%rip),%rdi        # 1083790 <core_durable_error.verbs+0x2b80>
 105ed6e:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed73:	48 89 ee             	mov    %rbp,%rsi
 105ed76:	e8 05 63 fc ff       	call   1025080 <myl_core_trap>
 105ed7b:	48 8d 3d 3e 26 02 00 	lea    0x2263e(%rip),%rdi        # 10813c0 <core_durable_error.verbs+0x7b0>
 105ed82:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed87:	4c 89 fe             	mov    %r15,%rsi
 105ed8a:	e8 f1 62 fc ff       	call   1025080 <myl_core_trap>
 105ed8f:	48 8d 3d 2a 23 02 00 	lea    0x2232a(%rip),%rdi        # 10810c0 <core_durable_error.verbs+0x4b0>
 105ed96:	e8 e5 62 fc ff       	call   1025080 <myl_core_trap>
 105ed9b:	48 8d 3d 2e 2b 02 00 	lea    0x22b2e(%rip),%rdi        # 10818d0 <core_durable_error.verbs+0xcc0>
 105eda2:	ba 01 00 00 00       	mov    $0x1,%edx
 105eda7:	4c 89 fe             	mov    %r15,%rsi
 105edaa:	e8 d1 62 fc ff       	call   1025080 <myl_core_trap>
 105edaf:	48 8d 3d 8a 2a 02 00 	lea    0x22a8a(%rip),%rdi        # 1081840 <core_durable_error.verbs+0xc30>
 105edb6:	ba 01 00 00 00       	mov    $0x1,%edx
 105edbb:	4c 89 fe             	mov    %r15,%rsi
 105edbe:	e8 bd 62 fc ff       	call   1025080 <myl_core_trap>
 105edc3:	48 8d 3d a6 2a 02 00 	lea    0x22aa6(%rip),%rdi        # 1081870 <core_durable_error.verbs+0xc60>
 105edca:	48 89 c6             	mov    %rax,%rsi
 105edcd:	4c 89 ca             	mov    %r9,%rdx
 105edd0:	e8 ab 62 fc ff       	call   1025080 <myl_core_trap>
 105edd5:	48 8d 3d d4 47 02 00 	lea    0x247d4(%rip),%rdi        # 10835b0 <core_durable_error.verbs+0x29a0>
 105eddc:	ba 01 00 00 00       	mov    $0x1,%edx
 105ede1:	e8 9a 62 fc ff       	call   1025080 <myl_core_trap>
 105ede6:	48 8d 3d 93 29 02 00 	lea    0x22993(%rip),%rdi        # 1081780 <core_durable_error.verbs+0xb70>
 105eded:	ba 01 00 00 00       	mov    $0x1,%edx
 105edf2:	4c 89 fe             	mov    %r15,%rsi
 105edf5:	e8 86 62 fc ff       	call   1025080 <myl_core_trap>
 105edfa:	48 8d 3d 5f 25 02 00 	lea    0x2255f(%rip),%rdi        # 1081360 <core_durable_error.verbs+0x750>
 105ee01:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee06:	4c 89 fe             	mov    %r15,%rsi
 105ee09:	e8 72 62 fc ff       	call   1025080 <myl_core_trap>
 105ee0e:	48 8d 3d 1b 22 02 00 	lea    0x2221b(%rip),%rdi        # 1081030 <core_durable_error.verbs+0x420>
 105ee15:	4c 89 ce             	mov    %r9,%rsi
 105ee18:	e8 63 62 fc ff       	call   1025080 <myl_core_trap>
 105ee1d:	48 8d 3d bc 41 02 00 	lea    0x241bc(%rip),%rdi        # 1082fe0 <core_durable_error.verbs+0x23d0>
 105ee24:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee29:	48 89 c6             	mov    %rax,%rsi
 105ee2c:	e8 4f 62 fc ff       	call   1025080 <myl_core_trap>
 105ee31:	48 8d 3d 08 27 02 00 	lea    0x22708(%rip),%rdi        # 1081540 <core_durable_error.verbs+0x930>
 105ee38:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee3d:	4c 89 fe             	mov    %r15,%rsi
 105ee40:	e8 3b 62 fc ff       	call   1025080 <myl_core_trap>
 105ee45:	48 8d 3d e4 2a 02 00 	lea    0x22ae4(%rip),%rdi        # 1081930 <core_durable_error.verbs+0xd20>
 105ee4c:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee51:	e8 2a 62 fc ff       	call   1025080 <myl_core_trap>
 105ee56:	48 8d 3d 13 27 02 00 	lea    0x22713(%rip),%rdi        # 1081570 <core_durable_error.verbs+0x960>
 105ee5d:	4c 89 ce             	mov    %r9,%rsi
 105ee60:	48 89 c2             	mov    %rax,%rdx
 105ee63:	e8 18 62 fc ff       	call   1025080 <myl_core_trap>
 105ee68:	48 8d 3d 01 24 02 00 	lea    0x22401(%rip),%rdi        # 1081270 <core_durable_error.verbs+0x660>
 105ee6f:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee74:	4c 89 fe             	mov    %r15,%rsi
 105ee77:	e8 04 62 fc ff       	call   1025080 <myl_core_trap>
 105ee7c:	48 8d 3d 1d 27 02 00 	lea    0x2271d(%rip),%rdi        # 10815a0 <core_durable_error.verbs+0x990>
 105ee83:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee88:	4c 89 fe             	mov    %r15,%rsi
 105ee8b:	e8 f0 61 fc ff       	call   1025080 <myl_core_trap>
 105ee90:	48 8d 3d 89 25 02 00 	lea    0x22589(%rip),%rdi        # 1081420 <core_durable_error.verbs+0x810>
 105ee97:	ba 01 00 00 00       	mov    $0x1,%edx
 105ee9c:	4c 89 fe             	mov    %r15,%rsi
 105ee9f:	e8 dc 61 fc ff       	call   1025080 <myl_core_trap>
 105eea4:	48 8d 3d a5 3d 02 00 	lea    0x23da5(%rip),%rdi        # 1082c50 <core_durable_error.verbs+0x2040>
 105eeab:	ba 01 00 00 00       	mov    $0x1,%edx
 105eeb0:	e8 cb 61 fc ff       	call   1025080 <myl_core_trap>
 105eeb5:	48 8d 3d e4 2c 02 00 	lea    0x22ce4(%rip),%rdi        # 1081ba0 <core_durable_error.verbs+0xf90>
 105eebc:	ba 01 00 00 00       	mov    $0x1,%edx
 105eec1:	e8 ba 61 fc ff       	call   1025080 <myl_core_trap>
 105eec6:	48 8d 3d 13 29 02 00 	lea    0x22913(%rip),%rdi        # 10817e0 <core_durable_error.verbs+0xbd0>
 105eecd:	ba 01 00 00 00       	mov    $0x1,%edx
 105eed2:	4c 89 fe             	mov    %r15,%rsi
 105eed5:	e8 a6 61 fc ff       	call   1025080 <myl_core_trap>
 105eeda:	48 8d 3d cf 25 02 00 	lea    0x225cf(%rip),%rdi        # 10814b0 <core_durable_error.verbs+0x8a0>
 105eee1:	ba 01 00 00 00       	mov    $0x1,%edx
 105eee6:	4c 89 fe             	mov    %r15,%rsi
 105eee9:	e8 92 61 fc ff       	call   1025080 <myl_core_trap>
 105eeee:	48 8d 3d 2b 28 02 00 	lea    0x2282b(%rip),%rdi        # 1081720 <core_durable_error.verbs+0xb10>
 105eef5:	ba 01 00 00 00       	mov    $0x1,%edx
 105eefa:	4c 89 fe             	mov    %r15,%rsi
 105eefd:	e8 7e 61 fc ff       	call   1025080 <myl_core_trap>
 105ef02:	48 8d 3d 17 22 02 00 	lea    0x22217(%rip),%rdi        # 1081120 <core_durable_error.verbs+0x510>
 105ef09:	e8 72 61 fc ff       	call   1025080 <myl_core_trap>
 105ef0e:	48 8d 3d cb 3d 02 00 	lea    0x23dcb(%rip),%rdi        # 1082ce0 <core_durable_error.verbs+0x20d0>
 105ef15:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef1a:	4c 89 fe             	mov    %r15,%rsi
 105ef1d:	e8 5e 61 fc ff       	call   1025080 <myl_core_trap>
 105ef22:	48 8d 3d 67 2a 02 00 	lea    0x22a67(%rip),%rdi        # 1081990 <core_durable_error.verbs+0xd80>
 105ef29:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef2e:	e8 4d 61 fc ff       	call   1025080 <myl_core_trap>
 105ef33:	48 8d 3d 86 27 02 00 	lea    0x22786(%rip),%rdi        # 10816c0 <core_durable_error.verbs+0xab0>
 105ef3a:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef3f:	4c 89 fe             	mov    %r15,%rsi
 105ef42:	e8 39 61 fc ff       	call   1025080 <myl_core_trap>
 105ef47:	48 8d 3d 62 3d 02 00 	lea    0x23d62(%rip),%rdi        # 1082cb0 <core_durable_error.verbs+0x20a0>
 105ef4e:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef53:	e8 28 61 fc ff       	call   1025080 <myl_core_trap>
 105ef58:	48 8d 3d 21 2b 02 00 	lea    0x22b21(%rip),%rdi        # 1081a80 <core_durable_error.verbs+0xe70>
 105ef5f:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef64:	4c 89 f6             	mov    %r14,%rsi
 105ef67:	e8 14 61 fc ff       	call   1025080 <myl_core_trap>
 105ef6c:	48 8d 3d dd 21 02 00 	lea    0x221dd(%rip),%rdi        # 1081150 <core_durable_error.verbs+0x540>
 105ef73:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef78:	4c 89 f6             	mov    %r14,%rsi
 105ef7b:	e8 00 61 fc ff       	call   1025080 <myl_core_trap>
 105ef80:	48 8d 3d 89 22 02 00 	lea    0x22289(%rip),%rdi        # 1081210 <core_durable_error.verbs+0x600>
 105ef87:	ba 01 00 00 00       	mov    $0x1,%edx
 105ef8c:	4c 89 f6             	mov    %r14,%rsi
 105ef8f:	e8 ec 60 fc ff       	call   1025080 <myl_core_trap>
 105ef94:	48 8d 3d 15 22 02 00 	lea    0x22215(%rip),%rdi        # 10811b0 <core_durable_error.verbs+0x5a0>
 105ef9b:	ba 01 00 00 00       	mov    $0x1,%edx
 105efa0:	4c 89 f6             	mov    %r14,%rsi
 105efa3:	e8 d8 60 fc ff       	call   1025080 <myl_core_trap>
 105efa8:	48 8d 3d a1 6f 02 00 	lea    0x26fa1(%rip),%rdi        # 1085f50 <core_durable_error.verbs+0x5340>
 105efaf:	e8 4c b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105efb4:	83 f9 01             	cmp    $0x1,%ecx
 105efb7:	0f 84 dd 00 00 00    	je     105f09a <my.vm::run+0x3b6a>
 105efbd:	85 c9                	test   %ecx,%ecx
 105efbf:	0f 85 e1 00 00 00    	jne    105f0a6 <my.vm::run+0x3b76>
 105efc5:	48 8d 3d 04 3e 02 00 	lea    0x23e04(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105efcc:	e8 2f b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105efd1:	83 f8 01             	cmp    $0x1,%eax
 105efd4:	0f 84 d8 00 00 00    	je     105f0b2 <my.vm::run+0x3b82>
 105efda:	85 c0                	test   %eax,%eax
 105efdc:	0f 85 dc 00 00 00    	jne    105f0be <my.vm::run+0x3b8e>
 105efe2:	48 8d 3d e7 3d 02 00 	lea    0x23de7(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105efe9:	e8 12 b4 fc ff       	call   102a400 <myl_core_assert_fail>
 105efee:	48 8d 3d 9b 3b 02 00 	lea    0x23b9b(%rip),%rdi        # 1082b90 <core_durable_error.verbs+0x1f80>
 105eff5:	ba 01 00 00 00       	mov    $0x1,%edx
 105effa:	48 89 ce             	mov    %rcx,%rsi
 105effd:	e8 7e 60 fc ff       	call   1025080 <myl_core_trap>
 105f002:	48 8d 3d f7 3a 02 00 	lea    0x23af7(%rip),%rdi        # 1082b00 <core_durable_error.verbs+0x1ef0>
 105f009:	ba 01 00 00 00       	mov    $0x1,%edx
 105f00e:	e8 6d 60 fc ff       	call   1025080 <myl_core_trap>
 105f013:	48 8d 3d d6 20 02 00 	lea    0x220d6(%rip),%rdi        # 10810f0 <core_durable_error.verbs+0x4e0>
 105f01a:	4c 89 e6             	mov    %r12,%rsi
 105f01d:	e8 5e 60 fc ff       	call   1025080 <myl_core_trap>
 105f022:	48 8d 3d 87 39 02 00 	lea    0x23987(%rip),%rdi        # 10829b0 <core_durable_error.verbs+0x1da0>
 105f029:	ba 01 00 00 00       	mov    $0x1,%edx
 105f02e:	e8 4d 60 fc ff       	call   1025080 <myl_core_trap>
 105f033:	48 8d 3d 96 1f 02 00 	lea    0x21f96(%rip),%rdi        # 1080fd0 <core_durable_error.verbs+0x3c0>
 105f03a:	ba 01 00 00 00       	mov    $0x1,%edx
 105f03f:	4c 89 f6             	mov    %r14,%rsi
 105f042:	e8 39 60 fc ff       	call   1025080 <myl_core_trap>
 105f047:	48 8d 3d a2 3b 02 00 	lea    0x23ba2(%rip),%rdi        # 1082bf0 <core_durable_error.verbs+0x1fe0>
 105f04e:	ba 01 00 00 00       	mov    $0x1,%edx
 105f053:	48 89 ce             	mov    %rcx,%rsi
 105f056:	e8 25 60 fc ff       	call   1025080 <myl_core_trap>
 105f05b:	83 f8 01             	cmp    $0x1,%eax
 105f05e:	0f 84 27 01 00 00    	je     105f18b <my.vm::run+0x3c5b>
 105f064:	85 c0                	test   %eax,%eax
 105f066:	0f 85 2b 01 00 00    	jne    105f197 <my.vm::run+0x3c67>
 105f06c:	48 8d 3d 5d 3d 02 00 	lea    0x23d5d(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105f073:	e8 88 b3 fc ff       	call   102a400 <myl_core_assert_fail>
 105f078:	48 8d 3d 21 3a 02 00 	lea    0x23a21(%rip),%rdi        # 1082aa0 <core_durable_error.verbs+0x1e90>
 105f07f:	ba 01 00 00 00       	mov    $0x1,%edx
 105f084:	e8 f7 5f fc ff       	call   1025080 <myl_core_trap>
 105f089:	48 8d 3d 10 40 02 00 	lea    0x24010(%rip),%rdi        # 10830a0 <core_durable_error.verbs+0x2490>
 105f090:	ba 01 00 00 00       	mov    $0x1,%edx
 105f095:	e8 e6 5f fc ff       	call   1025080 <myl_core_trap>
 105f09a:	48 8d 3d 5f 3d 02 00 	lea    0x23d5f(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105f0a1:	e8 5a b3 fc ff       	call   102a400 <myl_core_assert_fail>
 105f0a6:	48 8d 3d 83 3d 02 00 	lea    0x23d83(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105f0ad:	e8 4e b3 fc ff       	call   102a400 <myl_core_assert_fail>
 105f0b2:	48 8d 3d 47 3d 02 00 	lea    0x23d47(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105f0b9:	e8 42 b3 fc ff       	call   102a400 <myl_core_assert_fail>
 105f0be:	48 8d 3d 6b 3d 02 00 	lea    0x23d6b(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105f0c5:	e8 36 b3 fc ff       	call   102a400 <myl_core_assert_fail>
 105f0ca:	48 8d 3d 6f 3f 02 00 	lea    0x23f6f(%rip),%rdi        # 1083040 <core_durable_error.verbs+0x2430>
 105f0d1:	ba 01 00 00 00       	mov    $0x1,%edx
 105f0d6:	e8 a5 5f fc ff       	call   1025080 <myl_core_trap>
 105f0db:	48 8d 3d 9e 92 02 00 	lea    0x2929e(%rip),%rdi        # 1088380 <core_durable_error.verbs+0x7770>
 105f0e2:	e8 19 b3 fc ff       	call   102a400 <myl_core_assert_fail>
 105f0e7:	48 8d 3d c2 92 02 00 	lea    0x292c2(%rip),%rdi        # 10883b0 <core_durable_error.verbs+0x77a0>
 105f0ee:	e8 0d b3 fc ff       	call   102a400 <myl_core_assert_fail>
 105f0f3:	48 8d 3d e6 92 02 00 	lea    0x292e6(%rip),%rdi        # 10883e0 <core_durable_error.verbs+0x77d0>
 105f0fa:	e8 01 b3 fc ff       	call   102a400 <myl_core_assert_fail>
 105f0ff:	48 8d 3d 0a 93 02 00 	lea    0x2930a(%rip),%rdi        # 1088410 <core_durable_error.verbs+0x7800>
 105f106:	e8 f5 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f10b:	48 8d 3d 2e 93 02 00 	lea    0x2932e(%rip),%rdi        # 1088440 <core_durable_error.verbs+0x7830>
 105f112:	e8 e9 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f117:	48 8d 3d 52 93 02 00 	lea    0x29352(%rip),%rdi        # 1088470 <core_durable_error.verbs+0x7860>
 105f11e:	e8 dd b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f123:	48 8d 3d 76 93 02 00 	lea    0x29376(%rip),%rdi        # 10884a0 <core_durable_error.verbs+0x7890>
 105f12a:	e8 d1 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f12f:	48 8d 3d 9a 93 02 00 	lea    0x2939a(%rip),%rdi        # 10884d0 <core_durable_error.verbs+0x78c0>
 105f136:	e8 c5 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f13b:	48 8d 3d 8e 42 02 00 	lea    0x2428e(%rip),%rdi        # 10833d0 <core_durable_error.verbs+0x27c0>
 105f142:	ba 01 00 00 00       	mov    $0x1,%edx
 105f147:	48 89 c6             	mov    %rax,%rsi
 105f14a:	e8 31 5f fc ff       	call   1025080 <myl_core_trap>
 105f14f:	48 8d 3d 4a 42 02 00 	lea    0x2424a(%rip),%rdi        # 10833a0 <core_durable_error.verbs+0x2790>
 105f156:	4c 89 fe             	mov    %r15,%rsi
 105f159:	4c 89 e2             	mov    %r12,%rdx
 105f15c:	e8 1f 5f fc ff       	call   1025080 <myl_core_trap>
 105f161:	83 f9 01             	cmp    $0x1,%ecx
 105f164:	74 6e                	je     105f1d4 <my.vm::run+0x3ca4>
 105f166:	85 c9                	test   %ecx,%ecx
 105f168:	75 76                	jne    105f1e0 <my.vm::run+0x3cb0>
 105f16a:	48 8d 3d 5f 3c 02 00 	lea    0x23c5f(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105f171:	e8 8a b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f176:	83 f8 01             	cmp    $0x1,%eax
 105f179:	74 71                	je     105f1ec <my.vm::run+0x3cbc>
 105f17b:	85 c0                	test   %eax,%eax
 105f17d:	75 79                	jne    105f1f8 <my.vm::run+0x3cc8>
 105f17f:	48 8d 3d 4a 3c 02 00 	lea    0x23c4a(%rip),%rdi        # 1082dd0 <core_durable_error.verbs+0x21c0>
 105f186:	e8 75 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f18b:	48 8d 3d 6e 3c 02 00 	lea    0x23c6e(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105f192:	e8 69 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f197:	48 8d 3d 92 3c 02 00 	lea    0x23c92(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105f19e:	e8 5d b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f1a3:	48 8d 3d 56 93 02 00 	lea    0x29356(%rip),%rdi        # 1088500 <core_durable_error.verbs+0x78f0>
 105f1aa:	e8 51 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f1af:	48 8d 3d 9a 64 02 00 	lea    0x2649a(%rip),%rdi        # 1085650 <core_durable_error.verbs+0x4a40>
 105f1b6:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1bb:	e8 c0 5e fc ff       	call   1025080 <myl_core_trap>
 105f1c0:	48 8d 3d 29 64 02 00 	lea    0x26429(%rip),%rdi        # 10855f0 <core_durable_error.verbs+0x49e0>
 105f1c7:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1cc:	48 89 c6             	mov    %rax,%rsi
 105f1cf:	e8 ac 5e fc ff       	call   1025080 <myl_core_trap>
 105f1d4:	48 8d 3d 25 3c 02 00 	lea    0x23c25(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105f1db:	e8 20 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f1e0:	48 8d 3d 49 3c 02 00 	lea    0x23c49(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105f1e7:	e8 14 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f1ec:	48 8d 3d 0d 3c 02 00 	lea    0x23c0d(%rip),%rdi        # 1082e00 <core_durable_error.verbs+0x21f0>
 105f1f3:	e8 08 b2 fc ff       	call   102a400 <myl_core_assert_fail>
 105f1f8:	48 8d 3d 31 3c 02 00 	lea    0x23c31(%rip),%rdi        # 1082e30 <core_durable_error.verbs+0x2220>
 105f1ff:	e8 fc b1 fc ff       	call   102a400 <myl_core_assert_fail>
 105f204:	48 8d 3d 15 28 02 00 	lea    0x22815(%rip),%rdi        # 1081a20 <core_durable_error.verbs+0xe10>
 105f20b:	ba 01 00 00 00       	mov    $0x1,%edx
 105f210:	48 89 c6             	mov    %rax,%rsi
 105f213:	e8 68 5e fc ff       	call   1025080 <myl_core_trap>
 105f218:	48 8d 3d e1 20 02 00 	lea    0x220e1(%rip),%rdi        # 1081300 <core_durable_error.verbs+0x6f0>
 105f21f:	e8 5c 5e fc ff       	call   1025080 <myl_core_trap>
 105f224:	48 8d 3d 25 3d 02 00 	lea    0x23d25(%rip),%rdi        # 1082f50 <core_durable_error.verbs+0x2340>
 105f22b:	e8 50 5e fc ff       	call   1025080 <myl_core_trap>
 105f230:	48 8d 3d 49 6d 02 00 	lea    0x26d49(%rip),%rdi        # 1085f80 <core_durable_error.verbs+0x5370>
 105f237:	4c 89 ee             	mov    %r13,%rsi
 105f23a:	e8 41 5e fc ff       	call   1025080 <myl_core_trap>
 105f23f:	48 8d 3d 6a 3d 02 00 	lea    0x23d6a(%rip),%rdi        # 1082fb0 <core_durable_error.verbs+0x23a0>
 105f246:	4c 89 fe             	mov    %r15,%rsi
 105f249:	e8 32 5e fc ff       	call   1025080 <myl_core_trap>
 105f24e:	48 8d 3d 7b 23 02 00 	lea    0x2237b(%rip),%rdi        # 10815d0 <core_durable_error.verbs+0x9c0>
 105f255:	e8 26 5e fc ff       	call   1025080 <myl_core_trap>
 105f25a:	48 8d 3d 7f 28 02 00 	lea    0x2287f(%rip),%rdi        # 1081ae0 <core_durable_error.verbs+0xed0>
 105f261:	e8 1a 5e fc ff       	call   1025080 <myl_core_trap>
 105f266:	48 8d 3d 83 45 02 00 	lea    0x24583(%rip),%rdi        # 10837f0 <core_durable_error.verbs+0x2be0>
 105f26d:	48 89 ee             	mov    %rbp,%rsi
 105f270:	e8 0b 5e fc ff       	call   1025080 <myl_core_trap>
 105f275:	48 8d 3d 64 1f 02 00 	lea    0x21f64(%rip),%rdi        # 10811e0 <core_durable_error.verbs+0x5d0>
 105f27c:	e8 ff 5d fc ff       	call   1025080 <myl_core_trap>
 105f281:	48 8d 3d e8 28 02 00 	lea    0x228e8(%rip),%rdi        # 1081b70 <core_durable_error.verbs+0xf60>
 105f288:	4c 89 fe             	mov    %r15,%rsi
 105f28b:	e8 f0 5d fc ff       	call   1025080 <myl_core_trap>
 105f290:	48 8d 3d b9 21 02 00 	lea    0x221b9(%rip),%rdi        # 1081450 <core_durable_error.verbs+0x840>
 105f297:	4c 89 fe             	mov    %r15,%rsi
 105f29a:	e8 e1 5d fc ff       	call   1025080 <myl_core_trap>
 105f29f:	48 8d 3d 6a 25 02 00 	lea    0x2256a(%rip),%rdi        # 1081810 <core_durable_error.verbs+0xc00>
 105f2a6:	48 89 c2             	mov    %rax,%rdx
 105f2a9:	e8 d2 5d fc ff       	call   1025080 <myl_core_trap>
 105f2ae:	48 8d 3d 5b 6d 02 00 	lea    0x26d5b(%rip),%rdi        # 1086010 <core_durable_error.verbs+0x5400>
 105f2b5:	4c 89 fe             	mov    %r15,%rsi
 105f2b8:	48 89 c2             	mov    %rax,%rdx
 105f2bb:	e8 c0 5d fc ff       	call   1025080 <myl_core_trap>
 105f2c0:	48 8d 3d 89 24 02 00 	lea    0x22489(%rip),%rdi        # 1081750 <core_durable_error.verbs+0xb40>
 105f2c7:	e8 b4 5d fc ff       	call   1025080 <myl_core_trap>
 105f2cc:	48 8d 3d bd 1d 02 00 	lea    0x21dbd(%rip),%rdi        # 1081090 <core_durable_error.verbs+0x480>
 105f2d3:	e8 a8 5d fc ff       	call   1025080 <myl_core_trap>
 105f2d8:	48 8d 3d 81 26 02 00 	lea    0x22681(%rip),%rdi        # 1081960 <core_durable_error.verbs+0xd50>
 105f2df:	4c 89 fe             	mov    %r15,%rsi
 105f2e2:	e8 99 5d fc ff       	call   1025080 <myl_core_trap>
 105f2e7:	48 8d 3d 92 42 02 00 	lea    0x24292(%rip),%rdi        # 1083580 <core_durable_error.verbs+0x2970>
 105f2ee:	e8 8d 5d fc ff       	call   1025080 <myl_core_trap>
 105f2f3:	48 8d 3d f6 20 02 00 	lea    0x220f6(%rip),%rdi        # 10813f0 <core_durable_error.verbs+0x7e0>
 105f2fa:	4c 89 fe             	mov    %r15,%rsi
 105f2fd:	e8 7e 5d fc ff       	call   1025080 <myl_core_trap>
 105f302:	48 8d 3d f7 25 02 00 	lea    0x225f7(%rip),%rdi        # 1081900 <core_durable_error.verbs+0xcf0>
 105f309:	e8 72 5d fc ff       	call   1025080 <myl_core_trap>
 105f30e:	48 8d 3d 7b 41 02 00 	lea    0x2417b(%rip),%rdi        # 1083490 <core_durable_error.verbs+0x2880>
 105f315:	e8 66 5d fc ff       	call   1025080 <myl_core_trap>
 105f31a:	48 8d 3d cf 26 02 00 	lea    0x226cf(%rip),%rdi        # 10819f0 <core_durable_error.verbs+0xde0>
 105f321:	e8 5a 5d fc ff       	call   1025080 <myl_core_trap>
 105f326:	48 8d 3d e3 39 02 00 	lea    0x239e3(%rip),%rdi        # 1082d10 <core_durable_error.verbs+0x2100>
 105f32d:	48 8b 74 24 60       	mov    0x60(%rsp),%rsi
 105f332:	e8 49 5d fc ff       	call   1025080 <myl_core_trap>
 105f337:	48 8d 3d d2 36 02 00 	lea    0x236d2(%rip),%rdi        # 1082a10 <core_durable_error.verbs+0x1e00>
 105f33e:	e8 3d 5d fc ff       	call   1025080 <myl_core_trap>
 105f343:	48 8d 3d 06 42 02 00 	lea    0x24206(%rip),%rdi        # 1083550 <core_durable_error.verbs+0x2940>
 105f34a:	e8 31 5d fc ff       	call   1025080 <myl_core_trap>
 105f34f:	48 8d 3d 3a 20 02 00 	lea    0x2203a(%rip),%rdi        # 1081390 <core_durable_error.verbs+0x780>
 105f356:	4c 89 fe             	mov    %r15,%rsi
 105f359:	e8 22 5d fc ff       	call   1025080 <myl_core_trap>
 105f35e:	48 8d 3d fb 1c 02 00 	lea    0x21cfb(%rip),%rdi        # 1081060 <core_durable_error.verbs+0x450>
 105f365:	e8 16 5d fc ff       	call   1025080 <myl_core_trap>
 105f36a:	48 8d 3d 2f 25 02 00 	lea    0x2252f(%rip),%rdi        # 10818a0 <core_durable_error.verbs+0xc90>
 105f371:	e8 0a 5d fc ff       	call   1025080 <myl_core_trap>
 105f376:	48 8d 3d a3 44 02 00 	lea    0x244a3(%rip),%rdi        # 1083820 <core_durable_error.verbs+0x2c10>
 105f37d:	4c 89 fe             	mov    %r15,%rsi
 105f380:	e8 fb 5c fc ff       	call   1025080 <myl_core_trap>
 105f385:	48 8d 3d 24 27 02 00 	lea    0x22724(%rip),%rdi        # 1081ab0 <core_durable_error.verbs+0xea0>
 105f38c:	4c 89 fe             	mov    %r15,%rsi
 105f38f:	e8 ec 5c fc ff       	call   1025080 <myl_core_trap>
 105f394:	48 8d 3d 75 3c 02 00 	lea    0x23c75(%rip),%rdi        # 1083010 <core_durable_error.verbs+0x2400>
 105f39b:	e8 e0 5c fc ff       	call   1025080 <myl_core_trap>
 105f3a0:	48 8d 3d 69 21 02 00 	lea    0x22169(%rip),%rdi        # 1081510 <core_durable_error.verbs+0x900>
 105f3a7:	4c 89 fe             	mov    %r15,%rsi
 105f3aa:	e8 d1 5c fc ff       	call   1025080 <myl_core_trap>
 105f3af:	48 8d 3d ca 38 02 00 	lea    0x238ca(%rip),%rdi        # 1082c80 <core_durable_error.verbs+0x2070>
 105f3b6:	48 89 ee             	mov    %rbp,%rsi
 105f3b9:	e8 c2 5c fc ff       	call   1025080 <myl_core_trap>
 105f3be:	48 8d 3d db 1e 02 00 	lea    0x21edb(%rip),%rdi        # 10812a0 <core_durable_error.verbs+0x690>
 105f3c5:	e8 b6 5c fc ff       	call   1025080 <myl_core_trap>
 105f3ca:	48 8d 3d 5f 1f 02 00 	lea    0x21f5f(%rip),%rdi        # 1081330 <core_durable_error.verbs+0x720>
 105f3d1:	4c 89 fe             	mov    %r15,%rsi
 105f3d4:	e8 a7 5c fc ff       	call   1025080 <myl_core_trap>
 105f3d9:	48 8d 3d 50 22 02 00 	lea    0x22250(%rip),%rdi        # 1081630 <core_durable_error.verbs+0xa20>
 105f3e0:	e8 9b 5c fc ff       	call   1025080 <myl_core_trap>
 105f3e5:	48 8d 3d 54 42 02 00 	lea    0x24254(%rip),%rdi        # 1083640 <core_durable_error.verbs+0x2a30>
 105f3ec:	48 89 de             	mov    %rbx,%rsi
 105f3ef:	e8 8c 5c fc ff       	call   1025080 <myl_core_trap>
 105f3f4:	48 8d 3d 75 69 02 00 	lea    0x26975(%rip),%rdi        # 1085d70 <core_durable_error.verbs+0x5160>
 105f3fb:	4c 89 c6             	mov    %r8,%rsi
 105f3fe:	e8 7d 5c fc ff       	call   1025080 <myl_core_trap>
 105f403:	48 8d 3d b6 43 02 00 	lea    0x243b6(%rip),%rdi        # 10837c0 <core_durable_error.verbs+0x2bb0>
 105f40a:	e8 71 5c fc ff       	call   1025080 <myl_core_trap>
 105f40f:	48 8d 3d 2a 1e 02 00 	lea    0x21e2a(%rip),%rdi        # 1081240 <core_durable_error.verbs+0x630>
 105f416:	e8 65 5c fc ff       	call   1025080 <myl_core_trap>
 105f41b:	48 8d 3d 8e 23 02 00 	lea    0x2238e(%rip),%rdi        # 10817b0 <core_durable_error.verbs+0xba0>
 105f422:	48 89 de             	mov    %rbx,%rsi
 105f425:	e8 56 5c fc ff       	call   1025080 <myl_core_trap>
 105f42a:	48 8d 3d 4f 1d 02 00 	lea    0x21d4f(%rip),%rdi        # 1081180 <core_durable_error.verbs+0x570>
 105f431:	e8 4a 5c fc ff       	call   1025080 <myl_core_trap>
 105f436:	48 8d 3d b3 22 02 00 	lea    0x222b3(%rip),%rdi        # 10816f0 <core_durable_error.verbs+0xae0>
 105f43d:	e8 3e 5c fc ff       	call   1025080 <myl_core_trap>
 105f442:	48 8d 3d 97 20 02 00 	lea    0x22097(%rip),%rdi        # 10814e0 <core_durable_error.verbs+0x8d0>
 105f449:	e8 32 5c fc ff       	call   1025080 <myl_core_trap>
 105f44e:	48 8d 3d db 3c 02 00 	lea    0x23cdb(%rip),%rdi        # 1083130 <core_durable_error.verbs+0x2520>
 105f455:	4c 89 fe             	mov    %r15,%rsi
 105f458:	e8 23 5c fc ff       	call   1025080 <myl_core_trap>
 105f45d:	48 8d 3d 6c 42 02 00 	lea    0x2426c(%rip),%rdi        # 10836d0 <core_durable_error.verbs+0x2ac0>
 105f464:	e8 17 5c fc ff       	call   1025080 <myl_core_trap>
 105f469:	48 8d 3d 60 27 02 00 	lea    0x22760(%rip),%rdi        # 1081bd0 <core_durable_error.verbs+0xfc0>
 105f470:	4c 89 fe             	mov    %r15,%rsi
 105f473:	e8 08 5c fc ff       	call   1025080 <myl_core_trap>
 105f478:	48 8d 3d 11 22 02 00 	lea    0x22211(%rip),%rdi        # 1081690 <core_durable_error.verbs+0xa80>
 105f47f:	e8 fc 5b fc ff       	call   1025080 <myl_core_trap>
 105f484:	48 8d 3d b5 35 02 00 	lea    0x235b5(%rip),%rdi        # 1082a40 <core_durable_error.verbs+0x1e30>
 105f48b:	e8 f0 5b fc ff       	call   1025080 <myl_core_trap>
 105f490:	48 8d 3d 29 37 02 00 	lea    0x23729(%rip),%rdi        # 1082bc0 <core_durable_error.verbs+0x1fb0>
 105f497:	e8 e4 5b fc ff       	call   1025080 <myl_core_trap>
 105f49c:	48 8d 3d 2d 5a 02 00 	lea    0x25a2d(%rip),%rdi        # 1084ed0 <core_durable_error.verbs+0x42c0>
 105f4a3:	4c 89 f6             	mov    %r14,%rsi
 105f4a6:	e8 d5 5b fc ff       	call   1025080 <myl_core_trap>
 105f4ab:	48 8d 3d 0e 61 02 00 	lea    0x2610e(%rip),%rdi        # 10855c0 <core_durable_error.verbs+0x49b0>
 105f4b2:	48 89 c6             	mov    %rax,%rsi
 105f4b5:	e8 c6 5b fc ff       	call   1025080 <myl_core_trap>
 105f4ba:	48 8d 3d 0f 36 02 00 	lea    0x2360f(%rip),%rdi        # 1082ad0 <core_durable_error.verbs+0x1ec0>
 105f4c1:	e8 ba 5b fc ff       	call   1025080 <myl_core_trap>
 105f4c6:	48 8d 3d 63 36 02 00 	lea    0x23663(%rip),%rdi        # 1082b30 <core_durable_error.verbs+0x1f20>
 105f4cd:	48 89 c6             	mov    %rax,%rsi
 105f4d0:	e8 ab 5b fc ff       	call   1025080 <myl_core_trap>
 105f4d5:	48 8d 3d a4 34 02 00 	lea    0x234a4(%rip),%rdi        # 1082980 <core_durable_error.verbs+0x1d70>
 105f4dc:	48 89 c2             	mov    %rax,%rdx
 105f4df:	e8 9c 5b fc ff       	call   1025080 <myl_core_trap>
 105f4e4:	48 8d 3d 35 5e 02 00 	lea    0x25e35(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x4710>
 105f4eb:	48 89 c2             	mov    %rax,%rdx
 105f4ee:	e8 8d 5b fc ff       	call   1025080 <myl_core_trap>
 105f4f3:	48 8d 3d e6 6a 02 00 	lea    0x26ae6(%rip),%rdi        # 1085fe0 <core_durable_error.verbs+0x53d0>
 105f4fa:	4c 89 f6             	mov    %r14,%rsi
 105f4fd:	e8 7e 5b fc ff       	call   1025080 <myl_core_trap>
 105f502:	48 8d 3d 57 60 02 00 	lea    0x26057(%rip),%rdi        # 1085560 <core_durable_error.verbs+0x4950>
 105f509:	48 89 c6             	mov    %rax,%rsi
 105f50c:	48 89 ca             	mov    %rcx,%rdx
 105f50f:	e8 6c 5b fc ff       	call   1025080 <myl_core_trap>
 105f514:	48 8d 3d e5 3e 02 00 	lea    0x23ee5(%rip),%rdi        # 1083400 <core_durable_error.verbs+0x27f0>
 105f51b:	48 89 c2             	mov    %rax,%rdx
 105f51e:	e8 5d 5b fc ff       	call   1025080 <myl_core_trap>
 105f523:	48 8d 3d a6 59 02 00 	lea    0x259a6(%rip),%rdi        # 1084ed0 <core_durable_error.verbs+0x42c0>
 105f52a:	48 89 de             	mov    %rbx,%rsi
 105f52d:	e8 4e 5b fc ff       	call   1025080 <myl_core_trap>
 105f532:	48 8d 3d 37 35 02 00 	lea    0x23537(%rip),%rdi        # 1082a70 <core_durable_error.verbs+0x1e60>
 105f539:	e8 42 5b fc ff       	call   1025080 <myl_core_trap>
 105f53e:	48 8d 3d db 36 02 00 	lea    0x236db(%rip),%rdi        # 1082c20 <core_durable_error.verbs+0x2010>
 105f545:	e8 36 5b fc ff       	call   1025080 <myl_core_trap>
 105f54a:	48 8d 3d 5f 6a 02 00 	lea    0x26a5f(%rip),%rdi        # 1085fb0 <core_durable_error.verbs+0x53a0>
 105f551:	48 89 c2             	mov    %rax,%rdx
 105f554:	e8 27 5b fc ff       	call   1025080 <myl_core_trap>
 105f559:	48 8d 3d 10 3b 02 00 	lea    0x23b10(%rip),%rdi        # 1083070 <core_durable_error.verbs+0x2460>
 105f560:	48 89 c6             	mov    %rax,%rsi
 105f563:	e8 18 5b fc ff       	call   1025080 <myl_core_trap>
 105f568:	48 8d 3d d1 37 02 00 	lea    0x237d1(%rip),%rdi        # 1082d40 <core_durable_error.verbs+0x2130>
 105f56f:	4c 89 fe             	mov    %r15,%rsi
 105f572:	e8 09 5b fc ff       	call   1025080 <myl_core_trap>
 105f577:	48 8d 3d e2 35 02 00 	lea    0x235e2(%rip),%rdi        # 1082b60 <core_durable_error.verbs+0x1f50>
 105f57e:	48 89 de             	mov    %rbx,%rsi
 105f581:	e8 fa 5a fc ff       	call   1025080 <myl_core_trap>
 105f586:	48 8d 3d a3 41 02 00 	lea    0x241a3(%rip),%rdi        # 1083730 <core_durable_error.verbs+0x2b20>
 105f58d:	4c 89 fe             	mov    %r15,%rsi
 105f590:	e8 eb 5a fc ff       	call   1025080 <myl_core_trap>
 105f595:	48 8d 3d 84 8d 02 00 	lea    0x28d84(%rip),%rdi        # 1088320 <core_durable_error.verbs+0x7710>
 105f59c:	4c 89 f6             	mov    %r14,%rsi
 105f59f:	e8 dc 5a fc ff       	call   1025080 <myl_core_trap>
 105f5a4:	48 8d 3d c5 37 02 00 	lea    0x237c5(%rip),%rdi        # 1082d70 <core_durable_error.verbs+0x2160>
 105f5ab:	4c 89 fe             	mov    %r15,%rsi
 105f5ae:	e8 cd 5a fc ff       	call   1025080 <myl_core_trap>
 105f5b3:	48 8d 3d a6 5f 02 00 	lea    0x25fa6(%rip),%rdi        # 1085560 <core_durable_error.verbs+0x4950>
 105f5ba:	4c 89 c6             	mov    %r8,%rsi
 105f5bd:	48 89 ca             	mov    %rcx,%rdx
 105f5c0:	e8 bb 5a fc ff       	call   1025080 <myl_core_trap>
 105f5c5:	48 8d 3d 54 60 02 00 	lea    0x26054(%rip),%rdi        # 1085620 <core_durable_error.verbs+0x4a10>
 105f5cc:	e8 af 5a fc ff       	call   1025080 <myl_core_trap>
 105f5d1:	48 8d 3d 28 41 02 00 	lea    0x24128(%rip),%rdi        # 1083700 <core_durable_error.verbs+0x2af0>
 105f5d8:	4c 89 d6             	mov    %r10,%rsi
 105f5db:	e8 a0 5a fc ff       	call   1025080 <myl_core_trap>
 105f5e0:	48 8d 3d b9 37 02 00 	lea    0x237b9(%rip),%rdi        # 1082da0 <core_durable_error.verbs+0x2190>
 105f5e7:	4c 89 fe             	mov    %r15,%rsi
 105f5ea:	e8 91 5a fc ff       	call   1025080 <myl_core_trap>
 105f5ef:	48 8d 3d 9a 5f 02 00 	lea    0x25f9a(%rip),%rdi        # 1085590 <core_durable_error.verbs+0x4980>
 105f5f6:	e8 85 5a fc ff       	call   1025080 <myl_core_trap>
 105f5fb:	48 8d 3d ce 58 02 00 	lea    0x258ce(%rip),%rdi        # 1084ed0 <core_durable_error.verbs+0x42c0>
 105f602:	48 89 ee             	mov    %rbp,%rsi
 105f605:	e8 76 5a fc ff       	call   1025080 <myl_core_trap>
 105f60a:	48 8d 3d bf 3a 02 00 	lea    0x23abf(%rip),%rdi        # 10830d0 <core_durable_error.verbs+0x24c0>
 105f611:	4c 89 fe             	mov    %r15,%rsi
 105f614:	e8 67 5a fc ff       	call   1025080 <myl_core_trap>

Disassembly of section .plt:
