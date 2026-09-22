
.tmp/bench/armsset/maxperf/whole-o3.bin:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .text:

000000000040b140 <sexpr.printer::push_node>:
  40b140:	55                   	push   %rbp
  40b141:	41 57                	push   %r15
  40b143:	41 56                	push   %r14
  40b145:	41 55                	push   %r13
  40b147:	41 54                	push   %r12
  40b149:	53                   	push   %rbx
  40b14a:	48 81 ec e8 04 00 00 	sub    $0x4e8,%rsp
  40b151:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
  40b155:	c5 f8 29 84 24 20 03 	vmovaps %xmm0,0x320(%rsp)
  40b15c:	00 00 
  40b15e:	48 c7 84 24 30 03 00 	movq   $0x0,0x330(%rsp)
  40b165:	00 00 00 00 00 
  40b16a:	48 89 cd             	mov    %rcx,%rbp
  40b16d:	49 89 d6             	mov    %rdx,%r14
  40b170:	49 89 f5             	mov    %rsi,%r13
  40b173:	49 89 ff             	mov    %rdi,%r15
  40b176:	c5 f8 29 84 24 00 03 	vmovaps %xmm0,0x300(%rsp)
  40b17d:	00 00 
  40b17f:	48 c7 84 24 10 03 00 	movq   $0x0,0x310(%rsp)
  40b186:	00 00 00 00 00 
  40b18b:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
  40b18f:	c5 fc 11 8c 24 60 03 	vmovups %ymm1,0x360(%rsp)
  40b196:	00 00 
  40b198:	c5 f8 29 84 24 40 03 	vmovaps %xmm0,0x340(%rsp)
  40b19f:	00 00 
  40b1a1:	48 c7 84 24 50 03 00 	movq   $0x0,0x350(%rsp)
  40b1a8:	00 00 00 00 00 
  40b1ad:	c5 f8 77             	vzeroupper
  40b1b0:	e8 bb 03 01 00       	call   41b570 <myl_qbe_heap>
  40b1b5:	49 89 c0             	mov    %rax,%r8
  40b1b8:	41 8b 06             	mov    (%r14),%eax
  40b1bb:	48 83 f8 05          	cmp    $0x5,%rax
  40b1bf:	0f 87 18 4b 00 00    	ja     40fcdd <sexpr.printer::push_node+0x4b9d>
  40b1c5:	4d 8d 5e 08          	lea    0x8(%r14),%r11
  40b1c9:	48 8d 0d 00 a0 01 00 	lea    0x1a000(%rip),%rcx        # 4251d0 <_fini+0x88c>
  40b1d0:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
  40b1d4:	48 01 c8             	add    %rcx,%rax
  40b1d7:	ff e0                	jmp    *%rax
  40b1d9:	4d 8b 13             	mov    (%r11),%r10
  40b1dc:	49 83 3a 00          	cmpq   $0x0,(%r10)
  40b1e0:	49 8b 40 10          	mov    0x10(%r8),%rax
  40b1e4:	48 8d 7c 24 18       	lea    0x18(%rsp),%rdi
  40b1e9:	48 8d 8c 24 f8 00 00 	lea    0xf8(%rsp),%rcx
  40b1f0:	00 
  40b1f1:	48 8d b4 24 d8 00 00 	lea    0xd8(%rsp),%rsi
  40b1f8:	00 
  40b1f9:	48 8d 94 24 b8 00 00 	lea    0xb8(%rsp),%rdx
  40b200:	00 
  40b201:	0f 84 4f 30 00 00    	je     40e256 <sexpr.printer::push_node+0x3116>
  40b207:	48 89 ac 24 f8 02 00 	mov    %rbp,0x2f8(%rsp)
  40b20e:	00 
  40b20f:	48 89 04 24          	mov    %rax,(%rsp)
  40b213:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40b218:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
  40b21d:	48 c7 c7 60 84 42 00 	mov    $0x428460,%rdi
  40b224:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
  40b229:	48 89 e0             	mov    %rsp,%rax
  40b22c:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40b233:	00 
  40b234:	4c 89 b4 24 28 01 00 	mov    %r14,0x128(%rsp)
  40b23b:	00 
  40b23c:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40b243:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40b24a:	00 
  40b24b:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40b252:	00 
  40b253:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40b25a:	00 
  40b25b:	4c 89 9c 24 28 02 00 	mov    %r11,0x228(%rsp)
  40b262:	00 
  40b263:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40b26a:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40b271:	00 
  40b272:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40b279:	00 
  40b27a:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40b281:	00 
  40b282:	4c 89 94 24 f8 00 00 	mov    %r10,0xf8(%rsp)
  40b289:	00 
  40b28a:	48 89 8c 24 e8 00 00 	mov    %rcx,0xe8(%rsp)
  40b291:	00 
  40b292:	4c 89 bc 24 e0 02 00 	mov    %r15,0x2e0(%rsp)
  40b299:	00 
  40b29a:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40b2a1:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40b2a8:	00 
  40b2a9:	48 8d 9c 24 e0 00 00 	lea    0xe0(%rsp),%rbx
  40b2b0:	00 
  40b2b1:	48 89 9c 24 c0 00 00 	mov    %rbx,0xc0(%rsp)
  40b2b8:	00 
  40b2b9:	4c 89 94 24 d8 00 00 	mov    %r10,0xd8(%rsp)
  40b2c0:	00 
  40b2c1:	48 89 b4 24 c8 00 00 	mov    %rsi,0xc8(%rsp)
  40b2c8:	00 
  40b2c9:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40b2d0:	00 
  40b2d1:	48 8d 9c 24 c0 00 00 	lea    0xc0(%rsp),%rbx
  40b2d8:	00 
  40b2d9:	48 89 9c 24 a0 00 00 	mov    %rbx,0xa0(%rsp)
  40b2e0:	00 
  40b2e1:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40b2e8:	00 00 00 00 00 
  40b2ed:	48 89 94 24 a8 00 00 	mov    %rdx,0xa8(%rsp)
  40b2f4:	00 
  40b2f5:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40b2fc:	00 
  40b2fd:	48 8d 9c 24 a0 00 00 	lea    0xa0(%rsp),%rbx
  40b304:	00 
  40b305:	48 89 9c 24 80 00 00 	mov    %rbx,0x80(%rsp)
  40b30c:	00 
  40b30d:	48 8d 9c 24 98 00 00 	lea    0x98(%rsp),%rbx
  40b314:	00 
  40b315:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40b31c:	00 00 00 00 00 
  40b321:	48 89 9c 24 88 00 00 	mov    %rbx,0x88(%rsp)
  40b328:	00 
  40b329:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40b330:	00 
  40b331:	48 8d 9c 24 80 00 00 	lea    0x80(%rsp),%rbx
  40b338:	00 
  40b339:	48 89 5c 24 60       	mov    %rbx,0x60(%rsp)
  40b33e:	48 8d 5c 24 78       	lea    0x78(%rsp),%rbx
  40b343:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40b34a:	00 00 
  40b34c:	48 89 5c 24 68       	mov    %rbx,0x68(%rsp)
  40b351:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40b356:	48 8d 5c 24 60       	lea    0x60(%rsp),%rbx
  40b35b:	48 89 5c 24 40       	mov    %rbx,0x40(%rsp)
  40b360:	48 8d 5c 24 58       	lea    0x58(%rsp),%rbx
  40b365:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40b36c:	00 00 
  40b36e:	48 89 5c 24 48       	mov    %rbx,0x48(%rsp)
  40b373:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40b378:	48 8d 5c 24 40       	lea    0x40(%rsp),%rbx
  40b37d:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
  40b382:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40b389:	00 00 
  40b38b:	48 8d 5c 24 38       	lea    0x38(%rsp),%rbx
  40b390:	48 89 5c 24 28       	mov    %rbx,0x28(%rsp)
  40b395:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40b39a:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40b39f:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40b3a6:	00 
  40b3a7:	4c 89 9c 24 08 02 00 	mov    %r11,0x208(%rsp)
  40b3ae:	00 
  40b3af:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40b3b6:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40b3bd:	00 
  40b3be:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40b3c5:	00 
  40b3c6:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40b3cd:	00 
  40b3ce:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40b3d5:	00 
  40b3d6:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40b3dd:	00 
  40b3de:	48 c7 c3 70 24 43 00 	mov    $0x432470,%rbx
  40b3e5:	48 89 9c 24 f0 01 00 	mov    %rbx,0x1f0(%rsp)
  40b3ec:	00 
  40b3ed:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40b3f4:	00 
  40b3f5:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40b3fc:	00 
  40b3fd:	4c 89 9c 24 c8 01 00 	mov    %r11,0x1c8(%rsp)
  40b404:	00 
  40b405:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40b40c:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40b413:	00 
  40b414:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40b41b:	00 
  40b41c:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40b423:	00 
  40b424:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40b42b:	00 
  40b42c:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40b433:	00 
  40b434:	48 89 9c 24 b0 01 00 	mov    %rbx,0x1b0(%rsp)
  40b43b:	00 
  40b43c:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40b443:	00 
  40b444:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40b44b:	00 
  40b44c:	4c 89 9c 24 88 01 00 	mov    %r11,0x188(%rsp)
  40b453:	00 
  40b454:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40b45b:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40b462:	00 
  40b463:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40b46a:	00 
  40b46b:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40b472:	00 
  40b473:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40b47a:	00 
  40b47b:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40b482:	00 
  40b483:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40b48a:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40b491:	00 
  40b492:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40b499:	00 
  40b49a:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40b4a1:	00 
  40b4a2:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40b4a9:	00 
  40b4aa:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40b4b1:	00 
  40b4b2:	48 89 9c 24 50 01 00 	mov    %rbx,0x150(%rsp)
  40b4b9:	00 
  40b4ba:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40b4c1:	00 
  40b4c2:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40b4c9:	00 
  40b4ca:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40b4d1:	00 
  40b4d2:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40b4d9:	00 
  40b4da:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40b4e1:	00 
  40b4e2:	49 89 ff             	mov    %rdi,%r15
  40b4e5:	48 89 bc 24 10 01 00 	mov    %rdi,0x110(%rsp)
  40b4ec:	00 
  40b4ed:	48 c7 c0 b0 27 43 00 	mov    $0x4327b0,%rax
  40b4f4:	4c 89 b4 24 f0 02 00 	mov    %r14,0x2f0(%rsp)
  40b4fb:	00 
  40b4fc:	4c 8b 30             	mov    (%rax),%r14
  40b4ff:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40b506:	00 
  40b507:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40b50e:	00 
  40b50f:	4c 89 b4 24 b8 02 00 	mov    %r14,0x2b8(%rsp)
  40b516:	00 
  40b517:	48 8d 84 24 b8 02 00 	lea    0x2b8(%rsp),%rax
  40b51e:	00 
  40b51f:	48 89 84 24 a8 02 00 	mov    %rax,0x2a8(%rsp)
  40b526:	00 
  40b527:	48 c7 c5 d0 1e 43 00 	mov    $0x431ed0,%rbp
  40b52e:	48 89 ac 24 b0 02 00 	mov    %rbp,0x2b0(%rsp)
  40b535:	00 
  40b536:	48 8b bc 24 e0 02 00 	mov    0x2e0(%rsp),%rdi
  40b53d:	00 
  40b53e:	4c 89 94 24 10 04 00 	mov    %r10,0x410(%rsp)
  40b545:	00 
  40b546:	4c 89 c3             	mov    %r8,%rbx
  40b549:	e8 22 00 01 00       	call   41b570 <myl_qbe_heap>
  40b54e:	49 8b 75 00          	mov    0x0(%r13),%rsi
  40b552:	4d 8b 06             	mov    (%r14),%r8
  40b555:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40b559:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40b560:	00 
  40b561:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40b568:	00 
  40b569:	4c 89 ac 24 58 02 00 	mov    %r13,0x258(%rsp)
  40b570:	00 
  40b571:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40b578:	00 
  40b579:	4c 89 bc 24 50 02 00 	mov    %r15,0x250(%rsp)
  40b580:	00 
  40b581:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40b588:	00 
  40b589:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40b590:	00 
  40b591:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40b598:	00 
  40b599:	4c 89 b4 24 78 02 00 	mov    %r14,0x278(%rsp)
  40b5a0:	00 
  40b5a1:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40b5a8:	00 
  40b5a9:	48 89 ac 24 70 02 00 	mov    %rbp,0x270(%rsp)
  40b5b0:	00 
  40b5b1:	48 8d 8c 24 60 02 00 	lea    0x260(%rsp),%rcx
  40b5b8:	00 
  40b5b9:	48 89 8c 24 80 02 00 	mov    %rcx,0x280(%rsp)
  40b5c0:	00 
  40b5c1:	48 8d 8c 24 98 02 00 	lea    0x298(%rsp),%rcx
  40b5c8:	00 
  40b5c9:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40b5d0:	00 
  40b5d1:	48 89 8c 24 88 02 00 	mov    %rcx,0x288(%rsp)
  40b5d8:	00 
  40b5d9:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40b5e0:	48 89 8c 24 90 02 00 	mov    %rcx,0x290(%rsp)
  40b5e7:	00 
  40b5e8:	48 8d 8c 24 80 02 00 	lea    0x280(%rsp),%rcx
  40b5ef:	00 
  40b5f0:	48 89 8c 24 c0 02 00 	mov    %rcx,0x2c0(%rsp)
  40b5f7:	00 
  40b5f8:	48 8d 8c 24 d8 02 00 	lea    0x2d8(%rsp),%rcx
  40b5ff:	00 
  40b600:	4c 89 b4 24 d8 02 00 	mov    %r14,0x2d8(%rsp)
  40b607:	00 
  40b608:	48 89 8c 24 c8 02 00 	mov    %rcx,0x2c8(%rsp)
  40b60f:	00 
  40b610:	48 89 ac 24 d0 02 00 	mov    %rbp,0x2d0(%rsp)
  40b617:	00 
  40b618:	48 8d ac 24 e0 00 00 	lea    0xe0(%rsp),%rbp
  40b61f:	00 
  40b620:	48 89 c7             	mov    %rax,%rdi
  40b623:	4c 89 f2             	mov    %r14,%rdx
  40b626:	4c 8b bc 24 f0 02 00 	mov    0x2f0(%rsp),%r15
  40b62d:	00 
  40b62e:	4d 8d 77 08          	lea    0x8(%r15),%r14
  40b632:	31 c9                	xor    %ecx,%ecx
  40b634:	e8 87 55 01 00       	call   420bc0 <myl_native_bytes_buffer_append_range>
  40b639:	48 89 9c 24 e8 02 00 	mov    %rbx,0x2e8(%rsp)
  40b640:	00 
  40b641:	48 8b 43 10          	mov    0x10(%rbx),%rax
  40b645:	48 89 04 24          	mov    %rax,(%rsp)
  40b649:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40b64e:	4c 8b a4 24 10 04 00 	mov    0x410(%rsp),%r12
  40b655:	00 
  40b656:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40b65b:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40b660:	48 c7 c0 60 84 42 00 	mov    $0x428460,%rax
  40b667:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  40b66c:	48 89 e0             	mov    %rsp,%rax
  40b66f:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40b676:	00 
  40b677:	4c 89 bc 24 28 01 00 	mov    %r15,0x128(%rsp)
  40b67e:	00 
  40b67f:	4c 89 fb             	mov    %r15,%rbx
  40b682:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40b689:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40b690:	00 
  40b691:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40b698:	00 
  40b699:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40b6a0:	00 
  40b6a1:	4c 89 b4 24 28 02 00 	mov    %r14,0x228(%rsp)
  40b6a8:	00 
  40b6a9:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40b6b0:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40b6b7:	00 
  40b6b8:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40b6bf:	00 
  40b6c0:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40b6c7:	00 
  40b6c8:	4c 89 a4 24 f8 00 00 	mov    %r12,0xf8(%rsp)
  40b6cf:	00 
  40b6d0:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40b6d7:	00 
  40b6d8:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40b6df:	00 
  40b6e0:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40b6e7:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40b6ee:	00 
  40b6ef:	48 89 ac 24 c0 00 00 	mov    %rbp,0xc0(%rsp)
  40b6f6:	00 
  40b6f7:	4c 89 a4 24 d8 00 00 	mov    %r12,0xd8(%rsp)
  40b6fe:	00 
  40b6ff:	48 8d 94 24 d8 00 00 	lea    0xd8(%rsp),%rdx
  40b706:	00 
  40b707:	48 89 94 24 c8 00 00 	mov    %rdx,0xc8(%rsp)
  40b70e:	00 
  40b70f:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40b716:	00 
  40b717:	48 8d 94 24 c0 00 00 	lea    0xc0(%rsp),%rdx
  40b71e:	00 
  40b71f:	48 89 94 24 a0 00 00 	mov    %rdx,0xa0(%rsp)
  40b726:	00 
  40b727:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40b72e:	00 00 00 00 00 
  40b733:	48 8d 94 24 b8 00 00 	lea    0xb8(%rsp),%rdx
  40b73a:	00 
  40b73b:	48 89 94 24 a8 00 00 	mov    %rdx,0xa8(%rsp)
  40b742:	00 
  40b743:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40b74a:	00 
  40b74b:	48 8d 94 24 a0 00 00 	lea    0xa0(%rsp),%rdx
  40b752:	00 
  40b753:	48 89 94 24 80 00 00 	mov    %rdx,0x80(%rsp)
  40b75a:	00 
  40b75b:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40b762:	00 00 00 00 00 
  40b767:	48 8d 94 24 98 00 00 	lea    0x98(%rsp),%rdx
  40b76e:	00 
  40b76f:	48 89 94 24 88 00 00 	mov    %rdx,0x88(%rsp)
  40b776:	00 
  40b777:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40b77e:	00 
  40b77f:	48 8d 94 24 80 00 00 	lea    0x80(%rsp),%rdx
  40b786:	00 
  40b787:	48 89 54 24 60       	mov    %rdx,0x60(%rsp)
  40b78c:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40b793:	00 00 
  40b795:	48 8d 54 24 78       	lea    0x78(%rsp),%rdx
  40b79a:	48 89 54 24 68       	mov    %rdx,0x68(%rsp)
  40b79f:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40b7a4:	48 8d 54 24 60       	lea    0x60(%rsp),%rdx
  40b7a9:	48 89 54 24 40       	mov    %rdx,0x40(%rsp)
  40b7ae:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40b7b5:	00 00 
  40b7b7:	48 8d 54 24 58       	lea    0x58(%rsp),%rdx
  40b7bc:	48 89 54 24 48       	mov    %rdx,0x48(%rsp)
  40b7c1:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40b7c6:	48 8d 54 24 40       	lea    0x40(%rsp),%rdx
  40b7cb:	48 89 54 24 20       	mov    %rdx,0x20(%rsp)
  40b7d0:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40b7d7:	00 00 
  40b7d9:	48 8d 54 24 38       	lea    0x38(%rsp),%rdx
  40b7de:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
  40b7e3:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40b7e8:	48 8d 54 24 20       	lea    0x20(%rsp),%rdx
  40b7ed:	48 89 94 24 00 02 00 	mov    %rdx,0x200(%rsp)
  40b7f4:	00 
  40b7f5:	4c 89 b4 24 08 02 00 	mov    %r14,0x208(%rsp)
  40b7fc:	00 
  40b7fd:	48 c7 c2 d0 21 43 00 	mov    $0x4321d0,%rdx
  40b804:	48 89 94 24 10 02 00 	mov    %rdx,0x210(%rsp)
  40b80b:	00 
  40b80c:	48 8d 94 24 00 02 00 	lea    0x200(%rsp),%rdx
  40b813:	00 
  40b814:	48 89 94 24 e0 01 00 	mov    %rdx,0x1e0(%rsp)
  40b81b:	00 
  40b81c:	48 8d 94 24 20 03 00 	lea    0x320(%rsp),%rdx
  40b823:	00 
  40b824:	48 89 94 24 e8 01 00 	mov    %rdx,0x1e8(%rsp)
  40b82b:	00 
  40b82c:	48 c7 c2 70 24 43 00 	mov    $0x432470,%rdx
  40b833:	48 89 94 24 f0 01 00 	mov    %rdx,0x1f0(%rsp)
  40b83a:	00 
  40b83b:	48 8d b4 24 e0 01 00 	lea    0x1e0(%rsp),%rsi
  40b842:	00 
  40b843:	48 89 b4 24 c0 01 00 	mov    %rsi,0x1c0(%rsp)
  40b84a:	00 
  40b84b:	4c 89 b4 24 c8 01 00 	mov    %r14,0x1c8(%rsp)
  40b852:	00 
  40b853:	48 c7 c6 90 22 43 00 	mov    $0x432290,%rsi
  40b85a:	48 89 b4 24 d0 01 00 	mov    %rsi,0x1d0(%rsp)
  40b861:	00 
  40b862:	48 8d b4 24 c0 01 00 	lea    0x1c0(%rsp),%rsi
  40b869:	00 
  40b86a:	48 89 b4 24 a0 01 00 	mov    %rsi,0x1a0(%rsp)
  40b871:	00 
  40b872:	48 8d b4 24 00 03 00 	lea    0x300(%rsp),%rsi
  40b879:	00 
  40b87a:	48 89 b4 24 a8 01 00 	mov    %rsi,0x1a8(%rsp)
  40b881:	00 
  40b882:	48 89 94 24 b0 01 00 	mov    %rdx,0x1b0(%rsp)
  40b889:	00 
  40b88a:	48 8d b4 24 a0 01 00 	lea    0x1a0(%rsp),%rsi
  40b891:	00 
  40b892:	48 89 b4 24 80 01 00 	mov    %rsi,0x180(%rsp)
  40b899:	00 
  40b89a:	4c 89 b4 24 88 01 00 	mov    %r14,0x188(%rsp)
  40b8a1:	00 
  40b8a2:	48 c7 c6 30 25 43 00 	mov    $0x432530,%rsi
  40b8a9:	48 89 b4 24 90 01 00 	mov    %rsi,0x190(%rsp)
  40b8b0:	00 
  40b8b1:	48 8d b4 24 80 01 00 	lea    0x180(%rsp),%rsi
  40b8b8:	00 
  40b8b9:	48 89 b4 24 60 01 00 	mov    %rsi,0x160(%rsp)
  40b8c0:	00 
  40b8c1:	48 8d b4 24 60 03 00 	lea    0x360(%rsp),%rsi
  40b8c8:	00 
  40b8c9:	48 89 b4 24 68 01 00 	mov    %rsi,0x168(%rsp)
  40b8d0:	00 
  40b8d1:	48 c7 c6 30 1f 43 00 	mov    $0x431f30,%rsi
  40b8d8:	48 89 b4 24 70 01 00 	mov    %rsi,0x170(%rsp)
  40b8df:	00 
  40b8e0:	48 8d b4 24 60 01 00 	lea    0x160(%rsp),%rsi
  40b8e7:	00 
  40b8e8:	48 89 b4 24 40 01 00 	mov    %rsi,0x140(%rsp)
  40b8ef:	00 
  40b8f0:	48 8d b4 24 40 03 00 	lea    0x340(%rsp),%rsi
  40b8f7:	00 
  40b8f8:	48 89 b4 24 48 01 00 	mov    %rsi,0x148(%rsp)
  40b8ff:	00 
  40b900:	48 89 94 24 50 01 00 	mov    %rdx,0x150(%rsp)
  40b907:	00 
  40b908:	48 8d 8c 24 40 01 00 	lea    0x140(%rsp),%rcx
  40b90f:	00 
  40b910:	48 89 8c 24 00 01 00 	mov    %rcx,0x100(%rsp)
  40b917:	00 
  40b918:	4c 89 a4 24 18 01 00 	mov    %r12,0x118(%rsp)
  40b91f:	00 
  40b920:	48 8d 8c 24 18 01 00 	lea    0x118(%rsp),%rcx
  40b927:	00 
  40b928:	48 89 8c 24 08 01 00 	mov    %rcx,0x108(%rsp)
  40b92f:	00 
  40b930:	48 89 84 24 10 01 00 	mov    %rax,0x110(%rsp)
  40b937:	00 
  40b938:	4c 8b bc 24 e0 02 00 	mov    0x2e0(%rsp),%r15
  40b93f:	00 
  40b940:	4c 89 ff             	mov    %r15,%rdi
  40b943:	4c 89 e6             	mov    %r12,%rsi
  40b946:	e8 65 a5 ff ff       	call   405eb0 <sexpr.printer::is_short_list>
  40b94b:	48 85 c0             	test   %rax,%rax
  40b94e:	0f 84 45 30 00 00    	je     40e999 <sexpr.printer::push_node+0x3859>
  40b954:	49 83 3c 24 00       	cmpq   $0x0,(%r12)
  40b959:	4c 89 e3             	mov    %r12,%rbx
  40b95c:	0f 8e 5c 3f 00 00    	jle    40f8be <sexpr.printer::push_node+0x477e>
  40b962:	4c 89 b4 24 58 03 00 	mov    %r14,0x358(%rsp)
  40b969:	00 
  40b96a:	4d 89 ec             	mov    %r13,%r12
  40b96d:	48 83 84 24 f8 02 00 	addq   $0x2,0x2f8(%rsp)
  40b974:	00 02 
  40b976:	31 ed                	xor    %ebp,%ebp
  40b978:	31 c0                	xor    %eax,%eax
  40b97a:	e9 5c 03 00 00       	jmp    40bcdb <sexpr.printer::push_node+0xb9b>
  40b97f:	90                   	nop
  40b980:	48 89 df             	mov    %rbx,%rdi
  40b983:	48 89 ee             	mov    %rbp,%rsi
  40b986:	4c 8d b4 24 a8 04 00 	lea    0x4a8(%rsp),%r14
  40b98d:	00 
  40b98e:	4c 89 f2             	mov    %r14,%rdx
  40b991:	e8 0a a0 00 00       	call   4159a0 <__wrap_myl_native_list_get>
  40b996:	48 8b 84 24 e8 02 00 	mov    0x2e8(%rsp),%rax
  40b99d:	00 
  40b99e:	48 8b 40 10          	mov    0x10(%rax),%rax
  40b9a2:	48 89 04 24          	mov    %rax,(%rsp)
  40b9a6:	4c 89 64 24 18       	mov    %r12,0x18(%rsp)
  40b9ab:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40b9b0:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40b9b5:	48 c7 c1 60 84 42 00 	mov    $0x428460,%rcx
  40b9bc:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
  40b9c1:	48 89 e0             	mov    %rsp,%rax
  40b9c4:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40b9cb:	00 
  40b9cc:	48 8b 84 24 f0 02 00 	mov    0x2f0(%rsp),%rax
  40b9d3:	00 
  40b9d4:	48 89 84 24 28 01 00 	mov    %rax,0x128(%rsp)
  40b9db:	00 
  40b9dc:	4c 89 bc 24 30 01 00 	mov    %r15,0x130(%rsp)
  40b9e3:	00 
  40b9e4:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40b9eb:	00 
  40b9ec:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40b9f3:	00 
  40b9f4:	48 8b 84 24 58 03 00 	mov    0x358(%rsp),%rax
  40b9fb:	00 
  40b9fc:	48 89 84 24 28 02 00 	mov    %rax,0x228(%rsp)
  40ba03:	00 
  40ba04:	48 c7 c2 b0 23 43 00 	mov    $0x4323b0,%rdx
  40ba0b:	48 89 94 24 30 02 00 	mov    %rdx,0x230(%rsp)
  40ba12:	00 
  40ba13:	48 8d 94 24 20 02 00 	lea    0x220(%rsp),%rdx
  40ba1a:	00 
  40ba1b:	48 89 94 24 e0 00 00 	mov    %rdx,0xe0(%rsp)
  40ba22:	00 
  40ba23:	48 89 9c 24 f8 00 00 	mov    %rbx,0xf8(%rsp)
  40ba2a:	00 
  40ba2b:	48 8d 94 24 f8 00 00 	lea    0xf8(%rsp),%rdx
  40ba32:	00 
  40ba33:	48 89 94 24 e8 00 00 	mov    %rdx,0xe8(%rsp)
  40ba3a:	00 
  40ba3b:	48 c7 c2 b0 20 43 00 	mov    $0x4320b0,%rdx
  40ba42:	48 89 94 24 f0 00 00 	mov    %rdx,0xf0(%rsp)
  40ba49:	00 
  40ba4a:	48 8d b4 24 e0 00 00 	lea    0xe0(%rsp),%rsi
  40ba51:	00 
  40ba52:	48 89 b4 24 c0 00 00 	mov    %rsi,0xc0(%rsp)
  40ba59:	00 
  40ba5a:	48 89 9c 24 d8 00 00 	mov    %rbx,0xd8(%rsp)
  40ba61:	00 
  40ba62:	48 8d b4 24 d8 00 00 	lea    0xd8(%rsp),%rsi
  40ba69:	00 
  40ba6a:	48 89 b4 24 c8 00 00 	mov    %rsi,0xc8(%rsp)
  40ba71:	00 
  40ba72:	48 89 94 24 d0 00 00 	mov    %rdx,0xd0(%rsp)
  40ba79:	00 
  40ba7a:	48 8d b4 24 c0 00 00 	lea    0xc0(%rsp),%rsi
  40ba81:	00 
  40ba82:	48 89 b4 24 a0 00 00 	mov    %rsi,0xa0(%rsp)
  40ba89:	00 
  40ba8a:	48 89 9c 24 b8 00 00 	mov    %rbx,0xb8(%rsp)
  40ba91:	00 
  40ba92:	48 8d b4 24 b8 00 00 	lea    0xb8(%rsp),%rsi
  40ba99:	00 
  40ba9a:	48 89 b4 24 a8 00 00 	mov    %rsi,0xa8(%rsp)
  40baa1:	00 
  40baa2:	48 89 94 24 b0 00 00 	mov    %rdx,0xb0(%rsp)
  40baa9:	00 
  40baaa:	48 8d b4 24 a0 00 00 	lea    0xa0(%rsp),%rsi
  40bab1:	00 
  40bab2:	48 89 b4 24 80 00 00 	mov    %rsi,0x80(%rsp)
  40bab9:	00 
  40baba:	48 89 9c 24 98 00 00 	mov    %rbx,0x98(%rsp)
  40bac1:	00 
  40bac2:	48 8d b4 24 98 00 00 	lea    0x98(%rsp),%rsi
  40bac9:	00 
  40baca:	48 89 b4 24 88 00 00 	mov    %rsi,0x88(%rsp)
  40bad1:	00 
  40bad2:	48 89 94 24 90 00 00 	mov    %rdx,0x90(%rsp)
  40bad9:	00 
  40bada:	48 8d b4 24 80 00 00 	lea    0x80(%rsp),%rsi
  40bae1:	00 
  40bae2:	48 89 74 24 60       	mov    %rsi,0x60(%rsp)
  40bae7:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40baee:	00 00 
  40baf0:	48 8d 74 24 78       	lea    0x78(%rsp),%rsi
  40baf5:	48 89 74 24 68       	mov    %rsi,0x68(%rsp)
  40bafa:	48 89 54 24 70       	mov    %rdx,0x70(%rsp)
  40baff:	48 8d 74 24 60       	lea    0x60(%rsp),%rsi
  40bb04:	48 89 74 24 40       	mov    %rsi,0x40(%rsp)
  40bb09:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40bb10:	00 00 
  40bb12:	48 8d 74 24 58       	lea    0x58(%rsp),%rsi
  40bb17:	48 89 74 24 48       	mov    %rsi,0x48(%rsp)
  40bb1c:	48 89 54 24 50       	mov    %rdx,0x50(%rsp)
  40bb21:	48 8d 74 24 40       	lea    0x40(%rsp),%rsi
  40bb26:	48 89 74 24 20       	mov    %rsi,0x20(%rsp)
  40bb2b:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40bb32:	00 00 
  40bb34:	48 8d 74 24 38       	lea    0x38(%rsp),%rsi
  40bb39:	48 89 74 24 28       	mov    %rsi,0x28(%rsp)
  40bb3e:	48 89 54 24 30       	mov    %rdx,0x30(%rsp)
  40bb43:	48 8d 54 24 20       	lea    0x20(%rsp),%rdx
  40bb48:	48 89 94 24 00 02 00 	mov    %rdx,0x200(%rsp)
  40bb4f:	00 
  40bb50:	48 89 84 24 08 02 00 	mov    %rax,0x208(%rsp)
  40bb57:	00 
  40bb58:	48 c7 c2 d0 21 43 00 	mov    $0x4321d0,%rdx
  40bb5f:	48 89 94 24 10 02 00 	mov    %rdx,0x210(%rsp)
  40bb66:	00 
  40bb67:	48 8d 94 24 00 02 00 	lea    0x200(%rsp),%rdx
  40bb6e:	00 
  40bb6f:	48 89 94 24 e0 01 00 	mov    %rdx,0x1e0(%rsp)
  40bb76:	00 
  40bb77:	48 8d 94 24 20 03 00 	lea    0x320(%rsp),%rdx
  40bb7e:	00 
  40bb7f:	48 89 94 24 e8 01 00 	mov    %rdx,0x1e8(%rsp)
  40bb86:	00 
  40bb87:	48 c7 c2 70 24 43 00 	mov    $0x432470,%rdx
  40bb8e:	48 89 94 24 f0 01 00 	mov    %rdx,0x1f0(%rsp)
  40bb95:	00 
  40bb96:	48 8d b4 24 e0 01 00 	lea    0x1e0(%rsp),%rsi
  40bb9d:	00 
  40bb9e:	48 89 b4 24 c0 01 00 	mov    %rsi,0x1c0(%rsp)
  40bba5:	00 
  40bba6:	48 89 84 24 c8 01 00 	mov    %rax,0x1c8(%rsp)
  40bbad:	00 
  40bbae:	48 c7 c6 90 22 43 00 	mov    $0x432290,%rsi
  40bbb5:	48 89 b4 24 d0 01 00 	mov    %rsi,0x1d0(%rsp)
  40bbbc:	00 
  40bbbd:	48 8d b4 24 c0 01 00 	lea    0x1c0(%rsp),%rsi
  40bbc4:	00 
  40bbc5:	48 89 b4 24 a0 01 00 	mov    %rsi,0x1a0(%rsp)
  40bbcc:	00 
  40bbcd:	48 8d b4 24 00 03 00 	lea    0x300(%rsp),%rsi
  40bbd4:	00 
  40bbd5:	48 89 b4 24 a8 01 00 	mov    %rsi,0x1a8(%rsp)
  40bbdc:	00 
  40bbdd:	48 89 94 24 b0 01 00 	mov    %rdx,0x1b0(%rsp)
  40bbe4:	00 
  40bbe5:	48 8d b4 24 a0 01 00 	lea    0x1a0(%rsp),%rsi
  40bbec:	00 
  40bbed:	48 89 b4 24 80 01 00 	mov    %rsi,0x180(%rsp)
  40bbf4:	00 
  40bbf5:	48 89 84 24 88 01 00 	mov    %rax,0x188(%rsp)
  40bbfc:	00 
  40bbfd:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40bc04:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40bc0b:	00 
  40bc0c:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40bc13:	00 
  40bc14:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40bc1b:	00 
  40bc1c:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40bc23:	00 
  40bc24:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40bc2b:	00 
  40bc2c:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40bc33:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40bc3a:	00 
  40bc3b:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40bc42:	00 
  40bc43:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40bc4a:	00 
  40bc4b:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40bc52:	00 
  40bc53:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40bc5a:	00 
  40bc5b:	48 89 94 24 50 01 00 	mov    %rdx,0x150(%rsp)
  40bc62:	00 
  40bc63:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40bc6a:	00 
  40bc6b:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40bc72:	00 
  40bc73:	4c 89 a4 24 18 01 00 	mov    %r12,0x118(%rsp)
  40bc7a:	00 
  40bc7b:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40bc82:	00 
  40bc83:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40bc8a:	00 
  40bc8b:	48 89 8c 24 10 01 00 	mov    %rcx,0x110(%rsp)
  40bc92:	00 
  40bc93:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40bc9a:	00 
  40bc9b:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40bca2:	00 
  40bca3:	4c 89 b4 24 a8 02 00 	mov    %r14,0x2a8(%rsp)
  40bcaa:	00 
  40bcab:	4c 89 bc 24 b0 02 00 	mov    %r15,0x2b0(%rsp)
  40bcb2:	00 
  40bcb3:	4c 89 e6             	mov    %r12,%rsi
  40bcb6:	4d 89 ef             	mov    %r13,%r15
  40bcb9:	4c 89 ef             	mov    %r13,%rdi
  40bcbc:	4c 89 f2             	mov    %r14,%rdx
  40bcbf:	48 8b 8c 24 f8 02 00 	mov    0x2f8(%rsp),%rcx
  40bcc6:	00 
  40bcc7:	e8 74 f4 ff ff       	call   40b140 <sexpr.printer::push_node>
  40bccc:	48 ff c5             	inc    %rbp
  40bccf:	48 89 d8             	mov    %rbx,%rax
  40bcd2:	48 3b 2b             	cmp    (%rbx),%rbp
  40bcd5:	0f 8d 75 2c 00 00    	jge    40e950 <sexpr.printer::push_node+0x3810>
  40bcdb:	48 85 ed             	test   %rbp,%rbp
  40bcde:	4d 89 fd             	mov    %r15,%r13
  40bce1:	49 c7 c7 50 20 43 00 	mov    $0x432050,%r15
  40bce8:	0f 84 92 fc ff ff    	je     40b980 <sexpr.printer::push_node+0x840>
  40bcee:	48 8b 8c 24 e8 02 00 	mov    0x2e8(%rsp),%rcx
  40bcf5:	00 
  40bcf6:	48 8b 49 10          	mov    0x10(%rcx),%rcx
  40bcfa:	48 89 0c 24          	mov    %rcx,(%rsp)
  40bcfe:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  40bd05:	00 
  40bd06:	48 89 8c 24 80 00 00 	mov    %rcx,0x80(%rsp)
  40bd0d:	00 
  40bd0e:	48 89 84 24 98 00 00 	mov    %rax,0x98(%rsp)
  40bd15:	00 
  40bd16:	4d 89 e5             	mov    %r12,%r13
  40bd19:	48 c7 c0 b8 27 43 00 	mov    $0x4327b8,%rax
  40bd20:	4c 8b 20             	mov    (%rax),%r12
  40bd23:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40bd28:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40bd2d:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40bd32:	49 c7 c7 60 84 42 00 	mov    $0x428460,%r15
  40bd39:	4c 89 7c 24 10       	mov    %r15,0x10(%rsp)
  40bd3e:	48 89 e0             	mov    %rsp,%rax
  40bd41:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40bd48:	00 
  40bd49:	4c 8b b4 24 f0 02 00 	mov    0x2f0(%rsp),%r14
  40bd50:	00 
  40bd51:	4c 89 b4 24 28 01 00 	mov    %r14,0x128(%rsp)
  40bd58:	00 
  40bd59:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40bd60:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40bd67:	00 
  40bd68:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40bd6f:	00 
  40bd70:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40bd77:	00 
  40bd78:	49 8d 46 08          	lea    0x8(%r14),%rax
  40bd7c:	48 89 84 24 28 02 00 	mov    %rax,0x228(%rsp)
  40bd83:	00 
  40bd84:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40bd8b:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40bd92:	00 
  40bd93:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40bd9a:	00 
  40bd9b:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40bda2:	00 
  40bda3:	48 89 9c 24 f8 00 00 	mov    %rbx,0xf8(%rsp)
  40bdaa:	00 
  40bdab:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40bdb2:	00 
  40bdb3:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40bdba:	00 
  40bdbb:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40bdc2:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40bdc9:	00 
  40bdca:	48 8d 8c 24 e0 00 00 	lea    0xe0(%rsp),%rcx
  40bdd1:	00 
  40bdd2:	48 89 8c 24 c0 00 00 	mov    %rcx,0xc0(%rsp)
  40bdd9:	00 
  40bdda:	48 89 9c 24 d8 00 00 	mov    %rbx,0xd8(%rsp)
  40bde1:	00 
  40bde2:	48 8d 8c 24 d8 00 00 	lea    0xd8(%rsp),%rcx
  40bde9:	00 
  40bdea:	48 89 8c 24 c8 00 00 	mov    %rcx,0xc8(%rsp)
  40bdf1:	00 
  40bdf2:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40bdf9:	00 
  40bdfa:	48 8d 8c 24 c0 00 00 	lea    0xc0(%rsp),%rcx
  40be01:	00 
  40be02:	48 89 8c 24 a0 00 00 	mov    %rcx,0xa0(%rsp)
  40be09:	00 
  40be0a:	48 89 9c 24 b8 00 00 	mov    %rbx,0xb8(%rsp)
  40be11:	00 
  40be12:	48 8d 8c 24 b8 00 00 	lea    0xb8(%rsp),%rcx
  40be19:	00 
  40be1a:	48 89 8c 24 a8 00 00 	mov    %rcx,0xa8(%rsp)
  40be21:	00 
  40be22:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40be29:	00 
  40be2a:	48 8d 8c 24 98 00 00 	lea    0x98(%rsp),%rcx
  40be31:	00 
  40be32:	48 89 8c 24 88 00 00 	mov    %rcx,0x88(%rsp)
  40be39:	00 
  40be3a:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40be41:	00 
  40be42:	48 8d 8c 24 80 00 00 	lea    0x80(%rsp),%rcx
  40be49:	00 
  40be4a:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
  40be4f:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40be56:	00 00 
  40be58:	48 8d 4c 24 78       	lea    0x78(%rsp),%rcx
  40be5d:	48 89 4c 24 68       	mov    %rcx,0x68(%rsp)
  40be62:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40be67:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  40be6c:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  40be71:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40be78:	00 00 
  40be7a:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  40be7f:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  40be84:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40be89:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  40be8e:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  40be93:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40be9a:	00 00 
  40be9c:	48 8d 4c 24 38       	lea    0x38(%rsp),%rcx
  40bea1:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
  40bea6:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40beab:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40beb0:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40beb7:	00 
  40beb8:	49 8d 46 08          	lea    0x8(%r14),%rax
  40bebc:	48 89 84 24 08 02 00 	mov    %rax,0x208(%rsp)
  40bec3:	00 
  40bec4:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40becb:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40bed2:	00 
  40bed3:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40beda:	00 
  40bedb:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40bee2:	00 
  40bee3:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40beea:	00 
  40beeb:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40bef2:	00 
  40bef3:	48 c7 c1 70 24 43 00 	mov    $0x432470,%rcx
  40befa:	48 89 8c 24 f0 01 00 	mov    %rcx,0x1f0(%rsp)
  40bf01:	00 
  40bf02:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40bf09:	00 
  40bf0a:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40bf11:	00 
  40bf12:	49 8d 46 08          	lea    0x8(%r14),%rax
  40bf16:	48 89 84 24 c8 01 00 	mov    %rax,0x1c8(%rsp)
  40bf1d:	00 
  40bf1e:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40bf25:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40bf2c:	00 
  40bf2d:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40bf34:	00 
  40bf35:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40bf3c:	00 
  40bf3d:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40bf44:	00 
  40bf45:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40bf4c:	00 
  40bf4d:	48 89 8c 24 b0 01 00 	mov    %rcx,0x1b0(%rsp)
  40bf54:	00 
  40bf55:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40bf5c:	00 
  40bf5d:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40bf64:	00 
  40bf65:	49 8d 46 08          	lea    0x8(%r14),%rax
  40bf69:	48 89 84 24 88 01 00 	mov    %rax,0x188(%rsp)
  40bf70:	00 
  40bf71:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40bf78:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40bf7f:	00 
  40bf80:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40bf87:	00 
  40bf88:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40bf8f:	00 
  40bf90:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40bf97:	00 
  40bf98:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40bf9f:	00 
  40bfa0:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40bfa7:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40bfae:	00 
  40bfaf:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40bfb6:	00 
  40bfb7:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40bfbe:	00 
  40bfbf:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40bfc6:	00 
  40bfc7:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40bfce:	00 
  40bfcf:	48 89 8c 24 50 01 00 	mov    %rcx,0x150(%rsp)
  40bfd6:	00 
  40bfd7:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40bfde:	00 
  40bfdf:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40bfe6:	00 
  40bfe7:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40bfee:	00 
  40bfef:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40bff6:	00 
  40bff7:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40bffe:	00 
  40bfff:	4c 89 bc 24 10 01 00 	mov    %r15,0x110(%rsp)
  40c006:	00 
  40c007:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40c00e:	00 
  40c00f:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40c016:	00 
  40c017:	4c 89 a4 24 b8 02 00 	mov    %r12,0x2b8(%rsp)
  40c01e:	00 
  40c01f:	48 8d 84 24 b8 02 00 	lea    0x2b8(%rsp),%rax
  40c026:	00 
  40c027:	48 89 84 24 a8 02 00 	mov    %rax,0x2a8(%rsp)
  40c02e:	00 
  40c02f:	48 c7 c0 d0 1e 43 00 	mov    $0x431ed0,%rax
  40c036:	48 89 84 24 b0 02 00 	mov    %rax,0x2b0(%rsp)
  40c03d:	00 
  40c03e:	48 8b bc 24 e0 02 00 	mov    0x2e0(%rsp),%rdi
  40c045:	00 
  40c046:	e8 25 f5 00 00       	call   41b570 <myl_qbe_heap>
  40c04b:	49 8b 75 00          	mov    0x0(%r13),%rsi
  40c04f:	4d 8b 04 24          	mov    (%r12),%r8
  40c053:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40c057:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40c05e:	00 
  40c05f:	4c 89 ac 24 58 02 00 	mov    %r13,0x258(%rsp)
  40c066:	00 
  40c067:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40c06e:	00 
  40c06f:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40c076:	00 
  40c077:	4c 89 bc 24 50 02 00 	mov    %r15,0x250(%rsp)
  40c07e:	00 
  40c07f:	49 c7 c7 50 20 43 00 	mov    $0x432050,%r15
  40c086:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40c08d:	00 
  40c08e:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40c095:	00 
  40c096:	4c 89 a4 24 78 02 00 	mov    %r12,0x278(%rsp)
  40c09d:	00 
  40c09e:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40c0a5:	00 
  40c0a6:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40c0ad:	00 
  40c0ae:	48 c7 c2 d0 1e 43 00 	mov    $0x431ed0,%rdx
  40c0b5:	48 89 94 24 70 02 00 	mov    %rdx,0x270(%rsp)
  40c0bc:	00 
  40c0bd:	48 8d 8c 24 60 02 00 	lea    0x260(%rsp),%rcx
  40c0c4:	00 
  40c0c5:	48 89 8c 24 80 02 00 	mov    %rcx,0x280(%rsp)
  40c0cc:	00 
  40c0cd:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40c0d4:	00 
  40c0d5:	48 8d 8c 24 98 02 00 	lea    0x298(%rsp),%rcx
  40c0dc:	00 
  40c0dd:	48 89 8c 24 88 02 00 	mov    %rcx,0x288(%rsp)
  40c0e4:	00 
  40c0e5:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40c0ec:	48 89 8c 24 90 02 00 	mov    %rcx,0x290(%rsp)
  40c0f3:	00 
  40c0f4:	48 8d 8c 24 80 02 00 	lea    0x280(%rsp),%rcx
  40c0fb:	00 
  40c0fc:	48 89 8c 24 c0 02 00 	mov    %rcx,0x2c0(%rsp)
  40c103:	00 
  40c104:	4c 89 a4 24 d8 02 00 	mov    %r12,0x2d8(%rsp)
  40c10b:	00 
  40c10c:	48 8d 8c 24 d8 02 00 	lea    0x2d8(%rsp),%rcx
  40c113:	00 
  40c114:	48 89 8c 24 c8 02 00 	mov    %rcx,0x2c8(%rsp)
  40c11b:	00 
  40c11c:	48 89 94 24 d0 02 00 	mov    %rdx,0x2d0(%rsp)
  40c123:	00 
  40c124:	48 89 c7             	mov    %rax,%rdi
  40c127:	4c 89 e2             	mov    %r12,%rdx
  40c12a:	4d 89 ec             	mov    %r13,%r12
  40c12d:	4c 8b ac 24 e0 02 00 	mov    0x2e0(%rsp),%r13
  40c134:	00 
  40c135:	31 c9                	xor    %ecx,%ecx
  40c137:	e8 84 4a 01 00       	call   420bc0 <myl_native_bytes_buffer_append_range>
  40c13c:	e9 3f f8 ff ff       	jmp    40b980 <sexpr.printer::push_node+0x840>
  40c141:	49 8b 56 08          	mov    0x8(%r14),%rdx
  40c145:	c4 c1 7c 10 46 20    	vmovups 0x20(%r14),%ymm0
  40c14b:	c5 fc 11 84 24 60 03 	vmovups %ymm0,0x360(%rsp)
  40c152:	00 00 
  40c154:	8b 84 24 60 03 00 00 	mov    0x360(%rsp),%eax
  40c15b:	85 c0                	test   %eax,%eax
  40c15d:	0f 84 de 24 00 00    	je     40e641 <sexpr.printer::push_node+0x3501>
  40c163:	83 f8 01             	cmp    $0x1,%eax
  40c166:	0f 85 71 3b 00 00    	jne    40fcdd <sexpr.printer::push_node+0x4b9d>
  40c16c:	c5 f8 10 84 24 68 03 	vmovups 0x368(%rsp),%xmm0
  40c173:	00 00 
  40c175:	c5 f8 29 84 24 40 03 	vmovaps %xmm0,0x340(%rsp)
  40c17c:	00 00 
  40c17e:	48 8b 84 24 78 03 00 	mov    0x378(%rsp),%rax
  40c185:	00 
  40c186:	48 89 84 24 50 03 00 	mov    %rax,0x350(%rsp)
  40c18d:	00 
  40c18e:	49 8b 40 10          	mov    0x10(%r8),%rax
  40c192:	48 89 04 24          	mov    %rax,(%rsp)
  40c196:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40c19b:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40c1a0:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40c1a5:	48 c7 c3 60 84 42 00 	mov    $0x428460,%rbx
  40c1ac:	48 89 5c 24 10       	mov    %rbx,0x10(%rsp)
  40c1b1:	48 89 e0             	mov    %rsp,%rax
  40c1b4:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40c1bb:	00 
  40c1bc:	4c 89 b4 24 28 01 00 	mov    %r14,0x128(%rsp)
  40c1c3:	00 
  40c1c4:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40c1cb:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40c1d2:	00 
  40c1d3:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40c1da:	00 
  40c1db:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40c1e2:	00 
  40c1e3:	4c 89 9c 24 28 02 00 	mov    %r11,0x228(%rsp)
  40c1ea:	00 
  40c1eb:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40c1f2:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40c1f9:	00 
  40c1fa:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40c201:	00 
  40c202:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40c209:	00 
  40c20a:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40c211:	00 
  40c212:	48 c7 84 24 f8 00 00 	movq   $0x0,0xf8(%rsp)
  40c219:	00 00 00 00 00 
  40c21e:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40c225:	00 
  40c226:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40c22d:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40c234:	00 
  40c235:	48 8d 8c 24 e0 00 00 	lea    0xe0(%rsp),%rcx
  40c23c:	00 
  40c23d:	48 89 8c 24 c0 00 00 	mov    %rcx,0xc0(%rsp)
  40c244:	00 
  40c245:	48 8d 8c 24 d8 00 00 	lea    0xd8(%rsp),%rcx
  40c24c:	00 
  40c24d:	48 c7 84 24 d8 00 00 	movq   $0x0,0xd8(%rsp)
  40c254:	00 00 00 00 00 
  40c259:	48 89 8c 24 c8 00 00 	mov    %rcx,0xc8(%rsp)
  40c260:	00 
  40c261:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40c268:	00 
  40c269:	48 8d 8c 24 c0 00 00 	lea    0xc0(%rsp),%rcx
  40c270:	00 
  40c271:	48 89 8c 24 a0 00 00 	mov    %rcx,0xa0(%rsp)
  40c278:	00 
  40c279:	48 8d 8c 24 b8 00 00 	lea    0xb8(%rsp),%rcx
  40c280:	00 
  40c281:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40c288:	00 00 00 00 00 
  40c28d:	48 89 8c 24 a8 00 00 	mov    %rcx,0xa8(%rsp)
  40c294:	00 
  40c295:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40c29c:	00 
  40c29d:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  40c2a4:	00 
  40c2a5:	48 89 8c 24 80 00 00 	mov    %rcx,0x80(%rsp)
  40c2ac:	00 
  40c2ad:	48 8d 8c 24 98 00 00 	lea    0x98(%rsp),%rcx
  40c2b4:	00 
  40c2b5:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40c2bc:	00 00 00 00 00 
  40c2c1:	48 89 8c 24 88 00 00 	mov    %rcx,0x88(%rsp)
  40c2c8:	00 
  40c2c9:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40c2d0:	00 
  40c2d1:	48 8d 8c 24 80 00 00 	lea    0x80(%rsp),%rcx
  40c2d8:	00 
  40c2d9:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
  40c2de:	48 8d 4c 24 78       	lea    0x78(%rsp),%rcx
  40c2e3:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40c2ea:	00 00 
  40c2ec:	48 89 4c 24 68       	mov    %rcx,0x68(%rsp)
  40c2f1:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40c2f6:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  40c2fb:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  40c300:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  40c305:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40c30c:	00 00 
  40c30e:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  40c313:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40c318:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  40c31d:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  40c322:	48 8d 4c 24 38       	lea    0x38(%rsp),%rcx
  40c327:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40c32e:	00 00 
  40c330:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
  40c335:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40c33a:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40c33f:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40c346:	00 
  40c347:	4c 89 9c 24 08 02 00 	mov    %r11,0x208(%rsp)
  40c34e:	00 
  40c34f:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40c356:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40c35d:	00 
  40c35e:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40c365:	00 
  40c366:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40c36d:	00 
  40c36e:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40c375:	00 
  40c376:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40c37d:	00 
  40c37e:	4c 89 ed             	mov    %r13,%rbp
  40c381:	49 c7 c4 70 24 43 00 	mov    $0x432470,%r12
  40c388:	4c 89 a4 24 f0 01 00 	mov    %r12,0x1f0(%rsp)
  40c38f:	00 
  40c390:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40c397:	00 
  40c398:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40c39f:	00 
  40c3a0:	4c 89 9c 24 c8 01 00 	mov    %r11,0x1c8(%rsp)
  40c3a7:	00 
  40c3a8:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40c3af:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40c3b6:	00 
  40c3b7:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40c3be:	00 
  40c3bf:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40c3c6:	00 
  40c3c7:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40c3ce:	00 
  40c3cf:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40c3d6:	00 
  40c3d7:	4c 89 a4 24 b0 01 00 	mov    %r12,0x1b0(%rsp)
  40c3de:	00 
  40c3df:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40c3e6:	00 
  40c3e7:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40c3ee:	00 
  40c3ef:	4c 89 9c 24 88 01 00 	mov    %r11,0x188(%rsp)
  40c3f6:	00 
  40c3f7:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40c3fe:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40c405:	00 
  40c406:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40c40d:	00 
  40c40e:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40c415:	00 
  40c416:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40c41d:	00 
  40c41e:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40c425:	00 
  40c426:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40c42d:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40c434:	00 
  40c435:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40c43c:	00 
  40c43d:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40c444:	00 
  40c445:	4c 8d ac 24 40 03 00 	lea    0x340(%rsp),%r13
  40c44c:	00 
  40c44d:	4c 89 ac 24 48 01 00 	mov    %r13,0x148(%rsp)
  40c454:	00 
  40c455:	4c 89 a4 24 50 01 00 	mov    %r12,0x150(%rsp)
  40c45c:	00 
  40c45d:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40c464:	00 
  40c465:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40c46c:	00 
  40c46d:	48 89 ac 24 18 01 00 	mov    %rbp,0x118(%rsp)
  40c474:	00 
  40c475:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40c47c:	00 
  40c47d:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40c484:	00 
  40c485:	48 89 9c 24 10 01 00 	mov    %rbx,0x110(%rsp)
  40c48c:	00 
  40c48d:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40c494:	00 
  40c495:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40c49c:	00 
  40c49d:	4c 89 ac 24 a8 02 00 	mov    %r13,0x2a8(%rsp)
  40c4a4:	00 
  40c4a5:	4c 89 a4 24 b0 02 00 	mov    %r12,0x2b0(%rsp)
  40c4ac:	00 
  40c4ad:	4c 89 ff             	mov    %r15,%rdi
  40c4b0:	c5 f8 77             	vzeroupper
  40c4b3:	e8 b8 f0 00 00       	call   41b570 <myl_qbe_heap>
  40c4b8:	4c 8b b4 24 40 03 00 	mov    0x340(%rsp),%r14
  40c4bf:	00 
  40c4c0:	48 8b 40 10          	mov    0x10(%rax),%rax
  40c4c4:	48 89 84 24 a8 03 00 	mov    %rax,0x3a8(%rsp)
  40c4cb:	00 
  40c4cc:	48 8d 84 24 c0 03 00 	lea    0x3c0(%rsp),%rax
  40c4d3:	00 
  40c4d4:	48 89 ac 24 c0 03 00 	mov    %rbp,0x3c0(%rsp)
  40c4db:	00 
  40c4dc:	48 89 84 24 b0 03 00 	mov    %rax,0x3b0(%rsp)
  40c4e3:	00 
  40c4e4:	48 89 9c 24 b8 03 00 	mov    %rbx,0x3b8(%rsp)
  40c4eb:	00 
  40c4ec:	4c 89 ff             	mov    %r15,%rdi
  40c4ef:	4c 8b bc 24 48 03 00 	mov    0x348(%rsp),%r15
  40c4f6:	00 
  40c4f7:	48 8d 84 24 a8 03 00 	lea    0x3a8(%rsp),%rax
  40c4fe:	00 
  40c4ff:	48 89 84 24 f0 03 00 	mov    %rax,0x3f0(%rsp)
  40c506:	00 
  40c507:	4c 89 ac 24 f8 03 00 	mov    %r13,0x3f8(%rsp)
  40c50e:	00 
  40c50f:	4c 89 a4 24 00 04 00 	mov    %r12,0x400(%rsp)
  40c516:	00 
  40c517:	48 8d 84 24 f0 03 00 	lea    0x3f0(%rsp),%rax
  40c51e:	00 
  40c51f:	48 89 84 24 88 03 00 	mov    %rax,0x388(%rsp)
  40c526:	00 
  40c527:	48 8d 84 24 a0 03 00 	lea    0x3a0(%rsp),%rax
  40c52e:	00 
  40c52f:	48 89 ac 24 a0 03 00 	mov    %rbp,0x3a0(%rsp)
  40c536:	00 
  40c537:	48 89 84 24 90 03 00 	mov    %rax,0x390(%rsp)
  40c53e:	00 
  40c53f:	48 89 9c 24 98 03 00 	mov    %rbx,0x398(%rsp)
  40c546:	00 
  40c547:	4c 8b a4 24 50 03 00 	mov    0x350(%rsp),%r12
  40c54e:	00 
  40c54f:	e9 c2 14 00 00       	jmp    40da16 <sexpr.printer::push_node+0x28d6>
  40c554:	c4 c1 78 10 03       	vmovups (%r11),%xmm0
  40c559:	49 8b 43 10          	mov    0x10(%r11),%rax
  40c55d:	48 89 84 24 10 03 00 	mov    %rax,0x310(%rsp)
  40c564:	00 
  40c565:	c5 f8 29 84 24 00 03 	vmovaps %xmm0,0x300(%rsp)
  40c56c:	00 00 
  40c56e:	49 8b 40 10          	mov    0x10(%r8),%rax
  40c572:	48 89 04 24          	mov    %rax,(%rsp)
  40c576:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40c57b:	4c 89 ea             	mov    %r13,%rdx
  40c57e:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40c583:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40c588:	48 c7 c5 60 84 42 00 	mov    $0x428460,%rbp
  40c58f:	48 89 6c 24 10       	mov    %rbp,0x10(%rsp)
  40c594:	48 89 e0             	mov    %rsp,%rax
  40c597:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40c59e:	00 
  40c59f:	4c 89 b4 24 28 01 00 	mov    %r14,0x128(%rsp)
  40c5a6:	00 
  40c5a7:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40c5ae:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40c5b5:	00 
  40c5b6:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40c5bd:	00 
  40c5be:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40c5c5:	00 
  40c5c6:	4c 89 9c 24 28 02 00 	mov    %r11,0x228(%rsp)
  40c5cd:	00 
  40c5ce:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40c5d5:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40c5dc:	00 
  40c5dd:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40c5e4:	00 
  40c5e5:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40c5ec:	00 
  40c5ed:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40c5f4:	00 
  40c5f5:	48 c7 84 24 f8 00 00 	movq   $0x0,0xf8(%rsp)
  40c5fc:	00 00 00 00 00 
  40c601:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40c608:	00 
  40c609:	49 c7 c5 b0 20 43 00 	mov    $0x4320b0,%r13
  40c610:	4c 89 ac 24 f0 00 00 	mov    %r13,0xf0(%rsp)
  40c617:	00 
  40c618:	48 8d 84 24 e0 00 00 	lea    0xe0(%rsp),%rax
  40c61f:	00 
  40c620:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  40c627:	00 
  40c628:	48 8d 84 24 d8 00 00 	lea    0xd8(%rsp),%rax
  40c62f:	00 
  40c630:	48 c7 84 24 d8 00 00 	movq   $0x0,0xd8(%rsp)
  40c637:	00 00 00 00 00 
  40c63c:	48 89 84 24 c8 00 00 	mov    %rax,0xc8(%rsp)
  40c643:	00 
  40c644:	4c 89 ac 24 d0 00 00 	mov    %r13,0xd0(%rsp)
  40c64b:	00 
  40c64c:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  40c653:	00 
  40c654:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  40c65b:	00 
  40c65c:	48 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%rax
  40c663:	00 
  40c664:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40c66b:	00 00 00 00 00 
  40c670:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  40c677:	00 
  40c678:	4c 89 ac 24 b0 00 00 	mov    %r13,0xb0(%rsp)
  40c67f:	00 
  40c680:	48 8d 84 24 a0 00 00 	lea    0xa0(%rsp),%rax
  40c687:	00 
  40c688:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  40c68f:	00 
  40c690:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  40c697:	00 
  40c698:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40c69f:	00 00 00 00 00 
  40c6a4:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  40c6ab:	00 
  40c6ac:	4c 89 ac 24 90 00 00 	mov    %r13,0x90(%rsp)
  40c6b3:	00 
  40c6b4:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  40c6bb:	00 
  40c6bc:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40c6c1:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40c6c8:	00 00 
  40c6ca:	48 8d 44 24 78       	lea    0x78(%rsp),%rax
  40c6cf:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  40c6d4:	4c 89 6c 24 70       	mov    %r13,0x70(%rsp)
  40c6d9:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40c6de:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40c6e3:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40c6ea:	00 00 
  40c6ec:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  40c6f1:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40c6f6:	4c 89 6c 24 50       	mov    %r13,0x50(%rsp)
  40c6fb:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40c700:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40c705:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40c70c:	00 00 
  40c70e:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40c713:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40c718:	4c 89 6c 24 30       	mov    %r13,0x30(%rsp)
  40c71d:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40c722:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40c729:	00 
  40c72a:	4c 89 9c 24 08 02 00 	mov    %r11,0x208(%rsp)
  40c731:	00 
  40c732:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40c739:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40c740:	00 
  40c741:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40c748:	00 
  40c749:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40c750:	00 
  40c751:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40c758:	00 
  40c759:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40c760:	00 
  40c761:	48 c7 c6 70 24 43 00 	mov    $0x432470,%rsi
  40c768:	48 89 b4 24 f0 01 00 	mov    %rsi,0x1f0(%rsp)
  40c76f:	00 
  40c770:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40c777:	00 
  40c778:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40c77f:	00 
  40c780:	4c 89 9c 24 c8 01 00 	mov    %r11,0x1c8(%rsp)
  40c787:	00 
  40c788:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40c78f:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40c796:	00 
  40c797:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40c79e:	00 
  40c79f:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40c7a6:	00 
  40c7a7:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40c7ae:	00 
  40c7af:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40c7b6:	00 
  40c7b7:	48 89 b4 24 b0 01 00 	mov    %rsi,0x1b0(%rsp)
  40c7be:	00 
  40c7bf:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40c7c6:	00 
  40c7c7:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40c7ce:	00 
  40c7cf:	4c 89 9c 24 88 01 00 	mov    %r11,0x188(%rsp)
  40c7d6:	00 
  40c7d7:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40c7de:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40c7e5:	00 
  40c7e6:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40c7ed:	00 
  40c7ee:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40c7f5:	00 
  40c7f6:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40c7fd:	00 
  40c7fe:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40c805:	00 
  40c806:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40c80d:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40c814:	00 
  40c815:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40c81c:	00 
  40c81d:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40c824:	00 
  40c825:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40c82c:	00 
  40c82d:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40c834:	00 
  40c835:	48 89 b4 24 50 01 00 	mov    %rsi,0x150(%rsp)
  40c83c:	00 
  40c83d:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40c844:	00 
  40c845:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40c84c:	00 
  40c84d:	48 89 94 24 18 01 00 	mov    %rdx,0x118(%rsp)
  40c854:	00 
  40c855:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40c85c:	00 
  40c85d:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40c864:	00 
  40c865:	4c 89 ff             	mov    %r15,%rdi
  40c868:	4c 89 bc 24 e0 02 00 	mov    %r15,0x2e0(%rsp)
  40c86f:	00 
  40c870:	48 89 ac 24 10 01 00 	mov    %rbp,0x110(%rsp)
  40c877:	00 
  40c878:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40c87f:	00 
  40c880:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40c887:	00 
  40c888:	48 c7 c0 c8 27 43 00 	mov    $0x4327c8,%rax
  40c88f:	4c 89 c3             	mov    %r8,%rbx
  40c892:	4c 89 84 24 e8 02 00 	mov    %r8,0x2e8(%rsp)
  40c899:	00 
  40c89a:	4c 89 9c 24 58 03 00 	mov    %r11,0x358(%rsp)
  40c8a1:	00 
  40c8a2:	49 89 d7             	mov    %rdx,%r15
  40c8a5:	4d 89 f4             	mov    %r14,%r12
  40c8a8:	4c 89 b4 24 f0 02 00 	mov    %r14,0x2f0(%rsp)
  40c8af:	00 
  40c8b0:	4c 8b 30             	mov    (%rax),%r14
  40c8b3:	4c 89 b4 24 b8 02 00 	mov    %r14,0x2b8(%rsp)
  40c8ba:	00 
  40c8bb:	48 8d 84 24 b8 02 00 	lea    0x2b8(%rsp),%rax
  40c8c2:	00 
  40c8c3:	48 89 84 24 a8 02 00 	mov    %rax,0x2a8(%rsp)
  40c8ca:	00 
  40c8cb:	48 c7 c0 d0 1e 43 00 	mov    $0x431ed0,%rax
  40c8d2:	48 89 84 24 b0 02 00 	mov    %rax,0x2b0(%rsp)
  40c8d9:	00 
  40c8da:	e8 91 ec 00 00       	call   41b570 <myl_qbe_heap>
  40c8df:	49 8b 37             	mov    (%r15),%rsi
  40c8e2:	4d 8b 06             	mov    (%r14),%r8
  40c8e5:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40c8e9:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40c8f0:	00 
  40c8f1:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40c8f8:	00 
  40c8f9:	4c 89 bc 24 58 02 00 	mov    %r15,0x258(%rsp)
  40c900:	00 
  40c901:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40c908:	00 
  40c909:	48 89 ac 24 50 02 00 	mov    %rbp,0x250(%rsp)
  40c910:	00 
  40c911:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40c918:	00 
  40c919:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40c920:	00 
  40c921:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40c928:	00 
  40c929:	4c 89 b4 24 78 02 00 	mov    %r14,0x278(%rsp)
  40c930:	00 
  40c931:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40c938:	00 
  40c939:	48 c7 c2 d0 1e 43 00 	mov    $0x431ed0,%rdx
  40c940:	48 89 94 24 70 02 00 	mov    %rdx,0x270(%rsp)
  40c947:	00 
  40c948:	48 8d 8c 24 60 02 00 	lea    0x260(%rsp),%rcx
  40c94f:	00 
  40c950:	48 89 8c 24 80 02 00 	mov    %rcx,0x280(%rsp)
  40c957:	00 
  40c958:	48 8d 8c 24 98 02 00 	lea    0x298(%rsp),%rcx
  40c95f:	00 
  40c960:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40c967:	00 
  40c968:	48 89 8c 24 88 02 00 	mov    %rcx,0x288(%rsp)
  40c96f:	00 
  40c970:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40c977:	48 89 8c 24 90 02 00 	mov    %rcx,0x290(%rsp)
  40c97e:	00 
  40c97f:	48 8d 8c 24 80 02 00 	lea    0x280(%rsp),%rcx
  40c986:	00 
  40c987:	48 89 8c 24 c0 02 00 	mov    %rcx,0x2c0(%rsp)
  40c98e:	00 
  40c98f:	48 8d 8c 24 d8 02 00 	lea    0x2d8(%rsp),%rcx
  40c996:	00 
  40c997:	4c 89 b4 24 d8 02 00 	mov    %r14,0x2d8(%rsp)
  40c99e:	00 
  40c99f:	48 89 8c 24 c8 02 00 	mov    %rcx,0x2c8(%rsp)
  40c9a6:	00 
  40c9a7:	48 89 94 24 d0 02 00 	mov    %rdx,0x2d0(%rsp)
  40c9ae:	00 
  40c9af:	48 89 c7             	mov    %rax,%rdi
  40c9b2:	4c 89 f2             	mov    %r14,%rdx
  40c9b5:	31 c9                	xor    %ecx,%ecx
  40c9b7:	e8 04 42 01 00       	call   420bc0 <myl_native_bytes_buffer_append_range>
  40c9bc:	48 8b 43 10          	mov    0x10(%rbx),%rax
  40c9c0:	48 89 04 24          	mov    %rax,(%rsp)
  40c9c4:	4c 89 7c 24 18       	mov    %r15,0x18(%rsp)
  40c9c9:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40c9ce:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40c9d3:	48 89 6c 24 10       	mov    %rbp,0x10(%rsp)
  40c9d8:	49 89 ee             	mov    %rbp,%r14
  40c9db:	48 89 e0             	mov    %rsp,%rax
  40c9de:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40c9e5:	00 
  40c9e6:	4c 89 a4 24 28 01 00 	mov    %r12,0x128(%rsp)
  40c9ed:	00 
  40c9ee:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40c9f5:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40c9fc:	00 
  40c9fd:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40ca04:	00 
  40ca05:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40ca0c:	00 
  40ca0d:	48 8b ac 24 58 03 00 	mov    0x358(%rsp),%rbp
  40ca14:	00 
  40ca15:	48 89 ac 24 28 02 00 	mov    %rbp,0x228(%rsp)
  40ca1c:	00 
  40ca1d:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40ca24:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40ca2b:	00 
  40ca2c:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40ca33:	00 
  40ca34:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40ca3b:	00 
  40ca3c:	48 c7 84 24 f8 00 00 	movq   $0x0,0xf8(%rsp)
  40ca43:	00 00 00 00 00 
  40ca48:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40ca4f:	00 
  40ca50:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40ca57:	00 
  40ca58:	4c 89 ac 24 f0 00 00 	mov    %r13,0xf0(%rsp)
  40ca5f:	00 
  40ca60:	48 8d 84 24 e0 00 00 	lea    0xe0(%rsp),%rax
  40ca67:	00 
  40ca68:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  40ca6f:	00 
  40ca70:	48 c7 84 24 d8 00 00 	movq   $0x0,0xd8(%rsp)
  40ca77:	00 00 00 00 00 
  40ca7c:	48 8d 84 24 d8 00 00 	lea    0xd8(%rsp),%rax
  40ca83:	00 
  40ca84:	48 89 84 24 c8 00 00 	mov    %rax,0xc8(%rsp)
  40ca8b:	00 
  40ca8c:	4c 89 ac 24 d0 00 00 	mov    %r13,0xd0(%rsp)
  40ca93:	00 
  40ca94:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  40ca9b:	00 
  40ca9c:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  40caa3:	00 
  40caa4:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40caab:	00 00 00 00 00 
  40cab0:	48 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%rax
  40cab7:	00 
  40cab8:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  40cabf:	00 
  40cac0:	4c 89 ac 24 b0 00 00 	mov    %r13,0xb0(%rsp)
  40cac7:	00 
  40cac8:	48 8d 84 24 a0 00 00 	lea    0xa0(%rsp),%rax
  40cacf:	00 
  40cad0:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  40cad7:	00 
  40cad8:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40cadf:	00 00 00 00 00 
  40cae4:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  40caeb:	00 
  40caec:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  40caf3:	00 
  40caf4:	4c 89 ac 24 90 00 00 	mov    %r13,0x90(%rsp)
  40cafb:	00 
  40cafc:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  40cb03:	00 
  40cb04:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40cb09:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40cb10:	00 00 
  40cb12:	48 8d 44 24 78       	lea    0x78(%rsp),%rax
  40cb17:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  40cb1c:	4c 89 6c 24 70       	mov    %r13,0x70(%rsp)
  40cb21:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40cb26:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40cb2b:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40cb32:	00 00 
  40cb34:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  40cb39:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40cb3e:	4c 89 6c 24 50       	mov    %r13,0x50(%rsp)
  40cb43:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40cb48:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40cb4d:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40cb54:	00 00 
  40cb56:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40cb5b:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40cb60:	4c 89 6c 24 30       	mov    %r13,0x30(%rsp)
  40cb65:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40cb6a:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40cb71:	00 
  40cb72:	48 89 ac 24 08 02 00 	mov    %rbp,0x208(%rsp)
  40cb79:	00 
  40cb7a:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40cb81:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40cb88:	00 
  40cb89:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40cb90:	00 
  40cb91:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40cb98:	00 
  40cb99:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40cba0:	00 
  40cba1:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40cba8:	00 
  40cba9:	49 c7 c5 70 24 43 00 	mov    $0x432470,%r13
  40cbb0:	4c 89 ac 24 f0 01 00 	mov    %r13,0x1f0(%rsp)
  40cbb7:	00 
  40cbb8:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40cbbf:	00 
  40cbc0:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40cbc7:	00 
  40cbc8:	48 89 ac 24 c8 01 00 	mov    %rbp,0x1c8(%rsp)
  40cbcf:	00 
  40cbd0:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40cbd7:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40cbde:	00 
  40cbdf:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40cbe6:	00 
  40cbe7:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40cbee:	00 
  40cbef:	48 8d 9c 24 00 03 00 	lea    0x300(%rsp),%rbx
  40cbf6:	00 
  40cbf7:	48 89 9c 24 a8 01 00 	mov    %rbx,0x1a8(%rsp)
  40cbfe:	00 
  40cbff:	4c 89 ac 24 b0 01 00 	mov    %r13,0x1b0(%rsp)
  40cc06:	00 
  40cc07:	48 8d 8c 24 a0 01 00 	lea    0x1a0(%rsp),%rcx
  40cc0e:	00 
  40cc0f:	48 89 8c 24 80 01 00 	mov    %rcx,0x180(%rsp)
  40cc16:	00 
  40cc17:	48 89 ac 24 88 01 00 	mov    %rbp,0x188(%rsp)
  40cc1e:	00 
  40cc1f:	48 c7 c1 30 25 43 00 	mov    $0x432530,%rcx
  40cc26:	48 89 8c 24 90 01 00 	mov    %rcx,0x190(%rsp)
  40cc2d:	00 
  40cc2e:	48 8d 8c 24 80 01 00 	lea    0x180(%rsp),%rcx
  40cc35:	00 
  40cc36:	48 89 8c 24 60 01 00 	mov    %rcx,0x160(%rsp)
  40cc3d:	00 
  40cc3e:	48 8d 8c 24 60 03 00 	lea    0x360(%rsp),%rcx
  40cc45:	00 
  40cc46:	48 89 8c 24 68 01 00 	mov    %rcx,0x168(%rsp)
  40cc4d:	00 
  40cc4e:	48 c7 c1 30 1f 43 00 	mov    $0x431f30,%rcx
  40cc55:	48 89 8c 24 70 01 00 	mov    %rcx,0x170(%rsp)
  40cc5c:	00 
  40cc5d:	48 8d 8c 24 60 01 00 	lea    0x160(%rsp),%rcx
  40cc64:	00 
  40cc65:	48 89 8c 24 40 01 00 	mov    %rcx,0x140(%rsp)
  40cc6c:	00 
  40cc6d:	48 8d 8c 24 40 03 00 	lea    0x340(%rsp),%rcx
  40cc74:	00 
  40cc75:	48 89 8c 24 48 01 00 	mov    %rcx,0x148(%rsp)
  40cc7c:	00 
  40cc7d:	4c 89 ac 24 50 01 00 	mov    %r13,0x150(%rsp)
  40cc84:	00 
  40cc85:	48 8d 8c 24 40 01 00 	lea    0x140(%rsp),%rcx
  40cc8c:	00 
  40cc8d:	48 89 8c 24 00 01 00 	mov    %rcx,0x100(%rsp)
  40cc94:	00 
  40cc95:	4c 89 bc 24 18 01 00 	mov    %r15,0x118(%rsp)
  40cc9c:	00 
  40cc9d:	48 8d 8c 24 18 01 00 	lea    0x118(%rsp),%rcx
  40cca4:	00 
  40cca5:	48 89 8c 24 08 01 00 	mov    %rcx,0x108(%rsp)
  40ccac:	00 
  40ccad:	4c 89 b4 24 10 01 00 	mov    %r14,0x110(%rsp)
  40ccb4:	00 
  40ccb5:	48 8d 8c 24 00 01 00 	lea    0x100(%rsp),%rcx
  40ccbc:	00 
  40ccbd:	48 89 8c 24 a0 02 00 	mov    %rcx,0x2a0(%rsp)
  40ccc4:	00 
  40ccc5:	48 89 9c 24 a8 02 00 	mov    %rbx,0x2a8(%rsp)
  40cccc:	00 
  40cccd:	4c 89 ac 24 b0 02 00 	mov    %r13,0x2b0(%rsp)
  40ccd4:	00 
  40ccd5:	4c 8b a4 24 e0 02 00 	mov    0x2e0(%rsp),%r12
  40ccdc:	00 
  40ccdd:	4c 89 e7             	mov    %r12,%rdi
  40cce0:	e8 8b e8 00 00       	call   41b570 <myl_qbe_heap>
  40cce5:	48 8b 40 10          	mov    0x10(%rax),%rax
  40cce9:	48 89 84 24 a8 03 00 	mov    %rax,0x3a8(%rsp)
  40ccf0:	00 
  40ccf1:	48 8d 84 24 c0 03 00 	lea    0x3c0(%rsp),%rax
  40ccf8:	00 
  40ccf9:	4c 89 bc 24 c0 03 00 	mov    %r15,0x3c0(%rsp)
  40cd00:	00 
  40cd01:	48 89 84 24 b0 03 00 	mov    %rax,0x3b0(%rsp)
  40cd08:	00 
  40cd09:	4c 89 f1             	mov    %r14,%rcx
  40cd0c:	4c 89 b4 24 b8 03 00 	mov    %r14,0x3b8(%rsp)
  40cd13:	00 
  40cd14:	4c 8b b4 24 00 03 00 	mov    0x300(%rsp),%r14
  40cd1b:	00 
  40cd1c:	48 8d 84 24 a8 03 00 	lea    0x3a8(%rsp),%rax
  40cd23:	00 
  40cd24:	48 89 84 24 f0 03 00 	mov    %rax,0x3f0(%rsp)
  40cd2b:	00 
  40cd2c:	48 89 9c 24 f8 03 00 	mov    %rbx,0x3f8(%rsp)
  40cd33:	00 
  40cd34:	4c 89 e7             	mov    %r12,%rdi
  40cd37:	48 8b 84 24 08 03 00 	mov    0x308(%rsp),%rax
  40cd3e:	00 
  40cd3f:	48 89 84 24 f8 02 00 	mov    %rax,0x2f8(%rsp)
  40cd46:	00 
  40cd47:	4c 89 ac 24 00 04 00 	mov    %r13,0x400(%rsp)
  40cd4e:	00 
  40cd4f:	48 8d 84 24 f0 03 00 	lea    0x3f0(%rsp),%rax
  40cd56:	00 
  40cd57:	48 89 84 24 88 03 00 	mov    %rax,0x388(%rsp)
  40cd5e:	00 
  40cd5f:	4c 8b ac 24 10 03 00 	mov    0x310(%rsp),%r13
  40cd66:	00 
  40cd67:	48 8d 84 24 a0 03 00 	lea    0x3a0(%rsp),%rax
  40cd6e:	00 
  40cd6f:	4c 89 bc 24 a0 03 00 	mov    %r15,0x3a0(%rsp)
  40cd76:	00 
  40cd77:	48 89 84 24 90 03 00 	mov    %rax,0x390(%rsp)
  40cd7e:	00 
  40cd7f:	48 89 8c 24 98 03 00 	mov    %rcx,0x398(%rsp)
  40cd86:	00 
  40cd87:	48 89 cb             	mov    %rcx,%rbx
  40cd8a:	48 8d 84 24 88 03 00 	lea    0x388(%rsp),%rax
  40cd91:	00 
  40cd92:	48 89 84 24 c8 03 00 	mov    %rax,0x3c8(%rsp)
  40cd99:	00 
  40cd9a:	48 8d 84 24 e0 03 00 	lea    0x3e0(%rsp),%rax
  40cda1:	00 
  40cda2:	4c 89 b4 24 e0 03 00 	mov    %r14,0x3e0(%rsp)
  40cda9:	00 
  40cdaa:	48 89 84 24 d0 03 00 	mov    %rax,0x3d0(%rsp)
  40cdb1:	00 
  40cdb2:	49 c7 c4 d0 1e 43 00 	mov    $0x431ed0,%r12
  40cdb9:	4c 89 a4 24 d8 03 00 	mov    %r12,0x3d8(%rsp)
  40cdc0:	00 
  40cdc1:	e8 aa e7 00 00       	call   41b570 <myl_qbe_heap>
  40cdc6:	49 8b 37             	mov    (%r15),%rsi
  40cdc9:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40cdcd:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40cdd4:	00 
  40cdd5:	4c 89 bc 24 58 02 00 	mov    %r15,0x258(%rsp)
  40cddc:	00 
  40cddd:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40cde4:	00 
  40cde5:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40cdec:	00 
  40cded:	48 89 9c 24 50 02 00 	mov    %rbx,0x250(%rsp)
  40cdf4:	00 
  40cdf5:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40cdfc:	00 
  40cdfd:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40ce04:	00 
  40ce05:	4c 89 b4 24 78 02 00 	mov    %r14,0x278(%rsp)
  40ce0c:	00 
  40ce0d:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40ce14:	00 
  40ce15:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40ce1c:	00 
  40ce1d:	4c 89 a4 24 70 02 00 	mov    %r12,0x270(%rsp)
  40ce24:	00 
  40ce25:	48 8d 94 24 60 02 00 	lea    0x260(%rsp),%rdx
  40ce2c:	00 
  40ce2d:	48 89 94 24 80 02 00 	mov    %rdx,0x280(%rsp)
  40ce34:	00 
  40ce35:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40ce3c:	00 
  40ce3d:	48 8d 94 24 98 02 00 	lea    0x298(%rsp),%rdx
  40ce44:	00 
  40ce45:	48 89 94 24 88 02 00 	mov    %rdx,0x288(%rsp)
  40ce4c:	00 
  40ce4d:	48 c7 c2 f0 1c 43 00 	mov    $0x431cf0,%rdx
  40ce54:	48 89 94 24 90 02 00 	mov    %rdx,0x290(%rsp)
  40ce5b:	00 
  40ce5c:	48 8d 94 24 80 02 00 	lea    0x280(%rsp),%rdx
  40ce63:	00 
  40ce64:	48 89 94 24 c0 02 00 	mov    %rdx,0x2c0(%rsp)
  40ce6b:	00 
  40ce6c:	4c 89 b4 24 d8 02 00 	mov    %r14,0x2d8(%rsp)
  40ce73:	00 
  40ce74:	48 8d 94 24 d8 02 00 	lea    0x2d8(%rsp),%rdx
  40ce7b:	00 
  40ce7c:	48 89 94 24 c8 02 00 	mov    %rdx,0x2c8(%rsp)
  40ce83:	00 
  40ce84:	4c 89 a4 24 d0 02 00 	mov    %r12,0x2d0(%rsp)
  40ce8b:	00 
  40ce8c:	48 89 c7             	mov    %rax,%rdi
  40ce8f:	4c 89 f2             	mov    %r14,%rdx
  40ce92:	48 8b 8c 24 f8 02 00 	mov    0x2f8(%rsp),%rcx
  40ce99:	00 
  40ce9a:	4d 89 e8             	mov    %r13,%r8
  40ce9d:	e8 1e 3d 01 00       	call   420bc0 <myl_native_bytes_buffer_append_range>
  40cea2:	48 8b 84 24 e8 02 00 	mov    0x2e8(%rsp),%rax
  40cea9:	00 
  40ceaa:	48 8b 40 10          	mov    0x10(%rax),%rax
  40ceae:	48 89 04 24          	mov    %rax,(%rsp)
  40ceb2:	4c 89 7c 24 18       	mov    %r15,0x18(%rsp)
  40ceb7:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40cebc:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40cec1:	48 89 e0             	mov    %rsp,%rax
  40cec4:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40cecb:	00 
  40cecc:	48 8b 84 24 f0 02 00 	mov    0x2f0(%rsp),%rax
  40ced3:	00 
  40ced4:	48 89 84 24 28 01 00 	mov    %rax,0x128(%rsp)
  40cedb:	00 
  40cedc:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40cee3:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40ceea:	00 
  40ceeb:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40cef2:	00 
  40cef3:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40cefa:	00 
  40cefb:	48 89 ac 24 28 02 00 	mov    %rbp,0x228(%rsp)
  40cf02:	00 
  40cf03:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40cf0a:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40cf11:	00 
  40cf12:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40cf19:	00 
  40cf1a:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40cf21:	00 
  40cf22:	48 c7 84 24 f8 00 00 	movq   $0x0,0xf8(%rsp)
  40cf29:	00 00 00 00 00 
  40cf2e:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40cf35:	00 
  40cf36:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40cf3d:	00 
  40cf3e:	48 8d 84 24 e0 00 00 	lea    0xe0(%rsp),%rax
  40cf45:	00 
  40cf46:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  40cf4d:	00 
  40cf4e:	48 c7 84 24 d8 00 00 	movq   $0x0,0xd8(%rsp)
  40cf55:	00 00 00 00 00 
  40cf5a:	48 8d 84 24 d8 00 00 	lea    0xd8(%rsp),%rax
  40cf61:	00 
  40cf62:	48 89 84 24 c8 00 00 	mov    %rax,0xc8(%rsp)
  40cf69:	00 
  40cf6a:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  40cf71:	00 
  40cf72:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  40cf79:	00 
  40cf7a:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40cf81:	00 00 00 00 00 
  40cf86:	48 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%rax
  40cf8d:	00 
  40cf8e:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  40cf95:	00 
  40cf96:	48 8d 84 24 a0 00 00 	lea    0xa0(%rsp),%rax
  40cf9d:	00 
  40cf9e:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  40cfa5:	00 
  40cfa6:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40cfad:	00 00 00 00 00 
  40cfb2:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  40cfb9:	00 
  40cfba:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  40cfc1:	00 
  40cfc2:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  40cfc9:	00 
  40cfca:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40cfcf:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40cfd6:	00 00 
  40cfd8:	48 8d 44 24 78       	lea    0x78(%rsp),%rax
  40cfdd:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  40cfe2:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40cfe7:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40cfec:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40cff3:	00 00 
  40cff5:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  40cffa:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40cfff:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40d004:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40d009:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40d010:	00 00 
  40d012:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40d017:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40d01c:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40d023:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40d02a:	00 
  40d02b:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40d032:	00 
  40d033:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40d03a:	00 
  40d03b:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40d042:	00 
  40d043:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40d048:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40d04d:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40d052:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40d057:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40d05e:	00 
  40d05f:	48 89 ac 24 08 02 00 	mov    %rbp,0x208(%rsp)
  40d066:	00 
  40d067:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40d06e:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40d075:	00 
  40d076:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40d07d:	00 
  40d07e:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40d085:	00 
  40d086:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40d08d:	00 
  40d08e:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40d095:	00 
  40d096:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40d09d:	00 
  40d09e:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40d0a5:	00 
  40d0a6:	48 89 ac 24 c8 01 00 	mov    %rbp,0x1c8(%rsp)
  40d0ad:	00 
  40d0ae:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40d0b5:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40d0bc:	00 
  40d0bd:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40d0c4:	00 
  40d0c5:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40d0cc:	00 
  40d0cd:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40d0d4:	00 
  40d0d5:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40d0dc:	00 
  40d0dd:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40d0e4:	00 
  40d0e5:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40d0ec:	00 
  40d0ed:	48 89 ac 24 88 01 00 	mov    %rbp,0x188(%rsp)
  40d0f4:	00 
  40d0f5:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40d0fc:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40d103:	00 
  40d104:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40d10b:	00 
  40d10c:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40d113:	00 
  40d114:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40d11b:	00 
  40d11c:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40d123:	00 
  40d124:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40d12b:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40d132:	00 
  40d133:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40d13a:	00 
  40d13b:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40d142:	00 
  40d143:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40d14a:	00 
  40d14b:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40d152:	00 
  40d153:	48 c7 c0 70 24 43 00 	mov    $0x432470,%rax
  40d15a:	48 89 84 24 f0 01 00 	mov    %rax,0x1f0(%rsp)
  40d161:	00 
  40d162:	48 89 84 24 b0 01 00 	mov    %rax,0x1b0(%rsp)
  40d169:	00 
  40d16a:	48 89 84 24 50 01 00 	mov    %rax,0x150(%rsp)
  40d171:	00 
  40d172:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40d179:	00 
  40d17a:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40d181:	00 
  40d182:	4c 89 bc 24 18 01 00 	mov    %r15,0x118(%rsp)
  40d189:	00 
  40d18a:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40d191:	00 
  40d192:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40d199:	00 
  40d19a:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40d1a1:	00 
  40d1a2:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40d1a9:	00 
  40d1aa:	48 c7 c0 c8 27 43 00 	mov    $0x4327c8,%rax
  40d1b1:	4c 8b 30             	mov    (%rax),%r14
  40d1b4:	4c 89 b4 24 b8 02 00 	mov    %r14,0x2b8(%rsp)
  40d1bb:	00 
  40d1bc:	48 8d 84 24 b8 02 00 	lea    0x2b8(%rsp),%rax
  40d1c3:	00 
  40d1c4:	48 89 84 24 a8 02 00 	mov    %rax,0x2a8(%rsp)
  40d1cb:	00 
  40d1cc:	48 89 5c 24 10       	mov    %rbx,0x10(%rsp)
  40d1d1:	48 89 9c 24 10 01 00 	mov    %rbx,0x110(%rsp)
  40d1d8:	00 
  40d1d9:	4c 89 a4 24 b0 02 00 	mov    %r12,0x2b0(%rsp)
  40d1e0:	00 
  40d1e1:	48 8b bc 24 e0 02 00 	mov    0x2e0(%rsp),%rdi
  40d1e8:	00 
  40d1e9:	e8 82 e3 00 00       	call   41b570 <myl_qbe_heap>
  40d1ee:	49 8b 37             	mov    (%r15),%rsi
  40d1f1:	4d 8b 06             	mov    (%r14),%r8
  40d1f4:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40d1f8:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40d1ff:	00 
  40d200:	4c 89 bc 24 58 02 00 	mov    %r15,0x258(%rsp)
  40d207:	00 
  40d208:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40d20f:	00 
  40d210:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40d217:	00 
  40d218:	48 89 9c 24 50 02 00 	mov    %rbx,0x250(%rsp)
  40d21f:	00 
  40d220:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40d227:	00 
  40d228:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40d22f:	00 
  40d230:	4c 89 b4 24 78 02 00 	mov    %r14,0x278(%rsp)
  40d237:	00 
  40d238:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40d23f:	00 
  40d240:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40d247:	00 
  40d248:	48 8d 8c 24 60 02 00 	lea    0x260(%rsp),%rcx
  40d24f:	00 
  40d250:	48 89 8c 24 80 02 00 	mov    %rcx,0x280(%rsp)
  40d257:	00 
  40d258:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40d25f:	00 
  40d260:	48 8d 8c 24 98 02 00 	lea    0x298(%rsp),%rcx
  40d267:	00 
  40d268:	48 89 8c 24 88 02 00 	mov    %rcx,0x288(%rsp)
  40d26f:	00 
  40d270:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40d277:	48 89 8c 24 90 02 00 	mov    %rcx,0x290(%rsp)
  40d27e:	00 
  40d27f:	48 8d 8c 24 80 02 00 	lea    0x280(%rsp),%rcx
  40d286:	00 
  40d287:	48 89 8c 24 c0 02 00 	mov    %rcx,0x2c0(%rsp)
  40d28e:	00 
  40d28f:	4c 89 b4 24 d8 02 00 	mov    %r14,0x2d8(%rsp)
  40d296:	00 
  40d297:	48 8d 8c 24 d8 02 00 	lea    0x2d8(%rsp),%rcx
  40d29e:	00 
  40d29f:	48 89 8c 24 c8 02 00 	mov    %rcx,0x2c8(%rsp)
  40d2a6:	00 
  40d2a7:	4c 89 a4 24 70 02 00 	mov    %r12,0x270(%rsp)
  40d2ae:	00 
  40d2af:	4c 89 a4 24 d0 02 00 	mov    %r12,0x2d0(%rsp)
  40d2b6:	00 
  40d2b7:	e9 14 2a 00 00       	jmp    40fcd0 <sexpr.printer::push_node+0x4b90>
  40d2bc:	4c 89 f1             	mov    %r14,%rcx
  40d2bf:	4d 8b 76 08          	mov    0x8(%r14),%r14
  40d2c3:	49 8b 40 10          	mov    0x10(%r8),%rax
  40d2c7:	48 89 04 24          	mov    %rax,(%rsp)
  40d2cb:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40d2d0:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40d2d5:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40d2da:	48 c7 c3 60 84 42 00 	mov    $0x428460,%rbx
  40d2e1:	48 89 5c 24 10       	mov    %rbx,0x10(%rsp)
  40d2e6:	48 89 e0             	mov    %rsp,%rax
  40d2e9:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40d2f0:	00 
  40d2f1:	48 89 8c 24 28 01 00 	mov    %rcx,0x128(%rsp)
  40d2f8:	00 
  40d2f9:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40d300:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40d307:	00 
  40d308:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40d30f:	00 
  40d310:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40d317:	00 
  40d318:	4c 89 9c 24 28 02 00 	mov    %r11,0x228(%rsp)
  40d31f:	00 
  40d320:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40d327:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40d32e:	00 
  40d32f:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40d336:	00 
  40d337:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40d33e:	00 
  40d33f:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40d346:	00 
  40d347:	48 c7 84 24 f8 00 00 	movq   $0x0,0xf8(%rsp)
  40d34e:	00 00 00 00 00 
  40d353:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40d35a:	00 
  40d35b:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40d362:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40d369:	00 
  40d36a:	48 8d 8c 24 e0 00 00 	lea    0xe0(%rsp),%rcx
  40d371:	00 
  40d372:	48 89 8c 24 c0 00 00 	mov    %rcx,0xc0(%rsp)
  40d379:	00 
  40d37a:	48 8d 8c 24 d8 00 00 	lea    0xd8(%rsp),%rcx
  40d381:	00 
  40d382:	48 c7 84 24 d8 00 00 	movq   $0x0,0xd8(%rsp)
  40d389:	00 00 00 00 00 
  40d38e:	48 89 8c 24 c8 00 00 	mov    %rcx,0xc8(%rsp)
  40d395:	00 
  40d396:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40d39d:	00 
  40d39e:	48 8d 8c 24 c0 00 00 	lea    0xc0(%rsp),%rcx
  40d3a5:	00 
  40d3a6:	48 89 8c 24 a0 00 00 	mov    %rcx,0xa0(%rsp)
  40d3ad:	00 
  40d3ae:	48 8d 8c 24 b8 00 00 	lea    0xb8(%rsp),%rcx
  40d3b5:	00 
  40d3b6:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40d3bd:	00 00 00 00 00 
  40d3c2:	48 89 8c 24 a8 00 00 	mov    %rcx,0xa8(%rsp)
  40d3c9:	00 
  40d3ca:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40d3d1:	00 
  40d3d2:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  40d3d9:	00 
  40d3da:	48 89 8c 24 80 00 00 	mov    %rcx,0x80(%rsp)
  40d3e1:	00 
  40d3e2:	48 8d 8c 24 98 00 00 	lea    0x98(%rsp),%rcx
  40d3e9:	00 
  40d3ea:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40d3f1:	00 00 00 00 00 
  40d3f6:	48 89 8c 24 88 00 00 	mov    %rcx,0x88(%rsp)
  40d3fd:	00 
  40d3fe:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40d405:	00 
  40d406:	48 8d 8c 24 80 00 00 	lea    0x80(%rsp),%rcx
  40d40d:	00 
  40d40e:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
  40d413:	48 8d 4c 24 78       	lea    0x78(%rsp),%rcx
  40d418:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40d41f:	00 00 
  40d421:	48 89 4c 24 68       	mov    %rcx,0x68(%rsp)
  40d426:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40d42b:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  40d430:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  40d435:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  40d43a:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40d441:	00 00 
  40d443:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  40d448:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40d44d:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  40d452:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  40d457:	48 8d 4c 24 38       	lea    0x38(%rsp),%rcx
  40d45c:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40d463:	00 00 
  40d465:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
  40d46a:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40d46f:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40d474:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40d47b:	00 
  40d47c:	4c 89 9c 24 08 02 00 	mov    %r11,0x208(%rsp)
  40d483:	00 
  40d484:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40d48b:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40d492:	00 
  40d493:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40d49a:	00 
  40d49b:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40d4a2:	00 
  40d4a3:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40d4aa:	00 
  40d4ab:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40d4b2:	00 
  40d4b3:	48 c7 c0 70 24 43 00 	mov    $0x432470,%rax
  40d4ba:	48 89 84 24 f0 01 00 	mov    %rax,0x1f0(%rsp)
  40d4c1:	00 
  40d4c2:	48 8d 8c 24 e0 01 00 	lea    0x1e0(%rsp),%rcx
  40d4c9:	00 
  40d4ca:	48 89 8c 24 c0 01 00 	mov    %rcx,0x1c0(%rsp)
  40d4d1:	00 
  40d4d2:	4c 89 9c 24 c8 01 00 	mov    %r11,0x1c8(%rsp)
  40d4d9:	00 
  40d4da:	48 c7 c1 90 22 43 00 	mov    $0x432290,%rcx
  40d4e1:	48 89 8c 24 d0 01 00 	mov    %rcx,0x1d0(%rsp)
  40d4e8:	00 
  40d4e9:	48 8d 8c 24 c0 01 00 	lea    0x1c0(%rsp),%rcx
  40d4f0:	00 
  40d4f1:	48 89 8c 24 a0 01 00 	mov    %rcx,0x1a0(%rsp)
  40d4f8:	00 
  40d4f9:	48 8d 8c 24 00 03 00 	lea    0x300(%rsp),%rcx
  40d500:	00 
  40d501:	48 89 8c 24 a8 01 00 	mov    %rcx,0x1a8(%rsp)
  40d508:	00 
  40d509:	48 89 84 24 b0 01 00 	mov    %rax,0x1b0(%rsp)
  40d510:	00 
  40d511:	48 8d 8c 24 a0 01 00 	lea    0x1a0(%rsp),%rcx
  40d518:	00 
  40d519:	48 89 8c 24 80 01 00 	mov    %rcx,0x180(%rsp)
  40d520:	00 
  40d521:	4c 89 9c 24 88 01 00 	mov    %r11,0x188(%rsp)
  40d528:	00 
  40d529:	48 c7 c1 30 25 43 00 	mov    $0x432530,%rcx
  40d530:	48 89 8c 24 90 01 00 	mov    %rcx,0x190(%rsp)
  40d537:	00 
  40d538:	48 8d 8c 24 80 01 00 	lea    0x180(%rsp),%rcx
  40d53f:	00 
  40d540:	48 89 8c 24 60 01 00 	mov    %rcx,0x160(%rsp)
  40d547:	00 
  40d548:	48 8d 8c 24 60 03 00 	lea    0x360(%rsp),%rcx
  40d54f:	00 
  40d550:	48 89 8c 24 68 01 00 	mov    %rcx,0x168(%rsp)
  40d557:	00 
  40d558:	48 c7 c1 30 1f 43 00 	mov    $0x431f30,%rcx
  40d55f:	48 89 8c 24 70 01 00 	mov    %rcx,0x170(%rsp)
  40d566:	00 
  40d567:	48 8d 8c 24 60 01 00 	lea    0x160(%rsp),%rcx
  40d56e:	00 
  40d56f:	48 89 8c 24 40 01 00 	mov    %rcx,0x140(%rsp)
  40d576:	00 
  40d577:	48 8d 8c 24 40 03 00 	lea    0x340(%rsp),%rcx
  40d57e:	00 
  40d57f:	48 89 8c 24 48 01 00 	mov    %rcx,0x148(%rsp)
  40d586:	00 
  40d587:	48 89 84 24 50 01 00 	mov    %rax,0x150(%rsp)
  40d58e:	00 
  40d58f:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40d596:	00 
  40d597:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40d59e:	00 
  40d59f:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40d5a6:	00 
  40d5a7:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40d5ae:	00 
  40d5af:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40d5b6:	00 
  40d5b7:	48 89 9c 24 10 01 00 	mov    %rbx,0x110(%rsp)
  40d5be:	00 
  40d5bf:	4c 89 ff             	mov    %r15,%rdi
  40d5c2:	e8 a9 df 00 00       	call   41b570 <myl_qbe_heap>
  40d5c7:	49 8b 75 00          	mov    0x0(%r13),%rsi
  40d5cb:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40d5cf:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40d5d6:	00 
  40d5d7:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40d5de:	00 
  40d5df:	4c 89 ac 24 58 02 00 	mov    %r13,0x258(%rsp)
  40d5e6:	00 
  40d5e7:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40d5ee:	00 
  40d5ef:	48 89 9c 24 50 02 00 	mov    %rbx,0x250(%rsp)
  40d5f6:	00 
  40d5f7:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40d5fe:	00 
  40d5ff:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40d606:	00 
  40d607:	48 89 b4 24 78 02 00 	mov    %rsi,0x278(%rsp)
  40d60e:	00 
  40d60f:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40d616:	00 
  40d617:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40d61e:	00 
  40d61f:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40d626:	48 89 8c 24 70 02 00 	mov    %rcx,0x270(%rsp)
  40d62d:	00 
  40d62e:	48 89 c7             	mov    %rax,%rdi
  40d631:	4c 89 f2             	mov    %r14,%rdx
  40d634:	e8 17 37 01 00       	call   420d50 <myl_native_bytes_buffer_append_int>
  40d639:	e9 9f 26 00 00       	jmp    40fcdd <sexpr.printer::push_node+0x4b9d>
  40d63e:	c4 c1 78 10 03       	vmovups (%r11),%xmm0
  40d643:	49 8b 43 10          	mov    0x10(%r11),%rax
  40d647:	48 89 84 24 30 03 00 	mov    %rax,0x330(%rsp)
  40d64e:	00 
  40d64f:	c5 f8 29 84 24 20 03 	vmovaps %xmm0,0x320(%rsp)
  40d656:	00 00 
  40d658:	49 8b 40 10          	mov    0x10(%r8),%rax
  40d65c:	48 89 04 24          	mov    %rax,(%rsp)
  40d660:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40d665:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40d66a:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40d66f:	48 c7 c3 60 84 42 00 	mov    $0x428460,%rbx
  40d676:	48 89 5c 24 10       	mov    %rbx,0x10(%rsp)
  40d67b:	48 89 e0             	mov    %rsp,%rax
  40d67e:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40d685:	00 
  40d686:	4c 89 b4 24 28 01 00 	mov    %r14,0x128(%rsp)
  40d68d:	00 
  40d68e:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40d695:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40d69c:	00 
  40d69d:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40d6a4:	00 
  40d6a5:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40d6ac:	00 
  40d6ad:	4c 89 9c 24 28 02 00 	mov    %r11,0x228(%rsp)
  40d6b4:	00 
  40d6b5:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40d6bc:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40d6c3:	00 
  40d6c4:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40d6cb:	00 
  40d6cc:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40d6d3:	00 
  40d6d4:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40d6db:	00 
  40d6dc:	48 c7 84 24 f8 00 00 	movq   $0x0,0xf8(%rsp)
  40d6e3:	00 00 00 00 00 
  40d6e8:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40d6ef:	00 
  40d6f0:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40d6f7:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40d6fe:	00 
  40d6ff:	48 8d 8c 24 e0 00 00 	lea    0xe0(%rsp),%rcx
  40d706:	00 
  40d707:	48 89 8c 24 c0 00 00 	mov    %rcx,0xc0(%rsp)
  40d70e:	00 
  40d70f:	48 8d 8c 24 d8 00 00 	lea    0xd8(%rsp),%rcx
  40d716:	00 
  40d717:	48 c7 84 24 d8 00 00 	movq   $0x0,0xd8(%rsp)
  40d71e:	00 00 00 00 00 
  40d723:	48 89 8c 24 c8 00 00 	mov    %rcx,0xc8(%rsp)
  40d72a:	00 
  40d72b:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40d732:	00 
  40d733:	48 8d 8c 24 c0 00 00 	lea    0xc0(%rsp),%rcx
  40d73a:	00 
  40d73b:	48 89 8c 24 a0 00 00 	mov    %rcx,0xa0(%rsp)
  40d742:	00 
  40d743:	48 8d 8c 24 b8 00 00 	lea    0xb8(%rsp),%rcx
  40d74a:	00 
  40d74b:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40d752:	00 00 00 00 00 
  40d757:	48 89 8c 24 a8 00 00 	mov    %rcx,0xa8(%rsp)
  40d75e:	00 
  40d75f:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40d766:	00 
  40d767:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  40d76e:	00 
  40d76f:	48 89 8c 24 80 00 00 	mov    %rcx,0x80(%rsp)
  40d776:	00 
  40d777:	48 8d 8c 24 98 00 00 	lea    0x98(%rsp),%rcx
  40d77e:	00 
  40d77f:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40d786:	00 00 00 00 00 
  40d78b:	48 89 8c 24 88 00 00 	mov    %rcx,0x88(%rsp)
  40d792:	00 
  40d793:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40d79a:	00 
  40d79b:	48 8d 8c 24 80 00 00 	lea    0x80(%rsp),%rcx
  40d7a2:	00 
  40d7a3:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
  40d7a8:	48 8d 4c 24 78       	lea    0x78(%rsp),%rcx
  40d7ad:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40d7b4:	00 00 
  40d7b6:	48 89 4c 24 68       	mov    %rcx,0x68(%rsp)
  40d7bb:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40d7c0:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  40d7c5:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  40d7ca:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  40d7cf:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40d7d6:	00 00 
  40d7d8:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  40d7dd:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40d7e2:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  40d7e7:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  40d7ec:	48 8d 4c 24 38       	lea    0x38(%rsp),%rcx
  40d7f1:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40d7f8:	00 00 
  40d7fa:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
  40d7ff:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40d804:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40d809:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40d810:	00 
  40d811:	4c 89 9c 24 08 02 00 	mov    %r11,0x208(%rsp)
  40d818:	00 
  40d819:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40d820:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40d827:	00 
  40d828:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40d82f:	00 
  40d830:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40d837:	00 
  40d838:	4c 89 ed             	mov    %r13,%rbp
  40d83b:	4c 8d a4 24 20 03 00 	lea    0x320(%rsp),%r12
  40d842:	00 
  40d843:	4c 89 a4 24 e8 01 00 	mov    %r12,0x1e8(%rsp)
  40d84a:	00 
  40d84b:	49 c7 c5 70 24 43 00 	mov    $0x432470,%r13
  40d852:	4c 89 ac 24 f0 01 00 	mov    %r13,0x1f0(%rsp)
  40d859:	00 
  40d85a:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40d861:	00 
  40d862:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40d869:	00 
  40d86a:	4c 89 9c 24 c8 01 00 	mov    %r11,0x1c8(%rsp)
  40d871:	00 
  40d872:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40d879:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40d880:	00 
  40d881:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40d888:	00 
  40d889:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40d890:	00 
  40d891:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40d898:	00 
  40d899:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40d8a0:	00 
  40d8a1:	4c 89 ac 24 b0 01 00 	mov    %r13,0x1b0(%rsp)
  40d8a8:	00 
  40d8a9:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40d8b0:	00 
  40d8b1:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40d8b8:	00 
  40d8b9:	4c 89 9c 24 88 01 00 	mov    %r11,0x188(%rsp)
  40d8c0:	00 
  40d8c1:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40d8c8:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40d8cf:	00 
  40d8d0:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40d8d7:	00 
  40d8d8:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40d8df:	00 
  40d8e0:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40d8e7:	00 
  40d8e8:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40d8ef:	00 
  40d8f0:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40d8f7:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40d8fe:	00 
  40d8ff:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40d906:	00 
  40d907:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40d90e:	00 
  40d90f:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40d916:	00 
  40d917:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40d91e:	00 
  40d91f:	4c 89 ac 24 50 01 00 	mov    %r13,0x150(%rsp)
  40d926:	00 
  40d927:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40d92e:	00 
  40d92f:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40d936:	00 
  40d937:	48 89 ac 24 18 01 00 	mov    %rbp,0x118(%rsp)
  40d93e:	00 
  40d93f:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40d946:	00 
  40d947:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40d94e:	00 
  40d94f:	48 89 9c 24 10 01 00 	mov    %rbx,0x110(%rsp)
  40d956:	00 
  40d957:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40d95e:	00 
  40d95f:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40d966:	00 
  40d967:	4c 89 a4 24 a8 02 00 	mov    %r12,0x2a8(%rsp)
  40d96e:	00 
  40d96f:	4c 89 ac 24 b0 02 00 	mov    %r13,0x2b0(%rsp)
  40d976:	00 
  40d977:	4c 89 ff             	mov    %r15,%rdi
  40d97a:	e8 f1 db 00 00       	call   41b570 <myl_qbe_heap>
  40d97f:	4c 8b b4 24 20 03 00 	mov    0x320(%rsp),%r14
  40d986:	00 
  40d987:	48 8b 40 10          	mov    0x10(%rax),%rax
  40d98b:	48 89 84 24 a8 03 00 	mov    %rax,0x3a8(%rsp)
  40d992:	00 
  40d993:	48 8d 84 24 c0 03 00 	lea    0x3c0(%rsp),%rax
  40d99a:	00 
  40d99b:	48 89 ac 24 c0 03 00 	mov    %rbp,0x3c0(%rsp)
  40d9a2:	00 
  40d9a3:	48 89 84 24 b0 03 00 	mov    %rax,0x3b0(%rsp)
  40d9aa:	00 
  40d9ab:	48 89 9c 24 b8 03 00 	mov    %rbx,0x3b8(%rsp)
  40d9b2:	00 
  40d9b3:	4c 89 ff             	mov    %r15,%rdi
  40d9b6:	4c 8b bc 24 28 03 00 	mov    0x328(%rsp),%r15
  40d9bd:	00 
  40d9be:	48 8d 84 24 a8 03 00 	lea    0x3a8(%rsp),%rax
  40d9c5:	00 
  40d9c6:	48 89 84 24 f0 03 00 	mov    %rax,0x3f0(%rsp)
  40d9cd:	00 
  40d9ce:	4c 89 a4 24 f8 03 00 	mov    %r12,0x3f8(%rsp)
  40d9d5:	00 
  40d9d6:	4c 89 ac 24 00 04 00 	mov    %r13,0x400(%rsp)
  40d9dd:	00 
  40d9de:	48 8d 84 24 f0 03 00 	lea    0x3f0(%rsp),%rax
  40d9e5:	00 
  40d9e6:	48 89 84 24 88 03 00 	mov    %rax,0x388(%rsp)
  40d9ed:	00 
  40d9ee:	48 8d 84 24 a0 03 00 	lea    0x3a0(%rsp),%rax
  40d9f5:	00 
  40d9f6:	48 89 ac 24 a0 03 00 	mov    %rbp,0x3a0(%rsp)
  40d9fd:	00 
  40d9fe:	48 89 84 24 90 03 00 	mov    %rax,0x390(%rsp)
  40da05:	00 
  40da06:	48 89 9c 24 98 03 00 	mov    %rbx,0x398(%rsp)
  40da0d:	00 
  40da0e:	4c 8b a4 24 30 03 00 	mov    0x330(%rsp),%r12
  40da15:	00 
  40da16:	48 8d 84 24 88 03 00 	lea    0x388(%rsp),%rax
  40da1d:	00 
  40da1e:	48 89 84 24 c8 03 00 	mov    %rax,0x3c8(%rsp)
  40da25:	00 
  40da26:	4c 89 b4 24 e0 03 00 	mov    %r14,0x3e0(%rsp)
  40da2d:	00 
  40da2e:	48 8d 84 24 e0 03 00 	lea    0x3e0(%rsp),%rax
  40da35:	00 
  40da36:	48 89 84 24 d0 03 00 	mov    %rax,0x3d0(%rsp)
  40da3d:	00 
  40da3e:	49 c7 c5 d0 1e 43 00 	mov    $0x431ed0,%r13
  40da45:	4c 89 ac 24 d8 03 00 	mov    %r13,0x3d8(%rsp)
  40da4c:	00 
  40da4d:	e8 1e db 00 00       	call   41b570 <myl_qbe_heap>
  40da52:	48 8b 75 00          	mov    0x0(%rbp),%rsi
  40da56:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40da5a:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40da61:	00 
  40da62:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40da69:	00 
  40da6a:	48 89 ac 24 58 02 00 	mov    %rbp,0x258(%rsp)
  40da71:	00 
  40da72:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40da79:	00 
  40da7a:	48 89 9c 24 50 02 00 	mov    %rbx,0x250(%rsp)
  40da81:	00 
  40da82:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40da89:	00 
  40da8a:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40da91:	00 
  40da92:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40da99:	00 
  40da9a:	4c 89 b4 24 78 02 00 	mov    %r14,0x278(%rsp)
  40daa1:	00 
  40daa2:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40daa9:	00 
  40daaa:	4c 89 ac 24 70 02 00 	mov    %r13,0x270(%rsp)
  40dab1:	00 
  40dab2:	48 8d 8c 24 60 02 00 	lea    0x260(%rsp),%rcx
  40dab9:	00 
  40daba:	48 89 8c 24 80 02 00 	mov    %rcx,0x280(%rsp)
  40dac1:	00 
  40dac2:	48 8d 8c 24 98 02 00 	lea    0x298(%rsp),%rcx
  40dac9:	00 
  40daca:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40dad1:	00 
  40dad2:	48 89 8c 24 88 02 00 	mov    %rcx,0x288(%rsp)
  40dad9:	00 
  40dada:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40dae1:	48 89 8c 24 90 02 00 	mov    %rcx,0x290(%rsp)
  40dae8:	00 
  40dae9:	48 8d 8c 24 80 02 00 	lea    0x280(%rsp),%rcx
  40daf0:	00 
  40daf1:	48 89 8c 24 c0 02 00 	mov    %rcx,0x2c0(%rsp)
  40daf8:	00 
  40daf9:	48 8d 8c 24 d8 02 00 	lea    0x2d8(%rsp),%rcx
  40db00:	00 
  40db01:	4c 89 b4 24 d8 02 00 	mov    %r14,0x2d8(%rsp)
  40db08:	00 
  40db09:	48 89 8c 24 c8 02 00 	mov    %rcx,0x2c8(%rsp)
  40db10:	00 
  40db11:	4c 89 ac 24 d0 02 00 	mov    %r13,0x2d0(%rsp)
  40db18:	00 
  40db19:	48 89 c7             	mov    %rax,%rdi
  40db1c:	4c 89 f2             	mov    %r14,%rdx
  40db1f:	4c 89 f9             	mov    %r15,%rcx
  40db22:	4d 89 e0             	mov    %r12,%r8
  40db25:	e9 ae 21 00 00       	jmp    40fcd8 <sexpr.printer::push_node+0x4b98>
  40db2a:	49 8b 56 08          	mov    0x8(%r14),%rdx
  40db2e:	49 8b 40 10          	mov    0x10(%r8),%rax
  40db32:	48 89 04 24          	mov    %rax,(%rsp)
  40db36:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40db3b:	4c 89 e9             	mov    %r13,%rcx
  40db3e:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40db43:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40db48:	48 c7 c0 60 84 42 00 	mov    $0x428460,%rax
  40db4f:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  40db54:	48 89 e6             	mov    %rsp,%rsi
  40db57:	48 89 b4 24 20 01 00 	mov    %rsi,0x120(%rsp)
  40db5e:	00 
  40db5f:	4c 89 b4 24 28 01 00 	mov    %r14,0x128(%rsp)
  40db66:	00 
  40db67:	48 c7 c6 50 20 43 00 	mov    $0x432050,%rsi
  40db6e:	48 89 b4 24 30 01 00 	mov    %rsi,0x130(%rsp)
  40db75:	00 
  40db76:	48 8d b4 24 20 01 00 	lea    0x120(%rsp),%rsi
  40db7d:	00 
  40db7e:	48 89 b4 24 20 02 00 	mov    %rsi,0x220(%rsp)
  40db85:	00 
  40db86:	4c 89 9c 24 28 02 00 	mov    %r11,0x228(%rsp)
  40db8d:	00 
  40db8e:	48 c7 c6 b0 23 43 00 	mov    $0x4323b0,%rsi
  40db95:	48 89 b4 24 30 02 00 	mov    %rsi,0x230(%rsp)
  40db9c:	00 
  40db9d:	48 8d b4 24 20 02 00 	lea    0x220(%rsp),%rsi
  40dba4:	00 
  40dba5:	48 89 b4 24 e0 00 00 	mov    %rsi,0xe0(%rsp)
  40dbac:	00 
  40dbad:	48 8d b4 24 f8 00 00 	lea    0xf8(%rsp),%rsi
  40dbb4:	00 
  40dbb5:	48 c7 84 24 f8 00 00 	movq   $0x0,0xf8(%rsp)
  40dbbc:	00 00 00 00 00 
  40dbc1:	48 89 b4 24 e8 00 00 	mov    %rsi,0xe8(%rsp)
  40dbc8:	00 
  40dbc9:	4c 89 84 24 e8 02 00 	mov    %r8,0x2e8(%rsp)
  40dbd0:	00 
  40dbd1:	4c 89 db             	mov    %r11,%rbx
  40dbd4:	4c 89 b4 24 f0 02 00 	mov    %r14,0x2f0(%rsp)
  40dbdb:	00 
  40dbdc:	49 c7 c6 b0 20 43 00 	mov    $0x4320b0,%r14
  40dbe3:	4c 89 b4 24 f0 00 00 	mov    %r14,0xf0(%rsp)
  40dbea:	00 
  40dbeb:	48 8d b4 24 e0 00 00 	lea    0xe0(%rsp),%rsi
  40dbf2:	00 
  40dbf3:	48 89 b4 24 c0 00 00 	mov    %rsi,0xc0(%rsp)
  40dbfa:	00 
  40dbfb:	48 8d b4 24 d8 00 00 	lea    0xd8(%rsp),%rsi
  40dc02:	00 
  40dc03:	48 c7 84 24 d8 00 00 	movq   $0x0,0xd8(%rsp)
  40dc0a:	00 00 00 00 00 
  40dc0f:	48 89 b4 24 c8 00 00 	mov    %rsi,0xc8(%rsp)
  40dc16:	00 
  40dc17:	4c 89 b4 24 d0 00 00 	mov    %r14,0xd0(%rsp)
  40dc1e:	00 
  40dc1f:	48 8d b4 24 c0 00 00 	lea    0xc0(%rsp),%rsi
  40dc26:	00 
  40dc27:	48 89 b4 24 a0 00 00 	mov    %rsi,0xa0(%rsp)
  40dc2e:	00 
  40dc2f:	48 8d b4 24 b8 00 00 	lea    0xb8(%rsp),%rsi
  40dc36:	00 
  40dc37:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40dc3e:	00 00 00 00 00 
  40dc43:	48 89 b4 24 a8 00 00 	mov    %rsi,0xa8(%rsp)
  40dc4a:	00 
  40dc4b:	4c 89 b4 24 b0 00 00 	mov    %r14,0xb0(%rsp)
  40dc52:	00 
  40dc53:	48 8d b4 24 a0 00 00 	lea    0xa0(%rsp),%rsi
  40dc5a:	00 
  40dc5b:	48 89 b4 24 80 00 00 	mov    %rsi,0x80(%rsp)
  40dc62:	00 
  40dc63:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40dc6a:	00 00 00 00 00 
  40dc6f:	48 8d b4 24 98 00 00 	lea    0x98(%rsp),%rsi
  40dc76:	00 
  40dc77:	48 89 b4 24 88 00 00 	mov    %rsi,0x88(%rsp)
  40dc7e:	00 
  40dc7f:	4c 89 b4 24 90 00 00 	mov    %r14,0x90(%rsp)
  40dc86:	00 
  40dc87:	48 8d b4 24 80 00 00 	lea    0x80(%rsp),%rsi
  40dc8e:	00 
  40dc8f:	48 89 74 24 60       	mov    %rsi,0x60(%rsp)
  40dc94:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40dc9b:	00 00 
  40dc9d:	48 8d 74 24 78       	lea    0x78(%rsp),%rsi
  40dca2:	48 89 74 24 68       	mov    %rsi,0x68(%rsp)
  40dca7:	4c 89 74 24 70       	mov    %r14,0x70(%rsp)
  40dcac:	48 8d 74 24 60       	lea    0x60(%rsp),%rsi
  40dcb1:	48 89 74 24 40       	mov    %rsi,0x40(%rsp)
  40dcb6:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40dcbd:	00 00 
  40dcbf:	48 8d 74 24 58       	lea    0x58(%rsp),%rsi
  40dcc4:	48 89 74 24 48       	mov    %rsi,0x48(%rsp)
  40dcc9:	4c 89 74 24 50       	mov    %r14,0x50(%rsp)
  40dcce:	48 8d 74 24 40       	lea    0x40(%rsp),%rsi
  40dcd3:	48 89 74 24 20       	mov    %rsi,0x20(%rsp)
  40dcd8:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40dcdf:	00 00 
  40dce1:	48 8d 74 24 38       	lea    0x38(%rsp),%rsi
  40dce6:	48 89 74 24 28       	mov    %rsi,0x28(%rsp)
  40dceb:	4c 89 74 24 30       	mov    %r14,0x30(%rsp)
  40dcf0:	48 8d 74 24 20       	lea    0x20(%rsp),%rsi
  40dcf5:	48 89 b4 24 00 02 00 	mov    %rsi,0x200(%rsp)
  40dcfc:	00 
  40dcfd:	4c 89 9c 24 08 02 00 	mov    %r11,0x208(%rsp)
  40dd04:	00 
  40dd05:	48 c7 c6 d0 21 43 00 	mov    $0x4321d0,%rsi
  40dd0c:	48 89 b4 24 10 02 00 	mov    %rsi,0x210(%rsp)
  40dd13:	00 
  40dd14:	48 8d b4 24 00 02 00 	lea    0x200(%rsp),%rsi
  40dd1b:	00 
  40dd1c:	48 89 b4 24 e0 01 00 	mov    %rsi,0x1e0(%rsp)
  40dd23:	00 
  40dd24:	48 8d b4 24 20 03 00 	lea    0x320(%rsp),%rsi
  40dd2b:	00 
  40dd2c:	48 89 b4 24 e8 01 00 	mov    %rsi,0x1e8(%rsp)
  40dd33:	00 
  40dd34:	49 c7 c5 70 24 43 00 	mov    $0x432470,%r13
  40dd3b:	4c 89 ac 24 f0 01 00 	mov    %r13,0x1f0(%rsp)
  40dd42:	00 
  40dd43:	48 8d b4 24 e0 01 00 	lea    0x1e0(%rsp),%rsi
  40dd4a:	00 
  40dd4b:	48 89 b4 24 c0 01 00 	mov    %rsi,0x1c0(%rsp)
  40dd52:	00 
  40dd53:	4c 89 9c 24 c8 01 00 	mov    %r11,0x1c8(%rsp)
  40dd5a:	00 
  40dd5b:	48 c7 c6 90 22 43 00 	mov    $0x432290,%rsi
  40dd62:	48 89 b4 24 d0 01 00 	mov    %rsi,0x1d0(%rsp)
  40dd69:	00 
  40dd6a:	48 8d b4 24 c0 01 00 	lea    0x1c0(%rsp),%rsi
  40dd71:	00 
  40dd72:	48 89 b4 24 a0 01 00 	mov    %rsi,0x1a0(%rsp)
  40dd79:	00 
  40dd7a:	48 8d b4 24 00 03 00 	lea    0x300(%rsp),%rsi
  40dd81:	00 
  40dd82:	48 89 b4 24 a8 01 00 	mov    %rsi,0x1a8(%rsp)
  40dd89:	00 
  40dd8a:	4c 89 ac 24 b0 01 00 	mov    %r13,0x1b0(%rsp)
  40dd91:	00 
  40dd92:	48 8d b4 24 a0 01 00 	lea    0x1a0(%rsp),%rsi
  40dd99:	00 
  40dd9a:	48 89 b4 24 80 01 00 	mov    %rsi,0x180(%rsp)
  40dda1:	00 
  40dda2:	4c 89 9c 24 88 01 00 	mov    %r11,0x188(%rsp)
  40dda9:	00 
  40ddaa:	48 c7 c6 30 25 43 00 	mov    $0x432530,%rsi
  40ddb1:	48 89 b4 24 90 01 00 	mov    %rsi,0x190(%rsp)
  40ddb8:	00 
  40ddb9:	48 8d b4 24 80 01 00 	lea    0x180(%rsp),%rsi
  40ddc0:	00 
  40ddc1:	48 89 b4 24 60 01 00 	mov    %rsi,0x160(%rsp)
  40ddc8:	00 
  40ddc9:	48 8d b4 24 60 03 00 	lea    0x360(%rsp),%rsi
  40ddd0:	00 
  40ddd1:	48 89 b4 24 68 01 00 	mov    %rsi,0x168(%rsp)
  40ddd8:	00 
  40ddd9:	48 c7 c6 30 1f 43 00 	mov    $0x431f30,%rsi
  40dde0:	48 89 b4 24 70 01 00 	mov    %rsi,0x170(%rsp)
  40dde7:	00 
  40dde8:	4c 89 fd             	mov    %r15,%rbp
  40ddeb:	49 89 cf             	mov    %rcx,%r15
  40ddee:	48 8d 8c 24 60 01 00 	lea    0x160(%rsp),%rcx
  40ddf5:	00 
  40ddf6:	48 89 8c 24 40 01 00 	mov    %rcx,0x140(%rsp)
  40ddfd:	00 
  40ddfe:	4c 8d a4 24 40 03 00 	lea    0x340(%rsp),%r12
  40de05:	00 
  40de06:	4c 89 a4 24 48 01 00 	mov    %r12,0x148(%rsp)
  40de0d:	00 
  40de0e:	4c 89 ac 24 50 01 00 	mov    %r13,0x150(%rsp)
  40de15:	00 
  40de16:	48 8d 8c 24 40 01 00 	lea    0x140(%rsp),%rcx
  40de1d:	00 
  40de1e:	48 89 8c 24 00 01 00 	mov    %rcx,0x100(%rsp)
  40de25:	00 
  40de26:	4c 89 bc 24 18 01 00 	mov    %r15,0x118(%rsp)
  40de2d:	00 
  40de2e:	48 8d 8c 24 18 01 00 	lea    0x118(%rsp),%rcx
  40de35:	00 
  40de36:	48 89 8c 24 08 01 00 	mov    %rcx,0x108(%rsp)
  40de3d:	00 
  40de3e:	48 89 84 24 10 01 00 	mov    %rax,0x110(%rsp)
  40de45:	00 
  40de46:	48 89 ef             	mov    %rbp,%rdi
  40de49:	4c 89 fe             	mov    %r15,%rsi
  40de4c:	e8 bf 4e ff ff       	call   402d10 <sexpr.printer::append_float>
  40de51:	48 8b 84 24 e8 02 00 	mov    0x2e8(%rsp),%rax
  40de58:	00 
  40de59:	48 8b 40 10          	mov    0x10(%rax),%rax
  40de5d:	48 89 04 24          	mov    %rax,(%rsp)
  40de61:	4c 89 7c 24 18       	mov    %r15,0x18(%rsp)
  40de66:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40de6b:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40de70:	48 89 e0             	mov    %rsp,%rax
  40de73:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40de7a:	00 
  40de7b:	48 8b 84 24 f0 02 00 	mov    0x2f0(%rsp),%rax
  40de82:	00 
  40de83:	48 89 84 24 28 01 00 	mov    %rax,0x128(%rsp)
  40de8a:	00 
  40de8b:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40de92:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40de99:	00 
  40de9a:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40dea1:	00 
  40dea2:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40dea9:	00 
  40deaa:	48 89 9c 24 28 02 00 	mov    %rbx,0x228(%rsp)
  40deb1:	00 
  40deb2:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40deb9:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40dec0:	00 
  40dec1:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40dec8:	00 
  40dec9:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40ded0:	00 
  40ded1:	48 c7 84 24 f8 00 00 	movq   $0x0,0xf8(%rsp)
  40ded8:	00 00 00 00 00 
  40dedd:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40dee4:	00 
  40dee5:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40deec:	00 
  40deed:	48 8d 84 24 e0 00 00 	lea    0xe0(%rsp),%rax
  40def4:	00 
  40def5:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  40defc:	00 
  40defd:	48 c7 84 24 d8 00 00 	movq   $0x0,0xd8(%rsp)
  40df04:	00 00 00 00 00 
  40df09:	48 8d 84 24 d8 00 00 	lea    0xd8(%rsp),%rax
  40df10:	00 
  40df11:	48 89 84 24 c8 00 00 	mov    %rax,0xc8(%rsp)
  40df18:	00 
  40df19:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  40df20:	00 
  40df21:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  40df28:	00 
  40df29:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40df30:	00 00 00 00 00 
  40df35:	48 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%rax
  40df3c:	00 
  40df3d:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  40df44:	00 
  40df45:	48 8d 84 24 a0 00 00 	lea    0xa0(%rsp),%rax
  40df4c:	00 
  40df4d:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  40df54:	00 
  40df55:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40df5c:	00 00 00 00 00 
  40df61:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  40df68:	00 
  40df69:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  40df70:	00 
  40df71:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  40df78:	00 
  40df79:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40df7e:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40df85:	00 00 
  40df87:	48 8d 44 24 78       	lea    0x78(%rsp),%rax
  40df8c:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  40df91:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40df96:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40df9b:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40dfa2:	00 00 
  40dfa4:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  40dfa9:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40dfae:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40dfb3:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40dfb8:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40dfbf:	00 00 
  40dfc1:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40dfc6:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40dfcb:	4c 89 b4 24 f0 00 00 	mov    %r14,0xf0(%rsp)
  40dfd2:	00 
  40dfd3:	4c 89 b4 24 d0 00 00 	mov    %r14,0xd0(%rsp)
  40dfda:	00 
  40dfdb:	4c 89 b4 24 b0 00 00 	mov    %r14,0xb0(%rsp)
  40dfe2:	00 
  40dfe3:	4c 89 b4 24 90 00 00 	mov    %r14,0x90(%rsp)
  40dfea:	00 
  40dfeb:	4c 89 74 24 70       	mov    %r14,0x70(%rsp)
  40dff0:	4c 89 74 24 50       	mov    %r14,0x50(%rsp)
  40dff5:	4c 89 74 24 30       	mov    %r14,0x30(%rsp)
  40dffa:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40dfff:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40e006:	00 
  40e007:	48 89 9c 24 08 02 00 	mov    %rbx,0x208(%rsp)
  40e00e:	00 
  40e00f:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40e016:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40e01d:	00 
  40e01e:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40e025:	00 
  40e026:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40e02d:	00 
  40e02e:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40e035:	00 
  40e036:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40e03d:	00 
  40e03e:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40e045:	00 
  40e046:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40e04d:	00 
  40e04e:	48 89 9c 24 c8 01 00 	mov    %rbx,0x1c8(%rsp)
  40e055:	00 
  40e056:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40e05d:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40e064:	00 
  40e065:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40e06c:	00 
  40e06d:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40e074:	00 
  40e075:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40e07c:	00 
  40e07d:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40e084:	00 
  40e085:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40e08c:	00 
  40e08d:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40e094:	00 
  40e095:	48 89 9c 24 88 01 00 	mov    %rbx,0x188(%rsp)
  40e09c:	00 
  40e09d:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40e0a4:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40e0ab:	00 
  40e0ac:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40e0b3:	00 
  40e0b4:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40e0bb:	00 
  40e0bc:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40e0c3:	00 
  40e0c4:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40e0cb:	00 
  40e0cc:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40e0d3:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40e0da:	00 
  40e0db:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40e0e2:	00 
  40e0e3:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40e0ea:	00 
  40e0eb:	4c 89 a4 24 48 01 00 	mov    %r12,0x148(%rsp)
  40e0f2:	00 
  40e0f3:	4c 89 ac 24 f0 01 00 	mov    %r13,0x1f0(%rsp)
  40e0fa:	00 
  40e0fb:	4c 89 ac 24 b0 01 00 	mov    %r13,0x1b0(%rsp)
  40e102:	00 
  40e103:	4c 89 ac 24 50 01 00 	mov    %r13,0x150(%rsp)
  40e10a:	00 
  40e10b:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40e112:	00 
  40e113:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40e11a:	00 
  40e11b:	48 c7 c0 d0 27 43 00 	mov    $0x4327d0,%rax
  40e122:	49 c7 c4 60 84 42 00 	mov    $0x428460,%r12
  40e129:	4c 89 64 24 10       	mov    %r12,0x10(%rsp)
  40e12e:	4c 89 bc 24 18 01 00 	mov    %r15,0x118(%rsp)
  40e135:	00 
  40e136:	48 8d 94 24 18 01 00 	lea    0x118(%rsp),%rdx
  40e13d:	00 
  40e13e:	48 89 94 24 08 01 00 	mov    %rdx,0x108(%rsp)
  40e145:	00 
  40e146:	4c 89 a4 24 10 01 00 	mov    %r12,0x110(%rsp)
  40e14d:	00 
  40e14e:	4c 8b 30             	mov    (%rax),%r14
  40e151:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40e158:	00 
  40e159:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40e160:	00 
  40e161:	4c 89 b4 24 b8 02 00 	mov    %r14,0x2b8(%rsp)
  40e168:	00 
  40e169:	48 8d 84 24 b8 02 00 	lea    0x2b8(%rsp),%rax
  40e170:	00 
  40e171:	48 89 84 24 a8 02 00 	mov    %rax,0x2a8(%rsp)
  40e178:	00 
  40e179:	48 c7 c3 d0 1e 43 00 	mov    $0x431ed0,%rbx
  40e180:	48 89 9c 24 b0 02 00 	mov    %rbx,0x2b0(%rsp)
  40e187:	00 
  40e188:	48 89 ef             	mov    %rbp,%rdi
  40e18b:	e8 e0 d3 00 00       	call   41b570 <myl_qbe_heap>
  40e190:	49 8b 37             	mov    (%r15),%rsi
  40e193:	4d 8b 06             	mov    (%r14),%r8
  40e196:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40e19a:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40e1a1:	00 
  40e1a2:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40e1a9:	00 
  40e1aa:	4c 89 bc 24 58 02 00 	mov    %r15,0x258(%rsp)
  40e1b1:	00 
  40e1b2:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40e1b9:	00 
  40e1ba:	4c 89 a4 24 50 02 00 	mov    %r12,0x250(%rsp)
  40e1c1:	00 
  40e1c2:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40e1c9:	00 
  40e1ca:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40e1d1:	00 
  40e1d2:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40e1d9:	00 
  40e1da:	4c 89 b4 24 78 02 00 	mov    %r14,0x278(%rsp)
  40e1e1:	00 
  40e1e2:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40e1e9:	00 
  40e1ea:	48 89 9c 24 70 02 00 	mov    %rbx,0x270(%rsp)
  40e1f1:	00 
  40e1f2:	48 8d 8c 24 60 02 00 	lea    0x260(%rsp),%rcx
  40e1f9:	00 
  40e1fa:	48 89 8c 24 80 02 00 	mov    %rcx,0x280(%rsp)
  40e201:	00 
  40e202:	48 8d 8c 24 98 02 00 	lea    0x298(%rsp),%rcx
  40e209:	00 
  40e20a:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40e211:	00 
  40e212:	48 89 8c 24 88 02 00 	mov    %rcx,0x288(%rsp)
  40e219:	00 
  40e21a:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40e221:	48 89 8c 24 90 02 00 	mov    %rcx,0x290(%rsp)
  40e228:	00 
  40e229:	48 8d 8c 24 80 02 00 	lea    0x280(%rsp),%rcx
  40e230:	00 
  40e231:	48 89 8c 24 c0 02 00 	mov    %rcx,0x2c0(%rsp)
  40e238:	00 
  40e239:	48 8d 8c 24 d8 02 00 	lea    0x2d8(%rsp),%rcx
  40e240:	00 
  40e241:	4c 89 b4 24 d8 02 00 	mov    %r14,0x2d8(%rsp)
  40e248:	00 
  40e249:	48 89 8c 24 c8 02 00 	mov    %rcx,0x2c8(%rsp)
  40e250:	00 
  40e251:	e9 72 1a 00 00       	jmp    40fcc8 <sexpr.printer::push_node+0x4b88>
  40e256:	48 89 04 24          	mov    %rax,(%rsp)
  40e25a:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40e25f:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
  40e264:	48 c7 c3 60 84 42 00 	mov    $0x428460,%rbx
  40e26b:	48 89 5c 24 10       	mov    %rbx,0x10(%rsp)
  40e270:	48 89 e0             	mov    %rsp,%rax
  40e273:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40e27a:	00 
  40e27b:	4c 89 b4 24 28 01 00 	mov    %r14,0x128(%rsp)
  40e282:	00 
  40e283:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40e28a:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40e291:	00 
  40e292:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40e299:	00 
  40e29a:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40e2a1:	00 
  40e2a2:	4c 89 9c 24 28 02 00 	mov    %r11,0x228(%rsp)
  40e2a9:	00 
  40e2aa:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40e2b1:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40e2b8:	00 
  40e2b9:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40e2c0:	00 
  40e2c1:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40e2c8:	00 
  40e2c9:	4c 89 94 24 f8 00 00 	mov    %r10,0xf8(%rsp)
  40e2d0:	00 
  40e2d1:	48 89 8c 24 e8 00 00 	mov    %rcx,0xe8(%rsp)
  40e2d8:	00 
  40e2d9:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40e2e0:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40e2e7:	00 
  40e2e8:	48 8d 8c 24 e0 00 00 	lea    0xe0(%rsp),%rcx
  40e2ef:	00 
  40e2f0:	48 89 8c 24 c0 00 00 	mov    %rcx,0xc0(%rsp)
  40e2f7:	00 
  40e2f8:	4c 89 94 24 d8 00 00 	mov    %r10,0xd8(%rsp)
  40e2ff:	00 
  40e300:	48 89 b4 24 c8 00 00 	mov    %rsi,0xc8(%rsp)
  40e307:	00 
  40e308:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40e30f:	00 
  40e310:	48 8d 8c 24 c0 00 00 	lea    0xc0(%rsp),%rcx
  40e317:	00 
  40e318:	48 89 8c 24 a0 00 00 	mov    %rcx,0xa0(%rsp)
  40e31f:	00 
  40e320:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40e327:	00 00 00 00 00 
  40e32c:	48 89 94 24 a8 00 00 	mov    %rdx,0xa8(%rsp)
  40e333:	00 
  40e334:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40e33b:	00 
  40e33c:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  40e343:	00 
  40e344:	48 89 8c 24 80 00 00 	mov    %rcx,0x80(%rsp)
  40e34b:	00 
  40e34c:	48 8d 8c 24 98 00 00 	lea    0x98(%rsp),%rcx
  40e353:	00 
  40e354:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40e35b:	00 00 00 00 00 
  40e360:	48 89 8c 24 88 00 00 	mov    %rcx,0x88(%rsp)
  40e367:	00 
  40e368:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40e36f:	00 
  40e370:	48 8d 8c 24 80 00 00 	lea    0x80(%rsp),%rcx
  40e377:	00 
  40e378:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
  40e37d:	48 8d 4c 24 78       	lea    0x78(%rsp),%rcx
  40e382:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40e389:	00 00 
  40e38b:	48 89 4c 24 68       	mov    %rcx,0x68(%rsp)
  40e390:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40e395:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  40e39a:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  40e39f:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  40e3a4:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40e3ab:	00 00 
  40e3ad:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  40e3b2:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40e3b7:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  40e3bc:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  40e3c1:	48 8d 4c 24 38       	lea    0x38(%rsp),%rcx
  40e3c6:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40e3cd:	00 00 
  40e3cf:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
  40e3d4:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40e3d9:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40e3de:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40e3e5:	00 
  40e3e6:	4c 89 9c 24 08 02 00 	mov    %r11,0x208(%rsp)
  40e3ed:	00 
  40e3ee:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40e3f5:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40e3fc:	00 
  40e3fd:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40e404:	00 
  40e405:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40e40c:	00 
  40e40d:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40e414:	00 
  40e415:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40e41c:	00 
  40e41d:	48 c7 c0 70 24 43 00 	mov    $0x432470,%rax
  40e424:	48 89 84 24 f0 01 00 	mov    %rax,0x1f0(%rsp)
  40e42b:	00 
  40e42c:	48 8d 8c 24 e0 01 00 	lea    0x1e0(%rsp),%rcx
  40e433:	00 
  40e434:	48 89 8c 24 c0 01 00 	mov    %rcx,0x1c0(%rsp)
  40e43b:	00 
  40e43c:	4c 89 9c 24 c8 01 00 	mov    %r11,0x1c8(%rsp)
  40e443:	00 
  40e444:	48 c7 c1 90 22 43 00 	mov    $0x432290,%rcx
  40e44b:	48 89 8c 24 d0 01 00 	mov    %rcx,0x1d0(%rsp)
  40e452:	00 
  40e453:	48 8d 8c 24 c0 01 00 	lea    0x1c0(%rsp),%rcx
  40e45a:	00 
  40e45b:	48 89 8c 24 a0 01 00 	mov    %rcx,0x1a0(%rsp)
  40e462:	00 
  40e463:	48 8d 8c 24 00 03 00 	lea    0x300(%rsp),%rcx
  40e46a:	00 
  40e46b:	48 89 8c 24 a8 01 00 	mov    %rcx,0x1a8(%rsp)
  40e472:	00 
  40e473:	48 89 84 24 b0 01 00 	mov    %rax,0x1b0(%rsp)
  40e47a:	00 
  40e47b:	48 c7 c1 a8 27 43 00 	mov    $0x4327a8,%rcx
  40e482:	48 8d 94 24 a0 01 00 	lea    0x1a0(%rsp),%rdx
  40e489:	00 
  40e48a:	48 89 94 24 80 01 00 	mov    %rdx,0x180(%rsp)
  40e491:	00 
  40e492:	4c 89 9c 24 88 01 00 	mov    %r11,0x188(%rsp)
  40e499:	00 
  40e49a:	48 c7 c2 30 25 43 00 	mov    $0x432530,%rdx
  40e4a1:	48 89 94 24 90 01 00 	mov    %rdx,0x190(%rsp)
  40e4a8:	00 
  40e4a9:	48 8d 94 24 80 01 00 	lea    0x180(%rsp),%rdx
  40e4b0:	00 
  40e4b1:	48 89 94 24 60 01 00 	mov    %rdx,0x160(%rsp)
  40e4b8:	00 
  40e4b9:	48 8d 94 24 60 03 00 	lea    0x360(%rsp),%rdx
  40e4c0:	00 
  40e4c1:	48 89 94 24 68 01 00 	mov    %rdx,0x168(%rsp)
  40e4c8:	00 
  40e4c9:	48 c7 c2 30 1f 43 00 	mov    $0x431f30,%rdx
  40e4d0:	48 89 94 24 70 01 00 	mov    %rdx,0x170(%rsp)
  40e4d7:	00 
  40e4d8:	48 8d 94 24 60 01 00 	lea    0x160(%rsp),%rdx
  40e4df:	00 
  40e4e0:	48 89 94 24 40 01 00 	mov    %rdx,0x140(%rsp)
  40e4e7:	00 
  40e4e8:	48 8d 94 24 40 03 00 	lea    0x340(%rsp),%rdx
  40e4ef:	00 
  40e4f0:	48 89 94 24 48 01 00 	mov    %rdx,0x148(%rsp)
  40e4f7:	00 
  40e4f8:	48 89 84 24 50 01 00 	mov    %rax,0x150(%rsp)
  40e4ff:	00 
  40e500:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40e507:	00 
  40e508:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40e50f:	00 
  40e510:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40e517:	00 
  40e518:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40e51f:	00 
  40e520:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40e527:	00 
  40e528:	48 89 9c 24 10 01 00 	mov    %rbx,0x110(%rsp)
  40e52f:	00 
  40e530:	4c 8b 31             	mov    (%rcx),%r14
  40e533:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40e53a:	00 
  40e53b:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40e542:	00 
  40e543:	4c 89 b4 24 b8 02 00 	mov    %r14,0x2b8(%rsp)
  40e54a:	00 
  40e54b:	48 8d 84 24 b8 02 00 	lea    0x2b8(%rsp),%rax
  40e552:	00 
  40e553:	48 89 84 24 a8 02 00 	mov    %rax,0x2a8(%rsp)
  40e55a:	00 
  40e55b:	4c 89 ff             	mov    %r15,%rdi
  40e55e:	49 c7 c7 d0 1e 43 00 	mov    $0x431ed0,%r15
  40e565:	4c 89 bc 24 b0 02 00 	mov    %r15,0x2b0(%rsp)
  40e56c:	00 
  40e56d:	e8 fe cf 00 00       	call   41b570 <myl_qbe_heap>
  40e572:	49 8b 75 00          	mov    0x0(%r13),%rsi
  40e576:	4d 8b 06             	mov    (%r14),%r8
  40e579:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40e57d:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40e584:	00 
  40e585:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40e58c:	00 
  40e58d:	4c 89 ac 24 58 02 00 	mov    %r13,0x258(%rsp)
  40e594:	00 
  40e595:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40e59c:	00 
  40e59d:	48 89 9c 24 50 02 00 	mov    %rbx,0x250(%rsp)
  40e5a4:	00 
  40e5a5:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40e5ac:	00 
  40e5ad:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40e5b4:	00 
  40e5b5:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40e5bc:	00 
  40e5bd:	4c 89 b4 24 78 02 00 	mov    %r14,0x278(%rsp)
  40e5c4:	00 
  40e5c5:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40e5cc:	00 
  40e5cd:	4c 89 bc 24 70 02 00 	mov    %r15,0x270(%rsp)
  40e5d4:	00 
  40e5d5:	48 8d 8c 24 60 02 00 	lea    0x260(%rsp),%rcx
  40e5dc:	00 
  40e5dd:	48 89 8c 24 80 02 00 	mov    %rcx,0x280(%rsp)
  40e5e4:	00 
  40e5e5:	48 8d 8c 24 98 02 00 	lea    0x298(%rsp),%rcx
  40e5ec:	00 
  40e5ed:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40e5f4:	00 
  40e5f5:	48 89 8c 24 88 02 00 	mov    %rcx,0x288(%rsp)
  40e5fc:	00 
  40e5fd:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40e604:	48 89 8c 24 90 02 00 	mov    %rcx,0x290(%rsp)
  40e60b:	00 
  40e60c:	48 8d 8c 24 80 02 00 	lea    0x280(%rsp),%rcx
  40e613:	00 
  40e614:	48 89 8c 24 c0 02 00 	mov    %rcx,0x2c0(%rsp)
  40e61b:	00 
  40e61c:	48 8d 8c 24 d8 02 00 	lea    0x2d8(%rsp),%rcx
  40e623:	00 
  40e624:	4c 89 b4 24 d8 02 00 	mov    %r14,0x2d8(%rsp)
  40e62b:	00 
  40e62c:	48 89 8c 24 c8 02 00 	mov    %rcx,0x2c8(%rsp)
  40e633:	00 
  40e634:	4c 89 bc 24 d0 02 00 	mov    %r15,0x2d0(%rsp)
  40e63b:	00 
  40e63c:	e9 8f 16 00 00       	jmp    40fcd0 <sexpr.printer::push_node+0x4b90>
  40e641:	49 8b 40 10          	mov    0x10(%r8),%rax
  40e645:	48 89 04 24          	mov    %rax,(%rsp)
  40e649:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40e64e:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40e653:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40e658:	48 c7 c0 60 84 42 00 	mov    $0x428460,%rax
  40e65f:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  40e664:	48 89 e1             	mov    %rsp,%rcx
  40e667:	48 89 8c 24 20 01 00 	mov    %rcx,0x120(%rsp)
  40e66e:	00 
  40e66f:	4c 89 b4 24 28 01 00 	mov    %r14,0x128(%rsp)
  40e676:	00 
  40e677:	48 c7 c1 50 20 43 00 	mov    $0x432050,%rcx
  40e67e:	48 89 8c 24 30 01 00 	mov    %rcx,0x130(%rsp)
  40e685:	00 
  40e686:	48 8d 8c 24 20 01 00 	lea    0x120(%rsp),%rcx
  40e68d:	00 
  40e68e:	48 89 8c 24 20 02 00 	mov    %rcx,0x220(%rsp)
  40e695:	00 
  40e696:	4c 89 9c 24 28 02 00 	mov    %r11,0x228(%rsp)
  40e69d:	00 
  40e69e:	48 c7 c1 b0 23 43 00 	mov    $0x4323b0,%rcx
  40e6a5:	48 89 8c 24 30 02 00 	mov    %rcx,0x230(%rsp)
  40e6ac:	00 
  40e6ad:	48 8d 8c 24 20 02 00 	lea    0x220(%rsp),%rcx
  40e6b4:	00 
  40e6b5:	48 89 8c 24 e0 00 00 	mov    %rcx,0xe0(%rsp)
  40e6bc:	00 
  40e6bd:	48 8d 8c 24 f8 00 00 	lea    0xf8(%rsp),%rcx
  40e6c4:	00 
  40e6c5:	48 c7 84 24 f8 00 00 	movq   $0x0,0xf8(%rsp)
  40e6cc:	00 00 00 00 00 
  40e6d1:	48 89 8c 24 e8 00 00 	mov    %rcx,0xe8(%rsp)
  40e6d8:	00 
  40e6d9:	48 c7 c1 b0 20 43 00 	mov    $0x4320b0,%rcx
  40e6e0:	48 89 8c 24 f0 00 00 	mov    %rcx,0xf0(%rsp)
  40e6e7:	00 
  40e6e8:	48 8d b4 24 e0 00 00 	lea    0xe0(%rsp),%rsi
  40e6ef:	00 
  40e6f0:	48 89 b4 24 c0 00 00 	mov    %rsi,0xc0(%rsp)
  40e6f7:	00 
  40e6f8:	48 8d b4 24 d8 00 00 	lea    0xd8(%rsp),%rsi
  40e6ff:	00 
  40e700:	48 c7 84 24 d8 00 00 	movq   $0x0,0xd8(%rsp)
  40e707:	00 00 00 00 00 
  40e70c:	48 89 b4 24 c8 00 00 	mov    %rsi,0xc8(%rsp)
  40e713:	00 
  40e714:	48 89 8c 24 d0 00 00 	mov    %rcx,0xd0(%rsp)
  40e71b:	00 
  40e71c:	48 8d b4 24 c0 00 00 	lea    0xc0(%rsp),%rsi
  40e723:	00 
  40e724:	48 89 b4 24 a0 00 00 	mov    %rsi,0xa0(%rsp)
  40e72b:	00 
  40e72c:	48 8d b4 24 b8 00 00 	lea    0xb8(%rsp),%rsi
  40e733:	00 
  40e734:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40e73b:	00 00 00 00 00 
  40e740:	48 89 b4 24 a8 00 00 	mov    %rsi,0xa8(%rsp)
  40e747:	00 
  40e748:	48 89 8c 24 b0 00 00 	mov    %rcx,0xb0(%rsp)
  40e74f:	00 
  40e750:	48 8d b4 24 a0 00 00 	lea    0xa0(%rsp),%rsi
  40e757:	00 
  40e758:	48 89 b4 24 80 00 00 	mov    %rsi,0x80(%rsp)
  40e75f:	00 
  40e760:	48 8d b4 24 98 00 00 	lea    0x98(%rsp),%rsi
  40e767:	00 
  40e768:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40e76f:	00 00 00 00 00 
  40e774:	48 89 b4 24 88 00 00 	mov    %rsi,0x88(%rsp)
  40e77b:	00 
  40e77c:	48 89 8c 24 90 00 00 	mov    %rcx,0x90(%rsp)
  40e783:	00 
  40e784:	48 8d b4 24 80 00 00 	lea    0x80(%rsp),%rsi
  40e78b:	00 
  40e78c:	48 89 74 24 60       	mov    %rsi,0x60(%rsp)
  40e791:	48 8d 74 24 78       	lea    0x78(%rsp),%rsi
  40e796:	48 c7 44 24 78 00 00 	movq   $0x0,0x78(%rsp)
  40e79d:	00 00 
  40e79f:	48 89 74 24 68       	mov    %rsi,0x68(%rsp)
  40e7a4:	48 89 4c 24 70       	mov    %rcx,0x70(%rsp)
  40e7a9:	48 8d 74 24 60       	lea    0x60(%rsp),%rsi
  40e7ae:	48 89 74 24 40       	mov    %rsi,0x40(%rsp)
  40e7b3:	48 8d 74 24 58       	lea    0x58(%rsp),%rsi
  40e7b8:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40e7bf:	00 00 
  40e7c1:	48 89 74 24 48       	mov    %rsi,0x48(%rsp)
  40e7c6:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
  40e7cb:	48 8d 74 24 40       	lea    0x40(%rsp),%rsi
  40e7d0:	48 89 74 24 20       	mov    %rsi,0x20(%rsp)
  40e7d5:	48 8d 74 24 38       	lea    0x38(%rsp),%rsi
  40e7da:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40e7e1:	00 00 
  40e7e3:	48 89 74 24 28       	mov    %rsi,0x28(%rsp)
  40e7e8:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
  40e7ed:	48 8d 4c 24 20       	lea    0x20(%rsp),%rcx
  40e7f2:	48 89 8c 24 00 02 00 	mov    %rcx,0x200(%rsp)
  40e7f9:	00 
  40e7fa:	4c 89 9c 24 08 02 00 	mov    %r11,0x208(%rsp)
  40e801:	00 
  40e802:	48 c7 c1 d0 21 43 00 	mov    $0x4321d0,%rcx
  40e809:	48 89 8c 24 10 02 00 	mov    %rcx,0x210(%rsp)
  40e810:	00 
  40e811:	48 8d 8c 24 00 02 00 	lea    0x200(%rsp),%rcx
  40e818:	00 
  40e819:	48 89 8c 24 e0 01 00 	mov    %rcx,0x1e0(%rsp)
  40e820:	00 
  40e821:	48 8d 8c 24 20 03 00 	lea    0x320(%rsp),%rcx
  40e828:	00 
  40e829:	48 89 8c 24 e8 01 00 	mov    %rcx,0x1e8(%rsp)
  40e830:	00 
  40e831:	48 c7 c1 70 24 43 00 	mov    $0x432470,%rcx
  40e838:	48 89 8c 24 f0 01 00 	mov    %rcx,0x1f0(%rsp)
  40e83f:	00 
  40e840:	48 8d b4 24 e0 01 00 	lea    0x1e0(%rsp),%rsi
  40e847:	00 
  40e848:	48 89 b4 24 c0 01 00 	mov    %rsi,0x1c0(%rsp)
  40e84f:	00 
  40e850:	4c 89 9c 24 c8 01 00 	mov    %r11,0x1c8(%rsp)
  40e857:	00 
  40e858:	48 c7 c6 90 22 43 00 	mov    $0x432290,%rsi
  40e85f:	48 89 b4 24 d0 01 00 	mov    %rsi,0x1d0(%rsp)
  40e866:	00 
  40e867:	48 8d b4 24 c0 01 00 	lea    0x1c0(%rsp),%rsi
  40e86e:	00 
  40e86f:	48 89 b4 24 a0 01 00 	mov    %rsi,0x1a0(%rsp)
  40e876:	00 
  40e877:	48 8d b4 24 00 03 00 	lea    0x300(%rsp),%rsi
  40e87e:	00 
  40e87f:	48 89 b4 24 a8 01 00 	mov    %rsi,0x1a8(%rsp)
  40e886:	00 
  40e887:	48 89 8c 24 b0 01 00 	mov    %rcx,0x1b0(%rsp)
  40e88e:	00 
  40e88f:	48 8d b4 24 a0 01 00 	lea    0x1a0(%rsp),%rsi
  40e896:	00 
  40e897:	48 89 b4 24 80 01 00 	mov    %rsi,0x180(%rsp)
  40e89e:	00 
  40e89f:	4c 89 9c 24 88 01 00 	mov    %r11,0x188(%rsp)
  40e8a6:	00 
  40e8a7:	48 c7 c6 30 25 43 00 	mov    $0x432530,%rsi
  40e8ae:	48 89 b4 24 90 01 00 	mov    %rsi,0x190(%rsp)
  40e8b5:	00 
  40e8b6:	48 8d b4 24 80 01 00 	lea    0x180(%rsp),%rsi
  40e8bd:	00 
  40e8be:	48 89 b4 24 60 01 00 	mov    %rsi,0x160(%rsp)
  40e8c5:	00 
  40e8c6:	48 8d b4 24 60 03 00 	lea    0x360(%rsp),%rsi
  40e8cd:	00 
  40e8ce:	48 89 b4 24 68 01 00 	mov    %rsi,0x168(%rsp)
  40e8d5:	00 
  40e8d6:	48 c7 c6 30 1f 43 00 	mov    $0x431f30,%rsi
  40e8dd:	48 89 b4 24 70 01 00 	mov    %rsi,0x170(%rsp)
  40e8e4:	00 
  40e8e5:	48 8d b4 24 60 01 00 	lea    0x160(%rsp),%rsi
  40e8ec:	00 
  40e8ed:	48 89 b4 24 40 01 00 	mov    %rsi,0x140(%rsp)
  40e8f4:	00 
  40e8f5:	48 8d b4 24 40 03 00 	lea    0x340(%rsp),%rsi
  40e8fc:	00 
  40e8fd:	48 89 b4 24 48 01 00 	mov    %rsi,0x148(%rsp)
  40e904:	00 
  40e905:	48 89 8c 24 50 01 00 	mov    %rcx,0x150(%rsp)
  40e90c:	00 
  40e90d:	48 8d 8c 24 40 01 00 	lea    0x140(%rsp),%rcx
  40e914:	00 
  40e915:	48 89 8c 24 00 01 00 	mov    %rcx,0x100(%rsp)
  40e91c:	00 
  40e91d:	48 8d 8c 24 18 01 00 	lea    0x118(%rsp),%rcx
  40e924:	00 
  40e925:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40e92c:	00 
  40e92d:	48 89 8c 24 08 01 00 	mov    %rcx,0x108(%rsp)
  40e934:	00 
  40e935:	48 89 84 24 10 01 00 	mov    %rax,0x110(%rsp)
  40e93c:	00 
  40e93d:	4c 89 ff             	mov    %r15,%rdi
  40e940:	4c 89 ee             	mov    %r13,%rsi
  40e943:	c5 f8 77             	vzeroupper
  40e946:	e8 c5 43 ff ff       	call   402d10 <sexpr.printer::append_float>
  40e94b:	e9 8d 13 00 00       	jmp    40fcdd <sexpr.printer::push_node+0x4b9d>
  40e950:	48 89 d9             	mov    %rbx,%rcx
  40e953:	31 c0                	xor    %eax,%eax
  40e955:	48 c7 c5 60 84 42 00 	mov    $0x428460,%rbp
  40e95c:	48 c7 c6 b0 20 43 00 	mov    $0x4320b0,%rsi
  40e963:	4d 89 e5             	mov    %r12,%r13
  40e966:	49 89 dc             	mov    %rbx,%r12
  40e969:	48 c7 c7 70 24 43 00 	mov    $0x432470,%rdi
  40e970:	49 89 e0             	mov    %rsp,%r8
  40e973:	49 c7 c1 50 20 43 00 	mov    $0x432050,%r9
  40e97a:	4c 8d 94 24 20 01 00 	lea    0x120(%rsp),%r10
  40e981:	00 
  40e982:	49 c7 c3 b0 23 43 00 	mov    $0x4323b0,%r11
  40e989:	45 31 ff             	xor    %r15d,%r15d
  40e98c:	4c 8b b4 24 58 03 00 	mov    0x358(%rsp),%r14
  40e993:	00 
  40e994:	e9 5d 0f 00 00       	jmp    40f8f6 <sexpr.printer::push_node+0x47b6>
  40e999:	4c 8d b4 24 68 04 00 	lea    0x468(%rsp),%r14
  40e9a0:	00 
  40e9a1:	4c 89 e7             	mov    %r12,%rdi
  40e9a4:	31 f6                	xor    %esi,%esi
  40e9a6:	4c 89 f2             	mov    %r14,%rdx
  40e9a9:	e8 f2 6f 00 00       	call   4159a0 <__wrap_myl_native_list_get>
  40e9ae:	48 8b 84 24 e8 02 00 	mov    0x2e8(%rsp),%rax
  40e9b5:	00 
  40e9b6:	48 8b 40 10          	mov    0x10(%rax),%rax
  40e9ba:	48 89 04 24          	mov    %rax,(%rsp)
  40e9be:	48 8b 8c 24 f8 02 00 	mov    0x2f8(%rsp),%rcx
  40e9c5:	00 
  40e9c6:	48 83 c1 02          	add    $0x2,%rcx
  40e9ca:	4c 89 ee             	mov    %r13,%rsi
  40e9cd:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40e9d2:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40e9d7:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40e9dc:	48 c7 c2 60 84 42 00 	mov    $0x428460,%rdx
  40e9e3:	48 89 54 24 10       	mov    %rdx,0x10(%rsp)
  40e9e8:	48 89 e0             	mov    %rsp,%rax
  40e9eb:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40e9f2:	00 
  40e9f3:	49 89 d8             	mov    %rbx,%r8
  40e9f6:	48 89 9c 24 28 01 00 	mov    %rbx,0x128(%rsp)
  40e9fd:	00 
  40e9fe:	49 c7 c1 50 20 43 00 	mov    $0x432050,%r9
  40ea05:	4c 89 8c 24 30 01 00 	mov    %r9,0x130(%rsp)
  40ea0c:	00 
  40ea0d:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40ea14:	00 
  40ea15:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40ea1c:	00 
  40ea1d:	48 8d 43 08          	lea    0x8(%rbx),%rax
  40ea21:	48 89 84 24 28 02 00 	mov    %rax,0x228(%rsp)
  40ea28:	00 
  40ea29:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40ea30:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40ea37:	00 
  40ea38:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40ea3f:	00 
  40ea40:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40ea47:	00 
  40ea48:	4c 89 a4 24 f8 00 00 	mov    %r12,0xf8(%rsp)
  40ea4f:	00 
  40ea50:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40ea57:	00 
  40ea58:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40ea5f:	00 
  40ea60:	48 c7 c7 b0 20 43 00 	mov    $0x4320b0,%rdi
  40ea67:	48 89 bc 24 f0 00 00 	mov    %rdi,0xf0(%rsp)
  40ea6e:	00 
  40ea6f:	48 89 ac 24 c0 00 00 	mov    %rbp,0xc0(%rsp)
  40ea76:	00 
  40ea77:	4c 89 a4 24 d8 00 00 	mov    %r12,0xd8(%rsp)
  40ea7e:	00 
  40ea7f:	48 8d 84 24 d8 00 00 	lea    0xd8(%rsp),%rax
  40ea86:	00 
  40ea87:	48 89 84 24 c8 00 00 	mov    %rax,0xc8(%rsp)
  40ea8e:	00 
  40ea8f:	48 89 bc 24 d0 00 00 	mov    %rdi,0xd0(%rsp)
  40ea96:	00 
  40ea97:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  40ea9e:	00 
  40ea9f:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  40eaa6:	00 
  40eaa7:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40eaae:	00 00 00 00 00 
  40eab3:	48 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%rax
  40eaba:	00 
  40eabb:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  40eac2:	00 
  40eac3:	48 89 bc 24 b0 00 00 	mov    %rdi,0xb0(%rsp)
  40eaca:	00 
  40eacb:	48 8d 84 24 a0 00 00 	lea    0xa0(%rsp),%rax
  40ead2:	00 
  40ead3:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  40eada:	00 
  40eadb:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40eae2:	00 00 00 00 00 
  40eae7:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  40eaee:	00 
  40eaef:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  40eaf6:	00 
  40eaf7:	48 89 bc 24 90 00 00 	mov    %rdi,0x90(%rsp)
  40eafe:	00 
  40eaff:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  40eb06:	00 
  40eb07:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40eb0c:	4c 89 64 24 78       	mov    %r12,0x78(%rsp)
  40eb11:	48 8d 44 24 78       	lea    0x78(%rsp),%rax
  40eb16:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  40eb1b:	48 89 7c 24 70       	mov    %rdi,0x70(%rsp)
  40eb20:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40eb25:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40eb2a:	48 c7 44 24 58 00 00 	movq   $0x0,0x58(%rsp)
  40eb31:	00 00 
  40eb33:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  40eb38:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40eb3d:	48 89 7c 24 50       	mov    %rdi,0x50(%rsp)
  40eb42:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40eb47:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40eb4c:	48 c7 44 24 38 00 00 	movq   $0x0,0x38(%rsp)
  40eb53:	00 00 
  40eb55:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40eb5a:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40eb5f:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
  40eb64:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40eb69:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40eb70:	00 
  40eb71:	48 8d 43 08          	lea    0x8(%rbx),%rax
  40eb75:	48 89 84 24 08 02 00 	mov    %rax,0x208(%rsp)
  40eb7c:	00 
  40eb7d:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40eb84:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40eb8b:	00 
  40eb8c:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40eb93:	00 
  40eb94:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40eb9b:	00 
  40eb9c:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40eba3:	00 
  40eba4:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40ebab:	00 
  40ebac:	48 c7 c3 70 24 43 00 	mov    $0x432470,%rbx
  40ebb3:	48 89 9c 24 f0 01 00 	mov    %rbx,0x1f0(%rsp)
  40ebba:	00 
  40ebbb:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40ebc2:	00 
  40ebc3:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40ebca:	00 
  40ebcb:	49 8d 40 08          	lea    0x8(%r8),%rax
  40ebcf:	48 89 84 24 c8 01 00 	mov    %rax,0x1c8(%rsp)
  40ebd6:	00 
  40ebd7:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40ebde:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40ebe5:	00 
  40ebe6:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40ebed:	00 
  40ebee:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40ebf5:	00 
  40ebf6:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40ebfd:	00 
  40ebfe:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40ec05:	00 
  40ec06:	48 89 9c 24 b0 01 00 	mov    %rbx,0x1b0(%rsp)
  40ec0d:	00 
  40ec0e:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40ec15:	00 
  40ec16:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40ec1d:	00 
  40ec1e:	49 8d 40 08          	lea    0x8(%r8),%rax
  40ec22:	48 89 84 24 88 01 00 	mov    %rax,0x188(%rsp)
  40ec29:	00 
  40ec2a:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40ec31:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40ec38:	00 
  40ec39:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40ec40:	00 
  40ec41:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40ec48:	00 
  40ec49:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40ec50:	00 
  40ec51:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40ec58:	00 
  40ec59:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40ec60:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40ec67:	00 
  40ec68:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40ec6f:	00 
  40ec70:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40ec77:	00 
  40ec78:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40ec7f:	00 
  40ec80:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40ec87:	00 
  40ec88:	48 89 9c 24 50 01 00 	mov    %rbx,0x150(%rsp)
  40ec8f:	00 
  40ec90:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40ec97:	00 
  40ec98:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40ec9f:	00 
  40eca0:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40eca7:	00 
  40eca8:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40ecaf:	00 
  40ecb0:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40ecb7:	00 
  40ecb8:	48 89 d5             	mov    %rdx,%rbp
  40ecbb:	48 89 94 24 10 01 00 	mov    %rdx,0x110(%rsp)
  40ecc2:	00 
  40ecc3:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40ecca:	00 
  40eccb:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40ecd2:	00 
  40ecd3:	4c 89 b4 24 a8 02 00 	mov    %r14,0x2a8(%rsp)
  40ecda:	00 
  40ecdb:	4c 89 8c 24 b0 02 00 	mov    %r9,0x2b0(%rsp)
  40ece2:	00 
  40ece3:	4c 89 ff             	mov    %r15,%rdi
  40ece6:	4c 89 f2             	mov    %r14,%rdx
  40ece9:	4d 8d 70 08          	lea    0x8(%r8),%r14
  40eced:	48 89 8c 24 f8 02 00 	mov    %rcx,0x2f8(%rsp)
  40ecf4:	00 
  40ecf5:	e8 46 c4 ff ff       	call   40b140 <sexpr.printer::push_node>
  40ecfa:	49 83 3c 24 02       	cmpq   $0x2,(%r12)
  40ecff:	b9 00 00 00 00       	mov    $0x0,%ecx
  40ed04:	4d 89 e7             	mov    %r12,%r15
  40ed07:	b8 00 00 00 00       	mov    $0x0,%eax
  40ed0c:	48 c7 c6 b0 20 43 00 	mov    $0x4320b0,%rsi
  40ed13:	48 89 df             	mov    %rbx,%rdi
  40ed16:	49 89 e0             	mov    %rsp,%r8
  40ed19:	49 c7 c1 50 20 43 00 	mov    $0x432050,%r9
  40ed20:	4c 8d 94 24 20 01 00 	lea    0x120(%rsp),%r10
  40ed27:	00 
  40ed28:	49 c7 c3 b0 23 43 00 	mov    $0x4323b0,%r11
  40ed2f:	4c 89 e3             	mov    %r12,%rbx
  40ed32:	41 bc 00 00 00 00    	mov    $0x0,%r12d
  40ed38:	0f 8c b8 0b 00 00    	jl     40f8f6 <sexpr.printer::push_node+0x47b6>
  40ed3e:	4c 89 b4 24 58 03 00 	mov    %r14,0x358(%rsp)
  40ed45:	00 
  40ed46:	41 bf 01 00 00 00    	mov    $0x1,%r15d
  40ed4c:	4c 89 ac 24 e8 03 00 	mov    %r13,0x3e8(%rsp)
  40ed53:	00 
  40ed54:	31 c9                	xor    %ecx,%ecx
  40ed56:	49 89 dc             	mov    %rbx,%r12
  40ed59:	4c 8b ac 24 e8 03 00 	mov    0x3e8(%rsp),%r13
  40ed60:	00 
  40ed61:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  40ed68:	0f 1f 84 00 00 00 00 
  40ed6f:	00 
  40ed70:	48 89 8c 24 18 04 00 	mov    %rcx,0x418(%rsp)
  40ed77:	00 
  40ed78:	48 8b 84 24 e8 02 00 	mov    0x2e8(%rsp),%rax
  40ed7f:	00 
  40ed80:	48 8b 40 10          	mov    0x10(%rax),%rax
  40ed84:	48 89 04 24          	mov    %rax,(%rsp)
  40ed88:	48 c7 c0 f8 26 43 00 	mov    $0x4326f8,%rax
  40ed8f:	48 8b 28             	mov    (%rax),%rbp
  40ed92:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40ed97:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40ed9c:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40eda1:	48 c7 c0 60 84 42 00 	mov    $0x428460,%rax
  40eda8:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  40edad:	4c 89 84 24 20 01 00 	mov    %r8,0x120(%rsp)
  40edb4:	00 
  40edb5:	48 8b 84 24 f0 02 00 	mov    0x2f0(%rsp),%rax
  40edbc:	00 
  40edbd:	48 89 84 24 28 01 00 	mov    %rax,0x128(%rsp)
  40edc4:	00 
  40edc5:	4c 89 8c 24 30 01 00 	mov    %r9,0x130(%rsp)
  40edcc:	00 
  40edcd:	4c 89 94 24 20 02 00 	mov    %r10,0x220(%rsp)
  40edd4:	00 
  40edd5:	48 8b 9c 24 58 03 00 	mov    0x358(%rsp),%rbx
  40eddc:	00 
  40eddd:	48 89 9c 24 28 02 00 	mov    %rbx,0x228(%rsp)
  40ede4:	00 
  40ede5:	4c 89 9c 24 30 02 00 	mov    %r11,0x230(%rsp)
  40edec:	00 
  40eded:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40edf4:	00 
  40edf5:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40edfc:	00 
  40edfd:	4c 89 a4 24 f8 00 00 	mov    %r12,0xf8(%rsp)
  40ee04:	00 
  40ee05:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40ee0c:	00 
  40ee0d:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40ee14:	00 
  40ee15:	48 89 b4 24 f0 00 00 	mov    %rsi,0xf0(%rsp)
  40ee1c:	00 
  40ee1d:	48 8d 84 24 e0 00 00 	lea    0xe0(%rsp),%rax
  40ee24:	00 
  40ee25:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  40ee2c:	00 
  40ee2d:	4c 89 a4 24 d8 00 00 	mov    %r12,0xd8(%rsp)
  40ee34:	00 
  40ee35:	48 8d 84 24 d8 00 00 	lea    0xd8(%rsp),%rax
  40ee3c:	00 
  40ee3d:	48 89 84 24 c8 00 00 	mov    %rax,0xc8(%rsp)
  40ee44:	00 
  40ee45:	48 89 b4 24 d0 00 00 	mov    %rsi,0xd0(%rsp)
  40ee4c:	00 
  40ee4d:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  40ee54:	00 
  40ee55:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  40ee5c:	00 
  40ee5d:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40ee64:	00 00 00 00 00 
  40ee69:	48 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%rax
  40ee70:	00 
  40ee71:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  40ee78:	00 
  40ee79:	48 89 b4 24 b0 00 00 	mov    %rsi,0xb0(%rsp)
  40ee80:	00 
  40ee81:	48 8d 84 24 a0 00 00 	lea    0xa0(%rsp),%rax
  40ee88:	00 
  40ee89:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  40ee90:	00 
  40ee91:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40ee98:	00 00 00 00 00 
  40ee9d:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  40eea4:	00 
  40eea5:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  40eeac:	00 
  40eead:	48 89 b4 24 90 00 00 	mov    %rsi,0x90(%rsp)
  40eeb4:	00 
  40eeb5:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  40eebc:	00 
  40eebd:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40eec2:	4c 89 64 24 78       	mov    %r12,0x78(%rsp)
  40eec7:	48 8d 44 24 78       	lea    0x78(%rsp),%rax
  40eecc:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  40eed1:	48 89 74 24 70       	mov    %rsi,0x70(%rsp)
  40eed6:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40eedb:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40eee0:	4c 89 64 24 58       	mov    %r12,0x58(%rsp)
  40eee5:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  40eeea:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40eeef:	48 89 74 24 50       	mov    %rsi,0x50(%rsp)
  40eef4:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40eef9:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40eefe:	48 89 4c 24 38       	mov    %rcx,0x38(%rsp)
  40ef03:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40ef08:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40ef0d:	48 89 74 24 30       	mov    %rsi,0x30(%rsp)
  40ef12:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40ef17:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40ef1e:	00 
  40ef1f:	48 89 9c 24 08 02 00 	mov    %rbx,0x208(%rsp)
  40ef26:	00 
  40ef27:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40ef2e:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40ef35:	00 
  40ef36:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40ef3d:	00 
  40ef3e:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40ef45:	00 
  40ef46:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40ef4d:	00 
  40ef4e:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40ef55:	00 
  40ef56:	48 89 bc 24 f0 01 00 	mov    %rdi,0x1f0(%rsp)
  40ef5d:	00 
  40ef5e:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40ef65:	00 
  40ef66:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40ef6d:	00 
  40ef6e:	48 89 9c 24 c8 01 00 	mov    %rbx,0x1c8(%rsp)
  40ef75:	00 
  40ef76:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40ef7d:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40ef84:	00 
  40ef85:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40ef8c:	00 
  40ef8d:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40ef94:	00 
  40ef95:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40ef9c:	00 
  40ef9d:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40efa4:	00 
  40efa5:	48 89 bc 24 b0 01 00 	mov    %rdi,0x1b0(%rsp)
  40efac:	00 
  40efad:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40efb4:	00 
  40efb5:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40efbc:	00 
  40efbd:	48 89 9c 24 88 01 00 	mov    %rbx,0x188(%rsp)
  40efc4:	00 
  40efc5:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40efcc:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40efd3:	00 
  40efd4:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40efdb:	00 
  40efdc:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40efe3:	00 
  40efe4:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40efeb:	00 
  40efec:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40eff3:	00 
  40eff4:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40effb:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40f002:	00 
  40f003:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40f00a:	00 
  40f00b:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40f012:	00 
  40f013:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40f01a:	00 
  40f01b:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40f022:	00 
  40f023:	48 89 bc 24 50 01 00 	mov    %rdi,0x150(%rsp)
  40f02a:	00 
  40f02b:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40f032:	00 
  40f033:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40f03a:	00 
  40f03b:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40f042:	00 
  40f043:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40f04a:	00 
  40f04b:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40f052:	00 
  40f053:	48 c7 c0 60 84 42 00 	mov    $0x428460,%rax
  40f05a:	48 89 84 24 10 01 00 	mov    %rax,0x110(%rsp)
  40f061:	00 
  40f062:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40f069:	00 
  40f06a:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40f071:	00 
  40f072:	48 89 ac 24 b8 02 00 	mov    %rbp,0x2b8(%rsp)
  40f079:	00 
  40f07a:	48 8d 84 24 b8 02 00 	lea    0x2b8(%rsp),%rax
  40f081:	00 
  40f082:	48 89 84 24 a8 02 00 	mov    %rax,0x2a8(%rsp)
  40f089:	00 
  40f08a:	49 c7 c6 d0 1e 43 00 	mov    $0x431ed0,%r14
  40f091:	4c 89 b4 24 b0 02 00 	mov    %r14,0x2b0(%rsp)
  40f098:	00 
  40f099:	48 8b bc 24 e0 02 00 	mov    0x2e0(%rsp),%rdi
  40f0a0:	00 
  40f0a1:	e8 ca c4 00 00       	call   41b570 <myl_qbe_heap>
  40f0a6:	49 8b 75 00          	mov    0x0(%r13),%rsi
  40f0aa:	4c 8b 45 00          	mov    0x0(%rbp),%r8
  40f0ae:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40f0b2:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40f0b9:	00 
  40f0ba:	4c 89 ac 24 58 02 00 	mov    %r13,0x258(%rsp)
  40f0c1:	00 
  40f0c2:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40f0c9:	00 
  40f0ca:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40f0d1:	00 
  40f0d2:	48 c7 c1 60 84 42 00 	mov    $0x428460,%rcx
  40f0d9:	48 89 8c 24 50 02 00 	mov    %rcx,0x250(%rsp)
  40f0e0:	00 
  40f0e1:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40f0e8:	00 
  40f0e9:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40f0f0:	00 
  40f0f1:	48 89 ac 24 78 02 00 	mov    %rbp,0x278(%rsp)
  40f0f8:	00 
  40f0f9:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40f100:	00 
  40f101:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40f108:	00 
  40f109:	4c 89 b4 24 70 02 00 	mov    %r14,0x270(%rsp)
  40f110:	00 
  40f111:	48 8d 8c 24 60 02 00 	lea    0x260(%rsp),%rcx
  40f118:	00 
  40f119:	48 89 8c 24 80 02 00 	mov    %rcx,0x280(%rsp)
  40f120:	00 
  40f121:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40f128:	00 
  40f129:	48 8d 8c 24 98 02 00 	lea    0x298(%rsp),%rcx
  40f130:	00 
  40f131:	48 89 8c 24 88 02 00 	mov    %rcx,0x288(%rsp)
  40f138:	00 
  40f139:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40f140:	48 89 8c 24 90 02 00 	mov    %rcx,0x290(%rsp)
  40f147:	00 
  40f148:	48 8d 8c 24 80 02 00 	lea    0x280(%rsp),%rcx
  40f14f:	00 
  40f150:	48 89 8c 24 c0 02 00 	mov    %rcx,0x2c0(%rsp)
  40f157:	00 
  40f158:	48 89 ac 24 d8 02 00 	mov    %rbp,0x2d8(%rsp)
  40f15f:	00 
  40f160:	48 8d 8c 24 d8 02 00 	lea    0x2d8(%rsp),%rcx
  40f167:	00 
  40f168:	48 89 8c 24 c8 02 00 	mov    %rcx,0x2c8(%rsp)
  40f16f:	00 
  40f170:	4c 89 b4 24 d0 02 00 	mov    %r14,0x2d0(%rsp)
  40f177:	00 
  40f178:	4c 89 bc 24 20 04 00 	mov    %r15,0x420(%rsp)
  40f17f:	00 
  40f180:	48 89 c7             	mov    %rax,%rdi
  40f183:	48 89 ea             	mov    %rbp,%rdx
  40f186:	49 c7 c6 60 84 42 00 	mov    $0x428460,%r14
  40f18d:	31 c9                	xor    %ecx,%ecx
  40f18f:	e8 2c 1a 01 00       	call   420bc0 <myl_native_bytes_buffer_append_range>
  40f194:	48 8b 84 24 e8 02 00 	mov    0x2e8(%rsp),%rax
  40f19b:	00 
  40f19c:	48 8b 40 10          	mov    0x10(%rax),%rax
  40f1a0:	48 89 04 24          	mov    %rax,(%rsp)
  40f1a4:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40f1a9:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40f1ae:	48 8b 84 24 18 04 00 	mov    0x418(%rsp),%rax
  40f1b5:	00 
  40f1b6:	48 89 44 24 38       	mov    %rax,0x38(%rsp)
  40f1bb:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40f1c0:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40f1c5:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40f1ca:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
  40f1cf:	48 89 e0             	mov    %rsp,%rax
  40f1d2:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40f1d9:	00 
  40f1da:	48 8b ac 24 f0 02 00 	mov    0x2f0(%rsp),%rbp
  40f1e1:	00 
  40f1e2:	48 89 ac 24 28 01 00 	mov    %rbp,0x128(%rsp)
  40f1e9:	00 
  40f1ea:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40f1f1:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40f1f8:	00 
  40f1f9:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40f200:	00 
  40f201:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40f208:	00 
  40f209:	48 89 9c 24 28 02 00 	mov    %rbx,0x228(%rsp)
  40f210:	00 
  40f211:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40f218:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40f21f:	00 
  40f220:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40f227:	00 
  40f228:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40f22f:	00 
  40f230:	4c 89 a4 24 f8 00 00 	mov    %r12,0xf8(%rsp)
  40f237:	00 
  40f238:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40f23f:	00 
  40f240:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40f247:	00 
  40f248:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f24f:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40f256:	00 
  40f257:	48 8d 84 24 e0 00 00 	lea    0xe0(%rsp),%rax
  40f25e:	00 
  40f25f:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  40f266:	00 
  40f267:	4c 89 a4 24 d8 00 00 	mov    %r12,0xd8(%rsp)
  40f26e:	00 
  40f26f:	48 8d 84 24 d8 00 00 	lea    0xd8(%rsp),%rax
  40f276:	00 
  40f277:	48 89 84 24 c8 00 00 	mov    %rax,0xc8(%rsp)
  40f27e:	00 
  40f27f:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f286:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40f28d:	00 
  40f28e:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  40f295:	00 
  40f296:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  40f29d:	00 
  40f29e:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40f2a5:	00 00 00 00 00 
  40f2aa:	48 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%rax
  40f2b1:	00 
  40f2b2:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  40f2b9:	00 
  40f2ba:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f2c1:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40f2c8:	00 
  40f2c9:	48 8d 84 24 a0 00 00 	lea    0xa0(%rsp),%rax
  40f2d0:	00 
  40f2d1:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  40f2d8:	00 
  40f2d9:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40f2e0:	00 00 00 00 00 
  40f2e5:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  40f2ec:	00 
  40f2ed:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  40f2f4:	00 
  40f2f5:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f2fc:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40f303:	00 
  40f304:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  40f30b:	00 
  40f30c:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40f311:	4c 89 64 24 78       	mov    %r12,0x78(%rsp)
  40f316:	48 8d 44 24 78       	lea    0x78(%rsp),%rax
  40f31b:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  40f320:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f327:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40f32c:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40f331:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40f336:	4c 89 64 24 58       	mov    %r12,0x58(%rsp)
  40f33b:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  40f340:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40f345:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f34c:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40f351:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40f356:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40f35b:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f362:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40f367:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40f36c:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40f373:	00 
  40f374:	48 89 9c 24 08 02 00 	mov    %rbx,0x208(%rsp)
  40f37b:	00 
  40f37c:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40f383:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40f38a:	00 
  40f38b:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40f392:	00 
  40f393:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40f39a:	00 
  40f39b:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40f3a2:	00 
  40f3a3:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40f3aa:	00 
  40f3ab:	48 c7 c0 70 24 43 00 	mov    $0x432470,%rax
  40f3b2:	48 89 84 24 f0 01 00 	mov    %rax,0x1f0(%rsp)
  40f3b9:	00 
  40f3ba:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40f3c1:	00 
  40f3c2:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40f3c9:	00 
  40f3ca:	48 89 9c 24 c8 01 00 	mov    %rbx,0x1c8(%rsp)
  40f3d1:	00 
  40f3d2:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40f3d9:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40f3e0:	00 
  40f3e1:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40f3e8:	00 
  40f3e9:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40f3f0:	00 
  40f3f1:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40f3f8:	00 
  40f3f9:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40f400:	00 
  40f401:	48 c7 c0 70 24 43 00 	mov    $0x432470,%rax
  40f408:	48 89 84 24 b0 01 00 	mov    %rax,0x1b0(%rsp)
  40f40f:	00 
  40f410:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40f417:	00 
  40f418:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40f41f:	00 
  40f420:	48 89 9c 24 88 01 00 	mov    %rbx,0x188(%rsp)
  40f427:	00 
  40f428:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40f42f:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40f436:	00 
  40f437:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40f43e:	00 
  40f43f:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40f446:	00 
  40f447:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40f44e:	00 
  40f44f:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40f456:	00 
  40f457:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40f45e:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40f465:	00 
  40f466:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40f46d:	00 
  40f46e:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40f475:	00 
  40f476:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40f47d:	00 
  40f47e:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40f485:	00 
  40f486:	48 c7 c0 70 24 43 00 	mov    $0x432470,%rax
  40f48d:	48 89 84 24 50 01 00 	mov    %rax,0x150(%rsp)
  40f494:	00 
  40f495:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40f49c:	00 
  40f49d:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40f4a4:	00 
  40f4a5:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40f4ac:	00 
  40f4ad:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40f4b4:	00 
  40f4b5:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40f4bc:	00 
  40f4bd:	4c 89 b4 24 10 01 00 	mov    %r14,0x110(%rsp)
  40f4c4:	00 
  40f4c5:	48 8b bc 24 e0 02 00 	mov    0x2e0(%rsp),%rdi
  40f4cc:	00 
  40f4cd:	4c 89 ee             	mov    %r13,%rsi
  40f4d0:	48 8b 94 24 f8 02 00 	mov    0x2f8(%rsp),%rdx
  40f4d7:	00 
  40f4d8:	e8 33 16 00 00       	call   410b10 <byte_builder::append_spaces>
  40f4dd:	4c 89 e7             	mov    %r12,%rdi
  40f4e0:	4c 89 fe             	mov    %r15,%rsi
  40f4e3:	4c 8d bc 24 28 04 00 	lea    0x428(%rsp),%r15
  40f4ea:	00 
  40f4eb:	4c 89 fa             	mov    %r15,%rdx
  40f4ee:	e8 ad 64 00 00       	call   4159a0 <__wrap_myl_native_list_get>
  40f4f3:	48 8b 84 24 e8 02 00 	mov    0x2e8(%rsp),%rax
  40f4fa:	00 
  40f4fb:	48 8b 40 10          	mov    0x10(%rax),%rax
  40f4ff:	48 89 04 24          	mov    %rax,(%rsp)
  40f503:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40f508:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40f50d:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40f512:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
  40f517:	48 89 e0             	mov    %rsp,%rax
  40f51a:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  40f521:	00 
  40f522:	48 89 ac 24 28 01 00 	mov    %rbp,0x128(%rsp)
  40f529:	00 
  40f52a:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40f531:	48 89 84 24 30 01 00 	mov    %rax,0x130(%rsp)
  40f538:	00 
  40f539:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  40f540:	00 
  40f541:	48 89 84 24 20 02 00 	mov    %rax,0x220(%rsp)
  40f548:	00 
  40f549:	48 89 9c 24 28 02 00 	mov    %rbx,0x228(%rsp)
  40f550:	00 
  40f551:	48 c7 c0 b0 23 43 00 	mov    $0x4323b0,%rax
  40f558:	48 89 84 24 30 02 00 	mov    %rax,0x230(%rsp)
  40f55f:	00 
  40f560:	48 8d 84 24 20 02 00 	lea    0x220(%rsp),%rax
  40f567:	00 
  40f568:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  40f56f:	00 
  40f570:	4c 89 a4 24 f8 00 00 	mov    %r12,0xf8(%rsp)
  40f577:	00 
  40f578:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  40f57f:	00 
  40f580:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
  40f587:	00 
  40f588:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f58f:	48 89 84 24 f0 00 00 	mov    %rax,0xf0(%rsp)
  40f596:	00 
  40f597:	48 8d 84 24 e0 00 00 	lea    0xe0(%rsp),%rax
  40f59e:	00 
  40f59f:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  40f5a6:	00 
  40f5a7:	4c 89 a4 24 d8 00 00 	mov    %r12,0xd8(%rsp)
  40f5ae:	00 
  40f5af:	48 8d 84 24 d8 00 00 	lea    0xd8(%rsp),%rax
  40f5b6:	00 
  40f5b7:	48 89 84 24 c8 00 00 	mov    %rax,0xc8(%rsp)
  40f5be:	00 
  40f5bf:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f5c6:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40f5cd:	00 
  40f5ce:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  40f5d5:	00 
  40f5d6:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  40f5dd:	00 
  40f5de:	48 c7 84 24 b8 00 00 	movq   $0x0,0xb8(%rsp)
  40f5e5:	00 00 00 00 00 
  40f5ea:	48 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%rax
  40f5f1:	00 
  40f5f2:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  40f5f9:	00 
  40f5fa:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f601:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  40f608:	00 
  40f609:	48 8d 84 24 a0 00 00 	lea    0xa0(%rsp),%rax
  40f610:	00 
  40f611:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  40f618:	00 
  40f619:	48 c7 84 24 98 00 00 	movq   $0x0,0x98(%rsp)
  40f620:	00 00 00 00 00 
  40f625:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  40f62c:	00 
  40f62d:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  40f634:	00 
  40f635:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f63c:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40f643:	00 
  40f644:	48 8d 84 24 80 00 00 	lea    0x80(%rsp),%rax
  40f64b:	00 
  40f64c:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  40f651:	4c 89 64 24 78       	mov    %r12,0x78(%rsp)
  40f656:	48 8d 44 24 78       	lea    0x78(%rsp),%rax
  40f65b:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  40f660:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f667:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  40f66c:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40f671:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40f676:	4c 89 64 24 58       	mov    %r12,0x58(%rsp)
  40f67b:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  40f680:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40f685:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f68c:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40f691:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40f696:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40f69b:	4c 89 64 24 38       	mov    %r12,0x38(%rsp)
  40f6a0:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40f6a5:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40f6aa:	48 c7 c0 b0 20 43 00 	mov    $0x4320b0,%rax
  40f6b1:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40f6b6:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40f6bb:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40f6c2:	00 
  40f6c3:	48 89 9c 24 08 02 00 	mov    %rbx,0x208(%rsp)
  40f6ca:	00 
  40f6cb:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40f6d2:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40f6d9:	00 
  40f6da:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40f6e1:	00 
  40f6e2:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40f6e9:	00 
  40f6ea:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40f6f1:	00 
  40f6f2:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40f6f9:	00 
  40f6fa:	48 c7 c0 70 24 43 00 	mov    $0x432470,%rax
  40f701:	48 89 84 24 f0 01 00 	mov    %rax,0x1f0(%rsp)
  40f708:	00 
  40f709:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40f710:	00 
  40f711:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40f718:	00 
  40f719:	48 89 9c 24 c8 01 00 	mov    %rbx,0x1c8(%rsp)
  40f720:	00 
  40f721:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40f728:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40f72f:	00 
  40f730:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40f737:	00 
  40f738:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40f73f:	00 
  40f740:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40f747:	00 
  40f748:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40f74f:	00 
  40f750:	48 c7 c0 70 24 43 00 	mov    $0x432470,%rax
  40f757:	48 89 84 24 b0 01 00 	mov    %rax,0x1b0(%rsp)
  40f75e:	00 
  40f75f:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40f766:	00 
  40f767:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40f76e:	00 
  40f76f:	48 89 9c 24 88 01 00 	mov    %rbx,0x188(%rsp)
  40f776:	00 
  40f777:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40f77e:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40f785:	00 
  40f786:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40f78d:	00 
  40f78e:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40f795:	00 
  40f796:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40f79d:	00 
  40f79e:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40f7a5:	00 
  40f7a6:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40f7ad:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40f7b4:	00 
  40f7b5:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40f7bc:	00 
  40f7bd:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40f7c4:	00 
  40f7c5:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40f7cc:	00 
  40f7cd:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40f7d4:	00 
  40f7d5:	48 c7 c0 70 24 43 00 	mov    $0x432470,%rax
  40f7dc:	48 89 84 24 50 01 00 	mov    %rax,0x150(%rsp)
  40f7e3:	00 
  40f7e4:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40f7eb:	00 
  40f7ec:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40f7f3:	00 
  40f7f4:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40f7fb:	00 
  40f7fc:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40f803:	00 
  40f804:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40f80b:	00 
  40f80c:	4c 89 f3             	mov    %r14,%rbx
  40f80f:	4c 89 b4 24 10 01 00 	mov    %r14,0x110(%rsp)
  40f816:	00 
  40f817:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40f81e:	00 
  40f81f:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40f826:	00 
  40f827:	4c 89 bc 24 a8 02 00 	mov    %r15,0x2a8(%rsp)
  40f82e:	00 
  40f82f:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40f836:	48 89 84 24 b0 02 00 	mov    %rax,0x2b0(%rsp)
  40f83d:	00 
  40f83e:	48 8b bc 24 e0 02 00 	mov    0x2e0(%rsp),%rdi
  40f845:	00 
  40f846:	4c 89 ee             	mov    %r13,%rsi
  40f849:	4c 89 fa             	mov    %r15,%rdx
  40f84c:	48 8b 8c 24 f8 02 00 	mov    0x2f8(%rsp),%rcx
  40f853:	00 
  40f854:	e8 e7 b8 ff ff       	call   40b140 <sexpr.printer::push_node>
  40f859:	49 c7 c3 b0 23 43 00 	mov    $0x4323b0,%r11
  40f860:	4c 8d 94 24 20 01 00 	lea    0x120(%rsp),%r10
  40f867:	00 
  40f868:	49 c7 c1 50 20 43 00 	mov    $0x432050,%r9
  40f86f:	49 89 e0             	mov    %rsp,%r8
  40f872:	48 c7 c7 70 24 43 00 	mov    $0x432470,%rdi
  40f879:	48 c7 c6 b0 20 43 00 	mov    $0x4320b0,%rsi
  40f880:	48 8b 84 24 20 04 00 	mov    0x420(%rsp),%rax
  40f887:	00 
  40f888:	48 ff c0             	inc    %rax
  40f88b:	4c 89 e1             	mov    %r12,%rcx
  40f88e:	49 89 c7             	mov    %rax,%r15
  40f891:	49 3b 04 24          	cmp    (%r12),%rax
  40f895:	0f 8c d5 f4 ff ff    	jl     40ed70 <sexpr.printer::push_node+0x3c30>
  40f89b:	31 c9                	xor    %ecx,%ecx
  40f89d:	4d 89 e7             	mov    %r12,%r15
  40f8a0:	4c 89 e0             	mov    %r12,%rax
  40f8a3:	4c 8b ac 24 e8 03 00 	mov    0x3e8(%rsp),%r13
  40f8aa:	00 
  40f8ab:	4c 8b b4 24 58 03 00 	mov    0x358(%rsp),%r14
  40f8b2:	00 
  40f8b3:	48 89 dd             	mov    %rbx,%rbp
  40f8b6:	4c 89 e3             	mov    %r12,%rbx
  40f8b9:	45 31 e4             	xor    %r12d,%r12d
  40f8bc:	eb 38                	jmp    40f8f6 <sexpr.printer::push_node+0x47b6>
  40f8be:	31 c9                	xor    %ecx,%ecx
  40f8c0:	49 89 dc             	mov    %rbx,%r12
  40f8c3:	45 31 ff             	xor    %r15d,%r15d
  40f8c6:	31 c0                	xor    %eax,%eax
  40f8c8:	48 c7 c5 60 84 42 00 	mov    $0x428460,%rbp
  40f8cf:	48 c7 c6 b0 20 43 00 	mov    $0x4320b0,%rsi
  40f8d6:	48 c7 c7 70 24 43 00 	mov    $0x432470,%rdi
  40f8dd:	49 89 e0             	mov    %rsp,%r8
  40f8e0:	49 c7 c1 50 20 43 00 	mov    $0x432050,%r9
  40f8e7:	4c 8d 94 24 20 01 00 	lea    0x120(%rsp),%r10
  40f8ee:	00 
  40f8ef:	49 c7 c3 b0 23 43 00 	mov    $0x4323b0,%r11
  40f8f6:	48 8b 94 24 e8 02 00 	mov    0x2e8(%rsp),%rdx
  40f8fd:	00 
  40f8fe:	48 8b 52 10          	mov    0x10(%rdx),%rdx
  40f902:	48 89 14 24          	mov    %rdx,(%rsp)
  40f906:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
  40f90b:	48 8d 54 24 18       	lea    0x18(%rsp),%rdx
  40f910:	48 89 54 24 08       	mov    %rdx,0x8(%rsp)
  40f915:	4c 89 84 24 20 01 00 	mov    %r8,0x120(%rsp)
  40f91c:	00 
  40f91d:	48 8b 94 24 f0 02 00 	mov    0x2f0(%rsp),%rdx
  40f924:	00 
  40f925:	48 89 94 24 28 01 00 	mov    %rdx,0x128(%rsp)
  40f92c:	00 
  40f92d:	4c 89 8c 24 30 01 00 	mov    %r9,0x130(%rsp)
  40f934:	00 
  40f935:	4c 89 94 24 20 02 00 	mov    %r10,0x220(%rsp)
  40f93c:	00 
  40f93d:	4c 89 b4 24 28 02 00 	mov    %r14,0x228(%rsp)
  40f944:	00 
  40f945:	4c 89 9c 24 30 02 00 	mov    %r11,0x230(%rsp)
  40f94c:	00 
  40f94d:	48 8d 94 24 20 02 00 	lea    0x220(%rsp),%rdx
  40f954:	00 
  40f955:	48 89 94 24 e0 00 00 	mov    %rdx,0xe0(%rsp)
  40f95c:	00 
  40f95d:	48 89 9c 24 f8 00 00 	mov    %rbx,0xf8(%rsp)
  40f964:	00 
  40f965:	48 8d 94 24 f8 00 00 	lea    0xf8(%rsp),%rdx
  40f96c:	00 
  40f96d:	48 89 94 24 e8 00 00 	mov    %rdx,0xe8(%rsp)
  40f974:	00 
  40f975:	48 8d 94 24 e0 00 00 	lea    0xe0(%rsp),%rdx
  40f97c:	00 
  40f97d:	48 89 94 24 c0 00 00 	mov    %rdx,0xc0(%rsp)
  40f984:	00 
  40f985:	48 89 9c 24 d8 00 00 	mov    %rbx,0xd8(%rsp)
  40f98c:	00 
  40f98d:	48 8d 94 24 d8 00 00 	lea    0xd8(%rsp),%rdx
  40f994:	00 
  40f995:	48 89 94 24 c8 00 00 	mov    %rdx,0xc8(%rsp)
  40f99c:	00 
  40f99d:	48 8d 94 24 c0 00 00 	lea    0xc0(%rsp),%rdx
  40f9a4:	00 
  40f9a5:	48 89 94 24 a0 00 00 	mov    %rdx,0xa0(%rsp)
  40f9ac:	00 
  40f9ad:	4c 89 a4 24 b8 00 00 	mov    %r12,0xb8(%rsp)
  40f9b4:	00 
  40f9b5:	48 8d 94 24 b8 00 00 	lea    0xb8(%rsp),%rdx
  40f9bc:	00 
  40f9bd:	48 89 94 24 a8 00 00 	mov    %rdx,0xa8(%rsp)
  40f9c4:	00 
  40f9c5:	48 8d 94 24 a0 00 00 	lea    0xa0(%rsp),%rdx
  40f9cc:	00 
  40f9cd:	48 89 94 24 80 00 00 	mov    %rdx,0x80(%rsp)
  40f9d4:	00 
  40f9d5:	48 89 8c 24 98 00 00 	mov    %rcx,0x98(%rsp)
  40f9dc:	00 
  40f9dd:	48 8d 8c 24 98 00 00 	lea    0x98(%rsp),%rcx
  40f9e4:	00 
  40f9e5:	48 89 8c 24 88 00 00 	mov    %rcx,0x88(%rsp)
  40f9ec:	00 
  40f9ed:	48 8d 8c 24 80 00 00 	lea    0x80(%rsp),%rcx
  40f9f4:	00 
  40f9f5:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
  40f9fa:	4c 89 7c 24 78       	mov    %r15,0x78(%rsp)
  40f9ff:	48 8d 4c 24 78       	lea    0x78(%rsp),%rcx
  40fa04:	48 89 4c 24 68       	mov    %rcx,0x68(%rsp)
  40fa09:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  40fa0e:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  40fa13:	4c 89 7c 24 58       	mov    %r15,0x58(%rsp)
  40fa18:	48 8d 4c 24 58       	lea    0x58(%rsp),%rcx
  40fa1d:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  40fa22:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  40fa27:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  40fa2c:	48 89 44 24 38       	mov    %rax,0x38(%rsp)
  40fa31:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40fa36:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40fa3b:	48 89 b4 24 f0 00 00 	mov    %rsi,0xf0(%rsp)
  40fa42:	00 
  40fa43:	48 89 b4 24 d0 00 00 	mov    %rsi,0xd0(%rsp)
  40fa4a:	00 
  40fa4b:	48 89 b4 24 b0 00 00 	mov    %rsi,0xb0(%rsp)
  40fa52:	00 
  40fa53:	48 89 b4 24 90 00 00 	mov    %rsi,0x90(%rsp)
  40fa5a:	00 
  40fa5b:	48 89 74 24 70       	mov    %rsi,0x70(%rsp)
  40fa60:	48 89 74 24 50       	mov    %rsi,0x50(%rsp)
  40fa65:	48 89 74 24 30       	mov    %rsi,0x30(%rsp)
  40fa6a:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  40fa6f:	48 89 84 24 00 02 00 	mov    %rax,0x200(%rsp)
  40fa76:	00 
  40fa77:	4c 89 b4 24 08 02 00 	mov    %r14,0x208(%rsp)
  40fa7e:	00 
  40fa7f:	48 c7 c0 d0 21 43 00 	mov    $0x4321d0,%rax
  40fa86:	48 89 84 24 10 02 00 	mov    %rax,0x210(%rsp)
  40fa8d:	00 
  40fa8e:	48 8d 84 24 00 02 00 	lea    0x200(%rsp),%rax
  40fa95:	00 
  40fa96:	48 89 84 24 e0 01 00 	mov    %rax,0x1e0(%rsp)
  40fa9d:	00 
  40fa9e:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  40faa5:	00 
  40faa6:	48 89 84 24 e8 01 00 	mov    %rax,0x1e8(%rsp)
  40faad:	00 
  40faae:	48 8d 84 24 e0 01 00 	lea    0x1e0(%rsp),%rax
  40fab5:	00 
  40fab6:	48 89 84 24 c0 01 00 	mov    %rax,0x1c0(%rsp)
  40fabd:	00 
  40fabe:	4c 89 b4 24 c8 01 00 	mov    %r14,0x1c8(%rsp)
  40fac5:	00 
  40fac6:	48 c7 c0 90 22 43 00 	mov    $0x432290,%rax
  40facd:	48 89 84 24 d0 01 00 	mov    %rax,0x1d0(%rsp)
  40fad4:	00 
  40fad5:	48 8d 84 24 c0 01 00 	lea    0x1c0(%rsp),%rax
  40fadc:	00 
  40fadd:	48 89 84 24 a0 01 00 	mov    %rax,0x1a0(%rsp)
  40fae4:	00 
  40fae5:	48 8d 84 24 00 03 00 	lea    0x300(%rsp),%rax
  40faec:	00 
  40faed:	48 89 84 24 a8 01 00 	mov    %rax,0x1a8(%rsp)
  40faf4:	00 
  40faf5:	48 8d 84 24 a0 01 00 	lea    0x1a0(%rsp),%rax
  40fafc:	00 
  40fafd:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
  40fb04:	00 
  40fb05:	4c 89 b4 24 88 01 00 	mov    %r14,0x188(%rsp)
  40fb0c:	00 
  40fb0d:	48 c7 c0 30 25 43 00 	mov    $0x432530,%rax
  40fb14:	48 89 84 24 90 01 00 	mov    %rax,0x190(%rsp)
  40fb1b:	00 
  40fb1c:	48 8d 84 24 80 01 00 	lea    0x180(%rsp),%rax
  40fb23:	00 
  40fb24:	48 89 84 24 60 01 00 	mov    %rax,0x160(%rsp)
  40fb2b:	00 
  40fb2c:	48 8d 84 24 60 03 00 	lea    0x360(%rsp),%rax
  40fb33:	00 
  40fb34:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
  40fb3b:	00 
  40fb3c:	48 c7 c0 30 1f 43 00 	mov    $0x431f30,%rax
  40fb43:	48 89 84 24 70 01 00 	mov    %rax,0x170(%rsp)
  40fb4a:	00 
  40fb4b:	48 8d 84 24 60 01 00 	lea    0x160(%rsp),%rax
  40fb52:	00 
  40fb53:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40fb5a:	00 
  40fb5b:	48 8d 84 24 40 03 00 	lea    0x340(%rsp),%rax
  40fb62:	00 
  40fb63:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40fb6a:	00 
  40fb6b:	48 89 bc 24 f0 01 00 	mov    %rdi,0x1f0(%rsp)
  40fb72:	00 
  40fb73:	48 89 bc 24 b0 01 00 	mov    %rdi,0x1b0(%rsp)
  40fb7a:	00 
  40fb7b:	48 89 bc 24 50 01 00 	mov    %rdi,0x150(%rsp)
  40fb82:	00 
  40fb83:	48 8d 84 24 40 01 00 	lea    0x140(%rsp),%rax
  40fb8a:	00 
  40fb8b:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  40fb92:	00 
  40fb93:	4c 89 ac 24 18 01 00 	mov    %r13,0x118(%rsp)
  40fb9a:	00 
  40fb9b:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  40fba2:	00 
  40fba3:	48 89 84 24 08 01 00 	mov    %rax,0x108(%rsp)
  40fbaa:	00 
  40fbab:	48 8d 84 24 00 01 00 	lea    0x100(%rsp),%rax
  40fbb2:	00 
  40fbb3:	48 89 84 24 a0 02 00 	mov    %rax,0x2a0(%rsp)
  40fbba:	00 
  40fbbb:	48 c7 c0 c0 27 43 00 	mov    $0x4327c0,%rax
  40fbc2:	4c 8b 30             	mov    (%rax),%r14
  40fbc5:	4c 89 b4 24 b8 02 00 	mov    %r14,0x2b8(%rsp)
  40fbcc:	00 
  40fbcd:	48 8d 84 24 b8 02 00 	lea    0x2b8(%rsp),%rax
  40fbd4:	00 
  40fbd5:	48 89 84 24 a8 02 00 	mov    %rax,0x2a8(%rsp)
  40fbdc:	00 
  40fbdd:	48 89 6c 24 10       	mov    %rbp,0x10(%rsp)
  40fbe2:	48 89 ac 24 10 01 00 	mov    %rbp,0x110(%rsp)
  40fbe9:	00 
  40fbea:	48 c7 c3 d0 1e 43 00 	mov    $0x431ed0,%rbx
  40fbf1:	48 89 9c 24 b0 02 00 	mov    %rbx,0x2b0(%rsp)
  40fbf8:	00 
  40fbf9:	48 8b bc 24 e0 02 00 	mov    0x2e0(%rsp),%rdi
  40fc00:	00 
  40fc01:	e8 6a b9 00 00       	call   41b570 <myl_qbe_heap>
  40fc06:	49 8b 75 00          	mov    0x0(%r13),%rsi
  40fc0a:	4d 8b 06             	mov    (%r14),%r8
  40fc0d:	48 8b 48 10          	mov    0x10(%rax),%rcx
  40fc11:	48 89 8c 24 40 02 00 	mov    %rcx,0x240(%rsp)
  40fc18:	00 
  40fc19:	4c 89 ac 24 58 02 00 	mov    %r13,0x258(%rsp)
  40fc20:	00 
  40fc21:	48 8d 8c 24 58 02 00 	lea    0x258(%rsp),%rcx
  40fc28:	00 
  40fc29:	48 89 8c 24 48 02 00 	mov    %rcx,0x248(%rsp)
  40fc30:	00 
  40fc31:	48 89 ac 24 50 02 00 	mov    %rbp,0x250(%rsp)
  40fc38:	00 
  40fc39:	48 8d 8c 24 40 02 00 	lea    0x240(%rsp),%rcx
  40fc40:	00 
  40fc41:	48 89 8c 24 60 02 00 	mov    %rcx,0x260(%rsp)
  40fc48:	00 
  40fc49:	4c 89 b4 24 78 02 00 	mov    %r14,0x278(%rsp)
  40fc50:	00 
  40fc51:	48 8d 8c 24 78 02 00 	lea    0x278(%rsp),%rcx
  40fc58:	00 
  40fc59:	48 89 8c 24 68 02 00 	mov    %rcx,0x268(%rsp)
  40fc60:	00 
  40fc61:	48 8d 8c 24 60 02 00 	lea    0x260(%rsp),%rcx
  40fc68:	00 
  40fc69:	48 89 8c 24 80 02 00 	mov    %rcx,0x280(%rsp)
  40fc70:	00 
  40fc71:	48 89 b4 24 98 02 00 	mov    %rsi,0x298(%rsp)
  40fc78:	00 
  40fc79:	48 8d 8c 24 98 02 00 	lea    0x298(%rsp),%rcx
  40fc80:	00 
  40fc81:	48 89 8c 24 88 02 00 	mov    %rcx,0x288(%rsp)
  40fc88:	00 
  40fc89:	48 c7 c1 f0 1c 43 00 	mov    $0x431cf0,%rcx
  40fc90:	48 89 8c 24 90 02 00 	mov    %rcx,0x290(%rsp)
  40fc97:	00 
  40fc98:	48 8d 8c 24 80 02 00 	lea    0x280(%rsp),%rcx
  40fc9f:	00 
  40fca0:	48 89 8c 24 c0 02 00 	mov    %rcx,0x2c0(%rsp)
  40fca7:	00 
  40fca8:	4c 89 b4 24 d8 02 00 	mov    %r14,0x2d8(%rsp)
  40fcaf:	00 
  40fcb0:	48 8d 8c 24 d8 02 00 	lea    0x2d8(%rsp),%rcx
  40fcb7:	00 
  40fcb8:	48 89 8c 24 c8 02 00 	mov    %rcx,0x2c8(%rsp)
  40fcbf:	00 
  40fcc0:	48 89 9c 24 70 02 00 	mov    %rbx,0x270(%rsp)
  40fcc7:	00 
  40fcc8:	48 89 9c 24 d0 02 00 	mov    %rbx,0x2d0(%rsp)
  40fccf:	00 
  40fcd0:	48 89 c7             	mov    %rax,%rdi
  40fcd3:	4c 89 f2             	mov    %r14,%rdx
  40fcd6:	31 c9                	xor    %ecx,%ecx
  40fcd8:	e8 e3 0e 01 00       	call   420bc0 <myl_native_bytes_buffer_append_range>
  40fcdd:	31 c0                	xor    %eax,%eax
  40fcdf:	48 81 c4 e8 04 00 00 	add    $0x4e8,%rsp
  40fce6:	5b                   	pop    %rbx
  40fce7:	41 5c                	pop    %r12
  40fce9:	41 5d                	pop    %r13
  40fceb:	41 5e                	pop    %r14
  40fced:	41 5f                	pop    %r15
  40fcef:	5d                   	pop    %rbp
  40fcf0:	c5 f8 77             	vzeroupper
  40fcf3:	c3                   	ret

Disassembly of section .fini:
