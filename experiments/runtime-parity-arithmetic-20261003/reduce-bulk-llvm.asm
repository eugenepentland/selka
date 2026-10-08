
/home/epentland/.cache/mylang-tmp/runtime-parity-arithmetic-20261003/byte-reduction-llvm:     file format elf64-x86-64


Disassembly of section .text:

000000000100ff80 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad>:
 100ff80:	55                   	push   %rbp
 100ff81:	41 57                	push   %r15
 100ff83:	41 56                	push   %r14
 100ff85:	41 55                	push   %r13
 100ff87:	41 54                	push   %r12
 100ff89:	53                   	push   %rbx
 100ff8a:	48 83 ec 18          	sub    $0x18,%rsp
 100ff8e:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
 100ff93:	4c 8b 4e f0          	mov    -0x10(%rsi),%r9
 100ff97:	49 bd 02 00 00 00 00 	movabs $0x4000000000000002,%r13
 100ff9e:	00 00 40 
 100ffa1:	4d 85 e9             	test   %r13,%r9
 100ffa4:	75 11                	jne    100ffb7 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x37>
 100ffa6:	48 8b 46 e8          	mov    -0x18(%rsi),%rax
 100ffaa:	48 ff c0             	inc    %rax
 100ffad:	0f 84 83 05 00 00    	je     1010536 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x5b6>
 100ffb3:	48 89 46 e8          	mov    %rax,-0x18(%rsi)
 100ffb7:	4c 8b 1e             	mov    (%rsi),%r11
 100ffba:	49 8d 43 f0          	lea    -0x10(%r11),%rax
 100ffbe:	49 b8 f0 ff ff ff ff 	movabs $0xffffffffffffff0,%r8
 100ffc5:	ff ff 0f 
 100ffc8:	4c 39 c0             	cmp    %r8,%rax
 100ffcb:	77 55                	ja     1010022 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0xa2>
 100ffcd:	4c 8b 46 20          	mov    0x20(%rsi),%r8
 100ffd1:	48 81 fa 00 01 00 00 	cmp    $0x100,%rdx
 100ffd8:	0f 93 c3             	setae  %bl
 100ffdb:	49 be 80 80 80 80 80 	movabs $0x80808080808080,%r14
 100ffe2:	80 80 00 
 100ffe5:	4d 39 f3             	cmp    %r14,%r11
 100ffe8:	40 0f 97 c5          	seta   %bpl
 100ffec:	40 08 dd             	or     %bl,%bpl
 100ffef:	75 28                	jne    1010019 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x99>
 100fff1:	48 bb f8 ff ff ff ff 	movabs $0x7ffffffffffffff8,%rbx
 100fff8:	ff ff 7f 
 100fffb:	4d 89 de             	mov    %r11,%r14
 100fffe:	49 c1 e6 08          	shl    $0x8,%r14
 1010002:	4d 89 df             	mov    %r11,%r15
 1010005:	4d 29 f7             	sub    %r14,%r15
 1010008:	4e 8d 34 3b          	lea    (%rbx,%r15,1),%r14
 101000c:	49 83 c6 07          	add    $0x7,%r14
 1010010:	4c 39 f1             	cmp    %r14,%rcx
 1010013:	0f 8e 52 02 00 00    	jle    101026b <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x2eb>
 1010019:	48 89 d3             	mov    %rdx,%rbx
 101001c:	48 c1 fb 3f          	sar    $0x3f,%rbx
 1010020:	eb 39                	jmp    101005b <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0xdb>
 1010022:	4d 85 db             	test   %r11,%r11
 1010025:	0f 8e 9a 01 00 00    	jle    10101c5 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x245>
 101002b:	48 89 d3             	mov    %rdx,%rbx
 101002e:	48 c1 fb 3f          	sar    $0x3f,%rbx
 1010032:	4c 8b 46 20          	mov    0x20(%rsi),%r8
 1010036:	49 83 fb 08          	cmp    $0x8,%r11
 101003a:	73 1f                	jae    101005b <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0xdb>
 101003c:	4c 89 4c 24 10       	mov    %r9,0x10(%rsp)
 1010041:	4d 89 e9             	mov    %r13,%r9
 1010044:	41 bd 01 00 00 00    	mov    $0x1,%r13d
 101004a:	45 31 f6             	xor    %r14d,%r14d
 101004d:	45 31 ff             	xor    %r15d,%r15d
 1010050:	45 31 e4             	xor    %r12d,%r12d
 1010053:	48 89 c8             	mov    %rcx,%rax
 1010056:	e9 13 01 00 00       	jmp    101016e <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x1ee>
 101005b:	4d 89 dc             	mov    %r11,%r12
 101005e:	49 83 e4 f8          	and    $0xfffffffffffffff8,%r12
 1010062:	c4 e1 f9 6e c1       	vmovq  %rcx,%xmm0
 1010067:	c4 e1 f9 6e cb       	vmovq  %rbx,%xmm1
 101006c:	c4 e2 7d 59 d1       	vpbroadcastq %xmm1,%ymm2
 1010071:	c4 e1 f9 6e ca       	vmovq  %rdx,%xmm1
 1010076:	c4 e2 7d 59 e1       	vpbroadcastq %xmm1,%ymm4
 101007b:	c5 dd ef f2          	vpxor  %ymm2,%ymm4,%ymm6
 101007f:	c5 c1 ef ff          	vpxor  %xmm7,%xmm7,%xmm7
 1010083:	31 c0                	xor    %eax,%eax
 1010085:	c4 41 39 ef c0       	vpxor  %xmm8,%xmm8,%xmm8
 101008a:	c4 41 31 ef c9       	vpxor  %xmm9,%xmm9,%xmm9
 101008f:	c5 e1 ef db          	vpxor  %xmm3,%xmm3,%xmm3
 1010093:	c5 d1 ef ed          	vpxor  %xmm5,%xmm5,%xmm5
 1010097:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
 101009b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 10100a0:	c4 42 7d 32 14 00    	vpmovzxbq (%r8,%rax,1),%ymm10
 10100a6:	c4 42 7d 32 5c 00 04 	vpmovzxbq 0x4(%r8,%rax,1),%ymm11
 10100ad:	c5 2d ef e4          	vpxor  %ymm4,%ymm10,%ymm12
 10100b1:	c5 9d d4 c0          	vpaddq %ymm0,%ymm12,%ymm0
 10100b5:	c5 25 ef e4          	vpxor  %ymm4,%ymm11,%ymm12
 10100b9:	c5 9d d4 c9          	vpaddq %ymm1,%ymm12,%ymm1
 10100bd:	c5 2d ef d6          	vpxor  %ymm6,%ymm10,%ymm10
 10100c1:	c5 25 ef de          	vpxor  %ymm6,%ymm11,%ymm11
 10100c5:	c5 2d fb d2          	vpsubq %ymm2,%ymm10,%ymm10
 10100c9:	c5 25 fb da          	vpsubq %ymm2,%ymm11,%ymm11
 10100cd:	c4 63 2d 02 e7 aa    	vpblendd $0xaa,%ymm7,%ymm10,%ymm12
 10100d3:	c5 9d d4 db          	vpaddq %ymm3,%ymm12,%ymm3
 10100d7:	c4 63 25 02 e7 aa    	vpblendd $0xaa,%ymm7,%ymm11,%ymm12
 10100dd:	c5 9d d4 ed          	vpaddq %ymm5,%ymm12,%ymm5
 10100e1:	c4 c1 2d 73 d2 20    	vpsrlq $0x20,%ymm10,%ymm10
 10100e7:	c4 41 2d d4 c0       	vpaddq %ymm8,%ymm10,%ymm8
 10100ec:	c4 c1 2d 73 d3 20    	vpsrlq $0x20,%ymm11,%ymm10
 10100f2:	c4 41 2d d4 c9       	vpaddq %ymm9,%ymm10,%ymm9
 10100f7:	48 83 c0 08          	add    $0x8,%rax
 10100fb:	49 39 c4             	cmp    %rax,%r12
 10100fe:	75 a0                	jne    10100a0 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x120>
 1010100:	c4 c1 35 d4 d0       	vpaddq %ymm8,%ymm9,%ymm2
 1010105:	c4 e3 7d 39 d4 01    	vextracti128 $0x1,%ymm2,%xmm4
 101010b:	c5 e9 d4 d4          	vpaddq %xmm4,%xmm2,%xmm2
 101010f:	c5 f9 70 e2 ee       	vpshufd $0xee,%xmm2,%xmm4
 1010114:	c5 e9 d4 d4          	vpaddq %xmm4,%xmm2,%xmm2
 1010118:	c4 c1 f9 7e d6       	vmovq  %xmm2,%r14
 101011d:	c5 d5 d4 d3          	vpaddq %ymm3,%ymm5,%ymm2
 1010121:	c4 e3 7d 39 d3 01    	vextracti128 $0x1,%ymm2,%xmm3
 1010127:	c5 e9 d4 d3          	vpaddq %xmm3,%xmm2,%xmm2
 101012b:	c5 f9 70 da ee       	vpshufd $0xee,%xmm2,%xmm3
 1010130:	c5 e9 d4 d3          	vpaddq %xmm3,%xmm2,%xmm2
 1010134:	c4 c1 f9 7e d7       	vmovq  %xmm2,%r15
 1010139:	c5 f5 d4 c0          	vpaddq %ymm0,%ymm1,%ymm0
 101013d:	c4 e3 7d 39 c1 01    	vextracti128 $0x1,%ymm0,%xmm1
 1010143:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 1010147:	c5 f9 70 c8 ee       	vpshufd $0xee,%xmm0,%xmm1
 101014c:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 1010150:	c4 e1 f9 7e c0       	vmovq  %xmm0,%rax
 1010155:	4d 39 e3             	cmp    %r12,%r11
 1010158:	75 05                	jne    101015f <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x1df>
 101015a:	4d 89 d8             	mov    %r11,%r8
 101015d:	eb 56                	jmp    10101b5 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x235>
 101015f:	4c 89 4c 24 10       	mov    %r9,0x10(%rsp)
 1010164:	4d 89 e9             	mov    %r13,%r9
 1010167:	4d 89 e5             	mov    %r12,%r13
 101016a:	49 83 cd 01          	or     $0x1,%r13
 101016e:	4d 01 e0             	add    %r12,%r8
 1010171:	4c 89 dd             	mov    %r11,%rbp
 1010174:	4c 29 e5             	sub    %r12,%rbp
 1010177:	45 31 e4             	xor    %r12d,%r12d
 101017a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1010180:	47 0f b6 14 20       	movzbl (%r8,%r12,1),%r10d
 1010185:	49 31 d2             	xor    %rdx,%r10
 1010188:	4c 01 d0             	add    %r10,%rax
 101018b:	49 31 da             	xor    %rbx,%r10
 101018e:	49 29 da             	sub    %rbx,%r10
 1010191:	44 89 d7             	mov    %r10d,%edi
 1010194:	49 01 ff             	add    %rdi,%r15
 1010197:	49 c1 ea 20          	shr    $0x20,%r10
 101019b:	4d 01 d6             	add    %r10,%r14
 101019e:	49 ff c4             	inc    %r12
 10101a1:	4c 39 e5             	cmp    %r12,%rbp
 10101a4:	75 da                	jne    1010180 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x200>
 10101a6:	4f 8d 04 2c          	lea    (%r12,%r13,1),%r8
 10101aa:	49 ff c8             	dec    %r8
 10101ad:	4d 89 cd             	mov    %r9,%r13
 10101b0:	4c 8b 4c 24 10       	mov    0x10(%rsp),%r9
 10101b5:	bf ff ff ff ff       	mov    $0xffffffff,%edi
 10101ba:	49 39 f8             	cmp    %rdi,%r8
 10101bd:	0f 92 c3             	setb   %bl
 10101c0:	45 31 c0             	xor    %r8d,%r8d
 10101c3:	eb 0e                	jmp    10101d3 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x253>
 10101c5:	41 b0 01             	mov    $0x1,%r8b
 10101c8:	45 31 ff             	xor    %r15d,%r15d
 10101cb:	48 89 c8             	mov    %rcx,%rax
 10101ce:	45 31 f6             	xor    %r14d,%r14d
 10101d1:	b3 01                	mov    $0x1,%bl
 10101d3:	48 89 cf             	mov    %rcx,%rdi
 10101d6:	48 f7 df             	neg    %rdi
 10101d9:	48 0f 48 f9          	cmovs  %rcx,%rdi
 10101dd:	49 f7 c6 00 00 00 80 	test   $0xffffffff80000000,%r14
 10101e4:	41 0f 94 c2          	sete   %r10b
 10101e8:	49 c1 e6 20          	shl    $0x20,%r14
 10101ec:	4d 01 fe             	add    %r15,%r14
 10101ef:	4c 01 f7             	add    %r14,%rdi
 10101f2:	41 20 da             	and    %bl,%r10b
 10101f5:	4c 09 ff             	or     %r15,%rdi
 10101f8:	4c 09 f7             	or     %r14,%rdi
 10101fb:	40 0f 99 c7          	setns  %dil
 10101ff:	44 20 d7             	and    %r10b,%dil
 1010202:	41 08 f8             	or     %dil,%r8b
 1010205:	40 84 ff             	test   %dil,%dil
 1010208:	48 0f 44 c1          	cmove  %rcx,%rax
 101020c:	45 84 c0             	test   %r8b,%r8b
 101020f:	75 2b                	jne    101023c <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x2bc>
 1010211:	48 8b 5e 20          	mov    0x20(%rsi),%rbx
 1010215:	45 31 f6             	xor    %r14d,%r14d
 1010218:	48 89 c8             	mov    %rcx,%rax
 101021b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1010220:	46 0f b6 04 33       	movzbl (%rbx,%r14,1),%r8d
 1010225:	49 31 d0             	xor    %rdx,%r8
 1010228:	4c 01 c0             	add    %r8,%rax
 101022b:	0f 80 1b 03 00 00    	jo     101054c <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x5cc>
 1010231:	49 ff c6             	inc    %r14
 1010234:	48 89 c1             	mov    %rax,%rcx
 1010237:	4d 39 f3             	cmp    %r14,%r11
 101023a:	75 e4                	jne    1010220 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x2a0>
 101023c:	4d 85 e9             	test   %r13,%r9
 101023f:	75 18                	jne    1010259 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x2d9>
 1010241:	48 8b 4e e8          	mov    -0x18(%rsi),%rcx
 1010245:	48 ff c9             	dec    %rcx
 1010248:	75 0b                	jne    1010255 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x2d5>
 101024a:	48 83 7e e0 00       	cmpq   $0x0,-0x20(%rsi)
 101024f:	0f 84 28 01 00 00    	je     101037d <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x3fd>
 1010255:	48 89 4e e8          	mov    %rcx,-0x18(%rsi)
 1010259:	48 83 c4 18          	add    $0x18,%rsp
 101025d:	5b                   	pop    %rbx
 101025e:	41 5c                	pop    %r12
 1010260:	41 5d                	pop    %r13
 1010262:	41 5e                	pop    %r14
 1010264:	41 5f                	pop    %r15
 1010266:	5d                   	pop    %rbp
 1010267:	c5 f8 77             	vzeroupper
 101026a:	c3                   	ret
 101026b:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 101026f:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1010274:	89 c5                	mov    %eax,%ebp
 1010276:	f7 d5                	not    %ebp
 1010278:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
 101027c:	40 f6 c5 30          	test   $0x30,%bpl
 1010280:	75 06                	jne    1010288 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x308>
 1010282:	c5 e9 ef d2          	vpxor  %xmm2,%xmm2,%xmm2
 1010286:	eb 58                	jmp    10102e0 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x360>
 1010288:	41 89 c6             	mov    %eax,%r14d
 101028b:	41 c1 ee 04          	shr    $0x4,%r14d
 101028f:	41 ff c6             	inc    %r14d
 1010292:	41 83 e6 03          	and    $0x3,%r14d
 1010296:	c5 e1 ef db          	vpxor  %xmm3,%xmm3,%xmm3
 101029a:	4d 89 f7             	mov    %r14,%r15
 101029d:	4d 89 c4             	mov    %r8,%r12
 10102a0:	c5 e9 ef d2          	vpxor  %xmm2,%xmm2,%xmm2
 10102a4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10102ab:	00 00 00 00 00 
 10102b0:	c4 c1 79 ef 24 24    	vpxor  (%r12),%xmm0,%xmm4
 10102b6:	c5 d9 f6 e3          	vpsadbw %xmm3,%xmm4,%xmm4
 10102ba:	c5 d9 d4 d2          	vpaddq %xmm2,%xmm4,%xmm2
 10102be:	49 83 c4 10          	add    $0x10,%r12
 10102c2:	49 ff cf             	dec    %r15
 10102c5:	75 e9                	jne    10102b0 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x330>
 10102c7:	41 c1 e6 04          	shl    $0x4,%r14d
 10102cb:	4d 01 f0             	add    %r14,%r8
 10102ce:	4d 29 f3             	sub    %r14,%r11
 10102d1:	48 83 f8 30          	cmp    $0x30,%rax
 10102d5:	72 4e                	jb     1010325 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x3a5>
 10102d7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10102de:	00 00 
 10102e0:	c4 c1 79 ef 18       	vpxor  (%r8),%xmm0,%xmm3
 10102e5:	c5 e1 f6 d9          	vpsadbw %xmm1,%xmm3,%xmm3
 10102e9:	c5 e1 d4 d2          	vpaddq %xmm2,%xmm3,%xmm2
 10102ed:	c4 c1 79 ef 58 10    	vpxor  0x10(%r8),%xmm0,%xmm3
 10102f3:	c5 e1 f6 d9          	vpsadbw %xmm1,%xmm3,%xmm3
 10102f7:	c4 c1 79 ef 60 20    	vpxor  0x20(%r8),%xmm0,%xmm4
 10102fd:	c5 d9 f6 e1          	vpsadbw %xmm1,%xmm4,%xmm4
 1010301:	c5 d9 d4 db          	vpaddq %xmm3,%xmm4,%xmm3
 1010305:	c5 e1 d4 d2          	vpaddq %xmm2,%xmm3,%xmm2
 1010309:	c4 c1 79 ef 58 30    	vpxor  0x30(%r8),%xmm0,%xmm3
 101030f:	c5 e1 f6 d9          	vpsadbw %xmm1,%xmm3,%xmm3
 1010313:	c5 e1 d4 d2          	vpaddq %xmm2,%xmm3,%xmm2
 1010317:	49 83 c0 40          	add    $0x40,%r8
 101031b:	49 83 c3 c0          	add    $0xffffffffffffffc0,%r11
 101031f:	49 83 fb 0f          	cmp    $0xf,%r11
 1010323:	77 bb                	ja     10102e0 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x360>
 1010325:	c5 f9 70 c2 ee       	vpshufd $0xee,%xmm2,%xmm0
 101032a:	c5 e9 d4 c0          	vpaddq %xmm0,%xmm2,%xmm0
 101032e:	c4 e1 f9 7e c0       	vmovq  %xmm0,%rax
 1010333:	4d 85 db             	test   %r11,%r11
 1010336:	0f 84 e9 01 00 00    	je     1010525 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x5a5>
 101033c:	4d 89 dc             	mov    %r11,%r12
 101033f:	49 83 e4 03          	and    $0x3,%r12
 1010343:	74 62                	je     10103a7 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x427>
 1010345:	45 31 f6             	xor    %r14d,%r14d
 1010348:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 101034f:	00 
 1010350:	43 0f b6 2c 30       	movzbl (%r8,%r14,1),%ebp
 1010355:	40 30 d5             	xor    %dl,%bpl
 1010358:	44 0f b6 fd          	movzbl %bpl,%r15d
 101035c:	4c 01 f8             	add    %r15,%rax
 101035f:	49 ff c6             	inc    %r14
 1010362:	4d 39 f4             	cmp    %r14,%r12
 1010365:	75 e9                	jne    1010350 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x3d0>
 1010367:	4d 89 de             	mov    %r11,%r14
 101036a:	49 83 e6 fc          	and    $0xfffffffffffffffc,%r14
 101036e:	4f 8d 3c 20          	lea    (%r8,%r12,1),%r15
 1010372:	49 83 fb 04          	cmp    $0x4,%r11
 1010376:	73 3f                	jae    10103b7 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x437>
 1010378:	e9 a8 01 00 00       	jmp    1010525 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x5a5>
 101037d:	48 8b 5c 24 08       	mov    0x8(%rsp),%rbx
 1010382:	48 81 c3 58 02 00 00 	add    $0x258,%rbx
 1010389:	48 89 df             	mov    %rbx,%rdi
 101038c:	49 89 c6             	mov    %rax,%r14
 101038f:	c5 f8 77             	vzeroupper
 1010392:	e8 79 7d 00 00       	call   1018110 <myl_rc_hold_edge_release>
 1010397:	48 89 df             	mov    %rbx,%rdi
 101039a:	e8 01 ad 00 00       	call   101b0a0 <myl_rc_drain>
 101039f:	4c 89 f0             	mov    %r14,%rax
 10103a2:	e9 b2 fe ff ff       	jmp    1010259 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x2d9>
 10103a7:	4d 89 c7             	mov    %r8,%r15
 10103aa:	4d 89 de             	mov    %r11,%r14
 10103ad:	49 83 fb 04          	cmp    $0x4,%r11
 10103b1:	0f 82 6e 01 00 00    	jb     1010525 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x5a5>
 10103b7:	4d 8d 5e fc          	lea    -0x4(%r14),%r11
 10103bb:	49 83 fb 1c          	cmp    $0x1c,%r11
 10103bf:	0f 82 2b 01 00 00    	jb     10104f0 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x570>
 10103c5:	4c 89 ef             	mov    %r13,%rdi
 10103c8:	49 c1 eb 02          	shr    $0x2,%r11
 10103cc:	49 ff c3             	inc    %r11
 10103cf:	4c 21 db             	and    %r11,%rbx
 10103d2:	4c 8d 2c 9d 00 00 00 	lea    0x0(,%rbx,4),%r13
 10103d9:	00 
 10103da:	4d 8d 3c 9f          	lea    (%r15,%rbx,4),%r15
 10103de:	4d 29 ee             	sub    %r13,%r14
 10103e1:	c4 e1 f9 6e e8       	vmovq  %rax,%xmm5
 10103e6:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 10103ea:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10103ef:	4b 8d 04 04          	lea    (%r12,%r8,1),%rax
 10103f3:	48 83 c0 10          	add    $0x10,%rax
 10103f7:	c5 c9 ef f6          	vpxor  %xmm6,%xmm6,%xmm6
 10103fb:	45 31 c0             	xor    %r8d,%r8d
 10103fe:	c5 f9 6e 0d 2a 15 ff 	vmovd  -0xead6(%rip),%xmm1        # 1001930 <__abi_tag+0x1634>
 1010405:	ff 
 1010406:	c5 f9 6e 15 42 15 ff 	vmovd  -0xeabe(%rip),%xmm2        # 1001950 <__abi_tag+0x1654>
 101040d:	ff 
 101040e:	c5 f9 6e 1d 0a 15 ff 	vmovd  -0xeaf6(%rip),%xmm3        # 1001920 <__abi_tag+0x1624>
 1010415:	ff 
 1010416:	c5 f9 6e 25 c2 14 ff 	vmovd  -0xeb3e(%rip),%xmm4        # 10018e0 <__abi_tag+0x15e4>
 101041d:	ff 
 101041e:	66 90                	xchg   %ax,%ax
 1010420:	c4 a1 7a 6f 7c 80 f0 	vmovdqu -0x10(%rax,%r8,4),%xmm7
 1010427:	c4 21 7a 6f 04 80    	vmovdqu (%rax,%r8,4),%xmm8
 101042d:	c4 62 41 00 c9       	vpshufb %xmm1,%xmm7,%xmm9
 1010432:	c4 62 41 00 d2       	vpshufb %xmm2,%xmm7,%xmm10
 1010437:	c4 62 41 00 db       	vpshufb %xmm3,%xmm7,%xmm11
 101043c:	c4 e2 41 00 fc       	vpshufb %xmm4,%xmm7,%xmm7
 1010441:	c4 62 39 00 e1       	vpshufb %xmm1,%xmm8,%xmm12
 1010446:	c4 62 39 00 ea       	vpshufb %xmm2,%xmm8,%xmm13
 101044b:	c4 62 39 00 f3       	vpshufb %xmm3,%xmm8,%xmm14
 1010450:	c4 62 39 00 c4       	vpshufb %xmm4,%xmm8,%xmm8
 1010455:	c5 31 ef c8          	vpxor  %xmm0,%xmm9,%xmm9
 1010459:	c5 19 ef e0          	vpxor  %xmm0,%xmm12,%xmm12
 101045d:	c4 42 7d 32 c9       	vpmovzxbq %xmm9,%ymm9
 1010462:	c5 b5 d4 ed          	vpaddq %ymm5,%ymm9,%ymm5
 1010466:	c4 42 7d 32 cc       	vpmovzxbq %xmm12,%ymm9
 101046b:	c5 b5 d4 f6          	vpaddq %ymm6,%ymm9,%ymm6
 101046f:	c5 29 ef c8          	vpxor  %xmm0,%xmm10,%xmm9
 1010473:	c5 11 ef d0          	vpxor  %xmm0,%xmm13,%xmm10
 1010477:	c4 42 7d 32 c9       	vpmovzxbq %xmm9,%ymm9
 101047c:	c4 42 7d 32 d2       	vpmovzxbq %xmm10,%ymm10
 1010481:	c5 21 ef d8          	vpxor  %xmm0,%xmm11,%xmm11
 1010485:	c5 09 ef e0          	vpxor  %xmm0,%xmm14,%xmm12
 1010489:	c4 42 7d 32 db       	vpmovzxbq %xmm11,%ymm11
 101048e:	c4 41 35 d4 cb       	vpaddq %ymm11,%ymm9,%ymm9
 1010493:	c5 b5 d4 ed          	vpaddq %ymm5,%ymm9,%ymm5
 1010497:	c4 42 7d 32 cc       	vpmovzxbq %xmm12,%ymm9
 101049c:	c4 41 2d d4 c9       	vpaddq %ymm9,%ymm10,%ymm9
 10104a1:	c5 b5 d4 f6          	vpaddq %ymm6,%ymm9,%ymm6
 10104a5:	c5 c1 ef f8          	vpxor  %xmm0,%xmm7,%xmm7
 10104a9:	c5 39 ef c0          	vpxor  %xmm0,%xmm8,%xmm8
 10104ad:	c4 e2 7d 32 ff       	vpmovzxbq %xmm7,%ymm7
 10104b2:	c5 d5 d4 ef          	vpaddq %ymm7,%ymm5,%ymm5
 10104b6:	c4 c2 7d 32 f8       	vpmovzxbq %xmm8,%ymm7
 10104bb:	c5 cd d4 f7          	vpaddq %ymm7,%ymm6,%ymm6
 10104bf:	49 83 c0 08          	add    $0x8,%r8
 10104c3:	4c 39 c3             	cmp    %r8,%rbx
 10104c6:	0f 85 54 ff ff ff    	jne    1010420 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x4a0>
 10104cc:	c5 cd d4 c5          	vpaddq %ymm5,%ymm6,%ymm0
 10104d0:	c4 e3 7d 39 c1 01    	vextracti128 $0x1,%ymm0,%xmm1
 10104d6:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 10104da:	c5 f9 70 c8 ee       	vpshufd $0xee,%xmm0,%xmm1
 10104df:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 10104e3:	c4 e1 f9 7e c0       	vmovq  %xmm0,%rax
 10104e8:	49 39 db             	cmp    %rbx,%r11
 10104eb:	49 89 fd             	mov    %rdi,%r13
 10104ee:	74 35                	je     1010525 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x5a5>
 10104f0:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 10104f4:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10104f9:	31 d2                	xor    %edx,%edx
 10104fb:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
 10104ff:	90                   	nop
 1010500:	c4 c1 79 6e 14 17    	vmovd  (%r15,%rdx,1),%xmm2
 1010506:	c5 e9 ef d0          	vpxor  %xmm0,%xmm2,%xmm2
 101050a:	c4 e3 71 02 d2 01    	vpblendd $0x1,%xmm2,%xmm1,%xmm2
 1010510:	c5 e9 f6 d1          	vpsadbw %xmm1,%xmm2,%xmm2
 1010514:	c4 c1 f9 7e d0       	vmovq  %xmm2,%r8
 1010519:	4c 01 c0             	add    %r8,%rax
 101051c:	48 83 c2 04          	add    $0x4,%rdx
 1010520:	49 39 d6             	cmp    %rdx,%r14
 1010523:	75 db                	jne    1010500 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x580>
 1010525:	48 01 c8             	add    %rcx,%rax
 1010528:	4d 85 e9             	test   %r13,%r9
 101052b:	0f 85 28 fd ff ff    	jne    1010259 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x2d9>
 1010531:	e9 0b fd ff ff       	jmp    1010241 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x2c1>
 1010536:	be cb 3f 00 01       	mov    $0x1003fcb,%esi
 101053b:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1010540:	e8 f8 37 00 00       	call   1013d3d <fail>
 1010545:	31 c0                	xor    %eax,%eax
 1010547:	e9 0d fd ff ff       	jmp    1010259 <myl_f_4c7e98bfa0c750beb52cf2ddf452297d55681dc9efa8e9725d4334e981ae61ad+0x2d9>
 101054c:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1010551:	48 89 ce             	mov    %rcx,%rsi
 1010554:	4c 89 c2             	mov    %r8,%rdx
 1010557:	c5 f8 77             	vzeroupper
 101055a:	e8 21 3f 00 00       	call   1014480 <myl_qbe_fail_overflow_op>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
