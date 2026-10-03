
.tmp-lox-sweep/bin/final-sweep-llvm:     file format elf64-x86-64


Disassembly of section .text:

00000000010d9720 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3>:
 10d9720:	53                   	push   %rbx
 10d9721:	48 83 ec 60          	sub    $0x60,%rsp
 10d9725:	48 83 7a 08 00       	cmpq   $0x0,0x8(%rdx)
 10d972a:	0f 84 eb 00 00 00    	je     10d981b <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0xfb>
 10d9730:	4c 8b 1a             	mov    (%rdx),%r11
 10d9733:	4d 8b 0b             	mov    (%r11),%r9
 10d9736:	4d 85 c9             	test   %r9,%r9
 10d9739:	0f 88 3d 01 00 00    	js     10d987c <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x15c>
 10d973f:	49 8d 41 ff          	lea    -0x1(%r9),%rax
 10d9743:	49 ba ff ff ff ff fe 	movabs $0xfffffffeffffffff,%r10
 10d974a:	ff ff ff 
 10d974d:	4b 8d 1c 11          	lea    (%r9,%r10,1),%rbx
 10d9751:	49 ff c2             	inc    %r10
 10d9754:	4c 39 d3             	cmp    %r10,%rbx
 10d9757:	0f 82 2f 01 00 00    	jb     10d988c <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x16c>
 10d975d:	0f 1f 00             	nopl   (%rax)
 10d9760:	49 21 c0             	and    %rax,%r8
 10d9763:	4d 89 c2             	mov    %r8,%r10
 10d9766:	4d 39 c8             	cmp    %r9,%r8
 10d9769:	72 1e                	jb     10d9789 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x69>
 10d976b:	4d 89 c2             	mov    %r8,%r10
 10d976e:	4d 85 c0             	test   %r8,%r8
 10d9771:	79 0d                	jns    10d9780 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x60>
 10d9773:	4d 85 c9             	test   %r9,%r9
 10d9776:	0f 88 ed 00 00 00    	js     10d9869 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x149>
 10d977c:	4f 8d 14 01          	lea    (%r9,%r8,1),%r10
 10d9780:	4d 39 ca             	cmp    %r9,%r10
 10d9783:	0f 83 cf 00 00 00    	jae    10d9858 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x138>
 10d9789:	4d 8b 4b 20          	mov    0x20(%r11),%r9
 10d978d:	49 c1 e2 05          	shl    $0x5,%r10
 10d9791:	c4 81 7c 10 04 11    	vmovups (%r9,%r10,1),%ymm0
 10d9797:	c5 fc 11 44 24 20    	vmovups %ymm0,0x20(%rsp)
 10d979d:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 10d97a2:	49 83 f9 ff          	cmp    $0xffffffffffffffff,%r9
 10d97a6:	74 08                	je     10d97b0 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x90>
 10d97a8:	49 39 c9             	cmp    %rcx,%r9
 10d97ab:	75 1e                	jne    10d97cb <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0xab>
 10d97ad:	eb 3a                	jmp    10d97e9 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0xc9>
 10d97af:	90                   	nop
 10d97b0:	c5 fc 10 44 24 20    	vmovups 0x20(%rsp),%ymm0
 10d97b6:	c5 fc 11 44 24 40    	vmovups %ymm0,0x40(%rsp)
 10d97bc:	44 8b 4c 24 50       	mov    0x50(%rsp),%r9d
 10d97c1:	45 8d 51 ff          	lea    -0x1(%r9),%r10d
 10d97c5:	41 83 fa 03          	cmp    $0x3,%r10d
 10d97c9:	73 4b                	jae    10d9816 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0xf6>
 10d97cb:	4d 89 c2             	mov    %r8,%r10
 10d97ce:	49 ff c2             	inc    %r10
 10d97d1:	70 70                	jo     10d9843 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x123>
 10d97d3:	4c 8b 1a             	mov    (%rdx),%r11
 10d97d6:	4d 8b 0b             	mov    (%r11),%r9
 10d97d9:	4d 89 d0             	mov    %r10,%r8
 10d97dc:	49 21 c0             	and    %rax,%r8
 10d97df:	4d 89 c2             	mov    %r8,%r10
 10d97e2:	4d 39 c8             	cmp    %r9,%r8
 10d97e5:	73 84                	jae    10d976b <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x4b>
 10d97e7:	eb a0                	jmp    10d9789 <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x69>
 10d97e9:	c5 f8 28 44 24 30    	vmovaps 0x30(%rsp),%xmm0
 10d97ef:	c5 f8 11 44 24 10    	vmovups %xmm0,0x10(%rsp)
 10d97f5:	c7 07 01 00 00 00    	movl   $0x1,(%rdi)
 10d97fb:	c5 f8 10 44 24 0c    	vmovups 0xc(%rsp),%xmm0
 10d9801:	c5 f8 11 47 04       	vmovups %xmm0,0x4(%rdi)
 10d9806:	8b 44 24 1c          	mov    0x1c(%rsp),%eax
 10d980a:	89 47 14             	mov    %eax,0x14(%rdi)
 10d980d:	48 83 c4 60          	add    $0x60,%rsp
 10d9811:	5b                   	pop    %rbx
 10d9812:	c5 f8 77             	vzeroupper
 10d9815:	c3                   	ret
 10d9816:	45 85 c9             	test   %r9d,%r9d
 10d9819:	75 0f                	jne    10d982a <myl_f_05c0395f99e3d95f11848a23036537b613947380b701bcd66a0fa57cf17796f3+0x10a>
 10d981b:	c7 07 00 00 00 00    	movl   $0x0,(%rdi)
 10d9821:	48 83 c4 60          	add    $0x60,%rsp
 10d9825:	5b                   	pop    %rbx
 10d9826:	c5 f8 77             	vzeroupper
 10d9829:	c3                   	ret
 10d982a:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 10d982e:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
 10d9832:	48 c7 47 10 00 00 00 	movq   $0x0,0x10(%rdi)
 10d9839:	00 
 10d983a:	48 83 c4 60          	add    $0x60,%rsp
 10d983e:	5b                   	pop    %rbx
 10d983f:	c5 f8 77             	vzeroupper
 10d9842:	c3                   	ret
 10d9843:	b9 01 00 00 00       	mov    $0x1,%ecx
 10d9848:	48 89 f7             	mov    %rsi,%rdi
 10d984b:	31 f6                	xor    %esi,%esi
 10d984d:	4c 89 c2             	mov    %r8,%rdx
 10d9850:	c5 f8 77             	vzeroupper
 10d9853:	e8 f8 6d 0a 00       	call   1180650 <myl_qbe_fail_overflow_op>
 10d9858:	48 89 f7             	mov    %rsi,%rdi
 10d985b:	4c 89 d6             	mov    %r10,%rsi
 10d985e:	4c 89 ca             	mov    %r9,%rdx
 10d9861:	c5 f8 77             	vzeroupper
 10d9864:	e8 27 6d 0a 00       	call   1180590 <myl_qbe_fail_normalized_index_bounds>
 10d9869:	ba 40 01 00 00       	mov    $0x140,%edx
 10d986e:	48 89 f7             	mov    %rsi,%rdi
 10d9871:	4c 89 ce             	mov    %r9,%rsi
 10d9874:	c5 f8 77             	vzeroupper
 10d9877:	e8 34 6e 0a 00       	call   11806b0 <myl_qbe_fail_cast>
 10d987c:	ba 40 01 00 00       	mov    $0x140,%edx
 10d9881:	48 89 f7             	mov    %rsi,%rdi
 10d9884:	4c 89 ce             	mov    %r9,%rsi
 10d9887:	e8 24 6e 0a 00       	call   11806b0 <myl_qbe_fail_cast>
 10d988c:	ba 20 00 00 00       	mov    $0x20,%edx
 10d9891:	48 89 f7             	mov    %rsi,%rdi
 10d9894:	48 89 c6             	mov    %rax,%rsi
 10d9897:	e8 14 6e 0a 00       	call   11806b0 <myl_qbe_fail_cast>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
