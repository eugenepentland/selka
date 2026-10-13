
.tmp/lox-eda-parity/P4/compact-sret-001/candidate/lox:     file format elf64-x86-64


Disassembly of section .text:

0000000001064c50 <my.interpreter::evaluate>:
 1064c50:	55                   	push   %rbp
 1064c51:	41 57                	push   %r15
 1064c53:	41 56                	push   %r14
 1064c55:	41 55                	push   %r13
 1064c57:	41 54                	push   %r12
 1064c59:	53                   	push   %rbx
 1064c5a:	48 81 ec e8 01 00 00 	sub    $0x1e8,%rsp
 1064c61:	48 89 cb             	mov    %rcx,%rbx
 1064c64:	49 89 d2             	mov    %rdx,%r10
 1064c67:	49 89 f7             	mov    %rsi,%r15
 1064c6a:	48 89 fd             	mov    %rdi,%rbp
 1064c6d:	48 8b b4 24 40 02 00 	mov    0x240(%rsp),%rsi
 1064c74:	00 
 1064c75:	49 8b 57 08          	mov    0x8(%r15),%rdx
 1064c79:	48 39 d6             	cmp    %rdx,%rsi
 1064c7c:	0f 83 e8 22 00 00    	jae    1066f6a <my.interpreter::evaluate+0x231a>
 1064c82:	48 89 f0             	mov    %rsi,%rax
 1064c85:	4c 8b b4 24 38 02 00 	mov    0x238(%rsp),%r14
 1064c8c:	00 
 1064c8d:	4c 8b 9c 24 28 02 00 	mov    0x228(%rsp),%r11
 1064c94:	00 
 1064c95:	48 6b c8 70          	imul   $0x70,%rax,%rcx
 1064c99:	49 8d 04 0f          	lea    (%r15,%rcx,1),%rax
 1064c9d:	48 83 c0 20          	add    $0x20,%rax
 1064ca1:	41 8b 4c 0f 20       	mov    0x20(%r15,%rcx,1),%ecx
 1064ca6:	48 83 f9 0a          	cmp    $0xa,%rcx
 1064caa:	0f 87 99 0b 00 00    	ja     1065849 <my.interpreter::evaluate+0xbf9>
 1064cb0:	4c 89 7c 24 10       	mov    %r15,0x10(%rsp)
 1064cb5:	4c 8b a4 24 48 02 00 	mov    0x248(%rsp),%r12
 1064cbc:	00 
 1064cbd:	4c 8b bc 24 20 02 00 	mov    0x220(%rsp),%r15
 1064cc4:	00 
 1064cc5:	48 8d 15 b0 29 fa ff 	lea    -0x5d650(%rip),%rdx        # 100767c <core_number_pairs+0x41c>
 1064ccc:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 1064cd0:	48 01 d1             	add    %rdx,%rcx
 1064cd3:	4c 89 4c 24 40       	mov    %r9,0x40(%rsp)
 1064cd8:	4c 89 44 24 38       	mov    %r8,0x38(%rsp)
 1064cdd:	ff e1                	jmp    *%rcx
 1064cdf:	48 8b 48 20          	mov    0x20(%rax),%rcx
 1064ce3:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
 1064ce8:	48 89 d9             	mov    %rbx,%rcx
 1064ceb:	4c 89 e3             	mov    %r12,%rbx
 1064cee:	4c 8b 60 30          	mov    0x30(%rax),%r12
 1064cf2:	4d 89 fd             	mov    %r15,%r13
 1064cf5:	4c 8b 78 40          	mov    0x40(%rax),%r15
 1064cf9:	48 8b 50 48          	mov    0x48(%rax),%rdx
 1064cfd:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
 1064d02:	4c 89 d2             	mov    %r10,%rdx
 1064d05:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 1064d0c:	00 00 
 1064d0e:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 1064d13:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1064d18:	53                   	push   %rbx
 1064d19:	ff 70 38             	push   0x38(%rax)
 1064d1c:	41 56                	push   %r14
 1064d1e:	41 52                	push   %r10
 1064d20:	41 53                	push   %r11
 1064d22:	41 55                	push   %r13
 1064d24:	e8 27 ff ff ff       	call   1064c50 <my.interpreter::evaluate>
 1064d29:	48 83 c4 30          	add    $0x30,%rsp
 1064d2d:	c5 f8 10 84 24 80 00 	vmovups 0x80(%rsp),%xmm0
 1064d34:	00 00 
 1064d36:	4c 8b b4 24 90 00 00 	mov    0x90(%rsp),%r14
 1064d3d:	00 
 1064d3e:	80 7c 24 68 01       	cmpb   $0x1,0x68(%rsp)
 1064d43:	c5 f8 29 44 24 10    	vmovaps %xmm0,0x10(%rsp)
 1064d49:	0f 84 2e 1b 00 00    	je     106687d <my.interpreter::evaluate+0x1c2d>
 1064d4f:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 1064d53:	0f 84 5a 12 00 00    	je     1065fb3 <my.interpreter::evaluate+0x1363>
 1064d59:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1064d5e:	48 8b b7 a8 00 00 00 	mov    0xa8(%rdi),%rsi
 1064d65:	4d 85 ff             	test   %r15,%r15
 1064d68:	0f 8e 29 0e 00 00    	jle    1065b97 <my.interpreter::evaluate+0xf47>
 1064d6e:	48 8b 07             	mov    (%rdi),%rax
 1064d71:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1064d75:	48 83 c0 20          	add    $0x20,%rax
 1064d79:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1064d80:	48 39 d6             	cmp    %rdx,%rsi
 1064d83:	73 22                	jae    1064da7 <my.interpreter::evaluate+0x157>
 1064d85:	48 89 f1             	mov    %rsi,%rcx
 1064d88:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1064d8c:	83 3c 08 09          	cmpl   $0x9,(%rax,%rcx,1)
 1064d90:	0f 85 72 27 00 00    	jne    1067508 <my.interpreter::evaluate+0x28b8>
 1064d96:	48 01 c1             	add    %rax,%rcx
 1064d99:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 1064d9d:	49 ff cf             	dec    %r15
 1064da0:	75 de                	jne    1064d80 <my.interpreter::evaluate+0x130>
 1064da2:	e9 f0 0d 00 00       	jmp    1065b97 <my.interpreter::evaluate+0xf47>
 1064da7:	48 89 f1             	mov    %rsi,%rcx
 1064daa:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1064dae:	48 21 d1             	and    %rdx,%rcx
 1064db1:	48 01 f1             	add    %rsi,%rcx
 1064db4:	48 39 d1             	cmp    %rdx,%rcx
 1064db7:	72 cf                	jb     1064d88 <my.interpreter::evaluate+0x138>
 1064db9:	48 8d 3d 60 fe 01 00 	lea    0x1fe60(%rip),%rdi        # 1084c20 <core_durable_error.verbs+0x5cd0>
 1064dc0:	e8 bb f6 fb ff       	call   1024480 <myl_core_trap>
 1064dc5:	4c 89 d2             	mov    %r10,%rdx
 1064dc8:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 1064dcf:	00 00 
 1064dd1:	48 8d bc 24 b8 01 00 	lea    0x1b8(%rsp),%rdi
 1064dd8:	00 
 1064dd9:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1064dde:	48 89 d9             	mov    %rbx,%rcx
 1064de1:	41 54                	push   %r12
 1064de3:	ff 70 08             	push   0x8(%rax)
 1064de6:	41 56                	push   %r14
 1064de8:	41 52                	push   %r10
 1064dea:	41 53                	push   %r11
 1064dec:	41 57                	push   %r15
 1064dee:	e8 5d fe ff ff       	call   1064c50 <my.interpreter::evaluate>
 1064df3:	48 83 c4 30          	add    $0x30,%rsp
 1064df7:	0f b6 84 24 b8 01 00 	movzbl 0x1b8(%rsp),%eax
 1064dfe:	00 
 1064dff:	c5 f9 10 84 24 c0 01 	vmovupd 0x1c0(%rsp),%xmm0
 1064e06:	00 00 
 1064e08:	48 8b 8c 24 d0 01 00 	mov    0x1d0(%rsp),%rcx
 1064e0f:	00 
 1064e10:	0f b6 94 24 d8 01 00 	movzbl 0x1d8(%rsp),%edx
 1064e17:	00 
 1064e18:	48 8b b4 24 e0 01 00 	mov    0x1e0(%rsp),%rsi
 1064e1f:	00 
 1064e20:	48 83 f8 01          	cmp    $0x1,%rax
 1064e24:	0f 84 c1 19 00 00    	je     10667eb <my.interpreter::evaluate+0x1b9b>
 1064e2a:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1064e2e:	c5 f9 11 45 08       	vmovupd %xmm0,0x8(%rbp)
 1064e33:	48 89 4d 18          	mov    %rcx,0x18(%rbp)
 1064e37:	48 89 55 20          	mov    %rdx,0x20(%rbp)
 1064e3b:	48 89 75 28          	mov    %rsi,0x28(%rbp)
 1064e3f:	e9 11 21 00 00       	jmp    1066f55 <my.interpreter::evaluate+0x2305>
 1064e44:	48 8b 78 30          	mov    0x30(%rax),%rdi
 1064e48:	49 8b 09             	mov    (%r9),%rcx
 1064e4b:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 1064e52:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1064e56:	48 85 ff             	test   %rdi,%rdi
 1064e59:	0f 8e 6a 0a 00 00    	jle    10658c9 <my.interpreter::evaluate+0xc79>
 1064e5f:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 1064e63:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1064e6a:	0f 1f 84 00 00 00 00 
 1064e71:	00 
 1064e72:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1064e79:	1f 84 00 00 00 00 00 
 1064e80:	48 39 d6             	cmp    %rdx,%rsi
 1064e83:	73 23                	jae    1064ea8 <my.interpreter::evaluate+0x258>
 1064e85:	49 89 f2             	mov    %rsi,%r10
 1064e88:	49 6b f2 38          	imul   $0x38,%r10,%rsi
 1064e8c:	41 83 3c 30 09       	cmpl   $0x9,(%r8,%rsi,1)
 1064e91:	0f 85 41 26 00 00    	jne    10674d8 <my.interpreter::evaluate+0x2888>
 1064e97:	4c 01 c6             	add    %r8,%rsi
 1064e9a:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 1064e9e:	48 ff cf             	dec    %rdi
 1064ea1:	75 dd                	jne    1064e80 <my.interpreter::evaluate+0x230>
 1064ea3:	e9 21 0a 00 00       	jmp    10658c9 <my.interpreter::evaluate+0xc79>
 1064ea8:	49 89 f2             	mov    %rsi,%r10
 1064eab:	49 c1 fa 3f          	sar    $0x3f,%r10
 1064eaf:	49 21 d2             	and    %rdx,%r10
 1064eb2:	49 01 f2             	add    %rsi,%r10
 1064eb5:	49 39 d2             	cmp    %rdx,%r10
 1064eb8:	72 ce                	jb     1064e88 <my.interpreter::evaluate+0x238>
 1064eba:	48 8d 3d 5f fd 01 00 	lea    0x1fd5f(%rip),%rdi        # 1084c20 <core_durable_error.verbs+0x5cd0>
 1064ec1:	e8 ba f5 fb ff       	call   1024480 <myl_core_trap>
 1064ec6:	48 89 6c 24 08       	mov    %rbp,0x8(%rsp)
 1064ecb:	48 8b 48 28          	mov    0x28(%rax),%rcx
 1064ecf:	48 89 4c 24 58       	mov    %rcx,0x58(%rsp)
 1064ed4:	48 8b 68 38          	mov    0x38(%rax),%rbp
 1064ed8:	4c 89 d2             	mov    %r10,%rdx
 1064edb:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 1064ee2:	00 00 
 1064ee4:	48 8d bc 24 08 01 00 	lea    0x108(%rsp),%rdi
 1064eeb:	00 
 1064eec:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1064ef1:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 1064ef6:	48 89 d9             	mov    %rbx,%rcx
 1064ef9:	41 54                	push   %r12
 1064efb:	ff 70 08             	push   0x8(%rax)
 1064efe:	41 56                	push   %r14
 1064f00:	41 52                	push   %r10
 1064f02:	41 53                	push   %r11
 1064f04:	41 57                	push   %r15
 1064f06:	e8 45 fd ff ff       	call   1064c50 <my.interpreter::evaluate>
 1064f0b:	48 83 c4 30          	add    $0x30,%rsp
 1064f0f:	4c 8b 94 24 20 01 00 	mov    0x120(%rsp),%r10
 1064f16:	00 
 1064f17:	0f b6 bc 24 28 01 00 	movzbl 0x128(%rsp),%edi
 1064f1e:	00 
 1064f1f:	4c 8b 9c 24 30 01 00 	mov    0x130(%rsp),%r11
 1064f26:	00 
 1064f27:	80 bc 24 08 01 00 00 	cmpb   $0x1,0x108(%rsp)
 1064f2e:	01 
 1064f2f:	0f 84 d3 18 00 00    	je     1066808 <my.interpreter::evaluate+0x1bb8>
 1064f35:	4c 8b 75 08          	mov    0x8(%rbp),%r14
 1064f39:	4d 85 f6             	test   %r14,%r14
 1064f3c:	0f 84 3c 0e 00 00    	je     1065d7e <my.interpreter::evaluate+0x112e>
 1064f42:	4d 89 fd             	mov    %r15,%r13
 1064f45:	45 31 ff             	xor    %r15d,%r15d
 1064f48:	4c 8d a4 24 88 01 00 	lea    0x188(%rsp),%r12
 1064f4f:	00 
 1064f50:	4c 8b 4c 24 40       	mov    0x40(%rsp),%r9
 1064f55:	4c 8b 44 24 38       	mov    0x38(%rsp),%r8
 1064f5a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1064f61:	0f 1f 84 00 00 00 00 
 1064f68:	00 
 1064f69:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1064f70:	0f 1f 84 00 00 00 00 
 1064f77:	00 
 1064f78:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1064f7f:	00 
 1064f80:	40 0f b6 c7          	movzbl %dil,%eax
 1064f84:	4c 89 e7             	mov    %r12,%rdi
 1064f87:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1064f8c:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 1064f91:	48 89 d9             	mov    %rbx,%rcx
 1064f94:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 1064f9b:	42 ff 74 fd 20       	push   0x20(%rbp,%r15,8)
 1064fa0:	41 53                	push   %r11
 1064fa2:	50                   	push   %rax
 1064fa3:	41 52                	push   %r10
 1064fa5:	41 55                	push   %r13
 1064fa7:	e8 a4 fc ff ff       	call   1064c50 <my.interpreter::evaluate>
 1064fac:	48 83 c4 30          	add    $0x30,%rsp
 1064fb0:	4c 8b 94 24 a0 01 00 	mov    0x1a0(%rsp),%r10
 1064fb7:	00 
 1064fb8:	0f b6 bc 24 a8 01 00 	movzbl 0x1a8(%rsp),%edi
 1064fbf:	00 
 1064fc0:	4c 8b 9c 24 b0 01 00 	mov    0x1b0(%rsp),%r11
 1064fc7:	00 
 1064fc8:	80 bc 24 88 01 00 00 	cmpb   $0x1,0x188(%rsp)
 1064fcf:	01 
 1064fd0:	0f 84 5a 1a 00 00    	je     1066a30 <my.interpreter::evaluate+0x1de0>
 1064fd6:	49 ff c7             	inc    %r15
 1064fd9:	4d 39 fe             	cmp    %r15,%r14
 1064fdc:	4c 8b 4c 24 40       	mov    0x40(%rsp),%r9
 1064fe1:	4c 8b 44 24 38       	mov    0x38(%rsp),%r8
 1064fe6:	75 98                	jne    1064f80 <my.interpreter::evaluate+0x330>
 1064fe8:	4c 8b 75 08          	mov    0x8(%rbp),%r14
 1064fec:	e9 9a 0d 00 00       	jmp    1065d8b <my.interpreter::evaluate+0x113b>
 1064ff1:	48 8b 48 28          	mov    0x28(%rax),%rcx
 1064ff5:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
 1064ffa:	48 8b 48 38          	mov    0x38(%rax),%rcx
 1064ffe:	48 89 4c 24 38       	mov    %rcx,0x38(%rsp)
 1065003:	4c 89 d2             	mov    %r10,%rdx
 1065006:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 106500d:	00 00 
 106500f:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 1065014:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1065019:	48 89 d9             	mov    %rbx,%rcx
 106501c:	41 54                	push   %r12
 106501e:	ff 70 08             	push   0x8(%rax)
 1065021:	41 56                	push   %r14
 1065023:	41 52                	push   %r10
 1065025:	41 53                	push   %r11
 1065027:	41 57                	push   %r15
 1065029:	4c 89 cb             	mov    %r9,%rbx
 106502c:	e8 1f fc ff ff       	call   1064c50 <my.interpreter::evaluate>
 1065031:	48 83 c4 30          	add    $0x30,%rsp
 1065035:	c5 f8 10 84 24 80 00 	vmovups 0x80(%rsp),%xmm0
 106503c:	00 00 
 106503e:	4c 8b bc 24 90 00 00 	mov    0x90(%rsp),%r15
 1065045:	00 
 1065046:	80 7c 24 68 01       	cmpb   $0x1,0x68(%rsp)
 106504b:	c5 f8 29 44 24 10    	vmovaps %xmm0,0x10(%rsp)
 1065051:	0f 84 d7 17 00 00    	je     106682e <my.interpreter::evaluate+0x1bde>
 1065057:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 106505e:	48 89 c6             	mov    %rax,%rsi
 1065061:	48 ff ce             	dec    %rsi
 1065064:	0f 80 dd 26 00 00    	jo     1067747 <my.interpreter::evaluate+0x2af7>
 106506a:	48 89 df             	mov    %rbx,%rdi
 106506d:	48 8b 43 78          	mov    0x78(%rbx),%rax
 1065071:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065075:	48 39 d6             	cmp    %rdx,%rsi
 1065078:	0f 83 00 20 00 00    	jae    106707e <my.interpreter::evaluate+0x242e>
 106507e:	49 89 f5             	mov    %rsi,%r13
 1065081:	49 c1 e5 04          	shl    $0x4,%r13
 1065085:	4e 8b 74 28 20       	mov    0x20(%rax,%r13,1),%r14
 106508a:	41 0f b6 ce          	movzbl %r14b,%ecx
 106508e:	83 f9 03             	cmp    $0x3,%ecx
 1065091:	0f 85 d0 14 00 00    	jne    1066567 <my.interpreter::evaluate+0x1917>
 1065097:	4a 8b 5c 28 28       	mov    0x28(%rax,%r13,1),%rbx
 106509c:	48 8b 07             	mov    (%rdi),%rax
 106509f:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10650a3:	48 89 d9             	mov    %rbx,%rcx
 10650a6:	48 39 d3             	cmp    %rdx,%rbx
 10650a9:	0f 83 9e 20 00 00    	jae    106714d <my.interpreter::evaluate+0x24fd>
 10650af:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 10650b3:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 10650b8:	0f 85 a9 14 00 00    	jne    1066567 <my.interpreter::evaluate+0x1917>
 10650be:	4c 89 7c 24 28       	mov    %r15,0x28(%rsp)
 10650c3:	48 89 6c 24 08       	mov    %rbp,0x8(%rsp)
 10650c8:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 10650cd:	4c 89 e6             	mov    %r12,%rsi
 10650d0:	49 89 ff             	mov    %rdi,%r15
 10650d3:	e8 48 4a 00 00       	call   1069b20 <my.heap::string_hash>
 10650d8:	89 c5                	mov    %eax,%ebp
 10650da:	4c 89 ff             	mov    %r15,%rdi
 10650dd:	48 89 de             	mov    %rbx,%rsi
 10650e0:	4c 89 e2             	mov    %r12,%rdx
 10650e3:	89 c1                	mov    %eax,%ecx
 10650e5:	e8 16 50 00 00       	call   106a100 <my.heap::instance_field>
 10650ea:	3c 01                	cmp    $0x1,%al
 10650ec:	0f 85 10 0b 00 00    	jne    1065c02 <my.interpreter::evaluate+0xfb2>
 10650f2:	31 c0                	xor    %eax,%eax
 10650f4:	49 3b 87 80 00 00 00 	cmp    0x80(%r15),%rax
 10650fb:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1065100:	0f 80 c0 27 00 00    	jo     10678c6 <my.interpreter::evaluate+0x2c76>
 1065106:	49 8b 47 78          	mov    0x78(%r15),%rax
 106510a:	4a 8d 34 28          	lea    (%rax,%r13,1),%rsi
 106510e:	48 83 c6 20          	add    $0x20,%rsi
 1065112:	0f b6 d2             	movzbl %dl,%edx
 1065115:	4a 89 54 28 20       	mov    %rdx,0x20(%rax,%r13,1)
 106511a:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 1065120:	e9 77 0b 00 00       	jmp    1065c9c <my.interpreter::evaluate+0x104c>
 1065125:	48 8b 48 28          	mov    0x28(%rax),%rcx
 1065129:	48 89 4c 24 58       	mov    %rcx,0x58(%rsp)
 106512e:	48 8b 48 38          	mov    0x38(%rax),%rcx
 1065132:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 1065137:	48 89 d9             	mov    %rbx,%rcx
 106513a:	4c 89 e3             	mov    %r12,%rbx
 106513d:	48 8b 50 40          	mov    0x40(%rax),%rdx
 1065141:	48 89 54 24 30       	mov    %rdx,0x30(%rsp)
 1065146:	4c 89 d2             	mov    %r10,%rdx
 1065149:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 1065150:	00 00 
 1065152:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 1065157:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 106515c:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 1065161:	49 89 cc             	mov    %rcx,%r12
 1065164:	53                   	push   %rbx
 1065165:	ff 70 08             	push   0x8(%rax)
 1065168:	41 56                	push   %r14
 106516a:	41 52                	push   %r10
 106516c:	41 53                	push   %r11
 106516e:	4d 89 fd             	mov    %r15,%r13
 1065171:	41 57                	push   %r15
 1065173:	4d 89 cf             	mov    %r9,%r15
 1065176:	e8 d5 fa ff ff       	call   1064c50 <my.interpreter::evaluate>
 106517b:	48 83 c4 30          	add    $0x30,%rsp
 106517f:	48 8b 9c 24 80 00 00 	mov    0x80(%rsp),%rbx
 1065186:	00 
 1065187:	48 8b 84 24 88 00 00 	mov    0x88(%rsp),%rax
 106518e:	00 
 106518f:	44 0f b6 f0          	movzbl %al,%r14d
 1065193:	48 8b 8c 24 90 00 00 	mov    0x90(%rsp),%rcx
 106519a:	00 
 106519b:	80 7c 24 68 01       	cmpb   $0x1,0x68(%rsp)
 10651a0:	0f 84 ba 16 00 00    	je     1066860 <my.interpreter::evaluate+0x1c10>
 10651a6:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
 10651ab:	49 8b 87 80 00 00 00 	mov    0x80(%r15),%rax
 10651b2:	48 89 c6             	mov    %rax,%rsi
 10651b5:	48 ff ce             	dec    %rsi
 10651b8:	0f 80 9d 25 00 00    	jo     106775b <my.interpreter::evaluate+0x2b0b>
 10651be:	49 8b 47 78          	mov    0x78(%r15),%rax
 10651c2:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10651c6:	48 39 d6             	cmp    %rdx,%rsi
 10651c9:	4c 8b 44 24 38       	mov    0x38(%rsp),%r8
 10651ce:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 10651d3:	0f 83 c7 1e 00 00    	jae    10670a0 <my.interpreter::evaluate+0x2450>
 10651d9:	48 89 f7             	mov    %rsi,%rdi
 10651dc:	48 c1 e7 04          	shl    $0x4,%rdi
 10651e0:	80 7c 38 20 03       	cmpb   $0x3,0x20(%rax,%rdi,1)
 10651e5:	0f 85 a1 13 00 00    	jne    106658c <my.interpreter::evaluate+0x193c>
 10651eb:	48 8b 74 38 28       	mov    0x28(%rax,%rdi,1),%rsi
 10651f0:	49 8b 07             	mov    (%r15),%rax
 10651f3:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10651f7:	48 39 d6             	cmp    %rdx,%rsi
 10651fa:	0f 83 72 1f 00 00    	jae    1067172 <my.interpreter::evaluate+0x2522>
 1065200:	48 89 f7             	mov    %rsi,%rdi
 1065203:	48 6b d7 38          	imul   $0x38,%rdi,%rdx
 1065207:	83 7c 10 20 07       	cmpl   $0x7,0x20(%rax,%rdx,1)
 106520c:	0f 85 7a 13 00 00    	jne    106658c <my.interpreter::evaluate+0x193c>
 1065212:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 1065219:	00 
 106521a:	4c 89 de             	mov    %r11,%rsi
 106521d:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 1065222:	4c 89 e1             	mov    %r12,%rcx
 1065225:	4d 89 f9             	mov    %r15,%r9
 1065228:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 106522f:	ff 74 24 38          	push   0x38(%rsp)
 1065233:	ff 74 24 18          	push   0x18(%rsp)
 1065237:	41 56                	push   %r14
 1065239:	53                   	push   %rbx
 106523a:	41 55                	push   %r13
 106523c:	e8 0f fa ff ff       	call   1064c50 <my.interpreter::evaluate>
 1065241:	48 83 c4 30          	add    $0x30,%rsp
 1065245:	48 8b 84 24 b8 00 00 	mov    0xb8(%rsp),%rax
 106524c:	00 
 106524d:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 1065252:	44 0f b6 b4 24 c0 00 	movzbl 0xc0(%rsp),%r14d
 1065259:	00 00 
 106525b:	48 8b 8c 24 c8 00 00 	mov    0xc8(%rsp),%rcx
 1065262:	00 
 1065263:	80 bc 24 a0 00 00 00 	cmpb   $0x1,0xa0(%rsp)
 106526a:	01 
 106526b:	0f 84 6e 17 00 00    	je     10669df <my.interpreter::evaluate+0x1d8f>
 1065271:	49 8b b7 80 00 00 00 	mov    0x80(%r15),%rsi
 1065278:	48 89 f0             	mov    %rsi,%rax
 106527b:	48 ff c8             	dec    %rax
 106527e:	0f 80 9b 25 00 00    	jo     106781f <my.interpreter::evaluate+0x2bcf>
 1065284:	48 89 c6             	mov    %rax,%rsi
 1065287:	48 ff ce             	dec    %rsi
 106528a:	0f 80 a0 25 00 00    	jo     1067830 <my.interpreter::evaluate+0x2be0>
 1065290:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
 1065295:	4d 89 f5             	mov    %r14,%r13
 1065298:	49 8b 47 78          	mov    0x78(%r15),%rax
 106529c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10652a0:	48 39 d6             	cmp    %rdx,%rsi
 10652a3:	0f 83 a4 1f 00 00    	jae    106724d <my.interpreter::evaluate+0x25fd>
 10652a9:	48 89 f1             	mov    %rsi,%rcx
 10652ac:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 10652b1:	48 c1 e1 04          	shl    $0x4,%rcx
 10652b5:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 10652ba:	83 fa 03             	cmp    $0x3,%edx
 10652bd:	0f 85 e6 23 00 00    	jne    10676a9 <my.interpreter::evaluate+0x2a59>
 10652c3:	4c 8b 64 08 28       	mov    0x28(%rax,%rcx,1),%r12
 10652c8:	4c 89 ff             	mov    %r15,%rdi
 10652cb:	4c 89 f6             	mov    %r14,%rsi
 10652ce:	e8 4d 48 00 00       	call   1069b20 <my.heap::string_hash>
 10652d3:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 10652d8:	48 8b 8f 80 00 00 00 	mov    0x80(%rdi),%rcx
 10652df:	48 89 ce             	mov    %rcx,%rsi
 10652e2:	48 ff ce             	dec    %rsi
 10652e5:	0f 80 71 25 00 00    	jo     106785c <my.interpreter::evaluate+0x2c0c>
 10652eb:	48 8b 4f 78          	mov    0x78(%rdi),%rcx
 10652ef:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10652f3:	48 39 d6             	cmp    %rdx,%rsi
 10652f6:	0f 83 78 1f 00 00    	jae    1067274 <my.interpreter::evaluate+0x2624>
 10652fc:	49 89 f0             	mov    %rsi,%r8
 10652ff:	49 c1 e0 04          	shl    $0x4,%r8
 1065303:	42 0f b6 5c 01 20    	movzbl 0x20(%rcx,%r8,1),%ebx
 1065309:	4e 8b 7c 01 28       	mov    0x28(%rcx,%r8,1),%r15
 106530e:	4c 89 e6             	mov    %r12,%rsi
 1065311:	4c 89 f2             	mov    %r14,%rdx
 1065314:	89 c1                	mov    %eax,%ecx
 1065316:	41 89 d8             	mov    %ebx,%r8d
 1065319:	4d 89 f9             	mov    %r15,%r9
 106531c:	e8 af 4f 00 00       	call   106a2d0 <my.heap::set_instance_field>
 1065321:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1065326:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
 106532d:	48 89 c6             	mov    %rax,%rsi
 1065330:	48 ff ce             	dec    %rsi
 1065333:	0f 80 37 25 00 00    	jo     1067870 <my.interpreter::evaluate+0x2c20>
 1065339:	48 89 b7 80 00 00 00 	mov    %rsi,0x80(%rdi)
 1065340:	48 8b 4f 78          	mov    0x78(%rdi),%rcx
 1065344:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065348:	48 39 d6             	cmp    %rdx,%rsi
 106534b:	0f 83 45 1f 00 00    	jae    1067296 <my.interpreter::evaluate+0x2646>
 1065351:	48 89 f0             	mov    %rsi,%rax
 1065354:	48 ff c8             	dec    %rax
 1065357:	0f 80 27 25 00 00    	jo     1067884 <my.interpreter::evaluate+0x2c34>
 106535d:	48 39 d0             	cmp    %rdx,%rax
 1065360:	0f 83 52 1f 00 00    	jae    10672b8 <my.interpreter::evaluate+0x2668>
 1065366:	48 89 c6             	mov    %rax,%rsi
 1065369:	48 c1 e6 04          	shl    $0x4,%rsi
 106536d:	48 89 5c 31 20       	mov    %rbx,0x20(%rcx,%rsi,1)
 1065372:	4c 89 7c 31 28       	mov    %r15,0x28(%rcx,%rsi,1)
 1065377:	48 89 4f 78          	mov    %rcx,0x78(%rdi)
 106537b:	31 c0                	xor    %eax,%eax
 106537d:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 1065382:	4d 89 ee             	mov    %r13,%r14
 1065385:	48 8b 4c 24 08       	mov    0x8(%rsp),%rcx
 106538a:	e9 87 16 00 00       	jmp    1066a16 <my.interpreter::evaluate+0x1dc6>
 106538f:	48 89 6c 24 08       	mov    %rbp,0x8(%rsp)
 1065394:	4d 89 fd             	mov    %r15,%r13
 1065397:	0f b6 48 10          	movzbl 0x10(%rax),%ecx
 106539b:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
 10653a0:	48 8b 48 28          	mov    0x28(%rax),%rcx
 10653a4:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 10653a9:	48 8b 48 38          	mov    0x38(%rax),%rcx
 10653ad:	48 89 4c 24 38       	mov    %rcx,0x38(%rsp)
 10653b2:	4d 89 d7             	mov    %r10,%r15
 10653b5:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 10653bc:	00 00 
 10653be:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 10653c3:	48 8b 6c 24 10       	mov    0x10(%rsp),%rbp
 10653c8:	48 89 ee             	mov    %rbp,%rsi
 10653cb:	4c 89 fa             	mov    %r15,%rdx
 10653ce:	48 89 d9             	mov    %rbx,%rcx
 10653d1:	48 89 5c 24 28       	mov    %rbx,0x28(%rsp)
 10653d6:	4c 89 c3             	mov    %r8,%rbx
 10653d9:	41 54                	push   %r12
 10653db:	ff 70 08             	push   0x8(%rax)
 10653de:	41 56                	push   %r14
 10653e0:	41 52                	push   %r10
 10653e2:	41 53                	push   %r11
 10653e4:	4d 89 ee             	mov    %r13,%r14
 10653e7:	41 55                	push   %r13
 10653e9:	4d 89 cd             	mov    %r9,%r13
 10653ec:	e8 5f f8 ff ff       	call   1064c50 <my.interpreter::evaluate>
 10653f1:	48 83 c4 30          	add    $0x30,%rsp
 10653f5:	4c 8b 94 24 80 00 00 	mov    0x80(%rsp),%r10
 10653fc:	00 
 10653fd:	0f b6 84 24 88 00 00 	movzbl 0x88(%rsp),%eax
 1065404:	00 
 1065405:	4c 8b 9c 24 90 00 00 	mov    0x90(%rsp),%r11
 106540c:	00 
 106540d:	80 7c 24 68 01       	cmpb   $0x1,0x68(%rsp)
 1065412:	0f 84 80 14 00 00    	je     1066898 <my.interpreter::evaluate+0x1c48>
 1065418:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 106541f:	00 
 1065420:	48 89 ee             	mov    %rbp,%rsi
 1065423:	4c 89 fa             	mov    %r15,%rdx
 1065426:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 106542b:	49 89 d8             	mov    %rbx,%r8
 106542e:	4d 89 e9             	mov    %r13,%r9
 1065431:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 1065438:	ff 74 24 40          	push   0x40(%rsp)
 106543c:	41 53                	push   %r11
 106543e:	50                   	push   %rax
 106543f:	41 52                	push   %r10
 1065441:	41 56                	push   %r14
 1065443:	e8 08 f8 ff ff       	call   1064c50 <my.interpreter::evaluate>
 1065448:	48 83 c4 30          	add    $0x30,%rsp
 106544c:	4c 8b 94 24 b8 00 00 	mov    0xb8(%rsp),%r10
 1065453:	00 
 1065454:	44 0f b6 9c 24 c0 00 	movzbl 0xc0(%rsp),%r11d
 106545b:	00 00 
 106545d:	4c 8b b4 24 c8 00 00 	mov    0xc8(%rsp),%r14
 1065464:	00 
 1065465:	80 bc 24 a0 00 00 00 	cmpb   $0x1,0xa0(%rsp)
 106546c:	01 
 106546d:	0f 84 2b 15 00 00    	je     106699e <my.interpreter::evaluate+0x1d4e>
 1065473:	4d 8b 8d 80 00 00 00 	mov    0x80(%r13),%r9
 106547a:	4c 89 cb             	mov    %r9,%rbx
 106547d:	48 ff cb             	dec    %rbx
 1065480:	41 0f 90 c7          	seto   %r15b
 1065484:	0f 80 59 23 00 00    	jo     10677e3 <my.interpreter::evaluate+0x2b93>
 106548a:	48 89 de             	mov    %rbx,%rsi
 106548d:	48 ff ce             	dec    %rsi
 1065490:	0f 80 61 23 00 00    	jo     10677f7 <my.interpreter::evaluate+0x2ba7>
 1065496:	4c 89 ef             	mov    %r13,%rdi
 1065499:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 106549d:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10654a1:	48 39 d6             	cmp    %rdx,%rsi
 10654a4:	0f 83 ea 1c 00 00    	jae    1067194 <my.interpreter::evaluate+0x2544>
 10654aa:	49 89 f0             	mov    %rsi,%r8
 10654ad:	49 c1 e0 04          	shl    $0x4,%r8
 10654b1:	42 0f b6 44 01 20    	movzbl 0x20(%rcx,%r8,1),%eax
 10654b7:	4e 8b 6c 01 28       	mov    0x28(%rcx,%r8,1),%r13
 10654bc:	48 89 de             	mov    %rbx,%rsi
 10654bf:	48 39 d3             	cmp    %rdx,%rbx
 10654c2:	0f 83 ee 1c 00 00    	jae    10671b6 <my.interpreter::evaluate+0x2566>
 10654c8:	48 83 c1 20          	add    $0x20,%rcx
 10654cc:	48 c1 e6 04          	shl    $0x4,%rsi
 10654d0:	0f b6 2c 31          	movzbl (%rcx,%rsi,1),%ebp
 10654d4:	4c 8b 64 31 08       	mov    0x8(%rcx,%rsi,1),%r12
 10654d9:	48 8b 74 24 30       	mov    0x30(%rsp),%rsi
 10654de:	48 83 fe 0c          	cmp    $0xc,%rsi
 10654e2:	0f 84 d8 0b 00 00    	je     10660c0 <my.interpreter::evaluate+0x1470>
 10654e8:	83 fe 0e             	cmp    $0xe,%esi
 10654eb:	0f 85 f7 0b 00 00    	jne    10660e8 <my.interpreter::evaluate+0x1498>
 10654f1:	3c 02                	cmp    $0x2,%al
 10654f3:	0f 84 1b 11 00 00    	je     1066614 <my.interpreter::evaluate+0x19c4>
 10654f9:	0f b6 c0             	movzbl %al,%eax
 10654fc:	83 f8 01             	cmp    $0x1,%eax
 10654ff:	0f 84 f1 10 00 00    	je     10665f6 <my.interpreter::evaluate+0x19a6>
 1065505:	85 c0                	test   %eax,%eax
 1065507:	0f 85 2c 11 00 00    	jne    1066639 <my.interpreter::evaluate+0x19e9>
 106550d:	40 84 ed             	test   %bpl,%bpl
 1065510:	41 0f 94 c4          	sete   %r12b
 1065514:	e9 31 11 00 00       	jmp    106664a <my.interpreter::evaluate+0x19fa>
 1065519:	c5 f9 10 40 08       	vmovupd 0x8(%rax),%xmm0
 106551e:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065522:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065529:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106552d:	48 39 d6             	cmp    %rdx,%rsi
 1065530:	0f 83 56 1a 00 00    	jae    1066f8c <my.interpreter::evaluate+0x233c>
 1065536:	48 89 f1             	mov    %rsi,%rcx
 1065539:	c5 f9 54 05 9f ee f9 	vandpd -0x61161(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 1065540:	ff 
 1065541:	48 c1 e1 04          	shl    $0x4,%rcx
 1065545:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 106554b:	49 89 41 78          	mov    %rax,0x78(%r9)
 106554f:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065556:	48 89 f0             	mov    %rsi,%rax
 1065559:	48 ff c0             	inc    %rax
 106555c:	0f 81 ef 03 00 00    	jno    1065951 <my.interpreter::evaluate+0xd01>
 1065562:	48 8d 3d 57 cc 01 00 	lea    0x1cc57(%rip),%rdi        # 10821c0 <core_durable_error.verbs+0x3270>
 1065569:	ba 01 00 00 00       	mov    $0x1,%edx
 106556e:	e8 0d ef fb ff       	call   1024480 <myl_core_trap>
 1065573:	48 89 d9             	mov    %rbx,%rcx
 1065576:	4c 89 e3             	mov    %r12,%rbx
 1065579:	48 89 6c 24 08       	mov    %rbp,0x8(%rsp)
 106557e:	0f b6 68 10          	movzbl 0x10(%rax),%ebp
 1065582:	48 8b 50 38          	mov    0x38(%rax),%rdx
 1065586:	48 89 54 24 40       	mov    %rdx,0x40(%rsp)
 106558b:	4c 89 d2             	mov    %r10,%rdx
 106558e:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 1065595:	00 00 
 1065597:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 106559c:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10655a1:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 10655a6:	49 89 cc             	mov    %rcx,%r12
 10655a9:	53                   	push   %rbx
 10655aa:	ff 70 08             	push   0x8(%rax)
 10655ad:	41 56                	push   %r14
 10655af:	41 52                	push   %r10
 10655b1:	41 53                	push   %r11
 10655b3:	41 57                	push   %r15
 10655b5:	4d 89 cd             	mov    %r9,%r13
 10655b8:	e8 93 f6 ff ff       	call   1064c50 <my.interpreter::evaluate>
 10655bd:	48 83 c4 30          	add    $0x30,%rsp
 10655c1:	4c 8b 94 24 80 00 00 	mov    0x80(%rsp),%r10
 10655c8:	00 
 10655c9:	48 8b 84 24 88 00 00 	mov    0x88(%rsp),%rax
 10655d0:	00 
 10655d1:	44 0f b6 f0          	movzbl %al,%r14d
 10655d5:	4c 8b bc 24 90 00 00 	mov    0x90(%rsp),%r15
 10655dc:	00 
 10655dd:	80 7c 24 68 01       	cmpb   $0x1,0x68(%rsp)
 10655e2:	0f 84 ce 12 00 00    	je     10668b6 <my.interpreter::evaluate+0x1c66>
 10655e8:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 10655ef:	48 89 c6             	mov    %rax,%rsi
 10655f2:	48 ff ce             	dec    %rsi
 10655f5:	0f 80 74 21 00 00    	jo     106776f <my.interpreter::evaluate+0x2b1f>
 10655fb:	4d 89 e9             	mov    %r13,%r9
 10655fe:	49 8b 45 78          	mov    0x78(%r13),%rax
 1065602:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065606:	48 89 f7             	mov    %rsi,%rdi
 1065609:	48 39 d6             	cmp    %rdx,%rsi
 106560c:	4c 8b 44 24 38       	mov    0x38(%rsp),%r8
 1065611:	0f 83 ab 1a 00 00    	jae    10670c2 <my.interpreter::evaluate+0x2472>
 1065617:	48 c1 e7 04          	shl    $0x4,%rdi
 106561b:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 1065620:	83 fa 01             	cmp    $0x1,%edx
 1065623:	0f 84 52 0a 00 00    	je     106607b <my.interpreter::evaluate+0x142b>
 1065629:	85 d2                	test   %edx,%edx
 106562b:	0f 85 84 0a 00 00    	jne    10660b5 <my.interpreter::evaluate+0x1465>
 1065631:	83 fd 1e             	cmp    $0x1e,%ebp
 1065634:	0f 85 5a 0a 00 00    	jne    1066094 <my.interpreter::evaluate+0x1444>
 106563a:	49 89 b1 80 00 00 00 	mov    %rsi,0x80(%r9)
 1065641:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 1065648:	00 
 1065649:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 106564e:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 1065653:	4c 89 e1             	mov    %r12,%rcx
 1065656:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 106565d:	ff 74 24 48          	push   0x48(%rsp)
 1065661:	41 57                	push   %r15
 1065663:	41 56                	push   %r14
 1065665:	41 52                	push   %r10
 1065667:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 106566e:	e8 dd f5 ff ff       	call   1064c50 <my.interpreter::evaluate>
 1065673:	48 83 c4 30          	add    $0x30,%rsp
 1065677:	0f b6 84 24 a0 00 00 	movzbl 0xa0(%rsp),%eax
 106567e:	00 
 106567f:	c5 f9 10 84 24 a8 00 	vmovupd 0xa8(%rsp),%xmm0
 1065686:	00 00 
 1065688:	4c 8b 94 24 b8 00 00 	mov    0xb8(%rsp),%r10
 106568f:	00 
 1065690:	44 0f b6 b4 24 c0 00 	movzbl 0xc0(%rsp),%r14d
 1065697:	00 00 
 1065699:	4c 8b bc 24 c8 00 00 	mov    0xc8(%rsp),%r15
 10656a0:	00 
 10656a1:	48 83 f8 01          	cmp    $0x1,%rax
 10656a5:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 10656aa:	0f 85 eb 09 00 00    	jne    106609b <my.interpreter::evaluate+0x144b>
 10656b0:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 10656b6:	48 8d 3d 63 fb 01 00 	lea    0x1fb63(%rip),%rdi        # 1085220 <core_durable_error.verbs+0x62d0>
 10656bd:	e9 0c 12 00 00       	jmp    10668ce <my.interpreter::evaluate+0x1c7e>
 10656c2:	48 89 d9             	mov    %rbx,%rcx
 10656c5:	4c 89 e3             	mov    %r12,%rbx
 10656c8:	4d 89 f4             	mov    %r14,%r12
 10656cb:	44 0f b6 70 08       	movzbl 0x8(%rax),%r14d
 10656d0:	4d 89 fd             	mov    %r15,%r13
 10656d3:	4c 8b 78 20          	mov    0x20(%rax),%r15
 10656d7:	4c 89 d2             	mov    %r10,%rdx
 10656da:	44 0f b6 94 24 30 02 	movzbl 0x230(%rsp),%r10d
 10656e1:	00 00 
 10656e3:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 10656e8:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10656ed:	53                   	push   %rbx
 10656ee:	ff 70 30             	push   0x30(%rax)
 10656f1:	41 54                	push   %r12
 10656f3:	41 52                	push   %r10
 10656f5:	41 53                	push   %r11
 10656f7:	41 55                	push   %r13
 10656f9:	4d 89 cc             	mov    %r9,%r12
 10656fc:	e8 4f f5 ff ff       	call   1064c50 <my.interpreter::evaluate>
 1065701:	48 83 c4 30          	add    $0x30,%rsp
 1065705:	c5 f9 10 84 24 80 00 	vmovupd 0x80(%rsp),%xmm0
 106570c:	00 00 
 106570e:	48 8b 9c 24 90 00 00 	mov    0x90(%rsp),%rbx
 1065715:	00 
 1065716:	80 7c 24 68 01       	cmpb   $0x1,0x68(%rsp)
 106571b:	0f 84 ce 11 00 00    	je     10668ef <my.interpreter::evaluate+0x1c9f>
 1065721:	49 8b 84 24 80 00 00 	mov    0x80(%r12),%rax
 1065728:	00 
 1065729:	48 89 c6             	mov    %rax,%rsi
 106572c:	48 ff ce             	dec    %rsi
 106572f:	0f 80 4e 20 00 00    	jo     1067783 <my.interpreter::evaluate+0x2b33>
 1065735:	4d 89 e0             	mov    %r12,%r8
 1065738:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 106573d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065741:	48 39 d6             	cmp    %rdx,%rsi
 1065744:	0f 83 9a 19 00 00    	jae    10670e4 <my.interpreter::evaluate+0x2494>
 106574a:	48 89 f7             	mov    %rsi,%rdi
 106574d:	48 c1 e7 04          	shl    $0x4,%rdi
 1065751:	48 8d 0c 38          	lea    (%rax,%rdi,1),%rcx
 1065755:	48 83 c1 20          	add    $0x20,%rcx
 1065759:	0f b6 74 38 20       	movzbl 0x20(%rax,%rdi,1),%esi
 106575e:	48 8b 54 38 28       	mov    0x28(%rax,%rdi,1),%rdx
 1065763:	41 83 fe 0b          	cmp    $0xb,%r14d
 1065767:	0f 85 6e 04 00 00    	jne    1065bdb <my.interpreter::evaluate+0xf8b>
 106576d:	40 84 f6             	test   %sil,%sil
 1065770:	0f 84 eb 0c 00 00    	je     1066461 <my.interpreter::evaluate+0x1811>
 1065776:	40 0f b6 f6          	movzbl %sil,%esi
 106577a:	83 fe 01             	cmp    $0x1,%esi
 106577d:	0f 85 e2 0c 00 00    	jne    1066465 <my.interpreter::evaluate+0x1815>
 1065783:	f6 d2                	not    %dl
 1065785:	80 e2 01             	and    $0x1,%dl
 1065788:	e9 da 0c 00 00       	jmp    1066467 <my.interpreter::evaluate+0x1817>
 106578d:	48 89 6c 24 08       	mov    %rbp,0x8(%rsp)
 1065792:	4c 8b 70 48          	mov    0x48(%rax),%r14
 1065796:	48 8b 58 58          	mov    0x58(%rax),%rbx
 106579a:	48 8b 40 60          	mov    0x60(%rax),%rax
 106579e:	49 8b 39             	mov    (%r9),%rdi
 10657a1:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 10657a8:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 10657ac:	48 89 f1             	mov    %rsi,%rcx
 10657af:	48 85 c0             	test   %rax,%rax
 10657b2:	0f 8e ad 01 00 00    	jle    1065965 <my.interpreter::evaluate+0xd15>
 10657b8:	4c 8d 47 20          	lea    0x20(%rdi),%r8
 10657bc:	49 89 c3             	mov    %rax,%r11
 10657bf:	48 89 f1             	mov    %rsi,%rcx
 10657c2:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10657c9:	0f 1f 84 00 00 00 00 
 10657d0:	00 
 10657d1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10657d8:	0f 1f 84 00 00 00 00 
 10657df:	00 
 10657e0:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10657e7:	0f 1f 84 00 00 00 00 
 10657ee:	00 
 10657ef:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10657f6:	0f 1f 84 00 00 00 00 
 10657fd:	00 
 10657fe:	66 90                	xchg   %ax,%ax
 1065800:	48 39 d1             	cmp    %rdx,%rcx
 1065803:	73 23                	jae    1065828 <my.interpreter::evaluate+0xbd8>
 1065805:	49 89 ca             	mov    %rcx,%r10
 1065808:	49 6b ca 38          	imul   $0x38,%r10,%rcx
 106580c:	41 83 3c 08 09       	cmpl   $0x9,(%r8,%rcx,1)
 1065811:	0f 85 cd 1c 00 00    	jne    10674e4 <my.interpreter::evaluate+0x2894>
 1065817:	4c 01 c1             	add    %r8,%rcx
 106581a:	48 8b 49 08          	mov    0x8(%rcx),%rcx
 106581e:	49 ff cb             	dec    %r11
 1065821:	75 dd                	jne    1065800 <my.interpreter::evaluate+0xbb0>
 1065823:	e9 3d 01 00 00       	jmp    1065965 <my.interpreter::evaluate+0xd15>
 1065828:	49 89 ca             	mov    %rcx,%r10
 106582b:	49 c1 fa 3f          	sar    $0x3f,%r10
 106582f:	49 21 d2             	and    %rdx,%r10
 1065832:	49 01 ca             	add    %rcx,%r10
 1065835:	49 39 d2             	cmp    %rdx,%r10
 1065838:	72 ce                	jb     1065808 <my.interpreter::evaluate+0xbb8>
 106583a:	48 8d 3d df f3 01 00 	lea    0x1f3df(%rip),%rdi        # 1084c20 <core_durable_error.verbs+0x5cd0>
 1065841:	48 89 ce             	mov    %rcx,%rsi
 1065844:	e8 37 ec fb ff       	call   1024480 <myl_core_trap>
 1065849:	48 8b 78 38          	mov    0x38(%rax),%rdi
 106584d:	48 83 ff ff          	cmp    $0xffffffffffffffff,%rdi
 1065851:	0f 84 76 04 00 00    	je     1065ccd <my.interpreter::evaluate+0x107d>
 1065857:	48 8b 70 40          	mov    0x40(%rax),%rsi
 106585b:	49 8b 09             	mov    (%r9),%rcx
 106585e:	49 8b 81 a8 00 00 00 	mov    0xa8(%r9),%rax
 1065865:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065869:	48 85 ff             	test   %rdi,%rdi
 106586c:	0f 8e 9e 02 00 00    	jle    1065b10 <my.interpreter::evaluate+0xec0>
 1065872:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 1065876:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 106587d:	00 00 00 
 1065880:	48 39 d0             	cmp    %rdx,%rax
 1065883:	73 23                	jae    10658a8 <my.interpreter::evaluate+0xc58>
 1065885:	49 89 c2             	mov    %rax,%r10
 1065888:	49 6b c2 38          	imul   $0x38,%r10,%rax
 106588c:	41 83 3c 00 09       	cmpl   $0x9,(%r8,%rax,1)
 1065891:	0f 85 65 1c 00 00    	jne    10674fc <my.interpreter::evaluate+0x28ac>
 1065897:	4c 01 c0             	add    %r8,%rax
 106589a:	48 8b 40 08          	mov    0x8(%rax),%rax
 106589e:	48 ff cf             	dec    %rdi
 10658a1:	75 dd                	jne    1065880 <my.interpreter::evaluate+0xc30>
 10658a3:	e9 68 02 00 00       	jmp    1065b10 <my.interpreter::evaluate+0xec0>
 10658a8:	49 89 c2             	mov    %rax,%r10
 10658ab:	49 c1 fa 3f          	sar    $0x3f,%r10
 10658af:	49 21 d2             	and    %rdx,%r10
 10658b2:	49 01 c2             	add    %rax,%r10
 10658b5:	49 39 d2             	cmp    %rdx,%r10
 10658b8:	72 ce                	jb     1065888 <my.interpreter::evaluate+0xc38>
 10658ba:	48 8d 3d 5f f3 01 00 	lea    0x1f35f(%rip),%rdi        # 1084c20 <core_durable_error.verbs+0x5cd0>
 10658c1:	48 89 c6             	mov    %rax,%rsi
 10658c4:	e8 b7 eb fb ff       	call   1024480 <myl_core_trap>
 10658c9:	48 8b 40 38          	mov    0x38(%rax),%rax
 10658cd:	48 39 d6             	cmp    %rdx,%rsi
 10658d0:	0f 83 d8 16 00 00    	jae    1066fae <my.interpreter::evaluate+0x235e>
 10658d6:	48 89 f7             	mov    %rsi,%rdi
 10658d9:	48 6b d7 38          	imul   $0x38,%rdi,%rdx
 10658dd:	83 7c 11 20 09       	cmpl   $0x9,0x20(%rcx,%rdx,1)
 10658e2:	0f 85 fe 1d 00 00    	jne    10676e6 <my.interpreter::evaluate+0x2a96>
 10658e8:	48 01 d1             	add    %rdx,%rcx
 10658eb:	48 83 c1 20          	add    $0x20,%rcx
 10658ef:	48 8b 49 10          	mov    0x10(%rcx),%rcx
 10658f3:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10658f7:	48 39 d0             	cmp    %rdx,%rax
 10658fa:	0f 83 f5 16 00 00    	jae    1066ff5 <my.interpreter::evaluate+0x23a5>
 1065900:	48 89 c6             	mov    %rax,%rsi
 1065903:	48 c1 e6 04          	shl    $0x4,%rsi
 1065907:	c5 f9 10 44 31 20    	vmovupd 0x20(%rcx,%rsi,1),%xmm0
 106590d:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065911:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065918:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106591c:	48 39 d6             	cmp    %rdx,%rsi
 106591f:	0f 83 f5 16 00 00    	jae    106701a <my.interpreter::evaluate+0x23ca>
 1065925:	48 89 f1             	mov    %rsi,%rcx
 1065928:	c5 f9 54 05 b0 ea f9 	vandpd -0x61550(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 106592f:	ff 
 1065930:	48 c1 e1 04          	shl    $0x4,%rcx
 1065934:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 106593a:	49 89 41 78          	mov    %rax,0x78(%r9)
 106593e:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065945:	48 89 f0             	mov    %rsi,%rax
 1065948:	48 ff c0             	inc    %rax
 106594b:	0f 80 ad 1d 00 00    	jo     10676fe <my.interpreter::evaluate+0x2aae>
 1065951:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065958:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 106595f:	00 
 1065960:	e9 00 04 00 00       	jmp    1065d65 <my.interpreter::evaluate+0x1115>
 1065965:	48 39 d1             	cmp    %rdx,%rcx
 1065968:	0f 83 62 16 00 00    	jae    1066fd0 <my.interpreter::evaluate+0x2380>
 106596e:	49 89 c8             	mov    %rcx,%r8
 1065971:	49 6b c8 38          	imul   $0x38,%r8,%rcx
 1065975:	83 7c 0f 20 09       	cmpl   $0x9,0x20(%rdi,%rcx,1)
 106597a:	0f 85 72 1d 00 00    	jne    10676f2 <my.interpreter::evaluate+0x2aa2>
 1065980:	48 01 f9             	add    %rdi,%rcx
 1065983:	48 83 c1 20          	add    $0x20,%rcx
 1065987:	4c 8b 41 10          	mov    0x10(%rcx),%r8
 106598b:	49 83 78 08 00       	cmpq   $0x0,0x8(%r8)
 1065990:	0f 84 a6 16 00 00    	je     106703c <my.interpreter::evaluate+0x23ec>
 1065996:	48 89 c1             	mov    %rax,%rcx
 1065999:	48 ff c9             	dec    %rcx
 106599c:	0f 80 6d 1d 00 00    	jo     106770f <my.interpreter::evaluate+0x2abf>
 10659a2:	48 83 c7 20          	add    $0x20,%rdi
 10659a6:	41 0f b6 40 20       	movzbl 0x20(%r8),%eax
 10659ab:	4d 8b 78 28          	mov    0x28(%r8),%r15
 10659af:	48 85 c9             	test   %rcx,%rcx
 10659b2:	7e 4e                	jle    1065a02 <my.interpreter::evaluate+0xdb2>
 10659b4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10659bb:	00 00 00 00 00 
 10659c0:	48 39 d6             	cmp    %rdx,%rsi
 10659c3:	73 1f                	jae    10659e4 <my.interpreter::evaluate+0xd94>
 10659c5:	49 89 f0             	mov    %rsi,%r8
 10659c8:	49 6b f0 38          	imul   $0x38,%r8,%rsi
 10659cc:	83 3c 37 09          	cmpl   $0x9,(%rdi,%rsi,1)
 10659d0:	0f 85 1a 1b 00 00    	jne    10674f0 <my.interpreter::evaluate+0x28a0>
 10659d6:	48 01 fe             	add    %rdi,%rsi
 10659d9:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 10659dd:	48 ff c9             	dec    %rcx
 10659e0:	75 de                	jne    10659c0 <my.interpreter::evaluate+0xd70>
 10659e2:	eb 1e                	jmp    1065a02 <my.interpreter::evaluate+0xdb2>
 10659e4:	49 89 f0             	mov    %rsi,%r8
 10659e7:	49 c1 f8 3f          	sar    $0x3f,%r8
 10659eb:	49 21 d0             	and    %rdx,%r8
 10659ee:	49 01 f0             	add    %rsi,%r8
 10659f1:	49 39 d0             	cmp    %rdx,%r8
 10659f4:	72 d2                	jb     10659c8 <my.interpreter::evaluate+0xd78>
 10659f6:	48 8d 3d 23 f2 01 00 	lea    0x1f223(%rip),%rdi        # 1084c20 <core_durable_error.verbs+0x5cd0>
 10659fd:	e8 7e ea fb ff       	call   1024480 <myl_core_trap>
 1065a02:	48 39 d6             	cmp    %rdx,%rsi
 1065a05:	0f 83 41 16 00 00    	jae    106704c <my.interpreter::evaluate+0x23fc>
 1065a0b:	48 89 f1             	mov    %rsi,%rcx
 1065a0e:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065a12:	83 3c 0f 09          	cmpl   $0x9,(%rdi,%rcx,1)
 1065a16:	0f 85 07 1d 00 00    	jne    1067723 <my.interpreter::evaluate+0x2ad3>
 1065a1c:	48 01 cf             	add    %rcx,%rdi
 1065a1f:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 1065a23:	48 83 79 08 00       	cmpq   $0x0,0x8(%rcx)
 1065a28:	0f 84 40 16 00 00    	je     106706e <my.interpreter::evaluate+0x241e>
 1065a2e:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 1065a33:	3c 03                	cmp    $0x3,%al
 1065a35:	0f 85 2e 1c 00 00    	jne    1067669 <my.interpreter::evaluate+0x2a19>
 1065a3b:	44 0f b6 71 20       	movzbl 0x20(%rcx),%r14d
 1065a40:	4c 8b 61 28          	mov    0x28(%rcx),%r12
 1065a44:	4c 89 cf             	mov    %r9,%rdi
 1065a47:	48 89 de             	mov    %rbx,%rsi
 1065a4a:	4c 89 cd             	mov    %r9,%rbp
 1065a4d:	e8 ce 40 00 00       	call   1069b20 <my.heap::string_hash>
 1065a52:	48 89 ef             	mov    %rbp,%rdi
 1065a55:	4c 89 fe             	mov    %r15,%rsi
 1065a58:	48 89 da             	mov    %rbx,%rdx
 1065a5b:	89 c1                	mov    %eax,%ecx
 1065a5d:	e8 7e 49 00 00       	call   106a3e0 <my.heap::class_method>
 1065a62:	3c 01                	cmp    $0x1,%al
 1065a64:	0f 85 a6 0e 00 00    	jne    1066910 <my.interpreter::evaluate+0x1cc0>
 1065a6a:	80 fa 03             	cmp    $0x3,%dl
 1065a6d:	0f 85 16 1c 00 00    	jne    1067689 <my.interpreter::evaluate+0x2a39>
 1065a73:	49 89 c8             	mov    %rcx,%r8
 1065a76:	41 0f b6 d6          	movzbl %r14b,%edx
 1065a7a:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 1065a7f:	48 8b 5c 24 40       	mov    0x40(%rsp),%rbx
 1065a84:	48 89 de             	mov    %rbx,%rsi
 1065a87:	4c 89 e1             	mov    %r12,%rcx
 1065a8a:	e8 e1 a6 00 00       	call   1070170 <my.interpreter::bind>
 1065a8f:	48 8b 44 24 68       	mov    0x68(%rsp),%rax
 1065a94:	48 8b 4b 78          	mov    0x78(%rbx),%rcx
 1065a98:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 1065a9f:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065aa3:	48 89 f7             	mov    %rsi,%rdi
 1065aa6:	48 39 d6             	cmp    %rdx,%rsi
 1065aa9:	0f 83 57 16 00 00    	jae    1067106 <my.interpreter::evaluate+0x24b6>
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
 1065ad7:	0f 80 d2 1c 00 00    	jo     10677af <my.interpreter::evaluate+0x2b5f>
 1065add:	48 89 83 80 00 00 00 	mov    %rax,0x80(%rbx)
 1065ae4:	31 c0                	xor    %eax,%eax
 1065ae6:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1065aeb:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1065aef:	48 89 5d 08          	mov    %rbx,0x8(%rbp)
 1065af3:	48 89 75 10          	mov    %rsi,0x10(%rbp)
 1065af7:	48 89 55 18          	mov    %rdx,0x18(%rbp)
 1065afb:	0f b6 84 24 30 02 00 	movzbl 0x230(%rsp),%eax
 1065b02:	00 
 1065b03:	48 89 45 20          	mov    %rax,0x20(%rbp)
 1065b07:	48 89 7d 28          	mov    %rdi,0x28(%rbp)
 1065b0b:	e9 45 14 00 00       	jmp    1066f55 <my.interpreter::evaluate+0x2305>
 1065b10:	48 39 d0             	cmp    %rdx,%rax
 1065b13:	0f 83 c4 17 00 00    	jae    10672dd <my.interpreter::evaluate+0x268d>
 1065b19:	48 89 c7             	mov    %rax,%rdi
 1065b1c:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 1065b20:	83 7c 01 20 09       	cmpl   $0x9,0x20(%rcx,%rax,1)
 1065b25:	0f 85 6a 1d 00 00    	jne    1067895 <my.interpreter::evaluate+0x2c45>
 1065b2b:	48 01 c8             	add    %rcx,%rax
 1065b2e:	48 83 c0 20          	add    $0x20,%rax
 1065b32:	48 8b 40 10          	mov    0x10(%rax),%rax
 1065b36:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065b3a:	48 39 d6             	cmp    %rdx,%rsi
 1065b3d:	0f 83 bf 17 00 00    	jae    1067302 <my.interpreter::evaluate+0x26b2>
 1065b43:	48 89 f1             	mov    %rsi,%rcx
 1065b46:	48 c1 e1 04          	shl    $0x4,%rcx
 1065b4a:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 1065b50:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065b54:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065b5b:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065b5f:	48 89 f1             	mov    %rsi,%rcx
 1065b62:	48 39 d6             	cmp    %rdx,%rsi
 1065b65:	0f 83 b9 17 00 00    	jae    1067324 <my.interpreter::evaluate+0x26d4>
 1065b6b:	48 c1 e1 04          	shl    $0x4,%rcx
 1065b6f:	c5 f9 54 05 69 e8 f9 	vandpd -0x61797(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 1065b76:	ff 
 1065b77:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 1065b7d:	48 89 f0             	mov    %rsi,%rax
 1065b80:	48 ff c0             	inc    %rax
 1065b83:	0f 80 18 1d 00 00    	jo     10678a1 <my.interpreter::evaluate+0x2c51>
 1065b89:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065b90:	31 c0                	xor    %eax,%eax
 1065b92:	e9 c2 01 00 00       	jmp    1065d59 <my.interpreter::evaluate+0x1109>
 1065b97:	48 8b 8f 80 00 00 00 	mov    0x80(%rdi),%rcx
 1065b9e:	48 89 c8             	mov    %rcx,%rax
 1065ba1:	48 ff c8             	dec    %rax
 1065ba4:	0f 80 08 1d 00 00    	jo     10678b2 <my.interpreter::evaluate+0x2c62>
 1065baa:	48 8b 4f 78          	mov    0x78(%rdi),%rcx
 1065bae:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065bb2:	48 39 d0             	cmp    %rdx,%rax
 1065bb5:	0f 83 8b 17 00 00    	jae    1067346 <my.interpreter::evaluate+0x26f6>
 1065bbb:	49 89 c1             	mov    %rax,%r9
 1065bbe:	49 c1 e1 04          	shl    $0x4,%r9
 1065bc2:	4e 8b 44 09 28       	mov    0x28(%rcx,%r9,1),%r8
 1065bc7:	42 8b 4c 09 20       	mov    0x20(%rcx,%r9,1),%ecx
 1065bcc:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 1065bd1:	e8 aa 69 00 00       	call   106c580 <my.heap::set_env_slot>
 1065bd6:	e9 76 04 00 00       	jmp    1066051 <my.interpreter::evaluate+0x1401>
 1065bdb:	40 80 fe 02          	cmp    $0x2,%sil
 1065bdf:	0f 85 de 09 00 00    	jne    10665c3 <my.interpreter::evaluate+0x1973>
 1065be5:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 1065bec:	00 00 80 
 1065bef:	48 31 f2             	xor    %rsi,%rdx
 1065bf2:	48 c7 01 02 00 00 00 	movq   $0x2,(%rcx)
 1065bf9:	48 89 51 08          	mov    %rdx,0x8(%rcx)
 1065bfd:	e9 6f 08 00 00       	jmp    1066471 <my.interpreter::evaluate+0x1821>
 1065c02:	4c 89 ff             	mov    %r15,%rdi
 1065c05:	48 89 de             	mov    %rbx,%rsi
 1065c08:	e8 e3 45 00 00       	call   106a1f0 <my.heap::instance_class>
 1065c0d:	4c 89 ff             	mov    %r15,%rdi
 1065c10:	48 89 c6             	mov    %rax,%rsi
 1065c13:	4c 89 e2             	mov    %r12,%rdx
 1065c16:	89 e9                	mov    %ebp,%ecx
 1065c18:	e8 c3 47 00 00       	call   106a3e0 <my.heap::class_method>
 1065c1d:	3c 01                	cmp    $0x1,%al
 1065c1f:	0f 85 77 0e 00 00    	jne    1066a9c <my.interpreter::evaluate+0x1e4c>
 1065c25:	80 fa 03             	cmp    $0x3,%dl
 1065c28:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1065c2d:	0f 85 93 1a 00 00    	jne    10676c6 <my.interpreter::evaluate+0x2a76>
 1065c33:	49 89 c8             	mov    %rcx,%r8
 1065c36:	41 0f b6 d6          	movzbl %r14b,%edx
 1065c3a:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 1065c41:	00 
 1065c42:	4c 8b 7c 24 40       	mov    0x40(%rsp),%r15
 1065c47:	4c 89 fe             	mov    %r15,%rsi
 1065c4a:	48 89 d9             	mov    %rbx,%rcx
 1065c4d:	e8 1e a5 00 00       	call   1070170 <my.interpreter::bind>
 1065c52:	49 8b 87 80 00 00 00 	mov    0x80(%r15),%rax
 1065c59:	48 89 c6             	mov    %rax,%rsi
 1065c5c:	48 ff ce             	dec    %rsi
 1065c5f:	0f 80 94 1c 00 00    	jo     10678f9 <my.interpreter::evaluate+0x2ca9>
 1065c65:	48 8b 8c 24 a0 00 00 	mov    0xa0(%rsp),%rcx
 1065c6c:	00 
 1065c6d:	49 8b 47 78          	mov    0x78(%r15),%rax
 1065c71:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065c75:	48 39 d6             	cmp    %rdx,%rsi
 1065c78:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 1065c7e:	0f 83 e7 16 00 00    	jae    106736b <my.interpreter::evaluate+0x271b>
 1065c84:	48 89 f7             	mov    %rsi,%rdi
 1065c87:	48 c1 e7 04          	shl    $0x4,%rdi
 1065c8b:	48 8d 34 38          	lea    (%rax,%rdi,1),%rsi
 1065c8f:	48 83 c6 20          	add    $0x20,%rsi
 1065c93:	48 c7 44 38 20 03 00 	movq   $0x3,0x20(%rax,%rdi,1)
 1065c9a:	00 00 
 1065c9c:	48 89 4e 08          	mov    %rcx,0x8(%rsi)
 1065ca0:	49 89 47 78          	mov    %rax,0x78(%r15)
 1065ca4:	31 c0                	xor    %eax,%eax
 1065ca6:	4c 8b 7c 24 28       	mov    0x28(%rsp),%r15
 1065cab:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1065caf:	48 89 5d 08          	mov    %rbx,0x8(%rbp)
 1065cb3:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 1065cb7:	c5 f9 54 05 61 e6 f9 	vandpd -0x6199f(%rip),%xmm0,%xmm0        # 1004320 <__anon_2217+0x60>
 1065cbe:	ff 
 1065cbf:	c5 f9 11 45 18       	vmovupd %xmm0,0x18(%rbp)
 1065cc4:	4c 89 7d 28          	mov    %r15,0x28(%rbp)
 1065cc8:	e9 88 12 00 00       	jmp    1066f55 <my.interpreter::evaluate+0x2305>
 1065ccd:	48 8b 48 20          	mov    0x20(%rax),%rcx
 1065cd1:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
 1065cd6:	48 8b 58 30          	mov    0x30(%rax),%rbx
 1065cda:	4d 8b 79 30          	mov    0x30(%r9),%r15
 1065cde:	4d 8b 61 38          	mov    0x38(%r9),%r12
 1065ce2:	4c 89 cf             	mov    %r9,%rdi
 1065ce5:	48 89 de             	mov    %rbx,%rsi
 1065ce8:	4d 89 ce             	mov    %r9,%r14
 1065ceb:	e8 30 3e 00 00       	call   1069b20 <my.heap::string_hash>
 1065cf0:	4c 89 ff             	mov    %r15,%rdi
 1065cf3:	4c 89 e6             	mov    %r12,%rsi
 1065cf6:	48 89 da             	mov    %rbx,%rdx
 1065cf9:	89 c1                	mov    %eax,%ecx
 1065cfb:	e8 10 3d 00 00       	call   1069a10 <my.table::get>
 1065d00:	3c 01                	cmp    $0x1,%al
 1065d02:	0f 85 06 0e 00 00    	jne    1066b0e <my.interpreter::evaluate+0x1ebe>
 1065d08:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 1065d0c:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 1065d13:	48 8b 47 08          	mov    0x8(%rdi),%rax
 1065d17:	49 89 f0             	mov    %rsi,%r8
 1065d1a:	48 39 c6             	cmp    %rax,%rsi
 1065d1d:	0f 83 6a 16 00 00    	jae    106738d <my.interpreter::evaluate+0x273d>
 1065d23:	49 c1 e0 04          	shl    $0x4,%r8
 1065d27:	0f b6 c2             	movzbl %dl,%eax
 1065d2a:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 1065d2f:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 1065d34:	48 89 f0             	mov    %rsi,%rax
 1065d37:	48 ff c0             	inc    %rax
 1065d3a:	4c 8b 9c 24 28 02 00 	mov    0x228(%rsp),%r11
 1065d41:	00 
 1065d42:	0f 80 c5 1b 00 00    	jo     106790d <my.interpreter::evaluate+0x2cbd>
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
 1065d79:	e9 d7 11 00 00       	jmp    1066f55 <my.interpreter::evaluate+0x2305>
 1065d7e:	45 31 f6             	xor    %r14d,%r14d
 1065d81:	4c 8b 4c 24 40       	mov    0x40(%rsp),%r9
 1065d86:	4c 8b 44 24 38       	mov    0x38(%rsp),%r8
 1065d8b:	49 8b 81 80 00 00 00 	mov    0x80(%r9),%rax
 1065d92:	48 89 c6             	mov    %rax,%rsi
 1065d95:	4c 29 f6             	sub    %r14,%rsi
 1065d98:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1065d9d:	0f 80 1d 1a 00 00    	jo     10677c0 <my.interpreter::evaluate+0x2b70>
 1065da3:	49 89 f5             	mov    %rsi,%r13
 1065da6:	49 ff cd             	dec    %r13
 1065da9:	0f 80 23 1a 00 00    	jo     10677d2 <my.interpreter::evaluate+0x2b82>
 1065daf:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065db3:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065db7:	4c 89 e9             	mov    %r13,%rcx
 1065dba:	49 39 d5             	cmp    %rdx,%r13
 1065dbd:	0f 83 65 13 00 00    	jae    1067128 <my.interpreter::evaluate+0x24d8>
 1065dc3:	48 c1 e1 04          	shl    $0x4,%rcx
 1065dc7:	83 7c 08 20 03       	cmpl   $0x3,0x20(%rax,%rcx,1)
 1065dcc:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
 1065dd1:	0f 85 e4 09 00 00    	jne    10667bb <my.interpreter::evaluate+0x1b6b>
 1065dd7:	48 01 c8             	add    %rcx,%rax
 1065dda:	48 83 c0 20          	add    $0x20,%rax
 1065dde:	4c 8b 60 08          	mov    0x8(%rax),%r12
 1065de2:	49 8b 01             	mov    (%r9),%rax
 1065de5:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065de9:	4c 89 e1             	mov    %r12,%rcx
 1065dec:	49 39 d4             	cmp    %rdx,%r12
 1065def:	0f 83 33 14 00 00    	jae    1067228 <my.interpreter::evaluate+0x25d8>
 1065df5:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065df9:	8b 4c 08 20          	mov    0x20(%rax,%rcx,1),%ecx
 1065dfd:	83 f9 03             	cmp    $0x3,%ecx
 1065e00:	0f 84 2b 03 00 00    	je     1066131 <my.interpreter::evaluate+0x14e1>
 1065e06:	83 f9 06             	cmp    $0x6,%ecx
 1065e09:	4c 89 74 24 60       	mov    %r14,0x60(%rsp)
 1065e0e:	0f 84 a9 03 00 00    	je     10661bd <my.interpreter::evaluate+0x156d>
 1065e14:	83 f9 0a             	cmp    $0xa,%ecx
 1065e17:	0f 85 9e 09 00 00    	jne    10667bb <my.interpreter::evaluate+0x1b6b>
 1065e1d:	49 39 d4             	cmp    %rdx,%r12
 1065e20:	0f 83 ae 15 00 00    	jae    10673d4 <my.interpreter::evaluate+0x2784>
 1065e26:	4c 89 e1             	mov    %r12,%rcx
 1065e29:	48 83 c0 20          	add    $0x20,%rax
 1065e2d:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065e31:	83 3c 08 0a          	cmpl   $0xa,(%rax,%rcx,1)
 1065e35:	0f 85 f7 1a 00 00    	jne    1067932 <my.interpreter::evaluate+0x2ce2>
 1065e3b:	48 01 c8             	add    %rcx,%rax
 1065e3e:	48 8b 48 08          	mov    0x8(%rax),%rcx
 1065e42:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
 1065e47:	48 8b 68 10          	mov    0x10(%rax),%rbp
 1065e4b:	4c 8b 70 18          	mov    0x18(%rax),%r14
 1065e4f:	44 8b 60 20          	mov    0x20(%rax),%r12d
 1065e53:	49 ff c5             	inc    %r13
 1065e56:	48 83 ec 08          	sub    $0x8,%rsp
 1065e5a:	44 0f b6 ff          	movzbl %dil,%r15d
 1065e5e:	48 8d bc 24 40 01 00 	lea    0x140(%rsp),%rdi
 1065e65:	00 
 1065e66:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 1065e6b:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 1065e70:	48 89 d9             	mov    %rbx,%rcx
 1065e73:	4c 89 e8             	mov    %r13,%rax
 1065e76:	4d 89 c5             	mov    %r8,%r13
 1065e79:	ff 74 24 60          	push   0x60(%rsp)
 1065e7d:	50                   	push   %rax
 1065e7e:	ff 74 24 78          	push   0x78(%rsp)
 1065e82:	41 56                	push   %r14
 1065e84:	4c 89 a4 24 80 00 00 	mov    %r12,0x80(%rsp)
 1065e8b:	00 
 1065e8c:	41 54                	push   %r12
 1065e8e:	4d 89 f4             	mov    %r14,%r12
 1065e91:	41 56                	push   %r14
 1065e93:	48 89 6c 24 58       	mov    %rbp,0x58(%rsp)
 1065e98:	55                   	push   %rbp
 1065e99:	ff b4 24 80 00 00 00 	push   0x80(%rsp)
 1065ea0:	41 53                	push   %r11
 1065ea2:	4c 89 bc 24 88 00 00 	mov    %r15,0x88(%rsp)
 1065ea9:	00 
 1065eaa:	41 57                	push   %r15
 1065eac:	41 52                	push   %r10
 1065eae:	4d 89 ce             	mov    %r9,%r14
 1065eb1:	4d 89 d7             	mov    %r10,%r15
 1065eb4:	4c 89 dd             	mov    %r11,%rbp
 1065eb7:	e8 04 c7 00 00       	call   10725c0 <my.interpreter::enter_function>
 1065ebc:	48 83 c4 60          	add    $0x60,%rsp
 1065ec0:	4c 8b 94 24 40 01 00 	mov    0x140(%rsp),%r10
 1065ec7:	00 
 1065ec8:	80 bc 24 38 01 00 00 	cmpb   $0x1,0x138(%rsp)
 1065ecf:	01 
 1065ed0:	0f 84 6a 0e 00 00    	je     1066d40 <my.interpreter::evaluate+0x20f0>
 1065ed6:	0f b6 44 24 58       	movzbl 0x58(%rsp),%eax
 1065edb:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 1065ee2:	00 
 1065ee3:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1065ee8:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 1065eed:	48 89 d9             	mov    %rbx,%rcx
 1065ef0:	4d 89 e8             	mov    %r13,%r8
 1065ef3:	4d 89 f1             	mov    %r14,%r9
 1065ef6:	ff b4 24 48 02 00 00 	push   0x248(%rsp)
 1065efd:	41 52                	push   %r10
 1065eff:	50                   	push   %rax
 1065f00:	41 54                	push   %r12
 1065f02:	ff 74 24 40          	push   0x40(%rsp)
 1065f06:	ff 74 24 68          	push   0x68(%rsp)
 1065f0a:	55                   	push   %rbp
 1065f0b:	ff 74 24 70          	push   0x70(%rsp)
 1065f0f:	41 57                	push   %r15
 1065f11:	ff b4 24 68 02 00 00 	push   0x268(%rsp)
 1065f18:	e8 e3 cb 00 00       	call   1072b00 <my.interpreter::run_function>
 1065f1d:	48 83 c4 50          	add    $0x50,%rsp
 1065f21:	4c 8b a4 24 a8 00 00 	mov    0xa8(%rsp),%r12
 1065f28:	00 
 1065f29:	4c 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%r8
 1065f30:	00 
 1065f31:	4c 8b 94 24 b8 00 00 	mov    0xb8(%rsp),%r10
 1065f38:	00 
 1065f39:	44 0f b6 ac 24 c0 00 	movzbl 0xc0(%rsp),%r13d
 1065f40:	00 00 
 1065f42:	4c 8b 8c 24 c8 00 00 	mov    0xc8(%rsp),%r9
 1065f49:	00 
 1065f4a:	80 bc 24 a0 00 00 00 	cmpb   $0x1,0xa0(%rsp)
 1065f51:	01 
 1065f52:	0f 84 11 0e 00 00    	je     1066d69 <my.interpreter::evaluate+0x2119>
 1065f58:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 1065f5f:	48 89 f0             	mov    %rsi,%rax
 1065f62:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 1065f67:	48 29 d0             	sub    %rdx,%rax
 1065f6a:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1065f6f:	0f 80 0f 1a 00 00    	jo     1067984 <my.interpreter::evaluate+0x2d34>
 1065f75:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 1065f7c:	48 89 c6             	mov    %rax,%rsi
 1065f7f:	48 ff ce             	dec    %rsi
 1065f82:	0f 80 08 1a 00 00    	jo     1067990 <my.interpreter::evaluate+0x2d40>
 1065f88:	49 8b 46 78          	mov    0x78(%r14),%rax
 1065f8c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065f90:	48 39 d6             	cmp    %rdx,%rsi
 1065f93:	0f 83 d9 14 00 00    	jae    1067472 <my.interpreter::evaluate+0x2822>
 1065f99:	48 89 f1             	mov    %rsi,%rcx
 1065f9c:	48 c1 e1 04          	shl    $0x4,%rcx
 1065fa0:	41 0f b6 d4          	movzbl %r12b,%edx
 1065fa4:	48 89 54 08 20       	mov    %rdx,0x20(%rax,%rcx,1)
 1065fa9:	4c 89 44 08 28       	mov    %r8,0x28(%rax,%rcx,1)
 1065fae:	e9 ad 05 00 00       	jmp    1066560 <my.interpreter::evaluate+0x1910>
 1065fb3:	4c 8b 6c 24 40       	mov    0x40(%rsp),%r13
 1065fb8:	49 8b 5d 30          	mov    0x30(%r13),%rbx
 1065fbc:	4d 8b 7d 38          	mov    0x38(%r13),%r15
 1065fc0:	4c 89 ef             	mov    %r13,%rdi
 1065fc3:	4c 89 e6             	mov    %r12,%rsi
 1065fc6:	e8 55 3b 00 00       	call   1069b20 <my.heap::string_hash>
 1065fcb:	48 89 df             	mov    %rbx,%rdi
 1065fce:	4c 89 fe             	mov    %r15,%rsi
 1065fd1:	4c 89 e2             	mov    %r12,%rdx
 1065fd4:	89 c1                	mov    %eax,%ecx
 1065fd6:	e8 35 3a 00 00       	call   1069a10 <my.table::get>
 1065fdb:	3c 01                	cmp    $0x1,%al
 1065fdd:	0f 85 b7 0b 00 00    	jne    1066b9a <my.interpreter::evaluate+0x1f4a>
 1065fe3:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1065fea:	48 89 c6             	mov    %rax,%rsi
 1065fed:	48 ff ce             	dec    %rsi
 1065ff0:	0f 80 28 19 00 00    	jo     106791e <my.interpreter::evaluate+0x2cce>
 1065ff6:	4c 89 ef             	mov    %r13,%rdi
 1065ff9:	4d 89 f5             	mov    %r14,%r13
 1065ffc:	48 8b 47 78          	mov    0x78(%rdi),%rax
 1066000:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1066004:	49 89 ee             	mov    %rbp,%r14
 1066007:	48 39 d6             	cmp    %rdx,%rsi
 106600a:	0f 83 a2 13 00 00    	jae    10673b2 <my.interpreter::evaluate+0x2762>
 1066010:	48 89 f1             	mov    %rsi,%rcx
 1066013:	48 c1 e1 04          	shl    $0x4,%rcx
 1066017:	48 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%rbx
 106601c:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 1066020:	4c 89 e6             	mov    %r12,%rsi
 1066023:	49 89 ff             	mov    %rdi,%r15
 1066026:	e8 f5 3a 00 00       	call   1069b20 <my.heap::string_hash>
 106602b:	49 8b 7f 30          	mov    0x30(%r15),%rdi
 106602f:	49 8b 77 38          	mov    0x38(%r15),%rsi
 1066033:	4c 89 e2             	mov    %r12,%rdx
 1066036:	89 c1                	mov    %eax,%ecx
 1066038:	41 89 e8             	mov    %ebp,%r8d
 106603b:	49 89 d9             	mov    %rbx,%r9
 106603e:	e8 bd 3b 00 00       	call   1069c00 <my.table::set>
 1066043:	49 89 57 30          	mov    %rdx,0x30(%r15)
 1066047:	49 89 4f 38          	mov    %rcx,0x38(%r15)
 106604b:	4c 89 f5             	mov    %r14,%rbp
 106604e:	4d 89 ee             	mov    %r13,%r14
 1066051:	31 c0                	xor    %eax,%eax
 1066053:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 1066059:	48 89 45 00          	mov    %rax,0x0(%rbp)
 106605d:	48 89 5d 08          	mov    %rbx,0x8(%rbp)
 1066061:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 1066065:	c5 f9 54 05 b3 e2 f9 	vandpd -0x61d4d(%rip),%xmm0,%xmm0        # 1004320 <__anon_2217+0x60>
 106606c:	ff 
 106606d:	c5 f9 11 45 18       	vmovupd %xmm0,0x18(%rbp)
 1066072:	4c 89 75 28          	mov    %r14,0x28(%rbp)
 1066076:	e9 da 0e 00 00       	jmp    1066f55 <my.interpreter::evaluate+0x2305>
 106607b:	48 01 f8             	add    %rdi,%rax
 106607e:	48 83 c0 20          	add    $0x20,%rax
 1066082:	83 fd 1e             	cmp    $0x1e,%ebp
 1066085:	0f 95 c2             	setne  %dl
 1066088:	32 50 08             	xor    0x8(%rax),%dl
 106608b:	f6 c2 01             	test   $0x1,%dl
 106608e:	0f 84 a6 f5 ff ff    	je     106563a <my.interpreter::evaluate+0x9ea>
 1066094:	31 c0                	xor    %eax,%eax
 1066096:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 106609b:	48 89 45 00          	mov    %rax,0x0(%rbp)
 106609f:	c5 f9 11 45 08       	vmovupd %xmm0,0x8(%rbp)
 10660a4:	4c 89 55 18          	mov    %r10,0x18(%rbp)
 10660a8:	4c 89 75 20          	mov    %r14,0x20(%rbp)
 10660ac:	4c 89 7d 28          	mov    %r15,0x28(%rbp)
 10660b0:	e9 a0 0e 00 00       	jmp    1066f55 <my.interpreter::evaluate+0x2305>
 10660b5:	83 fd 1e             	cmp    $0x1e,%ebp
 10660b8:	0f 85 7c f5 ff ff    	jne    106563a <my.interpreter::evaluate+0x9ea>
 10660be:	eb d4                	jmp    1066094 <my.interpreter::evaluate+0x1444>
 10660c0:	3c 02                	cmp    $0x2,%al
 10660c2:	0f 84 89 05 00 00    	je     1066651 <my.interpreter::evaluate+0x1a01>
 10660c8:	0f b6 c0             	movzbl %al,%eax
 10660cb:	83 f8 01             	cmp    $0x1,%eax
 10660ce:	0f 84 31 05 00 00    	je     1066605 <my.interpreter::evaluate+0x19b5>
 10660d4:	85 c0                	test   %eax,%eax
 10660d6:	0f 85 9a 05 00 00    	jne    1066676 <my.interpreter::evaluate+0x1a26>
 10660dc:	40 84 ed             	test   %bpl,%bpl
 10660df:	41 0f 94 c4          	sete   %r12b
 10660e3:	e9 9f 05 00 00       	jmp    1066687 <my.interpreter::evaluate+0x1a37>
 10660e8:	89 c1                	mov    %eax,%ecx
 10660ea:	80 f1 02             	xor    $0x2,%cl
 10660ed:	c4 c1 f9 6e c5       	vmovq  %r13,%xmm0
 10660f2:	89 ea                	mov    %ebp,%edx
 10660f4:	80 f2 02             	xor    $0x2,%dl
 10660f7:	c4 c1 f9 6e cc       	vmovq  %r12,%xmm1
 10660fc:	08 ca                	or     %cl,%dl
 10660fe:	0f 94 c1             	sete   %cl
 1066101:	83 fe 07             	cmp    $0x7,%esi
 1066104:	0f 85 8f 03 00 00    	jne    1066499 <my.interpreter::evaluate+0x1849>
 106610a:	84 c9                	test   %cl,%cl
 106610c:	0f 84 f4 05 00 00    	je     1066706 <my.interpreter::evaluate+0x1ab6>
 1066112:	c5 fb 58 c1          	vaddsd %xmm1,%xmm0,%xmm0
 1066116:	c4 e1 f9 7e c2       	vmovq  %xmm0,%rdx
 106611b:	b0 02                	mov    $0x2,%al
 106611d:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1066122:	41 f6 c7 01          	test   $0x1,%r15b
 1066126:	0f 84 76 05 00 00    	je     10666a2 <my.interpreter::evaluate+0x1a52>
 106612c:	e9 76 06 00 00       	jmp    10667a7 <my.interpreter::evaluate+0x1b57>
 1066131:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 1066136:	4d 89 d5             	mov    %r10,%r13
 1066139:	4c 89 cf             	mov    %r9,%rdi
 106613c:	4c 89 e6             	mov    %r12,%rsi
 106613f:	4c 89 cb             	mov    %r9,%rbx
 1066142:	e8 c9 44 00 00       	call   106a610 <my.heap::native_obj>
 1066147:	49 39 d6             	cmp    %rdx,%r14
 106614a:	0f 85 c6 0a 00 00    	jne    1066c16 <my.interpreter::evaluate+0x1fc6>
 1066150:	48 89 c7             	mov    %rax,%rdi
 1066153:	48 8b b4 24 48 02 00 	mov    0x248(%rsp),%rsi
 106615a:	00 
 106615b:	e8 90 45 00 00       	call   106a6f0 <my.natives::call_native>
 1066160:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 1066167:	48 89 f1             	mov    %rsi,%rcx
 106616a:	4c 29 f1             	sub    %r14,%rcx
 106616d:	0f 80 cb 17 00 00    	jo     106793e <my.interpreter::evaluate+0x2cee>
 1066173:	48 89 8b 80 00 00 00 	mov    %rcx,0x80(%rbx)
 106617a:	48 89 ce             	mov    %rcx,%rsi
 106617d:	48 ff ce             	dec    %rsi
 1066180:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 1066185:	0f 80 c2 17 00 00    	jo     106794d <my.interpreter::evaluate+0x2cfd>
 106618b:	4d 89 ea             	mov    %r13,%r10
 106618e:	48 8b 7b 78          	mov    0x78(%rbx),%rdi
 1066192:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1066196:	48 39 ce             	cmp    %rcx,%rsi
 1066199:	0f 83 8c 12 00 00    	jae    106742b <my.interpreter::evaluate+0x27db>
 106619f:	49 89 f0             	mov    %rsi,%r8
 10661a2:	49 c1 e0 04          	shl    $0x4,%r8
 10661a6:	0f b6 c0             	movzbl %al,%eax
 10661a9:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 10661ae:	4a 89 54 07 28       	mov    %rdx,0x28(%rdi,%r8,1)
 10661b3:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 10661b8:	e9 a3 03 00 00       	jmp    1066560 <my.interpreter::evaluate+0x1910>
 10661bd:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 10661c2:	4c 89 94 24 98 00 00 	mov    %r10,0x98(%rsp)
 10661c9:	00 
 10661ca:	48 8d bc 24 00 01 00 	lea    0x100(%rsp),%rdi
 10661d1:	00 
 10661d2:	4c 89 ce             	mov    %r9,%rsi
 10661d5:	4c 89 e2             	mov    %r12,%rdx
 10661d8:	e8 f3 42 00 00       	call   106a4d0 <my.heap::allocate_instance>
 10661dd:	4c 8b 74 24 40       	mov    0x40(%rsp),%r14
 10661e2:	4c 8b bc 24 00 01 00 	mov    0x100(%rsp),%r15
 10661e9:	00 
 10661ea:	49 8b 46 78          	mov    0x78(%r14),%rax
 10661ee:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10661f2:	4c 89 e9             	mov    %r13,%rcx
 10661f5:	4c 89 ac 24 d0 00 00 	mov    %r13,0xd0(%rsp)
 10661fc:	00 
 10661fd:	49 39 d5             	cmp    %rdx,%r13
 1066200:	0f 83 f3 11 00 00    	jae    10673f9 <my.interpreter::evaluate+0x27a9>
 1066206:	48 c1 e1 04          	shl    $0x4,%rcx
 106620a:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 1066211:	00 00 
 1066213:	4c 89 7c 08 28       	mov    %r15,0x28(%rax,%rcx,1)
 1066218:	4d 8b 6e 40          	mov    0x40(%r14),%r13
 106621c:	4c 89 f7             	mov    %r14,%rdi
 106621f:	4c 89 ee             	mov    %r13,%rsi
 1066222:	e8 f9 38 00 00       	call   1069b20 <my.heap::string_hash>
 1066227:	4c 89 f7             	mov    %r14,%rdi
 106622a:	4c 89 e6             	mov    %r12,%rsi
 106622d:	4c 89 ea             	mov    %r13,%rdx
 1066230:	89 c1                	mov    %eax,%ecx
 1066232:	e8 a9 41 00 00       	call   106a3e0 <my.heap::class_method>
 1066237:	3c 01                	cmp    $0x1,%al
 1066239:	4c 89 bc 24 f0 00 00 	mov    %r15,0xf0(%rsp)
 1066240:	00 
 1066241:	0f 85 98 02 00 00    	jne    10664df <my.interpreter::evaluate+0x188f>
 1066247:	89 d7                	mov    %edx,%edi
 1066249:	48 89 ce             	mov    %rcx,%rsi
 106624c:	e8 ef 62 00 00       	call   106c540 <my.interpreter::as_obj>
 1066251:	48 8d bc 24 68 01 00 	lea    0x168(%rsp),%rdi
 1066258:	00 
 1066259:	4c 89 f6             	mov    %r14,%rsi
 106625c:	48 89 c2             	mov    %rax,%rdx
 106625f:	e8 dc c2 00 00       	call   1072540 <my.heap::tree_function_obj>
 1066264:	0f b6 ac 24 80 01 00 	movzbl 0x180(%rsp),%ebp
 106626b:	00 
 106626c:	48 8b 94 24 78 01 00 	mov    0x178(%rsp),%rdx
 1066273:	00 
 1066274:	48 8b 84 24 68 01 00 	mov    0x168(%rsp),%rax
 106627b:	00 
 106627c:	48 89 84 24 e0 00 00 	mov    %rax,0xe0(%rsp)
 1066283:	00 
 1066284:	48 8b 84 24 70 01 00 	mov    0x170(%rsp),%rax
 106628b:	00 
 106628c:	48 89 84 24 e8 00 00 	mov    %rax,0xe8(%rsp)
 1066293:	00 
 1066294:	48 8d bc 24 f8 00 00 	lea    0xf8(%rsp),%rdi
 106629b:	00 
 106629c:	b9 01 00 00 00       	mov    $0x1,%ecx
 10662a1:	4c 89 f6             	mov    %r14,%rsi
 10662a4:	48 89 94 24 d8 00 00 	mov    %rdx,0xd8(%rsp)
 10662ab:	00 
 10662ac:	e8 3f 61 00 00       	call   106c3f0 <my.interpreter::new_env>
 10662b1:	4c 8b a4 24 f8 00 00 	mov    0xf8(%rsp),%r12
 10662b8:	00 
 10662b9:	4c 89 f7             	mov    %r14,%rdi
 10662bc:	4c 89 e6             	mov    %r12,%rsi
 10662bf:	31 d2                	xor    %edx,%edx
 10662c1:	b9 03 00 00 00       	mov    $0x3,%ecx
 10662c6:	4d 89 f8             	mov    %r15,%r8
 10662c9:	e8 b2 62 00 00       	call   106c580 <my.heap::set_env_slot>
 10662ce:	49 8b 46 78          	mov    0x78(%r14),%rax
 10662d2:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 10662d9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10662dd:	48 89 f1             	mov    %rsi,%rcx
 10662e0:	48 39 d6             	cmp    %rdx,%rsi
 10662e3:	4d 89 f1             	mov    %r14,%r9
 10662e6:	0f 83 a8 11 00 00    	jae    1067494 <my.interpreter::evaluate+0x2844>
 10662ec:	48 c1 e1 04          	shl    $0x4,%rcx
 10662f0:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 10662f7:	00 00 
 10662f9:	4c 89 64 08 28       	mov    %r12,0x28(%rax,%rcx,1)
 10662fe:	48 89 f0             	mov    %rsi,%rax
 1066301:	48 ff c0             	inc    %rax
 1066304:	4c 8b 94 24 98 00 00 	mov    0x98(%rsp),%r10
 106630b:	00 
 106630c:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 1066311:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 1066316:	4c 8b 44 24 38       	mov    0x38(%rsp),%r8
 106631b:	4c 8b 74 24 60       	mov    0x60(%rsp),%r14
 1066320:	0f 80 7e 16 00 00    	jo     10679a4 <my.interpreter::evaluate+0x2d54>
 1066326:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 106632d:	48 8b 84 24 d0 00 00 	mov    0xd0(%rsp),%rax
 1066334:	00 
 1066335:	48 ff c0             	inc    %rax
 1066338:	48 83 ec 08          	sub    $0x8,%rsp
 106633c:	44 0f b6 e9          	movzbl %cl,%r13d
 1066340:	40 0f b6 ed          	movzbl %bpl,%ebp
 1066344:	48 8d bc 24 58 01 00 	lea    0x158(%rsp),%rdi
 106634b:	00 
 106634c:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 1066351:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 1066356:	48 89 d9             	mov    %rbx,%rcx
 1066359:	ff 74 24 60          	push   0x60(%rsp)
 106635d:	50                   	push   %rax
 106635e:	41 56                	push   %r14
 1066360:	41 54                	push   %r12
 1066362:	55                   	push   %rbp
 1066363:	ff b4 24 08 01 00 00 	push   0x108(%rsp)
 106636a:	ff b4 24 20 01 00 00 	push   0x120(%rsp)
 1066371:	ff b4 24 20 01 00 00 	push   0x120(%rsp)
 1066378:	41 53                	push   %r11
 106637a:	41 55                	push   %r13
 106637c:	41 52                	push   %r10
 106637e:	4d 89 ce             	mov    %r9,%r14
 1066381:	e8 3a c2 00 00       	call   10725c0 <my.interpreter::enter_function>
 1066386:	48 83 c4 60          	add    $0x60,%rsp
 106638a:	4c 8b a4 24 58 01 00 	mov    0x158(%rsp),%r12
 1066391:	00 
 1066392:	80 bc 24 50 01 00 00 	cmpb   $0x1,0x150(%rsp)
 1066399:	01 
 106639a:	0f 84 27 0b 00 00    	je     1066ec7 <my.interpreter::evaluate+0x2277>
 10663a0:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 10663a7:	48 89 c6             	mov    %rax,%rsi
 10663aa:	48 ff ce             	dec    %rsi
 10663ad:	0f 80 02 16 00 00    	jo     10679b5 <my.interpreter::evaluate+0x2d65>
 10663b3:	4d 89 f1             	mov    %r14,%r9
 10663b6:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 10663bd:	49 8b 46 78          	mov    0x78(%r14),%rax
 10663c1:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10663c5:	48 39 d6             	cmp    %rdx,%rsi
 10663c8:	4c 8b bc 24 98 00 00 	mov    0x98(%rsp),%r15
 10663cf:	00 
 10663d0:	4c 8b 54 24 20       	mov    0x20(%rsp),%r10
 10663d5:	4c 8b 44 24 38       	mov    0x38(%rsp),%r8
 10663da:	4c 8b 9c 24 48 02 00 	mov    0x248(%rsp),%r11
 10663e1:	00 
 10663e2:	4c 8b 74 24 60       	mov    0x60(%rsp),%r14
 10663e7:	0f 83 c9 10 00 00    	jae    10674b6 <my.interpreter::evaluate+0x2866>
 10663ed:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 10663f2:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10663f7:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 10663fc:	48 89 d9             	mov    %rbx,%rcx
 10663ff:	41 53                	push   %r11
 1066401:	41 54                	push   %r12
 1066403:	55                   	push   %rbp
 1066404:	ff b4 24 f0 00 00 00 	push   0xf0(%rsp)
 106640b:	ff b4 24 08 01 00 00 	push   0x108(%rsp)
 1066412:	ff b4 24 08 01 00 00 	push   0x108(%rsp)
 1066419:	41 52                	push   %r10
 106641b:	41 55                	push   %r13
 106641d:	41 57                	push   %r15
 106641f:	ff b4 24 68 02 00 00 	push   0x268(%rsp)
 1066426:	e8 d5 c6 00 00       	call   1072b00 <my.interpreter::run_function>
 106642b:	48 83 c4 50          	add    $0x50,%rsp
 106642f:	4c 8b 94 24 80 00 00 	mov    0x80(%rsp),%r10
 1066436:	00 
 1066437:	0f b6 84 24 88 00 00 	movzbl 0x88(%rsp),%eax
 106643e:	00 
 106643f:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 1066444:	4c 8b 8c 24 90 00 00 	mov    0x90(%rsp),%r9
 106644b:	00 
 106644c:	80 7c 24 68 01       	cmpb   $0x1,0x68(%rsp)
 1066451:	0f 84 93 0a 00 00    	je     1066eea <my.interpreter::evaluate+0x229a>
 1066457:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 106645c:	e9 99 00 00 00       	jmp    10664fa <my.interpreter::evaluate+0x18aa>
 1066461:	b2 01                	mov    $0x1,%dl
 1066463:	eb 02                	jmp    1066467 <my.interpreter::evaluate+0x1817>
 1066465:	31 d2                	xor    %edx,%edx
 1066467:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 106646e:	88 51 08             	mov    %dl,0x8(%rcx)
 1066471:	49 89 40 78          	mov    %rax,0x78(%r8)
 1066475:	31 c9                	xor    %ecx,%ecx
 1066477:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 106647b:	48 89 45 08          	mov    %rax,0x8(%rbp)
 106647f:	4c 89 7d 10          	mov    %r15,0x10(%rbp)
 1066483:	c5 f9 54 05 95 de f9 	vandpd -0x6216b(%rip),%xmm0,%xmm0        # 1004320 <__anon_2217+0x60>
 106648a:	ff 
 106648b:	c5 f9 11 45 18       	vmovupd %xmm0,0x18(%rbp)
 1066490:	48 89 5d 28          	mov    %rbx,0x28(%rbp)
 1066494:	e9 bc 0a 00 00       	jmp    1066f55 <my.interpreter::evaluate+0x2305>
 1066499:	45 89 fd             	mov    %r15d,%r13d
 106649c:	4c 89 5c 24 10       	mov    %r11,0x10(%rsp)
 10664a1:	4d 89 d7             	mov    %r10,%r15
 10664a4:	84 c9                	test   %cl,%cl
 10664a6:	0f 84 dd 08 00 00    	je     1066d89 <my.interpreter::evaluate+0x2139>
 10664ac:	40 0f b6 fe          	movzbl %sil,%edi
 10664b0:	4d 89 cc             	mov    %r9,%r12
 10664b3:	e8 58 9c 00 00       	call   1070110 <my.interpreter::arithmetic>
 10664b8:	4d 89 e1             	mov    %r12,%r9
 10664bb:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 10664c0:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 10664c5:	4d 89 fa             	mov    %r15,%r10
 10664c8:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 10664cd:	45 89 ef             	mov    %r13d,%r15d
 10664d0:	41 f6 c7 01          	test   $0x1,%r15b
 10664d4:	0f 84 c8 01 00 00    	je     10666a2 <my.interpreter::evaluate+0x1a52>
 10664da:	e9 c8 02 00 00       	jmp    10667a7 <my.interpreter::evaluate+0x1b57>
 10664df:	4c 8b 74 24 60       	mov    0x60(%rsp),%r14
 10664e4:	4d 85 f6             	test   %r14,%r14
 10664e7:	4c 8b 94 24 98 00 00 	mov    0x98(%rsp),%r10
 10664ee:	00 
 10664ef:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 10664f4:	0f 85 dd 08 00 00    	jne    1066dd7 <my.interpreter::evaluate+0x2187>
 10664fa:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 10664ff:	48 8b b7 80 00 00 00 	mov    0x80(%rdi),%rsi
 1066506:	48 89 f0             	mov    %rsi,%rax
 1066509:	4c 29 f0             	sub    %r14,%rax
 106650c:	0f 80 4f 14 00 00    	jo     1067961 <my.interpreter::evaluate+0x2d11>
 1066512:	48 89 87 80 00 00 00 	mov    %rax,0x80(%rdi)
 1066519:	48 89 c6             	mov    %rax,%rsi
 106651c:	48 ff ce             	dec    %rsi
 106651f:	0f 80 4b 14 00 00    	jo     1067970 <my.interpreter::evaluate+0x2d20>
 1066525:	48 8b 47 78          	mov    0x78(%rdi),%rax
 1066529:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106652d:	48 39 d6             	cmp    %rdx,%rsi
 1066530:	0f 83 1a 0f 00 00    	jae    1067450 <my.interpreter::evaluate+0x2800>
 1066536:	48 89 f1             	mov    %rsi,%rcx
 1066539:	48 c1 e1 04          	shl    $0x4,%rcx
 106653d:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 1066544:	00 00 
 1066546:	48 8b 94 24 f0 00 00 	mov    0xf0(%rsp),%rdx
 106654d:	00 
 106654e:	48 89 54 08 28       	mov    %rdx,0x28(%rax,%rcx,1)
 1066553:	48 89 47 78          	mov    %rax,0x78(%rdi)
 1066557:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 106655c:	45 0f b6 ed          	movzbl %r13b,%r13d
 1066560:	31 c0                	xor    %eax,%eax
 1066562:	e9 d6 09 00 00       	jmp    1066f3d <my.interpreter::evaluate+0x22ed>
 1066567:	48 8d 3d 32 bb fa ff 	lea    -0x544ce(%rip),%rdi        # 10120a0 <core_number_pairs+0xae40>
 106656e:	e8 0d da fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066573:	48 89 c3             	mov    %rax,%rbx
 1066576:	48 8d 3d 23 eb 01 00 	lea    0x1eb23(%rip),%rdi        # 10850a0 <core_durable_error.verbs+0x6150>
 106657d:	e8 be 02 ff ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066582:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 1066587:	e9 b8 02 00 00       	jmp    1066844 <my.interpreter::evaluate+0x1bf4>
 106658c:	48 8d 3d 4d bb fa ff 	lea    -0x544b3(%rip),%rdi        # 10120e0 <core_number_pairs+0xae80>
 1066593:	e8 e8 d9 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066598:	48 8d 3d 41 ed 01 00 	lea    0x1ed41(%rip),%rdi        # 10852e0 <core_durable_error.verbs+0x6390>
 106659f:	e8 9c 02 ff ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 10665a4:	c5 fa 7e 44 24 58    	vmovq  0x58(%rsp),%xmm0
 10665aa:	c4 e1 f9 6e c8       	vmovq  %rax,%xmm1
 10665af:	c5 f1 6c c0          	vpunpcklqdq %xmm0,%xmm1,%xmm0
 10665b3:	c5 f9 7f 44 24 40    	vmovdqa %xmm0,0x40(%rsp)
 10665b9:	48 8b 4c 24 08       	mov    0x8(%rsp),%rcx
 10665be:	e9 3c 04 00 00       	jmp    10669ff <my.interpreter::evaluate+0x1daf>
 10665c3:	40 0f b6 c6          	movzbl %sil,%eax
 10665c7:	83 f8 01             	cmp    $0x1,%eax
 10665ca:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 10665d0:	48 8d 3d e9 bb fa ff 	lea    -0x54417(%rip),%rdi        # 10121c0 <core_number_pairs+0xaf60>
 10665d7:	0f 84 84 04 00 00    	je     1066a61 <my.interpreter::evaluate+0x1e11>
 10665dd:	85 c0                	test   %eax,%eax
 10665df:	0f 85 8a 04 00 00    	jne    1066a6f <my.interpreter::evaluate+0x1e1f>
 10665e5:	e8 96 d9 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 10665ea:	48 8d 3d 4f f0 01 00 	lea    0x1f04f(%rip),%rdi        # 1085640 <core_durable_error.verbs+0x66f0>
 10665f1:	e9 85 04 00 00       	jmp    1066a7b <my.interpreter::evaluate+0x1e2b>
 10665f6:	40 80 fd 01          	cmp    $0x1,%bpl
 10665fa:	75 38                	jne    1066634 <my.interpreter::evaluate+0x19e4>
 10665fc:	45 31 ec             	xor    %r13d,%r12d
 10665ff:	41 80 f4 01          	xor    $0x1,%r12b
 1066603:	eb 45                	jmp    106664a <my.interpreter::evaluate+0x19fa>
 1066605:	40 80 fd 01          	cmp    $0x1,%bpl
 1066609:	75 66                	jne    1066671 <my.interpreter::evaluate+0x1a21>
 106660b:	45 31 ec             	xor    %r13d,%r12d
 106660e:	41 80 f4 01          	xor    $0x1,%r12b
 1066612:	eb 73                	jmp    1066687 <my.interpreter::evaluate+0x1a37>
 1066614:	40 80 fd 02          	cmp    $0x2,%bpl
 1066618:	75 1a                	jne    1066634 <my.interpreter::evaluate+0x19e4>
 106661a:	c4 c1 f9 6e c5       	vmovq  %r13,%xmm0
 106661f:	c4 c1 f9 6e cc       	vmovq  %r12,%xmm1
 1066624:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 1066629:	c4 c1 f9 7e c4       	vmovq  %xmm0,%r12
 106662e:	41 83 e4 01          	and    $0x1,%r12d
 1066632:	eb 16                	jmp    106664a <my.interpreter::evaluate+0x19fa>
 1066634:	45 31 e4             	xor    %r12d,%r12d
 1066637:	eb 11                	jmp    106664a <my.interpreter::evaluate+0x19fa>
 1066639:	40 80 fd 03          	cmp    $0x3,%bpl
 106663d:	0f 94 c0             	sete   %al
 1066640:	4d 39 e5             	cmp    %r12,%r13
 1066643:	41 0f 94 c4          	sete   %r12b
 1066647:	41 20 c4             	and    %al,%r12b
 106664a:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 106664f:	eb 3e                	jmp    106668f <my.interpreter::evaluate+0x1a3f>
 1066651:	40 80 fd 02          	cmp    $0x2,%bpl
 1066655:	75 1a                	jne    1066671 <my.interpreter::evaluate+0x1a21>
 1066657:	c4 c1 f9 6e c5       	vmovq  %r13,%xmm0
 106665c:	c4 c1 f9 6e cc       	vmovq  %r12,%xmm1
 1066661:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 1066666:	c4 c1 f9 7e c4       	vmovq  %xmm0,%r12
 106666b:	41 83 e4 01          	and    $0x1,%r12d
 106666f:	eb 16                	jmp    1066687 <my.interpreter::evaluate+0x1a37>
 1066671:	45 31 e4             	xor    %r12d,%r12d
 1066674:	eb 11                	jmp    1066687 <my.interpreter::evaluate+0x1a37>
 1066676:	40 80 fd 03          	cmp    $0x3,%bpl
 106667a:	0f 94 c0             	sete   %al
 106667d:	4d 39 e5             	cmp    %r12,%r13
 1066680:	41 0f 94 c4          	sete   %r12b
 1066684:	41 20 c4             	and    %al,%r12b
 1066687:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 106668c:	41 f6 d4             	not    %r12b
 106668f:	41 0f b6 d4          	movzbl %r12b,%edx
 1066693:	83 e2 01             	and    $0x1,%edx
 1066696:	b0 01                	mov    $0x1,%al
 1066698:	41 f6 c7 01          	test   $0x1,%r15b
 106669c:	0f 85 05 01 00 00    	jne    10667a7 <my.interpreter::evaluate+0x1b57>
 10666a2:	48 89 9f 80 00 00 00 	mov    %rbx,0x80(%rdi)
 10666a9:	4c 8b 4f 78          	mov    0x78(%rdi),%r9
 10666ad:	49 8b 49 08          	mov    0x8(%r9),%rcx
 10666b1:	48 39 cb             	cmp    %rcx,%rbx
 10666b4:	0f 83 21 0b 00 00    	jae    10671db <my.interpreter::evaluate+0x258b>
 10666ba:	48 89 de             	mov    %rbx,%rsi
 10666bd:	48 ff ce             	dec    %rsi
 10666c0:	0f 80 45 11 00 00    	jo     106780b <my.interpreter::evaluate+0x2bbb>
 10666c6:	48 39 ce             	cmp    %rcx,%rsi
 10666c9:	0f 83 34 0b 00 00    	jae    1067203 <my.interpreter::evaluate+0x25b3>
 10666cf:	49 89 f0             	mov    %rsi,%r8
 10666d2:	49 c1 e0 04          	shl    $0x4,%r8
 10666d6:	0f b6 c0             	movzbl %al,%eax
 10666d9:	4b 89 44 01 20       	mov    %rax,0x20(%r9,%r8,1)
 10666de:	4b 89 54 01 28       	mov    %rdx,0x28(%r9,%r8,1)
 10666e3:	4c 89 4f 78          	mov    %r9,0x78(%rdi)
 10666e7:	31 c9                	xor    %ecx,%ecx
 10666e9:	48 89 4d 00          	mov    %rcx,0x0(%rbp)
 10666ed:	48 89 45 08          	mov    %rax,0x8(%rbp)
 10666f1:	48 89 55 10          	mov    %rdx,0x10(%rbp)
 10666f5:	4c 89 55 18          	mov    %r10,0x18(%rbp)
 10666f9:	4c 89 5d 20          	mov    %r11,0x20(%rbp)
 10666fd:	4c 89 75 28          	mov    %r14,0x28(%rbp)
 1066701:	e9 4f 08 00 00       	jmp    1066f55 <my.interpreter::evaluate+0x2305>
 1066706:	4c 89 5c 24 10       	mov    %r11,0x10(%rsp)
 106670b:	4c 89 54 24 40       	mov    %r10,0x40(%rsp)
 1066710:	0f b6 d8             	movzbl %al,%ebx
 1066713:	89 de                	mov    %ebx,%esi
 1066715:	4c 89 ea             	mov    %r13,%rdx
 1066718:	49 89 ff             	mov    %rdi,%r15
 106671b:	e8 a0 99 00 00       	call   10700c0 <my.interpreter::is_string>
 1066720:	a8 01                	test   $0x1,%al
 1066722:	0f 84 83 06 00 00    	je     1066dab <my.interpreter::evaluate+0x215b>
 1066728:	40 0f b6 ed          	movzbl %bpl,%ebp
 106672c:	4c 89 ff             	mov    %r15,%rdi
 106672f:	89 ee                	mov    %ebp,%esi
 1066731:	4c 89 e2             	mov    %r12,%rdx
 1066734:	e8 87 99 00 00       	call   10700c0 <my.interpreter::is_string>
 1066739:	a8 01                	test   $0x1,%al
 106673b:	0f 84 6a 06 00 00    	je     1066dab <my.interpreter::evaluate+0x215b>
 1066741:	89 df                	mov    %ebx,%edi
 1066743:	4c 89 ee             	mov    %r13,%rsi
 1066746:	e8 f5 5d 00 00       	call   106c540 <my.interpreter::as_obj>
 106674b:	48 89 c3             	mov    %rax,%rbx
 106674e:	89 ef                	mov    %ebp,%edi
 1066750:	4c 89 e6             	mov    %r12,%rsi
 1066753:	e8 e8 5d 00 00       	call   106c540 <my.interpreter::as_obj>
 1066758:	48 8d bc 24 08 01 00 	lea    0x108(%rsp),%rdi
 106675f:	00 
 1066760:	4c 89 fe             	mov    %r15,%rsi
 1066763:	48 89 da             	mov    %rbx,%rdx
 1066766:	48 89 c1             	mov    %rax,%rcx
 1066769:	e8 12 79 00 00       	call   106e080 <my.lox_strings::concat>
 106676e:	48 8b 94 24 08 01 00 	mov    0x108(%rsp),%rdx
 1066775:	00 
 1066776:	b0 03                	mov    $0x3,%al
 1066778:	4d 8b 8f 80 00 00 00 	mov    0x80(%r15),%r9
 106677f:	4c 89 cb             	mov    %r9,%rbx
 1066782:	48 ff cb             	dec    %rbx
 1066785:	0f 90 c1             	seto   %cl
 1066788:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 106678d:	4c 89 ff             	mov    %r15,%rdi
 1066790:	41 89 cf             	mov    %ecx,%r15d
 1066793:	4c 8b 54 24 40       	mov    0x40(%rsp),%r10
 1066798:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 106679d:	41 f6 c7 01          	test   $0x1,%r15b
 10667a1:	0f 84 fb fe ff ff    	je     10666a2 <my.interpreter::evaluate+0x1a52>
 10667a7:	48 8d 3d 42 e7 01 00 	lea    0x1e742(%rip),%rdi        # 1084ef0 <core_durable_error.verbs+0x5fa0>
 10667ae:	ba 01 00 00 00       	mov    $0x1,%edx
 10667b3:	4c 89 ce             	mov    %r9,%rsi
 10667b6:	e8 c5 dc fb ff       	call   1024480 <myl_core_trap>
 10667bb:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 10667c0:	48 8d 3d 39 ba fa ff 	lea    -0x545c7(%rip),%rdi        # 1012200 <core_number_pairs+0xafa0>
 10667c7:	4c 89 d3             	mov    %r10,%rbx
 10667ca:	e8 b1 d7 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 10667cf:	49 89 da             	mov    %rbx,%r10
 10667d2:	49 89 c4             	mov    %rax,%r12
 10667d5:	48 8d 3d b4 04 02 00 	lea    0x204b4(%rip),%rdi        # 1086c90 <core_durable_error.verbs+0x7d40>
 10667dc:	e8 5f 00 ff ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 10667e1:	4c 8b 44 24 58       	mov    0x58(%rsp),%r8
 10667e6:	e9 2b 07 00 00       	jmp    1066f16 <my.interpreter::evaluate+0x22c6>
 10667eb:	48 8d 3d 7e b8 01 00 	lea    0x1b87e(%rip),%rdi        # 1082070 <core_durable_error.verbs+0x3120>
 10667f2:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 10667f8:	e8 83 00 ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 10667fd:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 1066803:	e9 22 e6 ff ff       	jmp    1064e2a <my.interpreter::evaluate+0x1da>
 1066808:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
 106680d:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 1066812:	48 8d 84 24 10 01 00 	lea    0x110(%rsp),%rax
 1066819:	00 
 106681a:	48 8d 8c 24 18 01 00 	lea    0x118(%rsp),%rcx
 1066821:	00 
 1066822:	48 8d 3d b7 e7 01 00 	lea    0x1e7b7(%rip),%rdi        # 1084fe0 <core_durable_error.verbs+0x6090>
 1066829:	e9 23 02 00 00       	jmp    1066a51 <my.interpreter::evaluate+0x1e01>
 106682e:	48 8b 5c 24 70       	mov    0x70(%rsp),%rbx
 1066833:	48 8b 4c 24 78       	mov    0x78(%rsp),%rcx
 1066838:	48 8d 3d 31 e8 01 00 	lea    0x1e831(%rip),%rdi        # 1085070 <core_durable_error.verbs+0x6120>
 106683f:	e8 3c 00 ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066844:	48 8d 3d f5 b7 01 00 	lea    0x1b7f5(%rip),%rdi        # 1082040 <core_durable_error.verbs+0x30f0>
 106684b:	e8 30 00 ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066850:	b8 01 00 00 00       	mov    $0x1,%eax
 1066855:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 106685b:	e9 4b f4 ff ff       	jmp    1065cab <my.interpreter::evaluate+0x105b>
 1066860:	c5 fa 6f 44 24 70    	vmovdqu 0x70(%rsp),%xmm0
 1066866:	c5 f9 7f 44 24 40    	vmovdqa %xmm0,0x40(%rsp)
 106686c:	48 8d 3d 3d ea 01 00 	lea    0x1ea3d(%rip),%rdi        # 10852b0 <core_durable_error.verbs+0x6360>
 1066873:	e8 08 00 ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066878:	e9 82 01 00 00       	jmp    10669ff <my.interpreter::evaluate+0x1daf>
 106687d:	48 8b 5c 24 70       	mov    0x70(%rsp),%rbx
 1066882:	48 8b 4c 24 78       	mov    0x78(%rsp),%rcx
 1066887:	48 8d 3d f2 e3 01 00 	lea    0x1e3f2(%rip),%rdi        # 1084c80 <core_durable_error.verbs+0x5d30>
 106688e:	e8 ed ff fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066893:	e9 68 03 00 00       	jmp    1066c00 <my.interpreter::evaluate+0x1fb0>
 1066898:	4d 89 de             	mov    %r11,%r14
 106689b:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 10668a0:	48 8b 44 24 70       	mov    0x70(%rsp),%rax
 10668a5:	48 8b 54 24 78       	mov    0x78(%rsp),%rdx
 10668aa:	48 8d 3d ef e4 01 00 	lea    0x1e4ef(%rip),%rdi        # 1084da0 <core_durable_error.verbs+0x5e50>
 10668b1:	e9 04 01 00 00       	jmp    10669ba <my.interpreter::evaluate+0x1d6a>
 10668b6:	48 8d 3d 33 e9 01 00 	lea    0x1e933(%rip),%rdi        # 10851f0 <core_durable_error.verbs+0x62a0>
 10668bd:	c5 f9 10 44 24 70    	vmovupd 0x70(%rsp),%xmm0
 10668c3:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 10668c9:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 10668ce:	e8 ad ff fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 10668d3:	48 8d 3d c6 b7 01 00 	lea    0x1b7c6(%rip),%rdi        # 10820a0 <core_durable_error.verbs+0x3150>
 10668da:	e8 a1 ff fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 10668df:	b8 01 00 00 00       	mov    $0x1,%eax
 10668e4:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 10668ea:	e9 ac f7 ff ff       	jmp    106609b <my.interpreter::evaluate+0x144b>
 10668ef:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 10668f5:	48 8b 44 24 70       	mov    0x70(%rsp),%rax
 10668fa:	4c 8b 7c 24 78       	mov    0x78(%rsp),%r15
 10668ff:	48 8d 3d 0a ed 01 00 	lea    0x1ed0a(%rip),%rdi        # 1085610 <core_durable_error.verbs+0x66c0>
 1066906:	e8 75 ff fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 106690b:	e9 70 01 00 00       	jmp    1066a80 <my.interpreter::evaluate+0x1e30>
 1066910:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1066915:	48 89 de             	mov    %rbx,%rsi
 1066918:	e8 13 30 00 00       	call   1069930 <my.heap::string_chars>
 106691d:	48 89 c3             	mov    %rax,%rbx
 1066920:	48 8d 3d 39 bd fa ff 	lea    -0x542c7(%rip),%rdi        # 1012660 <core_number_pairs+0xb400>
 1066927:	48 89 c6             	mov    %rax,%rsi
 106692a:	e8 d1 81 fc ff       	call   102eb00 <myl_core_bytes_concat>
 106692f:	49 89 c4             	mov    %rax,%r12
 1066932:	48 89 df             	mov    %rbx,%rdi
 1066935:	e8 c6 cd fb ff       	call   1023700 <myl_core_drop_owned>
 106693a:	48 8d 35 1f b7 fa ff 	lea    -0x548e1(%rip),%rsi        # 1012060 <core_number_pairs+0xae00>
 1066941:	4c 89 e7             	mov    %r12,%rdi
 1066944:	e8 b7 81 fc ff       	call   102eb00 <myl_core_bytes_concat>
 1066949:	49 89 c7             	mov    %rax,%r15
 106694c:	4c 89 e7             	mov    %r12,%rdi
 106694f:	e8 ac cd fb ff       	call   1023700 <myl_core_drop_owned>
 1066954:	4c 89 ff             	mov    %r15,%rdi
 1066957:	e8 24 d6 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 106695c:	48 89 c3             	mov    %rax,%rbx
 106695f:	4c 89 ff             	mov    %r15,%rdi
 1066962:	e8 99 cd fb ff       	call   1023700 <myl_core_drop_owned>
 1066967:	48 8d 3d 12 ec 01 00 	lea    0x1ec12(%rip),%rdi        # 1085580 <core_durable_error.verbs+0x6630>
 106696e:	e8 cd fe fe ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066973:	48 8d 3d 86 b7 01 00 	lea    0x1b786(%rip),%rdi        # 1082100 <core_durable_error.verbs+0x31b0>
 106697a:	e8 01 ff fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 106697f:	b8 01 00 00 00       	mov    $0x1,%eax
 1066984:	48 8b 94 24 28 02 00 	mov    0x228(%rsp),%rdx
 106698b:	00 
 106698c:	48 8b bc 24 38 02 00 	mov    0x238(%rsp),%rdi
 1066993:	00 
 1066994:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 1066999:	e9 48 f1 ff ff       	jmp    1065ae6 <my.interpreter::evaluate+0xe96>
 106699e:	4c 89 5c 24 10       	mov    %r11,0x10(%rsp)
 10669a3:	48 8b 84 24 a8 00 00 	mov    0xa8(%rsp),%rax
 10669aa:	00 
 10669ab:	48 8b 94 24 b0 00 00 	mov    0xb0(%rsp),%rdx
 10669b2:	00 
 10669b3:	48 8d 3d 16 e4 01 00 	lea    0x1e416(%rip),%rdi        # 1084dd0 <core_durable_error.verbs+0x5e80>
 10669ba:	e8 c1 fe fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 10669bf:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 10669c4:	48 8d 3d 15 b6 01 00 	lea    0x1b615(%rip),%rdi        # 1081fe0 <core_durable_error.verbs+0x3090>
 10669cb:	e8 b0 fe fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 10669d0:	b9 01 00 00 00       	mov    $0x1,%ecx
 10669d5:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 10669da:	e9 0a fd ff ff       	jmp    10666e9 <my.interpreter::evaluate+0x1a99>
 10669df:	c5 fa 6f 84 24 a8 00 	vmovdqu 0xa8(%rsp),%xmm0
 10669e6:	00 00 
 10669e8:	c5 f9 7f 44 24 40    	vmovdqa %xmm0,0x40(%rsp)
 10669ee:	48 8d 3d 1b e9 01 00 	lea    0x1e91b(%rip),%rdi        # 1085310 <core_durable_error.verbs+0x63c0>
 10669f5:	e8 86 fe fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 10669fa:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 10669ff:	48 8d 3d ca b6 01 00 	lea    0x1b6ca(%rip),%rdi        # 10820d0 <core_durable_error.verbs+0x3180>
 1066a06:	e8 75 fe fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066a0b:	b8 01 00 00 00       	mov    $0x1,%eax
 1066a10:	c5 f9 28 44 24 40    	vmovapd 0x40(%rsp),%xmm0
 1066a16:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1066a1a:	c5 f9 11 45 08       	vmovupd %xmm0,0x8(%rbp)
 1066a1f:	48 89 5d 18          	mov    %rbx,0x18(%rbp)
 1066a23:	4c 89 75 20          	mov    %r14,0x20(%rbp)
 1066a27:	48 89 4d 28          	mov    %rcx,0x28(%rbp)
 1066a2b:	e9 25 05 00 00       	jmp    1066f55 <my.interpreter::evaluate+0x2305>
 1066a30:	48 89 7c 24 30       	mov    %rdi,0x30(%rsp)
 1066a35:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
 1066a3a:	48 8d 3d cf e5 01 00 	lea    0x1e5cf(%rip),%rdi        # 1085010 <core_durable_error.verbs+0x60c0>
 1066a41:	48 8d 84 24 90 01 00 	lea    0x190(%rsp),%rax
 1066a48:	00 
 1066a49:	48 8d 8c 24 98 01 00 	lea    0x198(%rsp),%rcx
 1066a50:	00 
 1066a51:	4c 8b 20             	mov    (%rax),%r12
 1066a54:	4c 8b 01             	mov    (%rcx),%r8
 1066a57:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1066a5c:	e9 bc 04 00 00       	jmp    1066f1d <my.interpreter::evaluate+0x22cd>
 1066a61:	e8 1a d5 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066a66:	48 8d 3d 03 ec 01 00 	lea    0x1ec03(%rip),%rdi        # 1085670 <core_durable_error.verbs+0x6720>
 1066a6d:	eb 0c                	jmp    1066a7b <my.interpreter::evaluate+0x1e2b>
 1066a6f:	e8 0c d5 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066a74:	48 8d 3d 25 ec 01 00 	lea    0x1ec25(%rip),%rdi        # 10856a0 <core_durable_error.verbs+0x6750>
 1066a7b:	e8 c0 fd fe ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066a80:	48 8d 3d a9 b6 01 00 	lea    0x1b6a9(%rip),%rdi        # 1082130 <core_durable_error.verbs+0x31e0>
 1066a87:	e8 f4 fd fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066a8c:	b9 01 00 00 00       	mov    $0x1,%ecx
 1066a91:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 1066a97:	e9 db f9 ff ff       	jmp    1066477 <my.interpreter::evaluate+0x1827>
 1066a9c:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 1066aa1:	4c 89 e6             	mov    %r12,%rsi
 1066aa4:	e8 87 2e 00 00       	call   1069930 <my.heap::string_chars>
 1066aa9:	48 89 c3             	mov    %rax,%rbx
 1066aac:	48 8d 3d ad bb fa ff 	lea    -0x54453(%rip),%rdi        # 1012660 <core_number_pairs+0xb400>
 1066ab3:	48 89 c6             	mov    %rax,%rsi
 1066ab6:	e8 45 80 fc ff       	call   102eb00 <myl_core_bytes_concat>
 1066abb:	49 89 c6             	mov    %rax,%r14
 1066abe:	48 89 df             	mov    %rbx,%rdi
 1066ac1:	e8 3a cc fb ff       	call   1023700 <myl_core_drop_owned>
 1066ac6:	48 8d 35 93 b5 fa ff 	lea    -0x54a6d(%rip),%rsi        # 1012060 <core_number_pairs+0xae00>
 1066acd:	4c 89 f7             	mov    %r14,%rdi
 1066ad0:	e8 2b 80 fc ff       	call   102eb00 <myl_core_bytes_concat>
 1066ad5:	49 89 c5             	mov    %rax,%r13
 1066ad8:	4c 89 f7             	mov    %r14,%rdi
 1066adb:	e8 20 cc fb ff       	call   1023700 <myl_core_drop_owned>
 1066ae0:	4c 89 ef             	mov    %r13,%rdi
 1066ae3:	e8 98 d4 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066ae8:	48 89 c3             	mov    %rax,%rbx
 1066aeb:	4c 89 ef             	mov    %r13,%rdi
 1066aee:	e8 0d cc fb ff       	call   1023700 <myl_core_drop_owned>
 1066af3:	48 8d 3d d6 e5 01 00 	lea    0x1e5d6(%rip),%rdi        # 10850d0 <core_durable_error.verbs+0x6180>
 1066afa:	e8 41 fd fe ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066aff:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1066b04:	4c 8b 7c 24 28       	mov    0x28(%rsp),%r15
 1066b09:	e9 74 fa ff ff       	jmp    1066582 <my.interpreter::evaluate+0x1932>
 1066b0e:	4c 89 f7             	mov    %r14,%rdi
 1066b11:	48 89 de             	mov    %rbx,%rsi
 1066b14:	e8 17 2e 00 00       	call   1069930 <my.heap::string_chars>
 1066b19:	48 89 c3             	mov    %rax,%rbx
 1066b1c:	48 8d 3d fd b4 fa ff 	lea    -0x54b03(%rip),%rdi        # 1012020 <core_number_pairs+0xadc0>
 1066b23:	48 89 c6             	mov    %rax,%rsi
 1066b26:	e8 d5 7f fc ff       	call   102eb00 <myl_core_bytes_concat>
 1066b2b:	49 89 c4             	mov    %rax,%r12
 1066b2e:	48 89 df             	mov    %rbx,%rdi
 1066b31:	e8 ca cb fb ff       	call   1023700 <myl_core_drop_owned>
 1066b36:	48 8d 35 23 b5 fa ff 	lea    -0x54add(%rip),%rsi        # 1012060 <core_number_pairs+0xae00>
 1066b3d:	4c 89 e7             	mov    %r12,%rdi
 1066b40:	e8 bb 7f fc ff       	call   102eb00 <myl_core_bytes_concat>
 1066b45:	49 89 c7             	mov    %rax,%r15
 1066b48:	4c 89 e7             	mov    %r12,%rdi
 1066b4b:	e8 b0 cb fb ff       	call   1023700 <myl_core_drop_owned>
 1066b50:	4c 89 ff             	mov    %r15,%rdi
 1066b53:	e8 28 d4 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066b58:	48 89 c3             	mov    %rax,%rbx
 1066b5b:	4c 89 ff             	mov    %r15,%rdi
 1066b5e:	e8 9d cb fb ff       	call   1023700 <myl_core_drop_owned>
 1066b63:	48 8d 3d c6 eb 01 00 	lea    0x1ebc6(%rip),%rdi        # 1085730 <core_durable_error.verbs+0x67e0>
 1066b6a:	e8 d1 fc fe ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066b6f:	48 8d 3d ea b5 01 00 	lea    0x1b5ea(%rip),%rdi        # 1082160 <core_durable_error.verbs+0x3210>
 1066b76:	e8 05 fd fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066b7b:	b8 01 00 00 00       	mov    $0x1,%eax
 1066b80:	4c 8b 9c 24 28 02 00 	mov    0x228(%rsp),%r11
 1066b87:	00 
 1066b88:	4c 8b b4 24 38 02 00 	mov    0x238(%rsp),%r14
 1066b8f:	00 
 1066b90:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 1066b95:	e9 bf f1 ff ff       	jmp    1065d59 <my.interpreter::evaluate+0x1109>
 1066b9a:	4c 89 ef             	mov    %r13,%rdi
 1066b9d:	4c 89 e6             	mov    %r12,%rsi
 1066ba0:	e8 8b 2d 00 00       	call   1069930 <my.heap::string_chars>
 1066ba5:	48 89 c3             	mov    %rax,%rbx
 1066ba8:	48 8d 3d 71 b4 fa ff 	lea    -0x54b8f(%rip),%rdi        # 1012020 <core_number_pairs+0xadc0>
 1066baf:	48 89 c6             	mov    %rax,%rsi
 1066bb2:	e8 49 7f fc ff       	call   102eb00 <myl_core_bytes_concat>
 1066bb7:	49 89 c4             	mov    %rax,%r12
 1066bba:	48 89 df             	mov    %rbx,%rdi
 1066bbd:	e8 3e cb fb ff       	call   1023700 <myl_core_drop_owned>
 1066bc2:	48 8d 35 97 b4 fa ff 	lea    -0x54b69(%rip),%rsi        # 1012060 <core_number_pairs+0xae00>
 1066bc9:	4c 89 e7             	mov    %r12,%rdi
 1066bcc:	e8 2f 7f fc ff       	call   102eb00 <myl_core_bytes_concat>
 1066bd1:	49 89 c7             	mov    %rax,%r15
 1066bd4:	4c 89 e7             	mov    %r12,%rdi
 1066bd7:	e8 24 cb fb ff       	call   1023700 <myl_core_drop_owned>
 1066bdc:	4c 89 ff             	mov    %r15,%rdi
 1066bdf:	e8 9c d3 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066be4:	48 89 c3             	mov    %rax,%rbx
 1066be7:	4c 89 ff             	mov    %r15,%rdi
 1066bea:	e8 11 cb fb ff       	call   1023700 <myl_core_drop_owned>
 1066bef:	48 8d 3d ba e0 01 00 	lea    0x1e0ba(%rip),%rdi        # 1084cb0 <core_durable_error.verbs+0x5d60>
 1066bf6:	e8 45 fc fe ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066bfb:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 1066c00:	48 8d 3d a9 b3 01 00 	lea    0x1b3a9(%rip),%rdi        # 1081fb0 <core_durable_error.verbs+0x3060>
 1066c07:	e8 74 fc fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066c0c:	b8 01 00 00 00       	mov    $0x1,%eax
 1066c11:	e9 3d f4 ff ff       	jmp    1066053 <my.interpreter::evaluate+0x1403>
 1066c16:	64 48 8b 1c 25 d8 fe 	mov    %fs:0xfffffffffffffed8,%rbx
 1066c1d:	ff ff 
 1066c1f:	48 85 db             	test   %rbx,%rbx
 1066c22:	0f 84 ec 08 00 00    	je     1067514 <my.interpreter::evaluate+0x28c4>
 1066c28:	48 8b 03             	mov    (%rbx),%rax
 1066c2b:	64 48 89 04 25 d8 fe 	mov    %rax,%fs:0xfffffffffffffed8
 1066c32:	ff ff 
 1066c34:	c7 03 00 00 00 03    	movl   $0x3000000,(%rbx)
 1066c3a:	48 c7 43 08 00 00 00 	movq   $0x0,0x8(%rbx)
 1066c41:	00 
 1066c42:	48 c7 43 10 08 00 00 	movq   $0x8,0x10(%rbx)
 1066c49:	00 
 1066c4a:	48 8d 05 77 cf fa ff 	lea    -0x53089(%rip),%rax        # 1013bc8 <core_number_pairs+0xc968>
 1066c51:	48 89 43 18          	mov    %rax,0x18(%rbx)
 1066c55:	31 c0                	xor    %eax,%eax
 1066c57:	48 8d 0d 42 b2 fa ff 	lea    -0x54dbe(%rip),%rcx        # 1011ea0 <core_number_pairs+0xac40>
 1066c5e:	48 89 4c c3 20       	mov    %rcx,0x20(%rbx,%rax,8)
 1066c63:	48 ff c0             	inc    %rax
 1066c66:	48 89 43 08          	mov    %rax,0x8(%rbx)
 1066c6a:	48 89 d7             	mov    %rdx,%rdi
 1066c6d:	e8 0e 5a fd ff       	call   103c680 <myl_core_str_from_i64>
 1066c72:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1066c76:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 1066c7a:	48 39 d1             	cmp    %rdx,%rcx
 1066c7d:	0f 83 e2 08 00 00    	jae    1067565 <my.interpreter::evaluate+0x2915>
 1066c83:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066c88:	48 ff c1             	inc    %rcx
 1066c8b:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066c8f:	48 39 d1             	cmp    %rdx,%rcx
 1066c92:	0f 83 f6 08 00 00    	jae    106758e <my.interpreter::evaluate+0x293e>
 1066c98:	48 8d 05 41 b2 fa ff 	lea    -0x54dbf(%rip),%rax        # 1011ee0 <core_number_pairs+0xac80>
 1066c9f:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066ca4:	48 ff c1             	inc    %rcx
 1066ca7:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066cab:	4c 89 f7             	mov    %r14,%rdi
 1066cae:	e8 cd 59 fd ff       	call   103c680 <myl_core_str_from_i64>
 1066cb3:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1066cb7:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 1066cbb:	48 39 d1             	cmp    %rdx,%rcx
 1066cbe:	0f 83 e3 08 00 00    	jae    10675a7 <my.interpreter::evaluate+0x2957>
 1066cc4:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066cc9:	48 ff c1             	inc    %rcx
 1066ccc:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066cd0:	48 39 d1             	cmp    %rdx,%rcx
 1066cd3:	0f 83 f1 08 00 00    	jae    10675ca <my.interpreter::evaluate+0x297a>
 1066cd9:	48 8d 05 40 b2 fa ff 	lea    -0x54dc0(%rip),%rax        # 1011f20 <core_number_pairs+0xacc0>
 1066ce0:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066ce5:	48 ff c1             	inc    %rcx
 1066ce8:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066cec:	48 8d 3d 4d ad fa ff 	lea    -0x552b3(%rip),%rdi        # 1011a40 <core_number_pairs+0xa7e0>
 1066cf3:	48 89 de             	mov    %rbx,%rsi
 1066cf6:	e8 05 5d fc ff       	call   102ca00 <myl_core_str_join>
 1066cfb:	49 89 c4             	mov    %rax,%r12
 1066cfe:	48 89 df             	mov    %rbx,%rdi
 1066d01:	e8 fa c9 fb ff       	call   1023700 <myl_core_drop_owned>
 1066d06:	4c 89 e7             	mov    %r12,%rdi
 1066d09:	e8 32 80 fc ff       	call   102ed40 <myl_core_text_encode>
 1066d0e:	48 89 c3             	mov    %rax,%rbx
 1066d11:	4c 89 e7             	mov    %r12,%rdi
 1066d14:	e8 e7 c9 fb ff       	call   1023700 <myl_core_drop_owned>
 1066d19:	48 89 df             	mov    %rbx,%rdi
 1066d1c:	e8 5f d2 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066d21:	49 89 c4             	mov    %rax,%r12
 1066d24:	48 89 df             	mov    %rbx,%rdi
 1066d27:	e8 d4 c9 fb ff       	call   1023700 <myl_core_drop_owned>
 1066d2c:	48 8d 3d 1d 00 02 00 	lea    0x2001d(%rip),%rdi        # 1086d50 <core_durable_error.verbs+0x7e00>
 1066d33:	e8 08 fb fe ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066d38:	4d 89 ea             	mov    %r13,%r10
 1066d3b:	e9 a1 fa ff ff       	jmp    10667e1 <my.interpreter::evaluate+0x1b91>
 1066d40:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 1066d45:	4c 8b 84 24 48 01 00 	mov    0x148(%rsp),%r8
 1066d4c:	00 
 1066d4d:	48 8d 3d 6c ff 01 00 	lea    0x1ff6c(%rip),%rdi        # 1086cc0 <core_durable_error.verbs+0x7d70>
 1066d54:	e8 27 fb fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066d59:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1066d5e:	4d 89 d4             	mov    %r10,%r12
 1066d61:	4d 89 fa             	mov    %r15,%r10
 1066d64:	e9 ad 01 00 00       	jmp    1066f16 <my.interpreter::evaluate+0x22c6>
 1066d69:	4c 89 6c 24 30       	mov    %r13,0x30(%rsp)
 1066d6e:	4c 89 4c 24 20       	mov    %r9,0x20(%rsp)
 1066d73:	48 8d 3d 76 ff 01 00 	lea    0x1ff76(%rip),%rdi        # 1086cf0 <core_durable_error.verbs+0x7da0>
 1066d7a:	e8 01 fb fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066d7f:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1066d84:	e9 8d 01 00 00       	jmp    1066f16 <my.interpreter::evaluate+0x22c6>
 1066d89:	48 8d 3d 90 b3 fa ff 	lea    -0x54c70(%rip),%rdi        # 1012120 <core_number_pairs+0xaec0>
 1066d90:	e8 eb d1 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066d95:	48 8d 3d 94 e0 01 00 	lea    0x1e094(%rip),%rdi        # 1084e30 <core_durable_error.verbs+0x5ee0>
 1066d9c:	e8 9f fa fe ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066da1:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1066da6:	4d 89 fa             	mov    %r15,%r10
 1066da9:	eb 22                	jmp    1066dcd <my.interpreter::evaluate+0x217d>
 1066dab:	48 8d 3d ae b3 fa ff 	lea    -0x54c52(%rip),%rdi        # 1012160 <core_number_pairs+0xaf00>
 1066db2:	e8 c9 d1 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066db7:	48 8d 3d 42 e0 01 00 	lea    0x1e042(%rip),%rdi        # 1084e00 <core_durable_error.verbs+0x5eb0>
 1066dbe:	e8 7d fa fe ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066dc3:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1066dc8:	4c 8b 54 24 40       	mov    0x40(%rsp),%r10
 1066dcd:	48 8b 54 24 20       	mov    0x20(%rsp),%rdx
 1066dd2:	e9 ed fb ff ff       	jmp    10669c4 <my.interpreter::evaluate+0x1d74>
 1066dd7:	64 48 8b 1c 25 d0 fe 	mov    %fs:0xfffffffffffffed0,%rbx
 1066dde:	ff ff 
 1066de0:	48 85 db             	test   %rbx,%rbx
 1066de3:	0f 84 fa 07 00 00    	je     10675e3 <my.interpreter::evaluate+0x2993>
 1066de9:	48 8b 03             	mov    (%rbx),%rax
 1066dec:	64 48 89 04 25 d0 fe 	mov    %rax,%fs:0xfffffffffffffed0
 1066df3:	ff ff 
 1066df5:	c7 03 00 00 00 02    	movl   $0x2000000,(%rbx)
 1066dfb:	48 c7 43 08 00 00 00 	movq   $0x0,0x8(%rbx)
 1066e02:	00 
 1066e03:	48 c7 43 10 04 00 00 	movq   $0x4,0x10(%rbx)
 1066e0a:	00 
 1066e0b:	48 8d 05 b6 cd fa ff 	lea    -0x5324a(%rip),%rax        # 1013bc8 <core_number_pairs+0xc968>
 1066e12:	48 89 43 18          	mov    %rax,0x18(%rbx)
 1066e16:	31 c0                	xor    %eax,%eax
 1066e18:	48 8d 0d 81 cb fa ff 	lea    -0x5347f(%rip),%rcx        # 10139a0 <core_number_pairs+0xc740>
 1066e1f:	48 89 4c c3 20       	mov    %rcx,0x20(%rbx,%rax,8)
 1066e24:	48 ff c0             	inc    %rax
 1066e27:	48 89 43 08          	mov    %rax,0x8(%rbx)
 1066e2b:	4c 89 f7             	mov    %r14,%rdi
 1066e2e:	e8 4d 58 fd ff       	call   103c680 <myl_core_str_from_i64>
 1066e33:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1066e37:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 1066e3b:	48 39 d1             	cmp    %rdx,%rcx
 1066e3e:	0f 83 e9 07 00 00    	jae    106762d <my.interpreter::evaluate+0x29dd>
 1066e44:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066e49:	48 ff c1             	inc    %rcx
 1066e4c:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066e50:	48 39 d1             	cmp    %rdx,%rcx
 1066e53:	0f 83 f7 07 00 00    	jae    1067650 <my.interpreter::evaluate+0x2a00>
 1066e59:	48 8d 05 c0 b0 fa ff 	lea    -0x54f40(%rip),%rax        # 1011f20 <core_number_pairs+0xacc0>
 1066e60:	48 89 44 cb 20       	mov    %rax,0x20(%rbx,%rcx,8)
 1066e65:	48 ff c1             	inc    %rcx
 1066e68:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
 1066e6c:	48 8d 3d cd ab fa ff 	lea    -0x55433(%rip),%rdi        # 1011a40 <core_number_pairs+0xa7e0>
 1066e73:	48 89 de             	mov    %rbx,%rsi
 1066e76:	e8 85 5b fc ff       	call   102ca00 <myl_core_str_join>
 1066e7b:	49 89 c4             	mov    %rax,%r12
 1066e7e:	48 89 df             	mov    %rbx,%rdi
 1066e81:	e8 7a c8 fb ff       	call   1023700 <myl_core_drop_owned>
 1066e86:	4c 89 e7             	mov    %r12,%rdi
 1066e89:	e8 b2 7e fc ff       	call   102ed40 <myl_core_text_encode>
 1066e8e:	48 89 c3             	mov    %rax,%rbx
 1066e91:	4c 89 e7             	mov    %r12,%rdi
 1066e94:	e8 67 c8 fb ff       	call   1023700 <myl_core_drop_owned>
 1066e99:	48 89 df             	mov    %rbx,%rdi
 1066e9c:	e8 df d0 fb ff       	call   1023f80 <myl_core_owned_octets_copy>
 1066ea1:	49 89 c4             	mov    %rax,%r12
 1066ea4:	48 89 df             	mov    %rbx,%rdi
 1066ea7:	e8 54 c8 fb ff       	call   1023700 <myl_core_drop_owned>
 1066eac:	48 8d 3d cd 13 02 00 	lea    0x213cd(%rip),%rdi        # 1088280 <core_durable_error.verbs+0x9330>
 1066eb3:	e8 88 f9 fe ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 1066eb8:	4c 8b 94 24 98 00 00 	mov    0x98(%rsp),%r10
 1066ebf:	00 
 1066ec0:	4c 8b 44 24 58       	mov    0x58(%rsp),%r8
 1066ec5:	eb 43                	jmp    1066f0a <my.interpreter::evaluate+0x22ba>
 1066ec7:	4c 8b 84 24 60 01 00 	mov    0x160(%rsp),%r8
 1066ece:	00 
 1066ecf:	48 8d 3d 4a 13 02 00 	lea    0x2134a(%rip),%rdi        # 1088220 <core_durable_error.verbs+0x92d0>
 1066ed6:	e8 a5 f9 fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066edb:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1066ee0:	4c 8b 94 24 98 00 00 	mov    0x98(%rsp),%r10
 1066ee7:	00 
 1066ee8:	eb 20                	jmp    1066f0a <my.interpreter::evaluate+0x22ba>
 1066eea:	4c 89 4c 24 20       	mov    %r9,0x20(%rsp)
 1066eef:	4c 8b 64 24 70       	mov    0x70(%rsp),%r12
 1066ef4:	4c 8b 44 24 78       	mov    0x78(%rsp),%r8
 1066ef9:	48 8d 3d 50 13 02 00 	lea    0x21350(%rip),%rdi        # 1088250 <core_durable_error.verbs+0x9300>
 1066f00:	e8 7b f9 fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066f05:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1066f0a:	48 8d 3d 0f fe 01 00 	lea    0x1fe0f(%rip),%rdi        # 1086d20 <core_durable_error.verbs+0x7dd0>
 1066f11:	e8 6a f9 fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066f16:	48 8d 3d 23 e1 01 00 	lea    0x1e123(%rip),%rdi        # 1085040 <core_durable_error.verbs+0x60f0>
 1066f1d:	e8 5e f9 fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066f22:	48 8d 3d e7 b0 01 00 	lea    0x1b0e7(%rip),%rdi        # 1082010 <core_durable_error.verbs+0x30c0>
 1066f29:	e8 52 f9 fe ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 1066f2e:	b8 01 00 00 00       	mov    $0x1,%eax
 1066f33:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 1066f38:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 1066f3d:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1066f41:	4c 89 65 08          	mov    %r12,0x8(%rbp)
 1066f45:	4c 89 45 10          	mov    %r8,0x10(%rbp)
 1066f49:	4c 89 55 18          	mov    %r10,0x18(%rbp)
 1066f4d:	4c 89 6d 20          	mov    %r13,0x20(%rbp)
 1066f51:	4c 89 4d 28          	mov    %r9,0x28(%rbp)
 1066f55:	48 89 e8             	mov    %rbp,%rax
 1066f58:	48 81 c4 e8 01 00 00 	add    $0x1e8,%rsp
 1066f5f:	5b                   	pop    %rbx
 1066f60:	41 5c                	pop    %r12
 1066f62:	41 5d                	pop    %r13
 1066f64:	41 5e                	pop    %r14
 1066f66:	41 5f                	pop    %r15
 1066f68:	5d                   	pop    %rbp
 1066f69:	c3                   	ret
 1066f6a:	48 89 f0             	mov    %rsi,%rax
 1066f6d:	48 c1 f8 3f          	sar    $0x3f,%rax
 1066f71:	48 21 d0             	and    %rdx,%rax
 1066f74:	48 01 f0             	add    %rsi,%rax
 1066f77:	48 39 d0             	cmp    %rdx,%rax
 1066f7a:	0f 82 05 dd ff ff    	jb     1064c85 <my.interpreter::evaluate+0x35>
 1066f80:	48 8d 3d f9 af 01 00 	lea    0x1aff9(%rip),%rdi        # 1081f80 <core_durable_error.verbs+0x3030>
 1066f87:	e8 f4 d4 fb ff       	call   1024480 <myl_core_trap>
 1066f8c:	48 89 f1             	mov    %rsi,%rcx
 1066f8f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066f93:	48 21 d1             	and    %rdx,%rcx
 1066f96:	48 01 f1             	add    %rsi,%rcx
 1066f99:	48 39 d1             	cmp    %rdx,%rcx
 1066f9c:	0f 82 97 e5 ff ff    	jb     1065539 <my.interpreter::evaluate+0x8e9>
 1066fa2:	48 8d 3d e7 b1 01 00 	lea    0x1b1e7(%rip),%rdi        # 1082190 <core_durable_error.verbs+0x3240>
 1066fa9:	e8 d2 d4 fb ff       	call   1024480 <myl_core_trap>
 1066fae:	48 89 f7             	mov    %rsi,%rdi
 1066fb1:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066fb5:	48 21 d7             	and    %rdx,%rdi
 1066fb8:	48 01 f7             	add    %rsi,%rdi
 1066fbb:	48 39 d7             	cmp    %rdx,%rdi
 1066fbe:	0f 82 15 e9 ff ff    	jb     10658d9 <my.interpreter::evaluate+0xc89>
 1066fc4:	48 8d 3d 25 af 01 00 	lea    0x1af25(%rip),%rdi        # 1081ef0 <core_durable_error.verbs+0x2fa0>
 1066fcb:	e8 b0 d4 fb ff       	call   1024480 <myl_core_trap>
 1066fd0:	49 89 c8             	mov    %rcx,%r8
 1066fd3:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066fd7:	49 21 d0             	and    %rdx,%r8
 1066fda:	49 01 c8             	add    %rcx,%r8
 1066fdd:	49 39 d0             	cmp    %rdx,%r8
 1066fe0:	0f 82 8b e9 ff ff    	jb     1065971 <my.interpreter::evaluate+0xd21>
 1066fe6:	48 8d 3d 03 af 01 00 	lea    0x1af03(%rip),%rdi        # 1081ef0 <core_durable_error.verbs+0x2fa0>
 1066fed:	48 89 ce             	mov    %rcx,%rsi
 1066ff0:	e8 8b d4 fb ff       	call   1024480 <myl_core_trap>
 1066ff5:	48 89 c6             	mov    %rax,%rsi
 1066ff8:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066ffc:	48 21 d6             	and    %rdx,%rsi
 1066fff:	48 01 c6             	add    %rax,%rsi
 1067002:	48 39 d6             	cmp    %rdx,%rsi
 1067005:	0f 82 f8 e8 ff ff    	jb     1065903 <my.interpreter::evaluate+0xcb3>
 106700b:	48 8d 3d 3e af 01 00 	lea    0x1af3e(%rip),%rdi        # 1081f50 <core_durable_error.verbs+0x3000>
 1067012:	48 89 c6             	mov    %rax,%rsi
 1067015:	e8 66 d4 fb ff       	call   1024480 <myl_core_trap>
 106701a:	48 89 f1             	mov    %rsi,%rcx
 106701d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067021:	48 21 d1             	and    %rdx,%rcx
 1067024:	48 01 f1             	add    %rsi,%rcx
 1067027:	48 39 d1             	cmp    %rdx,%rcx
 106702a:	0f 82 f8 e8 ff ff    	jb     1065928 <my.interpreter::evaluate+0xcd8>
 1067030:	48 8d 3d b9 b1 01 00 	lea    0x1b1b9(%rip),%rdi        # 10821f0 <core_durable_error.verbs+0x32a0>
 1067037:	e8 44 d4 fb ff       	call   1024480 <myl_core_trap>
 106703c:	48 8d 3d 0d af 01 00 	lea    0x1af0d(%rip),%rdi        # 1081f50 <core_durable_error.verbs+0x3000>
 1067043:	31 f6                	xor    %esi,%esi
 1067045:	31 d2                	xor    %edx,%edx
 1067047:	e8 34 d4 fb ff       	call   1024480 <myl_core_trap>
 106704c:	48 89 f1             	mov    %rsi,%rcx
 106704f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067053:	48 21 d1             	and    %rdx,%rcx
 1067056:	48 01 f1             	add    %rsi,%rcx
 1067059:	48 39 d1             	cmp    %rdx,%rcx
 106705c:	0f 82 ac e9 ff ff    	jb     1065a0e <my.interpreter::evaluate+0xdbe>
 1067062:	48 8d 3d 87 ae 01 00 	lea    0x1ae87(%rip),%rdi        # 1081ef0 <core_durable_error.verbs+0x2fa0>
 1067069:	e8 12 d4 fb ff       	call   1024480 <myl_core_trap>
 106706e:	48 8d 3d db ae 01 00 	lea    0x1aedb(%rip),%rdi        # 1081f50 <core_durable_error.verbs+0x3000>
 1067075:	31 f6                	xor    %esi,%esi
 1067077:	31 d2                	xor    %edx,%edx
 1067079:	e8 02 d4 fb ff       	call   1024480 <myl_core_trap>
 106707e:	49 89 f5             	mov    %rsi,%r13
 1067081:	49 c1 fd 3f          	sar    $0x3f,%r13
 1067085:	49 21 d5             	and    %rdx,%r13
 1067088:	49 01 f5             	add    %rsi,%r13
 106708b:	49 39 d5             	cmp    %rdx,%r13
 106708e:	0f 82 ed df ff ff    	jb     1065081 <my.interpreter::evaluate+0x431>
 1067094:	48 8d 3d 95 e0 01 00 	lea    0x1e095(%rip),%rdi        # 1085130 <core_durable_error.verbs+0x61e0>
 106709b:	e8 e0 d3 fb ff       	call   1024480 <myl_core_trap>
 10670a0:	48 89 f7             	mov    %rsi,%rdi
 10670a3:	48 c1 ff 3f          	sar    $0x3f,%rdi
 10670a7:	48 21 d7             	and    %rdx,%rdi
 10670aa:	48 01 f7             	add    %rsi,%rdi
 10670ad:	48 39 d7             	cmp    %rdx,%rdi
 10670b0:	0f 82 26 e1 ff ff    	jb     10651dc <my.interpreter::evaluate+0x58c>
 10670b6:	48 8d 3d b3 e2 01 00 	lea    0x1e2b3(%rip),%rdi        # 1085370 <core_durable_error.verbs+0x6420>
 10670bd:	e8 be d3 fb ff       	call   1024480 <myl_core_trap>
 10670c2:	48 89 f7             	mov    %rsi,%rdi
 10670c5:	48 c1 ff 3f          	sar    $0x3f,%rdi
 10670c9:	48 21 d7             	and    %rdx,%rdi
 10670cc:	48 01 f7             	add    %rsi,%rdi
 10670cf:	48 39 d7             	cmp    %rdx,%rdi
 10670d2:	0f 82 3f e5 ff ff    	jb     1065617 <my.interpreter::evaluate+0x9c7>
 10670d8:	48 8d 3d a1 e1 01 00 	lea    0x1e1a1(%rip),%rdi        # 1085280 <core_durable_error.verbs+0x6330>
 10670df:	e8 9c d3 fb ff       	call   1024480 <myl_core_trap>
 10670e4:	48 89 f7             	mov    %rsi,%rdi
 10670e7:	48 c1 ff 3f          	sar    $0x3f,%rdi
 10670eb:	48 21 d7             	and    %rdx,%rdi
 10670ee:	48 01 f7             	add    %rsi,%rdi
 10670f1:	48 39 d7             	cmp    %rdx,%rdi
 10670f4:	0f 82 53 e6 ff ff    	jb     106574d <my.interpreter::evaluate+0xafd>
 10670fa:	48 8d 3d ff e5 01 00 	lea    0x1e5ff(%rip),%rdi        # 1085700 <core_durable_error.verbs+0x67b0>
 1067101:	e8 7a d3 fb ff       	call   1024480 <myl_core_trap>
 1067106:	48 89 f7             	mov    %rsi,%rdi
 1067109:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106710d:	48 21 d7             	and    %rdx,%rdi
 1067110:	48 01 f7             	add    %rsi,%rdi
 1067113:	48 39 d7             	cmp    %rdx,%rdi
 1067116:	0f 82 93 e9 ff ff    	jb     1065aaf <my.interpreter::evaluate+0xe5f>
 106711c:	48 8d 3d 8d e4 01 00 	lea    0x1e48d(%rip),%rdi        # 10855b0 <core_durable_error.verbs+0x6660>
 1067123:	e8 58 d3 fb ff       	call   1024480 <myl_core_trap>
 1067128:	4c 89 e9             	mov    %r13,%rcx
 106712b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106712f:	48 21 d1             	and    %rdx,%rcx
 1067132:	4c 01 e9             	add    %r13,%rcx
 1067135:	48 39 d1             	cmp    %rdx,%rcx
 1067138:	0f 82 85 ec ff ff    	jb     1065dc3 <my.interpreter::evaluate+0x1173>
 106713e:	48 8d 3d 1b fb 01 00 	lea    0x1fb1b(%rip),%rdi        # 1086c60 <core_durable_error.verbs+0x7d10>
 1067145:	4c 89 ee             	mov    %r13,%rsi
 1067148:	e8 33 d3 fb ff       	call   1024480 <myl_core_trap>
 106714d:	48 89 d9             	mov    %rbx,%rcx
 1067150:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067154:	48 21 d1             	and    %rdx,%rcx
 1067157:	48 01 d9             	add    %rbx,%rcx
 106715a:	48 39 d1             	cmp    %rdx,%rcx
 106715d:	0f 82 4c df ff ff    	jb     10650af <my.interpreter::evaluate+0x45f>
 1067163:	48 8d 3d f6 c1 01 00 	lea    0x1c1f6(%rip),%rdi        # 1083360 <core_durable_error.verbs+0x4410>
 106716a:	48 89 de             	mov    %rbx,%rsi
 106716d:	e8 0e d3 fb ff       	call   1024480 <myl_core_trap>
 1067172:	48 89 f7             	mov    %rsi,%rdi
 1067175:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1067179:	48 21 d7             	and    %rdx,%rdi
 106717c:	48 01 f7             	add    %rsi,%rdi
 106717f:	48 39 d7             	cmp    %rdx,%rdi
 1067182:	0f 82 7b e0 ff ff    	jb     1065203 <my.interpreter::evaluate+0x5b3>
 1067188:	48 8d 3d d1 c1 01 00 	lea    0x1c1d1(%rip),%rdi        # 1083360 <core_durable_error.verbs+0x4410>
 106718f:	e8 ec d2 fb ff       	call   1024480 <myl_core_trap>
 1067194:	49 89 f0             	mov    %rsi,%r8
 1067197:	49 c1 f8 3f          	sar    $0x3f,%r8
 106719b:	49 21 d0             	and    %rdx,%r8
 106719e:	49 01 f0             	add    %rsi,%r8
 10671a1:	49 39 d0             	cmp    %rdx,%r8
 10671a4:	0f 82 03 e3 ff ff    	jb     10654ad <my.interpreter::evaluate+0x85d>
 10671aa:	48 8d 3d 0f dd 01 00 	lea    0x1dd0f(%rip),%rdi        # 1084ec0 <core_durable_error.verbs+0x5f70>
 10671b1:	e8 ca d2 fb ff       	call   1024480 <myl_core_trap>
 10671b6:	48 89 de             	mov    %rbx,%rsi
 10671b9:	48 c1 fe 3f          	sar    $0x3f,%rsi
 10671bd:	48 21 d6             	and    %rdx,%rsi
 10671c0:	48 01 de             	add    %rbx,%rsi
 10671c3:	48 39 d6             	cmp    %rdx,%rsi
 10671c6:	0f 82 fc e2 ff ff    	jb     10654c8 <my.interpreter::evaluate+0x878>
 10671cc:	48 8d 3d 7d dd 01 00 	lea    0x1dd7d(%rip),%rdi        # 1084f50 <core_durable_error.verbs+0x6000>
 10671d3:	48 89 de             	mov    %rbx,%rsi
 10671d6:	e8 a5 d2 fb ff       	call   1024480 <myl_core_trap>
 10671db:	48 89 de             	mov    %rbx,%rsi
 10671de:	48 c1 fe 3f          	sar    $0x3f,%rsi
 10671e2:	48 21 ce             	and    %rcx,%rsi
 10671e5:	48 01 de             	add    %rbx,%rsi
 10671e8:	48 39 ce             	cmp    %rcx,%rsi
 10671eb:	0f 82 c9 f4 ff ff    	jb     10666ba <my.interpreter::evaluate+0x1a6a>
 10671f1:	48 8d 3d 28 dd 01 00 	lea    0x1dd28(%rip),%rdi        # 1084f20 <core_durable_error.verbs+0x5fd0>
 10671f8:	48 89 de             	mov    %rbx,%rsi
 10671fb:	48 89 ca             	mov    %rcx,%rdx
 10671fe:	e8 7d d2 fb ff       	call   1024480 <myl_core_trap>
 1067203:	49 89 f0             	mov    %rsi,%r8
 1067206:	49 c1 f8 3f          	sar    $0x3f,%r8
 106720a:	49 21 c8             	and    %rcx,%r8
 106720d:	49 01 f0             	add    %rsi,%r8
 1067210:	49 39 c8             	cmp    %rcx,%r8
 1067213:	0f 82 b9 f4 ff ff    	jb     10666d2 <my.interpreter::evaluate+0x1a82>
 1067219:	48 8d 3d 90 dd 01 00 	lea    0x1dd90(%rip),%rdi        # 1084fb0 <core_durable_error.verbs+0x6060>
 1067220:	48 89 ca             	mov    %rcx,%rdx
 1067223:	e8 58 d2 fb ff       	call   1024480 <myl_core_trap>
 1067228:	4c 89 e1             	mov    %r12,%rcx
 106722b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106722f:	48 21 d1             	and    %rdx,%rcx
 1067232:	4c 01 e1             	add    %r12,%rcx
 1067235:	48 39 d1             	cmp    %rdx,%rcx
 1067238:	0f 82 b7 eb ff ff    	jb     1065df5 <my.interpreter::evaluate+0x11a5>
 106723e:	48 8d 3d fb f8 01 00 	lea    0x1f8fb(%rip),%rdi        # 1086b40 <core_durable_error.verbs+0x7bf0>
 1067245:	4c 89 e6             	mov    %r12,%rsi
 1067248:	e8 33 d2 fb ff       	call   1024480 <myl_core_trap>
 106724d:	48 89 f1             	mov    %rsi,%rcx
 1067250:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067254:	48 21 d1             	and    %rdx,%rcx
 1067257:	48 01 f1             	add    %rsi,%rcx
 106725a:	48 39 d1             	cmp    %rdx,%rcx
 106725d:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 1067262:	0f 82 49 e0 ff ff    	jb     10652b1 <my.interpreter::evaluate+0x661>
 1067268:	48 8d 3d 91 e1 01 00 	lea    0x1e191(%rip),%rdi        # 1085400 <core_durable_error.verbs+0x64b0>
 106726f:	e8 0c d2 fb ff       	call   1024480 <myl_core_trap>
 1067274:	49 89 f0             	mov    %rsi,%r8
 1067277:	49 c1 f8 3f          	sar    $0x3f,%r8
 106727b:	49 21 d0             	and    %rdx,%r8
 106727e:	49 01 f0             	add    %rsi,%r8
 1067281:	49 39 d0             	cmp    %rdx,%r8
 1067284:	0f 82 75 e0 ff ff    	jb     10652ff <my.interpreter::evaluate+0x6af>
 106728a:	48 8d 3d cf e1 01 00 	lea    0x1e1cf(%rip),%rdi        # 1085460 <core_durable_error.verbs+0x6510>
 1067291:	e8 ea d1 fb ff       	call   1024480 <myl_core_trap>
 1067296:	48 89 f0             	mov    %rsi,%rax
 1067299:	48 c1 f8 3f          	sar    $0x3f,%rax
 106729d:	48 21 d0             	and    %rdx,%rax
 10672a0:	48 01 f0             	add    %rsi,%rax
 10672a3:	48 39 d0             	cmp    %rdx,%rax
 10672a6:	0f 82 a5 e0 ff ff    	jb     1065351 <my.interpreter::evaluate+0x701>
 10672ac:	48 8d 3d 0d e2 01 00 	lea    0x1e20d(%rip),%rdi        # 10854c0 <core_durable_error.verbs+0x6570>
 10672b3:	e8 c8 d1 fb ff       	call   1024480 <myl_core_trap>
 10672b8:	48 89 c6             	mov    %rax,%rsi
 10672bb:	48 c1 fe 3f          	sar    $0x3f,%rsi
 10672bf:	48 21 d6             	and    %rdx,%rsi
 10672c2:	48 01 c6             	add    %rax,%rsi
 10672c5:	48 39 d6             	cmp    %rdx,%rsi
 10672c8:	0f 82 9b e0 ff ff    	jb     1065369 <my.interpreter::evaluate+0x719>
 10672ce:	48 8d 3d 4b e2 01 00 	lea    0x1e24b(%rip),%rdi        # 1085520 <core_durable_error.verbs+0x65d0>
 10672d5:	48 89 c6             	mov    %rax,%rsi
 10672d8:	e8 a3 d1 fb ff       	call   1024480 <myl_core_trap>
 10672dd:	48 89 c7             	mov    %rax,%rdi
 10672e0:	48 c1 ff 3f          	sar    $0x3f,%rdi
 10672e4:	48 21 d7             	and    %rdx,%rdi
 10672e7:	48 01 c7             	add    %rax,%rdi
 10672ea:	48 39 d7             	cmp    %rdx,%rdi
 10672ed:	0f 82 29 e8 ff ff    	jb     1065b1c <my.interpreter::evaluate+0xecc>
 10672f3:	48 8d 3d f6 ab 01 00 	lea    0x1abf6(%rip),%rdi        # 1081ef0 <core_durable_error.verbs+0x2fa0>
 10672fa:	48 89 c6             	mov    %rax,%rsi
 10672fd:	e8 7e d1 fb ff       	call   1024480 <myl_core_trap>
 1067302:	48 89 f1             	mov    %rsi,%rcx
 1067305:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067309:	48 21 d1             	and    %rdx,%rcx
 106730c:	48 01 f1             	add    %rsi,%rcx
 106730f:	48 39 d1             	cmp    %rdx,%rcx
 1067312:	0f 82 2e e8 ff ff    	jb     1065b46 <my.interpreter::evaluate+0xef6>
 1067318:	48 8d 3d 31 ac 01 00 	lea    0x1ac31(%rip),%rdi        # 1081f50 <core_durable_error.verbs+0x3000>
 106731f:	e8 5c d1 fb ff       	call   1024480 <myl_core_trap>
 1067324:	48 89 f1             	mov    %rsi,%rcx
 1067327:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106732b:	48 21 d1             	and    %rdx,%rcx
 106732e:	48 01 f1             	add    %rsi,%rcx
 1067331:	48 39 d1             	cmp    %rdx,%rcx
 1067334:	0f 82 31 e8 ff ff    	jb     1065b6b <my.interpreter::evaluate+0xf1b>
 106733a:	48 8d 3d 1f e4 01 00 	lea    0x1e41f(%rip),%rdi        # 1085760 <core_durable_error.verbs+0x6810>
 1067341:	e8 3a d1 fb ff       	call   1024480 <myl_core_trap>
 1067346:	49 89 c1             	mov    %rax,%r9
 1067349:	49 c1 f9 3f          	sar    $0x3f,%r9
 106734d:	49 21 d1             	and    %rdx,%r9
 1067350:	49 01 c1             	add    %rax,%r9
 1067353:	49 39 d1             	cmp    %rdx,%r9
 1067356:	0f 82 62 e8 ff ff    	jb     1065bbe <my.interpreter::evaluate+0xf6e>
 106735c:	48 8d 3d ad d9 01 00 	lea    0x1d9ad(%rip),%rdi        # 1084d10 <core_durable_error.verbs+0x5dc0>
 1067363:	48 89 c6             	mov    %rax,%rsi
 1067366:	e8 15 d1 fb ff       	call   1024480 <myl_core_trap>
 106736b:	48 89 f7             	mov    %rsi,%rdi
 106736e:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1067372:	48 21 d7             	and    %rdx,%rdi
 1067375:	48 01 f7             	add    %rsi,%rdi
 1067378:	48 39 d7             	cmp    %rdx,%rdi
 106737b:	0f 82 06 e9 ff ff    	jb     1065c87 <my.interpreter::evaluate+0x1037>
 1067381:	48 8d 3d 38 de 01 00 	lea    0x1de38(%rip),%rdi        # 10851c0 <core_durable_error.verbs+0x6270>
 1067388:	e8 f3 d0 fb ff       	call   1024480 <myl_core_trap>
 106738d:	49 89 f0             	mov    %rsi,%r8
 1067390:	49 c1 f8 3f          	sar    $0x3f,%r8
 1067394:	49 21 c0             	and    %rax,%r8
 1067397:	49 01 f0             	add    %rsi,%r8
 106739a:	49 39 c0             	cmp    %rax,%r8
 106739d:	0f 82 80 e9 ff ff    	jb     1065d23 <my.interpreter::evaluate+0x10d3>
 10673a3:	48 8d 3d 16 e4 01 00 	lea    0x1e416(%rip),%rdi        # 10857c0 <core_durable_error.verbs+0x6870>
 10673aa:	48 89 c2             	mov    %rax,%rdx
 10673ad:	e8 ce d0 fb ff       	call   1024480 <myl_core_trap>
 10673b2:	48 89 f1             	mov    %rsi,%rcx
 10673b5:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10673b9:	48 21 d1             	and    %rdx,%rcx
 10673bc:	48 01 f1             	add    %rsi,%rcx
 10673bf:	48 39 d1             	cmp    %rdx,%rcx
 10673c2:	0f 82 4b ec ff ff    	jb     1066013 <my.interpreter::evaluate+0x13c3>
 10673c8:	48 8d 3d a1 d9 01 00 	lea    0x1d9a1(%rip),%rdi        # 1084d70 <core_durable_error.verbs+0x5e20>
 10673cf:	e8 ac d0 fb ff       	call   1024480 <myl_core_trap>
 10673d4:	4c 89 e1             	mov    %r12,%rcx
 10673d7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10673db:	48 21 d1             	and    %rdx,%rcx
 10673de:	4c 01 e1             	add    %r12,%rcx
 10673e1:	48 39 d1             	cmp    %rdx,%rcx
 10673e4:	0f 82 3f ea ff ff    	jb     1065e29 <my.interpreter::evaluate+0x11d9>
 10673ea:	48 8d 3d bf 0b 02 00 	lea    0x20bbf(%rip),%rdi        # 1087fb0 <core_durable_error.verbs+0x9060>
 10673f1:	4c 89 e6             	mov    %r12,%rsi
 10673f4:	e8 87 d0 fb ff       	call   1024480 <myl_core_trap>
 10673f9:	48 8b b4 24 d0 00 00 	mov    0xd0(%rsp),%rsi
 1067400:	00 
 1067401:	48 89 f1             	mov    %rsi,%rcx
 1067404:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067408:	48 21 d1             	and    %rdx,%rcx
 106740b:	48 01 f1             	add    %rsi,%rcx
 106740e:	48 39 d1             	cmp    %rdx,%rcx
 1067411:	0f 82 ef ed ff ff    	jb     1066206 <my.interpreter::evaluate+0x15b6>
 1067417:	48 8d 3d d2 0d 02 00 	lea    0x20dd2(%rip),%rdi        # 10881f0 <core_durable_error.verbs+0x92a0>
 106741e:	48 8b b4 24 d0 00 00 	mov    0xd0(%rsp),%rsi
 1067425:	00 
 1067426:	e8 55 d0 fb ff       	call   1024480 <myl_core_trap>
 106742b:	49 89 f0             	mov    %rsi,%r8
 106742e:	49 c1 f8 3f          	sar    $0x3f,%r8
 1067432:	49 21 c8             	and    %rcx,%r8
 1067435:	49 01 f0             	add    %rsi,%r8
 1067438:	49 39 c8             	cmp    %rcx,%r8
 106743b:	0f 82 61 ed ff ff    	jb     10661a2 <my.interpreter::evaluate+0x1552>
 1067441:	48 8d 3d 78 0d 02 00 	lea    0x20d78(%rip),%rdi        # 10881c0 <core_durable_error.verbs+0x9270>
 1067448:	48 89 ca             	mov    %rcx,%rdx
 106744b:	e8 30 d0 fb ff       	call   1024480 <myl_core_trap>
 1067450:	48 89 f1             	mov    %rsi,%rcx
 1067453:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067457:	48 21 d1             	and    %rdx,%rcx
 106745a:	48 01 f1             	add    %rsi,%rcx
 106745d:	48 39 d1             	cmp    %rdx,%rcx
 1067460:	0f 82 d3 f0 ff ff    	jb     1066539 <my.interpreter::evaluate+0x18e9>
 1067466:	48 8d 3d a3 0e 02 00 	lea    0x20ea3(%rip),%rdi        # 1088310 <core_durable_error.verbs+0x93c0>
 106746d:	e8 0e d0 fb ff       	call   1024480 <myl_core_trap>
 1067472:	48 89 f1             	mov    %rsi,%rcx
 1067475:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1067479:	48 21 d1             	and    %rdx,%rcx
 106747c:	48 01 f1             	add    %rsi,%rcx
 106747f:	48 39 d1             	cmp    %rdx,%rcx
 1067482:	0f 82 14 eb ff ff    	jb     1065f9c <my.interpreter::evaluate+0x134c>
 1067488:	48 8d 3d 31 0d 02 00 	lea    0x20d31(%rip),%rdi        # 10881c0 <core_durable_error.verbs+0x9270>
 106748f:	e8 ec cf fb ff       	call   1024480 <myl_core_trap>
 1067494:	48 89 f1             	mov    %rsi,%rcx
 1067497:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106749b:	48 21 d1             	and    %rdx,%rcx
 106749e:	48 01 f1             	add    %rsi,%rcx
 10674a1:	48 39 d1             	cmp    %rdx,%rcx
 10674a4:	0f 82 42 ee ff ff    	jb     10662ec <my.interpreter::evaluate+0x169c>
 10674aa:	48 8d 3d 8f 0e 02 00 	lea    0x20e8f(%rip),%rdi        # 1088340 <core_durable_error.verbs+0x93f0>
 10674b1:	e8 ca cf fb ff       	call   1024480 <myl_core_trap>
 10674b6:	48 89 f0             	mov    %rsi,%rax
 10674b9:	48 c1 f8 3f          	sar    $0x3f,%rax
 10674bd:	48 21 d0             	and    %rdx,%rax
 10674c0:	48 01 f0             	add    %rsi,%rax
 10674c3:	48 39 d0             	cmp    %rdx,%rax
 10674c6:	0f 82 21 ef ff ff    	jb     10663ed <my.interpreter::evaluate+0x179d>
 10674cc:	48 8d 3d fd 0e 02 00 	lea    0x20efd(%rip),%rdi        # 10883d0 <core_durable_error.verbs+0x9480>
 10674d3:	e8 a8 cf fb ff       	call   1024480 <myl_core_trap>
 10674d8:	48 8d 3d 71 d7 01 00 	lea    0x1d771(%rip),%rdi        # 1084c50 <core_durable_error.verbs+0x5d00>
 10674df:	e8 1c 23 fc ff       	call   1029800 <myl_core_assert_fail>
 10674e4:	48 8d 3d 65 d7 01 00 	lea    0x1d765(%rip),%rdi        # 1084c50 <core_durable_error.verbs+0x5d00>
 10674eb:	e8 10 23 fc ff       	call   1029800 <myl_core_assert_fail>
 10674f0:	48 8d 3d 59 d7 01 00 	lea    0x1d759(%rip),%rdi        # 1084c50 <core_durable_error.verbs+0x5d00>
 10674f7:	e8 04 23 fc ff       	call   1029800 <myl_core_assert_fail>
 10674fc:	48 8d 3d 4d d7 01 00 	lea    0x1d74d(%rip),%rdi        # 1084c50 <core_durable_error.verbs+0x5d00>
 1067503:	e8 f8 22 fc ff       	call   1029800 <myl_core_assert_fail>
 1067508:	48 8d 3d 41 d7 01 00 	lea    0x1d741(%rip),%rdi        # 1084c50 <core_durable_error.verbs+0x5d00>
 106750f:	e8 ec 22 fc ff       	call   1029800 <myl_core_assert_fail>
 1067514:	4d 89 f4             	mov    %r14,%r12
 1067517:	49 89 d6             	mov    %rdx,%r14
 106751a:	bf 05 00 00 00       	mov    $0x5,%edi
 106751f:	be 08 00 00 00       	mov    $0x8,%esi
 1067524:	e8 17 b4 fb ff       	call   1022940 <myl_core_list_new_slow>
 1067529:	48 89 c3             	mov    %rax,%rbx
 106752c:	48 8b 40 08          	mov    0x8(%rax),%rax
 1067530:	48 3b 43 10          	cmp    0x10(%rbx),%rax
 1067534:	48 8d 0d 8d c6 fa ff 	lea    -0x53973(%rip),%rcx        # 1013bc8 <core_number_pairs+0xc968>
 106753b:	48 89 4b 18          	mov    %rcx,0x18(%rbx)
 106753f:	72 14                	jb     1067555 <my.interpreter::evaluate+0x2905>
 1067541:	be 08 00 00 00       	mov    $0x8,%esi
 1067546:	48 89 df             	mov    %rbx,%rdi
 1067549:	e8 b2 b4 fb ff       	call   1022a00 <myl_core_list_grow>
 106754e:	48 89 c3             	mov    %rax,%rbx
 1067551:	48 8b 40 08          	mov    0x8(%rax),%rax
 1067555:	4c 89 f2             	mov    %r14,%rdx
 1067558:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 106755d:	4d 89 e6             	mov    %r12,%r14
 1067560:	e9 f2 f6 ff ff       	jmp    1066c57 <my.interpreter::evaluate+0x2007>
 1067565:	be 08 00 00 00       	mov    $0x8,%esi
 106756a:	48 89 df             	mov    %rbx,%rdi
 106756d:	4d 89 f4             	mov    %r14,%r12
 1067570:	49 89 c6             	mov    %rax,%r14
 1067573:	e8 88 b4 fb ff       	call   1022a00 <myl_core_list_grow>
 1067578:	48 89 c3             	mov    %rax,%rbx
 106757b:	4c 89 f0             	mov    %r14,%rax
 106757e:	4d 89 e6             	mov    %r12,%r14
 1067581:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1067585:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 1067589:	e9 f5 f6 ff ff       	jmp    1066c83 <my.interpreter::evaluate+0x2033>
 106758e:	be 08 00 00 00       	mov    $0x8,%esi
 1067593:	48 89 df             	mov    %rbx,%rdi
 1067596:	e8 65 b4 fb ff       	call   1022a00 <myl_core_list_grow>
 106759b:	48 89 c3             	mov    %rax,%rbx
 106759e:	48 8b 48 08          	mov    0x8(%rax),%rcx
 10675a2:	e9 f1 f6 ff ff       	jmp    1066c98 <my.interpreter::evaluate+0x2048>
 10675a7:	be 08 00 00 00       	mov    $0x8,%esi
 10675ac:	48 89 df             	mov    %rbx,%rdi
 10675af:	49 89 c6             	mov    %rax,%r14
 10675b2:	e8 49 b4 fb ff       	call   1022a00 <myl_core_list_grow>
 10675b7:	48 89 c3             	mov    %rax,%rbx
 10675ba:	4c 89 f0             	mov    %r14,%rax
 10675bd:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 10675c1:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 10675c5:	e9 fa f6 ff ff       	jmp    1066cc4 <my.interpreter::evaluate+0x2074>
 10675ca:	be 08 00 00 00       	mov    $0x8,%esi
 10675cf:	48 89 df             	mov    %rbx,%rdi
 10675d2:	e8 29 b4 fb ff       	call   1022a00 <myl_core_list_grow>
 10675d7:	48 89 c3             	mov    %rax,%rbx
 10675da:	48 8b 48 08          	mov    0x8(%rax),%rcx
 10675de:	e9 f6 f6 ff ff       	jmp    1066cd9 <my.interpreter::evaluate+0x2089>
 10675e3:	bf 03 00 00 00       	mov    $0x3,%edi
 10675e8:	be 08 00 00 00       	mov    $0x8,%esi
 10675ed:	e8 4e b3 fb ff       	call   1022940 <myl_core_list_new_slow>
 10675f2:	48 89 c3             	mov    %rax,%rbx
 10675f5:	48 8b 40 08          	mov    0x8(%rax),%rax
 10675f9:	48 3b 43 10          	cmp    0x10(%rbx),%rax
 10675fd:	48 8d 0d c4 c5 fa ff 	lea    -0x53a3c(%rip),%rcx        # 1013bc8 <core_number_pairs+0xc968>
 1067604:	48 89 4b 18          	mov    %rcx,0x18(%rbx)
 1067608:	72 14                	jb     106761e <my.interpreter::evaluate+0x29ce>
 106760a:	be 08 00 00 00       	mov    $0x8,%esi
 106760f:	48 89 df             	mov    %rbx,%rdi
 1067612:	e8 e9 b3 fb ff       	call   1022a00 <myl_core_list_grow>
 1067617:	48 89 c3             	mov    %rax,%rbx
 106761a:	48 8b 40 08          	mov    0x8(%rax),%rax
 106761e:	48 8b 6c 24 08       	mov    0x8(%rsp),%rbp
 1067623:	4c 8b 74 24 60       	mov    0x60(%rsp),%r14
 1067628:	e9 eb f7 ff ff       	jmp    1066e18 <my.interpreter::evaluate+0x21c8>
 106762d:	be 08 00 00 00       	mov    $0x8,%esi
 1067632:	48 89 df             	mov    %rbx,%rdi
 1067635:	49 89 c6             	mov    %rax,%r14
 1067638:	e8 c3 b3 fb ff       	call   1022a00 <myl_core_list_grow>
 106763d:	48 89 c3             	mov    %rax,%rbx
 1067640:	4c 89 f0             	mov    %r14,%rax
 1067643:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
 1067647:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 106764b:	e9 f4 f7 ff ff       	jmp    1066e44 <my.interpreter::evaluate+0x21f4>
 1067650:	be 08 00 00 00       	mov    $0x8,%esi
 1067655:	48 89 df             	mov    %rbx,%rdi
 1067658:	e8 a3 b3 fb ff       	call   1022a00 <myl_core_list_grow>
 106765d:	48 89 c3             	mov    %rax,%rbx
 1067660:	48 8b 48 08          	mov    0x8(%rax),%rcx
 1067664:	e9 f0 f7 ff ff       	jmp    1066e59 <my.interpreter::evaluate+0x2209>
 1067669:	0f b6 c0             	movzbl %al,%eax
 106766c:	83 f8 01             	cmp    $0x1,%eax
 106766f:	0f 84 ba 00 00 00    	je     106772f <my.interpreter::evaluate+0x2adf>
 1067675:	85 c0                	test   %eax,%eax
 1067677:	0f 85 be 00 00 00    	jne    106773b <my.interpreter::evaluate+0x2aeb>
 106767d:	48 8d 3d dc d4 01 00 	lea    0x1d4dc(%rip),%rdi        # 1084b60 <core_durable_error.verbs+0x5c10>
 1067684:	e8 77 21 fc ff       	call   1029800 <myl_core_assert_fail>
 1067689:	0f b6 c2             	movzbl %dl,%eax
 106768c:	83 f8 01             	cmp    $0x1,%eax
 106768f:	0f 84 02 01 00 00    	je     1067797 <my.interpreter::evaluate+0x2b47>
 1067695:	85 c0                	test   %eax,%eax
 1067697:	0f 85 06 01 00 00    	jne    10677a3 <my.interpreter::evaluate+0x2b53>
 106769d:	48 8d 3d bc d4 01 00 	lea    0x1d4bc(%rip),%rdi        # 1084b60 <core_durable_error.verbs+0x5c10>
 10676a4:	e8 57 21 fc ff       	call   1029800 <myl_core_assert_fail>
 10676a9:	83 fa 01             	cmp    $0x1,%edx
 10676ac:	0f 84 92 01 00 00    	je     1067844 <my.interpreter::evaluate+0x2bf4>
 10676b2:	85 d2                	test   %edx,%edx
 10676b4:	0f 85 96 01 00 00    	jne    1067850 <my.interpreter::evaluate+0x2c00>
 10676ba:	48 8d 3d 9f d4 01 00 	lea    0x1d49f(%rip),%rdi        # 1084b60 <core_durable_error.verbs+0x5c10>
 10676c1:	e8 3a 21 fc ff       	call   1029800 <myl_core_assert_fail>
 10676c6:	0f b6 c2             	movzbl %dl,%eax
 10676c9:	83 f8 01             	cmp    $0x1,%eax
 10676cc:	0f 84 0f 02 00 00    	je     10678e1 <my.interpreter::evaluate+0x2c91>
 10676d2:	85 c0                	test   %eax,%eax
 10676d4:	0f 85 13 02 00 00    	jne    10678ed <my.interpreter::evaluate+0x2c9d>
 10676da:	48 8d 3d 7f d4 01 00 	lea    0x1d47f(%rip),%rdi        # 1084b60 <core_durable_error.verbs+0x5c10>
 10676e1:	e8 1a 21 fc ff       	call   1029800 <myl_core_assert_fail>
 10676e6:	48 8d 3d 33 a8 01 00 	lea    0x1a833(%rip),%rdi        # 1081f20 <core_durable_error.verbs+0x2fd0>
 10676ed:	e8 0e 21 fc ff       	call   1029800 <myl_core_assert_fail>
 10676f2:	48 8d 3d 27 a8 01 00 	lea    0x1a827(%rip),%rdi        # 1081f20 <core_durable_error.verbs+0x2fd0>
 10676f9:	e8 02 21 fc ff       	call   1029800 <myl_core_assert_fail>
 10676fe:	48 8d 3d 1b ab 01 00 	lea    0x1ab1b(%rip),%rdi        # 1082220 <core_durable_error.verbs+0x32d0>
 1067705:	ba 01 00 00 00       	mov    $0x1,%edx
 106770a:	e8 71 cd fb ff       	call   1024480 <myl_core_trap>
 106770f:	48 8d 3d 3a de 01 00 	lea    0x1de3a(%rip),%rdi        # 1085550 <core_durable_error.verbs+0x6600>
 1067716:	ba 01 00 00 00       	mov    $0x1,%edx
 106771b:	48 89 c6             	mov    %rax,%rsi
 106771e:	e8 5d cd fb ff       	call   1024480 <myl_core_trap>
 1067723:	48 8d 3d f6 a7 01 00 	lea    0x1a7f6(%rip),%rdi        # 1081f20 <core_durable_error.verbs+0x2fd0>
 106772a:	e8 d1 20 fc ff       	call   1029800 <myl_core_assert_fail>
 106772f:	48 8d 3d 5a d4 01 00 	lea    0x1d45a(%rip),%rdi        # 1084b90 <core_durable_error.verbs+0x5c40>
 1067736:	e8 c5 20 fc ff       	call   1029800 <myl_core_assert_fail>
 106773b:	48 8d 3d 7e d4 01 00 	lea    0x1d47e(%rip),%rdi        # 1084bc0 <core_durable_error.verbs+0x5c70>
 1067742:	e8 b9 20 fc ff       	call   1029800 <myl_core_assert_fail>
 1067747:	48 8d 3d b2 d9 01 00 	lea    0x1d9b2(%rip),%rdi        # 1085100 <core_durable_error.verbs+0x61b0>
 106774e:	ba 01 00 00 00       	mov    $0x1,%edx
 1067753:	48 89 c6             	mov    %rax,%rsi
 1067756:	e8 25 cd fb ff       	call   1024480 <myl_core_trap>
 106775b:	48 8d 3d de db 01 00 	lea    0x1dbde(%rip),%rdi        # 1085340 <core_durable_error.verbs+0x63f0>
 1067762:	ba 01 00 00 00       	mov    $0x1,%edx
 1067767:	48 89 c6             	mov    %rax,%rsi
 106776a:	e8 11 cd fb ff       	call   1024480 <myl_core_trap>
 106776f:	48 8d 3d da da 01 00 	lea    0x1dada(%rip),%rdi        # 1085250 <core_durable_error.verbs+0x6300>
 1067776:	ba 01 00 00 00       	mov    $0x1,%edx
 106777b:	48 89 c6             	mov    %rax,%rsi
 106777e:	e8 fd cc fb ff       	call   1024480 <myl_core_trap>
 1067783:	48 8d 3d 46 df 01 00 	lea    0x1df46(%rip),%rdi        # 10856d0 <core_durable_error.verbs+0x6780>
 106778a:	ba 01 00 00 00       	mov    $0x1,%edx
 106778f:	48 89 c6             	mov    %rax,%rsi
 1067792:	e8 e9 cc fb ff       	call   1024480 <myl_core_trap>
 1067797:	48 8d 3d f2 d3 01 00 	lea    0x1d3f2(%rip),%rdi        # 1084b90 <core_durable_error.verbs+0x5c40>
 106779e:	e8 5d 20 fc ff       	call   1029800 <myl_core_assert_fail>
 10677a3:	48 8d 3d 16 d4 01 00 	lea    0x1d416(%rip),%rdi        # 1084bc0 <core_durable_error.verbs+0x5c70>
 10677aa:	e8 51 20 fc ff       	call   1029800 <myl_core_assert_fail>
 10677af:	48 8d 3d 2a de 01 00 	lea    0x1de2a(%rip),%rdi        # 10855e0 <core_durable_error.verbs+0x6690>
 10677b6:	ba 01 00 00 00       	mov    $0x1,%edx
 10677bb:	e8 c0 cc fb ff       	call   1024480 <myl_core_trap>
 10677c0:	48 8d 3d 39 f4 01 00 	lea    0x1f439(%rip),%rdi        # 1086c00 <core_durable_error.verbs+0x7cb0>
 10677c7:	48 89 c6             	mov    %rax,%rsi
 10677ca:	4c 89 f2             	mov    %r14,%rdx
 10677cd:	e8 ae cc fb ff       	call   1024480 <myl_core_trap>
 10677d2:	48 8d 3d 57 f4 01 00 	lea    0x1f457(%rip),%rdi        # 1086c30 <core_durable_error.verbs+0x7ce0>
 10677d9:	ba 01 00 00 00       	mov    $0x1,%edx
 10677de:	e8 9d cc fb ff       	call   1024480 <myl_core_trap>
 10677e3:	48 8d 3d 76 d6 01 00 	lea    0x1d676(%rip),%rdi        # 1084e60 <core_durable_error.verbs+0x5f10>
 10677ea:	ba 01 00 00 00       	mov    $0x1,%edx
 10677ef:	4c 89 ce             	mov    %r9,%rsi
 10677f2:	e8 89 cc fb ff       	call   1024480 <myl_core_trap>
 10677f7:	48 8d 3d 92 d6 01 00 	lea    0x1d692(%rip),%rdi        # 1084e90 <core_durable_error.verbs+0x5f40>
 10677fe:	ba 01 00 00 00       	mov    $0x1,%edx
 1067803:	48 89 de             	mov    %rbx,%rsi
 1067806:	e8 75 cc fb ff       	call   1024480 <myl_core_trap>
 106780b:	48 8d 3d 6e d7 01 00 	lea    0x1d76e(%rip),%rdi        # 1084f80 <core_durable_error.verbs+0x6030>
 1067812:	ba 01 00 00 00       	mov    $0x1,%edx
 1067817:	48 89 de             	mov    %rbx,%rsi
 106781a:	e8 61 cc fb ff       	call   1024480 <myl_core_trap>
 106781f:	48 8d 3d 7a db 01 00 	lea    0x1db7a(%rip),%rdi        # 10853a0 <core_durable_error.verbs+0x6450>
 1067826:	ba 01 00 00 00       	mov    $0x1,%edx
 106782b:	e8 50 cc fb ff       	call   1024480 <myl_core_trap>
 1067830:	48 8d 3d 99 db 01 00 	lea    0x1db99(%rip),%rdi        # 10853d0 <core_durable_error.verbs+0x6480>
 1067837:	ba 01 00 00 00       	mov    $0x1,%edx
 106783c:	48 89 c6             	mov    %rax,%rsi
 106783f:	e8 3c cc fb ff       	call   1024480 <myl_core_trap>
 1067844:	48 8d 3d 45 d3 01 00 	lea    0x1d345(%rip),%rdi        # 1084b90 <core_durable_error.verbs+0x5c40>
 106784b:	e8 b0 1f fc ff       	call   1029800 <myl_core_assert_fail>
 1067850:	48 8d 3d 69 d3 01 00 	lea    0x1d369(%rip),%rdi        # 1084bc0 <core_durable_error.verbs+0x5c70>
 1067857:	e8 a4 1f fc ff       	call   1029800 <myl_core_assert_fail>
 106785c:	48 8d 3d cd db 01 00 	lea    0x1dbcd(%rip),%rdi        # 1085430 <core_durable_error.verbs+0x64e0>
 1067863:	ba 01 00 00 00       	mov    $0x1,%edx
 1067868:	48 89 ce             	mov    %rcx,%rsi
 106786b:	e8 10 cc fb ff       	call   1024480 <myl_core_trap>
 1067870:	48 8d 3d 19 dc 01 00 	lea    0x1dc19(%rip),%rdi        # 1085490 <core_durable_error.verbs+0x6540>
 1067877:	ba 01 00 00 00       	mov    $0x1,%edx
 106787c:	48 89 c6             	mov    %rax,%rsi
 106787f:	e8 fc cb fb ff       	call   1024480 <myl_core_trap>
 1067884:	48 8d 3d 65 dc 01 00 	lea    0x1dc65(%rip),%rdi        # 10854f0 <core_durable_error.verbs+0x65a0>
 106788b:	ba 01 00 00 00       	mov    $0x1,%edx
 1067890:	e8 eb cb fb ff       	call   1024480 <myl_core_trap>
 1067895:	48 8d 3d 84 a6 01 00 	lea    0x1a684(%rip),%rdi        # 1081f20 <core_durable_error.verbs+0x2fd0>
 106789c:	e8 5f 1f fc ff       	call   1029800 <myl_core_assert_fail>
 10678a1:	48 8d 3d e8 de 01 00 	lea    0x1dee8(%rip),%rdi        # 1085790 <core_durable_error.verbs+0x6840>
 10678a8:	ba 01 00 00 00       	mov    $0x1,%edx
 10678ad:	e8 ce cb fb ff       	call   1024480 <myl_core_trap>
 10678b2:	48 8d 3d 27 d4 01 00 	lea    0x1d427(%rip),%rdi        # 1084ce0 <core_durable_error.verbs+0x5d90>
 10678b9:	ba 01 00 00 00       	mov    $0x1,%edx
 10678be:	48 89 ce             	mov    %rcx,%rsi
 10678c1:	e8 ba cb fb ff       	call   1024480 <myl_core_trap>
 10678c6:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 10678cd:	00 00 80 
 10678d0:	48 8d 3d 89 d8 01 00 	lea    0x1d889(%rip),%rdi        # 1085160 <core_durable_error.verbs+0x6210>
 10678d7:	ba 01 00 00 00       	mov    $0x1,%edx
 10678dc:	e8 9f cb fb ff       	call   1024480 <myl_core_trap>
 10678e1:	48 8d 3d a8 d2 01 00 	lea    0x1d2a8(%rip),%rdi        # 1084b90 <core_durable_error.verbs+0x5c40>
 10678e8:	e8 13 1f fc ff       	call   1029800 <myl_core_assert_fail>
 10678ed:	48 8d 3d cc d2 01 00 	lea    0x1d2cc(%rip),%rdi        # 1084bc0 <core_durable_error.verbs+0x5c70>
 10678f4:	e8 07 1f fc ff       	call   1029800 <myl_core_assert_fail>
 10678f9:	48 8d 3d 90 d8 01 00 	lea    0x1d890(%rip),%rdi        # 1085190 <core_durable_error.verbs+0x6240>
 1067900:	ba 01 00 00 00       	mov    $0x1,%edx
 1067905:	48 89 c6             	mov    %rax,%rsi
 1067908:	e8 73 cb fb ff       	call   1024480 <myl_core_trap>
 106790d:	48 8d 3d dc de 01 00 	lea    0x1dedc(%rip),%rdi        # 10857f0 <core_durable_error.verbs+0x68a0>
 1067914:	ba 01 00 00 00       	mov    $0x1,%edx
 1067919:	e8 62 cb fb ff       	call   1024480 <myl_core_trap>
 106791e:	48 8d 3d 1b d4 01 00 	lea    0x1d41b(%rip),%rdi        # 1084d40 <core_durable_error.verbs+0x5df0>
 1067925:	ba 01 00 00 00       	mov    $0x1,%edx
 106792a:	48 89 c6             	mov    %rax,%rsi
 106792d:	e8 4e cb fb ff       	call   1024480 <myl_core_trap>
 1067932:	48 8d 3d a7 06 02 00 	lea    0x206a7(%rip),%rdi        # 1087fe0 <core_durable_error.verbs+0x9090>
 1067939:	e8 c2 1e fc ff       	call   1029800 <myl_core_assert_fail>
 106793e:	48 8d 3d 1b 08 02 00 	lea    0x2081b(%rip),%rdi        # 1088160 <core_durable_error.verbs+0x9210>
 1067945:	4c 89 f2             	mov    %r14,%rdx
 1067948:	e8 33 cb fb ff       	call   1024480 <myl_core_trap>
 106794d:	48 8d 3d 3c 08 02 00 	lea    0x2083c(%rip),%rdi        # 1088190 <core_durable_error.verbs+0x9240>
 1067954:	ba 01 00 00 00       	mov    $0x1,%edx
 1067959:	48 89 ce             	mov    %rcx,%rsi
 106795c:	e8 1f cb fb ff       	call   1024480 <myl_core_trap>
 1067961:	48 8d 3d 48 09 02 00 	lea    0x20948(%rip),%rdi        # 10882b0 <core_durable_error.verbs+0x9360>
 1067968:	4c 89 f2             	mov    %r14,%rdx
 106796b:	e8 10 cb fb ff       	call   1024480 <myl_core_trap>
 1067970:	48 8d 3d 69 09 02 00 	lea    0x20969(%rip),%rdi        # 10882e0 <core_durable_error.verbs+0x9390>
 1067977:	ba 01 00 00 00       	mov    $0x1,%edx
 106797c:	48 89 c6             	mov    %rax,%rsi
 106797f:	e8 fc ca fb ff       	call   1024480 <myl_core_trap>
 1067984:	48 8d 3d d5 07 02 00 	lea    0x207d5(%rip),%rdi        # 1088160 <core_durable_error.verbs+0x9210>
 106798b:	e8 f0 ca fb ff       	call   1024480 <myl_core_trap>
 1067990:	48 8d 3d f9 07 02 00 	lea    0x207f9(%rip),%rdi        # 1088190 <core_durable_error.verbs+0x9240>
 1067997:	ba 01 00 00 00       	mov    $0x1,%edx
 106799c:	48 89 c6             	mov    %rax,%rsi
 106799f:	e8 dc ca fb ff       	call   1024480 <myl_core_trap>
 10679a4:	48 8d 3d c5 09 02 00 	lea    0x209c5(%rip),%rdi        # 1088370 <core_durable_error.verbs+0x9420>
 10679ab:	ba 01 00 00 00       	mov    $0x1,%edx
 10679b0:	e8 cb ca fb ff       	call   1024480 <myl_core_trap>
 10679b5:	48 8d 3d e4 09 02 00 	lea    0x209e4(%rip),%rdi        # 10883a0 <core_durable_error.verbs+0x9450>
 10679bc:	ba 01 00 00 00       	mov    $0x1,%edx
 10679c1:	48 89 c6             	mov    %rax,%rsi
 10679c4:	e8 b7 ca fb ff       	call   1024480 <myl_core_trap>

Disassembly of section .plt:
