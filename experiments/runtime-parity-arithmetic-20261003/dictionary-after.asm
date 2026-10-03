
/home/epentland/.cache/mylang-tmp/runtime-parity-arithmetic-20261003/dictionary-path-after:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .plt.got:

Disassembly of section .text:

0000000000007640 <rc_insert_result>:
    7640:	55                   	push   %rbp
    7641:	48 89 e5             	mov    %rsp,%rbp
    7644:	41 57                	push   %r15
    7646:	41 56                	push   %r14
    7648:	41 55                	push   %r13
    764a:	41 54                	push   %r12
    764c:	53                   	push   %rbx
    764d:	48 81 ec 98 02 00 00 	sub    $0x298,%rsp
    7654:	49 89 cd             	mov    %rcx,%r13
    7657:	49 89 d6             	mov    %rdx,%r14
    765a:	48 8b 56 30          	mov    0x30(%rsi),%rdx
    765e:	31 db                	xor    %ebx,%ebx
    7660:	4d 85 c0             	test   %r8,%r8
    7663:	74 09                	je     766e <rc_insert_result+0x2e>
    7665:	48 8b 46 10          	mov    0x10(%rsi),%rax
    7669:	48 8b 00             	mov    (%rax),%rax
    766c:	eb 02                	jmp    7670 <rc_insert_result+0x30>
    766e:	31 c0                	xor    %eax,%eax
    7670:	48 89 c1             	mov    %rax,%rcx
    7673:	48 f7 d1             	not    %rcx
    7676:	48 d1 e9             	shr    $1,%rcx
    7679:	48 39 ca             	cmp    %rcx,%rdx
    767c:	0f 87 f1 05 00 00    	ja     7c73 <rc_insert_result+0x633>
    7682:	48 89 75 c8          	mov    %rsi,-0x38(%rbp)
    7686:	48 89 7d b8          	mov    %rdi,-0x48(%rbp)
    768a:	4c 8d 3c 50          	lea    (%rax,%rdx,2),%r15
    768e:	49 81 ff 81 01 00 00 	cmp    $0x181,%r15
    7695:	4c 89 45 c0          	mov    %r8,-0x40(%rbp)
    7699:	48 89 55 d0          	mov    %rdx,-0x30(%rbp)
    769d:	73 09                	jae    76a8 <rc_insert_result+0x68>
    769f:	4c 8d a5 40 fd ff ff 	lea    -0x2c0(%rbp),%r12
    76a6:	eb 1c                	jmp    76c4 <rc_insert_result+0x84>
    76a8:	31 db                	xor    %ebx,%ebx
    76aa:	48 8b 7d b8          	mov    -0x48(%rbp),%rdi
    76ae:	4c 89 fe             	mov    %r15,%rsi
    76b1:	31 d2                	xor    %edx,%edx
    76b3:	e8 78 ac 00 00       	call   12330 <myl_rc_storage_bytes>
    76b8:	49 89 c4             	mov    %rax,%r12
    76bb:	48 85 c0             	test   %rax,%rax
    76be:	0f 84 af 05 00 00    	je     7c73 <rc_insert_result+0x633>
    76c4:	31 db                	xor    %ebx,%ebx
    76c6:	4c 89 e7             	mov    %r12,%rdi
    76c9:	31 f6                	xor    %esi,%esi
    76cb:	4c 89 fa             	mov    %r15,%rdx
    76ce:	e8 ad 99 ff ff       	call   1080 <memset@plt>
    76d3:	4c 8b 7d c8          	mov    -0x38(%rbp),%r15
    76d7:	49 8b 47 08          	mov    0x8(%r15),%rax
    76db:	48 8b 10             	mov    (%rax),%rdx
    76de:	4c 89 e7             	mov    %r12,%rdi
    76e1:	4c 89 f6             	mov    %r14,%rsi
    76e4:	e8 b7 99 ff ff       	call   10a0 <memcpy@plt>
    76e9:	49 8b 7f 18          	mov    0x18(%r15),%rdi
    76ed:	4c 01 e7             	add    %r12,%rdi
    76f0:	49 8b 47 10          	mov    0x10(%r15),%rax
    76f4:	48 8b 10             	mov    (%rax),%rdx
    76f7:	4c 89 ee             	mov    %r13,%rsi
    76fa:	e8 a1 99 ff ff       	call   10a0 <memcpy@plt>
    76ff:	49 8b 47 f0          	mov    -0x10(%r15),%rax
    7703:	49 8b 37             	mov    (%r15),%rsi
    7706:	49 89 c5             	mov    %rax,%r13
    7709:	49 c1 ed 28          	shr    $0x28,%r13
    770d:	41 81 e5 ff ff 0f 00 	and    $0xfffff,%r13d
    7714:	48 0f ba e0 3e       	bt     $0x3e,%rax
    7719:	44 0f 43 eb          	cmovae %ebx,%r13d
    771d:	49 8b 47 28          	mov    0x28(%r15),%rax
    7721:	48 85 c0             	test   %rax,%rax
    7724:	74 1c                	je     7742 <rc_insert_result+0x102>
    7726:	48 01 c0             	add    %rax,%rax
    7729:	48 8b 16             	mov    (%rsi),%rdx
    772c:	48 39 d0             	cmp    %rdx,%rax
    772f:	4c 8b 75 b8          	mov    -0x48(%rbp),%r14
    7733:	72 14                	jb     7749 <rc_insert_result+0x109>
    7735:	4c 89 ff             	mov    %r15,%rdi
    7738:	e8 03 e8 ff ff       	call   5f40 <myl_native_dictionary_settle>
    773d:	49 8b 37             	mov    (%r15),%rsi
    7740:	eb 04                	jmp    7746 <rc_insert_result+0x106>
    7742:	4c 8b 75 b8          	mov    -0x48(%rbp),%r14
    7746:	48 8b 16             	mov    (%rsi),%rdx
    7749:	31 db                	xor    %ebx,%ebx
    774b:	48 83 fa ff          	cmp    $0xffffffffffffffff,%rdx
    774f:	0f 84 07 05 00 00    	je     7c5c <rc_insert_result+0x61c>
    7755:	48 83 7e 10 ff       	cmpq   $0xffffffffffffffff,0x10(%rsi)
    775a:	0f 84 fc 04 00 00    	je     7c5c <rc_insert_result+0x61c>
    7760:	48 ff c2             	inc    %rdx
    7763:	4c 89 f7             	mov    %r14,%rdi
    7766:	e8 e5 d7 ff ff       	call   4f50 <myl_rc_list_storage_reserve>
    776b:	85 c0                	test   %eax,%eax
    776d:	0f 84 e9 04 00 00    	je     7c5c <rc_insert_result+0x61c>
    7773:	49 8b 07             	mov    (%r15),%rax
    7776:	48 8b 10             	mov    (%rax),%rdx
    7779:	48 ff c2             	inc    %rdx
    777c:	4c 89 f7             	mov    %r14,%rdi
    777f:	4c 89 fe             	mov    %r15,%rsi
    7782:	e8 f9 08 00 00       	call   8080 <index_reserve>
    7787:	41 83 7f 24 00       	cmpl   $0x0,0x24(%r15)
    778c:	75 10                	jne    779e <rc_insert_result+0x15e>
    778e:	49 8b 34 24          	mov    (%r12),%rsi
    7792:	31 db                	xor    %ebx,%ebx
    7794:	f6 46 10 04          	testb  $0x4,0x10(%rsi)
    7798:	0f 85 68 02 00 00    	jne    7a06 <rc_insert_result+0x3c6>
    779e:	45 31 d2             	xor    %r10d,%r10d
    77a1:	4c 8b 45 c0          	mov    -0x40(%rbp),%r8
    77a5:	48 8b 55 d0          	mov    -0x30(%rbp),%rdx
    77a9:	49 8b 77 08          	mov    0x8(%r15),%rsi
    77ad:	49 8b 86 08 16 00 00 	mov    0x1608(%r14),%rax
    77b4:	8b 4e 34             	mov    0x34(%rsi),%ecx
    77b7:	4c 8b 88 a0 00 00 00 	mov    0xa0(%rax),%r9
    77be:	49 39 c9             	cmp    %rcx,%r9
    77c1:	0f 86 f6 04 00 00    	jbe    7cbd <rc_insert_result+0x67d>
    77c7:	48 8b b8 98 00 00 00 	mov    0x98(%rax),%rdi
    77ce:	48 c1 e1 04          	shl    $0x4,%rcx
    77d2:	48 39 34 0f          	cmp    %rsi,(%rdi,%rcx,1)
    77d6:	0f 85 e1 04 00 00    	jne    7cbd <rc_insert_result+0x67d>
    77dc:	48 01 cf             	add    %rcx,%rdi
    77df:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
    77e3:	49 8b 77 10          	mov    0x10(%r15),%rsi
    77e7:	8b 7e 34             	mov    0x34(%rsi),%edi
    77ea:	49 39 f9             	cmp    %rdi,%r9
    77ed:	0f 86 e8 04 00 00    	jbe    7cdb <rc_insert_result+0x69b>
    77f3:	48 8b 80 98 00 00 00 	mov    0x98(%rax),%rax
    77fa:	48 c1 e7 04          	shl    $0x4,%rdi
    77fe:	48 39 34 38          	cmp    %rsi,(%rax,%rdi,1)
    7802:	0f 85 d3 04 00 00    	jne    7cdb <rc_insert_result+0x69b>
    7808:	48 01 f8             	add    %rdi,%rax
    780b:	48 8b 40 08          	mov    0x8(%rax),%rax
    780f:	48 85 c9             	test   %rcx,%rcx
    7812:	0f 84 d4 04 00 00    	je     7cec <rc_insert_result+0x6ac>
    7818:	48 85 c0             	test   %rax,%rax
    781b:	0f 84 cb 04 00 00    	je     7cec <rc_insert_result+0x6ac>
    7821:	49 8d 3c 14          	lea    (%r12,%rdx,1),%rdi
    7825:	48 8d 1c 17          	lea    (%rdi,%rdx,1),%rbx
    7829:	48 8b 71 08          	mov    0x8(%rcx),%rsi
    782d:	48 89 b5 20 ff ff ff 	mov    %rsi,-0xe0(%rbp)
    7834:	48 89 bd 28 ff ff ff 	mov    %rdi,-0xd8(%rbp)
    783b:	48 c7 85 30 ff ff ff 	movq   $0x0,-0xd0(%rbp)
    7842:	00 00 00 00 
    7846:	44 89 ad 38 ff ff ff 	mov    %r13d,-0xc8(%rbp)
    784d:	c7 85 3c ff ff ff 00 	movl   $0x0,-0xc4(%rbp)
    7854:	00 00 00 
    7857:	48 8b 70 08          	mov    0x8(%rax),%rsi
    785b:	48 89 b5 40 ff ff ff 	mov    %rsi,-0xc0(%rbp)
    7862:	4d 8b 4f 18          	mov    0x18(%r15),%r9
    7866:	48 89 7d b0          	mov    %rdi,-0x50(%rbp)
    786a:	4a 8d 34 0f          	lea    (%rdi,%r9,1),%rsi
    786e:	48 89 b5 48 ff ff ff 	mov    %rsi,-0xb8(%rbp)
    7875:	48 c7 85 50 ff ff ff 	movq   $0x0,-0xb0(%rbp)
    787c:	00 00 00 00 
    7880:	44 89 ad 58 ff ff ff 	mov    %r13d,-0xa8(%rbp)
    7887:	c7 85 5c ff ff ff 00 	movl   $0x0,-0xa4(%rbp)
    788e:	00 00 00 
    7891:	48 8b 70 08          	mov    0x8(%rax),%rsi
    7895:	48 89 b5 60 ff ff ff 	mov    %rsi,-0xa0(%rbp)
    789c:	48 89 9d 68 ff ff ff 	mov    %rbx,-0x98(%rbp)
    78a3:	48 c7 85 70 ff ff ff 	movq   $0x0,-0x90(%rbp)
    78aa:	00 00 00 00 
    78ae:	41 8b 76 70          	mov    0x70(%r14),%esi
    78b2:	89 b5 78 ff ff ff    	mov    %esi,-0x88(%rbp)
    78b8:	c7 85 7c ff ff ff 00 	movl   $0x0,-0x84(%rbp)
    78bf:	00 00 00 
    78c2:	48 8b 79 08          	mov    0x8(%rcx),%rdi
    78c6:	48 89 bd c0 fe ff ff 	mov    %rdi,-0x140(%rbp)
    78cd:	4c 89 a5 c8 fe ff ff 	mov    %r12,-0x138(%rbp)
    78d4:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    78d8:	c5 f8 29 85 d0 fe ff 	vmovaps %xmm0,-0x130(%rbp)
    78df:	ff 
    78e0:	48 8b 78 08          	mov    0x8(%rax),%rdi
    78e4:	48 89 bd e0 fe ff ff 	mov    %rdi,-0x120(%rbp)
    78eb:	4d 01 e1             	add    %r12,%r9
    78ee:	4c 89 8d e8 fe ff ff 	mov    %r9,-0x118(%rbp)
    78f5:	c5 f8 29 85 f0 fe ff 	vmovaps %xmm0,-0x110(%rbp)
    78fc:	ff 
    78fd:	48 8b 78 08          	mov    0x8(%rax),%rdi
    7901:	48 89 bd 00 ff ff ff 	mov    %rdi,-0x100(%rbp)
    7908:	4c 89 8d 08 ff ff ff 	mov    %r9,-0xf8(%rbp)
    790f:	c5 f8 29 85 10 ff ff 	vmovaps %xmm0,-0xf0(%rbp)
    7916:	ff 
    7917:	49 8b 3c 24          	mov    (%r12),%rdi
    791b:	4d 8b 8e 08 16 00 00 	mov    0x1608(%r14),%r9
    7922:	49 83 b9 c8 00 00 00 	cmpq   $0x0,0xc8(%r9)
    7929:	00 
    792a:	4c 89 55 88          	mov    %r10,-0x78(%rbp)
    792e:	75 21                	jne    7951 <rc_insert_result+0x311>
    7930:	41 39 f5             	cmp    %esi,%r13d
    7933:	77 1c                	ja     7951 <rc_insert_result+0x311>
    7935:	83 79 40 00          	cmpl   $0x0,0x40(%rcx)
    7939:	75 16                	jne    7951 <rc_insert_result+0x311>
    793b:	80 79 45 00          	cmpb   $0x0,0x45(%rcx)
    793f:	75 10                	jne    7951 <rc_insert_result+0x311>
    7941:	83 78 40 00          	cmpl   $0x0,0x40(%rax)
    7945:	75 0a                	jne    7951 <rc_insert_result+0x311>
    7947:	80 78 45 00          	cmpb   $0x0,0x45(%rax)
    794b:	0f 84 36 03 00 00    	je     7c87 <rc_insert_result+0x647>
    7951:	48 8b 41 08          	mov    0x8(%rcx),%rax
    7955:	83 78 08 01          	cmpl   $0x1,0x8(%rax)
    7959:	75 73                	jne    79ce <rc_insert_result+0x38e>
    795b:	49 8b 77 10          	mov    0x10(%r15),%rsi
    795f:	49 39 b1 10 01 00 00 	cmp    %rsi,0x110(%r9)
    7966:	74 4b                	je     79b3 <rc_insert_result+0x373>
    7968:	8b 46 34             	mov    0x34(%rsi),%eax
    796b:	49 39 81 a0 00 00 00 	cmp    %rax,0xa0(%r9)
    7972:	0f 86 79 03 00 00    	jbe    7cf1 <rc_insert_result+0x6b1>
    7978:	49 8b 89 98 00 00 00 	mov    0x98(%r9),%rcx
    797f:	48 c1 e0 04          	shl    $0x4,%rax
    7983:	48 39 34 01          	cmp    %rsi,(%rcx,%rax,1)
    7987:	0f 85 64 03 00 00    	jne    7cf1 <rc_insert_result+0x6b1>
    798d:	48 01 c1             	add    %rax,%rcx
    7990:	48 8b 41 08          	mov    0x8(%rcx),%rax
    7994:	48 85 c0             	test   %rax,%rax
    7997:	74 35                	je     79ce <rc_insert_result+0x38e>
    7999:	83 78 40 00          	cmpl   $0x0,0x40(%rax)
    799d:	75 2f                	jne    79ce <rc_insert_result+0x38e>
    799f:	80 78 45 00          	cmpb   $0x0,0x45(%rax)
    79a3:	75 29                	jne    79ce <rc_insert_result+0x38e>
    79a5:	49 8b 86 08 16 00 00 	mov    0x1608(%r14),%rax
    79ac:	48 89 b0 10 01 00 00 	mov    %rsi,0x110(%rax)
    79b3:	48 85 ff             	test   %rdi,%rdi
    79b6:	74 10                	je     79c8 <rc_insert_result+0x388>
    79b8:	48 b8 00 00 00 00 00 	movabs $0x4000000000000000,%rax
    79bf:	00 00 40 
    79c2:	48 85 47 f0          	test   %rax,-0x10(%rdi)
    79c6:	75 06                	jne    79ce <rc_insert_result+0x38e>
    79c8:	45 3b 6e 70          	cmp    0x70(%r14),%r13d
    79cc:	76 58                	jbe    7a26 <rc_insert_result+0x3e6>
    79ce:	49 83 f8 01          	cmp    $0x1,%r8
    79d2:	b9 03 00 00 00       	mov    $0x3,%ecx
    79d7:	48 83 d9 00          	sbb    $0x0,%rcx
    79db:	48 8d b5 20 ff ff ff 	lea    -0xe0(%rbp),%rsi
    79e2:	48 8d 95 c0 fe ff ff 	lea    -0x140(%rbp),%rdx
    79e9:	4c 89 f7             	mov    %r14,%rdi
    79ec:	e8 2f c7 00 00       	call   14120 <__wrap_myl_rc_value_retain_many>
    79f1:	85 c0                	test   %eax,%eax
    79f3:	74 67                	je     7a5c <rc_insert_result+0x41c>
    79f5:	4c 89 f7             	mov    %r14,%rdi
    79f8:	89 c6                	mov    %eax,%esi
    79fa:	e8 31 37 00 00       	call   b130 <myl_rc_record_failure>
    79ff:	31 db                	xor    %ebx,%ebx
    7a01:	e9 45 02 00 00       	jmp    7c4b <rc_insert_result+0x60b>
    7a06:	4c 89 f7             	mov    %r14,%rdi
    7a09:	44 89 ea             	mov    %r13d,%edx
    7a0c:	e8 af df ff ff       	call   59c0 <myl_native_text_own_at>
    7a11:	48 85 c0             	test   %rax,%rax
    7a14:	0f 84 42 02 00 00    	je     7c5c <rc_insert_result+0x61c>
    7a1a:	49 89 c2             	mov    %rax,%r10
    7a1d:	49 89 04 24          	mov    %rax,(%r12)
    7a21:	e9 7b fd ff ff       	jmp    77a1 <rc_insert_result+0x161>
    7a26:	e8 15 2a 00 00       	call   a440 <myl_rc_owner_take>
    7a2b:	85 c0                	test   %eax,%eax
    7a2d:	75 c6                	jne    79f5 <rc_insert_result+0x3b5>
    7a2f:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
    7a33:	4c 89 e6             	mov    %r12,%rsi
    7a36:	48 8b 55 d0          	mov    -0x30(%rbp),%rdx
    7a3a:	e8 61 96 ff ff       	call   10a0 <memcpy@plt>
    7a3f:	48 83 7d c0 00       	cmpq   $0x0,-0x40(%rbp)
    7a44:	74 16                	je     7a5c <rc_insert_result+0x41c>
    7a46:	49 8b 77 18          	mov    0x18(%r15),%rsi
    7a4a:	4c 01 e6             	add    %r12,%rsi
    7a4d:	49 8b 47 10          	mov    0x10(%r15),%rax
    7a51:	48 8b 10             	mov    (%rax),%rdx
    7a54:	48 89 df             	mov    %rbx,%rdi
    7a57:	e8 44 96 ff ff       	call   10a0 <memcpy@plt>
    7a5c:	41 8b 47 24          	mov    0x24(%r15),%eax
    7a60:	83 f8 02             	cmp    $0x2,%eax
    7a63:	4c 89 65 a0          	mov    %r12,-0x60(%rbp)
    7a67:	48 89 5d 90          	mov    %rbx,-0x70(%rbp)
    7a6b:	74 13                	je     7a80 <rc_insert_result+0x440>
    7a6d:	83 f8 01             	cmp    $0x1,%eax
    7a70:	4c 8b 6d b0          	mov    -0x50(%rbp),%r13
    7a74:	74 04                	je     7a7a <rc_insert_result+0x43a>
    7a76:	85 c0                	test   %eax,%eax
    7a78:	75 45                	jne    7abf <rc_insert_result+0x47f>
    7a7a:	49 8b 45 00          	mov    0x0(%r13),%rax
    7a7e:	eb 69                	jmp    7ae9 <rc_insert_result+0x4a9>
    7a80:	49 8b 47 08          	mov    0x8(%r15),%rax
    7a84:	48 8b 00             	mov    (%rax),%rax
    7a87:	48 c7 45 98 00 00 00 	movq   $0x0,-0x68(%rbp)
    7a8e:	00 
    7a8f:	f3 48 0f b8 c8       	popcnt %rax,%rcx
    7a94:	83 f9 01             	cmp    $0x1,%ecx
    7a97:	4c 8b 6d b0          	mov    -0x50(%rbp),%r13
    7a9b:	75 2f                	jne    7acc <rc_insert_result+0x48c>
    7a9d:	f3 48 0f bc c8       	tzcnt  %rax,%rcx
    7aa2:	48 83 f9 03          	cmp    $0x3,%rcx
    7aa6:	77 24                	ja     7acc <rc_insert_result+0x48c>
    7aa8:	48 8d 05 f9 df 00 00 	lea    0xdff9(%rip),%rax        # 15aa8 <rc_list_shape+0xd8>
    7aaf:	48 63 0c 88          	movslq (%rax,%rcx,4),%rcx
    7ab3:	48 01 c1             	add    %rax,%rcx
    7ab6:	ff e1                	jmp    *%rcx
    7ab8:	41 0f b6 45 00       	movzbl 0x0(%r13),%eax
    7abd:	eb 2a                	jmp    7ae9 <rc_insert_result+0x4a9>
    7abf:	41 b4 01             	mov    $0x1,%r12b
    7ac2:	48 c7 45 a8 00 00 00 	movq   $0x0,-0x58(%rbp)
    7ac9:	00 
    7aca:	eb 46                	jmp    7b12 <rc_insert_result+0x4d2>
    7acc:	48 83 f8 08          	cmp    $0x8,%rax
    7ad0:	ba 08 00 00 00       	mov    $0x8,%edx
    7ad5:	48 0f 42 d0          	cmovb  %rax,%rdx
    7ad9:	48 8d 7d 98          	lea    -0x68(%rbp),%rdi
    7add:	4c 89 ee             	mov    %r13,%rsi
    7ae0:	e8 bb 95 ff ff       	call   10a0 <memcpy@plt>
    7ae5:	48 8b 45 98          	mov    -0x68(%rbp),%rax
    7ae9:	41 83 bf f8 00 00 00 	cmpl   $0x2,0xf8(%r15)
    7af0:	02 
    7af1:	48 89 45 a8          	mov    %rax,-0x58(%rbp)
    7af5:	75 18                	jne    7b0f <rc_insert_result+0x4cf>
    7af7:	49 39 87 e0 00 00 00 	cmp    %rax,0xe0(%r15)
    7afe:	75 0f                	jne    7b0f <rc_insert_result+0x4cf>
    7b00:	41 8b 9f f4 00 00 00 	mov    0xf4(%r15),%ebx
    7b07:	41 b6 01             	mov    $0x1,%r14b
    7b0a:	45 31 e4             	xor    %r12d,%r12d
    7b0d:	eb 17                	jmp    7b26 <rc_insert_result+0x4e6>
    7b0f:	45 31 e4             	xor    %r12d,%r12d
    7b12:	4c 8b 7d c8          	mov    -0x38(%rbp),%r15
    7b16:	4c 89 ff             	mov    %r15,%rdi
    7b19:	4c 89 ee             	mov    %r13,%rsi
    7b1c:	e8 3f 09 00 00       	call   8460 <hash_key>
    7b21:	89 c3                	mov    %eax,%ebx
    7b23:	45 31 f6             	xor    %r14d,%r14d
    7b26:	48 8b 55 d0          	mov    -0x30(%rbp),%rdx
    7b2a:	48 c1 e3 20          	shl    $0x20,%rbx
    7b2e:	48 8d 43 01          	lea    0x1(%rbx),%rax
    7b32:	49 89 44 15 f8       	mov    %rax,-0x8(%r13,%rdx,1)
    7b37:	49 8b 07             	mov    (%r15),%rax
    7b3a:	4c 89 ee             	mov    %r13,%rsi
    7b3d:	4c 8b 28             	mov    (%rax),%r13
    7b40:	49 8b 7f 30          	mov    0x30(%r15),%rdi
    7b44:	49 0f af fd          	imul   %r13,%rdi
    7b48:	48 03 78 20          	add    0x20(%rax),%rdi
    7b4c:	e8 4f 95 ff ff       	call   10a0 <memcpy@plt>
    7b51:	49 8b 07             	mov    (%r15),%rax
    7b54:	48 ff 00             	incq   (%rax)
    7b57:	48 ff 40 10          	incq   0x10(%rax)
    7b5b:	49 8b 8f d8 00 00 00 	mov    0xd8(%r15),%rcx
    7b62:	48 85 c9             	test   %rcx,%rcx
    7b65:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
    7b69:	74 5a                	je     7bc5 <rc_insert_result+0x585>
    7b6b:	49 8d 45 01          	lea    0x1(%r13),%rax
    7b6f:	48 09 d8             	or     %rbx,%rax
    7b72:	45 84 f6             	test   %r14b,%r14b
    7b75:	74 17                	je     7b8e <rc_insert_result+0x54e>
    7b77:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
    7b7b:	48 8b 8a d0 00 00 00 	mov    0xd0(%rdx),%rcx
    7b82:	8b 92 f0 00 00 00    	mov    0xf0(%rdx),%edx
    7b88:	48 89 04 d1          	mov    %rax,(%rcx,%rdx,8)
    7b8c:	eb 37                	jmp    7bc5 <rc_insert_result+0x585>
    7b8e:	48 ff c9             	dec    %rcx
    7b91:	48 89 c6             	mov    %rax,%rsi
    7b94:	48 c1 ee 20          	shr    $0x20,%rsi
    7b98:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
    7b9c:	48 8b 92 d0 00 00 00 	mov    0xd0(%rdx),%rdx
    7ba3:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
    7baa:	84 00 00 00 00 00 
    7bb0:	49 89 f0             	mov    %rsi,%r8
    7bb3:	49 21 c8             	and    %rcx,%r8
    7bb6:	49 8d 70 01          	lea    0x1(%r8),%rsi
    7bba:	4a 83 3c c2 00       	cmpq   $0x0,(%rdx,%r8,8)
    7bbf:	75 ef                	jne    7bb0 <rc_insert_result+0x570>
    7bc1:	4a 89 04 c2          	mov    %rax,(%rdx,%r8,8)
    7bc5:	45 84 e4             	test   %r12b,%r12b
    7bc8:	74 1f                	je     7be9 <rc_insert_result+0x5a9>
    7bca:	48 8b 4d c8          	mov    -0x38(%rbp),%rcx
    7bce:	48 8d 81 e0 00 00 00 	lea    0xe0(%rcx),%rax
    7bd5:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    7bd9:	c5 f8 11 00          	vmovups %xmm0,(%rax)
    7bdd:	48 c7 40 10 00 00 00 	movq   $0x0,0x10(%rax)
    7be4:	00 
    7be5:	31 c0                	xor    %eax,%eax
    7be7:	eb 26                	jmp    7c0f <rc_insert_result+0x5cf>
    7be9:	48 8b 4d c8          	mov    -0x38(%rbp),%rcx
    7bed:	48 8b 45 a8          	mov    -0x58(%rbp),%rax
    7bf1:	48 89 81 e0 00 00 00 	mov    %rax,0xe0(%rcx)
    7bf8:	4c 89 a9 e8 00 00 00 	mov    %r13,0xe8(%rcx)
    7bff:	48 c7 81 f0 00 00 00 	movq   $0x0,0xf0(%rcx)
    7c06:	00 00 00 00 
    7c0a:	b8 01 00 00 00       	mov    $0x1,%eax
    7c0f:	4c 8b 75 b8          	mov    -0x48(%rbp),%r14
    7c13:	4c 8b 65 a0          	mov    -0x60(%rbp),%r12
    7c17:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    7c1b:	c5 f8 11 81 08 01 00 	vmovups %xmm0,0x108(%rcx)
    7c22:	00 
    7c23:	c5 f8 11 81 fc 00 00 	vmovups %xmm0,0xfc(%rcx)
    7c2a:	00 
    7c2b:	89 81 f8 00 00 00    	mov    %eax,0xf8(%rcx)
    7c31:	bb 01 00 00 00       	mov    $0x1,%ebx
    7c36:	48 85 ff             	test   %rdi,%rdi
    7c39:	74 10                	je     7c4b <rc_insert_result+0x60b>
    7c3b:	48 8b 41 10          	mov    0x10(%rcx),%rax
    7c3f:	48 8b 10             	mov    (%rax),%rdx
    7c42:	48 8b 75 90          	mov    -0x70(%rbp),%rsi
    7c46:	e8 55 94 ff ff       	call   10a0 <memcpy@plt>
    7c4b:	48 8b 75 88          	mov    -0x78(%rbp),%rsi
    7c4f:	48 85 f6             	test   %rsi,%rsi
    7c52:	74 08                	je     7c5c <rc_insert_result+0x61c>
    7c54:	4c 89 f7             	mov    %r14,%rdi
    7c57:	e8 94 3a 00 00       	call   b6f0 <myl_rc_owner_release>
    7c5c:	48 8d 85 40 fd ff ff 	lea    -0x2c0(%rbp),%rax
    7c63:	49 39 c4             	cmp    %rax,%r12
    7c66:	74 0b                	je     7c73 <rc_insert_result+0x633>
    7c68:	4c 89 f7             	mov    %r14,%rdi
    7c6b:	4c 89 e6             	mov    %r12,%rsi
    7c6e:	e8 7d 3a 00 00       	call   b6f0 <myl_rc_owner_release>
    7c73:	89 d8                	mov    %ebx,%eax
    7c75:	48 81 c4 98 02 00 00 	add    $0x298,%rsp
    7c7c:	5b                   	pop    %rbx
    7c7d:	41 5c                	pop    %r12
    7c7f:	41 5d                	pop    %r13
    7c81:	41 5e                	pop    %r14
    7c83:	41 5f                	pop    %r15
    7c85:	5d                   	pop    %rbp
    7c86:	c3                   	ret
    7c87:	49 8d 3c 14          	lea    (%r12,%rdx,1),%rdi
    7c8b:	4c 89 e6             	mov    %r12,%rsi
    7c8e:	49 89 de             	mov    %rbx,%r14
    7c91:	4c 89 c3             	mov    %r8,%rbx
    7c94:	e8 07 94 ff ff       	call   10a0 <memcpy@plt>
    7c99:	48 85 db             	test   %rbx,%rbx
    7c9c:	4c 89 f3             	mov    %r14,%rbx
    7c9f:	0f 85 a1 fd ff ff    	jne    7a46 <rc_insert_result+0x406>
    7ca5:	e9 b2 fd ff ff       	jmp    7a5c <rc_insert_result+0x41c>
    7caa:	41 8b 45 00          	mov    0x0(%r13),%eax
    7cae:	e9 36 fe ff ff       	jmp    7ae9 <rc_insert_result+0x4a9>
    7cb3:	41 0f b7 45 00       	movzwl 0x0(%r13),%eax
    7cb8:	e9 2c fe ff ff       	jmp    7ae9 <rc_insert_result+0x4a9>
    7cbd:	4c 89 f7             	mov    %r14,%rdi
    7cc0:	e8 84 94 ff ff       	call   1149 <myl_rc_binding_find_slow>
    7cc5:	48 89 c1             	mov    %rax,%rcx
    7cc8:	49 8b 86 08 16 00 00 	mov    0x1608(%r14),%rax
    7ccf:	4c 8b 88 a0 00 00 00 	mov    0xa0(%rax),%r9
    7cd6:	e9 08 fb ff ff       	jmp    77e3 <rc_insert_result+0x1a3>
    7cdb:	4c 89 f7             	mov    %r14,%rdi
    7cde:	e8 66 94 ff ff       	call   1149 <myl_rc_binding_find_slow>
    7ce3:	48 85 c9             	test   %rcx,%rcx
    7ce6:	0f 85 2c fb ff ff    	jne    7818 <rc_insert_result+0x1d8>
    7cec:	e8 4f 93 ff ff       	call   1040 <abort@plt>
    7cf1:	48 89 f9             	mov    %rdi,%rcx
    7cf4:	4c 89 f7             	mov    %r14,%rdi
    7cf7:	e8 4d 94 ff ff       	call   1149 <myl_rc_binding_find_slow>
    7cfc:	48 89 cf             	mov    %rcx,%rdi
    7cff:	48 85 c0             	test   %rax,%rax
    7d02:	0f 85 91 fc ff ff    	jne    7999 <rc_insert_result+0x359>
    7d08:	e9 c1 fc ff ff       	jmp    79ce <rc_insert_result+0x38e>

Disassembly of section .fini:
