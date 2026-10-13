
/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/dm-001/candidate-matched:     file format elf64-x86-64


Disassembly of section .text:

0000000001099de0 <my.diagram_membership::compute_sub_block_attachments>:
 1099de0:	push   %rbp
 1099de1:	push   %r15
 1099de3:	push   %r14
 1099de5:	push   %r13
 1099de7:	push   %r12
 1099de9:	push   %rbx
 1099dea:	sub    $0x1b8,%rsp
 1099df1:	mov    %fs:0xfffffffffffffec8,%rax
 1099dfa:	test   %rax,%rax
 1099dfd:	je     109d9f2 <my.diagram_membership::compute_sub_block_attachments+0x3c12>
 1099e03:	mov    (%rax),%rcx
 1099e06:	mov    %rcx,%fs:0xfffffffffffffec8
 1099e0f:	movl   $0x1000000,(%rax)
 1099e15:	vpxor  %xmm0,%xmm0,%xmm0
 1099e19:	vmovdqu %xmm0,0x8(%rax)
 1099e1e:	movq   $0x0,0x18(%rax)
 1099e26:	mov    0x30(%rdi),%rcx
 1099e2a:	mov    %rcx,0xa0(%rsp)
 1099e32:	mov    0x8(%rcx),%rbx
 1099e36:	test   %rbx,%rbx
 1099e39:	je     109d9bb <my.diagram_membership::compute_sub_block_attachments+0x3bdb>
 1099e3f:	mov    0x8(%rax),%rdx
 1099e43:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1099e52:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1099e61:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1099e70:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1099e7f:	nop
 1099e80:	cmp    0x10(%rax),%rdx
 1099e84:	jae    1099ea4 <my.diagram_membership::compute_sub_block_attachments+0xc4>
 1099e86:	mov    %rdx,%rcx
 1099e89:	shl    $0x4,%rcx
 1099e8d:	movq   $0x0,0x20(%rax,%rcx,1)
 1099e96:	inc    %rdx
 1099e99:	mov    %rdx,0x8(%rax)
 1099e9d:	dec    %rbx
 1099ea0:	jne    1099e80 <my.diagram_membership::compute_sub_block_attachments+0xa0>
 1099ea2:	jmp    1099ebd <my.diagram_membership::compute_sub_block_attachments+0xdd>
 1099ea4:	mov    $0x10,%esi
 1099ea9:	mov    %rdi,%r14
 1099eac:	mov    %rax,%rdi
 1099eaf:	call   103ba40 <myl_core_list_grow>
 1099eb4:	mov    %r14,%rdi
 1099eb7:	mov    0x8(%rax),%rdx
 1099ebb:	jmp    1099e86 <my.diagram_membership::compute_sub_block_attachments+0xa6>
 1099ebd:	mov    0xa0(%rsp),%rcx
 1099ec5:	cmpq   $0x0,0x8(%rcx)
 1099eca:	je     109d9bb <my.diagram_membership::compute_sub_block_attachments+0x3bdb>
 1099ed0:	mov    0x38(%rdi),%rcx
 1099ed4:	mov    %rcx,0x70(%rsp)
 1099ed9:	cmpq   $0x0,0x8(%rcx)
 1099ede:	je     109d9bb <my.diagram_membership::compute_sub_block_attachments+0x3bdb>
 1099ee4:	mov    %rax,0xc0(%rsp)
 1099eec:	lea    0x5d925(%rip),%rsi        # 10f7818 <core_durable_error.verbs+0xd258>
 1099ef3:	mov    %rdi,%rbx
 1099ef6:	xor    %edi,%edi
 1099ef8:	call   1042f80 <myl_core_dict_new>
 1099efd:	mov    %rax,0x8(%rsp)
 1099f02:	mov    0x60(%rbx),%rbx
 1099f06:	mov    0x8(%rbx),%rax
 1099f0a:	mov    %rax,0x48(%rsp)
 1099f0f:	test   %rax,%rax
 1099f12:	je     109a9f1 <my.diagram_membership::compute_sub_block_attachments+0xc11>
 1099f18:	add    $0x20,%rbx
 1099f1c:	xor    %eax,%eax
 1099f1e:	mov    %rbx,0x28(%rsp)
 1099f23:	jmp    1099f61 <my.diagram_membership::compute_sub_block_attachments+0x181>
 1099f25:	data16 cs nopw 0x0(%rax,%rax,1)
 1099f30:	mov    0x30(%rsp),%rdi
 1099f35:	call   103c740 <myl_core_drop_owned>
 1099f3a:	mov    0x8(%rsp),%rax
 1099f3f:	mov    0x10(%rsp),%rcx
 1099f44:	mov    %rcx,0x28(%rax,%r12,1)
 1099f49:	mov    0x28(%rsp),%rbx
 1099f4e:	mov    0x50(%rsp),%rax
 1099f53:	inc    %rax
 1099f56:	cmp    0x48(%rsp),%rax
 1099f5b:	je     109a9f1 <my.diagram_membership::compute_sub_block_attachments+0xc11>
 1099f61:	mov    %rax,0x50(%rsp)
 1099f66:	shl    $0x4,%rax
 1099f6a:	mov    (%rbx,%rax,1),%r14
 1099f6e:	mov    0x8(%rbx,%rax,1),%r15
 1099f73:	mov    %r14,%rdi
 1099f76:	lea    -0x7e93d(%rip),%r13        # 101b640 <core_number_pairs+0x140f0>
 1099f7d:	mov    %r13,%rsi
 1099f80:	call   1047e80 <myl_core_bytes_find>
 1099f85:	mov    %rax,%r12
 1099f88:	mov    %r15,%rdi
 1099f8b:	mov    %r13,%rsi
 1099f8e:	call   1047e80 <myl_core_bytes_find>
 1099f93:	mov    %rax,%r13
 1099f96:	test   %r12,%r12
 1099f99:	sets   %al
 1099f9c:	test   %r13,%r13
 1099f9f:	setns  %cl
 1099fa2:	test   %cl,%al
 1099fa4:	je     1099fc0 <my.diagram_membership::compute_sub_block_attachments+0x1e0>
 1099fa6:	mov    %r14,%rdi
 1099fa9:	call   103cfc0 <myl_core_owned_octets_copy>
 1099fae:	mov    %rax,%rbx
 1099fb1:	mov    %r15,%rdi
 1099fb4:	xor    %esi,%esi
 1099fb6:	mov    %r13,%rdx
 1099fb9:	jmp    1099fea <my.diagram_membership::compute_sub_block_attachments+0x20a>
 1099fbb:	nopl   0x0(%rax,%rax,1)
 1099fc0:	test   %r13,%r13
 1099fc3:	sets   %al
 1099fc6:	test   %r12,%r12
 1099fc9:	setns  %cl
 1099fcc:	and    %al,%cl
 1099fce:	cmp    $0x1,%cl
 1099fd1:	jne    1099f4e <my.diagram_membership::compute_sub_block_attachments+0x16e>
 1099fd7:	mov    %r15,%rdi
 1099fda:	call   103cfc0 <myl_core_owned_octets_copy>
 1099fdf:	mov    %rax,%rbx
 1099fe2:	mov    %r14,%rdi
 1099fe5:	xor    %esi,%esi
 1099fe7:	mov    %r12,%rdx
 1099fea:	call   1047c80 <myl_core_bytes_slice>
 1099fef:	mov    %rax,%r13
 1099ff2:	mov    %rbx,%rdi
 1099ff5:	call   104ba40 <myl_core_bytes_utf8_count>
 1099ffa:	test   %rax,%rax
 1099ffd:	js     109a9a6 <my.diagram_membership::compute_sub_block_attachments+0xbc6>
 109a003:	mov    %rbx,%rdi
 109a006:	call   104bb00 <myl_core_bytes_decode_text>
 109a00b:	mov    %rax,%rbp
 109a00e:	xor    %eax,%eax
 109a010:	mov    %rbp,0x10(%rsp)
 109a015:	test   %al,%al
 109a017:	jne    109db32 <my.diagram_membership::compute_sub_block_attachments+0x3d52>
 109a01d:	mov    %rbx,%rdi
 109a020:	call   103c740 <myl_core_drop_owned>
 109a025:	mov    %rbp,0x140(%rsp)
 109a02d:	testb  $0x2,0x1(%rbp)
 109a031:	jne    109a040 <my.diagram_membership::compute_sub_block_attachments+0x260>
 109a033:	mov    %rbp,%rdi
 109a036:	call   1044400 <myl_core_str_hash>
 109a03b:	jmp    109a043 <my.diagram_membership::compute_sub_block_attachments+0x263>
 109a03d:	nopl   (%rax)
 109a040:	mov    0x18(%rbp),%eax
 109a043:	mov    %eax,%eax
 109a045:	movabs $0x9e3779b97f4a7c15,%rcx
 109a04f:	imul   %rcx,%rax
 109a053:	mov    %rax,%rbx
 109a056:	shr    $0x20,%rbx
 109a05a:	xor    %rax,%rbx
 109a05d:	mov    0x8(%rsp),%rax
 109a062:	mov    0x18(%rax),%rcx
 109a066:	mov    0x8(%rcx),%rax
 109a06a:	test   %rax,%rax
 109a06d:	mov    %rbp,0x30(%rsp)
 109a072:	mov    %r13,0x80(%rsp)
 109a07a:	je     109a160 <my.diagram_membership::compute_sub_block_attachments+0x380>
 109a080:	mov    (%rax),%ecx
 109a082:	tzcnt  %ecx,%edx
 109a086:	neg    %dl
 109a088:	shrx   %rdx,%rbx,%r14
 109a08d:	vmovdqu 0x10(%rax,%r14,1),%xmm1
 109a094:	mov    %ebx,%edx
 109a096:	and    $0x7f,%dl
 109a099:	vmovd  %edx,%xmm0
 109a09d:	vpbroadcastb %xmm0,%xmm0
 109a0a2:	vmovdqa %xmm1,0x60(%rsp)
 109a0a8:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109a0ac:	vpmovmskb %xmm0,%edx
 109a0b0:	test   %edx,%edx
 109a0b2:	je     109a138 <my.diagram_membership::compute_sub_block_attachments+0x358>
 109a0b8:	lea    -0x1(%rcx),%ebp
 109a0bb:	add    $0x1e,%ecx
 109a0be:	and    $0xfffffff0,%ecx
 109a0c1:	lea    (%rax,%rcx,1),%r15
 109a0c5:	add    $0x10,%r15
 109a0c9:	movzwl %dx,%r12d
 109a0cd:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a0dc:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a0eb:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a0fa:	nopw   0x0(%rax,%rax,1)
 109a100:	tzcnt  %r12d,%eax
 109a105:	add    %r14d,%eax
 109a108:	and    %ebp,%eax
 109a10a:	mov    (%r15,%rax,4),%eax
 109a10e:	shl    $0x4,%rax
 109a112:	mov    0x8(%rsp),%rcx
 109a117:	mov    0x20(%rcx,%rax,1),%rdi
 109a11c:	mov    0x140(%rsp),%rsi
 109a124:	call   1044580 <myl_core_str_eq>
 109a129:	test   %al,%al
 109a12b:	jne    109a545 <my.diagram_membership::compute_sub_block_attachments+0x765>
 109a131:	blsr   %r12d,%r12d
 109a136:	jne    109a100 <my.diagram_membership::compute_sub_block_attachments+0x320>
 109a138:	vmovdqa 0x60(%rsp),%xmm0
 109a13e:	vpcmpeqb -0x95d76(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109a146:	vpmovmskb %xmm0,%eax
 109a14a:	test   %eax,%eax
 109a14c:	mov    0x30(%rsp),%rbp
 109a151:	jne    109a1f0 <my.diagram_membership::compute_sub_block_attachments+0x410>
 109a157:	jmp    109a167 <my.diagram_membership::compute_sub_block_attachments+0x387>
 109a159:	nopl   0x0(%rax)
 109a160:	cmpq   $0x0,0x18(%rcx)
 109a165:	je     109a18a <my.diagram_membership::compute_sub_block_attachments+0x3aa>
 109a167:	mov    0x8(%rsp),%rdi
 109a16c:	lea    0x140(%rsp),%rsi
 109a174:	mov    %rbx,%rdx
 109a177:	call   1042bc0 <myl_core_dict_find>
 109a17c:	mov    %rax,%r12
 109a17f:	test   %r12,%r12
 109a182:	jns    109a5a3 <my.diagram_membership::compute_sub_block_attachments+0x7c3>
 109a188:	jmp    109a1f0 <my.diagram_membership::compute_sub_block_attachments+0x410>
 109a18a:	mov    0x20(%rcx),%r14
 109a18e:	test   %r14,%r14
 109a191:	je     109a1f0 <my.diagram_membership::compute_sub_block_attachments+0x410>
 109a193:	mov    0x10(%rcx),%r15
 109a197:	mov    0x8(%rsp),%rax
 109a19c:	lea    0x20(%rax),%r13
 109a1a0:	xor    %r12d,%r12d
 109a1a3:	jmp    109a1cc <my.diagram_membership::compute_sub_block_attachments+0x3ec>
 109a1a5:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a1b4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a1c0:	inc    %r12
 109a1c3:	add    $0x10,%r13
 109a1c7:	cmp    %r12,%r14
 109a1ca:	je     109a1f0 <my.diagram_membership::compute_sub_block_attachments+0x410>
 109a1cc:	cmp    %rbx,(%r15,%r12,8)
 109a1d0:	jne    109a1c0 <my.diagram_membership::compute_sub_block_attachments+0x3e0>
 109a1d2:	mov    0x0(%r13),%rdi
 109a1d6:	mov    0x140(%rsp),%rsi
 109a1de:	call   1044580 <myl_core_str_eq>
 109a1e3:	test   %al,%al
 109a1e5:	je     109a1c0 <my.diagram_membership::compute_sub_block_attachments+0x3e0>
 109a1e7:	jmp    109a17f <my.diagram_membership::compute_sub_block_attachments+0x39f>
 109a1e9:	nopl   0x0(%rax)
 109a1f0:	xor    %edi,%edi
 109a1f2:	lea    0x5d467(%rip),%rsi        # 10f7660 <core_durable_error.verbs+0xd0a0>
 109a1f9:	call   1042f80 <myl_core_dict_new>
 109a1fe:	mov    %rax,%rbx
 109a201:	mov    0x8(%rbp),%r12
 109a205:	mov    0x10(%rsp),%rdi
 109a20a:	add    $0x20,%rdi
 109a20e:	mov    %rdi,0x10(%rsp)
 109a213:	mov    %r12,%rsi
 109a216:	call   10442c0 <myl_core_span_hash>
 109a21b:	mov    %eax,%eax
 109a21d:	movabs $0x9e3779b97f4a7c15,%rcx
 109a227:	imul   %rcx,%rax
 109a22b:	mov    %rax,%r15
 109a22e:	shr    $0x20,%r15
 109a232:	xor    %rax,%r15
 109a235:	mov    0x8(%rsp),%rax
 109a23a:	mov    0x18(%rax),%rcx
 109a23e:	mov    0x8(%rcx),%rax
 109a242:	test   %rax,%rax
 109a245:	mov    %rbx,0x60(%rsp)
 109a24a:	je     109a3bc <my.diagram_membership::compute_sub_block_attachments+0x5dc>
 109a250:	mov    (%rax),%ecx
 109a252:	tzcnt  %ecx,%edx
 109a256:	neg    %dl
 109a258:	shrx   %rdx,%r15,%r13
 109a25d:	lea    -0x1(%rcx),%ebp
 109a260:	vmovdqu 0x10(%rax,%r13,1),%xmm1
 109a267:	and    $0x7f,%r15b
 109a26b:	vmovd  %r15d,%xmm0
 109a270:	vpbroadcastb %xmm0,%xmm0
 109a275:	vmovdqa %xmm1,0xb0(%rsp)
 109a27e:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109a282:	vpmovmskb %xmm0,%edx
 109a286:	test   %edx,%edx
 109a288:	mov    0x10(%rsp),%rsi
 109a28d:	je     109a38c <my.diagram_membership::compute_sub_block_attachments+0x5ac>
 109a293:	add    $0x1e,%ecx
 109a296:	and    $0xfffffff0,%ecx
 109a299:	lea    (%rax,%rcx,1),%r14
 109a29d:	add    $0x10,%r14
 109a2a1:	movzwl %dx,%r15d
 109a2a5:	mov    %r12,%rax
 109a2a8:	shr    $1,%rax
 109a2ab:	mov    %rax,0x20(%rsp)
 109a2b0:	jmp    109a2e5 <my.diagram_membership::compute_sub_block_attachments+0x505>
 109a2b2:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a2c0:	mov    0x10(%rsp),%rsi
 109a2c5:	mov    %r12,%rdx
 109a2c8:	call   10e8ff0 <bcmp@plt>
 109a2cd:	mov    0x10(%rsp),%rsi
 109a2d2:	test   %eax,%eax
 109a2d4:	je     109a51e <my.diagram_membership::compute_sub_block_attachments+0x73e>
 109a2da:	blsr   %r15d,%r15d
 109a2df:	je     109a38c <my.diagram_membership::compute_sub_block_attachments+0x5ac>
 109a2e5:	tzcnt  %r15d,%eax
 109a2ea:	add    %r13d,%eax
 109a2ed:	and    %ebp,%eax
 109a2ef:	mov    (%r14,%rax,4),%ebx
 109a2f3:	mov    %rbx,%rax
 109a2f6:	shl    $0x4,%rax
 109a2fa:	mov    0x8(%rsp),%rcx
 109a2ff:	mov    0x20(%rcx,%rax,1),%rdi
 109a304:	cmp    %r12,0x8(%rdi)
 109a308:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a30a:	add    $0x20,%rdi
 109a30e:	cmp    $0x10,%r12
 109a312:	ja     109a2c0 <my.diagram_membership::compute_sub_block_attachments+0x4e0>
 109a314:	cmp    $0x8,%r12
 109a318:	jb     109a333 <my.diagram_membership::compute_sub_block_attachments+0x553>
 109a31a:	mov    (%rdi),%rax
 109a31d:	cmp    (%rsi),%rax
 109a320:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a322:	mov    -0x8(%rsi,%r12,1),%rax
 109a327:	cmp    %rax,-0x8(%rdi,%r12,1)
 109a32c:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a32e:	jmp    109a51e <my.diagram_membership::compute_sub_block_attachments+0x73e>
 109a333:	cmp    $0x4,%r12
 109a337:	jb     109a350 <my.diagram_membership::compute_sub_block_attachments+0x570>
 109a339:	mov    (%rdi),%eax
 109a33b:	cmp    (%rsi),%eax
 109a33d:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a33f:	mov    -0x4(%rsi,%r12,1),%eax
 109a344:	cmp    %eax,-0x4(%rdi,%r12,1)
 109a349:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a34b:	jmp    109a51e <my.diagram_membership::compute_sub_block_attachments+0x73e>
 109a350:	test   %r12,%r12
 109a353:	je     109a51e <my.diagram_membership::compute_sub_block_attachments+0x73e>
 109a359:	movzbl (%rdi),%eax
 109a35c:	cmp    (%rsi),%al
 109a35e:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a364:	mov    0x20(%rsp),%rcx
 109a369:	movzbl (%rsi,%rcx,1),%eax
 109a36d:	cmp    %al,(%rdi,%rcx,1)
 109a370:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a376:	movzbl -0x1(%rsi,%r12,1),%eax
 109a37c:	cmp    %al,-0x1(%rdi,%r12,1)
 109a381:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a387:	jmp    109a51e <my.diagram_membership::compute_sub_block_attachments+0x73e>
 109a38c:	vmovdqa 0xb0(%rsp),%xmm0
 109a395:	vpcmpeqb -0x95fcd(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109a39d:	vpmovmskb %xmm0,%eax
 109a3a1:	test   %eax,%eax
 109a3a3:	je     109a4fc <my.diagram_membership::compute_sub_block_attachments+0x71c>
 109a3a9:	tzcnt  %eax,%r14d
 109a3ae:	add    %r13d,%r14d
 109a3b1:	and    %ebp,%r14d
 109a3b4:	not    %r14
 109a3b7:	jmp    109a550 <my.diagram_membership::compute_sub_block_attachments+0x770>
 109a3bc:	mov    0x20(%rcx),%r13
 109a3c0:	mov    $0xffffffffffffffff,%r14
 109a3c7:	test   %r13,%r13
 109a3ca:	mov    0x10(%rsp),%rsi
 109a3cf:	je     109a550 <my.diagram_membership::compute_sub_block_attachments+0x770>
 109a3d5:	mov    0x10(%rcx),%rbp
 109a3d9:	mov    0x18(%rcx),%rdx
 109a3dd:	mov    %r12,%rax
 109a3e0:	shr    $1,%rax
 109a3e3:	mov    %rax,0x20(%rsp)
 109a3e8:	mov    0x8(%rsp),%rax
 109a3ed:	lea    0x20(%rax),%r14
 109a3f1:	xor    %ebx,%ebx
 109a3f3:	mov    %rdx,0xb0(%rsp)
 109a3fb:	jmp    109a450 <my.diagram_membership::compute_sub_block_attachments+0x670>
 109a3fd:	mov    0x10(%rsp),%rsi
 109a402:	mov    %r12,%rdx
 109a405:	call   10e8ff0 <bcmp@plt>
 109a40a:	mov    0xb0(%rsp),%rdx
 109a412:	mov    0x10(%rsp),%rsi
 109a417:	test   %eax,%eax
 109a419:	je     109a516 <my.diagram_membership::compute_sub_block_attachments+0x736>
 109a41f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a42e:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a43d:	nopl   (%rax)
 109a440:	inc    %rbx
 109a443:	add    $0x10,%r14
 109a447:	cmp    %rbx,%r13
 109a44a:	je     109a4f3 <my.diagram_membership::compute_sub_block_attachments+0x713>
 109a450:	cmp    %r15,0x0(%rbp,%rbx,8)
 109a455:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a457:	test   %rdx,%rdx
 109a45a:	je     109a471 <my.diagram_membership::compute_sub_block_attachments+0x691>
 109a45c:	mov    %rbx,%rax
 109a45f:	shr    $0x3,%rax
 109a463:	movzbl (%rdx,%rax,1),%eax
 109a467:	mov    %ebx,%ecx
 109a469:	and    $0x7,%ecx
 109a46c:	bt     %ecx,%eax
 109a46f:	jb     109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a471:	mov    (%r14),%rdi
 109a474:	cmp    %r12,0x8(%rdi)
 109a478:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a47a:	add    $0x20,%rdi
 109a47e:	cmp    $0x10,%r12
 109a482:	ja     109a3fd <my.diagram_membership::compute_sub_block_attachments+0x61d>
 109a488:	cmp    $0x8,%r12
 109a48c:	jb     109a4a4 <my.diagram_membership::compute_sub_block_attachments+0x6c4>
 109a48e:	mov    (%rdi),%rax
 109a491:	cmp    (%rsi),%rax
 109a494:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a496:	mov    -0x8(%rsi,%r12,1),%rax
 109a49b:	cmp    %rax,-0x8(%rdi,%r12,1)
 109a4a0:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4a2:	jmp    109a516 <my.diagram_membership::compute_sub_block_attachments+0x736>
 109a4a4:	cmp    $0x4,%r12
 109a4a8:	jb     109a4be <my.diagram_membership::compute_sub_block_attachments+0x6de>
 109a4aa:	mov    (%rdi),%eax
 109a4ac:	cmp    (%rsi),%eax
 109a4ae:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4b0:	mov    -0x4(%rsi,%r12,1),%eax
 109a4b5:	cmp    %eax,-0x4(%rdi,%r12,1)
 109a4ba:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4bc:	jmp    109a516 <my.diagram_membership::compute_sub_block_attachments+0x736>
 109a4be:	test   %r12,%r12
 109a4c1:	je     109a516 <my.diagram_membership::compute_sub_block_attachments+0x736>
 109a4c3:	movzbl (%rdi),%eax
 109a4c6:	cmp    (%rsi),%al
 109a4c8:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4ce:	mov    0x20(%rsp),%rcx
 109a4d3:	movzbl (%rsi,%rcx,1),%eax
 109a4d7:	cmp    %al,(%rdi,%rcx,1)
 109a4da:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4e0:	movzbl -0x1(%rsi,%r12,1),%eax
 109a4e6:	cmp    %al,-0x1(%rdi,%r12,1)
 109a4eb:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4f1:	jmp    109a516 <my.diagram_membership::compute_sub_block_attachments+0x736>
 109a4f3:	mov    $0xffffffffffffffff,%r14
 109a4fa:	jmp    109a550 <my.diagram_membership::compute_sub_block_attachments+0x770>
 109a4fc:	mov    0x8(%rsp),%rdi
 109a501:	mov    0x10(%rsp),%rsi
 109a506:	mov    %r12,%rdx
 109a509:	call   1043f00 <myl_core_dict_find_span>
 109a50e:	mov    0x10(%rsp),%rsi
 109a513:	mov    %rax,%rbx
 109a516:	mov    %rbx,%r14
 109a519:	test   %rbx,%rbx
 109a51c:	js     109a550 <my.diagram_membership::compute_sub_block_attachments+0x770>
 109a51e:	mov    0x60(%rsp),%rax
 109a523:	mov    %rax,0x1a0(%rsp)
 109a52b:	mov    0x8(%rsp),%rdi
 109a530:	mov    %rbx,%rsi
 109a533:	lea    0x1a0(%rsp),%rdx
 109a53b:	call   1043040 <myl_core_dict_set>
 109a540:	mov    %rax,0x8(%rsp)
 109a545:	mov    0x30(%rsp),%rbp
 109a54a:	jmp    109a5a3 <my.diagram_membership::compute_sub_block_attachments+0x7c3>
 109a54c:	nopl   0x0(%rax)
 109a550:	mov    0x30(%rsp),%rbp
 109a555:	mov    0x0(%rbp),%edx
 109a558:	shr    $0x8,%edx
 109a55b:	and    $0x1,%edx
 109a55e:	mov    %rsi,%rdi
 109a561:	mov    %r12,%rsi
 109a564:	call   1044c80 <myl_core_ir_str_from_span>
 109a569:	mov    %rax,0x198(%rsp)
 109a571:	mov    0x60(%rsp),%rax
 109a576:	mov    %rax,0x190(%rsp)
 109a57e:	mov    0x8(%rsp),%rdi
 109a583:	mov    %r14,%rsi
 109a586:	lea    0x198(%rsp),%rdx
 109a58e:	lea    0x190(%rsp),%rcx
 109a596:	xor    %r8d,%r8d
 109a599:	call   1043240 <myl_core_dict_insert>
 109a59e:	mov    %rax,0x8(%rsp)
 109a5a3:	mov    %rbp,0x138(%rsp)
 109a5ab:	testb  $0x2,0x1(%rbp)
 109a5af:	jne    109a5c0 <my.diagram_membership::compute_sub_block_attachments+0x7e0>
 109a5b1:	mov    %rbp,%rdi
 109a5b4:	call   1044400 <myl_core_str_hash>
 109a5b9:	jmp    109a5c3 <my.diagram_membership::compute_sub_block_attachments+0x7e3>
 109a5bb:	nopl   0x0(%rax,%rax,1)
 109a5c0:	mov    0x18(%rbp),%eax
 109a5c3:	mov    %eax,%eax
 109a5c5:	movabs $0x9e3779b97f4a7c15,%rcx
 109a5cf:	imul   %rcx,%rax
 109a5d3:	mov    %rax,%rbx
 109a5d6:	shr    $0x20,%rbx
 109a5da:	xor    %rax,%rbx
 109a5dd:	mov    0x8(%rsp),%rax
 109a5e2:	mov    0x18(%rax),%rcx
 109a5e6:	mov    0x8(%rcx),%rax
 109a5ea:	test   %rax,%rax
 109a5ed:	je     109a6a0 <my.diagram_membership::compute_sub_block_attachments+0x8c0>
 109a5f3:	mov    (%rax),%ecx
 109a5f5:	tzcnt  %ecx,%edx
 109a5f9:	neg    %dl
 109a5fb:	shrx   %rdx,%rbx,%r14
 109a600:	vmovdqu 0x10(%rax,%r14,1),%xmm1
 109a607:	mov    %ebx,%edx
 109a609:	and    $0x7f,%dl
 109a60c:	vmovd  %edx,%xmm0
 109a610:	vpbroadcastb %xmm0,%xmm0
 109a615:	vmovdqa %xmm1,0x10(%rsp)
 109a61b:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109a61f:	vpmovmskb %xmm0,%edx
 109a623:	test   %edx,%edx
 109a625:	je     109a678 <my.diagram_membership::compute_sub_block_attachments+0x898>
 109a627:	lea    -0x1(%rcx),%ebp
 109a62a:	add    $0x1e,%ecx
 109a62d:	and    $0xfffffff0,%ecx
 109a630:	lea    (%rax,%rcx,1),%r15
 109a634:	add    $0x10,%r15
 109a638:	movzwl %dx,%r13d
 109a63c:	nopl   0x0(%rax)
 109a640:	tzcnt  %r13d,%eax
 109a645:	add    %r14d,%eax
 109a648:	and    %ebp,%eax
 109a64a:	mov    (%r15,%rax,4),%r12d
 109a64e:	shl    $0x4,%r12
 109a652:	mov    0x8(%rsp),%rax
 109a657:	mov    0x20(%rax,%r12,1),%rdi
 109a65c:	mov    0x138(%rsp),%rsi
 109a664:	call   1044580 <myl_core_str_eq>
 109a669:	test   %al,%al
 109a66b:	jne    109a854 <my.diagram_membership::compute_sub_block_attachments+0xa74>
 109a671:	blsr   %r13d,%r13d
 109a676:	jne    109a640 <my.diagram_membership::compute_sub_block_attachments+0x860>
 109a678:	vmovdqa 0x10(%rsp),%xmm0
 109a67e:	vpcmpeqb -0x962b6(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109a686:	vpmovmskb %xmm0,%eax
 109a68a:	test   %eax,%eax
 109a68c:	mov    0x30(%rsp),%rbp
 109a691:	je     109a6ab <my.diagram_membership::compute_sub_block_attachments+0x8cb>
 109a693:	jmp    109da9d <my.diagram_membership::compute_sub_block_attachments+0x3cbd>
 109a698:	nopl   0x0(%rax,%rax,1)
 109a6a0:	cmpq   $0x0,0x18(%rcx)
 109a6a5:	je     109a86b <my.diagram_membership::compute_sub_block_attachments+0xa8b>
 109a6ab:	mov    0x8(%rsp),%rdi
 109a6b0:	lea    0x138(%rsp),%rsi
 109a6b8:	mov    %rbx,%rdx
 109a6bb:	call   1042bc0 <myl_core_dict_find>
 109a6c0:	mov    %rax,%r12
 109a6c3:	mov    %rbp,%rdi
 109a6c6:	call   103c740 <myl_core_drop_owned>
 109a6cb:	test   %r12,%r12
 109a6ce:	mov    0x80(%rsp),%rbx
 109a6d6:	js     109daa5 <my.diagram_membership::compute_sub_block_attachments+0x3cc5>
 109a6dc:	shl    $0x4,%r12
 109a6e0:	mov    %rbx,%rdi
 109a6e3:	call   104ba40 <myl_core_bytes_utf8_count>
 109a6e8:	test   %rax,%rax
 109a6eb:	js     109a9c0 <my.diagram_membership::compute_sub_block_attachments+0xbe0>
 109a6f1:	mov    %rbx,%rdi
 109a6f4:	call   104bb00 <myl_core_bytes_decode_text>
 109a6f9:	mov    %rax,%r14
 109a6fc:	xor    %eax,%eax
 109a6fe:	test   %al,%al
 109a700:	jne    109a9dd <my.diagram_membership::compute_sub_block_attachments+0xbfd>
 109a706:	mov    %rbx,%rdi
 109a709:	call   103c740 <myl_core_drop_owned>
 109a70e:	mov    0x8(%rsp),%rax
 109a713:	mov    0x28(%rax,%r12,1),%rax
 109a718:	mov    %rax,0x10(%rsp)
 109a71d:	mov    %r14,0x130(%rsp)
 109a725:	testb  $0x2,0x1(%r14)
 109a72a:	mov    %r14,0x30(%rsp)
 109a72f:	jne    109a740 <my.diagram_membership::compute_sub_block_attachments+0x960>
 109a731:	mov    %r14,%rdi
 109a734:	call   1044400 <myl_core_str_hash>
 109a739:	jmp    109a744 <my.diagram_membership::compute_sub_block_attachments+0x964>
 109a73b:	nopl   0x0(%rax,%rax,1)
 109a740:	mov    0x18(%r14),%eax
 109a744:	mov    %eax,%eax
 109a746:	movabs $0x9e3779b97f4a7c15,%rcx
 109a750:	imul   %rcx,%rax
 109a754:	mov    %rax,%r15
 109a757:	shr    $0x20,%r15
 109a75b:	xor    %rax,%r15
 109a75e:	mov    0x10(%rsp),%rax
 109a763:	mov    0x18(%rax),%rcx
 109a767:	mov    0x8(%rcx),%rax
 109a76b:	test   %rax,%rax
 109a76e:	je     109a820 <my.diagram_membership::compute_sub_block_attachments+0xa40>
 109a774:	mov    (%rax),%ecx
 109a776:	tzcnt  %ecx,%edx
 109a77a:	neg    %dl
 109a77c:	shrx   %rdx,%r15,%rbp
 109a781:	lea    -0x1(%rcx),%ebx
 109a784:	vmovdqu 0x10(%rax,%rbp,1),%xmm1
 109a78a:	mov    %r15d,%edx
 109a78d:	and    $0x7f,%dl
 109a790:	vmovd  %edx,%xmm0
 109a794:	vpbroadcastb %xmm0,%xmm0
 109a799:	vmovdqa %xmm1,0x80(%rsp)
 109a7a2:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109a7a6:	vpmovmskb %xmm0,%edx
 109a7aa:	test   %edx,%edx
 109a7ac:	je     109a7f4 <my.diagram_membership::compute_sub_block_attachments+0xa14>
 109a7ae:	add    $0x1e,%ecx
 109a7b1:	and    $0xfffffff0,%ecx
 109a7b4:	lea    (%rax,%rcx,1),%r13
 109a7b8:	add    $0x10,%r13
 109a7bc:	movzwl %dx,%r14d
 109a7c0:	tzcnt  %r14d,%eax
 109a7c5:	add    %ebp,%eax
 109a7c7:	and    %ebx,%eax
 109a7c9:	mov    0x0(%r13,%rax,4),%eax
 109a7ce:	mov    0x10(%rsp),%rcx
 109a7d3:	mov    0x20(%rcx,%rax,8),%rdi
 109a7d8:	mov    0x130(%rsp),%rsi
 109a7e0:	call   1044580 <myl_core_str_eq>
 109a7e5:	test   %al,%al
 109a7e7:	jne    1099f30 <my.diagram_membership::compute_sub_block_attachments+0x150>
 109a7ed:	blsr   %r14d,%r14d
 109a7f2:	jne    109a7c0 <my.diagram_membership::compute_sub_block_attachments+0x9e0>
 109a7f4:	vmovdqa 0x80(%rsp),%xmm0
 109a7fd:	vpcmpeqb -0x96435(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109a805:	vpmovmskb %xmm0,%eax
 109a809:	test   %eax,%eax
 109a80b:	je     109a82b <my.diagram_membership::compute_sub_block_attachments+0xa4b>
 109a80d:	tzcnt  %eax,%r13d
 109a812:	add    %ebp,%r13d
 109a815:	and    %ebx,%r13d
 109a818:	not    %r13
 109a81b:	jmp    109a970 <my.diagram_membership::compute_sub_block_attachments+0xb90>
 109a820:	cmpq   $0x0,0x18(%rcx)
 109a825:	je     109a8f0 <my.diagram_membership::compute_sub_block_attachments+0xb10>
 109a82b:	mov    0x10(%rsp),%rdi
 109a830:	lea    0x130(%rsp),%rsi
 109a838:	mov    %r15,%rdx
 109a83b:	call   1042bc0 <myl_core_dict_find>
 109a840:	mov    %rax,%rbp
 109a843:	mov    %rbp,%r13
 109a846:	test   %rbp,%rbp
 109a849:	jns    1099f30 <my.diagram_membership::compute_sub_block_attachments+0x150>
 109a84f:	jmp    109a970 <my.diagram_membership::compute_sub_block_attachments+0xb90>
 109a854:	mov    0x30(%rsp),%rdi
 109a859:	call   103c740 <myl_core_drop_owned>
 109a85e:	mov    0x80(%rsp),%rbx
 109a866:	jmp    109a6e0 <my.diagram_membership::compute_sub_block_attachments+0x900>
 109a86b:	mov    0x20(%rcx),%r14
 109a86f:	test   %r14,%r14
 109a872:	je     109da9d <my.diagram_membership::compute_sub_block_attachments+0x3cbd>
 109a878:	mov    0x10(%rcx),%r15
 109a87c:	mov    0x8(%rsp),%rax
 109a881:	lea    0x20(%rax),%r13
 109a885:	xor    %r12d,%r12d
 109a888:	jmp    109a8d0 <my.diagram_membership::compute_sub_block_attachments+0xaf0>
 109a88a:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a899:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a8a8:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a8b7:	nopw   0x0(%rax,%rax,1)
 109a8c0:	inc    %r12
 109a8c3:	add    $0x10,%r13
 109a8c7:	cmp    %r12,%r14
 109a8ca:	je     109da9d <my.diagram_membership::compute_sub_block_attachments+0x3cbd>
 109a8d0:	cmp    %rbx,(%r15,%r12,8)
 109a8d4:	jne    109a8c0 <my.diagram_membership::compute_sub_block_attachments+0xae0>
 109a8d6:	mov    0x0(%r13),%rdi
 109a8da:	mov    0x138(%rsp),%rsi
 109a8e2:	call   1044580 <myl_core_str_eq>
 109a8e7:	test   %al,%al
 109a8e9:	je     109a8c0 <my.diagram_membership::compute_sub_block_attachments+0xae0>
 109a8eb:	jmp    109a6c3 <my.diagram_membership::compute_sub_block_attachments+0x8e3>
 109a8f0:	mov    0x20(%rcx),%rbx
 109a8f4:	mov    $0xffffffffffffffff,%r13
 109a8fb:	test   %rbx,%rbx
 109a8fe:	je     109a970 <my.diagram_membership::compute_sub_block_attachments+0xb90>
 109a900:	mov    0x10(%rcx),%r14
 109a904:	xor    %ebp,%ebp
 109a906:	jmp    109a948 <my.diagram_membership::compute_sub_block_attachments+0xb68>
 109a908:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a917:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a926:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a935:	data16 cs nopw 0x0(%rax,%rax,1)
 109a940:	inc    %rbp
 109a943:	cmp    %rbp,%rbx
 109a946:	je     109a970 <my.diagram_membership::compute_sub_block_attachments+0xb90>
 109a948:	cmp    %r15,(%r14,%rbp,8)
 109a94c:	jne    109a940 <my.diagram_membership::compute_sub_block_attachments+0xb60>
 109a94e:	mov    0x10(%rsp),%rax
 109a953:	mov    0x20(%rax,%rbp,8),%rdi
 109a958:	mov    0x130(%rsp),%rsi
 109a960:	call   1044580 <myl_core_str_eq>
 109a965:	test   %al,%al
 109a967:	je     109a940 <my.diagram_membership::compute_sub_block_attachments+0xb60>
 109a969:	jmp    109a843 <my.diagram_membership::compute_sub_block_attachments+0xa63>
 109a96e:	xchg   %ax,%ax
 109a970:	mov    0x30(%rsp),%rax
 109a975:	mov    %rax,0x188(%rsp)
 109a97d:	mov    0x10(%rsp),%rdi
 109a982:	mov    %r13,%rsi
 109a985:	lea    0x188(%rsp),%rdx
 109a98d:	xor    %ecx,%ecx
 109a98f:	xor    %r8d,%r8d
 109a992:	call   1043240 <myl_core_dict_insert>
 109a997:	mov    0x8(%rsp),%rcx
 109a99c:	mov    %rax,0x28(%rcx,%r12,1)
 109a9a1:	jmp    1099f49 <my.diagram_membership::compute_sub_block_attachments+0x169>
 109a9a6:	lea    0x51143(%rip),%rdi        # 10ebaf0 <core_durable_error.verbs+0x1530>
 109a9ad:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109a9b2:	mov    $0x1,%al
 109a9b4:	lea    -0x7ed9b(%rip),%rbp        # 101bc20 <core_number_pairs+0x146d0>
 109a9bb:	jmp    109a010 <my.diagram_membership::compute_sub_block_attachments+0x230>
 109a9c0:	lea    0x51129(%rip),%rdi        # 10ebaf0 <core_durable_error.verbs+0x1530>
 109a9c7:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109a9cc:	mov    $0x1,%al
 109a9ce:	lea    -0x7edb5(%rip),%r14        # 101bc20 <core_number_pairs+0x146d0>
 109a9d5:	test   %al,%al
 109a9d7:	je     109a706 <my.diagram_membership::compute_sub_block_attachments+0x926>
 109a9dd:	mov    %r14,%rdi
 109a9e0:	call   103c740 <myl_core_drop_owned>
 109a9e5:	lea    0x51134(%rip),%rdi        # 10ebb20 <core_durable_error.verbs+0x1560>
 109a9ec:	call   1042840 <myl_core_assert_fail>
 109a9f1:	lea    0x5cce0(%rip),%rsi        # 10f76d8 <core_durable_error.verbs+0xd118>
 109a9f8:	xor    %edi,%edi
 109a9fa:	call   1042f80 <myl_core_dict_new>
 109a9ff:	mov    %rax,0x20(%rsp)
 109aa04:	mov    0xa0(%rsp),%rax
 109aa0c:	cmpq   $0x0,0x8(%rax)
 109aa11:	je     109acde <my.diagram_membership::compute_sub_block_attachments+0xefe>
 109aa17:	add    $0x20,%rax
 109aa1b:	mov    %rax,0x80(%rsp)
 109aa23:	xor    %ebx,%ebx
 109aa25:	jmp    109aaac <my.diagram_membership::compute_sub_block_attachments+0xccc>
 109aa2a:	nopw   0x0(%rax,%rax,1)
 109aa30:	vmovdqa 0x50(%rsp),%xmm0
 109aa36:	vpcmpeqb -0x9666e(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109aa3e:	vpmovmskb %xmm0,%eax
 109aa42:	test   %eax,%eax
 109aa44:	je     109ac07 <my.diagram_membership::compute_sub_block_attachments+0xe27>
 109aa4a:	tzcnt  %eax,%r15d
 109aa4f:	add    %ebx,%r15d
 109aa52:	and    %r13d,%r15d
 109aa55:	not    %r15
 109aa58:	mov    0x30(%rsp),%rax
 109aa5d:	mov    %rax,0x180(%rsp)
 109aa65:	mov    0x10(%rsp),%rbx
 109aa6a:	mov    %rbx,0x178(%rsp)
 109aa72:	mov    0x20(%rsp),%rdi
 109aa77:	mov    %r15,%rsi
 109aa7a:	lea    0x180(%rsp),%rdx
 109aa82:	lea    0x178(%rsp),%rcx
 109aa8a:	xor    %r8d,%r8d
 109aa8d:	call   1043240 <myl_core_dict_insert>
 109aa92:	mov    %rax,0x20(%rsp)
 109aa97:	inc    %rbx
 109aa9a:	mov    0xa0(%rsp),%rax
 109aaa2:	cmp    0x8(%rax),%rbx
 109aaa6:	jae    109acde <my.diagram_membership::compute_sub_block_attachments+0xefe>
 109aaac:	imul   $0x428,%rbx,%rax
 109aab3:	mov    0x80(%rsp),%rcx
 109aabb:	mov    (%rcx,%rax,1),%r15
 109aabf:	mov    %r15,%rdi
 109aac2:	call   104ba40 <myl_core_bytes_utf8_count>
 109aac7:	test   %rax,%rax
 109aaca:	js     109acb0 <my.diagram_membership::compute_sub_block_attachments+0xed0>
 109aad0:	mov    %r15,%rdi
 109aad3:	call   104bb00 <myl_core_bytes_decode_text>
 109aad8:	mov    %rax,%rdi
 109aadb:	xor    %eax,%eax
 109aadd:	test   %al,%al
 109aadf:	jne    109accd <my.diagram_membership::compute_sub_block_attachments+0xeed>
 109aae5:	mov    %rdi,0x128(%rsp)
 109aaed:	testb  $0x2,0x1(%rdi)
 109aaf1:	mov    %rbx,0x10(%rsp)
 109aaf6:	mov    %rdi,0x30(%rsp)
 109aafb:	jne    109ab10 <my.diagram_membership::compute_sub_block_attachments+0xd30>
 109aafd:	call   1044400 <myl_core_str_hash>
 109ab02:	jmp    109ab13 <my.diagram_membership::compute_sub_block_attachments+0xd33>
 109ab04:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ab10:	mov    0x18(%rdi),%eax
 109ab13:	mov    %eax,%eax
 109ab15:	movabs $0x9e3779b97f4a7c15,%rcx
 109ab1f:	imul   %rcx,%rax
 109ab23:	mov    %rax,%rbp
 109ab26:	shr    $0x20,%rbp
 109ab2a:	xor    %rax,%rbp
 109ab2d:	mov    0x20(%rsp),%rax
 109ab32:	mov    0x18(%rax),%rcx
 109ab36:	mov    0x8(%rcx),%rax
 109ab3a:	test   %rax,%rax
 109ab3d:	je     109ac00 <my.diagram_membership::compute_sub_block_attachments+0xe20>
 109ab43:	mov    (%rax),%ecx
 109ab45:	tzcnt  %ecx,%edx
 109ab49:	neg    %dl
 109ab4b:	shrx   %rdx,%rbp,%rbx
 109ab50:	lea    -0x1(%rcx),%r13d
 109ab54:	vmovdqu 0x10(%rax,%rbx,1),%xmm1
 109ab5a:	mov    %ebp,%edx
 109ab5c:	and    $0x7f,%dl
 109ab5f:	vmovd  %edx,%xmm0
 109ab63:	vpbroadcastb %xmm0,%xmm0
 109ab68:	vmovdqa %xmm1,0x50(%rsp)
 109ab6e:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109ab72:	vpmovmskb %xmm0,%edx
 109ab76:	test   %edx,%edx
 109ab78:	je     109aa30 <my.diagram_membership::compute_sub_block_attachments+0xc50>
 109ab7e:	add    $0x1e,%ecx
 109ab81:	and    $0xfffffff0,%ecx
 109ab84:	lea    (%rax,%rcx,1),%r15
 109ab88:	add    $0x10,%r15
 109ab8c:	movzwl %dx,%r14d
 109ab90:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ab9f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109abae:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109abbd:	nopl   (%rax)
 109abc0:	tzcnt  %r14d,%eax
 109abc5:	add    %ebx,%eax
 109abc7:	and    %r13d,%eax
 109abca:	mov    (%r15,%rax,4),%r12d
 109abce:	shl    $0x4,%r12
 109abd2:	mov    0x20(%rsp),%rax
 109abd7:	mov    0x20(%rax,%r12,1),%rdi
 109abdc:	mov    0x128(%rsp),%rsi
 109abe4:	call   1044580 <myl_core_str_eq>
 109abe9:	test   %al,%al
 109abeb:	jne    109ac28 <my.diagram_membership::compute_sub_block_attachments+0xe48>
 109abed:	blsr   %r14d,%r14d
 109abf2:	jne    109abc0 <my.diagram_membership::compute_sub_block_attachments+0xde0>
 109abf4:	jmp    109aa30 <my.diagram_membership::compute_sub_block_attachments+0xc50>
 109abf9:	nopl   0x0(%rax)
 109ac00:	cmpq   $0x0,0x18(%rcx)
 109ac05:	je     109ac4e <my.diagram_membership::compute_sub_block_attachments+0xe6e>
 109ac07:	mov    0x20(%rsp),%rdi
 109ac0c:	lea    0x128(%rsp),%rsi
 109ac14:	mov    %rbp,%rdx
 109ac17:	call   1042bc0 <myl_core_dict_find>
 109ac1c:	mov    %rax,%r12
 109ac1f:	test   %r12,%r12
 109ac22:	js     109ac46 <my.diagram_membership::compute_sub_block_attachments+0xe66>
 109ac24:	shl    $0x4,%r12
 109ac28:	mov    0x30(%rsp),%rdi
 109ac2d:	call   103c740 <myl_core_drop_owned>
 109ac32:	mov    0x20(%rsp),%rax
 109ac37:	mov    0x10(%rsp),%rbx
 109ac3c:	mov    %rbx,0x28(%rax,%r12,1)
 109ac41:	jmp    109aa97 <my.diagram_membership::compute_sub_block_attachments+0xcb7>
 109ac46:	mov    %r12,%r15
 109ac49:	jmp    109aa58 <my.diagram_membership::compute_sub_block_attachments+0xc78>
 109ac4e:	mov    0x20(%rcx),%rbx
 109ac52:	mov    $0xffffffffffffffff,%r15
 109ac59:	test   %rbx,%rbx
 109ac5c:	je     109aa58 <my.diagram_membership::compute_sub_block_attachments+0xc78>
 109ac62:	mov    0x10(%rcx),%r13
 109ac66:	mov    0x20(%rsp),%rax
 109ac6b:	lea    0x20(%rax),%r14
 109ac6f:	xor    %r12d,%r12d
 109ac72:	jmp    109ac90 <my.diagram_membership::compute_sub_block_attachments+0xeb0>
 109ac74:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ac80:	inc    %r12
 109ac83:	add    $0x10,%r14
 109ac87:	cmp    %r12,%rbx
 109ac8a:	je     109aa58 <my.diagram_membership::compute_sub_block_attachments+0xc78>
 109ac90:	cmp    %rbp,0x0(%r13,%r12,8)
 109ac95:	jne    109ac80 <my.diagram_membership::compute_sub_block_attachments+0xea0>
 109ac97:	mov    (%r14),%rdi
 109ac9a:	mov    0x128(%rsp),%rsi
 109aca2:	call   1044580 <myl_core_str_eq>
 109aca7:	test   %al,%al
 109aca9:	je     109ac80 <my.diagram_membership::compute_sub_block_attachments+0xea0>
 109acab:	jmp    109ac1f <my.diagram_membership::compute_sub_block_attachments+0xe3f>
 109acb0:	lea    0x50e39(%rip),%rdi        # 10ebaf0 <core_durable_error.verbs+0x1530>
 109acb7:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109acbc:	mov    $0x1,%al
 109acbe:	lea    -0x7f0a5(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109acc5:	test   %al,%al
 109acc7:	je     109aae5 <my.diagram_membership::compute_sub_block_attachments+0xd05>
 109accd:	call   103c740 <myl_core_drop_owned>
 109acd2:	lea    0x50e47(%rip),%rdi        # 10ebb20 <core_durable_error.verbs+0x1560>
 109acd9:	call   1042840 <myl_core_assert_fail>
 109acde:	lea    0x5c9f3(%rip),%rsi        # 10f76d8 <core_durable_error.verbs+0xd118>
 109ace5:	xor    %edi,%edi
 109ace7:	call   1042f80 <myl_core_dict_new>
 109acec:	mov    %rax,0x28(%rsp)
 109acf1:	mov    0x70(%rsp),%rax
 109acf6:	mov    0x8(%rax),%rax
 109acfa:	test   %rax,%rax
 109acfd:	je     109afdf <my.diagram_membership::compute_sub_block_attachments+0x11ff>
 109ad03:	xor    %r15d,%r15d
 109ad06:	jmp    109ad25 <my.diagram_membership::compute_sub_block_attachments+0xf45>
 109ad08:	nopl   0x0(%rax,%rax,1)
 109ad10:	mov    0x70(%rsp),%rax
 109ad15:	mov    0x8(%rax),%rax
 109ad19:	inc    %r15
 109ad1c:	cmp    %rax,%r15
 109ad1f:	jae    109afdf <my.diagram_membership::compute_sub_block_attachments+0x11ff>
 109ad25:	imul   $0x70,%r15,%rcx
 109ad29:	mov    0x70(%rsp),%rdx
 109ad2e:	mov    0x80(%rdx,%rcx,1),%rcx
 109ad36:	mov    %rcx,0x80(%rsp)
 109ad3e:	mov    0x8(%rcx),%rcx
 109ad42:	mov    %rcx,0x48(%rsp)
 109ad47:	test   %rcx,%rcx
 109ad4a:	je     109ad19 <my.diagram_membership::compute_sub_block_attachments+0xf39>
 109ad4c:	xor    %ebx,%ebx
 109ad4e:	mov    %r15,0x60(%rsp)
 109ad53:	jmp    109ad79 <my.diagram_membership::compute_sub_block_attachments+0xf99>
 109ad55:	data16 cs nopw 0x0(%rax,%rax,1)
 109ad60:	mov    0x10(%rsp),%rdi
 109ad65:	call   103c740 <myl_core_drop_owned>
 109ad6a:	mov    0x30(%rsp),%rbx
 109ad6f:	inc    %rbx
 109ad72:	cmp    0x48(%rsp),%rbx
 109ad77:	je     109ad10 <my.diagram_membership::compute_sub_block_attachments+0xf30>
 109ad79:	mov    0x80(%rsp),%rax
 109ad81:	mov    0x20(%rax,%rbx,8),%r14
 109ad86:	mov    %r14,%rdi
 109ad89:	call   104ba40 <myl_core_bytes_utf8_count>
 109ad8e:	test   %rax,%rax
 109ad91:	js     109af6e <my.diagram_membership::compute_sub_block_attachments+0x118e>
 109ad97:	mov    %r14,%rdi
 109ad9a:	call   104bb00 <myl_core_bytes_decode_text>
 109ad9f:	mov    %rax,%rdi
 109ada2:	xor    %eax,%eax
 109ada4:	test   %al,%al
 109ada6:	jne    109da4b <my.diagram_membership::compute_sub_block_attachments+0x3c6b>
 109adac:	mov    %rdi,0x120(%rsp)
 109adb4:	testb  $0x2,0x1(%rdi)
 109adb8:	mov    %rdi,0x10(%rsp)
 109adbd:	jne    109add0 <my.diagram_membership::compute_sub_block_attachments+0xff0>
 109adbf:	call   1044400 <myl_core_str_hash>
 109adc4:	jmp    109add3 <my.diagram_membership::compute_sub_block_attachments+0xff3>
 109adc6:	cs nopw 0x0(%rax,%rax,1)
 109add0:	mov    0x18(%rdi),%eax
 109add3:	mov    %rbx,0x30(%rsp)
 109add8:	mov    %eax,%eax
 109adda:	movabs $0x9e3779b97f4a7c15,%rcx
 109ade4:	imul   %rcx,%rax
 109ade8:	mov    %rax,%r14
 109adeb:	shr    $0x20,%r14
 109adef:	xor    %rax,%r14
 109adf2:	mov    0x28(%rsp),%rax
 109adf7:	mov    0x18(%rax),%rcx
 109adfb:	mov    0x8(%rcx),%rax
 109adff:	test   %rax,%rax
 109ae02:	je     109aee0 <my.diagram_membership::compute_sub_block_attachments+0x1100>
 109ae08:	mov    (%rax),%ecx
 109ae0a:	tzcnt  %ecx,%edx
 109ae0e:	neg    %dl
 109ae10:	shrx   %rdx,%r14,%r13
 109ae15:	lea    -0x1(%rcx),%ebx
 109ae18:	vmovdqu 0x10(%rax,%r13,1),%xmm1
 109ae1f:	mov    %r14d,%edx
 109ae22:	and    $0x7f,%dl
 109ae25:	vmovd  %edx,%xmm0
 109ae29:	vpbroadcastb %xmm0,%xmm0
 109ae2e:	vmovdqa %xmm1,0x50(%rsp)
 109ae34:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109ae38:	vpmovmskb %xmm0,%edx
 109ae3c:	test   %edx,%edx
 109ae3e:	je     109aeb7 <my.diagram_membership::compute_sub_block_attachments+0x10d7>
 109ae40:	add    $0x1e,%ecx
 109ae43:	and    $0xfffffff0,%ecx
 109ae46:	lea    (%rax,%rcx,1),%r12
 109ae4a:	add    $0x10,%r12
 109ae4e:	movzwl %dx,%ebp
 109ae51:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ae60:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ae6f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ae7e:	xchg   %ax,%ax
 109ae80:	tzcnt  %ebp,%eax
 109ae84:	add    %r13d,%eax
 109ae87:	and    %ebx,%eax
 109ae89:	mov    (%r12,%rax,4),%eax
 109ae8d:	shl    $0x4,%rax
 109ae91:	mov    0x28(%rsp),%rcx
 109ae96:	mov    0x20(%rcx,%rax,1),%rdi
 109ae9b:	mov    0x120(%rsp),%rsi
 109aea3:	call   1044580 <myl_core_str_eq>
 109aea8:	test   %al,%al
 109aeaa:	jne    109ad60 <my.diagram_membership::compute_sub_block_attachments+0xf80>
 109aeb0:	blsr   %ebp,%ebp
 109aeb5:	jne    109ae80 <my.diagram_membership::compute_sub_block_attachments+0x10a0>
 109aeb7:	vmovdqa 0x50(%rsp),%xmm0
 109aebd:	vpcmpeqb -0x96af5(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109aec5:	vpmovmskb %xmm0,%eax
 109aec9:	test   %eax,%eax
 109aecb:	je     109aee7 <my.diagram_membership::compute_sub_block_attachments+0x1107>
 109aecd:	tzcnt  %eax,%r12d
 109aed2:	add    %r13d,%r12d
 109aed5:	and    %ebx,%r12d
 109aed8:	not    %r12
 109aedb:	jmp    109afa0 <my.diagram_membership::compute_sub_block_attachments+0x11c0>
 109aee0:	cmpq   $0x0,0x18(%rcx)
 109aee5:	je     109af10 <my.diagram_membership::compute_sub_block_attachments+0x1130>
 109aee7:	mov    0x28(%rsp),%rdi
 109aeec:	lea    0x120(%rsp),%rsi
 109aef4:	mov    %r14,%rdx
 109aef7:	call   1042bc0 <myl_core_dict_find>
 109aefc:	mov    %rax,%r13
 109aeff:	mov    %r13,%r12
 109af02:	test   %r13,%r13
 109af05:	jns    109ad60 <my.diagram_membership::compute_sub_block_attachments+0xf80>
 109af0b:	jmp    109afa0 <my.diagram_membership::compute_sub_block_attachments+0x11c0>
 109af10:	mov    0x20(%rcx),%rbx
 109af14:	mov    $0xffffffffffffffff,%r12
 109af1b:	test   %rbx,%rbx
 109af1e:	je     109afa0 <my.diagram_membership::compute_sub_block_attachments+0x11c0>
 109af24:	mov    0x10(%rcx),%rbp
 109af28:	mov    0x28(%rsp),%rax
 109af2d:	lea    0x20(%rax),%r15
 109af31:	xor    %r13d,%r13d
 109af34:	jmp    109af4c <my.diagram_membership::compute_sub_block_attachments+0x116c>
 109af36:	cs nopw 0x0(%rax,%rax,1)
 109af40:	inc    %r13
 109af43:	add    $0x10,%r15
 109af47:	cmp    %r13,%rbx
 109af4a:	je     109af90 <my.diagram_membership::compute_sub_block_attachments+0x11b0>
 109af4c:	cmp    %r14,0x0(%rbp,%r13,8)
 109af51:	jne    109af40 <my.diagram_membership::compute_sub_block_attachments+0x1160>
 109af53:	mov    (%r15),%rdi
 109af56:	mov    0x120(%rsp),%rsi
 109af5e:	call   1044580 <myl_core_str_eq>
 109af63:	test   %al,%al
 109af65:	je     109af40 <my.diagram_membership::compute_sub_block_attachments+0x1160>
 109af67:	mov    0x60(%rsp),%r15
 109af6c:	jmp    109aeff <my.diagram_membership::compute_sub_block_attachments+0x111f>
 109af6e:	lea    0x50b7b(%rip),%rdi        # 10ebaf0 <core_durable_error.verbs+0x1530>
 109af75:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109af7a:	mov    $0x1,%al
 109af7c:	lea    -0x7f363(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109af83:	test   %al,%al
 109af85:	je     109adac <my.diagram_membership::compute_sub_block_attachments+0xfcc>
 109af8b:	jmp    109da4b <my.diagram_membership::compute_sub_block_attachments+0x3c6b>
 109af90:	mov    0x60(%rsp),%r15
 109af95:	data16 cs nopw 0x0(%rax,%rax,1)
 109afa0:	mov    0x10(%rsp),%rax
 109afa5:	mov    %rax,0x170(%rsp)
 109afad:	mov    %r15,0x168(%rsp)
 109afb5:	mov    0x28(%rsp),%rdi
 109afba:	mov    %r12,%rsi
 109afbd:	lea    0x170(%rsp),%rdx
 109afc5:	lea    0x168(%rsp),%rcx
 109afcd:	xor    %r8d,%r8d
 109afd0:	call   1043240 <myl_core_dict_insert>
 109afd5:	mov    %rax,0x28(%rsp)
 109afda:	jmp    109ad6a <my.diagram_membership::compute_sub_block_attachments+0xf8a>
 109afdf:	lea    0x5c67a(%rip),%rsi        # 10f7660 <core_durable_error.verbs+0xd0a0>
 109afe6:	xor    %edi,%edi
 109afe8:	call   1042f80 <myl_core_dict_new>
 109afed:	mov    %rax,0x60(%rsp)
 109aff2:	mov    0x70(%rsp),%rax
 109aff7:	mov    0x8(%rax),%rax
 109affb:	mov    %rax,0xb0(%rsp)
 109b003:	test   %rax,%rax
 109b006:	je     109b2df <my.diagram_membership::compute_sub_block_attachments+0x14ff>
 109b00c:	xor    %eax,%eax
 109b00e:	jmp    109b026 <my.diagram_membership::compute_sub_block_attachments+0x1246>
 109b010:	mov    0x48(%rsp),%rax
 109b015:	inc    %rax
 109b018:	cmp    0xb0(%rsp),%rax
 109b020:	je     109b2cf <my.diagram_membership::compute_sub_block_attachments+0x14ef>
 109b026:	mov    %rax,0x48(%rsp)
 109b02b:	imul   $0x70,%rax,%rax
 109b02f:	mov    0x70(%rsp),%rcx
 109b034:	mov    0x50(%rcx,%rax,1),%r15
 109b039:	mov    0x8(%r15),%r12
 109b03d:	test   %r12,%r12
 109b040:	je     109b010 <my.diagram_membership::compute_sub_block_attachments+0x1230>
 109b042:	add    $0x20,%r15
 109b046:	xor    %ebx,%ebx
 109b048:	mov    %r15,0x30(%rsp)
 109b04d:	mov    %r12,0x50(%rsp)
 109b052:	jmp    109b070 <my.diagram_membership::compute_sub_block_attachments+0x1290>
 109b054:	mov    0x10(%rsp),%rdi
 109b059:	call   103c740 <myl_core_drop_owned>
 109b05e:	mov    0x30(%rsp),%r15
 109b063:	mov    0x50(%rsp),%r12
 109b068:	inc    %rbx
 109b06b:	cmp    %r12,%rbx
 109b06e:	je     109b010 <my.diagram_membership::compute_sub_block_attachments+0x1230>
 109b070:	imul   $0xf0,%rbx,%rax
 109b077:	cmpl   $0x0,0x10(%r15,%rax,1)
 109b07d:	jne    109b068 <my.diagram_membership::compute_sub_block_attachments+0x1288>
 109b07f:	add    %r15,%rax
 109b082:	mov    (%rax),%r14
 109b085:	mov    %r14,%rdi
 109b088:	call   104ba40 <myl_core_bytes_utf8_count>
 109b08d:	test   %rax,%rax
 109b090:	js     109b2a1 <my.diagram_membership::compute_sub_block_attachments+0x14c1>
 109b096:	mov    %r14,%rdi
 109b099:	call   104bb00 <myl_core_bytes_decode_text>
 109b09e:	mov    %rax,%rdi
 109b0a1:	xor    %eax,%eax
 109b0a3:	test   %al,%al
 109b0a5:	jne    109b2be <my.diagram_membership::compute_sub_block_attachments+0x14de>
 109b0ab:	mov    %rdi,0x118(%rsp)
 109b0b3:	testb  $0x2,0x1(%rdi)
 109b0b7:	mov    %rdi,0x10(%rsp)
 109b0bc:	jne    109b0c5 <my.diagram_membership::compute_sub_block_attachments+0x12e5>
 109b0be:	call   1044400 <myl_core_str_hash>
 109b0c3:	jmp    109b0c8 <my.diagram_membership::compute_sub_block_attachments+0x12e8>
 109b0c5:	mov    0x18(%rdi),%eax
 109b0c8:	mov    %eax,%eax
 109b0ca:	movabs $0x9e3779b97f4a7c15,%rcx
 109b0d4:	imul   %rcx,%rax
 109b0d8:	mov    %rax,%r14
 109b0db:	shr    $0x20,%r14
 109b0df:	xor    %rax,%r14
 109b0e2:	mov    0x60(%rsp),%rax
 109b0e7:	mov    0x18(%rax),%rcx
 109b0eb:	mov    0x8(%rcx),%rax
 109b0ef:	test   %rax,%rax
 109b0f2:	je     109b1e0 <my.diagram_membership::compute_sub_block_attachments+0x1400>
 109b0f8:	mov    (%rax),%ecx
 109b0fa:	tzcnt  %ecx,%edx
 109b0fe:	neg    %dl
 109b100:	shrx   %rdx,%r14,%r13
 109b105:	lea    -0x1(%rcx),%r12d
 109b109:	vmovdqu 0x10(%rax,%r13,1),%xmm1
 109b110:	mov    %r14d,%edx
 109b113:	and    $0x7f,%dl
 109b116:	vmovd  %edx,%xmm0
 109b11a:	vpbroadcastb %xmm0,%xmm0
 109b11f:	vmovdqa %xmm1,0x80(%rsp)
 109b128:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109b12c:	vpmovmskb %xmm0,%edx
 109b130:	test   %edx,%edx
 109b132:	je     109b1b4 <my.diagram_membership::compute_sub_block_attachments+0x13d4>
 109b138:	add    $0x1e,%ecx
 109b13b:	and    $0xfffffff0,%ecx
 109b13e:	lea    (%rax,%rcx,1),%r15
 109b142:	add    $0x10,%r15
 109b146:	movzwl %dx,%ebp
 109b149:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b158:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b167:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b176:	cs nopw 0x0(%rax,%rax,1)
 109b180:	tzcnt  %ebp,%eax
 109b184:	add    %r13d,%eax
 109b187:	and    %r12d,%eax
 109b18a:	mov    (%r15,%rax,4),%eax
 109b18e:	mov    0x60(%rsp),%rcx
 109b193:	mov    0x20(%rcx,%rax,8),%rdi
 109b198:	mov    0x118(%rsp),%rsi
 109b1a0:	call   1044580 <myl_core_str_eq>
 109b1a5:	test   %al,%al
 109b1a7:	jne    109b054 <my.diagram_membership::compute_sub_block_attachments+0x1274>
 109b1ad:	blsr   %ebp,%ebp
 109b1b2:	jne    109b180 <my.diagram_membership::compute_sub_block_attachments+0x13a0>
 109b1b4:	vmovdqa 0x80(%rsp),%xmm0
 109b1bd:	vpcmpeqb -0x96df5(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109b1c5:	vpmovmskb %xmm0,%eax
 109b1c9:	test   %eax,%eax
 109b1cb:	je     109b1e7 <my.diagram_membership::compute_sub_block_attachments+0x1407>
 109b1cd:	tzcnt  %eax,%r15d
 109b1d2:	add    %r13d,%r15d
 109b1d5:	and    %r12d,%r15d
 109b1d8:	not    %r15
 109b1db:	jmp    109b270 <my.diagram_membership::compute_sub_block_attachments+0x1490>
 109b1e0:	cmpq   $0x0,0x18(%rcx)
 109b1e5:	je     109b20d <my.diagram_membership::compute_sub_block_attachments+0x142d>
 109b1e7:	mov    0x60(%rsp),%rdi
 109b1ec:	lea    0x118(%rsp),%rsi
 109b1f4:	mov    %r14,%rdx
 109b1f7:	call   1042bc0 <myl_core_dict_find>
 109b1fc:	mov    %rax,%r13
 109b1ff:	mov    %r13,%r15
 109b202:	test   %r13,%r13
 109b205:	jns    109b054 <my.diagram_membership::compute_sub_block_attachments+0x1274>
 109b20b:	jmp    109b270 <my.diagram_membership::compute_sub_block_attachments+0x1490>
 109b20d:	mov    0x20(%rcx),%r12
 109b211:	mov    $0xffffffffffffffff,%r15
 109b218:	test   %r12,%r12
 109b21b:	je     109b270 <my.diagram_membership::compute_sub_block_attachments+0x1490>
 109b21d:	mov    0x10(%rcx),%rbp
 109b221:	xor    %r13d,%r13d
 109b224:	jmp    109b248 <my.diagram_membership::compute_sub_block_attachments+0x1468>
 109b226:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b235:	data16 cs nopw 0x0(%rax,%rax,1)
 109b240:	inc    %r13
 109b243:	cmp    %r13,%r12
 109b246:	je     109b270 <my.diagram_membership::compute_sub_block_attachments+0x1490>
 109b248:	cmp    %r14,0x0(%rbp,%r13,8)
 109b24d:	jne    109b240 <my.diagram_membership::compute_sub_block_attachments+0x1460>
 109b24f:	mov    0x60(%rsp),%rax
 109b254:	mov    0x20(%rax,%r13,8),%rdi
 109b259:	mov    0x118(%rsp),%rsi
 109b261:	call   1044580 <myl_core_str_eq>
 109b266:	test   %al,%al
 109b268:	je     109b240 <my.diagram_membership::compute_sub_block_attachments+0x1460>
 109b26a:	jmp    109b1ff <my.diagram_membership::compute_sub_block_attachments+0x141f>
 109b26c:	nopl   0x0(%rax)
 109b270:	mov    0x10(%rsp),%rax
 109b275:	mov    %rax,0x160(%rsp)
 109b27d:	mov    0x60(%rsp),%rdi
 109b282:	mov    %r15,%rsi
 109b285:	lea    0x160(%rsp),%rdx
 109b28d:	xor    %ecx,%ecx
 109b28f:	xor    %r8d,%r8d
 109b292:	call   1043240 <myl_core_dict_insert>
 109b297:	mov    %rax,0x60(%rsp)
 109b29c:	jmp    109b05e <my.diagram_membership::compute_sub_block_attachments+0x127e>
 109b2a1:	lea    0x50848(%rip),%rdi        # 10ebaf0 <core_durable_error.verbs+0x1530>
 109b2a8:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109b2ad:	mov    $0x1,%al
 109b2af:	lea    -0x7f696(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109b2b6:	test   %al,%al
 109b2b8:	je     109b0ab <my.diagram_membership::compute_sub_block_attachments+0x12cb>
 109b2be:	call   103c740 <myl_core_drop_owned>
 109b2c3:	lea    0x50856(%rip),%rdi        # 10ebb20 <core_durable_error.verbs+0x1560>
 109b2ca:	call   1042840 <myl_core_assert_fail>
 109b2cf:	mov    0x70(%rsp),%rax
 109b2d4:	mov    0x8(%rax),%rax
 109b2d8:	mov    %rax,0x78(%rsp)
 109b2dd:	jmp    109b2e8 <my.diagram_membership::compute_sub_block_attachments+0x1508>
 109b2df:	movq   $0x0,0x78(%rsp)
 109b2e8:	mov    0xa0(%rsp),%rax
 109b2f0:	mov    0x8(%rax),%rax
 109b2f4:	mov    %rax,0xc8(%rsp)
 109b2fc:	mov    %fs:0xfffffffffffffec8,%rdi
 109b305:	test   %rdi,%rdi
 109b308:	je     109da37 <my.diagram_membership::compute_sub_block_attachments+0x3c57>
 109b30e:	mov    (%rdi),%rax
 109b311:	mov    %rax,%fs:0xfffffffffffffec8
 109b31a:	movl   $0x1000000,(%rdi)
 109b320:	vpxor  %xmm0,%xmm0,%xmm0
 109b324:	vmovdqu %xmm0,0x8(%rdi)
 109b329:	movq   $0x0,0x18(%rdi)
 109b331:	mov    0xc8(%rsp),%rbx
 109b339:	mov    0x78(%rsp),%rdx
 109b33e:	imul   %rdx,%rbx
 109b342:	jo     109d9cd <my.diagram_membership::compute_sub_block_attachments+0x3bed>
 109b348:	test   %rbx,%rbx
 109b34b:	je     109b3b4 <my.diagram_membership::compute_sub_block_attachments+0x15d4>
 109b34d:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b35c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b36b:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b37a:	nopw   0x0(%rax,%rax,1)
 109b380:	mov    0x8(%rdi),%rax
 109b384:	cmp    0x10(%rdi),%rax
 109b388:	jae    109b3a1 <my.diagram_membership::compute_sub_block_attachments+0x15c1>
 109b38a:	movq   $0x0,0x20(%rdi,%rax,8)
 109b393:	inc    %rax
 109b396:	mov    %rax,0x8(%rdi)
 109b39a:	dec    %rbx
 109b39d:	jne    109b380 <my.diagram_membership::compute_sub_block_attachments+0x15a0>
 109b39f:	jmp    109b3b4 <my.diagram_membership::compute_sub_block_attachments+0x15d4>
 109b3a1:	mov    $0x8,%esi
 109b3a6:	call   103ba40 <myl_core_list_grow>
 109b3ab:	mov    %rax,%rdi
 109b3ae:	mov    0x8(%rax),%rax
 109b3b2:	jmp    109b38a <my.diagram_membership::compute_sub_block_attachments+0x15aa>
 109b3b4:	mov    %rdi,0xa8(%rsp)
 109b3bc:	cmpq   $0x0,0x78(%rsp)
 109b3c2:	je     109bf70 <my.diagram_membership::compute_sub_block_attachments+0x2190>
 109b3c8:	mov    0x70(%rsp),%rax
 109b3cd:	add    $0x20,%rax
 109b3d1:	mov    %rax,0x98(%rsp)
 109b3d9:	mov    0x8(%rsp),%rax
 109b3de:	add    $0x20,%rax
 109b3e2:	mov    %rax,0xe8(%rsp)
 109b3ea:	mov    0x20(%rsp),%rax
 109b3ef:	add    $0x20,%rax
 109b3f3:	mov    %rax,0x158(%rsp)
 109b3fb:	xor    %eax,%eax
 109b3fd:	jmp    109b420 <my.diagram_membership::compute_sub_block_attachments+0x1640>
 109b3ff:	nop
 109b400:	mov    0x10(%rsp),%rdi
 109b405:	call   103c740 <myl_core_drop_owned>
 109b40a:	mov    0xd8(%rsp),%rax
 109b412:	inc    %rax
 109b415:	cmp    0x78(%rsp),%rax
 109b41a:	je     109bf70 <my.diagram_membership::compute_sub_block_attachments+0x2190>
 109b420:	mov    %rax,0xd8(%rsp)
 109b428:	imul   $0x70,%rax,%rbx
 109b42c:	xor    %edi,%edi
 109b42e:	lea    0x5c22b(%rip),%rsi        # 10f7660 <core_durable_error.verbs+0xd0a0>
 109b435:	call   1042f80 <myl_core_dict_new>
 109b43a:	mov    %rax,0x10(%rsp)
 109b43f:	mov    0x98(%rsp),%rax
 109b447:	mov    %rbx,0xd0(%rsp)
 109b44f:	mov    0x28(%rax,%rbx,1),%rax
 109b454:	mov    %rax,0xe0(%rsp)
 109b45c:	mov    0x8(%rax),%rax
 109b460:	mov    %rax,0xf0(%rsp)
 109b468:	test   %rax,%rax
 109b46b:	je     109b710 <my.diagram_membership::compute_sub_block_attachments+0x1930>
 109b471:	xor    %eax,%eax
 109b473:	jmp    109b499 <my.diagram_membership::compute_sub_block_attachments+0x16b9>
 109b475:	data16 cs nopw 0x0(%rax,%rax,1)
 109b480:	mov    0xb0(%rsp),%rax
 109b488:	inc    %rax
 109b48b:	cmp    0xf0(%rsp),%rax
 109b493:	je     109b710 <my.diagram_membership::compute_sub_block_attachments+0x1930>
 109b499:	mov    %rax,0xb0(%rsp)
 109b4a1:	lea    (%rax,%rax,2),%rax
 109b4a5:	mov    0xe0(%rsp),%rcx
 109b4ad:	mov    0x28(%rcx,%rax,8),%rax
 109b4b2:	mov    %rax,0x80(%rsp)
 109b4ba:	mov    0x8(%rax),%rax
 109b4be:	mov    %rax,0x48(%rsp)
 109b4c3:	test   %rax,%rax
 109b4c6:	je     109b480 <my.diagram_membership::compute_sub_block_attachments+0x16a0>
 109b4c8:	xor    %r12d,%r12d
 109b4cb:	jmp    109b4e4 <my.diagram_membership::compute_sub_block_attachments+0x1704>
 109b4cd:	nopl   (%rax)
 109b4d0:	mov    0x30(%rsp),%rdi
 109b4d5:	call   103c740 <myl_core_drop_owned>
 109b4da:	inc    %r12
 109b4dd:	cmp    0x48(%rsp),%r12
 109b4e2:	je     109b480 <my.diagram_membership::compute_sub_block_attachments+0x16a0>
 109b4e4:	mov    %r12,%rax
 109b4e7:	shl    $0x5,%rax
 109b4eb:	mov    0x80(%rsp),%rcx
 109b4f3:	mov    0x28(%rcx,%rax,1),%r14
 109b4f8:	mov    %r14,%rdi
 109b4fb:	call   104ba40 <myl_core_bytes_utf8_count>
 109b500:	test   %rax,%rax
 109b503:	js     109b6e1 <my.diagram_membership::compute_sub_block_attachments+0x1901>
 109b509:	mov    %r14,%rdi
 109b50c:	call   104bb00 <myl_core_bytes_decode_text>
 109b511:	mov    %rax,%rdi
 109b514:	xor    %eax,%eax
 109b516:	test   %al,%al
 109b518:	jne    109d9e1 <my.diagram_membership::compute_sub_block_attachments+0x3c01>
 109b51e:	mov    %rdi,0x150(%rsp)
 109b526:	testb  $0x2,0x1(%rdi)
 109b52a:	mov    %rdi,0x30(%rsp)
 109b52f:	jne    109b540 <my.diagram_membership::compute_sub_block_attachments+0x1760>
 109b531:	call   1044400 <myl_core_str_hash>
 109b536:	jmp    109b543 <my.diagram_membership::compute_sub_block_attachments+0x1763>
 109b538:	nopl   0x0(%rax,%rax,1)
 109b540:	mov    0x18(%rdi),%eax
 109b543:	mov    %eax,%eax
 109b545:	movabs $0x9e3779b97f4a7c15,%rcx
 109b54f:	imul   %rcx,%rax
 109b553:	mov    %rax,%r14
 109b556:	shr    $0x20,%r14
 109b55a:	xor    %rax,%r14
 109b55d:	mov    0x10(%rsp),%rax
 109b562:	mov    0x18(%rax),%rcx
 109b566:	mov    0x8(%rcx),%rax
 109b56a:	test   %rax,%rax
 109b56d:	je     109b620 <my.diagram_membership::compute_sub_block_attachments+0x1840>
 109b573:	mov    (%rax),%ecx
 109b575:	tzcnt  %ecx,%edx
 109b579:	neg    %dl
 109b57b:	shrx   %rdx,%r14,%r13
 109b580:	lea    -0x1(%rcx),%ebx
 109b583:	vmovdqu 0x10(%rax,%r13,1),%xmm1
 109b58a:	mov    %r14d,%edx
 109b58d:	and    $0x7f,%dl
 109b590:	vmovd  %edx,%xmm0
 109b594:	vpbroadcastb %xmm0,%xmm0
 109b599:	vmovdqa %xmm1,0x50(%rsp)
 109b59f:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109b5a3:	vpmovmskb %xmm0,%edx
 109b5a7:	test   %edx,%edx
 109b5a9:	je     109b5f3 <my.diagram_membership::compute_sub_block_attachments+0x1813>
 109b5ab:	add    $0x1e,%ecx
 109b5ae:	and    $0xfffffff0,%ecx
 109b5b1:	lea    (%rax,%rcx,1),%r15
 109b5b5:	add    $0x10,%r15
 109b5b9:	movzwl %dx,%ebp
 109b5bc:	nopl   0x0(%rax)
 109b5c0:	tzcnt  %ebp,%eax
 109b5c4:	add    %r13d,%eax
 109b5c7:	and    %ebx,%eax
 109b5c9:	mov    (%r15,%rax,4),%eax
 109b5cd:	mov    0x10(%rsp),%rcx
 109b5d2:	mov    0x20(%rcx,%rax,8),%rdi
 109b5d7:	mov    0x150(%rsp),%rsi
 109b5df:	call   1044580 <myl_core_str_eq>
 109b5e4:	test   %al,%al
 109b5e6:	jne    109b4d0 <my.diagram_membership::compute_sub_block_attachments+0x16f0>
 109b5ec:	blsr   %ebp,%ebp
 109b5f1:	jne    109b5c0 <my.diagram_membership::compute_sub_block_attachments+0x17e0>
 109b5f3:	vmovdqa 0x50(%rsp),%xmm0
 109b5f9:	vpcmpeqb -0x97231(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109b601:	vpmovmskb %xmm0,%eax
 109b605:	test   %eax,%eax
 109b607:	je     109b627 <my.diagram_membership::compute_sub_block_attachments+0x1847>
 109b609:	tzcnt  %eax,%r15d
 109b60e:	add    %r13d,%r15d
 109b611:	and    %ebx,%r15d
 109b614:	not    %r15
 109b617:	jmp    109b6b0 <my.diagram_membership::compute_sub_block_attachments+0x18d0>
 109b61c:	nopl   0x0(%rax)
 109b620:	cmpq   $0x0,0x18(%rcx)
 109b625:	je     109b64d <my.diagram_membership::compute_sub_block_attachments+0x186d>
 109b627:	mov    0x10(%rsp),%rdi
 109b62c:	lea    0x150(%rsp),%rsi
 109b634:	mov    %r14,%rdx
 109b637:	call   1042bc0 <myl_core_dict_find>
 109b63c:	mov    %rax,%r13
 109b63f:	mov    %r13,%r15
 109b642:	test   %r13,%r13
 109b645:	jns    109b4d0 <my.diagram_membership::compute_sub_block_attachments+0x16f0>
 109b64b:	jmp    109b6b0 <my.diagram_membership::compute_sub_block_attachments+0x18d0>
 109b64d:	mov    0x20(%rcx),%rbx
 109b651:	mov    $0xffffffffffffffff,%r15
 109b658:	test   %rbx,%rbx
 109b65b:	je     109b6b0 <my.diagram_membership::compute_sub_block_attachments+0x18d0>
 109b65d:	mov    0x10(%rcx),%rbp
 109b661:	xor    %r13d,%r13d
 109b664:	jmp    109b688 <my.diagram_membership::compute_sub_block_attachments+0x18a8>
 109b666:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b675:	data16 cs nopw 0x0(%rax,%rax,1)
 109b680:	inc    %r13
 109b683:	cmp    %r13,%rbx
 109b686:	je     109b6b0 <my.diagram_membership::compute_sub_block_attachments+0x18d0>
 109b688:	cmp    %r14,0x0(%rbp,%r13,8)
 109b68d:	jne    109b680 <my.diagram_membership::compute_sub_block_attachments+0x18a0>
 109b68f:	mov    0x10(%rsp),%rax
 109b694:	mov    0x20(%rax,%r13,8),%rdi
 109b699:	mov    0x150(%rsp),%rsi
 109b6a1:	call   1044580 <myl_core_str_eq>
 109b6a6:	test   %al,%al
 109b6a8:	je     109b680 <my.diagram_membership::compute_sub_block_attachments+0x18a0>
 109b6aa:	jmp    109b63f <my.diagram_membership::compute_sub_block_attachments+0x185f>
 109b6ac:	nopl   0x0(%rax)
 109b6b0:	mov    0x30(%rsp),%rax
 109b6b5:	mov    %rax,0x1b0(%rsp)
 109b6bd:	mov    0x10(%rsp),%rdi
 109b6c2:	mov    %r15,%rsi
 109b6c5:	lea    0x1b0(%rsp),%rdx
 109b6cd:	xor    %ecx,%ecx
 109b6cf:	xor    %r8d,%r8d
 109b6d2:	call   1043240 <myl_core_dict_insert>
 109b6d7:	mov    %rax,0x10(%rsp)
 109b6dc:	jmp    109b4da <my.diagram_membership::compute_sub_block_attachments+0x16fa>
 109b6e1:	lea    0x50408(%rip),%rdi        # 10ebaf0 <core_durable_error.verbs+0x1530>
 109b6e8:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109b6ed:	mov    $0x1,%al
 109b6ef:	lea    -0x7fad6(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109b6f6:	test   %al,%al
 109b6f8:	je     109b51e <my.diagram_membership::compute_sub_block_attachments+0x173e>
 109b6fe:	jmp    109d9e1 <my.diagram_membership::compute_sub_block_attachments+0x3c01>
 109b703:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b710:	mov    0xd0(%rsp),%rax
 109b718:	add    0x98(%rsp),%rax
 109b720:	mov    0x30(%rax),%rbx
 109b724:	mov    0x8(%rbx),%rax
 109b728:	mov    %rax,0x80(%rsp)
 109b730:	test   %rax,%rax
 109b733:	je     109b990 <my.diagram_membership::compute_sub_block_attachments+0x1bb0>
 109b739:	add    $0x20,%rbx
 109b73d:	xor    %r12d,%r12d
 109b740:	mov    %rbx,0x48(%rsp)
 109b745:	jmp    109b770 <my.diagram_membership::compute_sub_block_attachments+0x1990>
 109b747:	nopw   0x0(%rax,%rax,1)
 109b750:	mov    0x30(%rsp),%rdi
 109b755:	call   103c740 <myl_core_drop_owned>
 109b75a:	inc    %r12
 109b75d:	cmp    0x80(%rsp),%r12
 109b765:	mov    0x48(%rsp),%rbx
 109b76a:	je     109b990 <my.diagram_membership::compute_sub_block_attachments+0x1bb0>
 109b770:	imul   $0xf0,%r12,%rax
 109b777:	mov    (%rbx,%rax,1),%r14
 109b77b:	mov    %r14,%rdi
 109b77e:	call   104ba40 <myl_core_bytes_utf8_count>
 109b783:	test   %rax,%rax
 109b786:	js     109b961 <my.diagram_membership::compute_sub_block_attachments+0x1b81>
 109b78c:	mov    %r14,%rdi
 109b78f:	call   104bb00 <myl_core_bytes_decode_text>
 109b794:	mov    %rax,%rdi
 109b797:	xor    %eax,%eax
 109b799:	test   %al,%al
 109b79b:	jne    109da5c <my.diagram_membership::compute_sub_block_attachments+0x3c7c>
 109b7a1:	mov    %rdi,0x148(%rsp)
 109b7a9:	testb  $0x2,0x1(%rdi)
 109b7ad:	mov    %rdi,0x30(%rsp)
 109b7b2:	jne    109b7c0 <my.diagram_membership::compute_sub_block_attachments+0x19e0>
 109b7b4:	call   1044400 <myl_core_str_hash>
 109b7b9:	jmp    109b7c3 <my.diagram_membership::compute_sub_block_attachments+0x19e3>
 109b7bb:	nopl   0x0(%rax,%rax,1)
 109b7c0:	mov    0x18(%rdi),%eax
 109b7c3:	mov    %eax,%eax
 109b7c5:	movabs $0x9e3779b97f4a7c15,%rcx
 109b7cf:	imul   %rcx,%rax
 109b7d3:	mov    %rax,%r14
 109b7d6:	shr    $0x20,%r14
 109b7da:	xor    %rax,%r14
 109b7dd:	mov    0x10(%rsp),%rax
 109b7e2:	mov    0x18(%rax),%rcx
 109b7e6:	mov    0x8(%rcx),%rax
 109b7ea:	test   %rax,%rax
 109b7ed:	je     109b8a0 <my.diagram_membership::compute_sub_block_attachments+0x1ac0>
 109b7f3:	mov    (%rax),%ecx
 109b7f5:	tzcnt  %ecx,%edx
 109b7f9:	neg    %dl
 109b7fb:	shrx   %rdx,%r14,%r15
 109b800:	lea    -0x1(%rcx),%ebx
 109b803:	vmovdqu 0x10(%rax,%r15,1),%xmm1
 109b80a:	mov    %r14d,%edx
 109b80d:	and    $0x7f,%dl
 109b810:	vmovd  %edx,%xmm0
 109b814:	vpbroadcastb %xmm0,%xmm0
 109b819:	vmovdqa %xmm1,0x50(%rsp)
 109b81f:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109b823:	vpmovmskb %xmm0,%edx
 109b827:	test   %edx,%edx
 109b829:	je     109b874 <my.diagram_membership::compute_sub_block_attachments+0x1a94>
 109b82b:	add    $0x1e,%ecx
 109b82e:	and    $0xfffffff0,%ecx
 109b831:	lea    (%rax,%rcx,1),%r13
 109b835:	add    $0x10,%r13
 109b839:	movzwl %dx,%ebp
 109b83c:	nopl   0x0(%rax)
 109b840:	tzcnt  %ebp,%eax
 109b844:	add    %r15d,%eax
 109b847:	and    %ebx,%eax
 109b849:	mov    0x0(%r13,%rax,4),%eax
 109b84e:	mov    0x10(%rsp),%rcx
 109b853:	mov    0x20(%rcx,%rax,8),%rdi
 109b858:	mov    0x148(%rsp),%rsi
 109b860:	call   1044580 <myl_core_str_eq>
 109b865:	test   %al,%al
 109b867:	jne    109b750 <my.diagram_membership::compute_sub_block_attachments+0x1970>
 109b86d:	blsr   %ebp,%ebp
 109b872:	jne    109b840 <my.diagram_membership::compute_sub_block_attachments+0x1a60>
 109b874:	vmovdqa 0x50(%rsp),%xmm0
 109b87a:	vpcmpeqb -0x974b2(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109b882:	vpmovmskb %xmm0,%eax
 109b886:	test   %eax,%eax
 109b888:	je     109b8a7 <my.diagram_membership::compute_sub_block_attachments+0x1ac7>
 109b88a:	tzcnt  %eax,%r13d
 109b88f:	add    %r15d,%r13d
 109b892:	and    %ebx,%r13d
 109b895:	not    %r13
 109b898:	jmp    109b930 <my.diagram_membership::compute_sub_block_attachments+0x1b50>
 109b89d:	nopl   (%rax)
 109b8a0:	cmpq   $0x0,0x18(%rcx)
 109b8a5:	je     109b8cd <my.diagram_membership::compute_sub_block_attachments+0x1aed>
 109b8a7:	mov    0x10(%rsp),%rdi
 109b8ac:	lea    0x148(%rsp),%rsi
 109b8b4:	mov    %r14,%rdx
 109b8b7:	call   1042bc0 <myl_core_dict_find>
 109b8bc:	mov    %rax,%r15
 109b8bf:	mov    %r15,%r13
 109b8c2:	test   %r15,%r15
 109b8c5:	jns    109b750 <my.diagram_membership::compute_sub_block_attachments+0x1970>
 109b8cb:	jmp    109b930 <my.diagram_membership::compute_sub_block_attachments+0x1b50>
 109b8cd:	mov    0x20(%rcx),%rbx
 109b8d1:	mov    $0xffffffffffffffff,%r13
 109b8d8:	test   %rbx,%rbx
 109b8db:	je     109b930 <my.diagram_membership::compute_sub_block_attachments+0x1b50>
 109b8dd:	mov    0x10(%rcx),%rbp
 109b8e1:	xor    %r15d,%r15d
 109b8e4:	jmp    109b908 <my.diagram_membership::compute_sub_block_attachments+0x1b28>
 109b8e6:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b8f5:	data16 cs nopw 0x0(%rax,%rax,1)
 109b900:	inc    %r15
 109b903:	cmp    %r15,%rbx
 109b906:	je     109b930 <my.diagram_membership::compute_sub_block_attachments+0x1b50>
 109b908:	cmp    %r14,0x0(%rbp,%r15,8)
 109b90d:	jne    109b900 <my.diagram_membership::compute_sub_block_attachments+0x1b20>
 109b90f:	mov    0x10(%rsp),%rax
 109b914:	mov    0x20(%rax,%r15,8),%rdi
 109b919:	mov    0x148(%rsp),%rsi
 109b921:	call   1044580 <myl_core_str_eq>
 109b926:	test   %al,%al
 109b928:	je     109b900 <my.diagram_membership::compute_sub_block_attachments+0x1b20>
 109b92a:	jmp    109b8bf <my.diagram_membership::compute_sub_block_attachments+0x1adf>
 109b92c:	nopl   0x0(%rax)
 109b930:	mov    0x30(%rsp),%rax
 109b935:	mov    %rax,0x1a8(%rsp)
 109b93d:	mov    0x10(%rsp),%rdi
 109b942:	mov    %r13,%rsi
 109b945:	lea    0x1a8(%rsp),%rdx
 109b94d:	xor    %ecx,%ecx
 109b94f:	xor    %r8d,%r8d
 109b952:	call   1043240 <myl_core_dict_insert>
 109b957:	mov    %rax,0x10(%rsp)
 109b95c:	jmp    109b75a <my.diagram_membership::compute_sub_block_attachments+0x197a>
 109b961:	lea    0x50188(%rip),%rdi        # 10ebaf0 <core_durable_error.verbs+0x1530>
 109b968:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109b96d:	mov    $0x1,%al
 109b96f:	lea    -0x7fd56(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109b976:	test   %al,%al
 109b978:	je     109b7a1 <my.diagram_membership::compute_sub_block_attachments+0x19c1>
 109b97e:	jmp    109da5c <my.diagram_membership::compute_sub_block_attachments+0x3c7c>
 109b983:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b990:	mov    0x10(%rsp),%rax
 109b995:	mov    0x8(%rax),%rax
 109b999:	mov    %rax,0x80(%rsp)
 109b9a1:	test   %rax,%rax
 109b9a4:	je     109b400 <my.diagram_membership::compute_sub_block_attachments+0x1620>
 109b9aa:	xor    %esi,%esi
 109b9ac:	jmp    109b9e6 <my.diagram_membership::compute_sub_block_attachments+0x1c06>
 109b9ae:	xchg   %ax,%ax
 109b9b0:	vmovdqa 0x50(%rsp),%xmm0
 109b9b6:	vpcmpeqb -0x975ee(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109b9be:	vpmovmskb %xmm0,%eax
 109b9c2:	test   %eax,%eax
 109b9c4:	je     109bcc7 <my.diagram_membership::compute_sub_block_attachments+0x1ee7>
 109b9ca:	nopw   0x0(%rax,%rax,1)
 109b9d0:	mov    0x30(%rsp),%rsi
 109b9d5:	inc    %rsi
 109b9d8:	cmp    0x80(%rsp),%rsi
 109b9e0:	je     109b400 <my.diagram_membership::compute_sub_block_attachments+0x1620>
 109b9e6:	mov    0x10(%rsp),%rbx
 109b9eb:	mov    %rbx,%rdi
 109b9ee:	mov    %rsi,0x30(%rsp)
 109b9f3:	call   1043c40 <myl_core_dict_ordinal>
 109b9f8:	mov    0x20(%rbx,%rax,8),%r14
 109b9fd:	mov    %r14,0x110(%rsp)
 109ba05:	testb  $0x2,0x1(%r14)
 109ba0a:	jne    109ba20 <my.diagram_membership::compute_sub_block_attachments+0x1c40>
 109ba0c:	mov    %r14,%rdi
 109ba0f:	call   1044400 <myl_core_str_hash>
 109ba14:	jmp    109ba24 <my.diagram_membership::compute_sub_block_attachments+0x1c44>
 109ba16:	cs nopw 0x0(%rax,%rax,1)
 109ba20:	mov    0x18(%r14),%eax
 109ba24:	mov    %eax,%eax
 109ba26:	movabs $0x9e3779b97f4a7c15,%rcx
 109ba30:	imul   %rcx,%rax
 109ba34:	mov    %rax,%r13
 109ba37:	shr    $0x20,%r13
 109ba3b:	xor    %rax,%r13
 109ba3e:	mov    0x60(%rsp),%rax
 109ba43:	mov    0x18(%rax),%rcx
 109ba47:	mov    0x8(%rcx),%rax
 109ba4b:	test   %rax,%rax
 109ba4e:	je     109bb10 <my.diagram_membership::compute_sub_block_attachments+0x1d30>
 109ba54:	mov    (%rax),%ecx
 109ba56:	tzcnt  %ecx,%edx
 109ba5a:	neg    %dl
 109ba5c:	shrx   %rdx,%r13,%rbx
 109ba61:	vmovdqu 0x10(%rax,%rbx,1),%xmm1
 109ba67:	mov    %r13d,%edx
 109ba6a:	and    $0x7f,%dl
 109ba6d:	vmovd  %edx,%xmm0
 109ba71:	vpbroadcastb %xmm0,%xmm0
 109ba76:	vmovdqa %xmm1,0x50(%rsp)
 109ba7c:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109ba80:	vpmovmskb %xmm0,%edx
 109ba84:	test   %edx,%edx
 109ba86:	je     109baf3 <my.diagram_membership::compute_sub_block_attachments+0x1d13>
 109ba88:	lea    -0x1(%rcx),%r15d
 109ba8c:	add    $0x1e,%ecx
 109ba8f:	and    $0xfffffff0,%ecx
 109ba92:	lea    (%rax,%rcx,1),%r12
 109ba96:	add    $0x10,%r12
 109ba9a:	movzwl %dx,%ebp
 109ba9d:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109baac:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109babb:	nopl   0x0(%rax,%rax,1)
 109bac0:	tzcnt  %ebp,%eax
 109bac4:	add    %ebx,%eax
 109bac6:	and    %r15d,%eax
 109bac9:	mov    (%r12,%rax,4),%eax
 109bacd:	mov    0x60(%rsp),%rcx
 109bad2:	mov    0x20(%rcx,%rax,8),%rdi
 109bad7:	mov    0x110(%rsp),%rsi
 109badf:	call   1044580 <myl_core_str_eq>
 109bae4:	test   %al,%al
 109bae6:	jne    109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109baec:	blsr   %ebp,%ebp
 109baf1:	jne    109bac0 <my.diagram_membership::compute_sub_block_attachments+0x1ce0>
 109baf3:	vmovdqa 0x50(%rsp),%xmm0
 109baf9:	vpcmpeqb -0x97731(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109bb01:	vpmovmskb %xmm0,%eax
 109bb05:	test   %eax,%eax
 109bb07:	jne    109bbb0 <my.diagram_membership::compute_sub_block_attachments+0x1dd0>
 109bb0d:	jmp    109bb17 <my.diagram_membership::compute_sub_block_attachments+0x1d37>
 109bb0f:	nop
 109bb10:	cmpq   $0x0,0x18(%rcx)
 109bb15:	je     109bb3a <my.diagram_membership::compute_sub_block_attachments+0x1d5a>
 109bb17:	mov    0x60(%rsp),%rdi
 109bb1c:	lea    0x110(%rsp),%rsi
 109bb24:	mov    %r13,%rdx
 109bb27:	call   1042bc0 <myl_core_dict_find>
 109bb2c:	mov    %rax,%r15
 109bb2f:	test   %r15,%r15
 109bb32:	jns    109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109bb38:	jmp    109bbb0 <my.diagram_membership::compute_sub_block_attachments+0x1dd0>
 109bb3a:	mov    0x20(%rcx),%rbx
 109bb3e:	test   %rbx,%rbx
 109bb41:	je     109bbb0 <my.diagram_membership::compute_sub_block_attachments+0x1dd0>
 109bb43:	mov    0x10(%rcx),%r12
 109bb47:	xor    %r15d,%r15d
 109bb4a:	jmp    109bb88 <my.diagram_membership::compute_sub_block_attachments+0x1da8>
 109bb4c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bb5b:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bb6a:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bb79:	nopl   0x0(%rax)
 109bb80:	inc    %r15
 109bb83:	cmp    %r15,%rbx
 109bb86:	je     109bbb0 <my.diagram_membership::compute_sub_block_attachments+0x1dd0>
 109bb88:	cmp    %r13,(%r12,%r15,8)
 109bb8c:	jne    109bb80 <my.diagram_membership::compute_sub_block_attachments+0x1da0>
 109bb8e:	mov    0x60(%rsp),%rax
 109bb93:	mov    0x20(%rax,%r15,8),%rdi
 109bb98:	mov    0x110(%rsp),%rsi
 109bba0:	call   1044580 <myl_core_str_eq>
 109bba5:	test   %al,%al
 109bba7:	je     109bb80 <my.diagram_membership::compute_sub_block_attachments+0x1da0>
 109bba9:	jmp    109bb2f <my.diagram_membership::compute_sub_block_attachments+0x1d4f>
 109bbab:	nopl   0x0(%rax,%rax,1)
 109bbb0:	mov    %r14,0x108(%rsp)
 109bbb8:	testb  $0x2,0x1(%r14)
 109bbbd:	jne    109bbd0 <my.diagram_membership::compute_sub_block_attachments+0x1df0>
 109bbbf:	mov    %r14,%rdi
 109bbc2:	call   1044400 <myl_core_str_hash>
 109bbc7:	jmp    109bbd4 <my.diagram_membership::compute_sub_block_attachments+0x1df4>
 109bbc9:	nopl   0x0(%rax)
 109bbd0:	mov    0x18(%r14),%eax
 109bbd4:	mov    %eax,%eax
 109bbd6:	movabs $0x9e3779b97f4a7c15,%rcx
 109bbe0:	imul   %rcx,%rax
 109bbe4:	mov    %rax,%r14
 109bbe7:	shr    $0x20,%r14
 109bbeb:	xor    %rax,%r14
 109bbee:	mov    0x8(%rsp),%rax
 109bbf3:	mov    0x18(%rax),%rcx
 109bbf7:	mov    0x8(%rcx),%rax
 109bbfb:	test   %rax,%rax
 109bbfe:	je     109bcc0 <my.diagram_membership::compute_sub_block_attachments+0x1ee0>
 109bc04:	mov    (%rax),%ecx
 109bc06:	tzcnt  %ecx,%edx
 109bc0a:	neg    %dl
 109bc0c:	shrx   %rdx,%r14,%rbx
 109bc11:	vmovdqu 0x10(%rax,%rbx,1),%xmm1
 109bc17:	mov    %r14d,%edx
 109bc1a:	and    $0x7f,%dl
 109bc1d:	vmovd  %edx,%xmm0
 109bc21:	vpbroadcastb %xmm0,%xmm0
 109bc26:	vmovdqa %xmm1,0x50(%rsp)
 109bc2c:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109bc30:	vpmovmskb %xmm0,%edx
 109bc34:	test   %edx,%edx
 109bc36:	je     109b9b0 <my.diagram_membership::compute_sub_block_attachments+0x1bd0>
 109bc3c:	lea    -0x1(%rcx),%r15d
 109bc40:	add    $0x1e,%ecx
 109bc43:	and    $0xfffffff0,%ecx
 109bc46:	lea    (%rax,%rcx,1),%r12
 109bc4a:	add    $0x10,%r12
 109bc4e:	movzwl %dx,%ebp
 109bc51:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bc60:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bc6f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bc7e:	xchg   %ax,%ax
 109bc80:	tzcnt  %ebp,%eax
 109bc84:	add    %ebx,%eax
 109bc86:	and    %r15d,%eax
 109bc89:	mov    (%r12,%rax,4),%r13d
 109bc8d:	shl    $0x4,%r13
 109bc91:	mov    0x8(%rsp),%rax
 109bc96:	mov    0x20(%rax,%r13,1),%rdi
 109bc9b:	mov    0x108(%rsp),%rsi
 109bca3:	call   1044580 <myl_core_str_eq>
 109bca8:	test   %al,%al
 109bcaa:	jne    109bcec <my.diagram_membership::compute_sub_block_attachments+0x1f0c>
 109bcac:	blsr   %ebp,%ebp
 109bcb1:	jne    109bc80 <my.diagram_membership::compute_sub_block_attachments+0x1ea0>
 109bcb3:	jmp    109b9b0 <my.diagram_membership::compute_sub_block_attachments+0x1bd0>
 109bcb8:	nopl   0x0(%rax,%rax,1)
 109bcc0:	cmpq   $0x0,0x18(%rcx)
 109bcc5:	je     109bd2c <my.diagram_membership::compute_sub_block_attachments+0x1f4c>
 109bcc7:	mov    0x8(%rsp),%rdi
 109bccc:	lea    0x108(%rsp),%rsi
 109bcd4:	mov    %r14,%rdx
 109bcd7:	call   1042bc0 <myl_core_dict_find>
 109bcdc:	mov    %rax,%r13
 109bcdf:	test   %r13,%r13
 109bce2:	js     109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109bce8:	shl    $0x4,%r13
 109bcec:	mov    0x8(%rsp),%rax
 109bcf1:	mov    0x28(%rax,%r13,1),%r14
 109bcf6:	cmpq   $0x1,0x8(%r14)
 109bcfb:	jne    109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109bd01:	mov    %r14,%rdi
 109bd04:	xor    %esi,%esi
 109bd06:	call   1043c40 <myl_core_dict_ordinal>
 109bd0b:	mov    0x20(%r14,%rax,8),%rdi
 109bd10:	mov    %rdi,0x100(%rsp)
 109bd18:	testb  $0x2,0x1(%rdi)
 109bd1c:	jne    109bdb0 <my.diagram_membership::compute_sub_block_attachments+0x1fd0>
 109bd22:	call   1044400 <myl_core_str_hash>
 109bd27:	jmp    109bdb3 <my.diagram_membership::compute_sub_block_attachments+0x1fd3>
 109bd2c:	mov    0x20(%rcx),%rbx
 109bd30:	test   %rbx,%rbx
 109bd33:	je     109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109bd39:	mov    0x10(%rcx),%r15
 109bd3d:	mov    0xe8(%rsp),%r12
 109bd45:	xor    %r13d,%r13d
 109bd48:	jmp    109bd90 <my.diagram_membership::compute_sub_block_attachments+0x1fb0>
 109bd4a:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bd59:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bd68:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bd77:	nopw   0x0(%rax,%rax,1)
 109bd80:	inc    %r13
 109bd83:	add    $0x10,%r12
 109bd87:	cmp    %r13,%rbx
 109bd8a:	je     109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109bd90:	cmp    %r14,(%r15,%r13,8)
 109bd94:	jne    109bd80 <my.diagram_membership::compute_sub_block_attachments+0x1fa0>
 109bd96:	mov    (%r12),%rdi
 109bd9a:	mov    0x108(%rsp),%rsi
 109bda2:	call   1044580 <myl_core_str_eq>
 109bda7:	test   %al,%al
 109bda9:	je     109bd80 <my.diagram_membership::compute_sub_block_attachments+0x1fa0>
 109bdab:	jmp    109bcdf <my.diagram_membership::compute_sub_block_attachments+0x1eff>
 109bdb0:	mov    0x18(%rdi),%eax
 109bdb3:	mov    %eax,%eax
 109bdb5:	movabs $0x9e3779b97f4a7c15,%rcx
 109bdbf:	imul   %rcx,%rax
 109bdc3:	mov    %rax,%r14
 109bdc6:	shr    $0x20,%r14
 109bdca:	xor    %rax,%r14
 109bdcd:	mov    0x20(%rsp),%rax
 109bdd2:	mov    0x18(%rax),%rcx
 109bdd6:	mov    0x8(%rcx),%rax
 109bdda:	test   %rax,%rax
 109bddd:	je     109be8f <my.diagram_membership::compute_sub_block_attachments+0x20af>
 109bde3:	mov    (%rax),%ecx
 109bde5:	tzcnt  %ecx,%edx
 109bde9:	neg    %dl
 109bdeb:	shrx   %rdx,%r14,%rbx
 109bdf0:	vmovdqu 0x10(%rax,%rbx,1),%xmm1
 109bdf6:	mov    %r14d,%edx
 109bdf9:	and    $0x7f,%dl
 109bdfc:	vmovd  %edx,%xmm0
 109be00:	vpbroadcastb %xmm0,%xmm0
 109be05:	vmovdqa %xmm1,0x50(%rsp)
 109be0b:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109be0f:	vpmovmskb %xmm0,%edx
 109be13:	test   %edx,%edx
 109be15:	je     109be73 <my.diagram_membership::compute_sub_block_attachments+0x2093>
 109be17:	lea    -0x1(%rcx),%r15d
 109be1b:	add    $0x1e,%ecx
 109be1e:	and    $0xfffffff0,%ecx
 109be21:	lea    (%rax,%rcx,1),%r12
 109be25:	add    $0x10,%r12
 109be29:	movzwl %dx,%ebp
 109be2c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109be3b:	nopl   0x0(%rax,%rax,1)
 109be40:	tzcnt  %ebp,%eax
 109be44:	add    %ebx,%eax
 109be46:	and    %r15d,%eax
 109be49:	mov    (%r12,%rax,4),%r13d
 109be4d:	shl    $0x4,%r13
 109be51:	mov    0x20(%rsp),%rax
 109be56:	mov    0x20(%rax,%r13,1),%rdi
 109be5b:	mov    0x100(%rsp),%rsi
 109be63:	call   1044580 <myl_core_str_eq>
 109be68:	test   %al,%al
 109be6a:	jne    109bebf <my.diagram_membership::compute_sub_block_attachments+0x20df>
 109be6c:	blsr   %ebp,%ebp
 109be71:	jne    109be40 <my.diagram_membership::compute_sub_block_attachments+0x2060>
 109be73:	vmovdqa 0x50(%rsp),%xmm0
 109be79:	vpcmpeqb -0x97ab1(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109be81:	vpmovmskb %xmm0,%eax
 109be85:	test   %eax,%eax
 109be87:	jne    109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109be8d:	jmp    109be9a <my.diagram_membership::compute_sub_block_attachments+0x20ba>
 109be8f:	cmpq   $0x0,0x18(%rcx)
 109be94:	je     109bf1c <my.diagram_membership::compute_sub_block_attachments+0x213c>
 109be9a:	mov    0x20(%rsp),%rdi
 109be9f:	lea    0x100(%rsp),%rsi
 109bea7:	mov    %r14,%rdx
 109beaa:	call   1042bc0 <myl_core_dict_find>
 109beaf:	mov    %rax,%r13
 109beb2:	test   %r13,%r13
 109beb5:	js     109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109bebb:	shl    $0x4,%r13
 109bebf:	mov    0x20(%rsp),%rax
 109bec4:	mov    0x28(%rax,%r13,1),%rsi
 109bec9:	mov    %rsi,%rax
 109becc:	imul   0x78(%rsp),%rax
 109bed2:	jo     109daf9 <my.diagram_membership::compute_sub_block_attachments+0x3d19>
 109bed8:	mov    %rax,%rsi
 109bedb:	mov    0xd8(%rsp),%rdx
 109bee3:	add    %rdx,%rsi
 109bee6:	mov    0xa8(%rsp),%rdi
 109beee:	jo     109db23 <my.diagram_membership::compute_sub_block_attachments+0x3d43>
 109bef4:	mov    0x8(%rdi),%rdx
 109bef8:	cmp    %rdx,%rsi
 109befb:	jae    109db0a <my.diagram_membership::compute_sub_block_attachments+0x3d2a>
 109bf01:	mov    0x20(%rdi,%rsi,8),%rax
 109bf06:	mov    %rax,%rcx
 109bf09:	inc    %rcx
 109bf0c:	jo     109dae5 <my.diagram_membership::compute_sub_block_attachments+0x3d05>
 109bf12:	mov    %rcx,0x20(%rdi,%rsi,8)
 109bf17:	jmp    109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109bf1c:	mov    0x20(%rcx),%rbx
 109bf20:	test   %rbx,%rbx
 109bf23:	je     109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109bf29:	mov    0x10(%rcx),%r15
 109bf2d:	mov    0x158(%rsp),%r12
 109bf35:	xor    %r13d,%r13d
 109bf38:	jmp    109bf50 <my.diagram_membership::compute_sub_block_attachments+0x2170>
 109bf3a:	nopw   0x0(%rax,%rax,1)
 109bf40:	inc    %r13
 109bf43:	add    $0x10,%r12
 109bf47:	cmp    %r13,%rbx
 109bf4a:	je     109b9d0 <my.diagram_membership::compute_sub_block_attachments+0x1bf0>
 109bf50:	cmp    %r14,(%r15,%r13,8)
 109bf54:	jne    109bf40 <my.diagram_membership::compute_sub_block_attachments+0x2160>
 109bf56:	mov    (%r12),%rdi
 109bf5a:	mov    0x100(%rsp),%rsi
 109bf62:	call   1044580 <myl_core_str_eq>
 109bf67:	test   %al,%al
 109bf69:	je     109bf40 <my.diagram_membership::compute_sub_block_attachments+0x2160>
 109bf6b:	jmp    109beb2 <my.diagram_membership::compute_sub_block_attachments+0x20d2>
 109bf70:	mov    0x8(%rsp),%rdi
 109bf75:	call   103c740 <myl_core_drop_owned>
 109bf7a:	mov    0x20(%rsp),%rdi
 109bf7f:	call   103c740 <myl_core_drop_owned>
 109bf84:	mov    0x60(%rsp),%rdi
 109bf89:	call   103c740 <myl_core_drop_owned>
 109bf8e:	cmpq   $0x0,0xc8(%rsp)
 109bf97:	mov    0xa8(%rsp),%r14
 109bf9f:	je     109d9a1 <my.diagram_membership::compute_sub_block_attachments+0x3bc1>
 109bfa5:	addq   $0x20,0xa0(%rsp)
 109bfae:	addq   $0x20,0x70(%rsp)
 109bfb4:	mov    0xc0(%rsp),%rax
 109bfbc:	add    $0x20,%rax
 109bfc0:	mov    %rax,0xd0(%rsp)
 109bfc8:	mov    0x28(%rsp),%rax
 109bfcd:	add    $0x20,%rax
 109bfd1:	mov    %rax,0xe8(%rsp)
 109bfd9:	xor    %esi,%esi
 109bfdb:	jmp    109bff1 <my.diagram_membership::compute_sub_block_attachments+0x2211>
 109bfdd:	nopl   (%rax)
 109bfe0:	inc    %rsi
 109bfe3:	cmp    0xc8(%rsp),%rsi
 109bfeb:	je     109d9a1 <my.diagram_membership::compute_sub_block_attachments+0x3bc1>
 109bff1:	mov    %rsi,0x98(%rsp)
 109bff9:	imul   $0x428,%rsi,%rax
 109c000:	mov    0xa0(%rsp),%rcx
 109c008:	mov    (%rcx,%rax,1),%rbx
 109c00c:	mov    %rbx,%rdi
 109c00f:	call   104ba40 <myl_core_bytes_utf8_count>
 109c014:	test   %rax,%rax
 109c017:	js     109d970 <my.diagram_membership::compute_sub_block_attachments+0x3b90>
 109c01d:	mov    %rbx,%rdi
 109c020:	call   104bb00 <myl_core_bytes_decode_text>
 109c025:	mov    %rax,%rbp
 109c028:	xor    %eax,%eax
 109c02a:	test   %al,%al
 109c02c:	jne    109d98d <my.diagram_membership::compute_sub_block_attachments+0x3bad>
 109c032:	mov    %rbp,0xf8(%rsp)
 109c03a:	testb  $0x2,0x1(%rbp)
 109c03e:	jne    109c050 <my.diagram_membership::compute_sub_block_attachments+0x2270>
 109c040:	mov    %rbp,%rdi
 109c043:	call   1044400 <myl_core_str_hash>
 109c048:	jmp    109c053 <my.diagram_membership::compute_sub_block_attachments+0x2273>
 109c04a:	nopw   0x0(%rax,%rax,1)
 109c050:	mov    0x18(%rbp),%eax
 109c053:	mov    %eax,%eax
 109c055:	movabs $0x9e3779b97f4a7c15,%rcx
 109c05f:	imul   %rcx,%rax
 109c063:	mov    %rax,%r14
 109c066:	shr    $0x20,%r14
 109c06a:	xor    %rax,%r14
 109c06d:	mov    0x28(%rsp),%rax
 109c072:	mov    0x18(%rax),%rcx
 109c076:	mov    0x8(%rcx),%rax
 109c07a:	test   %rax,%rax
 109c07d:	je     109c170 <my.diagram_membership::compute_sub_block_attachments+0x2390>
 109c083:	mov    %rbp,0x10(%rsp)
 109c088:	mov    (%rax),%ecx
 109c08a:	tzcnt  %ecx,%edx
 109c08e:	neg    %dl
 109c090:	shrx   %rdx,%r14,%r12
 109c095:	vmovdqu 0x10(%rax,%r12,1),%xmm1
 109c09c:	mov    %r14d,%edx
 109c09f:	and    $0x7f,%dl
 109c0a2:	vmovd  %edx,%xmm0
 109c0a6:	vpbroadcastb %xmm0,%xmm0
 109c0ab:	vmovdqa %xmm1,0x30(%rsp)
 109c0b1:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109c0b5:	vpmovmskb %xmm0,%edx
 109c0b9:	test   %edx,%edx
 109c0bb:	je     109c13b <my.diagram_membership::compute_sub_block_attachments+0x235b>
 109c0bd:	lea    -0x1(%rcx),%ebp
 109c0c0:	add    $0x1e,%ecx
 109c0c3:	and    $0xfffffff0,%ecx
 109c0c6:	lea    (%rax,%rcx,1),%r13
 109c0ca:	add    $0x10,%r13
 109c0ce:	movzwl %dx,%ebx
 109c0d1:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109c0e0:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109c0ef:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109c0fe:	xchg   %ax,%ax
 109c100:	tzcnt  %ebx,%eax
 109c104:	add    %r12d,%eax
 109c107:	and    %ebp,%eax
 109c109:	mov    0x0(%r13,%rax,4),%r15d
 109c10e:	mov    %r15,%rax
 109c111:	shl    $0x4,%rax
 109c115:	mov    0x28(%rsp),%rcx
 109c11a:	mov    0x20(%rcx,%rax,1),%rdi
 109c11f:	mov    0xf8(%rsp),%rsi
 109c127:	call   1044580 <myl_core_str_eq>
 109c12c:	test   %al,%al
 109c12e:	jne    109d8a6 <my.diagram_membership::compute_sub_block_attachments+0x3ac6>
 109c134:	blsr   %ebx,%ebx
 109c139:	jne    109c100 <my.diagram_membership::compute_sub_block_attachments+0x2320>
 109c13b:	vmovdqa 0x30(%rsp),%xmm0
 109c141:	vpcmpeqb -0x97d79(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109c149:	vpmovmskb %xmm0,%eax
 109c14d:	test   %eax,%eax
 109c14f:	mov    0x10(%rsp),%rbp
 109c154:	je     109c17b <my.diagram_membership::compute_sub_block_attachments+0x239b>
 109c156:	mov    %rbp,%rdi
 109c159:	call   103c740 <myl_core_drop_owned>
 109c15e:	mov    0xa8(%rsp),%r14
 109c166:	jmp    109c1ac <my.diagram_membership::compute_sub_block_attachments+0x23cc>
 109c168:	nopl   0x0(%rax,%rax,1)
 109c170:	cmpq   $0x0,0x18(%rcx)
 109c175:	je     109d904 <my.diagram_membership::compute_sub_block_attachments+0x3b24>
 109c17b:	mov    0x28(%rsp),%rdi
 109c180:	lea    0xf8(%rsp),%rsi
 109c188:	mov    %r14,%rdx
 109c18b:	call   1042bc0 <myl_core_dict_find>
 109c190:	mov    %rax,%r15
 109c193:	mov    %rbp,%rdi
 109c196:	call   103c740 <myl_core_drop_owned>
 109c19b:	test   %r15,%r15
 109c19e:	mov    0xa8(%rsp),%r14
 109c1a6:	jns    109d8b8 <my.diagram_membership::compute_sub_block_attachments+0x3ad8>
 109c1ac:	cmpq   $0x0,0x78(%rsp)
 109c1b2:	mov    0x98(%rsp),%rsi
 109c1ba:	je     109bfe0 <my.diagram_membership::compute_sub_block_attachments+0x2200>
 109c1c0:	mov    0x78(%rsp),%rax
 109c1c5:	imul   %rax,%rsi
 109c1c9:	mov    %rsi,0xe0(%rsp)
 109c1d1:	jo     109db52 <my.diagram_membership::compute_sub_block_attachments+0x3d72>
 109c1d7:	mov    $0x1,%r8b
 109c1da:	xor    %ecx,%ecx
 109c1dc:	xor    %r10d,%r10d
 109c1df:	xor    %edi,%edi
 109c1e1:	xor    %r9d,%r9d
 109c1e4:	jmp    109c23d <my.diagram_membership::compute_sub_block_attachments+0x245d>
 109c1e6:	cs nopw 0x0(%rax,%rax,1)
 109c1f0:	cmp    $0x4,%bl
 109c1f3:	sete   %cl
 109c1f6:	cmp    %r10,%r11
 109c1f9:	setg   %al
 109c1fc:	sete   %dl
 109c1ff:	and    %r8b,%dl
 109c202:	movzbl %cl,%esi
 109c205:	xor    $0x1,%cl
 109c208:	and    %dl,%cl
 109c20a:	or     %al,%cl
 109c20c:	cmovne %r11,%r10
 109c210:	movzbl %r8b,%r8d
 109c214:	cmovne %esi,%r8d
 109c218:	cmovne %r9,%rdi
 109c21c:	mov    0x50(%rsp),%rcx
 109c221:	movzbl %cl,%ecx
 109c224:	mov    $0x1,%eax
 109c229:	cmovne %eax,%ecx
 109c22c:	mov    0x78(%rsp),%rax
 109c231:	inc    %r9
 109c234:	cmp    %rax,%r9
 109c237:	je     109d860 <my.diagram_membership::compute_sub_block_attachments+0x3a80>
 109c23d:	mov    0xe0(%rsp),%rsi
 109c245:	add    %r9,%rsi
 109c248:	jo     109da6d <my.diagram_membership::compute_sub_block_attachments+0x3c8d>
 109c24e:	mov    0x8(%r14),%rdx
 109c252:	cmp    %rdx,%rsi
 109c255:	jae    109da84 <my.diagram_membership::compute_sub_block_attachments+0x3ca4>
 109c25b:	mov    0x20(%r14,%rsi,8),%rdx
 109c260:	test   %rdx,%rdx
 109c263:	jle    109c231 <my.diagram_membership::compute_sub_block_attachments+0x2451>
 109c265:	mov    %rdx,0xb0(%rsp)
 109c26d:	mov    %r10,0x8(%rsp)
 109c272:	mov    %r8d,0x48(%rsp)
 109c277:	mov    %rdi,0x80(%rsp)
 109c27f:	mov    %rcx,0x50(%rsp)
 109c284:	mov    %r9,0x60(%rsp)
 109c289:	imul   $0x70,%r9,%rax
 109c28d:	mov    0x70(%rsp),%rcx
 109c292:	mov    (%rcx,%rax,1),%rbp
 109c296:	mov    0x20(%rcx,%rax,1),%rbx
 109c29b:	mov    %fs:0xfffffffffffffef0,%r14
 109c2a4:	test   %r14,%r14
 109c2a7:	lea    -0x71156(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109c2ae:	je     109cef7 <my.diagram_membership::compute_sub_block_attachments+0x3117>
 109c2b4:	mov    (%r14),%rax
 109c2b7:	mov    %rax,%fs:0xfffffffffffffef0
 109c2c0:	movl   $0x6000000,(%r14)
 109c2c7:	movq   $0x0,0x8(%r14)
 109c2cf:	movq   $0xa,0x10(%r14)
 109c2d7:	movq   $0x0,0x18(%r14)
 109c2df:	lea    -0x70216(%rip),%rax        # 102c0d0 <core_number_pairs+0x24b80>
 109c2e6:	mov    %rax,0x18(%r14)
 109c2ea:	mov    %fs:0xfffffffffffffed8,%rax
 109c2f3:	test   %rax,%rax
 109c2f6:	mov    %rbx,0xd8(%rsp)
 109c2fe:	je     109cf15 <my.diagram_membership::compute_sub_block_attachments+0x3135>
 109c304:	mov    (%rax),%rcx
 109c307:	mov    %rcx,%fs:0xfffffffffffffed8
 109c310:	movl   $0x3000000,(%rax)
 109c316:	movq   $0x0,0x8(%rax)
 109c31e:	movq   $0x8,0x10(%rax)
 109c326:	mov    %rsi,0x18(%rax)
 109c32a:	mov    $0x8,%edx
 109c32f:	xor    %ecx,%ecx
 109c331:	lea    -0x7b6d8(%rip),%rdi        # 1020c60 <core_number_pairs+0x19710>
 109c338:	mov    %rdi,0x20(%rax,%rcx,8)
 109c33d:	inc    %rcx
 109c340:	mov    %rcx,0x8(%rax)
 109c344:	cmp    %rdx,%rcx
 109c347:	jae    109cf59 <my.diagram_membership::compute_sub_block_attachments+0x3179>
 109c34d:	lea    -0x7b6b4(%rip),%rdi        # 1020ca0 <core_number_pairs+0x19750>
 109c354:	mov    %rdi,0x20(%rax,%rcx,8)
 109c359:	inc    %rcx
 109c35c:	mov    %rcx,0x8(%rax)
 109c360:	cmp    %rdx,%rcx
 109c363:	jae    109cf7a <my.diagram_membership::compute_sub_block_attachments+0x319a>
 109c369:	lea    -0x7b690(%rip),%rdi        # 1020ce0 <core_number_pairs+0x19790>
 109c370:	mov    %rdi,0x20(%rax,%rcx,8)
 109c375:	inc    %rcx
 109c378:	mov    %rcx,0x8(%rax)
 109c37c:	cmp    %rdx,%rcx
 109c37f:	jae    109cf9b <my.diagram_membership::compute_sub_block_attachments+0x31bb>
 109c385:	lea    -0x7b66c(%rip),%rdi        # 1020d20 <core_number_pairs+0x197d0>
 109c38c:	mov    %rdi,0x20(%rax,%rcx,8)
 109c391:	inc    %rcx
 109c394:	mov    %rcx,0x8(%rax)
 109c398:	cmp    %rdx,%rcx
 109c39b:	jae    109cfbc <my.diagram_membership::compute_sub_block_attachments+0x31dc>
 109c3a1:	lea    -0x7b648(%rip),%rdi        # 1020d60 <core_number_pairs+0x19810>
 109c3a8:	mov    %rdi,0x20(%rax,%rcx,8)
 109c3ad:	inc    %rcx
 109c3b0:	mov    %rcx,0x8(%rax)
 109c3b4:	cmp    %rdx,%rcx
 109c3b7:	jae    109cfdd <my.diagram_membership::compute_sub_block_attachments+0x31fd>
 109c3bd:	lea    -0x7b624(%rip),%rdi        # 1020da0 <core_number_pairs+0x19850>
 109c3c4:	mov    %rdi,0x20(%rax,%rcx,8)
 109c3c9:	inc    %rcx
 109c3cc:	mov    %rcx,0x8(%rax)
 109c3d0:	cmp    %rdx,%rcx
 109c3d3:	jae    109cffe <my.diagram_membership::compute_sub_block_attachments+0x321e>
 109c3d9:	lea    -0x7b600(%rip),%rdi        # 1020de0 <core_number_pairs+0x19890>
 109c3e0:	mov    %rdi,0x20(%rax,%rcx,8)
 109c3e5:	inc    %rcx
 109c3e8:	mov    %rcx,0x8(%rax)
 109c3ec:	cmp    %rdx,%rcx
 109c3ef:	jae    109d01f <my.diagram_membership::compute_sub_block_attachments+0x323f>
 109c3f5:	lea    -0x7b5dc(%rip),%rdx        # 1020e20 <core_number_pairs+0x198d0>
 109c3fc:	mov    %rdx,0x20(%rax,%rcx,8)
 109c401:	inc    %rcx
 109c404:	mov    %rcx,0x8(%rax)
 109c408:	mov    0x8(%r14),%rcx
 109c40c:	cmp    0x10(%r14),%rcx
 109c410:	jae    109d03c <my.diagram_membership::compute_sub_block_attachments+0x325c>
 109c416:	mov    %rcx,%rdx
 109c419:	shl    $0x4,%rdx
 109c41d:	movq   $0x0,0x20(%r14,%rdx,1)
 109c426:	mov    %rax,0x28(%r14,%rdx,1)
 109c42b:	inc    %rcx
 109c42e:	mov    %rcx,0x8(%r14)
 109c432:	mov    %fs:0xfffffffffffffed8,%rax
 109c43b:	test   %rax,%rax
 109c43e:	je     109d062 <my.diagram_membership::compute_sub_block_attachments+0x3282>
 109c444:	mov    (%rax),%rcx
 109c447:	mov    %rcx,%fs:0xfffffffffffffed8
 109c450:	movl   $0x3000000,(%rax)
 109c456:	movq   $0x0,0x8(%rax)
 109c45e:	movq   $0x8,0x10(%rax)
 109c466:	mov    %rsi,0x18(%rax)
 109c46a:	mov    $0x8,%edx
 109c46f:	xor    %ecx,%ecx
 109c471:	lea    -0x7b618(%rip),%rdi        # 1020e60 <core_number_pairs+0x19910>
 109c478:	mov    %rdi,0x20(%rax,%rcx,8)
 109c47d:	inc    %rcx
 109c480:	mov    %rcx,0x8(%rax)
 109c484:	cmp    %rdx,%rcx
 109c487:	jae    109d0a6 <my.diagram_membership::compute_sub_block_attachments+0x32c6>
 109c48d:	lea    -0x7b5f4(%rip),%rdi        # 1020ea0 <core_number_pairs+0x19950>
 109c494:	mov    %rdi,0x20(%rax,%rcx,8)
 109c499:	inc    %rcx
 109c49c:	mov    %rcx,0x8(%rax)
 109c4a0:	cmp    %rdx,%rcx
 109c4a3:	jae    109d0c7 <my.diagram_membership::compute_sub_block_attachments+0x32e7>
 109c4a9:	lea    -0x7b5d0(%rip),%rdi        # 1020ee0 <core_number_pairs+0x19990>
 109c4b0:	mov    %rdi,0x20(%rax,%rcx,8)
 109c4b5:	inc    %rcx
 109c4b8:	mov    %rcx,0x8(%rax)
 109c4bc:	cmp    %rdx,%rcx
 109c4bf:	jae    109d0e8 <my.diagram_membership::compute_sub_block_attachments+0x3308>
 109c4c5:	lea    -0x7b5ac(%rip),%rdi        # 1020f20 <core_number_pairs+0x199d0>
 109c4cc:	mov    %rdi,0x20(%rax,%rcx,8)
 109c4d1:	inc    %rcx
 109c4d4:	mov    %rcx,0x8(%rax)
 109c4d8:	cmp    %rdx,%rcx
 109c4db:	jae    109d109 <my.diagram_membership::compute_sub_block_attachments+0x3329>
 109c4e1:	lea    -0x7b588(%rip),%rdi        # 1020f60 <core_number_pairs+0x19a10>
 109c4e8:	mov    %rdi,0x20(%rax,%rcx,8)
 109c4ed:	inc    %rcx
 109c4f0:	mov    %rcx,0x8(%rax)
 109c4f4:	cmp    %rdx,%rcx
 109c4f7:	jae    109d12a <my.diagram_membership::compute_sub_block_attachments+0x334a>
 109c4fd:	lea    -0x7b564(%rip),%rdi        # 1020fa0 <core_number_pairs+0x19a50>
 109c504:	mov    %rdi,0x20(%rax,%rcx,8)
 109c509:	inc    %rcx
 109c50c:	mov    %rcx,0x8(%rax)
 109c510:	cmp    %rdx,%rcx
 109c513:	jae    109d14b <my.diagram_membership::compute_sub_block_attachments+0x336b>
 109c519:	lea    -0x7b540(%rip),%rdx        # 1020fe0 <core_number_pairs+0x19a90>
 109c520:	mov    %rdx,0x20(%rax,%rcx,8)
 109c525:	inc    %rcx
 109c528:	mov    %rcx,0x8(%rax)
 109c52c:	mov    0x8(%r14),%rcx
 109c530:	cmp    0x10(%r14),%rcx
 109c534:	jae    109d168 <my.diagram_membership::compute_sub_block_attachments+0x3388>
 109c53a:	mov    %rcx,%rdx
 109c53d:	shl    $0x4,%rdx
 109c541:	movq   $0x1,0x20(%r14,%rdx,1)
 109c54a:	mov    %rax,0x28(%r14,%rdx,1)
 109c54f:	inc    %rcx
 109c552:	mov    %rcx,0x8(%r14)
 109c556:	mov    %fs:0xfffffffffffffed8,%rax
 109c55f:	test   %rax,%rax
 109c562:	je     109d18e <my.diagram_membership::compute_sub_block_attachments+0x33ae>
 109c568:	mov    (%rax),%rcx
 109c56b:	mov    %rcx,%fs:0xfffffffffffffed8
 109c574:	movl   $0x3000000,(%rax)
 109c57a:	movq   $0x0,0x8(%rax)
 109c582:	movq   $0x8,0x10(%rax)
 109c58a:	mov    %rsi,0x18(%rax)
 109c58e:	mov    $0x8,%edx
 109c593:	xor    %ecx,%ecx
 109c595:	lea    -0x7b57c(%rip),%rdi        # 1021020 <core_number_pairs+0x19ad0>
 109c59c:	mov    %rdi,0x20(%rax,%rcx,8)
 109c5a1:	inc    %rcx
 109c5a4:	mov    %rcx,0x8(%rax)
 109c5a8:	cmp    %rdx,%rcx
 109c5ab:	jae    109d1d2 <my.diagram_membership::compute_sub_block_attachments+0x33f2>
 109c5b1:	lea    -0x7b558(%rip),%rdi        # 1021060 <core_number_pairs+0x19b10>
 109c5b8:	mov    %rdi,0x20(%rax,%rcx,8)
 109c5bd:	inc    %rcx
 109c5c0:	mov    %rcx,0x8(%rax)
 109c5c4:	cmp    %rdx,%rcx
 109c5c7:	jae    109d1f3 <my.diagram_membership::compute_sub_block_attachments+0x3413>
 109c5cd:	lea    -0x7b534(%rip),%rdi        # 10210a0 <core_number_pairs+0x19b50>
 109c5d4:	mov    %rdi,0x20(%rax,%rcx,8)
 109c5d9:	inc    %rcx
 109c5dc:	mov    %rcx,0x8(%rax)
 109c5e0:	cmp    %rdx,%rcx
 109c5e3:	jae    109d214 <my.diagram_membership::compute_sub_block_attachments+0x3434>
 109c5e9:	lea    -0x7b510(%rip),%rdi        # 10210e0 <core_number_pairs+0x19b90>
 109c5f0:	mov    %rdi,0x20(%rax,%rcx,8)
 109c5f5:	inc    %rcx
 109c5f8:	mov    %rcx,0x8(%rax)
 109c5fc:	cmp    %rdx,%rcx
 109c5ff:	jae    109d235 <my.diagram_membership::compute_sub_block_attachments+0x3455>
 109c605:	lea    -0x7b4ec(%rip),%rdx        # 1021120 <core_number_pairs+0x19bd0>
 109c60c:	mov    %rdx,0x20(%rax,%rcx,8)
 109c611:	inc    %rcx
 109c614:	mov    %rcx,0x8(%rax)
 109c618:	mov    0x8(%r14),%rcx
 109c61c:	cmp    0x10(%r14),%rcx
 109c620:	jae    109d252 <my.diagram_membership::compute_sub_block_attachments+0x3472>
 109c626:	mov    %rcx,%rdx
 109c629:	shl    $0x4,%rdx
 109c62d:	movq   $0x2,0x20(%r14,%rdx,1)
 109c636:	mov    %rax,0x28(%r14,%rdx,1)
 109c63b:	inc    %rcx
 109c63e:	mov    %rcx,0x8(%r14)
 109c642:	mov    %fs:0xfffffffffffffed8,%rax
 109c64b:	test   %rax,%rax
 109c64e:	je     109d278 <my.diagram_membership::compute_sub_block_attachments+0x3498>
 109c654:	mov    (%rax),%rcx
 109c657:	mov    %rcx,%fs:0xfffffffffffffed8
 109c660:	movl   $0x3000000,(%rax)
 109c666:	movq   $0x0,0x8(%rax)
 109c66e:	movq   $0x8,0x10(%rax)
 109c676:	mov    %rsi,0x18(%rax)
 109c67a:	mov    $0x8,%edx
 109c67f:	xor    %ecx,%ecx
 109c681:	lea    -0x7b528(%rip),%rdi        # 1021160 <core_number_pairs+0x19c10>
 109c688:	mov    %rdi,0x20(%rax,%rcx,8)
 109c68d:	inc    %rcx
 109c690:	mov    %rcx,0x8(%rax)
 109c694:	cmp    %rdx,%rcx
 109c697:	jae    109d2bc <my.diagram_membership::compute_sub_block_attachments+0x34dc>
 109c69d:	lea    -0x7b504(%rip),%rdi        # 10211a0 <core_number_pairs+0x19c50>
 109c6a4:	mov    %rdi,0x20(%rax,%rcx,8)
 109c6a9:	inc    %rcx
 109c6ac:	mov    %rcx,0x8(%rax)
 109c6b0:	cmp    %rdx,%rcx
 109c6b3:	jae    109d2dd <my.diagram_membership::compute_sub_block_attachments+0x34fd>
 109c6b9:	lea    -0x7b4e0(%rip),%rdi        # 10211e0 <core_number_pairs+0x19c90>
 109c6c0:	mov    %rdi,0x20(%rax,%rcx,8)
 109c6c5:	inc    %rcx
 109c6c8:	mov    %rcx,0x8(%rax)
 109c6cc:	cmp    %rdx,%rcx
 109c6cf:	jae    109d2fe <my.diagram_membership::compute_sub_block_attachments+0x351e>
 109c6d5:	lea    -0x7b4bc(%rip),%rdi        # 1021220 <core_number_pairs+0x19cd0>
 109c6dc:	mov    %rdi,0x20(%rax,%rcx,8)
 109c6e1:	inc    %rcx
 109c6e4:	mov    %rcx,0x8(%rax)
 109c6e8:	cmp    %rdx,%rcx
 109c6eb:	jae    109d31f <my.diagram_membership::compute_sub_block_attachments+0x353f>
 109c6f1:	lea    -0x7b498(%rip),%rdi        # 1021260 <core_number_pairs+0x19d10>
 109c6f8:	mov    %rdi,0x20(%rax,%rcx,8)
 109c6fd:	inc    %rcx
 109c700:	mov    %rcx,0x8(%rax)
 109c704:	cmp    %rdx,%rcx
 109c707:	jae    109d340 <my.diagram_membership::compute_sub_block_attachments+0x3560>
 109c70d:	lea    -0x7b474(%rip),%rdx        # 10212a0 <core_number_pairs+0x19d50>
 109c714:	mov    %rdx,0x20(%rax,%rcx,8)
 109c719:	inc    %rcx
 109c71c:	mov    %rcx,0x8(%rax)
 109c720:	mov    0x8(%r14),%rcx
 109c724:	cmp    0x10(%r14),%rcx
 109c728:	jae    109d35d <my.diagram_membership::compute_sub_block_attachments+0x357d>
 109c72e:	mov    %rcx,%rdx
 109c731:	shl    $0x4,%rdx
 109c735:	movq   $0x5,0x20(%r14,%rdx,1)
 109c73e:	mov    %rax,0x28(%r14,%rdx,1)
 109c743:	inc    %rcx
 109c746:	mov    %rcx,0x8(%r14)
 109c74a:	mov    %fs:0xfffffffffffffed8,%rax
 109c753:	test   %rax,%rax
 109c756:	je     109d383 <my.diagram_membership::compute_sub_block_attachments+0x35a3>
 109c75c:	mov    (%rax),%rcx
 109c75f:	mov    %rcx,%fs:0xfffffffffffffed8
 109c768:	movl   $0x3000000,(%rax)
 109c76e:	movq   $0x0,0x8(%rax)
 109c776:	movq   $0x8,0x10(%rax)
 109c77e:	mov    %rsi,0x18(%rax)
 109c782:	mov    $0x8,%edx
 109c787:	xor    %ecx,%ecx
 109c789:	lea    -0x7b4b0(%rip),%rdi        # 10212e0 <core_number_pairs+0x19d90>
 109c790:	mov    %rdi,0x20(%rax,%rcx,8)
 109c795:	inc    %rcx
 109c798:	mov    %rcx,0x8(%rax)
 109c79c:	cmp    %rdx,%rcx
 109c79f:	jae    109d3c7 <my.diagram_membership::compute_sub_block_attachments+0x35e7>
 109c7a5:	lea    -0x7b48c(%rip),%rdi        # 1021320 <core_number_pairs+0x19dd0>
 109c7ac:	mov    %rdi,0x20(%rax,%rcx,8)
 109c7b1:	inc    %rcx
 109c7b4:	mov    %rcx,0x8(%rax)
 109c7b8:	cmp    %rdx,%rcx
 109c7bb:	jae    109d3e8 <my.diagram_membership::compute_sub_block_attachments+0x3608>
 109c7c1:	lea    -0x7b468(%rip),%rdi        # 1021360 <core_number_pairs+0x19e10>
 109c7c8:	mov    %rdi,0x20(%rax,%rcx,8)
 109c7cd:	inc    %rcx
 109c7d0:	mov    %rcx,0x8(%rax)
 109c7d4:	cmp    %rdx,%rcx
 109c7d7:	jae    109d409 <my.diagram_membership::compute_sub_block_attachments+0x3629>
 109c7dd:	lea    -0x7b444(%rip),%rdi        # 10213a0 <core_number_pairs+0x19e50>
 109c7e4:	mov    %rdi,0x20(%rax,%rcx,8)
 109c7e9:	inc    %rcx
 109c7ec:	mov    %rcx,0x8(%rax)
 109c7f0:	cmp    %rdx,%rcx
 109c7f3:	jae    109d42a <my.diagram_membership::compute_sub_block_attachments+0x364a>
 109c7f9:	lea    -0x7b420(%rip),%rdi        # 10213e0 <core_number_pairs+0x19e90>
 109c800:	mov    %rdi,0x20(%rax,%rcx,8)
 109c805:	inc    %rcx
 109c808:	mov    %rcx,0x8(%rax)
 109c80c:	cmp    %rdx,%rcx
 109c80f:	jae    109d44b <my.diagram_membership::compute_sub_block_attachments+0x366b>
 109c815:	lea    -0x7b3fc(%rip),%rdx        # 1021420 <core_number_pairs+0x19ed0>
 109c81c:	mov    %rdx,0x20(%rax,%rcx,8)
 109c821:	inc    %rcx
 109c824:	mov    %rcx,0x8(%rax)
 109c828:	mov    0x8(%r14),%rcx
 109c82c:	cmp    0x10(%r14),%rcx
 109c830:	jae    109d468 <my.diagram_membership::compute_sub_block_attachments+0x3688>
 109c836:	mov    %rcx,%rdx
 109c839:	shl    $0x4,%rdx
 109c83d:	movq   $0x6,0x20(%r14,%rdx,1)
 109c846:	mov    %rax,0x28(%r14,%rdx,1)
 109c84b:	inc    %rcx
 109c84e:	mov    %rcx,0x8(%r14)
 109c852:	mov    %fs:0xfffffffffffffed8,%rax
 109c85b:	test   %rax,%rax
 109c85e:	je     109d48e <my.diagram_membership::compute_sub_block_attachments+0x36ae>
 109c864:	mov    (%rax),%rcx
 109c867:	mov    %rcx,%fs:0xfffffffffffffed8
 109c870:	movl   $0x3000000,(%rax)
 109c876:	movq   $0x0,0x8(%rax)
 109c87e:	movq   $0x8,0x10(%rax)
 109c886:	mov    %rsi,0x18(%rax)
 109c88a:	mov    $0x8,%edx
 109c88f:	xor    %ecx,%ecx
 109c891:	lea    -0x7b438(%rip),%rdi        # 1021460 <core_number_pairs+0x19f10>
 109c898:	mov    %rdi,0x20(%rax,%rcx,8)
 109c89d:	inc    %rcx
 109c8a0:	mov    %rcx,0x8(%rax)
 109c8a4:	cmp    %rdx,%rcx
 109c8a7:	jae    109d4d2 <my.diagram_membership::compute_sub_block_attachments+0x36f2>
 109c8ad:	lea    -0x7b414(%rip),%rdi        # 10214a0 <core_number_pairs+0x19f50>
 109c8b4:	mov    %rdi,0x20(%rax,%rcx,8)
 109c8b9:	inc    %rcx
 109c8bc:	mov    %rcx,0x8(%rax)
 109c8c0:	cmp    %rdx,%rcx
 109c8c3:	jae    109d4f3 <my.diagram_membership::compute_sub_block_attachments+0x3713>
 109c8c9:	lea    -0x7b3f0(%rip),%rdi        # 10214e0 <core_number_pairs+0x19f90>
 109c8d0:	mov    %rdi,0x20(%rax,%rcx,8)
 109c8d5:	inc    %rcx
 109c8d8:	mov    %rcx,0x8(%rax)
 109c8dc:	cmp    %rdx,%rcx
 109c8df:	jae    109d514 <my.diagram_membership::compute_sub_block_attachments+0x3734>
 109c8e5:	lea    -0x7b3cc(%rip),%rdi        # 1021520 <core_number_pairs+0x19fd0>
 109c8ec:	mov    %rdi,0x20(%rax,%rcx,8)
 109c8f1:	inc    %rcx
 109c8f4:	mov    %rcx,0x8(%rax)
 109c8f8:	cmp    %rdx,%rcx
 109c8fb:	jae    109d535 <my.diagram_membership::compute_sub_block_attachments+0x3755>
 109c901:	lea    -0x7b3a8(%rip),%rdi        # 1021560 <core_number_pairs+0x1a010>
 109c908:	mov    %rdi,0x20(%rax,%rcx,8)
 109c90d:	inc    %rcx
 109c910:	mov    %rcx,0x8(%rax)
 109c914:	cmp    %rdx,%rcx
 109c917:	jae    109d556 <my.diagram_membership::compute_sub_block_attachments+0x3776>
 109c91d:	lea    -0x7b384(%rip),%rdx        # 10215a0 <core_number_pairs+0x1a050>
 109c924:	mov    %rdx,0x20(%rax,%rcx,8)
 109c929:	inc    %rcx
 109c92c:	mov    %rcx,0x8(%rax)
 109c930:	mov    0x8(%r14),%rcx
 109c934:	cmp    0x10(%r14),%rcx
 109c938:	jae    109d573 <my.diagram_membership::compute_sub_block_attachments+0x3793>
 109c93e:	mov    %rcx,%rdx
 109c941:	shl    $0x4,%rdx
 109c945:	movq   $0x7,0x20(%r14,%rdx,1)
 109c94e:	mov    %rax,0x28(%r14,%rdx,1)
 109c953:	inc    %rcx
 109c956:	mov    %rcx,0x8(%r14)
 109c95a:	mov    %fs:0xfffffffffffffed8,%rax
 109c963:	test   %rax,%rax
 109c966:	je     109d599 <my.diagram_membership::compute_sub_block_attachments+0x37b9>
 109c96c:	mov    (%rax),%rcx
 109c96f:	mov    %rcx,%fs:0xfffffffffffffed8
 109c978:	movl   $0x3000000,(%rax)
 109c97e:	movq   $0x0,0x8(%rax)
 109c986:	movq   $0x8,0x10(%rax)
 109c98e:	mov    %rsi,0x18(%rax)
 109c992:	mov    $0x8,%edx
 109c997:	xor    %ecx,%ecx
 109c999:	lea    -0x7b3c0(%rip),%rdi        # 10215e0 <core_number_pairs+0x1a090>
 109c9a0:	mov    %rdi,0x20(%rax,%rcx,8)
 109c9a5:	inc    %rcx
 109c9a8:	mov    %rcx,0x8(%rax)
 109c9ac:	cmp    %rdx,%rcx
 109c9af:	jae    109d5dd <my.diagram_membership::compute_sub_block_attachments+0x37fd>
 109c9b5:	lea    -0x7b39c(%rip),%rdi        # 1021620 <core_number_pairs+0x1a0d0>
 109c9bc:	mov    %rdi,0x20(%rax,%rcx,8)
 109c9c1:	inc    %rcx
 109c9c4:	mov    %rcx,0x8(%rax)
 109c9c8:	cmp    %rdx,%rcx
 109c9cb:	jae    109d5fe <my.diagram_membership::compute_sub_block_attachments+0x381e>
 109c9d1:	lea    -0x7b378(%rip),%rdi        # 1021660 <core_number_pairs+0x1a110>
 109c9d8:	mov    %rdi,0x20(%rax,%rcx,8)
 109c9dd:	inc    %rcx
 109c9e0:	mov    %rcx,0x8(%rax)
 109c9e4:	cmp    %rdx,%rcx
 109c9e7:	jae    109d61f <my.diagram_membership::compute_sub_block_attachments+0x383f>
 109c9ed:	lea    -0x7b354(%rip),%rdi        # 10216a0 <core_number_pairs+0x1a150>
 109c9f4:	mov    %rdi,0x20(%rax,%rcx,8)
 109c9f9:	inc    %rcx
 109c9fc:	mov    %rcx,0x8(%rax)
 109ca00:	cmp    %rdx,%rcx
 109ca03:	jae    109d640 <my.diagram_membership::compute_sub_block_attachments+0x3860>
 109ca09:	lea    -0x7b330(%rip),%rdx        # 10216e0 <core_number_pairs+0x1a190>
 109ca10:	mov    %rdx,0x20(%rax,%rcx,8)
 109ca15:	inc    %rcx
 109ca18:	mov    %rcx,0x8(%rax)
 109ca1c:	mov    0x8(%r14),%rcx
 109ca20:	cmp    0x10(%r14),%rcx
 109ca24:	jae    109d65d <my.diagram_membership::compute_sub_block_attachments+0x387d>
 109ca2a:	mov    %rcx,%rdx
 109ca2d:	shl    $0x4,%rdx
 109ca31:	movq   $0x8,0x20(%r14,%rdx,1)
 109ca3a:	mov    %rax,0x28(%r14,%rdx,1)
 109ca3f:	inc    %rcx
 109ca42:	mov    %rcx,0x8(%r14)
 109ca46:	mov    %fs:0xfffffffffffffed0,%rax
 109ca4f:	test   %rax,%rax
 109ca52:	je     109d683 <my.diagram_membership::compute_sub_block_attachments+0x38a3>
 109ca58:	mov    (%rax),%rcx
 109ca5b:	mov    %rcx,%fs:0xfffffffffffffed0
 109ca64:	movl   $0x2000000,(%rax)
 109ca6a:	movq   $0x0,0x8(%rax)
 109ca72:	movq   $0x4,0x10(%rax)
 109ca7a:	mov    %rsi,0x18(%rax)
 109ca7e:	mov    $0x4,%edx
 109ca83:	xor    %ecx,%ecx
 109ca85:	lea    -0x7b36c(%rip),%rdi        # 1021720 <core_number_pairs+0x1a1d0>
 109ca8c:	mov    %rdi,0x20(%rax,%rcx,8)
 109ca91:	inc    %rcx
 109ca94:	mov    %rcx,0x8(%rax)
 109ca98:	cmp    %rdx,%rcx
 109ca9b:	jae    109d6c7 <my.diagram_membership::compute_sub_block_attachments+0x38e7>
 109caa1:	lea    -0x7b348(%rip),%rdi        # 1021760 <core_number_pairs+0x1a210>
 109caa8:	mov    %rdi,0x20(%rax,%rcx,8)
 109caad:	inc    %rcx
 109cab0:	mov    %rcx,0x8(%rax)
 109cab4:	cmp    %rdx,%rcx
 109cab7:	jae    109d6e8 <my.diagram_membership::compute_sub_block_attachments+0x3908>
 109cabd:	lea    -0x7b324(%rip),%rdi        # 10217a0 <core_number_pairs+0x1a250>
 109cac4:	mov    %rdi,0x20(%rax,%rcx,8)
 109cac9:	inc    %rcx
 109cacc:	mov    %rcx,0x8(%rax)
 109cad0:	cmp    %rdx,%rcx
 109cad3:	jae    109d709 <my.diagram_membership::compute_sub_block_attachments+0x3929>
 109cad9:	lea    -0x7b300(%rip),%rdx        # 10217e0 <core_number_pairs+0x1a290>
 109cae0:	mov    %rdx,0x20(%rax,%rcx,8)
 109cae5:	inc    %rcx
 109cae8:	mov    %rcx,0x8(%rax)
 109caec:	mov    0x8(%r14),%rcx
 109caf0:	cmp    0x10(%r14),%rcx
 109caf4:	jae    109d726 <my.diagram_membership::compute_sub_block_attachments+0x3946>
 109cafa:	mov    %rcx,%rdx
 109cafd:	shl    $0x4,%rdx
 109cb01:	movq   $0x9,0x20(%r14,%rdx,1)
 109cb0a:	mov    %rax,0x28(%r14,%rdx,1)
 109cb0f:	inc    %rcx
 109cb12:	mov    %rcx,0x8(%r14)
 109cb16:	mov    %fs:0xfffffffffffffed8,%rax
 109cb1f:	test   %rax,%rax
 109cb22:	je     109d74c <my.diagram_membership::compute_sub_block_attachments+0x396c>
 109cb28:	mov    (%rax),%rcx
 109cb2b:	mov    %rcx,%fs:0xfffffffffffffed8
 109cb34:	movl   $0x3000000,(%rax)
 109cb3a:	movq   $0x0,0x8(%rax)
 109cb42:	movq   $0x8,0x10(%rax)
 109cb4a:	mov    %rsi,0x18(%rax)
 109cb4e:	mov    $0x8,%edx
 109cb53:	xor    %ecx,%ecx
 109cb55:	lea    -0x7b33c(%rip),%rsi        # 1021820 <core_number_pairs+0x1a2d0>
 109cb5c:	mov    %rsi,0x20(%rax,%rcx,8)
 109cb61:	inc    %rcx
 109cb64:	mov    %rcx,0x8(%rax)
 109cb68:	cmp    %rdx,%rcx
 109cb6b:	jae    109d78d <my.diagram_membership::compute_sub_block_attachments+0x39ad>
 109cb71:	lea    -0x7b318(%rip),%rsi        # 1021860 <core_number_pairs+0x1a310>
 109cb78:	mov    %rsi,0x20(%rax,%rcx,8)
 109cb7d:	inc    %rcx
 109cb80:	mov    %rcx,0x8(%rax)
 109cb84:	cmp    %rdx,%rcx
 109cb87:	jae    109d7a7 <my.diagram_membership::compute_sub_block_attachments+0x39c7>
 109cb8d:	lea    -0x7b2f4(%rip),%rsi        # 10218a0 <core_number_pairs+0x1a350>
 109cb94:	mov    %rsi,0x20(%rax,%rcx,8)
 109cb99:	inc    %rcx
 109cb9c:	mov    %rcx,0x8(%rax)
 109cba0:	cmp    %rdx,%rcx
 109cba3:	jae    109d7c1 <my.diagram_membership::compute_sub_block_attachments+0x39e1>
 109cba9:	lea    -0x7b2d0(%rip),%rsi        # 10218e0 <core_number_pairs+0x1a390>
 109cbb0:	mov    %rsi,0x20(%rax,%rcx,8)
 109cbb5:	inc    %rcx
 109cbb8:	mov    %rcx,0x8(%rax)
 109cbbc:	cmp    %rdx,%rcx
 109cbbf:	jae    109d7db <my.diagram_membership::compute_sub_block_attachments+0x39fb>
 109cbc5:	lea    -0x7b2ac(%rip),%rsi        # 1021920 <core_number_pairs+0x1a3d0>
 109cbcc:	mov    %rsi,0x20(%rax,%rcx,8)
 109cbd1:	inc    %rcx
 109cbd4:	mov    %rcx,0x8(%rax)
 109cbd8:	cmp    %rdx,%rcx
 109cbdb:	jae    109d7f5 <my.diagram_membership::compute_sub_block_attachments+0x3a15>
 109cbe1:	lea    -0x7b288(%rip),%rsi        # 1021960 <core_number_pairs+0x1a410>
 109cbe8:	mov    %rsi,0x20(%rax,%rcx,8)
 109cbed:	inc    %rcx
 109cbf0:	mov    %rcx,0x8(%rax)
 109cbf4:	cmp    %rdx,%rcx
 109cbf7:	jae    109d80f <my.diagram_membership::compute_sub_block_attachments+0x3a2f>
 109cbfd:	lea    -0x7b264(%rip),%rsi        # 10219a0 <core_number_pairs+0x1a450>
 109cc04:	mov    %rsi,0x20(%rax,%rcx,8)
 109cc09:	inc    %rcx
 109cc0c:	mov    %rcx,0x8(%rax)
 109cc10:	cmp    %rdx,%rcx
 109cc13:	jae    109d829 <my.diagram_membership::compute_sub_block_attachments+0x3a49>
 109cc19:	lea    -0x7b240(%rip),%rdx        # 10219e0 <core_number_pairs+0x1a490>
 109cc20:	mov    %rdx,0x20(%rax,%rcx,8)
 109cc25:	inc    %rcx
 109cc28:	mov    %rcx,0x8(%rax)
 109cc2c:	mov    0x8(%r14),%rdx
 109cc30:	cmp    0x10(%r14),%rdx
 109cc34:	jae    109d83f <my.diagram_membership::compute_sub_block_attachments+0x3a5f>
 109cc3a:	lea    0x20(%r14),%rsi
 109cc3e:	mov    %rdx,%rcx
 109cc41:	shl    $0x4,%rcx
 109cc45:	movq   $0x4,0x20(%r14,%rcx,1)
 109cc4e:	mov    %rax,0x28(%r14,%rcx,1)
 109cc53:	lea    0x1(%rdx),%rax
 109cc57:	mov    %r14,0x20(%rsp)
 109cc5c:	mov    %rax,0x8(%r14)
 109cc60:	xor    %r9d,%r9d
 109cc63:	mov    %rdx,0xf0(%rsp)
 109cc6b:	mov    %rsi,0x30(%rsp)
 109cc70:	mov    %r9,%r10
 109cc73:	shl    $0x4,%r10
 109cc77:	mov    0x8(%rsi,%r10,1),%r11
 109cc7c:	mov    0x8(%r11),%rax
 109cc80:	mov    %rax,0x10(%rsp)
 109cc85:	test   %rax,%rax
 109cc88:	je     109ce00 <my.diagram_membership::compute_sub_block_attachments+0x3020>
 109cc8e:	add    %rsi,%r10
 109cc91:	mov    0x8(%rbp),%rdx
 109cc95:	xor    %r15d,%r15d
 109cc98:	jmp    109ccc3 <my.diagram_membership::compute_sub_block_attachments+0x2ee3>
 109cc9a:	test   %cl,%cl
 109cc9c:	je     109ce30 <my.diagram_membership::compute_sub_block_attachments+0x3050>
 109cca2:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ccb0:	inc    %r15
 109ccb3:	cmp    0x10(%rsp),%r15
 109ccb8:	mov    0x30(%rsp),%rsi
 109ccbd:	je     109ce00 <my.diagram_membership::compute_sub_block_attachments+0x3020>
 109ccc3:	mov    0x20(%r11,%r15,8),%rbx
 109ccc8:	mov    0x8(%rbx),%rax
 109cccc:	cmp    %rdx,%rax
 109cccf:	ja     109ccb0 <my.diagram_membership::compute_sub_block_attachments+0x2ed0>
 109ccd1:	xor    %r13d,%r13d
 109ccd4:	mov    %r13,%rsi
 109ccd7:	add    %rax,%rsi
 109ccda:	jo     109dab8 <my.diagram_membership::compute_sub_block_attachments+0x3cd8>
 109cce0:	cmp    %rdx,%rsi
 109cce3:	seta   %cl
 109cce6:	test   %rax,%rax
 109cce9:	je     109cc9a <my.diagram_membership::compute_sub_block_attachments+0x2eba>
 109cceb:	cmp    %rdx,%rsi
 109ccee:	ja     109cc9a <my.diagram_membership::compute_sub_block_attachments+0x2eba>
 109ccf0:	xor    %ecx,%ecx
 109ccf2:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109cd00:	mov    %r13,%rsi
 109cd03:	add    %rcx,%rsi
 109cd06:	jo     109da25 <my.diagram_membership::compute_sub_block_attachments+0x3c45>
 109cd0c:	cmp    %rdx,%rsi
 109cd0f:	jae    109da0c <my.diagram_membership::compute_sub_block_attachments+0x3c2c>
 109cd15:	movzbl 0x20(%rbp,%rsi,1),%esi
 109cd1a:	lea    -0x41(%rsi),%r8d
 109cd1e:	lea    0x20(%rsi),%r14d
 109cd22:	cmp    $0x1a,%r8b
 109cd26:	cmovae %rsi,%r14
 109cd2a:	movzbl 0x20(%rbx,%rcx,1),%esi
 109cd2f:	lea    -0x41(%rsi),%r8d
 109cd33:	lea    0x20(%rsi),%edi
 109cd36:	cmp    $0x1a,%r8b
 109cd3a:	cmovae %rsi,%rdi
 109cd3e:	cmp    %edi,%r14d
 109cd41:	jne    109cd50 <my.diagram_membership::compute_sub_block_attachments+0x2f70>
 109cd43:	inc    %rcx
 109cd46:	cmp    %rcx,%rax
 109cd49:	jne    109cd00 <my.diagram_membership::compute_sub_block_attachments+0x2f20>
 109cd4b:	jmp    109ce30 <my.diagram_membership::compute_sub_block_attachments+0x3050>
 109cd50:	lea    0x1(%r13),%r8
 109cd54:	mov    %r8,%rsi
 109cd57:	add    %rax,%rsi
 109cd5a:	jo     109dab5 <my.diagram_membership::compute_sub_block_attachments+0x3cd5>
 109cd60:	cmp    %rdx,%rsi
 109cd63:	seta   %cl
 109cd66:	test   %rax,%rax
 109cd69:	je     109cc9a <my.diagram_membership::compute_sub_block_attachments+0x2eba>
 109cd6f:	cmp    %rdx,%rsi
 109cd72:	ja     109cc9a <my.diagram_membership::compute_sub_block_attachments+0x2eba>
 109cd78:	xor    %ecx,%ecx
 109cd7a:	nopw   0x0(%rax,%rax,1)
 109cd80:	mov    %r8,%rsi
 109cd83:	add    %rcx,%rsi
 109cd86:	jo     109da22 <my.diagram_membership::compute_sub_block_attachments+0x3c42>
 109cd8c:	cmp    %rdx,%rsi
 109cd8f:	jae    109da09 <my.diagram_membership::compute_sub_block_attachments+0x3c29>
 109cd95:	mov    %rbp,%r12
 109cd98:	movzbl 0x20(%rbp,%rsi,1),%esi
 109cd9d:	lea    -0x41(%rsi),%edi
 109cda0:	lea    0x20(%rsi),%r14d
 109cda4:	cmp    $0x1a,%dil
 109cda8:	cmovae %rsi,%r14
 109cdac:	movzbl 0x20(%rbx,%rcx,1),%esi
 109cdb1:	lea    -0x41(%rsi),%edi
 109cdb4:	lea    0x20(%rsi),%ebp
 109cdb7:	cmp    $0x1a,%dil
 109cdbb:	cmovae %rsi,%rbp
 109cdbf:	cmp    %ebp,%r14d
 109cdc2:	jne    109cde0 <my.diagram_membership::compute_sub_block_attachments+0x3000>
 109cdc4:	inc    %rcx
 109cdc7:	cmp    %rcx,%rax
 109cdca:	mov    %r12,%rbp
 109cdcd:	jne    109cd80 <my.diagram_membership::compute_sub_block_attachments+0x2fa0>
 109cdcf:	jmp    109ce30 <my.diagram_membership::compute_sub_block_attachments+0x3050>
 109cdd1:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109cde0:	add    $0x2,%r13
 109cde4:	mov    %r12,%rbp
 109cde7:	jno    109ccd4 <my.diagram_membership::compute_sub_block_attachments+0x2ef4>
 109cded:	jmp    109daca <my.diagram_membership::compute_sub_block_attachments+0x3cea>
 109cdf2:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ce00:	mov    0xf0(%rsp),%rdx
 109ce08:	cmp    %rdx,%r9
 109ce0b:	lea    0x1(%r9),%r9
 109ce0f:	jne    109cc70 <my.diagram_membership::compute_sub_block_attachments+0x2e90>
 109ce15:	mov    0x20(%rsp),%rdi
 109ce1a:	call   103c740 <myl_core_drop_owned>
 109ce1f:	xor    %eax,%eax
 109ce21:	xor    %ebx,%ebx
 109ce23:	jmp    109ce40 <my.diagram_membership::compute_sub_block_attachments+0x3060>
 109ce25:	data16 cs nopw 0x0(%rax,%rax,1)
 109ce30:	movzbl (%r10),%ebx
 109ce34:	mov    0x20(%rsp),%rdi
 109ce39:	call   103c740 <myl_core_drop_owned>
 109ce3e:	mov    $0x1,%al
 109ce40:	cmp    $0x1,%al
 109ce42:	mov    0xa8(%rsp),%r14
 109ce4a:	mov    0x80(%rsp),%rdi
 109ce52:	mov    0x48(%rsp),%r8d
 109ce57:	mov    0x60(%rsp),%r9
 109ce5c:	mov    0x8(%rsp),%r10
 109ce61:	mov    0xb0(%rsp),%r11
 109ce69:	je     109c1f0 <my.diagram_membership::compute_sub_block_attachments+0x2410>
 109ce6f:	mov    0xd8(%rsp),%rsi
 109ce77:	mov    0x8(%rsi),%rax
 109ce7b:	test   %rax,%rax
 109ce7e:	je     109cef0 <my.diagram_membership::compute_sub_block_attachments+0x3110>
 109ce80:	add    $0x20,%rsi
 109ce84:	jmp    109cecc <my.diagram_membership::compute_sub_block_attachments+0x30ec>
 109ce86:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ce95:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109cea4:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ceb3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109cec0:	add    $0x218,%rsi
 109cec7:	dec    %rax
 109ceca:	je     109cef0 <my.diagram_membership::compute_sub_block_attachments+0x3110>
 109cecc:	mov    (%rsi),%rcx
 109cecf:	cmpq   $0x0,0x8(%rcx)
 109ced4:	je     109cec0 <my.diagram_membership::compute_sub_block_attachments+0x30e0>
 109ced6:	movzbl 0x20(%rcx),%edx
 109ceda:	mov    $0x1,%cl
 109cedc:	cmp    $0x50,%edx
 109cedf:	je     109c1f6 <my.diagram_membership::compute_sub_block_attachments+0x2416>
 109cee5:	cmp    $0x4a,%edx
 109cee8:	jne    109cec0 <my.diagram_membership::compute_sub_block_attachments+0x30e0>
 109ceea:	jmp    109c1f6 <my.diagram_membership::compute_sub_block_attachments+0x2416>
 109ceef:	nop
 109cef0:	xor    %ecx,%ecx
 109cef2:	jmp    109c1f6 <my.diagram_membership::compute_sub_block_attachments+0x2416>
 109cef7:	mov    $0x9,%edi
 109cefc:	mov    $0x10,%esi
 109cf01:	call   103b980 <myl_core_list_new_slow>
 109cf06:	lea    -0x71db5(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109cf0d:	mov    %rax,%r14
 109cf10:	jmp    109c2df <my.diagram_membership::compute_sub_block_attachments+0x24ff>
 109cf15:	mov    $0x8,%edi
 109cf1a:	mov    %rsi,%rbx
 109cf1d:	mov    $0x8,%esi
 109cf22:	call   103b980 <myl_core_list_new_slow>
 109cf27:	mov    0x8(%rax),%rcx
 109cf2b:	mov    0x10(%rax),%rdx
 109cf2f:	mov    %rbx,0x18(%rax)
 109cf33:	cmp    %rdx,%rcx
 109cf36:	jb     109cf4d <my.diagram_membership::compute_sub_block_attachments+0x316d>
 109cf38:	mov    $0x8,%esi
 109cf3d:	mov    %rax,%rdi
 109cf40:	call   103ba40 <myl_core_list_grow>
 109cf45:	mov    0x8(%rax),%rcx
 109cf49:	mov    0x10(%rax),%rdx
 109cf4d:	lea    -0x71dfc(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109cf54:	jmp    109c331 <my.diagram_membership::compute_sub_block_attachments+0x2551>
 109cf59:	mov    $0x8,%esi
 109cf5e:	mov    %rax,%rdi
 109cf61:	call   103ba40 <myl_core_list_grow>
 109cf66:	lea    -0x71e15(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109cf6d:	mov    0x8(%rax),%rcx
 109cf71:	mov    0x10(%rax),%rdx
 109cf75:	jmp    109c34d <my.diagram_membership::compute_sub_block_attachments+0x256d>
 109cf7a:	mov    $0x8,%esi
 109cf7f:	mov    %rax,%rdi
 109cf82:	call   103ba40 <myl_core_list_grow>
 109cf87:	lea    -0x71e36(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109cf8e:	mov    0x8(%rax),%rcx
 109cf92:	mov    0x10(%rax),%rdx
 109cf96:	jmp    109c369 <my.diagram_membership::compute_sub_block_attachments+0x2589>
 109cf9b:	mov    $0x8,%esi
 109cfa0:	mov    %rax,%rdi
 109cfa3:	call   103ba40 <myl_core_list_grow>
 109cfa8:	lea    -0x71e57(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109cfaf:	mov    0x8(%rax),%rcx
 109cfb3:	mov    0x10(%rax),%rdx
 109cfb7:	jmp    109c385 <my.diagram_membership::compute_sub_block_attachments+0x25a5>
 109cfbc:	mov    $0x8,%esi
 109cfc1:	mov    %rax,%rdi
 109cfc4:	call   103ba40 <myl_core_list_grow>
 109cfc9:	lea    -0x71e78(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109cfd0:	mov    0x8(%rax),%rcx
 109cfd4:	mov    0x10(%rax),%rdx
 109cfd8:	jmp    109c3a1 <my.diagram_membership::compute_sub_block_attachments+0x25c1>
 109cfdd:	mov    $0x8,%esi
 109cfe2:	mov    %rax,%rdi
 109cfe5:	call   103ba40 <myl_core_list_grow>
 109cfea:	lea    -0x71e99(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109cff1:	mov    0x8(%rax),%rcx
 109cff5:	mov    0x10(%rax),%rdx
 109cff9:	jmp    109c3bd <my.diagram_membership::compute_sub_block_attachments+0x25dd>
 109cffe:	mov    $0x8,%esi
 109d003:	mov    %rax,%rdi
 109d006:	call   103ba40 <myl_core_list_grow>
 109d00b:	lea    -0x71eba(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d012:	mov    0x8(%rax),%rcx
 109d016:	mov    0x10(%rax),%rdx
 109d01a:	jmp    109c3d9 <my.diagram_membership::compute_sub_block_attachments+0x25f9>
 109d01f:	mov    $0x8,%esi
 109d024:	mov    %rax,%rdi
 109d027:	call   103ba40 <myl_core_list_grow>
 109d02c:	lea    -0x71edb(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d033:	mov    0x8(%rax),%rcx
 109d037:	jmp    109c3f5 <my.diagram_membership::compute_sub_block_attachments+0x2615>
 109d03c:	mov    $0x10,%esi
 109d041:	mov    %r14,%rdi
 109d044:	mov    %rax,%rbx
 109d047:	call   103ba40 <myl_core_list_grow>
 109d04c:	lea    -0x71efb(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d053:	mov    %rax,%r14
 109d056:	mov    %rbx,%rax
 109d059:	mov    0x8(%r14),%rcx
 109d05d:	jmp    109c416 <my.diagram_membership::compute_sub_block_attachments+0x2636>
 109d062:	mov    $0x7,%edi
 109d067:	mov    %rsi,%rbx
 109d06a:	mov    $0x8,%esi
 109d06f:	call   103b980 <myl_core_list_new_slow>
 109d074:	mov    0x8(%rax),%rcx
 109d078:	mov    0x10(%rax),%rdx
 109d07c:	mov    %rbx,0x18(%rax)
 109d080:	cmp    %rdx,%rcx
 109d083:	jb     109d09a <my.diagram_membership::compute_sub_block_attachments+0x32ba>
 109d085:	mov    $0x8,%esi
 109d08a:	mov    %rax,%rdi
 109d08d:	call   103ba40 <myl_core_list_grow>
 109d092:	mov    0x8(%rax),%rcx
 109d096:	mov    0x10(%rax),%rdx
 109d09a:	lea    -0x71f49(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d0a1:	jmp    109c471 <my.diagram_membership::compute_sub_block_attachments+0x2691>
 109d0a6:	mov    $0x8,%esi
 109d0ab:	mov    %rax,%rdi
 109d0ae:	call   103ba40 <myl_core_list_grow>
 109d0b3:	lea    -0x71f62(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d0ba:	mov    0x8(%rax),%rcx
 109d0be:	mov    0x10(%rax),%rdx
 109d0c2:	jmp    109c48d <my.diagram_membership::compute_sub_block_attachments+0x26ad>
 109d0c7:	mov    $0x8,%esi
 109d0cc:	mov    %rax,%rdi
 109d0cf:	call   103ba40 <myl_core_list_grow>
 109d0d4:	lea    -0x71f83(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d0db:	mov    0x8(%rax),%rcx
 109d0df:	mov    0x10(%rax),%rdx
 109d0e3:	jmp    109c4a9 <my.diagram_membership::compute_sub_block_attachments+0x26c9>
 109d0e8:	mov    $0x8,%esi
 109d0ed:	mov    %rax,%rdi
 109d0f0:	call   103ba40 <myl_core_list_grow>
 109d0f5:	lea    -0x71fa4(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d0fc:	mov    0x8(%rax),%rcx
 109d100:	mov    0x10(%rax),%rdx
 109d104:	jmp    109c4c5 <my.diagram_membership::compute_sub_block_attachments+0x26e5>
 109d109:	mov    $0x8,%esi
 109d10e:	mov    %rax,%rdi
 109d111:	call   103ba40 <myl_core_list_grow>
 109d116:	lea    -0x71fc5(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d11d:	mov    0x8(%rax),%rcx
 109d121:	mov    0x10(%rax),%rdx
 109d125:	jmp    109c4e1 <my.diagram_membership::compute_sub_block_attachments+0x2701>
 109d12a:	mov    $0x8,%esi
 109d12f:	mov    %rax,%rdi
 109d132:	call   103ba40 <myl_core_list_grow>
 109d137:	lea    -0x71fe6(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d13e:	mov    0x8(%rax),%rcx
 109d142:	mov    0x10(%rax),%rdx
 109d146:	jmp    109c4fd <my.diagram_membership::compute_sub_block_attachments+0x271d>
 109d14b:	mov    $0x8,%esi
 109d150:	mov    %rax,%rdi
 109d153:	call   103ba40 <myl_core_list_grow>
 109d158:	lea    -0x72007(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d15f:	mov    0x8(%rax),%rcx
 109d163:	jmp    109c519 <my.diagram_membership::compute_sub_block_attachments+0x2739>
 109d168:	mov    $0x10,%esi
 109d16d:	mov    %r14,%rdi
 109d170:	mov    %rax,%rbx
 109d173:	call   103ba40 <myl_core_list_grow>
 109d178:	lea    -0x72027(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d17f:	mov    %rax,%r14
 109d182:	mov    %rbx,%rax
 109d185:	mov    0x8(%r14),%rcx
 109d189:	jmp    109c53a <my.diagram_membership::compute_sub_block_attachments+0x275a>
 109d18e:	mov    $0x5,%edi
 109d193:	mov    %rsi,%rbx
 109d196:	mov    $0x8,%esi
 109d19b:	call   103b980 <myl_core_list_new_slow>
 109d1a0:	mov    0x8(%rax),%rcx
 109d1a4:	mov    0x10(%rax),%rdx
 109d1a8:	mov    %rbx,0x18(%rax)
 109d1ac:	cmp    %rdx,%rcx
 109d1af:	jb     109d1c6 <my.diagram_membership::compute_sub_block_attachments+0x33e6>
 109d1b1:	mov    $0x8,%esi
 109d1b6:	mov    %rax,%rdi
 109d1b9:	call   103ba40 <myl_core_list_grow>
 109d1be:	mov    0x8(%rax),%rcx
 109d1c2:	mov    0x10(%rax),%rdx
 109d1c6:	lea    -0x72075(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d1cd:	jmp    109c595 <my.diagram_membership::compute_sub_block_attachments+0x27b5>
 109d1d2:	mov    $0x8,%esi
 109d1d7:	mov    %rax,%rdi
 109d1da:	call   103ba40 <myl_core_list_grow>
 109d1df:	lea    -0x7208e(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d1e6:	mov    0x8(%rax),%rcx
 109d1ea:	mov    0x10(%rax),%rdx
 109d1ee:	jmp    109c5b1 <my.diagram_membership::compute_sub_block_attachments+0x27d1>
 109d1f3:	mov    $0x8,%esi
 109d1f8:	mov    %rax,%rdi
 109d1fb:	call   103ba40 <myl_core_list_grow>
 109d200:	lea    -0x720af(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d207:	mov    0x8(%rax),%rcx
 109d20b:	mov    0x10(%rax),%rdx
 109d20f:	jmp    109c5cd <my.diagram_membership::compute_sub_block_attachments+0x27ed>
 109d214:	mov    $0x8,%esi
 109d219:	mov    %rax,%rdi
 109d21c:	call   103ba40 <myl_core_list_grow>
 109d221:	lea    -0x720d0(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d228:	mov    0x8(%rax),%rcx
 109d22c:	mov    0x10(%rax),%rdx
 109d230:	jmp    109c5e9 <my.diagram_membership::compute_sub_block_attachments+0x2809>
 109d235:	mov    $0x8,%esi
 109d23a:	mov    %rax,%rdi
 109d23d:	call   103ba40 <myl_core_list_grow>
 109d242:	lea    -0x720f1(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d249:	mov    0x8(%rax),%rcx
 109d24d:	jmp    109c605 <my.diagram_membership::compute_sub_block_attachments+0x2825>
 109d252:	mov    $0x10,%esi
 109d257:	mov    %r14,%rdi
 109d25a:	mov    %rax,%rbx
 109d25d:	call   103ba40 <myl_core_list_grow>
 109d262:	lea    -0x72111(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d269:	mov    %rax,%r14
 109d26c:	mov    %rbx,%rax
 109d26f:	mov    0x8(%r14),%rcx
 109d273:	jmp    109c626 <my.diagram_membership::compute_sub_block_attachments+0x2846>
 109d278:	mov    $0x6,%edi
 109d27d:	mov    %rsi,%rbx
 109d280:	mov    $0x8,%esi
 109d285:	call   103b980 <myl_core_list_new_slow>
 109d28a:	mov    0x8(%rax),%rcx
 109d28e:	mov    0x10(%rax),%rdx
 109d292:	mov    %rbx,0x18(%rax)
 109d296:	cmp    %rdx,%rcx
 109d299:	jb     109d2b0 <my.diagram_membership::compute_sub_block_attachments+0x34d0>
 109d29b:	mov    $0x8,%esi
 109d2a0:	mov    %rax,%rdi
 109d2a3:	call   103ba40 <myl_core_list_grow>
 109d2a8:	mov    0x8(%rax),%rcx
 109d2ac:	mov    0x10(%rax),%rdx
 109d2b0:	lea    -0x7215f(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d2b7:	jmp    109c681 <my.diagram_membership::compute_sub_block_attachments+0x28a1>
 109d2bc:	mov    $0x8,%esi
 109d2c1:	mov    %rax,%rdi
 109d2c4:	call   103ba40 <myl_core_list_grow>
 109d2c9:	lea    -0x72178(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d2d0:	mov    0x8(%rax),%rcx
 109d2d4:	mov    0x10(%rax),%rdx
 109d2d8:	jmp    109c69d <my.diagram_membership::compute_sub_block_attachments+0x28bd>
 109d2dd:	mov    $0x8,%esi
 109d2e2:	mov    %rax,%rdi
 109d2e5:	call   103ba40 <myl_core_list_grow>
 109d2ea:	lea    -0x72199(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d2f1:	mov    0x8(%rax),%rcx
 109d2f5:	mov    0x10(%rax),%rdx
 109d2f9:	jmp    109c6b9 <my.diagram_membership::compute_sub_block_attachments+0x28d9>
 109d2fe:	mov    $0x8,%esi
 109d303:	mov    %rax,%rdi
 109d306:	call   103ba40 <myl_core_list_grow>
 109d30b:	lea    -0x721ba(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d312:	mov    0x8(%rax),%rcx
 109d316:	mov    0x10(%rax),%rdx
 109d31a:	jmp    109c6d5 <my.diagram_membership::compute_sub_block_attachments+0x28f5>
 109d31f:	mov    $0x8,%esi
 109d324:	mov    %rax,%rdi
 109d327:	call   103ba40 <myl_core_list_grow>
 109d32c:	lea    -0x721db(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d333:	mov    0x8(%rax),%rcx
 109d337:	mov    0x10(%rax),%rdx
 109d33b:	jmp    109c6f1 <my.diagram_membership::compute_sub_block_attachments+0x2911>
 109d340:	mov    $0x8,%esi
 109d345:	mov    %rax,%rdi
 109d348:	call   103ba40 <myl_core_list_grow>
 109d34d:	lea    -0x721fc(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d354:	mov    0x8(%rax),%rcx
 109d358:	jmp    109c70d <my.diagram_membership::compute_sub_block_attachments+0x292d>
 109d35d:	mov    $0x10,%esi
 109d362:	mov    %r14,%rdi
 109d365:	mov    %rax,%rbx
 109d368:	call   103ba40 <myl_core_list_grow>
 109d36d:	lea    -0x7221c(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d374:	mov    %rax,%r14
 109d377:	mov    %rbx,%rax
 109d37a:	mov    0x8(%r14),%rcx
 109d37e:	jmp    109c72e <my.diagram_membership::compute_sub_block_attachments+0x294e>
 109d383:	mov    $0x6,%edi
 109d388:	mov    %rsi,%rbx
 109d38b:	mov    $0x8,%esi
 109d390:	call   103b980 <myl_core_list_new_slow>
 109d395:	mov    0x8(%rax),%rcx
 109d399:	mov    0x10(%rax),%rdx
 109d39d:	mov    %rbx,0x18(%rax)
 109d3a1:	cmp    %rdx,%rcx
 109d3a4:	jb     109d3bb <my.diagram_membership::compute_sub_block_attachments+0x35db>
 109d3a6:	mov    $0x8,%esi
 109d3ab:	mov    %rax,%rdi
 109d3ae:	call   103ba40 <myl_core_list_grow>
 109d3b3:	mov    0x8(%rax),%rcx
 109d3b7:	mov    0x10(%rax),%rdx
 109d3bb:	lea    -0x7226a(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d3c2:	jmp    109c789 <my.diagram_membership::compute_sub_block_attachments+0x29a9>
 109d3c7:	mov    $0x8,%esi
 109d3cc:	mov    %rax,%rdi
 109d3cf:	call   103ba40 <myl_core_list_grow>
 109d3d4:	lea    -0x72283(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d3db:	mov    0x8(%rax),%rcx
 109d3df:	mov    0x10(%rax),%rdx
 109d3e3:	jmp    109c7a5 <my.diagram_membership::compute_sub_block_attachments+0x29c5>
 109d3e8:	mov    $0x8,%esi
 109d3ed:	mov    %rax,%rdi
 109d3f0:	call   103ba40 <myl_core_list_grow>
 109d3f5:	lea    -0x722a4(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d3fc:	mov    0x8(%rax),%rcx
 109d400:	mov    0x10(%rax),%rdx
 109d404:	jmp    109c7c1 <my.diagram_membership::compute_sub_block_attachments+0x29e1>
 109d409:	mov    $0x8,%esi
 109d40e:	mov    %rax,%rdi
 109d411:	call   103ba40 <myl_core_list_grow>
 109d416:	lea    -0x722c5(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d41d:	mov    0x8(%rax),%rcx
 109d421:	mov    0x10(%rax),%rdx
 109d425:	jmp    109c7dd <my.diagram_membership::compute_sub_block_attachments+0x29fd>
 109d42a:	mov    $0x8,%esi
 109d42f:	mov    %rax,%rdi
 109d432:	call   103ba40 <myl_core_list_grow>
 109d437:	lea    -0x722e6(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d43e:	mov    0x8(%rax),%rcx
 109d442:	mov    0x10(%rax),%rdx
 109d446:	jmp    109c7f9 <my.diagram_membership::compute_sub_block_attachments+0x2a19>
 109d44b:	mov    $0x8,%esi
 109d450:	mov    %rax,%rdi
 109d453:	call   103ba40 <myl_core_list_grow>
 109d458:	lea    -0x72307(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d45f:	mov    0x8(%rax),%rcx
 109d463:	jmp    109c815 <my.diagram_membership::compute_sub_block_attachments+0x2a35>
 109d468:	mov    $0x10,%esi
 109d46d:	mov    %r14,%rdi
 109d470:	mov    %rax,%rbx
 109d473:	call   103ba40 <myl_core_list_grow>
 109d478:	lea    -0x72327(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d47f:	mov    %rax,%r14
 109d482:	mov    %rbx,%rax
 109d485:	mov    0x8(%r14),%rcx
 109d489:	jmp    109c836 <my.diagram_membership::compute_sub_block_attachments+0x2a56>
 109d48e:	mov    $0x6,%edi
 109d493:	mov    %rsi,%rbx
 109d496:	mov    $0x8,%esi
 109d49b:	call   103b980 <myl_core_list_new_slow>
 109d4a0:	mov    0x8(%rax),%rcx
 109d4a4:	mov    0x10(%rax),%rdx
 109d4a8:	mov    %rbx,0x18(%rax)
 109d4ac:	cmp    %rdx,%rcx
 109d4af:	jb     109d4c6 <my.diagram_membership::compute_sub_block_attachments+0x36e6>
 109d4b1:	mov    $0x8,%esi
 109d4b6:	mov    %rax,%rdi
 109d4b9:	call   103ba40 <myl_core_list_grow>
 109d4be:	mov    0x8(%rax),%rcx
 109d4c2:	mov    0x10(%rax),%rdx
 109d4c6:	lea    -0x72375(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d4cd:	jmp    109c891 <my.diagram_membership::compute_sub_block_attachments+0x2ab1>
 109d4d2:	mov    $0x8,%esi
 109d4d7:	mov    %rax,%rdi
 109d4da:	call   103ba40 <myl_core_list_grow>
 109d4df:	lea    -0x7238e(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d4e6:	mov    0x8(%rax),%rcx
 109d4ea:	mov    0x10(%rax),%rdx
 109d4ee:	jmp    109c8ad <my.diagram_membership::compute_sub_block_attachments+0x2acd>
 109d4f3:	mov    $0x8,%esi
 109d4f8:	mov    %rax,%rdi
 109d4fb:	call   103ba40 <myl_core_list_grow>
 109d500:	lea    -0x723af(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d507:	mov    0x8(%rax),%rcx
 109d50b:	mov    0x10(%rax),%rdx
 109d50f:	jmp    109c8c9 <my.diagram_membership::compute_sub_block_attachments+0x2ae9>
 109d514:	mov    $0x8,%esi
 109d519:	mov    %rax,%rdi
 109d51c:	call   103ba40 <myl_core_list_grow>
 109d521:	lea    -0x723d0(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d528:	mov    0x8(%rax),%rcx
 109d52c:	mov    0x10(%rax),%rdx
 109d530:	jmp    109c8e5 <my.diagram_membership::compute_sub_block_attachments+0x2b05>
 109d535:	mov    $0x8,%esi
 109d53a:	mov    %rax,%rdi
 109d53d:	call   103ba40 <myl_core_list_grow>
 109d542:	lea    -0x723f1(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d549:	mov    0x8(%rax),%rcx
 109d54d:	mov    0x10(%rax),%rdx
 109d551:	jmp    109c901 <my.diagram_membership::compute_sub_block_attachments+0x2b21>
 109d556:	mov    $0x8,%esi
 109d55b:	mov    %rax,%rdi
 109d55e:	call   103ba40 <myl_core_list_grow>
 109d563:	lea    -0x72412(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d56a:	mov    0x8(%rax),%rcx
 109d56e:	jmp    109c91d <my.diagram_membership::compute_sub_block_attachments+0x2b3d>
 109d573:	mov    $0x10,%esi
 109d578:	mov    %r14,%rdi
 109d57b:	mov    %rax,%rbx
 109d57e:	call   103ba40 <myl_core_list_grow>
 109d583:	lea    -0x72432(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d58a:	mov    %rax,%r14
 109d58d:	mov    %rbx,%rax
 109d590:	mov    0x8(%r14),%rcx
 109d594:	jmp    109c93e <my.diagram_membership::compute_sub_block_attachments+0x2b5e>
 109d599:	mov    $0x5,%edi
 109d59e:	mov    %rsi,%rbx
 109d5a1:	mov    $0x8,%esi
 109d5a6:	call   103b980 <myl_core_list_new_slow>
 109d5ab:	mov    0x8(%rax),%rcx
 109d5af:	mov    0x10(%rax),%rdx
 109d5b3:	mov    %rbx,0x18(%rax)
 109d5b7:	cmp    %rdx,%rcx
 109d5ba:	jb     109d5d1 <my.diagram_membership::compute_sub_block_attachments+0x37f1>
 109d5bc:	mov    $0x8,%esi
 109d5c1:	mov    %rax,%rdi
 109d5c4:	call   103ba40 <myl_core_list_grow>
 109d5c9:	mov    0x8(%rax),%rcx
 109d5cd:	mov    0x10(%rax),%rdx
 109d5d1:	lea    -0x72480(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d5d8:	jmp    109c999 <my.diagram_membership::compute_sub_block_attachments+0x2bb9>
 109d5dd:	mov    $0x8,%esi
 109d5e2:	mov    %rax,%rdi
 109d5e5:	call   103ba40 <myl_core_list_grow>
 109d5ea:	lea    -0x72499(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d5f1:	mov    0x8(%rax),%rcx
 109d5f5:	mov    0x10(%rax),%rdx
 109d5f9:	jmp    109c9b5 <my.diagram_membership::compute_sub_block_attachments+0x2bd5>
 109d5fe:	mov    $0x8,%esi
 109d603:	mov    %rax,%rdi
 109d606:	call   103ba40 <myl_core_list_grow>
 109d60b:	lea    -0x724ba(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d612:	mov    0x8(%rax),%rcx
 109d616:	mov    0x10(%rax),%rdx
 109d61a:	jmp    109c9d1 <my.diagram_membership::compute_sub_block_attachments+0x2bf1>
 109d61f:	mov    $0x8,%esi
 109d624:	mov    %rax,%rdi
 109d627:	call   103ba40 <myl_core_list_grow>
 109d62c:	lea    -0x724db(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d633:	mov    0x8(%rax),%rcx
 109d637:	mov    0x10(%rax),%rdx
 109d63b:	jmp    109c9ed <my.diagram_membership::compute_sub_block_attachments+0x2c0d>
 109d640:	mov    $0x8,%esi
 109d645:	mov    %rax,%rdi
 109d648:	call   103ba40 <myl_core_list_grow>
 109d64d:	lea    -0x724fc(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d654:	mov    0x8(%rax),%rcx
 109d658:	jmp    109ca09 <my.diagram_membership::compute_sub_block_attachments+0x2c29>
 109d65d:	mov    $0x10,%esi
 109d662:	mov    %r14,%rdi
 109d665:	mov    %rax,%rbx
 109d668:	call   103ba40 <myl_core_list_grow>
 109d66d:	lea    -0x7251c(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d674:	mov    %rax,%r14
 109d677:	mov    %rbx,%rax
 109d67a:	mov    0x8(%r14),%rcx
 109d67e:	jmp    109ca2a <my.diagram_membership::compute_sub_block_attachments+0x2c4a>
 109d683:	mov    $0x4,%edi
 109d688:	mov    %rsi,%rbx
 109d68b:	mov    $0x8,%esi
 109d690:	call   103b980 <myl_core_list_new_slow>
 109d695:	mov    0x8(%rax),%rcx
 109d699:	mov    0x10(%rax),%rdx
 109d69d:	mov    %rbx,0x18(%rax)
 109d6a1:	cmp    %rdx,%rcx
 109d6a4:	jb     109d6bb <my.diagram_membership::compute_sub_block_attachments+0x38db>
 109d6a6:	mov    $0x8,%esi
 109d6ab:	mov    %rax,%rdi
 109d6ae:	call   103ba40 <myl_core_list_grow>
 109d6b3:	mov    0x8(%rax),%rcx
 109d6b7:	mov    0x10(%rax),%rdx
 109d6bb:	lea    -0x7256a(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d6c2:	jmp    109ca85 <my.diagram_membership::compute_sub_block_attachments+0x2ca5>
 109d6c7:	mov    $0x8,%esi
 109d6cc:	mov    %rax,%rdi
 109d6cf:	call   103ba40 <myl_core_list_grow>
 109d6d4:	lea    -0x72583(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d6db:	mov    0x8(%rax),%rcx
 109d6df:	mov    0x10(%rax),%rdx
 109d6e3:	jmp    109caa1 <my.diagram_membership::compute_sub_block_attachments+0x2cc1>
 109d6e8:	mov    $0x8,%esi
 109d6ed:	mov    %rax,%rdi
 109d6f0:	call   103ba40 <myl_core_list_grow>
 109d6f5:	lea    -0x725a4(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d6fc:	mov    0x8(%rax),%rcx
 109d700:	mov    0x10(%rax),%rdx
 109d704:	jmp    109cabd <my.diagram_membership::compute_sub_block_attachments+0x2cdd>
 109d709:	mov    $0x8,%esi
 109d70e:	mov    %rax,%rdi
 109d711:	call   103ba40 <myl_core_list_grow>
 109d716:	lea    -0x725c5(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d71d:	mov    0x8(%rax),%rcx
 109d721:	jmp    109cad9 <my.diagram_membership::compute_sub_block_attachments+0x2cf9>
 109d726:	mov    $0x10,%esi
 109d72b:	mov    %r14,%rdi
 109d72e:	mov    %rax,%rbx
 109d731:	call   103ba40 <myl_core_list_grow>
 109d736:	lea    -0x725e5(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d73d:	mov    %rax,%r14
 109d740:	mov    %rbx,%rax
 109d743:	mov    0x8(%r14),%rcx
 109d747:	jmp    109cafa <my.diagram_membership::compute_sub_block_attachments+0x2d1a>
 109d74c:	mov    $0x8,%edi
 109d751:	mov    %rsi,%rbx
 109d754:	mov    $0x8,%esi
 109d759:	call   103b980 <myl_core_list_new_slow>
 109d75e:	mov    0x8(%rax),%rcx
 109d762:	mov    0x10(%rax),%rdx
 109d766:	mov    %rbx,0x18(%rax)
 109d76a:	cmp    %rdx,%rcx
 109d76d:	jb     109cb55 <my.diagram_membership::compute_sub_block_attachments+0x2d75>
 109d773:	mov    $0x8,%esi
 109d778:	mov    %rax,%rdi
 109d77b:	call   103ba40 <myl_core_list_grow>
 109d780:	mov    0x8(%rax),%rcx
 109d784:	mov    0x10(%rax),%rdx
 109d788:	jmp    109cb55 <my.diagram_membership::compute_sub_block_attachments+0x2d75>
 109d78d:	mov    $0x8,%esi
 109d792:	mov    %rax,%rdi
 109d795:	call   103ba40 <myl_core_list_grow>
 109d79a:	mov    0x8(%rax),%rcx
 109d79e:	mov    0x10(%rax),%rdx
 109d7a2:	jmp    109cb71 <my.diagram_membership::compute_sub_block_attachments+0x2d91>
 109d7a7:	mov    $0x8,%esi
 109d7ac:	mov    %rax,%rdi
 109d7af:	call   103ba40 <myl_core_list_grow>
 109d7b4:	mov    0x8(%rax),%rcx
 109d7b8:	mov    0x10(%rax),%rdx
 109d7bc:	jmp    109cb8d <my.diagram_membership::compute_sub_block_attachments+0x2dad>
 109d7c1:	mov    $0x8,%esi
 109d7c6:	mov    %rax,%rdi
 109d7c9:	call   103ba40 <myl_core_list_grow>
 109d7ce:	mov    0x8(%rax),%rcx
 109d7d2:	mov    0x10(%rax),%rdx
 109d7d6:	jmp    109cba9 <my.diagram_membership::compute_sub_block_attachments+0x2dc9>
 109d7db:	mov    $0x8,%esi
 109d7e0:	mov    %rax,%rdi
 109d7e3:	call   103ba40 <myl_core_list_grow>
 109d7e8:	mov    0x8(%rax),%rcx
 109d7ec:	mov    0x10(%rax),%rdx
 109d7f0:	jmp    109cbc5 <my.diagram_membership::compute_sub_block_attachments+0x2de5>
 109d7f5:	mov    $0x8,%esi
 109d7fa:	mov    %rax,%rdi
 109d7fd:	call   103ba40 <myl_core_list_grow>
 109d802:	mov    0x8(%rax),%rcx
 109d806:	mov    0x10(%rax),%rdx
 109d80a:	jmp    109cbe1 <my.diagram_membership::compute_sub_block_attachments+0x2e01>
 109d80f:	mov    $0x8,%esi
 109d814:	mov    %rax,%rdi
 109d817:	call   103ba40 <myl_core_list_grow>
 109d81c:	mov    0x8(%rax),%rcx
 109d820:	mov    0x10(%rax),%rdx
 109d824:	jmp    109cbfd <my.diagram_membership::compute_sub_block_attachments+0x2e1d>
 109d829:	mov    $0x8,%esi
 109d82e:	mov    %rax,%rdi
 109d831:	call   103ba40 <myl_core_list_grow>
 109d836:	mov    0x8(%rax),%rcx
 109d83a:	jmp    109cc19 <my.diagram_membership::compute_sub_block_attachments+0x2e39>
 109d83f:	mov    $0x10,%esi
 109d844:	mov    %r14,%rdi
 109d847:	mov    %rax,%rbx
 109d84a:	call   103ba40 <myl_core_list_grow>
 109d84f:	mov    %rax,%r14
 109d852:	mov    %rbx,%rax
 109d855:	mov    0x8(%r14),%rdx
 109d859:	jmp    109cc3a <my.diagram_membership::compute_sub_block_attachments+0x2e5a>
 109d85e:	xchg   %ax,%ax
 109d860:	test   %r10,%r10
 109d863:	mov    0x98(%rsp),%rsi
 109d86b:	je     109bfe0 <my.diagram_membership::compute_sub_block_attachments+0x2200>
 109d871:	mov    0xc0(%rsp),%rax
 109d879:	mov    0x8(%rax),%rdx
 109d87d:	cmp    %rdx,%rsi
 109d880:	jae    109db69 <my.diagram_membership::compute_sub_block_attachments+0x3d89>
 109d886:	mov    %rsi,%rax
 109d889:	shl    $0x4,%rax
 109d88d:	movzbl %cl,%ecx
 109d890:	mov    0xd0(%rsp),%rdx
 109d898:	mov    %rcx,(%rdx,%rax,1)
 109d89c:	mov    %rdi,0x8(%rdx,%rax,1)
 109d8a1:	jmp    109bfe0 <my.diagram_membership::compute_sub_block_attachments+0x2200>
 109d8a6:	mov    0x10(%rsp),%rdi
 109d8ab:	call   103c740 <myl_core_drop_owned>
 109d8b0:	mov    0xa8(%rsp),%r14
 109d8b8:	mov    0xc0(%rsp),%rax
 109d8c0:	mov    0x8(%rax),%rdx
 109d8c4:	mov    0x98(%rsp),%rsi
 109d8cc:	cmp    %rdx,%rsi
 109d8cf:	jae    109db46 <my.diagram_membership::compute_sub_block_attachments+0x3d66>
 109d8d5:	shl    $0x4,%r15
 109d8d9:	mov    0x28(%rsp),%rax
 109d8de:	mov    0x28(%rax,%r15,1),%rax
 109d8e3:	mov    %rsi,%rcx
 109d8e6:	shl    $0x4,%rcx
 109d8ea:	mov    0xd0(%rsp),%rdx
 109d8f2:	movq   $0x1,(%rdx,%rcx,1)
 109d8fa:	mov    %rax,0x8(%rdx,%rcx,1)
 109d8ff:	jmp    109bfe0 <my.diagram_membership::compute_sub_block_attachments+0x2200>
 109d904:	mov    0x20(%rcx),%r12
 109d908:	test   %r12,%r12
 109d90b:	je     109c156 <my.diagram_membership::compute_sub_block_attachments+0x2376>
 109d911:	mov    0x10(%rcx),%r13
 109d915:	mov    0xe8(%rsp),%rbx
 109d91d:	xor    %r15d,%r15d
 109d920:	jmp    109d950 <my.diagram_membership::compute_sub_block_attachments+0x3b70>
 109d922:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109d931:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109d940:	inc    %r15
 109d943:	add    $0x10,%rbx
 109d947:	cmp    %r15,%r12
 109d94a:	je     109c156 <my.diagram_membership::compute_sub_block_attachments+0x2376>
 109d950:	cmp    %r14,0x0(%r13,%r15,8)
 109d955:	jne    109d940 <my.diagram_membership::compute_sub_block_attachments+0x3b60>
 109d957:	mov    (%rbx),%rdi
 109d95a:	mov    0xf8(%rsp),%rsi
 109d962:	call   1044580 <myl_core_str_eq>
 109d967:	test   %al,%al
 109d969:	je     109d940 <my.diagram_membership::compute_sub_block_attachments+0x3b60>
 109d96b:	jmp    109c193 <my.diagram_membership::compute_sub_block_attachments+0x23b3>
 109d970:	lea    0x4e179(%rip),%rdi        # 10ebaf0 <core_durable_error.verbs+0x1530>
 109d977:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109d97c:	mov    $0x1,%al
 109d97e:	lea    -0x81d65(%rip),%rbp        # 101bc20 <core_number_pairs+0x146d0>
 109d985:	test   %al,%al
 109d987:	je     109c032 <my.diagram_membership::compute_sub_block_attachments+0x2252>
 109d98d:	mov    %rbp,%rdi
 109d990:	call   103c740 <myl_core_drop_owned>
 109d995:	lea    0x4e184(%rip),%rdi        # 10ebb20 <core_durable_error.verbs+0x1560>
 109d99c:	call   1042840 <myl_core_assert_fail>
 109d9a1:	mov    0x28(%rsp),%rdi
 109d9a6:	call   103c740 <myl_core_drop_owned>
 109d9ab:	mov    %r14,%rdi
 109d9ae:	call   103c740 <myl_core_drop_owned>
 109d9b3:	mov    0xc0(%rsp),%rax
 109d9bb:	add    $0x1b8,%rsp
 109d9c2:	pop    %rbx
 109d9c3:	pop    %r12
 109d9c5:	pop    %r13
 109d9c7:	pop    %r14
 109d9c9:	pop    %r15
 109d9cb:	pop    %rbp
 109d9cc:	ret
 109d9cd:	lea    0x50a5c(%rip),%rdi        # 10ee430 <core_durable_error.verbs+0x3e70>
 109d9d4:	mov    0xc8(%rsp),%rsi
 109d9dc:	call   103d4c0 <myl_core_trap>
 109d9e1:	call   103c740 <myl_core_drop_owned>
 109d9e6:	lea    0x4e133(%rip),%rdi        # 10ebb20 <core_durable_error.verbs+0x1560>
 109d9ed:	call   1042840 <myl_core_assert_fail>
 109d9f2:	mov    $0x10,%esi
 109d9f7:	mov    %rdi,%rbx
 109d9fa:	xor    %edi,%edi
 109d9fc:	call   103b980 <myl_core_list_new_slow>
 109da01:	mov    %rbx,%rdi
 109da04:	jmp    1099e26 <my.diagram_membership::compute_sub_block_attachments+0x46>
 109da09:	mov    %r8,%r13
 109da0c:	cmp    %r13,%rdx
 109da0f:	cmova  %rdx,%r13
 109da13:	lea    0x551e6(%rip),%rdi        # 10f2c00 <core_durable_error.verbs+0x8640>
 109da1a:	mov    %r13,%rsi
 109da1d:	call   103d4c0 <myl_core_trap>
 109da22:	mov    %r8,%r13
 109da25:	lea    0x551a4(%rip),%rdi        # 10f2bd0 <core_durable_error.verbs+0x8610>
 109da2c:	mov    %r13,%rsi
 109da2f:	mov    %rcx,%rdx
 109da32:	call   103d4c0 <myl_core_trap>
 109da37:	mov    $0x8,%esi
 109da3c:	xor    %edi,%edi
 109da3e:	call   103b980 <myl_core_list_new_slow>
 109da43:	mov    %rax,%rdi
 109da46:	jmp    109b331 <my.diagram_membership::compute_sub_block_attachments+0x1551>
 109da4b:	call   103c740 <myl_core_drop_owned>
 109da50:	lea    0x4e0c9(%rip),%rdi        # 10ebb20 <core_durable_error.verbs+0x1560>
 109da57:	call   1042840 <myl_core_assert_fail>
 109da5c:	call   103c740 <myl_core_drop_owned>
 109da61:	lea    0x4e0b8(%rip),%rdi        # 10ebb20 <core_durable_error.verbs+0x1560>
 109da68:	call   1042840 <myl_core_assert_fail>
 109da6d:	lea    0x50b0c(%rip),%rdi        # 10ee580 <core_durable_error.verbs+0x3fc0>
 109da74:	mov    0xe0(%rsp),%rsi
 109da7c:	mov    %r9,%rdx
 109da7f:	call   103d4c0 <myl_core_trap>
 109da84:	mov    %rsi,%rax
 109da87:	sar    $0x3f,%rax
 109da8b:	and    %rdx,%rax
 109da8e:	sub    %rax,%rsi
 109da91:	lea    0x50b18(%rip),%rdi        # 10ee5b0 <core_durable_error.verbs+0x3ff0>
 109da98:	call   103d4c0 <myl_core_trap>
 109da9d:	mov    %rbp,%rdi
 109daa0:	call   103c740 <myl_core_drop_owned>
 109daa5:	lea    0x50954(%rip),%rdi        # 10ee400 <core_durable_error.verbs+0x3e40>
 109daac:	xor    %esi,%esi
 109daae:	xor    %edx,%edx
 109dab0:	call   103d4c0 <myl_core_trap>
 109dab5:	mov    %r8,%r13
 109dab8:	lea    0x550e1(%rip),%rdi        # 10f2ba0 <core_durable_error.verbs+0x85e0>
 109dabf:	mov    %r13,%rsi
 109dac2:	mov    %rax,%rdx
 109dac5:	call   103d4c0 <myl_core_trap>
 109daca:	lea    0x5515f(%rip),%rdi        # 10f2c30 <core_durable_error.verbs+0x8670>
 109dad1:	movabs $0x7fffffffffffffff,%rsi
 109dadb:	mov    $0x1,%edx
 109dae0:	call   103d4c0 <myl_core_trap>
 109dae5:	lea    0x50a04(%rip),%rdi        # 10ee4f0 <core_durable_error.verbs+0x3f30>
 109daec:	mov    $0x1,%edx
 109daf1:	mov    %rax,%rsi
 109daf4:	call   103d4c0 <myl_core_trap>
 109daf9:	lea    0x50960(%rip),%rdi        # 10ee460 <core_durable_error.verbs+0x3ea0>
 109db00:	mov    0x78(%rsp),%rdx
 109db05:	call   103d4c0 <myl_core_trap>
 109db0a:	mov    %rsi,%rax
 109db0d:	sar    $0x3f,%rax
 109db11:	and    %rdx,%rax
 109db14:	sub    %rax,%rsi
 109db17:	lea    0x509a2(%rip),%rdi        # 10ee4c0 <core_durable_error.verbs+0x3f00>
 109db1e:	call   103d4c0 <myl_core_trap>
 109db23:	lea    0x50966(%rip),%rdi        # 10ee490 <core_durable_error.verbs+0x3ed0>
 109db2a:	mov    %rax,%rsi
 109db2d:	call   103d4c0 <myl_core_trap>
 109db32:	mov    %rbp,%rdi
 109db35:	call   103c740 <myl_core_drop_owned>
 109db3a:	lea    0x4dfdf(%rip),%rdi        # 10ebb20 <core_durable_error.verbs+0x1560>
 109db41:	call   1042840 <myl_core_assert_fail>
 109db46:	lea    0x509d3(%rip),%rdi        # 10ee520 <core_durable_error.verbs+0x3f60>
 109db4d:	call   103d4c0 <myl_core_trap>
 109db52:	lea    0x509f7(%rip),%rdi        # 10ee550 <core_durable_error.verbs+0x3f90>
 109db59:	mov    0x98(%rsp),%rsi
 109db61:	mov    %rax,%rdx
 109db64:	call   103d4c0 <myl_core_trap>
 109db69:	lea    0x50a70(%rip),%rdi        # 10ee5e0 <core_durable_error.verbs+0x4020>
 109db70:	call   103d4c0 <myl_core_trap>

Disassembly of section .plt:
