
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-packet-performance/.mylang-cache/s3-packet/rows-02/row_packet_decode_new:     file format elf64-x86-64


Disassembly of section .text:

00000000010328c0 <main>:
 10328c0:	push   %rbp
 10328c1:	push   %r15
 10328c3:	push   %r14
 10328c5:	push   %r13
 10328c7:	push   %r12
 10328c9:	push   %rbx
 10328ca:	sub    $0x48,%rsp
 10328ce:	call   1009bf0 <myl_core_args>
 10328d3:	mov    %rax,%r14
 10328d6:	call   1022500 <myl_core_host_grant>
 10328db:	mov    $0x2,%ebx
 10328e0:	cmpq   $0x3,0x8(%r14)
 10328e5:	jne    10337f7 <main+0xf37>
 10328eb:	mov    %rax,%r15
 10328ee:	mov    0x20(%r14),%rdi
 10328f2:	call   10326c0 <my.row_packet_decode::parse_number>
 10328f7:	mov    0x8(%r14),%rdx
 10328fb:	cmp    $0x1,%rdx
 10328ff:	jbe    103398a <main+0x10ca>
 1032905:	mov    %rax,%rbp
 1032908:	mov    0x28(%r14),%rdi
 103290c:	call   10326c0 <my.row_packet_decode::parse_number>
 1032911:	mov    0x8(%r14),%rdx
 1032915:	cmp    $0x2,%rdx
 1032919:	jbe    1033999 <main+0x10d9>
 103291f:	mov    %rax,%r12
 1032922:	mov    0x30(%r14),%rdi
 1032926:	call   10326c0 <my.row_packet_decode::parse_number>
 103292b:	mov    %rax,%r8
 103292e:	cmp    $0x2,%rbp
 1032932:	setl   %al
 1032935:	test   %r12,%r12
 1032938:	setle  %cl
 103293b:	or     %al,%cl
 103293d:	lea    -0xf4241(%r8),%rax
 1032944:	cmp    $0xfffffffffff0bdc0,%rax
 103294a:	setb   %al
 103294d:	or     %cl,%al
 103294f:	jne    10337f7 <main+0xf37>
 1032955:	cmp    $0x401,%rbp
 103295c:	setae  %al
 103295f:	lea    0x3f(,%rbp,8),%rsi
 1032967:	mov    %rsi,%r9
 103296a:	shr    $0x5,%r9
 103296e:	cmp    $0x420,%rsi
 1032975:	setae  %r10b
 1032979:	or     %al,%r10b
 103297c:	mov    %r8,(%rsp)
 1032980:	mov    %r14,0x30(%rsp)
 1032985:	mov    %r15,0x38(%rsp)
 103298a:	mov    %r12,0x40(%rsp)
 103298f:	jne    1033815 <main+0xf55>
 1032995:	lea    0x26d34(%rip),%rax        # 10596d0 <myl_core_free_lists>
 103299c:	mov    (%rax,%r9,8),%rdi
 10329a0:	test   %rdi,%rdi
 10329a3:	je     1033815 <main+0xf55>
 10329a9:	mov    (%rdi),%rcx
 10329ac:	mov    %rcx,(%rax,%r9,8)
 10329b0:	movl   $0x1,(%rdi)
 10329b6:	mov    %r9d,%eax
 10329b9:	shl    $0x18,%eax
 10329bc:	mov    %eax,0x4(%rdi)
 10329bf:	movq   $0x0,0x8(%rdi)
 10329c7:	mov    %esi,%eax
 10329c9:	and    $0x7e0,%eax
 10329ce:	add    $0xffffffffffffffe0,%rax
 10329d2:	shr    $0x3,%rax
 10329d6:	mov    %rax,0x10(%rdi)
 10329da:	movq   $0x0,0x18(%rdi)
 10329e2:	movabs $0x3759f22983759f3,%rbx
 10329ec:	xor    %r14d,%r14d
 10329ef:	movabs $0x81e722c258cd00c3,%r15
 10329f9:	xor    %r13d,%r13d
 10329fc:	mov    %rbp,0x10(%rsp)
 1032a01:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032a10:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032a1f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032a2e:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032a3d:	nopl   (%rax)
 1032a40:	cmp    %r13,%rbx
 1032a43:	je     10338e9 <main+0x1029>
 1032a49:	mov    %r8,%rbp
 1032a4c:	add    %r14,%rbp
 1032a4f:	jo     10338fb <main+0x103b>
 1032a55:	mov    %rbp,%rdx
 1032a58:	mulx   %r15,%r12,%r12
 1032a5d:	mov    0x8(%rdi),%rax
 1032a61:	cmp    0x10(%rdi),%rax
 1032a65:	jae    1032a94 <main+0x1d4>
 1032a67:	shr    $0x9,%r12
 1032a6b:	imul   $0x3f1,%r12,%rcx
 1032a72:	sub    %rcx,%rbp
 1032a75:	mov    %rbp,0x20(%rdi,%rax,8)
 1032a7a:	inc    %rax
 1032a7d:	mov    %rax,0x8(%rdi)
 1032a81:	inc    %r13
 1032a84:	add    $0x25,%r14
 1032a88:	mov    0x10(%rsp),%rbp
 1032a8d:	cmp    %r13,%rbp
 1032a90:	jne    1032a40 <main+0x180>
 1032a92:	jmp    1032aca <main+0x20a>
 1032a94:	mov    %rsi,0x8(%rsp)
 1032a99:	mov    $0x8,%esi
 1032a9e:	mov    %r9,0x20(%rsp)
 1032aa3:	mov    %r10b,0x18(%rsp)
 1032aa8:	call   10096f0 <myl_core_list_grow>
 1032aad:	movzbl 0x18(%rsp),%r10d
 1032ab3:	mov    0x20(%rsp),%r9
 1032ab8:	mov    0x8(%rsp),%rsi
 1032abd:	mov    (%rsp),%r8
 1032ac1:	mov    %rax,%rdi
 1032ac4:	mov    0x8(%rax),%rax
 1032ac8:	jmp    1032a67 <main+0x1a7>
 1032aca:	test   %r10b,%r10b
 1032acd:	mov    %rdi,0x18(%rsp)
 1032ad2:	jne    1033840 <main+0xf80>
 1032ad8:	lea    0x26bf1(%rip),%rax        # 10596d0 <myl_core_free_lists>
 1032adf:	mov    (%rax,%r9,8),%r15
 1032ae3:	test   %r15,%r15
 1032ae6:	je     1033840 <main+0xf80>
 1032aec:	mov    (%r15),%rcx
 1032aef:	mov    %rcx,(%rax,%r9,8)
 1032af3:	movl   $0x1,(%r15)
 1032afa:	shl    $0x18,%r9d
 1032afe:	mov    %r9d,0x4(%r15)
 1032b02:	movq   $0x0,0x8(%r15)
 1032b0a:	and    $0x7e0,%esi
 1032b10:	add    $0xffffffffffffffe0,%rsi
 1032b14:	shr    $0x3,%rsi
 1032b18:	mov    %rsi,0x10(%r15)
 1032b1c:	movq   $0x0,0x18(%r15)
 1032b24:	lea    -0x2da8b(%rip),%rax        # 10050a0 <myl_core_site_count+0x4>
 1032b2b:	mov    %rax,0x18(%r15)
 1032b2f:	xor    %r13d,%r13d
 1032b32:	lea    0x26b97(%rip),%rsi        # 10596d0 <myl_core_free_lists>
 1032b39:	nopl   0x0(%rax)
 1032b40:	mov    %r13,%rdx
 1032b43:	shl    $0x4,%rdx
 1032b47:	add    %r13,%rdx
 1032b4a:	mov    %r8,%rbx
 1032b4d:	add    %rdx,%rbx
 1032b50:	jo     103390b <main+0x104b>
 1032b56:	mov    0x18(%rsi),%r14
 1032b5a:	test   %r14,%r14
 1032b5d:	je     1032ddf <main+0x51f>
 1032b63:	mov    (%r14),%rax
 1032b66:	mov    %rax,0x18(%rsi)
 1032b6a:	vmovdqa -0x2f4d2(%rip),%ymm0        # 10036a0 <core_io_raw_layout+0x120>
 1032b72:	vmovdqu %ymm0,(%r14)
 1032b77:	mov    $0x8,%ecx
 1032b7c:	xor    %eax,%eax
 1032b7e:	movq   $0xa5,0x20(%r14,%rax,8)
 1032b87:	inc    %rax
 1032b8a:	mov    %rax,0x8(%r14)
 1032b8e:	cmp    %rcx,%rax
 1032b91:	jae    1032e1f <main+0x55f>
 1032b97:	movq   $0x1,0x20(%r14,%rax,8)
 1032ba0:	inc    %rax
 1032ba3:	mov    %rax,0x8(%r14)
 1032ba7:	cmp    %rcx,%rax
 1032baa:	jae    1032e43 <main+0x583>
 1032bb0:	movzbl %bh,%edx
 1032bb3:	mov    %rdx,0x20(%r14,%rax,8)
 1032bb8:	inc    %rax
 1032bbb:	mov    %rax,0x8(%r14)
 1032bbf:	cmp    %rcx,%rax
 1032bc2:	jae    1032e67 <main+0x5a7>
 1032bc8:	movzbl %bl,%edx
 1032bcb:	mov    %rdx,0x20(%r14,%rax,8)
 1032bd0:	inc    %rax
 1032bd3:	mov    %rax,0x8(%r14)
 1032bd7:	cmp    %rcx,%rax
 1032bda:	jae    1032e8b <main+0x5cb>
 1032be0:	movq   $0x4,0x20(%r14,%rax,8)
 1032be9:	inc    %rax
 1032bec:	mov    %rax,0x8(%r14)
 1032bf0:	lea    0x0(,%r13,2),%rcx
 1032bf8:	add    %r13,%rcx
 1032bfb:	lea    0x0(,%rcx,4),%rdx
 1032c03:	add    %r13,%rdx
 1032c06:	mov    %r8,%rbx
 1032c09:	add    %rdx,%rbx
 1032c0c:	jo     1033918 <main+0x1058>
 1032c12:	cmp    0x10(%r14),%rax
 1032c16:	jae    1032eab <main+0x5eb>
 1032c1c:	mov    %r15,%r12
 1032c1f:	movzbl %bl,%ecx
 1032c22:	mov    %rcx,0x20(%r14,%rax,8)
 1032c27:	inc    %rax
 1032c2a:	mov    %rax,0x8(%r14)
 1032c2e:	mov    %rbx,%r15
 1032c31:	add    $0x7,%r15
 1032c35:	jo     1033928 <main+0x1068>
 1032c3b:	cmp    0x10(%r14),%rax
 1032c3f:	jae    1032eca <main+0x60a>
 1032c45:	movzbl %r15b,%ecx
 1032c49:	mov    %rcx,0x20(%r14,%rax,8)
 1032c4e:	inc    %rax
 1032c51:	mov    %rax,0x8(%r14)
 1032c55:	mov    %rbx,%r15
 1032c58:	add    $0xe,%r15
 1032c5c:	jo     103392f <main+0x106f>
 1032c62:	cmp    0x10(%r14),%rax
 1032c66:	jae    1032ee6 <main+0x626>
 1032c6c:	movzbl %r15b,%ecx
 1032c70:	mov    %rcx,0x20(%r14,%rax,8)
 1032c75:	inc    %rax
 1032c78:	mov    %rax,0x8(%r14)
 1032c7c:	mov    %rbx,%r15
 1032c7f:	add    $0x15,%r15
 1032c83:	jo     1033936 <main+0x1076>
 1032c89:	cmp    0x10(%r14),%rax
 1032c8d:	jae    1032f02 <main+0x642>
 1032c93:	movzbl %r15b,%ecx
 1032c97:	mov    %rcx,0x20(%r14,%rax,8)
 1032c9c:	lea    0x1(%rax),%rcx
 1032ca0:	mov    %rcx,0x8(%r14)
 1032ca4:	mov    $0xffffffffffffffff,%rdi
 1032cab:	xor    %esi,%esi
 1032cad:	mov    %rsi,%rbx
 1032cb0:	mov    %r12,%r15
 1032cb3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cc0:	mov    0x28(%r14,%rdi,8),%rdx
 1032cc5:	add    %rdx,%rbx
 1032cc8:	jo     1033859 <main+0xf99>
 1032cce:	inc    %rdi
 1032cd1:	mov    %rbx,%rsi
 1032cd4:	cmp    %rdi,%rax
 1032cd7:	jne    1032cc0 <main+0x400>
 1032cd9:	cmp    0x10(%r14),%rcx
 1032cdd:	jae    1032f1e <main+0x65e>
 1032ce3:	movzbl %bl,%eax
 1032ce6:	mov    %rax,0x20(%r14,%rcx,8)
 1032ceb:	lea    0x1(%rcx),%rdx
 1032cef:	mov    %rdx,0x8(%r14)
 1032cf3:	mov    %r13d,%eax
 1032cf6:	and    $0x3,%eax
 1032cf9:	lea    -0x2e710(%rip),%rsi        # 10045f0 <core_number_pairs+0xe0>
 1032d00:	movslq (%rsi,%rax,4),%rax
 1032d04:	add    %rsi,%rax
 1032d07:	jmp    *%rax
 1032d09:	movq   $0xa4,0x20(%r14)
 1032d11:	jmp    1032d52 <main+0x492>
 1032d13:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032d20:	cmp    $0x8,%rcx
 1032d24:	jbe    1033978 <main+0x10b8>
 1032d2a:	mov    0x68(%r14),%eax
 1032d2e:	inc    %eax
 1032d30:	movzbl %al,%eax
 1032d33:	mov    %rax,0x68(%r14)
 1032d37:	jmp    1032d52 <main+0x492>
 1032d39:	nopl   0x0(%rax)
 1032d40:	cmp    $0x3,%rcx
 1032d44:	jbe    1033966 <main+0x10a6>
 1032d4a:	movq   $0x5,0x40(%r14)
 1032d52:	mov    %r14,%rdi
 1032d55:	vzeroupper
 1032d58:	call   10131c0 <myl_core_bytes_valid_list>
 1032d5d:	test   %al,%al
 1032d5f:	je     103394b <main+0x108b>
 1032d65:	mov    %r14,%rdi
 1032d68:	call   1013220 <myl_core_bytes_from_list>
 1032d6d:	mov    (%r14),%ecx
 1032d70:	cmp    $0xffffffff,%ecx
 1032d73:	lea    0x26956(%rip),%rsi        # 10596d0 <myl_core_free_lists>
 1032d7a:	mov    (%rsp),%r8
 1032d7e:	je     1032db4 <main+0x4f4>
 1032d80:	dec    %ecx
 1032d82:	je     1032d90 <main+0x4d0>
 1032d84:	mov    %ecx,(%r14)
 1032d87:	jmp    1032db4 <main+0x4f4>
 1032d89:	nopl   0x0(%rax)
 1032d90:	movzbl 0x7(%r14),%ecx
 1032d95:	test   %rcx,%rcx
 1032d98:	je     1032f64 <main+0x6a4>
 1032d9e:	cmpq   $0x0,0x18(%r14)
 1032da3:	jne    1032f64 <main+0x6a4>
 1032da9:	mov    (%rsi,%rcx,8),%rdx
 1032dad:	mov    %rdx,(%r14)
 1032db0:	mov    %r14,(%rsi,%rcx,8)
 1032db4:	mov    0x8(%r15),%rcx
 1032db8:	cmp    0x10(%r15),%rcx
 1032dbc:	jae    1032f3a <main+0x67a>
 1032dc2:	mov    %rax,0x20(%r15,%rcx,8)
 1032dc7:	inc    %rcx
 1032dca:	mov    %rcx,0x8(%r15)
 1032dce:	inc    %r13
 1032dd1:	cmp    %rbp,%r13
 1032dd4:	jne    1032b40 <main+0x280>
 1032dda:	jmp    1032f82 <main+0x6c2>
 1032ddf:	mov    $0x5,%edi
 1032de4:	mov    $0x8,%esi
 1032de9:	call   1009680 <myl_core_list_new_slow>
 1032dee:	mov    %rax,%r14
 1032df1:	mov    0x8(%rax),%rax
 1032df5:	mov    0x10(%r14),%rcx
 1032df9:	cmp    %rcx,%rax
 1032dfc:	jb     1032e16 <main+0x556>
 1032dfe:	mov    $0x8,%esi
 1032e03:	mov    %r14,%rdi
 1032e06:	call   10096f0 <myl_core_list_grow>
 1032e0b:	mov    %rax,%r14
 1032e0e:	mov    0x8(%rax),%rax
 1032e12:	mov    0x10(%r14),%rcx
 1032e16:	mov    (%rsp),%r8
 1032e1a:	jmp    1032b7e <main+0x2be>
 1032e1f:	mov    $0x8,%esi
 1032e24:	mov    %r14,%rdi
 1032e27:	vzeroupper
 1032e2a:	call   10096f0 <myl_core_list_grow>
 1032e2f:	mov    (%rsp),%r8
 1032e33:	mov    %rax,%r14
 1032e36:	mov    0x8(%rax),%rax
 1032e3a:	mov    0x10(%r14),%rcx
 1032e3e:	jmp    1032b97 <main+0x2d7>
 1032e43:	mov    $0x8,%esi
 1032e48:	mov    %r14,%rdi
 1032e4b:	vzeroupper
 1032e4e:	call   10096f0 <myl_core_list_grow>
 1032e53:	mov    (%rsp),%r8
 1032e57:	mov    %rax,%r14
 1032e5a:	mov    0x8(%rax),%rax
 1032e5e:	mov    0x10(%r14),%rcx
 1032e62:	jmp    1032bb0 <main+0x2f0>
 1032e67:	mov    $0x8,%esi
 1032e6c:	mov    %r14,%rdi
 1032e6f:	vzeroupper
 1032e72:	call   10096f0 <myl_core_list_grow>
 1032e77:	mov    (%rsp),%r8
 1032e7b:	mov    %rax,%r14
 1032e7e:	mov    0x8(%rax),%rax
 1032e82:	mov    0x10(%r14),%rcx
 1032e86:	jmp    1032bc8 <main+0x308>
 1032e8b:	mov    $0x8,%esi
 1032e90:	mov    %r14,%rdi
 1032e93:	vzeroupper
 1032e96:	call   10096f0 <myl_core_list_grow>
 1032e9b:	mov    (%rsp),%r8
 1032e9f:	mov    %rax,%r14
 1032ea2:	mov    0x8(%rax),%rax
 1032ea6:	jmp    1032be0 <main+0x320>
 1032eab:	mov    %r15,%r12
 1032eae:	mov    $0x8,%esi
 1032eb3:	mov    %r14,%rdi
 1032eb6:	vzeroupper
 1032eb9:	call   10096f0 <myl_core_list_grow>
 1032ebe:	mov    %rax,%r14
 1032ec1:	mov    0x8(%rax),%rax
 1032ec5:	jmp    1032c1f <main+0x35f>
 1032eca:	mov    $0x8,%esi
 1032ecf:	mov    %r14,%rdi
 1032ed2:	vzeroupper
 1032ed5:	call   10096f0 <myl_core_list_grow>
 1032eda:	mov    %rax,%r14
 1032edd:	mov    0x8(%rax),%rax
 1032ee1:	jmp    1032c45 <main+0x385>
 1032ee6:	mov    $0x8,%esi
 1032eeb:	mov    %r14,%rdi
 1032eee:	vzeroupper
 1032ef1:	call   10096f0 <myl_core_list_grow>
 1032ef6:	mov    %rax,%r14
 1032ef9:	mov    0x8(%rax),%rax
 1032efd:	jmp    1032c6c <main+0x3ac>
 1032f02:	mov    $0x8,%esi
 1032f07:	mov    %r14,%rdi
 1032f0a:	vzeroupper
 1032f0d:	call   10096f0 <myl_core_list_grow>
 1032f12:	mov    %rax,%r14
 1032f15:	mov    0x8(%rax),%rax
 1032f19:	jmp    1032c93 <main+0x3d3>
 1032f1e:	mov    $0x8,%esi
 1032f23:	mov    %r14,%rdi
 1032f26:	vzeroupper
 1032f29:	call   10096f0 <myl_core_list_grow>
 1032f2e:	mov    %rax,%r14
 1032f31:	mov    0x8(%rax),%rcx
 1032f35:	jmp    1032ce3 <main+0x423>
 1032f3a:	mov    $0x8,%esi
 1032f3f:	mov    %r15,%rdi
 1032f42:	mov    %rax,%rbx
 1032f45:	call   10096f0 <myl_core_list_grow>
 1032f4a:	mov    (%rsp),%r8
 1032f4e:	lea    0x2677b(%rip),%rsi        # 10596d0 <myl_core_free_lists>
 1032f55:	mov    %rax,%r15
 1032f58:	mov    %rbx,%rax
 1032f5b:	mov    0x8(%r15),%rcx
 1032f5f:	jmp    1032dc2 <main+0x502>
 1032f64:	mov    %r14,%rdi
 1032f67:	mov    %rax,%rbx
 1032f6a:	call   10320d0 <myl_core_free_block>
 1032f6f:	mov    (%rsp),%r8
 1032f73:	lea    0x26756(%rip),%rsi        # 10596d0 <myl_core_free_lists>
 1032f7a:	mov    %rbx,%rax
 1032f7d:	jmp    1032db4 <main+0x4f4>
 1032f82:	mov    $0x1b,%edi
 1032f87:	call   100a500 <myl_core_io_at>
 1032f8c:	mov    0x38(%rsp),%rdi
 1032f91:	call   1022530 <myl_core_host_check>
 1032f96:	xor    %r13d,%r13d
 1032f99:	call   10339c0 <runtime_bench_now>
 1032f9e:	mov    %rax,0x28(%rsp)
 1032fa3:	vpxor  %xmm5,%xmm5,%xmm5
 1032fa7:	xor    %edi,%edi
 1032fa9:	mov    %r15,0x8(%rsp)
 1032fae:	xchg   %ax,%ax
 1032fb0:	mov    %rdi,0x20(%rsp)
 1032fb5:	mov    %r13,(%rsp)
 1032fb9:	xor    %ebx,%ebx
 1032fbb:	xor    %r13d,%r13d
 1032fbe:	xchg   %ax,%ax
 1032fc0:	mov    0x20(%r15,%r13,8),%rax
 1032fc5:	mov    0x8(%rax),%rdi
 1032fc9:	cmp    $0x5,%rdi
 1032fcd:	jbe    10335f2 <main+0xd32>
 1032fd3:	cmpb   $0xa5,0x20(%rax)
 1032fd7:	jne    10335f9 <main+0xd39>
 1032fdd:	cmpb   $0x1,0x21(%rax)
 1032fe1:	jne    1033613 <main+0xd53>
 1032fe7:	movzbl 0x24(%rax),%edx
 1032feb:	lea    0x6(%rdx),%rcx
 1032fef:	cmp    %rcx,%rdi
 1032ff2:	jne    103362d <main+0xd6d>
 1032ff8:	lea    -0x1(%rdi),%rcx
 1032ffc:	cmp    $0x21,%rdi
 1033000:	jb     1033040 <main+0x780>
 1033002:	mov    %rcx,%rsi
 1033005:	and    $0xffffffffffffffe0,%rsi
 1033009:	lea    -0x1(%rsi),%r10
 103300d:	mov    %r10,%r9
 1033010:	shr    $0x5,%r9
 1033014:	inc    %r9
 1033017:	mov    %r9d,%r8d
 103301a:	and    $0x7,%r8d
 103301e:	cmp    $0xe0,%r10
 1033025:	jae    103304a <main+0x78a>
 1033027:	vpxor  %xmm0,%xmm0,%xmm0
 103302b:	xor    %r10d,%r10d
 103302e:	jmp    10330f9 <main+0x839>
 1033033:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033040:	xor    %esi,%esi
 1033042:	xor    %r10d,%r10d
 1033045:	jmp    103316b <main+0x8ab>
 103304a:	movabs $0xffffffffffffff8,%r10
 1033054:	and    %r10,%r9
 1033057:	vpxor  %xmm0,%xmm0,%xmm0
 103305b:	xor    %r10d,%r10d
 103305e:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 103306d:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 103307c:	nopl   0x0(%rax)
 1033080:	vpsadbw 0x20(%rax,%r10,1),%ymm5,%ymm1
 1033087:	vpaddq %ymm0,%ymm1,%ymm0
 103308b:	vpsadbw 0x40(%rax,%r10,1),%ymm5,%ymm1
 1033092:	vpsadbw 0x60(%rax,%r10,1),%ymm5,%ymm2
 1033099:	vpaddq %ymm1,%ymm2,%ymm1
 103309d:	vpaddq %ymm0,%ymm1,%ymm0
 10330a1:	vpsadbw 0x80(%rax,%r10,1),%ymm5,%ymm1
 10330ab:	vpsadbw 0xa0(%rax,%r10,1),%ymm5,%ymm2
 10330b5:	vpaddq %ymm1,%ymm2,%ymm1
 10330b9:	vpsadbw 0xc0(%rax,%r10,1),%ymm5,%ymm2
 10330c3:	vpaddq %ymm1,%ymm2,%ymm1
 10330c7:	vpaddq %ymm0,%ymm1,%ymm0
 10330cb:	vpsadbw 0xe0(%rax,%r10,1),%ymm5,%ymm1
 10330d5:	vpsadbw 0x100(%rax,%r10,1),%ymm5,%ymm2
 10330df:	vpaddq %ymm1,%ymm2,%ymm1
 10330e3:	vpaddq %ymm0,%ymm1,%ymm0
 10330e7:	add    $0x100,%r10
 10330ee:	add    $0xfffffffffffffff8,%r9
 10330f2:	jne    1033080 <main+0x7c0>
 10330f4:	test   %r8,%r8
 10330f7:	je     1033153 <main+0x893>
 10330f9:	lea    (%rax,%r10,1),%r9
 10330fd:	add    $0x20,%r9
 1033101:	shl    $0x5,%r8d
 1033105:	xor    %r10d,%r10d
 1033108:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033117:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033126:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033135:	data16 cs nopw 0x0(%rax,%rax,1)
 1033140:	vpsadbw (%r9,%r10,1),%ymm5,%ymm1
 1033146:	vpaddq %ymm0,%ymm1,%ymm0
 103314a:	add    $0x20,%r10
 103314e:	cmp    %r10,%r8
 1033151:	jne    1033140 <main+0x880>
 1033153:	vextracti128 $0x1,%ymm0,%xmm1
 1033159:	vpaddq %xmm1,%xmm0,%xmm0
 103315d:	vpshufd $0xee,%xmm0,%xmm1
 1033162:	vpaddq %xmm1,%xmm0,%xmm0
 1033166:	vmovq  %xmm0,%r10
 103316b:	lea    0x20(%rax),%r8
 103316f:	cmp    %rcx,%rsi
 1033172:	jae    1033290 <main+0x9d0>
 1033178:	mov    %rsi,%r9
 103317b:	not    %r9
 103317e:	add    %rdi,%r9
 1033181:	cmp    $0x4,%r9
 1033185:	jb     1033280 <main+0x9c0>
 103318b:	cmp    $0x10,%r9
 103318f:	jae    1033199 <main+0x8d9>
 1033191:	xor    %r11d,%r11d
 1033194:	jmp    1033227 <main+0x967>
 1033199:	mov    %r9,%r11
 103319c:	and    $0xfffffffffffffff0,%r11
 10331a0:	vmovq  %r10,%xmm0
 10331a5:	lea    (%rax,%rsi,1),%r10
 10331a9:	add    $0x2c,%r10
 10331ad:	vpxor  %xmm1,%xmm1,%xmm1
 10331b1:	xor    %r14d,%r14d
 10331b4:	vpxor  %xmm2,%xmm2,%xmm2
 10331b8:	vpxor  %xmm3,%xmm3,%xmm3
 10331bc:	nopl   0x0(%rax)
 10331c0:	vpmovzxbq -0xc(%r10,%r14,1),%ymm4
 10331c7:	vpaddq %ymm4,%ymm0,%ymm0
 10331cb:	vpmovzxbq -0x8(%r10,%r14,1),%ymm4
 10331d2:	vpaddq %ymm4,%ymm1,%ymm1
 10331d6:	vpmovzxbq -0x4(%r10,%r14,1),%ymm4
 10331dd:	vpaddq %ymm4,%ymm2,%ymm2
 10331e1:	vpmovzxbq (%r10,%r14,1),%ymm4
 10331e7:	vpaddq %ymm4,%ymm3,%ymm3
 10331eb:	add    $0x10,%r14
 10331ef:	cmp    %r14,%r11
 10331f2:	jne    10331c0 <main+0x900>
 10331f4:	vpaddq %ymm0,%ymm1,%ymm0
 10331f8:	vpaddq %ymm0,%ymm2,%ymm0
 10331fc:	vpaddq %ymm0,%ymm3,%ymm0
 1033200:	vextracti128 $0x1,%ymm0,%xmm1
 1033206:	vpaddq %xmm1,%xmm0,%xmm0
 103320a:	vpshufd $0xee,%xmm0,%xmm1
 103320f:	vpaddq %xmm1,%xmm0,%xmm0
 1033213:	vmovq  %xmm0,%r10
 1033218:	cmp    %r11,%r9
 103321b:	je     1033290 <main+0x9d0>
 103321d:	test   $0xc,%r9b
 1033221:	je     10336ce <main+0xe0e>
 1033227:	mov    %r9,%r14
 103322a:	and    $0xfffffffffffffffc,%r14
 103322e:	vmovq  %r10,%xmm0
 1033233:	lea    (%r8,%rsi,1),%r10
 1033237:	add    %r14,%rsi
 103323a:	nopw   0x0(%rax,%rax,1)
 1033240:	vpmovzxbq (%r10,%r11,1),%ymm1
 1033246:	vpaddq %ymm1,%ymm0,%ymm0
 103324a:	add    $0x4,%r11
 103324e:	cmp    %r11,%r14
 1033251:	jne    1033240 <main+0x980>
 1033253:	vextracti128 $0x1,%ymm0,%xmm1
 1033259:	vpaddq %xmm1,%xmm0,%xmm0
 103325d:	vpshufd $0xee,%xmm0,%xmm1
 1033262:	vpaddq %xmm1,%xmm0,%xmm0
 1033266:	vmovq  %xmm0,%r10
 103326b:	cmp    %r14,%r9
 103326e:	je     1033290 <main+0x9d0>
 1033270:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 103327f:	nop
 1033280:	movzbl (%r8,%rsi,1),%r9d
 1033285:	add    %r9,%r10
 1033288:	inc    %rsi
 103328b:	cmp    %rsi,%rcx
 103328e:	jne    1033280 <main+0x9c0>
 1033290:	cmp    %r10b,(%r8,%rcx,1)
 1033294:	jne    1033647 <main+0xd87>
 103329a:	movabs $0x7fffffffffffffe0,%rsi
 10332a4:	lea    (%rsi,%rdi,1),%r12
 10332a8:	add    $0x1a,%r12
 10332ac:	and    %rsi,%r12
 10332af:	je     10332e0 <main+0xa20>
 10332b1:	lea    -0x1(%r12),%r10
 10332b6:	shr    $0x5,%r10
 10332ba:	inc    %r10
 10332bd:	mov    %r10d,%esi
 10332c0:	and    $0x7,%esi
 10332c3:	cmp    $0xe1,%r12
 10332ca:	jae    1033300 <main+0xa40>
 10332cc:	vpxor  %xmm0,%xmm0,%xmm0
 10332d0:	xor    %r11d,%r11d
 10332d3:	jmp    10333b9 <main+0xaf9>
 10332d8:	nopl   0x0(%rax,%rax,1)
 10332e0:	mov    $0x5,%r10d
 10332e6:	xor    %esi,%esi
 10332e8:	cmp    %rcx,%r10
 10332eb:	jb     103343b <main+0xb7b>
 10332f1:	jmp    10335d0 <main+0xd10>
 10332f6:	cs nopw 0x0(%rax,%rax,1)
 1033300:	movabs $0xffffffffffffff8,%r9
 103330a:	and    %r9,%r10
 103330d:	vpxor  %xmm0,%xmm0,%xmm0
 1033311:	xor    %r11d,%r11d
 1033314:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033323:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033332:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033340:	vpsadbw 0x25(%rax,%r11,1),%ymm5,%ymm1
 1033347:	vpaddq %ymm0,%ymm1,%ymm0
 103334b:	vpsadbw 0x45(%rax,%r11,1),%ymm5,%ymm1
 1033352:	vpsadbw 0x65(%rax,%r11,1),%ymm5,%ymm2
 1033359:	vpaddq %ymm1,%ymm2,%ymm1
 103335d:	vpaddq %ymm0,%ymm1,%ymm0
 1033361:	vpsadbw 0x85(%rax,%r11,1),%ymm5,%ymm1
 103336b:	vpsadbw 0xa5(%rax,%r11,1),%ymm5,%ymm2
 1033375:	vpaddq %ymm1,%ymm2,%ymm1
 1033379:	vpsadbw 0xc5(%rax,%r11,1),%ymm5,%ymm2
 1033383:	vpaddq %ymm1,%ymm2,%ymm1
 1033387:	vpaddq %ymm0,%ymm1,%ymm0
 103338b:	vpsadbw 0xe5(%rax,%r11,1),%ymm5,%ymm1
 1033395:	vpsadbw 0x105(%rax,%r11,1),%ymm5,%ymm2
 103339f:	vpaddq %ymm1,%ymm2,%ymm1
 10333a3:	vpaddq %ymm0,%ymm1,%ymm0
 10333a7:	add    $0x100,%r11
 10333ae:	add    $0xfffffffffffffff8,%r10
 10333b2:	jne    1033340 <main+0xa80>
 10333b4:	test   %rsi,%rsi
 10333b7:	je     1033413 <main+0xb53>
 10333b9:	lea    (%rax,%r11,1),%r9
 10333bd:	add    $0x25,%r9
 10333c1:	shl    $0x5,%esi
 10333c4:	xor    %r10d,%r10d
 10333c7:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10333d6:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10333e5:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10333f4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033400:	vpsadbw (%r9,%r10,1),%ymm5,%ymm1
 1033406:	vpaddq %ymm0,%ymm1,%ymm0
 103340a:	add    $0x20,%r10
 103340e:	cmp    %r10,%rsi
 1033411:	jne    1033400 <main+0xb40>
 1033413:	mov    %r12,%r10
 1033416:	or     $0x5,%r10
 103341a:	vextracti128 $0x1,%ymm0,%xmm1
 1033420:	vpaddq %xmm1,%xmm0,%xmm0
 1033424:	vpshufd $0xee,%xmm0,%xmm1
 1033429:	vpaddq %xmm1,%xmm0,%xmm0
 103342d:	vmovq  %xmm0,%rsi
 1033432:	cmp    %rcx,%r10
 1033435:	jae    10335d0 <main+0xd10>
 103343b:	lea    -0x6(%rdi),%r14
 103343f:	mov    %r14,%r11
 1033442:	sub    %r12,%r11
 1033445:	cmp    $0x4,%r11
 1033449:	jb     10335c0 <main+0xd00>
 103344f:	cmp    $0x10,%r11
 1033453:	jae    103345d <main+0xb9d>
 1033455:	xor    %r15d,%r15d
 1033458:	jmp    1033530 <main+0xc70>
 103345d:	mov    %r14d,%ebp
 1033460:	and    $0xf,%ebp
 1033463:	mov    %r11,%r15
 1033466:	sub    %rbp,%r15
 1033469:	vmovq  %rsi,%xmm0
 103346e:	mov    %rdi,%rsi
 1033471:	sub    %rbp,%rsi
 1033474:	add    $0xfffffffffffffffa,%rsi
 1033478:	vpxor  %xmm1,%xmm1,%xmm1
 103347c:	mov    %r12,%r9
 103347f:	vpxor  %xmm2,%xmm2,%xmm2
 1033483:	vpxor  %xmm3,%xmm3,%xmm3
 1033487:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033496:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10334a5:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10334b4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10334c0:	vpmovzxbq 0x25(%rax,%r9,1),%ymm4
 10334c7:	vpaddq %ymm4,%ymm0,%ymm0
 10334cb:	vpmovzxbq 0x29(%rax,%r9,1),%ymm4
 10334d2:	vpaddq %ymm4,%ymm1,%ymm1
 10334d6:	vpmovzxbq 0x2d(%rax,%r9,1),%ymm4
 10334dd:	vpaddq %ymm4,%ymm2,%ymm2
 10334e1:	vpmovzxbq 0x31(%rax,%r9,1),%ymm4
 10334e8:	vpaddq %ymm4,%ymm3,%ymm3
 10334ec:	add    $0x10,%r9
 10334f0:	cmp    %r9,%rsi
 10334f3:	jne    10334c0 <main+0xc00>
 10334f5:	vpaddq %ymm0,%ymm1,%ymm0
 10334f9:	vpaddq %ymm0,%ymm2,%ymm0
 10334fd:	vpaddq %ymm0,%ymm3,%ymm0
 1033501:	vextracti128 $0x1,%ymm0,%xmm1
 1033507:	vpaddq %xmm1,%xmm0,%xmm0
 103350b:	vpshufd $0xee,%xmm0,%xmm1
 1033510:	vpaddq %xmm1,%xmm0,%xmm0
 1033514:	vmovq  %xmm0,%rsi
 1033519:	test   %rbp,%rbp
 103351c:	je     10336ad <main+0xded>
 1033522:	cmp    $0x4,%ebp
 1033525:	jb     10336bc <main+0xdfc>
 103352b:	mov    0x10(%rsp),%rbp
 1033530:	and    $0x3,%r14d
 1033534:	sub    %r14,%r11
 1033537:	add    %r11,%r10
 103353a:	vmovq  %rsi,%xmm0
 103353f:	add    %r12,%r15
 1033542:	sub    %r14,%rdi
 1033545:	add    $0xfffffffffffffffa,%rdi
 1033549:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033558:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033567:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033576:	cs nopw 0x0(%rax,%rax,1)
 1033580:	vpmovzxbq 0x25(%rax,%r15,1),%ymm1
 1033587:	vpaddq %ymm1,%ymm0,%ymm0
 103358b:	add    $0x4,%r15
 103358f:	cmp    %r15,%rdi
 1033592:	jne    1033580 <main+0xcc0>
 1033594:	vextracti128 $0x1,%ymm0,%xmm1
 103359a:	vpaddq %xmm1,%xmm0,%xmm0
 103359e:	vpshufd $0xee,%xmm0,%xmm1
 10335a3:	vpaddq %xmm1,%xmm0,%xmm0
 10335a7:	vmovq  %xmm0,%rsi
 10335ac:	test   %r14,%r14
 10335af:	mov    0x8(%rsp),%r15
 10335b4:	je     10335d0 <main+0xd10>
 10335b6:	cs nopw 0x0(%rax,%rax,1)
 10335c0:	movzbl (%r8,%r10,1),%edi
 10335c5:	add    %rdi,%rsi
 10335c8:	inc    %r10
 10335cb:	cmp    %rcx,%r10
 10335ce:	jl     10335c0 <main+0xd00>
 10335d0:	movbe  0x22(%rax),%ax
 10335d6:	movzwl %ax,%eax
 10335d9:	xor    %ecx,%ecx
 10335db:	test   %cl,%cl
 10335dd:	je     103366e <main+0xdae>
 10335e3:	imul   $0x65,%rax,%rcx
 10335e7:	jno    1033690 <main+0xdd0>
 10335ed:	jmp    1033879 <main+0xfb9>
 10335f2:	mov    $0x3b,%edi
 10335f7:	jmp    1033632 <main+0xd72>
 10335f9:	mov    $0x3d,%edi
 10335fe:	xor    %esi,%esi
 1033600:	vzeroupper
 1033603:	call   103247c <myl_core_err_trace>
 1033608:	vpxor  %xmm5,%xmm5,%xmm5
 103360c:	mov    $0x1,%eax
 1033611:	jmp    1033660 <main+0xda0>
 1033613:	mov    $0x3f,%edi
 1033618:	xor    %esi,%esi
 103361a:	vzeroupper
 103361d:	call   103247c <myl_core_err_trace>
 1033622:	vpxor  %xmm5,%xmm5,%xmm5
 1033626:	mov    $0x2,%eax
 103362b:	jmp    1033660 <main+0xda0>
 103362d:	mov    $0x41,%edi
 1033632:	xor    %esi,%esi
 1033634:	vzeroupper
 1033637:	call   103247c <myl_core_err_trace>
 103363c:	vpxor  %xmm5,%xmm5,%xmm5
 1033640:	mov    $0x3,%eax
 1033645:	jmp    1033660 <main+0xda0>
 1033647:	mov    $0x43,%edi
 103364c:	xor    %esi,%esi
 103364e:	vzeroupper
 1033651:	call   103247c <myl_core_err_trace>
 1033656:	vpxor  %xmm5,%xmm5,%xmm5
 103365a:	mov    $0x4,%eax
 103365f:	nop
 1033660:	mov    $0x1,%cl
 1033662:	xor    %esi,%esi
 1033664:	xor    %edx,%edx
 1033666:	test   %cl,%cl
 1033668:	jne    10335e3 <main+0xd23>
 103366e:	imul   $0x3,%rsi,%rcx
 1033672:	jo     10338b7 <main+0xff7>
 1033678:	mov    %rax,%rsi
 103367b:	add    %rcx,%rsi
 103367e:	jo     10338c9 <main+0x1009>
 1033684:	mov    %rsi,%rcx
 1033687:	add    %rdx,%rcx
 103368a:	jo     10338dc <main+0x101c>
 1033690:	mov    %rbx,%rdx
 1033693:	add    %rcx,%rdx
 1033696:	jo     1033866 <main+0xfa6>
 103369c:	inc    %r13
 103369f:	mov    %rdx,%rbx
 10336a2:	cmp    %rbp,%r13
 10336a5:	jne    1032fc0 <main+0x700>
 10336ab:	jmp    10336e0 <main+0xe20>
 10336ad:	mov    0x10(%rsp),%rbp
 10336b2:	mov    0x8(%rsp),%r15
 10336b7:	jmp    10335d0 <main+0xd10>
 10336bc:	add    %r15,%r10
 10336bf:	mov    0x10(%rsp),%rbp
 10336c4:	mov    0x8(%rsp),%r15
 10336c9:	jmp    10335c0 <main+0xd00>
 10336ce:	add    %r11,%rsi
 10336d1:	jmp    1033280 <main+0x9c0>
 10336d6:	cs nopw 0x0(%rax,%rax,1)
 10336e0:	mov    %rdx,%rcx
 10336e3:	mov    (%rsp),%rsi
 10336e7:	add    %rsi,%rcx
 10336ea:	mov    0x20(%rsp),%rdi
 10336ef:	jo     1033959 <main+0x1099>
 10336f5:	mov    %rcx,%rax
 10336f8:	movabs $0x89705f3112a28fe5,%rdx
 1033702:	imul   %rdx
 1033705:	add    %rcx,%rdx
 1033708:	mov    %rdx,%rax
 103370b:	shr    $0x3f,%rax
 103370f:	sar    $0x1d,%rdx
 1033713:	add    %rax,%rdx
 1033716:	imul   $0x3b9aca07,%rdx,%rax
 103371d:	sub    %rax,%rcx
 1033720:	mov    %rcx,%r13
 1033723:	sar    $0x3f,%r13
 1033727:	and    $0x3b9aca07,%r13d
 103372e:	add    %rcx,%r13
 1033731:	inc    %rdi
 1033734:	cmp    0x40(%rsp),%rdi
 1033739:	jne    1032fb0 <main+0x6f0>
 103373f:	mov    0x18(%rsp),%rdi
 1033744:	movzbl 0x7(%rdi),%eax
 1033748:	test   %rax,%rax
 103374b:	je     103388e <main+0xfce>
 1033751:	cmpq   $0x0,0x18(%rdi)
 1033756:	jne    103388e <main+0xfce>
 103375c:	lea    0x25f6d(%rip),%rdx        # 10596d0 <myl_core_free_lists>
 1033763:	mov    (%rdx,%rax,8),%rcx
 1033767:	mov    %rcx,(%rdi)
 103376a:	mov    %rdi,(%rdx,%rax,8)
 103376e:	mov    0x30(%rsp),%r14
 1033773:	mov    0x28(%rsp),%r12
 1033778:	movzbl 0x7(%r15),%eax
 103377d:	test   %rax,%rax
 1033780:	mov    0x38(%rsp),%rbx
 1033785:	je     10338a7 <main+0xfe7>
 103378b:	cmpq   $0x0,0x18(%r15)
 1033790:	jne    10338a7 <main+0xfe7>
 1033796:	mov    (%rdx,%rax,8),%rcx
 103379a:	mov    %rcx,(%r15)
 103379d:	mov    %r15,(%rdx,%rax,8)
 10337a1:	mov    $0x1c,%edi
 10337a6:	vzeroupper
 10337a9:	call   100a500 <myl_core_io_at>
 10337ae:	mov    %rbx,%rdi
 10337b1:	call   1022530 <myl_core_host_check>
 10337b6:	call   10339c0 <runtime_bench_now>
 10337bb:	mov    %rax,%rbx
 10337be:	sub    %r12,%rbx
 10337c1:	jo     10339a8 <main+0x10e8>
 10337c7:	mov    $0x1,%edi
 10337cc:	mov    %r13,%rsi
 10337cf:	call   100ac00 <myl_core_print_i64>
 10337d4:	mov    $0x1,%edi
 10337d9:	call   1009400 <myl_core_print_sep>
 10337de:	mov    $0x1,%edi
 10337e3:	mov    %rbx,%rsi
 10337e6:	call   100ac00 <myl_core_print_i64>
 10337eb:	mov    $0x1,%edi
 10337f0:	call   10094c0 <myl_core_print_end>
 10337f5:	xor    %ebx,%ebx
 10337f7:	mov    %r14,%rdi
 10337fa:	call   1009bc0 <myl_core_release>
 10337ff:	mov    %rbx,%rdi
 1033802:	add    $0x48,%rsp
 1033806:	pop    %rbx
 1033807:	pop    %r12
 1033809:	pop    %r13
 103380b:	pop    %r14
 103380d:	pop    %r15
 103380f:	pop    %rbp
 1033810:	jmp    100a510 <myl_core_exit>
 1033815:	mov    %rsi,%rbx
 1033818:	mov    $0x8,%esi
 103381d:	mov    %rbp,%rdi
 1033820:	mov    %r9,%r14
 1033823:	mov    %r10d,%r15d
 1033826:	call   1009680 <myl_core_list_new_slow>
 103382b:	mov    %r15d,%r10d
 103382e:	mov    %r14,%r9
 1033831:	mov    %rbx,%rsi
 1033834:	mov    (%rsp),%r8
 1033838:	mov    %rax,%rdi
 103383b:	jmp    10329e2 <main+0x122>
 1033840:	mov    $0x8,%esi
 1033845:	mov    %rbp,%rdi
 1033848:	call   1009680 <myl_core_list_new_slow>
 103384d:	mov    (%rsp),%r8
 1033851:	mov    %rax,%r15
 1033854:	jmp    1032b24 <main+0x264>
 1033859:	mov    $0x3a,%edi
 103385e:	vzeroupper
 1033861:	call   1009d80 <myl_core_trap>
 1033866:	mov    $0x23,%edi
 103386b:	mov    %rbx,%rsi
 103386e:	mov    %rcx,%rdx
 1033871:	vzeroupper
 1033874:	call   1009d80 <myl_core_trap>
 1033879:	mov    $0x65,%edx
 103387e:	mov    $0x27,%edi
 1033883:	mov    %rax,%rsi
 1033886:	vzeroupper
 1033889:	call   1009d80 <myl_core_trap>
 103388e:	vzeroupper
 1033891:	call   10320d0 <myl_core_free_block>
 1033896:	mov    0x30(%rsp),%r14
 103389b:	lea    0x25e2e(%rip),%rdx        # 10596d0 <myl_core_free_lists>
 10338a2:	jmp    1033773 <main+0xeb3>
 10338a7:	mov    %r15,%rdi
 10338aa:	vzeroupper
 10338ad:	call   10320d0 <myl_core_free_block>
 10338b2:	jmp    10337a1 <main+0xee1>
 10338b7:	mov    $0x3,%edx
 10338bc:	mov    $0x24,%edi
 10338c1:	vzeroupper
 10338c4:	call   1009d80 <myl_core_trap>
 10338c9:	mov    $0x25,%edi
 10338ce:	mov    %rax,%rsi
 10338d1:	mov    %rcx,%rdx
 10338d4:	vzeroupper
 10338d7:	call   1009d80 <myl_core_trap>
 10338dc:	mov    $0x26,%edi
 10338e1:	vzeroupper
 10338e4:	call   1009d80 <myl_core_trap>
 10338e9:	mov    $0x25,%edx
 10338ee:	mov    $0x11,%edi
 10338f3:	mov    %rbx,%rsi
 10338f6:	call   1009d80 <myl_core_trap>
 10338fb:	mov    $0x12,%edi
 1033900:	mov    %r8,%rsi
 1033903:	mov    %r14,%rdx
 1033906:	call   1009d80 <myl_core_trap>
 103390b:	mov    $0x28,%edi
 1033910:	mov    %r8,%rsi
 1033913:	call   1009d80 <myl_core_trap>
 1033918:	mov    $0x29,%edi
 103391d:	mov    %r8,%rsi
 1033920:	vzeroupper
 1033923:	call   1009d80 <myl_core_trap>
 1033928:	mov    $0x7,%edx
 103392d:	jmp    103393b <main+0x107b>
 103392f:	mov    $0xe,%edx
 1033934:	jmp    103393b <main+0x107b>
 1033936:	mov    $0x15,%edx
 103393b:	mov    $0x2a,%edi
 1033940:	mov    %rbx,%rsi
 1033943:	vzeroupper
 1033946:	call   1009d80 <myl_core_trap>
 103394b:	mov    $0x38,%edi
 1033950:	xor    %esi,%esi
 1033952:	xor    %edx,%edx
 1033954:	call   1009d80 <myl_core_trap>
 1033959:	mov    $0x1e,%edi
 103395e:	vzeroupper
 1033961:	call   1009d80 <myl_core_trap>
 1033966:	mov    $0x4,%esi
 103396b:	mov    $0x37,%edi
 1033970:	vzeroupper
 1033973:	call   1009d80 <myl_core_trap>
 1033978:	mov    $0x9,%esi
 103397d:	mov    $0x31,%edi
 1033982:	vzeroupper
 1033985:	call   1009d80 <myl_core_trap>
 103398a:	mov    $0x1,%esi
 103398f:	mov    $0x5,%edi
 1033994:	call   1009d80 <myl_core_trap>
 1033999:	mov    $0x2,%esi
 103399e:	mov    $0x8,%edi
 10339a3:	call   1009d80 <myl_core_trap>
 10339a8:	mov    $0x1d,%edi
 10339ad:	mov    %rax,%rsi
 10339b0:	mov    %r12,%rdx
 10339b3:	call   1009d80 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
