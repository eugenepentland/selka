
.tmp/bench/armsset/maxperf/whole-o3.bin:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .text:

00000000004033c0 <sexpr.printer::estimate_width>:
  4033c0:	55                   	push   %rbp
  4033c1:	41 57                	push   %r15
  4033c3:	41 56                	push   %r14
  4033c5:	41 55                	push   %r13
  4033c7:	41 54                	push   %r12
  4033c9:	53                   	push   %rbx
  4033ca:	48 81 ec a8 01 00 00 	sub    $0x1a8,%rsp
  4033d1:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
  4033d5:	c5 f8 29 84 24 f0 00 	vmovaps %xmm0,0xf0(%rsp)
  4033dc:	00 00 
  4033de:	48 c7 84 24 00 01 00 	movq   $0x0,0x100(%rsp)
  4033e5:	00 00 00 00 00 
  4033ea:	49 89 d5             	mov    %rdx,%r13
  4033ed:	49 89 f6             	mov    %rsi,%r14
  4033f0:	49 89 fc             	mov    %rdi,%r12
  4033f3:	c5 f8 29 84 24 d0 00 	vmovaps %xmm0,0xd0(%rsp)
  4033fa:	00 00 
  4033fc:	48 c7 84 24 e0 00 00 	movq   $0x0,0xe0(%rsp)
  403403:	00 00 00 00 00 
  403408:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
  40340c:	c5 fc 11 8c 24 20 01 	vmovups %ymm1,0x120(%rsp)
  403413:	00 00 
  403415:	c5 f8 29 84 24 b0 00 	vmovaps %xmm0,0xb0(%rsp)
  40341c:	00 00 
  40341e:	48 c7 84 24 c0 00 00 	movq   $0x0,0xc0(%rsp)
  403425:	00 00 00 00 00 
  40342a:	c5 f8 77             	vzeroupper
  40342d:	e8 3e 81 01 00       	call   41b570 <myl_qbe_heap>
  403432:	49 83 fd 04          	cmp    $0x4,%r13
  403436:	7c 07                	jl     40343f <sexpr.printer::estimate_width+0x7f>
  403438:	31 c0                	xor    %eax,%eax
  40343a:	e9 d8 06 00 00       	jmp    403b17 <sexpr.printer::estimate_width+0x757>
  40343f:	48 89 c7             	mov    %rax,%rdi
  403442:	41 8b 06             	mov    (%r14),%eax
  403445:	48 83 f8 05          	cmp    $0x5,%rax
  403449:	0f 87 70 02 00 00    	ja     4036bf <sexpr.printer::estimate_width+0x2ff>
  40344f:	49 8d 56 08          	lea    0x8(%r14),%rdx
  403453:	48 8d 0d 86 1c 02 00 	lea    0x21c86(%rip),%rcx        # 4250e0 <_fini+0x79c>
  40345a:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
  40345e:	48 01 c8             	add    %rcx,%rax
  403461:	ff e0                	jmp    *%rax
  403463:	48 8b 2a             	mov    (%rdx),%rbp
  403466:	b8 01 00 00 00       	mov    $0x1,%eax
  40346b:	48 83 7d 00 00       	cmpq   $0x0,0x0(%rbp)
  403470:	0f 8e d8 05 00 00    	jle    403a4e <sexpr.printer::estimate_width+0x68e>
  403476:	48 89 bc 24 a0 00 00 	mov    %rdi,0xa0(%rsp)
  40347d:	00 
  40347e:	4c 89 a4 24 a8 00 00 	mov    %r12,0xa8(%rsp)
  403485:	00 
  403486:	49 ff c5             	inc    %r13
  403489:	41 bc 02 00 00 00    	mov    $0x2,%r12d
  40348f:	31 db                	xor    %ebx,%ebx
  403491:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  403498:	0f 1f 84 00 00 00 00 
  40349f:	00 
  4034a0:	48 89 ef             	mov    %rbp,%rdi
  4034a3:	48 89 de             	mov    %rbx,%rsi
  4034a6:	4c 8d bc 24 68 01 00 	lea    0x168(%rsp),%r15
  4034ad:	00 
  4034ae:	4c 89 fa             	mov    %r15,%rdx
  4034b1:	e8 ea 24 01 00       	call   4159a0 <__wrap_myl_native_list_get>
  4034b6:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
  4034bd:	00 
  4034be:	48 8b 40 10          	mov    0x10(%rax),%rax
  4034c2:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  4034c9:	00 
  4034ca:	4c 89 b4 24 88 00 00 	mov    %r14,0x88(%rsp)
  4034d1:	00 
  4034d2:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  4034d9:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  4034e0:	00 
  4034e1:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  4034e8:	00 
  4034e9:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  4034ee:	49 8d 46 08          	lea    0x8(%r14),%rax
  4034f2:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  4034f7:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  4034fe:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  403503:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  403508:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40350d:	48 89 6c 24 38       	mov    %rbp,0x38(%rsp)
  403512:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  403517:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40351c:	48 c7 c1 b0 20 43 00 	mov    $0x4320b0,%rcx
  403523:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
  403528:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40352d:	48 89 04 24          	mov    %rax,(%rsp)
  403531:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
  403536:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40353b:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  403540:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
  403545:	48 89 e0             	mov    %rsp,%rax
  403548:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40354d:	48 89 6c 24 58       	mov    %rbp,0x58(%rsp)
  403552:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  403557:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40355c:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
  403561:	48 8b bc 24 a8 00 00 	mov    0xa8(%rsp),%rdi
  403568:	00 
  403569:	4c 89 fe             	mov    %r15,%rsi
  40356c:	4c 89 ea             	mov    %r13,%rdx
  40356f:	e8 4c fe ff ff       	call   4033c0 <sexpr.printer::estimate_width>
  403574:	48 89 84 24 10 01 00 	mov    %rax,0x110(%rsp)
  40357b:	00 
  40357c:	48 89 94 24 18 01 00 	mov    %rdx,0x118(%rsp)
  403583:	00 
  403584:	48 85 c0             	test   %rax,%rax
  403587:	0f 84 ab fe ff ff    	je     403438 <sexpr.printer::estimate_width+0x78>
  40358d:	48 83 fb 01          	cmp    $0x1,%rbx
  403591:	49 83 dc ff          	sbb    $0xffffffffffffffff,%r12
  403595:	4c 03 a4 24 18 01 00 	add    0x118(%rsp),%r12
  40359c:	00 
  40359d:	48 ff c3             	inc    %rbx
  4035a0:	48 3b 5d 00          	cmp    0x0(%rbp),%rbx
  4035a4:	0f 8c f6 fe ff ff    	jl     4034a0 <sexpr.printer::estimate_width+0xe0>
  4035aa:	e9 63 05 00 00       	jmp    403b12 <sexpr.printer::estimate_width+0x752>
  4035af:	49 8b 76 08          	mov    0x8(%r14),%rsi
  4035b3:	c4 c1 7c 10 46 20    	vmovups 0x20(%r14),%ymm0
  4035b9:	c5 fc 11 84 24 20 01 	vmovups %ymm0,0x120(%rsp)
  4035c0:	00 00 
  4035c2:	8b 84 24 20 01 00 00 	mov    0x120(%rsp),%eax
  4035c9:	85 c0                	test   %eax,%eax
  4035cb:	0f 84 88 04 00 00    	je     403a59 <sexpr.printer::estimate_width+0x699>
  4035d1:	83 f8 01             	cmp    $0x1,%eax
  4035d4:	0f 85 e5 00 00 00    	jne    4036bf <sexpr.printer::estimate_width+0x2ff>
  4035da:	c5 f8 10 84 24 28 01 	vmovups 0x128(%rsp),%xmm0
  4035e1:	00 00 
  4035e3:	c5 f8 29 84 24 b0 00 	vmovaps %xmm0,0xb0(%rsp)
  4035ea:	00 00 
  4035ec:	48 8b 84 24 38 01 00 	mov    0x138(%rsp),%rax
  4035f3:	00 
  4035f4:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  4035fb:	00 
  4035fc:	48 8b 47 10          	mov    0x10(%rdi),%rax
  403600:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  403607:	00 
  403608:	4c 89 b4 24 88 00 00 	mov    %r14,0x88(%rsp)
  40360f:	00 
  403610:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  403617:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40361e:	00 
  40361f:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  403626:	00 
  403627:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40362c:	48 89 54 24 68       	mov    %rdx,0x68(%rsp)
  403631:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  403638:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40363d:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  403642:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  403647:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40364c:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  403653:	00 00 
  403655:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40365a:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  403661:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  403666:	48 8d 4c 24 20       	lea    0x20(%rsp),%rcx
  40366b:	48 89 0c 24          	mov    %rcx,(%rsp)
  40366f:	48 8d 4c 24 18       	lea    0x18(%rsp),%rcx
  403674:	48 c7 44 24 18 00 00 	movq   $0x0,0x18(%rsp)
  40367b:	00 00 
  40367d:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
  403682:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  403687:	48 89 e1             	mov    %rsp,%rcx
  40368a:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  40368f:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  403694:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40369b:	00 00 
  40369d:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  4036a2:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  4036a7:	48 8d b4 24 b0 00 00 	lea    0xb0(%rsp),%rsi
  4036ae:	00 
  4036af:	4c 89 e7             	mov    %r12,%rdi
  4036b2:	c5 f8 77             	vzeroupper
  4036b5:	e8 66 26 00 00       	call   405d20 <sexpr.printer::literal_width>
  4036ba:	e9 50 04 00 00       	jmp    403b0f <sexpr.printer::estimate_width+0x74f>
  4036bf:	31 c0                	xor    %eax,%eax
  4036c1:	45 31 e4             	xor    %r12d,%r12d
  4036c4:	e9 4e 04 00 00       	jmp    403b17 <sexpr.printer::estimate_width+0x757>
  4036c9:	c5 f8 10 02          	vmovups (%rdx),%xmm0
  4036cd:	48 8b 42 10          	mov    0x10(%rdx),%rax
  4036d1:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  4036d8:	00 
  4036d9:	c5 f8 29 84 24 d0 00 	vmovaps %xmm0,0xd0(%rsp)
  4036e0:	00 00 
  4036e2:	48 8b 47 10          	mov    0x10(%rdi),%rax
  4036e6:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  4036ed:	00 
  4036ee:	4c 89 b4 24 88 00 00 	mov    %r14,0x88(%rsp)
  4036f5:	00 
  4036f6:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  4036fd:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  403704:	00 
  403705:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  40370c:	00 
  40370d:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  403712:	48 89 54 24 68       	mov    %rdx,0x68(%rsp)
  403717:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40371e:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  403723:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  403728:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40372d:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  403732:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  403739:	00 00 
  40373b:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  403740:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  403747:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40374c:	48 8d 4c 24 20       	lea    0x20(%rsp),%rcx
  403751:	48 89 0c 24          	mov    %rcx,(%rsp)
  403755:	48 8d 4c 24 18       	lea    0x18(%rsp),%rcx
  40375a:	48 c7 44 24 18 00 00 	movq   $0x0,0x18(%rsp)
  403761:	00 00 
  403763:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
  403768:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  40376d:	48 89 e1             	mov    %rsp,%rcx
  403770:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  403775:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  40377a:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  403781:	00 00 
  403783:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  403788:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40378d:	48 8d b4 24 d0 00 00 	lea    0xd0(%rsp),%rsi
  403794:	00 
  403795:	4c 89 e7             	mov    %r12,%rdi
  403798:	e8 73 78 00 00       	call   40b010 <sexpr.printer::scalar_len>
  40379d:	49 89 c4             	mov    %rax,%r12
  4037a0:	49 83 c4 02          	add    $0x2,%r12
  4037a4:	e9 69 03 00 00       	jmp    403b12 <sexpr.printer::estimate_width+0x752>
  4037a9:	49 8b 5e 08          	mov    0x8(%r14),%rbx
  4037ad:	48 8b 47 10          	mov    0x10(%rdi),%rax
  4037b1:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  4037b8:	00 
  4037b9:	4c 89 b4 24 88 00 00 	mov    %r14,0x88(%rsp)
  4037c0:	00 
  4037c1:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  4037c8:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  4037cf:	00 
  4037d0:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  4037d7:	00 
  4037d8:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  4037dd:	48 89 54 24 68       	mov    %rdx,0x68(%rsp)
  4037e2:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  4037e9:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  4037ee:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  4037f3:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  4037f8:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  4037fd:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  403804:	00 00 
  403806:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40380b:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  403812:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  403817:	48 8d 4c 24 20       	lea    0x20(%rsp),%rcx
  40381c:	48 89 0c 24          	mov    %rcx,(%rsp)
  403820:	48 8d 4c 24 18       	lea    0x18(%rsp),%rcx
  403825:	48 c7 44 24 18 00 00 	movq   $0x0,0x18(%rsp)
  40382c:	00 00 
  40382e:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
  403833:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  403838:	48 89 e1             	mov    %rsp,%rcx
  40383b:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  403840:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  403845:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40384c:	00 00 
  40384e:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  403853:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  403858:	4c 89 e7             	mov    %r12,%rdi
  40385b:	e8 10 7d 01 00       	call   41b570 <myl_qbe_heap>
  403860:	48 8b 48 10          	mov    0x10(%rax),%rcx
  403864:	48 89 8c 24 48 01 00 	mov    %rcx,0x148(%rsp)
  40386b:	00 
  40386c:	48 c7 84 24 60 01 00 	movq   $0x0,0x160(%rsp)
  403873:	00 00 00 00 00 
  403878:	48 8d 8c 24 60 01 00 	lea    0x160(%rsp),%rcx
  40387f:	00 
  403880:	48 89 8c 24 50 01 00 	mov    %rcx,0x150(%rsp)
  403887:	00 
  403888:	48 c7 c1 f0 22 43 00 	mov    $0x4322f0,%rcx
  40388f:	48 89 8c 24 58 01 00 	mov    %rcx,0x158(%rsp)
  403896:	00 
  403897:	48 89 c7             	mov    %rax,%rdi
  40389a:	48 89 de             	mov    %rbx,%rsi
  40389d:	31 d2                	xor    %edx,%edx
  40389f:	e8 6c 28 01 00       	call   416110 <myl_native_text_scalar>
  4038a4:	48 8b 00             	mov    (%rax),%rax
  4038a7:	48 85 c0             	test   %rax,%rax
  4038aa:	41 bc 0c 00 00 00    	mov    $0xc,%r12d
  4038b0:	4c 0f 45 e0          	cmovne %rax,%r12
  4038b4:	e9 59 02 00 00       	jmp    403b12 <sexpr.printer::estimate_width+0x752>
  4038b9:	c5 f8 10 02          	vmovups (%rdx),%xmm0
  4038bd:	48 8b 42 10          	mov    0x10(%rdx),%rax
  4038c1:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  4038c8:	00 
  4038c9:	c5 f8 29 84 24 f0 00 	vmovaps %xmm0,0xf0(%rsp)
  4038d0:	00 00 
  4038d2:	48 8b 47 10          	mov    0x10(%rdi),%rax
  4038d6:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  4038dd:	00 
  4038de:	4c 89 b4 24 88 00 00 	mov    %r14,0x88(%rsp)
  4038e5:	00 
  4038e6:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  4038ed:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  4038f4:	00 
  4038f5:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  4038fc:	00 
  4038fd:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  403902:	48 89 54 24 68       	mov    %rdx,0x68(%rsp)
  403907:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40390e:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  403913:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  403918:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40391d:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  403922:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  403929:	00 00 
  40392b:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  403930:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  403937:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40393c:	48 8d 4c 24 20       	lea    0x20(%rsp),%rcx
  403941:	48 89 0c 24          	mov    %rcx,(%rsp)
  403945:	48 8d 4c 24 18       	lea    0x18(%rsp),%rcx
  40394a:	48 c7 44 24 18 00 00 	movq   $0x0,0x18(%rsp)
  403951:	00 00 
  403953:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
  403958:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  40395d:	48 89 e1             	mov    %rsp,%rcx
  403960:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  403965:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  40396a:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  403971:	00 00 
  403973:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  403978:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40397d:	48 8d b4 24 f0 00 00 	lea    0xf0(%rsp),%rsi
  403984:	00 
  403985:	4c 89 e7             	mov    %r12,%rdi
  403988:	e8 83 76 00 00       	call   40b010 <sexpr.printer::scalar_len>
  40398d:	e9 7d 01 00 00       	jmp    403b0f <sexpr.printer::estimate_width+0x74f>
  403992:	49 8b 76 08          	mov    0x8(%r14),%rsi
  403996:	48 8b 47 10          	mov    0x10(%rdi),%rax
  40399a:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  4039a1:	00 
  4039a2:	4c 89 b4 24 88 00 00 	mov    %r14,0x88(%rsp)
  4039a9:	00 
  4039aa:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  4039b1:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  4039b8:	00 
  4039b9:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  4039c0:	00 
  4039c1:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  4039c6:	48 89 54 24 68       	mov    %rdx,0x68(%rsp)
  4039cb:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  4039d2:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  4039d7:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  4039dc:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  4039e1:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  4039e6:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  4039ed:	00 00 
  4039ef:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  4039f4:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  4039fb:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  403a00:	48 8d 4c 24 20       	lea    0x20(%rsp),%rcx
  403a05:	48 89 0c 24          	mov    %rcx,(%rsp)
  403a09:	48 8d 4c 24 18       	lea    0x18(%rsp),%rcx
  403a0e:	48 c7 44 24 18 00 00 	movq   $0x0,0x18(%rsp)
  403a15:	00 00 
  403a17:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
  403a1c:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  403a21:	48 89 e1             	mov    %rsp,%rcx
  403a24:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  403a29:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  403a2e:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  403a35:	00 00 
  403a37:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  403a3c:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  403a41:	4c 89 e7             	mov    %r12,%rdi
  403a44:	e8 e7 04 00 00       	call   403f30 <sexpr.printer::measure_width>
  403a49:	e9 c1 00 00 00       	jmp    403b0f <sexpr.printer::estimate_width+0x74f>
  403a4e:	41 bc 02 00 00 00    	mov    $0x2,%r12d
  403a54:	e9 be 00 00 00       	jmp    403b17 <sexpr.printer::estimate_width+0x757>
  403a59:	48 8b 47 10          	mov    0x10(%rdi),%rax
  403a5d:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  403a64:	00 
  403a65:	4c 89 b4 24 88 00 00 	mov    %r14,0x88(%rsp)
  403a6c:	00 
  403a6d:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  403a74:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  403a7b:	00 
  403a7c:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  403a83:	00 
  403a84:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  403a89:	48 89 54 24 68       	mov    %rdx,0x68(%rsp)
  403a8e:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  403a95:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  403a9a:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  403a9f:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  403aa4:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  403aa9:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  403ab0:	00 00 
  403ab2:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  403ab7:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  403abe:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  403ac3:	48 8d 4c 24 20       	lea    0x20(%rsp),%rcx
  403ac8:	48 89 0c 24          	mov    %rcx,(%rsp)
  403acc:	48 8d 4c 24 18       	lea    0x18(%rsp),%rcx
  403ad1:	48 c7 44 24 18 00 00 	movq   $0x0,0x18(%rsp)
  403ad8:	00 00 
  403ada:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
  403adf:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  403ae4:	48 89 e1             	mov    %rsp,%rcx
  403ae7:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  403aec:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  403af1:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  403af8:	00 00 
  403afa:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  403aff:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  403b04:	4c 89 e7             	mov    %r12,%rdi
  403b07:	c5 f8 77             	vzeroupper
  403b0a:	e8 21 1a 01 00       	call   415530 <sexpr.printer::decimal_width>
  403b0f:	49 89 c4             	mov    %rax,%r12
  403b12:	b8 01 00 00 00       	mov    $0x1,%eax
  403b17:	4c 89 e2             	mov    %r12,%rdx
  403b1a:	48 81 c4 a8 01 00 00 	add    $0x1a8,%rsp
  403b21:	5b                   	pop    %rbx
  403b22:	41 5c                	pop    %r12
  403b24:	41 5d                	pop    %r13
  403b26:	41 5e                	pop    %r14
  403b28:	41 5f                	pop    %r15
  403b2a:	5d                   	pop    %rbp
  403b2b:	c5 f8 77             	vzeroupper
  403b2e:	c3                   	ret

Disassembly of section .fini:
