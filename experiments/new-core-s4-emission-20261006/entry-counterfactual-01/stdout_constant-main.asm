
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-emission/experiments/new-core-s4-emission-20261006/entry-counterfactual-01/stdout_constant/program:     file format elf64-x86-64


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
 1033a08:	jne    1034ae9 <my.app::main+0x10f9>
 1033a0e:	mov    %rsi,%r15
 1033a11:	mov    %rdi,%r14
 1033a14:	mov    0x20(%rdi),%rdi
 1033a18:	call   1032e00 <my.workload::parse_number>
 1033a1d:	mov    %rax,0x8(%rsp)
 1033a22:	mov    0x8(%r14),%rdx
 1033a26:	cmp    $0x1,%rdx
 1033a2a:	jbe    1035090 <my.app::main+0x16a0>
 1033a30:	mov    0x28(%r14),%rdi
 1033a34:	call   1032e00 <my.workload::parse_number>
 1033a39:	mov    0x8(%r14),%rdx
 1033a3d:	cmp    $0x2,%rdx
 1033a41:	jbe    10350a1 <my.app::main+0x16b1>
 1033a47:	mov    %rax,%r12
 1033a4a:	mov    0x30(%r14),%rdi
 1033a4e:	call   1032e00 <my.workload::parse_number>
 1033a53:	cmpq   $0x2,0x8(%rsp)
 1033a59:	setl   %dl
 1033a5c:	test   %r12,%r12
 1033a5f:	setle  %cl
 1033a62:	or     %dl,%cl
 1033a64:	mov    %rax,0x28(%rsp)
 1033a69:	add    $0xfffffffffff0bdbf,%rax
 1033a6f:	cmp    $0xfffffffffff0bdc0,%rax
 1033a75:	setb   %al
 1033a78:	or     %cl,%al
 1033a7a:	jne    1034ae9 <my.app::main+0x10f9>
 1033a80:	lea    0x27179(%rip),%rcx        # 105ac00 <myl_core_free_lists>
 1033a87:	mov    0xa0(%rcx),%rax
 1033a8e:	test   %rax,%rax
 1033a91:	mov    %r12,0x38(%rsp)
 1033a96:	je     1034b6c <my.app::main+0x117c>
 1033a9c:	mov    (%rax),%rdx
 1033a9f:	mov    %rdx,0xa0(%rcx)
 1033aa6:	vmovaps -0x3040e(%rip),%ymm0        # 10036a0 <core_io_raw_layout+0x120>
 1033aae:	vmovups %ymm0,(%rax)
 1033ab2:	mov    $0x26,%ecx
 1033ab7:	xor    %esi,%esi
 1033ab9:	mov    %rsi,%rdx
 1033abc:	shl    $0x4,%rdx
 1033ac0:	inc    %rsi
 1033ac3:	vxorps %xmm0,%xmm0,%xmm0
 1033ac7:	vmovups %xmm0,0x20(%rax,%rdx,1)
 1033acd:	mov    %rsi,0x8(%rax)
 1033ad1:	cmp    %rcx,%rsi
 1033ad4:	jae    1034ba6 <my.app::main+0x11b6>
 1033ada:	mov    %rsi,%rdx
 1033add:	shl    $0x4,%rdx
 1033ae1:	movq   $0x4,0x20(%rax,%rdx,1)
 1033aea:	movq   $0x0,0x28(%rax,%rdx,1)
 1033af3:	inc    %rsi
 1033af6:	mov    %rsi,0x8(%rax)
 1033afa:	cmp    %rcx,%rsi
 1033afd:	jae    1034bc3 <my.app::main+0x11d3>
 1033b03:	mov    %rsi,%rdx
 1033b06:	shl    $0x4,%rdx
 1033b0a:	movq   $0x2,0x20(%rax,%rdx,1)
 1033b13:	movq   $0x0,0x28(%rax,%rdx,1)
 1033b1c:	inc    %rsi
 1033b1f:	mov    %rsi,0x8(%rax)
 1033b23:	cmp    %rcx,%rsi
 1033b26:	jae    1034be0 <my.app::main+0x11f0>
 1033b2c:	mov    %rsi,%rdx
 1033b2f:	shl    $0x4,%rdx
 1033b33:	movq   $0x4,0x20(%rax,%rdx,1)
 1033b3c:	movq   $0x1,0x28(%rax,%rdx,1)
 1033b45:	inc    %rsi
 1033b48:	mov    %rsi,0x8(%rax)
 1033b4c:	cmp    %rcx,%rsi
 1033b4f:	jae    1034bfd <my.app::main+0x120d>
 1033b55:	mov    %rsi,%rdx
 1033b58:	shl    $0x4,%rdx
 1033b5c:	movq   $0x3,0x20(%rax,%rdx,1)
 1033b65:	movq   $0x1,0x28(%rax,%rdx,1)
 1033b6e:	inc    %rsi
 1033b71:	mov    %rsi,0x8(%rax)
 1033b75:	cmp    %rcx,%rsi
 1033b78:	jae    1034c1a <my.app::main+0x122a>
 1033b7e:	mov    %rsi,%rdx
 1033b81:	shl    $0x4,%rdx
 1033b85:	movq   $0x1,0x20(%rax,%rdx,1)
 1033b8e:	movq   $0x0,0x28(%rax,%rdx,1)
 1033b97:	inc    %rsi
 1033b9a:	mov    %rsi,0x8(%rax)
 1033b9e:	cmp    %rcx,%rsi
 1033ba1:	jae    1034c37 <my.app::main+0x1247>
 1033ba7:	mov    %rsi,%rdx
 1033baa:	shl    $0x4,%rdx
 1033bae:	movq   $0x8,0x20(%rax,%rdx,1)
 1033bb7:	movq   $0x0,0x28(%rax,%rdx,1)
 1033bc0:	inc    %rsi
 1033bc3:	mov    %rsi,0x8(%rax)
 1033bc7:	cmp    %rcx,%rsi
 1033bca:	jae    1034c54 <my.app::main+0x1264>
 1033bd0:	mov    %rsi,%rdx
 1033bd3:	shl    $0x4,%rdx
 1033bd7:	movq   $0xa,0x20(%rax,%rdx,1)
 1033be0:	movq   $0x1d,0x28(%rax,%rdx,1)
 1033be9:	inc    %rsi
 1033bec:	mov    %rsi,0x8(%rax)
 1033bf0:	cmp    %rcx,%rsi
 1033bf3:	jae    1034c71 <my.app::main+0x1281>
 1033bf9:	mov    %rsi,%rdx
 1033bfc:	shl    $0x4,%rdx
 1033c00:	movq   $0x3,0x20(%rax,%rdx,1)
 1033c09:	movq   $0x1,0x28(%rax,%rdx,1)
 1033c12:	inc    %rsi
 1033c15:	mov    %rsi,0x8(%rax)
 1033c19:	cmp    %rcx,%rsi
 1033c1c:	jae    1034c8e <my.app::main+0x129e>
 1033c22:	mov    %rsi,%rdx
 1033c25:	shl    $0x4,%rdx
 1033c29:	movq   $0x2,0x20(%rax,%rdx,1)
 1033c32:	movq   $0x2,0x28(%rax,%rdx,1)
 1033c3b:	inc    %rsi
 1033c3e:	mov    %rsi,0x8(%rax)
 1033c42:	cmp    %rcx,%rsi
 1033c45:	jae    1034cab <my.app::main+0x12bb>
 1033c4b:	mov    %rsi,%rdx
 1033c4e:	shl    $0x4,%rdx
 1033c52:	movq   $0x7,0x20(%rax,%rdx,1)
 1033c5b:	movq   $0x0,0x28(%rax,%rdx,1)
 1033c64:	inc    %rsi
 1033c67:	mov    %rsi,0x8(%rax)
 1033c6b:	cmp    %rcx,%rsi
 1033c6e:	jae    1034cc8 <my.app::main+0x12d8>
 1033c74:	mov    %rsi,%rdx
 1033c77:	shl    $0x4,%rdx
 1033c7b:	movq   $0x2,0x20(%rax,%rdx,1)
 1033c84:	movq   $0x0,0x28(%rax,%rdx,1)
 1033c8d:	inc    %rsi
 1033c90:	mov    %rsi,0x8(%rax)
 1033c94:	cmp    %rcx,%rsi
 1033c97:	jae    1034ce5 <my.app::main+0x12f5>
 1033c9d:	mov    %rsi,%rdx
 1033ca0:	shl    $0x4,%rdx
 1033ca4:	movq   $0x9,0x20(%rax,%rdx,1)
 1033cad:	movq   $0x0,0x28(%rax,%rdx,1)
 1033cb6:	inc    %rsi
 1033cb9:	mov    %rsi,0x8(%rax)
 1033cbd:	cmp    %rcx,%rsi
 1033cc0:	jae    1034d02 <my.app::main+0x1312>
 1033cc6:	mov    %rsi,%rdx
 1033cc9:	shl    $0x4,%rdx
 1033ccd:	movq   $0xa,0x20(%rax,%rdx,1)
 1033cd6:	movq   $0x12,0x28(%rax,%rdx,1)
 1033cdf:	inc    %rsi
 1033ce2:	mov    %rsi,0x8(%rax)
 1033ce6:	cmp    %rcx,%rsi
 1033ce9:	jae    1034d1f <my.app::main+0x132f>
 1033cef:	mov    %rsi,%rdx
 1033cf2:	shl    $0x4,%rdx
 1033cf6:	movq   $0x3,0x20(%rax,%rdx,1)
 1033cff:	movq   $0x0,0x28(%rax,%rdx,1)
 1033d08:	inc    %rsi
 1033d0b:	mov    %rsi,0x8(%rax)
 1033d0f:	cmp    %rcx,%rsi
 1033d12:	jae    1034d3c <my.app::main+0x134c>
 1033d18:	mov    %rsi,%rdx
 1033d1b:	shl    $0x4,%rdx
 1033d1f:	movq   $0xc,0x20(%rax,%rdx,1)
 1033d28:	movq   $0x1f,0x28(%rax,%rdx,1)
 1033d31:	inc    %rsi
 1033d34:	mov    %rsi,0x8(%rax)
 1033d38:	cmp    %rcx,%rsi
 1033d3b:	jae    1034d59 <my.app::main+0x1369>
 1033d41:	mov    %rsi,%rdx
 1033d44:	shl    $0x4,%rdx
 1033d48:	movq   $0x4,0x20(%rax,%rdx,1)
 1033d51:	movq   $0x0,0x28(%rax,%rdx,1)
 1033d5a:	inc    %rsi
 1033d5d:	mov    %rsi,0x8(%rax)
 1033d61:	cmp    %rcx,%rsi
 1033d64:	jae    1034d76 <my.app::main+0x1386>
 1033d6a:	mov    %rsi,%rdx
 1033d6d:	shl    $0x4,%rdx
 1033d71:	movq   $0xb,0x20(%rax,%rdx,1)
 1033d7a:	movq   $0x18,0x28(%rax,%rdx,1)
 1033d83:	inc    %rsi
 1033d86:	mov    %rsi,0x8(%rax)
 1033d8a:	cmp    %rcx,%rsi
 1033d8d:	jae    1034d93 <my.app::main+0x13a3>
 1033d93:	mov    %rsi,%rdx
 1033d96:	shl    $0x4,%rdx
 1033d9a:	movq   $0x3,0x20(%rax,%rdx,1)
 1033da3:	movq   $0x0,0x28(%rax,%rdx,1)
 1033dac:	inc    %rsi
 1033daf:	mov    %rsi,0x8(%rax)
 1033db3:	cmp    %rcx,%rsi
 1033db6:	jae    1034db0 <my.app::main+0x13c0>
 1033dbc:	mov    %rsi,%rdx
 1033dbf:	shl    $0x4,%rdx
 1033dc3:	movq   $0x3,0x20(%rax,%rdx,1)
 1033dcc:	movq   $0x1,0x28(%rax,%rdx,1)
 1033dd5:	inc    %rsi
 1033dd8:	mov    %rsi,0x8(%rax)
 1033ddc:	cmp    %rcx,%rsi
 1033ddf:	jae    1034dcd <my.app::main+0x13dd>
 1033de5:	mov    %rsi,%rdx
 1033de8:	shl    $0x4,%rdx
 1033dec:	movq   $0x5,0x20(%rax,%rdx,1)
 1033df5:	movq   $0x0,0x28(%rax,%rdx,1)
 1033dfe:	inc    %rsi
 1033e01:	mov    %rsi,0x8(%rax)
 1033e05:	cmp    %rcx,%rsi
 1033e08:	jae    1034dea <my.app::main+0x13fa>
 1033e0e:	mov    %rsi,%rdx
 1033e11:	shl    $0x4,%rdx
 1033e15:	movq   $0x2,0x20(%rax,%rdx,1)
 1033e1e:	movq   $0xf4243,0x28(%rax,%rdx,1)
 1033e27:	inc    %rsi
 1033e2a:	mov    %rsi,0x8(%rax)
 1033e2e:	cmp    %rcx,%rsi
 1033e31:	jae    1034e07 <my.app::main+0x1417>
 1033e37:	mov    %rsi,%rdx
 1033e3a:	shl    $0x4,%rdx
 1033e3e:	movq   $0x7,0x20(%rax,%rdx,1)
 1033e47:	movq   $0x0,0x28(%rax,%rdx,1)
 1033e50:	inc    %rsi
 1033e53:	mov    %rsi,0x8(%rax)
 1033e57:	cmp    %rcx,%rsi
 1033e5a:	jae    1034e24 <my.app::main+0x1434>
 1033e60:	mov    %rsi,%rdx
 1033e63:	shl    $0x4,%rdx
 1033e67:	movq   $0x4,0x20(%rax,%rdx,1)
 1033e70:	movq   $0x0,0x28(%rax,%rdx,1)
 1033e79:	inc    %rsi
 1033e7c:	mov    %rsi,0x8(%rax)
 1033e80:	cmp    %rcx,%rsi
 1033e83:	jae    1034e41 <my.app::main+0x1451>
 1033e89:	mov    %rsi,%rdx
 1033e8c:	shl    $0x4,%rdx
 1033e90:	movq   $0x3,0x20(%rax,%rdx,1)
 1033e99:	movq   $0x1,0x28(%rax,%rdx,1)
 1033ea2:	inc    %rsi
 1033ea5:	mov    %rsi,0x8(%rax)
 1033ea9:	cmp    %rcx,%rsi
 1033eac:	jae    1034e5e <my.app::main+0x146e>
 1033eb2:	mov    %rsi,%rdx
 1033eb5:	shl    $0x4,%rdx
 1033eb9:	movq   $0x2,0x20(%rax,%rdx,1)
 1033ec2:	movq   $0x1,0x28(%rax,%rdx,1)
 1033ecb:	inc    %rsi
 1033ece:	mov    %rsi,0x8(%rax)
 1033ed2:	cmp    %rcx,%rsi
 1033ed5:	jae    1034e7b <my.app::main+0x148b>
 1033edb:	mov    %rsi,%rdx
 1033ede:	shl    $0x4,%rdx
 1033ee2:	movq   $0x5,0x20(%rax,%rdx,1)
 1033eeb:	movq   $0x0,0x28(%rax,%rdx,1)
 1033ef4:	inc    %rsi
 1033ef7:	mov    %rsi,0x8(%rax)
 1033efb:	cmp    %rcx,%rsi
 1033efe:	jae    1034e98 <my.app::main+0x14a8>
 1033f04:	mov    %rsi,%rdx
 1033f07:	shl    $0x4,%rdx
 1033f0b:	movq   $0x4,0x20(%rax,%rdx,1)
 1033f14:	movq   $0x1,0x28(%rax,%rdx,1)
 1033f1d:	inc    %rsi
 1033f20:	mov    %rsi,0x8(%rax)
 1033f24:	cmp    %rcx,%rsi
 1033f27:	jae    1034eb5 <my.app::main+0x14c5>
 1033f2d:	mov    %rsi,%rdx
 1033f30:	shl    $0x4,%rdx
 1033f34:	movq   $0xb,0x20(%rax,%rdx,1)
 1033f3d:	movq   $0x4,0x28(%rax,%rdx,1)
 1033f46:	inc    %rsi
 1033f49:	mov    %rsi,0x8(%rax)
 1033f4d:	cmp    %rcx,%rsi
 1033f50:	jae    1034ed2 <my.app::main+0x14e2>
 1033f56:	mov    %rsi,%rdx
 1033f59:	shl    $0x4,%rdx
 1033f5d:	movq   $0x3,0x20(%rax,%rdx,1)
 1033f66:	movq   $0x0,0x28(%rax,%rdx,1)
 1033f6f:	inc    %rsi
 1033f72:	mov    %rsi,0x8(%rax)
 1033f76:	cmp    %rcx,%rsi
 1033f79:	jae    1034eef <my.app::main+0x14ff>
 1033f7f:	mov    %rsi,%rdx
 1033f82:	shl    $0x4,%rdx
 1033f86:	movq   $0xe,0x20(%rax,%rdx,1)
 1033f8f:	movq   $0x0,0x28(%rax,%rdx,1)
 1033f98:	inc    %rsi
 1033f9b:	mov    %rsi,0x8(%rax)
 1033f9f:	cmp    %rcx,%rsi
 1033fa2:	jae    1034f0c <my.app::main+0x151c>
 1033fa8:	mov    %rsi,%rdx
 1033fab:	shl    $0x4,%rdx
 1033faf:	movq   $0x2,0x20(%rax,%rdx,1)
 1033fb8:	movq   $0x3,0x28(%rax,%rdx,1)
 1033fc1:	inc    %rsi
 1033fc4:	mov    %rsi,0x8(%rax)
 1033fc8:	cmp    %rcx,%rsi
 1033fcb:	jae    1034f29 <my.app::main+0x1539>
 1033fd1:	mov    %rsi,%rdx
 1033fd4:	shl    $0x4,%rdx
 1033fd8:	movq   $0x6,0x20(%rax,%rdx,1)
 1033fe1:	movq   $0x0,0x28(%rax,%rdx,1)
 1033fea:	inc    %rsi
 1033fed:	mov    %rsi,0x8(%rax)
 1033ff1:	cmp    %rcx,%rsi
 1033ff4:	jae    1034f46 <my.app::main+0x1556>
 1033ffa:	mov    %rsi,%rdx
 1033ffd:	shl    $0x4,%rdx
 1034001:	movq   $0x2,0x20(%rax,%rdx,1)
 103400a:	movq   $0x7,0x28(%rax,%rdx,1)
 1034013:	inc    %rsi
 1034016:	mov    %rsi,0x8(%rax)
 103401a:	cmp    %rcx,%rsi
 103401d:	jae    1034f63 <my.app::main+0x1573>
 1034023:	mov    %rsi,%rdx
 1034026:	shl    $0x4,%rdx
 103402a:	movq   $0x5,0x20(%rax,%rdx,1)
 1034033:	movq   $0x0,0x28(%rax,%rdx,1)
 103403c:	inc    %rsi
 103403f:	mov    %rsi,0x8(%rax)
 1034043:	cmp    %rcx,%rsi
 1034046:	jae    1034f80 <my.app::main+0x1590>
 103404c:	mov    %rsi,%rdx
 103404f:	shl    $0x4,%rdx
 1034053:	movq   $0x2,0x20(%rax,%rdx,1)
 103405c:	movq   $0xf4243,0x28(%rax,%rdx,1)
 1034065:	inc    %rsi
 1034068:	mov    %rsi,0x8(%rax)
 103406c:	cmp    %rcx,%rsi
 103406f:	jae    1034f9d <my.app::main+0x15ad>
 1034075:	mov    %rsi,%rdx
 1034078:	shl    $0x4,%rdx
 103407c:	movq   $0x7,0x20(%rax,%rdx,1)
 1034085:	movq   $0x0,0x28(%rax,%rdx,1)
 103408e:	inc    %rsi
 1034091:	mov    %rsi,0x8(%rax)
 1034095:	cmp    %rcx,%rsi
 1034098:	mov    %r15,0x20(%rsp)
 103409d:	jae    1034fba <my.app::main+0x15ca>
 10340a3:	mov    %rax,0x10(%rsp)
 10340a8:	lea    0x20(%rax),%r12
 10340ac:	mov    %rsi,%rcx
 10340af:	shl    $0x4,%rcx
 10340b3:	movq   $0xd,0x20(%rax,%rcx,1)
 10340bc:	movq   $0x0,0x28(%rax,%rcx,1)
 10340c5:	inc    %rsi
 10340c8:	mov    %rsi,0x8(%rax)
 10340cc:	lea    0x284d(%rip),%rdi        # 1036920 <core_io_file_error.verbs+0x350>
 10340d3:	vzeroupper
 10340d6:	call   100a4c0 <myl_core_io_at>
 10340db:	mov    0x20(%rsp),%rdi
 10340e0:	call   1022430 <myl_core_host_check>
 10340e5:	call   10350d0 <runtime_bench_now>
 10340ea:	xor    %r11d,%r11d
 10340ed:	mov    0x10(%rsp),%r10
 10340f2:	mov    %rax,0x30(%rsp)
 10340f7:	lea    -0x2f80e(%rip),%rbp        # 10048f0 <core_number_pairs+0x3c0>
 10340fe:	movabs $0x100000000000001,%r13
 1034108:	vxorps %xmm1,%xmm1,%xmm1
 103410c:	xor    %eax,%eax
 103410e:	xor    %edx,%edx
 1034110:	lea    0x26ae9(%rip),%r9        # 105ac00 <myl_core_free_lists>
 1034117:	mov    0x8(%rsp),%r8
 103411c:	nopl   0x0(%rax)
 1034120:	mov    0x28(%rsp),%rcx
 1034125:	add    %rdx,%rcx
 1034128:	mov    %rcx,0x50(%rsp)
 103412d:	jo     1035057 <my.app::main+0x1667>
 1034133:	mov    %rax,0x48(%rsp)
 1034138:	mov    %rdx,0x40(%rsp)
 103413d:	mov    0x8(%r9),%r15
 1034141:	test   %r15,%r15
 1034144:	je     103489b <my.app::main+0xeab>
 103414a:	mov    (%r15),%rax
 103414d:	mov    %rax,0x8(%r9)
 1034151:	mov    %r13,(%r15)
 1034154:	vmovups %xmm1,0x8(%r15)
 103415a:	movq   $0x0,0x18(%r15)
 1034162:	mov    0x8(%r9),%rax
 1034166:	test   %rax,%rax
 1034169:	je     10348ca <my.app::main+0xeda>
 103416f:	mov    (%rax),%rcx
 1034172:	mov    %rcx,0x8(%r9)
 1034176:	mov    %r13,(%rax)
 1034179:	vmovups %xmm1,0x8(%rax)
 103417e:	movq   $0x0,0x18(%rax)
 1034186:	mov    %rax,0x18(%rsp)
 103418b:	mov    0x10(%r9),%rdi
 103418f:	test   %rdi,%rdi
 1034192:	je     10348f6 <my.app::main+0xf06>
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
 10341c5:	jae    103494e <my.app::main+0xf5e>
 10341cb:	movq   $0x0,0x20(%rdi,%rdx,8)
 10341d4:	inc    %rdx
 10341d7:	mov    %rdx,0x8(%rdi)
 10341db:	mov    0x8(%r10),%rdx
 10341df:	xor    %esi,%esi
 10341e1:	test   %rdx,%rdx
 10341e4:	je     1034a30 <my.app::main+0x1040>
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
 1034232:	jae    1034a30 <my.app::main+0x1040>
 1034238:	inc    %r13
 103423b:	jo     1034afe <my.app::main+0x110e>
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
 103426a:	jae    10345be <my.app::main+0xbce>
 1034270:	mov    %rax,%rcx
 1034273:	shl    $0x4,%rcx
 1034277:	movq   $0x0,0x20(%r15,%rcx,1)
 1034280:	mov    0x50(%rsp),%rdx
 1034285:	mov    %rdx,0x28(%r15,%rcx,1)
 103428a:	jmp    1034214 <my.app::main+0x824>
 103428c:	mov    0x8(%r15),%rdx
 1034290:	test   %rdx,%rdx
 1034293:	je     1034b24 <my.app::main+0x1134>
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
 10342c6:	jae    1034b15 <my.app::main+0x1125>
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
 10342f1:	jae    1034b37 <my.app::main+0x1147>
 10342f7:	mov    0x20(%rdi,%rsi,8),%rbx
 10342fc:	mov    0x8(%r15),%rax
 1034300:	cmp    0x10(%r15),%rax
 1034304:	jae    1034632 <my.app::main+0xc42>
 103430a:	mov    %rax,%rcx
 103430d:	shl    $0x4,%rcx
 1034311:	movq   $0x0,0x20(%r15,%rcx,1)
 103431a:	mov    %rbx,0x28(%r15,%rcx,1)
 103431f:	jmp    1034214 <my.app::main+0x824>
 1034324:	mov    0x8(%r15),%rax
 1034328:	cmp    0x10(%r15),%rax
 103432c:	jae    10345f8 <my.app::main+0xc08>
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
 103435d:	je     1034b59 <my.app::main+0x1169>
 1034363:	lea    -0x1(%rcx),%rdx
 1034367:	mov    %rdx,%rsi
 103436a:	shl    $0x4,%rsi
 103436e:	cmpb   $0x0,0x20(%r15,%rsi,1)
 1034374:	jne    10343d4 <my.app::main+0x9e4>
 1034376:	mov    0x28(%r15,%rsi,1),%rbp
 103437b:	jmp    10343d6 <my.app::main+0x9e6>
 103437d:	add    $0xfffffffffffffff6,%rcx
 1034381:	cmp    $0x3,%rcx
 1034385:	ja     10347a0 <my.app::main+0xdb0>
 103438b:	lea    -0x2fa8e(%rip),%rdx        # 1004904 <core_number_pairs+0x3d4>
 1034392:	movslq (%rdx,%rcx,4),%rax
 1034396:	add    %rdx,%rax
 1034399:	jmp    *%rax
 103439b:	mov    0x8(%r15),%rax
 103439f:	test   %rax,%rax
 10343a2:	je     1034fd3 <my.app::main+0x15e3>
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
 10343dd:	je     1034b46 <my.app::main+0x1156>
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
 1034428:	jmp    1035022 <my.app::main+0x1632>
 103442d:	mov    0x18(%rsp),%rax
 1034432:	mov    0x8(%rax),%rcx
 1034436:	cmp    0x10(%rax),%rcx
 103443a:	jae    10346a6 <my.app::main+0xcb6>
 1034440:	mov    %r13,0x20(%rax,%rcx,8)
 1034445:	inc    %rcx
 1034448:	mov    %rax,0x18(%rsp)
 103444d:	mov    %rcx,0x8(%rax)
 1034451:	mov    %r14,%r13
 1034454:	jmp    103421b <my.app::main+0x82b>
 1034459:	mov    0x18(%rsp),%rcx
 103445e:	mov    0x8(%rcx),%rax
 1034462:	test   %rax,%rax
 1034465:	je     1034fe6 <my.app::main+0x15f6>
 103446b:	mov    0x18(%rcx,%rax,8),%r13
 1034470:	dec    %rax
 1034473:	mov    %rax,0x8(%rcx)
 1034477:	jmp    103421b <my.app::main+0x82b>
 103447c:	mov    %r14,%r13
 103447f:	jmp    103421b <my.app::main+0x82b>
 1034484:	test   %rbp,%rbp
 1034487:	je     103500e <my.app::main+0x161e>
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
 10344be:	jae    10346dd <my.app::main+0xced>
 10344c4:	mov    %rcx,%rax
 10344c7:	shl    $0x4,%rax
 10344cb:	cmp    %rbp,%rbx
 10344ce:	movq   $0x1,0x20(%r15,%rax,1)
 10344d7:	setl   0x28(%r15,%rax,1)
 10344dd:	jmp    1034522 <my.app::main+0xb32>
 10344df:	mov    %rbx,%r14
 10344e2:	imul   %rbp,%r14
 10344e6:	jo     1034ff9 <my.app::main+0x1609>
 10344ec:	cmp    0x10(%r15),%rcx
 10344f0:	jae    103466c <my.app::main+0xc7c>
 10344f6:	lea    -0x2fc0d(%rip),%rbp        # 10048f0 <core_number_pairs+0x3c0>
 10344fd:	jmp    1034563 <my.app::main+0xb73>
 10344ff:	cmp    0x10(%r15),%rcx
 1034503:	jae    1034717 <my.app::main+0xd27>
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
 1034553:	jae    1034751 <my.app::main+0xd61>
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
 103459e:	mov    0x10(%rsp),%r10
 10345a3:	mov    0x8(%rsp),%r8
 10345a8:	lea    0x26651(%rip),%r9        # 105ac00 <myl_core_free_lists>
 10345af:	mov    %rbx,%rdi
 10345b2:	mov    %rax,%r15
 10345b5:	mov    0x8(%rax),%rax
 10345b9:	jmp    10341ff <my.app::main+0x80f>
 10345be:	mov    $0x10,%esi
 10345c3:	mov    %rdi,%rbx
 10345c6:	mov    %r15,%rdi
 10345c9:	vzeroupper
 10345cc:	call   10094f0 <myl_core_list_grow>
 10345d1:	vxorps %xmm1,%xmm1,%xmm1
 10345d5:	xor    %r11d,%r11d
 10345d8:	mov    0x10(%rsp),%r10
 10345dd:	mov    0x8(%rsp),%r8
 10345e2:	lea    0x26617(%rip),%r9        # 105ac00 <myl_core_free_lists>
 10345e9:	mov    %rbx,%rdi
 10345ec:	mov    %rax,%r15
 10345ef:	mov    0x8(%rax),%rax
 10345f3:	jmp    1034270 <my.app::main+0x880>
 10345f8:	mov    $0x10,%esi
 10345fd:	mov    %rdi,%rbx
 1034600:	mov    %r15,%rdi
 1034603:	vzeroupper
 1034606:	call   10094f0 <myl_core_list_grow>
 103460b:	vxorps %xmm1,%xmm1,%xmm1
 103460f:	xor    %r11d,%r11d
 1034612:	mov    0x10(%rsp),%r10
 1034617:	mov    0x8(%rsp),%r8
 103461c:	lea    0x265dd(%rip),%r9        # 105ac00 <myl_core_free_lists>
 1034623:	mov    %rbx,%rdi
 1034626:	mov    %rax,%r15
 1034629:	mov    0x8(%rax),%rax
 103462d:	jmp    1034332 <my.app::main+0x942>
 1034632:	mov    $0x10,%esi
 1034637:	mov    %rdi,%r14
 103463a:	mov    %r15,%rdi
 103463d:	vzeroupper
 1034640:	call   10094f0 <myl_core_list_grow>
 1034645:	vxorps %xmm1,%xmm1,%xmm1
 1034649:	xor    %r11d,%r11d
 103464c:	mov    0x10(%rsp),%r10
 1034651:	mov    0x8(%rsp),%r8
 1034656:	lea    0x265a3(%rip),%r9        # 105ac00 <myl_core_free_lists>
 103465d:	mov    %r14,%rdi
 1034660:	mov    %rax,%r15
 1034663:	mov    0x8(%rax),%rax
 1034667:	jmp    103430a <my.app::main+0x91a>
 103466c:	mov    $0x10,%esi
 1034671:	mov    %rdi,%rbx
 1034674:	mov    %r15,%rdi
 1034677:	vzeroupper
 103467a:	call   10094f0 <myl_core_list_grow>
 103467f:	vxorps %xmm1,%xmm1,%xmm1
 1034683:	xor    %r11d,%r11d
 1034686:	mov    0x10(%rsp),%r10
 103468b:	mov    0x8(%rsp),%r8
 1034690:	lea    0x26569(%rip),%r9        # 105ac00 <myl_core_free_lists>
 1034697:	mov    %rbx,%rdi
 103469a:	mov    %rax,%r15
 103469d:	mov    0x8(%rax),%rcx
 10346a1:	jmp    10344f6 <my.app::main+0xb06>
 10346a6:	mov    $0x8,%esi
 10346ab:	mov    %rdi,%rbx
 10346ae:	mov    %rax,%rdi
 10346b1:	vzeroupper
 10346b4:	call   10094f0 <myl_core_list_grow>
 10346b9:	vxorps %xmm1,%xmm1,%xmm1
 10346bd:	xor    %r11d,%r11d
 10346c0:	mov    0x10(%rsp),%r10
 10346c5:	mov    0x8(%rsp),%r8
 10346ca:	lea    0x2652f(%rip),%r9        # 105ac00 <myl_core_free_lists>
 10346d1:	mov    %rbx,%rdi
 10346d4:	mov    0x8(%rax),%rcx
 10346d8:	jmp    1034440 <my.app::main+0xa50>
 10346dd:	mov    $0x10,%esi
 10346e2:	mov    %rdi,%r14
 10346e5:	mov    %r15,%rdi
 10346e8:	vzeroupper
 10346eb:	call   10094f0 <myl_core_list_grow>
 10346f0:	vxorps %xmm1,%xmm1,%xmm1
 10346f4:	xor    %r11d,%r11d
 10346f7:	mov    0x10(%rsp),%r10
 10346fc:	mov    0x8(%rsp),%r8
 1034701:	lea    0x264f8(%rip),%r9        # 105ac00 <myl_core_free_lists>
 1034708:	mov    %r14,%rdi
 103470b:	mov    %rax,%r15
 103470e:	mov    0x8(%rax),%rcx
 1034712:	jmp    10344c4 <my.app::main+0xad4>
 1034717:	mov    $0x10,%esi
 103471c:	mov    %rdi,%r14
 103471f:	mov    %r15,%rdi
 1034722:	vzeroupper
 1034725:	call   10094f0 <myl_core_list_grow>
 103472a:	vxorps %xmm1,%xmm1,%xmm1
 103472e:	xor    %r11d,%r11d
 1034731:	mov    0x10(%rsp),%r10
 1034736:	mov    0x8(%rsp),%r8
 103473b:	lea    0x264be(%rip),%r9        # 105ac00 <myl_core_free_lists>
 1034742:	mov    %r14,%rdi
 1034745:	mov    %rax,%r15
 1034748:	mov    0x8(%rax),%rcx
 103474c:	jmp    1034509 <my.app::main+0xb19>
 1034751:	mov    $0x10,%esi
 1034756:	mov    %rdi,%rbp
 1034759:	mov    %r15,%rdi
 103475c:	mov    %rdx,%rbx
 103475f:	vzeroupper
 1034762:	call   10094f0 <myl_core_list_grow>
 1034767:	vxorps %xmm1,%xmm1,%xmm1
 103476b:	xor    %r11d,%r11d
 103476e:	mov    0x10(%rsp),%r10
 1034773:	mov    0x8(%rsp),%r8
 1034778:	lea    0x26481(%rip),%r9        # 105ac00 <myl_core_free_lists>
 103477f:	mov    %rbp,%rdi
 1034782:	mov    %rbx,%rdx
 1034785:	mov    %rax,%r15
 1034788:	mov    0x8(%rax),%rcx
 103478c:	jmp    1034559 <my.app::main+0xb69>
 1034791:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10347a0:	movzbl 0x7(%rdi),%eax
 10347a4:	test   %rax,%rax
 10347a7:	je     103497f <my.app::main+0xf8f>
 10347ad:	cmpq   $0x0,0x18(%rdi)
 10347b2:	jne    103497f <my.app::main+0xf8f>
 10347b8:	mov    (%r9,%rax,8),%rcx
 10347bc:	mov    %rcx,(%rdi)
 10347bf:	mov    %rdi,(%r9,%rax,8)
 10347c3:	movabs $0x100000000000001,%r13
 10347cd:	mov    0x18(%rsp),%rdi
 10347d2:	movzbl 0x7(%rdi),%eax
 10347d6:	test   %rax,%rax
 10347d9:	je     10349a4 <my.app::main+0xfb4>
 10347df:	cmpq   $0x0,0x18(%rdi)
 10347e4:	jne    10349a4 <my.app::main+0xfb4>
 10347ea:	mov    (%r9,%rax,8),%rcx
 10347ee:	mov    %rcx,(%rdi)
 10347f1:	mov    %rdi,(%r9,%rax,8)
 10347f5:	mov    0x8(%r15),%rax
 10347f9:	test   %rax,%rax
 10347fc:	je     103506b <my.app::main+0x167b>
 1034802:	dec    %rax
 1034805:	mov    %rax,%rcx
 1034808:	shl    $0x4,%rcx
 103480c:	movzbl 0x20(%r15,%rcx,1),%ebx
 1034812:	mov    0x28(%r15,%rcx,1),%r14
 1034817:	mov    %rax,0x8(%r15)
 103481b:	movzbl 0x7(%r15),%eax
 1034820:	test   %rax,%rax
 1034823:	je     10349c9 <my.app::main+0xfd9>
 1034829:	cmpq   $0x0,0x18(%r15)
 103482e:	jne    10349c9 <my.app::main+0xfd9>
 1034834:	mov    (%r9,%rax,8),%rcx
 1034838:	mov    %rcx,(%r15)
 103483b:	mov    %r15,(%r9,%rax,8)
 103483f:	test   %rbx,%rbx
 1034842:	cmovne %r11,%r14
 1034846:	test   %r14,%r14
 1034849:	mov    0x48(%rsp),%rsi
 103484e:	js     10349fd <my.app::main+0x100d>
 1034854:	mov    %rsi,%rbx
 1034857:	add    %r14,%rbx
 103485a:	jo     103507e <my.app::main+0x168e>
 1034860:	mov    %rbx,%rdx
 1034863:	movabs $0x89705f3112a28fe5,%rax
 103486d:	mulx   %rax,%rax,%rax
 1034872:	shr    $0x1d,%rax
 1034876:	imul   $0x3b9aca07,%rax,%rax
 103487d:	sub    %rax,%rbx
 1034880:	mov    0x40(%rsp),%rdx
 1034885:	inc    %rdx
 1034888:	mov    %rbx,%rax
 103488b:	cmp    0x38(%rsp),%rdx
 1034890:	jne    1034120 <my.app::main+0x730>
 1034896:	jmp    1034a1a <my.app::main+0x102a>
 103489b:	mov    $0x10,%esi
 10348a0:	xor    %edi,%edi
 10348a2:	vzeroupper
 10348a5:	call   1009480 <myl_core_list_new_slow>
 10348aa:	vxorps %xmm1,%xmm1,%xmm1
 10348ae:	xor    %r11d,%r11d
 10348b1:	mov    0x10(%rsp),%r10
 10348b6:	mov    0x8(%rsp),%r8
 10348bb:	lea    0x2633e(%rip),%r9        # 105ac00 <myl_core_free_lists>
 10348c2:	mov    %rax,%r15
 10348c5:	jmp    1034162 <my.app::main+0x772>
 10348ca:	mov    $0x8,%esi
 10348cf:	xor    %edi,%edi
 10348d1:	vzeroupper
 10348d4:	call   1009480 <myl_core_list_new_slow>
 10348d9:	vxorps %xmm1,%xmm1,%xmm1
 10348dd:	xor    %r11d,%r11d
 10348e0:	mov    0x10(%rsp),%r10
 10348e5:	mov    0x8(%rsp),%r8
 10348ea:	lea    0x2630f(%rip),%r9        # 105ac00 <myl_core_free_lists>
 10348f1:	jmp    1034186 <my.app::main+0x796>
 10348f6:	mov    $0x2,%edi
 10348fb:	mov    $0x8,%esi
 1034900:	vzeroupper
 1034903:	call   1009480 <myl_core_list_new_slow>
 1034908:	mov    %rax,%rdi
 103490b:	mov    0x8(%rax),%rdx
 103490f:	mov    0x10(%rax),%rcx
 1034913:	cmp    %rcx,%rdx
 1034916:	jb     10349f1 <my.app::main+0x1001>
 103491c:	mov    $0x8,%esi
 1034921:	call   10094f0 <myl_core_list_grow>
 1034926:	mov    0x8(%rax),%rdx
 103492a:	mov    0x10(%rax),%rcx
 103492e:	lea    0x262cb(%rip),%r9        # 105ac00 <myl_core_free_lists>
 1034935:	mov    %rax,%rdi
 1034938:	mov    0x8(%rsp),%r8
 103493d:	mov    0x10(%rsp),%r10
 1034942:	xor    %r11d,%r11d
 1034945:	vxorps %xmm1,%xmm1,%xmm1
 1034949:	jmp    10341b2 <my.app::main+0x7c2>
 103494e:	mov    $0x8,%esi
 1034953:	vzeroupper
 1034956:	call   10094f0 <myl_core_list_grow>
 103495b:	vxorps %xmm1,%xmm1,%xmm1
 103495f:	xor    %r11d,%r11d
 1034962:	mov    0x10(%rsp),%r10
 1034967:	mov    0x8(%rsp),%r8
 103496c:	lea    0x2628d(%rip),%r9        # 105ac00 <myl_core_free_lists>
 1034973:	mov    %rax,%rdi
 1034976:	mov    0x8(%rax),%rdx
 103497a:	jmp    10341cb <my.app::main+0x7db>
 103497f:	vzeroupper
 1034982:	call   1032790 <myl_core_free_block>
 1034987:	vxorps %xmm1,%xmm1,%xmm1
 103498b:	xor    %r11d,%r11d
 103498e:	mov    0x10(%rsp),%r10
 1034993:	mov    0x8(%rsp),%r8
 1034998:	lea    0x26261(%rip),%r9        # 105ac00 <myl_core_free_lists>
 103499f:	jmp    10347c3 <my.app::main+0xdd3>
 10349a4:	vzeroupper
 10349a7:	call   1032790 <myl_core_free_block>
 10349ac:	vxorps %xmm1,%xmm1,%xmm1
 10349b0:	xor    %r11d,%r11d
 10349b3:	mov    0x10(%rsp),%r10
 10349b8:	mov    0x8(%rsp),%r8
 10349bd:	lea    0x2623c(%rip),%r9        # 105ac00 <myl_core_free_lists>
 10349c4:	jmp    10347f5 <my.app::main+0xe05>
 10349c9:	mov    %r15,%rdi
 10349cc:	vzeroupper
 10349cf:	call   1032790 <myl_core_free_block>
 10349d4:	vxorps %xmm1,%xmm1,%xmm1
 10349d8:	xor    %r11d,%r11d
 10349db:	mov    0x10(%rsp),%r10
 10349e0:	mov    0x8(%rsp),%r8
 10349e5:	lea    0x26214(%rip),%r9        # 105ac00 <myl_core_free_lists>
 10349ec:	jmp    103483f <my.app::main+0xe4f>
 10349f1:	lea    0x26208(%rip),%r9        # 105ac00 <myl_core_free_lists>
 10349f8:	jmp    1034938 <my.app::main+0xf48>
 10349fd:	mov    (%r10),%eax
 1034a00:	mov    $0x2,%ebx
 1034a05:	cmp    $0xffffffff,%eax
 1034a08:	je     1034ae9 <my.app::main+0x10f9>
 1034a0e:	dec    %eax
 1034a10:	je     1034a3f <my.app::main+0x104f>
 1034a12:	mov    %eax,(%r10)
 1034a15:	jmp    1034ae9 <my.app::main+0x10f9>
 1034a1a:	mov    (%r10),%eax
 1034a1d:	cmp    $0xffffffff,%eax
 1034a20:	mov    0x20(%rsp),%r14
 1034a25:	je     1034a8c <my.app::main+0x109c>
 1034a27:	dec    %eax
 1034a29:	je     1034a68 <my.app::main+0x1078>
 1034a2b:	mov    %eax,(%r10)
 1034a2e:	jmp    1034a8c <my.app::main+0x109c>
 1034a30:	lea    0x1fd9(%rip),%rdi        # 1036a10 <core_io_file_error.verbs+0x440>
 1034a37:	vzeroupper
 1034a3a:	call   1009b80 <myl_core_trap>
 1034a3f:	movzbl 0x7(%r10),%eax
 1034a44:	test   %rax,%rax
 1034a47:	je     1035037 <my.app::main+0x1647>
 1034a4d:	cmpq   $0x0,0x18(%r10)
 1034a52:	jne    1035037 <my.app::main+0x1647>
 1034a58:	mov    (%r9,%rax,8),%rcx
 1034a5c:	mov    %rcx,(%r10)
 1034a5f:	mov    %r10,(%r9,%rax,8)
 1034a63:	jmp    1034ae9 <my.app::main+0x10f9>
 1034a68:	movzbl 0x7(%r10),%eax
 1034a6d:	test   %rax,%rax
 1034a70:	je     1035047 <my.app::main+0x1657>
 1034a76:	cmpq   $0x0,0x18(%r10)
 1034a7b:	jne    1035047 <my.app::main+0x1657>
 1034a81:	mov    (%r9,%rax,8),%rcx
 1034a85:	mov    %rcx,(%r10)
 1034a88:	mov    %r10,(%r9,%rax,8)
 1034a8c:	lea    0x1ebd(%rip),%rdi        # 1036950 <core_io_file_error.verbs+0x380>
 1034a93:	vzeroupper
 1034a96:	call   100a4c0 <myl_core_io_at>
 1034a9b:	mov    %r14,%rdi
 1034a9e:	call   1022430 <myl_core_host_check>
 1034aa3:	call   10350d0 <runtime_bench_now>
 1034aa8:	mov    %rax,%r14
 1034aab:	mov    0x30(%rsp),%rdx
 1034ab0:	sub    %rdx,%r14
 1034ab3:	jo     10350b2 <my.app::main+0x16c2>
 1034ab9:	mov    $0x1,%edi
 1034abe:	mov    %rbx,%rsi
 1034ac1:	call   100abc0 <myl_core_print_i64>
 1034ac6:	mov    $0x1,%edi
 1034acb:	call   1009200 <myl_core_print_sep>
 1034ad0:	mov    $0x1,%edi
 1034ad5:	mov    %r14,%rsi
 1034ad8:	call   100abc0 <myl_core_print_i64>
 1034add:	mov    $0x1,%edi
 1034ae2:	call   10092c0 <myl_core_print_end>
 1034ae7:	xor    %ebx,%ebx
 1034ae9:	mov    %rbx,%rax
 1034aec:	add    $0x58,%rsp
 1034af0:	pop    %rbx
 1034af1:	pop    %r12
 1034af3:	pop    %r13
 1034af5:	pop    %r14
 1034af7:	pop    %r15
 1034af9:	pop    %rbp
 1034afa:	vzeroupper
 1034afd:	ret
 1034afe:	lea    0x1f3b(%rip),%rdi        # 1036a40 <core_io_file_error.verbs+0x470>
 1034b05:	mov    $0x1,%edx
 1034b0a:	mov    %rax,%rsi
 1034b0d:	vzeroupper
 1034b10:	call   1009b80 <myl_core_trap>
 1034b15:	lea    0x1fb4(%rip),%rdi        # 1036ad0 <core_io_file_error.verbs+0x500>
 1034b1c:	vzeroupper
 1034b1f:	call   1009b80 <myl_core_trap>
 1034b24:	lea    0x1f75(%rip),%rdi        # 1036aa0 <core_io_file_error.verbs+0x4d0>
 1034b2b:	xor    %esi,%esi
 1034b2d:	xor    %edx,%edx
 1034b2f:	vzeroupper
 1034b32:	call   1009b80 <myl_core_trap>
 1034b37:	lea    0x1f32(%rip),%rdi        # 1036a70 <core_io_file_error.verbs+0x4a0>
 1034b3e:	vzeroupper
 1034b41:	call   1009b80 <myl_core_trap>
 1034b46:	lea    0x1fe3(%rip),%rdi        # 1036b30 <core_io_file_error.verbs+0x560>
 1034b4d:	xor    %esi,%esi
 1034b4f:	xor    %edx,%edx
 1034b51:	vzeroupper
 1034b54:	call   1009b80 <myl_core_trap>
 1034b59:	lea    0x1fa0(%rip),%rdi        # 1036b00 <core_io_file_error.verbs+0x530>
 1034b60:	xor    %esi,%esi
 1034b62:	xor    %edx,%edx
 1034b64:	vzeroupper
 1034b67:	call   1009b80 <myl_core_trap>
 1034b6c:	mov    $0x26,%edi
 1034b71:	mov    $0x10,%esi
 1034b76:	call   1009480 <myl_core_list_new_slow>
 1034b7b:	mov    0x8(%rax),%rsi
 1034b7f:	mov    0x10(%rax),%rcx
 1034b83:	cmp    %rcx,%rsi
 1034b86:	jb     1033ab9 <my.app::main+0xc9>
 1034b8c:	mov    $0x10,%esi
 1034b91:	mov    %rax,%rdi
 1034b94:	call   10094f0 <myl_core_list_grow>
 1034b99:	mov    0x8(%rax),%rsi
 1034b9d:	mov    0x10(%rax),%rcx
 1034ba1:	jmp    1033ab9 <my.app::main+0xc9>
 1034ba6:	mov    $0x10,%esi
 1034bab:	mov    %rax,%rdi
 1034bae:	vzeroupper
 1034bb1:	call   10094f0 <myl_core_list_grow>
 1034bb6:	mov    0x8(%rax),%rsi
 1034bba:	mov    0x10(%rax),%rcx
 1034bbe:	jmp    1033ada <my.app::main+0xea>
 1034bc3:	mov    $0x10,%esi
 1034bc8:	mov    %rax,%rdi
 1034bcb:	vzeroupper
 1034bce:	call   10094f0 <myl_core_list_grow>
 1034bd3:	mov    0x8(%rax),%rsi
 1034bd7:	mov    0x10(%rax),%rcx
 1034bdb:	jmp    1033b03 <my.app::main+0x113>
 1034be0:	mov    $0x10,%esi
 1034be5:	mov    %rax,%rdi
 1034be8:	vzeroupper
 1034beb:	call   10094f0 <myl_core_list_grow>
 1034bf0:	mov    0x8(%rax),%rsi
 1034bf4:	mov    0x10(%rax),%rcx
 1034bf8:	jmp    1033b2c <my.app::main+0x13c>
 1034bfd:	mov    $0x10,%esi
 1034c02:	mov    %rax,%rdi
 1034c05:	vzeroupper
 1034c08:	call   10094f0 <myl_core_list_grow>
 1034c0d:	mov    0x8(%rax),%rsi
 1034c11:	mov    0x10(%rax),%rcx
 1034c15:	jmp    1033b55 <my.app::main+0x165>
 1034c1a:	mov    $0x10,%esi
 1034c1f:	mov    %rax,%rdi
 1034c22:	vzeroupper
 1034c25:	call   10094f0 <myl_core_list_grow>
 1034c2a:	mov    0x8(%rax),%rsi
 1034c2e:	mov    0x10(%rax),%rcx
 1034c32:	jmp    1033b7e <my.app::main+0x18e>
 1034c37:	mov    $0x10,%esi
 1034c3c:	mov    %rax,%rdi
 1034c3f:	vzeroupper
 1034c42:	call   10094f0 <myl_core_list_grow>
 1034c47:	mov    0x8(%rax),%rsi
 1034c4b:	mov    0x10(%rax),%rcx
 1034c4f:	jmp    1033ba7 <my.app::main+0x1b7>
 1034c54:	mov    $0x10,%esi
 1034c59:	mov    %rax,%rdi
 1034c5c:	vzeroupper
 1034c5f:	call   10094f0 <myl_core_list_grow>
 1034c64:	mov    0x8(%rax),%rsi
 1034c68:	mov    0x10(%rax),%rcx
 1034c6c:	jmp    1033bd0 <my.app::main+0x1e0>
 1034c71:	mov    $0x10,%esi
 1034c76:	mov    %rax,%rdi
 1034c79:	vzeroupper
 1034c7c:	call   10094f0 <myl_core_list_grow>
 1034c81:	mov    0x8(%rax),%rsi
 1034c85:	mov    0x10(%rax),%rcx
 1034c89:	jmp    1033bf9 <my.app::main+0x209>
 1034c8e:	mov    $0x10,%esi
 1034c93:	mov    %rax,%rdi
 1034c96:	vzeroupper
 1034c99:	call   10094f0 <myl_core_list_grow>
 1034c9e:	mov    0x8(%rax),%rsi
 1034ca2:	mov    0x10(%rax),%rcx
 1034ca6:	jmp    1033c22 <my.app::main+0x232>
 1034cab:	mov    $0x10,%esi
 1034cb0:	mov    %rax,%rdi
 1034cb3:	vzeroupper
 1034cb6:	call   10094f0 <myl_core_list_grow>
 1034cbb:	mov    0x8(%rax),%rsi
 1034cbf:	mov    0x10(%rax),%rcx
 1034cc3:	jmp    1033c4b <my.app::main+0x25b>
 1034cc8:	mov    $0x10,%esi
 1034ccd:	mov    %rax,%rdi
 1034cd0:	vzeroupper
 1034cd3:	call   10094f0 <myl_core_list_grow>
 1034cd8:	mov    0x8(%rax),%rsi
 1034cdc:	mov    0x10(%rax),%rcx
 1034ce0:	jmp    1033c74 <my.app::main+0x284>
 1034ce5:	mov    $0x10,%esi
 1034cea:	mov    %rax,%rdi
 1034ced:	vzeroupper
 1034cf0:	call   10094f0 <myl_core_list_grow>
 1034cf5:	mov    0x8(%rax),%rsi
 1034cf9:	mov    0x10(%rax),%rcx
 1034cfd:	jmp    1033c9d <my.app::main+0x2ad>
 1034d02:	mov    $0x10,%esi
 1034d07:	mov    %rax,%rdi
 1034d0a:	vzeroupper
 1034d0d:	call   10094f0 <myl_core_list_grow>
 1034d12:	mov    0x8(%rax),%rsi
 1034d16:	mov    0x10(%rax),%rcx
 1034d1a:	jmp    1033cc6 <my.app::main+0x2d6>
 1034d1f:	mov    $0x10,%esi
 1034d24:	mov    %rax,%rdi
 1034d27:	vzeroupper
 1034d2a:	call   10094f0 <myl_core_list_grow>
 1034d2f:	mov    0x8(%rax),%rsi
 1034d33:	mov    0x10(%rax),%rcx
 1034d37:	jmp    1033cef <my.app::main+0x2ff>
 1034d3c:	mov    $0x10,%esi
 1034d41:	mov    %rax,%rdi
 1034d44:	vzeroupper
 1034d47:	call   10094f0 <myl_core_list_grow>
 1034d4c:	mov    0x8(%rax),%rsi
 1034d50:	mov    0x10(%rax),%rcx
 1034d54:	jmp    1033d18 <my.app::main+0x328>
 1034d59:	mov    $0x10,%esi
 1034d5e:	mov    %rax,%rdi
 1034d61:	vzeroupper
 1034d64:	call   10094f0 <myl_core_list_grow>
 1034d69:	mov    0x8(%rax),%rsi
 1034d6d:	mov    0x10(%rax),%rcx
 1034d71:	jmp    1033d41 <my.app::main+0x351>
 1034d76:	mov    $0x10,%esi
 1034d7b:	mov    %rax,%rdi
 1034d7e:	vzeroupper
 1034d81:	call   10094f0 <myl_core_list_grow>
 1034d86:	mov    0x8(%rax),%rsi
 1034d8a:	mov    0x10(%rax),%rcx
 1034d8e:	jmp    1033d6a <my.app::main+0x37a>
 1034d93:	mov    $0x10,%esi
 1034d98:	mov    %rax,%rdi
 1034d9b:	vzeroupper
 1034d9e:	call   10094f0 <myl_core_list_grow>
 1034da3:	mov    0x8(%rax),%rsi
 1034da7:	mov    0x10(%rax),%rcx
 1034dab:	jmp    1033d93 <my.app::main+0x3a3>
 1034db0:	mov    $0x10,%esi
 1034db5:	mov    %rax,%rdi
 1034db8:	vzeroupper
 1034dbb:	call   10094f0 <myl_core_list_grow>
 1034dc0:	mov    0x8(%rax),%rsi
 1034dc4:	mov    0x10(%rax),%rcx
 1034dc8:	jmp    1033dbc <my.app::main+0x3cc>
 1034dcd:	mov    $0x10,%esi
 1034dd2:	mov    %rax,%rdi
 1034dd5:	vzeroupper
 1034dd8:	call   10094f0 <myl_core_list_grow>
 1034ddd:	mov    0x8(%rax),%rsi
 1034de1:	mov    0x10(%rax),%rcx
 1034de5:	jmp    1033de5 <my.app::main+0x3f5>
 1034dea:	mov    $0x10,%esi
 1034def:	mov    %rax,%rdi
 1034df2:	vzeroupper
 1034df5:	call   10094f0 <myl_core_list_grow>
 1034dfa:	mov    0x8(%rax),%rsi
 1034dfe:	mov    0x10(%rax),%rcx
 1034e02:	jmp    1033e0e <my.app::main+0x41e>
 1034e07:	mov    $0x10,%esi
 1034e0c:	mov    %rax,%rdi
 1034e0f:	vzeroupper
 1034e12:	call   10094f0 <myl_core_list_grow>
 1034e17:	mov    0x8(%rax),%rsi
 1034e1b:	mov    0x10(%rax),%rcx
 1034e1f:	jmp    1033e37 <my.app::main+0x447>
 1034e24:	mov    $0x10,%esi
 1034e29:	mov    %rax,%rdi
 1034e2c:	vzeroupper
 1034e2f:	call   10094f0 <myl_core_list_grow>
 1034e34:	mov    0x8(%rax),%rsi
 1034e38:	mov    0x10(%rax),%rcx
 1034e3c:	jmp    1033e60 <my.app::main+0x470>
 1034e41:	mov    $0x10,%esi
 1034e46:	mov    %rax,%rdi
 1034e49:	vzeroupper
 1034e4c:	call   10094f0 <myl_core_list_grow>
 1034e51:	mov    0x8(%rax),%rsi
 1034e55:	mov    0x10(%rax),%rcx
 1034e59:	jmp    1033e89 <my.app::main+0x499>
 1034e5e:	mov    $0x10,%esi
 1034e63:	mov    %rax,%rdi
 1034e66:	vzeroupper
 1034e69:	call   10094f0 <myl_core_list_grow>
 1034e6e:	mov    0x8(%rax),%rsi
 1034e72:	mov    0x10(%rax),%rcx
 1034e76:	jmp    1033eb2 <my.app::main+0x4c2>
 1034e7b:	mov    $0x10,%esi
 1034e80:	mov    %rax,%rdi
 1034e83:	vzeroupper
 1034e86:	call   10094f0 <myl_core_list_grow>
 1034e8b:	mov    0x8(%rax),%rsi
 1034e8f:	mov    0x10(%rax),%rcx
 1034e93:	jmp    1033edb <my.app::main+0x4eb>
 1034e98:	mov    $0x10,%esi
 1034e9d:	mov    %rax,%rdi
 1034ea0:	vzeroupper
 1034ea3:	call   10094f0 <myl_core_list_grow>
 1034ea8:	mov    0x8(%rax),%rsi
 1034eac:	mov    0x10(%rax),%rcx
 1034eb0:	jmp    1033f04 <my.app::main+0x514>
 1034eb5:	mov    $0x10,%esi
 1034eba:	mov    %rax,%rdi
 1034ebd:	vzeroupper
 1034ec0:	call   10094f0 <myl_core_list_grow>
 1034ec5:	mov    0x8(%rax),%rsi
 1034ec9:	mov    0x10(%rax),%rcx
 1034ecd:	jmp    1033f2d <my.app::main+0x53d>
 1034ed2:	mov    $0x10,%esi
 1034ed7:	mov    %rax,%rdi
 1034eda:	vzeroupper
 1034edd:	call   10094f0 <myl_core_list_grow>
 1034ee2:	mov    0x8(%rax),%rsi
 1034ee6:	mov    0x10(%rax),%rcx
 1034eea:	jmp    1033f56 <my.app::main+0x566>
 1034eef:	mov    $0x10,%esi
 1034ef4:	mov    %rax,%rdi
 1034ef7:	vzeroupper
 1034efa:	call   10094f0 <myl_core_list_grow>
 1034eff:	mov    0x8(%rax),%rsi
 1034f03:	mov    0x10(%rax),%rcx
 1034f07:	jmp    1033f7f <my.app::main+0x58f>
 1034f0c:	mov    $0x10,%esi
 1034f11:	mov    %rax,%rdi
 1034f14:	vzeroupper
 1034f17:	call   10094f0 <myl_core_list_grow>
 1034f1c:	mov    0x8(%rax),%rsi
 1034f20:	mov    0x10(%rax),%rcx
 1034f24:	jmp    1033fa8 <my.app::main+0x5b8>
 1034f29:	mov    $0x10,%esi
 1034f2e:	mov    %rax,%rdi
 1034f31:	vzeroupper
 1034f34:	call   10094f0 <myl_core_list_grow>
 1034f39:	mov    0x8(%rax),%rsi
 1034f3d:	mov    0x10(%rax),%rcx
 1034f41:	jmp    1033fd1 <my.app::main+0x5e1>
 1034f46:	mov    $0x10,%esi
 1034f4b:	mov    %rax,%rdi
 1034f4e:	vzeroupper
 1034f51:	call   10094f0 <myl_core_list_grow>
 1034f56:	mov    0x8(%rax),%rsi
 1034f5a:	mov    0x10(%rax),%rcx
 1034f5e:	jmp    1033ffa <my.app::main+0x60a>
 1034f63:	mov    $0x10,%esi
 1034f68:	mov    %rax,%rdi
 1034f6b:	vzeroupper
 1034f6e:	call   10094f0 <myl_core_list_grow>
 1034f73:	mov    0x8(%rax),%rsi
 1034f77:	mov    0x10(%rax),%rcx
 1034f7b:	jmp    1034023 <my.app::main+0x633>
 1034f80:	mov    $0x10,%esi
 1034f85:	mov    %rax,%rdi
 1034f88:	vzeroupper
 1034f8b:	call   10094f0 <myl_core_list_grow>
 1034f90:	mov    0x8(%rax),%rsi
 1034f94:	mov    0x10(%rax),%rcx
 1034f98:	jmp    103404c <my.app::main+0x65c>
 1034f9d:	mov    $0x10,%esi
 1034fa2:	mov    %rax,%rdi
 1034fa5:	vzeroupper
 1034fa8:	call   10094f0 <myl_core_list_grow>
 1034fad:	mov    0x8(%rax),%rsi
 1034fb1:	mov    0x10(%rax),%rcx
 1034fb5:	jmp    1034075 <my.app::main+0x685>
 1034fba:	mov    $0x10,%esi
 1034fbf:	mov    %rax,%rdi
 1034fc2:	vzeroupper
 1034fc5:	call   10094f0 <myl_core_list_grow>
 1034fca:	mov    0x8(%rax),%rsi
 1034fce:	jmp    10340a3 <my.app::main+0x6b3>
 1034fd3:	lea    0x1c16(%rip),%rdi        # 1036bf0 <core_io_file_error.verbs+0x620>
 1034fda:	xor    %esi,%esi
 1034fdc:	xor    %edx,%edx
 1034fde:	vzeroupper
 1034fe1:	call   1009b80 <myl_core_trap>
 1034fe6:	lea    0x1c33(%rip),%rdi        # 1036c20 <core_io_file_error.verbs+0x650>
 1034fed:	xor    %esi,%esi
 1034fef:	xor    %edx,%edx
 1034ff1:	vzeroupper
 1034ff4:	call   1009b80 <myl_core_trap>
 1034ff9:	lea    0x1b90(%rip),%rdi        # 1036b90 <core_io_file_error.verbs+0x5c0>
 1035000:	mov    %rbx,%rsi
 1035003:	mov    %rbp,%rdx
 1035006:	vzeroupper
 1035009:	call   1009b80 <myl_core_trap>
 103500e:	lea    0x1bab(%rip),%rdi        # 1036bc0 <core_io_file_error.verbs+0x5f0>
 1035015:	mov    %rbx,%rsi
 1035018:	xor    %edx,%edx
 103501a:	vzeroupper
 103501d:	call   1009b80 <myl_core_trap>
 1035022:	lea    0x1b37(%rip),%rdi        # 1036b60 <core_io_file_error.verbs+0x590>
 1035029:	mov    %rbx,%rsi
 103502c:	mov    %rbp,%rdx
 103502f:	vzeroupper
 1035032:	call   1009b80 <myl_core_trap>
 1035037:	mov    %r10,%rdi
 103503a:	vzeroupper
 103503d:	call   1032790 <myl_core_free_block>
 1035042:	jmp    1034ae9 <my.app::main+0x10f9>
 1035047:	mov    %r10,%rdi
 103504a:	vzeroupper
 103504d:	call   1032790 <myl_core_free_block>
 1035052:	jmp    1034a8c <my.app::main+0x109c>
 1035057:	lea    0x1982(%rip),%rdi        # 10369e0 <core_io_file_error.verbs+0x410>
 103505e:	mov    0x28(%rsp),%rsi
 1035063:	vzeroupper
 1035066:	call   1009b80 <myl_core_trap>
 103506b:	lea    0x1bde(%rip),%rdi        # 1036c50 <core_io_file_error.verbs+0x680>
 1035072:	xor    %esi,%esi
 1035074:	xor    %edx,%edx
 1035076:	vzeroupper
 1035079:	call   1009b80 <myl_core_trap>
 103507e:	lea    0x192b(%rip),%rdi        # 10369b0 <core_io_file_error.verbs+0x3e0>
 1035085:	mov    %r14,%rdx
 1035088:	vzeroupper
 103508b:	call   1009b80 <myl_core_trap>
 1035090:	lea    0x1829(%rip),%rdi        # 10368c0 <core_io_file_error.verbs+0x2f0>
 1035097:	mov    $0x1,%esi
 103509c:	call   1009b80 <myl_core_trap>
 10350a1:	lea    0x1848(%rip),%rdi        # 10368f0 <core_io_file_error.verbs+0x320>
 10350a8:	mov    $0x2,%esi
 10350ad:	call   1009b80 <myl_core_trap>
 10350b2:	lea    0x18c7(%rip),%rdi        # 1036980 <core_io_file_error.verbs+0x3b0>
 10350b9:	mov    %rax,%rsi
 10350bc:	call   1009b80 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
