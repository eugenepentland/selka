
.mylang-cache/concurrency-p1/tax-rows/base/json_transform:     file format elf64-x86-64


Disassembly of section .text:

0000000001042290 <my.json::read_value>:
 1042290:	55                   	push   %rbp
 1042291:	41 57                	push   %r15
 1042293:	41 56                	push   %r14
 1042295:	41 55                	push   %r13
 1042297:	41 54                	push   %r12
 1042299:	53                   	push   %rbx
 104229a:	48 81 ec 88 01 00 00 	sub    $0x188,%rsp
 10422a1:	49 89 f7             	mov    %rsi,%r15
 10422a4:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 10422a9:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
 10422ae:	48 83 f9 40          	cmp    $0x40,%rcx
 10422b2:	0f 8f 2f 12 00 00    	jg     10434e7 <my.json::read_value+0x1257>
 10422b8:	49 8b 47 08          	mov    0x8(%r15),%rax
 10422bc:	48 39 c2             	cmp    %rax,%rdx
 10422bf:	7d 79                	jge    104233a <my.json::read_value+0xaa>
 10422c1:	48 b9 00 26 00 00 01 	movabs $0x100002600,%rcx
 10422c8:	00 00 00
 10422cb:	4c 89 fe             	mov    %r15,%rsi
 10422ce:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10422d5:	0f 1f 84 00 00 00 00
 10422dc:	00
 10422dd:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10422e4:	0f 1f 84 00 00 00 00
 10422eb:	00
 10422ec:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10422f3:	0f 1f 84 00 00 00 00
 10422fa:	00
 10422fb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1042300:	48 89 d7             	mov    %rdx,%rdi
 1042303:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1042307:	48 21 c7             	and    %rax,%rdi
 104230a:	4c 8d 04 17          	lea    (%rdi,%rdx,1),%r8
 104230e:	49 39 c0             	cmp    %rax,%r8
 1042311:	0f 83 cc 18 00 00    	jae    1043be3 <my.json::read_value+0x1953>
 1042317:	48 01 fe             	add    %rdi,%rsi
 104231a:	0f b6 44 32 20       	movzbl 0x20(%rdx,%rsi,1),%eax
 104231f:	48 83 f8 20          	cmp    $0x20,%rax
 1042323:	77 15                	ja     104233a <my.json::read_value+0xaa>
 1042325:	48 0f a3 c1          	bt     %rax,%rcx
 1042329:	73 0f                	jae    104233a <my.json::read_value+0xaa>
 104232b:	48 ff c2             	inc    %rdx
 104232e:	49 8b 47 08          	mov    0x8(%r15),%rax
 1042332:	4c 89 fe             	mov    %r15,%rsi
 1042335:	48 39 c2             	cmp    %rax,%rdx
 1042338:	7c c6                	jl     1042300 <my.json::read_value+0x70>
 104233a:	4c 89 fd             	mov    %r15,%rbp
 104233d:	49 89 d6             	mov    %rdx,%r14
 1042340:	49 8b 4f 08          	mov    0x8(%r15),%rcx
 1042344:	48 39 ca             	cmp    %rcx,%rdx
 1042347:	0f 8d d7 11 00 00    	jge    1043524 <my.json::read_value+0x1294>
 104234d:	48 89 d0             	mov    %rdx,%rax
 1042350:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042354:	48 21 c8             	and    %rcx,%rax
 1042357:	48 01 d0             	add    %rdx,%rax
 104235a:	48 39 c8             	cmp    %rcx,%rax
 104235d:	0f 83 65 19 00 00    	jae    1043cc8 <my.json::read_value+0x1a38>
 1042363:	0f b6 44 05 20       	movzbl 0x20(%rbp,%rax,1),%eax
 1042368:	0f b6 f0             	movzbl %al,%esi
 104236b:	8d 7e a5             	lea    -0x5b(%rsi),%edi
 104236e:	83 ff 20             	cmp    $0x20,%edi
 1042371:	0f 87 99 03 00 00    	ja     1042710 <my.json::read_value+0x480>
 1042377:	48 8d 35 62 47 fc ff 	lea    -0x3b89e(%rip),%rsi        # 1006ae0 <core_number_pairs+0x110>
 104237e:	48 63 3c be          	movslq (%rsi,%rdi,4),%rdi
 1042382:	48 01 f7             	add    %rsi,%rdi
 1042385:	ff e7                	jmp    *%rdi
 1042387:	4c 8d 72 01          	lea    0x1(%rdx),%r14
 104238b:	48 8d 0d ee 46 03 00 	lea    0x346ee(%rip),%rcx        # 1076a80 <myl_core_free_lists>
 1042392:	48 8b 59 08          	mov    0x8(%rcx),%rbx
 1042396:	48 85 db             	test   %rbx,%rbx
 1042399:	0f 84 18 18 00 00    	je     1043bb7 <my.json::read_value+0x1927>
 104239f:	48 8b 03             	mov    (%rbx),%rax
 10423a2:	48 89 41 08          	mov    %rax,0x8(%rcx)
 10423a6:	48 b8 01 00 00 00 00 	movabs $0x100000000000001,%rax
 10423ad:	00 00 01
 10423b0:	48 89 03             	mov    %rax,(%rbx)
 10423b3:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
 10423b7:	c5 fa 7f 43 08       	vmovdqu %xmm0,0x8(%rbx)
 10423bc:	48 c7 43 18 00 00 00 	movq   $0x0,0x18(%rbx)
 10423c3:	00
 10423c4:	48 8d 05 69 69 fc ff 	lea    -0x39697(%rip),%rax        # 1008d34 <core_number_pairs+0x2364>
 10423cb:	48 89 43 18          	mov    %rax,0x18(%rbx)
 10423cf:	48 8b 45 08          	mov    0x8(%rbp),%rax
 10423d3:	49 39 c6             	cmp    %rax,%r14
 10423d6:	0f 8d 6f 00 00 00    	jge    104244b <my.json::read_value+0x1bb>
 10423dc:	48 bf 00 26 00 00 01 	movabs $0x100002600,%rdi
 10423e3:	00 00 00
 10423e6:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10423ed:	0f 1f 84 00 00 00 00
 10423f4:	00
 10423f5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 10423fc:	00 00 00 00
 1042400:	48 8d 72 01          	lea    0x1(%rdx),%rsi
 1042404:	48 89 f1             	mov    %rsi,%rcx
 1042407:	48 c1 f9 3f          	sar    $0x3f,%rcx
 104240b:	48 21 c1             	and    %rax,%rcx
 104240e:	4c 8d 04 0a          	lea    (%rdx,%rcx,1),%r8
 1042412:	49 ff c0             	inc    %r8
 1042415:	49 39 c0             	cmp    %rax,%r8
 1042418:	0f 83 3b 18 00 00    	jae    1043c59 <my.json::read_value+0x19c9>
 104241e:	48 01 cd             	add    %rcx,%rbp
 1042421:	0f b6 44 2a 21       	movzbl 0x21(%rdx,%rbp,1),%eax
 1042426:	48 83 f8 20          	cmp    $0x20,%rax
 104242a:	77 1f                	ja     104244b <my.json::read_value+0x1bb>
 104242c:	48 0f a3 c7          	bt     %rax,%rdi
 1042430:	73 19                	jae    104244b <my.json::read_value+0x1bb>
 1042432:	48 89 d1             	mov    %rdx,%rcx
 1042435:	48 83 c1 02          	add    $0x2,%rcx
 1042439:	49 8b 47 08          	mov    0x8(%r15),%rax
 104243d:	48 89 f2             	mov    %rsi,%rdx
 1042440:	4c 89 fd             	mov    %r15,%rbp
 1042443:	49 89 ce             	mov    %rcx,%r14
 1042446:	48 39 c1             	cmp    %rax,%rcx
 1042449:	7c b5                	jl     1042400 <my.json::read_value+0x170>
 104244b:	49 8b 47 08          	mov    0x8(%r15),%rax
 104244f:	49 39 c6             	cmp    %rax,%r14
 1042452:	0f 8d 8c 19 00 00    	jge    1043de4 <my.json::read_value+0x1b54>
 1042458:	4c 89 f2             	mov    %r14,%rdx
 104245b:	4c 89 f1             	mov    %r14,%rcx
 104245e:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1042462:	48 21 c1             	and    %rax,%rcx
 1042465:	4c 01 f1             	add    %r14,%rcx
 1042468:	48 39 c1             	cmp    %rax,%rcx
 104246b:	0f 83 d1 18 00 00    	jae    1043d42 <my.json::read_value+0x1ab2>
 1042471:	41 80 7c 0f 20 5d    	cmpb   $0x5d,0x20(%r15,%rcx,1)
 1042477:	0f 84 ed 10 00 00    	je     104356a <my.json::read_value+0x12da>
 104247d:	48 ff 44 24 50       	incq   0x50(%rsp)
 1042482:	4c 8d 74 24 70       	lea    0x70(%rsp),%r14
 1042487:	48 bd 00 26 00 00 01 	movabs $0x100002600,%rbp
 104248e:	00 00 00
 1042491:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042498:	0f 1f 84 00 00 00 00
 104249f:	00
 10424a0:	4c 89 f7             	mov    %r14,%rdi
 10424a3:	4c 89 fe             	mov    %r15,%rsi
 10424a6:	48 8b 4c 24 50       	mov    0x50(%rsp),%rcx
 10424ab:	e8 e0 fd ff ff       	call   1042290 <my.json::read_value>
 10424b0:	4c 8b 6c 24 70       	mov    0x70(%rsp),%r13
 10424b5:	48 8b 44 24 78       	mov    0x78(%rsp),%rax
 10424ba:	41 0f b6 cd          	movzbl %r13b,%ecx
 10424be:	4c 8b bc 24 88 00 00 	mov    0x88(%rsp),%r15
 10424c5:	00
 10424c6:	48 8b 94 24 90 00 00 	mov    0x90(%rsp),%rdx
 10424cd:	00
 10424ce:	83 f9 01             	cmp    $0x1,%ecx
 10424d1:	0f 84 5a 14 00 00    	je     1043931 <my.json::read_value+0x16a1>
 10424d7:	4c 8b a4 24 80 00 00 	mov    0x80(%rsp),%r12
 10424de:	00
 10424df:	3c 06                	cmp    $0x6,%al
 10424e1:	74 0d                	je     10424f0 <my.json::read_value+0x260>
 10424e3:	0f b6 c8             	movzbl %al,%ecx
 10424e6:	83 f9 05             	cmp    $0x5,%ecx
 10424e9:	74 05                	je     10424f0 <my.json::read_value+0x260>
 10424eb:	83 f9 04             	cmp    $0x4,%ecx
 10424ee:	75 0f                	jne    10424ff <my.json::read_value+0x26f>
 10424f0:	41 8b 0c 24          	mov    (%r12),%ecx
 10424f4:	83 f9 ff             	cmp    $0xffffffff,%ecx
 10424f7:	74 06                	je     10424ff <my.json::read_value+0x26f>
 10424f9:	ff c1                	inc    %ecx
 10424fb:	41 89 0c 24          	mov    %ecx,(%r12)
 10424ff:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1042503:	48 3b 4b 10          	cmp    0x10(%rbx),%rcx
 1042507:	0f 83 b6 01 00 00    	jae    10426c3 <my.json::read_value+0x433>
 104250d:	48 89 ce             	mov    %rcx,%rsi
 1042510:	48 c1 e6 04          	shl    $0x4,%rsi
 1042514:	0f b6 f8             	movzbl %al,%edi
 1042517:	48 89 7c 33 20       	mov    %rdi,0x20(%rbx,%rsi,1)
 104251c:	4c 89 64 33 28       	mov    %r12,0x28(%rbx,%rsi,1)
 1042521:	48 ff c1             	inc    %rcx
 1042524:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1042528:	41 80 fd 01          	cmp    $0x1,%r13b
 104252c:	74 42                	je     1042570 <my.json::read_value+0x2e0>
 104252e:	41 0f b6 cd          	movzbl %r13b,%ecx
 1042532:	85 c9                	test   %ecx,%ecx
 1042534:	0f 85 06 01 00 00    	jne    1042640 <my.json::read_value+0x3b0>
 104253a:	3c 06                	cmp    $0x6,%al
 104253c:	74 62                	je     10425a0 <my.json::read_value+0x310>
 104253e:	0f b6 c0             	movzbl %al,%eax
 1042541:	83 f8 05             	cmp    $0x5,%eax
 1042544:	74 40                	je     1042586 <my.json::read_value+0x2f6>
 1042546:	83 f8 04             	cmp    $0x4,%eax
 1042549:	0f 85 f1 00 00 00    	jne    1042640 <my.json::read_value+0x3b0>
 104254f:	41 8b 04 24          	mov    (%r12),%eax
 1042553:	83 f8 ff             	cmp    $0xffffffff,%eax
 1042556:	0f 84 e4 00 00 00    	je     1042640 <my.json::read_value+0x3b0>
 104255c:	ff c8                	dec    %eax
 104255e:	0f 84 82 00 00 00    	je     10425e6 <my.json::read_value+0x356>
 1042564:	41 89 04 24          	mov    %eax,(%r12)
 1042568:	e9 d3 00 00 00       	jmp    1042640 <my.json::read_value+0x3b0>
 104256d:	0f 1f 00             	nopl   (%rax)
 1042570:	8b 08                	mov    (%rax),%ecx
 1042572:	83 f9 ff             	cmp    $0xffffffff,%ecx
 1042575:	0f 84 c5 00 00 00    	je     1042640 <my.json::read_value+0x3b0>
 104257b:	ff c9                	dec    %ecx
 104257d:	74 3b                	je     10425ba <my.json::read_value+0x32a>
 104257f:	89 08                	mov    %ecx,(%rax)
 1042581:	e9 ba 00 00 00       	jmp    1042640 <my.json::read_value+0x3b0>
 1042586:	41 8b 04 24          	mov    (%r12),%eax
 104258a:	83 f8 ff             	cmp    $0xffffffff,%eax
 104258d:	0f 84 ad 00 00 00    	je     1042640 <my.json::read_value+0x3b0>
 1042593:	ff c8                	dec    %eax
 1042595:	74 4f                	je     10425e6 <my.json::read_value+0x356>
 1042597:	41 89 04 24          	mov    %eax,(%r12)
 104259b:	e9 a0 00 00 00       	jmp    1042640 <my.json::read_value+0x3b0>
 10425a0:	41 8b 04 24          	mov    (%r12),%eax
 10425a4:	83 f8 ff             	cmp    $0xffffffff,%eax
 10425a7:	0f 84 93 00 00 00    	je     1042640 <my.json::read_value+0x3b0>
 10425ad:	ff c8                	dec    %eax
 10425af:	74 35                	je     10425e6 <my.json::read_value+0x356>
 10425b1:	41 89 04 24          	mov    %eax,(%r12)
 10425b5:	e9 86 00 00 00       	jmp    1042640 <my.json::read_value+0x3b0>
 10425ba:	0f b6 48 07          	movzbl 0x7(%rax),%ecx
 10425be:	48 85 c9             	test   %rcx,%rcx
 10425c1:	0f 84 2b 01 00 00    	je     10426f2 <my.json::read_value+0x462>
 10425c7:	48 83 78 18 00       	cmpq   $0x0,0x18(%rax)
 10425cc:	0f 85 20 01 00 00    	jne    10426f2 <my.json::read_value+0x462>
 10425d2:	48 8d 3d a7 44 03 00 	lea    0x344a7(%rip),%rdi        # 1076a80 <myl_core_free_lists>
 10425d9:	48 8b 34 cf          	mov    (%rdi,%rcx,8),%rsi
 10425dd:	48 89 30             	mov    %rsi,(%rax)
 10425e0:	48 89 04 cf          	mov    %rax,(%rdi,%rcx,8)
 10425e4:	eb 5a                	jmp    1042640 <my.json::read_value+0x3b0>
 10425e6:	41 0f b6 44 24 07    	movzbl 0x7(%r12),%eax
 10425ec:	48 85 c0             	test   %rax,%rax
 10425ef:	0f 84 02 01 00 00    	je     10426f7 <my.json::read_value+0x467>
 10425f5:	49 83 7c 24 18 00    	cmpq   $0x0,0x18(%r12)
 10425fb:	0f 85 f6 00 00 00    	jne    10426f7 <my.json::read_value+0x467>
 1042601:	48 8d 35 78 44 03 00 	lea    0x34478(%rip),%rsi        # 1076a80 <myl_core_free_lists>
 1042608:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 104260c:	49 89 0c 24          	mov    %rcx,(%r12)
 1042610:	4c 89 24 c6          	mov    %r12,(%rsi,%rax,8)
 1042614:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104261b:	0f 1f 84 00 00 00 00
 1042622:	00
 1042623:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104262a:	0f 1f 84 00 00 00 00
 1042631:	00
 1042632:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042639:	1f 84 00 00 00 00 00
 1042640:	49 8b 47 08          	mov    0x8(%r15),%rax
 1042644:	48 39 c2             	cmp    %rax,%rdx
 1042647:	7d 37                	jge    1042680 <my.json::read_value+0x3f0>
 1042649:	48 89 d1             	mov    %rdx,%rcx
 104264c:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1042650:	48 21 c1             	and    %rax,%rcx
 1042653:	48 8d 34 11          	lea    (%rcx,%rdx,1),%rsi
 1042657:	48 39 c6             	cmp    %rax,%rsi
 104265a:	0f 83 71 15 00 00    	jae    1043bd1 <my.json::read_value+0x1941>
 1042660:	4c 01 f9             	add    %r15,%rcx
 1042663:	0f b6 44 0a 20       	movzbl 0x20(%rdx,%rcx,1),%eax
 1042668:	48 83 f8 20          	cmp    $0x20,%rax
 104266c:	77 12                	ja     1042680 <my.json::read_value+0x3f0>
 104266e:	48 0f a3 c5          	bt     %rax,%rbp
 1042672:	73 0c                	jae    1042680 <my.json::read_value+0x3f0>
 1042674:	48 ff c2             	inc    %rdx
 1042677:	eb c7                	jmp    1042640 <my.json::read_value+0x3b0>
 1042679:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1042680:	49 8b 47 08          	mov    0x8(%r15),%rax
 1042684:	48 39 c2             	cmp    %rax,%rdx
 1042687:	0f 8d 7a 11 00 00    	jge    1043807 <my.json::read_value+0x1577>
 104268d:	48 89 d1             	mov    %rdx,%rcx
 1042690:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1042694:	48 21 c1             	and    %rax,%rcx
 1042697:	48 01 d1             	add    %rdx,%rcx
 104269a:	48 39 c1             	cmp    %rax,%rcx
 104269d:	0f 83 ea 15 00 00    	jae    1043c8d <my.json::read_value+0x19fd>
 10426a3:	41 0f b6 4c 0f 20    	movzbl 0x20(%r15,%rcx,1),%ecx
 10426a9:	83 f9 2c             	cmp    $0x2c,%ecx
 10426ac:	0f 85 af 0e 00 00    	jne    1043561 <my.json::read_value+0x12d1>
 10426b2:	48 ff c2             	inc    %rdx
 10426b5:	48 39 c2             	cmp    %rax,%rdx
 10426b8:	0f 8c e2 fd ff ff    	jl     10424a0 <my.json::read_value+0x210>
 10426be:	e9 c1 12 00 00       	jmp    1043984 <my.json::read_value+0x16f4>
 10426c3:	be 10 00 00 00       	mov    $0x10,%esi
 10426c8:	48 89 df             	mov    %rbx,%rdi
 10426cb:	48 89 d3             	mov    %rdx,%rbx
 10426ce:	4c 89 7c 24 58       	mov    %r15,0x58(%rsp)
 10426d3:	49 89 c7             	mov    %rax,%r15
 10426d6:	e8 e5 13 fd ff       	call   1013ac0 <myl_core_list_grow>
 10426db:	48 89 da             	mov    %rbx,%rdx
 10426de:	48 89 c3             	mov    %rax,%rbx
 10426e1:	4c 89 f8             	mov    %r15,%rax
 10426e4:	4c 8b 7c 24 58       	mov    0x58(%rsp),%r15
 10426e9:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 10426ed:	e9 1b fe ff ff       	jmp    104250d <my.json::read_value+0x27d>
 10426f2:	48 89 c7             	mov    %rax,%rdi
 10426f5:	eb 03                	jmp    10426fa <my.json::read_value+0x46a>
 10426f7:	4c 89 e7             	mov    %r12,%rdi
 10426fa:	4d 89 fc             	mov    %r15,%r12
 10426fd:	49 89 d7             	mov    %rdx,%r15
 1042700:	e8 3b e2 ff ff       	call   1040940 <myl_core_free_block>
 1042705:	4c 89 fa             	mov    %r15,%rdx
 1042708:	4d 89 e7             	mov    %r12,%r15
 104270b:	e9 30 ff ff ff       	jmp    1042640 <my.json::read_value+0x3b0>
 1042710:	83 fe 22             	cmp    $0x22,%esi
 1042713:	0f 84 5a 0d 00 00    	je     1043473 <my.json::read_value+0x11e3>
 1042719:	83 fe 2d             	cmp    $0x2d,%esi
 104271c:	74 0d                	je     104272b <my.json::read_value+0x49b>
 104271e:	8d 70 d0             	lea    -0x30(%rax),%esi
 1042721:	40 80 fe 0a          	cmp    $0xa,%sil
 1042725:	0f 83 7c 0f 00 00    	jae    10436a7 <my.json::read_value+0x1417>
 104272b:	48 8d 72 01          	lea    0x1(%rdx),%rsi
 104272f:	3c 2d                	cmp    $0x2d,%al
 1042731:	48 89 d3             	mov    %rdx,%rbx
 1042734:	48 0f 44 de          	cmove  %rsi,%rbx
 1042738:	4c 0f 44 f6          	cmove  %rsi,%r14
 104273c:	48 39 cb             	cmp    %rcx,%rbx
 104273f:	0f 8d 4e 0e 00 00    	jge    1043593 <my.json::read_value+0x1303>
 1042745:	48 89 d8             	mov    %rbx,%rax
 1042748:	48 c1 f8 3f          	sar    $0x3f,%rax
 104274c:	48 21 c8             	and    %rcx,%rax
 104274f:	48 01 d8             	add    %rbx,%rax
 1042752:	48 39 c8             	cmp    %rcx,%rax
 1042755:	0f 83 c8 15 00 00    	jae    1043d23 <my.json::read_value+0x1a93>
 104275b:	0f b6 44 05 20       	movzbl 0x20(%rbp,%rax,1),%eax
 1042760:	8d 70 d0             	lea    -0x30(%rax),%esi
 1042763:	40 80 fe 0a          	cmp    $0xa,%sil
 1042767:	0f 83 26 0e 00 00    	jae    1043593 <my.json::read_value+0x1303>
 104276d:	3c 30                	cmp    $0x30,%al
 104276f:	0f 85 4b 01 00 00    	jne    10428c0 <my.json::read_value+0x630>
 1042775:	4c 8d 73 01          	lea    0x1(%rbx),%r14
 1042779:	b8 01 00 00 00       	mov    $0x1,%eax
 104277e:	49 39 ce             	cmp    %rcx,%r14
 1042781:	7d 27                	jge    10427aa <my.json::read_value+0x51a>
 1042783:	31 f6                	xor    %esi,%esi
 1042785:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 1042789:	48 0f 4c f1          	cmovl  %rcx,%rsi
 104278d:	4c 01 f6             	add    %r14,%rsi
 1042790:	48 39 ce             	cmp    %rcx,%rsi
 1042793:	0f 83 12 16 00 00    	jae    1043dab <my.json::read_value+0x1b1b>
 1042799:	0f b6 4c 35 20       	movzbl 0x20(%rbp,%rsi,1),%ecx
 104279e:	80 c1 d0             	add    $0xd0,%cl
 10427a1:	80 f9 0a             	cmp    $0xa,%cl
 10427a4:	0f 82 20 11 00 00    	jb     10438ca <my.json::read_value+0x163a>
 10427aa:	31 c9                	xor    %ecx,%ecx
 10427ac:	4c 89 f3             	mov    %r14,%rbx
 10427af:	80 f9 01             	cmp    $0x1,%cl
 10427b2:	0f 84 55 01 00 00    	je     104290d <my.json::read_value+0x67d>
 10427b8:	49 8b 4f 08          	mov    0x8(%r15),%rcx
 10427bc:	48 39 cb             	cmp    %rcx,%rbx
 10427bf:	0f 8d 71 01 00 00    	jge    1042936 <my.json::read_value+0x6a6>
 10427c5:	48 89 d8             	mov    %rbx,%rax
 10427c8:	48 c1 f8 3f          	sar    $0x3f,%rax
 10427cc:	48 21 c8             	and    %rcx,%rax
 10427cf:	48 01 d8             	add    %rbx,%rax
 10427d2:	48 39 c8             	cmp    %rcx,%rax
 10427d5:	0f 83 88 15 00 00    	jae    1043d63 <my.json::read_value+0x1ad3>
 10427db:	41 80 7c 07 20 2e    	cmpb   $0x2e,0x20(%r15,%rax,1)
 10427e1:	0f 85 4f 01 00 00    	jne    1042936 <my.json::read_value+0x6a6>
 10427e7:	4c 8d 73 01          	lea    0x1(%rbx),%r14
 10427eb:	49 39 ce             	cmp    %rcx,%r14
 10427ee:	0f 8d 5c 0f 00 00    	jge    1043750 <my.json::read_value+0x14c0>
 10427f4:	31 c0                	xor    %eax,%eax
 10427f6:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 10427fa:	48 0f 4c c1          	cmovl  %rcx,%rax
 10427fe:	4c 01 f0             	add    %r14,%rax
 1042801:	48 39 c8             	cmp    %rcx,%rax
 1042804:	0f 83 b3 15 00 00    	jae    1043dbd <my.json::read_value+0x1b2d>
 104280a:	41 0f b6 44 07 20    	movzbl 0x20(%r15,%rax,1),%eax
 1042810:	04 d0                	add    $0xd0,%al
 1042812:	3c 09                	cmp    $0x9,%al
 1042814:	0f 87 36 0f 00 00    	ja     1043750 <my.json::read_value+0x14c0>
 104281a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042821:	0f 1f 84 00 00 00 00
 1042828:	00
 1042829:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042830:	0f 1f 84 00 00 00 00
 1042837:	00
 1042838:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 104283f:	00
 1042840:	48 8d 73 01          	lea    0x1(%rbx),%rsi
 1042844:	48 89 f0             	mov    %rsi,%rax
 1042847:	48 c1 f8 3f          	sar    $0x3f,%rax
 104284b:	48 21 c8             	and    %rcx,%rax
 104284e:	48 8d 3c 03          	lea    (%rbx,%rax,1),%rdi
 1042852:	48 ff c7             	inc    %rdi
 1042855:	48 39 cf             	cmp    %rcx,%rdi
 1042858:	0f 83 7c 14 00 00    	jae    1043cda <my.json::read_value+0x1a4a>
 104285e:	4c 89 f9             	mov    %r15,%rcx
 1042861:	48 01 c1             	add    %rax,%rcx
 1042864:	0f b6 4c 0b 21       	movzbl 0x21(%rbx,%rcx,1),%ecx
 1042869:	80 c1 d0             	add    $0xd0,%cl
 104286c:	b8 01 00 00 00       	mov    $0x1,%eax
 1042871:	80 f9 0a             	cmp    $0xa,%cl
 1042874:	73 13                	jae    1042889 <my.json::read_value+0x5f9>
 1042876:	49 89 de             	mov    %rbx,%r14
 1042879:	49 83 c6 02          	add    $0x2,%r14
 104287d:	49 8b 4f 08          	mov    0x8(%r15),%rcx
 1042881:	48 89 f3             	mov    %rsi,%rbx
 1042884:	49 39 ce             	cmp    %rcx,%r14
 1042887:	7c b7                	jl     1042840 <my.json::read_value+0x5b0>
 1042889:	31 c9                	xor    %ecx,%ecx
 104288b:	80 f9 01             	cmp    $0x1,%cl
 104288e:	0f 85 b2 00 00 00    	jne    1042946 <my.json::read_value+0x6b6>
 1042894:	e9 e9 0e 00 00       	jmp    1043782 <my.json::read_value+0x14f2>
 1042899:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10428a0:	0f 1f 84 00 00 00 00
 10428a7:	00
 10428a8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10428af:	0f 1f 84 00 00 00 00
 10428b6:	00
 10428b7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10428be:	00 00
 10428c0:	48 89 d8             	mov    %rbx,%rax
 10428c3:	48 c1 f8 3f          	sar    $0x3f,%rax
 10428c7:	48 21 c8             	and    %rcx,%rax
 10428ca:	48 8d 34 18          	lea    (%rax,%rbx,1),%rsi
 10428ce:	48 39 ce             	cmp    %rcx,%rsi
 10428d1:	0f 83 70 13 00 00    	jae    1043c47 <my.json::read_value+0x19b7>
 10428d7:	48 01 c5             	add    %rax,%rbp
 10428da:	0f b6 4c 2b 20       	movzbl 0x20(%rbx,%rbp,1),%ecx
 10428df:	80 c1 d0             	add    $0xd0,%cl
 10428e2:	b8 01 00 00 00       	mov    $0x1,%eax
 10428e7:	80 f9 0a             	cmp    $0xa,%cl
 10428ea:	0f 83 ba fe ff ff    	jae    10427aa <my.json::read_value+0x51a>
 10428f0:	48 ff c3             	inc    %rbx
 10428f3:	49 8b 4f 08          	mov    0x8(%r15),%rcx
 10428f7:	4c 89 fd             	mov    %r15,%rbp
 10428fa:	49 89 de             	mov    %rbx,%r14
 10428fd:	48 39 cb             	cmp    %rcx,%rbx
 1042900:	7c be                	jl     10428c0 <my.json::read_value+0x630>
 1042902:	31 c9                	xor    %ecx,%ecx
 1042904:	80 f9 01             	cmp    $0x1,%cl
 1042907:	0f 85 ab fe ff ff    	jne    10427b8 <my.json::read_value+0x528>
 104290d:	48 8d 3d 3c ef 00 00 	lea    0xef3c(%rip),%rdi        # 1051850 <core_io_file_error.verbs+0x980>
 1042914:	e8 67 e4 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 1042919:	8b 08                	mov    (%rax),%ecx
 104291b:	83 f9 ff             	cmp    $0xffffffff,%ecx
 104291e:	0f 84 81 0e 00 00    	je     10437a5 <my.json::read_value+0x1515>
 1042924:	83 f9 fe             	cmp    $0xfffffffe,%ecx
 1042927:	ba ff ff ff ff       	mov    $0xffffffff,%edx
 104292c:	0f 45 d1             	cmovne %ecx,%edx
 104292f:	89 10                	mov    %edx,(%rax)
 1042931:	e9 6f 0e 00 00       	jmp    10437a5 <my.json::read_value+0x1515>
 1042936:	31 c9                	xor    %ecx,%ecx
 1042938:	31 c0                	xor    %eax,%eax
 104293a:	49 89 de             	mov    %rbx,%r14
 104293d:	80 f9 01             	cmp    $0x1,%cl
 1042940:	0f 84 3c 0e 00 00    	je     1043782 <my.json::read_value+0x14f2>
 1042946:	49 8b 4f 08          	mov    0x8(%r15),%rcx
 104294a:	49 39 ce             	cmp    %rcx,%r14
 104294d:	0f 8d f7 00 00 00    	jge    1042a4a <my.json::read_value+0x7ba>
 1042953:	4c 89 f6             	mov    %r14,%rsi
 1042956:	48 c1 fe 3f          	sar    $0x3f,%rsi
 104295a:	48 21 ce             	and    %rcx,%rsi
 104295d:	4c 01 f6             	add    %r14,%rsi
 1042960:	48 39 ce             	cmp    %rcx,%rsi
 1042963:	0f 83 0c 14 00 00    	jae    1043d75 <my.json::read_value+0x1ae5>
 1042969:	41 0f b6 74 37 20    	movzbl 0x20(%r15,%rsi,1),%esi
 104296f:	83 ce 20             	or     $0x20,%esi
 1042972:	83 fe 65             	cmp    $0x65,%esi
 1042975:	0f 85 cf 00 00 00    	jne    1042a4a <my.json::read_value+0x7ba>
 104297b:	49 8d 5e 01          	lea    0x1(%r14),%rbx
 104297f:	48 39 cb             	cmp    %rcx,%rbx
 1042982:	7d 2d                	jge    10429b1 <my.json::read_value+0x721>
 1042984:	31 f6                	xor    %esi,%esi
 1042986:	49 83 fe ff          	cmp    $0xffffffffffffffff,%r14
 104298a:	48 0f 4c f1          	cmovl  %rcx,%rsi
 104298e:	48 01 de             	add    %rbx,%rsi
 1042991:	48 39 ce             	cmp    %rcx,%rsi
 1042994:	0f 83 35 14 00 00    	jae    1043dcf <my.json::read_value+0x1b3f>
 104299a:	41 0f b6 4c 37 20    	movzbl 0x20(%r15,%rsi,1),%ecx
 10429a0:	83 f9 2d             	cmp    $0x2d,%ecx
 10429a3:	74 05                	je     10429aa <my.json::read_value+0x71a>
 10429a5:	83 f9 2b             	cmp    $0x2b,%ecx
 10429a8:	75 07                	jne    10429b1 <my.json::read_value+0x721>
 10429aa:	49 83 c6 02          	add    $0x2,%r14
 10429ae:	4c 89 f3             	mov    %r14,%rbx
 10429b1:	4d 8b 47 08          	mov    0x8(%r15),%r8
 10429b5:	4c 39 c3             	cmp    %r8,%rbx
 10429b8:	0f 8d 0d 0d 00 00    	jge    10436cb <my.json::read_value+0x143b>
 10429be:	48 89 d9             	mov    %rbx,%rcx
 10429c1:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10429c5:	4c 21 c1             	and    %r8,%rcx
 10429c8:	48 01 d9             	add    %rbx,%rcx
 10429cb:	4c 39 c1             	cmp    %r8,%rcx
 10429ce:	0f 83 c5 13 00 00    	jae    1043d99 <my.json::read_value+0x1b09>
 10429d4:	41 0f b6 4c 0f 20    	movzbl 0x20(%r15,%rcx,1),%ecx
 10429da:	80 c1 d0             	add    $0xd0,%cl
 10429dd:	80 f9 09             	cmp    $0x9,%cl
 10429e0:	0f 87 e5 0c 00 00    	ja     10436cb <my.json::read_value+0x143b>
 10429e6:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10429ed:	0f 1f 84 00 00 00 00
 10429f4:	00
 10429f5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 10429fc:	00 00 00 00
 1042a00:	48 89 d9             	mov    %rbx,%rcx
 1042a03:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1042a07:	4c 21 c1             	and    %r8,%rcx
 1042a0a:	48 8d 34 19          	lea    (%rcx,%rbx,1),%rsi
 1042a0e:	4c 39 c6             	cmp    %r8,%rsi
 1042a11:	0f 83 9f 12 00 00    	jae    1043cb6 <my.json::read_value+0x1a26>
 1042a17:	4c 89 fe             	mov    %r15,%rsi
 1042a1a:	48 01 ce             	add    %rcx,%rsi
 1042a1d:	0f b6 74 33 20       	movzbl 0x20(%rbx,%rsi,1),%esi
 1042a22:	40 80 c6 d0          	add    $0xd0,%sil
 1042a26:	b9 01 00 00 00       	mov    $0x1,%ecx
 1042a2b:	40 80 fe 0a          	cmp    $0xa,%sil
 1042a2f:	73 0c                	jae    1042a3d <my.json::read_value+0x7ad>
 1042a31:	48 ff c3             	inc    %rbx
 1042a34:	4d 8b 47 08          	mov    0x8(%r15),%r8
 1042a38:	4c 39 c3             	cmp    %r8,%rbx
 1042a3b:	7c c3                	jl     1042a00 <my.json::read_value+0x770>
 1042a3d:	31 f6                	xor    %esi,%esi
 1042a3f:	40 80 fe 01          	cmp    $0x1,%sil
 1042a43:	75 16                	jne    1042a5b <my.json::read_value+0x7cb>
 1042a45:	e9 c4 0c 00 00       	jmp    104370e <my.json::read_value+0x147e>
 1042a4a:	31 f6                	xor    %esi,%esi
 1042a4c:	31 c9                	xor    %ecx,%ecx
 1042a4e:	4c 89 f3             	mov    %r14,%rbx
 1042a51:	40 80 fe 01          	cmp    $0x1,%sil
 1042a55:	0f 84 b3 0c 00 00    	je     104370e <my.json::read_value+0x147e>
 1042a5b:	08 c1                	or     %al,%cl
 1042a5d:	f6 c1 01             	test   $0x1,%cl
 1042a60:	75 27                	jne    1042a89 <my.json::read_value+0x7f9>
 1042a62:	4c 89 ff             	mov    %r15,%rdi
 1042a65:	48 89 d6             	mov    %rdx,%rsi
 1042a68:	49 89 d6             	mov    %rdx,%r14
 1042a6b:	48 89 da             	mov    %rbx,%rdx
 1042a6e:	e8 8d 8a fe ff       	call   102b500 <myl_core_parse_int_range>
 1042a73:	48 89 d1             	mov    %rdx,%rcx
 1042a76:	4c 89 f2             	mov    %r14,%rdx
 1042a79:	3c 01                	cmp    $0x1,%al
 1042a7b:	75 0c                	jne    1042a89 <my.json::read_value+0x7f9>
 1042a7d:	b8 02 00 00 00       	mov    $0x2,%eax
 1042a82:	31 d2                	xor    %edx,%edx
 1042a84:	e9 2d 0d 00 00       	jmp    10437b6 <my.json::read_value+0x1526>
 1042a89:	4c 89 ff             	mov    %r15,%rdi
 1042a8c:	48 89 d6             	mov    %rdx,%rsi
 1042a8f:	48 89 da             	mov    %rbx,%rdx
 1042a92:	e8 79 7c 00 00       	call   104a710 <myl_core_parse_float_range>
 1042a97:	3c 01                	cmp    $0x1,%al
 1042a99:	0f 85 9f 0b 00 00    	jne    104363e <my.json::read_value+0x13ae>
 1042a9f:	c4 e1 f9 7e c1       	vmovq  %xmm0,%rcx
 1042aa4:	b8 03 00 00 00       	mov    $0x3,%eax
 1042aa9:	31 d2                	xor    %edx,%edx
 1042aab:	e9 06 0d 00 00       	jmp    10437b6 <my.json::read_value+0x1526>
 1042ab0:	48 8d 0d 89 57 fc ff 	lea    -0x3a877(%rip),%rcx        # 1008240 <core_number_pairs+0x1870>
 1042ab7:	48 8d bc 24 38 01 00 	lea    0x138(%rsp),%rdi
 1042abe:	00
 1042abf:	4c 89 fe             	mov    %r15,%rsi
 1042ac2:	4c 89 f2             	mov    %r14,%rdx
 1042ac5:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 1042acb:	45 31 c9             	xor    %r9d,%r9d
 1042ace:	e8 4d 21 00 00       	call   1044c20 <my.json::read_literal>
 1042ad3:	0f b6 84 24 38 01 00 	movzbl 0x138(%rsp),%eax
 1042ada:	00
 1042adb:	c5 fa 6f 84 24 40 01 	vmovdqu 0x140(%rsp),%xmm0
 1042ae2:	00 00
 1042ae4:	48 8b 8c 24 50 01 00 	mov    0x150(%rsp),%rcx
 1042aeb:	00
 1042aec:	48 8b 9c 24 58 01 00 	mov    0x158(%rsp),%rbx
 1042af3:	00
 1042af4:	48 83 f8 01          	cmp    $0x1,%rax
 1042af8:	0f 85 b0 00 00 00    	jne    1042bae <my.json::read_value+0x91e>
 1042afe:	48 8d 3d 2b e9 00 00 	lea    0xe92b(%rip),%rdi        # 1051430 <core_io_file_error.verbs+0x560>
 1042b05:	e9 30 0c 00 00       	jmp    104373a <my.json::read_value+0x14aa>
 1042b0a:	48 8d 0d 6f 57 fc ff 	lea    -0x3a891(%rip),%rcx        # 1008280 <core_number_pairs+0x18b0>
 1042b11:	48 8d bc 24 10 01 00 	lea    0x110(%rsp),%rdi
 1042b18:	00
 1042b19:	4c 89 fe             	mov    %r15,%rsi
 1042b1c:	4c 89 f2             	mov    %r14,%rdx
 1042b1f:	45 31 c0             	xor    %r8d,%r8d
 1042b22:	45 31 c9             	xor    %r9d,%r9d
 1042b25:	e8 f6 20 00 00       	call   1044c20 <my.json::read_literal>
 1042b2a:	0f b6 84 24 10 01 00 	movzbl 0x110(%rsp),%eax
 1042b31:	00
 1042b32:	c5 fa 6f 84 24 18 01 	vmovdqu 0x118(%rsp),%xmm0
 1042b39:	00 00
 1042b3b:	48 8b 8c 24 28 01 00 	mov    0x128(%rsp),%rcx
 1042b42:	00
 1042b43:	48 8b 9c 24 30 01 00 	mov    0x130(%rsp),%rbx
 1042b4a:	00
 1042b4b:	48 83 f8 01          	cmp    $0x1,%rax
 1042b4f:	75 5d                	jne    1042bae <my.json::read_value+0x91e>
 1042b51:	48 8d 3d 08 e9 00 00 	lea    0xe908(%rip),%rdi        # 1051460 <core_io_file_error.verbs+0x590>
 1042b58:	e9 dd 0b 00 00       	jmp    104373a <my.json::read_value+0x14aa>
 1042b5d:	48 8d 0d 9c 56 fc ff 	lea    -0x3a964(%rip),%rcx        # 1008200 <core_number_pairs+0x1830>
 1042b64:	48 8d bc 24 60 01 00 	lea    0x160(%rsp),%rdi
 1042b6b:	00
 1042b6c:	41 b9 01 00 00 00    	mov    $0x1,%r9d
 1042b72:	4c 89 fe             	mov    %r15,%rsi
 1042b75:	4c 89 f2             	mov    %r14,%rdx
 1042b78:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 1042b7e:	e8 9d 20 00 00       	call   1044c20 <my.json::read_literal>
 1042b83:	0f b6 84 24 60 01 00 	movzbl 0x160(%rsp),%eax
 1042b8a:	00
 1042b8b:	c5 fa 6f 84 24 68 01 	vmovdqu 0x168(%rsp),%xmm0
 1042b92:	00 00
 1042b94:	48 8b 8c 24 78 01 00 	mov    0x178(%rsp),%rcx
 1042b9b:	00
 1042b9c:	48 8b 9c 24 80 01 00 	mov    0x180(%rsp),%rbx
 1042ba3:	00
 1042ba4:	48 83 f8 01          	cmp    $0x1,%rax
 1042ba8:	0f 84 85 0b 00 00    	je     1043733 <my.json::read_value+0x14a3>
 1042bae:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 1042bb3:	48 89 02             	mov    %rax,(%rdx)
 1042bb6:	c5 fa 7f 42 08       	vmovdqu %xmm0,0x8(%rdx)
 1042bbb:	e9 1e 09 00 00       	jmp    10434de <my.json::read_value+0x124e>
 1042bc0:	48 89 d3             	mov    %rdx,%rbx
 1042bc3:	4c 8d 62 01          	lea    0x1(%rdx),%r12
 1042bc7:	48 8d 35 ba f1 00 00 	lea    0xf1ba(%rip),%rsi        # 1051d88 <core_io_file_error.verbs+0xeb8>
 1042bce:	31 ff                	xor    %edi,%edi
 1042bd0:	e8 2b 7a fd ff       	call   101a600 <myl_core_dict_new>
 1042bd5:	49 89 c5             	mov    %rax,%r13
 1042bd8:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 1042bdc:	49 39 d4             	cmp    %rdx,%r12
 1042bdf:	0f 8d 63 00 00 00    	jge    1042c48 <my.json::read_value+0x9b8>
 1042be5:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 1042bec:	00 00 00
 1042bef:	48 89 d9             	mov    %rbx,%rcx
 1042bf2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042bf9:	1f 84 00 00 00 00 00
 1042c00:	48 8d 71 01          	lea    0x1(%rcx),%rsi
 1042c04:	48 89 f7             	mov    %rsi,%rdi
 1042c07:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1042c0b:	48 21 d7             	and    %rdx,%rdi
 1042c0e:	4c 8d 04 39          	lea    (%rcx,%rdi,1),%r8
 1042c12:	49 ff c0             	inc    %r8
 1042c15:	49 39 d0             	cmp    %rdx,%r8
 1042c18:	0f 83 4a 10 00 00    	jae    1043c68 <my.json::read_value+0x19d8>
 1042c1e:	48 01 fd             	add    %rdi,%rbp
 1042c21:	0f b6 54 29 21       	movzbl 0x21(%rcx,%rbp,1),%edx
 1042c26:	48 83 fa 20          	cmp    $0x20,%rdx
 1042c2a:	77 1c                	ja     1042c48 <my.json::read_value+0x9b8>
 1042c2c:	48 0f a3 d0          	bt     %rdx,%rax
 1042c30:	73 16                	jae    1042c48 <my.json::read_value+0x9b8>
 1042c32:	49 89 cc             	mov    %rcx,%r12
 1042c35:	49 83 c4 02          	add    $0x2,%r12
 1042c39:	49 8b 57 08          	mov    0x8(%r15),%rdx
 1042c3d:	48 89 f1             	mov    %rsi,%rcx
 1042c40:	4c 89 fd             	mov    %r15,%rbp
 1042c43:	49 39 d4             	cmp    %rdx,%r12
 1042c46:	7c b8                	jl     1042c00 <my.json::read_value+0x970>
 1042c48:	49 8b 57 08          	mov    0x8(%r15),%rdx
 1042c4c:	49 39 d4             	cmp    %rdx,%r12
 1042c4f:	0f 8d 0c 0a 00 00    	jge    1043661 <my.json::read_value+0x13d1>
 1042c55:	4c 89 e0             	mov    %r12,%rax
 1042c58:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042c5c:	48 21 d0             	and    %rdx,%rax
 1042c5f:	4c 01 e0             	add    %r12,%rax
 1042c62:	48 39 d0             	cmp    %rdx,%rax
 1042c65:	0f 83 e9 10 00 00    	jae    1043d54 <my.json::read_value+0x1ac4>
 1042c6b:	41 80 7c 07 20 7d    	cmpb   $0x7d,0x20(%r15,%rax,1)
 1042c71:	0f 84 5c 09 00 00    	je     10435d3 <my.json::read_value+0x1343>
 1042c77:	48 ff 44 24 50       	incq   0x50(%rsp)
 1042c7c:	48 bb 00 26 00 00 01 	movabs $0x100002600,%rbx
 1042c83:	00 00 00
 1042c86:	4d 89 fe             	mov    %r15,%r14
 1042c89:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1042c90:	49 39 d4             	cmp    %rdx,%r12
 1042c93:	7d 38                	jge    1042ccd <my.json::read_value+0xa3d>
 1042c95:	4c 89 e0             	mov    %r12,%rax
 1042c98:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042c9c:	48 21 d0             	and    %rdx,%rax
 1042c9f:	4a 8d 0c 20          	lea    (%rax,%r12,1),%rcx
 1042ca3:	48 39 d1             	cmp    %rdx,%rcx
 1042ca6:	0f 83 49 0f 00 00    	jae    1043bf5 <my.json::read_value+0x1965>
 1042cac:	49 01 c7             	add    %rax,%r15
 1042caf:	43 0f b6 44 3c 20    	movzbl 0x20(%r12,%r15,1),%eax
 1042cb5:	48 83 f8 20          	cmp    $0x20,%rax
 1042cb9:	77 12                	ja     1042ccd <my.json::read_value+0xa3d>
 1042cbb:	48 0f a3 c3          	bt     %rax,%rbx
 1042cbf:	73 0c                	jae    1042ccd <my.json::read_value+0xa3d>
 1042cc1:	49 ff c4             	inc    %r12
 1042cc4:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1042cc8:	4d 89 f7             	mov    %r14,%r15
 1042ccb:	eb c3                	jmp    1042c90 <my.json::read_value+0xa00>
 1042ccd:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1042cd1:	49 39 d4             	cmp    %rdx,%r12
 1042cd4:	0f 8d 7e 0b 00 00    	jge    1043858 <my.json::read_value+0x15c8>
 1042cda:	4c 89 e0             	mov    %r12,%rax
 1042cdd:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042ce1:	48 21 d0             	and    %rdx,%rax
 1042ce4:	4c 01 e0             	add    %r12,%rax
 1042ce7:	48 39 d0             	cmp    %rdx,%rax
 1042cea:	0f 83 f9 0f 00 00    	jae    1043ce9 <my.json::read_value+0x1a59>
 1042cf0:	41 80 7c 06 20 22    	cmpb   $0x22,0x20(%r14,%rax,1)
 1042cf6:	0f 85 5c 0b 00 00    	jne    1043858 <my.json::read_value+0x15c8>
 1042cfc:	48 8d bc 24 c0 00 00 	lea    0xc0(%rsp),%rdi
 1042d03:	00
 1042d04:	4c 89 f6             	mov    %r14,%rsi
 1042d07:	4c 89 e2             	mov    %r12,%rdx
 1042d0a:	e8 c1 14 00 00       	call   10441d0 <my.json::read_string>
 1042d0f:	48 8b 9c 24 c8 00 00 	mov    0xc8(%rsp),%rbx
 1042d16:	00
 1042d17:	4c 8b a4 24 d8 00 00 	mov    0xd8(%rsp),%r12
 1042d1e:	00
 1042d1f:	4c 8b b4 24 d0 00 00 	mov    0xd0(%rsp),%r14
 1042d26:	00
 1042d27:	0f b6 84 24 c0 00 00 	movzbl 0xc0(%rsp),%eax
 1042d2e:	00
 1042d2f:	3c 01                	cmp    $0x1,%al
 1042d31:	0f 84 39 0d 00 00    	je     1043a70 <my.json::read_value+0x17e0>
 1042d37:	48 89 5c 24 68       	mov    %rbx,0x68(%rsp)
 1042d3c:	f6 43 05 02          	testb  $0x2,0x5(%rbx)
 1042d40:	88 44 24 0f          	mov    %al,0xf(%rsp)
 1042d44:	75 0a                	jne    1042d50 <my.json::read_value+0xac0>
 1042d46:	48 89 df             	mov    %rbx,%rdi
 1042d49:	e8 72 8e fd ff       	call   101bbc0 <myl_core_str_hash>
 1042d4e:	eb 03                	jmp    1042d53 <my.json::read_value+0xac3>
 1042d50:	8b 43 18             	mov    0x18(%rbx),%eax
 1042d53:	89 c0                	mov    %eax,%eax
 1042d55:	48 b9 15 7c 4a 7f b9 	movabs $0x9e3779b97f4a7c15,%rcx
 1042d5c:	79 37 9e
 1042d5f:	48 0f af c1          	imul   %rcx,%rax
 1042d63:	48 89 c6             	mov    %rax,%rsi
 1042d66:	48 c1 ee 20          	shr    $0x20,%rsi
 1042d6a:	48 31 c6             	xor    %rax,%rsi
 1042d6d:	4c 89 6c 24 20       	mov    %r13,0x20(%rsp)
 1042d72:	49 8b 4d 18          	mov    0x18(%r13),%rcx
 1042d76:	48 8b 41 08          	mov    0x8(%rcx),%rax
 1042d7a:	48 85 c0             	test   %rax,%rax
 1042d7d:	48 89 5c 24 48       	mov    %rbx,0x48(%rsp)
 1042d82:	48 89 74 24 40       	mov    %rsi,0x40(%rsp)
 1042d87:	0f 84 bf 00 00 00    	je     1042e4c <my.json::read_value+0xbbc>
 1042d8d:	8b 08                	mov    (%rax),%ecx
 1042d8f:	f3 0f bc d1          	tzcnt  %ecx,%edx
 1042d93:	f6 da                	neg    %dl
 1042d95:	c4 62 eb f7 ee       	shrx   %rdx,%rsi,%r13
 1042d9a:	c4 a1 7a 6f 4c 28 10 	vmovdqu 0x10(%rax,%r13,1),%xmm1
 1042da1:	89 f2                	mov    %esi,%edx
 1042da3:	80 e2 7f             	and    $0x7f,%dl
 1042da6:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 1042daa:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1042daf:	c5 f9 7f 4c 24 30    	vmovdqa %xmm1,0x30(%rsp)
 1042db5:	c5 f1 74 c0          	vpcmpeqb %xmm0,%xmm1,%xmm0
 1042db9:	c5 f9 d7 d0          	vpmovmskb %xmm0,%edx
 1042dbd:	85 d2                	test   %edx,%edx
 1042dbf:	74 73                	je     1042e34 <my.json::read_value+0xba4>
 1042dc1:	8d 69 ff             	lea    -0x1(%rcx),%ebp
 1042dc4:	83 c1 1e             	add    $0x1e,%ecx
 1042dc7:	83 e1 f0             	and    $0xfffffff0,%ecx
 1042dca:	48 8d 1c 08          	lea    (%rax,%rcx,1),%rbx
 1042dce:	48 83 c3 10          	add    $0x10,%rbx
 1042dd2:	44 0f b7 fa          	movzwl %dx,%r15d
 1042dd6:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042ddd:	0f 1f 84 00 00 00 00
 1042de4:	00
 1042de5:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042dec:	0f 1f 84 00 00 00 00
 1042df3:	00
 1042df4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042dfb:	00 00 00 00 00
 1042e00:	f3 41 0f bc c7       	tzcnt  %r15d,%eax
 1042e05:	44 01 e8             	add    %r13d,%eax
 1042e08:	21 e8                	and    %ebp,%eax
 1042e0a:	8b 04 83             	mov    (%rbx,%rax,4),%eax
 1042e0d:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 1042e11:	48 8b 4c 24 20       	mov    0x20(%rsp),%rcx
 1042e16:	48 8b 7c c1 20       	mov    0x20(%rcx,%rax,8),%rdi
 1042e1b:	48 8b 74 24 68       	mov    0x68(%rsp),%rsi
 1042e20:	e8 1b 8f fd ff       	call   101bd40 <myl_core_str_eq>
 1042e25:	84 c0                	test   %al,%al
 1042e27:	0f 85 ba 07 00 00    	jne    10435e7 <my.json::read_value+0x1357>
 1042e2d:	c4 c2 00 f3 cf       	blsr   %r15d,%r15d
 1042e32:	75 cc                	jne    1042e00 <my.json::read_value+0xb70>
 1042e34:	c5 f9 6f 44 24 30    	vmovdqa 0x30(%rsp),%xmm0
 1042e3a:	c5 f9 74 05 9e 0f fc 	vpcmpeqb -0x3f062(%rip),%xmm0,%xmm0        # 1003de0 <__anon_2214+0x50>
 1042e41:	ff
 1042e42:	c5 f9 d7 c0          	vpmovmskb %xmm0,%eax
 1042e46:	85 c0                	test   %eax,%eax
 1042e48:	75 2d                	jne    1042e77 <my.json::read_value+0xbe7>
 1042e4a:	eb 0b                	jmp    1042e57 <my.json::read_value+0xbc7>
 1042e4c:	48 83 79 18 00       	cmpq   $0x0,0x18(%rcx)
 1042e51:	0f 84 73 01 00 00    	je     1042fca <my.json::read_value+0xd3a>
 1042e57:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 1042e5c:	48 8d 74 24 68       	lea    0x68(%rsp),%rsi
 1042e61:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 1042e66:	e8 d5 73 fd ff       	call   101a240 <myl_core_dict_find>
 1042e6b:	49 89 c5             	mov    %rax,%r13
 1042e6e:	4d 85 ed             	test   %r13,%r13
 1042e71:	0f 89 70 07 00 00    	jns    10435e7 <my.json::read_value+0x1357>
 1042e77:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1042e7b:	49 39 d4             	cmp    %rdx,%r12
 1042e7e:	0f 8d 76 00 00 00    	jge    1042efa <my.json::read_value+0xc6a>
 1042e84:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 1042e89:	48 bb 00 26 00 00 01 	movabs $0x100002600,%rbx
 1042e90:	00 00 00
 1042e93:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042e9a:	0f 1f 84 00 00 00 00
 1042ea1:	00
 1042ea2:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042ea9:	0f 1f 84 00 00 00 00
 1042eb0:	00
 1042eb1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042eb8:	0f 1f 84 00 00 00 00
 1042ebf:	00
 1042ec0:	4c 89 e0             	mov    %r12,%rax
 1042ec3:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042ec7:	48 21 d0             	and    %rdx,%rax
 1042eca:	4a 8d 0c 20          	lea    (%rax,%r12,1),%rcx
 1042ece:	48 39 d1             	cmp    %rdx,%rcx
 1042ed1:	0f 83 2d 0d 00 00    	jae    1043c04 <my.json::read_value+0x1974>
 1042ed7:	4c 01 f0             	add    %r14,%rax
 1042eda:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 1042ee0:	48 83 f8 20          	cmp    $0x20,%rax
 1042ee4:	77 23                	ja     1042f09 <my.json::read_value+0xc79>
 1042ee6:	48 0f a3 c3          	bt     %rax,%rbx
 1042eea:	73 1d                	jae    1042f09 <my.json::read_value+0xc79>
 1042eec:	49 ff c4             	inc    %r12
 1042eef:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1042ef3:	49 39 d4             	cmp    %rdx,%r12
 1042ef6:	7c c8                	jl     1042ec0 <my.json::read_value+0xc30>
 1042ef8:	eb 0f                	jmp    1042f09 <my.json::read_value+0xc79>
 1042efa:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 1042eff:	48 bb 00 26 00 00 01 	movabs $0x100002600,%rbx
 1042f06:	00 00 00
 1042f09:	4c 8b 7c 24 48       	mov    0x48(%rsp),%r15
 1042f0e:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1042f12:	49 39 d4             	cmp    %rdx,%r12
 1042f15:	0f 8d 60 09 00 00    	jge    104387b <my.json::read_value+0x15eb>
 1042f1b:	4c 89 e0             	mov    %r12,%rax
 1042f1e:	48 c1 f8 3f          	sar    $0x3f,%rax
 1042f22:	48 21 d0             	and    %rdx,%rax
 1042f25:	4c 01 e0             	add    %r12,%rax
 1042f28:	48 39 d0             	cmp    %rdx,%rax
 1042f2b:	0f 83 c7 0d 00 00    	jae    1043cf8 <my.json::read_value+0x1a68>
 1042f31:	41 80 7c 06 20 3a    	cmpb   $0x3a,0x20(%r14,%rax,1)
 1042f37:	0f 85 3e 09 00 00    	jne    104387b <my.json::read_value+0x15eb>
 1042f3d:	49 ff c4             	inc    %r12
 1042f40:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 1042f45:	4c 89 f6             	mov    %r14,%rsi
 1042f48:	4c 89 e2             	mov    %r12,%rdx
 1042f4b:	48 8b 4c 24 50       	mov    0x50(%rsp),%rcx
 1042f50:	e8 3b f3 ff ff       	call   1042290 <my.json::read_value>
 1042f55:	48 8b 6c 24 70       	mov    0x70(%rsp),%rbp
 1042f5a:	48 8b 44 24 78       	mov    0x78(%rsp),%rax
 1042f5f:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 1042f64:	40 0f b6 c5          	movzbl %bpl,%eax
 1042f68:	4c 8b b4 24 88 00 00 	mov    0x88(%rsp),%r14
 1042f6f:	00
 1042f70:	4c 8b a4 24 90 00 00 	mov    0x90(%rsp),%r12
 1042f77:	00
 1042f78:	83 f8 01             	cmp    $0x1,%eax
 1042f7b:	0f 84 1e 0b 00 00    	je     1043a9f <my.json::read_value+0x180f>
 1042f81:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 1042f88:	00
 1042f89:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 1042f8e:	41 83 7d 00 01       	cmpl   $0x1,0x0(%r13)
 1042f93:	75 0a                	jne    1042f9f <my.json::read_value+0xd0f>
 1042f95:	4c 89 6c 24 20       	mov    %r13,0x20(%rsp)
 1042f9a:	e9 bf 00 00 00       	jmp    104305e <my.json::read_value+0xdce>
 1042f9f:	4c 89 ef             	mov    %r13,%rdi
 1042fa2:	e8 19 83 fd ff       	call   101b2c0 <myl_core_dict_copy>
 1042fa7:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 1042fac:	41 8b 45 00          	mov    0x0(%r13),%eax
 1042fb0:	83 f8 ff             	cmp    $0xffffffff,%eax
 1042fb3:	0f 84 a5 00 00 00    	je     104305e <my.json::read_value+0xdce>
 1042fb9:	ff c8                	dec    %eax
 1042fbb:	0f 84 71 00 00 00    	je     1043032 <my.json::read_value+0xda2>
 1042fc1:	41 89 45 00          	mov    %eax,0x0(%r13)
 1042fc5:	e9 94 00 00 00       	jmp    104305e <my.json::read_value+0xdce>
 1042fca:	4c 8b 79 20          	mov    0x20(%rcx),%r15
 1042fce:	4d 85 ff             	test   %r15,%r15
 1042fd1:	0f 84 a0 fe ff ff    	je     1042e77 <my.json::read_value+0xbe7>
 1042fd7:	48 8b 59 10          	mov    0x10(%rcx),%rbx
 1042fdb:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 1042fe0:	48 8d 68 20          	lea    0x20(%rax),%rbp
 1042fe4:	45 31 ed             	xor    %r13d,%r13d
 1042fe7:	eb 27                	jmp    1043010 <my.json::read_value+0xd80>
 1042fe9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1042ff0:	0f 1f 84 00 00 00 00
 1042ff7:	00
 1042ff8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1042fff:	00
 1043000:	49 ff c5             	inc    %r13
 1043003:	48 83 c5 18          	add    $0x18,%rbp
 1043007:	4d 39 ef             	cmp    %r13,%r15
 104300a:	0f 84 67 fe ff ff    	je     1042e77 <my.json::read_value+0xbe7>
 1043010:	48 8b 44 24 40       	mov    0x40(%rsp),%rax
 1043015:	4a 39 04 eb          	cmp    %rax,(%rbx,%r13,8)
 1043019:	75 e5                	jne    1043000 <my.json::read_value+0xd70>
 104301b:	48 8b 7d 00          	mov    0x0(%rbp),%rdi
 104301f:	48 8b 74 24 68       	mov    0x68(%rsp),%rsi
 1043024:	e8 17 8d fd ff       	call   101bd40 <myl_core_str_eq>
 1043029:	84 c0                	test   %al,%al
 104302b:	74 d3                	je     1043000 <my.json::read_value+0xd70>
 104302d:	e9 3c fe ff ff       	jmp    1042e6e <my.json::read_value+0xbde>
 1043032:	41 0f b6 45 07       	movzbl 0x7(%r13),%eax
 1043037:	48 85 c0             	test   %rax,%rax
 104303a:	0f 84 19 04 00 00    	je     1043459 <my.json::read_value+0x11c9>
 1043040:	49 83 7d 18 00       	cmpq   $0x0,0x18(%r13)
 1043045:	0f 85 0e 04 00 00    	jne    1043459 <my.json::read_value+0x11c9>
 104304b:	48 8d 15 2e 3a 03 00 	lea    0x33a2e(%rip),%rdx        # 1076a80 <myl_core_free_lists>
 1043052:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043056:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 104305a:	4c 89 2c c2          	mov    %r13,(%rdx,%rax,8)
 104305e:	4c 89 7c 24 60       	mov    %r15,0x60(%rsp)
 1043063:	41 f6 47 05 02       	testb  $0x2,0x5(%r15)
 1043068:	75 0a                	jne    1043074 <my.json::read_value+0xde4>
 104306a:	4c 89 ff             	mov    %r15,%rdi
 104306d:	e8 4e 8b fd ff       	call   101bbc0 <myl_core_str_hash>
 1043072:	eb 04                	jmp    1043078 <my.json::read_value+0xde8>
 1043074:	41 8b 47 18          	mov    0x18(%r15),%eax
 1043078:	48 89 ac 24 a0 00 00 	mov    %rbp,0xa0(%rsp)
 104307f:	00
 1043080:	4c 89 74 24 58       	mov    %r14,0x58(%rsp)
 1043085:	89 c0                	mov    %eax,%eax
 1043087:	48 b9 15 7c 4a 7f b9 	movabs $0x9e3779b97f4a7c15,%rcx
 104308e:	79 37 9e
 1043091:	48 0f af c1          	imul   %rcx,%rax
 1043095:	49 89 c5             	mov    %rax,%r13
 1043098:	49 c1 ed 20          	shr    $0x20,%r13
 104309c:	49 31 c5             	xor    %rax,%r13
 104309f:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 10430a4:	48 8b 48 18          	mov    0x18(%rax),%rcx
 10430a8:	48 8b 41 08          	mov    0x8(%rcx),%rax
 10430ac:	48 85 c0             	test   %rax,%rax
 10430af:	0f 84 f0 00 00 00    	je     10431a5 <my.json::read_value+0xf15>
 10430b5:	8b 08                	mov    (%rax),%ecx
 10430b7:	f3 0f bc f1          	tzcnt  %ecx,%esi
 10430bb:	40 f6 de             	neg    %sil
 10430be:	c4 c2 cb f7 ed       	shrx   %rsi,%r13,%rbp
 10430c3:	8d 71 ff             	lea    -0x1(%rcx),%esi
 10430c6:	89 74 24 40          	mov    %esi,0x40(%rsp)
 10430ca:	c5 fa 6f 4c 28 10    	vmovdqu 0x10(%rax,%rbp,1),%xmm1
 10430d0:	4c 89 ac 24 98 00 00 	mov    %r13,0x98(%rsp)
 10430d7:	00
 10430d8:	44 89 ea             	mov    %r13d,%edx
 10430db:	80 e2 7f             	and    $0x7f,%dl
 10430de:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 10430e2:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10430e7:	c5 f9 7f 8c 24 00 01 	vmovdqa %xmm1,0x100(%rsp)
 10430ee:	00 00
 10430f0:	c5 f1 74 c0          	vpcmpeqb %xmm0,%xmm1,%xmm0
 10430f4:	c5 f9 d7 d0          	vpmovmskb %xmm0,%edx
 10430f8:	85 d2                	test   %edx,%edx
 10430fa:	74 76                	je     1043172 <my.json::read_value+0xee2>
 10430fc:	83 c1 1e             	add    $0x1e,%ecx
 10430ff:	83 e1 f0             	and    $0xfffffff0,%ecx
 1043102:	4c 8d 34 08          	lea    (%rax,%rcx,1),%r14
 1043106:	49 83 c6 10          	add    $0x10,%r14
 104310a:	44 0f b7 ea          	movzwl %dx,%r13d
 104310e:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043115:	0f 1f 84 00 00 00 00
 104311c:	00
 104311d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043124:	0f 1f 84 00 00 00 00
 104312b:	00
 104312c:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1043133:	0f 1f 84 00 00 00 00
 104313a:	00
 104313b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1043140:	f3 41 0f bc c5       	tzcnt  %r13d,%eax
 1043145:	01 e8                	add    %ebp,%eax
 1043147:	23 44 24 40          	and    0x40(%rsp),%eax
 104314b:	45 8b 3c 86          	mov    (%r14,%rax,4),%r15d
 104314f:	4b 8d 04 7f          	lea    (%r15,%r15,2),%rax
 1043153:	48 8b 4c 24 20       	mov    0x20(%rsp),%rcx
 1043158:	48 8b 7c c1 20       	mov    0x20(%rcx,%rax,8),%rdi
 104315d:	48 8b 74 24 60       	mov    0x60(%rsp),%rsi
 1043162:	e8 d9 8b fd ff       	call   101bd40 <myl_core_str_eq>
 1043167:	84 c0                	test   %al,%al
 1043169:	75 5a                	jne    10431c5 <my.json::read_value+0xf35>
 104316b:	c4 c2 10 f3 cd       	blsr   %r13d,%r13d
 1043170:	75 ce                	jne    1043140 <my.json::read_value+0xeb0>
 1043172:	c5 f9 6f 84 24 00 01 	vmovdqa 0x100(%rsp),%xmm0
 1043179:	00 00
 104317b:	c5 f9 74 05 5d 0c fc 	vpcmpeqb -0x3f3a3(%rip),%xmm0,%xmm0        # 1003de0 <__anon_2214+0x50>
 1043182:	ff
 1043183:	c5 f9 d7 c0          	vpmovmskb %xmm0,%eax
 1043187:	85 c0                	test   %eax,%eax
 1043189:	4c 8b ac 24 98 00 00 	mov    0x98(%rsp),%r13
 1043190:	00
 1043191:	74 1d                	je     10431b0 <my.json::read_value+0xf20>
 1043193:	f3 44 0f bc f8       	tzcnt  %eax,%r15d
 1043198:	41 01 ef             	add    %ebp,%r15d
 104319b:	44 23 7c 24 40       	and    0x40(%rsp),%r15d
 10431a0:	49 f7 d7             	not    %r15
 10431a3:	eb 20                	jmp    10431c5 <my.json::read_value+0xf35>
 10431a5:	48 83 79 18 00       	cmpq   $0x0,0x18(%rcx)
 10431aa:	0f 84 22 01 00 00    	je     10432d2 <my.json::read_value+0x1042>
 10431b0:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 10431b5:	48 8d 74 24 60       	lea    0x60(%rsp),%rsi
 10431ba:	4c 89 ea             	mov    %r13,%rdx
 10431bd:	e8 7e 70 fd ff       	call   101a240 <myl_core_dict_find>
 10431c2:	49 89 c7             	mov    %rax,%r15
 10431c5:	48 8b 6c 24 48       	mov    0x48(%rsp),%rbp
 10431ca:	8b 45 00             	mov    0x0(%rbp),%eax
 10431cd:	83 f8 ff             	cmp    $0xffffffff,%eax
 10431d0:	74 05                	je     10431d7 <my.json::read_value+0xf47>
 10431d2:	ff c0                	inc    %eax
 10431d4:	89 45 00             	mov    %eax,0x0(%rbp)
 10431d7:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 10431dc:	44 0f b6 f1          	movzbl %cl,%r14d
 10431e0:	41 80 fe 06          	cmp    $0x6,%r14b
 10431e4:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 10431e9:	74 0c                	je     10431f7 <my.json::read_value+0xf67>
 10431eb:	41 83 fe 05          	cmp    $0x5,%r14d
 10431ef:	74 06                	je     10431f7 <my.json::read_value+0xf67>
 10431f1:	41 83 fe 04          	cmp    $0x4,%r14d
 10431f5:	75 0b                	jne    1043202 <my.json::read_value+0xf72>
 10431f7:	8b 02                	mov    (%rdx),%eax
 10431f9:	83 f8 ff             	cmp    $0xffffffff,%eax
 10431fc:	74 04                	je     1043202 <my.json::read_value+0xf72>
 10431fe:	ff c0                	inc    %eax
 1043200:	89 02                	mov    %eax,(%rdx)
 1043202:	48 89 ac 24 a8 00 00 	mov    %rbp,0xa8(%rsp)
 1043209:	00
 104320a:	0f b6 c1             	movzbl %cl,%eax
 104320d:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
 1043214:	00
 1043215:	48 89 94 24 b8 00 00 	mov    %rdx,0xb8(%rsp)
 104321c:	00
 104321d:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 1043222:	4c 89 fe             	mov    %r15,%rsi
 1043225:	48 8d 94 24 a8 00 00 	lea    0xa8(%rsp),%rdx
 104322c:	00
 104322d:	48 8d 8c 24 b0 00 00 	lea    0xb0(%rsp),%rcx
 1043234:	00
 1043235:	45 31 c0             	xor    %r8d,%r8d
 1043238:	e8 03 76 fd ff       	call   101a840 <myl_core_dict_insert>
 104323d:	49 89 c5             	mov    %rax,%r13
 1043240:	80 7c 24 0f 00       	cmpb   $0x0,0xf(%rsp)
 1043245:	4c 8b 7c 24 58       	mov    0x58(%rsp),%r15
 104324a:	74 4d                	je     1043299 <my.json::read_value+0x1009>
 104324c:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
 1043253:	00
 1043254:	3c 01                	cmp    $0x1,%al
 1043256:	74 56                	je     10432ae <my.json::read_value+0x101e>
 1043258:	0f b6 c0             	movzbl %al,%eax
 104325b:	85 c0                	test   %eax,%eax
 104325d:	0f 85 5d 01 00 00    	jne    10433c0 <my.json::read_value+0x1130>
 1043263:	80 7c 24 30 06       	cmpb   $0x6,0x30(%rsp)
 1043268:	74 10                	je     104327a <my.json::read_value+0xfea>
 104326a:	41 83 fe 05          	cmp    $0x5,%r14d
 104326e:	74 0a                	je     104327a <my.json::read_value+0xfea>
 1043270:	41 83 fe 04          	cmp    $0x4,%r14d
 1043274:	0f 85 46 01 00 00    	jne    10433c0 <my.json::read_value+0x1130>
 104327a:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 104327f:	8b 00                	mov    (%rax),%eax
 1043281:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043284:	0f 84 36 01 00 00    	je     10433c0 <my.json::read_value+0x1130>
 104328a:	ff c8                	dec    %eax
 104328c:	0f 84 e4 00 00 00    	je     1043376 <my.json::read_value+0x10e6>
 1043292:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 1043297:	eb 32                	jmp    10432cb <my.json::read_value+0x103b>
 1043299:	8b 45 00             	mov    0x0(%rbp),%eax
 104329c:	83 f8 ff             	cmp    $0xffffffff,%eax
 104329f:	74 ab                	je     104324c <my.json::read_value+0xfbc>
 10432a1:	ff c8                	dec    %eax
 10432a3:	0f 84 96 00 00 00    	je     104333f <my.json::read_value+0x10af>
 10432a9:	89 45 00             	mov    %eax,0x0(%rbp)
 10432ac:	eb 9e                	jmp    104324c <my.json::read_value+0xfbc>
 10432ae:	48 8b 44 24 30       	mov    0x30(%rsp),%rax
 10432b3:	8b 00                	mov    (%rax),%eax
 10432b5:	83 f8 ff             	cmp    $0xffffffff,%eax
 10432b8:	0f 84 02 01 00 00    	je     10433c0 <my.json::read_value+0x1130>
 10432be:	ff c8                	dec    %eax
 10432c0:	0f 84 a9 00 00 00    	je     104336f <my.json::read_value+0x10df>
 10432c6:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 10432cb:	89 01                	mov    %eax,(%rcx)
 10432cd:	e9 ee 00 00 00       	jmp    10433c0 <my.json::read_value+0x1130>
 10432d2:	48 8b 71 20          	mov    0x20(%rcx),%rsi
 10432d6:	49 c7 c7 ff ff ff ff 	mov    $0xffffffffffffffff,%r15
 10432dd:	48 85 f6             	test   %rsi,%rsi
 10432e0:	0f 84 df fe ff ff    	je     10431c5 <my.json::read_value+0xf35>
 10432e6:	4c 8b 71 10          	mov    0x10(%rcx),%r14
 10432ea:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 10432ef:	48 8d 68 20          	lea    0x20(%rax),%rbp
 10432f3:	31 db                	xor    %ebx,%ebx
 10432f5:	48 89 74 24 40       	mov    %rsi,0x40(%rsp)
 10432fa:	eb 14                	jmp    1043310 <my.json::read_value+0x1080>
 10432fc:	0f 1f 40 00          	nopl   0x0(%rax)
 1043300:	48 ff c3             	inc    %rbx
 1043303:	48 83 c5 18          	add    $0x18,%rbp
 1043307:	48 39 de             	cmp    %rbx,%rsi
 104330a:	0f 84 30 01 00 00    	je     1043440 <my.json::read_value+0x11b0>
 1043310:	4d 39 2c de          	cmp    %r13,(%r14,%rbx,8)
 1043314:	75 ea                	jne    1043300 <my.json::read_value+0x1070>
 1043316:	48 8b 7d 00          	mov    0x0(%rbp),%rdi
 104331a:	48 8b 74 24 60       	mov    0x60(%rsp),%rsi
 104331f:	e8 1c 8a fd ff       	call   101bd40 <myl_core_str_eq>
 1043324:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 1043329:	84 c0                	test   %al,%al
 104332b:	74 d3                	je     1043300 <my.json::read_value+0x1070>
 104332d:	49 89 df             	mov    %rbx,%r15
 1043330:	48 bb 00 26 00 00 01 	movabs $0x100002600,%rbx
 1043337:	00 00 00
 104333a:	e9 86 fe ff ff       	jmp    10431c5 <my.json::read_value+0xf35>
 104333f:	0f b6 45 07          	movzbl 0x7(%rbp),%eax
 1043343:	48 85 c0             	test   %rax,%rax
 1043346:	0f 84 1a 01 00 00    	je     1043466 <my.json::read_value+0x11d6>
 104334c:	48 83 7d 18 00       	cmpq   $0x0,0x18(%rbp)
 1043351:	0f 85 0f 01 00 00    	jne    1043466 <my.json::read_value+0x11d6>
 1043357:	48 8d 15 22 37 03 00 	lea    0x33722(%rip),%rdx        # 1076a80 <myl_core_free_lists>
 104335e:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043362:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 1043366:	48 89 2c c2          	mov    %rbp,(%rdx,%rax,8)
 104336a:	e9 dd fe ff ff       	jmp    104324c <my.json::read_value+0xfbc>
 104336f:	48 8b 7c 24 30       	mov    0x30(%rsp),%rdi
 1043374:	eb 05                	jmp    104337b <my.json::read_value+0x10eb>
 1043376:	48 8b 7c 24 18       	mov    0x18(%rsp),%rdi
 104337b:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 104337f:	48 85 c0             	test   %rax,%rax
 1043382:	0f 84 c7 00 00 00    	je     104344f <my.json::read_value+0x11bf>
 1043388:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 104338d:	0f 85 bc 00 00 00    	jne    104344f <my.json::read_value+0x11bf>
 1043393:	48 8d 15 e6 36 03 00 	lea    0x336e6(%rip),%rdx        # 1076a80 <myl_core_free_lists>
 104339a:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 104339e:	48 89 0f             	mov    %rcx,(%rdi)
 10433a1:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 10433a5:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10433ac:	0f 1f 84 00 00 00 00
 10433b3:	00
 10433b4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10433bb:	00 00 00 00 00
 10433c0:	49 8b 57 08          	mov    0x8(%r15),%rdx
 10433c4:	49 39 d4             	cmp    %rdx,%r12
 10433c7:	7d 31                	jge    10433fa <my.json::read_value+0x116a>
 10433c9:	4c 89 e0             	mov    %r12,%rax
 10433cc:	48 c1 f8 3f          	sar    $0x3f,%rax
 10433d0:	48 21 d0             	and    %rdx,%rax
 10433d3:	4a 8d 0c 20          	lea    (%rax,%r12,1),%rcx
 10433d7:	48 39 d1             	cmp    %rdx,%rcx
 10433da:	0f 83 33 08 00 00    	jae    1043c13 <my.json::read_value+0x1983>
 10433e0:	4c 01 f8             	add    %r15,%rax
 10433e3:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 10433e9:	48 83 f8 20          	cmp    $0x20,%rax
 10433ed:	77 0b                	ja     10433fa <my.json::read_value+0x116a>
 10433ef:	48 0f a3 c3          	bt     %rax,%rbx
 10433f3:	73 05                	jae    10433fa <my.json::read_value+0x116a>
 10433f5:	49 ff c4             	inc    %r12
 10433f8:	eb c6                	jmp    10433c0 <my.json::read_value+0x1130>
 10433fa:	49 8b 57 08          	mov    0x8(%r15),%rdx
 10433fe:	49 39 d4             	cmp    %rdx,%r12
 1043401:	0f 8d e4 04 00 00    	jge    10438eb <my.json::read_value+0x165b>
 1043407:	4c 89 e0             	mov    %r12,%rax
 104340a:	48 c1 f8 3f          	sar    $0x3f,%rax
 104340e:	48 21 d0             	and    %rdx,%rax
 1043411:	4c 01 e0             	add    %r12,%rax
 1043414:	48 39 d0             	cmp    %rdx,%rax
 1043417:	0f 83 ea 08 00 00    	jae    1043d07 <my.json::read_value+0x1a77>
 104341d:	41 0f b6 44 07 20    	movzbl 0x20(%r15,%rax,1),%eax
 1043423:	83 f8 2c             	cmp    $0x2c,%eax
 1043426:	0f 85 9e 01 00 00    	jne    10435ca <my.json::read_value+0x133a>
 104342c:	49 ff c4             	inc    %r12
 104342f:	4d 89 fe             	mov    %r15,%r14
 1043432:	49 39 d4             	cmp    %rdx,%r12
 1043435:	0f 8c 55 f8 ff ff    	jl     1042c90 <my.json::read_value+0xa00>
 104343b:	e9 21 02 00 00       	jmp    1043661 <my.json::read_value+0x13d1>
 1043440:	48 bb 00 26 00 00 01 	movabs $0x100002600,%rbx
 1043447:	00 00 00
 104344a:	e9 76 fd ff ff       	jmp    10431c5 <my.json::read_value+0xf35>
 104344f:	e8 ec d4 ff ff       	call   1040940 <myl_core_free_block>
 1043454:	e9 67 ff ff ff       	jmp    10433c0 <my.json::read_value+0x1130>
 1043459:	4c 89 ef             	mov    %r13,%rdi
 104345c:	e8 df d4 ff ff       	call   1040940 <myl_core_free_block>
 1043461:	e9 f8 fb ff ff       	jmp    104305e <my.json::read_value+0xdce>
 1043466:	48 89 ef             	mov    %rbp,%rdi
 1043469:	e8 d2 d4 ff ff       	call   1040940 <myl_core_free_block>
 104346e:	e9 d9 fd ff ff       	jmp    104324c <my.json::read_value+0xfbc>
 1043473:	48 8d bc 24 e0 00 00 	lea    0xe0(%rsp),%rdi
 104347a:	00
 104347b:	4c 89 fe             	mov    %r15,%rsi
 104347e:	4c 89 f2             	mov    %r14,%rdx
 1043481:	e8 4a 0d 00 00       	call   10441d0 <my.json::read_string>
 1043486:	48 8b 84 24 e8 00 00 	mov    0xe8(%rsp),%rax
 104348d:	00
 104348e:	48 8b 9c 24 f8 00 00 	mov    0xf8(%rsp),%rbx
 1043495:	00
 1043496:	48 8b 8c 24 f0 00 00 	mov    0xf0(%rsp),%rcx
 104349d:	00
 104349e:	0f b6 94 24 e0 00 00 	movzbl 0xe0(%rsp),%edx
 10434a5:	00
 10434a6:	80 fa 01             	cmp    $0x1,%dl
 10434a9:	0f 84 23 03 00 00    	je     10437d2 <my.json::read_value+0x1542>
 10434af:	8b 30                	mov    (%rax),%esi
 10434b1:	83 fe ff             	cmp    $0xffffffff,%esi
 10434b4:	74 10                	je     10434c6 <my.json::read_value+0x1236>
 10434b6:	8d 7e 01             	lea    0x1(%rsi),%edi
 10434b9:	83 ff ff             	cmp    $0xffffffff,%edi
 10434bc:	0f 44 f7             	cmove  %edi,%esi
 10434bf:	84 d2                	test   %dl,%dl
 10434c1:	0f 45 f7             	cmovne %edi,%esi
 10434c4:	89 30                	mov    %esi,(%rax)
 10434c6:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 10434cb:	48 c7 02 00 00 00 00 	movq   $0x0,(%rdx)
 10434d2:	48 c7 42 08 04 00 00 	movq   $0x4,0x8(%rdx)
 10434d9:	00
 10434da:	48 89 42 10          	mov    %rax,0x10(%rdx)
 10434de:	48 89 4a 18          	mov    %rcx,0x18(%rdx)
 10434e2:	e9 60 06 00 00       	jmp    1043b47 <my.json::read_value+0x18b7>
 10434e7:	48 8d 05 b2 4c fc ff 	lea    -0x3b34e(%rip),%rax        # 10081a0 <core_number_pairs+0x17d0>
 10434ee:	4c 89 ff             	mov    %r15,%rdi
 10434f1:	48 89 d6             	mov    %rdx,%rsi
 10434f4:	48 89 d3             	mov    %rdx,%rbx
 10434f7:	48 89 c2             	mov    %rax,%rdx
 10434fa:	e8 31 09 00 00       	call   1043e30 <my.json::fail>
 10434ff:	48 8d 3d 3a de 00 00 	lea    0xde3a(%rip),%rdi        # 1051340 <core_io_file_error.verbs+0x470>
 1043506:	e8 35 d8 ff ff       	call   1040d40 <myl_core_err_trace_origin_preserve_most>
 104350b:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 1043510:	48 c7 02 01 00 00 00 	movq   $0x1,(%rdx)
 1043517:	48 89 42 08          	mov    %rax,0x8(%rdx)
 104351b:	4c 89 7a 18          	mov    %r15,0x18(%rdx)
 104351f:	e9 23 06 00 00       	jmp    1043b47 <my.json::read_value+0x18b7>
 1043524:	48 8d 05 95 4d fc ff 	lea    -0x3b26b(%rip),%rax        # 10082c0 <core_number_pairs+0x18f0>
 104352b:	4c 89 ff             	mov    %r15,%rdi
 104352e:	4c 89 f6             	mov    %r14,%rsi
 1043531:	48 89 d3             	mov    %rdx,%rbx
 1043534:	48 89 c2             	mov    %rax,%rdx
 1043537:	e8 f4 08 00 00       	call   1043e30 <my.json::fail>
 104353c:	48 8d 3d 7d df 00 00 	lea    0xdf7d(%rip),%rdi        # 10514c0 <core_io_file_error.verbs+0x5f0>
 1043543:	e8 f8 d7 ff ff       	call   1040d40 <myl_core_err_trace_origin_preserve_most>
 1043548:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 104354d:	48 c7 02 01 00 00 00 	movq   $0x1,(%rdx)
 1043554:	48 89 42 08          	mov    %rax,0x8(%rdx)
 1043558:	48 89 6a 18          	mov    %rbp,0x18(%rdx)
 104355c:	e9 e6 05 00 00       	jmp    1043b47 <my.json::read_value+0x18b7>
 1043561:	83 f9 5d             	cmp    $0x5d,%ecx
 1043564:	0f 85 9d 02 00 00    	jne    1043807 <my.json::read_value+0x1577>
 104356a:	48 ff c2             	inc    %rdx
 104356d:	b8 05 00 00 00       	mov    $0x5,%eax
 1043572:	31 c9                	xor    %ecx,%ecx
 1043574:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1043579:	48 89 0e             	mov    %rcx,(%rsi)
 104357c:	48 89 46 08          	mov    %rax,0x8(%rsi)
 1043580:	48 89 5e 10          	mov    %rbx,0x10(%rsi)
 1043584:	4c 89 7e 18          	mov    %r15,0x18(%rsi)
 1043588:	48 89 d3             	mov    %rdx,%rbx
 104358b:	48 89 f2             	mov    %rsi,%rdx
 104358e:	e9 b4 05 00 00       	jmp    1043b47 <my.json::read_value+0x18b7>
 1043593:	49 89 d4             	mov    %rdx,%r12
 1043596:	48 8d 15 43 55 fc ff 	lea    -0x3aabd(%rip),%rdx        # 1008ae0 <core_number_pairs+0x2110>
 104359d:	4c 89 ff             	mov    %r15,%rdi
 10435a0:	4c 89 f6             	mov    %r14,%rsi
 10435a3:	e8 88 08 00 00       	call   1043e30 <my.json::fail>
 10435a8:	48 8d 3d a1 e5 00 00 	lea    0xe5a1(%rip),%rdi        # 1051b50 <core_io_file_error.verbs+0xc80>
 10435af:	b1 01                	mov    $0x1,%cl
 10435b1:	e8 8a d7 ff ff       	call   1040d40 <myl_core_err_trace_origin_preserve_most>
 10435b6:	4c 89 f3             	mov    %r14,%rbx
 10435b9:	4c 89 e2             	mov    %r12,%rdx
 10435bc:	80 f9 01             	cmp    $0x1,%cl
 10435bf:	0f 85 f3 f1 ff ff    	jne    10427b8 <my.json::read_value+0x528>
 10435c5:	e9 43 f3 ff ff       	jmp    104290d <my.json::read_value+0x67d>
 10435ca:	83 f8 7d             	cmp    $0x7d,%eax
 10435cd:	0f 85 18 03 00 00    	jne    10438eb <my.json::read_value+0x165b>
 10435d3:	49 ff c4             	inc    %r12
 10435d6:	b9 06 00 00 00       	mov    $0x6,%ecx
 10435db:	31 c0                	xor    %eax,%eax
 10435dd:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 10435e2:	e9 4e 05 00 00       	jmp    1043b35 <my.json::read_value+0x18a5>
 10435e7:	80 7c 24 0f 00       	cmpb   $0x0,0xf(%rsp)
 10435ec:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 10435f1:	48 8b 7c 24 48       	mov    0x48(%rsp),%rdi
 10435f6:	0f 85 b9 03 00 00    	jne    10439b5 <my.json::read_value+0x1725>
 10435fc:	8b 07                	mov    (%rdi),%eax
 10435fe:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043601:	0f 84 ae 03 00 00    	je     10439b5 <my.json::read_value+0x1725>
 1043607:	ff c8                	dec    %eax
 1043609:	0f 85 a4 03 00 00    	jne    10439b3 <my.json::read_value+0x1723>
 104360f:	0f b6 47 07          	movzbl 0x7(%rdi),%eax
 1043613:	48 85 c0             	test   %rax,%rax
 1043616:	0f 84 83 06 00 00    	je     1043c9f <my.json::read_value+0x1a0f>
 104361c:	48 83 7f 18 00       	cmpq   $0x0,0x18(%rdi)
 1043621:	0f 85 78 06 00 00    	jne    1043c9f <my.json::read_value+0x1a0f>
 1043627:	48 8d 15 52 34 03 00 	lea    0x33452(%rip),%rdx        # 1076a80 <myl_core_free_lists>
 104362e:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043632:	48 89 0f             	mov    %rcx,(%rdi)
 1043635:	48 89 3c c2          	mov    %rdi,(%rdx,%rax,8)
 1043639:	e9 77 03 00 00       	jmp    10439b5 <my.json::read_value+0x1725>
 104363e:	48 8d 15 7b 51 fc ff 	lea    -0x3ae85(%rip),%rdx        # 10087c0 <core_number_pairs+0x1df0>
 1043645:	4c 89 ff             	mov    %r15,%rdi
 1043648:	48 89 de             	mov    %rbx,%rsi
 104364b:	e8 e0 07 00 00       	call   1043e30 <my.json::fail>
 1043650:	48 8d 3d 89 e2 00 00 	lea    0xe289(%rip),%rdi        # 10518e0 <core_io_file_error.verbs+0xa10>
 1043657:	e8 e4 d6 ff ff       	call   1040d40 <myl_core_err_trace_origin_preserve_most>
 104365c:	e9 44 01 00 00       	jmp    10437a5 <my.json::read_value+0x1515>
 1043661:	41 8b 45 00          	mov    0x0(%r13),%eax
 1043665:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043668:	0f 84 df 03 00 00    	je     1043a4d <my.json::read_value+0x17bd>
 104366e:	ff c8                	dec    %eax
 1043670:	0f 85 d3 03 00 00    	jne    1043a49 <my.json::read_value+0x17b9>
 1043676:	41 0f b6 45 07       	movzbl 0x7(%r13),%eax
 104367b:	48 85 c0             	test   %rax,%rax
 104367e:	0f 84 25 06 00 00    	je     1043ca9 <my.json::read_value+0x1a19>
 1043684:	49 83 7d 18 00       	cmpq   $0x0,0x18(%r13)
 1043689:	0f 85 1a 06 00 00    	jne    1043ca9 <my.json::read_value+0x1a19>
 104368f:	48 8d 0d ea 33 03 00 	lea    0x333ea(%rip),%rcx        # 1076a80 <myl_core_free_lists>
 1043696:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 104369a:	49 89 55 00          	mov    %rdx,0x0(%r13)
 104369e:	4c 89 2c c1          	mov    %r13,(%rcx,%rax,8)
 10436a2:	e9 a6 03 00 00       	jmp    1043a4d <my.json::read_value+0x17bd>
 10436a7:	48 8d 05 52 4c fc ff 	lea    -0x3b3ae(%rip),%rax        # 1008300 <core_number_pairs+0x1930>
 10436ae:	4c 89 ff             	mov    %r15,%rdi
 10436b1:	4c 89 f6             	mov    %r14,%rsi
 10436b4:	48 89 d3             	mov    %rdx,%rbx
 10436b7:	48 89 c2             	mov    %rax,%rdx
 10436ba:	e8 71 07 00 00       	call   1043e30 <my.json::fail>
 10436bf:	48 8d 3d 2a de 00 00 	lea    0xde2a(%rip),%rdi        # 10514f0 <core_io_file_error.verbs+0x620>
 10436c6:	e9 78 fe ff ff       	jmp    1043543 <my.json::read_value+0x12b3>
 10436cb:	48 8d 0d ce 54 fc ff 	lea    -0x3ab32(%rip),%rcx        # 1008ba0 <core_number_pairs+0x21d0>
 10436d2:	4c 89 ff             	mov    %r15,%rdi
 10436d5:	48 89 de             	mov    %rbx,%rsi
 10436d8:	4d 89 fc             	mov    %r15,%r12
 10436db:	49 89 d7             	mov    %rdx,%r15
 10436de:	48 89 ca             	mov    %rcx,%rdx
 10436e1:	49 89 c6             	mov    %rax,%r14
 10436e4:	e8 47 07 00 00       	call   1043e30 <my.json::fail>
 10436e9:	4c 89 fa             	mov    %r15,%rdx
 10436ec:	4d 89 e7             	mov    %r12,%r15
 10436ef:	48 89 c1             	mov    %rax,%rcx
 10436f2:	4c 89 f0             	mov    %r14,%rax
 10436f5:	40 b6 01             	mov    $0x1,%sil
 10436f8:	48 8d 3d e1 e4 00 00 	lea    0xe4e1(%rip),%rdi        # 1051be0 <core_io_file_error.verbs+0xd10>
 10436ff:	e8 3c d6 ff ff       	call   1040d40 <myl_core_err_trace_origin_preserve_most>
 1043704:	40 80 fe 01          	cmp    $0x1,%sil
 1043708:	0f 85 4d f3 ff ff    	jne    1042a5b <my.json::read_value+0x7cb>
 104370e:	48 8d 3d 9b e1 00 00 	lea    0xe19b(%rip),%rdi        # 10518b0 <core_io_file_error.verbs+0x9e0>
 1043715:	e8 66 d6 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 104371a:	8b 01                	mov    (%rcx),%eax
 104371c:	83 f8 ff             	cmp    $0xffffffff,%eax
 104371f:	74 0d                	je     104372e <my.json::read_value+0x149e>
 1043721:	83 f8 fe             	cmp    $0xfffffffe,%eax
 1043724:	ba ff ff ff ff       	mov    $0xffffffff,%edx
 1043729:	0f 45 d0             	cmovne %eax,%edx
 104372c:	89 11                	mov    %edx,(%rcx)
 104372e:	48 89 c8             	mov    %rcx,%rax
 1043731:	eb 72                	jmp    10437a5 <my.json::read_value+0x1515>
 1043733:	48 8d 3d c6 dc 00 00 	lea    0xdcc6(%rip),%rdi        # 1051400 <core_io_file_error.verbs+0x530>
 104373a:	c5 f9 7f 44 24 20    	vmovdqa %xmm0,0x20(%rsp)
 1043740:	e8 3b d6 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 1043745:	c5 f9 6f 44 24 20    	vmovdqa 0x20(%rsp),%xmm0
 104374b:	e9 5e f4 ff ff       	jmp    1042bae <my.json::read_value+0x91e>
 1043750:	48 8d 05 09 54 fc ff 	lea    -0x3abf7(%rip),%rax        # 1008b60 <core_number_pairs+0x2190>
 1043757:	4c 89 ff             	mov    %r15,%rdi
 104375a:	4c 89 f6             	mov    %r14,%rsi
 104375d:	48 89 d3             	mov    %rdx,%rbx
 1043760:	48 89 c2             	mov    %rax,%rdx
 1043763:	e8 c8 06 00 00       	call   1043e30 <my.json::fail>
 1043768:	48 89 da             	mov    %rbx,%rdx
 104376b:	b1 01                	mov    $0x1,%cl
 104376d:	48 8d 3d 3c e4 00 00 	lea    0xe43c(%rip),%rdi        # 1051bb0 <core_io_file_error.verbs+0xce0>
 1043774:	e8 c7 d5 ff ff       	call   1040d40 <myl_core_err_trace_origin_preserve_most>
 1043779:	80 f9 01             	cmp    $0x1,%cl
 104377c:	0f 85 c4 f1 ff ff    	jne    1042946 <my.json::read_value+0x6b6>
 1043782:	48 8d 3d f7 e0 00 00 	lea    0xe0f7(%rip),%rdi        # 1051880 <core_io_file_error.verbs+0x9b0>
 1043789:	e8 f2 d5 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 104378e:	8b 08                	mov    (%rax),%ecx
 1043790:	83 f9 ff             	cmp    $0xffffffff,%ecx
 1043793:	74 0d                	je     10437a2 <my.json::read_value+0x1512>
 1043795:	83 f9 fe             	cmp    $0xfffffffe,%ecx
 1043798:	ba ff ff ff ff       	mov    $0xffffffff,%edx
 104379d:	0f 45 d1             	cmovne %ecx,%edx
 10437a0:	89 10                	mov    %edx,(%rax)
 10437a2:	4c 89 f3             	mov    %r14,%rbx
 10437a5:	48 8d 3d e4 dc 00 00 	lea    0xdce4(%rip),%rdi        # 1051490 <core_io_file_error.verbs+0x5c0>
 10437ac:	e8 cf d5 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 10437b1:	ba 01 00 00 00       	mov    $0x1,%edx
 10437b6:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10437bb:	48 89 16             	mov    %rdx,(%rsi)
 10437be:	48 89 f2             	mov    %rsi,%rdx
 10437c1:	48 89 46 08          	mov    %rax,0x8(%rsi)
 10437c5:	48 89 4e 10          	mov    %rcx,0x10(%rsi)
 10437c9:	4c 89 7e 18          	mov    %r15,0x18(%rsi)
 10437cd:	e9 75 03 00 00       	jmp    1043b47 <my.json::read_value+0x18b7>
 10437d2:	48 8d 3d f7 db 00 00 	lea    0xdbf7(%rip),%rdi        # 10513d0 <core_io_file_error.verbs+0x500>
 10437d9:	e8 a2 d5 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 10437de:	8b 10                	mov    (%rax),%edx
 10437e0:	83 fa ff             	cmp    $0xffffffff,%edx
 10437e3:	74 0d                	je     10437f2 <my.json::read_value+0x1562>
 10437e5:	83 fa fe             	cmp    $0xfffffffe,%edx
 10437e8:	be ff ff ff ff       	mov    $0xffffffff,%esi
 10437ed:	0f 45 f2             	cmovne %edx,%esi
 10437f0:	89 30                	mov    %esi,(%rax)
 10437f2:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 10437f7:	48 c7 02 01 00 00 00 	movq   $0x1,(%rdx)
 10437fe:	48 89 42 08          	mov    %rax,0x8(%rdx)
 1043802:	e9 d7 fc ff ff       	jmp    10434de <my.json::read_value+0x124e>
 1043807:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 104380b:	48 85 c0             	test   %rax,%rax
 104380e:	0f 84 20 04 00 00    	je     1043c34 <my.json::read_value+0x19a4>
 1043814:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043819:	0f 85 15 04 00 00    	jne    1043c34 <my.json::read_value+0x19a4>
 104381f:	48 8d 35 5a 32 03 00 	lea    0x3325a(%rip),%rsi        # 1076a80 <myl_core_free_lists>
 1043826:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 104382a:	48 89 0b             	mov    %rcx,(%rbx)
 104382d:	48 89 1c c6          	mov    %rbx,(%rsi,%rax,8)
 1043831:	48 8d 05 08 4e fc ff 	lea    -0x3b1f8(%rip),%rax        # 1008640 <core_number_pairs+0x1c70>
 1043838:	4c 89 ff             	mov    %r15,%rdi
 104383b:	48 89 d6             	mov    %rdx,%rsi
 104383e:	48 89 d3             	mov    %rdx,%rbx
 1043841:	48 89 c2             	mov    %rax,%rdx
 1043844:	e8 e7 05 00 00       	call   1043e30 <my.json::fail>
 1043849:	48 89 da             	mov    %rbx,%rdx
 104384c:	48 8d 3d ed dd 00 00 	lea    0xdded(%rip),%rdi        # 1051640 <core_io_file_error.verbs+0x770>
 1043853:	e9 b9 05 00 00       	jmp    1043e11 <my.json::read_value+0x1b81>
 1043858:	48 8d 15 c1 50 fc ff 	lea    -0x3af3f(%rip),%rdx        # 1008920 <core_number_pairs+0x1f50>
 104385f:	4c 89 f7             	mov    %r14,%rdi
 1043862:	4c 89 e6             	mov    %r12,%rsi
 1043865:	e8 c6 05 00 00       	call   1043e30 <my.json::fail>
 104386a:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 104386f:	48 8d 3d fa e0 00 00 	lea    0xe0fa(%rip),%rdi        # 1051970 <core_io_file_error.verbs+0xaa0>
 1043876:	e9 58 01 00 00       	jmp    10439d3 <my.json::read_value+0x1743>
 104387b:	80 7c 24 0f 00       	cmpb   $0x0,0xf(%rsp)
 1043880:	0f 85 dd 02 00 00    	jne    1043b63 <my.json::read_value+0x18d3>
 1043886:	41 8b 07             	mov    (%r15),%eax
 1043889:	83 f8 ff             	cmp    $0xffffffff,%eax
 104388c:	0f 84 d1 02 00 00    	je     1043b63 <my.json::read_value+0x18d3>
 1043892:	ff c8                	dec    %eax
 1043894:	0f 85 c6 02 00 00    	jne    1043b60 <my.json::read_value+0x18d0>
 104389a:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 104389f:	48 85 c0             	test   %rax,%rax
 10438a2:	0f 84 8d 04 00 00    	je     1043d35 <my.json::read_value+0x1aa5>
 10438a8:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 10438ad:	0f 85 82 04 00 00    	jne    1043d35 <my.json::read_value+0x1aa5>
 10438b3:	48 8d 15 c6 31 03 00 	lea    0x331c6(%rip),%rdx        # 1076a80 <myl_core_free_lists>
 10438ba:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 10438be:	49 89 0f             	mov    %rcx,(%r15)
 10438c1:	4c 89 3c c2          	mov    %r15,(%rdx,%rax,8)
 10438c5:	e9 99 02 00 00       	jmp    1043b63 <my.json::read_value+0x18d3>
 10438ca:	49 89 d4             	mov    %rdx,%r12
 10438cd:	48 8d 15 4c 52 fc ff 	lea    -0x3adb4(%rip),%rdx        # 1008b20 <core_number_pairs+0x2150>
 10438d4:	4c 89 ff             	mov    %r15,%rdi
 10438d7:	4c 89 f6             	mov    %r14,%rsi
 10438da:	e8 51 05 00 00       	call   1043e30 <my.json::fail>
 10438df:	48 8d 3d 9a e2 00 00 	lea    0xe29a(%rip),%rdi        # 1051b80 <core_io_file_error.verbs+0xcb0>
 10438e6:	e9 c4 fc ff ff       	jmp    10435af <my.json::read_value+0x131f>
 10438eb:	41 8b 45 00          	mov    0x0(%r13),%eax
 10438ef:	83 f8 ff             	cmp    $0xffffffff,%eax
 10438f2:	0f 84 ff 01 00 00    	je     1043af7 <my.json::read_value+0x1867>
 10438f8:	ff c8                	dec    %eax
 10438fa:	0f 85 f3 01 00 00    	jne    1043af3 <my.json::read_value+0x1863>
 1043900:	41 0f b6 45 07       	movzbl 0x7(%r13),%eax
 1043905:	48 85 c0             	test   %rax,%rax
 1043908:	0f 84 08 04 00 00    	je     1043d16 <my.json::read_value+0x1a86>
 104390e:	49 83 7d 18 00       	cmpq   $0x0,0x18(%r13)
 1043913:	0f 85 fd 03 00 00    	jne    1043d16 <my.json::read_value+0x1a86>
 1043919:	48 8d 15 60 31 03 00 	lea    0x33160(%rip),%rdx        # 1076a80 <myl_core_free_lists>
 1043920:	48 8b 0c c2          	mov    (%rdx,%rax,8),%rcx
 1043924:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 1043928:	4c 89 2c c2          	mov    %r13,(%rdx,%rax,8)
 104392c:	e9 c6 01 00 00       	jmp    1043af7 <my.json::read_value+0x1867>
 1043931:	0f b6 4b 07          	movzbl 0x7(%rbx),%ecx
 1043935:	48 85 c9             	test   %rcx,%rcx
 1043938:	0f 84 36 03 00 00    	je     1043c74 <my.json::read_value+0x19e4>
 104393e:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 1043943:	0f 85 2b 03 00 00    	jne    1043c74 <my.json::read_value+0x19e4>
 1043949:	48 8d 3d 30 31 03 00 	lea    0x33130(%rip),%rdi        # 1076a80 <myl_core_free_lists>
 1043950:	48 8b 34 cf          	mov    (%rdi,%rcx,8),%rsi
 1043954:	48 89 33             	mov    %rsi,(%rbx)
 1043957:	48 89 1c cf          	mov    %rbx,(%rdi,%rcx,8)
 104395b:	48 8d 3d ae dc 00 00 	lea    0xdcae(%rip),%rdi        # 1051610 <core_io_file_error.verbs+0x740>
 1043962:	e8 19 d4 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 1043967:	8b 08                	mov    (%rax),%ecx
 1043969:	83 f9 ff             	cmp    $0xffffffff,%ecx
 104396c:	0f 84 a4 04 00 00    	je     1043e16 <my.json::read_value+0x1b86>
 1043972:	83 f9 fe             	cmp    $0xfffffffe,%ecx
 1043975:	be ff ff ff ff       	mov    $0xffffffff,%esi
 104397a:	0f 45 f1             	cmovne %ecx,%esi
 104397d:	89 30                	mov    %esi,(%rax)
 104397f:	e9 92 04 00 00       	jmp    1043e16 <my.json::read_value+0x1b86>
 1043984:	0f b6 43 07          	movzbl 0x7(%rbx),%eax
 1043988:	48 85 c0             	test   %rax,%rax
 104398b:	48 8d 35 ee 30 03 00 	lea    0x330ee(%rip),%rsi        # 1076a80 <myl_core_free_lists>
 1043992:	0f 84 49 04 00 00    	je     1043de1 <my.json::read_value+0x1b51>
 1043998:	48 83 7b 18 00       	cmpq   $0x0,0x18(%rbx)
 104399d:	0f 85 3e 04 00 00    	jne    1043de1 <my.json::read_value+0x1b51>
 10439a3:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 10439a7:	48 89 0b             	mov    %rcx,(%rbx)
 10439aa:	48 89 1c c6          	mov    %rbx,(%rsi,%rax,8)
 10439ae:	e9 3c 04 00 00       	jmp    1043def <my.json::read_value+0x1b5f>
 10439b3:	89 07                	mov    %eax,(%rdi)
 10439b5:	48 8d 15 c4 4f fc ff 	lea    -0x3b03c(%rip),%rdx        # 1008980 <core_number_pairs+0x1fb0>
 10439bc:	4c 89 f7             	mov    %r14,%rdi
 10439bf:	4c 89 e6             	mov    %r12,%rsi
 10439c2:	e8 69 04 00 00       	call   1043e30 <my.json::fail>
 10439c7:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 10439cc:	48 8d 3d fd df 00 00 	lea    0xdffd(%rip),%rdi        # 10519d0 <core_io_file_error.verbs+0xb00>
 10439d3:	e8 68 d3 ff ff       	call   1040d40 <myl_core_err_trace_origin_preserve_most>
 10439d8:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 10439dd:	41 8b 45 00          	mov    0x0(%r13),%eax
 10439e1:	83 f8 ff             	cmp    $0xffffffff,%eax
 10439e4:	74 36                	je     1043a1c <my.json::read_value+0x178c>
 10439e6:	ff c8                	dec    %eax
 10439e8:	75 2e                	jne    1043a18 <my.json::read_value+0x1788>
 10439ea:	41 0f b6 45 07       	movzbl 0x7(%r13),%eax
 10439ef:	48 85 c0             	test   %rax,%rax
 10439f2:	0f 84 2a 02 00 00    	je     1043c22 <my.json::read_value+0x1992>
 10439f8:	49 83 7d 18 00       	cmpq   $0x0,0x18(%r13)
 10439fd:	0f 85 1f 02 00 00    	jne    1043c22 <my.json::read_value+0x1992>
 1043a03:	48 8d 35 76 30 03 00 	lea    0x33076(%rip),%rsi        # 1076a80 <myl_core_free_lists>
 1043a0a:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1043a0e:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 1043a12:	4c 89 2c c6          	mov    %r13,(%rsi,%rax,8)
 1043a16:	eb 04                	jmp    1043a1c <my.json::read_value+0x178c>
 1043a18:	41 89 45 00          	mov    %eax,0x0(%r13)
 1043a1c:	48 8d 3d 5d db 00 00 	lea    0xdb5d(%rip),%rdi        # 1051580 <core_io_file_error.verbs+0x6b0>
 1043a23:	e8 58 d3 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 1043a28:	48 8b 74 24 30       	mov    0x30(%rsp),%rsi
 1043a2d:	8b 06                	mov    (%rsi),%eax
 1043a2f:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043a32:	74 0d                	je     1043a41 <my.json::read_value+0x17b1>
 1043a34:	83 f8 fe             	cmp    $0xfffffffe,%eax
 1043a37:	b9 ff ff ff ff       	mov    $0xffffffff,%ecx
 1043a3c:	0f 45 c8             	cmovne %eax,%ecx
 1043a3f:	89 0e                	mov    %ecx,(%rsi)
 1043a41:	4d 89 f7             	mov    %r14,%r15
 1043a44:	e9 d6 00 00 00       	jmp    1043b1f <my.json::read_value+0x188f>
 1043a49:	41 89 45 00          	mov    %eax,0x0(%r13)
 1043a4d:	48 8d 15 0c 4b fc ff 	lea    -0x3b4f4(%rip),%rdx        # 1008560 <core_number_pairs+0x1b90>
 1043a54:	4c 89 ff             	mov    %r15,%rdi
 1043a57:	4c 89 e6             	mov    %r12,%rsi
 1043a5a:	e8 d1 03 00 00       	call   1043e30 <my.json::fail>
 1043a5f:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 1043a64:	48 8d 3d e5 da 00 00 	lea    0xdae5(%rip),%rdi        # 1051550 <core_io_file_error.verbs+0x680>
 1043a6b:	e9 a5 00 00 00       	jmp    1043b15 <my.json::read_value+0x1885>
 1043a70:	48 8d 3d 29 df 00 00 	lea    0xdf29(%rip),%rdi        # 10519a0 <core_io_file_error.verbs+0xad0>
 1043a77:	e8 04 d3 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 1043a7c:	8b 03                	mov    (%rbx),%eax
 1043a7e:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043a81:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 1043a86:	74 0d                	je     1043a95 <my.json::read_value+0x1805>
 1043a88:	83 f8 fe             	cmp    $0xfffffffe,%eax
 1043a8b:	b9 ff ff ff ff       	mov    $0xffffffff,%ecx
 1043a90:	0f 45 c8             	cmovne %eax,%ecx
 1043a93:	89 0b                	mov    %ecx,(%rbx)
 1043a95:	48 89 5c 24 30       	mov    %rbx,0x30(%rsp)
 1043a9a:	e9 3e ff ff ff       	jmp    10439dd <my.json::read_value+0x174d>
 1043a9f:	80 7c 24 0f 00       	cmpb   $0x0,0xf(%rsp)
 1043aa4:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 1043aa9:	0f 85 da 00 00 00    	jne    1043b89 <my.json::read_value+0x18f9>
 1043aaf:	41 8b 07             	mov    (%r15),%eax
 1043ab2:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043ab5:	0f 84 ce 00 00 00    	je     1043b89 <my.json::read_value+0x18f9>
 1043abb:	ff c8                	dec    %eax
 1043abd:	0f 85 c3 00 00 00    	jne    1043b86 <my.json::read_value+0x18f6>
 1043ac3:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 1043ac8:	48 85 c0             	test   %rax,%rax
 1043acb:	0f 84 b6 02 00 00    	je     1043d87 <my.json::read_value+0x1af7>
 1043ad1:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 1043ad6:	0f 85 ab 02 00 00    	jne    1043d87 <my.json::read_value+0x1af7>
 1043adc:	48 8d 35 9d 2f 03 00 	lea    0x32f9d(%rip),%rsi        # 1076a80 <myl_core_free_lists>
 1043ae3:	48 8b 0c c6          	mov    (%rsi,%rax,8),%rcx
 1043ae7:	49 89 0f             	mov    %rcx,(%r15)
 1043aea:	4c 89 3c c6          	mov    %r15,(%rsi,%rax,8)
 1043aee:	e9 96 00 00 00       	jmp    1043b89 <my.json::read_value+0x18f9>
 1043af3:	41 89 45 00          	mov    %eax,0x0(%r13)
 1043af7:	48 8d 15 a2 4a fc ff 	lea    -0x3b55e(%rip),%rdx        # 10085a0 <core_number_pairs+0x1bd0>
 1043afe:	4c 89 ff             	mov    %r15,%rdi
 1043b01:	4c 89 e6             	mov    %r12,%rsi
 1043b04:	e8 27 03 00 00       	call   1043e30 <my.json::fail>
 1043b09:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 1043b0e:	48 8d 3d 9b da 00 00 	lea    0xda9b(%rip),%rdi        # 10515b0 <core_io_file_error.verbs+0x6e0>
 1043b15:	e8 26 d2 ff ff       	call   1040d40 <myl_core_err_trace_origin_preserve_most>
 1043b1a:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 1043b1f:	48 8d 3d 4a d8 00 00 	lea    0xd84a(%rip),%rdi        # 1051370 <core_io_file_error.verbs+0x4a0>
 1043b26:	e8 55 d2 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 1043b2b:	b8 01 00 00 00       	mov    $0x1,%eax
 1043b30:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 1043b35:	48 89 02             	mov    %rax,(%rdx)
 1043b38:	48 89 4a 08          	mov    %rcx,0x8(%rdx)
 1043b3c:	4c 89 6a 10          	mov    %r13,0x10(%rdx)
 1043b40:	4c 89 7a 18          	mov    %r15,0x18(%rdx)
 1043b44:	4c 89 e3             	mov    %r12,%rbx
 1043b47:	48 89 5a 20          	mov    %rbx,0x20(%rdx)
 1043b4b:	48 89 d0             	mov    %rdx,%rax
 1043b4e:	48 81 c4 88 01 00 00 	add    $0x188,%rsp
 1043b55:	5b                   	pop    %rbx
 1043b56:	41 5c                	pop    %r12
 1043b58:	41 5d                	pop    %r13
 1043b5a:	41 5e                	pop    %r14
 1043b5c:	41 5f                	pop    %r15
 1043b5e:	5d                   	pop    %rbp
 1043b5f:	c3                   	ret
 1043b60:	41 89 07             	mov    %eax,(%r15)
 1043b63:	48 8d 15 56 4e fc ff 	lea    -0x3b1aa(%rip),%rdx        # 10089c0 <core_number_pairs+0x1ff0>
 1043b6a:	4c 89 f7             	mov    %r14,%rdi
 1043b6d:	4c 89 e6             	mov    %r12,%rsi
 1043b70:	e8 bb 02 00 00       	call   1043e30 <my.json::fail>
 1043b75:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 1043b7a:	48 8d 3d 7f de 00 00 	lea    0xde7f(%rip),%rdi        # 1051a00 <core_io_file_error.verbs+0xb30>
 1043b81:	e9 4d fe ff ff       	jmp    10439d3 <my.json::read_value+0x1743>
 1043b86:	41 89 07             	mov    %eax,(%r15)
 1043b89:	48 8d 3d a0 de 00 00 	lea    0xdea0(%rip),%rdi        # 1051a30 <core_io_file_error.verbs+0xb60>
 1043b90:	e8 eb d1 ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 1043b95:	48 8b 74 24 30       	mov    0x30(%rsp),%rsi
 1043b9a:	8b 06                	mov    (%rsi),%eax
 1043b9c:	83 f8 ff             	cmp    $0xffffffff,%eax
 1043b9f:	0f 84 38 fe ff ff    	je     10439dd <my.json::read_value+0x174d>
 1043ba5:	83 f8 fe             	cmp    $0xfffffffe,%eax
 1043ba8:	b9 ff ff ff ff       	mov    $0xffffffff,%ecx
 1043bad:	0f 45 c8             	cmovne %eax,%ecx
 1043bb0:	89 0e                	mov    %ecx,(%rsi)
 1043bb2:	e9 26 fe ff ff       	jmp    10439dd <my.json::read_value+0x174d>
 1043bb7:	be 10 00 00 00       	mov    $0x10,%esi
 1043bbc:	31 ff                	xor    %edi,%edi
 1043bbe:	48 89 d3             	mov    %rdx,%rbx
 1043bc1:	e8 7a fe fc ff       	call   1013a40 <myl_core_list_new_slow>
 1043bc6:	48 89 da             	mov    %rbx,%rdx
 1043bc9:	48 89 c3             	mov    %rax,%rbx
 1043bcc:	e9 f3 e7 ff ff       	jmp    10423c4 <my.json::read_value+0x134>
 1043bd1:	48 8d 3d 48 d9 00 00 	lea    0xd948(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043bd8:	48 89 d6             	mov    %rdx,%rsi
 1043bdb:	48 89 c2             	mov    %rax,%rdx
 1043bde:	e8 1d 0a fd ff       	call   1014600 <myl_core_trap>
 1043be3:	48 8d 3d 36 d9 00 00 	lea    0xd936(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043bea:	48 89 d6             	mov    %rdx,%rsi
 1043bed:	48 89 c2             	mov    %rax,%rdx
 1043bf0:	e8 0b 0a fd ff       	call   1014600 <myl_core_trap>
 1043bf5:	48 8d 3d 24 d9 00 00 	lea    0xd924(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043bfc:	4c 89 e6             	mov    %r12,%rsi
 1043bff:	e8 fc 09 fd ff       	call   1014600 <myl_core_trap>
 1043c04:	48 8d 3d 15 d9 00 00 	lea    0xd915(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043c0b:	4c 89 e6             	mov    %r12,%rsi
 1043c0e:	e8 ed 09 fd ff       	call   1014600 <myl_core_trap>
 1043c13:	48 8d 3d 06 d9 00 00 	lea    0xd906(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043c1a:	4c 89 e6             	mov    %r12,%rsi
 1043c1d:	e8 de 09 fd ff       	call   1014600 <myl_core_trap>
 1043c22:	4c 89 ef             	mov    %r13,%rdi
 1043c25:	e8 16 cd ff ff       	call   1040940 <myl_core_free_block>
 1043c2a:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 1043c2f:	e9 e8 fd ff ff       	jmp    1043a1c <my.json::read_value+0x178c>
 1043c34:	48 89 df             	mov    %rbx,%rdi
 1043c37:	48 89 d3             	mov    %rdx,%rbx
 1043c3a:	e8 01 cd ff ff       	call   1040940 <myl_core_free_block>
 1043c3f:	48 89 da             	mov    %rbx,%rdx
 1043c42:	e9 ea fb ff ff       	jmp    1043831 <my.json::read_value+0x15a1>
 1043c47:	48 8d 3d d2 d8 00 00 	lea    0xd8d2(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043c4e:	48 89 de             	mov    %rbx,%rsi
 1043c51:	48 89 ca             	mov    %rcx,%rdx
 1043c54:	e8 a7 09 fd ff       	call   1014600 <myl_core_trap>
 1043c59:	48 8d 3d c0 d8 00 00 	lea    0xd8c0(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043c60:	48 89 c2             	mov    %rax,%rdx
 1043c63:	e8 98 09 fd ff       	call   1014600 <myl_core_trap>
 1043c68:	48 8d 3d b1 d8 00 00 	lea    0xd8b1(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043c6f:	e8 8c 09 fd ff       	call   1014600 <myl_core_trap>
 1043c74:	48 89 df             	mov    %rbx,%rdi
 1043c77:	48 89 d3             	mov    %rdx,%rbx
 1043c7a:	49 89 c6             	mov    %rax,%r14
 1043c7d:	e8 be cc ff ff       	call   1040940 <myl_core_free_block>
 1043c82:	4c 89 f0             	mov    %r14,%rax
 1043c85:	48 89 da             	mov    %rbx,%rdx
 1043c88:	e9 ce fc ff ff       	jmp    104395b <my.json::read_value+0x16cb>
 1043c8d:	48 8d 3d 8c d8 00 00 	lea    0xd88c(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043c94:	48 89 d6             	mov    %rdx,%rsi
 1043c97:	48 89 c2             	mov    %rax,%rdx
 1043c9a:	e8 61 09 fd ff       	call   1014600 <myl_core_trap>
 1043c9f:	e8 9c cc ff ff       	call   1040940 <myl_core_free_block>
 1043ca4:	e9 0c fd ff ff       	jmp    10439b5 <my.json::read_value+0x1725>
 1043ca9:	4c 89 ef             	mov    %r13,%rdi
 1043cac:	e8 8f cc ff ff       	call   1040940 <myl_core_free_block>
 1043cb1:	e9 97 fd ff ff       	jmp    1043a4d <my.json::read_value+0x17bd>
 1043cb6:	48 8d 3d 63 d8 00 00 	lea    0xd863(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043cbd:	48 89 de             	mov    %rbx,%rsi
 1043cc0:	4c 89 c2             	mov    %r8,%rdx
 1043cc3:	e8 38 09 fd ff       	call   1014600 <myl_core_trap>
 1043cc8:	48 8d 3d 51 d8 00 00 	lea    0xd851(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043ccf:	48 89 d6             	mov    %rdx,%rsi
 1043cd2:	48 89 ca             	mov    %rcx,%rdx
 1043cd5:	e8 26 09 fd ff       	call   1014600 <myl_core_trap>
 1043cda:	48 8d 3d 3f d8 00 00 	lea    0xd83f(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043ce1:	48 89 ca             	mov    %rcx,%rdx
 1043ce4:	e8 17 09 fd ff       	call   1014600 <myl_core_trap>
 1043ce9:	48 8d 3d 30 d8 00 00 	lea    0xd830(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043cf0:	4c 89 e6             	mov    %r12,%rsi
 1043cf3:	e8 08 09 fd ff       	call   1014600 <myl_core_trap>
 1043cf8:	48 8d 3d 21 d8 00 00 	lea    0xd821(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043cff:	4c 89 e6             	mov    %r12,%rsi
 1043d02:	e8 f9 08 fd ff       	call   1014600 <myl_core_trap>
 1043d07:	48 8d 3d 12 d8 00 00 	lea    0xd812(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043d0e:	4c 89 e6             	mov    %r12,%rsi
 1043d11:	e8 ea 08 fd ff       	call   1014600 <myl_core_trap>
 1043d16:	4c 89 ef             	mov    %r13,%rdi
 1043d19:	e8 22 cc ff ff       	call   1040940 <myl_core_free_block>
 1043d1e:	e9 d4 fd ff ff       	jmp    1043af7 <my.json::read_value+0x1867>
 1043d23:	48 8d 3d f6 d7 00 00 	lea    0xd7f6(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043d2a:	48 89 de             	mov    %rbx,%rsi
 1043d2d:	48 89 ca             	mov    %rcx,%rdx
 1043d30:	e8 cb 08 fd ff       	call   1014600 <myl_core_trap>
 1043d35:	4c 89 ff             	mov    %r15,%rdi
 1043d38:	e8 03 cc ff ff       	call   1040940 <myl_core_free_block>
 1043d3d:	e9 21 fe ff ff       	jmp    1043b63 <my.json::read_value+0x18d3>
 1043d42:	48 8d 3d d7 d7 00 00 	lea    0xd7d7(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043d49:	48 89 d6             	mov    %rdx,%rsi
 1043d4c:	48 89 c2             	mov    %rax,%rdx
 1043d4f:	e8 ac 08 fd ff       	call   1014600 <myl_core_trap>
 1043d54:	48 8d 3d c5 d7 00 00 	lea    0xd7c5(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043d5b:	4c 89 e6             	mov    %r12,%rsi
 1043d5e:	e8 9d 08 fd ff       	call   1014600 <myl_core_trap>
 1043d63:	48 8d 3d b6 d7 00 00 	lea    0xd7b6(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043d6a:	48 89 de             	mov    %rbx,%rsi
 1043d6d:	48 89 ca             	mov    %rcx,%rdx
 1043d70:	e8 8b 08 fd ff       	call   1014600 <myl_core_trap>
 1043d75:	48 8d 3d a4 d7 00 00 	lea    0xd7a4(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043d7c:	4c 89 f6             	mov    %r14,%rsi
 1043d7f:	48 89 ca             	mov    %rcx,%rdx
 1043d82:	e8 79 08 fd ff       	call   1014600 <myl_core_trap>
 1043d87:	4c 89 ff             	mov    %r15,%rdi
 1043d8a:	e8 b1 cb ff ff       	call   1040940 <myl_core_free_block>
 1043d8f:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 1043d94:	e9 f0 fd ff ff       	jmp    1043b89 <my.json::read_value+0x18f9>
 1043d99:	48 8d 3d 80 d7 00 00 	lea    0xd780(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043da0:	48 89 de             	mov    %rbx,%rsi
 1043da3:	4c 89 c2             	mov    %r8,%rdx
 1043da6:	e8 55 08 fd ff       	call   1014600 <myl_core_trap>
 1043dab:	48 8d 3d 6e d7 00 00 	lea    0xd76e(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043db2:	4c 89 f6             	mov    %r14,%rsi
 1043db5:	48 89 ca             	mov    %rcx,%rdx
 1043db8:	e8 43 08 fd ff       	call   1014600 <myl_core_trap>
 1043dbd:	48 8d 3d 5c d7 00 00 	lea    0xd75c(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043dc4:	4c 89 f6             	mov    %r14,%rsi
 1043dc7:	48 89 ca             	mov    %rcx,%rdx
 1043dca:	e8 31 08 fd ff       	call   1014600 <myl_core_trap>
 1043dcf:	48 8d 3d 4a d7 00 00 	lea    0xd74a(%rip),%rdi        # 1051520 <core_io_file_error.verbs+0x650>
 1043dd6:	48 89 de             	mov    %rbx,%rsi
 1043dd9:	48 89 ca             	mov    %rcx,%rdx
 1043ddc:	e8 1f 08 fd ff       	call   1014600 <myl_core_trap>
 1043de1:	49 89 d6             	mov    %rdx,%r14
 1043de4:	48 89 df             	mov    %rbx,%rdi
 1043de7:	e8 54 cb ff ff       	call   1040940 <myl_core_free_block>
 1043dec:	4c 89 f2             	mov    %r14,%rdx
 1043def:	48 8d 05 0a 48 fc ff 	lea    -0x3b7f6(%rip),%rax        # 1008600 <core_number_pairs+0x1c30>
 1043df6:	4c 89 ff             	mov    %r15,%rdi
 1043df9:	48 89 d6             	mov    %rdx,%rsi
 1043dfc:	48 89 d3             	mov    %rdx,%rbx
 1043dff:	48 89 c2             	mov    %rax,%rdx
 1043e02:	e8 29 00 00 00       	call   1043e30 <my.json::fail>
 1043e07:	48 89 da             	mov    %rbx,%rdx
 1043e0a:	48 8d 3d cf d7 00 00 	lea    0xd7cf(%rip),%rdi        # 10515e0 <core_io_file_error.verbs+0x710>
 1043e11:	e8 2a cf ff ff       	call   1040d40 <myl_core_err_trace_origin_preserve_most>
 1043e16:	48 8d 3d 83 d5 00 00 	lea    0xd583(%rip),%rdi        # 10513a0 <core_io_file_error.verbs+0x4d0>
 1043e1d:	e8 5e cf ff ff       	call   1040d80 <myl_core_err_trace_append_preserve_most>
 1043e22:	b9 01 00 00 00       	mov    $0x1,%ecx
 1043e27:	e9 48 f7 ff ff       	jmp    1043574 <my.json::read_value+0x12e4>

Disassembly of section .plt:
