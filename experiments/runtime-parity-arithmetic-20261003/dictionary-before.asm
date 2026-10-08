
/home/epentland/.cache/mylang-tmp/runtime-parity-arithmetic-20261003/dictionary-path-before:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .plt.got:

Disassembly of section .text:

0000000000007620 <rc_insert_result>:
    7620:	55                   	push   %rbp
    7621:	48 89 e5             	mov    %rsp,%rbp
    7624:	41 57                	push   %r15
    7626:	41 56                	push   %r14
    7628:	41 55                	push   %r13
    762a:	41 54                	push   %r12
    762c:	53                   	push   %rbx
    762d:	48 81 ec 78 02 00 00 	sub    $0x278,%rsp
    7634:	49 89 cd             	mov    %rcx,%r13
    7637:	49 89 d7             	mov    %rdx,%r15
    763a:	48 8b 56 30          	mov    0x30(%rsi),%rdx
    763e:	31 db                	xor    %ebx,%ebx
    7640:	4d 85 c0             	test   %r8,%r8
    7643:	74 09                	je     764e <rc_insert_result+0x2e>
    7645:	48 8b 46 10          	mov    0x10(%rsi),%rax
    7649:	48 8b 00             	mov    (%rax),%rax
    764c:	eb 02                	jmp    7650 <rc_insert_result+0x30>
    764e:	31 c0                	xor    %eax,%eax
    7650:	48 89 c1             	mov    %rax,%rcx
    7653:	48 f7 d1             	not    %rcx
    7656:	48 d1 e9             	shr    $1,%rcx
    7659:	48 39 ca             	cmp    %rcx,%rdx
    765c:	0f 87 a7 04 00 00    	ja     7b09 <rc_insert_result+0x4e9>
    7662:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
    7666:	48 89 7d d0          	mov    %rdi,-0x30(%rbp)
    766a:	4c 8d 24 50          	lea    (%rax,%rdx,2),%r12
    766e:	49 81 fc 81 01 00 00 	cmp    $0x181,%r12
    7675:	4c 89 45 c0          	mov    %r8,-0x40(%rbp)
    7679:	48 89 55 b8          	mov    %rdx,-0x48(%rbp)
    767d:	73 09                	jae    7688 <rc_insert_result+0x68>
    767f:	4c 8d b5 60 fd ff ff 	lea    -0x2a0(%rbp),%r14
    7686:	eb 1c                	jmp    76a4 <rc_insert_result+0x84>
    7688:	31 db                	xor    %ebx,%ebx
    768a:	48 8b 7d d0          	mov    -0x30(%rbp),%rdi
    768e:	4c 89 e6             	mov    %r12,%rsi
    7691:	31 d2                	xor    %edx,%edx
    7693:	e8 f8 aa 00 00       	call   12190 <myl_rc_storage_bytes>
    7698:	49 89 c6             	mov    %rax,%r14
    769b:	48 85 c0             	test   %rax,%rax
    769e:	0f 84 65 04 00 00    	je     7b09 <rc_insert_result+0x4e9>
    76a4:	31 db                	xor    %ebx,%ebx
    76a6:	4c 89 f7             	mov    %r14,%rdi
    76a9:	31 f6                	xor    %esi,%esi
    76ab:	4c 89 e2             	mov    %r12,%rdx
    76ae:	e8 cd 99 ff ff       	call   1080 <memset@plt>
    76b3:	4c 8b 65 c8          	mov    -0x38(%rbp),%r12
    76b7:	49 8b 44 24 08       	mov    0x8(%r12),%rax
    76bc:	48 8b 10             	mov    (%rax),%rdx
    76bf:	4c 89 f7             	mov    %r14,%rdi
    76c2:	4c 89 fe             	mov    %r15,%rsi
    76c5:	e8 d6 99 ff ff       	call   10a0 <memcpy@plt>
    76ca:	49 8b 7c 24 18       	mov    0x18(%r12),%rdi
    76cf:	4c 01 f7             	add    %r14,%rdi
    76d2:	49 8b 44 24 10       	mov    0x10(%r12),%rax
    76d7:	48 8b 10             	mov    (%rax),%rdx
    76da:	4c 89 ee             	mov    %r13,%rsi
    76dd:	e8 be 99 ff ff       	call   10a0 <memcpy@plt>
    76e2:	49 8b 44 24 f0       	mov    -0x10(%r12),%rax
    76e7:	49 8b 34 24          	mov    (%r12),%rsi
    76eb:	49 89 c5             	mov    %rax,%r13
    76ee:	49 c1 ed 28          	shr    $0x28,%r13
    76f2:	41 81 e5 ff ff 0f 00 	and    $0xfffff,%r13d
    76f9:	48 0f ba e0 3e       	bt     $0x3e,%rax
    76fe:	44 0f 43 eb          	cmovae %ebx,%r13d
    7702:	49 8b 44 24 28       	mov    0x28(%r12),%rax
    7707:	48 85 c0             	test   %rax,%rax
    770a:	74 20                	je     772c <rc_insert_result+0x10c>
    770c:	4c 89 e7             	mov    %r12,%rdi
    770f:	48 01 c0             	add    %rax,%rax
    7712:	48 8b 16             	mov    (%rsi),%rdx
    7715:	48 39 d0             	cmp    %rdx,%rax
    7718:	4c 8b 65 d0          	mov    -0x30(%rbp),%r12
    771c:	72 15                	jb     7733 <rc_insert_result+0x113>
    771e:	e8 1d e8 ff ff       	call   5f40 <myl_native_dictionary_settle>
    7723:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
    7727:	48 8b 30             	mov    (%rax),%rsi
    772a:	eb 04                	jmp    7730 <rc_insert_result+0x110>
    772c:	4c 8b 65 d0          	mov    -0x30(%rbp),%r12
    7730:	48 8b 16             	mov    (%rsi),%rdx
    7733:	31 db                	xor    %ebx,%ebx
    7735:	48 83 fa ff          	cmp    $0xffffffffffffffff,%rdx
    7739:	0f 84 b3 03 00 00    	je     7af2 <rc_insert_result+0x4d2>
    773f:	48 83 7e 10 ff       	cmpq   $0xffffffffffffffff,0x10(%rsi)
    7744:	0f 84 a8 03 00 00    	je     7af2 <rc_insert_result+0x4d2>
    774a:	48 ff c2             	inc    %rdx
    774d:	4c 89 e7             	mov    %r12,%rdi
    7750:	e8 fb d7 ff ff       	call   4f50 <myl_rc_list_storage_reserve>
    7755:	85 c0                	test   %eax,%eax
    7757:	0f 84 95 03 00 00    	je     7af2 <rc_insert_result+0x4d2>
    775d:	48 8b 5d c8          	mov    -0x38(%rbp),%rbx
    7761:	48 8b 03             	mov    (%rbx),%rax
    7764:	48 8b 10             	mov    (%rax),%rdx
    7767:	48 ff c2             	inc    %rdx
    776a:	4c 89 e7             	mov    %r12,%rdi
    776d:	48 89 de             	mov    %rbx,%rsi
    7770:	e8 6b 07 00 00       	call   7ee0 <index_reserve>
    7775:	49 89 d9             	mov    %rbx,%r9
    7778:	83 7b 24 00          	cmpl   $0x0,0x24(%rbx)
    777c:	75 0f                	jne    778d <rc_insert_result+0x16d>
    777e:	49 8b 36             	mov    (%r14),%rsi
    7781:	31 db                	xor    %ebx,%ebx
    7783:	f6 46 10 04          	testb  $0x4,0x10(%rsi)
    7787:	0f 85 28 02 00 00    	jne    79b5 <rc_insert_result+0x395>
    778d:	45 31 ff             	xor    %r15d,%r15d
    7790:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
    7794:	49 8b 71 08          	mov    0x8(%r9),%rsi
    7798:	49 8b 84 24 08 16 00 	mov    0x1608(%r12),%rax
    779f:	00 
    77a0:	8b 4e 34             	mov    0x34(%rsi),%ecx
    77a3:	48 8b b8 a0 00 00 00 	mov    0xa0(%rax),%rdi
    77aa:	48 39 cf             	cmp    %rcx,%rdi
    77ad:	0f 86 6a 03 00 00    	jbe    7b1d <rc_insert_result+0x4fd>
    77b3:	4c 8b 80 98 00 00 00 	mov    0x98(%rax),%r8
    77ba:	48 c1 e1 04          	shl    $0x4,%rcx
    77be:	49 39 34 08          	cmp    %rsi,(%r8,%rcx,1)
    77c2:	0f 85 55 03 00 00    	jne    7b1d <rc_insert_result+0x4fd>
    77c8:	49 01 c8             	add    %rcx,%r8
    77cb:	49 8b 48 08          	mov    0x8(%r8),%rcx
    77cf:	49 8b 71 10          	mov    0x10(%r9),%rsi
    77d3:	44 8b 46 34          	mov    0x34(%rsi),%r8d
    77d7:	4c 39 c7             	cmp    %r8,%rdi
    77da:	0f 86 5c 03 00 00    	jbe    7b3c <rc_insert_result+0x51c>
    77e0:	48 8b 80 98 00 00 00 	mov    0x98(%rax),%rax
    77e7:	49 c1 e0 04          	shl    $0x4,%r8
    77eb:	4a 39 34 00          	cmp    %rsi,(%rax,%r8,1)
    77ef:	0f 85 47 03 00 00    	jne    7b3c <rc_insert_result+0x51c>
    77f5:	4c 01 c0             	add    %r8,%rax
    77f8:	48 8b 40 08          	mov    0x8(%rax),%rax
    77fc:	48 85 c9             	test   %rcx,%rcx
    77ff:	0f 84 48 03 00 00    	je     7b4d <rc_insert_result+0x52d>
    7805:	48 85 c0             	test   %rax,%rax
    7808:	0f 84 3f 03 00 00    	je     7b4d <rc_insert_result+0x52d>
    780e:	48 8b 75 b8          	mov    -0x48(%rbp),%rsi
    7812:	49 8d 3c 36          	lea    (%r14,%rsi,1),%rdi
    7816:	48 8d 1c 37          	lea    (%rdi,%rsi,1),%rbx
    781a:	48 8b 49 08          	mov    0x8(%rcx),%rcx
    781e:	48 89 8d 40 ff ff ff 	mov    %rcx,-0xc0(%rbp)
    7825:	48 89 bd 48 ff ff ff 	mov    %rdi,-0xb8(%rbp)
    782c:	48 c7 85 50 ff ff ff 	movq   $0x0,-0xb0(%rbp)
    7833:	00 00 00 00 
    7837:	44 89 ad 58 ff ff ff 	mov    %r13d,-0xa8(%rbp)
    783e:	c7 85 5c ff ff ff 00 	movl   $0x0,-0xa4(%rbp)
    7845:	00 00 00 
    7848:	48 8b 40 08          	mov    0x8(%rax),%rax
    784c:	48 89 85 60 ff ff ff 	mov    %rax,-0xa0(%rbp)
    7853:	49 8b 71 18          	mov    0x18(%r9),%rsi
    7857:	48 89 7d d0          	mov    %rdi,-0x30(%rbp)
    785b:	48 8d 3c 37          	lea    (%rdi,%rsi,1),%rdi
    785f:	48 89 bd 68 ff ff ff 	mov    %rdi,-0x98(%rbp)
    7866:	48 c7 85 70 ff ff ff 	movq   $0x0,-0x90(%rbp)
    786d:	00 00 00 00 
    7871:	44 89 ad 78 ff ff ff 	mov    %r13d,-0x88(%rbp)
    7878:	c7 85 7c ff ff ff 00 	movl   $0x0,-0x84(%rbp)
    787f:	00 00 00 
    7882:	48 89 45 80          	mov    %rax,-0x80(%rbp)
    7886:	48 89 5d 88          	mov    %rbx,-0x78(%rbp)
    788a:	48 c7 45 90 00 00 00 	movq   $0x0,-0x70(%rbp)
    7891:	00 
    7892:	41 8b 7c 24 70       	mov    0x70(%r12),%edi
    7897:	89 7d 98             	mov    %edi,-0x68(%rbp)
    789a:	c7 45 9c 00 00 00 00 	movl   $0x0,-0x64(%rbp)
    78a1:	48 89 8d e0 fe ff ff 	mov    %rcx,-0x120(%rbp)
    78a8:	4c 89 b5 e8 fe ff ff 	mov    %r14,-0x118(%rbp)
    78af:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    78b3:	c5 f8 29 85 f0 fe ff 	vmovaps %xmm0,-0x110(%rbp)
    78ba:	ff 
    78bb:	48 89 85 00 ff ff ff 	mov    %rax,-0x100(%rbp)
    78c2:	4c 01 f6             	add    %r14,%rsi
    78c5:	48 89 b5 08 ff ff ff 	mov    %rsi,-0xf8(%rbp)
    78cc:	c5 f8 29 85 10 ff ff 	vmovaps %xmm0,-0xf0(%rbp)
    78d3:	ff 
    78d4:	48 89 85 20 ff ff ff 	mov    %rax,-0xe0(%rbp)
    78db:	48 89 b5 28 ff ff ff 	mov    %rsi,-0xd8(%rbp)
    78e2:	c5 f8 29 85 30 ff ff 	vmovaps %xmm0,-0xd0(%rbp)
    78e9:	ff 
    78ea:	83 79 08 01          	cmpl   $0x1,0x8(%rcx)
    78ee:	0f 85 80 00 00 00    	jne    7974 <rc_insert_result+0x354>
    78f4:	49 8b 3e             	mov    (%r14),%rdi
    78f7:	49 8b 71 10          	mov    0x10(%r9),%rsi
    78fb:	49 8b 8c 24 08 16 00 	mov    0x1608(%r12),%rcx
    7902:	00 
    7903:	48 39 b1 10 01 00 00 	cmp    %rsi,0x110(%rcx)
    790a:	74 4c                	je     7958 <rc_insert_result+0x338>
    790c:	8b 46 34             	mov    0x34(%rsi),%eax
    790f:	48 39 81 a0 00 00 00 	cmp    %rax,0xa0(%rcx)
    7916:	0f 86 36 02 00 00    	jbe    7b52 <rc_insert_result+0x532>
    791c:	48 8b 89 98 00 00 00 	mov    0x98(%rcx),%rcx
    7923:	48 c1 e0 04          	shl    $0x4,%rax
    7927:	48 39 34 01          	cmp    %rsi,(%rcx,%rax,1)
    792b:	0f 85 21 02 00 00    	jne    7b52 <rc_insert_result+0x532>
    7931:	48 01 c1             	add    %rax,%rcx
    7934:	48 8b 41 08          	mov    0x8(%rcx),%rax
    7938:	48 85 c0             	test   %rax,%rax
    793b:	74 37                	je     7974 <rc_insert_result+0x354>
    793d:	83 78 40 00          	cmpl   $0x0,0x40(%rax)
    7941:	75 31                	jne    7974 <rc_insert_result+0x354>
    7943:	80 78 45 00          	cmpb   $0x0,0x45(%rax)
    7947:	75 2b                	jne    7974 <rc_insert_result+0x354>
    7949:	49 8b 84 24 08 16 00 	mov    0x1608(%r12),%rax
    7950:	00 
    7951:	48 89 b0 10 01 00 00 	mov    %rsi,0x110(%rax)
    7958:	48 85 ff             	test   %rdi,%rdi
    795b:	74 10                	je     796d <rc_insert_result+0x34d>
    795d:	48 b8 00 00 00 00 00 	movabs $0x4000000000000000,%rax
    7964:	00 00 40 
    7967:	48 85 47 f0          	test   %rax,-0x10(%rdi)
    796b:	75 07                	jne    7974 <rc_insert_result+0x354>
    796d:	45 3b 6c 24 70       	cmp    0x70(%r12),%r13d
    7972:	76 68                	jbe    79dc <rc_insert_result+0x3bc>
    7974:	48 83 fa 01          	cmp    $0x1,%rdx
    7978:	b9 03 00 00 00       	mov    $0x3,%ecx
    797d:	48 83 d9 00          	sbb    $0x0,%rcx
    7981:	48 8d b5 40 ff ff ff 	lea    -0xc0(%rbp),%rsi
    7988:	48 8d 95 e0 fe ff ff 	lea    -0x120(%rbp),%rdx
    798f:	4c 89 e7             	mov    %r12,%rdi
    7992:	e8 e9 c5 00 00       	call   13f80 <__wrap_myl_rc_value_retain_many>
    7997:	85 c0                	test   %eax,%eax
    7999:	74 7b                	je     7a16 <rc_insert_result+0x3f6>
    799b:	4c 89 e7             	mov    %r12,%rdi
    799e:	89 c6                	mov    %eax,%esi
    79a0:	e8 eb 35 00 00       	call   af90 <myl_rc_record_failure>
    79a5:	31 db                	xor    %ebx,%ebx
    79a7:	4d 85 ff             	test   %r15,%r15
    79aa:	0f 85 37 01 00 00    	jne    7ae7 <rc_insert_result+0x4c7>
    79b0:	e9 3d 01 00 00       	jmp    7af2 <rc_insert_result+0x4d2>
    79b5:	4c 89 e7             	mov    %r12,%rdi
    79b8:	44 89 ea             	mov    %r13d,%edx
    79bb:	e8 00 e0 ff ff       	call   59c0 <myl_native_text_own_at>
    79c0:	48 85 c0             	test   %rax,%rax
    79c3:	0f 84 29 01 00 00    	je     7af2 <rc_insert_result+0x4d2>
    79c9:	49 89 c7             	mov    %rax,%r15
    79cc:	49 89 06             	mov    %rax,(%r14)
    79cf:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
    79d3:	4c 8b 4d c8          	mov    -0x38(%rbp),%r9
    79d7:	e9 b8 fd ff ff       	jmp    7794 <rc_insert_result+0x174>
    79dc:	e8 bf 28 00 00       	call   a2a0 <myl_rc_owner_take>
    79e1:	85 c0                	test   %eax,%eax
    79e3:	75 b6                	jne    799b <rc_insert_result+0x37b>
    79e5:	48 8b 7d d0          	mov    -0x30(%rbp),%rdi
    79e9:	4c 89 f6             	mov    %r14,%rsi
    79ec:	48 8b 55 b8          	mov    -0x48(%rbp),%rdx
    79f0:	e8 ab 96 ff ff       	call   10a0 <memcpy@plt>
    79f5:	48 83 7d c0 00       	cmpq   $0x0,-0x40(%rbp)
    79fa:	74 1a                	je     7a16 <rc_insert_result+0x3f6>
    79fc:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
    7a00:	48 8b 70 18          	mov    0x18(%rax),%rsi
    7a04:	4c 01 f6             	add    %r14,%rsi
    7a07:	48 8b 40 10          	mov    0x10(%rax),%rax
    7a0b:	48 8b 10             	mov    (%rax),%rdx
    7a0e:	48 89 df             	mov    %rbx,%rdi
    7a11:	e8 8a 96 ff ff       	call   10a0 <memcpy@plt>
    7a16:	48 89 5d a0          	mov    %rbx,-0x60(%rbp)
    7a1a:	4c 89 7d a8          	mov    %r15,-0x58(%rbp)
    7a1e:	4c 89 75 b0          	mov    %r14,-0x50(%rbp)
    7a22:	4c 8b 6d c8          	mov    -0x38(%rbp),%r13
    7a26:	4c 89 ef             	mov    %r13,%rdi
    7a29:	4c 8b 7d d0          	mov    -0x30(%rbp),%r15
    7a2d:	4c 89 fe             	mov    %r15,%rsi
    7a30:	e8 8b 08 00 00       	call   82c0 <hash_key>
    7a35:	89 c3                	mov    %eax,%ebx
    7a37:	48 c1 e3 20          	shl    $0x20,%rbx
    7a3b:	48 8d 43 01          	lea    0x1(%rbx),%rax
    7a3f:	48 8b 55 b8          	mov    -0x48(%rbp),%rdx
    7a43:	49 89 44 17 f8       	mov    %rax,-0x8(%r15,%rdx,1)
    7a48:	49 8b 45 00          	mov    0x0(%r13),%rax
    7a4c:	4c 8b 30             	mov    (%rax),%r14
    7a4f:	49 8b 7d 30          	mov    0x30(%r13),%rdi
    7a53:	49 0f af fe          	imul   %r14,%rdi
    7a57:	48 03 78 20          	add    0x20(%rax),%rdi
    7a5b:	4c 89 fe             	mov    %r15,%rsi
    7a5e:	e8 3d 96 ff ff       	call   10a0 <memcpy@plt>
    7a63:	49 8b 45 00          	mov    0x0(%r13),%rax
    7a67:	48 ff 00             	incq   (%rax)
    7a6a:	48 ff 40 10          	incq   0x10(%rax)
    7a6e:	49 8b 85 d8 00 00 00 	mov    0xd8(%r13),%rax
    7a75:	48 85 c0             	test   %rax,%rax
    7a78:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
    7a7c:	74 37                	je     7ab5 <rc_insert_result+0x495>
    7a7e:	49 ff c6             	inc    %r14
    7a81:	49 09 de             	or     %rbx,%r14
    7a84:	48 ff c8             	dec    %rax
    7a87:	4c 89 f2             	mov    %r14,%rdx
    7a8a:	48 c1 ea 20          	shr    $0x20,%rdx
    7a8e:	49 8b 8d d0 00 00 00 	mov    0xd0(%r13),%rcx
    7a95:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
    7a9c:	00 00 00 00 
    7aa0:	48 89 d6             	mov    %rdx,%rsi
    7aa3:	48 21 c6             	and    %rax,%rsi
    7aa6:	48 8d 56 01          	lea    0x1(%rsi),%rdx
    7aaa:	48 83 3c f1 00       	cmpq   $0x0,(%rcx,%rsi,8)
    7aaf:	75 ef                	jne    7aa0 <rc_insert_result+0x480>
    7ab1:	4c 89 34 f1          	mov    %r14,(%rcx,%rsi,8)
    7ab5:	41 c7 85 f8 00 00 00 	movl   $0x0,0xf8(%r13)
    7abc:	00 00 00 00 
    7ac0:	bb 01 00 00 00       	mov    $0x1,%ebx
    7ac5:	48 85 ff             	test   %rdi,%rdi
    7ac8:	74 10                	je     7ada <rc_insert_result+0x4ba>
    7aca:	49 8b 45 10          	mov    0x10(%r13),%rax
    7ace:	48 8b 10             	mov    (%rax),%rdx
    7ad1:	48 8b 75 a0          	mov    -0x60(%rbp),%rsi
    7ad5:	e8 c6 95 ff ff       	call   10a0 <memcpy@plt>
    7ada:	4c 8b 75 b0          	mov    -0x50(%rbp),%r14
    7ade:	4c 8b 7d a8          	mov    -0x58(%rbp),%r15
    7ae2:	4d 85 ff             	test   %r15,%r15
    7ae5:	74 0b                	je     7af2 <rc_insert_result+0x4d2>
    7ae7:	4c 89 e7             	mov    %r12,%rdi
    7aea:	4c 89 fe             	mov    %r15,%rsi
    7aed:	e8 5e 3a 00 00       	call   b550 <myl_rc_owner_release>
    7af2:	48 8d 85 60 fd ff ff 	lea    -0x2a0(%rbp),%rax
    7af9:	49 39 c6             	cmp    %rax,%r14
    7afc:	74 0b                	je     7b09 <rc_insert_result+0x4e9>
    7afe:	4c 89 e7             	mov    %r12,%rdi
    7b01:	4c 89 f6             	mov    %r14,%rsi
    7b04:	e8 47 3a 00 00       	call   b550 <myl_rc_owner_release>
    7b09:	89 d8                	mov    %ebx,%eax
    7b0b:	48 81 c4 78 02 00 00 	add    $0x278,%rsp
    7b12:	5b                   	pop    %rbx
    7b13:	41 5c                	pop    %r12
    7b15:	41 5d                	pop    %r13
    7b17:	41 5e                	pop    %r14
    7b19:	41 5f                	pop    %r15
    7b1b:	5d                   	pop    %rbp
    7b1c:	c3                   	ret
    7b1d:	4c 89 e7             	mov    %r12,%rdi
    7b20:	e8 24 96 ff ff       	call   1149 <myl_rc_binding_find_slow>
    7b25:	48 89 c1             	mov    %rax,%rcx
    7b28:	49 8b 84 24 08 16 00 	mov    0x1608(%r12),%rax
    7b2f:	00 
    7b30:	48 8b b8 a0 00 00 00 	mov    0xa0(%rax),%rdi
    7b37:	e9 93 fc ff ff       	jmp    77cf <rc_insert_result+0x1af>
    7b3c:	4c 89 e7             	mov    %r12,%rdi
    7b3f:	e8 05 96 ff ff       	call   1149 <myl_rc_binding_find_slow>
    7b44:	48 85 c9             	test   %rcx,%rcx
    7b47:	0f 85 b8 fc ff ff    	jne    7805 <rc_insert_result+0x1e5>
    7b4d:	e8 ee 94 ff ff       	call   1040 <abort@plt>
    7b52:	48 89 f9             	mov    %rdi,%rcx
    7b55:	4c 89 e7             	mov    %r12,%rdi
    7b58:	e8 ec 95 ff ff       	call   1149 <myl_rc_binding_find_slow>
    7b5d:	48 89 cf             	mov    %rcx,%rdi
    7b60:	48 85 c0             	test   %rax,%rax
    7b63:	0f 85 d4 fd ff ff    	jne    793d <rc_insert_result+0x31d>
    7b69:	e9 06 fe ff ff       	jmp    7974 <rc_insert_result+0x354>

Disassembly of section .fini:
