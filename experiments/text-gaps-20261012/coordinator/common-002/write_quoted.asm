
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/text-runtime:     file format elf64-x86-64


Disassembly of section .text:

0000000001050320 <my.json::write_quoted>:
 1050320:	55                   	push   %rbp
 1050321:	41 57                	push   %r15
 1050323:	41 56                	push   %r14
 1050325:	41 55                	push   %r13
 1050327:	41 54                	push   %r12
 1050329:	53                   	push   %rbx
 105032a:	50                   	push   %rax
 105032b:	48 89 f3             	mov    %rsi,%rbx
 105032e:	4c 8b 76 08          	mov    0x8(%rsi),%r14
 1050332:	48 83 c3 20          	add    $0x20,%rbx
 1050336:	be 22 00 00 00       	mov    $0x22,%esi
 105033b:	e8 c0 c9 fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 1050340:	4d 89 f0             	mov    %r14,%r8
 1050343:	49 89 c5             	mov    %rax,%r13
 1050346:	4d 85 f6             	test   %r14,%r14
 1050349:	0f 84 ac 02 00 00    	je     10505fb <my.json::write_quoted+0x2db>
 105034f:	45 31 ff             	xor    %r15d,%r15d
 1050352:	45 31 e4             	xor    %r12d,%r12d
 1050355:	4c 89 04 24          	mov    %r8,(%rsp)
 1050359:	eb 54                	jmp    10503af <my.json::write_quoted+0x8f>
 105035b:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050362:	0f 1f 84 00 00 00 00 
 1050369:	00 
 105036a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050371:	0f 1f 84 00 00 00 00 
 1050378:	00 
 1050379:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1050380:	be 5c 00 00 00       	mov    $0x5c,%esi
 1050385:	4c 89 ef             	mov    %r13,%rdi
 1050388:	e8 73 c9 fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 105038d:	48 89 c7             	mov    %rax,%rdi
 1050390:	48 89 ee             	mov    %rbp,%rsi
 1050393:	e8 68 c9 fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 1050398:	49 89 c5             	mov    %rax,%r13
 105039b:	4d 8d 67 01          	lea    0x1(%r15),%r12
 105039f:	4c 8b 04 24          	mov    (%rsp),%r8
 10503a3:	49 ff c7             	inc    %r15
 10503a6:	4d 39 f8             	cmp    %r15,%r8
 10503a9:	0f 84 4f 02 00 00    	je     10505fe <my.json::write_quoted+0x2de>
 10503af:	42 0f b6 2c 3b       	movzbl (%rbx,%r15,1),%ebp
 10503b4:	48 83 fd 22          	cmp    $0x22,%rbp
 10503b8:	74 12                	je     10503cc <my.json::write_quoted+0xac>
 10503ba:	48 83 fd 5c          	cmp    $0x5c,%rbp
 10503be:	0f 94 c0             	sete   %al
 10503c1:	40 80 fd 20          	cmp    $0x20,%bpl
 10503c5:	0f 92 c1             	setb   %cl
 10503c8:	08 c1                	or     %al,%cl
 10503ca:	74 d7                	je     10503a3 <my.json::write_quoted+0x83>
 10503cc:	4d 39 c7             	cmp    %r8,%r15
 10503cf:	0f 8f 7c 01 00 00    	jg     1050551 <my.json::write_quoted+0x231>
 10503d5:	4d 85 e4             	test   %r12,%r12
 10503d8:	0f 88 73 01 00 00    	js     1050551 <my.json::write_quoted+0x231>
 10503de:	4c 89 fa             	mov    %r15,%rdx
 10503e1:	4c 29 e2             	sub    %r12,%rdx
 10503e4:	48 85 d2             	test   %rdx,%rdx
 10503e7:	0f 8e 64 01 00 00    	jle    1050551 <my.json::write_quoted+0x231>
 10503ed:	4d 8b 75 08          	mov    0x8(%r13),%r14
 10503f1:	49 8b 45 10          	mov    0x10(%r13),%rax
 10503f5:	4c 29 f0             	sub    %r14,%rax
 10503f8:	48 39 c2             	cmp    %rax,%rdx
 10503fb:	0f 8f 50 01 00 00    	jg     1050551 <my.json::write_quoted+0x231>
 1050401:	4b 8d 3c 2e          	lea    (%r14,%r13,1),%rdi
 1050405:	48 83 c7 20          	add    $0x20,%rdi
 1050409:	4a 8d 34 23          	lea    (%rbx,%r12,1),%rsi
 105040d:	e8 ae ca 00 00       	call   105cec0 <memmove@plt>
 1050412:	4d 01 fe             	add    %r15,%r14
 1050415:	4d 29 e6             	sub    %r12,%r14
 1050418:	4d 89 75 08          	mov    %r14,0x8(%r13)
 105041c:	40 80 fd 20          	cmp    $0x20,%bpl
 1050420:	0f 83 5a ff ff ff    	jae    1050380 <my.json::write_quoted+0x60>
 1050426:	49 8b 45 08          	mov    0x8(%r13),%rax
 105042a:	49 8b 4d 10          	mov    0x10(%r13),%rcx
 105042e:	48 29 c1             	sub    %rax,%rcx
 1050431:	8d 55 f8             	lea    -0x8(%rbp),%edx
 1050434:	83 fa 05             	cmp    $0x5,%edx
 1050437:	77 2b                	ja     1050464 <my.json::write_quoted+0x144>
 1050439:	48 8d 35 b8 6f fb ff 	lea    -0x49048(%rip),%rsi        # 10073f8 <core_number_pairs+0x158>
 1050440:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 1050444:	48 01 f2             	add    %rsi,%rdx
 1050447:	ff e2                	jmp    *%rdx
 1050449:	48 83 f9 02          	cmp    $0x2,%rcx
 105044d:	4c 8b 04 24          	mov    (%rsp),%r8
 1050451:	0f 8c 4f 01 00 00    	jl     10505a6 <my.json::write_quoted+0x286>
 1050457:	66 41 c7 44 05 20 5c 	movw   $0x625c,0x20(%r13,%rax,1)
 105045e:	62 
 105045f:	e9 dc 00 00 00       	jmp    1050540 <my.json::write_quoted+0x220>
 1050464:	48 83 f9 04          	cmp    $0x4,%rcx
 1050468:	0f 8c 09 01 00 00    	jl     1050577 <my.json::write_quoted+0x257>
 105046e:	41 c7 44 05 20 5c 75 	movl   $0x3030755c,0x20(%r13,%rax,1)
 1050475:	30 30 
 1050477:	48 83 c0 04          	add    $0x4,%rax
 105047b:	49 89 45 08          	mov    %rax,0x8(%r13)
 105047f:	89 e8                	mov    %ebp,%eax
 1050481:	c1 e8 04             	shr    $0x4,%eax
 1050484:	4c 8d 35 d5 9b fb ff 	lea    -0x4642b(%rip),%r14        # 100a060 <core_number_pairs+0x2dc0>
 105048b:	42 0f b6 74 30 20    	movzbl 0x20(%rax,%r14,1),%esi
 1050491:	4c 89 ef             	mov    %r13,%rdi
 1050494:	e8 67 c8 fe ff       	call   103cd00 <myl_core_buffer_push_checked>
 1050499:	83 e5 0f             	and    $0xf,%ebp
 105049c:	42 0f b6 74 35 20    	movzbl 0x20(%rbp,%r14,1),%esi
 10504a2:	48 89 c7             	mov    %rax,%rdi
 10504a5:	e9 e9 fe ff ff       	jmp    1050393 <my.json::write_quoted+0x73>
 10504aa:	48 83 f9 02          	cmp    $0x2,%rcx
 10504ae:	4c 8b 04 24          	mov    (%rsp),%r8
 10504b2:	0f 8c dd 00 00 00    	jl     1050595 <my.json::write_quoted+0x275>
 10504b8:	66 41 c7 44 05 20 5c 	movw   $0x6e5c,0x20(%r13,%rax,1)
 10504bf:	6e 
 10504c0:	eb 7e                	jmp    1050540 <my.json::write_quoted+0x220>
 10504c2:	48 83 f9 02          	cmp    $0x2,%rcx
 10504c6:	4c 8b 04 24          	mov    (%rsp),%r8
 10504ca:	0f 8c e7 00 00 00    	jl     10505b7 <my.json::write_quoted+0x297>
 10504d0:	66 41 c7 44 05 20 5c 	movw   $0x745c,0x20(%r13,%rax,1)
 10504d7:	74 
 10504d8:	eb 66                	jmp    1050540 <my.json::write_quoted+0x220>
 10504da:	48 83 f9 02          	cmp    $0x2,%rcx
 10504de:	4c 8b 04 24          	mov    (%rsp),%r8
 10504e2:	0f 8c e0 00 00 00    	jl     10505c8 <my.json::write_quoted+0x2a8>
 10504e8:	66 41 c7 44 05 20 5c 	movw   $0x665c,0x20(%r13,%rax,1)
 10504ef:	66 
 10504f0:	eb 4e                	jmp    1050540 <my.json::write_quoted+0x220>
 10504f2:	48 83 f9 02          	cmp    $0x2,%rcx
 10504f6:	4c 8b 04 24          	mov    (%rsp),%r8
 10504fa:	0f 8c d9 00 00 00    	jl     10505d9 <my.json::write_quoted+0x2b9>
 1050500:	66 41 c7 44 05 20 5c 	movw   $0x725c,0x20(%r13,%rax,1)
 1050507:	72 
 1050508:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105050f:	0f 1f 84 00 00 00 00 
 1050516:	00 
 1050517:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105051e:	0f 1f 84 00 00 00 00 
 1050525:	00 
 1050526:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105052d:	0f 1f 84 00 00 00 00 
 1050534:	00 
 1050535:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 105053c:	00 00 00 00 
 1050540:	48 83 c0 02          	add    $0x2,%rax
 1050544:	49 89 45 08          	mov    %rax,0x8(%r13)
 1050548:	4d 8d 67 01          	lea    0x1(%r15),%r12
 105054c:	e9 52 fe ff ff       	jmp    10503a3 <my.json::write_quoted+0x83>
 1050551:	4c 89 ef             	mov    %r13,%rdi
 1050554:	48 89 de             	mov    %rbx,%rsi
 1050557:	4c 89 c2             	mov    %r8,%rdx
 105055a:	4c 89 e1             	mov    %r12,%rcx
 105055d:	4d 89 f8             	mov    %r15,%r8
 1050560:	e8 1b c7 fe ff       	call   103cc80 <myl_core_buffer_append_span_checked>
 1050565:	49 89 c5             	mov    %rax,%r13
 1050568:	40 80 fd 20          	cmp    $0x20,%bpl
 105056c:	0f 82 b4 fe ff ff    	jb     1050426 <my.json::write_quoted+0x106>
 1050572:	e9 09 fe ff ff       	jmp    1050380 <my.json::write_quoted+0x60>
 1050577:	b9 04 00 00 00       	mov    $0x4,%ecx
 105057c:	4c 89 ef             	mov    %r13,%rdi
 105057f:	48 8d 35 9a 9a fb ff 	lea    -0x46566(%rip),%rsi        # 100a020 <core_number_pairs+0x2d80>
 1050586:	31 d2                	xor    %edx,%edx
 1050588:	e8 f3 c5 fe ff       	call   103cb80 <myl_core_buffer_append_checked>
 105058d:	49 89 c5             	mov    %rax,%r13
 1050590:	e9 ea fe ff ff       	jmp    105047f <my.json::write_quoted+0x15f>
 1050595:	b9 02 00 00 00       	mov    $0x2,%ecx
 105059a:	4c 89 ef             	mov    %r13,%rdi
 105059d:	48 8d 35 bc 99 fb ff 	lea    -0x46644(%rip),%rsi        # 1009f60 <core_number_pairs+0x2cc0>
 10505a4:	eb 42                	jmp    10505e8 <my.json::write_quoted+0x2c8>
 10505a6:	b9 02 00 00 00       	mov    $0x2,%ecx
 10505ab:	4c 89 ef             	mov    %r13,%rdi
 10505ae:	48 8d 35 2b 99 fb ff 	lea    -0x466d5(%rip),%rsi        # 1009ee0 <core_number_pairs+0x2c40>
 10505b5:	eb 31                	jmp    10505e8 <my.json::write_quoted+0x2c8>
 10505b7:	b9 02 00 00 00       	mov    $0x2,%ecx
 10505bc:	4c 89 ef             	mov    %r13,%rdi
 10505bf:	48 8d 35 5a 99 fb ff 	lea    -0x466a6(%rip),%rsi        # 1009f20 <core_number_pairs+0x2c80>
 10505c6:	eb 20                	jmp    10505e8 <my.json::write_quoted+0x2c8>
 10505c8:	b9 02 00 00 00       	mov    $0x2,%ecx
 10505cd:	4c 89 ef             	mov    %r13,%rdi
 10505d0:	48 8d 35 c9 99 fb ff 	lea    -0x46637(%rip),%rsi        # 1009fa0 <core_number_pairs+0x2d00>
 10505d7:	eb 0f                	jmp    10505e8 <my.json::write_quoted+0x2c8>
 10505d9:	b9 02 00 00 00       	mov    $0x2,%ecx
 10505de:	4c 89 ef             	mov    %r13,%rdi
 10505e1:	48 8d 35 f8 99 fb ff 	lea    -0x46608(%rip),%rsi        # 1009fe0 <core_number_pairs+0x2d40>
 10505e8:	31 d2                	xor    %edx,%edx
 10505ea:	e8 91 c5 fe ff       	call   103cb80 <myl_core_buffer_append_checked>
 10505ef:	4c 8b 04 24          	mov    (%rsp),%r8
 10505f3:	49 89 c5             	mov    %rax,%r13
 10505f6:	e9 4d ff ff ff       	jmp    1050548 <my.json::write_quoted+0x228>
 10505fb:	45 31 e4             	xor    %r12d,%r12d
 10505fe:	4d 85 e4             	test   %r12,%r12
 1050601:	78 53                	js     1050656 <my.json::write_quoted+0x336>
 1050603:	4d 89 c7             	mov    %r8,%r15
 1050606:	4d 29 e7             	sub    %r12,%r15
 1050609:	4d 85 ff             	test   %r15,%r15
 105060c:	7e 48                	jle    1050656 <my.json::write_quoted+0x336>
 105060e:	4d 8b 75 08          	mov    0x8(%r13),%r14
 1050612:	49 8b 45 10          	mov    0x10(%r13),%rax
 1050616:	4c 29 f0             	sub    %r14,%rax
 1050619:	49 39 c7             	cmp    %rax,%r15
 105061c:	7f 38                	jg     1050656 <my.json::write_quoted+0x336>
 105061e:	4b 8d 3c 2e          	lea    (%r14,%r13,1),%rdi
 1050622:	48 83 c7 20          	add    $0x20,%rdi
 1050626:	4c 01 e3             	add    %r12,%rbx
 1050629:	48 89 de             	mov    %rbx,%rsi
 105062c:	4c 89 fa             	mov    %r15,%rdx
 105062f:	e8 8c c8 00 00       	call   105cec0 <memmove@plt>
 1050634:	4d 01 fe             	add    %r15,%r14
 1050637:	4d 89 75 08          	mov    %r14,0x8(%r13)
 105063b:	be 22 00 00 00       	mov    $0x22,%esi
 1050640:	4c 89 ef             	mov    %r13,%rdi
 1050643:	48 83 c4 08          	add    $0x8,%rsp
 1050647:	5b                   	pop    %rbx
 1050648:	41 5c                	pop    %r12
 105064a:	41 5d                	pop    %r13
 105064c:	41 5e                	pop    %r14
 105064e:	41 5f                	pop    %r15
 1050650:	5d                   	pop    %rbp
 1050651:	e9 aa c6 fe ff       	jmp    103cd00 <myl_core_buffer_push_checked>
 1050656:	4c 89 ef             	mov    %r13,%rdi
 1050659:	48 89 de             	mov    %rbx,%rsi
 105065c:	4c 89 c2             	mov    %r8,%rdx
 105065f:	4c 89 e1             	mov    %r12,%rcx
 1050662:	e8 19 c6 fe ff       	call   103cc80 <myl_core_buffer_append_span_checked>
 1050667:	49 89 c5             	mov    %rax,%r13
 105066a:	eb cf                	jmp    105063b <my.json::write_quoted+0x31b>

Disassembly of section .plt:
