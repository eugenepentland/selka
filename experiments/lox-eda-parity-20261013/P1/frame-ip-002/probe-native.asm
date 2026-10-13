
.tmp/lox-eda-parity/P1/frame-ip-002/scalar-frame-probe:     file format elf64-x86-64


Disassembly of section .text:

0000000001040240 <main>:
 1040240:	55                   	push   %rbp
 1040241:	41 57                	push   %r15
 1040243:	41 56                	push   %r14
 1040245:	41 55                	push   %r13
 1040247:	41 54                	push   %r12
 1040249:	53                   	push   %rbx
 104024a:	50                   	push   %rax
 104024b:	48 89 f3             	mov    %rsi,%rbx
 104024e:	89 fd                	mov    %edi,%ebp
 1040250:	e8 6b 4e ff ff       	call   10350c0 <myl_core_start>
 1040255:	89 ef                	mov    %ebp,%edi
 1040257:	48 89 de             	mov    %rbx,%rsi
 104025a:	e8 e1 d3 fc ff       	call   100d640 <myl_core_args>
 104025f:	48 89 c3             	mov    %rax,%rbx
 1040262:	64 48 8b 3c 25 d0 fe 	mov    %fs:0xfffffffffffffed0,%rdi
 1040269:	ff ff 
 104026b:	48 85 ff             	test   %rdi,%rdi
 104026e:	0f 84 cc 00 00 00    	je     1040340 <main+0x100>
 1040274:	48 8b 07             	mov    (%rdi),%rax
 1040277:	64 48 89 04 25 d0 fe 	mov    %rax,%fs:0xfffffffffffffed0
 104027e:	ff ff 
 1040280:	c7 07 00 00 00 02    	movl   $0x2000000,(%rdi)
 1040286:	48 c7 47 08 00 00 00 	movq   $0x0,0x8(%rdi)
 104028d:	00 
 104028e:	48 c7 47 10 01 00 00 	movq   $0x1,0x10(%rdi)
 1040295:	00 
 1040296:	48 c7 47 18 00 00 00 	movq   $0x0,0x18(%rdi)
 104029d:	00 
 104029e:	31 d2                	xor    %edx,%edx
 10402a0:	48 89 d0             	mov    %rdx,%rax
 10402a3:	48 c1 e0 05          	shl    $0x5,%rax
 10402a7:	c5 fc 28 05 31 42 fc 	vmovaps -0x3bdcf(%rip),%ymm0        # 10044e0 <core_run_timed_out.message+0x320>
 10402ae:	ff 
 10402af:	c5 fc 11 44 07 20    	vmovups %ymm0,0x20(%rdi,%rax,1)
 10402b5:	48 ff c2             	inc    %rdx
 10402b8:	48 89 57 08          	mov    %rdx,0x8(%rdi)
 10402bc:	48 8b 43 08          	mov    0x8(%rbx),%rax
 10402c0:	31 c9                	xor    %ecx,%ecx
 10402c2:	48 83 f8 01          	cmp    $0x1,%rax
 10402c6:	0f 94 c1             	sete   %cl
 10402c9:	48 f7 d9             	neg    %rcx
 10402cc:	48 83 f8 02          	cmp    $0x2,%rax
 10402d0:	41 bf 01 00 00 00    	mov    $0x1,%r15d
 10402d6:	4c 0f 45 f9          	cmovne %rcx,%r15
 10402da:	48 83 f8 03          	cmp    $0x3,%rax
 10402de:	49 c7 c6 fe ff ff ff 	mov    $0xfffffffffffffffe,%r14
 10402e5:	4d 0f 45 f7          	cmovne %r15,%r14
 10402e9:	48 83 f8 04          	cmp    $0x4,%rax
 10402ed:	0f 85 96 00 00 00    	jne    1040389 <main+0x149>
 10402f3:	c5 f8 77             	vzeroupper
 10402f6:	e8 c5 c9 fc ff       	call   100ccc0 <myl_core_drop_owned>
 10402fb:	64 48 8b 04 25 c8 fe 	mov    %fs:0xfffffffffffffec8,%rax
 1040302:	ff ff 
 1040304:	48 85 c0             	test   %rax,%rax
 1040307:	74 6d                	je     1040376 <main+0x136>
 1040309:	48 8b 08             	mov    (%rax),%rcx
 104030c:	64 48 89 0c 25 c8 fe 	mov    %rcx,%fs:0xfffffffffffffec8
 1040313:	ff ff 
 1040315:	c7 00 00 00 00 01    	movl   $0x1000000,(%rax)
 104031b:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 104031f:	c5 f8 11 40 08       	vmovups %xmm0,0x8(%rax)
 1040324:	48 c7 40 18 00 00 00 	movq   $0x0,0x18(%rax)
 104032b:	00 
 104032c:	31 d2                	xor    %edx,%edx
 104032e:	48 8d 3d 3b 19 00 00 	lea    0x193b(%rip),%rdi        # 1041c70 <core_durable_error.verbs+0x30>
 1040335:	4c 89 f6             	mov    %r14,%rsi
 1040338:	c5 f8 77             	vzeroupper
 104033b:	e8 00 d7 fc ff       	call   100da40 <myl_core_trap>
 1040340:	bf 01 00 00 00       	mov    $0x1,%edi
 1040345:	be 20 00 00 00       	mov    $0x20,%esi
 104034a:	e8 b1 bb fc ff       	call   100bf00 <myl_core_list_new_slow>
 104034f:	48 89 c7             	mov    %rax,%rdi
 1040352:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1040356:	48 3b 50 10          	cmp    0x10(%rax),%rdx
 104035a:	0f 82 40 ff ff ff    	jb     10402a0 <main+0x60>
 1040360:	be 20 00 00 00       	mov    $0x20,%esi
 1040365:	e8 56 bc fc ff       	call   100bfc0 <myl_core_list_grow>
 104036a:	48 89 c7             	mov    %rax,%rdi
 104036d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1040371:	e9 2a ff ff ff       	jmp    10402a0 <main+0x60>
 1040376:	be 20 00 00 00       	mov    $0x20,%esi
 104037b:	31 ff                	xor    %edi,%edi
 104037d:	e8 7e bb fc ff       	call   100bf00 <myl_core_list_new_slow>
 1040382:	48 89 c7             	mov    %rax,%rdi
 1040385:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1040389:	48 8b 43 08          	mov    0x8(%rbx),%rax
 104038d:	49 39 d6             	cmp    %rdx,%r14
 1040390:	0f 83 a1 00 00 00    	jae    1040437 <main+0x1f7>
 1040396:	4d 89 f7             	mov    %r14,%r15
 1040399:	48 83 c0 28          	add    $0x28,%rax
 104039d:	49 c1 e7 05          	shl    $0x5,%r15
 10403a1:	4a 89 44 3f 30       	mov    %rax,0x30(%rdi,%r15,1)
 10403a6:	4c 8b 7f 20          	mov    0x20(%rdi),%r15
 10403aa:	4c 8b 67 28          	mov    0x28(%rdi),%r12
 10403ae:	4c 8b 6f 30          	mov    0x30(%rdi),%r13
 10403b2:	4c 8b 77 38          	mov    0x38(%rdi),%r14
 10403b6:	c5 f8 77             	vzeroupper
 10403b9:	e8 02 c9 fc ff       	call   100ccc0 <myl_core_drop_owned>
 10403be:	bf 01 00 00 00       	mov    $0x1,%edi
 10403c3:	4c 89 fe             	mov    %r15,%rsi
 10403c6:	e8 75 ec fc ff       	call   100f040 <myl_core_print_i64>
 10403cb:	bf 01 00 00 00       	mov    $0x1,%edi
 10403d0:	e8 6b b1 fc ff       	call   100b540 <myl_core_print_sep>
 10403d5:	bf 01 00 00 00       	mov    $0x1,%edi
 10403da:	4c 89 e6             	mov    %r12,%rsi
 10403dd:	e8 5e ec fc ff       	call   100f040 <myl_core_print_i64>
 10403e2:	bf 01 00 00 00       	mov    $0x1,%edi
 10403e7:	e8 54 b1 fc ff       	call   100b540 <myl_core_print_sep>
 10403ec:	bf 01 00 00 00       	mov    $0x1,%edi
 10403f1:	4c 89 ee             	mov    %r13,%rsi
 10403f4:	e8 47 ec fc ff       	call   100f040 <myl_core_print_i64>
 10403f9:	bf 01 00 00 00       	mov    $0x1,%edi
 10403fe:	e8 3d b1 fc ff       	call   100b540 <myl_core_print_sep>
 1040403:	bf 01 00 00 00       	mov    $0x1,%edi
 1040408:	4c 89 f6             	mov    %r14,%rsi
 104040b:	e8 30 ec fc ff       	call   100f040 <myl_core_print_i64>
 1040410:	bf 01 00 00 00       	mov    $0x1,%edi
 1040415:	e8 66 b1 fc ff       	call   100b580 <myl_core_print_end>
 104041a:	48 89 df             	mov    %rbx,%rdi
 104041d:	e8 9e c8 fc ff       	call   100ccc0 <myl_core_drop_owned>
 1040422:	31 ff                	xor    %edi,%edi
 1040424:	48 83 c4 08          	add    $0x8,%rsp
 1040428:	5b                   	pop    %rbx
 1040429:	41 5c                	pop    %r12
 104042b:	41 5d                	pop    %r13
 104042d:	41 5e                	pop    %r14
 104042f:	41 5f                	pop    %r15
 1040431:	5d                   	pop    %rbp
 1040432:	e9 c9 e0 fc ff       	jmp    100e500 <myl_core_exit>
 1040437:	4a 8d 0c 32          	lea    (%rdx,%r14,1),%rcx
 104043b:	4d 85 f6             	test   %r14,%r14
 104043e:	4c 0f 48 f9          	cmovs  %rcx,%r15
 1040442:	49 39 d7             	cmp    %rdx,%r15
 1040445:	0f 82 4e ff ff ff    	jb     1040399 <main+0x159>
 104044b:	e9 de fe ff ff       	jmp    104032e <main+0xee>

Disassembly of section .plt:
