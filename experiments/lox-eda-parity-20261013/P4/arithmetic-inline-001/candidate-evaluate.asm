
.tmp/lox-eda-parity/P4/arithmetic-inline-001/candidate/lox:     file format elf64-x86-64


Disassembly of section .text:

0000000001064fd0 <my.interpreter::evaluate>:
 1064fd0:	55                   	push   %rbp
 1064fd1:	41 57                	push   %r15
 1064fd3:	41 56                	push   %r14
 1064fd5:	41 55                	push   %r13
 1064fd7:	41 54                	push   %r12
 1064fd9:	53                   	push   %rbx
 1064fda:	48 81 ec a8 04 00 00 	sub    $0x4a8,%rsp
 1064fe1:	48 89 d3             	mov    %rdx,%rbx
 1064fe4:	48 89 f5             	mov    %rsi,%rbp
 1064fe7:	49 89 fe             	mov    %rdi,%r14
 1064fea:	48 8b b4 24 00 05 00 	mov    0x500(%rsp),%rsi
 1064ff1:	00 
 1064ff2:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 1064ff6:	48 39 d6             	cmp    %rdx,%rsi
 1064ff9:	0f 83 7f 1a 00 00    	jae    1066a7e <my.interpreter::evaluate+0x1aae>
 1064fff:	48 89 f0             	mov    %rsi,%rax
 1065002:	44 0f b6 ac 24 f0 04 	movzbl 0x4f0(%rsp),%r13d
 1065009:	00 00 
 106500b:	4c 8b bc 24 f8 04 00 	mov    0x4f8(%rsp),%r15
 1065012:	00 
 1065013:	4c 8b 9c 24 e8 04 00 	mov    0x4e8(%rsp),%r11
 106501a:	00 
 106501b:	48 6b d0 70          	imul   $0x70,%rax,%rdx
 106501f:	48 8d 04 2a          	lea    (%rdx,%rbp,1),%rax
 1065023:	48 83 c0 20          	add    $0x20,%rax
 1065027:	8b 74 15 20          	mov    0x20(%rbp,%rdx,1),%esi
 106502b:	48 83 fe 0a          	cmp    $0xa,%rsi
 106502f:	0f 87 54 0b 00 00    	ja     1065b89 <my.interpreter::evaluate+0xbb9>
 1065035:	48 8b bc 24 08 05 00 	mov    0x508(%rsp),%rdi
 106503c:	00 
 106503d:	4c 8b a4 24 e0 04 00 	mov    0x4e0(%rsp),%r12
 1065044:	00 
 1065045:	48 8d 15 30 26 fa ff 	lea    -0x5d9d0(%rip),%rdx        # 100767c <core_number_pairs+0x41c>
 106504c:	48 63 34 b2          	movslq (%rdx,%rsi,4),%rsi
 1065050:	48 01 d6             	add    %rdx,%rsi
 1065053:	4c 89 04 24          	mov    %r8,(%rsp)
 1065057:	ff e6                	jmp    *%rsi
 1065059:	48 8b 50 20          	mov    0x20(%rax),%rdx
 106505d:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
 1065062:	48 8b 50 30          	mov    0x30(%rax),%rdx
 1065066:	48 89 54 24 20       	mov    %rdx,0x20(%rsp)
 106506b:	48 89 da             	mov    %rbx,%rdx
 106506e:	48 8b 58 40          	mov    0x40(%rax),%rbx
 1065072:	48 8b 70 48          	mov    0x48(%rax),%rsi
 1065076:	48 89 74 24 18       	mov    %rsi,0x18(%rsp)
 106507b:	45 0f b6 d5          	movzbl %r13b,%r10d
 106507f:	48 8d 7c 24 48       	lea    0x48(%rsp),%rdi
 1065084:	48 89 ee             	mov    %rbp,%rsi
 1065087:	4d 89 cd             	mov    %r9,%r13
 106508a:	ff b4 24 08 05 00 00 	push   0x508(%rsp)
 1065091:	ff 70 38             	push   0x38(%rax)
 1065094:	41 57                	push   %r15
 1065096:	41 52                	push   %r10
 1065098:	41 53                	push   %r11
 106509a:	41 54                	push   %r12
 106509c:	e8 2f ff ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10650a1:	48 83 c4 30          	add    $0x30,%rsp
 10650a5:	c5 f8 10 84 24 48 01 	vmovups 0x148(%rsp),%xmm0
 10650ac:	00 00 
 10650ae:	4c 8b a4 24 58 01 00 	mov    0x158(%rsp),%r12
 10650b5:	00 
 10650b6:	80 7c 24 48 01       	cmpb   $0x1,0x48(%rsp)
 10650bb:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 10650c0:	0f 84 63 15 00 00    	je     1066629 <my.interpreter::evaluate+0x1659>
 10650c6:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 10650ca:	0f 84 b9 10 00 00    	je     1066189 <my.interpreter::evaluate+0x11b9>
 10650d0:	49 8b b5 a8 00 00 00 	mov    0xa8(%r13),%rsi
 10650d7:	48 85 db             	test   %rbx,%rbx
 10650da:	0f 8e 3f 0e 00 00    	jle    1065f1f <my.interpreter::evaluate+0xf4f>
 10650e0:	49 8b 45 00          	mov    0x0(%r13),%rax
 10650e4:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10650e8:	48 83 c0 20          	add    $0x20,%rax
 10650ec:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10650f3:	0f 1f 84 00 00 00 00 
 10650fa:	00 
 10650fb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1065100:	48 39 d6             	cmp    %rdx,%rsi
 1065103:	73 22                	jae    1065127 <my.interpreter::evaluate+0x157>
 1065105:	48 89 f1             	mov    %rsi,%rcx
 1065108:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 106510c:	83 3c 08 09          	cmpl   $0x9,(%rax,%rcx,1)
 1065110:	0f 85 ee 1d 00 00    	jne    1066f04 <my.interpreter::evaluate+0x1f34>
 1065116:	48 01 c1             	add    %rax,%rcx
 1065119:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 106511d:	48 ff cb             	dec    %rbx
 1065120:	75 de                	jne    1065100 <my.interpreter::evaluate+0x130>
 1065122:	e9 f8 0d 00 00       	jmp    1065f1f <my.interpreter::evaluate+0xf4f>
 1065127:	48 89 f1             	mov    %rsi,%rcx
 106512a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106512e:	48 21 d1             	and    %rdx,%rcx
 1065131:	48 01 f1             	add    %rsi,%rcx
 1065134:	48 39 d1             	cmp    %rdx,%rcx
 1065137:	72 cf                	jb     1065108 <my.interpreter::evaluate+0x138>
 1065139:	48 8d 3d a0 02 02 00 	lea    0x202a0(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065140:	e8 bb f5 fb ff       	call   1024700 <myl_core_trap>
 1065145:	45 0f b6 d5          	movzbl %r13b,%r10d
 1065149:	4d 89 dd             	mov    %r11,%r13
 106514c:	49 89 fb             	mov    %rdi,%r11
 106514f:	48 8d bc 24 90 03 00 	lea    0x390(%rsp),%rdi
 1065156:	00 
 1065157:	48 89 ee             	mov    %rbp,%rsi
 106515a:	48 89 da             	mov    %rbx,%rdx
 106515d:	41 53                	push   %r11
 106515f:	ff 70 08             	push   0x8(%rax)
 1065162:	41 57                	push   %r15
 1065164:	41 52                	push   %r10
 1065166:	41 55                	push   %r13
 1065168:	41 54                	push   %r12
 106516a:	e8 61 fe ff ff       	call   1064fd0 <my.interpreter::evaluate>
 106516f:	48 83 c4 30          	add    $0x30,%rsp
 1065173:	0f b6 84 24 90 03 00 	movzbl 0x390(%rsp),%eax
 106517a:	00 
 106517b:	c5 f9 10 84 24 98 03 	vmovupd 0x398(%rsp),%xmm0
 1065182:	00 00 
 1065184:	48 8b 8c 24 90 04 00 	mov    0x490(%rsp),%rcx
 106518b:	00 
 106518c:	0f b6 94 24 98 04 00 	movzbl 0x498(%rsp),%edx
 1065193:	00 
 1065194:	48 8b b4 24 a0 04 00 	mov    0x4a0(%rsp),%rsi
 106519b:	00 
 106519c:	48 83 f8 01          	cmp    $0x1,%rax
 10651a0:	0f 84 1b 14 00 00    	je     10665c1 <my.interpreter::evaluate+0x15f1>
 10651a6:	49 89 06             	mov    %rax,(%r14)
 10651a9:	c4 c1 79 11 46 08    	vmovupd %xmm0,0x8(%r14)
 10651af:	49 89 8e 00 01 00 00 	mov    %rcx,0x100(%r14)
 10651b6:	49 89 96 08 01 00 00 	mov    %rdx,0x108(%r14)
 10651bd:	49 89 b6 10 01 00 00 	mov    %rsi,0x110(%r14)
 10651c4:	e9 4c 18 00 00       	jmp    1066a15 <my.interpreter::evaluate+0x1a45>
 10651c9:	48 8b 78 30          	mov    0x30(%rax),%rdi
 10651cd:	49 8b 09             	mov    (%r9),%rcx
 10651d0:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 10651d7:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10651db:	48 85 ff             	test   %rdi,%rdi
 10651de:	0f 8e 25 0a 00 00    	jle    1065c09 <my.interpreter::evaluate+0xc39>
 10651e4:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 10651e8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10651ef:	0f 1f 84 00 00 00 00 
 10651f6:	00 
 10651f7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10651fe:	00 00 
 1065200:	48 39 d6             	cmp    %rdx,%rsi
 1065203:	73 23                	jae    1065228 <my.interpreter::evaluate+0x258>
 1065205:	49 89 f2             	mov    %rsi,%r10
 1065208:	49 6b f2 38          	imul   $0x38,%r10,%rsi
 106520c:	41 83 3c 30 09       	cmpl   $0x9,(%r8,%rsi,1)
 1065211:	0f 85 bd 1c 00 00    	jne    1066ed4 <my.interpreter::evaluate+0x1f04>
 1065217:	4c 01 c6             	add    %r8,%rsi
 106521a:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 106521e:	48 ff cf             	dec    %rdi
 1065221:	75 dd                	jne    1065200 <my.interpreter::evaluate+0x230>
 1065223:	e9 e1 09 00 00       	jmp    1065c09 <my.interpreter::evaluate+0xc39>
 1065228:	49 89 f2             	mov    %rsi,%r10
 106522b:	49 c1 fa 3f          	sar    $0x3f,%r10
 106522f:	49 21 d2             	and    %rdx,%r10
 1065232:	49 01 f2             	add    %rsi,%r10
 1065235:	49 39 d2             	cmp    %rdx,%r10
 1065238:	72 ce                	jb     1065208 <my.interpreter::evaluate+0x238>
 106523a:	48 8d 3d 9f 01 02 00 	lea    0x2019f(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065241:	e8 ba f4 fb ff       	call   1024700 <myl_core_trap>
 1065246:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 106524b:	48 8b 50 28          	mov    0x28(%rax),%rdx
 106524f:	48 89 54 24 18       	mov    %rdx,0x18(%rsp)
 1065254:	4c 8b 70 38          	mov    0x38(%rax),%r14
 1065258:	45 0f b6 d5          	movzbl %r13b,%r10d
 106525c:	49 89 fb             	mov    %rdi,%r11
 106525f:	48 8d 7c 24 48       	lea    0x48(%rsp),%rdi
 1065264:	48 89 ee             	mov    %rbp,%rsi
 1065267:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
 106526c:	48 89 da             	mov    %rbx,%rdx
 106526f:	48 89 cb             	mov    %rcx,%rbx
 1065272:	4d 89 cd             	mov    %r9,%r13
 1065275:	41 53                	push   %r11
 1065277:	ff 70 08             	push   0x8(%rax)
 106527a:	41 57                	push   %r15
 106527c:	41 52                	push   %r10
 106527e:	ff b4 24 08 05 00 00 	push   0x508(%rsp)
 1065285:	41 54                	push   %r12
 1065287:	e8 44 fd ff ff       	call   1064fd0 <my.interpreter::evaluate>
 106528c:	48 83 c4 30          	add    $0x30,%rsp
 1065290:	48 8b 84 24 48 01 00 	mov    0x148(%rsp),%rax
 1065297:	00 
 1065298:	0f b6 8c 24 50 01 00 	movzbl 0x150(%rsp),%ecx
 106529f:	00 
 10652a0:	4c 8b 94 24 58 01 00 	mov    0x158(%rsp),%r10
 10652a7:	00 
 10652a8:	80 7c 24 48 01       	cmpb   $0x1,0x48(%rsp)
 10652ad:	0f 84 29 13 00 00    	je     10665dc <my.interpreter::evaluate+0x160c>
 10652b3:	4d 8b 7e 08          	mov    0x8(%r14),%r15
 10652b7:	4d 85 ff             	test   %r15,%r15
 10652ba:	0f 84 2c 0e 00 00    	je     10660ec <my.interpreter::evaluate+0x111c>
 10652c0:	45 31 e4             	xor    %r12d,%r12d
 10652c3:	4c 8b 04 24          	mov    (%rsp),%r8
 10652c7:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10652ce:	0f 1f 84 00 00 00 00 
 10652d5:	00 
 10652d6:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10652dd:	0f 1f 84 00 00 00 00 
 10652e4:	00 
 10652e5:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10652ec:	0f 1f 84 00 00 00 00 
 10652f3:	00 
 10652f4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10652fb:	00 00 00 00 00 
 1065300:	44 0f b6 d9          	movzbl %cl,%r11d
 1065304:	48 8d bc 24 60 01 00 	lea    0x160(%rsp),%rdi
 106530b:	00 
 106530c:	48 89 ee             	mov    %rbp,%rsi
 106530f:	48 8b 54 24 20       	mov    0x20(%rsp),%rdx
 1065314:	48 89 d9             	mov    %rbx,%rcx
 1065317:	4d 89 e9             	mov    %r13,%r9
 106531a:	ff b4 24 08 05 00 00 	push   0x508(%rsp)
 1065321:	43 ff 74 e6 20       	push   0x20(%r14,%r12,8)
 1065326:	41 52                	push   %r10
 1065328:	41 53                	push   %r11
 106532a:	50                   	push   %rax
 106532b:	ff b4 24 08 05 00 00 	push   0x508(%rsp)
 1065332:	e8 99 fc ff ff       	call   1064fd0 <my.interpreter::evaluate>
 1065337:	48 83 c4 30          	add    $0x30,%rsp
 106533b:	48 8b 84 24 60 02 00 	mov    0x260(%rsp),%rax
 1065342:	00 
 1065343:	0f b6 8c 24 68 02 00 	movzbl 0x268(%rsp),%ecx
 106534a:	00 
 106534b:	4c 8b 94 24 70 02 00 	mov    0x270(%rsp),%r10
 1065352:	00 
 1065353:	80 bc 24 60 01 00 00 	cmpb   $0x1,0x160(%rsp)
 106535a:	01 
 106535b:	0f 84 94 14 00 00    	je     10667f5 <my.interpreter::evaluate+0x1825>
 1065361:	49 ff c4             	inc    %r12
 1065364:	4d 39 e7             	cmp    %r12,%r15
 1065367:	4c 8b 04 24          	mov    (%rsp),%r8
 106536b:	75 93                	jne    1065300 <my.interpreter::evaluate+0x330>
 106536d:	4d 8b 5e 08          	mov    0x8(%r14),%r11
 1065371:	4c 8b a4 24 e0 04 00 	mov    0x4e0(%rsp),%r12
 1065378:	00 
 1065379:	e9 75 0d 00 00       	jmp    10660f3 <my.interpreter::evaluate+0x1123>
 106537e:	48 8b 50 28          	mov    0x28(%rax),%rdx
 1065382:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
 1065387:	48 8b 50 38          	mov    0x38(%rax),%rdx
 106538b:	48 89 54 24 20       	mov    %rdx,0x20(%rsp)
 1065390:	45 0f b6 d5          	movzbl %r13b,%r10d
 1065394:	4d 89 dd             	mov    %r11,%r13
 1065397:	49 89 fb             	mov    %rdi,%r11
 106539a:	48 8d 7c 24 48       	lea    0x48(%rsp),%rdi
 106539f:	48 89 ee             	mov    %rbp,%rsi
 10653a2:	48 89 da             	mov    %rbx,%rdx
 10653a5:	41 53                	push   %r11
 10653a7:	ff 70 08             	push   0x8(%rax)
 10653aa:	41 57                	push   %r15
 10653ac:	41 52                	push   %r10
 10653ae:	41 55                	push   %r13
 10653b0:	41 54                	push   %r12
 10653b2:	4c 89 cb             	mov    %r9,%rbx
 10653b5:	e8 16 fc ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10653ba:	48 83 c4 30          	add    $0x30,%rsp
 10653be:	c5 f8 10 84 24 48 01 	vmovups 0x148(%rsp),%xmm0
 10653c5:	00 00 
 10653c7:	4c 8b a4 24 58 01 00 	mov    0x158(%rsp),%r12
 10653ce:	00 
 10653cf:	80 7c 24 48 01       	cmpb   $0x1,0x48(%rsp)
 10653d4:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 10653d9:	0f 84 0e 12 00 00    	je     10665ed <my.interpreter::evaluate+0x161d>
 10653df:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 10653e6:	48 89 c6             	mov    %rax,%rsi
 10653e9:	48 ff ce             	dec    %rsi
 10653ec:	0f 80 fc 1b 00 00    	jo     1066fee <my.interpreter::evaluate+0x201e>
 10653f2:	48 89 df             	mov    %rbx,%rdi
 10653f5:	48 8b 43 78          	mov    0x78(%rbx),%rax
 10653f9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10653fd:	48 39 d6             	cmp    %rdx,%rsi
 1065400:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 1065405:	0f 83 c5 17 00 00    	jae    1066bd0 <my.interpreter::evaluate+0x1c00>
 106540b:	49 89 f5             	mov    %rsi,%r13
 106540e:	49 c1 e5 04          	shl    $0x4,%r13
 1065412:	4e 8b 74 28 20       	mov    0x20(%rax,%r13,1),%r14
 1065417:	41 0f b6 ce          	movzbl %r14b,%ecx
 106541b:	83 f9 03             	cmp    $0x3,%ecx
 106541e:	0f 85 3b 0f 00 00    	jne    106635f <my.interpreter::evaluate+0x138f>
 1065424:	4e 8b 7c 28 28       	mov    0x28(%rax,%r13,1),%r15
 1065429:	48 8b 07             	mov    (%rdi),%rax
 106542c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065430:	4c 89 f9             	mov    %r15,%rcx
 1065433:	49 39 d7             	cmp    %rdx,%r15
 1065436:	0f 83 41 18 00 00    	jae    1066c7d <my.interpreter::evaluate+0x1cad>
 106543c:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065440:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 1065445:	0f 85 14 0f 00 00    	jne    106635f <my.interpreter::evaluate+0x138f>
 106544b:	4c 89 64 24 18       	mov    %r12,0x18(%rsp)
 1065450:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 1065455:	48 89 ee             	mov    %rbp,%rsi
 1065458:	49 89 fc             	mov    %rdi,%r12
 106545b:	e8 c0 3e 00 00       	call   1069320 <my.heap::string_hash>
 1065460:	89 c3                	mov    %eax,%ebx
 1065462:	4c 89 e7             	mov    %r12,%rdi
 1065465:	4c 89 fe             	mov    %r15,%rsi
 1065468:	48 89 ea             	mov    %rbp,%rdx
 106546b:	89 c1                	mov    %eax,%ecx
 106546d:	e8 8e 44 00 00       	call   1069900 <my.heap::instance_field>
 1065472:	3c 01                	cmp    $0x1,%al
 1065474:	0f 85 16 0b 00 00    	jne    1065f90 <my.interpreter::evaluate+0xfc0>
 106547a:	31 c0                	xor    %eax,%eax
 106547c:	49 3b 84 24 80 00 00 	cmp    0x80(%r12),%rax
 1065483:	00 
 1065484:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 1065489:	0f 80 b5 1c 00 00    	jo     1067144 <my.interpreter::evaluate+0x2174>
 106548f:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1065494:	4a 8d 34 28          	lea    (%rax,%r13,1),%rsi
 1065498:	48 83 c6 20          	add    $0x20,%rsi
 106549c:	0f b6 d2             	movzbl %dl,%edx
 106549f:	4a 89 54 28 20       	mov    %rdx,0x20(%rax,%r13,1)
 10654a4:	c5 f9 28 04 24       	vmovapd (%rsp),%xmm0
 10654a9:	e9 7c 0b 00 00       	jmp    106602a <my.interpreter::evaluate+0x105a>
 10654ae:	48 8b 50 28          	mov    0x28(%rax),%rdx
 10654b2:	48 89 54 24 40       	mov    %rdx,0x40(%rsp)
 10654b7:	48 8b 50 38          	mov    0x38(%rax),%rdx
 10654bb:	48 89 54 24 18       	mov    %rdx,0x18(%rsp)
 10654c0:	48 8b 50 40          	mov    0x40(%rax),%rdx
 10654c4:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
 10654c9:	45 0f b6 d5          	movzbl %r13b,%r10d
 10654cd:	49 89 fb             	mov    %rdi,%r11
 10654d0:	48 8d 7c 24 48       	lea    0x48(%rsp),%rdi
 10654d5:	48 89 ee             	mov    %rbp,%rsi
 10654d8:	49 89 dd             	mov    %rbx,%r13
 10654db:	48 89 da             	mov    %rbx,%rdx
 10654de:	48 89 cb             	mov    %rcx,%rbx
 10654e1:	41 53                	push   %r11
 10654e3:	ff 70 08             	push   0x8(%rax)
 10654e6:	41 57                	push   %r15
 10654e8:	41 52                	push   %r10
 10654ea:	ff b4 24 08 05 00 00 	push   0x508(%rsp)
 10654f1:	41 54                	push   %r12
 10654f3:	4d 89 cf             	mov    %r9,%r15
 10654f6:	e8 d5 fa ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10654fb:	48 83 c4 30          	add    $0x30,%rsp
 10654ff:	4c 8b 9c 24 48 01 00 	mov    0x148(%rsp),%r11
 1065506:	00 
 1065507:	48 8b 84 24 50 01 00 	mov    0x150(%rsp),%rax
 106550e:	00 
 106550f:	44 0f b6 c0          	movzbl %al,%r8d
 1065513:	4c 8b 94 24 58 01 00 	mov    0x158(%rsp),%r10
 106551a:	00 
 106551b:	80 7c 24 48 01       	cmpb   $0x1,0x48(%rsp)
 1065520:	0f 84 e9 10 00 00    	je     106660f <my.interpreter::evaluate+0x163f>
 1065526:	49 8b 87 80 00 00 00 	mov    0x80(%r15),%rax
 106552d:	48 89 c6             	mov    %rax,%rsi
 1065530:	48 ff ce             	dec    %rsi
 1065533:	0f 80 c9 1a 00 00    	jo     1067002 <my.interpreter::evaluate+0x2032>
 1065539:	4d 89 f9             	mov    %r15,%r9
 106553c:	4d 89 d7             	mov    %r10,%r15
 106553f:	4c 89 44 24 20       	mov    %r8,0x20(%rsp)
 1065544:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065548:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106554c:	48 39 d6             	cmp    %rdx,%rsi
 106554f:	4c 8b 04 24          	mov    (%rsp),%r8
 1065553:	48 89 d9             	mov    %rbx,%rcx
 1065556:	0f 83 96 16 00 00    	jae    1066bf2 <my.interpreter::evaluate+0x1c22>
 106555c:	48 89 f7             	mov    %rsi,%rdi
 106555f:	4d 89 ea             	mov    %r13,%r10
 1065562:	48 c1 e7 04          	shl    $0x4,%rdi
 1065566:	80 7c 38 20 03       	cmpb   $0x3,0x20(%rax,%rdi,1)
 106556b:	0f 85 1f 0e 00 00    	jne    1066390 <my.interpreter::evaluate+0x13c0>
 1065571:	48 8b 74 38 28       	mov    0x28(%rax,%rdi,1),%rsi
 1065576:	49 8b 01             	mov    (%r9),%rax
 1065579:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106557d:	48 39 d6             	cmp    %rdx,%rsi
 1065580:	0f 83 1c 17 00 00    	jae    1066ca2 <my.interpreter::evaluate+0x1cd2>
 1065586:	48 89 f7             	mov    %rsi,%rdi
 1065589:	48 6b d7 38          	imul   $0x38,%rdi,%rdx
 106558d:	83 7c 10 20 07       	cmpl   $0x7,0x20(%rax,%rdx,1)
 1065592:	0f 85 f8 0d 00 00    	jne    1066390 <my.interpreter::evaluate+0x13c0>
 1065598:	48 8d bc 24 60 01 00 	lea    0x160(%rsp),%rdi
 106559f:	00 
 10655a0:	48 89 ee             	mov    %rbp,%rsi
 10655a3:	4c 89 d2             	mov    %r10,%rdx
 10655a6:	ff b4 24 08 05 00 00 	push   0x508(%rsp)
 10655ad:	ff 74 24 40          	push   0x40(%rsp)
 10655b1:	41 57                	push   %r15
 10655b3:	ff 74 24 38          	push   0x38(%rsp)
 10655b7:	41 53                	push   %r11
 10655b9:	41 54                	push   %r12
 10655bb:	4c 89 cb             	mov    %r9,%rbx
 10655be:	e8 0d fa ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10655c3:	48 83 c4 30          	add    $0x30,%rsp
 10655c7:	48 8b ac 24 60 02 00 	mov    0x260(%rsp),%rbp
 10655ce:	00 
 10655cf:	44 0f b6 84 24 68 02 	movzbl 0x268(%rsp),%r8d
 10655d6:	00 00 
 10655d8:	4c 8b 94 24 70 02 00 	mov    0x270(%rsp),%r10
 10655df:	00 
 10655e0:	80 bc 24 60 01 00 00 	cmpb   $0x1,0x160(%rsp)
 10655e7:	01 
 10655e8:	0f 84 b4 11 00 00    	je     10667a2 <my.interpreter::evaluate+0x17d2>
 10655ee:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 10655f5:	48 89 f0             	mov    %rsi,%rax
 10655f8:	48 ff c8             	dec    %rax
 10655fb:	0f 80 9c 1a 00 00    	jo     106709d <my.interpreter::evaluate+0x20cd>
 1065601:	48 89 c6             	mov    %rax,%rsi
 1065604:	48 ff ce             	dec    %rsi
 1065607:	0f 80 a1 1a 00 00    	jo     10670ae <my.interpreter::evaluate+0x20de>
 106560d:	48 89 df             	mov    %rbx,%rdi
 1065610:	48 8b 43 78          	mov    0x78(%rbx),%rax
 1065614:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065618:	48 39 d6             	cmp    %rdx,%rsi
 106561b:	0f 83 31 17 00 00    	jae    1066d52 <my.interpreter::evaluate+0x1d82>
 1065621:	48 89 f1             	mov    %rsi,%rcx
 1065624:	4c 89 14 24          	mov    %r10,(%rsp)
 1065628:	4c 89 44 24 20       	mov    %r8,0x20(%rsp)
 106562d:	48 c1 e1 04          	shl    $0x4,%rcx
 1065631:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 1065636:	83 fa 03             	cmp    $0x3,%edx
 1065639:	0f 85 11 19 00 00    	jne    1066f50 <my.interpreter::evaluate+0x1f80>
 106563f:	48 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%rbx
 1065644:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 1065649:	49 89 fd             	mov    %rdi,%r13
 106564c:	e8 cf 3c 00 00       	call   1069320 <my.heap::string_hash>
 1065651:	49 8b 8d 80 00 00 00 	mov    0x80(%r13),%rcx
 1065658:	48 89 ce             	mov    %rcx,%rsi
 106565b:	48 ff ce             	dec    %rsi
 106565e:	0f 80 76 1a 00 00    	jo     10670da <my.interpreter::evaluate+0x210a>
 1065664:	4c 89 ef             	mov    %r13,%rdi
 1065667:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 106566b:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 106566f:	48 39 d6             	cmp    %rdx,%rsi
 1065672:	0f 83 fc 16 00 00    	jae    1066d74 <my.interpreter::evaluate+0x1da4>
 1065678:	49 89 f0             	mov    %rsi,%r8
 106567b:	49 c1 e0 04          	shl    $0x4,%r8
 106567f:	46 0f b6 7c 01 20    	movzbl 0x20(%rcx,%r8,1),%r15d
 1065685:	4e 8b 64 01 28       	mov    0x28(%rcx,%r8,1),%r12
 106568a:	48 89 de             	mov    %rbx,%rsi
 106568d:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 1065692:	89 c1                	mov    %eax,%ecx
 1065694:	45 89 f8             	mov    %r15d,%r8d
 1065697:	4d 89 e1             	mov    %r12,%r9
 106569a:	e8 31 44 00 00       	call   1069ad0 <my.heap::set_instance_field>
 106569f:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 10656a6:	48 89 c6             	mov    %rax,%rsi
 10656a9:	48 ff ce             	dec    %rsi
 10656ac:	0f 80 3c 1a 00 00    	jo     10670ee <my.interpreter::evaluate+0x211e>
 10656b2:	4c 89 ef             	mov    %r13,%rdi
 10656b5:	49 89 b5 80 00 00 00 	mov    %rsi,0x80(%r13)
 10656bc:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 10656c0:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10656c4:	48 39 d6             	cmp    %rdx,%rsi
 10656c7:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 10656cc:	4c 8b 14 24          	mov    (%rsp),%r10
 10656d0:	0f 83 c0 16 00 00    	jae    1066d96 <my.interpreter::evaluate+0x1dc6>
 10656d6:	48 89 f0             	mov    %rsi,%rax
 10656d9:	48 ff c8             	dec    %rax
 10656dc:	0f 80 20 1a 00 00    	jo     1067102 <my.interpreter::evaluate+0x2132>
 10656e2:	48 39 d0             	cmp    %rdx,%rax
 10656e5:	0f 83 cd 16 00 00    	jae    1066db8 <my.interpreter::evaluate+0x1de8>
 10656eb:	48 89 c6             	mov    %rax,%rsi
 10656ee:	48 c1 e6 04          	shl    $0x4,%rsi
 10656f2:	4c 89 7c 31 20       	mov    %r15,0x20(%rcx,%rsi,1)
 10656f7:	4c 89 64 31 28       	mov    %r12,0x28(%rcx,%rsi,1)
 10656fc:	48 89 4f 78          	mov    %rcx,0x78(%rdi)
 1065700:	31 c0                	xor    %eax,%eax
 1065702:	e9 cb 10 00 00       	jmp    10667d2 <my.interpreter::evaluate+0x1802>
 1065707:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 106570c:	0f b6 50 10          	movzbl 0x10(%rax),%edx
 1065710:	48 89 54 24 20       	mov    %rdx,0x20(%rsp)
 1065715:	48 8b 50 28          	mov    0x28(%rax),%rdx
 1065719:	48 89 54 24 18       	mov    %rdx,0x18(%rsp)
 106571e:	48 8b 50 38          	mov    0x38(%rax),%rdx
 1065722:	48 89 14 24          	mov    %rdx,(%rsp)
 1065726:	49 89 ce             	mov    %rcx,%r14
 1065729:	45 0f b6 d5          	movzbl %r13b,%r10d
 106572d:	49 89 ff             	mov    %rdi,%r15
 1065730:	48 8d 7c 24 48       	lea    0x48(%rsp),%rdi
 1065735:	48 89 ee             	mov    %rbp,%rsi
 1065738:	48 89 da             	mov    %rbx,%rdx
 106573b:	4d 89 c5             	mov    %r8,%r13
 106573e:	41 57                	push   %r15
 1065740:	ff 70 08             	push   0x8(%rax)
 1065743:	ff b4 24 08 05 00 00 	push   0x508(%rsp)
 106574a:	41 52                	push   %r10
 106574c:	41 53                	push   %r11
 106574e:	41 54                	push   %r12
 1065750:	4d 89 cf             	mov    %r9,%r15
 1065753:	e8 78 f8 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 1065758:	48 83 c4 30          	add    $0x30,%rsp
 106575c:	4c 8b 94 24 48 01 00 	mov    0x148(%rsp),%r10
 1065763:	00 
 1065764:	0f b6 84 24 50 01 00 	movzbl 0x150(%rsp),%eax
 106576b:	00 
 106576c:	4d 89 e3             	mov    %r12,%r11
 106576f:	4c 8b a4 24 58 01 00 	mov    0x158(%rsp),%r12
 1065776:	00 
 1065777:	80 7c 24 48 01       	cmpb   $0x1,0x48(%rsp)
 106577c:	0f 84 c2 0e 00 00    	je     1066644 <my.interpreter::evaluate+0x1674>
 1065782:	48 8d bc 24 60 01 00 	lea    0x160(%rsp),%rdi
 1065789:	00 
 106578a:	48 89 ee             	mov    %rbp,%rsi
 106578d:	48 89 da             	mov    %rbx,%rdx
 1065790:	4c 89 f1             	mov    %r14,%rcx
 1065793:	4d 89 e8             	mov    %r13,%r8
 1065796:	4d 89 f9             	mov    %r15,%r9
 1065799:	ff b4 24 08 05 00 00 	push   0x508(%rsp)
 10657a0:	ff 74 24 08          	push   0x8(%rsp)
 10657a4:	41 54                	push   %r12
 10657a6:	50                   	push   %rax
 10657a7:	41 52                	push   %r10
 10657a9:	41 53                	push   %r11
 10657ab:	e8 20 f8 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10657b0:	48 83 c4 30          	add    $0x30,%rsp
 10657b4:	4c 8b 94 24 60 02 00 	mov    0x260(%rsp),%r10
 10657bb:	00 
 10657bc:	44 0f b6 9c 24 68 02 	movzbl 0x268(%rsp),%r11d
 10657c3:	00 00 
 10657c5:	4c 8b a4 24 70 02 00 	mov    0x270(%rsp),%r12
 10657cc:	00 
 10657cd:	80 bc 24 60 01 00 00 	cmpb   $0x1,0x160(%rsp)
 10657d4:	01 
 10657d5:	0f 84 78 0f 00 00    	je     1066753 <my.interpreter::evaluate+0x1783>
 10657db:	4c 89 14 24          	mov    %r10,(%rsp)
 10657df:	49 8b 87 80 00 00 00 	mov    0x80(%r15),%rax
 10657e6:	48 89 c6             	mov    %rax,%rsi
 10657e9:	48 ff ce             	dec    %rsi
 10657ec:	41 0f 90 c2          	seto   %r10b
 10657f0:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 10657f5:	0f 80 6c 18 00 00    	jo     1067067 <my.interpreter::evaluate+0x2097>
 10657fb:	48 89 f1             	mov    %rsi,%rcx
 10657fe:	48 ff c9             	dec    %rcx
 1065801:	0f 80 74 18 00 00    	jo     106707b <my.interpreter::evaluate+0x20ab>
 1065807:	4c 89 fb             	mov    %r15,%rbx
 106580a:	4d 8b 47 78          	mov    0x78(%r15),%r8
 106580e:	49 8b 50 08          	mov    0x8(%r8),%rdx
 1065812:	4d 89 e5             	mov    %r12,%r13
 1065815:	48 39 d1             	cmp    %rdx,%rcx
 1065818:	0f 83 a6 14 00 00    	jae    1066cc4 <my.interpreter::evaluate+0x1cf4>
 106581e:	49 89 c9             	mov    %rcx,%r9
 1065821:	49 c1 e1 04          	shl    $0x4,%r9
 1065825:	43 0f b6 4c 08 20    	movzbl 0x20(%r8,%r9,1),%ecx
 106582b:	4f 8b 64 08 28       	mov    0x28(%r8,%r9,1),%r12
 1065830:	49 89 f1             	mov    %rsi,%r9
 1065833:	48 39 d6             	cmp    %rdx,%rsi
 1065836:	0f 83 ad 14 00 00    	jae    1066ce9 <my.interpreter::evaluate+0x1d19>
 106583c:	49 83 c0 20          	add    $0x20,%r8
 1065840:	49 c1 e1 04          	shl    $0x4,%r9
 1065844:	43 0f b6 2c 08       	movzbl (%r8,%r9,1),%ebp
 1065849:	4f 8b 7c 08 08       	mov    0x8(%r8,%r9,1),%r15
 106584e:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 1065853:	49 83 f9 0c          	cmp    $0xc,%r9
 1065857:	0f 84 1a 0a 00 00    	je     1066277 <my.interpreter::evaluate+0x12a7>
 106585d:	41 83 f9 0e          	cmp    $0xe,%r9d
 1065861:	0f 85 39 0a 00 00    	jne    10662a0 <my.interpreter::evaluate+0x12d0>
 1065867:	80 f9 02             	cmp    $0x2,%cl
 106586a:	0f 84 ad 0b 00 00    	je     106641d <my.interpreter::evaluate+0x144d>
 1065870:	0f b6 c9             	movzbl %cl,%ecx
 1065873:	83 f9 01             	cmp    $0x1,%ecx
 1065876:	0f 84 83 0b 00 00    	je     10663ff <my.interpreter::evaluate+0x142f>
 106587c:	85 c9                	test   %ecx,%ecx
 106587e:	0f 85 be 0b 00 00    	jne    1066442 <my.interpreter::evaluate+0x1472>
 1065884:	40 84 ed             	test   %bpl,%bpl
 1065887:	41 0f 94 c7          	sete   %r15b
 106588b:	e9 c3 0b 00 00       	jmp    1066453 <my.interpreter::evaluate+0x1483>
 1065890:	c5 f9 10 40 08       	vmovupd 0x8(%rax),%xmm0
 1065895:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065899:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 10658a0:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10658a4:	48 39 d6             	cmp    %rdx,%rsi
 10658a7:	0f 83 31 12 00 00    	jae    1066ade <my.interpreter::evaluate+0x1b0e>
 10658ad:	48 89 f1             	mov    %rsi,%rcx
 10658b0:	c5 f9 54 05 28 eb f9 	vandpd -0x614d8(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 10658b7:	ff 
 10658b8:	48 c1 e1 04          	shl    $0x4,%rcx
 10658bc:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 10658c2:	49 89 41 78          	mov    %rax,0x78(%r9)
 10658c6:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 10658cd:	48 89 f0             	mov    %rsi,%rax
 10658d0:	48 ff c0             	inc    %rax
 10658d3:	0f 81 b8 03 00 00    	jno    1065c91 <my.interpreter::evaluate+0xcc1>
 10658d9:	48 8d 3d a0 d0 01 00 	lea    0x1d0a0(%rip),%rdi        # 1082980 <core_durable_error.verbs+0x3270>
 10658e0:	ba 01 00 00 00       	mov    $0x1,%edx
 10658e5:	e8 16 ee fb ff       	call   1024700 <myl_core_trap>
 10658ea:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 10658ef:	44 0f b6 70 10       	movzbl 0x10(%rax),%r14d
 10658f4:	48 8b 50 38          	mov    0x38(%rax),%rdx
 10658f8:	48 89 54 24 18       	mov    %rdx,0x18(%rsp)
 10658fd:	45 0f b6 d5          	movzbl %r13b,%r10d
 1065901:	4d 89 dd             	mov    %r11,%r13
 1065904:	49 89 fb             	mov    %rdi,%r11
 1065907:	48 8d 7c 24 48       	lea    0x48(%rsp),%rdi
 106590c:	48 89 ee             	mov    %rbp,%rsi
 106590f:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
 1065914:	48 89 da             	mov    %rbx,%rdx
 1065917:	48 89 cb             	mov    %rcx,%rbx
 106591a:	41 53                	push   %r11
 106591c:	ff 70 08             	push   0x8(%rax)
 106591f:	41 57                	push   %r15
 1065921:	41 52                	push   %r10
 1065923:	41 55                	push   %r13
 1065925:	4d 89 e5             	mov    %r12,%r13
 1065928:	41 54                	push   %r12
 106592a:	4d 89 cc             	mov    %r9,%r12
 106592d:	e8 9e f6 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 1065932:	48 83 c4 30          	add    $0x30,%rsp
 1065936:	48 8b bc 24 48 01 00 	mov    0x148(%rsp),%rdi
 106593d:	00 
 106593e:	48 8b 84 24 50 01 00 	mov    0x150(%rsp),%rax
 1065945:	00 
 1065946:	44 0f b6 f8          	movzbl %al,%r15d
 106594a:	4c 8b 94 24 58 01 00 	mov    0x158(%rsp),%r10
 1065951:	00 
 1065952:	80 7c 24 48 01       	cmpb   $0x1,0x48(%rsp)
 1065957:	0f 84 02 0d 00 00    	je     106665f <my.interpreter::evaluate+0x168f>
 106595d:	49 8b 84 24 80 00 00 	mov    0x80(%r12),%rax
 1065964:	00 
 1065965:	48 89 c6             	mov    %rax,%rsi
 1065968:	48 ff ce             	dec    %rsi
 106596b:	0f 80 a5 16 00 00    	jo     1067016 <my.interpreter::evaluate+0x2046>
 1065971:	4d 89 e1             	mov    %r12,%r9
 1065974:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1065979:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106597d:	48 89 f1             	mov    %rsi,%rcx
 1065980:	48 39 d6             	cmp    %rdx,%rsi
 1065983:	4d 89 eb             	mov    %r13,%r11
 1065986:	4c 8b 04 24          	mov    (%rsp),%r8
 106598a:	0f 83 87 12 00 00    	jae    1066c17 <my.interpreter::evaluate+0x1c47>
 1065990:	48 c1 e1 04          	shl    $0x4,%rcx
 1065994:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 1065999:	83 fa 01             	cmp    $0x1,%edx
 106599c:	0f 84 85 08 00 00    	je     1066227 <my.interpreter::evaluate+0x1257>
 10659a2:	85 d2                	test   %edx,%edx
 10659a4:	0f 85 c1 08 00 00    	jne    106626b <my.interpreter::evaluate+0x129b>
 10659aa:	41 83 fe 1e          	cmp    $0x1e,%r14d
 10659ae:	0f 85 8d 08 00 00    	jne    1066241 <my.interpreter::evaluate+0x1271>
 10659b4:	49 89 b1 80 00 00 00 	mov    %rsi,0x80(%r9)
 10659bb:	48 89 f8             	mov    %rdi,%rax
 10659be:	48 8d bc 24 60 01 00 	lea    0x160(%rsp),%rdi
 10659c5:	00 
 10659c6:	48 89 ee             	mov    %rbp,%rsi
 10659c9:	48 8b 54 24 20       	mov    0x20(%rsp),%rdx
 10659ce:	48 89 d9             	mov    %rbx,%rcx
 10659d1:	ff b4 24 08 05 00 00 	push   0x508(%rsp)
 10659d8:	ff 74 24 20          	push   0x20(%rsp)
 10659dc:	41 52                	push   %r10
 10659de:	41 57                	push   %r15
 10659e0:	50                   	push   %rax
 10659e1:	41 53                	push   %r11
 10659e3:	e8 e8 f5 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10659e8:	48 83 c4 30          	add    $0x30,%rsp
 10659ec:	0f b6 84 24 60 01 00 	movzbl 0x160(%rsp),%eax
 10659f3:	00 
 10659f4:	c5 f9 10 84 24 68 01 	vmovupd 0x168(%rsp),%xmm0
 10659fb:	00 00 
 10659fd:	48 8b bc 24 60 02 00 	mov    0x260(%rsp),%rdi
 1065a04:	00 
 1065a05:	44 0f b6 bc 24 68 02 	movzbl 0x268(%rsp),%r15d
 1065a0c:	00 00 
 1065a0e:	4c 8b 94 24 70 02 00 	mov    0x270(%rsp),%r10
 1065a15:	00 
 1065a16:	48 83 f8 01          	cmp    $0x1,%rax
 1065a1a:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 1065a1f:	0f 85 23 08 00 00    	jne    1066248 <my.interpreter::evaluate+0x1278>
 1065a25:	c5 f9 29 04 24       	vmovapd %xmm0,(%rsp)
 1065a2a:	48 89 f9             	mov    %rdi,%rcx
 1065a2d:	48 8d 3d ac ff 01 00 	lea    0x1ffac(%rip),%rdi        # 10859e0 <core_durable_error.verbs+0x62d0>
 1065a34:	e9 40 0c 00 00       	jmp    1066679 <my.interpreter::evaluate+0x16a9>
 1065a39:	48 89 da             	mov    %rbx,%rdx
 1065a3c:	4c 89 f3             	mov    %r14,%rbx
 1065a3f:	44 0f b6 70 08       	movzbl 0x8(%rax),%r14d
 1065a44:	48 8b 70 20          	mov    0x20(%rax),%rsi
 1065a48:	48 89 34 24          	mov    %rsi,(%rsp)
 1065a4c:	45 0f b6 d5          	movzbl %r13b,%r10d
 1065a50:	4d 89 dd             	mov    %r11,%r13
 1065a53:	49 89 fb             	mov    %rdi,%r11
 1065a56:	48 8d 7c 24 48       	lea    0x48(%rsp),%rdi
 1065a5b:	48 89 ee             	mov    %rbp,%rsi
 1065a5e:	41 53                	push   %r11
 1065a60:	ff 70 30             	push   0x30(%rax)
 1065a63:	41 57                	push   %r15
 1065a65:	41 52                	push   %r10
 1065a67:	41 55                	push   %r13
 1065a69:	41 54                	push   %r12
 1065a6b:	4d 89 cd             	mov    %r9,%r13
 1065a6e:	e8 5d f5 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 1065a73:	48 83 c4 30          	add    $0x30,%rsp
 1065a77:	c5 f9 10 84 24 48 01 	vmovupd 0x148(%rsp),%xmm0
 1065a7e:	00 00 
 1065a80:	4c 8b bc 24 58 01 00 	mov    0x158(%rsp),%r15
 1065a87:	00 
 1065a88:	80 7c 24 48 01       	cmpb   $0x1,0x48(%rsp)
 1065a8d:	0f 84 09 0c 00 00    	je     106669c <my.interpreter::evaluate+0x16cc>
 1065a93:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1065a9a:	48 89 c6             	mov    %rax,%rsi
 1065a9d:	48 ff ce             	dec    %rsi
 1065aa0:	0f 80 84 15 00 00    	jo     106702a <my.interpreter::evaluate+0x205a>
 1065aa6:	4d 89 e8             	mov    %r13,%r8
 1065aa9:	49 8b 45 78          	mov    0x78(%r13),%rax
 1065aad:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065ab1:	48 39 d6             	cmp    %rdx,%rsi
 1065ab4:	0f 83 7f 11 00 00    	jae    1066c39 <my.interpreter::evaluate+0x1c69>
 1065aba:	48 89 f7             	mov    %rsi,%rdi
 1065abd:	48 c1 e7 04          	shl    $0x4,%rdi
 1065ac1:	48 8d 0c 38          	lea    (%rax,%rdi,1),%rcx
 1065ac5:	48 83 c1 20          	add    $0x20,%rcx
 1065ac9:	0f b6 74 38 20       	movzbl 0x20(%rax,%rdi,1),%esi
 1065ace:	48 8b 54 38 28       	mov    0x28(%rax,%rdi,1),%rdx
 1065ad3:	41 83 fe 0b          	cmp    $0xb,%r14d
 1065ad7:	0f 85 89 04 00 00    	jne    1065f66 <my.interpreter::evaluate+0xf96>
 1065add:	40 84 f6             	test   %sil,%sil
 1065ae0:	49 89 de             	mov    %rbx,%r14
 1065ae3:	0f 84 f5 07 00 00    	je     10662de <my.interpreter::evaluate+0x130e>
 1065ae9:	40 0f b6 f6          	movzbl %sil,%esi
 1065aed:	83 fe 01             	cmp    $0x1,%esi
 1065af0:	0f 85 ec 07 00 00    	jne    10662e2 <my.interpreter::evaluate+0x1312>
 1065af6:	f6 d2                	not    %dl
 1065af8:	80 e2 01             	and    $0x1,%dl
 1065afb:	e9 e4 07 00 00       	jmp    10662e4 <my.interpreter::evaluate+0x1314>
 1065b00:	48 8b 58 48          	mov    0x48(%rax),%rbx
 1065b04:	4c 8b 78 58          	mov    0x58(%rax),%r15
 1065b08:	48 8b 40 60          	mov    0x60(%rax),%rax
 1065b0c:	49 8b 39             	mov    (%r9),%rdi
 1065b0f:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 1065b16:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 1065b1a:	48 89 f1             	mov    %rsi,%rcx
 1065b1d:	48 85 c0             	test   %rax,%rax
 1065b20:	0f 8e 90 01 00 00    	jle    1065cb6 <my.interpreter::evaluate+0xce6>
 1065b26:	4c 8d 47 20          	lea    0x20(%rdi),%r8
 1065b2a:	49 89 c3             	mov    %rax,%r11
 1065b2d:	48 89 f1             	mov    %rsi,%rcx
 1065b30:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065b37:	0f 1f 84 00 00 00 00 
 1065b3e:	00 
 1065b3f:	90                   	nop
 1065b40:	48 39 d1             	cmp    %rdx,%rcx
 1065b43:	73 23                	jae    1065b68 <my.interpreter::evaluate+0xb98>
 1065b45:	49 89 ca             	mov    %rcx,%r10
 1065b48:	49 6b ca 38          	imul   $0x38,%r10,%rcx
 1065b4c:	41 83 3c 08 09       	cmpl   $0x9,(%r8,%rcx,1)
 1065b51:	0f 85 89 13 00 00    	jne    1066ee0 <my.interpreter::evaluate+0x1f10>
 1065b57:	4c 01 c1             	add    %r8,%rcx
 1065b5a:	48 8b 49 08          	mov    0x8(%rcx),%rcx
 1065b5e:	49 ff cb             	dec    %r11
 1065b61:	75 dd                	jne    1065b40 <my.interpreter::evaluate+0xb70>
 1065b63:	e9 4e 01 00 00       	jmp    1065cb6 <my.interpreter::evaluate+0xce6>
 1065b68:	49 89 ca             	mov    %rcx,%r10
 1065b6b:	49 c1 fa 3f          	sar    $0x3f,%r10
 1065b6f:	49 21 d2             	and    %rdx,%r10
 1065b72:	49 01 ca             	add    %rcx,%r10
 1065b75:	49 39 d2             	cmp    %rdx,%r10
 1065b78:	72 ce                	jb     1065b48 <my.interpreter::evaluate+0xb78>
 1065b7a:	48 8d 3d 5f f8 01 00 	lea    0x1f85f(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065b81:	48 89 ce             	mov    %rcx,%rsi
 1065b84:	e8 77 eb fb ff       	call   1024700 <myl_core_trap>
 1065b89:	48 8b 78 38          	mov    0x38(%rax),%rdi
 1065b8d:	48 83 ff ff          	cmp    $0xffffffffffffffff,%rdi
 1065b91:	0f 84 a8 04 00 00    	je     106603f <my.interpreter::evaluate+0x106f>
 1065b97:	48 8b 70 40          	mov    0x40(%rax),%rsi
 1065b9b:	49 8b 09             	mov    (%r9),%rcx
 1065b9e:	49 8b 81 a8 00 00 00 	mov    0xa8(%r9),%rax
 1065ba5:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065ba9:	48 85 ff             	test   %rdi,%rdi
 1065bac:	0f 8e e8 02 00 00    	jle    1065e9a <my.interpreter::evaluate+0xeca>
 1065bb2:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 1065bb6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 1065bbd:	00 00 00 
 1065bc0:	48 39 d0             	cmp    %rdx,%rax
 1065bc3:	73 23                	jae    1065be8 <my.interpreter::evaluate+0xc18>
 1065bc5:	49 89 c2             	mov    %rax,%r10
 1065bc8:	49 6b c2 38          	imul   $0x38,%r10,%rax
 1065bcc:	41 83 3c 00 09       	cmpl   $0x9,(%r8,%rax,1)
 1065bd1:	0f 85 21 13 00 00    	jne    1066ef8 <my.interpreter::evaluate+0x1f28>
 1065bd7:	4c 01 c0             	add    %r8,%rax
 1065bda:	48 8b 40 08          	mov    0x8(%rax),%rax
 1065bde:	48 ff cf             	dec    %rdi
 1065be1:	75 dd                	jne    1065bc0 <my.interpreter::evaluate+0xbf0>
 1065be3:	e9 b2 02 00 00       	jmp    1065e9a <my.interpreter::evaluate+0xeca>
 1065be8:	49 89 c2             	mov    %rax,%r10
 1065beb:	49 c1 fa 3f          	sar    $0x3f,%r10
 1065bef:	49 21 d2             	and    %rdx,%r10
 1065bf2:	49 01 c2             	add    %rax,%r10
 1065bf5:	49 39 d2             	cmp    %rdx,%r10
 1065bf8:	72 ce                	jb     1065bc8 <my.interpreter::evaluate+0xbf8>
 1065bfa:	48 8d 3d df f7 01 00 	lea    0x1f7df(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065c01:	48 89 c6             	mov    %rax,%rsi
 1065c04:	e8 f7 ea fb ff       	call   1024700 <myl_core_trap>
 1065c09:	48 8b 40 38          	mov    0x38(%rax),%rax
 1065c0d:	48 39 d6             	cmp    %rdx,%rsi
 1065c10:	0f 83 ea 0e 00 00    	jae    1066b00 <my.interpreter::evaluate+0x1b30>
 1065c16:	48 89 f7             	mov    %rsi,%rdi
 1065c19:	48 6b d7 38          	imul   $0x38,%rdi,%rdx
 1065c1d:	83 7c 11 20 09       	cmpl   $0x9,0x20(%rcx,%rdx,1)
 1065c22:	0f 85 65 13 00 00    	jne    1066f8d <my.interpreter::evaluate+0x1fbd>
 1065c28:	48 01 d1             	add    %rdx,%rcx
 1065c2b:	48 83 c1 20          	add    $0x20,%rcx
 1065c2f:	48 8b 49 10          	mov    0x10(%rcx),%rcx
 1065c33:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065c37:	48 39 d0             	cmp    %rdx,%rax
 1065c3a:	0f 83 07 0f 00 00    	jae    1066b47 <my.interpreter::evaluate+0x1b77>
 1065c40:	48 89 c6             	mov    %rax,%rsi
 1065c43:	48 c1 e6 04          	shl    $0x4,%rsi
 1065c47:	c5 f9 10 44 31 20    	vmovupd 0x20(%rcx,%rsi,1),%xmm0
 1065c4d:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065c51:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065c58:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065c5c:	48 39 d6             	cmp    %rdx,%rsi
 1065c5f:	0f 83 07 0f 00 00    	jae    1066b6c <my.interpreter::evaluate+0x1b9c>
 1065c65:	48 89 f1             	mov    %rsi,%rcx
 1065c68:	c5 f9 54 05 70 e7 f9 	vandpd -0x61890(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 1065c6f:	ff 
 1065c70:	48 c1 e1 04          	shl    $0x4,%rcx
 1065c74:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 1065c7a:	49 89 41 78          	mov    %rax,0x78(%r9)
 1065c7e:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065c85:	48 89 f0             	mov    %rsi,%rax
 1065c88:	48 ff c0             	inc    %rax
 1065c8b:	0f 80 14 13 00 00    	jo     1066fa5 <my.interpreter::evaluate+0x1fd5>
 1065c91:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065c98:	49 c7 06 00 00 00 00 	movq   $0x0,(%r14)
 1065c9f:	4d 89 9e 00 01 00 00 	mov    %r11,0x100(%r14)
 1065ca6:	41 0f b6 c5          	movzbl %r13b,%eax
 1065caa:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 1065cb1:	e9 5a 06 00 00       	jmp    1066310 <my.interpreter::evaluate+0x1340>
 1065cb6:	48 39 d1             	cmp    %rdx,%rcx
 1065cb9:	0f 83 63 0e 00 00    	jae    1066b22 <my.interpreter::evaluate+0x1b52>
 1065cbf:	49 89 c8             	mov    %rcx,%r8
 1065cc2:	49 6b c8 38          	imul   $0x38,%r8,%rcx
 1065cc6:	83 7c 0f 20 09       	cmpl   $0x9,0x20(%rdi,%rcx,1)
 1065ccb:	0f 85 c8 12 00 00    	jne    1066f99 <my.interpreter::evaluate+0x1fc9>
 1065cd1:	48 01 f9             	add    %rdi,%rcx
 1065cd4:	48 83 c1 20          	add    $0x20,%rcx
 1065cd8:	4c 8b 41 10          	mov    0x10(%rcx),%r8
 1065cdc:	49 83 78 08 00       	cmpq   $0x0,0x8(%r8)
 1065ce1:	0f 84 a7 0e 00 00    	je     1066b8e <my.interpreter::evaluate+0x1bbe>
 1065ce7:	48 89 c1             	mov    %rax,%rcx
 1065cea:	48 ff c9             	dec    %rcx
 1065ced:	0f 80 c3 12 00 00    	jo     1066fb6 <my.interpreter::evaluate+0x1fe6>
 1065cf3:	48 83 c7 20          	add    $0x20,%rdi
 1065cf7:	41 0f b6 40 20       	movzbl 0x20(%r8),%eax
 1065cfc:	4d 8b 60 28          	mov    0x28(%r8),%r12
 1065d00:	48 85 c9             	test   %rcx,%rcx
 1065d03:	7e 7d                	jle    1065d82 <my.interpreter::evaluate+0xdb2>
 1065d05:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065d0c:	0f 1f 84 00 00 00 00 
 1065d13:	00 
 1065d14:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065d1b:	0f 1f 84 00 00 00 00 
 1065d22:	00 
 1065d23:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065d2a:	0f 1f 84 00 00 00 00 
 1065d31:	00 
 1065d32:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065d39:	1f 84 00 00 00 00 00 
 1065d40:	48 39 d6             	cmp    %rdx,%rsi
 1065d43:	73 1f                	jae    1065d64 <my.interpreter::evaluate+0xd94>
 1065d45:	49 89 f0             	mov    %rsi,%r8
 1065d48:	49 6b f0 38          	imul   $0x38,%r8,%rsi
 1065d4c:	83 3c 37 09          	cmpl   $0x9,(%rdi,%rsi,1)
 1065d50:	0f 85 96 11 00 00    	jne    1066eec <my.interpreter::evaluate+0x1f1c>
 1065d56:	48 01 fe             	add    %rdi,%rsi
 1065d59:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 1065d5d:	48 ff c9             	dec    %rcx
 1065d60:	75 de                	jne    1065d40 <my.interpreter::evaluate+0xd70>
 1065d62:	eb 1e                	jmp    1065d82 <my.interpreter::evaluate+0xdb2>
 1065d64:	49 89 f0             	mov    %rsi,%r8
 1065d67:	49 c1 f8 3f          	sar    $0x3f,%r8
 1065d6b:	49 21 d0             	and    %rdx,%r8
 1065d6e:	49 01 f0             	add    %rsi,%r8
 1065d71:	49 39 d0             	cmp    %rdx,%r8
 1065d74:	72 d2                	jb     1065d48 <my.interpreter::evaluate+0xd78>
 1065d76:	48 8d 3d 63 f6 01 00 	lea    0x1f663(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065d7d:	e8 7e e9 fb ff       	call   1024700 <myl_core_trap>
 1065d82:	48 39 d6             	cmp    %rdx,%rsi
 1065d85:	0f 83 13 0e 00 00    	jae    1066b9e <my.interpreter::evaluate+0x1bce>
 1065d8b:	48 89 f1             	mov    %rsi,%rcx
 1065d8e:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065d92:	83 3c 0f 09          	cmpl   $0x9,(%rdi,%rcx,1)
 1065d96:	0f 85 2e 12 00 00    	jne    1066fca <my.interpreter::evaluate+0x1ffa>
 1065d9c:	48 01 cf             	add    %rcx,%rdi
 1065d9f:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 1065da3:	48 83 79 08 00       	cmpq   $0x0,0x8(%rcx)
 1065da8:	0f 84 12 0e 00 00    	je     1066bc0 <my.interpreter::evaluate+0x1bf0>
 1065dae:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
 1065db3:	3c 03                	cmp    $0x3,%al
 1065db5:	0f 85 55 11 00 00    	jne    1066f10 <my.interpreter::evaluate+0x1f40>
 1065dbb:	0f b6 69 20          	movzbl 0x20(%rcx),%ebp
 1065dbf:	48 8b 41 28          	mov    0x28(%rcx),%rax
 1065dc3:	48 89 04 24          	mov    %rax,(%rsp)
 1065dc7:	4c 89 cf             	mov    %r9,%rdi
 1065dca:	4c 89 fe             	mov    %r15,%rsi
 1065dcd:	4d 89 cd             	mov    %r9,%r13
 1065dd0:	e8 4b 35 00 00       	call   1069320 <my.heap::string_hash>
 1065dd5:	4c 89 eb             	mov    %r13,%rbx
 1065dd8:	4c 89 ef             	mov    %r13,%rdi
 1065ddb:	4c 89 e6             	mov    %r12,%rsi
 1065dde:	4c 89 fa             	mov    %r15,%rdx
 1065de1:	89 c1                	mov    %eax,%ecx
 1065de3:	e8 f8 3d 00 00       	call   1069be0 <my.heap::class_method>
 1065de8:	3c 01                	cmp    $0x1,%al
 1065dea:	0f 85 d0 08 00 00    	jne    10666c0 <my.interpreter::evaluate+0x16f0>
 1065df0:	80 fa 03             	cmp    $0x3,%dl
 1065df3:	44 0f b6 a4 24 f0 04 	movzbl 0x4f0(%rsp),%r12d
 1065dfa:	00 00 
 1065dfc:	0f 85 2e 11 00 00    	jne    1066f30 <my.interpreter::evaluate+0x1f60>
 1065e02:	49 89 c8             	mov    %rcx,%r8
 1065e05:	40 0f b6 d5          	movzbl %bpl,%edx
 1065e09:	48 8d 7c 24 48       	lea    0x48(%rsp),%rdi
 1065e0e:	48 89 de             	mov    %rbx,%rsi
 1065e11:	48 8b 0c 24          	mov    (%rsp),%rcx
 1065e15:	e8 56 a3 00 00       	call   1070170 <my.interpreter::bind>
 1065e1a:	48 8b 44 24 48       	mov    0x48(%rsp),%rax
 1065e1f:	48 8b 4b 78          	mov    0x78(%rbx),%rcx
 1065e23:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 1065e2a:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065e2e:	48 89 f7             	mov    %rsi,%rdi
 1065e31:	48 39 d6             	cmp    %rdx,%rsi
 1065e34:	0f 83 21 0e 00 00    	jae    1066c5b <my.interpreter::evaluate+0x1c8b>
 1065e3a:	48 c1 e7 04          	shl    $0x4,%rdi
 1065e3e:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 1065e45:	00 00 
 1065e47:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 1065e4c:	48 89 f0             	mov    %rsi,%rax
 1065e4f:	48 ff c0             	inc    %rax
 1065e52:	48 8b 8c 24 e8 04 00 	mov    0x4e8(%rsp),%rcx
 1065e59:	00 
 1065e5a:	0f 80 f6 11 00 00    	jo     1067056 <my.interpreter::evaluate+0x2086>
 1065e60:	48 89 83 80 00 00 00 	mov    %rax,0x80(%rbx)
 1065e67:	31 c0                	xor    %eax,%eax
 1065e69:	49 89 06             	mov    %rax,(%r14)
 1065e6c:	49 89 5e 08          	mov    %rbx,0x8(%r14)
 1065e70:	49 89 56 10          	mov    %rdx,0x10(%r14)
 1065e74:	49 89 8e 00 01 00 00 	mov    %rcx,0x100(%r14)
 1065e7b:	41 0f b6 c4          	movzbl %r12b,%eax
 1065e7f:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 1065e86:	48 8b 84 24 f8 04 00 	mov    0x4f8(%rsp),%rax
 1065e8d:	00 
 1065e8e:	49 89 86 10 01 00 00 	mov    %rax,0x110(%r14)
 1065e95:	e9 7b 0b 00 00       	jmp    1066a15 <my.interpreter::evaluate+0x1a45>
 1065e9a:	48 39 d0             	cmp    %rdx,%rax
 1065e9d:	0f 83 3a 0f 00 00    	jae    1066ddd <my.interpreter::evaluate+0x1e0d>
 1065ea3:	48 89 c7             	mov    %rax,%rdi
 1065ea6:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 1065eaa:	83 7c 01 20 09       	cmpl   $0x9,0x20(%rcx,%rax,1)
 1065eaf:	0f 85 5e 12 00 00    	jne    1067113 <my.interpreter::evaluate+0x2143>
 1065eb5:	48 01 c8             	add    %rcx,%rax
 1065eb8:	48 83 c0 20          	add    $0x20,%rax
 1065ebc:	48 8b 40 10          	mov    0x10(%rax),%rax
 1065ec0:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065ec4:	48 39 d6             	cmp    %rdx,%rsi
 1065ec7:	0f 83 35 0f 00 00    	jae    1066e02 <my.interpreter::evaluate+0x1e32>
 1065ecd:	48 89 f1             	mov    %rsi,%rcx
 1065ed0:	48 c1 e1 04          	shl    $0x4,%rcx
 1065ed4:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 1065eda:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065ede:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065ee5:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065ee9:	48 89 f1             	mov    %rsi,%rcx
 1065eec:	48 39 d6             	cmp    %rdx,%rsi
 1065eef:	0f 83 2f 0f 00 00    	jae    1066e24 <my.interpreter::evaluate+0x1e54>
 1065ef5:	48 c1 e1 04          	shl    $0x4,%rcx
 1065ef9:	c5 f9 54 05 df e4 f9 	vandpd -0x61b21(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 1065f00:	ff 
 1065f01:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 1065f07:	48 89 f0             	mov    %rsi,%rax
 1065f0a:	48 ff c0             	inc    %rax
 1065f0d:	0f 80 0c 12 00 00    	jo     106711f <my.interpreter::evaluate+0x214f>
 1065f13:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065f1a:	e9 a5 01 00 00       	jmp    10660c4 <my.interpreter::evaluate+0x10f4>
 1065f1f:	49 8b 8d 80 00 00 00 	mov    0x80(%r13),%rcx
 1065f26:	48 89 c8             	mov    %rcx,%rax
 1065f29:	48 ff c8             	dec    %rax
 1065f2c:	0f 80 fe 11 00 00    	jo     1067130 <my.interpreter::evaluate+0x2160>
 1065f32:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 1065f36:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065f3a:	48 39 d0             	cmp    %rdx,%rax
 1065f3d:	0f 83 03 0f 00 00    	jae    1066e46 <my.interpreter::evaluate+0x1e76>
 1065f43:	49 89 c1             	mov    %rax,%r9
 1065f46:	49 c1 e1 04          	shl    $0x4,%r9
 1065f4a:	4e 8b 44 09 28       	mov    0x28(%rcx,%r9,1),%r8
 1065f4f:	42 8b 4c 09 20       	mov    0x20(%rcx,%r9,1),%ecx
 1065f54:	4c 89 ef             	mov    %r13,%rdi
 1065f57:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 1065f5c:	e8 1f 5e 00 00       	call   106bd80 <my.heap::set_env_slot>
 1065f61:	e9 ba 02 00 00       	jmp    1066220 <my.interpreter::evaluate+0x1250>
 1065f66:	40 80 fe 02          	cmp    $0x2,%sil
 1065f6a:	49 89 de             	mov    %rbx,%r14
 1065f6d:	0f 85 59 04 00 00    	jne    10663cc <my.interpreter::evaluate+0x13fc>
 1065f73:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 1065f7a:	00 00 80 
 1065f7d:	48 31 f2             	xor    %rsi,%rdx
 1065f80:	48 c7 01 02 00 00 00 	movq   $0x2,(%rcx)
 1065f87:	48 89 51 08          	mov    %rdx,0x8(%rcx)
 1065f8b:	e9 5e 03 00 00       	jmp    10662ee <my.interpreter::evaluate+0x131e>
 1065f90:	4c 89 e7             	mov    %r12,%rdi
 1065f93:	4c 89 fe             	mov    %r15,%rsi
 1065f96:	e8 55 3a 00 00       	call   10699f0 <my.heap::instance_class>
 1065f9b:	4d 89 e5             	mov    %r12,%r13
 1065f9e:	4c 89 e7             	mov    %r12,%rdi
 1065fa1:	48 89 c6             	mov    %rax,%rsi
 1065fa4:	48 89 ea             	mov    %rbp,%rdx
 1065fa7:	89 d9                	mov    %ebx,%ecx
 1065fa9:	e8 32 3c 00 00       	call   1069be0 <my.heap::class_method>
 1065fae:	3c 01                	cmp    $0x1,%al
 1065fb0:	0f 85 bb 08 00 00    	jne    1066871 <my.interpreter::evaluate+0x18a1>
 1065fb6:	80 fa 03             	cmp    $0x3,%dl
 1065fb9:	0f 85 ae 0f 00 00    	jne    1066f6d <my.interpreter::evaluate+0x1f9d>
 1065fbf:	49 89 c8             	mov    %rcx,%r8
 1065fc2:	41 0f b6 d6          	movzbl %r14b,%edx
 1065fc6:	48 8d bc 24 60 01 00 	lea    0x160(%rsp),%rdi
 1065fcd:	00 
 1065fce:	4c 89 ee             	mov    %r13,%rsi
 1065fd1:	4c 89 f9             	mov    %r15,%rcx
 1065fd4:	e8 97 a1 00 00       	call   1070170 <my.interpreter::bind>
 1065fd9:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1065fe0:	48 89 c6             	mov    %rax,%rsi
 1065fe3:	48 ff ce             	dec    %rsi
 1065fe6:	0f 80 8b 11 00 00    	jo     1067177 <my.interpreter::evaluate+0x21a7>
 1065fec:	4d 89 ec             	mov    %r13,%r12
 1065fef:	48 8b 8c 24 60 01 00 	mov    0x160(%rsp),%rcx
 1065ff6:	00 
 1065ff7:	49 8b 45 78          	mov    0x78(%r13),%rax
 1065ffb:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065fff:	48 39 d6             	cmp    %rdx,%rsi
 1066002:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 1066007:	c5 f9 28 04 24       	vmovapd (%rsp),%xmm0
 106600c:	0f 83 59 0e 00 00    	jae    1066e6b <my.interpreter::evaluate+0x1e9b>
 1066012:	48 89 f7             	mov    %rsi,%rdi
 1066015:	48 c1 e7 04          	shl    $0x4,%rdi
 1066019:	48 8d 34 38          	lea    (%rax,%rdi,1),%rsi
 106601d:	48 83 c6 20          	add    $0x20,%rsi
 1066021:	48 c7 44 38 20 03 00 	movq   $0x3,0x20(%rax,%rdi,1)
 1066028:	00 00 
 106602a:	48 89 4e 08          	mov    %rcx,0x8(%rsi)
 106602e:	49 89 44 24 78       	mov    %rax,0x78(%r12)
 1066033:	31 c0                	xor    %eax,%eax
 1066035:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 106603a:	e9 b3 09 00 00       	jmp    10669f2 <my.interpreter::evaluate+0x1a22>
 106603f:	4c 8b 68 20          	mov    0x20(%rax),%r13
 1066043:	48 8b 58 30          	mov    0x30(%rax),%rbx
 1066047:	4d 8b 79 30          	mov    0x30(%r9),%r15
 106604b:	4d 8b 61 38          	mov    0x38(%r9),%r12
 106604f:	4c 89 cf             	mov    %r9,%rdi
 1066052:	48 89 de             	mov    %rbx,%rsi
 1066055:	4c 89 cd             	mov    %r9,%rbp
 1066058:	e8 c3 32 00 00       	call   1069320 <my.heap::string_hash>
 106605d:	4c 89 ff             	mov    %r15,%rdi
 1066060:	4c 89 e6             	mov    %r12,%rsi
 1066063:	48 89 da             	mov    %rbx,%rdx
 1066066:	89 c1                	mov    %eax,%ecx
 1066068:	e8 a3 31 00 00       	call   1069210 <my.table::get>
 106606d:	3c 01                	cmp    $0x1,%al
 106606f:	0f 85 6c 08 00 00    	jne    10668e1 <my.interpreter::evaluate+0x1911>
 1066075:	48 8b 7d 78          	mov    0x78(%rbp),%rdi
 1066079:	48 8b b5 80 00 00 00 	mov    0x80(%rbp),%rsi
 1066080:	48 8b 47 08          	mov    0x8(%rdi),%rax
 1066084:	49 89 f0             	mov    %rsi,%r8
 1066087:	48 39 c6             	cmp    %rax,%rsi
 106608a:	0f 83 fd 0d 00 00    	jae    1066e8d <my.interpreter::evaluate+0x1ebd>
 1066090:	49 c1 e0 04          	shl    $0x4,%r8
 1066094:	0f b6 c2             	movzbl %dl,%eax
 1066097:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 106609c:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 10660a1:	48 89 f0             	mov    %rsi,%rax
 10660a4:	48 ff c0             	inc    %rax
 10660a7:	4c 8b 9c 24 e8 04 00 	mov    0x4e8(%rsp),%r11
 10660ae:	00 
 10660af:	4c 8b bc 24 f8 04 00 	mov    0x4f8(%rsp),%r15
 10660b6:	00 
 10660b7:	0f 80 ce 10 00 00    	jo     106718b <my.interpreter::evaluate+0x21bb>
 10660bd:	48 89 85 80 00 00 00 	mov    %rax,0x80(%rbp)
 10660c4:	31 c0                	xor    %eax,%eax
 10660c6:	49 89 06             	mov    %rax,(%r14)
 10660c9:	49 89 5e 08          	mov    %rbx,0x8(%r14)
 10660cd:	4d 89 6e 10          	mov    %r13,0x10(%r14)
 10660d1:	4d 89 9e 00 01 00 00 	mov    %r11,0x100(%r14)
 10660d8:	0f b6 84 24 f0 04 00 	movzbl 0x4f0(%rsp),%eax
 10660df:	00 
 10660e0:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 10660e7:	e9 24 02 00 00       	jmp    1066310 <my.interpreter::evaluate+0x1340>
 10660ec:	45 31 db             	xor    %r11d,%r11d
 10660ef:	4c 8b 04 24          	mov    (%rsp),%r8
 10660f3:	48 83 ec 08          	sub    $0x8,%rsp
 10660f7:	44 0f b6 f1          	movzbl %cl,%r14d
 10660fb:	48 8d bc 24 80 02 00 	lea    0x280(%rsp),%rdi
 1066102:	00 
 1066103:	48 89 ee             	mov    %rbp,%rsi
 1066106:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 106610b:	48 89 d9             	mov    %rbx,%rcx
 106610e:	4d 89 e9             	mov    %r13,%r9
 1066111:	ff b4 24 10 05 00 00 	push   0x510(%rsp)
 1066118:	ff 74 24 28          	push   0x28(%rsp)
 106611c:	41 53                	push   %r11
 106611e:	41 52                	push   %r10
 1066120:	41 56                	push   %r14
 1066122:	50                   	push   %rax
 1066123:	41 54                	push   %r12
 1066125:	e8 e6 92 00 00       	call   106f410 <my.interpreter::call_value>
 106612a:	48 83 c4 40          	add    $0x40,%rsp
 106612e:	0f b6 94 24 78 02 00 	movzbl 0x278(%rsp),%edx
 1066135:	00 
 1066136:	c5 f9 10 84 24 80 02 	vmovupd 0x280(%rsp),%xmm0
 106613d:	00 00 
 106613f:	48 8b 84 24 78 03 00 	mov    0x378(%rsp),%rax
 1066146:	00 
 1066147:	0f b6 8c 24 80 03 00 	movzbl 0x380(%rsp),%ecx
 106614e:	00 
 106614f:	4c 8b 94 24 88 03 00 	mov    0x388(%rsp),%r10
 1066156:	00 
 1066157:	48 83 fa 01          	cmp    $0x1,%rdx
 106615b:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 1066160:	0f 84 2e 06 00 00    	je     1066794 <my.interpreter::evaluate+0x17c4>
 1066166:	49 89 16             	mov    %rdx,(%r14)
 1066169:	c4 c1 79 11 46 08    	vmovupd %xmm0,0x8(%r14)
 106616f:	49 89 86 00 01 00 00 	mov    %rax,0x100(%r14)
 1066176:	49 89 8e 08 01 00 00 	mov    %rcx,0x108(%r14)
 106617d:	4d 89 96 10 01 00 00 	mov    %r10,0x110(%r14)
 1066184:	e9 8c 08 00 00       	jmp    1066a15 <my.interpreter::evaluate+0x1a45>
 1066189:	49 8b 5d 30          	mov    0x30(%r13),%rbx
 106618d:	4d 8b 7d 38          	mov    0x38(%r13),%r15
 1066191:	4c 89 ef             	mov    %r13,%rdi
 1066194:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 1066199:	48 89 ee             	mov    %rbp,%rsi
 106619c:	e8 7f 31 00 00       	call   1069320 <my.heap::string_hash>
 10661a1:	48 89 df             	mov    %rbx,%rdi
 10661a4:	4c 89 fe             	mov    %r15,%rsi
 10661a7:	48 89 ea             	mov    %rbp,%rdx
 10661aa:	89 c1                	mov    %eax,%ecx
 10661ac:	e8 5f 30 00 00       	call   1069210 <my.table::get>
 10661b1:	3c 01                	cmp    $0x1,%al
 10661b3:	0f 85 b5 07 00 00    	jne    106696e <my.interpreter::evaluate+0x199e>
 10661b9:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 10661c0:	48 89 c6             	mov    %rax,%rsi
 10661c3:	48 ff ce             	dec    %rsi
 10661c6:	0f 80 d0 0f 00 00    	jo     106719c <my.interpreter::evaluate+0x21cc>
 10661cc:	4c 89 ef             	mov    %r13,%rdi
 10661cf:	49 8b 45 78          	mov    0x78(%r13),%rax
 10661d3:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10661d7:	48 39 d6             	cmp    %rdx,%rsi
 10661da:	0f 83 d2 0c 00 00    	jae    1066eb2 <my.interpreter::evaluate+0x1ee2>
 10661e0:	48 89 f1             	mov    %rsi,%rcx
 10661e3:	48 c1 e1 04          	shl    $0x4,%rcx
 10661e7:	48 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%rbx
 10661ec:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 10661f0:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 10661f5:	4c 89 ee             	mov    %r13,%rsi
 10661f8:	49 89 ff             	mov    %rdi,%r15
 10661fb:	e8 20 31 00 00       	call   1069320 <my.heap::string_hash>
 1066200:	49 8b 7f 30          	mov    0x30(%r15),%rdi
 1066204:	49 8b 77 38          	mov    0x38(%r15),%rsi
 1066208:	4c 89 ea             	mov    %r13,%rdx
 106620b:	89 c1                	mov    %eax,%ecx
 106620d:	41 89 e8             	mov    %ebp,%r8d
 1066210:	49 89 d9             	mov    %rbx,%r9
 1066213:	e8 e8 31 00 00       	call   1069400 <my.table::set>
 1066218:	49 89 57 30          	mov    %rdx,0x30(%r15)
 106621c:	49 89 4f 38          	mov    %rcx,0x38(%r15)
 1066220:	31 c0                	xor    %eax,%eax
 1066222:	e9 c6 07 00 00       	jmp    10669ed <my.interpreter::evaluate+0x1a1d>
 1066227:	48 01 c8             	add    %rcx,%rax
 106622a:	48 83 c0 20          	add    $0x20,%rax
 106622e:	41 83 fe 1e          	cmp    $0x1e,%r14d
 1066232:	0f 95 c1             	setne  %cl
 1066235:	32 48 08             	xor    0x8(%rax),%cl
 1066238:	f6 c1 01             	test   $0x1,%cl
 106623b:	0f 84 73 f7 ff ff    	je     10659b4 <my.interpreter::evaluate+0x9e4>
 1066241:	31 c0                	xor    %eax,%eax
 1066243:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 1066248:	49 89 06             	mov    %rax,(%r14)
 106624b:	c4 c1 79 11 46 08    	vmovupd %xmm0,0x8(%r14)
 1066251:	49 89 be 00 01 00 00 	mov    %rdi,0x100(%r14)
 1066258:	4d 89 be 08 01 00 00 	mov    %r15,0x108(%r14)
 106625f:	4d 89 96 10 01 00 00 	mov    %r10,0x110(%r14)
 1066266:	e9 aa 07 00 00       	jmp    1066a15 <my.interpreter::evaluate+0x1a45>
 106626b:	41 83 fe 1e          	cmp    $0x1e,%r14d
 106626f:	0f 85 3f f7 ff ff    	jne    10659b4 <my.interpreter::evaluate+0x9e4>
 1066275:	eb ca                	jmp    1066241 <my.interpreter::evaluate+0x1271>
 1066277:	80 f9 02             	cmp    $0x2,%cl
 106627a:	0f 84 d8 01 00 00    	je     1066458 <my.interpreter::evaluate+0x1488>
 1066280:	0f b6 c9             	movzbl %cl,%ecx
 1066283:	83 f9 01             	cmp    $0x1,%ecx
 1066286:	0f 84 82 01 00 00    	je     106640e <my.interpreter::evaluate+0x143e>
 106628c:	85 c9                	test   %ecx,%ecx
 106628e:	0f 85 e9 01 00 00    	jne    106647d <my.interpreter::evaluate+0x14ad>
 1066294:	40 84 ed             	test   %bpl,%bpl
 1066297:	41 0f 94 c7          	sete   %r15b
 106629b:	e9 ee 01 00 00       	jmp    106648e <my.interpreter::evaluate+0x14be>
 10662a0:	89 ca                	mov    %ecx,%edx
 10662a2:	80 f2 02             	xor    $0x2,%dl
 10662a5:	c4 c1 f9 6e c4       	vmovq  %r12,%xmm0
 10662aa:	41 89 e8             	mov    %ebp,%r8d
 10662ad:	41 80 f0 02          	xor    $0x2,%r8b
 10662b1:	c4 c1 f9 6e cf       	vmovq  %r15,%xmm1
 10662b6:	41 08 d0             	or     %dl,%r8b
 10662b9:	0f 94 c2             	sete   %dl
 10662bc:	41 83 f9 07          	cmp    $0x7,%r9d
 10662c0:	75 5a                	jne    106631c <my.interpreter::evaluate+0x134c>
 10662c2:	84 d2                	test   %dl,%dl
 10662c4:	0f 84 47 02 00 00    	je     1066511 <my.interpreter::evaluate+0x1541>
 10662ca:	c5 fb 58 c1          	vaddsd %xmm1,%xmm0,%xmm0
 10662ce:	c4 e1 f9 7e c1       	vmovq  %xmm0,%rcx
 10662d3:	41 b8 02 00 00 00    	mov    $0x2,%r8d
 10662d9:	e9 c2 02 00 00       	jmp    10665a0 <my.interpreter::evaluate+0x15d0>
 10662de:	b2 01                	mov    $0x1,%dl
 10662e0:	eb 02                	jmp    10662e4 <my.interpreter::evaluate+0x1314>
 10662e2:	31 d2                	xor    %edx,%edx
 10662e4:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 10662eb:	88 51 08             	mov    %dl,0x8(%rcx)
 10662ee:	49 89 40 78          	mov    %rax,0x78(%r8)
 10662f2:	31 c9                	xor    %ecx,%ecx
 10662f4:	49 89 0e             	mov    %rcx,(%r14)
 10662f7:	49 89 46 08          	mov    %rax,0x8(%r14)
 10662fb:	49 89 56 10          	mov    %rdx,0x10(%r14)
 10662ff:	c5 f9 54 05 19 e0 f9 	vandpd -0x61fe7(%rip),%xmm0,%xmm0        # 1004320 <__anon_2217+0x60>
 1066306:	ff 
 1066307:	c4 c1 79 11 86 00 01 	vmovupd %xmm0,0x100(%r14)
 106630e:	00 00 
 1066310:	4d 89 be 10 01 00 00 	mov    %r15,0x110(%r14)
 1066317:	e9 f9 06 00 00       	jmp    1066a15 <my.interpreter::evaluate+0x1a45>
 106631c:	84 d2                	test   %dl,%dl
 106631e:	0f 84 06 07 00 00    	je     1066a2a <my.interpreter::evaluate+0x1a5a>
 1066324:	41 80 f9 26          	cmp    $0x26,%r9b
 1066328:	4d 89 ec             	mov    %r13,%r12
 106632b:	77 14                	ja     1066341 <my.interpreter::evaluate+0x1371>
 106632d:	41 0f b6 c9          	movzbl %r9b,%ecx
 1066331:	48 8d 15 70 13 fa ff 	lea    -0x5ec90(%rip),%rdx        # 10076a8 <core_number_pairs+0x448>
 1066338:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 106633c:	48 01 d1             	add    %rdx,%rcx
 106633f:	ff e1                	jmp    *%rcx
 1066341:	c5 fb 59 c1          	vmulsd %xmm1,%xmm0,%xmm0
 1066345:	c4 e1 f9 7e c1       	vmovq  %xmm0,%rcx
 106634a:	41 b8 02 00 00 00    	mov    $0x2,%r8d
 1066350:	41 f6 c2 01          	test   $0x1,%r10b
 1066354:	0f 84 51 01 00 00    	je     10664ab <my.interpreter::evaluate+0x14db>
 106635a:	e9 4e 02 00 00       	jmp    10665ad <my.interpreter::evaluate+0x15dd>
 106635f:	48 8d 3d da bd fa ff 	lea    -0x54226(%rip),%rdi        # 1012140 <core_number_pairs+0xaee0>
 1066366:	e8 95 de fb ff       	call   1024200 <myl_core_owned_octets_copy>
 106636b:	48 89 c3             	mov    %rax,%rbx
 106636e:	48 8d 3d eb f4 01 00 	lea    0x1f4eb(%rip),%rdi        # 1085860 <core_durable_error.verbs+0x6150>
 1066375:	e8 46 07 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 106637a:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 106637f:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 1066384:	48 8d 3d 75 c4 01 00 	lea    0x1c475(%rip),%rdi        # 1082800 <core_durable_error.verbs+0x30f0>
 106638b:	e9 53 06 00 00       	jmp    10669e3 <my.interpreter::evaluate+0x1a13>
 1066390:	4c 89 dd             	mov    %r11,%rbp
 1066393:	48 8d 3d e6 bd fa ff 	lea    -0x5421a(%rip),%rdi        # 1012180 <core_number_pairs+0xaf20>
 106639a:	e8 61 de fb ff       	call   1024200 <myl_core_owned_octets_copy>
 106639f:	48 8d 3d fa f6 01 00 	lea    0x1f6fa(%rip),%rdi        # 1085aa0 <core_durable_error.verbs+0x6390>
 10663a6:	e8 15 07 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 10663ab:	c5 fa 7e 44 24 40    	vmovq  0x40(%rsp),%xmm0
 10663b1:	c4 e1 f9 6e c8       	vmovq  %rax,%xmm1
 10663b6:	c5 f1 6c c0          	vpunpcklqdq %xmm0,%xmm1,%xmm0
 10663ba:	c5 f9 7f 04 24       	vmovdqa %xmm0,(%rsp)
 10663bf:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
 10663c4:	4d 89 fa             	mov    %r15,%r10
 10663c7:	e9 f0 03 00 00       	jmp    10667bc <my.interpreter::evaluate+0x17ec>
 10663cc:	40 0f b6 c6          	movzbl %sil,%eax
 10663d0:	83 f8 01             	cmp    $0x1,%eax
 10663d3:	c5 f9 29 44 24 20    	vmovapd %xmm0,0x20(%rsp)
 10663d9:	48 8d 3d 80 be fa ff 	lea    -0x54180(%rip),%rdi        # 1012260 <core_number_pairs+0xb000>
 10663e0:	0f 84 4c 04 00 00    	je     1066832 <my.interpreter::evaluate+0x1862>
 10663e6:	85 c0                	test   %eax,%eax
 10663e8:	0f 85 52 04 00 00    	jne    1066840 <my.interpreter::evaluate+0x1870>
 10663ee:	e8 0d de fb ff       	call   1024200 <myl_core_owned_octets_copy>
 10663f3:	48 8d 3d 06 fa 01 00 	lea    0x1fa06(%rip),%rdi        # 1085e00 <core_durable_error.verbs+0x66f0>
 10663fa:	e9 4d 04 00 00       	jmp    106684c <my.interpreter::evaluate+0x187c>
 10663ff:	40 80 fd 01          	cmp    $0x1,%bpl
 1066403:	75 38                	jne    106643d <my.interpreter::evaluate+0x146d>
 1066405:	45 31 e7             	xor    %r12d,%r15d
 1066408:	41 80 f7 01          	xor    $0x1,%r15b
 106640c:	eb 45                	jmp    1066453 <my.interpreter::evaluate+0x1483>
 106640e:	40 80 fd 01          	cmp    $0x1,%bpl
 1066412:	75 64                	jne    1066478 <my.interpreter::evaluate+0x14a8>
 1066414:	45 31 e7             	xor    %r12d,%r15d
 1066417:	41 80 f7 01          	xor    $0x1,%r15b
 106641b:	eb 71                	jmp    106648e <my.interpreter::evaluate+0x14be>
 106641d:	40 80 fd 02          	cmp    $0x2,%bpl
 1066421:	75 1a                	jne    106643d <my.interpreter::evaluate+0x146d>
 1066423:	c4 c1 f9 6e c4       	vmovq  %r12,%xmm0
 1066428:	c4 c1 f9 6e cf       	vmovq  %r15,%xmm1
 106642d:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 1066432:	c4 c1 f9 7e c7       	vmovq  %xmm0,%r15
 1066437:	41 83 e7 01          	and    $0x1,%r15d
 106643b:	eb 16                	jmp    1066453 <my.interpreter::evaluate+0x1483>
 106643d:	45 31 ff             	xor    %r15d,%r15d
 1066440:	eb 11                	jmp    1066453 <my.interpreter::evaluate+0x1483>
 1066442:	40 80 fd 03          	cmp    $0x3,%bpl
 1066446:	0f 94 c1             	sete   %cl
 1066449:	4d 39 fc             	cmp    %r15,%r12
 106644c:	41 0f 94 c7          	sete   %r15b
 1066450:	41 20 cf             	and    %cl,%r15b
 1066453:	4d 89 ec             	mov    %r13,%r12
 1066456:	eb 3c                	jmp    1066494 <my.interpreter::evaluate+0x14c4>
 1066458:	40 80 fd 02          	cmp    $0x2,%bpl
 106645c:	75 1a                	jne    1066478 <my.interpreter::evaluate+0x14a8>
 106645e:	c4 c1 f9 6e c4       	vmovq  %r12,%xmm0
 1066463:	c4 c1 f9 6e cf       	vmovq  %r15,%xmm1
 1066468:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 106646d:	c4 c1 f9 7e c7       	vmovq  %xmm0,%r15
 1066472:	41 83 e7 01          	and    $0x1,%r15d
 1066476:	eb 16                	jmp    106648e <my.interpreter::evaluate+0x14be>
 1066478:	45 31 ff             	xor    %r15d,%r15d
 106647b:	eb 11                	jmp    106648e <my.interpreter::evaluate+0x14be>
 106647d:	40 80 fd 03          	cmp    $0x3,%bpl
 1066481:	0f 94 c1             	sete   %cl
 1066484:	4d 39 fc             	cmp    %r15,%r12
 1066487:	41 0f 94 c7          	sete   %r15b
 106648b:	41 20 cf             	and    %cl,%r15b
 106648e:	4d 89 ec             	mov    %r13,%r12
 1066491:	41 f6 d7             	not    %r15b
 1066494:	41 0f b6 cf          	movzbl %r15b,%ecx
 1066498:	83 e1 01             	and    $0x1,%ecx
 106649b:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 10664a1:	41 f6 c2 01          	test   $0x1,%r10b
 10664a5:	0f 85 02 01 00 00    	jne    10665ad <my.interpreter::evaluate+0x15dd>
 10664ab:	48 89 b3 80 00 00 00 	mov    %rsi,0x80(%rbx)
 10664b2:	4c 8b 4b 78          	mov    0x78(%rbx),%r9
 10664b6:	49 8b 51 08          	mov    0x8(%r9),%rdx
 10664ba:	48 39 d6             	cmp    %rdx,%rsi
 10664bd:	4c 8b 14 24          	mov    (%rsp),%r10
 10664c1:	0f 83 44 08 00 00    	jae    1066d0b <my.interpreter::evaluate+0x1d3b>
 10664c7:	48 89 f0             	mov    %rsi,%rax
 10664ca:	48 ff c8             	dec    %rax
 10664cd:	0f 80 b9 0b 00 00    	jo     106708c <my.interpreter::evaluate+0x20bc>
 10664d3:	48 39 d0             	cmp    %rdx,%rax
 10664d6:	0f 83 51 08 00 00    	jae    1066d2d <my.interpreter::evaluate+0x1d5d>
 10664dc:	48 89 c6             	mov    %rax,%rsi
 10664df:	48 c1 e6 04          	shl    $0x4,%rsi
 10664e3:	4d 89 44 31 20       	mov    %r8,0x20(%r9,%rsi,1)
 10664e8:	49 89 4c 31 28       	mov    %rcx,0x28(%r9,%rsi,1)
 10664ed:	4c 89 4b 78          	mov    %r9,0x78(%rbx)
 10664f1:	31 c9                	xor    %ecx,%ecx
 10664f3:	49 89 0e             	mov    %rcx,(%r14)
 10664f6:	49 89 46 08          	mov    %rax,0x8(%r14)
 10664fa:	49 89 56 10          	mov    %rdx,0x10(%r14)
 10664fe:	4d 89 96 00 01 00 00 	mov    %r10,0x100(%r14)
 1066505:	4d 89 9e 08 01 00 00 	mov    %r11,0x108(%r14)
 106650c:	e9 fd 04 00 00       	jmp    1066a0e <my.interpreter::evaluate+0x1a3e>
 1066511:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 1066516:	44 0f b6 f1          	movzbl %cl,%r14d
 106651a:	48 89 df             	mov    %rbx,%rdi
 106651d:	44 89 f6             	mov    %r14d,%esi
 1066520:	4c 89 e2             	mov    %r12,%rdx
 1066523:	e8 98 8e 00 00       	call   106f3c0 <my.interpreter::is_string>
 1066528:	a8 01                	test   $0x1,%al
 106652a:	0f 84 20 05 00 00    	je     1066a50 <my.interpreter::evaluate+0x1a80>
 1066530:	40 0f b6 ed          	movzbl %bpl,%ebp
 1066534:	48 89 df             	mov    %rbx,%rdi
 1066537:	89 ee                	mov    %ebp,%esi
 1066539:	4c 89 fa             	mov    %r15,%rdx
 106653c:	e8 7f 8e 00 00       	call   106f3c0 <my.interpreter::is_string>
 1066541:	a8 01                	test   $0x1,%al
 1066543:	0f 84 07 05 00 00    	je     1066a50 <my.interpreter::evaluate+0x1a80>
 1066549:	44 89 f7             	mov    %r14d,%edi
 106654c:	4c 89 e6             	mov    %r12,%rsi
 106654f:	e8 ec 57 00 00       	call   106bd40 <my.interpreter::as_obj>
 1066554:	49 89 c6             	mov    %rax,%r14
 1066557:	89 ef                	mov    %ebp,%edi
 1066559:	4c 89 fe             	mov    %r15,%rsi
 106655c:	e8 df 57 00 00       	call   106bd40 <my.interpreter::as_obj>
 1066561:	48 8d bc 24 78 02 00 	lea    0x278(%rsp),%rdi
 1066568:	00 
 1066569:	48 89 de             	mov    %rbx,%rsi
 106656c:	4c 89 f2             	mov    %r14,%rdx
 106656f:	48 89 c1             	mov    %rax,%rcx
 1066572:	e8 09 73 00 00       	call   106d880 <my.lox_strings::concat>
 1066577:	48 8b 8c 24 78 02 00 	mov    0x278(%rsp),%rcx
 106657e:	00 
 106657f:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 1066586:	48 89 c6             	mov    %rax,%rsi
 1066589:	48 ff ce             	dec    %rsi
 106658c:	41 0f 90 c2          	seto   %r10b
 1066590:	41 b8 03 00 00 00    	mov    $0x3,%r8d
 1066596:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 106659b:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 10665a0:	4d 89 ec             	mov    %r13,%r12
 10665a3:	41 f6 c2 01          	test   $0x1,%r10b
 10665a7:	0f 84 fe fe ff ff    	je     10664ab <my.interpreter::evaluate+0x14db>
 10665ad:	48 8d 3d fc f0 01 00 	lea    0x1f0fc(%rip),%rdi        # 10856b0 <core_durable_error.verbs+0x5fa0>
 10665b4:	ba 01 00 00 00       	mov    $0x1,%edx
 10665b9:	48 89 c6             	mov    %rax,%rsi
 10665bc:	e8 3f e1 fb ff       	call   1024700 <myl_core_trap>
 10665c1:	48 8d 3d 68 c2 01 00 	lea    0x1c268(%rip),%rdi        # 1082830 <core_durable_error.verbs+0x3120>
 10665c8:	c5 f9 29 04 24       	vmovapd %xmm0,(%rsp)
 10665cd:	e8 2e 05 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10665d2:	c5 f9 28 04 24       	vmovapd (%rsp),%xmm0
 10665d7:	e9 ca eb ff ff       	jmp    10651a6 <my.interpreter::evaluate+0x1d6>
 10665dc:	48 8d 54 24 50       	lea    0x50(%rsp),%rdx
 10665e1:	48 8d 3d b8 f1 01 00 	lea    0x1f1b8(%rip),%rdi        # 10857a0 <core_durable_error.verbs+0x6090>
 10665e8:	e9 17 02 00 00       	jmp    1066804 <my.interpreter::evaluate+0x1834>
 10665ed:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 10665f2:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 10665f7:	48 8d 3d 32 f2 01 00 	lea    0x1f232(%rip),%rdi        # 1085830 <core_durable_error.verbs+0x6120>
 10665fe:	e8 fd 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066603:	48 8d 3d f6 c1 01 00 	lea    0x1c1f6(%rip),%rdi        # 1082800 <core_durable_error.verbs+0x30f0>
 106660a:	e9 d4 03 00 00       	jmp    10669e3 <my.interpreter::evaluate+0x1a13>
 106660f:	4c 89 dd             	mov    %r11,%rbp
 1066612:	c5 fa 6f 44 24 50    	vmovdqu 0x50(%rsp),%xmm0
 1066618:	c5 f9 7f 04 24       	vmovdqa %xmm0,(%rsp)
 106661d:	48 8d 3d 4c f4 01 00 	lea    0x1f44c(%rip),%rdi        # 1085a70 <core_durable_error.verbs+0x6360>
 1066624:	e9 8e 01 00 00       	jmp    10667b7 <my.interpreter::evaluate+0x17e7>
 1066629:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 106662e:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 1066633:	48 8d 3d 06 ee 01 00 	lea    0x1ee06(%rip),%rdi        # 1085440 <core_durable_error.verbs+0x5d30>
 106663a:	e8 c1 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 106663f:	e9 98 03 00 00       	jmp    10669dc <my.interpreter::evaluate+0x1a0c>
 1066644:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 1066649:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
 106664e:	48 8b 54 24 58       	mov    0x58(%rsp),%rdx
 1066653:	48 8d 3d 06 ef 01 00 	lea    0x1ef06(%rip),%rdi        # 1085560 <core_durable_error.verbs+0x5e50>
 106665a:	e9 10 01 00 00       	jmp    106676f <my.interpreter::evaluate+0x179f>
 106665f:	48 89 f9             	mov    %rdi,%rcx
 1066662:	48 8d 3d 47 f3 01 00 	lea    0x1f347(%rip),%rdi        # 10859b0 <core_durable_error.verbs+0x62a0>
 1066669:	c5 f9 10 44 24 50    	vmovupd 0x50(%rsp),%xmm0
 106666f:	c5 f9 29 04 24       	vmovapd %xmm0,(%rsp)
 1066674:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 1066679:	e8 82 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 106667e:	48 8d 3d db c1 01 00 	lea    0x1c1db(%rip),%rdi        # 1082860 <core_durable_error.verbs+0x3150>
 1066685:	e8 76 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 106668a:	b8 01 00 00 00       	mov    $0x1,%eax
 106668f:	48 89 cf             	mov    %rcx,%rdi
 1066692:	c5 f9 28 04 24       	vmovapd (%rsp),%xmm0
 1066697:	e9 ac fb ff ff       	jmp    1066248 <my.interpreter::evaluate+0x1278>
 106669c:	c5 f9 29 44 24 20    	vmovapd %xmm0,0x20(%rsp)
 10666a2:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
 10666a7:	48 8b 54 24 58       	mov    0x58(%rsp),%rdx
 10666ac:	48 8d 3d 1d f7 01 00 	lea    0x1f71d(%rip),%rdi        # 1085dd0 <core_durable_error.verbs+0x66c0>
 10666b3:	e8 48 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10666b8:	49 89 de             	mov    %rbx,%r14
 10666bb:	e9 95 01 00 00       	jmp    1066855 <my.interpreter::evaluate+0x1885>
 10666c0:	48 89 df             	mov    %rbx,%rdi
 10666c3:	4c 89 fe             	mov    %r15,%rsi
 10666c6:	e8 65 2a 00 00       	call   1069130 <my.heap::string_chars>
 10666cb:	48 89 c3             	mov    %rax,%rbx
 10666ce:	48 8d 3d 2b c0 fa ff 	lea    -0x53fd5(%rip),%rdi        # 1012700 <core_number_pairs+0xb4a0>
 10666d5:	48 89 c6             	mov    %rax,%rsi
 10666d8:	e8 a3 86 fc ff       	call   102ed80 <myl_core_bytes_concat>
 10666dd:	4d 89 f4             	mov    %r14,%r12
 10666e0:	49 89 c6             	mov    %rax,%r14
 10666e3:	48 89 df             	mov    %rbx,%rdi
 10666e6:	e8 95 d2 fb ff       	call   1023980 <myl_core_drop_owned>
 10666eb:	48 8d 35 0e ba fa ff 	lea    -0x545f2(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 10666f2:	4c 89 f7             	mov    %r14,%rdi
 10666f5:	e8 86 86 fc ff       	call   102ed80 <myl_core_bytes_concat>
 10666fa:	49 89 c7             	mov    %rax,%r15
 10666fd:	4c 89 f7             	mov    %r14,%rdi
 1066700:	4d 89 e6             	mov    %r12,%r14
 1066703:	e8 78 d2 fb ff       	call   1023980 <myl_core_drop_owned>
 1066708:	4c 89 ff             	mov    %r15,%rdi
 106670b:	e8 f0 da fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066710:	48 89 c3             	mov    %rax,%rbx
 1066713:	4c 89 ff             	mov    %r15,%rdi
 1066716:	e8 65 d2 fb ff       	call   1023980 <myl_core_drop_owned>
 106671b:	48 8d 3d 1e f6 01 00 	lea    0x1f61e(%rip),%rdi        # 1085d40 <core_durable_error.verbs+0x6630>
 1066722:	e8 99 03 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066727:	48 8d 3d 92 c1 01 00 	lea    0x1c192(%rip),%rdi        # 10828c0 <core_durable_error.verbs+0x31b0>
 106672e:	e8 cd 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066733:	b8 01 00 00 00       	mov    $0x1,%eax
 1066738:	48 8b 8c 24 e8 04 00 	mov    0x4e8(%rsp),%rcx
 106673f:	00 
 1066740:	44 0f b6 a4 24 f0 04 	movzbl 0x4f0(%rsp),%r12d
 1066747:	00 00 
 1066749:	48 8b 54 24 20       	mov    0x20(%rsp),%rdx
 106674e:	e9 16 f7 ff ff       	jmp    1065e69 <my.interpreter::evaluate+0xe99>
 1066753:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 1066758:	48 8b 84 24 68 01 00 	mov    0x168(%rsp),%rax
 106675f:	00 
 1066760:	48 8b 94 24 70 01 00 	mov    0x170(%rsp),%rdx
 1066767:	00 
 1066768:	48 8d 3d 21 ee 01 00 	lea    0x1ee21(%rip),%rdi        # 1085590 <core_durable_error.verbs+0x5e80>
 106676f:	e8 8c 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066774:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 1066779:	48 8d 3d 20 c0 01 00 	lea    0x1c020(%rip),%rdi        # 10827a0 <core_durable_error.verbs+0x3090>
 1066780:	e8 7b 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066785:	b9 01 00 00 00       	mov    $0x1,%ecx
 106678a:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 106678f:	e9 5f fd ff ff       	jmp    10664f3 <my.interpreter::evaluate+0x1523>
 1066794:	c5 f9 29 04 24       	vmovapd %xmm0,(%rsp)
 1066799:	48 8d 3d 60 f0 01 00 	lea    0x1f060(%rip),%rdi        # 1085800 <core_durable_error.verbs+0x60f0>
 10667a0:	eb 70                	jmp    1066812 <my.interpreter::evaluate+0x1842>
 10667a2:	c5 fa 6f 84 24 68 01 	vmovdqu 0x168(%rsp),%xmm0
 10667a9:	00 00 
 10667ab:	c5 f9 7f 04 24       	vmovdqa %xmm0,(%rsp)
 10667b0:	48 8d 3d 19 f3 01 00 	lea    0x1f319(%rip),%rdi        # 1085ad0 <core_durable_error.verbs+0x63c0>
 10667b7:	e8 44 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10667bc:	48 8d 3d cd c0 01 00 	lea    0x1c0cd(%rip),%rdi        # 1082890 <core_durable_error.verbs+0x3180>
 10667c3:	e8 38 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10667c8:	b8 01 00 00 00       	mov    $0x1,%eax
 10667cd:	c5 f9 28 04 24       	vmovapd (%rsp),%xmm0
 10667d2:	49 89 06             	mov    %rax,(%r14)
 10667d5:	c4 c1 79 11 46 08    	vmovupd %xmm0,0x8(%r14)
 10667db:	49 89 ae 00 01 00 00 	mov    %rbp,0x100(%r14)
 10667e2:	4d 89 86 08 01 00 00 	mov    %r8,0x108(%r14)
 10667e9:	4d 89 96 10 01 00 00 	mov    %r10,0x110(%r14)
 10667f0:	e9 20 02 00 00       	jmp    1066a15 <my.interpreter::evaluate+0x1a45>
 10667f5:	48 8d 3d d4 ef 01 00 	lea    0x1efd4(%rip),%rdi        # 10857d0 <core_durable_error.verbs+0x60c0>
 10667fc:	48 8d 94 24 68 01 00 	lea    0x168(%rsp),%rdx
 1066803:	00 
 1066804:	c5 f9 10 02          	vmovupd (%rdx),%xmm0
 1066808:	c5 f9 29 04 24       	vmovapd %xmm0,(%rsp)
 106680d:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 1066812:	e8 e9 02 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066817:	48 8d 3d b2 bf 01 00 	lea    0x1bfb2(%rip),%rdi        # 10827d0 <core_durable_error.verbs+0x30c0>
 106681e:	e8 dd 02 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066823:	ba 01 00 00 00       	mov    $0x1,%edx
 1066828:	c5 f9 28 04 24       	vmovapd (%rsp),%xmm0
 106682d:	e9 34 f9 ff ff       	jmp    1066166 <my.interpreter::evaluate+0x1196>
 1066832:	e8 c9 d9 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066837:	48 8d 3d f2 f5 01 00 	lea    0x1f5f2(%rip),%rdi        # 1085e30 <core_durable_error.verbs+0x6720>
 106683e:	eb 0c                	jmp    106684c <my.interpreter::evaluate+0x187c>
 1066840:	e8 bb d9 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066845:	48 8d 3d 14 f6 01 00 	lea    0x1f614(%rip),%rdi        # 1085e60 <core_durable_error.verbs+0x6750>
 106684c:	e8 6f 02 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066851:	48 8b 14 24          	mov    (%rsp),%rdx
 1066855:	48 8d 3d 94 c0 01 00 	lea    0x1c094(%rip),%rdi        # 10828f0 <core_durable_error.verbs+0x31e0>
 106685c:	e8 9f 02 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066861:	b9 01 00 00 00       	mov    $0x1,%ecx
 1066866:	c5 f9 28 44 24 20    	vmovapd 0x20(%rsp),%xmm0
 106686c:	e9 83 fa ff ff       	jmp    10662f4 <my.interpreter::evaluate+0x1324>
 1066871:	4c 89 ef             	mov    %r13,%rdi
 1066874:	48 89 ee             	mov    %rbp,%rsi
 1066877:	e8 b4 28 00 00       	call   1069130 <my.heap::string_chars>
 106687c:	48 89 c3             	mov    %rax,%rbx
 106687f:	48 8d 3d 7a be fa ff 	lea    -0x54186(%rip),%rdi        # 1012700 <core_number_pairs+0xb4a0>
 1066886:	48 89 c6             	mov    %rax,%rsi
 1066889:	e8 f2 84 fc ff       	call   102ed80 <myl_core_bytes_concat>
 106688e:	49 89 c6             	mov    %rax,%r14
 1066891:	48 89 df             	mov    %rbx,%rdi
 1066894:	e8 e7 d0 fb ff       	call   1023980 <myl_core_drop_owned>
 1066899:	48 8d 35 60 b8 fa ff 	lea    -0x547a0(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 10668a0:	4c 89 f7             	mov    %r14,%rdi
 10668a3:	e8 d8 84 fc ff       	call   102ed80 <myl_core_bytes_concat>
 10668a8:	49 89 c7             	mov    %rax,%r15
 10668ab:	4c 89 f7             	mov    %r14,%rdi
 10668ae:	e8 cd d0 fb ff       	call   1023980 <myl_core_drop_owned>
 10668b3:	4c 89 ff             	mov    %r15,%rdi
 10668b6:	e8 45 d9 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 10668bb:	48 89 c3             	mov    %rax,%rbx
 10668be:	4c 89 ff             	mov    %r15,%rdi
 10668c1:	e8 ba d0 fb ff       	call   1023980 <myl_core_drop_owned>
 10668c6:	48 8d 3d c3 ef 01 00 	lea    0x1efc3(%rip),%rdi        # 1085890 <core_durable_error.verbs+0x6180>
 10668cd:	e8 ee 01 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 10668d2:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 10668d7:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 10668dc:	e9 9e fa ff ff       	jmp    106637f <my.interpreter::evaluate+0x13af>
 10668e1:	48 89 ef             	mov    %rbp,%rdi
 10668e4:	48 89 de             	mov    %rbx,%rsi
 10668e7:	e8 44 28 00 00       	call   1069130 <my.heap::string_chars>
 10668ec:	48 89 c3             	mov    %rax,%rbx
 10668ef:	48 8d 3d ca b7 fa ff 	lea    -0x54836(%rip),%rdi        # 10120c0 <core_number_pairs+0xae60>
 10668f6:	48 89 c6             	mov    %rax,%rsi
 10668f9:	e8 82 84 fc ff       	call   102ed80 <myl_core_bytes_concat>
 10668fe:	4d 89 f4             	mov    %r14,%r12
 1066901:	49 89 c6             	mov    %rax,%r14
 1066904:	48 89 df             	mov    %rbx,%rdi
 1066907:	e8 74 d0 fb ff       	call   1023980 <myl_core_drop_owned>
 106690c:	48 8d 35 ed b7 fa ff 	lea    -0x54813(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 1066913:	4c 89 f7             	mov    %r14,%rdi
 1066916:	e8 65 84 fc ff       	call   102ed80 <myl_core_bytes_concat>
 106691b:	49 89 c7             	mov    %rax,%r15
 106691e:	4c 89 f7             	mov    %r14,%rdi
 1066921:	4d 89 e6             	mov    %r12,%r14
 1066924:	e8 57 d0 fb ff       	call   1023980 <myl_core_drop_owned>
 1066929:	4c 89 ff             	mov    %r15,%rdi
 106692c:	e8 cf d8 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066931:	48 89 c3             	mov    %rax,%rbx
 1066934:	4c 89 ff             	mov    %r15,%rdi
 1066937:	e8 44 d0 fb ff       	call   1023980 <myl_core_drop_owned>
 106693c:	48 8d 3d ad f5 01 00 	lea    0x1f5ad(%rip),%rdi        # 1085ef0 <core_durable_error.verbs+0x67e0>
 1066943:	e8 78 01 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066948:	48 8d 3d d1 bf 01 00 	lea    0x1bfd1(%rip),%rdi        # 1082920 <core_durable_error.verbs+0x3210>
 106694f:	e8 ac 01 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066954:	b8 01 00 00 00       	mov    $0x1,%eax
 1066959:	4c 8b 9c 24 e8 04 00 	mov    0x4e8(%rsp),%r11
 1066960:	00 
 1066961:	4c 8b bc 24 f8 04 00 	mov    0x4f8(%rsp),%r15
 1066968:	00 
 1066969:	e9 58 f7 ff ff       	jmp    10660c6 <my.interpreter::evaluate+0x10f6>
 106696e:	4c 89 ef             	mov    %r13,%rdi
 1066971:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 1066976:	e8 b5 27 00 00       	call   1069130 <my.heap::string_chars>
 106697b:	48 89 c3             	mov    %rax,%rbx
 106697e:	48 8d 3d 3b b7 fa ff 	lea    -0x548c5(%rip),%rdi        # 10120c0 <core_number_pairs+0xae60>
 1066985:	48 89 c6             	mov    %rax,%rsi
 1066988:	e8 f3 83 fc ff       	call   102ed80 <myl_core_bytes_concat>
 106698d:	4d 89 f5             	mov    %r14,%r13
 1066990:	49 89 c6             	mov    %rax,%r14
 1066993:	48 89 df             	mov    %rbx,%rdi
 1066996:	e8 e5 cf fb ff       	call   1023980 <myl_core_drop_owned>
 106699b:	48 8d 35 5e b7 fa ff 	lea    -0x548a2(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 10669a2:	4c 89 f7             	mov    %r14,%rdi
 10669a5:	e8 d6 83 fc ff       	call   102ed80 <myl_core_bytes_concat>
 10669aa:	49 89 c7             	mov    %rax,%r15
 10669ad:	4c 89 f7             	mov    %r14,%rdi
 10669b0:	4d 89 ee             	mov    %r13,%r14
 10669b3:	e8 c8 cf fb ff       	call   1023980 <myl_core_drop_owned>
 10669b8:	4c 89 ff             	mov    %r15,%rdi
 10669bb:	e8 40 d8 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 10669c0:	48 89 c3             	mov    %rax,%rbx
 10669c3:	4c 89 ff             	mov    %r15,%rdi
 10669c6:	e8 b5 cf fb ff       	call   1023980 <myl_core_drop_owned>
 10669cb:	48 8d 3d 9e ea 01 00 	lea    0x1ea9e(%rip),%rdi        # 1085470 <core_durable_error.verbs+0x5d60>
 10669d2:	e8 e9 00 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 10669d7:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 10669dc:	48 8d 3d 8d bd 01 00 	lea    0x1bd8d(%rip),%rdi        # 1082770 <core_durable_error.verbs+0x3060>
 10669e3:	e8 18 01 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10669e8:	b8 01 00 00 00       	mov    $0x1,%eax
 10669ed:	c5 f9 28 04 24       	vmovapd (%rsp),%xmm0
 10669f2:	49 89 06             	mov    %rax,(%r14)
 10669f5:	49 89 5e 08          	mov    %rbx,0x8(%r14)
 10669f9:	49 89 4e 10          	mov    %rcx,0x10(%r14)
 10669fd:	c5 f9 54 05 1b d9 f9 	vandpd -0x626e5(%rip),%xmm0,%xmm0        # 1004320 <__anon_2217+0x60>
 1066a04:	ff 
 1066a05:	c4 c1 79 11 86 00 01 	vmovupd %xmm0,0x100(%r14)
 1066a0c:	00 00 
 1066a0e:	4d 89 a6 10 01 00 00 	mov    %r12,0x110(%r14)
 1066a15:	4c 89 f0             	mov    %r14,%rax
 1066a18:	48 81 c4 a8 04 00 00 	add    $0x4a8,%rsp
 1066a1f:	5b                   	pop    %rbx
 1066a20:	41 5c                	pop    %r12
 1066a22:	41 5d                	pop    %r13
 1066a24:	41 5e                	pop    %r14
 1066a26:	41 5f                	pop    %r15
 1066a28:	5d                   	pop    %rbp
 1066a29:	c3                   	ret
 1066a2a:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 1066a2f:	48 8d 3d 8a b7 fa ff 	lea    -0x54876(%rip),%rdi        # 10121c0 <core_number_pairs+0xaf60>
 1066a36:	e8 c5 d7 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066a3b:	48 8d 3d ae eb 01 00 	lea    0x1ebae(%rip),%rdi        # 10855f0 <core_durable_error.verbs+0x5ee0>
 1066a42:	e8 79 00 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066a47:	4d 89 ec             	mov    %r13,%r12
 1066a4a:	4c 8b 14 24          	mov    (%rsp),%r10
 1066a4e:	eb 24                	jmp    1066a74 <my.interpreter::evaluate+0x1aa4>
 1066a50:	48 8d 3d a9 b7 fa ff 	lea    -0x54857(%rip),%rdi        # 1012200 <core_number_pairs+0xafa0>
 1066a57:	e8 a4 d7 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066a5c:	48 8d 3d 5d eb 01 00 	lea    0x1eb5d(%rip),%rdi        # 10855c0 <core_durable_error.verbs+0x5eb0>
 1066a63:	e8 58 00 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066a68:	4c 8b 74 24 10       	mov    0x10(%rsp),%r14
 1066a6d:	4c 8b 14 24          	mov    (%rsp),%r10
 1066a71:	4d 89 ec             	mov    %r13,%r12
 1066a74:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 1066a79:	e9 fb fc ff ff       	jmp    1066779 <my.interpreter::evaluate+0x17a9>
 1066a7e:	48 89 f0             	mov    %rsi,%rax
 1066a81:	48 c1 f8 3f          	sar    $0x3f,%rax
 1066a85:	48 21 d0             	and    %rdx,%rax
 1066a88:	48 01 f0             	add    %rsi,%rax
 1066a8b:	48 39 d0             	cmp    %rdx,%rax
 1066a8e:	0f 82 6e e5 ff ff    	jb     1065002 <my.interpreter::evaluate+0x32>
 1066a94:	48 8d 3d a5 bc 01 00 	lea    0x1bca5(%rip),%rdi        # 1082740 <core_durable_error.verbs+0x3030>
 1066a9b:	e8 60 dc fb ff       	call   1024700 <myl_core_trap>
 1066aa0:	31 c9                	xor    %ecx,%ecx
 1066aa2:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 1066aa6:	eb 17                	jmp    1066abf <my.interpreter::evaluate+0x1aef>
 1066aa8:	c5 fb 5e c1          	vdivsd %xmm1,%xmm0,%xmm0
 1066aac:	e9 94 f8 ff ff       	jmp    1066345 <my.interpreter::evaluate+0x1375>
 1066ab1:	31 c9                	xor    %ecx,%ecx
 1066ab3:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 1066ab7:	eb 14                	jmp    1066acd <my.interpreter::evaluate+0x1afd>
 1066ab9:	31 c9                	xor    %ecx,%ecx
 1066abb:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
 1066abf:	0f 97 c1             	seta   %cl
 1066ac2:	e9 d4 f9 ff ff       	jmp    106649b <my.interpreter::evaluate+0x14cb>
 1066ac7:	31 c9                	xor    %ecx,%ecx
 1066ac9:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
 1066acd:	0f 93 c1             	setae  %cl
 1066ad0:	e9 c6 f9 ff ff       	jmp    106649b <my.interpreter::evaluate+0x14cb>
 1066ad5:	c5 fb 5c c1          	vsubsd %xmm1,%xmm0,%xmm0
 1066ad9:	e9 67 f8 ff ff       	jmp    1066345 <my.interpreter::evaluate+0x1375>
 1066ade:	48 89 f1             	mov    %rsi,%rcx
 1066ae1:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066ae5:	48 21 d1             	and    %rdx,%rcx
 1066ae8:	48 01 f1             	add    %rsi,%rcx
 1066aeb:	48 39 d1             	cmp    %rdx,%rcx
 1066aee:	0f 82 bc ed ff ff    	jb     10658b0 <my.interpreter::evaluate+0x8e0>
 1066af4:	48 8d 3d 55 be 01 00 	lea    0x1be55(%rip),%rdi        # 1082950 <core_durable_error.verbs+0x3240>
 1066afb:	e8 00 dc fb ff       	call   1024700 <myl_core_trap>
 1066b00:	48 89 f7             	mov    %rsi,%rdi
 1066b03:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066b07:	48 21 d7             	and    %rdx,%rdi
 1066b0a:	48 01 f7             	add    %rsi,%rdi
 1066b0d:	48 39 d7             	cmp    %rdx,%rdi
 1066b10:	0f 82 03 f1 ff ff    	jb     1065c19 <my.interpreter::evaluate+0xc49>
 1066b16:	48 8d 3d 93 bb 01 00 	lea    0x1bb93(%rip),%rdi        # 10826b0 <core_durable_error.verbs+0x2fa0>
 1066b1d:	e8 de db fb ff       	call   1024700 <myl_core_trap>
 1066b22:	49 89 c8             	mov    %rcx,%r8
 1066b25:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066b29:	49 21 d0             	and    %rdx,%r8
 1066b2c:	49 01 c8             	add    %rcx,%r8
 1066b2f:	49 39 d0             	cmp    %rdx,%r8
 1066b32:	0f 82 8a f1 ff ff    	jb     1065cc2 <my.interpreter::evaluate+0xcf2>
 1066b38:	48 8d 3d 71 bb 01 00 	lea    0x1bb71(%rip),%rdi        # 10826b0 <core_durable_error.verbs+0x2fa0>
 1066b3f:	48 89 ce             	mov    %rcx,%rsi
 1066b42:	e8 b9 db fb ff       	call   1024700 <myl_core_trap>
 1066b47:	48 89 c6             	mov    %rax,%rsi
 1066b4a:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066b4e:	48 21 d6             	and    %rdx,%rsi
 1066b51:	48 01 c6             	add    %rax,%rsi
 1066b54:	48 39 d6             	cmp    %rdx,%rsi
 1066b57:	0f 82 e6 f0 ff ff    	jb     1065c43 <my.interpreter::evaluate+0xc73>
 1066b5d:	48 8d 3d ac bb 01 00 	lea    0x1bbac(%rip),%rdi        # 1082710 <core_durable_error.verbs+0x3000>
 1066b64:	48 89 c6             	mov    %rax,%rsi
 1066b67:	e8 94 db fb ff       	call   1024700 <myl_core_trap>
 1066b6c:	48 89 f1             	mov    %rsi,%rcx
 1066b6f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066b73:	48 21 d1             	and    %rdx,%rcx
 1066b76:	48 01 f1             	add    %rsi,%rcx
 1066b79:	48 39 d1             	cmp    %rdx,%rcx
 1066b7c:	0f 82 e6 f0 ff ff    	jb     1065c68 <my.interpreter::evaluate+0xc98>
 1066b82:	48 8d 3d 27 be 01 00 	lea    0x1be27(%rip),%rdi        # 10829b0 <core_durable_error.verbs+0x32a0>
 1066b89:	e8 72 db fb ff       	call   1024700 <myl_core_trap>
 1066b8e:	48 8d 3d 7b bb 01 00 	lea    0x1bb7b(%rip),%rdi        # 1082710 <core_durable_error.verbs+0x3000>
 1066b95:	31 f6                	xor    %esi,%esi
 1066b97:	31 d2                	xor    %edx,%edx
 1066b99:	e8 62 db fb ff       	call   1024700 <myl_core_trap>
 1066b9e:	48 89 f1             	mov    %rsi,%rcx
 1066ba1:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066ba5:	48 21 d1             	and    %rdx,%rcx
 1066ba8:	48 01 f1             	add    %rsi,%rcx
 1066bab:	48 39 d1             	cmp    %rdx,%rcx
 1066bae:	0f 82 da f1 ff ff    	jb     1065d8e <my.interpreter::evaluate+0xdbe>
 1066bb4:	48 8d 3d f5 ba 01 00 	lea    0x1baf5(%rip),%rdi        # 10826b0 <core_durable_error.verbs+0x2fa0>
 1066bbb:	e8 40 db fb ff       	call   1024700 <myl_core_trap>
 1066bc0:	48 8d 3d 49 bb 01 00 	lea    0x1bb49(%rip),%rdi        # 1082710 <core_durable_error.verbs+0x3000>
 1066bc7:	31 f6                	xor    %esi,%esi
 1066bc9:	31 d2                	xor    %edx,%edx
 1066bcb:	e8 30 db fb ff       	call   1024700 <myl_core_trap>
 1066bd0:	49 89 f5             	mov    %rsi,%r13
 1066bd3:	49 c1 fd 3f          	sar    $0x3f,%r13
 1066bd7:	49 21 d5             	and    %rdx,%r13
 1066bda:	49 01 f5             	add    %rsi,%r13
 1066bdd:	49 39 d5             	cmp    %rdx,%r13
 1066be0:	0f 82 28 e8 ff ff    	jb     106540e <my.interpreter::evaluate+0x43e>
 1066be6:	48 8d 3d 03 ed 01 00 	lea    0x1ed03(%rip),%rdi        # 10858f0 <core_durable_error.verbs+0x61e0>
 1066bed:	e8 0e db fb ff       	call   1024700 <myl_core_trap>
 1066bf2:	48 89 f7             	mov    %rsi,%rdi
 1066bf5:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066bf9:	48 21 d7             	and    %rdx,%rdi
 1066bfc:	48 01 f7             	add    %rsi,%rdi
 1066bff:	48 39 d7             	cmp    %rdx,%rdi
 1066c02:	4d 89 ea             	mov    %r13,%r10
 1066c05:	0f 82 57 e9 ff ff    	jb     1065562 <my.interpreter::evaluate+0x592>
 1066c0b:	48 8d 3d 1e ef 01 00 	lea    0x1ef1e(%rip),%rdi        # 1085b30 <core_durable_error.verbs+0x6420>
 1066c12:	e8 e9 da fb ff       	call   1024700 <myl_core_trap>
 1066c17:	48 89 f1             	mov    %rsi,%rcx
 1066c1a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066c1e:	48 21 d1             	and    %rdx,%rcx
 1066c21:	48 01 f1             	add    %rsi,%rcx
 1066c24:	48 39 d1             	cmp    %rdx,%rcx
 1066c27:	0f 82 63 ed ff ff    	jb     1065990 <my.interpreter::evaluate+0x9c0>
 1066c2d:	48 8d 3d 0c ee 01 00 	lea    0x1ee0c(%rip),%rdi        # 1085a40 <core_durable_error.verbs+0x6330>
 1066c34:	e8 c7 da fb ff       	call   1024700 <myl_core_trap>
 1066c39:	48 89 f7             	mov    %rsi,%rdi
 1066c3c:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066c40:	48 21 d7             	and    %rdx,%rdi
 1066c43:	48 01 f7             	add    %rsi,%rdi
 1066c46:	48 39 d7             	cmp    %rdx,%rdi
 1066c49:	0f 82 6e ee ff ff    	jb     1065abd <my.interpreter::evaluate+0xaed>
 1066c4f:	48 8d 3d 6a f2 01 00 	lea    0x1f26a(%rip),%rdi        # 1085ec0 <core_durable_error.verbs+0x67b0>
 1066c56:	e8 a5 da fb ff       	call   1024700 <myl_core_trap>
 1066c5b:	48 89 f7             	mov    %rsi,%rdi
 1066c5e:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066c62:	48 21 d7             	and    %rdx,%rdi
 1066c65:	48 01 f7             	add    %rsi,%rdi
 1066c68:	48 39 d7             	cmp    %rdx,%rdi
 1066c6b:	0f 82 c9 f1 ff ff    	jb     1065e3a <my.interpreter::evaluate+0xe6a>
 1066c71:	48 8d 3d f8 f0 01 00 	lea    0x1f0f8(%rip),%rdi        # 1085d70 <core_durable_error.verbs+0x6660>
 1066c78:	e8 83 da fb ff       	call   1024700 <myl_core_trap>
 1066c7d:	4c 89 f9             	mov    %r15,%rcx
 1066c80:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066c84:	48 21 d1             	and    %rdx,%rcx
 1066c87:	4c 01 f9             	add    %r15,%rcx
 1066c8a:	48 39 d1             	cmp    %rdx,%rcx
 1066c8d:	0f 82 a9 e7 ff ff    	jb     106543c <my.interpreter::evaluate+0x46c>
 1066c93:	48 8d 3d 86 ce 01 00 	lea    0x1ce86(%rip),%rdi        # 1083b20 <core_durable_error.verbs+0x4410>
 1066c9a:	4c 89 fe             	mov    %r15,%rsi
 1066c9d:	e8 5e da fb ff       	call   1024700 <myl_core_trap>
 1066ca2:	48 89 f7             	mov    %rsi,%rdi
 1066ca5:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066ca9:	48 21 d7             	and    %rdx,%rdi
 1066cac:	48 01 f7             	add    %rsi,%rdi
 1066caf:	48 39 d7             	cmp    %rdx,%rdi
 1066cb2:	0f 82 d1 e8 ff ff    	jb     1065589 <my.interpreter::evaluate+0x5b9>
 1066cb8:	48 8d 3d 61 ce 01 00 	lea    0x1ce61(%rip),%rdi        # 1083b20 <core_durable_error.verbs+0x4410>
 1066cbf:	e8 3c da fb ff       	call   1024700 <myl_core_trap>
 1066cc4:	49 89 c9             	mov    %rcx,%r9
 1066cc7:	49 c1 f9 3f          	sar    $0x3f,%r9
 1066ccb:	49 21 d1             	and    %rdx,%r9
 1066cce:	49 01 c9             	add    %rcx,%r9
 1066cd1:	49 39 d1             	cmp    %rdx,%r9
 1066cd4:	0f 82 47 eb ff ff    	jb     1065821 <my.interpreter::evaluate+0x851>
 1066cda:	48 8d 3d 9f e9 01 00 	lea    0x1e99f(%rip),%rdi        # 1085680 <core_durable_error.verbs+0x5f70>
 1066ce1:	48 89 ce             	mov    %rcx,%rsi
 1066ce4:	e8 17 da fb ff       	call   1024700 <myl_core_trap>
 1066ce9:	49 89 f1             	mov    %rsi,%r9
 1066cec:	49 c1 f9 3f          	sar    $0x3f,%r9
 1066cf0:	49 21 d1             	and    %rdx,%r9
 1066cf3:	49 01 f1             	add    %rsi,%r9
 1066cf6:	49 39 d1             	cmp    %rdx,%r9
 1066cf9:	0f 82 3d eb ff ff    	jb     106583c <my.interpreter::evaluate+0x86c>
 1066cff:	48 8d 3d 0a ea 01 00 	lea    0x1ea0a(%rip),%rdi        # 1085710 <core_durable_error.verbs+0x6000>
 1066d06:	e8 f5 d9 fb ff       	call   1024700 <myl_core_trap>
 1066d0b:	48 89 f0             	mov    %rsi,%rax
 1066d0e:	48 c1 f8 3f          	sar    $0x3f,%rax
 1066d12:	48 21 d0             	and    %rdx,%rax
 1066d15:	48 01 f0             	add    %rsi,%rax
 1066d18:	48 39 d0             	cmp    %rdx,%rax
 1066d1b:	0f 82 a6 f7 ff ff    	jb     10664c7 <my.interpreter::evaluate+0x14f7>
 1066d21:	48 8d 3d b8 e9 01 00 	lea    0x1e9b8(%rip),%rdi        # 10856e0 <core_durable_error.verbs+0x5fd0>
 1066d28:	e8 d3 d9 fb ff       	call   1024700 <myl_core_trap>
 1066d2d:	48 89 c6             	mov    %rax,%rsi
 1066d30:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066d34:	48 21 d6             	and    %rdx,%rsi
 1066d37:	48 01 c6             	add    %rax,%rsi
 1066d3a:	48 39 d6             	cmp    %rdx,%rsi
 1066d3d:	0f 82 9c f7 ff ff    	jb     10664df <my.interpreter::evaluate+0x150f>
 1066d43:	48 8d 3d 26 ea 01 00 	lea    0x1ea26(%rip),%rdi        # 1085770 <core_durable_error.verbs+0x6060>
 1066d4a:	48 89 c6             	mov    %rax,%rsi
 1066d4d:	e8 ae d9 fb ff       	call   1024700 <myl_core_trap>
 1066d52:	48 89 f1             	mov    %rsi,%rcx
 1066d55:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066d59:	48 21 d1             	and    %rdx,%rcx
 1066d5c:	48 01 f1             	add    %rsi,%rcx
 1066d5f:	48 39 d1             	cmp    %rdx,%rcx
 1066d62:	0f 82 bc e8 ff ff    	jb     1065624 <my.interpreter::evaluate+0x654>
 1066d68:	48 8d 3d 51 ee 01 00 	lea    0x1ee51(%rip),%rdi        # 1085bc0 <core_durable_error.verbs+0x64b0>
 1066d6f:	e8 8c d9 fb ff       	call   1024700 <myl_core_trap>
 1066d74:	49 89 f0             	mov    %rsi,%r8
 1066d77:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066d7b:	49 21 d0             	and    %rdx,%r8
 1066d7e:	49 01 f0             	add    %rsi,%r8
 1066d81:	49 39 d0             	cmp    %rdx,%r8
 1066d84:	0f 82 f1 e8 ff ff    	jb     106567b <my.interpreter::evaluate+0x6ab>
 1066d8a:	48 8d 3d 8f ee 01 00 	lea    0x1ee8f(%rip),%rdi        # 1085c20 <core_durable_error.verbs+0x6510>
 1066d91:	e8 6a d9 fb ff       	call   1024700 <myl_core_trap>
 1066d96:	48 89 f0             	mov    %rsi,%rax
 1066d99:	48 c1 f8 3f          	sar    $0x3f,%rax
 1066d9d:	48 21 d0             	and    %rdx,%rax
 1066da0:	48 01 f0             	add    %rsi,%rax
 1066da3:	48 39 d0             	cmp    %rdx,%rax
 1066da6:	0f 82 2a e9 ff ff    	jb     10656d6 <my.interpreter::evaluate+0x706>
 1066dac:	48 8d 3d cd ee 01 00 	lea    0x1eecd(%rip),%rdi        # 1085c80 <core_durable_error.verbs+0x6570>
 1066db3:	e8 48 d9 fb ff       	call   1024700 <myl_core_trap>
 1066db8:	48 89 c6             	mov    %rax,%rsi
 1066dbb:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066dbf:	48 21 d6             	and    %rdx,%rsi
 1066dc2:	48 01 c6             	add    %rax,%rsi
 1066dc5:	48 39 d6             	cmp    %rdx,%rsi
 1066dc8:	0f 82 20 e9 ff ff    	jb     10656ee <my.interpreter::evaluate+0x71e>
 1066dce:	48 8d 3d 0b ef 01 00 	lea    0x1ef0b(%rip),%rdi        # 1085ce0 <core_durable_error.verbs+0x65d0>
 1066dd5:	48 89 c6             	mov    %rax,%rsi
 1066dd8:	e8 23 d9 fb ff       	call   1024700 <myl_core_trap>
 1066ddd:	48 89 c7             	mov    %rax,%rdi
 1066de0:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066de4:	48 21 d7             	and    %rdx,%rdi
 1066de7:	48 01 c7             	add    %rax,%rdi
 1066dea:	48 39 d7             	cmp    %rdx,%rdi
 1066ded:	0f 82 b3 f0 ff ff    	jb     1065ea6 <my.interpreter::evaluate+0xed6>
 1066df3:	48 8d 3d b6 b8 01 00 	lea    0x1b8b6(%rip),%rdi        # 10826b0 <core_durable_error.verbs+0x2fa0>
 1066dfa:	48 89 c6             	mov    %rax,%rsi
 1066dfd:	e8 fe d8 fb ff       	call   1024700 <myl_core_trap>
 1066e02:	48 89 f1             	mov    %rsi,%rcx
 1066e05:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066e09:	48 21 d1             	and    %rdx,%rcx
 1066e0c:	48 01 f1             	add    %rsi,%rcx
 1066e0f:	48 39 d1             	cmp    %rdx,%rcx
 1066e12:	0f 82 b8 f0 ff ff    	jb     1065ed0 <my.interpreter::evaluate+0xf00>
 1066e18:	48 8d 3d f1 b8 01 00 	lea    0x1b8f1(%rip),%rdi        # 1082710 <core_durable_error.verbs+0x3000>
 1066e1f:	e8 dc d8 fb ff       	call   1024700 <myl_core_trap>
 1066e24:	48 89 f1             	mov    %rsi,%rcx
 1066e27:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066e2b:	48 21 d1             	and    %rdx,%rcx
 1066e2e:	48 01 f1             	add    %rsi,%rcx
 1066e31:	48 39 d1             	cmp    %rdx,%rcx
 1066e34:	0f 82 bb f0 ff ff    	jb     1065ef5 <my.interpreter::evaluate+0xf25>
 1066e3a:	48 8d 3d df f0 01 00 	lea    0x1f0df(%rip),%rdi        # 1085f20 <core_durable_error.verbs+0x6810>
 1066e41:	e8 ba d8 fb ff       	call   1024700 <myl_core_trap>
 1066e46:	49 89 c1             	mov    %rax,%r9
 1066e49:	49 c1 f9 3f          	sar    $0x3f,%r9
 1066e4d:	49 21 d1             	and    %rdx,%r9
 1066e50:	49 01 c1             	add    %rax,%r9
 1066e53:	49 39 d1             	cmp    %rdx,%r9
 1066e56:	0f 82 ea f0 ff ff    	jb     1065f46 <my.interpreter::evaluate+0xf76>
 1066e5c:	48 8d 3d 6d e6 01 00 	lea    0x1e66d(%rip),%rdi        # 10854d0 <core_durable_error.verbs+0x5dc0>
 1066e63:	48 89 c6             	mov    %rax,%rsi
 1066e66:	e8 95 d8 fb ff       	call   1024700 <myl_core_trap>
 1066e6b:	48 89 f7             	mov    %rsi,%rdi
 1066e6e:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066e72:	48 21 d7             	and    %rdx,%rdi
 1066e75:	48 01 f7             	add    %rsi,%rdi
 1066e78:	48 39 d7             	cmp    %rdx,%rdi
 1066e7b:	0f 82 94 f1 ff ff    	jb     1066015 <my.interpreter::evaluate+0x1045>
 1066e81:	48 8d 3d f8 ea 01 00 	lea    0x1eaf8(%rip),%rdi        # 1085980 <core_durable_error.verbs+0x6270>
 1066e88:	e8 73 d8 fb ff       	call   1024700 <myl_core_trap>
 1066e8d:	49 89 f0             	mov    %rsi,%r8
 1066e90:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066e94:	49 21 c0             	and    %rax,%r8
 1066e97:	49 01 f0             	add    %rsi,%r8
 1066e9a:	49 39 c0             	cmp    %rax,%r8
 1066e9d:	0f 82 ed f1 ff ff    	jb     1066090 <my.interpreter::evaluate+0x10c0>
 1066ea3:	48 8d 3d d6 f0 01 00 	lea    0x1f0d6(%rip),%rdi        # 1085f80 <core_durable_error.verbs+0x6870>
 1066eaa:	48 89 c2             	mov    %rax,%rdx
 1066ead:	e8 4e d8 fb ff       	call   1024700 <myl_core_trap>
 1066eb2:	48 89 f1             	mov    %rsi,%rcx
 1066eb5:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066eb9:	48 21 d1             	and    %rdx,%rcx
 1066ebc:	48 01 f1             	add    %rsi,%rcx
 1066ebf:	48 39 d1             	cmp    %rdx,%rcx
 1066ec2:	0f 82 1b f3 ff ff    	jb     10661e3 <my.interpreter::evaluate+0x1213>
 1066ec8:	48 8d 3d 61 e6 01 00 	lea    0x1e661(%rip),%rdi        # 1085530 <core_durable_error.verbs+0x5e20>
 1066ecf:	e8 2c d8 fb ff       	call   1024700 <myl_core_trap>
 1066ed4:	48 8d 3d 35 e5 01 00 	lea    0x1e535(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066edb:	e8 a0 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066ee0:	48 8d 3d 29 e5 01 00 	lea    0x1e529(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066ee7:	e8 94 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066eec:	48 8d 3d 1d e5 01 00 	lea    0x1e51d(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066ef3:	e8 88 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066ef8:	48 8d 3d 11 e5 01 00 	lea    0x1e511(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066eff:	e8 7c 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f04:	48 8d 3d 05 e5 01 00 	lea    0x1e505(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066f0b:	e8 70 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f10:	0f b6 c0             	movzbl %al,%eax
 1066f13:	83 f8 01             	cmp    $0x1,%eax
 1066f16:	0f 84 ba 00 00 00    	je     1066fd6 <my.interpreter::evaluate+0x2006>
 1066f1c:	85 c0                	test   %eax,%eax
 1066f1e:	0f 85 be 00 00 00    	jne    1066fe2 <my.interpreter::evaluate+0x2012>
 1066f24:	48 8d 3d f5 e3 01 00 	lea    0x1e3f5(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x5c10>
 1066f2b:	e8 50 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f30:	0f b6 c2             	movzbl %dl,%eax
 1066f33:	83 f8 01             	cmp    $0x1,%eax
 1066f36:	0f 84 02 01 00 00    	je     106703e <my.interpreter::evaluate+0x206e>
 1066f3c:	85 c0                	test   %eax,%eax
 1066f3e:	0f 85 06 01 00 00    	jne    106704a <my.interpreter::evaluate+0x207a>
 1066f44:	48 8d 3d d5 e3 01 00 	lea    0x1e3d5(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x5c10>
 1066f4b:	e8 30 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f50:	83 fa 01             	cmp    $0x1,%edx
 1066f53:	0f 84 69 01 00 00    	je     10670c2 <my.interpreter::evaluate+0x20f2>
 1066f59:	85 d2                	test   %edx,%edx
 1066f5b:	0f 85 6d 01 00 00    	jne    10670ce <my.interpreter::evaluate+0x20fe>
 1066f61:	48 8d 3d b8 e3 01 00 	lea    0x1e3b8(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x5c10>
 1066f68:	e8 13 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f6d:	0f b6 c2             	movzbl %dl,%eax
 1066f70:	83 f8 01             	cmp    $0x1,%eax
 1066f73:	0f 84 e6 01 00 00    	je     106715f <my.interpreter::evaluate+0x218f>
 1066f79:	85 c0                	test   %eax,%eax
 1066f7b:	0f 85 ea 01 00 00    	jne    106716b <my.interpreter::evaluate+0x219b>
 1066f81:	48 8d 3d 98 e3 01 00 	lea    0x1e398(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x5c10>
 1066f88:	e8 f3 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f8d:	48 8d 3d 4c b7 01 00 	lea    0x1b74c(%rip),%rdi        # 10826e0 <core_durable_error.verbs+0x2fd0>
 1066f94:	e8 e7 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f99:	48 8d 3d 40 b7 01 00 	lea    0x1b740(%rip),%rdi        # 10826e0 <core_durable_error.verbs+0x2fd0>
 1066fa0:	e8 db 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1066fa5:	48 8d 3d 34 ba 01 00 	lea    0x1ba34(%rip),%rdi        # 10829e0 <core_durable_error.verbs+0x32d0>
 1066fac:	ba 01 00 00 00       	mov    $0x1,%edx
 1066fb1:	e8 4a d7 fb ff       	call   1024700 <myl_core_trap>
 1066fb6:	48 8d 3d 53 ed 01 00 	lea    0x1ed53(%rip),%rdi        # 1085d10 <core_durable_error.verbs+0x6600>
 1066fbd:	ba 01 00 00 00       	mov    $0x1,%edx
 1066fc2:	48 89 c6             	mov    %rax,%rsi
 1066fc5:	e8 36 d7 fb ff       	call   1024700 <myl_core_trap>
 1066fca:	48 8d 3d 0f b7 01 00 	lea    0x1b70f(%rip),%rdi        # 10826e0 <core_durable_error.verbs+0x2fd0>
 1066fd1:	e8 aa 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1066fd6:	48 8d 3d 73 e3 01 00 	lea    0x1e373(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x5c40>
 1066fdd:	e8 9e 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1066fe2:	48 8d 3d 97 e3 01 00 	lea    0x1e397(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x5c70>
 1066fe9:	e8 92 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1066fee:	48 8d 3d cb e8 01 00 	lea    0x1e8cb(%rip),%rdi        # 10858c0 <core_durable_error.verbs+0x61b0>
 1066ff5:	ba 01 00 00 00       	mov    $0x1,%edx
 1066ffa:	48 89 c6             	mov    %rax,%rsi
 1066ffd:	e8 fe d6 fb ff       	call   1024700 <myl_core_trap>
 1067002:	48 8d 3d f7 ea 01 00 	lea    0x1eaf7(%rip),%rdi        # 1085b00 <core_durable_error.verbs+0x63f0>
 1067009:	ba 01 00 00 00       	mov    $0x1,%edx
 106700e:	48 89 c6             	mov    %rax,%rsi
 1067011:	e8 ea d6 fb ff       	call   1024700 <myl_core_trap>
 1067016:	48 8d 3d f3 e9 01 00 	lea    0x1e9f3(%rip),%rdi        # 1085a10 <core_durable_error.verbs+0x6300>
 106701d:	ba 01 00 00 00       	mov    $0x1,%edx
 1067022:	48 89 c6             	mov    %rax,%rsi
 1067025:	e8 d6 d6 fb ff       	call   1024700 <myl_core_trap>
 106702a:	48 8d 3d 5f ee 01 00 	lea    0x1ee5f(%rip),%rdi        # 1085e90 <core_durable_error.verbs+0x6780>
 1067031:	ba 01 00 00 00       	mov    $0x1,%edx
 1067036:	48 89 c6             	mov    %rax,%rsi
 1067039:	e8 c2 d6 fb ff       	call   1024700 <myl_core_trap>
 106703e:	48 8d 3d 0b e3 01 00 	lea    0x1e30b(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x5c40>
 1067045:	e8 36 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 106704a:	48 8d 3d 2f e3 01 00 	lea    0x1e32f(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x5c70>
 1067051:	e8 2a 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1067056:	48 8d 3d 43 ed 01 00 	lea    0x1ed43(%rip),%rdi        # 1085da0 <core_durable_error.verbs+0x6690>
 106705d:	ba 01 00 00 00       	mov    $0x1,%edx
 1067062:	e8 99 d6 fb ff       	call   1024700 <myl_core_trap>
 1067067:	48 8d 3d b2 e5 01 00 	lea    0x1e5b2(%rip),%rdi        # 1085620 <core_durable_error.verbs+0x5f10>
 106706e:	ba 01 00 00 00       	mov    $0x1,%edx
 1067073:	48 89 c6             	mov    %rax,%rsi
 1067076:	e8 85 d6 fb ff       	call   1024700 <myl_core_trap>
 106707b:	48 8d 3d ce e5 01 00 	lea    0x1e5ce(%rip),%rdi        # 1085650 <core_durable_error.verbs+0x5f40>
 1067082:	ba 01 00 00 00       	mov    $0x1,%edx
 1067087:	e8 74 d6 fb ff       	call   1024700 <myl_core_trap>
 106708c:	48 8d 3d ad e6 01 00 	lea    0x1e6ad(%rip),%rdi        # 1085740 <core_durable_error.verbs+0x6030>
 1067093:	ba 01 00 00 00       	mov    $0x1,%edx
 1067098:	e8 63 d6 fb ff       	call   1024700 <myl_core_trap>
 106709d:	48 8d 3d bc ea 01 00 	lea    0x1eabc(%rip),%rdi        # 1085b60 <core_durable_error.verbs+0x6450>
 10670a4:	ba 01 00 00 00       	mov    $0x1,%edx
 10670a9:	e8 52 d6 fb ff       	call   1024700 <myl_core_trap>
 10670ae:	48 8d 3d db ea 01 00 	lea    0x1eadb(%rip),%rdi        # 1085b90 <core_durable_error.verbs+0x6480>
 10670b5:	ba 01 00 00 00       	mov    $0x1,%edx
 10670ba:	48 89 c6             	mov    %rax,%rsi
 10670bd:	e8 3e d6 fb ff       	call   1024700 <myl_core_trap>
 10670c2:	48 8d 3d 87 e2 01 00 	lea    0x1e287(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x5c40>
 10670c9:	e8 b2 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 10670ce:	48 8d 3d ab e2 01 00 	lea    0x1e2ab(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x5c70>
 10670d5:	e8 a6 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 10670da:	48 8d 3d 0f eb 01 00 	lea    0x1eb0f(%rip),%rdi        # 1085bf0 <core_durable_error.verbs+0x64e0>
 10670e1:	ba 01 00 00 00       	mov    $0x1,%edx
 10670e6:	48 89 ce             	mov    %rcx,%rsi
 10670e9:	e8 12 d6 fb ff       	call   1024700 <myl_core_trap>
 10670ee:	48 8d 3d 5b eb 01 00 	lea    0x1eb5b(%rip),%rdi        # 1085c50 <core_durable_error.verbs+0x6540>
 10670f5:	ba 01 00 00 00       	mov    $0x1,%edx
 10670fa:	48 89 c6             	mov    %rax,%rsi
 10670fd:	e8 fe d5 fb ff       	call   1024700 <myl_core_trap>
 1067102:	48 8d 3d a7 eb 01 00 	lea    0x1eba7(%rip),%rdi        # 1085cb0 <core_durable_error.verbs+0x65a0>
 1067109:	ba 01 00 00 00       	mov    $0x1,%edx
 106710e:	e8 ed d5 fb ff       	call   1024700 <myl_core_trap>
 1067113:	48 8d 3d c6 b5 01 00 	lea    0x1b5c6(%rip),%rdi        # 10826e0 <core_durable_error.verbs+0x2fd0>
 106711a:	e8 61 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 106711f:	48 8d 3d 2a ee 01 00 	lea    0x1ee2a(%rip),%rdi        # 1085f50 <core_durable_error.verbs+0x6840>
 1067126:	ba 01 00 00 00       	mov    $0x1,%edx
 106712b:	e8 d0 d5 fb ff       	call   1024700 <myl_core_trap>
 1067130:	48 8d 3d 69 e3 01 00 	lea    0x1e369(%rip),%rdi        # 10854a0 <core_durable_error.verbs+0x5d90>
 1067137:	ba 01 00 00 00       	mov    $0x1,%edx
 106713c:	48 89 ce             	mov    %rcx,%rsi
 106713f:	e8 bc d5 fb ff       	call   1024700 <myl_core_trap>
 1067144:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 106714b:	00 00 80 
 106714e:	48 8d 3d cb e7 01 00 	lea    0x1e7cb(%rip),%rdi        # 1085920 <core_durable_error.verbs+0x6210>
 1067155:	ba 01 00 00 00       	mov    $0x1,%edx
 106715a:	e8 a1 d5 fb ff       	call   1024700 <myl_core_trap>
 106715f:	48 8d 3d ea e1 01 00 	lea    0x1e1ea(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x5c40>
 1067166:	e8 15 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 106716b:	48 8d 3d 0e e2 01 00 	lea    0x1e20e(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x5c70>
 1067172:	e8 09 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 1067177:	48 8d 3d d2 e7 01 00 	lea    0x1e7d2(%rip),%rdi        # 1085950 <core_durable_error.verbs+0x6240>
 106717e:	ba 01 00 00 00       	mov    $0x1,%edx
 1067183:	48 89 c6             	mov    %rax,%rsi
 1067186:	e8 75 d5 fb ff       	call   1024700 <myl_core_trap>
 106718b:	48 8d 3d 1e ee 01 00 	lea    0x1ee1e(%rip),%rdi        # 1085fb0 <core_durable_error.verbs+0x68a0>
 1067192:	ba 01 00 00 00       	mov    $0x1,%edx
 1067197:	e8 64 d5 fb ff       	call   1024700 <myl_core_trap>
 106719c:	48 8d 3d 5d e3 01 00 	lea    0x1e35d(%rip),%rdi        # 1085500 <core_durable_error.verbs+0x5df0>
 10671a3:	ba 01 00 00 00       	mov    $0x1,%edx
 10671a8:	48 89 c6             	mov    %rax,%rsi
 10671ab:	e8 50 d5 fb ff       	call   1024700 <myl_core_trap>

Disassembly of section .plt:
