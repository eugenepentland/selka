
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/eda/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

0000000001099de0 <my.diagram_membership::compute_sub_block_attachments>:
 1099de0:	push   %rbp
 1099de1:	push   %r15
 1099de3:	push   %r14
 1099de5:	push   %r13
 1099de7:	push   %r12
 1099de9:	push   %rbx
 1099dea:	sub    $0x368,%rsp
 1099df1:	mov    %fs:0xfffffffffffffec8,%rax
 1099dfa:	test   %rax,%rax
 1099dfd:	je     109ea35 <my.diagram_membership::compute_sub_block_attachments+0x4c55>
 1099e03:	mov    (%rax),%rcx
 1099e06:	mov    %rcx,%fs:0xfffffffffffffec8
 1099e0f:	movl   $0x1000000,(%rax)
 1099e15:	vpxor  %xmm0,%xmm0,%xmm0
 1099e19:	vmovdqu %xmm0,0x8(%rax)
 1099e1e:	movq   $0x0,0x18(%rax)
 1099e26:	mov    0x30(%rdi),%rcx
 1099e2a:	mov    %rcx,0x100(%rsp)
 1099e32:	mov    0x8(%rcx),%rbx
 1099e36:	test   %rbx,%rbx
 1099e39:	je     109e9fe <my.diagram_membership::compute_sub_block_attachments+0x4c1e>
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
 1099ebd:	mov    0x100(%rsp),%rcx
 1099ec5:	cmpq   $0x0,0x8(%rcx)
 1099eca:	je     109e9fe <my.diagram_membership::compute_sub_block_attachments+0x4c1e>
 1099ed0:	mov    0x38(%rdi),%rcx
 1099ed4:	mov    %rcx,0xa0(%rsp)
 1099edc:	cmpq   $0x0,0x8(%rcx)
 1099ee1:	je     109e9fe <my.diagram_membership::compute_sub_block_attachments+0x4c1e>
 1099ee7:	mov    %rax,0x120(%rsp)
 1099eef:	lea    0x5e962(%rip),%rsi        # 10f8858 <core_durable_error.verbs+0xd258>
 1099ef6:	mov    %rdi,%rbx
 1099ef9:	xor    %edi,%edi
 1099efb:	call   1042f80 <myl_core_dict_new>
 1099f00:	mov    %rax,(%rsp)
 1099f04:	mov    0x60(%rbx),%rbx
 1099f08:	mov    0x8(%rbx),%rax
 1099f0c:	mov    %rax,0x80(%rsp)
 1099f14:	test   %rax,%rax
 1099f17:	je     109a9f0 <my.diagram_membership::compute_sub_block_attachments+0xc10>
 1099f1d:	add    $0x20,%rbx
 1099f21:	xor    %eax,%eax
 1099f23:	mov    %rbx,0x38(%rsp)
 1099f28:	jmp    1099f63 <my.diagram_membership::compute_sub_block_attachments+0x183>
 1099f2a:	nopw   0x0(%rax,%rax,1)
 1099f30:	mov    0x8(%rsp),%rdi
 1099f35:	call   103c740 <myl_core_drop_owned>
 1099f3a:	mov    (%rsp),%rax
 1099f3e:	mov    0x10(%rsp),%rcx
 1099f43:	mov    %rcx,0x28(%rax,%r12,1)
 1099f48:	mov    0x38(%rsp),%rbx
 1099f4d:	mov    0x20(%rsp),%rax
 1099f52:	inc    %rax
 1099f55:	cmp    0x80(%rsp),%rax
 1099f5d:	je     109a9f0 <my.diagram_membership::compute_sub_block_attachments+0xc10>
 1099f63:	mov    %rax,0x20(%rsp)
 1099f68:	shl    $0x4,%rax
 1099f6c:	mov    (%rbx,%rax,1),%r14
 1099f70:	mov    0x8(%rbx,%rax,1),%r15
 1099f75:	mov    %r14,%rdi
 1099f78:	lea    -0x7e93f(%rip),%r13        # 101b640 <core_number_pairs+0x140f0>
 1099f7f:	mov    %r13,%rsi
 1099f82:	call   1047e80 <myl_core_bytes_find>
 1099f87:	mov    %rax,%r12
 1099f8a:	mov    %r15,%rdi
 1099f8d:	mov    %r13,%rsi
 1099f90:	call   1047e80 <myl_core_bytes_find>
 1099f95:	mov    %rax,%r13
 1099f98:	test   %r12,%r12
 1099f9b:	sets   %al
 1099f9e:	test   %r13,%r13
 1099fa1:	setns  %cl
 1099fa4:	test   %cl,%al
 1099fa6:	je     1099fc0 <my.diagram_membership::compute_sub_block_attachments+0x1e0>
 1099fa8:	mov    %r14,%rdi
 1099fab:	call   103cfc0 <myl_core_owned_octets_copy>
 1099fb0:	mov    %rax,%rbx
 1099fb3:	mov    %r15,%rdi
 1099fb6:	xor    %esi,%esi
 1099fb8:	mov    %r13,%rdx
 1099fbb:	jmp    1099fea <my.diagram_membership::compute_sub_block_attachments+0x20a>
 1099fbd:	nopl   (%rax)
 1099fc0:	test   %r13,%r13
 1099fc3:	sets   %al
 1099fc6:	test   %r12,%r12
 1099fc9:	setns  %cl
 1099fcc:	and    %al,%cl
 1099fce:	cmp    $0x1,%cl
 1099fd1:	jne    1099f4d <my.diagram_membership::compute_sub_block_attachments+0x16d>
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
 1099ffd:	js     109a9a5 <my.diagram_membership::compute_sub_block_attachments+0xbc5>
 109a003:	mov    %rbx,%rdi
 109a006:	call   104bb00 <myl_core_bytes_decode_text>
 109a00b:	mov    %rax,%rbp
 109a00e:	xor    %eax,%eax
 109a010:	mov    %rbp,0x10(%rsp)
 109a015:	test   %al,%al
 109a017:	jne    109eb94 <my.diagram_membership::compute_sub_block_attachments+0x4db4>
 109a01d:	mov    %rbx,%rdi
 109a020:	call   103c740 <myl_core_drop_owned>
 109a025:	mov    %rbp,0x248(%rsp)
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
 109a05d:	mov    (%rsp),%rax
 109a061:	mov    0x18(%rax),%rcx
 109a065:	mov    0x8(%rcx),%rax
 109a069:	test   %rax,%rax
 109a06c:	mov    %rbp,0x8(%rsp)
 109a071:	mov    %r13,0x70(%rsp)
 109a076:	je     109a160 <my.diagram_membership::compute_sub_block_attachments+0x380>
 109a07c:	mov    (%rax),%ecx
 109a07e:	tzcnt  %ecx,%edx
 109a082:	neg    %dl
 109a084:	shrx   %rdx,%rbx,%r14
 109a089:	vmovdqu 0x10(%rax,%r14,1),%xmm1
 109a090:	mov    %ebx,%edx
 109a092:	and    $0x7f,%dl
 109a095:	vmovd  %edx,%xmm0
 109a099:	vpbroadcastb %xmm0,%xmm0
 109a09e:	vmovdqa %xmm1,0x40(%rsp)
 109a0a4:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109a0a8:	vpmovmskb %xmm0,%edx
 109a0ac:	test   %edx,%edx
 109a0ae:	je     109a137 <my.diagram_membership::compute_sub_block_attachments+0x357>
 109a0b4:	lea    -0x1(%rcx),%ebp
 109a0b7:	add    $0x1e,%ecx
 109a0ba:	and    $0xfffffff0,%ecx
 109a0bd:	lea    (%rax,%rcx,1),%r15
 109a0c1:	add    $0x10,%r15
 109a0c5:	movzwl %dx,%r12d
 109a0c9:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a0d8:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a0e7:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a0f6:	cs nopw 0x0(%rax,%rax,1)
 109a100:	tzcnt  %r12d,%eax
 109a105:	add    %r14d,%eax
 109a108:	and    %ebp,%eax
 109a10a:	mov    (%r15,%rax,4),%eax
 109a10e:	shl    $0x4,%rax
 109a112:	mov    (%rsp),%rcx
 109a116:	mov    0x20(%rcx,%rax,1),%rdi
 109a11b:	mov    0x248(%rsp),%rsi
 109a123:	call   1044580 <myl_core_str_eq>
 109a128:	test   %al,%al
 109a12a:	jne    109a542 <my.diagram_membership::compute_sub_block_attachments+0x762>
 109a130:	blsr   %r12d,%r12d
 109a135:	jne    109a100 <my.diagram_membership::compute_sub_block_attachments+0x320>
 109a137:	vmovdqa 0x40(%rsp),%xmm0
 109a13d:	vpcmpeqb -0x95d75(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109a145:	vpmovmskb %xmm0,%eax
 109a149:	test   %eax,%eax
 109a14b:	mov    0x8(%rsp),%rbp
 109a150:	jne    109a1f0 <my.diagram_membership::compute_sub_block_attachments+0x410>
 109a156:	jmp    109a167 <my.diagram_membership::compute_sub_block_attachments+0x387>
 109a158:	nopl   0x0(%rax,%rax,1)
 109a160:	cmpq   $0x0,0x18(%rcx)
 109a165:	je     109a189 <my.diagram_membership::compute_sub_block_attachments+0x3a9>
 109a167:	mov    (%rsp),%rdi
 109a16b:	lea    0x248(%rsp),%rsi
 109a173:	mov    %rbx,%rdx
 109a176:	call   1042bc0 <myl_core_dict_find>
 109a17b:	mov    %rax,%r13
 109a17e:	test   %r13,%r13
 109a181:	jns    109a5a1 <my.diagram_membership::compute_sub_block_attachments+0x7c1>
 109a187:	jmp    109a1f0 <my.diagram_membership::compute_sub_block_attachments+0x410>
 109a189:	mov    0x20(%rcx),%r14
 109a18d:	test   %r14,%r14
 109a190:	je     109a1f0 <my.diagram_membership::compute_sub_block_attachments+0x410>
 109a192:	mov    0x10(%rcx),%r15
 109a196:	mov    (%rsp),%rax
 109a19a:	lea    0x20(%rax),%r12
 109a19e:	xor    %r13d,%r13d
 109a1a1:	jmp    109a1cc <my.diagram_membership::compute_sub_block_attachments+0x3ec>
 109a1a3:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a1b2:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a1c0:	inc    %r13
 109a1c3:	add    $0x10,%r12
 109a1c7:	cmp    %r13,%r14
 109a1ca:	je     109a1f0 <my.diagram_membership::compute_sub_block_attachments+0x410>
 109a1cc:	cmp    %rbx,(%r15,%r13,8)
 109a1d0:	jne    109a1c0 <my.diagram_membership::compute_sub_block_attachments+0x3e0>
 109a1d2:	mov    (%r12),%rdi
 109a1d6:	mov    0x248(%rsp),%rsi
 109a1de:	call   1044580 <myl_core_str_eq>
 109a1e3:	test   %al,%al
 109a1e5:	je     109a1c0 <my.diagram_membership::compute_sub_block_attachments+0x3e0>
 109a1e7:	jmp    109a17e <my.diagram_membership::compute_sub_block_attachments+0x39e>
 109a1e9:	nopl   0x0(%rax)
 109a1f0:	xor    %edi,%edi
 109a1f2:	lea    0x5e4a7(%rip),%rsi        # 10f86a0 <core_durable_error.verbs+0xd0a0>
 109a1f9:	call   1042f80 <myl_core_dict_new>
 109a1fe:	mov    %rax,%rbx
 109a201:	mov    0x8(%rbp),%r13
 109a205:	mov    0x10(%rsp),%rdi
 109a20a:	add    $0x20,%rdi
 109a20e:	mov    %rdi,0x10(%rsp)
 109a213:	mov    %r13,%rsi
 109a216:	call   10442c0 <myl_core_span_hash>
 109a21b:	mov    %eax,%eax
 109a21d:	movabs $0x9e3779b97f4a7c15,%rcx
 109a227:	imul   %rcx,%rax
 109a22b:	mov    %rax,%r15
 109a22e:	shr    $0x20,%r15
 109a232:	xor    %rax,%r15
 109a235:	mov    (%rsp),%rax
 109a239:	mov    0x18(%rax),%rcx
 109a23d:	mov    0x8(%rcx),%rax
 109a241:	test   %rax,%rax
 109a244:	mov    %rbx,0x40(%rsp)
 109a249:	je     109a3b8 <my.diagram_membership::compute_sub_block_attachments+0x5d8>
 109a24f:	mov    (%rax),%ecx
 109a251:	tzcnt  %ecx,%edx
 109a255:	neg    %dl
 109a257:	shrx   %rdx,%r15,%rbp
 109a25c:	lea    -0x1(%rcx),%r12d
 109a260:	vmovdqu 0x10(%rax,%rbp,1),%xmm1
 109a266:	and    $0x7f,%r15b
 109a26a:	vmovd  %r15d,%xmm0
 109a26f:	vpbroadcastb %xmm0,%xmm0
 109a274:	vmovdqa %xmm1,0x60(%rsp)
 109a27a:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109a27e:	vpmovmskb %xmm0,%edx
 109a282:	test   %edx,%edx
 109a284:	mov    0x10(%rsp),%rsi
 109a289:	je     109a38b <my.diagram_membership::compute_sub_block_attachments+0x5ab>
 109a28f:	add    $0x1e,%ecx
 109a292:	and    $0xfffffff0,%ecx
 109a295:	lea    (%rax,%rcx,1),%r14
 109a299:	add    $0x10,%r14
 109a29d:	movzwl %dx,%r15d
 109a2a1:	mov    %r13,%rax
 109a2a4:	shr    $1,%rax
 109a2a7:	mov    %rax,0x30(%rsp)
 109a2ac:	jmp    109a2e5 <my.diagram_membership::compute_sub_block_attachments+0x505>
 109a2ae:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a2bd:	nopl   (%rax)
 109a2c0:	mov    0x10(%rsp),%rsi
 109a2c5:	mov    %r13,%rdx
 109a2c8:	call   10ea030 <bcmp@plt>
 109a2cd:	mov    0x10(%rsp),%rsi
 109a2d2:	test   %eax,%eax
 109a2d4:	je     109a51d <my.diagram_membership::compute_sub_block_attachments+0x73d>
 109a2da:	blsr   %r15d,%r15d
 109a2df:	je     109a38b <my.diagram_membership::compute_sub_block_attachments+0x5ab>
 109a2e5:	tzcnt  %r15d,%eax
 109a2ea:	add    %ebp,%eax
 109a2ec:	and    %r12d,%eax
 109a2ef:	mov    (%r14,%rax,4),%ebx
 109a2f3:	mov    %rbx,%rax
 109a2f6:	shl    $0x4,%rax
 109a2fa:	mov    (%rsp),%rcx
 109a2fe:	mov    0x20(%rcx,%rax,1),%rdi
 109a303:	cmp    %r13,0x8(%rdi)
 109a307:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a309:	add    $0x20,%rdi
 109a30d:	cmp    $0x10,%r13
 109a311:	ja     109a2c0 <my.diagram_membership::compute_sub_block_attachments+0x4e0>
 109a313:	cmp    $0x8,%r13
 109a317:	jb     109a332 <my.diagram_membership::compute_sub_block_attachments+0x552>
 109a319:	mov    (%rdi),%rax
 109a31c:	cmp    (%rsi),%rax
 109a31f:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a321:	mov    -0x8(%rsi,%r13,1),%rax
 109a326:	cmp    %rax,-0x8(%rdi,%r13,1)
 109a32b:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a32d:	jmp    109a51d <my.diagram_membership::compute_sub_block_attachments+0x73d>
 109a332:	cmp    $0x4,%r13
 109a336:	jb     109a34f <my.diagram_membership::compute_sub_block_attachments+0x56f>
 109a338:	mov    (%rdi),%eax
 109a33a:	cmp    (%rsi),%eax
 109a33c:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a33e:	mov    -0x4(%rsi,%r13,1),%eax
 109a343:	cmp    %eax,-0x4(%rdi,%r13,1)
 109a348:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a34a:	jmp    109a51d <my.diagram_membership::compute_sub_block_attachments+0x73d>
 109a34f:	test   %r13,%r13
 109a352:	je     109a51d <my.diagram_membership::compute_sub_block_attachments+0x73d>
 109a358:	movzbl (%rdi),%eax
 109a35b:	cmp    (%rsi),%al
 109a35d:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a363:	mov    0x30(%rsp),%rcx
 109a368:	movzbl (%rsi,%rcx,1),%eax
 109a36c:	cmp    %al,(%rdi,%rcx,1)
 109a36f:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a375:	movzbl -0x1(%rsi,%r13,1),%eax
 109a37b:	cmp    %al,-0x1(%rdi,%r13,1)
 109a380:	jne    109a2da <my.diagram_membership::compute_sub_block_attachments+0x4fa>
 109a386:	jmp    109a51d <my.diagram_membership::compute_sub_block_attachments+0x73d>
 109a38b:	vmovdqa 0x60(%rsp),%xmm0
 109a391:	vpcmpeqb -0x95fc9(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109a399:	vpmovmskb %xmm0,%eax
 109a39d:	test   %eax,%eax
 109a39f:	je     109a4fc <my.diagram_membership::compute_sub_block_attachments+0x71c>
 109a3a5:	tzcnt  %eax,%r14d
 109a3aa:	add    %ebp,%r14d
 109a3ad:	and    %r12d,%r14d
 109a3b0:	not    %r14
 109a3b3:	jmp    109a550 <my.diagram_membership::compute_sub_block_attachments+0x770>
 109a3b8:	mov    0x20(%rcx),%r12
 109a3bc:	mov    $0xffffffffffffffff,%r14
 109a3c3:	test   %r12,%r12
 109a3c6:	mov    0x10(%rsp),%rsi
 109a3cb:	je     109a550 <my.diagram_membership::compute_sub_block_attachments+0x770>
 109a3d1:	mov    0x10(%rcx),%rbp
 109a3d5:	mov    0x18(%rcx),%rdx
 109a3d9:	mov    %r13,%rax
 109a3dc:	shr    $1,%rax
 109a3df:	mov    %rax,0x30(%rsp)
 109a3e4:	mov    (%rsp),%rax
 109a3e8:	lea    0x20(%rax),%r14
 109a3ec:	xor    %ebx,%ebx
 109a3ee:	mov    %rdx,0x60(%rsp)
 109a3f3:	jmp    109a450 <my.diagram_membership::compute_sub_block_attachments+0x670>
 109a3f5:	mov    0x10(%rsp),%rsi
 109a3fa:	mov    %r13,%rdx
 109a3fd:	call   10ea030 <bcmp@plt>
 109a402:	mov    0x60(%rsp),%rdx
 109a407:	mov    0x10(%rsp),%rsi
 109a40c:	test   %eax,%eax
 109a40e:	je     109a515 <my.diagram_membership::compute_sub_block_attachments+0x735>
 109a414:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a423:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a432:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a440:	inc    %rbx
 109a443:	add    $0x10,%r14
 109a447:	cmp    %rbx,%r12
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
 109a474:	cmp    %r13,0x8(%rdi)
 109a478:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a47a:	add    $0x20,%rdi
 109a47e:	cmp    $0x10,%r13
 109a482:	ja     109a3f5 <my.diagram_membership::compute_sub_block_attachments+0x615>
 109a488:	cmp    $0x8,%r13
 109a48c:	jb     109a4a4 <my.diagram_membership::compute_sub_block_attachments+0x6c4>
 109a48e:	mov    (%rdi),%rax
 109a491:	cmp    (%rsi),%rax
 109a494:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a496:	mov    -0x8(%rsi,%r13,1),%rax
 109a49b:	cmp    %rax,-0x8(%rdi,%r13,1)
 109a4a0:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4a2:	jmp    109a515 <my.diagram_membership::compute_sub_block_attachments+0x735>
 109a4a4:	cmp    $0x4,%r13
 109a4a8:	jb     109a4be <my.diagram_membership::compute_sub_block_attachments+0x6de>
 109a4aa:	mov    (%rdi),%eax
 109a4ac:	cmp    (%rsi),%eax
 109a4ae:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4b0:	mov    -0x4(%rsi,%r13,1),%eax
 109a4b5:	cmp    %eax,-0x4(%rdi,%r13,1)
 109a4ba:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4bc:	jmp    109a515 <my.diagram_membership::compute_sub_block_attachments+0x735>
 109a4be:	test   %r13,%r13
 109a4c1:	je     109a515 <my.diagram_membership::compute_sub_block_attachments+0x735>
 109a4c3:	movzbl (%rdi),%eax
 109a4c6:	cmp    (%rsi),%al
 109a4c8:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4ce:	mov    0x30(%rsp),%rcx
 109a4d3:	movzbl (%rsi,%rcx,1),%eax
 109a4d7:	cmp    %al,(%rdi,%rcx,1)
 109a4da:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4e0:	movzbl -0x1(%rsi,%r13,1),%eax
 109a4e6:	cmp    %al,-0x1(%rdi,%r13,1)
 109a4eb:	jne    109a440 <my.diagram_membership::compute_sub_block_attachments+0x660>
 109a4f1:	jmp    109a515 <my.diagram_membership::compute_sub_block_attachments+0x735>
 109a4f3:	mov    $0xffffffffffffffff,%r14
 109a4fa:	jmp    109a550 <my.diagram_membership::compute_sub_block_attachments+0x770>
 109a4fc:	mov    (%rsp),%rdi
 109a500:	mov    0x10(%rsp),%rsi
 109a505:	mov    %r13,%rdx
 109a508:	call   1043f00 <myl_core_dict_find_span>
 109a50d:	mov    0x10(%rsp),%rsi
 109a512:	mov    %rax,%rbx
 109a515:	mov    %rbx,%r14
 109a518:	test   %rbx,%rbx
 109a51b:	js     109a550 <my.diagram_membership::compute_sub_block_attachments+0x770>
 109a51d:	mov    0x40(%rsp),%rax
 109a522:	mov    %rax,0x360(%rsp)
 109a52a:	mov    (%rsp),%rdi
 109a52e:	mov    %rbx,%rsi
 109a531:	lea    0x360(%rsp),%rdx
 109a539:	call   1043040 <myl_core_dict_set>
 109a53e:	mov    %rax,(%rsp)
 109a542:	mov    0x8(%rsp),%rbp
 109a547:	jmp    109a5a1 <my.diagram_membership::compute_sub_block_attachments+0x7c1>
 109a549:	nopl   0x0(%rax)
 109a550:	mov    0x8(%rsp),%rbp
 109a555:	mov    0x0(%rbp),%edx
 109a558:	shr    $0x8,%edx
 109a55b:	and    $0x1,%edx
 109a55e:	mov    %rsi,%rdi
 109a561:	mov    %r13,%rsi
 109a564:	call   1044c80 <myl_core_ir_str_from_span>
 109a569:	mov    %rax,0x358(%rsp)
 109a571:	mov    0x40(%rsp),%rax
 109a576:	mov    %rax,0x350(%rsp)
 109a57e:	mov    (%rsp),%rdi
 109a582:	mov    %r14,%rsi
 109a585:	lea    0x358(%rsp),%rdx
 109a58d:	lea    0x350(%rsp),%rcx
 109a595:	xor    %r8d,%r8d
 109a598:	call   1043240 <myl_core_dict_insert>
 109a59d:	mov    %rax,(%rsp)
 109a5a1:	mov    %rbp,0x240(%rsp)
 109a5a9:	testb  $0x2,0x1(%rbp)
 109a5ad:	jne    109a5c0 <my.diagram_membership::compute_sub_block_attachments+0x7e0>
 109a5af:	mov    %rbp,%rdi
 109a5b2:	call   1044400 <myl_core_str_hash>
 109a5b7:	jmp    109a5c3 <my.diagram_membership::compute_sub_block_attachments+0x7e3>
 109a5b9:	nopl   0x0(%rax)
 109a5c0:	mov    0x18(%rbp),%eax
 109a5c3:	mov    %eax,%eax
 109a5c5:	movabs $0x9e3779b97f4a7c15,%rcx
 109a5cf:	imul   %rcx,%rax
 109a5d3:	mov    %rax,%rbx
 109a5d6:	shr    $0x20,%rbx
 109a5da:	xor    %rax,%rbx
 109a5dd:	mov    (%rsp),%rax
 109a5e1:	mov    0x18(%rax),%rcx
 109a5e5:	mov    0x8(%rcx),%rax
 109a5e9:	test   %rax,%rax
 109a5ec:	je     109a6a0 <my.diagram_membership::compute_sub_block_attachments+0x8c0>
 109a5f2:	mov    (%rax),%ecx
 109a5f4:	tzcnt  %ecx,%edx
 109a5f8:	neg    %dl
 109a5fa:	shrx   %rdx,%rbx,%r14
 109a5ff:	vmovdqu 0x10(%rax,%r14,1),%xmm1
 109a606:	mov    %ebx,%edx
 109a608:	and    $0x7f,%dl
 109a60b:	vmovd  %edx,%xmm0
 109a60f:	vpbroadcastb %xmm0,%xmm0
 109a614:	vmovdqa %xmm1,0x10(%rsp)
 109a61a:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109a61e:	vpmovmskb %xmm0,%edx
 109a622:	test   %edx,%edx
 109a624:	je     109a677 <my.diagram_membership::compute_sub_block_attachments+0x897>
 109a626:	lea    -0x1(%rcx),%ebp
 109a629:	add    $0x1e,%ecx
 109a62c:	and    $0xfffffff0,%ecx
 109a62f:	lea    (%rax,%rcx,1),%r15
 109a633:	add    $0x10,%r15
 109a637:	movzwl %dx,%r13d
 109a63b:	nopl   0x0(%rax,%rax,1)
 109a640:	tzcnt  %r13d,%eax
 109a645:	add    %r14d,%eax
 109a648:	and    %ebp,%eax
 109a64a:	mov    (%r15,%rax,4),%r12d
 109a64e:	shl    $0x4,%r12
 109a652:	mov    (%rsp),%rax
 109a656:	mov    0x20(%rax,%r12,1),%rdi
 109a65b:	mov    0x240(%rsp),%rsi
 109a663:	call   1044580 <myl_core_str_eq>
 109a668:	test   %al,%al
 109a66a:	jne    109a854 <my.diagram_membership::compute_sub_block_attachments+0xa74>
 109a670:	blsr   %r13d,%r13d
 109a675:	jne    109a640 <my.diagram_membership::compute_sub_block_attachments+0x860>
 109a677:	vmovdqa 0x10(%rsp),%xmm0
 109a67d:	vpcmpeqb -0x962b5(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109a685:	vpmovmskb %xmm0,%eax
 109a689:	test   %eax,%eax
 109a68b:	mov    0x8(%rsp),%rbp
 109a690:	je     109a6ab <my.diagram_membership::compute_sub_block_attachments+0x8cb>
 109a692:	jmp    109eb04 <my.diagram_membership::compute_sub_block_attachments+0x4d24>
 109a697:	nopw   0x0(%rax,%rax,1)
 109a6a0:	cmpq   $0x0,0x18(%rcx)
 109a6a5:	je     109a868 <my.diagram_membership::compute_sub_block_attachments+0xa88>
 109a6ab:	mov    (%rsp),%rdi
 109a6af:	lea    0x240(%rsp),%rsi
 109a6b7:	mov    %rbx,%rdx
 109a6ba:	call   1042bc0 <myl_core_dict_find>
 109a6bf:	mov    %rax,%r12
 109a6c2:	mov    %rbp,%rdi
 109a6c5:	call   103c740 <myl_core_drop_owned>
 109a6ca:	test   %r12,%r12
 109a6cd:	mov    0x70(%rsp),%rbx
 109a6d2:	js     109eb0c <my.diagram_membership::compute_sub_block_attachments+0x4d2c>
 109a6d8:	shl    $0x4,%r12
 109a6dc:	mov    %rbx,%rdi
 109a6df:	call   104ba40 <myl_core_bytes_utf8_count>
 109a6e4:	test   %rax,%rax
 109a6e7:	js     109a9bf <my.diagram_membership::compute_sub_block_attachments+0xbdf>
 109a6ed:	mov    %rbx,%rdi
 109a6f0:	call   104bb00 <myl_core_bytes_decode_text>
 109a6f5:	mov    %rax,%r14
 109a6f8:	xor    %eax,%eax
 109a6fa:	test   %al,%al
 109a6fc:	jne    109a9dc <my.diagram_membership::compute_sub_block_attachments+0xbfc>
 109a702:	mov    %rbx,%rdi
 109a705:	call   103c740 <myl_core_drop_owned>
 109a70a:	mov    (%rsp),%rax
 109a70e:	mov    0x28(%rax,%r12,1),%rax
 109a713:	mov    %rax,0x10(%rsp)
 109a718:	mov    %r14,0x238(%rsp)
 109a720:	testb  $0x2,0x1(%r14)
 109a725:	mov    %r14,0x8(%rsp)
 109a72a:	jne    109a740 <my.diagram_membership::compute_sub_block_attachments+0x960>
 109a72c:	mov    %r14,%rdi
 109a72f:	call   1044400 <myl_core_str_hash>
 109a734:	jmp    109a744 <my.diagram_membership::compute_sub_block_attachments+0x964>
 109a736:	cs nopw 0x0(%rax,%rax,1)
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
 109a799:	vmovdqa %xmm1,0x70(%rsp)
 109a79f:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109a7a3:	vpmovmskb %xmm0,%edx
 109a7a7:	test   %edx,%edx
 109a7a9:	je     109a7f4 <my.diagram_membership::compute_sub_block_attachments+0xa14>
 109a7ab:	add    $0x1e,%ecx
 109a7ae:	and    $0xfffffff0,%ecx
 109a7b1:	lea    (%rax,%rcx,1),%r13
 109a7b5:	add    $0x10,%r13
 109a7b9:	movzwl %dx,%r14d
 109a7bd:	nopl   (%rax)
 109a7c0:	tzcnt  %r14d,%eax
 109a7c5:	add    %ebp,%eax
 109a7c7:	and    %ebx,%eax
 109a7c9:	mov    0x0(%r13,%rax,4),%eax
 109a7ce:	mov    0x10(%rsp),%rcx
 109a7d3:	mov    0x20(%rcx,%rax,8),%rdi
 109a7d8:	mov    0x238(%rsp),%rsi
 109a7e0:	call   1044580 <myl_core_str_eq>
 109a7e5:	test   %al,%al
 109a7e7:	jne    1099f30 <my.diagram_membership::compute_sub_block_attachments+0x150>
 109a7ed:	blsr   %r14d,%r14d
 109a7f2:	jne    109a7c0 <my.diagram_membership::compute_sub_block_attachments+0x9e0>
 109a7f4:	vmovdqa 0x70(%rsp),%xmm0
 109a7fa:	vpcmpeqb -0x96432(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109a802:	vpmovmskb %xmm0,%eax
 109a806:	test   %eax,%eax
 109a808:	je     109a82b <my.diagram_membership::compute_sub_block_attachments+0xa4b>
 109a80a:	tzcnt  %eax,%r13d
 109a80f:	add    %ebp,%r13d
 109a812:	and    %ebx,%r13d
 109a815:	not    %r13
 109a818:	jmp    109a970 <my.diagram_membership::compute_sub_block_attachments+0xb90>
 109a81d:	nopl   (%rax)
 109a820:	cmpq   $0x0,0x18(%rcx)
 109a825:	je     109a8f0 <my.diagram_membership::compute_sub_block_attachments+0xb10>
 109a82b:	mov    0x10(%rsp),%rdi
 109a830:	lea    0x238(%rsp),%rsi
 109a838:	mov    %r15,%rdx
 109a83b:	call   1042bc0 <myl_core_dict_find>
 109a840:	mov    %rax,%rbp
 109a843:	mov    %rbp,%r13
 109a846:	test   %rbp,%rbp
 109a849:	jns    1099f30 <my.diagram_membership::compute_sub_block_attachments+0x150>
 109a84f:	jmp    109a970 <my.diagram_membership::compute_sub_block_attachments+0xb90>
 109a854:	mov    0x8(%rsp),%rdi
 109a859:	call   103c740 <myl_core_drop_owned>
 109a85e:	mov    0x70(%rsp),%rbx
 109a863:	jmp    109a6dc <my.diagram_membership::compute_sub_block_attachments+0x8fc>
 109a868:	mov    0x20(%rcx),%r14
 109a86c:	test   %r14,%r14
 109a86f:	je     109eb04 <my.diagram_membership::compute_sub_block_attachments+0x4d24>
 109a875:	mov    0x10(%rcx),%r15
 109a879:	mov    (%rsp),%rax
 109a87d:	lea    0x20(%rax),%r13
 109a881:	xor    %r12d,%r12d
 109a884:	jmp    109a8d0 <my.diagram_membership::compute_sub_block_attachments+0xaf0>
 109a886:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a895:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a8a4:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a8b3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109a8c0:	inc    %r12
 109a8c3:	add    $0x10,%r13
 109a8c7:	cmp    %r12,%r14
 109a8ca:	je     109eb04 <my.diagram_membership::compute_sub_block_attachments+0x4d24>
 109a8d0:	cmp    %rbx,(%r15,%r12,8)
 109a8d4:	jne    109a8c0 <my.diagram_membership::compute_sub_block_attachments+0xae0>
 109a8d6:	mov    0x0(%r13),%rdi
 109a8da:	mov    0x240(%rsp),%rsi
 109a8e2:	call   1044580 <myl_core_str_eq>
 109a8e7:	test   %al,%al
 109a8e9:	je     109a8c0 <my.diagram_membership::compute_sub_block_attachments+0xae0>
 109a8eb:	jmp    109a6c2 <my.diagram_membership::compute_sub_block_attachments+0x8e2>
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
 109a958:	mov    0x238(%rsp),%rsi
 109a960:	call   1044580 <myl_core_str_eq>
 109a965:	test   %al,%al
 109a967:	je     109a940 <my.diagram_membership::compute_sub_block_attachments+0xb60>
 109a969:	jmp    109a843 <my.diagram_membership::compute_sub_block_attachments+0xa63>
 109a96e:	xchg   %ax,%ax
 109a970:	mov    0x8(%rsp),%rax
 109a975:	mov    %rax,0x348(%rsp)
 109a97d:	mov    0x10(%rsp),%rdi
 109a982:	mov    %r13,%rsi
 109a985:	lea    0x348(%rsp),%rdx
 109a98d:	xor    %ecx,%ecx
 109a98f:	xor    %r8d,%r8d
 109a992:	call   1043240 <myl_core_dict_insert>
 109a997:	mov    (%rsp),%rcx
 109a99b:	mov    %rax,0x28(%rcx,%r12,1)
 109a9a0:	jmp    1099f48 <my.diagram_membership::compute_sub_block_attachments+0x168>
 109a9a5:	lea    0x52184(%rip),%rdi        # 10ecb30 <core_durable_error.verbs+0x1530>
 109a9ac:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109a9b1:	mov    $0x1,%al
 109a9b3:	lea    -0x7ed9a(%rip),%rbp        # 101bc20 <core_number_pairs+0x146d0>
 109a9ba:	jmp    109a010 <my.diagram_membership::compute_sub_block_attachments+0x230>
 109a9bf:	lea    0x5216a(%rip),%rdi        # 10ecb30 <core_durable_error.verbs+0x1530>
 109a9c6:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109a9cb:	mov    $0x1,%al
 109a9cd:	lea    -0x7edb4(%rip),%r14        # 101bc20 <core_number_pairs+0x146d0>
 109a9d4:	test   %al,%al
 109a9d6:	je     109a702 <my.diagram_membership::compute_sub_block_attachments+0x922>
 109a9dc:	mov    %r14,%rdi
 109a9df:	call   103c740 <myl_core_drop_owned>
 109a9e4:	lea    0x52175(%rip),%rdi        # 10ecb60 <core_durable_error.verbs+0x1560>
 109a9eb:	call   1042840 <myl_core_assert_fail>
 109a9f0:	lea    0x5dd21(%rip),%rsi        # 10f8718 <core_durable_error.verbs+0xd118>
 109a9f7:	xor    %edi,%edi
 109a9f9:	call   1042f80 <myl_core_dict_new>
 109a9fe:	mov    %rax,0x60(%rsp)
 109aa03:	mov    0x100(%rsp),%rax
 109aa0b:	cmpq   $0x0,0x8(%rax)
 109aa10:	je     109acde <my.diagram_membership::compute_sub_block_attachments+0xefe>
 109aa16:	add    $0x20,%rax
 109aa1a:	mov    %rax,0x70(%rsp)
 109aa1f:	xor    %ebx,%ebx
 109aa21:	jmp    109aaac <my.diagram_membership::compute_sub_block_attachments+0xccc>
 109aa26:	cs nopw 0x0(%rax,%rax,1)
 109aa30:	vmovdqa 0x20(%rsp),%xmm0
 109aa36:	vpcmpeqb -0x9666e(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109aa3e:	vpmovmskb %xmm0,%eax
 109aa42:	test   %eax,%eax
 109aa44:	je     109ac07 <my.diagram_membership::compute_sub_block_attachments+0xe27>
 109aa4a:	tzcnt  %eax,%r15d
 109aa4f:	add    %ebx,%r15d
 109aa52:	and    %r13d,%r15d
 109aa55:	not    %r15
 109aa58:	mov    0x8(%rsp),%rax
 109aa5d:	mov    %rax,0x340(%rsp)
 109aa65:	mov    0x10(%rsp),%rbx
 109aa6a:	mov    %rbx,0x338(%rsp)
 109aa72:	mov    0x60(%rsp),%rdi
 109aa77:	mov    %r15,%rsi
 109aa7a:	lea    0x340(%rsp),%rdx
 109aa82:	lea    0x338(%rsp),%rcx
 109aa8a:	xor    %r8d,%r8d
 109aa8d:	call   1043240 <myl_core_dict_insert>
 109aa92:	mov    %rax,0x60(%rsp)
 109aa97:	inc    %rbx
 109aa9a:	mov    0x100(%rsp),%rax
 109aaa2:	cmp    0x8(%rax),%rbx
 109aaa6:	jae    109acde <my.diagram_membership::compute_sub_block_attachments+0xefe>
 109aaac:	imul   $0x428,%rbx,%rax
 109aab3:	mov    0x70(%rsp),%rcx
 109aab8:	mov    (%rcx,%rax,1),%r15
 109aabc:	mov    %r15,%rdi
 109aabf:	call   104ba40 <myl_core_bytes_utf8_count>
 109aac4:	test   %rax,%rax
 109aac7:	js     109acb0 <my.diagram_membership::compute_sub_block_attachments+0xed0>
 109aacd:	mov    %r15,%rdi
 109aad0:	call   104bb00 <myl_core_bytes_decode_text>
 109aad5:	mov    %rax,%rdi
 109aad8:	xor    %eax,%eax
 109aada:	test   %al,%al
 109aadc:	jne    109accd <my.diagram_membership::compute_sub_block_attachments+0xeed>
 109aae2:	mov    %rdi,0x230(%rsp)
 109aaea:	testb  $0x2,0x1(%rdi)
 109aaee:	mov    %rbx,0x10(%rsp)
 109aaf3:	mov    %rdi,0x8(%rsp)
 109aaf8:	jne    109ab10 <my.diagram_membership::compute_sub_block_attachments+0xd30>
 109aafa:	call   1044400 <myl_core_str_hash>
 109aaff:	jmp    109ab13 <my.diagram_membership::compute_sub_block_attachments+0xd33>
 109ab01:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ab10:	mov    0x18(%rdi),%eax
 109ab13:	mov    %eax,%eax
 109ab15:	movabs $0x9e3779b97f4a7c15,%rcx
 109ab1f:	imul   %rcx,%rax
 109ab23:	mov    %rax,%rbp
 109ab26:	shr    $0x20,%rbp
 109ab2a:	xor    %rax,%rbp
 109ab2d:	mov    0x60(%rsp),%rax
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
 109ab68:	vmovdqa %xmm1,0x20(%rsp)
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
 109abd2:	mov    0x60(%rsp),%rax
 109abd7:	mov    0x20(%rax,%r12,1),%rdi
 109abdc:	mov    0x230(%rsp),%rsi
 109abe4:	call   1044580 <myl_core_str_eq>
 109abe9:	test   %al,%al
 109abeb:	jne    109ac28 <my.diagram_membership::compute_sub_block_attachments+0xe48>
 109abed:	blsr   %r14d,%r14d
 109abf2:	jne    109abc0 <my.diagram_membership::compute_sub_block_attachments+0xde0>
 109abf4:	jmp    109aa30 <my.diagram_membership::compute_sub_block_attachments+0xc50>
 109abf9:	nopl   0x0(%rax)
 109ac00:	cmpq   $0x0,0x18(%rcx)
 109ac05:	je     109ac4e <my.diagram_membership::compute_sub_block_attachments+0xe6e>
 109ac07:	mov    0x60(%rsp),%rdi
 109ac0c:	lea    0x230(%rsp),%rsi
 109ac14:	mov    %rbp,%rdx
 109ac17:	call   1042bc0 <myl_core_dict_find>
 109ac1c:	mov    %rax,%r12
 109ac1f:	test   %r12,%r12
 109ac22:	js     109ac46 <my.diagram_membership::compute_sub_block_attachments+0xe66>
 109ac24:	shl    $0x4,%r12
 109ac28:	mov    0x8(%rsp),%rdi
 109ac2d:	call   103c740 <myl_core_drop_owned>
 109ac32:	mov    0x60(%rsp),%rax
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
 109ac66:	mov    0x60(%rsp),%rax
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
 109ac9a:	mov    0x230(%rsp),%rsi
 109aca2:	call   1044580 <myl_core_str_eq>
 109aca7:	test   %al,%al
 109aca9:	je     109ac80 <my.diagram_membership::compute_sub_block_attachments+0xea0>
 109acab:	jmp    109ac1f <my.diagram_membership::compute_sub_block_attachments+0xe3f>
 109acb0:	lea    0x51e79(%rip),%rdi        # 10ecb30 <core_durable_error.verbs+0x1530>
 109acb7:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109acbc:	mov    $0x1,%al
 109acbe:	lea    -0x7f0a5(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109acc5:	test   %al,%al
 109acc7:	je     109aae2 <my.diagram_membership::compute_sub_block_attachments+0xd02>
 109accd:	call   103c740 <myl_core_drop_owned>
 109acd2:	lea    0x51e87(%rip),%rdi        # 10ecb60 <core_durable_error.verbs+0x1560>
 109acd9:	call   1042840 <myl_core_assert_fail>
 109acde:	lea    0x5da33(%rip),%rsi        # 10f8718 <core_durable_error.verbs+0xd118>
 109ace5:	xor    %edi,%edi
 109ace7:	call   1042f80 <myl_core_dict_new>
 109acec:	mov    %rax,%r15
 109acef:	mov    0xa0(%rsp),%rax
 109acf7:	mov    0x8(%rax),%rax
 109acfb:	test   %rax,%rax
 109acfe:	je     109afe0 <my.diagram_membership::compute_sub_block_attachments+0x1200>
 109ad04:	xor    %esi,%esi
 109ad06:	jmp    109ad2d <my.diagram_membership::compute_sub_block_attachments+0xf4d>
 109ad08:	nopl   0x0(%rax,%rax,1)
 109ad10:	mov    0xa0(%rsp),%rax
 109ad18:	mov    0x8(%rax),%rax
 109ad1c:	mov    0x40(%rsp),%rsi
 109ad21:	inc    %rsi
 109ad24:	cmp    %rax,%rsi
 109ad27:	jae    109afe0 <my.diagram_membership::compute_sub_block_attachments+0x1200>
 109ad2d:	imul   $0x70,%rsi,%rcx
 109ad31:	mov    0xa0(%rsp),%rdx
 109ad39:	mov    0x80(%rdx,%rcx,1),%rcx
 109ad41:	mov    %rcx,0x70(%rsp)
 109ad46:	mov    0x8(%rcx),%rcx
 109ad4a:	mov    %rcx,0x80(%rsp)
 109ad52:	test   %rcx,%rcx
 109ad55:	je     109ad21 <my.diagram_membership::compute_sub_block_attachments+0xf41>
 109ad57:	mov    %rsi,0x40(%rsp)
 109ad5c:	xor    %ebx,%ebx
 109ad5e:	jmp    109ad7c <my.diagram_membership::compute_sub_block_attachments+0xf9c>
 109ad60:	mov    0x10(%rsp),%rdi
 109ad65:	call   103c740 <myl_core_drop_owned>
 109ad6a:	mov    0x8(%rsp),%rbx
 109ad6f:	inc    %rbx
 109ad72:	cmp    0x80(%rsp),%rbx
 109ad7a:	je     109ad10 <my.diagram_membership::compute_sub_block_attachments+0xf30>
 109ad7c:	mov    0x70(%rsp),%rax
 109ad81:	mov    0x20(%rax,%rbx,8),%r14
 109ad86:	mov    %r14,%rdi
 109ad89:	call   104ba40 <myl_core_bytes_utf8_count>
 109ad8e:	test   %rax,%rax
 109ad91:	js     109af6d <my.diagram_membership::compute_sub_block_attachments+0x118d>
 109ad97:	mov    %r14,%rdi
 109ad9a:	call   104bb00 <myl_core_bytes_decode_text>
 109ad9f:	mov    %rax,%rdi
 109ada2:	xor    %eax,%eax
 109ada4:	test   %al,%al
 109ada6:	jne    109ea96 <my.diagram_membership::compute_sub_block_attachments+0x4cb6>
 109adac:	mov    %rdi,0x228(%rsp)
 109adb4:	testb  $0x2,0x1(%rdi)
 109adb8:	mov    %rdi,0x10(%rsp)
 109adbd:	jne    109add0 <my.diagram_membership::compute_sub_block_attachments+0xff0>
 109adbf:	call   1044400 <myl_core_str_hash>
 109adc4:	jmp    109add3 <my.diagram_membership::compute_sub_block_attachments+0xff3>
 109adc6:	cs nopw 0x0(%rax,%rax,1)
 109add0:	mov    0x18(%rdi),%eax
 109add3:	mov    %rbx,0x8(%rsp)
 109add8:	mov    %eax,%eax
 109adda:	movabs $0x9e3779b97f4a7c15,%rcx
 109ade4:	imul   %rcx,%rax
 109ade8:	mov    %rax,%rbp
 109adeb:	shr    $0x20,%rbp
 109adef:	xor    %rax,%rbp
 109adf2:	mov    0x18(%r15),%rcx
 109adf6:	mov    0x8(%rcx),%rax
 109adfa:	test   %rax,%rax
 109adfd:	je     109aee0 <my.diagram_membership::compute_sub_block_attachments+0x1100>
 109ae03:	mov    (%rax),%ecx
 109ae05:	tzcnt  %ecx,%edx
 109ae09:	neg    %dl
 109ae0b:	shrx   %rdx,%rbp,%r13
 109ae10:	lea    -0x1(%rcx),%ebx
 109ae13:	vmovdqu 0x10(%rax,%r13,1),%xmm1
 109ae1a:	mov    %ebp,%edx
 109ae1c:	and    $0x7f,%dl
 109ae1f:	vmovd  %edx,%xmm0
 109ae23:	vpbroadcastb %xmm0,%xmm0
 109ae28:	vmovdqa %xmm1,0x20(%rsp)
 109ae2e:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109ae32:	vpmovmskb %xmm0,%edx
 109ae36:	test   %edx,%edx
 109ae38:	je     109aeb3 <my.diagram_membership::compute_sub_block_attachments+0x10d3>
 109ae3a:	add    $0x1e,%ecx
 109ae3d:	and    $0xfffffff0,%ecx
 109ae40:	lea    (%rax,%rcx,1),%r12
 109ae44:	add    $0x10,%r12
 109ae48:	movzwl %dx,%r14d
 109ae4c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ae5b:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ae6a:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ae79:	nopl   0x0(%rax)
 109ae80:	tzcnt  %r14d,%eax
 109ae85:	add    %r13d,%eax
 109ae88:	and    %ebx,%eax
 109ae8a:	mov    (%r12,%rax,4),%eax
 109ae8e:	shl    $0x4,%rax
 109ae92:	mov    0x20(%r15,%rax,1),%rdi
 109ae97:	mov    0x228(%rsp),%rsi
 109ae9f:	call   1044580 <myl_core_str_eq>
 109aea4:	test   %al,%al
 109aea6:	jne    109ad60 <my.diagram_membership::compute_sub_block_attachments+0xf80>
 109aeac:	blsr   %r14d,%r14d
 109aeb1:	jne    109ae80 <my.diagram_membership::compute_sub_block_attachments+0x10a0>
 109aeb3:	vmovdqa 0x20(%rsp),%xmm0
 109aeb9:	vpcmpeqb -0x96af1(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109aec1:	vpmovmskb %xmm0,%eax
 109aec5:	test   %eax,%eax
 109aec7:	je     109aee7 <my.diagram_membership::compute_sub_block_attachments+0x1107>
 109aec9:	tzcnt  %eax,%r12d
 109aece:	add    %r13d,%r12d
 109aed1:	and    %ebx,%r12d
 109aed4:	not    %r12
 109aed7:	jmp    109afa0 <my.diagram_membership::compute_sub_block_attachments+0x11c0>
 109aedc:	nopl   0x0(%rax)
 109aee0:	cmpq   $0x0,0x18(%rcx)
 109aee5:	je     109af0e <my.diagram_membership::compute_sub_block_attachments+0x112e>
 109aee7:	mov    %r15,%rdi
 109aeea:	lea    0x228(%rsp),%rsi
 109aef2:	mov    %rbp,%rdx
 109aef5:	call   1042bc0 <myl_core_dict_find>
 109aefa:	mov    %rax,%r13
 109aefd:	mov    %r13,%r12
 109af00:	test   %r13,%r13
 109af03:	jns    109ad60 <my.diagram_membership::compute_sub_block_attachments+0xf80>
 109af09:	jmp    109afa0 <my.diagram_membership::compute_sub_block_attachments+0x11c0>
 109af0e:	mov    0x20(%rcx),%rbx
 109af12:	mov    $0xffffffffffffffff,%r12
 109af19:	test   %rbx,%rbx
 109af1c:	je     109afa0 <my.diagram_membership::compute_sub_block_attachments+0x11c0>
 109af22:	mov    0x10(%rcx),%r14
 109af26:	mov    %r15,0x58(%rsp)
 109af2b:	add    $0x20,%r15
 109af2f:	xor    %r13d,%r13d
 109af32:	jmp    109af4c <my.diagram_membership::compute_sub_block_attachments+0x116c>
 109af34:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109af40:	inc    %r13
 109af43:	add    $0x10,%r15
 109af47:	cmp    %r13,%rbx
 109af4a:	je     109af8f <my.diagram_membership::compute_sub_block_attachments+0x11af>
 109af4c:	cmp    %rbp,(%r14,%r13,8)
 109af50:	jne    109af40 <my.diagram_membership::compute_sub_block_attachments+0x1160>
 109af52:	mov    (%r15),%rdi
 109af55:	mov    0x228(%rsp),%rsi
 109af5d:	call   1044580 <myl_core_str_eq>
 109af62:	test   %al,%al
 109af64:	je     109af40 <my.diagram_membership::compute_sub_block_attachments+0x1160>
 109af66:	mov    0x58(%rsp),%r15
 109af6b:	jmp    109aefd <my.diagram_membership::compute_sub_block_attachments+0x111d>
 109af6d:	lea    0x51bbc(%rip),%rdi        # 10ecb30 <core_durable_error.verbs+0x1530>
 109af74:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109af79:	mov    $0x1,%al
 109af7b:	lea    -0x7f362(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109af82:	test   %al,%al
 109af84:	je     109adac <my.diagram_membership::compute_sub_block_attachments+0xfcc>
 109af8a:	jmp    109ea96 <my.diagram_membership::compute_sub_block_attachments+0x4cb6>
 109af8f:	mov    0x58(%rsp),%r15
 109af94:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109afa0:	mov    0x10(%rsp),%rax
 109afa5:	mov    %rax,0x330(%rsp)
 109afad:	mov    0x40(%rsp),%rax
 109afb2:	mov    %rax,0x328(%rsp)
 109afba:	mov    %r15,%rdi
 109afbd:	mov    %r12,%rsi
 109afc0:	lea    0x330(%rsp),%rdx
 109afc8:	lea    0x328(%rsp),%rcx
 109afd0:	xor    %r8d,%r8d
 109afd3:	call   1043240 <myl_core_dict_insert>
 109afd8:	mov    %rax,%r15
 109afdb:	jmp    109ad6a <my.diagram_membership::compute_sub_block_attachments+0xf8a>
 109afe0:	lea    0x5d6b9(%rip),%rsi        # 10f86a0 <core_durable_error.verbs+0xd0a0>
 109afe7:	xor    %edi,%edi
 109afe9:	call   1042f80 <myl_core_dict_new>
 109afee:	mov    %rax,0x40(%rsp)
 109aff3:	mov    0xa0(%rsp),%rax
 109affb:	mov    0x8(%rax),%rax
 109afff:	mov    %rax,0x38(%rsp)
 109b004:	test   %rax,%rax
 109b007:	mov    %r15,0x58(%rsp)
 109b00c:	je     109b2dd <my.diagram_membership::compute_sub_block_attachments+0x14fd>
 109b012:	xor    %eax,%eax
 109b014:	jmp    109b036 <my.diagram_membership::compute_sub_block_attachments+0x1256>
 109b016:	cs nopw 0x0(%rax,%rax,1)
 109b020:	mov    0x80(%rsp),%rax
 109b028:	inc    %rax
 109b02b:	cmp    0x38(%rsp),%rax
 109b030:	je     109b2cf <my.diagram_membership::compute_sub_block_attachments+0x14ef>
 109b036:	mov    %rax,0x80(%rsp)
 109b03e:	imul   $0x70,%rax,%rax
 109b042:	mov    0xa0(%rsp),%rcx
 109b04a:	mov    0x50(%rcx,%rax,1),%rcx
 109b04f:	mov    0x8(%rcx),%rdx
 109b053:	test   %rdx,%rdx
 109b056:	je     109b020 <my.diagram_membership::compute_sub_block_attachments+0x1240>
 109b058:	add    $0x20,%rcx
 109b05c:	xor    %ebx,%ebx
 109b05e:	mov    %rcx,0x8(%rsp)
 109b063:	mov    %rdx,0x20(%rsp)
 109b068:	jmp    109b08b <my.diagram_membership::compute_sub_block_attachments+0x12ab>
 109b06a:	mov    0x10(%rsp),%rdi
 109b06f:	call   103c740 <myl_core_drop_owned>
 109b074:	mov    0x58(%rsp),%r15
 109b079:	mov    0x8(%rsp),%rcx
 109b07e:	mov    0x20(%rsp),%rdx
 109b083:	inc    %rbx
 109b086:	cmp    %rdx,%rbx
 109b089:	je     109b020 <my.diagram_membership::compute_sub_block_attachments+0x1240>
 109b08b:	imul   $0xf0,%rbx,%rax
 109b092:	cmpl   $0x0,0x10(%rcx,%rax,1)
 109b097:	jne    109b083 <my.diagram_membership::compute_sub_block_attachments+0x12a3>
 109b099:	add    %rcx,%rax
 109b09c:	mov    (%rax),%r14
 109b09f:	mov    %r14,%rdi
 109b0a2:	call   104ba40 <myl_core_bytes_utf8_count>
 109b0a7:	test   %rax,%rax
 109b0aa:	js     109b2a1 <my.diagram_membership::compute_sub_block_attachments+0x14c1>
 109b0b0:	mov    %r14,%rdi
 109b0b3:	call   104bb00 <myl_core_bytes_decode_text>
 109b0b8:	mov    %rax,%rdi
 109b0bb:	xor    %eax,%eax
 109b0bd:	test   %al,%al
 109b0bf:	jne    109b2be <my.diagram_membership::compute_sub_block_attachments+0x14de>
 109b0c5:	mov    %rdi,0x220(%rsp)
 109b0cd:	testb  $0x2,0x1(%rdi)
 109b0d1:	mov    %rdi,0x10(%rsp)
 109b0d6:	jne    109b0df <my.diagram_membership::compute_sub_block_attachments+0x12ff>
 109b0d8:	call   1044400 <myl_core_str_hash>
 109b0dd:	jmp    109b0e2 <my.diagram_membership::compute_sub_block_attachments+0x1302>
 109b0df:	mov    0x18(%rdi),%eax
 109b0e2:	mov    %eax,%eax
 109b0e4:	movabs $0x9e3779b97f4a7c15,%rcx
 109b0ee:	imul   %rcx,%rax
 109b0f2:	mov    %rax,%rbp
 109b0f5:	shr    $0x20,%rbp
 109b0f9:	xor    %rax,%rbp
 109b0fc:	mov    0x40(%rsp),%rax
 109b101:	mov    0x18(%rax),%rcx
 109b105:	mov    0x8(%rcx),%rax
 109b109:	test   %rax,%rax
 109b10c:	je     109b1de <my.diagram_membership::compute_sub_block_attachments+0x13fe>
 109b112:	mov    (%rax),%ecx
 109b114:	tzcnt  %ecx,%edx
 109b118:	neg    %dl
 109b11a:	shrx   %rdx,%rbp,%r13
 109b11f:	lea    -0x1(%rcx),%r15d
 109b123:	vmovdqu 0x10(%rax,%r13,1),%xmm1
 109b12a:	mov    %ebp,%edx
 109b12c:	and    $0x7f,%dl
 109b12f:	vmovd  %edx,%xmm0
 109b133:	vpbroadcastb %xmm0,%xmm0
 109b138:	vmovdqa %xmm1,0x70(%rsp)
 109b13e:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109b142:	vpmovmskb %xmm0,%edx
 109b146:	test   %edx,%edx
 109b148:	je     109b1b5 <my.diagram_membership::compute_sub_block_attachments+0x13d5>
 109b14a:	add    $0x1e,%ecx
 109b14d:	and    $0xfffffff0,%ecx
 109b150:	lea    (%rax,%rcx,1),%r12
 109b154:	add    $0x10,%r12
 109b158:	movzwl %dx,%r14d
 109b15c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b16b:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b17a:	nopw   0x0(%rax,%rax,1)
 109b180:	tzcnt  %r14d,%eax
 109b185:	add    %r13d,%eax
 109b188:	and    %r15d,%eax
 109b18b:	mov    (%r12,%rax,4),%eax
 109b18f:	mov    0x40(%rsp),%rcx
 109b194:	mov    0x20(%rcx,%rax,8),%rdi
 109b199:	mov    0x220(%rsp),%rsi
 109b1a1:	call   1044580 <myl_core_str_eq>
 109b1a6:	test   %al,%al
 109b1a8:	jne    109b06a <my.diagram_membership::compute_sub_block_attachments+0x128a>
 109b1ae:	blsr   %r14d,%r14d
 109b1b3:	jne    109b180 <my.diagram_membership::compute_sub_block_attachments+0x13a0>
 109b1b5:	vmovdqa 0x70(%rsp),%xmm0
 109b1bb:	vpcmpeqb -0x96df3(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109b1c3:	vpmovmskb %xmm0,%eax
 109b1c7:	test   %eax,%eax
 109b1c9:	je     109b1e5 <my.diagram_membership::compute_sub_block_attachments+0x1405>
 109b1cb:	tzcnt  %eax,%r12d
 109b1d0:	add    %r13d,%r12d
 109b1d3:	and    %r15d,%r12d
 109b1d6:	not    %r12
 109b1d9:	jmp    109b270 <my.diagram_membership::compute_sub_block_attachments+0x1490>
 109b1de:	cmpq   $0x0,0x18(%rcx)
 109b1e3:	je     109b20b <my.diagram_membership::compute_sub_block_attachments+0x142b>
 109b1e5:	mov    0x40(%rsp),%rdi
 109b1ea:	lea    0x220(%rsp),%rsi
 109b1f2:	mov    %rbp,%rdx
 109b1f5:	call   1042bc0 <myl_core_dict_find>
 109b1fa:	mov    %rax,%r13
 109b1fd:	mov    %r13,%r12
 109b200:	test   %r13,%r13
 109b203:	jns    109b06a <my.diagram_membership::compute_sub_block_attachments+0x128a>
 109b209:	jmp    109b270 <my.diagram_membership::compute_sub_block_attachments+0x1490>
 109b20b:	mov    0x20(%rcx),%r15
 109b20f:	mov    $0xffffffffffffffff,%r12
 109b216:	test   %r15,%r15
 109b219:	je     109b270 <my.diagram_membership::compute_sub_block_attachments+0x1490>
 109b21b:	mov    0x10(%rcx),%r14
 109b21f:	xor    %r13d,%r13d
 109b222:	jmp    109b248 <my.diagram_membership::compute_sub_block_attachments+0x1468>
 109b224:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b233:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b240:	inc    %r13
 109b243:	cmp    %r13,%r15
 109b246:	je     109b270 <my.diagram_membership::compute_sub_block_attachments+0x1490>
 109b248:	cmp    %rbp,(%r14,%r13,8)
 109b24c:	jne    109b240 <my.diagram_membership::compute_sub_block_attachments+0x1460>
 109b24e:	mov    0x40(%rsp),%rax
 109b253:	mov    0x20(%rax,%r13,8),%rdi
 109b258:	mov    0x220(%rsp),%rsi
 109b260:	call   1044580 <myl_core_str_eq>
 109b265:	test   %al,%al
 109b267:	je     109b240 <my.diagram_membership::compute_sub_block_attachments+0x1460>
 109b269:	jmp    109b1fd <my.diagram_membership::compute_sub_block_attachments+0x141d>
 109b26b:	nopl   0x0(%rax,%rax,1)
 109b270:	mov    0x10(%rsp),%rax
 109b275:	mov    %rax,0x320(%rsp)
 109b27d:	mov    0x40(%rsp),%rdi
 109b282:	mov    %r12,%rsi
 109b285:	lea    0x320(%rsp),%rdx
 109b28d:	xor    %ecx,%ecx
 109b28f:	xor    %r8d,%r8d
 109b292:	call   1043240 <myl_core_dict_insert>
 109b297:	mov    %rax,0x40(%rsp)
 109b29c:	jmp    109b074 <my.diagram_membership::compute_sub_block_attachments+0x1294>
 109b2a1:	lea    0x51888(%rip),%rdi        # 10ecb30 <core_durable_error.verbs+0x1530>
 109b2a8:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109b2ad:	mov    $0x1,%al
 109b2af:	lea    -0x7f696(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109b2b6:	test   %al,%al
 109b2b8:	je     109b0c5 <my.diagram_membership::compute_sub_block_attachments+0x12e5>
 109b2be:	call   103c740 <myl_core_drop_owned>
 109b2c3:	lea    0x51896(%rip),%rdi        # 10ecb60 <core_durable_error.verbs+0x1560>
 109b2ca:	call   1042840 <myl_core_assert_fail>
 109b2cf:	mov    0xa0(%rsp),%rax
 109b2d7:	mov    0x8(%rax),%rdx
 109b2db:	jmp    109b2df <my.diagram_membership::compute_sub_block_attachments+0x14ff>
 109b2dd:	xor    %edx,%edx
 109b2df:	mov    0x100(%rsp),%rax
 109b2e7:	mov    0x8(%rax),%rax
 109b2eb:	mov    %rax,0x128(%rsp)
 109b2f3:	mov    %fs:0xfffffffffffffec8,%rdi
 109b2fc:	test   %rdi,%rdi
 109b2ff:	mov    %rdx,0xc0(%rsp)
 109b307:	je     109ea7a <my.diagram_membership::compute_sub_block_attachments+0x4c9a>
 109b30d:	mov    (%rdi),%rax
 109b310:	mov    %rax,%fs:0xfffffffffffffec8
 109b319:	movl   $0x1000000,(%rdi)
 109b31f:	vpxor  %xmm0,%xmm0,%xmm0
 109b323:	vmovdqu %xmm0,0x8(%rdi)
 109b328:	movq   $0x0,0x18(%rdi)
 109b330:	mov    0x128(%rsp),%rbx
 109b338:	imul   %rdx,%rbx
 109b33c:	jo     109ea10 <my.diagram_membership::compute_sub_block_attachments+0x4c30>
 109b342:	test   %rbx,%rbx
 109b345:	je     109b3bc <my.diagram_membership::compute_sub_block_attachments+0x15dc>
 109b347:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b356:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b365:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b374:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b380:	mov    0x8(%rdi),%rax
 109b384:	cmp    0x10(%rdi),%rax
 109b388:	jae    109b3a1 <my.diagram_membership::compute_sub_block_attachments+0x15c1>
 109b38a:	movq   $0x0,0x20(%rdi,%rax,8)
 109b393:	inc    %rax
 109b396:	mov    %rax,0x8(%rdi)
 109b39a:	dec    %rbx
 109b39d:	jne    109b380 <my.diagram_membership::compute_sub_block_attachments+0x15a0>
 109b39f:	jmp    109b3bc <my.diagram_membership::compute_sub_block_attachments+0x15dc>
 109b3a1:	mov    $0x8,%esi
 109b3a6:	call   103ba40 <myl_core_list_grow>
 109b3ab:	mov    0xc0(%rsp),%rdx
 109b3b3:	mov    %rax,%rdi
 109b3b6:	mov    0x8(%rax),%rax
 109b3ba:	jmp    109b38a <my.diagram_membership::compute_sub_block_attachments+0x15aa>
 109b3bc:	mov    %rdi,0x1e8(%rsp)
 109b3c4:	test   %rdx,%rdx
 109b3c7:	je     109c12f <my.diagram_membership::compute_sub_block_attachments+0x234f>
 109b3cd:	mov    0xa0(%rsp),%rax
 109b3d5:	add    $0x20,%rax
 109b3d9:	mov    %rax,0x118(%rsp)
 109b3e1:	mov    (%rsp),%rax
 109b3e5:	add    $0x20,%rax
 109b3e9:	mov    %rax,0x110(%rsp)
 109b3f1:	mov    0x60(%rsp),%rax
 109b3f6:	add    $0x20,%rax
 109b3fa:	mov    %rax,0x108(%rsp)
 109b402:	xor    %eax,%eax
 109b404:	jmp    109b438 <my.diagram_membership::compute_sub_block_attachments+0x1658>
 109b406:	cs nopw 0x0(%rax,%rax,1)
 109b410:	mov    0x10(%rsp),%rdi
 109b415:	call   103c740 <myl_core_drop_owned>
 109b41a:	mov    0x98(%rsp),%rax
 109b422:	inc    %rax
 109b425:	cmp    0xc0(%rsp),%rax
 109b42d:	mov    0x58(%rsp),%r15
 109b432:	je     109c12f <my.diagram_membership::compute_sub_block_attachments+0x234f>
 109b438:	mov    %rax,0x98(%rsp)
 109b440:	imul   $0x70,%rax,%rax
 109b444:	mov    0x118(%rsp),%rcx
 109b44c:	mov    (%rcx,%rax,1),%rdi
 109b450:	mov    0x8(%rcx,%rax,1),%r14
 109b455:	mov    0x10(%rcx,%rax,1),%r13
 109b45a:	mov    0x18(%rcx,%rax,1),%rbp
 109b45f:	mov    0x20(%rcx,%rax,1),%rbx
 109b464:	mov    0x28(%rcx,%rax,1),%r12
 109b469:	mov    0x30(%rcx,%rax,1),%rdx
 109b46e:	mov    %rdx,0x70(%rsp)
 109b473:	mov    0x38(%rcx,%rax,1),%rdx
 109b478:	mov    %rdx,0x20(%rsp)
 109b47d:	mov    0x40(%rcx,%rax,1),%rdx
 109b482:	mov    %rdx,0x8(%rsp)
 109b487:	mov    0x48(%rcx,%rax,1),%rdx
 109b48c:	mov    %rdx,0x10(%rsp)
 109b491:	mov    0x60(%rcx,%rax,1),%r15
 109b496:	call   103cfc0 <myl_core_owned_octets_copy>
 109b49b:	mov    %rax,0xa8(%rsp)
 109b4a3:	mov    %r14,%rdi
 109b4a6:	call   103cfc0 <myl_core_owned_octets_copy>
 109b4ab:	mov    %rax,0xb8(%rsp)
 109b4b3:	mov    %r13,%rdi
 109b4b6:	call   103cfc0 <myl_core_owned_octets_copy>
 109b4bb:	mov    %rax,0xf0(%rsp)
 109b4c3:	lea    0x5eea6(%rip),%rdi        # 10fa370 <core_durable_error.verbs+0xed70>
 109b4ca:	mov    %rbp,%rsi
 109b4cd:	call   1063d00 <myl_core_values_copy_box>
 109b4d2:	mov    %rax,0xe8(%rsp)
 109b4da:	lea    0x5e9ff(%rip),%rdi        # 10f9ee0 <core_durable_error.verbs+0xe8e0>
 109b4e1:	mov    %rbx,%rsi
 109b4e4:	call   1063d00 <myl_core_values_copy_box>
 109b4e9:	mov    %rax,0xe0(%rsp)
 109b4f1:	lea    0x5eef8(%rip),%rdi        # 10fa3f0 <core_durable_error.verbs+0xedf0>
 109b4f8:	mov    %r12,%rsi
 109b4fb:	call   1063d00 <myl_core_values_copy_box>
 109b500:	mov    %rax,%r14
 109b503:	lea    0x5f0d6(%rip),%rdi        # 10fa5e0 <core_durable_error.verbs+0xefe0>
 109b50a:	mov    0x70(%rsp),%rsi
 109b50f:	call   1063d00 <myl_core_values_copy_box>
 109b514:	mov    %rax,0x90(%rsp)
 109b51c:	lea    0x5d72d(%rip),%rbx        # 10f8c50 <core_durable_error.verbs+0xd650>
 109b523:	mov    %rbx,%rdi
 109b526:	mov    0x20(%rsp),%rsi
 109b52b:	call   1063d00 <myl_core_values_copy_box>
 109b530:	mov    %rax,0xb0(%rsp)
 109b538:	lea    0x5f181(%rip),%rdi        # 10fa6c0 <core_durable_error.verbs+0xf0c0>
 109b53f:	mov    0x8(%rsp),%rsi
 109b544:	call   1063d00 <myl_core_values_copy_box>
 109b549:	mov    %rax,0xd8(%rsp)
 109b551:	lea    0x5f198(%rip),%rdi        # 10fa6f0 <core_durable_error.verbs+0xf0f0>
 109b558:	mov    0x10(%rsp),%rsi
 109b55d:	call   1063d00 <myl_core_values_copy_box>
 109b562:	mov    %rax,0xd0(%rsp)
 109b56a:	mov    %rbx,%rdi
 109b56d:	mov    %r15,%rsi
 109b570:	call   1063d00 <myl_core_values_copy_box>
 109b575:	mov    %rax,0xf8(%rsp)
 109b57d:	xor    %edi,%edi
 109b57f:	lea    0x5d11a(%rip),%rsi        # 10f86a0 <core_durable_error.verbs+0xd0a0>
 109b586:	call   1042f80 <myl_core_dict_new>
 109b58b:	mov    %rax,0x10(%rsp)
 109b590:	mov    %r14,0x30(%rsp)
 109b595:	mov    0x8(%r14),%rax
 109b599:	mov    %rax,0xc8(%rsp)
 109b5a1:	test   %rax,%rax
 109b5a4:	je     109b850 <my.diagram_membership::compute_sub_block_attachments+0x1a70>
 109b5aa:	xor    %eax,%eax
 109b5ac:	jmp    109b5c6 <my.diagram_membership::compute_sub_block_attachments+0x17e6>
 109b5ae:	xchg   %ax,%ax
 109b5b0:	mov    0x38(%rsp),%rax
 109b5b5:	inc    %rax
 109b5b8:	cmp    0xc8(%rsp),%rax
 109b5c0:	je     109b850 <my.diagram_membership::compute_sub_block_attachments+0x1a70>
 109b5c6:	mov    %rax,0x38(%rsp)
 109b5cb:	lea    (%rax,%rax,2),%rax
 109b5cf:	mov    0x30(%rsp),%rcx
 109b5d4:	mov    0x28(%rcx,%rax,8),%rax
 109b5d9:	mov    %rax,0x70(%rsp)
 109b5de:	mov    0x8(%rax),%rax
 109b5e2:	mov    %rax,0x80(%rsp)
 109b5ea:	test   %rax,%rax
 109b5ed:	je     109b5b0 <my.diagram_membership::compute_sub_block_attachments+0x17d0>
 109b5ef:	xor    %r15d,%r15d
 109b5f2:	jmp    109b617 <my.diagram_membership::compute_sub_block_attachments+0x1837>
 109b5f4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b600:	mov    0x8(%rsp),%rdi
 109b605:	call   103c740 <myl_core_drop_owned>
 109b60a:	inc    %r15
 109b60d:	cmp    0x80(%rsp),%r15
 109b615:	je     109b5b0 <my.diagram_membership::compute_sub_block_attachments+0x17d0>
 109b617:	mov    %r15,%rax
 109b61a:	shl    $0x5,%rax
 109b61e:	mov    0x70(%rsp),%rcx
 109b623:	mov    0x28(%rcx,%rax,1),%r14
 109b628:	mov    %r14,%rdi
 109b62b:	call   104ba40 <myl_core_bytes_utf8_count>
 109b630:	test   %rax,%rax
 109b633:	js     109b821 <my.diagram_membership::compute_sub_block_attachments+0x1a41>
 109b639:	mov    %r14,%rdi
 109b63c:	call   104bb00 <myl_core_bytes_decode_text>
 109b641:	mov    %rax,%rdi
 109b644:	xor    %eax,%eax
 109b646:	test   %al,%al
 109b648:	jne    109ea24 <my.diagram_membership::compute_sub_block_attachments+0x4c44>
 109b64e:	mov    %rdi,0x218(%rsp)
 109b656:	testb  $0x2,0x1(%rdi)
 109b65a:	mov    %rdi,0x8(%rsp)
 109b65f:	jne    109b670 <my.diagram_membership::compute_sub_block_attachments+0x1890>
 109b661:	call   1044400 <myl_core_str_hash>
 109b666:	jmp    109b673 <my.diagram_membership::compute_sub_block_attachments+0x1893>
 109b668:	nopl   0x0(%rax,%rax,1)
 109b670:	mov    0x18(%rdi),%eax
 109b673:	mov    %eax,%eax
 109b675:	movabs $0x9e3779b97f4a7c15,%rcx
 109b67f:	imul   %rcx,%rax
 109b683:	mov    %rax,%rbp
 109b686:	shr    $0x20,%rbp
 109b68a:	xor    %rax,%rbp
 109b68d:	mov    0x10(%rsp),%rax
 109b692:	mov    0x18(%rax),%rcx
 109b696:	mov    0x8(%rcx),%rax
 109b69a:	test   %rax,%rax
 109b69d:	je     109b760 <my.diagram_membership::compute_sub_block_attachments+0x1980>
 109b6a3:	mov    (%rax),%ecx
 109b6a5:	tzcnt  %ecx,%edx
 109b6a9:	neg    %dl
 109b6ab:	shrx   %rdx,%rbp,%r13
 109b6b0:	lea    -0x1(%rcx),%ebx
 109b6b3:	vmovdqu 0x10(%rax,%r13,1),%xmm1
 109b6ba:	mov    %ebp,%edx
 109b6bc:	and    $0x7f,%dl
 109b6bf:	vmovd  %edx,%xmm0
 109b6c3:	vpbroadcastb %xmm0,%xmm0
 109b6c8:	vmovdqa %xmm1,0x20(%rsp)
 109b6ce:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109b6d2:	vpmovmskb %xmm0,%edx
 109b6d6:	test   %edx,%edx
 109b6d8:	je     109b734 <my.diagram_membership::compute_sub_block_attachments+0x1954>
 109b6da:	add    $0x1e,%ecx
 109b6dd:	and    $0xfffffff0,%ecx
 109b6e0:	lea    (%rax,%rcx,1),%r12
 109b6e4:	add    $0x10,%r12
 109b6e8:	movzwl %dx,%r14d
 109b6ec:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b6fb:	nopl   0x0(%rax,%rax,1)
 109b700:	tzcnt  %r14d,%eax
 109b705:	add    %r13d,%eax
 109b708:	and    %ebx,%eax
 109b70a:	mov    (%r12,%rax,4),%eax
 109b70e:	mov    0x10(%rsp),%rcx
 109b713:	mov    0x20(%rcx,%rax,8),%rdi
 109b718:	mov    0x218(%rsp),%rsi
 109b720:	call   1044580 <myl_core_str_eq>
 109b725:	test   %al,%al
 109b727:	jne    109b600 <my.diagram_membership::compute_sub_block_attachments+0x1820>
 109b72d:	blsr   %r14d,%r14d
 109b732:	jne    109b700 <my.diagram_membership::compute_sub_block_attachments+0x1920>
 109b734:	vmovdqa 0x20(%rsp),%xmm0
 109b73a:	vpcmpeqb -0x97372(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109b742:	vpmovmskb %xmm0,%eax
 109b746:	test   %eax,%eax
 109b748:	je     109b767 <my.diagram_membership::compute_sub_block_attachments+0x1987>
 109b74a:	tzcnt  %eax,%r12d
 109b74f:	add    %r13d,%r12d
 109b752:	and    %ebx,%r12d
 109b755:	not    %r12
 109b758:	jmp    109b7f0 <my.diagram_membership::compute_sub_block_attachments+0x1a10>
 109b75d:	nopl   (%rax)
 109b760:	cmpq   $0x0,0x18(%rcx)
 109b765:	je     109b78d <my.diagram_membership::compute_sub_block_attachments+0x19ad>
 109b767:	mov    0x10(%rsp),%rdi
 109b76c:	lea    0x218(%rsp),%rsi
 109b774:	mov    %rbp,%rdx
 109b777:	call   1042bc0 <myl_core_dict_find>
 109b77c:	mov    %rax,%r13
 109b77f:	mov    %r13,%r12
 109b782:	test   %r13,%r13
 109b785:	jns    109b600 <my.diagram_membership::compute_sub_block_attachments+0x1820>
 109b78b:	jmp    109b7f0 <my.diagram_membership::compute_sub_block_attachments+0x1a10>
 109b78d:	mov    0x20(%rcx),%rbx
 109b791:	mov    $0xffffffffffffffff,%r12
 109b798:	test   %rbx,%rbx
 109b79b:	je     109b7f0 <my.diagram_membership::compute_sub_block_attachments+0x1a10>
 109b79d:	mov    0x10(%rcx),%r14
 109b7a1:	xor    %r13d,%r13d
 109b7a4:	jmp    109b7c8 <my.diagram_membership::compute_sub_block_attachments+0x19e8>
 109b7a6:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b7b5:	data16 cs nopw 0x0(%rax,%rax,1)
 109b7c0:	inc    %r13
 109b7c3:	cmp    %r13,%rbx
 109b7c6:	je     109b7f0 <my.diagram_membership::compute_sub_block_attachments+0x1a10>
 109b7c8:	cmp    %rbp,(%r14,%r13,8)
 109b7cc:	jne    109b7c0 <my.diagram_membership::compute_sub_block_attachments+0x19e0>
 109b7ce:	mov    0x10(%rsp),%rax
 109b7d3:	mov    0x20(%rax,%r13,8),%rdi
 109b7d8:	mov    0x218(%rsp),%rsi
 109b7e0:	call   1044580 <myl_core_str_eq>
 109b7e5:	test   %al,%al
 109b7e7:	je     109b7c0 <my.diagram_membership::compute_sub_block_attachments+0x19e0>
 109b7e9:	jmp    109b77f <my.diagram_membership::compute_sub_block_attachments+0x199f>
 109b7eb:	nopl   0x0(%rax,%rax,1)
 109b7f0:	mov    0x8(%rsp),%rax
 109b7f5:	mov    %rax,0x318(%rsp)
 109b7fd:	mov    0x10(%rsp),%rdi
 109b802:	mov    %r12,%rsi
 109b805:	lea    0x318(%rsp),%rdx
 109b80d:	xor    %ecx,%ecx
 109b80f:	xor    %r8d,%r8d
 109b812:	call   1043240 <myl_core_dict_insert>
 109b817:	mov    %rax,0x10(%rsp)
 109b81c:	jmp    109b60a <my.diagram_membership::compute_sub_block_attachments+0x182a>
 109b821:	lea    0x51308(%rip),%rdi        # 10ecb30 <core_durable_error.verbs+0x1530>
 109b828:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109b82d:	mov    $0x1,%al
 109b82f:	lea    -0x7fc16(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109b836:	test   %al,%al
 109b838:	je     109b64e <my.diagram_membership::compute_sub_block_attachments+0x186e>
 109b83e:	jmp    109ea24 <my.diagram_membership::compute_sub_block_attachments+0x4c44>
 109b843:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b850:	mov    0x90(%rsp),%rax
 109b858:	mov    0x8(%rax),%rcx
 109b85c:	mov    %rcx,0x70(%rsp)
 109b861:	test   %rcx,%rcx
 109b864:	je     109bad0 <my.diagram_membership::compute_sub_block_attachments+0x1cf0>
 109b86a:	add    $0x20,%rax
 109b86e:	mov    %rax,0x80(%rsp)
 109b876:	xor    %r15d,%r15d
 109b879:	jmp    109b898 <my.diagram_membership::compute_sub_block_attachments+0x1ab8>
 109b87b:	nopl   0x0(%rax,%rax,1)
 109b880:	mov    0x8(%rsp),%rdi
 109b885:	call   103c740 <myl_core_drop_owned>
 109b88a:	inc    %r15
 109b88d:	cmp    0x70(%rsp),%r15
 109b892:	je     109bad0 <my.diagram_membership::compute_sub_block_attachments+0x1cf0>
 109b898:	imul   $0xf0,%r15,%rax
 109b89f:	mov    0x80(%rsp),%rcx
 109b8a7:	mov    (%rcx,%rax,1),%r14
 109b8ab:	mov    %r14,%rdi
 109b8ae:	call   104ba40 <myl_core_bytes_utf8_count>
 109b8b3:	test   %rax,%rax
 109b8b6:	js     109baa1 <my.diagram_membership::compute_sub_block_attachments+0x1cc1>
 109b8bc:	mov    %r14,%rdi
 109b8bf:	call   104bb00 <myl_core_bytes_decode_text>
 109b8c4:	mov    %rax,%rdi
 109b8c7:	xor    %eax,%eax
 109b8c9:	test   %al,%al
 109b8cb:	jne    109eaa7 <my.diagram_membership::compute_sub_block_attachments+0x4cc7>
 109b8d1:	mov    %rdi,0x210(%rsp)
 109b8d9:	testb  $0x2,0x1(%rdi)
 109b8dd:	mov    %rdi,0x8(%rsp)
 109b8e2:	jne    109b8f0 <my.diagram_membership::compute_sub_block_attachments+0x1b10>
 109b8e4:	call   1044400 <myl_core_str_hash>
 109b8e9:	jmp    109b8f3 <my.diagram_membership::compute_sub_block_attachments+0x1b13>
 109b8eb:	nopl   0x0(%rax,%rax,1)
 109b8f0:	mov    0x18(%rdi),%eax
 109b8f3:	mov    %eax,%eax
 109b8f5:	movabs $0x9e3779b97f4a7c15,%rcx
 109b8ff:	imul   %rcx,%rax
 109b903:	mov    %rax,%rbp
 109b906:	shr    $0x20,%rbp
 109b90a:	xor    %rax,%rbp
 109b90d:	mov    0x10(%rsp),%rax
 109b912:	mov    0x18(%rax),%rcx
 109b916:	mov    0x8(%rcx),%rax
 109b91a:	test   %rax,%rax
 109b91d:	je     109b9e0 <my.diagram_membership::compute_sub_block_attachments+0x1c00>
 109b923:	mov    (%rax),%ecx
 109b925:	tzcnt  %ecx,%edx
 109b929:	neg    %dl
 109b92b:	shrx   %rdx,%rbp,%r12
 109b930:	lea    -0x1(%rcx),%ebx
 109b933:	vmovdqu 0x10(%rax,%r12,1),%xmm1
 109b93a:	mov    %ebp,%edx
 109b93c:	and    $0x7f,%dl
 109b93f:	vmovd  %edx,%xmm0
 109b943:	vpbroadcastb %xmm0,%xmm0
 109b948:	vmovdqa %xmm1,0x20(%rsp)
 109b94e:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109b952:	vpmovmskb %xmm0,%edx
 109b956:	test   %edx,%edx
 109b958:	je     109b9b5 <my.diagram_membership::compute_sub_block_attachments+0x1bd5>
 109b95a:	add    $0x1e,%ecx
 109b95d:	and    $0xfffffff0,%ecx
 109b960:	lea    (%rax,%rcx,1),%r13
 109b964:	add    $0x10,%r13
 109b968:	movzwl %dx,%r14d
 109b96c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109b97b:	nopl   0x0(%rax,%rax,1)
 109b980:	tzcnt  %r14d,%eax
 109b985:	add    %r12d,%eax
 109b988:	and    %ebx,%eax
 109b98a:	mov    0x0(%r13,%rax,4),%eax
 109b98f:	mov    0x10(%rsp),%rcx
 109b994:	mov    0x20(%rcx,%rax,8),%rdi
 109b999:	mov    0x210(%rsp),%rsi
 109b9a1:	call   1044580 <myl_core_str_eq>
 109b9a6:	test   %al,%al
 109b9a8:	jne    109b880 <my.diagram_membership::compute_sub_block_attachments+0x1aa0>
 109b9ae:	blsr   %r14d,%r14d
 109b9b3:	jne    109b980 <my.diagram_membership::compute_sub_block_attachments+0x1ba0>
 109b9b5:	vmovdqa 0x20(%rsp),%xmm0
 109b9bb:	vpcmpeqb -0x975f3(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109b9c3:	vpmovmskb %xmm0,%eax
 109b9c7:	test   %eax,%eax
 109b9c9:	je     109b9e7 <my.diagram_membership::compute_sub_block_attachments+0x1c07>
 109b9cb:	tzcnt  %eax,%r13d
 109b9d0:	add    %r12d,%r13d
 109b9d3:	and    %ebx,%r13d
 109b9d6:	not    %r13
 109b9d9:	jmp    109ba70 <my.diagram_membership::compute_sub_block_attachments+0x1c90>
 109b9de:	xchg   %ax,%ax
 109b9e0:	cmpq   $0x0,0x18(%rcx)
 109b9e5:	je     109ba0d <my.diagram_membership::compute_sub_block_attachments+0x1c2d>
 109b9e7:	mov    0x10(%rsp),%rdi
 109b9ec:	lea    0x210(%rsp),%rsi
 109b9f4:	mov    %rbp,%rdx
 109b9f7:	call   1042bc0 <myl_core_dict_find>
 109b9fc:	mov    %rax,%r12
 109b9ff:	mov    %r12,%r13
 109ba02:	test   %r12,%r12
 109ba05:	jns    109b880 <my.diagram_membership::compute_sub_block_attachments+0x1aa0>
 109ba0b:	jmp    109ba70 <my.diagram_membership::compute_sub_block_attachments+0x1c90>
 109ba0d:	mov    0x20(%rcx),%rbx
 109ba11:	mov    $0xffffffffffffffff,%r13
 109ba18:	test   %rbx,%rbx
 109ba1b:	je     109ba70 <my.diagram_membership::compute_sub_block_attachments+0x1c90>
 109ba1d:	mov    0x10(%rcx),%r14
 109ba21:	xor    %r12d,%r12d
 109ba24:	jmp    109ba48 <my.diagram_membership::compute_sub_block_attachments+0x1c68>
 109ba26:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ba35:	data16 cs nopw 0x0(%rax,%rax,1)
 109ba40:	inc    %r12
 109ba43:	cmp    %r12,%rbx
 109ba46:	je     109ba70 <my.diagram_membership::compute_sub_block_attachments+0x1c90>
 109ba48:	cmp    %rbp,(%r14,%r12,8)
 109ba4c:	jne    109ba40 <my.diagram_membership::compute_sub_block_attachments+0x1c60>
 109ba4e:	mov    0x10(%rsp),%rax
 109ba53:	mov    0x20(%rax,%r12,8),%rdi
 109ba58:	mov    0x210(%rsp),%rsi
 109ba60:	call   1044580 <myl_core_str_eq>
 109ba65:	test   %al,%al
 109ba67:	je     109ba40 <my.diagram_membership::compute_sub_block_attachments+0x1c60>
 109ba69:	jmp    109b9ff <my.diagram_membership::compute_sub_block_attachments+0x1c1f>
 109ba6b:	nopl   0x0(%rax,%rax,1)
 109ba70:	mov    0x8(%rsp),%rax
 109ba75:	mov    %rax,0x310(%rsp)
 109ba7d:	mov    0x10(%rsp),%rdi
 109ba82:	mov    %r13,%rsi
 109ba85:	lea    0x310(%rsp),%rdx
 109ba8d:	xor    %ecx,%ecx
 109ba8f:	xor    %r8d,%r8d
 109ba92:	call   1043240 <myl_core_dict_insert>
 109ba97:	mov    %rax,0x10(%rsp)
 109ba9c:	jmp    109b88a <my.diagram_membership::compute_sub_block_attachments+0x1aaa>
 109baa1:	lea    0x51088(%rip),%rdi        # 10ecb30 <core_durable_error.verbs+0x1530>
 109baa8:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109baad:	mov    $0x1,%al
 109baaf:	lea    -0x7fe96(%rip),%rdi        # 101bc20 <core_number_pairs+0x146d0>
 109bab6:	test   %al,%al
 109bab8:	je     109b8d1 <my.diagram_membership::compute_sub_block_attachments+0x1af1>
 109babe:	jmp    109eaa7 <my.diagram_membership::compute_sub_block_attachments+0x4cc7>
 109bac3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bad0:	mov    0xa8(%rsp),%rdi
 109bad8:	call   103c740 <myl_core_drop_owned>
 109badd:	mov    0xb8(%rsp),%rdi
 109bae5:	call   103c740 <myl_core_drop_owned>
 109baea:	mov    0xf0(%rsp),%rdi
 109baf2:	call   103c740 <myl_core_drop_owned>
 109baf7:	mov    0xe8(%rsp),%rdi
 109baff:	call   103c740 <myl_core_drop_owned>
 109bb04:	mov    0xe0(%rsp),%rdi
 109bb0c:	call   103c740 <myl_core_drop_owned>
 109bb11:	mov    0x30(%rsp),%rdi
 109bb16:	call   103c740 <myl_core_drop_owned>
 109bb1b:	mov    0x90(%rsp),%rdi
 109bb23:	call   103c740 <myl_core_drop_owned>
 109bb28:	mov    0xb0(%rsp),%rdi
 109bb30:	call   103c740 <myl_core_drop_owned>
 109bb35:	mov    0xd8(%rsp),%rdi
 109bb3d:	call   103c740 <myl_core_drop_owned>
 109bb42:	mov    0xd0(%rsp),%rdi
 109bb4a:	call   103c740 <myl_core_drop_owned>
 109bb4f:	mov    0xf8(%rsp),%rdi
 109bb57:	call   103c740 <myl_core_drop_owned>
 109bb5c:	mov    0x10(%rsp),%rax
 109bb61:	mov    0x8(%rax),%rax
 109bb65:	mov    %rax,0x70(%rsp)
 109bb6a:	test   %rax,%rax
 109bb6d:	je     109b410 <my.diagram_membership::compute_sub_block_attachments+0x1630>
 109bb73:	xor    %esi,%esi
 109bb75:	jmp    109bbbb <my.diagram_membership::compute_sub_block_attachments+0x1ddb>
 109bb77:	vmovdqa 0x80(%rsp),%xmm0
 109bb80:	vpcmpeqb -0x977b8(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109bb88:	vpmovmskb %xmm0,%eax
 109bb8c:	test   %eax,%eax
 109bb8e:	mov    0x20(%rsp),%r12
 109bb93:	je     109c044 <my.diagram_membership::compute_sub_block_attachments+0x2264>
 109bb99:	nopl   0x0(%rax)
 109bba0:	mov    %r12,%rdi
 109bba3:	call   103c740 <myl_core_drop_owned>
 109bba8:	mov    0x8(%rsp),%rsi
 109bbad:	inc    %rsi
 109bbb0:	cmp    0x70(%rsp),%rsi
 109bbb5:	je     109b410 <my.diagram_membership::compute_sub_block_attachments+0x1630>
 109bbbb:	mov    0x10(%rsp),%rbx
 109bbc0:	mov    %rbx,%rdi
 109bbc3:	mov    %rsi,0x8(%rsp)
 109bbc8:	call   1043c40 <myl_core_dict_ordinal>
 109bbcd:	mov    0x20(%rbx,%rax,8),%r14
 109bbd2:	mov    %r14,0x208(%rsp)
 109bbda:	testb  $0x2,0x1(%r14)
 109bbdf:	jne    109bbf0 <my.diagram_membership::compute_sub_block_attachments+0x1e10>
 109bbe1:	mov    %r14,%rdi
 109bbe4:	call   1044400 <myl_core_str_hash>
 109bbe9:	jmp    109bbf4 <my.diagram_membership::compute_sub_block_attachments+0x1e14>
 109bbeb:	nopl   0x0(%rax,%rax,1)
 109bbf0:	mov    0x18(%r14),%eax
 109bbf4:	mov    %eax,%eax
 109bbf6:	movabs $0x9e3779b97f4a7c15,%rcx
 109bc00:	imul   %rcx,%rax
 109bc04:	mov    %rax,%rbp
 109bc07:	shr    $0x20,%rbp
 109bc0b:	xor    %rax,%rbp
 109bc0e:	mov    0x40(%rsp),%rax
 109bc13:	mov    0x18(%rax),%rcx
 109bc17:	mov    0x8(%rcx),%rax
 109bc1b:	test   %rax,%rax
 109bc1e:	je     109bcd0 <my.diagram_membership::compute_sub_block_attachments+0x1ef0>
 109bc24:	mov    (%rax),%ecx
 109bc26:	tzcnt  %ecx,%edx
 109bc2a:	neg    %dl
 109bc2c:	shrx   %rdx,%rbp,%rbx
 109bc31:	vmovdqu 0x10(%rax,%rbx,1),%xmm1
 109bc37:	mov    %ebp,%edx
 109bc39:	and    $0x7f,%dl
 109bc3c:	vmovd  %edx,%xmm0
 109bc40:	vpbroadcastb %xmm0,%xmm0
 109bc45:	vmovdqa %xmm1,0x20(%rsp)
 109bc4b:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109bc4f:	vpmovmskb %xmm0,%edx
 109bc53:	test   %edx,%edx
 109bc55:	je     109bcb4 <my.diagram_membership::compute_sub_block_attachments+0x1ed4>
 109bc57:	lea    -0x1(%rcx),%r15d
 109bc5b:	add    $0x1e,%ecx
 109bc5e:	and    $0xfffffff0,%ecx
 109bc61:	lea    (%rax,%rcx,1),%r12
 109bc65:	add    $0x10,%r12
 109bc69:	movzwl %dx,%r13d
 109bc6d:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bc7c:	nopl   0x0(%rax)
 109bc80:	tzcnt  %r13d,%eax
 109bc85:	add    %ebx,%eax
 109bc87:	and    %r15d,%eax
 109bc8a:	mov    (%r12,%rax,4),%eax
 109bc8e:	mov    0x40(%rsp),%rcx
 109bc93:	mov    0x20(%rcx,%rax,8),%rdi
 109bc98:	mov    0x208(%rsp),%rsi
 109bca0:	call   1044580 <myl_core_str_eq>
 109bca5:	test   %al,%al
 109bca7:	jne    109bba8 <my.diagram_membership::compute_sub_block_attachments+0x1dc8>
 109bcad:	blsr   %r13d,%r13d
 109bcb2:	jne    109bc80 <my.diagram_membership::compute_sub_block_attachments+0x1ea0>
 109bcb4:	vmovdqa 0x20(%rsp),%xmm0
 109bcba:	vpcmpeqb -0x978f2(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109bcc2:	vpmovmskb %xmm0,%eax
 109bcc6:	test   %eax,%eax
 109bcc8:	jne    109bd70 <my.diagram_membership::compute_sub_block_attachments+0x1f90>
 109bcce:	jmp    109bcd7 <my.diagram_membership::compute_sub_block_attachments+0x1ef7>
 109bcd0:	cmpq   $0x0,0x18(%rcx)
 109bcd5:	je     109bcfa <my.diagram_membership::compute_sub_block_attachments+0x1f1a>
 109bcd7:	mov    0x40(%rsp),%rdi
 109bcdc:	lea    0x208(%rsp),%rsi
 109bce4:	mov    %rbp,%rdx
 109bce7:	call   1042bc0 <myl_core_dict_find>
 109bcec:	mov    %rax,%r13
 109bcef:	test   %r13,%r13
 109bcf2:	jns    109bba8 <my.diagram_membership::compute_sub_block_attachments+0x1dc8>
 109bcf8:	jmp    109bd70 <my.diagram_membership::compute_sub_block_attachments+0x1f90>
 109bcfa:	mov    0x20(%rcx),%rbx
 109bcfe:	test   %rbx,%rbx
 109bd01:	je     109bd70 <my.diagram_membership::compute_sub_block_attachments+0x1f90>
 109bd03:	mov    0x10(%rcx),%r15
 109bd07:	xor    %r13d,%r13d
 109bd0a:	jmp    109bd48 <my.diagram_membership::compute_sub_block_attachments+0x1f68>
 109bd0c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bd1b:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bd2a:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bd39:	nopl   0x0(%rax)
 109bd40:	inc    %r13
 109bd43:	cmp    %r13,%rbx
 109bd46:	je     109bd70 <my.diagram_membership::compute_sub_block_attachments+0x1f90>
 109bd48:	cmp    %rbp,(%r15,%r13,8)
 109bd4c:	jne    109bd40 <my.diagram_membership::compute_sub_block_attachments+0x1f60>
 109bd4e:	mov    0x40(%rsp),%rax
 109bd53:	mov    0x20(%rax,%r13,8),%rdi
 109bd58:	mov    0x208(%rsp),%rsi
 109bd60:	call   1044580 <myl_core_str_eq>
 109bd65:	test   %al,%al
 109bd67:	je     109bd40 <my.diagram_membership::compute_sub_block_attachments+0x1f60>
 109bd69:	jmp    109bcef <my.diagram_membership::compute_sub_block_attachments+0x1f0f>
 109bd6b:	nopl   0x0(%rax,%rax,1)
 109bd70:	mov    %r14,0x200(%rsp)
 109bd78:	testb  $0x2,0x1(%r14)
 109bd7d:	jne    109bd90 <my.diagram_membership::compute_sub_block_attachments+0x1fb0>
 109bd7f:	mov    %r14,%rdi
 109bd82:	call   1044400 <myl_core_str_hash>
 109bd87:	jmp    109bd94 <my.diagram_membership::compute_sub_block_attachments+0x1fb4>
 109bd89:	nopl   0x0(%rax)
 109bd90:	mov    0x18(%r14),%eax
 109bd94:	mov    %eax,%eax
 109bd96:	movabs $0x9e3779b97f4a7c15,%rcx
 109bda0:	imul   %rcx,%rax
 109bda4:	mov    %rax,%r14
 109bda7:	shr    $0x20,%r14
 109bdab:	xor    %rax,%r14
 109bdae:	mov    (%rsp),%rax
 109bdb2:	mov    0x18(%rax),%rcx
 109bdb6:	mov    0x8(%rcx),%rax
 109bdba:	test   %rax,%rax
 109bdbd:	je     109be90 <my.diagram_membership::compute_sub_block_attachments+0x20b0>
 109bdc3:	mov    (%rax),%ecx
 109bdc5:	tzcnt  %ecx,%edx
 109bdc9:	neg    %dl
 109bdcb:	shrx   %rdx,%r14,%rbx
 109bdd0:	vmovdqu 0x10(%rax,%rbx,1),%xmm1
 109bdd6:	mov    %r14d,%edx
 109bdd9:	and    $0x7f,%dl
 109bddc:	vmovd  %edx,%xmm0
 109bde0:	vpbroadcastb %xmm0,%xmm0
 109bde5:	vmovdqa %xmm1,0x20(%rsp)
 109bdeb:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109bdef:	vpmovmskb %xmm0,%edx
 109bdf3:	test   %edx,%edx
 109bdf5:	je     109be74 <my.diagram_membership::compute_sub_block_attachments+0x2094>
 109bdfb:	lea    -0x1(%rcx),%r15d
 109bdff:	add    $0x1e,%ecx
 109be02:	and    $0xfffffff0,%ecx
 109be05:	lea    (%rax,%rcx,1),%r13
 109be09:	add    $0x10,%r13
 109be0d:	movzwl %dx,%r12d
 109be11:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109be20:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109be2f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109be3e:	xchg   %ax,%ax
 109be40:	tzcnt  %r12d,%eax
 109be45:	add    %ebx,%eax
 109be47:	and    %r15d,%eax
 109be4a:	mov    0x0(%r13,%rax,4),%ebp
 109be4f:	shl    $0x4,%rbp
 109be53:	mov    (%rsp),%rax
 109be57:	mov    0x20(%rax,%rbp,1),%rdi
 109be5c:	mov    0x200(%rsp),%rsi
 109be64:	call   1044580 <myl_core_str_eq>
 109be69:	test   %al,%al
 109be6b:	jne    109bebb <my.diagram_membership::compute_sub_block_attachments+0x20db>
 109be6d:	blsr   %r12d,%r12d
 109be72:	jne    109be40 <my.diagram_membership::compute_sub_block_attachments+0x2060>
 109be74:	vmovdqa 0x20(%rsp),%xmm0
 109be7a:	vpcmpeqb -0x97ab2(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109be82:	vpmovmskb %xmm0,%eax
 109be86:	test   %eax,%eax
 109be88:	jne    109bba8 <my.diagram_membership::compute_sub_block_attachments+0x1dc8>
 109be8e:	jmp    109be97 <my.diagram_membership::compute_sub_block_attachments+0x20b7>
 109be90:	cmpq   $0x0,0x18(%rcx)
 109be95:	je     109bf02 <my.diagram_membership::compute_sub_block_attachments+0x2122>
 109be97:	mov    (%rsp),%rdi
 109be9b:	lea    0x200(%rsp),%rsi
 109bea3:	mov    %r14,%rdx
 109bea6:	call   1042bc0 <myl_core_dict_find>
 109beab:	mov    %rax,%rbp
 109beae:	test   %rbp,%rbp
 109beb1:	js     109bba8 <my.diagram_membership::compute_sub_block_attachments+0x1dc8>
 109beb7:	shl    $0x4,%rbp
 109bebb:	mov    (%rsp),%rax
 109bebf:	mov    0x28(%rax,%rbp,1),%rsi
 109bec4:	lea    0x61de5(%rip),%rdi        # 10fdcb0 <core_durable_error.verbs+0x126b0>
 109becb:	call   1063d00 <myl_core_values_copy_box>
 109bed0:	mov    %rax,%r12
 109bed3:	cmpq   $0x1,0x8(%rax)
 109bed8:	jne    109bba0 <my.diagram_membership::compute_sub_block_attachments+0x1dc0>
 109bede:	mov    %r12,%rdi
 109bee1:	xor    %esi,%esi
 109bee3:	call   1043c40 <myl_core_dict_ordinal>
 109bee8:	mov    0x20(%r12,%rax,8),%rdi
 109beed:	mov    %rdi,0x1f8(%rsp)
 109bef5:	testb  $0x2,0x1(%rdi)
 109bef9:	jne    109bf70 <my.diagram_membership::compute_sub_block_attachments+0x2190>
 109befb:	call   1044400 <myl_core_str_hash>
 109bf00:	jmp    109bf73 <my.diagram_membership::compute_sub_block_attachments+0x2193>
 109bf02:	mov    0x20(%rcx),%rbx
 109bf06:	test   %rbx,%rbx
 109bf09:	je     109bba8 <my.diagram_membership::compute_sub_block_attachments+0x1dc8>
 109bf0f:	mov    0x10(%rcx),%r15
 109bf13:	mov    0x110(%rsp),%r12
 109bf1b:	xor    %ebp,%ebp
 109bf1d:	jmp    109bf50 <my.diagram_membership::compute_sub_block_attachments+0x2170>
 109bf1f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bf2e:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109bf3d:	nopl   (%rax)
 109bf40:	inc    %rbp
 109bf43:	add    $0x10,%r12
 109bf47:	cmp    %rbp,%rbx
 109bf4a:	je     109bba8 <my.diagram_membership::compute_sub_block_attachments+0x1dc8>
 109bf50:	cmp    %r14,(%r15,%rbp,8)
 109bf54:	jne    109bf40 <my.diagram_membership::compute_sub_block_attachments+0x2160>
 109bf56:	mov    (%r12),%rdi
 109bf5a:	mov    0x200(%rsp),%rsi
 109bf62:	call   1044580 <myl_core_str_eq>
 109bf67:	test   %al,%al
 109bf69:	je     109bf40 <my.diagram_membership::compute_sub_block_attachments+0x2160>
 109bf6b:	jmp    109beae <my.diagram_membership::compute_sub_block_attachments+0x20ce>
 109bf70:	mov    0x18(%rdi),%eax
 109bf73:	mov    %eax,%eax
 109bf75:	movabs $0x9e3779b97f4a7c15,%rcx
 109bf7f:	imul   %rcx,%rax
 109bf83:	mov    %rax,%rbp
 109bf86:	shr    $0x20,%rbp
 109bf8a:	xor    %rax,%rbp
 109bf8d:	mov    0x60(%rsp),%rax
 109bf92:	mov    0x18(%rax),%rcx
 109bf96:	mov    0x8(%rcx),%rax
 109bf9a:	test   %rax,%rax
 109bf9d:	je     109c039 <my.diagram_membership::compute_sub_block_attachments+0x2259>
 109bfa3:	mov    %r12,0x20(%rsp)
 109bfa8:	mov    (%rax),%ecx
 109bfaa:	tzcnt  %ecx,%edx
 109bfae:	neg    %dl
 109bfb0:	shrx   %rdx,%rbp,%rbx
 109bfb5:	vmovdqu 0x10(%rax,%rbx,1),%xmm1
 109bfbb:	mov    %ebp,%edx
 109bfbd:	and    $0x7f,%dl
 109bfc0:	vmovd  %edx,%xmm0
 109bfc4:	vpbroadcastb %xmm0,%xmm0
 109bfc9:	vmovdqa %xmm1,0x80(%rsp)
 109bfd2:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109bfd6:	vpmovmskb %xmm0,%edx
 109bfda:	test   %edx,%edx
 109bfdc:	je     109bb77 <my.diagram_membership::compute_sub_block_attachments+0x1d97>
 109bfe2:	lea    -0x1(%rcx),%r15d
 109bfe6:	add    $0x1e,%ecx
 109bfe9:	and    $0xfffffff0,%ecx
 109bfec:	lea    (%rax,%rcx,1),%r14
 109bff0:	add    $0x10,%r14
 109bff4:	movzwl %dx,%r12d
 109bff8:	nopl   0x0(%rax,%rax,1)
 109c000:	tzcnt  %r12d,%eax
 109c005:	add    %ebx,%eax
 109c007:	and    %r15d,%eax
 109c00a:	mov    (%r14,%rax,4),%r13d
 109c00e:	shl    $0x4,%r13
 109c012:	mov    0x60(%rsp),%rax
 109c017:	mov    0x20(%rax,%r13,1),%rdi
 109c01c:	mov    0x1f8(%rsp),%rsi
 109c024:	call   1044580 <myl_core_str_eq>
 109c029:	test   %al,%al
 109c02b:	jne    109c06e <my.diagram_membership::compute_sub_block_attachments+0x228e>
 109c02d:	blsr   %r12d,%r12d
 109c032:	jne    109c000 <my.diagram_membership::compute_sub_block_attachments+0x2220>
 109c034:	jmp    109bb77 <my.diagram_membership::compute_sub_block_attachments+0x1d97>
 109c039:	cmpq   $0x0,0x18(%rcx)
 109c03e:	je     109c0d6 <my.diagram_membership::compute_sub_block_attachments+0x22f6>
 109c044:	mov    0x60(%rsp),%rdi
 109c049:	lea    0x1f8(%rsp),%rsi
 109c051:	mov    %rbp,%rdx
 109c054:	call   1042bc0 <myl_core_dict_find>
 109c059:	mov    %rax,%r13
 109c05c:	test   %r13,%r13
 109c05f:	js     109bba0 <my.diagram_membership::compute_sub_block_attachments+0x1dc0>
 109c065:	mov    %r12,0x20(%rsp)
 109c06a:	shl    $0x4,%r13
 109c06e:	mov    0x60(%rsp),%rax
 109c073:	mov    0x28(%rax,%r13,1),%rsi
 109c078:	mov    %rsi,%rax
 109c07b:	mov    0xc0(%rsp),%rdx
 109c083:	imul   %rdx,%rax
 109c087:	jo     109eb60 <my.diagram_membership::compute_sub_block_attachments+0x4d80>
 109c08d:	mov    %rax,%rsi
 109c090:	mov    0x98(%rsp),%rdx
 109c098:	add    %rdx,%rsi
 109c09b:	mov    0x1e8(%rsp),%rdi
 109c0a3:	jo     109eb85 <my.diagram_membership::compute_sub_block_attachments+0x4da5>
 109c0a9:	mov    0x8(%rdi),%rdx
 109c0ad:	cmp    %rdx,%rsi
 109c0b0:	mov    0x20(%rsp),%r12
 109c0b5:	jae    109eb6c <my.diagram_membership::compute_sub_block_attachments+0x4d8c>
 109c0bb:	mov    0x20(%rdi,%rsi,8),%rax
 109c0c0:	mov    %rax,%rcx
 109c0c3:	inc    %rcx
 109c0c6:	jo     109eb4c <my.diagram_membership::compute_sub_block_attachments+0x4d6c>
 109c0cc:	mov    %rcx,0x20(%rdi,%rsi,8)
 109c0d1:	jmp    109bba0 <my.diagram_membership::compute_sub_block_attachments+0x1dc0>
 109c0d6:	mov    0x20(%rcx),%rbx
 109c0da:	test   %rbx,%rbx
 109c0dd:	je     109bba0 <my.diagram_membership::compute_sub_block_attachments+0x1dc0>
 109c0e3:	mov    0x10(%rcx),%r14
 109c0e7:	mov    0x108(%rsp),%r15
 109c0ef:	xor    %r13d,%r13d
 109c0f2:	jmp    109c110 <my.diagram_membership::compute_sub_block_attachments+0x2330>
 109c0f4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109c100:	inc    %r13
 109c103:	add    $0x10,%r15
 109c107:	cmp    %r13,%rbx
 109c10a:	je     109bba0 <my.diagram_membership::compute_sub_block_attachments+0x1dc0>
 109c110:	cmp    %rbp,(%r14,%r13,8)
 109c114:	jne    109c100 <my.diagram_membership::compute_sub_block_attachments+0x2320>
 109c116:	mov    (%r15),%rdi
 109c119:	mov    0x1f8(%rsp),%rsi
 109c121:	call   1044580 <myl_core_str_eq>
 109c126:	test   %al,%al
 109c128:	je     109c100 <my.diagram_membership::compute_sub_block_attachments+0x2320>
 109c12a:	jmp    109c05c <my.diagram_membership::compute_sub_block_attachments+0x227c>
 109c12f:	mov    (%rsp),%rdi
 109c133:	call   103c740 <myl_core_drop_owned>
 109c138:	mov    0x60(%rsp),%rdi
 109c13d:	call   103c740 <myl_core_drop_owned>
 109c142:	mov    0x40(%rsp),%rdi
 109c147:	call   103c740 <myl_core_drop_owned>
 109c14c:	cmpq   $0x0,0x128(%rsp)
 109c155:	je     109e9e1 <my.diagram_membership::compute_sub_block_attachments+0x4c01>
 109c15b:	addq   $0x20,0x100(%rsp)
 109c164:	addq   $0x20,0xa0(%rsp)
 109c16d:	mov    0x120(%rsp),%rax
 109c175:	add    $0x20,%rax
 109c179:	mov    %rax,0x250(%rsp)
 109c181:	lea    0x20(%r15),%rax
 109c185:	mov    %rax,0x258(%rsp)
 109c18d:	xor    %esi,%esi
 109c18f:	jmp    109c1d9 <my.diagram_membership::compute_sub_block_attachments+0x23f9>
 109c191:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109c1a0:	mov    %rsi,%rax
 109c1a3:	shl    $0x4,%rax
 109c1a7:	movzbl 0x90(%rsp),%ecx
 109c1af:	mov    0x250(%rsp),%rdx
 109c1b7:	mov    %rcx,(%rdx,%rax,1)
 109c1bb:	mov    0xa8(%rsp),%rcx
 109c1c3:	mov    %rcx,0x8(%rdx,%rax,1)
 109c1c8:	inc    %rsi
 109c1cb:	cmp    0x128(%rsp),%rsi
 109c1d3:	je     109e9e1 <my.diagram_membership::compute_sub_block_attachments+0x4c01>
 109c1d9:	mov    %rsi,0xf8(%rsp)
 109c1e1:	imul   $0x428,%rsi,%rax
 109c1e8:	mov    0x100(%rsp),%rcx
 109c1f0:	mov    (%rcx,%rax,1),%rdi
 109c1f4:	mov    0x8(%rcx,%rax,1),%r12
 109c1f9:	mov    0x10(%rcx,%rax,1),%r13
 109c1fe:	mov    0x18(%rcx,%rax,1),%r15
 109c203:	mov    0x20(%rcx,%rax,1),%rbp
 109c208:	mov    0x28(%rcx,%rax,1),%r14
 109c20d:	mov    0x30(%rcx,%rax,1),%rbx
 109c212:	mov    0x38(%rcx,%rax,1),%rdx
 109c217:	mov    %rdx,0x130(%rsp)
 109c21f:	mov    0x40(%rcx,%rax,1),%rdx
 109c224:	mov    %rdx,0x138(%rsp)
 109c22c:	mov    0x48(%rcx,%rax,1),%rdx
 109c231:	mov    %rdx,0x140(%rsp)
 109c239:	mov    0x50(%rcx,%rax,1),%rdx
 109c23e:	mov    %rdx,0x148(%rsp)
 109c246:	mov    0x60(%rcx,%rax,1),%rdx
 109c24b:	mov    %rdx,0x150(%rsp)
 109c253:	mov    0x68(%rcx,%rax,1),%rdx
 109c258:	mov    %rdx,0x158(%rsp)
 109c260:	mov    0x70(%rcx,%rax,1),%rdx
 109c265:	mov    %rdx,0x160(%rsp)
 109c26d:	mov    0x78(%rcx,%rax,1),%rdx
 109c272:	mov    %rdx,0x168(%rsp)
 109c27a:	mov    0x80(%rcx,%rax,1),%rdx
 109c282:	mov    %rdx,0x170(%rsp)
 109c28a:	mov    0x88(%rcx,%rax,1),%rdx
 109c292:	mov    %rdx,0x178(%rsp)
 109c29a:	mov    0x90(%rcx,%rax,1),%rdx
 109c2a2:	mov    %rdx,0x180(%rsp)
 109c2aa:	mov    0x98(%rcx,%rax,1),%rdx
 109c2b2:	mov    %rdx,0x188(%rsp)
 109c2ba:	mov    0xa0(%rcx,%rax,1),%rdx
 109c2c2:	mov    %rdx,0x190(%rsp)
 109c2ca:	mov    0xa8(%rcx,%rax,1),%rdx
 109c2d2:	mov    %rdx,0x198(%rsp)
 109c2da:	mov    0xb0(%rcx,%rax,1),%rdx
 109c2e2:	mov    %rdx,0x1a0(%rsp)
 109c2ea:	mov    0xb8(%rcx,%rax,1),%rdx
 109c2f2:	mov    %rdx,0x1a8(%rsp)
 109c2fa:	mov    0xc0(%rcx,%rax,1),%rdx
 109c302:	mov    %rdx,0x1b0(%rsp)
 109c30a:	mov    0xc8(%rcx,%rax,1),%rdx
 109c312:	mov    %rdx,0x1b8(%rsp)
 109c31a:	mov    0xd0(%rcx,%rax,1),%rdx
 109c322:	mov    %rdx,0x1c0(%rsp)
 109c32a:	mov    0xd8(%rcx,%rax,1),%rdx
 109c332:	mov    %rdx,0x1c8(%rsp)
 109c33a:	mov    0xe0(%rcx,%rax,1),%rdx
 109c342:	mov    %rdx,0x1d0(%rsp)
 109c34a:	mov    0xe8(%rcx,%rax,1),%rdx
 109c352:	mov    %rdx,0x1d8(%rsp)
 109c35a:	mov    0xf0(%rcx,%rax,1),%rdx
 109c362:	mov    %rdx,0x1e0(%rsp)
 109c36a:	mov    0xf8(%rcx,%rax,1),%rdx
 109c372:	mov    %rdx,0x108(%rsp)
 109c37a:	mov    0x100(%rcx,%rax,1),%rdx
 109c382:	mov    %rdx,0x110(%rsp)
 109c38a:	mov    0x110(%rcx,%rax,1),%rdx
 109c392:	mov    %rdx,0x118(%rsp)
 109c39a:	mov    0x148(%rcx,%rax,1),%rdx
 109c3a2:	mov    %rdx,0xd0(%rsp)
 109c3aa:	mov    0x150(%rcx,%rax,1),%edx
 109c3b1:	mov    %rdx,0x20(%rsp)
 109c3b6:	mov    0x180(%rcx,%rax,1),%rdx
 109c3be:	mov    %rdx,0x2a0(%rsp)
 109c3c6:	mov    0x188(%rcx,%rax,1),%rdx
 109c3ce:	mov    %rdx,0x2a8(%rsp)
 109c3d6:	mov    0x190(%rcx,%rax,1),%rdx
 109c3de:	mov    %rdx,0x2b0(%rsp)
 109c3e6:	mov    0x198(%rcx,%rax,1),%rdx
 109c3ee:	mov    %rdx,0x2b8(%rsp)
 109c3f6:	mov    0x1a0(%rcx,%rax,1),%rdx
 109c3fe:	mov    %rdx,0x2c0(%rsp)
 109c406:	mov    0x1f0(%rcx,%rax,1),%edx
 109c40d:	mov    %rdx,0x8(%rsp)
 109c412:	mov    0x1f8(%rcx,%rax,1),%rdx
 109c41a:	mov    %rdx,0x2c8(%rsp)
 109c422:	mov    0x270(%rcx,%rax,1),%rdx
 109c42a:	mov    %rdx,0xd8(%rsp)
 109c432:	mov    0x278(%rcx,%rax,1),%rdx
 109c43a:	mov    %rdx,0xb0(%rsp)
 109c442:	mov    0x280(%rcx,%rax,1),%rdx
 109c44a:	mov    %rdx,0xe0(%rsp)
 109c452:	mov    0x290(%rcx,%rax,1),%rdx
 109c45a:	mov    %rdx,0xe8(%rsp)
 109c462:	mov    0x298(%rcx,%rax,1),%rdx
 109c46a:	mov    %rdx,0xf0(%rsp)
 109c472:	mov    0x2a0(%rcx,%rax,1),%rdx
 109c47a:	mov    %rdx,0xb8(%rsp)
 109c482:	mov    0x2b0(%rcx,%rax,1),%rdx
 109c48a:	mov    %rdx,0xa8(%rsp)
 109c492:	mov    0x2b8(%rcx,%rax,1),%rdx
 109c49a:	mov    %rdx,0x90(%rsp)
 109c4a2:	mov    0x2c0(%rcx,%rax,1),%rdx
 109c4aa:	mov    %rdx,0x98(%rsp)
 109c4b2:	mov    0x2c8(%rcx,%rax,1),%rdx
 109c4ba:	mov    %rdx,0xc8(%rsp)
 109c4c2:	mov    0x2d0(%rcx,%rax,1),%rdx
 109c4ca:	mov    %rdx,0x30(%rsp)
 109c4cf:	mov    0x2f0(%rcx,%rax,1),%rdx
 109c4d7:	mov    %rdx,0x60(%rsp)
 109c4dc:	mov    0x2f8(%rcx,%rax,1),%rdx
 109c4e4:	mov    %rdx,0x38(%rsp)
 109c4e9:	mov    0x3b0(%rcx,%rax,1),%rdx
 109c4f1:	mov    %rdx,(%rsp)
 109c4f5:	mov    0x3c8(%rcx,%rax,1),%rdx
 109c4fd:	mov    %rdx,0x40(%rsp)
 109c502:	mov    0x3d0(%rcx,%rax,1),%edx
 109c509:	mov    %rdx,0x70(%rsp)
 109c50e:	mov    0x3d8(%rcx,%rax,1),%rdx
 109c516:	mov    %rdx,0x2d0(%rsp)
 109c51e:	mov    0x3e0(%rcx,%rax,1),%rdx
 109c526:	mov    %rdx,0x2d8(%rsp)
 109c52e:	mov    0x418(%rcx,%rax,1),%rax
 109c536:	mov    %rax,0x80(%rsp)
 109c53e:	call   103cfc0 <myl_core_owned_octets_copy>
 109c543:	mov    %rax,0x10(%rsp)
 109c548:	mov    %r12,%rdi
 109c54b:	call   103cfc0 <myl_core_owned_octets_copy>
 109c550:	mov    %rax,0x308(%rsp)
 109c558:	lea    0x5d981(%rip),%rdi        # 10f9ee0 <core_durable_error.verbs+0xe8e0>
 109c55f:	mov    %r13,%rsi
 109c562:	call   1063d00 <myl_core_values_copy_box>
 109c567:	mov    %rax,0x300(%rsp)
 109c56f:	lea    0x5da6a(%rip),%rdi        # 10f9fe0 <core_durable_error.verbs+0xe9e0>
 109c576:	mov    %r15,%rsi
 109c579:	call   1063d00 <myl_core_values_copy_box>
 109c57e:	mov    %rax,0x2f8(%rsp)
 109c586:	lea    0x5db73(%rip),%rdi        # 10fa100 <core_durable_error.verbs+0xeb00>
 109c58d:	mov    %rbp,%rsi
 109c590:	call   1063d00 <myl_core_values_copy_box>
 109c595:	mov    %rax,0x2f0(%rsp)
 109c59d:	lea    0x5dbcc(%rip),%rdi        # 10fa170 <core_durable_error.verbs+0xeb70>
 109c5a4:	mov    %r14,%rsi
 109c5a7:	call   1063d00 <myl_core_values_copy_box>
 109c5ac:	mov    %rax,0x2e8(%rsp)
 109c5b4:	lea    0x5dc25(%rip),%rdi        # 10fa1e0 <core_durable_error.verbs+0xebe0>
 109c5bb:	mov    %rbx,%rsi
 109c5be:	call   1063d00 <myl_core_values_copy_box>
 109c5c3:	mov    %rax,0x2e0(%rsp)
 109c5cb:	lea    0x5dc8e(%rip),%rdi        # 10fa260 <core_durable_error.verbs+0xec60>
 109c5d2:	mov    0x130(%rsp),%rsi
 109c5da:	call   1063d00 <myl_core_values_copy_box>
 109c5df:	mov    %rax,0x130(%rsp)
 109c5e7:	lea    0x5e102(%rip),%rdi        # 10fa6f0 <core_durable_error.verbs+0xf0f0>
 109c5ee:	mov    0x138(%rsp),%rsi
 109c5f6:	call   1063d00 <myl_core_values_copy_box>
 109c5fb:	mov    %rax,0x138(%rsp)
 109c603:	lea    0x5e286(%rip),%rdi        # 10fa890 <core_durable_error.verbs+0xf290>
 109c60a:	mov    0x140(%rsp),%rsi
 109c612:	call   1063d00 <myl_core_values_copy_box>
 109c617:	mov    %rax,0x140(%rsp)
 109c61f:	lea    0x5e2ea(%rip),%rdi        # 10fa910 <core_durable_error.verbs+0xf310>
 109c626:	mov    0x148(%rsp),%rsi
 109c62e:	call   1063d00 <myl_core_values_copy_box>
 109c633:	mov    %rax,0x148(%rsp)
 109c63b:	mov    0x150(%rsp),%rdi
 109c643:	call   103cfc0 <myl_core_owned_octets_copy>
 109c648:	mov    %rax,0x150(%rsp)
 109c650:	lea    0x5e369(%rip),%rdi        # 10fa9c0 <core_durable_error.verbs+0xf3c0>
 109c657:	mov    0x158(%rsp),%rsi
 109c65f:	call   1063d00 <myl_core_values_copy_box>
 109c664:	mov    %rax,0x158(%rsp)
 109c66c:	lea    0x5e3ed(%rip),%rdi        # 10faa60 <core_durable_error.verbs+0xf460>
 109c673:	mov    0x160(%rsp),%rsi
 109c67b:	call   1063d00 <myl_core_values_copy_box>
 109c680:	mov    %rax,0x160(%rsp)
 109c688:	lea    0x5e601(%rip),%rdi        # 10fac90 <core_durable_error.verbs+0xf690>
 109c68f:	mov    0x168(%rsp),%rsi
 109c697:	call   1063d00 <myl_core_values_copy_box>
 109c69c:	mov    %rax,0x168(%rsp)
 109c6a4:	lea    0x5e6d5(%rip),%rdi        # 10fad80 <core_durable_error.verbs+0xf780>
 109c6ab:	mov    0x170(%rsp),%rsi
 109c6b3:	call   1063d00 <myl_core_values_copy_box>
 109c6b8:	mov    %rax,0x170(%rsp)
 109c6c0:	lea    0x5e829(%rip),%rdi        # 10faef0 <core_durable_error.verbs+0xf8f0>
 109c6c7:	mov    0x178(%rsp),%rsi
 109c6cf:	call   1063d00 <myl_core_values_copy_box>
 109c6d4:	mov    %rax,0x178(%rsp)
 109c6dc:	lea    0x5e89d(%rip),%rdi        # 10faf80 <core_durable_error.verbs+0xf980>
 109c6e3:	mov    0x180(%rsp),%rsi
 109c6eb:	call   1063d00 <myl_core_values_copy_box>
 109c6f0:	mov    %rax,0x180(%rsp)
 109c6f8:	lea    0x5e8f1(%rip),%rdi        # 10faff0 <core_durable_error.verbs+0xf9f0>
 109c6ff:	mov    0x188(%rsp),%rsi
 109c707:	call   1063d00 <myl_core_values_copy_box>
 109c70c:	mov    %rax,0x188(%rsp)
 109c714:	lea    0x5e975(%rip),%rdi        # 10fb090 <core_durable_error.verbs+0xfa90>
 109c71b:	mov    0x190(%rsp),%rsi
 109c723:	call   1063d00 <myl_core_values_copy_box>
 109c728:	mov    %rax,0x190(%rsp)
 109c730:	lea    0x5ea79(%rip),%rdi        # 10fb1b0 <core_durable_error.verbs+0xfbb0>
 109c737:	mov    0x198(%rsp),%rsi
 109c73f:	call   1063d00 <myl_core_values_copy_box>
 109c744:	mov    %rax,0x198(%rsp)
 109c74c:	lea    0x5eadd(%rip),%rdi        # 10fb230 <core_durable_error.verbs+0xfc30>
 109c753:	mov    0x1a0(%rsp),%rsi
 109c75b:	call   1063d00 <myl_core_values_copy_box>
 109c760:	mov    %rax,0x1a0(%rsp)
 109c768:	lea    0x5ebf1(%rip),%rdi        # 10fb360 <core_durable_error.verbs+0xfd60>
 109c76f:	mov    0x1a8(%rsp),%rsi
 109c777:	call   1063d00 <myl_core_values_copy_box>
 109c77c:	mov    %rax,0x1a8(%rsp)
 109c784:	lea    0x5ed55(%rip),%rdi        # 10fb4e0 <core_durable_error.verbs+0xfee0>
 109c78b:	mov    0x1b0(%rsp),%rsi
 109c793:	call   1063d00 <myl_core_values_copy_box>
 109c798:	mov    %rax,0x1b0(%rsp)
 109c7a0:	lea    0x5ed99(%rip),%rdi        # 10fb540 <core_durable_error.verbs+0xff40>
 109c7a7:	mov    0x1b8(%rsp),%rsi
 109c7af:	call   1063d00 <myl_core_values_copy_box>
 109c7b4:	mov    %rax,0x1b8(%rsp)
 109c7bc:	lea    0x5eded(%rip),%rdi        # 10fb5b0 <core_durable_error.verbs+0xffb0>
 109c7c3:	mov    0x1c0(%rsp),%rsi
 109c7cb:	call   1063d00 <myl_core_values_copy_box>
 109c7d0:	mov    %rax,0x1c0(%rsp)
 109c7d8:	lea    0x5ee81(%rip),%rdi        # 10fb660 <core_durable_error.verbs+0x10060>
 109c7df:	mov    0x1c8(%rsp),%rsi
 109c7e7:	call   1063d00 <myl_core_values_copy_box>
 109c7ec:	mov    %rax,0x1c8(%rsp)
 109c7f4:	mov    0x1d0(%rsp),%rdi
 109c7fc:	call   103cfc0 <myl_core_owned_octets_copy>
 109c801:	mov    %rax,0x1d0(%rsp)
 109c809:	mov    0x1d8(%rsp),%rdi
 109c811:	call   103cfc0 <myl_core_owned_octets_copy>
 109c816:	mov    %rax,0x1d8(%rsp)
 109c81e:	lea    0x5f00b(%rip),%rdi        # 10fb830 <core_durable_error.verbs+0x10230>
 109c825:	mov    0x1e0(%rsp),%rsi
 109c82d:	call   1063d00 <myl_core_values_copy_box>
 109c832:	mov    %rax,0x1e0(%rsp)
 109c83a:	lea    0x5efbf(%rip),%rdi        # 10fb800 <core_durable_error.verbs+0x10200>
 109c841:	mov    0x108(%rsp),%rsi
 109c849:	call   1063d00 <myl_core_values_copy_box>
 109c84e:	mov    %rax,0x108(%rsp)
 109c856:	mov    0x110(%rsp),%rdi
 109c85e:	call   103cfc0 <myl_core_owned_octets_copy>
 109c863:	mov    %rax,0x110(%rsp)
 109c86b:	lea    0x5c3de(%rip),%rdi        # 10f8c50 <core_durable_error.verbs+0xd650>
 109c872:	mov    0x118(%rsp),%rsi
 109c87a:	call   1063d00 <myl_core_values_copy_box>
 109c87f:	mov    %rax,0x118(%rsp)
 109c887:	lea    0x5f232(%rip),%rdi        # 10fbac0 <core_durable_error.verbs+0x104c0>
 109c88e:	mov    0xd0(%rsp),%rsi
 109c896:	call   1063d00 <myl_core_values_copy_box>
 109c89b:	mov    %rax,0xd0(%rsp)
 109c8a3:	cmpq   $0x0,0x20(%rsp)
 109c8a9:	je     109c914 <my.diagram_membership::compute_sub_block_attachments+0x2b34>
 109c8ab:	mov    0x2a0(%rsp),%rdi
 109c8b3:	call   103cfc0 <myl_core_owned_octets_copy>
 109c8b8:	mov    %rax,0x298(%rsp)
 109c8c0:	mov    0x2a8(%rsp),%rdi
 109c8c8:	call   103cfc0 <myl_core_owned_octets_copy>
 109c8cd:	mov    %rax,0x280(%rsp)
 109c8d5:	mov    0x2b0(%rsp),%rdi
 109c8dd:	call   103cfc0 <myl_core_owned_octets_copy>
 109c8e2:	mov    %rax,0x278(%rsp)
 109c8ea:	mov    0x2b8(%rsp),%rdi
 109c8f2:	call   103cfc0 <myl_core_owned_octets_copy>
 109c8f7:	mov    %rax,0x268(%rsp)
 109c8ff:	mov    0x2c0(%rsp),%rdi
 109c907:	call   103cfc0 <myl_core_owned_octets_copy>
 109c90c:	mov    %rax,0x260(%rsp)
 109c914:	cmpq   $0x0,0x8(%rsp)
 109c91a:	je     109c931 <my.diagram_membership::compute_sub_block_attachments+0x2b51>
 109c91c:	mov    0x2c8(%rsp),%rdi
 109c924:	call   103cfc0 <myl_core_owned_octets_copy>
 109c929:	mov    %rax,0x290(%rsp)
 109c931:	mov    0xd8(%rsp),%rdi
 109c939:	call   103cfc0 <myl_core_owned_octets_copy>
 109c93e:	mov    %rax,0xd8(%rsp)
 109c946:	mov    0xb0(%rsp),%rdi
 109c94e:	call   103cfc0 <myl_core_owned_octets_copy>
 109c953:	mov    %rax,0xb0(%rsp)
 109c95b:	lea    0x5f5ce(%rip),%rdi        # 10fbf30 <core_durable_error.verbs+0x10930>
 109c962:	mov    0xe0(%rsp),%rsi
 109c96a:	call   1063d00 <myl_core_values_copy_box>
 109c96f:	mov    %rax,0xe0(%rsp)
 109c977:	mov    0xe8(%rsp),%rdi
 109c97f:	call   103cfc0 <myl_core_owned_octets_copy>
 109c984:	mov    %rax,0xe8(%rsp)
 109c98c:	lea    0x5f65d(%rip),%rbx        # 10fbff0 <core_durable_error.verbs+0x109f0>
 109c993:	mov    %rbx,%rdi
 109c996:	mov    0xf0(%rsp),%rsi
 109c99e:	call   1063d00 <myl_core_values_copy_box>
 109c9a3:	mov    %rax,0xf0(%rsp)
 109c9ab:	mov    %rbx,%rdi
 109c9ae:	mov    0xb8(%rsp),%rsi
 109c9b6:	call   1063d00 <myl_core_values_copy_box>
 109c9bb:	mov    %rax,0xb8(%rsp)
 109c9c3:	lea    0x5f706(%rip),%rdi        # 10fc0d0 <core_durable_error.verbs+0x10ad0>
 109c9ca:	mov    0xa8(%rsp),%rsi
 109c9d2:	call   1063d00 <myl_core_values_copy_box>
 109c9d7:	mov    %rax,0xa8(%rsp)
 109c9df:	lea    0x5f7ba(%rip),%rdi        # 10fc1a0 <core_durable_error.verbs+0x10ba0>
 109c9e6:	mov    0x90(%rsp),%rsi
 109c9ee:	call   1063d00 <myl_core_values_copy_box>
 109c9f3:	mov    %rax,0x90(%rsp)
 109c9fb:	lea    0x5f86e(%rip),%rdi        # 10fc270 <core_durable_error.verbs+0x10c70>
 109ca02:	mov    0x98(%rsp),%rsi
 109ca0a:	call   1063d00 <myl_core_values_copy_box>
 109ca0f:	mov    %rax,0x98(%rsp)
 109ca17:	lea    0x5f8e2(%rip),%rdi        # 10fc300 <core_durable_error.verbs+0x10d00>
 109ca1e:	mov    0xc8(%rsp),%rsi
 109ca26:	call   1063d00 <myl_core_values_copy_box>
 109ca2b:	mov    %rax,0xc8(%rsp)
 109ca33:	mov    0x30(%rsp),%rdi
 109ca38:	call   103cfc0 <myl_core_owned_octets_copy>
 109ca3d:	mov    %rax,0x30(%rsp)
 109ca42:	lea    0x5faa7(%rip),%rdi        # 10fc4f0 <core_durable_error.verbs+0x10ef0>
 109ca49:	mov    0x60(%rsp),%rsi
 109ca4e:	call   1063d00 <myl_core_values_copy_box>
 109ca53:	mov    %rax,0x60(%rsp)
 109ca58:	lea    0x5ff01(%rip),%rdi        # 10fc960 <core_durable_error.verbs+0x11360>
 109ca5f:	mov    0x38(%rsp),%rsi
 109ca64:	call   1063d00 <myl_core_values_copy_box>
 109ca69:	mov    %rax,0x38(%rsp)
 109ca6e:	lea    0x6018b(%rip),%rdi        # 10fcc00 <core_durable_error.verbs+0x11600>
 109ca75:	mov    (%rsp),%rsi
 109ca79:	call   1063d00 <myl_core_values_copy_box>
 109ca7e:	mov    %rax,%r13
 109ca81:	mov    0x40(%rsp),%rdi
 109ca86:	test   %rdi,%rdi
 109ca89:	mov    0x58(%rsp),%rbx
 109ca8e:	mov    0x70(%rsp),%r15
 109ca93:	mov    0x10(%rsp),%r14
 109ca98:	je     109cf20 <my.diagram_membership::compute_sub_block_attachments+0x3140>
 109ca9e:	call   103cfc0 <myl_core_owned_octets_copy>
 109caa3:	mov    %rax,%rbp
 109caa6:	test   %r15,%r15
 109caa9:	je     109cae7 <my.diagram_membership::compute_sub_block_attachments+0x2d07>
 109caab:	lea    0x606ce(%rip),%r14        # 10fd180 <core_durable_error.verbs+0x11b80>
 109cab2:	mov    %r14,%rdi
 109cab5:	mov    0x2d0(%rsp),%rsi
 109cabd:	call   1063d00 <myl_core_values_copy_box>
 109cac2:	mov    %rax,0x288(%rsp)
 109caca:	mov    %r14,%rdi
 109cacd:	mov    0x10(%rsp),%r14
 109cad2:	mov    0x2d8(%rsp),%rsi
 109cada:	call   1063d00 <myl_core_values_copy_box>
 109cadf:	mov    %rax,0x270(%rsp)
 109cae7:	mov    0x80(%rsp),%rdi
 109caef:	call   103cfc0 <myl_core_owned_octets_copy>
 109caf4:	mov    %rax,%r12
 109caf7:	mov    %r14,%rdi
 109cafa:	call   104ba40 <myl_core_bytes_utf8_count>
 109caff:	test   %rax,%rax
 109cb02:	js     109e9b0 <my.diagram_membership::compute_sub_block_attachments+0x4bd0>
 109cb08:	mov    %r14,%rdi
 109cb0b:	call   104bb00 <myl_core_bytes_decode_text>
 109cb10:	mov    %rax,%r14
 109cb13:	xor    %eax,%eax
 109cb15:	test   %al,%al
 109cb17:	jne    109e9cd <my.diagram_membership::compute_sub_block_attachments+0x4bed>
 109cb1d:	mov    0x10(%rsp),%rdi
 109cb22:	call   103c740 <myl_core_drop_owned>
 109cb27:	mov    0x308(%rsp),%rdi
 109cb2f:	call   103c740 <myl_core_drop_owned>
 109cb34:	mov    0x300(%rsp),%rdi
 109cb3c:	call   103c740 <myl_core_drop_owned>
 109cb41:	mov    0x2f8(%rsp),%rdi
 109cb49:	call   103c740 <myl_core_drop_owned>
 109cb4e:	mov    0x2f0(%rsp),%rdi
 109cb56:	call   103c740 <myl_core_drop_owned>
 109cb5b:	mov    0x2e8(%rsp),%rdi
 109cb63:	call   103c740 <myl_core_drop_owned>
 109cb68:	mov    0x2e0(%rsp),%rdi
 109cb70:	call   103c740 <myl_core_drop_owned>
 109cb75:	mov    0x130(%rsp),%rdi
 109cb7d:	call   103c740 <myl_core_drop_owned>
 109cb82:	mov    0x138(%rsp),%rdi
 109cb8a:	call   103c740 <myl_core_drop_owned>
 109cb8f:	mov    0x140(%rsp),%rdi
 109cb97:	call   103c740 <myl_core_drop_owned>
 109cb9c:	mov    0x148(%rsp),%rdi
 109cba4:	call   103c740 <myl_core_drop_owned>
 109cba9:	mov    0x150(%rsp),%rdi
 109cbb1:	call   103c740 <myl_core_drop_owned>
 109cbb6:	mov    0x158(%rsp),%rdi
 109cbbe:	call   103c740 <myl_core_drop_owned>
 109cbc3:	mov    0x160(%rsp),%rdi
 109cbcb:	call   103c740 <myl_core_drop_owned>
 109cbd0:	mov    0x168(%rsp),%rdi
 109cbd8:	call   103c740 <myl_core_drop_owned>
 109cbdd:	mov    0x170(%rsp),%rdi
 109cbe5:	call   103c740 <myl_core_drop_owned>
 109cbea:	mov    0x178(%rsp),%rdi
 109cbf2:	call   103c740 <myl_core_drop_owned>
 109cbf7:	mov    0x180(%rsp),%rdi
 109cbff:	call   103c740 <myl_core_drop_owned>
 109cc04:	mov    0x188(%rsp),%rdi
 109cc0c:	call   103c740 <myl_core_drop_owned>
 109cc11:	mov    0x190(%rsp),%rdi
 109cc19:	call   103c740 <myl_core_drop_owned>
 109cc1e:	mov    0x198(%rsp),%rdi
 109cc26:	call   103c740 <myl_core_drop_owned>
 109cc2b:	mov    0x1a0(%rsp),%rdi
 109cc33:	call   103c740 <myl_core_drop_owned>
 109cc38:	mov    0x1a8(%rsp),%rdi
 109cc40:	call   103c740 <myl_core_drop_owned>
 109cc45:	mov    0x1b0(%rsp),%rdi
 109cc4d:	call   103c740 <myl_core_drop_owned>
 109cc52:	mov    0x1b8(%rsp),%rdi
 109cc5a:	call   103c740 <myl_core_drop_owned>
 109cc5f:	mov    0x1c0(%rsp),%rdi
 109cc67:	call   103c740 <myl_core_drop_owned>
 109cc6c:	mov    0x1c8(%rsp),%rdi
 109cc74:	call   103c740 <myl_core_drop_owned>
 109cc79:	mov    0x1d0(%rsp),%rdi
 109cc81:	call   103c740 <myl_core_drop_owned>
 109cc86:	mov    0x1d8(%rsp),%rdi
 109cc8e:	call   103c740 <myl_core_drop_owned>
 109cc93:	mov    0x1e0(%rsp),%rdi
 109cc9b:	call   103c740 <myl_core_drop_owned>
 109cca0:	mov    0x108(%rsp),%rdi
 109cca8:	call   103c740 <myl_core_drop_owned>
 109ccad:	mov    0x110(%rsp),%rdi
 109ccb5:	call   103c740 <myl_core_drop_owned>
 109ccba:	mov    0x118(%rsp),%rdi
 109ccc2:	call   103c740 <myl_core_drop_owned>
 109ccc7:	mov    0xd0(%rsp),%rdi
 109cccf:	call   103c740 <myl_core_drop_owned>
 109ccd4:	cmpq   $0x0,0x20(%rsp)
 109ccda:	je     109cd1d <my.diagram_membership::compute_sub_block_attachments+0x2f3d>
 109ccdc:	mov    0x298(%rsp),%rdi
 109cce4:	call   103c740 <myl_core_drop_owned>
 109cce9:	mov    0x280(%rsp),%rdi
 109ccf1:	call   103c740 <myl_core_drop_owned>
 109ccf6:	mov    0x278(%rsp),%rdi
 109ccfe:	call   103c740 <myl_core_drop_owned>
 109cd03:	mov    0x268(%rsp),%rdi
 109cd0b:	call   103c740 <myl_core_drop_owned>
 109cd10:	mov    0x260(%rsp),%rdi
 109cd18:	call   103c740 <myl_core_drop_owned>
 109cd1d:	cmpq   $0x0,0x8(%rsp)
 109cd23:	je     109cd32 <my.diagram_membership::compute_sub_block_attachments+0x2f52>
 109cd25:	mov    0x290(%rsp),%rdi
 109cd2d:	call   103c740 <myl_core_drop_owned>
 109cd32:	mov    0xd8(%rsp),%rdi
 109cd3a:	call   103c740 <myl_core_drop_owned>
 109cd3f:	mov    0xb0(%rsp),%rdi
 109cd47:	call   103c740 <myl_core_drop_owned>
 109cd4c:	mov    0xe0(%rsp),%rdi
 109cd54:	call   103c740 <myl_core_drop_owned>
 109cd59:	mov    0xe8(%rsp),%rdi
 109cd61:	call   103c740 <myl_core_drop_owned>
 109cd66:	mov    0xf0(%rsp),%rdi
 109cd6e:	call   103c740 <myl_core_drop_owned>
 109cd73:	mov    0xb8(%rsp),%rdi
 109cd7b:	call   103c740 <myl_core_drop_owned>
 109cd80:	mov    0xa8(%rsp),%rdi
 109cd88:	call   103c740 <myl_core_drop_owned>
 109cd8d:	mov    0x90(%rsp),%rdi
 109cd95:	call   103c740 <myl_core_drop_owned>
 109cd9a:	mov    0x98(%rsp),%rdi
 109cda2:	call   103c740 <myl_core_drop_owned>
 109cda7:	mov    0xc8(%rsp),%rdi
 109cdaf:	call   103c740 <myl_core_drop_owned>
 109cdb4:	mov    0x30(%rsp),%rdi
 109cdb9:	call   103c740 <myl_core_drop_owned>
 109cdbe:	mov    0x60(%rsp),%rdi
 109cdc3:	call   103c740 <myl_core_drop_owned>
 109cdc8:	mov    0x38(%rsp),%rdi
 109cdcd:	call   103c740 <myl_core_drop_owned>
 109cdd2:	mov    %r13,%rdi
 109cdd5:	call   103c740 <myl_core_drop_owned>
 109cdda:	test   %rbp,%rbp
 109cddd:	je     109cde7 <my.diagram_membership::compute_sub_block_attachments+0x3007>
 109cddf:	mov    %rbp,%rdi
 109cde2:	call   103c740 <myl_core_drop_owned>
 109cde7:	test   %r15,%r15
 109cdea:	je     109ce06 <my.diagram_membership::compute_sub_block_attachments+0x3026>
 109cdec:	mov    0x288(%rsp),%rdi
 109cdf4:	call   103c740 <myl_core_drop_owned>
 109cdf9:	mov    0x270(%rsp),%rdi
 109ce01:	call   103c740 <myl_core_drop_owned>
 109ce06:	mov    %r12,%rdi
 109ce09:	call   103c740 <myl_core_drop_owned>
 109ce0e:	mov    %r14,0x1f0(%rsp)
 109ce16:	testb  $0x2,0x1(%r14)
 109ce1b:	mov    %r14,0x80(%rsp)
 109ce23:	jne    109ce30 <my.diagram_membership::compute_sub_block_attachments+0x3050>
 109ce25:	mov    %r14,%rdi
 109ce28:	call   1044400 <myl_core_str_hash>
 109ce2d:	jmp    109ce34 <my.diagram_membership::compute_sub_block_attachments+0x3054>
 109ce2f:	nop
 109ce30:	mov    0x18(%r14),%eax
 109ce34:	mov    %eax,%eax
 109ce36:	movabs $0x9e3779b97f4a7c15,%rcx
 109ce40:	imul   %rcx,%rax
 109ce44:	mov    %rax,%r14
 109ce47:	shr    $0x20,%r14
 109ce4b:	xor    %rax,%r14
 109ce4e:	mov    0x18(%rbx),%rcx
 109ce52:	mov    0x8(%rcx),%rax
 109ce56:	test   %rax,%rax
 109ce59:	je     109cf30 <my.diagram_membership::compute_sub_block_attachments+0x3150>
 109ce5f:	mov    (%rax),%ecx
 109ce61:	tzcnt  %ecx,%edx
 109ce65:	neg    %dl
 109ce67:	shrx   %rdx,%r14,%r12
 109ce6c:	vmovdqu 0x10(%rax,%r12,1),%xmm1
 109ce73:	mov    %r14d,%edx
 109ce76:	and    $0x7f,%dl
 109ce79:	vmovd  %edx,%xmm0
 109ce7d:	vpbroadcastb %xmm0,%xmm0
 109ce82:	vmovdqa %xmm1,0x10(%rsp)
 109ce88:	vpcmpeqb %xmm0,%xmm1,%xmm0
 109ce8c:	vpmovmskb %xmm0,%edx
 109ce90:	test   %edx,%edx
 109ce92:	je     109cefb <my.diagram_membership::compute_sub_block_attachments+0x311b>
 109ce98:	lea    -0x1(%rcx),%ebp
 109ce9b:	add    $0x1e,%ecx
 109ce9e:	and    $0xfffffff0,%ecx
 109cea1:	lea    (%rax,%rcx,1),%r13
 109cea5:	add    $0x10,%r13
 109cea9:	movzwl %dx,%ebx
 109ceac:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109cebb:	nopl   0x0(%rax,%rax,1)
 109cec0:	tzcnt  %ebx,%eax
 109cec4:	add    %r12d,%eax
 109cec7:	and    %ebp,%eax
 109cec9:	mov    0x0(%r13,%rax,4),%r15d
 109cece:	mov    %r15,%rax
 109ced1:	shl    $0x4,%rax
 109ced5:	mov    0x58(%rsp),%rcx
 109ceda:	mov    0x20(%rcx,%rax,1),%rdi
 109cedf:	mov    0x1f0(%rsp),%rsi
 109cee7:	call   1044580 <myl_core_str_eq>
 109ceec:	test   %al,%al
 109ceee:	jne    109e8e6 <my.diagram_membership::compute_sub_block_attachments+0x4b06>
 109cef4:	blsr   %ebx,%ebx
 109cef9:	jne    109cec0 <my.diagram_membership::compute_sub_block_attachments+0x30e0>
 109cefb:	vmovdqa 0x10(%rsp),%xmm0
 109cf01:	vpcmpeqb -0x98b39(%rip),%xmm0,%xmm0        # 10043d0 <__anon_2214+0x50>
 109cf09:	vpmovmskb %xmm0,%eax
 109cf0d:	test   %eax,%eax
 109cf0f:	je     109cf3b <my.diagram_membership::compute_sub_block_attachments+0x315b>
 109cf11:	mov    0x80(%rsp),%rdi
 109cf19:	call   103c740 <myl_core_drop_owned>
 109cf1e:	jmp    109cf69 <my.diagram_membership::compute_sub_block_attachments+0x3189>
 109cf20:	xor    %ebp,%ebp
 109cf22:	test   %r15,%r15
 109cf25:	jne    109caab <my.diagram_membership::compute_sub_block_attachments+0x2ccb>
 109cf2b:	jmp    109cae7 <my.diagram_membership::compute_sub_block_attachments+0x2d07>
 109cf30:	cmpq   $0x0,0x18(%rcx)
 109cf35:	je     109e942 <my.diagram_membership::compute_sub_block_attachments+0x4b62>
 109cf3b:	mov    0x58(%rsp),%rdi
 109cf40:	lea    0x1f0(%rsp),%rsi
 109cf48:	mov    %r14,%rdx
 109cf4b:	call   1042bc0 <myl_core_dict_find>
 109cf50:	mov    %rax,%r15
 109cf53:	mov    0x80(%rsp),%rdi
 109cf5b:	call   103c740 <myl_core_drop_owned>
 109cf60:	test   %r15,%r15
 109cf63:	jns    109e8f3 <my.diagram_membership::compute_sub_block_attachments+0x4b13>
 109cf69:	cmpq   $0x0,0xc0(%rsp)
 109cf72:	mov    0x58(%rsp),%r15
 109cf77:	mov    0xf8(%rsp),%rsi
 109cf7f:	je     109c1c8 <my.diagram_membership::compute_sub_block_attachments+0x23e8>
 109cf85:	imul   0xc0(%rsp),%rsi
 109cf8e:	mov    %rsi,0xb0(%rsp)
 109cf96:	seto   0xd8(%rsp)
 109cf9e:	mov    $0x1,%al
 109cfa0:	mov    %eax,0xb8(%rsp)
 109cfa7:	movq   $0x0,0x90(%rsp)
 109cfb3:	movq   $0x0,0x98(%rsp)
 109cfbf:	movq   $0x0,0xa8(%rsp)
 109cfcb:	xor    %r13d,%r13d
 109cfce:	jmp    109d059 <my.diagram_membership::compute_sub_block_attachments+0x3279>
 109cfd3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109cfe0:	mov    0x10(%rsp),%rdi
 109cfe5:	call   103c740 <myl_core_drop_owned>
 109cfea:	mov    0xc8(%rsp),%rdi
 109cff2:	call   103c740 <myl_core_drop_owned>
 109cff7:	mov    0x30(%rsp),%rdi
 109cffc:	call   103c740 <myl_core_drop_owned>
 109d001:	mov    0x60(%rsp),%rdi
 109d006:	call   103c740 <myl_core_drop_owned>
 109d00b:	mov    0x8(%rsp),%rdi
 109d010:	call   103c740 <myl_core_drop_owned>
 109d015:	mov    0x38(%rsp),%rdi
 109d01a:	call   103c740 <myl_core_drop_owned>
 109d01f:	mov    (%rsp),%rdi
 109d023:	call   103c740 <myl_core_drop_owned>
 109d028:	mov    %rbp,%rdi
 109d02b:	call   103c740 <myl_core_drop_owned>
 109d030:	mov    %r12,%rdi
 109d033:	call   103c740 <myl_core_drop_owned>
 109d038:	mov    %r15,%rdi
 109d03b:	call   103c740 <myl_core_drop_owned>
 109d040:	mov    %r14,%rdi
 109d043:	call   103c740 <myl_core_drop_owned>
 109d048:	inc    %r13
 109d04b:	cmp    0xc0(%rsp),%r13
 109d053:	je     109e8b0 <my.diagram_membership::compute_sub_block_attachments+0x4ad0>
 109d059:	imul   $0x70,%r13,%rax
 109d05d:	mov    0xa0(%rsp),%rcx
 109d065:	mov    (%rcx,%rax,1),%rdi
 109d069:	mov    0x8(%rcx,%rax,1),%r14
 109d06e:	mov    0x10(%rcx,%rax,1),%r15
 109d073:	mov    0x18(%rcx,%rax,1),%r12
 109d078:	mov    0x20(%rcx,%rax,1),%rbp
 109d07d:	mov    0x28(%rcx,%rax,1),%rbx
 109d082:	mov    0x30(%rcx,%rax,1),%rdx
 109d087:	mov    %rdx,(%rsp)
 109d08b:	mov    0x38(%rcx,%rax,1),%rdx
 109d090:	mov    %rdx,0x40(%rsp)
 109d095:	mov    0x40(%rcx,%rax,1),%rdx
 109d09a:	mov    %rdx,0x80(%rsp)
 109d0a2:	mov    0x48(%rcx,%rax,1),%rdx
 109d0a7:	mov    %rdx,0x70(%rsp)
 109d0ac:	mov    0x60(%rcx,%rax,1),%rax
 109d0b1:	mov    %rax,0x20(%rsp)
 109d0b6:	call   103cfc0 <myl_core_owned_octets_copy>
 109d0bb:	mov    %rax,0x10(%rsp)
 109d0c0:	mov    %r14,%rdi
 109d0c3:	call   103cfc0 <myl_core_owned_octets_copy>
 109d0c8:	mov    %rax,0xc8(%rsp)
 109d0d0:	mov    %r15,%rdi
 109d0d3:	call   103cfc0 <myl_core_owned_octets_copy>
 109d0d8:	mov    %rax,0x30(%rsp)
 109d0dd:	lea    0x5d28c(%rip),%rdi        # 10fa370 <core_durable_error.verbs+0xed70>
 109d0e4:	mov    %r12,%rsi
 109d0e7:	call   1063d00 <myl_core_values_copy_box>
 109d0ec:	mov    %rax,0x60(%rsp)
 109d0f1:	lea    0x5cde8(%rip),%rdi        # 10f9ee0 <core_durable_error.verbs+0xe8e0>
 109d0f8:	mov    %rbp,%rsi
 109d0fb:	call   1063d00 <myl_core_values_copy_box>
 109d100:	mov    %rax,0x8(%rsp)
 109d105:	lea    0x5d2e4(%rip),%rdi        # 10fa3f0 <core_durable_error.verbs+0xedf0>
 109d10c:	mov    %rbx,%rsi
 109d10f:	call   1063d00 <myl_core_values_copy_box>
 109d114:	mov    %rax,0x38(%rsp)
 109d119:	lea    0x5d4c0(%rip),%rdi        # 10fa5e0 <core_durable_error.verbs+0xefe0>
 109d120:	mov    (%rsp),%rsi
 109d124:	call   1063d00 <myl_core_values_copy_box>
 109d129:	mov    %rax,(%rsp)
 109d12d:	lea    0x5bb1c(%rip),%rbx        # 10f8c50 <core_durable_error.verbs+0xd650>
 109d134:	mov    %rbx,%rdi
 109d137:	mov    0x40(%rsp),%rsi
 109d13c:	call   1063d00 <myl_core_values_copy_box>
 109d141:	mov    %rax,%rbp
 109d144:	lea    0x5d575(%rip),%rdi        # 10fa6c0 <core_durable_error.verbs+0xf0c0>
 109d14b:	mov    0x80(%rsp),%rsi
 109d153:	call   1063d00 <myl_core_values_copy_box>
 109d158:	mov    %rax,%r12
 109d15b:	lea    0x5d58e(%rip),%rdi        # 10fa6f0 <core_durable_error.verbs+0xf0f0>
 109d162:	mov    0x70(%rsp),%rsi
 109d167:	call   1063d00 <myl_core_values_copy_box>
 109d16c:	mov    %rax,%r15
 109d16f:	mov    %rbx,%rdi
 109d172:	mov    0x20(%rsp),%rsi
 109d177:	call   1063d00 <myl_core_values_copy_box>
 109d17c:	cmpb   $0x0,0xd8(%rsp)
 109d184:	jne    109eab8 <my.diagram_membership::compute_sub_block_attachments+0x4cd8>
 109d18a:	mov    %rax,%r14
 109d18d:	mov    0xb0(%rsp),%rsi
 109d195:	add    %r13,%rsi
 109d198:	mov    0x1e8(%rsp),%rax
 109d1a0:	jo     109ead4 <my.diagram_membership::compute_sub_block_attachments+0x4cf4>
 109d1a6:	mov    0x8(%rax),%rdx
 109d1aa:	cmp    %rdx,%rsi
 109d1ad:	jae    109eaeb <my.diagram_membership::compute_sub_block_attachments+0x4d0b>
 109d1b3:	mov    0x20(%rax,%rsi,8),%rax
 109d1b8:	test   %rax,%rax
 109d1bb:	jle    109cfe0 <my.diagram_membership::compute_sub_block_attachments+0x3200>
 109d1c1:	mov    %rax,0xe0(%rsp)
 109d1c9:	mov    %r15,0x40(%rsp)
 109d1ce:	mov    %r14,0x80(%rsp)
 109d1d6:	mov    %r13,0x70(%rsp)
 109d1db:	mov    %fs:0xfffffffffffffef0,%r15
 109d1e4:	test   %r15,%r15
 109d1e7:	je     109df2d <my.diagram_membership::compute_sub_block_attachments+0x414d>
 109d1ed:	mov    (%r15),%rax
 109d1f0:	mov    %rax,%fs:0xfffffffffffffef0
 109d1f9:	movl   $0x6000000,(%r15)
 109d200:	movq   $0x0,0x8(%r15)
 109d208:	movq   $0xa,0x10(%r15)
 109d210:	movq   $0x0,0x18(%r15)
 109d218:	mov    0x10(%rsp),%r14
 109d21d:	lea    -0x712dc(%rip),%rax        # 102bf48 <core_number_pairs+0x249f8>
 109d224:	mov    %rax,0x18(%r15)
 109d228:	mov    %fs:0xfffffffffffffed8,%rax
 109d231:	test   %rax,%rax
 109d234:	lea    -0x720e3(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109d23b:	je     109df44 <my.diagram_membership::compute_sub_block_attachments+0x4164>
 109d241:	mov    (%rax),%rcx
 109d244:	mov    %rcx,%fs:0xfffffffffffffed8
 109d24d:	movl   $0x3000000,(%rax)
 109d253:	movq   $0x0,0x8(%rax)
 109d25b:	movq   $0x8,0x10(%rax)
 109d263:	mov    %rsi,0x18(%rax)
 109d267:	mov    $0x8,%edx
 109d26c:	xor    %ecx,%ecx
 109d26e:	lea    -0x7e015(%rip),%rdi        # 101f260 <core_number_pairs+0x17d10>
 109d275:	mov    %rdi,0x20(%rax,%rcx,8)
 109d27a:	inc    %rcx
 109d27d:	mov    %rcx,0x8(%rax)
 109d281:	cmp    %rdx,%rcx
 109d284:	jae    109df88 <my.diagram_membership::compute_sub_block_attachments+0x41a8>
 109d28a:	lea    -0x7dff1(%rip),%rdi        # 101f2a0 <core_number_pairs+0x17d50>
 109d291:	mov    %rdi,0x20(%rax,%rcx,8)
 109d296:	inc    %rcx
 109d299:	mov    %rcx,0x8(%rax)
 109d29d:	cmp    %rdx,%rcx
 109d2a0:	jae    109dfa9 <my.diagram_membership::compute_sub_block_attachments+0x41c9>
 109d2a6:	lea    -0x7dfcd(%rip),%rdi        # 101f2e0 <core_number_pairs+0x17d90>
 109d2ad:	mov    %rdi,0x20(%rax,%rcx,8)
 109d2b2:	inc    %rcx
 109d2b5:	mov    %rcx,0x8(%rax)
 109d2b9:	cmp    %rdx,%rcx
 109d2bc:	jae    109dfca <my.diagram_membership::compute_sub_block_attachments+0x41ea>
 109d2c2:	lea    -0x7dfa9(%rip),%rdi        # 101f320 <core_number_pairs+0x17dd0>
 109d2c9:	mov    %rdi,0x20(%rax,%rcx,8)
 109d2ce:	inc    %rcx
 109d2d1:	mov    %rcx,0x8(%rax)
 109d2d5:	cmp    %rdx,%rcx
 109d2d8:	jae    109dfeb <my.diagram_membership::compute_sub_block_attachments+0x420b>
 109d2de:	lea    -0x7df85(%rip),%rdi        # 101f360 <core_number_pairs+0x17e10>
 109d2e5:	mov    %rdi,0x20(%rax,%rcx,8)
 109d2ea:	inc    %rcx
 109d2ed:	mov    %rcx,0x8(%rax)
 109d2f1:	cmp    %rdx,%rcx
 109d2f4:	jae    109e00c <my.diagram_membership::compute_sub_block_attachments+0x422c>
 109d2fa:	lea    -0x7df61(%rip),%rdi        # 101f3a0 <core_number_pairs+0x17e50>
 109d301:	mov    %rdi,0x20(%rax,%rcx,8)
 109d306:	inc    %rcx
 109d309:	mov    %rcx,0x8(%rax)
 109d30d:	cmp    %rdx,%rcx
 109d310:	jae    109e02d <my.diagram_membership::compute_sub_block_attachments+0x424d>
 109d316:	lea    -0x7df3d(%rip),%rdi        # 101f3e0 <core_number_pairs+0x17e90>
 109d31d:	mov    %rdi,0x20(%rax,%rcx,8)
 109d322:	inc    %rcx
 109d325:	mov    %rcx,0x8(%rax)
 109d329:	cmp    %rdx,%rcx
 109d32c:	jae    109e04e <my.diagram_membership::compute_sub_block_attachments+0x426e>
 109d332:	lea    -0x7df19(%rip),%rdx        # 101f420 <core_number_pairs+0x17ed0>
 109d339:	mov    %rdx,0x20(%rax,%rcx,8)
 109d33e:	inc    %rcx
 109d341:	mov    %rcx,0x8(%rax)
 109d345:	mov    0x8(%r15),%rcx
 109d349:	cmp    0x10(%r15),%rcx
 109d34d:	jae    109e06b <my.diagram_membership::compute_sub_block_attachments+0x428b>
 109d353:	mov    %rcx,%rdx
 109d356:	shl    $0x4,%rdx
 109d35a:	movq   $0x0,0x20(%r15,%rdx,1)
 109d363:	mov    %rax,0x28(%r15,%rdx,1)
 109d368:	inc    %rcx
 109d36b:	mov    %rcx,0x8(%r15)
 109d36f:	mov    %fs:0xfffffffffffffed8,%rax
 109d378:	test   %rax,%rax
 109d37b:	je     109e091 <my.diagram_membership::compute_sub_block_attachments+0x42b1>
 109d381:	mov    (%rax),%rcx
 109d384:	mov    %rcx,%fs:0xfffffffffffffed8
 109d38d:	movl   $0x3000000,(%rax)
 109d393:	movq   $0x0,0x8(%rax)
 109d39b:	movq   $0x8,0x10(%rax)
 109d3a3:	mov    %rsi,0x18(%rax)
 109d3a7:	mov    $0x8,%edx
 109d3ac:	xor    %ecx,%ecx
 109d3ae:	lea    -0x7df55(%rip),%rdi        # 101f460 <core_number_pairs+0x17f10>
 109d3b5:	mov    %rdi,0x20(%rax,%rcx,8)
 109d3ba:	inc    %rcx
 109d3bd:	mov    %rcx,0x8(%rax)
 109d3c1:	cmp    %rdx,%rcx
 109d3c4:	jae    109e0d5 <my.diagram_membership::compute_sub_block_attachments+0x42f5>
 109d3ca:	lea    -0x7df31(%rip),%rdi        # 101f4a0 <core_number_pairs+0x17f50>
 109d3d1:	mov    %rdi,0x20(%rax,%rcx,8)
 109d3d6:	inc    %rcx
 109d3d9:	mov    %rcx,0x8(%rax)
 109d3dd:	cmp    %rdx,%rcx
 109d3e0:	jae    109e0f6 <my.diagram_membership::compute_sub_block_attachments+0x4316>
 109d3e6:	lea    -0x7df0d(%rip),%rdi        # 101f4e0 <core_number_pairs+0x17f90>
 109d3ed:	mov    %rdi,0x20(%rax,%rcx,8)
 109d3f2:	inc    %rcx
 109d3f5:	mov    %rcx,0x8(%rax)
 109d3f9:	cmp    %rdx,%rcx
 109d3fc:	jae    109e117 <my.diagram_membership::compute_sub_block_attachments+0x4337>
 109d402:	lea    -0x7dee9(%rip),%rdi        # 101f520 <core_number_pairs+0x17fd0>
 109d409:	mov    %rdi,0x20(%rax,%rcx,8)
 109d40e:	inc    %rcx
 109d411:	mov    %rcx,0x8(%rax)
 109d415:	cmp    %rdx,%rcx
 109d418:	jae    109e138 <my.diagram_membership::compute_sub_block_attachments+0x4358>
 109d41e:	lea    -0x7dec5(%rip),%rdi        # 101f560 <core_number_pairs+0x18010>
 109d425:	mov    %rdi,0x20(%rax,%rcx,8)
 109d42a:	inc    %rcx
 109d42d:	mov    %rcx,0x8(%rax)
 109d431:	cmp    %rdx,%rcx
 109d434:	jae    109e159 <my.diagram_membership::compute_sub_block_attachments+0x4379>
 109d43a:	lea    -0x7dea1(%rip),%rdi        # 101f5a0 <core_number_pairs+0x18050>
 109d441:	mov    %rdi,0x20(%rax,%rcx,8)
 109d446:	inc    %rcx
 109d449:	mov    %rcx,0x8(%rax)
 109d44d:	cmp    %rdx,%rcx
 109d450:	jae    109e17a <my.diagram_membership::compute_sub_block_attachments+0x439a>
 109d456:	lea    -0x7de7d(%rip),%rdx        # 101f5e0 <core_number_pairs+0x18090>
 109d45d:	mov    %rdx,0x20(%rax,%rcx,8)
 109d462:	inc    %rcx
 109d465:	mov    %rcx,0x8(%rax)
 109d469:	mov    0x8(%r15),%rcx
 109d46d:	cmp    0x10(%r15),%rcx
 109d471:	jae    109e197 <my.diagram_membership::compute_sub_block_attachments+0x43b7>
 109d477:	mov    %rcx,%rdx
 109d47a:	shl    $0x4,%rdx
 109d47e:	movq   $0x1,0x20(%r15,%rdx,1)
 109d487:	mov    %rax,0x28(%r15,%rdx,1)
 109d48c:	inc    %rcx
 109d48f:	mov    %rcx,0x8(%r15)
 109d493:	mov    %fs:0xfffffffffffffed8,%rax
 109d49c:	test   %rax,%rax
 109d49f:	je     109e1bd <my.diagram_membership::compute_sub_block_attachments+0x43dd>
 109d4a5:	mov    (%rax),%rcx
 109d4a8:	mov    %rcx,%fs:0xfffffffffffffed8
 109d4b1:	movl   $0x3000000,(%rax)
 109d4b7:	movq   $0x0,0x8(%rax)
 109d4bf:	movq   $0x8,0x10(%rax)
 109d4c7:	mov    %rsi,0x18(%rax)
 109d4cb:	mov    $0x8,%edx
 109d4d0:	xor    %ecx,%ecx
 109d4d2:	lea    -0x7deb9(%rip),%rdi        # 101f620 <core_number_pairs+0x180d0>
 109d4d9:	mov    %rdi,0x20(%rax,%rcx,8)
 109d4de:	inc    %rcx
 109d4e1:	mov    %rcx,0x8(%rax)
 109d4e5:	cmp    %rdx,%rcx
 109d4e8:	jae    109e201 <my.diagram_membership::compute_sub_block_attachments+0x4421>
 109d4ee:	lea    -0x7de95(%rip),%rdi        # 101f660 <core_number_pairs+0x18110>
 109d4f5:	mov    %rdi,0x20(%rax,%rcx,8)
 109d4fa:	inc    %rcx
 109d4fd:	mov    %rcx,0x8(%rax)
 109d501:	cmp    %rdx,%rcx
 109d504:	jae    109e222 <my.diagram_membership::compute_sub_block_attachments+0x4442>
 109d50a:	lea    -0x7de71(%rip),%rdi        # 101f6a0 <core_number_pairs+0x18150>
 109d511:	mov    %rdi,0x20(%rax,%rcx,8)
 109d516:	inc    %rcx
 109d519:	mov    %rcx,0x8(%rax)
 109d51d:	cmp    %rdx,%rcx
 109d520:	jae    109e243 <my.diagram_membership::compute_sub_block_attachments+0x4463>
 109d526:	lea    -0x7de4d(%rip),%rdi        # 101f6e0 <core_number_pairs+0x18190>
 109d52d:	mov    %rdi,0x20(%rax,%rcx,8)
 109d532:	inc    %rcx
 109d535:	mov    %rcx,0x8(%rax)
 109d539:	cmp    %rdx,%rcx
 109d53c:	jae    109e264 <my.diagram_membership::compute_sub_block_attachments+0x4484>
 109d542:	lea    -0x7de29(%rip),%rdx        # 101f720 <core_number_pairs+0x181d0>
 109d549:	mov    %rdx,0x20(%rax,%rcx,8)
 109d54e:	inc    %rcx
 109d551:	mov    %rcx,0x8(%rax)
 109d555:	mov    0x8(%r15),%rcx
 109d559:	cmp    0x10(%r15),%rcx
 109d55d:	jae    109e281 <my.diagram_membership::compute_sub_block_attachments+0x44a1>
 109d563:	mov    %rcx,%rdx
 109d566:	shl    $0x4,%rdx
 109d56a:	movq   $0x2,0x20(%r15,%rdx,1)
 109d573:	mov    %rax,0x28(%r15,%rdx,1)
 109d578:	inc    %rcx
 109d57b:	mov    %rcx,0x8(%r15)
 109d57f:	mov    %fs:0xfffffffffffffed8,%rax
 109d588:	test   %rax,%rax
 109d58b:	je     109e2a7 <my.diagram_membership::compute_sub_block_attachments+0x44c7>
 109d591:	mov    (%rax),%rcx
 109d594:	mov    %rcx,%fs:0xfffffffffffffed8
 109d59d:	movl   $0x3000000,(%rax)
 109d5a3:	movq   $0x0,0x8(%rax)
 109d5ab:	movq   $0x8,0x10(%rax)
 109d5b3:	mov    %rsi,0x18(%rax)
 109d5b7:	mov    $0x8,%edx
 109d5bc:	xor    %ecx,%ecx
 109d5be:	lea    -0x7de65(%rip),%rdi        # 101f760 <core_number_pairs+0x18210>
 109d5c5:	mov    %rdi,0x20(%rax,%rcx,8)
 109d5ca:	inc    %rcx
 109d5cd:	mov    %rcx,0x8(%rax)
 109d5d1:	cmp    %rdx,%rcx
 109d5d4:	jae    109e2eb <my.diagram_membership::compute_sub_block_attachments+0x450b>
 109d5da:	lea    -0x7de41(%rip),%rdi        # 101f7a0 <core_number_pairs+0x18250>
 109d5e1:	mov    %rdi,0x20(%rax,%rcx,8)
 109d5e6:	inc    %rcx
 109d5e9:	mov    %rcx,0x8(%rax)
 109d5ed:	cmp    %rdx,%rcx
 109d5f0:	jae    109e30c <my.diagram_membership::compute_sub_block_attachments+0x452c>
 109d5f6:	lea    -0x7de1d(%rip),%rdi        # 101f7e0 <core_number_pairs+0x18290>
 109d5fd:	mov    %rdi,0x20(%rax,%rcx,8)
 109d602:	inc    %rcx
 109d605:	mov    %rcx,0x8(%rax)
 109d609:	cmp    %rdx,%rcx
 109d60c:	jae    109e32d <my.diagram_membership::compute_sub_block_attachments+0x454d>
 109d612:	lea    -0x7ddf9(%rip),%rdi        # 101f820 <core_number_pairs+0x182d0>
 109d619:	mov    %rdi,0x20(%rax,%rcx,8)
 109d61e:	inc    %rcx
 109d621:	mov    %rcx,0x8(%rax)
 109d625:	cmp    %rdx,%rcx
 109d628:	jae    109e34e <my.diagram_membership::compute_sub_block_attachments+0x456e>
 109d62e:	lea    -0x7ddd5(%rip),%rdi        # 101f860 <core_number_pairs+0x18310>
 109d635:	mov    %rdi,0x20(%rax,%rcx,8)
 109d63a:	inc    %rcx
 109d63d:	mov    %rcx,0x8(%rax)
 109d641:	cmp    %rdx,%rcx
 109d644:	jae    109e36f <my.diagram_membership::compute_sub_block_attachments+0x458f>
 109d64a:	lea    -0x7ddb1(%rip),%rdx        # 101f8a0 <core_number_pairs+0x18350>
 109d651:	mov    %rdx,0x20(%rax,%rcx,8)
 109d656:	inc    %rcx
 109d659:	mov    %rcx,0x8(%rax)
 109d65d:	mov    0x8(%r15),%rcx
 109d661:	cmp    0x10(%r15),%rcx
 109d665:	jae    109e38c <my.diagram_membership::compute_sub_block_attachments+0x45ac>
 109d66b:	mov    %rcx,%rdx
 109d66e:	shl    $0x4,%rdx
 109d672:	movq   $0x5,0x20(%r15,%rdx,1)
 109d67b:	mov    %rax,0x28(%r15,%rdx,1)
 109d680:	inc    %rcx
 109d683:	mov    %rcx,0x8(%r15)
 109d687:	mov    %fs:0xfffffffffffffed8,%rax
 109d690:	test   %rax,%rax
 109d693:	je     109e3b2 <my.diagram_membership::compute_sub_block_attachments+0x45d2>
 109d699:	mov    (%rax),%rcx
 109d69c:	mov    %rcx,%fs:0xfffffffffffffed8
 109d6a5:	movl   $0x3000000,(%rax)
 109d6ab:	movq   $0x0,0x8(%rax)
 109d6b3:	movq   $0x8,0x10(%rax)
 109d6bb:	mov    %rsi,0x18(%rax)
 109d6bf:	mov    $0x8,%edx
 109d6c4:	xor    %ecx,%ecx
 109d6c6:	lea    -0x7dded(%rip),%rdi        # 101f8e0 <core_number_pairs+0x18390>
 109d6cd:	mov    %rdi,0x20(%rax,%rcx,8)
 109d6d2:	inc    %rcx
 109d6d5:	mov    %rcx,0x8(%rax)
 109d6d9:	cmp    %rdx,%rcx
 109d6dc:	jae    109e3f6 <my.diagram_membership::compute_sub_block_attachments+0x4616>
 109d6e2:	lea    -0x7ddc9(%rip),%rdi        # 101f920 <core_number_pairs+0x183d0>
 109d6e9:	mov    %rdi,0x20(%rax,%rcx,8)
 109d6ee:	inc    %rcx
 109d6f1:	mov    %rcx,0x8(%rax)
 109d6f5:	cmp    %rdx,%rcx
 109d6f8:	jae    109e417 <my.diagram_membership::compute_sub_block_attachments+0x4637>
 109d6fe:	lea    -0x7dda5(%rip),%rdi        # 101f960 <core_number_pairs+0x18410>
 109d705:	mov    %rdi,0x20(%rax,%rcx,8)
 109d70a:	inc    %rcx
 109d70d:	mov    %rcx,0x8(%rax)
 109d711:	cmp    %rdx,%rcx
 109d714:	jae    109e438 <my.diagram_membership::compute_sub_block_attachments+0x4658>
 109d71a:	lea    -0x7dd81(%rip),%rdi        # 101f9a0 <core_number_pairs+0x18450>
 109d721:	mov    %rdi,0x20(%rax,%rcx,8)
 109d726:	inc    %rcx
 109d729:	mov    %rcx,0x8(%rax)
 109d72d:	cmp    %rdx,%rcx
 109d730:	jae    109e459 <my.diagram_membership::compute_sub_block_attachments+0x4679>
 109d736:	lea    -0x7dd5d(%rip),%rdi        # 101f9e0 <core_number_pairs+0x18490>
 109d73d:	mov    %rdi,0x20(%rax,%rcx,8)
 109d742:	inc    %rcx
 109d745:	mov    %rcx,0x8(%rax)
 109d749:	cmp    %rdx,%rcx
 109d74c:	jae    109e47a <my.diagram_membership::compute_sub_block_attachments+0x469a>
 109d752:	lea    -0x7dd39(%rip),%rdx        # 101fa20 <core_number_pairs+0x184d0>
 109d759:	mov    %rdx,0x20(%rax,%rcx,8)
 109d75e:	inc    %rcx
 109d761:	mov    %rcx,0x8(%rax)
 109d765:	mov    0x8(%r15),%rcx
 109d769:	cmp    0x10(%r15),%rcx
 109d76d:	jae    109e497 <my.diagram_membership::compute_sub_block_attachments+0x46b7>
 109d773:	mov    %rcx,%rdx
 109d776:	shl    $0x4,%rdx
 109d77a:	movq   $0x6,0x20(%r15,%rdx,1)
 109d783:	mov    %rax,0x28(%r15,%rdx,1)
 109d788:	inc    %rcx
 109d78b:	mov    %rcx,0x8(%r15)
 109d78f:	mov    %fs:0xfffffffffffffed8,%rax
 109d798:	test   %rax,%rax
 109d79b:	je     109e4bd <my.diagram_membership::compute_sub_block_attachments+0x46dd>
 109d7a1:	mov    (%rax),%rcx
 109d7a4:	mov    %rcx,%fs:0xfffffffffffffed8
 109d7ad:	movl   $0x3000000,(%rax)
 109d7b3:	movq   $0x0,0x8(%rax)
 109d7bb:	movq   $0x8,0x10(%rax)
 109d7c3:	mov    %rsi,0x18(%rax)
 109d7c7:	mov    $0x8,%edx
 109d7cc:	xor    %ecx,%ecx
 109d7ce:	lea    -0x7dd75(%rip),%rdi        # 101fa60 <core_number_pairs+0x18510>
 109d7d5:	mov    %rdi,0x20(%rax,%rcx,8)
 109d7da:	inc    %rcx
 109d7dd:	mov    %rcx,0x8(%rax)
 109d7e1:	cmp    %rdx,%rcx
 109d7e4:	jae    109e501 <my.diagram_membership::compute_sub_block_attachments+0x4721>
 109d7ea:	lea    -0x7dd51(%rip),%rdi        # 101faa0 <core_number_pairs+0x18550>
 109d7f1:	mov    %rdi,0x20(%rax,%rcx,8)
 109d7f6:	inc    %rcx
 109d7f9:	mov    %rcx,0x8(%rax)
 109d7fd:	cmp    %rdx,%rcx
 109d800:	jae    109e522 <my.diagram_membership::compute_sub_block_attachments+0x4742>
 109d806:	lea    -0x7dd2d(%rip),%rdi        # 101fae0 <core_number_pairs+0x18590>
 109d80d:	mov    %rdi,0x20(%rax,%rcx,8)
 109d812:	inc    %rcx
 109d815:	mov    %rcx,0x8(%rax)
 109d819:	cmp    %rdx,%rcx
 109d81c:	jae    109e543 <my.diagram_membership::compute_sub_block_attachments+0x4763>
 109d822:	lea    -0x7dd09(%rip),%rdi        # 101fb20 <core_number_pairs+0x185d0>
 109d829:	mov    %rdi,0x20(%rax,%rcx,8)
 109d82e:	inc    %rcx
 109d831:	mov    %rcx,0x8(%rax)
 109d835:	cmp    %rdx,%rcx
 109d838:	jae    109e564 <my.diagram_membership::compute_sub_block_attachments+0x4784>
 109d83e:	lea    -0x7dce5(%rip),%rdi        # 101fb60 <core_number_pairs+0x18610>
 109d845:	mov    %rdi,0x20(%rax,%rcx,8)
 109d84a:	inc    %rcx
 109d84d:	mov    %rcx,0x8(%rax)
 109d851:	cmp    %rdx,%rcx
 109d854:	jae    109e585 <my.diagram_membership::compute_sub_block_attachments+0x47a5>
 109d85a:	lea    -0x7dcc1(%rip),%rdx        # 101fba0 <core_number_pairs+0x18650>
 109d861:	mov    %rdx,0x20(%rax,%rcx,8)
 109d866:	inc    %rcx
 109d869:	mov    %rcx,0x8(%rax)
 109d86d:	mov    0x8(%r15),%rcx
 109d871:	cmp    0x10(%r15),%rcx
 109d875:	jae    109e5a2 <my.diagram_membership::compute_sub_block_attachments+0x47c2>
 109d87b:	mov    %rcx,%rdx
 109d87e:	shl    $0x4,%rdx
 109d882:	movq   $0x7,0x20(%r15,%rdx,1)
 109d88b:	mov    %rax,0x28(%r15,%rdx,1)
 109d890:	inc    %rcx
 109d893:	mov    %rcx,0x8(%r15)
 109d897:	mov    %fs:0xfffffffffffffed8,%rax
 109d8a0:	test   %rax,%rax
 109d8a3:	je     109e5c8 <my.diagram_membership::compute_sub_block_attachments+0x47e8>
 109d8a9:	mov    (%rax),%rcx
 109d8ac:	mov    %rcx,%fs:0xfffffffffffffed8
 109d8b5:	movl   $0x3000000,(%rax)
 109d8bb:	movq   $0x0,0x8(%rax)
 109d8c3:	movq   $0x8,0x10(%rax)
 109d8cb:	mov    %rsi,0x18(%rax)
 109d8cf:	mov    $0x8,%edx
 109d8d4:	xor    %ecx,%ecx
 109d8d6:	lea    -0x7dcfd(%rip),%rdi        # 101fbe0 <core_number_pairs+0x18690>
 109d8dd:	mov    %rdi,0x20(%rax,%rcx,8)
 109d8e2:	inc    %rcx
 109d8e5:	mov    %rcx,0x8(%rax)
 109d8e9:	cmp    %rdx,%rcx
 109d8ec:	jae    109e60c <my.diagram_membership::compute_sub_block_attachments+0x482c>
 109d8f2:	lea    -0x7dcd9(%rip),%rdi        # 101fc20 <core_number_pairs+0x186d0>
 109d8f9:	mov    %rdi,0x20(%rax,%rcx,8)
 109d8fe:	inc    %rcx
 109d901:	mov    %rcx,0x8(%rax)
 109d905:	cmp    %rdx,%rcx
 109d908:	jae    109e62d <my.diagram_membership::compute_sub_block_attachments+0x484d>
 109d90e:	lea    -0x7dcb5(%rip),%rdi        # 101fc60 <core_number_pairs+0x18710>
 109d915:	mov    %rdi,0x20(%rax,%rcx,8)
 109d91a:	inc    %rcx
 109d91d:	mov    %rcx,0x8(%rax)
 109d921:	cmp    %rdx,%rcx
 109d924:	jae    109e64e <my.diagram_membership::compute_sub_block_attachments+0x486e>
 109d92a:	lea    -0x7dc91(%rip),%rdi        # 101fca0 <core_number_pairs+0x18750>
 109d931:	mov    %rdi,0x20(%rax,%rcx,8)
 109d936:	inc    %rcx
 109d939:	mov    %rcx,0x8(%rax)
 109d93d:	cmp    %rdx,%rcx
 109d940:	jae    109e66f <my.diagram_membership::compute_sub_block_attachments+0x488f>
 109d946:	lea    -0x7dc6d(%rip),%rdx        # 101fce0 <core_number_pairs+0x18790>
 109d94d:	mov    %rdx,0x20(%rax,%rcx,8)
 109d952:	inc    %rcx
 109d955:	mov    %rcx,0x8(%rax)
 109d959:	mov    0x8(%r15),%rcx
 109d95d:	cmp    0x10(%r15),%rcx
 109d961:	jae    109e68c <my.diagram_membership::compute_sub_block_attachments+0x48ac>
 109d967:	mov    %rcx,%rdx
 109d96a:	shl    $0x4,%rdx
 109d96e:	movq   $0x8,0x20(%r15,%rdx,1)
 109d977:	mov    %rax,0x28(%r15,%rdx,1)
 109d97c:	inc    %rcx
 109d97f:	mov    %rcx,0x8(%r15)
 109d983:	mov    %fs:0xfffffffffffffed0,%rax
 109d98c:	test   %rax,%rax
 109d98f:	je     109e6b2 <my.diagram_membership::compute_sub_block_attachments+0x48d2>
 109d995:	mov    (%rax),%rcx
 109d998:	mov    %rcx,%fs:0xfffffffffffffed0
 109d9a1:	movl   $0x2000000,(%rax)
 109d9a7:	movq   $0x0,0x8(%rax)
 109d9af:	movq   $0x4,0x10(%rax)
 109d9b7:	mov    %rsi,0x18(%rax)
 109d9bb:	mov    $0x4,%edx
 109d9c0:	xor    %ecx,%ecx
 109d9c2:	lea    -0x7dca9(%rip),%rdi        # 101fd20 <core_number_pairs+0x187d0>
 109d9c9:	mov    %rdi,0x20(%rax,%rcx,8)
 109d9ce:	inc    %rcx
 109d9d1:	mov    %rcx,0x8(%rax)
 109d9d5:	cmp    %rdx,%rcx
 109d9d8:	jae    109e6f6 <my.diagram_membership::compute_sub_block_attachments+0x4916>
 109d9de:	lea    -0x7dc85(%rip),%rdi        # 101fd60 <core_number_pairs+0x18810>
 109d9e5:	mov    %rdi,0x20(%rax,%rcx,8)
 109d9ea:	inc    %rcx
 109d9ed:	mov    %rcx,0x8(%rax)
 109d9f1:	cmp    %rdx,%rcx
 109d9f4:	jae    109e717 <my.diagram_membership::compute_sub_block_attachments+0x4937>
 109d9fa:	lea    -0x7dc61(%rip),%rdi        # 101fda0 <core_number_pairs+0x18850>
 109da01:	mov    %rdi,0x20(%rax,%rcx,8)
 109da06:	inc    %rcx
 109da09:	mov    %rcx,0x8(%rax)
 109da0d:	cmp    %rdx,%rcx
 109da10:	jae    109e738 <my.diagram_membership::compute_sub_block_attachments+0x4958>
 109da16:	lea    -0x7dc3d(%rip),%rdx        # 101fde0 <core_number_pairs+0x18890>
 109da1d:	mov    %rdx,0x20(%rax,%rcx,8)
 109da22:	inc    %rcx
 109da25:	mov    %rcx,0x8(%rax)
 109da29:	mov    0x8(%r15),%rcx
 109da2d:	cmp    0x10(%r15),%rcx
 109da31:	mov    %r12,0xf0(%rsp)
 109da39:	jae    109e755 <my.diagram_membership::compute_sub_block_attachments+0x4975>
 109da3f:	mov    %rcx,%rdx
 109da42:	shl    $0x4,%rdx
 109da46:	movq   $0x9,0x20(%r15,%rdx,1)
 109da4f:	mov    %rax,0x28(%r15,%rdx,1)
 109da54:	inc    %rcx
 109da57:	mov    %rcx,0x8(%r15)
 109da5b:	mov    %fs:0xfffffffffffffed8,%r12
 109da64:	test   %r12,%r12
 109da67:	je     109e77b <my.diagram_membership::compute_sub_block_attachments+0x499b>
 109da6d:	mov    (%r12),%rax
 109da71:	mov    %rax,%fs:0xfffffffffffffed8
 109da7a:	movl   $0x3000000,(%r12)
 109da82:	movq   $0x0,0x8(%r12)
 109da8b:	movq   $0x8,0x10(%r12)
 109da94:	mov    %rsi,0x18(%r12)
 109da99:	mov    $0x8,%ecx
 109da9e:	xor    %eax,%eax
 109daa0:	lea    -0x7dc87(%rip),%rdx        # 101fe20 <core_number_pairs+0x188d0>
 109daa7:	mov    %rdx,0x20(%r12,%rax,8)
 109daac:	inc    %rax
 109daaf:	mov    %rax,0x8(%r12)
 109dab4:	cmp    %rcx,%rax
 109dab7:	jae    109e7c5 <my.diagram_membership::compute_sub_block_attachments+0x49e5>
 109dabd:	lea    -0x7dc64(%rip),%rdx        # 101fe60 <core_number_pairs+0x18910>
 109dac4:	mov    %rdx,0x20(%r12,%rax,8)
 109dac9:	inc    %rax
 109dacc:	mov    %rax,0x8(%r12)
 109dad1:	cmp    %rcx,%rax
 109dad4:	jae    109e7e3 <my.diagram_membership::compute_sub_block_attachments+0x4a03>
 109dada:	lea    -0x7dc41(%rip),%rdx        # 101fea0 <core_number_pairs+0x18950>
 109dae1:	mov    %rdx,0x20(%r12,%rax,8)
 109dae6:	inc    %rax
 109dae9:	mov    %rax,0x8(%r12)
 109daee:	cmp    %rcx,%rax
 109daf1:	jae    109e801 <my.diagram_membership::compute_sub_block_attachments+0x4a21>
 109daf7:	lea    -0x7dc1e(%rip),%rdx        # 101fee0 <core_number_pairs+0x18990>
 109dafe:	mov    %rdx,0x20(%r12,%rax,8)
 109db03:	inc    %rax
 109db06:	mov    %rax,0x8(%r12)
 109db0b:	cmp    %rcx,%rax
 109db0e:	jae    109e81f <my.diagram_membership::compute_sub_block_attachments+0x4a3f>
 109db14:	lea    -0x7dbfb(%rip),%rdx        # 101ff20 <core_number_pairs+0x189d0>
 109db1b:	mov    %rdx,0x20(%r12,%rax,8)
 109db20:	inc    %rax
 109db23:	mov    %rax,0x8(%r12)
 109db28:	cmp    %rcx,%rax
 109db2b:	jae    109e83d <my.diagram_membership::compute_sub_block_attachments+0x4a5d>
 109db31:	lea    -0x7dbd8(%rip),%rdx        # 101ff60 <core_number_pairs+0x18a10>
 109db38:	mov    %rdx,0x20(%r12,%rax,8)
 109db3d:	inc    %rax
 109db40:	mov    %rax,0x8(%r12)
 109db45:	cmp    %rcx,%rax
 109db48:	jae    109e85b <my.diagram_membership::compute_sub_block_attachments+0x4a7b>
 109db4e:	lea    -0x7dbb5(%rip),%rdx        # 101ffa0 <core_number_pairs+0x18a50>
 109db55:	mov    %rdx,0x20(%r12,%rax,8)
 109db5a:	inc    %rax
 109db5d:	mov    %rax,0x8(%r12)
 109db62:	cmp    %rcx,%rax
 109db65:	jae    109e879 <my.diagram_membership::compute_sub_block_attachments+0x4a99>
 109db6b:	lea    -0x7db92(%rip),%rcx        # 101ffe0 <core_number_pairs+0x18a90>
 109db72:	mov    %rcx,0x20(%r12,%rax,8)
 109db77:	inc    %rax
 109db7a:	mov    %rax,0x8(%r12)
 109db7f:	mov    0x8(%r15),%rcx
 109db83:	cmp    0x10(%r15),%rcx
 109db87:	mov    %rbp,0xe8(%rsp)
 109db8f:	jae    109e892 <my.diagram_membership::compute_sub_block_attachments+0x4ab2>
 109db95:	lea    0x20(%r15),%rsi
 109db99:	mov    %rcx,%rax
 109db9c:	shl    $0x4,%rax
 109dba0:	movq   $0x4,0x20(%r15,%rax,1)
 109dba9:	mov    %r12,0x28(%r15,%rax,1)
 109dbae:	lea    0x1(%rcx),%rax
 109dbb2:	mov    %rax,0x8(%r15)
 109dbb6:	xor    %r9d,%r9d
 109dbb9:	mov    %rcx,0xd0(%rsp)
 109dbc1:	mov    %r9,%r10
 109dbc4:	shl    $0x4,%r10
 109dbc8:	mov    0x8(%rsi,%r10,1),%r11
 109dbcd:	mov    0x8(%r11),%rax
 109dbd1:	mov    %rax,0x20(%rsp)
 109dbd6:	test   %rax,%rax
 109dbd9:	je     109dd40 <my.diagram_membership::compute_sub_block_attachments+0x3f60>
 109dbdf:	add    %rsi,%r10
 109dbe2:	mov    0x8(%r14),%rdx
 109dbe6:	xor    %r12d,%r12d
 109dbe9:	jmp    109dc12 <my.diagram_membership::compute_sub_block_attachments+0x3e32>
 109dbeb:	test   %cl,%cl
 109dbed:	je     109dd70 <my.diagram_membership::compute_sub_block_attachments+0x3f90>
 109dbf3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109dc00:	inc    %r12
 109dc03:	cmp    0x20(%rsp),%r12
 109dc08:	lea    0x20(%r15),%rsi
 109dc0c:	je     109dd40 <my.diagram_membership::compute_sub_block_attachments+0x3f60>
 109dc12:	mov    0x20(%r11,%r12,8),%r13
 109dc17:	mov    0x8(%r13),%rax
 109dc1b:	cmp    %rdx,%rax
 109dc1e:	ja     109dc00 <my.diagram_membership::compute_sub_block_attachments+0x3e20>
 109dc20:	xor    %ebx,%ebx
 109dc22:	mov    %rbx,%rbp
 109dc25:	add    %rax,%rbp
 109dc28:	jo     109eb1f <my.diagram_membership::compute_sub_block_attachments+0x4d3f>
 109dc2e:	cmp    %rdx,%rbp
 109dc31:	seta   %cl
 109dc34:	test   %rax,%rax
 109dc37:	je     109dbeb <my.diagram_membership::compute_sub_block_attachments+0x3e0b>
 109dc39:	cmp    %rdx,%rbp
 109dc3c:	ja     109dbeb <my.diagram_membership::compute_sub_block_attachments+0x3e0b>
 109dc3e:	xor    %ecx,%ecx
 109dc40:	mov    %rbx,%rsi
 109dc43:	add    %rcx,%rsi
 109dc46:	jo     109ea68 <my.diagram_membership::compute_sub_block_attachments+0x4c88>
 109dc4c:	cmp    %rdx,%rsi
 109dc4f:	jae    109ea4f <my.diagram_membership::compute_sub_block_attachments+0x4c6f>
 109dc55:	movzbl 0x20(%r14,%rsi,1),%esi
 109dc5b:	lea    -0x41(%rsi),%ebp
 109dc5e:	lea    0x20(%rsi),%r8d
 109dc62:	cmp    $0x1a,%bpl
 109dc66:	cmovae %rsi,%r8
 109dc6a:	movzbl 0x20(%r13,%rcx,1),%esi
 109dc70:	lea    -0x41(%rsi),%ebp
 109dc73:	lea    0x20(%rsi),%edi
 109dc76:	cmp    $0x1a,%bpl
 109dc7a:	cmovae %rsi,%rdi
 109dc7e:	cmp    %edi,%r8d
 109dc81:	jne    109dc90 <my.diagram_membership::compute_sub_block_attachments+0x3eb0>
 109dc83:	inc    %rcx
 109dc86:	cmp    %rcx,%rax
 109dc89:	jne    109dc40 <my.diagram_membership::compute_sub_block_attachments+0x3e60>
 109dc8b:	jmp    109dd70 <my.diagram_membership::compute_sub_block_attachments+0x3f90>
 109dc90:	lea    0x1(%rbx),%rsi
 109dc94:	mov    %rsi,%rbp
 109dc97:	add    %rax,%rbp
 109dc9a:	jo     109eb1c <my.diagram_membership::compute_sub_block_attachments+0x4d3c>
 109dca0:	cmp    %rdx,%rbp
 109dca3:	seta   %cl
 109dca6:	test   %rax,%rax
 109dca9:	je     109dbeb <my.diagram_membership::compute_sub_block_attachments+0x3e0b>
 109dcaf:	cmp    %rdx,%rbp
 109dcb2:	ja     109dbeb <my.diagram_membership::compute_sub_block_attachments+0x3e0b>
 109dcb8:	xor    %ecx,%ecx
 109dcba:	nopw   0x0(%rax,%rax,1)
 109dcc0:	mov    %rsi,%rbp
 109dcc3:	add    %rcx,%rbp
 109dcc6:	jo     109ea65 <my.diagram_membership::compute_sub_block_attachments+0x4c85>
 109dccc:	cmp    %rdx,%rbp
 109dccf:	jae    109ea4c <my.diagram_membership::compute_sub_block_attachments+0x4c6c>
 109dcd5:	movzbl 0x20(%r14,%rbp,1),%edi
 109dcdb:	lea    -0x41(%rdi),%r8d
 109dcdf:	lea    0x20(%rdi),%ebp
 109dce2:	cmp    $0x1a,%r8b
 109dce6:	cmovae %rdi,%rbp
 109dcea:	movzbl 0x20(%r13,%rcx,1),%edi
 109dcf0:	lea    -0x41(%rdi),%r8d
 109dcf4:	lea    0x20(%rdi),%r14d
 109dcf8:	cmp    $0x1a,%r8b
 109dcfc:	cmovae %rdi,%r14
 109dd00:	cmp    %r14d,%ebp
 109dd03:	jne    109dd20 <my.diagram_membership::compute_sub_block_attachments+0x3f40>
 109dd05:	inc    %rcx
 109dd08:	cmp    %rcx,%rax
 109dd0b:	mov    0x10(%rsp),%r14
 109dd10:	jne    109dcc0 <my.diagram_membership::compute_sub_block_attachments+0x3ee0>
 109dd12:	jmp    109dd70 <my.diagram_membership::compute_sub_block_attachments+0x3f90>
 109dd14:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109dd20:	add    $0x2,%rbx
 109dd24:	mov    0x10(%rsp),%r14
 109dd29:	jno    109dc22 <my.diagram_membership::compute_sub_block_attachments+0x3e42>
 109dd2f:	jmp    109eb31 <my.diagram_membership::compute_sub_block_attachments+0x4d51>
 109dd34:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109dd40:	mov    0xd0(%rsp),%rcx
 109dd48:	cmp    %rcx,%r9
 109dd4b:	lea    0x1(%r9),%r9
 109dd4f:	jne    109dbc1 <my.diagram_membership::compute_sub_block_attachments+0x3de1>
 109dd55:	mov    %r15,%rdi
 109dd58:	call   103c740 <myl_core_drop_owned>
 109dd5d:	xor    %eax,%eax
 109dd5f:	xor    %r14d,%r14d
 109dd62:	jmp    109dd7e <my.diagram_membership::compute_sub_block_attachments+0x3f9e>
 109dd64:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 109dd70:	movzbl (%r10),%r14d
 109dd74:	mov    %r15,%rdi
 109dd77:	call   103c740 <myl_core_drop_owned>
 109dd7c:	mov    $0x1,%al
 109dd7e:	cmp    $0x1,%al
 109dd80:	mov    0x70(%rsp),%r13
 109dd85:	mov    0x80(%rsp),%r15
 109dd8d:	mov    0xf0(%rsp),%r12
 109dd95:	jne    109ddb0 <my.diagram_membership::compute_sub_block_attachments+0x3fd0>
 109dd97:	cmp    $0x4,%r14b
 109dd9b:	sete   %bpl
 109dd9f:	mov    (%rsp),%r14
 109dda3:	jmp    109de40 <my.diagram_membership::compute_sub_block_attachments+0x4060>
 109dda8:	nopl   0x0(%rax,%rax,1)
 109ddb0:	mov    0x8(%rsp),%rcx
 109ddb5:	mov    0x8(%rcx),%rax
 109ddb9:	test   %rax,%rax
 109ddbc:	je     109de29 <my.diagram_membership::compute_sub_block_attachments+0x4049>
 109ddbe:	add    $0x20,%rcx
 109ddc2:	mov    (%rsp),%r14
 109ddc6:	jmp    109de0c <my.diagram_membership::compute_sub_block_attachments+0x402c>
 109ddc8:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ddd7:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109dde6:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109ddf5:	data16 cs nopw 0x0(%rax,%rax,1)
 109de00:	add    $0x218,%rcx
 109de07:	dec    %rax
 109de0a:	je     109de31 <my.diagram_membership::compute_sub_block_attachments+0x4051>
 109de0c:	mov    (%rcx),%rdx
 109de0f:	cmpq   $0x0,0x8(%rdx)
 109de14:	je     109de00 <my.diagram_membership::compute_sub_block_attachments+0x4020>
 109de16:	movzbl 0x20(%rdx),%edx
 109de1a:	mov    $0x1,%bpl
 109de1d:	cmp    $0x50,%edx
 109de20:	je     109de40 <my.diagram_membership::compute_sub_block_attachments+0x4060>
 109de22:	cmp    $0x4a,%edx
 109de25:	jne    109de00 <my.diagram_membership::compute_sub_block_attachments+0x4020>
 109de27:	jmp    109de40 <my.diagram_membership::compute_sub_block_attachments+0x4060>
 109de29:	xor    %ebp,%ebp
 109de2b:	mov    (%rsp),%r14
 109de2f:	jmp    109de40 <my.diagram_membership::compute_sub_block_attachments+0x4060>
 109de31:	xor    %ebp,%ebp
 109de33:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109de40:	mov    0x10(%rsp),%rdi
 109de45:	call   103c740 <myl_core_drop_owned>
 109de4a:	mov    0xc8(%rsp),%rdi
 109de52:	call   103c740 <myl_core_drop_owned>
 109de57:	mov    0x30(%rsp),%rdi
 109de5c:	call   103c740 <myl_core_drop_owned>
 109de61:	mov    0x60(%rsp),%rdi
 109de66:	call   103c740 <myl_core_drop_owned>
 109de6b:	mov    0x8(%rsp),%rdi
 109de70:	call   103c740 <myl_core_drop_owned>
 109de75:	mov    0x38(%rsp),%rdi
 109de7a:	call   103c740 <myl_core_drop_owned>
 109de7f:	mov    %r14,%rdi
 109de82:	call   103c740 <myl_core_drop_owned>
 109de87:	mov    0xe8(%rsp),%rdi
 109de8f:	call   103c740 <myl_core_drop_owned>
 109de94:	mov    %r12,%rdi
 109de97:	call   103c740 <myl_core_drop_owned>
 109de9c:	mov    0x40(%rsp),%rdi
 109dea1:	call   103c740 <myl_core_drop_owned>
 109dea6:	mov    %r15,%rdi
 109dea9:	call   103c740 <myl_core_drop_owned>
 109deae:	mov    0x98(%rsp),%rdi
 109deb6:	mov    0xe0(%rsp),%r8
 109debe:	cmp    %rdi,%r8
 109dec1:	setg   %al
 109dec4:	sete   %cl
 109dec7:	mov    0xb8(%rsp),%esi
 109dece:	and    %sil,%cl
 109ded1:	movzbl %bpl,%edx
 109ded5:	xor    $0x1,%bpl
 109ded9:	and    %cl,%bpl
 109dedc:	or     %al,%bpl
 109dedf:	cmovne %r8,%rdi
 109dee3:	mov    %rdi,0x98(%rsp)
 109deeb:	movzbl %sil,%esi
 109deef:	cmovne %edx,%esi
 109def2:	mov    %esi,0xb8(%rsp)
 109def9:	mov    0xa8(%rsp),%rax
 109df01:	cmovne %r13,%rax
 109df05:	mov    %rax,0xa8(%rsp)
 109df0d:	mov    0x90(%rsp),%rcx
 109df15:	movzbl %cl,%ecx
 109df18:	mov    $0x1,%eax
 109df1d:	cmovne %eax,%ecx
 109df20:	mov    %rcx,0x90(%rsp)
 109df28:	jmp    109d048 <my.diagram_membership::compute_sub_block_attachments+0x3268>
 109df2d:	mov    $0x9,%edi
 109df32:	mov    $0x10,%esi
 109df37:	call   103b980 <myl_core_list_new_slow>
 109df3c:	mov    %rax,%r15
 109df3f:	jmp    109d218 <my.diagram_membership::compute_sub_block_attachments+0x3438>
 109df44:	mov    $0x8,%edi
 109df49:	mov    %rsi,%rbx
 109df4c:	mov    $0x8,%esi
 109df51:	call   103b980 <myl_core_list_new_slow>
 109df56:	mov    0x8(%rax),%rcx
 109df5a:	mov    0x10(%rax),%rdx
 109df5e:	mov    %rbx,0x18(%rax)
 109df62:	cmp    %rdx,%rcx
 109df65:	jb     109df7c <my.diagram_membership::compute_sub_block_attachments+0x419c>
 109df67:	mov    $0x8,%esi
 109df6c:	mov    %rax,%rdi
 109df6f:	call   103ba40 <myl_core_list_grow>
 109df74:	mov    0x8(%rax),%rcx
 109df78:	mov    0x10(%rax),%rdx
 109df7c:	lea    -0x72e2b(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109df83:	jmp    109d26e <my.diagram_membership::compute_sub_block_attachments+0x348e>
 109df88:	mov    $0x8,%esi
 109df8d:	mov    %rax,%rdi
 109df90:	call   103ba40 <myl_core_list_grow>
 109df95:	lea    -0x72e44(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109df9c:	mov    0x8(%rax),%rcx
 109dfa0:	mov    0x10(%rax),%rdx
 109dfa4:	jmp    109d28a <my.diagram_membership::compute_sub_block_attachments+0x34aa>
 109dfa9:	mov    $0x8,%esi
 109dfae:	mov    %rax,%rdi
 109dfb1:	call   103ba40 <myl_core_list_grow>
 109dfb6:	lea    -0x72e65(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109dfbd:	mov    0x8(%rax),%rcx
 109dfc1:	mov    0x10(%rax),%rdx
 109dfc5:	jmp    109d2a6 <my.diagram_membership::compute_sub_block_attachments+0x34c6>
 109dfca:	mov    $0x8,%esi
 109dfcf:	mov    %rax,%rdi
 109dfd2:	call   103ba40 <myl_core_list_grow>
 109dfd7:	lea    -0x72e86(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109dfde:	mov    0x8(%rax),%rcx
 109dfe2:	mov    0x10(%rax),%rdx
 109dfe6:	jmp    109d2c2 <my.diagram_membership::compute_sub_block_attachments+0x34e2>
 109dfeb:	mov    $0x8,%esi
 109dff0:	mov    %rax,%rdi
 109dff3:	call   103ba40 <myl_core_list_grow>
 109dff8:	lea    -0x72ea7(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109dfff:	mov    0x8(%rax),%rcx
 109e003:	mov    0x10(%rax),%rdx
 109e007:	jmp    109d2de <my.diagram_membership::compute_sub_block_attachments+0x34fe>
 109e00c:	mov    $0x8,%esi
 109e011:	mov    %rax,%rdi
 109e014:	call   103ba40 <myl_core_list_grow>
 109e019:	lea    -0x72ec8(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e020:	mov    0x8(%rax),%rcx
 109e024:	mov    0x10(%rax),%rdx
 109e028:	jmp    109d2fa <my.diagram_membership::compute_sub_block_attachments+0x351a>
 109e02d:	mov    $0x8,%esi
 109e032:	mov    %rax,%rdi
 109e035:	call   103ba40 <myl_core_list_grow>
 109e03a:	lea    -0x72ee9(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e041:	mov    0x8(%rax),%rcx
 109e045:	mov    0x10(%rax),%rdx
 109e049:	jmp    109d316 <my.diagram_membership::compute_sub_block_attachments+0x3536>
 109e04e:	mov    $0x8,%esi
 109e053:	mov    %rax,%rdi
 109e056:	call   103ba40 <myl_core_list_grow>
 109e05b:	lea    -0x72f0a(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e062:	mov    0x8(%rax),%rcx
 109e066:	jmp    109d332 <my.diagram_membership::compute_sub_block_attachments+0x3552>
 109e06b:	mov    $0x10,%esi
 109e070:	mov    %r15,%rdi
 109e073:	mov    %rax,%rbx
 109e076:	call   103ba40 <myl_core_list_grow>
 109e07b:	lea    -0x72f2a(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e082:	mov    %rax,%r15
 109e085:	mov    %rbx,%rax
 109e088:	mov    0x8(%r15),%rcx
 109e08c:	jmp    109d353 <my.diagram_membership::compute_sub_block_attachments+0x3573>
 109e091:	mov    $0x7,%edi
 109e096:	mov    %rsi,%rbx
 109e099:	mov    $0x8,%esi
 109e09e:	call   103b980 <myl_core_list_new_slow>
 109e0a3:	mov    0x8(%rax),%rcx
 109e0a7:	mov    0x10(%rax),%rdx
 109e0ab:	mov    %rbx,0x18(%rax)
 109e0af:	cmp    %rdx,%rcx
 109e0b2:	jb     109e0c9 <my.diagram_membership::compute_sub_block_attachments+0x42e9>
 109e0b4:	mov    $0x8,%esi
 109e0b9:	mov    %rax,%rdi
 109e0bc:	call   103ba40 <myl_core_list_grow>
 109e0c1:	mov    0x8(%rax),%rcx
 109e0c5:	mov    0x10(%rax),%rdx
 109e0c9:	lea    -0x72f78(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e0d0:	jmp    109d3ae <my.diagram_membership::compute_sub_block_attachments+0x35ce>
 109e0d5:	mov    $0x8,%esi
 109e0da:	mov    %rax,%rdi
 109e0dd:	call   103ba40 <myl_core_list_grow>
 109e0e2:	lea    -0x72f91(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e0e9:	mov    0x8(%rax),%rcx
 109e0ed:	mov    0x10(%rax),%rdx
 109e0f1:	jmp    109d3ca <my.diagram_membership::compute_sub_block_attachments+0x35ea>
 109e0f6:	mov    $0x8,%esi
 109e0fb:	mov    %rax,%rdi
 109e0fe:	call   103ba40 <myl_core_list_grow>
 109e103:	lea    -0x72fb2(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e10a:	mov    0x8(%rax),%rcx
 109e10e:	mov    0x10(%rax),%rdx
 109e112:	jmp    109d3e6 <my.diagram_membership::compute_sub_block_attachments+0x3606>
 109e117:	mov    $0x8,%esi
 109e11c:	mov    %rax,%rdi
 109e11f:	call   103ba40 <myl_core_list_grow>
 109e124:	lea    -0x72fd3(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e12b:	mov    0x8(%rax),%rcx
 109e12f:	mov    0x10(%rax),%rdx
 109e133:	jmp    109d402 <my.diagram_membership::compute_sub_block_attachments+0x3622>
 109e138:	mov    $0x8,%esi
 109e13d:	mov    %rax,%rdi
 109e140:	call   103ba40 <myl_core_list_grow>
 109e145:	lea    -0x72ff4(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e14c:	mov    0x8(%rax),%rcx
 109e150:	mov    0x10(%rax),%rdx
 109e154:	jmp    109d41e <my.diagram_membership::compute_sub_block_attachments+0x363e>
 109e159:	mov    $0x8,%esi
 109e15e:	mov    %rax,%rdi
 109e161:	call   103ba40 <myl_core_list_grow>
 109e166:	lea    -0x73015(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e16d:	mov    0x8(%rax),%rcx
 109e171:	mov    0x10(%rax),%rdx
 109e175:	jmp    109d43a <my.diagram_membership::compute_sub_block_attachments+0x365a>
 109e17a:	mov    $0x8,%esi
 109e17f:	mov    %rax,%rdi
 109e182:	call   103ba40 <myl_core_list_grow>
 109e187:	lea    -0x73036(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e18e:	mov    0x8(%rax),%rcx
 109e192:	jmp    109d456 <my.diagram_membership::compute_sub_block_attachments+0x3676>
 109e197:	mov    $0x10,%esi
 109e19c:	mov    %r15,%rdi
 109e19f:	mov    %rax,%rbx
 109e1a2:	call   103ba40 <myl_core_list_grow>
 109e1a7:	lea    -0x73056(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e1ae:	mov    %rax,%r15
 109e1b1:	mov    %rbx,%rax
 109e1b4:	mov    0x8(%r15),%rcx
 109e1b8:	jmp    109d477 <my.diagram_membership::compute_sub_block_attachments+0x3697>
 109e1bd:	mov    $0x5,%edi
 109e1c2:	mov    %rsi,%rbx
 109e1c5:	mov    $0x8,%esi
 109e1ca:	call   103b980 <myl_core_list_new_slow>
 109e1cf:	mov    0x8(%rax),%rcx
 109e1d3:	mov    0x10(%rax),%rdx
 109e1d7:	mov    %rbx,0x18(%rax)
 109e1db:	cmp    %rdx,%rcx
 109e1de:	jb     109e1f5 <my.diagram_membership::compute_sub_block_attachments+0x4415>
 109e1e0:	mov    $0x8,%esi
 109e1e5:	mov    %rax,%rdi
 109e1e8:	call   103ba40 <myl_core_list_grow>
 109e1ed:	mov    0x8(%rax),%rcx
 109e1f1:	mov    0x10(%rax),%rdx
 109e1f5:	lea    -0x730a4(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e1fc:	jmp    109d4d2 <my.diagram_membership::compute_sub_block_attachments+0x36f2>
 109e201:	mov    $0x8,%esi
 109e206:	mov    %rax,%rdi
 109e209:	call   103ba40 <myl_core_list_grow>
 109e20e:	lea    -0x730bd(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e215:	mov    0x8(%rax),%rcx
 109e219:	mov    0x10(%rax),%rdx
 109e21d:	jmp    109d4ee <my.diagram_membership::compute_sub_block_attachments+0x370e>
 109e222:	mov    $0x8,%esi
 109e227:	mov    %rax,%rdi
 109e22a:	call   103ba40 <myl_core_list_grow>
 109e22f:	lea    -0x730de(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e236:	mov    0x8(%rax),%rcx
 109e23a:	mov    0x10(%rax),%rdx
 109e23e:	jmp    109d50a <my.diagram_membership::compute_sub_block_attachments+0x372a>
 109e243:	mov    $0x8,%esi
 109e248:	mov    %rax,%rdi
 109e24b:	call   103ba40 <myl_core_list_grow>
 109e250:	lea    -0x730ff(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e257:	mov    0x8(%rax),%rcx
 109e25b:	mov    0x10(%rax),%rdx
 109e25f:	jmp    109d526 <my.diagram_membership::compute_sub_block_attachments+0x3746>
 109e264:	mov    $0x8,%esi
 109e269:	mov    %rax,%rdi
 109e26c:	call   103ba40 <myl_core_list_grow>
 109e271:	lea    -0x73120(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e278:	mov    0x8(%rax),%rcx
 109e27c:	jmp    109d542 <my.diagram_membership::compute_sub_block_attachments+0x3762>
 109e281:	mov    $0x10,%esi
 109e286:	mov    %r15,%rdi
 109e289:	mov    %rax,%rbx
 109e28c:	call   103ba40 <myl_core_list_grow>
 109e291:	lea    -0x73140(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e298:	mov    %rax,%r15
 109e29b:	mov    %rbx,%rax
 109e29e:	mov    0x8(%r15),%rcx
 109e2a2:	jmp    109d563 <my.diagram_membership::compute_sub_block_attachments+0x3783>
 109e2a7:	mov    $0x6,%edi
 109e2ac:	mov    %rsi,%rbx
 109e2af:	mov    $0x8,%esi
 109e2b4:	call   103b980 <myl_core_list_new_slow>
 109e2b9:	mov    0x8(%rax),%rcx
 109e2bd:	mov    0x10(%rax),%rdx
 109e2c1:	mov    %rbx,0x18(%rax)
 109e2c5:	cmp    %rdx,%rcx
 109e2c8:	jb     109e2df <my.diagram_membership::compute_sub_block_attachments+0x44ff>
 109e2ca:	mov    $0x8,%esi
 109e2cf:	mov    %rax,%rdi
 109e2d2:	call   103ba40 <myl_core_list_grow>
 109e2d7:	mov    0x8(%rax),%rcx
 109e2db:	mov    0x10(%rax),%rdx
 109e2df:	lea    -0x7318e(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e2e6:	jmp    109d5be <my.diagram_membership::compute_sub_block_attachments+0x37de>
 109e2eb:	mov    $0x8,%esi
 109e2f0:	mov    %rax,%rdi
 109e2f3:	call   103ba40 <myl_core_list_grow>
 109e2f8:	lea    -0x731a7(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e2ff:	mov    0x8(%rax),%rcx
 109e303:	mov    0x10(%rax),%rdx
 109e307:	jmp    109d5da <my.diagram_membership::compute_sub_block_attachments+0x37fa>
 109e30c:	mov    $0x8,%esi
 109e311:	mov    %rax,%rdi
 109e314:	call   103ba40 <myl_core_list_grow>
 109e319:	lea    -0x731c8(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e320:	mov    0x8(%rax),%rcx
 109e324:	mov    0x10(%rax),%rdx
 109e328:	jmp    109d5f6 <my.diagram_membership::compute_sub_block_attachments+0x3816>
 109e32d:	mov    $0x8,%esi
 109e332:	mov    %rax,%rdi
 109e335:	call   103ba40 <myl_core_list_grow>
 109e33a:	lea    -0x731e9(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e341:	mov    0x8(%rax),%rcx
 109e345:	mov    0x10(%rax),%rdx
 109e349:	jmp    109d612 <my.diagram_membership::compute_sub_block_attachments+0x3832>
 109e34e:	mov    $0x8,%esi
 109e353:	mov    %rax,%rdi
 109e356:	call   103ba40 <myl_core_list_grow>
 109e35b:	lea    -0x7320a(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e362:	mov    0x8(%rax),%rcx
 109e366:	mov    0x10(%rax),%rdx
 109e36a:	jmp    109d62e <my.diagram_membership::compute_sub_block_attachments+0x384e>
 109e36f:	mov    $0x8,%esi
 109e374:	mov    %rax,%rdi
 109e377:	call   103ba40 <myl_core_list_grow>
 109e37c:	lea    -0x7322b(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e383:	mov    0x8(%rax),%rcx
 109e387:	jmp    109d64a <my.diagram_membership::compute_sub_block_attachments+0x386a>
 109e38c:	mov    $0x10,%esi
 109e391:	mov    %r15,%rdi
 109e394:	mov    %rax,%rbx
 109e397:	call   103ba40 <myl_core_list_grow>
 109e39c:	lea    -0x7324b(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e3a3:	mov    %rax,%r15
 109e3a6:	mov    %rbx,%rax
 109e3a9:	mov    0x8(%r15),%rcx
 109e3ad:	jmp    109d66b <my.diagram_membership::compute_sub_block_attachments+0x388b>
 109e3b2:	mov    $0x6,%edi
 109e3b7:	mov    %rsi,%rbx
 109e3ba:	mov    $0x8,%esi
 109e3bf:	call   103b980 <myl_core_list_new_slow>
 109e3c4:	mov    0x8(%rax),%rcx
 109e3c8:	mov    0x10(%rax),%rdx
 109e3cc:	mov    %rbx,0x18(%rax)
 109e3d0:	cmp    %rdx,%rcx
 109e3d3:	jb     109e3ea <my.diagram_membership::compute_sub_block_attachments+0x460a>
 109e3d5:	mov    $0x8,%esi
 109e3da:	mov    %rax,%rdi
 109e3dd:	call   103ba40 <myl_core_list_grow>
 109e3e2:	mov    0x8(%rax),%rcx
 109e3e6:	mov    0x10(%rax),%rdx
 109e3ea:	lea    -0x73299(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e3f1:	jmp    109d6c6 <my.diagram_membership::compute_sub_block_attachments+0x38e6>
 109e3f6:	mov    $0x8,%esi
 109e3fb:	mov    %rax,%rdi
 109e3fe:	call   103ba40 <myl_core_list_grow>
 109e403:	lea    -0x732b2(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e40a:	mov    0x8(%rax),%rcx
 109e40e:	mov    0x10(%rax),%rdx
 109e412:	jmp    109d6e2 <my.diagram_membership::compute_sub_block_attachments+0x3902>
 109e417:	mov    $0x8,%esi
 109e41c:	mov    %rax,%rdi
 109e41f:	call   103ba40 <myl_core_list_grow>
 109e424:	lea    -0x732d3(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e42b:	mov    0x8(%rax),%rcx
 109e42f:	mov    0x10(%rax),%rdx
 109e433:	jmp    109d6fe <my.diagram_membership::compute_sub_block_attachments+0x391e>
 109e438:	mov    $0x8,%esi
 109e43d:	mov    %rax,%rdi
 109e440:	call   103ba40 <myl_core_list_grow>
 109e445:	lea    -0x732f4(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e44c:	mov    0x8(%rax),%rcx
 109e450:	mov    0x10(%rax),%rdx
 109e454:	jmp    109d71a <my.diagram_membership::compute_sub_block_attachments+0x393a>
 109e459:	mov    $0x8,%esi
 109e45e:	mov    %rax,%rdi
 109e461:	call   103ba40 <myl_core_list_grow>
 109e466:	lea    -0x73315(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e46d:	mov    0x8(%rax),%rcx
 109e471:	mov    0x10(%rax),%rdx
 109e475:	jmp    109d736 <my.diagram_membership::compute_sub_block_attachments+0x3956>
 109e47a:	mov    $0x8,%esi
 109e47f:	mov    %rax,%rdi
 109e482:	call   103ba40 <myl_core_list_grow>
 109e487:	lea    -0x73336(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e48e:	mov    0x8(%rax),%rcx
 109e492:	jmp    109d752 <my.diagram_membership::compute_sub_block_attachments+0x3972>
 109e497:	mov    $0x10,%esi
 109e49c:	mov    %r15,%rdi
 109e49f:	mov    %rax,%rbx
 109e4a2:	call   103ba40 <myl_core_list_grow>
 109e4a7:	lea    -0x73356(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e4ae:	mov    %rax,%r15
 109e4b1:	mov    %rbx,%rax
 109e4b4:	mov    0x8(%r15),%rcx
 109e4b8:	jmp    109d773 <my.diagram_membership::compute_sub_block_attachments+0x3993>
 109e4bd:	mov    $0x6,%edi
 109e4c2:	mov    %rsi,%rbx
 109e4c5:	mov    $0x8,%esi
 109e4ca:	call   103b980 <myl_core_list_new_slow>
 109e4cf:	mov    0x8(%rax),%rcx
 109e4d3:	mov    0x10(%rax),%rdx
 109e4d7:	mov    %rbx,0x18(%rax)
 109e4db:	cmp    %rdx,%rcx
 109e4de:	jb     109e4f5 <my.diagram_membership::compute_sub_block_attachments+0x4715>
 109e4e0:	mov    $0x8,%esi
 109e4e5:	mov    %rax,%rdi
 109e4e8:	call   103ba40 <myl_core_list_grow>
 109e4ed:	mov    0x8(%rax),%rcx
 109e4f1:	mov    0x10(%rax),%rdx
 109e4f5:	lea    -0x733a4(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e4fc:	jmp    109d7ce <my.diagram_membership::compute_sub_block_attachments+0x39ee>
 109e501:	mov    $0x8,%esi
 109e506:	mov    %rax,%rdi
 109e509:	call   103ba40 <myl_core_list_grow>
 109e50e:	lea    -0x733bd(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e515:	mov    0x8(%rax),%rcx
 109e519:	mov    0x10(%rax),%rdx
 109e51d:	jmp    109d7ea <my.diagram_membership::compute_sub_block_attachments+0x3a0a>
 109e522:	mov    $0x8,%esi
 109e527:	mov    %rax,%rdi
 109e52a:	call   103ba40 <myl_core_list_grow>
 109e52f:	lea    -0x733de(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e536:	mov    0x8(%rax),%rcx
 109e53a:	mov    0x10(%rax),%rdx
 109e53e:	jmp    109d806 <my.diagram_membership::compute_sub_block_attachments+0x3a26>
 109e543:	mov    $0x8,%esi
 109e548:	mov    %rax,%rdi
 109e54b:	call   103ba40 <myl_core_list_grow>
 109e550:	lea    -0x733ff(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e557:	mov    0x8(%rax),%rcx
 109e55b:	mov    0x10(%rax),%rdx
 109e55f:	jmp    109d822 <my.diagram_membership::compute_sub_block_attachments+0x3a42>
 109e564:	mov    $0x8,%esi
 109e569:	mov    %rax,%rdi
 109e56c:	call   103ba40 <myl_core_list_grow>
 109e571:	lea    -0x73420(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e578:	mov    0x8(%rax),%rcx
 109e57c:	mov    0x10(%rax),%rdx
 109e580:	jmp    109d83e <my.diagram_membership::compute_sub_block_attachments+0x3a5e>
 109e585:	mov    $0x8,%esi
 109e58a:	mov    %rax,%rdi
 109e58d:	call   103ba40 <myl_core_list_grow>
 109e592:	lea    -0x73441(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e599:	mov    0x8(%rax),%rcx
 109e59d:	jmp    109d85a <my.diagram_membership::compute_sub_block_attachments+0x3a7a>
 109e5a2:	mov    $0x10,%esi
 109e5a7:	mov    %r15,%rdi
 109e5aa:	mov    %rax,%rbx
 109e5ad:	call   103ba40 <myl_core_list_grow>
 109e5b2:	lea    -0x73461(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e5b9:	mov    %rax,%r15
 109e5bc:	mov    %rbx,%rax
 109e5bf:	mov    0x8(%r15),%rcx
 109e5c3:	jmp    109d87b <my.diagram_membership::compute_sub_block_attachments+0x3a9b>
 109e5c8:	mov    $0x5,%edi
 109e5cd:	mov    %rsi,%rbx
 109e5d0:	mov    $0x8,%esi
 109e5d5:	call   103b980 <myl_core_list_new_slow>
 109e5da:	mov    0x8(%rax),%rcx
 109e5de:	mov    0x10(%rax),%rdx
 109e5e2:	mov    %rbx,0x18(%rax)
 109e5e6:	cmp    %rdx,%rcx
 109e5e9:	jb     109e600 <my.diagram_membership::compute_sub_block_attachments+0x4820>
 109e5eb:	mov    $0x8,%esi
 109e5f0:	mov    %rax,%rdi
 109e5f3:	call   103ba40 <myl_core_list_grow>
 109e5f8:	mov    0x8(%rax),%rcx
 109e5fc:	mov    0x10(%rax),%rdx
 109e600:	lea    -0x734af(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e607:	jmp    109d8d6 <my.diagram_membership::compute_sub_block_attachments+0x3af6>
 109e60c:	mov    $0x8,%esi
 109e611:	mov    %rax,%rdi
 109e614:	call   103ba40 <myl_core_list_grow>
 109e619:	lea    -0x734c8(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e620:	mov    0x8(%rax),%rcx
 109e624:	mov    0x10(%rax),%rdx
 109e628:	jmp    109d8f2 <my.diagram_membership::compute_sub_block_attachments+0x3b12>
 109e62d:	mov    $0x8,%esi
 109e632:	mov    %rax,%rdi
 109e635:	call   103ba40 <myl_core_list_grow>
 109e63a:	lea    -0x734e9(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e641:	mov    0x8(%rax),%rcx
 109e645:	mov    0x10(%rax),%rdx
 109e649:	jmp    109d90e <my.diagram_membership::compute_sub_block_attachments+0x3b2e>
 109e64e:	mov    $0x8,%esi
 109e653:	mov    %rax,%rdi
 109e656:	call   103ba40 <myl_core_list_grow>
 109e65b:	lea    -0x7350a(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e662:	mov    0x8(%rax),%rcx
 109e666:	mov    0x10(%rax),%rdx
 109e66a:	jmp    109d92a <my.diagram_membership::compute_sub_block_attachments+0x3b4a>
 109e66f:	mov    $0x8,%esi
 109e674:	mov    %rax,%rdi
 109e677:	call   103ba40 <myl_core_list_grow>
 109e67c:	lea    -0x7352b(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e683:	mov    0x8(%rax),%rcx
 109e687:	jmp    109d946 <my.diagram_membership::compute_sub_block_attachments+0x3b66>
 109e68c:	mov    $0x10,%esi
 109e691:	mov    %r15,%rdi
 109e694:	mov    %rax,%rbx
 109e697:	call   103ba40 <myl_core_list_grow>
 109e69c:	lea    -0x7354b(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e6a3:	mov    %rax,%r15
 109e6a6:	mov    %rbx,%rax
 109e6a9:	mov    0x8(%r15),%rcx
 109e6ad:	jmp    109d967 <my.diagram_membership::compute_sub_block_attachments+0x3b87>
 109e6b2:	mov    $0x4,%edi
 109e6b7:	mov    %rsi,%rbx
 109e6ba:	mov    $0x8,%esi
 109e6bf:	call   103b980 <myl_core_list_new_slow>
 109e6c4:	mov    0x8(%rax),%rcx
 109e6c8:	mov    0x10(%rax),%rdx
 109e6cc:	mov    %rbx,0x18(%rax)
 109e6d0:	cmp    %rdx,%rcx
 109e6d3:	jb     109e6ea <my.diagram_membership::compute_sub_block_attachments+0x490a>
 109e6d5:	mov    $0x8,%esi
 109e6da:	mov    %rax,%rdi
 109e6dd:	call   103ba40 <myl_core_list_grow>
 109e6e2:	mov    0x8(%rax),%rcx
 109e6e6:	mov    0x10(%rax),%rdx
 109e6ea:	lea    -0x73599(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e6f1:	jmp    109d9c2 <my.diagram_membership::compute_sub_block_attachments+0x3be2>
 109e6f6:	mov    $0x8,%esi
 109e6fb:	mov    %rax,%rdi
 109e6fe:	call   103ba40 <myl_core_list_grow>
 109e703:	lea    -0x735b2(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e70a:	mov    0x8(%rax),%rcx
 109e70e:	mov    0x10(%rax),%rdx
 109e712:	jmp    109d9de <my.diagram_membership::compute_sub_block_attachments+0x3bfe>
 109e717:	mov    $0x8,%esi
 109e71c:	mov    %rax,%rdi
 109e71f:	call   103ba40 <myl_core_list_grow>
 109e724:	lea    -0x735d3(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e72b:	mov    0x8(%rax),%rcx
 109e72f:	mov    0x10(%rax),%rdx
 109e733:	jmp    109d9fa <my.diagram_membership::compute_sub_block_attachments+0x3c1a>
 109e738:	mov    $0x8,%esi
 109e73d:	mov    %rax,%rdi
 109e740:	call   103ba40 <myl_core_list_grow>
 109e745:	lea    -0x735f4(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e74c:	mov    0x8(%rax),%rcx
 109e750:	jmp    109da16 <my.diagram_membership::compute_sub_block_attachments+0x3c36>
 109e755:	mov    $0x10,%esi
 109e75a:	mov    %r15,%rdi
 109e75d:	mov    %rax,%rbx
 109e760:	call   103ba40 <myl_core_list_grow>
 109e765:	lea    -0x73614(%rip),%rsi        # 102b158 <core_number_pairs+0x23c08>
 109e76c:	mov    %rax,%r15
 109e76f:	mov    %rbx,%rax
 109e772:	mov    0x8(%r15),%rcx
 109e776:	jmp    109da3f <my.diagram_membership::compute_sub_block_attachments+0x3c5f>
 109e77b:	mov    $0x8,%edi
 109e780:	mov    %rsi,%rbx
 109e783:	mov    $0x8,%esi
 109e788:	call   103b980 <myl_core_list_new_slow>
 109e78d:	mov    %rax,%r12
 109e790:	mov    0x8(%rax),%rax
 109e794:	mov    0x10(%r12),%rcx
 109e799:	mov    %rbx,0x18(%r12)
 109e79e:	cmp    %rcx,%rax
 109e7a1:	jb     109daa0 <my.diagram_membership::compute_sub_block_attachments+0x3cc0>
 109e7a7:	mov    $0x8,%esi
 109e7ac:	mov    %r12,%rdi
 109e7af:	call   103ba40 <myl_core_list_grow>
 109e7b4:	mov    %rax,%r12
 109e7b7:	mov    0x8(%rax),%rax
 109e7bb:	mov    0x10(%r12),%rcx
 109e7c0:	jmp    109daa0 <my.diagram_membership::compute_sub_block_attachments+0x3cc0>
 109e7c5:	mov    $0x8,%esi
 109e7ca:	mov    %r12,%rdi
 109e7cd:	call   103ba40 <myl_core_list_grow>
 109e7d2:	mov    %rax,%r12
 109e7d5:	mov    0x8(%rax),%rax
 109e7d9:	mov    0x10(%r12),%rcx
 109e7de:	jmp    109dabd <my.diagram_membership::compute_sub_block_attachments+0x3cdd>
 109e7e3:	mov    $0x8,%esi
 109e7e8:	mov    %r12,%rdi
 109e7eb:	call   103ba40 <myl_core_list_grow>
 109e7f0:	mov    %rax,%r12
 109e7f3:	mov    0x8(%rax),%rax
 109e7f7:	mov    0x10(%r12),%rcx
 109e7fc:	jmp    109dada <my.diagram_membership::compute_sub_block_attachments+0x3cfa>
 109e801:	mov    $0x8,%esi
 109e806:	mov    %r12,%rdi
 109e809:	call   103ba40 <myl_core_list_grow>
 109e80e:	mov    %rax,%r12
 109e811:	mov    0x8(%rax),%rax
 109e815:	mov    0x10(%r12),%rcx
 109e81a:	jmp    109daf7 <my.diagram_membership::compute_sub_block_attachments+0x3d17>
 109e81f:	mov    $0x8,%esi
 109e824:	mov    %r12,%rdi
 109e827:	call   103ba40 <myl_core_list_grow>
 109e82c:	mov    %rax,%r12
 109e82f:	mov    0x8(%rax),%rax
 109e833:	mov    0x10(%r12),%rcx
 109e838:	jmp    109db14 <my.diagram_membership::compute_sub_block_attachments+0x3d34>
 109e83d:	mov    $0x8,%esi
 109e842:	mov    %r12,%rdi
 109e845:	call   103ba40 <myl_core_list_grow>
 109e84a:	mov    %rax,%r12
 109e84d:	mov    0x8(%rax),%rax
 109e851:	mov    0x10(%r12),%rcx
 109e856:	jmp    109db31 <my.diagram_membership::compute_sub_block_attachments+0x3d51>
 109e85b:	mov    $0x8,%esi
 109e860:	mov    %r12,%rdi
 109e863:	call   103ba40 <myl_core_list_grow>
 109e868:	mov    %rax,%r12
 109e86b:	mov    0x8(%rax),%rax
 109e86f:	mov    0x10(%r12),%rcx
 109e874:	jmp    109db4e <my.diagram_membership::compute_sub_block_attachments+0x3d6e>
 109e879:	mov    $0x8,%esi
 109e87e:	mov    %r12,%rdi
 109e881:	call   103ba40 <myl_core_list_grow>
 109e886:	mov    %rax,%r12
 109e889:	mov    0x8(%rax),%rax
 109e88d:	jmp    109db6b <my.diagram_membership::compute_sub_block_attachments+0x3d8b>
 109e892:	mov    $0x10,%esi
 109e897:	mov    %r15,%rdi
 109e89a:	call   103ba40 <myl_core_list_grow>
 109e89f:	mov    %rax,%r15
 109e8a2:	mov    0x8(%rax),%rcx
 109e8a6:	jmp    109db95 <my.diagram_membership::compute_sub_block_attachments+0x3db5>
 109e8ab:	nopl   0x0(%rax,%rax,1)
 109e8b0:	cmpq   $0x0,0x98(%rsp)
 109e8b9:	mov    0x58(%rsp),%r15
 109e8be:	mov    0xf8(%rsp),%rsi
 109e8c6:	je     109c1c8 <my.diagram_membership::compute_sub_block_attachments+0x23e8>
 109e8cc:	mov    0x120(%rsp),%rax
 109e8d4:	mov    0x8(%rax),%rdx
 109e8d8:	cmp    %rdx,%rsi
 109e8db:	jb     109c1a0 <my.diagram_membership::compute_sub_block_attachments+0x23c0>
 109e8e1:	jmp    109ebb4 <my.diagram_membership::compute_sub_block_attachments+0x4dd4>
 109e8e6:	mov    0x80(%rsp),%rdi
 109e8ee:	call   103c740 <myl_core_drop_owned>
 109e8f3:	mov    0x120(%rsp),%rax
 109e8fb:	mov    0x8(%rax),%rdx
 109e8ff:	mov    0xf8(%rsp),%rsi
 109e907:	cmp    %rdx,%rsi
 109e90a:	jae    109eba8 <my.diagram_membership::compute_sub_block_attachments+0x4dc8>
 109e910:	shl    $0x4,%r15
 109e914:	mov    0x58(%rsp),%rcx
 109e919:	mov    0x28(%rcx,%r15,1),%rax
 109e91e:	mov    %rcx,%r15
 109e921:	mov    %rsi,%rcx
 109e924:	shl    $0x4,%rcx
 109e928:	mov    0x250(%rsp),%rdx
 109e930:	movq   $0x1,(%rdx,%rcx,1)
 109e938:	mov    %rax,0x8(%rdx,%rcx,1)
 109e93d:	jmp    109c1c8 <my.diagram_membership::compute_sub_block_attachments+0x23e8>
 109e942:	mov    0x20(%rcx),%r12
 109e946:	test   %r12,%r12
 109e949:	je     109cf11 <my.diagram_membership::compute_sub_block_attachments+0x3131>
 109e94f:	mov    0x10(%rcx),%r13
 109e953:	mov    0x258(%rsp),%rbx
 109e95b:	xor    %r15d,%r15d
 109e95e:	jmp    109e990 <my.diagram_membership::compute_sub_block_attachments+0x4bb0>
 109e960:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109e96f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109e97e:	xchg   %ax,%ax
 109e980:	inc    %r15
 109e983:	add    $0x10,%rbx
 109e987:	cmp    %r15,%r12
 109e98a:	je     109cf11 <my.diagram_membership::compute_sub_block_attachments+0x3131>
 109e990:	cmp    %r14,0x0(%r13,%r15,8)
 109e995:	jne    109e980 <my.diagram_membership::compute_sub_block_attachments+0x4ba0>
 109e997:	mov    (%rbx),%rdi
 109e99a:	mov    0x1f0(%rsp),%rsi
 109e9a2:	call   1044580 <myl_core_str_eq>
 109e9a7:	test   %al,%al
 109e9a9:	je     109e980 <my.diagram_membership::compute_sub_block_attachments+0x4ba0>
 109e9ab:	jmp    109cf53 <my.diagram_membership::compute_sub_block_attachments+0x3173>
 109e9b0:	lea    0x4e179(%rip),%rdi        # 10ecb30 <core_durable_error.verbs+0x1530>
 109e9b7:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 109e9bc:	mov    $0x1,%al
 109e9be:	lea    -0x82da5(%rip),%r14        # 101bc20 <core_number_pairs+0x146d0>
 109e9c5:	test   %al,%al
 109e9c7:	je     109cb1d <my.diagram_membership::compute_sub_block_attachments+0x2d3d>
 109e9cd:	mov    %r14,%rdi
 109e9d0:	call   103c740 <myl_core_drop_owned>
 109e9d5:	lea    0x4e184(%rip),%rdi        # 10ecb60 <core_durable_error.verbs+0x1560>
 109e9dc:	call   1042840 <myl_core_assert_fail>
 109e9e1:	mov    %r15,%rdi
 109e9e4:	call   103c740 <myl_core_drop_owned>
 109e9e9:	mov    0x1e8(%rsp),%rdi
 109e9f1:	call   103c740 <myl_core_drop_owned>
 109e9f6:	mov    0x120(%rsp),%rax
 109e9fe:	add    $0x368,%rsp
 109ea05:	pop    %rbx
 109ea06:	pop    %r12
 109ea08:	pop    %r13
 109ea0a:	pop    %r14
 109ea0c:	pop    %r15
 109ea0e:	pop    %rbp
 109ea0f:	ret
 109ea10:	lea    0x50a59(%rip),%rdi        # 10ef470 <core_durable_error.verbs+0x3e70>
 109ea17:	mov    0x128(%rsp),%rsi
 109ea1f:	call   103d4c0 <myl_core_trap>
 109ea24:	call   103c740 <myl_core_drop_owned>
 109ea29:	lea    0x4e130(%rip),%rdi        # 10ecb60 <core_durable_error.verbs+0x1560>
 109ea30:	call   1042840 <myl_core_assert_fail>
 109ea35:	mov    $0x10,%esi
 109ea3a:	mov    %rdi,%rbx
 109ea3d:	xor    %edi,%edi
 109ea3f:	call   103b980 <myl_core_list_new_slow>
 109ea44:	mov    %rbx,%rdi
 109ea47:	jmp    1099e26 <my.diagram_membership::compute_sub_block_attachments+0x46>
 109ea4c:	mov    %rsi,%rbx
 109ea4f:	cmp    %rbx,%rdx
 109ea52:	cmova  %rdx,%rbx
 109ea56:	lea    0x53293(%rip),%rdi        # 10f1cf0 <core_durable_error.verbs+0x66f0>
 109ea5d:	mov    %rbx,%rsi
 109ea60:	call   103d4c0 <myl_core_trap>
 109ea65:	mov    %rsi,%rbx
 109ea68:	lea    0x53251(%rip),%rdi        # 10f1cc0 <core_durable_error.verbs+0x66c0>
 109ea6f:	mov    %rbx,%rsi
 109ea72:	mov    %rcx,%rdx
 109ea75:	call   103d4c0 <myl_core_trap>
 109ea7a:	mov    $0x8,%esi
 109ea7f:	xor    %edi,%edi
 109ea81:	call   103b980 <myl_core_list_new_slow>
 109ea86:	mov    0xc0(%rsp),%rdx
 109ea8e:	mov    %rax,%rdi
 109ea91:	jmp    109b330 <my.diagram_membership::compute_sub_block_attachments+0x1550>
 109ea96:	call   103c740 <myl_core_drop_owned>
 109ea9b:	lea    0x4e0be(%rip),%rdi        # 10ecb60 <core_durable_error.verbs+0x1560>
 109eaa2:	call   1042840 <myl_core_assert_fail>
 109eaa7:	call   103c740 <myl_core_drop_owned>
 109eaac:	lea    0x4e0ad(%rip),%rdi        # 10ecb60 <core_durable_error.verbs+0x1560>
 109eab3:	call   1042840 <myl_core_assert_fail>
 109eab8:	lea    0x50ad1(%rip),%rdi        # 10ef590 <core_durable_error.verbs+0x3f90>
 109eabf:	mov    0xf8(%rsp),%rsi
 109eac7:	mov    0xc0(%rsp),%rdx
 109eacf:	call   103d4c0 <myl_core_trap>
 109ead4:	lea    0x50ae5(%rip),%rdi        # 10ef5c0 <core_durable_error.verbs+0x3fc0>
 109eadb:	mov    0xb0(%rsp),%rsi
 109eae3:	mov    %r13,%rdx
 109eae6:	call   103d4c0 <myl_core_trap>
 109eaeb:	mov    %rsi,%rax
 109eaee:	sar    $0x3f,%rax
 109eaf2:	and    %rdx,%rax
 109eaf5:	sub    %rax,%rsi
 109eaf8:	lea    0x50af1(%rip),%rdi        # 10ef5f0 <core_durable_error.verbs+0x3ff0>
 109eaff:	call   103d4c0 <myl_core_trap>
 109eb04:	mov    %rbp,%rdi
 109eb07:	call   103c740 <myl_core_drop_owned>
 109eb0c:	lea    0x5092d(%rip),%rdi        # 10ef440 <core_durable_error.verbs+0x3e40>
 109eb13:	xor    %esi,%esi
 109eb15:	xor    %edx,%edx
 109eb17:	call   103d4c0 <myl_core_trap>
 109eb1c:	mov    %rsi,%rbx
 109eb1f:	lea    0x5316a(%rip),%rdi        # 10f1c90 <core_durable_error.verbs+0x6690>
 109eb26:	mov    %rbx,%rsi
 109eb29:	mov    %rax,%rdx
 109eb2c:	call   103d4c0 <myl_core_trap>
 109eb31:	lea    0x531e8(%rip),%rdi        # 10f1d20 <core_durable_error.verbs+0x6720>
 109eb38:	movabs $0x7fffffffffffffff,%rsi
 109eb42:	mov    $0x1,%edx
 109eb47:	call   103d4c0 <myl_core_trap>
 109eb4c:	lea    0x509dd(%rip),%rdi        # 10ef530 <core_durable_error.verbs+0x3f30>
 109eb53:	mov    $0x1,%edx
 109eb58:	mov    %rax,%rsi
 109eb5b:	call   103d4c0 <myl_core_trap>
 109eb60:	lea    0x50939(%rip),%rdi        # 10ef4a0 <core_durable_error.verbs+0x3ea0>
 109eb67:	call   103d4c0 <myl_core_trap>
 109eb6c:	mov    %rsi,%rax
 109eb6f:	sar    $0x3f,%rax
 109eb73:	and    %rdx,%rax
 109eb76:	sub    %rax,%rsi
 109eb79:	lea    0x50980(%rip),%rdi        # 10ef500 <core_durable_error.verbs+0x3f00>
 109eb80:	call   103d4c0 <myl_core_trap>
 109eb85:	lea    0x50944(%rip),%rdi        # 10ef4d0 <core_durable_error.verbs+0x3ed0>
 109eb8c:	mov    %rax,%rsi
 109eb8f:	call   103d4c0 <myl_core_trap>
 109eb94:	mov    %rbp,%rdi
 109eb97:	call   103c740 <myl_core_drop_owned>
 109eb9c:	lea    0x4dfbd(%rip),%rdi        # 10ecb60 <core_durable_error.verbs+0x1560>
 109eba3:	call   1042840 <myl_core_assert_fail>
 109eba8:	lea    0x509b1(%rip),%rdi        # 10ef560 <core_durable_error.verbs+0x3f60>
 109ebaf:	call   103d4c0 <myl_core_trap>
 109ebb4:	lea    0x50a65(%rip),%rdi        # 10ef620 <core_durable_error.verbs+0x4020>
 109ebbb:	call   103d4c0 <myl_core_trap>

Disassembly of section .plt:
