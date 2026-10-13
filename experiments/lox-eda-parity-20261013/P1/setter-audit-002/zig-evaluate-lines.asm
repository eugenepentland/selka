
/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/lox-eda-20261012/reference-binaries/lox-zig-fast:     file format elf64-x86-64


Disassembly of section .text:

00000000010855b0 <interpreter.Interpreter.evaluate>:
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:213
 10855b0:	55                   	push   %rbp
 10855b1:	48 89 e5             	mov    %rsp,%rbp
 10855b4:	41 57                	push   %r15
 10855b6:	41 56                	push   %r14
 10855b8:	41 55                	push   %r13
 10855ba:	41 54                	push   %r12
 10855bc:	53                   	push   %rbx
 10855bd:	48 81 ec e8 00 00 00 	sub    $0xe8,%rsp
 10855c4:	49 89 fe             	mov    %rdi,%r14
 10855c7:	eb 20                	jmp    10855e9 <interpreter.Interpreter.evaluate+0x39>
 10855c9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:246
 10855d0:	41 80 7f 10 1e       	cmpb   $0x1e,0x10(%r15)
 10855d5:	0f 84 2a 10 00 00    	je     1086605 <interpreter.Interpreter.evaluate+0x1055>
heap.Runtime.pop():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:121
 10855db:	48 ff c8             	dec    %rax
 10855de:	48 89 83 90 00 00 00 	mov    %rax,0x90(%rbx)
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:248 (discriminator 4)
 10855e5:	49 8b 77 08          	mov    0x8(%r15),%rsi
 10855e9:	49 89 f7             	mov    %rsi,%r15
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:214
 10855ec:	49 8b 1e             	mov    (%r14),%rbx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:215
 10855ef:	48 8b 36             	mov    (%rsi),%rsi
 10855f2:	41 8b 47 10          	mov    0x10(%r15),%eax
 10855f6:	41 0f b6 4f 30       	movzbl 0x30(%r15),%ecx
 10855fb:	ff 24 cd f8 eb 00 01 	jmp    *0x100ebf8(,%rcx,8)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:243
 1085602:	4c 89 f7             	mov    %r14,%rdi
 1085605:	e8 a6 ff ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 108560a:	66 85 c0             	test   %ax,%ax
 108560d:	0f 85 f4 0f 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:244
 1085613:	48 8b 8b 80 00 00 00 	mov    0x80(%rbx),%rcx
 108561a:	48 8b 83 90 00 00 00 	mov    0x90(%rbx),%rax
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 1085621:	48 89 c2             	mov    %rax,%rdx
 1085624:	48 c1 e2 04          	shl    $0x4,%rdx
 1085628:	0f b6 74 11 f8       	movzbl -0x8(%rcx,%rdx,1),%esi
value.isFalsey():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:35
 108562d:	8d 7e fe             	lea    -0x2(%rsi),%edi
 1085630:	83 ff 02             	cmp    $0x2,%edi
 1085633:	72 9b                	jb     10855d0 <interpreter.Interpreter.evaluate+0x20>
 1085635:	83 fe 01             	cmp    $0x1,%esi
 1085638:	75 1b                	jne    1085655 <interpreter.Interpreter.evaluate+0xa5>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:244
 108563a:	48 01 d1             	add    %rdx,%rcx
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 108563d:	0f b6 49 f0          	movzbl -0x10(%rcx),%ecx
value.isFalsey():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:35 (discriminator 6)
 1085641:	80 e1 01             	and    $0x1,%cl
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:246
 1085644:	41 80 7f 10 1e       	cmpb   $0x1e,0x10(%r15)
 1085649:	0f 94 c2             	sete   %dl
 108564c:	38 ca                	cmp    %cl,%dl
 108564e:	75 8b                	jne    10855db <interpreter.Interpreter.evaluate+0x2b>
 1085650:	e9 b0 0f 00 00       	jmp    1086605 <interpreter.Interpreter.evaluate+0x1055>
 1085655:	41 80 7f 10 1e       	cmpb   $0x1e,0x10(%r15)
 108565a:	0f 84 7b ff ff ff    	je     10855db <interpreter.Interpreter.evaluate+0x2b>
 1085660:	e9 a0 0f 00 00       	jmp    1086605 <interpreter.Interpreter.evaluate+0x1055>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:274
 1085665:	4c 89 f7             	mov    %r14,%rdi
 1085668:	e8 43 ff ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 108566d:	66 85 c0             	test   %ax,%ax
 1085670:	0f 85 91 0f 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:275
 1085676:	48 8b 8b 80 00 00 00 	mov    0x80(%rbx),%rcx
 108567d:	48 8b 93 90 00 00 00 	mov    0x90(%rbx),%rdx
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 1085684:	48 c1 e2 04          	shl    $0x4,%rdx
 1085688:	48 8d 04 11          	lea    (%rcx,%rdx,1),%rax
 108568c:	c5 fa 7e 44 11 f0    	vmovq  -0x10(%rcx,%rdx,1),%xmm0
 1085692:	0f b6 4c 11 f8       	movzbl -0x8(%rcx,%rdx,1),%ecx
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:276
 1085697:	41 80 7f 0c 0b       	cmpb   $0xb,0xc(%r15)
 108569c:	0f 85 3f 07 00 00    	jne    1085de1 <interpreter.Interpreter.evaluate+0x831>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:276 (discriminator 2)
 10856a2:	c6 40 f8 01          	movb   $0x1,-0x8(%rax)
value.isFalsey():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:35
 10856a6:	0f b6 d1             	movzbl %cl,%edx
 10856a9:	8d 4a fe             	lea    -0x2(%rdx),%ecx
 10856ac:	83 f9 02             	cmp    $0x2,%ecx
 10856af:	0f 83 6e 0b 00 00    	jae    1086223 <interpreter.Interpreter.evaluate+0xc73>
interpreter.Interpreter.evaluate():
 10856b5:	31 c9                	xor    %ecx,%ecx
 10856b7:	e9 71 0b 00 00       	jmp    108622d <interpreter.Interpreter.evaluate+0xc7d>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:272
 10856bc:	49 8b 77 04          	mov    0x4(%r15),%rsi
 10856c0:	48 89 f0             	mov    %rsi,%rax
 10856c3:	48 c1 e8 20          	shr    $0x20,%rax
 10856c7:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
interpreter.Interpreter.envAt():
 10856cd:	8b bb f0 06 00 00    	mov    0x6f0(%rbx),%edi
 10856d3:	48 8b 4b 20          	mov    0x20(%rbx),%rcx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 10856d7:	49 21 f0             	and    %rsi,%r8
 10856da:	0f 84 93 00 00 00    	je     1085773 <interpreter.Interpreter.evaluate+0x1c3>
 10856e0:	89 f2                	mov    %esi,%edx
 10856e2:	83 e2 07             	and    $0x7,%edx
 10856e5:	41 83 f8 08          	cmp    $0x8,%r8d
 10856e9:	72 75                	jb     1085760 <interpreter.Interpreter.evaluate+0x1b0>
 10856eb:	83 e6 f8             	and    $0xfffffff8,%esi
value.ObjRef.index():
 10856ee:	66 90                	xchg   %ax,%ax
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 10856f0:	89 ff                	mov    %edi,%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 10856f2:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 10856f6:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 10856fa:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 10856fe:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085702:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085706:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 108570a:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 108570e:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085712:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085716:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 108571a:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 108571e:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085722:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085726:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 108572a:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 108572e:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085732:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085736:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 108573a:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 108573e:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085742:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085746:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 108574a:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 108574e:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 1085752:	48 83 c6 f8          	add    $0xfffffffffffffff8,%rsi
 1085756:	75 98                	jne    10856f0 <interpreter.Interpreter.evaluate+0x140>
 1085758:	48 85 d2             	test   %rdx,%rdx
 108575b:	74 16                	je     1085773 <interpreter.Interpreter.evaluate+0x1c3>
value.ObjRef.index():
 108575d:	0f 1f 00             	nopl   (%rax)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085760:	89 fe                	mov    %edi,%esi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085762:	48 8d 34 76          	lea    (%rsi,%rsi,2),%rsi
 1085766:	48 c1 e6 04          	shl    $0x4,%rsi
interpreter.Interpreter.envAt():
 108576a:	8b 7c 31 10          	mov    0x10(%rcx,%rsi,1),%edi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 108576e:	48 ff ca             	dec    %rdx
 1085771:	75 ed                	jne    1085760 <interpreter.Interpreter.evaluate+0x1b0>
value.ObjRef.index():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085773:	89 fa                	mov    %edi,%edx
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085775:	48 8d 14 52          	lea    (%rdx,%rdx,2),%rdx
 1085779:	48 c1 e2 04          	shl    $0x4,%rdx
interpreter.Interpreter.slotAt():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:81
 108577d:	48 8b 0c 11          	mov    (%rcx,%rdx,1),%rcx
 1085781:	48 c1 e0 04          	shl    $0x4,%rax
heap.Runtime.push():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:115
 1085785:	48 8b 93 80 00 00 00 	mov    0x80(%rbx),%rdx
 108578c:	48 8b b3 90 00 00 00 	mov    0x90(%rbx),%rsi
 1085793:	48 c1 e6 04          	shl    $0x4,%rsi
 1085797:	c5 f8 10 04 01       	vmovups (%rcx,%rax,1),%xmm0
 108579c:	c5 f8 11 04 32       	vmovups %xmm0,(%rdx,%rsi,1)
interpreter.Interpreter.evaluate():
 10857a1:	e9 58 0e 00 00       	jmp    10865fe <interpreter.Interpreter.evaluate+0x104e>
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:303
 10857a6:	4c 89 f7             	mov    %r14,%rdi
 10857a9:	e8 02 fe ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 10857ae:	66 85 c0             	test   %ax,%ax
 10857b1:	0f 85 50 0e 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:304
 10857b7:	49 8b 77 08          	mov    0x8(%r15),%rsi
 10857bb:	4c 89 f7             	mov    %r14,%rdi
 10857be:	e8 ed fd ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 10857c3:	66 85 c0             	test   %ax,%ax
 10857c6:	0f 85 3b 0e 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:305
 10857cc:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 10857d3:	48 8b 8b 90 00 00 00 	mov    0x90(%rbx),%rcx
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 10857da:	48 89 ce             	mov    %rcx,%rsi
 10857dd:	48 c1 e6 04          	shl    $0x4,%rsi
 10857e1:	0f b6 54 30 e8       	movzbl -0x18(%rax,%rsi,1),%edx
 10857e6:	c5 fb 10 4c 30 e0    	vmovsd -0x20(%rax,%rsi,1),%xmm1
 10857ec:	c5 fb 10 44 30 f0    	vmovsd -0x10(%rax,%rsi,1),%xmm0
 10857f2:	0f b6 74 30 f8       	movzbl -0x8(%rax,%rsi,1),%esi
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:307
 10857f7:	41 0f b6 7f 14       	movzbl 0x14(%r15),%edi
 10857fc:	83 ff 07             	cmp    $0x7,%edi
 10857ff:	0f 84 07 0b 00 00    	je     108630c <interpreter.Interpreter.evaluate+0xd5c>
 1085805:	83 ff 0c             	cmp    $0xc,%edi
 1085808:	0f 84 ec 0a 00 00    	je     10862fa <interpreter.Interpreter.evaluate+0xd4a>
 108580e:	83 ff 0e             	cmp    $0xe,%edi
 1085811:	0f 85 16 0b 00 00    	jne    108632d <interpreter.Interpreter.evaluate+0xd7d>
value.valuesEqual():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:45
 1085817:	0f b6 d2             	movzbl %dl,%edx
 108581a:	ff 24 d5 78 ec 00 01 	jmp    *0x100ec78(,%rdx,8)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:45 (discriminator 4)
 1085821:	40 84 f6             	test   %sil,%sil
 1085824:	e9 ac 0d 00 00       	jmp    10865d5 <interpreter.Interpreter.evaluate+0x1025>
interpreter.Interpreter.evaluateGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:341
 1085829:	4c 89 f7             	mov    %r14,%rdi
 108582c:	e8 7f fd ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 1085831:	66 85 c0             	test   %ax,%ax
 1085834:	0f 85 cd 0d 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:342
 108583a:	48 8b bb 80 00 00 00 	mov    0x80(%rbx),%rdi
 1085841:	4c 8b 83 90 00 00 00 	mov    0x90(%rbx),%r8
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 1085848:	49 c1 e0 04          	shl    $0x4,%r8
 108584c:	c4 a1 7a 6f 44 07 f0 	vmovdqu -0x10(%rdi,%r8,1),%xmm0
 1085853:	c5 f9 7f 45 80       	vmovdqa %xmm0,-0x80(%rbp)
heap.Runtime.isInstance():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:192
 1085858:	80 7d 88 03          	cmpb   $0x3,-0x78(%rbp)
 108585c:	0f 85 3e 04 00 00    	jne    1085ca0 <interpreter.Interpreter.evaluate+0x6f0>
interpreter.Interpreter.evaluateGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:342
 1085862:	8b 45 80             	mov    -0x80(%rbp),%eax
heap.Runtime.isInstance():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:192 (discriminator 4)
 1085865:	48 8b 53 20          	mov    0x20(%rbx),%rdx
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085869:	48 8d 34 40          	lea    (%rax,%rax,2),%rsi
 108586d:	48 c1 e6 04          	shl    $0x4,%rsi
heap.Runtime.isInstance():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:192 (discriminator 4)
 1085871:	80 7c 32 20 07       	cmpb   $0x7,0x20(%rdx,%rsi,1)
interpreter.Interpreter.evaluateGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:343
 1085876:	0f 85 24 04 00 00    	jne    1085ca0 <interpreter.Interpreter.evaluate+0x6f0>
 108587c:	48 01 d6             	add    %rdx,%rsi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:347
 108587f:	41 8b 47 18          	mov    0x18(%r15),%eax
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085883:	48 8d 0c 40          	lea    (%rax,%rax,2),%rcx
 1085887:	48 c1 e1 04          	shl    $0x4,%rcx
heap.Runtime.stringHash():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:152
 108588b:	8b 4c 0a 10          	mov    0x10(%rdx,%rcx,1),%ecx
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:60
 108588f:	48 83 7e 10 00       	cmpq   $0x0,0x10(%rsi)
 1085894:	0f 84 b4 0a 00 00    	je     108634e <interpreter.Interpreter.evaluate+0xd9e>
interpreter.Interpreter.evaluateGet():
 108589a:	4c 01 c7             	add    %r8,%rdi
 108589d:	48 83 c7 f0          	add    $0xfffffffffffffff0,%rdi
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:61
 10858a1:	4c 8b 06             	mov    (%rsi),%r8
 10858a4:	4c 8b 4e 08          	mov    0x8(%rsi),%r9
table.Table.findEntry():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:43
 10858a8:	49 ff c9             	dec    %r9
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:44
 10858ab:	45 89 ca             	mov    %r9d,%r10d
 10858ae:	41 21 ca             	and    %ecx,%r10d
 10858b1:	45 31 db             	xor    %r11d,%r11d
 10858b4:	eb 17                	jmp    10858cd <interpreter.Interpreter.evaluate+0x31d>
 10858b6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 10858bd:	00 00 00 
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:49
 10858c0:	41 39 44 24 10       	cmp    %eax,0x10(%r12)
 10858c5:	74 36                	je     10858fd <interpreter.Interpreter.evaluate+0x34d>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:46
 10858c7:	49 ff c2             	inc    %r10
 10858ca:	4d 21 ca             	and    %r9,%r10
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:47
 10858cd:	4d 89 d5             	mov    %r10,%r13
 10858d0:	49 c1 e5 05          	shl    $0x5,%r13
 10858d4:	4f 8d 24 28          	lea    (%r8,%r13,1),%r12
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:48
 10858d8:	43 f6 44 28 14 01    	testb  $0x1,0x14(%r8,%r13,1)
 10858de:	75 e0                	jne    10858c0 <interpreter.Interpreter.evaluate+0x310>
 10858e0:	4d 85 db             	test   %r11,%r11
 10858e3:	4d 0f 44 dc          	cmove  %r12,%r11
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:50
 10858e7:	41 80 7c 24 08 00    	cmpb   $0x0,0x8(%r12)
 10858ed:	75 d8                	jne    10858c7 <interpreter.Interpreter.evaluate+0x317>
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:62
 10858ef:	41 80 7b 14 01       	cmpb   $0x1,0x14(%r11)
 10858f4:	4d 89 dc             	mov    %r11,%r12
 10858f7:	0f 85 51 0a 00 00    	jne    108634e <interpreter.Interpreter.evaluate+0xd9e>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:63
 10858fd:	c4 c1 7a 6f 04 24    	vmovdqu (%r12),%xmm0
heap.Runtime.tableGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:207
 1085903:	c5 f9 7f 85 20 ff ff 	vmovdqa %xmm0,-0xe0(%rbp)
 108590a:	ff 
interpreter.Interpreter.evaluateGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:348
 108590b:	c5 fa 7f 07          	vmovdqu %xmm0,(%rdi)
 108590f:	e9 f1 0c 00 00       	jmp    1086605 <interpreter.Interpreter.evaluate+0x1055>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:217
 1085914:	49 8b 77 18          	mov    0x18(%r15),%rsi
 1085918:	4c 89 f7             	mov    %r14,%rdi
 108591b:	e8 90 fc ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 1085920:	66 85 c0             	test   %ax,%ax
 1085923:	0f 85 de 0c 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:218
 1085929:	41 80 7f 28 01       	cmpb   $0x1,0x28(%r15)
 108592e:	0f 85 c8 04 00 00    	jne    1085dfc <interpreter.Interpreter.evaluate+0x84c>
 1085934:	49 8b 77 20          	mov    0x20(%r15),%rsi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:218 (discriminator 2)
 1085938:	48 89 f0             	mov    %rsi,%rax
 108593b:	48 c1 e8 20          	shr    $0x20,%rax
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:219
 108593f:	49 8b 0e             	mov    (%r14),%rcx
 1085942:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
interpreter.Interpreter.envAt():
 1085948:	8b b9 f0 06 00 00    	mov    0x6f0(%rcx),%edi
 108594e:	48 8b 49 20          	mov    0x20(%rcx),%rcx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 1085952:	49 21 f0             	and    %rsi,%r8
 1085955:	0f 84 98 00 00 00    	je     10859f3 <interpreter.Interpreter.evaluate+0x443>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 108595b:	89 f2                	mov    %esi,%edx
 108595d:	83 e2 07             	and    $0x7,%edx
 1085960:	41 83 f8 08          	cmp    $0x8,%r8d
 1085964:	72 7a                	jb     10859e0 <interpreter.Interpreter.evaluate+0x430>
 1085966:	83 e6 f8             	and    $0xfffffff8,%esi
value.ObjRef.index():
 1085969:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085970:	89 ff                	mov    %edi,%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085972:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085976:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 108597a:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 108597e:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085982:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085986:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 108598a:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 108598e:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085992:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085996:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 108599a:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 108599e:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 10859a2:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 10859a6:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 10859aa:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 10859ae:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 10859b2:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 10859b6:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 10859ba:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 10859be:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 10859c2:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 10859c6:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 10859ca:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 10859ce:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 10859d2:	48 83 c6 f8          	add    $0xfffffffffffffff8,%rsi
 10859d6:	75 98                	jne    1085970 <interpreter.Interpreter.evaluate+0x3c0>
 10859d8:	48 85 d2             	test   %rdx,%rdx
 10859db:	74 16                	je     10859f3 <interpreter.Interpreter.evaluate+0x443>
value.ObjRef.index():
 10859dd:	0f 1f 00             	nopl   (%rax)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 10859e0:	89 fe                	mov    %edi,%esi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 10859e2:	48 8d 34 76          	lea    (%rsi,%rsi,2),%rsi
 10859e6:	48 c1 e6 04          	shl    $0x4,%rsi
interpreter.Interpreter.envAt():
 10859ea:	8b 7c 31 10          	mov    0x10(%rcx,%rsi,1),%edi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 10859ee:	48 ff ca             	dec    %rdx
 10859f1:	75 ed                	jne    10859e0 <interpreter.Interpreter.evaluate+0x430>
value.ObjRef.index():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 10859f3:	89 fa                	mov    %edi,%edx
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 10859f5:	48 8d 14 52          	lea    (%rdx,%rdx,2),%rdx
 10859f9:	48 c1 e2 04          	shl    $0x4,%rdx
interpreter.Interpreter.slotAt():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:81
 10859fd:	48 8b 0c 11          	mov    (%rcx,%rdx,1),%rcx
 1085a01:	48 c1 e0 04          	shl    $0x4,%rax
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:219 (discriminator 2)
 1085a05:	48 8b 93 80 00 00 00 	mov    0x80(%rbx),%rdx
 1085a0c:	48 8b b3 90 00 00 00 	mov    0x90(%rbx),%rsi
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 1085a13:	48 c1 e6 04          	shl    $0x4,%rsi
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:219
 1085a17:	c5 fa 6f 44 32 f0    	vmovdqu -0x10(%rdx,%rsi,1),%xmm0
 1085a1d:	c5 fa 7f 04 01       	vmovdqu %xmm0,(%rcx,%rax,1)
 1085a22:	e9 de 0b 00 00       	jmp    1086605 <interpreter.Interpreter.evaluate+0x1055>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:215
 1085a27:	41 0f b6 4f 18       	movzbl 0x18(%r15),%ecx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:236
 1085a2c:	ff 24 cd 58 ec 00 01 	jmp    *0x100ec58(,%rcx,8)
 1085a33:	b8 90 05 00 01       	mov    $0x1000590,%eax
 1085a38:	e9 c6 07 00 00       	jmp    1086203 <interpreter.Interpreter.evaluate+0xc53>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:229
 1085a3d:	4c 8b a3 90 00 00 00 	mov    0x90(%rbx),%r12
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:230
 1085a44:	4c 89 f7             	mov    %r14,%rdi
 1085a47:	e8 64 fb ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 1085a4c:	66 85 c0             	test   %ax,%ax
 1085a4f:	0f 85 b2 0b 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:231
 1085a55:	4d 8b 6f 10          	mov    0x10(%r15),%r13
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:231 (discriminator 2)
 1085a59:	4d 85 ed             	test   %r13,%r13
 1085a5c:	0f 84 09 06 00 00    	je     108606b <interpreter.Interpreter.evaluate+0xabb>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:231
 1085a62:	49 8b 5f 08          	mov    0x8(%r15),%rbx
 1085a66:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 1085a6d:	00 00 00 
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:231 (discriminator 6)
 1085a70:	4c 89 f7             	mov    %r14,%rdi
 1085a73:	48 89 de             	mov    %rbx,%rsi
 1085a76:	e8 35 fb ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 1085a7b:	66 85 c0             	test   %ax,%ax
 1085a7e:	0f 85 83 0b 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:231 (discriminator 2)
 1085a84:	48 83 c3 38          	add    $0x38,%rbx
 1085a88:	49 ff cd             	dec    %r13
 1085a8b:	75 e3                	jne    1085a70 <interpreter.Interpreter.evaluate+0x4c0>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:232
 1085a8d:	49 8b 4f 10          	mov    0x10(%r15),%rcx
 1085a91:	e9 d7 05 00 00       	jmp    108606d <interpreter.Interpreter.evaluate+0xabd>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:252
 1085a96:	4c 89 f7             	mov    %r14,%rdi
 1085a99:	e8 12 fb ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 1085a9e:	66 85 c0             	test   %ax,%ax
 1085aa1:	0f 85 60 0b 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:253
 1085aa7:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 1085aae:	48 8b 8b 90 00 00 00 	mov    0x90(%rbx),%rcx
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 1085ab5:	48 c1 e1 04          	shl    $0x4,%rcx
heap.Runtime.isInstance():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:192
 1085ab9:	80 7c 08 f8 03       	cmpb   $0x3,-0x8(%rax,%rcx,1)
 1085abe:	0f 85 7d 02 00 00    	jne    1085d41 <interpreter.Interpreter.evaluate+0x791>
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 1085ac4:	48 01 c8             	add    %rcx,%rax
 1085ac7:	8b 40 f0             	mov    -0x10(%rax),%eax
heap.Runtime.isInstance():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:192 (discriminator 4)
 1085aca:	48 8b 4b 20          	mov    0x20(%rbx),%rcx
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085ace:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 1085ad2:	48 c1 e0 04          	shl    $0x4,%rax
heap.Runtime.isInstance():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:192 (discriminator 4)
 1085ad6:	80 7c 01 20 07       	cmpb   $0x7,0x20(%rcx,%rax,1)
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:253
 1085adb:	0f 85 60 02 00 00    	jne    1085d41 <interpreter.Interpreter.evaluate+0x791>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:256
 1085ae1:	49 8b 77 20          	mov    0x20(%r15),%rsi
 1085ae5:	4c 89 f7             	mov    %r14,%rdi
 1085ae8:	e8 c3 fa ff ff       	call   10855b0 <interpreter.Interpreter.evaluate>
 1085aed:	66 85 c0             	test   %ax,%ax
 1085af0:	0f 85 11 0b 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:257
 1085af6:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 1085afd:	48 8b 8b 90 00 00 00 	mov    0x90(%rbx),%rcx
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 1085b04:	48 c1 e1 04          	shl    $0x4,%rcx
 1085b08:	c5 f8 10 44 08 f0    	vmovups -0x10(%rax,%rcx,1),%xmm0
 1085b0e:	c5 f8 29 85 50 ff ff 	vmovaps %xmm0,-0xb0(%rbp)
 1085b15:	ff 
 1085b16:	8b 44 08 e0          	mov    -0x20(%rax,%rcx,1),%eax
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:258 (discriminator 4)
 1085b1a:	48 8b 53 20          	mov    0x20(%rbx),%rdx
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085b1e:	48 8d 34 40          	lea    (%rax,%rax,2),%rsi
 1085b22:	48 c1 e6 04          	shl    $0x4,%rsi
 1085b26:	48 01 d6             	add    %rdx,%rsi
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:258
 1085b29:	41 8b 4f 18          	mov    0x18(%r15),%ecx
heap.Runtime.tableSet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:212
 1085b2d:	c5 f8 10 03          	vmovups (%rbx),%xmm0
 1085b31:	c5 f8 29 45 b0       	vmovaps %xmm0,-0x50(%rbp)
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085b36:	48 8d 04 49          	lea    (%rcx,%rcx,2),%rax
 1085b3a:	48 c1 e0 04          	shl    $0x4,%rax
heap.Runtime.stringHash():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:152
 1085b3e:	44 8b 44 02 10       	mov    0x10(%rdx,%rax,1),%r8d
 1085b43:	48 8d 7d a0          	lea    -0x60(%rbp),%rdi
 1085b47:	48 8d 55 b0          	lea    -0x50(%rbp),%rdx
 1085b4b:	4c 8d 8d 50 ff ff ff 	lea    -0xb0(%rbp),%r9
heap.Runtime.tableSet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:212 (discriminator 2)
 1085b52:	e8 49 f6 ff ff       	call   10851a0 <table.Table.set>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:212
 1085b57:	0f b7 45 a0          	movzwl -0x60(%rbp),%eax
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:258
 1085b5b:	66 85 c0             	test   %ax,%ax
 1085b5e:	0f 85 a3 0a 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
heap.Runtime.push():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:115
 1085b64:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:259
 1085b6b:	48 8b 8b 90 00 00 00 	mov    0x90(%rbx),%rcx
 1085b72:	48 83 c1 fe          	add    $0xfffffffffffffffe,%rcx
 1085b76:	48 89 8b 90 00 00 00 	mov    %rcx,0x90(%rbx)
heap.Runtime.push():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:115
 1085b7d:	48 c1 e1 04          	shl    $0x4,%rcx
 1085b81:	c5 f8 28 85 50 ff ff 	vmovaps -0xb0(%rbp),%xmm0
 1085b88:	ff 
 1085b89:	c5 f8 11 04 08       	vmovups %xmm0,(%rax,%rcx,1)
interpreter.Interpreter.evaluate():
 1085b8e:	e9 6b 0a 00 00       	jmp    10865fe <interpreter.Interpreter.evaluate+0x104e>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:263
 1085b93:	41 8b 57 1c          	mov    0x1c(%r15),%edx
interpreter.Interpreter.envAt():
 1085b97:	8b bb f0 06 00 00    	mov    0x6f0(%rbx),%edi
 1085b9d:	48 8b 4b 20          	mov    0x20(%rbx),%rcx
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:263
 1085ba1:	48 85 d2             	test   %rdx,%rdx
interpreter.Interpreter.envAt():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 1085ba4:	0f 84 1d 03 00 00    	je     1085ec7 <interpreter.Interpreter.evaluate+0x917>
 1085baa:	41 89 d0             	mov    %edx,%r8d
 1085bad:	41 83 e0 07          	and    $0x7,%r8d
 1085bb1:	41 89 fa             	mov    %edi,%r10d
 1085bb4:	83 fa 08             	cmp    $0x8,%edx
 1085bb7:	0f 82 93 00 00 00    	jb     1085c50 <interpreter.Interpreter.evaluate+0x6a0>
 1085bbd:	41 89 d1             	mov    %edx,%r9d
 1085bc0:	41 83 e1 f8          	and    $0xfffffff8,%r9d
 1085bc4:	41 89 fa             	mov    %edi,%r10d
value.ObjRef.index():
 1085bc7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1085bce:	00 00 
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085bd0:	45 89 d2             	mov    %r10d,%r10d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085bd3:	4f 8d 14 52          	lea    (%r10,%r10,2),%r10
 1085bd7:	49 c1 e2 04          	shl    $0x4,%r10
interpreter.Interpreter.envAt():
 1085bdb:	46 8b 54 11 10       	mov    0x10(%rcx,%r10,1),%r10d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085be0:	4f 8d 14 52          	lea    (%r10,%r10,2),%r10
 1085be4:	49 c1 e2 04          	shl    $0x4,%r10
interpreter.Interpreter.envAt():
 1085be8:	46 8b 54 11 10       	mov    0x10(%rcx,%r10,1),%r10d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085bed:	4f 8d 14 52          	lea    (%r10,%r10,2),%r10
 1085bf1:	49 c1 e2 04          	shl    $0x4,%r10
interpreter.Interpreter.envAt():
 1085bf5:	46 8b 54 11 10       	mov    0x10(%rcx,%r10,1),%r10d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085bfa:	4f 8d 14 52          	lea    (%r10,%r10,2),%r10
 1085bfe:	49 c1 e2 04          	shl    $0x4,%r10
interpreter.Interpreter.envAt():
 1085c02:	46 8b 54 11 10       	mov    0x10(%rcx,%r10,1),%r10d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085c07:	4f 8d 14 52          	lea    (%r10,%r10,2),%r10
 1085c0b:	49 c1 e2 04          	shl    $0x4,%r10
interpreter.Interpreter.envAt():
 1085c0f:	46 8b 54 11 10       	mov    0x10(%rcx,%r10,1),%r10d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085c14:	4f 8d 14 52          	lea    (%r10,%r10,2),%r10
 1085c18:	49 c1 e2 04          	shl    $0x4,%r10
interpreter.Interpreter.envAt():
 1085c1c:	46 8b 54 11 10       	mov    0x10(%rcx,%r10,1),%r10d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085c21:	4f 8d 14 52          	lea    (%r10,%r10,2),%r10
 1085c25:	49 c1 e2 04          	shl    $0x4,%r10
interpreter.Interpreter.envAt():
 1085c29:	46 8b 54 11 10       	mov    0x10(%rcx,%r10,1),%r10d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085c2e:	4f 8d 14 52          	lea    (%r10,%r10,2),%r10
 1085c32:	49 c1 e2 04          	shl    $0x4,%r10
interpreter.Interpreter.envAt():
 1085c36:	46 8b 54 11 10       	mov    0x10(%rcx,%r10,1),%r10d
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 1085c3b:	49 83 c1 f8          	add    $0xfffffffffffffff8,%r9
 1085c3f:	75 8f                	jne    1085bd0 <interpreter.Interpreter.evaluate+0x620>
 1085c41:	4d 85 c0             	test   %r8,%r8
 1085c44:	74 1f                	je     1085c65 <interpreter.Interpreter.evaluate+0x6b5>
value.ObjRef.index():
 1085c46:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 1085c4d:	00 00 00 
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085c50:	45 89 d1             	mov    %r10d,%r9d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085c53:	4f 8d 0c 49          	lea    (%r9,%r9,2),%r9
 1085c57:	49 c1 e1 04          	shl    $0x4,%r9
interpreter.Interpreter.envAt():
 1085c5b:	46 8b 54 09 10       	mov    0x10(%rcx,%r9,1),%r10d
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 1085c60:	49 ff c8             	dec    %r8
 1085c63:	75 eb                	jne    1085c50 <interpreter.Interpreter.evaluate+0x6a0>
value.ObjRef.index():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085c65:	45 89 d0             	mov    %r10d,%r8d
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085c68:	4f 8d 04 40          	lea    (%r8,%r8,2),%r8
 1085c6c:	49 c1 e0 04          	shl    $0x4,%r8
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:264
 1085c70:	4e 8b 04 01          	mov    (%rcx,%r8,1),%r8
 1085c74:	45 8b 00             	mov    (%r8),%r8d
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:265
 1085c77:	ff ca                	dec    %edx
interpreter.Interpreter.envAt():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 1085c79:	0f 85 5c 02 00 00    	jne    1085edb <interpreter.Interpreter.evaluate+0x92b>
 1085c7f:	e9 ef 02 00 00       	jmp    1085f73 <interpreter.Interpreter.evaluate+0x9c3>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:285 (discriminator 2)
 1085c84:	4c 89 f7             	mov    %r14,%rdi
 1085c87:	4c 89 fe             	mov    %r15,%rsi
 1085c8a:	48 81 c4 e8 00 00 00 	add    $0xe8,%rsp
 1085c91:	5b                   	pop    %rbx
 1085c92:	41 5c                	pop    %r12
 1085c94:	41 5d                	pop    %r13
 1085c96:	41 5e                	pop    %r14
 1085c98:	41 5f                	pop    %r15
 1085c9a:	5d                   	pop    %rbp
 1085c9b:	e9 d0 09 00 00       	jmp    1086670 <interpreter.Interpreter.evaluateVariable>
interpreter.Interpreter.evaluateGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:344
 1085ca0:	41 8b 47 1c          	mov    0x1c(%r15),%eax
 1085ca4:	89 45 d4             	mov    %eax,-0x2c(%rbp)
interpreter.Interpreter.runtimeError__anon_31195():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:60
 1085ca7:	4d 8b 6e 08          	mov    0x8(%r14),%r13
output.Output.diagnostic__anon_31230():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/output.zig:59
 1085cab:	4d 8b 7d 08          	mov    0x8(%r13),%r15
 1085caf:	31 db                	xor    %ebx,%ebx
Io.Writer.writeAll():
 1085cb1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1085cb8:	0f 1f 84 00 00 00 00 
 1085cbf:	00 
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 6)
 1085cc0:	48 8d b3 20 b2 01 01 	lea    0x101b220(%rbx),%rsi
 1085cc7:	41 bc 20 00 00 00    	mov    $0x20,%r12d
 1085ccd:	49 29 dc             	sub    %rbx,%r12
Io.Writer.write():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:534
 1085cd0:	49 8b 7f 18          	mov    0x18(%r15),%rdi
 1085cd4:	4a 8d 04 27          	lea    (%rdi,%r12,1),%rax
 1085cd8:	49 3b 47 10          	cmp    0x10(%r15),%rax
 1085cdc:	77 1e                	ja     1085cfc <interpreter.Interpreter.evaluate+0x74c>
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:536
 1085cde:	49 03 7f 08          	add    0x8(%r15),%rdi
 1085ce2:	4c 89 e2             	mov    %r12,%rdx
 1085ce5:	e8 06 d2 01 00       	call   10a2ef0 <compiler_rt.memcpy.memcpyFast>
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:537
 1085cea:	4d 01 67 18          	add    %r12,0x18(%r15)
Io.Writer.writeAll():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 12)
 1085cee:	4c 01 e3             	add    %r12,%rbx
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 2)
 1085cf1:	48 83 fb 20          	cmp    $0x20,%rbx
 1085cf5:	72 c9                	jb     1085cc0 <interpreter.Interpreter.evaluate+0x710>
 1085cf7:	e9 cd 05 00 00       	jmp    10862c9 <interpreter.Interpreter.evaluate+0xd19>
Io.Writer.write():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:540
 1085cfc:	49 8b 07             	mov    (%r15),%rax
 1085cff:	48 8b 00             	mov    (%rax),%rax
 1085d02:	48 89 75 a0          	mov    %rsi,-0x60(%rbp)
 1085d06:	4c 89 65 a8          	mov    %r12,-0x58(%rbp)
 1085d0a:	b9 01 00 00 00       	mov    $0x1,%ecx
 1085d0f:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 1085d15:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
 1085d19:	4c 89 fe             	mov    %r15,%rsi
 1085d1c:	48 8d 55 a0          	lea    -0x60(%rbp),%rdx
 1085d20:	ff d0                	call   *%rax
 1085d22:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
Io.Writer.writeAll():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 6)
 1085d26:	66 85 c0             	test   %ax,%ax
 1085d29:	0f 85 d8 08 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
 1085d2f:	4c 8b 65 b0          	mov    -0x50(%rbp),%r12
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 12)
 1085d33:	4c 01 e3             	add    %r12,%rbx
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 2)
 1085d36:	48 83 fb 20          	cmp    $0x20,%rbx
 1085d3a:	72 84                	jb     1085cc0 <interpreter.Interpreter.evaluate+0x710>
 1085d3c:	e9 88 05 00 00       	jmp    10862c9 <interpreter.Interpreter.evaluate+0xd19>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:254
 1085d41:	41 8b 47 1c          	mov    0x1c(%r15),%eax
 1085d45:	89 45 d4             	mov    %eax,-0x2c(%rbp)
interpreter.Interpreter.runtimeError__anon_30886():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:60
 1085d48:	4d 8b 6e 08          	mov    0x8(%r14),%r13
output.Output.diagnostic__anon_31180():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/output.zig:59
 1085d4c:	4d 8b 7d 08          	mov    0x8(%r13),%r15
 1085d50:	31 db                	xor    %ebx,%ebx
Io.Writer.writeAll():
 1085d52:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1085d59:	1f 84 00 00 00 00 00 
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 6)
 1085d60:	48 8d b3 ef 63 01 01 	lea    0x10163ef(%rbx),%rsi
 1085d67:	41 bc 1c 00 00 00    	mov    $0x1c,%r12d
 1085d6d:	49 29 dc             	sub    %rbx,%r12
Io.Writer.write():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:534
 1085d70:	49 8b 7f 18          	mov    0x18(%r15),%rdi
 1085d74:	4a 8d 04 27          	lea    (%rdi,%r12,1),%rax
 1085d78:	49 3b 47 10          	cmp    0x10(%r15),%rax
 1085d7c:	77 1e                	ja     1085d9c <interpreter.Interpreter.evaluate+0x7ec>
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:536
 1085d7e:	49 03 7f 08          	add    0x8(%r15),%rdi
 1085d82:	4c 89 e2             	mov    %r12,%rdx
 1085d85:	e8 66 d1 01 00       	call   10a2ef0 <compiler_rt.memcpy.memcpyFast>
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:537
 1085d8a:	4d 01 67 18          	add    %r12,0x18(%r15)
Io.Writer.writeAll():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 12)
 1085d8e:	4c 01 e3             	add    %r12,%rbx
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 2)
 1085d91:	48 83 fb 1c          	cmp    $0x1c,%rbx
 1085d95:	72 c9                	jb     1085d60 <interpreter.Interpreter.evaluate+0x7b0>
 1085d97:	e9 2d 05 00 00       	jmp    10862c9 <interpreter.Interpreter.evaluate+0xd19>
Io.Writer.write():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:540
 1085d9c:	49 8b 07             	mov    (%r15),%rax
 1085d9f:	48 8b 00             	mov    (%rax),%rax
 1085da2:	48 89 75 a0          	mov    %rsi,-0x60(%rbp)
 1085da6:	4c 89 65 a8          	mov    %r12,-0x58(%rbp)
 1085daa:	b9 01 00 00 00       	mov    $0x1,%ecx
 1085daf:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 1085db5:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
 1085db9:	4c 89 fe             	mov    %r15,%rsi
 1085dbc:	48 8d 55 a0          	lea    -0x60(%rbp),%rdx
 1085dc0:	ff d0                	call   *%rax
 1085dc2:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
Io.Writer.writeAll():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 6)
 1085dc6:	66 85 c0             	test   %ax,%ax
 1085dc9:	0f 85 38 08 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
 1085dcf:	4c 8b 65 b0          	mov    -0x50(%rbp),%r12
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 12)
 1085dd3:	4c 01 e3             	add    %r12,%rbx
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 2)
 1085dd6:	48 83 fb 1c          	cmp    $0x1c,%rbx
 1085dda:	72 84                	jb     1085d60 <interpreter.Interpreter.evaluate+0x7b0>
 1085ddc:	e9 e8 04 00 00       	jmp    10862c9 <interpreter.Interpreter.evaluate+0xd19>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:278
 1085de1:	80 f9 02             	cmp    $0x2,%cl
 1085de4:	0f 85 4b 04 00 00    	jne    1086235 <interpreter.Interpreter.evaluate+0xc85>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:279
 1085dea:	c5 f9 ef 05 de a7 f7 	vpxor  -0x85822(%rip),%xmm0,%xmm0        # 10005d0 <__anon_42106+0x10>
 1085df1:	ff 
 1085df2:	c5 f9 d6 40 f0       	vmovq  %xmm0,-0x10(%rax)
 1085df7:	e9 09 08 00 00       	jmp    1086605 <interpreter.Interpreter.evaluate+0x1055>
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:60
 1085dfc:	48 83 7b 78 00       	cmpq   $0x0,0x78(%rbx)
 1085e01:	0f 84 9a 03 00 00    	je     10861a1 <interpreter.Interpreter.evaluate+0xbf1>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:221
 1085e07:	48 8d 73 68          	lea    0x68(%rbx),%rsi
 1085e0b:	41 8b 4f 10          	mov    0x10(%r15),%ecx
 1085e0f:	48 8b 43 20          	mov    0x20(%rbx),%rax
heap.Runtime.tableGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:207
 1085e13:	48 8d 14 49          	lea    (%rcx,%rcx,2),%rdx
 1085e17:	48 c1 e2 04          	shl    $0x4,%rdx
 1085e1b:	44 8b 44 10 10       	mov    0x10(%rax,%rdx,1),%r8d
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:61
 1085e20:	48 8b 43 68          	mov    0x68(%rbx),%rax
 1085e24:	48 8b 53 70          	mov    0x70(%rbx),%rdx
table.Table.findEntry():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:43
 1085e28:	48 ff ca             	dec    %rdx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:44
 1085e2b:	89 d7                	mov    %edx,%edi
 1085e2d:	44 21 c7             	and    %r8d,%edi
 1085e30:	45 31 c9             	xor    %r9d,%r9d
 1085e33:	eb 17                	jmp    1085e4c <interpreter.Interpreter.evaluate+0x89c>
 1085e35:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 1085e3c:	00 00 00 00 
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:49
 1085e40:	41 39 4a 10          	cmp    %ecx,0x10(%r10)
 1085e44:	74 32                	je     1085e78 <interpreter.Interpreter.evaluate+0x8c8>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:46
 1085e46:	48 ff c7             	inc    %rdi
 1085e49:	48 21 d7             	and    %rdx,%rdi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:47
 1085e4c:	49 89 fb             	mov    %rdi,%r11
 1085e4f:	49 c1 e3 05          	shl    $0x5,%r11
 1085e53:	4e 8d 14 18          	lea    (%rax,%r11,1),%r10
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:48
 1085e57:	42 f6 44 18 14 01    	testb  $0x1,0x14(%rax,%r11,1)
 1085e5d:	75 e1                	jne    1085e40 <interpreter.Interpreter.evaluate+0x890>
 1085e5f:	4d 85 c9             	test   %r9,%r9
 1085e62:	4d 0f 44 ca          	cmove  %r10,%r9
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:50
 1085e66:	41 80 7a 08 00       	cmpb   $0x0,0x8(%r10)
 1085e6b:	75 d9                	jne    1085e46 <interpreter.Interpreter.evaluate+0x896>
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:62
 1085e6d:	41 f6 41 14 01       	testb  $0x1,0x14(%r9)
 1085e72:	0f 84 29 03 00 00    	je     10861a1 <interpreter.Interpreter.evaluate+0xbf1>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:224 (discriminator 2)
 1085e78:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 1085e7f:	48 8b 93 90 00 00 00 	mov    0x90(%rbx),%rdx
