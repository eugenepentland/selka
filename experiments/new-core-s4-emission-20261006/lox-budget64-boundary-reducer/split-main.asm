
experiments/new-core-s4-emission-20261006/paired-budget64-01/split-lox_eval:     file format elf64-x86-64


Disassembly of section .text:

0000000001032da0 <my.app::main>:
 1032da0:	push   %rbp
 1032da1:	push   %r15
 1032da3:	push   %r14
 1032da5:	push   %r13
 1032da7:	push   %r12
 1032da9:	push   %rbx
 1032daa:	sub    $0x58,%rsp
 1032dae:	mov    $0x2,%ebx
 1032db3:	cmpq   $0x3,0x8(%rdi)
 1032db8:	jne    1033e7c <my.app::main+0x10dc>
 1032dbe:	mov    %rsi,%r15
 1032dc1:	mov    %rdi,%r14
 1032dc4:	mov    %rdx,0x30(%rsp)
 1032dc9:	mov    0x20(%rdi),%rdi
 1032dcd:	call   1034480 <my.workload::parse_number>
 1032dd2:	mov    %rax,(%rsp)
 1032dd6:	mov    0x8(%r14),%rdx
 1032dda:	cmp    $0x1,%rdx
 1032dde:	jbe    1034423 <my.app::main+0x1683>
 1032de4:	mov    0x28(%r14),%rdi
 1032de8:	call   1034480 <my.workload::parse_number>
 1032ded:	mov    0x8(%r14),%rdx
 1032df1:	cmp    $0x2,%rdx
 1032df5:	jbe    1034434 <my.app::main+0x1694>
 1032dfb:	mov    %rax,%r12
 1032dfe:	mov    0x30(%r14),%rdi
 1032e02:	call   1034480 <my.workload::parse_number>
 1032e07:	cmpq   $0x2,(%rsp)
 1032e0c:	setl   %dl
 1032e0f:	test   %r12,%r12
 1032e12:	setle  %cl
 1032e15:	or     %dl,%cl
 1032e17:	mov    %rax,0x20(%rsp)
 1032e1c:	add    $0xfffffffffff0bdbf,%rax
 1032e22:	cmp    $0xfffffffffff0bdc0,%rax
 1032e28:	setb   %al
 1032e2b:	or     %cl,%al
 1032e2d:	jne    1033e7c <my.app::main+0x10dc>
 1032e33:	lea    0x27da6(%rip),%rcx        # 105abe0 <myl_core_free_lists>
 1032e3a:	mov    0xa0(%rcx),%rax
 1032e41:	test   %rax,%rax
 1032e44:	mov    %r12,0x38(%rsp)
 1032e49:	je     1033eff <my.app::main+0x115f>
 1032e4f:	mov    (%rax),%rdx
 1032e52:	mov    %rdx,0xa0(%rcx)
 1032e59:	vmovaps -0x2f7c1(%rip),%ymm0        # 10036a0 <core_io_raw_layout+0x120>
 1032e61:	vmovups %ymm0,(%rax)
 1032e65:	mov    $0x26,%ecx
 1032e6a:	xor    %esi,%esi
 1032e6c:	mov    %rsi,%rdx
 1032e6f:	shl    $0x4,%rdx
 1032e73:	inc    %rsi
 1032e76:	vxorps %xmm0,%xmm0,%xmm0
 1032e7a:	vmovups %xmm0,0x20(%rax,%rdx,1)
 1032e80:	mov    %rsi,0x8(%rax)
 1032e84:	cmp    %rcx,%rsi
 1032e87:	jae    1033f39 <my.app::main+0x1199>
 1032e8d:	mov    %rsi,%rdx
 1032e90:	shl    $0x4,%rdx
 1032e94:	movq   $0x4,0x20(%rax,%rdx,1)
 1032e9d:	movq   $0x0,0x28(%rax,%rdx,1)
 1032ea6:	inc    %rsi
 1032ea9:	mov    %rsi,0x8(%rax)
 1032ead:	cmp    %rcx,%rsi
 1032eb0:	jae    1033f56 <my.app::main+0x11b6>
 1032eb6:	mov    %rsi,%rdx
 1032eb9:	shl    $0x4,%rdx
 1032ebd:	movq   $0x2,0x20(%rax,%rdx,1)
 1032ec6:	movq   $0x0,0x28(%rax,%rdx,1)
 1032ecf:	inc    %rsi
 1032ed2:	mov    %rsi,0x8(%rax)
 1032ed6:	cmp    %rcx,%rsi
 1032ed9:	jae    1033f73 <my.app::main+0x11d3>
 1032edf:	mov    %rsi,%rdx
 1032ee2:	shl    $0x4,%rdx
 1032ee6:	movq   $0x4,0x20(%rax,%rdx,1)
 1032eef:	movq   $0x1,0x28(%rax,%rdx,1)
 1032ef8:	inc    %rsi
 1032efb:	mov    %rsi,0x8(%rax)
 1032eff:	cmp    %rcx,%rsi
 1032f02:	jae    1033f90 <my.app::main+0x11f0>
 1032f08:	mov    %rsi,%rdx
 1032f0b:	shl    $0x4,%rdx
 1032f0f:	movq   $0x3,0x20(%rax,%rdx,1)
 1032f18:	movq   $0x1,0x28(%rax,%rdx,1)
 1032f21:	inc    %rsi
 1032f24:	mov    %rsi,0x8(%rax)
 1032f28:	cmp    %rcx,%rsi
 1032f2b:	jae    1033fad <my.app::main+0x120d>
 1032f31:	mov    %rsi,%rdx
 1032f34:	shl    $0x4,%rdx
 1032f38:	movq   $0x1,0x20(%rax,%rdx,1)
 1032f41:	movq   $0x0,0x28(%rax,%rdx,1)
 1032f4a:	inc    %rsi
 1032f4d:	mov    %rsi,0x8(%rax)
 1032f51:	cmp    %rcx,%rsi
 1032f54:	jae    1033fca <my.app::main+0x122a>
 1032f5a:	mov    %rsi,%rdx
 1032f5d:	shl    $0x4,%rdx
 1032f61:	movq   $0x8,0x20(%rax,%rdx,1)
 1032f6a:	movq   $0x0,0x28(%rax,%rdx,1)
 1032f73:	inc    %rsi
 1032f76:	mov    %rsi,0x8(%rax)
 1032f7a:	cmp    %rcx,%rsi
 1032f7d:	jae    1033fe7 <my.app::main+0x1247>
 1032f83:	mov    %rsi,%rdx
 1032f86:	shl    $0x4,%rdx
 1032f8a:	movq   $0xa,0x20(%rax,%rdx,1)
 1032f93:	movq   $0x1d,0x28(%rax,%rdx,1)
 1032f9c:	inc    %rsi
 1032f9f:	mov    %rsi,0x8(%rax)
 1032fa3:	cmp    %rcx,%rsi
 1032fa6:	jae    1034004 <my.app::main+0x1264>
 1032fac:	mov    %rsi,%rdx
 1032faf:	shl    $0x4,%rdx
 1032fb3:	movq   $0x3,0x20(%rax,%rdx,1)
 1032fbc:	movq   $0x1,0x28(%rax,%rdx,1)
 1032fc5:	inc    %rsi
 1032fc8:	mov    %rsi,0x8(%rax)
 1032fcc:	cmp    %rcx,%rsi
 1032fcf:	jae    1034021 <my.app::main+0x1281>
 1032fd5:	mov    %rsi,%rdx
 1032fd8:	shl    $0x4,%rdx
 1032fdc:	movq   $0x2,0x20(%rax,%rdx,1)
 1032fe5:	movq   $0x2,0x28(%rax,%rdx,1)
 1032fee:	inc    %rsi
 1032ff1:	mov    %rsi,0x8(%rax)
 1032ff5:	cmp    %rcx,%rsi
 1032ff8:	jae    103403e <my.app::main+0x129e>
 1032ffe:	mov    %rsi,%rdx
 1033001:	shl    $0x4,%rdx
 1033005:	movq   $0x7,0x20(%rax,%rdx,1)
 103300e:	movq   $0x0,0x28(%rax,%rdx,1)
 1033017:	inc    %rsi
 103301a:	mov    %rsi,0x8(%rax)
 103301e:	cmp    %rcx,%rsi
 1033021:	jae    103405b <my.app::main+0x12bb>
 1033027:	mov    %rsi,%rdx
 103302a:	shl    $0x4,%rdx
 103302e:	movq   $0x2,0x20(%rax,%rdx,1)
 1033037:	movq   $0x0,0x28(%rax,%rdx,1)
 1033040:	inc    %rsi
 1033043:	mov    %rsi,0x8(%rax)
 1033047:	cmp    %rcx,%rsi
 103304a:	jae    1034078 <my.app::main+0x12d8>
 1033050:	mov    %rsi,%rdx
 1033053:	shl    $0x4,%rdx
 1033057:	movq   $0x9,0x20(%rax,%rdx,1)
 1033060:	movq   $0x0,0x28(%rax,%rdx,1)
 1033069:	inc    %rsi
 103306c:	mov    %rsi,0x8(%rax)
 1033070:	cmp    %rcx,%rsi
 1033073:	jae    1034095 <my.app::main+0x12f5>
 1033079:	mov    %rsi,%rdx
 103307c:	shl    $0x4,%rdx
 1033080:	movq   $0xa,0x20(%rax,%rdx,1)
 1033089:	movq   $0x12,0x28(%rax,%rdx,1)
 1033092:	inc    %rsi
 1033095:	mov    %rsi,0x8(%rax)
 1033099:	cmp    %rcx,%rsi
 103309c:	jae    10340b2 <my.app::main+0x1312>
 10330a2:	mov    %rsi,%rdx
 10330a5:	shl    $0x4,%rdx
 10330a9:	movq   $0x3,0x20(%rax,%rdx,1)
 10330b2:	movq   $0x0,0x28(%rax,%rdx,1)
 10330bb:	inc    %rsi
 10330be:	mov    %rsi,0x8(%rax)
 10330c2:	cmp    %rcx,%rsi
 10330c5:	jae    10340cf <my.app::main+0x132f>
 10330cb:	mov    %rsi,%rdx
 10330ce:	shl    $0x4,%rdx
 10330d2:	movq   $0xc,0x20(%rax,%rdx,1)
 10330db:	movq   $0x1f,0x28(%rax,%rdx,1)
 10330e4:	inc    %rsi
 10330e7:	mov    %rsi,0x8(%rax)
 10330eb:	cmp    %rcx,%rsi
 10330ee:	jae    10340ec <my.app::main+0x134c>
 10330f4:	mov    %rsi,%rdx
 10330f7:	shl    $0x4,%rdx
 10330fb:	movq   $0x4,0x20(%rax,%rdx,1)
 1033104:	movq   $0x0,0x28(%rax,%rdx,1)
 103310d:	inc    %rsi
 1033110:	mov    %rsi,0x8(%rax)
 1033114:	cmp    %rcx,%rsi
 1033117:	jae    1034109 <my.app::main+0x1369>
 103311d:	mov    %rsi,%rdx
 1033120:	shl    $0x4,%rdx
 1033124:	movq   $0xb,0x20(%rax,%rdx,1)
 103312d:	movq   $0x18,0x28(%rax,%rdx,1)
 1033136:	inc    %rsi
 1033139:	mov    %rsi,0x8(%rax)
 103313d:	cmp    %rcx,%rsi
 1033140:	jae    1034126 <my.app::main+0x1386>
 1033146:	mov    %rsi,%rdx
 1033149:	shl    $0x4,%rdx
 103314d:	movq   $0x3,0x20(%rax,%rdx,1)
 1033156:	movq   $0x0,0x28(%rax,%rdx,1)
 103315f:	inc    %rsi
 1033162:	mov    %rsi,0x8(%rax)
 1033166:	cmp    %rcx,%rsi
 1033169:	jae    1034143 <my.app::main+0x13a3>
 103316f:	mov    %rsi,%rdx
 1033172:	shl    $0x4,%rdx
 1033176:	movq   $0x3,0x20(%rax,%rdx,1)
 103317f:	movq   $0x1,0x28(%rax,%rdx,1)
 1033188:	inc    %rsi
 103318b:	mov    %rsi,0x8(%rax)
 103318f:	cmp    %rcx,%rsi
 1033192:	jae    1034160 <my.app::main+0x13c0>
 1033198:	mov    %rsi,%rdx
 103319b:	shl    $0x4,%rdx
 103319f:	movq   $0x5,0x20(%rax,%rdx,1)
 10331a8:	movq   $0x0,0x28(%rax,%rdx,1)
 10331b1:	inc    %rsi
 10331b4:	mov    %rsi,0x8(%rax)
 10331b8:	cmp    %rcx,%rsi
 10331bb:	jae    103417d <my.app::main+0x13dd>
 10331c1:	mov    %rsi,%rdx
 10331c4:	shl    $0x4,%rdx
 10331c8:	movq   $0x2,0x20(%rax,%rdx,1)
 10331d1:	movq   $0xf4243,0x28(%rax,%rdx,1)
 10331da:	inc    %rsi
 10331dd:	mov    %rsi,0x8(%rax)
 10331e1:	cmp    %rcx,%rsi
 10331e4:	jae    103419a <my.app::main+0x13fa>
 10331ea:	mov    %rsi,%rdx
 10331ed:	shl    $0x4,%rdx
 10331f1:	movq   $0x7,0x20(%rax,%rdx,1)
 10331fa:	movq   $0x0,0x28(%rax,%rdx,1)
 1033203:	inc    %rsi
 1033206:	mov    %rsi,0x8(%rax)
 103320a:	cmp    %rcx,%rsi
 103320d:	jae    10341b7 <my.app::main+0x1417>
 1033213:	mov    %rsi,%rdx
 1033216:	shl    $0x4,%rdx
 103321a:	movq   $0x4,0x20(%rax,%rdx,1)
 1033223:	movq   $0x0,0x28(%rax,%rdx,1)
 103322c:	inc    %rsi
 103322f:	mov    %rsi,0x8(%rax)
 1033233:	cmp    %rcx,%rsi
 1033236:	jae    10341d4 <my.app::main+0x1434>
 103323c:	mov    %rsi,%rdx
 103323f:	shl    $0x4,%rdx
 1033243:	movq   $0x3,0x20(%rax,%rdx,1)
 103324c:	movq   $0x1,0x28(%rax,%rdx,1)
 1033255:	inc    %rsi
 1033258:	mov    %rsi,0x8(%rax)
 103325c:	cmp    %rcx,%rsi
 103325f:	jae    10341f1 <my.app::main+0x1451>
 1033265:	mov    %rsi,%rdx
 1033268:	shl    $0x4,%rdx
 103326c:	movq   $0x2,0x20(%rax,%rdx,1)
 1033275:	movq   $0x1,0x28(%rax,%rdx,1)
 103327e:	inc    %rsi
 1033281:	mov    %rsi,0x8(%rax)
 1033285:	cmp    %rcx,%rsi
 1033288:	jae    103420e <my.app::main+0x146e>
 103328e:	mov    %rsi,%rdx
 1033291:	shl    $0x4,%rdx
 1033295:	movq   $0x5,0x20(%rax,%rdx,1)
 103329e:	movq   $0x0,0x28(%rax,%rdx,1)
 10332a7:	inc    %rsi
 10332aa:	mov    %rsi,0x8(%rax)
 10332ae:	cmp    %rcx,%rsi
 10332b1:	jae    103422b <my.app::main+0x148b>
 10332b7:	mov    %rsi,%rdx
 10332ba:	shl    $0x4,%rdx
 10332be:	movq   $0x4,0x20(%rax,%rdx,1)
 10332c7:	movq   $0x1,0x28(%rax,%rdx,1)
 10332d0:	inc    %rsi
 10332d3:	mov    %rsi,0x8(%rax)
 10332d7:	cmp    %rcx,%rsi
 10332da:	jae    1034248 <my.app::main+0x14a8>
 10332e0:	mov    %rsi,%rdx
 10332e3:	shl    $0x4,%rdx
 10332e7:	movq   $0xb,0x20(%rax,%rdx,1)
 10332f0:	movq   $0x4,0x28(%rax,%rdx,1)
 10332f9:	inc    %rsi
 10332fc:	mov    %rsi,0x8(%rax)
 1033300:	cmp    %rcx,%rsi
 1033303:	jae    1034265 <my.app::main+0x14c5>
 1033309:	mov    %rsi,%rdx
 103330c:	shl    $0x4,%rdx
 1033310:	movq   $0x3,0x20(%rax,%rdx,1)
 1033319:	movq   $0x0,0x28(%rax,%rdx,1)
 1033322:	inc    %rsi
 1033325:	mov    %rsi,0x8(%rax)
 1033329:	cmp    %rcx,%rsi
 103332c:	jae    1034282 <my.app::main+0x14e2>
 1033332:	mov    %rsi,%rdx
 1033335:	shl    $0x4,%rdx
 1033339:	movq   $0xe,0x20(%rax,%rdx,1)
 1033342:	movq   $0x0,0x28(%rax,%rdx,1)
 103334b:	inc    %rsi
 103334e:	mov    %rsi,0x8(%rax)
 1033352:	cmp    %rcx,%rsi
 1033355:	jae    103429f <my.app::main+0x14ff>
 103335b:	mov    %rsi,%rdx
 103335e:	shl    $0x4,%rdx
 1033362:	movq   $0x2,0x20(%rax,%rdx,1)
 103336b:	movq   $0x3,0x28(%rax,%rdx,1)
 1033374:	inc    %rsi
 1033377:	mov    %rsi,0x8(%rax)
 103337b:	cmp    %rcx,%rsi
 103337e:	jae    10342bc <my.app::main+0x151c>
 1033384:	mov    %rsi,%rdx
 1033387:	shl    $0x4,%rdx
 103338b:	movq   $0x6,0x20(%rax,%rdx,1)
 1033394:	movq   $0x0,0x28(%rax,%rdx,1)
 103339d:	inc    %rsi
 10333a0:	mov    %rsi,0x8(%rax)
 10333a4:	cmp    %rcx,%rsi
 10333a7:	jae    10342d9 <my.app::main+0x1539>
 10333ad:	mov    %rsi,%rdx
 10333b0:	shl    $0x4,%rdx
 10333b4:	movq   $0x2,0x20(%rax,%rdx,1)
 10333bd:	movq   $0x7,0x28(%rax,%rdx,1)
 10333c6:	inc    %rsi
 10333c9:	mov    %rsi,0x8(%rax)
 10333cd:	cmp    %rcx,%rsi
 10333d0:	jae    10342f6 <my.app::main+0x1556>
 10333d6:	mov    %rsi,%rdx
 10333d9:	shl    $0x4,%rdx
 10333dd:	movq   $0x5,0x20(%rax,%rdx,1)
 10333e6:	movq   $0x0,0x28(%rax,%rdx,1)
 10333ef:	inc    %rsi
 10333f2:	mov    %rsi,0x8(%rax)
 10333f6:	cmp    %rcx,%rsi
 10333f9:	jae    1034313 <my.app::main+0x1573>
 10333ff:	mov    %rsi,%rdx
 1033402:	shl    $0x4,%rdx
 1033406:	movq   $0x2,0x20(%rax,%rdx,1)
 103340f:	movq   $0xf4243,0x28(%rax,%rdx,1)
 1033418:	inc    %rsi
 103341b:	mov    %rsi,0x8(%rax)
 103341f:	cmp    %rcx,%rsi
 1033422:	jae    1034330 <my.app::main+0x1590>
 1033428:	mov    %rsi,%rdx
 103342b:	shl    $0x4,%rdx
 103342f:	movq   $0x7,0x20(%rax,%rdx,1)
 1033438:	movq   $0x0,0x28(%rax,%rdx,1)
 1033441:	inc    %rsi
 1033444:	mov    %rsi,0x8(%rax)
 1033448:	cmp    %rcx,%rsi
 103344b:	mov    %r15,0x18(%rsp)
 1033450:	jae    103434d <my.app::main+0x15ad>
 1033456:	mov    %rax,0x8(%rsp)
 103345b:	lea    0x20(%rax),%r12
 103345f:	mov    %rsi,%rcx
 1033462:	shl    $0x4,%rcx
 1033466:	movq   $0xd,0x20(%rax,%rcx,1)
 103346f:	movq   $0x0,0x28(%rax,%rcx,1)
 1033478:	inc    %rsi
 103347b:	mov    %rsi,0x8(%rax)
 103347f:	lea    0x31da(%rip),%rdi        # 1036660 <core_io_file_error.verbs+0xb0>
 1033486:	vzeroupper
 1033489:	call   100a4c0 <myl_core_io_at>
 103348e:	mov    0x18(%rsp),%rdi
 1033493:	call   1022430 <myl_core_host_check>
 1033498:	call   10350b0 <runtime_bench_now>
 103349d:	xor    %r11d,%r11d
 10334a0:	mov    0x8(%rsp),%r10
 10334a5:	mov    %rax,0x28(%rsp)
 10334aa:	lea    -0x2eeb1(%rip),%rbp        # 1004600 <core_number_pairs+0xd0>
 10334b1:	movabs $0x100000000000001,%r13
 10334bb:	vxorps %xmm1,%xmm1,%xmm1
 10334bf:	xor    %eax,%eax
 10334c1:	xor    %edx,%edx
 10334c3:	lea    0x27716(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10334ca:	mov    (%rsp),%r8
 10334ce:	xchg   %ax,%ax
 10334d0:	mov    0x20(%rsp),%rcx
 10334d5:	add    %rdx,%rcx
 10334d8:	mov    %rcx,0x50(%rsp)
 10334dd:	jo     10343ea <my.app::main+0x164a>
 10334e3:	mov    %rax,0x48(%rsp)
 10334e8:	mov    %rdx,0x40(%rsp)
 10334ed:	mov    0x8(%r9),%r15
 10334f1:	test   %r15,%r15
 10334f4:	je     1033c3b <my.app::main+0xe9b>
 10334fa:	mov    (%r15),%rax
 10334fd:	mov    %rax,0x8(%r9)
 1033501:	mov    %r13,(%r15)
 1033504:	vmovups %xmm1,0x8(%r15)
 103350a:	movq   $0x0,0x18(%r15)
 1033512:	mov    0x8(%r9),%rax
 1033516:	test   %rax,%rax
 1033519:	je     1033c69 <my.app::main+0xec9>
 103351f:	mov    (%rax),%rcx
 1033522:	mov    %rcx,0x8(%r9)
 1033526:	mov    %r13,(%rax)
 1033529:	vmovups %xmm1,0x8(%rax)
 103352e:	movq   $0x0,0x18(%rax)
 1033536:	mov    %rax,0x10(%rsp)
 103353b:	mov    0x10(%r9),%rdi
 103353f:	test   %rdi,%rdi
 1033542:	je     1033c94 <my.app::main+0xef4>
 1033548:	mov    (%rdi),%rax
 103354b:	mov    %rax,0x10(%r9)
 103354f:	vmovaps -0x2fe77(%rip),%ymm0        # 10036e0 <core_io_raw_layout+0x160>
 1033557:	vmovups %ymm0,(%rdi)
 103355b:	mov    $0x4,%ecx
 1033560:	xor    %edx,%edx
 1033562:	movq   $0x0,0x20(%rdi,%rdx,8)
 103356b:	inc    %rdx
 103356e:	mov    %rdx,0x8(%rdi)
 1033572:	cmp    %rcx,%rdx
 1033575:	jae    1033ceb <my.app::main+0xf4b>
 103357b:	movq   $0x0,0x20(%rdi,%rdx,8)
 1033584:	inc    %rdx
 1033587:	mov    %rdx,0x8(%rdi)
 103358b:	mov    0x8(%r10),%rdx
 103358f:	xor    %esi,%esi
 1033591:	test   %rdx,%rdx
 1033594:	je     1033dc9 <my.app::main+0x1029>
 103359a:	xor    %eax,%eax
 103359c:	mov    %rax,%r13
 103359f:	jmp    10335e8 <my.app::main+0x848>
 10335a1:	mov    0x8(%r15),%rax
 10335a5:	cmp    0x10(%r15),%rax
 10335a9:	jae    1033934 <my.app::main+0xb94>
 10335af:	mov    %rax,%rcx
 10335b2:	shl    $0x4,%rcx
 10335b6:	movq   $0x0,0x20(%r15,%rcx,1)
 10335bf:	mov    %r14,0x28(%r15,%rcx,1)
 10335c4:	inc    %rax
 10335c7:	mov    %rax,0x8(%r15)
 10335cb:	mov    0x8(%r10),%rdx
 10335cf:	mov    %r13,%rsi
 10335d2:	sar    $0x3f,%rsi
 10335d6:	and    %rdx,%rsi
 10335d9:	add    %r13,%rsi
 10335dc:	mov    %r13,%rax
 10335df:	cmp    %rdx,%rsi
 10335e2:	jae    1033dc9 <my.app::main+0x1029>
 10335e8:	inc    %r13
 10335eb:	jo     1033e91 <my.app::main+0x10f1>
 10335f1:	shl    $0x4,%rsi
 10335f5:	mov    (%r12,%rsi,1),%rcx
 10335f9:	mov    0x8(%r12,%rsi,1),%r14
 10335fe:	cmp    $0x4,%rcx
 1033602:	ja     10336fc <my.app::main+0x95c>
 1033608:	movslq 0x0(%rbp,%rcx,4),%rax
 103360d:	add    %rbp,%rax
 1033610:	jmp    *%rax
 1033612:	mov    0x8(%r15),%rax
 1033616:	cmp    0x10(%r15),%rax
 103361a:	jae    103396d <my.app::main+0xbcd>
 1033620:	mov    %rax,%rcx
 1033623:	shl    $0x4,%rcx
 1033627:	movq   $0x0,0x20(%r15,%rcx,1)
 1033630:	mov    0x50(%rsp),%rdx
 1033635:	mov    %rdx,0x28(%r15,%rcx,1)
 103363a:	jmp    10335c4 <my.app::main+0x824>
 103363c:	mov    0x8(%r15),%rdx
 1033640:	test   %rdx,%rdx
 1033643:	je     1033eb7 <my.app::main+0x1117>
 1033649:	dec    %rdx
 103364c:	mov    %rdx,%rax
 103364f:	shl    $0x4,%rax
 1033653:	movzbl 0x20(%r15,%rax,1),%ecx
 1033659:	mov    0x28(%r15,%rax,1),%rax
 103365e:	mov    %rdx,0x8(%r15)
 1033662:	mov    0x8(%rdi),%rdx
 1033666:	mov    %r14,%rsi
 1033669:	sar    $0x3f,%rsi
 103366d:	and    %rdx,%rsi
 1033670:	add    %r14,%rsi
 1033673:	cmp    %rdx,%rsi
 1033676:	jae    1033ea8 <my.app::main+0x1108>
 103367c:	test   %rcx,%rcx
 103367f:	cmovne %r11,%rax
 1033683:	mov    %rax,0x20(%rdi,%rsi,8)
 1033688:	jmp    10335cb <my.app::main+0x82b>
 103368d:	mov    0x8(%rdi),%rdx
 1033691:	mov    %r14,%rsi
 1033694:	sar    $0x3f,%rsi
 1033698:	and    %rdx,%rsi
 103369b:	add    %r14,%rsi
 103369e:	cmp    %rdx,%rsi
 10336a1:	jae    1033eca <my.app::main+0x112a>
 10336a7:	mov    0x20(%rdi,%rsi,8),%rbx
 10336ac:	mov    0x8(%r15),%rax
 10336b0:	cmp    0x10(%r15),%rax
 10336b4:	jae    10339df <my.app::main+0xc3f>
 10336ba:	mov    %rax,%rcx
 10336bd:	shl    $0x4,%rcx
 10336c1:	movq   $0x0,0x20(%r15,%rcx,1)
 10336ca:	mov    %rbx,0x28(%r15,%rcx,1)
 10336cf:	jmp    10335c4 <my.app::main+0x824>
 10336d4:	mov    0x8(%r15),%rax
 10336d8:	cmp    0x10(%r15),%rax
 10336dc:	jae    10339a6 <my.app::main+0xc06>
 10336e2:	mov    %rax,%rcx
 10336e5:	shl    $0x4,%rcx
 10336e9:	movq   $0x0,0x20(%r15,%rcx,1)
 10336f2:	mov    %r8,0x28(%r15,%rcx,1)
 10336f7:	jmp    10335c4 <my.app::main+0x824>
 10336fc:	lea    -0x5(%rcx),%rax
 1033700:	cmp    $0x5,%rax
 1033704:	jae    103372d <my.app::main+0x98d>
 1033706:	mov    0x8(%r15),%rcx
 103370a:	test   %rcx,%rcx
 103370d:	je     1033eec <my.app::main+0x114c>
 1033713:	lea    -0x1(%rcx),%rdx
 1033717:	mov    %rdx,%rsi
 103371a:	shl    $0x4,%rsi
 103371e:	cmpb   $0x0,0x20(%r15,%rsi,1)
 1033724:	jne    1033784 <my.app::main+0x9e4>
 1033726:	mov    0x28(%r15,%rsi,1),%rbp
 103372b:	jmp    1033786 <my.app::main+0x9e6>
 103372d:	add    $0xfffffffffffffff6,%rcx
 1033731:	cmp    $0x3,%rcx
 1033735:	ja     1033b40 <my.app::main+0xda0>
 103373b:	lea    -0x2f12e(%rip),%rdx        # 1004614 <core_number_pairs+0xe4>
 1033742:	movslq (%rdx,%rcx,4),%rax
 1033746:	add    %rdx,%rax
 1033749:	jmp    *%rax
 103374b:	mov    0x8(%r15),%rax
 103374f:	test   %rax,%rax
 1033752:	je     1034366 <my.app::main+0x15c6>
 1033758:	dec    %rax
 103375b:	mov    %rax,%rcx
 103375e:	shl    $0x4,%rcx
 1033762:	movzbl 0x20(%r15,%rcx,1),%edx
 1033768:	mov    0x28(%r15,%rcx,1),%rcx
 103376d:	mov    %rax,0x8(%r15)
 1033771:	test   $0x1,%cl
 1033774:	cmove  %r14,%r13
 1033778:	cmp    $0x1,%dl
 103377b:	cmovne %r14,%r13
 103377f:	jmp    10335cb <my.app::main+0x82b>
 1033784:	xor    %ebp,%ebp
 1033786:	mov    %rdx,0x8(%r15)
 103378a:	test   %rdx,%rdx
 103378d:	je     1033ed9 <my.app::main+0x1139>
 1033793:	mov    %rcx,%rdx
 1033796:	shl    $0x4,%rdx
 103379a:	cmpb   $0x0,(%r15,%rdx,1)
 103379f:	jne    10337a8 <my.app::main+0xa08>
 10337a1:	mov    0x8(%r15,%rdx,1),%rbx
 10337a6:	jmp    10337aa <my.app::main+0xa0a>
 10337a8:	xor    %ebx,%ebx
 10337aa:	add    $0xfffffffffffffffe,%rcx
 10337ae:	mov    %rcx,0x8(%r15)
 10337b2:	cmp    $0x3,%rax
 10337b6:	ja     10338af <my.app::main+0xb0f>
 10337bc:	lea    -0x2f19f(%rip),%rdx        # 1004624 <core_number_pairs+0xf4>
 10337c3:	movslq (%rdx,%rax,4),%rax
 10337c7:	add    %rdx,%rax
 10337ca:	jmp    *%rax
 10337cc:	mov    %rbx,%r14
 10337cf:	add    %rbp,%r14
 10337d2:	jno    103389c <my.app::main+0xafc>
 10337d8:	jmp    10343b5 <my.app::main+0x1615>
 10337dd:	mov    0x10(%rsp),%rax
 10337e2:	mov    0x8(%rax),%rcx
 10337e6:	cmp    0x10(%rax),%rcx
 10337ea:	jae    1033a51 <my.app::main+0xcb1>
 10337f0:	mov    %r13,0x20(%rax,%rcx,8)
 10337f5:	inc    %rcx
 10337f8:	mov    %rax,0x10(%rsp)
 10337fd:	mov    %rcx,0x8(%rax)
 1033801:	mov    %r14,%r13
 1033804:	jmp    10335cb <my.app::main+0x82b>
 1033809:	mov    0x10(%rsp),%rcx
 103380e:	mov    0x8(%rcx),%rax
 1033812:	test   %rax,%rax
 1033815:	je     1034379 <my.app::main+0x15d9>
 103381b:	mov    0x18(%rcx,%rax,8),%r13
 1033820:	dec    %rax
 1033823:	mov    %rax,0x8(%rcx)
 1033827:	jmp    10335cb <my.app::main+0x82b>
 103382c:	mov    %r14,%r13
 103382f:	jmp    10335cb <my.app::main+0x82b>
 1033834:	test   %rbp,%rbp
 1033837:	je     10343a1 <my.app::main+0x1601>
 103383d:	cmp    $0xffffffffffffffff,%rbp
 1033841:	mov    %rbp,%rsi
 1033844:	mov    $0x1,%eax
 1033849:	cmove  %rax,%rsi
 103384d:	mov    %rbx,%rax
 1033850:	or     %rsi,%rax
 1033853:	shr    $0x20,%rax
 1033857:	je     10338e5 <my.app::main+0xb45>
 103385d:	mov    %rbx,%rax
 1033860:	cqto
 1033862:	idiv   %rsi
 1033865:	jmp    10338eb <my.app::main+0xb4b>
 103386a:	cmp    0x10(%r15),%rcx
 103386e:	jae    1033a87 <my.app::main+0xce7>
 1033874:	mov    %rcx,%rax
 1033877:	shl    $0x4,%rax
 103387b:	cmp    %rbp,%rbx
 103387e:	movq   $0x1,0x20(%r15,%rax,1)
 1033887:	setl   0x28(%r15,%rax,1)
 103388d:	jmp    10338d2 <my.app::main+0xb32>
 103388f:	mov    %rbx,%r14
 1033892:	imul   %rbp,%r14
 1033896:	jo     103438c <my.app::main+0x15ec>
 103389c:	cmp    0x10(%r15),%rcx
 10338a0:	jae    1033a18 <my.app::main+0xc78>
 10338a6:	lea    -0x2f2ad(%rip),%rbp        # 1004600 <core_number_pairs+0xd0>
 10338ad:	jmp    1033913 <my.app::main+0xb73>
 10338af:	cmp    0x10(%r15),%rcx
 10338b3:	jae    1033ac0 <my.app::main+0xd20>
 10338b9:	mov    %rcx,%rax
 10338bc:	shl    $0x4,%rax
 10338c0:	cmp    %rbp,%rbx
 10338c3:	movq   $0x1,0x20(%r15,%rax,1)
 10338cc:	sete   0x28(%r15,%rax,1)
 10338d2:	inc    %rcx
 10338d5:	mov    %rcx,0x8(%r15)
 10338d9:	lea    -0x2f2e0(%rip),%rbp        # 1004600 <core_number_pairs+0xd0>
 10338e0:	jmp    10335cb <my.app::main+0x82b>
 10338e5:	mov    %ebx,%eax
 10338e7:	xor    %edx,%edx
 10338e9:	div    %esi
 10338eb:	mov    %rdx,%r14
 10338ee:	xor    %rbp,%r14
 10338f1:	sar    $0x3f,%r14
 10338f5:	and    %rbp,%r14
 10338f8:	test   %rdx,%rdx
 10338fb:	cmove  %rdx,%r14
 10338ff:	cmp    0x10(%r15),%rcx
 1033903:	jae    1033af9 <my.app::main+0xd59>
 1033909:	lea    -0x2f310(%rip),%rbp        # 1004600 <core_number_pairs+0xd0>
 1033910:	add    %rdx,%r14
 1033913:	mov    %rcx,%rax
 1033916:	shl    $0x4,%rax
 103391a:	movq   $0x0,0x20(%r15,%rax,1)
 1033923:	mov    %r14,0x28(%r15,%rax,1)
 1033928:	inc    %rcx
 103392b:	mov    %rcx,0x8(%r15)
 103392f:	jmp    10335cb <my.app::main+0x82b>
 1033934:	mov    $0x10,%esi
 1033939:	mov    %rdi,%rbx
 103393c:	mov    %r15,%rdi
 103393f:	vzeroupper
 1033942:	call   10094f0 <myl_core_list_grow>
 1033947:	vxorps %xmm1,%xmm1,%xmm1
 103394b:	xor    %r11d,%r11d
 103394e:	mov    0x8(%rsp),%r10
 1033953:	mov    (%rsp),%r8
 1033957:	lea    0x27282(%rip),%r9        # 105abe0 <myl_core_free_lists>
 103395e:	mov    %rbx,%rdi
 1033961:	mov    %rax,%r15
 1033964:	mov    0x8(%rax),%rax
 1033968:	jmp    10335af <my.app::main+0x80f>
 103396d:	mov    $0x10,%esi
 1033972:	mov    %rdi,%rbx
 1033975:	mov    %r15,%rdi
 1033978:	vzeroupper
 103397b:	call   10094f0 <myl_core_list_grow>
 1033980:	vxorps %xmm1,%xmm1,%xmm1
 1033984:	xor    %r11d,%r11d
 1033987:	mov    0x8(%rsp),%r10
 103398c:	mov    (%rsp),%r8
 1033990:	lea    0x27249(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033997:	mov    %rbx,%rdi
 103399a:	mov    %rax,%r15
 103399d:	mov    0x8(%rax),%rax
 10339a1:	jmp    1033620 <my.app::main+0x880>
 10339a6:	mov    $0x10,%esi
 10339ab:	mov    %rdi,%rbx
 10339ae:	mov    %r15,%rdi
 10339b1:	vzeroupper
 10339b4:	call   10094f0 <myl_core_list_grow>
 10339b9:	vxorps %xmm1,%xmm1,%xmm1
 10339bd:	xor    %r11d,%r11d
 10339c0:	mov    0x8(%rsp),%r10
 10339c5:	mov    (%rsp),%r8
 10339c9:	lea    0x27210(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10339d0:	mov    %rbx,%rdi
 10339d3:	mov    %rax,%r15
 10339d6:	mov    0x8(%rax),%rax
 10339da:	jmp    10336e2 <my.app::main+0x942>
 10339df:	mov    $0x10,%esi
 10339e4:	mov    %rdi,%r14
 10339e7:	mov    %r15,%rdi
 10339ea:	vzeroupper
 10339ed:	call   10094f0 <myl_core_list_grow>
 10339f2:	vxorps %xmm1,%xmm1,%xmm1
 10339f6:	xor    %r11d,%r11d
 10339f9:	mov    0x8(%rsp),%r10
 10339fe:	mov    (%rsp),%r8
 1033a02:	lea    0x271d7(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033a09:	mov    %r14,%rdi
 1033a0c:	mov    %rax,%r15
 1033a0f:	mov    0x8(%rax),%rax
 1033a13:	jmp    10336ba <my.app::main+0x91a>
 1033a18:	mov    $0x10,%esi
 1033a1d:	mov    %rdi,%rbx
 1033a20:	mov    %r15,%rdi
 1033a23:	vzeroupper
 1033a26:	call   10094f0 <myl_core_list_grow>
 1033a2b:	vxorps %xmm1,%xmm1,%xmm1
 1033a2f:	xor    %r11d,%r11d
 1033a32:	mov    0x8(%rsp),%r10
 1033a37:	mov    (%rsp),%r8
 1033a3b:	lea    0x2719e(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033a42:	mov    %rbx,%rdi
 1033a45:	mov    %rax,%r15
 1033a48:	mov    0x8(%rax),%rcx
 1033a4c:	jmp    10338a6 <my.app::main+0xb06>
 1033a51:	mov    $0x8,%esi
 1033a56:	mov    %rdi,%rbx
 1033a59:	mov    %rax,%rdi
 1033a5c:	vzeroupper
 1033a5f:	call   10094f0 <myl_core_list_grow>
 1033a64:	vxorps %xmm1,%xmm1,%xmm1
 1033a68:	xor    %r11d,%r11d
 1033a6b:	mov    0x8(%rsp),%r10
 1033a70:	mov    (%rsp),%r8
 1033a74:	lea    0x27165(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033a7b:	mov    %rbx,%rdi
 1033a7e:	mov    0x8(%rax),%rcx
 1033a82:	jmp    10337f0 <my.app::main+0xa50>
 1033a87:	mov    $0x10,%esi
 1033a8c:	mov    %rdi,%r14
 1033a8f:	mov    %r15,%rdi
 1033a92:	vzeroupper
 1033a95:	call   10094f0 <myl_core_list_grow>
 1033a9a:	vxorps %xmm1,%xmm1,%xmm1
 1033a9e:	xor    %r11d,%r11d
 1033aa1:	mov    0x8(%rsp),%r10
 1033aa6:	mov    (%rsp),%r8
 1033aaa:	lea    0x2712f(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033ab1:	mov    %r14,%rdi
 1033ab4:	mov    %rax,%r15
 1033ab7:	mov    0x8(%rax),%rcx
 1033abb:	jmp    1033874 <my.app::main+0xad4>
 1033ac0:	mov    $0x10,%esi
 1033ac5:	mov    %rdi,%r14
 1033ac8:	mov    %r15,%rdi
 1033acb:	vzeroupper
 1033ace:	call   10094f0 <myl_core_list_grow>
 1033ad3:	vxorps %xmm1,%xmm1,%xmm1
 1033ad7:	xor    %r11d,%r11d
 1033ada:	mov    0x8(%rsp),%r10
 1033adf:	mov    (%rsp),%r8
 1033ae3:	lea    0x270f6(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033aea:	mov    %r14,%rdi
 1033aed:	mov    %rax,%r15
 1033af0:	mov    0x8(%rax),%rcx
 1033af4:	jmp    10338b9 <my.app::main+0xb19>
 1033af9:	mov    $0x10,%esi
 1033afe:	mov    %rdi,%rbp
 1033b01:	mov    %r15,%rdi
 1033b04:	mov    %rdx,%rbx
 1033b07:	vzeroupper
 1033b0a:	call   10094f0 <myl_core_list_grow>
 1033b0f:	vxorps %xmm1,%xmm1,%xmm1
 1033b13:	xor    %r11d,%r11d
 1033b16:	mov    0x8(%rsp),%r10
 1033b1b:	mov    (%rsp),%r8
 1033b1f:	lea    0x270ba(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033b26:	mov    %rbp,%rdi
 1033b29:	mov    %rbx,%rdx
 1033b2c:	mov    %rax,%r15
 1033b2f:	mov    0x8(%rax),%rcx
 1033b33:	jmp    1033909 <my.app::main+0xb69>
 1033b38:	nopl   0x0(%rax,%rax,1)
 1033b40:	movzbl 0x7(%rdi),%eax
 1033b44:	test   %rax,%rax
 1033b47:	je     1033d1b <my.app::main+0xf7b>
 1033b4d:	cmpq   $0x0,0x18(%rdi)
 1033b52:	jne    1033d1b <my.app::main+0xf7b>
 1033b58:	mov    (%r9,%rax,8),%rcx
 1033b5c:	mov    %rcx,(%rdi)
 1033b5f:	mov    %rdi,(%r9,%rax,8)
 1033b63:	movabs $0x100000000000001,%r13
 1033b6d:	mov    0x10(%rsp),%rdi
 1033b72:	movzbl 0x7(%rdi),%eax
 1033b76:	test   %rax,%rax
 1033b79:	je     1033d3f <my.app::main+0xf9f>
 1033b7f:	cmpq   $0x0,0x18(%rdi)
 1033b84:	jne    1033d3f <my.app::main+0xf9f>
 1033b8a:	mov    (%r9,%rax,8),%rcx
 1033b8e:	mov    %rcx,(%rdi)
 1033b91:	mov    %rdi,(%r9,%rax,8)
 1033b95:	mov    0x8(%r15),%rax
 1033b99:	test   %rax,%rax
 1033b9c:	je     10343fe <my.app::main+0x165e>
 1033ba2:	dec    %rax
 1033ba5:	mov    %rax,%rcx
 1033ba8:	shl    $0x4,%rcx
 1033bac:	movzbl 0x20(%r15,%rcx,1),%ebx
 1033bb2:	mov    0x28(%r15,%rcx,1),%r14
 1033bb7:	mov    %rax,0x8(%r15)
 1033bbb:	movzbl 0x7(%r15),%eax
 1033bc0:	test   %rax,%rax
 1033bc3:	je     1033d63 <my.app::main+0xfc3>
 1033bc9:	cmpq   $0x0,0x18(%r15)
 1033bce:	jne    1033d63 <my.app::main+0xfc3>
 1033bd4:	mov    (%r9,%rax,8),%rcx
 1033bd8:	mov    %rcx,(%r15)
 1033bdb:	mov    %r15,(%r9,%rax,8)
 1033bdf:	test   %rbx,%rbx
 1033be2:	cmovne %r11,%r14
 1033be6:	test   %r14,%r14
 1033be9:	mov    0x48(%rsp),%rsi
 1033bee:	js     1033d96 <my.app::main+0xff6>
 1033bf4:	mov    %rsi,%rbx
 1033bf7:	add    %r14,%rbx
 1033bfa:	jo     1034411 <my.app::main+0x1671>
 1033c00:	mov    %rbx,%rdx
 1033c03:	movabs $0x89705f3112a28fe5,%rax
 1033c0d:	mulx   %rax,%rax,%rax
 1033c12:	shr    $0x1d,%rax
 1033c16:	imul   $0x3b9aca07,%rax,%rax
 1033c1d:	sub    %rax,%rbx
 1033c20:	mov    0x40(%rsp),%rdx
 1033c25:	inc    %rdx
 1033c28:	mov    %rbx,%rax
 1033c2b:	cmp    0x38(%rsp),%rdx
 1033c30:	jne    10334d0 <my.app::main+0x730>
 1033c36:	jmp    1033db3 <my.app::main+0x1013>
 1033c3b:	mov    $0x10,%esi
 1033c40:	xor    %edi,%edi
 1033c42:	vzeroupper
 1033c45:	call   1009480 <myl_core_list_new_slow>
 1033c4a:	vxorps %xmm1,%xmm1,%xmm1
 1033c4e:	xor    %r11d,%r11d
 1033c51:	mov    0x8(%rsp),%r10
 1033c56:	mov    (%rsp),%r8
 1033c5a:	lea    0x26f7f(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033c61:	mov    %rax,%r15
 1033c64:	jmp    1033512 <my.app::main+0x772>
 1033c69:	mov    $0x8,%esi
 1033c6e:	xor    %edi,%edi
 1033c70:	vzeroupper
 1033c73:	call   1009480 <myl_core_list_new_slow>
 1033c78:	vxorps %xmm1,%xmm1,%xmm1
 1033c7c:	xor    %r11d,%r11d
 1033c7f:	mov    0x8(%rsp),%r10
 1033c84:	mov    (%rsp),%r8
 1033c88:	lea    0x26f51(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033c8f:	jmp    1033536 <my.app::main+0x796>
 1033c94:	mov    $0x2,%edi
 1033c99:	mov    $0x8,%esi
 1033c9e:	vzeroupper
 1033ca1:	call   1009480 <myl_core_list_new_slow>
 1033ca6:	mov    %rax,%rdi
 1033ca9:	mov    0x8(%rax),%rdx
 1033cad:	mov    0x10(%rax),%rcx
 1033cb1:	cmp    %rcx,%rdx
 1033cb4:	jb     1033d8a <my.app::main+0xfea>
 1033cba:	mov    $0x8,%esi
 1033cbf:	call   10094f0 <myl_core_list_grow>
 1033cc4:	mov    0x8(%rax),%rdx
 1033cc8:	mov    0x10(%rax),%rcx
 1033ccc:	lea    0x26f0d(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033cd3:	mov    %rax,%rdi
 1033cd6:	mov    (%rsp),%r8
 1033cda:	mov    0x8(%rsp),%r10
 1033cdf:	xor    %r11d,%r11d
 1033ce2:	vxorps %xmm1,%xmm1,%xmm1
 1033ce6:	jmp    1033562 <my.app::main+0x7c2>
 1033ceb:	mov    $0x8,%esi
 1033cf0:	vzeroupper
 1033cf3:	call   10094f0 <myl_core_list_grow>
 1033cf8:	vxorps %xmm1,%xmm1,%xmm1
 1033cfc:	xor    %r11d,%r11d
 1033cff:	mov    0x8(%rsp),%r10
 1033d04:	mov    (%rsp),%r8
 1033d08:	lea    0x26ed1(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d0f:	mov    %rax,%rdi
 1033d12:	mov    0x8(%rax),%rdx
 1033d16:	jmp    103357b <my.app::main+0x7db>
 1033d1b:	vzeroupper
 1033d1e:	call   1032790 <myl_core_free_block>
 1033d23:	vxorps %xmm1,%xmm1,%xmm1
 1033d27:	xor    %r11d,%r11d
 1033d2a:	mov    0x8(%rsp),%r10
 1033d2f:	mov    (%rsp),%r8
 1033d33:	lea    0x26ea6(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d3a:	jmp    1033b63 <my.app::main+0xdc3>
 1033d3f:	vzeroupper
 1033d42:	call   1032790 <myl_core_free_block>
 1033d47:	vxorps %xmm1,%xmm1,%xmm1
 1033d4b:	xor    %r11d,%r11d
 1033d4e:	mov    0x8(%rsp),%r10
 1033d53:	mov    (%rsp),%r8
 1033d57:	lea    0x26e82(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d5e:	jmp    1033b95 <my.app::main+0xdf5>
 1033d63:	mov    %r15,%rdi
 1033d66:	vzeroupper
 1033d69:	call   1032790 <myl_core_free_block>
 1033d6e:	vxorps %xmm1,%xmm1,%xmm1
 1033d72:	xor    %r11d,%r11d
 1033d75:	mov    0x8(%rsp),%r10
 1033d7a:	mov    (%rsp),%r8
 1033d7e:	lea    0x26e5b(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d85:	jmp    1033bdf <my.app::main+0xe3f>
 1033d8a:	lea    0x26e4f(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1033d91:	jmp    1033cd6 <my.app::main+0xf36>
 1033d96:	mov    (%r10),%eax
 1033d99:	mov    $0x2,%ebx
 1033d9e:	cmp    $0xffffffff,%eax
 1033da1:	je     1033e7c <my.app::main+0x10dc>
 1033da7:	dec    %eax
 1033da9:	je     1033dd8 <my.app::main+0x1038>
 1033dab:	mov    %eax,(%r10)
 1033dae:	jmp    1033e7c <my.app::main+0x10dc>
 1033db3:	mov    (%r10),%eax
 1033db6:	cmp    $0xffffffff,%eax
 1033db9:	mov    0x18(%rsp),%r14
 1033dbe:	je     1033e22 <my.app::main+0x1082>
 1033dc0:	dec    %eax
 1033dc2:	je     1033dfe <my.app::main+0x105e>
 1033dc4:	mov    %eax,(%r10)
 1033dc7:	jmp    1033e22 <my.app::main+0x1082>
 1033dc9:	lea    0x2980(%rip),%rdi        # 1036750 <core_io_file_error.verbs+0x1a0>
 1033dd0:	vzeroupper
 1033dd3:	call   1009b80 <myl_core_trap>
 1033dd8:	movzbl 0x7(%r10),%eax
 1033ddd:	test   %rax,%rax
 1033de0:	je     10343ca <my.app::main+0x162a>
 1033de6:	cmpq   $0x0,0x18(%r10)
 1033deb:	jne    10343ca <my.app::main+0x162a>
 1033df1:	mov    (%r9,%rax,8),%rcx
 1033df5:	mov    %rcx,(%r10)
 1033df8:	mov    %r10,(%r9,%rax,8)
 1033dfc:	jmp    1033e7c <my.app::main+0x10dc>
 1033dfe:	movzbl 0x7(%r10),%eax
 1033e03:	test   %rax,%rax
 1033e06:	je     10343da <my.app::main+0x163a>
 1033e0c:	cmpq   $0x0,0x18(%r10)
 1033e11:	jne    10343da <my.app::main+0x163a>
 1033e17:	mov    (%r9,%rax,8),%rcx
 1033e1b:	mov    %rcx,(%r10)
 1033e1e:	mov    %r10,(%r9,%rax,8)
 1033e22:	lea    0x2867(%rip),%rdi        # 1036690 <core_io_file_error.verbs+0xe0>
 1033e29:	vzeroupper
 1033e2c:	call   100a4c0 <myl_core_io_at>
 1033e31:	mov    %r14,%rdi
 1033e34:	call   1022430 <myl_core_host_check>
 1033e39:	call   10350b0 <runtime_bench_now>
 1033e3e:	mov    %rax,%r14
 1033e41:	mov    0x28(%rsp),%rdx
 1033e46:	sub    %rdx,%r14
 1033e49:	jo     1034445 <my.app::main+0x16a5>
 1033e4f:	mov    0x30(%rsp),%r15
 1033e54:	mov    %r15,%rdi
 1033e57:	mov    %rbx,%rsi
 1033e5a:	call   100abc0 <myl_core_print_i64>
 1033e5f:	mov    %r15,%rdi
 1033e62:	call   1009200 <myl_core_print_sep>
 1033e67:	mov    %r15,%rdi
 1033e6a:	mov    %r14,%rsi
 1033e6d:	call   100abc0 <myl_core_print_i64>
 1033e72:	mov    %r15,%rdi
 1033e75:	call   10092c0 <myl_core_print_end>
 1033e7a:	xor    %ebx,%ebx
 1033e7c:	mov    %rbx,%rax
 1033e7f:	add    $0x58,%rsp
 1033e83:	pop    %rbx
 1033e84:	pop    %r12
 1033e86:	pop    %r13
 1033e88:	pop    %r14
 1033e8a:	pop    %r15
 1033e8c:	pop    %rbp
 1033e8d:	vzeroupper
 1033e90:	ret
 1033e91:	lea    0x28e8(%rip),%rdi        # 1036780 <core_io_file_error.verbs+0x1d0>
 1033e98:	mov    $0x1,%edx
 1033e9d:	mov    %rax,%rsi
 1033ea0:	vzeroupper
 1033ea3:	call   1009b80 <myl_core_trap>
 1033ea8:	lea    0x2961(%rip),%rdi        # 1036810 <core_io_file_error.verbs+0x260>
 1033eaf:	vzeroupper
 1033eb2:	call   1009b80 <myl_core_trap>
 1033eb7:	lea    0x2922(%rip),%rdi        # 10367e0 <core_io_file_error.verbs+0x230>
 1033ebe:	xor    %esi,%esi
 1033ec0:	xor    %edx,%edx
 1033ec2:	vzeroupper
 1033ec5:	call   1009b80 <myl_core_trap>
 1033eca:	lea    0x28df(%rip),%rdi        # 10367b0 <core_io_file_error.verbs+0x200>
 1033ed1:	vzeroupper
 1033ed4:	call   1009b80 <myl_core_trap>
 1033ed9:	lea    0x2990(%rip),%rdi        # 1036870 <core_io_file_error.verbs+0x2c0>
 1033ee0:	xor    %esi,%esi
 1033ee2:	xor    %edx,%edx
 1033ee4:	vzeroupper
 1033ee7:	call   1009b80 <myl_core_trap>
 1033eec:	lea    0x294d(%rip),%rdi        # 1036840 <core_io_file_error.verbs+0x290>
 1033ef3:	xor    %esi,%esi
 1033ef5:	xor    %edx,%edx
 1033ef7:	vzeroupper
 1033efa:	call   1009b80 <myl_core_trap>
 1033eff:	mov    $0x26,%edi
 1033f04:	mov    $0x10,%esi
 1033f09:	call   1009480 <myl_core_list_new_slow>
 1033f0e:	mov    0x8(%rax),%rsi
 1033f12:	mov    0x10(%rax),%rcx
 1033f16:	cmp    %rcx,%rsi
 1033f19:	jb     1032e6c <my.app::main+0xcc>
 1033f1f:	mov    $0x10,%esi
 1033f24:	mov    %rax,%rdi
 1033f27:	call   10094f0 <myl_core_list_grow>
 1033f2c:	mov    0x8(%rax),%rsi
 1033f30:	mov    0x10(%rax),%rcx
 1033f34:	jmp    1032e6c <my.app::main+0xcc>
 1033f39:	mov    $0x10,%esi
 1033f3e:	mov    %rax,%rdi
 1033f41:	vzeroupper
 1033f44:	call   10094f0 <myl_core_list_grow>
 1033f49:	mov    0x8(%rax),%rsi
 1033f4d:	mov    0x10(%rax),%rcx
 1033f51:	jmp    1032e8d <my.app::main+0xed>
 1033f56:	mov    $0x10,%esi
 1033f5b:	mov    %rax,%rdi
 1033f5e:	vzeroupper
 1033f61:	call   10094f0 <myl_core_list_grow>
 1033f66:	mov    0x8(%rax),%rsi
 1033f6a:	mov    0x10(%rax),%rcx
 1033f6e:	jmp    1032eb6 <my.app::main+0x116>
 1033f73:	mov    $0x10,%esi
 1033f78:	mov    %rax,%rdi
 1033f7b:	vzeroupper
 1033f7e:	call   10094f0 <myl_core_list_grow>
 1033f83:	mov    0x8(%rax),%rsi
 1033f87:	mov    0x10(%rax),%rcx
 1033f8b:	jmp    1032edf <my.app::main+0x13f>
 1033f90:	mov    $0x10,%esi
 1033f95:	mov    %rax,%rdi
 1033f98:	vzeroupper
 1033f9b:	call   10094f0 <myl_core_list_grow>
 1033fa0:	mov    0x8(%rax),%rsi
 1033fa4:	mov    0x10(%rax),%rcx
 1033fa8:	jmp    1032f08 <my.app::main+0x168>
 1033fad:	mov    $0x10,%esi
 1033fb2:	mov    %rax,%rdi
 1033fb5:	vzeroupper
 1033fb8:	call   10094f0 <myl_core_list_grow>
 1033fbd:	mov    0x8(%rax),%rsi
 1033fc1:	mov    0x10(%rax),%rcx
 1033fc5:	jmp    1032f31 <my.app::main+0x191>
 1033fca:	mov    $0x10,%esi
 1033fcf:	mov    %rax,%rdi
 1033fd2:	vzeroupper
 1033fd5:	call   10094f0 <myl_core_list_grow>
 1033fda:	mov    0x8(%rax),%rsi
 1033fde:	mov    0x10(%rax),%rcx
 1033fe2:	jmp    1032f5a <my.app::main+0x1ba>
 1033fe7:	mov    $0x10,%esi
 1033fec:	mov    %rax,%rdi
 1033fef:	vzeroupper
 1033ff2:	call   10094f0 <myl_core_list_grow>
 1033ff7:	mov    0x8(%rax),%rsi
 1033ffb:	mov    0x10(%rax),%rcx
 1033fff:	jmp    1032f83 <my.app::main+0x1e3>
 1034004:	mov    $0x10,%esi
 1034009:	mov    %rax,%rdi
 103400c:	vzeroupper
 103400f:	call   10094f0 <myl_core_list_grow>
 1034014:	mov    0x8(%rax),%rsi
 1034018:	mov    0x10(%rax),%rcx
 103401c:	jmp    1032fac <my.app::main+0x20c>
 1034021:	mov    $0x10,%esi
 1034026:	mov    %rax,%rdi
 1034029:	vzeroupper
 103402c:	call   10094f0 <myl_core_list_grow>
 1034031:	mov    0x8(%rax),%rsi
 1034035:	mov    0x10(%rax),%rcx
 1034039:	jmp    1032fd5 <my.app::main+0x235>
 103403e:	mov    $0x10,%esi
 1034043:	mov    %rax,%rdi
 1034046:	vzeroupper
 1034049:	call   10094f0 <myl_core_list_grow>
 103404e:	mov    0x8(%rax),%rsi
 1034052:	mov    0x10(%rax),%rcx
 1034056:	jmp    1032ffe <my.app::main+0x25e>
 103405b:	mov    $0x10,%esi
 1034060:	mov    %rax,%rdi
 1034063:	vzeroupper
 1034066:	call   10094f0 <myl_core_list_grow>
 103406b:	mov    0x8(%rax),%rsi
 103406f:	mov    0x10(%rax),%rcx
 1034073:	jmp    1033027 <my.app::main+0x287>
 1034078:	mov    $0x10,%esi
 103407d:	mov    %rax,%rdi
 1034080:	vzeroupper
 1034083:	call   10094f0 <myl_core_list_grow>
 1034088:	mov    0x8(%rax),%rsi
 103408c:	mov    0x10(%rax),%rcx
 1034090:	jmp    1033050 <my.app::main+0x2b0>
 1034095:	mov    $0x10,%esi
 103409a:	mov    %rax,%rdi
 103409d:	vzeroupper
 10340a0:	call   10094f0 <myl_core_list_grow>
 10340a5:	mov    0x8(%rax),%rsi
 10340a9:	mov    0x10(%rax),%rcx
 10340ad:	jmp    1033079 <my.app::main+0x2d9>
 10340b2:	mov    $0x10,%esi
 10340b7:	mov    %rax,%rdi
 10340ba:	vzeroupper
 10340bd:	call   10094f0 <myl_core_list_grow>
 10340c2:	mov    0x8(%rax),%rsi
 10340c6:	mov    0x10(%rax),%rcx
 10340ca:	jmp    10330a2 <my.app::main+0x302>
 10340cf:	mov    $0x10,%esi
 10340d4:	mov    %rax,%rdi
 10340d7:	vzeroupper
 10340da:	call   10094f0 <myl_core_list_grow>
 10340df:	mov    0x8(%rax),%rsi
 10340e3:	mov    0x10(%rax),%rcx
 10340e7:	jmp    10330cb <my.app::main+0x32b>
 10340ec:	mov    $0x10,%esi
 10340f1:	mov    %rax,%rdi
 10340f4:	vzeroupper
 10340f7:	call   10094f0 <myl_core_list_grow>
 10340fc:	mov    0x8(%rax),%rsi
 1034100:	mov    0x10(%rax),%rcx
 1034104:	jmp    10330f4 <my.app::main+0x354>
 1034109:	mov    $0x10,%esi
 103410e:	mov    %rax,%rdi
 1034111:	vzeroupper
 1034114:	call   10094f0 <myl_core_list_grow>
 1034119:	mov    0x8(%rax),%rsi
 103411d:	mov    0x10(%rax),%rcx
 1034121:	jmp    103311d <my.app::main+0x37d>
 1034126:	mov    $0x10,%esi
 103412b:	mov    %rax,%rdi
 103412e:	vzeroupper
 1034131:	call   10094f0 <myl_core_list_grow>
 1034136:	mov    0x8(%rax),%rsi
 103413a:	mov    0x10(%rax),%rcx
 103413e:	jmp    1033146 <my.app::main+0x3a6>
 1034143:	mov    $0x10,%esi
 1034148:	mov    %rax,%rdi
 103414b:	vzeroupper
 103414e:	call   10094f0 <myl_core_list_grow>
 1034153:	mov    0x8(%rax),%rsi
 1034157:	mov    0x10(%rax),%rcx
 103415b:	jmp    103316f <my.app::main+0x3cf>
 1034160:	mov    $0x10,%esi
 1034165:	mov    %rax,%rdi
 1034168:	vzeroupper
 103416b:	call   10094f0 <myl_core_list_grow>
 1034170:	mov    0x8(%rax),%rsi
 1034174:	mov    0x10(%rax),%rcx
 1034178:	jmp    1033198 <my.app::main+0x3f8>
 103417d:	mov    $0x10,%esi
 1034182:	mov    %rax,%rdi
 1034185:	vzeroupper
 1034188:	call   10094f0 <myl_core_list_grow>
 103418d:	mov    0x8(%rax),%rsi
 1034191:	mov    0x10(%rax),%rcx
 1034195:	jmp    10331c1 <my.app::main+0x421>
 103419a:	mov    $0x10,%esi
 103419f:	mov    %rax,%rdi
 10341a2:	vzeroupper
 10341a5:	call   10094f0 <myl_core_list_grow>
 10341aa:	mov    0x8(%rax),%rsi
 10341ae:	mov    0x10(%rax),%rcx
 10341b2:	jmp    10331ea <my.app::main+0x44a>
 10341b7:	mov    $0x10,%esi
 10341bc:	mov    %rax,%rdi
 10341bf:	vzeroupper
 10341c2:	call   10094f0 <myl_core_list_grow>
 10341c7:	mov    0x8(%rax),%rsi
 10341cb:	mov    0x10(%rax),%rcx
 10341cf:	jmp    1033213 <my.app::main+0x473>
 10341d4:	mov    $0x10,%esi
 10341d9:	mov    %rax,%rdi
 10341dc:	vzeroupper
 10341df:	call   10094f0 <myl_core_list_grow>
 10341e4:	mov    0x8(%rax),%rsi
 10341e8:	mov    0x10(%rax),%rcx
 10341ec:	jmp    103323c <my.app::main+0x49c>
 10341f1:	mov    $0x10,%esi
 10341f6:	mov    %rax,%rdi
 10341f9:	vzeroupper
 10341fc:	call   10094f0 <myl_core_list_grow>
 1034201:	mov    0x8(%rax),%rsi
 1034205:	mov    0x10(%rax),%rcx
 1034209:	jmp    1033265 <my.app::main+0x4c5>
 103420e:	mov    $0x10,%esi
 1034213:	mov    %rax,%rdi
 1034216:	vzeroupper
 1034219:	call   10094f0 <myl_core_list_grow>
 103421e:	mov    0x8(%rax),%rsi
 1034222:	mov    0x10(%rax),%rcx
 1034226:	jmp    103328e <my.app::main+0x4ee>
 103422b:	mov    $0x10,%esi
 1034230:	mov    %rax,%rdi
 1034233:	vzeroupper
 1034236:	call   10094f0 <myl_core_list_grow>
 103423b:	mov    0x8(%rax),%rsi
 103423f:	mov    0x10(%rax),%rcx
 1034243:	jmp    10332b7 <my.app::main+0x517>
 1034248:	mov    $0x10,%esi
 103424d:	mov    %rax,%rdi
 1034250:	vzeroupper
 1034253:	call   10094f0 <myl_core_list_grow>
 1034258:	mov    0x8(%rax),%rsi
 103425c:	mov    0x10(%rax),%rcx
 1034260:	jmp    10332e0 <my.app::main+0x540>
 1034265:	mov    $0x10,%esi
 103426a:	mov    %rax,%rdi
 103426d:	vzeroupper
 1034270:	call   10094f0 <myl_core_list_grow>
 1034275:	mov    0x8(%rax),%rsi
 1034279:	mov    0x10(%rax),%rcx
 103427d:	jmp    1033309 <my.app::main+0x569>
 1034282:	mov    $0x10,%esi
 1034287:	mov    %rax,%rdi
 103428a:	vzeroupper
 103428d:	call   10094f0 <myl_core_list_grow>
 1034292:	mov    0x8(%rax),%rsi
 1034296:	mov    0x10(%rax),%rcx
 103429a:	jmp    1033332 <my.app::main+0x592>
 103429f:	mov    $0x10,%esi
 10342a4:	mov    %rax,%rdi
 10342a7:	vzeroupper
 10342aa:	call   10094f0 <myl_core_list_grow>
 10342af:	mov    0x8(%rax),%rsi
 10342b3:	mov    0x10(%rax),%rcx
 10342b7:	jmp    103335b <my.app::main+0x5bb>
 10342bc:	mov    $0x10,%esi
 10342c1:	mov    %rax,%rdi
 10342c4:	vzeroupper
 10342c7:	call   10094f0 <myl_core_list_grow>
 10342cc:	mov    0x8(%rax),%rsi
 10342d0:	mov    0x10(%rax),%rcx
 10342d4:	jmp    1033384 <my.app::main+0x5e4>
 10342d9:	mov    $0x10,%esi
 10342de:	mov    %rax,%rdi
 10342e1:	vzeroupper
 10342e4:	call   10094f0 <myl_core_list_grow>
 10342e9:	mov    0x8(%rax),%rsi
 10342ed:	mov    0x10(%rax),%rcx
 10342f1:	jmp    10333ad <my.app::main+0x60d>
 10342f6:	mov    $0x10,%esi
 10342fb:	mov    %rax,%rdi
 10342fe:	vzeroupper
 1034301:	call   10094f0 <myl_core_list_grow>
 1034306:	mov    0x8(%rax),%rsi
 103430a:	mov    0x10(%rax),%rcx
 103430e:	jmp    10333d6 <my.app::main+0x636>
 1034313:	mov    $0x10,%esi
 1034318:	mov    %rax,%rdi
 103431b:	vzeroupper
 103431e:	call   10094f0 <myl_core_list_grow>
 1034323:	mov    0x8(%rax),%rsi
 1034327:	mov    0x10(%rax),%rcx
 103432b:	jmp    10333ff <my.app::main+0x65f>
 1034330:	mov    $0x10,%esi
 1034335:	mov    %rax,%rdi
 1034338:	vzeroupper
 103433b:	call   10094f0 <myl_core_list_grow>
 1034340:	mov    0x8(%rax),%rsi
 1034344:	mov    0x10(%rax),%rcx
 1034348:	jmp    1033428 <my.app::main+0x688>
 103434d:	mov    $0x10,%esi
 1034352:	mov    %rax,%rdi
 1034355:	vzeroupper
 1034358:	call   10094f0 <myl_core_list_grow>
 103435d:	mov    0x8(%rax),%rsi
 1034361:	jmp    1033456 <my.app::main+0x6b6>
 1034366:	lea    0x25c3(%rip),%rdi        # 1036930 <core_io_file_error.verbs+0x380>
 103436d:	xor    %esi,%esi
 103436f:	xor    %edx,%edx
 1034371:	vzeroupper
 1034374:	call   1009b80 <myl_core_trap>
 1034379:	lea    0x25e0(%rip),%rdi        # 1036960 <core_io_file_error.verbs+0x3b0>
 1034380:	xor    %esi,%esi
 1034382:	xor    %edx,%edx
 1034384:	vzeroupper
 1034387:	call   1009b80 <myl_core_trap>
 103438c:	lea    0x253d(%rip),%rdi        # 10368d0 <core_io_file_error.verbs+0x320>
 1034393:	mov    %rbx,%rsi
 1034396:	mov    %rbp,%rdx
 1034399:	vzeroupper
 103439c:	call   1009b80 <myl_core_trap>
 10343a1:	lea    0x2558(%rip),%rdi        # 1036900 <core_io_file_error.verbs+0x350>
 10343a8:	mov    %rbx,%rsi
 10343ab:	xor    %edx,%edx
 10343ad:	vzeroupper
 10343b0:	call   1009b80 <myl_core_trap>
 10343b5:	lea    0x24e4(%rip),%rdi        # 10368a0 <core_io_file_error.verbs+0x2f0>
 10343bc:	mov    %rbx,%rsi
 10343bf:	mov    %rbp,%rdx
 10343c2:	vzeroupper
 10343c5:	call   1009b80 <myl_core_trap>
 10343ca:	mov    %r10,%rdi
 10343cd:	vzeroupper
 10343d0:	call   1032790 <myl_core_free_block>
 10343d5:	jmp    1033e7c <my.app::main+0x10dc>
 10343da:	mov    %r10,%rdi
 10343dd:	vzeroupper
 10343e0:	call   1032790 <myl_core_free_block>
 10343e5:	jmp    1033e22 <my.app::main+0x1082>
 10343ea:	lea    0x232f(%rip),%rdi        # 1036720 <core_io_file_error.verbs+0x170>
 10343f1:	mov    0x20(%rsp),%rsi
 10343f6:	vzeroupper
 10343f9:	call   1009b80 <myl_core_trap>
 10343fe:	lea    0x258b(%rip),%rdi        # 1036990 <core_io_file_error.verbs+0x3e0>
 1034405:	xor    %esi,%esi
 1034407:	xor    %edx,%edx
 1034409:	vzeroupper
 103440c:	call   1009b80 <myl_core_trap>
 1034411:	lea    0x22d8(%rip),%rdi        # 10366f0 <core_io_file_error.verbs+0x140>
 1034418:	mov    %r14,%rdx
 103441b:	vzeroupper
 103441e:	call   1009b80 <myl_core_trap>
 1034423:	lea    0x21d6(%rip),%rdi        # 1036600 <core_io_file_error.verbs+0x50>
 103442a:	mov    $0x1,%esi
 103442f:	call   1009b80 <myl_core_trap>
 1034434:	lea    0x21f5(%rip),%rdi        # 1036630 <core_io_file_error.verbs+0x80>
 103443b:	mov    $0x2,%esi
 1034440:	call   1009b80 <myl_core_trap>
 1034445:	lea    0x2274(%rip),%rdi        # 10366c0 <core_io_file_error.verbs+0x110>
 103444c:	mov    %rax,%rsi
 103444f:	call   1009b80 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
