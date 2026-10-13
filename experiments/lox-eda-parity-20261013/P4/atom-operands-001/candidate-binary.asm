
.tmp/lox-eda-parity/P4/atom-operands-001/candidate/lox:     file format elf64-x86-64


Disassembly of section .text:

000000000106bb70 <my.interpreter::binary>:
 106bb70:	55                   	push   %rbp
 106bb71:	41 57                	push   %r15
 106bb73:	41 56                	push   %r14
 106bb75:	41 55                	push   %r13
 106bb77:	41 54                	push   %r12
 106bb79:	53                   	push   %rbx
 106bb7a:	48 81 ec b8 04 00 00 	sub    $0x4b8,%rsp
 106bb81:	4d 89 cf             	mov    %r9,%r15
 106bb84:	4d 89 c4             	mov    %r8,%r12
 106bb87:	49 89 ce             	mov    %rcx,%r14
 106bb8a:	49 89 d5             	mov    %rdx,%r13
 106bb8d:	48 89 f5             	mov    %rsi,%rbp
 106bb90:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 106bb95:	48 8b 84 24 10 05 00 	mov    0x510(%rsp),%rax
 106bb9c:	00 
 106bb9d:	48 8b 18             	mov    (%rax),%rbx
 106bba0:	48 83 ec 08          	sub    $0x8,%rsp
 106bba4:	48 8d bc 24 f8 03 00 	lea    0x3f8(%rsp),%rdi
 106bbab:	00 
 106bbac:	53                   	push   %rbx
 106bbad:	e8 ce 3b 00 00       	call   106f780 <my.interpreter::try_push_atom>
 106bbb2:	48 83 c4 10          	add    $0x10,%rsp
 106bbb6:	f6 84 24 f0 03 00 00 	testb  $0x1,0x3f0(%rsp)
 106bbbd:	01 
 106bbbe:	4c 89 64 24 28       	mov    %r12,0x28(%rsp)
 106bbc3:	0f b6 84 24 00 05 00 	movzbl 0x500(%rsp),%eax
 106bbca:	00 
 106bbcb:	74 23                	je     106bbf0 <my.interpreter::binary+0x80>
 106bbcd:	48 89 04 24          	mov    %rax,(%rsp)
 106bbd1:	4d 89 fc             	mov    %r15,%r12
 106bbd4:	48 8b 84 24 f8 04 00 	mov    0x4f8(%rsp),%rax
 106bbdb:	00 
 106bbdc:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 106bbe1:	48 8b 84 24 08 05 00 	mov    0x508(%rsp),%rax
 106bbe8:	00 
 106bbe9:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 106bbee:	eb 78                	jmp    106bc68 <my.interpreter::binary+0xf8>
 106bbf0:	0f b6 c0             	movzbl %al,%eax
 106bbf3:	48 8d bc 24 48 01 00 	lea    0x148(%rsp),%rdi
 106bbfa:	00 
 106bbfb:	48 89 ee             	mov    %rbp,%rsi
 106bbfe:	4c 89 ea             	mov    %r13,%rdx
 106bc01:	4c 89 f1             	mov    %r14,%rcx
 106bc04:	4d 89 e0             	mov    %r12,%r8
 106bc07:	4d 89 fc             	mov    %r15,%r12
 106bc0a:	4d 89 f9             	mov    %r15,%r9
 106bc0d:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 106bc14:	53                   	push   %rbx
 106bc15:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 106bc1c:	50                   	push   %rax
 106bc1d:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 106bc24:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 106bc2b:	e8 a0 94 ff ff       	call   10650d0 <my.interpreter::evaluate>
 106bc30:	48 83 c4 30          	add    $0x30,%rsp
 106bc34:	48 8b 84 24 48 02 00 	mov    0x248(%rsp),%rax
 106bc3b:	00 
 106bc3c:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 106bc41:	48 8b 84 24 50 02 00 	mov    0x250(%rsp),%rax
 106bc48:	00 
 106bc49:	48 89 04 24          	mov    %rax,(%rsp)
 106bc4d:	48 8b 84 24 58 02 00 	mov    0x258(%rsp),%rax
 106bc54:	00 
 106bc55:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 106bc5a:	80 bc 24 48 01 00 00 	cmpb   $0x1,0x148(%rsp)
 106bc61:	01 
 106bc62:	0f 84 b1 03 00 00    	je     106c019 <my.interpreter::binary+0x4a9>
 106bc68:	48 8b 84 24 10 05 00 	mov    0x510(%rsp),%rax
 106bc6f:	00 
 106bc70:	48 8b 58 30          	mov    0x30(%rax),%rbx
 106bc74:	48 83 ec 08          	sub    $0x8,%rsp
 106bc78:	48 8d bc 24 30 03 00 	lea    0x330(%rsp),%rdi
 106bc7f:	00 
 106bc80:	48 89 ee             	mov    %rbp,%rsi
 106bc83:	4c 89 ea             	mov    %r13,%rdx
 106bc86:	4c 89 f1             	mov    %r14,%rcx
 106bc89:	4c 8b 7c 24 30       	mov    0x30(%rsp),%r15
 106bc8e:	4d 89 f8             	mov    %r15,%r8
 106bc91:	4d 89 e1             	mov    %r12,%r9
 106bc94:	53                   	push   %rbx
 106bc95:	e8 e6 3a 00 00       	call   106f780 <my.interpreter::try_push_atom>
 106bc9a:	48 83 c4 10          	add    $0x10,%rsp
 106bc9e:	f6 84 24 28 03 00 00 	testb  $0x1,0x328(%rsp)
 106bca5:	01 
 106bca6:	74 0c                	je     106bcb4 <my.interpreter::binary+0x144>
 106bca8:	4c 8b 7c 24 18       	mov    0x18(%rsp),%r15
 106bcad:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 106bcb2:	eb 60                	jmp    106bd14 <my.interpreter::binary+0x1a4>
 106bcb4:	0f b6 04 24          	movzbl (%rsp),%eax
 106bcb8:	48 8d 7c 24 30       	lea    0x30(%rsp),%rdi
 106bcbd:	48 89 ee             	mov    %rbp,%rsi
 106bcc0:	4c 89 ea             	mov    %r13,%rdx
 106bcc3:	4c 89 f1             	mov    %r14,%rcx
 106bcc6:	4d 89 f8             	mov    %r15,%r8
 106bcc9:	4d 89 e1             	mov    %r12,%r9
 106bccc:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 106bcd3:	53                   	push   %rbx
 106bcd4:	ff 74 24 28          	push   0x28(%rsp)
 106bcd8:	50                   	push   %rax
 106bcd9:	ff 74 24 40          	push   0x40(%rsp)
 106bcdd:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 106bce4:	e8 e7 93 ff ff       	call   10650d0 <my.interpreter::evaluate>
 106bce9:	48 83 c4 30          	add    $0x30,%rsp
 106bced:	4c 8b b4 24 30 01 00 	mov    0x130(%rsp),%r14
 106bcf4:	00 
 106bcf5:	48 8b 84 24 38 01 00 	mov    0x138(%rsp),%rax
 106bcfc:	00 
 106bcfd:	48 89 04 24          	mov    %rax,(%rsp)
 106bd01:	4c 8b bc 24 40 01 00 	mov    0x140(%rsp),%r15
 106bd08:	00 
 106bd09:	80 7c 24 30 01       	cmpb   $0x1,0x30(%rsp)
 106bd0e:	0f 84 5d 03 00 00    	je     106c071 <my.interpreter::binary+0x501>
 106bd14:	49 8b 84 24 80 00 00 	mov    0x80(%r12),%rax
 106bd1b:	00 
 106bd1c:	48 89 c6             	mov    %rax,%rsi
 106bd1f:	48 ff ce             	dec    %rsi
 106bd22:	40 0f 90 c7          	seto   %dil
 106bd26:	0f 80 0e 05 00 00    	jo     106c23a <my.interpreter::binary+0x6ca>
 106bd2c:	48 89 f2             	mov    %rsi,%rdx
 106bd2f:	48 ff ca             	dec    %rdx
 106bd32:	0f 80 16 05 00 00    	jo     106c24e <my.interpreter::binary+0x6de>
 106bd38:	4d 8b 54 24 78       	mov    0x78(%r12),%r10
 106bd3d:	49 8b 4a 08          	mov    0x8(%r10),%rcx
 106bd41:	48 39 ca             	cmp    %rcx,%rdx
 106bd44:	0f 83 0c 04 00 00    	jae    106c156 <my.interpreter::binary+0x5e6>
 106bd4a:	49 89 d0             	mov    %rdx,%r8
 106bd4d:	49 c1 e0 04          	shl    $0x4,%r8
 106bd51:	47 0f b6 4c 02 20    	movzbl 0x20(%r10,%r8,1),%r9d
 106bd57:	4b 8b 54 02 28       	mov    0x28(%r10,%r8,1),%rdx
 106bd5c:	49 89 f3             	mov    %rsi,%r11
 106bd5f:	48 39 ce             	cmp    %rcx,%rsi
 106bd62:	0f 83 16 04 00 00    	jae    106c17e <my.interpreter::binary+0x60e>
 106bd68:	49 83 c2 20          	add    $0x20,%r10
 106bd6c:	49 c1 e3 04          	shl    $0x4,%r11
 106bd70:	47 0f b6 04 1a       	movzbl (%r10,%r11,1),%r8d
 106bd75:	4b 8b 4c 1a 08       	mov    0x8(%r10,%r11,1),%rcx
 106bd7a:	4c 8b 94 24 10 05 00 	mov    0x510(%rsp),%r10
 106bd81:	00 
 106bd82:	4d 8b 52 08          	mov    0x8(%r10),%r10
 106bd86:	41 80 fa 0c          	cmp    $0xc,%r10b
 106bd8a:	74 36                	je     106bdc2 <my.interpreter::binary+0x252>
 106bd8c:	45 0f b6 da          	movzbl %r10b,%r11d
 106bd90:	41 83 fb 0e          	cmp    $0xe,%r11d
 106bd94:	75 58                	jne    106bdee <my.interpreter::binary+0x27e>
 106bd96:	41 80 f9 02          	cmp    $0x2,%r9b
 106bd9a:	0f 84 d5 00 00 00    	je     106be75 <my.interpreter::binary+0x305>
 106bda0:	45 0f b6 c9          	movzbl %r9b,%r9d
 106bda4:	41 83 f9 01          	cmp    $0x1,%r9d
 106bda8:	0f 84 ad 00 00 00    	je     106be5b <my.interpreter::binary+0x2eb>
 106bdae:	45 85 c9             	test   %r9d,%r9d
 106bdb1:	0f 85 e1 00 00 00    	jne    106be98 <my.interpreter::binary+0x328>
 106bdb7:	45 84 c0             	test   %r8b,%r8b
 106bdba:	0f 94 c1             	sete   %cl
 106bdbd:	e9 1f 01 00 00       	jmp    106bee1 <my.interpreter::binary+0x371>
 106bdc2:	41 80 f9 02          	cmp    $0x2,%r9b
 106bdc6:	0f 84 df 00 00 00    	je     106beab <my.interpreter::binary+0x33b>
 106bdcc:	45 0f b6 c9          	movzbl %r9b,%r9d
 106bdd0:	41 83 f9 01          	cmp    $0x1,%r9d
 106bdd4:	0f 84 8e 00 00 00    	je     106be68 <my.interpreter::binary+0x2f8>
 106bdda:	45 85 c9             	test   %r9d,%r9d
 106bddd:	0f 85 eb 00 00 00    	jne    106bece <my.interpreter::binary+0x35e>
 106bde3:	45 84 c0             	test   %r8b,%r8b
 106bde6:	0f 94 c1             	sete   %cl
 106bde9:	e9 f1 00 00 00       	jmp    106bedf <my.interpreter::binary+0x36f>
 106bdee:	44 89 cb             	mov    %r9d,%ebx
 106bdf1:	80 f3 02             	xor    $0x2,%bl
 106bdf4:	c4 e1 f9 6e c2       	vmovq  %rdx,%xmm0
 106bdf9:	44 89 c5             	mov    %r8d,%ebp
 106bdfc:	40 80 f5 02          	xor    $0x2,%bpl
 106be00:	c4 e1 f9 6e c9       	vmovq  %rcx,%xmm1
 106be05:	40 08 dd             	or     %bl,%bpl
 106be08:	0f 94 c3             	sete   %bl
 106be0b:	41 83 fb 07          	cmp    $0x7,%r11d
 106be0f:	75 0e                	jne    106be1f <my.interpreter::binary+0x2af>
 106be11:	84 db                	test   %bl,%bl
 106be13:	0f 84 5d 01 00 00    	je     106bf76 <my.interpreter::binary+0x406>
 106be19:	c5 fb 58 c1          	vaddsd %xmm1,%xmm0,%xmm0
 106be1d:	eb 22                	jmp    106be41 <my.interpreter::binary+0x2d1>
 106be1f:	84 db                	test   %bl,%bl
 106be21:	0f 84 a8 02 00 00    	je     106c0cf <my.interpreter::binary+0x55f>
 106be27:	41 80 fa 26          	cmp    $0x26,%r10b
 106be2b:	77 10                	ja     106be3d <my.interpreter::binary+0x2cd>
 106be2d:	48 8d 0d 18 be f9 ff 	lea    -0x641e8(%rip),%rcx        # 1007c4c <core_number_pairs+0x9ec>
 106be34:	4a 63 14 99          	movslq (%rcx,%r11,4),%rdx
 106be38:	48 01 ca             	add    %rcx,%rdx
 106be3b:	ff e2                	jmp    *%rdx
 106be3d:	c5 fb 59 c1          	vmulsd %xmm1,%xmm0,%xmm0
 106be41:	c4 e1 f9 7e c1       	vmovq  %xmm0,%rcx
 106be46:	41 b8 02 00 00 00    	mov    $0x2,%r8d
 106be4c:	40 f6 c7 01          	test   $0x1,%dil
 106be50:	0f 84 a1 00 00 00    	je     106bef7 <my.interpreter::binary+0x387>
 106be56:	e9 aa 01 00 00       	jmp    106c005 <my.interpreter::binary+0x495>
 106be5b:	41 80 f8 01          	cmp    $0x1,%r8b
 106be5f:	75 33                	jne    106be94 <my.interpreter::binary+0x324>
 106be61:	31 d1                	xor    %edx,%ecx
 106be63:	80 f1 01             	xor    $0x1,%cl
 106be66:	eb 79                	jmp    106bee1 <my.interpreter::binary+0x371>
 106be68:	41 80 f8 01          	cmp    $0x1,%r8b
 106be6c:	75 5c                	jne    106beca <my.interpreter::binary+0x35a>
 106be6e:	31 d1                	xor    %edx,%ecx
 106be70:	80 f1 01             	xor    $0x1,%cl
 106be73:	eb 6a                	jmp    106bedf <my.interpreter::binary+0x36f>
 106be75:	41 80 f8 02          	cmp    $0x2,%r8b
 106be79:	75 19                	jne    106be94 <my.interpreter::binary+0x324>
 106be7b:	c4 e1 f9 6e c2       	vmovq  %rdx,%xmm0
 106be80:	c4 e1 f9 6e c9       	vmovq  %rcx,%xmm1
 106be85:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 106be8a:	c4 e1 f9 7e c1       	vmovq  %xmm0,%rcx
 106be8f:	83 e1 01             	and    $0x1,%ecx
 106be92:	eb 4d                	jmp    106bee1 <my.interpreter::binary+0x371>
 106be94:	31 c9                	xor    %ecx,%ecx
 106be96:	eb 49                	jmp    106bee1 <my.interpreter::binary+0x371>
 106be98:	41 80 f8 03          	cmp    $0x3,%r8b
 106be9c:	41 0f 94 c0          	sete   %r8b
 106bea0:	48 39 ca             	cmp    %rcx,%rdx
 106bea3:	0f 94 c1             	sete   %cl
 106bea6:	44 20 c1             	and    %r8b,%cl
 106bea9:	eb 36                	jmp    106bee1 <my.interpreter::binary+0x371>
 106beab:	41 80 f8 02          	cmp    $0x2,%r8b
 106beaf:	75 19                	jne    106beca <my.interpreter::binary+0x35a>
 106beb1:	c4 e1 f9 6e c2       	vmovq  %rdx,%xmm0
 106beb6:	c4 e1 f9 6e c9       	vmovq  %rcx,%xmm1
 106bebb:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 106bec0:	c4 e1 f9 7e c1       	vmovq  %xmm0,%rcx
 106bec5:	83 e1 01             	and    $0x1,%ecx
 106bec8:	eb 15                	jmp    106bedf <my.interpreter::binary+0x36f>
 106beca:	31 c9                	xor    %ecx,%ecx
 106becc:	eb 11                	jmp    106bedf <my.interpreter::binary+0x36f>
 106bece:	41 80 f8 03          	cmp    $0x3,%r8b
 106bed2:	41 0f 94 c0          	sete   %r8b
 106bed6:	48 39 ca             	cmp    %rcx,%rdx
 106bed9:	0f 94 c1             	sete   %cl
 106bedc:	44 20 c1             	and    %r8b,%cl
 106bedf:	f6 d1                	not    %cl
 106bee1:	0f b6 c9             	movzbl %cl,%ecx
 106bee4:	83 e1 01             	and    $0x1,%ecx
 106bee7:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 106beed:	40 f6 c7 01          	test   $0x1,%dil
 106bef1:	0f 85 0e 01 00 00    	jne    106c005 <my.interpreter::binary+0x495>
 106bef7:	49 89 b4 24 80 00 00 	mov    %rsi,0x80(%r12)
 106befe:	00 
 106beff:	49 8b 7c 24 78       	mov    0x78(%r12),%rdi
 106bf04:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 106bf08:	48 39 d6             	cmp    %rdx,%rsi
 106bf0b:	0f 83 92 02 00 00    	jae    106c1a3 <my.interpreter::binary+0x633>
 106bf11:	48 89 f0             	mov    %rsi,%rax
 106bf14:	48 ff c8             	dec    %rax
 106bf17:	0f 80 42 03 00 00    	jo     106c25f <my.interpreter::binary+0x6ef>
 106bf1d:	48 39 d0             	cmp    %rdx,%rax
 106bf20:	0f 83 9f 02 00 00    	jae    106c1c5 <my.interpreter::binary+0x655>
 106bf26:	48 89 c6             	mov    %rax,%rsi
 106bf29:	48 c1 e6 04          	shl    $0x4,%rsi
 106bf2d:	4c 89 44 37 20       	mov    %r8,0x20(%rdi,%rsi,1)
 106bf32:	48 89 4c 37 28       	mov    %rcx,0x28(%rdi,%rsi,1)
 106bf37:	49 89 7c 24 78       	mov    %rdi,0x78(%r12)
 106bf3c:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 106bf41:	48 c7 01 00 00 00 00 	movq   $0x0,(%rcx)
 106bf48:	4c 89 b1 00 01 00 00 	mov    %r14,0x100(%rcx)
 106bf4f:	0f b6 04 24          	movzbl (%rsp),%eax
 106bf53:	48 89 81 08 01 00 00 	mov    %rax,0x108(%rcx)
 106bf5a:	4c 89 b9 10 01 00 00 	mov    %r15,0x110(%rcx)
 106bf61:	48 89 c8             	mov    %rcx,%rax
 106bf64:	48 81 c4 b8 04 00 00 	add    $0x4b8,%rsp
 106bf6b:	5b                   	pop    %rbx
 106bf6c:	41 5c                	pop    %r12
 106bf6e:	41 5d                	pop    %r13
 106bf70:	41 5e                	pop    %r14
 106bf72:	41 5f                	pop    %r15
 106bf74:	5d                   	pop    %rbp
 106bf75:	c3                   	ret
 106bf76:	41 80 f9 03          	cmp    $0x3,%r9b
 106bf7a:	0f 85 2e 01 00 00    	jne    106c0ae <my.interpreter::binary+0x53e>
 106bf80:	49 8b 34 24          	mov    (%r12),%rsi
 106bf84:	48 8b 46 08          	mov    0x8(%rsi),%rax
 106bf88:	48 89 d7             	mov    %rdx,%rdi
 106bf8b:	48 39 c2             	cmp    %rax,%rdx
 106bf8e:	0f 83 56 02 00 00    	jae    106c1ea <my.interpreter::binary+0x67a>
 106bf94:	48 6b ff 38          	imul   $0x38,%rdi,%rdi
 106bf98:	83 7c 3e 20 01       	cmpl   $0x1,0x20(%rsi,%rdi,1)
 106bf9d:	0f 85 0b 01 00 00    	jne    106c0ae <my.interpreter::binary+0x53e>
 106bfa3:	41 80 f8 03          	cmp    $0x3,%r8b
 106bfa7:	0f 85 01 01 00 00    	jne    106c0ae <my.interpreter::binary+0x53e>
 106bfad:	48 89 cf             	mov    %rcx,%rdi
 106bfb0:	48 39 c1             	cmp    %rax,%rcx
 106bfb3:	0f 83 59 02 00 00    	jae    106c212 <my.interpreter::binary+0x6a2>
 106bfb9:	48 83 c6 20          	add    $0x20,%rsi
 106bfbd:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 106bfc1:	83 3c 06 01          	cmpl   $0x1,(%rsi,%rax,1)
 106bfc5:	0f 85 e3 00 00 00    	jne    106c0ae <my.interpreter::binary+0x53e>
 106bfcb:	48 8d bc 24 60 02 00 	lea    0x260(%rsp),%rdi
 106bfd2:	00 
 106bfd3:	4c 89 e6             	mov    %r12,%rsi
 106bfd6:	e8 65 1c 00 00       	call   106dc40 <my.lox_strings::concat>
 106bfdb:	48 8b 8c 24 60 02 00 	mov    0x260(%rsp),%rcx
 106bfe2:	00 
 106bfe3:	49 8b 84 24 80 00 00 	mov    0x80(%r12),%rax
 106bfea:	00 
 106bfeb:	48 89 c6             	mov    %rax,%rsi
 106bfee:	48 ff ce             	dec    %rsi
 106bff1:	40 0f 90 c7          	seto   %dil
 106bff5:	41 b8 03 00 00 00    	mov    $0x3,%r8d
 106bffb:	40 f6 c7 01          	test   $0x1,%dil
 106bfff:	0f 84 f2 fe ff ff    	je     106bef7 <my.interpreter::binary+0x387>
 106c005:	48 8d 3d 64 9c 01 00 	lea    0x19c64(%rip),%rdi        # 1085c70 <core_durable_error.verbs+0x5fa0>
 106c00c:	ba 01 00 00 00       	mov    $0x1,%edx
 106c011:	48 89 c6             	mov    %rax,%rsi
 106c014:	e8 e7 87 fb ff       	call   1024800 <myl_core_trap>
 106c019:	0f b6 04 24          	movzbl (%rsp),%eax
 106c01d:	c5 f8 10 84 24 50 01 	vmovups 0x150(%rsp),%xmm0
 106c024:	00 00 
 106c026:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 106c02b:	48 8d 3d ee 9a 01 00 	lea    0x19aee(%rip),%rdi        # 1085b20 <core_durable_error.verbs+0x5e50>
 106c032:	e8 c9 ab fe ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 106c037:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 106c03c:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 106c043:	c5 f9 28 04 24       	vmovapd (%rsp),%xmm0
 106c048:	c5 f9 11 41 08       	vmovupd %xmm0,0x8(%rcx)
 106c04d:	48 8b 54 24 20       	mov    0x20(%rsp),%rdx
 106c052:	48 89 91 00 01 00 00 	mov    %rdx,0x100(%rcx)
 106c059:	48 89 81 08 01 00 00 	mov    %rax,0x108(%rcx)
 106c060:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 106c065:	48 89 81 10 01 00 00 	mov    %rax,0x110(%rcx)
 106c06c:	e9 f0 fe ff ff       	jmp    106bf61 <my.interpreter::binary+0x3f1>
 106c071:	0f b6 04 24          	movzbl (%rsp),%eax
 106c075:	c5 f8 10 44 24 38    	vmovups 0x38(%rsp),%xmm0
 106c07b:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 106c080:	48 8d 3d c9 9a 01 00 	lea    0x19ac9(%rip),%rdi        # 1085b50 <core_durable_error.verbs+0x5e80>
 106c087:	e8 74 ab fe ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 106c08c:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 106c091:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 106c098:	c5 f9 28 04 24       	vmovapd (%rsp),%xmm0
 106c09d:	c5 f9 11 41 08       	vmovupd %xmm0,0x8(%rcx)
 106c0a2:	4c 89 b1 00 01 00 00 	mov    %r14,0x100(%rcx)
 106c0a9:	e9 a5 fe ff ff       	jmp    106bf53 <my.interpreter::binary+0x3e3>
 106c0ae:	48 8b 84 24 10 05 00 	mov    0x510(%rsp),%rax
 106c0b5:	00 
 106c0b6:	48 8b 58 20          	mov    0x20(%rax),%rbx
 106c0ba:	48 8d 3d bf 61 fa ff 	lea    -0x59e41(%rip),%rdi        # 1012280 <core_number_pairs+0xb020>
 106c0c1:	e8 3a 82 fb ff       	call   1024300 <myl_core_owned_octets_copy>
 106c0c6:	48 8d 3d b3 9a 01 00 	lea    0x19ab3(%rip),%rdi        # 1085b80 <core_durable_error.verbs+0x5eb0>
 106c0cd:	eb 1f                	jmp    106c0ee <my.interpreter::binary+0x57e>
 106c0cf:	48 8b 84 24 10 05 00 	mov    0x510(%rsp),%rax
 106c0d6:	00 
 106c0d7:	48 8b 58 20          	mov    0x20(%rax),%rbx
 106c0db:	48 8d 3d 5e 61 fa ff 	lea    -0x59ea2(%rip),%rdi        # 1012240 <core_number_pairs+0xafe0>
 106c0e2:	e8 19 82 fb ff       	call   1024300 <myl_core_owned_octets_copy>
 106c0e7:	48 8d 3d c2 9a 01 00 	lea    0x19ac2(%rip),%rdi        # 1085bb0 <core_durable_error.verbs+0x5ee0>
 106c0ee:	e8 cd aa fe ff       	call   1056bc0 <myl_core_err_trace_origin_preserve_most>
 106c0f3:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 106c0f8:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 106c0ff:	48 89 41 08          	mov    %rax,0x8(%rcx)
 106c103:	48 89 59 10          	mov    %rbx,0x10(%rcx)
 106c107:	e9 3c fe ff ff       	jmp    106bf48 <my.interpreter::binary+0x3d8>
 106c10c:	31 c9                	xor    %ecx,%ecx
 106c10e:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 106c112:	0f 97 c1             	seta   %cl
 106c115:	e9 cd fd ff ff       	jmp    106bee7 <my.interpreter::binary+0x377>
 106c11a:	c5 fb 5e c1          	vdivsd %xmm1,%xmm0,%xmm0
 106c11e:	e9 1e fd ff ff       	jmp    106be41 <my.interpreter::binary+0x2d1>
 106c123:	31 c9                	xor    %ecx,%ecx
 106c125:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 106c129:	0f 93 c1             	setae  %cl
 106c12c:	e9 b6 fd ff ff       	jmp    106bee7 <my.interpreter::binary+0x377>
 106c131:	31 c9                	xor    %ecx,%ecx
 106c133:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
 106c137:	0f 97 c1             	seta   %cl
 106c13a:	e9 a8 fd ff ff       	jmp    106bee7 <my.interpreter::binary+0x377>
 106c13f:	31 c9                	xor    %ecx,%ecx
 106c141:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
 106c145:	0f 93 c1             	setae  %cl
 106c148:	e9 9a fd ff ff       	jmp    106bee7 <my.interpreter::binary+0x377>
 106c14d:	c5 fb 5c c1          	vsubsd %xmm1,%xmm0,%xmm0
 106c151:	e9 eb fc ff ff       	jmp    106be41 <my.interpreter::binary+0x2d1>
 106c156:	49 89 d0             	mov    %rdx,%r8
 106c159:	49 c1 f8 3f          	sar    $0x3f,%r8
 106c15d:	49 21 c8             	and    %rcx,%r8
 106c160:	49 01 d0             	add    %rdx,%r8
 106c163:	49 39 c8             	cmp    %rcx,%r8
 106c166:	0f 82 e1 fb ff ff    	jb     106bd4d <my.interpreter::binary+0x1dd>
 106c16c:	48 8d 3d cd 9a 01 00 	lea    0x19acd(%rip),%rdi        # 1085c40 <core_durable_error.verbs+0x5f70>
 106c173:	48 89 d6             	mov    %rdx,%rsi
 106c176:	48 89 ca             	mov    %rcx,%rdx
 106c179:	e8 82 86 fb ff       	call   1024800 <myl_core_trap>
 106c17e:	49 89 f3             	mov    %rsi,%r11
 106c181:	49 c1 fb 3f          	sar    $0x3f,%r11
 106c185:	49 21 cb             	and    %rcx,%r11
 106c188:	49 01 f3             	add    %rsi,%r11
 106c18b:	49 39 cb             	cmp    %rcx,%r11
 106c18e:	0f 82 d4 fb ff ff    	jb     106bd68 <my.interpreter::binary+0x1f8>
 106c194:	48 8d 3d 35 9b 01 00 	lea    0x19b35(%rip),%rdi        # 1085cd0 <core_durable_error.verbs+0x6000>
 106c19b:	48 89 ca             	mov    %rcx,%rdx
 106c19e:	e8 5d 86 fb ff       	call   1024800 <myl_core_trap>
 106c1a3:	48 89 f0             	mov    %rsi,%rax
 106c1a6:	48 c1 f8 3f          	sar    $0x3f,%rax
 106c1aa:	48 21 d0             	and    %rdx,%rax
 106c1ad:	48 01 f0             	add    %rsi,%rax
 106c1b0:	48 39 d0             	cmp    %rdx,%rax
 106c1b3:	0f 82 58 fd ff ff    	jb     106bf11 <my.interpreter::binary+0x3a1>
 106c1b9:	48 8d 3d e0 9a 01 00 	lea    0x19ae0(%rip),%rdi        # 1085ca0 <core_durable_error.verbs+0x5fd0>
 106c1c0:	e8 3b 86 fb ff       	call   1024800 <myl_core_trap>
 106c1c5:	48 89 c6             	mov    %rax,%rsi
 106c1c8:	48 c1 fe 3f          	sar    $0x3f,%rsi
 106c1cc:	48 21 d6             	and    %rdx,%rsi
 106c1cf:	48 01 c6             	add    %rax,%rsi
 106c1d2:	48 39 d6             	cmp    %rdx,%rsi
 106c1d5:	0f 82 4e fd ff ff    	jb     106bf29 <my.interpreter::binary+0x3b9>
 106c1db:	48 8d 3d 4e 9b 01 00 	lea    0x19b4e(%rip),%rdi        # 1085d30 <core_durable_error.verbs+0x6060>
 106c1e2:	48 89 c6             	mov    %rax,%rsi
 106c1e5:	e8 16 86 fb ff       	call   1024800 <myl_core_trap>
 106c1ea:	48 89 d7             	mov    %rdx,%rdi
 106c1ed:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106c1f1:	48 21 c7             	and    %rax,%rdi
 106c1f4:	48 01 d7             	add    %rdx,%rdi
 106c1f7:	48 39 c7             	cmp    %rax,%rdi
 106c1fa:	0f 82 94 fd ff ff    	jb     106bf94 <my.interpreter::binary+0x424>
 106c200:	48 8d 3d 39 b8 01 00 	lea    0x1b839(%rip),%rdi        # 1087a40 <core_durable_error.verbs+0x7d70>
 106c207:	48 89 d6             	mov    %rdx,%rsi
 106c20a:	48 89 c2             	mov    %rax,%rdx
 106c20d:	e8 ee 85 fb ff       	call   1024800 <myl_core_trap>
 106c212:	48 89 cf             	mov    %rcx,%rdi
 106c215:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106c219:	48 21 c7             	and    %rax,%rdi
 106c21c:	48 01 cf             	add    %rcx,%rdi
 106c21f:	48 39 c7             	cmp    %rax,%rdi
 106c222:	0f 82 91 fd ff ff    	jb     106bfb9 <my.interpreter::binary+0x449>
 106c228:	48 8d 3d 11 b8 01 00 	lea    0x1b811(%rip),%rdi        # 1087a40 <core_durable_error.verbs+0x7d70>
 106c22f:	48 89 ce             	mov    %rcx,%rsi
 106c232:	48 89 c2             	mov    %rax,%rdx
 106c235:	e8 c6 85 fb ff       	call   1024800 <myl_core_trap>
 106c23a:	48 8d 3d 9f 99 01 00 	lea    0x1999f(%rip),%rdi        # 1085be0 <core_durable_error.verbs+0x5f10>
 106c241:	ba 01 00 00 00       	mov    $0x1,%edx
 106c246:	48 89 c6             	mov    %rax,%rsi
 106c249:	e8 b2 85 fb ff       	call   1024800 <myl_core_trap>
 106c24e:	48 8d 3d bb 99 01 00 	lea    0x199bb(%rip),%rdi        # 1085c10 <core_durable_error.verbs+0x5f40>
 106c255:	ba 01 00 00 00       	mov    $0x1,%edx
 106c25a:	e8 a1 85 fb ff       	call   1024800 <myl_core_trap>
 106c25f:	48 8d 3d 9a 9a 01 00 	lea    0x19a9a(%rip),%rdi        # 1085d00 <core_durable_error.verbs+0x6030>
 106c266:	ba 01 00 00 00       	mov    $0x1,%edx
 106c26b:	e8 90 85 fb ff       	call   1024800 <myl_core_trap>

Disassembly of section .plt:
