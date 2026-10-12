<myl_core_ir_str_append_char>:
 1020800:	48 3b 56 08          	cmp    0x8(%rsi),%rdx
 1020804:	0f 83 82 00 00 00    	jae    102088c <myl_core_ir_str_append_char+0x8c>
 102080a:	0f b6 44 16 20       	movzbl 0x20(%rsi,%rdx,1),%eax
 102080f:	84 c0                	test   %al,%al
 1020811:	78 2d                	js     1020840 <myl_core_ir_str_append_char+0x40>
 1020813:	4c 8b 47 08          	mov    0x8(%rdi),%r8
 1020817:	b9 01 00 00 00       	mov    $0x1,%ecx
 102081c:	4d 85 c0             	test   %r8,%r8
 102081f:	0f 88 9b 00 00 00    	js     10208c0 <core_text_append_char_general>
 1020825:	4c 3b 47 10          	cmp    0x10(%rdi),%r8
 1020829:	0f 8d 91 00 00 00    	jge    10208c0 <core_text_append_char_general>
 102082f:	44 8b 0f             	mov    (%rdi),%r9d
 1020832:	41 f7 c1 00 18 80 00 	test   $0x801800,%r9d
 1020839:	74 1f                	je     102085a <myl_core_ir_str_append_char+0x5a>
 102083b:	e9 80 00 00 00       	jmp    10208c0 <core_text_append_char_general>
 1020840:	b9 02 00 00 00       	mov    $0x2,%ecx
 1020845:	3c e0                	cmp    $0xe0,%al
 1020847:	0f 82 73 00 00 00    	jb     10208c0 <core_text_append_char_general>
 102084d:	3c f0                	cmp    $0xf0,%al
 102084f:	b9 04 00 00 00       	mov    $0x4,%ecx
 1020854:	48 83 d9 00          	sbb    $0x0,%rcx
 1020858:	eb 66                	jmp    10208c0 <core_text_append_char_general>
 102085a:	41 81 e1 00 01 00 00 	and    $0x100,%r9d
 1020861:	49 8d 48 01          	lea    0x1(%r8),%rcx
 1020865:	42 88 44 07 20       	mov    %al,0x20(%rdi,%r8,1)
 102086a:	48 89 4f 08          	mov    %rcx,0x8(%rdi)
 102086e:	42 c6 44 07 21 00    	movb   $0x0,0x21(%rdi,%r8,1)
 1020874:	b8 ff f8 ff ff       	mov    $0xfffff8ff,%eax
 1020879:	23 07                	and    (%rdi),%eax
 102087b:	44 09 c8             	or     %r9d,%eax
 102087e:	89 07                	mov    %eax,(%rdi)
 1020880:	48 c7 47 18 00 00 00 	movq   $0x0,0x18(%rdi)
 1020887:	00 
 1020888:	48 89 f8             	mov    %rdi,%rax
 102088b:	c3                   	ret
 102088c:	55                   	push   %rbp
 102088d:	48 89 e5             	mov    %rsp,%rbp
 1020890:	bf ff ff ff ff       	mov    $0xffffffff,%edi
 1020895:	e8 26 a5 02 00       	call   104adc0 <myl_core_s2_unsupported>
 102089a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10208a1:	0f 1f 84 00 00 00 00 
 10208a8:	00 
 10208a9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10208b0:	0f 1f 84 00 00 00 00 
 10208b7:	00 
 10208b8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 10208bf:	00 
