
.tmp/llvm-parity-audit-20260920/probes/root-clean.bin:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .text:

00000000004064b0 <sexpr.printer::push_node>:
  4064b0:	55                   	push   %rbp
  4064b1:	41 57                	push   %r15
  4064b3:	41 56                	push   %r14
  4064b5:	41 55                	push   %r13
  4064b7:	41 54                	push   %r12
  4064b9:	53                   	push   %rbx
  4064ba:	48 81 ec a8 01 00 00 	sub    $0x1a8,%rsp
  4064c1:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
  4064c5:	c5 f8 29 44 24 50    	vmovaps %xmm0,0x50(%rsp)
  4064cb:	48 c7 44 24 60 00 00 	movq   $0x0,0x60(%rsp)
  4064d2:	00 00 
  4064d4:	48 89 cd             	mov    %rcx,%rbp
  4064d7:	49 89 d7             	mov    %rdx,%r15
  4064da:	48 89 f3             	mov    %rsi,%rbx
  4064dd:	49 89 fe             	mov    %rdi,%r14
  4064e0:	c5 f8 29 44 24 30    	vmovaps %xmm0,0x30(%rsp)
  4064e6:	48 c7 44 24 40 00 00 	movq   $0x0,0x40(%rsp)
  4064ed:	00 00 
  4064ef:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
  4064f3:	c5 fc 11 8c 24 80 00 	vmovups %ymm1,0x80(%rsp)
  4064fa:	00 00 
  4064fc:	c5 f8 29 44 24 10    	vmovaps %xmm0,0x10(%rsp)
  406502:	48 c7 44 24 20 00 00 	movq   $0x0,0x20(%rsp)
  406509:	00 00 
  40650b:	c5 f8 77             	vzeroupper
  40650e:	e8 7d 7e 00 00       	call   40e390 <myl_qbe_heap>
  406513:	41 8b 0f             	mov    (%r15),%ecx
  406516:	48 83 f9 05          	cmp    $0x5,%rcx
  40651a:	0f 87 b3 04 00 00    	ja     4069d3 <sexpr.printer::push_node+0x523>
  406520:	49 8d 47 08          	lea    0x8(%r15),%rax
  406524:	48 8d 15 a5 1c 01 00 	lea    0x11ca5(%rip),%rdx        # 4181d0 <_fini+0xa6c>
  40652b:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
  40652f:	48 01 d1             	add    %rdx,%rcx
  406532:	ff e1                	jmp    *%rcx
  406534:	4c 8b 20             	mov    (%rax),%r12
  406537:	49 83 3c 24 00       	cmpq   $0x0,(%r12)
  40653c:	0f 84 e5 02 00 00    	je     406827 <sexpr.printer::push_node+0x377>
  406542:	48 c7 c0 a0 58 42 00 	mov    $0x4258a0,%rax
  406549:	4c 8b 38             	mov    (%rax),%r15
  40654c:	4c 89 f7             	mov    %r14,%rdi
  40654f:	e8 3c 7e 00 00       	call   40e390 <myl_qbe_heap>
  406554:	48 8b 33             	mov    (%rbx),%rsi
  406557:	4d 8b 07             	mov    (%r15),%r8
  40655a:	48 89 c7             	mov    %rax,%rdi
  40655d:	4c 89 fa             	mov    %r15,%rdx
  406560:	31 c9                	xor    %ecx,%ecx
  406562:	e8 79 d4 00 00       	call   4139e0 <myl_native_bytes_buffer_append_range>
  406567:	4c 89 f7             	mov    %r14,%rdi
  40656a:	e8 21 7e 00 00       	call   40e390 <myl_qbe_heap>
  40656f:	49 83 3c 24 00       	cmpq   $0x0,(%r12)
  406574:	4c 89 e7             	mov    %r12,%rdi
  406577:	4c 89 24 24          	mov    %r12,(%rsp)
  40657b:	7e 61                	jle    4065de <sexpr.printer::push_node+0x12e>
  40657d:	41 bd 02 00 00 00    	mov    $0x2,%r13d
  406583:	45 31 ff             	xor    %r15d,%r15d
  406586:	4c 8d a4 24 68 01 00 	lea    0x168(%rsp),%r12
  40658d:	00 
  40658e:	66 90                	xchg   %ax,%ax
  406590:	4c 89 fe             	mov    %r15,%rsi
  406593:	4c 89 e2             	mov    %r12,%rdx
  406596:	e8 25 22 00 00       	call   4087c0 <__wrap_myl_native_list_get>
  40659b:	4c 89 f7             	mov    %r14,%rdi
  40659e:	4c 89 e6             	mov    %r12,%rsi
  4065a1:	31 d2                	xor    %edx,%edx
  4065a3:	e8 98 c9 ff ff       	call   402f40 <sexpr.printer::estimate_width>
  4065a8:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  4065ad:	48 89 54 24 78       	mov    %rdx,0x78(%rsp)
  4065b2:	83 f8 01             	cmp    $0x1,%eax
  4065b5:	0f 85 bd 02 00 00    	jne    406878 <sexpr.printer::push_node+0x3c8>
  4065bb:	49 83 ff 01          	cmp    $0x1,%r15
  4065bf:	49 83 dd ff          	sbb    $0xffffffffffffffff,%r13
  4065c3:	4c 03 6c 24 78       	add    0x78(%rsp),%r13
  4065c8:	49 83 fd 48          	cmp    $0x48,%r13
  4065cc:	0f 8f a6 02 00 00    	jg     406878 <sexpr.printer::push_node+0x3c8>
  4065d2:	49 ff c7             	inc    %r15
  4065d5:	48 8b 3c 24          	mov    (%rsp),%rdi
  4065d9:	4c 3b 3f             	cmp    (%rdi),%r15
  4065dc:	7c b2                	jl     406590 <sexpr.printer::push_node+0xe0>
  4065de:	48 83 3f 00          	cmpq   $0x0,(%rdi)
  4065e2:	0f 8e c6 03 00 00    	jle    4069ae <sexpr.printer::push_node+0x4fe>
  4065e8:	49 89 ec             	mov    %rbp,%r12
  4065eb:	49 83 c4 02          	add    $0x2,%r12
  4065ef:	4c 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%r15
  4065f6:	00 
  4065f7:	49 89 fd             	mov    %rdi,%r13
  4065fa:	31 f6                	xor    %esi,%esi
  4065fc:	4c 89 fa             	mov    %r15,%rdx
  4065ff:	e8 bc 21 00 00       	call   4087c0 <__wrap_myl_native_list_get>
  406604:	4c 89 f7             	mov    %r14,%rdi
  406607:	48 89 de             	mov    %rbx,%rsi
  40660a:	4c 89 fa             	mov    %r15,%rdx
  40660d:	4c 89 e5             	mov    %r12,%rbp
  406610:	4c 89 e1             	mov    %r12,%rcx
  406613:	e8 98 fe ff ff       	call   4064b0 <sexpr.printer::push_node>
  406618:	49 83 7d 00 02       	cmpq   $0x2,0x0(%r13)
  40661d:	0f 8c 8b 03 00 00    	jl     4069ae <sexpr.printer::push_node+0x4fe>
  406623:	41 bf 01 00 00 00    	mov    $0x1,%r15d
  406629:	4c 8d a4 24 a8 00 00 	lea    0xa8(%rsp),%r12
  406630:	00 
  406631:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  406638:	0f 1f 84 00 00 00 00 
  40663f:	00 
  406640:	48 c7 c0 a8 58 42 00 	mov    $0x4258a8,%rax
  406647:	4c 8b 28             	mov    (%rax),%r13
  40664a:	4c 89 f7             	mov    %r14,%rdi
  40664d:	e8 3e 7d 00 00       	call   40e390 <myl_qbe_heap>
  406652:	48 8b 33             	mov    (%rbx),%rsi
  406655:	4d 8b 45 00          	mov    0x0(%r13),%r8
  406659:	48 89 c7             	mov    %rax,%rdi
  40665c:	4c 89 ea             	mov    %r13,%rdx
  40665f:	4c 8b 2c 24          	mov    (%rsp),%r13
  406663:	31 c9                	xor    %ecx,%ecx
  406665:	e8 76 d3 00 00       	call   4139e0 <myl_native_bytes_buffer_append_range>
  40666a:	4c 89 ef             	mov    %r13,%rdi
  40666d:	4c 89 fe             	mov    %r15,%rsi
  406670:	4c 89 e2             	mov    %r12,%rdx
  406673:	e8 48 21 00 00       	call   4087c0 <__wrap_myl_native_list_get>
  406678:	4c 89 f7             	mov    %r14,%rdi
  40667b:	48 89 de             	mov    %rbx,%rsi
  40667e:	4c 89 e2             	mov    %r12,%rdx
  406681:	48 89 e9             	mov    %rbp,%rcx
  406684:	e8 27 fe ff ff       	call   4064b0 <sexpr.printer::push_node>
  406689:	49 ff c7             	inc    %r15
  40668c:	4d 3b 7d 00          	cmp    0x0(%r13),%r15
  406690:	7c ae                	jl     406640 <sexpr.printer::push_node+0x190>
  406692:	e9 17 03 00 00       	jmp    4069ae <sexpr.printer::push_node+0x4fe>
  406697:	4d 8b 67 08          	mov    0x8(%r15),%r12
  40669b:	c4 c1 7c 10 47 20    	vmovups 0x20(%r15),%ymm0
  4066a1:	c5 fc 11 84 24 80 00 	vmovups %ymm0,0x80(%rsp)
  4066a8:	00 00 
  4066aa:	8b 84 24 80 00 00 00 	mov    0x80(%rsp),%eax
  4066b1:	85 c0                	test   %eax,%eax
  4066b3:	0f 84 7a 01 00 00    	je     406833 <sexpr.printer::push_node+0x383>
  4066b9:	83 f8 01             	cmp    $0x1,%eax
  4066bc:	0f 85 11 03 00 00    	jne    4069d3 <sexpr.printer::push_node+0x523>
  4066c2:	c5 f8 10 84 24 88 00 	vmovups 0x88(%rsp),%xmm0
  4066c9:	00 00 
  4066cb:	c5 f8 29 44 24 10    	vmovaps %xmm0,0x10(%rsp)
  4066d1:	48 8b 84 24 98 00 00 	mov    0x98(%rsp),%rax
  4066d8:	00 
  4066d9:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  4066de:	4c 89 f7             	mov    %r14,%rdi
  4066e1:	c5 f8 77             	vzeroupper
  4066e4:	e8 a7 7c 00 00       	call   40e390 <myl_qbe_heap>
  4066e9:	4c 8b 7c 24 10       	mov    0x10(%rsp),%r15
  4066ee:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
  4066f3:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
  4066f8:	e9 bd 00 00 00       	jmp    4067ba <sexpr.printer::push_node+0x30a>
  4066fd:	c5 f8 10 00          	vmovups (%rax),%xmm0
  406701:	48 8b 40 10          	mov    0x10(%rax),%rax
  406705:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40670a:	c5 f8 29 44 24 30    	vmovaps %xmm0,0x30(%rsp)
  406710:	48 c7 c5 b8 58 42 00 	mov    $0x4258b8,%rbp
  406717:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
  40671b:	4c 89 f7             	mov    %r14,%rdi
  40671e:	e8 6d 7c 00 00       	call   40e390 <myl_qbe_heap>
  406723:	48 8b 33             	mov    (%rbx),%rsi
  406726:	4d 8b 07             	mov    (%r15),%r8
  406729:	48 89 c7             	mov    %rax,%rdi
  40672c:	4c 89 fa             	mov    %r15,%rdx
  40672f:	31 c9                	xor    %ecx,%ecx
  406731:	e8 aa d2 00 00       	call   4139e0 <myl_native_bytes_buffer_append_range>
  406736:	4c 89 f7             	mov    %r14,%rdi
  406739:	e8 52 7c 00 00       	call   40e390 <myl_qbe_heap>
  40673e:	4c 8b 7c 24 30       	mov    0x30(%rsp),%r15
  406743:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
  406748:	4c 8b 6c 24 40       	mov    0x40(%rsp),%r13
  40674d:	4c 89 f7             	mov    %r14,%rdi
  406750:	e8 3b 7c 00 00       	call   40e390 <myl_qbe_heap>
  406755:	48 8b 33             	mov    (%rbx),%rsi
  406758:	48 89 c7             	mov    %rax,%rdi
  40675b:	4c 89 fa             	mov    %r15,%rdx
  40675e:	4c 89 e1             	mov    %r12,%rcx
  406761:	4d 89 e8             	mov    %r13,%r8
  406764:	e8 77 d2 00 00       	call   4139e0 <myl_native_bytes_buffer_append_range>
  406769:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
  40676d:	e9 46 02 00 00       	jmp    4069b8 <sexpr.printer::push_node+0x508>
  406772:	4c 8b 38             	mov    (%rax),%r15
  406775:	4c 89 f7             	mov    %r14,%rdi
  406778:	e8 13 7c 00 00       	call   40e390 <myl_qbe_heap>
  40677d:	48 8b 33             	mov    (%rbx),%rsi
  406780:	48 89 c7             	mov    %rax,%rdi
  406783:	4c 89 fa             	mov    %r15,%rdx
  406786:	e8 e5 d3 00 00       	call   413b70 <myl_native_bytes_buffer_append_int>
  40678b:	e9 43 02 00 00       	jmp    4069d3 <sexpr.printer::push_node+0x523>
  406790:	c5 f8 10 00          	vmovups (%rax),%xmm0
  406794:	48 8b 40 10          	mov    0x10(%rax),%rax
  406798:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40679d:	c5 f8 29 44 24 50    	vmovaps %xmm0,0x50(%rsp)
  4067a3:	4c 89 f7             	mov    %r14,%rdi
  4067a6:	e8 e5 7b 00 00       	call   40e390 <myl_qbe_heap>
  4067ab:	4c 8b 7c 24 50       	mov    0x50(%rsp),%r15
  4067b0:	4c 8b 64 24 58       	mov    0x58(%rsp),%r12
  4067b5:	4c 8b 6c 24 60       	mov    0x60(%rsp),%r13
  4067ba:	4c 89 f7             	mov    %r14,%rdi
  4067bd:	e8 ce 7b 00 00       	call   40e390 <myl_qbe_heap>
  4067c2:	48 8b 33             	mov    (%rbx),%rsi
  4067c5:	48 89 c7             	mov    %rax,%rdi
  4067c8:	4c 89 fa             	mov    %r15,%rdx
  4067cb:	4c 89 e1             	mov    %r12,%rcx
  4067ce:	4d 89 e8             	mov    %r13,%r8
  4067d1:	e9 f8 01 00 00       	jmp    4069ce <sexpr.printer::push_node+0x51e>
  4067d6:	4c 8b 38             	mov    (%rax),%r15
  4067d9:	4c 89 f7             	mov    %r14,%rdi
  4067dc:	e8 af 7b 00 00       	call   40e390 <myl_qbe_heap>
  4067e1:	49 89 c4             	mov    %rax,%r12
  4067e4:	4c 89 f7             	mov    %r14,%rdi
  4067e7:	4c 89 fe             	mov    %r15,%rsi
  4067ea:	e8 d1 1e 00 00       	call   4086c0 <sexpr.printer::render_float>
  4067ef:	4c 89 e7             	mov    %r12,%rdi
  4067f2:	48 89 c6             	mov    %rax,%rsi
  4067f5:	e8 16 ce 00 00       	call   413610 <myl_native_bytes_encode>
  4067fa:	49 89 c7             	mov    %rax,%r15
  4067fd:	4c 8b 20             	mov    (%rax),%r12
  406800:	4c 89 f7             	mov    %r14,%rdi
  406803:	e8 88 7b 00 00       	call   40e390 <myl_qbe_heap>
  406808:	48 8b 33             	mov    (%rbx),%rsi
  40680b:	48 89 c7             	mov    %rax,%rdi
  40680e:	4c 89 fa             	mov    %r15,%rdx
  406811:	31 c9                	xor    %ecx,%ecx
  406813:	4d 89 e0             	mov    %r12,%r8
  406816:	e8 c5 d1 00 00       	call   4139e0 <myl_native_bytes_buffer_append_range>
  40681b:	48 c7 c0 c0 58 42 00 	mov    $0x4258c0,%rax
  406822:	e9 8e 01 00 00       	jmp    4069b5 <sexpr.printer::push_node+0x505>
  406827:	48 c7 c0 98 58 42 00 	mov    $0x425898,%rax
  40682e:	e9 82 01 00 00       	jmp    4069b5 <sexpr.printer::push_node+0x505>
  406833:	4c 89 f7             	mov    %r14,%rdi
  406836:	c5 f8 77             	vzeroupper
  406839:	e8 52 7b 00 00       	call   40e390 <myl_qbe_heap>
  40683e:	49 89 c7             	mov    %rax,%r15
  406841:	4c 89 f7             	mov    %r14,%rdi
  406844:	4c 89 e6             	mov    %r12,%rsi
  406847:	e8 74 1e 00 00       	call   4086c0 <sexpr.printer::render_float>
  40684c:	4c 89 ff             	mov    %r15,%rdi
  40684f:	48 89 c6             	mov    %rax,%rsi
  406852:	e8 b9 cd 00 00       	call   413610 <myl_native_bytes_encode>
  406857:	49 89 c7             	mov    %rax,%r15
  40685a:	4c 8b 20             	mov    (%rax),%r12
  40685d:	4c 89 f7             	mov    %r14,%rdi
  406860:	e8 2b 7b 00 00       	call   40e390 <myl_qbe_heap>
  406865:	48 8b 33             	mov    (%rbx),%rsi
  406868:	48 89 c7             	mov    %rax,%rdi
  40686b:	4c 89 fa             	mov    %r15,%rdx
  40686e:	31 c9                	xor    %ecx,%ecx
  406870:	4d 89 e0             	mov    %r12,%r8
  406873:	e9 56 01 00 00       	jmp    4069ce <sexpr.printer::push_node+0x51e>
  406878:	4c 8d bc 24 28 01 00 	lea    0x128(%rsp),%r15
  40687f:	00 
  406880:	4c 8b 24 24          	mov    (%rsp),%r12
  406884:	4c 89 e7             	mov    %r12,%rdi
  406887:	31 f6                	xor    %esi,%esi
  406889:	4c 89 fa             	mov    %r15,%rdx
  40688c:	e8 2f 1f 00 00       	call   4087c0 <__wrap_myl_native_list_get>
  406891:	48 89 6c 24 08       	mov    %rbp,0x8(%rsp)
  406896:	4c 8d 6d 02          	lea    0x2(%rbp),%r13
  40689a:	4c 89 f7             	mov    %r14,%rdi
  40689d:	48 89 de             	mov    %rbx,%rsi
  4068a0:	4c 89 fa             	mov    %r15,%rdx
  4068a3:	4c 89 e9             	mov    %r13,%rcx
  4068a6:	e8 05 fc ff ff       	call   4064b0 <sexpr.printer::push_node>
  4068ab:	49 83 3c 24 02       	cmpq   $0x2,(%r12)
  4068b0:	0f 8c f8 00 00 00    	jl     4069ae <sexpr.printer::push_node+0x4fe>
  4068b6:	48 83 44 24 08 42    	addq   $0x42,0x8(%rsp)
  4068bc:	bd 01 00 00 00       	mov    $0x1,%ebp
  4068c1:	4c 89 74 24 68       	mov    %r14,0x68(%rsp)
  4068c6:	eb 47                	jmp    40690f <sexpr.printer::push_node+0x45f>
  4068c8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
  4068cf:	00 
  4068d0:	4c 8b 3c 24          	mov    (%rsp),%r15
  4068d4:	4c 89 ff             	mov    %r15,%rdi
  4068d7:	48 89 ee             	mov    %rbp,%rsi
  4068da:	4c 8d a4 24 e8 00 00 	lea    0xe8(%rsp),%r12
  4068e1:	00 
  4068e2:	4c 89 e2             	mov    %r12,%rdx
  4068e5:	e8 d6 1e 00 00       	call   4087c0 <__wrap_myl_native_list_get>
  4068ea:	48 8b 7c 24 68       	mov    0x68(%rsp),%rdi
  4068ef:	48 89 de             	mov    %rbx,%rsi
  4068f2:	4c 89 e2             	mov    %r12,%rdx
  4068f5:	4d 89 f5             	mov    %r14,%r13
  4068f8:	49 89 fe             	mov    %rdi,%r14
  4068fb:	4c 89 e9             	mov    %r13,%rcx
  4068fe:	e8 ad fb ff ff       	call   4064b0 <sexpr.printer::push_node>
  406903:	48 ff c5             	inc    %rbp
  406906:	49 3b 2f             	cmp    (%r15),%rbp
  406909:	0f 8d 9f 00 00 00    	jge    4069ae <sexpr.printer::push_node+0x4fe>
  40690f:	48 c7 c0 e8 57 42 00 	mov    $0x4257e8,%rax
  406916:	4c 8b 38             	mov    (%rax),%r15
  406919:	4c 89 f7             	mov    %r14,%rdi
  40691c:	e8 6f 7a 00 00       	call   40e390 <myl_qbe_heap>
  406921:	48 8b 33             	mov    (%rbx),%rsi
  406924:	4d 8b 07             	mov    (%r15),%r8
  406927:	48 89 c7             	mov    %rax,%rdi
  40692a:	4c 89 fa             	mov    %r15,%rdx
  40692d:	31 c9                	xor    %ecx,%ecx
  40692f:	e8 ac d0 00 00       	call   4139e0 <myl_native_bytes_buffer_append_range>
  406934:	4c 89 f7             	mov    %r14,%rdi
  406937:	e8 54 7a 00 00       	call   40e390 <myl_qbe_heap>
  40693c:	4d 89 ee             	mov    %r13,%r14
  40693f:	4d 85 ed             	test   %r13,%r13
  406942:	78 8c                	js     4068d0 <sexpr.printer::push_node+0x420>
  406944:	49 89 c7             	mov    %rax,%r15
  406947:	48 c7 c0 c8 58 42 00 	mov    $0x4258c8,%rax
  40694e:	4c 8b 20             	mov    (%rax),%r12
  406951:	4d 89 f5             	mov    %r14,%r13
  406954:	49 83 fe 40          	cmp    $0x40,%r14
  406958:	72 33                	jb     40698d <sexpr.printer::push_node+0x4dd>
  40695a:	4c 8b 6c 24 08       	mov    0x8(%rsp),%r13
  40695f:	90                   	nop
  406960:	48 8b 33             	mov    (%rbx),%rsi
  406963:	41 b8 40 00 00 00    	mov    $0x40,%r8d
  406969:	4c 89 ff             	mov    %r15,%rdi
  40696c:	4c 89 e2             	mov    %r12,%rdx
  40696f:	31 c9                	xor    %ecx,%ecx
  406971:	e8 6a d0 00 00       	call   4139e0 <myl_native_bytes_buffer_append_range>
  406976:	83 f8 01             	cmp    $0x1,%eax
  406979:	0f 85 51 ff ff ff    	jne    4068d0 <sexpr.printer::push_node+0x420>
  40697f:	49 83 c5 c0          	add    $0xffffffffffffffc0,%r13
  406983:	49 83 fd 7f          	cmp    $0x7f,%r13
  406987:	7f d7                	jg     406960 <sexpr.printer::push_node+0x4b0>
  406989:	49 83 c5 c0          	add    $0xffffffffffffffc0,%r13
  40698d:	4d 85 ed             	test   %r13,%r13
  406990:	0f 84 3a ff ff ff    	je     4068d0 <sexpr.printer::push_node+0x420>
  406996:	48 8b 33             	mov    (%rbx),%rsi
  406999:	4c 89 ff             	mov    %r15,%rdi
  40699c:	4c 89 e2             	mov    %r12,%rdx
  40699f:	31 c9                	xor    %ecx,%ecx
  4069a1:	4d 89 e8             	mov    %r13,%r8
  4069a4:	e8 37 d0 00 00       	call   4139e0 <myl_native_bytes_buffer_append_range>
  4069a9:	e9 22 ff ff ff       	jmp    4068d0 <sexpr.printer::push_node+0x420>
  4069ae:	48 c7 c0 b0 58 42 00 	mov    $0x4258b0,%rax
  4069b5:	4c 8b 38             	mov    (%rax),%r15
  4069b8:	4c 89 f7             	mov    %r14,%rdi
  4069bb:	e8 d0 79 00 00       	call   40e390 <myl_qbe_heap>
  4069c0:	48 8b 33             	mov    (%rbx),%rsi
  4069c3:	4d 8b 07             	mov    (%r15),%r8
  4069c6:	48 89 c7             	mov    %rax,%rdi
  4069c9:	4c 89 fa             	mov    %r15,%rdx
  4069cc:	31 c9                	xor    %ecx,%ecx
  4069ce:	e8 0d d0 00 00       	call   4139e0 <myl_native_bytes_buffer_append_range>
  4069d3:	31 c0                	xor    %eax,%eax
  4069d5:	48 81 c4 a8 01 00 00 	add    $0x1a8,%rsp
  4069dc:	5b                   	pop    %rbx
  4069dd:	41 5c                	pop    %r12
  4069df:	41 5d                	pop    %r13
  4069e1:	41 5e                	pop    %r14
  4069e3:	41 5f                	pop    %r15
  4069e5:	5d                   	pop    %rbp
  4069e6:	c5 f8 77             	vzeroupper
  4069e9:	c3                   	ret

Disassembly of section .fini:
