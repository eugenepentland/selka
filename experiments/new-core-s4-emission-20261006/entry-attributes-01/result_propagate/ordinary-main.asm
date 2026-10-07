
experiments/new-core-s4-emission-20261006/entry-attributes-01/result_propagate/ordinary_dependencies/program:     file format elf64-x86-64


Disassembly of section .text:

0000000001033580 <main>:
 1033580:	55                   	push   %rbp
 1033581:	41 57                	push   %r15
 1033583:	41 56                	push   %r14
 1033585:	41 55                	push   %r13
 1033587:	41 54                	push   %r12
 1033589:	53                   	push   %rbx
 103358a:	48 83 ec 28          	sub    $0x28,%rsp
 103358e:	e8 9d 64 fd ff       	call   1009a30 <myl_core_args>
 1033593:	48 89 c3             	mov    %rax,%rbx
 1033596:	e8 a5 ee fe ff       	call   1022440 <myl_core_host_grant>
 103359b:	41 be 02 00 00 00    	mov    $0x2,%r14d
 10335a1:	48 83 7b 08 03       	cmpq   $0x3,0x8(%rbx)
 10335a6:	0f 85 58 03 00 00    	jne    1033904 <main+0x384>
 10335ac:	49 89 c4             	mov    %rax,%r12
 10335af:	48 8b 7b 20          	mov    0x20(%rbx),%rdi
 10335b3:	e8 a8 fc ff ff       	call   1033260 <my.row_result_propagate::parse_number>
 10335b8:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 10335bc:	48 83 fa 01          	cmp    $0x1,%rdx
 10335c0:	0f 86 c5 03 00 00    	jbe    103398b <main+0x40b>
 10335c6:	49 89 c7             	mov    %rax,%r15
 10335c9:	48 8b 7b 28          	mov    0x28(%rbx),%rdi
 10335cd:	e8 8e fc ff ff       	call   1033260 <my.row_result_propagate::parse_number>
 10335d2:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 10335d6:	48 83 fa 02          	cmp    $0x2,%rdx
 10335da:	0f 86 bc 03 00 00    	jbe    103399c <main+0x41c>
 10335e0:	49 89 c5             	mov    %rax,%r13
 10335e3:	48 8b 7b 30          	mov    0x30(%rbx),%rdi
 10335e7:	e8 74 fc ff ff       	call   1033260 <my.row_result_propagate::parse_number>
 10335ec:	49 83 ff 02          	cmp    $0x2,%r15
 10335f0:	0f 9c c1             	setl   %cl
 10335f3:	4d 85 ed             	test   %r13,%r13
 10335f6:	0f 9e c2             	setle  %dl
 10335f9:	08 ca                	or     %cl,%dl
 10335fb:	48 8d 88 bf bd f0 ff 	lea    -0xf4241(%rax),%rcx
 1033602:	48 81 f9 c0 bd f0 ff 	cmp    $0xfffffffffff0bdc0,%rcx
 1033609:	0f 92 c1             	setb   %cl
 103360c:	08 d1                	or     %dl,%cl
 103360e:	0f 85 f0 02 00 00    	jne    1033904 <main+0x384>
 1033614:	4c 89 6c 24 20       	mov    %r13,0x20(%rsp)
 1033619:	4c 89 64 24 08       	mov    %r12,0x8(%rsp)
 103361e:	49 81 ff 00 04 00 00 	cmp    $0x400,%r15
 1033625:	48 89 5c 24 18       	mov    %rbx,0x18(%rsp)
 103362a:	0f 87 f2 02 00 00    	ja     1033922 <main+0x3a2>
 1033630:	4a 8d 0c fd 3f 00 00 	lea    0x3f(,%r15,8),%rcx
 1033637:	00 
 1033638:	48 81 f9 1f 04 00 00 	cmp    $0x41f,%rcx
 103363f:	0f 87 dd 02 00 00    	ja     1033922 <main+0x3a2>
 1033645:	48 89 ca             	mov    %rcx,%rdx
 1033648:	48 c1 ea 05          	shr    $0x5,%rdx
 103364c:	48 8d 35 1d 5d 02 00 	lea    0x25d1d(%rip),%rsi        # 1059370 <myl_core_free_lists>
 1033653:	4c 8b 2c d6          	mov    (%rsi,%rdx,8),%r13
 1033657:	4d 85 ed             	test   %r13,%r13
 103365a:	0f 84 c2 02 00 00    	je     1033922 <main+0x3a2>
 1033660:	49 8b 7d 00          	mov    0x0(%r13),%rdi
 1033664:	48 89 3c d6          	mov    %rdi,(%rsi,%rdx,8)
 1033668:	41 c7 45 00 01 00 00 	movl   $0x1,0x0(%r13)
 103366f:	00 
 1033670:	c1 e2 18             	shl    $0x18,%edx
 1033673:	41 89 55 04          	mov    %edx,0x4(%r13)
 1033677:	49 c7 45 08 00 00 00 	movq   $0x0,0x8(%r13)
 103367e:	00 
 103367f:	81 e1 e0 07 00 00    	and    $0x7e0,%ecx
 1033685:	48 83 c1 e0          	add    $0xffffffffffffffe0,%rcx
 1033689:	48 c1 e9 03          	shr    $0x3,%rcx
 103368d:	49 89 4d 10          	mov    %rcx,0x10(%r13)
 1033691:	49 c7 45 18 00 00 00 	movq   $0x0,0x18(%r13)
 1033698:	00 
 1033699:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 10336a0:	9f 75 03 
 10336a3:	45 31 f6             	xor    %r14d,%r14d
 10336a6:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 10336ad:	22 e7 81 
 10336b0:	31 ed                	xor    %ebp,%ebp
 10336b2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10336b9:	1f 84 00 00 00 00 00 
 10336c0:	48 39 ee             	cmp    %rbp,%rsi
 10336c3:	0f 84 90 02 00 00    	je     1033959 <main+0x3d9>
 10336c9:	48 89 c3             	mov    %rax,%rbx
 10336cc:	4c 01 f3             	add    %r14,%rbx
 10336cf:	0f 80 95 02 00 00    	jo     103396a <main+0x3ea>
 10336d5:	48 89 da             	mov    %rbx,%rdx
 10336d8:	c4 62 9b f6 e7       	mulx   %rdi,%r12,%r12
 10336dd:	49 8b 4d 08          	mov    0x8(%r13),%rcx
 10336e1:	49 3b 4d 10          	cmp    0x10(%r13),%rcx
 10336e5:	73 28                	jae    103370f <main+0x18f>
 10336e7:	49 c1 ec 09          	shr    $0x9,%r12
 10336eb:	49 69 d4 f1 03 00 00 	imul   $0x3f1,%r12,%rdx
 10336f2:	48 29 d3             	sub    %rdx,%rbx
 10336f5:	49 89 5c cd 20       	mov    %rbx,0x20(%r13,%rcx,8)
 10336fa:	48 ff c1             	inc    %rcx
 10336fd:	49 89 4d 08          	mov    %rcx,0x8(%r13)
 1033701:	48 ff c5             	inc    %rbp
 1033704:	49 83 c6 25          	add    $0x25,%r14
 1033708:	49 39 ef             	cmp    %rbp,%r15
 103370b:	75 b3                	jne    10336c0 <main+0x140>
 103370d:	eb 34                	jmp    1033743 <main+0x1c3>
 103370f:	be 08 00 00 00       	mov    $0x8,%esi
 1033714:	4c 89 ef             	mov    %r13,%rdi
 1033717:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 103371c:	e8 0f 5e fd ff       	call   1009530 <myl_core_list_grow>
 1033721:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 1033728:	22 e7 81 
 103372b:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 1033732:	9f 75 03 
 1033735:	49 89 c5             	mov    %rax,%r13
 1033738:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 103373d:	49 8b 4d 08          	mov    0x8(%r13),%rcx
 1033741:	eb a4                	jmp    10336e7 <main+0x167>
 1033743:	48 8d 3d 56 1b 00 00 	lea    0x1b56(%rip),%rdi        # 10352a0 <core_io_file_error.verbs+0x3e0>
 103374a:	e8 b1 6d fd ff       	call   100a500 <myl_core_io_at>
 103374f:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 1033754:	e8 17 ed fe ff       	call   1022470 <myl_core_host_check>
 1033759:	31 ed                	xor    %ebp,%ebp
 103375b:	e8 60 02 00 00       	call   10339c0 <runtime_bench_now>
 1033760:	49 89 c4             	mov    %rax,%r12
 1033763:	48 8d 0d 56 1c 00 00 	lea    0x1c56(%rip),%rcx        # 10353c0 <core_io_file_error.verbs+0x500>
 103376a:	4c 8d 0d 1f 1c 00 00 	lea    0x1c1f(%rip),%r9        # 1035390 <core_io_file_error.verbs+0x4d0>
 1033771:	48 bb e5 8f a2 12 31 	movabs $0x89705f3112a28fe5,%rbx
 1033778:	5f 70 89 
 103377b:	45 31 c0             	xor    %r8d,%r8d
 103377e:	66 90                	xchg   %ax,%ax
 1033780:	4c 89 c2             	mov    %r8,%rdx
 1033783:	48 b8 f1 f0 f0 f0 f0 	movabs $0xf0f0f0f0f0f0f0f1,%rax
 103378a:	f0 f0 f0 
 103378d:	c4 e2 fb f6 c0       	mulx   %rax,%rax,%rax
 1033792:	48 89 c2             	mov    %rax,%rdx
 1033795:	48 83 e2 f0          	and    $0xfffffffffffffff0,%rdx
 1033799:	48 c1 e8 04          	shr    $0x4,%rax
 103379d:	48 01 d0             	add    %rdx,%rax
 10337a0:	4d 89 c6             	mov    %r8,%r14
 10337a3:	49 29 c6             	sub    %rax,%r14
 10337a6:	31 f6                	xor    %esi,%esi
 10337a8:	45 31 d2             	xor    %r10d,%r10d
 10337ab:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10337b2:	0f 1f 84 00 00 00 00 
 10337b9:	00 
 10337ba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 10337c0:	4b 8b 54 d5 20       	mov    0x20(%r13,%r10,8),%rdx
 10337c5:	69 c2 cd cc ff ff    	imul   $0xffffcccd,%edx,%eax
 10337cb:	0f b7 c0             	movzwl %ax,%eax
 10337ce:	3d 33 33 00 00       	cmp    $0x3333,%eax
 10337d3:	76 29                	jbe    10337fe <main+0x27e>
 10337d5:	4c 01 f2             	add    %r14,%rdx
 10337d8:	31 c0                	xor    %eax,%eax
 10337da:	3c 01                	cmp    $0x1,%al
 10337dc:	74 33                	je     1033811 <main+0x291>
 10337de:	48 8d 04 52          	lea    (%rdx,%rdx,2),%rax
 10337e2:	48 ff c0             	inc    %rax
 10337e5:	48 89 f2             	mov    %rsi,%rdx
 10337e8:	48 01 c2             	add    %rax,%rdx
 10337eb:	0f 80 4c 01 00 00    	jo     103393d <main+0x3bd>
 10337f1:	49 ff c2             	inc    %r10
 10337f4:	48 89 d6             	mov    %rdx,%rsi
 10337f7:	4d 39 d7             	cmp    %r10,%r15
 10337fa:	75 c4                	jne    10337c0 <main+0x240>
 10337fc:	eb 32                	jmp    1033830 <main+0x2b0>
 10337fe:	48 89 cf             	mov    %rcx,%rdi
 1033801:	e8 ac f3 ff ff       	call   1032bb2 <myl_core_err_trace_origin_preserve_most>
 1033806:	ba 01 00 00 00       	mov    $0x1,%edx
 103380b:	b0 01                	mov    $0x1,%al
 103380d:	3c 01                	cmp    $0x1,%al
 103380f:	75 cd                	jne    10337de <main+0x25e>
 1033811:	4c 89 cf             	mov    %r9,%rdi
 1033814:	e8 b1 f3 ff ff       	call   1032bca <myl_core_err_trace_append_preserve_most>
 1033819:	48 8d 04 d5 00 00 00 	lea    0x0(,%rdx,8),%rax
 1033820:	00 
 1033821:	48 29 d0             	sub    %rdx,%rax
 1033824:	eb bf                	jmp    10337e5 <main+0x265>
 1033826:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 103382d:	00 00 00 
 1033830:	48 89 d6             	mov    %rdx,%rsi
 1033833:	48 01 ee             	add    %rbp,%rsi
 1033836:	0f 80 40 01 00 00    	jo     103397c <main+0x3fc>
 103383c:	48 89 f0             	mov    %rsi,%rax
 103383f:	48 f7 eb             	imul   %rbx
 1033842:	48 01 f2             	add    %rsi,%rdx
 1033845:	48 89 d0             	mov    %rdx,%rax
 1033848:	48 c1 e8 3f          	shr    $0x3f,%rax
 103384c:	48 c1 fa 1d          	sar    $0x1d,%rdx
 1033850:	48 01 c2             	add    %rax,%rdx
 1033853:	48 69 c2 07 ca 9a 3b 	imul   $0x3b9aca07,%rdx,%rax
 103385a:	48 29 c6             	sub    %rax,%rsi
 103385d:	48 89 f5             	mov    %rsi,%rbp
 1033860:	48 c1 fd 3f          	sar    $0x3f,%rbp
 1033864:	81 e5 07 ca 9a 3b    	and    $0x3b9aca07,%ebp
 103386a:	48 01 f5             	add    %rsi,%rbp
 103386d:	49 ff c0             	inc    %r8
 1033870:	4c 3b 44 24 20       	cmp    0x20(%rsp),%r8
 1033875:	0f 85 05 ff ff ff    	jne    1033780 <main+0x200>
 103387b:	41 0f b6 45 07       	movzbl 0x7(%r13),%eax
 1033880:	48 85 c0             	test   %rax,%rax
 1033883:	0f 84 c3 00 00 00    	je     103394c <main+0x3cc>
 1033889:	49 83 7d 18 00       	cmpq   $0x0,0x18(%r13)
 103388e:	0f 85 b8 00 00 00    	jne    103394c <main+0x3cc>
 1033894:	48 8d 0d d5 5a 02 00 	lea    0x25ad5(%rip),%rcx        # 1059370 <myl_core_free_lists>
 103389b:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 103389f:	49 89 55 00          	mov    %rdx,0x0(%r13)
 10338a3:	4c 89 2c c1          	mov    %r13,(%rcx,%rax,8)
 10338a7:	48 8d 3d 22 1a 00 00 	lea    0x1a22(%rip),%rdi        # 10352d0 <core_io_file_error.verbs+0x410>
 10338ae:	e8 4d 6c fd ff       	call   100a500 <myl_core_io_at>
 10338b3:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
 10338b8:	e8 b3 eb fe ff       	call   1022470 <myl_core_host_check>
 10338bd:	e8 fe 00 00 00       	call   10339c0 <runtime_bench_now>
 10338c2:	48 89 c3             	mov    %rax,%rbx
 10338c5:	4c 29 e3             	sub    %r12,%rbx
 10338c8:	0f 80 df 00 00 00    	jo     10339ad <main+0x42d>
 10338ce:	bf 01 00 00 00       	mov    $0x1,%edi
 10338d3:	48 89 ee             	mov    %rbp,%rsi
 10338d6:	e8 25 73 fd ff       	call   100ac00 <myl_core_print_i64>
 10338db:	bf 01 00 00 00       	mov    $0x1,%edi
 10338e0:	e8 5b 59 fd ff       	call   1009240 <myl_core_print_sep>
 10338e5:	bf 01 00 00 00       	mov    $0x1,%edi
 10338ea:	48 89 de             	mov    %rbx,%rsi
 10338ed:	e8 0e 73 fd ff       	call   100ac00 <myl_core_print_i64>
 10338f2:	bf 01 00 00 00       	mov    $0x1,%edi
 10338f7:	e8 04 5a fd ff       	call   1009300 <myl_core_print_end>
 10338fc:	45 31 f6             	xor    %r14d,%r14d
 10338ff:	48 8b 5c 24 18       	mov    0x18(%rsp),%rbx
 1033904:	48 89 df             	mov    %rbx,%rdi
 1033907:	e8 f4 60 fd ff       	call   1009a00 <myl_core_release>
 103390c:	4c 89 f7             	mov    %r14,%rdi
 103390f:	48 83 c4 28          	add    $0x28,%rsp
 1033913:	5b                   	pop    %rbx
 1033914:	41 5c                	pop    %r12
 1033916:	41 5d                	pop    %r13
 1033918:	41 5e                	pop    %r14
 103391a:	41 5f                	pop    %r15
 103391c:	5d                   	pop    %rbp
 103391d:	e9 ee 6b fd ff       	jmp    100a510 <myl_core_exit>
 1033922:	be 08 00 00 00       	mov    $0x8,%esi
 1033927:	4c 89 ff             	mov    %r15,%rdi
 103392a:	48 89 c3             	mov    %rax,%rbx
 103392d:	e8 8e 5b fd ff       	call   10094c0 <myl_core_list_new_slow>
 1033932:	49 89 c5             	mov    %rax,%r13
 1033935:	48 89 d8             	mov    %rbx,%rax
 1033938:	e9 5c fd ff ff       	jmp    1033699 <main+0x119>
 103393d:	48 8d 3d 1c 1a 00 00 	lea    0x1a1c(%rip),%rdi        # 1035360 <core_io_file_error.verbs+0x4a0>
 1033944:	48 89 c2             	mov    %rax,%rdx
 1033947:	e8 74 62 fd ff       	call   1009bc0 <myl_core_trap>
 103394c:	4c 89 ef             	mov    %r13,%rdi
 103394f:	e8 7c ee ff ff       	call   10327d0 <myl_core_free_block>
 1033954:	e9 4e ff ff ff       	jmp    10338a7 <main+0x327>
 1033959:	48 8d 3d e0 18 00 00 	lea    0x18e0(%rip),%rdi        # 1035240 <core_io_file_error.verbs+0x380>
 1033960:	ba 25 00 00 00       	mov    $0x25,%edx
 1033965:	e8 56 62 fd ff       	call   1009bc0 <myl_core_trap>
 103396a:	48 8d 3d ff 18 00 00 	lea    0x18ff(%rip),%rdi        # 1035270 <core_io_file_error.verbs+0x3b0>
 1033971:	48 89 c6             	mov    %rax,%rsi
 1033974:	4c 89 f2             	mov    %r14,%rdx
 1033977:	e8 44 62 fd ff       	call   1009bc0 <myl_core_trap>
 103397c:	48 8d 3d ad 19 00 00 	lea    0x19ad(%rip),%rdi        # 1035330 <core_io_file_error.verbs+0x470>
 1033983:	48 89 ee             	mov    %rbp,%rsi
 1033986:	e8 35 62 fd ff       	call   1009bc0 <myl_core_trap>
 103398b:	48 8d 3d 4e 18 00 00 	lea    0x184e(%rip),%rdi        # 10351e0 <core_io_file_error.verbs+0x320>
 1033992:	be 01 00 00 00       	mov    $0x1,%esi
 1033997:	e8 24 62 fd ff       	call   1009bc0 <myl_core_trap>
 103399c:	48 8d 3d 6d 18 00 00 	lea    0x186d(%rip),%rdi        # 1035210 <core_io_file_error.verbs+0x350>
 10339a3:	be 02 00 00 00       	mov    $0x2,%esi
 10339a8:	e8 13 62 fd ff       	call   1009bc0 <myl_core_trap>
 10339ad:	48 8d 3d 4c 19 00 00 	lea    0x194c(%rip),%rdi        # 1035300 <core_io_file_error.verbs+0x440>
 10339b4:	48 89 c6             	mov    %rax,%rsi
 10339b7:	4c 89 e2             	mov    %r12,%rdx
 10339ba:	e8 01 62 fd ff       	call   1009bc0 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
