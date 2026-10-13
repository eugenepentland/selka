
.tmp/lox-eda-parity/P4/compact-sret-002/candidate/lox:     file format elf64-x86-64


Disassembly of section .text:

0000000001064c90 <my.interpreter::evaluate>:
 1064c90:	55                   	push   %rbp
 1064c91:	41 57                	push   %r15
 1064c93:	41 56                	push   %r14
 1064c95:	41 55                	push   %r13
 1064c97:	41 54                	push   %r12
 1064c99:	53                   	push   %rbx
 1064c9a:	48 81 ec e8 01 00 00 	sub    $0x1e8,%rsp
 1064ca1:	48 89 cb             	mov    %rcx,%rbx
 1064ca4:	49 89 d2             	mov    %rdx,%r10
 1064ca7:	49 89 f7             	mov    %rsi,%r15
 1064caa:	48 89 fd             	mov    %rdi,%rbp
 1064cad:	48 8b b4 24 40 02 00 	mov    0x240(%rsp),%rsi
 1064cb4:	00 
 1064cb5:	49 8b 57 08          	mov    0x8(%r15),%rdx
 1064cb9:	48 39 d6             	cmp    %rdx,%rsi
 1064cbc:	0f 83 c1 22 00 00    	jae    1066f83 <my.interpreter::evaluate+0x22f3>
 1064cc2:	48 89 f0             	mov    %rsi,%rax
 1064cc5:	4c 8b b4 24 38 02 00 	mov    0x238(%rsp),%r14
 1064ccc:	00 
 1064ccd:	4c 8b 9c 24 28 02 00 	mov    0x228(%rsp),%r11
 1064cd4:	00 
 1064cd5:	48 6b c8 70          	imul   $0x70,%rax,%rcx
 1064cd9:	49 8d 04 0f          	lea    (%r15,%rcx,1),%rax
 1064cdd:	48 83 c0 20          	add    $0x20,%rax
 1064ce1:	41 8b 4c 0f 20       	mov    0x20(%r15,%rcx,1),%ecx
 1064ce6:	48 83 f9 0a          	cmp    $0xa,%rcx
 1064cea:	0f 87 59 0b 00 00    	ja     1065849 <my.interpreter::evaluate+0xbb9>
 1064cf0:	4c 89 7c 24 10       	mov    %r15,0x10(%rsp)
 1064cf5:	4c 8b a4 24 48 02 00 	mov    0x248(%rsp),%r12
 1064cfc:	00 
 1064cfd:	4c 8b bc 24 20 02 00 	mov    0x220(%rsp),%r15
 1064d04:	00 
 1064d05:	48 8d 15 90 29 fa ff 	lea    -0x5d670(%rip),%rdx        # 100769c <core_number_pairs+0x41c>
 1064d0c:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 1064d10:	48 01 d1             	add    %rdx,%rcx
 1064d13:	4c 89 4c 24 40       	mov    %r9,0x40(%rsp)
 1064d18:	4c 89 44 24 28       	mov    %r8,0x28(%rsp)
 1064d1d:	ff e1                	jmp    *%rcx
 1064d1f:	48 8b 48 20          	mov    0x20(%rax),%rcx
 1064d23:	48 89 4c 24 38       	mov    %rcx,0x38(%rsp)
 1064d28:	48 89 d9             	mov    %rbx,%rcx
 1064d2b:	4c 89 e3             	mov    %r12,%rbx
 1064d2e:	4c 8b 60 30          	mov    0x30(%rax),%r12
 1064d32:	4d 89 fd             	mov    %r15,%r13
 1064d35:	4c 8b 78 40          	mov    0x40(%rax),%r15
 1064d39:	48 8b 50 48          	mov    0x48(%rax),%rdx
 1064d3d:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 1064d42:	4c 89 d2             	mov    %r10,%rdx
 1064d45:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 1064d4c:	00 00 
 1064d4e:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1064d53:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1064d58:	53                   	push   %rbx
 1064d59:	ff 70 38             	push   0x38(%rax)
 1064d5c:	41 56                	push   %r14
 1064d5e:	41 52                	push   %r10
 1064d60:	41 53                	push   %r11
 1064d62:	41 55                	push   %r13
 1064d64:	e8 27 ff ff ff       	call   1064c90 <my.interpreter::evaluate>
 1064d69:	48 83 c4 30          	add    $0x30,%rsp
 1064d6d:	4c 8b 74 24 78       	mov    0x78(%rsp),%r14
 1064d72:	44 0f b6 ac 24 80 00 	movzbl 0x80(%rsp),%r13d
 1064d79:	00 00 
 1064d7b:	4c 8b 84 24 88 00 00 	mov    0x88(%rsp),%r8
 1064d82:	00 
 1064d83:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 1064d88:	0f 84 e4 1a 00 00    	je     1066872 <my.interpreter::evaluate+0x1be2>
 1064d8e:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 1064d92:	4c 89 44 24 10       	mov    %r8,0x10(%rsp)
 1064d97:	0f 84 1d 12 00 00    	je     1065fba <my.interpreter::evaluate+0x132a>
 1064d9d:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1064da2:	48 8b b7 a8 00 00 00 	mov    0xa8(%rdi),%rsi
 1064da9:	4d 85 ff             	test   %r15,%r15
 1064dac:	0f 8e e4 0d 00 00    	jle    1065b96 <my.interpreter::evaluate+0xf06>
 1064db2:	48 8b 07             	mov    (%rdi),%rax
 1064db5:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1064db9:	48 83 c0 20          	add    $0x20,%rax
 1064dbd:	0f 1f 00             	nopl   (%rax)
 1064dc0:	48 39 d6             	cmp    %rdx,%rsi
 1064dc3:	73 22                	jae    1064de7 <my.interpreter::evaluate+0x157>
 1064dc5:	48 89 f1             	mov    %rsi,%rcx
 1064dc8:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1064dcc:	83 3c 08 09          	cmpl   $0x9,(%rax,%rcx,1)
 1064dd0:	0f 85 4b 27 00 00    	jne    1067521 <my.interpreter::evaluate+0x2891>
 1064dd6:	48 01 c1             	add    %rax,%rcx
 1064dd9:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 1064ddd:	49 ff cf             	dec    %r15
 1064de0:	75 de                	jne    1064dc0 <my.interpreter::evaluate+0x130>
 1064de2:	e9 af 0d 00 00       	jmp    1065b96 <my.interpreter::evaluate+0xf06>
 1064de7:	48 89 f1             	mov    %rsi,%rcx
 1064dea:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1064dee:	48 21 d1             	and    %rdx,%rcx
 1064df1:	48 01 f1             	add    %rsi,%rcx
 1064df4:	48 39 d1             	cmp    %rdx,%rcx
 1064df7:	72 cf                	jb     1064dc8 <my.interpreter::evaluate+0x138>
 1064df9:	48 8d 3d d0 fd 01 00 	lea    0x1fdd0(%rip),%rdi        # 1084bd0 <core_durable_error.verbs+0x5cd0>
 1064e00:	e8 bb f6 fb ff       	call   10244c0 <myl_core_trap>
 1064e05:	4c 89 d2             	mov    %r10,%rdx
 1064e08:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 1064e0f:	00 00 
 1064e11:	48 8d bc 24 88 01 00 	lea    0x188(%rsp),%rdi
 1064e18:	00 
 1064e19:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1064e1e:	48 89 d9             	mov    %rbx,%rcx
 1064e21:	41 54                	push   %r12
 1064e23:	ff 70 08             	push   0x8(%rax)
 1064e26:	41 56                	push   %r14
 1064e28:	41 52                	push   %r10
 1064e2a:	41 53                	push   %r11
 1064e2c:	41 57                	push   %r15
 1064e2e:	e8 5d fe ff ff       	call   1064c90 <my.interpreter::evaluate>
 1064e33:	48 83 c4 30          	add    $0x30,%rsp
 1064e37:	0f b6 84 24 88 01 00 	movzbl 0x188(%rsp),%eax
 1064e3e:	00 
 1064e3f:	c5 f9 10 84 24 90 01 	vmovupd 0x190(%rsp),%xmm0
 1064e46:	00 00 
 1064e48:	48 8b 8c 24 a0 01 00 	mov    0x1a0(%rsp),%rcx
 1064e4f:	00 
 1064e50:	0f b6 94 24 a8 01 00 	movzbl 0x1a8(%rsp),%edx
 1064e57:	00 
 1064e58:	48 8b b4 24 b0 01 00 	mov    0x1b0(%rsp),%rsi
 1064e5f:	00 
 1064e60:	48 83 f8 01          	cmp    $0x1,%rax
 1064e64:	0f 84 83 19 00 00    	je     10667ed <my.interpreter::evaluate+0x1b5d>
 1064e6a:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1064e6e:	c5 f9 11 45 08       	vmovupd %xmm0,0x8(%rbp)
 1064e73:	48 89 4d 18          	mov    %rcx,0x18(%rbp)
 1064e77:	48 89 55 20          	mov    %rdx,0x20(%rbp)
 1064e7b:	48 89 75 28          	mov    %rsi,0x28(%rbp)
 1064e7f:	e9 ea 20 00 00       	jmp    1066f6e <my.interpreter::evaluate+0x22de>
 1064e84:	48 8b 78 30          	mov    0x30(%rax),%rdi
 1064e88:	49 8b 09             	mov    (%r9),%rcx
 1064e8b:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 1064e92:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1064e96:	48 85 ff             	test   %rdi,%rdi
 1064e99:	0f 8e 2a 0a 00 00    	jle    10658c9 <my.interpreter::evaluate+0xc39>
 1064e9f:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 1064ea3:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1064eaa:	0f 1f 84 00 00 00 00 
 1064eb1:	00 
 1064eb2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1064eb9:	1f 84 00 00 00 00 00 
 1064ec0:	48 39 d6             	cmp    %rdx,%rsi
 1064ec3:	73 23                	jae    1064ee8 <my.interpreter::evaluate+0x258>
 1064ec5:	49 89 f2             	mov    %rsi,%r10
 1064ec8:	49 6b f2 38          	imul   $0x38,%r10,%rsi
 1064ecc:	41 83 3c 30 09       	cmpl   $0x9,(%r8,%rsi,1)
 1064ed1:	0f 85 1a 26 00 00    	jne    10674f1 <my.interpreter::evaluate+0x2861>
 1064ed7:	4c 01 c6             	add    %r8,%rsi
 1064eda:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 1064ede:	48 ff cf             	dec    %rdi
 1064ee1:	75 dd                	jne    1064ec0 <my.interpreter::evaluate+0x230>
 1064ee3:	e9 e1 09 00 00       	jmp    10658c9 <my.interpreter::evaluate+0xc39>
 1064ee8:	49 89 f2             	mov    %rsi,%r10
 1064eeb:	49 c1 fa 3f          	sar    $0x3f,%r10
 1064eef:	49 21 d2             	and    %rdx,%r10
 1064ef2:	49 01 f2             	add    %rsi,%r10
 1064ef5:	49 39 d2             	cmp    %rdx,%r10
 1064ef8:	72 ce                	jb     1064ec8 <my.interpreter::evaluate+0x238>
 1064efa:	48 8d 3d cf fc 01 00 	lea    0x1fccf(%rip),%rdi        # 1084bd0 <core_durable_error.verbs+0x5cd0>
 1064f01:	e8 ba f5 fb ff       	call   10244c0 <myl_core_trap>
 1064f06:	48 89 2c 24          	mov    %rbp,(%rsp)
 1064f0a:	48 8b 48 28          	mov    0x28(%rax),%rcx
 1064f0e:	48 89 4c 24 58       	mov    %rcx,0x58(%rsp)
 1064f13:	48 8b 68 38          	mov    0x38(%rax),%rbp
 1064f17:	4c 89 d2             	mov    %r10,%rdx
 1064f1a:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 1064f21:	00 00 
 1064f23:	48 8d bc 24 08 01 00 	lea    0x108(%rsp),%rdi
 1064f2a:	00 
 1064f2b:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1064f30:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
 1064f35:	48 89 d9             	mov    %rbx,%rcx
 1064f38:	41 54                	push   %r12
 1064f3a:	ff 70 08             	push   0x8(%rax)
 1064f3d:	41 56                	push   %r14
 1064f3f:	41 52                	push   %r10
 1064f41:	41 53                	push   %r11
 1064f43:	41 57                	push   %r15
 1064f45:	e8 46 fd ff ff       	call   1064c90 <my.interpreter::evaluate>
 1064f4a:	48 83 c4 30          	add    $0x30,%rsp
 1064f4e:	4c 8b 94 24 20 01 00 	mov    0x120(%rsp),%r10
 1064f55:	00 
 1064f56:	0f b6 bc 24 28 01 00 	movzbl 0x128(%rsp),%edi
 1064f5d:	00 
 1064f5e:	4c 8b 9c 24 30 01 00 	mov    0x130(%rsp),%r11
 1064f65:	00 
 1064f66:	80 bc 24 08 01 00 00 	cmpb   $0x1,0x108(%rsp)
 1064f6d:	01 
 1064f6e:	0f 84 96 18 00 00    	je     106680a <my.interpreter::evaluate+0x1b7a>
 1064f74:	4c 8b 75 08          	mov    0x8(%rbp),%r14
 1064f78:	4d 85 f6             	test   %r14,%r14
 1064f7b:	0f 84 fd 0d 00 00    	je     1065d7e <my.interpreter::evaluate+0x10ee>
 1064f81:	4d 89 fd             	mov    %r15,%r13
 1064f84:	45 31 ff             	xor    %r15d,%r15d
 1064f87:	4c 8d a4 24 b8 01 00 	lea    0x1b8(%rsp),%r12
 1064f8e:	00 
 1064f8f:	4c 8b 4c 24 40       	mov    0x40(%rsp),%r9
 1064f94:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 1064f99:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1064fa0:	0f 1f 84 00 00 00 00 
 1064fa7:	00 
 1064fa8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1064faf:	0f 1f 84 00 00 00 00 
 1064fb6:	00 
 1064fb7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1064fbe:	00 00 
 1064fc0:	40 0f b6 c7          	movzbl %dil,%eax
 1064fc4:	4c 89 e7             	mov    %r12,%rdi
 1064fc7:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1064fcc:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 1064fd1:	48 89 d9             	mov    %rbx,%rcx
 1064fd4:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 1064fdb:	42 ff 74 fd 20       	push   0x20(%rbp,%r15,8)
 1064fe0:	41 53                	push   %r11
 1064fe2:	50                   	push   %rax
 1064fe3:	41 52                	push   %r10
 1064fe5:	41 55                	push   %r13
 1064fe7:	e8 a4 fc ff ff       	call   1064c90 <my.interpreter::evaluate>
 1064fec:	48 83 c4 30          	add    $0x30,%rsp
 1064ff0:	4c 8b 94 24 d0 01 00 	mov    0x1d0(%rsp),%r10
 1064ff7:	00 
 1064ff8:	0f b6 bc 24 d8 01 00 	movzbl 0x1d8(%rsp),%edi
 1064fff:	00 
 1065000:	4c 8b 9c 24 e0 01 00 	mov    0x1e0(%rsp),%r11
 1065007:	00 
 1065008:	80 bc 24 b8 01 00 00 	cmpb   $0x1,0x1b8(%rsp)
 106500f:	01 
 1065010:	0f 84 0a 1a 00 00    	je     1066a20 <my.interpreter::evaluate+0x1d90>
 1065016:	49 ff c7             	inc    %r15
 1065019:	4d 39 fe             	cmp    %r15,%r14
 106501c:	4c 8b 4c 24 40       	mov    0x40(%rsp),%r9
 1065021:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 1065026:	75 98                	jne    1064fc0 <my.interpreter::evaluate+0x330>
 1065028:	4c 8b 75 08          	mov    0x8(%rbp),%r14
 106502c:	e9 5a 0d 00 00       	jmp    1065d8b <my.interpreter::evaluate+0x10fb>
 1065031:	48 8b 48 28          	mov    0x28(%rax),%rcx
 1065035:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
 106503a:	48 8b 48 38          	mov    0x38(%rax),%rcx
 106503e:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
 1065043:	4c 89 d2             	mov    %r10,%rdx
 1065046:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 106504d:	00 00 
 106504f:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1065054:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1065059:	48 89 d9             	mov    %rbx,%rcx
 106505c:	41 54                	push   %r12
 106505e:	ff 70 08             	push   0x8(%rax)
 1065061:	41 56                	push   %r14
 1065063:	41 52                	push   %r10
 1065065:	41 53                	push   %r11
 1065067:	41 57                	push   %r15
 1065069:	4c 89 cb             	mov    %r9,%rbx
 106506c:	e8 1f fc ff ff       	call   1064c90 <my.interpreter::evaluate>
 1065071:	48 83 c4 30          	add    $0x30,%rsp
 1065075:	4c 8b 7c 24 78       	mov    0x78(%rsp),%r15
 106507a:	44 0f b6 ac 24 80 00 	movzbl 0x80(%rsp),%r13d
 1065081:	00 00 
 1065083:	48 8b 8c 24 88 00 00 	mov    0x88(%rsp),%rcx
 106508a:	00 
 106508b:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 1065090:	0f 84 93 17 00 00    	je     1066829 <my.interpreter::evaluate+0x1b99>
 1065096:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 106509d:	48 89 c6             	mov    %rax,%rsi
 10650a0:	48 ff ce             	dec    %rsi
 10650a3:	0f 80 b8 26 00 00    	jo     1067761 <my.interpreter::evaluate+0x2ad1>
 10650a9:	48 89 df             	mov    %rbx,%rdi
 10650ac:	48 8b 43 78          	mov    0x78(%rbx),%rax
 10650b0:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10650b4:	48 39 d6             	cmp    %rdx,%rsi
 10650b7:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
 10650bc:	0f 83 d5 1f 00 00    	jae    1067097 <my.interpreter::evaluate+0x2407>
 10650c2:	49 89 f4             	mov    %rsi,%r12
 10650c5:	49 c1 e4 04          	shl    $0x4,%r12
 10650c9:	4e 8b 74 20 20       	mov    0x20(%rax,%r12,1),%r14
 10650ce:	41 0f b6 ce          	movzbl %r14b,%ecx
 10650d2:	83 f9 03             	cmp    $0x3,%ecx
 10650d5:	0f 85 90 14 00 00    	jne    106656b <my.interpreter::evaluate+0x18db>
 10650db:	4a 8b 5c 20 28       	mov    0x28(%rax,%r12,1),%rbx
 10650e0:	48 8b 07             	mov    (%rdi),%rax
 10650e3:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10650e7:	48 89 d9             	mov    %rbx,%rcx
 10650ea:	48 39 d3             	cmp    %rdx,%rbx
 10650ed:	0f 83 73 20 00 00    	jae    1067166 <my.interpreter::evaluate+0x24d6>
 10650f3:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 10650f7:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 10650fc:	0f 85 69 14 00 00    	jne    106656b <my.interpreter::evaluate+0x18db>
 1065102:	4c 89 6c 24 30       	mov    %r13,0x30(%rsp)
 1065107:	4c 89 7c 24 38       	mov    %r15,0x38(%rsp)
 106510c:	48 89 2c 24          	mov    %rbp,(%rsp)
 1065110:	4c 8b 6c 24 28       	mov    0x28(%rsp),%r13
 1065115:	4c 89 ee             	mov    %r13,%rsi
 1065118:	49 89 ff             	mov    %rdi,%r15
 106511b:	e8 40 4a 00 00       	call   1069b60 <my.heap::string_hash>
 1065120:	89 c5                	mov    %eax,%ebp
 1065122:	4c 89 ff             	mov    %r15,%rdi
 1065125:	48 89 de             	mov    %rbx,%rsi
 1065128:	4c 89 ea             	mov    %r13,%rdx
 106512b:	89 c1                	mov    %eax,%ecx
 106512d:	e8 0e 50 00 00       	call   106a140 <my.heap::instance_field>
 1065132:	3c 01                	cmp    $0x1,%al
 1065134:	0f 85 ca 0a 00 00    	jne    1065c04 <my.interpreter::evaluate+0xf74>
 106513a:	31 c0                	xor    %eax,%eax
 106513c:	49 3b 87 80 00 00 00 	cmp    0x80(%r15),%rax
 1065143:	48 8b 2c 24          	mov    (%rsp),%rbp
 1065147:	0f 80 93 27 00 00    	jo     10678e0 <my.interpreter::evaluate+0x2c50>
 106514d:	49 8b 47 78          	mov    0x78(%r15),%rax
 1065151:	4a 8d 34 20          	lea    (%rax,%r12,1),%rsi
 1065155:	48 83 c6 20          	add    $0x20,%rsi
 1065159:	0f b6 d2             	movzbl %dl,%edx
 106515c:	4a 89 54 20 20       	mov    %rdx,0x20(%rax,%r12,1)
 1065161:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 1065166:	e9 31 0b 00 00       	jmp    1065c9c <my.interpreter::evaluate+0x100c>
 106516b:	48 8b 48 28          	mov    0x28(%rax),%rcx
 106516f:	48 89 4c 24 58       	mov    %rcx,0x58(%rsp)
 1065174:	48 8b 48 38          	mov    0x38(%rax),%rcx
 1065178:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
 106517d:	48 89 d9             	mov    %rbx,%rcx
 1065180:	4c 89 e3             	mov    %r12,%rbx
 1065183:	48 8b 50 40          	mov    0x40(%rax),%rdx
 1065187:	48 89 54 24 30       	mov    %rdx,0x30(%rsp)
 106518c:	4c 89 d2             	mov    %r10,%rdx
 106518f:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 1065196:	00 00 
 1065198:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 106519d:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10651a2:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
 10651a7:	49 89 cc             	mov    %rcx,%r12
 10651aa:	53                   	push   %rbx
 10651ab:	ff 70 08             	push   0x8(%rax)
 10651ae:	41 56                	push   %r14
 10651b0:	41 52                	push   %r10
 10651b2:	41 53                	push   %r11
 10651b4:	4d 89 fd             	mov    %r15,%r13
 10651b7:	41 57                	push   %r15
 10651b9:	4d 89 cf             	mov    %r9,%r15
 10651bc:	e8 cf fa ff ff       	call   1064c90 <my.interpreter::evaluate>
 10651c1:	48 83 c4 30          	add    $0x30,%rsp
 10651c5:	48 8b 5c 24 78       	mov    0x78(%rsp),%rbx
 10651ca:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 10651d1:	00 
 10651d2:	44 0f b6 f0          	movzbl %al,%r14d
 10651d6:	48 8b 8c 24 88 00 00 	mov    0x88(%rsp),%rcx
 10651dd:	00 
 10651de:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 10651e3:	0f 84 6c 16 00 00    	je     1066855 <my.interpreter::evaluate+0x1bc5>
 10651e9:	48 89 0c 24          	mov    %rcx,(%rsp)
 10651ed:	49 8b 87 80 00 00 00 	mov    0x80(%r15),%rax
 10651f4:	48 89 c6             	mov    %rax,%rsi
 10651f7:	48 ff ce             	dec    %rsi
 10651fa:	0f 80 75 25 00 00    	jo     1067775 <my.interpreter::evaluate+0x2ae5>
 1065200:	49 8b 47 78          	mov    0x78(%r15),%rax
 1065204:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065208:	48 39 d6             	cmp    %rdx,%rsi
 106520b:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 1065210:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 1065215:	0f 83 9e 1e 00 00    	jae    10670b9 <my.interpreter::evaluate+0x2429>
 106521b:	48 89 f7             	mov    %rsi,%rdi
 106521e:	48 c1 e7 04          	shl    $0x4,%rdi
 1065222:	80 7c 38 20 03       	cmpb   $0x3,0x20(%rax,%rdi,1)
 1065227:	0f 85 68 13 00 00    	jne    1066595 <my.interpreter::evaluate+0x1905>
 106522d:	48 8b 74 38 28       	mov    0x28(%rax,%rdi,1),%rsi
 1065232:	49 8b 07             	mov    (%r15),%rax
 1065235:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065239:	48 39 d6             	cmp    %rdx,%rsi
 106523c:	0f 83 49 1f 00 00    	jae    106718b <my.interpreter::evaluate+0x24fb>
 1065242:	48 89 f7             	mov    %rsi,%rdi
 1065245:	48 6b d7 38          	imul   $0x38,%rdi,%rdx
 1065249:	83 7c 10 20 07       	cmpl   $0x7,0x20(%rax,%rdx,1)
 106524e:	0f 85 41 13 00 00    	jne    1066595 <my.interpreter::evaluate+0x1905>
 1065254:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 106525b:	00 
 106525c:	4c 89 de             	mov    %r11,%rsi
 106525f:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 1065264:	4c 89 e1             	mov    %r12,%rcx
 1065267:	4d 89 f9             	mov    %r15,%r9
 106526a:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 1065271:	ff 74 24 38          	push   0x38(%rsp)
 1065275:	ff 74 24 10          	push   0x10(%rsp)
 1065279:	41 56                	push   %r14
 106527b:	53                   	push   %rbx
 106527c:	41 55                	push   %r13
 106527e:	e8 0d fa ff ff       	call   1064c90 <my.interpreter::evaluate>
 1065283:	48 83 c4 30          	add    $0x30,%rsp
 1065287:	48 8b 84 24 b8 00 00 	mov    0xb8(%rsp),%rax
 106528e:	00 
 106528f:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 1065294:	44 0f b6 b4 24 c0 00 	movzbl 0xc0(%rsp),%r14d
 106529b:	00 00 
 106529d:	48 8b 8c 24 c8 00 00 	mov    0xc8(%rsp),%rcx
 10652a4:	00 
 10652a5:	80 bc 24 a0 00 00 00 	cmpb   $0x1,0xa0(%rsp)
 10652ac:	01 
 10652ad:	0f 84 1c 17 00 00    	je     10669cf <my.interpreter::evaluate+0x1d3f>
 10652b3:	49 8b b7 80 00 00 00 	mov    0x80(%r15),%rsi
 10652ba:	48 89 f0             	mov    %rsi,%rax
 10652bd:	48 ff c8             	dec    %rax
 10652c0:	0f 80 73 25 00 00    	jo     1067839 <my.interpreter::evaluate+0x2ba9>
 10652c6:	48 89 c6             	mov    %rax,%rsi
 10652c9:	48 ff ce             	dec    %rsi
 10652cc:	0f 80 78 25 00 00    	jo     106784a <my.interpreter::evaluate+0x2bba>
 10652d2:	48 89 0c 24          	mov    %rcx,(%rsp)
 10652d6:	4d 89 f5             	mov    %r14,%r13
 10652d9:	49 8b 47 78          	mov    0x78(%r15),%rax
 10652dd:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10652e1:	48 39 d6             	cmp    %rdx,%rsi
 10652e4:	0f 83 7c 1f 00 00    	jae    1067266 <my.interpreter::evaluate+0x25d6>
 10652ea:	48 89 f1             	mov    %rsi,%rcx
 10652ed:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 10652f2:	48 c1 e1 04          	shl    $0x4,%rcx
 10652f6:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 10652fb:	83 fa 03             	cmp    $0x3,%edx
 10652fe:	0f 85 bf 23 00 00    	jne    10676c3 <my.interpreter::evaluate+0x2a33>
 1065304:	4c 8b 64 08 28       	mov    0x28(%rax,%rcx,1),%r12
 1065309:	4c 89 ff             	mov    %r15,%rdi
 106530c:	4c 89 f6             	mov    %r14,%rsi
 106530f:	e8 4c 48 00 00       	call   1069b60 <my.heap::string_hash>
 1065314:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1065319:	48 8b 8f 80 00 00 00 	mov    0x80(%rdi),%rcx
 1065320:	48 89 ce             	mov    %rcx,%rsi
 1065323:	48 ff ce             	dec    %rsi
 1065326:	0f 80 4a 25 00 00    	jo     1067876 <my.interpreter::evaluate+0x2be6>
 106532c:	48 8b 4f 78          	mov    0x78(%rdi),%rcx
 1065330:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065334:	48 39 d6             	cmp    %rdx,%rsi
 1065337:	0f 83 50 1f 00 00    	jae    106728d <my.interpreter::evaluate+0x25fd>
 106533d:	49 89 f0             	mov    %rsi,%r8
 1065340:	49 c1 e0 04          	shl    $0x4,%r8
 1065344:	42 0f b6 5c 01 20    	movzbl 0x20(%rcx,%r8,1),%ebx
 106534a:	4e 8b 7c 01 28       	mov    0x28(%rcx,%r8,1),%r15
 106534f:	4c 89 e6             	mov    %r12,%rsi
 1065352:	4c 89 f2             	mov    %r14,%rdx
 1065355:	89 c1                	mov    %eax,%ecx
 1065357:	41 89 d8             	mov    %ebx,%r8d
 106535a:	4d 89 f9             	mov    %r15,%r9
 106535d:	e8 ae 4f 00 00       	call   106a310 <my.heap::set_instance_field>
 1065362:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1065367:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
 106536e:	48 89 c6             	mov    %rax,%rsi
 1065371:	48 ff ce             	dec    %rsi
 1065374:	0f 80 10 25 00 00    	jo     106788a <my.interpreter::evaluate+0x2bfa>
 106537a:	48 89 b7 80 00 00 00 	mov    %rsi,0x80(%rdi)
 1065381:	48 8b 4f 78          	mov    0x78(%rdi),%rcx
 1065385:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065389:	48 39 d6             	cmp    %rdx,%rsi
 106538c:	0f 83 1d 1f 00 00    	jae    10672af <my.interpreter::evaluate+0x261f>
 1065392:	48 89 f0             	mov    %rsi,%rax
 1065395:	48 ff c8             	dec    %rax
 1065398:	0f 80 00 25 00 00    	jo     106789e <my.interpreter::evaluate+0x2c0e>
 106539e:	48 39 d0             	cmp    %rdx,%rax
 10653a1:	0f 83 2a 1f 00 00    	jae    10672d1 <my.interpreter::evaluate+0x2641>
 10653a7:	48 89 c6             	mov    %rax,%rsi
 10653aa:	48 c1 e6 04          	shl    $0x4,%rsi
 10653ae:	48 89 5c 31 20       	mov    %rbx,0x20(%rcx,%rsi,1)
 10653b3:	4c 89 7c 31 28       	mov    %r15,0x28(%rcx,%rsi,1)
 10653b8:	48 89 4f 78          	mov    %rcx,0x78(%rdi)
 10653bc:	31 c0                	xor    %eax,%eax
 10653be:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 10653c3:	4d 89 ee             	mov    %r13,%r14
 10653c6:	48 8b 0c 24          	mov    (%rsp),%rcx
 10653ca:	e9 37 16 00 00       	jmp    1066a06 <my.interpreter::evaluate+0x1d76>
 10653cf:	48 89 2c 24          	mov    %rbp,(%rsp)
 10653d3:	4d 89 fd             	mov    %r15,%r13
 10653d6:	0f b6 48 10          	movzbl 0x10(%rax),%ecx
 10653da:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
 10653df:	48 8b 48 28          	mov    0x28(%rax),%rcx
 10653e3:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
 10653e8:	48 8b 48 38          	mov    0x38(%rax),%rcx
 10653ec:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
 10653f1:	4d 89 d7             	mov    %r10,%r15
 10653f4:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 10653fb:	00 00 
 10653fd:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1065402:	48 8b 6c 24 10       	mov    0x10(%rsp),%rbp
 1065407:	48 89 ee             	mov    %rbp,%rsi
 106540a:	4c 89 fa             	mov    %r15,%rdx
 106540d:	48 89 d9             	mov    %rbx,%rcx
 1065410:	48 89 5c 24 38       	mov    %rbx,0x38(%rsp)
 1065415:	4c 89 c3             	mov    %r8,%rbx
 1065418:	41 54                	push   %r12
 106541a:	ff 70 08             	push   0x8(%rax)
 106541d:	41 56                	push   %r14
 106541f:	41 52                	push   %r10
 1065421:	41 53                	push   %r11
 1065423:	4d 89 ee             	mov    %r13,%r14
 1065426:	41 55                	push   %r13
 1065428:	4d 89 cd             	mov    %r9,%r13
 106542b:	e8 60 f8 ff ff       	call   1064c90 <my.interpreter::evaluate>
 1065430:	48 83 c4 30          	add    $0x30,%rsp
 1065434:	4c 8b 54 24 78       	mov    0x78(%rsp),%r10
 1065439:	0f b6 84 24 80 00 00 	movzbl 0x80(%rsp),%eax
 1065440:	00 
 1065441:	4c 8b 9c 24 88 00 00 	mov    0x88(%rsp),%r11
 1065448:	00 
 1065449:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 106544e:	0f 84 39 14 00 00    	je     106688d <my.interpreter::evaluate+0x1bfd>
 1065454:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 106545b:	00 
 106545c:	48 89 ee             	mov    %rbp,%rsi
 106545f:	4c 89 fa             	mov    %r15,%rdx
 1065462:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 1065467:	49 89 d8             	mov    %rbx,%r8
 106546a:	4d 89 e9             	mov    %r13,%r9
 106546d:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 1065474:	ff 74 24 30          	push   0x30(%rsp)
 1065478:	41 53                	push   %r11
 106547a:	50                   	push   %rax
 106547b:	41 52                	push   %r10
 106547d:	41 56                	push   %r14
 106547f:	e8 0c f8 ff ff       	call   1064c90 <my.interpreter::evaluate>
 1065484:	48 83 c4 30          	add    $0x30,%rsp
 1065488:	4c 8b 94 24 b8 00 00 	mov    0xb8(%rsp),%r10
 106548f:	00 
 1065490:	44 0f b6 9c 24 c0 00 	movzbl 0xc0(%rsp),%r11d
 1065497:	00 00 
 1065499:	4c 8b b4 24 c8 00 00 	mov    0xc8(%rsp),%r14
 10654a0:	00 
 10654a1:	80 bc 24 a0 00 00 00 	cmpb   $0x1,0xa0(%rsp)
 10654a8:	01 
 10654a9:	0f 84 e0 14 00 00    	je     106698f <my.interpreter::evaluate+0x1cff>
 10654af:	4d 8b 8d 80 00 00 00 	mov    0x80(%r13),%r9
 10654b6:	4c 89 cb             	mov    %r9,%rbx
 10654b9:	48 ff cb             	dec    %rbx
 10654bc:	41 0f 90 c7          	seto   %r15b
 10654c0:	0f 80 37 23 00 00    	jo     10677fd <my.interpreter::evaluate+0x2b6d>
 10654c6:	48 89 de             	mov    %rbx,%rsi
 10654c9:	48 ff ce             	dec    %rsi
 10654cc:	0f 80 3f 23 00 00    	jo     1067811 <my.interpreter::evaluate+0x2b81>
 10654d2:	4c 89 ef             	mov    %r13,%rdi
 10654d5:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 10654d9:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10654dd:	48 39 d6             	cmp    %rdx,%rsi
 10654e0:	0f 83 c7 1c 00 00    	jae    10671ad <my.interpreter::evaluate+0x251d>
 10654e6:	49 89 f0             	mov    %rsi,%r8
 10654e9:	49 c1 e0 04          	shl    $0x4,%r8
 10654ed:	42 0f b6 44 01 20    	movzbl 0x20(%rcx,%r8,1),%eax
 10654f3:	4e 8b 6c 01 28       	mov    0x28(%rcx,%r8,1),%r13
 10654f8:	48 89 de             	mov    %rbx,%rsi
 10654fb:	48 39 d3             	cmp    %rdx,%rbx
 10654fe:	0f 83 cb 1c 00 00    	jae    10671cf <my.interpreter::evaluate+0x253f>
 1065504:	48 83 c1 20          	add    $0x20,%rcx
 1065508:	48 c1 e6 04          	shl    $0x4,%rsi
 106550c:	0f b6 2c 31          	movzbl (%rcx,%rsi,1),%ebp
 1065510:	4c 8b 64 31 08       	mov    0x8(%rcx,%rsi,1),%r12
 1065515:	48 8b 74 24 30       	mov    0x30(%rsp),%rsi
 106551a:	48 83 fe 0c          	cmp    $0xc,%rsi
 106551e:	0f 84 a2 0b 00 00    	je     10660c6 <my.interpreter::evaluate+0x1436>
 1065524:	83 fe 0e             	cmp    $0xe,%esi
 1065527:	0f 85 c1 0b 00 00    	jne    10660ee <my.interpreter::evaluate+0x145e>
 106552d:	3c 02                	cmp    $0x2,%al
 106552f:	0f 84 e4 10 00 00    	je     1066619 <my.interpreter::evaluate+0x1989>
 1065535:	0f b6 c0             	movzbl %al,%eax
 1065538:	83 f8 01             	cmp    $0x1,%eax
 106553b:	0f 84 ba 10 00 00    	je     10665fb <my.interpreter::evaluate+0x196b>
 1065541:	85 c0                	test   %eax,%eax
 1065543:	0f 85 f5 10 00 00    	jne    106663e <my.interpreter::evaluate+0x19ae>
 1065549:	40 84 ed             	test   %bpl,%bpl
 106554c:	41 0f 94 c4          	sete   %r12b
 1065550:	e9 fa 10 00 00       	jmp    106664f <my.interpreter::evaluate+0x19bf>
 1065555:	c5 f9 10 40 08       	vmovupd 0x8(%rax),%xmm0
 106555a:	49 8b 41 78          	mov    0x78(%r9),%rax
 106555e:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065565:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065569:	48 39 d6             	cmp    %rdx,%rsi
 106556c:	0f 83 33 1a 00 00    	jae    1066fa5 <my.interpreter::evaluate+0x2315>
 1065572:	48 89 f1             	mov    %rsi,%rcx
 1065575:	c5 f9 54 05 63 ee f9 	vandpd -0x6119d(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 106557c:	ff 
 106557d:	48 c1 e1 04          	shl    $0x4,%rcx
 1065581:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 1065587:	49 89 41 78          	mov    %rax,0x78(%r9)
 106558b:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065592:	48 89 f0             	mov    %rsi,%rax
 1065595:	48 ff c0             	inc    %rax
 1065598:	0f 81 b3 03 00 00    	jno    1065951 <my.interpreter::evaluate+0xcc1>
 106559e:	48 8d 3d cb cb 01 00 	lea    0x1cbcb(%rip),%rdi        # 1082170 <core_durable_error.verbs+0x3270>
 10655a5:	ba 01 00 00 00       	mov    $0x1,%edx
 10655aa:	e8 11 ef fb ff       	call   10244c0 <myl_core_trap>
 10655af:	48 89 d9             	mov    %rbx,%rcx
 10655b2:	4c 89 e3             	mov    %r12,%rbx
 10655b5:	48 89 2c 24          	mov    %rbp,(%rsp)
 10655b9:	0f b6 68 10          	movzbl 0x10(%rax),%ebp
 10655bd:	48 8b 50 38          	mov    0x38(%rax),%rdx
 10655c1:	48 89 54 24 40       	mov    %rdx,0x40(%rsp)
 10655c6:	4c 89 d2             	mov    %r10,%rdx
 10655c9:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 10655d0:	00 00 
 10655d2:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 10655d7:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10655dc:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
 10655e1:	49 89 cc             	mov    %rcx,%r12
 10655e4:	53                   	push   %rbx
 10655e5:	ff 70 08             	push   0x8(%rax)
 10655e8:	41 56                	push   %r14
 10655ea:	41 52                	push   %r10
 10655ec:	41 53                	push   %r11
 10655ee:	41 57                	push   %r15
 10655f0:	4d 89 cd             	mov    %r9,%r13
 10655f3:	e8 98 f6 ff ff       	call   1064c90 <my.interpreter::evaluate>
 10655f8:	48 83 c4 30          	add    $0x30,%rsp
 10655fc:	4c 8b 54 24 78       	mov    0x78(%rsp),%r10
 1065601:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 1065608:	00 
 1065609:	44 0f b6 f0          	movzbl %al,%r14d
 106560d:	4c 8b bc 24 88 00 00 	mov    0x88(%rsp),%r15
 1065614:	00 
 1065615:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 106561a:	0f 84 8b 12 00 00    	je     10668ab <my.interpreter::evaluate+0x1c1b>
 1065620:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1065627:	48 89 c6             	mov    %rax,%rsi
 106562a:	48 ff ce             	dec    %rsi
 106562d:	0f 80 56 21 00 00    	jo     1067789 <my.interpreter::evaluate+0x2af9>
 1065633:	4d 89 e9             	mov    %r13,%r9
 1065636:	49 8b 45 78          	mov    0x78(%r13),%rax
 106563a:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106563e:	48 89 f7             	mov    %rsi,%rdi
 1065641:	48 39 d6             	cmp    %rdx,%rsi
 1065644:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 1065649:	0f 83 8c 1a 00 00    	jae    10670db <my.interpreter::evaluate+0x244b>
 106564f:	48 c1 e7 04          	shl    $0x4,%rdi
 1065653:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 1065658:	83 fa 01             	cmp    $0x1,%edx
 106565b:	0f 84 25 0a 00 00    	je     1066086 <my.interpreter::evaluate+0x13f6>
 1065661:	85 d2                	test   %edx,%edx
 1065663:	0f 85 52 0a 00 00    	jne    10660bb <my.interpreter::evaluate+0x142b>
 1065669:	83 fd 1e             	cmp    $0x1e,%ebp
 106566c:	0f 85 2d 0a 00 00    	jne    106609f <my.interpreter::evaluate+0x140f>
 1065672:	49 89 b1 80 00 00 00 	mov    %rsi,0x80(%r9)
 1065679:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 1065680:	00 
 1065681:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1065686:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 106568b:	4c 89 e1             	mov    %r12,%rcx
 106568e:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 1065695:	ff 74 24 48          	push   0x48(%rsp)
 1065699:	41 57                	push   %r15
 106569b:	41 56                	push   %r14
 106569d:	41 52                	push   %r10
 106569f:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 10656a6:	e8 e5 f5 ff ff       	call   1064c90 <my.interpreter::evaluate>
 10656ab:	48 83 c4 30          	add    $0x30,%rsp
 10656af:	0f b6 84 24 a0 00 00 	movzbl 0xa0(%rsp),%eax
 10656b6:	00 
 10656b7:	c5 f9 10 84 24 a8 00 	vmovupd 0xa8(%rsp),%xmm0
 10656be:	00 00 
 10656c0:	4c 8b 94 24 b8 00 00 	mov    0xb8(%rsp),%r10
 10656c7:	00 
 10656c8:	44 0f b6 b4 24 c0 00 	movzbl 0xc0(%rsp),%r14d
 10656cf:	00 00 
 10656d1:	4c 8b bc 24 c8 00 00 	mov    0xc8(%rsp),%r15
 10656d8:	00 
 10656d9:	48 83 f8 01          	cmp    $0x1,%rax
 10656dd:	48 8b 2c 24          	mov    (%rsp),%rbp
 10656e1:	0f 85 be 09 00 00    	jne    10660a5 <my.interpreter::evaluate+0x1415>
 10656e7:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 10656ed:	48 8d 3d dc fa 01 00 	lea    0x1fadc(%rip),%rdi        # 10851d0 <core_durable_error.verbs+0x62d0>
 10656f4:	e9 c9 11 00 00       	jmp    10668c2 <my.interpreter::evaluate+0x1c32>
 10656f9:	4d 89 fd             	mov    %r15,%r13
 10656fc:	4d 89 f7             	mov    %r14,%r15
 10656ff:	49 89 ee             	mov    %rbp,%r14
 1065702:	0f b6 68 08          	movzbl 0x8(%rax),%ebp
 1065706:	48 89 d9             	mov    %rbx,%rcx
 1065709:	4c 89 e3             	mov    %r12,%rbx
 106570c:	4c 8b 60 20          	mov    0x20(%rax),%r12
 1065710:	4c 89 d2             	mov    %r10,%rdx
 1065713:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 106571a:	00 00 
 106571c:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1065721:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1065726:	53                   	push   %rbx
 1065727:	ff 70 30             	push   0x30(%rax)
 106572a:	41 57                	push   %r15
 106572c:	41 52                	push   %r10
 106572e:	41 53                	push   %r11
 1065730:	41 55                	push   %r13
 1065732:	4c 89 cb             	mov    %r9,%rbx
 1065735:	e8 56 f5 ff ff       	call   1064c90 <my.interpreter::evaluate>
 106573a:	48 83 c4 30          	add    $0x30,%rsp
 106573e:	4c 8b 4c 24 78       	mov    0x78(%rsp),%r9
 1065743:	44 0f b6 ac 24 80 00 	movzbl 0x80(%rsp),%r13d
 106574a:	00 00 
 106574c:	4c 8b bc 24 88 00 00 	mov    0x88(%rsp),%r15
 1065753:	00 
 1065754:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 1065759:	0f 84 84 11 00 00    	je     10668e3 <my.interpreter::evaluate+0x1c53>
 106575f:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 1065766:	48 89 c6             	mov    %rax,%rsi
 1065769:	48 ff ce             	dec    %rsi
 106576c:	0f 80 2b 20 00 00    	jo     106779d <my.interpreter::evaluate+0x2b0d>
 1065772:	48 8b 43 78          	mov    0x78(%rbx),%rax
 1065776:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106577a:	48 39 d6             	cmp    %rdx,%rsi
 106577d:	0f 83 7a 19 00 00    	jae    10670fd <my.interpreter::evaluate+0x246d>
 1065783:	48 89 f7             	mov    %rsi,%rdi
 1065786:	48 c1 e7 04          	shl    $0x4,%rdi
 106578a:	48 8d 0c 38          	lea    (%rax,%rdi,1),%rcx
 106578e:	48 83 c1 20          	add    $0x20,%rcx
 1065792:	0f b6 74 38 20       	movzbl 0x20(%rax,%rdi,1),%esi
 1065797:	48 8b 54 38 28       	mov    0x28(%rax,%rdi,1),%rdx
 106579c:	83 fd 0b             	cmp    $0xb,%ebp
 106579f:	0f 85 35 04 00 00    	jne    1065bda <my.interpreter::evaluate+0xf4a>
 10657a5:	40 84 f6             	test   %sil,%sil
 10657a8:	4c 89 f5             	mov    %r14,%rbp
 10657ab:	0f 84 b7 0c 00 00    	je     1066468 <my.interpreter::evaluate+0x17d8>
 10657b1:	40 0f b6 f6          	movzbl %sil,%esi
 10657b5:	83 fe 01             	cmp    $0x1,%esi
 10657b8:	0f 85 ae 0c 00 00    	jne    106646c <my.interpreter::evaluate+0x17dc>
 10657be:	f6 d2                	not    %dl
 10657c0:	80 e2 01             	and    $0x1,%dl
 10657c3:	e9 a6 0c 00 00       	jmp    106646e <my.interpreter::evaluate+0x17de>
 10657c8:	48 89 2c 24          	mov    %rbp,(%rsp)
 10657cc:	4c 8b 70 48          	mov    0x48(%rax),%r14
 10657d0:	48 8b 58 58          	mov    0x58(%rax),%rbx
 10657d4:	48 8b 40 60          	mov    0x60(%rax),%rax
 10657d8:	49 8b 39             	mov    (%r9),%rdi
 10657db:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 10657e2:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 10657e6:	48 89 f1             	mov    %rsi,%rcx
 10657e9:	48 85 c0             	test   %rax,%rax
 10657ec:	0f 8e 73 01 00 00    	jle    1065965 <my.interpreter::evaluate+0xcd5>
 10657f2:	4c 8d 47 20          	lea    0x20(%rdi),%r8
 10657f6:	49 89 c3             	mov    %rax,%r11
 10657f9:	48 89 f1             	mov    %rsi,%rcx
 10657fc:	0f 1f 40 00          	nopl   0x0(%rax)
 1065800:	48 39 d1             	cmp    %rdx,%rcx
 1065803:	73 23                	jae    1065828 <my.interpreter::evaluate+0xb98>
 1065805:	49 89 ca             	mov    %rcx,%r10
 1065808:	49 6b ca 38          	imul   $0x38,%r10,%rcx
 106580c:	41 83 3c 08 09       	cmpl   $0x9,(%r8,%rcx,1)
 1065811:	0f 85 e6 1c 00 00    	jne    10674fd <my.interpreter::evaluate+0x286d>
 1065817:	4c 01 c1             	add    %r8,%rcx
 106581a:	48 8b 49 08          	mov    0x8(%rcx),%rcx
 106581e:	49 ff cb             	dec    %r11
 1065821:	75 dd                	jne    1065800 <my.interpreter::evaluate+0xb70>
 1065823:	e9 3d 01 00 00       	jmp    1065965 <my.interpreter::evaluate+0xcd5>
 1065828:	49 89 ca             	mov    %rcx,%r10
 106582b:	49 c1 fa 3f          	sar    $0x3f,%r10
 106582f:	49 21 d2             	and    %rdx,%r10
 1065832:	49 01 ca             	add    %rcx,%r10
 1065835:	49 39 d2             	cmp    %rdx,%r10
 1065838:	72 ce                	jb     1065808 <my.interpreter::evaluate+0xb78>
 106583a:	48 8d 3d 8f f3 01 00 	lea    0x1f38f(%rip),%rdi        # 1084bd0 <core_durable_error.verbs+0x5cd0>
 1065841:	48 89 ce             	mov    %rcx,%rsi
 1065844:	e8 77 ec fb ff       	call   10244c0 <myl_core_trap>
 1065849:	48 8b 78 38          	mov    0x38(%rax),%rdi
 106584d:	48 83 ff ff          	cmp    $0xffffffffffffffff,%rdi
 1065851:	0f 84 76 04 00 00    	je     1065ccd <my.interpreter::evaluate+0x103d>
 1065857:	48 8b 70 40          	mov    0x40(%rax),%rsi
 106585b:	49 8b 09             	mov    (%r9),%rcx
 106585e:	49 8b 81 a8 00 00 00 	mov    0xa8(%r9),%rax
 1065865:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065869:	48 85 ff             	test   %rdi,%rdi
 106586c:	0f 8e 9d 02 00 00    	jle    1065b0f <my.interpreter::evaluate+0xe7f>
 1065872:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 1065876:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 106587d:	00 00 00 
 1065880:	48 39 d0             	cmp    %rdx,%rax
 1065883:	73 23                	jae    10658a8 <my.interpreter::evaluate+0xc18>
 1065885:	49 89 c2             	mov    %rax,%r10
 1065888:	49 6b c2 38          	imul   $0x38,%r10,%rax
 106588c:	41 83 3c 00 09       	cmpl   $0x9,(%r8,%rax,1)
 1065891:	0f 85 7e 1c 00 00    	jne    1067515 <my.interpreter::evaluate+0x2885>
 1065897:	4c 01 c0             	add    %r8,%rax
 106589a:	48 8b 40 08          	mov    0x8(%rax),%rax
 106589e:	48 ff cf             	dec    %rdi
 10658a1:	75 dd                	jne    1065880 <my.interpreter::evaluate+0xbf0>
 10658a3:	e9 67 02 00 00       	jmp    1065b0f <my.interpreter::evaluate+0xe7f>
 10658a8:	49 89 c2             	mov    %rax,%r10
 10658ab:	49 c1 fa 3f          	sar    $0x3f,%r10
 10658af:	49 21 d2             	and    %rdx,%r10
 10658b2:	49 01 c2             	add    %rax,%r10
 10658b5:	49 39 d2             	cmp    %rdx,%r10
 10658b8:	72 ce                	jb     1065888 <my.interpreter::evaluate+0xbf8>
 10658ba:	48 8d 3d 0f f3 01 00 	lea    0x1f30f(%rip),%rdi        # 1084bd0 <core_durable_error.verbs+0x5cd0>
 10658c1:	48 89 c6             	mov    %rax,%rsi
 10658c4:	e8 f7 eb fb ff       	call   10244c0 <myl_core_trap>
 10658c9:	48 8b 40 38          	mov    0x38(%rax),%rax
 10658cd:	48 39 d6             	cmp    %rdx,%rsi
 10658d0:	0f 83 f1 16 00 00    	jae    1066fc7 <my.interpreter::evaluate+0x2337>
 10658d6:	48 89 f7             	mov    %rsi,%rdi
 10658d9:	48 6b d7 38          	imul   $0x38,%rdi,%rdx
 10658dd:	83 7c 11 20 09       	cmpl   $0x9,0x20(%rcx,%rdx,1)
 10658e2:	0f 85 18 1e 00 00    	jne    1067700 <my.interpreter::evaluate+0x2a70>
 10658e8:	48 01 d1             	add    %rdx,%rcx
 10658eb:	48 83 c1 20          	add    $0x20,%rcx
 10658ef:	48 8b 49 10          	mov    0x10(%rcx),%rcx
 10658f3:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10658f7:	48 39 d0             	cmp    %rdx,%rax
 10658fa:	0f 83 0e 17 00 00    	jae    106700e <my.interpreter::evaluate+0x237e>
 1065900:	48 89 c6             	mov    %rax,%rsi
 1065903:	48 c1 e6 04          	shl    $0x4,%rsi
 1065907:	c5 f9 10 44 31 20    	vmovupd 0x20(%rcx,%rsi,1),%xmm0
 106590d:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065911:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065918:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106591c:	48 39 d6             	cmp    %rdx,%rsi
 106591f:	0f 83 0e 17 00 00    	jae    1067033 <my.interpreter::evaluate+0x23a3>
 1065925:	48 89 f1             	mov    %rsi,%rcx
 1065928:	c5 f9 54 05 b0 ea f9 	vandpd -0x61550(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 106592f:	ff 
 1065930:	48 c1 e1 04          	shl    $0x4,%rcx
 1065934:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 106593a:	49 89 41 78          	mov    %rax,0x78(%r9)
 106593e:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065945:	48 89 f0             	mov    %rsi,%rax
 1065948:	48 ff c0             	inc    %rax
 106594b:	0f 80 c7 1d 00 00    	jo     1067718 <my.interpreter::evaluate+0x2a88>
 1065951:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065958:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 106595f:	00 
 1065960:	e9 00 04 00 00       	jmp    1065d65 <my.interpreter::evaluate+0x10d5>
 1065965:	48 39 d1             	cmp    %rdx,%rcx
 1065968:	0f 83 7b 16 00 00    	jae    1066fe9 <my.interpreter::evaluate+0x2359>
 106596e:	49 89 c8             	mov    %rcx,%r8
 1065971:	49 6b c8 38          	imul   $0x38,%r8,%rcx
 1065975:	83 7c 0f 20 09       	cmpl   $0x9,0x20(%rdi,%rcx,1)
 106597a:	0f 85 8c 1d 00 00    	jne    106770c <my.interpreter::evaluate+0x2a7c>
 1065980:	48 01 f9             	add    %rdi,%rcx
 1065983:	48 83 c1 20          	add    $0x20,%rcx
 1065987:	4c 8b 41 10          	mov    0x10(%rcx),%r8
 106598b:	49 83 78 08 00       	cmpq   $0x0,0x8(%r8)
 1065990:	0f 84 bf 16 00 00    	je     1067055 <my.interpreter::evaluate+0x23c5>
 1065996:	48 89 c1             	mov    %rax,%rcx
 1065999:	48 ff c9             	dec    %rcx
 106599c:	0f 80 87 1d 00 00    	jo     1067729 <my.interpreter::evaluate+0x2a99>
 10659a2:	48 83 c7 20          	add    $0x20,%rdi
 10659a6:	41 0f b6 40 20       	movzbl 0x20(%r8),%eax
 10659ab:	4d 8b 78 28          	mov    0x28(%r8),%r15
 10659af:	48 85 c9             	test   %rcx,%rcx
 10659b2:	7e 4e                	jle    1065a02 <my.interpreter::evaluate+0xd72>
 10659b4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10659bb:	00 00 00 00 00 
 10659c0:	48 39 d6             	cmp    %rdx,%rsi
 10659c3:	73 1f                	jae    10659e4 <my.interpreter::evaluate+0xd54>
 10659c5:	49 89 f0             	mov    %rsi,%r8
 10659c8:	49 6b f0 38          	imul   $0x38,%r8,%rsi
 10659cc:	83 3c 37 09          	cmpl   $0x9,(%rdi,%rsi,1)
 10659d0:	0f 85 33 1b 00 00    	jne    1067509 <my.interpreter::evaluate+0x2879>
 10659d6:	48 01 fe             	add    %rdi,%rsi
 10659d9:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 10659dd:	48 ff c9             	dec    %rcx
 10659e0:	75 de                	jne    10659c0 <my.interpreter::evaluate+0xd30>
 10659e2:	eb 1e                	jmp    1065a02 <my.interpreter::evaluate+0xd72>
 10659e4:	49 89 f0             	mov    %rsi,%r8
 10659e7:	49 c1 f8 3f          	sar    $0x3f,%r8
 10659eb:	49 21 d0             	and    %rdx,%r8
 10659ee:	49 01 f0             	add    %rsi,%r8
 10659f1:	49 39 d0             	cmp    %rdx,%r8
 10659f4:	72 d2                	jb     10659c8 <my.interpreter::evaluate+0xd38>
 10659f6:	48 8d 3d d3 f1 01 00 	lea    0x1f1d3(%rip),%rdi        # 1084bd0 <core_durable_error.verbs+0x5cd0>
 10659fd:	e8 be ea fb ff       	call   10244c0 <myl_core_trap>
 1065a02:	48 39 d6             	cmp    %rdx,%rsi
 1065a05:	0f 83 5a 16 00 00    	jae    1067065 <my.interpreter::evaluate+0x23d5>
 1065a0b:	48 89 f1             	mov    %rsi,%rcx
 1065a0e:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065a12:	83 3c 0f 09          	cmpl   $0x9,(%rdi,%rcx,1)
 1065a16:	0f 85 21 1d 00 00    	jne    106773d <my.interpreter::evaluate+0x2aad>
 1065a1c:	48 01 cf             	add    %rcx,%rdi
 1065a1f:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 1065a23:	48 83 79 08 00       	cmpq   $0x0,0x8(%rcx)
 1065a28:	0f 84 59 16 00 00    	je     1067087 <my.interpreter::evaluate+0x23f7>
 1065a2e:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 1065a33:	3c 03                	cmp    $0x3,%al
 1065a35:	0f 85 48 1c 00 00    	jne    1067683 <my.interpreter::evaluate+0x29f3>
 1065a3b:	44 0f b6 71 20       	movzbl 0x20(%rcx),%r14d
 1065a40:	4c 8b 61 28          	mov    0x28(%rcx),%r12
 1065a44:	4c 89 cf             	mov    %r9,%rdi
 1065a47:	48 89 de             	mov    %rbx,%rsi
 1065a4a:	4c 89 cd             	mov    %r9,%rbp
 1065a4d:	e8 0e 41 00 00       	call   1069b60 <my.heap::string_hash>
 1065a52:	48 89 ef             	mov    %rbp,%rdi
 1065a55:	4c 89 fe             	mov    %r15,%rsi
 1065a58:	48 89 da             	mov    %rbx,%rdx
 1065a5b:	89 c1                	mov    %eax,%ecx
 1065a5d:	e8 be 49 00 00       	call   106a420 <my.heap::class_method>
 1065a62:	3c 01                	cmp    $0x1,%al
 1065a64:	0f 85 97 0e 00 00    	jne    1066901 <my.interpreter::evaluate+0x1c71>
 1065a6a:	80 fa 03             	cmp    $0x3,%dl
 1065a6d:	0f 85 30 1c 00 00    	jne    10676a3 <my.interpreter::evaluate+0x2a13>
 1065a73:	49 89 c8             	mov    %rcx,%r8
 1065a76:	41 0f b6 d6          	movzbl %r14b,%edx
 1065a7a:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1065a7f:	48 8b 5c 24 40       	mov    0x40(%rsp),%rbx
 1065a84:	48 89 de             	mov    %rbx,%rsi
 1065a87:	4c 89 e1             	mov    %r12,%rcx
 1065a8a:	e8 d1 a6 00 00       	call   1070160 <my.interpreter::bind>
 1065a8f:	48 8b 44 24 60       	mov    0x60(%rsp),%rax
 1065a94:	48 8b 4b 78          	mov    0x78(%rbx),%rcx
 1065a98:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 1065a9f:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065aa3:	48 89 f7             	mov    %rsi,%rdi
 1065aa6:	48 39 d6             	cmp    %rdx,%rsi
 1065aa9:	0f 83 70 16 00 00    	jae    106711f <my.interpreter::evaluate+0x248f>
 1065aaf:	48 c1 e7 04          	shl    $0x4,%rdi
 1065ab3:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 1065aba:	00 00 
 1065abc:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 1065ac1:	48 89 f0             	mov    %rsi,%rax
 1065ac4:	48 ff c0             	inc    %rax
 1065ac7:	48 8b 94 24 28 02 00 	mov    0x228(%rsp),%rdx
 1065ace:	00 
 1065acf:	48 8b bc 24 38 02 00 	mov    0x238(%rsp),%rdi
 1065ad6:	00 
 1065ad7:	0f 80 ec 1c 00 00    	jo     10677c9 <my.interpreter::evaluate+0x2b39>
 1065add:	48 89 83 80 00 00 00 	mov    %rax,0x80(%rbx)
 1065ae4:	31 c0                	xor    %eax,%eax
 1065ae6:	48 8b 2c 24          	mov    (%rsp),%rbp
 1065aea:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1065aee:	48 89 5d 08          	mov    %rbx,0x8(%rbp)
 1065af2:	48 89 75 10          	mov    %rsi,0x10(%rbp)
 1065af6:	48 89 55 18          	mov    %rdx,0x18(%rbp)
 1065afa:	0f b6 84 24 30 02 00 	movzbl 0x230(%rsp),%eax
 1065b01:	00 
 1065b02:	48 89 45 20          	mov    %rax,0x20(%rbp)
 1065b06:	48 89 7d 28          	mov    %rdi,0x28(%rbp)
 1065b0a:	e9 5f 14 00 00       	jmp    1066f6e <my.interpreter::evaluate+0x22de>
 1065b0f:	48 39 d0             	cmp    %rdx,%rax
 1065b12:	0f 83 de 17 00 00    	jae    10672f6 <my.interpreter::evaluate+0x2666>
 1065b18:	48 89 c7             	mov    %rax,%rdi
 1065b1b:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 1065b1f:	83 7c 01 20 09       	cmpl   $0x9,0x20(%rcx,%rax,1)
 1065b24:	0f 85 85 1d 00 00    	jne    10678af <my.interpreter::evaluate+0x2c1f>
 1065b2a:	48 01 c8             	add    %rcx,%rax
 1065b2d:	48 83 c0 20          	add    $0x20,%rax
 1065b31:	48 8b 40 10          	mov    0x10(%rax),%rax
 1065b35:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065b39:	48 39 d6             	cmp    %rdx,%rsi
 1065b3c:	0f 83 d9 17 00 00    	jae    106731b <my.interpreter::evaluate+0x268b>
 1065b42:	48 89 f1             	mov    %rsi,%rcx
 1065b45:	48 c1 e1 04          	shl    $0x4,%rcx
 1065b49:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 1065b4f:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065b53:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065b5a:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065b5e:	48 89 f1             	mov    %rsi,%rcx
 1065b61:	48 39 d6             	cmp    %rdx,%rsi
 1065b64:	0f 83 d3 17 00 00    	jae    106733d <my.interpreter::evaluate+0x26ad>
 1065b6a:	48 c1 e1 04          	shl    $0x4,%rcx
 1065b6e:	c5 f9 54 05 6a e8 f9 	vandpd -0x61796(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 1065b75:	ff 
 1065b76:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 1065b7c:	48 89 f0             	mov    %rsi,%rax
 1065b7f:	48 ff c0             	inc    %rax
 1065b82:	0f 80 33 1d 00 00    	jo     10678bb <my.interpreter::evaluate+0x2c2b>
 1065b88:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065b8f:	31 c0                	xor    %eax,%eax
 1065b91:	e9 c3 01 00 00       	jmp    1065d59 <my.interpreter::evaluate+0x10c9>
 1065b96:	48 8b 8f 80 00 00 00 	mov    0x80(%rdi),%rcx
 1065b9d:	48 89 c8             	mov    %rcx,%rax
 1065ba0:	48 ff c8             	dec    %rax
 1065ba3:	0f 80 23 1d 00 00    	jo     10678cc <my.interpreter::evaluate+0x2c3c>
 1065ba9:	48 8b 4f 78          	mov    0x78(%rdi),%rcx
 1065bad:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065bb1:	48 39 d0             	cmp    %rdx,%rax
 1065bb4:	0f 83 a5 17 00 00    	jae    106735f <my.interpreter::evaluate+0x26cf>
 1065bba:	49 89 c1             	mov    %rax,%r9
 1065bbd:	49 c1 e1 04          	shl    $0x4,%r9
 1065bc1:	4e 8b 44 09 28       	mov    0x28(%rcx,%r9,1),%r8
 1065bc6:	42 8b 4c 09 20       	mov    0x20(%rcx,%r9,1),%ecx
 1065bcb:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 1065bd0:	e8 eb 69 00 00       	call   106c5c0 <my.heap::set_env_slot>
 1065bd5:	e9 88 04 00 00       	jmp    1066062 <my.interpreter::evaluate+0x13d2>
 1065bda:	40 80 fe 02          	cmp    $0x2,%sil
 1065bde:	4c 89 f5             	mov    %r14,%rbp
 1065be1:	0f 85 e4 09 00 00    	jne    10665cb <my.interpreter::evaluate+0x193b>
 1065be7:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 1065bee:	00 00 80 
 1065bf1:	48 31 f2             	xor    %rsi,%rdx
 1065bf4:	48 c7 01 02 00 00 00 	movq   $0x2,(%rcx)
 1065bfb:	48 89 51 08          	mov    %rdx,0x8(%rcx)
 1065bff:	e9 74 08 00 00       	jmp    1066478 <my.interpreter::evaluate+0x17e8>
 1065c04:	4c 89 ff             	mov    %r15,%rdi
 1065c07:	48 89 de             	mov    %rbx,%rsi
 1065c0a:	e8 21 46 00 00       	call   106a230 <my.heap::instance_class>
 1065c0f:	4c 89 ff             	mov    %r15,%rdi
 1065c12:	48 89 c6             	mov    %rax,%rsi
 1065c15:	4c 89 ea             	mov    %r13,%rdx
 1065c18:	89 e9                	mov    %ebp,%ecx
 1065c1a:	e8 01 48 00 00       	call   106a420 <my.heap::class_method>
 1065c1f:	3c 01                	cmp    $0x1,%al
 1065c21:	0f 85 6c 0e 00 00    	jne    1066a93 <my.interpreter::evaluate+0x1e03>
 1065c27:	80 fa 03             	cmp    $0x3,%dl
 1065c2a:	0f 85 b0 1a 00 00    	jne    10676e0 <my.interpreter::evaluate+0x2a50>
 1065c30:	49 89 c8             	mov    %rcx,%r8
 1065c33:	41 0f b6 d6          	movzbl %r14b,%edx
 1065c37:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 1065c3e:	00 
 1065c3f:	4c 8b 7c 24 40       	mov    0x40(%rsp),%r15
 1065c44:	4c 89 fe             	mov    %r15,%rsi
 1065c47:	48 89 d9             	mov    %rbx,%rcx
 1065c4a:	e8 11 a5 00 00       	call   1070160 <my.interpreter::bind>
 1065c4f:	49 8b 87 80 00 00 00 	mov    0x80(%r15),%rax
 1065c56:	48 89 c6             	mov    %rax,%rsi
 1065c59:	48 ff ce             	dec    %rsi
 1065c5c:	48 8b 2c 24          	mov    (%rsp),%rbp
 1065c60:	0f 80 ad 1c 00 00    	jo     1067913 <my.interpreter::evaluate+0x2c83>
 1065c66:	48 8b 8c 24 a0 00 00 	mov    0xa0(%rsp),%rcx
 1065c6d:	00 
 1065c6e:	49 8b 47 78          	mov    0x78(%r15),%rax
 1065c72:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065c76:	48 39 d6             	cmp    %rdx,%rsi
 1065c79:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 1065c7e:	0f 83 00 17 00 00    	jae    1067384 <my.interpreter::evaluate+0x26f4>
 1065c84:	48 89 f7             	mov    %rsi,%rdi
 1065c87:	48 c1 e7 04          	shl    $0x4,%rdi
 1065c8b:	48 8d 34 38          	lea    (%rax,%rdi,1),%rsi
 1065c8f:	48 83 c6 20          	add    $0x20,%rsi
 1065c93:	48 c7 44 38 20 03 00 	movq   $0x3,0x20(%rax,%rdi,1)
 1065c9a:	00 00 
 1065c9c:	48 89 4e 08          	mov    %rcx,0x8(%rsi)
 1065ca0:	49 89 47 78          	mov    %rax,0x78(%r15)
 1065ca4:	31 c0                	xor    %eax,%eax
 1065ca6:	4c 8b 7c 24 38       	mov    0x38(%rsp),%r15
 1065cab:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 1065cb0:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1065cb4:	48 89 5d 08          	mov    %rbx,0x8(%rbp)
 1065cb8:	48 89 55 10          	mov    %rdx,0x10(%rbp)
 1065cbc:	4c 89 7d 18          	mov    %r15,0x18(%rbp)
 1065cc0:	4c 89 6d 20          	mov    %r13,0x20(%rbp)
 1065cc4:	48 89 4d 28          	mov    %rcx,0x28(%rbp)
 1065cc8:	e9 a1 12 00 00       	jmp    1066f6e <my.interpreter::evaluate+0x22de>
 1065ccd:	48 8b 48 20          	mov    0x20(%rax),%rcx
 1065cd1:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
 1065cd6:	48 8b 58 30          	mov    0x30(%rax),%rbx
 1065cda:	4d 8b 79 30          	mov    0x30(%r9),%r15
 1065cde:	4d 8b 61 38          	mov    0x38(%r9),%r12
 1065ce2:	4c 89 cf             	mov    %r9,%rdi
 1065ce5:	48 89 de             	mov    %rbx,%rsi
 1065ce8:	4d 89 ce             	mov    %r9,%r14
 1065ceb:	e8 70 3e 00 00       	call   1069b60 <my.heap::string_hash>
 1065cf0:	4c 89 ff             	mov    %r15,%rdi
 1065cf3:	4c 89 e6             	mov    %r12,%rsi
 1065cf6:	48 89 da             	mov    %rbx,%rdx
 1065cf9:	89 c1                	mov    %eax,%ecx
 1065cfb:	e8 50 3d 00 00       	call   1069a50 <my.table::get>
 1065d00:	3c 01                	cmp    $0x1,%al
 1065d02:	0f 85 01 0e 00 00    	jne    1066b09 <my.interpreter::evaluate+0x1e79>
 1065d08:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 1065d0c:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 1065d13:	48 8b 47 08          	mov    0x8(%rdi),%rax
 1065d17:	49 89 f0             	mov    %rsi,%r8
 1065d1a:	48 39 c6             	cmp    %rax,%rsi
 1065d1d:	0f 83 83 16 00 00    	jae    10673a6 <my.interpreter::evaluate+0x2716>
 1065d23:	49 c1 e0 04          	shl    $0x4,%r8
 1065d27:	0f b6 c2             	movzbl %dl,%eax
 1065d2a:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 1065d2f:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 1065d34:	48 89 f0             	mov    %rsi,%rax
 1065d37:	48 ff c0             	inc    %rax
 1065d3a:	4c 8b 9c 24 28 02 00 	mov    0x228(%rsp),%r11
 1065d41:	00 
 1065d42:	0f 80 df 1b 00 00    	jo     1067927 <my.interpreter::evaluate+0x2c97>
 1065d48:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 1065d4f:	31 c0                	xor    %eax,%eax
 1065d51:	4c 8b b4 24 38 02 00 	mov    0x238(%rsp),%r14
 1065d58:	00 
 1065d59:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1065d5d:	48 89 5d 08          	mov    %rbx,0x8(%rbp)
 1065d61:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 1065d65:	4c 89 5d 18          	mov    %r11,0x18(%rbp)
 1065d69:	0f b6 84 24 30 02 00 	movzbl 0x230(%rsp),%eax
 1065d70:	00 
 1065d71:	48 89 45 20          	mov    %rax,0x20(%rbp)
 1065d75:	4c 89 75 28          	mov    %r14,0x28(%rbp)
 1065d79:	e9 f0 11 00 00       	jmp    1066f6e <my.interpreter::evaluate+0x22de>
 1065d7e:	45 31 f6             	xor    %r14d,%r14d
 1065d81:	4c 8b 4c 24 40       	mov    0x40(%rsp),%r9
 1065d86:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 1065d8b:	49 8b 81 80 00 00 00 	mov    0x80(%r9),%rax
 1065d92:	48 89 c6             	mov    %rax,%rsi
 1065d95:	4c 29 f6             	sub    %r14,%rsi
 1065d98:	48 8b 2c 24          	mov    (%rsp),%rbp
 1065d9c:	0f 80 38 1a 00 00    	jo     10677da <my.interpreter::evaluate+0x2b4a>
 1065da2:	49 89 f5             	mov    %rsi,%r13
 1065da5:	49 ff cd             	dec    %r13
 1065da8:	0f 80 3e 1a 00 00    	jo     10677ec <my.interpreter::evaluate+0x2b5c>
 1065dae:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065db2:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065db6:	4c 89 e9             	mov    %r13,%rcx
 1065db9:	49 39 d5             	cmp    %rdx,%r13
 1065dbc:	0f 83 7f 13 00 00    	jae    1067141 <my.interpreter::evaluate+0x24b1>
 1065dc2:	48 c1 e1 04          	shl    $0x4,%rcx
 1065dc6:	83 7c 08 20 03       	cmpl   $0x3,0x20(%rax,%rcx,1)
 1065dcb:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
 1065dd0:	0f 85 e7 09 00 00    	jne    10667bd <my.interpreter::evaluate+0x1b2d>
 1065dd6:	48 01 c8             	add    %rcx,%rax
 1065dd9:	48 83 c0 20          	add    $0x20,%rax
 1065ddd:	4c 8b 60 08          	mov    0x8(%rax),%r12
 1065de1:	49 8b 01             	mov    (%r9),%rax
 1065de4:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065de8:	4c 89 e1             	mov    %r12,%rcx
 1065deb:	49 39 d4             	cmp    %rdx,%r12
 1065dee:	0f 83 4d 14 00 00    	jae    1067241 <my.interpreter::evaluate+0x25b1>
 1065df4:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065df8:	8b 4c 08 20          	mov    0x20(%rax,%rcx,1),%ecx
 1065dfc:	83 f9 03             	cmp    $0x3,%ecx
 1065dff:	0f 84 31 03 00 00    	je     1066136 <my.interpreter::evaluate+0x14a6>
 1065e05:	83 f9 06             	cmp    $0x6,%ecx
 1065e08:	4c 89 b4 24 90 00 00 	mov    %r14,0x90(%rsp)
 1065e0f:	00 
 1065e10:	0f 84 ac 03 00 00    	je     10661c2 <my.interpreter::evaluate+0x1532>
 1065e16:	83 f9 0a             	cmp    $0xa,%ecx
 1065e19:	0f 85 9e 09 00 00    	jne    10667bd <my.interpreter::evaluate+0x1b2d>
 1065e1f:	49 39 d4             	cmp    %rdx,%r12
 1065e22:	0f 83 c5 15 00 00    	jae    10673ed <my.interpreter::evaluate+0x275d>
 1065e28:	4c 89 e1             	mov    %r12,%rcx
 1065e2b:	48 83 c0 20          	add    $0x20,%rax
 1065e2f:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065e33:	83 3c 08 0a          	cmpl   $0xa,(%rax,%rcx,1)
 1065e37:	0f 85 0f 1b 00 00    	jne    106794c <my.interpreter::evaluate+0x2cbc>
 1065e3d:	48 01 c8             	add    %rcx,%rax
 1065e40:	48 8b 48 08          	mov    0x8(%rax),%rcx
 1065e44:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
 1065e49:	48 8b 68 10          	mov    0x10(%rax),%rbp
 1065e4d:	4c 8b 60 18          	mov    0x18(%rax),%r12
 1065e51:	44 8b 70 20          	mov    0x20(%rax),%r14d
 1065e55:	49 ff c5             	inc    %r13
 1065e58:	48 83 ec 08          	sub    $0x8,%rsp
 1065e5c:	44 0f b6 ff          	movzbl %dil,%r15d
 1065e60:	48 8d bc 24 40 01 00 	lea    0x140(%rsp),%rdi
 1065e67:	00 
 1065e68:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 1065e6d:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 1065e72:	48 89 d9             	mov    %rbx,%rcx
 1065e75:	4c 89 e8             	mov    %r13,%rax
 1065e78:	4d 89 c5             	mov    %r8,%r13
 1065e7b:	ff 74 24 60          	push   0x60(%rsp)
 1065e7f:	50                   	push   %rax
 1065e80:	ff b4 24 a8 00 00 00 	push   0xa8(%rsp)
 1065e87:	41 54                	push   %r12
 1065e89:	4c 89 b4 24 80 00 00 	mov    %r14,0x80(%rsp)
 1065e90:	00 
 1065e91:	41 56                	push   %r14
 1065e93:	4d 89 e6             	mov    %r12,%r14
 1065e96:	41 54                	push   %r12
 1065e98:	48 89 6c 24 40       	mov    %rbp,0x40(%rsp)
 1065e9d:	55                   	push   %rbp
 1065e9e:	ff b4 24 80 00 00 00 	push   0x80(%rsp)
 1065ea5:	41 53                	push   %r11
 1065ea7:	4c 89 7c 24 78       	mov    %r15,0x78(%rsp)
 1065eac:	41 57                	push   %r15
 1065eae:	41 52                	push   %r10
 1065eb0:	4d 89 cc             	mov    %r9,%r12
 1065eb3:	4d 89 d7             	mov    %r10,%r15
 1065eb6:	4c 89 dd             	mov    %r11,%rbp
 1065eb9:	e8 02 c7 00 00       	call   10725c0 <my.interpreter::enter_function>
 1065ebe:	48 83 c4 60          	add    $0x60,%rsp
 1065ec2:	4c 8b 94 24 40 01 00 	mov    0x140(%rsp),%r10
 1065ec9:	00 
 1065eca:	80 bc 24 38 01 00 00 	cmpb   $0x1,0x138(%rsp)
 1065ed1:	01 
 1065ed2:	0f 84 6d 0e 00 00    	je     1066d45 <my.interpreter::evaluate+0x20b5>
 1065ed8:	0f b6 44 24 58       	movzbl 0x58(%rsp),%eax
 1065edd:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 1065ee4:	00 
 1065ee5:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1065eea:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 1065eef:	48 89 d9             	mov    %rbx,%rcx
 1065ef2:	4d 89 e8             	mov    %r13,%r8
 1065ef5:	4d 89 e1             	mov    %r12,%r9
 1065ef8:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 1065eff:	41 52                	push   %r10
 1065f01:	50                   	push   %rax
 1065f02:	41 56                	push   %r14
 1065f04:	ff 74 24 28          	push   0x28(%rsp)
 1065f08:	ff 74 24 68          	push   0x68(%rsp)
 1065f0c:	55                   	push   %rbp
 1065f0d:	ff 74 24 60          	push   0x60(%rsp)
 1065f11:	41 57                	push   %r15
 1065f13:	ff b4 24 68 02 00 00 	push   0x268(%rsp)
 1065f1a:	e8 e1 cb 00 00       	call   1072b00 <my.interpreter::run_function>
 1065f1f:	48 83 c4 50          	add    $0x50,%rsp
 1065f23:	4c 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%r8
 1065f2a:	00 
 1065f2b:	4c 8b b4 24 a8 00 00 	mov    0xa8(%rsp),%r14
 1065f32:	00 
 1065f33:	4c 8b 94 24 b8 00 00 	mov    0xb8(%rsp),%r10
 1065f3a:	00 
 1065f3b:	44 0f b6 ac 24 c0 00 	movzbl 0xc0(%rsp),%r13d
 1065f42:	00 00 
 1065f44:	4c 8b 8c 24 c8 00 00 	mov    0xc8(%rsp),%r9
 1065f4b:	00 
 1065f4c:	80 bc 24 a0 00 00 00 	cmpb   $0x1,0xa0(%rsp)
 1065f53:	01 
 1065f54:	0f 84 13 0e 00 00    	je     1066d6d <my.interpreter::evaluate+0x20dd>
 1065f5a:	49 8b b4 24 80 00 00 	mov    0x80(%r12),%rsi
 1065f61:	00 
 1065f62:	48 89 f0             	mov    %rsi,%rax
 1065f65:	48 8b 94 24 90 00 00 	mov    0x90(%rsp),%rdx
 1065f6c:	00 
 1065f6d:	48 29 d0             	sub    %rdx,%rax
 1065f70:	48 8b 2c 24          	mov    (%rsp),%rbp
 1065f74:	0f 80 24 1a 00 00    	jo     106799e <my.interpreter::evaluate+0x2d0e>
 1065f7a:	49 89 84 24 80 00 00 	mov    %rax,0x80(%r12)
 1065f81:	00 
 1065f82:	48 89 c6             	mov    %rax,%rsi
 1065f85:	48 ff ce             	dec    %rsi
 1065f88:	0f 80 1c 1a 00 00    	jo     10679aa <my.interpreter::evaluate+0x2d1a>
 1065f8e:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1065f93:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065f97:	48 39 d6             	cmp    %rdx,%rsi
 1065f9a:	0f 83 eb 14 00 00    	jae    106748b <my.interpreter::evaluate+0x27fb>
 1065fa0:	48 89 f1             	mov    %rsi,%rcx
 1065fa3:	48 c1 e1 04          	shl    $0x4,%rcx
 1065fa7:	41 0f b6 d6          	movzbl %r14b,%edx
 1065fab:	48 89 54 08 20       	mov    %rdx,0x20(%rax,%rcx,1)
 1065fb0:	4c 89 44 08 28       	mov    %r8,0x28(%rax,%rcx,1)
 1065fb5:	e9 aa 05 00 00       	jmp    1066564 <my.interpreter::evaluate+0x18d4>
 1065fba:	4c 89 6c 24 28       	mov    %r13,0x28(%rsp)
 1065fbf:	4c 8b 6c 24 40       	mov    0x40(%rsp),%r13
 1065fc4:	49 8b 5d 30          	mov    0x30(%r13),%rbx
 1065fc8:	4d 8b 7d 38          	mov    0x38(%r13),%r15
 1065fcc:	4c 89 ef             	mov    %r13,%rdi
 1065fcf:	4c 89 e6             	mov    %r12,%rsi
 1065fd2:	e8 89 3b 00 00       	call   1069b60 <my.heap::string_hash>
 1065fd7:	48 89 df             	mov    %rbx,%rdi
 1065fda:	4c 89 fe             	mov    %r15,%rsi
 1065fdd:	4c 89 e2             	mov    %r12,%rdx
 1065fe0:	89 c1                	mov    %eax,%ecx
 1065fe2:	e8 69 3a 00 00       	call   1069a50 <my.table::get>
 1065fe7:	3c 01                	cmp    $0x1,%al
 1065fe9:	0f 85 a6 0b 00 00    	jne    1066b95 <my.interpreter::evaluate+0x1f05>
 1065fef:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1065ff6:	48 89 c6             	mov    %rax,%rsi
 1065ff9:	48 ff ce             	dec    %rsi
 1065ffc:	0f 80 36 19 00 00    	jo     1067938 <my.interpreter::evaluate+0x2ca8>
 1066002:	4c 89 ef             	mov    %r13,%rdi
 1066005:	4d 89 f5             	mov    %r14,%r13
 1066008:	48 8b 47 78          	mov    0x78(%rdi),%rax
 106600c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1066010:	49 89 ee             	mov    %rbp,%r14
 1066013:	48 39 d6             	cmp    %rdx,%rsi
 1066016:	0f 83 af 13 00 00    	jae    10673cb <my.interpreter::evaluate+0x273b>
 106601c:	48 89 f1             	mov    %rsi,%rcx
 106601f:	48 c1 e1 04          	shl    $0x4,%rcx
 1066023:	48 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%rbx
 1066028:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 106602c:	4c 89 e6             	mov    %r12,%rsi
 106602f:	49 89 ff             	mov    %rdi,%r15
 1066032:	e8 29 3b 00 00       	call   1069b60 <my.heap::string_hash>
 1066037:	49 8b 7f 30          	mov    0x30(%r15),%rdi
 106603b:	49 8b 77 38          	mov    0x38(%r15),%rsi
 106603f:	4c 89 e2             	mov    %r12,%rdx
 1066042:	89 c1                	mov    %eax,%ecx
 1066044:	41 89 e8             	mov    %ebp,%r8d
 1066047:	49 89 d9             	mov    %rbx,%r9
 106604a:	e8 f1 3b 00 00       	call   1069c40 <my.table::set>
 106604f:	49 89 57 30          	mov    %rdx,0x30(%r15)
 1066053:	49 89 4f 38          	mov    %rcx,0x38(%r15)
 1066057:	4c 89 f5             	mov    %r14,%rbp
 106605a:	4d 89 ee             	mov    %r13,%r14
 106605d:	4c 8b 6c 24 28       	mov    0x28(%rsp),%r13
 1066062:	31 c0                	xor    %eax,%eax
 1066064:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1066069:	48 89 45 00          	mov    %rax,0x0(%rbp)
 106606d:	48 89 5d 08          	mov    %rbx,0x8(%rbp)
 1066071:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 1066075:	4c 89 75 18          	mov    %r14,0x18(%rbp)
 1066079:	4c 89 6d 20          	mov    %r13,0x20(%rbp)
 106607d:	4c 89 45 28          	mov    %r8,0x28(%rbp)
 1066081:	e9 e8 0e 00 00       	jmp    1066f6e <my.interpreter::evaluate+0x22de>
 1066086:	48 01 f8             	add    %rdi,%rax
 1066089:	48 83 c0 20          	add    $0x20,%rax
 106608d:	83 fd 1e             	cmp    $0x1e,%ebp
 1066090:	0f 95 c2             	setne  %dl
 1066093:	32 50 08             	xor    0x8(%rax),%dl
 1066096:	f6 c2 01             	test   $0x1,%dl
 1066099:	0f 84 d3 f5 ff ff    	je     1065672 <my.interpreter::evaluate+0x9e2>
 106609f:	31 c0                	xor    %eax,%eax
 10660a1:	48 8b 2c 24          	mov    (%rsp),%rbp
 10660a5:	48 89 45 00          	mov    %rax,0x0(%rbp)
 10660a9:	c5 f9 11 45 08       	vmovupd %xmm0,0x8(%rbp)
 10660ae:	4c 89 55 18          	mov    %r10,0x18(%rbp)
 10660b2:	4c 89 75 20          	mov    %r14,0x20(%rbp)
 10660b6:	e9 d7 03 00 00       	jmp    1066492 <my.interpreter::evaluate+0x1802>
 10660bb:	83 fd 1e             	cmp    $0x1e,%ebp
 10660be:	0f 85 ae f5 ff ff    	jne    1065672 <my.interpreter::evaluate+0x9e2>
 10660c4:	eb d9                	jmp    106609f <my.interpreter::evaluate+0x140f>
 10660c6:	3c 02                	cmp    $0x2,%al
 10660c8:	0f 84 87 05 00 00    	je     1066655 <my.interpreter::evaluate+0x19c5>
 10660ce:	0f b6 c0             	movzbl %al,%eax
 10660d1:	83 f8 01             	cmp    $0x1,%eax
 10660d4:	0f 84 30 05 00 00    	je     106660a <my.interpreter::evaluate+0x197a>
 10660da:	85 c0                	test   %eax,%eax
 10660dc:	0f 85 98 05 00 00    	jne    106667a <my.interpreter::evaluate+0x19ea>
 10660e2:	40 84 ed             	test   %bpl,%bpl
 10660e5:	41 0f 94 c4          	sete   %r12b
 10660e9:	e9 9d 05 00 00       	jmp    106668b <my.interpreter::evaluate+0x19fb>
 10660ee:	89 c1                	mov    %eax,%ecx
 10660f0:	80 f1 02             	xor    $0x2,%cl
 10660f3:	c4 c1 f9 6e c5       	vmovq  %r13,%xmm0
 10660f8:	89 ea                	mov    %ebp,%edx
 10660fa:	80 f2 02             	xor    $0x2,%dl
 10660fd:	c4 c1 f9 6e cc       	vmovq  %r12,%xmm1
 1066102:	08 ca                	or     %cl,%dl
 1066104:	0f 94 c1             	sete   %cl
 1066107:	83 fe 07             	cmp    $0x7,%esi
 106610a:	0f 85 8b 03 00 00    	jne    106649b <my.interpreter::evaluate+0x180b>
 1066110:	84 c9                	test   %cl,%cl
 1066112:	0f 84 f1 05 00 00    	je     1066709 <my.interpreter::evaluate+0x1a79>
 1066118:	c5 fb 58 c1          	vaddsd %xmm1,%xmm0,%xmm0
 106611c:	c4 e1 f9 7e c2       	vmovq  %xmm0,%rdx
 1066121:	b0 02                	mov    $0x2,%al
 1066123:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066127:	41 f6 c7 01          	test   $0x1,%r15b
 106612b:	0f 84 74 05 00 00    	je     10666a5 <my.interpreter::evaluate+0x1a15>
 1066131:	e9 73 06 00 00       	jmp    10667a9 <my.interpreter::evaluate+0x1b19>
 1066136:	4c 89 5c 24 08       	mov    %r11,0x8(%rsp)
 106613b:	4d 89 d5             	mov    %r10,%r13
 106613e:	4c 89 cf             	mov    %r9,%rdi
 1066141:	4c 89 e6             	mov    %r12,%rsi
 1066144:	4c 89 cb             	mov    %r9,%rbx
 1066147:	e8 04 45 00 00       	call   106a650 <my.heap::native_obj>
 106614c:	49 39 d6             	cmp    %rdx,%r14
 106614f:	0f 85 c6 0a 00 00    	jne    1066c1b <my.interpreter::evaluate+0x1f8b>
 1066155:	48 89 c7             	mov    %rax,%rdi
 1066158:	48 8b b4 24 48 02 00 	mov    0x248(%rsp),%rsi
 106615f:	00 
 1066160:	e8 cb 45 00 00       	call   106a730 <my.natives::call_native>
 1066165:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 106616c:	48 89 f1             	mov    %rsi,%rcx
 106616f:	4c 29 f1             	sub    %r14,%rcx
 1066172:	0f 80 e0 17 00 00    	jo     1067958 <my.interpreter::evaluate+0x2cc8>
 1066178:	48 89 8b 80 00 00 00 	mov    %rcx,0x80(%rbx)
 106617f:	48 89 ce             	mov    %rcx,%rsi
 1066182:	48 ff ce             	dec    %rsi
 1066185:	4c 8b 4c 24 08       	mov    0x8(%rsp),%r9
 106618a:	0f 80 d7 17 00 00    	jo     1067967 <my.interpreter::evaluate+0x2cd7>
 1066190:	4d 89 ea             	mov    %r13,%r10
 1066193:	48 8b 7b 78          	mov    0x78(%rbx),%rdi
 1066197:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 106619b:	48 39 ce             	cmp    %rcx,%rsi
 106619e:	0f 83 a0 12 00 00    	jae    1067444 <my.interpreter::evaluate+0x27b4>
 10661a4:	49 89 f0             	mov    %rsi,%r8
 10661a7:	49 c1 e0 04          	shl    $0x4,%r8
 10661ab:	0f b6 c0             	movzbl %al,%eax
 10661ae:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 10661b3:	4a 89 54 07 28       	mov    %rdx,0x28(%rdi,%r8,1)
 10661b8:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 10661bd:	e9 a2 03 00 00       	jmp    1066564 <my.interpreter::evaluate+0x18d4>
 10661c2:	4c 89 5c 24 08       	mov    %r11,0x8(%rsp)
 10661c7:	4c 89 94 24 98 00 00 	mov    %r10,0x98(%rsp)
 10661ce:	00 
 10661cf:	48 8d bc 24 00 01 00 	lea    0x100(%rsp),%rdi
 10661d6:	00 
 10661d7:	4c 89 ce             	mov    %r9,%rsi
 10661da:	4c 89 e2             	mov    %r12,%rdx
 10661dd:	e8 2e 43 00 00       	call   106a510 <my.heap::allocate_instance>
 10661e2:	4c 8b 74 24 40       	mov    0x40(%rsp),%r14
 10661e7:	4c 8b bc 24 00 01 00 	mov    0x100(%rsp),%r15
 10661ee:	00 
 10661ef:	49 8b 46 78          	mov    0x78(%r14),%rax
 10661f3:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10661f7:	4c 89 e9             	mov    %r13,%rcx
 10661fa:	4c 89 ac 24 d0 00 00 	mov    %r13,0xd0(%rsp)
 1066201:	00 
 1066202:	49 39 d5             	cmp    %rdx,%r13
 1066205:	0f 83 07 12 00 00    	jae    1067412 <my.interpreter::evaluate+0x2782>
 106620b:	48 c1 e1 04          	shl    $0x4,%rcx
 106620f:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 1066216:	00 00 
 1066218:	4c 89 7c 08 28       	mov    %r15,0x28(%rax,%rcx,1)
 106621d:	4d 8b 6e 40          	mov    0x40(%r14),%r13
 1066221:	4c 89 f7             	mov    %r14,%rdi
 1066224:	4c 89 ee             	mov    %r13,%rsi
 1066227:	e8 34 39 00 00       	call   1069b60 <my.heap::string_hash>
 106622c:	4c 89 f7             	mov    %r14,%rdi
 106622f:	4c 89 e6             	mov    %r12,%rsi
 1066232:	4c 89 ea             	mov    %r13,%rdx
 1066235:	89 c1                	mov    %eax,%ecx
 1066237:	e8 e4 41 00 00       	call   106a420 <my.heap::class_method>
 106623c:	3c 01                	cmp    $0x1,%al
 106623e:	4c 89 bc 24 f0 00 00 	mov    %r15,0xf0(%rsp)
 1066245:	00 
 1066246:	0f 85 94 02 00 00    	jne    10664e0 <my.interpreter::evaluate+0x1850>
 106624c:	89 d7                	mov    %edx,%edi
 106624e:	48 89 ce             	mov    %rcx,%rsi
 1066251:	e8 2a 63 00 00       	call   106c580 <my.interpreter::as_obj>
 1066256:	48 8d bc 24 68 01 00 	lea    0x168(%rsp),%rdi
 106625d:	00 
 106625e:	4c 89 f6             	mov    %r14,%rsi
 1066261:	48 89 c2             	mov    %rax,%rdx
 1066264:	e8 d7 c2 00 00       	call   1072540 <my.heap::tree_function_obj>
 1066269:	0f b6 ac 24 80 01 00 	movzbl 0x180(%rsp),%ebp
 1066270:	00 
 1066271:	48 8b 94 24 78 01 00 	mov    0x178(%rsp),%rdx
 1066278:	00 
 1066279:	48 8b 84 24 68 01 00 	mov    0x168(%rsp),%rax
 1066280:	00 
 1066281:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
 1066288:	00 
 1066289:	48 8b 84 24 70 01 00 	mov    0x170(%rsp),%rax
 1066290:	00 
 1066291:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
 1066298:	00 
 1066299:	48 8d bc 24 f8 00 00 	lea    0xf8(%rsp),%rdi
 10662a0:	00 
 10662a1:	b9 01 00 00 00       	mov    $0x1,%ecx
 10662a6:	4c 89 f6             	mov    %r14,%rsi
 10662a9:	48 89 94 24 d8 00 00 	mov    %rdx,0xd8(%rsp)
 10662b0:	00 
 10662b1:	e8 7a 61 00 00       	call   106c430 <my.interpreter::new_env>
 10662b6:	4c 8b a4 24 f8 00 00 	mov    0xf8(%rsp),%r12
 10662bd:	00 
 10662be:	4c 89 f7             	mov    %r14,%rdi
 10662c1:	4c 89 e6             	mov    %r12,%rsi
 10662c4:	31 d2                	xor    %edx,%edx
 10662c6:	b9 03 00 00 00       	mov    $0x3,%ecx
 10662cb:	4d 89 f8             	mov    %r15,%r8
 10662ce:	e8 ed 62 00 00       	call   106c5c0 <my.heap::set_env_slot>
 10662d3:	49 8b 46 78          	mov    0x78(%r14),%rax
 10662d7:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 10662de:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10662e2:	48 89 f1             	mov    %rsi,%rcx
 10662e5:	48 39 d6             	cmp    %rdx,%rsi
 10662e8:	4d 89 f1             	mov    %r14,%r9
 10662eb:	0f 83 bc 11 00 00    	jae    10674ad <my.interpreter::evaluate+0x281d>
 10662f1:	48 c1 e1 04          	shl    $0x4,%rcx
 10662f5:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 10662fc:	00 00 
 10662fe:	4c 89 64 08 28       	mov    %r12,0x28(%rax,%rcx,1)
 1066303:	48 89 f0             	mov    %rsi,%rax
 1066306:	48 ff c0             	inc    %rax
 1066309:	4c 8b 94 24 98 00 00 	mov    0x98(%rsp),%r10
 1066310:	00 
 1066311:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 1066316:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 106631b:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 1066320:	4c 8b b4 24 90 00 00 	mov    0x90(%rsp),%r14
 1066327:	00 
 1066328:	0f 80 90 16 00 00    	jo     10679be <my.interpreter::evaluate+0x2d2e>
 106632e:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1066335:	48 8b 84 24 d0 00 00 	mov    0xd0(%rsp),%rax
 106633c:	00 
 106633d:	48 ff c0             	inc    %rax
 1066340:	48 83 ec 08          	sub    $0x8,%rsp
 1066344:	44 0f b6 e9          	movzbl %cl,%r13d
 1066348:	40 0f b6 ed          	movzbl %bpl,%ebp
 106634c:	48 8d bc 24 58 01 00 	lea    0x158(%rsp),%rdi
 1066353:	00 
 1066354:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 1066359:	48 8b 54 24 40       	mov    0x40(%rsp),%rdx
 106635e:	48 89 d9             	mov    %rbx,%rcx
 1066361:	ff 74 24 60          	push   0x60(%rsp)
 1066365:	50                   	push   %rax
 1066366:	41 56                	push   %r14
 1066368:	41 54                	push   %r12
 106636a:	55                   	push   %rbp
 106636b:	ff b4 24 08 01 00 00 	push   0x108(%rsp)
 1066372:	ff b4 24 20 01 00 00 	push   0x120(%rsp)
 1066379:	ff b4 24 20 01 00 00 	push   0x120(%rsp)
 1066380:	41 53                	push   %r11
 1066382:	41 55                	push   %r13
 1066384:	41 52                	push   %r10
 1066386:	4d 89 ce             	mov    %r9,%r14
 1066389:	e8 32 c2 00 00       	call   10725c0 <my.interpreter::enter_function>
 106638e:	48 83 c4 60          	add    $0x60,%rsp
 1066392:	4c 8b a4 24 58 01 00 	mov    0x158(%rsp),%r12
 1066399:	00 
 106639a:	80 bc 24 50 01 00 00 	cmpb   $0x1,0x150(%rsp)
 10663a1:	01 
 10663a2:	0f 84 20 0b 00 00    	je     1066ec8 <my.interpreter::evaluate+0x2238>
 10663a8:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 10663af:	48 89 c6             	mov    %rax,%rsi
 10663b2:	48 ff ce             	dec    %rsi
 10663b5:	0f 80 14 16 00 00    	jo     10679cf <my.interpreter::evaluate+0x2d3f>
 10663bb:	4d 89 f1             	mov    %r14,%r9
 10663be:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 10663c5:	49 8b 46 78          	mov    0x78(%r14),%rax
 10663c9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10663cd:	48 39 d6             	cmp    %rdx,%rsi
 10663d0:	4c 8b bc 24 98 00 00 	mov    0x98(%rsp),%r15
 10663d7:	00 
 10663d8:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10663dd:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 10663e2:	4c 8b 9c 24 48 02 00 	mov    0x248(%rsp),%r11
 10663e9:	00 
 10663ea:	4c 8b b4 24 90 00 00 	mov    0x90(%rsp),%r14
 10663f1:	00 
 10663f2:	0f 83 d7 10 00 00    	jae    10674cf <my.interpreter::evaluate+0x283f>
 10663f8:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 10663fd:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1066402:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 1066407:	48 89 d9             	mov    %rbx,%rcx
 106640a:	41 53                	push   %r11
 106640c:	41 54                	push   %r12
 106640e:	55                   	push   %rbp
 106640f:	ff b4 24 f0 00 00 00 	push   0xf0(%rsp)
 1066416:	ff b4 24 08 01 00 00 	push   0x108(%rsp)
 106641d:	ff b4 24 08 01 00 00 	push   0x108(%rsp)
 1066424:	41 52                	push   %r10
 1066426:	41 55                	push   %r13
 1066428:	41 57                	push   %r15
 106642a:	ff b4 24 68 02 00 00 	push   0x268(%rsp)
 1066431:	e8 ca c6 00 00       	call   1072b00 <my.interpreter::run_function>
 1066436:	48 83 c4 50          	add    $0x50,%rsp
 106643a:	4c 8b 54 24 78       	mov    0x78(%rsp),%r10
 106643f:	0f b6 84 24 80 00 00 	movzbl 0x80(%rsp),%eax
 1066446:	00 
 1066447:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 106644c:	4c 8b 8c 24 88 00 00 	mov    0x88(%rsp),%r9
 1066453:	00 
 1066454:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 1066459:	0f 84 8e 0a 00 00    	je     1066eed <my.interpreter::evaluate+0x225d>
 106645f:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066463:	e9 96 00 00 00       	jmp    10664fe <my.interpreter::evaluate+0x186e>
 1066468:	b2 01                	mov    $0x1,%dl
 106646a:	eb 02                	jmp    106646e <my.interpreter::evaluate+0x17de>
 106646c:	31 d2                	xor    %edx,%edx
 106646e:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 1066475:	88 51 08             	mov    %dl,0x8(%rcx)
 1066478:	48 89 43 78          	mov    %rax,0x78(%rbx)
 106647c:	31 c9                	xor    %ecx,%ecx
 106647e:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 1066482:	48 89 45 08          	mov    %rax,0x8(%rbp)
 1066486:	4c 89 65 10          	mov    %r12,0x10(%rbp)
 106648a:	4c 89 4d 18          	mov    %r9,0x18(%rbp)
 106648e:	4c 89 6d 20          	mov    %r13,0x20(%rbp)
 1066492:	4c 89 7d 28          	mov    %r15,0x28(%rbp)
 1066496:	e9 d3 0a 00 00       	jmp    1066f6e <my.interpreter::evaluate+0x22de>
 106649b:	45 89 fd             	mov    %r15d,%r13d
 106649e:	4c 89 5c 24 10       	mov    %r11,0x10(%rsp)
 10664a3:	4d 89 d7             	mov    %r10,%r15
 10664a6:	84 c9                	test   %cl,%cl
 10664a8:	0f 84 de 08 00 00    	je     1066d8c <my.interpreter::evaluate+0x20fc>
 10664ae:	40 0f b6 fe          	movzbl %sil,%edi
 10664b2:	4d 89 cc             	mov    %r9,%r12
 10664b5:	e8 46 9c 00 00       	call   1070100 <my.interpreter::arithmetic>
 10664ba:	4d 89 e1             	mov    %r12,%r9
 10664bd:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 10664c2:	48 8b 2c 24          	mov    (%rsp),%rbp
 10664c6:	4d 89 fa             	mov    %r15,%r10
 10664c9:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 10664ce:	45 89 ef             	mov    %r13d,%r15d
 10664d1:	41 f6 c7 01          	test   $0x1,%r15b
 10664d5:	0f 84 ca 01 00 00    	je     10666a5 <my.interpreter::evaluate+0x1a15>
 10664db:	e9 c9 02 00 00       	jmp    10667a9 <my.interpreter::evaluate+0x1b19>
 10664e0:	4c 8b b4 24 90 00 00 	mov    0x90(%rsp),%r14
 10664e7:	00 
 10664e8:	4d 85 f6             	test   %r14,%r14
 10664eb:	4c 8b 94 24 98 00 00 	mov    0x98(%rsp),%r10
 10664f2:	00 
 10664f3:	4c 8b 4c 24 08       	mov    0x8(%rsp),%r9
 10664f8:	0f 85 da 08 00 00    	jne    1066dd8 <my.interpreter::evaluate+0x2148>
 10664fe:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1066503:	48 8b b7 80 00 00 00 	mov    0x80(%rdi),%rsi
 106650a:	48 89 f0             	mov    %rsi,%rax
 106650d:	4c 29 f0             	sub    %r14,%rax
 1066510:	0f 80 65 14 00 00    	jo     106797b <my.interpreter::evaluate+0x2ceb>
 1066516:	48 89 87 80 00 00 00 	mov    %rax,0x80(%rdi)
 106651d:	48 89 c6             	mov    %rax,%rsi
 1066520:	48 ff ce             	dec    %rsi
 1066523:	0f 80 61 14 00 00    	jo     106798a <my.interpreter::evaluate+0x2cfa>
 1066529:	48 8b 47 78          	mov    0x78(%rdi),%rax
 106652d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1066531:	48 39 d6             	cmp    %rdx,%rsi
 1066534:	0f 83 2f 0f 00 00    	jae    1067469 <my.interpreter::evaluate+0x27d9>
 106653a:	48 89 f1             	mov    %rsi,%rcx
 106653d:	48 c1 e1 04          	shl    $0x4,%rcx
 1066541:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 1066548:	00 00 
 106654a:	48 8b 94 24 f0 00 00 	mov    0xf0(%rsp),%rdx
 1066551:	00 
 1066552:	48 89 54 08 28       	mov    %rdx,0x28(%rax,%rcx,1)
 1066557:	48 89 47 78          	mov    %rax,0x78(%rdi)
 106655b:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 1066560:	45 0f b6 ed          	movzbl %r13b,%r13d
 1066564:	31 c0                	xor    %eax,%eax
 1066566:	e9 ee 09 00 00       	jmp    1066f59 <my.interpreter::evaluate+0x22c9>
 106656b:	48 8d 3d 4e bb fa ff 	lea    -0x544b2(%rip),%rdi        # 10120c0 <core_number_pairs+0xae40>
 1066572:	e8 49 da fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066577:	48 89 c3             	mov    %rax,%rbx
 106657a:	48 8d 3d cf ea 01 00 	lea    0x1eacf(%rip),%rdi        # 1085050 <core_durable_error.verbs+0x6150>
 1066581:	e8 fa 02 ff ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066586:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 106658b:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 1066590:	e9 aa 02 00 00       	jmp    106683f <my.interpreter::evaluate+0x1baf>
 1066595:	48 8d 3d 64 bb fa ff 	lea    -0x5449c(%rip),%rdi        # 1012100 <core_number_pairs+0xae80>
 106659c:	e8 1f da fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 10665a1:	48 8d 3d e8 ec 01 00 	lea    0x1ece8(%rip),%rdi        # 1085290 <core_durable_error.verbs+0x6390>
 10665a8:	e8 d3 02 ff ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 10665ad:	c5 fa 7e 44 24 58    	vmovq  0x58(%rsp),%xmm0
 10665b3:	c4 e1 f9 6e c8       	vmovq  %rax,%xmm1
 10665b8:	c5 f1 6c c0          	vpunpcklqdq %xmm0,%xmm1,%xmm0
 10665bc:	c5 f9 7f 44 24 40    	vmovdqa %xmm0,0x40(%rsp)
 10665c2:	48 8b 0c 24          	mov    (%rsp),%rcx
 10665c6:	e9 24 04 00 00       	jmp    10669ef <my.interpreter::evaluate+0x1d5f>
 10665cb:	40 0f b6 c6          	movzbl %sil,%eax
 10665cf:	83 f8 01             	cmp    $0x1,%eax
 10665d2:	0f 84 71 04 00 00    	je     1066a49 <my.interpreter::evaluate+0x1db9>
 10665d8:	4c 89 cb             	mov    %r9,%rbx
 10665db:	48 8d 3d fe bb fa ff 	lea    -0x54402(%rip),%rdi        # 10121e0 <core_number_pairs+0xaf60>
 10665e2:	85 c0                	test   %eax,%eax
 10665e4:	0f 85 7f 04 00 00    	jne    1066a69 <my.interpreter::evaluate+0x1dd9>
 10665ea:	e8 d1 d9 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 10665ef:	48 8d 3d fa ef 01 00 	lea    0x1effa(%rip),%rdi        # 10855f0 <core_durable_error.verbs+0x66f0>
 10665f6:	e9 7a 04 00 00       	jmp    1066a75 <my.interpreter::evaluate+0x1de5>
 10665fb:	40 80 fd 01          	cmp    $0x1,%bpl
 10665ff:	75 38                	jne    1066639 <my.interpreter::evaluate+0x19a9>
 1066601:	45 31 ec             	xor    %r13d,%r12d
 1066604:	41 80 f4 01          	xor    $0x1,%r12b
 1066608:	eb 45                	jmp    106664f <my.interpreter::evaluate+0x19bf>
 106660a:	40 80 fd 01          	cmp    $0x1,%bpl
 106660e:	75 65                	jne    1066675 <my.interpreter::evaluate+0x19e5>
 1066610:	45 31 ec             	xor    %r13d,%r12d
 1066613:	41 80 f4 01          	xor    $0x1,%r12b
 1066617:	eb 72                	jmp    106668b <my.interpreter::evaluate+0x19fb>
 1066619:	40 80 fd 02          	cmp    $0x2,%bpl
 106661d:	75 1a                	jne    1066639 <my.interpreter::evaluate+0x19a9>
 106661f:	c4 c1 f9 6e c5       	vmovq  %r13,%xmm0
 1066624:	c4 c1 f9 6e cc       	vmovq  %r12,%xmm1
 1066629:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 106662e:	c4 c1 f9 7e c4       	vmovq  %xmm0,%r12
 1066633:	41 83 e4 01          	and    $0x1,%r12d
 1066637:	eb 16                	jmp    106664f <my.interpreter::evaluate+0x19bf>
 1066639:	45 31 e4             	xor    %r12d,%r12d
 106663c:	eb 11                	jmp    106664f <my.interpreter::evaluate+0x19bf>
 106663e:	40 80 fd 03          	cmp    $0x3,%bpl
 1066642:	0f 94 c0             	sete   %al
 1066645:	4d 39 e5             	cmp    %r12,%r13
 1066648:	41 0f 94 c4          	sete   %r12b
 106664c:	41 20 c4             	and    %al,%r12b
 106664f:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066653:	eb 3d                	jmp    1066692 <my.interpreter::evaluate+0x1a02>
 1066655:	40 80 fd 02          	cmp    $0x2,%bpl
 1066659:	75 1a                	jne    1066675 <my.interpreter::evaluate+0x19e5>
 106665b:	c4 c1 f9 6e c5       	vmovq  %r13,%xmm0
 1066660:	c4 c1 f9 6e cc       	vmovq  %r12,%xmm1
 1066665:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 106666a:	c4 c1 f9 7e c4       	vmovq  %xmm0,%r12
 106666f:	41 83 e4 01          	and    $0x1,%r12d
 1066673:	eb 16                	jmp    106668b <my.interpreter::evaluate+0x19fb>
 1066675:	45 31 e4             	xor    %r12d,%r12d
 1066678:	eb 11                	jmp    106668b <my.interpreter::evaluate+0x19fb>
 106667a:	40 80 fd 03          	cmp    $0x3,%bpl
 106667e:	0f 94 c0             	sete   %al
 1066681:	4d 39 e5             	cmp    %r12,%r13
 1066684:	41 0f 94 c4          	sete   %r12b
 1066688:	41 20 c4             	and    %al,%r12b
 106668b:	48 8b 2c 24          	mov    (%rsp),%rbp
 106668f:	41 f6 d4             	not    %r12b
 1066692:	41 0f b6 d4          	movzbl %r12b,%edx
 1066696:	83 e2 01             	and    $0x1,%edx
 1066699:	b0 01                	mov    $0x1,%al
 106669b:	41 f6 c7 01          	test   $0x1,%r15b
 106669f:	0f 85 04 01 00 00    	jne    10667a9 <my.interpreter::evaluate+0x1b19>
 10666a5:	48 89 9f 80 00 00 00 	mov    %rbx,0x80(%rdi)
 10666ac:	4c 8b 4f 78          	mov    0x78(%rdi),%r9
 10666b0:	49 8b 49 08          	mov    0x8(%r9),%rcx
 10666b4:	48 39 cb             	cmp    %rcx,%rbx
 10666b7:	0f 83 37 0b 00 00    	jae    10671f4 <my.interpreter::evaluate+0x2564>
 10666bd:	48 89 de             	mov    %rbx,%rsi
 10666c0:	48 ff ce             	dec    %rsi
 10666c3:	0f 80 5c 11 00 00    	jo     1067825 <my.interpreter::evaluate+0x2b95>
 10666c9:	48 39 ce             	cmp    %rcx,%rsi
 10666cc:	0f 83 4a 0b 00 00    	jae    106721c <my.interpreter::evaluate+0x258c>
 10666d2:	49 89 f0             	mov    %rsi,%r8
 10666d5:	49 c1 e0 04          	shl    $0x4,%r8
 10666d9:	0f b6 c0             	movzbl %al,%eax
 10666dc:	4b 89 44 01 20       	mov    %rax,0x20(%r9,%r8,1)
 10666e1:	4b 89 54 01 28       	mov    %rdx,0x28(%r9,%r8,1)
 10666e6:	4c 89 4f 78          	mov    %r9,0x78(%rdi)
 10666ea:	31 c9                	xor    %ecx,%ecx
 10666ec:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 10666f0:	48 89 45 08          	mov    %rax,0x8(%rbp)
 10666f4:	48 89 55 10          	mov    %rdx,0x10(%rbp)
 10666f8:	4c 89 55 18          	mov    %r10,0x18(%rbp)
 10666fc:	4c 89 5d 20          	mov    %r11,0x20(%rbp)
 1066700:	4c 89 75 28          	mov    %r14,0x28(%rbp)
 1066704:	e9 65 08 00 00       	jmp    1066f6e <my.interpreter::evaluate+0x22de>
 1066709:	4c 89 5c 24 10       	mov    %r11,0x10(%rsp)
 106670e:	4c 89 54 24 40       	mov    %r10,0x40(%rsp)
 1066713:	0f b6 d8             	movzbl %al,%ebx
 1066716:	89 de                	mov    %ebx,%esi
 1066718:	4c 89 ea             	mov    %r13,%rdx
 106671b:	49 89 ff             	mov    %rdi,%r15
 106671e:	e8 8d 99 00 00       	call   10700b0 <my.interpreter::is_string>
 1066723:	a8 01                	test   $0x1,%al
 1066725:	0f 84 82 06 00 00    	je     1066dad <my.interpreter::evaluate+0x211d>
 106672b:	40 0f b6 ed          	movzbl %bpl,%ebp
 106672f:	4c 89 ff             	mov    %r15,%rdi
 1066732:	89 ee                	mov    %ebp,%esi
 1066734:	4c 89 e2             	mov    %r12,%rdx
 1066737:	e8 74 99 00 00       	call   10700b0 <my.interpreter::is_string>
 106673c:	a8 01                	test   $0x1,%al
 106673e:	0f 84 69 06 00 00    	je     1066dad <my.interpreter::evaluate+0x211d>
 1066744:	89 df                	mov    %ebx,%edi
 1066746:	4c 89 ee             	mov    %r13,%rsi
 1066749:	e8 32 5e 00 00       	call   106c580 <my.interpreter::as_obj>
 106674e:	48 89 c3             	mov    %rax,%rbx
 1066751:	89 ef                	mov    %ebp,%edi
 1066753:	4c 89 e6             	mov    %r12,%rsi
 1066756:	e8 25 5e 00 00       	call   106c580 <my.interpreter::as_obj>
 106675b:	48 8d bc 24 08 01 00 	lea    0x108(%rsp),%rdi
 1066762:	00 
 1066763:	4c 89 fe             	mov    %r15,%rsi
 1066766:	48 89 da             	mov    %rbx,%rdx
 1066769:	48 89 c1             	mov    %rax,%rcx
 106676c:	e8 4f 79 00 00       	call   106e0c0 <my.lox_strings::concat>
 1066771:	48 8b 94 24 08 01 00 	mov    0x108(%rsp),%rdx
 1066778:	00 
 1066779:	b0 03                	mov    $0x3,%al
 106677b:	4d 8b 8f 80 00 00 00 	mov    0x80(%r15),%r9
 1066782:	4c 89 cb             	mov    %r9,%rbx
 1066785:	48 ff cb             	dec    %rbx
 1066788:	0f 90 c1             	seto   %cl
 106678b:	48 8b 2c 24          	mov    (%rsp),%rbp
 106678f:	4c 89 ff             	mov    %r15,%rdi
 1066792:	41 89 cf             	mov    %ecx,%r15d
 1066795:	4c 8b 54 24 40       	mov    0x40(%rsp),%r10
 106679a:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 106679f:	41 f6 c7 01          	test   $0x1,%r15b
 10667a3:	0f 84 fc fe ff ff    	je     10666a5 <my.interpreter::evaluate+0x1a15>
 10667a9:	48 8d 3d f0 e6 01 00 	lea    0x1e6f0(%rip),%rdi        # 1084ea0 <core_durable_error.verbs+0x5fa0>
 10667b0:	ba 01 00 00 00       	mov    $0x1,%edx
 10667b5:	4c 89 ce             	mov    %r9,%rsi
 10667b8:	e8 03 dd fb ff       	call   10244c0 <myl_core_trap>
 10667bd:	4c 89 5c 24 08       	mov    %r11,0x8(%rsp)
 10667c2:	48 8d 3d 57 ba fa ff 	lea    -0x545a9(%rip),%rdi        # 1012220 <core_number_pairs+0xafa0>
 10667c9:	4c 89 d3             	mov    %r10,%rbx
 10667cc:	e8 ef d7 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 10667d1:	49 89 da             	mov    %rbx,%r10
 10667d4:	49 89 c6             	mov    %rax,%r14
 10667d7:	48 8d 3d 62 04 02 00 	lea    0x20462(%rip),%rdi        # 1086c40 <core_durable_error.verbs+0x7d40>
 10667de:	e8 9d 00 ff ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 10667e3:	4c 8b 44 24 58       	mov    0x58(%rsp),%r8
 10667e8:	e9 2b 07 00 00       	jmp    1066f18 <my.interpreter::evaluate+0x2288>
 10667ed:	48 8d 3d 2c b8 01 00 	lea    0x1b82c(%rip),%rdi        # 1082020 <core_durable_error.verbs+0x3120>
 10667f4:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 10667fa:	e8 c1 00 ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 10667ff:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 1066805:	e9 60 e6 ff ff       	jmp    1064e6a <my.interpreter::evaluate+0x1da>
 106680a:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
 106680f:	4c 89 5c 24 08       	mov    %r11,0x8(%rsp)
 1066814:	48 8d 3d 75 e7 01 00 	lea    0x1e775(%rip),%rdi        # 1084f90 <core_durable_error.verbs+0x6090>
 106681b:	c5 fa 6f 84 24 10 01 	vmovdqu 0x110(%rsp),%xmm0
 1066822:	00 00 
 1066824:	e9 11 02 00 00       	jmp    1066a3a <my.interpreter::evaluate+0x1daa>
 1066829:	48 8b 5c 24 68       	mov    0x68(%rsp),%rbx
 106682e:	48 8b 54 24 70       	mov    0x70(%rsp),%rdx
 1066833:	48 8d 3d e6 e7 01 00 	lea    0x1e7e6(%rip),%rdi        # 1085020 <core_durable_error.verbs+0x6120>
 106683a:	e8 81 00 ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 106683f:	48 8d 3d aa b7 01 00 	lea    0x1b7aa(%rip),%rdi        # 1081ff0 <core_durable_error.verbs+0x30f0>
 1066846:	e8 75 00 ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 106684b:	b8 01 00 00 00       	mov    $0x1,%eax
 1066850:	e9 5b f4 ff ff       	jmp    1065cb0 <my.interpreter::evaluate+0x1020>
 1066855:	c5 fa 6f 44 24 68    	vmovdqu 0x68(%rsp),%xmm0
 106685b:	c5 f9 7f 44 24 40    	vmovdqa %xmm0,0x40(%rsp)
 1066861:	48 8d 3d f8 e9 01 00 	lea    0x1e9f8(%rip),%rdi        # 1085260 <core_durable_error.verbs+0x6360>
 1066868:	e8 53 00 ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 106686d:	e9 7d 01 00 00       	jmp    10669ef <my.interpreter::evaluate+0x1d5f>
 1066872:	48 8b 5c 24 68       	mov    0x68(%rsp),%rbx
 1066877:	48 8b 4c 24 70       	mov    0x70(%rsp),%rcx
 106687c:	48 8d 3d ad e3 01 00 	lea    0x1e3ad(%rip),%rdi        # 1084c30 <core_durable_error.verbs+0x5d30>
 1066883:	e8 38 00 ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066888:	e9 78 03 00 00       	jmp    1066c05 <my.interpreter::evaluate+0x1f75>
 106688d:	4d 89 de             	mov    %r11,%r14
 1066890:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 1066895:	48 8b 44 24 68       	mov    0x68(%rsp),%rax
 106689a:	48 8b 54 24 70       	mov    0x70(%rsp),%rdx
 106689f:	48 8d 3d aa e4 01 00 	lea    0x1e4aa(%rip),%rdi        # 1084d50 <core_durable_error.verbs+0x5e50>
 10668a6:	e9 00 01 00 00       	jmp    10669ab <my.interpreter::evaluate+0x1d1b>
 10668ab:	48 8d 3d ee e8 01 00 	lea    0x1e8ee(%rip),%rdi        # 10851a0 <core_durable_error.verbs+0x62a0>
 10668b2:	c5 f9 10 44 24 68    	vmovupd 0x68(%rsp),%xmm0
 10668b8:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 10668be:	48 8b 2c 24          	mov    (%rsp),%rbp
 10668c2:	e8 f9 ff fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 10668c7:	48 8d 3d 82 b7 01 00 	lea    0x1b782(%rip),%rdi        # 1082050 <core_durable_error.verbs+0x3150>
 10668ce:	e8 ed ff fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 10668d3:	b8 01 00 00 00       	mov    $0x1,%eax
 10668d8:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 10668de:	e9 c2 f7 ff ff       	jmp    10660a5 <my.interpreter::evaluate+0x1415>
 10668e3:	48 8b 44 24 68       	mov    0x68(%rsp),%rax
 10668e8:	4c 8b 64 24 70       	mov    0x70(%rsp),%r12
 10668ed:	48 8d 3d cc ec 01 00 	lea    0x1eccc(%rip),%rdi        # 10855c0 <core_durable_error.verbs+0x66c0>
 10668f4:	e8 c7 ff fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 10668f9:	4c 89 f5             	mov    %r14,%rbp
 10668fc:	e9 7c 01 00 00       	jmp    1066a7d <my.interpreter::evaluate+0x1ded>
 1066901:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1066906:	48 89 de             	mov    %rbx,%rsi
 1066909:	e8 62 30 00 00       	call   1069970 <my.heap::string_chars>
 106690e:	48 89 c3             	mov    %rax,%rbx
 1066911:	48 8d 3d 68 bd fa ff 	lea    -0x54298(%rip),%rdi        # 1012680 <core_number_pairs+0xb400>
 1066918:	48 89 c6             	mov    %rax,%rsi
 106691b:	e8 20 82 fc ff       	call   102eb40 <myl_core_bytes_concat>
 1066920:	49 89 c4             	mov    %rax,%r12
 1066923:	48 89 df             	mov    %rbx,%rdi
 1066926:	e8 15 ce fb ff       	call   1023740 <myl_core_drop_owned>
 106692b:	48 8d 35 4e b7 fa ff 	lea    -0x548b2(%rip),%rsi        # 1012080 <core_number_pairs+0xae00>
 1066932:	4c 89 e7             	mov    %r12,%rdi
 1066935:	e8 06 82 fc ff       	call   102eb40 <myl_core_bytes_concat>
 106693a:	49 89 c7             	mov    %rax,%r15
 106693d:	4c 89 e7             	mov    %r12,%rdi
 1066940:	e8 fb cd fb ff       	call   1023740 <myl_core_drop_owned>
 1066945:	4c 89 ff             	mov    %r15,%rdi
 1066948:	e8 73 d6 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 106694d:	48 89 c3             	mov    %rax,%rbx
 1066950:	4c 89 ff             	mov    %r15,%rdi
 1066953:	e8 e8 cd fb ff       	call   1023740 <myl_core_drop_owned>
 1066958:	48 8d 3d d1 eb 01 00 	lea    0x1ebd1(%rip),%rdi        # 1085530 <core_durable_error.verbs+0x6630>
 106695f:	e8 1c ff fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066964:	48 8d 3d 45 b7 01 00 	lea    0x1b745(%rip),%rdi        # 10820b0 <core_durable_error.verbs+0x31b0>
 106696b:	e8 50 ff fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066970:	b8 01 00 00 00       	mov    $0x1,%eax
 1066975:	48 8b 94 24 28 02 00 	mov    0x228(%rsp),%rdx
 106697c:	00 
 106697d:	48 8b bc 24 38 02 00 	mov    0x238(%rsp),%rdi
 1066984:	00 
 1066985:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 106698a:	e9 57 f1 ff ff       	jmp    1065ae6 <my.interpreter::evaluate+0xe56>
 106698f:	4c 89 5c 24 10       	mov    %r11,0x10(%rsp)
 1066994:	48 8b 84 24 a8 00 00 	mov    0xa8(%rsp),%rax
 106699b:	00 
 106699c:	48 8b 94 24 b0 00 00 	mov    0xb0(%rsp),%rdx
 10669a3:	00 
 10669a4:	48 8d 3d d5 e3 01 00 	lea    0x1e3d5(%rip),%rdi        # 1084d80 <core_durable_error.verbs+0x5e80>
 10669ab:	e8 10 ff fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 10669b0:	48 8b 2c 24          	mov    (%rsp),%rbp
 10669b4:	48 8d 3d d5 b5 01 00 	lea    0x1b5d5(%rip),%rdi        # 1081f90 <core_durable_error.verbs+0x3090>
 10669bb:	e8 00 ff fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 10669c0:	b9 01 00 00 00       	mov    $0x1,%ecx
 10669c5:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 10669ca:	e9 1d fd ff ff       	jmp    10666ec <my.interpreter::evaluate+0x1a5c>
 10669cf:	c5 fa 6f 84 24 a8 00 	vmovdqu 0xa8(%rsp),%xmm0
 10669d6:	00 00 
 10669d8:	c5 f9 7f 44 24 40    	vmovdqa %xmm0,0x40(%rsp)
 10669de:	48 8d 3d db e8 01 00 	lea    0x1e8db(%rip),%rdi        # 10852c0 <core_durable_error.verbs+0x63c0>
 10669e5:	e8 d6 fe fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 10669ea:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 10669ef:	48 8d 3d 8a b6 01 00 	lea    0x1b68a(%rip),%rdi        # 1082080 <core_durable_error.verbs+0x3180>
 10669f6:	e8 c5 fe fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 10669fb:	b8 01 00 00 00       	mov    $0x1,%eax
 1066a00:	c5 f9 28 44 24 40    	vmovapd 0x40(%rsp),%xmm0
 1066a06:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1066a0a:	c5 f9 11 45 08       	vmovupd %xmm0,0x8(%rbp)
 1066a0f:	48 89 5d 18          	mov    %rbx,0x18(%rbp)
 1066a13:	4c 89 75 20          	mov    %r14,0x20(%rbp)
 1066a17:	48 89 4d 28          	mov    %rcx,0x28(%rbp)
 1066a1b:	e9 4e 05 00 00       	jmp    1066f6e <my.interpreter::evaluate+0x22de>
 1066a20:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
 1066a25:	4c 89 5c 24 08       	mov    %r11,0x8(%rsp)
 1066a2a:	48 8d 3d 8f e5 01 00 	lea    0x1e58f(%rip),%rdi        # 1084fc0 <core_durable_error.verbs+0x60c0>
 1066a31:	c5 fa 6f 84 24 c0 01 	vmovdqu 0x1c0(%rsp),%xmm0
 1066a38:	00 00 
 1066a3a:	c5 f9 7f 44 24 10    	vmovdqa %xmm0,0x10(%rsp)
 1066a40:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066a44:	e9 ea 04 00 00       	jmp    1066f33 <my.interpreter::evaluate+0x22a3>
 1066a49:	48 8d 3d 90 b7 fa ff 	lea    -0x54870(%rip),%rdi        # 10121e0 <core_number_pairs+0xaf60>
 1066a50:	4c 89 cb             	mov    %r9,%rbx
 1066a53:	e8 68 d5 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066a58:	49 89 d9             	mov    %rbx,%r9
 1066a5b:	48 8d 3d be eb 01 00 	lea    0x1ebbe(%rip),%rdi        # 1085620 <core_durable_error.verbs+0x6720>
 1066a62:	e8 19 fe fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066a67:	eb 14                	jmp    1066a7d <my.interpreter::evaluate+0x1ded>
 1066a69:	e8 52 d5 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066a6e:	48 8d 3d db eb 01 00 	lea    0x1ebdb(%rip),%rdi        # 1085650 <core_durable_error.verbs+0x6750>
 1066a75:	e8 06 fe fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066a7a:	49 89 d9             	mov    %rbx,%r9
 1066a7d:	48 8d 3d 5c b6 01 00 	lea    0x1b65c(%rip),%rdi        # 10820e0 <core_durable_error.verbs+0x31e0>
 1066a84:	e8 37 fe fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066a89:	b9 01 00 00 00       	mov    $0x1,%ecx
 1066a8e:	e9 eb f9 ff ff       	jmp    106647e <my.interpreter::evaluate+0x17ee>
 1066a93:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1066a98:	4c 89 ee             	mov    %r13,%rsi
 1066a9b:	e8 d0 2e 00 00       	call   1069970 <my.heap::string_chars>
 1066aa0:	48 89 c3             	mov    %rax,%rbx
 1066aa3:	48 8d 3d d6 bb fa ff 	lea    -0x5442a(%rip),%rdi        # 1012680 <core_number_pairs+0xb400>
 1066aaa:	48 89 c6             	mov    %rax,%rsi
 1066aad:	e8 8e 80 fc ff       	call   102eb40 <myl_core_bytes_concat>
 1066ab2:	49 89 c6             	mov    %rax,%r14
 1066ab5:	48 89 df             	mov    %rbx,%rdi
 1066ab8:	e8 83 cc fb ff       	call   1023740 <myl_core_drop_owned>
 1066abd:	48 8d 35 bc b5 fa ff 	lea    -0x54a44(%rip),%rsi        # 1012080 <core_number_pairs+0xae00>
 1066ac4:	4c 89 f7             	mov    %r14,%rdi
 1066ac7:	e8 74 80 fc ff       	call   102eb40 <myl_core_bytes_concat>
 1066acc:	48 89 c5             	mov    %rax,%rbp
 1066acf:	4c 89 f7             	mov    %r14,%rdi
 1066ad2:	e8 69 cc fb ff       	call   1023740 <myl_core_drop_owned>
 1066ad7:	48 89 ef             	mov    %rbp,%rdi
 1066ada:	e8 e1 d4 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066adf:	48 89 c3             	mov    %rax,%rbx
 1066ae2:	48 89 ef             	mov    %rbp,%rdi
 1066ae5:	e8 56 cc fb ff       	call   1023740 <myl_core_drop_owned>
 1066aea:	48 8d 3d 8f e5 01 00 	lea    0x1e58f(%rip),%rdi        # 1085080 <core_durable_error.verbs+0x6180>
 1066af1:	e8 8a fd fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066af6:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066afa:	4c 8b 7c 24 38       	mov    0x38(%rsp),%r15
 1066aff:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 1066b04:	e9 7d fa ff ff       	jmp    1066586 <my.interpreter::evaluate+0x18f6>
 1066b09:	4c 89 f7             	mov    %r14,%rdi
 1066b0c:	48 89 de             	mov    %rbx,%rsi
 1066b0f:	e8 5c 2e 00 00       	call   1069970 <my.heap::string_chars>
 1066b14:	48 89 c3             	mov    %rax,%rbx
 1066b17:	48 8d 3d 22 b5 fa ff 	lea    -0x54ade(%rip),%rdi        # 1012040 <core_number_pairs+0xadc0>
 1066b1e:	48 89 c6             	mov    %rax,%rsi
 1066b21:	e8 1a 80 fc ff       	call   102eb40 <myl_core_bytes_concat>
 1066b26:	49 89 c4             	mov    %rax,%r12
 1066b29:	48 89 df             	mov    %rbx,%rdi
 1066b2c:	e8 0f cc fb ff       	call   1023740 <myl_core_drop_owned>
 1066b31:	48 8d 35 48 b5 fa ff 	lea    -0x54ab8(%rip),%rsi        # 1012080 <core_number_pairs+0xae00>
 1066b38:	4c 89 e7             	mov    %r12,%rdi
 1066b3b:	e8 00 80 fc ff       	call   102eb40 <myl_core_bytes_concat>
 1066b40:	49 89 c7             	mov    %rax,%r15
 1066b43:	4c 89 e7             	mov    %r12,%rdi
 1066b46:	e8 f5 cb fb ff       	call   1023740 <myl_core_drop_owned>
 1066b4b:	4c 89 ff             	mov    %r15,%rdi
 1066b4e:	e8 6d d4 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066b53:	48 89 c3             	mov    %rax,%rbx
 1066b56:	4c 89 ff             	mov    %r15,%rdi
 1066b59:	e8 e2 cb fb ff       	call   1023740 <myl_core_drop_owned>
 1066b5e:	48 8d 3d 7b eb 01 00 	lea    0x1eb7b(%rip),%rdi        # 10856e0 <core_durable_error.verbs+0x67e0>
 1066b65:	e8 16 fd fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066b6a:	48 8d 3d 9f b5 01 00 	lea    0x1b59f(%rip),%rdi        # 1082110 <core_durable_error.verbs+0x3210>
 1066b71:	e8 4a fd fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066b76:	b8 01 00 00 00       	mov    $0x1,%eax
 1066b7b:	4c 8b 9c 24 28 02 00 	mov    0x228(%rsp),%r11
 1066b82:	00 
 1066b83:	4c 8b b4 24 38 02 00 	mov    0x238(%rsp),%r14
 1066b8a:	00 
 1066b8b:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 1066b90:	e9 c4 f1 ff ff       	jmp    1065d59 <my.interpreter::evaluate+0x10c9>
 1066b95:	4c 89 ef             	mov    %r13,%rdi
 1066b98:	4c 89 e6             	mov    %r12,%rsi
 1066b9b:	e8 d0 2d 00 00       	call   1069970 <my.heap::string_chars>
 1066ba0:	48 89 c3             	mov    %rax,%rbx
 1066ba3:	48 8d 3d 96 b4 fa ff 	lea    -0x54b6a(%rip),%rdi        # 1012040 <core_number_pairs+0xadc0>
 1066baa:	48 89 c6             	mov    %rax,%rsi
 1066bad:	e8 8e 7f fc ff       	call   102eb40 <myl_core_bytes_concat>
 1066bb2:	49 89 c4             	mov    %rax,%r12
 1066bb5:	48 89 df             	mov    %rbx,%rdi
 1066bb8:	e8 83 cb fb ff       	call   1023740 <myl_core_drop_owned>
 1066bbd:	48 8d 35 bc b4 fa ff 	lea    -0x54b44(%rip),%rsi        # 1012080 <core_number_pairs+0xae00>
 1066bc4:	4c 89 e7             	mov    %r12,%rdi
 1066bc7:	e8 74 7f fc ff       	call   102eb40 <myl_core_bytes_concat>
 1066bcc:	49 89 c7             	mov    %rax,%r15
 1066bcf:	4c 89 e7             	mov    %r12,%rdi
 1066bd2:	e8 69 cb fb ff       	call   1023740 <myl_core_drop_owned>
 1066bd7:	4c 89 ff             	mov    %r15,%rdi
 1066bda:	e8 e1 d3 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066bdf:	48 89 c3             	mov    %rax,%rbx
 1066be2:	4c 89 ff             	mov    %r15,%rdi
 1066be5:	e8 56 cb fb ff       	call   1023740 <myl_core_drop_owned>
 1066bea:	48 8d 3d 6f e0 01 00 	lea    0x1e06f(%rip),%rdi        # 1084c60 <core_durable_error.verbs+0x5d60>
 1066bf1:	e8 8a fc fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066bf6:	4c 8b 6c 24 28       	mov    0x28(%rsp),%r13
 1066bfb:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1066c00:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 1066c05:	48 8d 3d 54 b3 01 00 	lea    0x1b354(%rip),%rdi        # 1081f60 <core_durable_error.verbs+0x3060>
 1066c0c:	e8 af fc fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066c11:	b8 01 00 00 00       	mov    $0x1,%eax
 1066c16:	e9 4e f4 ff ff       	jmp    1066069 <my.interpreter::evaluate+0x13d9>
 1066c1b:	64 48 8b 1c 25 d8 fe 	mov    %fs:0xfffffffffffffed8,%rbx
 1066c22:	ff ff 
 1066c24:	48 85 db             	test   %rbx,%rbx
 1066c27:	0f 84 00 09 00 00    	je     106752d <my.interpreter::evaluate+0x289d>
 1066c2d:	48 8b 03             	mov    (%rbx),%rax
 1066c30:	64 48 89 04 25 d8 fe 	mov    %rax,%fs:0xfffffffffffffed8
 1066c37:	ff ff 
 1066c39:	c7 03 00 00 00 03    	movl   $0x3000000,(%rbx)
 1066c3f:	48 c7 43 08 00 00 00 	movq   $0x0,0x8(%rbx)
 1066c46:	00 
 1066c47:	48 c7 43 10 08 00 00 	movq   $0x8,0x10(%rbx)
 1066c4e:	00 
 1066c4f:	48 8d 05 92 cf fa ff 	lea    -0x5306e(%rip),%rax        # 1013be8 <core_number_pairs+0xc968>
 1066c56:	48 89 43 18          	mov    %rax,0x18(%rbx)
 1066c5a:	31 c0                	xor    %eax,%eax
 1066c5c:	48 8d 0d 5d b2 fa ff 	lea    -0x54da3(%rip),%rcx        # 1011ec0 <core_number_pairs+0xac40>
 1066c63:	48 89 4c c3 20       	mov    %rcx,0x20(%rbx,%rax,8)
 1066c68:	48 ff c0             	inc    %rax
 1066c6b:	48 89 43 08          	mov    %rax,0x8(%rbx)
 1066c6f:	48 89 d7             	mov    %rdx,%rdi
 1066c72:	e8 49 5a fd ff       	call   103c6c0 <myl_core_str_from_i64>
 1066c77:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1066c7b:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 1066c7f:	48 39 d1             	cmp    %rdx,%rcx
 1066c82:	0f 83 f5 08 00 00    	jae    106757d <my.interpreter::evaluate+0x28ed>
 1066c88:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066c8d:	48 ff c1             	inc    %rcx
 1066c90:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066c94:	48 39 d1             	cmp    %rdx,%rcx
 1066c97:	0f 83 09 09 00 00    	jae    10675a6 <my.interpreter::evaluate+0x2916>
 1066c9d:	48 8d 05 5c b2 fa ff 	lea    -0x54da4(%rip),%rax        # 1011f00 <core_number_pairs+0xac80>
 1066ca4:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066ca9:	48 ff c1             	inc    %rcx
 1066cac:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066cb0:	4c 89 f7             	mov    %r14,%rdi
 1066cb3:	e8 08 5a fd ff       	call   103c6c0 <myl_core_str_from_i64>
 1066cb8:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1066cbc:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 1066cc0:	48 39 d1             	cmp    %rdx,%rcx
 1066cc3:	0f 83 f6 08 00 00    	jae    10675bf <my.interpreter::evaluate+0x292f>
 1066cc9:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066cce:	48 ff c1             	inc    %rcx
 1066cd1:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066cd5:	48 39 d1             	cmp    %rdx,%rcx
 1066cd8:	0f 83 04 09 00 00    	jae    10675e2 <my.interpreter::evaluate+0x2952>
 1066cde:	48 8d 05 5b b2 fa ff 	lea    -0x54da5(%rip),%rax        # 1011f40 <core_number_pairs+0xacc0>
 1066ce5:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066cea:	48 ff c1             	inc    %rcx
 1066ced:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066cf1:	48 8d 3d 68 ad fa ff 	lea    -0x55298(%rip),%rdi        # 1011a60 <core_number_pairs+0xa7e0>
 1066cf8:	48 89 de             	mov    %rbx,%rsi
 1066cfb:	e8 40 5d fc ff       	call   102ca40 <myl_core_str_join>
 1066d00:	49 89 c4             	mov    %rax,%r12
 1066d03:	48 89 df             	mov    %rbx,%rdi
 1066d06:	e8 35 ca fb ff       	call   1023740 <myl_core_drop_owned>
 1066d0b:	4c 89 e7             	mov    %r12,%rdi
 1066d0e:	e8 6d 80 fc ff       	call   102ed80 <myl_core_text_encode>
 1066d13:	48 89 c3             	mov    %rax,%rbx
 1066d16:	4c 89 e7             	mov    %r12,%rdi
 1066d19:	e8 22 ca fb ff       	call   1023740 <myl_core_drop_owned>
 1066d1e:	48 89 df             	mov    %rbx,%rdi
 1066d21:	e8 9a d2 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066d26:	49 89 c6             	mov    %rax,%r14
 1066d29:	48 89 df             	mov    %rbx,%rdi
 1066d2c:	e8 0f ca fb ff       	call   1023740 <myl_core_drop_owned>
 1066d31:	48 8d 3d c8 ff 01 00 	lea    0x1ffc8(%rip),%rdi        # 1086d00 <core_durable_error.verbs+0x7e00>
 1066d38:	e8 43 fb fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066d3d:	4d 89 ea             	mov    %r13,%r10
 1066d40:	e9 9e fa ff ff       	jmp    10667e3 <my.interpreter::evaluate+0x1b53>
 1066d45:	48 89 6c 24 08       	mov    %rbp,0x8(%rsp)
 1066d4a:	4c 8b 84 24 48 01 00 	mov    0x148(%rsp),%r8
 1066d51:	00 
 1066d52:	48 8d 3d 17 ff 01 00 	lea    0x1ff17(%rip),%rdi        # 1086c70 <core_durable_error.verbs+0x7d70>
 1066d59:	4d 89 d6             	mov    %r10,%r14
 1066d5c:	e8 5f fb fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066d61:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066d65:	4d 89 fa             	mov    %r15,%r10
 1066d68:	e9 ab 01 00 00       	jmp    1066f18 <my.interpreter::evaluate+0x2288>
 1066d6d:	4c 89 6c 24 30       	mov    %r13,0x30(%rsp)
 1066d72:	4c 89 4c 24 08       	mov    %r9,0x8(%rsp)
 1066d77:	48 8d 3d 22 ff 01 00 	lea    0x1ff22(%rip),%rdi        # 1086ca0 <core_durable_error.verbs+0x7da0>
 1066d7e:	e8 3d fb fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066d83:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066d87:	e9 8c 01 00 00       	jmp    1066f18 <my.interpreter::evaluate+0x2288>
 1066d8c:	48 8d 3d ad b3 fa ff 	lea    -0x54c53(%rip),%rdi        # 1012140 <core_number_pairs+0xaec0>
 1066d93:	e8 28 d2 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066d98:	48 8d 3d 41 e0 01 00 	lea    0x1e041(%rip),%rdi        # 1084de0 <core_durable_error.verbs+0x5ee0>
 1066d9f:	e8 dc fa fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066da4:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066da8:	4d 89 fa             	mov    %r15,%r10
 1066dab:	eb 21                	jmp    1066dce <my.interpreter::evaluate+0x213e>
 1066dad:	48 8d 3d cc b3 fa ff 	lea    -0x54c34(%rip),%rdi        # 1012180 <core_number_pairs+0xaf00>
 1066db4:	e8 07 d2 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066db9:	48 8d 3d f0 df 01 00 	lea    0x1dff0(%rip),%rdi        # 1084db0 <core_durable_error.verbs+0x5eb0>
 1066dc0:	e8 bb fa fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066dc5:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066dc9:	4c 8b 54 24 40       	mov    0x40(%rsp),%r10
 1066dce:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 1066dd3:	e9 dc fb ff ff       	jmp    10669b4 <my.interpreter::evaluate+0x1d24>
 1066dd8:	64 48 8b 1c 25 d0 fe 	mov    %fs:0xfffffffffffffed0,%rbx
 1066ddf:	ff ff 
 1066de1:	48 85 db             	test   %rbx,%rbx
 1066de4:	0f 84 11 08 00 00    	je     10675fb <my.interpreter::evaluate+0x296b>
 1066dea:	48 8b 03             	mov    (%rbx),%rax
 1066ded:	64 48 89 04 25 d0 fe 	mov    %rax,%fs:0xfffffffffffffed0
 1066df4:	ff ff 
 1066df6:	c7 03 00 00 00 02    	movl   $0x2000000,(%rbx)
 1066dfc:	48 c7 43 08 00 00 00 	movq   $0x0,0x8(%rbx)
 1066e03:	00 
 1066e04:	48 c7 43 10 04 00 00 	movq   $0x4,0x10(%rbx)
 1066e0b:	00 
 1066e0c:	48 8d 05 d5 cd fa ff 	lea    -0x5322b(%rip),%rax        # 1013be8 <core_number_pairs+0xc968>
 1066e13:	48 89 43 18          	mov    %rax,0x18(%rbx)
 1066e17:	31 c0                	xor    %eax,%eax
 1066e19:	48 8d 0d a0 cb fa ff 	lea    -0x53460(%rip),%rcx        # 10139c0 <core_number_pairs+0xc740>
 1066e20:	48 89 4c c3 20       	mov    %rcx,0x20(%rbx,%rax,8)
 1066e25:	48 ff c0             	inc    %rax
 1066e28:	48 89 43 08          	mov    %rax,0x8(%rbx)
 1066e2c:	4c 89 f7             	mov    %r14,%rdi
 1066e2f:	e8 8c 58 fd ff       	call   103c6c0 <myl_core_str_from_i64>
 1066e34:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1066e38:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 1066e3c:	48 39 d1             	cmp    %rdx,%rcx
 1066e3f:	0f 83 02 08 00 00    	jae    1067647 <my.interpreter::evaluate+0x29b7>
 1066e45:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066e4a:	48 ff c1             	inc    %rcx
 1066e4d:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066e51:	48 39 d1             	cmp    %rdx,%rcx
 1066e54:	0f 83 10 08 00 00    	jae    106766a <my.interpreter::evaluate+0x29da>
 1066e5a:	48 8d 05 df b0 fa ff 	lea    -0x54f21(%rip),%rax        # 1011f40 <core_number_pairs+0xacc0>
 1066e61:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066e66:	48 ff c1             	inc    %rcx
 1066e69:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066e6d:	48 8d 3d ec ab fa ff 	lea    -0x55414(%rip),%rdi        # 1011a60 <core_number_pairs+0xa7e0>
 1066e74:	48 89 de             	mov    %rbx,%rsi
 1066e77:	e8 c4 5b fc ff       	call   102ca40 <myl_core_str_join>
 1066e7c:	49 89 c4             	mov    %rax,%r12
 1066e7f:	48 89 df             	mov    %rbx,%rdi
 1066e82:	e8 b9 c8 fb ff       	call   1023740 <myl_core_drop_owned>
 1066e87:	4c 89 e7             	mov    %r12,%rdi
 1066e8a:	e8 f1 7e fc ff       	call   102ed80 <myl_core_text_encode>
 1066e8f:	48 89 c3             	mov    %rax,%rbx
 1066e92:	4c 89 e7             	mov    %r12,%rdi
 1066e95:	e8 a6 c8 fb ff       	call   1023740 <myl_core_drop_owned>
 1066e9a:	48 89 df             	mov    %rbx,%rdi
 1066e9d:	e8 1e d1 fb ff       	call   1023fc0 <myl_core_owned_octets_copy>
 1066ea2:	49 89 c6             	mov    %rax,%r14
 1066ea5:	48 89 df             	mov    %rbx,%rdi
 1066ea8:	e8 93 c8 fb ff       	call   1023740 <myl_core_drop_owned>
 1066ead:	48 8d 3d 7c 13 02 00 	lea    0x2137c(%rip),%rdi        # 1088230 <core_durable_error.verbs+0x9330>
 1066eb4:	e8 c7 f9 fe ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 1066eb9:	4c 8b 94 24 98 00 00 	mov    0x98(%rsp),%r10
 1066ec0:	00 
 1066ec1:	4c 8b 44 24 58       	mov    0x58(%rsp),%r8
 1066ec6:	eb 44                	jmp    1066f0c <my.interpreter::evaluate+0x227c>
 1066ec8:	4d 89 e6             	mov    %r12,%r14
 1066ecb:	4c 8b 84 24 60 01 00 	mov    0x160(%rsp),%r8
 1066ed2:	00 
 1066ed3:	48 8d 3d f6 12 02 00 	lea    0x212f6(%rip),%rdi        # 10881d0 <core_durable_error.verbs+0x92d0>
 1066eda:	e8 e1 f9 fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066edf:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066ee3:	4c 8b 94 24 98 00 00 	mov    0x98(%rsp),%r10
 1066eea:	00 
 1066eeb:	eb 1f                	jmp    1066f0c <my.interpreter::evaluate+0x227c>
 1066eed:	4c 89 4c 24 08       	mov    %r9,0x8(%rsp)
 1066ef2:	4c 8b 74 24 68       	mov    0x68(%rsp),%r14
 1066ef7:	4c 8b 44 24 70       	mov    0x70(%rsp),%r8
 1066efc:	48 8d 3d fd 12 02 00 	lea    0x212fd(%rip),%rdi        # 1088200 <core_durable_error.verbs+0x9300>
 1066f03:	e8 b8 f9 fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066f08:	48 8b 2c 24          	mov    (%rsp),%rbp
 1066f0c:	48 8d 3d bd fd 01 00 	lea    0x1fdbd(%rip),%rdi        # 1086cd0 <core_durable_error.verbs+0x7dd0>
 1066f13:	e8 a8 f9 fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066f18:	c4 c1 f9 6e c0       	vmovq  %r8,%xmm0
 1066f1d:	c4 c1 f9 6e ce       	vmovq  %r14,%xmm1
 1066f22:	c5 f1 6c c0          	vpunpcklqdq %xmm0,%xmm1,%xmm0
 1066f26:	c5 f9 7f 44 24 10    	vmovdqa %xmm0,0x10(%rsp)
 1066f2c:	48 8d 3d bd e0 01 00 	lea    0x1e0bd(%rip),%rdi        # 1084ff0 <core_durable_error.verbs+0x60f0>
 1066f33:	e8 88 f9 fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066f38:	48 8d 3d 81 b0 01 00 	lea    0x1b081(%rip),%rdi        # 1081fc0 <core_durable_error.verbs+0x30c0>
 1066f3f:	e8 7c f9 fe ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 1066f44:	b8 01 00 00 00       	mov    $0x1,%eax
 1066f49:	4c 8b 4c 24 08       	mov    0x8(%rsp),%r9
 1066f4e:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 1066f53:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 1066f59:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1066f5d:	c5 f9 11 45 08       	vmovupd %xmm0,0x8(%rbp)
 1066f62:	4c 89 55 18          	mov    %r10,0x18(%rbp)
 1066f66:	4c 89 6d 20          	mov    %r13,0x20(%rbp)
 1066f6a:	4c 89 4d 28          	mov    %r9,0x28(%rbp)
 1066f6e:	48 89 e8             	mov    %rbp,%rax
 1066f71:	48 81 c4 e8 01 00 00 	add    $0x1e8,%rsp
 1066f78:	5b                   	pop    %rbx
 1066f79:	41 5c                	pop    %r12
 1066f7b:	41 5d                	pop    %r13
 1066f7d:	41 5e                	pop    %r14
 1066f7f:	41 5f                	pop    %r15
 1066f81:	5d                   	pop    %rbp
 1066f82:	c3                   	ret
 1066f83:	48 89 f0             	mov    %rsi,%rax
 1066f86:	48 c1 f8 3f          	sar    $0x3f,%rax
 1066f8a:	48 21 d0             	and    %rdx,%rax
 1066f8d:	48 01 f0             	add    %rsi,%rax
 1066f90:	48 39 d0             	cmp    %rdx,%rax
 1066f93:	0f 82 2c dd ff ff    	jb     1064cc5 <my.interpreter::evaluate+0x35>
 1066f99:	48 8d 3d 90 af 01 00 	lea    0x1af90(%rip),%rdi        # 1081f30 <core_durable_error.verbs+0x3030>
 1066fa0:	e8 1b d5 fb ff       	call   10244c0 <myl_core_trap>
 1066fa5:	48 89 f1             	mov    %rsi,%rcx
 1066fa8:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066fac:	48 21 d1             	and    %rdx,%rcx
 1066faf:	48 01 f1             	add    %rsi,%rcx
 1066fb2:	48 39 d1             	cmp    %rdx,%rcx
 1066fb5:	0f 82 ba e5 ff ff    	jb     1065575 <my.interpreter::evaluate+0x8e5>
 1066fbb:	48 8d 3d 7e b1 01 00 	lea    0x1b17e(%rip),%rdi        # 1082140 <core_durable_error.verbs+0x3240>
 1066fc2:	e8 f9 d4 fb ff       	call   10244c0 <myl_core_trap>
 1066fc7:	48 89 f7             	mov    %rsi,%rdi
 1066fca:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066fce:	48 21 d7             	and    %rdx,%rdi
 1066fd1:	48 01 f7             	add    %rsi,%rdi
 1066fd4:	48 39 d7             	cmp    %rdx,%rdi
 1066fd7:	0f 82 fc e8 ff ff    	jb     10658d9 <my.interpreter::evaluate+0xc49>
 1066fdd:	48 8d 3d bc ae 01 00 	lea    0x1aebc(%rip),%rdi        # 1081ea0 <core_durable_error.verbs+0x2fa0>
 1066fe4:	e8 d7 d4 fb ff       	call   10244c0 <myl_core_trap>
 1066fe9:	49 89 c8             	mov    %rcx,%r8
 1066fec:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066ff0:	49 21 d0             	and    %rdx,%r8
 1066ff3:	49 01 c8             	add    %rcx,%r8
 1066ff6:	49 39 d0             	cmp    %rdx,%r8
 1066ff9:	0f 82 72 e9 ff ff    	jb     1065971 <my.interpreter::evaluate+0xce1>
 1066fff:	48 8d 3d 9a ae 01 00 	lea    0x1ae9a(%rip),%rdi        # 1081ea0 <core_durable_error.verbs+0x2fa0>
 1067006:	48 89 ce             	mov    %rcx,%rsi
 1067009:	e8 b2 d4 fb ff       	call   10244c0 <myl_core_trap>
 106700e:	48 89 c6             	mov    %rax,%rsi
 1067011:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1067015:	48 21 d6             	and    %rdx,%rsi
 1067018:	48 01 c6             	add    %rax,%rsi
 106701b:	48 39 d6             	cmp    %rdx,%rsi
 106701e:	0f 82 df e8 ff ff    	jb     1065903 <my.interpreter::evaluate+0xc73>
 1067024:	48 8d 3d d5 ae 01 00 	lea    0x1aed5(%rip),%rdi        # 1081f00 <core_durable_error.verbs+0x3000>
 106702b:	48 89 c6             	mov    %rax,%rsi
 106702e:	e8 8d d4 fb ff       	call   10244c0 <myl_core_trap>
 1067033:	48 89 f1             	mov    %rsi,%rcx
 1067036:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106703a:	48 21 d1             	and    %rdx,%rcx
 106703d:	48 01 f1             	add    %rsi,%rcx
 1067040:	48 39 d1             	cmp    %rdx,%rcx
 1067043:	0f 82 df e8 ff ff    	jb     1065928 <my.interpreter::evaluate+0xc98>
 1067049:	48 8d 3d 50 b1 01 00 	lea    0x1b150(%rip),%rdi        # 10821a0 <core_durable_error.verbs+0x32a0>
 1067050:	e8 6b d4 fb ff       	call   10244c0 <myl_core_trap>
 1067055:	48 8d 3d a4 ae 01 00 	lea    0x1aea4(%rip),%rdi        # 1081f00 <core_durable_error.verbs+0x3000>
 106705c:	31 f6                	xor    %esi,%esi
 106705e:	31 d2                	xor    %edx,%edx
 1067060:	e8 5b d4 fb ff       	call   10244c0 <myl_core_trap>
 1067065:	48 89 f1             	mov    %rsi,%rcx
 1067068:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106706c:	48 21 d1             	and    %rdx,%rcx
 106706f:	48 01 f1             	add    %rsi,%rcx
 1067072:	48 39 d1             	cmp    %rdx,%rcx
 1067075:	0f 82 93 e9 ff ff    	jb     1065a0e <my.interpreter::evaluate+0xd7e>
 106707b:	48 8d 3d 1e ae 01 00 	lea    0x1ae1e(%rip),%rdi        # 1081ea0 <core_durable_error.verbs+0x2fa0>
 1067082:	e8 39 d4 fb ff       	call   10244c0 <myl_core_trap>
 1067087:	48 8d 3d 72 ae 01 00 	lea    0x1ae72(%rip),%rdi        # 1081f00 <core_durable_error.verbs+0x3000>
 106708e:	31 f6                	xor    %esi,%esi
 1067090:	31 d2                	xor    %edx,%edx
 1067092:	e8 29 d4 fb ff       	call   10244c0 <myl_core_trap>
 1067097:	49 89 f4             	mov    %rsi,%r12
 106709a:	49 c1 fc 3f          	sar    $0x3f,%r12
 106709e:	49 21 d4             	and    %rdx,%r12
 10670a1:	49 01 f4             	add    %rsi,%r12
 10670a4:	49 39 d4             	cmp    %rdx,%r12
 10670a7:	0f 82 18 e0 ff ff    	jb     10650c5 <my.interpreter::evaluate+0x435>
 10670ad:	48 8d 3d 2c e0 01 00 	lea    0x1e02c(%rip),%rdi        # 10850e0 <core_durable_error.verbs+0x61e0>
 10670b4:	e8 07 d4 fb ff       	call   10244c0 <myl_core_trap>
 10670b9:	48 89 f7             	mov    %rsi,%rdi
 10670bc:	48 c1 ff 3f          	sar    $0x3f,%rdi
 10670c0:	48 21 d7             	and    %rdx,%rdi
 10670c3:	48 01 f7             	add    %rsi,%rdi
 10670c6:	48 39 d7             	cmp    %rdx,%rdi
 10670c9:	0f 82 4f e1 ff ff    	jb     106521e <my.interpreter::evaluate+0x58e>
 10670cf:	48 8d 3d 4a e2 01 00 	lea    0x1e24a(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x6420>
 10670d6:	e8 e5 d3 fb ff       	call   10244c0 <myl_core_trap>
 10670db:	48 89 f7             	mov    %rsi,%rdi
 10670de:	48 c1 ff 3f          	sar    $0x3f,%rdi
 10670e2:	48 21 d7             	and    %rdx,%rdi
 10670e5:	48 01 f7             	add    %rsi,%rdi
 10670e8:	48 39 d7             	cmp    %rdx,%rdi
 10670eb:	0f 82 5e e5 ff ff    	jb     106564f <my.interpreter::evaluate+0x9bf>
 10670f1:	48 8d 3d 38 e1 01 00 	lea    0x1e138(%rip),%rdi        # 1085230 <core_durable_error.verbs+0x6330>
 10670f8:	e8 c3 d3 fb ff       	call   10244c0 <myl_core_trap>
 10670fd:	48 89 f7             	mov    %rsi,%rdi
 1067100:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1067104:	48 21 d7             	and    %rdx,%rdi
 1067107:	48 01 f7             	add    %rsi,%rdi
 106710a:	48 39 d7             	cmp    %rdx,%rdi
 106710d:	0f 82 73 e6 ff ff    	jb     1065786 <my.interpreter::evaluate+0xaf6>
 1067113:	48 8d 3d 96 e5 01 00 	lea    0x1e596(%rip),%rdi        # 10856b0 <core_durable_error.verbs+0x67b0>
 106711a:	e8 a1 d3 fb ff       	call   10244c0 <myl_core_trap>
 106711f:	48 89 f7             	mov    %rsi,%rdi
 1067122:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1067126:	48 21 d7             	and    %rdx,%rdi
 1067129:	48 01 f7             	add    %rsi,%rdi
 106712c:	48 39 d7             	cmp    %rdx,%rdi
 106712f:	0f 82 7a e9 ff ff    	jb     1065aaf <my.interpreter::evaluate+0xe1f>
 1067135:	48 8d 3d 24 e4 01 00 	lea    0x1e424(%rip),%rdi        # 1085560 <core_durable_error.verbs+0x6660>
 106713c:	e8 7f d3 fb ff       	call   10244c0 <myl_core_trap>
 1067141:	4c 89 e9             	mov    %r13,%rcx
 1067144:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067148:	48 21 d1             	and    %rdx,%rcx
 106714b:	4c 01 e9             	add    %r13,%rcx
 106714e:	48 39 d1             	cmp    %rdx,%rcx
 1067151:	0f 82 6b ec ff ff    	jb     1065dc2 <my.interpreter::evaluate+0x1132>
 1067157:	48 8d 3d b2 fa 01 00 	lea    0x1fab2(%rip),%rdi        # 1086c10 <core_durable_error.verbs+0x7d10>
 106715e:	4c 89 ee             	mov    %r13,%rsi
 1067161:	e8 5a d3 fb ff       	call   10244c0 <myl_core_trap>
 1067166:	48 89 d9             	mov    %rbx,%rcx
 1067169:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106716d:	48 21 d1             	and    %rdx,%rcx
 1067170:	48 01 d9             	add    %rbx,%rcx
 1067173:	48 39 d1             	cmp    %rdx,%rcx
 1067176:	0f 82 77 df ff ff    	jb     10650f3 <my.interpreter::evaluate+0x463>
 106717c:	48 8d 3d 8d c1 01 00 	lea    0x1c18d(%rip),%rdi        # 1083310 <core_durable_error.verbs+0x4410>
 1067183:	48 89 de             	mov    %rbx,%rsi
 1067186:	e8 35 d3 fb ff       	call   10244c0 <myl_core_trap>
 106718b:	48 89 f7             	mov    %rsi,%rdi
 106718e:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1067192:	48 21 d7             	and    %rdx,%rdi
 1067195:	48 01 f7             	add    %rsi,%rdi
 1067198:	48 39 d7             	cmp    %rdx,%rdi
 106719b:	0f 82 a4 e0 ff ff    	jb     1065245 <my.interpreter::evaluate+0x5b5>
 10671a1:	48 8d 3d 68 c1 01 00 	lea    0x1c168(%rip),%rdi        # 1083310 <core_durable_error.verbs+0x4410>
 10671a8:	e8 13 d3 fb ff       	call   10244c0 <myl_core_trap>
 10671ad:	49 89 f0             	mov    %rsi,%r8
 10671b0:	49 c1 f8 3f          	sar    $0x3f,%r8
 10671b4:	49 21 d0             	and    %rdx,%r8
 10671b7:	49 01 f0             	add    %rsi,%r8
 10671ba:	49 39 d0             	cmp    %rdx,%r8
 10671bd:	0f 82 26 e3 ff ff    	jb     10654e9 <my.interpreter::evaluate+0x859>
 10671c3:	48 8d 3d a6 dc 01 00 	lea    0x1dca6(%rip),%rdi        # 1084e70 <core_durable_error.verbs+0x5f70>
 10671ca:	e8 f1 d2 fb ff       	call   10244c0 <myl_core_trap>
 10671cf:	48 89 de             	mov    %rbx,%rsi
 10671d2:	48 c1 fe 3f          	sar    $0x3f,%rsi
 10671d6:	48 21 d6             	and    %rdx,%rsi
 10671d9:	48 01 de             	add    %rbx,%rsi
 10671dc:	48 39 d6             	cmp    %rdx,%rsi
 10671df:	0f 82 1f e3 ff ff    	jb     1065504 <my.interpreter::evaluate+0x874>
 10671e5:	48 8d 3d 14 dd 01 00 	lea    0x1dd14(%rip),%rdi        # 1084f00 <core_durable_error.verbs+0x6000>
 10671ec:	48 89 de             	mov    %rbx,%rsi
 10671ef:	e8 cc d2 fb ff       	call   10244c0 <myl_core_trap>
 10671f4:	48 89 de             	mov    %rbx,%rsi
 10671f7:	48 c1 fe 3f          	sar    $0x3f,%rsi
 10671fb:	48 21 ce             	and    %rcx,%rsi
 10671fe:	48 01 de             	add    %rbx,%rsi
 1067201:	48 39 ce             	cmp    %rcx,%rsi
 1067204:	0f 82 b3 f4 ff ff    	jb     10666bd <my.interpreter::evaluate+0x1a2d>
 106720a:	48 8d 3d bf dc 01 00 	lea    0x1dcbf(%rip),%rdi        # 1084ed0 <core_durable_error.verbs+0x5fd0>
 1067211:	48 89 de             	mov    %rbx,%rsi
 1067214:	48 89 ca             	mov    %rcx,%rdx
 1067217:	e8 a4 d2 fb ff       	call   10244c0 <myl_core_trap>
 106721c:	49 89 f0             	mov    %rsi,%r8
 106721f:	49 c1 f8 3f          	sar    $0x3f,%r8
 1067223:	49 21 c8             	and    %rcx,%r8
 1067226:	49 01 f0             	add    %rsi,%r8
 1067229:	49 39 c8             	cmp    %rcx,%r8
 106722c:	0f 82 a3 f4 ff ff    	jb     10666d5 <my.interpreter::evaluate+0x1a45>
 1067232:	48 8d 3d 27 dd 01 00 	lea    0x1dd27(%rip),%rdi        # 1084f60 <core_durable_error.verbs+0x6060>
 1067239:	48 89 ca             	mov    %rcx,%rdx
 106723c:	e8 7f d2 fb ff       	call   10244c0 <myl_core_trap>
 1067241:	4c 89 e1             	mov    %r12,%rcx
 1067244:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067248:	48 21 d1             	and    %rdx,%rcx
 106724b:	4c 01 e1             	add    %r12,%rcx
 106724e:	48 39 d1             	cmp    %rdx,%rcx
 1067251:	0f 82 9d eb ff ff    	jb     1065df4 <my.interpreter::evaluate+0x1164>
 1067257:	48 8d 3d 92 f8 01 00 	lea    0x1f892(%rip),%rdi        # 1086af0 <core_durable_error.verbs+0x7bf0>
 106725e:	4c 89 e6             	mov    %r12,%rsi
 1067261:	e8 5a d2 fb ff       	call   10244c0 <myl_core_trap>
 1067266:	48 89 f1             	mov    %rsi,%rcx
 1067269:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106726d:	48 21 d1             	and    %rdx,%rcx
 1067270:	48 01 f1             	add    %rsi,%rcx
 1067273:	48 39 d1             	cmp    %rdx,%rcx
 1067276:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 106727b:	0f 82 71 e0 ff ff    	jb     10652f2 <my.interpreter::evaluate+0x662>
 1067281:	48 8d 3d 28 e1 01 00 	lea    0x1e128(%rip),%rdi        # 10853b0 <core_durable_error.verbs+0x64b0>
 1067288:	e8 33 d2 fb ff       	call   10244c0 <myl_core_trap>
 106728d:	49 89 f0             	mov    %rsi,%r8
 1067290:	49 c1 f8 3f          	sar    $0x3f,%r8
 1067294:	49 21 d0             	and    %rdx,%r8
 1067297:	49 01 f0             	add    %rsi,%r8
 106729a:	49 39 d0             	cmp    %rdx,%r8
 106729d:	0f 82 9d e0 ff ff    	jb     1065340 <my.interpreter::evaluate+0x6b0>
 10672a3:	48 8d 3d 66 e1 01 00 	lea    0x1e166(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x6510>
 10672aa:	e8 11 d2 fb ff       	call   10244c0 <myl_core_trap>
 10672af:	48 89 f0             	mov    %rsi,%rax
 10672b2:	48 c1 f8 3f          	sar    $0x3f,%rax
 10672b6:	48 21 d0             	and    %rdx,%rax
 10672b9:	48 01 f0             	add    %rsi,%rax
 10672bc:	48 39 d0             	cmp    %rdx,%rax
 10672bf:	0f 82 cd e0 ff ff    	jb     1065392 <my.interpreter::evaluate+0x702>
 10672c5:	48 8d 3d a4 e1 01 00 	lea    0x1e1a4(%rip),%rdi        # 1085470 <core_durable_error.verbs+0x6570>
 10672cc:	e8 ef d1 fb ff       	call   10244c0 <myl_core_trap>
 10672d1:	48 89 c6             	mov    %rax,%rsi
 10672d4:	48 c1 fe 3f          	sar    $0x3f,%rsi
 10672d8:	48 21 d6             	and    %rdx,%rsi
 10672db:	48 01 c6             	add    %rax,%rsi
 10672de:	48 39 d6             	cmp    %rdx,%rsi
 10672e1:	0f 82 c3 e0 ff ff    	jb     10653aa <my.interpreter::evaluate+0x71a>
 10672e7:	48 8d 3d e2 e1 01 00 	lea    0x1e1e2(%rip),%rdi        # 10854d0 <core_durable_error.verbs+0x65d0>
 10672ee:	48 89 c6             	mov    %rax,%rsi
 10672f1:	e8 ca d1 fb ff       	call   10244c0 <myl_core_trap>
 10672f6:	48 89 c7             	mov    %rax,%rdi
 10672f9:	48 c1 ff 3f          	sar    $0x3f,%rdi
 10672fd:	48 21 d7             	and    %rdx,%rdi
 1067300:	48 01 c7             	add    %rax,%rdi
 1067303:	48 39 d7             	cmp    %rdx,%rdi
 1067306:	0f 82 0f e8 ff ff    	jb     1065b1b <my.interpreter::evaluate+0xe8b>
 106730c:	48 8d 3d 8d ab 01 00 	lea    0x1ab8d(%rip),%rdi        # 1081ea0 <core_durable_error.verbs+0x2fa0>
 1067313:	48 89 c6             	mov    %rax,%rsi
 1067316:	e8 a5 d1 fb ff       	call   10244c0 <myl_core_trap>
 106731b:	48 89 f1             	mov    %rsi,%rcx
 106731e:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067322:	48 21 d1             	and    %rdx,%rcx
 1067325:	48 01 f1             	add    %rsi,%rcx
 1067328:	48 39 d1             	cmp    %rdx,%rcx
 106732b:	0f 82 14 e8 ff ff    	jb     1065b45 <my.interpreter::evaluate+0xeb5>
 1067331:	48 8d 3d c8 ab 01 00 	lea    0x1abc8(%rip),%rdi        # 1081f00 <core_durable_error.verbs+0x3000>
 1067338:	e8 83 d1 fb ff       	call   10244c0 <myl_core_trap>
 106733d:	48 89 f1             	mov    %rsi,%rcx
 1067340:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067344:	48 21 d1             	and    %rdx,%rcx
 1067347:	48 01 f1             	add    %rsi,%rcx
 106734a:	48 39 d1             	cmp    %rdx,%rcx
 106734d:	0f 82 17 e8 ff ff    	jb     1065b6a <my.interpreter::evaluate+0xeda>
 1067353:	48 8d 3d b6 e3 01 00 	lea    0x1e3b6(%rip),%rdi        # 1085710 <core_durable_error.verbs+0x6810>
 106735a:	e8 61 d1 fb ff       	call   10244c0 <myl_core_trap>
 106735f:	49 89 c1             	mov    %rax,%r9
 1067362:	49 c1 f9 3f          	sar    $0x3f,%r9
 1067366:	49 21 d1             	and    %rdx,%r9
 1067369:	49 01 c1             	add    %rax,%r9
 106736c:	49 39 d1             	cmp    %rdx,%r9
 106736f:	0f 82 48 e8 ff ff    	jb     1065bbd <my.interpreter::evaluate+0xf2d>
 1067375:	48 8d 3d 44 d9 01 00 	lea    0x1d944(%rip),%rdi        # 1084cc0 <core_durable_error.verbs+0x5dc0>
 106737c:	48 89 c6             	mov    %rax,%rsi
 106737f:	e8 3c d1 fb ff       	call   10244c0 <myl_core_trap>
 1067384:	48 89 f7             	mov    %rsi,%rdi
 1067387:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106738b:	48 21 d7             	and    %rdx,%rdi
 106738e:	48 01 f7             	add    %rsi,%rdi
 1067391:	48 39 d7             	cmp    %rdx,%rdi
 1067394:	0f 82 ed e8 ff ff    	jb     1065c87 <my.interpreter::evaluate+0xff7>
 106739a:	48 8d 3d cf dd 01 00 	lea    0x1ddcf(%rip),%rdi        # 1085170 <core_durable_error.verbs+0x6270>
 10673a1:	e8 1a d1 fb ff       	call   10244c0 <myl_core_trap>
 10673a6:	49 89 f0             	mov    %rsi,%r8
 10673a9:	49 c1 f8 3f          	sar    $0x3f,%r8
 10673ad:	49 21 c0             	and    %rax,%r8
 10673b0:	49 01 f0             	add    %rsi,%r8
 10673b3:	49 39 c0             	cmp    %rax,%r8
 10673b6:	0f 82 67 e9 ff ff    	jb     1065d23 <my.interpreter::evaluate+0x1093>
 10673bc:	48 8d 3d ad e3 01 00 	lea    0x1e3ad(%rip),%rdi        # 1085770 <core_durable_error.verbs+0x6870>
 10673c3:	48 89 c2             	mov    %rax,%rdx
 10673c6:	e8 f5 d0 fb ff       	call   10244c0 <myl_core_trap>
 10673cb:	48 89 f1             	mov    %rsi,%rcx
 10673ce:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10673d2:	48 21 d1             	and    %rdx,%rcx
 10673d5:	48 01 f1             	add    %rsi,%rcx
 10673d8:	48 39 d1             	cmp    %rdx,%rcx
 10673db:	0f 82 3e ec ff ff    	jb     106601f <my.interpreter::evaluate+0x138f>
 10673e1:	48 8d 3d 38 d9 01 00 	lea    0x1d938(%rip),%rdi        # 1084d20 <core_durable_error.verbs+0x5e20>
 10673e8:	e8 d3 d0 fb ff       	call   10244c0 <myl_core_trap>
 10673ed:	4c 89 e1             	mov    %r12,%rcx
 10673f0:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10673f4:	48 21 d1             	and    %rdx,%rcx
 10673f7:	4c 01 e1             	add    %r12,%rcx
 10673fa:	48 39 d1             	cmp    %rdx,%rcx
 10673fd:	0f 82 28 ea ff ff    	jb     1065e2b <my.interpreter::evaluate+0x119b>
 1067403:	48 8d 3d 56 0b 02 00 	lea    0x20b56(%rip),%rdi        # 1087f60 <core_durable_error.verbs+0x9060>
 106740a:	4c 89 e6             	mov    %r12,%rsi
 106740d:	e8 ae d0 fb ff       	call   10244c0 <myl_core_trap>
 1067412:	48 8b b4 24 d0 00 00 	mov    0xd0(%rsp),%rsi
 1067419:	00 
 106741a:	48 89 f1             	mov    %rsi,%rcx
 106741d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067421:	48 21 d1             	and    %rdx,%rcx
 1067424:	48 01 f1             	add    %rsi,%rcx
 1067427:	48 39 d1             	cmp    %rdx,%rcx
 106742a:	0f 82 db ed ff ff    	jb     106620b <my.interpreter::evaluate+0x157b>
 1067430:	48 8d 3d 69 0d 02 00 	lea    0x20d69(%rip),%rdi        # 10881a0 <core_durable_error.verbs+0x92a0>
 1067437:	48 8b b4 24 d0 00 00 	mov    0xd0(%rsp),%rsi
 106743e:	00 
 106743f:	e8 7c d0 fb ff       	call   10244c0 <myl_core_trap>
 1067444:	49 89 f0             	mov    %rsi,%r8
 1067447:	49 c1 f8 3f          	sar    $0x3f,%r8
 106744b:	49 21 c8             	and    %rcx,%r8
 106744e:	49 01 f0             	add    %rsi,%r8
 1067451:	49 39 c8             	cmp    %rcx,%r8
 1067454:	0f 82 4d ed ff ff    	jb     10661a7 <my.interpreter::evaluate+0x1517>
 106745a:	48 8d 3d 0f 0d 02 00 	lea    0x20d0f(%rip),%rdi        # 1088170 <core_durable_error.verbs+0x9270>
 1067461:	48 89 ca             	mov    %rcx,%rdx
 1067464:	e8 57 d0 fb ff       	call   10244c0 <myl_core_trap>
 1067469:	48 89 f1             	mov    %rsi,%rcx
 106746c:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067470:	48 21 d1             	and    %rdx,%rcx
 1067473:	48 01 f1             	add    %rsi,%rcx
 1067476:	48 39 d1             	cmp    %rdx,%rcx
 1067479:	0f 82 be f0 ff ff    	jb     106653d <my.interpreter::evaluate+0x18ad>
 106747f:	48 8d 3d 3a 0e 02 00 	lea    0x20e3a(%rip),%rdi        # 10882c0 <core_durable_error.verbs+0x93c0>
 1067486:	e8 35 d0 fb ff       	call   10244c0 <myl_core_trap>
 106748b:	48 89 f1             	mov    %rsi,%rcx
 106748e:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067492:	48 21 d1             	and    %rdx,%rcx
 1067495:	48 01 f1             	add    %rsi,%rcx
 1067498:	48 39 d1             	cmp    %rdx,%rcx
 106749b:	0f 82 02 eb ff ff    	jb     1065fa3 <my.interpreter::evaluate+0x1313>
 10674a1:	48 8d 3d c8 0c 02 00 	lea    0x20cc8(%rip),%rdi        # 1088170 <core_durable_error.verbs+0x9270>
 10674a8:	e8 13 d0 fb ff       	call   10244c0 <myl_core_trap>
 10674ad:	48 89 f1             	mov    %rsi,%rcx
 10674b0:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10674b4:	48 21 d1             	and    %rdx,%rcx
 10674b7:	48 01 f1             	add    %rsi,%rcx
 10674ba:	48 39 d1             	cmp    %rdx,%rcx
 10674bd:	0f 82 2e ee ff ff    	jb     10662f1 <my.interpreter::evaluate+0x1661>
 10674c3:	48 8d 3d 26 0e 02 00 	lea    0x20e26(%rip),%rdi        # 10882f0 <core_durable_error.verbs+0x93f0>
 10674ca:	e8 f1 cf fb ff       	call   10244c0 <myl_core_trap>
 10674cf:	48 89 f0             	mov    %rsi,%rax
 10674d2:	48 c1 f8 3f          	sar    $0x3f,%rax
 10674d6:	48 21 d0             	and    %rdx,%rax
 10674d9:	48 01 f0             	add    %rsi,%rax
 10674dc:	48 39 d0             	cmp    %rdx,%rax
 10674df:	0f 82 13 ef ff ff    	jb     10663f8 <my.interpreter::evaluate+0x1768>
 10674e5:	48 8d 3d 94 0e 02 00 	lea    0x20e94(%rip),%rdi        # 1088380 <core_durable_error.verbs+0x9480>
 10674ec:	e8 cf cf fb ff       	call   10244c0 <myl_core_trap>
 10674f1:	48 8d 3d 08 d7 01 00 	lea    0x1d708(%rip),%rdi        # 1084c00 <core_durable_error.verbs+0x5d00>
 10674f8:	e8 43 23 fc ff       	call   1029840 <myl_core_assert_fail>
 10674fd:	48 8d 3d fc d6 01 00 	lea    0x1d6fc(%rip),%rdi        # 1084c00 <core_durable_error.verbs+0x5d00>
 1067504:	e8 37 23 fc ff       	call   1029840 <myl_core_assert_fail>
 1067509:	48 8d 3d f0 d6 01 00 	lea    0x1d6f0(%rip),%rdi        # 1084c00 <core_durable_error.verbs+0x5d00>
 1067510:	e8 2b 23 fc ff       	call   1029840 <myl_core_assert_fail>
 1067515:	48 8d 3d e4 d6 01 00 	lea    0x1d6e4(%rip),%rdi        # 1084c00 <core_durable_error.verbs+0x5d00>
 106751c:	e8 1f 23 fc ff       	call   1029840 <myl_core_assert_fail>
 1067521:	48 8d 3d d8 d6 01 00 	lea    0x1d6d8(%rip),%rdi        # 1084c00 <core_durable_error.verbs+0x5d00>
 1067528:	e8 13 23 fc ff       	call   1029840 <myl_core_assert_fail>
 106752d:	4d 89 f4             	mov    %r14,%r12
 1067530:	49 89 d6             	mov    %rdx,%r14
 1067533:	bf 05 00 00 00       	mov    $0x5,%edi
 1067538:	be 08 00 00 00       	mov    $0x8,%esi
 106753d:	e8 3e b4 fb ff       	call   1022980 <myl_core_list_new_slow>
 1067542:	48 89 c3             	mov    %rax,%rbx
 1067545:	48 8b 40 08          	mov    0x8(%rax),%rax
 1067549:	48 3b 43 10          	cmp    0x10(%rbx),%rax
 106754d:	48 8d 0d 94 c6 fa ff 	lea    -0x5396c(%rip),%rcx        # 1013be8 <core_number_pairs+0xc968>
 1067554:	48 89 4b 18          	mov    %rcx,0x18(%rbx)
 1067558:	72 14                	jb     106756e <my.interpreter::evaluate+0x28de>
 106755a:	be 08 00 00 00       	mov    $0x8,%esi
 106755f:	48 89 df             	mov    %rbx,%rdi
 1067562:	e8 d9 b4 fb ff       	call   1022a40 <myl_core_list_grow>
 1067567:	48 89 c3             	mov    %rax,%rbx
 106756a:	48 8b 40 08          	mov    0x8(%rax),%rax
 106756e:	4c 89 f2             	mov    %r14,%rdx
 1067571:	48 8b 2c 24          	mov    (%rsp),%rbp
 1067575:	4d 89 e6             	mov    %r12,%r14
 1067578:	e9 df f6 ff ff       	jmp    1066c5c <my.interpreter::evaluate+0x1fcc>
 106757d:	be 08 00 00 00       	mov    $0x8,%esi
 1067582:	48 89 df             	mov    %rbx,%rdi
 1067585:	4d 89 f4             	mov    %r14,%r12
 1067588:	49 89 c6             	mov    %rax,%r14
 106758b:	e8 b0 b4 fb ff       	call   1022a40 <myl_core_list_grow>
 1067590:	48 89 c3             	mov    %rax,%rbx
 1067593:	4c 89 f0             	mov    %r14,%rax
 1067596:	4d 89 e6             	mov    %r12,%r14
 1067599:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 106759d:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 10675a1:	e9 e2 f6 ff ff       	jmp    1066c88 <my.interpreter::evaluate+0x1ff8>
 10675a6:	be 08 00 00 00       	mov    $0x8,%esi
 10675ab:	48 89 df             	mov    %rbx,%rdi
 10675ae:	e8 8d b4 fb ff       	call   1022a40 <myl_core_list_grow>
 10675b3:	48 89 c3             	mov    %rax,%rbx
 10675b6:	48 8b 48 08          	mov    0x8(%rax),%rcx
 10675ba:	e9 de f6 ff ff       	jmp    1066c9d <my.interpreter::evaluate+0x200d>
 10675bf:	be 08 00 00 00       	mov    $0x8,%esi
 10675c4:	48 89 df             	mov    %rbx,%rdi
 10675c7:	49 89 c6             	mov    %rax,%r14
 10675ca:	e8 71 b4 fb ff       	call   1022a40 <myl_core_list_grow>
 10675cf:	48 89 c3             	mov    %rax,%rbx
 10675d2:	4c 89 f0             	mov    %r14,%rax
 10675d5:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 10675d9:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 10675dd:	e9 e7 f6 ff ff       	jmp    1066cc9 <my.interpreter::evaluate+0x2039>
 10675e2:	be 08 00 00 00       	mov    $0x8,%esi
 10675e7:	48 89 df             	mov    %rbx,%rdi
 10675ea:	e8 51 b4 fb ff       	call   1022a40 <myl_core_list_grow>
 10675ef:	48 89 c3             	mov    %rax,%rbx
 10675f2:	48 8b 48 08          	mov    0x8(%rax),%rcx
 10675f6:	e9 e3 f6 ff ff       	jmp    1066cde <my.interpreter::evaluate+0x204e>
 10675fb:	bf 03 00 00 00       	mov    $0x3,%edi
 1067600:	be 08 00 00 00       	mov    $0x8,%esi
 1067605:	e8 76 b3 fb ff       	call   1022980 <myl_core_list_new_slow>
 106760a:	48 89 c3             	mov    %rax,%rbx
 106760d:	48 8b 40 08          	mov    0x8(%rax),%rax
 1067611:	48 3b 43 10          	cmp    0x10(%rbx),%rax
 1067615:	48 8d 0d cc c5 fa ff 	lea    -0x53a34(%rip),%rcx        # 1013be8 <core_number_pairs+0xc968>
 106761c:	48 89 4b 18          	mov    %rcx,0x18(%rbx)
 1067620:	72 14                	jb     1067636 <my.interpreter::evaluate+0x29a6>
 1067622:	be 08 00 00 00       	mov    $0x8,%esi
 1067627:	48 89 df             	mov    %rbx,%rdi
 106762a:	e8 11 b4 fb ff       	call   1022a40 <myl_core_list_grow>
 106762f:	48 89 c3             	mov    %rax,%rbx
 1067632:	48 8b 40 08          	mov    0x8(%rax),%rax
 1067636:	48 8b 2c 24          	mov    (%rsp),%rbp
 106763a:	4c 8b b4 24 90 00 00 	mov    0x90(%rsp),%r14
 1067641:	00 
 1067642:	e9 d2 f7 ff ff       	jmp    1066e19 <my.interpreter::evaluate+0x2189>
 1067647:	be 08 00 00 00       	mov    $0x8,%esi
 106764c:	48 89 df             	mov    %rbx,%rdi
 106764f:	49 89 c6             	mov    %rax,%r14
 1067652:	e8 e9 b3 fb ff       	call   1022a40 <myl_core_list_grow>
 1067657:	48 89 c3             	mov    %rax,%rbx
 106765a:	4c 89 f0             	mov    %r14,%rax
 106765d:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1067661:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 1067665:	e9 db f7 ff ff       	jmp    1066e45 <my.interpreter::evaluate+0x21b5>
 106766a:	be 08 00 00 00       	mov    $0x8,%esi
 106766f:	48 89 df             	mov    %rbx,%rdi
 1067672:	e8 c9 b3 fb ff       	call   1022a40 <myl_core_list_grow>
 1067677:	48 89 c3             	mov    %rax,%rbx
 106767a:	48 8b 48 08          	mov    0x8(%rax),%rcx
 106767e:	e9 d7 f7 ff ff       	jmp    1066e5a <my.interpreter::evaluate+0x21ca>
 1067683:	0f b6 c0             	movzbl %al,%eax
 1067686:	83 f8 01             	cmp    $0x1,%eax
 1067689:	0f 84 ba 00 00 00    	je     1067749 <my.interpreter::evaluate+0x2ab9>
 106768f:	85 c0                	test   %eax,%eax
 1067691:	0f 85 be 00 00 00    	jne    1067755 <my.interpreter::evaluate+0x2ac5>
 1067697:	48 8d 3d 72 d4 01 00 	lea    0x1d472(%rip),%rdi        # 1084b10 <core_durable_error.verbs+0x5c10>
 106769e:	e8 9d 21 fc ff       	call   1029840 <myl_core_assert_fail>
 10676a3:	0f b6 c2             	movzbl %dl,%eax
 10676a6:	83 f8 01             	cmp    $0x1,%eax
 10676a9:	0f 84 02 01 00 00    	je     10677b1 <my.interpreter::evaluate+0x2b21>
 10676af:	85 c0                	test   %eax,%eax
 10676b1:	0f 85 06 01 00 00    	jne    10677bd <my.interpreter::evaluate+0x2b2d>
 10676b7:	48 8d 3d 52 d4 01 00 	lea    0x1d452(%rip),%rdi        # 1084b10 <core_durable_error.verbs+0x5c10>
 10676be:	e8 7d 21 fc ff       	call   1029840 <myl_core_assert_fail>
 10676c3:	83 fa 01             	cmp    $0x1,%edx
 10676c6:	0f 84 92 01 00 00    	je     106785e <my.interpreter::evaluate+0x2bce>
 10676cc:	85 d2                	test   %edx,%edx
 10676ce:	0f 85 96 01 00 00    	jne    106786a <my.interpreter::evaluate+0x2bda>
 10676d4:	48 8d 3d 35 d4 01 00 	lea    0x1d435(%rip),%rdi        # 1084b10 <core_durable_error.verbs+0x5c10>
 10676db:	e8 60 21 fc ff       	call   1029840 <myl_core_assert_fail>
 10676e0:	0f b6 c2             	movzbl %dl,%eax
 10676e3:	83 f8 01             	cmp    $0x1,%eax
 10676e6:	0f 84 0f 02 00 00    	je     10678fb <my.interpreter::evaluate+0x2c6b>
 10676ec:	85 c0                	test   %eax,%eax
 10676ee:	0f 85 13 02 00 00    	jne    1067907 <my.interpreter::evaluate+0x2c77>
 10676f4:	48 8d 3d 15 d4 01 00 	lea    0x1d415(%rip),%rdi        # 1084b10 <core_durable_error.verbs+0x5c10>
 10676fb:	e8 40 21 fc ff       	call   1029840 <myl_core_assert_fail>
 1067700:	48 8d 3d c9 a7 01 00 	lea    0x1a7c9(%rip),%rdi        # 1081ed0 <core_durable_error.verbs+0x2fd0>
 1067707:	e8 34 21 fc ff       	call   1029840 <myl_core_assert_fail>
 106770c:	48 8d 3d bd a7 01 00 	lea    0x1a7bd(%rip),%rdi        # 1081ed0 <core_durable_error.verbs+0x2fd0>
 1067713:	e8 28 21 fc ff       	call   1029840 <myl_core_assert_fail>
 1067718:	48 8d 3d b1 aa 01 00 	lea    0x1aab1(%rip),%rdi        # 10821d0 <core_durable_error.verbs+0x32d0>
 106771f:	ba 01 00 00 00       	mov    $0x1,%edx
 1067724:	e8 97 cd fb ff       	call   10244c0 <myl_core_trap>
 1067729:	48 8d 3d d0 dd 01 00 	lea    0x1ddd0(%rip),%rdi        # 1085500 <core_durable_error.verbs+0x6600>
 1067730:	ba 01 00 00 00       	mov    $0x1,%edx
 1067735:	48 89 c6             	mov    %rax,%rsi
 1067738:	e8 83 cd fb ff       	call   10244c0 <myl_core_trap>
 106773d:	48 8d 3d 8c a7 01 00 	lea    0x1a78c(%rip),%rdi        # 1081ed0 <core_durable_error.verbs+0x2fd0>
 1067744:	e8 f7 20 fc ff       	call   1029840 <myl_core_assert_fail>
 1067749:	48 8d 3d f0 d3 01 00 	lea    0x1d3f0(%rip),%rdi        # 1084b40 <core_durable_error.verbs+0x5c40>
 1067750:	e8 eb 20 fc ff       	call   1029840 <myl_core_assert_fail>
 1067755:	48 8d 3d 14 d4 01 00 	lea    0x1d414(%rip),%rdi        # 1084b70 <core_durable_error.verbs+0x5c70>
 106775c:	e8 df 20 fc ff       	call   1029840 <myl_core_assert_fail>
 1067761:	48 8d 3d 48 d9 01 00 	lea    0x1d948(%rip),%rdi        # 10850b0 <core_durable_error.verbs+0x61b0>
 1067768:	ba 01 00 00 00       	mov    $0x1,%edx
 106776d:	48 89 c6             	mov    %rax,%rsi
 1067770:	e8 4b cd fb ff       	call   10244c0 <myl_core_trap>
 1067775:	48 8d 3d 74 db 01 00 	lea    0x1db74(%rip),%rdi        # 10852f0 <core_durable_error.verbs+0x63f0>
 106777c:	ba 01 00 00 00       	mov    $0x1,%edx
 1067781:	48 89 c6             	mov    %rax,%rsi
 1067784:	e8 37 cd fb ff       	call   10244c0 <myl_core_trap>
 1067789:	48 8d 3d 70 da 01 00 	lea    0x1da70(%rip),%rdi        # 1085200 <core_durable_error.verbs+0x6300>
 1067790:	ba 01 00 00 00       	mov    $0x1,%edx
 1067795:	48 89 c6             	mov    %rax,%rsi
 1067798:	e8 23 cd fb ff       	call   10244c0 <myl_core_trap>
 106779d:	48 8d 3d dc de 01 00 	lea    0x1dedc(%rip),%rdi        # 1085680 <core_durable_error.verbs+0x6780>
 10677a4:	ba 01 00 00 00       	mov    $0x1,%edx
 10677a9:	48 89 c6             	mov    %rax,%rsi
 10677ac:	e8 0f cd fb ff       	call   10244c0 <myl_core_trap>
 10677b1:	48 8d 3d 88 d3 01 00 	lea    0x1d388(%rip),%rdi        # 1084b40 <core_durable_error.verbs+0x5c40>
 10677b8:	e8 83 20 fc ff       	call   1029840 <myl_core_assert_fail>
 10677bd:	48 8d 3d ac d3 01 00 	lea    0x1d3ac(%rip),%rdi        # 1084b70 <core_durable_error.verbs+0x5c70>
 10677c4:	e8 77 20 fc ff       	call   1029840 <myl_core_assert_fail>
 10677c9:	48 8d 3d c0 dd 01 00 	lea    0x1ddc0(%rip),%rdi        # 1085590 <core_durable_error.verbs+0x6690>
 10677d0:	ba 01 00 00 00       	mov    $0x1,%edx
 10677d5:	e8 e6 cc fb ff       	call   10244c0 <myl_core_trap>
 10677da:	48 8d 3d cf f3 01 00 	lea    0x1f3cf(%rip),%rdi        # 1086bb0 <core_durable_error.verbs+0x7cb0>
 10677e1:	48 89 c6             	mov    %rax,%rsi
 10677e4:	4c 89 f2             	mov    %r14,%rdx
 10677e7:	e8 d4 cc fb ff       	call   10244c0 <myl_core_trap>
 10677ec:	48 8d 3d ed f3 01 00 	lea    0x1f3ed(%rip),%rdi        # 1086be0 <core_durable_error.verbs+0x7ce0>
 10677f3:	ba 01 00 00 00       	mov    $0x1,%edx
 10677f8:	e8 c3 cc fb ff       	call   10244c0 <myl_core_trap>
 10677fd:	48 8d 3d 0c d6 01 00 	lea    0x1d60c(%rip),%rdi        # 1084e10 <core_durable_error.verbs+0x5f10>
 1067804:	ba 01 00 00 00       	mov    $0x1,%edx
 1067809:	4c 89 ce             	mov    %r9,%rsi
 106780c:	e8 af cc fb ff       	call   10244c0 <myl_core_trap>
 1067811:	48 8d 3d 28 d6 01 00 	lea    0x1d628(%rip),%rdi        # 1084e40 <core_durable_error.verbs+0x5f40>
 1067818:	ba 01 00 00 00       	mov    $0x1,%edx
 106781d:	48 89 de             	mov    %rbx,%rsi
 1067820:	e8 9b cc fb ff       	call   10244c0 <myl_core_trap>
 1067825:	48 8d 3d 04 d7 01 00 	lea    0x1d704(%rip),%rdi        # 1084f30 <core_durable_error.verbs+0x6030>
 106782c:	ba 01 00 00 00       	mov    $0x1,%edx
 1067831:	48 89 de             	mov    %rbx,%rsi
 1067834:	e8 87 cc fb ff       	call   10244c0 <myl_core_trap>
 1067839:	48 8d 3d 10 db 01 00 	lea    0x1db10(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x6450>
 1067840:	ba 01 00 00 00       	mov    $0x1,%edx
 1067845:	e8 76 cc fb ff       	call   10244c0 <myl_core_trap>
 106784a:	48 8d 3d 2f db 01 00 	lea    0x1db2f(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x6480>
 1067851:	ba 01 00 00 00       	mov    $0x1,%edx
 1067856:	48 89 c6             	mov    %rax,%rsi
 1067859:	e8 62 cc fb ff       	call   10244c0 <myl_core_trap>
 106785e:	48 8d 3d db d2 01 00 	lea    0x1d2db(%rip),%rdi        # 1084b40 <core_durable_error.verbs+0x5c40>
 1067865:	e8 d6 1f fc ff       	call   1029840 <myl_core_assert_fail>
 106786a:	48 8d 3d ff d2 01 00 	lea    0x1d2ff(%rip),%rdi        # 1084b70 <core_durable_error.verbs+0x5c70>
 1067871:	e8 ca 1f fc ff       	call   1029840 <myl_core_assert_fail>
 1067876:	48 8d 3d 63 db 01 00 	lea    0x1db63(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x64e0>
 106787d:	ba 01 00 00 00       	mov    $0x1,%edx
 1067882:	48 89 ce             	mov    %rcx,%rsi
 1067885:	e8 36 cc fb ff       	call   10244c0 <myl_core_trap>
 106788a:	48 8d 3d af db 01 00 	lea    0x1dbaf(%rip),%rdi        # 1085440 <core_durable_error.verbs+0x6540>
 1067891:	ba 01 00 00 00       	mov    $0x1,%edx
 1067896:	48 89 c6             	mov    %rax,%rsi
 1067899:	e8 22 cc fb ff       	call   10244c0 <myl_core_trap>
 106789e:	48 8d 3d fb db 01 00 	lea    0x1dbfb(%rip),%rdi        # 10854a0 <core_durable_error.verbs+0x65a0>
 10678a5:	ba 01 00 00 00       	mov    $0x1,%edx
 10678aa:	e8 11 cc fb ff       	call   10244c0 <myl_core_trap>
 10678af:	48 8d 3d 1a a6 01 00 	lea    0x1a61a(%rip),%rdi        # 1081ed0 <core_durable_error.verbs+0x2fd0>
 10678b6:	e8 85 1f fc ff       	call   1029840 <myl_core_assert_fail>
 10678bb:	48 8d 3d 7e de 01 00 	lea    0x1de7e(%rip),%rdi        # 1085740 <core_durable_error.verbs+0x6840>
 10678c2:	ba 01 00 00 00       	mov    $0x1,%edx
 10678c7:	e8 f4 cb fb ff       	call   10244c0 <myl_core_trap>
 10678cc:	48 8d 3d bd d3 01 00 	lea    0x1d3bd(%rip),%rdi        # 1084c90 <core_durable_error.verbs+0x5d90>
 10678d3:	ba 01 00 00 00       	mov    $0x1,%edx
 10678d8:	48 89 ce             	mov    %rcx,%rsi
 10678db:	e8 e0 cb fb ff       	call   10244c0 <myl_core_trap>
 10678e0:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 10678e7:	00 00 80 
 10678ea:	48 8d 3d 1f d8 01 00 	lea    0x1d81f(%rip),%rdi        # 1085110 <core_durable_error.verbs+0x6210>
 10678f1:	ba 01 00 00 00       	mov    $0x1,%edx
 10678f6:	e8 c5 cb fb ff       	call   10244c0 <myl_core_trap>
 10678fb:	48 8d 3d 3e d2 01 00 	lea    0x1d23e(%rip),%rdi        # 1084b40 <core_durable_error.verbs+0x5c40>
 1067902:	e8 39 1f fc ff       	call   1029840 <myl_core_assert_fail>
 1067907:	48 8d 3d 62 d2 01 00 	lea    0x1d262(%rip),%rdi        # 1084b70 <core_durable_error.verbs+0x5c70>
 106790e:	e8 2d 1f fc ff       	call   1029840 <myl_core_assert_fail>
 1067913:	48 8d 3d 26 d8 01 00 	lea    0x1d826(%rip),%rdi        # 1085140 <core_durable_error.verbs+0x6240>
 106791a:	ba 01 00 00 00       	mov    $0x1,%edx
 106791f:	48 89 c6             	mov    %rax,%rsi
 1067922:	e8 99 cb fb ff       	call   10244c0 <myl_core_trap>
 1067927:	48 8d 3d 72 de 01 00 	lea    0x1de72(%rip),%rdi        # 10857a0 <core_durable_error.verbs+0x68a0>
 106792e:	ba 01 00 00 00       	mov    $0x1,%edx
 1067933:	e8 88 cb fb ff       	call   10244c0 <myl_core_trap>
 1067938:	48 8d 3d b1 d3 01 00 	lea    0x1d3b1(%rip),%rdi        # 1084cf0 <core_durable_error.verbs+0x5df0>
 106793f:	ba 01 00 00 00       	mov    $0x1,%edx
 1067944:	48 89 c6             	mov    %rax,%rsi
 1067947:	e8 74 cb fb ff       	call   10244c0 <myl_core_trap>
 106794c:	48 8d 3d 3d 06 02 00 	lea    0x2063d(%rip),%rdi        # 1087f90 <core_durable_error.verbs+0x9090>
 1067953:	e8 e8 1e fc ff       	call   1029840 <myl_core_assert_fail>
 1067958:	48 8d 3d b1 07 02 00 	lea    0x207b1(%rip),%rdi        # 1088110 <core_durable_error.verbs+0x9210>
 106795f:	4c 89 f2             	mov    %r14,%rdx
 1067962:	e8 59 cb fb ff       	call   10244c0 <myl_core_trap>
 1067967:	48 8d 3d d2 07 02 00 	lea    0x207d2(%rip),%rdi        # 1088140 <core_durable_error.verbs+0x9240>
 106796e:	ba 01 00 00 00       	mov    $0x1,%edx
 1067973:	48 89 ce             	mov    %rcx,%rsi
 1067976:	e8 45 cb fb ff       	call   10244c0 <myl_core_trap>
 106797b:	48 8d 3d de 08 02 00 	lea    0x208de(%rip),%rdi        # 1088260 <core_durable_error.verbs+0x9360>
 1067982:	4c 89 f2             	mov    %r14,%rdx
 1067985:	e8 36 cb fb ff       	call   10244c0 <myl_core_trap>
 106798a:	48 8d 3d ff 08 02 00 	lea    0x208ff(%rip),%rdi        # 1088290 <core_durable_error.verbs+0x9390>
 1067991:	ba 01 00 00 00       	mov    $0x1,%edx
 1067996:	48 89 c6             	mov    %rax,%rsi
 1067999:	e8 22 cb fb ff       	call   10244c0 <myl_core_trap>
 106799e:	48 8d 3d 6b 07 02 00 	lea    0x2076b(%rip),%rdi        # 1088110 <core_durable_error.verbs+0x9210>
 10679a5:	e8 16 cb fb ff       	call   10244c0 <myl_core_trap>
 10679aa:	48 8d 3d 8f 07 02 00 	lea    0x2078f(%rip),%rdi        # 1088140 <core_durable_error.verbs+0x9240>
 10679b1:	ba 01 00 00 00       	mov    $0x1,%edx
 10679b6:	48 89 c6             	mov    %rax,%rsi
 10679b9:	e8 02 cb fb ff       	call   10244c0 <myl_core_trap>
 10679be:	48 8d 3d 5b 09 02 00 	lea    0x2095b(%rip),%rdi        # 1088320 <core_durable_error.verbs+0x9420>
 10679c5:	ba 01 00 00 00       	mov    $0x1,%edx
 10679ca:	e8 f1 ca fb ff       	call   10244c0 <myl_core_trap>
 10679cf:	48 8d 3d 7a 09 02 00 	lea    0x2097a(%rip),%rdi        # 1088350 <core_durable_error.verbs+0x9450>
 10679d6:	ba 01 00 00 00       	mov    $0x1,%edx
 10679db:	48 89 c6             	mov    %rax,%rsi
 10679de:	e8 dd ca fb ff       	call   10244c0 <myl_core_trap>

Disassembly of section .plt:
