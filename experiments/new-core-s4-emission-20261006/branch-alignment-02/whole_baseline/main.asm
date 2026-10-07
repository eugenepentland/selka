
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-emission/experiments/new-core-s4-emission-20261006/branch-alignment-02/whole_baseline/program:     file format elf64-x86-64


Disassembly of section .text:

0000000001032b80 <main>:
 1032b80:	55                   	push   %rbp
 1032b81:	41 57                	push   %r15
 1032b83:	41 56                	push   %r14
 1032b85:	41 55                	push   %r13
 1032b87:	41 54                	push   %r12
 1032b89:	53                   	push   %rbx
 1032b8a:	48 83 ec 28          	sub    $0x28,%rsp
 1032b8e:	e8 1d 6a fd ff       	call   10095b0 <myl_core_args>
 1032b93:	48 89 c3             	mov    %rax,%rbx
 1032b96:	e8 25 f4 fe ff       	call   1021fc0 <myl_core_host_grant>
 1032b9b:	41 be 02 00 00 00    	mov    $0x2,%r14d
 1032ba1:	48 83 7b 08 03       	cmpq   $0x3,0x8(%rbx)
 1032ba6:	0f 85 62 03 00 00    	jne    1032f0e <main+0x38e>
 1032bac:	49 89 c4             	mov    %rax,%r12
 1032baf:	48 8b 7b 20          	mov    0x20(%rbx),%rdi
 1032bb3:	e8 c8 fd ff ff       	call   1032980 <my.row_result_propagate::parse_number>
 1032bb8:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032bbc:	48 83 fa 01          	cmp    $0x1,%rdx
 1032bc0:	0f 86 e3 03 00 00    	jbe    1032fa9 <main+0x429>
 1032bc6:	49 89 c7             	mov    %rax,%r15
 1032bc9:	48 8b 7b 28          	mov    0x28(%rbx),%rdi
 1032bcd:	e8 ae fd ff ff       	call   1032980 <my.row_result_propagate::parse_number>
 1032bd2:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032bd6:	48 83 fa 02          	cmp    $0x2,%rdx
 1032bda:	0f 86 da 03 00 00    	jbe    1032fba <main+0x43a>
 1032be0:	48 89 c5             	mov    %rax,%rbp
 1032be3:	48 8b 7b 30          	mov    0x30(%rbx),%rdi
 1032be7:	e8 94 fd ff ff       	call   1032980 <my.row_result_propagate::parse_number>
 1032bec:	49 83 ff 02          	cmp    $0x2,%r15
 1032bf0:	0f 9c c1             	setl   %cl
 1032bf3:	48 85 ed             	test   %rbp,%rbp
 1032bf6:	0f 9e c2             	setle  %dl
 1032bf9:	08 ca                	or     %cl,%dl
 1032bfb:	48 8d 88 bf bd f0 ff 	lea    -0xf4241(%rax),%rcx
 1032c02:	48 81 f9 c0 bd f0 ff 	cmp    $0xfffffffffff0bdc0,%rcx
 1032c09:	0f 92 c1             	setb   %cl
 1032c0c:	08 d1                	or     %dl,%cl
 1032c0e:	0f 85 fa 02 00 00    	jne    1032f0e <main+0x38e>
 1032c14:	49 81 ff 00 04 00 00 	cmp    $0x400,%r15
 1032c1b:	48 89 5c 24 18       	mov    %rbx,0x18(%rsp)
 1032c20:	4c 89 64 24 08       	mov    %r12,0x8(%rsp)
 1032c25:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 1032c2a:	0f 87 fc 02 00 00    	ja     1032f2c <main+0x3ac>
 1032c30:	4a 8d 0c fd 3f 00 00 	lea    0x3f(,%r15,8),%rcx
 1032c37:	00 
 1032c38:	48 81 f9 1f 04 00 00 	cmp    $0x41f,%rcx
 1032c3f:	0f 87 e7 02 00 00    	ja     1032f2c <main+0x3ac>
 1032c45:	48 89 ca             	mov    %rcx,%rdx
 1032c48:	48 c1 ea 05          	shr    $0x5,%rdx
 1032c4c:	48 8d 35 9d 5a 02 00 	lea    0x25a9d(%rip),%rsi        # 10586f0 <myl_core_free_lists>
 1032c53:	4c 8b 2c d6          	mov    (%rsi,%rdx,8),%r13
 1032c57:	4d 85 ed             	test   %r13,%r13
 1032c5a:	0f 84 cc 02 00 00    	je     1032f2c <main+0x3ac>
 1032c60:	49 8b 7d 00          	mov    0x0(%r13),%rdi
 1032c64:	48 89 3c d6          	mov    %rdi,(%rsi,%rdx,8)
 1032c68:	41 c7 45 00 01 00 00 	movl   $0x1,0x0(%r13)
 1032c6f:	00 
 1032c70:	c1 e2 18             	shl    $0x18,%edx
 1032c73:	41 89 55 04          	mov    %edx,0x4(%r13)
 1032c77:	49 c7 45 08 00 00 00 	movq   $0x0,0x8(%r13)
 1032c7e:	00 
 1032c7f:	81 e1 e0 07 00 00    	and    $0x7e0,%ecx
 1032c85:	48 83 c1 e0          	add    $0xffffffffffffffe0,%rcx
 1032c89:	48 c1 e9 03          	shr    $0x3,%rcx
 1032c8d:	49 89 4d 10          	mov    %rcx,0x10(%r13)
 1032c91:	49 c7 45 18 00 00 00 	movq   $0x0,0x18(%r13)
 1032c98:	00 
 1032c99:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 1032ca0:	9f 75 03 
 1032ca3:	45 31 f6             	xor    %r14d,%r14d
 1032ca6:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 1032cad:	22 e7 81 
 1032cb0:	31 ed                	xor    %ebp,%ebp
 1032cb2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cb9:	1f 84 00 00 00 00 00 
 1032cc0:	48 39 ee             	cmp    %rbp,%rsi
 1032cc3:	0f 84 ae 02 00 00    	je     1032f77 <main+0x3f7>
 1032cc9:	48 89 c3             	mov    %rax,%rbx
 1032ccc:	4c 01 f3             	add    %r14,%rbx
 1032ccf:	0f 80 b3 02 00 00    	jo     1032f88 <main+0x408>
 1032cd5:	48 89 da             	mov    %rbx,%rdx
 1032cd8:	c4 62 9b f6 e7       	mulx   %rdi,%r12,%r12
 1032cdd:	49 8b 4d 08          	mov    0x8(%r13),%rcx
 1032ce1:	49 3b 4d 10          	cmp    0x10(%r13),%rcx
 1032ce5:	73 28                	jae    1032d0f <main+0x18f>
 1032ce7:	49 c1 ec 09          	shr    $0x9,%r12
 1032ceb:	49 69 d4 f1 03 00 00 	imul   $0x3f1,%r12,%rdx
 1032cf2:	48 29 d3             	sub    %rdx,%rbx
 1032cf5:	49 89 5c cd 20       	mov    %rbx,0x20(%r13,%rcx,8)
 1032cfa:	48 ff c1             	inc    %rcx
 1032cfd:	49 89 4d 08          	mov    %rcx,0x8(%r13)
 1032d01:	48 ff c5             	inc    %rbp
 1032d04:	49 83 c6 25          	add    $0x25,%r14
 1032d08:	49 39 ef             	cmp    %rbp,%r15
 1032d0b:	75 b3                	jne    1032cc0 <main+0x140>
 1032d0d:	eb 34                	jmp    1032d43 <main+0x1c3>
 1032d0f:	be 08 00 00 00       	mov    $0x8,%esi
 1032d14:	4c 89 ef             	mov    %r13,%rdi
 1032d17:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 1032d1c:	e8 8f 63 fd ff       	call   10090b0 <myl_core_list_grow>
 1032d21:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 1032d28:	22 e7 81 
 1032d2b:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 1032d32:	9f 75 03 
 1032d35:	49 89 c5             	mov    %rax,%r13
 1032d38:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 1032d3d:	49 8b 4d 08          	mov    0x8(%r13),%rcx
 1032d41:	eb a4                	jmp    1032ce7 <main+0x167>
 1032d43:	48 8d 3d a6 18 00 00 	lea    0x18a6(%rip),%rdi        # 10345f0 <core_io_file_error.verbs+0x110>
 1032d4a:	e8 31 73 fd ff       	call   100a080 <myl_core_io_at>
 1032d4f:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1032d54:	e8 97 f2 fe ff       	call   1021ff0 <myl_core_host_check>
 1032d59:	31 ed                	xor    %ebp,%ebp
 1032d5b:	e8 80 02 00 00       	call   1032fe0 <runtime_bench_now>
 1032d60:	49 89 c4             	mov    %rax,%r12
 1032d63:	48 8d 0d d6 19 00 00 	lea    0x19d6(%rip),%rcx        # 1034740 <core_io_file_error.verbs+0x260>
 1032d6a:	4c 8d 0d 9f 19 00 00 	lea    0x199f(%rip),%r9        # 1034710 <core_io_file_error.verbs+0x230>
 1032d71:	31 db                	xor    %ebx,%ebx
 1032d73:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032d7a:	84 00 00 00 00 00 
 1032d80:	48 89 da             	mov    %rbx,%rdx
 1032d83:	48 b8 f1 f0 f0 f0 f0 	movabs $0xf0f0f0f0f0f0f0f1,%rax
 1032d8a:	f0 f0 f0 
 1032d8d:	c4 e2 fb f6 c0       	mulx   %rax,%rax,%rax
 1032d92:	48 89 c2             	mov    %rax,%rdx
 1032d95:	48 83 e2 f0          	and    $0xfffffffffffffff0,%rdx
 1032d99:	48 c1 e8 04          	shr    $0x4,%rax
 1032d9d:	48 01 d0             	add    %rdx,%rax
 1032da0:	49 89 d8             	mov    %rbx,%r8
 1032da3:	49 29 c0             	sub    %rax,%r8
 1032da6:	31 f6                	xor    %esi,%esi
 1032da8:	45 31 f6             	xor    %r14d,%r14d
 1032dab:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032db2:	0f 1f 84 00 00 00 00 
 1032db9:	00 
 1032dba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1032dc0:	4b 8b 44 f5 20       	mov    0x20(%r13,%r14,8),%rax
 1032dc5:	69 d0 cd cc ff ff    	imul   $0xffffcccd,%eax,%edx
 1032dcb:	0f b7 d2             	movzwl %dx,%edx
 1032dce:	81 fa 33 33 00 00    	cmp    $0x3333,%edx
 1032dd4:	76 2a                	jbe    1032e00 <main+0x280>
 1032dd6:	4c 01 c0             	add    %r8,%rax
 1032dd9:	31 d2                	xor    %edx,%edx
 1032ddb:	80 fa 01             	cmp    $0x1,%dl
 1032dde:	74 34                	je     1032e14 <main+0x294>
 1032de0:	4c 8d 14 40          	lea    (%rax,%rax,2),%r10
 1032de4:	49 ff c2             	inc    %r10
 1032de7:	48 89 f2             	mov    %rsi,%rdx
 1032dea:	4c 01 d2             	add    %r10,%rdx
 1032ded:	0f 80 54 01 00 00    	jo     1032f47 <main+0x3c7>
 1032df3:	49 ff c6             	inc    %r14
 1032df6:	48 89 d6             	mov    %rdx,%rsi
 1032df9:	4d 39 f7             	cmp    %r14,%r15
 1032dfc:	75 c2                	jne    1032dc0 <main+0x240>
 1032dfe:	eb 30                	jmp    1032e30 <main+0x2b0>
 1032e00:	48 89 cf             	mov    %rcx,%rdi
 1032e03:	e8 2a f9 ff ff       	call   1032732 <myl_core_err_trace_origin_preserve_most>
 1032e08:	b8 01 00 00 00       	mov    $0x1,%eax
 1032e0d:	b2 01                	mov    $0x1,%dl
 1032e0f:	80 fa 01             	cmp    $0x1,%dl
 1032e12:	75 cc                	jne    1032de0 <main+0x260>
 1032e14:	4c 89 cf             	mov    %r9,%rdi
 1032e17:	e8 2e f9 ff ff       	call   103274a <myl_core_err_trace_append_preserve_most>
 1032e1c:	4c 6b d0 07          	imul   $0x7,%rax,%r10
 1032e20:	71 c5                	jno    1032de7 <main+0x267>
 1032e22:	e9 3c 01 00 00       	jmp    1032f63 <main+0x3e3>
 1032e27:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1032e2e:	00 00 
 1032e30:	48 89 d6             	mov    %rdx,%rsi
 1032e33:	48 01 ee             	add    %rbp,%rsi
 1032e36:	0f 80 5e 01 00 00    	jo     1032f9a <main+0x41a>
 1032e3c:	48 89 f0             	mov    %rsi,%rax
 1032e3f:	48 ba e5 8f a2 12 31 	movabs $0x89705f3112a28fe5,%rdx
 1032e46:	5f 70 89 
 1032e49:	48 f7 ea             	imul   %rdx
 1032e4c:	48 01 f2             	add    %rsi,%rdx
 1032e4f:	48 89 d0             	mov    %rdx,%rax
 1032e52:	48 c1 e8 3f          	shr    $0x3f,%rax
 1032e56:	48 c1 fa 1d          	sar    $0x1d,%rdx
 1032e5a:	48 01 c2             	add    %rax,%rdx
 1032e5d:	48 69 c2 07 ca 9a 3b 	imul   $0x3b9aca07,%rdx,%rax
 1032e64:	48 29 c6             	sub    %rax,%rsi
 1032e67:	48 89 f5             	mov    %rsi,%rbp
 1032e6a:	48 c1 fd 3f          	sar    $0x3f,%rbp
 1032e6e:	81 e5 07 ca 9a 3b    	and    $0x3b9aca07,%ebp
 1032e74:	48 01 f5             	add    %rsi,%rbp
 1032e77:	48 ff c3             	inc    %rbx
 1032e7a:	48 3b 5c 24 20       	cmp    0x20(%rsp),%rbx
 1032e7f:	0f 85 fb fe ff ff    	jne    1032d80 <main+0x200>
 1032e85:	41 0f b6 45 07       	movzbl 0x7(%r13),%eax
 1032e8a:	48 85 c0             	test   %rax,%rax
 1032e8d:	0f 84 c3 00 00 00    	je     1032f56 <main+0x3d6>
 1032e93:	49 83 7d 18 00       	cmpq   $0x0,0x18(%r13)
 1032e98:	0f 85 b8 00 00 00    	jne    1032f56 <main+0x3d6>
 1032e9e:	48 8d 0d 4b 58 02 00 	lea    0x2584b(%rip),%rcx        # 10586f0 <myl_core_free_lists>
 1032ea5:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1032ea9:	49 89 55 00          	mov    %rdx,0x0(%r13)
 1032ead:	4c 89 2c c1          	mov    %r13,(%rcx,%rax,8)
 1032eb1:	48 8d 3d 68 17 00 00 	lea    0x1768(%rip),%rdi        # 1034620 <core_io_file_error.verbs+0x140>
 1032eb8:	e8 c3 71 fd ff       	call   100a080 <myl_core_io_at>
 1032ebd:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1032ec2:	e8 29 f1 fe ff       	call   1021ff0 <myl_core_host_check>
 1032ec7:	e8 14 01 00 00       	call   1032fe0 <runtime_bench_now>
 1032ecc:	48 89 c3             	mov    %rax,%rbx
 1032ecf:	4c 29 e3             	sub    %r12,%rbx
 1032ed2:	0f 80 f3 00 00 00    	jo     1032fcb <main+0x44b>
 1032ed8:	bf 01 00 00 00       	mov    $0x1,%edi
 1032edd:	48 89 ee             	mov    %rbp,%rsi
 1032ee0:	e8 9b 78 fd ff       	call   100a780 <myl_core_print_i64>
 1032ee5:	bf 01 00 00 00       	mov    $0x1,%edi
 1032eea:	e8 d1 5e fd ff       	call   1008dc0 <myl_core_print_sep>
 1032eef:	bf 01 00 00 00       	mov    $0x1,%edi
 1032ef4:	48 89 de             	mov    %rbx,%rsi
 1032ef7:	e8 84 78 fd ff       	call   100a780 <myl_core_print_i64>
 1032efc:	bf 01 00 00 00       	mov    $0x1,%edi
 1032f01:	e8 7a 5f fd ff       	call   1008e80 <myl_core_print_end>
 1032f06:	45 31 f6             	xor    %r14d,%r14d
 1032f09:	48 8b 5c 24 18       	mov    0x18(%rsp),%rbx
 1032f0e:	48 89 df             	mov    %rbx,%rdi
 1032f11:	e8 6a 66 fd ff       	call   1009580 <myl_core_release>
 1032f16:	4c 89 f7             	mov    %r14,%rdi
 1032f19:	48 83 c4 28          	add    $0x28,%rsp
 1032f1d:	5b                   	pop    %rbx
 1032f1e:	41 5c                	pop    %r12
 1032f20:	41 5d                	pop    %r13
 1032f22:	41 5e                	pop    %r14
 1032f24:	41 5f                	pop    %r15
 1032f26:	5d                   	pop    %rbp
 1032f27:	e9 64 71 fd ff       	jmp    100a090 <myl_core_exit>
 1032f2c:	be 08 00 00 00       	mov    $0x8,%esi
 1032f31:	4c 89 ff             	mov    %r15,%rdi
 1032f34:	48 89 c3             	mov    %rax,%rbx
 1032f37:	e8 04 61 fd ff       	call   1009040 <myl_core_list_new_slow>
 1032f3c:	49 89 c5             	mov    %rax,%r13
 1032f3f:	48 89 d8             	mov    %rbx,%rax
 1032f42:	e9 52 fd ff ff       	jmp    1032c99 <main+0x119>
 1032f47:	48 8d 3d 62 17 00 00 	lea    0x1762(%rip),%rdi        # 10346b0 <core_io_file_error.verbs+0x1d0>
 1032f4e:	4c 89 d2             	mov    %r10,%rdx
 1032f51:	e8 ea 67 fd ff       	call   1009740 <myl_core_trap>
 1032f56:	4c 89 ef             	mov    %r13,%rdi
 1032f59:	e8 f2 f3 ff ff       	call   1032350 <myl_core_free_block>
 1032f5e:	e9 4e ff ff ff       	jmp    1032eb1 <main+0x331>
 1032f63:	48 8d 3d 76 17 00 00 	lea    0x1776(%rip),%rdi        # 10346e0 <core_io_file_error.verbs+0x200>
 1032f6a:	ba 07 00 00 00       	mov    $0x7,%edx
 1032f6f:	48 89 c6             	mov    %rax,%rsi
 1032f72:	e8 c9 67 fd ff       	call   1009740 <myl_core_trap>
 1032f77:	48 8d 3d 12 16 00 00 	lea    0x1612(%rip),%rdi        # 1034590 <core_io_file_error.verbs+0xb0>
 1032f7e:	ba 25 00 00 00       	mov    $0x25,%edx
 1032f83:	e8 b8 67 fd ff       	call   1009740 <myl_core_trap>
 1032f88:	48 8d 3d 31 16 00 00 	lea    0x1631(%rip),%rdi        # 10345c0 <core_io_file_error.verbs+0xe0>
 1032f8f:	48 89 c6             	mov    %rax,%rsi
 1032f92:	4c 89 f2             	mov    %r14,%rdx
 1032f95:	e8 a6 67 fd ff       	call   1009740 <myl_core_trap>
 1032f9a:	48 8d 3d df 16 00 00 	lea    0x16df(%rip),%rdi        # 1034680 <core_io_file_error.verbs+0x1a0>
 1032fa1:	48 89 ee             	mov    %rbp,%rsi
 1032fa4:	e8 97 67 fd ff       	call   1009740 <myl_core_trap>
 1032fa9:	48 8d 3d 80 15 00 00 	lea    0x1580(%rip),%rdi        # 1034530 <core_io_file_error.verbs+0x50>
 1032fb0:	be 01 00 00 00       	mov    $0x1,%esi
 1032fb5:	e8 86 67 fd ff       	call   1009740 <myl_core_trap>
 1032fba:	48 8d 3d 9f 15 00 00 	lea    0x159f(%rip),%rdi        # 1034560 <core_io_file_error.verbs+0x80>
 1032fc1:	be 02 00 00 00       	mov    $0x2,%esi
 1032fc6:	e8 75 67 fd ff       	call   1009740 <myl_core_trap>
 1032fcb:	48 8d 3d 7e 16 00 00 	lea    0x167e(%rip),%rdi        # 1034650 <core_io_file_error.verbs+0x170>
 1032fd2:	48 89 c6             	mov    %rax,%rsi
 1032fd5:	4c 89 e2             	mov    %r12,%rdx
 1032fd8:	e8 63 67 fd ff       	call   1009740 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
