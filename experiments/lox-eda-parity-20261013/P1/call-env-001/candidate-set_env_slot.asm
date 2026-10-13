
.tmp/lox-eda-parity/P1/call-env-001/candidate-lox:     file format elf64-x86-64


Disassembly of section .text:

000000000106c740 <my.heap::set_env_slot>:
 106c740:	41 56                	push   %r14
 106c742:	53                   	push   %rbx
 106c743:	50                   	push   %rax
 106c744:	48 85 f6             	test   %rsi,%rsi
 106c747:	0f 88 f7 00 00 00    	js     106c844 <my.heap::set_env_slot+0x104>
 106c74d:	48 8b 07             	mov    (%rdi),%rax
 106c750:	48 3b 70 08          	cmp    0x8(%rax),%rsi
 106c754:	0f 8d ea 00 00 00    	jge    106c844 <my.heap::set_env_slot+0x104>
 106c75a:	48 6b f6 38          	imul   $0x38,%rsi,%rsi
 106c75e:	83 7c 30 20 09       	cmpl   $0x9,0x20(%rax,%rsi,1)
 106c763:	0f 85 e7 00 00 00    	jne    106c850 <my.heap::set_env_slot+0x110>
 106c769:	48 01 c6             	add    %rax,%rsi
 106c76c:	48 83 c6 20          	add    $0x20,%rsi
 106c770:	4c 8b 4e 10          	mov    0x10(%rsi),%r9
 106c774:	49 8b 41 08          	mov    0x8(%r9),%rax
 106c778:	48 89 c7             	mov    %rax,%rdi
 106c77b:	48 f7 df             	neg    %rdi
 106c77e:	48 39 fa             	cmp    %rdi,%rdx
 106c781:	0f 8c d5 00 00 00    	jl     106c85c <my.heap::set_env_slot+0x11c>
 106c787:	48 39 c2             	cmp    %rax,%rdx
 106c78a:	0f 8d cc 00 00 00    	jge    106c85c <my.heap::set_env_slot+0x11c>
 106c790:	4c 8b 56 08          	mov    0x8(%rsi),%r10
 106c794:	48 c7 06 00 00 00 00 	movq   $0x0,(%rsi)
 106c79b:	73 7f                	jae    106c81c <my.heap::set_env_slot+0xdc>
 106c79d:	48 89 d7             	mov    %rdx,%rdi
 106c7a0:	48 c1 e7 04          	shl    $0x4,%rdi
 106c7a4:	0f b6 c1             	movzbl %cl,%eax
 106c7a7:	49 89 44 39 20       	mov    %rax,0x20(%r9,%rdi,1)
 106c7ac:	4d 89 44 39 28       	mov    %r8,0x28(%r9,%rdi,1)
 106c7b1:	0f b6 0e             	movzbl (%rsi),%ecx
 106c7b4:	48 8b 7e 08          	mov    0x8(%rsi),%rdi
 106c7b8:	48 8b 56 10          	mov    0x10(%rsi),%rdx
 106c7bc:	48 8b 46 18          	mov    0x18(%rsi),%rax
 106c7c0:	48 8b 5e 20          	mov    0x20(%rsi),%rbx
 106c7c4:	4c 8b 76 28          	mov    0x28(%rsi),%r14
 106c7c8:	48 c7 06 09 00 00 00 	movq   $0x9,(%rsi)
 106c7cf:	4c 89 56 08          	mov    %r10,0x8(%rsi)
 106c7d3:	4c 89 4e 10          	mov    %r9,0x10(%rsi)
 106c7d7:	83 f9 09             	cmp    $0x9,%ecx
 106c7da:	77 38                	ja     106c814 <my.heap::set_env_slot+0xd4>
 106c7dc:	be d0 02 00 00       	mov    $0x2d0,%esi
 106c7e1:	0f a3 ce             	bt     %ecx,%esi
 106c7e4:	73 0f                	jae    106c7f5 <my.heap::set_env_slot+0xb5>
 106c7e6:	48 89 d7             	mov    %rdx,%rdi
 106c7e9:	48 83 c4 08          	add    $0x8,%rsp
 106c7ed:	5b                   	pop    %rbx
 106c7ee:	41 5e                	pop    %r14
 106c7f0:	e9 4b 78 fb ff       	jmp    1024040 <myl_core_drop_owned>
 106c7f5:	83 f9 01             	cmp    $0x1,%ecx
 106c7f8:	74 ef                	je     106c7e9 <my.heap::set_env_slot+0xa9>
 106c7fa:	83 f9 02             	cmp    $0x2,%ecx
 106c7fd:	75 15                	jne    106c814 <my.heap::set_env_slot+0xd4>
 106c7ff:	48 89 c7             	mov    %rax,%rdi
 106c802:	e8 39 78 fb ff       	call   1024040 <myl_core_drop_owned>
 106c807:	48 89 df             	mov    %rbx,%rdi
 106c80a:	e8 31 78 fb ff       	call   1024040 <myl_core_drop_owned>
 106c80f:	4c 89 f7             	mov    %r14,%rdi
 106c812:	eb d5                	jmp    106c7e9 <my.heap::set_env_slot+0xa9>
 106c814:	48 83 c4 08          	add    $0x8,%rsp
 106c818:	5b                   	pop    %rbx
 106c819:	41 5e                	pop    %r14
 106c81b:	c3                   	ret
 106c81c:	48 89 d7             	mov    %rdx,%rdi
 106c81f:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106c823:	48 21 c7             	and    %rax,%rdi
 106c826:	48 01 d7             	add    %rdx,%rdi
 106c829:	48 39 c7             	cmp    %rax,%rdi
 106c82c:	0f 82 6e ff ff ff    	jb     106c7a0 <my.heap::set_env_slot+0x60>
 106c832:	48 8d 3d 87 96 01 00 	lea    0x19687(%rip),%rdi        # 1085ec0 <core_durable_error.verbs+0x5bb0>
 106c839:	48 89 d6             	mov    %rdx,%rsi
 106c83c:	48 89 c2             	mov    %rax,%rdx
 106c83f:	e8 7c 85 fb ff       	call   1024dc0 <myl_core_trap>
 106c844:	48 8d 3d f5 c1 01 00 	lea    0x1c1f5(%rip),%rdi        # 1088a40 <core_durable_error.verbs+0x8730>
 106c84b:	e8 f0 d8 fb ff       	call   102a140 <myl_core_assert_fail>
 106c850:	48 8d 3d c9 b7 01 00 	lea    0x1b7c9(%rip),%rdi        # 1088020 <core_durable_error.verbs+0x7d10>
 106c857:	e8 e4 d8 fb ff       	call   102a140 <myl_core_assert_fail>
 106c85c:	48 8d 3d ed b7 01 00 	lea    0x1b7ed(%rip),%rdi        # 1088050 <core_durable_error.verbs+0x7d40>
 106c863:	e8 d8 d8 fb ff       	call   102a140 <myl_core_assert_fail>
