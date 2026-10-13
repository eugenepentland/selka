
/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/dm-001/candidate-application:     file format elf64-x86-64


Disassembly of section .text:

00000000010e9930 <my.diagram_membership::compute_sub_block_attachments>:
 10e9930:	push   %rbp
 10e9931:	push   %r15
 10e9933:	push   %r14
 10e9935:	push   %r13
 10e9937:	push   %r12
 10e9939:	push   %rbx
 10e993a:	sub    $0x1d8,%rsp
 10e9941:	mov    %rdi,%rbx
 10e9944:	mov    %fs:0xfffffffffffffec8,%rdi
 10e994d:	test   %rdi,%rdi
 10e9950:	je     10ee114 <my.diagram_membership::compute_sub_block_attachments+0x47e4>
 10e9956:	mov    (%rdi),%rax
 10e9959:	mov    %rax,%fs:0xfffffffffffffec8
 10e9962:	movl   $0x1000000,(%rdi)
 10e9968:	vpxor  %xmm0,%xmm0,%xmm0
 10e996c:	vmovdqu %xmm0,0x8(%rdi)
 10e9971:	movq   $0x0,0x18(%rdi)
 10e9979:	movabs $0x800000000000,%rcx
 10e9983:	mov    0x30(%rbx),%rax
 10e9987:	mov    %rax,0xc8(%rsp)
 10e998f:	mov    0x8(%rax),%r14
 10e9993:	cmp    %rcx,%r14
 10e9996:	ja     10ee973 <my.diagram_membership::compute_sub_block_attachments+0x5043>
 10e999c:	xor    %esi,%esi
 10e999e:	lea    -0x1(%rcx),%rax
 10e99a2:	mov    %rax,0xe0(%rsp)
 10e99aa:	xor    %r15d,%r15d
 10e99ad:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10e99bc:	nopl   0x0(%rax)
 10e99c0:	cmp    %r15,%r14
 10e99c3:	je     10e9a1c <my.diagram_membership::compute_sub_block_attachments+0xec>
 10e99c5:	cmp    0x10(%rdi),%rsi
 10e99c9:	jae    10e99ff <my.diagram_membership::compute_sub_block_attachments+0xcf>
 10e99cb:	mov    %rsi,%rax
 10e99ce:	shl    $0x4,%rax
 10e99d2:	movq   $0x0,0x20(%rdi,%rax,1)
 10e99db:	cmp    0xe0(%rsp),%rsi
 10e99e3:	lea    0x1(%rsi),%rsi
 10e99e7:	mov    %rsi,0x8(%rdi)
 10e99eb:	ja     10ee7e1 <my.diagram_membership::compute_sub_block_attachments+0x4eb1>
 10e99f1:	cmp    %r15,%rcx
 10e99f4:	lea    0x1(%r15),%r15
 10e99f8:	jne    10e99c0 <my.diagram_membership::compute_sub_block_attachments+0x90>
 10e99fa:	jmp    10ee7ef <my.diagram_membership::compute_sub_block_attachments+0x4ebf>
 10e99ff:	mov    $0x10,%esi
 10e9a04:	call   1085500 <myl_core_list_grow>
 10e9a09:	movabs $0x800000000000,%rcx
 10e9a13:	mov    %rax,%rdi
 10e9a16:	mov    0x8(%rax),%rsi
 10e9a1a:	jmp    10e99cb <my.diagram_membership::compute_sub_block_attachments+0x9b>
 10e9a1c:	mov    0xc8(%rsp),%rax
 10e9a24:	mov    0x8(%rax),%rsi
 10e9a28:	cmp    %rcx,%rsi
 10e9a2b:	ja     10ee984 <my.diagram_membership::compute_sub_block_attachments+0x5054>
 10e9a31:	test   %rsi,%rsi
 10e9a34:	je     10ee006 <my.diagram_membership::compute_sub_block_attachments+0x46d6>
 10e9a3a:	mov    0x38(%rbx),%rax
 10e9a3e:	mov    %rax,0x80(%rsp)
 10e9a46:	mov    0x8(%rax),%rsi
 10e9a4a:	cmp    %rcx,%rsi
 10e9a4d:	ja     10ee992 <my.diagram_membership::compute_sub_block_attachments+0x5062>
 10e9a53:	test   %rsi,%rsi
 10e9a56:	je     10ee006 <my.diagram_membership::compute_sub_block_attachments+0x46d6>
 10e9a5c:	mov    %rdi,0xc0(%rsp)
 10e9a64:	lea    0x9981d(%rip),%rsi        # 1183288 <core_durable_error.verbs+0x32d88>
 10e9a6b:	xor    %edi,%edi
 10e9a6d:	call   108ca40 <myl_core_dict_new>
 10e9a72:	mov    %rax,0x8(%rsp)
 10e9a77:	mov    0x60(%rbx),%rbx
 10e9a7b:	mov    0x8(%rbx),%rcx
 10e9a7f:	movabs $0x800000000000,%rax
 10e9a89:	mov    %rcx,0x28(%rsp)
 10e9a8e:	cmp    %rax,%rcx
 10e9a91:	ja     10ee9a0 <my.diagram_membership::compute_sub_block_attachments+0x5070>
 10e9a97:	lea    0x20(%rbx),%rax
 10e9a9b:	mov    %rax,0xb0(%rsp)
 10e9aa3:	xor    %eax,%eax
 10e9aa5:	mov    %rbx,0x90(%rsp)
 10e9aad:	jmp    10e9aed <my.diagram_membership::compute_sub_block_attachments+0x1bd>
 10e9aaf:	nop
 10e9ab0:	mov    0x30(%rsp),%rdi
 10e9ab5:	call   1086200 <myl_core_drop_owned>
 10e9aba:	mov    0x8(%rsp),%rax
 10e9abf:	mov    0x10(%rsp),%rcx
 10e9ac4:	mov    %rcx,0x28(%rax,%r14,1)
 10e9ac9:	mov    0x90(%rsp),%rbx
 10e9ad1:	mov    0x40(%rsp),%rax
 10e9ad6:	movabs $0x800000000000,%rsi
 10e9ae0:	cmp    %rsi,%rax
 10e9ae3:	lea    0x1(%rax),%rax
 10e9ae7:	je     10ee829 <my.diagram_membership::compute_sub_block_attachments+0x4ef9>
 10e9aed:	cmp    0x28(%rsp),%rax
 10e9af2:	je     10ea5fc <my.diagram_membership::compute_sub_block_attachments+0xccc>
 10e9af8:	mov    0x8(%rbx),%rdx
 10e9afc:	cmp    %rdx,%rax
 10e9aff:	jae    10ee83a <my.diagram_membership::compute_sub_block_attachments+0x4f0a>
 10e9b05:	mov    %rax,0x40(%rsp)
 10e9b0a:	shl    $0x4,%rax
 10e9b0e:	mov    0xb0(%rsp),%rcx
 10e9b16:	mov    (%rcx,%rax,1),%r14
 10e9b1a:	mov    0x8(%rcx,%rax,1),%r12
 10e9b1f:	mov    %r14,%rdi
 10e9b22:	lea    -0x850c9(%rip),%r15        # 1064a60 <core_number_pairs+0x5d390>
 10e9b29:	mov    %r15,%rsi
 10e9b2c:	call   1091940 <myl_core_bytes_find>
 10e9b31:	mov    %rax,%r13
 10e9b34:	mov    %r12,%rdi
 10e9b37:	mov    %r15,%rsi
 10e9b3a:	call   1091940 <myl_core_bytes_find>
 10e9b3f:	mov    %rax,%r15
 10e9b42:	test   %r13,%r13
 10e9b45:	sets   %al
 10e9b48:	test   %r15,%r15
 10e9b4b:	setns  %cl
 10e9b4e:	test   %cl,%al
 10e9b50:	je     10e9b70 <my.diagram_membership::compute_sub_block_attachments+0x240>
 10e9b52:	mov    %r14,%rdi
 10e9b55:	call   1086a80 <myl_core_owned_octets_copy>
 10e9b5a:	mov    %rax,%rbx
 10e9b5d:	mov    %r12,%rdi
 10e9b60:	xor    %esi,%esi
 10e9b62:	mov    %r15,%rdx
 10e9b65:	jmp    10e9b9a <my.diagram_membership::compute_sub_block_attachments+0x26a>
 10e9b67:	nopw   0x0(%rax,%rax,1)
 10e9b70:	test   %r15,%r15
 10e9b73:	sets   %al
 10e9b76:	test   %r13,%r13
 10e9b79:	setns  %cl
 10e9b7c:	and    %al,%cl
 10e9b7e:	cmp    $0x1,%cl
 10e9b81:	jne    10e9ad1 <my.diagram_membership::compute_sub_block_attachments+0x1a1>
 10e9b87:	mov    %r12,%rdi
 10e9b8a:	call   1086a80 <myl_core_owned_octets_copy>
 10e9b8f:	mov    %rax,%rbx
 10e9b92:	mov    %r14,%rdi
 10e9b95:	xor    %esi,%esi
 10e9b97:	mov    %r13,%rdx
 10e9b9a:	call   1091740 <myl_core_bytes_slice>
 10e9b9f:	mov    %rax,%r13
 10e9ba2:	mov    %rbx,%rdi
 10e9ba5:	call   1095500 <myl_core_bytes_utf8_count>
 10e9baa:	test   %rax,%rax
 10e9bad:	js     10ea5a9 <my.diagram_membership::compute_sub_block_attachments+0xc79>
 10e9bb3:	mov    %rbx,%rdi
 10e9bb6:	call   10955c0 <myl_core_bytes_decode_text>
 10e9bbb:	mov    %rax,%rbp
 10e9bbe:	xor    %eax,%eax
 10e9bc0:	test   %al,%al
 10e9bc2:	jne    10ee88d <my.diagram_membership::compute_sub_block_attachments+0x4f5d>
 10e9bc8:	mov    %rbx,%rdi
 10e9bcb:	call   1086200 <myl_core_drop_owned>
 10e9bd0:	mov    %rbp,0x160(%rsp)
 10e9bd8:	testb  $0x2,0x1(%rbp)
 10e9bdc:	jne    10e9bf0 <my.diagram_membership::compute_sub_block_attachments+0x2c0>
 10e9bde:	mov    %rbp,%rdi
 10e9be1:	call   108dec0 <myl_core_str_hash>
 10e9be6:	jmp    10e9bf3 <my.diagram_membership::compute_sub_block_attachments+0x2c3>
 10e9be8:	nopl   0x0(%rax,%rax,1)
 10e9bf0:	mov    0x18(%rbp),%eax
 10e9bf3:	mov    %eax,%eax
 10e9bf5:	movabs $0x9e3779b97f4a7c15,%rcx
 10e9bff:	imul   %rcx,%rax
 10e9c03:	mov    %rax,%rbx
 10e9c06:	shr    $0x20,%rbx
 10e9c0a:	xor    %rax,%rbx
 10e9c0d:	mov    0x8(%rsp),%rax
 10e9c12:	mov    0x18(%rax),%rcx
 10e9c16:	mov    0x8(%rcx),%rax
 10e9c1a:	test   %rax,%rax
 10e9c1d:	mov    %rbp,0x30(%rsp)
 10e9c22:	mov    %r13,0x70(%rsp)
 10e9c27:	je     10e9ce0 <my.diagram_membership::compute_sub_block_attachments+0x3b0>
 10e9c2d:	mov    (%rax),%ecx
 10e9c2f:	tzcnt  %ecx,%edx
 10e9c33:	neg    %dl
 10e9c35:	shrx   %rdx,%rbx,%r14
 10e9c3a:	vmovdqu 0x10(%rax,%r14,1),%xmm1
 10e9c41:	mov    %ebx,%edx
 10e9c43:	and    $0x7f,%dl
 10e9c46:	vmovd  %edx,%xmm0
 10e9c4a:	vpbroadcastb %xmm0,%xmm0
 10e9c4f:	vmovdqa %xmm1,0x10(%rsp)
 10e9c55:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10e9c59:	vpmovmskb %xmm0,%edx
 10e9c5d:	test   %edx,%edx
 10e9c5f:	je     10e9cb8 <my.diagram_membership::compute_sub_block_attachments+0x388>
 10e9c65:	lea    -0x1(%rcx),%ebp
 10e9c68:	add    $0x1e,%ecx
 10e9c6b:	and    $0xfffffff0,%ecx
 10e9c6e:	lea    (%rax,%rcx,1),%r15
 10e9c72:	add    $0x10,%r15
 10e9c76:	movzwl %dx,%r12d
 10e9c7a:	nopw   0x0(%rax,%rax,1)
 10e9c80:	tzcnt  %r12d,%eax
 10e9c85:	add    %r14d,%eax
 10e9c88:	and    %ebp,%eax
 10e9c8a:	mov    (%r15,%rax,4),%eax
 10e9c8e:	shl    $0x4,%rax
 10e9c92:	mov    0x8(%rsp),%rcx
 10e9c97:	mov    0x20(%rcx,%rax,1),%rdi
 10e9c9c:	mov    0x160(%rsp),%rsi
 10e9ca4:	call   108e040 <myl_core_str_eq>
 10e9ca9:	test   %al,%al
 10e9cab:	jne    10ea109 <my.diagram_membership::compute_sub_block_attachments+0x7d9>
 10e9cb1:	blsr   %r12d,%r12d
 10e9cb6:	jne    10e9c80 <my.diagram_membership::compute_sub_block_attachments+0x350>
 10e9cb8:	vmovdqa 0x10(%rsp),%xmm0
 10e9cbe:	vpcmpeqb -0xe5906(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10e9cc6:	vpmovmskb %xmm0,%eax
 10e9cca:	test   %eax,%eax
 10e9ccc:	mov    0x30(%rsp),%rbp
 10e9cd1:	jne    10e9d70 <my.diagram_membership::compute_sub_block_attachments+0x440>
 10e9cd7:	jmp    10e9ce7 <my.diagram_membership::compute_sub_block_attachments+0x3b7>
 10e9cd9:	nopl   0x0(%rax)
 10e9ce0:	cmpq   $0x0,0x18(%rcx)
 10e9ce5:	je     10e9d0a <my.diagram_membership::compute_sub_block_attachments+0x3da>
 10e9ce7:	mov    0x8(%rsp),%rdi
 10e9cec:	lea    0x160(%rsp),%rsi
 10e9cf4:	mov    %rbx,%rdx
 10e9cf7:	call   108c680 <myl_core_dict_find>
 10e9cfc:	mov    %rax,%r14
 10e9cff:	test   %r14,%r14
 10e9d02:	jns    10ea169 <my.diagram_membership::compute_sub_block_attachments+0x839>
 10e9d08:	jmp    10e9d70 <my.diagram_membership::compute_sub_block_attachments+0x440>
 10e9d0a:	mov    0x20(%rcx),%r15
 10e9d0e:	test   %r15,%r15
 10e9d11:	je     10e9d70 <my.diagram_membership::compute_sub_block_attachments+0x440>
 10e9d13:	mov    0x10(%rcx),%r12
 10e9d17:	mov    0x8(%rsp),%rax
 10e9d1c:	lea    0x20(%rax),%r13
 10e9d20:	xor    %r14d,%r14d
 10e9d23:	jmp    10e9d4c <my.diagram_membership::compute_sub_block_attachments+0x41c>
 10e9d25:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10e9d34:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10e9d40:	inc    %r14
 10e9d43:	add    $0x10,%r13
 10e9d47:	cmp    %r14,%r15
 10e9d4a:	je     10e9d70 <my.diagram_membership::compute_sub_block_attachments+0x440>
 10e9d4c:	cmp    %rbx,(%r12,%r14,8)
 10e9d50:	jne    10e9d40 <my.diagram_membership::compute_sub_block_attachments+0x410>
 10e9d52:	mov    0x0(%r13),%rdi
 10e9d56:	mov    0x160(%rsp),%rsi
 10e9d5e:	call   108e040 <myl_core_str_eq>
 10e9d63:	test   %al,%al
 10e9d65:	je     10e9d40 <my.diagram_membership::compute_sub_block_attachments+0x410>
 10e9d67:	jmp    10e9cff <my.diagram_membership::compute_sub_block_attachments+0x3cf>
 10e9d69:	nopl   0x0(%rax)
 10e9d70:	xor    %edi,%edi
 10e9d72:	lea    0x99357(%rip),%rsi        # 11830d0 <core_durable_error.verbs+0x32bd0>
 10e9d79:	call   108ca40 <myl_core_dict_new>
 10e9d7e:	mov    %rax,%rbx
 10e9d81:	mov    0x8(%rbp),%r14
 10e9d85:	movabs $0x800000000000,%rax
 10e9d8f:	cmp    %rax,%r14
 10e9d92:	ja     10ee906 <my.diagram_membership::compute_sub_block_attachments+0x4fd6>
 10e9d98:	add    $0x20,%rbp
 10e9d9c:	mov    %rbp,0x10(%rsp)
 10e9da1:	mov    %rbp,%rdi
 10e9da4:	mov    %r14,%rsi
 10e9da7:	call   108dd80 <myl_core_span_hash>
 10e9dac:	mov    %eax,%eax
 10e9dae:	movabs $0x9e3779b97f4a7c15,%rcx
 10e9db8:	imul   %rcx,%rax
 10e9dbc:	mov    %rax,%r15
 10e9dbf:	shr    $0x20,%r15
 10e9dc3:	xor    %rax,%r15
 10e9dc6:	mov    0x8(%rsp),%rax
 10e9dcb:	mov    0x18(%rax),%rcx
 10e9dcf:	mov    0x8(%rcx),%rax
 10e9dd3:	test   %rax,%rax
 10e9dd6:	mov    %rbx,0xa0(%rsp)
 10e9dde:	je     10e9f79 <my.diagram_membership::compute_sub_block_attachments+0x649>
 10e9de4:	mov    (%rax),%ecx
 10e9de6:	tzcnt  %ecx,%edx
 10e9dea:	neg    %dl
 10e9dec:	shrx   %rdx,%r15,%r12
 10e9df1:	lea    -0x1(%rcx),%ebp
 10e9df4:	vmovdqu 0x10(%rax,%r12,1),%xmm1
 10e9dfb:	and    $0x7f,%r15b
 10e9dff:	vmovd  %r15d,%xmm0
 10e9e04:	vpbroadcastb %xmm0,%xmm0
 10e9e09:	vmovdqa %xmm1,0x60(%rsp)
 10e9e0f:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10e9e13:	vpmovmskb %xmm0,%edx
 10e9e17:	test   %edx,%edx
 10e9e19:	mov    0x10(%rsp),%rsi
 10e9e1e:	je     10e9f4c <my.diagram_membership::compute_sub_block_attachments+0x61c>
 10e9e24:	add    $0x1e,%ecx
 10e9e27:	and    $0xfffffff0,%ecx
 10e9e2a:	lea    (%rax,%rcx,1),%r15
 10e9e2e:	add    $0x10,%r15
 10e9e32:	movzwl %dx,%r13d
 10e9e36:	mov    %r14,%rax
 10e9e39:	shr    $1,%rax
 10e9e3c:	mov    %rax,0x58(%rsp)
 10e9e41:	jmp    10e9ea5 <my.diagram_membership::compute_sub_block_attachments+0x575>
 10e9e43:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10e9e52:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10e9e61:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10e9e70:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10e9e7f:	nop
 10e9e80:	mov    0x10(%rsp),%rsi
 10e9e85:	mov    %r14,%rdx
 10e9e88:	call   114ef30 <bcmp@plt>
 10e9e8d:	mov    0x10(%rsp),%rsi
 10e9e92:	test   %eax,%eax
 10e9e94:	je     10ea0df <my.diagram_membership::compute_sub_block_attachments+0x7af>
 10e9e9a:	blsr   %r13d,%r13d
 10e9e9f:	je     10e9f4c <my.diagram_membership::compute_sub_block_attachments+0x61c>
 10e9ea5:	tzcnt  %r13d,%eax
 10e9eaa:	add    %r12d,%eax
 10e9ead:	and    %ebp,%eax
 10e9eaf:	mov    (%r15,%rax,4),%ebx
 10e9eb3:	mov    %rbx,%rax
 10e9eb6:	shl    $0x4,%rax
 10e9eba:	mov    0x8(%rsp),%rcx
 10e9ebf:	mov    0x20(%rcx,%rax,1),%rdi
 10e9ec4:	cmp    %r14,0x8(%rdi)
 10e9ec8:	jne    10e9e9a <my.diagram_membership::compute_sub_block_attachments+0x56a>
 10e9eca:	add    $0x20,%rdi
 10e9ece:	cmp    $0x10,%r14
 10e9ed2:	ja     10e9e80 <my.diagram_membership::compute_sub_block_attachments+0x550>
 10e9ed4:	cmp    $0x8,%r14
 10e9ed8:	jb     10e9ef3 <my.diagram_membership::compute_sub_block_attachments+0x5c3>
 10e9eda:	mov    (%rdi),%rax
 10e9edd:	cmp    (%rsi),%rax
 10e9ee0:	jne    10e9e9a <my.diagram_membership::compute_sub_block_attachments+0x56a>
 10e9ee2:	mov    -0x8(%rsi,%r14,1),%rax
 10e9ee7:	cmp    %rax,-0x8(%rdi,%r14,1)
 10e9eec:	jne    10e9e9a <my.diagram_membership::compute_sub_block_attachments+0x56a>
 10e9eee:	jmp    10ea0df <my.diagram_membership::compute_sub_block_attachments+0x7af>
 10e9ef3:	cmp    $0x4,%r14
 10e9ef7:	jb     10e9f10 <my.diagram_membership::compute_sub_block_attachments+0x5e0>
 10e9ef9:	mov    (%rdi),%eax
 10e9efb:	cmp    (%rsi),%eax
 10e9efd:	jne    10e9e9a <my.diagram_membership::compute_sub_block_attachments+0x56a>
 10e9eff:	mov    -0x4(%rsi,%r14,1),%eax
 10e9f04:	cmp    %eax,-0x4(%rdi,%r14,1)
 10e9f09:	jne    10e9e9a <my.diagram_membership::compute_sub_block_attachments+0x56a>
 10e9f0b:	jmp    10ea0df <my.diagram_membership::compute_sub_block_attachments+0x7af>
 10e9f10:	test   %r14,%r14
 10e9f13:	je     10ea0df <my.diagram_membership::compute_sub_block_attachments+0x7af>
 10e9f19:	movzbl (%rdi),%eax
 10e9f1c:	cmp    (%rsi),%al
 10e9f1e:	jne    10e9e9a <my.diagram_membership::compute_sub_block_attachments+0x56a>
 10e9f24:	mov    0x58(%rsp),%rcx
 10e9f29:	movzbl (%rsi,%rcx,1),%eax
 10e9f2d:	cmp    %al,(%rdi,%rcx,1)
 10e9f30:	jne    10e9e9a <my.diagram_membership::compute_sub_block_attachments+0x56a>
 10e9f36:	movzbl -0x1(%rsi,%r14,1),%eax
 10e9f3c:	cmp    %al,-0x1(%rdi,%r14,1)
 10e9f41:	jne    10e9e9a <my.diagram_membership::compute_sub_block_attachments+0x56a>
 10e9f47:	jmp    10ea0df <my.diagram_membership::compute_sub_block_attachments+0x7af>
 10e9f4c:	vmovdqa 0x60(%rsp),%xmm0
 10e9f52:	vpcmpeqb -0xe5b9a(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10e9f5a:	vpmovmskb %xmm0,%eax
 10e9f5e:	test   %eax,%eax
 10e9f60:	je     10ea0bd <my.diagram_membership::compute_sub_block_attachments+0x78d>
 10e9f66:	tzcnt  %eax,%r13d
 10e9f6b:	add    %r12d,%r13d
 10e9f6e:	and    %ebp,%r13d
 10e9f71:	not    %r13
 10e9f74:	jmp    10ea110 <my.diagram_membership::compute_sub_block_attachments+0x7e0>
 10e9f79:	mov    0x20(%rcx),%r12
 10e9f7d:	mov    $0xffffffffffffffff,%r13
 10e9f84:	test   %r12,%r12
 10e9f87:	mov    0x10(%rsp),%rsi
 10e9f8c:	je     10ea110 <my.diagram_membership::compute_sub_block_attachments+0x7e0>
 10e9f92:	mov    0x10(%rcx),%rbp
 10e9f96:	mov    0x18(%rcx),%rdx
 10e9f9a:	mov    %r14,%rax
 10e9f9d:	shr    $1,%rax
 10e9fa0:	mov    %rax,0x58(%rsp)
 10e9fa5:	mov    0x8(%rsp),%rax
 10e9faa:	lea    0x20(%rax),%r13
 10e9fae:	xor    %ebx,%ebx
 10e9fb0:	mov    %rdx,0x60(%rsp)
 10e9fb5:	jmp    10ea010 <my.diagram_membership::compute_sub_block_attachments+0x6e0>
 10e9fb7:	mov    0x10(%rsp),%rsi
 10e9fbc:	mov    %r14,%rdx
 10e9fbf:	call   114ef30 <bcmp@plt>
 10e9fc4:	mov    0x60(%rsp),%rdx
 10e9fc9:	mov    0x10(%rsp),%rsi
 10e9fce:	test   %eax,%eax
 10e9fd0:	je     10ea0d7 <my.diagram_membership::compute_sub_block_attachments+0x7a7>
 10e9fd6:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10e9fe5:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10e9ff4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea000:	inc    %rbx
 10ea003:	add    $0x10,%r13
 10ea007:	cmp    %rbx,%r12
 10ea00a:	je     10ea0b4 <my.diagram_membership::compute_sub_block_attachments+0x784>
 10ea010:	cmp    %r15,0x0(%rbp,%rbx,8)
 10ea015:	jne    10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea017:	test   %rdx,%rdx
 10ea01a:	je     10ea031 <my.diagram_membership::compute_sub_block_attachments+0x701>
 10ea01c:	mov    %rbx,%rax
 10ea01f:	shr    $0x3,%rax
 10ea023:	movzbl (%rdx,%rax,1),%eax
 10ea027:	mov    %ebx,%ecx
 10ea029:	and    $0x7,%ecx
 10ea02c:	bt     %ecx,%eax
 10ea02f:	jb     10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea031:	mov    0x0(%r13),%rdi
 10ea035:	cmp    %r14,0x8(%rdi)
 10ea039:	jne    10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea03b:	add    $0x20,%rdi
 10ea03f:	cmp    $0x10,%r14
 10ea043:	ja     10e9fb7 <my.diagram_membership::compute_sub_block_attachments+0x687>
 10ea049:	cmp    $0x8,%r14
 10ea04d:	jb     10ea065 <my.diagram_membership::compute_sub_block_attachments+0x735>
 10ea04f:	mov    (%rdi),%rax
 10ea052:	cmp    (%rsi),%rax
 10ea055:	jne    10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea057:	mov    -0x8(%rsi,%r14,1),%rax
 10ea05c:	cmp    %rax,-0x8(%rdi,%r14,1)
 10ea061:	jne    10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea063:	jmp    10ea0d7 <my.diagram_membership::compute_sub_block_attachments+0x7a7>
 10ea065:	cmp    $0x4,%r14
 10ea069:	jb     10ea07f <my.diagram_membership::compute_sub_block_attachments+0x74f>
 10ea06b:	mov    (%rdi),%eax
 10ea06d:	cmp    (%rsi),%eax
 10ea06f:	jne    10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea071:	mov    -0x4(%rsi,%r14,1),%eax
 10ea076:	cmp    %eax,-0x4(%rdi,%r14,1)
 10ea07b:	jne    10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea07d:	jmp    10ea0d7 <my.diagram_membership::compute_sub_block_attachments+0x7a7>
 10ea07f:	test   %r14,%r14
 10ea082:	je     10ea0d7 <my.diagram_membership::compute_sub_block_attachments+0x7a7>
 10ea084:	movzbl (%rdi),%eax
 10ea087:	cmp    (%rsi),%al
 10ea089:	jne    10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea08f:	mov    0x58(%rsp),%rcx
 10ea094:	movzbl (%rsi,%rcx,1),%eax
 10ea098:	cmp    %al,(%rdi,%rcx,1)
 10ea09b:	jne    10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea0a1:	movzbl -0x1(%rsi,%r14,1),%eax
 10ea0a7:	cmp    %al,-0x1(%rdi,%r14,1)
 10ea0ac:	jne    10ea000 <my.diagram_membership::compute_sub_block_attachments+0x6d0>
 10ea0b2:	jmp    10ea0d7 <my.diagram_membership::compute_sub_block_attachments+0x7a7>
 10ea0b4:	mov    $0xffffffffffffffff,%r13
 10ea0bb:	jmp    10ea110 <my.diagram_membership::compute_sub_block_attachments+0x7e0>
 10ea0bd:	mov    0x8(%rsp),%rdi
 10ea0c2:	mov    0x10(%rsp),%rsi
 10ea0c7:	mov    %r14,%rdx
 10ea0ca:	call   108d9c0 <myl_core_dict_find_span>
 10ea0cf:	mov    0x10(%rsp),%rsi
 10ea0d4:	mov    %rax,%rbx
 10ea0d7:	mov    %rbx,%r13
 10ea0da:	test   %rbx,%rbx
 10ea0dd:	js     10ea110 <my.diagram_membership::compute_sub_block_attachments+0x7e0>
 10ea0df:	mov    0xa0(%rsp),%rax
 10ea0e7:	mov    %rax,0x1c0(%rsp)
 10ea0ef:	mov    0x8(%rsp),%rdi
 10ea0f4:	mov    %rbx,%rsi
 10ea0f7:	lea    0x1c0(%rsp),%rdx
 10ea0ff:	call   108cb00 <myl_core_dict_set>
 10ea104:	mov    %rax,0x8(%rsp)
 10ea109:	mov    0x30(%rsp),%rbp
 10ea10e:	jmp    10ea169 <my.diagram_membership::compute_sub_block_attachments+0x839>
 10ea110:	mov    0x30(%rsp),%rbp
 10ea115:	mov    0x0(%rbp),%edx
 10ea118:	shr    $0x8,%edx
 10ea11b:	and    $0x1,%edx
 10ea11e:	mov    %rsi,%rdi
 10ea121:	mov    %r14,%rsi
 10ea124:	call   108e740 <myl_core_ir_str_from_span>
 10ea129:	mov    %rax,0x1b8(%rsp)
 10ea131:	mov    0xa0(%rsp),%rax
 10ea139:	mov    %rax,0x1b0(%rsp)
 10ea141:	mov    0x8(%rsp),%rdi
 10ea146:	mov    %r13,%rsi
 10ea149:	lea    0x1b8(%rsp),%rdx
 10ea151:	lea    0x1b0(%rsp),%rcx
 10ea159:	mov    $0x1,%r8d
 10ea15f:	call   108cd00 <myl_core_dict_insert>
 10ea164:	mov    %rax,0x8(%rsp)
 10ea169:	mov    %rbp,0x158(%rsp)
 10ea171:	testb  $0x2,0x1(%rbp)
 10ea175:	jne    10ea190 <my.diagram_membership::compute_sub_block_attachments+0x860>
 10ea177:	mov    %rbp,%rdi
 10ea17a:	call   108dec0 <myl_core_str_hash>
 10ea17f:	jmp    10ea193 <my.diagram_membership::compute_sub_block_attachments+0x863>
 10ea181:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea190:	mov    0x18(%rbp),%eax
 10ea193:	mov    %eax,%eax
 10ea195:	movabs $0x9e3779b97f4a7c15,%rcx
 10ea19f:	imul   %rcx,%rax
 10ea1a3:	mov    %rax,%rbx
 10ea1a6:	shr    $0x20,%rbx
 10ea1aa:	xor    %rax,%rbx
 10ea1ad:	mov    0x8(%rsp),%rax
 10ea1b2:	mov    0x18(%rax),%rcx
 10ea1b6:	mov    0x8(%rcx),%rax
 10ea1ba:	test   %rax,%rax
 10ea1bd:	je     10ea2a0 <my.diagram_membership::compute_sub_block_attachments+0x970>
 10ea1c3:	mov    (%rax),%ecx
 10ea1c5:	tzcnt  %ecx,%edx
 10ea1c9:	neg    %dl
 10ea1cb:	shrx   %rdx,%rbx,%r15
 10ea1d0:	vmovdqu 0x10(%rax,%r15,1),%xmm1
 10ea1d7:	mov    %ebx,%edx
 10ea1d9:	and    $0x7f,%dl
 10ea1dc:	vmovd  %edx,%xmm0
 10ea1e0:	vpbroadcastb %xmm0,%xmm0
 10ea1e5:	vmovdqa %xmm1,0x10(%rsp)
 10ea1eb:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10ea1ef:	vpmovmskb %xmm0,%edx
 10ea1f3:	test   %edx,%edx
 10ea1f5:	je     10ea278 <my.diagram_membership::compute_sub_block_attachments+0x948>
 10ea1fb:	lea    -0x1(%rcx),%ebp
 10ea1fe:	add    $0x1e,%ecx
 10ea201:	and    $0xfffffff0,%ecx
 10ea204:	lea    (%rax,%rcx,1),%r12
 10ea208:	add    $0x10,%r12
 10ea20c:	movzwl %dx,%r13d
 10ea210:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea21f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea22e:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea23d:	nopl   (%rax)
 10ea240:	tzcnt  %r13d,%eax
 10ea245:	add    %r15d,%eax
 10ea248:	and    %ebp,%eax
 10ea24a:	mov    (%r12,%rax,4),%r14d
 10ea24e:	shl    $0x4,%r14
 10ea252:	mov    0x8(%rsp),%rax
 10ea257:	mov    0x20(%rax,%r14,1),%rdi
 10ea25c:	mov    0x158(%rsp),%rsi
 10ea264:	call   108e040 <myl_core_str_eq>
 10ea269:	test   %al,%al
 10ea26b:	jne    10ea454 <my.diagram_membership::compute_sub_block_attachments+0xb24>
 10ea271:	blsr   %r13d,%r13d
 10ea276:	jne    10ea240 <my.diagram_membership::compute_sub_block_attachments+0x910>
 10ea278:	vmovdqa 0x10(%rsp),%xmm0
 10ea27e:	vpcmpeqb -0xe5ec6(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10ea286:	vpmovmskb %xmm0,%eax
 10ea28a:	test   %eax,%eax
 10ea28c:	mov    0x30(%rsp),%rbp
 10ea291:	je     10ea2ab <my.diagram_membership::compute_sub_block_attachments+0x97b>
 10ea293:	jmp    10ee307 <my.diagram_membership::compute_sub_block_attachments+0x49d7>
 10ea298:	nopl   0x0(%rax,%rax,1)
 10ea2a0:	cmpq   $0x0,0x18(%rcx)
 10ea2a5:	je     10ea468 <my.diagram_membership::compute_sub_block_attachments+0xb38>
 10ea2ab:	mov    0x8(%rsp),%rdi
 10ea2b0:	lea    0x158(%rsp),%rsi
 10ea2b8:	mov    %rbx,%rdx
 10ea2bb:	call   108c680 <myl_core_dict_find>
 10ea2c0:	mov    %rax,%r14
 10ea2c3:	mov    %rbp,%rdi
 10ea2c6:	call   1086200 <myl_core_drop_owned>
 10ea2cb:	test   %r14,%r14
 10ea2ce:	mov    0x70(%rsp),%rbx
 10ea2d3:	js     10ee30f <my.diagram_membership::compute_sub_block_attachments+0x49df>
 10ea2d9:	shl    $0x4,%r14
 10ea2dd:	mov    %rbx,%rdi
 10ea2e0:	call   1095500 <myl_core_bytes_utf8_count>
 10ea2e5:	test   %rax,%rax
 10ea2e8:	js     10ea5cb <my.diagram_membership::compute_sub_block_attachments+0xc9b>
 10ea2ee:	mov    %rbx,%rdi
 10ea2f1:	call   10955c0 <myl_core_bytes_decode_text>
 10ea2f6:	mov    %rax,%r15
 10ea2f9:	xor    %eax,%eax
 10ea2fb:	test   %al,%al
 10ea2fd:	jne    10ea5e8 <my.diagram_membership::compute_sub_block_attachments+0xcb8>
 10ea303:	mov    %rbx,%rdi
 10ea306:	call   1086200 <myl_core_drop_owned>
 10ea30b:	mov    0x8(%rsp),%rax
 10ea310:	mov    0x28(%rax,%r14,1),%rax
 10ea315:	mov    %rax,0x10(%rsp)
 10ea31a:	mov    %r15,0x150(%rsp)
 10ea322:	testb  $0x2,0x1(%r15)
 10ea327:	mov    %r15,0x30(%rsp)
 10ea32c:	jne    10ea340 <my.diagram_membership::compute_sub_block_attachments+0xa10>
 10ea32e:	mov    %r15,%rdi
 10ea331:	call   108dec0 <myl_core_str_hash>
 10ea336:	jmp    10ea344 <my.diagram_membership::compute_sub_block_attachments+0xa14>
 10ea338:	nopl   0x0(%rax,%rax,1)
 10ea340:	mov    0x18(%r15),%eax
 10ea344:	mov    %eax,%eax
 10ea346:	movabs $0x9e3779b97f4a7c15,%rcx
 10ea350:	imul   %rcx,%rax
 10ea354:	mov    %rax,%r13
 10ea357:	shr    $0x20,%r13
 10ea35b:	xor    %rax,%r13
 10ea35e:	mov    0x10(%rsp),%rax
 10ea363:	mov    0x18(%rax),%rcx
 10ea367:	mov    0x8(%rcx),%rax
 10ea36b:	test   %rax,%rax
 10ea36e:	je     10ea420 <my.diagram_membership::compute_sub_block_attachments+0xaf0>
 10ea374:	mov    (%rax),%ecx
 10ea376:	tzcnt  %ecx,%edx
 10ea37a:	neg    %dl
 10ea37c:	shrx   %rdx,%r13,%rbp
 10ea381:	lea    -0x1(%rcx),%ebx
 10ea384:	vmovdqu 0x10(%rax,%rbp,1),%xmm1
 10ea38a:	mov    %r13d,%edx
 10ea38d:	and    $0x7f,%dl
 10ea390:	vmovd  %edx,%xmm0
 10ea394:	vpbroadcastb %xmm0,%xmm0
 10ea399:	vmovdqa %xmm1,0x70(%rsp)
 10ea39f:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10ea3a3:	vpmovmskb %xmm0,%edx
 10ea3a7:	test   %edx,%edx
 10ea3a9:	je     10ea3f3 <my.diagram_membership::compute_sub_block_attachments+0xac3>
 10ea3ab:	add    $0x1e,%ecx
 10ea3ae:	and    $0xfffffff0,%ecx
 10ea3b1:	lea    (%rax,%rcx,1),%r15
 10ea3b5:	add    $0x10,%r15
 10ea3b9:	movzwl %dx,%r12d
 10ea3bd:	nopl   (%rax)
 10ea3c0:	tzcnt  %r12d,%eax
 10ea3c5:	add    %ebp,%eax
 10ea3c7:	and    %ebx,%eax
 10ea3c9:	mov    (%r15,%rax,4),%eax
 10ea3cd:	mov    0x10(%rsp),%rcx
 10ea3d2:	mov    0x20(%rcx,%rax,8),%rdi
 10ea3d7:	mov    0x150(%rsp),%rsi
 10ea3df:	call   108e040 <myl_core_str_eq>
 10ea3e4:	test   %al,%al
 10ea3e6:	jne    10e9ab0 <my.diagram_membership::compute_sub_block_attachments+0x180>
 10ea3ec:	blsr   %r12d,%r12d
 10ea3f1:	jne    10ea3c0 <my.diagram_membership::compute_sub_block_attachments+0xa90>
 10ea3f3:	vmovdqa 0x70(%rsp),%xmm0
 10ea3f9:	vpcmpeqb -0xe6041(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10ea401:	vpmovmskb %xmm0,%eax
 10ea405:	test   %eax,%eax
 10ea407:	je     10ea42b <my.diagram_membership::compute_sub_block_attachments+0xafb>
 10ea409:	tzcnt  %eax,%r15d
 10ea40e:	add    %ebp,%r15d
 10ea411:	and    %ebx,%r15d
 10ea414:	not    %r15
 10ea417:	jmp    10ea570 <my.diagram_membership::compute_sub_block_attachments+0xc40>
 10ea41c:	nopl   0x0(%rax)
 10ea420:	cmpq   $0x0,0x18(%rcx)
 10ea425:	je     10ea4f0 <my.diagram_membership::compute_sub_block_attachments+0xbc0>
 10ea42b:	mov    0x10(%rsp),%rdi
 10ea430:	lea    0x150(%rsp),%rsi
 10ea438:	mov    %r13,%rdx
 10ea43b:	call   108c680 <myl_core_dict_find>
 10ea440:	mov    %rax,%rbp
 10ea443:	mov    %rbp,%r15
 10ea446:	test   %rbp,%rbp
 10ea449:	jns    10e9ab0 <my.diagram_membership::compute_sub_block_attachments+0x180>
 10ea44f:	jmp    10ea570 <my.diagram_membership::compute_sub_block_attachments+0xc40>
 10ea454:	mov    0x30(%rsp),%rdi
 10ea459:	call   1086200 <myl_core_drop_owned>
 10ea45e:	mov    0x70(%rsp),%rbx
 10ea463:	jmp    10ea2dd <my.diagram_membership::compute_sub_block_attachments+0x9ad>
 10ea468:	mov    0x20(%rcx),%r15
 10ea46c:	test   %r15,%r15
 10ea46f:	je     10ee307 <my.diagram_membership::compute_sub_block_attachments+0x49d7>
 10ea475:	mov    0x10(%rcx),%r12
 10ea479:	mov    0x8(%rsp),%rax
 10ea47e:	lea    0x20(%rax),%r13
 10ea482:	xor    %r14d,%r14d
 10ea485:	jmp    10ea4d0 <my.diagram_membership::compute_sub_block_attachments+0xba0>
 10ea487:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea496:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea4a5:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea4b4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea4c0:	inc    %r14
 10ea4c3:	add    $0x10,%r13
 10ea4c7:	cmp    %r14,%r15
 10ea4ca:	je     10ee307 <my.diagram_membership::compute_sub_block_attachments+0x49d7>
 10ea4d0:	cmp    %rbx,(%r12,%r14,8)
 10ea4d4:	jne    10ea4c0 <my.diagram_membership::compute_sub_block_attachments+0xb90>
 10ea4d6:	mov    0x0(%r13),%rdi
 10ea4da:	mov    0x158(%rsp),%rsi
 10ea4e2:	call   108e040 <myl_core_str_eq>
 10ea4e7:	test   %al,%al
 10ea4e9:	je     10ea4c0 <my.diagram_membership::compute_sub_block_attachments+0xb90>
 10ea4eb:	jmp    10ea2c3 <my.diagram_membership::compute_sub_block_attachments+0x993>
 10ea4f0:	mov    0x20(%rcx),%rbx
 10ea4f4:	mov    $0xffffffffffffffff,%r15
 10ea4fb:	test   %rbx,%rbx
 10ea4fe:	je     10ea570 <my.diagram_membership::compute_sub_block_attachments+0xc40>
 10ea500:	mov    0x10(%rcx),%r12
 10ea504:	xor    %ebp,%ebp
 10ea506:	jmp    10ea548 <my.diagram_membership::compute_sub_block_attachments+0xc18>
 10ea508:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea517:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea526:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea535:	data16 cs nopw 0x0(%rax,%rax,1)
 10ea540:	inc    %rbp
 10ea543:	cmp    %rbp,%rbx
 10ea546:	je     10ea570 <my.diagram_membership::compute_sub_block_attachments+0xc40>
 10ea548:	cmp    %r13,(%r12,%rbp,8)
 10ea54c:	jne    10ea540 <my.diagram_membership::compute_sub_block_attachments+0xc10>
 10ea54e:	mov    0x10(%rsp),%rax
 10ea553:	mov    0x20(%rax,%rbp,8),%rdi
 10ea558:	mov    0x150(%rsp),%rsi
 10ea560:	call   108e040 <myl_core_str_eq>
 10ea565:	test   %al,%al
 10ea567:	je     10ea540 <my.diagram_membership::compute_sub_block_attachments+0xc10>
 10ea569:	jmp    10ea443 <my.diagram_membership::compute_sub_block_attachments+0xb13>
 10ea56e:	xchg   %ax,%ax
 10ea570:	mov    0x30(%rsp),%rax
 10ea575:	mov    %rax,0x1a8(%rsp)
 10ea57d:	mov    0x10(%rsp),%rdi
 10ea582:	mov    %r15,%rsi
 10ea585:	lea    0x1a8(%rsp),%rdx
 10ea58d:	xor    %ecx,%ecx
 10ea58f:	mov    $0x1,%r8d
 10ea595:	call   108cd00 <myl_core_dict_insert>
 10ea59a:	mov    0x8(%rsp),%rcx
 10ea59f:	mov    %rax,0x28(%rcx,%r14,1)
 10ea5a4:	jmp    10e9ac9 <my.diagram_membership::compute_sub_block_attachments+0x199>
 10ea5a9:	lea    0x68e30(%rip),%rdi        # 11533e0 <core_durable_error.verbs+0x2ee0>
 10ea5b0:	call   10b9340 <myl_core_err_trace_origin_preserve_most>
 10ea5b5:	mov    $0x1,%al
 10ea5b7:	lea    -0x8557e(%rip),%rbp        # 1065040 <core_number_pairs+0x5d970>
 10ea5be:	test   %al,%al
 10ea5c0:	je     10e9bc8 <my.diagram_membership::compute_sub_block_attachments+0x298>
 10ea5c6:	jmp    10ee88d <my.diagram_membership::compute_sub_block_attachments+0x4f5d>
 10ea5cb:	lea    0x68e0e(%rip),%rdi        # 11533e0 <core_durable_error.verbs+0x2ee0>
 10ea5d2:	call   10b9340 <myl_core_err_trace_origin_preserve_most>
 10ea5d7:	mov    $0x1,%al
 10ea5d9:	lea    -0x855a0(%rip),%r15        # 1065040 <core_number_pairs+0x5d970>
 10ea5e0:	test   %al,%al
 10ea5e2:	je     10ea303 <my.diagram_membership::compute_sub_block_attachments+0x9d3>
 10ea5e8:	mov    %r15,%rdi
 10ea5eb:	call   1086200 <myl_core_drop_owned>
 10ea5f0:	lea    0x68e19(%rip),%rdi        # 1153410 <core_durable_error.verbs+0x2f10>
 10ea5f7:	call   108c300 <myl_core_assert_fail>
 10ea5fc:	lea    0x98b45(%rip),%rsi        # 1183148 <core_durable_error.verbs+0x32c48>
 10ea603:	xor    %edi,%edi
 10ea605:	call   108ca40 <myl_core_dict_new>
 10ea60a:	mov    %rax,0x30(%rsp)
 10ea60f:	mov    0xc8(%rsp),%rcx
 10ea617:	mov    0x8(%rcx),%rsi
 10ea61b:	movabs $0x800000000000,%rax
 10ea625:	cmp    %rax,%rsi
 10ea628:	ja     10ee045 <my.diagram_membership::compute_sub_block_attachments+0x4715>
 10ea62e:	lea    0x20(%rcx),%rax
 10ea632:	mov    %rax,0x178(%rsp)
 10ea63a:	xor    %r14d,%r14d
 10ea63d:	jmp    10ea6dc <my.diagram_membership::compute_sub_block_attachments+0xdac>
 10ea642:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea650:	vmovdqa 0x70(%rsp),%xmm0
 10ea656:	vpcmpeqb -0xe629e(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10ea65e:	vpmovmskb %xmm0,%eax
 10ea662:	test   %eax,%eax
 10ea664:	je     10ea807 <my.diagram_membership::compute_sub_block_attachments+0xed7>
 10ea66a:	tzcnt  %eax,%r13d
 10ea66f:	add    %r15d,%r13d
 10ea672:	and    %ebx,%r13d
 10ea675:	not    %r13
 10ea678:	mov    0x40(%rsp),%rax
 10ea67d:	mov    %rax,0x1a0(%rsp)
 10ea685:	mov    0x10(%rsp),%r14
 10ea68a:	mov    %r14,0x198(%rsp)
 10ea692:	mov    0x30(%rsp),%rdi
 10ea697:	mov    %r13,%rsi
 10ea69a:	lea    0x1a0(%rsp),%rdx
 10ea6a2:	lea    0x198(%rsp),%rcx
 10ea6aa:	mov    $0x1,%r8d
 10ea6b0:	call   108cd00 <myl_core_dict_insert>
 10ea6b5:	mov    %rax,0x30(%rsp)
 10ea6ba:	inc    %r14
 10ea6bd:	mov    0xc8(%rsp),%rax
 10ea6c5:	mov    0x8(%rax),%rsi
 10ea6c9:	movabs $0x800000000000,%rax
 10ea6d3:	cmp    %rax,%rsi
 10ea6d6:	ja     10ee045 <my.diagram_membership::compute_sub_block_attachments+0x4715>
 10ea6dc:	cmp    %rsi,%r14
 10ea6df:	jae    10ea8dd <my.diagram_membership::compute_sub_block_attachments+0xfad>
 10ea6e5:	imul   $0x428,%r14,%rax
 10ea6ec:	mov    0x178(%rsp),%rcx
 10ea6f4:	mov    (%rcx,%rax,1),%rbx
 10ea6f8:	mov    %rbx,%rdi
 10ea6fb:	call   1095500 <myl_core_bytes_utf8_count>
 10ea700:	test   %rax,%rax
 10ea703:	js     10ea8af <my.diagram_membership::compute_sub_block_attachments+0xf7f>
 10ea709:	mov    %rbx,%rdi
 10ea70c:	call   10955c0 <myl_core_bytes_decode_text>
 10ea711:	mov    %rax,%rdi
 10ea714:	xor    %eax,%eax
 10ea716:	test   %al,%al
 10ea718:	jne    10ea8cc <my.diagram_membership::compute_sub_block_attachments+0xf9c>
 10ea71e:	mov    %rdi,0x148(%rsp)
 10ea726:	testb  $0x2,0x1(%rdi)
 10ea72a:	mov    %r14,0x10(%rsp)
 10ea72f:	mov    %rdi,0x40(%rsp)
 10ea734:	jne    10ea740 <my.diagram_membership::compute_sub_block_attachments+0xe10>
 10ea736:	call   108dec0 <myl_core_str_hash>
 10ea73b:	jmp    10ea743 <my.diagram_membership::compute_sub_block_attachments+0xe13>
 10ea73d:	nopl   (%rax)
 10ea740:	mov    0x18(%rdi),%eax
 10ea743:	mov    %eax,%eax
 10ea745:	movabs $0x9e3779b97f4a7c15,%rcx
 10ea74f:	imul   %rcx,%rax
 10ea753:	mov    %rax,%rbp
 10ea756:	shr    $0x20,%rbp
 10ea75a:	xor    %rax,%rbp
 10ea75d:	mov    0x30(%rsp),%rax
 10ea762:	mov    0x18(%rax),%rcx
 10ea766:	mov    0x8(%rcx),%rax
 10ea76a:	test   %rax,%rax
 10ea76d:	je     10ea800 <my.diagram_membership::compute_sub_block_attachments+0xed0>
 10ea773:	mov    (%rax),%ecx
 10ea775:	tzcnt  %ecx,%edx
 10ea779:	neg    %dl
 10ea77b:	shrx   %rdx,%rbp,%r15
 10ea780:	lea    -0x1(%rcx),%ebx
 10ea783:	vmovdqu 0x10(%rax,%r15,1),%xmm1
 10ea78a:	mov    %ebp,%edx
 10ea78c:	and    $0x7f,%dl
 10ea78f:	vmovd  %edx,%xmm0
 10ea793:	vpbroadcastb %xmm0,%xmm0
 10ea798:	vmovdqa %xmm1,0x70(%rsp)
 10ea79e:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10ea7a2:	vpmovmskb %xmm0,%edx
 10ea7a6:	test   %edx,%edx
 10ea7a8:	je     10ea650 <my.diagram_membership::compute_sub_block_attachments+0xd20>
 10ea7ae:	add    $0x1e,%ecx
 10ea7b1:	and    $0xfffffff0,%ecx
 10ea7b4:	lea    (%rax,%rcx,1),%r13
 10ea7b8:	add    $0x10,%r13
 10ea7bc:	movzwl %dx,%r14d
 10ea7c0:	tzcnt  %r14d,%eax
 10ea7c5:	add    %r15d,%eax
 10ea7c8:	and    %ebx,%eax
 10ea7ca:	mov    0x0(%r13,%rax,4),%r12d
 10ea7cf:	shl    $0x4,%r12
 10ea7d3:	mov    0x30(%rsp),%rax
 10ea7d8:	mov    0x20(%rax,%r12,1),%rdi
 10ea7dd:	mov    0x148(%rsp),%rsi
 10ea7e5:	call   108e040 <myl_core_str_eq>
 10ea7ea:	test   %al,%al
 10ea7ec:	jne    10ea828 <my.diagram_membership::compute_sub_block_attachments+0xef8>
 10ea7ee:	blsr   %r14d,%r14d
 10ea7f3:	jne    10ea7c0 <my.diagram_membership::compute_sub_block_attachments+0xe90>
 10ea7f5:	jmp    10ea650 <my.diagram_membership::compute_sub_block_attachments+0xd20>
 10ea7fa:	nopw   0x0(%rax,%rax,1)
 10ea800:	cmpq   $0x0,0x18(%rcx)
 10ea805:	je     10ea84e <my.diagram_membership::compute_sub_block_attachments+0xf1e>
 10ea807:	mov    0x30(%rsp),%rdi
 10ea80c:	lea    0x148(%rsp),%rsi
 10ea814:	mov    %rbp,%rdx
 10ea817:	call   108c680 <myl_core_dict_find>
 10ea81c:	mov    %rax,%r12
 10ea81f:	test   %r12,%r12
 10ea822:	js     10ea846 <my.diagram_membership::compute_sub_block_attachments+0xf16>
 10ea824:	shl    $0x4,%r12
 10ea828:	mov    0x40(%rsp),%rdi
 10ea82d:	call   1086200 <myl_core_drop_owned>
 10ea832:	mov    0x30(%rsp),%rax
 10ea837:	mov    0x10(%rsp),%r14
 10ea83c:	mov    %r14,0x28(%rax,%r12,1)
 10ea841:	jmp    10ea6ba <my.diagram_membership::compute_sub_block_attachments+0xd8a>
 10ea846:	mov    %r12,%r13
 10ea849:	jmp    10ea678 <my.diagram_membership::compute_sub_block_attachments+0xd48>
 10ea84e:	mov    0x20(%rcx),%rbx
 10ea852:	mov    $0xffffffffffffffff,%r13
 10ea859:	test   %rbx,%rbx
 10ea85c:	je     10ea678 <my.diagram_membership::compute_sub_block_attachments+0xd48>
 10ea862:	mov    0x10(%rcx),%r15
 10ea866:	mov    0x30(%rsp),%rax
 10ea86b:	lea    0x20(%rax),%r14
 10ea86f:	xor    %r12d,%r12d
 10ea872:	jmp    10ea890 <my.diagram_membership::compute_sub_block_attachments+0xf60>
 10ea874:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea880:	inc    %r12
 10ea883:	add    $0x10,%r14
 10ea887:	cmp    %r12,%rbx
 10ea88a:	je     10ea678 <my.diagram_membership::compute_sub_block_attachments+0xd48>
 10ea890:	cmp    %rbp,(%r15,%r12,8)
 10ea894:	jne    10ea880 <my.diagram_membership::compute_sub_block_attachments+0xf50>
 10ea896:	mov    (%r14),%rdi
 10ea899:	mov    0x148(%rsp),%rsi
 10ea8a1:	call   108e040 <myl_core_str_eq>
 10ea8a6:	test   %al,%al
 10ea8a8:	je     10ea880 <my.diagram_membership::compute_sub_block_attachments+0xf50>
 10ea8aa:	jmp    10ea81f <my.diagram_membership::compute_sub_block_attachments+0xeef>
 10ea8af:	lea    0x68b2a(%rip),%rdi        # 11533e0 <core_durable_error.verbs+0x2ee0>
 10ea8b6:	call   10b9340 <myl_core_err_trace_origin_preserve_most>
 10ea8bb:	mov    $0x1,%al
 10ea8bd:	lea    -0x85884(%rip),%rdi        # 1065040 <core_number_pairs+0x5d970>
 10ea8c4:	test   %al,%al
 10ea8c6:	je     10ea71e <my.diagram_membership::compute_sub_block_attachments+0xdee>
 10ea8cc:	call   1086200 <myl_core_drop_owned>
 10ea8d1:	lea    0x68b38(%rip),%rdi        # 1153410 <core_durable_error.verbs+0x2f10>
 10ea8d8:	call   108c300 <myl_core_assert_fail>
 10ea8dd:	lea    0x98864(%rip),%rsi        # 1183148 <core_durable_error.verbs+0x32c48>
 10ea8e4:	xor    %edi,%edi
 10ea8e6:	call   108ca40 <myl_core_dict_new>
 10ea8eb:	mov    %rax,0x70(%rsp)
 10ea8f0:	mov    0x80(%rsp),%rax
 10ea8f8:	mov    0x8(%rax),%rsi
 10ea8fc:	movabs $0x800000000000,%rcx
 10ea906:	cmp    %rcx,%rsi
 10ea909:	ja     10ee053 <my.diagram_membership::compute_sub_block_attachments+0x4723>
 10ea90f:	xor    %ebx,%ebx
 10ea911:	jmp    10ea938 <my.diagram_membership::compute_sub_block_attachments+0x1008>
 10ea913:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ea920:	inc    %rbx
 10ea923:	mov    0x80(%rsp),%rax
 10ea92b:	mov    0x8(%rax),%rsi
 10ea92f:	cmp    %rcx,%rsi
 10ea932:	ja     10ee053 <my.diagram_membership::compute_sub_block_attachments+0x4723>
 10ea938:	cmp    %rsi,%rbx
 10ea93b:	jae    10eac62 <my.diagram_membership::compute_sub_block_attachments+0x1332>
 10ea941:	imul   $0x70,%rbx,%rax
 10ea945:	mov    0x80(%rsp),%rdx
 10ea94d:	mov    0x80(%rdx,%rax,1),%r15
 10ea955:	mov    0x8(%r15),%rax
 10ea959:	mov    %rax,0x28(%rsp)
 10ea95e:	cmp    %rcx,%rax
 10ea961:	ja     10ee849 <my.diagram_membership::compute_sub_block_attachments+0x4f19>
 10ea967:	xor    %r12d,%r12d
 10ea96a:	mov    %rbx,0x90(%rsp)
 10ea972:	mov    %r15,0xa0(%rsp)
 10ea97a:	jmp    10ea9ae <my.diagram_membership::compute_sub_block_attachments+0x107e>
 10ea97c:	nopl   0x0(%rax)
 10ea980:	mov    0x10(%rsp),%rdi
 10ea985:	call   1086200 <myl_core_drop_owned>
 10ea98a:	movabs $0x800000000000,%rcx
 10ea994:	mov    0x40(%rsp),%rax
 10ea999:	cmp    %rcx,%rax
 10ea99c:	lea    0x1(%rax),%r12
 10ea9a0:	mov    0xa0(%rsp),%r15
 10ea9a8:	je     10ee13e <my.diagram_membership::compute_sub_block_attachments+0x480e>
 10ea9ae:	cmp    0x28(%rsp),%r12
 10ea9b3:	je     10ea920 <my.diagram_membership::compute_sub_block_attachments+0xff0>
 10ea9b9:	mov    0x8(%r15),%rdx
 10ea9bd:	cmp    %rdx,%r12
 10ea9c0:	jae    10ee163 <my.diagram_membership::compute_sub_block_attachments+0x4833>
 10ea9c6:	mov    0x20(%r15,%r12,8),%r14
 10ea9cb:	mov    %r14,%rdi
 10ea9ce:	call   1095500 <myl_core_bytes_utf8_count>
 10ea9d3:	test   %rax,%rax
 10ea9d6:	js     10eabf3 <my.diagram_membership::compute_sub_block_attachments+0x12c3>
 10ea9dc:	mov    %r14,%rdi
 10ea9df:	call   10955c0 <myl_core_bytes_decode_text>
 10ea9e4:	mov    %rax,%rdi
 10ea9e7:	xor    %eax,%eax
 10ea9e9:	test   %al,%al
 10ea9eb:	jne    10ee152 <my.diagram_membership::compute_sub_block_attachments+0x4822>
 10ea9f1:	mov    %rdi,0x140(%rsp)
 10ea9f9:	testb  $0x2,0x1(%rdi)
 10ea9fd:	mov    %rdi,0x10(%rsp)
 10eaa02:	jne    10eaa10 <my.diagram_membership::compute_sub_block_attachments+0x10e0>
 10eaa04:	call   108dec0 <myl_core_str_hash>
 10eaa09:	jmp    10eaa13 <my.diagram_membership::compute_sub_block_attachments+0x10e3>
 10eaa0b:	nopl   0x0(%rax,%rax,1)
 10eaa10:	mov    0x18(%rdi),%eax
 10eaa13:	mov    %r12,0x40(%rsp)
 10eaa18:	mov    %eax,%eax
 10eaa1a:	movabs $0x9e3779b97f4a7c15,%rcx
 10eaa24:	imul   %rcx,%rax
 10eaa28:	mov    %rax,%r14
 10eaa2b:	shr    $0x20,%r14
 10eaa2f:	xor    %rax,%r14
 10eaa32:	mov    0x70(%rsp),%rax
 10eaa37:	mov    0x18(%rax),%rcx
 10eaa3b:	mov    0x8(%rcx),%rax
 10eaa3f:	test   %rax,%rax
 10eaa42:	je     10eab30 <my.diagram_membership::compute_sub_block_attachments+0x1200>
 10eaa48:	mov    (%rax),%ecx
 10eaa4a:	tzcnt  %ecx,%edx
 10eaa4e:	neg    %dl
 10eaa50:	shrx   %rdx,%r14,%r12
 10eaa55:	lea    -0x1(%rcx),%ebp
 10eaa58:	vmovdqu 0x10(%rax,%r12,1),%xmm1
 10eaa5f:	mov    %r14d,%edx
 10eaa62:	and    $0x7f,%dl
 10eaa65:	vmovd  %edx,%xmm0
 10eaa69:	vpbroadcastb %xmm0,%xmm0
 10eaa6e:	vmovdqa %xmm1,0xb0(%rsp)
 10eaa77:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10eaa7b:	vpmovmskb %xmm0,%edx
 10eaa7f:	test   %edx,%edx
 10eaa81:	je     10eaaf9 <my.diagram_membership::compute_sub_block_attachments+0x11c9>
 10eaa83:	add    $0x1e,%ecx
 10eaa86:	and    $0xfffffff0,%ecx
 10eaa89:	lea    (%rax,%rcx,1),%r13
 10eaa8d:	add    $0x10,%r13
 10eaa91:	movzwl %dx,%r15d
 10eaa95:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eaaa4:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eaab3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eaac0:	tzcnt  %r15d,%eax
 10eaac5:	add    %r12d,%eax
 10eaac8:	and    %ebp,%eax
 10eaaca:	mov    0x0(%r13,%rax,4),%eax
 10eaacf:	shl    $0x4,%rax
 10eaad3:	mov    0x70(%rsp),%rcx
 10eaad8:	mov    0x20(%rcx,%rax,1),%rdi
 10eaadd:	mov    0x140(%rsp),%rsi
 10eaae5:	call   108e040 <myl_core_str_eq>
 10eaaea:	test   %al,%al
 10eaaec:	jne    10ea980 <my.diagram_membership::compute_sub_block_attachments+0x1050>
 10eaaf2:	blsr   %r15d,%r15d
 10eaaf7:	jne    10eaac0 <my.diagram_membership::compute_sub_block_attachments+0x1190>
 10eaaf9:	vmovdqa 0xb0(%rsp),%xmm0
 10eab02:	vpcmpeqb -0xe674a(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10eab0a:	vpmovmskb %xmm0,%eax
 10eab0e:	test   %eax,%eax
 10eab10:	je     10eab37 <my.diagram_membership::compute_sub_block_attachments+0x1207>
 10eab12:	tzcnt  %eax,%r13d
 10eab17:	add    %r12d,%r13d
 10eab1a:	and    %ebp,%r13d
 10eab1d:	not    %r13
 10eab20:	jmp    10eac20 <my.diagram_membership::compute_sub_block_attachments+0x12f0>
 10eab25:	data16 cs nopw 0x0(%rax,%rax,1)
 10eab30:	cmpq   $0x0,0x18(%rcx)
 10eab35:	je     10eab60 <my.diagram_membership::compute_sub_block_attachments+0x1230>
 10eab37:	mov    0x70(%rsp),%rdi
 10eab3c:	lea    0x140(%rsp),%rsi
 10eab44:	mov    %r14,%rdx
 10eab47:	call   108c680 <myl_core_dict_find>
 10eab4c:	mov    %rax,%r12
 10eab4f:	mov    %r12,%r13
 10eab52:	test   %r12,%r12
 10eab55:	jns    10ea980 <my.diagram_membership::compute_sub_block_attachments+0x1050>
 10eab5b:	jmp    10eac20 <my.diagram_membership::compute_sub_block_attachments+0x12f0>
 10eab60:	mov    0x20(%rcx),%rbp
 10eab64:	mov    $0xffffffffffffffff,%r13
 10eab6b:	test   %rbp,%rbp
 10eab6e:	je     10eac20 <my.diagram_membership::compute_sub_block_attachments+0x12f0>
 10eab74:	mov    0x10(%rcx),%r15
 10eab78:	mov    0x70(%rsp),%rax
 10eab7d:	lea    0x20(%rax),%rbx
 10eab81:	xor    %r12d,%r12d
 10eab84:	jmp    10eabcc <my.diagram_membership::compute_sub_block_attachments+0x129c>
 10eab86:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eab95:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eaba4:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eabb3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eabc0:	inc    %r12
 10eabc3:	add    $0x10,%rbx
 10eabc7:	cmp    %r12,%rbp
 10eabca:	je     10eac15 <my.diagram_membership::compute_sub_block_attachments+0x12e5>
 10eabcc:	cmp    %r14,(%r15,%r12,8)
 10eabd0:	jne    10eabc0 <my.diagram_membership::compute_sub_block_attachments+0x1290>
 10eabd2:	mov    (%rbx),%rdi
 10eabd5:	mov    0x140(%rsp),%rsi
 10eabdd:	call   108e040 <myl_core_str_eq>
 10eabe2:	test   %al,%al
 10eabe4:	je     10eabc0 <my.diagram_membership::compute_sub_block_attachments+0x1290>
 10eabe6:	mov    0x90(%rsp),%rbx
 10eabee:	jmp    10eab4f <my.diagram_membership::compute_sub_block_attachments+0x121f>
 10eabf3:	lea    0x687e6(%rip),%rdi        # 11533e0 <core_durable_error.verbs+0x2ee0>
 10eabfa:	call   10b9340 <myl_core_err_trace_origin_preserve_most>
 10eabff:	mov    $0x1,%al
 10eac01:	lea    -0x85bc8(%rip),%rdi        # 1065040 <core_number_pairs+0x5d970>
 10eac08:	test   %al,%al
 10eac0a:	je     10ea9f1 <my.diagram_membership::compute_sub_block_attachments+0x10c1>
 10eac10:	jmp    10ee152 <my.diagram_membership::compute_sub_block_attachments+0x4822>
 10eac15:	mov    0x90(%rsp),%rbx
 10eac1d:	nopl   (%rax)
 10eac20:	mov    0x10(%rsp),%rax
 10eac25:	mov    %rax,0x190(%rsp)
 10eac2d:	mov    %rbx,0x188(%rsp)
 10eac35:	mov    0x70(%rsp),%rdi
 10eac3a:	mov    %r13,%rsi
 10eac3d:	lea    0x190(%rsp),%rdx
 10eac45:	lea    0x188(%rsp),%rcx
 10eac4d:	mov    $0x1,%r8d
 10eac53:	call   108cd00 <myl_core_dict_insert>
 10eac58:	mov    %rax,0x70(%rsp)
 10eac5d:	jmp    10ea98a <my.diagram_membership::compute_sub_block_attachments+0x105a>
 10eac62:	lea    0x98467(%rip),%rsi        # 11830d0 <core_durable_error.verbs+0x32bd0>
 10eac69:	xor    %edi,%edi
 10eac6b:	call   108ca40 <myl_core_dict_new>
 10eac70:	movabs $0x800000000000,%rcx
 10eac7a:	mov    %rax,0x28(%rsp)
 10eac7f:	mov    0x80(%rsp),%rax
 10eac87:	mov    0x8(%rax),%rax
 10eac8b:	mov    %rax,0x58(%rsp)
 10eac90:	cmp    %rcx,%rax
 10eac93:	ja     10ee9b3 <my.diagram_membership::compute_sub_block_attachments+0x5083>
 10eac99:	xor    %esi,%esi
 10eac9b:	jmp    10eacb2 <my.diagram_membership::compute_sub_block_attachments+0x1382>
 10eac9d:	nopl   (%rax)
 10eaca0:	mov    0x60(%rsp),%rax
 10eaca5:	cmp    %rcx,%rax
 10eaca8:	lea    0x1(%rax),%rsi
 10eacac:	je     10ee879 <my.diagram_membership::compute_sub_block_attachments+0x4f49>
 10eacb2:	mov    0x80(%rsp),%rax
 10eacba:	mov    0x8(%rax),%rdx
 10eacbe:	cmp    0x58(%rsp),%rsi
 10eacc3:	je     10eaf8d <my.diagram_membership::compute_sub_block_attachments+0x165d>
 10eacc9:	cmp    %rdx,%rsi
 10eaccc:	jae    10ee85c <my.diagram_membership::compute_sub_block_attachments+0x4f2c>
 10eacd2:	mov    %rsi,0x60(%rsp)
 10eacd7:	imul   $0x70,%rsi,%rax
 10eacdb:	mov    0x80(%rsp),%rdx
 10eace3:	mov    0x50(%rdx,%rax,1),%r12
 10eace8:	mov    0x8(%r12),%r14
 10eaced:	cmp    %rcx,%r14
 10eacf0:	ja     10ee868 <my.diagram_membership::compute_sub_block_attachments+0x4f38>
 10eacf6:	lea    0x20(%r12),%rsi
 10eacfb:	xor    %ebx,%ebx
 10eacfd:	mov    %rsi,0xa0(%rsp)
 10ead05:	mov    %r14,0x40(%rsp)
 10ead0a:	mov    %r12,0xb0(%rsp)
 10ead12:	jmp    10ead4a <my.diagram_membership::compute_sub_block_attachments+0x141a>
 10ead14:	mov    0x10(%rsp),%rdi
 10ead19:	call   1086200 <myl_core_drop_owned>
 10ead1e:	mov    0x40(%rsp),%r14
 10ead23:	mov    0xb0(%rsp),%r12
 10ead2b:	mov    0xa0(%rsp),%rsi
 10ead33:	movabs $0x800000000000,%rcx
 10ead3d:	cmp    %rcx,%rbx
 10ead40:	lea    0x1(%rbx),%rbx
 10ead44:	je     10ee181 <my.diagram_membership::compute_sub_block_attachments+0x4851>
 10ead4a:	cmp    %r14,%rbx
 10ead4d:	je     10eaca0 <my.diagram_membership::compute_sub_block_attachments+0x1370>
 10ead53:	mov    0x8(%r12),%rdx
 10ead58:	cmp    %rdx,%rbx
 10ead5b:	jae    10ee172 <my.diagram_membership::compute_sub_block_attachments+0x4842>
 10ead61:	imul   $0xf0,%rbx,%rax
 10ead68:	cmpl   $0x0,0x10(%rsi,%rax,1)
 10ead6d:	jne    10ead33 <my.diagram_membership::compute_sub_block_attachments+0x1403>
 10ead6f:	add    %rsi,%rax
 10ead72:	mov    (%rax),%r15
 10ead75:	mov    %r15,%rdi
 10ead78:	call   1095500 <myl_core_bytes_utf8_count>
 10ead7d:	test   %rax,%rax
 10ead80:	js     10eaf5f <my.diagram_membership::compute_sub_block_attachments+0x162f>
 10ead86:	mov    %r15,%rdi
 10ead89:	call   10955c0 <myl_core_bytes_decode_text>
 10ead8e:	mov    %rax,%rdi
 10ead91:	xor    %eax,%eax
 10ead93:	test   %al,%al
 10ead95:	jne    10eaf7c <my.diagram_membership::compute_sub_block_attachments+0x164c>
 10ead9b:	mov    %rdi,0x138(%rsp)
 10eada3:	testb  $0x2,0x1(%rdi)
 10eada7:	mov    %rdi,0x10(%rsp)
 10eadac:	jne    10eadb5 <my.diagram_membership::compute_sub_block_attachments+0x1485>
 10eadae:	call   108dec0 <myl_core_str_hash>
 10eadb3:	jmp    10eadb8 <my.diagram_membership::compute_sub_block_attachments+0x1488>
 10eadb5:	mov    0x18(%rdi),%eax
 10eadb8:	mov    %eax,%eax
 10eadba:	movabs $0x9e3779b97f4a7c15,%rcx
 10eadc4:	imul   %rcx,%rax
 10eadc8:	mov    %rax,%r13
 10eadcb:	shr    $0x20,%r13
 10eadcf:	xor    %rax,%r13
 10eadd2:	mov    0x28(%rsp),%rax
 10eadd7:	mov    0x18(%rax),%rcx
 10eaddb:	mov    0x8(%rcx),%rax
 10eaddf:	test   %rax,%rax
 10eade2:	je     10eaea0 <my.diagram_membership::compute_sub_block_attachments+0x1570>
 10eade8:	mov    (%rax),%ecx
 10eadea:	tzcnt  %ecx,%edx
 10eadee:	neg    %dl
 10eadf0:	shrx   %rdx,%r13,%r12
 10eadf5:	lea    -0x1(%rcx),%r14d
 10eadf9:	vmovdqu 0x10(%rax,%r12,1),%xmm1
 10eae00:	mov    %r13d,%edx
 10eae03:	and    $0x7f,%dl
 10eae06:	vmovd  %edx,%xmm0
 10eae0a:	vpbroadcastb %xmm0,%xmm0
 10eae0f:	vmovdqa %xmm1,0x90(%rsp)
 10eae18:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10eae1c:	vpmovmskb %xmm0,%edx
 10eae20:	test   %edx,%edx
 10eae22:	je     10eae75 <my.diagram_membership::compute_sub_block_attachments+0x1545>
 10eae24:	add    $0x1e,%ecx
 10eae27:	and    $0xfffffff0,%ecx
 10eae2a:	lea    (%rax,%rcx,1),%rbp
 10eae2e:	add    $0x10,%rbp
 10eae32:	movzwl %dx,%r15d
 10eae36:	cs nopw 0x0(%rax,%rax,1)
 10eae40:	tzcnt  %r15d,%eax
 10eae45:	add    %r12d,%eax
 10eae48:	and    %r14d,%eax
 10eae4b:	mov    0x0(%rbp,%rax,4),%eax
 10eae4f:	mov    0x28(%rsp),%rcx
 10eae54:	mov    0x20(%rcx,%rax,8),%rdi
 10eae59:	mov    0x138(%rsp),%rsi
 10eae61:	call   108e040 <myl_core_str_eq>
 10eae66:	test   %al,%al
 10eae68:	jne    10ead14 <my.diagram_membership::compute_sub_block_attachments+0x13e4>
 10eae6e:	blsr   %r15d,%r15d
 10eae73:	jne    10eae40 <my.diagram_membership::compute_sub_block_attachments+0x1510>
 10eae75:	vmovdqa 0x90(%rsp),%xmm0
 10eae7e:	vpcmpeqb -0xe6ac6(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10eae86:	vpmovmskb %xmm0,%eax
 10eae8a:	test   %eax,%eax
 10eae8c:	je     10eaea7 <my.diagram_membership::compute_sub_block_attachments+0x1577>
 10eae8e:	tzcnt  %eax,%ebp
 10eae92:	add    %r12d,%ebp
 10eae95:	and    %r14d,%ebp
 10eae98:	not    %rbp
 10eae9b:	jmp    10eaf2b <my.diagram_membership::compute_sub_block_attachments+0x15fb>
 10eaea0:	cmpq   $0x0,0x18(%rcx)
 10eaea5:	je     10eaecd <my.diagram_membership::compute_sub_block_attachments+0x159d>
 10eaea7:	mov    0x28(%rsp),%rdi
 10eaeac:	lea    0x138(%rsp),%rsi
 10eaeb4:	mov    %r13,%rdx
 10eaeb7:	call   108c680 <myl_core_dict_find>
 10eaebc:	mov    %rax,%r12
 10eaebf:	mov    %r12,%rbp
 10eaec2:	test   %r12,%r12
 10eaec5:	jns    10ead14 <my.diagram_membership::compute_sub_block_attachments+0x13e4>
 10eaecb:	jmp    10eaf2b <my.diagram_membership::compute_sub_block_attachments+0x15fb>
 10eaecd:	mov    0x20(%rcx),%r14
 10eaed1:	mov    $0xffffffffffffffff,%rbp
 10eaed8:	test   %r14,%r14
 10eaedb:	je     10eaf2b <my.diagram_membership::compute_sub_block_attachments+0x15fb>
 10eaedd:	mov    0x10(%rcx),%r15
 10eaee1:	xor    %r12d,%r12d
 10eaee4:	jmp    10eaf08 <my.diagram_membership::compute_sub_block_attachments+0x15d8>
 10eaee6:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eaef5:	data16 cs nopw 0x0(%rax,%rax,1)
 10eaf00:	inc    %r12
 10eaf03:	cmp    %r12,%r14
 10eaf06:	je     10eaf2b <my.diagram_membership::compute_sub_block_attachments+0x15fb>
 10eaf08:	cmp    %r13,(%r15,%r12,8)
 10eaf0c:	jne    10eaf00 <my.diagram_membership::compute_sub_block_attachments+0x15d0>
 10eaf0e:	mov    0x28(%rsp),%rax
 10eaf13:	mov    0x20(%rax,%r12,8),%rdi
 10eaf18:	mov    0x138(%rsp),%rsi
 10eaf20:	call   108e040 <myl_core_str_eq>
 10eaf25:	test   %al,%al
 10eaf27:	je     10eaf00 <my.diagram_membership::compute_sub_block_attachments+0x15d0>
 10eaf29:	jmp    10eaebf <my.diagram_membership::compute_sub_block_attachments+0x158f>
 10eaf2b:	mov    0x10(%rsp),%rax
 10eaf30:	mov    %rax,0x180(%rsp)
 10eaf38:	mov    0x28(%rsp),%rdi
 10eaf3d:	mov    %rbp,%rsi
 10eaf40:	lea    0x180(%rsp),%rdx
 10eaf48:	xor    %ecx,%ecx
 10eaf4a:	mov    $0x1,%r8d
 10eaf50:	call   108cd00 <myl_core_dict_insert>
 10eaf55:	mov    %rax,0x28(%rsp)
 10eaf5a:	jmp    10ead1e <my.diagram_membership::compute_sub_block_attachments+0x13ee>
 10eaf5f:	lea    0x6847a(%rip),%rdi        # 11533e0 <core_durable_error.verbs+0x2ee0>
 10eaf66:	call   10b9340 <myl_core_err_trace_origin_preserve_most>
 10eaf6b:	mov    $0x1,%al
 10eaf6d:	lea    -0x85f34(%rip),%rdi        # 1065040 <core_number_pairs+0x5d970>
 10eaf74:	test   %al,%al
 10eaf76:	je     10ead9b <my.diagram_membership::compute_sub_block_attachments+0x146b>
 10eaf7c:	call   1086200 <myl_core_drop_owned>
 10eaf81:	lea    0x68488(%rip),%rdi        # 1153410 <core_durable_error.verbs+0x2f10>
 10eaf88:	call   108c300 <myl_core_assert_fail>
 10eaf8d:	cmp    %rcx,%rdx
 10eaf90:	ja     10ee9c6 <my.diagram_membership::compute_sub_block_attachments+0x5096>
 10eaf96:	mov    0xc8(%rsp),%rax
 10eaf9e:	mov    0x8(%rax),%rax
 10eafa2:	mov    %rax,0xe8(%rsp)
 10eafaa:	cmp    %rcx,%rax
 10eafad:	ja     10ee9d7 <my.diagram_membership::compute_sub_block_attachments+0x50a7>
 10eafb3:	mov    %fs:0xfffffffffffffec8,%rsi
 10eafbc:	test   %rsi,%rsi
 10eafbf:	mov    %rdx,0x58(%rsp)
 10eafc4:	je     10ee23a <my.diagram_membership::compute_sub_block_attachments+0x490a>
 10eafca:	mov    (%rsi),%rax
 10eafcd:	mov    %rax,%fs:0xfffffffffffffec8
 10eafd6:	movl   $0x1000000,(%rsi)
 10eafdc:	vpxor  %xmm0,%xmm0,%xmm0
 10eafe0:	vmovdqu %xmm0,0x8(%rsi)
 10eafe5:	mov    %rsi,0x60(%rsp)
 10eafea:	movq   $0x0,0x18(%rsi)
 10eaff2:	mov    0xe8(%rsp),%rbx
 10eaffa:	imul   %rdx,%rbx
 10eaffe:	jo     10ee9ed <my.diagram_membership::compute_sub_block_attachments+0x50bd>
 10eb004:	test   %rbx,%rbx
 10eb007:	js     10eea01 <my.diagram_membership::compute_sub_block_attachments+0x50d1>
 10eb00d:	je     10eb09f <my.diagram_membership::compute_sub_block_attachments+0x176f>
 10eb013:	xor    %esi,%esi
 10eb015:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb024:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb033:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb040:	mov    0x60(%rsp),%rax
 10eb045:	cmp    0x10(%rax),%rsi
 10eb049:	jae    10eb07a <my.diagram_membership::compute_sub_block_attachments+0x174a>
 10eb04b:	mov    0x60(%rsp),%rdi
 10eb050:	mov    0x8(%rdi),%rax
 10eb054:	movq   $0x0,0x20(%rdi,%rax,8)
 10eb05d:	lea    0x1(%rax),%rsi
 10eb061:	mov    %rsi,0x8(%rdi)
 10eb065:	cmp    0xe0(%rsp),%rax
 10eb06d:	ja     10ee8a1 <my.diagram_membership::compute_sub_block_attachments+0x4f71>
 10eb073:	dec    %rbx
 10eb076:	jne    10eb040 <my.diagram_membership::compute_sub_block_attachments+0x1710>
 10eb078:	jmp    10eb09f <my.diagram_membership::compute_sub_block_attachments+0x176f>
 10eb07a:	mov    $0x8,%esi
 10eb07f:	mov    0x60(%rsp),%rdi
 10eb084:	call   1085500 <myl_core_list_grow>
 10eb089:	mov    0x58(%rsp),%rdx
 10eb08e:	movabs $0x800000000000,%rcx
 10eb098:	mov    %rax,0x60(%rsp)
 10eb09d:	jmp    10eb04b <my.diagram_membership::compute_sub_block_attachments+0x171b>
 10eb09f:	mov    0x80(%rsp),%rax
 10eb0a7:	add    $0x20,%rax
 10eb0ab:	mov    %rax,0x100(%rsp)
 10eb0b3:	mov    0x8(%rsp),%rax
 10eb0b8:	add    $0x20,%rax
 10eb0bc:	mov    %rax,0xf8(%rsp)
 10eb0c4:	mov    0x30(%rsp),%rax
 10eb0c9:	add    $0x20,%rax
 10eb0cd:	mov    %rax,0x88(%rsp)
 10eb0d5:	xor    %r8d,%r8d
 10eb0d8:	jmp    10eb10e <my.diagram_membership::compute_sub_block_attachments+0x17de>
 10eb0da:	nopw   0x0(%rax,%rax,1)
 10eb0e0:	mov    0x10(%rsp),%rdi
 10eb0e5:	call   1086200 <myl_core_drop_owned>
 10eb0ea:	movabs $0x800000000000,%rcx
 10eb0f4:	mov    0xd8(%rsp),%rax
 10eb0fc:	cmp    %rcx,%rax
 10eb0ff:	lea    0x1(%rax),%r8
 10eb103:	mov    0x58(%rsp),%rdx
 10eb108:	je     10ee8f2 <my.diagram_membership::compute_sub_block_attachments+0x4fc2>
 10eb10e:	mov    0x60(%rsp),%rax
 10eb113:	mov    0x8(%rax),%rsi
 10eb117:	cmp    %rcx,%rsi
 10eb11a:	ja     10ee8af <my.diagram_membership::compute_sub_block_attachments+0x4f7f>
 10eb120:	cmp    %rdx,%r8
 10eb123:	je     10ebe70 <my.diagram_membership::compute_sub_block_attachments+0x2540>
 10eb129:	mov    0x80(%rsp),%rax
 10eb131:	mov    0x8(%rax),%rdx
 10eb135:	cmp    %rdx,%r8
 10eb138:	jae    10ee036 <my.diagram_membership::compute_sub_block_attachments+0x4706>
 10eb13e:	mov    %r8,0xd8(%rsp)
 10eb146:	imul   $0x70,%r8,%rbx
 10eb14a:	xor    %edi,%edi
 10eb14c:	lea    0x97f7d(%rip),%rsi        # 11830d0 <core_durable_error.verbs+0x32bd0>
 10eb153:	call   108ca40 <myl_core_dict_new>
 10eb158:	mov    %rax,0x10(%rsp)
 10eb15d:	mov    0x100(%rsp),%rax
 10eb165:	mov    %rbx,0xf0(%rsp)
 10eb16d:	mov    0x28(%rax,%rbx,1),%rcx
 10eb172:	mov    0x8(%rcx),%rsi
 10eb176:	movabs $0x800000000000,%rax
 10eb180:	cmp    %rax,%rsi
 10eb183:	ja     10ee8bd <my.diagram_membership::compute_sub_block_attachments+0x4f8d>
 10eb189:	test   %rsi,%rsi
 10eb18c:	je     10eb490 <my.diagram_membership::compute_sub_block_attachments+0x1b60>
 10eb192:	xor    %r8d,%r8d
 10eb195:	mov    %rsi,0x110(%rsp)
 10eb19d:	mov    %rcx,0x108(%rsp)
 10eb1a5:	jmp    10eb1d4 <my.diagram_membership::compute_sub_block_attachments+0x18a4>
 10eb1a7:	nopw   0x0(%rax,%rax,1)
 10eb1b0:	mov    0xd0(%rsp),%r8
 10eb1b8:	inc    %r8
 10eb1bb:	mov    0x110(%rsp),%rsi
 10eb1c3:	cmp    %rsi,%r8
 10eb1c6:	mov    0x108(%rsp),%rcx
 10eb1ce:	je     10eb490 <my.diagram_membership::compute_sub_block_attachments+0x1b60>
 10eb1d4:	mov    0x8(%rcx),%rdx
 10eb1d8:	cmp    %rdx,%r8
 10eb1db:	jae    10ee2d6 <my.diagram_membership::compute_sub_block_attachments+0x49a6>
 10eb1e1:	lea    (%r8,%r8,2),%rax
 10eb1e5:	mov    0x28(%rcx,%rax,8),%rdi
 10eb1ea:	mov    0x8(%rdi),%r14
 10eb1ee:	movabs $0x800000000000,%rax
 10eb1f8:	cmp    %rax,%r14
 10eb1fb:	ja     10ee2c5 <my.diagram_membership::compute_sub_block_attachments+0x4995>
 10eb201:	mov    %r8,0xd0(%rsp)
 10eb209:	test   %r14,%r14
 10eb20c:	je     10eb1b0 <my.diagram_membership::compute_sub_block_attachments+0x1880>
 10eb20e:	xor    %r15d,%r15d
 10eb211:	mov    %rdi,0x90(%rsp)
 10eb219:	mov    %r14,0xa0(%rsp)
 10eb221:	jmp    10eb256 <my.diagram_membership::compute_sub_block_attachments+0x1926>
 10eb223:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb230:	mov    0x40(%rsp),%rdi
 10eb235:	call   1086200 <myl_core_drop_owned>
 10eb23a:	inc    %r15
 10eb23d:	mov    0xa0(%rsp),%r14
 10eb245:	cmp    %r14,%r15
 10eb248:	mov    0x90(%rsp),%rdi
 10eb250:	je     10eb1b0 <my.diagram_membership::compute_sub_block_attachments+0x1880>
 10eb256:	mov    0x8(%rdi),%rdx
 10eb25a:	cmp    %rdx,%r15
 10eb25d:	jae    10ee061 <my.diagram_membership::compute_sub_block_attachments+0x4731>
 10eb263:	mov    %r15,%rax
 10eb266:	shl    $0x5,%rax
 10eb26a:	mov    0x28(%rdi,%rax,1),%rbx
 10eb26f:	mov    %rbx,%rdi
 10eb272:	call   1095500 <myl_core_bytes_utf8_count>
 10eb277:	test   %rax,%rax
 10eb27a:	js     10eb464 <my.diagram_membership::compute_sub_block_attachments+0x1b34>
 10eb280:	mov    %rbx,%rdi
 10eb283:	call   10955c0 <myl_core_bytes_decode_text>
 10eb288:	mov    %rax,%rdi
 10eb28b:	xor    %eax,%eax
 10eb28d:	test   %al,%al
 10eb28f:	jne    10ee070 <my.diagram_membership::compute_sub_block_attachments+0x4740>
 10eb295:	mov    %rdi,0x170(%rsp)
 10eb29d:	testb  $0x2,0x1(%rdi)
 10eb2a1:	mov    %rdi,0x40(%rsp)
 10eb2a6:	jne    10eb2b0 <my.diagram_membership::compute_sub_block_attachments+0x1980>
 10eb2a8:	call   108dec0 <myl_core_str_hash>
 10eb2ad:	jmp    10eb2b3 <my.diagram_membership::compute_sub_block_attachments+0x1983>
 10eb2af:	nop
 10eb2b0:	mov    0x18(%rdi),%eax
 10eb2b3:	mov    %eax,%eax
 10eb2b5:	movabs $0x9e3779b97f4a7c15,%rcx
 10eb2bf:	imul   %rcx,%rax
 10eb2c3:	mov    %rax,%r12
 10eb2c6:	shr    $0x20,%r12
 10eb2ca:	xor    %rax,%r12
 10eb2cd:	mov    0x10(%rsp),%rax
 10eb2d2:	mov    0x18(%rax),%rcx
 10eb2d6:	mov    0x8(%rcx),%rax
 10eb2da:	test   %rax,%rax
 10eb2dd:	je     10eb3a0 <my.diagram_membership::compute_sub_block_attachments+0x1a70>
 10eb2e3:	mov    (%rax),%ecx
 10eb2e5:	tzcnt  %ecx,%edx
 10eb2e9:	neg    %dl
 10eb2eb:	shrx   %rdx,%r12,%r14
 10eb2f0:	lea    -0x1(%rcx),%ebp
 10eb2f3:	vmovdqu 0x10(%rax,%r14,1),%xmm1
 10eb2fa:	mov    %r12d,%edx
 10eb2fd:	and    $0x7f,%dl
 10eb300:	vmovd  %edx,%xmm0
 10eb304:	vpbroadcastb %xmm0,%xmm0
 10eb309:	vmovdqa %xmm1,0xb0(%rsp)
 10eb312:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10eb316:	vpmovmskb %xmm0,%edx
 10eb31a:	test   %edx,%edx
 10eb31c:	je     10eb373 <my.diagram_membership::compute_sub_block_attachments+0x1a43>
 10eb31e:	add    $0x1e,%ecx
 10eb321:	and    $0xfffffff0,%ecx
 10eb324:	lea    (%rax,%rcx,1),%rbx
 10eb328:	add    $0x10,%rbx
 10eb32c:	movzwl %dx,%r13d
 10eb330:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb33f:	nop
 10eb340:	tzcnt  %r13d,%eax
 10eb345:	add    %r14d,%eax
 10eb348:	and    %ebp,%eax
 10eb34a:	mov    (%rbx,%rax,4),%eax
 10eb34d:	mov    0x10(%rsp),%rcx
 10eb352:	mov    0x20(%rcx,%rax,8),%rdi
 10eb357:	mov    0x170(%rsp),%rsi
 10eb35f:	call   108e040 <myl_core_str_eq>
 10eb364:	test   %al,%al
 10eb366:	jne    10eb230 <my.diagram_membership::compute_sub_block_attachments+0x1900>
 10eb36c:	blsr   %r13d,%r13d
 10eb371:	jne    10eb340 <my.diagram_membership::compute_sub_block_attachments+0x1a10>
 10eb373:	vmovdqa 0xb0(%rsp),%xmm0
 10eb37c:	vpcmpeqb -0xe6fc4(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10eb384:	vpmovmskb %xmm0,%eax
 10eb388:	test   %eax,%eax
 10eb38a:	je     10eb3a7 <my.diagram_membership::compute_sub_block_attachments+0x1a77>
 10eb38c:	tzcnt  %eax,%ebx
 10eb390:	add    %r14d,%ebx
 10eb393:	and    %ebp,%ebx
 10eb395:	not    %rbx
 10eb398:	jmp    10eb430 <my.diagram_membership::compute_sub_block_attachments+0x1b00>
 10eb39d:	nopl   (%rax)
 10eb3a0:	cmpq   $0x0,0x18(%rcx)
 10eb3a5:	je     10eb3cd <my.diagram_membership::compute_sub_block_attachments+0x1a9d>
 10eb3a7:	mov    0x10(%rsp),%rdi
 10eb3ac:	lea    0x170(%rsp),%rsi
 10eb3b4:	mov    %r12,%rdx
 10eb3b7:	call   108c680 <myl_core_dict_find>
 10eb3bc:	mov    %rax,%r14
 10eb3bf:	mov    %r14,%rbx
 10eb3c2:	test   %r14,%r14
 10eb3c5:	jns    10eb230 <my.diagram_membership::compute_sub_block_attachments+0x1900>
 10eb3cb:	jmp    10eb430 <my.diagram_membership::compute_sub_block_attachments+0x1b00>
 10eb3cd:	mov    0x20(%rcx),%rbp
 10eb3d1:	mov    $0xffffffffffffffff,%rbx
 10eb3d8:	test   %rbp,%rbp
 10eb3db:	je     10eb430 <my.diagram_membership::compute_sub_block_attachments+0x1b00>
 10eb3dd:	mov    0x10(%rcx),%r13
 10eb3e1:	xor    %r14d,%r14d
 10eb3e4:	jmp    10eb408 <my.diagram_membership::compute_sub_block_attachments+0x1ad8>
 10eb3e6:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb3f5:	data16 cs nopw 0x0(%rax,%rax,1)
 10eb400:	inc    %r14
 10eb403:	cmp    %r14,%rbp
 10eb406:	je     10eb430 <my.diagram_membership::compute_sub_block_attachments+0x1b00>
 10eb408:	cmp    %r12,0x0(%r13,%r14,8)
 10eb40d:	jne    10eb400 <my.diagram_membership::compute_sub_block_attachments+0x1ad0>
 10eb40f:	mov    0x10(%rsp),%rax
 10eb414:	mov    0x20(%rax,%r14,8),%rdi
 10eb419:	mov    0x170(%rsp),%rsi
 10eb421:	call   108e040 <myl_core_str_eq>
 10eb426:	test   %al,%al
 10eb428:	je     10eb400 <my.diagram_membership::compute_sub_block_attachments+0x1ad0>
 10eb42a:	jmp    10eb3bf <my.diagram_membership::compute_sub_block_attachments+0x1a8f>
 10eb42c:	nopl   0x0(%rax)
 10eb430:	mov    0x40(%rsp),%rax
 10eb435:	mov    %rax,0x1d0(%rsp)
 10eb43d:	mov    0x10(%rsp),%rdi
 10eb442:	mov    %rbx,%rsi
 10eb445:	lea    0x1d0(%rsp),%rdx
 10eb44d:	xor    %ecx,%ecx
 10eb44f:	mov    $0x1,%r8d
 10eb455:	call   108cd00 <myl_core_dict_insert>
 10eb45a:	mov    %rax,0x10(%rsp)
 10eb45f:	jmp    10eb23a <my.diagram_membership::compute_sub_block_attachments+0x190a>
 10eb464:	lea    0x67f75(%rip),%rdi        # 11533e0 <core_durable_error.verbs+0x2ee0>
 10eb46b:	call   10b9340 <myl_core_err_trace_origin_preserve_most>
 10eb470:	mov    $0x1,%al
 10eb472:	lea    -0x86439(%rip),%rdi        # 1065040 <core_number_pairs+0x5d970>
 10eb479:	test   %al,%al
 10eb47b:	je     10eb295 <my.diagram_membership::compute_sub_block_attachments+0x1965>
 10eb481:	jmp    10ee070 <my.diagram_membership::compute_sub_block_attachments+0x4740>
 10eb486:	cs nopw 0x0(%rax,%rax,1)
 10eb490:	mov    0xf0(%rsp),%rax
 10eb498:	add    0x100(%rsp),%rax
 10eb4a0:	mov    0x30(%rax),%rax
 10eb4a4:	mov    %rax,0xb0(%rsp)
 10eb4ac:	mov    0x8(%rax),%r15
 10eb4b0:	movabs $0x800000000000,%rax
 10eb4ba:	cmp    %rax,%r15
 10eb4bd:	ja     10ee8cb <my.diagram_membership::compute_sub_block_attachments+0x4f9b>
 10eb4c3:	test   %r15,%r15
 10eb4c6:	je     10eb750 <my.diagram_membership::compute_sub_block_attachments+0x1e20>
 10eb4cc:	mov    0xb0(%rsp),%rax
 10eb4d4:	add    $0x20,%rax
 10eb4d8:	mov    %rax,0x90(%rsp)
 10eb4e0:	xor    %r14d,%r14d
 10eb4e3:	mov    %r15,0xd0(%rsp)
 10eb4eb:	jmp    10eb50e <my.diagram_membership::compute_sub_block_attachments+0x1bde>
 10eb4ed:	nopl   (%rax)
 10eb4f0:	mov    0x40(%rsp),%rdi
 10eb4f5:	call   1086200 <myl_core_drop_owned>
 10eb4fa:	inc    %r14
 10eb4fd:	mov    0xd0(%rsp),%r15
 10eb505:	cmp    %r15,%r14
 10eb508:	je     10eb750 <my.diagram_membership::compute_sub_block_attachments+0x1e20>
 10eb50e:	mov    0xb0(%rsp),%rax
 10eb516:	mov    0x8(%rax),%rdx
 10eb51a:	cmp    %rdx,%r14
 10eb51d:	jae    10ee2a5 <my.diagram_membership::compute_sub_block_attachments+0x4975>
 10eb523:	imul   $0xf0,%r14,%rax
 10eb52a:	mov    0x90(%rsp),%rcx
 10eb532:	mov    (%rcx,%rax,1),%rbx
 10eb536:	mov    %rbx,%rdi
 10eb539:	call   1095500 <myl_core_bytes_utf8_count>
 10eb53e:	test   %rax,%rax
 10eb541:	js     10eb724 <my.diagram_membership::compute_sub_block_attachments+0x1df4>
 10eb547:	mov    %rbx,%rdi
 10eb54a:	call   10955c0 <myl_core_bytes_decode_text>
 10eb54f:	mov    %rax,%rdi
 10eb552:	xor    %eax,%eax
 10eb554:	test   %al,%al
 10eb556:	jne    10ee2b4 <my.diagram_membership::compute_sub_block_attachments+0x4984>
 10eb55c:	mov    %rdi,0x168(%rsp)
 10eb564:	testb  $0x2,0x1(%rdi)
 10eb568:	mov    %rdi,0x40(%rsp)
 10eb56d:	jne    10eb580 <my.diagram_membership::compute_sub_block_attachments+0x1c50>
 10eb56f:	call   108dec0 <myl_core_str_hash>
 10eb574:	jmp    10eb583 <my.diagram_membership::compute_sub_block_attachments+0x1c53>
 10eb576:	cs nopw 0x0(%rax,%rax,1)
 10eb580:	mov    0x18(%rdi),%eax
 10eb583:	mov    %eax,%eax
 10eb585:	movabs $0x9e3779b97f4a7c15,%rcx
 10eb58f:	imul   %rcx,%rax
 10eb593:	mov    %rax,%r12
 10eb596:	shr    $0x20,%r12
 10eb59a:	xor    %rax,%r12
 10eb59d:	mov    0x10(%rsp),%rax
 10eb5a2:	mov    0x18(%rax),%rcx
 10eb5a6:	mov    0x8(%rcx),%rax
 10eb5aa:	test   %rax,%rax
 10eb5ad:	je     10eb660 <my.diagram_membership::compute_sub_block_attachments+0x1d30>
 10eb5b3:	mov    (%rax),%ecx
 10eb5b5:	tzcnt  %ecx,%edx
 10eb5b9:	neg    %dl
 10eb5bb:	shrx   %rdx,%r12,%r13
 10eb5c0:	lea    -0x1(%rcx),%ebp
 10eb5c3:	vmovdqu 0x10(%rax,%r13,1),%xmm1
 10eb5ca:	mov    %r12d,%edx
 10eb5cd:	and    $0x7f,%dl
 10eb5d0:	vmovd  %edx,%xmm0
 10eb5d4:	vpbroadcastb %xmm0,%xmm0
 10eb5d9:	vmovdqa %xmm1,0xa0(%rsp)
 10eb5e2:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10eb5e6:	vpmovmskb %xmm0,%edx
 10eb5ea:	test   %edx,%edx
 10eb5ec:	je     10eb633 <my.diagram_membership::compute_sub_block_attachments+0x1d03>
 10eb5ee:	add    $0x1e,%ecx
 10eb5f1:	and    $0xfffffff0,%ecx
 10eb5f4:	lea    (%rax,%rcx,1),%rbx
 10eb5f8:	add    $0x10,%rbx
 10eb5fc:	movzwl %dx,%r15d
 10eb600:	tzcnt  %r15d,%eax
 10eb605:	add    %r13d,%eax
 10eb608:	and    %ebp,%eax
 10eb60a:	mov    (%rbx,%rax,4),%eax
 10eb60d:	mov    0x10(%rsp),%rcx
 10eb612:	mov    0x20(%rcx,%rax,8),%rdi
 10eb617:	mov    0x168(%rsp),%rsi
 10eb61f:	call   108e040 <myl_core_str_eq>
 10eb624:	test   %al,%al
 10eb626:	jne    10eb4f0 <my.diagram_membership::compute_sub_block_attachments+0x1bc0>
 10eb62c:	blsr   %r15d,%r15d
 10eb631:	jne    10eb600 <my.diagram_membership::compute_sub_block_attachments+0x1cd0>
 10eb633:	vmovdqa 0xa0(%rsp),%xmm0
 10eb63c:	vpcmpeqb -0xe7284(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10eb644:	vpmovmskb %xmm0,%eax
 10eb648:	test   %eax,%eax
 10eb64a:	je     10eb667 <my.diagram_membership::compute_sub_block_attachments+0x1d37>
 10eb64c:	tzcnt  %eax,%ebx
 10eb650:	add    %r13d,%ebx
 10eb653:	and    %ebp,%ebx
 10eb655:	not    %rbx
 10eb658:	jmp    10eb6f0 <my.diagram_membership::compute_sub_block_attachments+0x1dc0>
 10eb65d:	nopl   (%rax)
 10eb660:	cmpq   $0x0,0x18(%rcx)
 10eb665:	je     10eb68d <my.diagram_membership::compute_sub_block_attachments+0x1d5d>
 10eb667:	mov    0x10(%rsp),%rdi
 10eb66c:	lea    0x168(%rsp),%rsi
 10eb674:	mov    %r12,%rdx
 10eb677:	call   108c680 <myl_core_dict_find>
 10eb67c:	mov    %rax,%r13
 10eb67f:	mov    %r13,%rbx
 10eb682:	test   %r13,%r13
 10eb685:	jns    10eb4f0 <my.diagram_membership::compute_sub_block_attachments+0x1bc0>
 10eb68b:	jmp    10eb6f0 <my.diagram_membership::compute_sub_block_attachments+0x1dc0>
 10eb68d:	mov    0x20(%rcx),%rbp
 10eb691:	mov    $0xffffffffffffffff,%rbx
 10eb698:	test   %rbp,%rbp
 10eb69b:	je     10eb6f0 <my.diagram_membership::compute_sub_block_attachments+0x1dc0>
 10eb69d:	mov    0x10(%rcx),%r15
 10eb6a1:	xor    %r13d,%r13d
 10eb6a4:	jmp    10eb6c8 <my.diagram_membership::compute_sub_block_attachments+0x1d98>
 10eb6a6:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb6b5:	data16 cs nopw 0x0(%rax,%rax,1)
 10eb6c0:	inc    %r13
 10eb6c3:	cmp    %r13,%rbp
 10eb6c6:	je     10eb6f0 <my.diagram_membership::compute_sub_block_attachments+0x1dc0>
 10eb6c8:	cmp    %r12,(%r15,%r13,8)
 10eb6cc:	jne    10eb6c0 <my.diagram_membership::compute_sub_block_attachments+0x1d90>
 10eb6ce:	mov    0x10(%rsp),%rax
 10eb6d3:	mov    0x20(%rax,%r13,8),%rdi
 10eb6d8:	mov    0x168(%rsp),%rsi
 10eb6e0:	call   108e040 <myl_core_str_eq>
 10eb6e5:	test   %al,%al
 10eb6e7:	je     10eb6c0 <my.diagram_membership::compute_sub_block_attachments+0x1d90>
 10eb6e9:	jmp    10eb67f <my.diagram_membership::compute_sub_block_attachments+0x1d4f>
 10eb6eb:	nopl   0x0(%rax,%rax,1)
 10eb6f0:	mov    0x40(%rsp),%rax
 10eb6f5:	mov    %rax,0x1c8(%rsp)
 10eb6fd:	mov    0x10(%rsp),%rdi
 10eb702:	mov    %rbx,%rsi
 10eb705:	lea    0x1c8(%rsp),%rdx
 10eb70d:	xor    %ecx,%ecx
 10eb70f:	mov    $0x1,%r8d
 10eb715:	call   108cd00 <myl_core_dict_insert>
 10eb71a:	mov    %rax,0x10(%rsp)
 10eb71f:	jmp    10eb4fa <my.diagram_membership::compute_sub_block_attachments+0x1bca>
 10eb724:	lea    0x67cb5(%rip),%rdi        # 11533e0 <core_durable_error.verbs+0x2ee0>
 10eb72b:	call   10b9340 <myl_core_err_trace_origin_preserve_most>
 10eb730:	mov    $0x1,%al
 10eb732:	lea    -0x866f9(%rip),%rdi        # 1065040 <core_number_pairs+0x5d970>
 10eb739:	test   %al,%al
 10eb73b:	je     10eb55c <my.diagram_membership::compute_sub_block_attachments+0x1c2c>
 10eb741:	jmp    10ee2b4 <my.diagram_membership::compute_sub_block_attachments+0x4984>
 10eb746:	cs nopw 0x0(%rax,%rax,1)
 10eb750:	mov    0x10(%rsp),%rax
 10eb755:	mov    0x8(%rax),%rax
 10eb759:	movabs $0x800000000000,%rcx
 10eb763:	mov    %rax,0x90(%rsp)
 10eb76b:	cmp    %rcx,%rax
 10eb76e:	ja     10ee8dc <my.diagram_membership::compute_sub_block_attachments+0x4fac>
 10eb774:	mov    0x60(%rsp),%rax
 10eb779:	mov    0x8(%rax),%rsi
 10eb77d:	xor    %eax,%eax
 10eb77f:	jmp    10eb7e1 <my.diagram_membership::compute_sub_block_attachments+0x1eb1>
 10eb781:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb790:	vmovdqa 0x40(%rsp),%xmm0
 10eb796:	vpcmpeqb -0xe73de(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10eb79e:	vpmovmskb %xmm0,%eax
 10eb7a2:	test   %eax,%eax
 10eb7a4:	je     10ebac5 <my.diagram_membership::compute_sub_block_attachments+0x2195>
 10eb7aa:	nopw   0x0(%rax,%rax,1)
 10eb7b0:	mov    0x60(%rsp),%rax
 10eb7b5:	mov    0x8(%rax),%rsi
 10eb7b9:	movabs $0x800000000000,%rcx
 10eb7c3:	cmp    %rcx,%rsi
 10eb7c6:	ja     10ee283 <my.diagram_membership::compute_sub_block_attachments+0x4953>
 10eb7cc:	mov    0xa0(%rsp),%rax
 10eb7d4:	cmp    %rcx,%rax
 10eb7d7:	lea    0x1(%rax),%rax
 10eb7db:	je     10ee291 <my.diagram_membership::compute_sub_block_attachments+0x4961>
 10eb7e1:	cmp    %rcx,%rsi
 10eb7e4:	ja     10ee275 <my.diagram_membership::compute_sub_block_attachments+0x4945>
 10eb7ea:	cmp    0x90(%rsp),%rax
 10eb7f2:	je     10eb0e0 <my.diagram_membership::compute_sub_block_attachments+0x17b0>
 10eb7f8:	mov    0x10(%rsp),%rbx
 10eb7fd:	mov    %rbx,%rdi
 10eb800:	mov    %rax,0xa0(%rsp)
 10eb808:	mov    %rax,%rsi
 10eb80b:	call   108d700 <myl_core_dict_ordinal>
 10eb810:	mov    0x20(%rbx,%rax,8),%rbx
 10eb815:	mov    %rbx,0x130(%rsp)
 10eb81d:	testb  $0x2,0x1(%rbx)
 10eb821:	jne    10eb830 <my.diagram_membership::compute_sub_block_attachments+0x1f00>
 10eb823:	mov    %rbx,%rdi
 10eb826:	call   108dec0 <myl_core_str_hash>
 10eb82b:	jmp    10eb833 <my.diagram_membership::compute_sub_block_attachments+0x1f03>
 10eb82d:	nopl   (%rax)
 10eb830:	mov    0x18(%rbx),%eax
 10eb833:	mov    %eax,%eax
 10eb835:	movabs $0x9e3779b97f4a7c15,%rcx
 10eb83f:	imul   %rcx,%rax
 10eb843:	mov    %rax,%r15
 10eb846:	shr    $0x20,%r15
 10eb84a:	xor    %rax,%r15
 10eb84d:	mov    0x28(%rsp),%rax
 10eb852:	mov    0x18(%rax),%rcx
 10eb856:	mov    0x8(%rcx),%rax
 10eb85a:	test   %rax,%rax
 10eb85d:	je     10eb910 <my.diagram_membership::compute_sub_block_attachments+0x1fe0>
 10eb863:	mov    (%rax),%ecx
 10eb865:	tzcnt  %ecx,%edx
 10eb869:	neg    %dl
 10eb86b:	shrx   %rdx,%r15,%r12
 10eb870:	vmovdqu 0x10(%rax,%r12,1),%xmm1
 10eb877:	mov    %r15d,%edx
 10eb87a:	and    $0x7f,%dl
 10eb87d:	vmovd  %edx,%xmm0
 10eb881:	vpbroadcastb %xmm0,%xmm0
 10eb886:	vmovdqa %xmm1,0x40(%rsp)
 10eb88c:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10eb890:	vpmovmskb %xmm0,%edx
 10eb894:	test   %edx,%edx
 10eb896:	je     10eb8f4 <my.diagram_membership::compute_sub_block_attachments+0x1fc4>
 10eb898:	lea    -0x1(%rcx),%ebp
 10eb89b:	add    $0x1e,%ecx
 10eb89e:	and    $0xfffffff0,%ecx
 10eb8a1:	lea    (%rax,%rcx,1),%r14
 10eb8a5:	add    $0x10,%r14
 10eb8a9:	movzwl %dx,%r13d
 10eb8ad:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb8bc:	nopl   0x0(%rax)
 10eb8c0:	tzcnt  %r13d,%eax
 10eb8c5:	add    %r12d,%eax
 10eb8c8:	and    %ebp,%eax
 10eb8ca:	mov    (%r14,%rax,4),%eax
 10eb8ce:	mov    0x28(%rsp),%rcx
 10eb8d3:	mov    0x20(%rcx,%rax,8),%rdi
 10eb8d8:	mov    0x130(%rsp),%rsi
 10eb8e0:	call   108e040 <myl_core_str_eq>
 10eb8e5:	test   %al,%al
 10eb8e7:	jne    10eb7b0 <my.diagram_membership::compute_sub_block_attachments+0x1e80>
 10eb8ed:	blsr   %r13d,%r13d
 10eb8f2:	jne    10eb8c0 <my.diagram_membership::compute_sub_block_attachments+0x1f90>
 10eb8f4:	vmovdqa 0x40(%rsp),%xmm0
 10eb8fa:	vpcmpeqb -0xe7542(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10eb902:	vpmovmskb %xmm0,%eax
 10eb906:	test   %eax,%eax
 10eb908:	jne    10eb9b0 <my.diagram_membership::compute_sub_block_attachments+0x2080>
 10eb90e:	jmp    10eb917 <my.diagram_membership::compute_sub_block_attachments+0x1fe7>
 10eb910:	cmpq   $0x0,0x18(%rcx)
 10eb915:	je     10eb93a <my.diagram_membership::compute_sub_block_attachments+0x200a>
 10eb917:	mov    0x28(%rsp),%rdi
 10eb91c:	lea    0x130(%rsp),%rsi
 10eb924:	mov    %r15,%rdx
 10eb927:	call   108c680 <myl_core_dict_find>
 10eb92c:	mov    %rax,%r12
 10eb92f:	test   %r12,%r12
 10eb932:	jns    10eb7b0 <my.diagram_membership::compute_sub_block_attachments+0x1e80>
 10eb938:	jmp    10eb9b0 <my.diagram_membership::compute_sub_block_attachments+0x2080>
 10eb93a:	mov    0x20(%rcx),%r14
 10eb93e:	test   %r14,%r14
 10eb941:	je     10eb9b0 <my.diagram_membership::compute_sub_block_attachments+0x2080>
 10eb943:	mov    0x10(%rcx),%r13
 10eb947:	xor    %r12d,%r12d
 10eb94a:	jmp    10eb988 <my.diagram_membership::compute_sub_block_attachments+0x2058>
 10eb94c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb95b:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb96a:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eb979:	nopl   0x0(%rax)
 10eb980:	inc    %r12
 10eb983:	cmp    %r12,%r14
 10eb986:	je     10eb9b0 <my.diagram_membership::compute_sub_block_attachments+0x2080>
 10eb988:	cmp    %r15,0x0(%r13,%r12,8)
 10eb98d:	jne    10eb980 <my.diagram_membership::compute_sub_block_attachments+0x2050>
 10eb98f:	mov    0x28(%rsp),%rax
 10eb994:	mov    0x20(%rax,%r12,8),%rdi
 10eb999:	mov    0x130(%rsp),%rsi
 10eb9a1:	call   108e040 <myl_core_str_eq>
 10eb9a6:	test   %al,%al
 10eb9a8:	je     10eb980 <my.diagram_membership::compute_sub_block_attachments+0x2050>
 10eb9aa:	jmp    10eb92f <my.diagram_membership::compute_sub_block_attachments+0x1fff>
 10eb9ac:	nopl   0x0(%rax)
 10eb9b0:	mov    %rbx,0x128(%rsp)
 10eb9b8:	testb  $0x2,0x1(%rbx)
 10eb9bc:	jne    10eb9d0 <my.diagram_membership::compute_sub_block_attachments+0x20a0>
 10eb9be:	mov    %rbx,%rdi
 10eb9c1:	call   108dec0 <myl_core_str_hash>
 10eb9c6:	jmp    10eb9d3 <my.diagram_membership::compute_sub_block_attachments+0x20a3>
 10eb9c8:	nopl   0x0(%rax,%rax,1)
 10eb9d0:	mov    0x18(%rbx),%eax
 10eb9d3:	mov    %eax,%eax
 10eb9d5:	movabs $0x9e3779b97f4a7c15,%rcx
 10eb9df:	imul   %rcx,%rax
 10eb9e3:	mov    %rax,%rbx
 10eb9e6:	shr    $0x20,%rbx
 10eb9ea:	xor    %rax,%rbx
 10eb9ed:	mov    0x8(%rsp),%rax
 10eb9f2:	mov    0x18(%rax),%rcx
 10eb9f6:	mov    0x8(%rcx),%rax
 10eb9fa:	test   %rax,%rax
 10eb9fd:	je     10ebaba <my.diagram_membership::compute_sub_block_attachments+0x218a>
 10eba03:	mov    (%rax),%ecx
 10eba05:	tzcnt  %ecx,%edx
 10eba09:	neg    %dl
 10eba0b:	shrx   %rdx,%rbx,%r12
 10eba10:	vmovdqu 0x10(%rax,%r12,1),%xmm1
 10eba17:	mov    %ebx,%edx
 10eba19:	and    $0x7f,%dl
 10eba1c:	vmovd  %edx,%xmm0
 10eba20:	vpbroadcastb %xmm0,%xmm0
 10eba25:	vmovdqa %xmm1,0x40(%rsp)
 10eba2b:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10eba2f:	vpmovmskb %xmm0,%edx
 10eba33:	test   %edx,%edx
 10eba35:	je     10eb790 <my.diagram_membership::compute_sub_block_attachments+0x1e60>
 10eba3b:	lea    -0x1(%rcx),%ebp
 10eba3e:	add    $0x1e,%ecx
 10eba41:	and    $0xfffffff0,%ecx
 10eba44:	lea    (%rax,%rcx,1),%r13
 10eba48:	add    $0x10,%r13
 10eba4c:	movzwl %dx,%r14d
 10eba50:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eba5f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eba6e:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eba7d:	nopl   (%rax)
 10eba80:	tzcnt  %r14d,%eax
 10eba85:	add    %r12d,%eax
 10eba88:	and    %ebp,%eax
 10eba8a:	mov    0x0(%r13,%rax,4),%r15d
 10eba8f:	shl    $0x4,%r15
 10eba93:	mov    0x8(%rsp),%rax
 10eba98:	mov    0x20(%rax,%r15,1),%rdi
 10eba9d:	mov    0x128(%rsp),%rsi
 10ebaa5:	call   108e040 <myl_core_str_eq>
 10ebaaa:	test   %al,%al
 10ebaac:	jne    10ebaea <my.diagram_membership::compute_sub_block_attachments+0x21ba>
 10ebaae:	blsr   %r14d,%r14d
 10ebab3:	jne    10eba80 <my.diagram_membership::compute_sub_block_attachments+0x2150>
 10ebab5:	jmp    10eb790 <my.diagram_membership::compute_sub_block_attachments+0x1e60>
 10ebaba:	cmpq   $0x0,0x18(%rcx)
 10ebabf:	je     10ebdef <my.diagram_membership::compute_sub_block_attachments+0x24bf>
 10ebac5:	mov    0x8(%rsp),%rdi
 10ebaca:	lea    0x128(%rsp),%rsi
 10ebad2:	mov    %rbx,%rdx
 10ebad5:	call   108c680 <myl_core_dict_find>
 10ebada:	mov    %rax,%r15
 10ebadd:	test   %r15,%r15
 10ebae0:	js     10eb7b0 <my.diagram_membership::compute_sub_block_attachments+0x1e80>
 10ebae6:	shl    $0x4,%r15
 10ebaea:	mov    0x8(%rsp),%rax
 10ebaef:	mov    0x28(%rax,%r15,1),%rax
 10ebaf4:	mov    %rax,0x40(%rsp)
 10ebaf9:	mov    0x8(%rax),%rsi
 10ebafd:	movabs $0x800000000000,%rax
 10ebb07:	cmp    %rax,%rsi
 10ebb0a:	ja     10ee397 <my.diagram_membership::compute_sub_block_attachments+0x4a67>
 10ebb10:	cmp    $0x1,%rsi
 10ebb14:	jne    10eb7b0 <my.diagram_membership::compute_sub_block_attachments+0x1e80>
 10ebb1a:	mov    0x60(%rsp),%rax
 10ebb1f:	mov    0x8(%rax),%rsi
 10ebb23:	mov    $0x1,%al
 10ebb25:	movabs $0x800000000000,%rcx
 10ebb2f:	jmp    10ebb7b <my.diagram_membership::compute_sub_block_attachments+0x224b>
 10ebb31:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebb40:	vmovdqa 0xb0(%rsp),%xmm0
 10ebb49:	vpcmpeqb -0xe7791(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10ebb51:	vpmovmskb %xmm0,%eax
 10ebb55:	test   %eax,%eax
 10ebb57:	je     10ebccb <my.diagram_membership::compute_sub_block_attachments+0x239b>
 10ebb5d:	mov    0x60(%rsp),%rax
 10ebb62:	mov    0x8(%rax),%rsi
 10ebb66:	xor    %eax,%eax
 10ebb68:	movabs $0x800000000000,%rcx
 10ebb72:	cmp    %rcx,%rsi
 10ebb75:	ja     10ee0f7 <my.diagram_membership::compute_sub_block_attachments+0x47c7>
 10ebb7b:	cmp    %rcx,%rsi
 10ebb7e:	ja     10ee0e9 <my.diagram_membership::compute_sub_block_attachments+0x47b9>
 10ebb84:	test   $0x1,%al
 10ebb86:	je     10eb7cc <my.diagram_membership::compute_sub_block_attachments+0x1e9c>
 10ebb8c:	mov    0x40(%rsp),%rbx
 10ebb91:	mov    %rbx,%rdi
 10ebb94:	xor    %esi,%esi
 10ebb96:	call   108d700 <myl_core_dict_ordinal>
 10ebb9b:	mov    0x20(%rbx,%rax,8),%rdi
 10ebba0:	mov    %rdi,0x120(%rsp)
 10ebba8:	testb  $0x2,0x1(%rdi)
 10ebbac:	jne    10ebbc0 <my.diagram_membership::compute_sub_block_attachments+0x2290>
 10ebbae:	call   108dec0 <myl_core_str_hash>
 10ebbb3:	jmp    10ebbc3 <my.diagram_membership::compute_sub_block_attachments+0x2293>
 10ebbb5:	data16 cs nopw 0x0(%rax,%rax,1)
 10ebbc0:	mov    0x18(%rdi),%eax
 10ebbc3:	mov    %eax,%eax
 10ebbc5:	movabs $0x9e3779b97f4a7c15,%rcx
 10ebbcf:	imul   %rcx,%rax
 10ebbd3:	mov    %rax,%r15
 10ebbd6:	shr    $0x20,%r15
 10ebbda:	xor    %rax,%r15
 10ebbdd:	mov    0x30(%rsp),%rax
 10ebbe2:	mov    0x18(%rax),%rcx
 10ebbe6:	mov    0x8(%rcx),%rax
 10ebbea:	test   %rax,%rax
 10ebbed:	je     10ebcc0 <my.diagram_membership::compute_sub_block_attachments+0x2390>
 10ebbf3:	mov    (%rax),%ecx
 10ebbf5:	tzcnt  %ecx,%edx
 10ebbf9:	neg    %dl
 10ebbfb:	shrx   %rdx,%r15,%r13
 10ebc00:	vmovdqu 0x10(%rax,%r13,1),%xmm1
 10ebc07:	mov    %r15d,%edx
 10ebc0a:	and    $0x7f,%dl
 10ebc0d:	vmovd  %edx,%xmm0
 10ebc11:	vpbroadcastb %xmm0,%xmm0
 10ebc16:	vmovdqa %xmm1,0xb0(%rsp)
 10ebc1f:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10ebc23:	vpmovmskb %xmm0,%edx
 10ebc27:	test   %edx,%edx
 10ebc29:	je     10ebb40 <my.diagram_membership::compute_sub_block_attachments+0x2210>
 10ebc2f:	lea    -0x1(%rcx),%ebp
 10ebc32:	add    $0x1e,%ecx
 10ebc35:	and    $0xfffffff0,%ecx
 10ebc38:	lea    (%rax,%rcx,1),%r14
 10ebc3c:	add    $0x10,%r14
 10ebc40:	movzwl %dx,%ebx
 10ebc43:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebc52:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebc61:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebc70:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebc7f:	nop
 10ebc80:	tzcnt  %ebx,%eax
 10ebc84:	add    %r13d,%eax
 10ebc87:	and    %ebp,%eax
 10ebc89:	mov    (%r14,%rax,4),%r12d
 10ebc8d:	shl    $0x4,%r12
 10ebc91:	mov    0x30(%rsp),%rax
 10ebc96:	mov    0x20(%rax,%r12,1),%rdi
 10ebc9b:	mov    0x120(%rsp),%rsi
 10ebca3:	call   108e040 <myl_core_str_eq>
 10ebca8:	test   %al,%al
 10ebcaa:	jne    10ebcf0 <my.diagram_membership::compute_sub_block_attachments+0x23c0>
 10ebcac:	blsr   %ebx,%ebx
 10ebcb1:	jne    10ebc80 <my.diagram_membership::compute_sub_block_attachments+0x2350>
 10ebcb3:	jmp    10ebb40 <my.diagram_membership::compute_sub_block_attachments+0x2210>
 10ebcb8:	nopl   0x0(%rax,%rax,1)
 10ebcc0:	cmpq   $0x0,0x18(%rcx)
 10ebcc5:	je     10ebd95 <my.diagram_membership::compute_sub_block_attachments+0x2465>
 10ebccb:	mov    0x30(%rsp),%rdi
 10ebcd0:	lea    0x120(%rsp),%rsi
 10ebcd8:	mov    %r15,%rdx
 10ebcdb:	call   108c680 <myl_core_dict_find>
 10ebce0:	mov    %rax,%r12
 10ebce3:	test   %r12,%r12
 10ebce6:	js     10ebb5d <my.diagram_membership::compute_sub_block_attachments+0x222d>
 10ebcec:	shl    $0x4,%r12
 10ebcf0:	mov    0x30(%rsp),%rax
 10ebcf5:	mov    0x28(%rax,%r12,1),%rsi
 10ebcfa:	cmp    0xe0(%rsp),%rsi
 10ebd02:	ja     10ee1b5 <my.diagram_membership::compute_sub_block_attachments+0x4885>
 10ebd08:	mov    %rsi,%rax
 10ebd0b:	mov    0x58(%rsp),%rdx
 10ebd10:	imul   %rdx,%rax
 10ebd14:	jo     10ee1d1 <my.diagram_membership::compute_sub_block_attachments+0x48a1>
 10ebd1a:	test   %rax,%rax
 10ebd1d:	js     10ee1a4 <my.diagram_membership::compute_sub_block_attachments+0x4874>
 10ebd23:	mov    %rax,%rsi
 10ebd26:	mov    0xd8(%rsp),%rdx
 10ebd2e:	add    %rdx,%rsi
 10ebd31:	jo     10ee195 <my.diagram_membership::compute_sub_block_attachments+0x4865>
 10ebd37:	js     10ee1c3 <my.diagram_membership::compute_sub_block_attachments+0x4893>
 10ebd3d:	mov    0x60(%rsp),%rax
 10ebd42:	mov    0x8(%rax),%rdx
 10ebd46:	cmp    %rdx,%rsi
 10ebd49:	jae    10edfde <my.diagram_membership::compute_sub_block_attachments+0x46ae>
 10ebd4f:	mov    0x20(%rax,%rsi,8),%rax
 10ebd54:	mov    %rax,%rcx
 10ebd57:	inc    %rcx
 10ebd5a:	jo     10ee1dd <my.diagram_membership::compute_sub_block_attachments+0x48ad>
 10ebd60:	movabs $0x8000000000000000,%rax
 10ebd6a:	cmp    %rax,%rcx
 10ebd6d:	je     10ee202 <my.diagram_membership::compute_sub_block_attachments+0x48d2>
 10ebd73:	mov    0x60(%rsp),%rax
 10ebd78:	mov    %rcx,0x20(%rax,%rsi,8)
 10ebd7d:	movabs $0x800000000000,%rax
 10ebd87:	cmp    %rax,%rdx
 10ebd8a:	jbe    10ebb5d <my.diagram_membership::compute_sub_block_attachments+0x222d>
 10ebd90:	jmp    10ee1f1 <my.diagram_membership::compute_sub_block_attachments+0x48c1>
 10ebd95:	mov    0x20(%rcx),%r13
 10ebd99:	test   %r13,%r13
 10ebd9c:	je     10ebb5d <my.diagram_membership::compute_sub_block_attachments+0x222d>
 10ebda2:	mov    0x10(%rcx),%r14
 10ebda6:	mov    0x88(%rsp),%rbx
 10ebdae:	xor    %r12d,%r12d
 10ebdb1:	jmp    10ebdd0 <my.diagram_membership::compute_sub_block_attachments+0x24a0>
 10ebdb3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebdc0:	inc    %r12
 10ebdc3:	add    $0x10,%rbx
 10ebdc7:	cmp    %r12,%r13
 10ebdca:	je     10ebb5d <my.diagram_membership::compute_sub_block_attachments+0x222d>
 10ebdd0:	cmp    %r15,(%r14,%r12,8)
 10ebdd4:	jne    10ebdc0 <my.diagram_membership::compute_sub_block_attachments+0x2490>
 10ebdd6:	mov    (%rbx),%rdi
 10ebdd9:	mov    0x120(%rsp),%rsi
 10ebde1:	call   108e040 <myl_core_str_eq>
 10ebde6:	test   %al,%al
 10ebde8:	je     10ebdc0 <my.diagram_membership::compute_sub_block_attachments+0x2490>
 10ebdea:	jmp    10ebce3 <my.diagram_membership::compute_sub_block_attachments+0x23b3>
 10ebdef:	mov    0x20(%rcx),%r12
 10ebdf3:	test   %r12,%r12
 10ebdf6:	je     10eb7b0 <my.diagram_membership::compute_sub_block_attachments+0x1e80>
 10ebdfc:	mov    0x10(%rcx),%r14
 10ebe00:	mov    0xf8(%rsp),%r13
 10ebe08:	xor    %r15d,%r15d
 10ebe0b:	jmp    10ebe50 <my.diagram_membership::compute_sub_block_attachments+0x2520>
 10ebe0d:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebe1c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebe2b:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebe3a:	nopw   0x0(%rax,%rax,1)
 10ebe40:	inc    %r15
 10ebe43:	add    $0x10,%r13
 10ebe47:	cmp    %r15,%r12
 10ebe4a:	je     10eb7b0 <my.diagram_membership::compute_sub_block_attachments+0x1e80>
 10ebe50:	cmp    %rbx,(%r14,%r15,8)
 10ebe54:	jne    10ebe40 <my.diagram_membership::compute_sub_block_attachments+0x2510>
 10ebe56:	mov    0x0(%r13),%rdi
 10ebe5a:	mov    0x128(%rsp),%rsi
 10ebe62:	call   108e040 <myl_core_str_eq>
 10ebe67:	test   %al,%al
 10ebe69:	je     10ebe40 <my.diagram_membership::compute_sub_block_attachments+0x2510>
 10ebe6b:	jmp    10ebadd <my.diagram_membership::compute_sub_block_attachments+0x21ad>
 10ebe70:	mov    0x8(%rsp),%rdi
 10ebe75:	call   1086200 <myl_core_drop_owned>
 10ebe7a:	mov    0x30(%rsp),%rdi
 10ebe7f:	call   1086200 <myl_core_drop_owned>
 10ebe84:	mov    0x28(%rsp),%rdi
 10ebe89:	call   1086200 <myl_core_drop_owned>
 10ebe8e:	mov    0xc0(%rsp),%rcx
 10ebe96:	mov    0x8(%rcx),%rdx
 10ebe9a:	movabs $0x800000000000,%rax
 10ebea4:	cmp    %rax,%rdx
 10ebea7:	ja     10ee090 <my.diagram_membership::compute_sub_block_attachments+0x4760>
 10ebead:	lea    0x20(%rcx),%rax
 10ebeb1:	mov    %rax,0xf0(%rsp)
 10ebeb9:	mov    0x70(%rsp),%rax
 10ebebe:	add    $0x20,%rax
 10ebec2:	mov    %rax,0xf8(%rsp)
 10ebeca:	xor    %r8d,%r8d
 10ebecd:	lea    -0x777dc(%rip),%rbp        # 10746f8 <core_number_pairs+0x6d028>
 10ebed4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebee0:	cmp    0xe8(%rsp),%r8
 10ebee8:	jge    10edfea <my.diagram_membership::compute_sub_block_attachments+0x46ba>
 10ebeee:	mov    0xc8(%rsp),%rax
 10ebef6:	mov    0x8(%rax),%rdx
 10ebefa:	cmp    %rdx,%r8
 10ebefd:	jae    10ee081 <my.diagram_membership::compute_sub_block_attachments+0x4751>
 10ebf03:	mov    %r8,0x88(%rsp)
 10ebf0b:	imul   $0x428,%r8,%rax
 10ebf12:	mov    0x178(%rsp),%rcx
 10ebf1a:	mov    (%rcx,%rax,1),%rbx
 10ebf1e:	mov    %rbx,%rdi
 10ebf21:	call   1095500 <myl_core_bytes_utf8_count>
 10ebf26:	test   %rax,%rax
 10ebf29:	js     10edfb0 <my.diagram_membership::compute_sub_block_attachments+0x4680>
 10ebf2f:	mov    %rbx,%rdi
 10ebf32:	call   10955c0 <myl_core_bytes_decode_text>
 10ebf37:	mov    %rax,%rdi
 10ebf3a:	xor    %eax,%eax
 10ebf3c:	test   %al,%al
 10ebf3e:	jne    10edfcd <my.diagram_membership::compute_sub_block_attachments+0x469d>
 10ebf44:	mov    %rdi,0x118(%rsp)
 10ebf4c:	testb  $0x2,0x1(%rdi)
 10ebf50:	mov    %rdi,0x10(%rsp)
 10ebf55:	jne    10ebf60 <my.diagram_membership::compute_sub_block_attachments+0x2630>
 10ebf57:	call   108dec0 <myl_core_str_hash>
 10ebf5c:	jmp    10ebf63 <my.diagram_membership::compute_sub_block_attachments+0x2633>
 10ebf5e:	xchg   %ax,%ax
 10ebf60:	mov    0x18(%rdi),%eax
 10ebf63:	mov    %eax,%eax
 10ebf65:	movabs $0x9e3779b97f4a7c15,%rcx
 10ebf6f:	imul   %rcx,%rax
 10ebf73:	mov    %rax,%r14
 10ebf76:	shr    $0x20,%r14
 10ebf7a:	xor    %rax,%r14
 10ebf7d:	mov    0x70(%rsp),%rax
 10ebf82:	mov    0x18(%rax),%rcx
 10ebf86:	mov    0x8(%rcx),%rax
 10ebf8a:	test   %rax,%rax
 10ebf8d:	je     10ec070 <my.diagram_membership::compute_sub_block_attachments+0x2740>
 10ebf93:	mov    (%rax),%ecx
 10ebf95:	tzcnt  %ecx,%edx
 10ebf99:	neg    %dl
 10ebf9b:	shrx   %rdx,%r14,%r12
 10ebfa0:	vmovdqu 0x10(%rax,%r12,1),%xmm1
 10ebfa7:	mov    %r14d,%edx
 10ebfaa:	and    $0x7f,%dl
 10ebfad:	vmovd  %edx,%xmm0
 10ebfb1:	vpbroadcastb %xmm0,%xmm0
 10ebfb6:	vmovdqa %xmm1,0x30(%rsp)
 10ebfbc:	vpcmpeqb %xmm0,%xmm1,%xmm0
 10ebfc0:	vpmovmskb %xmm0,%edx
 10ebfc4:	test   %edx,%edx
 10ebfc6:	je     10ec038 <my.diagram_membership::compute_sub_block_attachments+0x2708>
 10ebfc8:	lea    -0x1(%rcx),%ebp
 10ebfcb:	add    $0x1e,%ecx
 10ebfce:	and    $0xfffffff0,%ecx
 10ebfd1:	lea    (%rax,%rcx,1),%r13
 10ebfd5:	add    $0x10,%r13
 10ebfd9:	movzwl %dx,%ebx
 10ebfdc:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebfeb:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ebffa:	nopw   0x0(%rax,%rax,1)
 10ec000:	tzcnt  %ebx,%eax
 10ec004:	add    %r12d,%eax
 10ec007:	and    %ebp,%eax
 10ec009:	mov    0x0(%r13,%rax,4),%r15d
 10ec00e:	shl    $0x4,%r15
 10ec012:	mov    0x70(%rsp),%rax
 10ec017:	mov    0x20(%rax,%r15,1),%rdi
 10ec01c:	mov    0x118(%rsp),%rsi
 10ec024:	call   108e040 <myl_core_str_eq>
 10ec029:	test   %al,%al
 10ec02b:	jne    10edea0 <my.diagram_membership::compute_sub_block_attachments+0x4570>
 10ec031:	blsr   %ebx,%ebx
 10ec036:	jne    10ec000 <my.diagram_membership::compute_sub_block_attachments+0x26d0>
 10ec038:	vmovdqa 0x30(%rsp),%xmm0
 10ec03e:	vpcmpeqb -0xe7c86(%rip),%xmm0,%xmm0        # 10043c0 <__anon_2214+0x50>
 10ec046:	vpmovmskb %xmm0,%eax
 10ec04a:	test   %eax,%eax
 10ec04c:	lea    -0x7795b(%rip),%rbp        # 10746f8 <core_number_pairs+0x6d028>
 10ec053:	je     10ec07b <my.diagram_membership::compute_sub_block_attachments+0x274b>
 10ec055:	mov    0x10(%rsp),%rdi
 10ec05a:	call   1086200 <myl_core_drop_owned>
 10ec05f:	jmp    10ec0c0 <my.diagram_membership::compute_sub_block_attachments+0x2790>
 10ec061:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ec070:	cmpq   $0x0,0x18(%rcx)
 10ec075:	je     10edf5f <my.diagram_membership::compute_sub_block_attachments+0x462f>
 10ec07b:	mov    0x70(%rsp),%rdi
 10ec080:	lea    0x118(%rsp),%rsi
 10ec088:	mov    %r14,%rdx
 10ec08b:	call   108c680 <myl_core_dict_find>
 10ec090:	mov    %rax,%r15
 10ec093:	mov    0x10(%rsp),%rdi
 10ec098:	call   1086200 <myl_core_drop_owned>
 10ec09d:	test   %r15,%r15
 10ec0a0:	js     10ec0c0 <my.diagram_membership::compute_sub_block_attachments+0x2790>
 10ec0a2:	shl    $0x4,%r15
 10ec0a6:	mov    0xc0(%rsp),%rcx
 10ec0ae:	mov    0x88(%rsp),%r8
 10ec0b6:	jmp    10edec1 <my.diagram_membership::compute_sub_block_attachments+0x4591>
 10ec0bb:	nopl   0x0(%rax,%rax,1)
 10ec0c0:	mov    0x88(%rsp),%r11
 10ec0c8:	mov    0x58(%rsp),%r10
 10ec0cd:	imul   %r10,%r11
 10ec0d1:	seto   0xd0(%rsp)
 10ec0d9:	mov    $0x1,%r12b
 10ec0dc:	xor    %ebx,%ebx
 10ec0de:	movq   $0x0,0x40(%rsp)
 10ec0e7:	xor    %r15d,%r15d
 10ec0ea:	xor    %r13d,%r13d
 10ec0ed:	mov    0x60(%rsp),%rcx
 10ec0f2:	mov    %r11,0x108(%rsp)
 10ec0fa:	jmp    10ec16e <my.diagram_membership::compute_sub_block_attachments+0x283e>
 10ec0fc:	nopl   0x0(%rax)
 10ec100:	mov    %rbp,%r9
 10ec103:	cmp    $0x4,%r14b
 10ec107:	sete   %r14b
 10ec10b:	mov    0x40(%rsp),%rdi
 10ec110:	mov    0x28(%rsp),%r8
 10ec115:	cmp    %rdi,%r8
 10ec118:	setg   %al
 10ec11b:	sete   %cl
 10ec11e:	and    %r12b,%cl
 10ec121:	movzbl %r14b,%esi
 10ec125:	xor    $0x1,%r14b
 10ec129:	and    %cl,%r14b
 10ec12c:	or     %al,%r14b
 10ec12f:	cmovne %r8,%rdi
 10ec133:	mov    %rdi,0x40(%rsp)
 10ec138:	movzbl %r12b,%r12d
 10ec13c:	cmovne %esi,%r12d
 10ec140:	cmovne %r13,%r15
 10ec144:	movzbl %bl,%ebx
 10ec147:	mov    $0x1,%eax
 10ec14c:	cmovne %eax,%ebx
 10ec14f:	mov    0x60(%rsp),%rcx
 10ec154:	mov    %r9,%rbp
 10ec157:	movabs $0x800000000000,%rsi
 10ec161:	cmp    %rsi,%r13
 10ec164:	lea    0x1(%r13),%r13
 10ec168:	je     10ee386 <my.diagram_membership::compute_sub_block_attachments+0x4a56>
 10ec16e:	cmp    %r10,%r13
 10ec171:	je     10ede40 <my.diagram_membership::compute_sub_block_attachments+0x4510>
 10ec177:	cmpb   $0x0,0xd0(%rsp)
 10ec17f:	jne    10ee33e <my.diagram_membership::compute_sub_block_attachments+0x4a0e>
 10ec185:	test   %r11,%r11
 10ec188:	js     10ee355 <my.diagram_membership::compute_sub_block_attachments+0x4a25>
 10ec18e:	mov    %r11,%rsi
 10ec191:	add    %r13,%rsi
 10ec194:	jo     10ee366 <my.diagram_membership::compute_sub_block_attachments+0x4a36>
 10ec19a:	js     10ee378 <my.diagram_membership::compute_sub_block_attachments+0x4a48>
 10ec1a0:	mov    0x8(%rcx),%rdx
 10ec1a4:	cmp    %rdx,%rsi
 10ec1a7:	jae    10ee01b <my.diagram_membership::compute_sub_block_attachments+0x46eb>
 10ec1ad:	mov    0x20(%rcx,%rsi,8),%rax
 10ec1b2:	test   %rax,%rax
 10ec1b5:	jle    10ec157 <my.diagram_membership::compute_sub_block_attachments+0x2827>
 10ec1b7:	mov    %rax,0x28(%rsp)
 10ec1bc:	mov    0x80(%rsp),%rax
 10ec1c4:	mov    0x8(%rax),%rdx
 10ec1c8:	cmp    %rdx,%r13
 10ec1cb:	jae    10ee027 <my.diagram_membership::compute_sub_block_attachments+0x46f7>
 10ec1d1:	mov    %r12d,0x90(%rsp)
 10ec1d9:	mov    %r15,0xa0(%rsp)
 10ec1e1:	mov    %rbx,0xb0(%rsp)
 10ec1e9:	imul   $0x70,%r13,%rax
 10ec1ed:	mov    0x100(%rsp),%rcx
 10ec1f5:	mov    (%rcx,%rax,1),%rdx
 10ec1f9:	mov    %rdx,0x10(%rsp)
 10ec1fe:	mov    0x20(%rcx,%rax,1),%rcx
 10ec203:	mov    0x8(%rcx),%rbx
 10ec207:	mov    %fs:0xfffffffffffffef0,%r15
 10ec210:	test   %r15,%r15
 10ec213:	je     10ece9c <my.diagram_membership::compute_sub_block_attachments+0x356c>
 10ec219:	mov    (%r15),%rax
 10ec21c:	mov    %rax,%fs:0xfffffffffffffef0
 10ec225:	movl   $0x6000000,(%r15)
 10ec22c:	movq   $0x0,0x8(%r15)
 10ec234:	movq   $0xa,0x10(%r15)
 10ec23c:	lea    -0x76bd3(%rip),%rax        # 1075670 <core_number_pairs+0x6dfa0>
 10ec243:	mov    %rax,0x18(%r15)
 10ec247:	mov    %rcx,0x8(%rsp)
 10ec24c:	mov    %fs:0xfffffffffffffed8,%rax
 10ec255:	test   %rax,%rax
 10ec258:	je     10eced1 <my.diagram_membership::compute_sub_block_attachments+0x35a1>
 10ec25e:	mov    (%rax),%rcx
 10ec261:	mov    %rcx,%fs:0xfffffffffffffed8
 10ec26a:	movl   $0x3000000,(%rax)
 10ec270:	movq   $0x0,0x8(%rax)
 10ec278:	movq   $0x8,0x10(%rax)
 10ec280:	mov    %rbp,0x18(%rax)
 10ec284:	mov    $0x8,%ecx
 10ec289:	lea    -0x82110(%rip),%rdx        # 106a180 <core_number_pairs+0x62ab0>
 10ec290:	mov    %rdx,0x20(%rax)
 10ec294:	movq   $0x1,0x8(%rax)
 10ec29c:	cmp    $0x2,%rcx
 10ec2a0:	jb     10ecf3a <my.diagram_membership::compute_sub_block_attachments+0x360a>
 10ec2a6:	lea    -0x820ed(%rip),%rdx        # 106a1c0 <core_number_pairs+0x62af0>
 10ec2ad:	mov    %rdx,0x28(%rax)
 10ec2b1:	movq   $0x2,0x8(%rax)
 10ec2b9:	cmp    $0x3,%rcx
 10ec2bd:	jb     10ecf77 <my.diagram_membership::compute_sub_block_attachments+0x3647>
 10ec2c3:	lea    -0x820ca(%rip),%rdx        # 106a200 <core_number_pairs+0x62b30>
 10ec2ca:	mov    %rdx,0x30(%rax)
 10ec2ce:	movq   $0x3,0x8(%rax)
 10ec2d6:	cmp    $0x4,%rcx
 10ec2da:	jb     10ecfb4 <my.diagram_membership::compute_sub_block_attachments+0x3684>
 10ec2e0:	lea    -0x820a7(%rip),%rdx        # 106a240 <core_number_pairs+0x62b70>
 10ec2e7:	mov    %rdx,0x38(%rax)
 10ec2eb:	movq   $0x4,0x8(%rax)
 10ec2f3:	cmp    $0x5,%rcx
 10ec2f7:	jb     10ecff1 <my.diagram_membership::compute_sub_block_attachments+0x36c1>
 10ec2fd:	lea    -0x82084(%rip),%rdx        # 106a280 <core_number_pairs+0x62bb0>
 10ec304:	mov    %rdx,0x40(%rax)
 10ec308:	movq   $0x5,0x8(%rax)
 10ec310:	cmp    $0x6,%rcx
 10ec314:	jb     10ed02e <my.diagram_membership::compute_sub_block_attachments+0x36fe>
 10ec31a:	lea    -0x82061(%rip),%rdx        # 106a2c0 <core_number_pairs+0x62bf0>
 10ec321:	mov    %rdx,0x48(%rax)
 10ec325:	movq   $0x6,0x8(%rax)
 10ec32d:	cmp    $0x7,%rcx
 10ec331:	jb     10ed06b <my.diagram_membership::compute_sub_block_attachments+0x373b>
 10ec337:	lea    -0x8203e(%rip),%rdx        # 106a300 <core_number_pairs+0x62c30>
 10ec33e:	mov    %rdx,0x50(%rax)
 10ec342:	movq   $0x7,0x8(%rax)
 10ec34a:	cmp    $0x8,%rcx
 10ec34e:	jb     10ed0a8 <my.diagram_membership::compute_sub_block_attachments+0x3778>
 10ec354:	lea    -0x8201b(%rip),%rcx        # 106a340 <core_number_pairs+0x62c70>
 10ec35b:	mov    %rcx,0x58(%rax)
 10ec35f:	movq   $0x8,0x8(%rax)
 10ec367:	mov    0x8(%r15),%rcx
 10ec36b:	cmp    0x10(%r15),%rcx
 10ec36f:	mov    %rbx,0x110(%rsp)
 10ec377:	jae    10ed0dc <my.diagram_membership::compute_sub_block_attachments+0x37ac>
 10ec37d:	mov    %rcx,%rdx
 10ec380:	shl    $0x4,%rdx
 10ec384:	movq   $0x0,0x20(%r15,%rdx,1)
 10ec38d:	mov    %rax,0x28(%r15,%rdx,1)
 10ec392:	lea    0x1(%rcx),%rsi
 10ec396:	mov    %rsi,0x8(%r15)
 10ec39a:	test   %rcx,%rcx
 10ec39d:	jne    10ee3eb <my.diagram_membership::compute_sub_block_attachments+0x4abb>
 10ec3a3:	mov    %fs:0xfffffffffffffed8,%rax
 10ec3ac:	test   %rax,%rax
 10ec3af:	je     10ed0fb <my.diagram_membership::compute_sub_block_attachments+0x37cb>
 10ec3b5:	mov    (%rax),%rcx
 10ec3b8:	mov    %rcx,%fs:0xfffffffffffffed8
 10ec3c1:	movl   $0x3000000,(%rax)
 10ec3c7:	movq   $0x0,0x8(%rax)
 10ec3cf:	movq   $0x8,0x10(%rax)
 10ec3d7:	mov    %rbp,0x18(%rax)
 10ec3db:	mov    $0x8,%ecx
 10ec3e0:	lea    -0x82067(%rip),%rdx        # 106a380 <core_number_pairs+0x62cb0>
 10ec3e7:	mov    %rdx,0x20(%rax)
 10ec3eb:	movq   $0x1,0x8(%rax)
 10ec3f3:	cmp    $0x2,%rcx
 10ec3f7:	jb     10ed164 <my.diagram_membership::compute_sub_block_attachments+0x3834>
 10ec3fd:	lea    -0x82044(%rip),%rdx        # 106a3c0 <core_number_pairs+0x62cf0>
 10ec404:	mov    %rdx,0x28(%rax)
 10ec408:	movq   $0x2,0x8(%rax)
 10ec410:	cmp    $0x3,%rcx
 10ec414:	jb     10ed1a1 <my.diagram_membership::compute_sub_block_attachments+0x3871>
 10ec41a:	lea    -0x82021(%rip),%rdx        # 106a400 <core_number_pairs+0x62d30>
 10ec421:	mov    %rdx,0x30(%rax)
 10ec425:	movq   $0x3,0x8(%rax)
 10ec42d:	cmp    $0x4,%rcx
 10ec431:	jb     10ed1de <my.diagram_membership::compute_sub_block_attachments+0x38ae>
 10ec437:	lea    -0x81ffe(%rip),%rdx        # 106a440 <core_number_pairs+0x62d70>
 10ec43e:	mov    %rdx,0x38(%rax)
 10ec442:	movq   $0x4,0x8(%rax)
 10ec44a:	cmp    $0x5,%rcx
 10ec44e:	jb     10ed21b <my.diagram_membership::compute_sub_block_attachments+0x38eb>
 10ec454:	lea    -0x81fdb(%rip),%rdx        # 106a480 <core_number_pairs+0x62db0>
 10ec45b:	mov    %rdx,0x40(%rax)
 10ec45f:	movq   $0x5,0x8(%rax)
 10ec467:	cmp    $0x6,%rcx
 10ec46b:	jb     10ed258 <my.diagram_membership::compute_sub_block_attachments+0x3928>
 10ec471:	lea    -0x81fb8(%rip),%rdx        # 106a4c0 <core_number_pairs+0x62df0>
 10ec478:	mov    %rdx,0x48(%rax)
 10ec47c:	movq   $0x6,0x8(%rax)
 10ec484:	cmp    $0x7,%rcx
 10ec488:	jb     10ed295 <my.diagram_membership::compute_sub_block_attachments+0x3965>
 10ec48e:	lea    -0x81f95(%rip),%rcx        # 106a500 <core_number_pairs+0x62e30>
 10ec495:	mov    %rcx,0x50(%rax)
 10ec499:	movq   $0x7,0x8(%rax)
 10ec4a1:	mov    0x8(%r15),%rcx
 10ec4a5:	cmp    0x10(%r15),%rcx
 10ec4a9:	jae    10ed2c9 <my.diagram_membership::compute_sub_block_attachments+0x3999>
 10ec4af:	mov    %rcx,%rdx
 10ec4b2:	shl    $0x4,%rdx
 10ec4b6:	movq   $0x1,0x20(%r15,%rdx,1)
 10ec4bf:	mov    %rax,0x28(%r15,%rdx,1)
 10ec4c4:	lea    0x1(%rcx),%rsi
 10ec4c8:	mov    %rsi,0x8(%r15)
 10ec4cc:	cmp    $0x1,%rcx
 10ec4d0:	jne    10ee4bd <my.diagram_membership::compute_sub_block_attachments+0x4b8d>
 10ec4d6:	mov    %fs:0xfffffffffffffed8,%rax
 10ec4df:	test   %rax,%rax
 10ec4e2:	je     10ed2e8 <my.diagram_membership::compute_sub_block_attachments+0x39b8>
 10ec4e8:	mov    (%rax),%rcx
 10ec4eb:	mov    %rcx,%fs:0xfffffffffffffed8
 10ec4f4:	movl   $0x3000000,(%rax)
 10ec4fa:	movq   $0x0,0x8(%rax)
 10ec502:	movq   $0x8,0x10(%rax)
 10ec50a:	mov    %rbp,0x18(%rax)
 10ec50e:	mov    $0x8,%ecx
 10ec513:	lea    -0x81fda(%rip),%rdx        # 106a540 <core_number_pairs+0x62e70>
 10ec51a:	mov    %rdx,0x20(%rax)
 10ec51e:	movq   $0x1,0x8(%rax)
 10ec526:	cmp    $0x2,%rcx
 10ec52a:	jb     10ed351 <my.diagram_membership::compute_sub_block_attachments+0x3a21>
 10ec530:	lea    -0x81fb7(%rip),%rdx        # 106a580 <core_number_pairs+0x62eb0>
 10ec537:	mov    %rdx,0x28(%rax)
 10ec53b:	movq   $0x2,0x8(%rax)
 10ec543:	cmp    $0x3,%rcx
 10ec547:	jb     10ed38e <my.diagram_membership::compute_sub_block_attachments+0x3a5e>
 10ec54d:	lea    -0x81f94(%rip),%rdx        # 106a5c0 <core_number_pairs+0x62ef0>
 10ec554:	mov    %rdx,0x30(%rax)
 10ec558:	movq   $0x3,0x8(%rax)
 10ec560:	cmp    $0x4,%rcx
 10ec564:	jb     10ed3cb <my.diagram_membership::compute_sub_block_attachments+0x3a9b>
 10ec56a:	lea    -0x81f71(%rip),%rdx        # 106a600 <core_number_pairs+0x62f30>
 10ec571:	mov    %rdx,0x38(%rax)
 10ec575:	movq   $0x4,0x8(%rax)
 10ec57d:	cmp    $0x5,%rcx
 10ec581:	jb     10ed408 <my.diagram_membership::compute_sub_block_attachments+0x3ad8>
 10ec587:	lea    -0x81f4e(%rip),%rcx        # 106a640 <core_number_pairs+0x62f70>
 10ec58e:	mov    %rcx,0x40(%rax)
 10ec592:	movq   $0x5,0x8(%rax)
 10ec59a:	mov    0x8(%r15),%rcx
 10ec59e:	cmp    0x10(%r15),%rcx
 10ec5a2:	jae    10ed43c <my.diagram_membership::compute_sub_block_attachments+0x3b0c>
 10ec5a8:	mov    %rcx,%rdx
 10ec5ab:	shl    $0x4,%rdx
 10ec5af:	movq   $0x2,0x20(%r15,%rdx,1)
 10ec5b8:	mov    %rax,0x28(%r15,%rdx,1)
 10ec5bd:	lea    0x1(%rcx),%rsi
 10ec5c1:	mov    %rsi,0x8(%r15)
 10ec5c5:	cmp    $0x2,%rcx
 10ec5c9:	jne    10ee4d9 <my.diagram_membership::compute_sub_block_attachments+0x4ba9>
 10ec5cf:	mov    %fs:0xfffffffffffffed8,%rax
 10ec5d8:	test   %rax,%rax
 10ec5db:	je     10ed45b <my.diagram_membership::compute_sub_block_attachments+0x3b2b>
 10ec5e1:	mov    (%rax),%rcx
 10ec5e4:	mov    %rcx,%fs:0xfffffffffffffed8
 10ec5ed:	movl   $0x3000000,(%rax)
 10ec5f3:	movq   $0x0,0x8(%rax)
 10ec5fb:	movq   $0x8,0x10(%rax)
 10ec603:	mov    %rbp,0x18(%rax)
 10ec607:	mov    $0x8,%ecx
 10ec60c:	lea    -0x81f93(%rip),%rdx        # 106a680 <core_number_pairs+0x62fb0>
 10ec613:	mov    %rdx,0x20(%rax)
 10ec617:	movq   $0x1,0x8(%rax)
 10ec61f:	cmp    $0x2,%rcx
 10ec623:	jb     10ed4c4 <my.diagram_membership::compute_sub_block_attachments+0x3b94>
 10ec629:	lea    -0x81f70(%rip),%rdx        # 106a6c0 <core_number_pairs+0x62ff0>
 10ec630:	mov    %rdx,0x28(%rax)
 10ec634:	movq   $0x2,0x8(%rax)
 10ec63c:	cmp    $0x3,%rcx
 10ec640:	jb     10ed501 <my.diagram_membership::compute_sub_block_attachments+0x3bd1>
 10ec646:	lea    -0x81f4d(%rip),%rdx        # 106a700 <core_number_pairs+0x63030>
 10ec64d:	mov    %rdx,0x30(%rax)
 10ec651:	movq   $0x3,0x8(%rax)
 10ec659:	cmp    $0x4,%rcx
 10ec65d:	jb     10ed53e <my.diagram_membership::compute_sub_block_attachments+0x3c0e>
 10ec663:	lea    -0x81f2a(%rip),%rdx        # 106a740 <core_number_pairs+0x63070>
 10ec66a:	mov    %rdx,0x38(%rax)
 10ec66e:	movq   $0x4,0x8(%rax)
 10ec676:	cmp    $0x5,%rcx
 10ec67a:	jb     10ed57b <my.diagram_membership::compute_sub_block_attachments+0x3c4b>
 10ec680:	lea    -0x81f07(%rip),%rdx        # 106a780 <core_number_pairs+0x630b0>
 10ec687:	mov    %rdx,0x40(%rax)
 10ec68b:	movq   $0x5,0x8(%rax)
 10ec693:	cmp    $0x6,%rcx
 10ec697:	jb     10ed5b8 <my.diagram_membership::compute_sub_block_attachments+0x3c88>
 10ec69d:	lea    -0x81ee4(%rip),%rcx        # 106a7c0 <core_number_pairs+0x630f0>
 10ec6a4:	mov    %rcx,0x48(%rax)
 10ec6a8:	movq   $0x6,0x8(%rax)
 10ec6b0:	mov    0x8(%r15),%rcx
 10ec6b4:	cmp    0x10(%r15),%rcx
 10ec6b8:	jae    10ed5ec <my.diagram_membership::compute_sub_block_attachments+0x3cbc>
 10ec6be:	mov    %rcx,%rdx
 10ec6c1:	shl    $0x4,%rdx
 10ec6c5:	movq   $0x5,0x20(%r15,%rdx,1)
 10ec6ce:	mov    %rax,0x28(%r15,%rdx,1)
 10ec6d3:	lea    0x1(%rcx),%rsi
 10ec6d7:	mov    %rsi,0x8(%r15)
 10ec6db:	cmp    $0x3,%rcx
 10ec6df:	jne    10ee6a7 <my.diagram_membership::compute_sub_block_attachments+0x4d77>
 10ec6e5:	mov    %fs:0xfffffffffffffed8,%rax
 10ec6ee:	test   %rax,%rax
 10ec6f1:	je     10ed60b <my.diagram_membership::compute_sub_block_attachments+0x3cdb>
 10ec6f7:	mov    (%rax),%rcx
 10ec6fa:	mov    %rcx,%fs:0xfffffffffffffed8
 10ec703:	movl   $0x3000000,(%rax)
 10ec709:	movq   $0x0,0x8(%rax)
 10ec711:	movq   $0x8,0x10(%rax)
 10ec719:	mov    %rbp,0x18(%rax)
 10ec71d:	mov    $0x8,%ecx
 10ec722:	lea    -0x81f29(%rip),%rdx        # 106a800 <core_number_pairs+0x63130>
 10ec729:	mov    %rdx,0x20(%rax)
 10ec72d:	movq   $0x1,0x8(%rax)
 10ec735:	cmp    $0x2,%rcx
 10ec739:	jb     10ed674 <my.diagram_membership::compute_sub_block_attachments+0x3d44>
 10ec73f:	lea    -0x81f06(%rip),%rdx        # 106a840 <core_number_pairs+0x63170>
 10ec746:	mov    %rdx,0x28(%rax)
 10ec74a:	movq   $0x2,0x8(%rax)
 10ec752:	cmp    $0x3,%rcx
 10ec756:	jb     10ed6b1 <my.diagram_membership::compute_sub_block_attachments+0x3d81>
 10ec75c:	lea    -0x81ee3(%rip),%rdx        # 106a880 <core_number_pairs+0x631b0>
 10ec763:	mov    %rdx,0x30(%rax)
 10ec767:	movq   $0x3,0x8(%rax)
 10ec76f:	cmp    $0x4,%rcx
 10ec773:	jb     10ed6ee <my.diagram_membership::compute_sub_block_attachments+0x3dbe>
 10ec779:	lea    -0x81ec0(%rip),%rdx        # 106a8c0 <core_number_pairs+0x631f0>
 10ec780:	mov    %rdx,0x38(%rax)
 10ec784:	movq   $0x4,0x8(%rax)
 10ec78c:	cmp    $0x5,%rcx
 10ec790:	jb     10ed72b <my.diagram_membership::compute_sub_block_attachments+0x3dfb>
 10ec796:	lea    -0x81e9d(%rip),%rdx        # 106a900 <core_number_pairs+0x63230>
 10ec79d:	mov    %rdx,0x40(%rax)
 10ec7a1:	movq   $0x5,0x8(%rax)
 10ec7a9:	cmp    $0x6,%rcx
 10ec7ad:	jb     10ed768 <my.diagram_membership::compute_sub_block_attachments+0x3e38>
 10ec7b3:	lea    -0x81e7a(%rip),%rcx        # 106a940 <core_number_pairs+0x63270>
 10ec7ba:	mov    %rcx,0x48(%rax)
 10ec7be:	movq   $0x6,0x8(%rax)
 10ec7c6:	mov    0x8(%r15),%rcx
 10ec7ca:	cmp    0x10(%r15),%rcx
 10ec7ce:	jae    10ed79c <my.diagram_membership::compute_sub_block_attachments+0x3e6c>
 10ec7d4:	mov    %rcx,%rdx
 10ec7d7:	shl    $0x4,%rdx
 10ec7db:	movq   $0x6,0x20(%r15,%rdx,1)
 10ec7e4:	mov    %rax,0x28(%r15,%rdx,1)
 10ec7e9:	lea    0x1(%rcx),%rsi
 10ec7ed:	mov    %rsi,0x8(%r15)
 10ec7f1:	cmp    $0x4,%rcx
 10ec7f5:	jne    10ee629 <my.diagram_membership::compute_sub_block_attachments+0x4cf9>
 10ec7fb:	mov    %fs:0xfffffffffffffed8,%rax
 10ec804:	test   %rax,%rax
 10ec807:	je     10ed7bb <my.diagram_membership::compute_sub_block_attachments+0x3e8b>
 10ec80d:	mov    (%rax),%rcx
 10ec810:	mov    %rcx,%fs:0xfffffffffffffed8
 10ec819:	movl   $0x3000000,(%rax)
 10ec81f:	movq   $0x0,0x8(%rax)
 10ec827:	movq   $0x8,0x10(%rax)
 10ec82f:	mov    %rbp,0x18(%rax)
 10ec833:	mov    $0x8,%ecx
 10ec838:	lea    -0x81ebf(%rip),%rdx        # 106a980 <core_number_pairs+0x632b0>
 10ec83f:	mov    %rdx,0x20(%rax)
 10ec843:	movq   $0x1,0x8(%rax)
 10ec84b:	cmp    $0x2,%rcx
 10ec84f:	jb     10ed824 <my.diagram_membership::compute_sub_block_attachments+0x3ef4>
 10ec855:	lea    -0x81e9c(%rip),%rdx        # 106a9c0 <core_number_pairs+0x632f0>
 10ec85c:	mov    %rdx,0x28(%rax)
 10ec860:	movq   $0x2,0x8(%rax)
 10ec868:	cmp    $0x3,%rcx
 10ec86c:	jb     10ed861 <my.diagram_membership::compute_sub_block_attachments+0x3f31>
 10ec872:	lea    -0x81e79(%rip),%rdx        # 106aa00 <core_number_pairs+0x63330>
 10ec879:	mov    %rdx,0x30(%rax)
 10ec87d:	movq   $0x3,0x8(%rax)
 10ec885:	cmp    $0x4,%rcx
 10ec889:	jb     10ed89e <my.diagram_membership::compute_sub_block_attachments+0x3f6e>
 10ec88f:	lea    -0x81e56(%rip),%rdx        # 106aa40 <core_number_pairs+0x63370>
 10ec896:	mov    %rdx,0x38(%rax)
 10ec89a:	movq   $0x4,0x8(%rax)
 10ec8a2:	cmp    $0x5,%rcx
 10ec8a6:	jb     10ed8db <my.diagram_membership::compute_sub_block_attachments+0x3fab>
 10ec8ac:	lea    -0x81e33(%rip),%rdx        # 106aa80 <core_number_pairs+0x633b0>
 10ec8b3:	mov    %rdx,0x40(%rax)
 10ec8b7:	movq   $0x5,0x8(%rax)
 10ec8bf:	cmp    $0x6,%rcx
 10ec8c3:	jb     10ed918 <my.diagram_membership::compute_sub_block_attachments+0x3fe8>
 10ec8c9:	lea    -0x81e10(%rip),%rcx        # 106aac0 <core_number_pairs+0x633f0>
 10ec8d0:	mov    %rcx,0x48(%rax)
 10ec8d4:	movq   $0x6,0x8(%rax)
 10ec8dc:	mov    0x8(%r15),%rcx
 10ec8e0:	cmp    0x10(%r15),%rcx
 10ec8e4:	jae    10ed94c <my.diagram_membership::compute_sub_block_attachments+0x401c>
 10ec8ea:	mov    %rcx,%rdx
 10ec8ed:	shl    $0x4,%rdx
 10ec8f1:	movq   $0x7,0x20(%r15,%rdx,1)
 10ec8fa:	mov    %rax,0x28(%r15,%rdx,1)
 10ec8ff:	lea    0x1(%rcx),%rsi
 10ec903:	mov    %rsi,0x8(%r15)
 10ec907:	cmp    $0x5,%rcx
 10ec90b:	jne    10ee5b9 <my.diagram_membership::compute_sub_block_attachments+0x4c89>
 10ec911:	mov    %fs:0xfffffffffffffed8,%rax
 10ec91a:	test   %rax,%rax
 10ec91d:	je     10ed96b <my.diagram_membership::compute_sub_block_attachments+0x403b>
 10ec923:	mov    (%rax),%rcx
 10ec926:	mov    %rcx,%fs:0xfffffffffffffed8
 10ec92f:	movl   $0x3000000,(%rax)
 10ec935:	movq   $0x0,0x8(%rax)
 10ec93d:	movq   $0x8,0x10(%rax)
 10ec945:	mov    %rbp,0x18(%rax)
 10ec949:	mov    $0x8,%ecx
 10ec94e:	lea    -0x81e55(%rip),%rdx        # 106ab00 <core_number_pairs+0x63430>
 10ec955:	mov    %rdx,0x20(%rax)
 10ec959:	movq   $0x1,0x8(%rax)
 10ec961:	cmp    $0x2,%rcx
 10ec965:	jb     10ed9d4 <my.diagram_membership::compute_sub_block_attachments+0x40a4>
 10ec96b:	lea    -0x81e32(%rip),%rdx        # 106ab40 <core_number_pairs+0x63470>
 10ec972:	mov    %rdx,0x28(%rax)
 10ec976:	movq   $0x2,0x8(%rax)
 10ec97e:	cmp    $0x3,%rcx
 10ec982:	jb     10eda11 <my.diagram_membership::compute_sub_block_attachments+0x40e1>
 10ec988:	lea    -0x81e0f(%rip),%rdx        # 106ab80 <core_number_pairs+0x634b0>
 10ec98f:	mov    %rdx,0x30(%rax)
 10ec993:	movq   $0x3,0x8(%rax)
 10ec99b:	cmp    $0x4,%rcx
 10ec99f:	jb     10eda4e <my.diagram_membership::compute_sub_block_attachments+0x411e>
 10ec9a5:	lea    -0x81dec(%rip),%rdx        # 106abc0 <core_number_pairs+0x634f0>
 10ec9ac:	mov    %rdx,0x38(%rax)
 10ec9b0:	movq   $0x4,0x8(%rax)
 10ec9b8:	cmp    $0x5,%rcx
 10ec9bc:	jb     10eda8b <my.diagram_membership::compute_sub_block_attachments+0x415b>
 10ec9c2:	lea    -0x81dc9(%rip),%rcx        # 106ac00 <core_number_pairs+0x63530>
 10ec9c9:	mov    %rcx,0x40(%rax)
 10ec9cd:	movq   $0x5,0x8(%rax)
 10ec9d5:	mov    0x8(%r15),%rcx
 10ec9d9:	cmp    0x10(%r15),%rcx
 10ec9dd:	jae    10edabf <my.diagram_membership::compute_sub_block_attachments+0x418f>
 10ec9e3:	mov    %rcx,%rdx
 10ec9e6:	shl    $0x4,%rdx
 10ec9ea:	movq   $0x8,0x20(%r15,%rdx,1)
 10ec9f3:	mov    %rax,0x28(%r15,%rdx,1)
 10ec9f8:	lea    0x1(%rcx),%rsi
 10ec9fc:	mov    %rsi,0x8(%r15)
 10eca00:	cmp    $0x6,%rcx
 10eca04:	jne    10ee61b <my.diagram_membership::compute_sub_block_attachments+0x4ceb>
 10eca0a:	mov    %fs:0xfffffffffffffed0,%rax
 10eca13:	test   %rax,%rax
 10eca16:	je     10edade <my.diagram_membership::compute_sub_block_attachments+0x41ae>
 10eca1c:	mov    (%rax),%rcx
 10eca1f:	mov    %rcx,%fs:0xfffffffffffffed0
 10eca28:	movl   $0x2000000,(%rax)
 10eca2e:	movq   $0x0,0x8(%rax)
 10eca36:	movq   $0x4,0x10(%rax)
 10eca3e:	mov    %rbp,0x18(%rax)
 10eca42:	mov    $0x4,%ecx
 10eca47:	lea    -0x81e0e(%rip),%rdx        # 106ac40 <core_number_pairs+0x63570>
 10eca4e:	mov    %rdx,0x20(%rax)
 10eca52:	movq   $0x1,0x8(%rax)
 10eca5a:	cmp    $0x2,%rcx
 10eca5e:	jb     10edb47 <my.diagram_membership::compute_sub_block_attachments+0x4217>
 10eca64:	lea    -0x81deb(%rip),%rdx        # 106ac80 <core_number_pairs+0x635b0>
 10eca6b:	mov    %rdx,0x28(%rax)
 10eca6f:	movq   $0x2,0x8(%rax)
 10eca77:	cmp    $0x3,%rcx
 10eca7b:	jb     10edb84 <my.diagram_membership::compute_sub_block_attachments+0x4254>
 10eca81:	lea    -0x81dc8(%rip),%rdx        # 106acc0 <core_number_pairs+0x635f0>
 10eca88:	mov    %rdx,0x30(%rax)
 10eca8c:	movq   $0x3,0x8(%rax)
 10eca94:	cmp    $0x4,%rcx
 10eca98:	jb     10edbc1 <my.diagram_membership::compute_sub_block_attachments+0x4291>
 10eca9e:	lea    -0x81da5(%rip),%rcx        # 106ad00 <core_number_pairs+0x63630>
 10ecaa5:	mov    %rcx,0x38(%rax)
 10ecaa9:	movq   $0x4,0x8(%rax)
 10ecab1:	mov    0x8(%r15),%rcx
 10ecab5:	cmp    0x10(%r15),%rcx
 10ecab9:	jae    10edbf5 <my.diagram_membership::compute_sub_block_attachments+0x42c5>
 10ecabf:	mov    %rcx,%rdx
 10ecac2:	shl    $0x4,%rdx
 10ecac6:	movq   $0x9,0x20(%r15,%rdx,1)
 10ecacf:	mov    %rax,0x28(%r15,%rdx,1)
 10ecad4:	lea    0x1(%rcx),%rsi
 10ecad8:	mov    %rsi,0x8(%r15)
 10ecadc:	cmp    $0x7,%rcx
 10ecae0:	jne    10ee6c3 <my.diagram_membership::compute_sub_block_attachments+0x4d93>
 10ecae6:	mov    %fs:0xfffffffffffffed8,%rax
 10ecaef:	test   %rax,%rax
 10ecaf2:	je     10edc14 <my.diagram_membership::compute_sub_block_attachments+0x42e4>
 10ecaf8:	mov    (%rax),%rcx
 10ecafb:	mov    %rcx,%fs:0xfffffffffffffed8
 10ecb04:	movl   $0x3000000,(%rax)
 10ecb0a:	movq   $0x0,0x8(%rax)
 10ecb12:	movq   $0x8,0x10(%rax)
 10ecb1a:	mov    %rbp,0x18(%rax)
 10ecb1e:	mov    $0x8,%ecx
 10ecb23:	lea    -0x81dea(%rip),%rdx        # 106ad40 <core_number_pairs+0x63670>
 10ecb2a:	mov    %rdx,0x20(%rax)
 10ecb2e:	movq   $0x1,0x8(%rax)
 10ecb36:	cmp    $0x2,%rcx
 10ecb3a:	jb     10edc7d <my.diagram_membership::compute_sub_block_attachments+0x434d>
 10ecb40:	lea    -0x81dc7(%rip),%rdx        # 106ad80 <core_number_pairs+0x636b0>
 10ecb47:	mov    %rdx,0x28(%rax)
 10ecb4b:	movq   $0x2,0x8(%rax)
 10ecb53:	cmp    $0x3,%rcx
 10ecb57:	jb     10edcba <my.diagram_membership::compute_sub_block_attachments+0x438a>
 10ecb5d:	lea    -0x81da4(%rip),%rdx        # 106adc0 <core_number_pairs+0x636f0>
 10ecb64:	mov    %rdx,0x30(%rax)
 10ecb68:	movq   $0x3,0x8(%rax)
 10ecb70:	cmp    $0x4,%rcx
 10ecb74:	jb     10edcf7 <my.diagram_membership::compute_sub_block_attachments+0x43c7>
 10ecb7a:	lea    -0x81d81(%rip),%rdx        # 106ae00 <core_number_pairs+0x63730>
 10ecb81:	mov    %rdx,0x38(%rax)
 10ecb85:	movq   $0x4,0x8(%rax)
 10ecb8d:	cmp    $0x5,%rcx
 10ecb91:	jb     10edd34 <my.diagram_membership::compute_sub_block_attachments+0x4404>
 10ecb97:	lea    -0x81d5e(%rip),%rdx        # 106ae40 <core_number_pairs+0x63770>
 10ecb9e:	mov    %rdx,0x40(%rax)
 10ecba2:	movq   $0x5,0x8(%rax)
 10ecbaa:	cmp    $0x6,%rcx
 10ecbae:	jb     10edd71 <my.diagram_membership::compute_sub_block_attachments+0x4441>
 10ecbb4:	lea    -0x81d3b(%rip),%rdx        # 106ae80 <core_number_pairs+0x637b0>
 10ecbbb:	mov    %rdx,0x48(%rax)
 10ecbbf:	movq   $0x6,0x8(%rax)
 10ecbc7:	cmp    $0x7,%rcx
 10ecbcb:	jb     10eddae <my.diagram_membership::compute_sub_block_attachments+0x447e>
 10ecbd1:	lea    -0x81d18(%rip),%rdx        # 106aec0 <core_number_pairs+0x637f0>
 10ecbd8:	mov    %rdx,0x50(%rax)
 10ecbdc:	movq   $0x7,0x8(%rax)
 10ecbe4:	cmp    $0x8,%rcx
 10ecbe8:	jb     10eddeb <my.diagram_membership::compute_sub_block_attachments+0x44bb>
 10ecbee:	lea    -0x81cf5(%rip),%rcx        # 106af00 <core_number_pairs+0x63830>
 10ecbf5:	mov    %rcx,0x58(%rax)
 10ecbf9:	movq   $0x8,0x8(%rax)
 10ecc01:	mov    0x8(%r15),%rcx
 10ecc05:	cmp    0x10(%r15),%rcx
 10ecc09:	jae    10ede1f <my.diagram_membership::compute_sub_block_attachments+0x44ef>
 10ecc0f:	mov    %rcx,%rdx
 10ecc12:	shl    $0x4,%rdx
 10ecc16:	movq   $0x4,0x20(%r15,%rdx,1)
 10ecc1f:	mov    %rax,0x28(%r15,%rdx,1)
 10ecc24:	lea    0x1(%rcx),%rsi
 10ecc28:	mov    %rsi,0x8(%r15)
 10ecc2c:	cmp    $0x8,%rcx
 10ecc30:	jne    10ee549 <my.diagram_membership::compute_sub_block_attachments+0x4c19>
 10ecc36:	mov    %r15,0xd8(%rsp)
 10ecc3e:	lea    0x20(%r15),%r12
 10ecc42:	xor    %r10d,%r10d
 10ecc45:	movabs $0x800000000000,%rax
 10ecc4f:	mov    %r13,0x30(%rsp)
 10ecc54:	mov    %r10,%r11
 10ecc57:	shl    $0x4,%r11
 10ecc5b:	mov    0x8(%r12,%r11,1),%rbp
 10ecc60:	mov    0x8(%rbp),%rsi
 10ecc64:	cmp    %rax,%rsi
 10ecc67:	ja     10ee330 <my.diagram_membership::compute_sub_block_attachments+0x4a00>
 10ecc6d:	test   %rsi,%rsi
 10ecc70:	je     10ecd80 <my.diagram_membership::compute_sub_block_attachments+0x3450>
 10ecc76:	add    %r12,%r11
 10ecc79:	mov    0x10(%rsp),%rax
 10ecc7e:	mov    0x8(%rax),%rdx
 10ecc82:	xor    %r13d,%r13d
 10ecc85:	jmp    10ecc9c <my.diagram_membership::compute_sub_block_attachments+0x336c>
 10ecc87:	nopw   0x0(%rax,%rax,1)
 10ecc90:	inc    %r13
 10ecc93:	cmp    %rsi,%r13
 10ecc96:	je     10ecd80 <my.diagram_membership::compute_sub_block_attachments+0x3450>
 10ecc9c:	mov    0x20(%rbp,%r13,8),%r14
 10ecca1:	mov    0x8(%r14),%rax
 10ecca5:	movabs $0x800000000000,%rcx
 10eccaf:	cmp    %rcx,%rax
 10eccb2:	ja     10ee2e5 <my.diagram_membership::compute_sub_block_attachments+0x49b5>
 10eccb8:	cmp    %rcx,%rdx
 10eccbb:	ja     10ee2f6 <my.diagram_membership::compute_sub_block_attachments+0x49c6>
 10eccc1:	cmp    %rdx,%rax
 10eccc4:	ja     10ecc90 <my.diagram_membership::compute_sub_block_attachments+0x3360>
 10eccc6:	mov    %rax,%r8
 10eccc9:	xor    %ecx,%ecx
 10ecccb:	test   %r8,%r8
 10eccce:	js     10ee31f <my.diagram_membership::compute_sub_block_attachments+0x49ef>
 10eccd4:	cmp    %rdx,%r8
 10eccd7:	jg     10ecc90 <my.diagram_membership::compute_sub_block_attachments+0x3360>
 10eccd9:	test   %rax,%rax
 10eccdc:	je     10ecdb0 <my.diagram_membership::compute_sub_block_attachments+0x3480>
 10ecce2:	xor    %r8d,%r8d
 10ecce5:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10eccf4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ecd00:	mov    %rcx,%r9
 10ecd03:	add    %r8,%r9
 10ecd06:	jo     10ee0c8 <my.diagram_membership::compute_sub_block_attachments+0x4798>
 10ecd0c:	js     10ee0a1 <my.diagram_membership::compute_sub_block_attachments+0x4771>
 10ecd12:	cmp    %rdx,%r9
 10ecd15:	jae    10ee0b2 <my.diagram_membership::compute_sub_block_attachments+0x4782>
 10ecd1b:	mov    0x10(%rsp),%rdi
 10ecd20:	movzbl 0x20(%rdi,%r9,1),%r15d
 10ecd26:	lea    -0x41(%r15),%edi
 10ecd2a:	mov    %r15d,%r9d
 10ecd2d:	or     $0x20,%r9d
 10ecd31:	cmp    $0x1a,%dil
 10ecd35:	cmovae %r15,%r9
 10ecd39:	movzbl 0x20(%r14,%r8,1),%ebx
 10ecd3f:	lea    -0x41(%rbx),%r15d
 10ecd43:	mov    %ebx,%edi
 10ecd45:	or     $0x20,%edi
 10ecd48:	cmp    $0x1a,%r15b
 10ecd4c:	cmovae %rbx,%rdi
 10ecd50:	cmp    %edi,%r9d
 10ecd53:	jne    10ecd60 <my.diagram_membership::compute_sub_block_attachments+0x3430>
 10ecd55:	inc    %r8
 10ecd58:	cmp    %r8,%rax
 10ecd5b:	jne    10ecd00 <my.diagram_membership::compute_sub_block_attachments+0x33d0>
 10ecd5d:	jmp    10ecdb0 <my.diagram_membership::compute_sub_block_attachments+0x3480>
 10ecd5f:	nop
 10ecd60:	inc    %rcx
 10ecd63:	jo     10ee7b1 <my.diagram_membership::compute_sub_block_attachments+0x4e81>
 10ecd69:	mov    %rcx,%r8
 10ecd6c:	add    %rax,%r8
 10ecd6f:	jno    10ecccb <my.diagram_membership::compute_sub_block_attachments+0x339b>
 10ecd75:	jmp    10ee7cf <my.diagram_membership::compute_sub_block_attachments+0x4e9f>
 10ecd7a:	nopw   0x0(%rax,%rax,1)
 10ecd80:	inc    %r10
 10ecd83:	cmp    $0x9,%r10
 10ecd87:	movabs $0x800000000000,%rax
 10ecd91:	mov    0x30(%rsp),%r13
 10ecd96:	jne    10ecc54 <my.diagram_membership::compute_sub_block_attachments+0x3324>
 10ecd9c:	mov    0xd8(%rsp),%rdi
 10ecda4:	call   1086200 <myl_core_drop_owned>
 10ecda9:	xor    %eax,%eax
 10ecdab:	xor    %r14d,%r14d
 10ecdae:	jmp    10ecdc8 <my.diagram_membership::compute_sub_block_attachments+0x3498>
 10ecdb0:	movzbl (%r11),%r14d
 10ecdb4:	mov    0xd8(%rsp),%rdi
 10ecdbc:	call   1086200 <myl_core_drop_owned>
 10ecdc1:	mov    $0x1,%al
 10ecdc3:	mov    0x30(%rsp),%r13
 10ecdc8:	cmp    $0x1,%al
 10ecdca:	mov    0x58(%rsp),%r10
 10ecdcf:	lea    -0x786de(%rip),%rbp        # 10746f8 <core_number_pairs+0x6d028>
 10ecdd6:	mov    0x108(%rsp),%r11
 10ecdde:	mov    0xb0(%rsp),%rbx
 10ecde6:	mov    0xa0(%rsp),%r15
 10ecdee:	mov    0x90(%rsp),%r12d
 10ecdf6:	mov    0x8(%rsp),%rcx
 10ecdfb:	je     10ec100 <my.diagram_membership::compute_sub_block_attachments+0x27d0>
 10ece01:	mov    0x8(%rcx),%rsi
 10ece05:	movabs $0x800000000000,%rax
 10ece0f:	cmp    %rax,%rsi
 10ece12:	ja     10ee81b <my.diagram_membership::compute_sub_block_attachments+0x4eeb>
 10ece18:	mov    0x110(%rsp),%rdx
 10ece20:	cmp    %rdx,%rsi
 10ece23:	ja     10ee80f <my.diagram_membership::compute_sub_block_attachments+0x4edf>
 10ece29:	jg     10ee803 <my.diagram_membership::compute_sub_block_attachments+0x4ed3>
 10ece2f:	mov    %rbp,%r9
 10ece32:	add    $0x20,%rcx
 10ece36:	xor    %eax,%eax
 10ece38:	jmp    10ece56 <my.diagram_membership::compute_sub_block_attachments+0x3526>
 10ece3a:	nopw   0x0(%rax,%rax,1)
 10ece40:	inc    %rax
 10ece43:	mov    %rbp,%rcx
 10ece46:	add    $0x218,%rcx
 10ece4d:	cmp    %rdx,%rax
 10ece50:	jg     10ee22b <my.diagram_membership::compute_sub_block_attachments+0x48fb>
 10ece56:	cmp    %rax,%rsi
 10ece59:	setne  %r14b
 10ece5d:	je     10ec10b <my.diagram_membership::compute_sub_block_attachments+0x27db>
 10ece63:	mov    %rcx,%rbp
 10ece66:	mov    (%rcx),%rdi
 10ece69:	mov    0x8(%rdi),%rcx
 10ece6d:	movabs $0x800000000000,%r8
 10ece77:	cmp    %r8,%rcx
 10ece7a:	ja     10ee21a <my.diagram_membership::compute_sub_block_attachments+0x48ea>
 10ece80:	test   %rcx,%rcx
 10ece83:	je     10ece40 <my.diagram_membership::compute_sub_block_attachments+0x3510>
 10ece85:	movzbl 0x20(%rdi),%ecx
 10ece89:	cmp    $0x50,%ecx
 10ece8c:	je     10ec10b <my.diagram_membership::compute_sub_block_attachments+0x27db>
 10ece92:	cmp    $0x4a,%ecx
 10ece95:	jne    10ece40 <my.diagram_membership::compute_sub_block_attachments+0x3510>
 10ece97:	jmp    10ec10b <my.diagram_membership::compute_sub_block_attachments+0x27db>
 10ece9c:	mov    $0x9,%edi
 10ecea1:	mov    $0x10,%esi
 10ecea6:	mov    %rcx,%r14
 10ecea9:	call   1085440 <myl_core_list_new_slow>
 10eceae:	mov    %r14,%rcx
 10eceb1:	mov    %rax,%r15
 10eceb4:	mov    0x8(%rax),%rsi
 10eceb8:	lea    -0x7784f(%rip),%rax        # 1075670 <core_number_pairs+0x6dfa0>
 10ecebf:	mov    %rax,0x18(%r15)
 10ecec3:	test   %rsi,%rsi
 10ecec6:	je     10ec247 <my.diagram_membership::compute_sub_block_attachments+0x2917>
 10ececc:	jmp    10ee503 <my.diagram_membership::compute_sub_block_attachments+0x4bd3>
 10eced1:	mov    $0x8,%edi
 10eced6:	mov    $0x8,%esi
 10ecedb:	call   1085440 <myl_core_list_new_slow>
 10ecee0:	mov    0x8(%rax),%rsi
 10ecee4:	mov    %rbp,0x18(%rax)
 10ecee8:	test   %rsi,%rsi
 10eceeb:	jne    10ee4a1 <my.diagram_membership::compute_sub_block_attachments+0x4b71>
 10ecef1:	mov    0x10(%rax),%rcx
 10ecef5:	test   %rcx,%rcx
 10ecef8:	jne    10ec289 <my.diagram_membership::compute_sub_block_attachments+0x2959>
 10ecefe:	mov    $0x8,%esi
 10ecf03:	mov    %rax,%rdi
 10ecf06:	call   1085500 <myl_core_list_grow>
 10ecf0b:	mov    0x8(%rax),%rcx
 10ecf0f:	lea    -0x82d96(%rip),%rdx        # 106a180 <core_number_pairs+0x62ab0>
 10ecf16:	mov    %rdx,0x20(%rax,%rcx,8)
 10ecf1b:	lea    0x1(%rcx),%rsi
 10ecf1f:	mov    %rsi,0x8(%rax)
 10ecf23:	test   %rcx,%rcx
 10ecf26:	jne    10ee75d <my.diagram_membership::compute_sub_block_attachments+0x4e2d>
 10ecf2c:	mov    0x10(%rax),%rcx
 10ecf30:	cmp    $0x2,%rcx
 10ecf34:	jae    10ec2a6 <my.diagram_membership::compute_sub_block_attachments+0x2976>
 10ecf3a:	mov    $0x8,%esi
 10ecf3f:	mov    %rax,%rdi
 10ecf42:	call   1085500 <myl_core_list_grow>
 10ecf47:	mov    0x8(%rax),%rcx
 10ecf4b:	lea    -0x82d92(%rip),%rdx        # 106a1c0 <core_number_pairs+0x62af0>
 10ecf52:	mov    %rdx,0x20(%rax,%rcx,8)
 10ecf57:	lea    0x1(%rcx),%rsi
 10ecf5b:	mov    %rsi,0x8(%rax)
 10ecf5f:	cmp    $0x1,%rcx
 10ecf63:	jne    10ee3f9 <my.diagram_membership::compute_sub_block_attachments+0x4ac9>
 10ecf69:	mov    0x10(%rax),%rcx
 10ecf6d:	cmp    $0x3,%rcx
 10ecf71:	jae    10ec2c3 <my.diagram_membership::compute_sub_block_attachments+0x2993>
 10ecf77:	mov    $0x8,%esi
 10ecf7c:	mov    %rax,%rdi
 10ecf7f:	call   1085500 <myl_core_list_grow>
 10ecf84:	mov    0x8(%rax),%rcx
 10ecf88:	lea    -0x82d8f(%rip),%rdx        # 106a200 <core_number_pairs+0x62b30>
 10ecf8f:	mov    %rdx,0x20(%rax,%rcx,8)
 10ecf94:	lea    0x1(%rcx),%rsi
 10ecf98:	mov    %rsi,0x8(%rax)
 10ecf9c:	cmp    $0x2,%rcx
 10ecfa0:	jne    10ee4af <my.diagram_membership::compute_sub_block_attachments+0x4b7f>
 10ecfa6:	mov    0x10(%rax),%rcx
 10ecfaa:	cmp    $0x4,%rcx
 10ecfae:	jae    10ec2e0 <my.diagram_membership::compute_sub_block_attachments+0x29b0>
 10ecfb4:	mov    $0x8,%esi
 10ecfb9:	mov    %rax,%rdi
 10ecfbc:	call   1085500 <myl_core_list_grow>
 10ecfc1:	mov    0x8(%rax),%rcx
 10ecfc5:	lea    -0x82d8c(%rip),%rdx        # 106a240 <core_number_pairs+0x62b70>
 10ecfcc:	mov    %rdx,0x20(%rax,%rcx,8)
 10ecfd1:	lea    0x1(%rcx),%rsi
 10ecfd5:	mov    %rsi,0x8(%rax)
 10ecfd9:	cmp    $0x3,%rcx
 10ecfdd:	jne    10ee469 <my.diagram_membership::compute_sub_block_attachments+0x4b39>
 10ecfe3:	mov    0x10(%rax),%rcx
 10ecfe7:	cmp    $0x5,%rcx
 10ecfeb:	jae    10ec2fd <my.diagram_membership::compute_sub_block_attachments+0x29cd>
 10ecff1:	mov    $0x8,%esi
 10ecff6:	mov    %rax,%rdi
 10ecff9:	call   1085500 <myl_core_list_grow>
 10ecffe:	mov    0x8(%rax),%rcx
 10ed002:	lea    -0x82d89(%rip),%rdx        # 106a280 <core_number_pairs+0x62bb0>
 10ed009:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed00e:	lea    0x1(%rcx),%rsi
 10ed012:	mov    %rsi,0x8(%rax)
 10ed016:	cmp    $0x4,%rcx
 10ed01a:	jne    10ee415 <my.diagram_membership::compute_sub_block_attachments+0x4ae5>
 10ed020:	mov    0x10(%rax),%rcx
 10ed024:	cmp    $0x6,%rcx
 10ed028:	jae    10ec31a <my.diagram_membership::compute_sub_block_attachments+0x29ea>
 10ed02e:	mov    $0x8,%esi
 10ed033:	mov    %rax,%rdi
 10ed036:	call   1085500 <myl_core_list_grow>
 10ed03b:	mov    0x8(%rax),%rcx
 10ed03f:	lea    -0x82d86(%rip),%rdx        # 106a2c0 <core_number_pairs+0x62bf0>
 10ed046:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed04b:	lea    0x1(%rcx),%rsi
 10ed04f:	mov    %rsi,0x8(%rax)
 10ed053:	cmp    $0x5,%rcx
 10ed057:	jne    10ee3c1 <my.diagram_membership::compute_sub_block_attachments+0x4a91>
 10ed05d:	mov    0x10(%rax),%rcx
 10ed061:	cmp    $0x7,%rcx
 10ed065:	jae    10ec337 <my.diagram_membership::compute_sub_block_attachments+0x2a07>
 10ed06b:	mov    $0x8,%esi
 10ed070:	mov    %rax,%rdi
 10ed073:	call   1085500 <myl_core_list_grow>
 10ed078:	mov    0x8(%rax),%rcx
 10ed07c:	lea    -0x82d83(%rip),%rdx        # 106a300 <core_number_pairs+0x62c30>
 10ed083:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed088:	lea    0x1(%rcx),%rsi
 10ed08c:	mov    %rsi,0x8(%rax)
 10ed090:	cmp    $0x6,%rcx
 10ed094:	jne    10ee4cb <my.diagram_membership::compute_sub_block_attachments+0x4b9b>
 10ed09a:	mov    0x10(%rax),%rcx
 10ed09e:	cmp    $0x8,%rcx
 10ed0a2:	jae    10ec354 <my.diagram_membership::compute_sub_block_attachments+0x2a24>
 10ed0a8:	mov    $0x8,%esi
 10ed0ad:	mov    %rax,%rdi
 10ed0b0:	call   1085500 <myl_core_list_grow>
 10ed0b5:	mov    0x8(%rax),%rcx
 10ed0b9:	lea    -0x82d80(%rip),%rdx        # 106a340 <core_number_pairs+0x62c70>
 10ed0c0:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed0c5:	lea    0x1(%rcx),%rsi
 10ed0c9:	mov    %rsi,0x8(%rax)
 10ed0cd:	cmp    $0x7,%rcx
 10ed0d1:	je     10ec367 <my.diagram_membership::compute_sub_block_attachments+0x2a37>
 10ed0d7:	jmp    10ee431 <my.diagram_membership::compute_sub_block_attachments+0x4b01>
 10ed0dc:	mov    $0x10,%esi
 10ed0e1:	mov    %r15,%rdi
 10ed0e4:	mov    %rax,%r14
 10ed0e7:	call   1085500 <myl_core_list_grow>
 10ed0ec:	mov    %rax,%r15
 10ed0ef:	mov    %r14,%rax
 10ed0f2:	mov    0x8(%r15),%rcx
 10ed0f6:	jmp    10ec37d <my.diagram_membership::compute_sub_block_attachments+0x2a4d>
 10ed0fb:	mov    $0x7,%edi
 10ed100:	mov    $0x8,%esi
 10ed105:	call   1085440 <myl_core_list_new_slow>
 10ed10a:	mov    0x8(%rax),%rsi
 10ed10e:	mov    %rbp,0x18(%rax)
 10ed112:	test   %rsi,%rsi
 10ed115:	jne    10ee511 <my.diagram_membership::compute_sub_block_attachments+0x4be1>
 10ed11b:	mov    0x10(%rax),%rcx
 10ed11f:	test   %rcx,%rcx
 10ed122:	jne    10ec3e0 <my.diagram_membership::compute_sub_block_attachments+0x2ab0>
 10ed128:	mov    $0x8,%esi
 10ed12d:	mov    %rax,%rdi
 10ed130:	call   1085500 <myl_core_list_grow>
 10ed135:	mov    0x8(%rax),%rcx
 10ed139:	lea    -0x82dc0(%rip),%rdx        # 106a380 <core_number_pairs+0x62cb0>
 10ed140:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed145:	lea    0x1(%rcx),%rsi
 10ed149:	mov    %rsi,0x8(%rax)
 10ed14d:	test   %rcx,%rcx
 10ed150:	jne    10ee76b <my.diagram_membership::compute_sub_block_attachments+0x4e3b>
 10ed156:	mov    0x10(%rax),%rcx
 10ed15a:	cmp    $0x2,%rcx
 10ed15e:	jae    10ec3fd <my.diagram_membership::compute_sub_block_attachments+0x2acd>
 10ed164:	mov    $0x8,%esi
 10ed169:	mov    %rax,%rdi
 10ed16c:	call   1085500 <myl_core_list_grow>
 10ed171:	mov    0x8(%rax),%rcx
 10ed175:	lea    -0x82dbc(%rip),%rdx        # 106a3c0 <core_number_pairs+0x62cf0>
 10ed17c:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed181:	lea    0x1(%rcx),%rsi
 10ed185:	mov    %rsi,0x8(%rax)
 10ed189:	cmp    $0x1,%rcx
 10ed18d:	jne    10ee45b <my.diagram_membership::compute_sub_block_attachments+0x4b2b>
 10ed193:	mov    0x10(%rax),%rcx
 10ed197:	cmp    $0x3,%rcx
 10ed19b:	jae    10ec41a <my.diagram_membership::compute_sub_block_attachments+0x2aea>
 10ed1a1:	mov    $0x8,%esi
 10ed1a6:	mov    %rax,%rdi
 10ed1a9:	call   1085500 <myl_core_list_grow>
 10ed1ae:	mov    0x8(%rax),%rcx
 10ed1b2:	lea    -0x82db9(%rip),%rdx        # 106a400 <core_number_pairs+0x62d30>
 10ed1b9:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed1be:	lea    0x1(%rcx),%rsi
 10ed1c2:	mov    %rsi,0x8(%rax)
 10ed1c6:	cmp    $0x2,%rcx
 10ed1ca:	jne    10ee3dd <my.diagram_membership::compute_sub_block_attachments+0x4aad>
 10ed1d0:	mov    0x10(%rax),%rcx
 10ed1d4:	cmp    $0x4,%rcx
 10ed1d8:	jae    10ec437 <my.diagram_membership::compute_sub_block_attachments+0x2b07>
 10ed1de:	mov    $0x8,%esi
 10ed1e3:	mov    %rax,%rdi
 10ed1e6:	call   1085500 <myl_core_list_grow>
 10ed1eb:	mov    0x8(%rax),%rcx
 10ed1ef:	lea    -0x82db6(%rip),%rdx        # 106a440 <core_number_pairs+0x62d70>
 10ed1f6:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed1fb:	lea    0x1(%rcx),%rsi
 10ed1ff:	mov    %rsi,0x8(%rax)
 10ed203:	cmp    $0x3,%rcx
 10ed207:	jne    10ee4f5 <my.diagram_membership::compute_sub_block_attachments+0x4bc5>
 10ed20d:	mov    0x10(%rax),%rcx
 10ed211:	cmp    $0x5,%rcx
 10ed215:	jae    10ec454 <my.diagram_membership::compute_sub_block_attachments+0x2b24>
 10ed21b:	mov    $0x8,%esi
 10ed220:	mov    %rax,%rdi
 10ed223:	call   1085500 <myl_core_list_grow>
 10ed228:	mov    0x8(%rax),%rcx
 10ed22c:	lea    -0x82db3(%rip),%rdx        # 106a480 <core_number_pairs+0x62db0>
 10ed233:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed238:	lea    0x1(%rcx),%rsi
 10ed23c:	mov    %rsi,0x8(%rax)
 10ed240:	cmp    $0x4,%rcx
 10ed244:	jne    10ee477 <my.diagram_membership::compute_sub_block_attachments+0x4b47>
 10ed24a:	mov    0x10(%rax),%rcx
 10ed24e:	cmp    $0x6,%rcx
 10ed252:	jae    10ec471 <my.diagram_membership::compute_sub_block_attachments+0x2b41>
 10ed258:	mov    $0x8,%esi
 10ed25d:	mov    %rax,%rdi
 10ed260:	call   1085500 <myl_core_list_grow>
 10ed265:	mov    0x8(%rax),%rcx
 10ed269:	lea    -0x82db0(%rip),%rdx        # 106a4c0 <core_number_pairs+0x62df0>
 10ed270:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed275:	lea    0x1(%rcx),%rsi
 10ed279:	mov    %rsi,0x8(%rax)
 10ed27d:	cmp    $0x5,%rcx
 10ed281:	jne    10ee407 <my.diagram_membership::compute_sub_block_attachments+0x4ad7>
 10ed287:	mov    0x10(%rax),%rcx
 10ed28b:	cmp    $0x7,%rcx
 10ed28f:	jae    10ec48e <my.diagram_membership::compute_sub_block_attachments+0x2b5e>
 10ed295:	mov    $0x8,%esi
 10ed29a:	mov    %rax,%rdi
 10ed29d:	call   1085500 <myl_core_list_grow>
 10ed2a2:	mov    0x8(%rax),%rcx
 10ed2a6:	lea    -0x82dad(%rip),%rdx        # 106a500 <core_number_pairs+0x62e30>
 10ed2ad:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed2b2:	lea    0x1(%rcx),%rsi
 10ed2b6:	mov    %rsi,0x8(%rax)
 10ed2ba:	cmp    $0x6,%rcx
 10ed2be:	je     10ec4a1 <my.diagram_membership::compute_sub_block_attachments+0x2b71>
 10ed2c4:	jmp    10ee3b3 <my.diagram_membership::compute_sub_block_attachments+0x4a83>
 10ed2c9:	mov    $0x10,%esi
 10ed2ce:	mov    %r15,%rdi
 10ed2d1:	mov    %rax,%r14
 10ed2d4:	call   1085500 <myl_core_list_grow>
 10ed2d9:	mov    %rax,%r15
 10ed2dc:	mov    %r14,%rax
 10ed2df:	mov    0x8(%r15),%rcx
 10ed2e3:	jmp    10ec4af <my.diagram_membership::compute_sub_block_attachments+0x2b7f>
 10ed2e8:	mov    $0x5,%edi
 10ed2ed:	mov    $0x8,%esi
 10ed2f2:	call   1085440 <myl_core_list_new_slow>
 10ed2f7:	mov    0x8(%rax),%rsi
 10ed2fb:	mov    %rbp,0x18(%rax)
 10ed2ff:	test   %rsi,%rsi
 10ed302:	jne    10ee43f <my.diagram_membership::compute_sub_block_attachments+0x4b0f>
 10ed308:	mov    0x10(%rax),%rcx
 10ed30c:	test   %rcx,%rcx
 10ed30f:	jne    10ec513 <my.diagram_membership::compute_sub_block_attachments+0x2be3>
 10ed315:	mov    $0x8,%esi
 10ed31a:	mov    %rax,%rdi
 10ed31d:	call   1085500 <myl_core_list_grow>
 10ed322:	mov    0x8(%rax),%rcx
 10ed326:	lea    -0x82ded(%rip),%rdx        # 106a540 <core_number_pairs+0x62e70>
 10ed32d:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed332:	lea    0x1(%rcx),%rsi
 10ed336:	mov    %rsi,0x8(%rax)
 10ed33a:	test   %rcx,%rcx
 10ed33d:	jne    10ee741 <my.diagram_membership::compute_sub_block_attachments+0x4e11>
 10ed343:	mov    0x10(%rax),%rcx
 10ed347:	cmp    $0x2,%rcx
 10ed34b:	jae    10ec530 <my.diagram_membership::compute_sub_block_attachments+0x2c00>
 10ed351:	mov    $0x8,%esi
 10ed356:	mov    %rax,%rdi
 10ed359:	call   1085500 <myl_core_list_grow>
 10ed35e:	mov    0x8(%rax),%rcx
 10ed362:	lea    -0x82de9(%rip),%rdx        # 106a580 <core_number_pairs+0x62eb0>
 10ed369:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed36e:	lea    0x1(%rcx),%rsi
 10ed372:	mov    %rsi,0x8(%rax)
 10ed376:	cmp    $0x1,%rcx
 10ed37a:	jne    10ee51f <my.diagram_membership::compute_sub_block_attachments+0x4bef>
 10ed380:	mov    0x10(%rax),%rcx
 10ed384:	cmp    $0x3,%rcx
 10ed388:	jae    10ec54d <my.diagram_membership::compute_sub_block_attachments+0x2c1d>
 10ed38e:	mov    $0x8,%esi
 10ed393:	mov    %rax,%rdi
 10ed396:	call   1085500 <myl_core_list_grow>
 10ed39b:	mov    0x8(%rax),%rcx
 10ed39f:	lea    -0x82de6(%rip),%rdx        # 106a5c0 <core_number_pairs+0x62ef0>
 10ed3a6:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed3ab:	lea    0x1(%rcx),%rsi
 10ed3af:	mov    %rsi,0x8(%rax)
 10ed3b3:	cmp    $0x2,%rcx
 10ed3b7:	jne    10ee493 <my.diagram_membership::compute_sub_block_attachments+0x4b63>
 10ed3bd:	mov    0x10(%rax),%rcx
 10ed3c1:	cmp    $0x4,%rcx
 10ed3c5:	jae    10ec56a <my.diagram_membership::compute_sub_block_attachments+0x2c3a>
 10ed3cb:	mov    $0x8,%esi
 10ed3d0:	mov    %rax,%rdi
 10ed3d3:	call   1085500 <myl_core_list_grow>
 10ed3d8:	mov    0x8(%rax),%rcx
 10ed3dc:	lea    -0x82de3(%rip),%rdx        # 106a600 <core_number_pairs+0x62f30>
 10ed3e3:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed3e8:	lea    0x1(%rcx),%rsi
 10ed3ec:	mov    %rsi,0x8(%rax)
 10ed3f0:	cmp    $0x3,%rcx
 10ed3f4:	jne    10ee423 <my.diagram_membership::compute_sub_block_attachments+0x4af3>
 10ed3fa:	mov    0x10(%rax),%rcx
 10ed3fe:	cmp    $0x5,%rcx
 10ed402:	jae    10ec587 <my.diagram_membership::compute_sub_block_attachments+0x2c57>
 10ed408:	mov    $0x8,%esi
 10ed40d:	mov    %rax,%rdi
 10ed410:	call   1085500 <myl_core_list_grow>
 10ed415:	mov    0x8(%rax),%rcx
 10ed419:	lea    -0x82de0(%rip),%rdx        # 106a640 <core_number_pairs+0x62f70>
 10ed420:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed425:	lea    0x1(%rcx),%rsi
 10ed429:	mov    %rsi,0x8(%rax)
 10ed42d:	cmp    $0x4,%rcx
 10ed431:	je     10ec59a <my.diagram_membership::compute_sub_block_attachments+0x2c6a>
 10ed437:	jmp    10ee3cf <my.diagram_membership::compute_sub_block_attachments+0x4a9f>
 10ed43c:	mov    $0x10,%esi
 10ed441:	mov    %r15,%rdi
 10ed444:	mov    %rax,%r14
 10ed447:	call   1085500 <myl_core_list_grow>
 10ed44c:	mov    %rax,%r15
 10ed44f:	mov    %r14,%rax
 10ed452:	mov    0x8(%r15),%rcx
 10ed456:	jmp    10ec5a8 <my.diagram_membership::compute_sub_block_attachments+0x2c78>
 10ed45b:	mov    $0x6,%edi
 10ed460:	mov    $0x8,%esi
 10ed465:	call   1085440 <myl_core_list_new_slow>
 10ed46a:	mov    0x8(%rax),%rsi
 10ed46e:	mov    %rbp,0x18(%rax)
 10ed472:	test   %rsi,%rsi
 10ed475:	jne    10ee485 <my.diagram_membership::compute_sub_block_attachments+0x4b55>
 10ed47b:	mov    0x10(%rax),%rcx
 10ed47f:	test   %rcx,%rcx
 10ed482:	jne    10ec60c <my.diagram_membership::compute_sub_block_attachments+0x2cdc>
 10ed488:	mov    $0x8,%esi
 10ed48d:	mov    %rax,%rdi
 10ed490:	call   1085500 <myl_core_list_grow>
 10ed495:	mov    0x8(%rax),%rcx
 10ed499:	lea    -0x82e20(%rip),%rdx        # 106a680 <core_number_pairs+0x62fb0>
 10ed4a0:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed4a5:	lea    0x1(%rcx),%rsi
 10ed4a9:	mov    %rsi,0x8(%rax)
 10ed4ad:	test   %rcx,%rcx
 10ed4b0:	jne    10ee74f <my.diagram_membership::compute_sub_block_attachments+0x4e1f>
 10ed4b6:	mov    0x10(%rax),%rcx
 10ed4ba:	cmp    $0x2,%rcx
 10ed4be:	jae    10ec629 <my.diagram_membership::compute_sub_block_attachments+0x2cf9>
 10ed4c4:	mov    $0x8,%esi
 10ed4c9:	mov    %rax,%rdi
 10ed4cc:	call   1085500 <myl_core_list_grow>
 10ed4d1:	mov    0x8(%rax),%rcx
 10ed4d5:	lea    -0x82e1c(%rip),%rdx        # 106a6c0 <core_number_pairs+0x62ff0>
 10ed4dc:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed4e1:	lea    0x1(%rcx),%rsi
 10ed4e5:	mov    %rsi,0x8(%rax)
 10ed4e9:	cmp    $0x1,%rcx
 10ed4ed:	jne    10ee3a5 <my.diagram_membership::compute_sub_block_attachments+0x4a75>
 10ed4f3:	mov    0x10(%rax),%rcx
 10ed4f7:	cmp    $0x3,%rcx
 10ed4fb:	jae    10ec646 <my.diagram_membership::compute_sub_block_attachments+0x2d16>
 10ed501:	mov    $0x8,%esi
 10ed506:	mov    %rax,%rdi
 10ed509:	call   1085500 <myl_core_list_grow>
 10ed50e:	mov    0x8(%rax),%rcx
 10ed512:	lea    -0x82e19(%rip),%rdx        # 106a700 <core_number_pairs+0x63030>
 10ed519:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed51e:	lea    0x1(%rcx),%rsi
 10ed522:	mov    %rsi,0x8(%rax)
 10ed526:	cmp    $0x2,%rcx
 10ed52a:	jne    10ee4e7 <my.diagram_membership::compute_sub_block_attachments+0x4bb7>
 10ed530:	mov    0x10(%rax),%rcx
 10ed534:	cmp    $0x4,%rcx
 10ed538:	jae    10ec663 <my.diagram_membership::compute_sub_block_attachments+0x2d33>
 10ed53e:	mov    $0x8,%esi
 10ed543:	mov    %rax,%rdi
 10ed546:	call   1085500 <myl_core_list_grow>
 10ed54b:	mov    0x8(%rax),%rcx
 10ed54f:	lea    -0x82e16(%rip),%rdx        # 106a740 <core_number_pairs+0x63070>
 10ed556:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed55b:	lea    0x1(%rcx),%rsi
 10ed55f:	mov    %rsi,0x8(%rax)
 10ed563:	cmp    $0x3,%rcx
 10ed567:	jne    10ee44d <my.diagram_membership::compute_sub_block_attachments+0x4b1d>
 10ed56d:	mov    0x10(%rax),%rcx
 10ed571:	cmp    $0x5,%rcx
 10ed575:	jae    10ec680 <my.diagram_membership::compute_sub_block_attachments+0x2d50>
 10ed57b:	mov    $0x8,%esi
 10ed580:	mov    %rax,%rdi
 10ed583:	call   1085500 <myl_core_list_grow>
 10ed588:	mov    0x8(%rax),%rcx
 10ed58c:	lea    -0x82e13(%rip),%rdx        # 106a780 <core_number_pairs+0x630b0>
 10ed593:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed598:	lea    0x1(%rcx),%rsi
 10ed59c:	mov    %rsi,0x8(%rax)
 10ed5a0:	cmp    $0x4,%rcx
 10ed5a4:	jne    10ee581 <my.diagram_membership::compute_sub_block_attachments+0x4c51>
 10ed5aa:	mov    0x10(%rax),%rcx
 10ed5ae:	cmp    $0x6,%rcx
 10ed5b2:	jae    10ec69d <my.diagram_membership::compute_sub_block_attachments+0x2d6d>
 10ed5b8:	mov    $0x8,%esi
 10ed5bd:	mov    %rax,%rdi
 10ed5c0:	call   1085500 <myl_core_list_grow>
 10ed5c5:	mov    0x8(%rax),%rcx
 10ed5c9:	lea    -0x82e10(%rip),%rdx        # 106a7c0 <core_number_pairs+0x630f0>
 10ed5d0:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed5d5:	lea    0x1(%rcx),%rsi
 10ed5d9:	mov    %rsi,0x8(%rax)
 10ed5dd:	cmp    $0x5,%rcx
 10ed5e1:	je     10ec6b0 <my.diagram_membership::compute_sub_block_attachments+0x2d80>
 10ed5e7:	jmp    10ee6df <my.diagram_membership::compute_sub_block_attachments+0x4daf>
 10ed5ec:	mov    $0x10,%esi
 10ed5f1:	mov    %r15,%rdi
 10ed5f4:	mov    %rax,%r14
 10ed5f7:	call   1085500 <myl_core_list_grow>
 10ed5fc:	mov    %rax,%r15
 10ed5ff:	mov    %r14,%rax
 10ed602:	mov    0x8(%r15),%rcx
 10ed606:	jmp    10ec6be <my.diagram_membership::compute_sub_block_attachments+0x2d8e>
 10ed60b:	mov    $0x6,%edi
 10ed610:	mov    $0x8,%esi
 10ed615:	call   1085440 <myl_core_list_new_slow>
 10ed61a:	mov    0x8(%rax),%rsi
 10ed61e:	mov    %rbp,0x18(%rax)
 10ed622:	test   %rsi,%rsi
 10ed625:	jne    10ee5f1 <my.diagram_membership::compute_sub_block_attachments+0x4cc1>
 10ed62b:	mov    0x10(%rax),%rcx
 10ed62f:	test   %rcx,%rcx
 10ed632:	jne    10ec722 <my.diagram_membership::compute_sub_block_attachments+0x2df2>
 10ed638:	mov    $0x8,%esi
 10ed63d:	mov    %rax,%rdi
 10ed640:	call   1085500 <myl_core_list_grow>
 10ed645:	mov    0x8(%rax),%rcx
 10ed649:	lea    -0x82e50(%rip),%rdx        # 106a800 <core_number_pairs+0x63130>
 10ed650:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed655:	lea    0x1(%rcx),%rsi
 10ed659:	mov    %rsi,0x8(%rax)
 10ed65d:	test   %rcx,%rcx
 10ed660:	jne    10ee733 <my.diagram_membership::compute_sub_block_attachments+0x4e03>
 10ed666:	mov    0x10(%rax),%rcx
 10ed66a:	cmp    $0x2,%rcx
 10ed66e:	jae    10ec73f <my.diagram_membership::compute_sub_block_attachments+0x2e0f>
 10ed674:	mov    $0x8,%esi
 10ed679:	mov    %rax,%rdi
 10ed67c:	call   1085500 <myl_core_list_grow>
 10ed681:	mov    0x8(%rax),%rcx
 10ed685:	lea    -0x82e4c(%rip),%rdx        # 106a840 <core_number_pairs+0x63170>
 10ed68c:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed691:	lea    0x1(%rcx),%rsi
 10ed695:	mov    %rsi,0x8(%rax)
 10ed699:	cmp    $0x1,%rcx
 10ed69d:	jne    10ee725 <my.diagram_membership::compute_sub_block_attachments+0x4df5>
 10ed6a3:	mov    0x10(%rax),%rcx
 10ed6a7:	cmp    $0x3,%rcx
 10ed6ab:	jae    10ec75c <my.diagram_membership::compute_sub_block_attachments+0x2e2c>
 10ed6b1:	mov    $0x8,%esi
 10ed6b6:	mov    %rax,%rdi
 10ed6b9:	call   1085500 <myl_core_list_grow>
 10ed6be:	mov    0x8(%rax),%rcx
 10ed6c2:	lea    -0x82e49(%rip),%rdx        # 106a880 <core_number_pairs+0x631b0>
 10ed6c9:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed6ce:	lea    0x1(%rcx),%rsi
 10ed6d2:	mov    %rsi,0x8(%rax)
 10ed6d6:	cmp    $0x2,%rcx
 10ed6da:	jne    10ee661 <my.diagram_membership::compute_sub_block_attachments+0x4d31>
 10ed6e0:	mov    0x10(%rax),%rcx
 10ed6e4:	cmp    $0x4,%rcx
 10ed6e8:	jae    10ec779 <my.diagram_membership::compute_sub_block_attachments+0x2e49>
 10ed6ee:	mov    $0x8,%esi
 10ed6f3:	mov    %rax,%rdi
 10ed6f6:	call   1085500 <myl_core_list_grow>
 10ed6fb:	mov    0x8(%rax),%rcx
 10ed6ff:	lea    -0x82e46(%rip),%rdx        # 106a8c0 <core_number_pairs+0x631f0>
 10ed706:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed70b:	lea    0x1(%rcx),%rsi
 10ed70f:	mov    %rsi,0x8(%rax)
 10ed713:	cmp    $0x3,%rcx
 10ed717:	jne    10ee5d5 <my.diagram_membership::compute_sub_block_attachments+0x4ca5>
 10ed71d:	mov    0x10(%rax),%rcx
 10ed721:	cmp    $0x5,%rcx
 10ed725:	jae    10ec796 <my.diagram_membership::compute_sub_block_attachments+0x2e66>
 10ed72b:	mov    $0x8,%esi
 10ed730:	mov    %rax,%rdi
 10ed733:	call   1085500 <myl_core_list_grow>
 10ed738:	mov    0x8(%rax),%rcx
 10ed73c:	lea    -0x82e43(%rip),%rdx        # 106a900 <core_number_pairs+0x63230>
 10ed743:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed748:	lea    0x1(%rcx),%rsi
 10ed74c:	mov    %rsi,0x8(%rax)
 10ed750:	cmp    $0x4,%rcx
 10ed754:	jne    10ee53b <my.diagram_membership::compute_sub_block_attachments+0x4c0b>
 10ed75a:	mov    0x10(%rax),%rcx
 10ed75e:	cmp    $0x6,%rcx
 10ed762:	jae    10ec7b3 <my.diagram_membership::compute_sub_block_attachments+0x2e83>
 10ed768:	mov    $0x8,%esi
 10ed76d:	mov    %rax,%rdi
 10ed770:	call   1085500 <myl_core_list_grow>
 10ed775:	mov    0x8(%rax),%rcx
 10ed779:	lea    -0x82e40(%rip),%rdx        # 106a940 <core_number_pairs+0x63270>
 10ed780:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed785:	lea    0x1(%rcx),%rsi
 10ed789:	mov    %rsi,0x8(%rax)
 10ed78d:	cmp    $0x5,%rcx
 10ed791:	je     10ec7c6 <my.diagram_membership::compute_sub_block_attachments+0x2e96>
 10ed797:	jmp    10ee6d1 <my.diagram_membership::compute_sub_block_attachments+0x4da1>
 10ed79c:	mov    $0x10,%esi
 10ed7a1:	mov    %r15,%rdi
 10ed7a4:	mov    %rax,%r14
 10ed7a7:	call   1085500 <myl_core_list_grow>
 10ed7ac:	mov    %rax,%r15
 10ed7af:	mov    %r14,%rax
 10ed7b2:	mov    0x8(%r15),%rcx
 10ed7b6:	jmp    10ec7d4 <my.diagram_membership::compute_sub_block_attachments+0x2ea4>
 10ed7bb:	mov    $0x6,%edi
 10ed7c0:	mov    $0x8,%esi
 10ed7c5:	call   1085440 <myl_core_list_new_slow>
 10ed7ca:	mov    0x8(%rax),%rsi
 10ed7ce:	mov    %rbp,0x18(%rax)
 10ed7d2:	test   %rsi,%rsi
 10ed7d5:	jne    10ee565 <my.diagram_membership::compute_sub_block_attachments+0x4c35>
 10ed7db:	mov    0x10(%rax),%rcx
 10ed7df:	test   %rcx,%rcx
 10ed7e2:	jne    10ec838 <my.diagram_membership::compute_sub_block_attachments+0x2f08>
 10ed7e8:	mov    $0x8,%esi
 10ed7ed:	mov    %rax,%rdi
 10ed7f0:	call   1085500 <myl_core_list_grow>
 10ed7f5:	mov    0x8(%rax),%rcx
 10ed7f9:	lea    -0x82e80(%rip),%rdx        # 106a980 <core_number_pairs+0x632b0>
 10ed800:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed805:	lea    0x1(%rcx),%rsi
 10ed809:	mov    %rsi,0x8(%rax)
 10ed80d:	test   %rcx,%rcx
 10ed810:	jne    10ee787 <my.diagram_membership::compute_sub_block_attachments+0x4e57>
 10ed816:	mov    0x10(%rax),%rcx
 10ed81a:	cmp    $0x2,%rcx
 10ed81e:	jae    10ec855 <my.diagram_membership::compute_sub_block_attachments+0x2f25>
 10ed824:	mov    $0x8,%esi
 10ed829:	mov    %rax,%rdi
 10ed82c:	call   1085500 <myl_core_list_grow>
 10ed831:	mov    0x8(%rax),%rcx
 10ed835:	lea    -0x82e7c(%rip),%rdx        # 106a9c0 <core_number_pairs+0x632f0>
 10ed83c:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed841:	lea    0x1(%rcx),%rsi
 10ed845:	mov    %rsi,0x8(%rax)
 10ed849:	cmp    $0x1,%rcx
 10ed84d:	jne    10ee68b <my.diagram_membership::compute_sub_block_attachments+0x4d5b>
 10ed853:	mov    0x10(%rax),%rcx
 10ed857:	cmp    $0x3,%rcx
 10ed85b:	jae    10ec872 <my.diagram_membership::compute_sub_block_attachments+0x2f42>
 10ed861:	mov    $0x8,%esi
 10ed866:	mov    %rax,%rdi
 10ed869:	call   1085500 <myl_core_list_grow>
 10ed86e:	mov    0x8(%rax),%rcx
 10ed872:	lea    -0x82e79(%rip),%rdx        # 106aa00 <core_number_pairs+0x63330>
 10ed879:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed87e:	lea    0x1(%rcx),%rsi
 10ed882:	mov    %rsi,0x8(%rax)
 10ed886:	cmp    $0x2,%rcx
 10ed88a:	jne    10ee5ff <my.diagram_membership::compute_sub_block_attachments+0x4ccf>
 10ed890:	mov    0x10(%rax),%rcx
 10ed894:	cmp    $0x4,%rcx
 10ed898:	jae    10ec88f <my.diagram_membership::compute_sub_block_attachments+0x2f5f>
 10ed89e:	mov    $0x8,%esi
 10ed8a3:	mov    %rax,%rdi
 10ed8a6:	call   1085500 <myl_core_list_grow>
 10ed8ab:	mov    0x8(%rax),%rcx
 10ed8af:	lea    -0x82e76(%rip),%rdx        # 106aa40 <core_number_pairs+0x63370>
 10ed8b6:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed8bb:	lea    0x1(%rcx),%rsi
 10ed8bf:	mov    %rsi,0x8(%rax)
 10ed8c3:	cmp    $0x3,%rcx
 10ed8c7:	jne    10ee573 <my.diagram_membership::compute_sub_block_attachments+0x4c43>
 10ed8cd:	mov    0x10(%rax),%rcx
 10ed8d1:	cmp    $0x5,%rcx
 10ed8d5:	jae    10ec8ac <my.diagram_membership::compute_sub_block_attachments+0x2f7c>
 10ed8db:	mov    $0x8,%esi
 10ed8e0:	mov    %rax,%rdi
 10ed8e3:	call   1085500 <myl_core_list_grow>
 10ed8e8:	mov    0x8(%rax),%rcx
 10ed8ec:	lea    -0x82e73(%rip),%rdx        # 106aa80 <core_number_pairs+0x633b0>
 10ed8f3:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed8f8:	lea    0x1(%rcx),%rsi
 10ed8fc:	mov    %rsi,0x8(%rax)
 10ed900:	cmp    $0x4,%rcx
 10ed904:	jne    10ee6fb <my.diagram_membership::compute_sub_block_attachments+0x4dcb>
 10ed90a:	mov    0x10(%rax),%rcx
 10ed90e:	cmp    $0x6,%rcx
 10ed912:	jae    10ec8c9 <my.diagram_membership::compute_sub_block_attachments+0x2f99>
 10ed918:	mov    $0x8,%esi
 10ed91d:	mov    %rax,%rdi
 10ed920:	call   1085500 <myl_core_list_grow>
 10ed925:	mov    0x8(%rax),%rcx
 10ed929:	lea    -0x82e70(%rip),%rdx        # 106aac0 <core_number_pairs+0x633f0>
 10ed930:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed935:	lea    0x1(%rcx),%rsi
 10ed939:	mov    %rsi,0x8(%rax)
 10ed93d:	cmp    $0x5,%rcx
 10ed941:	je     10ec8dc <my.diagram_membership::compute_sub_block_attachments+0x2fac>
 10ed947:	jmp    10ee637 <my.diagram_membership::compute_sub_block_attachments+0x4d07>
 10ed94c:	mov    $0x10,%esi
 10ed951:	mov    %r15,%rdi
 10ed954:	mov    %rax,%r14
 10ed957:	call   1085500 <myl_core_list_grow>
 10ed95c:	mov    %rax,%r15
 10ed95f:	mov    %r14,%rax
 10ed962:	mov    0x8(%r15),%rcx
 10ed966:	jmp    10ec8ea <my.diagram_membership::compute_sub_block_attachments+0x2fba>
 10ed96b:	mov    $0x5,%edi
 10ed970:	mov    $0x8,%esi
 10ed975:	call   1085440 <myl_core_list_new_slow>
 10ed97a:	mov    0x8(%rax),%rsi
 10ed97e:	mov    %rbp,0x18(%rax)
 10ed982:	test   %rsi,%rsi
 10ed985:	jne    10ee557 <my.diagram_membership::compute_sub_block_attachments+0x4c27>
 10ed98b:	mov    0x10(%rax),%rcx
 10ed98f:	test   %rcx,%rcx
 10ed992:	jne    10ec94e <my.diagram_membership::compute_sub_block_attachments+0x301e>
 10ed998:	mov    $0x8,%esi
 10ed99d:	mov    %rax,%rdi
 10ed9a0:	call   1085500 <myl_core_list_grow>
 10ed9a5:	mov    0x8(%rax),%rcx
 10ed9a9:	lea    -0x82eb0(%rip),%rdx        # 106ab00 <core_number_pairs+0x63430>
 10ed9b0:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed9b5:	lea    0x1(%rcx),%rsi
 10ed9b9:	mov    %rsi,0x8(%rax)
 10ed9bd:	test   %rcx,%rcx
 10ed9c0:	jne    10ee7a3 <my.diagram_membership::compute_sub_block_attachments+0x4e73>
 10ed9c6:	mov    0x10(%rax),%rcx
 10ed9ca:	cmp    $0x2,%rcx
 10ed9ce:	jae    10ec96b <my.diagram_membership::compute_sub_block_attachments+0x303b>
 10ed9d4:	mov    $0x8,%esi
 10ed9d9:	mov    %rax,%rdi
 10ed9dc:	call   1085500 <myl_core_list_grow>
 10ed9e1:	mov    0x8(%rax),%rcx
 10ed9e5:	lea    -0x82eac(%rip),%rdx        # 106ab40 <core_number_pairs+0x63470>
 10ed9ec:	mov    %rdx,0x20(%rax,%rcx,8)
 10ed9f1:	lea    0x1(%rcx),%rsi
 10ed9f5:	mov    %rsi,0x8(%rax)
 10ed9f9:	cmp    $0x1,%rcx
 10ed9fd:	jne    10ee66f <my.diagram_membership::compute_sub_block_attachments+0x4d3f>
 10eda03:	mov    0x10(%rax),%rcx
 10eda07:	cmp    $0x3,%rcx
 10eda0b:	jae    10ec988 <my.diagram_membership::compute_sub_block_attachments+0x3058>
 10eda11:	mov    $0x8,%esi
 10eda16:	mov    %rax,%rdi
 10eda19:	call   1085500 <myl_core_list_grow>
 10eda1e:	mov    0x8(%rax),%rcx
 10eda22:	lea    -0x82ea9(%rip),%rdx        # 106ab80 <core_number_pairs+0x634b0>
 10eda29:	mov    %rdx,0x20(%rax,%rcx,8)
 10eda2e:	lea    0x1(%rcx),%rsi
 10eda32:	mov    %rsi,0x8(%rax)
 10eda36:	cmp    $0x2,%rcx
 10eda3a:	jne    10ee58f <my.diagram_membership::compute_sub_block_attachments+0x4c5f>
 10eda40:	mov    0x10(%rax),%rcx
 10eda44:	cmp    $0x4,%rcx
 10eda48:	jae    10ec9a5 <my.diagram_membership::compute_sub_block_attachments+0x3075>
 10eda4e:	mov    $0x8,%esi
 10eda53:	mov    %rax,%rdi
 10eda56:	call   1085500 <myl_core_list_grow>
 10eda5b:	mov    0x8(%rax),%rcx
 10eda5f:	lea    -0x82ea6(%rip),%rdx        # 106abc0 <core_number_pairs+0x634f0>
 10eda66:	mov    %rdx,0x20(%rax,%rcx,8)
 10eda6b:	lea    0x1(%rcx),%rsi
 10eda6f:	mov    %rsi,0x8(%rax)
 10eda73:	cmp    $0x3,%rcx
 10eda77:	jne    10ee6ed <my.diagram_membership::compute_sub_block_attachments+0x4dbd>
 10eda7d:	mov    0x10(%rax),%rcx
 10eda81:	cmp    $0x5,%rcx
 10eda85:	jae    10ec9c2 <my.diagram_membership::compute_sub_block_attachments+0x3092>
 10eda8b:	mov    $0x8,%esi
 10eda90:	mov    %rax,%rdi
 10eda93:	call   1085500 <myl_core_list_grow>
 10eda98:	mov    0x8(%rax),%rcx
 10eda9c:	lea    -0x82ea3(%rip),%rdx        # 106ac00 <core_number_pairs+0x63530>
 10edaa3:	mov    %rdx,0x20(%rax,%rcx,8)
 10edaa8:	lea    0x1(%rcx),%rsi
 10edaac:	mov    %rsi,0x8(%rax)
 10edab0:	cmp    $0x4,%rcx
 10edab4:	je     10ec9d5 <my.diagram_membership::compute_sub_block_attachments+0x30a5>
 10edaba:	jmp    10ee6b5 <my.diagram_membership::compute_sub_block_attachments+0x4d85>
 10edabf:	mov    $0x10,%esi
 10edac4:	mov    %r15,%rdi
 10edac7:	mov    %rax,%r14
 10edaca:	call   1085500 <myl_core_list_grow>
 10edacf:	mov    %rax,%r15
 10edad2:	mov    %r14,%rax
 10edad5:	mov    0x8(%r15),%rcx
 10edad9:	jmp    10ec9e3 <my.diagram_membership::compute_sub_block_attachments+0x30b3>
 10edade:	mov    $0x4,%edi
 10edae3:	mov    $0x8,%esi
 10edae8:	call   1085440 <myl_core_list_new_slow>
 10edaed:	mov    0x8(%rax),%rsi
 10edaf1:	mov    %rbp,0x18(%rax)
 10edaf5:	test   %rsi,%rsi
 10edaf8:	jne    10ee59d <my.diagram_membership::compute_sub_block_attachments+0x4c6d>
 10edafe:	mov    0x10(%rax),%rcx
 10edb02:	test   %rcx,%rcx
 10edb05:	jne    10eca47 <my.diagram_membership::compute_sub_block_attachments+0x3117>
 10edb0b:	mov    $0x8,%esi
 10edb10:	mov    %rax,%rdi
 10edb13:	call   1085500 <myl_core_list_grow>
 10edb18:	mov    0x8(%rax),%rcx
 10edb1c:	lea    -0x82ee3(%rip),%rdx        # 106ac40 <core_number_pairs+0x63570>
 10edb23:	mov    %rdx,0x20(%rax,%rcx,8)
 10edb28:	lea    0x1(%rcx),%rsi
 10edb2c:	mov    %rsi,0x8(%rax)
 10edb30:	test   %rcx,%rcx
 10edb33:	jne    10ee779 <my.diagram_membership::compute_sub_block_attachments+0x4e49>
 10edb39:	mov    0x10(%rax),%rcx
 10edb3d:	cmp    $0x2,%rcx
 10edb41:	jae    10eca64 <my.diagram_membership::compute_sub_block_attachments+0x3134>
 10edb47:	mov    $0x8,%esi
 10edb4c:	mov    %rax,%rdi
 10edb4f:	call   1085500 <myl_core_list_grow>
 10edb54:	mov    0x8(%rax),%rcx
 10edb58:	lea    -0x82edf(%rip),%rdx        # 106ac80 <core_number_pairs+0x635b0>
 10edb5f:	mov    %rdx,0x20(%rax,%rcx,8)
 10edb64:	lea    0x1(%rcx),%rsi
 10edb68:	mov    %rsi,0x8(%rax)
 10edb6c:	cmp    $0x1,%rcx
 10edb70:	jne    10ee67d <my.diagram_membership::compute_sub_block_attachments+0x4d4d>
 10edb76:	mov    0x10(%rax),%rcx
 10edb7a:	cmp    $0x3,%rcx
 10edb7e:	jae    10eca81 <my.diagram_membership::compute_sub_block_attachments+0x3151>
 10edb84:	mov    $0x8,%esi
 10edb89:	mov    %rax,%rdi
 10edb8c:	call   1085500 <myl_core_list_grow>
 10edb91:	mov    0x8(%rax),%rcx
 10edb95:	lea    -0x82edc(%rip),%rdx        # 106acc0 <core_number_pairs+0x635f0>
 10edb9c:	mov    %rdx,0x20(%rax,%rcx,8)
 10edba1:	lea    0x1(%rcx),%rsi
 10edba5:	mov    %rsi,0x8(%rax)
 10edba9:	cmp    $0x2,%rcx
 10edbad:	jne    10ee5c7 <my.diagram_membership::compute_sub_block_attachments+0x4c97>
 10edbb3:	mov    0x10(%rax),%rcx
 10edbb7:	cmp    $0x4,%rcx
 10edbbb:	jae    10eca9e <my.diagram_membership::compute_sub_block_attachments+0x316e>
 10edbc1:	mov    $0x8,%esi
 10edbc6:	mov    %rax,%rdi
 10edbc9:	call   1085500 <myl_core_list_grow>
 10edbce:	mov    0x8(%rax),%rcx
 10edbd2:	lea    -0x82ed9(%rip),%rdx        # 106ad00 <core_number_pairs+0x63630>
 10edbd9:	mov    %rdx,0x20(%rax,%rcx,8)
 10edbde:	lea    0x1(%rcx),%rsi
 10edbe2:	mov    %rsi,0x8(%rax)
 10edbe6:	cmp    $0x3,%rcx
 10edbea:	je     10ecab1 <my.diagram_membership::compute_sub_block_attachments+0x3181>
 10edbf0:	jmp    10ee52d <my.diagram_membership::compute_sub_block_attachments+0x4bfd>
 10edbf5:	mov    $0x10,%esi
 10edbfa:	mov    %r15,%rdi
 10edbfd:	mov    %rax,%r14
 10edc00:	call   1085500 <myl_core_list_grow>
 10edc05:	mov    %rax,%r15
 10edc08:	mov    %r14,%rax
 10edc0b:	mov    0x8(%r15),%rcx
 10edc0f:	jmp    10ecabf <my.diagram_membership::compute_sub_block_attachments+0x318f>
 10edc14:	mov    $0x8,%edi
 10edc19:	mov    $0x8,%esi
 10edc1e:	call   1085440 <myl_core_list_new_slow>
 10edc23:	mov    0x8(%rax),%rsi
 10edc27:	mov    %rbp,0x18(%rax)
 10edc2b:	test   %rsi,%rsi
 10edc2e:	jne    10ee645 <my.diagram_membership::compute_sub_block_attachments+0x4d15>
 10edc34:	mov    0x10(%rax),%rcx
 10edc38:	test   %rcx,%rcx
 10edc3b:	jne    10ecb23 <my.diagram_membership::compute_sub_block_attachments+0x31f3>
 10edc41:	mov    $0x8,%esi
 10edc46:	mov    %rax,%rdi
 10edc49:	call   1085500 <myl_core_list_grow>
 10edc4e:	mov    0x8(%rax),%rcx
 10edc52:	lea    -0x82f19(%rip),%rdx        # 106ad40 <core_number_pairs+0x63670>
 10edc59:	mov    %rdx,0x20(%rax,%rcx,8)
 10edc5e:	lea    0x1(%rcx),%rsi
 10edc62:	mov    %rsi,0x8(%rax)
 10edc66:	test   %rcx,%rcx
 10edc69:	jne    10ee795 <my.diagram_membership::compute_sub_block_attachments+0x4e65>
 10edc6f:	mov    0x10(%rax),%rcx
 10edc73:	cmp    $0x2,%rcx
 10edc77:	jae    10ecb40 <my.diagram_membership::compute_sub_block_attachments+0x3210>
 10edc7d:	mov    $0x8,%esi
 10edc82:	mov    %rax,%rdi
 10edc85:	call   1085500 <myl_core_list_grow>
 10edc8a:	mov    0x8(%rax),%rcx
 10edc8e:	lea    -0x82f15(%rip),%rdx        # 106ad80 <core_number_pairs+0x636b0>
 10edc95:	mov    %rdx,0x20(%rax,%rcx,8)
 10edc9a:	lea    0x1(%rcx),%rsi
 10edc9e:	mov    %rsi,0x8(%rax)
 10edca2:	cmp    $0x1,%rcx
 10edca6:	jne    10ee709 <my.diagram_membership::compute_sub_block_attachments+0x4dd9>
 10edcac:	mov    0x10(%rax),%rcx
 10edcb0:	cmp    $0x3,%rcx
 10edcb4:	jae    10ecb5d <my.diagram_membership::compute_sub_block_attachments+0x322d>
 10edcba:	mov    $0x8,%esi
 10edcbf:	mov    %rax,%rdi
 10edcc2:	call   1085500 <myl_core_list_grow>
 10edcc7:	mov    0x8(%rax),%rcx
 10edccb:	lea    -0x82f12(%rip),%rdx        # 106adc0 <core_number_pairs+0x636f0>
 10edcd2:	mov    %rdx,0x20(%rax,%rcx,8)
 10edcd7:	lea    0x1(%rcx),%rsi
 10edcdb:	mov    %rsi,0x8(%rax)
 10edcdf:	cmp    $0x2,%rcx
 10edce3:	jne    10ee699 <my.diagram_membership::compute_sub_block_attachments+0x4d69>
 10edce9:	mov    0x10(%rax),%rcx
 10edced:	cmp    $0x4,%rcx
 10edcf1:	jae    10ecb7a <my.diagram_membership::compute_sub_block_attachments+0x324a>
 10edcf7:	mov    $0x8,%esi
 10edcfc:	mov    %rax,%rdi
 10edcff:	call   1085500 <myl_core_list_grow>
 10edd04:	mov    0x8(%rax),%rcx
 10edd08:	lea    -0x82f0f(%rip),%rdx        # 106ae00 <core_number_pairs+0x63730>
 10edd0f:	mov    %rdx,0x20(%rax,%rcx,8)
 10edd14:	lea    0x1(%rcx),%rsi
 10edd18:	mov    %rsi,0x8(%rax)
 10edd1c:	cmp    $0x3,%rcx
 10edd20:	jne    10ee60d <my.diagram_membership::compute_sub_block_attachments+0x4cdd>
 10edd26:	mov    0x10(%rax),%rcx
 10edd2a:	cmp    $0x5,%rcx
 10edd2e:	jae    10ecb97 <my.diagram_membership::compute_sub_block_attachments+0x3267>
 10edd34:	mov    $0x8,%esi
 10edd39:	mov    %rax,%rdi
 10edd3c:	call   1085500 <myl_core_list_grow>
 10edd41:	mov    0x8(%rax),%rcx
 10edd45:	lea    -0x82f0c(%rip),%rdx        # 106ae40 <core_number_pairs+0x63770>
 10edd4c:	mov    %rdx,0x20(%rax,%rcx,8)
 10edd51:	lea    0x1(%rcx),%rsi
 10edd55:	mov    %rsi,0x8(%rax)
 10edd59:	cmp    $0x4,%rcx
 10edd5d:	jne    10ee5ab <my.diagram_membership::compute_sub_block_attachments+0x4c7b>
 10edd63:	mov    0x10(%rax),%rcx
 10edd67:	cmp    $0x6,%rcx
 10edd6b:	jae    10ecbb4 <my.diagram_membership::compute_sub_block_attachments+0x3284>
 10edd71:	mov    $0x8,%esi
 10edd76:	mov    %rax,%rdi
 10edd79:	call   1085500 <myl_core_list_grow>
 10edd7e:	mov    0x8(%rax),%rcx
 10edd82:	lea    -0x82f09(%rip),%rdx        # 106ae80 <core_number_pairs+0x637b0>
 10edd89:	mov    %rdx,0x20(%rax,%rcx,8)
 10edd8e:	lea    0x1(%rcx),%rsi
 10edd92:	mov    %rsi,0x8(%rax)
 10edd96:	cmp    $0x5,%rcx
 10edd9a:	jne    10ee717 <my.diagram_membership::compute_sub_block_attachments+0x4de7>
 10edda0:	mov    0x10(%rax),%rcx
 10edda4:	cmp    $0x7,%rcx
 10edda8:	jae    10ecbd1 <my.diagram_membership::compute_sub_block_attachments+0x32a1>
 10eddae:	mov    $0x8,%esi
 10eddb3:	mov    %rax,%rdi
 10eddb6:	call   1085500 <myl_core_list_grow>
 10eddbb:	mov    0x8(%rax),%rcx
 10eddbf:	lea    -0x82f06(%rip),%rdx        # 106aec0 <core_number_pairs+0x637f0>
 10eddc6:	mov    %rdx,0x20(%rax,%rcx,8)
 10eddcb:	lea    0x1(%rcx),%rsi
 10eddcf:	mov    %rsi,0x8(%rax)
 10eddd3:	cmp    $0x6,%rcx
 10eddd7:	jne    10ee653 <my.diagram_membership::compute_sub_block_attachments+0x4d23>
 10edddd:	mov    0x10(%rax),%rcx
 10edde1:	cmp    $0x8,%rcx
 10edde5:	jae    10ecbee <my.diagram_membership::compute_sub_block_attachments+0x32be>
 10eddeb:	mov    $0x8,%esi
 10eddf0:	mov    %rax,%rdi
 10eddf3:	call   1085500 <myl_core_list_grow>
 10eddf8:	mov    0x8(%rax),%rcx
 10eddfc:	lea    -0x82f03(%rip),%rdx        # 106af00 <core_number_pairs+0x63830>
 10ede03:	mov    %rdx,0x20(%rax,%rcx,8)
 10ede08:	lea    0x1(%rcx),%rsi
 10ede0c:	mov    %rsi,0x8(%rax)
 10ede10:	cmp    $0x7,%rcx
 10ede14:	je     10ecc01 <my.diagram_membership::compute_sub_block_attachments+0x32d1>
 10ede1a:	jmp    10ee5e3 <my.diagram_membership::compute_sub_block_attachments+0x4cb3>
 10ede1f:	mov    $0x10,%esi
 10ede24:	mov    %r15,%rdi
 10ede27:	mov    %rax,%r14
 10ede2a:	call   1085500 <myl_core_list_grow>
 10ede2f:	mov    %rax,%r15
 10ede32:	mov    %r14,%rax
 10ede35:	mov    0x8(%r15),%rcx
 10ede39:	jmp    10ecc0f <my.diagram_membership::compute_sub_block_attachments+0x32df>
 10ede3e:	xchg   %ax,%ax
 10ede40:	mov    0xc0(%rsp),%rsi
 10ede48:	mov    0x8(%rsi),%rdx
 10ede4c:	cmpq   $0x0,0x40(%rsp)
 10ede52:	jle    10edf1a <my.diagram_membership::compute_sub_block_attachments+0x45ea>
 10ede58:	mov    0x88(%rsp),%r8
 10ede60:	cmp    %rdx,%r8
 10ede63:	jae    10ee105 <my.diagram_membership::compute_sub_block_attachments+0x47d5>
 10ede69:	mov    %r8,%rax
 10ede6c:	shl    $0x4,%rax
 10ede70:	movzbl %bl,%ecx
 10ede73:	mov    0xf0(%rsp),%rdx
 10ede7b:	mov    %rcx,(%rdx,%rax,1)
 10ede7f:	mov    %r15,0x8(%rdx,%rax,1)
 10ede84:	mov    0x8(%rsi),%rdx
 10ede88:	movabs $0x800000000000,%rax
 10ede92:	cmp    %rax,%rdx
 10ede95:	jbe    10edf40 <my.diagram_membership::compute_sub_block_attachments+0x4610>
 10ede9b:	jmp    10ee962 <my.diagram_membership::compute_sub_block_attachments+0x5032>
 10edea0:	mov    0x10(%rsp),%rdi
 10edea5:	call   1086200 <myl_core_drop_owned>
 10edeaa:	mov    0xc0(%rsp),%rcx
 10edeb2:	mov    0x88(%rsp),%r8
 10edeba:	lea    -0x797c9(%rip),%rbp        # 10746f8 <core_number_pairs+0x6d028>
 10edec1:	mov    0x70(%rsp),%rax
 10edec6:	mov    0x28(%rax,%r15,1),%rsi
 10edecb:	cmp    0xe0(%rsp),%rsi
 10eded3:	ja     10ee943 <my.diagram_membership::compute_sub_block_attachments+0x5013>
 10eded9:	mov    0x8(%rcx),%rdx
 10ededd:	cmp    %rdx,%r8
 10edee0:	jae    10ee0da <my.diagram_membership::compute_sub_block_attachments+0x47aa>
 10edee6:	mov    %r8,%rax
 10edee9:	shl    $0x4,%rax
 10edeed:	mov    0xf0(%rsp),%rdx
 10edef5:	movq   $0x1,(%rdx,%rax,1)
 10edefd:	mov    %rsi,0x8(%rdx,%rax,1)
 10edf02:	mov    0x8(%rcx),%rdx
 10edf06:	movabs $0x800000000000,%rax
 10edf10:	cmp    %rax,%rdx
 10edf13:	jbe    10edf40 <my.diagram_membership::compute_sub_block_attachments+0x4610>
 10edf15:	jmp    10ee951 <my.diagram_membership::compute_sub_block_attachments+0x5021>
 10edf1a:	movabs $0x800000000000,%rax
 10edf24:	cmp    %rax,%rdx
 10edf27:	mov    0x88(%rsp),%r8
 10edf2f:	ja     10ee932 <my.diagram_membership::compute_sub_block_attachments+0x5002>
 10edf35:	data16 cs nopw 0x0(%rax,%rax,1)
 10edf40:	cmp    0xe0(%rsp),%r8
 10edf48:	ja     10ee917 <my.diagram_membership::compute_sub_block_attachments+0x4fe7>
 10edf4e:	inc    %r8
 10edf51:	cmp    %rax,%rdx
 10edf54:	jbe    10ebee0 <my.diagram_membership::compute_sub_block_attachments+0x25b0>
 10edf5a:	jmp    10ee090 <my.diagram_membership::compute_sub_block_attachments+0x4760>
 10edf5f:	mov    0x20(%rcx),%r12
 10edf63:	test   %r12,%r12
 10edf66:	je     10ec055 <my.diagram_membership::compute_sub_block_attachments+0x2725>
 10edf6c:	mov    0x10(%rcx),%r13
 10edf70:	mov    0xf8(%rsp),%rbx
 10edf78:	xor    %r15d,%r15d
 10edf7b:	jmp    10edf90 <my.diagram_membership::compute_sub_block_attachments+0x4660>
 10edf7d:	nopl   (%rax)
 10edf80:	inc    %r15
 10edf83:	add    $0x10,%rbx
 10edf87:	cmp    %r15,%r12
 10edf8a:	je     10ec055 <my.diagram_membership::compute_sub_block_attachments+0x2725>
 10edf90:	cmp    %r14,0x0(%r13,%r15,8)
 10edf95:	jne    10edf80 <my.diagram_membership::compute_sub_block_attachments+0x4650>
 10edf97:	mov    (%rbx),%rdi
 10edf9a:	mov    0x118(%rsp),%rsi
 10edfa2:	call   108e040 <myl_core_str_eq>
 10edfa7:	test   %al,%al
 10edfa9:	je     10edf80 <my.diagram_membership::compute_sub_block_attachments+0x4650>
 10edfab:	jmp    10ec093 <my.diagram_membership::compute_sub_block_attachments+0x2763>
 10edfb0:	lea    0x65429(%rip),%rdi        # 11533e0 <core_durable_error.verbs+0x2ee0>
 10edfb7:	call   10b9340 <myl_core_err_trace_origin_preserve_most>
 10edfbc:	mov    $0x1,%al
 10edfbe:	lea    -0x88f85(%rip),%rdi        # 1065040 <core_number_pairs+0x5d970>
 10edfc5:	test   %al,%al
 10edfc7:	je     10ebf44 <my.diagram_membership::compute_sub_block_attachments+0x2614>
 10edfcd:	call   1086200 <myl_core_drop_owned>
 10edfd2:	lea    0x65437(%rip),%rdi        # 1153410 <core_durable_error.verbs+0x2f10>
 10edfd9:	call   108c300 <myl_core_assert_fail>
 10edfde:	lea    0x6dafb(%rip),%rdi        # 115bae0 <core_durable_error.verbs+0xb5e0>
 10edfe5:	call   1086f80 <myl_core_trap>
 10edfea:	mov    0x70(%rsp),%rdi
 10edfef:	call   1086200 <myl_core_drop_owned>
 10edff4:	mov    0x60(%rsp),%rdi
 10edff9:	call   1086200 <myl_core_drop_owned>
 10edffe:	mov    0xc0(%rsp),%rdi
 10ee006:	mov    %rdi,%rax
 10ee009:	add    $0x1d8,%rsp
 10ee010:	pop    %rbx
 10ee011:	pop    %r12
 10ee013:	pop    %r13
 10ee015:	pop    %r14
 10ee017:	pop    %r15
 10ee019:	pop    %rbp
 10ee01a:	ret
 10ee01b:	lea    0x6dd8e(%rip),%rdi        # 115bdb0 <core_durable_error.verbs+0xb8b0>
 10ee022:	call   1086f80 <myl_core_trap>
 10ee027:	lea    0x6ddb2(%rip),%rdi        # 115bde0 <core_durable_error.verbs+0xb8e0>
 10ee02e:	mov    %r13,%rsi
 10ee031:	call   1086f80 <myl_core_trap>
 10ee036:	lea    0x6d833(%rip),%rdi        # 115b870 <core_durable_error.verbs+0xb370>
 10ee03d:	mov    %r8,%rsi
 10ee040:	call   1086f80 <myl_core_trap>
 10ee045:	lea    0x6d494(%rip),%rdi        # 115b4e0 <core_durable_error.verbs+0xafe0>
 10ee04c:	xor    %edx,%edx
 10ee04e:	call   1086f80 <myl_core_trap>
 10ee053:	lea    0x6d4b6(%rip),%rdi        # 115b510 <core_durable_error.verbs+0xb010>
 10ee05a:	xor    %edx,%edx
 10ee05c:	call   1086f80 <myl_core_trap>
 10ee061:	lea    0x70838(%rip),%rdi        # 115e8a0 <core_durable_error.verbs+0xe3a0>
 10ee068:	mov    %r15,%rsi
 10ee06b:	call   1086f80 <myl_core_trap>
 10ee070:	call   1086200 <myl_core_drop_owned>
 10ee075:	lea    0x65394(%rip),%rdi        # 1153410 <core_durable_error.verbs+0x2f10>
 10ee07c:	call   108c300 <myl_core_assert_fail>
 10ee081:	lea    0x6db78(%rip),%rdi        # 115bc00 <core_durable_error.verbs+0xb700>
 10ee088:	mov    %r8,%rsi
 10ee08b:	call   1086f80 <myl_core_trap>
 10ee090:	lea    0x6db09(%rip),%rdi        # 115bba0 <core_durable_error.verbs+0xb6a0>
 10ee097:	mov    %rdx,%rsi
 10ee09a:	xor    %edx,%edx
 10ee09c:	call   1086f80 <myl_core_trap>
 10ee0a1:	lea    0x80ab8(%rip),%rdi        # 116eb60 <core_durable_error.verbs+0x1e660>
 10ee0a8:	mov    %r9,%rsi
 10ee0ab:	xor    %edx,%edx
 10ee0ad:	call   1086f80 <myl_core_trap>
 10ee0b2:	cmp    %rcx,%rdx
 10ee0b5:	cmova  %rdx,%rcx
 10ee0b9:	lea    0x80ad0(%rip),%rdi        # 116eb90 <core_durable_error.verbs+0x1e690>
 10ee0c0:	mov    %rcx,%rsi
 10ee0c3:	call   1086f80 <myl_core_trap>
 10ee0c8:	lea    0x80a61(%rip),%rdi        # 116eb30 <core_durable_error.verbs+0x1e630>
 10ee0cf:	mov    %rcx,%rsi
 10ee0d2:	mov    %r8,%rdx
 10ee0d5:	call   1086f80 <myl_core_trap>
 10ee0da:	lea    0x6db7f(%rip),%rdi        # 115bc60 <core_durable_error.verbs+0xb760>
 10ee0e1:	mov    %r8,%rsi
 10ee0e4:	call   1086f80 <myl_core_trap>
 10ee0e9:	lea    0x6d8a0(%rip),%rdi        # 115b990 <core_durable_error.verbs+0xb490>
 10ee0f0:	xor    %edx,%edx
 10ee0f2:	call   1086f80 <myl_core_trap>
 10ee0f7:	lea    0x6d8c2(%rip),%rdi        # 115b9c0 <core_durable_error.verbs+0xb4c0>
 10ee0fe:	xor    %edx,%edx
 10ee100:	call   1086f80 <myl_core_trap>
 10ee105:	lea    0x6dd34(%rip),%rdi        # 115be40 <core_durable_error.verbs+0xb940>
 10ee10c:	mov    %r8,%rsi
 10ee10f:	call   1086f80 <myl_core_trap>
 10ee114:	mov    $0x10,%esi
 10ee119:	xor    %edi,%edi
 10ee11b:	call   1085440 <myl_core_list_new_slow>
 10ee120:	mov    %rax,%rdi
 10ee123:	mov    0x8(%rax),%rsi
 10ee127:	test   %rsi,%rsi
 10ee12a:	je     10e9979 <my.diagram_membership::compute_sub_block_attachments+0x49>
 10ee130:	lea    0x6d199(%rip),%rdi        # 115b2d0 <core_durable_error.verbs+0xadd0>
 10ee137:	xor    %edx,%edx
 10ee139:	call   1086f80 <myl_core_trap>
 10ee13e:	inc    %rcx
 10ee141:	lea    0x6d458(%rip),%rdi        # 115b5a0 <core_durable_error.verbs+0xb0a0>
 10ee148:	mov    %rcx,%rsi
 10ee14b:	xor    %edx,%edx
 10ee14d:	call   1086f80 <myl_core_trap>
 10ee152:	call   1086200 <myl_core_drop_owned>
 10ee157:	lea    0x652b2(%rip),%rdi        # 1153410 <core_durable_error.verbs+0x2f10>
 10ee15e:	call   108c300 <myl_core_assert_fail>
 10ee163:	lea    0x6d466(%rip),%rdi        # 115b5d0 <core_durable_error.verbs+0xb0d0>
 10ee16a:	mov    %r12,%rsi
 10ee16d:	call   1086f80 <myl_core_trap>
 10ee172:	lea    0x6d5d7(%rip),%rdi        # 115b750 <core_durable_error.verbs+0xb250>
 10ee179:	mov    %rbx,%rsi
 10ee17c:	call   1086f80 <myl_core_trap>
 10ee181:	inc    %rcx
 10ee184:	lea    0x6d595(%rip),%rdi        # 115b720 <core_durable_error.verbs+0xb220>
 10ee18b:	mov    %rcx,%rsi
 10ee18e:	xor    %edx,%edx
 10ee190:	call   1086f80 <myl_core_trap>
 10ee195:	lea    0x6d8e4(%rip),%rdi        # 115ba80 <core_durable_error.verbs+0xb580>
 10ee19c:	mov    %rax,%rsi
 10ee19f:	call   1086f80 <myl_core_trap>
 10ee1a4:	lea    0x6d8a5(%rip),%rdi        # 115ba50 <core_durable_error.verbs+0xb550>
 10ee1ab:	mov    %rax,%rsi
 10ee1ae:	xor    %edx,%edx
 10ee1b0:	call   1086f80 <myl_core_trap>
 10ee1b5:	lea    0x6d834(%rip),%rdi        # 115b9f0 <core_durable_error.verbs+0xb4f0>
 10ee1bc:	xor    %edx,%edx
 10ee1be:	call   1086f80 <myl_core_trap>
 10ee1c3:	lea    0x6d8e6(%rip),%rdi        # 115bab0 <core_durable_error.verbs+0xb5b0>
 10ee1ca:	xor    %edx,%edx
 10ee1cc:	call   1086f80 <myl_core_trap>
 10ee1d1:	lea    0x6d848(%rip),%rdi        # 115ba20 <core_durable_error.verbs+0xb520>
 10ee1d8:	call   1086f80 <myl_core_trap>
 10ee1dd:	lea    0x6d92c(%rip),%rdi        # 115bb10 <core_durable_error.verbs+0xb610>
 10ee1e4:	mov    $0x1,%edx
 10ee1e9:	mov    %rax,%rsi
 10ee1ec:	call   1086f80 <myl_core_trap>
 10ee1f1:	lea    0x6d978(%rip),%rdi        # 115bb70 <core_durable_error.verbs+0xb670>
 10ee1f8:	mov    %rdx,%rsi
 10ee1fb:	xor    %edx,%edx
 10ee1fd:	call   1086f80 <myl_core_trap>
 10ee202:	lea    0x6d937(%rip),%rdi        # 115bb40 <core_durable_error.verbs+0xb640>
 10ee209:	movabs $0x8000000000000000,%rsi
 10ee213:	xor    %edx,%edx
 10ee215:	call   1086f80 <myl_core_trap>
 10ee21a:	lea    0x72fbf(%rip),%rdi        # 11611e0 <core_durable_error.verbs+0x10ce0>
 10ee221:	mov    %rcx,%rsi
 10ee224:	xor    %edx,%edx
 10ee226:	call   1086f80 <myl_core_trap>
 10ee22b:	lea    0x72fde(%rip),%rdi        # 1161210 <core_durable_error.verbs+0x10d10>
 10ee232:	mov    %rax,%rsi
 10ee235:	call   1086f80 <myl_core_trap>
 10ee23a:	mov    $0x8,%esi
 10ee23f:	xor    %edi,%edi
 10ee241:	call   1085440 <myl_core_list_new_slow>
 10ee246:	mov    0x58(%rsp),%rdx
 10ee24b:	movabs $0x800000000000,%rcx
 10ee255:	mov    %rax,0x60(%rsp)
 10ee25a:	mov    0x8(%rax),%rsi
 10ee25e:	test   %rsi,%rsi
 10ee261:	je     10eaff2 <my.diagram_membership::compute_sub_block_attachments+0x16c2>
 10ee267:	lea    0x6d482(%rip),%rdi        # 115b6f0 <core_durable_error.verbs+0xb1f0>
 10ee26e:	xor    %edx,%edx
 10ee270:	call   1086f80 <myl_core_trap>
 10ee275:	lea    0x6d684(%rip),%rdi        # 115b900 <core_durable_error.verbs+0xb400>
 10ee27c:	xor    %edx,%edx
 10ee27e:	call   1086f80 <myl_core_trap>
 10ee283:	lea    0x6d6a6(%rip),%rdi        # 115b930 <core_durable_error.verbs+0xb430>
 10ee28a:	xor    %edx,%edx
 10ee28c:	call   1086f80 <myl_core_trap>
 10ee291:	inc    %rcx
 10ee294:	lea    0x6d635(%rip),%rdi        # 115b8d0 <core_durable_error.verbs+0xb3d0>
 10ee29b:	mov    %rcx,%rsi
 10ee29e:	xor    %edx,%edx
 10ee2a0:	call   1086f80 <myl_core_trap>
 10ee2a5:	lea    0x70624(%rip),%rdi        # 115e8d0 <core_durable_error.verbs+0xe3d0>
 10ee2ac:	mov    %r14,%rsi
 10ee2af:	call   1086f80 <myl_core_trap>
 10ee2b4:	call   1086200 <myl_core_drop_owned>
 10ee2b9:	lea    0x65150(%rip),%rdi        # 1153410 <core_durable_error.verbs+0x2f10>
 10ee2c0:	call   108c300 <myl_core_assert_fail>
 10ee2c5:	lea    0x70574(%rip),%rdi        # 115e840 <core_durable_error.verbs+0xe340>
 10ee2cc:	mov    %r14,%rsi
 10ee2cf:	xor    %edx,%edx
 10ee2d1:	call   1086f80 <myl_core_trap>
 10ee2d6:	lea    0x70533(%rip),%rdi        # 115e810 <core_durable_error.verbs+0xe310>
 10ee2dd:	mov    %r8,%rsi
 10ee2e0:	call   1086f80 <myl_core_trap>
 10ee2e5:	lea    0x80784(%rip),%rdi        # 116ea70 <core_durable_error.verbs+0x1e570>
 10ee2ec:	mov    %rax,%rsi
 10ee2ef:	xor    %edx,%edx
 10ee2f1:	call   1086f80 <myl_core_trap>
 10ee2f6:	lea    0x807a3(%rip),%rdi        # 116eaa0 <core_durable_error.verbs+0x1e5a0>
 10ee2fd:	mov    %rdx,%rsi
 10ee300:	xor    %edx,%edx
 10ee302:	call   1086f80 <myl_core_trap>
 10ee307:	mov    %rbp,%rdi
 10ee30a:	call   1086200 <myl_core_drop_owned>
 10ee30f:	lea    0x6d19a(%rip),%rdi        # 115b4b0 <core_durable_error.verbs+0xafb0>
 10ee316:	xor    %esi,%esi
 10ee318:	xor    %edx,%edx
 10ee31a:	call   1086f80 <myl_core_trap>
 10ee31f:	lea    0x807da(%rip),%rdi        # 116eb00 <core_durable_error.verbs+0x1e600>
 10ee326:	mov    %r8,%rsi
 10ee329:	xor    %edx,%edx
 10ee32b:	call   1086f80 <myl_core_trap>
 10ee330:	lea    0x78339(%rip),%rdi        # 1166670 <core_durable_error.verbs+0x16170>
 10ee337:	xor    %edx,%edx
 10ee339:	call   1086f80 <myl_core_trap>
 10ee33e:	lea    0x6d9ab(%rip),%rdi        # 115bcf0 <core_durable_error.verbs+0xb7f0>
 10ee345:	mov    0x88(%rsp),%rsi
 10ee34d:	mov    %r10,%rdx
 10ee350:	call   1086f80 <myl_core_trap>
 10ee355:	lea    0x6d9c4(%rip),%rdi        # 115bd20 <core_durable_error.verbs+0xb820>
 10ee35c:	mov    %r11,%rsi
 10ee35f:	xor    %edx,%edx
 10ee361:	call   1086f80 <myl_core_trap>
 10ee366:	lea    0x6d9e3(%rip),%rdi        # 115bd50 <core_durable_error.verbs+0xb850>
 10ee36d:	mov    %r11,%rsi
 10ee370:	mov    %r13,%rdx
 10ee373:	call   1086f80 <myl_core_trap>
 10ee378:	lea    0x6da01(%rip),%rdi        # 115bd80 <core_durable_error.verbs+0xb880>
 10ee37f:	xor    %edx,%edx
 10ee381:	call   1086f80 <myl_core_trap>
 10ee386:	inc    %rsi
 10ee389:	lea    0x6d930(%rip),%rdi        # 115bcc0 <core_durable_error.verbs+0xb7c0>
 10ee390:	xor    %edx,%edx
 10ee392:	call   1086f80 <myl_core_trap>
 10ee397:	lea    0x6d5c2(%rip),%rdi        # 115b960 <core_durable_error.verbs+0xb460>
 10ee39e:	xor    %edx,%edx
 10ee3a0:	call   1086f80 <myl_core_trap>
 10ee3a5:	lea    0x77a54(%rip),%rdi        # 1165e00 <core_durable_error.verbs+0x15900>
 10ee3ac:	xor    %edx,%edx
 10ee3ae:	call   1086f80 <myl_core_trap>
 10ee3b3:	lea    0x77836(%rip),%rdi        # 1165bf0 <core_durable_error.verbs+0x156f0>
 10ee3ba:	xor    %edx,%edx
 10ee3bc:	call   1086f80 <myl_core_trap>
 10ee3c1:	lea    0x77618(%rip),%rdi        # 11659e0 <core_durable_error.verbs+0x154e0>
 10ee3c8:	xor    %edx,%edx
 10ee3ca:	call   1086f80 <myl_core_trap>
 10ee3cf:	lea    0x7796a(%rip),%rdi        # 1165d40 <core_durable_error.verbs+0x15840>
 10ee3d6:	xor    %edx,%edx
 10ee3d8:	call   1086f80 <myl_core_trap>
 10ee3dd:	lea    0x7774c(%rip),%rdi        # 1165b30 <core_durable_error.verbs+0x15630>
 10ee3e4:	xor    %edx,%edx
 10ee3e6:	call   1086f80 <myl_core_trap>
 10ee3eb:	lea    0x7767e(%rip),%rdi        # 1165a70 <core_durable_error.verbs+0x15570>
 10ee3f2:	xor    %edx,%edx
 10ee3f4:	call   1086f80 <myl_core_trap>
 10ee3f9:	lea    0x77520(%rip),%rdi        # 1165920 <core_durable_error.verbs+0x15420>
 10ee400:	xor    %edx,%edx
 10ee402:	call   1086f80 <myl_core_trap>
 10ee407:	lea    0x777b2(%rip),%rdi        # 1165bc0 <core_durable_error.verbs+0x156c0>
 10ee40e:	xor    %edx,%edx
 10ee410:	call   1086f80 <myl_core_trap>
 10ee415:	lea    0x77594(%rip),%rdi        # 11659b0 <core_durable_error.verbs+0x154b0>
 10ee41c:	xor    %edx,%edx
 10ee41e:	call   1086f80 <myl_core_trap>
 10ee423:	lea    0x778e6(%rip),%rdi        # 1165d10 <core_durable_error.verbs+0x15810>
 10ee42a:	xor    %edx,%edx
 10ee42c:	call   1086f80 <myl_core_trap>
 10ee431:	lea    0x77608(%rip),%rdi        # 1165a40 <core_durable_error.verbs+0x15540>
 10ee438:	xor    %edx,%edx
 10ee43a:	call   1086f80 <myl_core_trap>
 10ee43f:	lea    0x7780a(%rip),%rdi        # 1165c50 <core_durable_error.verbs+0x15750>
 10ee446:	xor    %edx,%edx
 10ee448:	call   1086f80 <myl_core_trap>
 10ee44d:	lea    0x77a0c(%rip),%rdi        # 1165e60 <core_durable_error.verbs+0x15960>
 10ee454:	xor    %edx,%edx
 10ee456:	call   1086f80 <myl_core_trap>
 10ee45b:	lea    0x7769e(%rip),%rdi        # 1165b00 <core_durable_error.verbs+0x15600>
 10ee462:	xor    %edx,%edx
 10ee464:	call   1086f80 <myl_core_trap>
 10ee469:	lea    0x77510(%rip),%rdi        # 1165980 <core_durable_error.verbs+0x15480>
 10ee470:	xor    %edx,%edx
 10ee472:	call   1086f80 <myl_core_trap>
 10ee477:	lea    0x77712(%rip),%rdi        # 1165b90 <core_durable_error.verbs+0x15690>
 10ee47e:	xor    %edx,%edx
 10ee480:	call   1086f80 <myl_core_trap>
 10ee485:	lea    0x77914(%rip),%rdi        # 1165da0 <core_durable_error.verbs+0x158a0>
 10ee48c:	xor    %edx,%edx
 10ee48e:	call   1086f80 <myl_core_trap>
 10ee493:	lea    0x77846(%rip),%rdi        # 1165ce0 <core_durable_error.verbs+0x157e0>
 10ee49a:	xor    %edx,%edx
 10ee49c:	call   1086f80 <myl_core_trap>
 10ee4a1:	lea    0x77418(%rip),%rdi        # 11658c0 <core_durable_error.verbs+0x153c0>
 10ee4a8:	xor    %edx,%edx
 10ee4aa:	call   1086f80 <myl_core_trap>
 10ee4af:	lea    0x7749a(%rip),%rdi        # 1165950 <core_durable_error.verbs+0x15450>
 10ee4b6:	xor    %edx,%edx
 10ee4b8:	call   1086f80 <myl_core_trap>
 10ee4bd:	lea    0x7775c(%rip),%rdi        # 1165c20 <core_durable_error.verbs+0x15720>
 10ee4c4:	xor    %edx,%edx
 10ee4c6:	call   1086f80 <myl_core_trap>
 10ee4cb:	lea    0x7753e(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x15510>
 10ee4d2:	xor    %edx,%edx
 10ee4d4:	call   1086f80 <myl_core_trap>
 10ee4d9:	lea    0x77890(%rip),%rdi        # 1165d70 <core_durable_error.verbs+0x15870>
 10ee4e0:	xor    %edx,%edx
 10ee4e2:	call   1086f80 <myl_core_trap>
 10ee4e7:	lea    0x77942(%rip),%rdi        # 1165e30 <core_durable_error.verbs+0x15930>
 10ee4ee:	xor    %edx,%edx
 10ee4f0:	call   1086f80 <myl_core_trap>
 10ee4f5:	lea    0x77664(%rip),%rdi        # 1165b60 <core_durable_error.verbs+0x15660>
 10ee4fc:	xor    %edx,%edx
 10ee4fe:	call   1086f80 <myl_core_trap>
 10ee503:	lea    0x77386(%rip),%rdi        # 1165890 <core_durable_error.verbs+0x15390>
 10ee50a:	xor    %edx,%edx
 10ee50c:	call   1086f80 <myl_core_trap>
 10ee511:	lea    0x77588(%rip),%rdi        # 1165aa0 <core_durable_error.verbs+0x155a0>
 10ee518:	xor    %edx,%edx
 10ee51a:	call   1086f80 <myl_core_trap>
 10ee51f:	lea    0x7778a(%rip),%rdi        # 1165cb0 <core_durable_error.verbs+0x157b0>
 10ee526:	xor    %edx,%edx
 10ee528:	call   1086f80 <myl_core_trap>
 10ee52d:	lea    0x77efc(%rip),%rdi        # 1166430 <core_durable_error.verbs+0x15f30>
 10ee534:	xor    %edx,%edx
 10ee536:	call   1086f80 <myl_core_trap>
 10ee53b:	lea    0x77ace(%rip),%rdi        # 1166010 <core_durable_error.verbs+0x15b10>
 10ee542:	xor    %edx,%edx
 10ee544:	call   1086f80 <myl_core_trap>
 10ee549:	lea    0x780f0(%rip),%rdi        # 1166640 <core_durable_error.verbs+0x16140>
 10ee550:	xor    %edx,%edx
 10ee552:	call   1086f80 <myl_core_trap>
 10ee557:	lea    0x77cc2(%rip),%rdi        # 1166220 <core_durable_error.verbs+0x15d20>
 10ee55e:	xor    %edx,%edx
 10ee560:	call   1086f80 <myl_core_trap>
 10ee565:	lea    0x77b34(%rip),%rdi        # 11660a0 <core_durable_error.verbs+0x15ba0>
 10ee56c:	xor    %edx,%edx
 10ee56e:	call   1086f80 <myl_core_trap>
 10ee573:	lea    0x77be6(%rip),%rdi        # 1166160 <core_durable_error.verbs+0x15c60>
 10ee57a:	xor    %edx,%edx
 10ee57c:	call   1086f80 <myl_core_trap>
 10ee581:	lea    0x77908(%rip),%rdi        # 1165e90 <core_durable_error.verbs+0x15990>
 10ee588:	xor    %edx,%edx
 10ee58a:	call   1086f80 <myl_core_trap>
 10ee58f:	lea    0x77d1a(%rip),%rdi        # 11662b0 <core_durable_error.verbs+0x15db0>
 10ee596:	xor    %edx,%edx
 10ee598:	call   1086f80 <myl_core_trap>
 10ee59d:	lea    0x77dcc(%rip),%rdi        # 1166370 <core_durable_error.verbs+0x15e70>
 10ee5a4:	xor    %edx,%edx
 10ee5a6:	call   1086f80 <myl_core_trap>
 10ee5ab:	lea    0x77fce(%rip),%rdi        # 1166580 <core_durable_error.verbs+0x16080>
 10ee5b2:	xor    %edx,%edx
 10ee5b4:	call   1086f80 <myl_core_trap>
 10ee5b9:	lea    0x77c30(%rip),%rdi        # 11661f0 <core_durable_error.verbs+0x15cf0>
 10ee5c0:	xor    %edx,%edx
 10ee5c2:	call   1086f80 <myl_core_trap>
 10ee5c7:	lea    0x77e32(%rip),%rdi        # 1166400 <core_durable_error.verbs+0x15f00>
 10ee5ce:	xor    %edx,%edx
 10ee5d0:	call   1086f80 <myl_core_trap>
 10ee5d5:	lea    0x77a04(%rip),%rdi        # 1165fe0 <core_durable_error.verbs+0x15ae0>
 10ee5dc:	xor    %edx,%edx
 10ee5de:	call   1086f80 <myl_core_trap>
 10ee5e3:	lea    0x78026(%rip),%rdi        # 1166610 <core_durable_error.verbs+0x16110>
 10ee5ea:	xor    %edx,%edx
 10ee5ec:	call   1086f80 <myl_core_trap>
 10ee5f1:	lea    0x77928(%rip),%rdi        # 1165f20 <core_durable_error.verbs+0x15a20>
 10ee5f8:	xor    %edx,%edx
 10ee5fa:	call   1086f80 <myl_core_trap>
 10ee5ff:	lea    0x77b2a(%rip),%rdi        # 1166130 <core_durable_error.verbs+0x15c30>
 10ee606:	xor    %edx,%edx
 10ee608:	call   1086f80 <myl_core_trap>
 10ee60d:	lea    0x77f3c(%rip),%rdi        # 1166550 <core_durable_error.verbs+0x16050>
 10ee614:	xor    %edx,%edx
 10ee616:	call   1086f80 <myl_core_trap>
 10ee61b:	lea    0x77d1e(%rip),%rdi        # 1166340 <core_durable_error.verbs+0x15e40>
 10ee622:	xor    %edx,%edx
 10ee624:	call   1086f80 <myl_core_trap>
 10ee629:	lea    0x77a40(%rip),%rdi        # 1166070 <core_durable_error.verbs+0x15b70>
 10ee630:	xor    %edx,%edx
 10ee632:	call   1086f80 <myl_core_trap>
 10ee637:	lea    0x77b82(%rip),%rdi        # 11661c0 <core_durable_error.verbs+0x15cc0>
 10ee63e:	xor    %edx,%edx
 10ee640:	call   1086f80 <myl_core_trap>
 10ee645:	lea    0x77e44(%rip),%rdi        # 1166490 <core_durable_error.verbs+0x15f90>
 10ee64c:	xor    %edx,%edx
 10ee64e:	call   1086f80 <myl_core_trap>
 10ee653:	lea    0x77f86(%rip),%rdi        # 11665e0 <core_durable_error.verbs+0x160e0>
 10ee65a:	xor    %edx,%edx
 10ee65c:	call   1086f80 <myl_core_trap>
 10ee661:	lea    0x77948(%rip),%rdi        # 1165fb0 <core_durable_error.verbs+0x15ab0>
 10ee668:	xor    %edx,%edx
 10ee66a:	call   1086f80 <myl_core_trap>
 10ee66f:	lea    0x77c0a(%rip),%rdi        # 1166280 <core_durable_error.verbs+0x15d80>
 10ee676:	xor    %edx,%edx
 10ee678:	call   1086f80 <myl_core_trap>
 10ee67d:	lea    0x77d4c(%rip),%rdi        # 11663d0 <core_durable_error.verbs+0x15ed0>
 10ee684:	xor    %edx,%edx
 10ee686:	call   1086f80 <myl_core_trap>
 10ee68b:	lea    0x77a6e(%rip),%rdi        # 1166100 <core_durable_error.verbs+0x15c00>
 10ee692:	xor    %edx,%edx
 10ee694:	call   1086f80 <myl_core_trap>
 10ee699:	lea    0x77e80(%rip),%rdi        # 1166520 <core_durable_error.verbs+0x16020>
 10ee6a0:	xor    %edx,%edx
 10ee6a2:	call   1086f80 <myl_core_trap>
 10ee6a7:	lea    0x77842(%rip),%rdi        # 1165ef0 <core_durable_error.verbs+0x159f0>
 10ee6ae:	xor    %edx,%edx
 10ee6b0:	call   1086f80 <myl_core_trap>
 10ee6b5:	lea    0x77c54(%rip),%rdi        # 1166310 <core_durable_error.verbs+0x15e10>
 10ee6bc:	xor    %edx,%edx
 10ee6be:	call   1086f80 <myl_core_trap>
 10ee6c3:	lea    0x77d96(%rip),%rdi        # 1166460 <core_durable_error.verbs+0x15f60>
 10ee6ca:	xor    %edx,%edx
 10ee6cc:	call   1086f80 <myl_core_trap>
 10ee6d1:	lea    0x77968(%rip),%rdi        # 1166040 <core_durable_error.verbs+0x15b40>
 10ee6d8:	xor    %edx,%edx
 10ee6da:	call   1086f80 <myl_core_trap>
 10ee6df:	lea    0x777da(%rip),%rdi        # 1165ec0 <core_durable_error.verbs+0x159c0>
 10ee6e6:	xor    %edx,%edx
 10ee6e8:	call   1086f80 <myl_core_trap>
 10ee6ed:	lea    0x77bec(%rip),%rdi        # 11662e0 <core_durable_error.verbs+0x15de0>
 10ee6f4:	xor    %edx,%edx
 10ee6f6:	call   1086f80 <myl_core_trap>
 10ee6fb:	lea    0x77a8e(%rip),%rdi        # 1166190 <core_durable_error.verbs+0x15c90>
 10ee702:	xor    %edx,%edx
 10ee704:	call   1086f80 <myl_core_trap>
 10ee709:	lea    0x77de0(%rip),%rdi        # 11664f0 <core_durable_error.verbs+0x15ff0>
 10ee710:	xor    %edx,%edx
 10ee712:	call   1086f80 <myl_core_trap>
 10ee717:	lea    0x77e92(%rip),%rdi        # 11665b0 <core_durable_error.verbs+0x160b0>
 10ee71e:	xor    %edx,%edx
 10ee720:	call   1086f80 <myl_core_trap>
 10ee725:	lea    0x77854(%rip),%rdi        # 1165f80 <core_durable_error.verbs+0x15a80>
 10ee72c:	xor    %edx,%edx
 10ee72e:	call   1086f80 <myl_core_trap>
 10ee733:	lea    0x77816(%rip),%rdi        # 1165f50 <core_durable_error.verbs+0x15a50>
 10ee73a:	xor    %edx,%edx
 10ee73c:	call   1086f80 <myl_core_trap>
 10ee741:	lea    0x77538(%rip),%rdi        # 1165c80 <core_durable_error.verbs+0x15780>
 10ee748:	xor    %edx,%edx
 10ee74a:	call   1086f80 <myl_core_trap>
 10ee74f:	lea    0x7767a(%rip),%rdi        # 1165dd0 <core_durable_error.verbs+0x158d0>
 10ee756:	xor    %edx,%edx
 10ee758:	call   1086f80 <myl_core_trap>
 10ee75d:	lea    0x7718c(%rip),%rdi        # 11658f0 <core_durable_error.verbs+0x153f0>
 10ee764:	xor    %edx,%edx
 10ee766:	call   1086f80 <myl_core_trap>
 10ee76b:	lea    0x7735e(%rip),%rdi        # 1165ad0 <core_durable_error.verbs+0x155d0>
 10ee772:	xor    %edx,%edx
 10ee774:	call   1086f80 <myl_core_trap>
 10ee779:	lea    0x77c20(%rip),%rdi        # 11663a0 <core_durable_error.verbs+0x15ea0>
 10ee780:	xor    %edx,%edx
 10ee782:	call   1086f80 <myl_core_trap>
 10ee787:	lea    0x77942(%rip),%rdi        # 11660d0 <core_durable_error.verbs+0x15bd0>
 10ee78e:	xor    %edx,%edx
 10ee790:	call   1086f80 <myl_core_trap>
 10ee795:	lea    0x77d24(%rip),%rdi        # 11664c0 <core_durable_error.verbs+0x15fc0>
 10ee79c:	xor    %edx,%edx
 10ee79e:	call   1086f80 <myl_core_trap>
 10ee7a3:	lea    0x77aa6(%rip),%rdi        # 1166250 <core_durable_error.verbs+0x15d50>
 10ee7aa:	xor    %edx,%edx
 10ee7ac:	call   1086f80 <myl_core_trap>
 10ee7b1:	movabs $0x8000000000000000,%rsi
 10ee7bb:	dec    %rsi
 10ee7be:	lea    0x803fb(%rip),%rdi        # 116ebc0 <core_durable_error.verbs+0x1e6c0>
 10ee7c5:	mov    $0x1,%edx
 10ee7ca:	call   1086f80 <myl_core_trap>
 10ee7cf:	lea    0x802fa(%rip),%rdi        # 116ead0 <core_durable_error.verbs+0x1e5d0>
 10ee7d6:	mov    %rcx,%rsi
 10ee7d9:	mov    %rax,%rdx
 10ee7dc:	call   1086f80 <myl_core_trap>
 10ee7e1:	lea    0x6cb78(%rip),%rdi        # 115b360 <core_durable_error.verbs+0xae60>
 10ee7e8:	xor    %edx,%edx
 10ee7ea:	call   1086f80 <myl_core_trap>
 10ee7ef:	inc    %rcx
 10ee7f2:	lea    0x6cb37(%rip),%rdi        # 115b330 <core_durable_error.verbs+0xae30>
 10ee7f9:	mov    %rcx,%rsi
 10ee7fc:	xor    %edx,%edx
 10ee7fe:	call   1086f80 <myl_core_trap>
 10ee803:	lea    0x729a6(%rip),%rdi        # 11611b0 <core_durable_error.verbs+0x10cb0>
 10ee80a:	call   1086f80 <myl_core_trap>
 10ee80f:	lea    0x7296a(%rip),%rdi        # 1161180 <core_durable_error.verbs+0x10c80>
 10ee816:	call   1086f80 <myl_core_trap>
 10ee81b:	lea    0x7292e(%rip),%rdi        # 1161150 <core_durable_error.verbs+0x10c50>
 10ee822:	xor    %edx,%edx
 10ee824:	call   1086f80 <myl_core_trap>
 10ee829:	inc    %rsi
 10ee82c:	lea    0x6cbed(%rip),%rdi        # 115b420 <core_durable_error.verbs+0xaf20>
 10ee833:	xor    %edx,%edx
 10ee835:	call   1086f80 <myl_core_trap>
 10ee83a:	lea    0x6cc0f(%rip),%rdi        # 115b450 <core_durable_error.verbs+0xaf50>
 10ee841:	mov    %rax,%rsi
 10ee844:	call   1086f80 <myl_core_trap>
 10ee849:	lea    0x6cd20(%rip),%rdi        # 115b570 <core_durable_error.verbs+0xb070>
 10ee850:	mov    0x28(%rsp),%rsi
 10ee855:	xor    %edx,%edx
 10ee857:	call   1086f80 <myl_core_trap>
 10ee85c:	lea    0x6cdcd(%rip),%rdi        # 115b630 <core_durable_error.verbs+0xb130>
 10ee863:	call   1086f80 <myl_core_trap>
 10ee868:	lea    0x6cdf1(%rip),%rdi        # 115b660 <core_durable_error.verbs+0xb160>
 10ee86f:	mov    %r14,%rsi
 10ee872:	xor    %edx,%edx
 10ee874:	call   1086f80 <myl_core_trap>
 10ee879:	inc    %rcx
 10ee87c:	lea    0x6cd7d(%rip),%rdi        # 115b600 <core_durable_error.verbs+0xb100>
 10ee883:	mov    %rcx,%rsi
 10ee886:	xor    %edx,%edx
 10ee888:	call   1086f80 <myl_core_trap>
 10ee88d:	mov    %rbp,%rdi
 10ee890:	call   1086200 <myl_core_drop_owned>
 10ee895:	lea    0x64b74(%rip),%rdi        # 1153410 <core_durable_error.verbs+0x2f10>
 10ee89c:	call   108c300 <myl_core_assert_fail>
 10ee8a1:	lea    0x6cf38(%rip),%rdi        # 115b7e0 <core_durable_error.verbs+0xb2e0>
 10ee8a8:	xor    %edx,%edx
 10ee8aa:	call   1086f80 <myl_core_trap>
 10ee8af:	lea    0x6cf8a(%rip),%rdi        # 115b840 <core_durable_error.verbs+0xb340>
 10ee8b6:	xor    %edx,%edx
 10ee8b8:	call   1086f80 <myl_core_trap>
 10ee8bd:	lea    0x6ff1c(%rip),%rdi        # 115e7e0 <core_durable_error.verbs+0xe2e0>
 10ee8c4:	xor    %edx,%edx
 10ee8c6:	call   1086f80 <myl_core_trap>
 10ee8cb:	lea    0x6ff9e(%rip),%rdi        # 115e870 <core_durable_error.verbs+0xe370>
 10ee8d2:	mov    %r15,%rsi
 10ee8d5:	xor    %edx,%edx
 10ee8d7:	call   1086f80 <myl_core_trap>
 10ee8dc:	lea    0x6cfbd(%rip),%rdi        # 115b8a0 <core_durable_error.verbs+0xb3a0>
 10ee8e3:	mov    0x90(%rsp),%rsi
 10ee8eb:	xor    %edx,%edx
 10ee8ed:	call   1086f80 <myl_core_trap>
 10ee8f2:	inc    %rcx
 10ee8f5:	lea    0x6cf14(%rip),%rdi        # 115b810 <core_durable_error.verbs+0xb310>
 10ee8fc:	mov    %rcx,%rsi
 10ee8ff:	xor    %edx,%edx
 10ee901:	call   1086f80 <myl_core_trap>
 10ee906:	lea    0x6cb73(%rip),%rdi        # 115b480 <core_durable_error.verbs+0xaf80>
 10ee90d:	mov    %r14,%rsi
 10ee910:	xor    %edx,%edx
 10ee912:	call   1086f80 <myl_core_trap>
 10ee917:	movabs $0x800000000000,%rsi
 10ee921:	inc    %rsi
 10ee924:	lea    0x6d2a5(%rip),%rdi        # 115bbd0 <core_durable_error.verbs+0xb6d0>
 10ee92b:	xor    %edx,%edx
 10ee92d:	call   1086f80 <myl_core_trap>
 10ee932:	lea    0x6d4d7(%rip),%rdi        # 115be10 <core_durable_error.verbs+0xb910>
 10ee939:	mov    %rdx,%rsi
 10ee93c:	xor    %edx,%edx
 10ee93e:	call   1086f80 <myl_core_trap>
 10ee943:	lea    0x6d2e6(%rip),%rdi        # 115bc30 <core_durable_error.verbs+0xb730>
 10ee94a:	xor    %edx,%edx
 10ee94c:	call   1086f80 <myl_core_trap>
 10ee951:	lea    0x6d338(%rip),%rdi        # 115bc90 <core_durable_error.verbs+0xb790>
 10ee958:	mov    %rdx,%rsi
 10ee95b:	xor    %edx,%edx
 10ee95d:	call   1086f80 <myl_core_trap>
 10ee962:	lea    0x6d507(%rip),%rdi        # 115be70 <core_durable_error.verbs+0xb970>
 10ee969:	mov    %rdx,%rsi
 10ee96c:	xor    %edx,%edx
 10ee96e:	call   1086f80 <myl_core_trap>
 10ee973:	lea    0x6c986(%rip),%rdi        # 115b300 <core_durable_error.verbs+0xae00>
 10ee97a:	mov    %r14,%rsi
 10ee97d:	xor    %edx,%edx
 10ee97f:	call   1086f80 <myl_core_trap>
 10ee984:	lea    0x6ca05(%rip),%rdi        # 115b390 <core_durable_error.verbs+0xae90>
 10ee98b:	xor    %edx,%edx
 10ee98d:	call   1086f80 <myl_core_trap>
 10ee992:	lea    0x6ca57(%rip),%rdi        # 115b3f0 <core_durable_error.verbs+0xaef0>
 10ee999:	xor    %edx,%edx
 10ee99b:	call   1086f80 <myl_core_trap>
 10ee9a0:	lea    0x6ca19(%rip),%rdi        # 115b3c0 <core_durable_error.verbs+0xaec0>
 10ee9a7:	mov    0x28(%rsp),%rsi
 10ee9ac:	xor    %edx,%edx
 10ee9ae:	call   1086f80 <myl_core_trap>
 10ee9b3:	lea    0x6cb86(%rip),%rdi        # 115b540 <core_durable_error.verbs+0xb040>
 10ee9ba:	mov    0x58(%rsp),%rsi
 10ee9bf:	xor    %edx,%edx
 10ee9c1:	call   1086f80 <myl_core_trap>
 10ee9c6:	lea    0x6ccc3(%rip),%rdi        # 115b690 <core_durable_error.verbs+0xb190>
 10ee9cd:	mov    %rdx,%rsi
 10ee9d0:	xor    %edx,%edx
 10ee9d2:	call   1086f80 <myl_core_trap>
 10ee9d7:	lea    0x6cce2(%rip),%rdi        # 115b6c0 <core_durable_error.verbs+0xb1c0>
 10ee9de:	mov    0xe8(%rsp),%rsi
 10ee9e6:	xor    %edx,%edx
 10ee9e8:	call   1086f80 <myl_core_trap>
 10ee9ed:	lea    0x6cd8c(%rip),%rdi        # 115b780 <core_durable_error.verbs+0xb280>
 10ee9f4:	mov    0xe8(%rsp),%rsi
 10ee9fc:	call   1086f80 <myl_core_trap>
 10eea01:	lea    0x6cda8(%rip),%rdi        # 115b7b0 <core_durable_error.verbs+0xb2b0>
 10eea08:	mov    %rbx,%rsi
 10eea0b:	xor    %edx,%edx
 10eea0d:	call   1086f80 <myl_core_trap>

Disassembly of section .plt:
