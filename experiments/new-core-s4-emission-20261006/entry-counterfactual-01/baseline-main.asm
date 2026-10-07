
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-emission/experiments/new-core-s4-emission-20261006/entry-counterfactual-01/baseline/program:     file format elf64-x86-64


Disassembly of section .text:

00000000010339f0 <my.app::main>:
 10339f0:	push   %rbp
 10339f1:	push   %r15
 10339f3:	push   %r14
 10339f5:	push   %r13
 10339f7:	push   %r12
 10339f9:	push   %rbx
 10339fa:	sub    $0x58,%rsp
 10339fe:	mov    $0x2,%ebx
 1033a03:	cmpq   $0x3,0x8(%rdi)
 1033a08:	jne    1034acc <my.app::main+0x10dc>
 1033a0e:	mov    %rsi,%r15
 1033a11:	mov    %rdi,%r14
 1033a14:	mov    %rdx,0x30(%rsp)
 1033a19:	mov    0x20(%rdi),%rdi
 1033a1d:	call   1032e00 <my.workload::parse_number>
 1033a22:	mov    %rax,(%rsp)
 1033a26:	mov    0x8(%r14),%rdx
 1033a2a:	cmp    $0x1,%rdx
 1033a2e:	jbe    1035073 <my.app::main+0x1683>
 1033a34:	mov    0x28(%r14),%rdi
 1033a38:	call   1032e00 <my.workload::parse_number>
 1033a3d:	mov    0x8(%r14),%rdx
 1033a41:	cmp    $0x2,%rdx
 1033a45:	jbe    1035084 <my.app::main+0x1694>
 1033a4b:	mov    %rax,%r12
 1033a4e:	mov    0x30(%r14),%rdi
 1033a52:	call   1032e00 <my.workload::parse_number>
 1033a57:	cmpq   $0x2,(%rsp)
 1033a5c:	setl   %dl
 1033a5f:	test   %r12,%r12
 1033a62:	setle  %cl
 1033a65:	or     %dl,%cl
 1033a67:	mov    %rax,0x20(%rsp)
 1033a6c:	add    $0xfffffffffff0bdbf,%rax
 1033a72:	cmp    $0xfffffffffff0bdc0,%rax
 1033a78:	setb   %al
 1033a7b:	or     %cl,%al
 1033a7d:	jne    1034acc <my.app::main+0x10dc>
 1033a83:	lea    0x27156(%rip),%rcx        # 105abe0 <myl_core_free_lists>
 1033a8a:	mov    0xa0(%rcx),%rax
 1033a91:	test   %rax,%rax
 1033a94:	mov    %r12,0x38(%rsp)
 1033a99:	je     1034b4f <my.app::main+0x115f>
 1033a9f:	mov    (%rax),%rdx
 1033aa2:	mov    %rdx,0xa0(%rcx)
 1033aa9:	vmovaps -0x30411(%rip),%ymm0        # 10036a0 <core_io_raw_layout+0x120>
 1033ab1:	vmovups %ymm0,(%rax)
 1033ab5:	mov    $0x26,%ecx
 1033aba:	xor    %esi,%esi
 1033abc:	mov    %rsi,%rdx
 1033abf:	shl    $0x4,%rdx
 1033ac3:	inc    %rsi
 1033ac6:	vxorps %xmm0,%xmm0,%xmm0
 1033aca:	vmovups %xmm0,0x20(%rax,%rdx,1)
 1033ad0:	mov    %rsi,0x8(%rax)
 1033ad4:	cmp    %rcx,%rsi
 1033ad7:	jae    1034b89 <my.app::main+0x1199>
 1033add:	mov    %rsi,%rdx
 1033ae0:	shl    $0x4,%rdx
 1033ae4:	movq   $0x4,0x20(%rax,%rdx,1)
 1033aed:	movq   $0x0,0x28(%rax,%rdx,1)
 1033af6:	inc    %rsi
 1033af9:	mov    %rsi,0x8(%rax)
 1033afd:	cmp    %rcx,%rsi
 1033b00:	jae    1034ba6 <my.app::main+0x11b6>
 1033b06:	mov    %rsi,%rdx
 1033b09:	shl    $0x4,%rdx
 1033b0d:	movq   $0x2,0x20(%rax,%rdx,1)
 1033b16:	movq   $0x0,0x28(%rax,%rdx,1)
 1033b1f:	inc    %rsi
 1033b22:	mov    %rsi,0x8(%rax)
 1033b26:	cmp    %rcx,%rsi
 1033b29:	jae    1034bc3 <my.app::main+0x11d3>
 1033b2f:	mov    %rsi,%rdx
 1033b32:	shl    $0x4,%rdx
 1033b36:	movq   $0x4,0x20(%rax,%rdx,1)
 1033b3f:	movq   $0x1,0x28(%rax,%rdx,1)
 1033b48:	inc    %rsi
 1033b4b:	mov    %rsi,0x8(%rax)
 1033b4f:	cmp    %rcx,%rsi
 1033b52:	jae    1034be0 <my.app::main+0x11f0>
 1033b58:	mov    %rsi,%rdx
 1033b5b:	shl    $0x4,%rdx
 1033b5f:	movq   $0x3,0x20(%rax,%rdx,1)
 1033b68:	movq   $0x1,0x28(%rax,%rdx,1)
 1033b71:	inc    %rsi
 1033b74:	mov    %rsi,0x8(%rax)
 1033b78:	cmp    %rcx,%rsi
 1033b7b:	jae    1034bfd <my.app::main+0x120d>
 1033b81:	mov    %rsi,%rdx
 1033b84:	shl    $0x4,%rdx
 1033b88:	movq   $0x1,0x20(%rax,%rdx,1)
 1033b91:	movq   $0x0,0x28(%rax,%rdx,1)
 1033b9a:	inc    %rsi
 1033b9d:	mov    %rsi,0x8(%rax)
 1033ba1:	cmp    %rcx,%rsi
 1033ba4:	jae    1034c1a <my.app::main+0x122a>
 1033baa:	mov    %rsi,%rdx
 1033bad:	shl    $0x4,%rdx
 1033bb1:	movq   $0x8,0x20(%rax,%rdx,1)
 1033bba:	movq   $0x0,0x28(%rax,%rdx,1)
 1033bc3:	inc    %rsi
 1033bc6:	mov    %rsi,0x8(%rax)
 1033bca:	cmp    %rcx,%rsi
 1033bcd:	jae    1034c37 <my.app::main+0x1247>
 1033bd3:	mov    %rsi,%rdx
 1033bd6:	shl    $0x4,%rdx
 1033bda:	movq   $0xa,0x20(%rax,%rdx,1)
 1033be3:	movq   $0x1d,0x28(%rax,%rdx,1)
 1033bec:	inc    %rsi
 1033bef:	mov    %rsi,0x8(%rax)
 1033bf3:	cmp    %rcx,%rsi
 1033bf6:	jae    1034c54 <my.app::main+0x1264>
 1033bfc:	mov    %rsi,%rdx
 1033bff:	shl    $0x4,%rdx
 1033c03:	movq   $0x3,0x20(%rax,%rdx,1)
 1033c0c:	movq   $0x1,0x28(%rax,%rdx,1)
 1033c15:	inc    %rsi
 1033c18:	mov    %rsi,0x8(%rax)
 1033c1c:	cmp    %rcx,%rsi
 1033c1f:	jae    1034c71 <my.app::main+0x1281>
 1033c25:	mov    %rsi,%rdx
 1033c28:	shl    $0x4,%rdx
 1033c2c:	movq   $0x2,0x20(%rax,%rdx,1)
 1033c35:	movq   $0x2,0x28(%rax,%rdx,1)
 1033c3e:	inc    %rsi
 1033c41:	mov    %rsi,0x8(%rax)
 1033c45:	cmp    %rcx,%rsi
 1033c48:	jae    1034c8e <my.app::main+0x129e>
 1033c4e:	mov    %rsi,%rdx
 1033c51:	shl    $0x4,%rdx
 1033c55:	movq   $0x7,0x20(%rax,%rdx,1)
 1033c5e:	movq   $0x0,0x28(%rax,%rdx,1)
 1033c67:	inc    %rsi
 1033c6a:	mov    %rsi,0x8(%rax)
 1033c6e:	cmp    %rcx,%rsi
 1033c71:	jae    1034cab <my.app::main+0x12bb>
 1033c77:	mov    %rsi,%rdx
 1033c7a:	shl    $0x4,%rdx
 1033c7e:	movq   $0x2,0x20(%rax,%rdx,1)
 1033c87:	movq   $0x0,0x28(%rax,%rdx,1)
 1033c90:	inc    %rsi
 1033c93:	mov    %rsi,0x8(%rax)
 1033c97:	cmp    %rcx,%rsi
 1033c9a:	jae    1034cc8 <my.app::main+0x12d8>
 1033ca0:	mov    %rsi,%rdx
 1033ca3:	shl    $0x4,%rdx
 1033ca7:	movq   $0x9,0x20(%rax,%rdx,1)
 1033cb0:	movq   $0x0,0x28(%rax,%rdx,1)
 1033cb9:	inc    %rsi
 1033cbc:	mov    %rsi,0x8(%rax)
 1033cc0:	cmp    %rcx,%rsi
 1033cc3:	jae    1034ce5 <my.app::main+0x12f5>
 1033cc9:	mov    %rsi,%rdx
 1033ccc:	shl    $0x4,%rdx
 1033cd0:	movq   $0xa,0x20(%rax,%rdx,1)
 1033cd9:	movq   $0x12,0x28(%rax,%rdx,1)
 1033ce2:	inc    %rsi
 1033ce5:	mov    %rsi,0x8(%rax)
 1033ce9:	cmp    %rcx,%rsi
 1033cec:	jae    1034d02 <my.app::main+0x1312>
 1033cf2:	mov    %rsi,%rdx
 1033cf5:	shl    $0x4,%rdx
 1033cf9:	movq   $0x3,0x20(%rax,%rdx,1)
 1033d02:	movq   $0x0,0x28(%rax,%rdx,1)
 1033d0b:	inc    %rsi
 1033d0e:	mov    %rsi,0x8(%rax)
 1033d12:	cmp    %rcx,%rsi
 1033d15:	jae    1034d1f <my.app::main+0x132f>
 1033d1b:	mov    %rsi,%rdx
 1033d1e:	shl    $0x4,%rdx
 1033d22:	movq   $0xc,0x20(%rax,%rdx,1)
 1033d2b:	movq   $0x1f,0x28(%rax,%rdx,1)
 1033d34:	inc    %rsi
 1033d37:	mov    %rsi,0x8(%rax)
 1033d3b:	cmp    %rcx,%rsi
 1033d3e:	jae    1034d3c <my.app::main+0x134c>
 1033d44:	mov    %rsi,%rdx
 1033d47:	shl    $0x4,%rdx
 1033d4b:	movq   $0x4,0x20(%rax,%rdx,1)
 1033d54:	movq   $0x0,0x28(%rax,%rdx,1)
 1033d5d:	inc    %rsi
 1033d60:	mov    %rsi,0x8(%rax)
 1033d64:	cmp    %rcx,%rsi
 1033d67:	jae    1034d59 <my.app::main+0x1369>
 1033d6d:	mov    %rsi,%rdx
 1033d70:	shl    $0x4,%rdx
 1033d74:	movq   $0xb,0x20(%rax,%rdx,1)
 1033d7d:	movq   $0x18,0x28(%rax,%rdx,1)
 1033d86:	inc    %rsi
 1033d89:	mov    %rsi,0x8(%rax)
 1033d8d:	cmp    %rcx,%rsi
 1033d90:	jae    1034d76 <my.app::main+0x1386>
 1033d96:	mov    %rsi,%rdx
 1033d99:	shl    $0x4,%rdx
 1033d9d:	movq   $0x3,0x20(%rax,%rdx,1)
 1033da6:	movq   $0x0,0x28(%rax,%rdx,1)
 1033daf:	inc    %rsi
 1033db2:	mov    %rsi,0x8(%rax)
 1033db6:	cmp    %rcx,%rsi
 1033db9:	jae    1034d93 <my.app::main+0x13a3>
 1033dbf:	mov    %rsi,%rdx
 1033dc2:	shl    $0x4,%rdx
 1033dc6:	movq   $0x3,0x20(%rax,%rdx,1)
 1033dcf:	movq   $0x1,0x28(%rax,%rdx,1)
 1033dd8:	inc    %rsi
 1033ddb:	mov    %rsi,0x8(%rax)
 1033ddf:	cmp    %rcx,%rsi
 1033de2:	jae    1034db0 <my.app::main+0x13c0>
 1033de8:	mov    %rsi,%rdx
 1033deb:	shl    $0x4,%rdx
 1033def:	movq   $0x5,0x20(%rax,%rdx,1)
 1033df8:	movq   $0x0,0x28(%rax,%rdx,1)
 1033e01:	inc    %rsi
 1033e04:	mov    %rsi,0x8(%rax)
 1033e08:	cmp    %rcx,%rsi
 1033e0b:	jae    1034dcd <my.app::main+0x13dd>
 1033e11:	mov    %rsi,%rdx
 1033e14:	shl    $0x4,%rdx
 1033e18:	movq   $0x2,0x20(%rax,%rdx,1)
 1033e21:	movq   $0xf4243,0x28(%rax,%rdx,1)
 1033e2a:	inc    %rsi
 1033e2d:	mov    %rsi,0x8(%rax)
 1033e31:	cmp    %rcx,%rsi
 1033e34:	jae    1034dea <my.app::main+0x13fa>
 1033e3a:	mov    %rsi,%rdx
 1033e3d:	shl    $0x4,%rdx
 1033e41:	movq   $0x7,0x20(%rax,%rdx,1)
 1033e4a:	movq   $0x0,0x28(%rax,%rdx,1)
 1033e53:	inc    %rsi
 1033e56:	mov    %rsi,0x8(%rax)
 1033e5a:	cmp    %rcx,%rsi
 1033e5d:	jae    1034e07 <my.app::main+0x1417>
 1033e63:	mov    %rsi,%rdx
 1033e66:	shl    $0x4,%rdx
 1033e6a:	movq   $0x4,0x20(%rax,%rdx,1)
 1033e73:	movq   $0x0,0x28(%rax,%rdx,1)
 1033e7c:	inc    %rsi
 1033e7f:	mov    %rsi,0x8(%rax)
 1033e83:	cmp    %rcx,%rsi
 1033e86:	jae    1034e24 <my.app::main+0x1434>
 1033e8c:	mov    %rsi,%rdx
 1033e8f:	shl    $0x4,%rdx
 1033e93:	movq   $0x3,0x20(%rax,%rdx,1)
 1033e9c:	movq   $0x1,0x28(%rax,%rdx,1)
 1033ea5:	inc    %rsi
 1033ea8:	mov    %rsi,0x8(%rax)
 1033eac:	cmp    %rcx,%rsi
 1033eaf:	jae    1034e41 <my.app::main+0x1451>
 1033eb5:	mov    %rsi,%rdx
 1033eb8:	shl    $0x4,%rdx
 1033ebc:	movq   $0x2,0x20(%rax,%rdx,1)
 1033ec5:	movq   $0x1,0x28(%rax,%rdx,1)
 1033ece:	inc    %rsi
 1033ed1:	mov    %rsi,0x8(%rax)
 1033ed5:	cmp    %rcx,%rsi
 1033ed8:	jae    1034e5e <my.app::main+0x146e>
 1033ede:	mov    %rsi,%rdx
 1033ee1:	shl    $0x4,%rdx
 1033ee5:	movq   $0x5,0x20(%rax,%rdx,1)
 1033eee:	movq   $0x0,0x28(%rax,%rdx,1)
 1033ef7:	inc    %rsi
 1033efa:	mov    %rsi,0x8(%rax)
 1033efe:	cmp    %rcx,%rsi
 1033f01:	jae    1034e7b <my.app::main+0x148b>
 1033f07:	mov    %rsi,%rdx
 1033f0a:	shl    $0x4,%rdx
 1033f0e:	movq   $0x4,0x20(%rax,%rdx,1)
 1033f17:	movq   $0x1,0x28(%rax,%rdx,1)
 1033f20:	inc    %rsi
 1033f23:	mov    %rsi,0x8(%rax)
 1033f27:	cmp    %rcx,%rsi
 1033f2a:	jae    1034e98 <my.app::main+0x14a8>
 1033f30:	mov    %rsi,%rdx
 1033f33:	shl    $0x4,%rdx
 1033f37:	movq   $0xb,0x20(%rax,%rdx,1)
 1033f40:	movq   $0x4,0x28(%rax,%rdx,1)
 1033f49:	inc    %rsi
 1033f4c:	mov    %rsi,0x8(%rax)
 1033f50:	cmp    %rcx,%rsi
 1033f53:	jae    1034eb5 <my.app::main+0x14c5>
 1033f59:	mov    %rsi,%rdx
 1033f5c:	shl    $0x4,%rdx
 1033f60:	movq   $0x3,0x20(%rax,%rdx,1)
 1033f69:	movq   $0x0,0x28(%rax,%rdx,1)
 1033f72:	inc    %rsi
 1033f75:	mov    %rsi,0x8(%rax)
 1033f79:	cmp    %rcx,%rsi
 1033f7c:	jae    1034ed2 <my.app::main+0x14e2>
 1033f82:	mov    %rsi,%rdx
 1033f85:	shl    $0x4,%rdx
 1033f89:	movq   $0xe,0x20(%rax,%rdx,1)
 1033f92:	movq   $0x0,0x28(%rax,%rdx,1)
 1033f9b:	inc    %rsi
 1033f9e:	mov    %rsi,0x8(%rax)
 1033fa2:	cmp    %rcx,%rsi
 1033fa5:	jae    1034eef <my.app::main+0x14ff>
 1033fab:	mov    %rsi,%rdx
 1033fae:	shl    $0x4,%rdx
 1033fb2:	movq   $0x2,0x20(%rax,%rdx,1)
 1033fbb:	movq   $0x3,0x28(%rax,%rdx,1)
 1033fc4:	inc    %rsi
 1033fc7:	mov    %rsi,0x8(%rax)
 1033fcb:	cmp    %rcx,%rsi
 1033fce:	jae    1034f0c <my.app::main+0x151c>
 1033fd4:	mov    %rsi,%rdx
 1033fd7:	shl    $0x4,%rdx
 1033fdb:	movq   $0x6,0x20(%rax,%rdx,1)
 1033fe4:	movq   $0x0,0x28(%rax,%rdx,1)
 1033fed:	inc    %rsi
 1033ff0:	mov    %rsi,0x8(%rax)
 1033ff4:	cmp    %rcx,%rsi
 1033ff7:	jae    1034f29 <my.app::main+0x1539>
 1033ffd:	mov    %rsi,%rdx
 1034000:	shl    $0x4,%rdx
 1034004:	movq   $0x2,0x20(%rax,%rdx,1)
 103400d:	movq   $0x7,0x28(%rax,%rdx,1)
 1034016:	inc    %rsi
 1034019:	mov    %rsi,0x8(%rax)
 103401d:	cmp    %rcx,%rsi
 1034020:	jae    1034f46 <my.app::main+0x1556>
 1034026:	mov    %rsi,%rdx
 1034029:	shl    $0x4,%rdx
 103402d:	movq   $0x5,0x20(%rax,%rdx,1)
 1034036:	movq   $0x0,0x28(%rax,%rdx,1)
 103403f:	inc    %rsi
 1034042:	mov    %rsi,0x8(%rax)
 1034046:	cmp    %rcx,%rsi
 1034049:	jae    1034f63 <my.app::main+0x1573>
 103404f:	mov    %rsi,%rdx
 1034052:	shl    $0x4,%rdx
 1034056:	movq   $0x2,0x20(%rax,%rdx,1)
 103405f:	movq   $0xf4243,0x28(%rax,%rdx,1)
 1034068:	inc    %rsi
 103406b:	mov    %rsi,0x8(%rax)
 103406f:	cmp    %rcx,%rsi
 1034072:	jae    1034f80 <my.app::main+0x1590>
 1034078:	mov    %rsi,%rdx
 103407b:	shl    $0x4,%rdx
 103407f:	movq   $0x7,0x20(%rax,%rdx,1)
 1034088:	movq   $0x0,0x28(%rax,%rdx,1)
 1034091:	inc    %rsi
 1034094:	mov    %rsi,0x8(%rax)
 1034098:	cmp    %rcx,%rsi
 103409b:	mov    %r15,0x18(%rsp)
 10340a0:	jae    1034f9d <my.app::main+0x15ad>
 10340a6:	mov    %rax,0x8(%rsp)
 10340ab:	lea    0x20(%rax),%r12
 10340af:	mov    %rsi,%rcx
 10340b2:	shl    $0x4,%rcx
 10340b6:	movq   $0xd,0x20(%rax,%rcx,1)
 10340bf:	movq   $0x0,0x28(%rax,%rcx,1)
 10340c8:	inc    %rsi
 10340cb:	mov    %rsi,0x8(%rax)
 10340cf:	lea    0x282a(%rip),%rdi        # 1036900 <core_io_file_error.verbs+0x350>
 10340d6:	vzeroupper
 10340d9:	call   100a4c0 <myl_core_io_at>
 10340de:	mov    0x18(%rsp),%rdi
 10340e3:	call   1022430 <myl_core_host_check>
 10340e8:	call   10350b0 <runtime_bench_now>
 10340ed:	xor    %r11d,%r11d
 10340f0:	mov    0x8(%rsp),%r10
 10340f5:	mov    %rax,0x28(%rsp)
 10340fa:	lea    -0x2f811(%rip),%rbp        # 10048f0 <core_number_pairs+0x3c0>
 1034101:	movabs $0x100000000000001,%r13
 103410b:	vxorps %xmm1,%xmm1,%xmm1
 103410f:	xor    %eax,%eax
 1034111:	xor    %edx,%edx
 1034113:	lea    0x26ac6(%rip),%r9        # 105abe0 <myl_core_free_lists>
 103411a:	mov    (%rsp),%r8
 103411e:	xchg   %ax,%ax
 1034120:	mov    0x20(%rsp),%rcx
 1034125:	add    %rdx,%rcx
 1034128:	mov    %rcx,0x50(%rsp)
 103412d:	jo     103503a <my.app::main+0x164a>
 1034133:	mov    %rax,0x48(%rsp)
 1034138:	mov    %rdx,0x40(%rsp)
 103413d:	mov    0x8(%r9),%r15
 1034141:	test   %r15,%r15
 1034144:	je     103488b <my.app::main+0xe9b>
 103414a:	mov    (%r15),%rax
 103414d:	mov    %rax,0x8(%r9)
 1034151:	mov    %r13,(%r15)
 1034154:	vmovups %xmm1,0x8(%r15)
 103415a:	movq   $0x0,0x18(%r15)
 1034162:	mov    0x8(%r9),%rax
 1034166:	test   %rax,%rax
 1034169:	je     10348b9 <my.app::main+0xec9>
 103416f:	mov    (%rax),%rcx
 1034172:	mov    %rcx,0x8(%r9)
 1034176:	mov    %r13,(%rax)
 1034179:	vmovups %xmm1,0x8(%rax)
 103417e:	movq   $0x0,0x18(%rax)
 1034186:	mov    %rax,0x10(%rsp)
 103418b:	mov    0x10(%r9),%rdi
 103418f:	test   %rdi,%rdi
 1034192:	je     10348e4 <my.app::main+0xef4>
 1034198:	mov    (%rdi),%rax
 103419b:	mov    %rax,0x10(%r9)
 103419f:	vmovaps -0x30ac7(%rip),%ymm0        # 10036e0 <core_io_raw_layout+0x160>
 10341a7:	vmovups %ymm0,(%rdi)
 10341ab:	mov    $0x4,%ecx
 10341b0:	xor    %edx,%edx
 10341b2:	movq   $0x0,0x20(%rdi,%rdx,8)
 10341bb:	inc    %rdx
 10341be:	mov    %rdx,0x8(%rdi)
 10341c2:	cmp    %rcx,%rdx
 10341c5:	jae    103493b <my.app::main+0xf4b>
 10341cb:	movq   $0x0,0x20(%rdi,%rdx,8)
 10341d4:	inc    %rdx
 10341d7:	mov    %rdx,0x8(%rdi)
 10341db:	mov    0x8(%r10),%rdx
 10341df:	xor    %esi,%esi
 10341e1:	test   %rdx,%rdx
 10341e4:	je     1034a19 <my.app::main+0x1029>
 10341ea:	xor    %eax,%eax
 10341ec:	mov    %rax,%r13
 10341ef:	jmp    1034238 <my.app::main+0x848>
 10341f1:	mov    0x8(%r15),%rax
 10341f5:	cmp    0x10(%r15),%rax
 10341f9:	jae    1034584 <my.app::main+0xb94>
 10341ff:	mov    %rax,%rcx
 1034202:	shl    $0x4,%rcx
 1034206:	movq   $0x0,0x20(%r15,%rcx,1)
 103420f:	mov    %r14,0x28(%r15,%rcx,1)
 1034214:	inc    %rax
 1034217:	mov    %rax,0x8(%r15)
 103421b:	mov    0x8(%r10),%rdx
 103421f:	mov    %r13,%rsi
 1034222:	sar    $0x3f,%rsi
 1034226:	and    %rdx,%rsi
 1034229:	add    %r13,%rsi
 103422c:	mov    %r13,%rax
 103422f:	cmp    %rdx,%rsi
 1034232:	jae    1034a19 <my.app::main+0x1029>
 1034238:	inc    %r13
 103423b:	jo     1034ae1 <my.app::main+0x10f1>
 1034241:	shl    $0x4,%rsi
 1034245:	mov    (%r12,%rsi,1),%rcx
 1034249:	mov    0x8(%r12,%rsi,1),%r14
 103424e:	cmp    $0x4,%rcx
 1034252:	ja     103434c <my.app::main+0x95c>
 1034258:	movslq 0x0(%rbp,%rcx,4),%rax
 103425d:	add    %rbp,%rax
 1034260:	jmp    *%rax
 1034262:	mov    0x8(%r15),%rax
 1034266:	cmp    0x10(%r15),%rax
 103426a:	jae    10345bd <my.app::main+0xbcd>
 1034270:	mov    %rax,%rcx
 1034273:	shl    $0x4,%rcx
 1034277:	movq   $0x0,0x20(%r15,%rcx,1)
 1034280:	mov    0x50(%rsp),%rdx
 1034285:	mov    %rdx,0x28(%r15,%rcx,1)
 103428a:	jmp    1034214 <my.app::main+0x824>
 103428c:	mov    0x8(%r15),%rdx
 1034290:	test   %rdx,%rdx
 1034293:	je     1034b07 <my.app::main+0x1117>
 1034299:	dec    %rdx
 103429c:	mov    %rdx,%rax
 103429f:	shl    $0x4,%rax
 10342a3:	movzbl 0x20(%r15,%rax,1),%ecx
 10342a9:	mov    0x28(%r15,%rax,1),%rax
 10342ae:	mov    %rdx,0x8(%r15)
 10342b2:	mov    0x8(%rdi),%rdx
 10342b6:	mov    %r14,%rsi
 10342b9:	sar    $0x3f,%rsi
 10342bd:	and    %rdx,%rsi
 10342c0:	add    %r14,%rsi
 10342c3:	cmp    %rdx,%rsi
 10342c6:	jae    1034af8 <my.app::main+0x1108>
 10342cc:	test   %rcx,%rcx
 10342cf:	cmovne %r11,%rax
 10342d3:	mov    %rax,0x20(%rdi,%rsi,8)
 10342d8:	jmp    103421b <my.app::main+0x82b>
 10342dd:	mov    0x8(%rdi),%rdx
 10342e1:	mov    %r14,%rsi
 10342e4:	sar    $0x3f,%rsi
 10342e8:	and    %rdx,%rsi
 10342eb:	add    %r14,%rsi
 10342ee:	cmp    %rdx,%rsi
 10342f1:	jae    1034b1a <my.app::main+0x112a>
 10342f7:	mov    0x20(%rdi,%rsi,8),%rbx
 10342fc:	mov    0x8(%r15),%rax
 1034300:	cmp    0x10(%r15),%rax
 1034304:	jae    103462f <my.app::main+0xc3f>
 103430a:	mov    %rax,%rcx
 103430d:	shl    $0x4,%rcx
 1034311:	movq   $0x0,0x20(%r15,%rcx,1)
 103431a:	mov    %rbx,0x28(%r15,%rcx,1)
 103431f:	jmp    1034214 <my.app::main+0x824>
 1034324:	mov    0x8(%r15),%rax
 1034328:	cmp    0x10(%r15),%rax
 103432c:	jae    10345f6 <my.app::main+0xc06>
 1034332:	mov    %rax,%rcx
 1034335:	shl    $0x4,%rcx
 1034339:	movq   $0x0,0x20(%r15,%rcx,1)
 1034342:	mov    %r8,0x28(%r15,%rcx,1)
 1034347:	jmp    1034214 <my.app::main+0x824>
 103434c:	lea    -0x5(%rcx),%rax
 1034350:	cmp    $0x5,%rax
 1034354:	jae    103437d <my.app::main+0x98d>
 1034356:	mov    0x8(%r15),%rcx
 103435a:	test   %rcx,%rcx
 103435d:	je     1034b3c <my.app::main+0x114c>
 1034363:	lea    -0x1(%rcx),%rdx
 1034367:	mov    %rdx,%rsi
 103436a:	shl    $0x4,%rsi
 103436e:	cmpb   $0x0,0x20(%r15,%rsi,1)
 1034374:	jne    10343d4 <my.app::main+0x9e4>
 1034376:	mov    0x28(%r15,%rsi,1),%rbp
 103437b:	jmp    10343d6 <my.app::main+0x9e6>
 103437d:	add    $0xfffffffffffffff6,%rcx
 1034381:	cmp    $0x3,%rcx
 1034385:	ja     1034790 <my.app::main+0xda0>
 103438b:	lea    -0x2fa8e(%rip),%rdx        # 1004904 <core_number_pairs+0x3d4>
 1034392:	movslq (%rdx,%rcx,4),%rax
 1034396:	add    %rdx,%rax
 1034399:	jmp    *%rax
 103439b:	mov    0x8(%r15),%rax
 103439f:	test   %rax,%rax
 10343a2:	je     1034fb6 <my.app::main+0x15c6>
 10343a8:	dec    %rax
 10343ab:	mov    %rax,%rcx
 10343ae:	shl    $0x4,%rcx
 10343b2:	movzbl 0x20(%r15,%rcx,1),%edx
 10343b8:	mov    0x28(%r15,%rcx,1),%rcx
 10343bd:	mov    %rax,0x8(%r15)
 10343c1:	test   $0x1,%cl
 10343c4:	cmove  %r14,%r13
 10343c8:	cmp    $0x1,%dl
 10343cb:	cmovne %r14,%r13
 10343cf:	jmp    103421b <my.app::main+0x82b>
 10343d4:	xor    %ebp,%ebp
 10343d6:	mov    %rdx,0x8(%r15)
 10343da:	test   %rdx,%rdx
 10343dd:	je     1034b29 <my.app::main+0x1139>
 10343e3:	mov    %rcx,%rdx
 10343e6:	shl    $0x4,%rdx
 10343ea:	cmpb   $0x0,(%r15,%rdx,1)
 10343ef:	jne    10343f8 <my.app::main+0xa08>
 10343f1:	mov    0x8(%r15,%rdx,1),%rbx
 10343f6:	jmp    10343fa <my.app::main+0xa0a>
 10343f8:	xor    %ebx,%ebx
 10343fa:	add    $0xfffffffffffffffe,%rcx
 10343fe:	mov    %rcx,0x8(%r15)
 1034402:	cmp    $0x3,%rax
 1034406:	ja     10344ff <my.app::main+0xb0f>
 103440c:	lea    -0x2faff(%rip),%rdx        # 1004914 <core_number_pairs+0x3e4>
 1034413:	movslq (%rdx,%rax,4),%rax
 1034417:	add    %rdx,%rax
 103441a:	jmp    *%rax
 103441c:	mov    %rbx,%r14
 103441f:	add    %rbp,%r14
 1034422:	jno    10344ec <my.app::main+0xafc>
 1034428:	jmp    1035005 <my.app::main+0x1615>
 103442d:	mov    0x10(%rsp),%rax
 1034432:	mov    0x8(%rax),%rcx
 1034436:	cmp    0x10(%rax),%rcx
 103443a:	jae    10346a1 <my.app::main+0xcb1>
 1034440:	mov    %r13,0x20(%rax,%rcx,8)
 1034445:	inc    %rcx
 1034448:	mov    %rax,0x10(%rsp)
 103444d:	mov    %rcx,0x8(%rax)
 1034451:	mov    %r14,%r13
 1034454:	jmp    103421b <my.app::main+0x82b>
 1034459:	mov    0x10(%rsp),%rcx
 103445e:	mov    0x8(%rcx),%rax
 1034462:	test   %rax,%rax
 1034465:	je     1034fc9 <my.app::main+0x15d9>
 103446b:	mov    0x18(%rcx,%rax,8),%r13
 1034470:	dec    %rax
 1034473:	mov    %rax,0x8(%rcx)
 1034477:	jmp    103421b <my.app::main+0x82b>
 103447c:	mov    %r14,%r13
 103447f:	jmp    103421b <my.app::main+0x82b>
 1034484:	test   %rbp,%rbp
 1034487:	je     1034ff1 <my.app::main+0x1601>
 103448d:	cmp    $0xffffffffffffffff,%rbp
 1034491:	mov    %rbp,%rsi
 1034494:	mov    $0x1,%eax
 1034499:	cmove  %rax,%rsi
 103449d:	mov    %rbx,%rax
 10344a0:	or     %rsi,%rax
 10344a3:	shr    $0x20,%rax
 10344a7:	je     1034535 <my.app::main+0xb45>
 10344ad:	mov    %rbx,%rax
 10344b0:	cqto
 10344b2:	idiv   %rsi
 10344b5:	jmp    103453b <my.app::main+0xb4b>
 10344ba:	cmp    0x10(%r15),%rcx
 10344be:	jae    10346d7 <my.app::main+0xce7>
 10344c4:	mov    %rcx,%rax
 10344c7:	shl    $0x4,%rax
 10344cb:	cmp    %rbp,%rbx
 10344ce:	movq   $0x1,0x20(%r15,%rax,1)
 10344d7:	setl   0x28(%r15,%rax,1)
 10344dd:	jmp    1034522 <my.app::main+0xb32>
 10344df:	mov    %rbx,%r14
 10344e2:	imul   %rbp,%r14
 10344e6:	jo     1034fdc <my.app::main+0x15ec>
 10344ec:	cmp    0x10(%r15),%rcx
 10344f0:	jae    1034668 <my.app::main+0xc78>
 10344f6:	lea    -0x2fc0d(%rip),%rbp        # 10048f0 <core_number_pairs+0x3c0>
 10344fd:	jmp    1034563 <my.app::main+0xb73>
 10344ff:	cmp    0x10(%r15),%rcx
 1034503:	jae    1034710 <my.app::main+0xd20>
 1034509:	mov    %rcx,%rax
 103450c:	shl    $0x4,%rax
 1034510:	cmp    %rbp,%rbx
 1034513:	movq   $0x1,0x20(%r15,%rax,1)
 103451c:	sete   0x28(%r15,%rax,1)
 1034522:	inc    %rcx
 1034525:	mov    %rcx,0x8(%r15)
 1034529:	lea    -0x2fc40(%rip),%rbp        # 10048f0 <core_number_pairs+0x3c0>
 1034530:	jmp    103421b <my.app::main+0x82b>
 1034535:	mov    %ebx,%eax
 1034537:	xor    %edx,%edx
 1034539:	div    %esi
 103453b:	mov    %rdx,%r14
 103453e:	xor    %rbp,%r14
 1034541:	sar    $0x3f,%r14
 1034545:	and    %rbp,%r14
 1034548:	test   %rdx,%rdx
 103454b:	cmove  %rdx,%r14
 103454f:	cmp    0x10(%r15),%rcx
 1034553:	jae    1034749 <my.app::main+0xd59>
 1034559:	lea    -0x2fc70(%rip),%rbp        # 10048f0 <core_number_pairs+0x3c0>
 1034560:	add    %rdx,%r14
 1034563:	mov    %rcx,%rax
 1034566:	shl    $0x4,%rax
 103456a:	movq   $0x0,0x20(%r15,%rax,1)
 1034573:	mov    %r14,0x28(%r15,%rax,1)
 1034578:	inc    %rcx
 103457b:	mov    %rcx,0x8(%r15)
 103457f:	jmp    103421b <my.app::main+0x82b>
 1034584:	mov    $0x10,%esi
 1034589:	mov    %rdi,%rbx
 103458c:	mov    %r15,%rdi
 103458f:	vzeroupper
 1034592:	call   10094f0 <myl_core_list_grow>
 1034597:	vxorps %xmm1,%xmm1,%xmm1
 103459b:	xor    %r11d,%r11d
 103459e:	mov    0x8(%rsp),%r10
 10345a3:	mov    (%rsp),%r8
 10345a7:	lea    0x26632(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10345ae:	mov    %rbx,%rdi
 10345b1:	mov    %rax,%r15
 10345b4:	mov    0x8(%rax),%rax
 10345b8:	jmp    10341ff <my.app::main+0x80f>
 10345bd:	mov    $0x10,%esi
 10345c2:	mov    %rdi,%rbx
 10345c5:	mov    %r15,%rdi
 10345c8:	vzeroupper
 10345cb:	call   10094f0 <myl_core_list_grow>
 10345d0:	vxorps %xmm1,%xmm1,%xmm1
 10345d4:	xor    %r11d,%r11d
 10345d7:	mov    0x8(%rsp),%r10
 10345dc:	mov    (%rsp),%r8
 10345e0:	lea    0x265f9(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10345e7:	mov    %rbx,%rdi
 10345ea:	mov    %rax,%r15
 10345ed:	mov    0x8(%rax),%rax
 10345f1:	jmp    1034270 <my.app::main+0x880>
 10345f6:	mov    $0x10,%esi
 10345fb:	mov    %rdi,%rbx
 10345fe:	mov    %r15,%rdi
 1034601:	vzeroupper
 1034604:	call   10094f0 <myl_core_list_grow>
 1034609:	vxorps %xmm1,%xmm1,%xmm1
 103460d:	xor    %r11d,%r11d
 1034610:	mov    0x8(%rsp),%r10
 1034615:	mov    (%rsp),%r8
 1034619:	lea    0x265c0(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1034620:	mov    %rbx,%rdi
 1034623:	mov    %rax,%r15
 1034626:	mov    0x8(%rax),%rax
 103462a:	jmp    1034332 <my.app::main+0x942>
 103462f:	mov    $0x10,%esi
 1034634:	mov    %rdi,%r14
 1034637:	mov    %r15,%rdi
 103463a:	vzeroupper
 103463d:	call   10094f0 <myl_core_list_grow>
 1034642:	vxorps %xmm1,%xmm1,%xmm1
 1034646:	xor    %r11d,%r11d
 1034649:	mov    0x8(%rsp),%r10
 103464e:	mov    (%rsp),%r8
 1034652:	lea    0x26587(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1034659:	mov    %r14,%rdi
 103465c:	mov    %rax,%r15
 103465f:	mov    0x8(%rax),%rax
 1034663:	jmp    103430a <my.app::main+0x91a>
 1034668:	mov    $0x10,%esi
 103466d:	mov    %rdi,%rbx
 1034670:	mov    %r15,%rdi
 1034673:	vzeroupper
 1034676:	call   10094f0 <myl_core_list_grow>
 103467b:	vxorps %xmm1,%xmm1,%xmm1
 103467f:	xor    %r11d,%r11d
 1034682:	mov    0x8(%rsp),%r10
 1034687:	mov    (%rsp),%r8
 103468b:	lea    0x2654e(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1034692:	mov    %rbx,%rdi
 1034695:	mov    %rax,%r15
 1034698:	mov    0x8(%rax),%rcx
 103469c:	jmp    10344f6 <my.app::main+0xb06>
 10346a1:	mov    $0x8,%esi
 10346a6:	mov    %rdi,%rbx
 10346a9:	mov    %rax,%rdi
 10346ac:	vzeroupper
 10346af:	call   10094f0 <myl_core_list_grow>
 10346b4:	vxorps %xmm1,%xmm1,%xmm1
 10346b8:	xor    %r11d,%r11d
 10346bb:	mov    0x8(%rsp),%r10
 10346c0:	mov    (%rsp),%r8
 10346c4:	lea    0x26515(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10346cb:	mov    %rbx,%rdi
 10346ce:	mov    0x8(%rax),%rcx
 10346d2:	jmp    1034440 <my.app::main+0xa50>
 10346d7:	mov    $0x10,%esi
 10346dc:	mov    %rdi,%r14
 10346df:	mov    %r15,%rdi
 10346e2:	vzeroupper
 10346e5:	call   10094f0 <myl_core_list_grow>
 10346ea:	vxorps %xmm1,%xmm1,%xmm1
 10346ee:	xor    %r11d,%r11d
 10346f1:	mov    0x8(%rsp),%r10
 10346f6:	mov    (%rsp),%r8
 10346fa:	lea    0x264df(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1034701:	mov    %r14,%rdi
 1034704:	mov    %rax,%r15
 1034707:	mov    0x8(%rax),%rcx
 103470b:	jmp    10344c4 <my.app::main+0xad4>
 1034710:	mov    $0x10,%esi
 1034715:	mov    %rdi,%r14
 1034718:	mov    %r15,%rdi
 103471b:	vzeroupper
 103471e:	call   10094f0 <myl_core_list_grow>
 1034723:	vxorps %xmm1,%xmm1,%xmm1
 1034727:	xor    %r11d,%r11d
 103472a:	mov    0x8(%rsp),%r10
 103472f:	mov    (%rsp),%r8
 1034733:	lea    0x264a6(%rip),%r9        # 105abe0 <myl_core_free_lists>
 103473a:	mov    %r14,%rdi
 103473d:	mov    %rax,%r15
 1034740:	mov    0x8(%rax),%rcx
 1034744:	jmp    1034509 <my.app::main+0xb19>
 1034749:	mov    $0x10,%esi
 103474e:	mov    %rdi,%rbp
 1034751:	mov    %r15,%rdi
 1034754:	mov    %rdx,%rbx
 1034757:	vzeroupper
 103475a:	call   10094f0 <myl_core_list_grow>
 103475f:	vxorps %xmm1,%xmm1,%xmm1
 1034763:	xor    %r11d,%r11d
 1034766:	mov    0x8(%rsp),%r10
 103476b:	mov    (%rsp),%r8
 103476f:	lea    0x2646a(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1034776:	mov    %rbp,%rdi
 1034779:	mov    %rbx,%rdx
 103477c:	mov    %rax,%r15
 103477f:	mov    0x8(%rax),%rcx
 1034783:	jmp    1034559 <my.app::main+0xb69>
 1034788:	nopl   0x0(%rax,%rax,1)
 1034790:	movzbl 0x7(%rdi),%eax
 1034794:	test   %rax,%rax
 1034797:	je     103496b <my.app::main+0xf7b>
 103479d:	cmpq   $0x0,0x18(%rdi)
 10347a2:	jne    103496b <my.app::main+0xf7b>
 10347a8:	mov    (%r9,%rax,8),%rcx
 10347ac:	mov    %rcx,(%rdi)
 10347af:	mov    %rdi,(%r9,%rax,8)
 10347b3:	movabs $0x100000000000001,%r13
 10347bd:	mov    0x10(%rsp),%rdi
 10347c2:	movzbl 0x7(%rdi),%eax
 10347c6:	test   %rax,%rax
 10347c9:	je     103498f <my.app::main+0xf9f>
 10347cf:	cmpq   $0x0,0x18(%rdi)
 10347d4:	jne    103498f <my.app::main+0xf9f>
 10347da:	mov    (%r9,%rax,8),%rcx
 10347de:	mov    %rcx,(%rdi)
 10347e1:	mov    %rdi,(%r9,%rax,8)
 10347e5:	mov    0x8(%r15),%rax
 10347e9:	test   %rax,%rax
 10347ec:	je     103504e <my.app::main+0x165e>
 10347f2:	dec    %rax
 10347f5:	mov    %rax,%rcx
 10347f8:	shl    $0x4,%rcx
 10347fc:	movzbl 0x20(%r15,%rcx,1),%ebx
 1034802:	mov    0x28(%r15,%rcx,1),%r14
 1034807:	mov    %rax,0x8(%r15)
 103480b:	movzbl 0x7(%r15),%eax
 1034810:	test   %rax,%rax
 1034813:	je     10349b3 <my.app::main+0xfc3>
 1034819:	cmpq   $0x0,0x18(%r15)
 103481e:	jne    10349b3 <my.app::main+0xfc3>
 1034824:	mov    (%r9,%rax,8),%rcx
 1034828:	mov    %rcx,(%r15)
 103482b:	mov    %r15,(%r9,%rax,8)
 103482f:	test   %rbx,%rbx
 1034832:	cmovne %r11,%r14
 1034836:	test   %r14,%r14
 1034839:	mov    0x48(%rsp),%rsi
 103483e:	js     10349e6 <my.app::main+0xff6>
 1034844:	mov    %rsi,%rbx
 1034847:	add    %r14,%rbx
 103484a:	jo     1035061 <my.app::main+0x1671>
 1034850:	mov    %rbx,%rdx
 1034853:	movabs $0x89705f3112a28fe5,%rax
 103485d:	mulx   %rax,%rax,%rax
 1034862:	shr    $0x1d,%rax
 1034866:	imul   $0x3b9aca07,%rax,%rax
 103486d:	sub    %rax,%rbx
 1034870:	mov    0x40(%rsp),%rdx
 1034875:	inc    %rdx
 1034878:	mov    %rbx,%rax
 103487b:	cmp    0x38(%rsp),%rdx
 1034880:	jne    1034120 <my.app::main+0x730>
 1034886:	jmp    1034a03 <my.app::main+0x1013>
 103488b:	mov    $0x10,%esi
 1034890:	xor    %edi,%edi
 1034892:	vzeroupper
 1034895:	call   1009480 <myl_core_list_new_slow>
 103489a:	vxorps %xmm1,%xmm1,%xmm1
 103489e:	xor    %r11d,%r11d
 10348a1:	mov    0x8(%rsp),%r10
 10348a6:	mov    (%rsp),%r8
 10348aa:	lea    0x2632f(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10348b1:	mov    %rax,%r15
 10348b4:	jmp    1034162 <my.app::main+0x772>
 10348b9:	mov    $0x8,%esi
 10348be:	xor    %edi,%edi
 10348c0:	vzeroupper
 10348c3:	call   1009480 <myl_core_list_new_slow>
 10348c8:	vxorps %xmm1,%xmm1,%xmm1
 10348cc:	xor    %r11d,%r11d
 10348cf:	mov    0x8(%rsp),%r10
 10348d4:	mov    (%rsp),%r8
 10348d8:	lea    0x26301(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10348df:	jmp    1034186 <my.app::main+0x796>
 10348e4:	mov    $0x2,%edi
 10348e9:	mov    $0x8,%esi
 10348ee:	vzeroupper
 10348f1:	call   1009480 <myl_core_list_new_slow>
 10348f6:	mov    %rax,%rdi
 10348f9:	mov    0x8(%rax),%rdx
 10348fd:	mov    0x10(%rax),%rcx
 1034901:	cmp    %rcx,%rdx
 1034904:	jb     10349da <my.app::main+0xfea>
 103490a:	mov    $0x8,%esi
 103490f:	call   10094f0 <myl_core_list_grow>
 1034914:	mov    0x8(%rax),%rdx
 1034918:	mov    0x10(%rax),%rcx
 103491c:	lea    0x262bd(%rip),%r9        # 105abe0 <myl_core_free_lists>
 1034923:	mov    %rax,%rdi
 1034926:	mov    (%rsp),%r8
 103492a:	mov    0x8(%rsp),%r10
 103492f:	xor    %r11d,%r11d
 1034932:	vxorps %xmm1,%xmm1,%xmm1
 1034936:	jmp    10341b2 <my.app::main+0x7c2>
 103493b:	mov    $0x8,%esi
 1034940:	vzeroupper
 1034943:	call   10094f0 <myl_core_list_grow>
 1034948:	vxorps %xmm1,%xmm1,%xmm1
 103494c:	xor    %r11d,%r11d
 103494f:	mov    0x8(%rsp),%r10
 1034954:	mov    (%rsp),%r8
 1034958:	lea    0x26281(%rip),%r9        # 105abe0 <myl_core_free_lists>
 103495f:	mov    %rax,%rdi
 1034962:	mov    0x8(%rax),%rdx
 1034966:	jmp    10341cb <my.app::main+0x7db>
 103496b:	vzeroupper
 103496e:	call   1032790 <myl_core_free_block>
 1034973:	vxorps %xmm1,%xmm1,%xmm1
 1034977:	xor    %r11d,%r11d
 103497a:	mov    0x8(%rsp),%r10
 103497f:	mov    (%rsp),%r8
 1034983:	lea    0x26256(%rip),%r9        # 105abe0 <myl_core_free_lists>
 103498a:	jmp    10347b3 <my.app::main+0xdc3>
 103498f:	vzeroupper
 1034992:	call   1032790 <myl_core_free_block>
 1034997:	vxorps %xmm1,%xmm1,%xmm1
 103499b:	xor    %r11d,%r11d
 103499e:	mov    0x8(%rsp),%r10
 10349a3:	mov    (%rsp),%r8
 10349a7:	lea    0x26232(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10349ae:	jmp    10347e5 <my.app::main+0xdf5>
 10349b3:	mov    %r15,%rdi
 10349b6:	vzeroupper
 10349b9:	call   1032790 <myl_core_free_block>
 10349be:	vxorps %xmm1,%xmm1,%xmm1
 10349c2:	xor    %r11d,%r11d
 10349c5:	mov    0x8(%rsp),%r10
 10349ca:	mov    (%rsp),%r8
 10349ce:	lea    0x2620b(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10349d5:	jmp    103482f <my.app::main+0xe3f>
 10349da:	lea    0x261ff(%rip),%r9        # 105abe0 <myl_core_free_lists>
 10349e1:	jmp    1034926 <my.app::main+0xf36>
 10349e6:	mov    (%r10),%eax
 10349e9:	mov    $0x2,%ebx
 10349ee:	cmp    $0xffffffff,%eax
 10349f1:	je     1034acc <my.app::main+0x10dc>
 10349f7:	dec    %eax
 10349f9:	je     1034a28 <my.app::main+0x1038>
 10349fb:	mov    %eax,(%r10)
 10349fe:	jmp    1034acc <my.app::main+0x10dc>
 1034a03:	mov    (%r10),%eax
 1034a06:	cmp    $0xffffffff,%eax
 1034a09:	mov    0x18(%rsp),%r14
 1034a0e:	je     1034a72 <my.app::main+0x1082>
 1034a10:	dec    %eax
 1034a12:	je     1034a4e <my.app::main+0x105e>
 1034a14:	mov    %eax,(%r10)
 1034a17:	jmp    1034a72 <my.app::main+0x1082>
 1034a19:	lea    0x1fd0(%rip),%rdi        # 10369f0 <core_io_file_error.verbs+0x440>
 1034a20:	vzeroupper
 1034a23:	call   1009b80 <myl_core_trap>
 1034a28:	movzbl 0x7(%r10),%eax
 1034a2d:	test   %rax,%rax
 1034a30:	je     103501a <my.app::main+0x162a>
 1034a36:	cmpq   $0x0,0x18(%r10)
 1034a3b:	jne    103501a <my.app::main+0x162a>
 1034a41:	mov    (%r9,%rax,8),%rcx
 1034a45:	mov    %rcx,(%r10)
 1034a48:	mov    %r10,(%r9,%rax,8)
 1034a4c:	jmp    1034acc <my.app::main+0x10dc>
 1034a4e:	movzbl 0x7(%r10),%eax
 1034a53:	test   %rax,%rax
 1034a56:	je     103502a <my.app::main+0x163a>
 1034a5c:	cmpq   $0x0,0x18(%r10)
 1034a61:	jne    103502a <my.app::main+0x163a>
 1034a67:	mov    (%r9,%rax,8),%rcx
 1034a6b:	mov    %rcx,(%r10)
 1034a6e:	mov    %r10,(%r9,%rax,8)
 1034a72:	lea    0x1eb7(%rip),%rdi        # 1036930 <core_io_file_error.verbs+0x380>
 1034a79:	vzeroupper
 1034a7c:	call   100a4c0 <myl_core_io_at>
 1034a81:	mov    %r14,%rdi
 1034a84:	call   1022430 <myl_core_host_check>
 1034a89:	call   10350b0 <runtime_bench_now>
 1034a8e:	mov    %rax,%r14
 1034a91:	mov    0x28(%rsp),%rdx
 1034a96:	sub    %rdx,%r14
 1034a99:	jo     1035095 <my.app::main+0x16a5>
 1034a9f:	mov    0x30(%rsp),%r15
 1034aa4:	mov    %r15,%rdi
 1034aa7:	mov    %rbx,%rsi
 1034aaa:	call   100abc0 <myl_core_print_i64>
 1034aaf:	mov    %r15,%rdi
 1034ab2:	call   1009200 <myl_core_print_sep>
 1034ab7:	mov    %r15,%rdi
 1034aba:	mov    %r14,%rsi
 1034abd:	call   100abc0 <myl_core_print_i64>
 1034ac2:	mov    %r15,%rdi
 1034ac5:	call   10092c0 <myl_core_print_end>
 1034aca:	xor    %ebx,%ebx
 1034acc:	mov    %rbx,%rax
 1034acf:	add    $0x58,%rsp
 1034ad3:	pop    %rbx
 1034ad4:	pop    %r12
 1034ad6:	pop    %r13
 1034ad8:	pop    %r14
 1034ada:	pop    %r15
 1034adc:	pop    %rbp
 1034add:	vzeroupper
 1034ae0:	ret
 1034ae1:	lea    0x1f38(%rip),%rdi        # 1036a20 <core_io_file_error.verbs+0x470>
 1034ae8:	mov    $0x1,%edx
 1034aed:	mov    %rax,%rsi
 1034af0:	vzeroupper
 1034af3:	call   1009b80 <myl_core_trap>
 1034af8:	lea    0x1fb1(%rip),%rdi        # 1036ab0 <core_io_file_error.verbs+0x500>
 1034aff:	vzeroupper
 1034b02:	call   1009b80 <myl_core_trap>
 1034b07:	lea    0x1f72(%rip),%rdi        # 1036a80 <core_io_file_error.verbs+0x4d0>
 1034b0e:	xor    %esi,%esi
 1034b10:	xor    %edx,%edx
 1034b12:	vzeroupper
 1034b15:	call   1009b80 <myl_core_trap>
 1034b1a:	lea    0x1f2f(%rip),%rdi        # 1036a50 <core_io_file_error.verbs+0x4a0>
 1034b21:	vzeroupper
 1034b24:	call   1009b80 <myl_core_trap>
 1034b29:	lea    0x1fe0(%rip),%rdi        # 1036b10 <core_io_file_error.verbs+0x560>
 1034b30:	xor    %esi,%esi
 1034b32:	xor    %edx,%edx
 1034b34:	vzeroupper
 1034b37:	call   1009b80 <myl_core_trap>
 1034b3c:	lea    0x1f9d(%rip),%rdi        # 1036ae0 <core_io_file_error.verbs+0x530>
 1034b43:	xor    %esi,%esi
 1034b45:	xor    %edx,%edx
 1034b47:	vzeroupper
 1034b4a:	call   1009b80 <myl_core_trap>
 1034b4f:	mov    $0x26,%edi
 1034b54:	mov    $0x10,%esi
 1034b59:	call   1009480 <myl_core_list_new_slow>
 1034b5e:	mov    0x8(%rax),%rsi
 1034b62:	mov    0x10(%rax),%rcx
 1034b66:	cmp    %rcx,%rsi
 1034b69:	jb     1033abc <my.app::main+0xcc>
 1034b6f:	mov    $0x10,%esi
 1034b74:	mov    %rax,%rdi
 1034b77:	call   10094f0 <myl_core_list_grow>
 1034b7c:	mov    0x8(%rax),%rsi
 1034b80:	mov    0x10(%rax),%rcx
 1034b84:	jmp    1033abc <my.app::main+0xcc>
 1034b89:	mov    $0x10,%esi
 1034b8e:	mov    %rax,%rdi
 1034b91:	vzeroupper
 1034b94:	call   10094f0 <myl_core_list_grow>
 1034b99:	mov    0x8(%rax),%rsi
 1034b9d:	mov    0x10(%rax),%rcx
 1034ba1:	jmp    1033add <my.app::main+0xed>
 1034ba6:	mov    $0x10,%esi
 1034bab:	mov    %rax,%rdi
 1034bae:	vzeroupper
 1034bb1:	call   10094f0 <myl_core_list_grow>
 1034bb6:	mov    0x8(%rax),%rsi
 1034bba:	mov    0x10(%rax),%rcx
 1034bbe:	jmp    1033b06 <my.app::main+0x116>
 1034bc3:	mov    $0x10,%esi
 1034bc8:	mov    %rax,%rdi
 1034bcb:	vzeroupper
 1034bce:	call   10094f0 <myl_core_list_grow>
 1034bd3:	mov    0x8(%rax),%rsi
 1034bd7:	mov    0x10(%rax),%rcx
 1034bdb:	jmp    1033b2f <my.app::main+0x13f>
 1034be0:	mov    $0x10,%esi
 1034be5:	mov    %rax,%rdi
 1034be8:	vzeroupper
 1034beb:	call   10094f0 <myl_core_list_grow>
 1034bf0:	mov    0x8(%rax),%rsi
 1034bf4:	mov    0x10(%rax),%rcx
 1034bf8:	jmp    1033b58 <my.app::main+0x168>
 1034bfd:	mov    $0x10,%esi
 1034c02:	mov    %rax,%rdi
 1034c05:	vzeroupper
 1034c08:	call   10094f0 <myl_core_list_grow>
 1034c0d:	mov    0x8(%rax),%rsi
 1034c11:	mov    0x10(%rax),%rcx
 1034c15:	jmp    1033b81 <my.app::main+0x191>
 1034c1a:	mov    $0x10,%esi
 1034c1f:	mov    %rax,%rdi
 1034c22:	vzeroupper
 1034c25:	call   10094f0 <myl_core_list_grow>
 1034c2a:	mov    0x8(%rax),%rsi
 1034c2e:	mov    0x10(%rax),%rcx
 1034c32:	jmp    1033baa <my.app::main+0x1ba>
 1034c37:	mov    $0x10,%esi
 1034c3c:	mov    %rax,%rdi
 1034c3f:	vzeroupper
 1034c42:	call   10094f0 <myl_core_list_grow>
 1034c47:	mov    0x8(%rax),%rsi
 1034c4b:	mov    0x10(%rax),%rcx
 1034c4f:	jmp    1033bd3 <my.app::main+0x1e3>
 1034c54:	mov    $0x10,%esi
 1034c59:	mov    %rax,%rdi
 1034c5c:	vzeroupper
 1034c5f:	call   10094f0 <myl_core_list_grow>
 1034c64:	mov    0x8(%rax),%rsi
 1034c68:	mov    0x10(%rax),%rcx
 1034c6c:	jmp    1033bfc <my.app::main+0x20c>
 1034c71:	mov    $0x10,%esi
 1034c76:	mov    %rax,%rdi
 1034c79:	vzeroupper
 1034c7c:	call   10094f0 <myl_core_list_grow>
 1034c81:	mov    0x8(%rax),%rsi
 1034c85:	mov    0x10(%rax),%rcx
 1034c89:	jmp    1033c25 <my.app::main+0x235>
 1034c8e:	mov    $0x10,%esi
 1034c93:	mov    %rax,%rdi
 1034c96:	vzeroupper
 1034c99:	call   10094f0 <myl_core_list_grow>
 1034c9e:	mov    0x8(%rax),%rsi
 1034ca2:	mov    0x10(%rax),%rcx
 1034ca6:	jmp    1033c4e <my.app::main+0x25e>
 1034cab:	mov    $0x10,%esi
 1034cb0:	mov    %rax,%rdi
 1034cb3:	vzeroupper
 1034cb6:	call   10094f0 <myl_core_list_grow>
 1034cbb:	mov    0x8(%rax),%rsi
 1034cbf:	mov    0x10(%rax),%rcx
 1034cc3:	jmp    1033c77 <my.app::main+0x287>
 1034cc8:	mov    $0x10,%esi
 1034ccd:	mov    %rax,%rdi
 1034cd0:	vzeroupper
 1034cd3:	call   10094f0 <myl_core_list_grow>
 1034cd8:	mov    0x8(%rax),%rsi
 1034cdc:	mov    0x10(%rax),%rcx
 1034ce0:	jmp    1033ca0 <my.app::main+0x2b0>
 1034ce5:	mov    $0x10,%esi
 1034cea:	mov    %rax,%rdi
 1034ced:	vzeroupper
 1034cf0:	call   10094f0 <myl_core_list_grow>
 1034cf5:	mov    0x8(%rax),%rsi
 1034cf9:	mov    0x10(%rax),%rcx
 1034cfd:	jmp    1033cc9 <my.app::main+0x2d9>
 1034d02:	mov    $0x10,%esi
 1034d07:	mov    %rax,%rdi
 1034d0a:	vzeroupper
 1034d0d:	call   10094f0 <myl_core_list_grow>
 1034d12:	mov    0x8(%rax),%rsi
 1034d16:	mov    0x10(%rax),%rcx
 1034d1a:	jmp    1033cf2 <my.app::main+0x302>
 1034d1f:	mov    $0x10,%esi
 1034d24:	mov    %rax,%rdi
 1034d27:	vzeroupper
 1034d2a:	call   10094f0 <myl_core_list_grow>
 1034d2f:	mov    0x8(%rax),%rsi
 1034d33:	mov    0x10(%rax),%rcx
 1034d37:	jmp    1033d1b <my.app::main+0x32b>
 1034d3c:	mov    $0x10,%esi
 1034d41:	mov    %rax,%rdi
 1034d44:	vzeroupper
 1034d47:	call   10094f0 <myl_core_list_grow>
 1034d4c:	mov    0x8(%rax),%rsi
 1034d50:	mov    0x10(%rax),%rcx
 1034d54:	jmp    1033d44 <my.app::main+0x354>
 1034d59:	mov    $0x10,%esi
 1034d5e:	mov    %rax,%rdi
 1034d61:	vzeroupper
 1034d64:	call   10094f0 <myl_core_list_grow>
 1034d69:	mov    0x8(%rax),%rsi
 1034d6d:	mov    0x10(%rax),%rcx
 1034d71:	jmp    1033d6d <my.app::main+0x37d>
 1034d76:	mov    $0x10,%esi
 1034d7b:	mov    %rax,%rdi
 1034d7e:	vzeroupper
 1034d81:	call   10094f0 <myl_core_list_grow>
 1034d86:	mov    0x8(%rax),%rsi
 1034d8a:	mov    0x10(%rax),%rcx
 1034d8e:	jmp    1033d96 <my.app::main+0x3a6>
 1034d93:	mov    $0x10,%esi
 1034d98:	mov    %rax,%rdi
 1034d9b:	vzeroupper
 1034d9e:	call   10094f0 <myl_core_list_grow>
 1034da3:	mov    0x8(%rax),%rsi
 1034da7:	mov    0x10(%rax),%rcx
 1034dab:	jmp    1033dbf <my.app::main+0x3cf>
 1034db0:	mov    $0x10,%esi
 1034db5:	mov    %rax,%rdi
 1034db8:	vzeroupper
 1034dbb:	call   10094f0 <myl_core_list_grow>
 1034dc0:	mov    0x8(%rax),%rsi
 1034dc4:	mov    0x10(%rax),%rcx
 1034dc8:	jmp    1033de8 <my.app::main+0x3f8>
 1034dcd:	mov    $0x10,%esi
 1034dd2:	mov    %rax,%rdi
 1034dd5:	vzeroupper
 1034dd8:	call   10094f0 <myl_core_list_grow>
 1034ddd:	mov    0x8(%rax),%rsi
 1034de1:	mov    0x10(%rax),%rcx
 1034de5:	jmp    1033e11 <my.app::main+0x421>
 1034dea:	mov    $0x10,%esi
 1034def:	mov    %rax,%rdi
 1034df2:	vzeroupper
 1034df5:	call   10094f0 <myl_core_list_grow>
 1034dfa:	mov    0x8(%rax),%rsi
 1034dfe:	mov    0x10(%rax),%rcx
 1034e02:	jmp    1033e3a <my.app::main+0x44a>
 1034e07:	mov    $0x10,%esi
 1034e0c:	mov    %rax,%rdi
 1034e0f:	vzeroupper
 1034e12:	call   10094f0 <myl_core_list_grow>
 1034e17:	mov    0x8(%rax),%rsi
 1034e1b:	mov    0x10(%rax),%rcx
 1034e1f:	jmp    1033e63 <my.app::main+0x473>
 1034e24:	mov    $0x10,%esi
 1034e29:	mov    %rax,%rdi
 1034e2c:	vzeroupper
 1034e2f:	call   10094f0 <myl_core_list_grow>
 1034e34:	mov    0x8(%rax),%rsi
 1034e38:	mov    0x10(%rax),%rcx
 1034e3c:	jmp    1033e8c <my.app::main+0x49c>
 1034e41:	mov    $0x10,%esi
 1034e46:	mov    %rax,%rdi
 1034e49:	vzeroupper
 1034e4c:	call   10094f0 <myl_core_list_grow>
 1034e51:	mov    0x8(%rax),%rsi
 1034e55:	mov    0x10(%rax),%rcx
 1034e59:	jmp    1033eb5 <my.app::main+0x4c5>
 1034e5e:	mov    $0x10,%esi
 1034e63:	mov    %rax,%rdi
 1034e66:	vzeroupper
 1034e69:	call   10094f0 <myl_core_list_grow>
 1034e6e:	mov    0x8(%rax),%rsi
 1034e72:	mov    0x10(%rax),%rcx
 1034e76:	jmp    1033ede <my.app::main+0x4ee>
 1034e7b:	mov    $0x10,%esi
 1034e80:	mov    %rax,%rdi
 1034e83:	vzeroupper
 1034e86:	call   10094f0 <myl_core_list_grow>
 1034e8b:	mov    0x8(%rax),%rsi
 1034e8f:	mov    0x10(%rax),%rcx
 1034e93:	jmp    1033f07 <my.app::main+0x517>
 1034e98:	mov    $0x10,%esi
 1034e9d:	mov    %rax,%rdi
 1034ea0:	vzeroupper
 1034ea3:	call   10094f0 <myl_core_list_grow>
 1034ea8:	mov    0x8(%rax),%rsi
 1034eac:	mov    0x10(%rax),%rcx
 1034eb0:	jmp    1033f30 <my.app::main+0x540>
 1034eb5:	mov    $0x10,%esi
 1034eba:	mov    %rax,%rdi
 1034ebd:	vzeroupper
 1034ec0:	call   10094f0 <myl_core_list_grow>
 1034ec5:	mov    0x8(%rax),%rsi
 1034ec9:	mov    0x10(%rax),%rcx
 1034ecd:	jmp    1033f59 <my.app::main+0x569>
 1034ed2:	mov    $0x10,%esi
 1034ed7:	mov    %rax,%rdi
 1034eda:	vzeroupper
 1034edd:	call   10094f0 <myl_core_list_grow>
 1034ee2:	mov    0x8(%rax),%rsi
 1034ee6:	mov    0x10(%rax),%rcx
 1034eea:	jmp    1033f82 <my.app::main+0x592>
 1034eef:	mov    $0x10,%esi
 1034ef4:	mov    %rax,%rdi
 1034ef7:	vzeroupper
 1034efa:	call   10094f0 <myl_core_list_grow>
 1034eff:	mov    0x8(%rax),%rsi
 1034f03:	mov    0x10(%rax),%rcx
 1034f07:	jmp    1033fab <my.app::main+0x5bb>
 1034f0c:	mov    $0x10,%esi
 1034f11:	mov    %rax,%rdi
 1034f14:	vzeroupper
 1034f17:	call   10094f0 <myl_core_list_grow>
 1034f1c:	mov    0x8(%rax),%rsi
 1034f20:	mov    0x10(%rax),%rcx
 1034f24:	jmp    1033fd4 <my.app::main+0x5e4>
 1034f29:	mov    $0x10,%esi
 1034f2e:	mov    %rax,%rdi
 1034f31:	vzeroupper
 1034f34:	call   10094f0 <myl_core_list_grow>
 1034f39:	mov    0x8(%rax),%rsi
 1034f3d:	mov    0x10(%rax),%rcx
 1034f41:	jmp    1033ffd <my.app::main+0x60d>
 1034f46:	mov    $0x10,%esi
 1034f4b:	mov    %rax,%rdi
 1034f4e:	vzeroupper
 1034f51:	call   10094f0 <myl_core_list_grow>
 1034f56:	mov    0x8(%rax),%rsi
 1034f5a:	mov    0x10(%rax),%rcx
 1034f5e:	jmp    1034026 <my.app::main+0x636>
 1034f63:	mov    $0x10,%esi
 1034f68:	mov    %rax,%rdi
 1034f6b:	vzeroupper
 1034f6e:	call   10094f0 <myl_core_list_grow>
 1034f73:	mov    0x8(%rax),%rsi
 1034f77:	mov    0x10(%rax),%rcx
 1034f7b:	jmp    103404f <my.app::main+0x65f>
 1034f80:	mov    $0x10,%esi
 1034f85:	mov    %rax,%rdi
 1034f88:	vzeroupper
 1034f8b:	call   10094f0 <myl_core_list_grow>
 1034f90:	mov    0x8(%rax),%rsi
 1034f94:	mov    0x10(%rax),%rcx
 1034f98:	jmp    1034078 <my.app::main+0x688>
 1034f9d:	mov    $0x10,%esi
 1034fa2:	mov    %rax,%rdi
 1034fa5:	vzeroupper
 1034fa8:	call   10094f0 <myl_core_list_grow>
 1034fad:	mov    0x8(%rax),%rsi
 1034fb1:	jmp    10340a6 <my.app::main+0x6b6>
 1034fb6:	lea    0x1c13(%rip),%rdi        # 1036bd0 <core_io_file_error.verbs+0x620>
 1034fbd:	xor    %esi,%esi
 1034fbf:	xor    %edx,%edx
 1034fc1:	vzeroupper
 1034fc4:	call   1009b80 <myl_core_trap>
 1034fc9:	lea    0x1c30(%rip),%rdi        # 1036c00 <core_io_file_error.verbs+0x650>
 1034fd0:	xor    %esi,%esi
 1034fd2:	xor    %edx,%edx
 1034fd4:	vzeroupper
 1034fd7:	call   1009b80 <myl_core_trap>
 1034fdc:	lea    0x1b8d(%rip),%rdi        # 1036b70 <core_io_file_error.verbs+0x5c0>
 1034fe3:	mov    %rbx,%rsi
 1034fe6:	mov    %rbp,%rdx
 1034fe9:	vzeroupper
 1034fec:	call   1009b80 <myl_core_trap>
 1034ff1:	lea    0x1ba8(%rip),%rdi        # 1036ba0 <core_io_file_error.verbs+0x5f0>
 1034ff8:	mov    %rbx,%rsi
 1034ffb:	xor    %edx,%edx
 1034ffd:	vzeroupper
 1035000:	call   1009b80 <myl_core_trap>
 1035005:	lea    0x1b34(%rip),%rdi        # 1036b40 <core_io_file_error.verbs+0x590>
 103500c:	mov    %rbx,%rsi
 103500f:	mov    %rbp,%rdx
 1035012:	vzeroupper
 1035015:	call   1009b80 <myl_core_trap>
 103501a:	mov    %r10,%rdi
 103501d:	vzeroupper
 1035020:	call   1032790 <myl_core_free_block>
 1035025:	jmp    1034acc <my.app::main+0x10dc>
 103502a:	mov    %r10,%rdi
 103502d:	vzeroupper
 1035030:	call   1032790 <myl_core_free_block>
 1035035:	jmp    1034a72 <my.app::main+0x1082>
 103503a:	lea    0x197f(%rip),%rdi        # 10369c0 <core_io_file_error.verbs+0x410>
 1035041:	mov    0x20(%rsp),%rsi
 1035046:	vzeroupper
 1035049:	call   1009b80 <myl_core_trap>
 103504e:	lea    0x1bdb(%rip),%rdi        # 1036c30 <core_io_file_error.verbs+0x680>
 1035055:	xor    %esi,%esi
 1035057:	xor    %edx,%edx
 1035059:	vzeroupper
 103505c:	call   1009b80 <myl_core_trap>
 1035061:	lea    0x1928(%rip),%rdi        # 1036990 <core_io_file_error.verbs+0x3e0>
 1035068:	mov    %r14,%rdx
 103506b:	vzeroupper
 103506e:	call   1009b80 <myl_core_trap>
 1035073:	lea    0x1826(%rip),%rdi        # 10368a0 <core_io_file_error.verbs+0x2f0>
 103507a:	mov    $0x1,%esi
 103507f:	call   1009b80 <myl_core_trap>
 1035084:	lea    0x1845(%rip),%rdi        # 10368d0 <core_io_file_error.verbs+0x320>
 103508b:	mov    $0x2,%esi
 1035090:	call   1009b80 <myl_core_trap>
 1035095:	lea    0x18c4(%rip),%rdi        # 1036960 <core_io_file_error.verbs+0x3b0>
 103509c:	mov    %rax,%rsi
 103509f:	call   1009b80 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
