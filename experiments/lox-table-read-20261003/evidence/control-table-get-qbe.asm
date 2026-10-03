
.tmp-lox-sweep/bin/final-sweep-qbe:     file format elf64-x86-64


Disassembly of section .text:

000000000111b640 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3>:
 111b640:	f3 0f 1e fa          	endbr64
 111b644:	55                   	push   %rbp
 111b645:	48 89 e5             	mov    %rsp,%rbp
 111b648:	48 83 ec 50          	sub    $0x50,%rsp
 111b64c:	53                   	push   %rbx
 111b64d:	41 54                	push   %r12
 111b64f:	48 89 f8             	mov    %rdi,%rax
 111b652:	48 89 f7             	mov    %rsi,%rdi
 111b655:	48 89 d6             	mov    %rdx,%rsi
 111b658:	4c 89 c2             	mov    %r8,%rdx
 111b65b:	4c 8b 46 08          	mov    0x8(%rsi),%r8
 111b65f:	49 83 f8 00          	cmp    $0x0,%r8
 111b663:	0f 84 96 02 00 00    	je     111b8ff <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x2bf>
 111b669:	4c 8b 06             	mov    (%rsi),%r8
 111b66c:	49 8b 30             	mov    (%r8),%rsi
 111b66f:	49 b9 ff ff ff ff ff 	movabs $0x7fffffffffffffff,%r9
 111b676:	ff ff 7f 
 111b679:	4c 39 ce             	cmp    %r9,%rsi
 111b67c:	0f 87 71 02 00 00    	ja     111b8f3 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x2b3>
 111b682:	49 b9 01 00 00 00 00 	movabs $0x8000000000000001,%r9
 111b689:	00 00 80 
 111b68c:	4c 39 ce             	cmp    %r9,%rsi
 111b68f:	0f 8c 44 02 00 00    	jl     111b8d9 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x299>
 111b695:	48 83 ee 01          	sub    $0x1,%rsi
 111b699:	48 83 fe 00          	cmp    $0x0,%rsi
 111b69d:	41 0f 9c c1          	setl   %r9b
 111b6a1:	4d 0f b6 c9          	movzbq %r9b,%r9
 111b6a5:	41 ba ff ff ff ff    	mov    $0xffffffff,%r10d
 111b6ab:	4c 39 d6             	cmp    %r10,%rsi
 111b6ae:	41 0f 9f c2          	setg   %r10b
 111b6b2:	4d 0f b6 d2          	movzbq %r10b,%r10
 111b6b6:	4d 09 d1             	or     %r10,%r9
 111b6b9:	0f 85 0e 02 00 00    	jne    111b8cd <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x28d>
 111b6bf:	48 21 f2             	and    %rsi,%rdx
 111b6c2:	48 c1 e2 20          	shl    $0x20,%rdx
 111b6c6:	48 c1 ea 20          	shr    $0x20,%rdx
 111b6ca:	49 89 d1             	mov    %rdx,%r9
 111b6cd:	48 8d 55 c8          	lea    -0x38(%rbp),%rdx
 111b6d1:	48 83 c2 10          	add    $0x10,%rdx
 111b6d5:	48 87 f7             	xchg   %rsi,%rdi
 111b6d8:	48 97                	xchg   %rax,%rdi
 111b6da:	49 90                	xchg   %rax,%r8
 111b6dc:	0f 1f 40 00          	nopl   0x0(%rax)
 111b6e0:	4c 8b 18             	mov    (%rax),%r11
 111b6e3:	4d 39 d9             	cmp    %r11,%r9
 111b6e6:	41 0f 92 c2          	setb   %r10b
 111b6ea:	4d 0f b6 d2          	movzbq %r10b,%r10
 111b6ee:	41 83 fa 00          	cmp    $0x0,%r10d
 111b6f2:	0f 85 90 00 00 00    	jne    111b788 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x148>
 111b6f8:	49 83 f9 00          	cmp    $0x0,%r9
 111b6fc:	7c 05                	jl     111b703 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0xc3>
 111b6fe:	4d 89 cb             	mov    %r9,%r11
 111b701:	eb 2d                	jmp    111b730 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0xf0>
 111b703:	49 ba ff ff ff ff ff 	movabs $0x7fffffffffffffff,%r10
 111b70a:	ff ff 7f 
 111b70d:	4d 39 d3             	cmp    %r10,%r11
 111b710:	77 64                	ja     111b776 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x136>
 111b712:	4d 89 da             	mov    %r11,%r10
 111b715:	4d 01 ca             	add    %r9,%r10
 111b718:	4c 89 db             	mov    %r11,%rbx
 111b71b:	4c 31 d3             	xor    %r10,%rbx
 111b71e:	4d 89 d4             	mov    %r10,%r12
 111b721:	4d 31 cc             	xor    %r9,%r12
 111b724:	4c 21 e3             	and    %r12,%rbx
 111b727:	48 83 fb 00          	cmp    $0x0,%rbx
 111b72b:	7c 28                	jl     111b755 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x115>
 111b72d:	4d 89 d3             	mov    %r10,%r11
 111b730:	4c 8b 10             	mov    (%rax),%r10
 111b733:	4d 39 d3             	cmp    %r10,%r11
 111b736:	73 0d                	jae    111b745 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x105>
 111b738:	4c 8b 50 20          	mov    0x20(%rax),%r10
 111b73c:	4d 6b db 20          	imul   $0x20,%r11,%r11
 111b740:	4d 01 da             	add    %r11,%r10
 111b743:	eb 4e                	jmp    111b793 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x153>
 111b745:	4c 89 d2             	mov    %r10,%rdx
 111b748:	48 89 f7             	mov    %rsi,%rdi
 111b74b:	4c 89 de             	mov    %r11,%rsi
 111b74e:	e8 4d f8 03 00       	call   115afa0 <myl_qbe_fail_normalized_index_bounds>
 111b753:	0f 0b                	ud2
 111b755:	4c 89 ca             	mov    %r9,%rdx
 111b758:	48 89 f7             	mov    %rsi,%rdi
 111b75b:	4c 89 de             	mov    %r11,%rsi
 111b75e:	41 b8 40 00 00 00    	mov    $0x40,%r8d
 111b764:	48 89 d1             	mov    %rdx,%rcx
 111b767:	48 89 f2             	mov    %rsi,%rdx
 111b76a:	be 00 00 00 00       	mov    $0x0,%esi
 111b76f:	e8 3c fa 03 00       	call   115b1b0 <myl_qbe_fail_overflow_op>
 111b774:	0f 0b                	ud2
 111b776:	48 89 f7             	mov    %rsi,%rdi
 111b779:	4c 89 de             	mov    %r11,%rsi
 111b77c:	ba 40 01 00 00       	mov    $0x140,%edx
 111b781:	e8 6a fb 03 00       	call   115b2f0 <myl_qbe_fail_cast>
 111b786:	0f 0b                	ud2
 111b788:	4c 8b 50 20          	mov    0x20(%rax),%r10
 111b78c:	4d 6b d9 20          	imul   $0x20,%r9,%r11
 111b790:	4d 01 da             	add    %r11,%r10
 111b793:	4d 8b 1a             	mov    (%r10),%r11
 111b796:	4c 89 5d c8          	mov    %r11,-0x38(%rbp)
 111b79a:	4d 8b 5a 08          	mov    0x8(%r10),%r11
 111b79e:	4c 89 5d d0          	mov    %r11,-0x30(%rbp)
 111b7a2:	4d 8b 5a 10          	mov    0x10(%r10),%r11
 111b7a6:	4c 89 5d d8          	mov    %r11,-0x28(%rbp)
 111b7aa:	4d 8b 52 18          	mov    0x18(%r10),%r10
 111b7ae:	4c 89 55 e0          	mov    %r10,-0x20(%rbp)
 111b7b2:	4c 8b 55 c8          	mov    -0x38(%rbp),%r10
 111b7b6:	49 83 fa ff          	cmp    $0xffffffffffffffff,%r10
 111b7ba:	74 41                	je     111b7fd <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x1bd>
 111b7bc:	4c 39 d1             	cmp    %r10,%rcx
 111b7bf:	0f 85 ad 00 00 00    	jne    111b872 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x232>
 111b7c5:	48 89 f8             	mov    %rdi,%rax
 111b7c8:	c7 45 e8 01 00 00 00 	movl   $0x1,-0x18(%rbp)
 111b7cf:	48 8b 0a             	mov    (%rdx),%rcx
 111b7d2:	48 89 4d f0          	mov    %rcx,-0x10(%rbp)
 111b7d6:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
 111b7da:	48 89 4d f8          	mov    %rcx,-0x8(%rbp)
 111b7de:	48 8b 4d e8          	mov    -0x18(%rbp),%rcx
 111b7e2:	48 89 08             	mov    %rcx,(%rax)
 111b7e5:	48 8b 4d f0          	mov    -0x10(%rbp),%rcx
 111b7e9:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111b7ed:	48 8b 4d f8          	mov    -0x8(%rbp),%rcx
 111b7f1:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111b7f5:	48 89 c3             	mov    %rax,%rbx
 111b7f8:	e9 20 01 00 00       	jmp    111b91d <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x2dd>
 111b7fd:	44 8b 55 d8          	mov    -0x28(%rbp),%r10d
 111b801:	49 83 fa 00          	cmp    $0x0,%r10
 111b805:	74 5f                	je     111b866 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x226>
 111b807:	49 83 fa 01          	cmp    $0x1,%r10
 111b80b:	74 51                	je     111b85e <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x21e>
 111b80d:	49 83 fa 02          	cmp    $0x2,%r10
 111b811:	74 43                	je     111b856 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x216>
 111b813:	49 83 fa 03          	cmp    $0x3,%r10
 111b817:	75 08                	jne    111b821 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x1e1>
 111b819:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 111b81f:	eb 4b                	jmp    111b86c <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x22c>
 111b821:	48 89 fb             	mov    %rdi,%rbx
 111b824:	ba 18 00 00 00       	mov    $0x18,%edx
 111b829:	be 00 00 00 00       	mov    $0x0,%esi
 111b82e:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
 111b832:	e8 19 bf 05 00       	call   1177750 <compiler_rt.fastMemset>
 111b837:	48 89 d8             	mov    %rbx,%rax
 111b83a:	48 8b 4d b0          	mov    -0x50(%rbp),%rcx
 111b83e:	48 89 08             	mov    %rcx,(%rax)
 111b841:	48 8b 4d b8          	mov    -0x48(%rbp),%rcx
 111b845:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111b849:	48 8b 4d c0          	mov    -0x40(%rbp),%rcx
 111b84d:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111b851:	e9 c7 00 00 00       	jmp    111b91d <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x2dd>
 111b856:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 111b85c:	eb 0e                	jmp    111b86c <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x22c>
 111b85e:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 111b864:	eb 06                	jmp    111b86c <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x22c>
 111b866:	41 ba 00 00 00 00    	mov    $0x0,%r10d
 111b86c:	49 83 f2 01          	xor    $0x1,%r10
 111b870:	75 38                	jne    111b8aa <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x26a>
 111b872:	49 ba fe ff ff ff ff 	movabs $0x7ffffffffffffffe,%r10
 111b879:	ff ff 7f 
 111b87c:	4d 39 d1             	cmp    %r10,%r9
 111b87f:	7f 0c                	jg     111b88d <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x24d>
 111b881:	49 83 c1 01          	add    $0x1,%r9
 111b885:	4d 21 c1             	and    %r8,%r9
 111b888:	e9 53 fe ff ff       	jmp    111b6e0 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0xa0>
 111b88d:	4c 89 ca             	mov    %r9,%rdx
 111b890:	48 89 f7             	mov    %rsi,%rdi
 111b893:	41 b8 40 00 00 00    	mov    $0x40,%r8d
 111b899:	b9 01 00 00 00       	mov    $0x1,%ecx
 111b89e:	be 00 00 00 00       	mov    $0x0,%esi
 111b8a3:	e8 08 f9 03 00       	call   115b1b0 <myl_qbe_fail_overflow_op>
 111b8a8:	0f 0b                	ud2
 111b8aa:	48 89 f8             	mov    %rdi,%rax
 111b8ad:	c7 45 c8 00 00 00 00 	movl   $0x0,-0x38(%rbp)
 111b8b4:	48 8b 4d c8          	mov    -0x38(%rbp),%rcx
 111b8b8:	48 89 08             	mov    %rcx,(%rax)
 111b8bb:	48 8b 4d d0          	mov    -0x30(%rbp),%rcx
 111b8bf:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111b8c3:	48 8b 4d d8          	mov    -0x28(%rbp),%rcx
 111b8c7:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111b8cb:	eb 50                	jmp    111b91d <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x2dd>
 111b8cd:	ba 20 00 00 00       	mov    $0x20,%edx
 111b8d2:	e8 19 fa 03 00       	call   115b2f0 <myl_qbe_fail_cast>
 111b8d7:	0f 0b                	ud2
 111b8d9:	41 b8 40 00 00 00    	mov    $0x40,%r8d
 111b8df:	b9 01 00 00 00       	mov    $0x1,%ecx
 111b8e4:	48 89 f2             	mov    %rsi,%rdx
 111b8e7:	be 01 00 00 00       	mov    $0x1,%esi
 111b8ec:	e8 bf f8 03 00       	call   115b1b0 <myl_qbe_fail_overflow_op>
 111b8f1:	0f 0b                	ud2
 111b8f3:	ba 40 01 00 00       	mov    $0x140,%edx
 111b8f8:	e8 f3 f9 03 00       	call   115b2f0 <myl_qbe_fail_cast>
 111b8fd:	0f 0b                	ud2
 111b8ff:	c7 45 c8 00 00 00 00 	movl   $0x0,-0x38(%rbp)
 111b906:	48 8b 4d c8          	mov    -0x38(%rbp),%rcx
 111b90a:	48 89 08             	mov    %rcx,(%rax)
 111b90d:	48 8b 4d d0          	mov    -0x30(%rbp),%rcx
 111b911:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111b915:	48 8b 4d d8          	mov    -0x28(%rbp),%rcx
 111b919:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111b91d:	41 5c                	pop    %r12
 111b91f:	5b                   	pop    %rbx
 111b920:	c9                   	leave
 111b921:	c3                   	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
