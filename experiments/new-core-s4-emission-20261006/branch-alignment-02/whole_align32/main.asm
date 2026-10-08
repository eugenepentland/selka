
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-emission/experiments/new-core-s4-emission-20261006/branch-alignment-02/whole_align32/program:     file format elf64-x86-64


Disassembly of section .text:

0000000001032ba0 <main>:
 1032ba0:	55                   	push   %rbp
 1032ba1:	41 57                	push   %r15
 1032ba3:	41 56                	push   %r14
 1032ba5:	41 55                	push   %r13
 1032ba7:	41 54                	push   %r12
 1032ba9:	53                   	push   %rbx
 1032baa:	48 83 ec 28          	sub    $0x28,%rsp
 1032bae:	e8 fd 69 fd ff       	call   10095b0 <myl_core_args>
 1032bb3:	48 89 c3             	mov    %rax,%rbx
 1032bb6:	e8 05 f4 fe ff       	call   1021fc0 <myl_core_host_grant>
 1032bbb:	41 be 02 00 00 00    	mov    $0x2,%r14d
 1032bc1:	48 83 7b 08 03       	cmpq   $0x3,0x8(%rbx)
 1032bc6:	0f 85 90 03 00 00    	jne    1032f5c <main+0x3bc>
 1032bcc:	49 89 c4             	mov    %rax,%r12
 1032bcf:	48 8b 7b 20          	mov    0x20(%rbx),%rdi
 1032bd3:	e8 a8 fd ff ff       	call   1032980 <my.row_result_propagate::parse_number>
 1032bd8:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032bdc:	0f 1f 40 00          	nopl   0x0(%rax)
 1032be0:	48 83 fa 01          	cmp    $0x1,%rdx
 1032be4:	0f 86 0d 04 00 00    	jbe    1032ff7 <main+0x457>
 1032bea:	49 89 c7             	mov    %rax,%r15
 1032bed:	48 8b 7b 28          	mov    0x28(%rbx),%rdi
 1032bf1:	e8 8a fd ff ff       	call   1032980 <my.row_result_propagate::parse_number>
 1032bf6:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032bfa:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1032c00:	48 83 fa 02          	cmp    $0x2,%rdx
 1032c04:	0f 86 fe 03 00 00    	jbe    1033008 <main+0x468>
 1032c0a:	48 89 c5             	mov    %rax,%rbp
 1032c0d:	48 8b 7b 30          	mov    0x30(%rbx),%rdi
 1032c11:	e8 6a fd ff ff       	call   1032980 <my.row_result_propagate::parse_number>
 1032c16:	49 83 ff 02          	cmp    $0x2,%r15
 1032c1a:	0f 9c c1             	setl   %cl
 1032c1d:	48 85 ed             	test   %rbp,%rbp
 1032c20:	0f 9e c2             	setle  %dl
 1032c23:	08 ca                	or     %cl,%dl
 1032c25:	48 8d 88 bf bd f0 ff 	lea    -0xf4241(%rax),%rcx
 1032c2c:	48 81 f9 c0 bd f0 ff 	cmp    $0xfffffffffff0bdc0,%rcx
 1032c33:	0f 92 c1             	setb   %cl
 1032c36:	08 d1                	or     %dl,%cl
 1032c38:	0f 85 1e 03 00 00    	jne    1032f5c <main+0x3bc>
 1032c3e:	49 81 ff 00 04 00 00 	cmp    $0x400,%r15
 1032c45:	48 89 5c 24 18       	mov    %rbx,0x18(%rsp)
 1032c4a:	4c 89 64 24 08       	mov    %r12,0x8(%rsp)
 1032c4f:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 1032c54:	0f 87 20 03 00 00    	ja     1032f7a <main+0x3da>
 1032c5a:	4a 8d 0c fd 3f 00 00 	lea    0x3f(,%r15,8),%rcx
 1032c61:	00 
 1032c62:	48 81 f9 1f 04 00 00 	cmp    $0x41f,%rcx
 1032c69:	0f 87 0b 03 00 00    	ja     1032f7a <main+0x3da>
 1032c6f:	48 89 ca             	mov    %rcx,%rdx
 1032c72:	48 c1 ea 05          	shr    $0x5,%rdx
 1032c76:	48 8d 35 d3 5a 02 00 	lea    0x25ad3(%rip),%rsi        # 1058750 <myl_core_free_lists>
 1032c7d:	4c 8b 2c d6          	mov    (%rsi,%rdx,8),%r13
 1032c81:	4d 85 ed             	test   %r13,%r13
 1032c84:	0f 84 f0 02 00 00    	je     1032f7a <main+0x3da>
 1032c8a:	49 8b 7d 00          	mov    0x0(%r13),%rdi
 1032c8e:	48 89 3c d6          	mov    %rdi,(%rsi,%rdx,8)
 1032c92:	41 c7 45 00 01 00 00 	movl   $0x1,0x0(%r13)
 1032c99:	00 
 1032c9a:	c1 e2 18             	shl    $0x18,%edx
 1032c9d:	41 89 55 04          	mov    %edx,0x4(%r13)
 1032ca1:	49 c7 45 08 00 00 00 	movq   $0x0,0x8(%r13)
 1032ca8:	00 
 1032ca9:	81 e1 e0 07 00 00    	and    $0x7e0,%ecx
 1032caf:	48 83 c1 e0          	add    $0xffffffffffffffe0,%rcx
 1032cb3:	48 c1 e9 03          	shr    $0x3,%rcx
 1032cb7:	49 89 4d 10          	mov    %rcx,0x10(%r13)
 1032cbb:	49 c7 45 18 00 00 00 	movq   $0x0,0x18(%r13)
 1032cc2:	00 
 1032cc3:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 1032cca:	9f 75 03 
 1032ccd:	45 31 f6             	xor    %r14d,%r14d
 1032cd0:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 1032cd7:	22 e7 81 
 1032cda:	31 ed                	xor    %ebp,%ebp
 1032cdc:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032ce3:	0f 1f 84 00 00 00 00 
 1032cea:	00 
 1032ceb:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cf2:	0f 1f 84 00 00 00 00 
 1032cf9:	00 
 1032cfa:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1032d00:	48 39 ee             	cmp    %rbp,%rsi
 1032d03:	0f 84 bc 02 00 00    	je     1032fc5 <main+0x425>
 1032d09:	48 89 c3             	mov    %rax,%rbx
 1032d0c:	4c 01 f3             	add    %r14,%rbx
 1032d0f:	0f 80 c1 02 00 00    	jo     1032fd6 <main+0x436>
 1032d15:	48 89 da             	mov    %rbx,%rdx
 1032d18:	c4 62 9b f6 e7       	mulx   %rdi,%r12,%r12
 1032d1d:	49 8b 4d 08          	mov    0x8(%r13),%rcx
 1032d21:	49 3b 4d 10          	cmp    0x10(%r13),%rcx
 1032d25:	73 28                	jae    1032d4f <main+0x1af>
 1032d27:	49 c1 ec 09          	shr    $0x9,%r12
 1032d2b:	49 69 d4 f1 03 00 00 	imul   $0x3f1,%r12,%rdx
 1032d32:	48 29 d3             	sub    %rdx,%rbx
 1032d35:	49 89 5c cd 20       	mov    %rbx,0x20(%r13,%rcx,8)
 1032d3a:	48 ff c1             	inc    %rcx
 1032d3d:	49 89 4d 08          	mov    %rcx,0x8(%r13)
 1032d41:	48 ff c5             	inc    %rbp
 1032d44:	49 83 c6 25          	add    $0x25,%r14
 1032d48:	49 39 ef             	cmp    %rbp,%r15
 1032d4b:	75 b3                	jne    1032d00 <main+0x160>
 1032d4d:	eb 34                	jmp    1032d83 <main+0x1e3>
 1032d4f:	be 08 00 00 00       	mov    $0x8,%esi
 1032d54:	4c 89 ef             	mov    %r13,%rdi
 1032d57:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 1032d5c:	e8 4f 63 fd ff       	call   10090b0 <myl_core_list_grow>
 1032d61:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 1032d68:	22 e7 81 
 1032d6b:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 1032d72:	9f 75 03 
 1032d75:	49 89 c5             	mov    %rax,%r13
 1032d78:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 1032d7d:	49 8b 4d 08          	mov    0x8(%r13),%rcx
 1032d81:	eb a4                	jmp    1032d27 <main+0x187>
 1032d83:	48 8d 3d c6 18 00 00 	lea    0x18c6(%rip),%rdi        # 1034650 <core_io_file_error.verbs+0x110>
 1032d8a:	e8 f1 72 fd ff       	call   100a080 <myl_core_io_at>
 1032d8f:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1032d94:	e8 57 f2 fe ff       	call   1021ff0 <myl_core_host_check>
 1032d99:	31 ed                	xor    %ebp,%ebp
 1032d9b:	e8 a0 02 00 00       	call   1033040 <runtime_bench_now>
 1032da0:	49 89 c4             	mov    %rax,%r12
 1032da3:	48 8d 0d f6 19 00 00 	lea    0x19f6(%rip),%rcx        # 10347a0 <core_io_file_error.verbs+0x260>
 1032daa:	4c 8d 0d bf 19 00 00 	lea    0x19bf(%rip),%r9        # 1034770 <core_io_file_error.verbs+0x230>
 1032db1:	31 db                	xor    %ebx,%ebx
 1032db3:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032dba:	84 00 00 00 00 00 
 1032dc0:	48 89 da             	mov    %rbx,%rdx
 1032dc3:	48 b8 f1 f0 f0 f0 f0 	movabs $0xf0f0f0f0f0f0f0f1,%rax
 1032dca:	f0 f0 f0 
 1032dcd:	c4 e2 fb f6 c0       	mulx   %rax,%rax,%rax
 1032dd2:	48 89 c2             	mov    %rax,%rdx
 1032dd5:	48 83 e2 f0          	and    $0xfffffffffffffff0,%rdx
 1032dd9:	48 c1 e8 04          	shr    $0x4,%rax
 1032ddd:	48 01 d0             	add    %rdx,%rax
 1032de0:	49 89 d8             	mov    %rbx,%r8
 1032de3:	49 29 c0             	sub    %rax,%r8
 1032de6:	31 f6                	xor    %esi,%esi
 1032de8:	45 31 f6             	xor    %r14d,%r14d
 1032deb:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032df2:	0f 1f 84 00 00 00 00 
 1032df9:	00 
 1032dfa:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1032e00:	4b 8b 44 f5 20       	mov    0x20(%r13,%r14,8),%rax
 1032e05:	69 d0 cd cc ff ff    	imul   $0xffffcccd,%eax,%edx
 1032e0b:	0f b7 d2             	movzwl %dx,%edx
 1032e0e:	81 fa 33 33 00 00    	cmp    $0x3333,%edx
 1032e14:	76 31                	jbe    1032e47 <main+0x2a7>
 1032e16:	4c 01 c0             	add    %r8,%rax
 1032e19:	31 d2                	xor    %edx,%edx
 1032e1b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1032e20:	80 fa 01             	cmp    $0x1,%dl
 1032e23:	74 36                	je     1032e5b <main+0x2bb>
 1032e25:	4c 8d 14 40          	lea    (%rax,%rax,2),%r10
 1032e29:	49 ff c2             	inc    %r10
 1032e2c:	48 89 f2             	mov    %rsi,%rdx
 1032e2f:	4c 01 d2             	add    %r10,%rdx
 1032e32:	0f 80 5d 01 00 00    	jo     1032f95 <main+0x3f5>
 1032e38:	49 ff c6             	inc    %r14
 1032e3b:	48 89 d6             	mov    %rdx,%rsi
 1032e3e:	66 90                	xchg   %ax,%ax
 1032e40:	4d 39 f7             	cmp    %r14,%r15
 1032e43:	75 bb                	jne    1032e00 <main+0x260>
 1032e45:	eb 29                	jmp    1032e70 <main+0x2d0>
 1032e47:	48 89 cf             	mov    %rcx,%rdi
 1032e4a:	e8 e3 f8 ff ff       	call   1032732 <myl_core_err_trace_origin_preserve_most>
 1032e4f:	b8 01 00 00 00       	mov    $0x1,%eax
 1032e54:	b2 01                	mov    $0x1,%dl
 1032e56:	80 fa 01             	cmp    $0x1,%dl
 1032e59:	75 ca                	jne    1032e25 <main+0x285>
 1032e5b:	4c 89 cf             	mov    %r9,%rdi
 1032e5e:	e8 e7 f8 ff ff       	call   103274a <myl_core_err_trace_append_preserve_most>
 1032e63:	4c 6b d0 07          	imul   $0x7,%rax,%r10
 1032e67:	71 c3                	jno    1032e2c <main+0x28c>
 1032e69:	e9 43 01 00 00       	jmp    1032fb1 <main+0x411>
 1032e6e:	66 90                	xchg   %ax,%ax
 1032e70:	48 89 d6             	mov    %rdx,%rsi
 1032e73:	48 01 ee             	add    %rbp,%rsi
 1032e76:	0f 80 6c 01 00 00    	jo     1032fe8 <main+0x448>
 1032e7c:	48 89 f0             	mov    %rsi,%rax
 1032e7f:	48 ba e5 8f a2 12 31 	movabs $0x89705f3112a28fe5,%rdx
 1032e86:	5f 70 89 
 1032e89:	48 f7 ea             	imul   %rdx
 1032e8c:	48 01 f2             	add    %rsi,%rdx
 1032e8f:	48 89 d0             	mov    %rdx,%rax
 1032e92:	48 c1 e8 3f          	shr    $0x3f,%rax
 1032e96:	48 c1 fa 1d          	sar    $0x1d,%rdx
 1032e9a:	48 01 c2             	add    %rax,%rdx
 1032e9d:	48 69 c2 07 ca 9a 3b 	imul   $0x3b9aca07,%rdx,%rax
 1032ea4:	48 29 c6             	sub    %rax,%rsi
 1032ea7:	48 89 f5             	mov    %rsi,%rbp
 1032eaa:	48 c1 fd 3f          	sar    $0x3f,%rbp
 1032eae:	81 e5 07 ca 9a 3b    	and    $0x3b9aca07,%ebp
 1032eb4:	48 01 f5             	add    %rsi,%rbp
 1032eb7:	48 ff c3             	inc    %rbx
 1032eba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1032ec0:	48 3b 5c 24 20       	cmp    0x20(%rsp),%rbx
 1032ec5:	0f 85 f5 fe ff ff    	jne    1032dc0 <main+0x220>
 1032ecb:	41 0f b6 45 07       	movzbl 0x7(%r13),%eax
 1032ed0:	48 85 c0             	test   %rax,%rax
 1032ed3:	0f 84 cb 00 00 00    	je     1032fa4 <main+0x404>
 1032ed9:	49 83 7d 18 00       	cmpq   $0x0,0x18(%r13)
 1032ede:	66 90                	xchg   %ax,%ax
 1032ee0:	0f 85 be 00 00 00    	jne    1032fa4 <main+0x404>
 1032ee6:	48 8d 0d 63 58 02 00 	lea    0x25863(%rip),%rcx        # 1058750 <myl_core_free_lists>
 1032eed:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1032ef1:	49 89 55 00          	mov    %rdx,0x0(%r13)
 1032ef5:	4c 89 2c c1          	mov    %r13,(%rcx,%rax,8)
 1032ef9:	48 8d 3d 80 17 00 00 	lea    0x1780(%rip),%rdi        # 1034680 <core_io_file_error.verbs+0x140>
 1032f00:	e8 7b 71 fd ff       	call   100a080 <myl_core_io_at>
 1032f05:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1032f0a:	e8 e1 f0 fe ff       	call   1021ff0 <myl_core_host_check>
 1032f0f:	e8 2c 01 00 00       	call   1033040 <runtime_bench_now>
 1032f14:	48 89 c3             	mov    %rax,%rbx
 1032f17:	4c 29 e3             	sub    %r12,%rbx
 1032f1a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1032f20:	0f 80 f3 00 00 00    	jo     1033019 <main+0x479>
 1032f26:	bf 01 00 00 00       	mov    $0x1,%edi
 1032f2b:	48 89 ee             	mov    %rbp,%rsi
 1032f2e:	e8 4d 78 fd ff       	call   100a780 <myl_core_print_i64>
 1032f33:	bf 01 00 00 00       	mov    $0x1,%edi
 1032f38:	e8 83 5e fd ff       	call   1008dc0 <myl_core_print_sep>
 1032f3d:	bf 01 00 00 00       	mov    $0x1,%edi
 1032f42:	48 89 de             	mov    %rbx,%rsi
 1032f45:	e8 36 78 fd ff       	call   100a780 <myl_core_print_i64>
 1032f4a:	bf 01 00 00 00       	mov    $0x1,%edi
 1032f4f:	e8 2c 5f fd ff       	call   1008e80 <myl_core_print_end>
 1032f54:	45 31 f6             	xor    %r14d,%r14d
 1032f57:	48 8b 5c 24 18       	mov    0x18(%rsp),%rbx
 1032f5c:	48 89 df             	mov    %rbx,%rdi
 1032f5f:	e8 1c 66 fd ff       	call   1009580 <myl_core_release>
 1032f64:	4c 89 f7             	mov    %r14,%rdi
 1032f67:	48 83 c4 28          	add    $0x28,%rsp
 1032f6b:	5b                   	pop    %rbx
 1032f6c:	41 5c                	pop    %r12
 1032f6e:	41 5d                	pop    %r13
 1032f70:	41 5e                	pop    %r14
 1032f72:	41 5f                	pop    %r15
 1032f74:	5d                   	pop    %rbp
 1032f75:	e9 16 71 fd ff       	jmp    100a090 <myl_core_exit>
 1032f7a:	be 08 00 00 00       	mov    $0x8,%esi
 1032f7f:	4c 89 ff             	mov    %r15,%rdi
 1032f82:	48 89 c3             	mov    %rax,%rbx
 1032f85:	e8 b6 60 fd ff       	call   1009040 <myl_core_list_new_slow>
 1032f8a:	49 89 c5             	mov    %rax,%r13
 1032f8d:	48 89 d8             	mov    %rbx,%rax
 1032f90:	e9 2e fd ff ff       	jmp    1032cc3 <main+0x123>
 1032f95:	48 8d 3d 74 17 00 00 	lea    0x1774(%rip),%rdi        # 1034710 <core_io_file_error.verbs+0x1d0>
 1032f9c:	4c 89 d2             	mov    %r10,%rdx
 1032f9f:	e8 9c 67 fd ff       	call   1009740 <myl_core_trap>
 1032fa4:	4c 89 ef             	mov    %r13,%rdi
 1032fa7:	e8 a4 f3 ff ff       	call   1032350 <myl_core_free_block>
 1032fac:	e9 48 ff ff ff       	jmp    1032ef9 <main+0x359>
 1032fb1:	48 8d 3d 88 17 00 00 	lea    0x1788(%rip),%rdi        # 1034740 <core_io_file_error.verbs+0x200>
 1032fb8:	ba 07 00 00 00       	mov    $0x7,%edx
 1032fbd:	48 89 c6             	mov    %rax,%rsi
 1032fc0:	e8 7b 67 fd ff       	call   1009740 <myl_core_trap>
 1032fc5:	48 8d 3d 24 16 00 00 	lea    0x1624(%rip),%rdi        # 10345f0 <core_io_file_error.verbs+0xb0>
 1032fcc:	ba 25 00 00 00       	mov    $0x25,%edx
 1032fd1:	e8 6a 67 fd ff       	call   1009740 <myl_core_trap>
 1032fd6:	48 8d 3d 43 16 00 00 	lea    0x1643(%rip),%rdi        # 1034620 <core_io_file_error.verbs+0xe0>
 1032fdd:	48 89 c6             	mov    %rax,%rsi
 1032fe0:	4c 89 f2             	mov    %r14,%rdx
 1032fe3:	e8 58 67 fd ff       	call   1009740 <myl_core_trap>
 1032fe8:	48 8d 3d f1 16 00 00 	lea    0x16f1(%rip),%rdi        # 10346e0 <core_io_file_error.verbs+0x1a0>
 1032fef:	48 89 ee             	mov    %rbp,%rsi
 1032ff2:	e8 49 67 fd ff       	call   1009740 <myl_core_trap>
 1032ff7:	48 8d 3d 92 15 00 00 	lea    0x1592(%rip),%rdi        # 1034590 <core_io_file_error.verbs+0x50>
 1032ffe:	be 01 00 00 00       	mov    $0x1,%esi
 1033003:	e8 38 67 fd ff       	call   1009740 <myl_core_trap>
 1033008:	48 8d 3d b1 15 00 00 	lea    0x15b1(%rip),%rdi        # 10345c0 <core_io_file_error.verbs+0x80>
 103300f:	be 02 00 00 00       	mov    $0x2,%esi
 1033014:	e8 27 67 fd ff       	call   1009740 <myl_core_trap>
 1033019:	48 8d 3d 90 16 00 00 	lea    0x1690(%rip),%rdi        # 10346b0 <core_io_file_error.verbs+0x170>
 1033020:	48 89 c6             	mov    %rax,%rsi
 1033023:	4c 89 e2             	mov    %r12,%rdx
 1033026:	e8 15 67 fd ff       	call   1009740 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
