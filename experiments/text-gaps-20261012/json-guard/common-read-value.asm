
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-001/text-runtime:     file format elf64-x86-64


Disassembly of section .text:

0000000001050880 <my.json::read_value>:
 1050880:	55                   	push   %rbp
 1050881:	41 57                	push   %r15
 1050883:	41 56                	push   %r14
 1050885:	41 55                	push   %r13
 1050887:	41 54                	push   %r12
 1050889:	53                   	push   %rbx
 105088a:	48 81 ec d8 00 00 00 	sub    $0xd8,%rsp
 1050891:	49 89 d7             	mov    %rdx,%r15
 1050894:	48 89 f3             	mov    %rsi,%rbx
 1050897:	49 89 fd             	mov    %rdi,%r13
 105089a:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
 105089f:	48 83 f9 40          	cmp    $0x40,%rcx
 10508a3:	0f 8f 52 0b 00 00    	jg     10513fb <my.json::read_value+0xb7b>
 10508a9:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 10508ad:	49 39 d7             	cmp    %rdx,%r15
 10508b0:	7d 49                	jge    10508fb <my.json::read_value+0x7b>
 10508b2:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 10508b9:	00 00 00 
 10508bc:	48 89 d9             	mov    %rbx,%rcx
 10508bf:	90                   	nop
 10508c0:	4c 89 fe             	mov    %r15,%rsi
 10508c3:	48 c1 fe 3f          	sar    $0x3f,%rsi
 10508c7:	48 21 d6             	and    %rdx,%rsi
 10508ca:	4a 8d 3c 3e          	lea    (%rsi,%r15,1),%rdi
 10508ce:	48 39 d7             	cmp    %rdx,%rdi
 10508d1:	0f 83 f8 12 00 00    	jae    1051bcf <my.json::read_value+0x134f>
 10508d7:	48 01 f1             	add    %rsi,%rcx
 10508da:	41 0f b6 4c 0f 20    	movzbl 0x20(%r15,%rcx,1),%ecx
 10508e0:	48 83 f9 20          	cmp    $0x20,%rcx
 10508e4:	77 15                	ja     10508fb <my.json::read_value+0x7b>
 10508e6:	48 0f a3 c8          	bt     %rcx,%rax
 10508ea:	73 0f                	jae    10508fb <my.json::read_value+0x7b>
 10508ec:	49 ff c7             	inc    %r15
 10508ef:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 10508f3:	48 89 d9             	mov    %rbx,%rcx
 10508f6:	49 39 d7             	cmp    %rdx,%r15
 10508f9:	7c c5                	jl     10508c0 <my.json::read_value+0x40>
 10508fb:	49 89 dc             	mov    %rbx,%r12
 10508fe:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1050902:	49 39 d7             	cmp    %rdx,%r15
 1050905:	0f 8d 23 0b 00 00    	jge    105142e <my.json::read_value+0xbae>
 105090b:	4c 89 f8             	mov    %r15,%rax
 105090e:	48 c1 f8 3f          	sar    $0x3f,%rax
 1050912:	48 21 d0             	and    %rdx,%rax
 1050915:	4c 01 f8             	add    %r15,%rax
 1050918:	48 39 d0             	cmp    %rdx,%rax
 105091b:	0f 83 26 13 00 00    	jae    1051c47 <my.json::read_value+0x13c7>
 1050921:	49 8d 7c 24 20       	lea    0x20(%r12),%rdi
 1050926:	41 0f b6 4c 04 20    	movzbl 0x20(%r12,%rax,1),%ecx
 105092c:	0f b6 f1             	movzbl %cl,%esi
 105092f:	44 8d 46 a5          	lea    -0x5b(%rsi),%r8d
 1050933:	41 83 f8 20          	cmp    $0x20,%r8d
 1050937:	0f 87 37 02 00 00    	ja     1050b74 <my.json::read_value+0x2f4>
 105093d:	48 8d 35 cc 6a fb ff 	lea    -0x49534(%rip),%rsi        # 1007410 <core_number_pairs+0x170>
 1050944:	4e 63 04 86          	movslq (%rsi,%r8,4),%r8
 1050948:	49 01 f0             	add    %rsi,%r8
 105094b:	41 ff e0             	jmp    *%r8
 105094e:	49 8d 57 01          	lea    0x1(%r15),%rdx
 1050952:	64 4c 8b 34 25 c8 fe 	mov    %fs:0xfffffffffffffec8,%r14
 1050959:	ff ff 
 105095b:	4d 85 f6             	test   %r14,%r14
 105095e:	0f 84 3f 12 00 00    	je     1051ba3 <my.json::read_value+0x1323>
 1050964:	49 8b 06             	mov    (%r14),%rax
 1050967:	64 48 89 04 25 c8 fe 	mov    %rax,%fs:0xfffffffffffffec8
 105096e:	ff ff 
 1050970:	41 c7 06 00 00 00 01 	movl   $0x1000000,(%r14)
 1050977:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
 105097b:	c4 c1 7a 7f 46 08    	vmovdqu %xmm0,0x8(%r14)
 1050981:	49 c7 46 18 00 00 00 	movq   $0x0,0x18(%r14)
 1050988:	00 
 1050989:	48 8d 05 e8 9e fb ff 	lea    -0x46118(%rip),%rax        # 100a878 <core_number_pairs+0x35d8>
 1050990:	49 89 46 18          	mov    %rax,0x18(%r14)
 1050994:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 1050999:	48 39 c2             	cmp    %rax,%rdx
 105099c:	7d 6b                	jge    1050a09 <my.json::read_value+0x189>
 105099e:	48 b9 00 26 00 00 01 	movabs $0x100002600,%rcx
 10509a5:	00 00 00 
 10509a8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10509af:	0f 1f 84 00 00 00 00 
 10509b6:	00 
 10509b7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10509be:	00 00 
 10509c0:	49 8d 77 01          	lea    0x1(%r15),%rsi
 10509c4:	48 89 f7             	mov    %rsi,%rdi
 10509c7:	48 c1 ff 3f          	sar    $0x3f,%rdi
 10509cb:	48 21 c7             	and    %rax,%rdi
 10509ce:	4d 8d 04 3f          	lea    (%r15,%rdi,1),%r8
 10509d2:	49 ff c0             	inc    %r8
 10509d5:	49 39 c0             	cmp    %rax,%r8
 10509d8:	0f 83 3c 12 00 00    	jae    1051c1a <my.json::read_value+0x139a>
 10509de:	49 01 fc             	add    %rdi,%r12
 10509e1:	43 0f b6 44 27 21    	movzbl 0x21(%r15,%r12,1),%eax
 10509e7:	48 83 f8 20          	cmp    $0x20,%rax
 10509eb:	77 1c                	ja     1050a09 <my.json::read_value+0x189>
 10509ed:	48 0f a3 c1          	bt     %rax,%rcx
 10509f1:	73 16                	jae    1050a09 <my.json::read_value+0x189>
 10509f3:	4c 89 fa             	mov    %r15,%rdx
 10509f6:	48 83 c2 02          	add    $0x2,%rdx
 10509fa:	48 8b 43 08          	mov    0x8(%rbx),%rax
 10509fe:	49 89 f7             	mov    %rsi,%r15
 1050a01:	49 89 dc             	mov    %rbx,%r12
 1050a04:	48 39 c2             	cmp    %rax,%rdx
 1050a07:	7c b7                	jl     10509c0 <my.json::read_value+0x140>
 1050a09:	48 8b 43 08          	mov    0x8(%rbx),%rax
 1050a0d:	48 39 c2             	cmp    %rax,%rdx
 1050a10:	0f 8d 5f 0e 00 00    	jge    1051875 <my.json::read_value+0xff5>
 1050a16:	48 89 d1             	mov    %rdx,%rcx
 1050a19:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050a1d:	48 21 c1             	and    %rax,%rcx
 1050a20:	48 01 d1             	add    %rdx,%rcx
 1050a23:	48 39 c1             	cmp    %rax,%rcx
 1050a26:	0f 83 bd 12 00 00    	jae    1051ce9 <my.json::read_value+0x1469>
 1050a2c:	80 7c 0b 20 5d       	cmpb   $0x5d,0x20(%rbx,%rcx,1)
 1050a31:	0f 84 b6 0c 00 00    	je     10516ed <my.json::read_value+0xe6d>
 1050a37:	4c 89 6c 24 08       	mov    %r13,0x8(%rsp)
 1050a3c:	4d 8b 66 08          	mov    0x8(%r14),%r12
 1050a40:	49 8b 6e 10          	mov    0x10(%r14),%rbp
 1050a44:	48 ff 44 24 28       	incq   0x28(%rsp)
 1050a49:	4c 8d 7c 24 40       	lea    0x40(%rsp),%r15
 1050a4e:	49 bd 00 26 00 00 01 	movabs $0x100002600,%r13
 1050a55:	00 00 00 
 1050a58:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1050a5f:	00 
 1050a60:	4c 89 ff             	mov    %r15,%rdi
 1050a63:	48 89 de             	mov    %rbx,%rsi
 1050a66:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 1050a6b:	e8 10 fe ff ff       	call   1050880 <my.json::read_value>
 1050a70:	48 8b 5c 24 58       	mov    0x58(%rsp),%rbx
 1050a75:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 1050a7a:	80 7c 24 40 01       	cmpb   $0x1,0x40(%rsp)
 1050a7f:	0f 84 7a 10 00 00    	je     1051aff <my.json::read_value+0x127f>
 1050a85:	c5 fa 6f 44 24 48    	vmovdqu 0x48(%rsp),%xmm0
 1050a8b:	49 39 ec             	cmp    %rbp,%r12
 1050a8e:	0f 83 b1 00 00 00    	jae    1050b45 <my.json::read_value+0x2c5>
 1050a94:	4c 89 e0             	mov    %r12,%rax
 1050a97:	48 c1 e0 04          	shl    $0x4,%rax
 1050a9b:	c5 f9 db 05 9d 39 fb 	vpand  -0x4c663(%rip),%xmm0,%xmm0        # 1004440 <__anon_2214+0xb0>
 1050aa2:	ff 
 1050aa3:	c4 c1 7a 7f 44 06 20 	vmovdqu %xmm0,0x20(%r14,%rax,1)
 1050aaa:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050ab1:	0f 1f 84 00 00 00 00 
 1050ab8:	00 
 1050ab9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1050ac0:	48 8b 43 08          	mov    0x8(%rbx),%rax
 1050ac4:	48 39 c2             	cmp    %rax,%rdx
 1050ac7:	7d 37                	jge    1050b00 <my.json::read_value+0x280>
 1050ac9:	48 89 d1             	mov    %rdx,%rcx
 1050acc:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050ad0:	48 21 c1             	and    %rax,%rcx
 1050ad3:	48 8d 34 11          	lea    (%rcx,%rdx,1),%rsi
 1050ad7:	48 39 c6             	cmp    %rax,%rsi
 1050ada:	0f 83 dd 10 00 00    	jae    1051bbd <my.json::read_value+0x133d>
 1050ae0:	48 01 d9             	add    %rbx,%rcx
 1050ae3:	0f b6 44 0a 20       	movzbl 0x20(%rdx,%rcx,1),%eax
 1050ae8:	48 83 f8 20          	cmp    $0x20,%rax
 1050aec:	77 12                	ja     1050b00 <my.json::read_value+0x280>
 1050aee:	49 0f a3 c5          	bt     %rax,%r13
 1050af2:	73 0c                	jae    1050b00 <my.json::read_value+0x280>
 1050af4:	48 ff c2             	inc    %rdx
 1050af7:	eb c7                	jmp    1050ac0 <my.json::read_value+0x240>
 1050af9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1050b00:	49 ff c4             	inc    %r12
 1050b03:	48 8b 43 08          	mov    0x8(%rbx),%rax
 1050b07:	48 39 c2             	cmp    %rax,%rdx
 1050b0a:	0f 8d 8c 0e 00 00    	jge    105199c <my.json::read_value+0x111c>
 1050b10:	48 89 d1             	mov    %rdx,%rcx
 1050b13:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050b17:	48 21 c1             	and    %rax,%rcx
 1050b1a:	48 01 d1             	add    %rdx,%rcx
 1050b1d:	48 39 c1             	cmp    %rax,%rcx
 1050b20:	0f 83 0f 11 00 00    	jae    1051c35 <my.json::read_value+0x13b5>
 1050b26:	0f b6 4c 0b 20       	movzbl 0x20(%rbx,%rcx,1),%ecx
 1050b2b:	83 f9 2c             	cmp    $0x2c,%ecx
 1050b2e:	0f 85 a7 0b 00 00    	jne    10516db <my.json::read_value+0xe5b>
 1050b34:	48 ff c2             	inc    %rdx
 1050b37:	48 39 c2             	cmp    %rax,%rdx
 1050b3a:	0f 8c 20 ff ff ff    	jl     1050a60 <my.json::read_value+0x1e0>
 1050b40:	e9 e4 0f 00 00       	jmp    1051b29 <my.json::read_value+0x12a9>
 1050b45:	4d 89 66 08          	mov    %r12,0x8(%r14)
 1050b49:	be 10 00 00 00       	mov    $0x10,%esi
 1050b4e:	4c 89 f7             	mov    %r14,%rdi
 1050b51:	49 89 d6             	mov    %rdx,%r14
 1050b54:	c5 f9 7f 44 24 10    	vmovdqa %xmm0,0x10(%rsp)
 1050b5a:	e8 61 63 fc ff       	call   1016ec0 <myl_core_list_grow>
 1050b5f:	c5 f9 6f 44 24 10    	vmovdqa 0x10(%rsp),%xmm0
 1050b65:	4c 89 f2             	mov    %r14,%rdx
 1050b68:	49 89 c6             	mov    %rax,%r14
 1050b6b:	48 8b 68 10          	mov    0x10(%rax),%rbp
 1050b6f:	e9 20 ff ff ff       	jmp    1050a94 <my.json::read_value+0x214>
 1050b74:	83 fe 22             	cmp    $0x22,%esi
 1050b77:	0f 84 28 08 00 00    	je     10513a5 <my.json::read_value+0xb25>
 1050b7d:	83 fe 2d             	cmp    $0x2d,%esi
 1050b80:	74 0b                	je     1050b8d <my.json::read_value+0x30d>
 1050b82:	8d 41 d0             	lea    -0x30(%rcx),%eax
 1050b85:	3c 0a                	cmp    $0xa,%al
 1050b87:	0f 83 3e 0c 00 00    	jae    10517cb <my.json::read_value+0xf4b>
 1050b8d:	45 31 f6             	xor    %r14d,%r14d
 1050b90:	80 f9 2d             	cmp    $0x2d,%cl
 1050b93:	41 0f 94 c6          	sete   %r14b
 1050b97:	4d 01 fe             	add    %r15,%r14
 1050b9a:	49 39 d6             	cmp    %rdx,%r14
 1050b9d:	0f 8d 6c 0b 00 00    	jge    105170f <my.json::read_value+0xe8f>
 1050ba3:	4c 89 f0             	mov    %r14,%rax
 1050ba6:	48 c1 f8 3f          	sar    $0x3f,%rax
 1050baa:	48 21 d0             	and    %rdx,%rax
 1050bad:	4c 01 f0             	add    %r14,%rax
 1050bb0:	48 39 d0             	cmp    %rdx,%rax
 1050bb3:	0f 83 e5 10 00 00    	jae    1051c9e <my.json::read_value+0x141e>
 1050bb9:	0f b6 04 07          	movzbl (%rdi,%rax,1),%eax
 1050bbd:	8d 70 d0             	lea    -0x30(%rax),%esi
 1050bc0:	40 80 fe 0a          	cmp    $0xa,%sil
 1050bc4:	0f 83 45 0b 00 00    	jae    105170f <my.json::read_value+0xe8f>
 1050bca:	3c 30                	cmp    $0x30,%al
 1050bcc:	0f 85 e8 06 00 00    	jne    10512ba <my.json::read_value+0xa3a>
 1050bd2:	49 8d 6e 01          	lea    0x1(%r14),%rbp
 1050bd6:	48 39 d5             	cmp    %rdx,%rbp
 1050bd9:	7d 24                	jge    1050bff <my.json::read_value+0x37f>
 1050bdb:	31 c0                	xor    %eax,%eax
 1050bdd:	49 83 fe ff          	cmp    $0xffffffffffffffff,%r14
 1050be1:	48 0f 4c c2          	cmovl  %rdx,%rax
 1050be5:	48 01 e8             	add    %rbp,%rax
 1050be8:	48 39 d0             	cmp    %rdx,%rax
 1050beb:	0f 83 46 11 00 00    	jae    1051d37 <my.json::read_value+0x14b7>
 1050bf1:	0f b6 04 07          	movzbl (%rdi,%rax,1),%eax
 1050bf5:	04 d0                	add    $0xd0,%al
 1050bf7:	3c 0a                	cmp    $0xa,%al
 1050bf9:	0f 82 6b 0e 00 00    	jb     1051a6a <my.json::read_value+0x11ea>
 1050bff:	45 31 d2             	xor    %r10d,%r10d
 1050c02:	45 31 db             	xor    %r11d,%r11d
 1050c05:	e9 7e 08 00 00       	jmp    1051488 <my.json::read_value+0xc08>
 1050c0a:	4d 89 fe             	mov    %r15,%r14
 1050c0d:	49 83 c6 05          	add    $0x5,%r14
 1050c11:	0f 80 96 10 00 00    	jo     1051cad <my.json::read_value+0x142d>
 1050c17:	49 39 d6             	cmp    %rdx,%r14
 1050c1a:	0f 8f 22 0c 00 00    	jg     1051842 <my.json::read_value+0xfc2>
 1050c20:	48 89 c1             	mov    %rax,%rcx
 1050c23:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050c27:	c4 e2 f0 f2 c0       	andn   %rax,%rcx,%rax
 1050c2c:	48 39 d0             	cmp    %rdx,%rax
 1050c2f:	48 0f 4d c2          	cmovge %rdx,%rax
 1050c33:	4c 89 f1             	mov    %r14,%rcx
 1050c36:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050c3a:	48 21 d1             	and    %rdx,%rcx
 1050c3d:	4c 01 f1             	add    %r14,%rcx
 1050c40:	48 89 ce             	mov    %rcx,%rsi
 1050c43:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1050c47:	c4 e2 c8 f2 c9       	andn   %rcx,%rsi,%rcx
 1050c4c:	48 39 d1             	cmp    %rdx,%rcx
 1050c4f:	48 0f 4c d1          	cmovl  %rcx,%rdx
 1050c53:	48 29 c2             	sub    %rax,%rdx
 1050c56:	48 89 d1             	mov    %rdx,%rcx
 1050c59:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050c5d:	c4 e2 f0 f2 f2       	andn   %rdx,%rcx,%rsi
 1050c62:	48 01 c7             	add    %rax,%rdi
 1050c65:	48 8d 15 74 91 fb ff 	lea    -0x46e8c(%rip),%rdx        # 1009de0 <core_number_pairs+0x2b40>
 1050c6c:	b9 05 00 00 00       	mov    $0x5,%ecx
 1050c71:	e8 8a 15 fd ff       	call   1022200 <myl_core_span_eq>
 1050c76:	84 c0                	test   %al,%al
 1050c78:	0f 84 03 0c 00 00    	je     1051881 <my.json::read_value+0x1001>
 1050c7e:	b8 01 00 00 00       	mov    $0x1,%eax
 1050c83:	31 c9                	xor    %ecx,%ecx
 1050c85:	4d 89 f7             	mov    %r14,%r15
 1050c88:	e9 50 0c 00 00       	jmp    10518dd <my.json::read_value+0x105d>
 1050c8d:	4d 89 fe             	mov    %r15,%r14
 1050c90:	49 83 c6 04          	add    $0x4,%r14
 1050c94:	0f 80 27 10 00 00    	jo     1051cc1 <my.json::read_value+0x1441>
 1050c9a:	49 39 d6             	cmp    %rdx,%r14
 1050c9d:	0f 8f af 0b 00 00    	jg     1051852 <my.json::read_value+0xfd2>
 1050ca3:	48 89 c1             	mov    %rax,%rcx
 1050ca6:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050caa:	c4 e2 f0 f2 c0       	andn   %rax,%rcx,%rax
 1050caf:	48 39 d0             	cmp    %rdx,%rax
 1050cb2:	48 0f 4d c2          	cmovge %rdx,%rax
 1050cb6:	4c 89 f1             	mov    %r14,%rcx
 1050cb9:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050cbd:	48 21 d1             	and    %rdx,%rcx
 1050cc0:	4c 01 f1             	add    %r14,%rcx
 1050cc3:	48 89 ce             	mov    %rcx,%rsi
 1050cc6:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1050cca:	c4 e2 c8 f2 c9       	andn   %rcx,%rsi,%rcx
 1050ccf:	48 39 d1             	cmp    %rdx,%rcx
 1050cd2:	48 0f 4c d1          	cmovl  %rcx,%rdx
 1050cd6:	48 29 c2             	sub    %rax,%rdx
 1050cd9:	48 89 d1             	mov    %rdx,%rcx
 1050cdc:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050ce0:	c4 e2 f0 f2 f2       	andn   %rdx,%rcx,%rsi
 1050ce5:	48 01 c7             	add    %rax,%rdi
 1050ce8:	48 8d 15 71 90 fb ff 	lea    -0x46f8f(%rip),%rdx        # 1009d60 <core_number_pairs+0x2ac0>
 1050cef:	b9 04 00 00 00       	mov    $0x4,%ecx
 1050cf4:	e8 07 15 fd ff       	call   1022200 <myl_core_span_eq>
 1050cf9:	84 c0                	test   %al,%al
 1050cfb:	0f 84 aa 0b 00 00    	je     10518ab <my.json::read_value+0x102b>
 1050d01:	31 c9                	xor    %ecx,%ecx
 1050d03:	4d 89 f7             	mov    %r14,%r15
 1050d06:	31 c0                	xor    %eax,%eax
 1050d08:	e9 d0 0b 00 00       	jmp    10518dd <my.json::read_value+0x105d>
 1050d0d:	4d 89 fe             	mov    %r15,%r14
 1050d10:	49 83 c6 04          	add    $0x4,%r14
 1050d14:	0f 80 bb 0f 00 00    	jo     1051cd5 <my.json::read_value+0x1455>
 1050d1a:	49 39 d6             	cmp    %rdx,%r14
 1050d1d:	0f 8f 3f 0b 00 00    	jg     1051862 <my.json::read_value+0xfe2>
 1050d23:	48 89 c1             	mov    %rax,%rcx
 1050d26:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050d2a:	c4 e2 f0 f2 c0       	andn   %rax,%rcx,%rax
 1050d2f:	48 39 d0             	cmp    %rdx,%rax
 1050d32:	48 0f 4d c2          	cmovge %rdx,%rax
 1050d36:	4c 89 f1             	mov    %r14,%rcx
 1050d39:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050d3d:	48 21 d1             	and    %rdx,%rcx
 1050d40:	4c 01 f1             	add    %r14,%rcx
 1050d43:	48 89 ce             	mov    %rcx,%rsi
 1050d46:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1050d4a:	c4 e2 c8 f2 c9       	andn   %rcx,%rsi,%rcx
 1050d4f:	48 39 d1             	cmp    %rdx,%rcx
 1050d52:	48 0f 4c d1          	cmovl  %rcx,%rdx
 1050d56:	48 29 c2             	sub    %rax,%rdx
 1050d59:	48 89 d1             	mov    %rdx,%rcx
 1050d5c:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050d60:	c4 e2 f0 f2 f2       	andn   %rdx,%rcx,%rsi
 1050d65:	48 01 c7             	add    %rax,%rdi
 1050d68:	48 8d 15 31 90 fb ff 	lea    -0x46fcf(%rip),%rdx        # 1009da0 <core_number_pairs+0x2b00>
 1050d6f:	b9 04 00 00 00       	mov    $0x4,%ecx
 1050d74:	e8 87 14 fd ff       	call   1022200 <myl_core_span_eq>
 1050d79:	84 c0                	test   %al,%al
 1050d7b:	0f 84 75 0b 00 00    	je     10518f6 <my.json::read_value+0x1076>
 1050d81:	b8 01 00 00 00       	mov    $0x1,%eax
 1050d86:	31 c9                	xor    %ecx,%ecx
 1050d88:	4d 89 f7             	mov    %r14,%r15
 1050d8b:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 1050d8f:	49 89 45 08          	mov    %rax,0x8(%r13)
 1050d93:	49 c7 45 10 01 00 00 	movq   $0x1,0x10(%r13)
 1050d9a:	00 
 1050d9b:	e9 4d 0b 00 00       	jmp    10518ed <my.json::read_value+0x106d>
 1050da0:	4c 89 6c 24 08       	mov    %r13,0x8(%rsp)
 1050da5:	4d 8d 6f 01          	lea    0x1(%r15),%r13
 1050da9:	48 8d 35 18 fc 00 00 	lea    0xfc18(%rip),%rsi        # 10609c8 <core_durable_error.verbs+0x1d98>
 1050db0:	31 ff                	xor    %edi,%edi
 1050db2:	e8 49 d6 fc ff       	call   101e400 <myl_core_dict_new>
 1050db7:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 1050dbc:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 1050dc1:	49 39 d5             	cmp    %rdx,%r13
 1050dc4:	0f 8d 7f 00 00 00    	jge    1050e49 <my.json::read_value+0x5c9>
 1050dca:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 1050dd1:	00 00 00 
 1050dd4:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050ddb:	0f 1f 84 00 00 00 00 
 1050de2:	00 
 1050de3:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050dea:	0f 1f 84 00 00 00 00 
 1050df1:	00 
 1050df2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050df9:	1f 84 00 00 00 00 00 
 1050e00:	49 8d 77 01          	lea    0x1(%r15),%rsi
 1050e04:	48 89 f1             	mov    %rsi,%rcx
 1050e07:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1050e0b:	48 21 d1             	and    %rdx,%rcx
 1050e0e:	49 8d 3c 0f          	lea    (%r15,%rcx,1),%rdi
 1050e12:	48 ff c7             	inc    %rdi
 1050e15:	48 39 d7             	cmp    %rdx,%rdi
 1050e18:	0f 83 0b 0e 00 00    	jae    1051c29 <my.json::read_value+0x13a9>
 1050e1e:	49 01 cc             	add    %rcx,%r12
 1050e21:	43 0f b6 4c 27 21    	movzbl 0x21(%r15,%r12,1),%ecx
 1050e27:	48 83 f9 20          	cmp    $0x20,%rcx
 1050e2b:	77 1c                	ja     1050e49 <my.json::read_value+0x5c9>
 1050e2d:	48 0f a3 c8          	bt     %rcx,%rax
 1050e31:	73 16                	jae    1050e49 <my.json::read_value+0x5c9>
 1050e33:	4d 89 fd             	mov    %r15,%r13
 1050e36:	49 83 c5 02          	add    $0x2,%r13
 1050e3a:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1050e3e:	49 89 f7             	mov    %rsi,%r15
 1050e41:	49 89 dc             	mov    %rbx,%r12
 1050e44:	49 39 d5             	cmp    %rdx,%r13
 1050e47:	7c b7                	jl     1050e00 <my.json::read_value+0x580>
 1050e49:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1050e4d:	49 39 d5             	cmp    %rdx,%r13
 1050e50:	0f 8d 4a 09 00 00    	jge    10517a0 <my.json::read_value+0xf20>
 1050e56:	4c 89 e8             	mov    %r13,%rax
 1050e59:	48 c1 f8 3f          	sar    $0x3f,%rax
 1050e5d:	48 21 d0             	and    %rdx,%rax
 1050e60:	4c 01 e8             	add    %r13,%rax
 1050e63:	48 39 d0             	cmp    %rdx,%rax
 1050e66:	0f 83 8f 0e 00 00    	jae    1051cfb <my.json::read_value+0x147b>
 1050e6c:	80 7c 03 20 7d       	cmpb   $0x7d,0x20(%rbx,%rax,1)
 1050e71:	0f 84 d0 08 00 00    	je     1051747 <my.json::read_value+0xec7>
 1050e77:	48 ff 44 24 28       	incq   0x28(%rsp)
 1050e7c:	49 bc 00 26 00 00 01 	movabs $0x100002600,%r12
 1050e83:	00 00 00 
 1050e86:	49 89 de             	mov    %rbx,%r14
 1050e89:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1050e90:	49 39 d5             	cmp    %rdx,%r13
 1050e93:	7d 38                	jge    1050ecd <my.json::read_value+0x64d>
 1050e95:	4c 89 e8             	mov    %r13,%rax
 1050e98:	48 c1 f8 3f          	sar    $0x3f,%rax
 1050e9c:	48 21 d0             	and    %rdx,%rax
 1050e9f:	4a 8d 0c 28          	lea    (%rax,%r13,1),%rcx
 1050ea3:	48 39 d1             	cmp    %rdx,%rcx
 1050ea6:	0f 83 32 0d 00 00    	jae    1051bde <my.json::read_value+0x135e>
 1050eac:	48 01 c3             	add    %rax,%rbx
 1050eaf:	41 0f b6 44 1d 20    	movzbl 0x20(%r13,%rbx,1),%eax
 1050eb5:	48 83 f8 20          	cmp    $0x20,%rax
 1050eb9:	77 12                	ja     1050ecd <my.json::read_value+0x64d>
 1050ebb:	49 0f a3 c4          	bt     %rax,%r12
 1050ebf:	73 0c                	jae    1050ecd <my.json::read_value+0x64d>
 1050ec1:	49 ff c5             	inc    %r13
 1050ec4:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1050ec8:	4c 89 f3             	mov    %r14,%rbx
 1050ecb:	eb c3                	jmp    1050e90 <my.json::read_value+0x610>
 1050ecd:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1050ed1:	49 39 d5             	cmp    %rdx,%r13
 1050ed4:	0f 8d 44 0b 00 00    	jge    1051a1e <my.json::read_value+0x119e>
 1050eda:	4c 89 e8             	mov    %r13,%rax
 1050edd:	48 c1 f8 3f          	sar    $0x3f,%rax
 1050ee1:	48 21 d0             	and    %rdx,%rax
 1050ee4:	4c 01 e8             	add    %r13,%rax
 1050ee7:	48 39 d0             	cmp    %rdx,%rax
 1050eea:	0f 83 75 0d 00 00    	jae    1051c65 <my.json::read_value+0x13e5>
 1050ef0:	41 80 7c 06 20 22    	cmpb   $0x22,0x20(%r14,%rax,1)
 1050ef6:	0f 85 22 0b 00 00    	jne    1051a1e <my.json::read_value+0x119e>
 1050efc:	48 8d bc 24 80 00 00 	lea    0x80(%rsp),%rdi
 1050f03:	00 
 1050f04:	4c 89 f6             	mov    %r14,%rsi
 1050f07:	4c 89 ea             	mov    %r13,%rdx
 1050f0a:	e8 51 10 00 00       	call   1051f60 <my.json::read_string>
 1050f0f:	4c 8b bc 24 88 00 00 	mov    0x88(%rsp),%r15
 1050f16:	00 
 1050f17:	4c 8b ac 24 98 00 00 	mov    0x98(%rsp),%r13
 1050f1e:	00 
 1050f1f:	4c 8b b4 24 90 00 00 	mov    0x90(%rsp),%r14
 1050f26:	00 
 1050f27:	80 bc 24 80 00 00 00 	cmpb   $0x1,0x80(%rsp)
 1050f2e:	01 
 1050f2f:	0f 84 3f 0c 00 00    	je     1051b74 <my.json::read_value+0x12f4>
 1050f35:	4c 89 7c 24 38       	mov    %r15,0x38(%rsp)
 1050f3a:	41 f6 47 01 02       	testb  $0x2,0x1(%r15)
 1050f3f:	4c 89 7c 24 20       	mov    %r15,0x20(%rsp)
 1050f44:	75 0a                	jne    1050f50 <my.json::read_value+0x6d0>
 1050f46:	4c 89 ff             	mov    %r15,%rdi
 1050f49:	e8 32 e9 fc ff       	call   101f880 <myl_core_str_hash>
 1050f4e:	eb 04                	jmp    1050f54 <my.json::read_value+0x6d4>
 1050f50:	41 8b 47 18          	mov    0x18(%r15),%eax
 1050f54:	89 c0                	mov    %eax,%eax
 1050f56:	48 b9 15 7c 4a 7f b9 	movabs $0x9e3779b97f4a7c15,%rcx
 1050f5d:	79 37 9e 
 1050f60:	48 0f af c1          	imul   %rcx,%rax
 1050f64:	48 89 c3             	mov    %rax,%rbx
 1050f67:	48 c1 eb 20          	shr    $0x20,%rbx
 1050f6b:	48 31 c3             	xor    %rax,%rbx
 1050f6e:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 1050f73:	48 8b 48 18          	mov    0x18(%rax),%rcx
 1050f77:	48 8b 41 08          	mov    0x8(%rcx),%rax
 1050f7b:	48 85 c0             	test   %rax,%rax
 1050f7e:	0f 84 de 00 00 00    	je     1051062 <my.json::read_value+0x7e2>
 1050f84:	8b 08                	mov    (%rax),%ecx
 1050f86:	f3 0f bc d1          	tzcnt  %ecx,%edx
 1050f8a:	f6 da                	neg    %dl
 1050f8c:	c4 62 eb f7 fb       	shrx   %rdx,%rbx,%r15
 1050f91:	44 8d 61 ff          	lea    -0x1(%rcx),%r12d
 1050f95:	c4 a1 7a 6f 4c 38 10 	vmovdqu 0x10(%rax,%r15,1),%xmm1
 1050f9c:	48 89 5c 24 30       	mov    %rbx,0x30(%rsp)
 1050fa1:	89 da                	mov    %ebx,%edx
 1050fa3:	80 e2 7f             	and    $0x7f,%dl
 1050fa6:	c5 f9 6e c2          	vmovd  %edx,%xmm0
 1050faa:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1050faf:	c5 f9 7f 8c 24 c0 00 	vmovdqa %xmm1,0xc0(%rsp)
 1050fb6:	00 00 
 1050fb8:	c5 f1 74 c0          	vpcmpeqb %xmm0,%xmm1,%xmm0
 1050fbc:	c5 f9 d7 d0          	vpmovmskb %xmm0,%edx
 1050fc0:	85 d2                	test   %edx,%edx
 1050fc2:	74 71                	je     1051035 <my.json::read_value+0x7b5>
 1050fc4:	83 c1 1e             	add    $0x1e,%ecx
 1050fc7:	83 e1 f0             	and    $0xfffffff0,%ecx
 1050fca:	48 8d 2c 08          	lea    (%rax,%rcx,1),%rbp
 1050fce:	48 83 c5 10          	add    $0x10,%rbp
 1050fd2:	0f b7 da             	movzwl %dx,%ebx
 1050fd5:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050fdc:	0f 1f 84 00 00 00 00 
 1050fe3:	00 
 1050fe4:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050feb:	0f 1f 84 00 00 00 00 
 1050ff2:	00 
 1050ff3:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1050ffa:	84 00 00 00 00 00 
 1051000:	f3 0f bc c3          	tzcnt  %ebx,%eax
 1051004:	44 01 f8             	add    %r15d,%eax
 1051007:	44 21 e0             	and    %r12d,%eax
 105100a:	8b 44 85 00          	mov    0x0(%rbp,%rax,4),%eax
 105100e:	48 8d 04 40          	lea    (%rax,%rax,2),%rax
 1051012:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 1051017:	48 8b 7c c1 20       	mov    0x20(%rcx,%rax,8),%rdi
 105101c:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 1051021:	e8 da e9 fc ff       	call   101fa00 <myl_core_str_eq>
 1051026:	84 c0                	test   %al,%al
 1051028:	0f 85 29 07 00 00    	jne    1051757 <my.json::read_value+0xed7>
 105102e:	c4 e2 60 f3 cb       	blsr   %ebx,%ebx
 1051033:	75 cb                	jne    1051000 <my.json::read_value+0x780>
 1051035:	c5 f9 6f 84 24 c0 00 	vmovdqa 0xc0(%rsp),%xmm0
 105103c:	00 00 
 105103e:	c5 f9 74 05 9a 33 fb 	vpcmpeqb -0x4cc66(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0x50>
 1051045:	ff 
 1051046:	c5 f9 d7 c0          	vpmovmskb %xmm0,%eax
 105104a:	85 c0                	test   %eax,%eax
 105104c:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 1051051:	74 1a                	je     105106d <my.json::read_value+0x7ed>
 1051053:	f3 0f bc e8          	tzcnt  %eax,%ebp
 1051057:	44 01 fd             	add    %r15d,%ebp
 105105a:	44 21 e5             	and    %r12d,%ebp
 105105d:	48 f7 d5             	not    %rbp
 1051060:	eb 2c                	jmp    105108e <my.json::read_value+0x80e>
 1051062:	48 83 79 18 00       	cmpq   $0x0,0x18(%rcx)
 1051067:	0f 84 d2 01 00 00    	je     105123f <my.json::read_value+0x9bf>
 105106d:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1051072:	48 8d 74 24 38       	lea    0x38(%rsp),%rsi
 1051077:	48 89 da             	mov    %rbx,%rdx
 105107a:	e8 c1 cf fc ff       	call   101e040 <myl_core_dict_find>
 105107f:	49 89 c7             	mov    %rax,%r15
 1051082:	4c 89 fd             	mov    %r15,%rbp
 1051085:	4d 85 ff             	test   %r15,%r15
 1051088:	0f 89 c9 06 00 00    	jns    1051757 <my.json::read_value+0xed7>
 105108e:	49 8b 56 08          	mov    0x8(%r14),%rdx
 1051092:	49 bc 00 26 00 00 01 	movabs $0x100002600,%r12
 1051099:	00 00 00 
 105109c:	49 39 d5             	cmp    %rdx,%r13
 105109f:	7d 57                	jge    10510f8 <my.json::read_value+0x878>
 10510a1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10510a8:	0f 1f 84 00 00 00 00 
 10510af:	00 
 10510b0:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10510b7:	0f 1f 84 00 00 00 00 
 10510be:	00 
 10510bf:	90                   	nop
 10510c0:	4c 89 e8             	mov    %r13,%rax
 10510c3:	48 c1 f8 3f          	sar    $0x3f,%rax
 10510c7:	48 21 d0             	and    %rdx,%rax
 10510ca:	4a 8d 0c 28          	lea    (%rax,%r13,1),%rcx
 10510ce:	48 39 d1             	cmp    %rdx,%rcx
 10510d1:	0f 83 16 0b 00 00    	jae    1051bed <my.json::read_value+0x136d>
 10510d7:	4c 01 f0             	add    %r14,%rax
 10510da:	41 0f b6 44 05 20    	movzbl 0x20(%r13,%rax,1),%eax
 10510e0:	48 83 f8 20          	cmp    $0x20,%rax
 10510e4:	77 12                	ja     10510f8 <my.json::read_value+0x878>
 10510e6:	49 0f a3 c4          	bt     %rax,%r12
 10510ea:	73 0c                	jae    10510f8 <my.json::read_value+0x878>
 10510ec:	49 ff c5             	inc    %r13
 10510ef:	49 8b 56 08          	mov    0x8(%r14),%rdx
 10510f3:	49 39 d5             	cmp    %rdx,%r13
 10510f6:	7c c8                	jl     10510c0 <my.json::read_value+0x840>
 10510f8:	49 8b 56 08          	mov    0x8(%r14),%rdx
 10510fc:	49 39 d5             	cmp    %rdx,%r13
 10510ff:	0f 8d 3a 09 00 00    	jge    1051a3f <my.json::read_value+0x11bf>
 1051105:	4c 89 e8             	mov    %r13,%rax
 1051108:	48 c1 f8 3f          	sar    $0x3f,%rax
 105110c:	48 21 d0             	and    %rdx,%rax
 105110f:	4c 01 e8             	add    %r13,%rax
 1051112:	48 39 d0             	cmp    %rdx,%rax
 1051115:	0f 83 59 0b 00 00    	jae    1051c74 <my.json::read_value+0x13f4>
 105111b:	41 80 7c 06 20 3a    	cmpb   $0x3a,0x20(%r14,%rax,1)
 1051121:	0f 85 18 09 00 00    	jne    1051a3f <my.json::read_value+0x11bf>
 1051127:	49 ff c5             	inc    %r13
 105112a:	48 8d 7c 24 40       	lea    0x40(%rsp),%rdi
 105112f:	4c 89 f6             	mov    %r14,%rsi
 1051132:	4c 89 ea             	mov    %r13,%rdx
 1051135:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 105113a:	e8 41 f7 ff ff       	call   1050880 <my.json::read_value>
 105113f:	4c 8b 7c 24 48       	mov    0x48(%rsp),%r15
 1051144:	48 8b 5c 24 58       	mov    0x58(%rsp),%rbx
 1051149:	4c 8b 6c 24 60       	mov    0x60(%rsp),%r13
 105114e:	80 7c 24 40 01       	cmpb   $0x1,0x40(%rsp)
 1051153:	0f 84 2c 0a 00 00    	je     1051b85 <my.json::read_value+0x1305>
 1051159:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 105115e:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
 1051163:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
 1051168:	41 0f b6 cf          	movzbl %r15b,%ecx
 105116c:	48 89 4c 24 70       	mov    %rcx,0x70(%rsp)
 1051171:	48 89 44 24 78       	mov    %rax,0x78(%rsp)
 1051176:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 105117b:	48 89 ee             	mov    %rbp,%rsi
 105117e:	48 8d 54 24 68       	lea    0x68(%rsp),%rdx
 1051183:	48 8d 4c 24 70       	lea    0x70(%rsp),%rcx
 1051188:	45 31 c0             	xor    %r8d,%r8d
 105118b:	e8 30 d5 fc ff       	call   101e6c0 <myl_core_dict_insert>
 1051190:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 1051195:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105119c:	0f 1f 84 00 00 00 00 
 10511a3:	00 
 10511a4:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10511ab:	0f 1f 84 00 00 00 00 
 10511b2:	00 
 10511b3:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10511ba:	84 00 00 00 00 00 
 10511c0:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 10511c4:	49 39 d5             	cmp    %rdx,%r13
 10511c7:	7d 31                	jge    10511fa <my.json::read_value+0x97a>
 10511c9:	4c 89 e8             	mov    %r13,%rax
 10511cc:	48 c1 f8 3f          	sar    $0x3f,%rax
 10511d0:	48 21 d0             	and    %rdx,%rax
 10511d3:	4a 8d 0c 28          	lea    (%rax,%r13,1),%rcx
 10511d7:	48 39 d1             	cmp    %rdx,%rcx
 10511da:	0f 83 1c 0a 00 00    	jae    1051bfc <my.json::read_value+0x137c>
 10511e0:	48 01 d8             	add    %rbx,%rax
 10511e3:	41 0f b6 44 05 20    	movzbl 0x20(%r13,%rax,1),%eax
 10511e9:	48 83 f8 20          	cmp    $0x20,%rax
 10511ed:	77 0b                	ja     10511fa <my.json::read_value+0x97a>
 10511ef:	49 0f a3 c4          	bt     %rax,%r12
 10511f3:	73 05                	jae    10511fa <my.json::read_value+0x97a>
 10511f5:	49 ff c5             	inc    %r13
 10511f8:	eb c6                	jmp    10511c0 <my.json::read_value+0x940>
 10511fa:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 10511fe:	49 39 d5             	cmp    %rdx,%r13
 1051201:	0f 8d 84 08 00 00    	jge    1051a8b <my.json::read_value+0x120b>
 1051207:	4c 89 e8             	mov    %r13,%rax
 105120a:	48 c1 f8 3f          	sar    $0x3f,%rax
 105120e:	48 21 d0             	and    %rdx,%rax
 1051211:	4c 01 e8             	add    %r13,%rax
 1051214:	48 39 d0             	cmp    %rdx,%rax
 1051217:	0f 83 66 0a 00 00    	jae    1051c83 <my.json::read_value+0x1403>
 105121d:	0f b6 44 03 20       	movzbl 0x20(%rbx,%rax,1),%eax
 1051222:	83 f8 2c             	cmp    $0x2c,%eax
 1051225:	0f 85 13 05 00 00    	jne    105173e <my.json::read_value+0xebe>
 105122b:	49 ff c5             	inc    %r13
 105122e:	49 89 de             	mov    %rbx,%r14
 1051231:	49 39 d5             	cmp    %rdx,%r13
 1051234:	0f 8c 56 fc ff ff    	jl     1050e90 <my.json::read_value+0x610>
 105123a:	e9 61 05 00 00       	jmp    10517a0 <my.json::read_value+0xf20>
 105123f:	48 8b 51 20          	mov    0x20(%rcx),%rdx
 1051243:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 105124a:	48 85 d2             	test   %rdx,%rdx
 105124d:	0f 84 3b fe ff ff    	je     105108e <my.json::read_value+0x80e>
 1051253:	4c 8b 61 10          	mov    0x10(%rcx),%r12
 1051257:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105125c:	48 8d 68 20          	lea    0x20(%rax),%rbp
 1051260:	45 31 ff             	xor    %r15d,%r15d
 1051263:	48 89 54 24 30       	mov    %rdx,0x30(%rsp)
 1051268:	eb 22                	jmp    105128c <my.json::read_value+0xa0c>
 105126a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1051271:	0f 1f 84 00 00 00 00 
 1051278:	00 
 1051279:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1051280:	49 ff c7             	inc    %r15
 1051283:	48 83 c5 18          	add    $0x18,%rbp
 1051287:	4c 39 fa             	cmp    %r15,%rdx
 105128a:	74 22                	je     10512ae <my.json::read_value+0xa2e>
 105128c:	4b 39 1c fc          	cmp    %rbx,(%r12,%r15,8)
 1051290:	75 ee                	jne    1051280 <my.json::read_value+0xa00>
 1051292:	48 8b 7d 00          	mov    0x0(%rbp),%rdi
 1051296:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 105129b:	e8 60 e7 fc ff       	call   101fa00 <myl_core_str_eq>
 10512a0:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 10512a5:	84 c0                	test   %al,%al
 10512a7:	74 d7                	je     1051280 <my.json::read_value+0xa00>
 10512a9:	e9 d4 fd ff ff       	jmp    1051082 <my.json::read_value+0x802>
 10512ae:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 10512b5:	e9 d4 fd ff ff       	jmp    105108e <my.json::read_value+0x80e>
 10512ba:	45 31 c0             	xor    %r8d,%r8d
 10512bd:	80 f9 2d             	cmp    $0x2d,%cl
 10512c0:	41 0f 94 c0          	sete   %r8b
 10512c4:	49 b9 34 33 33 33 33 	movabs $0xf333333333333334,%r9
 10512cb:	33 33 f3 
 10512ce:	49 83 c0 07          	add    $0x7,%r8
 10512d2:	41 b3 01             	mov    $0x1,%r11b
 10512d5:	45 31 d2             	xor    %r10d,%r10d
 10512d8:	eb 35                	jmp    105130f <my.json::read_value+0xa8f>
 10512da:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10512e1:	0f 1f 84 00 00 00 00 
 10512e8:	00 
 10512e9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10512f0:	0f 1f 84 00 00 00 00 
 10512f7:	00 
 10512f8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 10512ff:	00 
 1051300:	45 31 db             	xor    %r11d,%r11d
 1051303:	49 ff c6             	inc    %r14
 1051306:	4c 39 f2             	cmp    %r14,%rdx
 1051309:	0f 84 53 01 00 00    	je     1051462 <my.json::read_value+0xbe2>
 105130f:	4c 89 f0             	mov    %r14,%rax
 1051312:	48 c1 f8 3f          	sar    $0x3f,%rax
 1051316:	48 21 d0             	and    %rdx,%rax
 1051319:	4a 8d 34 30          	lea    (%rax,%r14,1),%rsi
 105131d:	48 39 d6             	cmp    %rdx,%rsi
 1051320:	0f 83 e5 08 00 00    	jae    1051c0b <my.json::read_value+0x138b>
 1051326:	48 01 f8             	add    %rdi,%rax
 1051329:	41 0f b6 04 06       	movzbl (%r14,%rax,1),%eax
 105132e:	8d 70 c6             	lea    -0x3a(%rax),%esi
 1051331:	40 80 fe f5          	cmp    $0xf5,%sil
 1051335:	0f 86 22 01 00 00    	jbe    105145d <my.json::read_value+0xbdd>
 105133b:	49 8d 71 ff          	lea    -0x1(%r9),%rsi
 105133f:	49 39 f2             	cmp    %rsi,%r10
 1051342:	40 0f 9f c6          	setg   %sil
 1051346:	41 84 f3             	test   %sil,%r11b
 1051349:	74 b5                	je     1051300 <my.json::read_value+0xa80>
 105134b:	48 83 c0 d0          	add    $0xffffffffffffffd0,%rax
 105134f:	4d 39 ca             	cmp    %r9,%r10
 1051352:	75 2c                	jne    1051380 <my.json::read_value+0xb00>
 1051354:	44 39 c0             	cmp    %r8d,%eax
 1051357:	7e 27                	jle    1051380 <my.json::read_value+0xb00>
 1051359:	45 31 db             	xor    %r11d,%r11d
 105135c:	4d 89 ca             	mov    %r9,%r10
 105135f:	eb a2                	jmp    1051303 <my.json::read_value+0xa83>
 1051361:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1051368:	0f 1f 84 00 00 00 00 
 105136f:	00 
 1051370:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1051377:	0f 1f 84 00 00 00 00 
 105137e:	00 
 105137f:	90                   	nop
 1051380:	4d 01 d2             	add    %r10,%r10
 1051383:	4b 8d 34 92          	lea    (%r10,%r10,4),%rsi
 1051387:	49 89 f2             	mov    %rsi,%r10
 105138a:	49 29 c2             	sub    %rax,%r10
 105138d:	41 b3 01             	mov    $0x1,%r11b
 1051390:	0f 81 6d ff ff ff    	jno    1051303 <my.json::read_value+0xa83>
 1051396:	48 8d 3d 93 f3 00 00 	lea    0xf393(%rip),%rdi        # 1060730 <core_durable_error.verbs+0x1b00>
 105139d:	48 89 c2             	mov    %rax,%rdx
 10513a0:	e8 9b 75 fc ff       	call   1018940 <myl_core_trap>
 10513a5:	48 8d bc 24 a0 00 00 	lea    0xa0(%rsp),%rdi
 10513ac:	00 
 10513ad:	48 89 de             	mov    %rbx,%rsi
 10513b0:	4c 89 fa             	mov    %r15,%rdx
 10513b3:	e8 a8 0b 00 00       	call   1051f60 <my.json::read_string>
 10513b8:	48 8b 84 24 a8 00 00 	mov    0xa8(%rsp),%rax
 10513bf:	00 
 10513c0:	4c 8b bc 24 b8 00 00 	mov    0xb8(%rsp),%r15
 10513c7:	00 
 10513c8:	48 8b 8c 24 b0 00 00 	mov    0xb0(%rsp),%rcx
 10513cf:	00 
 10513d0:	80 bc 24 a0 00 00 00 	cmpb   $0x1,0xa0(%rsp)
 10513d7:	01 
 10513d8:	0f 84 9d 05 00 00    	je     105197b <my.json::read_value+0x10fb>
 10513de:	49 c7 45 00 00 00 00 	movq   $0x0,0x0(%r13)
 10513e5:	00 
 10513e6:	49 c7 45 08 04 00 00 	movq   $0x4,0x8(%r13)
 10513ed:	00 
 10513ee:	49 89 45 10          	mov    %rax,0x10(%r13)
 10513f2:	49 89 4d 18          	mov    %rcx,0x18(%r13)
 10513f6:	e9 eb 06 00 00       	jmp    1051ae6 <my.json::read_value+0x1266>
 10513fb:	48 8d 15 5e 8a fb ff 	lea    -0x475a2(%rip),%rdx        # 1009e60 <core_number_pairs+0x2bc0>
 1051402:	48 89 df             	mov    %rbx,%rdi
 1051405:	4c 89 fe             	mov    %r15,%rsi
 1051408:	e8 73 09 00 00       	call   1051d80 <my.json::parse_error>
 105140d:	48 8d 3d 8c e9 00 00 	lea    0xe98c(%rip),%rdi        # 105fda0 <core_durable_error.verbs+0x1170>
 1051414:	e8 e7 98 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 1051419:	49 c7 45 00 01 00 00 	movq   $0x1,0x0(%r13)
 1051420:	00 
 1051421:	49 89 45 08          	mov    %rax,0x8(%r13)
 1051425:	49 89 5d 18          	mov    %rbx,0x18(%r13)
 1051429:	e9 b8 06 00 00       	jmp    1051ae6 <my.json::read_value+0x1266>
 105142e:	48 8d 15 8b 8a fb ff 	lea    -0x47575(%rip),%rdx        # 1009ec0 <core_number_pairs+0x2c20>
 1051435:	48 89 df             	mov    %rbx,%rdi
 1051438:	4c 89 fe             	mov    %r15,%rsi
 105143b:	e8 40 09 00 00       	call   1051d80 <my.json::parse_error>
 1051440:	48 8d 3d d9 ea 00 00 	lea    0xead9(%rip),%rdi        # 105ff20 <core_durable_error.verbs+0x12f0>
 1051447:	e8 b4 98 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 105144c:	49 c7 45 00 01 00 00 	movq   $0x1,0x0(%r13)
 1051453:	00 
 1051454:	49 89 45 08          	mov    %rax,0x8(%r13)
 1051458:	e9 90 04 00 00       	jmp    10518ed <my.json::read_value+0x106d>
 105145d:	4c 89 f5             	mov    %r14,%rbp
 1051460:	eb 03                	jmp    1051465 <my.json::read_value+0xbe5>
 1051462:	48 89 d5             	mov    %rdx,%rbp
 1051465:	80 f9 2d             	cmp    $0x2d,%cl
 1051468:	0f 94 c0             	sete   %al
 105146b:	41 80 f3 01          	xor    $0x1,%r11b
 105146f:	44 08 d8             	or     %r11b,%al
 1051472:	a8 01                	test   $0x1,%al
 1051474:	75 12                	jne    1051488 <my.json::read_value+0xc08>
 1051476:	4c 89 d0             	mov    %r10,%rax
 1051479:	48 f7 d8             	neg    %rax
 105147c:	0f 80 c4 08 00 00    	jo     1051d46 <my.json::read_value+0x14c6>
 1051482:	45 31 db             	xor    %r11d,%r11d
 1051485:	49 89 c2             	mov    %rax,%r10
 1051488:	48 39 d5             	cmp    %rdx,%rbp
 105148b:	4c 89 6c 24 08       	mov    %r13,0x8(%rsp)
 1051490:	0f 8d c0 00 00 00    	jge    1051556 <my.json::read_value+0xcd6>
 1051496:	48 89 e8             	mov    %rbp,%rax
 1051499:	48 c1 f8 3f          	sar    $0x3f,%rax
 105149d:	48 21 d0             	and    %rdx,%rax
 10514a0:	48 01 e8             	add    %rbp,%rax
 10514a3:	48 39 d0             	cmp    %rdx,%rax
 10514a6:	0f 83 5e 08 00 00    	jae    1051d0a <my.json::read_value+0x148a>
 10514ac:	80 3c 07 2e          	cmpb   $0x2e,(%rdi,%rax,1)
 10514b0:	0f 85 a0 00 00 00    	jne    1051556 <my.json::read_value+0xcd6>
 10514b6:	4c 8d 6d 01          	lea    0x1(%rbp),%r13
 10514ba:	49 39 d5             	cmp    %rdx,%r13
 10514bd:	0f 8d 6a 04 00 00    	jge    105192d <my.json::read_value+0x10ad>
 10514c3:	31 c0                	xor    %eax,%eax
 10514c5:	48 83 fd ff          	cmp    $0xffffffffffffffff,%rbp
 10514c9:	48 0f 4c c2          	cmovl  %rdx,%rax
 10514cd:	4c 01 e8             	add    %r13,%rax
 10514d0:	48 39 d0             	cmp    %rdx,%rax
 10514d3:	0f 83 7e 08 00 00    	jae    1051d57 <my.json::read_value+0x14d7>
 10514d9:	0f b6 04 07          	movzbl (%rdi,%rax,1),%eax
 10514dd:	04 d0                	add    $0xd0,%al
 10514df:	3c 09                	cmp    $0x9,%al
 10514e1:	0f 87 46 04 00 00    	ja     105192d <my.json::read_value+0x10ad>
 10514e7:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10514ee:	0f 1f 84 00 00 00 00 
 10514f5:	00 
 10514f6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 10514fd:	00 00 00 
 1051500:	48 8d 75 01          	lea    0x1(%rbp),%rsi
 1051504:	48 89 f0             	mov    %rsi,%rax
 1051507:	48 c1 f8 3f          	sar    $0x3f,%rax
 105150b:	48 21 d0             	and    %rdx,%rax
 105150e:	48 8d 0c 28          	lea    (%rax,%rbp,1),%rcx
 1051512:	48 ff c1             	inc    %rcx
 1051515:	48 39 d1             	cmp    %rdx,%rcx
 1051518:	0f 83 74 07 00 00    	jae    1051c92 <my.json::read_value+0x1412>
 105151e:	49 01 c4             	add    %rax,%r12
 1051521:	42 0f b6 4c 25 21    	movzbl 0x21(%rbp,%r12,1),%ecx
 1051527:	80 c1 d0             	add    $0xd0,%cl
 105152a:	b8 01 00 00 00       	mov    $0x1,%eax
 105152f:	80 f9 0a             	cmp    $0xa,%cl
 1051532:	73 16                	jae    105154a <my.json::read_value+0xcca>
 1051534:	49 89 ed             	mov    %rbp,%r13
 1051537:	49 83 c5 02          	add    $0x2,%r13
 105153b:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105153f:	48 89 f5             	mov    %rsi,%rbp
 1051542:	49 89 dc             	mov    %rbx,%r12
 1051545:	49 39 d5             	cmp    %rdx,%r13
 1051548:	7c b6                	jl     1051500 <my.json::read_value+0xc80>
 105154a:	31 c9                	xor    %ecx,%ecx
 105154c:	80 f9 01             	cmp    $0x1,%cl
 105154f:	75 15                	jne    1051566 <my.json::read_value+0xce6>
 1051551:	e9 0c 04 00 00       	jmp    1051962 <my.json::read_value+0x10e2>
 1051556:	31 c9                	xor    %ecx,%ecx
 1051558:	31 c0                	xor    %eax,%eax
 105155a:	49 89 ed             	mov    %rbp,%r13
 105155d:	80 f9 01             	cmp    $0x1,%cl
 1051560:	0f 84 fc 03 00 00    	je     1051962 <my.json::read_value+0x10e2>
 1051566:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105156a:	49 39 d5             	cmp    %rdx,%r13
 105156d:	0f 8d 15 01 00 00    	jge    1051688 <my.json::read_value+0xe08>
 1051573:	4c 89 e9             	mov    %r13,%rcx
 1051576:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105157a:	48 21 d1             	and    %rdx,%rcx
 105157d:	4c 01 e9             	add    %r13,%rcx
 1051580:	48 39 d1             	cmp    %rdx,%rcx
 1051583:	0f 83 90 07 00 00    	jae    1051d19 <my.json::read_value+0x1499>
 1051589:	0f b6 4c 0b 20       	movzbl 0x20(%rbx,%rcx,1),%ecx
 105158e:	83 c9 20             	or     $0x20,%ecx
 1051591:	83 f9 65             	cmp    $0x65,%ecx
 1051594:	0f 85 ee 00 00 00    	jne    1051688 <my.json::read_value+0xe08>
 105159a:	4d 8d 75 01          	lea    0x1(%r13),%r14
 105159e:	49 39 d6             	cmp    %rdx,%r14
 10515a1:	7d 2c                	jge    10515cf <my.json::read_value+0xd4f>
 10515a3:	31 c9                	xor    %ecx,%ecx
 10515a5:	49 83 fd ff          	cmp    $0xffffffffffffffff,%r13
 10515a9:	48 0f 4c ca          	cmovl  %rdx,%rcx
 10515ad:	4c 01 f1             	add    %r14,%rcx
 10515b0:	48 39 d1             	cmp    %rdx,%rcx
 10515b3:	0f 83 ad 07 00 00    	jae    1051d66 <my.json::read_value+0x14e6>
 10515b9:	0f b6 4c 0b 20       	movzbl 0x20(%rbx,%rcx,1),%ecx
 10515be:	83 f9 2d             	cmp    $0x2d,%ecx
 10515c1:	74 05                	je     10515c8 <my.json::read_value+0xd48>
 10515c3:	83 f9 2b             	cmp    $0x2b,%ecx
 10515c6:	75 07                	jne    10515cf <my.json::read_value+0xd4f>
 10515c8:	49 83 c5 02          	add    $0x2,%r13
 10515cc:	4d 89 ee             	mov    %r13,%r14
 10515cf:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 10515d3:	49 39 d6             	cmp    %rdx,%r14
 10515d6:	4c 8b 6c 24 08       	mov    0x8(%rsp),%r13
 10515db:	0f 8d 08 02 00 00    	jge    10517e9 <my.json::read_value+0xf69>
 10515e1:	4c 89 f1             	mov    %r14,%rcx
 10515e4:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10515e8:	48 21 d1             	and    %rdx,%rcx
 10515eb:	4c 01 f1             	add    %r14,%rcx
 10515ee:	48 39 d1             	cmp    %rdx,%rcx
 10515f1:	0f 83 31 07 00 00    	jae    1051d28 <my.json::read_value+0x14a8>
 10515f7:	0f b6 4c 0b 20       	movzbl 0x20(%rbx,%rcx,1),%ecx
 10515fc:	80 c1 d0             	add    $0xd0,%cl
 10515ff:	80 f9 09             	cmp    $0x9,%cl
 1051602:	0f 87 e1 01 00 00    	ja     10517e9 <my.json::read_value+0xf69>
 1051608:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105160f:	0f 1f 84 00 00 00 00 
 1051616:	00 
 1051617:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105161e:	0f 1f 84 00 00 00 00 
 1051625:	00 
 1051626:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105162d:	0f 1f 84 00 00 00 00 
 1051634:	00 
 1051635:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 105163c:	00 00 00 00 
 1051640:	4c 89 f1             	mov    %r14,%rcx
 1051643:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1051647:	48 21 d1             	and    %rdx,%rcx
 105164a:	4a 8d 34 31          	lea    (%rcx,%r14,1),%rsi
 105164e:	48 39 d6             	cmp    %rdx,%rsi
 1051651:	0f 83 ff 05 00 00    	jae    1051c56 <my.json::read_value+0x13d6>
 1051657:	48 89 da             	mov    %rbx,%rdx
 105165a:	48 01 ca             	add    %rcx,%rdx
 105165d:	41 0f b6 54 16 20    	movzbl 0x20(%r14,%rdx,1),%edx
 1051663:	80 c2 d0             	add    $0xd0,%dl
 1051666:	b9 01 00 00 00       	mov    $0x1,%ecx
 105166b:	80 fa 0a             	cmp    $0xa,%dl
 105166e:	73 0c                	jae    105167c <my.json::read_value+0xdfc>
 1051670:	49 ff c6             	inc    %r14
 1051673:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1051677:	49 39 d6             	cmp    %rdx,%r14
 105167a:	7c c4                	jl     1051640 <my.json::read_value+0xdc0>
 105167c:	31 d2                	xor    %edx,%edx
 105167e:	80 fa 01             	cmp    $0x1,%dl
 1051681:	75 1a                	jne    105169d <my.json::read_value+0xe1d>
 1051683:	e9 a3 01 00 00       	jmp    105182b <my.json::read_value+0xfab>
 1051688:	31 d2                	xor    %edx,%edx
 105168a:	31 c9                	xor    %ecx,%ecx
 105168c:	4d 89 ee             	mov    %r13,%r14
 105168f:	4c 8b 6c 24 08       	mov    0x8(%rsp),%r13
 1051694:	80 fa 01             	cmp    $0x1,%dl
 1051697:	0f 84 8e 01 00 00    	je     105182b <my.json::read_value+0xfab>
 105169d:	09 c1                	or     %eax,%ecx
 105169f:	41 08 cb             	or     %cl,%r11b
 10516a2:	41 f6 c3 01          	test   $0x1,%r11b
 10516a6:	74 27                	je     10516cf <my.json::read_value+0xe4f>
 10516a8:	48 89 df             	mov    %rbx,%rdi
 10516ab:	4c 89 fe             	mov    %r15,%rsi
 10516ae:	4c 89 f2             	mov    %r14,%rdx
 10516b1:	e8 fa 6b 00 00       	call   10582b0 <myl_core_parse_float_range>
 10516b6:	3c 01                	cmp    $0x1,%al
 10516b8:	0f 85 13 03 00 00    	jne    10519d1 <my.json::read_value+0x1151>
 10516be:	c4 c1 f9 7e c2       	vmovq  %xmm0,%r10
 10516c3:	b8 03 00 00 00       	mov    $0x3,%eax
 10516c8:	31 c9                	xor    %ecx,%ecx
 10516ca:	e9 37 03 00 00       	jmp    1051a06 <my.json::read_value+0x1186>
 10516cf:	b8 02 00 00 00       	mov    $0x2,%eax
 10516d4:	31 c9                	xor    %ecx,%ecx
 10516d6:	e9 2b 03 00 00       	jmp    1051a06 <my.json::read_value+0x1186>
 10516db:	83 f9 5d             	cmp    $0x5d,%ecx
 10516de:	0f 85 b8 02 00 00    	jne    105199c <my.json::read_value+0x111c>
 10516e4:	4d 89 66 08          	mov    %r12,0x8(%r14)
 10516e8:	4c 8b 6c 24 08       	mov    0x8(%rsp),%r13
 10516ed:	48 ff c2             	inc    %rdx
 10516f0:	b8 05 00 00 00       	mov    $0x5,%eax
 10516f5:	31 c9                	xor    %ecx,%ecx
 10516f7:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 10516fb:	49 89 45 08          	mov    %rax,0x8(%r13)
 10516ff:	4d 89 75 10          	mov    %r14,0x10(%r13)
 1051703:	49 89 5d 18          	mov    %rbx,0x18(%r13)
 1051707:	49 89 d7             	mov    %rdx,%r15
 105170a:	e9 d7 03 00 00       	jmp    1051ae6 <my.json::read_value+0x1266>
 105170f:	48 8d 15 0a 8f fb ff 	lea    -0x470f6(%rip),%rdx        # 100a620 <core_number_pairs+0x3380>
 1051716:	48 89 df             	mov    %rbx,%rdi
 1051719:	4c 89 f6             	mov    %r14,%rsi
 105171c:	e8 5f 06 00 00       	call   1051d80 <my.json::parse_error>
 1051721:	48 8d 3d 18 ef 00 00 	lea    0xef18(%rip),%rdi        # 1060640 <core_durable_error.verbs+0x1a10>
 1051728:	e8 d3 95 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 105172d:	48 8d 3d 4c eb 00 00 	lea    0xeb4c(%rip),%rdi        # 1060280 <core_durable_error.verbs+0x1650>
 1051734:	e8 07 96 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051739:	e9 b4 02 00 00       	jmp    10519f2 <my.json::read_value+0x1172>
 105173e:	83 f8 7d             	cmp    $0x7d,%eax
 1051741:	0f 85 44 03 00 00    	jne    1051a8b <my.json::read_value+0x120b>
 1051747:	49 ff c5             	inc    %r13
 105174a:	41 bf 06 00 00 00    	mov    $0x6,%r15d
 1051750:	31 c0                	xor    %eax,%eax
 1051752:	e9 70 03 00 00       	jmp    1051ac7 <my.json::read_value+0x1247>
 1051757:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 105175c:	e8 5f 64 fc ff       	call   1017bc0 <myl_core_drop_owned>
 1051761:	48 8d 15 58 8d fb ff 	lea    -0x472a8(%rip),%rdx        # 100a4c0 <core_number_pairs+0x3220>
 1051768:	4c 89 f7             	mov    %r14,%rdi
 105176b:	4c 89 ee             	mov    %r13,%rsi
 105176e:	e8 0d 06 00 00       	call   1051d80 <my.json::parse_error>
 1051773:	49 89 c7             	mov    %rax,%r15
 1051776:	48 8d 3d 83 ec 00 00 	lea    0xec83(%rip),%rdi        # 1060400 <core_durable_error.verbs+0x17d0>
 105177d:	e8 7e 95 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 1051782:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1051787:	e8 34 64 fc ff       	call   1017bc0 <myl_core_drop_owned>
 105178c:	48 8d 3d 4d e8 00 00 	lea    0xe84d(%rip),%rdi        # 105ffe0 <core_durable_error.verbs+0x13b0>
 1051793:	e8 a8 95 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051798:	4c 89 f3             	mov    %r14,%rbx
 105179b:	e9 16 03 00 00       	jmp    1051ab6 <my.json::read_value+0x1236>
 10517a0:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 10517a5:	e8 16 64 fc ff       	call   1017bc0 <myl_core_drop_owned>
 10517aa:	48 8d 15 af 89 fb ff 	lea    -0x47651(%rip),%rdx        # 100a160 <core_number_pairs+0x2ec0>
 10517b1:	48 89 df             	mov    %rbx,%rdi
 10517b4:	4c 89 ee             	mov    %r13,%rsi
 10517b7:	e8 c4 05 00 00       	call   1051d80 <my.json::parse_error>
 10517bc:	49 89 c7             	mov    %rax,%r15
 10517bf:	48 8d 3d ea e7 00 00 	lea    0xe7ea(%rip),%rdi        # 105ffb0 <core_durable_error.verbs+0x1380>
 10517c6:	e9 e6 02 00 00       	jmp    1051ab1 <my.json::read_value+0x1231>
 10517cb:	48 8d 15 2e 87 fb ff 	lea    -0x478d2(%rip),%rdx        # 1009f00 <core_number_pairs+0x2c60>
 10517d2:	48 89 df             	mov    %rbx,%rdi
 10517d5:	4c 89 fe             	mov    %r15,%rsi
 10517d8:	e8 a3 05 00 00       	call   1051d80 <my.json::parse_error>
 10517dd:	48 8d 3d 6c e7 00 00 	lea    0xe76c(%rip),%rdi        # 105ff50 <core_durable_error.verbs+0x1320>
 10517e4:	e9 5e fc ff ff       	jmp    1051447 <my.json::read_value+0xbc7>
 10517e9:	48 8d 15 f0 8e fb ff 	lea    -0x47110(%rip),%rdx        # 100a6e0 <core_number_pairs+0x3440>
 10517f0:	48 89 df             	mov    %rbx,%rdi
 10517f3:	4c 89 f6             	mov    %r14,%rsi
 10517f6:	49 89 c4             	mov    %rax,%r12
 10517f9:	4c 89 d5             	mov    %r10,%rbp
 10517fc:	44 89 5c 24 10       	mov    %r11d,0x10(%rsp)
 1051801:	e8 7a 05 00 00       	call   1051d80 <my.json::parse_error>
 1051806:	49 89 ea             	mov    %rbp,%r10
 1051809:	48 89 c1             	mov    %rax,%rcx
 105180c:	4c 89 e0             	mov    %r12,%rax
 105180f:	b2 01                	mov    $0x1,%dl
 1051811:	48 8d 3d a8 ef 00 00 	lea    0xefa8(%rip),%rdi        # 10607c0 <core_durable_error.verbs+0x1b90>
 1051818:	e8 e3 94 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 105181d:	44 8b 5c 24 10       	mov    0x10(%rsp),%r11d
 1051822:	80 fa 01             	cmp    $0x1,%dl
 1051825:	0f 85 72 fe ff ff    	jne    105169d <my.json::read_value+0xe1d>
 105182b:	48 8d 3d ae ea 00 00 	lea    0xeaae(%rip),%rdi        # 10602e0 <core_durable_error.verbs+0x16b0>
 1051832:	e8 09 95 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051837:	49 89 dc             	mov    %rbx,%r12
 105183a:	48 89 c8             	mov    %rcx,%rax
 105183d:	e9 b0 01 00 00       	jmp    10519f2 <my.json::read_value+0x1172>
 1051842:	4c 8d 35 d7 e9 00 00 	lea    0xe9d7(%rip),%r14        # 1060220 <core_durable_error.verbs+0x15f0>
 1051849:	48 8d 15 f0 8a fb ff 	lea    -0x47510(%rip),%rdx        # 100a340 <core_number_pairs+0x30a0>
 1051850:	eb 3d                	jmp    105188f <my.json::read_value+0x100f>
 1051852:	4c 8d 35 c7 e9 00 00 	lea    0xe9c7(%rip),%r14        # 1060220 <core_durable_error.verbs+0x15f0>
 1051859:	48 8d 15 e0 8a fb ff 	lea    -0x47520(%rip),%rdx        # 100a340 <core_number_pairs+0x30a0>
 1051860:	eb 57                	jmp    10518b9 <my.json::read_value+0x1039>
 1051862:	4c 8d 35 b7 e9 00 00 	lea    0xe9b7(%rip),%r14        # 1060220 <core_durable_error.verbs+0x15f0>
 1051869:	48 8d 15 d0 8a fb ff 	lea    -0x47530(%rip),%rdx        # 100a340 <core_number_pairs+0x30a0>
 1051870:	e9 8f 00 00 00       	jmp    1051904 <my.json::read_value+0x1084>
 1051875:	49 89 d7             	mov    %rdx,%r15
 1051878:	4d 8b 66 08          	mov    0x8(%r14),%r12
 105187c:	e9 b0 02 00 00       	jmp    1051b31 <my.json::read_value+0x12b1>
 1051881:	4c 8d 35 c8 e9 00 00 	lea    0xe9c8(%rip),%r14        # 1060250 <core_durable_error.verbs+0x1620>
 1051888:	48 8d 15 f1 8a fb ff 	lea    -0x4750f(%rip),%rdx        # 100a380 <core_number_pairs+0x30e0>
 105188f:	48 89 df             	mov    %rbx,%rdi
 1051892:	4c 89 fe             	mov    %r15,%rsi
 1051895:	e8 e6 04 00 00       	call   1051d80 <my.json::parse_error>
 105189a:	4c 89 f7             	mov    %r14,%rdi
 105189d:	e8 5e 94 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 10518a2:	48 8d 3d e7 e5 00 00 	lea    0xe5e7(%rip),%rdi        # 105fe90 <core_durable_error.verbs+0x1260>
 10518a9:	eb 28                	jmp    10518d3 <my.json::read_value+0x1053>
 10518ab:	4c 8d 35 9e e9 00 00 	lea    0xe99e(%rip),%r14        # 1060250 <core_durable_error.verbs+0x1620>
 10518b2:	48 8d 15 c7 8a fb ff 	lea    -0x47539(%rip),%rdx        # 100a380 <core_number_pairs+0x30e0>
 10518b9:	48 89 df             	mov    %rbx,%rdi
 10518bc:	4c 89 fe             	mov    %r15,%rsi
 10518bf:	e8 bc 04 00 00       	call   1051d80 <my.json::parse_error>
 10518c4:	4c 89 f7             	mov    %r14,%rdi
 10518c7:	e8 34 94 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 10518cc:	48 8d 3d ed e5 00 00 	lea    0xe5ed(%rip),%rdi        # 105fec0 <core_durable_error.verbs+0x1290>
 10518d3:	e8 68 94 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 10518d8:	b9 01 00 00 00       	mov    $0x1,%ecx
 10518dd:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 10518e1:	49 89 45 08          	mov    %rax,0x8(%r13)
 10518e5:	49 c7 45 10 00 00 00 	movq   $0x0,0x10(%r13)
 10518ec:	00 
 10518ed:	4d 89 65 18          	mov    %r12,0x18(%r13)
 10518f1:	e9 f0 01 00 00       	jmp    1051ae6 <my.json::read_value+0x1266>
 10518f6:	4c 8d 35 53 e9 00 00 	lea    0xe953(%rip),%r14        # 1060250 <core_durable_error.verbs+0x1620>
 10518fd:	48 8d 15 7c 8a fb ff 	lea    -0x47584(%rip),%rdx        # 100a380 <core_number_pairs+0x30e0>
 1051904:	48 89 df             	mov    %rbx,%rdi
 1051907:	4c 89 fe             	mov    %r15,%rsi
 105190a:	e8 71 04 00 00       	call   1051d80 <my.json::parse_error>
 105190f:	4c 89 f7             	mov    %r14,%rdi
 1051912:	e8 e9 93 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 1051917:	48 8d 3d 42 e5 00 00 	lea    0xe542(%rip),%rdi        # 105fe60 <core_durable_error.verbs+0x1230>
 105191e:	e8 1d 94 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051923:	b9 01 00 00 00       	mov    $0x1,%ecx
 1051928:	e9 5e f4 ff ff       	jmp    1050d8b <my.json::read_value+0x50b>
 105192d:	48 8d 15 6c 8d fb ff 	lea    -0x47294(%rip),%rdx        # 100a6a0 <core_number_pairs+0x3400>
 1051934:	48 89 df             	mov    %rbx,%rdi
 1051937:	4c 89 ee             	mov    %r13,%rsi
 105193a:	4d 89 d6             	mov    %r10,%r14
 105193d:	44 89 dd             	mov    %r11d,%ebp
 1051940:	e8 3b 04 00 00       	call   1051d80 <my.json::parse_error>
 1051945:	4d 89 f2             	mov    %r14,%r10
 1051948:	b1 01                	mov    $0x1,%cl
 105194a:	48 8d 3d 3f ee 00 00 	lea    0xee3f(%rip),%rdi        # 1060790 <core_durable_error.verbs+0x1b60>
 1051951:	e8 aa 93 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 1051956:	41 89 eb             	mov    %ebp,%r11d
 1051959:	80 f9 01             	cmp    $0x1,%cl
 105195c:	0f 85 04 fc ff ff    	jne    1051566 <my.json::read_value+0xce6>
 1051962:	48 8d 3d 47 e9 00 00 	lea    0xe947(%rip),%rdi        # 10602b0 <core_durable_error.verbs+0x1680>
 1051969:	e8 d2 93 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 105196e:	49 89 dc             	mov    %rbx,%r12
 1051971:	4d 89 ee             	mov    %r13,%r14
 1051974:	4c 8b 6c 24 08       	mov    0x8(%rsp),%r13
 1051979:	eb 77                	jmp    10519f2 <my.json::read_value+0x1172>
 105197b:	48 8d 3d ae e4 00 00 	lea    0xe4ae(%rip),%rdi        # 105fe30 <core_durable_error.verbs+0x1200>
 1051982:	e8 b9 93 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051987:	49 c7 45 00 01 00 00 	movq   $0x1,0x0(%r13)
 105198e:	00 
 105198f:	49 89 45 08          	mov    %rax,0x8(%r13)
 1051993:	49 89 4d 18          	mov    %rcx,0x18(%r13)
 1051997:	e9 4a 01 00 00       	jmp    1051ae6 <my.json::read_value+0x1266>
 105199c:	4d 89 66 08          	mov    %r12,0x8(%r14)
 10519a0:	4c 89 f7             	mov    %r14,%rdi
 10519a3:	49 89 d6             	mov    %rdx,%r14
 10519a6:	e8 15 62 fc ff       	call   1017bc0 <myl_core_drop_owned>
 10519ab:	48 8d 15 8e 88 fb ff 	lea    -0x47772(%rip),%rdx        # 100a240 <core_number_pairs+0x2fa0>
 10519b2:	48 89 df             	mov    %rbx,%rdi
 10519b5:	4d 89 f7             	mov    %r14,%r15
 10519b8:	4c 89 f6             	mov    %r14,%rsi
 10519bb:	e8 c0 03 00 00       	call   1051d80 <my.json::parse_error>
 10519c0:	48 8d 3d d9 e6 00 00 	lea    0xe6d9(%rip),%rdi        # 10600a0 <core_durable_error.verbs+0x1470>
 10519c7:	e8 34 93 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 10519cc:	e9 51 01 00 00       	jmp    1051b22 <my.json::read_value+0x12a2>
 10519d1:	48 8d 15 e8 89 fb ff 	lea    -0x47618(%rip),%rdx        # 100a3c0 <core_number_pairs+0x3120>
 10519d8:	48 89 df             	mov    %rbx,%rdi
 10519db:	4c 89 f6             	mov    %r14,%rsi
 10519de:	e8 9d 03 00 00       	call   1051d80 <my.json::parse_error>
 10519e3:	48 8d 3d 26 e9 00 00 	lea    0xe926(%rip),%rdi        # 1060310 <core_durable_error.verbs+0x16e0>
 10519ea:	e8 11 93 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 10519ef:	49 89 dc             	mov    %rbx,%r12
 10519f2:	48 8d 3d f7 e4 00 00 	lea    0xe4f7(%rip),%rdi        # 105fef0 <core_durable_error.verbs+0x12c0>
 10519f9:	e8 42 93 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 10519fe:	b9 01 00 00 00       	mov    $0x1,%ecx
 1051a03:	4c 89 e3             	mov    %r12,%rbx
 1051a06:	49 89 4d 00          	mov    %rcx,0x0(%r13)
 1051a0a:	49 89 45 08          	mov    %rax,0x8(%r13)
 1051a0e:	4d 89 55 10          	mov    %r10,0x10(%r13)
 1051a12:	49 89 5d 18          	mov    %rbx,0x18(%r13)
 1051a16:	4d 89 f7             	mov    %r14,%r15
 1051a19:	e9 c8 00 00 00       	jmp    1051ae6 <my.json::read_value+0x1266>
 1051a1e:	48 8d 15 3b 8a fb ff 	lea    -0x475c5(%rip),%rdx        # 100a460 <core_number_pairs+0x31c0>
 1051a25:	4c 89 f7             	mov    %r14,%rdi
 1051a28:	4c 89 ee             	mov    %r13,%rsi
 1051a2b:	e8 50 03 00 00       	call   1051d80 <my.json::parse_error>
 1051a30:	49 89 c7             	mov    %rax,%r15
 1051a33:	48 8d 3d 66 e9 00 00 	lea    0xe966(%rip),%rdi        # 10603a0 <core_durable_error.verbs+0x1770>
 1051a3a:	e9 3e fd ff ff       	jmp    105177d <my.json::read_value+0xefd>
 1051a3f:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 1051a44:	e8 77 61 fc ff       	call   1017bc0 <myl_core_drop_owned>
 1051a49:	48 8d 15 b0 8a fb ff 	lea    -0x47550(%rip),%rdx        # 100a500 <core_number_pairs+0x3260>
 1051a50:	4c 89 f7             	mov    %r14,%rdi
 1051a53:	4c 89 ee             	mov    %r13,%rsi
 1051a56:	e8 25 03 00 00       	call   1051d80 <my.json::parse_error>
 1051a5b:	49 89 c7             	mov    %rax,%r15
 1051a5e:	48 8d 3d cb e9 00 00 	lea    0xe9cb(%rip),%rdi        # 1060430 <core_durable_error.verbs+0x1800>
 1051a65:	e9 13 fd ff ff       	jmp    105177d <my.json::read_value+0xefd>
 1051a6a:	48 8d 15 ef 8b fb ff 	lea    -0x47411(%rip),%rdx        # 100a660 <core_number_pairs+0x33c0>
 1051a71:	48 89 df             	mov    %rbx,%rdi
 1051a74:	48 89 ee             	mov    %rbp,%rsi
 1051a77:	e8 04 03 00 00       	call   1051d80 <my.json::parse_error>
 1051a7c:	48 8d 3d 1d ec 00 00 	lea    0xec1d(%rip),%rdi        # 10606a0 <core_durable_error.verbs+0x1a70>
 1051a83:	49 89 ee             	mov    %rbp,%r14
 1051a86:	e9 9d fc ff ff       	jmp    1051728 <my.json::read_value+0xea8>
 1051a8b:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1051a90:	e8 2b 61 fc ff       	call   1017bc0 <myl_core_drop_owned>
 1051a95:	48 8d 15 04 87 fb ff 	lea    -0x478fc(%rip),%rdx        # 100a1a0 <core_number_pairs+0x2f00>
 1051a9c:	48 89 df             	mov    %rbx,%rdi
 1051a9f:	4c 89 ee             	mov    %r13,%rsi
 1051aa2:	e8 d9 02 00 00       	call   1051d80 <my.json::parse_error>
 1051aa7:	49 89 c7             	mov    %rax,%r15
 1051aaa:	48 8d 3d 5f e5 00 00 	lea    0xe55f(%rip),%rdi        # 1060010 <core_durable_error.verbs+0x13e0>
 1051ab1:	e8 4a 92 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 1051ab6:	48 8d 3d 13 e3 00 00 	lea    0xe313(%rip),%rdi        # 105fdd0 <core_durable_error.verbs+0x11a0>
 1051abd:	e8 7e 92 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051ac2:	b8 01 00 00 00       	mov    $0x1,%eax
 1051ac7:	48 8b 4c 24 08       	mov    0x8(%rsp),%rcx
 1051acc:	48 89 01             	mov    %rax,(%rcx)
 1051acf:	4c 89 79 08          	mov    %r15,0x8(%rcx)
 1051ad3:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 1051ad8:	48 89 41 10          	mov    %rax,0x10(%rcx)
 1051adc:	48 89 59 18          	mov    %rbx,0x18(%rcx)
 1051ae0:	4d 89 ef             	mov    %r13,%r15
 1051ae3:	49 89 cd             	mov    %rcx,%r13
 1051ae6:	4d 89 7d 20          	mov    %r15,0x20(%r13)
 1051aea:	4c 89 e8             	mov    %r13,%rax
 1051aed:	48 81 c4 d8 00 00 00 	add    $0xd8,%rsp
 1051af4:	5b                   	pop    %rbx
 1051af5:	41 5c                	pop    %r12
 1051af7:	41 5d                	pop    %r13
 1051af9:	41 5e                	pop    %r14
 1051afb:	41 5f                	pop    %r15
 1051afd:	5d                   	pop    %rbp
 1051afe:	c3                   	ret
 1051aff:	49 89 d7             	mov    %rdx,%r15
 1051b02:	4c 8b 6c 24 48       	mov    0x48(%rsp),%r13
 1051b07:	4d 89 66 08          	mov    %r12,0x8(%r14)
 1051b0b:	4c 89 f7             	mov    %r14,%rdi
 1051b0e:	e8 ad 60 fc ff       	call   1017bc0 <myl_core_drop_owned>
 1051b13:	4c 89 e8             	mov    %r13,%rax
 1051b16:	48 8d 3d 53 e5 00 00 	lea    0xe553(%rip),%rdi        # 1060070 <core_durable_error.verbs+0x1440>
 1051b1d:	e8 1e 92 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051b22:	4c 8b 6c 24 08       	mov    0x8(%rsp),%r13
 1051b27:	eb 32                	jmp    1051b5b <my.json::read_value+0x12db>
 1051b29:	49 89 d7             	mov    %rdx,%r15
 1051b2c:	4c 8b 6c 24 08       	mov    0x8(%rsp),%r13
 1051b31:	4d 89 66 08          	mov    %r12,0x8(%r14)
 1051b35:	4c 89 f7             	mov    %r14,%rdi
 1051b38:	e8 83 60 fc ff       	call   1017bc0 <myl_core_drop_owned>
 1051b3d:	48 8d 15 bc 86 fb ff 	lea    -0x47944(%rip),%rdx        # 100a200 <core_number_pairs+0x2f60>
 1051b44:	48 89 df             	mov    %rbx,%rdi
 1051b47:	4c 89 fe             	mov    %r15,%rsi
 1051b4a:	e8 31 02 00 00       	call   1051d80 <my.json::parse_error>
 1051b4f:	48 8d 3d ea e4 00 00 	lea    0xe4ea(%rip),%rdi        # 1060040 <core_durable_error.verbs+0x1410>
 1051b56:	e8 a5 91 ff ff       	call   104ad00 <myl_core_err_trace_origin_preserve_most>
 1051b5b:	48 8d 3d 9e e2 00 00 	lea    0xe29e(%rip),%rdi        # 105fe00 <core_durable_error.verbs+0x11d0>
 1051b62:	e8 d9 91 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051b67:	b9 01 00 00 00       	mov    $0x1,%ecx
 1051b6c:	4c 89 fa             	mov    %r15,%rdx
 1051b6f:	e9 83 fb ff ff       	jmp    10516f7 <my.json::read_value+0xe77>
 1051b74:	48 8d 3d 55 e8 00 00 	lea    0xe855(%rip),%rdi        # 10603d0 <core_durable_error.verbs+0x17a0>
 1051b7b:	e8 c0 91 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051b80:	e9 fd fb ff ff       	jmp    1051782 <my.json::read_value+0xf02>
 1051b85:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 1051b8a:	e8 31 60 fc ff       	call   1017bc0 <myl_core_drop_owned>
 1051b8f:	48 8d 3d ca e8 00 00 	lea    0xe8ca(%rip),%rdi        # 1060460 <core_durable_error.verbs+0x1830>
 1051b96:	e8 a5 91 ff ff       	call   104ad40 <myl_core_err_trace_append_preserve_most>
 1051b9b:	49 89 de             	mov    %rbx,%r14
 1051b9e:	e9 df fb ff ff       	jmp    1051782 <my.json::read_value+0xf02>
 1051ba3:	be 10 00 00 00       	mov    $0x10,%esi
 1051ba8:	31 ff                	xor    %edi,%edi
 1051baa:	49 89 d6             	mov    %rdx,%r14
 1051bad:	e8 4e 52 fc ff       	call   1016e00 <myl_core_list_new_slow>
 1051bb2:	4c 89 f2             	mov    %r14,%rdx
 1051bb5:	49 89 c6             	mov    %rax,%r14
 1051bb8:	e9 cc ed ff ff       	jmp    1050989 <my.json::read_value+0x109>
 1051bbd:	48 8d 3d bc e3 00 00 	lea    0xe3bc(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051bc4:	48 89 d6             	mov    %rdx,%rsi
 1051bc7:	48 89 c2             	mov    %rax,%rdx
 1051bca:	e8 71 6d fc ff       	call   1018940 <myl_core_trap>
 1051bcf:	48 8d 3d aa e3 00 00 	lea    0xe3aa(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051bd6:	4c 89 fe             	mov    %r15,%rsi
 1051bd9:	e8 62 6d fc ff       	call   1018940 <myl_core_trap>
 1051bde:	48 8d 3d 9b e3 00 00 	lea    0xe39b(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051be5:	4c 89 ee             	mov    %r13,%rsi
 1051be8:	e8 53 6d fc ff       	call   1018940 <myl_core_trap>
 1051bed:	48 8d 3d 8c e3 00 00 	lea    0xe38c(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051bf4:	4c 89 ee             	mov    %r13,%rsi
 1051bf7:	e8 44 6d fc ff       	call   1018940 <myl_core_trap>
 1051bfc:	48 8d 3d 7d e3 00 00 	lea    0xe37d(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c03:	4c 89 ee             	mov    %r13,%rsi
 1051c06:	e8 35 6d fc ff       	call   1018940 <myl_core_trap>
 1051c0b:	48 8d 3d ee ea 00 00 	lea    0xeaee(%rip),%rdi        # 1060700 <core_durable_error.verbs+0x1ad0>
 1051c12:	4c 89 f6             	mov    %r14,%rsi
 1051c15:	e8 26 6d fc ff       	call   1018940 <myl_core_trap>
 1051c1a:	48 8d 3d 5f e3 00 00 	lea    0xe35f(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c21:	48 89 c2             	mov    %rax,%rdx
 1051c24:	e8 17 6d fc ff       	call   1018940 <myl_core_trap>
 1051c29:	48 8d 3d 50 e3 00 00 	lea    0xe350(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c30:	e8 0b 6d fc ff       	call   1018940 <myl_core_trap>
 1051c35:	48 8d 3d 44 e3 00 00 	lea    0xe344(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c3c:	48 89 d6             	mov    %rdx,%rsi
 1051c3f:	48 89 c2             	mov    %rax,%rdx
 1051c42:	e8 f9 6c fc ff       	call   1018940 <myl_core_trap>
 1051c47:	48 8d 3d 32 e3 00 00 	lea    0xe332(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c4e:	4c 89 fe             	mov    %r15,%rsi
 1051c51:	e8 ea 6c fc ff       	call   1018940 <myl_core_trap>
 1051c56:	48 8d 3d 23 e3 00 00 	lea    0xe323(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c5d:	4c 89 f6             	mov    %r14,%rsi
 1051c60:	e8 db 6c fc ff       	call   1018940 <myl_core_trap>
 1051c65:	48 8d 3d 14 e3 00 00 	lea    0xe314(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c6c:	4c 89 ee             	mov    %r13,%rsi
 1051c6f:	e8 cc 6c fc ff       	call   1018940 <myl_core_trap>
 1051c74:	48 8d 3d 05 e3 00 00 	lea    0xe305(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c7b:	4c 89 ee             	mov    %r13,%rsi
 1051c7e:	e8 bd 6c fc ff       	call   1018940 <myl_core_trap>
 1051c83:	48 8d 3d f6 e2 00 00 	lea    0xe2f6(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c8a:	4c 89 ee             	mov    %r13,%rsi
 1051c8d:	e8 ae 6c fc ff       	call   1018940 <myl_core_trap>
 1051c92:	48 8d 3d e7 e2 00 00 	lea    0xe2e7(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051c99:	e8 a2 6c fc ff       	call   1018940 <myl_core_trap>
 1051c9e:	48 8d 3d cb e9 00 00 	lea    0xe9cb(%rip),%rdi        # 1060670 <core_durable_error.verbs+0x1a40>
 1051ca5:	4c 89 f6             	mov    %r14,%rsi
 1051ca8:	e8 93 6c fc ff       	call   1018940 <myl_core_trap>
 1051cad:	48 8d 3d 3c e5 00 00 	lea    0xe53c(%rip),%rdi        # 10601f0 <core_durable_error.verbs+0x15c0>
 1051cb4:	ba 05 00 00 00       	mov    $0x5,%edx
 1051cb9:	4c 89 fe             	mov    %r15,%rsi
 1051cbc:	e8 7f 6c fc ff       	call   1018940 <myl_core_trap>
 1051cc1:	48 8d 3d 28 e5 00 00 	lea    0xe528(%rip),%rdi        # 10601f0 <core_durable_error.verbs+0x15c0>
 1051cc8:	ba 04 00 00 00       	mov    $0x4,%edx
 1051ccd:	4c 89 fe             	mov    %r15,%rsi
 1051cd0:	e8 6b 6c fc ff       	call   1018940 <myl_core_trap>
 1051cd5:	48 8d 3d 14 e5 00 00 	lea    0xe514(%rip),%rdi        # 10601f0 <core_durable_error.verbs+0x15c0>
 1051cdc:	ba 04 00 00 00       	mov    $0x4,%edx
 1051ce1:	4c 89 fe             	mov    %r15,%rsi
 1051ce4:	e8 57 6c fc ff       	call   1018940 <myl_core_trap>
 1051ce9:	48 8d 3d 90 e2 00 00 	lea    0xe290(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051cf0:	48 89 d6             	mov    %rdx,%rsi
 1051cf3:	48 89 c2             	mov    %rax,%rdx
 1051cf6:	e8 45 6c fc ff       	call   1018940 <myl_core_trap>
 1051cfb:	48 8d 3d 7e e2 00 00 	lea    0xe27e(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051d02:	4c 89 ee             	mov    %r13,%rsi
 1051d05:	e8 36 6c fc ff       	call   1018940 <myl_core_trap>
 1051d0a:	48 8d 3d 6f e2 00 00 	lea    0xe26f(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051d11:	48 89 ee             	mov    %rbp,%rsi
 1051d14:	e8 27 6c fc ff       	call   1018940 <myl_core_trap>
 1051d19:	48 8d 3d 60 e2 00 00 	lea    0xe260(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051d20:	4c 89 ee             	mov    %r13,%rsi
 1051d23:	e8 18 6c fc ff       	call   1018940 <myl_core_trap>
 1051d28:	48 8d 3d 51 e2 00 00 	lea    0xe251(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051d2f:	4c 89 f6             	mov    %r14,%rsi
 1051d32:	e8 09 6c fc ff       	call   1018940 <myl_core_trap>
 1051d37:	48 8d 3d 92 e9 00 00 	lea    0xe992(%rip),%rdi        # 10606d0 <core_durable_error.verbs+0x1aa0>
 1051d3e:	48 89 ee             	mov    %rbp,%rsi
 1051d41:	e8 fa 6b fc ff       	call   1018940 <myl_core_trap>
 1051d46:	48 8d 3d 13 ea 00 00 	lea    0xea13(%rip),%rdi        # 1060760 <core_durable_error.verbs+0x1b30>
 1051d4d:	31 f6                	xor    %esi,%esi
 1051d4f:	4c 89 d2             	mov    %r10,%rdx
 1051d52:	e8 e9 6b fc ff       	call   1018940 <myl_core_trap>
 1051d57:	48 8d 3d 22 e2 00 00 	lea    0xe222(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051d5e:	4c 89 ee             	mov    %r13,%rsi
 1051d61:	e8 da 6b fc ff       	call   1018940 <myl_core_trap>
 1051d66:	48 8d 3d 13 e2 00 00 	lea    0xe213(%rip),%rdi        # 105ff80 <core_durable_error.verbs+0x1350>
 1051d6d:	4c 89 f6             	mov    %r14,%rsi
 1051d70:	e8 cb 6b fc ff       	call   1018940 <myl_core_trap>

Disassembly of section .plt:
