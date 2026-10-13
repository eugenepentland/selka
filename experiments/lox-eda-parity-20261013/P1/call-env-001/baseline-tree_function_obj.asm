
.tmp/lox-eda-parity/P1/call-env-001/baseline-lox:     file format elf64-x86-64


Disassembly of section .text:

0000000001073520 <my.heap::tree_function_obj>:
 1073520:	50                   	push   %rax
 1073521:	48 8b 0e             	mov    (%rsi),%rcx
 1073524:	48 8b 41 08          	mov    0x8(%rcx),%rax
 1073528:	48 39 c2             	cmp    %rax,%rdx
 107352b:	73 37                	jae    1073564 <my.heap::tree_function_obj+0x44>
 107352d:	48 89 d6             	mov    %rdx,%rsi
 1073530:	48 6b d6 38          	imul   $0x38,%rsi,%rdx
 1073534:	8b 44 11 20          	mov    0x20(%rcx,%rdx,1),%eax
 1073538:	83 f8 0a             	cmp    $0xa,%eax
 107353b:	75 4b                	jne    1073588 <my.heap::tree_function_obj+0x68>
 107353d:	48 8d 04 11          	lea    (%rcx,%rdx,1),%rax
 1073541:	48 83 c0 20          	add    $0x20,%rax
 1073545:	48 8b 48 08          	mov    0x8(%rax),%rcx
 1073549:	c5 f8 10 40 10       	vmovups 0x10(%rax),%xmm0
 107354e:	0f b6 40 20          	movzbl 0x20(%rax),%eax
 1073552:	c5 f8 11 47 08       	vmovups %xmm0,0x8(%rdi)
 1073557:	48 89 0f             	mov    %rcx,(%rdi)
 107355a:	24 01                	and    $0x1,%al
 107355c:	88 47 18             	mov    %al,0x18(%rdi)
 107355f:	48 89 f8             	mov    %rdi,%rax
 1073562:	59                   	pop    %rcx
 1073563:	c3                   	ret
 1073564:	48 89 d6             	mov    %rdx,%rsi
 1073567:	48 c1 fe 3f          	sar    $0x3f,%rsi
 107356b:	48 21 c6             	and    %rax,%rsi
 107356e:	48 01 d6             	add    %rdx,%rsi
 1073571:	48 39 c6             	cmp    %rax,%rsi
 1073574:	72 ba                	jb     1073530 <my.heap::tree_function_obj+0x10>
 1073576:	48 8d 3d f3 5d 01 00 	lea    0x15df3(%rip),%rdi        # 1089370 <core_durable_error.verbs+0x9360>
 107357d:	48 89 d6             	mov    %rdx,%rsi
 1073580:	48 89 c2             	mov    %rax,%rdx
 1073583:	e8 b8 16 fb ff       	call   1024c40 <myl_core_trap>
 1073588:	83 f8 08             	cmp    $0x8,%eax
 107358b:	77 7e                	ja     107360b <my.heap::tree_function_obj+0xeb>
 107358d:	89 c0                	mov    %eax,%eax
 107358f:	48 8d 0d 36 49 f9 ff 	lea    -0x6b6ca(%rip),%rcx        # 1007ecc <core_number_pairs+0xc6c>
 1073596:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 107359a:	48 01 c8             	add    %rcx,%rax
 107359d:	ff e0                	jmp    *%rax
 107359f:	48 8d 3d fa 5d 01 00 	lea    0x15dfa(%rip),%rdi        # 10893a0 <core_durable_error.verbs+0x9390>
 10735a6:	e8 15 6a fb ff       	call   1029fc0 <myl_core_assert_fail>
 10735ab:	48 8d 3d ae 5e 01 00 	lea    0x15eae(%rip),%rdi        # 1089460 <core_durable_error.verbs+0x9450>
 10735b2:	e8 09 6a fb ff       	call   1029fc0 <myl_core_assert_fail>
 10735b7:	48 8d 3d 42 5e 01 00 	lea    0x15e42(%rip),%rdi        # 1089400 <core_durable_error.verbs+0x93f0>
 10735be:	e8 fd 69 fb ff       	call   1029fc0 <myl_core_assert_fail>
 10735c3:	48 8d 3d 66 5e 01 00 	lea    0x15e66(%rip),%rdi        # 1089430 <core_durable_error.verbs+0x9420>
 10735ca:	e8 f1 69 fb ff       	call   1029fc0 <myl_core_assert_fail>
 10735cf:	48 8d 3d 1a 5f 01 00 	lea    0x15f1a(%rip),%rdi        # 10894f0 <core_durable_error.verbs+0x94e0>
 10735d6:	e8 e5 69 fb ff       	call   1029fc0 <myl_core_assert_fail>
 10735db:	48 8d 3d ee 5d 01 00 	lea    0x15dee(%rip),%rdi        # 10893d0 <core_durable_error.verbs+0x93c0>
 10735e2:	e8 d9 69 fb ff       	call   1029fc0 <myl_core_assert_fail>
 10735e7:	48 8d 3d a2 5e 01 00 	lea    0x15ea2(%rip),%rdi        # 1089490 <core_durable_error.verbs+0x9480>
 10735ee:	e8 cd 69 fb ff       	call   1029fc0 <myl_core_assert_fail>
 10735f3:	48 8d 3d c6 5e 01 00 	lea    0x15ec6(%rip),%rdi        # 10894c0 <core_durable_error.verbs+0x94b0>
 10735fa:	e8 c1 69 fb ff       	call   1029fc0 <myl_core_assert_fail>
 10735ff:	48 8d 3d 1a 5f 01 00 	lea    0x15f1a(%rip),%rdi        # 1089520 <core_durable_error.verbs+0x9510>
 1073606:	e8 b5 69 fb ff       	call   1029fc0 <myl_core_assert_fail>
 107360b:	48 8d 3d 3e 5f 01 00 	lea    0x15f3e(%rip),%rdi        # 1089550 <core_durable_error.verbs+0x9540>
 1073612:	e8 a9 69 fb ff       	call   1029fc0 <myl_core_assert_fail>
