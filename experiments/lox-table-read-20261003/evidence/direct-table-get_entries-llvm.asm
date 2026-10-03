
.tmp-lox-table-read-20261003/bin/direct-entries-llvm:     file format elf64-x86-64


Disassembly of section .text:

00000000010f3840 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f>:
 10f3840:	48 83 ec 48          	sub    $0x48,%rsp
 10f3844:	48 85 c9             	test   %rcx,%rcx
 10f3847:	0f 84 a7 00 00 00    	je     10f38f4 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xb4>
 10f384d:	48 8b 0a             	mov    (%rdx),%rcx
 10f3850:	48 85 c9             	test   %rcx,%rcx
 10f3853:	0f 88 d6 00 00 00    	js     10f392f <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xef>
 10f3859:	48 8d 41 ff          	lea    -0x1(%rcx),%rax
 10f385d:	49 ba ff ff ff ff fe 	movabs $0xfffffffeffffffff,%r10
 10f3864:	ff ff ff 
 10f3867:	4c 01 d1             	add    %r10,%rcx
 10f386a:	49 ff c2             	inc    %r10
 10f386d:	4c 39 d1             	cmp    %r10,%rcx
 10f3870:	0f 82 c9 00 00 00    	jb     10f393f <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xff>
 10f3876:	48 8b 4a 20          	mov    0x20(%rdx),%rcx
 10f387a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 10f3880:	49 21 c1             	and    %rax,%r9
 10f3883:	4d 89 ca             	mov    %r9,%r10
 10f3886:	49 c1 e2 05          	shl    $0x5,%r10
 10f388a:	4a 8d 14 11          	lea    (%rcx,%r10,1),%rdx
 10f388e:	4e 8b 14 11          	mov    (%rcx,%r10,1),%r10
 10f3892:	49 83 fa ff          	cmp    $0xffffffffffffffff,%r10
 10f3896:	74 08                	je     10f38a0 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x60>
 10f3898:	4d 39 c2             	cmp    %r8,%r10
 10f389b:	75 1b                	jne    10f38b8 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x78>
 10f389d:	eb 26                	jmp    10f38c5 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x85>
 10f389f:	90                   	nop
 10f38a0:	c5 fc 10 02          	vmovups (%rdx),%ymm0
 10f38a4:	c5 fc 11 44 24 20    	vmovups %ymm0,0x20(%rsp)
 10f38aa:	8b 54 24 30          	mov    0x30(%rsp),%edx
 10f38ae:	44 8d 52 ff          	lea    -0x1(%rdx),%r10d
 10f38b2:	41 83 fa 03          	cmp    $0x3,%r10d
 10f38b6:	73 38                	jae    10f38f0 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xb0>
 10f38b8:	4c 89 ca             	mov    %r9,%rdx
 10f38bb:	48 ff c2             	inc    %rdx
 10f38be:	70 5a                	jo     10f391a <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xda>
 10f38c0:	49 89 d1             	mov    %rdx,%r9
 10f38c3:	eb bb                	jmp    10f3880 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x40>
 10f38c5:	c5 f8 10 42 10       	vmovups 0x10(%rdx),%xmm0
 10f38ca:	c5 f8 11 44 24 10    	vmovups %xmm0,0x10(%rsp)
 10f38d0:	c7 07 01 00 00 00    	movl   $0x1,(%rdi)
 10f38d6:	c5 f8 10 44 24 0c    	vmovups 0xc(%rsp),%xmm0
 10f38dc:	c5 f8 11 47 04       	vmovups %xmm0,0x4(%rdi)
 10f38e1:	8b 44 24 1c          	mov    0x1c(%rsp),%eax
 10f38e5:	89 47 14             	mov    %eax,0x14(%rdi)
 10f38e8:	48 83 c4 48          	add    $0x48,%rsp
 10f38ec:	c5 f8 77             	vzeroupper
 10f38ef:	c3                   	ret
 10f38f0:	85 d2                	test   %edx,%edx
 10f38f2:	75 0e                	jne    10f3902 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xc2>
 10f38f4:	c7 07 00 00 00 00    	movl   $0x0,(%rdi)
 10f38fa:	48 83 c4 48          	add    $0x48,%rsp
 10f38fe:	c5 f8 77             	vzeroupper
 10f3901:	c3                   	ret
 10f3902:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 10f3906:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
 10f390a:	48 c7 47 10 00 00 00 	movq   $0x0,0x10(%rdi)
 10f3911:	00 
 10f3912:	48 83 c4 48          	add    $0x48,%rsp
 10f3916:	c5 f8 77             	vzeroupper
 10f3919:	c3                   	ret
 10f391a:	b9 01 00 00 00       	mov    $0x1,%ecx
 10f391f:	48 89 f7             	mov    %rsi,%rdi
 10f3922:	31 f6                	xor    %esi,%esi
 10f3924:	4c 89 ca             	mov    %r9,%rdx
 10f3927:	c5 f8 77             	vzeroupper
 10f392a:	e8 71 cf 08 00       	call   11808a0 <myl_qbe_fail_overflow_op>
 10f392f:	ba 40 01 00 00       	mov    $0x140,%edx
 10f3934:	48 89 f7             	mov    %rsi,%rdi
 10f3937:	48 89 ce             	mov    %rcx,%rsi
 10f393a:	e8 c1 cf 08 00       	call   1180900 <myl_qbe_fail_cast>
 10f393f:	ba 20 00 00 00       	mov    $0x20,%edx
 10f3944:	48 89 f7             	mov    %rsi,%rdi
 10f3947:	48 89 c6             	mov    %rax,%rsi
 10f394a:	e8 b1 cf 08 00       	call   1180900 <myl_qbe_fail_cast>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
