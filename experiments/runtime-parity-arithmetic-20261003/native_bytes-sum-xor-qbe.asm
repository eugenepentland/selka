
/home/epentland/.cache/mylang-tmp/runtime-parity-arithmetic-20261003/byte-reduction-qbe:     file format elf64-x86-64


Disassembly of section .text:

0000000001019360 <myl_native_bytes_sum_xor>:
 1019360:	55                   	push   %rbp
 1019361:	48 89 e5             	mov    %rsp,%rbp
 1019364:	48 83 fe 10          	cmp    $0x10,%rsi
 1019368:	72 1c                	jb     1019386 <myl_native_bytes_sum_xor+0x26>
 101936a:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 101936e:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1019373:	48 8d 46 f0          	lea    -0x10(%rsi),%rax
 1019377:	89 c1                	mov    %eax,%ecx
 1019379:	f7 d1                	not    %ecx
 101937b:	f6 c1 30             	test   $0x30,%cl
 101937e:	75 16                	jne    1019396 <myl_native_bytes_sum_xor+0x36>
 1019380:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
 1019384:	eb 43                	jmp    10193c9 <myl_native_bytes_sum_xor+0x69>
 1019386:	31 c0                	xor    %eax,%eax
 1019388:	48 85 f6             	test   %rsi,%rsi
 101938b:	0f 85 a7 00 00 00    	jne    1019438 <myl_native_bytes_sum_xor+0xd8>
 1019391:	e9 3c 01 00 00       	jmp    10194d2 <myl_native_bytes_sum_xor+0x172>
 1019396:	89 c1                	mov    %eax,%ecx
 1019398:	c1 e9 04             	shr    $0x4,%ecx
 101939b:	ff c1                	inc    %ecx
 101939d:	83 e1 03             	and    $0x3,%ecx
 10193a0:	c5 e9 ef d2          	vpxor  %xmm2,%xmm2,%xmm2
 10193a4:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
 10193a8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 10193af:	00 
 10193b0:	c5 f9 ef 1f          	vpxor  (%rdi),%xmm0,%xmm3
 10193b4:	c5 e1 f6 da          	vpsadbw %xmm2,%xmm3,%xmm3
 10193b8:	c5 e1 d4 c9          	vpaddq %xmm1,%xmm3,%xmm1
 10193bc:	48 83 c7 10          	add    $0x10,%rdi
 10193c0:	48 83 c6 f0          	add    $0xfffffffffffffff0,%rsi
 10193c4:	48 ff c9             	dec    %rcx
 10193c7:	75 e7                	jne    10193b0 <myl_native_bytes_sum_xor+0x50>
 10193c9:	48 83 f8 30          	cmp    $0x30,%rax
 10193cd:	72 52                	jb     1019421 <myl_native_bytes_sum_xor+0xc1>
 10193cf:	c5 e9 ef d2          	vpxor  %xmm2,%xmm2,%xmm2
 10193d3:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10193da:	84 00 00 00 00 00 
 10193e0:	c5 f9 ef 1f          	vpxor  (%rdi),%xmm0,%xmm3
 10193e4:	c5 e1 f6 da          	vpsadbw %xmm2,%xmm3,%xmm3
 10193e8:	c5 e1 d4 c9          	vpaddq %xmm1,%xmm3,%xmm1
 10193ec:	c5 f9 ef 5f 10       	vpxor  0x10(%rdi),%xmm0,%xmm3
 10193f1:	c5 e1 f6 da          	vpsadbw %xmm2,%xmm3,%xmm3
 10193f5:	c5 f9 ef 67 20       	vpxor  0x20(%rdi),%xmm0,%xmm4
 10193fa:	c5 d9 f6 e2          	vpsadbw %xmm2,%xmm4,%xmm4
 10193fe:	c5 d9 d4 db          	vpaddq %xmm3,%xmm4,%xmm3
 1019402:	c5 e1 d4 c9          	vpaddq %xmm1,%xmm3,%xmm1
 1019406:	c5 f9 ef 5f 30       	vpxor  0x30(%rdi),%xmm0,%xmm3
 101940b:	c5 e1 f6 da          	vpsadbw %xmm2,%xmm3,%xmm3
 101940f:	c5 e1 d4 c9          	vpaddq %xmm1,%xmm3,%xmm1
 1019413:	48 83 c7 40          	add    $0x40,%rdi
 1019417:	48 83 c6 c0          	add    $0xffffffffffffffc0,%rsi
 101941b:	48 83 fe 0f          	cmp    $0xf,%rsi
 101941f:	77 bf                	ja     10193e0 <myl_native_bytes_sum_xor+0x80>
 1019421:	c5 f9 70 c1 ee       	vpshufd $0xee,%xmm1,%xmm0
 1019426:	c5 f1 d4 c0          	vpaddq %xmm0,%xmm1,%xmm0
 101942a:	c4 e1 f9 7e c0       	vmovq  %xmm0,%rax
 101942f:	48 85 f6             	test   %rsi,%rsi
 1019432:	0f 84 9a 00 00 00    	je     10194d2 <myl_native_bytes_sum_xor+0x172>
 1019438:	48 89 f1             	mov    %rsi,%rcx
 101943b:	48 83 e1 03          	and    $0x3,%rcx
 101943f:	74 37                	je     1019478 <myl_native_bytes_sum_xor+0x118>
 1019441:	45 31 c0             	xor    %r8d,%r8d
 1019444:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 101944b:	00 00 00 00 00 
 1019450:	46 0f b6 0c 07       	movzbl (%rdi,%r8,1),%r9d
 1019455:	41 30 d1             	xor    %dl,%r9b
 1019458:	45 0f b6 c9          	movzbl %r9b,%r9d
 101945c:	4c 01 c8             	add    %r9,%rax
 101945f:	49 ff c0             	inc    %r8
 1019462:	4c 39 c1             	cmp    %r8,%rcx
 1019465:	75 e9                	jne    1019450 <myl_native_bytes_sum_xor+0xf0>
 1019467:	4c 01 c7             	add    %r8,%rdi
 101946a:	48 89 f1             	mov    %rsi,%rcx
 101946d:	4c 29 c1             	sub    %r8,%rcx
 1019470:	48 83 fe 04          	cmp    $0x4,%rsi
 1019474:	73 0b                	jae    1019481 <myl_native_bytes_sum_xor+0x121>
 1019476:	eb 5a                	jmp    10194d2 <myl_native_bytes_sum_xor+0x172>
 1019478:	48 89 f1             	mov    %rsi,%rcx
 101947b:	48 83 fe 04          	cmp    $0x4,%rsi
 101947f:	72 51                	jb     10194d2 <myl_native_bytes_sum_xor+0x172>
 1019481:	31 f6                	xor    %esi,%esi
 1019483:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 101948a:	84 00 00 00 00 00 
 1019490:	44 0f b6 04 37       	movzbl (%rdi,%rsi,1),%r8d
 1019495:	41 30 d0             	xor    %dl,%r8b
 1019498:	45 0f b6 c0          	movzbl %r8b,%r8d
 101949c:	49 01 c0             	add    %rax,%r8
 101949f:	0f b6 44 37 01       	movzbl 0x1(%rdi,%rsi,1),%eax
 10194a4:	30 d0                	xor    %dl,%al
 10194a6:	0f b6 c0             	movzbl %al,%eax
 10194a9:	44 0f b6 4c 37 02    	movzbl 0x2(%rdi,%rsi,1),%r9d
 10194af:	41 30 d1             	xor    %dl,%r9b
 10194b2:	45 0f b6 c9          	movzbl %r9b,%r9d
 10194b6:	49 01 c1             	add    %rax,%r9
 10194b9:	4d 01 c1             	add    %r8,%r9
 10194bc:	0f b6 44 37 03       	movzbl 0x3(%rdi,%rsi,1),%eax
 10194c1:	30 d0                	xor    %dl,%al
 10194c3:	0f b6 c0             	movzbl %al,%eax
 10194c6:	4c 01 c8             	add    %r9,%rax
 10194c9:	48 83 c6 04          	add    $0x4,%rsi
 10194cd:	48 39 f1             	cmp    %rsi,%rcx
 10194d0:	75 be                	jne    1019490 <myl_native_bytes_sum_xor+0x130>
 10194d2:	5d                   	pop    %rbp
 10194d3:	c3                   	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
