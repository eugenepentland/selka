
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-applications/.mylang-cache/s3-a/all40-combined-final-01/row_word_count_new:     file format elf64-x86-64


Disassembly of section .text:

0000000001032900 <main>:
 1032900:	push   %rbp
 1032901:	push   %r15
 1032903:	push   %r14
 1032905:	push   %r13
 1032907:	push   %r12
 1032909:	push   %rbx
 103290a:	sub    $0xd8,%rsp
 1032911:	call   1009a30 <myl_core_args>
 1032916:	mov    %rax,%rbx
 1032919:	call   1022440 <myl_core_host_grant>
 103291e:	mov    %rbx,%rdi
 1032921:	mov    $0x2,%ebx
 1032926:	cmpq   $0x3,0x8(%rdi)
 103292b:	jne    10329ba <main+0xba>
 1032931:	mov    %rax,0x40(%rsp)
 1032936:	mov    %rdi,0x8(%rsp)
 103293b:	mov    0x8(%rsp),%rax
 1032940:	mov    0x20(%rax),%rdi
 1032944:	call   1032700 <my.row_word_count::number>
 1032949:	mov    %rax,%r14
 103294c:	mov    0x8(%rsp),%rax
 1032951:	mov    0x8(%rax),%rdx
 1032955:	cmp    $0x1,%rdx
 1032959:	jbe    10335bb <main+0xcbb>
 103295f:	mov    0x8(%rsp),%rax
 1032964:	mov    0x28(%rax),%rdi
 1032968:	call   1032700 <my.row_word_count::number>
 103296d:	mov    %rax,%r15
 1032970:	mov    0x8(%rsp),%rax
 1032975:	mov    0x8(%rax),%rdx
 1032979:	cmp    $0x2,%rdx
 103297d:	jbe    10335ca <main+0xcca>
 1032983:	mov    0x8(%rsp),%rax
 1032988:	mov    0x30(%rax),%rdi
 103298c:	call   1032700 <my.row_word_count::number>
 1032991:	mov    0x8(%rsp),%rdi
 1032996:	cmp    $0x2,%r14
 103299a:	setl   %dl
 103299d:	test   %r15,%r15
 10329a0:	setle  %cl
 10329a3:	or     %dl,%cl
 10329a5:	lea    -0xf4241(%rax),%rdx
 10329ac:	cmp    $0xfffffffffff0bdc0,%rdx
 10329b3:	setb   %dl
 10329b6:	or     %cl,%dl
 10329b8:	je     10329d9 <main+0xd9>
 10329ba:	call   1009a00 <myl_core_release>
 10329bf:	mov    %rbx,%rdi
 10329c2:	call   100a510 <myl_core_exit>
 10329c7:	add    $0xd8,%rsp
 10329ce:	pop    %rbx
 10329cf:	pop    %r12
 10329d1:	pop    %r13
 10329d3:	pop    %r14
 10329d5:	pop    %r15
 10329d7:	pop    %rbp
 10329d8:	ret
 10329d9:	mov    %r15,0x88(%rsp)
 10329e1:	lea    0xb0(%rsp),%rdi
 10329e9:	mov    %r14,%rsi
 10329ec:	mov    %rax,0x48(%rsp)
 10329f1:	mov    %rax,%rdx
 10329f4:	call   1033600 <my.row_word_count::inputs>
 10329f9:	mov    $0x9,%edi
 10329fe:	call   100a500 <myl_core_io_at>
 1032a03:	mov    0x40(%rsp),%rdi
 1032a08:	call   1022470 <myl_core_host_check>
 1032a0d:	call   1033e90 <runtime_bench_now>
 1032a12:	mov    %rax,0x78(%rsp)
 1032a17:	xor    %r14d,%r14d
 1032a1a:	mov    0xb8(%rsp),%rax
 1032a22:	xor    %edx,%edx
 1032a24:	mov    %rax,0x80(%rsp)
 1032a2c:	nopl   0x0(%rax)
 1032a30:	mov    0x48(%rsp),%rsi
 1032a35:	add    %rdx,%rsi
 1032a38:	jo     103359f <main+0xc9f>
 1032a3e:	mov    %rdx,0x90(%rsp)
 1032a46:	mov    %r14,0x98(%rsp)
 1032a4e:	and    $0x1,%esi
 1032a51:	mov    0x8(%rax),%rdx
 1032a55:	cmp    %rdx,%rsi
 1032a58:	jae    1033595 <main+0xc95>
 1032a5e:	mov    0x20(%rax,%rsi,8),%rbx
 1032a63:	xor    %edi,%edi
 1032a65:	lea    0x2e74(%rip),%rsi        # 10358e0 <myl_core_sites+0x500>
 1032a6c:	call   100f870 <myl_core_dict_new>
 1032a71:	mov    %rax,%r14
 1032a74:	mov    %rbx,%rdi
 1032a77:	xor    %esi,%esi
 1032a79:	call   1013be0 <myl_core_split_ws_start>
 1032a7e:	mov    %rax,%r15
 1032a81:	mov    0x8(%rbx),%rax
 1032a85:	mov    %rax,0x20(%rsp)
 1032a8a:	cmp    %rax,%r15
 1032a8d:	jge    1032df0 <main+0x4f0>
 1032a93:	lea    0x20(%rbx),%rax
 1032a97:	mov    %rax,0x60(%rsp)
 1032a9c:	mov    %rbx,0x18(%rsp)
 1032aa1:	jmp    1032b2a <main+0x22a>
 1032aa6:	cs nopw 0x0(%rax,%rax,1)
 1032ab0:	cmpq   $0x0,0x18(%rcx)
 1032ab5:	je     1032d65 <main+0x465>
 1032abb:	mov    (%rsp),%rdi
 1032abf:	lea    0x38(%rsp),%rsi
 1032ac4:	mov    %rbp,%rdx
 1032ac7:	call   100f500 <myl_core_dict_find>
 1032acc:	mov    %rax,%r12
 1032acf:	mov    0x10(%rsp),%rax
 1032ad4:	mov    %rax,0xa8(%rsp)
 1032adc:	movq   $0x1,0xa0(%rsp)
 1032ae8:	mov    (%rsp),%rdi
 1032aec:	mov    %r12,%rsi
 1032aef:	lea    0xa8(%rsp),%rdx
 1032af7:	lea    0xa0(%rsp),%rcx
 1032aff:	xor    %r8d,%r8d
 1032b02:	call   100fa60 <myl_core_dict_insert>
 1032b07:	mov    %rax,%r14
 1032b0a:	mov    0x18(%rsp),%rbx
 1032b0f:	mov    %rbx,%rdi
 1032b12:	mov    0x28(%rsp),%rsi
 1032b17:	call   1013be0 <myl_core_split_ws_start>
 1032b1c:	mov    %rax,%r15
 1032b1f:	cmp    0x20(%rsp),%rax
 1032b24:	jge    1032df0 <main+0x4f0>
 1032b2a:	mov    %rbx,%rdi
 1032b2d:	mov    %r15,%rsi
 1032b30:	call   1013c30 <myl_core_split_ws_end>
 1032b35:	test   %r15,%r15
 1032b38:	js     1033526 <main+0xc26>
 1032b3e:	mov    %rax,%rbp
 1032b41:	sub    %r15,%rbp
 1032b44:	jo     1033535 <main+0xc35>
 1032b4a:	js     1033545 <main+0xc45>
 1032b50:	mov    %rax,0x28(%rsp)
 1032b55:	add    0x60(%rsp),%r15
 1032b5a:	mov    0x18(%r14),%rbx
 1032b5e:	mov    0x8(%rbx),%rax
 1032b62:	or     0x18(%rbx),%rax
 1032b66:	mov    %r14,(%rsp)
 1032b6a:	mov    %r15,0x10(%rsp)
 1032b6f:	jne    1032c30 <main+0x330>
 1032b75:	mov    %r15,%rdi
 1032b78:	mov    %rbp,%rsi
 1032b7b:	call   1010b60 <myl_core_span_hash>
 1032b80:	mov    0x20(%rbx),%r14
 1032b84:	test   %r14,%r14
 1032b87:	je     1032c46 <main+0x346>
 1032b8d:	mov    %eax,%eax
 1032b8f:	movabs $0x9e3779b97f4a7c15,%rcx
 1032b99:	imul   %rcx,%rax
 1032b9d:	mov    %rax,%r15
 1032ba0:	shr    $0x20,%r15
 1032ba4:	xor    %rax,%r15
 1032ba7:	mov    0x10(%rbx),%rbx
 1032bab:	mov    (%rsp),%rax
 1032baf:	lea    0x20(%rax),%r13
 1032bb3:	xor    %r12d,%r12d
 1032bb6:	jmp    1032bcc <main+0x2cc>
 1032bb8:	nopl   0x0(%rax,%rax,1)
 1032bc0:	inc    %r12
 1032bc3:	add    $0x10,%r13
 1032bc7:	cmp    %r12,%r14
 1032bca:	je     1032c46 <main+0x346>
 1032bcc:	cmp    %r15,(%rbx,%r12,8)
 1032bd0:	jne    1032bc0 <main+0x2c0>
 1032bd2:	mov    0x0(%r13),%rdi
 1032bd6:	cmp    %rbp,0x8(%rdi)
 1032bda:	jne    1032bc0 <main+0x2c0>
 1032bdc:	add    $0x20,%rdi
 1032be0:	mov    0x10(%rsp),%rsi
 1032be5:	mov    %rbp,%rdx
 1032be8:	call   1033fd0 <bcmp@plt>
 1032bed:	test   %eax,%eax
 1032bef:	jne    1032bc0 <main+0x2c0>
 1032bf1:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032c00:	test   %r12,%r12
 1032c03:	js     1032c46 <main+0x346>
 1032c05:	shl    $0x4,%r12
 1032c09:	mov    (%rsp),%r14
 1032c0d:	mov    0x28(%r14,%r12,1),%rsi
 1032c12:	mov    %rsi,%rax
 1032c15:	inc    %rax
 1032c18:	jo     1033554 <main+0xc54>
 1032c1e:	mov    %rax,0x28(%r14,%r12,1)
 1032c23:	jmp    1032b0a <main+0x20a>
 1032c28:	nopl   0x0(%rax,%rax,1)
 1032c30:	mov    %r14,%rdi
 1032c33:	mov    %r15,%rsi
 1032c36:	mov    %rbp,%rdx
 1032c39:	call   10107c0 <myl_core_dict_find_span>
 1032c3e:	mov    %rax,%r12
 1032c41:	test   %r12,%r12
 1032c44:	jns    1032c05 <main+0x305>
 1032c46:	mov    0x10(%rsp),%rdi
 1032c4b:	mov    %rbp,%rsi
 1032c4e:	call   1011470 <myl_core_ir_str_from_view>
 1032c53:	mov    %rax,0x38(%rsp)
 1032c58:	testb  $0x2,0x5(%rax)
 1032c5c:	mov    %rax,0x10(%rsp)
 1032c61:	jne    1032c70 <main+0x370>
 1032c63:	mov    %rax,%rdi
 1032c66:	call   1010c70 <myl_core_str_hash>
 1032c6b:	jmp    1032c73 <main+0x373>
 1032c6d:	nopl   (%rax)
 1032c70:	mov    0x18(%rax),%eax
 1032c73:	mov    (%rsp),%rdx
 1032c77:	mov    %eax,%eax
 1032c79:	movabs $0x9e3779b97f4a7c15,%rcx
 1032c83:	imul   %rcx,%rax
 1032c87:	mov    %rax,%rbp
 1032c8a:	shr    $0x20,%rbp
 1032c8e:	xor    %rax,%rbp
 1032c91:	mov    0x18(%rdx),%rcx
 1032c95:	mov    0x8(%rcx),%rax
 1032c99:	test   %rax,%rax
 1032c9c:	je     1032ab0 <main+0x1b0>
 1032ca2:	mov    (%rax),%ecx
 1032ca4:	tzcnt  %ecx,%edx
 1032ca8:	neg    %dl
 1032caa:	shrx   %rdx,%rbp,%r14
 1032caf:	lea    -0x1(%rcx),%r15d
 1032cb3:	vmovdqu 0x10(%rax,%r14,1),%xmm1
 1032cba:	mov    %ebp,%edx
 1032cbc:	and    $0x7f,%dl
 1032cbf:	vmovd  %edx,%xmm0
 1032cc3:	vpbroadcastb %xmm0,%xmm0
 1032cc8:	vmovdqa %xmm1,0x50(%rsp)
 1032cce:	vpcmpeqb %xmm0,%xmm1,%xmm0
 1032cd2:	vpmovmskb %xmm0,%edx
 1032cd6:	test   %edx,%edx
 1032cd8:	je     1032d38 <main+0x438>
 1032cda:	add    $0x1e,%ecx
 1032cdd:	and    $0xfffffff0,%ecx
 1032ce0:	lea    (%rax,%rcx,1),%rbx
 1032ce4:	add    $0x10,%rbx
 1032ce8:	movzwl %dx,%r13d
 1032cec:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cfb:	nopl   0x0(%rax,%rax,1)
 1032d00:	tzcnt  %r13d,%eax
 1032d05:	add    %r14d,%eax
 1032d08:	and    %r15d,%eax
 1032d0b:	mov    (%rbx,%rax,4),%r12d
 1032d0f:	mov    %r12,%rax
 1032d12:	shl    $0x4,%rax
 1032d16:	mov    (%rsp),%rcx
 1032d1a:	mov    0x20(%rcx,%rax,1),%rdi
 1032d1f:	mov    0x38(%rsp),%rsi
 1032d24:	call   1010dd0 <myl_core_str_eq>
 1032d29:	test   %al,%al
 1032d2b:	jne    1032acf <main+0x1cf>
 1032d31:	blsr   %r13d,%r13d
 1032d36:	jne    1032d00 <main+0x400>
 1032d38:	vmovdqa 0x50(%rsp),%xmm0
 1032d3e:	vpcmpeqb -0x2f526(%rip),%xmm0,%xmm0        # 1003820 <core_io_raw_layout+0x2a0>
 1032d46:	vpmovmskb %xmm0,%eax
 1032d4a:	test   %eax,%eax
 1032d4c:	je     1032abb <main+0x1bb>
 1032d52:	tzcnt  %eax,%r12d
 1032d57:	add    %r14d,%r12d
 1032d5a:	and    %r15d,%r12d
 1032d5d:	not    %r12
 1032d60:	jmp    1032acf <main+0x1cf>
 1032d65:	mov    0x20(%rcx),%rbx
 1032d69:	mov    $0xffffffffffffffff,%r12
 1032d70:	test   %rbx,%rbx
 1032d73:	je     1032acf <main+0x1cf>
 1032d79:	mov    0x10(%rcx),%r14
 1032d7d:	mov    (%rsp),%rax
 1032d81:	lea    0x20(%rax),%r15
 1032d85:	xor    %r13d,%r13d
 1032d88:	jmp    1032dd0 <main+0x4d0>
 1032d8a:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032d99:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032da8:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032db7:	nopw   0x0(%rax,%rax,1)
 1032dc0:	inc    %r13
 1032dc3:	add    $0x10,%r15
 1032dc7:	cmp    %r13,%rbx
 1032dca:	je     1032acf <main+0x1cf>
 1032dd0:	cmp    %rbp,(%r14,%r13,8)
 1032dd4:	jne    1032dc0 <main+0x4c0>
 1032dd6:	mov    (%r15),%rdi
 1032dd9:	mov    0x38(%rsp),%rsi
 1032dde:	call   1010dd0 <myl_core_str_eq>
 1032de3:	test   %al,%al
 1032de5:	je     1032dc0 <main+0x4c0>
 1032de7:	mov    %r13,%r12
 1032dea:	jmp    1032acf <main+0x1cf>
 1032def:	nop
 1032df0:	mov    0x8(%r14),%rax
 1032df4:	mov    %rax,0x18(%rsp)
 1032df9:	test   %rax,%rax
 1032dfc:	je     1033280 <main+0x980>
 1032e02:	lea    0x20(%r14),%rax
 1032e06:	mov    %rax,0x50(%rsp)
 1032e0b:	xor    %eax,%eax
 1032e0d:	xor    %esi,%esi
 1032e0f:	mov    %r14,(%rsp)
 1032e13:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032e20:	mov    %rax,0x28(%rsp)
 1032e25:	mov    %r14,%rdi
 1032e28:	mov    %rsi,0x20(%rsp)
 1032e2d:	call   10103b0 <myl_core_dict_ordinal>
 1032e32:	shl    $0x4,%rax
 1032e36:	mov    0x20(%r14,%rax,1),%rdi
 1032e3b:	mov    0x8(%rdi),%rax
 1032e3f:	mov    %rax,%rcx
 1032e42:	sar    $0x3f,%rcx
 1032e46:	andn   %rax,%rcx,%rcx
 1032e4b:	mov    %rax,%r13
 1032e4e:	movabs $0x7fffffffffffffe0,%rdx
 1032e58:	and    %rdx,%rcx
 1032e5b:	movabs $0x10000000000,%r9
 1032e65:	vpxor  %xmm2,%xmm2,%xmm2
 1032e69:	je     1032ef8 <main+0x5f8>
 1032e6f:	xor    %edx,%edx
 1032e71:	mov    %rax,%r13
 1032e74:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032e80:	mov    %rdx,%r8
 1032e83:	lea    (%rdx,%r9,1),%rsi
 1032e87:	cmp    %rcx,%rsi
 1032e8a:	mov    %rcx,%rdx
 1032e8d:	cmovb  %rsi,%rdx
 1032e91:	vpxor  %xmm0,%xmm0,%xmm0
 1032e95:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032ea4:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032eb3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032ec0:	vpsadbw 0x20(%rdi,%r8,1),%ymm2,%ymm1
 1032ec7:	vpaddq %ymm0,%ymm1,%ymm0
 1032ecb:	add    $0x20,%r8
 1032ecf:	cmp    %rdx,%r8
 1032ed2:	jb     1032ec0 <main+0x5c0>
 1032ed4:	vextracti128 $0x1,%ymm0,%xmm1
 1032eda:	vpaddq %xmm1,%xmm0,%xmm0
 1032ede:	vpshufd $0xee,%xmm0,%xmm1
 1032ee3:	vpaddq %xmm1,%xmm0,%xmm0
 1032ee7:	vmovq  %xmm0,%r8
 1032eec:	add    %r8,%r13
 1032eef:	cmp    %rcx,%rsi
 1032ef2:	jb     1032e80 <main+0x580>
 1032ef8:	mov    %rax,%rdx
 1032efb:	sub    %rcx,%rdx
 1032efe:	jbe    1033090 <main+0x790>
 1032f04:	cmp    $0x4,%rdx
 1032f08:	jae    1032f20 <main+0x620>
 1032f0a:	mov    %rcx,%rdx
 1032f0d:	jmp    1033080 <main+0x780>
 1032f12:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032f20:	cmp    $0x10,%rdx
 1032f24:	jae    1032f2d <main+0x62d>
 1032f26:	xor    %esi,%esi
 1032f28:	jmp    1032fec <main+0x6ec>
 1032f2d:	mov    %eax,%r8d
 1032f30:	and    $0xf,%r8d
 1032f34:	mov    %rdx,%rsi
 1032f37:	sub    %r8,%rsi
 1032f3a:	vmovq  %r13,%xmm0
 1032f3f:	mov    %rax,%r9
 1032f42:	and    $0xfffffffffffffff0,%r9
 1032f46:	vpxor  %xmm1,%xmm1,%xmm1
 1032f4a:	mov    %rcx,%r10
 1032f4d:	vpxor  %xmm2,%xmm2,%xmm2
 1032f51:	vpxor  %xmm3,%xmm3,%xmm3
 1032f55:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032f64:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032f73:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032f80:	vpmovzxbq 0x20(%rdi,%r10,1),%ymm4
 1032f87:	vpaddq %ymm4,%ymm0,%ymm0
 1032f8b:	vpmovzxbq 0x24(%rdi,%r10,1),%ymm4
 1032f92:	vpaddq %ymm4,%ymm1,%ymm1
 1032f96:	vpmovzxbq 0x28(%rdi,%r10,1),%ymm4
 1032f9d:	vpaddq %ymm4,%ymm2,%ymm2
 1032fa1:	vpmovzxbq 0x2c(%rdi,%r10,1),%ymm4
 1032fa8:	vpaddq %ymm4,%ymm3,%ymm3
 1032fac:	add    $0x10,%r10
 1032fb0:	cmp    %r10,%r9
 1032fb3:	jne    1032f80 <main+0x680>
 1032fb5:	vpaddq %ymm0,%ymm1,%ymm0
 1032fb9:	vpaddq %ymm0,%ymm2,%ymm0
 1032fbd:	vpaddq %ymm0,%ymm3,%ymm0
 1032fc1:	vextracti128 $0x1,%ymm0,%xmm1
 1032fc7:	vpaddq %xmm1,%xmm0,%xmm0
 1032fcb:	vpshufd $0xee,%xmm0,%xmm1
 1032fd0:	vpaddq %xmm1,%xmm0,%xmm0
 1032fd4:	vmovq  %xmm0,%r13
 1032fd9:	test   %r8,%r8
 1032fdc:	je     1033090 <main+0x790>
 1032fe2:	cmp    $0x4,%r8d
 1032fe6:	jb     103326f <main+0x96f>
 1032fec:	mov    %eax,%r8d
 1032fef:	and    $0x3,%r8d
 1032ff3:	sub    %r8,%rdx
 1032ff6:	add    %rcx,%rdx
 1032ff9:	vmovq  %r13,%xmm0
 1032ffe:	add    %rcx,%rsi
 1033001:	mov    %rax,%rcx
 1033004:	and    $0xfffffffffffffffc,%rcx
 1033008:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033017:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033026:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033035:	data16 cs nopw 0x0(%rax,%rax,1)
 1033040:	vpmovzxbq 0x20(%rdi,%rsi,1),%ymm1
 1033047:	vpaddq %ymm1,%ymm0,%ymm0
 103304b:	add    $0x4,%rsi
 103304f:	cmp    %rsi,%rcx
 1033052:	jne    1033040 <main+0x740>
 1033054:	vextracti128 $0x1,%ymm0,%xmm1
 103305a:	vpaddq %xmm1,%xmm0,%xmm0
 103305e:	vpshufd $0xee,%xmm0,%xmm1
 1033063:	vpaddq %xmm1,%xmm0,%xmm0
 1033067:	vmovq  %xmm0,%r13
 103306c:	test   %r8,%r8
 103306f:	je     1033090 <main+0x790>
 1033071:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033080:	movzbl 0x20(%rdi,%rdx,1),%ecx
 1033085:	add    %rcx,%r13
 1033088:	inc    %rdx
 103308b:	cmp    %rax,%rdx
 103308e:	jb     1033080 <main+0x780>
 1033090:	mov    %rdi,0x30(%rsp)
 1033095:	testb  $0x2,0x5(%rdi)
 1033099:	jne    10330b0 <main+0x7b0>
 103309b:	vzeroupper
 103309e:	call   1010c70 <myl_core_str_hash>
 10330a3:	jmp    10330b3 <main+0x7b3>
 10330a5:	data16 cs nopw 0x0(%rax,%rax,1)
 10330b0:	mov    0x18(%rdi),%eax
 10330b3:	mov    %eax,%eax
 10330b5:	movabs $0x9e3779b97f4a7c15,%rcx
 10330bf:	imul   %rcx,%rax
 10330c3:	mov    %rax,%rbp
 10330c6:	shr    $0x20,%rbp
 10330ca:	xor    %rax,%rbp
 10330cd:	mov    0x18(%r14),%rcx
 10330d1:	mov    0x8(%rcx),%rax
 10330d5:	test   %rax,%rax
 10330d8:	je     1033190 <main+0x890>
 10330de:	mov    (%rax),%ecx
 10330e0:	tzcnt  %ecx,%edx
 10330e4:	neg    %dl
 10330e6:	shrx   %rdx,%rbp,%rdx
 10330eb:	mov    %rdx,0x10(%rsp)
 10330f0:	vmovdqu 0x10(%rax,%rdx,1),%xmm1
 10330f6:	mov    %ebp,%edx
 10330f8:	and    $0x7f,%dl
 10330fb:	vmovd  %edx,%xmm0
 10330ff:	vpbroadcastb %xmm0,%xmm0
 1033104:	vmovdqa %xmm1,0x60(%rsp)
 103310a:	vpcmpeqb %xmm0,%xmm1,%xmm0
 103310e:	vpmovmskb %xmm0,%edx
 1033112:	test   %edx,%edx
 1033114:	je     1033175 <main+0x875>
 1033116:	lea    -0x1(%rcx),%r15d
 103311a:	add    $0x1e,%ecx
 103311d:	and    $0xfffffff0,%ecx
 1033120:	lea    (%rax,%rcx,1),%rbx
 1033124:	add    $0x10,%rbx
 1033128:	movzwl %dx,%r14d
 103312c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 103313b:	nopl   0x0(%rax,%rax,1)
 1033140:	tzcnt  %r14d,%eax
 1033145:	add    0x10(%rsp),%eax
 1033149:	and    %r15d,%eax
 103314c:	mov    (%rbx,%rax,4),%r12d
 1033150:	shl    $0x4,%r12
 1033154:	mov    (%rsp),%rax
 1033158:	mov    0x20(%rax,%r12,1),%rdi
 103315d:	mov    0x30(%rsp),%rsi
 1033162:	vzeroupper
 1033165:	call   1010dd0 <myl_core_str_eq>
 103316a:	test   %al,%al
 103316c:	jne    10331bb <main+0x8bb>
 103316e:	blsr   %r14d,%r14d
 1033173:	jne    1033140 <main+0x840>
 1033175:	vmovdqa 0x60(%rsp),%xmm0
 103317b:	vpcmpeqb -0x2f963(%rip),%xmm0,%xmm0        # 1003820 <core_io_raw_layout+0x2a0>
 1033183:	vpmovmskb %xmm0,%eax
 1033187:	test   %eax,%eax
 1033189:	je     1033197 <main+0x897>
 103318b:	jmp    10334f1 <main+0xbf1>
 1033190:	cmpq   $0x0,0x18(%rcx)
 1033195:	je     103320a <main+0x90a>
 1033197:	mov    (%rsp),%rdi
 103319b:	lea    0x30(%rsp),%rsi
 10331a0:	mov    %rbp,%rdx
 10331a3:	vzeroupper
 10331a6:	call   100f500 <myl_core_dict_find>
 10331ab:	mov    %rax,%r12
 10331ae:	test   %r12,%r12
 10331b1:	js     10334f1 <main+0xbf1>
 10331b7:	shl    $0x4,%r12
 10331bb:	mov    (%rsp),%r14
 10331bf:	mov    0x28(%r14,%r12,1),%rdx
 10331c4:	mov    %r13,%rsi
 10331c7:	imul   %rdx,%rsi
 10331cb:	jo     1033519 <main+0xc19>
 10331d1:	mov    %rsi,%rax
 10331d4:	imul   %rdx,%rax
 10331d8:	jo     103350f <main+0xc0f>
 10331de:	mov    0x28(%rsp),%rsi
 10331e3:	mov    %rsi,%r12
 10331e6:	add    %rax,%r12
 10331e9:	jo     1033502 <main+0xc02>
 10331ef:	mov    0x20(%rsp),%rsi
 10331f4:	inc    %rsi
 10331f7:	mov    %r12,%rax
 10331fa:	cmp    0x18(%rsp),%rsi
 10331ff:	jne    1032e20 <main+0x520>
 1033205:	jmp    1033283 <main+0x983>
 103320a:	mov    0x20(%rcx),%rbx
 103320e:	test   %rbx,%rbx
 1033211:	je     10334f1 <main+0xbf1>
 1033217:	mov    0x10(%rcx),%r14
 103321b:	mov    0x50(%rsp),%r15
 1033220:	xor    %r12d,%r12d
 1033223:	jmp    1033250 <main+0x950>
 1033225:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033234:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033240:	inc    %r12
 1033243:	add    $0x10,%r15
 1033247:	cmp    %r12,%rbx
 103324a:	je     10334f1 <main+0xbf1>
 1033250:	cmp    %rbp,(%r14,%r12,8)
 1033254:	jne    1033240 <main+0x940>
 1033256:	mov    (%r15),%rdi
 1033259:	mov    0x30(%rsp),%rsi
 103325e:	vzeroupper
 1033261:	call   1010dd0 <myl_core_str_eq>
 1033266:	test   %al,%al
 1033268:	je     1033240 <main+0x940>
 103326a:	jmp    10331ae <main+0x8ae>
 103326f:	add    %rsi,%rcx
 1033272:	jmp    1032f0a <main+0x60a>
 1033277:	nopw   0x0(%rax,%rax,1)
 1033280:	xor    %r12d,%r12d
 1033283:	mov    (%r14),%eax
 1033286:	cmp    $0xffffffff,%eax
 1033289:	je     10332cb <main+0x9cb>
 103328b:	dec    %eax
 103328d:	je     10332a0 <main+0x9a0>
 103328f:	mov    %eax,(%r14)
 1033292:	jmp    10332cb <main+0x9cb>
 1033294:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10332a0:	movzbl 0x7(%r14),%eax
 10332a5:	test   %rax,%rax
 10332a8:	je     103333e <main+0xa3e>
 10332ae:	cmpq   $0x0,0x18(%r14)
 10332b3:	jne    103333e <main+0xa3e>
 10332b9:	lea    0x26550(%rip),%rdx        # 1059810 <myl_core_free_lists>
 10332c0:	mov    (%rdx,%rax,8),%rcx
 10332c4:	mov    %rcx,(%r14)
 10332c7:	mov    %r14,(%rdx,%rax,8)
 10332cb:	mov    0x98(%rsp),%rsi
 10332d3:	mov    %rsi,%rcx
 10332d6:	add    %r12,%rcx
 10332d9:	jo     10335ae <main+0xcae>
 10332df:	mov    %rcx,%rax
 10332e2:	movabs $0x89705f3112a28fe5,%rdx
 10332ec:	imul   %rdx
 10332ef:	add    %rcx,%rdx
 10332f2:	mov    %rdx,%rax
 10332f5:	shr    $0x3f,%rax
 10332f9:	sar    $0x1d,%rdx
 10332fd:	add    %rax,%rdx
 1033300:	imul   $0x3b9aca07,%rdx,%rax
 1033307:	sub    %rax,%rcx
 103330a:	mov    %rcx,%r14
 103330d:	sar    $0x3f,%r14
 1033311:	and    $0x3b9aca07,%r14d
 1033318:	add    %rcx,%r14
 103331b:	mov    0x90(%rsp),%rdx
 1033323:	inc    %rdx
 1033326:	cmp    0x88(%rsp),%rdx
 103332e:	mov    0x80(%rsp),%rax
 1033336:	jne    1032a30 <main+0x130>
 103333c:	jmp    1033348 <main+0xa48>
 103333e:	mov    %r14,%rdi
 1033341:	call   1032110 <myl_core_free_block>
 1033346:	jmp    10332cb <main+0x9cb>
 1033348:	mov    0xb0(%rsp),%rdi
 1033350:	mov    (%rdi),%eax
 1033352:	cmp    $0xffffffff,%eax
 1033355:	je     1033389 <main+0xa89>
 1033357:	dec    %eax
 1033359:	je     103335f <main+0xa5f>
 103335b:	mov    %eax,(%rdi)
 103335d:	jmp    1033389 <main+0xa89>
 103335f:	movzbl 0x7(%rdi),%eax
 1033363:	test   %rax,%rax
 1033366:	je     1033563 <main+0xc63>
 103336c:	cmpq   $0x0,0x18(%rdi)
 1033371:	jne    1033563 <main+0xc63>
 1033377:	lea    0x26492(%rip),%rdx        # 1059810 <myl_core_free_lists>
 103337e:	mov    (%rdx,%rax,8),%rcx
 1033382:	mov    %rcx,(%rdi)
 1033385:	mov    %rdi,(%rdx,%rax,8)
 1033389:	mov    0xb8(%rsp),%rdi
 1033391:	mov    (%rdi),%eax
 1033393:	cmp    $0xffffffff,%eax
 1033396:	je     10333ca <main+0xaca>
 1033398:	dec    %eax
 103339a:	je     10333a0 <main+0xaa0>
 103339c:	mov    %eax,(%rdi)
 103339e:	jmp    10333ca <main+0xaca>
 10333a0:	movzbl 0x7(%rdi),%eax
 10333a4:	test   %rax,%rax
 10333a7:	je     103356d <main+0xc6d>
 10333ad:	cmpq   $0x0,0x18(%rdi)
 10333b2:	jne    103356d <main+0xc6d>
 10333b8:	lea    0x26451(%rip),%rdx        # 1059810 <myl_core_free_lists>
 10333bf:	mov    (%rdx,%rax,8),%rcx
 10333c3:	mov    %rcx,(%rdi)
 10333c6:	mov    %rdi,(%rdx,%rax,8)
 10333ca:	mov    0xc0(%rsp),%rdi
 10333d2:	mov    (%rdi),%eax
 10333d4:	cmp    $0xffffffff,%eax
 10333d7:	je     103340b <main+0xb0b>
 10333d9:	dec    %eax
 10333db:	je     10333e1 <main+0xae1>
 10333dd:	mov    %eax,(%rdi)
 10333df:	jmp    103340b <main+0xb0b>
 10333e1:	movzbl 0x7(%rdi),%eax
 10333e5:	test   %rax,%rax
 10333e8:	je     1033577 <main+0xc77>
 10333ee:	cmpq   $0x0,0x18(%rdi)
 10333f3:	jne    1033577 <main+0xc77>
 10333f9:	lea    0x26410(%rip),%rdx        # 1059810 <myl_core_free_lists>
 1033400:	mov    (%rdx,%rax,8),%rcx
 1033404:	mov    %rcx,(%rdi)
 1033407:	mov    %rdi,(%rdx,%rax,8)
 103340b:	mov    0xc8(%rsp),%rdi
 1033413:	mov    (%rdi),%eax
 1033415:	cmp    $0xffffffff,%eax
 1033418:	je     103344c <main+0xb4c>
 103341a:	dec    %eax
 103341c:	je     1033422 <main+0xb22>
 103341e:	mov    %eax,(%rdi)
 1033420:	jmp    103344c <main+0xb4c>
 1033422:	movzbl 0x7(%rdi),%eax
 1033426:	test   %rax,%rax
 1033429:	je     1033581 <main+0xc81>
 103342f:	cmpq   $0x0,0x18(%rdi)
 1033434:	jne    1033581 <main+0xc81>
 103343a:	lea    0x263cf(%rip),%rdx        # 1059810 <myl_core_free_lists>
 1033441:	mov    (%rdx,%rax,8),%rcx
 1033445:	mov    %rcx,(%rdi)
 1033448:	mov    %rdi,(%rdx,%rax,8)
 103344c:	mov    0xd0(%rsp),%rdi
 1033454:	mov    (%rdi),%eax
 1033456:	cmp    $0xffffffff,%eax
 1033459:	je     103348d <main+0xb8d>
 103345b:	dec    %eax
 103345d:	je     1033463 <main+0xb63>
 103345f:	mov    %eax,(%rdi)
 1033461:	jmp    103348d <main+0xb8d>
 1033463:	movzbl 0x7(%rdi),%eax
 1033467:	test   %rax,%rax
 103346a:	je     103358b <main+0xc8b>
 1033470:	cmpq   $0x0,0x18(%rdi)
 1033475:	jne    103358b <main+0xc8b>
 103347b:	lea    0x2638e(%rip),%rdx        # 1059810 <myl_core_free_lists>
 1033482:	mov    (%rdx,%rax,8),%rcx
 1033486:	mov    %rcx,(%rdi)
 1033489:	mov    %rdi,(%rdx,%rax,8)
 103348d:	mov    $0xa,%edi
 1033492:	call   100a500 <myl_core_io_at>
 1033497:	mov    0x40(%rsp),%rdi
 103349c:	call   1022470 <myl_core_host_check>
 10334a1:	call   1033e90 <runtime_bench_now>
 10334a6:	mov    %rax,%rbx
 10334a9:	mov    0x78(%rsp),%rdx
 10334ae:	sub    %rdx,%rbx
 10334b1:	jo     10335d9 <main+0xcd9>
 10334b7:	mov    $0x1,%edi
 10334bc:	mov    %r14,%rsi
 10334bf:	call   100ac00 <myl_core_print_i64>
 10334c4:	mov    $0x1,%edi
 10334c9:	call   1009240 <myl_core_print_sep>
 10334ce:	mov    $0x1,%edi
 10334d3:	mov    %rbx,%rsi
 10334d6:	call   100ac00 <myl_core_print_i64>
 10334db:	mov    $0x1,%edi
 10334e0:	call   1009300 <myl_core_print_end>
 10334e5:	xor    %ebx,%ebx
 10334e7:	mov    0x8(%rsp),%rdi
 10334ec:	jmp    10329ba <main+0xba>
 10334f1:	mov    $0x24,%edi
 10334f6:	xor    %esi,%esi
 10334f8:	xor    %edx,%edx
 10334fa:	vzeroupper
 10334fd:	call   1009bc0 <myl_core_trap>
 1033502:	mov    $0x26,%edi
 1033507:	mov    %rax,%rdx
 103350a:	call   1009bc0 <myl_core_trap>
 103350f:	mov    $0x25,%edi
 1033514:	call   1009bc0 <myl_core_trap>
 1033519:	mov    $0x23,%edi
 103351e:	mov    %r13,%rsi
 1033521:	call   1009bc0 <myl_core_trap>
 1033526:	mov    $0x1e,%edi
 103352b:	mov    %r15,%rsi
 103352e:	xor    %edx,%edx
 1033530:	call   1009bc0 <myl_core_trap>
 1033535:	mov    $0x1f,%edi
 103353a:	mov    %rax,%rsi
 103353d:	mov    %r15,%rdx
 1033540:	call   1009bc0 <myl_core_trap>
 1033545:	mov    $0x20,%edi
 103354a:	mov    %rbp,%rsi
 103354d:	xor    %edx,%edx
 103354f:	call   1009bc0 <myl_core_trap>
 1033554:	mov    $0x1,%edx
 1033559:	mov    $0x21,%edi
 103355e:	call   1009bc0 <myl_core_trap>
 1033563:	call   1032110 <myl_core_free_block>
 1033568:	jmp    1033389 <main+0xa89>
 103356d:	call   1032110 <myl_core_free_block>
 1033572:	jmp    10333ca <main+0xaca>
 1033577:	call   1032110 <myl_core_free_block>
 103357c:	jmp    103340b <main+0xb0b>
 1033581:	call   1032110 <myl_core_free_block>
 1033586:	jmp    103344c <main+0xb4c>
 103358b:	call   1032110 <myl_core_free_block>
 1033590:	jmp    103348d <main+0xb8d>
 1033595:	mov    $0x1c,%edi
 103359a:	call   1009bc0 <myl_core_trap>
 103359f:	mov    $0x19,%edi
 10335a4:	mov    0x48(%rsp),%rsi
 10335a9:	call   1009bc0 <myl_core_trap>
 10335ae:	mov    $0x1d,%edi
 10335b3:	mov    %r12,%rdx
 10335b6:	call   1009bc0 <myl_core_trap>
 10335bb:	mov    $0x1,%esi
 10335c0:	mov    $0x5,%edi
 10335c5:	call   1009bc0 <myl_core_trap>
 10335ca:	mov    $0x2,%esi
 10335cf:	mov    $0x8,%edi
 10335d4:	call   1009bc0 <myl_core_trap>
 10335d9:	mov    $0xb,%edi
 10335de:	mov    %rax,%rsi
 10335e1:	call   1009bc0 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
