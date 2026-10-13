
.tmp/lox-eda-parity/P1/frame-ip-002/candidate-lox:     file format elf64-x86-64


Disassembly of section .text:

000000000105ab70 <my.vm::run>:
 105ab70:	55                   	push   %rbp
 105ab71:	41 57                	push   %r15
 105ab73:	41 56                	push   %r14
 105ab75:	41 55                	push   %r13
 105ab77:	41 54                	push   %r12
 105ab79:	53                   	push   %rbx
 105ab7a:	48 81 ec a8 08 00 00 	sub    $0x8a8,%rsp
 105ab81:	48 89 4c 24 58       	mov    %rcx,0x58(%rsp)
 105ab86:	48 89 54 24 08       	mov    %rdx,0x8(%rsp)
 105ab8b:	49 89 f6             	mov    %rsi,%r14
 105ab8e:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 105ab93:	48 8b 9e 90 00 00 00 	mov    0x90(%rsi),%rbx
 105ab9a:	48 89 de             	mov    %rbx,%rsi
 105ab9d:	48 ff ce             	dec    %rsi
 105aba0:	0f 80 ce 2b 00 00    	jo     105d774 <my.vm::run+0x2c04>
 105aba6:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105abad:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105abb4:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105abb8:	48 39 d6             	cmp    %rdx,%rsi
 105abbb:	0f 83 12 24 00 00    	jae    105cfd3 <my.vm::run+0x2463>
 105abc1:	48 89 f1             	mov    %rsi,%rcx
 105abc4:	48 c1 e1 05          	shl    $0x5,%rcx
 105abc8:	48 8b 54 08 20       	mov    0x20(%rax,%rcx,1),%rdx
 105abcd:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 105abd2:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105abd7:	48 8b 6c 08 30       	mov    0x30(%rax,%rcx,1),%rbp
 105abdc:	48 8b 44 08 38       	mov    0x38(%rax,%rcx,1),%rax
 105abe1:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105abe6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 105abed:	00 00 00 
 105abf0:	4c 89 f7             	mov    %r14,%rdi
 105abf3:	4c 89 fe             	mov    %r15,%rsi
 105abf6:	48 89 ea             	mov    %rbp,%rdx
 105abf9:	e8 42 78 00 00       	call   1062440 <my.vm::read_byte>
 105abfe:	48 89 d5             	mov    %rdx,%rbp
 105ac01:	49 8b 8e 88 00 00 00 	mov    0x88(%r14),%rcx
 105ac08:	4c 8d 63 ff          	lea    -0x1(%rbx),%r12
 105ac0c:	4c 89 e2             	mov    %r12,%rdx
 105ac0f:	48 85 db             	test   %rbx,%rbx
 105ac12:	7f 07                	jg     105ac1b <my.vm::run+0xab>
 105ac14:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105ac18:	4c 01 e2             	add    %r12,%rdx
 105ac1b:	48 c1 e2 05          	shl    $0x5,%rdx
 105ac1f:	48 89 6c 11 30       	mov    %rbp,0x30(%rcx,%rdx,1)
 105ac24:	49 89 8e 88 00 00 00 	mov    %rcx,0x88(%r14)
 105ac2b:	48 83 f8 24          	cmp    $0x24,%rax
 105ac2f:	0f 87 be 1b 00 00    	ja     105c7f3 <my.vm::run+0x1c83>
 105ac35:	48 8d 15 70 c7 fa ff 	lea    -0x53890(%rip),%rdx        # 10073ac <core_number_pairs+0x14c>
 105ac3c:	48 63 0c 82          	movslq (%rdx,%rax,4),%rcx
 105ac40:	48 01 d1             	add    %rdx,%rcx
 105ac43:	ff e1                	jmp    *%rcx
 105ac45:	49 8b 8e 80 00 00 00 	mov    0x80(%r14),%rcx
 105ac4c:	48 89 ce             	mov    %rcx,%rsi
 105ac4f:	48 ff ce             	dec    %rsi
 105ac52:	0f 80 28 24 00 00    	jo     105d080 <my.vm::run+0x2510>
 105ac58:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105ac5c:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105ac60:	48 89 f7             	mov    %rsi,%rdi
 105ac63:	48 39 d6             	cmp    %rdx,%rsi
 105ac66:	0f 83 96 1c 00 00    	jae    105c902 <my.vm::run+0x1d92>
 105ac6c:	48 c1 e7 04          	shl    $0x4,%rdi
 105ac70:	80 7c 39 20 02       	cmpb   $0x2,0x20(%rcx,%rdi,1)
 105ac75:	75 5b                	jne    105acd2 <my.vm::run+0x162>
 105ac77:	49 89 f5             	mov    %rsi,%r13
 105ac7a:	49 ff cd             	dec    %r13
 105ac7d:	0f 80 88 25 00 00    	jo     105d20b <my.vm::run+0x269b>
 105ac83:	c5 fb 10 44 39 28    	vmovsd 0x28(%rcx,%rdi,1),%xmm0
 105ac89:	4c 89 ee             	mov    %r13,%rsi
 105ac8c:	49 39 d5             	cmp    %rdx,%r13
 105ac8f:	0f 83 88 1c 00 00    	jae    105c91d <my.vm::run+0x1dad>
 105ac95:	48 83 c1 20          	add    $0x20,%rcx
 105ac99:	48 c1 e6 04          	shl    $0x4,%rsi
 105ac9d:	80 3c 31 02          	cmpb   $0x2,(%rcx,%rsi,1)
 105aca1:	75 2f                	jne    105acd2 <my.vm::run+0x162>
 105aca3:	48 01 f1             	add    %rsi,%rcx
 105aca6:	c5 fb 10 49 08       	vmovsd 0x8(%rcx),%xmm1
 105acab:	48 83 c0 f0          	add    $0xfffffffffffffff0,%rax
 105acaf:	48 83 f8 04          	cmp    $0x4,%rax
 105acb3:	0f 87 19 1b 00 00    	ja     105c7d2 <my.vm::run+0x1c62>
 105acb9:	48 8d 15 cc c7 fa ff 	lea    -0x53834(%rip),%rdx        # 100748c <core_number_pairs+0x22c>
 105acc0:	48 63 04 82          	movslq (%rdx,%rax,4),%rax
 105acc4:	48 01 d0             	add    %rdx,%rax
 105acc7:	ff e0                	jmp    *%rax
 105acc9:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 105accd:	e9 ed 1a 00 00       	jmp    105c7bf <my.vm::run+0x1c4f>
 105acd2:	48 8d 0d e7 74 fb ff 	lea    -0x48b19(%rip),%rcx        # 10121c0 <core_number_pairs+0xaf60>
 105acd9:	48 8d bc 24 d0 00 00 	lea    0xd0(%rsp),%rdi
 105ace0:	00 
 105ace1:	4c 89 f6             	mov    %r14,%rsi
 105ace4:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105ace9:	e8 d2 72 00 00       	call   1061fc0 <my.vm::runtime_error>
 105acee:	f6 84 24 d0 00 00 00 	testb  $0x1,0xd0(%rsp)
 105acf5:	01 
 105acf6:	0f 84 8d 22 00 00    	je     105cf89 <my.vm::run+0x2419>
 105acfc:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105ad03:	e9 e4 1a 00 00       	jmp    105c7ec <my.vm::run+0x1c7c>
 105ad08:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105ad0f:	49 89 f5             	mov    %rsi,%r13
 105ad12:	49 ff cd             	dec    %r13
 105ad15:	0f 80 aa 28 00 00    	jo     105d5c5 <my.vm::run+0x2a55>
 105ad1b:	4c 89 ee             	mov    %r13,%rsi
 105ad1e:	48 ff ce             	dec    %rsi
 105ad21:	0f 80 07 28 00 00    	jo     105d52e <my.vm::run+0x29be>
 105ad27:	49 8b 5e 78          	mov    0x78(%r14),%rbx
 105ad2b:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105ad2f:	48 39 d6             	cmp    %rdx,%rsi
 105ad32:	0f 83 be 1d 00 00    	jae    105caf6 <my.vm::run+0x1f86>
 105ad38:	48 89 f0             	mov    %rsi,%rax
 105ad3b:	48 c1 e0 04          	shl    $0x4,%rax
 105ad3f:	80 7c 03 20 03       	cmpb   $0x3,0x20(%rbx,%rax,1)
 105ad44:	0f 85 0b 17 00 00    	jne    105c455 <my.vm::run+0x18e5>
 105ad4a:	48 8b 44 03 28       	mov    0x28(%rbx,%rax,1),%rax
 105ad4f:	49 8b 36             	mov    (%r14),%rsi
 105ad52:	48 8b 4e 08          	mov    0x8(%rsi),%rcx
 105ad56:	48 89 c7             	mov    %rax,%rdi
 105ad59:	48 39 c8             	cmp    %rcx,%rax
 105ad5c:	0f 83 08 20 00 00    	jae    105cd6a <my.vm::run+0x21fa>
 105ad62:	48 6b cf 38          	imul   $0x38,%rdi,%rcx
 105ad66:	83 7c 0e 20 06       	cmpl   $0x6,0x20(%rsi,%rcx,1)
 105ad6b:	0f 85 e4 16 00 00    	jne    105c455 <my.vm::run+0x18e5>
 105ad71:	4c 89 e9             	mov    %r13,%rcx
 105ad74:	49 39 d5             	cmp    %rdx,%r13
 105ad77:	0f 83 c5 20 00 00    	jae    105ce42 <my.vm::run+0x22d2>
 105ad7d:	48 8d 53 20          	lea    0x20(%rbx),%rdx
 105ad81:	48 c1 e1 04          	shl    $0x4,%rcx
 105ad85:	0f b6 34 0a          	movzbl (%rdx,%rcx,1),%esi
 105ad89:	83 fe 03             	cmp    $0x3,%esi
 105ad8c:	0f 85 7d 29 00 00    	jne    105d70f <my.vm::run+0x2b9f>
 105ad92:	48 01 ca             	add    %rcx,%rdx
 105ad95:	48 8b 72 08          	mov    0x8(%rdx),%rsi
 105ad99:	4c 89 f7             	mov    %r14,%rdi
 105ad9c:	48 89 c2             	mov    %rax,%rdx
 105ad9f:	e8 0c f1 00 00       	call   1069eb0 <my.heap::inherit_class_methods>
 105ada4:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105adab:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105adaf:	49 39 d5             	cmp    %rdx,%r13
 105adb2:	0f 82 34 1a 00 00    	jb     105c7ec <my.vm::run+0x1c7c>
 105adb8:	4c 89 e8             	mov    %r13,%rax
 105adbb:	48 c1 f8 3f          	sar    $0x3f,%rax
 105adbf:	48 21 d0             	and    %rdx,%rax
 105adc2:	4c 01 e8             	add    %r13,%rax
 105adc5:	48 39 d0             	cmp    %rdx,%rax
 105adc8:	0f 82 1e 1a 00 00    	jb     105c7ec <my.vm::run+0x1c7c>
 105adce:	e9 8e 2e 00 00       	jmp    105dc61 <my.vm::run+0x30f1>
 105add3:	4c 89 f7             	mov    %r14,%rdi
 105add6:	4c 89 fe             	mov    %r15,%rsi
 105add9:	48 89 ea             	mov    %rbp,%rdx
 105addc:	e8 0f 77 00 00       	call   10624f0 <my.vm::read_constant>
 105ade1:	3c 03                	cmp    $0x3,%al
 105ade3:	0f 85 28 23 00 00    	jne    105d111 <my.vm::run+0x25a1>
 105ade9:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105adf0:	49 89 f5             	mov    %rsi,%r13
 105adf3:	49 ff cd             	dec    %r13
 105adf6:	0f 80 36 28 00 00    	jo     105d632 <my.vm::run+0x2ac2>
 105adfc:	4c 89 7c 24 18       	mov    %r15,0x18(%rsp)
 105ae01:	4c 89 ee             	mov    %r13,%rsi
 105ae04:	48 ff ce             	dec    %rsi
 105ae07:	0f 80 7f 27 00 00    	jo     105d58c <my.vm::run+0x2a1c>
 105ae0d:	48 89 d3             	mov    %rdx,%rbx
 105ae10:	48 89 cd             	mov    %rcx,%rbp
 105ae13:	4d 8b 7e 78          	mov    0x78(%r14),%r15
 105ae17:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105ae1b:	48 39 d6             	cmp    %rdx,%rsi
 105ae1e:	0f 83 e0 1d 00 00    	jae    105cc04 <my.vm::run+0x2094>
 105ae24:	48 89 f0             	mov    %rsi,%rax
 105ae27:	48 c1 e0 04          	shl    $0x4,%rax
 105ae2b:	41 0f b6 4c 07 20    	movzbl 0x20(%r15,%rax,1),%ecx
 105ae31:	83 f9 03             	cmp    $0x3,%ecx
 105ae34:	0f 85 37 23 00 00    	jne    105d171 <my.vm::run+0x2601>
 105ae3a:	4d 8b 64 07 28       	mov    0x28(%r15,%rax,1),%r12
 105ae3f:	4c 89 f7             	mov    %r14,%rdi
 105ae42:	48 89 de             	mov    %rbx,%rsi
 105ae45:	e8 96 e3 00 00       	call   10691e0 <my.heap::string_hash>
 105ae4a:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105ae4e:	4c 89 e9             	mov    %r13,%rcx
 105ae51:	49 39 d5             	cmp    %rdx,%r13
 105ae54:	0f 83 00 1e 00 00    	jae    105cc5a <my.vm::run+0x20ea>
 105ae5a:	49 8d 57 20          	lea    0x20(%r15),%rdx
 105ae5e:	48 c1 e1 04          	shl    $0x4,%rcx
 105ae62:	4c 8b 4c 0a 08       	mov    0x8(%rdx,%rcx,1),%r9
 105ae67:	44 8b 04 0a          	mov    (%rdx,%rcx,1),%r8d
 105ae6b:	4c 89 f7             	mov    %r14,%rdi
 105ae6e:	4c 89 e6             	mov    %r12,%rsi
 105ae71:	48 89 da             	mov    %rbx,%rdx
 105ae74:	89 c1                	mov    %eax,%ecx
 105ae76:	e8 15 f2 00 00       	call   106a090 <my.heap::set_class_method>
 105ae7b:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105ae82:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105ae86:	49 39 d5             	cmp    %rdx,%r13
 105ae89:	0f 82 d5 16 00 00    	jb     105c564 <my.vm::run+0x19f4>
 105ae8f:	4c 89 e8             	mov    %r13,%rax
 105ae92:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ae96:	48 21 d0             	and    %rdx,%rax
 105ae99:	4c 01 e8             	add    %r13,%rax
 105ae9c:	48 39 d0             	cmp    %rdx,%rax
 105ae9f:	0f 82 bf 16 00 00    	jb     105c564 <my.vm::run+0x19f4>
 105aea5:	e9 20 2b 00 00       	jmp    105d9ca <my.vm::run+0x2e5a>
 105aeaa:	4c 89 f7             	mov    %r14,%rdi
 105aead:	4c 89 fe             	mov    %r15,%rsi
 105aeb0:	48 89 ea             	mov    %rbp,%rdx
 105aeb3:	e8 d8 7c 00 00       	call   1062b90 <my.vm::read_short>
 105aeb8:	4c 89 ee             	mov    %r13,%rsi
 105aebb:	48 ff ce             	dec    %rsi
 105aebe:	0f 80 85 25 00 00    	jo     105d449 <my.vm::run+0x28d9>
 105aec4:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105aec8:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 105aecc:	48 39 ce             	cmp    %rcx,%rsi
 105aecf:	0f 83 cf 1a 00 00    	jae    105c9a4 <my.vm::run+0x1e34>
 105aed5:	49 89 f0             	mov    %rsi,%r8
 105aed8:	48 89 d5             	mov    %rdx,%rbp
 105aedb:	49 c1 e0 04          	shl    $0x4,%r8
 105aedf:	42 0f b6 4c 07 20    	movzbl 0x20(%rdi,%r8,1),%ecx
 105aee5:	85 c9                	test   %ecx,%ecx
 105aee7:	74 1b                	je     105af04 <my.vm::run+0x394>
 105aee9:	83 f9 01             	cmp    $0x1,%ecx
 105aeec:	0f 85 01 19 00 00    	jne    105c7f3 <my.vm::run+0x1c83>
 105aef2:	4a 8d 0c 07          	lea    (%rdi,%r8,1),%rcx
 105aef6:	48 83 c1 20          	add    $0x20,%rcx
 105aefa:	f6 41 08 01          	testb  $0x1,0x8(%rcx)
 105aefe:	0f 85 ef 18 00 00    	jne    105c7f3 <my.vm::run+0x1c83>
 105af04:	48 01 c2             	add    %rax,%rdx
 105af07:	0f 80 44 28 00 00    	jo     105d751 <my.vm::run+0x2be1>
 105af0d:	48 89 d5             	mov    %rdx,%rbp
 105af10:	e9 de 18 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105af15:	4c 89 f7             	mov    %r14,%rdi
 105af18:	4c 89 fe             	mov    %r15,%rsi
 105af1b:	48 89 ea             	mov    %rbp,%rdx
 105af1e:	e8 6d 7c 00 00       	call   1062b90 <my.vm::read_short>
 105af23:	48 89 d5             	mov    %rdx,%rbp
 105af26:	48 29 c5             	sub    %rax,%rbp
 105af29:	0f 81 c4 18 00 00    	jno    105c7f3 <my.vm::run+0x1c83>
 105af2f:	e9 e8 25 00 00       	jmp    105d51c <my.vm::run+0x29ac>
 105af34:	4c 89 f7             	mov    %r14,%rdi
 105af37:	4c 89 fe             	mov    %r15,%rsi
 105af3a:	48 89 ea             	mov    %rbp,%rdx
 105af3d:	e8 ae 75 00 00       	call   10624f0 <my.vm::read_constant>
 105af42:	3c 03                	cmp    $0x3,%al
 105af44:	0f 85 4a 21 00 00    	jne    105d094 <my.vm::run+0x2524>
 105af4a:	48 89 cd             	mov    %rcx,%rbp
 105af4d:	48 8d bc 24 10 05 00 	lea    0x510(%rsp),%rdi
 105af54:	00 
 105af55:	4c 89 f6             	mov    %r14,%rsi
 105af58:	e8 53 86 00 00       	call   10635b0 <my.heap::allocate_class>
 105af5d:	48 8b 84 24 10 05 00 	mov    0x510(%rsp),%rax
 105af64:	00 
 105af65:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105af69:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105af70:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105af74:	48 39 d6             	cmp    %rdx,%rsi
 105af77:	0f 83 00 1c 00 00    	jae    105cb7d <my.vm::run+0x200d>
 105af7d:	48 89 f7             	mov    %rsi,%rdi
 105af80:	48 c1 e7 04          	shl    $0x4,%rdi
 105af84:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 105af8b:	00 00 
 105af8d:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 105af92:	49 89 4e 78          	mov    %rcx,0x78(%r14)
 105af96:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105af9d:	49 89 f5             	mov    %rsi,%r13
 105afa0:	49 ff c5             	inc    %r13
 105afa3:	0f 81 3c 18 00 00    	jno    105c7e5 <my.vm::run+0x1c75>
 105afa9:	e9 10 25 00 00       	jmp    105d4be <my.vm::run+0x294e>
 105afae:	4c 89 f7             	mov    %r14,%rdi
 105afb1:	4c 89 fe             	mov    %r15,%rsi
 105afb4:	48 89 ea             	mov    %rbp,%rdx
 105afb7:	e8 34 75 00 00       	call   10624f0 <my.vm::read_constant>
 105afbc:	3c 03                	cmp    $0x3,%al
 105afbe:	0f 85 6d 21 00 00    	jne    105d131 <my.vm::run+0x25c1>
 105afc4:	4c 89 ee             	mov    %r13,%rsi
 105afc7:	48 ff ce             	dec    %rsi
 105afca:	0f 80 24 25 00 00    	jo     105d4f4 <my.vm::run+0x2984>
 105afd0:	49 89 d0             	mov    %rdx,%r8
 105afd3:	48 89 cd             	mov    %rcx,%rbp
 105afd6:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105afdd:	49 8b 46 78          	mov    0x78(%r14),%rax
 105afe1:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105afe5:	48 39 d6             	cmp    %rdx,%rsi
 105afe8:	0f 83 c5 1b 00 00    	jae    105cbb3 <my.vm::run+0x2043>
 105afee:	48 89 f1             	mov    %rsi,%rcx
 105aff1:	48 c1 e1 04          	shl    $0x4,%rcx
 105aff5:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 105affa:	83 fa 03             	cmp    $0x3,%edx
 105affd:	0f 85 d1 20 00 00    	jne    105d0d4 <my.vm::run+0x2564>
 105b003:	48 01 c8             	add    %rcx,%rax
 105b006:	48 83 c0 20          	add    $0x20,%rax
 105b00a:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105b00e:	48 8d bc 24 b8 07 00 	lea    0x7b8(%rsp),%rdi
 105b015:	00 
 105b016:	4c 89 f6             	mov    %r14,%rsi
 105b019:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105b01e:	e8 bd 75 00 00       	call   10625e0 <my.vm::bind_method>
 105b023:	f6 84 24 b8 07 00 00 	testb  $0x1,0x7b8(%rsp)
 105b02a:	01 
 105b02b:	0f 85 cb fc ff ff    	jne    105acfc <my.vm::run+0x18c>
 105b031:	e9 53 1f 00 00       	jmp    105cf89 <my.vm::run+0x2419>
 105b036:	4c 89 ee             	mov    %r13,%rsi
 105b039:	48 ff ce             	dec    %rsi
 105b03c:	0f 80 c8 25 00 00    	jo     105d60a <my.vm::run+0x2a9a>
 105b042:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105b049:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b04d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b051:	48 39 d6             	cmp    %rdx,%rsi
 105b054:	0f 83 65 19 00 00    	jae    105c9bf <my.vm::run+0x1e4f>
 105b05a:	48 89 f1             	mov    %rsi,%rcx
 105b05d:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 105b062:	48 c1 e1 04          	shl    $0x4,%rcx
 105b066:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105b06c:	c5 f9 29 44 24 30    	vmovapd %xmm0,0x30(%rsp)
 105b072:	4c 89 f7             	mov    %r14,%rdi
 105b075:	4c 89 ee             	mov    %r13,%rsi
 105b078:	e8 93 83 00 00       	call   1063410 <my.vm::close_upvalues>
 105b07d:	49 8b b6 90 00 00 00 	mov    0x90(%r14),%rsi
 105b084:	48 89 f3             	mov    %rsi,%rbx
 105b087:	48 ff cb             	dec    %rbx
 105b08a:	0f 80 58 25 00 00    	jo     105d5e8 <my.vm::run+0x2a78>
 105b090:	49 89 9e 90 00 00 00 	mov    %rbx,0x90(%r14)
 105b097:	0f 84 0b 1f 00 00    	je     105cfa8 <my.vm::run+0x2438>
 105b09d:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105b0a4:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b0a8:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b0ac:	4c 89 e9             	mov    %r13,%rcx
 105b0af:	49 39 d5             	cmp    %rdx,%r13
 105b0b2:	0f 83 f8 1b 00 00    	jae    105ccb0 <my.vm::run+0x2140>
 105b0b8:	48 c1 e1 04          	shl    $0x4,%rcx
 105b0bc:	c5 f9 28 44 24 30    	vmovapd 0x30(%rsp),%xmm0
 105b0c2:	c5 f9 54 05 16 93 fa 	vandpd -0x56cea(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105b0c9:	ff 
 105b0ca:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 105b0d0:	49 89 46 78          	mov    %rax,0x78(%r14)
 105b0d4:	49 ff c5             	inc    %r13
 105b0d7:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105b0de:	48 89 de             	mov    %rbx,%rsi
 105b0e1:	48 ff ce             	dec    %rsi
 105b0e4:	0f 80 d1 25 00 00    	jo     105d6bb <my.vm::run+0x2b4b>
 105b0ea:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105b0f1:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b0f5:	48 39 d6             	cmp    %rdx,%rsi
 105b0f8:	0f 82 b9 13 00 00    	jb     105c4b7 <my.vm::run+0x1947>
 105b0fe:	48 89 f1             	mov    %rsi,%rcx
 105b101:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105b105:	48 21 d1             	and    %rdx,%rcx
 105b108:	48 01 f1             	add    %rsi,%rcx
 105b10b:	48 39 d1             	cmp    %rdx,%rcx
 105b10e:	0f 82 a6 13 00 00    	jb     105c4ba <my.vm::run+0x194a>
 105b114:	e9 a5 28 00 00       	jmp    105d9be <my.vm::run+0x2e4e>
 105b119:	4c 89 f7             	mov    %r14,%rdi
 105b11c:	4c 89 fe             	mov    %r15,%rsi
 105b11f:	48 89 ea             	mov    %rbp,%rdx
 105b122:	e8 19 73 00 00       	call   1062440 <my.vm::read_byte>
 105b127:	48 89 d5             	mov    %rdx,%rbp
 105b12a:	4c 89 f7             	mov    %r14,%rdi
 105b12d:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105b132:	48 89 c2             	mov    %rax,%rdx
 105b135:	e8 76 e5 00 00       	call   10696b0 <my.heap::closure_upvalue>
 105b13a:	48 89 c3             	mov    %rax,%rbx
 105b13d:	48 8d bc 24 b0 00 00 	lea    0xb0(%rsp),%rdi
 105b144:	00 
 105b145:	4c 89 f6             	mov    %r14,%rsi
 105b148:	48 89 c2             	mov    %rax,%rdx
 105b14b:	e8 60 e4 00 00       	call   10695b0 <my.heap::upvalue_obj>
 105b150:	48 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%rax
 105b157:	00 
 105b158:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105b15c:	49 8b 8e 80 00 00 00 	mov    0x80(%r14),%rcx
 105b163:	48 89 ce             	mov    %rcx,%rsi
 105b166:	48 ff ce             	dec    %rsi
 105b169:	0f 90 c2             	seto   %dl
 105b16c:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 105b170:	0f 84 ff 13 00 00    	je     105c575 <my.vm::run+0x1a05>
 105b176:	84 d2                	test   %dl,%dl
 105b178:	0f 85 ae 25 00 00    	jne    105d72c <my.vm::run+0x2bbc>
 105b17e:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105b182:	48 39 d6             	cmp    %rdx,%rsi
 105b185:	0f 83 8e 1b 00 00    	jae    105cd19 <my.vm::run+0x21a9>
 105b18b:	48 89 f1             	mov    %rsi,%rcx
 105b18e:	4d 89 fc             	mov    %r15,%r12
 105b191:	48 c1 e1 04          	shl    $0x4,%rcx
 105b195:	c5 f9 10 44 0f 20    	vmovupd 0x20(%rdi,%rcx,1),%xmm0
 105b19b:	48 39 d0             	cmp    %rdx,%rax
 105b19e:	0f 83 90 1b 00 00    	jae    105cd34 <my.vm::run+0x21c4>
 105b1a4:	48 89 c1             	mov    %rax,%rcx
 105b1a7:	48 83 c7 20          	add    $0x20,%rdi
 105b1ab:	48 c1 e1 04          	shl    $0x4,%rcx
 105b1af:	c5 f9 54 05 29 92 fa 	vandpd -0x56dd7(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105b1b6:	ff 
 105b1b7:	c5 f9 11 04 0f       	vmovupd %xmm0,(%rdi,%rcx,1)
 105b1bc:	e9 59 14 00 00       	jmp    105c61a <my.vm::run+0x1aaa>
 105b1c1:	4c 89 ee             	mov    %r13,%rsi
 105b1c4:	48 ff ce             	dec    %rsi
 105b1c7:	0f 80 b2 24 00 00    	jo     105d67f <my.vm::run+0x2b0f>
 105b1cd:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105b1d4:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b1d8:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b1dc:	48 39 d6             	cmp    %rdx,%rsi
 105b1df:	0f 83 fa 17 00 00    	jae    105c9df <my.vm::run+0x1e6f>
 105b1e5:	49 89 f5             	mov    %rsi,%r13
 105b1e8:	e9 06 16 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105b1ed:	4c 89 7c 24 18       	mov    %r15,0x18(%rsp)
 105b1f2:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105b1f9:	49 89 f5             	mov    %rsi,%r13
 105b1fc:	49 ff cd             	dec    %r13
 105b1ff:	0f 80 f4 23 00 00    	jo     105d5f9 <my.vm::run+0x2a89>
 105b205:	49 89 ec             	mov    %rbp,%r12
 105b208:	4d 8b 7e 78          	mov    0x78(%r14),%r15
 105b20c:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105b210:	4c 89 ed             	mov    %r13,%rbp
 105b213:	49 39 d5             	cmp    %rdx,%r13
 105b216:	0f 83 de 17 00 00    	jae    105c9fa <my.vm::run+0x1e8a>
 105b21c:	48 c1 e5 04          	shl    $0x4,%rbp
 105b220:	41 80 7c 2f 20 03    	cmpb   $0x3,0x20(%r15,%rbp,1)
 105b226:	0f 85 e6 11 00 00    	jne    105c412 <my.vm::run+0x18a2>
 105b22c:	49 8b 74 2f 28       	mov    0x28(%r15,%rbp,1),%rsi
 105b231:	49 8b 06             	mov    (%r14),%rax
 105b234:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b238:	48 89 f1             	mov    %rsi,%rcx
 105b23b:	48 39 d6             	cmp    %rdx,%rsi
 105b23e:	0f 83 0b 1b 00 00    	jae    105cd4f <my.vm::run+0x21df>
 105b244:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105b248:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 105b24d:	0f 85 bf 11 00 00    	jne    105c412 <my.vm::run+0x18a2>
 105b253:	48 89 74 24 30       	mov    %rsi,0x30(%rsp)
 105b258:	4c 89 f7             	mov    %r14,%rdi
 105b25b:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 105b260:	4c 89 e2             	mov    %r12,%rdx
 105b263:	e8 88 72 00 00       	call   10624f0 <my.vm::read_constant>
 105b268:	3c 03                	cmp    $0x3,%al
 105b26a:	0f 85 7f 24 00 00    	jne    105d6ef <my.vm::run+0x2b7f>
 105b270:	49 89 cc             	mov    %rcx,%r12
 105b273:	4c 89 f7             	mov    %r14,%rdi
 105b276:	48 89 d6             	mov    %rdx,%rsi
 105b279:	48 89 d3             	mov    %rdx,%rbx
 105b27c:	e8 5f df 00 00       	call   10691e0 <my.heap::string_hash>
 105b281:	4c 89 f7             	mov    %r14,%rdi
 105b284:	48 8b 74 24 30       	mov    0x30(%rsp),%rsi
 105b289:	48 89 5c 24 48       	mov    %rbx,0x48(%rsp)
 105b28e:	48 89 da             	mov    %rbx,%rdx
 105b291:	89 c1                	mov    %eax,%ecx
 105b293:	e8 28 e5 00 00       	call   10697c0 <my.heap::instance_field>
 105b298:	3c 01                	cmp    $0x1,%al
 105b29a:	0f 85 bb 15 00 00    	jne    105c85b <my.vm::run+0x1ceb>
 105b2a0:	49 8d 04 2f          	lea    (%r15,%rbp,1),%rax
 105b2a4:	48 83 c0 20          	add    $0x20,%rax
 105b2a8:	0f b6 d2             	movzbl %dl,%edx
 105b2ab:	48 89 10             	mov    %rdx,(%rax)
 105b2ae:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105b2b2:	49 ff c5             	inc    %r13
 105b2b5:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105b2bc:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105b2c3:	4c 8b 7c 24 18       	mov    0x18(%rsp),%r15
 105b2c8:	e9 80 11 00 00       	jmp    105c44d <my.vm::run+0x18dd>
 105b2cd:	4c 89 f7             	mov    %r14,%rdi
 105b2d0:	4c 89 fe             	mov    %r15,%rsi
 105b2d3:	48 89 ea             	mov    %rbp,%rdx
 105b2d6:	e8 15 72 00 00       	call   10624f0 <my.vm::read_constant>
 105b2db:	3c 03                	cmp    $0x3,%al
 105b2dd:	0f 85 0e 1e 00 00    	jne    105d0f1 <my.vm::run+0x2581>
 105b2e3:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105b2ea:	48 89 c6             	mov    %rax,%rsi
 105b2ed:	48 ff ce             	dec    %rsi
 105b2f0:	0f 80 ce 20 00 00    	jo     105d3c4 <my.vm::run+0x2854>
 105b2f6:	48 89 d3             	mov    %rdx,%rbx
 105b2f9:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b2fd:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b301:	48 39 d6             	cmp    %rdx,%rsi
 105b304:	4c 89 7c 24 18       	mov    %r15,0x18(%rsp)
 105b309:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
 105b30e:	0f 83 ba 18 00 00    	jae    105cbce <my.vm::run+0x205e>
 105b314:	48 89 f1             	mov    %rsi,%rcx
 105b317:	48 c1 e1 04          	shl    $0x4,%rcx
 105b31b:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105b320:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 105b324:	4c 89 f7             	mov    %r14,%rdi
 105b327:	48 89 de             	mov    %rbx,%rsi
 105b32a:	e8 b1 de 00 00       	call   10691e0 <my.heap::string_hash>
 105b32f:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105b333:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105b337:	48 89 da             	mov    %rbx,%rdx
 105b33a:	89 c1                	mov    %eax,%ecx
 105b33c:	41 89 e8             	mov    %ebp,%r8d
 105b33f:	4d 89 f9             	mov    %r15,%r9
 105b342:	e8 79 df 00 00       	call   10692c0 <my.table::set>
 105b347:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105b34b:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105b34f:	a8 01                	test   $0x1,%al
 105b351:	0f 84 99 00 00 00    	je     105b3f0 <my.vm::run+0x880>
 105b357:	49 89 d7             	mov    %rdx,%r15
 105b35a:	49 89 cc             	mov    %rcx,%r12
 105b35d:	4c 89 f7             	mov    %r14,%rdi
 105b360:	48 89 de             	mov    %rbx,%rsi
 105b363:	e8 78 de 00 00       	call   10691e0 <my.heap::string_hash>
 105b368:	4c 89 ff             	mov    %r15,%rdi
 105b36b:	4c 89 e6             	mov    %r12,%rsi
 105b36e:	48 89 da             	mov    %rbx,%rdx
 105b371:	89 c1                	mov    %eax,%ecx
 105b373:	e8 38 e1 00 00       	call   10694b0 <my.table::delete>
 105b378:	49 89 46 30          	mov    %rax,0x30(%r14)
 105b37c:	49 89 56 38          	mov    %rdx,0x38(%r14)
 105b380:	4c 89 f7             	mov    %r14,%rdi
 105b383:	48 89 de             	mov    %rbx,%rsi
 105b386:	e8 65 dc 00 00       	call   1068ff0 <my.heap::string_chars>
 105b38b:	48 89 c3             	mov    %rax,%rbx
 105b38e:	48 8d 3d 2b 6d fb ff 	lea    -0x492d5(%rip),%rdi        # 10120c0 <core_number_pairs+0xae60>
 105b395:	48 89 c6             	mov    %rax,%rsi
 105b398:	e8 e3 39 fd ff       	call   102ed80 <myl_core_bytes_concat>
 105b39d:	49 89 c7             	mov    %rax,%r15
 105b3a0:	48 89 df             	mov    %rbx,%rdi
 105b3a3:	e8 d8 85 fc ff       	call   1023980 <myl_core_drop_owned>
 105b3a8:	48 8d 35 51 6d fb ff 	lea    -0x492af(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 105b3af:	4c 89 ff             	mov    %r15,%rdi
 105b3b2:	e8 c9 39 fd ff       	call   102ed80 <myl_core_bytes_concat>
 105b3b7:	48 89 c3             	mov    %rax,%rbx
 105b3ba:	4c 89 ff             	mov    %r15,%rdi
 105b3bd:	e8 be 85 fc ff       	call   1023980 <myl_core_drop_owned>
 105b3c2:	48 8d bc 24 d0 00 00 	lea    0xd0(%rsp),%rdi
 105b3c9:	00 
 105b3ca:	4c 89 f6             	mov    %r14,%rsi
 105b3cd:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105b3d2:	48 89 d9             	mov    %rbx,%rcx
 105b3d5:	e8 e6 6b 00 00       	call   1061fc0 <my.vm::runtime_error>
 105b3da:	48 89 df             	mov    %rbx,%rdi
 105b3dd:	e8 9e 85 fc ff       	call   1023980 <myl_core_drop_owned>
 105b3e2:	f6 84 24 d0 00 00 00 	testb  $0x1,0xd0(%rsp)
 105b3e9:	01 
 105b3ea:	0f 84 99 1b 00 00    	je     105cf89 <my.vm::run+0x2419>
 105b3f0:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105b3f7:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105b3fe:	4c 8b 7c 24 18       	mov    0x18(%rsp),%r15
 105b403:	48 8b 6c 24 30       	mov    0x30(%rsp),%rbp
 105b408:	e9 e6 13 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105b40d:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b411:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b415:	4c 89 e9             	mov    %r13,%rcx
 105b418:	49 39 d5             	cmp    %rdx,%r13
 105b41b:	0f 83 17 15 00 00    	jae    105c938 <my.vm::run+0x1dc8>
 105b421:	48 c1 e1 04          	shl    $0x4,%rcx
 105b425:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105b42c:	00 00 
 105b42e:	c6 44 08 28 01       	movb   $0x1,0x28(%rax,%rcx,1)
 105b433:	49 89 46 78          	mov    %rax,0x78(%r14)
 105b437:	4c 89 e8             	mov    %r13,%rax
 105b43a:	48 ff c0             	inc    %rax
 105b43d:	0f 81 b5 02 00 00    	jno    105b6f8 <my.vm::run+0xb88>
 105b443:	e9 69 21 00 00       	jmp    105d5b1 <my.vm::run+0x2a41>
 105b448:	4c 89 ee             	mov    %r13,%rsi
 105b44b:	48 ff ce             	dec    %rsi
 105b44e:	0f 80 84 1f 00 00    	jo     105d3d8 <my.vm::run+0x2868>
 105b454:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105b45b:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b45f:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b463:	48 89 f1             	mov    %rsi,%rcx
 105b466:	48 39 d6             	cmp    %rdx,%rsi
 105b469:	0f 83 a6 15 00 00    	jae    105ca15 <my.vm::run+0x1ea5>
 105b46f:	49 89 f5             	mov    %rsi,%r13
 105b472:	49 ff cd             	dec    %r13
 105b475:	0f 80 68 20 00 00    	jo     105d4e3 <my.vm::run+0x2973>
 105b47b:	48 c1 e1 04          	shl    $0x4,%rcx
 105b47f:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105b485:	48 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%rdi
 105b48a:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105b491:	4c 89 e9             	mov    %r13,%rcx
 105b494:	49 39 d5             	cmp    %rdx,%r13
 105b497:	0f 83 74 16 00 00    	jae    105cb11 <my.vm::run+0x1fa1>
 105b49d:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105b4a1:	48 c1 e1 04          	shl    $0x4,%rcx
 105b4a5:	44 0f b6 0c 0a       	movzbl (%rdx,%rcx,1),%r9d
 105b4aa:	48 8b 74 0a 08       	mov    0x8(%rdx,%rcx,1),%rsi
 105b4af:	41 83 f9 02          	cmp    $0x2,%r9d
 105b4b3:	0f 84 81 12 00 00    	je     105c73a <my.vm::run+0x1bca>
 105b4b9:	41 83 f9 01          	cmp    $0x1,%r9d
 105b4bd:	0f 84 69 12 00 00    	je     105c72c <my.vm::run+0x1bbc>
 105b4c3:	45 85 c9             	test   %r9d,%r9d
 105b4c6:	0f 85 9e 12 00 00    	jne    105c76a <my.vm::run+0x1bfa>
 105b4cc:	45 84 c0             	test   %r8b,%r8b
 105b4cf:	40 0f 94 c6          	sete   %sil
 105b4d3:	e9 a4 12 00 00       	jmp    105c77c <my.vm::run+0x1c0c>
 105b4d8:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b4dc:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b4e0:	4c 89 e9             	mov    %r13,%rcx
 105b4e3:	49 39 d5             	cmp    %rdx,%r13
 105b4e6:	0f 83 67 14 00 00    	jae    105c953 <my.vm::run+0x1de3>
 105b4ec:	48 c1 e1 04          	shl    $0x4,%rcx
 105b4f0:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105b4f7:	00 00 
 105b4f9:	c6 44 08 28 00       	movb   $0x0,0x28(%rax,%rcx,1)
 105b4fe:	49 89 46 78          	mov    %rax,0x78(%r14)
 105b502:	4c 89 e8             	mov    %r13,%rax
 105b505:	48 ff c0             	inc    %rax
 105b508:	0f 81 ea 01 00 00    	jno    105b6f8 <my.vm::run+0xb88>
 105b50e:	e9 65 20 00 00       	jmp    105d578 <my.vm::run+0x2a08>
 105b513:	4c 89 f7             	mov    %r14,%rdi
 105b516:	4c 89 7c 24 18       	mov    %r15,0x18(%rsp)
 105b51b:	4c 89 fe             	mov    %r15,%rsi
 105b51e:	48 89 ea             	mov    %rbp,%rdx
 105b521:	e8 ca 6f 00 00       	call   10624f0 <my.vm::read_constant>
 105b526:	3c 03                	cmp    $0x3,%al
 105b528:	0f 85 86 1b 00 00    	jne    105d0b4 <my.vm::run+0x2544>
 105b52e:	48 89 d3             	mov    %rdx,%rbx
 105b531:	48 89 cd             	mov    %rcx,%rbp
 105b534:	4d 8b 7e 30          	mov    0x30(%r14),%r15
 105b538:	4d 8b 66 38          	mov    0x38(%r14),%r12
 105b53c:	4c 89 f7             	mov    %r14,%rdi
 105b53f:	48 89 d6             	mov    %rdx,%rsi
 105b542:	e8 99 dc 00 00       	call   10691e0 <my.heap::string_hash>
 105b547:	4c 89 ff             	mov    %r15,%rdi
 105b54a:	4c 89 e6             	mov    %r12,%rsi
 105b54d:	48 89 da             	mov    %rbx,%rdx
 105b550:	89 c1                	mov    %eax,%ecx
 105b552:	e8 79 db 00 00       	call   10690d0 <my.table::get>
 105b557:	3c 01                	cmp    $0x1,%al
 105b559:	0f 85 8e 0f 00 00    	jne    105c4ed <my.vm::run+0x197d>
 105b55f:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105b563:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105b56a:	48 8b 47 08          	mov    0x8(%rdi),%rax
 105b56e:	49 89 f0             	mov    %rsi,%r8
 105b571:	48 39 c6             	cmp    %rax,%rsi
 105b574:	0f 83 0b 18 00 00    	jae    105cd85 <my.vm::run+0x2215>
 105b57a:	49 c1 e0 04          	shl    $0x4,%r8
 105b57e:	0f b6 c2             	movzbl %dl,%eax
 105b581:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 105b586:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 105b58b:	49 89 f5             	mov    %rsi,%r13
 105b58e:	49 ff c5             	inc    %r13
 105b591:	4c 8b 7c 24 18       	mov    0x18(%rsp),%r15
 105b596:	0f 81 49 12 00 00    	jno    105c7e5 <my.vm::run+0x1c75>
 105b59c:	e9 c2 21 00 00       	jmp    105d763 <my.vm::run+0x2bf3>
 105b5a1:	4c 89 f7             	mov    %r14,%rdi
 105b5a4:	4c 89 fe             	mov    %r15,%rsi
 105b5a7:	48 89 ea             	mov    %rbp,%rdx
 105b5aa:	e8 41 6f 00 00       	call   10624f0 <my.vm::read_constant>
 105b5af:	48 89 cd             	mov    %rcx,%rbp
 105b5b2:	49 8b 76 78          	mov    0x78(%r14),%rsi
 105b5b6:	48 8b 4e 08          	mov    0x8(%rsi),%rcx
 105b5ba:	4c 89 ef             	mov    %r13,%rdi
 105b5bd:	49 39 cd             	cmp    %rcx,%r13
 105b5c0:	0f 83 a8 13 00 00    	jae    105c96e <my.vm::run+0x1dfe>
 105b5c6:	48 c1 e7 04          	shl    $0x4,%rdi
 105b5ca:	0f b6 c0             	movzbl %al,%eax
 105b5cd:	48 89 44 3e 20       	mov    %rax,0x20(%rsi,%rdi,1)
 105b5d2:	48 89 54 3e 28       	mov    %rdx,0x28(%rsi,%rdi,1)
 105b5d7:	49 89 76 78          	mov    %rsi,0x78(%r14)
 105b5db:	4c 89 e8             	mov    %r13,%rax
 105b5de:	48 ff c0             	inc    %rax
 105b5e1:	0f 81 11 01 00 00    	jno    105b6f8 <my.vm::run+0xb88>
 105b5e7:	e9 ad 1e 00 00       	jmp    105d499 <my.vm::run+0x2929>
 105b5ec:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b5f0:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b5f4:	4c 89 e9             	mov    %r13,%rcx
 105b5f7:	49 39 d5             	cmp    %rdx,%r13
 105b5fa:	0f 83 89 13 00 00    	jae    105c989 <my.vm::run+0x1e19>
 105b600:	48 c1 e1 04          	shl    $0x4,%rcx
 105b604:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105b60b:	00 00 
 105b60d:	49 89 46 78          	mov    %rax,0x78(%r14)
 105b611:	4c 89 e8             	mov    %r13,%rax
 105b614:	48 ff c0             	inc    %rax
 105b617:	0f 81 db 00 00 00    	jno    105b6f8 <my.vm::run+0xb88>
 105b61d:	e9 fc 1f 00 00       	jmp    105d61e <my.vm::run+0x2aae>
 105b622:	4c 89 f7             	mov    %r14,%rdi
 105b625:	4c 89 fe             	mov    %r15,%rsi
 105b628:	48 89 ea             	mov    %rbp,%rdx
 105b62b:	e8 60 75 00 00       	call   1062b90 <my.vm::read_short>
 105b630:	48 89 d5             	mov    %rdx,%rbp
 105b633:	48 01 c5             	add    %rax,%rbp
 105b636:	0f 81 b7 11 00 00    	jno    105c7f3 <my.vm::run+0x1c83>
 105b63c:	e9 e2 1d 00 00       	jmp    105d423 <my.vm::run+0x28b3>
 105b641:	4d 89 ec             	mov    %r13,%r12
 105b644:	49 ff cc             	dec    %r12
 105b647:	0f 80 4f 1d 00 00    	jo     105d39c <my.vm::run+0x282c>
 105b64d:	4d 89 a6 80 00 00 00 	mov    %r12,0x80(%r14)
 105b654:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b658:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b65c:	4c 89 e6             	mov    %r12,%rsi
 105b65f:	49 39 d4             	cmp    %rdx,%r12
 105b662:	0f 83 c8 13 00 00    	jae    105ca30 <my.vm::run+0x1ec0>
 105b668:	48 c1 e6 04          	shl    $0x4,%rsi
 105b66c:	48 8b 4c 30 28       	mov    0x28(%rax,%rsi,1),%rcx
 105b671:	8b 54 30 20          	mov    0x20(%rax,%rsi,1),%edx
 105b675:	4c 89 f7             	mov    %r14,%rdi
 105b678:	48 8b 74 24 08       	mov    0x8(%rsp),%rsi
 105b67d:	e8 7e 71 00 00       	call   1062800 <my.output::print_value>
 105b682:	4d 89 e5             	mov    %r12,%r13
 105b685:	e9 69 11 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105b68a:	4c 89 f7             	mov    %r14,%rdi
 105b68d:	4c 89 fe             	mov    %r15,%rsi
 105b690:	48 89 ea             	mov    %rbp,%rdx
 105b693:	e8 a8 6d 00 00       	call   1062440 <my.vm::read_byte>
 105b698:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105b69d:	48 01 c6             	add    %rax,%rsi
 105b6a0:	0f 80 8f 1d 00 00    	jo     105d435 <my.vm::run+0x28c5>
 105b6a6:	48 89 d5             	mov    %rdx,%rbp
 105b6a9:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b6ad:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b6b1:	48 39 d6             	cmp    %rdx,%rsi
 105b6b4:	0f 83 91 13 00 00    	jae    105ca4b <my.vm::run+0x1edb>
 105b6ba:	48 89 f1             	mov    %rsi,%rcx
 105b6bd:	48 c1 e1 04          	shl    $0x4,%rcx
 105b6c1:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105b6c7:	4c 89 e9             	mov    %r13,%rcx
 105b6ca:	49 39 d5             	cmp    %rdx,%r13
 105b6cd:	0f 83 c9 13 00 00    	jae    105ca9c <my.vm::run+0x1f2c>
 105b6d3:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105b6d7:	48 c1 e1 04          	shl    $0x4,%rcx
 105b6db:	c5 f9 54 05 fd 8c fa 	vandpd -0x57303(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105b6e2:	ff 
 105b6e3:	c5 f9 11 04 0a       	vmovupd %xmm0,(%rdx,%rcx,1)
 105b6e8:	49 89 46 78          	mov    %rax,0x78(%r14)
 105b6ec:	4c 89 e8             	mov    %r13,%rax
 105b6ef:	48 ff c0             	inc    %rax
 105b6f2:	0f 80 f4 1c 00 00    	jo     105d3ec <my.vm::run+0x287c>
 105b6f8:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105b6ff:	49 89 c5             	mov    %rax,%r13
 105b702:	e9 ec 10 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105b707:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105b70e:	48 89 f3             	mov    %rsi,%rbx
 105b711:	48 ff cb             	dec    %rbx
 105b714:	0f 80 93 1d 00 00    	jo     105d4ad <my.vm::run+0x293d>
 105b71a:	49 89 dd             	mov    %rbx,%r13
 105b71d:	49 ff cd             	dec    %r13
 105b720:	0f 80 37 1d 00 00    	jo     105d45d <my.vm::run+0x28ed>
 105b726:	4d 89 fc             	mov    %r15,%r12
 105b729:	4d 8b 7e 78          	mov    0x78(%r14),%r15
 105b72d:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105b731:	4c 89 e8             	mov    %r13,%rax
 105b734:	49 39 d5             	cmp    %rdx,%r13
 105b737:	0f 83 ef 13 00 00    	jae    105cb2c <my.vm::run+0x1fbc>
 105b73d:	48 c1 e0 04          	shl    $0x4,%rax
 105b741:	41 0f b6 4c 07 20    	movzbl 0x20(%r15,%rax,1),%ecx
 105b747:	85 c9                	test   %ecx,%ecx
 105b749:	0f 84 4f 10 00 00    	je     105c79e <my.vm::run+0x1c2e>
 105b74f:	83 f9 01             	cmp    $0x1,%ecx
 105b752:	0f 84 05 10 00 00    	je     105c75d <my.vm::run+0x1bed>
 105b758:	83 f9 03             	cmp    $0x3,%ecx
 105b75b:	0f 85 4a 10 00 00    	jne    105c7ab <my.vm::run+0x1c3b>
 105b761:	49 8b 74 07 28       	mov    0x28(%r15,%rax,1),%rsi
 105b766:	49 8b 06             	mov    (%r14),%rax
 105b769:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b76d:	48 89 f1             	mov    %rsi,%rcx
 105b770:	48 39 d6             	cmp    %rdx,%rsi
 105b773:	0f 83 e4 16 00 00    	jae    105ce5d <my.vm::run+0x22ed>
 105b779:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105b77d:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 105b782:	0f 85 a3 10 00 00    	jne    105c82b <my.vm::run+0x1cbb>
 105b788:	48 89 74 24 48       	mov    %rsi,0x48(%rsp)
 105b78d:	4c 89 f7             	mov    %r14,%rdi
 105b790:	4c 89 e6             	mov    %r12,%rsi
 105b793:	48 89 ea             	mov    %rbp,%rdx
 105b796:	e8 55 6d 00 00       	call   10624f0 <my.vm::read_constant>
 105b79b:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
 105b7a0:	3c 03                	cmp    $0x3,%al
 105b7a2:	0f 85 05 20 00 00    	jne    105d7ad <my.vm::run+0x2c3d>
 105b7a8:	48 89 d5             	mov    %rdx,%rbp
 105b7ab:	4c 89 f7             	mov    %r14,%rdi
 105b7ae:	48 89 d6             	mov    %rdx,%rsi
 105b7b1:	e8 2a da 00 00       	call   10691e0 <my.heap::string_hash>
 105b7b6:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105b7ba:	48 89 d9             	mov    %rbx,%rcx
 105b7bd:	48 39 d3             	cmp    %rdx,%rbx
 105b7c0:	0f 83 cd 16 00 00    	jae    105ce93 <my.vm::run+0x2323>
 105b7c6:	49 8d 57 20          	lea    0x20(%r15),%rdx
 105b7ca:	48 c1 e1 04          	shl    $0x4,%rcx
 105b7ce:	4c 8b 4c 0a 08       	mov    0x8(%rdx,%rcx,1),%r9
 105b7d3:	48 89 54 24 50       	mov    %rdx,0x50(%rsp)
 105b7d8:	44 8b 04 0a          	mov    (%rdx,%rcx,1),%r8d
 105b7dc:	4c 89 f7             	mov    %r14,%rdi
 105b7df:	48 8b 74 24 48       	mov    0x48(%rsp),%rsi
 105b7e4:	48 89 ea             	mov    %rbp,%rdx
 105b7e7:	89 c1                	mov    %eax,%ecx
 105b7e9:	e8 a2 e1 00 00       	call   1069990 <my.heap::set_instance_field>
 105b7ee:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105b7f2:	48 39 d3             	cmp    %rdx,%rbx
 105b7f5:	0f 83 b3 16 00 00    	jae    105ceae <my.vm::run+0x233e>
 105b7fb:	48 89 d8             	mov    %rbx,%rax
 105b7fe:	4d 89 e7             	mov    %r12,%r15
 105b801:	48 c1 e0 04          	shl    $0x4,%rax
 105b805:	48 8b 4c 24 50       	mov    0x50(%rsp),%rcx
 105b80a:	c5 f9 10 04 01       	vmovupd (%rcx,%rax,1),%xmm0
 105b80f:	4c 89 e8             	mov    %r13,%rax
 105b812:	49 39 d5             	cmp    %rdx,%r13
 105b815:	48 8b 6c 24 30       	mov    0x30(%rsp),%rbp
 105b81a:	0f 83 ac 16 00 00    	jae    105cecc <my.vm::run+0x235c>
 105b820:	c5 f9 54 05 b8 8b fa 	vandpd -0x57448(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105b827:	ff 
 105b828:	48 c1 e0 04          	shl    $0x4,%rax
 105b82c:	c5 f9 11 04 01       	vmovupd %xmm0,(%rcx,%rax,1)
 105b831:	e9 ac 0f 00 00       	jmp    105c7e2 <my.vm::run+0x1c72>
 105b836:	4c 89 f7             	mov    %r14,%rdi
 105b839:	4c 89 fe             	mov    %r15,%rsi
 105b83c:	48 89 ea             	mov    %rbp,%rdx
 105b83f:	e8 fc 6b 00 00       	call   1062440 <my.vm::read_byte>
 105b844:	4c 89 ee             	mov    %r13,%rsi
 105b847:	48 ff ce             	dec    %rsi
 105b84a:	0f 80 03 1d 00 00    	jo     105d553 <my.vm::run+0x29e3>
 105b850:	48 89 d5             	mov    %rdx,%rbp
 105b853:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105b857:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105b85b:	48 39 d6             	cmp    %rdx,%rsi
 105b85e:	0f 83 02 12 00 00    	jae    105ca66 <my.vm::run+0x1ef6>
 105b864:	48 89 f7             	mov    %rsi,%rdi
 105b867:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105b86c:	48 01 c6             	add    %rax,%rsi
 105b86f:	0f 80 93 1c 00 00    	jo     105d508 <my.vm::run+0x2998>
 105b875:	48 c1 e7 04          	shl    $0x4,%rdi
 105b879:	c5 f9 10 44 39 20    	vmovupd 0x20(%rcx,%rdi,1),%xmm0
 105b87f:	48 39 d6             	cmp    %rdx,%rsi
 105b882:	0f 83 bf 12 00 00    	jae    105cb47 <my.vm::run+0x1fd7>
 105b888:	48 89 f0             	mov    %rsi,%rax
 105b88b:	48 8d 51 20          	lea    0x20(%rcx),%rdx
 105b88f:	48 c1 e0 04          	shl    $0x4,%rax
 105b893:	c5 f9 54 05 45 8b fa 	vandpd -0x574bb(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105b89a:	ff 
 105b89b:	c5 f9 11 04 02       	vmovupd %xmm0,(%rdx,%rax,1)
 105b8a0:	49 89 4e 78          	mov    %rcx,0x78(%r14)
 105b8a4:	e9 4a 0f 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105b8a9:	4c 89 f7             	mov    %r14,%rdi
 105b8ac:	4c 89 fe             	mov    %r15,%rsi
 105b8af:	48 89 ea             	mov    %rbp,%rdx
 105b8b2:	e8 89 6b 00 00       	call   1062440 <my.vm::read_byte>
 105b8b7:	48 89 d5             	mov    %rdx,%rbp
 105b8ba:	4c 89 f7             	mov    %r14,%rdi
 105b8bd:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105b8c2:	48 89 c2             	mov    %rax,%rdx
 105b8c5:	e8 e6 dd 00 00       	call   10696b0 <my.heap::closure_upvalue>
 105b8ca:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105b8cf:	4c 89 f6             	mov    %r14,%rsi
 105b8d2:	48 89 c2             	mov    %rax,%rdx
 105b8d5:	e8 d6 dc 00 00       	call   10695b0 <my.heap::upvalue_obj>
 105b8da:	48 8b 74 24 70       	mov    0x70(%rsp),%rsi
 105b8df:	48 83 fe ff          	cmp    $0xffffffffffffffff,%rsi
 105b8e3:	0f 84 47 0d 00 00    	je     105c630 <my.vm::run+0x1ac0>
 105b8e9:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b8ed:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b8f1:	48 39 d6             	cmp    %rdx,%rsi
 105b8f4:	0f 83 e9 13 00 00    	jae    105cce3 <my.vm::run+0x2173>
 105b8fa:	48 89 f1             	mov    %rsi,%rcx
 105b8fd:	48 c1 e1 04          	shl    $0x4,%rcx
 105b901:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105b907:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105b90e:	48 89 f1             	mov    %rsi,%rcx
 105b911:	48 39 d6             	cmp    %rdx,%rsi
 105b914:	0f 83 e4 13 00 00    	jae    105ccfe <my.vm::run+0x218e>
 105b91a:	48 83 c0 20          	add    $0x20,%rax
 105b91e:	48 c1 e1 04          	shl    $0x4,%rcx
 105b922:	c5 f9 54 05 b6 8a fa 	vandpd -0x5754a(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105b929:	ff 
 105b92a:	c5 f9 11 04 08       	vmovupd %xmm0,(%rax,%rcx,1)
 105b92f:	49 89 f5             	mov    %rsi,%r13
 105b932:	49 ff c5             	inc    %r13
 105b935:	0f 81 aa 0e 00 00    	jno    105c7e5 <my.vm::run+0x1c75>
 105b93b:	e9 00 1e 00 00       	jmp    105d740 <my.vm::run+0x2bd0>
 105b940:	4c 89 ee             	mov    %r13,%rsi
 105b943:	48 ff ce             	dec    %rsi
 105b946:	0f 80 f7 1c 00 00    	jo     105d643 <my.vm::run+0x2ad3>
 105b94c:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b950:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b954:	49 89 e8             	mov    %rbp,%r8
 105b957:	48 39 d6             	cmp    %rdx,%rsi
 105b95a:	0f 83 21 11 00 00    	jae    105ca81 <my.vm::run+0x1f11>
 105b960:	48 89 f1             	mov    %rsi,%rcx
 105b963:	48 c1 e1 04          	shl    $0x4,%rcx
 105b967:	48 8b 5c 08 20       	mov    0x20(%rax,%rcx,1),%rbx
 105b96c:	4c 8b 64 08 28       	mov    0x28(%rax,%rcx,1),%r12
 105b971:	4c 89 f7             	mov    %r14,%rdi
 105b974:	4c 89 fd             	mov    %r15,%rbp
 105b977:	4c 89 fe             	mov    %r15,%rsi
 105b97a:	4c 89 c2             	mov    %r8,%rdx
 105b97d:	e8 6e 6b 00 00       	call   10624f0 <my.vm::read_constant>
 105b982:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
 105b987:	3c 03                	cmp    $0x3,%al
 105b989:	0f 85 ff 17 00 00    	jne    105d18e <my.vm::run+0x261e>
 105b98f:	4c 89 f7             	mov    %r14,%rdi
 105b992:	48 89 d6             	mov    %rdx,%rsi
 105b995:	49 89 d7             	mov    %rdx,%r15
 105b998:	e8 43 d8 00 00       	call   10691e0 <my.heap::string_hash>
 105b99d:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105b9a1:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105b9a5:	4c 89 fa             	mov    %r15,%rdx
 105b9a8:	89 c1                	mov    %eax,%ecx
 105b9aa:	41 89 d8             	mov    %ebx,%r8d
 105b9ad:	4d 89 e1             	mov    %r12,%r9
 105b9b0:	e8 0b d9 00 00       	call   10692c0 <my.table::set>
 105b9b5:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105b9b9:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105b9bd:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105b9c4:	49 89 f5             	mov    %rsi,%r13
 105b9c7:	49 ff cd             	dec    %r13
 105b9ca:	0f 80 d0 1b 00 00    	jo     105d5a0 <my.vm::run+0x2a30>
 105b9d0:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105b9d7:	49 8b 46 78          	mov    0x78(%r14),%rax
 105b9db:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105b9e2:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105b9e6:	49 39 d5             	cmp    %rdx,%r13
 105b9e9:	49 89 ef             	mov    %rbp,%r15
 105b9ec:	0f 83 2d 12 00 00    	jae    105cc1f <my.vm::run+0x20af>
 105b9f2:	48 8b 6c 24 30       	mov    0x30(%rsp),%rbp
 105b9f7:	e9 f7 0d 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105b9fc:	4c 89 f7             	mov    %r14,%rdi
 105b9ff:	4c 89 fe             	mov    %r15,%rsi
 105ba02:	48 89 ea             	mov    %rbp,%rdx
 105ba05:	e8 e6 6a 00 00       	call   10624f0 <my.vm::read_constant>
 105ba0a:	3c 03                	cmp    $0x3,%al
 105ba0c:	0f 85 3f 17 00 00    	jne    105d151 <my.vm::run+0x25e1>
 105ba12:	48 89 cd             	mov    %rcx,%rbp
 105ba15:	49 8b 0e             	mov    (%r14),%rcx
 105ba18:	48 8b 41 08          	mov    0x8(%rcx),%rax
 105ba1c:	48 89 d6             	mov    %rdx,%rsi
 105ba1f:	48 39 c2             	cmp    %rax,%rdx
 105ba22:	0f 83 70 11 00 00    	jae    105cb98 <my.vm::run+0x2028>
 105ba28:	48 6b f6 38          	imul   $0x38,%rsi,%rsi
 105ba2c:	8b 44 31 20          	mov    0x20(%rcx,%rsi,1),%eax
 105ba30:	83 f8 02             	cmp    $0x2,%eax
 105ba33:	0f 85 ee 15 00 00    	jne    105d027 <my.vm::run+0x24b7>
 105ba39:	48 8d 04 31          	lea    (%rcx,%rsi,1),%rax
 105ba3d:	48 83 c0 20          	add    $0x20,%rax
 105ba41:	48 8b 70 10          	mov    0x10(%rax),%rsi
 105ba45:	48 89 d7             	mov    %rdx,%rdi
 105ba48:	48 89 74 24 48       	mov    %rsi,0x48(%rsp)
 105ba4d:	e8 9e ed ff ff       	call   105a7f0 <my.object::new_closure>
 105ba52:	49 89 c5             	mov    %rax,%r13
 105ba55:	49 89 d4             	mov    %rdx,%r12
 105ba58:	be 08 00 00 00       	mov    $0x8,%esi
 105ba5d:	48 89 d7             	mov    %rdx,%rdi
 105ba60:	e8 db 7d fc ff       	call   1023840 <myl_core_list_copy>
 105ba65:	48 89 c3             	mov    %rax,%rbx
 105ba68:	48 c7 84 24 20 04 00 	movq   $0x4,0x420(%rsp)
 105ba6f:	00 04 00 00 00 
 105ba74:	4c 89 ac 24 28 04 00 	mov    %r13,0x428(%rsp)
 105ba7b:	00 
 105ba7c:	48 89 84 24 30 04 00 	mov    %rax,0x430(%rsp)
 105ba83:	00 
 105ba84:	48 8d bc 24 30 03 00 	lea    0x330(%rsp),%rdi
 105ba8b:	00 
 105ba8c:	48 8d 94 24 20 04 00 	lea    0x420(%rsp),%rdx
 105ba93:	00 
 105ba94:	4c 89 f6             	mov    %r14,%rsi
 105ba97:	e8 04 e9 ff ff       	call   105a3a0 <my.heap::allocate>
 105ba9c:	48 89 df             	mov    %rbx,%rdi
 105ba9f:	e8 dc 7e fc ff       	call   1023980 <myl_core_drop_owned>
 105baa4:	48 8b bc 24 30 03 00 	mov    0x330(%rsp),%rdi
 105baab:	00 
 105baac:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bab0:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105bab7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105babb:	48 89 f1             	mov    %rsi,%rcx
 105babe:	48 39 d6             	cmp    %rdx,%rsi
 105bac1:	0f 83 ae 11 00 00    	jae    105cc75 <my.vm::run+0x2105>
 105bac7:	48 c1 e1 04          	shl    $0x4,%rcx
 105bacb:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 105bad2:	00 00 
 105bad4:	48 89 7c 08 28       	mov    %rdi,0x28(%rax,%rcx,1)
 105bad9:	48 89 f0             	mov    %rsi,%rax
 105badc:	48 ff c0             	inc    %rax
 105badf:	0f 80 82 1a 00 00    	jo     105d567 <my.vm::run+0x29f7>
 105bae5:	48 89 7c 24 68       	mov    %rdi,0x68(%rsp)
 105baea:	4c 89 6c 24 60       	mov    %r13,0x60(%rsp)
 105baef:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105baf6:	be 08 00 00 00       	mov    $0x8,%esi
 105bafb:	4c 89 e7             	mov    %r12,%rdi
 105bafe:	e8 3d 7d fc ff       	call   1023840 <myl_core_list_copy>
 105bb03:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
 105bb08:	4c 89 e7             	mov    %r12,%rdi
 105bb0b:	e8 70 7e fc ff       	call   1023980 <myl_core_drop_owned>
 105bb10:	48 83 7c 24 48 00    	cmpq   $0x0,0x48(%rsp)
 105bb16:	0f 8e 75 08 00 00    	jle    105c391 <my.vm::run+0x1821>
 105bb1c:	45 31 ed             	xor    %r13d,%r13d
 105bb1f:	eb 34                	jmp    105bb55 <my.vm::run+0xfe5>
 105bb21:	4d 89 a6 98 00 00 00 	mov    %r12,0x98(%r14)
 105bb28:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
 105bb2d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bb31:	49 39 d5             	cmp    %rdx,%r13
 105bb34:	49 89 df             	mov    %rbx,%r15
 105bb37:	48 8b 6c 24 30       	mov    0x30(%rsp),%rbp
 105bb3c:	0f 83 0c 15 00 00    	jae    105d04e <my.vm::run+0x24de>
 105bb42:	4e 89 64 e8 20       	mov    %r12,0x20(%rax,%r13,8)
 105bb47:	49 ff c5             	inc    %r13
 105bb4a:	4c 3b 6c 24 48       	cmp    0x48(%rsp),%r13
 105bb4f:	0f 84 3c 08 00 00    	je     105c391 <my.vm::run+0x1821>
 105bb55:	4c 89 f7             	mov    %r14,%rdi
 105bb58:	4c 89 fe             	mov    %r15,%rsi
 105bb5b:	48 89 ea             	mov    %rbp,%rdx
 105bb5e:	e8 dd 68 00 00       	call   1062440 <my.vm::read_byte>
 105bb63:	4c 89 fe             	mov    %r15,%rsi
 105bb66:	49 89 c7             	mov    %rax,%r15
 105bb69:	4c 89 f7             	mov    %r14,%rdi
 105bb6c:	48 89 f3             	mov    %rsi,%rbx
 105bb6f:	e8 cc 68 00 00       	call   1062440 <my.vm::read_byte>
 105bb74:	48 89 d5             	mov    %rdx,%rbp
 105bb77:	49 83 ff 01          	cmp    $0x1,%r15
 105bb7b:	0f 85 ef 00 00 00    	jne    105bc70 <my.vm::run+0x1100>
 105bb81:	49 89 c7             	mov    %rax,%r15
 105bb84:	4c 03 7c 24 20       	add    0x20(%rsp),%r15
 105bb89:	0f 80 dd 14 00 00    	jo     105d06c <my.vm::run+0x24fc>
 105bb8f:	48 89 6c 24 30       	mov    %rbp,0x30(%rsp)
 105bb94:	4d 8b a6 98 00 00 00 	mov    0x98(%r14),%r12
 105bb9b:	49 83 fc ff          	cmp    $0xffffffffffffffff,%r12
 105bb9f:	0f 84 f8 00 00 00    	je     105bc9d <my.vm::run+0x112d>
 105bba5:	48 8d bc 24 20 02 00 	lea    0x220(%rsp),%rdi
 105bbac:	00 
 105bbad:	4c 89 f6             	mov    %r14,%rsi
 105bbb0:	4c 89 e2             	mov    %r12,%rdx
 105bbb3:	e8 f8 d9 00 00       	call   10695b0 <my.heap::upvalue_obj>
 105bbb8:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 105bbbf:	4c 39 bc 24 20 02 00 	cmp    %r15,0x220(%rsp)
 105bbc6:	00 
 105bbc7:	7e 7c                	jle    105bc45 <my.vm::run+0x10d5>
 105bbc9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105bbd0:	0f 1f 84 00 00 00 00 
 105bbd7:	00 
 105bbd8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105bbdf:	0f 1f 84 00 00 00 00 
 105bbe6:	00 
 105bbe7:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105bbee:	0f 1f 84 00 00 00 00 
 105bbf5:	00 
 105bbf6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 105bbfd:	00 00 00 
 105bc00:	4c 89 e5             	mov    %r12,%rbp
 105bc03:	48 8d bc 24 00 02 00 	lea    0x200(%rsp),%rdi
 105bc0a:	00 
 105bc0b:	4c 89 f6             	mov    %r14,%rsi
 105bc0e:	4c 89 e2             	mov    %r12,%rdx
 105bc11:	e8 9a d9 00 00       	call   10695b0 <my.heap::upvalue_obj>
 105bc16:	4c 8b a4 24 18 02 00 	mov    0x218(%rsp),%r12
 105bc1d:	00 
 105bc1e:	49 83 fc ff          	cmp    $0xffffffffffffffff,%r12
 105bc22:	0f 84 85 00 00 00    	je     105bcad <my.vm::run+0x113d>
 105bc28:	48 8d bc 24 e0 01 00 	lea    0x1e0(%rsp),%rdi
 105bc2f:	00 
 105bc30:	4c 89 f6             	mov    %r14,%rsi
 105bc33:	4c 89 e2             	mov    %r12,%rdx
 105bc36:	e8 75 d9 00 00       	call   10695b0 <my.heap::upvalue_obj>
 105bc3b:	4c 39 bc 24 e0 01 00 	cmp    %r15,0x1e0(%rsp)
 105bc42:	00 
 105bc43:	7f bb                	jg     105bc00 <my.vm::run+0x1090>
 105bc45:	48 8d bc 24 c0 01 00 	lea    0x1c0(%rsp),%rdi
 105bc4c:	00 
 105bc4d:	4c 89 f6             	mov    %r14,%rsi
 105bc50:	4c 89 e2             	mov    %r12,%rdx
 105bc53:	e8 58 d9 00 00       	call   10695b0 <my.heap::upvalue_obj>
 105bc58:	4c 39 bc 24 c0 01 00 	cmp    %r15,0x1c0(%rsp)
 105bc5f:	00 
 105bc60:	0f 84 c2 fe ff ff    	je     105bb28 <my.vm::run+0xfb8>
 105bc66:	eb 4c                	jmp    105bcb4 <my.vm::run+0x1144>
 105bc68:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 105bc6f:	00 
 105bc70:	4c 89 f7             	mov    %r14,%rdi
 105bc73:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105bc78:	48 89 c2             	mov    %rax,%rdx
 105bc7b:	e8 30 da 00 00       	call   10696b0 <my.heap::closure_upvalue>
 105bc80:	49 89 c4             	mov    %rax,%r12
 105bc83:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
 105bc88:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bc8c:	49 39 d5             	cmp    %rdx,%r13
 105bc8f:	0f 83 c8 13 00 00    	jae    105d05d <my.vm::run+0x24ed>
 105bc95:	49 89 df             	mov    %rbx,%r15
 105bc98:	e9 a5 fe ff ff       	jmp    105bb42 <my.vm::run+0xfd2>
 105bc9d:	49 c7 c4 ff ff ff ff 	mov    $0xffffffffffffffff,%r12
 105bca4:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 105bcab:	eb 07                	jmp    105bcb4 <my.vm::run+0x1144>
 105bcad:	49 c7 c4 ff ff ff ff 	mov    $0xffffffffffffffff,%r12
 105bcb4:	48 c7 84 24 40 02 00 	movq   $0x5,0x240(%rsp)
 105bcbb:	00 05 00 00 00 
 105bcc0:	4c 89 bc 24 48 02 00 	mov    %r15,0x248(%rsp)
 105bcc7:	00 
 105bcc8:	48 c7 84 24 50 02 00 	movq   $0x0,0x250(%rsp)
 105bccf:	00 00 00 00 00 
 105bcd4:	4c 89 a4 24 60 02 00 	mov    %r12,0x260(%rsp)
 105bcdb:	00 
 105bcdc:	48 8d bc 24 d0 00 00 	lea    0xd0(%rsp),%rdi
 105bce3:	00 
 105bce4:	48 8d 94 24 40 02 00 	lea    0x240(%rsp),%rdx
 105bceb:	00 
 105bcec:	4c 89 f6             	mov    %r14,%rsi
 105bcef:	e8 ac e6 ff ff       	call   105a3a0 <my.heap::allocate>
 105bcf4:	4c 8b a4 24 d0 00 00 	mov    0xd0(%rsp),%r12
 105bcfb:	00 
 105bcfc:	48 83 fd ff          	cmp    $0xffffffffffffffff,%rbp
 105bd00:	0f 84 1b fe ff ff    	je     105bb21 <my.vm::run+0xfb1>
 105bd06:	48 8d bc 24 90 00 00 	lea    0x90(%rsp),%rdi
 105bd0d:	00 
 105bd0e:	4c 89 f6             	mov    %r14,%rsi
 105bd11:	48 89 ea             	mov    %rbp,%rdx
 105bd14:	e8 97 d8 00 00       	call   10695b0 <my.heap::upvalue_obj>
 105bd19:	48 8b b4 24 a0 00 00 	mov    0xa0(%rsp),%rsi
 105bd20:	00 
 105bd21:	44 0f b6 8c 24 98 00 	movzbl 0x98(%rsp),%r9d
 105bd28:	00 00 
 105bd2a:	4c 8b 94 24 90 00 00 	mov    0x90(%rsp),%r10
 105bd31:	00 
 105bd32:	4d 8b 06             	mov    (%r14),%r8
 105bd35:	49 8b 50 08          	mov    0x8(%r8),%rdx
 105bd39:	48 39 d5             	cmp    %rdx,%rbp
 105bd3c:	0f 83 86 00 00 00    	jae    105bdc8 <my.vm::run+0x1258>
 105bd42:	48 89 e8             	mov    %rbp,%rax
 105bd45:	4c 6b d8 38          	imul   $0x38,%rax,%r11
 105bd49:	43 0f b6 54 18 20    	movzbl 0x20(%r8,%r11,1),%edx
 105bd4f:	4b 8b 44 18 28       	mov    0x28(%r8,%r11,1),%rax
 105bd54:	4b 8b 7c 18 30       	mov    0x30(%r8,%r11,1),%rdi
 105bd59:	4b 8b 4c 18 38       	mov    0x38(%r8,%r11,1),%rcx
 105bd5e:	4f 8b 7c 18 40       	mov    0x40(%r8,%r11,1),%r15
 105bd63:	4b 8b 6c 18 48       	mov    0x48(%r8,%r11,1),%rbp
 105bd68:	4b c7 44 18 20 05 00 	movq   $0x5,0x20(%r8,%r11,1)
 105bd6f:	00 00 
 105bd71:	4f 89 54 18 28       	mov    %r10,0x28(%r8,%r11,1)
 105bd76:	45 0f b6 c9          	movzbl %r9b,%r9d
 105bd7a:	4f 89 4c 18 30       	mov    %r9,0x30(%r8,%r11,1)
 105bd7f:	4b 89 74 18 38       	mov    %rsi,0x38(%r8,%r11,1)
 105bd84:	4f 89 64 18 40       	mov    %r12,0x40(%r8,%r11,1)
 105bd89:	ff ca                	dec    %edx
 105bd8b:	83 fa 08             	cmp    $0x8,%edx
 105bd8e:	0f 87 94 fd ff ff    	ja     105bb28 <my.vm::run+0xfb8>
 105bd94:	48 8d 35 cd b6 fa ff 	lea    -0x54933(%rip),%rsi        # 1007468 <core_number_pairs+0x208>
 105bd9b:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105bd9f:	48 01 f2             	add    %rsi,%rdx
 105bda2:	ff e2                	jmp    *%rdx
 105bda4:	e8 d7 7b fc ff       	call   1023980 <myl_core_drop_owned>
 105bda9:	e9 7a fd ff ff       	jmp    105bb28 <my.vm::run+0xfb8>
 105bdae:	48 89 cf             	mov    %rcx,%rdi
 105bdb1:	e8 ca 7b fc ff       	call   1023980 <myl_core_drop_owned>
 105bdb6:	4c 89 ff             	mov    %r15,%rdi
 105bdb9:	e8 c2 7b fc ff       	call   1023980 <myl_core_drop_owned>
 105bdbe:	48 89 ef             	mov    %rbp,%rdi
 105bdc1:	eb e1                	jmp    105bda4 <my.vm::run+0x1234>
 105bdc3:	48 89 c7             	mov    %rax,%rdi
 105bdc6:	eb dc                	jmp    105bda4 <my.vm::run+0x1234>
 105bdc8:	48 89 e8             	mov    %rbp,%rax
 105bdcb:	48 c1 f8 3f          	sar    $0x3f,%rax
 105bdcf:	48 21 d0             	and    %rdx,%rax
 105bdd2:	48 01 e8             	add    %rbp,%rax
 105bdd5:	48 39 d0             	cmp    %rdx,%rax
 105bdd8:	0f 82 67 ff ff ff    	jb     105bd45 <my.vm::run+0x11d5>
 105bdde:	e9 2d 1b 00 00       	jmp    105d910 <my.vm::run+0x2da0>
 105bde3:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105bdea:	48 89 c6             	mov    %rax,%rsi
 105bded:	48 ff ce             	dec    %rsi
 105bdf0:	0f 80 75 18 00 00    	jo     105d66b <my.vm::run+0x2afb>
 105bdf6:	49 8b 46 78          	mov    0x78(%r14),%rax
 105bdfa:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105bdfe:	49 89 f1             	mov    %rsi,%r9
 105be01:	49 c1 f9 3f          	sar    $0x3f,%r9
 105be05:	49 21 d1             	and    %rdx,%r9
 105be08:	48 89 f1             	mov    %rsi,%rcx
 105be0b:	48 39 d6             	cmp    %rdx,%rsi
 105be0e:	0f 83 a3 0c 00 00    	jae    105cab7 <my.vm::run+0x1f47>
 105be14:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105be18:	48 c1 e1 04          	shl    $0x4,%rcx
 105be1c:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105be22:	48 8b 44 08 28       	mov    0x28(%rax,%rcx,1),%rax
 105be27:	41 83 f8 02          	cmp    $0x2,%r8d
 105be2b:	0f 84 74 08 00 00    	je     105c6a5 <my.vm::run+0x1b35>
 105be31:	41 83 f8 03          	cmp    $0x3,%r8d
 105be35:	0f 85 aa 08 00 00    	jne    105c6e5 <my.vm::run+0x1b75>
 105be3b:	4d 8b 16             	mov    (%r14),%r10
 105be3e:	49 8b 4a 08          	mov    0x8(%r10),%rcx
 105be42:	48 39 c8             	cmp    %rcx,%rax
 105be45:	0f 83 c1 0f 00 00    	jae    105ce0c <my.vm::run+0x229c>
 105be4b:	49 89 c0             	mov    %rax,%r8
 105be4e:	49 6b c0 38          	imul   $0x38,%r8,%rax
 105be52:	41 83 7c 02 20 01    	cmpl   $0x1,0x20(%r10,%rax,1)
 105be58:	0f 85 87 08 00 00    	jne    105c6e5 <my.vm::run+0x1b75>
 105be5e:	48 89 f0             	mov    %rsi,%rax
 105be61:	48 ff c8             	dec    %rax
 105be64:	0f 80 a4 19 00 00    	jo     105d80e <my.vm::run+0x2c9e>
 105be6a:	49 89 c0             	mov    %rax,%r8
 105be6d:	48 39 d0             	cmp    %rdx,%rax
 105be70:	0f 83 02 10 00 00    	jae    105ce78 <my.vm::run+0x2308>
 105be76:	49 c1 e0 04          	shl    $0x4,%r8
 105be7a:	42 80 3c 07 03       	cmpb   $0x3,(%rdi,%r8,1)
 105be7f:	0f 85 60 08 00 00    	jne    105c6e5 <my.vm::run+0x1b75>
 105be85:	4e 8b 44 07 08       	mov    0x8(%rdi,%r8,1),%r8
 105be8a:	49 39 c8             	cmp    %rcx,%r8
 105be8d:	0f 83 6f 10 00 00    	jae    105cf02 <my.vm::run+0x2392>
 105be93:	4d 89 c3             	mov    %r8,%r11
 105be96:	49 83 c2 20          	add    $0x20,%r10
 105be9a:	49 6b cb 38          	imul   $0x38,%r11,%rcx
 105be9e:	41 83 3c 0a 01       	cmpl   $0x1,(%r10,%rcx,1)
 105bea3:	0f 85 3c 08 00 00    	jne    105c6e5 <my.vm::run+0x1b75>
 105bea9:	48 39 d6             	cmp    %rdx,%rsi
 105beac:	0f 83 6b 10 00 00    	jae    105cf1d <my.vm::run+0x23ad>
 105beb2:	49 89 f1             	mov    %rsi,%r9
 105beb5:	49 c1 e1 04          	shl    $0x4,%r9
 105beb9:	42 0f b6 0c 0f       	movzbl (%rdi,%r9,1),%ecx
 105bebe:	83 f9 03             	cmp    $0x3,%ecx
 105bec1:	0f 85 9b 19 00 00    	jne    105d862 <my.vm::run+0x2cf2>
 105bec7:	4a 8b 4c 0f 08       	mov    0x8(%rdi,%r9,1),%rcx
 105becc:	48 39 d0             	cmp    %rdx,%rax
 105becf:	0f 83 59 10 00 00    	jae    105cf2e <my.vm::run+0x23be>
 105bed5:	48 89 c6             	mov    %rax,%rsi
 105bed8:	48 c1 e6 04          	shl    $0x4,%rsi
 105bedc:	0f b6 04 37          	movzbl (%rdi,%rsi,1),%eax
 105bee0:	83 f8 03             	cmp    $0x3,%eax
 105bee3:	0f 85 36 19 00 00    	jne    105d81f <my.vm::run+0x2caf>
 105bee9:	48 01 f7             	add    %rsi,%rdi
 105beec:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105bef0:	48 8d bc 24 30 03 00 	lea    0x330(%rsp),%rdi
 105bef7:	00 
 105bef8:	4c 89 f6             	mov    %r14,%rsi
 105befb:	e8 40 18 01 00       	call   106d740 <my.lox_strings::concat>
 105bf00:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105bf07:	48 89 c6             	mov    %rax,%rsi
 105bf0a:	48 ff ce             	dec    %rsi
 105bf0d:	0f 80 7c 19 00 00    	jo     105d88f <my.vm::run+0x2d1f>
 105bf13:	48 8b 84 24 30 03 00 	mov    0x330(%rsp),%rax
 105bf1a:	00 
 105bf1b:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105bf1f:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105bf23:	48 39 d6             	cmp    %rdx,%rsi
 105bf26:	0f 83 1d 10 00 00    	jae    105cf49 <my.vm::run+0x23d9>
 105bf2c:	49 89 f5             	mov    %rsi,%r13
 105bf2f:	49 ff cd             	dec    %r13
 105bf32:	0f 80 6b 19 00 00    	jo     105d8a3 <my.vm::run+0x2d33>
 105bf38:	4c 89 ee             	mov    %r13,%rsi
 105bf3b:	49 39 d5             	cmp    %rdx,%r13
 105bf3e:	0f 83 20 10 00 00    	jae    105cf64 <my.vm::run+0x23f4>
 105bf44:	48 c1 e6 04          	shl    $0x4,%rsi
 105bf48:	48 c7 44 31 20 03 00 	movq   $0x3,0x20(%rcx,%rsi,1)
 105bf4f:	00 00 
 105bf51:	48 89 44 31 28       	mov    %rax,0x28(%rcx,%rsi,1)
 105bf56:	e9 87 08 00 00       	jmp    105c7e2 <my.vm::run+0x1c72>
 105bf5b:	4c 89 f7             	mov    %r14,%rdi
 105bf5e:	4c 89 fe             	mov    %r15,%rsi
 105bf61:	48 89 ea             	mov    %rbp,%rdx
 105bf64:	e8 87 65 00 00       	call   10624f0 <my.vm::read_constant>
 105bf69:	3c 03                	cmp    $0x3,%al
 105bf6b:	0f 85 7a 12 00 00    	jne    105d1eb <my.vm::run+0x267b>
 105bf71:	4c 89 fe             	mov    %r15,%rsi
 105bf74:	49 89 d7             	mov    %rdx,%r15
 105bf77:	4c 89 f7             	mov    %r14,%rdi
 105bf7a:	48 89 ca             	mov    %rcx,%rdx
 105bf7d:	e8 be 64 00 00       	call   1062440 <my.vm::read_byte>
 105bf82:	49 8b 8e 88 00 00 00 	mov    0x88(%r14),%rcx
 105bf89:	48 85 db             	test   %rbx,%rbx
 105bf8c:	7f 04                	jg     105bf92 <my.vm::run+0x1422>
 105bf8e:	4c 03 61 08          	add    0x8(%rcx),%r12
 105bf92:	49 c1 e4 05          	shl    $0x5,%r12
 105bf96:	4a 89 54 21 30       	mov    %rdx,0x30(%rcx,%r12,1)
 105bf9b:	49 89 8e 88 00 00 00 	mov    %rcx,0x88(%r14)
 105bfa2:	4c 89 ee             	mov    %r13,%rsi
 105bfa5:	48 ff ce             	dec    %rsi
 105bfa8:	0f 80 02 14 00 00    	jo     105d3b0 <my.vm::run+0x2840>
 105bfae:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105bfb5:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105bfb9:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105bfbd:	48 39 d6             	cmp    %rdx,%rsi
 105bfc0:	0f 83 23 0c 00 00    	jae    105cbe9 <my.vm::run+0x2079>
 105bfc6:	48 89 f7             	mov    %rsi,%rdi
 105bfc9:	48 c1 e7 04          	shl    $0x4,%rdi
 105bfcd:	0f b6 54 39 20       	movzbl 0x20(%rcx,%rdi,1),%edx
 105bfd2:	83 fa 03             	cmp    $0x3,%edx
 105bfd5:	0f 85 d3 11 00 00    	jne    105d1ae <my.vm::run+0x263e>
 105bfdb:	48 01 f9             	add    %rdi,%rcx
 105bfde:	48 83 c1 20          	add    $0x20,%rcx
 105bfe2:	48 8b 49 08          	mov    0x8(%rcx),%rcx
 105bfe6:	48 8d bc 24 d8 05 00 	lea    0x5d8(%rsp),%rdi
 105bfed:	00 
 105bfee:	4c 89 f6             	mov    %r14,%rsi
 105bff1:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105bff6:	4d 89 f8             	mov    %r15,%r8
 105bff9:	49 89 c1             	mov    %rax,%r9
 105bffc:	e8 ef 72 00 00       	call   10632f0 <my.vm::invoke_from_class>
 105c001:	f6 84 24 d8 05 00 00 	testb  $0x1,0x5d8(%rsp)
 105c008:	01 
 105c009:	0f 84 7a 0f 00 00    	je     105cf89 <my.vm::run+0x2419>
 105c00f:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105c016:	48 89 de             	mov    %rbx,%rsi
 105c019:	48 ff ce             	dec    %rsi
 105c01c:	0f 80 ad 16 00 00    	jo     105d6cf <my.vm::run+0x2b5f>
 105c022:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105c029:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105c030:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c034:	48 39 d6             	cmp    %rdx,%rsi
 105c037:	0f 82 7a 04 00 00    	jb     105c4b7 <my.vm::run+0x1947>
 105c03d:	48 89 f1             	mov    %rsi,%rcx
 105c040:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105c044:	48 21 d1             	and    %rdx,%rcx
 105c047:	48 01 f1             	add    %rsi,%rcx
 105c04a:	48 39 d1             	cmp    %rdx,%rcx
 105c04d:	0f 82 67 04 00 00    	jb     105c4ba <my.vm::run+0x194a>
 105c053:	e9 f4 18 00 00       	jmp    105d94c <my.vm::run+0x2ddc>
 105c058:	4c 89 ee             	mov    %r13,%rsi
 105c05b:	48 ff ce             	dec    %rsi
 105c05e:	0f 80 0d 14 00 00    	jo     105d471 <my.vm::run+0x2901>
 105c064:	4c 89 f7             	mov    %r14,%rdi
 105c067:	e8 a4 73 00 00       	call   1063410 <my.vm::close_upvalues>
 105c06c:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105c073:	49 89 f5             	mov    %rsi,%r13
 105c076:	49 ff cd             	dec    %r13
 105c079:	0f 80 81 13 00 00    	jo     105d400 <my.vm::run+0x2890>
 105c07f:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105c086:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c08a:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105c091:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c095:	49 39 d5             	cmp    %rdx,%r13
 105c098:	0f 82 55 07 00 00    	jb     105c7f3 <my.vm::run+0x1c83>
 105c09e:	4c 89 e8             	mov    %r13,%rax
 105c0a1:	48 c1 f8 3f          	sar    $0x3f,%rax
 105c0a5:	48 21 d0             	and    %rdx,%rax
 105c0a8:	4c 01 e8             	add    %r13,%rax
 105c0ab:	48 39 d0             	cmp    %rdx,%rax
 105c0ae:	0f 82 3f 07 00 00    	jb     105c7f3 <my.vm::run+0x1c83>
 105c0b4:	e9 3b 19 00 00       	jmp    105d9f4 <my.vm::run+0x2e84>
 105c0b9:	4c 89 ee             	mov    %r13,%rsi
 105c0bc:	48 ff ce             	dec    %rsi
 105c0bf:	0f 80 c0 13 00 00    	jo     105d485 <my.vm::run+0x2915>
 105c0c5:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105c0cc:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c0d0:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c0d4:	48 89 f1             	mov    %rsi,%rcx
 105c0d7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105c0db:	48 21 d1             	and    %rdx,%rcx
 105c0de:	48 89 f7             	mov    %rsi,%rdi
 105c0e1:	48 39 d6             	cmp    %rdx,%rsi
 105c0e4:	0f 83 df 09 00 00    	jae    105cac9 <my.vm::run+0x1f59>
 105c0ea:	48 c1 e7 04          	shl    $0x4,%rdi
 105c0ee:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 105c0f3:	85 d2                	test   %edx,%edx
 105c0f5:	0f 84 f6 05 00 00    	je     105c6f1 <my.vm::run+0x1b81>
 105c0fb:	83 fa 01             	cmp    $0x1,%edx
 105c0fe:	0f 85 f1 05 00 00    	jne    105c6f5 <my.vm::run+0x1b85>
 105c104:	48 8d 14 38          	lea    (%rax,%rdi,1),%rdx
 105c108:	48 83 c2 20          	add    $0x20,%rdx
 105c10c:	0f b6 52 08          	movzbl 0x8(%rdx),%edx
 105c110:	f6 d2                	not    %dl
 105c112:	80 e2 01             	and    $0x1,%dl
 105c115:	e9 dd 05 00 00       	jmp    105c6f7 <my.vm::run+0x1b87>
 105c11a:	4c 89 f7             	mov    %r14,%rdi
 105c11d:	4c 89 fe             	mov    %r15,%rsi
 105c120:	48 89 ea             	mov    %rbp,%rdx
 105c123:	e8 18 63 00 00       	call   1062440 <my.vm::read_byte>
 105c128:	49 8b 8e 88 00 00 00 	mov    0x88(%r14),%rcx
 105c12f:	48 85 db             	test   %rbx,%rbx
 105c132:	7f 04                	jg     105c138 <my.vm::run+0x15c8>
 105c134:	4c 03 61 08          	add    0x8(%rcx),%r12
 105c138:	49 c1 e4 05          	shl    $0x5,%r12
 105c13c:	4a 89 54 21 30       	mov    %rdx,0x30(%rcx,%r12,1)
 105c141:	49 89 8e 88 00 00 00 	mov    %rcx,0x88(%r14)
 105c148:	4c 89 e9             	mov    %r13,%rcx
 105c14b:	48 ff c9             	dec    %rcx
 105c14e:	0f 80 03 15 00 00    	jo     105d657 <my.vm::run+0x2ae7>
 105c154:	48 89 ce             	mov    %rcx,%rsi
 105c157:	48 29 c6             	sub    %rax,%rsi
 105c15a:	0f 80 76 14 00 00    	jo     105d5d6 <my.vm::run+0x2a66>
 105c160:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105c164:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105c168:	48 39 d6             	cmp    %rdx,%rsi
 105c16b:	0f 83 f1 09 00 00    	jae    105cb62 <my.vm::run+0x1ff2>
 105c171:	48 89 f7             	mov    %rsi,%rdi
 105c174:	48 c1 e7 04          	shl    $0x4,%rdi
 105c178:	4c 8b 44 39 28       	mov    0x28(%rcx,%rdi,1),%r8
 105c17d:	8b 4c 39 20          	mov    0x20(%rcx,%rdi,1),%ecx
 105c181:	48 8b 54 24 58       	mov    0x58(%rsp),%rdx
 105c186:	48 89 14 24          	mov    %rdx,(%rsp)
 105c18a:	48 8d bc 24 c8 06 00 	lea    0x6c8(%rsp),%rdi
 105c191:	00 
 105c192:	4c 89 f6             	mov    %r14,%rsi
 105c195:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105c19a:	49 89 c1             	mov    %rax,%r9
 105c19d:	e8 9e 6b 00 00       	call   1062d40 <my.vm::call_value>
 105c1a2:	f6 84 24 c8 06 00 00 	testb  $0x1,0x6c8(%rsp)
 105c1a9:	01 
 105c1aa:	0f 84 d9 0d 00 00    	je     105cf89 <my.vm::run+0x2419>
 105c1b0:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105c1b7:	48 89 de             	mov    %rbx,%rsi
 105c1ba:	48 ff ce             	dec    %rsi
 105c1bd:	0f 80 d0 14 00 00    	jo     105d693 <my.vm::run+0x2b23>
 105c1c3:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105c1ca:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105c1d1:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c1d5:	48 39 d6             	cmp    %rdx,%rsi
 105c1d8:	0f 82 d9 02 00 00    	jb     105c4b7 <my.vm::run+0x1947>
 105c1de:	48 89 f1             	mov    %rsi,%rcx
 105c1e1:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105c1e5:	48 21 d1             	and    %rdx,%rcx
 105c1e8:	48 01 f1             	add    %rsi,%rcx
 105c1eb:	48 39 d1             	cmp    %rdx,%rcx
 105c1ee:	0f 82 c6 02 00 00    	jb     105c4ba <my.vm::run+0x194a>
 105c1f4:	e9 7a 17 00 00       	jmp    105d973 <my.vm::run+0x2e03>
 105c1f9:	4c 89 f7             	mov    %r14,%rdi
 105c1fc:	4c 89 fe             	mov    %r15,%rsi
 105c1ff:	48 89 ea             	mov    %rbp,%rdx
 105c202:	e8 e9 62 00 00       	call   10624f0 <my.vm::read_constant>
 105c207:	3c 03                	cmp    $0x3,%al
 105c209:	0f 85 bc 0f 00 00    	jne    105d1cb <my.vm::run+0x265b>
 105c20f:	4c 89 fe             	mov    %r15,%rsi
 105c212:	49 89 d7             	mov    %rdx,%r15
 105c215:	4c 89 f7             	mov    %r14,%rdi
 105c218:	48 89 ca             	mov    %rcx,%rdx
 105c21b:	e8 20 62 00 00       	call   1062440 <my.vm::read_byte>
 105c220:	49 8b 8e 88 00 00 00 	mov    0x88(%r14),%rcx
 105c227:	48 85 db             	test   %rbx,%rbx
 105c22a:	7f 04                	jg     105c230 <my.vm::run+0x16c0>
 105c22c:	4c 03 61 08          	add    0x8(%rcx),%r12
 105c230:	49 c1 e4 05          	shl    $0x5,%r12
 105c234:	4a 89 54 21 30       	mov    %rdx,0x30(%rcx,%r12,1)
 105c239:	49 89 8e 88 00 00 00 	mov    %rcx,0x88(%r14)
 105c240:	49 8b 9e 80 00 00 00 	mov    0x80(%r14),%rbx
 105c247:	48 89 d9             	mov    %rbx,%rcx
 105c24a:	48 ff c9             	dec    %rcx
 105c24d:	0f 80 7c 12 00 00    	jo     105d4cf <my.vm::run+0x295f>
 105c253:	48 89 ce             	mov    %rcx,%rsi
 105c256:	48 29 c6             	sub    %rax,%rsi
 105c259:	0f 80 b2 11 00 00    	jo     105d411 <my.vm::run+0x28a1>
 105c25f:	49 8b 6e 78          	mov    0x78(%r14),%rbp
 105c263:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105c267:	48 39 d6             	cmp    %rdx,%rsi
 105c26a:	0f 83 cf 09 00 00    	jae    105cc3f <my.vm::run+0x20cf>
 105c270:	48 89 f1             	mov    %rsi,%rcx
 105c273:	48 c1 e1 04          	shl    $0x4,%rcx
 105c277:	80 7c 0d 20 03       	cmpb   $0x3,0x20(%rbp,%rcx,1)
 105c27c:	0f 85 df 01 00 00    	jne    105c461 <my.vm::run+0x18f1>
 105c282:	4c 8b 64 0d 28       	mov    0x28(%rbp,%rcx,1),%r12
 105c287:	49 8b 0e             	mov    (%r14),%rcx
 105c28a:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105c28e:	4c 89 e6             	mov    %r12,%rsi
 105c291:	49 39 d4             	cmp    %rdx,%r12
 105c294:	0f 83 06 0b 00 00    	jae    105cda0 <my.vm::run+0x2230>
 105c29a:	48 6b d6 38          	imul   $0x38,%rsi,%rdx
 105c29e:	83 7c 11 20 07       	cmpl   $0x7,0x20(%rcx,%rdx,1)
 105c2a3:	0f 85 b8 01 00 00    	jne    105c461 <my.vm::run+0x18f1>
 105c2a9:	49 89 c5             	mov    %rax,%r13
 105c2ac:	4c 89 f7             	mov    %r14,%rdi
 105c2af:	4c 89 fe             	mov    %r15,%rsi
 105c2b2:	e8 29 cf 00 00       	call   10691e0 <my.heap::string_hash>
 105c2b7:	4c 89 f7             	mov    %r14,%rdi
 105c2ba:	4c 89 e6             	mov    %r12,%rsi
 105c2bd:	4c 89 fa             	mov    %r15,%rdx
 105c2c0:	89 c1                	mov    %eax,%ecx
 105c2c2:	e8 f9 d4 00 00       	call   10697c0 <my.heap::instance_field>
 105c2c7:	3c 01                	cmp    $0x1,%al
 105c2c9:	0f 85 be 05 00 00    	jne    105c88d <my.vm::run+0x1d1d>
 105c2cf:	48 89 d8             	mov    %rbx,%rax
 105c2d2:	4c 29 e8             	sub    %r13,%rax
 105c2d5:	0f 80 75 15 00 00    	jo     105d850 <my.vm::run+0x2ce0>
 105c2db:	48 89 c6             	mov    %rax,%rsi
 105c2de:	48 ff ce             	dec    %rsi
 105c2e1:	0f 80 55 15 00 00    	jo     105d83c <my.vm::run+0x2ccc>
 105c2e7:	49 89 c8             	mov    %rcx,%r8
 105c2ea:	48 8b 45 08          	mov    0x8(%rbp),%rax
 105c2ee:	48 39 c6             	cmp    %rax,%rsi
 105c2f1:	0f 83 f0 0b 00 00    	jae    105cee7 <my.vm::run+0x2377>
 105c2f7:	48 89 f1             	mov    %rsi,%rcx
 105c2fa:	48 83 c5 20          	add    $0x20,%rbp
 105c2fe:	48 c1 e1 04          	shl    $0x4,%rcx
 105c302:	0f b6 c2             	movzbl %dl,%eax
 105c305:	48 89 44 0d 00       	mov    %rax,0x0(%rbp,%rcx,1)
 105c30a:	4c 89 44 0d 08       	mov    %r8,0x8(%rbp,%rcx,1)
 105c30f:	48 8b 44 24 58       	mov    0x58(%rsp),%rax
 105c314:	48 89 04 24          	mov    %rax,(%rsp)
 105c318:	0f b6 ca             	movzbl %dl,%ecx
 105c31b:	48 8d 9c 24 d0 00 00 	lea    0xd0(%rsp),%rbx
 105c322:	00 
 105c323:	48 89 df             	mov    %rbx,%rdi
 105c326:	4c 89 f6             	mov    %r14,%rsi
 105c329:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105c32e:	4d 89 e9             	mov    %r13,%r9
 105c331:	e8 0a 6a 00 00       	call   1062d40 <my.vm::call_value>
 105c336:	f6 03 01             	testb  $0x1,(%rbx)
 105c339:	0f 85 4a 01 00 00    	jne    105c489 <my.vm::run+0x1919>
 105c33f:	e9 45 0c 00 00       	jmp    105cf89 <my.vm::run+0x2419>
 105c344:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105c34b:	49 89 f5             	mov    %rsi,%r13
 105c34e:	49 ff cd             	dec    %r13
 105c351:	0f 80 eb 11 00 00    	jo     105d542 <my.vm::run+0x29d2>
 105c357:	49 8b 46 78          	mov    0x78(%r14),%rax
 105c35b:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c35f:	4c 89 e9             	mov    %r13,%rcx
 105c362:	49 39 d5             	cmp    %rdx,%r13
 105c365:	0f 83 70 07 00 00    	jae    105cadb <my.vm::run+0x1f6b>
 105c36b:	48 c1 e1 04          	shl    $0x4,%rcx
 105c36f:	80 7c 08 20 02       	cmpb   $0x2,0x20(%rax,%rcx,1)
 105c374:	0f 85 67 01 00 00    	jne    105c4e1 <my.vm::run+0x1971>
 105c37a:	48 01 c8             	add    %rcx,%rax
 105c37d:	48 83 c0 20          	add    $0x20,%rax
 105c381:	48 c7 00 02 00 00 00 	movq   $0x2,(%rax)
 105c388:	80 70 0f 80          	xorb   $0x80,0xf(%rax)
 105c38c:	e9 51 04 00 00       	jmp    105c7e2 <my.vm::run+0x1c72>
 105c391:	49 8b 0e             	mov    (%r14),%rcx
 105c394:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105c398:	48 8b 74 24 68       	mov    0x68(%rsp),%rsi
 105c39d:	48 39 d6             	cmp    %rdx,%rsi
 105c3a0:	4c 89 7c 24 18       	mov    %r15,0x18(%rsp)
 105c3a5:	0f 83 e5 08 00 00    	jae    105cc90 <my.vm::run+0x2120>
 105c3ab:	48 89 f0             	mov    %rsi,%rax
 105c3ae:	4c 8b 4c 24 60       	mov    0x60(%rsp),%r9
 105c3b3:	4c 6b c0 38          	imul   $0x38,%rax,%r8
 105c3b7:	42 0f b6 54 01 20    	movzbl 0x20(%rcx,%r8,1),%edx
 105c3bd:	4a 8b 7c 01 28       	mov    0x28(%rcx,%r8,1),%rdi
 105c3c2:	4a 8b 74 01 30       	mov    0x30(%rcx,%r8,1),%rsi
 105c3c7:	4a 8b 44 01 38       	mov    0x38(%rcx,%r8,1),%rax
 105c3cc:	4e 8b 7c 01 40       	mov    0x40(%rcx,%r8,1),%r15
 105c3d1:	4e 8b 64 01 48       	mov    0x48(%rcx,%r8,1),%r12
 105c3d6:	4a c7 44 01 20 04 00 	movq   $0x4,0x20(%rcx,%r8,1)
 105c3dd:	00 00 
 105c3df:	4e 89 4c 01 28       	mov    %r9,0x28(%rcx,%r8,1)
 105c3e4:	4c 8b 4c 24 50       	mov    0x50(%rsp),%r9
 105c3e9:	4e 89 4c 01 30       	mov    %r9,0x30(%rcx,%r8,1)
 105c3ee:	83 fa 09             	cmp    $0x9,%edx
 105c3f1:	0f 87 66 01 00 00    	ja     105c55d <my.vm::run+0x19ed>
 105c3f7:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105c3fc:	0f a3 d1             	bt     %edx,%ecx
 105c3ff:	0f 83 76 02 00 00    	jae    105c67b <my.vm::run+0x1b0b>
 105c405:	48 89 f7             	mov    %rsi,%rdi
 105c408:	e8 73 75 fc ff       	call   1023980 <myl_core_drop_owned>
 105c40d:	e9 4b 01 00 00       	jmp    105c55d <my.vm::run+0x19ed>
 105c412:	48 8d 0d 27 5d fb ff 	lea    -0x4a2d9(%rip),%rcx        # 1012140 <core_number_pairs+0xaee0>
 105c419:	48 8d 9c 24 30 03 00 	lea    0x330(%rsp),%rbx
 105c420:	00 
 105c421:	48 89 df             	mov    %rbx,%rdi
 105c424:	4c 89 f6             	mov    %r14,%rsi
 105c427:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105c42c:	e8 8f 5b 00 00       	call   1061fc0 <my.vm::runtime_error>
 105c431:	f6 03 01             	testb  $0x1,(%rbx)
 105c434:	4c 8b 7c 24 18       	mov    0x18(%rsp),%r15
 105c439:	0f 84 4a 0b 00 00    	je     105cf89 <my.vm::run+0x2419>
 105c43f:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105c446:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105c44d:	4c 89 e5             	mov    %r12,%rbp
 105c450:	e9 9e 03 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105c455:	48 8d 0d e4 5e fb ff 	lea    -0x4a11c(%rip),%rcx        # 1012340 <core_number_pairs+0xb0e0>
 105c45c:	e9 78 e8 ff ff       	jmp    105acd9 <my.vm::run+0x169>
 105c461:	48 8d 0d 98 5e fb ff 	lea    -0x4a168(%rip),%rcx        # 1012300 <core_number_pairs+0xb0a0>
 105c468:	48 8d 9c 24 d0 00 00 	lea    0xd0(%rsp),%rbx
 105c46f:	00 
 105c470:	48 89 df             	mov    %rbx,%rdi
 105c473:	4c 89 f6             	mov    %r14,%rsi
 105c476:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105c47b:	e8 40 5b 00 00       	call   1061fc0 <my.vm::runtime_error>
 105c480:	f6 03 01             	testb  $0x1,(%rbx)
 105c483:	0f 84 00 0b 00 00    	je     105cf89 <my.vm::run+0x2419>
 105c489:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105c490:	48 89 de             	mov    %rbx,%rsi
 105c493:	48 ff ce             	dec    %rsi
 105c496:	0f 80 0b 12 00 00    	jo     105d6a7 <my.vm::run+0x2b37>
 105c49c:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105c4a3:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105c4aa:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c4ae:	48 39 d6             	cmp    %rdx,%rsi
 105c4b1:	0f 83 11 08 00 00    	jae    105ccc8 <my.vm::run+0x2158>
 105c4b7:	48 89 f1             	mov    %rsi,%rcx
 105c4ba:	48 c1 e1 05          	shl    $0x5,%rcx
 105c4be:	48 8b 54 08 20       	mov    0x20(%rax,%rcx,1),%rdx
 105c4c3:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 105c4c8:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105c4cd:	48 8b 6c 08 30       	mov    0x30(%rax,%rcx,1),%rbp
 105c4d2:	48 8b 44 08 38       	mov    0x38(%rax,%rcx,1),%rax
 105c4d7:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105c4dc:	e9 12 03 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105c4e1:	48 8d 0d 78 5d fb ff 	lea    -0x4a288(%rip),%rcx        # 1012260 <core_number_pairs+0xb000>
 105c4e8:	e9 ec e7 ff ff       	jmp    105acd9 <my.vm::run+0x169>
 105c4ed:	4c 89 f7             	mov    %r14,%rdi
 105c4f0:	48 89 de             	mov    %rbx,%rsi
 105c4f3:	e8 f8 ca 00 00       	call   1068ff0 <my.heap::string_chars>
 105c4f8:	48 89 c3             	mov    %rax,%rbx
 105c4fb:	48 8d 3d be 5b fb ff 	lea    -0x4a442(%rip),%rdi        # 10120c0 <core_number_pairs+0xae60>
 105c502:	48 89 c6             	mov    %rax,%rsi
 105c505:	e8 76 28 fd ff       	call   102ed80 <myl_core_bytes_concat>
 105c50a:	49 89 c7             	mov    %rax,%r15
 105c50d:	48 89 df             	mov    %rbx,%rdi
 105c510:	e8 6b 74 fc ff       	call   1023980 <myl_core_drop_owned>
 105c515:	48 8d 35 e4 5b fb ff 	lea    -0x4a41c(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 105c51c:	4c 89 ff             	mov    %r15,%rdi
 105c51f:	e8 5c 28 fd ff       	call   102ed80 <myl_core_bytes_concat>
 105c524:	48 89 c3             	mov    %rax,%rbx
 105c527:	4c 89 ff             	mov    %r15,%rdi
 105c52a:	e8 51 74 fc ff       	call   1023980 <myl_core_drop_owned>
 105c52f:	48 8d bc 24 d0 00 00 	lea    0xd0(%rsp),%rdi
 105c536:	00 
 105c537:	4c 89 f6             	mov    %r14,%rsi
 105c53a:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105c53f:	48 89 d9             	mov    %rbx,%rcx
 105c542:	e8 79 5a 00 00       	call   1061fc0 <my.vm::runtime_error>
 105c547:	48 89 df             	mov    %rbx,%rdi
 105c54a:	e8 31 74 fc ff       	call   1023980 <myl_core_drop_owned>
 105c54f:	f6 84 24 d0 00 00 00 	testb  $0x1,0xd0(%rsp)
 105c556:	01 
 105c557:	0f 84 2c 0a 00 00    	je     105cf89 <my.vm::run+0x2419>
 105c55d:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105c564:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105c56b:	4c 8b 7c 24 18       	mov    0x18(%rsp),%r15
 105c570:	e9 7e 02 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105c575:	84 d2                	test   %dl,%dl
 105c577:	0f 85 0b 12 00 00    	jne    105d788 <my.vm::run+0x2c18>
 105c57d:	4c 8b 84 24 c8 00 00 	mov    0xc8(%rsp),%r8
 105c584:	00 
 105c585:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105c589:	48 39 d6             	cmp    %rdx,%rsi
 105c58c:	0f 83 44 08 00 00    	jae    105cdd6 <my.vm::run+0x2266>
 105c592:	48 89 f0             	mov    %rsi,%rax
 105c595:	48 c1 e0 04          	shl    $0x4,%rax
 105c599:	c5 f9 10 44 07 20    	vmovupd 0x20(%rdi,%rax,1),%xmm0
 105c59f:	49 8b 36             	mov    (%r14),%rsi
 105c5a2:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105c5a6:	4d 89 fc             	mov    %r15,%r12
 105c5a9:	48 39 d3             	cmp    %rdx,%rbx
 105c5ac:	0f 83 3f 08 00 00    	jae    105cdf1 <my.vm::run+0x2281>
 105c5b2:	48 89 d8             	mov    %rbx,%rax
 105c5b5:	4c 6b c8 38          	imul   $0x38,%rax,%r9
 105c5b9:	42 0f b6 54 0e 20    	movzbl 0x20(%rsi,%r9,1),%edx
 105c5bf:	4a 8b 44 0e 28       	mov    0x28(%rsi,%r9,1),%rax
 105c5c4:	4a 8b 7c 0e 30       	mov    0x30(%rsi,%r9,1),%rdi
 105c5c9:	4a 8b 4c 0e 38       	mov    0x38(%rsi,%r9,1),%rcx
 105c5ce:	4e 8b 7c 0e 40       	mov    0x40(%rsi,%r9,1),%r15
 105c5d3:	4a 8b 5c 0e 48       	mov    0x48(%rsi,%r9,1),%rbx
 105c5d8:	4a c7 44 0e 20 05 00 	movq   $0x5,0x20(%rsi,%r9,1)
 105c5df:	00 00 
 105c5e1:	4a c7 44 0e 28 ff ff 	movq   $0xffffffffffffffff,0x28(%rsi,%r9,1)
 105c5e8:	ff ff 
 105c5ea:	c5 f9 54 05 ee 7d fa 	vandpd -0x58212(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105c5f1:	ff 
 105c5f2:	c4 a1 79 11 44 0e 30 	vmovupd %xmm0,0x30(%rsi,%r9,1)
 105c5f9:	4e 89 44 0e 40       	mov    %r8,0x40(%rsi,%r9,1)
 105c5fe:	ff ca                	dec    %edx
 105c600:	83 fa 08             	cmp    $0x8,%edx
 105c603:	77 15                	ja     105c61a <my.vm::run+0x1aaa>
 105c605:	48 8d 35 94 ae fa ff 	lea    -0x5516c(%rip),%rsi        # 10074a0 <core_number_pairs+0x240>
 105c60c:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105c610:	48 01 f2             	add    %rsi,%rdx
 105c613:	ff e2                	jmp    *%rdx
 105c615:	e8 66 73 fc ff       	call   1023980 <myl_core_drop_owned>
 105c61a:	4d 8b ae 80 00 00 00 	mov    0x80(%r14),%r13
 105c621:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105c628:	4d 89 e7             	mov    %r12,%r15
 105c62b:	e9 c3 01 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105c630:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 105c637:	00 
 105c638:	0f b6 7c 24 78       	movzbl 0x78(%rsp),%edi
 105c63d:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105c641:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105c648:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105c64c:	49 89 f0             	mov    %rsi,%r8
 105c64f:	48 39 d6             	cmp    %rdx,%rsi
 105c652:	0f 83 63 07 00 00    	jae    105cdbb <my.vm::run+0x224b>
 105c658:	49 c1 e0 04          	shl    $0x4,%r8
 105c65c:	40 0f b6 d7          	movzbl %dil,%edx
 105c660:	4a 89 54 01 20       	mov    %rdx,0x20(%rcx,%r8,1)
 105c665:	4a 89 44 01 28       	mov    %rax,0x28(%rcx,%r8,1)
 105c66a:	49 89 f5             	mov    %rsi,%r13
 105c66d:	49 ff c5             	inc    %r13
 105c670:	0f 81 6f 01 00 00    	jno    105c7e5 <my.vm::run+0x1c75>
 105c676:	e9 21 11 00 00       	jmp    105d79c <my.vm::run+0x2c2c>
 105c67b:	83 fa 01             	cmp    $0x1,%edx
 105c67e:	0f 84 84 fd ff ff    	je     105c408 <my.vm::run+0x1898>
 105c684:	83 fa 02             	cmp    $0x2,%edx
 105c687:	0f 85 d0 fe ff ff    	jne    105c55d <my.vm::run+0x19ed>
 105c68d:	48 89 c7             	mov    %rax,%rdi
 105c690:	e8 eb 72 fc ff       	call   1023980 <myl_core_drop_owned>
 105c695:	4c 89 ff             	mov    %r15,%rdi
 105c698:	e8 e3 72 fc ff       	call   1023980 <myl_core_drop_owned>
 105c69d:	4c 89 e7             	mov    %r12,%rdi
 105c6a0:	e9 63 fd ff ff       	jmp    105c408 <my.vm::run+0x1898>
 105c6a5:	49 89 f5             	mov    %rsi,%r13
 105c6a8:	49 ff cd             	dec    %r13
 105c6ab:	0f 80 1c 11 00 00    	jo     105d7cd <my.vm::run+0x2c5d>
 105c6b1:	4c 89 e9             	mov    %r13,%rcx
 105c6b4:	49 39 d5             	cmp    %rdx,%r13
 105c6b7:	0f 83 6a 07 00 00    	jae    105ce27 <my.vm::run+0x22b7>
 105c6bd:	48 c1 e1 04          	shl    $0x4,%rcx
 105c6c1:	80 3c 0f 02          	cmpb   $0x2,(%rdi,%rcx,1)
 105c6c5:	75 1e                	jne    105c6e5 <my.vm::run+0x1b75>
 105c6c7:	48 01 cf             	add    %rcx,%rdi
 105c6ca:	c4 e1 f9 6e c0       	vmovq  %rax,%xmm0
 105c6cf:	c5 fb 58 47 08       	vaddsd 0x8(%rdi),%xmm0,%xmm0
 105c6d4:	48 c7 07 02 00 00 00 	movq   $0x2,(%rdi)
 105c6db:	c5 fb 11 47 08       	vmovsd %xmm0,0x8(%rdi)
 105c6e0:	e9 fd 00 00 00       	jmp    105c7e2 <my.vm::run+0x1c72>
 105c6e5:	48 8d 0d 14 5b fb ff 	lea    -0x4a4ec(%rip),%rcx        # 1012200 <core_number_pairs+0xafa0>
 105c6ec:	e9 e8 e5 ff ff       	jmp    105acd9 <my.vm::run+0x169>
 105c6f1:	b2 01                	mov    $0x1,%dl
 105c6f3:	eb 02                	jmp    105c6f7 <my.vm::run+0x1b87>
 105c6f5:	31 d2                	xor    %edx,%edx
 105c6f7:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105c6fb:	49 89 f0             	mov    %rsi,%r8
 105c6fe:	49 c1 e0 04          	shl    $0x4,%r8
 105c702:	49 01 f8             	add    %rdi,%r8
 105c705:	48 c1 e1 04          	shl    $0x4,%rcx
 105c709:	4a c7 04 01 01 00 00 	movq   $0x1,(%rcx,%r8,1)
 105c710:	00 
 105c711:	42 88 54 01 08       	mov    %dl,0x8(%rcx,%r8,1)
 105c716:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c71a:	48 ff c6             	inc    %rsi
 105c71d:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105c724:	49 89 f5             	mov    %rsi,%r13
 105c727:	e9 c7 00 00 00       	jmp    105c7f3 <my.vm::run+0x1c83>
 105c72c:	41 80 f8 01          	cmp    $0x1,%r8b
 105c730:	75 27                	jne    105c759 <my.vm::run+0x1be9>
 105c732:	31 fe                	xor    %edi,%esi
 105c734:	40 80 f6 01          	xor    $0x1,%sil
 105c738:	eb 42                	jmp    105c77c <my.vm::run+0x1c0c>
 105c73a:	41 80 f8 02          	cmp    $0x2,%r8b
 105c73e:	75 19                	jne    105c759 <my.vm::run+0x1be9>
 105c740:	c4 e1 f9 6e c6       	vmovq  %rsi,%xmm0
 105c745:	c4 e1 f9 6e cf       	vmovq  %rdi,%xmm1
 105c74a:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 105c74f:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 105c754:	83 e6 01             	and    $0x1,%esi
 105c757:	eb 23                	jmp    105c77c <my.vm::run+0x1c0c>
 105c759:	31 f6                	xor    %esi,%esi
 105c75b:	eb 1f                	jmp    105c77c <my.vm::run+0x1c0c>
 105c75d:	48 8d 9c 24 40 02 00 	lea    0x240(%rsp),%rbx
 105c764:	00 
 105c765:	e9 c9 00 00 00       	jmp    105c833 <my.vm::run+0x1cc3>
 105c76a:	41 80 f8 03          	cmp    $0x3,%r8b
 105c76e:	41 0f 94 c0          	sete   %r8b
 105c772:	48 39 fe             	cmp    %rdi,%rsi
 105c775:	40 0f 94 c6          	sete   %sil
 105c779:	44 20 c6             	and    %r8b,%sil
 105c77c:	48 01 ca             	add    %rcx,%rdx
 105c77f:	48 c7 02 01 00 00 00 	movq   $0x1,(%rdx)
 105c786:	40 80 e6 01          	and    $0x1,%sil
 105c78a:	40 88 72 08          	mov    %sil,0x8(%rdx)
 105c78e:	49 89 46 78          	mov    %rax,0x78(%r14)
 105c792:	49 ff c5             	inc    %r13
 105c795:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105c79c:	eb 55                	jmp    105c7f3 <my.vm::run+0x1c83>
 105c79e:	48 8d 9c 24 30 03 00 	lea    0x330(%rsp),%rbx
 105c7a5:	00 
 105c7a6:	e9 88 00 00 00       	jmp    105c833 <my.vm::run+0x1cc3>
 105c7ab:	48 8d 9c 24 20 04 00 	lea    0x420(%rsp),%rbx
 105c7b2:	00 
 105c7b3:	eb 7e                	jmp    105c833 <my.vm::run+0x1cc3>
 105c7b5:	c5 f3 5c c0          	vsubsd %xmm0,%xmm1,%xmm0
 105c7b9:	eb 1b                	jmp    105c7d6 <my.vm::run+0x1c66>
 105c7bb:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
 105c7bf:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 105c7c6:	0f 97 41 08          	seta   0x8(%rcx)
 105c7ca:	eb 16                	jmp    105c7e2 <my.vm::run+0x1c72>
 105c7cc:	c5 fb 59 c1          	vmulsd %xmm1,%xmm0,%xmm0
 105c7d0:	eb 04                	jmp    105c7d6 <my.vm::run+0x1c66>
 105c7d2:	c5 f3 5e c0          	vdivsd %xmm0,%xmm1,%xmm0
 105c7d6:	48 c7 01 02 00 00 00 	movq   $0x2,(%rcx)
 105c7dd:	c5 fb 11 41 08       	vmovsd %xmm0,0x8(%rcx)
 105c7e2:	49 ff c5             	inc    %r13
 105c7e5:	4d 89 ae 80 00 00 00 	mov    %r13,0x80(%r14)
 105c7ec:	49 8b 9e 90 00 00 00 	mov    0x90(%r14),%rbx
 105c7f3:	48 89 de             	mov    %rbx,%rsi
 105c7f6:	48 ff ce             	dec    %rsi
 105c7f9:	0f 80 f6 07 00 00    	jo     105cff5 <my.vm::run+0x2485>
 105c7ff:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105c806:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105c80a:	48 39 d6             	cmp    %rdx,%rsi
 105c80d:	0f 83 d4 00 00 00    	jae    105c8e7 <my.vm::run+0x1d77>
 105c813:	48 89 f1             	mov    %rsi,%rcx
 105c816:	48 c1 e1 05          	shl    $0x5,%rcx
 105c81a:	48 89 6c 08 30       	mov    %rbp,0x30(%rax,%rcx,1)
 105c81f:	49 89 86 88 00 00 00 	mov    %rax,0x88(%r14)
 105c826:	e9 c5 e3 ff ff       	jmp    105abf0 <my.vm::run+0x80>
 105c82b:	48 8d 9c 24 d0 00 00 	lea    0xd0(%rsp),%rbx
 105c832:	00 
 105c833:	48 8d 0d 46 59 fb ff 	lea    -0x4a6ba(%rip),%rcx        # 1012180 <core_number_pairs+0xaf20>
 105c83a:	48 89 df             	mov    %rbx,%rdi
 105c83d:	4c 89 f6             	mov    %r14,%rsi
 105c840:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105c845:	e8 76 57 00 00       	call   1061fc0 <my.vm::runtime_error>
 105c84a:	f6 03 01             	testb  $0x1,(%rbx)
 105c84d:	0f 84 36 07 00 00    	je     105cf89 <my.vm::run+0x2419>
 105c853:	4d 89 e7             	mov    %r12,%r15
 105c856:	e9 a1 e4 ff ff       	jmp    105acfc <my.vm::run+0x18c>
 105c85b:	4c 89 f7             	mov    %r14,%rdi
 105c85e:	48 8b 74 24 30       	mov    0x30(%rsp),%rsi
 105c863:	e8 48 d0 00 00       	call   10698b0 <my.heap::instance_class>
 105c868:	48 8d 9c 24 d0 00 00 	lea    0xd0(%rsp),%rbx
 105c86f:	00 
 105c870:	48 89 df             	mov    %rbx,%rdi
 105c873:	4c 89 f6             	mov    %r14,%rsi
 105c876:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105c87b:	48 89 c1             	mov    %rax,%rcx
 105c87e:	4c 8b 44 24 48       	mov    0x48(%rsp),%r8
 105c883:	e8 58 5d 00 00       	call   10625e0 <my.vm::bind_method>
 105c888:	e9 a4 fb ff ff       	jmp    105c431 <my.vm::run+0x18c1>
 105c88d:	4c 89 f7             	mov    %r14,%rdi
 105c890:	4c 89 e6             	mov    %r12,%rsi
 105c893:	e8 18 d0 00 00       	call   10698b0 <my.heap::instance_class>
 105c898:	48 8d 9c 24 d0 00 00 	lea    0xd0(%rsp),%rbx
 105c89f:	00 
 105c8a0:	48 89 df             	mov    %rbx,%rdi
 105c8a3:	4c 89 f6             	mov    %r14,%rsi
 105c8a6:	48 8b 54 24 08       	mov    0x8(%rsp),%rdx
 105c8ab:	48 89 c1             	mov    %rax,%rcx
 105c8ae:	4d 89 f8             	mov    %r15,%r8
 105c8b1:	4d 89 e9             	mov    %r13,%r9
 105c8b4:	e8 37 6a 00 00       	call   10632f0 <my.vm::invoke_from_class>
 105c8b9:	f6 03 01             	testb  $0x1,(%rbx)
 105c8bc:	0f 85 c7 fb ff ff    	jne    105c489 <my.vm::run+0x1919>
 105c8c2:	e9 c2 06 00 00       	jmp    105cf89 <my.vm::run+0x2419>
 105c8c7:	48 89 cf             	mov    %rcx,%rdi
 105c8ca:	e8 b1 70 fc ff       	call   1023980 <myl_core_drop_owned>
 105c8cf:	4c 89 ff             	mov    %r15,%rdi
 105c8d2:	e8 a9 70 fc ff       	call   1023980 <myl_core_drop_owned>
 105c8d7:	48 89 df             	mov    %rbx,%rdi
 105c8da:	e9 36 fd ff ff       	jmp    105c615 <my.vm::run+0x1aa5>
 105c8df:	48 89 c7             	mov    %rax,%rdi
 105c8e2:	e9 2e fd ff ff       	jmp    105c615 <my.vm::run+0x1aa5>
 105c8e7:	48 89 f1             	mov    %rsi,%rcx
 105c8ea:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105c8ee:	48 21 d1             	and    %rdx,%rcx
 105c8f1:	48 01 f1             	add    %rsi,%rcx
 105c8f4:	48 39 d1             	cmp    %rdx,%rcx
 105c8f7:	0f 82 19 ff ff ff    	jb     105c816 <my.vm::run+0x1ca6>
 105c8fd:	e9 f6 0f 00 00       	jmp    105d8f8 <my.vm::run+0x2d88>
 105c902:	48 89 f7             	mov    %rsi,%rdi
 105c905:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105c909:	48 21 d7             	and    %rdx,%rdi
 105c90c:	48 01 f7             	add    %rsi,%rdi
 105c90f:	48 39 d7             	cmp    %rdx,%rdi
 105c912:	0f 82 54 e3 ff ff    	jb     105ac6c <my.vm::run+0xfc>
 105c918:	e9 e7 0f 00 00       	jmp    105d904 <my.vm::run+0x2d94>
 105c91d:	4c 89 ee             	mov    %r13,%rsi
 105c920:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105c924:	48 21 d6             	and    %rdx,%rsi
 105c927:	4c 01 ee             	add    %r13,%rsi
 105c92a:	48 39 d6             	cmp    %rdx,%rsi
 105c92d:	0f 82 62 e3 ff ff    	jb     105ac95 <my.vm::run+0x125>
 105c933:	e9 e7 0f 00 00       	jmp    105d91f <my.vm::run+0x2daf>
 105c938:	4c 89 e9             	mov    %r13,%rcx
 105c93b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105c93f:	48 21 d1             	and    %rdx,%rcx
 105c942:	4c 01 e9             	add    %r13,%rcx
 105c945:	48 39 d1             	cmp    %rdx,%rcx
 105c948:	0f 82 d3 ea ff ff    	jb     105b421 <my.vm::run+0x8b1>
 105c94e:	e9 70 11 00 00       	jmp    105dac3 <my.vm::run+0x2f53>
 105c953:	4c 89 e9             	mov    %r13,%rcx
 105c956:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105c95a:	48 21 d1             	and    %rdx,%rcx
 105c95d:	4c 01 e9             	add    %r13,%rcx
 105c960:	48 39 d1             	cmp    %rdx,%rcx
 105c963:	0f 82 83 eb ff ff    	jb     105b4ec <my.vm::run+0x97c>
 105c969:	e9 11 10 00 00       	jmp    105d97f <my.vm::run+0x2e0f>
 105c96e:	4c 89 ef             	mov    %r13,%rdi
 105c971:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105c975:	48 21 cf             	and    %rcx,%rdi
 105c978:	4c 01 ef             	add    %r13,%rdi
 105c97b:	48 39 cf             	cmp    %rcx,%rdi
 105c97e:	0f 82 42 ec ff ff    	jb     105b5c6 <my.vm::run+0xa56>
 105c984:	e9 7a 10 00 00       	jmp    105da03 <my.vm::run+0x2e93>
 105c989:	4c 89 e9             	mov    %r13,%rcx
 105c98c:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105c990:	48 21 d1             	and    %rdx,%rcx
 105c993:	4c 01 e9             	add    %r13,%rcx
 105c996:	48 39 d1             	cmp    %rdx,%rcx
 105c999:	0f 82 61 ec ff ff    	jb     105b600 <my.vm::run+0xa90>
 105c99f:	e9 52 11 00 00       	jmp    105daf6 <my.vm::run+0x2f86>
 105c9a4:	49 89 f0             	mov    %rsi,%r8
 105c9a7:	49 c1 f8 3f          	sar    $0x3f,%r8
 105c9ab:	49 21 c8             	and    %rcx,%r8
 105c9ae:	49 01 f0             	add    %rsi,%r8
 105c9b1:	49 39 c8             	cmp    %rcx,%r8
 105c9b4:	0f 82 1e e5 ff ff    	jb     105aed8 <my.vm::run+0x368>
 105c9ba:	e9 46 11 00 00       	jmp    105db05 <my.vm::run+0x2f95>
 105c9bf:	48 89 f1             	mov    %rsi,%rcx
 105c9c2:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105c9c6:	48 21 d1             	and    %rdx,%rcx
 105c9c9:	48 01 f1             	add    %rsi,%rcx
 105c9cc:	48 39 d1             	cmp    %rdx,%rcx
 105c9cf:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 105c9d4:	0f 82 88 e6 ff ff    	jb     105b062 <my.vm::run+0x4f2>
 105c9da:	e9 d8 10 00 00       	jmp    105dab7 <my.vm::run+0x2f47>
 105c9df:	48 89 f0             	mov    %rsi,%rax
 105c9e2:	48 c1 f8 3f          	sar    $0x3f,%rax
 105c9e6:	48 21 d0             	and    %rdx,%rax
 105c9e9:	48 01 f0             	add    %rsi,%rax
 105c9ec:	48 39 d0             	cmp    %rdx,%rax
 105c9ef:	0f 82 f0 e7 ff ff    	jb     105b1e5 <my.vm::run+0x675>
 105c9f5:	e9 3f 10 00 00       	jmp    105da39 <my.vm::run+0x2ec9>
 105c9fa:	4c 89 ed             	mov    %r13,%rbp
 105c9fd:	48 c1 fd 3f          	sar    $0x3f,%rbp
 105ca01:	48 21 d5             	and    %rdx,%rbp
 105ca04:	4c 01 ed             	add    %r13,%rbp
 105ca07:	48 39 d5             	cmp    %rdx,%rbp
 105ca0a:	0f 82 0c e8 ff ff    	jb     105b21c <my.vm::run+0x6ac>
 105ca10:	e9 6f 10 00 00       	jmp    105da84 <my.vm::run+0x2f14>
 105ca15:	48 89 f1             	mov    %rsi,%rcx
 105ca18:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ca1c:	48 21 d1             	and    %rdx,%rcx
 105ca1f:	48 01 f1             	add    %rsi,%rcx
 105ca22:	48 39 d1             	cmp    %rdx,%rcx
 105ca25:	0f 82 44 ea ff ff    	jb     105b46f <my.vm::run+0x8ff>
 105ca2b:	e9 15 10 00 00       	jmp    105da45 <my.vm::run+0x2ed5>
 105ca30:	4c 89 e6             	mov    %r12,%rsi
 105ca33:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105ca37:	48 21 d6             	and    %rdx,%rsi
 105ca3a:	4c 01 e6             	add    %r12,%rsi
 105ca3d:	48 39 d6             	cmp    %rdx,%rsi
 105ca40:	0f 82 22 ec ff ff    	jb     105b668 <my.vm::run+0xaf8>
 105ca46:	e9 e3 0e 00 00       	jmp    105d92e <my.vm::run+0x2dbe>
 105ca4b:	48 89 f1             	mov    %rsi,%rcx
 105ca4e:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ca52:	48 21 d1             	and    %rdx,%rcx
 105ca55:	48 01 f1             	add    %rsi,%rcx
 105ca58:	48 39 d1             	cmp    %rdx,%rcx
 105ca5b:	0f 82 5c ec ff ff    	jb     105b6bd <my.vm::run+0xb4d>
 105ca61:	e9 c9 10 00 00       	jmp    105db2f <my.vm::run+0x2fbf>
 105ca66:	48 89 f7             	mov    %rsi,%rdi
 105ca69:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105ca6d:	48 21 d7             	and    %rdx,%rdi
 105ca70:	48 01 f7             	add    %rsi,%rdi
 105ca73:	48 39 d7             	cmp    %rdx,%rdi
 105ca76:	0f 82 eb ed ff ff    	jb     105b867 <my.vm::run+0xcf7>
 105ca7c:	e9 d7 0e 00 00       	jmp    105d958 <my.vm::run+0x2de8>
 105ca81:	48 89 f1             	mov    %rsi,%rcx
 105ca84:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ca88:	48 21 d1             	and    %rdx,%rcx
 105ca8b:	48 01 f1             	add    %rsi,%rcx
 105ca8e:	48 39 d1             	cmp    %rdx,%rcx
 105ca91:	0f 82 cc ee ff ff    	jb     105b963 <my.vm::run+0xdf3>
 105ca97:	e9 79 0f 00 00       	jmp    105da15 <my.vm::run+0x2ea5>
 105ca9c:	4c 89 e9             	mov    %r13,%rcx
 105ca9f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105caa3:	48 21 d1             	and    %rdx,%rcx
 105caa6:	4c 01 e9             	add    %r13,%rcx
 105caa9:	48 39 d1             	cmp    %rdx,%rcx
 105caac:	0f 82 21 ec ff ff    	jb     105b6d3 <my.vm::run+0xb63>
 105cab2:	e9 9a 0f 00 00       	jmp    105da51 <my.vm::run+0x2ee1>
 105cab7:	49 8d 0c 31          	lea    (%r9,%rsi,1),%rcx
 105cabb:	48 39 d1             	cmp    %rdx,%rcx
 105cabe:	0f 82 50 f3 ff ff    	jb     105be14 <my.vm::run+0x12a4>
 105cac4:	e9 97 0f 00 00       	jmp    105da60 <my.vm::run+0x2ef0>
 105cac9:	48 8d 3c 0e          	lea    (%rsi,%rcx,1),%rdi
 105cacd:	48 39 d7             	cmp    %rdx,%rdi
 105cad0:	0f 82 14 f6 ff ff    	jb     105c0ea <my.vm::run+0x157a>
 105cad6:	e9 39 10 00 00       	jmp    105db14 <my.vm::run+0x2fa4>
 105cadb:	4c 89 e9             	mov    %r13,%rcx
 105cade:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cae2:	48 21 d1             	and    %rdx,%rcx
 105cae5:	4c 01 e9             	add    %r13,%rcx
 105cae8:	48 39 d1             	cmp    %rdx,%rcx
 105caeb:	0f 82 7a f8 ff ff    	jb     105c36b <my.vm::run+0x17fb>
 105caf1:	e9 e3 0e 00 00       	jmp    105d9d9 <my.vm::run+0x2e69>
 105caf6:	48 89 f0             	mov    %rsi,%rax
 105caf9:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cafd:	48 21 d0             	and    %rdx,%rax
 105cb00:	48 01 f0             	add    %rsi,%rax
 105cb03:	48 39 d0             	cmp    %rdx,%rax
 105cb06:	0f 82 2f e2 ff ff    	jb     105ad3b <my.vm::run+0x1cb>
 105cb0c:	e9 c1 0f 00 00       	jmp    105dad2 <my.vm::run+0x2f62>
 105cb11:	4c 89 e9             	mov    %r13,%rcx
 105cb14:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cb18:	48 21 d1             	and    %rdx,%rcx
 105cb1b:	4c 01 e9             	add    %r13,%rcx
 105cb1e:	48 39 d1             	cmp    %rdx,%rcx
 105cb21:	0f 82 76 e9 ff ff    	jb     105b49d <my.vm::run+0x92d>
 105cb27:	e9 62 0e 00 00       	jmp    105d98e <my.vm::run+0x2e1e>
 105cb2c:	4c 89 e8             	mov    %r13,%rax
 105cb2f:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cb33:	48 21 d0             	and    %rdx,%rax
 105cb36:	4c 01 e8             	add    %r13,%rax
 105cb39:	48 39 d0             	cmp    %rdx,%rax
 105cb3c:	0f 82 fb eb ff ff    	jb     105b73d <my.vm::run+0xbcd>
 105cb42:	e9 d9 0f 00 00       	jmp    105db20 <my.vm::run+0x2fb0>
 105cb47:	48 89 f0             	mov    %rsi,%rax
 105cb4a:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cb4e:	48 21 d0             	and    %rdx,%rax
 105cb51:	48 01 f0             	add    %rsi,%rax
 105cb54:	48 39 d0             	cmp    %rdx,%rax
 105cb57:	0f 82 2e ed ff ff    	jb     105b88b <my.vm::run+0xd1b>
 105cb5d:	e9 86 0e 00 00       	jmp    105d9e8 <my.vm::run+0x2e78>
 105cb62:	48 89 f7             	mov    %rsi,%rdi
 105cb65:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105cb69:	48 21 d7             	and    %rdx,%rdi
 105cb6c:	48 01 f7             	add    %rsi,%rdi
 105cb6f:	48 39 d7             	cmp    %rdx,%rdi
 105cb72:	0f 82 fc f5 ff ff    	jb     105c174 <my.vm::run+0x1604>
 105cb78:	e9 a4 0e 00 00       	jmp    105da21 <my.vm::run+0x2eb1>
 105cb7d:	48 89 f7             	mov    %rsi,%rdi
 105cb80:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105cb84:	48 21 d7             	and    %rdx,%rdi
 105cb87:	48 01 f7             	add    %rsi,%rdi
 105cb8a:	48 39 d7             	cmp    %rdx,%rdi
 105cb8d:	0f 82 ed e3 ff ff    	jb     105af80 <my.vm::run+0x410>
 105cb93:	e9 a3 0f 00 00       	jmp    105db3b <my.vm::run+0x2fcb>
 105cb98:	48 89 d6             	mov    %rdx,%rsi
 105cb9b:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105cb9f:	48 21 c6             	and    %rax,%rsi
 105cba2:	48 01 d6             	add    %rdx,%rsi
 105cba5:	48 39 c6             	cmp    %rax,%rsi
 105cba8:	0f 82 7a ee ff ff    	jb     105ba28 <my.vm::run+0xeb8>
 105cbae:	e9 ea 0d 00 00       	jmp    105d99d <my.vm::run+0x2e2d>
 105cbb3:	48 89 f1             	mov    %rsi,%rcx
 105cbb6:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cbba:	48 21 d1             	and    %rdx,%rcx
 105cbbd:	48 01 f1             	add    %rsi,%rcx
 105cbc0:	48 39 d1             	cmp    %rdx,%rcx
 105cbc3:	0f 82 28 e4 ff ff    	jb     105aff1 <my.vm::run+0x481>
 105cbc9:	e9 9e 0e 00 00       	jmp    105da6c <my.vm::run+0x2efc>
 105cbce:	48 89 f1             	mov    %rsi,%rcx
 105cbd1:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cbd5:	48 21 d1             	and    %rdx,%rcx
 105cbd8:	48 01 f1             	add    %rsi,%rcx
 105cbdb:	48 39 d1             	cmp    %rdx,%rcx
 105cbde:	0f 82 33 e7 ff ff    	jb     105b317 <my.vm::run+0x7a7>
 105cbe4:	e9 f5 0e 00 00       	jmp    105dade <my.vm::run+0x2f6e>
 105cbe9:	48 89 f7             	mov    %rsi,%rdi
 105cbec:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105cbf0:	48 21 d7             	and    %rdx,%rdi
 105cbf3:	48 01 f7             	add    %rsi,%rdi
 105cbf6:	48 39 d7             	cmp    %rdx,%rdi
 105cbf9:	0f 82 ca f3 ff ff    	jb     105bfc9 <my.vm::run+0x1459>
 105cbff:	e9 8f 0e 00 00       	jmp    105da93 <my.vm::run+0x2f23>
 105cc04:	48 89 f0             	mov    %rsi,%rax
 105cc07:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cc0b:	48 21 d0             	and    %rdx,%rax
 105cc0e:	48 01 f0             	add    %rsi,%rax
 105cc11:	48 39 d0             	cmp    %rdx,%rax
 105cc14:	0f 82 0d e2 ff ff    	jb     105ae27 <my.vm::run+0x2b7>
 105cc1a:	e9 59 0e 00 00       	jmp    105da78 <my.vm::run+0x2f08>
 105cc1f:	4c 89 e8             	mov    %r13,%rax
 105cc22:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cc26:	48 21 d0             	and    %rdx,%rax
 105cc29:	4c 01 e8             	add    %r13,%rax
 105cc2c:	48 39 d0             	cmp    %rdx,%rax
 105cc2f:	48 8b 6c 24 30       	mov    0x30(%rsp),%rbp
 105cc34:	0f 82 b9 fb ff ff    	jb     105c7f3 <my.vm::run+0x1c83>
 105cc3a:	e9 70 0d 00 00       	jmp    105d9af <my.vm::run+0x2e3f>
 105cc3f:	48 89 f1             	mov    %rsi,%rcx
 105cc42:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cc46:	48 21 d1             	and    %rdx,%rcx
 105cc49:	48 01 f1             	add    %rsi,%rcx
 105cc4c:	48 39 d1             	cmp    %rdx,%rcx
 105cc4f:	0f 82 1e f6 ff ff    	jb     105c273 <my.vm::run+0x1703>
 105cc55:	e9 45 0e 00 00       	jmp    105da9f <my.vm::run+0x2f2f>
 105cc5a:	4c 89 e9             	mov    %r13,%rcx
 105cc5d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cc61:	48 21 d1             	and    %rdx,%rcx
 105cc64:	4c 01 e9             	add    %r13,%rcx
 105cc67:	48 39 d1             	cmp    %rdx,%rcx
 105cc6a:	0f 82 ea e1 ff ff    	jb     105ae5a <my.vm::run+0x2ea>
 105cc70:	e9 ef 0c 00 00       	jmp    105d964 <my.vm::run+0x2df4>
 105cc75:	48 89 f1             	mov    %rsi,%rcx
 105cc78:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cc7c:	48 21 d1             	and    %rdx,%rcx
 105cc7f:	48 01 f1             	add    %rsi,%rcx
 105cc82:	48 39 d1             	cmp    %rdx,%rcx
 105cc85:	0f 82 3c ee ff ff    	jb     105bac7 <my.vm::run+0xf57>
 105cc8b:	e9 9d 0d 00 00       	jmp    105da2d <my.vm::run+0x2ebd>
 105cc90:	48 89 f0             	mov    %rsi,%rax
 105cc93:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cc97:	48 21 d0             	and    %rdx,%rax
 105cc9a:	48 01 f0             	add    %rsi,%rax
 105cc9d:	48 39 d0             	cmp    %rdx,%rax
 105cca0:	4c 8b 4c 24 60       	mov    0x60(%rsp),%r9
 105cca5:	0f 82 08 f7 ff ff    	jb     105c3b3 <my.vm::run+0x1843>
 105ccab:	e9 fb 0d 00 00       	jmp    105daab <my.vm::run+0x2f3b>
 105ccb0:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ccb4:	48 21 d1             	and    %rdx,%rcx
 105ccb7:	4c 01 e9             	add    %r13,%rcx
 105ccba:	48 39 d1             	cmp    %rdx,%rcx
 105ccbd:	0f 82 f5 e3 ff ff    	jb     105b0b8 <my.vm::run+0x548>
 105ccc3:	e9 75 0c 00 00       	jmp    105d93d <my.vm::run+0x2dcd>
 105ccc8:	48 89 f1             	mov    %rsi,%rcx
 105cccb:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cccf:	48 21 d1             	and    %rdx,%rcx
 105ccd2:	48 01 f1             	add    %rsi,%rcx
 105ccd5:	48 39 d1             	cmp    %rdx,%rcx
 105ccd8:	0f 82 dc f7 ff ff    	jb     105c4ba <my.vm::run+0x194a>
 105ccde:	e9 07 0e 00 00       	jmp    105daea <my.vm::run+0x2f7a>
 105cce3:	48 89 f1             	mov    %rsi,%rcx
 105cce6:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ccea:	48 21 d1             	and    %rdx,%rcx
 105cced:	48 01 f1             	add    %rsi,%rcx
 105ccf0:	48 39 d1             	cmp    %rdx,%rcx
 105ccf3:	0f 82 04 ec ff ff    	jb     105b8fd <my.vm::run+0xd8d>
 105ccf9:	e9 f1 0e 00 00       	jmp    105dbef <my.vm::run+0x307f>
 105ccfe:	48 89 f1             	mov    %rsi,%rcx
 105cd01:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cd05:	48 21 d1             	and    %rdx,%rcx
 105cd08:	48 01 f1             	add    %rsi,%rcx
 105cd0b:	48 39 d1             	cmp    %rdx,%rcx
 105cd0e:	0f 82 06 ec ff ff    	jb     105b91a <my.vm::run+0xdaa>
 105cd14:	e9 85 0e 00 00       	jmp    105db9e <my.vm::run+0x302e>
 105cd19:	48 89 f1             	mov    %rsi,%rcx
 105cd1c:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cd20:	48 21 d1             	and    %rdx,%rcx
 105cd23:	48 01 f1             	add    %rsi,%rcx
 105cd26:	48 39 d1             	cmp    %rdx,%rcx
 105cd29:	0f 82 5f e4 ff ff    	jb     105b18e <my.vm::run+0x61e>
 105cd2f:	e9 76 0e 00 00       	jmp    105dbaa <my.vm::run+0x303a>
 105cd34:	48 89 c1             	mov    %rax,%rcx
 105cd37:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cd3b:	48 21 d1             	and    %rdx,%rcx
 105cd3e:	48 01 c1             	add    %rax,%rcx
 105cd41:	48 39 d1             	cmp    %rdx,%rcx
 105cd44:	0f 82 5d e4 ff ff    	jb     105b1a7 <my.vm::run+0x637>
 105cd4a:	e9 40 0e 00 00       	jmp    105db8f <my.vm::run+0x301f>
 105cd4f:	48 89 f1             	mov    %rsi,%rcx
 105cd52:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cd56:	48 21 d1             	and    %rdx,%rcx
 105cd59:	48 01 f1             	add    %rsi,%rcx
 105cd5c:	48 39 d1             	cmp    %rdx,%rcx
 105cd5f:	0f 82 df e4 ff ff    	jb     105b244 <my.vm::run+0x6d4>
 105cd65:	e9 4c 0e 00 00       	jmp    105dbb6 <my.vm::run+0x3046>
 105cd6a:	48 89 c7             	mov    %rax,%rdi
 105cd6d:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105cd71:	48 21 cf             	and    %rcx,%rdi
 105cd74:	48 01 c7             	add    %rax,%rdi
 105cd77:	48 39 cf             	cmp    %rcx,%rdi
 105cd7a:	0f 82 e2 df ff ff    	jb     105ad62 <my.vm::run+0x1f2>
 105cd80:	e9 3d 0e 00 00       	jmp    105dbc2 <my.vm::run+0x3052>
 105cd85:	49 89 f0             	mov    %rsi,%r8
 105cd88:	49 c1 f8 3f          	sar    $0x3f,%r8
 105cd8c:	49 21 c0             	and    %rax,%r8
 105cd8f:	49 01 f0             	add    %rsi,%r8
 105cd92:	49 39 c0             	cmp    %rax,%r8
 105cd95:	0f 82 df e7 ff ff    	jb     105b57a <my.vm::run+0xa0a>
 105cd9b:	e9 88 0e 00 00       	jmp    105dc28 <my.vm::run+0x30b8>
 105cda0:	4c 89 e6             	mov    %r12,%rsi
 105cda3:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105cda7:	48 21 d6             	and    %rdx,%rsi
 105cdaa:	4c 01 e6             	add    %r12,%rsi
 105cdad:	48 39 d6             	cmp    %rdx,%rsi
 105cdb0:	0f 82 e4 f4 ff ff    	jb     105c29a <my.vm::run+0x172a>
 105cdb6:	e9 40 0e 00 00       	jmp    105dbfb <my.vm::run+0x308b>
 105cdbb:	49 89 f0             	mov    %rsi,%r8
 105cdbe:	49 c1 f8 3f          	sar    $0x3f,%r8
 105cdc2:	49 21 d0             	and    %rdx,%r8
 105cdc5:	49 01 f0             	add    %rsi,%r8
 105cdc8:	49 39 d0             	cmp    %rdx,%r8
 105cdcb:	0f 82 87 f8 ff ff    	jb     105c658 <my.vm::run+0x1ae8>
 105cdd1:	e9 61 0e 00 00       	jmp    105dc37 <my.vm::run+0x30c7>
 105cdd6:	48 89 f0             	mov    %rsi,%rax
 105cdd9:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cddd:	48 21 d0             	and    %rdx,%rax
 105cde0:	48 01 f0             	add    %rsi,%rax
 105cde3:	48 39 d0             	cmp    %rdx,%rax
 105cde6:	0f 82 a9 f7 ff ff    	jb     105c595 <my.vm::run+0x1a25>
 105cdec:	e9 52 0e 00 00       	jmp    105dc43 <my.vm::run+0x30d3>
 105cdf1:	48 89 d8             	mov    %rbx,%rax
 105cdf4:	48 c1 f8 3f          	sar    $0x3f,%rax
 105cdf8:	48 21 d0             	and    %rdx,%rax
 105cdfb:	48 01 d8             	add    %rbx,%rax
 105cdfe:	48 39 d0             	cmp    %rdx,%rax
 105ce01:	0f 82 ae f7 ff ff    	jb     105c5b5 <my.vm::run+0x1a45>
 105ce07:	e9 82 0e 00 00       	jmp    105dc8e <my.vm::run+0x311e>
 105ce0c:	49 89 c0             	mov    %rax,%r8
 105ce0f:	49 c1 f8 3f          	sar    $0x3f,%r8
 105ce13:	49 21 c8             	and    %rcx,%r8
 105ce16:	49 01 c0             	add    %rax,%r8
 105ce19:	49 39 c8             	cmp    %rcx,%r8
 105ce1c:	0f 82 2c f0 ff ff    	jb     105be4e <my.vm::run+0x12de>
 105ce22:	e9 28 0e 00 00       	jmp    105dc4f <my.vm::run+0x30df>
 105ce27:	4c 89 e9             	mov    %r13,%rcx
 105ce2a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ce2e:	48 21 d1             	and    %rdx,%rcx
 105ce31:	4c 01 e9             	add    %r13,%rcx
 105ce34:	48 39 d1             	cmp    %rdx,%rcx
 105ce37:	0f 82 80 f8 ff ff    	jb     105c6bd <my.vm::run+0x1b4d>
 105ce3d:	e9 c8 0d 00 00       	jmp    105dc0a <my.vm::run+0x309a>
 105ce42:	4c 89 e9             	mov    %r13,%rcx
 105ce45:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ce49:	48 21 d1             	and    %rdx,%rcx
 105ce4c:	4c 01 e9             	add    %r13,%rcx
 105ce4f:	48 39 d1             	cmp    %rdx,%rcx
 105ce52:	0f 82 25 df ff ff    	jb     105ad7d <my.vm::run+0x20d>
 105ce58:	e9 bc 0d 00 00       	jmp    105dc19 <my.vm::run+0x30a9>
 105ce5d:	48 89 f1             	mov    %rsi,%rcx
 105ce60:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ce64:	48 21 d1             	and    %rdx,%rcx
 105ce67:	48 01 f1             	add    %rsi,%rcx
 105ce6a:	48 39 d1             	cmp    %rdx,%rcx
 105ce6d:	0f 82 06 e9 ff ff    	jb     105b779 <my.vm::run+0xc09>
 105ce73:	e9 5c 0d 00 00       	jmp    105dbd4 <my.vm::run+0x3064>
 105ce78:	49 89 c0             	mov    %rax,%r8
 105ce7b:	49 c1 f8 3f          	sar    $0x3f,%r8
 105ce7f:	49 21 d0             	and    %rdx,%r8
 105ce82:	49 01 c0             	add    %rax,%r8
 105ce85:	49 39 d0             	cmp    %rdx,%r8
 105ce88:	0f 82 e8 ef ff ff    	jb     105be76 <my.vm::run+0x1306>
 105ce8e:	e9 b4 0c 00 00       	jmp    105db47 <my.vm::run+0x2fd7>
 105ce93:	48 89 d9             	mov    %rbx,%rcx
 105ce96:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ce9a:	48 21 d1             	and    %rdx,%rcx
 105ce9d:	48 01 d9             	add    %rbx,%rcx
 105cea0:	48 39 d1             	cmp    %rdx,%rcx
 105cea3:	0f 82 1d e9 ff ff    	jb     105b7c6 <my.vm::run+0xc56>
 105cea9:	e9 c2 0d 00 00       	jmp    105dc70 <my.vm::run+0x3100>
 105ceae:	48 89 d8             	mov    %rbx,%rax
 105ceb1:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ceb5:	48 21 d0             	and    %rdx,%rax
 105ceb8:	48 01 d8             	add    %rbx,%rax
 105cebb:	48 39 d0             	cmp    %rdx,%rax
 105cebe:	4d 89 e7             	mov    %r12,%r15
 105cec1:	0f 82 3a e9 ff ff    	jb     105b801 <my.vm::run+0xc91>
 105cec7:	e9 d1 0d 00 00       	jmp    105dc9d <my.vm::run+0x312d>
 105cecc:	4c 89 e8             	mov    %r13,%rax
 105cecf:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ced3:	48 21 d0             	and    %rdx,%rax
 105ced6:	4c 01 e8             	add    %r13,%rax
 105ced9:	48 39 d0             	cmp    %rdx,%rax
 105cedc:	0f 82 3e e9 ff ff    	jb     105b820 <my.vm::run+0xcb0>
 105cee2:	e9 7b 0c 00 00       	jmp    105db62 <my.vm::run+0x2ff2>
 105cee7:	48 89 f1             	mov    %rsi,%rcx
 105ceea:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ceee:	48 21 c1             	and    %rax,%rcx
 105cef1:	48 01 f1             	add    %rsi,%rcx
 105cef4:	48 39 c1             	cmp    %rax,%rcx
 105cef7:	0f 82 fd f3 ff ff    	jb     105c2fa <my.vm::run+0x178a>
 105cefd:	e9 7d 0d 00 00       	jmp    105dc7f <my.vm::run+0x310f>
 105cf02:	4d 89 c3             	mov    %r8,%r11
 105cf05:	49 c1 fb 3f          	sar    $0x3f,%r11
 105cf09:	49 21 cb             	and    %rcx,%r11
 105cf0c:	4d 01 c3             	add    %r8,%r11
 105cf0f:	49 39 cb             	cmp    %rcx,%r11
 105cf12:	0f 82 7e ef ff ff    	jb     105be96 <my.vm::run+0x1326>
 105cf18:	e9 54 0c 00 00       	jmp    105db71 <my.vm::run+0x3001>
 105cf1d:	49 01 f1             	add    %rsi,%r9
 105cf20:	49 39 d1             	cmp    %rdx,%r9
 105cf23:	0f 82 8c ef ff ff    	jb     105beb5 <my.vm::run+0x1345>
 105cf29:	e9 55 0c 00 00       	jmp    105db83 <my.vm::run+0x3013>
 105cf2e:	48 89 c6             	mov    %rax,%rsi
 105cf31:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105cf35:	48 21 d6             	and    %rdx,%rsi
 105cf38:	48 01 c6             	add    %rax,%rsi
 105cf3b:	48 39 d6             	cmp    %rdx,%rsi
 105cf3e:	0f 82 94 ef ff ff    	jb     105bed8 <my.vm::run+0x1368>
 105cf44:	e9 97 0c 00 00       	jmp    105dbe0 <my.vm::run+0x3070>
 105cf49:	48 89 f7             	mov    %rsi,%rdi
 105cf4c:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105cf50:	48 21 d7             	and    %rdx,%rdi
 105cf53:	48 01 f7             	add    %rsi,%rdi
 105cf56:	48 39 d7             	cmp    %rdx,%rdi
 105cf59:	0f 82 cd ef ff ff    	jb     105bf2c <my.vm::run+0x13bc>
 105cf5f:	e9 f2 0b 00 00       	jmp    105db56 <my.vm::run+0x2fe6>
 105cf64:	4c 89 ee             	mov    %r13,%rsi
 105cf67:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105cf6b:	48 21 d6             	and    %rdx,%rsi
 105cf6e:	4c 01 ee             	add    %r13,%rsi
 105cf71:	48 39 d6             	cmp    %rdx,%rsi
 105cf74:	0f 82 ca ef ff ff    	jb     105bf44 <my.vm::run+0x13d4>
 105cf7a:	48 8d 3d 4f 72 02 00 	lea    0x2724f(%rip),%rdi        # 10841d0 <core_durable_error.verbs+0x4bc0>
 105cf81:	4c 89 ee             	mov    %r13,%rsi
 105cf84:	e8 77 77 fc ff       	call   1024700 <myl_core_trap>
 105cf89:	b9 02 00 00 00       	mov    $0x2,%ecx
 105cf8e:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105cf93:	48 89 08             	mov    %rcx,(%rax)
 105cf96:	48 81 c4 a8 08 00 00 	add    $0x8a8,%rsp
 105cf9d:	5b                   	pop    %rbx
 105cf9e:	41 5c                	pop    %r12
 105cfa0:	41 5d                	pop    %r13
 105cfa2:	41 5e                	pop    %r14
 105cfa4:	41 5f                	pop    %r15
 105cfa6:	5d                   	pop    %rbp
 105cfa7:	c3                   	ret
 105cfa8:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105cfaf:	48 89 c6             	mov    %rax,%rsi
 105cfb2:	48 ff ce             	dec    %rsi
 105cfb5:	0f 80 29 09 00 00    	jo     105d8e4 <my.vm::run+0x2d74>
 105cfbb:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105cfc2:	49 8b 46 78          	mov    0x78(%r14),%rax
 105cfc6:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cfca:	48 39 d6             	cmp    %rdx,%rsi
 105cfcd:	73 3a                	jae    105d009 <my.vm::run+0x2499>
 105cfcf:	31 c9                	xor    %ecx,%ecx
 105cfd1:	eb bb                	jmp    105cf8e <my.vm::run+0x241e>
 105cfd3:	48 89 f1             	mov    %rsi,%rcx
 105cfd6:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105cfda:	48 21 d1             	and    %rdx,%rcx
 105cfdd:	48 01 f1             	add    %rsi,%rcx
 105cfe0:	48 39 d1             	cmp    %rdx,%rcx
 105cfe3:	0f 82 db db ff ff    	jb     105abc4 <my.vm::run+0x54>
 105cfe9:	48 8d 3d 10 2a 02 00 	lea    0x22a10(%rip),%rdi        # 107fa00 <core_durable_error.verbs+0x3f0>
 105cff0:	e8 0b 77 fc ff       	call   1024700 <myl_core_trap>
 105cff5:	48 8d 3d d4 2c 02 00 	lea    0x22cd4(%rip),%rdi        # 107fcd0 <core_durable_error.verbs+0x6c0>
 105cffc:	ba 01 00 00 00       	mov    $0x1,%edx
 105d001:	48 89 de             	mov    %rbx,%rsi
 105d004:	e8 f7 76 fc ff       	call   1024700 <myl_core_trap>
 105d009:	48 89 f0             	mov    %rsi,%rax
 105d00c:	48 c1 f8 3f          	sar    $0x3f,%rax
 105d010:	48 21 d0             	and    %rdx,%rax
 105d013:	48 01 f0             	add    %rsi,%rax
 105d016:	48 39 d0             	cmp    %rdx,%rax
 105d019:	72 b4                	jb     105cfcf <my.vm::run+0x245f>
 105d01b:	48 8d 3d 2e 34 02 00 	lea    0x2342e(%rip),%rdi        # 1080450 <core_durable_error.verbs+0xe40>
 105d022:	e8 d9 76 fc ff       	call   1024700 <myl_core_trap>
 105d027:	83 f8 09             	cmp    $0x9,%eax
 105d02a:	0f 87 b3 06 00 00    	ja     105d6e3 <my.vm::run+0x2b73>
 105d030:	89 c0                	mov    %eax,%eax
 105d032:	48 8d 0d 07 a4 fa ff 	lea    -0x55bf9(%rip),%rcx        # 1007440 <core_number_pairs+0x1e0>
 105d039:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105d03d:	48 01 c8             	add    %rcx,%rax
 105d040:	ff e0                	jmp    *%rax
 105d042:	48 8d 3d a7 78 02 00 	lea    0x278a7(%rip),%rdi        # 10848f0 <core_durable_error.verbs+0x52e0>
 105d049:	e8 32 ca fc ff       	call   1029a80 <myl_core_assert_fail>
 105d04e:	48 8d 3d 2b 4f 02 00 	lea    0x24f2b(%rip),%rdi        # 1081f80 <core_durable_error.verbs+0x2970>
 105d055:	4c 89 ee             	mov    %r13,%rsi
 105d058:	e8 a3 76 fc ff       	call   1024700 <myl_core_trap>
 105d05d:	48 8d 3d 4c 4f 02 00 	lea    0x24f4c(%rip),%rdi        # 1081fb0 <core_durable_error.verbs+0x29a0>
 105d064:	4c 89 ee             	mov    %r13,%rsi
 105d067:	e8 94 76 fc ff       	call   1024700 <myl_core_trap>
 105d06c:	48 8d 3d dd 4e 02 00 	lea    0x24edd(%rip),%rdi        # 1081f50 <core_durable_error.verbs+0x2940>
 105d073:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105d078:	48 89 c2             	mov    %rax,%rdx
 105d07b:	e8 80 76 fc ff       	call   1024700 <myl_core_trap>
 105d080:	48 8d 3d 29 49 02 00 	lea    0x24929(%rip),%rdi        # 10819b0 <core_durable_error.verbs+0x23a0>
 105d087:	ba 01 00 00 00       	mov    $0x1,%edx
 105d08c:	48 89 ce             	mov    %rcx,%rsi
 105d08f:	e8 6c 76 fc ff       	call   1024700 <myl_core_trap>
 105d094:	0f b6 c0             	movzbl %al,%eax
 105d097:	83 f8 01             	cmp    $0x1,%eax
 105d09a:	0f 84 dc 01 00 00    	je     105d27c <my.vm::run+0x270c>
 105d0a0:	85 c0                	test   %eax,%eax
 105d0a2:	0f 85 e0 01 00 00    	jne    105d288 <my.vm::run+0x2718>
 105d0a8:	48 8d 3d b1 47 02 00 	lea    0x247b1(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d0af:	e8 cc c9 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d0b4:	0f b6 c0             	movzbl %al,%eax
 105d0b7:	83 f8 01             	cmp    $0x1,%eax
 105d0ba:	0f 84 d4 01 00 00    	je     105d294 <my.vm::run+0x2724>
 105d0c0:	85 c0                	test   %eax,%eax
 105d0c2:	0f 85 d8 01 00 00    	jne    105d2a0 <my.vm::run+0x2730>
 105d0c8:	48 8d 3d 91 47 02 00 	lea    0x24791(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d0cf:	e8 ac c9 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d0d4:	83 fa 01             	cmp    $0x1,%edx
 105d0d7:	0f 84 cf 01 00 00    	je     105d2ac <my.vm::run+0x273c>
 105d0dd:	85 d2                	test   %edx,%edx
 105d0df:	0f 85 d3 01 00 00    	jne    105d2b8 <my.vm::run+0x2748>
 105d0e5:	48 8d 3d 74 47 02 00 	lea    0x24774(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d0ec:	e8 8f c9 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d0f1:	0f b6 c0             	movzbl %al,%eax
 105d0f4:	83 f8 01             	cmp    $0x1,%eax
 105d0f7:	0f 84 c7 01 00 00    	je     105d2c4 <my.vm::run+0x2754>
 105d0fd:	85 c0                	test   %eax,%eax
 105d0ff:	0f 85 cb 01 00 00    	jne    105d2d0 <my.vm::run+0x2760>
 105d105:	48 8d 3d 54 47 02 00 	lea    0x24754(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d10c:	e8 6f c9 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d111:	0f b6 c0             	movzbl %al,%eax
 105d114:	83 f8 01             	cmp    $0x1,%eax
 105d117:	0f 84 bf 01 00 00    	je     105d2dc <my.vm::run+0x276c>
 105d11d:	85 c0                	test   %eax,%eax
 105d11f:	0f 85 c3 01 00 00    	jne    105d2e8 <my.vm::run+0x2778>
 105d125:	48 8d 3d 34 47 02 00 	lea    0x24734(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d12c:	e8 4f c9 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d131:	0f b6 c0             	movzbl %al,%eax
 105d134:	83 f8 01             	cmp    $0x1,%eax
 105d137:	0f 84 b7 01 00 00    	je     105d2f4 <my.vm::run+0x2784>
 105d13d:	85 c0                	test   %eax,%eax
 105d13f:	0f 85 bb 01 00 00    	jne    105d300 <my.vm::run+0x2790>
 105d145:	48 8d 3d 14 47 02 00 	lea    0x24714(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d14c:	e8 2f c9 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d151:	0f b6 c0             	movzbl %al,%eax
 105d154:	83 f8 01             	cmp    $0x1,%eax
 105d157:	0f 84 af 01 00 00    	je     105d30c <my.vm::run+0x279c>
 105d15d:	85 c0                	test   %eax,%eax
 105d15f:	0f 85 b3 01 00 00    	jne    105d318 <my.vm::run+0x27a8>
 105d165:	48 8d 3d f4 46 02 00 	lea    0x246f4(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d16c:	e8 0f c9 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d171:	83 f9 01             	cmp    $0x1,%ecx
 105d174:	0f 84 aa 01 00 00    	je     105d324 <my.vm::run+0x27b4>
 105d17a:	85 c9                	test   %ecx,%ecx
 105d17c:	0f 85 ba 01 00 00    	jne    105d33c <my.vm::run+0x27cc>
 105d182:	48 8d 3d d7 46 02 00 	lea    0x246d7(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d189:	e8 f2 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d18e:	0f b6 c0             	movzbl %al,%eax
 105d191:	83 f8 01             	cmp    $0x1,%eax
 105d194:	0f 84 96 01 00 00    	je     105d330 <my.vm::run+0x27c0>
 105d19a:	85 c0                	test   %eax,%eax
 105d19c:	0f 85 a6 01 00 00    	jne    105d348 <my.vm::run+0x27d8>
 105d1a2:	48 8d 3d b7 46 02 00 	lea    0x246b7(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d1a9:	e8 d2 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d1ae:	83 fa 01             	cmp    $0x1,%edx
 105d1b1:	0f 84 9d 01 00 00    	je     105d354 <my.vm::run+0x27e4>
 105d1b7:	85 d2                	test   %edx,%edx
 105d1b9:	0f 85 a1 01 00 00    	jne    105d360 <my.vm::run+0x27f0>
 105d1bf:	48 8d 3d 9a 46 02 00 	lea    0x2469a(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d1c6:	e8 b5 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d1cb:	0f b6 c0             	movzbl %al,%eax
 105d1ce:	83 f8 01             	cmp    $0x1,%eax
 105d1d1:	0f 84 95 01 00 00    	je     105d36c <my.vm::run+0x27fc>
 105d1d7:	85 c0                	test   %eax,%eax
 105d1d9:	0f 85 99 01 00 00    	jne    105d378 <my.vm::run+0x2808>
 105d1df:	48 8d 3d 7a 46 02 00 	lea    0x2467a(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d1e6:	e8 95 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d1eb:	0f b6 c0             	movzbl %al,%eax
 105d1ee:	83 f8 01             	cmp    $0x1,%eax
 105d1f1:	0f 84 8d 01 00 00    	je     105d384 <my.vm::run+0x2814>
 105d1f7:	85 c0                	test   %eax,%eax
 105d1f9:	0f 85 91 01 00 00    	jne    105d390 <my.vm::run+0x2820>
 105d1ff:	48 8d 3d 5a 46 02 00 	lea    0x2465a(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d206:	e8 75 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d20b:	48 8d 3d fe 47 02 00 	lea    0x247fe(%rip),%rdi        # 1081a10 <core_durable_error.verbs+0x2400>
 105d212:	ba 01 00 00 00       	mov    $0x1,%edx
 105d217:	e8 e4 74 fc ff       	call   1024700 <myl_core_trap>
 105d21c:	48 8d 3d fd 76 02 00 	lea    0x276fd(%rip),%rdi        # 1084920 <core_durable_error.verbs+0x5310>
 105d223:	e8 58 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d228:	48 8d 3d b1 77 02 00 	lea    0x277b1(%rip),%rdi        # 10849e0 <core_durable_error.verbs+0x53d0>
 105d22f:	e8 4c c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d234:	48 8d 3d 15 77 02 00 	lea    0x27715(%rip),%rdi        # 1084950 <core_durable_error.verbs+0x5340>
 105d23b:	e8 40 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d240:	48 8d 3d 39 77 02 00 	lea    0x27739(%rip),%rdi        # 1084980 <core_durable_error.verbs+0x5370>
 105d247:	e8 34 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d24c:	48 8d 3d 5d 77 02 00 	lea    0x2775d(%rip),%rdi        # 10849b0 <core_durable_error.verbs+0x53a0>
 105d253:	e8 28 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d258:	48 8d 3d b1 77 02 00 	lea    0x277b1(%rip),%rdi        # 1084a10 <core_durable_error.verbs+0x5400>
 105d25f:	e8 1c c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d264:	48 8d 3d d5 77 02 00 	lea    0x277d5(%rip),%rdi        # 1084a40 <core_durable_error.verbs+0x5430>
 105d26b:	e8 10 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d270:	48 8d 3d f9 77 02 00 	lea    0x277f9(%rip),%rdi        # 1084a70 <core_durable_error.verbs+0x5460>
 105d277:	e8 04 c8 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d27c:	48 8d 3d 0d 46 02 00 	lea    0x2460d(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d283:	e8 f8 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d288:	48 8d 3d 31 46 02 00 	lea    0x24631(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d28f:	e8 ec c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d294:	48 8d 3d f5 45 02 00 	lea    0x245f5(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d29b:	e8 e0 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d2a0:	48 8d 3d 19 46 02 00 	lea    0x24619(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d2a7:	e8 d4 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d2ac:	48 8d 3d dd 45 02 00 	lea    0x245dd(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d2b3:	e8 c8 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d2b8:	48 8d 3d 01 46 02 00 	lea    0x24601(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d2bf:	e8 bc c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d2c4:	48 8d 3d c5 45 02 00 	lea    0x245c5(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d2cb:	e8 b0 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d2d0:	48 8d 3d e9 45 02 00 	lea    0x245e9(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d2d7:	e8 a4 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d2dc:	48 8d 3d ad 45 02 00 	lea    0x245ad(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d2e3:	e8 98 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d2e8:	48 8d 3d d1 45 02 00 	lea    0x245d1(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d2ef:	e8 8c c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d2f4:	48 8d 3d 95 45 02 00 	lea    0x24595(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d2fb:	e8 80 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d300:	48 8d 3d b9 45 02 00 	lea    0x245b9(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d307:	e8 74 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d30c:	48 8d 3d 7d 45 02 00 	lea    0x2457d(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d313:	e8 68 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d318:	48 8d 3d a1 45 02 00 	lea    0x245a1(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d31f:	e8 5c c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d324:	48 8d 3d 65 45 02 00 	lea    0x24565(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d32b:	e8 50 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d330:	48 8d 3d 59 45 02 00 	lea    0x24559(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d337:	e8 44 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d33c:	48 8d 3d 7d 45 02 00 	lea    0x2457d(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d343:	e8 38 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d348:	48 8d 3d 71 45 02 00 	lea    0x24571(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d34f:	e8 2c c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d354:	48 8d 3d 35 45 02 00 	lea    0x24535(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d35b:	e8 20 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d360:	48 8d 3d 59 45 02 00 	lea    0x24559(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d367:	e8 14 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d36c:	48 8d 3d 1d 45 02 00 	lea    0x2451d(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d373:	e8 08 c7 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d378:	48 8d 3d 41 45 02 00 	lea    0x24541(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d37f:	e8 fc c6 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d384:	48 8d 3d 05 45 02 00 	lea    0x24505(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d38b:	e8 f0 c6 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d390:	48 8d 3d 29 45 02 00 	lea    0x24529(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d397:	e8 e4 c6 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d39c:	48 8d 3d dd 2d 02 00 	lea    0x22ddd(%rip),%rdi        # 1080180 <core_durable_error.verbs+0xb70>
 105d3a3:	ba 01 00 00 00       	mov    $0x1,%edx
 105d3a8:	4c 89 ee             	mov    %r13,%rsi
 105d3ab:	e8 50 73 fc ff       	call   1024700 <myl_core_trap>
 105d3b0:	48 8d 3d 19 2f 02 00 	lea    0x22f19(%rip),%rdi        # 10802d0 <core_durable_error.verbs+0xcc0>
 105d3b7:	ba 01 00 00 00       	mov    $0x1,%edx
 105d3bc:	4c 89 ee             	mov    %r13,%rsi
 105d3bf:	e8 3c 73 fc ff       	call   1024700 <myl_core_trap>
 105d3c4:	48 8d 3d a5 40 02 00 	lea    0x240a5(%rip),%rdi        # 1081470 <core_durable_error.verbs+0x1e60>
 105d3cb:	ba 01 00 00 00       	mov    $0x1,%edx
 105d3d0:	48 89 c6             	mov    %rax,%rsi
 105d3d3:	e8 28 73 fc ff       	call   1024700 <myl_core_trap>
 105d3d8:	48 8d 3d e1 2c 02 00 	lea    0x22ce1(%rip),%rdi        # 10800c0 <core_durable_error.verbs+0xab0>
 105d3df:	ba 01 00 00 00       	mov    $0x1,%edx
 105d3e4:	4c 89 ee             	mov    %r13,%rsi
 105d3e7:	e8 14 73 fc ff       	call   1024700 <myl_core_trap>
 105d3ec:	48 8d 3d 4d 2b 02 00 	lea    0x22b4d(%rip),%rdi        # 107ff40 <core_durable_error.verbs+0x930>
 105d3f3:	ba 01 00 00 00       	mov    $0x1,%edx
 105d3f8:	4c 89 ee             	mov    %r13,%rsi
 105d3fb:	e8 00 73 fc ff       	call   1024700 <myl_core_trap>
 105d400:	48 8d 3d 29 2f 02 00 	lea    0x22f29(%rip),%rdi        # 1080330 <core_durable_error.verbs+0xd20>
 105d407:	ba 01 00 00 00       	mov    $0x1,%edx
 105d40c:	e8 ef 72 fc ff       	call   1024700 <myl_core_trap>
 105d411:	48 8d 3d d8 4a 02 00 	lea    0x24ad8(%rip),%rdi        # 1081ef0 <core_durable_error.verbs+0x28e0>
 105d418:	48 89 ce             	mov    %rcx,%rsi
 105d41b:	48 89 c2             	mov    %rax,%rdx
 105d41e:	e8 dd 72 fc ff       	call   1024700 <myl_core_trap>
 105d423:	48 8d 3d 96 26 02 00 	lea    0x22696(%rip),%rdi        # 107fac0 <core_durable_error.verbs+0x4b0>
 105d42a:	48 89 d6             	mov    %rdx,%rsi
 105d42d:	48 89 c2             	mov    %rax,%rdx
 105d430:	e8 cb 72 fc ff       	call   1024700 <myl_core_trap>
 105d435:	48 8d 3d f4 25 02 00 	lea    0x225f4(%rip),%rdi        # 107fa30 <core_durable_error.verbs+0x420>
 105d43c:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105d441:	48 89 c2             	mov    %rax,%rdx
 105d444:	e8 b7 72 fc ff       	call   1024700 <myl_core_trap>
 105d449:	48 8d 3d 90 2d 02 00 	lea    0x22d90(%rip),%rdi        # 10801e0 <core_durable_error.verbs+0xbd0>
 105d450:	ba 01 00 00 00       	mov    $0x1,%edx
 105d455:	4c 89 ee             	mov    %r13,%rsi
 105d458:	e8 a3 72 fc ff       	call   1024700 <myl_core_trap>
 105d45d:	48 8d 3d 0c 43 02 00 	lea    0x2430c(%rip),%rdi        # 1081770 <core_durable_error.verbs+0x2160>
 105d464:	ba 01 00 00 00       	mov    $0x1,%edx
 105d469:	48 89 de             	mov    %rbx,%rsi
 105d46c:	e8 8f 72 fc ff       	call   1024700 <myl_core_trap>
 105d471:	48 8d 3d f8 27 02 00 	lea    0x227f8(%rip),%rdi        # 107fc70 <core_durable_error.verbs+0x660>
 105d478:	ba 01 00 00 00       	mov    $0x1,%edx
 105d47d:	4c 89 ee             	mov    %r13,%rsi
 105d480:	e8 7b 72 fc ff       	call   1024700 <myl_core_trap>
 105d485:	48 8d 3d 94 2c 02 00 	lea    0x22c94(%rip),%rdi        # 1080120 <core_durable_error.verbs+0xb10>
 105d48c:	ba 01 00 00 00       	mov    $0x1,%edx
 105d491:	4c 89 ee             	mov    %r13,%rsi
 105d494:	e8 67 72 fc ff       	call   1024700 <myl_core_trap>
 105d499:	48 8d 3d c0 28 02 00 	lea    0x228c0(%rip),%rdi        # 107fd60 <core_durable_error.verbs+0x750>
 105d4a0:	ba 01 00 00 00       	mov    $0x1,%edx
 105d4a5:	4c 89 ee             	mov    %r13,%rsi
 105d4a8:	e8 53 72 fc ff       	call   1024700 <myl_core_trap>
 105d4ad:	48 8d 3d 8c 42 02 00 	lea    0x2428c(%rip),%rdi        # 1081740 <core_durable_error.verbs+0x2130>
 105d4b4:	ba 01 00 00 00       	mov    $0x1,%edx
 105d4b9:	e8 42 72 fc ff       	call   1024700 <myl_core_trap>
 105d4be:	48 8d 3d 4b 30 02 00 	lea    0x2304b(%rip),%rdi        # 1080510 <core_durable_error.verbs+0xf00>
 105d4c5:	ba 01 00 00 00       	mov    $0x1,%edx
 105d4ca:	e8 31 72 fc ff       	call   1024700 <myl_core_trap>
 105d4cf:	48 8d 3d ea 49 02 00 	lea    0x249ea(%rip),%rdi        # 1081ec0 <core_durable_error.verbs+0x28b0>
 105d4d6:	ba 01 00 00 00       	mov    $0x1,%edx
 105d4db:	48 89 de             	mov    %rbx,%rsi
 105d4de:	e8 1d 72 fc ff       	call   1024700 <myl_core_trap>
 105d4e3:	48 8d 3d b6 30 02 00 	lea    0x230b6(%rip),%rdi        # 10805a0 <core_durable_error.verbs+0xf90>
 105d4ea:	ba 01 00 00 00       	mov    $0x1,%edx
 105d4ef:	e8 0c 72 fc ff       	call   1024700 <myl_core_trap>
 105d4f4:	48 8d 3d 65 2b 02 00 	lea    0x22b65(%rip),%rdi        # 1080060 <core_durable_error.verbs+0xa50>
 105d4fb:	ba 01 00 00 00       	mov    $0x1,%edx
 105d500:	4c 89 ee             	mov    %r13,%rsi
 105d503:	e8 f8 71 fc ff       	call   1024700 <myl_core_trap>
 105d508:	48 8d 3d 61 2a 02 00 	lea    0x22a61(%rip),%rdi        # 107ff70 <core_durable_error.verbs+0x960>
 105d50f:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105d514:	48 89 c2             	mov    %rax,%rdx
 105d517:	e8 e4 71 fc ff       	call   1024700 <myl_core_trap>
 105d51c:	48 8d 3d fd 25 02 00 	lea    0x225fd(%rip),%rdi        # 107fb20 <core_durable_error.verbs+0x510>
 105d523:	48 89 d6             	mov    %rdx,%rsi
 105d526:	48 89 c2             	mov    %rax,%rdx
 105d529:	e8 d2 71 fc ff       	call   1024700 <myl_core_trap>
 105d52e:	48 8d 3d fb 4b 02 00 	lea    0x24bfb(%rip),%rdi        # 1082130 <core_durable_error.verbs+0x2b20>
 105d535:	ba 01 00 00 00       	mov    $0x1,%edx
 105d53a:	4c 89 ee             	mov    %r13,%rsi
 105d53d:	e8 be 71 fc ff       	call   1024700 <myl_core_trap>
 105d542:	48 8d 3d 47 46 02 00 	lea    0x24647(%rip),%rdi        # 1081b90 <core_durable_error.verbs+0x2580>
 105d549:	ba 01 00 00 00       	mov    $0x1,%edx
 105d54e:	e8 ad 71 fc ff       	call   1024700 <myl_core_trap>
 105d553:	48 8d 3d 46 2a 02 00 	lea    0x22a46(%rip),%rdi        # 107ffa0 <core_durable_error.verbs+0x990>
 105d55a:	ba 01 00 00 00       	mov    $0x1,%edx
 105d55f:	4c 89 ee             	mov    %r13,%rsi
 105d562:	e8 99 71 fc ff       	call   1024700 <myl_core_trap>
 105d567:	48 8d 3d d2 4a 02 00 	lea    0x24ad2(%rip),%rdi        # 1082040 <core_durable_error.verbs+0x2a30>
 105d56e:	ba 01 00 00 00       	mov    $0x1,%edx
 105d573:	e8 88 71 fc ff       	call   1024700 <myl_core_trap>
 105d578:	48 8d 3d 01 29 02 00 	lea    0x22901(%rip),%rdi        # 107fe80 <core_durable_error.verbs+0x870>
 105d57f:	ba 01 00 00 00       	mov    $0x1,%edx
 105d584:	4c 89 ee             	mov    %r13,%rsi
 105d587:	e8 74 71 fc ff       	call   1024700 <myl_core_trap>
 105d58c:	48 8d 3d 8d 4c 02 00 	lea    0x24c8d(%rip),%rdi        # 1082220 <core_durable_error.verbs+0x2c10>
 105d593:	ba 01 00 00 00       	mov    $0x1,%edx
 105d598:	4c 89 ee             	mov    %r13,%rsi
 105d59b:	e8 60 71 fc ff       	call   1024700 <myl_core_trap>
 105d5a0:	48 8d 3d 99 2f 02 00 	lea    0x22f99(%rip),%rdi        # 1080540 <core_durable_error.verbs+0xf30>
 105d5a7:	ba 01 00 00 00       	mov    $0x1,%edx
 105d5ac:	e8 4f 71 fc ff       	call   1024700 <myl_core_trap>
 105d5b1:	48 8d 3d 68 28 02 00 	lea    0x22868(%rip),%rdi        # 107fe20 <core_durable_error.verbs+0x810>
 105d5b8:	ba 01 00 00 00       	mov    $0x1,%edx
 105d5bd:	4c 89 ee             	mov    %r13,%rsi
 105d5c0:	e8 3b 71 fc ff       	call   1024700 <myl_core_trap>
 105d5c5:	48 8d 3d 34 4b 02 00 	lea    0x24b34(%rip),%rdi        # 1082100 <core_durable_error.verbs+0x2af0>
 105d5cc:	ba 01 00 00 00       	mov    $0x1,%edx
 105d5d1:	e8 2a 71 fc ff       	call   1024700 <myl_core_trap>
 105d5d6:	48 8d 3d 93 2c 02 00 	lea    0x22c93(%rip),%rdi        # 1080270 <core_durable_error.verbs+0xc60>
 105d5dd:	48 89 ce             	mov    %rcx,%rsi
 105d5e0:	48 89 c2             	mov    %rax,%rdx
 105d5e3:	e8 18 71 fc ff       	call   1024700 <myl_core_trap>
 105d5e8:	48 8d 3d a1 2d 02 00 	lea    0x22da1(%rip),%rdi        # 1080390 <core_durable_error.verbs+0xd80>
 105d5ef:	ba 01 00 00 00       	mov    $0x1,%edx
 105d5f4:	e8 07 71 fc ff       	call   1024700 <myl_core_trap>
 105d5f9:	48 8d 3d e0 40 02 00 	lea    0x240e0(%rip),%rdi        # 10816e0 <core_durable_error.verbs+0x20d0>
 105d600:	ba 01 00 00 00       	mov    $0x1,%edx
 105d605:	e8 f6 70 fc ff       	call   1024700 <myl_core_trap>
 105d60a:	48 8d 3d af 2d 02 00 	lea    0x22daf(%rip),%rdi        # 10803c0 <core_durable_error.verbs+0xdb0>
 105d611:	ba 01 00 00 00       	mov    $0x1,%edx
 105d616:	4c 89 ee             	mov    %r13,%rsi
 105d619:	e8 e2 70 fc ff       	call   1024700 <myl_core_trap>
 105d61e:	48 8d 3d 9b 27 02 00 	lea    0x2279b(%rip),%rdi        # 107fdc0 <core_durable_error.verbs+0x7b0>
 105d625:	ba 01 00 00 00       	mov    $0x1,%edx
 105d62a:	4c 89 ee             	mov    %r13,%rsi
 105d62d:	e8 ce 70 fc ff       	call   1024700 <myl_core_trap>
 105d632:	48 8d 3d b7 4b 02 00 	lea    0x24bb7(%rip),%rdi        # 10821f0 <core_durable_error.verbs+0x2be0>
 105d639:	ba 01 00 00 00       	mov    $0x1,%edx
 105d63e:	e8 bd 70 fc ff       	call   1024700 <myl_core_trap>
 105d643:	48 8d 3d b6 29 02 00 	lea    0x229b6(%rip),%rdi        # 1080000 <core_durable_error.verbs+0x9f0>
 105d64a:	ba 01 00 00 00       	mov    $0x1,%edx
 105d64f:	4c 89 ee             	mov    %r13,%rsi
 105d652:	e8 a9 70 fc ff       	call   1024700 <myl_core_trap>
 105d657:	48 8d 3d e2 2b 02 00 	lea    0x22be2(%rip),%rdi        # 1080240 <core_durable_error.verbs+0xc30>
 105d65e:	ba 01 00 00 00       	mov    $0x1,%edx
 105d663:	4c 89 ee             	mov    %r13,%rsi
 105d666:	e8 95 70 fc ff       	call   1024700 <myl_core_trap>
 105d66b:	48 8d 3d fe 43 02 00 	lea    0x243fe(%rip),%rdi        # 1081a70 <core_durable_error.verbs+0x2460>
 105d672:	ba 01 00 00 00       	mov    $0x1,%edx
 105d677:	48 89 c6             	mov    %rax,%rsi
 105d67a:	e8 81 70 fc ff       	call   1024700 <myl_core_trap>
 105d67f:	48 8d 3d 2a 28 02 00 	lea    0x2282a(%rip),%rdi        # 107feb0 <core_durable_error.verbs+0x8a0>
 105d686:	ba 01 00 00 00       	mov    $0x1,%edx
 105d68b:	4c 89 ee             	mov    %r13,%rsi
 105d68e:	e8 6d 70 fc ff       	call   1024700 <myl_core_trap>
 105d693:	48 8d 3d b6 24 02 00 	lea    0x224b6(%rip),%rdi        # 107fb50 <core_durable_error.verbs+0x540>
 105d69a:	ba 01 00 00 00       	mov    $0x1,%edx
 105d69f:	48 89 de             	mov    %rbx,%rsi
 105d6a2:	e8 59 70 fc ff       	call   1024700 <myl_core_trap>
 105d6a7:	48 8d 3d 02 25 02 00 	lea    0x22502(%rip),%rdi        # 107fbb0 <core_durable_error.verbs+0x5a0>
 105d6ae:	ba 01 00 00 00       	mov    $0x1,%edx
 105d6b3:	48 89 de             	mov    %rbx,%rsi
 105d6b6:	e8 45 70 fc ff       	call   1024700 <myl_core_trap>
 105d6bb:	48 8d 3d be 2d 02 00 	lea    0x22dbe(%rip),%rdi        # 1080480 <core_durable_error.verbs+0xe70>
 105d6c2:	ba 01 00 00 00       	mov    $0x1,%edx
 105d6c7:	48 89 de             	mov    %rbx,%rsi
 105d6ca:	e8 31 70 fc ff       	call   1024700 <myl_core_trap>
 105d6cf:	48 8d 3d 3a 25 02 00 	lea    0x2253a(%rip),%rdi        # 107fc10 <core_durable_error.verbs+0x600>
 105d6d6:	ba 01 00 00 00       	mov    $0x1,%edx
 105d6db:	48 89 de             	mov    %rbx,%rsi
 105d6de:	e8 1d 70 fc ff       	call   1024700 <myl_core_trap>
 105d6e3:	48 8d 3d b6 73 02 00 	lea    0x273b6(%rip),%rdi        # 1084aa0 <core_durable_error.verbs+0x5490>
 105d6ea:	e8 91 c3 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d6ef:	0f b6 c0             	movzbl %al,%eax
 105d6f2:	83 f8 01             	cmp    $0x1,%eax
 105d6f5:	0f 84 e3 00 00 00    	je     105d7de <my.vm::run+0x2c6e>
 105d6fb:	85 c0                	test   %eax,%eax
 105d6fd:	0f 85 e7 00 00 00    	jne    105d7ea <my.vm::run+0x2c7a>
 105d703:	48 8d 3d 56 41 02 00 	lea    0x24156(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d70a:	e8 71 c3 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d70f:	83 fe 01             	cmp    $0x1,%esi
 105d712:	0f 84 de 00 00 00    	je     105d7f6 <my.vm::run+0x2c86>
 105d718:	85 f6                	test   %esi,%esi
 105d71a:	0f 85 e2 00 00 00    	jne    105d802 <my.vm::run+0x2c92>
 105d720:	48 8d 3d 39 41 02 00 	lea    0x24139(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d727:	e8 54 c3 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d72c:	48 8d 3d ed 3e 02 00 	lea    0x23eed(%rip),%rdi        # 1081620 <core_durable_error.verbs+0x2010>
 105d733:	ba 01 00 00 00       	mov    $0x1,%edx
 105d738:	48 89 ce             	mov    %rcx,%rsi
 105d73b:	e8 c0 6f fc ff       	call   1024700 <myl_core_trap>
 105d740:	48 8d 3d 49 3e 02 00 	lea    0x23e49(%rip),%rdi        # 1081590 <core_durable_error.verbs+0x1f80>
 105d747:	ba 01 00 00 00       	mov    $0x1,%edx
 105d74c:	e8 af 6f fc ff       	call   1024700 <myl_core_trap>
 105d751:	48 8d 3d 98 23 02 00 	lea    0x22398(%rip),%rdi        # 107faf0 <core_durable_error.verbs+0x4e0>
 105d758:	48 89 ee             	mov    %rbp,%rsi
 105d75b:	48 89 c2             	mov    %rax,%rdx
 105d75e:	e8 9d 6f fc ff       	call   1024700 <myl_core_trap>
 105d763:	48 8d 3d d6 3c 02 00 	lea    0x23cd6(%rip),%rdi        # 1081440 <core_durable_error.verbs+0x1e30>
 105d76a:	ba 01 00 00 00       	mov    $0x1,%edx
 105d76f:	e8 8c 6f fc ff       	call   1024700 <myl_core_trap>
 105d774:	48 8d 3d 55 22 02 00 	lea    0x22255(%rip),%rdi        # 107f9d0 <core_durable_error.verbs+0x3c0>
 105d77b:	ba 01 00 00 00       	mov    $0x1,%edx
 105d780:	48 89 de             	mov    %rbx,%rsi
 105d783:	e8 78 6f fc ff       	call   1024700 <myl_core_trap>
 105d788:	48 8d 3d f1 3e 02 00 	lea    0x23ef1(%rip),%rdi        # 1081680 <core_durable_error.verbs+0x2070>
 105d78f:	ba 01 00 00 00       	mov    $0x1,%edx
 105d794:	48 89 ce             	mov    %rcx,%rsi
 105d797:	e8 64 6f fc ff       	call   1024700 <myl_core_trap>
 105d79c:	48 8d 3d 8d 3d 02 00 	lea    0x23d8d(%rip),%rdi        # 1081530 <core_durable_error.verbs+0x1f20>
 105d7a3:	ba 01 00 00 00       	mov    $0x1,%edx
 105d7a8:	e8 53 6f fc ff       	call   1024700 <myl_core_trap>
 105d7ad:	0f b6 c0             	movzbl %al,%eax
 105d7b0:	83 f8 01             	cmp    $0x1,%eax
 105d7b3:	0f 84 be 00 00 00    	je     105d877 <my.vm::run+0x2d07>
 105d7b9:	85 c0                	test   %eax,%eax
 105d7bb:	0f 85 c2 00 00 00    	jne    105d883 <my.vm::run+0x2d13>
 105d7c1:	48 8d 3d 98 40 02 00 	lea    0x24098(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d7c8:	e8 b3 c2 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d7cd:	48 8d 3d 5c 43 02 00 	lea    0x2435c(%rip),%rdi        # 1081b30 <core_durable_error.verbs+0x2520>
 105d7d4:	ba 01 00 00 00       	mov    $0x1,%edx
 105d7d9:	e8 22 6f fc ff       	call   1024700 <myl_core_trap>
 105d7de:	48 8d 3d ab 40 02 00 	lea    0x240ab(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d7e5:	e8 96 c2 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d7ea:	48 8d 3d cf 40 02 00 	lea    0x240cf(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d7f1:	e8 8a c2 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d7f6:	48 8d 3d 93 40 02 00 	lea    0x24093(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d7fd:	e8 7e c2 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d802:	48 8d 3d b7 40 02 00 	lea    0x240b7(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d809:	e8 72 c2 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d80e:	48 8d 3d bb 42 02 00 	lea    0x242bb(%rip),%rdi        # 1081ad0 <core_durable_error.verbs+0x24c0>
 105d815:	ba 01 00 00 00       	mov    $0x1,%edx
 105d81a:	e8 e1 6e fc ff       	call   1024700 <myl_core_trap>
 105d81f:	83 f8 01             	cmp    $0x1,%eax
 105d822:	0f 84 8c 00 00 00    	je     105d8b4 <my.vm::run+0x2d44>
 105d828:	85 c0                	test   %eax,%eax
 105d82a:	0f 85 90 00 00 00    	jne    105d8c0 <my.vm::run+0x2d50>
 105d830:	48 8d 3d 29 40 02 00 	lea    0x24029(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d837:	e8 44 c2 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d83c:	48 8d 3d 1d 46 02 00 	lea    0x2461d(%rip),%rdi        # 1081e60 <core_durable_error.verbs+0x2850>
 105d843:	ba 01 00 00 00       	mov    $0x1,%edx
 105d848:	48 89 c6             	mov    %rax,%rsi
 105d84b:	e8 b0 6e fc ff       	call   1024700 <myl_core_trap>
 105d850:	48 8d 3d d9 45 02 00 	lea    0x245d9(%rip),%rdi        # 1081e30 <core_durable_error.verbs+0x2820>
 105d857:	48 89 de             	mov    %rbx,%rsi
 105d85a:	4c 89 ea             	mov    %r13,%rdx
 105d85d:	e8 9e 6e fc ff       	call   1024700 <myl_core_trap>
 105d862:	83 f9 01             	cmp    $0x1,%ecx
 105d865:	74 65                	je     105d8cc <my.vm::run+0x2d5c>
 105d867:	85 c9                	test   %ecx,%ecx
 105d869:	75 6d                	jne    105d8d8 <my.vm::run+0x2d68>
 105d86b:	48 8d 3d ee 3f 02 00 	lea    0x23fee(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x2250>
 105d872:	e8 09 c2 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d877:	48 8d 3d 12 40 02 00 	lea    0x24012(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d87e:	e8 fd c1 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d883:	48 8d 3d 36 40 02 00 	lea    0x24036(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d88a:	e8 f1 c1 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d88f:	48 8d 3d aa 68 02 00 	lea    0x268aa(%rip),%rdi        # 1084140 <core_durable_error.verbs+0x4b30>
 105d896:	ba 01 00 00 00       	mov    $0x1,%edx
 105d89b:	48 89 c6             	mov    %rax,%rsi
 105d89e:	e8 5d 6e fc ff       	call   1024700 <myl_core_trap>
 105d8a3:	48 8d 3d f6 68 02 00 	lea    0x268f6(%rip),%rdi        # 10841a0 <core_durable_error.verbs+0x4b90>
 105d8aa:	ba 01 00 00 00       	mov    $0x1,%edx
 105d8af:	e8 4c 6e fc ff       	call   1024700 <myl_core_trap>
 105d8b4:	48 8d 3d d5 3f 02 00 	lea    0x23fd5(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d8bb:	e8 c0 c1 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d8c0:	48 8d 3d f9 3f 02 00 	lea    0x23ff9(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d8c7:	e8 b4 c1 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d8cc:	48 8d 3d bd 3f 02 00 	lea    0x23fbd(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x2280>
 105d8d3:	e8 a8 c1 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d8d8:	48 8d 3d e1 3f 02 00 	lea    0x23fe1(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x22b0>
 105d8df:	e8 9c c1 fc ff       	call   1029a80 <myl_core_assert_fail>
 105d8e4:	48 8d 3d 35 2b 02 00 	lea    0x22b35(%rip),%rdi        # 1080420 <core_durable_error.verbs+0xe10>
 105d8eb:	ba 01 00 00 00       	mov    $0x1,%edx
 105d8f0:	48 89 c6             	mov    %rax,%rsi
 105d8f3:	e8 08 6e fc ff       	call   1024700 <myl_core_trap>
 105d8f8:	48 8d 3d 01 24 02 00 	lea    0x22401(%rip),%rdi        # 107fd00 <core_durable_error.verbs+0x6f0>
 105d8ff:	e8 fc 6d fc ff       	call   1024700 <myl_core_trap>
 105d904:	48 8d 3d d5 40 02 00 	lea    0x240d5(%rip),%rdi        # 10819e0 <core_durable_error.verbs+0x23d0>
 105d90b:	e8 f0 6d fc ff       	call   1024700 <myl_core_trap>
 105d910:	48 8d 3d b9 71 02 00 	lea    0x271b9(%rip),%rdi        # 1084ad0 <core_durable_error.verbs+0x54c0>
 105d917:	48 89 ee             	mov    %rbp,%rsi
 105d91a:	e8 e1 6d fc ff       	call   1024700 <myl_core_trap>
 105d91f:	48 8d 3d 1a 41 02 00 	lea    0x2411a(%rip),%rdi        # 1081a40 <core_durable_error.verbs+0x2430>
 105d926:	4c 89 ee             	mov    %r13,%rsi
 105d929:	e8 d2 6d fc ff       	call   1024700 <myl_core_trap>
 105d92e:	48 8d 3d 7b 28 02 00 	lea    0x2287b(%rip),%rdi        # 10801b0 <core_durable_error.verbs+0xba0>
 105d935:	4c 89 e6             	mov    %r12,%rsi
 105d938:	e8 c3 6d fc ff       	call   1024700 <myl_core_trap>
 105d93d:	48 8d 3d 6c 2b 02 00 	lea    0x22b6c(%rip),%rdi        # 10804b0 <core_durable_error.verbs+0xea0>
 105d944:	4c 89 ee             	mov    %r13,%rsi
 105d947:	e8 b4 6d fc ff       	call   1024700 <myl_core_trap>
 105d94c:	48 8d 3d ed 22 02 00 	lea    0x222ed(%rip),%rdi        # 107fc40 <core_durable_error.verbs+0x630>
 105d953:	e8 a8 6d fc ff       	call   1024700 <myl_core_trap>
 105d958:	48 8d 3d 71 26 02 00 	lea    0x22671(%rip),%rdi        # 107ffd0 <core_durable_error.verbs+0x9c0>
 105d95f:	e8 9c 6d fc ff       	call   1024700 <myl_core_trap>
 105d964:	48 8d 3d 15 49 02 00 	lea    0x24915(%rip),%rdi        # 1082280 <core_durable_error.verbs+0x2c70>
 105d96b:	4c 89 ee             	mov    %r13,%rsi
 105d96e:	e8 8d 6d fc ff       	call   1024700 <myl_core_trap>
 105d973:	48 8d 3d 06 22 02 00 	lea    0x22206(%rip),%rdi        # 107fb80 <core_durable_error.verbs+0x570>
 105d97a:	e8 81 6d fc ff       	call   1024700 <myl_core_trap>
 105d97f:	48 8d 3d ca 24 02 00 	lea    0x224ca(%rip),%rdi        # 107fe50 <core_durable_error.verbs+0x840>
 105d986:	4c 89 ee             	mov    %r13,%rsi
 105d989:	e8 72 6d fc ff       	call   1024700 <myl_core_trap>
 105d98e:	48 8d 3d 3b 2c 02 00 	lea    0x22c3b(%rip),%rdi        # 10805d0 <core_durable_error.verbs+0xfc0>
 105d995:	4c 89 ee             	mov    %r13,%rsi
 105d998:	e8 63 6d fc ff       	call   1024700 <myl_core_trap>
 105d99d:	48 8d 3d 1c 6f 02 00 	lea    0x26f1c(%rip),%rdi        # 10848c0 <core_durable_error.verbs+0x52b0>
 105d9a4:	48 89 d6             	mov    %rdx,%rsi
 105d9a7:	48 89 c2             	mov    %rax,%rdx
 105d9aa:	e8 51 6d fc ff       	call   1024700 <myl_core_trap>
 105d9af:	48 8d 3d ba 2b 02 00 	lea    0x22bba(%rip),%rdi        # 1080570 <core_durable_error.verbs+0xf60>
 105d9b6:	4c 89 ee             	mov    %r13,%rsi
 105d9b9:	e8 42 6d fc ff       	call   1024700 <myl_core_trap>
 105d9be:	48 8d 3d db 22 02 00 	lea    0x222db(%rip),%rdi        # 107fca0 <core_durable_error.verbs+0x690>
 105d9c5:	e8 36 6d fc ff       	call   1024700 <myl_core_trap>
 105d9ca:	48 8d 3d df 48 02 00 	lea    0x248df(%rip),%rdi        # 10822b0 <core_durable_error.verbs+0x2ca0>
 105d9d1:	4c 89 ee             	mov    %r13,%rsi
 105d9d4:	e8 27 6d fc ff       	call   1024700 <myl_core_trap>
 105d9d9:	48 8d 3d e0 41 02 00 	lea    0x241e0(%rip),%rdi        # 1081bc0 <core_durable_error.verbs+0x25b0>
 105d9e0:	4c 89 ee             	mov    %r13,%rsi
 105d9e3:	e8 18 6d fc ff       	call   1024700 <myl_core_trap>
 105d9e8:	48 8d 3d a1 20 02 00 	lea    0x220a1(%rip),%rdi        # 107fa90 <core_durable_error.verbs+0x480>
 105d9ef:	e8 0c 6d fc ff       	call   1024700 <myl_core_trap>
 105d9f4:	48 8d 3d 65 29 02 00 	lea    0x22965(%rip),%rdi        # 1080360 <core_durable_error.verbs+0xd50>
 105d9fb:	4c 89 ee             	mov    %r13,%rsi
 105d9fe:	e8 fd 6c fc ff       	call   1024700 <myl_core_trap>
 105da03:	48 8d 3d 26 23 02 00 	lea    0x22326(%rip),%rdi        # 107fd30 <core_durable_error.verbs+0x720>
 105da0a:	4c 89 ee             	mov    %r13,%rsi
 105da0d:	48 89 ca             	mov    %rcx,%rdx
 105da10:	e8 eb 6c fc ff       	call   1024700 <myl_core_trap>
 105da15:	48 8d 3d 14 26 02 00 	lea    0x22614(%rip),%rdi        # 1080030 <core_durable_error.verbs+0xa20>
 105da1c:	e8 df 6c fc ff       	call   1024700 <myl_core_trap>
 105da21:	48 8d 3d 78 28 02 00 	lea    0x22878(%rip),%rdi        # 10802a0 <core_durable_error.verbs+0xc90>
 105da28:	e8 d3 6c fc ff       	call   1024700 <myl_core_trap>
 105da2d:	48 8d 3d dc 45 02 00 	lea    0x245dc(%rip),%rdi        # 1082010 <core_durable_error.verbs+0x2a00>
 105da34:	e8 c7 6c fc ff       	call   1024700 <myl_core_trap>
 105da39:	48 8d 3d a0 24 02 00 	lea    0x224a0(%rip),%rdi        # 107fee0 <core_durable_error.verbs+0x8d0>
 105da40:	e8 bb 6c fc ff       	call   1024700 <myl_core_trap>
 105da45:	48 8d 3d a4 26 02 00 	lea    0x226a4(%rip),%rdi        # 10800f0 <core_durable_error.verbs+0xae0>
 105da4c:	e8 af 6c fc ff       	call   1024700 <myl_core_trap>
 105da51:	48 8d 3d b8 24 02 00 	lea    0x224b8(%rip),%rdi        # 107ff10 <core_durable_error.verbs+0x900>
 105da58:	4c 89 ee             	mov    %r13,%rsi
 105da5b:	e8 a0 6c fc ff       	call   1024700 <myl_core_trap>
 105da60:	48 8d 3d 39 40 02 00 	lea    0x24039(%rip),%rdi        # 1081aa0 <core_durable_error.verbs+0x2490>
 105da67:	e8 94 6c fc ff       	call   1024700 <myl_core_trap>
 105da6c:	48 8d 3d 1d 26 02 00 	lea    0x2261d(%rip),%rdi        # 1080090 <core_durable_error.verbs+0xa80>
 105da73:	e8 88 6c fc ff       	call   1024700 <myl_core_trap>
 105da78:	48 8d 3d d1 47 02 00 	lea    0x247d1(%rip),%rdi        # 1082250 <core_durable_error.verbs+0x2c40>
 105da7f:	e8 7c 6c fc ff       	call   1024700 <myl_core_trap>
 105da84:	48 8d 3d 85 3c 02 00 	lea    0x23c85(%rip),%rdi        # 1081710 <core_durable_error.verbs+0x2100>
 105da8b:	4c 89 ee             	mov    %r13,%rsi
 105da8e:	e8 6d 6c fc ff       	call   1024700 <myl_core_trap>
 105da93:	48 8d 3d 66 28 02 00 	lea    0x22866(%rip),%rdi        # 1080300 <core_durable_error.verbs+0xcf0>
 105da9a:	e8 61 6c fc ff       	call   1024700 <myl_core_trap>
 105da9f:	48 8d 3d 7a 44 02 00 	lea    0x2447a(%rip),%rdi        # 1081f20 <core_durable_error.verbs+0x2910>
 105daa6:	e8 55 6c fc ff       	call   1024700 <myl_core_trap>
 105daab:	48 8d 3d 2e 45 02 00 	lea    0x2452e(%rip),%rdi        # 1081fe0 <core_durable_error.verbs+0x29d0>
 105dab2:	e8 49 6c fc ff       	call   1024700 <myl_core_trap>
 105dab7:	48 8d 3d 32 29 02 00 	lea    0x22932(%rip),%rdi        # 10803f0 <core_durable_error.verbs+0xde0>
 105dabe:	e8 3d 6c fc ff       	call   1024700 <myl_core_trap>
 105dac3:	48 8d 3d 26 23 02 00 	lea    0x22326(%rip),%rdi        # 107fdf0 <core_durable_error.verbs+0x7e0>
 105daca:	4c 89 ee             	mov    %r13,%rsi
 105dacd:	e8 2e 6c fc ff       	call   1024700 <myl_core_trap>
 105dad2:	48 8d 3d 87 46 02 00 	lea    0x24687(%rip),%rdi        # 1082160 <core_durable_error.verbs+0x2b50>
 105dad9:	e8 22 6c fc ff       	call   1024700 <myl_core_trap>
 105dade:	48 8d 3d bb 39 02 00 	lea    0x239bb(%rip),%rdi        # 10814a0 <core_durable_error.verbs+0x1e90>
 105dae5:	e8 16 6c fc ff       	call   1024700 <myl_core_trap>
 105daea:	48 8d 3d ef 20 02 00 	lea    0x220ef(%rip),%rdi        # 107fbe0 <core_durable_error.verbs+0x5d0>
 105daf1:	e8 0a 6c fc ff       	call   1024700 <myl_core_trap>
 105daf6:	48 8d 3d 93 22 02 00 	lea    0x22293(%rip),%rdi        # 107fd90 <core_durable_error.verbs+0x780>
 105dafd:	4c 89 ee             	mov    %r13,%rsi
 105db00:	e8 fb 6b fc ff       	call   1024700 <myl_core_trap>
 105db05:	48 8d 3d 04 27 02 00 	lea    0x22704(%rip),%rdi        # 1080210 <core_durable_error.verbs+0xc00>
 105db0c:	48 89 ca             	mov    %rcx,%rdx
 105db0f:	e8 ec 6b fc ff       	call   1024700 <myl_core_trap>
 105db14:	48 8d 3d 35 26 02 00 	lea    0x22635(%rip),%rdi        # 1080150 <core_durable_error.verbs+0xb40>
 105db1b:	e8 e0 6b fc ff       	call   1024700 <myl_core_trap>
 105db20:	48 8d 3d 79 3c 02 00 	lea    0x23c79(%rip),%rdi        # 10817a0 <core_durable_error.verbs+0x2190>
 105db27:	4c 89 ee             	mov    %r13,%rsi
 105db2a:	e8 d1 6b fc ff       	call   1024700 <myl_core_trap>
 105db2f:	48 8d 3d 2a 1f 02 00 	lea    0x21f2a(%rip),%rdi        # 107fa60 <core_durable_error.verbs+0x450>
 105db36:	e8 c5 6b fc ff       	call   1024700 <myl_core_trap>
 105db3b:	48 8d 3d 9e 29 02 00 	lea    0x2299e(%rip),%rdi        # 10804e0 <core_durable_error.verbs+0xed0>
 105db42:	e8 b9 6b fc ff       	call   1024700 <myl_core_trap>
 105db47:	48 8d 3d b2 3f 02 00 	lea    0x23fb2(%rip),%rdi        # 1081b00 <core_durable_error.verbs+0x24f0>
 105db4e:	48 89 c6             	mov    %rax,%rsi
 105db51:	e8 aa 6b fc ff       	call   1024700 <myl_core_trap>
 105db56:	48 8d 3d 13 66 02 00 	lea    0x26613(%rip),%rdi        # 1084170 <core_durable_error.verbs+0x4b60>
 105db5d:	e8 9e 6b fc ff       	call   1024700 <myl_core_trap>
 105db62:	48 8d 3d c7 3c 02 00 	lea    0x23cc7(%rip),%rdi        # 1081830 <core_durable_error.verbs+0x2220>
 105db69:	4c 89 ee             	mov    %r13,%rsi
 105db6c:	e8 8f 6b fc ff       	call   1024700 <myl_core_trap>
 105db71:	48 8d 3d 38 65 02 00 	lea    0x26538(%rip),%rdi        # 10840b0 <core_durable_error.verbs+0x4aa0>
 105db78:	4c 89 c6             	mov    %r8,%rsi
 105db7b:	48 89 ca             	mov    %rcx,%rdx
 105db7e:	e8 7d 6b fc ff       	call   1024700 <myl_core_trap>
 105db83:	48 8d 3d 56 65 02 00 	lea    0x26556(%rip),%rdi        # 10840e0 <core_durable_error.verbs+0x4ad0>
 105db8a:	e8 71 6b fc ff       	call   1024700 <myl_core_trap>
 105db8f:	48 8d 3d 2a 3a 02 00 	lea    0x23a2a(%rip),%rdi        # 10815c0 <core_durable_error.verbs+0x1fb0>
 105db96:	48 89 c6             	mov    %rax,%rsi
 105db99:	e8 62 6b fc ff       	call   1024700 <myl_core_trap>
 105db9e:	48 8d 3d bb 39 02 00 	lea    0x239bb(%rip),%rdi        # 1081560 <core_durable_error.verbs+0x1f50>
 105dba5:	e8 56 6b fc ff       	call   1024700 <myl_core_trap>
 105dbaa:	48 8d 3d 9f 3a 02 00 	lea    0x23a9f(%rip),%rdi        # 1081650 <core_durable_error.verbs+0x2040>
 105dbb1:	e8 4a 6b fc ff       	call   1024700 <myl_core_trap>
 105dbb6:	48 8d 3d 63 5e 02 00 	lea    0x25e63(%rip),%rdi        # 1083a20 <core_durable_error.verbs+0x4410>
 105dbbd:	e8 3e 6b fc ff       	call   1024700 <myl_core_trap>
 105dbc2:	48 8d 3d 37 6f 02 00 	lea    0x26f37(%rip),%rdi        # 1084b00 <core_durable_error.verbs+0x54f0>
 105dbc9:	48 89 c6             	mov    %rax,%rsi
 105dbcc:	48 89 ca             	mov    %rcx,%rdx
 105dbcf:	e8 2c 6b fc ff       	call   1024700 <myl_core_trap>
 105dbd4:	48 8d 3d 45 5e 02 00 	lea    0x25e45(%rip),%rdi        # 1083a20 <core_durable_error.verbs+0x4410>
 105dbdb:	e8 20 6b fc ff       	call   1024700 <myl_core_trap>
 105dbe0:	48 8d 3d 29 65 02 00 	lea    0x26529(%rip),%rdi        # 1084110 <core_durable_error.verbs+0x4b00>
 105dbe7:	48 89 c6             	mov    %rax,%rsi
 105dbea:	e8 11 6b fc ff       	call   1024700 <myl_core_trap>
 105dbef:	48 8d 3d da 38 02 00 	lea    0x238da(%rip),%rdi        # 10814d0 <core_durable_error.verbs+0x1ec0>
 105dbf6:	e8 05 6b fc ff       	call   1024700 <myl_core_trap>
 105dbfb:	48 8d 3d 1e 5e 02 00 	lea    0x25e1e(%rip),%rdi        # 1083a20 <core_durable_error.verbs+0x4410>
 105dc02:	4c 89 e6             	mov    %r12,%rsi
 105dc05:	e8 f6 6a fc ff       	call   1024700 <myl_core_trap>
 105dc0a:	48 8d 3d 4f 3f 02 00 	lea    0x23f4f(%rip),%rdi        # 1081b60 <core_durable_error.verbs+0x2550>
 105dc11:	4c 89 ee             	mov    %r13,%rsi
 105dc14:	e8 e7 6a fc ff       	call   1024700 <myl_core_trap>
 105dc19:	48 8d 3d 70 45 02 00 	lea    0x24570(%rip),%rdi        # 1082190 <core_durable_error.verbs+0x2b80>
 105dc20:	4c 89 ee             	mov    %r13,%rsi
 105dc23:	e8 d8 6a fc ff       	call   1024700 <myl_core_trap>
 105dc28:	48 8d 3d e1 37 02 00 	lea    0x237e1(%rip),%rdi        # 1081410 <core_durable_error.verbs+0x1e00>
 105dc2f:	48 89 c2             	mov    %rax,%rdx
 105dc32:	e8 c9 6a fc ff       	call   1024700 <myl_core_trap>
 105dc37:	48 8d 3d c2 38 02 00 	lea    0x238c2(%rip),%rdi        # 1081500 <core_durable_error.verbs+0x1ef0>
 105dc3e:	e8 bd 6a fc ff       	call   1024700 <myl_core_trap>
 105dc43:	48 8d 3d 66 3a 02 00 	lea    0x23a66(%rip),%rdi        # 10816b0 <core_durable_error.verbs+0x20a0>
 105dc4a:	e8 b1 6a fc ff       	call   1024700 <myl_core_trap>
 105dc4f:	48 8d 3d 5a 64 02 00 	lea    0x2645a(%rip),%rdi        # 10840b0 <core_durable_error.verbs+0x4aa0>
 105dc56:	48 89 c6             	mov    %rax,%rsi
 105dc59:	48 89 ca             	mov    %rcx,%rdx
 105dc5c:	e8 9f 6a fc ff       	call   1024700 <myl_core_trap>
 105dc61:	48 8d 3d 58 45 02 00 	lea    0x24558(%rip),%rdi        # 10821c0 <core_durable_error.verbs+0x2bb0>
 105dc68:	4c 89 ee             	mov    %r13,%rsi
 105dc6b:	e8 90 6a fc ff       	call   1024700 <myl_core_trap>
 105dc70:	48 8d 3d 59 3b 02 00 	lea    0x23b59(%rip),%rdi        # 10817d0 <core_durable_error.verbs+0x21c0>
 105dc77:	48 89 de             	mov    %rbx,%rsi
 105dc7a:	e8 81 6a fc ff       	call   1024700 <myl_core_trap>
 105dc7f:	48 8d 3d 0a 42 02 00 	lea    0x2420a(%rip),%rdi        # 1081e90 <core_durable_error.verbs+0x2880>
 105dc86:	48 89 c2             	mov    %rax,%rdx
 105dc89:	e8 72 6a fc ff       	call   1024700 <myl_core_trap>
 105dc8e:	48 8d 3d 5b 39 02 00 	lea    0x2395b(%rip),%rdi        # 10815f0 <core_durable_error.verbs+0x1fe0>
 105dc95:	48 89 de             	mov    %rbx,%rsi
 105dc98:	e8 63 6a fc ff       	call   1024700 <myl_core_trap>
 105dc9d:	48 8d 3d 5c 3b 02 00 	lea    0x23b5c(%rip),%rdi        # 1081800 <core_durable_error.verbs+0x21f0>
 105dca4:	48 89 de             	mov    %rbx,%rsi
 105dca7:	e8 54 6a fc ff       	call   1024700 <myl_core_trap>

Disassembly of section .plt:
