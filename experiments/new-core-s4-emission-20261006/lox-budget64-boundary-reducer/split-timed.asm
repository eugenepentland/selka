 103349d:	xor    %r11d,%r11d
 10334a0:	mov    0x8(%rsp),%r10
 10334a5:	mov    %rax,0x28(%rsp)
 10334aa:	lea    -0x2eeb1(%rip),%rbp        # 1004600 <core_number_pairs+0xd0>
 10334b1:	movabs $0x100000000000001,%r13
 10334bb:	vxorps %xmm1,%xmm1,%xmm1
 10334bf:	xor    %eax,%eax
 10334c1:	xor    %edx,%edx
 10334c3:	lea    0x27716(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10334ca:	mov    (%rsp),%r8
 10334ce:	xchg   %ax,%ax
 10334d0:	mov    0x20(%rsp),%rcx
 10334d5:	add    %rdx,%rcx
 10334d8:	mov    %rcx,0x50(%rsp)
 10334dd:	jo     10343ea <my.app::main+0x164a>
 10334e3:	mov    %rax,0x48(%rsp)
 10334e8:	mov    %rdx,0x40(%rsp)
 10334ed:	mov    0x8(%r9),%r15
 10334f1:	test   %r15,%r15
 10334f4:	je     1033c3b <my.app::main+0xe9b>
 10334fa:	mov    (%r15),%rax
 10334fd:	mov    %rax,0x8(%r9)
 1033501:	mov    %r13,(%r15)
 1033504:	vmovups %xmm1,0x8(%r15)
 103350a:	movq   $0x0,0x18(%r15)
 1033512:	mov    0x8(%r9),%rax
 1033516:	test   %rax,%rax
 1033519:	je     1033c69 <my.app::main+0xec9>
 103351f:	mov    (%rax),%rcx
 1033522:	mov    %rcx,0x8(%r9)
 1033526:	mov    %r13,(%rax)
 1033529:	vmovups %xmm1,0x8(%rax)
 103352e:	movq   $0x0,0x18(%rax)
 1033536:	mov    %rax,0x10(%rsp)
 103353b:	mov    0x10(%r9),%rdi
 103353f:	test   %rdi,%rdi
 1033542:	je     1033c94 <my.app::main+0xef4>
 1033548:	mov    (%rdi),%rax
 103354b:	mov    %rax,0x10(%r9)
 103354f:	vmovaps -0x2fe77(%rip),%ymm0        # 10036e0 <core_io_raw_layout+0x160>
 1033557:	vmovups %ymm0,(%rdi)
 103355b:	mov    $0x4,%ecx
 1033560:	xor    %edx,%edx
 1033562:	movq   $0x0,0x20(%rdi,%rdx,8)
 103356b:	inc    %rdx
 103356e:	mov    %rdx,0x8(%rdi)
 1033572:	cmp    %rcx,%rdx
 1033575:	jae    1033ceb <my.app::main+0xf4b>
 103357b:	movq   $0x0,0x20(%rdi,%rdx,8)
 1033584:	inc    %rdx
 1033587:	mov    %rdx,0x8(%rdi)
 103358b:	mov    0x8(%r10),%rdx
 103358f:	xor    %esi,%esi
 1033591:	test   %rdx,%rdx
 1033594:	je     1033dc9 <my.app::main+0x1029>
 103359a:	xor    %eax,%eax
 103359c:	mov    %rax,%r13
 103359f:	jmp    10335e8 <my.app::main+0x848>
 10335a1:	mov    0x8(%r15),%rax
 10335a5:	cmp    0x10(%r15),%rax
 10335a9:	jae    1033934 <my.app::main+0xb94>
 10335af:	mov    %rax,%rcx
 10335b2:	shl    $0x4,%rcx
 10335b6:	movq   $0x0,0x20(%r15,%rcx,1)
 10335bf:	mov    %r14,0x28(%r15,%rcx,1)
 10335c4:	inc    %rax
 10335c7:	mov    %rax,0x8(%r15)
 10335cb:	mov    0x8(%r10),%rdx
 10335cf:	mov    %r13,%rsi
 10335d2:	sar    $0x3f,%rsi
 10335d6:	and    %rdx,%rsi
 10335d9:	add    %r13,%rsi
 10335dc:	mov    %r13,%rax
 10335df:	cmp    %rdx,%rsi
 10335e2:	jae    1033dc9 <my.app::main+0x1029>
 10335e8:	inc    %r13
 10335eb:	jo     1033e91 <my.app::main+0x10f1>
 10335f1:	shl    $0x4,%rsi
 10335f5:	mov    (%r12,%rsi,1),%rcx
 10335f9:	mov    0x8(%r12,%rsi,1),%r14
 10335fe:	cmp    $0x4,%rcx
 1033602:	ja     10336fc <my.app::main+0x95c>
 1033608:	movslq 0x0(%rbp,%rcx,4),%rax
 103360d:	add    %rbp,%rax
 1033610:	jmp    *%rax
 1033612:	mov    0x8(%r15),%rax
 1033616:	cmp    0x10(%r15),%rax
 103361a:	jae    103396d <my.app::main+0xbcd>
 1033620:	mov    %rax,%rcx
 1033623:	shl    $0x4,%rcx
 1033627:	movq   $0x0,0x20(%r15,%rcx,1)
 1033630:	mov    0x50(%rsp),%rdx
 1033635:	mov    %rdx,0x28(%r15,%rcx,1)
 103363a:	jmp    10335c4 <my.app::main+0x824>
 103363c:	mov    0x8(%r15),%rdx
 1033640:	test   %rdx,%rdx
 1033643:	je     1033eb7 <my.app::main+0x1117>
 1033649:	dec    %rdx
 103364c:	mov    %rdx,%rax
 103364f:	shl    $0x4,%rax
 1033653:	movzbl 0x20(%r15,%rax,1),%ecx
 1033659:	mov    0x28(%r15,%rax,1),%rax
 103365e:	mov    %rdx,0x8(%r15)
 1033662:	mov    0x8(%rdi),%rdx
 1033666:	mov    %r14,%rsi
 1033669:	sar    $0x3f,%rsi
 103366d:	and    %rdx,%rsi
 1033670:	add    %r14,%rsi
 1033673:	cmp    %rdx,%rsi
 1033676:	jae    1033ea8 <my.app::main+0x1108>
 103367c:	test   %rcx,%rcx
 103367f:	cmovne %r11,%rax
 1033683:	mov    %rax,0x20(%rdi,%rsi,8)
 1033688:	jmp    10335cb <my.app::main+0x82b>
 103368d:	mov    0x8(%rdi),%rdx
 1033691:	mov    %r14,%rsi
 1033694:	sar    $0x3f,%rsi
 1033698:	and    %rdx,%rsi
 103369b:	add    %r14,%rsi
 103369e:	cmp    %rdx,%rsi
 10336a1:	jae    1033eca <my.app::main+0x112a>
 10336a7:	mov    0x20(%rdi,%rsi,8),%rbx
 10336ac:	mov    0x8(%r15),%rax
 10336b0:	cmp    0x10(%r15),%rax
 10336b4:	jae    10339df <my.app::main+0xc3f>
 10336ba:	mov    %rax,%rcx
 10336bd:	shl    $0x4,%rcx
 10336c1:	movq   $0x0,0x20(%r15,%rcx,1)
 10336ca:	mov    %rbx,0x28(%r15,%rcx,1)
 10336cf:	jmp    10335c4 <my.app::main+0x824>
 10336d4:	mov    0x8(%r15),%rax
 10336d8:	cmp    0x10(%r15),%rax
 10336dc:	jae    10339a6 <my.app::main+0xc06>
 10336e2:	mov    %rax,%rcx
 10336e5:	shl    $0x4,%rcx
 10336e9:	movq   $0x0,0x20(%r15,%rcx,1)
 10336f2:	mov    %r8,0x28(%r15,%rcx,1)
 10336f7:	jmp    10335c4 <my.app::main+0x824>
 10336fc:	lea    -0x5(%rcx),%rax
 1033700:	cmp    $0x5,%rax
 1033704:	jae    103372d <my.app::main+0x98d>
 1033706:	mov    0x8(%r15),%rcx
 103370a:	test   %rcx,%rcx
 103370d:	je     1033eec <my.app::main+0x114c>
 1033713:	lea    -0x1(%rcx),%rdx
 1033717:	mov    %rdx,%rsi
 103371a:	shl    $0x4,%rsi
 103371e:	cmpb   $0x0,0x20(%r15,%rsi,1)
 1033724:	jne    1033784 <my.app::main+0x9e4>
 1033726:	mov    0x28(%r15,%rsi,1),%rbp
 103372b:	jmp    1033786 <my.app::main+0x9e6>
 103372d:	add    $0xfffffffffffffff6,%rcx
 1033731:	cmp    $0x3,%rcx
 1033735:	ja     1033b40 <my.app::main+0xda0>
 103373b:	lea    -0x2f12e(%rip),%rdx        # 1004614 <core_number_pairs+0xe4>
 1033742:	movslq (%rdx,%rcx,4),%rax
 1033746:	add    %rdx,%rax
 1033749:	jmp    *%rax
 103374b:	mov    0x8(%r15),%rax
 103374f:	test   %rax,%rax
 1033752:	je     1034366 <my.app::main+0x15c6>
 1033758:	dec    %rax
 103375b:	mov    %rax,%rcx
 103375e:	shl    $0x4,%rcx
 1033762:	movzbl 0x20(%r15,%rcx,1),%edx
 1033768:	mov    0x28(%r15,%rcx,1),%rcx
 103376d:	mov    %rax,0x8(%r15)
 1033771:	test   $0x1,%cl
 1033774:	cmove  %r14,%r13
 1033778:	cmp    $0x1,%dl
 103377b:	cmovne %r14,%r13
 103377f:	jmp    10335cb <my.app::main+0x82b>
 1033784:	xor    %ebp,%ebp
 1033786:	mov    %rdx,0x8(%r15)
 103378a:	test   %rdx,%rdx
 103378d:	je     1033ed9 <my.app::main+0x1139>
 1033793:	mov    %rcx,%rdx
 1033796:	shl    $0x4,%rdx
 103379a:	cmpb   $0x0,(%r15,%rdx,1)
 103379f:	jne    10337a8 <my.app::main+0xa08>
 10337a1:	mov    0x8(%r15,%rdx,1),%rbx
 10337a6:	jmp    10337aa <my.app::main+0xa0a>
 10337a8:	xor    %ebx,%ebx
 10337aa:	add    $0xfffffffffffffffe,%rcx
 10337ae:	mov    %rcx,0x8(%r15)
 10337b2:	cmp    $0x3,%rax
 10337b6:	ja     10338af <my.app::main+0xb0f>
 10337bc:	lea    -0x2f19f(%rip),%rdx        # 1004624 <core_number_pairs+0xf4>
 10337c3:	movslq (%rdx,%rax,4),%rax
 10337c7:	add    %rdx,%rax
 10337ca:	jmp    *%rax
 10337cc:	mov    %rbx,%r14
 10337cf:	add    %rbp,%r14
 10337d2:	jno    103389c <my.app::main+0xafc>
 10337d8:	jmp    10343b5 <my.app::main+0x1615>
 10337dd:	mov    0x10(%rsp),%rax
 10337e2:	mov    0x8(%rax),%rcx
 10337e6:	cmp    0x10(%rax),%rcx
 10337ea:	jae    1033a51 <my.app::main+0xcb1>
 10337f0:	mov    %r13,0x20(%rax,%rcx,8)
 10337f5:	inc    %rcx
 10337f8:	mov    %rax,0x10(%rsp)
 10337fd:	mov    %rcx,0x8(%rax)
 1033801:	mov    %r14,%r13
 1033804:	jmp    10335cb <my.app::main+0x82b>
 1033809:	mov    0x10(%rsp),%rcx
 103380e:	mov    0x8(%rcx),%rax
 1033812:	test   %rax,%rax
 1033815:	je     1034379 <my.app::main+0x15d9>
 103381b:	mov    0x18(%rcx,%rax,8),%r13
 1033820:	dec    %rax
 1033823:	mov    %rax,0x8(%rcx)
 1033827:	jmp    10335cb <my.app::main+0x82b>
 103382c:	mov    %r14,%r13
 103382f:	jmp    10335cb <my.app::main+0x82b>
 1033834:	test   %rbp,%rbp
 1033837:	je     10343a1 <my.app::main+0x1601>
 103383d:	cmp    $0xffffffffffffffff,%rbp
 1033841:	mov    %rbp,%rsi
 1033844:	mov    $0x1,%eax
 1033849:	cmove  %rax,%rsi
 103384d:	mov    %rbx,%rax
 1033850:	or     %rsi,%rax
 1033853:	shr    $0x20,%rax
 1033857:	je     10338e5 <my.app::main+0xb45>
 103385d:	mov    %rbx,%rax
 1033860:	cqto
 1033862:	idiv   %rsi
 1033865:	jmp    10338eb <my.app::main+0xb4b>
 103386a:	cmp    0x10(%r15),%rcx
 103386e:	jae    1033a87 <my.app::main+0xce7>
 1033874:	mov    %rcx,%rax
 1033877:	shl    $0x4,%rax
 103387b:	cmp    %rbp,%rbx
 103387e:	movq   $0x1,0x20(%r15,%rax,1)
 1033887:	setl   0x28(%r15,%rax,1)
 103388d:	jmp    10338d2 <my.app::main+0xb32>
 103388f:	mov    %rbx,%r14
 1033892:	imul   %rbp,%r14
 1033896:	jo     103438c <my.app::main+0x15ec>
 103389c:	cmp    0x10(%r15),%rcx
 10338a0:	jae    1033a18 <my.app::main+0xc78>
 10338a6:	lea    -0x2f2ad(%rip),%rbp        # 1004600 <core_number_pairs+0xd0>
 10338ad:	jmp    1033913 <my.app::main+0xb73>
 10338af:	cmp    0x10(%r15),%rcx
 10338b3:	jae    1033ac0 <my.app::main+0xd20>
 10338b9:	mov    %rcx,%rax
 10338bc:	shl    $0x4,%rax
 10338c0:	cmp    %rbp,%rbx
 10338c3:	movq   $0x1,0x20(%r15,%rax,1)
 10338cc:	sete   0x28(%r15,%rax,1)
 10338d2:	inc    %rcx
 10338d5:	mov    %rcx,0x8(%r15)
 10338d9:	lea    -0x2f2e0(%rip),%rbp        # 1004600 <core_number_pairs+0xd0>
 10338e0:	jmp    10335cb <my.app::main+0x82b>
 10338e5:	mov    %ebx,%eax
 10338e7:	xor    %edx,%edx
 10338e9:	div    %esi
 10338eb:	mov    %rdx,%r14
 10338ee:	xor    %rbp,%r14
 10338f1:	sar    $0x3f,%r14
 10338f5:	and    %rbp,%r14
 10338f8:	test   %rdx,%rdx
 10338fb:	cmove  %rdx,%r14
 10338ff:	cmp    0x10(%r15),%rcx
 1033903:	jae    1033af9 <my.app::main+0xd59>
 1033909:	lea    -0x2f310(%rip),%rbp        # 1004600 <core_number_pairs+0xd0>
 1033910:	add    %rdx,%r14
 1033913:	mov    %rcx,%rax
 1033916:	shl    $0x4,%rax
 103391a:	movq   $0x0,0x20(%r15,%rax,1)
 1033923:	mov    %r14,0x28(%r15,%rax,1)
 1033928:	inc    %rcx
 103392b:	mov    %rcx,0x8(%r15)
 103392f:	jmp    10335cb <my.app::main+0x82b>
 1033934:	mov    $0x10,%esi
 1033939:	mov    %rdi,%rbx
 103393c:	mov    %r15,%rdi
 103393f:	vzeroupper
 1033942:	call   10094f0 <myl_core_list_grow>
 1033947:	vxorps %xmm1,%xmm1,%xmm1
 103394b:	xor    %r11d,%r11d
 103394e:	mov    0x8(%rsp),%r10
 1033953:	mov    (%rsp),%r8
 1033957:	lea    0x27282(%rip),%r9        # 105abe0 <myl_core_free_lists>
 103395e:	mov    %rbx,%rdi
 1033961:	mov    %rax,%r15
 1033964:	mov    0x8(%rax),%rax
 1033968:	jmp    10335af <my.app::main+0x80f>
 103396d:	mov    $0x10,%esi
 1033972:	mov    %rdi,%rbx
 1033975:	mov    %r15,%rdi
 1033978:	vzeroupper
 103397b:	call   10094f0 <myl_core_list_grow>
 1033980:	vxorps %xmm1,%xmm1,%xmm1
 1033984:	xor    %r11d,%r11d
 1033987:	mov    0x8(%rsp),%r10
 103398c:	mov    (%rsp),%r8
 1033990:	lea    0x27249(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033997:	mov    %rbx,%rdi
 103399a:	mov    %rax,%r15
 103399d:	mov    0x8(%rax),%rax
 10339a1:	jmp    1033620 <my.app::main+0x880>
 10339a6:	mov    $0x10,%esi
 10339ab:	mov    %rdi,%rbx
 10339ae:	mov    %r15,%rdi
 10339b1:	vzeroupper
 10339b4:	call   10094f0 <myl_core_list_grow>
 10339b9:	vxorps %xmm1,%xmm1,%xmm1
 10339bd:	xor    %r11d,%r11d
 10339c0:	mov    0x8(%rsp),%r10
 10339c5:	mov    (%rsp),%r8
 10339c9:	lea    0x27210(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10339d0:	mov    %rbx,%rdi
 10339d3:	mov    %rax,%r15
 10339d6:	mov    0x8(%rax),%rax
 10339da:	jmp    10336e2 <my.app::main+0x942>
 10339df:	mov    $0x10,%esi
 10339e4:	mov    %rdi,%r14
 10339e7:	mov    %r15,%rdi
 10339ea:	vzeroupper
 10339ed:	call   10094f0 <myl_core_list_grow>
 10339f2:	vxorps %xmm1,%xmm1,%xmm1
 10339f6:	xor    %r11d,%r11d
 10339f9:	mov    0x8(%rsp),%r10
 10339fe:	mov    (%rsp),%r8
 1033a02:	lea    0x271d7(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033a09:	mov    %r14,%rdi
 1033a0c:	mov    %rax,%r15
 1033a0f:	mov    0x8(%rax),%rax
 1033a13:	jmp    10336ba <my.app::main+0x91a>
 1033a18:	mov    $0x10,%esi
 1033a1d:	mov    %rdi,%rbx
 1033a20:	mov    %r15,%rdi
 1033a23:	vzeroupper
 1033a26:	call   10094f0 <myl_core_list_grow>
 1033a2b:	vxorps %xmm1,%xmm1,%xmm1
 1033a2f:	xor    %r11d,%r11d
 1033a32:	mov    0x8(%rsp),%r10
 1033a37:	mov    (%rsp),%r8
 1033a3b:	lea    0x2719e(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033a42:	mov    %rbx,%rdi
 1033a45:	mov    %rax,%r15
 1033a48:	mov    0x8(%rax),%rcx
 1033a4c:	jmp    10338a6 <my.app::main+0xb06>
 1033a51:	mov    $0x8,%esi
 1033a56:	mov    %rdi,%rbx
 1033a59:	mov    %rax,%rdi
 1033a5c:	vzeroupper
 1033a5f:	call   10094f0 <myl_core_list_grow>
 1033a64:	vxorps %xmm1,%xmm1,%xmm1
 1033a68:	xor    %r11d,%r11d
 1033a6b:	mov    0x8(%rsp),%r10
 1033a70:	mov    (%rsp),%r8
 1033a74:	lea    0x27165(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033a7b:	mov    %rbx,%rdi
 1033a7e:	mov    0x8(%rax),%rcx
 1033a82:	jmp    10337f0 <my.app::main+0xa50>
 1033a87:	mov    $0x10,%esi
 1033a8c:	mov    %rdi,%r14
 1033a8f:	mov    %r15,%rdi
 1033a92:	vzeroupper
 1033a95:	call   10094f0 <myl_core_list_grow>
 1033a9a:	vxorps %xmm1,%xmm1,%xmm1
 1033a9e:	xor    %r11d,%r11d
 1033aa1:	mov    0x8(%rsp),%r10
 1033aa6:	mov    (%rsp),%r8
 1033aaa:	lea    0x2712f(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033ab1:	mov    %r14,%rdi
 1033ab4:	mov    %rax,%r15
 1033ab7:	mov    0x8(%rax),%rcx
 1033abb:	jmp    1033874 <my.app::main+0xad4>
 1033ac0:	mov    $0x10,%esi
 1033ac5:	mov    %rdi,%r14
 1033ac8:	mov    %r15,%rdi
 1033acb:	vzeroupper
 1033ace:	call   10094f0 <myl_core_list_grow>
 1033ad3:	vxorps %xmm1,%xmm1,%xmm1
 1033ad7:	xor    %r11d,%r11d
 1033ada:	mov    0x8(%rsp),%r10
 1033adf:	mov    (%rsp),%r8
 1033ae3:	lea    0x270f6(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033aea:	mov    %r14,%rdi
 1033aed:	mov    %rax,%r15
 1033af0:	mov    0x8(%rax),%rcx
 1033af4:	jmp    10338b9 <my.app::main+0xb19>
 1033af9:	mov    $0x10,%esi
 1033afe:	mov    %rdi,%rbp
 1033b01:	mov    %r15,%rdi
 1033b04:	mov    %rdx,%rbx
 1033b07:	vzeroupper
 1033b0a:	call   10094f0 <myl_core_list_grow>
 1033b0f:	vxorps %xmm1,%xmm1,%xmm1
 1033b13:	xor    %r11d,%r11d
 1033b16:	mov    0x8(%rsp),%r10
 1033b1b:	mov    (%rsp),%r8
 1033b1f:	lea    0x270ba(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033b26:	mov    %rbp,%rdi
 1033b29:	mov    %rbx,%rdx
 1033b2c:	mov    %rax,%r15
 1033b2f:	mov    0x8(%rax),%rcx
 1033b33:	jmp    1033909 <my.app::main+0xb69>
 1033b38:	nopl   0x0(%rax,%rax,1)
 1033b40:	movzbl 0x7(%rdi),%eax
 1033b44:	test   %rax,%rax
 1033b47:	je     1033d1b <my.app::main+0xf7b>
 1033b4d:	cmpq   $0x0,0x18(%rdi)
 1033b52:	jne    1033d1b <my.app::main+0xf7b>
 1033b58:	mov    (%r9,%rax,8),%rcx
 1033b5c:	mov    %rcx,(%rdi)
 1033b5f:	mov    %rdi,(%r9,%rax,8)
 1033b63:	movabs $0x100000000000001,%r13
 1033b6d:	mov    0x10(%rsp),%rdi
 1033b72:	movzbl 0x7(%rdi),%eax
 1033b76:	test   %rax,%rax
 1033b79:	je     1033d3f <my.app::main+0xf9f>
 1033b7f:	cmpq   $0x0,0x18(%rdi)
 1033b84:	jne    1033d3f <my.app::main+0xf9f>
 1033b8a:	mov    (%r9,%rax,8),%rcx
 1033b8e:	mov    %rcx,(%rdi)
 1033b91:	mov    %rdi,(%r9,%rax,8)
 1033b95:	mov    0x8(%r15),%rax
 1033b99:	test   %rax,%rax
 1033b9c:	je     10343fe <my.app::main+0x165e>
 1033ba2:	dec    %rax
 1033ba5:	mov    %rax,%rcx
 1033ba8:	shl    $0x4,%rcx
 1033bac:	movzbl 0x20(%r15,%rcx,1),%ebx
 1033bb2:	mov    0x28(%r15,%rcx,1),%r14
 1033bb7:	mov    %rax,0x8(%r15)
 1033bbb:	movzbl 0x7(%r15),%eax
 1033bc0:	test   %rax,%rax
 1033bc3:	je     1033d63 <my.app::main+0xfc3>
 1033bc9:	cmpq   $0x0,0x18(%r15)
 1033bce:	jne    1033d63 <my.app::main+0xfc3>
 1033bd4:	mov    (%r9,%rax,8),%rcx
 1033bd8:	mov    %rcx,(%r15)
 1033bdb:	mov    %r15,(%r9,%rax,8)
 1033bdf:	test   %rbx,%rbx
 1033be2:	cmovne %r11,%r14
 1033be6:	test   %r14,%r14
 1033be9:	mov    0x48(%rsp),%rsi
 1033bee:	js     1033d96 <my.app::main+0xff6>
 1033bf4:	mov    %rsi,%rbx
 1033bf7:	add    %r14,%rbx
 1033bfa:	jo     1034411 <my.app::main+0x1671>
 1033c00:	mov    %rbx,%rdx
 1033c03:	movabs $0x89705f3112a28fe5,%rax
 1033c0d:	mulx   %rax,%rax,%rax
 1033c12:	shr    $0x1d,%rax
 1033c16:	imul   $0x3b9aca07,%rax,%rax
 1033c1d:	sub    %rax,%rbx
 1033c20:	mov    0x40(%rsp),%rdx
 1033c25:	inc    %rdx
 1033c28:	mov    %rbx,%rax
 1033c2b:	cmp    0x38(%rsp),%rdx
 1033c30:	jne    10334d0 <my.app::main+0x730>
 1033c36:	jmp    1033db3 <my.app::main+0x1013>
 1033c3b:	mov    $0x10,%esi
 1033c40:	xor    %edi,%edi
 1033c42:	vzeroupper
 1033c45:	call   1009480 <myl_core_list_new_slow>
 1033c4a:	vxorps %xmm1,%xmm1,%xmm1
 1033c4e:	xor    %r11d,%r11d
 1033c51:	mov    0x8(%rsp),%r10
 1033c56:	mov    (%rsp),%r8
 1033c5a:	lea    0x26f7f(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033c61:	mov    %rax,%r15
 1033c64:	jmp    1033512 <my.app::main+0x772>
 1033c69:	mov    $0x8,%esi
 1033c6e:	xor    %edi,%edi
 1033c70:	vzeroupper
 1033c73:	call   1009480 <myl_core_list_new_slow>
 1033c78:	vxorps %xmm1,%xmm1,%xmm1
 1033c7c:	xor    %r11d,%r11d
 1033c7f:	mov    0x8(%rsp),%r10
 1033c84:	mov    (%rsp),%r8
 1033c88:	lea    0x26f51(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033c8f:	jmp    1033536 <my.app::main+0x796>
 1033c94:	mov    $0x2,%edi
 1033c99:	mov    $0x8,%esi
 1033c9e:	vzeroupper
 1033ca1:	call   1009480 <myl_core_list_new_slow>
 1033ca6:	mov    %rax,%rdi
 1033ca9:	mov    0x8(%rax),%rdx
 1033cad:	mov    0x10(%rax),%rcx
 1033cb1:	cmp    %rcx,%rdx
 1033cb4:	jb     1033d8a <my.app::main+0xfea>
 1033cba:	mov    $0x8,%esi
 1033cbf:	call   10094f0 <myl_core_list_grow>
 1033cc4:	mov    0x8(%rax),%rdx
 1033cc8:	mov    0x10(%rax),%rcx
 1033ccc:	lea    0x26f0d(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033cd3:	mov    %rax,%rdi
 1033cd6:	mov    (%rsp),%r8
 1033cda:	mov    0x8(%rsp),%r10
 1033cdf:	xor    %r11d,%r11d
 1033ce2:	vxorps %xmm1,%xmm1,%xmm1
 1033ce6:	jmp    1033562 <my.app::main+0x7c2>
 1033ceb:	mov    $0x8,%esi
 1033cf0:	vzeroupper
 1033cf3:	call   10094f0 <myl_core_list_grow>
 1033cf8:	vxorps %xmm1,%xmm1,%xmm1
 1033cfc:	xor    %r11d,%r11d
 1033cff:	mov    0x8(%rsp),%r10
 1033d04:	mov    (%rsp),%r8
 1033d08:	lea    0x26ed1(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d0f:	mov    %rax,%rdi
 1033d12:	mov    0x8(%rax),%rdx
 1033d16:	jmp    103357b <my.app::main+0x7db>
 1033d1b:	vzeroupper
 1033d1e:	call   1032790 <myl_core_free_block>
 1033d23:	vxorps %xmm1,%xmm1,%xmm1
 1033d27:	xor    %r11d,%r11d
 1033d2a:	mov    0x8(%rsp),%r10
 1033d2f:	mov    (%rsp),%r8
 1033d33:	lea    0x26ea6(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d3a:	jmp    1033b63 <my.app::main+0xdc3>
 1033d3f:	vzeroupper
 1033d42:	call   1032790 <myl_core_free_block>
 1033d47:	vxorps %xmm1,%xmm1,%xmm1
 1033d4b:	xor    %r11d,%r11d
 1033d4e:	mov    0x8(%rsp),%r10
 1033d53:	mov    (%rsp),%r8
 1033d57:	lea    0x26e82(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d5e:	jmp    1033b95 <my.app::main+0xdf5>
 1033d63:	mov    %r15,%rdi
 1033d66:	vzeroupper
 1033d69:	call   1032790 <myl_core_free_block>
 1033d6e:	vxorps %xmm1,%xmm1,%xmm1
 1033d72:	xor    %r11d,%r11d
 1033d75:	mov    0x8(%rsp),%r10
 1033d7a:	mov    (%rsp),%r8
 1033d7e:	lea    0x26e5b(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d85:	jmp    1033bdf <my.app::main+0xe3f>
 1033d8a:	lea    0x26e4f(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d91:	jmp    1033cd6 <my.app::main+0xf36>
 1033d96:	mov    (%r10),%eax
 1033d99:	mov    $0x2,%ebx
 1033d9e:	cmp    $0xffffffff,%eax
 1033da1:	je     1033e7c <my.app::main+0x10dc>
 1033da7:	dec    %eax
 1033da9:	je     1033dd8 <my.app::main+0x1038>
 1033dab:	mov    %eax,(%r10)
 1033dae:	jmp    1033e7c <my.app::main+0x10dc>
 1033db3:	mov    (%r10),%eax
 1033db6:	cmp    $0xffffffff,%eax
 1033db9:	mov    0x18(%rsp),%r14
 1033dbe:	je     1033e22 <my.app::main+0x1082>
 1033dc0:	dec    %eax
 1033dc2:	je     1033dfe <my.app::main+0x105e>
 1033dc4:	mov    %eax,(%r10)
 1033dc7:	jmp    1033e22 <my.app::main+0x1082>
 1033dc9:	lea    0x2980(%rip),%rdi        # 1036750 <core_io_file_error.verbs+0x1a0>
 1033dd0:	vzeroupper
 1033dd3:	call   1009b80 <myl_core_trap>
 1033dd8:	movzbl 0x7(%r10),%eax
 1033ddd:	test   %rax,%rax
 1033de0:	je     10343ca <my.app::main+0x162a>
 1033de6:	cmpq   $0x0,0x18(%r10)
 1033deb:	jne    10343ca <my.app::main+0x162a>
 1033df1:	mov    (%r9,%rax,8),%rcx
 1033df5:	mov    %rcx,(%r10)
 1033df8:	mov    %r10,(%r9,%rax,8)
 1033dfc:	jmp    1033e7c <my.app::main+0x10dc>
 1033dfe:	movzbl 0x7(%r10),%eax
 1033e03:	test   %rax,%rax
 1033e06:	je     10343da <my.app::main+0x163a>
 1033e0c:	cmpq   $0x0,0x18(%r10)
 1033e11:	jne    10343da <my.app::main+0x163a>
 1033e17:	mov    (%r9,%rax,8),%rcx
 1033e1b:	mov    %rcx,(%r10)
 1033e1e:	mov    %r10,(%r9,%rax,8)
 1033e22:	lea    0x2867(%rip),%rdi        # 1036690 <core_io_file_error.verbs+0xe0>
 1033e29:	vzeroupper
 1033e2c:	call   100a4c0 <myl_core_io_at>
 1033e31:	mov    %r14,%rdi
 1033e34:	call   1022430 <myl_core_host_check>
