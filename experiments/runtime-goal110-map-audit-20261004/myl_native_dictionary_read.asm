
/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf/runner/bin/collections-my-llvm:     file format elf64-x86-64


Disassembly of section .text:

000000000105d470 <myl_native_dictionary_read>:
 105d470:	push   %rbp
 105d471:	mov    %rsp,%rbp
 105d474:	push   %r15
 105d476:	push   %r14
 105d478:	push   %r13
 105d47a:	push   %r12
 105d47c:	push   %rbx
 105d47d:	push   %rax
 105d47e:	cmpl   $0x1,0xf8(%rdi)
 105d485:	jne    105d6fb <myl_native_dictionary_read+0x28b>
 105d48b:	mov    0x24(%rdi),%r15d
 105d48f:	cmp    $0x2,%r15d
 105d493:	je     105d4a9 <myl_native_dictionary_read+0x39>
 105d495:	cmp    $0x1,%r15d
 105d499:	je     105d4a4 <myl_native_dictionary_read+0x34>
 105d49b:	test   %r15d,%r15d
 105d49e:	jne    105d6fb <myl_native_dictionary_read+0x28b>
 105d4a4:	mov    (%rsi),%r14
 105d4a7:	jmp    105d50c <myl_native_dictionary_read+0x9c>
 105d4a9:	mov    0x8(%rdi),%rax
 105d4ad:	mov    (%rax),%rcx
 105d4b0:	movq   $0x0,-0x30(%rbp)
 105d4b8:	popcnt %rcx,%rax
 105d4bd:	cmp    $0x1,%eax
 105d4c0:	jne    105d4da <myl_native_dictionary_read+0x6a>
 105d4c2:	tzcnt  %rcx,%rax
 105d4c7:	cmp    $0x3,%rax
 105d4cb:	ja     105d4da <myl_native_dictionary_read+0x6a>
 105d4cd:	jmp    *0x100b3f8(,%rax,8)
 105d4d4:	movzbl (%rsi),%r14d
 105d4d8:	jmp    105d50c <myl_native_dictionary_read+0x9c>
 105d4da:	cmp    $0x8,%rcx
 105d4de:	mov    $0x8,%eax
 105d4e3:	cmovb  %rcx,%rax
 105d4e7:	lea    -0x30(%rbp),%rcx
 105d4eb:	mov    %rdi,%r14
 105d4ee:	mov    %rcx,%rdi
 105d4f1:	mov    %rsi,%rbx
 105d4f4:	mov    %rdx,%r12
 105d4f7:	mov    %rax,%rdx
 105d4fa:	call   10713b0 <memcpy@plt>
 105d4ff:	mov    %rbx,%rsi
 105d502:	mov    %r14,%rdi
 105d505:	mov    %r12,%rdx
 105d508:	mov    -0x30(%rbp),%r14
 105d50c:	cmp    0xe0(%rdi),%r14
 105d513:	jne    105d6fb <myl_native_dictionary_read+0x28b>
 105d519:	mov    (%rdi),%rcx
 105d51c:	mov    0xe8(%rdi),%rax
 105d523:	cmp    (%rcx),%rax
 105d526:	jae    105d6fb <myl_native_dictionary_read+0x28b>
 105d52c:	mov    0x30(%rdi),%rbx
 105d530:	imul   %rax,%rbx
 105d534:	add    0x20(%rcx),%rbx
 105d538:	cmp    $0x2,%r15d
 105d53c:	je     105d54c <myl_native_dictionary_read+0xdc>
 105d53e:	cmp    $0x1,%r15d
 105d542:	jne    105d57c <myl_native_dictionary_read+0x10c>
 105d544:	mov    (%rbx),%rax
 105d547:	jmp    105d5d0 <myl_native_dictionary_read+0x160>
 105d54c:	mov    0x8(%rdi),%rax
 105d550:	mov    (%rax),%rcx
 105d553:	movq   $0x0,-0x30(%rbp)
 105d55b:	popcnt %rcx,%rax
 105d560:	cmp    $0x1,%eax
 105d563:	jne    105d59b <myl_native_dictionary_read+0x12b>
 105d565:	tzcnt  %rcx,%rax
 105d56a:	cmp    $0x3,%rax
 105d56e:	ja     105d59b <myl_native_dictionary_read+0x12b>
 105d570:	jmp    *0x100b418(,%rax,8)
 105d577:	movzbl (%rbx),%eax
 105d57a:	jmp    105d5d0 <myl_native_dictionary_read+0x160>
 105d57c:	mov    (%rbx),%rcx
 105d57f:	mov    (%rsi),%r10
 105d582:	cmp    %r10,%rcx
 105d585:	je     105d5d9 <myl_native_dictionary_read+0x169>
 105d587:	testb  $0x4,0x10(%r10)
 105d58c:	jne    105d625 <myl_native_dictionary_read+0x1b5>
 105d592:	lea    0x18(%r10),%r8
 105d596:	jmp    105d634 <myl_native_dictionary_read+0x1c4>
 105d59b:	cmp    $0x8,%rcx
 105d59f:	mov    $0x8,%eax
 105d5a4:	cmovb  %rcx,%rax
 105d5a8:	lea    -0x30(%rbp),%rcx
 105d5ac:	mov    %rdi,%r15
 105d5af:	mov    %rcx,%rdi
 105d5b2:	mov    %rsi,%r12
 105d5b5:	mov    %rbx,%rsi
 105d5b8:	mov    %rdx,%r13
 105d5bb:	mov    %rax,%rdx
 105d5be:	call   10713b0 <memcpy@plt>
 105d5c3:	mov    %r12,%rsi
 105d5c6:	mov    %r15,%rdi
 105d5c9:	mov    %r13,%rdx
 105d5cc:	mov    -0x30(%rbp),%rax
 105d5d0:	cmp    %r14,%rax
 105d5d3:	jne    105d6fb <myl_native_dictionary_read+0x28b>
 105d5d9:	add    0x18(%rdi),%rbx
 105d5dd:	mov    0x10(%rdi),%rax
 105d5e1:	mov    (%rax),%rax
 105d5e4:	cmp    $0x8,%rax
 105d5e8:	jne    105d5f2 <myl_native_dictionary_read+0x182>
 105d5ea:	mov    (%rbx),%rax
 105d5ed:	mov    %rax,(%rdx)
 105d5f0:	jmp    105d600 <myl_native_dictionary_read+0x190>
 105d5f2:	mov    %rdx,%rdi
 105d5f5:	mov    %rbx,%rsi
 105d5f8:	mov    %rax,%rdx
 105d5fb:	call   10713e0 <memmove@plt>
 105d600:	mov    $0x1,%eax
 105d605:	add    $0x8,%rsp
 105d609:	pop    %rbx
 105d60a:	pop    %r12
 105d60c:	pop    %r13
 105d60e:	pop    %r14
 105d610:	pop    %r15
 105d612:	pop    %rbp
 105d613:	ret
 105d614:	mov    (%rsi),%r14d
 105d617:	jmp    105d50c <myl_native_dictionary_read+0x9c>
 105d61c:	movzwl (%rsi),%r14d
 105d620:	jmp    105d50c <myl_native_dictionary_read+0x9c>
 105d625:	mov    0x18(%r10),%r8
 105d629:	mov    0x14(%r10),%r9d
 105d62d:	add    %r9,%r8
 105d630:	add    $0x18,%r8
 105d634:	mov    0x8(%rcx),%r9
 105d638:	cmp    0x8(%r10),%r9
 105d63c:	jne    105d6fb <myl_native_dictionary_read+0x28b>
 105d642:	cmp    $0x8,%r9
 105d646:	jb     105d667 <myl_native_dictionary_read+0x1f7>
 105d648:	xor    %r10d,%r10d
 105d64b:	lea    0x8(%r10),%r11
 105d64f:	cmp    %r9,%r11
 105d652:	jae    105d692 <myl_native_dictionary_read+0x222>
 105d654:	mov    0x18(%rcx,%r10,1),%r14
 105d659:	cmp    (%r8,%r10,1),%r14
 105d65d:	mov    %r11,%r10
 105d660:	je     105d64b <myl_native_dictionary_read+0x1db>
 105d662:	jmp    105d6fb <myl_native_dictionary_read+0x28b>
 105d667:	cmp    $0x3,%r9
 105d66b:	jbe    105d6af <myl_native_dictionary_read+0x23f>
 105d66d:	mov    0x18(%rcx),%r10d
 105d671:	mov    -0x4(%r8,%r9,1),%r11d
 105d676:	xor    (%r8),%r10d
 105d679:	xor    0x14(%rcx,%r9,1),%r11d
 105d67e:	or     %r10d,%r11d
 105d681:	jmp    105d69c <myl_native_dictionary_read+0x22c>
 105d683:	mov    (%rbx),%eax
 105d685:	jmp    105d5d0 <myl_native_dictionary_read+0x160>
 105d68a:	movzwl (%rbx),%eax
 105d68d:	jmp    105d5d0 <myl_native_dictionary_read+0x160>
 105d692:	mov    0x10(%rcx,%r9,1),%rcx
 105d697:	cmp    -0x8(%r8,%r9,1),%rcx
 105d69c:	sete   %cl
 105d69f:	cmp    $0xffffffffffffffff,%rax
 105d6a3:	je     105d6fb <myl_native_dictionary_read+0x28b>
 105d6a5:	test   %cl,%cl
 105d6a7:	jne    105d5d9 <myl_native_dictionary_read+0x169>
 105d6ad:	jmp    105d6fb <myl_native_dictionary_read+0x28b>
 105d6af:	test   %r9,%r9
 105d6b2:	je     105d5d9 <myl_native_dictionary_read+0x169>
 105d6b8:	movzbl 0x18(%rcx),%r10d
 105d6bd:	cmp    (%r8),%r10b
 105d6c0:	jne    105d6fb <myl_native_dictionary_read+0x28b>
 105d6c2:	cmp    $0x1,%r9
 105d6c6:	je     105d5d9 <myl_native_dictionary_read+0x169>
 105d6cc:	movzbl 0x19(%rcx),%r10d
 105d6d1:	cmp    0x1(%r8),%r10b
 105d6d5:	jne    105d6fb <myl_native_dictionary_read+0x28b>
 105d6d7:	cmp    $0x2,%r9
 105d6db:	je     105d5d9 <myl_native_dictionary_read+0x169>
 105d6e1:	movzbl 0x1a(%rcx),%ecx
 105d6e5:	cmp    0x2(%r8),%cl
 105d6e9:	setne  %cl
 105d6ec:	cmp    $0xffffffffffffffff,%rax
 105d6f0:	sete   %al
 105d6f3:	or     %cl,%al
 105d6f5:	je     105d5d9 <myl_native_dictionary_read+0x169>
 105d6fb:	add    $0x8,%rsp
 105d6ff:	pop    %rbx
 105d700:	pop    %r12
 105d702:	pop    %r13
 105d704:	pop    %r14
 105d706:	pop    %r15
 105d708:	pop    %rbp
 105d709:	jmp    105d710 <read_walk>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
