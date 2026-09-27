 10075b0:	mov    %r12,-0x60(%rbp)
 10075b4:	movq   $0xf42400,-0x58(%rbp)
 10075bc:	cmp    $0xf42400,%r12
 10075c3:	setl   %cl
 10075c6:	movzbq %cl,%rcx
 10075ca:	mov    %rcx,-0x60(%rbp)
 10075ce:	jge    10076a9 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0x969>
 10075d4:	mov    %r12,-0x60(%rbp)
 10075d8:	mov    -0x70(%rbp),%r13
 10075dc:	mov    0x0(%r13),%r15
 10075e0:	mov    0x8(%r13),%rcx
 10075e4:	mov    0x10(%r13),%r14
 10075e8:	cmp    %rcx,%r15
 10075eb:	setb   %cl
 10075ee:	movzbl %cl,%ecx
 10075f1:	cmp    $0xffffffffffffffff,%r14
 10075f5:	setne  %dl
 10075f8:	movzbl %dl,%edx
 10075fb:	test   %ecx,%edx
 10075fd:	je     1007614 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0x8d4>
 10075ff:	cmp    $0x0,%eax
 1007602:	jne    100763a <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0x8fa>
 100763a:	mov    0x20(%r13),%rcx
 100763e:	mov    %r12,(%rcx,%r15,8)
 1007642:	mov    %r15,%rcx
 1007645:	add    $0x1,%rcx
 1007649:	mov    %rcx,0x0(%r13)
 100764d:	mov    %r14,%rcx
 1007650:	add    $0x1,%rcx
 1007654:	mov    %rcx,0x10(%r13)
 1007658:	movq   $0x0,-0x60(%rbp)
 1007660:	mov    %r12,-0x60(%rbp)
 1007664:	movq   $0x1,-0x58(%rbp)
 100766c:	movabs $0x7ffffffffffffffe,%rcx
 1007676:	cmp    %rcx,%r12
 1007679:	jg     1007688 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0x948>
 100767b:	add    $0x1,%r12
 100767f:	mov    %r12,-0x60(%rbp)
 1007683:	jmp    10075b0 <myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605+0x870>
