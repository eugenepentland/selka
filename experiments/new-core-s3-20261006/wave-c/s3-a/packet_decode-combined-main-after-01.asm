
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-applications/.mylang-cache/s3-a/all40-combined-final-01/row_packet_decode_new:     file format elf64-x86-64


Disassembly of section .text:

0000000001032b80 <main>:
 1032b80:	push   %rbp
 1032b81:	push   %r15
 1032b83:	push   %r14
 1032b85:	push   %r13
 1032b87:	push   %r12
 1032b89:	push   %rbx
 1032b8a:	sub    $0x48,%rsp
 1032b8e:	call   1009cb0 <myl_core_args>
 1032b93:	mov    %rax,%r14
 1032b96:	call   10226c0 <myl_core_host_grant>
 1032b9b:	mov    $0x2,%ebx
 1032ba0:	cmpq   $0x3,0x8(%r14)
 1032ba5:	jne    1033ab7 <main+0xf37>
 1032bab:	mov    %rax,%r15
 1032bae:	mov    0x20(%r14),%rdi
 1032bb2:	call   1032980 <my.row_packet_decode::parse_number>
 1032bb7:	mov    0x8(%r14),%rdx
 1032bbb:	cmp    $0x1,%rdx
 1032bbf:	jbe    1033c4a <main+0x10ca>
 1032bc5:	mov    %rax,%rbp
 1032bc8:	mov    0x28(%r14),%rdi
 1032bcc:	call   1032980 <my.row_packet_decode::parse_number>
 1032bd1:	mov    0x8(%r14),%rdx
 1032bd5:	cmp    $0x2,%rdx
 1032bd9:	jbe    1033c59 <main+0x10d9>
 1032bdf:	mov    %rax,%r12
 1032be2:	mov    0x30(%r14),%rdi
 1032be6:	call   1032980 <my.row_packet_decode::parse_number>
 1032beb:	mov    %rax,%r8
 1032bee:	cmp    $0x2,%rbp
 1032bf2:	setl   %al
 1032bf5:	test   %r12,%r12
 1032bf8:	setle  %cl
 1032bfb:	or     %al,%cl
 1032bfd:	lea    -0xf4241(%r8),%rax
 1032c04:	cmp    $0xfffffffffff0bdc0,%rax
 1032c0a:	setb   %al
 1032c0d:	or     %cl,%al
 1032c0f:	jne    1033ab7 <main+0xf37>
 1032c15:	cmp    $0x401,%rbp
 1032c1c:	setae  %al
 1032c1f:	lea    0x3f(,%rbp,8),%rsi
 1032c27:	mov    %rsi,%r9
 1032c2a:	shr    $0x5,%r9
 1032c2e:	cmp    $0x420,%rsi
 1032c35:	setae  %r10b
 1032c39:	or     %al,%r10b
 1032c3c:	mov    %r8,(%rsp)
 1032c40:	mov    %r14,0x30(%rsp)
 1032c45:	mov    %r15,0x38(%rsp)
 1032c4a:	mov    %r12,0x40(%rsp)
 1032c4f:	jne    1033ad5 <main+0xf55>
 1032c55:	lea    0x26d34(%rip),%rax        # 1059990 <myl_core_free_lists>
 1032c5c:	mov    (%rax,%r9,8),%rdi
 1032c60:	test   %rdi,%rdi
 1032c63:	je     1033ad5 <main+0xf55>
 1032c69:	mov    (%rdi),%rcx
 1032c6c:	mov    %rcx,(%rax,%r9,8)
 1032c70:	movl   $0x1,(%rdi)
 1032c76:	mov    %r9d,%eax
 1032c79:	shl    $0x18,%eax
 1032c7c:	mov    %eax,0x4(%rdi)
 1032c7f:	movq   $0x0,0x8(%rdi)
 1032c87:	mov    %esi,%eax
 1032c89:	and    $0x7e0,%eax
 1032c8e:	add    $0xffffffffffffffe0,%rax
 1032c92:	shr    $0x3,%rax
 1032c96:	mov    %rax,0x10(%rdi)
 1032c9a:	movq   $0x0,0x18(%rdi)
 1032ca2:	movabs $0x3759f22983759f3,%rbx
 1032cac:	xor    %r14d,%r14d
 1032caf:	movabs $0x81e722c258cd00c3,%r15
 1032cb9:	xor    %r13d,%r13d
 1032cbc:	mov    %rbp,0x10(%rsp)
 1032cc1:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cd0:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cdf:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cee:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cfd:	nopl   (%rax)
 1032d00:	cmp    %r13,%rbx
 1032d03:	je     1033ba9 <main+0x1029>
 1032d09:	mov    %r8,%rbp
 1032d0c:	add    %r14,%rbp
 1032d0f:	jo     1033bbb <main+0x103b>
 1032d15:	mov    %rbp,%rdx
 1032d18:	mulx   %r15,%r12,%r12
 1032d1d:	mov    0x8(%rdi),%rax
 1032d21:	cmp    0x10(%rdi),%rax
 1032d25:	jae    1032d54 <main+0x1d4>
 1032d27:	shr    $0x9,%r12
 1032d2b:	imul   $0x3f1,%r12,%rcx
 1032d32:	sub    %rcx,%rbp
 1032d35:	mov    %rbp,0x20(%rdi,%rax,8)
 1032d3a:	inc    %rax
 1032d3d:	mov    %rax,0x8(%rdi)
 1032d41:	inc    %r13
 1032d44:	add    $0x25,%r14
 1032d48:	mov    0x10(%rsp),%rbp
 1032d4d:	cmp    %r13,%rbp
 1032d50:	jne    1032d00 <main+0x180>
 1032d52:	jmp    1032d8a <main+0x20a>
 1032d54:	mov    %rsi,0x8(%rsp)
 1032d59:	mov    $0x8,%esi
 1032d5e:	mov    %r9,0x20(%rsp)
 1032d63:	mov    %r10b,0x18(%rsp)
 1032d68:	call   10097b0 <myl_core_list_grow>
 1032d6d:	movzbl 0x18(%rsp),%r10d
 1032d73:	mov    0x20(%rsp),%r9
 1032d78:	mov    0x8(%rsp),%rsi
 1032d7d:	mov    (%rsp),%r8
 1032d81:	mov    %rax,%rdi
 1032d84:	mov    0x8(%rax),%rax
 1032d88:	jmp    1032d27 <main+0x1a7>
 1032d8a:	test   %r10b,%r10b
 1032d8d:	mov    %rdi,0x18(%rsp)
 1032d92:	jne    1033b00 <main+0xf80>
 1032d98:	lea    0x26bf1(%rip),%rax        # 1059990 <myl_core_free_lists>
 1032d9f:	mov    (%rax,%r9,8),%r15
 1032da3:	test   %r15,%r15
 1032da6:	je     1033b00 <main+0xf80>
 1032dac:	mov    (%r15),%rcx
 1032daf:	mov    %rcx,(%rax,%r9,8)
 1032db3:	movl   $0x1,(%r15)
 1032dba:	shl    $0x18,%r9d
 1032dbe:	mov    %r9d,0x4(%r15)
 1032dc2:	movq   $0x0,0x8(%r15)
 1032dca:	and    $0x7e0,%esi
 1032dd0:	add    $0xffffffffffffffe0,%rsi
 1032dd4:	shr    $0x3,%rsi
 1032dd8:	mov    %rsi,0x10(%r15)
 1032ddc:	movq   $0x0,0x18(%r15)
 1032de4:	lea    -0x2dd4b(%rip),%rax        # 10050a0 <myl_core_site_count+0x4>
 1032deb:	mov    %rax,0x18(%r15)
 1032def:	xor    %r13d,%r13d
 1032df2:	lea    0x26b97(%rip),%rsi        # 1059990 <myl_core_free_lists>
 1032df9:	nopl   0x0(%rax)
 1032e00:	mov    %r13,%rdx
 1032e03:	shl    $0x4,%rdx
 1032e07:	add    %r13,%rdx
 1032e0a:	mov    %r8,%rbx
 1032e0d:	add    %rdx,%rbx
 1032e10:	jo     1033bcb <main+0x104b>
 1032e16:	mov    0x18(%rsi),%r14
 1032e1a:	test   %r14,%r14
 1032e1d:	je     103309f <main+0x51f>
 1032e23:	mov    (%r14),%rax
 1032e26:	mov    %rax,0x18(%rsi)
 1032e2a:	vmovdqa -0x2f792(%rip),%ymm0        # 10036a0 <core_io_raw_layout+0x120>
 1032e32:	vmovdqu %ymm0,(%r14)
 1032e37:	mov    $0x8,%ecx
 1032e3c:	xor    %eax,%eax
 1032e3e:	movq   $0xa5,0x20(%r14,%rax,8)
 1032e47:	inc    %rax
 1032e4a:	mov    %rax,0x8(%r14)
 1032e4e:	cmp    %rcx,%rax
 1032e51:	jae    10330df <main+0x55f>
 1032e57:	movq   $0x1,0x20(%r14,%rax,8)
 1032e60:	inc    %rax
 1032e63:	mov    %rax,0x8(%r14)
 1032e67:	cmp    %rcx,%rax
 1032e6a:	jae    1033103 <main+0x583>
 1032e70:	movzbl %bh,%edx
 1032e73:	mov    %rdx,0x20(%r14,%rax,8)
 1032e78:	inc    %rax
 1032e7b:	mov    %rax,0x8(%r14)
 1032e7f:	cmp    %rcx,%rax
 1032e82:	jae    1033127 <main+0x5a7>
 1032e88:	movzbl %bl,%edx
 1032e8b:	mov    %rdx,0x20(%r14,%rax,8)
 1032e90:	inc    %rax
 1032e93:	mov    %rax,0x8(%r14)
 1032e97:	cmp    %rcx,%rax
 1032e9a:	jae    103314b <main+0x5cb>
 1032ea0:	movq   $0x4,0x20(%r14,%rax,8)
 1032ea9:	inc    %rax
 1032eac:	mov    %rax,0x8(%r14)
 1032eb0:	lea    0x0(,%r13,2),%rcx
 1032eb8:	add    %r13,%rcx
 1032ebb:	lea    0x0(,%rcx,4),%rdx
 1032ec3:	add    %r13,%rdx
 1032ec6:	mov    %r8,%rbx
 1032ec9:	add    %rdx,%rbx
 1032ecc:	jo     1033bd8 <main+0x1058>
 1032ed2:	cmp    0x10(%r14),%rax
 1032ed6:	jae    103316b <main+0x5eb>
 1032edc:	mov    %r15,%r12
 1032edf:	movzbl %bl,%ecx
 1032ee2:	mov    %rcx,0x20(%r14,%rax,8)
 1032ee7:	inc    %rax
 1032eea:	mov    %rax,0x8(%r14)
 1032eee:	mov    %rbx,%r15
 1032ef1:	add    $0x7,%r15
 1032ef5:	jo     1033be8 <main+0x1068>
 1032efb:	cmp    0x10(%r14),%rax
 1032eff:	jae    103318a <main+0x60a>
 1032f05:	movzbl %r15b,%ecx
 1032f09:	mov    %rcx,0x20(%r14,%rax,8)
 1032f0e:	inc    %rax
 1032f11:	mov    %rax,0x8(%r14)
 1032f15:	mov    %rbx,%r15
 1032f18:	add    $0xe,%r15
 1032f1c:	jo     1033bef <main+0x106f>
 1032f22:	cmp    0x10(%r14),%rax
 1032f26:	jae    10331a6 <main+0x626>
 1032f2c:	movzbl %r15b,%ecx
 1032f30:	mov    %rcx,0x20(%r14,%rax,8)
 1032f35:	inc    %rax
 1032f38:	mov    %rax,0x8(%r14)
 1032f3c:	mov    %rbx,%r15
 1032f3f:	add    $0x15,%r15
 1032f43:	jo     1033bf6 <main+0x1076>
 1032f49:	cmp    0x10(%r14),%rax
 1032f4d:	jae    10331c2 <main+0x642>
 1032f53:	movzbl %r15b,%ecx
 1032f57:	mov    %rcx,0x20(%r14,%rax,8)
 1032f5c:	lea    0x1(%rax),%rcx
 1032f60:	mov    %rcx,0x8(%r14)
 1032f64:	mov    $0xffffffffffffffff,%rdi
 1032f6b:	xor    %esi,%esi
 1032f6d:	mov    %rsi,%rbx
 1032f70:	mov    %r12,%r15
 1032f73:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032f80:	mov    0x28(%r14,%rdi,8),%rdx
 1032f85:	add    %rdx,%rbx
 1032f88:	jo     1033b19 <main+0xf99>
 1032f8e:	inc    %rdi
 1032f91:	mov    %rbx,%rsi
 1032f94:	cmp    %rdi,%rax
 1032f97:	jne    1032f80 <main+0x400>
 1032f99:	cmp    0x10(%r14),%rcx
 1032f9d:	jae    10331de <main+0x65e>
 1032fa3:	movzbl %bl,%eax
 1032fa6:	mov    %rax,0x20(%r14,%rcx,8)
 1032fab:	lea    0x1(%rcx),%rdx
 1032faf:	mov    %rdx,0x8(%r14)
 1032fb3:	mov    %r13d,%eax
 1032fb6:	and    $0x3,%eax
 1032fb9:	lea    -0x2e9d0(%rip),%rsi        # 10045f0 <core_number_pairs+0xe0>
 1032fc0:	movslq (%rsi,%rax,4),%rax
 1032fc4:	add    %rsi,%rax
 1032fc7:	jmp    *%rax
 1032fc9:	movq   $0xa4,0x20(%r14)
 1032fd1:	jmp    1033012 <main+0x492>
 1032fd3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032fe0:	cmp    $0x8,%rcx
 1032fe4:	jbe    1033c38 <main+0x10b8>
 1032fea:	mov    0x68(%r14),%eax
 1032fee:	inc    %eax
 1032ff0:	movzbl %al,%eax
 1032ff3:	mov    %rax,0x68(%r14)
 1032ff7:	jmp    1033012 <main+0x492>
 1032ff9:	nopl   0x0(%rax)
 1033000:	cmp    $0x3,%rcx
 1033004:	jbe    1033c26 <main+0x10a6>
 103300a:	movq   $0x5,0x40(%r14)
 1033012:	mov    %r14,%rdi
 1033015:	vzeroupper
 1033018:	call   10132c0 <myl_core_bytes_valid_list>
 103301d:	test   %al,%al
 103301f:	je     1033c0b <main+0x108b>
 1033025:	mov    %r14,%rdi
 1033028:	call   1013320 <myl_core_bytes_from_list>
 103302d:	mov    (%r14),%ecx
 1033030:	cmp    $0xffffffff,%ecx
 1033033:	lea    0x26956(%rip),%rsi        # 1059990 <myl_core_free_lists>
 103303a:	mov    (%rsp),%r8
 103303e:	je     1033074 <main+0x4f4>
 1033040:	dec    %ecx
 1033042:	je     1033050 <main+0x4d0>
 1033044:	mov    %ecx,(%r14)
 1033047:	jmp    1033074 <main+0x4f4>
 1033049:	nopl   0x0(%rax)
 1033050:	movzbl 0x7(%r14),%ecx
 1033055:	test   %rcx,%rcx
 1033058:	je     1033224 <main+0x6a4>
 103305e:	cmpq   $0x0,0x18(%r14)
 1033063:	jne    1033224 <main+0x6a4>
 1033069:	mov    (%rsi,%rcx,8),%rdx
 103306d:	mov    %rdx,(%r14)
 1033070:	mov    %r14,(%rsi,%rcx,8)
 1033074:	mov    0x8(%r15),%rcx
 1033078:	cmp    0x10(%r15),%rcx
 103307c:	jae    10331fa <main+0x67a>
 1033082:	mov    %rax,0x20(%r15,%rcx,8)
 1033087:	inc    %rcx
 103308a:	mov    %rcx,0x8(%r15)
 103308e:	inc    %r13
 1033091:	cmp    %rbp,%r13
 1033094:	jne    1032e00 <main+0x280>
 103309a:	jmp    1033242 <main+0x6c2>
 103309f:	mov    $0x5,%edi
 10330a4:	mov    $0x8,%esi
 10330a9:	call   1009740 <myl_core_list_new_slow>
 10330ae:	mov    %rax,%r14
 10330b1:	mov    0x8(%rax),%rax
 10330b5:	mov    0x10(%r14),%rcx
 10330b9:	cmp    %rcx,%rax
 10330bc:	jb     10330d6 <main+0x556>
 10330be:	mov    $0x8,%esi
 10330c3:	mov    %r14,%rdi
 10330c6:	call   10097b0 <myl_core_list_grow>
 10330cb:	mov    %rax,%r14
 10330ce:	mov    0x8(%rax),%rax
 10330d2:	mov    0x10(%r14),%rcx
 10330d6:	mov    (%rsp),%r8
 10330da:	jmp    1032e3e <main+0x2be>
 10330df:	mov    $0x8,%esi
 10330e4:	mov    %r14,%rdi
 10330e7:	vzeroupper
 10330ea:	call   10097b0 <myl_core_list_grow>
 10330ef:	mov    (%rsp),%r8
 10330f3:	mov    %rax,%r14
 10330f6:	mov    0x8(%rax),%rax
 10330fa:	mov    0x10(%r14),%rcx
 10330fe:	jmp    1032e57 <main+0x2d7>
 1033103:	mov    $0x8,%esi
 1033108:	mov    %r14,%rdi
 103310b:	vzeroupper
 103310e:	call   10097b0 <myl_core_list_grow>
 1033113:	mov    (%rsp),%r8
 1033117:	mov    %rax,%r14
 103311a:	mov    0x8(%rax),%rax
 103311e:	mov    0x10(%r14),%rcx
 1033122:	jmp    1032e70 <main+0x2f0>
 1033127:	mov    $0x8,%esi
 103312c:	mov    %r14,%rdi
 103312f:	vzeroupper
 1033132:	call   10097b0 <myl_core_list_grow>
 1033137:	mov    (%rsp),%r8
 103313b:	mov    %rax,%r14
 103313e:	mov    0x8(%rax),%rax
 1033142:	mov    0x10(%r14),%rcx
 1033146:	jmp    1032e88 <main+0x308>
 103314b:	mov    $0x8,%esi
 1033150:	mov    %r14,%rdi
 1033153:	vzeroupper
 1033156:	call   10097b0 <myl_core_list_grow>
 103315b:	mov    (%rsp),%r8
 103315f:	mov    %rax,%r14
 1033162:	mov    0x8(%rax),%rax
 1033166:	jmp    1032ea0 <main+0x320>
 103316b:	mov    %r15,%r12
 103316e:	mov    $0x8,%esi
 1033173:	mov    %r14,%rdi
 1033176:	vzeroupper
 1033179:	call   10097b0 <myl_core_list_grow>
 103317e:	mov    %rax,%r14
 1033181:	mov    0x8(%rax),%rax
 1033185:	jmp    1032edf <main+0x35f>
 103318a:	mov    $0x8,%esi
 103318f:	mov    %r14,%rdi
 1033192:	vzeroupper
 1033195:	call   10097b0 <myl_core_list_grow>
 103319a:	mov    %rax,%r14
 103319d:	mov    0x8(%rax),%rax
 10331a1:	jmp    1032f05 <main+0x385>
 10331a6:	mov    $0x8,%esi
 10331ab:	mov    %r14,%rdi
 10331ae:	vzeroupper
 10331b1:	call   10097b0 <myl_core_list_grow>
 10331b6:	mov    %rax,%r14
 10331b9:	mov    0x8(%rax),%rax
 10331bd:	jmp    1032f2c <main+0x3ac>
 10331c2:	mov    $0x8,%esi
 10331c7:	mov    %r14,%rdi
 10331ca:	vzeroupper
 10331cd:	call   10097b0 <myl_core_list_grow>
 10331d2:	mov    %rax,%r14
 10331d5:	mov    0x8(%rax),%rax
 10331d9:	jmp    1032f53 <main+0x3d3>
 10331de:	mov    $0x8,%esi
 10331e3:	mov    %r14,%rdi
 10331e6:	vzeroupper
 10331e9:	call   10097b0 <myl_core_list_grow>
 10331ee:	mov    %rax,%r14
 10331f1:	mov    0x8(%rax),%rcx
 10331f5:	jmp    1032fa3 <main+0x423>
 10331fa:	mov    $0x8,%esi
 10331ff:	mov    %r15,%rdi
 1033202:	mov    %rax,%rbx
 1033205:	call   10097b0 <myl_core_list_grow>
 103320a:	mov    (%rsp),%r8
 103320e:	lea    0x2677b(%rip),%rsi        # 1059990 <myl_core_free_lists>
 1033215:	mov    %rax,%r15
 1033218:	mov    %rbx,%rax
 103321b:	mov    0x8(%r15),%rcx
 103321f:	jmp    1033082 <main+0x502>
 1033224:	mov    %r14,%rdi
 1033227:	mov    %rax,%rbx
 103322a:	call   1032390 <myl_core_free_block>
 103322f:	mov    (%rsp),%r8
 1033233:	lea    0x26756(%rip),%rsi        # 1059990 <myl_core_free_lists>
 103323a:	mov    %rbx,%rax
 103323d:	jmp    1033074 <main+0x4f4>
 1033242:	mov    $0x1b,%edi
 1033247:	call   100a780 <myl_core_io_at>
 103324c:	mov    0x38(%rsp),%rdi
 1033251:	call   10226f0 <myl_core_host_check>
 1033256:	xor    %r13d,%r13d
 1033259:	call   1033c80 <runtime_bench_now>
 103325e:	mov    %rax,0x28(%rsp)
 1033263:	vpxor  %xmm5,%xmm5,%xmm5
 1033267:	xor    %edi,%edi
 1033269:	mov    %r15,0x8(%rsp)
 103326e:	xchg   %ax,%ax
 1033270:	mov    %rdi,0x20(%rsp)
 1033275:	mov    %r13,(%rsp)
 1033279:	xor    %ebx,%ebx
 103327b:	xor    %r13d,%r13d
 103327e:	xchg   %ax,%ax
 1033280:	mov    0x20(%r15,%r13,8),%rax
 1033285:	mov    0x8(%rax),%rdi
 1033289:	cmp    $0x5,%rdi
 103328d:	jbe    10338b2 <main+0xd32>
 1033293:	cmpb   $0xa5,0x20(%rax)
 1033297:	jne    10338b9 <main+0xd39>
 103329d:	cmpb   $0x1,0x21(%rax)
 10332a1:	jne    10338d3 <main+0xd53>
 10332a7:	movzbl 0x24(%rax),%edx
 10332ab:	lea    0x6(%rdx),%rcx
 10332af:	cmp    %rcx,%rdi
 10332b2:	jne    10338ed <main+0xd6d>
 10332b8:	lea    -0x1(%rdi),%rcx
 10332bc:	cmp    $0x21,%rdi
 10332c0:	jb     1033300 <main+0x780>
 10332c2:	mov    %rcx,%rsi
 10332c5:	and    $0xffffffffffffffe0,%rsi
 10332c9:	lea    -0x1(%rsi),%r10
 10332cd:	mov    %r10,%r9
 10332d0:	shr    $0x5,%r9
 10332d4:	inc    %r9
 10332d7:	mov    %r9d,%r8d
 10332da:	and    $0x7,%r8d
 10332de:	cmp    $0xe0,%r10
 10332e5:	jae    103330a <main+0x78a>
 10332e7:	vpxor  %xmm0,%xmm0,%xmm0
 10332eb:	xor    %r10d,%r10d
 10332ee:	jmp    10333b9 <main+0x839>
 10332f3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033300:	xor    %esi,%esi
 1033302:	xor    %r10d,%r10d
 1033305:	jmp    103342b <main+0x8ab>
 103330a:	movabs $0xffffffffffffff8,%r10
 1033314:	and    %r10,%r9
 1033317:	vpxor  %xmm0,%xmm0,%xmm0
 103331b:	xor    %r10d,%r10d
 103331e:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 103332d:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 103333c:	nopl   0x0(%rax)
 1033340:	vpsadbw 0x20(%rax,%r10,1),%ymm5,%ymm1
 1033347:	vpaddq %ymm0,%ymm1,%ymm0
 103334b:	vpsadbw 0x40(%rax,%r10,1),%ymm5,%ymm1
 1033352:	vpsadbw 0x60(%rax,%r10,1),%ymm5,%ymm2
 1033359:	vpaddq %ymm1,%ymm2,%ymm1
 103335d:	vpaddq %ymm0,%ymm1,%ymm0
 1033361:	vpsadbw 0x80(%rax,%r10,1),%ymm5,%ymm1
 103336b:	vpsadbw 0xa0(%rax,%r10,1),%ymm5,%ymm2
 1033375:	vpaddq %ymm1,%ymm2,%ymm1
 1033379:	vpsadbw 0xc0(%rax,%r10,1),%ymm5,%ymm2
 1033383:	vpaddq %ymm1,%ymm2,%ymm1
 1033387:	vpaddq %ymm0,%ymm1,%ymm0
 103338b:	vpsadbw 0xe0(%rax,%r10,1),%ymm5,%ymm1
 1033395:	vpsadbw 0x100(%rax,%r10,1),%ymm5,%ymm2
 103339f:	vpaddq %ymm1,%ymm2,%ymm1
 10333a3:	vpaddq %ymm0,%ymm1,%ymm0
 10333a7:	add    $0x100,%r10
 10333ae:	add    $0xfffffffffffffff8,%r9
 10333b2:	jne    1033340 <main+0x7c0>
 10333b4:	test   %r8,%r8
 10333b7:	je     1033413 <main+0x893>
 10333b9:	lea    (%rax,%r10,1),%r9
 10333bd:	add    $0x20,%r9
 10333c1:	shl    $0x5,%r8d
 10333c5:	xor    %r10d,%r10d
 10333c8:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10333d7:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10333e6:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10333f5:	data16 cs nopw 0x0(%rax,%rax,1)
 1033400:	vpsadbw (%r9,%r10,1),%ymm5,%ymm1
 1033406:	vpaddq %ymm0,%ymm1,%ymm0
 103340a:	add    $0x20,%r10
 103340e:	cmp    %r10,%r8
 1033411:	jne    1033400 <main+0x880>
 1033413:	vextracti128 $0x1,%ymm0,%xmm1
 1033419:	vpaddq %xmm1,%xmm0,%xmm0
 103341d:	vpshufd $0xee,%xmm0,%xmm1
 1033422:	vpaddq %xmm1,%xmm0,%xmm0
 1033426:	vmovq  %xmm0,%r10
 103342b:	lea    0x20(%rax),%r8
 103342f:	cmp    %rcx,%rsi
 1033432:	jae    1033550 <main+0x9d0>
 1033438:	mov    %rsi,%r9
 103343b:	not    %r9
 103343e:	add    %rdi,%r9
 1033441:	cmp    $0x4,%r9
 1033445:	jb     1033540 <main+0x9c0>
 103344b:	cmp    $0x10,%r9
 103344f:	jae    1033459 <main+0x8d9>
 1033451:	xor    %r11d,%r11d
 1033454:	jmp    10334e7 <main+0x967>
 1033459:	mov    %r9,%r11
 103345c:	and    $0xfffffffffffffff0,%r11
 1033460:	vmovq  %r10,%xmm0
 1033465:	lea    (%rax,%rsi,1),%r10
 1033469:	add    $0x2c,%r10
 103346d:	vpxor  %xmm1,%xmm1,%xmm1
 1033471:	xor    %r14d,%r14d
 1033474:	vpxor  %xmm2,%xmm2,%xmm2
 1033478:	vpxor  %xmm3,%xmm3,%xmm3
 103347c:	nopl   0x0(%rax)
 1033480:	vpmovzxbq -0xc(%r10,%r14,1),%ymm4
 1033487:	vpaddq %ymm4,%ymm0,%ymm0
 103348b:	vpmovzxbq -0x8(%r10,%r14,1),%ymm4
 1033492:	vpaddq %ymm4,%ymm1,%ymm1
 1033496:	vpmovzxbq -0x4(%r10,%r14,1),%ymm4
 103349d:	vpaddq %ymm4,%ymm2,%ymm2
 10334a1:	vpmovzxbq (%r10,%r14,1),%ymm4
 10334a7:	vpaddq %ymm4,%ymm3,%ymm3
 10334ab:	add    $0x10,%r14
 10334af:	cmp    %r14,%r11
 10334b2:	jne    1033480 <main+0x900>
 10334b4:	vpaddq %ymm0,%ymm1,%ymm0
 10334b8:	vpaddq %ymm0,%ymm2,%ymm0
 10334bc:	vpaddq %ymm0,%ymm3,%ymm0
 10334c0:	vextracti128 $0x1,%ymm0,%xmm1
 10334c6:	vpaddq %xmm1,%xmm0,%xmm0
 10334ca:	vpshufd $0xee,%xmm0,%xmm1
 10334cf:	vpaddq %xmm1,%xmm0,%xmm0
 10334d3:	vmovq  %xmm0,%r10
 10334d8:	cmp    %r11,%r9
 10334db:	je     1033550 <main+0x9d0>
 10334dd:	test   $0xc,%r9b
 10334e1:	je     103398e <main+0xe0e>
 10334e7:	mov    %r9,%r14
 10334ea:	and    $0xfffffffffffffffc,%r14
 10334ee:	vmovq  %r10,%xmm0
 10334f3:	lea    (%r8,%rsi,1),%r10
 10334f7:	add    %r14,%rsi
 10334fa:	nopw   0x0(%rax,%rax,1)
 1033500:	vpmovzxbq (%r10,%r11,1),%ymm1
 1033506:	vpaddq %ymm1,%ymm0,%ymm0
 103350a:	add    $0x4,%r11
 103350e:	cmp    %r11,%r14
 1033511:	jne    1033500 <main+0x980>
 1033513:	vextracti128 $0x1,%ymm0,%xmm1
 1033519:	vpaddq %xmm1,%xmm0,%xmm0
 103351d:	vpshufd $0xee,%xmm0,%xmm1
 1033522:	vpaddq %xmm1,%xmm0,%xmm0
 1033526:	vmovq  %xmm0,%r10
 103352b:	cmp    %r14,%r9
 103352e:	je     1033550 <main+0x9d0>
 1033530:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 103353f:	nop
 1033540:	movzbl (%r8,%rsi,1),%r9d
 1033545:	add    %r9,%r10
 1033548:	inc    %rsi
 103354b:	cmp    %rsi,%rcx
 103354e:	jne    1033540 <main+0x9c0>
 1033550:	cmp    %r10b,(%r8,%rcx,1)
 1033554:	jne    1033907 <main+0xd87>
 103355a:	movabs $0x7fffffffffffffe0,%rsi
 1033564:	lea    (%rsi,%rdi,1),%r12
 1033568:	add    $0x1a,%r12
 103356c:	and    %rsi,%r12
 103356f:	je     10335a0 <main+0xa20>
 1033571:	lea    -0x1(%r12),%r10
 1033576:	shr    $0x5,%r10
 103357a:	inc    %r10
 103357d:	mov    %r10d,%esi
 1033580:	and    $0x7,%esi
 1033583:	cmp    $0xe1,%r12
 103358a:	jae    10335c0 <main+0xa40>
 103358c:	vpxor  %xmm0,%xmm0,%xmm0
 1033590:	xor    %r11d,%r11d
 1033593:	jmp    1033679 <main+0xaf9>
 1033598:	nopl   0x0(%rax,%rax,1)
 10335a0:	mov    $0x5,%r10d
 10335a6:	xor    %esi,%esi
 10335a8:	cmp    %rcx,%r10
 10335ab:	jb     10336fb <main+0xb7b>
 10335b1:	jmp    1033890 <main+0xd10>
 10335b6:	cs nopw 0x0(%rax,%rax,1)
 10335c0:	movabs $0xffffffffffffff8,%r9
 10335ca:	and    %r9,%r10
 10335cd:	vpxor  %xmm0,%xmm0,%xmm0
 10335d1:	xor    %r11d,%r11d
 10335d4:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10335e3:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10335f2:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033600:	vpsadbw 0x25(%rax,%r11,1),%ymm5,%ymm1
 1033607:	vpaddq %ymm0,%ymm1,%ymm0
 103360b:	vpsadbw 0x45(%rax,%r11,1),%ymm5,%ymm1
 1033612:	vpsadbw 0x65(%rax,%r11,1),%ymm5,%ymm2
 1033619:	vpaddq %ymm1,%ymm2,%ymm1
 103361d:	vpaddq %ymm0,%ymm1,%ymm0
 1033621:	vpsadbw 0x85(%rax,%r11,1),%ymm5,%ymm1
 103362b:	vpsadbw 0xa5(%rax,%r11,1),%ymm5,%ymm2
 1033635:	vpaddq %ymm1,%ymm2,%ymm1
 1033639:	vpsadbw 0xc5(%rax,%r11,1),%ymm5,%ymm2
 1033643:	vpaddq %ymm1,%ymm2,%ymm1
 1033647:	vpaddq %ymm0,%ymm1,%ymm0
 103364b:	vpsadbw 0xe5(%rax,%r11,1),%ymm5,%ymm1
 1033655:	vpsadbw 0x105(%rax,%r11,1),%ymm5,%ymm2
 103365f:	vpaddq %ymm1,%ymm2,%ymm1
 1033663:	vpaddq %ymm0,%ymm1,%ymm0
 1033667:	add    $0x100,%r11
 103366e:	add    $0xfffffffffffffff8,%r10
 1033672:	jne    1033600 <main+0xa80>
 1033674:	test   %rsi,%rsi
 1033677:	je     10336d3 <main+0xb53>
 1033679:	lea    (%rax,%r11,1),%r9
 103367d:	add    $0x25,%r9
 1033681:	shl    $0x5,%esi
 1033684:	xor    %r10d,%r10d
 1033687:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033696:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10336a5:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10336b4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10336c0:	vpsadbw (%r9,%r10,1),%ymm5,%ymm1
 10336c6:	vpaddq %ymm0,%ymm1,%ymm0
 10336ca:	add    $0x20,%r10
 10336ce:	cmp    %r10,%rsi
 10336d1:	jne    10336c0 <main+0xb40>
 10336d3:	mov    %r12,%r10
 10336d6:	or     $0x5,%r10
 10336da:	vextracti128 $0x1,%ymm0,%xmm1
 10336e0:	vpaddq %xmm1,%xmm0,%xmm0
 10336e4:	vpshufd $0xee,%xmm0,%xmm1
 10336e9:	vpaddq %xmm1,%xmm0,%xmm0
 10336ed:	vmovq  %xmm0,%rsi
 10336f2:	cmp    %rcx,%r10
 10336f5:	jae    1033890 <main+0xd10>
 10336fb:	lea    -0x6(%rdi),%r14
 10336ff:	mov    %r14,%r11
 1033702:	sub    %r12,%r11
 1033705:	cmp    $0x4,%r11
 1033709:	jb     1033880 <main+0xd00>
 103370f:	cmp    $0x10,%r11
 1033713:	jae    103371d <main+0xb9d>
 1033715:	xor    %r15d,%r15d
 1033718:	jmp    10337f0 <main+0xc70>
 103371d:	mov    %r14d,%ebp
 1033720:	and    $0xf,%ebp
 1033723:	mov    %r11,%r15
 1033726:	sub    %rbp,%r15
 1033729:	vmovq  %rsi,%xmm0
 103372e:	mov    %rdi,%rsi
 1033731:	sub    %rbp,%rsi
 1033734:	add    $0xfffffffffffffffa,%rsi
 1033738:	vpxor  %xmm1,%xmm1,%xmm1
 103373c:	mov    %r12,%r9
 103373f:	vpxor  %xmm2,%xmm2,%xmm2
 1033743:	vpxor  %xmm3,%xmm3,%xmm3
 1033747:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033756:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033765:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033774:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033780:	vpmovzxbq 0x25(%rax,%r9,1),%ymm4
 1033787:	vpaddq %ymm4,%ymm0,%ymm0
 103378b:	vpmovzxbq 0x29(%rax,%r9,1),%ymm4
 1033792:	vpaddq %ymm4,%ymm1,%ymm1
 1033796:	vpmovzxbq 0x2d(%rax,%r9,1),%ymm4
 103379d:	vpaddq %ymm4,%ymm2,%ymm2
 10337a1:	vpmovzxbq 0x31(%rax,%r9,1),%ymm4
 10337a8:	vpaddq %ymm4,%ymm3,%ymm3
 10337ac:	add    $0x10,%r9
 10337b0:	cmp    %r9,%rsi
 10337b3:	jne    1033780 <main+0xc00>
 10337b5:	vpaddq %ymm0,%ymm1,%ymm0
 10337b9:	vpaddq %ymm0,%ymm2,%ymm0
 10337bd:	vpaddq %ymm0,%ymm3,%ymm0
 10337c1:	vextracti128 $0x1,%ymm0,%xmm1
 10337c7:	vpaddq %xmm1,%xmm0,%xmm0
 10337cb:	vpshufd $0xee,%xmm0,%xmm1
 10337d0:	vpaddq %xmm1,%xmm0,%xmm0
 10337d4:	vmovq  %xmm0,%rsi
 10337d9:	test   %rbp,%rbp
 10337dc:	je     103396d <main+0xded>
 10337e2:	cmp    $0x4,%ebp
 10337e5:	jb     103397c <main+0xdfc>
 10337eb:	mov    0x10(%rsp),%rbp
 10337f0:	and    $0x3,%r14d
 10337f4:	sub    %r14,%r11
 10337f7:	add    %r11,%r10
 10337fa:	vmovq  %rsi,%xmm0
 10337ff:	add    %r12,%r15
 1033802:	sub    %r14,%rdi
 1033805:	add    $0xfffffffffffffffa,%rdi
 1033809:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033818:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033827:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033836:	cs nopw 0x0(%rax,%rax,1)
 1033840:	vpmovzxbq 0x25(%rax,%r15,1),%ymm1
 1033847:	vpaddq %ymm1,%ymm0,%ymm0
 103384b:	add    $0x4,%r15
 103384f:	cmp    %r15,%rdi
 1033852:	jne    1033840 <main+0xcc0>
 1033854:	vextracti128 $0x1,%ymm0,%xmm1
 103385a:	vpaddq %xmm1,%xmm0,%xmm0
 103385e:	vpshufd $0xee,%xmm0,%xmm1
 1033863:	vpaddq %xmm1,%xmm0,%xmm0
 1033867:	vmovq  %xmm0,%rsi
 103386c:	test   %r14,%r14
 103386f:	mov    0x8(%rsp),%r15
 1033874:	je     1033890 <main+0xd10>
 1033876:	cs nopw 0x0(%rax,%rax,1)
 1033880:	movzbl (%r8,%r10,1),%edi
 1033885:	add    %rdi,%rsi
 1033888:	inc    %r10
 103388b:	cmp    %rcx,%r10
 103388e:	jl     1033880 <main+0xd00>
 1033890:	movbe  0x22(%rax),%ax
 1033896:	movzwl %ax,%eax
 1033899:	xor    %ecx,%ecx
 103389b:	test   %cl,%cl
 103389d:	je     103392e <main+0xdae>
 10338a3:	imul   $0x65,%rax,%rcx
 10338a7:	jno    1033950 <main+0xdd0>
 10338ad:	jmp    1033b39 <main+0xfb9>
 10338b2:	mov    $0x3b,%edi
 10338b7:	jmp    10338f2 <main+0xd72>
 10338b9:	mov    $0x3d,%edi
 10338be:	xor    %esi,%esi
 10338c0:	vzeroupper
 10338c3:	call   103273c <myl_core_err_trace>
 10338c8:	vpxor  %xmm5,%xmm5,%xmm5
 10338cc:	mov    $0x1,%eax
 10338d1:	jmp    1033920 <main+0xda0>
 10338d3:	mov    $0x3f,%edi
 10338d8:	xor    %esi,%esi
 10338da:	vzeroupper
 10338dd:	call   103273c <myl_core_err_trace>
 10338e2:	vpxor  %xmm5,%xmm5,%xmm5
 10338e6:	mov    $0x2,%eax
 10338eb:	jmp    1033920 <main+0xda0>
 10338ed:	mov    $0x41,%edi
 10338f2:	xor    %esi,%esi
 10338f4:	vzeroupper
 10338f7:	call   103273c <myl_core_err_trace>
 10338fc:	vpxor  %xmm5,%xmm5,%xmm5
 1033900:	mov    $0x3,%eax
 1033905:	jmp    1033920 <main+0xda0>
 1033907:	mov    $0x43,%edi
 103390c:	xor    %esi,%esi
 103390e:	vzeroupper
 1033911:	call   103273c <myl_core_err_trace>
 1033916:	vpxor  %xmm5,%xmm5,%xmm5
 103391a:	mov    $0x4,%eax
 103391f:	nop
 1033920:	mov    $0x1,%cl
 1033922:	xor    %esi,%esi
 1033924:	xor    %edx,%edx
 1033926:	test   %cl,%cl
 1033928:	jne    10338a3 <main+0xd23>
 103392e:	imul   $0x3,%rsi,%rcx
 1033932:	jo     1033b77 <main+0xff7>
 1033938:	mov    %rax,%rsi
 103393b:	add    %rcx,%rsi
 103393e:	jo     1033b89 <main+0x1009>
 1033944:	mov    %rsi,%rcx
 1033947:	add    %rdx,%rcx
 103394a:	jo     1033b9c <main+0x101c>
 1033950:	mov    %rbx,%rdx
 1033953:	add    %rcx,%rdx
 1033956:	jo     1033b26 <main+0xfa6>
 103395c:	inc    %r13
 103395f:	mov    %rdx,%rbx
 1033962:	cmp    %rbp,%r13
 1033965:	jne    1033280 <main+0x700>
 103396b:	jmp    10339a0 <main+0xe20>
 103396d:	mov    0x10(%rsp),%rbp
 1033972:	mov    0x8(%rsp),%r15
 1033977:	jmp    1033890 <main+0xd10>
 103397c:	add    %r15,%r10
 103397f:	mov    0x10(%rsp),%rbp
 1033984:	mov    0x8(%rsp),%r15
 1033989:	jmp    1033880 <main+0xd00>
 103398e:	add    %r11,%rsi
 1033991:	jmp    1033540 <main+0x9c0>
 1033996:	cs nopw 0x0(%rax,%rax,1)
 10339a0:	mov    %rdx,%rcx
 10339a3:	mov    (%rsp),%rsi
 10339a7:	add    %rsi,%rcx
 10339aa:	mov    0x20(%rsp),%rdi
 10339af:	jo     1033c19 <main+0x1099>
 10339b5:	mov    %rcx,%rax
 10339b8:	movabs $0x89705f3112a28fe5,%rdx
 10339c2:	imul   %rdx
 10339c5:	add    %rcx,%rdx
 10339c8:	mov    %rdx,%rax
 10339cb:	shr    $0x3f,%rax
 10339cf:	sar    $0x1d,%rdx
 10339d3:	add    %rax,%rdx
 10339d6:	imul   $0x3b9aca07,%rdx,%rax
 10339dd:	sub    %rax,%rcx
 10339e0:	mov    %rcx,%r13
 10339e3:	sar    $0x3f,%r13
 10339e7:	and    $0x3b9aca07,%r13d
 10339ee:	add    %rcx,%r13
 10339f1:	inc    %rdi
 10339f4:	cmp    0x40(%rsp),%rdi
 10339f9:	jne    1033270 <main+0x6f0>
 10339ff:	mov    0x18(%rsp),%rdi
 1033a04:	movzbl 0x7(%rdi),%eax
 1033a08:	test   %rax,%rax
 1033a0b:	je     1033b4e <main+0xfce>
 1033a11:	cmpq   $0x0,0x18(%rdi)
 1033a16:	jne    1033b4e <main+0xfce>
 1033a1c:	lea    0x25f6d(%rip),%rdx        # 1059990 <myl_core_free_lists>
 1033a23:	mov    (%rdx,%rax,8),%rcx
 1033a27:	mov    %rcx,(%rdi)
 1033a2a:	mov    %rdi,(%rdx,%rax,8)
 1033a2e:	mov    0x30(%rsp),%r14
 1033a33:	mov    0x28(%rsp),%r12
 1033a38:	movzbl 0x7(%r15),%eax
 1033a3d:	test   %rax,%rax
 1033a40:	mov    0x38(%rsp),%rbx
 1033a45:	je     1033b67 <main+0xfe7>
 1033a4b:	cmpq   $0x0,0x18(%r15)
 1033a50:	jne    1033b67 <main+0xfe7>
 1033a56:	mov    (%rdx,%rax,8),%rcx
 1033a5a:	mov    %rcx,(%r15)
 1033a5d:	mov    %r15,(%rdx,%rax,8)
 1033a61:	mov    $0x1c,%edi
 1033a66:	vzeroupper
 1033a69:	call   100a780 <myl_core_io_at>
 1033a6e:	mov    %rbx,%rdi
 1033a71:	call   10226f0 <myl_core_host_check>
 1033a76:	call   1033c80 <runtime_bench_now>
 1033a7b:	mov    %rax,%rbx
 1033a7e:	sub    %r12,%rbx
 1033a81:	jo     1033c68 <main+0x10e8>
 1033a87:	mov    $0x1,%edi
 1033a8c:	mov    %r13,%rsi
 1033a8f:	call   100ae80 <myl_core_print_i64>
 1033a94:	mov    $0x1,%edi
 1033a99:	call   10094c0 <myl_core_print_sep>
 1033a9e:	mov    $0x1,%edi
 1033aa3:	mov    %rbx,%rsi
 1033aa6:	call   100ae80 <myl_core_print_i64>
 1033aab:	mov    $0x1,%edi
 1033ab0:	call   1009580 <myl_core_print_end>
 1033ab5:	xor    %ebx,%ebx
 1033ab7:	mov    %r14,%rdi
 1033aba:	call   1009c80 <myl_core_release>
 1033abf:	mov    %rbx,%rdi
 1033ac2:	add    $0x48,%rsp
 1033ac6:	pop    %rbx
 1033ac7:	pop    %r12
 1033ac9:	pop    %r13
 1033acb:	pop    %r14
 1033acd:	pop    %r15
 1033acf:	pop    %rbp
 1033ad0:	jmp    100a790 <myl_core_exit>
 1033ad5:	mov    %rsi,%rbx
 1033ad8:	mov    $0x8,%esi
 1033add:	mov    %rbp,%rdi
 1033ae0:	mov    %r9,%r14
 1033ae3:	mov    %r10d,%r15d
 1033ae6:	call   1009740 <myl_core_list_new_slow>
 1033aeb:	mov    %r15d,%r10d
 1033aee:	mov    %r14,%r9
 1033af1:	mov    %rbx,%rsi
 1033af4:	mov    (%rsp),%r8
 1033af8:	mov    %rax,%rdi
 1033afb:	jmp    1032ca2 <main+0x122>
 1033b00:	mov    $0x8,%esi
 1033b05:	mov    %rbp,%rdi
 1033b08:	call   1009740 <myl_core_list_new_slow>
 1033b0d:	mov    (%rsp),%r8
 1033b11:	mov    %rax,%r15
 1033b14:	jmp    1032de4 <main+0x264>
 1033b19:	mov    $0x3a,%edi
 1033b1e:	vzeroupper
 1033b21:	call   1009e40 <myl_core_trap>
 1033b26:	mov    $0x23,%edi
 1033b2b:	mov    %rbx,%rsi
 1033b2e:	mov    %rcx,%rdx
 1033b31:	vzeroupper
 1033b34:	call   1009e40 <myl_core_trap>
 1033b39:	mov    $0x65,%edx
 1033b3e:	mov    $0x27,%edi
 1033b43:	mov    %rax,%rsi
 1033b46:	vzeroupper
 1033b49:	call   1009e40 <myl_core_trap>
 1033b4e:	vzeroupper
 1033b51:	call   1032390 <myl_core_free_block>
 1033b56:	mov    0x30(%rsp),%r14
 1033b5b:	lea    0x25e2e(%rip),%rdx        # 1059990 <myl_core_free_lists>
 1033b62:	jmp    1033a33 <main+0xeb3>
 1033b67:	mov    %r15,%rdi
 1033b6a:	vzeroupper
 1033b6d:	call   1032390 <myl_core_free_block>
 1033b72:	jmp    1033a61 <main+0xee1>
 1033b77:	mov    $0x3,%edx
 1033b7c:	mov    $0x24,%edi
 1033b81:	vzeroupper
 1033b84:	call   1009e40 <myl_core_trap>
 1033b89:	mov    $0x25,%edi
 1033b8e:	mov    %rax,%rsi
 1033b91:	mov    %rcx,%rdx
 1033b94:	vzeroupper
 1033b97:	call   1009e40 <myl_core_trap>
 1033b9c:	mov    $0x26,%edi
 1033ba1:	vzeroupper
 1033ba4:	call   1009e40 <myl_core_trap>
 1033ba9:	mov    $0x25,%edx
 1033bae:	mov    $0x11,%edi
 1033bb3:	mov    %rbx,%rsi
 1033bb6:	call   1009e40 <myl_core_trap>
 1033bbb:	mov    $0x12,%edi
 1033bc0:	mov    %r8,%rsi
 1033bc3:	mov    %r14,%rdx
 1033bc6:	call   1009e40 <myl_core_trap>
 1033bcb:	mov    $0x28,%edi
 1033bd0:	mov    %r8,%rsi
 1033bd3:	call   1009e40 <myl_core_trap>
 1033bd8:	mov    $0x29,%edi
 1033bdd:	mov    %r8,%rsi
 1033be0:	vzeroupper
 1033be3:	call   1009e40 <myl_core_trap>
 1033be8:	mov    $0x7,%edx
 1033bed:	jmp    1033bfb <main+0x107b>
 1033bef:	mov    $0xe,%edx
 1033bf4:	jmp    1033bfb <main+0x107b>
 1033bf6:	mov    $0x15,%edx
 1033bfb:	mov    $0x2a,%edi
 1033c00:	mov    %rbx,%rsi
 1033c03:	vzeroupper
 1033c06:	call   1009e40 <myl_core_trap>
 1033c0b:	mov    $0x38,%edi
 1033c10:	xor    %esi,%esi
 1033c12:	xor    %edx,%edx
 1033c14:	call   1009e40 <myl_core_trap>
 1033c19:	mov    $0x1e,%edi
 1033c1e:	vzeroupper
 1033c21:	call   1009e40 <myl_core_trap>
 1033c26:	mov    $0x4,%esi
 1033c2b:	mov    $0x37,%edi
 1033c30:	vzeroupper
 1033c33:	call   1009e40 <myl_core_trap>
 1033c38:	mov    $0x9,%esi
 1033c3d:	mov    $0x31,%edi
 1033c42:	vzeroupper
 1033c45:	call   1009e40 <myl_core_trap>
 1033c4a:	mov    $0x1,%esi
 1033c4f:	mov    $0x5,%edi
 1033c54:	call   1009e40 <myl_core_trap>
 1033c59:	mov    $0x2,%esi
 1033c5e:	mov    $0x8,%edi
 1033c63:	call   1009e40 <myl_core_trap>
 1033c68:	mov    $0x1d,%edi
 1033c6d:	mov    %rax,%rsi
 1033c70:	mov    %r12,%rdx
 1033c73:	call   1009e40 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
