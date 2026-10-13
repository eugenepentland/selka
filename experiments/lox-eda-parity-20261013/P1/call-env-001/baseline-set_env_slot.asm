
.tmp/lox-eda-parity/P1/call-env-001/baseline-lox:     file format elf64-x86-64


Disassembly of section .text:

000000000106c6c0 <my.heap::set_env_slot>:
 106c6c0:	41 56                	push   %r14
 106c6c2:	53                   	push   %rbx
 106c6c3:	50                   	push   %rax
 106c6c4:	48 85 f6             	test   %rsi,%rsi
 106c6c7:	0f 88 f7 00 00 00    	js     106c7c4 <my.heap::set_env_slot+0x104>
 106c6cd:	48 8b 07             	mov    (%rdi),%rax
 106c6d0:	48 3b 70 08          	cmp    0x8(%rax),%rsi
 106c6d4:	0f 8d ea 00 00 00    	jge    106c7c4 <my.heap::set_env_slot+0x104>
 106c6da:	48 6b f6 38          	imul   $0x38,%rsi,%rsi
 106c6de:	83 7c 30 20 09       	cmpl   $0x9,0x20(%rax,%rsi,1)
 106c6e3:	0f 85 e7 00 00 00    	jne    106c7d0 <my.heap::set_env_slot+0x110>
 106c6e9:	48 01 c6             	add    %rax,%rsi
 106c6ec:	48 83 c6 20          	add    $0x20,%rsi
 106c6f0:	4c 8b 4e 10          	mov    0x10(%rsi),%r9
 106c6f4:	49 8b 41 08          	mov    0x8(%r9),%rax
 106c6f8:	48 89 c7             	mov    %rax,%rdi
 106c6fb:	48 f7 df             	neg    %rdi
 106c6fe:	48 39 fa             	cmp    %rdi,%rdx
 106c701:	0f 8c d5 00 00 00    	jl     106c7dc <my.heap::set_env_slot+0x11c>
 106c707:	48 39 c2             	cmp    %rax,%rdx
 106c70a:	0f 8d cc 00 00 00    	jge    106c7dc <my.heap::set_env_slot+0x11c>
 106c710:	4c 8b 56 08          	mov    0x8(%rsi),%r10
 106c714:	48 c7 06 00 00 00 00 	movq   $0x0,(%rsi)
 106c71b:	73 7f                	jae    106c79c <my.heap::set_env_slot+0xdc>
 106c71d:	48 89 d7             	mov    %rdx,%rdi
 106c720:	48 c1 e7 04          	shl    $0x4,%rdi
 106c724:	0f b6 c1             	movzbl %cl,%eax
 106c727:	49 89 44 39 20       	mov    %rax,0x20(%r9,%rdi,1)
 106c72c:	4d 89 44 39 28       	mov    %r8,0x28(%r9,%rdi,1)
 106c731:	0f b6 0e             	movzbl (%rsi),%ecx
 106c734:	48 8b 7e 08          	mov    0x8(%rsi),%rdi
 106c738:	48 8b 56 10          	mov    0x10(%rsi),%rdx
 106c73c:	48 8b 46 18          	mov    0x18(%rsi),%rax
 106c740:	48 8b 5e 20          	mov    0x20(%rsi),%rbx
 106c744:	4c 8b 76 28          	mov    0x28(%rsi),%r14
 106c748:	48 c7 06 09 00 00 00 	movq   $0x9,(%rsi)
 106c74f:	4c 89 56 08          	mov    %r10,0x8(%rsi)
 106c753:	4c 89 4e 10          	mov    %r9,0x10(%rsi)
 106c757:	83 f9 09             	cmp    $0x9,%ecx
 106c75a:	77 38                	ja     106c794 <my.heap::set_env_slot+0xd4>
 106c75c:	be d0 02 00 00       	mov    $0x2d0,%esi
 106c761:	0f a3 ce             	bt     %ecx,%esi
 106c764:	73 0f                	jae    106c775 <my.heap::set_env_slot+0xb5>
 106c766:	48 89 d7             	mov    %rdx,%rdi
 106c769:	48 83 c4 08          	add    $0x8,%rsp
 106c76d:	5b                   	pop    %rbx
 106c76e:	41 5e                	pop    %r14
 106c770:	e9 4b 77 fb ff       	jmp    1023ec0 <myl_core_drop_owned>
 106c775:	83 f9 01             	cmp    $0x1,%ecx
 106c778:	74 ef                	je     106c769 <my.heap::set_env_slot+0xa9>
 106c77a:	83 f9 02             	cmp    $0x2,%ecx
 106c77d:	75 15                	jne    106c794 <my.heap::set_env_slot+0xd4>
 106c77f:	48 89 c7             	mov    %rax,%rdi
 106c782:	e8 39 77 fb ff       	call   1023ec0 <myl_core_drop_owned>
 106c787:	48 89 df             	mov    %rbx,%rdi
 106c78a:	e8 31 77 fb ff       	call   1023ec0 <myl_core_drop_owned>
 106c78f:	4c 89 f7             	mov    %r14,%rdi
 106c792:	eb d5                	jmp    106c769 <my.heap::set_env_slot+0xa9>
 106c794:	48 83 c4 08          	add    $0x8,%rsp
 106c798:	5b                   	pop    %rbx
 106c799:	41 5e                	pop    %r14
 106c79b:	c3                   	ret
 106c79c:	48 89 d7             	mov    %rdx,%rdi
 106c79f:	48 c1 ff 3f          	sar    $0x3f,%rdi
 106c7a3:	48 21 c7             	and    %rax,%rdi
 106c7a6:	48 01 d7             	add    %rdx,%rdi
 106c7a9:	48 39 c7             	cmp    %rax,%rdi
 106c7ac:	0f 82 6e ff ff ff    	jb     106c720 <my.heap::set_env_slot+0x60>
 106c7b2:	48 8d 3d 07 94 01 00 	lea    0x19407(%rip),%rdi        # 1085bc0 <core_durable_error.verbs+0x5bb0>
 106c7b9:	48 89 d6             	mov    %rdx,%rsi
 106c7bc:	48 89 c2             	mov    %rax,%rdx
 106c7bf:	e8 7c 84 fb ff       	call   1024c40 <myl_core_trap>
 106c7c4:	48 8d 3d 75 bf 01 00 	lea    0x1bf75(%rip),%rdi        # 1088740 <core_durable_error.verbs+0x8730>
 106c7cb:	e8 f0 d7 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c7d0:	48 8d 3d 49 b5 01 00 	lea    0x1b549(%rip),%rdi        # 1087d20 <core_durable_error.verbs+0x7d10>
 106c7d7:	e8 e4 d7 fb ff       	call   1029fc0 <myl_core_assert_fail>
 106c7dc:	48 8d 3d 6d b5 01 00 	lea    0x1b56d(%rip),%rdi        # 1087d50 <core_durable_error.verbs+0x7d40>
 106c7e3:	e8 d8 d7 fb ff       	call   1029fc0 <myl_core_assert_fail>