heap.Runtime.peek():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:127
 1085e86:	48 c1 e2 04          	shl    $0x4,%rdx
 1085e8a:	c5 f8 10 44 10 f0    	vmovups -0x10(%rax,%rdx,1),%xmm0
 1085e90:	c5 f8 29 85 40 ff ff 	vmovaps %xmm0,-0xc0(%rbp)
 1085e97:	ff 
heap.Runtime.tableSet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:212
 1085e98:	c5 fa 6f 03          	vmovdqu (%rbx),%xmm0
 1085e9c:	c5 f9 7f 45 b0       	vmovdqa %xmm0,-0x50(%rbp)
 1085ea1:	48 8d 7d a0          	lea    -0x60(%rbp),%rdi
 1085ea5:	48 8d 55 b0          	lea    -0x50(%rbp),%rdx
 1085ea9:	4c 8d 8d 40 ff ff ff 	lea    -0xc0(%rbp),%r9
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:212 (discriminator 2)
 1085eb0:	e8 eb f2 ff ff       	call   10851a0 <table.Table.set>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:212
 1085eb5:	0f b7 45 a0          	movzwl -0x60(%rbp),%eax
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:224 (discriminator 2)
 1085eb9:	66 85 c0             	test   %ax,%ax
 1085ebc:	0f 84 43 07 00 00    	je     1086605 <interpreter.Interpreter.evaluate+0x1055>
 1085ec2:	e9 40 07 00 00       	jmp    1086607 <interpreter.Interpreter.evaluate+0x1057>
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085ec7:	48 8d 14 7f          	lea    (%rdi,%rdi,2),%rdx
 1085ecb:	48 c1 e2 04          	shl    $0x4,%rdx
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:264
 1085ecf:	48 8b 14 11          	mov    (%rcx,%rdx,1),%rdx
 1085ed3:	44 8b 02             	mov    (%rdx),%r8d
 1085ed6:	ba ff ff ff ff       	mov    $0xffffffff,%edx
interpreter.Interpreter.envAt():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 1085edb:	4c 8d 52 ff          	lea    -0x1(%rdx),%r10
 1085edf:	41 89 d1             	mov    %edx,%r9d
 1085ee2:	41 83 e1 07          	and    $0x7,%r9d
 1085ee6:	49 83 fa 07          	cmp    $0x7,%r10
 1085eea:	72 74                	jb     1085f60 <interpreter.Interpreter.evaluate+0x9b0>
 1085eec:	83 e2 f8             	and    $0xfffffff8,%edx
value.ObjRef.index():
 1085eef:	90                   	nop
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085ef0:	89 ff                	mov    %edi,%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085ef2:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085ef6:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085efa:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085efe:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085f02:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085f06:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085f0a:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085f0e:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085f12:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085f16:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085f1a:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085f1e:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085f22:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085f26:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085f2a:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085f2e:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085f32:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085f36:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085f3a:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085f3e:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085f42:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085f46:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
 1085f4a:	48 c1 e7 04          	shl    $0x4,%rdi
interpreter.Interpreter.envAt():
 1085f4e:	8b 7c 39 10          	mov    0x10(%rcx,%rdi,1),%edi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 1085f52:	48 83 c2 f8          	add    $0xfffffffffffffff8,%rdx
 1085f56:	75 98                	jne    1085ef0 <interpreter.Interpreter.evaluate+0x940>
 1085f58:	4d 85 c9             	test   %r9,%r9
 1085f5b:	74 16                	je     1085f73 <interpreter.Interpreter.evaluate+0x9c3>
value.ObjRef.index():
 1085f5d:	0f 1f 00             	nopl   (%rax)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085f60:	89 fa                	mov    %edi,%edx
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085f62:	48 8d 14 52          	lea    (%rdx,%rdx,2),%rdx
 1085f66:	48 c1 e2 04          	shl    $0x4,%rdx
interpreter.Interpreter.envAt():
 1085f6a:	8b 7c 11 10          	mov    0x10(%rcx,%rdx,1),%edi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:76 (discriminator 2)
 1085f6e:	49 ff c9             	dec    %r9
 1085f71:	75 ed                	jne    1085f60 <interpreter.Interpreter.evaluate+0x9b0>
value.ObjRef.index():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085f73:	89 fa                	mov    %edi,%edx
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085f75:	48 8d 14 52          	lea    (%rdx,%rdx,2),%rdx
 1085f79:	48 c1 e2 04          	shl    $0x4,%rdx
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:265
 1085f7d:	48 8b 14 11          	mov    (%rcx,%rdx,1),%rdx
 1085f81:	c5 fa 6f 02          	vmovdqu (%rdx),%xmm0
 1085f85:	c5 f9 7f 85 30 ff ff 	vmovdqa %xmm0,-0xd0(%rbp)
 1085f8c:	ff 
value.ObjRef.index():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1085f8d:	44 89 c2             	mov    %r8d,%edx
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085f90:	48 8d 3c 52          	lea    (%rdx,%rdx,2),%rdi
 1085f94:	48 c1 e7 04          	shl    $0x4,%rdi
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:60
 1085f98:	48 83 7c 39 10 00    	cmpq   $0x0,0x10(%rcx,%rdi,1)
 1085f9e:	0f 84 a8 00 00 00    	je     108604c <interpreter.Interpreter.evaluate+0xa9c>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:266
 1085fa4:	48 01 cf             	add    %rcx,%rdi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1085fa7:	4c 8d 04 40          	lea    (%rax,%rax,2),%r8
 1085fab:	49 c1 e0 04          	shl    $0x4,%r8
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:61
 1085faf:	48 8b 17             	mov    (%rdi),%rdx
 1085fb2:	48 8b 7f 08          	mov    0x8(%rdi),%rdi
table.Table.findEntry():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:43
 1085fb6:	48 ff cf             	dec    %rdi
 1085fb9:	42 8b 4c 01 10       	mov    0x10(%rcx,%r8,1),%ecx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:44
 1085fbe:	21 f9                	and    %edi,%ecx
 1085fc0:	45 31 c0             	xor    %r8d,%r8d
 1085fc3:	eb 17                	jmp    1085fdc <interpreter.Interpreter.evaluate+0xa2c>
 1085fc5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 1085fcc:	00 00 00 00 
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:49
 1085fd0:	41 39 41 10          	cmp    %eax,0x10(%r9)
 1085fd4:	74 31                	je     1086007 <interpreter.Interpreter.evaluate+0xa57>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:46
 1085fd6:	48 ff c1             	inc    %rcx
 1085fd9:	48 21 f9             	and    %rdi,%rcx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:47
 1085fdc:	49 89 ca             	mov    %rcx,%r10
 1085fdf:	49 c1 e2 05          	shl    $0x5,%r10
 1085fe3:	4e 8d 0c 12          	lea    (%rdx,%r10,1),%r9
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:48
 1085fe7:	42 f6 44 12 14 01    	testb  $0x1,0x14(%rdx,%r10,1)
 1085fed:	75 e1                	jne    1085fd0 <interpreter.Interpreter.evaluate+0xa20>
 1085fef:	4d 85 c0             	test   %r8,%r8
 1085ff2:	4d 0f 44 c1          	cmove  %r9,%r8
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:50
 1085ff6:	41 80 79 08 00       	cmpb   $0x0,0x8(%r9)
 1085ffb:	75 d9                	jne    1085fd6 <interpreter.Interpreter.evaluate+0xa26>
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:62
 1085ffd:	41 f6 40 14 01       	testb  $0x1,0x14(%r8)
 1086002:	4d 89 c1             	mov    %r8,%r9
 1086005:	74 45                	je     108604c <interpreter.Interpreter.evaluate+0xa9c>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:63
 1086007:	41 8b 09             	mov    (%r9),%ecx
 108600a:	48 8d 7d 98          	lea    -0x68(%rbp),%rdi
 108600e:	48 8d 95 30 ff ff ff 	lea    -0xd0(%rbp),%rdx
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:269
 1086015:	4c 89 f6             	mov    %r14,%rsi
 1086018:	e8 93 0c 00 00       	call   1086cb0 <interpreter.Interpreter.bind>
 108601d:	0f b7 45 9c          	movzwl -0x64(%rbp),%eax
 1086021:	66 85 c0             	test   %ax,%ax
 1086024:	0f 85 dd 05 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:269 (discriminator 4)
 108602a:	8b 45 98             	mov    -0x68(%rbp),%eax
heap.Runtime.push():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:115
 108602d:	48 8b 8b 80 00 00 00 	mov    0x80(%rbx),%rcx
 1086034:	48 8b 93 90 00 00 00 	mov    0x90(%rbx),%rdx
 108603b:	48 c1 e2 04          	shl    $0x4,%rdx
 108603f:	89 04 11             	mov    %eax,(%rcx,%rdx,1)
 1086042:	c6 44 11 08 03       	movb   $0x3,0x8(%rcx,%rdx,1)
interpreter.Interpreter.evaluate():
 1086047:	e9 b2 05 00 00       	jmp    10865fe <interpreter.Interpreter.evaluate+0x104e>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:267 (discriminator 2)
 108604c:	41 8b 5f 14          	mov    0x14(%r15),%ebx
 1086050:	49 8b 57 08          	mov    0x8(%r15),%rdx
interpreter.Interpreter.runtimeError__anon_30904():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:60
 1086054:	49 8b 7e 08          	mov    0x8(%r14),%rdi
 1086058:	e8 e3 0d 00 00       	call   1086e40 <output.Output.diagnostic__anon_31132>
interpreter.Interpreter.evaluate():
 108605d:	66 85 c0             	test   %ax,%ax
 1086060:	0f 85 a1 05 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
 1086066:	e9 53 01 00 00       	jmp    10861be <interpreter.Interpreter.evaluate+0xc0e>
 108606b:	31 c9                	xor    %ecx,%ecx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:232
 108606d:	45 8b 4f 18          	mov    0x18(%r15),%r9d
 1086071:	4c 89 a5 68 ff ff ff 	mov    %r12,-0x98(%rbp)
 1086078:	48 89 8d 70 ff ff ff 	mov    %rcx,-0x90(%rbp)
 108607f:	44 89 8d 78 ff ff ff 	mov    %r9d,-0x88(%rbp)
interpreter.Interpreter.callValue():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:377
 1086086:	49 8b 1e             	mov    (%r14),%rbx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:378
 1086089:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 1086090:	4d 89 e7             	mov    %r12,%r15
 1086093:	49 c1 e7 04          	shl    $0x4,%r15
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:379
 1086097:	42 80 7c 38 08 03    	cmpb   $0x3,0x8(%rax,%r15,1)
 108609d:	75 72                	jne    1086111 <interpreter.Interpreter.evaluate+0xb61>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:378
 108609f:	4c 01 f8             	add    %r15,%rax
 10860a2:	8b 30                	mov    (%rax),%esi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:380
 10860a4:	48 8b 43 20          	mov    0x20(%rbx),%rax
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 10860a8:	48 8d 14 76          	lea    (%rsi,%rsi,2),%rdx
 10860ac:	48 c1 e2 04          	shl    $0x4,%rdx
interpreter.Interpreter.callValue():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:380
 10860b0:	0f b6 3c 10          	movzbl (%rax,%rdx,1),%edi
 10860b4:	44 0f b6 44 10 20    	movzbl 0x20(%rax,%rdx,1),%r8d
 10860ba:	41 83 f8 03          	cmp    $0x3,%r8d
 10860be:	0f 84 f9 03 00 00    	je     10864bd <interpreter.Interpreter.evaluate+0xf0d>
 10860c4:	41 83 f8 06          	cmp    $0x6,%r8d
 10860c8:	0f 84 db 03 00 00    	je     10864a9 <interpreter.Interpreter.evaluate+0xef9>
 10860ce:	41 83 f8 0a          	cmp    $0xa,%r8d
 10860d2:	75 3d                	jne    1086111 <interpreter.Interpreter.evaluate+0xb61>
 10860d4:	48 01 d0             	add    %rdx,%rax
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:380 (discriminator 2)
 10860d7:	40 88 7d b0          	mov    %dil,-0x50(%rbp)
 10860db:	c5 fa 6f 40 01       	vmovdqu 0x1(%rax),%xmm0
 10860e0:	c5 fa 7f 45 b1       	vmovdqu %xmm0,-0x4f(%rbp)
 10860e5:	48 8b 40 10          	mov    0x10(%rax),%rax
 10860e9:	48 89 45 c0          	mov    %rax,-0x40(%rbp)
 10860ed:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:381
 10860f1:	48 89 45 a0          	mov    %rax,-0x60(%rbp)
 10860f5:	48 8d 75 b0          	lea    -0x50(%rbp),%rsi
 10860f9:	48 8d 95 68 ff ff ff 	lea    -0x98(%rbp),%rdx
 1086100:	48 8d 4d a0          	lea    -0x60(%rbp),%rcx
 1086104:	4c 89 f7             	mov    %r14,%rdi
 1086107:	e8 64 18 00 00       	call   1087970 <interpreter.Interpreter.callFunction>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:385
 108610c:	e9 f6 04 00 00       	jmp    1086607 <interpreter.Interpreter.evaluate+0x1057>
 1086111:	44 89 4d d4          	mov    %r9d,-0x2c(%rbp)
interpreter.Interpreter.runtimeError__anon_31266():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:60
 1086115:	4d 8b 6e 08          	mov    0x8(%r14),%r13
output.Output.diagnostic__anon_31276():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/output.zig:59
 1086119:	4d 8b 7d 08          	mov    0x8(%r13),%r15
 108611d:	31 db                	xor    %ebx,%ebx
Io.Writer.writeAll():
 108611f:	90                   	nop
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 6)
 1086120:	48 8d b3 0b 64 01 01 	lea    0x101640b(%rbx),%rsi
 1086127:	41 bc 25 00 00 00    	mov    $0x25,%r12d
 108612d:	49 29 dc             	sub    %rbx,%r12
Io.Writer.write():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:534
 1086130:	49 8b 7f 18          	mov    0x18(%r15),%rdi
 1086134:	4a 8d 04 27          	lea    (%rdi,%r12,1),%rax
 1086138:	49 3b 47 10          	cmp    0x10(%r15),%rax
 108613c:	77 1e                	ja     108615c <interpreter.Interpreter.evaluate+0xbac>
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:536
 108613e:	49 03 7f 08          	add    0x8(%r15),%rdi
 1086142:	4c 89 e2             	mov    %r12,%rdx
 1086145:	e8 a6 cd 01 00       	call   10a2ef0 <compiler_rt.memcpy.memcpyFast>
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:537
 108614a:	4d 01 67 18          	add    %r12,0x18(%r15)
Io.Writer.writeAll():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 12)
 108614e:	4c 01 e3             	add    %r12,%rbx
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 2)
 1086151:	48 83 fb 25          	cmp    $0x25,%rbx
 1086155:	72 c9                	jb     1086120 <interpreter.Interpreter.evaluate+0xb70>
 1086157:	e9 6d 01 00 00       	jmp    10862c9 <interpreter.Interpreter.evaluate+0xd19>
Io.Writer.write():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:540
 108615c:	49 8b 07             	mov    (%r15),%rax
 108615f:	48 8b 00             	mov    (%rax),%rax
 1086162:	48 89 75 a0          	mov    %rsi,-0x60(%rbp)
 1086166:	4c 89 65 a8          	mov    %r12,-0x58(%rbp)
 108616a:	b9 01 00 00 00       	mov    $0x1,%ecx
 108616f:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 1086175:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
 1086179:	4c 89 fe             	mov    %r15,%rsi
 108617c:	48 8d 55 a0          	lea    -0x60(%rbp),%rdx
 1086180:	ff d0                	call   *%rax
 1086182:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
Io.Writer.writeAll():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 6)
 1086186:	66 85 c0             	test   %ax,%ax
 1086189:	0f 85 78 04 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
 108618f:	4c 8b 65 b0          	mov    -0x50(%rbp),%r12
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 12)
 1086193:	4c 01 e3             	add    %r12,%rbx
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 2)
 1086196:	48 83 fb 25          	cmp    $0x25,%rbx
 108619a:	72 84                	jb     1086120 <interpreter.Interpreter.evaluate+0xb70>
 108619c:	e9 28 01 00 00       	jmp    10862c9 <interpreter.Interpreter.evaluate+0xd19>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:222
 10861a1:	41 8b 5f 14          	mov    0x14(%r15),%ebx
 10861a5:	49 8b 37             	mov    (%r15),%rsi
 10861a8:	49 8b 57 08          	mov    0x8(%r15),%rdx
interpreter.Interpreter.runtimeError__anon_30842():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:60
 10861ac:	49 8b 7e 08          	mov    0x8(%r14),%rdi
 10861b0:	e8 db 24 00 00       	call   1088690 <output.Output.diagnostic__anon_31746>
interpreter.Interpreter.evaluate():
 10861b5:	66 85 c0             	test   %ax,%ax
 10861b8:	0f 85 49 04 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
 10861be:	49 8b 7e 08          	mov    0x8(%r14),%rdi
 10861c2:	89 de                	mov    %ebx,%esi
 10861c4:	e9 1a 01 00 00       	jmp    10862e3 <interpreter.Interpreter.evaluate+0xd33>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:236 (discriminator 10)
 10861c9:	48 89 b5 00 ff ff ff 	mov    %rsi,-0x100(%rbp)
 10861d0:	b1 02                	mov    $0x2,%cl
 10861d2:	48 8d 85 00 ff ff ff 	lea    -0x100(%rbp),%rax
 10861d9:	eb 25                	jmp    1086200 <interpreter.Interpreter.evaluate+0xc50>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:240 (discriminator 2)
 10861db:	89 85 f0 fe ff ff    	mov    %eax,-0x110(%rbp)
 10861e1:	b1 03                	mov    $0x3,%cl
 10861e3:	48 8d 85 f0 fe ff ff 	lea    -0x110(%rbp),%rax
 10861ea:	eb 14                	jmp    1086200 <interpreter.Interpreter.evaluate+0xc50>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:236 (discriminator 8)
 10861ec:	40 80 e6 01          	and    $0x1,%sil
 10861f0:	40 88 b5 10 ff ff ff 	mov    %sil,-0xf0(%rbp)
 10861f7:	b1 01                	mov    $0x1,%cl
 10861f9:	48 8d 85 10 ff ff ff 	lea    -0xf0(%rbp),%rax
 1086200:	88 48 08             	mov    %cl,0x8(%rax)
heap.Runtime.push():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:115
 1086203:	48 8b 8b 80 00 00 00 	mov    0x80(%rbx),%rcx
 108620a:	48 8b 93 90 00 00 00 	mov    0x90(%rbx),%rdx
 1086211:	48 c1 e2 04          	shl    $0x4,%rdx
 1086215:	c5 fa 6f 00          	vmovdqu (%rax),%xmm0
 1086219:	c5 fa 7f 04 11       	vmovdqu %xmm0,(%rcx,%rdx,1)
interpreter.Interpreter.evaluate():
 108621e:	e9 db 03 00 00       	jmp    10865fe <interpreter.Interpreter.evaluate+0x104e>
 1086223:	b1 01                	mov    $0x1,%cl
value.isFalsey():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:35
 1086225:	85 d2                	test   %edx,%edx
 1086227:	0f 85 d4 01 00 00    	jne    1086401 <interpreter.Interpreter.evaluate+0xe51>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:277
 108622d:	88 48 f0             	mov    %cl,-0x10(%rax)
 1086230:	e9 d0 03 00 00       	jmp    1086605 <interpreter.Interpreter.evaluate+0x1055>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:281 (discriminator 2)
 1086235:	41 8b 47 08          	mov    0x8(%r15),%eax
 1086239:	89 45 d4             	mov    %eax,-0x2c(%rbp)
interpreter.Interpreter.runtimeError__anon_30925():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:60
 108623c:	4d 8b 6e 08          	mov    0x8(%r14),%r13
output.Output.diagnostic__anon_31084():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/output.zig:59
 1086240:	4d 8b 7d 08          	mov    0x8(%r13),%r15
 1086244:	31 db                	xor    %ebx,%ebx
Io.Writer.writeAll():
 1086246:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 108624d:	00 00 00 
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 6)
 1086250:	48 8d b3 be 63 01 01 	lea    0x10163be(%rbx),%rsi
 1086257:	41 bc 1a 00 00 00    	mov    $0x1a,%r12d
 108625d:	49 29 dc             	sub    %rbx,%r12
Io.Writer.write():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:534
 1086260:	49 8b 7f 18          	mov    0x18(%r15),%rdi
 1086264:	4a 8d 04 27          	lea    (%rdi,%r12,1),%rax
 1086268:	49 3b 47 10          	cmp    0x10(%r15),%rax
 108626c:	77 1b                	ja     1086289 <interpreter.Interpreter.evaluate+0xcd9>
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:536
 108626e:	49 03 7f 08          	add    0x8(%r15),%rdi
 1086272:	4c 89 e2             	mov    %r12,%rdx
 1086275:	e8 76 cc 01 00       	call   10a2ef0 <compiler_rt.memcpy.memcpyFast>
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:537
 108627a:	4d 01 67 18          	add    %r12,0x18(%r15)
Io.Writer.writeAll():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 12)
 108627e:	4c 01 e3             	add    %r12,%rbx
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 2)
 1086281:	48 83 fb 1a          	cmp    $0x1a,%rbx
 1086285:	72 c9                	jb     1086250 <interpreter.Interpreter.evaluate+0xca0>
 1086287:	eb 40                	jmp    10862c9 <interpreter.Interpreter.evaluate+0xd19>
Io.Writer.write():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:540
 1086289:	49 8b 07             	mov    (%r15),%rax
 108628c:	48 8b 00             	mov    (%rax),%rax
 108628f:	48 89 75 a0          	mov    %rsi,-0x60(%rbp)
 1086293:	4c 89 65 a8          	mov    %r12,-0x58(%rbp)
 1086297:	b9 01 00 00 00       	mov    $0x1,%ecx
 108629c:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 10862a2:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
 10862a6:	4c 89 fe             	mov    %r15,%rsi
 10862a9:	48 8d 55 a0          	lea    -0x60(%rbp),%rdx
 10862ad:	ff d0                	call   *%rax
 10862af:	0f b7 45 b8          	movzwl -0x48(%rbp),%eax
Io.Writer.writeAll():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 6)
 10862b3:	66 85 c0             	test   %ax,%ax
 10862b6:	0f 85 4b 03 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
 10862bc:	4c 8b 65 b0          	mov    -0x50(%rbp),%r12
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 12)
 10862c0:	4c 01 e3             	add    %r12,%rbx
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io/Writer.zig:552 (discriminator 2)
 10862c3:	48 83 fb 1a          	cmp    $0x1a,%rbx
 10862c7:	72 87                	jb     1086250 <interpreter.Interpreter.evaluate+0xca0>
interpreter.Interpreter.evaluate():
 10862c9:	49 8b 7d 08          	mov    0x8(%r13),%rdi
 10862cd:	48 8b 07             	mov    (%rdi),%rax
 10862d0:	ff 50 10             	call   *0x10(%rax)
 10862d3:	66 85 c0             	test   %ax,%ax
 10862d6:	0f 85 2b 03 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
 10862dc:	49 8b 7e 08          	mov    0x8(%r14),%rdi
 10862e0:	8b 75 d4             	mov    -0x2c(%rbp),%esi
 10862e3:	e8 48 07 00 00       	call   1086a30 <output.Output.diagnostic__anon_30986>
 10862e8:	89 c1                	mov    %eax,%ecx
 10862ea:	66 85 c0             	test   %ax,%ax
 10862ed:	b8 a7 00 00 00       	mov    $0xa7,%eax
 10862f2:	0f 45 c1             	cmovne %ecx,%eax
interpreter.Interpreter.runtimeError__anon_30842():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:61
 10862f5:	e9 0d 03 00 00       	jmp    1086607 <interpreter.Interpreter.evaluate+0x1057>
value.valuesEqual():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:45
 10862fa:	0f b6 d2             	movzbl %dl,%edx
 10862fd:	ff 24 d5 98 ec 00 01 	jmp    *0x100ec98(,%rdx,8)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:45 (discriminator 4)
 1086304:	40 84 f6             	test   %sil,%sil
 1086307:	e9 93 02 00 00       	jmp    108659f <interpreter.Interpreter.evaluate+0xfef>
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:310
 108630c:	89 d7                	mov    %edx,%edi
 108630e:	40 80 f7 02          	xor    $0x2,%dil
 1086312:	41 89 f0             	mov    %esi,%r8d
 1086315:	41 80 f0 02          	xor    $0x2,%r8b
 1086319:	41 08 f8             	or     %dil,%r8b
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:310 (discriminator 2)
 108631c:	0f 85 f1 00 00 00    	jne    1086413 <interpreter.Interpreter.evaluate+0xe63>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:311
 1086322:	c5 f3 58 c0          	vaddsd %xmm0,%xmm1,%xmm0
 1086326:	b2 02                	mov    $0x2,%dl
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:330
 1086328:	e9 b9 02 00 00       	jmp    10865e6 <interpreter.Interpreter.evaluate+0x1036>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:318
 108632d:	80 f2 02             	xor    $0x2,%dl
 1086330:	40 80 f6 02          	xor    $0x2,%sil
 1086334:	40 08 d6             	or     %dl,%sil
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:318 (discriminator 2)
 1086337:	0f 84 57 01 00 00    	je     1086494 <interpreter.Interpreter.evaluate+0xee4>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:319
 108633d:	41 8b 77 10          	mov    0x10(%r15),%esi
 1086341:	4c 89 f7             	mov    %r14,%rdi
 1086344:	e8 67 1e 00 00       	call   10881b0 <interpreter.Interpreter.runtimeError__anon_31576>
interpreter.Interpreter.callValue():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:385
 1086349:	e9 b9 02 00 00       	jmp    1086607 <interpreter.Interpreter.evaluate+0x1057>
table.Table.get():
 108634e:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
heap.Runtime.tableGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:207
 1086352:	c5 f9 7f 85 20 ff ff 	vmovdqa %xmm0,-0xe0(%rbp)
 1086359:	ff 
interpreter.Interpreter.evaluateGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:351
 108635a:	8b 76 18             	mov    0x18(%rsi),%esi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 108635d:	48 8d 34 76          	lea    (%rsi,%rsi,2),%rsi
 1086361:	48 c1 e6 04          	shl    $0x4,%rsi
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:60
 1086365:	48 83 7c 32 10 00    	cmpq   $0x0,0x10(%rdx,%rsi,1)
 108636b:	0f 84 b5 01 00 00    	je     1086526 <interpreter.Interpreter.evaluate+0xf76>
interpreter.Interpreter.evaluateGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:351
 1086371:	48 01 f2             	add    %rsi,%rdx
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:61
 1086374:	48 8b 32             	mov    (%rdx),%rsi
 1086377:	48 8b 52 08          	mov    0x8(%rdx),%rdx
table.Table.findEntry():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:43
 108637b:	48 ff ca             	dec    %rdx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:44
 108637e:	21 d1                	and    %edx,%ecx
 1086380:	31 ff                	xor    %edi,%edi
 1086382:	eb 0c                	jmp    1086390 <interpreter.Interpreter.evaluate+0xde0>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:49
 1086384:	41 39 40 10          	cmp    %eax,0x10(%r8)
 1086388:	74 34                	je     10863be <interpreter.Interpreter.evaluate+0xe0e>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:46
 108638a:	48 ff c1             	inc    %rcx
 108638d:	48 21 d1             	and    %rdx,%rcx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:47
 1086390:	49 89 c9             	mov    %rcx,%r9
 1086393:	49 c1 e1 05          	shl    $0x5,%r9
 1086397:	4e 8d 04 0e          	lea    (%rsi,%r9,1),%r8
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:48
 108639b:	42 f6 44 0e 14 01    	testb  $0x1,0x14(%rsi,%r9,1)
 10863a1:	75 e1                	jne    1086384 <interpreter.Interpreter.evaluate+0xdd4>
 10863a3:	48 85 ff             	test   %rdi,%rdi
 10863a6:	49 0f 44 f8          	cmove  %r8,%rdi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:50
 10863aa:	41 80 78 08 00       	cmpb   $0x0,0x8(%r8)
 10863af:	75 d9                	jne    108638a <interpreter.Interpreter.evaluate+0xdda>
table.Table.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:62
 10863b1:	80 7f 14 01          	cmpb   $0x1,0x14(%rdi)
 10863b5:	49 89 f8             	mov    %rdi,%r8
 10863b8:	0f 85 68 01 00 00    	jne    1086526 <interpreter.Interpreter.evaluate+0xf76>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/table.zig:63
 10863be:	41 8b 08             	mov    (%r8),%ecx
 10863c1:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
 10863c5:	48 8d 55 80          	lea    -0x80(%rbp),%rdx
interpreter.Interpreter.evaluateGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:354
 10863c9:	4c 89 f6             	mov    %r14,%rsi
 10863cc:	e8 df 08 00 00       	call   1086cb0 <interpreter.Interpreter.bind>
 10863d1:	0f b7 45 b4          	movzwl -0x4c(%rbp),%eax
 10863d5:	66 85 c0             	test   %ax,%ax
 10863d8:	0f 85 29 02 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:354 (discriminator 4)
 10863de:	8b 45 b0             	mov    -0x50(%rbp),%eax
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:355
 10863e1:	48 8b 8b 80 00 00 00 	mov    0x80(%rbx),%rcx
 10863e8:	48 8b 93 90 00 00 00 	mov    0x90(%rbx),%rdx
 10863ef:	48 c1 e2 04          	shl    $0x4,%rdx
 10863f3:	c6 44 11 f8 03       	movb   $0x3,-0x8(%rcx,%rdx,1)
 10863f8:	89 44 11 f0          	mov    %eax,-0x10(%rcx,%rdx,1)
 10863fc:	e9 04 02 00 00       	jmp    1086605 <interpreter.Interpreter.evaluate+0x1055>
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:277
 1086401:	c4 e1 f9 7e c1       	vmovq  %xmm0,%rcx
value.isFalsey():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:35 (discriminator 6)
 1086406:	f6 d1                	not    %cl
interpreter.Interpreter.evaluate():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:277
 1086408:	80 e1 01             	and    $0x1,%cl
 108640b:	88 48 f0             	mov    %cl,-0x10(%rax)
 108640e:	e9 f2 01 00 00       	jmp    1086605 <interpreter.Interpreter.evaluate+0x1055>
heap.Runtime.isString():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:202
 1086413:	80 fa 03             	cmp    $0x3,%dl
 1086416:	0f 85 f9 00 00 00    	jne    1086515 <interpreter.Interpreter.evaluate+0xf65>
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:312
 108641c:	c4 e1 f9 7e ca       	vmovq  %xmm1,%rdx
heap.Runtime.isString():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:202 (discriminator 4)
 1086421:	48 8b 43 20          	mov    0x20(%rbx),%rax
value.ObjRef.index():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1086425:	89 d1                	mov    %edx,%ecx
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 1086427:	48 8d 0c 49          	lea    (%rcx,%rcx,2),%rcx
 108642b:	48 c1 e1 04          	shl    $0x4,%rcx
heap.Runtime.isString():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:202 (discriminator 4)
 108642f:	80 7c 08 20 01       	cmpb   $0x1,0x20(%rax,%rcx,1)
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:312
 1086434:	0f 85 db 00 00 00    	jne    1086515 <interpreter.Interpreter.evaluate+0xf65>
heap.Runtime.isString():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:202
 108643a:	40 80 fe 03          	cmp    $0x3,%sil
 108643e:	0f 85 d1 00 00 00    	jne    1086515 <interpreter.Interpreter.evaluate+0xf65>
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:312 (discriminator 4)
 1086444:	c4 e1 f9 7e c1       	vmovq  %xmm0,%rcx
value.ObjRef.index():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:13
 1086449:	89 ce                	mov    %ecx,%esi
heap.Runtime.get():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:137
 108644b:	48 8d 34 76          	lea    (%rsi,%rsi,2),%rsi
 108644f:	48 c1 e6 04          	shl    $0x4,%rsi
heap.Runtime.isString():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:202 (discriminator 4)
 1086453:	80 7c 30 20 01       	cmpb   $0x1,0x20(%rax,%rsi,1)
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:312 (discriminator 2)
 1086458:	0f 85 b7 00 00 00    	jne    1086515 <interpreter.Interpreter.evaluate+0xf65>
 108645e:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:314
 1086462:	48 89 de             	mov    %rbx,%rsi
 1086465:	e8 06 1f 00 00       	call   1088370 <strings.concat>
 108646a:	0f b7 45 b4          	movzwl -0x4c(%rbp),%eax
 108646e:	66 85 c0             	test   %ax,%ax
 1086471:	0f 85 90 01 00 00    	jne    1086607 <interpreter.Interpreter.evaluate+0x1057>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:314 (discriminator 4)
 1086477:	8b 45 b0             	mov    -0x50(%rbp),%eax
 108647a:	c4 e1 f9 6e c0       	vmovq  %rax,%xmm0
