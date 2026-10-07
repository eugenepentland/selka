
.mylang-cache/s4-emission/paired-budget64-01-whole/row_lox_eval:     file format elf64-x86-64


Disassembly of section .text:

0000000001032c00 <main>:
 1032c00:	push   %rbp
 1032c01:	push   %r15
 1032c03:	push   %r14
 1032c05:	push   %r13
 1032c07:	push   %r12
 1032c09:	push   %rbx
 1032c0a:	sub    $0x68,%rsp
 1032c0e:	call   1009630 <myl_core_args>
 1032c13:	mov    %rax,%r14
 1032c16:	call   1022040 <myl_core_host_grant>
 1032c1b:	mov    $0x2,%ebx
 1032c20:	cmpq   $0x3,0x8(%r14)
 1032c25:	jne    1033cf2 <main+0x10f2>
 1032c2b:	mov    %rax,%r15
 1032c2e:	mov    0x20(%r14),%rdi
 1032c32:	call   1032a00 <my.workload::parse_number>
 1032c37:	mov    %rax,0x8(%rsp)
 1032c3c:	mov    0x8(%r14),%rdx
 1032c40:	cmp    $0x1,%rdx
 1032c44:	jbe    10342a8 <main+0x16a8>
 1032c4a:	mov    0x28(%r14),%rdi
 1032c4e:	call   1032a00 <my.workload::parse_number>
 1032c53:	mov    0x8(%r14),%rdx
 1032c57:	cmp    $0x2,%rdx
 1032c5b:	jbe    10342b9 <main+0x16b9>
 1032c61:	mov    %rax,%r12
 1032c64:	mov    0x30(%r14),%rdi
 1032c68:	call   1032a00 <my.workload::parse_number>
 1032c6d:	cmpq   $0x2,0x8(%rsp)
 1032c73:	setl   %dl
 1032c76:	test   %r12,%r12
 1032c79:	setle  %cl
 1032c7c:	or     %dl,%cl
 1032c7e:	mov    %rax,0x30(%rsp)
 1032c83:	add    $0xfffffffffff0bdbf,%rax
 1032c89:	cmp    $0xfffffffffff0bdc0,%rax
 1032c8f:	setb   %al
 1032c92:	or     %cl,%al
 1032c94:	jne    1033cf2 <main+0x10f2>
 1032c9a:	lea    0x26ecf(%rip),%rcx        # 1059b70 <myl_core_free_lists>
 1032ca1:	mov    0xa0(%rcx),%rax
 1032ca8:	test   %rax,%rax
 1032cab:	mov    %r12,0x50(%rsp)
 1032cb0:	je     1033d81 <main+0x1181>
 1032cb6:	mov    (%rax),%rdx
 1032cb9:	mov    %rdx,0xa0(%rcx)
 1032cc0:	vmovaps -0x2f628(%rip),%ymm0        # 10036a0 <core_io_raw_layout+0x120>
 1032cc8:	vmovups %ymm0,(%rax)
 1032ccc:	mov    $0x26,%ecx
 1032cd1:	xor    %esi,%esi
 1032cd3:	mov    %rsi,%rdx
 1032cd6:	shl    $0x4,%rdx
 1032cda:	inc    %rsi
 1032cdd:	vxorps %xmm0,%xmm0,%xmm0
 1032ce1:	vmovups %xmm0,0x20(%rax,%rdx,1)
 1032ce7:	mov    %rsi,0x8(%rax)
 1032ceb:	cmp    %rcx,%rsi
 1032cee:	jae    1033dbb <main+0x11bb>
 1032cf4:	mov    %rsi,%rdx
 1032cf7:	shl    $0x4,%rdx
 1032cfb:	movq   $0x4,0x20(%rax,%rdx,1)
 1032d04:	movq   $0x0,0x28(%rax,%rdx,1)
 1032d0d:	inc    %rsi
 1032d10:	mov    %rsi,0x8(%rax)
 1032d14:	cmp    %rcx,%rsi
 1032d17:	jae    1033dd8 <main+0x11d8>
 1032d1d:	mov    %rsi,%rdx
 1032d20:	shl    $0x4,%rdx
 1032d24:	movq   $0x2,0x20(%rax,%rdx,1)
 1032d2d:	movq   $0x0,0x28(%rax,%rdx,1)
 1032d36:	inc    %rsi
 1032d39:	mov    %rsi,0x8(%rax)
 1032d3d:	cmp    %rcx,%rsi
 1032d40:	jae    1033df5 <main+0x11f5>
 1032d46:	mov    %rsi,%rdx
 1032d49:	shl    $0x4,%rdx
 1032d4d:	movq   $0x4,0x20(%rax,%rdx,1)
 1032d56:	movq   $0x1,0x28(%rax,%rdx,1)
 1032d5f:	inc    %rsi
 1032d62:	mov    %rsi,0x8(%rax)
 1032d66:	cmp    %rcx,%rsi
 1032d69:	jae    1033e12 <main+0x1212>
 1032d6f:	mov    %rsi,%rdx
 1032d72:	shl    $0x4,%rdx
 1032d76:	movq   $0x3,0x20(%rax,%rdx,1)
 1032d7f:	movq   $0x1,0x28(%rax,%rdx,1)
 1032d88:	inc    %rsi
 1032d8b:	mov    %rsi,0x8(%rax)
 1032d8f:	cmp    %rcx,%rsi
 1032d92:	jae    1033e2f <main+0x122f>
 1032d98:	mov    %rsi,%rdx
 1032d9b:	shl    $0x4,%rdx
 1032d9f:	movq   $0x1,0x20(%rax,%rdx,1)
 1032da8:	movq   $0x0,0x28(%rax,%rdx,1)
 1032db1:	inc    %rsi
 1032db4:	mov    %rsi,0x8(%rax)
 1032db8:	cmp    %rcx,%rsi
 1032dbb:	jae    1033e4c <main+0x124c>
 1032dc1:	mov    %rsi,%rdx
 1032dc4:	shl    $0x4,%rdx
 1032dc8:	movq   $0x8,0x20(%rax,%rdx,1)
 1032dd1:	movq   $0x0,0x28(%rax,%rdx,1)
 1032dda:	inc    %rsi
 1032ddd:	mov    %rsi,0x8(%rax)
 1032de1:	cmp    %rcx,%rsi
 1032de4:	jae    1033e69 <main+0x1269>
 1032dea:	mov    %rsi,%rdx
 1032ded:	shl    $0x4,%rdx
 1032df1:	movq   $0xa,0x20(%rax,%rdx,1)
 1032dfa:	movq   $0x1d,0x28(%rax,%rdx,1)
 1032e03:	inc    %rsi
 1032e06:	mov    %rsi,0x8(%rax)
 1032e0a:	cmp    %rcx,%rsi
 1032e0d:	jae    1033e86 <main+0x1286>
 1032e13:	mov    %rsi,%rdx
 1032e16:	shl    $0x4,%rdx
 1032e1a:	movq   $0x3,0x20(%rax,%rdx,1)
 1032e23:	movq   $0x1,0x28(%rax,%rdx,1)
 1032e2c:	inc    %rsi
 1032e2f:	mov    %rsi,0x8(%rax)
 1032e33:	cmp    %rcx,%rsi
 1032e36:	jae    1033ea3 <main+0x12a3>
 1032e3c:	mov    %rsi,%rdx
 1032e3f:	shl    $0x4,%rdx
 1032e43:	movq   $0x2,0x20(%rax,%rdx,1)
 1032e4c:	movq   $0x2,0x28(%rax,%rdx,1)
 1032e55:	inc    %rsi
 1032e58:	mov    %rsi,0x8(%rax)
 1032e5c:	cmp    %rcx,%rsi
 1032e5f:	jae    1033ec0 <main+0x12c0>
 1032e65:	mov    %rsi,%rdx
 1032e68:	shl    $0x4,%rdx
 1032e6c:	movq   $0x7,0x20(%rax,%rdx,1)
 1032e75:	movq   $0x0,0x28(%rax,%rdx,1)
 1032e7e:	inc    %rsi
 1032e81:	mov    %rsi,0x8(%rax)
 1032e85:	cmp    %rcx,%rsi
 1032e88:	jae    1033edd <main+0x12dd>
 1032e8e:	mov    %rsi,%rdx
 1032e91:	shl    $0x4,%rdx
 1032e95:	movq   $0x2,0x20(%rax,%rdx,1)
 1032e9e:	movq   $0x0,0x28(%rax,%rdx,1)
 1032ea7:	inc    %rsi
 1032eaa:	mov    %rsi,0x8(%rax)
 1032eae:	cmp    %rcx,%rsi
 1032eb1:	jae    1033efa <main+0x12fa>
 1032eb7:	mov    %rsi,%rdx
 1032eba:	shl    $0x4,%rdx
 1032ebe:	movq   $0x9,0x20(%rax,%rdx,1)
 1032ec7:	movq   $0x0,0x28(%rax,%rdx,1)
 1032ed0:	inc    %rsi
 1032ed3:	mov    %rsi,0x8(%rax)
 1032ed7:	cmp    %rcx,%rsi
 1032eda:	jae    1033f17 <main+0x1317>
 1032ee0:	mov    %rsi,%rdx
 1032ee3:	shl    $0x4,%rdx
 1032ee7:	movq   $0xa,0x20(%rax,%rdx,1)
 1032ef0:	movq   $0x12,0x28(%rax,%rdx,1)
 1032ef9:	inc    %rsi
 1032efc:	mov    %rsi,0x8(%rax)
 1032f00:	cmp    %rcx,%rsi
 1032f03:	jae    1033f34 <main+0x1334>
 1032f09:	mov    %rsi,%rdx
 1032f0c:	shl    $0x4,%rdx
 1032f10:	movq   $0x3,0x20(%rax,%rdx,1)
 1032f19:	movq   $0x0,0x28(%rax,%rdx,1)
 1032f22:	inc    %rsi
 1032f25:	mov    %rsi,0x8(%rax)
 1032f29:	cmp    %rcx,%rsi
 1032f2c:	jae    1033f51 <main+0x1351>
 1032f32:	mov    %rsi,%rdx
 1032f35:	shl    $0x4,%rdx
 1032f39:	movq   $0xc,0x20(%rax,%rdx,1)
 1032f42:	movq   $0x1f,0x28(%rax,%rdx,1)
 1032f4b:	inc    %rsi
 1032f4e:	mov    %rsi,0x8(%rax)
 1032f52:	cmp    %rcx,%rsi
 1032f55:	jae    1033f6e <main+0x136e>
 1032f5b:	mov    %rsi,%rdx
 1032f5e:	shl    $0x4,%rdx
 1032f62:	movq   $0x4,0x20(%rax,%rdx,1)
 1032f6b:	movq   $0x0,0x28(%rax,%rdx,1)
 1032f74:	inc    %rsi
 1032f77:	mov    %rsi,0x8(%rax)
 1032f7b:	cmp    %rcx,%rsi
 1032f7e:	jae    1033f8b <main+0x138b>
 1032f84:	mov    %rsi,%rdx
 1032f87:	shl    $0x4,%rdx
 1032f8b:	movq   $0xb,0x20(%rax,%rdx,1)
 1032f94:	movq   $0x18,0x28(%rax,%rdx,1)
 1032f9d:	inc    %rsi
 1032fa0:	mov    %rsi,0x8(%rax)
 1032fa4:	cmp    %rcx,%rsi
 1032fa7:	jae    1033fa8 <main+0x13a8>
 1032fad:	mov    %rsi,%rdx
 1032fb0:	shl    $0x4,%rdx
 1032fb4:	movq   $0x3,0x20(%rax,%rdx,1)
 1032fbd:	movq   $0x0,0x28(%rax,%rdx,1)
 1032fc6:	inc    %rsi
 1032fc9:	mov    %rsi,0x8(%rax)
 1032fcd:	cmp    %rcx,%rsi
 1032fd0:	jae    1033fc5 <main+0x13c5>
 1032fd6:	mov    %rsi,%rdx
 1032fd9:	shl    $0x4,%rdx
 1032fdd:	movq   $0x3,0x20(%rax,%rdx,1)
 1032fe6:	movq   $0x1,0x28(%rax,%rdx,1)
 1032fef:	inc    %rsi
 1032ff2:	mov    %rsi,0x8(%rax)
 1032ff6:	cmp    %rcx,%rsi
 1032ff9:	jae    1033fe2 <main+0x13e2>
 1032fff:	mov    %rsi,%rdx
 1033002:	shl    $0x4,%rdx
 1033006:	movq   $0x5,0x20(%rax,%rdx,1)
 103300f:	movq   $0x0,0x28(%rax,%rdx,1)
 1033018:	inc    %rsi
 103301b:	mov    %rsi,0x8(%rax)
 103301f:	cmp    %rcx,%rsi
 1033022:	jae    1033fff <main+0x13ff>
 1033028:	mov    %rsi,%rdx
 103302b:	shl    $0x4,%rdx
 103302f:	movq   $0x2,0x20(%rax,%rdx,1)
 1033038:	movq   $0xf4243,0x28(%rax,%rdx,1)
 1033041:	inc    %rsi
 1033044:	mov    %rsi,0x8(%rax)
 1033048:	cmp    %rcx,%rsi
 103304b:	jae    103401c <main+0x141c>
 1033051:	mov    %rsi,%rdx
 1033054:	shl    $0x4,%rdx
 1033058:	movq   $0x7,0x20(%rax,%rdx,1)
 1033061:	movq   $0x0,0x28(%rax,%rdx,1)
 103306a:	inc    %rsi
 103306d:	mov    %rsi,0x8(%rax)
 1033071:	cmp    %rcx,%rsi
 1033074:	jae    1034039 <main+0x1439>
 103307a:	mov    %rsi,%rdx
 103307d:	shl    $0x4,%rdx
 1033081:	movq   $0x4,0x20(%rax,%rdx,1)
 103308a:	movq   $0x0,0x28(%rax,%rdx,1)
 1033093:	inc    %rsi
 1033096:	mov    %rsi,0x8(%rax)
 103309a:	cmp    %rcx,%rsi
 103309d:	jae    1034056 <main+0x1456>
 10330a3:	mov    %rsi,%rdx
 10330a6:	shl    $0x4,%rdx
 10330aa:	movq   $0x3,0x20(%rax,%rdx,1)
 10330b3:	movq   $0x1,0x28(%rax,%rdx,1)
 10330bc:	inc    %rsi
 10330bf:	mov    %rsi,0x8(%rax)
 10330c3:	cmp    %rcx,%rsi
 10330c6:	jae    1034073 <main+0x1473>
 10330cc:	mov    %rsi,%rdx
 10330cf:	shl    $0x4,%rdx
 10330d3:	movq   $0x2,0x20(%rax,%rdx,1)
 10330dc:	movq   $0x1,0x28(%rax,%rdx,1)
 10330e5:	inc    %rsi
 10330e8:	mov    %rsi,0x8(%rax)
 10330ec:	cmp    %rcx,%rsi
 10330ef:	jae    1034090 <main+0x1490>
 10330f5:	mov    %rsi,%rdx
 10330f8:	shl    $0x4,%rdx
 10330fc:	movq   $0x5,0x20(%rax,%rdx,1)
 1033105:	movq   $0x0,0x28(%rax,%rdx,1)
 103310e:	inc    %rsi
 1033111:	mov    %rsi,0x8(%rax)
 1033115:	cmp    %rcx,%rsi
 1033118:	jae    10340ad <main+0x14ad>
 103311e:	mov    %rsi,%rdx
 1033121:	shl    $0x4,%rdx
 1033125:	movq   $0x4,0x20(%rax,%rdx,1)
 103312e:	movq   $0x1,0x28(%rax,%rdx,1)
 1033137:	inc    %rsi
 103313a:	mov    %rsi,0x8(%rax)
 103313e:	cmp    %rcx,%rsi
 1033141:	jae    10340ca <main+0x14ca>
 1033147:	mov    %rsi,%rdx
 103314a:	shl    $0x4,%rdx
 103314e:	movq   $0xb,0x20(%rax,%rdx,1)
 1033157:	movq   $0x4,0x28(%rax,%rdx,1)
 1033160:	inc    %rsi
 1033163:	mov    %rsi,0x8(%rax)
 1033167:	cmp    %rcx,%rsi
 103316a:	jae    10340e7 <main+0x14e7>
 1033170:	mov    %rsi,%rdx
 1033173:	shl    $0x4,%rdx
 1033177:	movq   $0x3,0x20(%rax,%rdx,1)
 1033180:	movq   $0x0,0x28(%rax,%rdx,1)
 1033189:	inc    %rsi
 103318c:	mov    %rsi,0x8(%rax)
 1033190:	cmp    %rcx,%rsi
 1033193:	jae    1034104 <main+0x1504>
 1033199:	mov    %rsi,%rdx
 103319c:	shl    $0x4,%rdx
 10331a0:	movq   $0xe,0x20(%rax,%rdx,1)
 10331a9:	movq   $0x0,0x28(%rax,%rdx,1)
 10331b2:	inc    %rsi
 10331b5:	mov    %rsi,0x8(%rax)
 10331b9:	cmp    %rcx,%rsi
 10331bc:	jae    1034121 <main+0x1521>
 10331c2:	mov    %rsi,%rdx
 10331c5:	shl    $0x4,%rdx
 10331c9:	movq   $0x2,0x20(%rax,%rdx,1)
 10331d2:	movq   $0x3,0x28(%rax,%rdx,1)
 10331db:	inc    %rsi
 10331de:	mov    %rsi,0x8(%rax)
 10331e2:	cmp    %rcx,%rsi
 10331e5:	jae    103413e <main+0x153e>
 10331eb:	mov    %rsi,%rdx
 10331ee:	shl    $0x4,%rdx
 10331f2:	movq   $0x6,0x20(%rax,%rdx,1)
 10331fb:	movq   $0x0,0x28(%rax,%rdx,1)
 1033204:	inc    %rsi
 1033207:	mov    %rsi,0x8(%rax)
 103320b:	cmp    %rcx,%rsi
 103320e:	jae    103415b <main+0x155b>
 1033214:	mov    %rsi,%rdx
 1033217:	shl    $0x4,%rdx
 103321b:	movq   $0x2,0x20(%rax,%rdx,1)
 1033224:	movq   $0x7,0x28(%rax,%rdx,1)
 103322d:	inc    %rsi
 1033230:	mov    %rsi,0x8(%rax)
 1033234:	cmp    %rcx,%rsi
 1033237:	jae    1034178 <main+0x1578>
 103323d:	mov    %rsi,%rdx
 1033240:	shl    $0x4,%rdx
 1033244:	movq   $0x5,0x20(%rax,%rdx,1)
 103324d:	movq   $0x0,0x28(%rax,%rdx,1)
 1033256:	inc    %rsi
 1033259:	mov    %rsi,0x8(%rax)
 103325d:	cmp    %rcx,%rsi
 1033260:	jae    1034195 <main+0x1595>
 1033266:	mov    %rsi,%rdx
 1033269:	shl    $0x4,%rdx
 103326d:	movq   $0x2,0x20(%rax,%rdx,1)
 1033276:	movq   $0xf4243,0x28(%rax,%rdx,1)
 103327f:	inc    %rsi
 1033282:	mov    %rsi,0x8(%rax)
 1033286:	cmp    %rcx,%rsi
 1033289:	jae    10341b2 <main+0x15b2>
 103328f:	mov    %rsi,%rdx
 1033292:	shl    $0x4,%rdx
 1033296:	movq   $0x7,0x20(%rax,%rdx,1)
 103329f:	movq   $0x0,0x28(%rax,%rdx,1)
 10332a8:	inc    %rsi
 10332ab:	mov    %rsi,0x8(%rax)
 10332af:	cmp    %rcx,%rsi
 10332b2:	mov    %r14,0x28(%rsp)
 10332b7:	jae    10341cf <main+0x15cf>
 10332bd:	mov    %rax,0x10(%rsp)
 10332c2:	lea    0x20(%rax),%rbx
 10332c6:	mov    %rsi,%rcx
 10332c9:	shl    $0x4,%rcx
 10332cd:	movq   $0xd,0x20(%rax,%rcx,1)
 10332d6:	movq   $0x0,0x28(%rax,%rcx,1)
 10332df:	inc    %rsi
 10332e2:	mov    %rsi,0x8(%rax)
 10332e6:	lea    0x25a3(%rip),%rdi        # 1035890 <core_io_file_error.verbs+0xb0>
 10332ed:	vzeroupper
 10332f0:	call   100a100 <myl_core_io_at>
 10332f5:	mov    %r15,%rdi
 10332f8:	mov    %r15,0x48(%rsp)
 10332fd:	call   1022070 <myl_core_host_check>
 1033302:	call   10342e0 <runtime_bench_now>
 1033307:	xor    %r11d,%r11d
 103330a:	mov    0x10(%rsp),%r10
 103330f:	mov    %rax,0x40(%rsp)
 1033314:	movabs $0x100000000000001,%r12
 103331e:	vxorps %xmm1,%xmm1,%xmm1
 1033322:	xor    %ebp,%ebp
 1033324:	xor    %edx,%edx
 1033326:	lea    0x26843(%rip),%r9        # 1059b70 <myl_core_free_lists>
 103332d:	mov    0x8(%rsp),%r8
 1033332:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033340:	mov    0x30(%rsp),%rax
 1033345:	add    %rdx,%rax
 1033348:	mov    %rax,0x60(%rsp)
 103334d:	jo     103426c <main+0x166c>
 1033353:	mov    0x8(%r9),%r13
 1033357:	test   %r13,%r13
 103335a:	je     1033a7c <main+0xe7c>
 1033360:	mov    0x0(%r13),%rax
 1033364:	mov    %rax,0x8(%r9)
 1033368:	mov    %r12,0x0(%r13)
 103336c:	vmovups %xmm1,0x8(%r13)
 1033372:	movq   $0x0,0x18(%r13)
 103337a:	mov    0x8(%r9),%rcx
 103337e:	test   %rcx,%rcx
 1033381:	lea    -0x2ed78(%rip),%r15        # 1004610 <core_number_pairs+0xe0>
 1033388:	je     1033ab1 <main+0xeb1>
 103338e:	mov    (%rcx),%rax
 1033391:	mov    %rax,0x8(%r9)
 1033395:	mov    %r12,(%rcx)
 1033398:	vmovups %xmm1,0x8(%rcx)
 103339d:	mov    %rcx,0x18(%rsp)
 10333a2:	movq   $0x0,0x18(%rcx)
 10333aa:	mov    0x10(%r9),%rdi
 10333ae:	test   %rdi,%rdi
 10333b1:	je     1033ae8 <main+0xee8>
 10333b7:	mov    (%rdi),%rax
 10333ba:	mov    %rax,0x10(%r9)
 10333be:	vmovaps -0x2fce6(%rip),%ymm0        # 10036e0 <core_io_raw_layout+0x160>
 10333c6:	vmovups %ymm0,(%rdi)
 10333ca:	mov    $0x4,%ecx
 10333cf:	xor    %esi,%esi
 10333d1:	movq   $0x0,0x20(%rdi,%rsi,8)
 10333da:	inc    %rsi
 10333dd:	mov    %rsi,0x8(%rdi)
 10333e1:	cmp    %rcx,%rsi
 10333e4:	jae    1033b46 <main+0xf46>
 10333ea:	movq   $0x0,0x20(%rdi,%rsi,8)
 10333f3:	inc    %rsi
 10333f6:	mov    %rsi,0x8(%rdi)
 10333fa:	cmpq   $0x0,0x8(%r10)
 10333ff:	je     1033c2e <main+0x102e>
 1033405:	mov    %rbp,0x38(%rsp)
 103340a:	mov    %rdx,0x58(%rsp)
 103340f:	xor    %esi,%esi
 1033411:	xor    %eax,%eax
 1033413:	mov    %rax,%rbp
 1033416:	jmp    1033487 <main+0x887>
 1033418:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033427:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033436:	cs nopw 0x0(%rax,%rax,1)
 1033440:	mov    0x8(%r13),%rax
 1033444:	cmp    0x10(%r13),%rax
 1033448:	jae    10337da <main+0xbda>
 103344e:	mov    %rax,%rcx
 1033451:	shl    $0x4,%rcx
 1033455:	movq   $0x0,0x20(%r13,%rcx,1)
 103345e:	mov    %r14,0x28(%r13,%rcx,1)
 1033463:	inc    %rax
 1033466:	mov    %rax,0x8(%r13)
 103346a:	mov    0x8(%r10),%rdx
 103346e:	mov    %rbp,%rsi
 1033471:	sar    $0x3f,%rsi
 1033475:	and    %rdx,%rsi
 1033478:	add    %rbp,%rsi
 103347b:	mov    %rbp,%rax
 103347e:	cmp    %rdx,%rsi
 1033481:	jae    1033c32 <main+0x1032>
 1033487:	inc    %rbp
 103348a:	jo     1033d13 <main+0x1113>
 1033490:	shl    $0x4,%rsi
 1033494:	mov    (%rbx,%rsi,1),%rcx
 1033498:	mov    0x8(%rbx,%rsi,1),%r14
 103349d:	cmp    $0x4,%rcx
 10334a1:	ja     1033577 <main+0x977>
 10334a7:	movslq (%r15,%rcx,4),%rax
 10334ab:	add    %r15,%rax
 10334ae:	jmp    *%rax
 10334b0:	mov    0x8(%r13),%rax
 10334b4:	cmp    0x10(%r13),%rax
 10334b8:	jae    1033814 <main+0xc14>
 10334be:	mov    %rax,%rcx
 10334c1:	shl    $0x4,%rcx
 10334c5:	movq   $0x0,0x20(%r13,%rcx,1)
 10334ce:	mov    0x60(%rsp),%rdx
 10334d3:	mov    %rdx,0x28(%r13,%rcx,1)
 10334d8:	jmp    1033463 <main+0x863>
 10334da:	mov    0x8(%r13),%rdx
 10334de:	test   %rdx,%rdx
 10334e1:	je     1033d39 <main+0x1139>
 10334e7:	dec    %rdx
 10334ea:	mov    %rdx,%rax
 10334ed:	shl    $0x4,%rax
 10334f1:	movzbl 0x20(%r13,%rax,1),%ecx
 10334f7:	mov    0x28(%r13,%rax,1),%rax
 10334fc:	mov    %rdx,0x8(%r13)
 1033500:	mov    0x8(%rdi),%rdx
 1033504:	mov    %r14,%rsi
 1033507:	sar    $0x3f,%rsi
 103350b:	and    %rdx,%rsi
 103350e:	add    %r14,%rsi
 1033511:	cmp    %rdx,%rsi
 1033514:	jae    1033d2a <main+0x112a>
 103351a:	test   %rcx,%rcx
 103351d:	cmovne %r11,%rax
 1033521:	mov    %rax,0x20(%rdi,%rsi,8)
 1033526:	jmp    103346a <main+0x86a>
 103352b:	mov    0x8(%rdi),%rdx
 103352f:	mov    %r14,%rsi
 1033532:	sar    $0x3f,%rsi
 1033536:	and    %rdx,%rsi
 1033539:	add    %r14,%rsi
 103353c:	cmp    %rdx,%rsi
 103353f:	jae    1033d4c <main+0x114c>
 1033545:	mov    0x20(%rdi,%rsi,8),%r14
 103354a:	jmp    1033440 <main+0x840>
 103354f:	mov    0x8(%r13),%rax
 1033553:	cmp    0x10(%r13),%rax
 1033557:	jae    103384e <main+0xc4e>
 103355d:	mov    %rax,%rcx
 1033560:	shl    $0x4,%rcx
 1033564:	movq   $0x0,0x20(%r13,%rcx,1)
 103356d:	mov    %r8,0x28(%r13,%rcx,1)
 1033572:	jmp    1033463 <main+0x863>
 1033577:	lea    -0x5(%rcx),%rax
 103357b:	cmp    $0x5,%rax
 103357f:	jae    10335a8 <main+0x9a8>
 1033581:	mov    0x8(%r13),%rcx
 1033585:	test   %rcx,%rcx
 1033588:	je     1033d6e <main+0x116e>
 103358e:	lea    -0x1(%rcx),%rdx
 1033592:	mov    %rdx,%rsi
 1033595:	shl    $0x4,%rsi
 1033599:	cmpb   $0x0,0x20(%r13,%rsi,1)
 103359f:	jne    10335ff <main+0x9ff>
 10335a1:	mov    0x28(%r13,%rsi,1),%r14
 10335a6:	jmp    1033602 <main+0xa02>
 10335a8:	add    $0xfffffffffffffff6,%rcx
 10335ac:	cmp    $0x3,%rcx
 10335b0:	ja     1033980 <main+0xd80>
 10335b6:	lea    -0x2ef99(%rip),%rdx        # 1004624 <core_number_pairs+0xf4>
 10335bd:	movslq (%rdx,%rcx,4),%rax
 10335c1:	add    %rdx,%rax
 10335c4:	jmp    *%rax
 10335c6:	mov    0x8(%r13),%rax
 10335ca:	test   %rax,%rax
 10335cd:	je     10341e8 <main+0x15e8>
 10335d3:	dec    %rax
 10335d6:	mov    %rax,%rcx
 10335d9:	shl    $0x4,%rcx
 10335dd:	movzbl 0x20(%r13,%rcx,1),%edx
 10335e3:	mov    0x28(%r13,%rcx,1),%rcx
 10335e8:	mov    %rax,0x8(%r13)
 10335ec:	test   $0x1,%cl
 10335ef:	cmove  %r14,%rbp
 10335f3:	cmp    $0x1,%dl
 10335f6:	cmovne %r14,%rbp
 10335fa:	jmp    103346a <main+0x86a>
 10335ff:	xor    %r14d,%r14d
 1033602:	mov    %rdx,0x8(%r13)
 1033606:	test   %rdx,%rdx
 1033609:	je     1033d5b <main+0x115b>
 103360f:	mov    %rcx,%rdx
 1033612:	shl    $0x4,%rdx
 1033616:	cmpb   $0x0,0x0(%r13,%rdx,1)
 103361c:	jne    1033625 <main+0xa25>
 103361e:	mov    0x8(%r13,%rdx,1),%r12
 1033623:	jmp    1033628 <main+0xa28>
 1033625:	xor    %r12d,%r12d
 1033628:	add    $0xfffffffffffffffe,%rcx
 103362c:	mov    %rcx,0x8(%r13)
 1033630:	cmp    $0x3,%rax
 1033634:	ja     103375b <main+0xb5b>
 103363a:	lea    -0x2f00d(%rip),%rdx        # 1004634 <core_number_pairs+0x104>
 1033641:	movslq (%rdx,%rax,4),%rax
 1033645:	add    %rdx,%rax
 1033648:	jmp    *%rax
 103364a:	mov    %r12,%r15
 103364d:	add    %r14,%r15
 1033650:	jno    103371a <main+0xb1a>
 1033656:	jmp    1034237 <main+0x1637>
 103365b:	mov    0x18(%rsp),%rax
 1033660:	mov    0x8(%rax),%rcx
 1033664:	cmp    0x10(%rax),%rcx
 1033668:	jae    1033888 <main+0xc88>
 103366e:	mov    %rbp,0x20(%rax,%rcx,8)
 1033673:	inc    %rcx
 1033676:	mov    %rax,0x18(%rsp)
 103367b:	mov    %rcx,0x8(%rax)
 103367f:	mov    %r14,%rbp
 1033682:	jmp    103346a <main+0x86a>
 1033687:	mov    0x18(%rsp),%rcx
 103368c:	mov    0x8(%rcx),%rax
 1033690:	test   %rax,%rax
 1033693:	je     10341fb <main+0x15fb>
 1033699:	mov    0x18(%rcx,%rax,8),%rbp
 103369e:	dec    %rax
 10336a1:	mov    %rax,0x8(%rcx)
 10336a5:	jmp    103346a <main+0x86a>
 10336aa:	mov    %r14,%rbp
 10336ad:	jmp    103346a <main+0x86a>
 10336b2:	test   %r14,%r14
 10336b5:	je     1034223 <main+0x1623>
 10336bb:	cmp    $0xffffffffffffffff,%r14
 10336bf:	mov    %r14,%rsi
 10336c2:	mov    $0x1,%eax
 10336c7:	cmove  %rax,%rsi
 10336cb:	mov    %r12,%rax
 10336ce:	or     %rsi,%rax
 10336d1:	shr    $0x20,%rax
 10336d5:	je     103378a <main+0xb8a>
 10336db:	mov    %r12,%rax
 10336de:	cqto
 10336e0:	idiv   %rsi
 10336e3:	jmp    1033791 <main+0xb91>
 10336e8:	cmp    0x10(%r13),%rcx
 10336ec:	jae    10338bf <main+0xcbf>
 10336f2:	mov    %rcx,%rax
 10336f5:	shl    $0x4,%rax
 10336f9:	cmp    %r14,%r12
 10336fc:	movq   $0x1,0x20(%r13,%rax,1)
 1033705:	setl   0x28(%r13,%rax,1)
 103370b:	jmp    103377e <main+0xb7e>
 103370d:	mov    %r12,%r15
 1033710:	imul   %r14,%r15
 1033714:	jo     103420e <main+0x160e>
 103371a:	cmp    0x10(%r13),%rcx
 103371e:	jb     10337b2 <main+0xbb2>
 1033724:	mov    $0x10,%esi
 1033729:	mov    %rdi,%r14
 103372c:	mov    %r13,%rdi
 103372f:	vzeroupper
 1033732:	call   1009130 <myl_core_list_grow>
 1033737:	vxorps %xmm1,%xmm1,%xmm1
 103373b:	xor    %r11d,%r11d
 103373e:	mov    0x10(%rsp),%r10
 1033743:	mov    0x8(%rsp),%r8
 1033748:	lea    0x26421(%rip),%r9        # 1059b70 <myl_core_free_lists>
 103374f:	mov    %r14,%rdi
 1033752:	mov    %rax,%r13
 1033755:	mov    0x8(%rax),%rcx
 1033759:	jmp    10337b2 <main+0xbb2>
 103375b:	cmp    0x10(%r13),%rcx
 103375f:	jae    10338fd <main+0xcfd>
 1033765:	mov    %rcx,%rax
 1033768:	shl    $0x4,%rax
 103376c:	cmp    %r14,%r12
 103376f:	movq   $0x1,0x20(%r13,%rax,1)
 1033778:	sete   0x28(%r13,%rax,1)
 103377e:	inc    %rcx
 1033781:	mov    %rcx,0x8(%r13)
 1033785:	jmp    103346a <main+0x86a>
 103378a:	mov    %r12d,%eax
 103378d:	xor    %edx,%edx
 103378f:	div    %esi
 1033791:	mov    %rdx,%r15
 1033794:	xor    %r14,%r15
 1033797:	sar    $0x3f,%r15
 103379b:	and    %r14,%r15
 103379e:	test   %rdx,%rdx
 10337a1:	cmove  %rdx,%r15
 10337a5:	cmp    0x10(%r13),%rcx
 10337a9:	jae    103393b <main+0xd3b>
 10337af:	add    %rdx,%r15
 10337b2:	mov    %rcx,%rax
 10337b5:	shl    $0x4,%rax
 10337b9:	movq   $0x0,0x20(%r13,%rax,1)
 10337c2:	mov    %r15,0x28(%r13,%rax,1)
 10337c7:	inc    %rcx
 10337ca:	mov    %rcx,0x8(%r13)
 10337ce:	lea    -0x2f1c5(%rip),%r15        # 1004610 <core_number_pairs+0xe0>
 10337d5:	jmp    103346a <main+0x86a>
 10337da:	mov    $0x10,%esi
 10337df:	mov    %rdi,%r12
 10337e2:	mov    %r13,%rdi
 10337e5:	vzeroupper
 10337e8:	call   1009130 <myl_core_list_grow>
 10337ed:	vxorps %xmm1,%xmm1,%xmm1
 10337f1:	xor    %r11d,%r11d
 10337f4:	mov    0x10(%rsp),%r10
 10337f9:	mov    0x8(%rsp),%r8
 10337fe:	lea    0x2636b(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033805:	mov    %r12,%rdi
 1033808:	mov    %rax,%r13
 103380b:	mov    0x8(%rax),%rax
 103380f:	jmp    103344e <main+0x84e>
 1033814:	mov    $0x10,%esi
 1033819:	mov    %rdi,%r14
 103381c:	mov    %r13,%rdi
 103381f:	vzeroupper
 1033822:	call   1009130 <myl_core_list_grow>
 1033827:	vxorps %xmm1,%xmm1,%xmm1
 103382b:	xor    %r11d,%r11d
 103382e:	mov    0x10(%rsp),%r10
 1033833:	mov    0x8(%rsp),%r8
 1033838:	lea    0x26331(%rip),%r9        # 1059b70 <myl_core_free_lists>
 103383f:	mov    %r14,%rdi
 1033842:	mov    %rax,%r13
 1033845:	mov    0x8(%rax),%rax
 1033849:	jmp    10334be <main+0x8be>
 103384e:	mov    $0x10,%esi
 1033853:	mov    %rdi,%r14
 1033856:	mov    %r13,%rdi
 1033859:	vzeroupper
 103385c:	call   1009130 <myl_core_list_grow>
 1033861:	vxorps %xmm1,%xmm1,%xmm1
 1033865:	xor    %r11d,%r11d
 1033868:	mov    0x10(%rsp),%r10
 103386d:	mov    0x8(%rsp),%r8
 1033872:	lea    0x262f7(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033879:	mov    %r14,%rdi
 103387c:	mov    %rax,%r13
 103387f:	mov    0x8(%rax),%rax
 1033883:	jmp    103355d <main+0x95d>
 1033888:	mov    $0x8,%esi
 103388d:	mov    %rdi,%r12
 1033890:	mov    %rax,%rdi
 1033893:	vzeroupper
 1033896:	call   1009130 <myl_core_list_grow>
 103389b:	vxorps %xmm1,%xmm1,%xmm1
 103389f:	xor    %r11d,%r11d
 10338a2:	mov    0x10(%rsp),%r10
 10338a7:	mov    0x8(%rsp),%r8
 10338ac:	lea    0x262bd(%rip),%r9        # 1059b70 <myl_core_free_lists>
 10338b3:	mov    %r12,%rdi
 10338b6:	mov    0x8(%rax),%rcx
 10338ba:	jmp    103366e <main+0xa6e>
 10338bf:	mov    $0x10,%esi
 10338c4:	mov    %rdi,0x20(%rsp)
 10338c9:	mov    %r13,%rdi
 10338cc:	vzeroupper
 10338cf:	call   1009130 <myl_core_list_grow>
 10338d4:	vxorps %xmm1,%xmm1,%xmm1
 10338d8:	xor    %r11d,%r11d
 10338db:	mov    0x10(%rsp),%r10
 10338e0:	mov    0x8(%rsp),%r8
 10338e5:	lea    0x26284(%rip),%r9        # 1059b70 <myl_core_free_lists>
 10338ec:	mov    0x20(%rsp),%rdi
 10338f1:	mov    %rax,%r13
 10338f4:	mov    0x8(%rax),%rcx
 10338f8:	jmp    10336f2 <main+0xaf2>
 10338fd:	mov    $0x10,%esi
 1033902:	mov    %rdi,0x20(%rsp)
 1033907:	mov    %r13,%rdi
 103390a:	vzeroupper
 103390d:	call   1009130 <myl_core_list_grow>
 1033912:	vxorps %xmm1,%xmm1,%xmm1
 1033916:	xor    %r11d,%r11d
 1033919:	mov    0x10(%rsp),%r10
 103391e:	mov    0x8(%rsp),%r8
 1033923:	lea    0x26246(%rip),%r9        # 1059b70 <myl_core_free_lists>
 103392a:	mov    0x20(%rsp),%rdi
 103392f:	mov    %rax,%r13
 1033932:	mov    0x8(%rax),%rcx
 1033936:	jmp    1033765 <main+0xb65>
 103393b:	mov    $0x10,%esi
 1033940:	mov    %rdi,%r12
 1033943:	mov    %r13,%rdi
 1033946:	mov    %rdx,%r14
 1033949:	vzeroupper
 103394c:	call   1009130 <myl_core_list_grow>
 1033951:	vxorps %xmm1,%xmm1,%xmm1
 1033955:	xor    %r11d,%r11d
 1033958:	mov    0x10(%rsp),%r10
 103395d:	mov    0x8(%rsp),%r8
 1033962:	lea    0x26207(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033969:	mov    %r12,%rdi
 103396c:	mov    %r14,%rdx
 103396f:	mov    %rax,%r13
 1033972:	mov    0x8(%rax),%rcx
 1033976:	jmp    10337af <main+0xbaf>
 103397b:	nopl   0x0(%rax,%rax,1)
 1033980:	movzbl 0x7(%rdi),%eax
 1033984:	test   %rax,%rax
 1033987:	je     1033b7d <main+0xf7d>
 103398d:	cmpq   $0x0,0x18(%rdi)
 1033992:	jne    1033b7d <main+0xf7d>
 1033998:	mov    (%r9,%rax,8),%rcx
 103399c:	mov    %rcx,(%rdi)
 103399f:	mov    %rdi,(%r9,%rax,8)
 10339a3:	movabs $0x100000000000001,%r12
 10339ad:	mov    0x38(%rsp),%rbp
 10339b2:	mov    0x18(%rsp),%rdi
 10339b7:	movzbl 0x7(%rdi),%eax
 10339bb:	test   %rax,%rax
 10339be:	je     1033ba2 <main+0xfa2>
 10339c4:	cmpq   $0x0,0x18(%rdi)
 10339c9:	jne    1033ba2 <main+0xfa2>
 10339cf:	mov    (%r9,%rax,8),%rcx
 10339d3:	mov    %rcx,(%rdi)
 10339d6:	mov    %rdi,(%r9,%rax,8)
 10339da:	mov    0x8(%r13),%rax
 10339de:	test   %rax,%rax
 10339e1:	je     1034280 <main+0x1680>
 10339e7:	dec    %rax
 10339ea:	mov    %rax,%rcx
 10339ed:	shl    $0x4,%rcx
 10339f1:	movzbl 0x20(%r13,%rcx,1),%r15d
 10339f7:	mov    0x28(%r13,%rcx,1),%r14
 10339fc:	mov    %rax,0x8(%r13)
 1033a00:	movzbl 0x7(%r13),%eax
 1033a05:	test   %rax,%rax
 1033a08:	je     1033bc7 <main+0xfc7>
 1033a0e:	cmpq   $0x0,0x18(%r13)
 1033a13:	jne    1033bc7 <main+0xfc7>
 1033a19:	mov    (%r9,%rax,8),%rcx
 1033a1d:	mov    %rcx,0x0(%r13)
 1033a21:	mov    %r13,(%r9,%rax,8)
 1033a25:	test   %r15,%r15
 1033a28:	cmovne %r11,%r14
 1033a2c:	test   %r14,%r14
 1033a2f:	js     1033bfb <main+0xffb>
 1033a35:	mov    %rbp,%r15
 1033a38:	add    %r14,%r15
 1033a3b:	jo     1034293 <main+0x1693>
 1033a41:	mov    %r15,%rdx
 1033a44:	movabs $0x89705f3112a28fe5,%rax
 1033a4e:	mulx   %rax,%rax,%rax
 1033a53:	shr    $0x1d,%rax
 1033a57:	imul   $0x3b9aca07,%rax,%rax
 1033a5e:	sub    %rax,%r15
 1033a61:	mov    0x58(%rsp),%rdx
 1033a66:	inc    %rdx
 1033a69:	mov    %r15,%rbp
 1033a6c:	cmp    0x50(%rsp),%rdx
 1033a71:	jne    1033340 <main+0x740>
 1033a77:	jmp    1033c1d <main+0x101d>
 1033a7c:	mov    $0x10,%esi
 1033a81:	xor    %edi,%edi
 1033a83:	mov    %rdx,%r14
 1033a86:	vzeroupper
 1033a89:	call   10090c0 <myl_core_list_new_slow>
 1033a8e:	vxorps %xmm1,%xmm1,%xmm1
 1033a92:	mov    %r14,%rdx
 1033a95:	xor    %r11d,%r11d
 1033a98:	mov    0x10(%rsp),%r10
 1033a9d:	mov    0x8(%rsp),%r8
 1033aa2:	lea    0x260c7(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033aa9:	mov    %rax,%r13
 1033aac:	jmp    103337a <main+0x77a>
 1033ab1:	mov    $0x8,%esi
 1033ab6:	xor    %edi,%edi
 1033ab8:	mov    %rdx,%r14
 1033abb:	vzeroupper
 1033abe:	call   10090c0 <myl_core_list_new_slow>
 1033ac3:	vxorps %xmm1,%xmm1,%xmm1
 1033ac7:	mov    %r14,%rdx
 1033aca:	xor    %r11d,%r11d
 1033acd:	mov    0x10(%rsp),%r10
 1033ad2:	mov    0x8(%rsp),%r8
 1033ad7:	lea    0x26092(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033ade:	mov    %rax,0x18(%rsp)
 1033ae3:	jmp    10333aa <main+0x7aa>
 1033ae8:	mov    %rdx,%r14
 1033aeb:	mov    $0x2,%edi
 1033af0:	mov    $0x8,%esi
 1033af5:	vzeroupper
 1033af8:	call   10090c0 <myl_core_list_new_slow>
 1033afd:	mov    %rax,%rdi
 1033b00:	mov    0x8(%rax),%rsi
 1033b04:	mov    0x10(%rax),%rcx
 1033b08:	cmp    %rcx,%rsi
 1033b0b:	jb     1033bef <main+0xfef>
 1033b11:	mov    $0x8,%esi
 1033b16:	call   1009130 <myl_core_list_grow>
 1033b1b:	mov    0x8(%rax),%rsi
 1033b1f:	mov    0x10(%rax),%rcx
 1033b23:	lea    0x26046(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033b2a:	mov    %rax,%rdi
 1033b2d:	mov    0x8(%rsp),%r8
 1033b32:	mov    0x10(%rsp),%r10
 1033b37:	xor    %r11d,%r11d
 1033b3a:	mov    %r14,%rdx
 1033b3d:	vxorps %xmm1,%xmm1,%xmm1
 1033b41:	jmp    10333d1 <main+0x7d1>
 1033b46:	mov    $0x8,%esi
 1033b4b:	mov    %rdx,%r14
 1033b4e:	vzeroupper
 1033b51:	call   1009130 <myl_core_list_grow>
 1033b56:	vxorps %xmm1,%xmm1,%xmm1
 1033b5a:	mov    %r14,%rdx
 1033b5d:	xor    %r11d,%r11d
 1033b60:	mov    0x10(%rsp),%r10
 1033b65:	mov    0x8(%rsp),%r8
 1033b6a:	lea    0x25fff(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033b71:	mov    %rax,%rdi
 1033b74:	mov    0x8(%rax),%rsi
 1033b78:	jmp    10333ea <main+0x7ea>
 1033b7d:	vzeroupper
 1033b80:	call   10323d0 <myl_core_free_block>
 1033b85:	vxorps %xmm1,%xmm1,%xmm1
 1033b89:	xor    %r11d,%r11d
 1033b8c:	mov    0x10(%rsp),%r10
 1033b91:	mov    0x8(%rsp),%r8
 1033b96:	lea    0x25fd3(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033b9d:	jmp    10339a3 <main+0xda3>
 1033ba2:	vzeroupper
 1033ba5:	call   10323d0 <myl_core_free_block>
 1033baa:	vxorps %xmm1,%xmm1,%xmm1
 1033bae:	xor    %r11d,%r11d
 1033bb1:	mov    0x10(%rsp),%r10
 1033bb6:	mov    0x8(%rsp),%r8
 1033bbb:	lea    0x25fae(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033bc2:	jmp    10339da <main+0xdda>
 1033bc7:	mov    %r13,%rdi
 1033bca:	vzeroupper
 1033bcd:	call   10323d0 <myl_core_free_block>
 1033bd2:	vxorps %xmm1,%xmm1,%xmm1
 1033bd6:	xor    %r11d,%r11d
 1033bd9:	mov    0x10(%rsp),%r10
 1033bde:	mov    0x8(%rsp),%r8
 1033be3:	lea    0x25f86(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033bea:	jmp    1033a25 <main+0xe25>
 1033bef:	lea    0x25f7a(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033bf6:	jmp    1033b2d <main+0xf2d>
 1033bfb:	mov    (%r10),%eax
 1033bfe:	mov    $0x2,%ebx
 1033c03:	cmp    $0xffffffff,%eax
 1033c06:	je     1033ced <main+0x10ed>
 1033c0c:	dec    %eax
 1033c0e:	mov    0x28(%rsp),%r14
 1033c13:	je     1033c41 <main+0x1041>
 1033c15:	mov    %eax,(%r10)
 1033c18:	jmp    1033cf2 <main+0x10f2>
 1033c1d:	mov    (%r10),%eax
 1033c20:	cmp    $0xffffffff,%eax
 1033c23:	je     1033c8e <main+0x108e>
 1033c25:	dec    %eax
 1033c27:	je     1033c6a <main+0x106a>
 1033c29:	mov    %eax,(%r10)
 1033c2c:	jmp    1033c8e <main+0x108e>
 1033c2e:	xor    %edx,%edx
 1033c30:	xor    %esi,%esi
 1033c32:	lea    0x1d47(%rip),%rdi        # 1035980 <core_io_file_error.verbs+0x1a0>
 1033c39:	vzeroupper
 1033c3c:	call   10097c0 <myl_core_trap>
 1033c41:	movzbl 0x7(%r10),%eax
 1033c46:	test   %rax,%rax
 1033c49:	je     103424c <main+0x164c>
 1033c4f:	cmpq   $0x0,0x18(%r10)
 1033c54:	jne    103424c <main+0x164c>
 1033c5a:	mov    (%r9,%rax,8),%rcx
 1033c5e:	mov    %rcx,(%r10)
 1033c61:	mov    %r10,(%r9,%rax,8)
 1033c65:	jmp    1033cf2 <main+0x10f2>
 1033c6a:	movzbl 0x7(%r10),%eax
 1033c6f:	test   %rax,%rax
 1033c72:	je     103425c <main+0x165c>
 1033c78:	cmpq   $0x0,0x18(%r10)
 1033c7d:	jne    103425c <main+0x165c>
 1033c83:	mov    (%r9,%rax,8),%rcx
 1033c87:	mov    %rcx,(%r10)
 1033c8a:	mov    %r10,(%r9,%rax,8)
 1033c8e:	lea    0x1c2b(%rip),%rdi        # 10358c0 <core_io_file_error.verbs+0xe0>
 1033c95:	vzeroupper
 1033c98:	call   100a100 <myl_core_io_at>
 1033c9d:	mov    0x48(%rsp),%rdi
 1033ca2:	call   1022070 <myl_core_host_check>
 1033ca7:	call   10342e0 <runtime_bench_now>
 1033cac:	mov    %rax,%r14
 1033caf:	mov    0x40(%rsp),%rdx
 1033cb4:	sub    %rdx,%r14
 1033cb7:	jo     10342ca <main+0x16ca>
 1033cbd:	mov    $0x1,%edi
 1033cc2:	mov    %r15,%rsi
 1033cc5:	call   100a800 <myl_core_print_i64>
 1033cca:	mov    $0x1,%edi
 1033ccf:	call   1008e40 <myl_core_print_sep>
 1033cd4:	mov    $0x1,%edi
 1033cd9:	mov    %r14,%rsi
 1033cdc:	call   100a800 <myl_core_print_i64>
 1033ce1:	mov    $0x1,%edi
 1033ce6:	call   1008f00 <myl_core_print_end>
 1033ceb:	xor    %ebx,%ebx
 1033ced:	mov    0x28(%rsp),%r14
 1033cf2:	mov    %r14,%rdi
 1033cf5:	vzeroupper
 1033cf8:	call   1009600 <myl_core_release>
 1033cfd:	mov    %rbx,%rdi
 1033d00:	add    $0x68,%rsp
 1033d04:	pop    %rbx
 1033d05:	pop    %r12
 1033d07:	pop    %r13
 1033d09:	pop    %r14
 1033d0b:	pop    %r15
 1033d0d:	pop    %rbp
 1033d0e:	jmp    100a110 <myl_core_exit>
 1033d13:	lea    0x1c96(%rip),%rdi        # 10359b0 <core_io_file_error.verbs+0x1d0>
 1033d1a:	mov    $0x1,%edx
 1033d1f:	mov    %rax,%rsi
 1033d22:	vzeroupper
 1033d25:	call   10097c0 <myl_core_trap>
 1033d2a:	lea    0x1d0f(%rip),%rdi        # 1035a40 <core_io_file_error.verbs+0x260>
 1033d31:	vzeroupper
 1033d34:	call   10097c0 <myl_core_trap>
 1033d39:	lea    0x1cd0(%rip),%rdi        # 1035a10 <core_io_file_error.verbs+0x230>
 1033d40:	xor    %esi,%esi
 1033d42:	xor    %edx,%edx
 1033d44:	vzeroupper
 1033d47:	call   10097c0 <myl_core_trap>
 1033d4c:	lea    0x1c8d(%rip),%rdi        # 10359e0 <core_io_file_error.verbs+0x200>
 1033d53:	vzeroupper
 1033d56:	call   10097c0 <myl_core_trap>
 1033d5b:	lea    0x1d3e(%rip),%rdi        # 1035aa0 <core_io_file_error.verbs+0x2c0>
 1033d62:	xor    %esi,%esi
 1033d64:	xor    %edx,%edx
 1033d66:	vzeroupper
 1033d69:	call   10097c0 <myl_core_trap>
 1033d6e:	lea    0x1cfb(%rip),%rdi        # 1035a70 <core_io_file_error.verbs+0x290>
 1033d75:	xor    %esi,%esi
 1033d77:	xor    %edx,%edx
 1033d79:	vzeroupper
 1033d7c:	call   10097c0 <myl_core_trap>
 1033d81:	mov    $0x26,%edi
 1033d86:	mov    $0x10,%esi
 1033d8b:	call   10090c0 <myl_core_list_new_slow>
 1033d90:	mov    0x8(%rax),%rsi
 1033d94:	mov    0x10(%rax),%rcx
 1033d98:	cmp    %rcx,%rsi
 1033d9b:	jb     1032cd3 <main+0xd3>
 1033da1:	mov    $0x10,%esi
 1033da6:	mov    %rax,%rdi
 1033da9:	call   1009130 <myl_core_list_grow>
 1033dae:	mov    0x8(%rax),%rsi
 1033db2:	mov    0x10(%rax),%rcx
 1033db6:	jmp    1032cd3 <main+0xd3>
 1033dbb:	mov    $0x10,%esi
 1033dc0:	mov    %rax,%rdi
 1033dc3:	vzeroupper
 1033dc6:	call   1009130 <myl_core_list_grow>
 1033dcb:	mov    0x8(%rax),%rsi
 1033dcf:	mov    0x10(%rax),%rcx
 1033dd3:	jmp    1032cf4 <main+0xf4>
 1033dd8:	mov    $0x10,%esi
 1033ddd:	mov    %rax,%rdi
 1033de0:	vzeroupper
 1033de3:	call   1009130 <myl_core_list_grow>
 1033de8:	mov    0x8(%rax),%rsi
 1033dec:	mov    0x10(%rax),%rcx
 1033df0:	jmp    1032d1d <main+0x11d>
 1033df5:	mov    $0x10,%esi
 1033dfa:	mov    %rax,%rdi
 1033dfd:	vzeroupper
 1033e00:	call   1009130 <myl_core_list_grow>
 1033e05:	mov    0x8(%rax),%rsi
 1033e09:	mov    0x10(%rax),%rcx
 1033e0d:	jmp    1032d46 <main+0x146>
 1033e12:	mov    $0x10,%esi
 1033e17:	mov    %rax,%rdi
 1033e1a:	vzeroupper
 1033e1d:	call   1009130 <myl_core_list_grow>
 1033e22:	mov    0x8(%rax),%rsi
 1033e26:	mov    0x10(%rax),%rcx
 1033e2a:	jmp    1032d6f <main+0x16f>
 1033e2f:	mov    $0x10,%esi
 1033e34:	mov    %rax,%rdi
 1033e37:	vzeroupper
 1033e3a:	call   1009130 <myl_core_list_grow>
 1033e3f:	mov    0x8(%rax),%rsi
 1033e43:	mov    0x10(%rax),%rcx
 1033e47:	jmp    1032d98 <main+0x198>
 1033e4c:	mov    $0x10,%esi
 1033e51:	mov    %rax,%rdi
 1033e54:	vzeroupper
 1033e57:	call   1009130 <myl_core_list_grow>
 1033e5c:	mov    0x8(%rax),%rsi
 1033e60:	mov    0x10(%rax),%rcx
 1033e64:	jmp    1032dc1 <main+0x1c1>
 1033e69:	mov    $0x10,%esi
 1033e6e:	mov    %rax,%rdi
 1033e71:	vzeroupper
 1033e74:	call   1009130 <myl_core_list_grow>
 1033e79:	mov    0x8(%rax),%rsi
 1033e7d:	mov    0x10(%rax),%rcx
 1033e81:	jmp    1032dea <main+0x1ea>
 1033e86:	mov    $0x10,%esi
 1033e8b:	mov    %rax,%rdi
 1033e8e:	vzeroupper
 1033e91:	call   1009130 <myl_core_list_grow>
 1033e96:	mov    0x8(%rax),%rsi
 1033e9a:	mov    0x10(%rax),%rcx
 1033e9e:	jmp    1032e13 <main+0x213>
 1033ea3:	mov    $0x10,%esi
 1033ea8:	mov    %rax,%rdi
 1033eab:	vzeroupper
 1033eae:	call   1009130 <myl_core_list_grow>
 1033eb3:	mov    0x8(%rax),%rsi
 1033eb7:	mov    0x10(%rax),%rcx
 1033ebb:	jmp    1032e3c <main+0x23c>
 1033ec0:	mov    $0x10,%esi
 1033ec5:	mov    %rax,%rdi
 1033ec8:	vzeroupper
 1033ecb:	call   1009130 <myl_core_list_grow>
 1033ed0:	mov    0x8(%rax),%rsi
 1033ed4:	mov    0x10(%rax),%rcx
 1033ed8:	jmp    1032e65 <main+0x265>
 1033edd:	mov    $0x10,%esi
 1033ee2:	mov    %rax,%rdi
 1033ee5:	vzeroupper
 1033ee8:	call   1009130 <myl_core_list_grow>
 1033eed:	mov    0x8(%rax),%rsi
 1033ef1:	mov    0x10(%rax),%rcx
 1033ef5:	jmp    1032e8e <main+0x28e>
 1033efa:	mov    $0x10,%esi
 1033eff:	mov    %rax,%rdi
 1033f02:	vzeroupper
 1033f05:	call   1009130 <myl_core_list_grow>
 1033f0a:	mov    0x8(%rax),%rsi
 1033f0e:	mov    0x10(%rax),%rcx
 1033f12:	jmp    1032eb7 <main+0x2b7>
 1033f17:	mov    $0x10,%esi
 1033f1c:	mov    %rax,%rdi
 1033f1f:	vzeroupper
 1033f22:	call   1009130 <myl_core_list_grow>
 1033f27:	mov    0x8(%rax),%rsi
 1033f2b:	mov    0x10(%rax),%rcx
 1033f2f:	jmp    1032ee0 <main+0x2e0>
 1033f34:	mov    $0x10,%esi
 1033f39:	mov    %rax,%rdi
 1033f3c:	vzeroupper
 1033f3f:	call   1009130 <myl_core_list_grow>
 1033f44:	mov    0x8(%rax),%rsi
 1033f48:	mov    0x10(%rax),%rcx
 1033f4c:	jmp    1032f09 <main+0x309>
 1033f51:	mov    $0x10,%esi
 1033f56:	mov    %rax,%rdi
 1033f59:	vzeroupper
 1033f5c:	call   1009130 <myl_core_list_grow>
 1033f61:	mov    0x8(%rax),%rsi
 1033f65:	mov    0x10(%rax),%rcx
 1033f69:	jmp    1032f32 <main+0x332>
 1033f6e:	mov    $0x10,%esi
 1033f73:	mov    %rax,%rdi
 1033f76:	vzeroupper
 1033f79:	call   1009130 <myl_core_list_grow>
 1033f7e:	mov    0x8(%rax),%rsi
 1033f82:	mov    0x10(%rax),%rcx
 1033f86:	jmp    1032f5b <main+0x35b>
 1033f8b:	mov    $0x10,%esi
 1033f90:	mov    %rax,%rdi
 1033f93:	vzeroupper
 1033f96:	call   1009130 <myl_core_list_grow>
 1033f9b:	mov    0x8(%rax),%rsi
 1033f9f:	mov    0x10(%rax),%rcx
 1033fa3:	jmp    1032f84 <main+0x384>
 1033fa8:	mov    $0x10,%esi
 1033fad:	mov    %rax,%rdi
 1033fb0:	vzeroupper
 1033fb3:	call   1009130 <myl_core_list_grow>
 1033fb8:	mov    0x8(%rax),%rsi
 1033fbc:	mov    0x10(%rax),%rcx
 1033fc0:	jmp    1032fad <main+0x3ad>
 1033fc5:	mov    $0x10,%esi
 1033fca:	mov    %rax,%rdi
 1033fcd:	vzeroupper
 1033fd0:	call   1009130 <myl_core_list_grow>
 1033fd5:	mov    0x8(%rax),%rsi
 1033fd9:	mov    0x10(%rax),%rcx
 1033fdd:	jmp    1032fd6 <main+0x3d6>
 1033fe2:	mov    $0x10,%esi
 1033fe7:	mov    %rax,%rdi
 1033fea:	vzeroupper
 1033fed:	call   1009130 <myl_core_list_grow>
 1033ff2:	mov    0x8(%rax),%rsi
 1033ff6:	mov    0x10(%rax),%rcx
 1033ffa:	jmp    1032fff <main+0x3ff>
 1033fff:	mov    $0x10,%esi
 1034004:	mov    %rax,%rdi
 1034007:	vzeroupper
 103400a:	call   1009130 <myl_core_list_grow>
 103400f:	mov    0x8(%rax),%rsi
 1034013:	mov    0x10(%rax),%rcx
 1034017:	jmp    1033028 <main+0x428>
 103401c:	mov    $0x10,%esi
 1034021:	mov    %rax,%rdi
 1034024:	vzeroupper
 1034027:	call   1009130 <myl_core_list_grow>
 103402c:	mov    0x8(%rax),%rsi
 1034030:	mov    0x10(%rax),%rcx
 1034034:	jmp    1033051 <main+0x451>
 1034039:	mov    $0x10,%esi
 103403e:	mov    %rax,%rdi
 1034041:	vzeroupper
 1034044:	call   1009130 <myl_core_list_grow>
 1034049:	mov    0x8(%rax),%rsi
 103404d:	mov    0x10(%rax),%rcx
 1034051:	jmp    103307a <main+0x47a>
 1034056:	mov    $0x10,%esi
 103405b:	mov    %rax,%rdi
 103405e:	vzeroupper
 1034061:	call   1009130 <myl_core_list_grow>
 1034066:	mov    0x8(%rax),%rsi
 103406a:	mov    0x10(%rax),%rcx
 103406e:	jmp    10330a3 <main+0x4a3>
 1034073:	mov    $0x10,%esi
 1034078:	mov    %rax,%rdi
 103407b:	vzeroupper
 103407e:	call   1009130 <myl_core_list_grow>
 1034083:	mov    0x8(%rax),%rsi
 1034087:	mov    0x10(%rax),%rcx
 103408b:	jmp    10330cc <main+0x4cc>
 1034090:	mov    $0x10,%esi
 1034095:	mov    %rax,%rdi
 1034098:	vzeroupper
 103409b:	call   1009130 <myl_core_list_grow>
 10340a0:	mov    0x8(%rax),%rsi
 10340a4:	mov    0x10(%rax),%rcx
 10340a8:	jmp    10330f5 <main+0x4f5>
 10340ad:	mov    $0x10,%esi
 10340b2:	mov    %rax,%rdi
 10340b5:	vzeroupper
 10340b8:	call   1009130 <myl_core_list_grow>
 10340bd:	mov    0x8(%rax),%rsi
 10340c1:	mov    0x10(%rax),%rcx
 10340c5:	jmp    103311e <main+0x51e>
 10340ca:	mov    $0x10,%esi
 10340cf:	mov    %rax,%rdi
 10340d2:	vzeroupper
 10340d5:	call   1009130 <myl_core_list_grow>
 10340da:	mov    0x8(%rax),%rsi
 10340de:	mov    0x10(%rax),%rcx
 10340e2:	jmp    1033147 <main+0x547>
 10340e7:	mov    $0x10,%esi
 10340ec:	mov    %rax,%rdi
 10340ef:	vzeroupper
 10340f2:	call   1009130 <myl_core_list_grow>
 10340f7:	mov    0x8(%rax),%rsi
 10340fb:	mov    0x10(%rax),%rcx
 10340ff:	jmp    1033170 <main+0x570>
 1034104:	mov    $0x10,%esi
 1034109:	mov    %rax,%rdi
 103410c:	vzeroupper
 103410f:	call   1009130 <myl_core_list_grow>
 1034114:	mov    0x8(%rax),%rsi
 1034118:	mov    0x10(%rax),%rcx
 103411c:	jmp    1033199 <main+0x599>
 1034121:	mov    $0x10,%esi
 1034126:	mov    %rax,%rdi
 1034129:	vzeroupper
 103412c:	call   1009130 <myl_core_list_grow>
 1034131:	mov    0x8(%rax),%rsi
 1034135:	mov    0x10(%rax),%rcx
 1034139:	jmp    10331c2 <main+0x5c2>
 103413e:	mov    $0x10,%esi
 1034143:	mov    %rax,%rdi
 1034146:	vzeroupper
 1034149:	call   1009130 <myl_core_list_grow>
 103414e:	mov    0x8(%rax),%rsi
 1034152:	mov    0x10(%rax),%rcx
 1034156:	jmp    10331eb <main+0x5eb>
 103415b:	mov    $0x10,%esi
 1034160:	mov    %rax,%rdi
 1034163:	vzeroupper
 1034166:	call   1009130 <myl_core_list_grow>
 103416b:	mov    0x8(%rax),%rsi
 103416f:	mov    0x10(%rax),%rcx
 1034173:	jmp    1033214 <main+0x614>
 1034178:	mov    $0x10,%esi
 103417d:	mov    %rax,%rdi
 1034180:	vzeroupper
 1034183:	call   1009130 <myl_core_list_grow>
 1034188:	mov    0x8(%rax),%rsi
 103418c:	mov    0x10(%rax),%rcx
 1034190:	jmp    103323d <main+0x63d>
 1034195:	mov    $0x10,%esi
 103419a:	mov    %rax,%rdi
 103419d:	vzeroupper
 10341a0:	call   1009130 <myl_core_list_grow>
 10341a5:	mov    0x8(%rax),%rsi
 10341a9:	mov    0x10(%rax),%rcx
 10341ad:	jmp    1033266 <main+0x666>
 10341b2:	mov    $0x10,%esi
 10341b7:	mov    %rax,%rdi
 10341ba:	vzeroupper
 10341bd:	call   1009130 <myl_core_list_grow>
 10341c2:	mov    0x8(%rax),%rsi
 10341c6:	mov    0x10(%rax),%rcx
 10341ca:	jmp    103328f <main+0x68f>
 10341cf:	mov    $0x10,%esi
 10341d4:	mov    %rax,%rdi
 10341d7:	vzeroupper
 10341da:	call   1009130 <myl_core_list_grow>
 10341df:	mov    0x8(%rax),%rsi
 10341e3:	jmp    10332bd <main+0x6bd>
 10341e8:	lea    0x1971(%rip),%rdi        # 1035b60 <core_io_file_error.verbs+0x380>
 10341ef:	xor    %esi,%esi
 10341f1:	xor    %edx,%edx
 10341f3:	vzeroupper
 10341f6:	call   10097c0 <myl_core_trap>
 10341fb:	lea    0x198e(%rip),%rdi        # 1035b90 <core_io_file_error.verbs+0x3b0>
 1034202:	xor    %esi,%esi
 1034204:	xor    %edx,%edx
 1034206:	vzeroupper
 1034209:	call   10097c0 <myl_core_trap>
 103420e:	lea    0x18eb(%rip),%rdi        # 1035b00 <core_io_file_error.verbs+0x320>
 1034215:	mov    %r12,%rsi
 1034218:	mov    %r14,%rdx
 103421b:	vzeroupper
 103421e:	call   10097c0 <myl_core_trap>
 1034223:	lea    0x1906(%rip),%rdi        # 1035b30 <core_io_file_error.verbs+0x350>
 103422a:	mov    %r12,%rsi
 103422d:	xor    %edx,%edx
 103422f:	vzeroupper
 1034232:	call   10097c0 <myl_core_trap>
 1034237:	lea    0x1892(%rip),%rdi        # 1035ad0 <core_io_file_error.verbs+0x2f0>
 103423e:	mov    %r12,%rsi
 1034241:	mov    %r14,%rdx
 1034244:	vzeroupper
 1034247:	call   10097c0 <myl_core_trap>
 103424c:	mov    %r10,%rdi
 103424f:	vzeroupper
 1034252:	call   10323d0 <myl_core_free_block>
 1034257:	jmp    1033cf2 <main+0x10f2>
 103425c:	mov    %r10,%rdi
 103425f:	vzeroupper
 1034262:	call   10323d0 <myl_core_free_block>
 1034267:	jmp    1033c8e <main+0x108e>
 103426c:	lea    0x16dd(%rip),%rdi        # 1035950 <core_io_file_error.verbs+0x170>
 1034273:	mov    0x30(%rsp),%rsi
 1034278:	vzeroupper
 103427b:	call   10097c0 <myl_core_trap>
 1034280:	lea    0x1939(%rip),%rdi        # 1035bc0 <core_io_file_error.verbs+0x3e0>
 1034287:	xor    %esi,%esi
 1034289:	xor    %edx,%edx
 103428b:	vzeroupper
 103428e:	call   10097c0 <myl_core_trap>
 1034293:	lea    0x1686(%rip),%rdi        # 1035920 <core_io_file_error.verbs+0x140>
 103429a:	mov    %rbp,%rsi
 103429d:	mov    %r14,%rdx
 10342a0:	vzeroupper
 10342a3:	call   10097c0 <myl_core_trap>
 10342a8:	lea    0x1581(%rip),%rdi        # 1035830 <core_io_file_error.verbs+0x50>
 10342af:	mov    $0x1,%esi
 10342b4:	call   10097c0 <myl_core_trap>
 10342b9:	lea    0x15a0(%rip),%rdi        # 1035860 <core_io_file_error.verbs+0x80>
 10342c0:	mov    $0x2,%esi
 10342c5:	call   10097c0 <myl_core_trap>
 10342ca:	lea    0x161f(%rip),%rdi        # 10358f0 <core_io_file_error.verbs+0x110>
 10342d1:	mov    %rax,%rsi
 10342d4:	call   10097c0 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
