
.tmp/lox-eda-parity/P1/call-env-001/candidate-lox:     file format elf64-x86-64


Disassembly of section .text:

00000000010736c0 <my.heap::tree_function_obj>:
 10736c0:	50                   	push   %rax
 10736c1:	48 8b 0e             	mov    (%rsi),%rcx
 10736c4:	48 8b 41 08          	mov    0x8(%rcx),%rax
 10736c8:	48 39 c2             	cmp    %rax,%rdx
 10736cb:	73 37                	jae    1073704 <my.heap::tree_function_obj+0x44>
 10736cd:	48 89 d6             	mov    %rdx,%rsi
 10736d0:	48 6b d6 38          	imul   $0x38,%rsi,%rdx
 10736d4:	8b 44 11 20          	mov    0x20(%rcx,%rdx,1),%eax
 10736d8:	83 f8 0a             	cmp    $0xa,%eax
 10736db:	75 4b                	jne    1073728 <my.heap::tree_function_obj+0x68>
 10736dd:	48 8d 04 11          	lea    (%rcx,%rdx,1),%rax
 10736e1:	48 83 c0 20          	add    $0x20,%rax
 10736e5:	48 8b 48 08          	mov    0x8(%rax),%rcx
 10736e9:	c5 f8 10 40 10       	vmovups 0x10(%rax),%xmm0
 10736ee:	0f b6 40 20          	movzbl 0x20(%rax),%eax
 10736f2:	c5 f8 11 47 08       	vmovups %xmm0,0x8(%rdi)
 10736f7:	48 89 0f             	mov    %rcx,(%rdi)
 10736fa:	24 01                	and    $0x1,%al
 10736fc:	88 47 18             	mov    %al,0x18(%rdi)
 10736ff:	48 89 f8             	mov    %rdi,%rax
 1073702:	59                   	pop    %rcx
 1073703:	c3                   	ret
 1073704:	48 89 d6             	mov    %rdx,%rsi
 1073707:	48 c1 fe 3f          	sar    $0x3f,%rsi
 107370b:	48 21 c6             	and    %rax,%rsi
 107370e:	48 01 d6             	add    %rdx,%rsi
 1073711:	48 39 c6             	cmp    %rax,%rsi
 1073714:	72 ba                	jb     10736d0 <my.heap::tree_function_obj+0x10>
 1073716:	48 8d 3d 53 5f 01 00 	lea    0x15f53(%rip),%rdi        # 1089670 <core_durable_error.verbs+0x9360>
 107371d:	48 89 d6             	mov    %rdx,%rsi
 1073720:	48 89 c2             	mov    %rax,%rdx
 1073723:	e8 98 16 fb ff       	call   1024dc0 <myl_core_trap>
 1073728:	83 f8 08             	cmp    $0x8,%eax
 107372b:	77 7e                	ja     10737ab <my.heap::tree_function_obj+0xeb>
 107372d:	89 c0                	mov    %eax,%eax
 107372f:	48 8d 0d 96 47 f9 ff 	lea    -0x6b86a(%rip),%rcx        # 1007ecc <core_number_pairs+0xc6c>
 1073736:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 107373a:	48 01 c8             	add    %rcx,%rax
 107373d:	ff e0                	jmp    *%rax
 107373f:	48 8d 3d 5a 5f 01 00 	lea    0x15f5a(%rip),%rdi        # 10896a0 <core_durable_error.verbs+0x9390>
 1073746:	e8 f5 69 fb ff       	call   102a140 <myl_core_assert_fail>
 107374b:	48 8d 3d 0e 60 01 00 	lea    0x1600e(%rip),%rdi        # 1089760 <core_durable_error.verbs+0x9450>
 1073752:	e8 e9 69 fb ff       	call   102a140 <myl_core_assert_fail>
 1073757:	48 8d 3d a2 5f 01 00 	lea    0x15fa2(%rip),%rdi        # 1089700 <core_durable_error.verbs+0x93f0>
 107375e:	e8 dd 69 fb ff       	call   102a140 <myl_core_assert_fail>
 1073763:	48 8d 3d c6 5f 01 00 	lea    0x15fc6(%rip),%rdi        # 1089730 <core_durable_error.verbs+0x9420>
 107376a:	e8 d1 69 fb ff       	call   102a140 <myl_core_assert_fail>
 107376f:	48 8d 3d 7a 60 01 00 	lea    0x1607a(%rip),%rdi        # 10897f0 <core_durable_error.verbs+0x94e0>
 1073776:	e8 c5 69 fb ff       	call   102a140 <myl_core_assert_fail>
 107377b:	48 8d 3d 4e 5f 01 00 	lea    0x15f4e(%rip),%rdi        # 10896d0 <core_durable_error.verbs+0x93c0>
 1073782:	e8 b9 69 fb ff       	call   102a140 <myl_core_assert_fail>
 1073787:	48 8d 3d 02 60 01 00 	lea    0x16002(%rip),%rdi        # 1089790 <core_durable_error.verbs+0x9480>
 107378e:	e8 ad 69 fb ff       	call   102a140 <myl_core_assert_fail>
 1073793:	48 8d 3d 26 60 01 00 	lea    0x16026(%rip),%rdi        # 10897c0 <core_durable_error.verbs+0x94b0>
 107379a:	e8 a1 69 fb ff       	call   102a140 <myl_core_assert_fail>
 107379f:	48 8d 3d 7a 60 01 00 	lea    0x1607a(%rip),%rdi        # 1089820 <core_durable_error.verbs+0x9510>
 10737a6:	e8 95 69 fb ff       	call   102a140 <myl_core_assert_fail>
 10737ab:	48 8d 3d 9e 60 01 00 	lea    0x1609e(%rip),%rdi        # 1089850 <core_durable_error.verbs+0x9540>
 10737b2:	e8 89 69 fb ff       	call   102a140 <myl_core_assert_fail>