heap.Runtime.push():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:115
 108647f:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:335
 1086486:	48 8b 8b 90 00 00 00 	mov    0x90(%rbx),%rcx
 108648d:	b2 03                	mov    $0x3,%dl
 108648f:	e9 52 01 00 00       	jmp    10865e6 <interpreter.Interpreter.evaluate+0x1036>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:323
 1086494:	83 c7 fa             	add    $0xfffffffa,%edi
 1086497:	ff 24 fd b8 ec 00 01 	jmp    *0x100ecb8(,%rdi,8)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:328
 108649e:	c5 f3 5c c0          	vsubsd %xmm0,%xmm1,%xmm0
 10864a2:	b2 02                	mov    $0x2,%dl
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:330
 10864a4:	e9 3d 01 00 00       	jmp    10865e6 <interpreter.Interpreter.evaluate+0x1036>
interpreter.Interpreter.evaluate():
 10864a9:	48 8d 95 68 ff ff ff 	lea    -0x98(%rbp),%rdx
interpreter.Interpreter.callValue():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:382
 10864b0:	4c 89 f7             	mov    %r14,%rdi
 10864b3:	e8 c8 0f 00 00       	call   1087480 <interpreter.Interpreter.callClass>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:385
 10864b8:	e9 4a 01 00 00       	jmp    1086607 <interpreter.Interpreter.evaluate+0x1057>
 10864bd:	40 0f b6 d7          	movzbl %dil,%edx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:384
 10864c1:	48 39 d1             	cmp    %rdx,%rcx
 10864c4:	0f 85 4f 01 00 00    	jne    1086619 <interpreter.Interpreter.evaluate+0x1069>
natives.call():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/natives.zig:29
 10864ca:	48 8b 73 10          	mov    0x10(%rbx),%rsi
 10864ce:	48 8b 43 18          	mov    0x18(%rbx),%rax
 10864d2:	48 8d 7d b0          	lea    -0x50(%rbp),%rdi
Io.Clock.now():
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/Io.zig:797
 10864d6:	ba 01 00 00 00       	mov    $0x1,%edx
 10864db:	ff 90 c0 02 00 00    	call   *0x2c0(%rax)
 10864e1:	48 63 75 b8          	movslq -0x48(%rbp),%rsi
 10864e5:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
natives.clock():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/natives.zig:37
 10864e9:	e8 e2 cb 01 00       	call   10a30d0 <__floattidf>
 10864ee:	c5 fb 5e 05 0a 4f f9 	vdivsd -0x6b0f6(%rip),%xmm0,%xmm0        # 101b400 <__anon_30753+0x180>
 10864f5:	ff 
interpreter.Interpreter.callValue():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:388
 10864f6:	4c 89 a3 90 00 00 00 	mov    %r12,0x90(%rbx)
heap.Runtime.push():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:115
 10864fd:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 1086504:	c4 a1 7b 11 04 38    	vmovsd %xmm0,(%rax,%r15,1)
 108650a:	42 c6 44 38 08 02    	movb   $0x2,0x8(%rax,%r15,1)
interpreter.Interpreter.evaluate():
 1086510:	e9 e9 00 00 00       	jmp    10865fe <interpreter.Interpreter.evaluate+0x104e>
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:316 (discriminator 4)
 1086515:	41 8b 77 10          	mov    0x10(%r15),%esi
 1086519:	4c 89 f7             	mov    %r14,%rdi
 108651c:	e8 6f 1d 00 00       	call   1088290 <interpreter.Interpreter.runtimeError__anon_31571>
interpreter.Interpreter.callValue():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:385
 1086521:	e9 e1 00 00 00       	jmp    1086607 <interpreter.Interpreter.evaluate+0x1057>
interpreter.Interpreter.evaluateGet():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:352 (discriminator 2)
 1086526:	41 8b 77 1c          	mov    0x1c(%r15),%esi
 108652a:	49 8b 57 08          	mov    0x8(%r15),%rdx
 108652e:	49 8b 4f 10          	mov    0x10(%r15),%rcx
 1086532:	4c 89 f7             	mov    %r14,%rdi
 1086535:	e8 b6 08 00 00       	call   1086df0 <interpreter.Interpreter.runtimeError__anon_30904>
interpreter.Interpreter.callValue():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:385
 108653a:	e9 c8 00 00 00       	jmp    1086607 <interpreter.Interpreter.evaluate+0x1057>
value.valuesEqual():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:51
 108653f:	40 80 fe 02          	cmp    $0x2,%sil
 1086543:	40 0f 94 c6          	sete   %sil
 1086547:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 108654b:	40 0f 9b c7          	setnp  %dil
 108654f:	0f 94 c2             	sete   %dl
 1086552:	40 20 fa             	and    %dil,%dl
 1086555:	40 20 f2             	and    %sil,%dl
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:308
 1086558:	80 f2 01             	xor    $0x1,%dl
 108655b:	eb 7f                	jmp    10865dc <interpreter.Interpreter.evaluate+0x102c>
value.valuesEqual():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:55 (discriminator 2)
 108655d:	40 80 fe 03          	cmp    $0x3,%sil
 1086561:	75 44                	jne    10865a7 <interpreter.Interpreter.evaluate+0xff7>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:51 (discriminator 2)
 1086563:	c4 e1 f9 7e ca       	vmovq  %xmm1,%rdx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:55 (discriminator 8)
 1086568:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 108656d:	39 f2                	cmp    %esi,%edx
 108656f:	eb 2e                	jmp    108659f <interpreter.Interpreter.evaluate+0xfef>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:51
 1086571:	40 80 fe 02          	cmp    $0x2,%sil
 1086575:	40 0f 94 c6          	sete   %sil
 1086579:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 108657d:	40 0f 9b c7          	setnp  %dil
 1086581:	0f 94 c2             	sete   %dl
 1086584:	40 20 fa             	and    %dil,%dl
 1086587:	40 20 f2             	and    %sil,%dl
 108658a:	eb 50                	jmp    10865dc <interpreter.Interpreter.evaluate+0x102c>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:47
 108658c:	40 80 fe 01          	cmp    $0x1,%sil
 1086590:	75 15                	jne    10865a7 <interpreter.Interpreter.evaluate+0xff7>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:45 (discriminator 6)
 1086592:	c4 e1 f9 7e ca       	vmovq  %xmm1,%rdx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:47 (discriminator 6)
 1086597:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 108659c:	40 38 f2             	cmp    %sil,%dl
 108659f:	0f 94 c2             	sete   %dl
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:308
 10865a2:	80 f2 01             	xor    $0x1,%dl
 10865a5:	eb 35                	jmp    10865dc <interpreter.Interpreter.evaluate+0x102c>
 10865a7:	31 d2                	xor    %edx,%edx
 10865a9:	80 f2 01             	xor    $0x1,%dl
 10865ac:	eb 2e                	jmp    10865dc <interpreter.Interpreter.evaluate+0x102c>
value.valuesEqual():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:55 (discriminator 2)
 10865ae:	40 80 fe 03          	cmp    $0x3,%sil
 10865b2:	75 26                	jne    10865da <interpreter.Interpreter.evaluate+0x102a>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:51 (discriminator 2)
 10865b4:	c4 e1 f9 7e ca       	vmovq  %xmm1,%rdx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:55 (discriminator 8)
 10865b9:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 10865be:	39 f2                	cmp    %esi,%edx
 10865c0:	eb 13                	jmp    10865d5 <interpreter.Interpreter.evaluate+0x1025>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:47
 10865c2:	40 80 fe 01          	cmp    $0x1,%sil
 10865c6:	75 12                	jne    10865da <interpreter.Interpreter.evaluate+0x102a>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:45 (discriminator 6)
 10865c8:	c4 e1 f9 7e ca       	vmovq  %xmm1,%rdx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:47 (discriminator 6)
 10865cd:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 10865d2:	40 38 f2             	cmp    %sil,%dl
 10865d5:	0f 94 c2             	sete   %dl
 10865d8:	eb 02                	jmp    10865dc <interpreter.Interpreter.evaluate+0x102c>
interpreter.Interpreter.evaluateBinary():
 10865da:	31 d2                	xor    %edx,%edx
 10865dc:	0f b6 d2             	movzbl %dl,%edx
 10865df:	c4 e1 f9 6e c2       	vmovq  %rdx,%xmm0
 10865e4:	b2 01                	mov    $0x1,%dl
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:335
 10865e6:	48 83 c1 fe          	add    $0xfffffffffffffffe,%rcx
 10865ea:	48 89 8b 90 00 00 00 	mov    %rcx,0x90(%rbx)
heap.Runtime.push():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:115
 10865f1:	48 c1 e1 04          	shl    $0x4,%rcx
 10865f5:	c5 f9 d6 04 08       	vmovq  %xmm0,(%rax,%rcx,1)
 10865fa:	88 54 08 08          	mov    %dl,0x8(%rax,%rcx,1)
interpreter.Interpreter.evaluate():
 10865fe:	48 ff 83 90 00 00 00 	incq   0x90(%rbx)
 1086605:	31 c0                	xor    %eax,%eax
 1086607:	48 81 c4 e8 00 00 00 	add    $0xe8,%rsp
 108660e:	5b                   	pop    %rbx
 108660f:	41 5c                	pop    %r12
 1086611:	41 5d                	pop    %r13
 1086613:	41 5e                	pop    %r14
 1086615:	41 5f                	pop    %r15
 1086617:	5d                   	pop    %rbp
 1086618:	c3                   	ret
interpreter.Interpreter.callValue():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:385
 1086619:	4c 89 f7             	mov    %r14,%rdi
 108661c:	44 89 ce             	mov    %r9d,%esi
 108661f:	e8 ec 09 00 00       	call   1087010 <interpreter.Interpreter.runtimeError__anon_31252>
 1086624:	eb e1                	jmp    1086607 <interpreter.Interpreter.evaluate+0x1057>
interpreter.Interpreter.evaluateBinary():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:323 (discriminator 2)
 1086626:	31 d2                	xor    %edx,%edx
 1086628:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:323
 108662c:	0f 97 c2             	seta   %dl
 108662f:	eb ae                	jmp    10865df <interpreter.Interpreter.evaluate+0x102f>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:330
 1086631:	c5 f3 59 c0          	vmulsd %xmm0,%xmm1,%xmm0
 1086635:	b2 02                	mov    $0x2,%dl
 1086637:	eb ad                	jmp    10865e6 <interpreter.Interpreter.evaluate+0x1036>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:329
 1086639:	c5 f3 5e c0          	vdivsd %xmm0,%xmm1,%xmm0
 108663d:	b2 02                	mov    $0x2,%dl
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:330
 108663f:	eb a5                	jmp    10865e6 <interpreter.Interpreter.evaluate+0x1036>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:323 (discriminator 6)
 1086641:	31 d2                	xor    %edx,%edx
 1086643:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:323
 1086647:	0f 97 c2             	seta   %dl
 108664a:	eb 93                	jmp    10865df <interpreter.Interpreter.evaluate+0x102f>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:323 (discriminator 8)
 108664c:	31 d2                	xor    %edx,%edx
 108664e:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:323
 1086652:	0f 93 c2             	setae  %dl
 1086655:	eb 88                	jmp    10865df <interpreter.Interpreter.evaluate+0x102f>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:323 (discriminator 4)
 1086657:	31 d2                	xor    %edx,%edx
 1086659:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/interpreter.zig:323
 108665d:	0f 93 c2             	setae  %dl
 1086660:	e9 7a ff ff ff       	jmp    10865df <interpreter.Interpreter.evaluate+0x102f>
