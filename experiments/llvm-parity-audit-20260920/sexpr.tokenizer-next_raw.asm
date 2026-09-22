
.tmp/bench/armsset/maxperf/whole-o3.bin:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .text:

0000000000405fe0 <sexpr.tokenizer::next_raw>:
  405fe0:	55                   	push   %rbp
  405fe1:	41 57                	push   %r15
  405fe3:	41 56                	push   %r14
  405fe5:	41 55                	push   %r13
  405fe7:	41 54                	push   %r12
  405fe9:	53                   	push   %rbx
  405fea:	48 81 ec 08 03 00 00 	sub    $0x308,%rsp
  405ff1:	49 89 d7             	mov    %rdx,%r15
  405ff4:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
  405ff9:	48 89 b4 24 58 01 00 	mov    %rsi,0x158(%rsp)
  406000:	00 
  406001:	48 89 f7             	mov    %rsi,%rdi
  406004:	e8 67 55 01 00       	call   41b570 <myl_qbe_heap>
  406009:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  40600e:	4d 8b 2f             	mov    (%r15),%r13
  406011:	4d 8b 77 08          	mov    0x8(%r15),%r14
  406015:	49 8b 5d 00          	mov    0x0(%r13),%rbx
  406019:	49 8b 77 10          	mov    0x10(%r15),%rsi
  40601d:	49 8b 6f 18          	mov    0x18(%r15),%rbp
  406021:	49 39 de             	cmp    %rbx,%r14
  406024:	0f 8d 69 02 00 00    	jge    406293 <sexpr.tokenizer::next_raw+0x2b3>
  40602a:	4c 8d 25 27 f1 01 00 	lea    0x1f127(%rip),%r12        # 425158 <_fini+0x814>
  406031:	eb 1c                	jmp    40604f <sexpr.tokenizer::next_raw+0x6f>
  406033:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  40603a:	84 00 00 00 00 00 
  406040:	48 ff c5             	inc    %rbp
  406043:	49 ff c6             	inc    %r14
  406046:	49 39 de             	cmp    %rbx,%r14
  406049:	0f 8d 44 02 00 00    	jge    406293 <sexpr.tokenizer::next_raw+0x2b3>
  40604f:	4c 89 f0             	mov    %r14,%rax
  406052:	48 c1 f8 3f          	sar    $0x3f,%rax
  406056:	49 23 45 00          	and    0x0(%r13),%rax
  40605a:	4c 01 f0             	add    %r14,%rax
  40605d:	49 8b 4d 20          	mov    0x20(%r13),%rcx
  406061:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
  406065:	8d 48 f7             	lea    -0x9(%rax),%ecx
  406068:	83 f9 17             	cmp    $0x17,%ecx
  40606b:	77 13                	ja     406080 <sexpr.tokenizer::next_raw+0xa0>
  40606d:	49 63 04 8c          	movslq (%r12,%rcx,4),%rax
  406071:	4c 01 e0             	add    %r12,%rax
  406074:	ff e0                	jmp    *%rax
  406076:	48 ff c6             	inc    %rsi
  406079:	bd 01 00 00 00       	mov    $0x1,%ebp
  40607e:	eb c3                	jmp    406043 <sexpr.tokenizer::next_raw+0x63>
  406080:	83 f8 3b             	cmp    $0x3b,%eax
  406083:	0f 85 0a 02 00 00    	jne    406293 <sexpr.tokenizer::next_raw+0x2b3>
  406089:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
  40608e:	48 8b 40 10          	mov    0x10(%rax),%rax
  406092:	48 89 84 24 18 01 00 	mov    %rax,0x118(%rsp)
  406099:	00 
  40609a:	48 89 b4 24 60 01 00 	mov    %rsi,0x160(%rsp)
  4060a1:	00 
  4060a2:	48 c7 c0 f8 26 43 00 	mov    $0x4326f8,%rax
  4060a9:	48 8b 30             	mov    (%rax),%rsi
  4060ac:	4c 89 bc 24 30 01 00 	mov    %r15,0x130(%rsp)
  4060b3:	00 
  4060b4:	48 8d 84 24 30 01 00 	lea    0x130(%rsp),%rax
  4060bb:	00 
  4060bc:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  4060c3:	00 
  4060c4:	48 c7 c1 20 85 42 00 	mov    $0x428520,%rcx
  4060cb:	48 89 8c 24 28 01 00 	mov    %rcx,0x128(%rsp)
  4060d2:	00 
  4060d3:	48 8d 84 24 18 01 00 	lea    0x118(%rsp),%rax
  4060da:	00 
  4060db:	48 89 84 24 f8 00 00 	mov    %rax,0xf8(%rsp)
  4060e2:	00 
  4060e3:	4c 89 ac 24 10 01 00 	mov    %r13,0x110(%rsp)
  4060ea:	00 
  4060eb:	48 8d 84 24 10 01 00 	lea    0x110(%rsp),%rax
  4060f2:	00 
  4060f3:	48 89 84 24 00 01 00 	mov    %rax,0x100(%rsp)
  4060fa:	00 
  4060fb:	48 c7 c2 d0 1e 43 00 	mov    $0x431ed0,%rdx
  406102:	48 89 94 24 08 01 00 	mov    %rdx,0x108(%rsp)
  406109:	00 
  40610a:	48 8d 84 24 f8 00 00 	lea    0xf8(%rsp),%rax
  406111:	00 
  406112:	48 89 84 24 d8 00 00 	mov    %rax,0xd8(%rsp)
  406119:	00 
  40611a:	4c 89 ac 24 f0 00 00 	mov    %r13,0xf0(%rsp)
  406121:	00 
  406122:	48 8d 84 24 f0 00 00 	lea    0xf0(%rsp),%rax
  406129:	00 
  40612a:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
  406131:	00 
  406132:	48 89 94 24 e8 00 00 	mov    %rdx,0xe8(%rsp)
  406139:	00 
  40613a:	48 8d 84 24 d8 00 00 	lea    0xd8(%rsp),%rax
  406141:	00 
  406142:	48 89 84 24 b8 00 00 	mov    %rax,0xb8(%rsp)
  406149:	00 
  40614a:	48 c7 84 24 d0 00 00 	movq   $0x0,0xd0(%rsp)
  406151:	00 00 00 00 00 
  406156:	48 8d 84 24 d0 00 00 	lea    0xd0(%rsp),%rax
  40615d:	00 
  40615e:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  406165:	00 
  406166:	48 89 94 24 c8 00 00 	mov    %rdx,0xc8(%rsp)
  40616d:	00 
  40616e:	48 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%rax
  406175:	00 
  406176:	48 89 84 24 98 00 00 	mov    %rax,0x98(%rsp)
  40617d:	00 
  40617e:	48 c7 84 24 b0 00 00 	movq   $0x0,0xb0(%rsp)
  406185:	00 00 00 00 00 
  40618a:	48 8d 84 24 b0 00 00 	lea    0xb0(%rsp),%rax
  406191:	00 
  406192:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  406199:	00 
  40619a:	48 89 8c 24 a8 00 00 	mov    %rcx,0xa8(%rsp)
  4061a1:	00 
  4061a2:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  4061a9:	00 
  4061aa:	48 89 44 24 78       	mov    %rax,0x78(%rsp)
  4061af:	48 c7 84 24 90 00 00 	movq   $0x0,0x90(%rsp)
  4061b6:	00 00 00 00 00 
  4061bb:	48 8d 84 24 90 00 00 	lea    0x90(%rsp),%rax
  4061c2:	00 
  4061c3:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  4061ca:	00 
  4061cb:	48 89 8c 24 88 00 00 	mov    %rcx,0x88(%rsp)
  4061d2:	00 
  4061d3:	48 8d 44 24 78       	lea    0x78(%rsp),%rax
  4061d8:	48 89 44 24 58       	mov    %rax,0x58(%rsp)
  4061dd:	48 c7 44 24 70 00 00 	movq   $0x0,0x70(%rsp)
  4061e4:	00 00 
  4061e6:	48 8d 44 24 70       	lea    0x70(%rsp),%rax
  4061eb:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  4061f0:	48 89 4c 24 68       	mov    %rcx,0x68(%rsp)
  4061f5:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  4061fa:	48 89 44 24 38       	mov    %rax,0x38(%rsp)
  4061ff:	48 c7 44 24 50 00 00 	movq   $0x0,0x50(%rsp)
  406206:	00 00 
  406208:	48 8d 44 24 50       	lea    0x50(%rsp),%rax
  40620d:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  406212:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  406217:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40621c:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
  406221:	48 c7 44 24 30 00 00 	movq   $0x0,0x30(%rsp)
  406228:	00 00 
  40622a:	48 8d 44 24 30       	lea    0x30(%rsp),%rax
  40622f:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  406234:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
  406239:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40623e:	48 89 84 24 38 01 00 	mov    %rax,0x138(%rsp)
  406245:	00 
  406246:	48 89 b4 24 50 01 00 	mov    %rsi,0x150(%rsp)
  40624d:	00 
  40624e:	48 8d 84 24 50 01 00 	lea    0x150(%rsp),%rax
  406255:	00 
  406256:	48 89 84 24 40 01 00 	mov    %rax,0x140(%rsp)
  40625d:	00 
  40625e:	48 89 94 24 48 01 00 	mov    %rdx,0x148(%rsp)
  406265:	00 
  406266:	4c 89 ef             	mov    %r13,%rdi
  406269:	4c 89 f2             	mov    %r14,%rdx
  40626c:	e8 8f a3 01 00       	call   420600 <myl_native_bytes_find_any>
  406271:	48 8b b4 24 60 01 00 	mov    0x160(%rsp),%rsi
  406278:	00 
  406279:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
  40627d:	48 0f 44 c3          	cmove  %rbx,%rax
  406281:	4c 29 f5             	sub    %r14,%rbp
  406284:	48 01 c5             	add    %rax,%rbp
  406287:	49 89 c6             	mov    %rax,%r14
  40628a:	49 39 de             	cmp    %rbx,%r14
  40628d:	0f 8c bc fd ff ff    	jl     40604f <sexpr.tokenizer::next_raw+0x6f>
  406293:	49 39 de             	cmp    %rbx,%r14
  406296:	7d 4c                	jge    4062e4 <sexpr.tokenizer::next_raw+0x304>
  406298:	4c 89 f0             	mov    %r14,%rax
  40629b:	48 c1 f8 3f          	sar    $0x3f,%rax
  40629f:	49 23 45 00          	and    0x0(%r13),%rax
  4062a3:	4c 01 f0             	add    %r14,%rax
  4062a6:	49 8b 4d 20          	mov    0x20(%r13),%rcx
  4062aa:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
  4062ae:	83 f8 28             	cmp    $0x28,%eax
  4062b1:	74 6b                	je     40631e <sexpr.tokenizer::next_raw+0x33e>
  4062b3:	83 f8 29             	cmp    $0x29,%eax
  4062b6:	0f 85 b7 00 00 00    	jne    406373 <sexpr.tokenizer::next_raw+0x393>
  4062bc:	49 8d 56 01          	lea    0x1(%r14),%rdx
  4062c0:	48 8d 4d 01          	lea    0x1(%rbp),%rcx
  4062c4:	49 89 57 08          	mov    %rdx,0x8(%r15)
  4062c8:	49 89 77 10          	mov    %rsi,0x10(%r15)
  4062cc:	49 89 4f 18          	mov    %rcx,0x18(%r15)
  4062d0:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  4062d5:	c7 00 00 00 00 00    	movl   $0x0,(%rax)
  4062db:	c7 40 08 01 00 00 00 	movl   $0x1,0x8(%rax)
  4062e2:	eb 60                	jmp    406344 <sexpr.tokenizer::next_raw+0x364>
  4062e4:	4d 89 77 08          	mov    %r14,0x8(%r15)
  4062e8:	49 89 77 10          	mov    %rsi,0x10(%r15)
  4062ec:	49 89 6f 18          	mov    %rbp,0x18(%r15)
  4062f0:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  4062f5:	c7 00 00 00 00 00    	movl   $0x0,(%rax)
  4062fb:	c7 40 08 08 00 00 00 	movl   $0x8,0x8(%rax)
  406302:	4c 89 70 10          	mov    %r14,0x10(%rax)
  406306:	4c 89 70 18          	mov    %r14,0x18(%rax)
  40630a:	89 70 20             	mov    %esi,0x20(%rax)
  40630d:	89 68 24             	mov    %ebp,0x24(%rax)
  406310:	44 89 70 28          	mov    %r14d,0x28(%rax)
  406314:	4c 89 70 30          	mov    %r14,0x30(%rax)
  406318:	4c 89 70 38          	mov    %r14,0x38(%rax)
  40631c:	eb 40                	jmp    40635e <sexpr.tokenizer::next_raw+0x37e>
  40631e:	49 8d 56 01          	lea    0x1(%r14),%rdx
  406322:	48 8d 4d 01          	lea    0x1(%rbp),%rcx
  406326:	49 89 57 08          	mov    %rdx,0x8(%r15)
  40632a:	49 89 77 10          	mov    %rsi,0x10(%r15)
  40632e:	49 89 4f 18          	mov    %rcx,0x18(%r15)
  406332:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  406337:	c7 00 00 00 00 00    	movl   $0x0,(%rax)
  40633d:	c7 40 08 00 00 00 00 	movl   $0x0,0x8(%rax)
  406344:	4c 89 70 10          	mov    %r14,0x10(%rax)
  406348:	48 89 50 18          	mov    %rdx,0x18(%rax)
  40634c:	89 70 20             	mov    %esi,0x20(%rax)
  40634f:	89 68 24             	mov    %ebp,0x24(%rax)
  406352:	44 89 70 28          	mov    %r14d,0x28(%rax)
  406356:	4c 89 70 30          	mov    %r14,0x30(%rax)
  40635a:	48 89 50 38          	mov    %rdx,0x38(%rax)
  40635e:	48 81 c4 08 03 00 00 	add    $0x308,%rsp
  406365:	5b                   	pop    %rbx
  406366:	41 5c                	pop    %r12
  406368:	41 5d                	pop    %r13
  40636a:	41 5e                	pop    %r14
  40636c:	41 5f                	pop    %r15
  40636e:	5d                   	pop    %rbp
  40636f:	c5 f8 77             	vzeroupper
  406372:	c3                   	ret
  406373:	4d 89 77 08          	mov    %r14,0x8(%r15)
  406377:	49 89 77 10          	mov    %rsi,0x10(%r15)
  40637b:	49 89 6f 18          	mov    %rbp,0x18(%r15)
  40637f:	83 f8 22             	cmp    $0x22,%eax
  406382:	0f 85 03 02 00 00    	jne    40658b <sexpr.tokenizer::next_raw+0x5ab>
  406388:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
  40638d:	48 8b 40 10          	mov    0x10(%rax),%rax
  406391:	48 89 84 24 18 01 00 	mov    %rax,0x118(%rsp)
  406398:	00 
  406399:	4c 89 bc 24 30 01 00 	mov    %r15,0x130(%rsp)
  4063a0:	00 
  4063a1:	48 8d 84 24 30 01 00 	lea    0x130(%rsp),%rax
  4063a8:	00 
  4063a9:	48 89 84 24 20 01 00 	mov    %rax,0x120(%rsp)
  4063b0:	00 
  4063b1:	48 c7 c0 20 85 42 00 	mov    $0x428520,%rax
  4063b8:	48 89 84 24 28 01 00 	mov    %rax,0x128(%rsp)
  4063bf:	00 
  4063c0:	48 8d 8c 24 18 01 00 	lea    0x118(%rsp),%rcx
  4063c7:	00 
  4063c8:	48 89 8c 24 f8 00 00 	mov    %rcx,0xf8(%rsp)
  4063cf:	00 
  4063d0:	4c 89 ac 24 10 01 00 	mov    %r13,0x110(%rsp)
  4063d7:	00 
  4063d8:	48 8d 8c 24 10 01 00 	lea    0x110(%rsp),%rcx
  4063df:	00 
  4063e0:	48 89 8c 24 00 01 00 	mov    %rcx,0x100(%rsp)
  4063e7:	00 
  4063e8:	48 c7 c1 d0 1e 43 00 	mov    $0x431ed0,%rcx
  4063ef:	48 89 8c 24 08 01 00 	mov    %rcx,0x108(%rsp)
  4063f6:	00 
  4063f7:	48 8d 94 24 f8 00 00 	lea    0xf8(%rsp),%rdx
  4063fe:	00 
  4063ff:	48 89 94 24 d8 00 00 	mov    %rdx,0xd8(%rsp)
  406406:	00 
  406407:	4c 89 ac 24 f0 00 00 	mov    %r13,0xf0(%rsp)
  40640e:	00 
  40640f:	48 8d 94 24 f0 00 00 	lea    0xf0(%rsp),%rdx
  406416:	00 
  406417:	48 89 94 24 e0 00 00 	mov    %rdx,0xe0(%rsp)
  40641e:	00 
  40641f:	48 89 8c 24 e8 00 00 	mov    %rcx,0xe8(%rsp)
  406426:	00 
  406427:	48 8d 94 24 d8 00 00 	lea    0xd8(%rsp),%rdx
  40642e:	00 
  40642f:	48 89 94 24 b8 00 00 	mov    %rdx,0xb8(%rsp)
  406436:	00 
  406437:	4c 89 ac 24 d0 00 00 	mov    %r13,0xd0(%rsp)
  40643e:	00 
  40643f:	48 8d 94 24 d0 00 00 	lea    0xd0(%rsp),%rdx
  406446:	00 
  406447:	48 89 94 24 c0 00 00 	mov    %rdx,0xc0(%rsp)
  40644e:	00 
  40644f:	48 89 8c 24 c8 00 00 	mov    %rcx,0xc8(%rsp)
  406456:	00 
  406457:	48 8d 94 24 b8 00 00 	lea    0xb8(%rsp),%rdx
  40645e:	00 
  40645f:	48 89 94 24 98 00 00 	mov    %rdx,0x98(%rsp)
  406466:	00 
  406467:	48 c7 84 24 b0 00 00 	movq   $0x0,0xb0(%rsp)
  40646e:	00 00 00 00 00 
  406473:	48 8d 94 24 b0 00 00 	lea    0xb0(%rsp),%rdx
  40647a:	00 
  40647b:	48 89 94 24 a0 00 00 	mov    %rdx,0xa0(%rsp)
  406482:	00 
  406483:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  40648a:	00 
  40648b:	48 8d 94 24 98 00 00 	lea    0x98(%rsp),%rdx
  406492:	00 
  406493:	48 89 54 24 78       	mov    %rdx,0x78(%rsp)
  406498:	48 c7 84 24 90 00 00 	movq   $0x0,0x90(%rsp)
  40649f:	00 00 00 00 00 
  4064a4:	48 8d 94 24 90 00 00 	lea    0x90(%rsp),%rdx
  4064ab:	00 
  4064ac:	48 89 94 24 80 00 00 	mov    %rdx,0x80(%rsp)
  4064b3:	00 
  4064b4:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  4064bb:	00 
  4064bc:	48 8d 54 24 78       	lea    0x78(%rsp),%rdx
  4064c1:	48 89 54 24 58       	mov    %rdx,0x58(%rsp)
  4064c6:	48 c7 44 24 70 00 00 	movq   $0x0,0x70(%rsp)
  4064cd:	00 00 
  4064cf:	48 8d 54 24 70       	lea    0x70(%rsp),%rdx
  4064d4:	48 89 54 24 60       	mov    %rdx,0x60(%rsp)
  4064d9:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  4064de:	48 8d 54 24 58       	lea    0x58(%rsp),%rdx
  4064e3:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
  4064e8:	4c 89 7c 24 50       	mov    %r15,0x50(%rsp)
  4064ed:	48 8d 54 24 50       	lea    0x50(%rsp),%rdx
  4064f2:	48 89 54 24 40       	mov    %rdx,0x40(%rsp)
  4064f7:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  4064fc:	48 8d 54 24 38       	lea    0x38(%rsp),%rdx
  406501:	48 89 54 24 18       	mov    %rdx,0x18(%rsp)
  406506:	48 c7 44 24 30 00 00 	movq   $0x0,0x30(%rsp)
  40650d:	00 00 
  40650f:	48 8d 54 24 30       	lea    0x30(%rsp),%rdx
  406514:	48 89 54 24 20       	mov    %rdx,0x20(%rsp)
  406519:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
  40651e:	48 8d 4c 24 18       	lea    0x18(%rsp),%rcx
  406523:	48 89 8c 24 38 01 00 	mov    %rcx,0x138(%rsp)
  40652a:	00 
  40652b:	4c 89 bc 24 50 01 00 	mov    %r15,0x150(%rsp)
  406532:	00 
  406533:	48 8d 8c 24 50 01 00 	lea    0x150(%rsp),%rcx
  40653a:	00 
  40653b:	48 89 8c 24 40 01 00 	mov    %rcx,0x140(%rsp)
  406542:	00 
  406543:	48 89 84 24 48 01 00 	mov    %rax,0x148(%rsp)
  40654a:	00 
  40654b:	48 8d bc 24 c8 02 00 	lea    0x2c8(%rsp),%rdi
  406552:	00 
  406553:	48 8b b4 24 58 01 00 	mov    0x158(%rsp),%rsi
  40655a:	00 
  40655b:	4c 89 fa             	mov    %r15,%rdx
  40655e:	4c 89 f1             	mov    %r14,%rcx
  406561:	e8 fa dd ff ff       	call   404360 <sexpr.tokenizer::read_string>
  406566:	c5 fc 10 84 24 c8 02 	vmovups 0x2c8(%rsp),%ymm0
  40656d:	00 00 
  40656f:	c5 fc 10 8c 24 e8 02 	vmovups 0x2e8(%rsp),%ymm1
  406576:	00 00 
  406578:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  40657d:	c5 fc 11 48 20       	vmovups %ymm1,0x20(%rax)
  406582:	c5 fc 11 00          	vmovups %ymm0,(%rax)
  406586:	e9 d3 fd ff ff       	jmp    40635e <sexpr.tokenizer::next_raw+0x37e>
  40658b:	3c 30                	cmp    $0x30,%al
  40658d:	72 28                	jb     4065b7 <sexpr.tokenizer::next_raw+0x5d7>
  40658f:	3c 39                	cmp    $0x39,%al
  406591:	0f 86 73 01 00 00    	jbe    40670a <sexpr.tokenizer::next_raw+0x72a>
  406597:	3c 61                	cmp    $0x61,%al
  406599:	0f 82 b8 00 00 00    	jb     406657 <sexpr.tokenizer::next_raw+0x677>
  40659f:	3c 7b                	cmp    $0x7b,%al
  4065a1:	0f 92 c1             	setb   %cl
  4065a4:	83 f8 7e             	cmp    $0x7e,%eax
  4065a7:	0f 94 c0             	sete   %al
  4065aa:	08 c8                	or     %cl,%al
  4065ac:	0f 85 b8 00 00 00    	jne    40666a <sexpr.tokenizer::next_raw+0x68a>
  4065b2:	e9 16 01 00 00       	jmp    4066cd <sexpr.tokenizer::next_raw+0x6ed>
  4065b7:	83 f8 2f             	cmp    $0x2f,%eax
  4065ba:	0f 87 0d 01 00 00    	ja     4066cd <sexpr.tokenizer::next_raw+0x6ed>
  4065c0:	89 c0                	mov    %eax,%eax
  4065c2:	48 b9 00 00 00 00 22 	movabs $0x882200000000,%rcx
  4065c9:	88 00 00 
  4065cc:	48 0f a3 c1          	bt     %rax,%rcx
  4065d0:	73 59                	jae    40662b <sexpr.tokenizer::next_raw+0x64b>
  4065d2:	48 8d bc 24 20 02 00 	lea    0x220(%rsp),%rdi
  4065d9:	00 
  4065da:	4c 89 fa             	mov    %r15,%rdx
  4065dd:	4c 89 f1             	mov    %r14,%rcx
  4065e0:	e8 0b cd ff ff       	call   4032f0 <sexpr.tokenizer::read_operator>
  4065e5:	c5 fc 10 84 24 20 02 	vmovups 0x220(%rsp),%ymm0
  4065ec:	00 00 
  4065ee:	c5 fc 10 8c 24 38 02 	vmovups 0x238(%rsp),%ymm1
  4065f5:	00 00 
  4065f7:	c5 fc 11 8c 24 88 01 	vmovups %ymm1,0x188(%rsp)
  4065fe:	00 00 
  406600:	c5 fc 11 84 24 70 01 	vmovups %ymm0,0x170(%rsp)
  406607:	00 00 
  406609:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  40660e:	c7 00 00 00 00 00    	movl   $0x0,(%rax)
  406614:	c5 fc 10 84 24 6c 01 	vmovups 0x16c(%rsp),%ymm0
  40661b:	00 00 
  40661d:	c5 fc 10 8c 24 88 01 	vmovups 0x188(%rsp),%ymm1
  406624:	00 00 
  406626:	e9 33 01 00 00       	jmp    40675e <sexpr.tokenizer::next_raw+0x77e>
  40662b:	48 83 f8 2a          	cmp    $0x2a,%rax
  40662f:	74 39                	je     40666a <sexpr.tokenizer::next_raw+0x68a>
  406631:	48 83 f8 2d          	cmp    $0x2d,%rax
  406635:	0f 85 92 00 00 00    	jne    4066cd <sexpr.tokenizer::next_raw+0x6ed>
  40663b:	49 8d 46 01          	lea    0x1(%r14),%rax
  40663f:	48 39 d8             	cmp    %rbx,%rax
  406642:	7d 8e                	jge    4065d2 <sexpr.tokenizer::next_raw+0x5f2>
  406644:	49 83 fe ff          	cmp    $0xffffffffffffffff,%r14
  406648:	0f 8d a5 00 00 00    	jge    4066f3 <sexpr.tokenizer::next_raw+0x713>
  40664e:	49 8b 4d 00          	mov    0x0(%r13),%rcx
  406652:	e9 9e 00 00 00       	jmp    4066f5 <sexpr.tokenizer::next_raw+0x715>
  406657:	3c 41                	cmp    $0x41,%al
  406659:	72 68                	jb     4066c3 <sexpr.tokenizer::next_raw+0x6e3>
  40665b:	3c 5b                	cmp    $0x5b,%al
  40665d:	0f 93 c1             	setae  %cl
  406660:	83 f8 5f             	cmp    $0x5f,%eax
  406663:	0f 95 c0             	setne  %al
  406666:	84 c1                	test   %al,%cl
  406668:	75 63                	jne    4066cd <sexpr.tokenizer::next_raw+0x6ed>
  40666a:	48 8d bc 24 58 02 00 	lea    0x258(%rsp),%rdi
  406671:	00 
  406672:	4c 89 fa             	mov    %r15,%rdx
  406675:	4c 89 f1             	mov    %r14,%rcx
  406678:	e8 13 eb 00 00       	call   415190 <sexpr.tokenizer::read_atom>
  40667d:	c5 fc 10 84 24 58 02 	vmovups 0x258(%rsp),%ymm0
  406684:	00 00 
  406686:	c5 fc 10 8c 24 70 02 	vmovups 0x270(%rsp),%ymm1
  40668d:	00 00 
  40668f:	c5 fc 11 8c 24 c4 01 	vmovups %ymm1,0x1c4(%rsp)
  406696:	00 00 
  406698:	c5 fc 11 84 24 ac 01 	vmovups %ymm0,0x1ac(%rsp)
  40669f:	00 00 
  4066a1:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  4066a6:	c7 00 00 00 00 00    	movl   $0x0,(%rax)
  4066ac:	c5 fc 10 84 24 a8 01 	vmovups 0x1a8(%rsp),%ymm0
  4066b3:	00 00 
  4066b5:	c5 fc 10 8c 24 c4 01 	vmovups 0x1c4(%rsp),%ymm1
  4066bc:	00 00 
  4066be:	e9 9b 00 00 00       	jmp    40675e <sexpr.tokenizer::next_raw+0x77e>
  4066c3:	04 c4                	add    $0xc4,%al
  4066c5:	3c 02                	cmp    $0x2,%al
  4066c7:	0f 86 05 ff ff ff    	jbe    4065d2 <sexpr.tokenizer::next_raw+0x5f2>
  4066cd:	48 c7 c0 40 27 43 00 	mov    $0x432740,%rax
  4066d4:	48 8b 08             	mov    (%rax),%rcx
  4066d7:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  4066dc:	c7 00 01 00 00 00    	movl   $0x1,(%rax)
  4066e2:	48 89 48 08          	mov    %rcx,0x8(%rax)
  4066e6:	4c 89 70 10          	mov    %r14,0x10(%rax)
  4066ea:	48 89 70 18          	mov    %rsi,0x18(%rax)
  4066ee:	e9 6b fc ff ff       	jmp    40635e <sexpr.tokenizer::next_raw+0x37e>
  4066f3:	31 c9                	xor    %ecx,%ecx
  4066f5:	48 01 c1             	add    %rax,%rcx
  4066f8:	49 8b 45 20          	mov    0x20(%r13),%rax
  4066fc:	0f b6 04 08          	movzbl (%rax,%rcx,1),%eax
  406700:	04 c6                	add    $0xc6,%al
  406702:	3c f6                	cmp    $0xf6,%al
  406704:	0f 82 c8 fe ff ff    	jb     4065d2 <sexpr.tokenizer::next_raw+0x5f2>
  40670a:	48 8d bc 24 90 02 00 	lea    0x290(%rsp),%rdi
  406711:	00 
  406712:	4c 89 fa             	mov    %r15,%rdx
  406715:	4c 89 f1             	mov    %r14,%rcx
  406718:	e8 b3 15 00 00       	call   407cd0 <sexpr.tokenizer::read_number>
  40671d:	c5 fc 10 84 24 90 02 	vmovups 0x290(%rsp),%ymm0
  406724:	00 00 
  406726:	c5 fc 10 8c 24 a8 02 	vmovups 0x2a8(%rsp),%ymm1
  40672d:	00 00 
  40672f:	c5 fc 11 8c 24 00 02 	vmovups %ymm1,0x200(%rsp)
  406736:	00 00 
  406738:	c5 fc 11 84 24 e8 01 	vmovups %ymm0,0x1e8(%rsp)
  40673f:	00 00 
  406741:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  406746:	c7 00 00 00 00 00    	movl   $0x0,(%rax)
  40674c:	c5 fc 10 84 24 e4 01 	vmovups 0x1e4(%rsp),%ymm0
  406753:	00 00 
  406755:	c5 fc 10 8c 24 00 02 	vmovups 0x200(%rsp),%ymm1
  40675c:	00 00 
  40675e:	c5 fc 11 40 04       	vmovups %ymm0,0x4(%rax)
  406763:	c5 fc 11 48 20       	vmovups %ymm1,0x20(%rax)
  406768:	e9 f1 fb ff ff       	jmp    40635e <sexpr.tokenizer::next_raw+0x37e>

Disassembly of section .fini:
