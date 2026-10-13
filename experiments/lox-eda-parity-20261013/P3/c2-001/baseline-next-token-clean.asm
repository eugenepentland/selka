
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/eda/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

0000000001090640 <my.sexpr_parser::next_token>:
 1090640:	push   %rbp
 1090641:	push   %r15
 1090643:	push   %r14
 1090645:	push   %r13
 1090647:	push   %r12
 1090649:	push   %rbx
 109064a:	sub    $0x48,%rsp
 109064e:	mov    %r9,%r13
 1090651:	mov    %rcx,%r11
 1090654:	mov    %rsi,%r12
 1090657:	mov    %rdi,0x38(%rsp)
 109065c:	mov    0x80(%rsp),%r15
 1090664:	mov    0x8(%rsi),%r10
 1090668:	mov    (%rdx),%rbx
 109066b:	lea    0x20(%rsi),%rdi
 109066f:	movabs $0x100002600,%rax
 1090679:	nopl   0x0(%rax)
 1090680:	mov    $0xffffffffffffffff,%rcx
 1090687:	cmp    %r10,%rbx
 109068a:	jge    10906b4 <my.sexpr_parser::next_token+0x74>
 109068c:	mov    %rbx,%rcx
 109068f:	sar    $0x3f,%rcx
 1090693:	and    %r10,%rcx
 1090696:	add    %rbx,%rcx
 1090699:	cmp    %r10,%rcx
 109069c:	jae    1091b85 <my.sexpr_parser::next_token+0x1545>
 10906a2:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10906b0:	movzbl (%rdi,%rcx,1),%ecx
 10906b4:	cmp    $0x3b,%rcx
 10906b8:	ja     10907d7 <my.sexpr_parser::next_token+0x197>
 10906be:	bt     %rcx,%rax
 10906c2:	jae    1090710 <my.sexpr_parser::next_token+0xd0>
 10906c4:	cmp    %r10,%rbx
 10906c7:	jge    10907aa <my.sexpr_parser::next_token+0x16a>
 10906cd:	mov    %rbx,%rcx
 10906d0:	sar    $0x3f,%rcx
 10906d4:	and    %r10,%rcx
 10906d7:	add    %rbx,%rcx
 10906da:	cmp    %r10,%rcx
 10906dd:	jae    1091b3f <my.sexpr_parser::next_token+0x14ff>
 10906e3:	cmpb   $0xa,(%rdi,%rcx,1)
 10906e7:	jne    1090790 <my.sexpr_parser::next_token+0x150>
 10906ed:	mov    0x8(%rdx),%rsi
 10906f1:	mov    %rsi,%rcx
 10906f4:	inc    %rcx
 10906f7:	jo     1091b63 <my.sexpr_parser::next_token+0x1523>
 10906fd:	mov    %rcx,0x8(%rdx)
 1090701:	mov    $0x1,%ecx
 1090706:	jmp    10907a0 <my.sexpr_parser::next_token+0x160>
 109070b:	nopl   0x0(%rax,%rax,1)
 1090710:	cmp    $0x3b,%rcx
 1090714:	jne    10907d7 <my.sexpr_parser::next_token+0x197>
 109071a:	cmp    %r10,%rbx
 109071d:	jge    1090680 <my.sexpr_parser::next_token+0x40>
 1090723:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090732:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090740:	mov    %rbx,%rcx
 1090743:	sar    $0x3f,%rcx
 1090747:	and    %r10,%rcx
 109074a:	lea    (%rcx,%rbx,1),%rsi
 109074e:	cmp    %r10,%rsi
 1090751:	jae    1091a13 <my.sexpr_parser::next_token+0x13d3>
 1090757:	add    %rdi,%rcx
 109075a:	cmpb   $0xa,(%rbx,%rcx,1)
 109075e:	je     1090680 <my.sexpr_parser::next_token+0x40>
 1090764:	mov    0x10(%rdx),%rsi
 1090768:	mov    %rsi,%rcx
 109076b:	inc    %rcx
 109076e:	jo     1091a25 <my.sexpr_parser::next_token+0x13e5>
 1090774:	mov    %rcx,0x10(%rdx)
 1090778:	inc    %rbx
 109077b:	mov    %rbx,(%rdx)
 109077e:	cmp    %rbx,%r10
 1090781:	jne    1090740 <my.sexpr_parser::next_token+0x100>
 1090783:	mov    %r10,%rbx
 1090786:	jmp    1090680 <my.sexpr_parser::next_token+0x40>
 109078b:	nopl   0x0(%rax,%rax,1)
 1090790:	mov    0x10(%rdx),%rsi
 1090794:	mov    %rsi,%rcx
 1090797:	inc    %rcx
 109079a:	jo     1091b74 <my.sexpr_parser::next_token+0x1534>
 10907a0:	mov    %rcx,0x10(%rdx)
 10907a4:	inc    %rbx
 10907a7:	mov    %rbx,(%rdx)
 10907aa:	cmp    %r10,%rbx
 10907ad:	jge    10907d7 <my.sexpr_parser::next_token+0x197>
 10907af:	mov    %rbx,%rcx
 10907b2:	sar    $0x3f,%rcx
 10907b6:	and    %r10,%rcx
 10907b9:	add    %rbx,%rcx
 10907bc:	cmp    %r10,%rcx
 10907bf:	jb     10906b0 <my.sexpr_parser::next_token+0x70>
 10907c5:	lea    0x61104(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 10907cc:	mov    %rbx,%rsi
 10907cf:	mov    %r10,%rdx
 10907d2:	call   103d4c0 <myl_core_trap>
 10907d7:	mov    0x8(%rdx),%rax
 10907db:	mov    %rax,0x20(%rsp)
 10907e0:	mov    0x10(%rdx),%r14
 10907e4:	mov    $0x8,%r9d
 10907ea:	mov    %rbx,%rax
 10907ed:	mov    %rbx,%rcx
 10907f0:	cmp    %r10,%rbx
 10907f3:	jge    1090aa7 <my.sexpr_parser::next_token+0x467>
 10907f9:	mov    %rbx,%rax
 10907fc:	sar    $0x3f,%rax
 1090800:	and    %r10,%rax
 1090803:	add    %rbx,%rax
 1090806:	cmp    %r10,%rax
 1090809:	jae    1091c3a <my.sexpr_parser::next_token+0x15fa>
 109080f:	movzbl (%rdi,%rax,1),%ecx
 1090813:	cmp    $0x22,%ecx
 1090816:	mov    %r14,0x8(%rsp)
 109081b:	je     1090869 <my.sexpr_parser::next_token+0x229>
 109081d:	cmp    $0x29,%ecx
 1090820:	je     1090844 <my.sexpr_parser::next_token+0x204>
 1090822:	cmp    $0x28,%ecx
 1090825:	jne    10909bb <my.sexpr_parser::next_token+0x37b>
 109082b:	mov    %r14,%rax
 109082e:	inc    %rax
 1090831:	jo     1091c86 <my.sexpr_parser::next_token+0x1646>
 1090837:	mov    %rax,0x10(%rdx)
 109083b:	lea    0x1(%rbx),%r12
 109083f:	xor    %r9d,%r9d
 1090842:	jmp    109085e <my.sexpr_parser::next_token+0x21e>
 1090844:	mov    %r14,%rax
 1090847:	inc    %rax
 109084a:	jo     1091c9a <my.sexpr_parser::next_token+0x165a>
 1090850:	mov    %rax,0x10(%rdx)
 1090854:	lea    0x1(%rbx),%r12
 1090858:	mov    $0x1,%r9d
 109085e:	mov    %r12,%rax
 1090861:	mov    %rbx,%rcx
 1090864:	jmp    1090aa4 <my.sexpr_parser::next_token+0x464>
 1090869:	mov    %r14,%r12
 109086c:	inc    %r12
 109086f:	jo     1091cae <my.sexpr_parser::next_token+0x166e>
 1090875:	mov    %r12,0x10(%rdx)
 1090879:	lea    0x1(%rbx),%rcx
 109087d:	mov    %rcx,(%rdx)
 1090880:	cmp    %r10,%rcx
 1090883:	jge    1090cec <my.sexpr_parser::next_token+0x6ac>
 1090889:	mov    %r11,%r14
 109088c:	mov    %r13,%r9
 109088f:	mov    0x20(%rsp),%r11
 1090894:	mov    %rcx,%rax
 1090897:	jmp    10908ea <my.sexpr_parser::next_token+0x2aa>
 1090899:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10908a8:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10908b7:	nopw   0x0(%rax,%rax,1)
 10908c0:	mov    %r12,%r13
 10908c3:	inc    %r13
 10908c6:	jo     1091bd1 <my.sexpr_parser::next_token+0x1591>
 10908cc:	mov    $0x1,%ebp
 10908d1:	mov    %r13,0x10(%rdx)
 10908d5:	add    %rax,%rbp
 10908d8:	mov    %rbp,(%rdx)
 10908db:	mov    %r13,%r12
 10908de:	mov    %rbp,%rax
 10908e1:	cmp    %r10,%rbp
 10908e4:	jge    1090cec <my.sexpr_parser::next_token+0x6ac>
 10908ea:	mov    %rax,%rsi
 10908ed:	sar    $0x3f,%rsi
 10908f1:	and    %r10,%rsi
 10908f4:	add    %rax,%rsi
 10908f7:	cmp    %r10,%rsi
 10908fa:	jae    1091b51 <my.sexpr_parser::next_token+0x1511>
 1090900:	movzbl (%rdi,%rsi,1),%esi
 1090904:	cmp    $0x5c,%esi
 1090907:	je     1090940 <my.sexpr_parser::next_token+0x300>
 1090909:	cmp    $0x22,%esi
 109090c:	je     1090a7f <my.sexpr_parser::next_token+0x43f>
 1090912:	cmp    $0xa,%sil
 1090916:	jne    10908c0 <my.sexpr_parser::next_token+0x280>
 1090918:	mov    %r11,%rsi
 109091b:	inc    %rsi
 109091e:	jo     1091bab <my.sexpr_parser::next_token+0x156b>
 1090924:	mov    %rsi,0x8(%rdx)
 1090928:	mov    $0x1,%r13d
 109092e:	mov    %rsi,%r11
 1090931:	jmp    10908cc <my.sexpr_parser::next_token+0x28c>
 1090933:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090940:	mov    %r12,%r13
 1090943:	inc    %r13
 1090946:	jo     1091b97 <my.sexpr_parser::next_token+0x1557>
 109094c:	mov    %r13,0x10(%rdx)
 1090950:	lea    0x1(%rax),%rbp
 1090954:	mov    %rbp,(%rdx)
 1090957:	cmp    %r10,%rbp
 109095a:	jge    10908db <my.sexpr_parser::next_token+0x29b>
 1090960:	cmp    $0xffffffffffffffff,%rax
 1090964:	mov    $0x0,%esi
 1090969:	cmovl  %r10,%rsi
 109096d:	add    %rbp,%rsi
 1090970:	cmp    %r10,%rsi
 1090973:	jae    1091bbf <my.sexpr_parser::next_token+0x157f>
 1090979:	cmpb   $0xa,(%rdi,%rsi,1)
 109097d:	jne    10909a2 <my.sexpr_parser::next_token+0x362>
 109097f:	mov    %r11,%rsi
 1090982:	inc    %rsi
 1090985:	jo     1091be5 <my.sexpr_parser::next_token+0x15a5>
 109098b:	mov    %rsi,0x8(%rdx)
 109098f:	mov    $0x2,%ebp
 1090994:	mov    $0x1,%r13d
 109099a:	mov    %rsi,%r11
 109099d:	jmp    10908d1 <my.sexpr_parser::next_token+0x291>
 10909a2:	mov    %r13,%rsi
 10909a5:	inc    %rsi
 10909a8:	jo     1091bf9 <my.sexpr_parser::next_token+0x15b9>
 10909ae:	mov    $0x2,%ebp
 10909b3:	mov    %rsi,%r13
 10909b6:	jmp    10908d1 <my.sexpr_parser::next_token+0x291>
 10909bb:	lea    -0x30(%rcx),%esi
 10909be:	mov    %r14,%r9
 10909c1:	mov    %rbx,%rax
 10909c4:	cmp    $0x9,%sil
 10909c8:	mov    %r8,0x10(%rsp)
 10909cd:	mov    %r11,(%rsp)
 10909d1:	ja     1090b00 <my.sexpr_parser::next_token+0x4c0>
 10909d7:	mov    $0x4,%ecx
 10909dc:	mov    %rcx,0x30(%rsp)
 10909e1:	mov    %rax,%rbp
 10909e4:	sub    %r10,%rbp
 10909e7:	jge    1090ef1 <my.sexpr_parser::next_token+0x8b1>
 10909ed:	mov    %r13,%r8
 10909f0:	lea    (%r12,%rax,1),%r11
 10909f4:	xor    %ecx,%ecx
 10909f6:	cs nopw 0x0(%rax,%rax,1)
 1090a00:	lea    (%rax,%rcx,1),%r15
 1090a04:	mov    %r15,%r13
 1090a07:	sar    $0x3f,%r13
 1090a0b:	and    %r10,%r13
 1090a0e:	lea    (%r15,%r13,1),%rsi
 1090a12:	cmp    %r10,%rsi
 1090a15:	jae    1091c0d <my.sexpr_parser::next_token+0x15cd>
 1090a1b:	lea    (%r9,%rcx,1),%rsi
 1090a1f:	add    %r11,%r13
 1090a22:	movzbl 0x20(%rcx,%r13,1),%r13d
 1090a28:	lea    -0x30(%r13),%r14d
 1090a2c:	cmp    $0x9,%r14b
 1090a30:	ja     1090d74 <my.sexpr_parser::next_token+0x734>
 1090a36:	inc    %rsi
 1090a39:	mov    0x8(%rsp),%r14
 1090a3e:	jo     1091c1f <my.sexpr_parser::next_token+0x15df>
 1090a44:	mov    %rsi,0x10(%rdx)
 1090a48:	lea    (%rax,%rcx,1),%rsi
 1090a4c:	inc    %rsi
 1090a4f:	mov    %rsi,(%rdx)
 1090a52:	inc    %rcx
 1090a55:	mov    %rbp,%rsi
 1090a58:	add    %rcx,%rsi
 1090a5b:	jne    1090a00 <my.sexpr_parser::next_token+0x3c0>
 1090a5d:	mov    $0x4,%r9d
 1090a63:	mov    %r10,%rax
 1090a66:	mov    %rbx,%rcx
 1090a69:	mov    0x80(%rsp),%r15
 1090a71:	mov    %r8,%r13
 1090a74:	mov    0x10(%rsp),%r8
 1090a79:	mov    (%rsp),%r11
 1090a7d:	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 1090a7f:	mov    %r12,%rsi
 1090a82:	inc    %rsi
 1090a85:	jo     1091cc4 <my.sexpr_parser::next_token+0x1684>
 1090a8b:	mov    %rsi,0x10(%rdx)
 1090a8f:	lea    0x1(%rax),%r12
 1090a93:	mov    %r9,%r13
 1090a96:	mov    $0x3,%r9d
 1090a9c:	mov    %r14,%r11
 1090a9f:	mov    0x8(%rsp),%r14
 1090aa4:	mov    %r12,(%rdx)
 1090aa7:	mov    0x38(%rsp),%r12
 1090aac:	mov    %r9,0x8(%r12)
 1090ab1:	mov    %rcx,0x10(%r12)
 1090ab6:	mov    %rax,0x18(%r12)
 1090abb:	mov    0x20(%rsp),%rax
 1090ac0:	mov    %rax,0x20(%r12)
 1090ac5:	mov    %r14,0x28(%r12)
 1090aca:	mov    %rbx,0x30(%r12)
 1090acf:	movq   $0x0,(%r12)
 1090ad7:	mov    %r11,0x68(%r12)
 1090adc:	mov    %r8,0x70(%r12)
 1090ae1:	mov    %r13,0x78(%r12)
 1090ae6:	mov    %r15,0x80(%r12)
 1090aee:	mov    %r12,%rax
 1090af1:	add    $0x48,%rsp
 1090af5:	pop    %rbx
 1090af6:	pop    %r12
 1090af8:	pop    %r13
 1090afa:	pop    %r14
 1090afc:	pop    %r15
 1090afe:	pop    %rbp
 1090aff:	ret
 1090b00:	cmp    $0x2d,%ecx
 1090b03:	jne    1090b5e <my.sexpr_parser::next_token+0x51e>
 1090b05:	lea    0x1(%rbx),%rax
 1090b09:	cmp    %r10,%rax
 1090b0c:	jge    1090e7a <my.sexpr_parser::next_token+0x83a>
 1090b12:	xor    %esi,%esi
 1090b14:	cmp    $0xffffffffffffffff,%rbx
 1090b18:	cmovl  %r10,%rsi
 1090b1c:	add    %rax,%rsi
 1090b1f:	cmp    %r10,%rsi
 1090b22:	jae    1091d5a <my.sexpr_parser::next_token+0x171a>
 1090b28:	movzbl (%rdi,%rsi,1),%esi
 1090b2c:	add    $0xd0,%sil
 1090b30:	cmp    $0xa,%sil
 1090b34:	jae    1090e7a <my.sexpr_parser::next_token+0x83a>
 1090b3a:	mov    %r14,%rcx
 1090b3d:	inc    %rcx
 1090b40:	jo     1091dc4 <my.sexpr_parser::next_token+0x1784>
 1090b46:	mov    %rcx,0x10(%rdx)
 1090b4a:	mov    %rax,(%rdx)
 1090b4d:	mov    0x10(%rsp),%r8
 1090b52:	mov    (%rsp),%r11
 1090b56:	mov    %rcx,%r9
 1090b59:	jmp    10909d7 <my.sexpr_parser::next_token+0x397>
 1090b5e:	mov    %ecx,%eax
 1090b60:	and    $0xffffffdf,%eax
 1090b63:	add    $0xffffffbf,%eax
 1090b66:	cmp    $0x1a,%eax
 1090b69:	jae    1090e5e <my.sexpr_parser::next_token+0x81e>
 1090b6f:	vmovd  -0x8c8f7(%rip),%xmm0        # 1004280 <__anon_1393+0x50>
 1090b77:	mov    0x20(%rsp),%r11
 1090b7c:	mov    %r14,%r12
 1090b7f:	mov    %rbx,%rax
 1090b82:	jmp    1090be7 <my.sexpr_parser::next_token+0x5a7>
 1090b84:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090b93:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090ba2:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090bb1:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090bc0:	mov    %r12,%rcx
 1090bc3:	inc    %rcx
 1090bc6:	jo     1091c72 <my.sexpr_parser::next_token+0x1632>
 1090bcc:	mov    %rcx,%r12
 1090bcf:	mov    0x8(%rsp),%r14
 1090bd4:	mov    %r12,0x10(%rdx)
 1090bd8:	inc    %rax
 1090bdb:	mov    %rax,(%rdx)
 1090bde:	cmp    %rax,%r10
 1090be1:	je     10910c6 <my.sexpr_parser::next_token+0xa86>
 1090be7:	mov    %rax,%rcx
 1090bea:	sar    $0x3f,%rcx
 1090bee:	and    %r10,%rcx
 1090bf1:	lea    (%rcx,%rax,1),%rsi
 1090bf5:	cmp    %r10,%rsi
 1090bf8:	jae    1091c4c <my.sexpr_parser::next_token+0x160c>
 1090bfe:	add    %rdi,%rcx
 1090c01:	movzbl (%rax,%rcx,1),%ecx
 1090c05:	mov    %ecx,%r8d
 1090c08:	and    $0xdf,%r8d
 1090c0f:	add    $0xffffffbf,%r8d
 1090c13:	mov    $0x1,%sil
 1090c16:	cmp    $0x1a,%r8d
 1090c1a:	jae    1090cc0 <my.sexpr_parser::next_token+0x680>
 1090c20:	vmovd  %ecx,%xmm1
 1090c24:	vpbroadcastb %xmm1,%xmm1
 1090c29:	vpcmpeqb %xmm0,%xmm1,%xmm1
 1090c2d:	vpmovsxbd %xmm1,%xmm1
 1090c32:	vmovmskps %xmm1,%ebp
 1090c36:	test   %ebp,%ebp
 1090c38:	jne    1090c66 <my.sexpr_parser::next_token+0x626>
 1090c3a:	mov    %ecx,%r14d
 1090c3d:	and    $0xfffffffd,%r14d
 1090c41:	cmp    $0x2d,%r14d
 1090c45:	je     1090c66 <my.sexpr_parser::next_token+0x626>
 1090c47:	mov    %ecx,%r14d
 1090c4a:	and    $0xfffffffb,%r14d
 1090c4e:	cmp    $0x2a,%r14d
 1090c52:	je     1090c66 <my.sexpr_parser::next_token+0x626>
 1090c54:	lea    -0x2b(%rcx),%ebp
 1090c57:	cmp    $0x2,%bpl
 1090c5b:	jb     1090c66 <my.sexpr_parser::next_token+0x626>
 1090c5d:	test   %sil,%sil
 1090c60:	je     10910aa <my.sexpr_parser::next_token+0xa6a>
 1090c66:	cmp    $0xa,%ecx
 1090c69:	jne    1090bc0 <my.sexpr_parser::next_token+0x580>
 1090c6f:	mov    %r11,%rcx
 1090c72:	inc    %rcx
 1090c75:	jo     1091c5e <my.sexpr_parser::next_token+0x161e>
 1090c7b:	mov    %rcx,0x8(%rdx)
 1090c7f:	mov    $0x1,%r12d
 1090c85:	mov    %rcx,%r11
 1090c88:	jmp    1090bcf <my.sexpr_parser::next_token+0x58f>
 1090c8d:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090c9c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090cab:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090cba:	nopw   0x0(%rax,%rax,1)
 1090cc0:	cmp    $0x2a,%rcx
 1090cc4:	je     1090c20 <my.sexpr_parser::next_token+0x5e0>
 1090cca:	cmp    $0x5f,%ecx
 1090ccd:	je     1090c20 <my.sexpr_parser::next_token+0x5e0>
 1090cd3:	cmp    $0x7e,%ecx
 1090cd6:	je     1090c20 <my.sexpr_parser::next_token+0x5e0>
 1090cdc:	lea    -0x30(%rcx),%esi
 1090cdf:	cmp    $0xa,%sil
 1090ce3:	setb   %sil
 1090ce7:	jmp    1090c20 <my.sexpr_parser::next_token+0x5e0>
 1090cec:	mov    0x38(%rsp),%r12
 1090cf1:	mov    0x20(%rsp),%r13
 1090cf6:	mov    %r13,0x18(%rdx)
 1090cfa:	mov    0x8(%rsp),%r14
 1090cff:	mov    %r14,0x20(%rdx)
 1090d03:	mov    %rbx,0x28(%rdx)
 1090d07:	lea    0x60c82(%rip),%rdi        # 10f1990 <core_durable_error.verbs+0x6390>
 1090d0e:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 1090d13:	lea    0x5fe66(%rip),%rdi        # 10f0b80 <core_durable_error.verbs+0x5580>
 1090d1a:	call   106f8c0 <myl_core_err_trace_append_preserve_most>
 1090d1f:	lea    -0x748c6(%rip),%rax        # 101c460 <core_number_pairs+0x14f10>
 1090d26:	mov    %rax,(%rsp)
 1090d2a:	mov    $0x3,%ebp
 1090d2f:	lea    0x5ec1a(%rip),%rdi        # 10ef950 <core_durable_error.verbs+0x4350>
 1090d36:	call   106f8c0 <myl_core_err_trace_append_preserve_most>
 1090d3b:	mov    %r15,%rdi
 1090d3e:	call   103c740 <myl_core_drop_owned>
 1090d43:	lea    0x5d9d6(%rip),%rdi        # 10ee720 <core_durable_error.verbs+0x3120>
 1090d4a:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 1090d4f:	movq   $0x1,(%r12)
 1090d57:	mov    %rbp,0x8(%r12)
 1090d5c:	mov    %r13,0x68(%r12)
 1090d61:	mov    %r14,0x70(%r12)
 1090d66:	mov    %rbx,0x78(%r12)
 1090d6b:	mov    (%rsp),%r15
 1090d6f:	jmp    1090ae6 <my.sexpr_parser::next_token+0x4a6>
 1090d74:	cmp    $0x2e,%r13b
 1090d78:	mov    0x8(%rsp),%r14
 1090d7d:	jne    1090ed7 <my.sexpr_parser::next_token+0x897>
 1090d83:	lea    (%rax,%rcx,1),%rbp
 1090d87:	inc    %rbp
 1090d8a:	cmp    %r10,%rbp
 1090d8d:	jge    1090ed7 <my.sexpr_parser::next_token+0x897>
 1090d93:	xor    %r13d,%r13d
 1090d96:	cmp    $0xffffffffffffffff,%r15
 1090d9a:	cmovl  %r10,%r13
 1090d9e:	lea    (%rax,%r13,1),%r14
 1090da2:	add    %rcx,%r14
 1090da5:	inc    %r14
 1090da8:	cmp    %r10,%r14
 1090dab:	jae    1091e13 <my.sexpr_parser::next_token+0x17d3>
 1090db1:	add    %r13,%r11
 1090db4:	movzbl 0x21(%rcx,%r11,1),%r11d
 1090dba:	add    $0xd0,%r11b
 1090dbe:	cmp    $0xa,%r11b
 1090dc2:	mov    0x8(%rsp),%r14
 1090dc7:	jae    1090ed7 <my.sexpr_parser::next_token+0x897>
 1090dcd:	mov    %rsi,%r11
 1090dd0:	inc    %r11
 1090dd3:	mov    %r8,%r13
 1090dd6:	mov    0x10(%rsp),%r8
 1090ddb:	jo     1091e25 <my.sexpr_parser::next_token+0x17e5>
 1090de1:	add    %r9,%rcx
 1090de4:	inc    %rcx
 1090de7:	mov    %r11,0x10(%rdx)
 1090deb:	add    $0x21,%r12
 1090def:	cmp    $0xffffffffffffffff,%r15
 1090df3:	mov    $0x0,%esi
 1090df8:	cmovl  %r10,%rsi
 1090dfc:	lea    (%rsi,%rbp,1),%r11
 1090e00:	cmp    %r10,%r11
 1090e03:	jae    1091cea <my.sexpr_parser::next_token+0x16aa>
 1090e09:	add    %r12,%rsi
 1090e0c:	movzbl (%r15,%rsi,1),%esi
 1090e11:	add    $0xd0,%sil
 1090e15:	cmp    $0x9,%sil
 1090e19:	mov    (%rsp),%r11
 1090e1d:	ja     1090e3e <my.sexpr_parser::next_token+0x7fe>
 1090e1f:	inc    %rcx
 1090e22:	jo     1091cff <my.sexpr_parser::next_token+0x16bf>
 1090e28:	mov    %rcx,0x10(%rdx)
 1090e2c:	inc    %rbp
 1090e2f:	inc    %r15
 1090e32:	cmp    %r10,%rbp
 1090e35:	jl     1090def <my.sexpr_parser::next_token+0x7af>
 1090e37:	mov    %r10,%rbp
 1090e3a:	mov    (%rsp),%r11
 1090e3e:	mov    %rbp,(%rdx)
 1090e41:	mov    $0x5,%eax
 1090e46:	mov    %rax,0x30(%rsp)
 1090e4b:	mov    %rcx,%r9
 1090e4e:	mov    %rbp,%rax
 1090e51:	mov    0x80(%rsp),%r15
 1090e59:	jmp    1090ef1 <my.sexpr_parser::next_token+0x8b1>
 1090e5e:	cmp    $0x2a,%rcx
 1090e62:	je     1090b6f <my.sexpr_parser::next_token+0x52f>
 1090e68:	cmp    $0x5f,%ecx
 1090e6b:	je     1090b6f <my.sexpr_parser::next_token+0x52f>
 1090e71:	cmp    $0x7e,%ecx
 1090e74:	je     1090b6f <my.sexpr_parser::next_token+0x52f>
 1090e7a:	mov    %ecx,%eax
 1090e7c:	and    $0xfffffffb,%eax
 1090e7f:	cmp    $0x2b,%eax
 1090e82:	je     1090ea6 <my.sexpr_parser::next_token+0x866>
 1090e84:	mov    %ecx,%eax
 1090e86:	and    $0xfffffff7,%eax
 1090e89:	cmp    $0x25,%eax
 1090e8c:	je     1090ea6 <my.sexpr_parser::next_token+0x866>
 1090e8e:	cmp    $0x21,%cl
 1090e91:	je     1090ea6 <my.sexpr_parser::next_token+0x866>
 1090e93:	cmp    $0x3d,%cl
 1090e96:	je     1090ea6 <my.sexpr_parser::next_token+0x866>
 1090e98:	mov    %ecx,%eax
 1090e9a:	and    $0xfffffffd,%eax
 1090e9d:	cmp    $0x3c,%eax
 1090ea0:	jne    109146e <my.sexpr_parser::next_token+0xe2e>
 1090ea6:	cmp    $0xa,%ecx
 1090ea9:	jne    10910e0 <my.sexpr_parser::next_token+0xaa0>
 1090eaf:	mov    0x20(%rsp),%rsi
 1090eb4:	mov    %rsi,%rax
 1090eb7:	inc    %rax
 1090eba:	mov    0x10(%rsp),%r8
 1090ebf:	mov    (%rsp),%r11
 1090ec3:	jo     1091d7e <my.sexpr_parser::next_token+0x173e>
 1090ec9:	mov    %rax,0x8(%rdx)
 1090ecd:	mov    $0x1,%esi
 1090ed2:	jmp    10910f5 <my.sexpr_parser::next_token+0xab5>
 1090ed7:	mov    %rsi,%r9
 1090eda:	mov    %r15,%rax
 1090edd:	mov    0x80(%rsp),%r15
 1090ee5:	mov    %r8,%r13
 1090ee8:	mov    0x10(%rsp),%r8
 1090eed:	mov    (%rsp),%r11
 1090ef1:	cmp    %r10,%rax
 1090ef4:	jge    109109d <my.sexpr_parser::next_token+0xa5d>
 1090efa:	mov    %rax,%r12
 1090efd:	sar    $0x3f,%r12
 1090f01:	and    %r10,%r12
 1090f04:	add    %rax,%r12
 1090f07:	cmp    %r10,%r12
 1090f0a:	jae    1091d23 <my.sexpr_parser::next_token+0x16e3>
 1090f10:	movzbl (%rdi,%r12,1),%ebp
 1090f15:	mov    %ebp,%ecx
 1090f17:	add    $0xffffffb9,%ecx
 1090f1a:	cmp    $0x2e,%ecx
 1090f1d:	mov    %r9,0x28(%rsp)
 1090f22:	ja     10912b6 <my.sexpr_parser::next_token+0xc76>
 1090f28:	movabs $0x429000000041,%rsi
 1090f32:	bt     %rcx,%rsi
 1090f36:	jae    109114f <my.sexpr_parser::next_token+0xb0f>
 1090f3c:	mov    %r13,0x18(%rsp)
 1090f41:	lea    0x1(%rax),%rsi
 1090f45:	mov    $0x1,%r9b
 1090f48:	cmp    %r10,%rsi
 1090f4b:	jge    109136b <my.sexpr_parser::next_token+0xd2b>
 1090f51:	xor    %ecx,%ecx
 1090f53:	cmp    $0xffffffffffffffff,%rax
 1090f57:	cmovl  %r10,%rcx
 1090f5b:	add    %rsi,%rcx
 1090f5e:	cmp    %r10,%rcx
 1090f61:	jae    1091db5 <my.sexpr_parser::next_token+0x1775>
 1090f67:	movzbl (%rdi,%rcx,1),%ecx
 1090f6b:	mov    %ecx,%r11d
 1090f6e:	and    $0xdf,%r11d
 1090f75:	add    $0xffffffbf,%r11d
 1090f79:	mov    $0x1,%r9b
 1090f7c:	mov    $0x1,%sil
 1090f7f:	cmp    $0x1a,%r11d
 1090f83:	jae    109128a <my.sexpr_parser::next_token+0xc4a>
 1090f89:	vmovd  %ecx,%xmm0
 1090f8d:	vpbroadcastb %xmm0,%xmm0
 1090f92:	vpcmpeqb -0x8cd1a(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 1090f9a:	vpmovsxbd %xmm0,%xmm0
 1090f9f:	vmovmskps %xmm0,%r11d
 1090fa3:	test   %r11d,%r11d
 1090fa6:	jne    1090fd5 <my.sexpr_parser::next_token+0x995>
 1090fa8:	mov    %ecx,%r11d
 1090fab:	and    $0xfffffffd,%r11d
 1090faf:	cmp    $0x2d,%r11d
 1090fb3:	je     1090fd5 <my.sexpr_parser::next_token+0x995>
 1090fb5:	mov    %ecx,%r11d
 1090fb8:	and    $0xfffffffb,%r11d
 1090fbc:	cmp    $0x2a,%r11d
 1090fc0:	je     1090fd5 <my.sexpr_parser::next_token+0x995>
 1090fc2:	lea    -0x2b(%rcx),%r11d
 1090fc6:	cmp    $0x2,%r11b
 1090fca:	jb     1090fd5 <my.sexpr_parser::next_token+0x995>
 1090fcc:	test   %sil,%sil
 1090fcf:	je     109136b <my.sexpr_parser::next_token+0xd2b>
 1090fd5:	mov    %ecx,%esi
 1090fd7:	and    $0xffffffef,%esi
 1090fda:	cmp    $0x46,%esi
 1090fdd:	je     1090ff9 <my.sexpr_parser::next_token+0x9b9>
 1090fdf:	add    $0xffffffbf,%ecx
 1090fe2:	cmp    $0x11,%ecx
 1090fe5:	ja     10914e3 <my.sexpr_parser::next_token+0xea3>
 1090feb:	mov    $0x20081,%esi
 1090ff0:	bt     %ecx,%esi
 1090ff3:	jae    10914e3 <my.sexpr_parser::next_token+0xea3>
 1090ff9:	lea    0x2(%rax),%rsi
 1090ffd:	cmp    %r10,%rsi
 1091000:	jge    1091095 <my.sexpr_parser::next_token+0xa55>
 1091006:	xor    %ecx,%ecx
 1091008:	cmp    $0xfffffffffffffffe,%rax
 109100c:	cmovl  %r10,%rcx
 1091010:	add    %rsi,%rcx
 1091013:	cmp    %r10,%rcx
 1091016:	jae    1091e36 <my.sexpr_parser::next_token+0x17f6>
 109101c:	movzbl (%rdi,%rcx,1),%ecx
 1091020:	mov    %ecx,%r11d
 1091023:	and    $0xdf,%r11d
 109102a:	add    $0xffffffbf,%r11d
 109102e:	mov    $0x1,%sil
 1091031:	cmp    $0x1a,%r11d
 1091035:	jae    10914a5 <my.sexpr_parser::next_token+0xe65>
 109103b:	vmovd  %ecx,%xmm0
 109103f:	vpbroadcastb %xmm0,%xmm0
 1091044:	vpcmpeqb -0x8cdcc(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 109104c:	vpmovsxbd %xmm0,%xmm0
 1091051:	vmovmskps %xmm0,%r11d
 1091055:	test   %r11d,%r11d
 1091058:	jne    10914e3 <my.sexpr_parser::next_token+0xea3>
 109105e:	mov    %ecx,%r11d
 1091061:	and    $0xfffffffd,%r11d
 1091065:	cmp    $0x2d,%r11d
 1091069:	je     10914e3 <my.sexpr_parser::next_token+0xea3>
 109106f:	mov    %ecx,%r11d
 1091072:	and    $0xfffffffb,%r11d
 1091076:	cmp    $0x2a,%r11d
 109107a:	je     10914e3 <my.sexpr_parser::next_token+0xea3>
 1091080:	add    $0xffffffd5,%ecx
 1091083:	cmp    $0x2,%cl
 1091086:	jb     10914e3 <my.sexpr_parser::next_token+0xea3>
 109108c:	test   %sil,%sil
 109108f:	jne    10914e3 <my.sexpr_parser::next_token+0xea3>
 1091095:	xor    %r9d,%r9d
 1091098:	jmp    109136b <my.sexpr_parser::next_token+0xd2b>
 109109d:	mov    %rbx,%rcx
 10910a0:	mov    0x30(%rsp),%r9
 10910a5:	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 10910aa:	mov    %rbx,%rcx
 10910ad:	mov    0x10(%rsp),%r8
 10910b2:	mov    (%rsp),%r11
 10910b6:	mov    0x8(%rsp),%r14
 10910bb:	mov    $0x2,%r9d
 10910c1:	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 10910c6:	mov    %r10,%rax
 10910c9:	mov    %rbx,%rcx
 10910cc:	mov    0x10(%rsp),%r8
 10910d1:	mov    (%rsp),%r11
 10910d5:	mov    $0x2,%r9d
 10910db:	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 10910e0:	mov    %r14,%rsi
 10910e3:	inc    %rsi
 10910e6:	mov    0x10(%rsp),%r8
 10910eb:	mov    (%rsp),%r11
 10910ef:	jo     1091d8f <my.sexpr_parser::next_token+0x174f>
 10910f5:	mov    %rsi,0x10(%rdx)
 10910f9:	lea    0x1(%rbx),%rax
 10910fd:	mov    %rax,(%rdx)
 1091100:	mov    $0x2,%r9d
 1091106:	cmp    %r10,%rax
 1091109:	jge    1091147 <my.sexpr_parser::next_token+0xb07>
 109110b:	xor    %ecx,%ecx
 109110d:	cmp    $0xffffffffffffffff,%rbx
 1091111:	cmovl  %r10,%rcx
 1091115:	add    %rax,%rcx
 1091118:	cmp    %r10,%rcx
 109111b:	jae    1091da3 <my.sexpr_parser::next_token+0x1763>
 1091121:	cmpb   $0x3d,(%rdi,%rcx,1)
 1091125:	mov    %rbx,%rcx
 1091128:	jne    1090aa7 <my.sexpr_parser::next_token+0x467>
 109112e:	mov    %rsi,%rax
 1091131:	inc    %rax
 1091134:	jo     1091de9 <my.sexpr_parser::next_token+0x17a9>
 109113a:	mov    %rax,0x10(%rdx)
 109113e:	lea    0x2(%rbx),%r12
 1091142:	jmp    109085e <my.sexpr_parser::next_token+0x21e>
 1091147:	mov    %rbx,%rcx
 109114a:	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 109114f:	cmp    $0x26,%rcx
 1091153:	jne    10912b6 <my.sexpr_parser::next_token+0xc76>
 1091159:	lea    0x1(%rax),%rcx
 109115d:	mov    $0x1,%sil
 1091160:	mov    $0x6d,%r9d
 1091166:	cmp    %r10,%rcx
 1091169:	jge    109178d <my.sexpr_parser::next_token+0x114d>
 109116f:	mov    %rcx,%rsi
 1091172:	xor    %ecx,%ecx
 1091174:	cmp    $0xffffffffffffffff,%rax
 1091178:	cmovl  %r10,%rcx
 109117c:	mov    %rsi,0x40(%rsp)
 1091181:	add    %rsi,%rcx
 1091184:	cmp    %r10,%rcx
 1091187:	jae    1091e45 <my.sexpr_parser::next_token+0x1805>
 109118d:	movzbl (%rdi,%rcx,1),%ecx
 1091191:	cmp    $0x69,%ecx
 1091194:	je     1091571 <my.sexpr_parser::next_token+0xf31>
 109119a:	cmp    $0x6d,%ecx
 109119d:	jne    10916a8 <my.sexpr_parser::next_token+0x1068>
 10911a3:	lea    0x2(%rax),%r12
 10911a7:	cmp    %r10,%r12
 10911aa:	jge    109124b <my.sexpr_parser::next_token+0xc0b>
 10911b0:	xor    %ecx,%ecx
 10911b2:	cmp    $0xfffffffffffffffe,%rax
 10911b6:	cmovl  %r10,%rcx
 10911ba:	add    %r12,%rcx
 10911bd:	cmp    %r10,%rcx
 10911c0:	jae    1091e7c <my.sexpr_parser::next_token+0x183c>
 10911c6:	movzbl (%rdi,%rcx,1),%ecx
 10911ca:	mov    %ecx,%r14d
 10911cd:	and    $0xdf,%r14d
 10911d4:	add    $0xffffffbf,%r14d
 10911d8:	mov    $0x1,%sil
 10911db:	mov    $0x1,%r11b
 10911de:	cmp    $0x1a,%r14d
 10911e2:	jae    10919a3 <my.sexpr_parser::next_token+0x1363>
 10911e8:	vmovd  %ecx,%xmm0
 10911ec:	vpbroadcastb %xmm0,%xmm0
 10911f1:	vpcmpeqb -0x8cf79(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 10911f9:	vpmovsxbd %xmm0,%xmm0
 10911fe:	vmovmskps %xmm0,%r14d
 1091202:	test   %r14d,%r14d
 1091205:	jne    1091a40 <my.sexpr_parser::next_token+0x1400>
 109120b:	mov    %ecx,%r14d
 109120e:	and    $0xfffffffd,%r14d
 1091212:	cmp    $0x2d,%r14d
 1091216:	je     1091a40 <my.sexpr_parser::next_token+0x1400>
 109121c:	mov    %ecx,%r14d
 109121f:	and    $0xfffffffb,%r14d
 1091223:	cmp    $0x2a,%r14d
 1091227:	je     1091a40 <my.sexpr_parser::next_token+0x1400>
 109122d:	add    $0xffffffd5,%ecx
 1091230:	cmp    $0x2,%cl
 1091233:	mov    0x8(%rsp),%r14
 1091238:	jb     1091b20 <my.sexpr_parser::next_token+0x14e0>
 109123e:	test   %r11b,%r11b
 1091241:	mov    (%rsp),%r11
 1091245:	jne    109178d <my.sexpr_parser::next_token+0x114d>
 109124b:	mov    0x28(%rsp),%rcx
 1091250:	mov    %rcx,%rsi
 1091253:	inc    %rsi
 1091256:	jo     1091e68 <my.sexpr_parser::next_token+0x1828>
 109125c:	mov    %rsi,0x10(%rdx)
 1091260:	lea    0x1(%rax),%rcx
 1091264:	mov    %rcx,(%rdx)
 1091267:	mov    %rsi,%rcx
 109126a:	inc    %rcx
 109126d:	mov    $0x6,%r9d
 1091273:	jno    1091ad7 <my.sexpr_parser::next_token+0x1497>
 1091279:	lea    0x606e0(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091280:	mov    $0x1,%edx
 1091285:	call   103d4c0 <myl_core_trap>
 109128a:	cmp    $0x2a,%rcx
 109128e:	je     1090f89 <my.sexpr_parser::next_token+0x949>
 1091294:	cmp    $0x5f,%ecx
 1091297:	je     1090f89 <my.sexpr_parser::next_token+0x949>
 109129d:	cmp    $0x7e,%ecx
 10912a0:	je     1090f89 <my.sexpr_parser::next_token+0x949>
 10912a6:	lea    -0x30(%rcx),%esi
 10912a9:	cmp    $0xa,%sil
 10912ad:	setb   %sil
 10912b1:	jmp    1090f89 <my.sexpr_parser::next_token+0x949>
 10912b6:	mov    %r13,0x18(%rsp)
 10912bb:	mov    %ebp,%ecx
 10912bd:	and    $0xef,%cl
 10912c0:	cmp    $0x46,%cl
 10912c3:	jne    1091455 <my.sexpr_parser::next_token+0xe15>
 10912c9:	lea    0x1(%rax),%rsi
 10912cd:	mov    $0x1,%r9b
 10912d0:	cmp    %r10,%rsi
 10912d3:	jge    109136b <my.sexpr_parser::next_token+0xd2b>
 10912d9:	xor    %ecx,%ecx
 10912db:	cmp    $0xffffffffffffffff,%rax
 10912df:	cmovl  %r10,%rcx
 10912e3:	add    %rsi,%rcx
 10912e6:	cmp    %r10,%rcx
 10912e9:	jae    1091e59 <my.sexpr_parser::next_token+0x1819>
 10912ef:	movzbl (%rdi,%rcx,1),%ecx
 10912f3:	mov    %ecx,%r11d
 10912f6:	and    $0xdf,%r11d
 10912fd:	add    $0xffffffbf,%r11d
 1091301:	mov    $0x1,%r9b
 1091304:	mov    $0x1,%sil
 1091307:	cmp    $0x1a,%r11d
 109130b:	jae    1091545 <my.sexpr_parser::next_token+0xf05>
 1091311:	vmovd  %ecx,%xmm0
 1091315:	vpbroadcastb %xmm0,%xmm0
 109131a:	vpcmpeqb -0x8d0a2(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 1091322:	vpmovsxbd %xmm0,%xmm0
 1091327:	vmovmskps %xmm0,%r11d
 109132b:	test   %r11d,%r11d
 109132e:	jne    10914e3 <my.sexpr_parser::next_token+0xea3>
 1091334:	mov    %ecx,%r11d
 1091337:	and    $0xfffffffd,%r11d
 109133b:	cmp    $0x2d,%r11d
 109133f:	je     10914e3 <my.sexpr_parser::next_token+0xea3>
 1091345:	mov    %ecx,%r11d
 1091348:	and    $0xfffffffb,%r11d
 109134c:	cmp    $0x2a,%r11d
 1091350:	je     10914e3 <my.sexpr_parser::next_token+0xea3>
 1091356:	add    $0xffffffd5,%ecx
 1091359:	cmp    $0x2,%cl
 109135c:	jb     10914e3 <my.sexpr_parser::next_token+0xea3>
 1091362:	test   %sil,%sil
 1091365:	jne    10914e3 <my.sexpr_parser::next_token+0xea3>
 109136b:	cmp    %r10,%rax
 109136e:	jge    10913a7 <my.sexpr_parser::next_token+0xd67>
 1091370:	cmp    %r10,%r12
 1091373:	mov    0x18(%rsp),%r13
 1091378:	mov    0x10(%rsp),%r8
 109137d:	mov    (%rsp),%r11
 1091381:	jae    1091d6c <my.sexpr_parser::next_token+0x172c>
 1091387:	cmpb   $0xa,(%rdi,%r12,1)
 109138c:	jne    10913bc <my.sexpr_parser::next_token+0xd7c>
 109138e:	mov    0x20(%rsp),%r12
 1091393:	inc    %r12
 1091396:	jo     1091dfa <my.sexpr_parser::next_token+0x17ba>
 109139c:	mov    %r12,0x8(%rdx)
 10913a0:	mov    $0x1,%ecx
 10913a5:	jmp    10913d2 <my.sexpr_parser::next_token+0xd92>
 10913a7:	mov    0x20(%rsp),%r12
 10913ac:	mov    0x18(%rsp),%r13
 10913b1:	mov    0x10(%rsp),%r8
 10913b6:	mov    (%rsp),%r11
 10913ba:	jmp    10913e1 <my.sexpr_parser::next_token+0xda1>
 10913bc:	mov    0x28(%rsp),%rsi
 10913c1:	mov    %rsi,%rcx
 10913c4:	inc    %rcx
 10913c7:	jo     1091dd8 <my.sexpr_parser::next_token+0x1798>
 10913cd:	mov    0x20(%rsp),%r12
 10913d2:	mov    %rcx,0x28(%rsp)
 10913d7:	mov    %rcx,0x10(%rdx)
 10913db:	inc    %rax
 10913de:	mov    %rax,(%rdx)
 10913e1:	test   %r9b,%r9b
 10913e4:	jne    1091429 <my.sexpr_parser::next_token+0xde9>
 10913e6:	cmp    %r10,%rax
 10913e9:	jge    1091429 <my.sexpr_parser::next_token+0xde9>
 10913eb:	mov    %rax,%rcx
 10913ee:	sar    $0x3f,%rcx
 10913f2:	and    %r10,%rcx
 10913f5:	add    %rax,%rcx
 10913f8:	cmp    %r10,%rcx
 10913fb:	mov    $0x7,%r9d
 1091401:	jae    1091d6c <my.sexpr_parser::next_token+0x172c>
 1091407:	cmpb   $0xa,(%rdi,%rcx,1)
 109140b:	mov    0x28(%rsp),%rsi
 1091410:	jne    1091437 <my.sexpr_parser::next_token+0xdf7>
 1091412:	mov    %r12,%rcx
 1091415:	inc    %rcx
 1091418:	jo     1091dff <my.sexpr_parser::next_token+0x17bf>
 109141e:	mov    %rcx,0x8(%rdx)
 1091422:	mov    $0x1,%ecx
 1091427:	jmp    1091443 <my.sexpr_parser::next_token+0xe03>
 1091429:	mov    %rbx,%rcx
 109142c:	mov    $0x7,%r9d
 1091432:	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 1091437:	mov    %rsi,%rcx
 109143a:	inc    %rcx
 109143d:	jo     1091dd8 <my.sexpr_parser::next_token+0x1798>
 1091443:	mov    %rcx,0x10(%rdx)
 1091447:	inc    %rax
 109144a:	mov    %rax,(%rdx)
 109144d:	mov    %rbx,%rcx
 1091450:	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 1091455:	cmp    $0x47,%ebp
 1091458:	jg     10914d1 <my.sexpr_parser::next_token+0xe91>
 109145a:	cmp    $0x25,%ebp
 109145d:	je     10917fb <my.sexpr_parser::next_token+0x11bb>
 1091463:	cmp    $0x41,%ebp
 1091466:	je     10912c9 <my.sexpr_parser::next_token+0xc89>
 109146c:	jmp    10914e3 <my.sexpr_parser::next_token+0xea3>
 109146e:	mov    0x38(%rsp),%r12
 1091473:	mov    0x20(%rsp),%r13
 1091478:	mov    %r13,0x18(%rdx)
 109147c:	mov    %r14,0x20(%rdx)
 1091480:	mov    %rbx,0x28(%rdx)
 1091484:	lea    0x5f725(%rip),%rdi        # 10f0bb0 <core_durable_error.verbs+0x55b0>
 109148b:	call   106f880 <myl_core_err_trace_origin_preserve_most>
 1091490:	lea    -0x75077(%rip),%rax        # 101c420 <core_number_pairs+0x14ed0>
 1091497:	mov    %rax,(%rsp)
 109149b:	mov    $0x2,%ebp
 10914a0:	jmp    1090d2f <my.sexpr_parser::next_token+0x6ef>
 10914a5:	cmp    $0x2a,%rcx
 10914a9:	je     109103b <my.sexpr_parser::next_token+0x9fb>
 10914af:	cmp    $0x5f,%ecx
 10914b2:	je     109103b <my.sexpr_parser::next_token+0x9fb>
 10914b8:	cmp    $0x7e,%ecx
 10914bb:	je     109103b <my.sexpr_parser::next_token+0x9fb>
 10914c1:	lea    -0x30(%rcx),%esi
 10914c4:	cmp    $0xa,%sil
 10914c8:	setb   %sil
 10914cc:	jmp    109103b <my.sexpr_parser::next_token+0x9fb>
 10914d1:	cmp    $0x48,%ebp
 10914d4:	je     10912c9 <my.sexpr_parser::next_token+0xc89>
 10914da:	cmp    $0x52,%ebp
 10914dd:	je     10912c9 <my.sexpr_parser::next_token+0xc89>
 10914e3:	mov    %ebp,%ecx
 10914e5:	and    $0xffffffdf,%ecx
 10914e8:	add    $0xffffffbf,%ecx
 10914eb:	mov    $0x1,%sil
 10914ee:	cmp    $0x1a,%ecx
 10914f1:	jae    1091509 <my.sexpr_parser::next_token+0xec9>
 10914f3:	mov    %rbp,%r9
 10914f6:	mov    0x18(%rsp),%r13
 10914fb:	mov    0x10(%rsp),%r8
 1091500:	mov    (%rsp),%r11
 1091504:	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091509:	cmp    $0x2a,%rbp
 109150d:	mov    0x18(%rsp),%r13
 1091512:	mov    0x10(%rsp),%r8
 1091517:	mov    (%rsp),%r11
 109151b:	mov    %rbp,%r9
 109151e:	je     109178d <my.sexpr_parser::next_token+0x114d>
 1091524:	cmp    $0x5f,%ebp
 1091527:	je     109178d <my.sexpr_parser::next_token+0x114d>
 109152d:	cmp    $0x7e,%ebp
 1091530:	je     109178d <my.sexpr_parser::next_token+0x114d>
 1091536:	lea    -0x30(%rbp),%ecx
 1091539:	cmp    $0xa,%cl
 109153c:	setb   %sil
 1091540:	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091545:	cmp    $0x2a,%rcx
 1091549:	je     1091311 <my.sexpr_parser::next_token+0xcd1>
 109154f:	cmp    $0x5f,%ecx
 1091552:	je     1091311 <my.sexpr_parser::next_token+0xcd1>
 1091558:	cmp    $0x7e,%ecx
 109155b:	je     1091311 <my.sexpr_parser::next_token+0xcd1>
 1091561:	lea    -0x30(%rcx),%esi
 1091564:	cmp    $0xa,%sil
 1091568:	setb   %sil
 109156c:	jmp    1091311 <my.sexpr_parser::next_token+0xcd1>
 1091571:	lea    0x2(%rax),%rsi
 1091575:	cmp    %r10,%rsi
 1091578:	jge    109178a <my.sexpr_parser::next_token+0x114a>
 109157e:	xor    %ecx,%ecx
 1091580:	cmp    $0xfffffffffffffffe,%rax
 1091584:	cmovl  %r10,%rcx
 1091588:	add    %rsi,%rcx
 109158b:	cmp    %r10,%rcx
 109158e:	jae    1091e8e <my.sexpr_parser::next_token+0x184e>
 1091594:	cmpb   $0x6c,(%rdi,%rcx,1)
 1091598:	jne    109178a <my.sexpr_parser::next_token+0x114a>
 109159e:	lea    0x3(%rax),%r12
 10915a2:	cmp    %r10,%r12
 10915a5:	jge    1091650 <my.sexpr_parser::next_token+0x1010>
 10915ab:	mov    %r13,0x18(%rsp)
 10915b0:	xor    %ecx,%ecx
 10915b2:	cmp    $0xfffffffffffffffd,%rax
 10915b6:	cmovl  %r10,%rcx
 10915ba:	add    %r12,%rcx
 10915bd:	cmp    %r10,%rcx
 10915c0:	jae    1091ef9 <my.sexpr_parser::next_token+0x18b9>
 10915c6:	movzbl (%rdi,%rcx,1),%ecx
 10915ca:	mov    %ecx,%r14d
 10915cd:	and    $0xdf,%r14d
 10915d4:	add    $0xffffffbf,%r14d
 10915d8:	mov    $0x1,%r11b
 10915db:	cmp    $0x1a,%r14d
 10915df:	jae    1091ae0 <my.sexpr_parser::next_token+0x14a0>
 10915e5:	vmovd  %ecx,%xmm0
 10915e9:	vpbroadcastb %xmm0,%xmm0
 10915ee:	vpcmpeqb -0x8d376(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 10915f6:	vpmovsxbd %xmm0,%xmm0
 10915fb:	vmovmskps %xmm0,%r14d
 10915ff:	test   %r14d,%r14d
 1091602:	jne    1091b29 <my.sexpr_parser::next_token+0x14e9>
 1091608:	mov    %ecx,%r14d
 109160b:	and    $0xfffffffd,%r14d
 109160f:	cmp    $0x2d,%r14d
 1091613:	je     1091b29 <my.sexpr_parser::next_token+0x14e9>
 1091619:	mov    %ecx,%r14d
 109161c:	and    $0xfffffffb,%r14d
 1091620:	cmp    $0x2a,%r14d
 1091624:	je     1091b29 <my.sexpr_parser::next_token+0x14e9>
 109162a:	add    $0xffffffd5,%ecx
 109162d:	cmp    $0x2,%cl
 1091630:	jb     1091b29 <my.sexpr_parser::next_token+0x14e9>
 1091636:	test   %r11b,%r11b
 1091639:	mov    0x18(%rsp),%r13
 109163e:	mov    (%rsp),%r11
 1091642:	mov    0x8(%rsp),%r14
 1091647:	mov    $0x1,%sil
 109164a:	jne    109178d <my.sexpr_parser::next_token+0x114d>
 1091650:	mov    0x28(%rsp),%r10
 1091655:	inc    %r10
 1091658:	jo     1091ecf <my.sexpr_parser::next_token+0x188f>
 109165e:	mov    %r10,0x10(%rdx)
 1091662:	lea    0x1(%rax),%rcx
 1091666:	mov    %rcx,(%rdx)
 1091669:	mov    %r10,%rsi
 109166c:	inc    %rsi
 109166f:	jo     1091ee5 <my.sexpr_parser::next_token+0x18a5>
 1091675:	mov    %rsi,0x10(%rdx)
 1091679:	lea    0x2(%rax),%rcx
 109167d:	mov    %rcx,(%rdx)
 1091680:	mov    %rsi,%rcx
 1091683:	inc    %rcx
 1091686:	mov    $0x6,%r9d
 109168c:	mov    0x8(%rsp),%r14
 1091691:	jno    1091ad7 <my.sexpr_parser::next_token+0x1497>
 1091697:	lea    0x602c2(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 109169e:	mov    $0x1,%edx
 10916a3:	call   103d4c0 <myl_core_trap>
 10916a8:	mov    %r13,0x18(%rsp)
 10916ad:	mov    %ecx,%r11d
 10916b0:	and    $0xef,%r11b
 10916b4:	cmp    $0x46,%r11b
 10916b8:	je     10916d6 <my.sexpr_parser::next_token+0x1096>
 10916ba:	add    $0xffffffbf,%ecx
 10916bd:	cmp    $0x11,%ecx
 10916c0:	ja     10919fd <my.sexpr_parser::next_token+0x13bd>
 10916c6:	mov    $0x20081,%r11d
 10916cc:	bt     %ecx,%r11d
 10916d0:	jae    10919fd <my.sexpr_parser::next_token+0x13bd>
 10916d6:	lea    0x2(%rax),%rsi
 10916da:	cmp    %r10,%rsi
 10916dd:	jge    1091095 <my.sexpr_parser::next_token+0xa55>
 10916e3:	xor    %ecx,%ecx
 10916e5:	cmp    $0xfffffffffffffffe,%rax
 10916e9:	cmovl  %r10,%rcx
 10916ed:	add    %rsi,%rcx
 10916f0:	cmp    %r10,%rcx
 10916f3:	jae    1091eae <my.sexpr_parser::next_token+0x186e>
 10916f9:	movzbl (%rdi,%rcx,1),%ecx
 10916fd:	mov    %ecx,%r14d
 1091700:	and    $0xdf,%r14d
 1091707:	add    $0xffffffbf,%r14d
 109170b:	mov    $0x1,%sil
 109170e:	mov    $0x1,%r11b
 1091711:	cmp    $0x1a,%r14d
 1091715:	jae    10919d0 <my.sexpr_parser::next_token+0x1390>
 109171b:	vmovd  %ecx,%xmm0
 109171f:	vpbroadcastb %xmm0,%xmm0
 1091724:	vpcmpeqb -0x8d4ac(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 109172c:	vpmovsxbd %xmm0,%xmm0
 1091731:	vmovmskps %xmm0,%r14d
 1091735:	test   %r14d,%r14d
 1091738:	jne    1091a36 <my.sexpr_parser::next_token+0x13f6>
 109173e:	mov    %ecx,%r14d
 1091741:	and    $0xfffffffd,%r14d
 1091745:	cmp    $0x2d,%r14d
 1091749:	je     1091a36 <my.sexpr_parser::next_token+0x13f6>
 109174f:	mov    %ecx,%r14d
 1091752:	and    $0xfffffffb,%r14d
 1091756:	cmp    $0x2a,%r14d
 109175a:	je     1091a36 <my.sexpr_parser::next_token+0x13f6>
 1091760:	add    $0xffffffd5,%ecx
 1091763:	cmp    $0x2,%cl
 1091766:	mov    0x8(%rsp),%r14
 109176b:	jb     10914f6 <my.sexpr_parser::next_token+0xeb6>
 1091771:	test   %r11b,%r11b
 1091774:	mov    0x18(%rsp),%r13
 1091779:	mov    0x10(%rsp),%r8
 109177e:	mov    (%rsp),%r11
 1091782:	je     1091095 <my.sexpr_parser::next_token+0xa55>
 1091788:	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 109178a:	mov    $0x1,%sil
 109178d:	vmovd  %ebp,%xmm0
 1091791:	vpbroadcastb %xmm0,%xmm0
 1091796:	vpcmpeqb -0x8d51e(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 109179e:	vpmovsxbd %xmm0,%xmm0
 10917a3:	vmovmskps %xmm0,%ecx
 10917a7:	test   %ecx,%ecx
 10917a9:	jne    1091883 <my.sexpr_parser::next_token+0x1243>
 10917af:	mov    %r9d,%ecx
 10917b2:	and    $0xfffffffd,%ecx
 10917b5:	cmp    $0x2d,%ecx
 10917b8:	mov    0x20(%rsp),%r12
 10917bd:	je     109187c <my.sexpr_parser::next_token+0x123c>
 10917c3:	and    $0xfffffffb,%r9d
 10917c7:	cmp    $0x2a,%r9d
 10917cb:	je     109188f <my.sexpr_parser::next_token+0x124f>
 10917d1:	mov    %esi,%r9d
 10917d4:	lea    -0x2b(%rbp),%ecx
 10917d7:	cmp    $0x2,%cl
 10917da:	mov    0x28(%rsp),%rsi
 10917df:	jb     10918c6 <my.sexpr_parser::next_token+0x1286>
 10917e5:	mov    %rbx,%rcx
 10917e8:	test   %r9b,%r9b
 10917eb:	mov    0x30(%rsp),%r9
 10917f0:	je     1090aa7 <my.sexpr_parser::next_token+0x467>
 10917f6:	jmp    10918c6 <my.sexpr_parser::next_token+0x1286>
 10917fb:	lea    0x1(%rax),%r12
 10917ff:	cmp    %r10,%r12
 1091802:	mov    0x18(%rsp),%r13
 1091807:	mov    0x10(%rsp),%r8
 109180c:	mov    (%rsp),%r11
 1091810:	jge    1091abd <my.sexpr_parser::next_token+0x147d>
 1091816:	xor    %ecx,%ecx
 1091818:	cmp    $0xffffffffffffffff,%rax
 109181c:	cmovl  %r10,%rcx
 1091820:	add    %r12,%rcx
 1091823:	cmp    %r10,%rcx
 1091826:	jae    1091ebd <my.sexpr_parser::next_token+0x187d>
 109182c:	movzbl (%rdi,%rcx,1),%ecx
 1091830:	mov    %ecx,%r11d
 1091833:	and    $0xdf,%r11d
 109183a:	add    $0xffffffbf,%r11d
 109183e:	mov    $0x1,%sil
 1091841:	cmp    $0x1a,%r11d
 1091845:	jb     1091a53 <my.sexpr_parser::next_token+0x1413>
 109184b:	cmp    $0x2a,%rcx
 109184f:	je     1091a4e <my.sexpr_parser::next_token+0x140e>
 1091855:	cmp    $0x5f,%ecx
 1091858:	je     1091a4e <my.sexpr_parser::next_token+0x140e>
 109185e:	cmp    $0x7e,%ecx
 1091861:	mov    0x8(%rsp),%r14
 1091866:	je     1091a53 <my.sexpr_parser::next_token+0x1413>
 109186c:	lea    -0x30(%rcx),%esi
 109186f:	cmp    $0xa,%sil
 1091873:	setb   %sil
 1091877:	jmp    1091a53 <my.sexpr_parser::next_token+0x1413>
 109187c:	mov    0x28(%rsp),%rsi
 1091881:	jmp    10918c6 <my.sexpr_parser::next_token+0x1286>
 1091883:	mov    0x20(%rsp),%r12
 1091888:	mov    0x28(%rsp),%rsi
 109188d:	jmp    10918c6 <my.sexpr_parser::next_token+0x1286>
 109188f:	mov    0x28(%rsp),%rsi
 1091894:	jmp    10918c6 <my.sexpr_parser::next_token+0x1286>
 1091896:	mov    %rsi,%rcx
 1091899:	inc    %rcx
 109189c:	jo     1091d49 <my.sexpr_parser::next_token+0x1709>
 10918a2:	mov    %rcx,%rsi
 10918a5:	mov    %r14,%r11
 10918a8:	mov    %rsi,0x10(%rdx)
 10918ac:	inc    %rax
 10918af:	mov    %rax,(%rdx)
 10918b2:	cmp    %rax,%r10
 10918b5:	mov    0x8(%rsp),%r14
 10918ba:	mov    $0x2,%r9d
 10918c0:	je     1091998 <my.sexpr_parser::next_token+0x1358>
 10918c6:	mov    %rax,%rcx
 10918c9:	sar    $0x3f,%rcx
 10918cd:	and    %r10,%rcx
 10918d0:	lea    (%rcx,%rax,1),%r9
 10918d4:	cmp    %r10,%r9
 10918d7:	jae    1091cd8 <my.sexpr_parser::next_token+0x1698>
 10918dd:	mov    %r11,%r14
 10918e0:	add    %rdi,%rcx
 10918e3:	movzbl (%rax,%rcx,1),%ecx
 10918e7:	mov    %ecx,%r11d
 10918ea:	and    $0xdf,%r11d
 10918f1:	add    $0xffffffbf,%r11d
 10918f5:	mov    $0x1,%bpl
 10918f8:	cmp    $0x1a,%r11d
 10918fc:	jae    109196c <my.sexpr_parser::next_token+0x132c>
 10918fe:	vmovd  %ecx,%xmm0
 1091902:	vpbroadcastb %xmm0,%xmm0
 1091907:	vpcmpeqb -0x8d68f(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 109190f:	vpmovsxbd %xmm0,%xmm0
 1091914:	vmovmskps %xmm0,%r11d
 1091918:	test   %r11d,%r11d
 109191b:	jne    1091946 <my.sexpr_parser::next_token+0x1306>
 109191d:	mov    %ecx,%r11d
 1091920:	and    $0xfffffffd,%r11d
 1091924:	cmp    $0x2d,%r11d
 1091928:	je     1091946 <my.sexpr_parser::next_token+0x1306>
 109192a:	mov    %ecx,%r11d
 109192d:	and    $0xfffffffb,%r11d
 1091931:	cmp    $0x2a,%r11d
 1091935:	je     1091946 <my.sexpr_parser::next_token+0x1306>
 1091937:	lea    -0x2b(%rcx),%r11d
 109193b:	cmp    $0x2,%r11b
 109193f:	jb     1091946 <my.sexpr_parser::next_token+0x1306>
 1091941:	test   %bpl,%bpl
 1091944:	je     109198d <my.sexpr_parser::next_token+0x134d>
 1091946:	cmp    $0xa,%ecx
 1091949:	jne    1091896 <my.sexpr_parser::next_token+0x1256>
 109194f:	mov    %r12,%rcx
 1091952:	inc    %rcx
 1091955:	jo     1091d35 <my.sexpr_parser::next_token+0x16f5>
 109195b:	mov    %rcx,0x8(%rdx)
 109195f:	mov    $0x1,%esi
 1091964:	mov    %rcx,%r12
 1091967:	jmp    10918a5 <my.sexpr_parser::next_token+0x1265>
 109196c:	cmp    $0x2a,%rcx
 1091970:	je     10918fe <my.sexpr_parser::next_token+0x12be>
 1091972:	cmp    $0x5f,%ecx
 1091975:	je     10918fe <my.sexpr_parser::next_token+0x12be>
 1091977:	cmp    $0x7e,%ecx
 109197a:	je     10918fe <my.sexpr_parser::next_token+0x12be>
 109197c:	lea    -0x30(%rcx),%r11d
 1091980:	cmp    $0xa,%r11b
 1091984:	setb   %bpl
 1091988:	jmp    10918fe <my.sexpr_parser::next_token+0x12be>
 109198d:	mov    %rbx,%rcx
 1091990:	mov    %r14,%r11
 1091993:	jmp    10910b6 <my.sexpr_parser::next_token+0xa76>
 1091998:	mov    %r10,%rax
 109199b:	mov    %rbx,%rcx
 109199e:	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 10919a3:	cmp    $0x2a,%rcx
 10919a7:	je     10911e8 <my.sexpr_parser::next_token+0xba8>
 10919ad:	cmp    $0x5f,%ecx
 10919b0:	je     10911e8 <my.sexpr_parser::next_token+0xba8>
 10919b6:	cmp    $0x7e,%ecx
 10919b9:	je     10911e8 <my.sexpr_parser::next_token+0xba8>
 10919bf:	lea    -0x30(%rcx),%r11d
 10919c3:	cmp    $0xa,%r11b
 10919c7:	setb   %r11b
 10919cb:	jmp    10911e8 <my.sexpr_parser::next_token+0xba8>
 10919d0:	cmp    $0x2a,%rcx
 10919d4:	je     109171b <my.sexpr_parser::next_token+0x10db>
 10919da:	cmp    $0x5f,%ecx
 10919dd:	je     109171b <my.sexpr_parser::next_token+0x10db>
 10919e3:	cmp    $0x7e,%ecx
 10919e6:	je     109171b <my.sexpr_parser::next_token+0x10db>
 10919ec:	lea    -0x30(%rcx),%r11d
 10919f0:	cmp    $0xa,%r11b
 10919f4:	setb   %r11b
 10919f8:	jmp    109171b <my.sexpr_parser::next_token+0x10db>
 10919fd:	mov    0x18(%rsp),%r13
 1091a02:	mov    0x10(%rsp),%r8
 1091a07:	mov    (%rsp),%r11
 1091a0b:	mov    $0x1,%sil
 1091a0e:	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091a13:	lea    0x5feb6(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091a1a:	mov    %rbx,%rsi
 1091a1d:	mov    %r10,%rdx
 1091a20:	call   103d4c0 <myl_core_trap>
 1091a25:	lea    0x5ff34(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091a2c:	mov    $0x1,%edx
 1091a31:	call   103d4c0 <myl_core_trap>
 1091a36:	mov    0x18(%rsp),%r13
 1091a3b:	mov    0x10(%rsp),%r8
 1091a40:	mov    (%rsp),%r11
 1091a44:	mov    0x8(%rsp),%r14
 1091a49:	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091a4e:	mov    0x8(%rsp),%r14
 1091a53:	vmovd  %ecx,%xmm0
 1091a57:	vpbroadcastb %xmm0,%xmm0
 1091a5c:	vpcmpeqb -0x8d7e4(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 1091a64:	vpmovsxbd %xmm0,%xmm0
 1091a69:	vmovmskps %xmm0,%r11d
 1091a6d:	mov    $0x25,%r9d
 1091a73:	test   %r11d,%r11d
 1091a76:	jne    1091b0d <my.sexpr_parser::next_token+0x14cd>
 1091a7c:	mov    %ecx,%r11d
 1091a7f:	and    $0xfffffffd,%r11d
 1091a83:	cmp    $0x2d,%r11d
 1091a87:	je     1091b0d <my.sexpr_parser::next_token+0x14cd>
 1091a8d:	mov    %ecx,%r11d
 1091a90:	and    $0xfffffffb,%r11d
 1091a94:	cmp    $0x2a,%r11d
 1091a98:	je     1091b0d <my.sexpr_parser::next_token+0x14cd>
 1091a9a:	add    $0xffffffd5,%ecx
 1091a9d:	cmp    $0x2,%cl
 1091aa0:	mov    0x18(%rsp),%r13
 1091aa5:	mov    0x10(%rsp),%r8
 1091aaa:	mov    (%rsp),%r11
 1091aae:	jb     1091536 <my.sexpr_parser::next_token+0xef6>
 1091ab4:	test   %sil,%sil
 1091ab7:	jne    1091536 <my.sexpr_parser::next_token+0xef6>
 1091abd:	mov    0x28(%rsp),%rsi
 1091ac2:	mov    %rsi,%rcx
 1091ac5:	inc    %rcx
 1091ac8:	mov    $0x7,%r9d
 1091ace:	mov    %r12,%rax
 1091ad1:	jo     1091e9d <my.sexpr_parser::next_token+0x185d>
 1091ad7:	mov    %rcx,0x10(%rdx)
 1091adb:	jmp    1090861 <my.sexpr_parser::next_token+0x221>
 1091ae0:	cmp    $0x2a,%rcx
 1091ae4:	je     10915e5 <my.sexpr_parser::next_token+0xfa5>
 1091aea:	cmp    $0x5f,%ecx
 1091aed:	je     10915e5 <my.sexpr_parser::next_token+0xfa5>
 1091af3:	cmp    $0x7e,%ecx
 1091af6:	je     10915e5 <my.sexpr_parser::next_token+0xfa5>
 1091afc:	lea    -0x30(%rcx),%r11d
 1091b00:	cmp    $0xa,%r11b
 1091b04:	setb   %r11b
 1091b08:	jmp    10915e5 <my.sexpr_parser::next_token+0xfa5>
 1091b0d:	mov    0x18(%rsp),%r13
 1091b12:	mov    0x10(%rsp),%r8
 1091b17:	mov    (%rsp),%r11
 1091b1b:	jmp    1091536 <my.sexpr_parser::next_token+0xef6>
 1091b20:	mov    (%rsp),%r11
 1091b24:	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091b29:	mov    0x18(%rsp),%r13
 1091b2e:	mov    (%rsp),%r11
 1091b32:	mov    0x8(%rsp),%r14
 1091b37:	mov    $0x1,%sil
 1091b3a:	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091b3f:	lea    0x5fdba(%rip),%rdi        # 10f1900 <core_durable_error.verbs+0x6300>
 1091b46:	mov    %rbx,%rsi
 1091b49:	mov    %r10,%rdx
 1091b4c:	call   103d4c0 <myl_core_trap>
 1091b51:	lea    0x5fd78(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091b58:	mov    %rax,%rsi
 1091b5b:	mov    %r10,%rdx
 1091b5e:	call   103d4c0 <myl_core_trap>
 1091b63:	lea    0x5fdc6(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091b6a:	mov    $0x1,%edx
 1091b6f:	call   103d4c0 <myl_core_trap>
 1091b74:	lea    0x5fde5(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091b7b:	mov    $0x1,%edx
 1091b80:	call   103d4c0 <myl_core_trap>
 1091b85:	lea    0x5fd44(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091b8c:	mov    %rbx,%rsi
 1091b8f:	mov    %r10,%rdx
 1091b92:	call   103d4c0 <myl_core_trap>
 1091b97:	lea    0x5fdc2(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091b9e:	mov    $0x1,%edx
 1091ba3:	mov    %r12,%rsi
 1091ba6:	call   103d4c0 <myl_core_trap>
 1091bab:	lea    0x5fd7e(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091bb2:	mov    $0x1,%edx
 1091bb7:	mov    %r11,%rsi
 1091bba:	call   103d4c0 <myl_core_trap>
 1091bbf:	lea    0x5fd3a(%rip),%rdi        # 10f1900 <core_durable_error.verbs+0x6300>
 1091bc6:	mov    %rbp,%rsi
 1091bc9:	mov    %r10,%rdx
 1091bcc:	call   103d4c0 <myl_core_trap>
 1091bd1:	lea    0x5fd88(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091bd8:	mov    $0x1,%edx
 1091bdd:	mov    %r12,%rsi
 1091be0:	call   103d4c0 <myl_core_trap>
 1091be5:	lea    0x5fd44(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091bec:	mov    $0x1,%edx
 1091bf1:	mov    %r11,%rsi
 1091bf4:	call   103d4c0 <myl_core_trap>
 1091bf9:	lea    0x5fd60(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091c00:	mov    $0x1,%edx
 1091c05:	mov    %r13,%rsi
 1091c08:	call   103d4c0 <myl_core_trap>
 1091c0d:	lea    0x5fcbc(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091c14:	mov    %r15,%rsi
 1091c17:	mov    %r10,%rdx
 1091c1a:	call   103d4c0 <myl_core_trap>
 1091c1f:	lea    0x5fd3a(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091c26:	movabs $0x7fffffffffffffff,%rsi
 1091c30:	mov    $0x1,%edx
 1091c35:	call   103d4c0 <myl_core_trap>
 1091c3a:	lea    0x5fc8f(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091c41:	mov    %rbx,%rsi
 1091c44:	mov    %r10,%rdx
 1091c47:	call   103d4c0 <myl_core_trap>
 1091c4c:	lea    0x5fc7d(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091c53:	mov    %rax,%rsi
 1091c56:	mov    %r10,%rdx
 1091c59:	call   103d4c0 <myl_core_trap>
 1091c5e:	lea    0x5fccb(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091c65:	mov    $0x1,%edx
 1091c6a:	mov    %r11,%rsi
 1091c6d:	call   103d4c0 <myl_core_trap>
 1091c72:	lea    0x5fce7(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091c79:	mov    $0x1,%edx
 1091c7e:	mov    %r12,%rsi
 1091c81:	call   103d4c0 <myl_core_trap>
 1091c86:	lea    0x5fcd3(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091c8d:	mov    $0x1,%edx
 1091c92:	mov    %r14,%rsi
 1091c95:	call   103d4c0 <myl_core_trap>
 1091c9a:	lea    0x5fcbf(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ca1:	mov    $0x1,%edx
 1091ca6:	mov    %r14,%rsi
 1091ca9:	call   103d4c0 <myl_core_trap>
 1091cae:	lea    0x5fcab(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091cb5:	mov    $0x1,%edx
 1091cba:	mov    0x8(%rsp),%rsi
 1091cbf:	call   103d4c0 <myl_core_trap>
 1091cc4:	lea    0x5fc95(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ccb:	mov    $0x1,%edx
 1091cd0:	mov    %r12,%rsi
 1091cd3:	call   103d4c0 <myl_core_trap>
 1091cd8:	lea    0x5fbf1(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091cdf:	mov    %rax,%rsi
 1091ce2:	mov    %r10,%rdx
 1091ce5:	call   103d4c0 <myl_core_trap>
 1091cea:	mov    %rbp,(%rdx)
 1091ced:	lea    0x5fbdc(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091cf4:	mov    %rbp,%rsi
 1091cf7:	mov    %r10,%rdx
 1091cfa:	call   103d4c0 <myl_core_trap>
 1091cff:	sub    %r9,%rax
 1091d02:	movabs $0x7fffffffffffffff,%rsi
 1091d0c:	add    %rsi,%rax
 1091d0f:	mov    %rax,(%rdx)
 1091d12:	lea    0x5fc47(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091d19:	mov    $0x1,%edx
 1091d1e:	call   103d4c0 <myl_core_trap>
 1091d23:	lea    0x5fba6(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091d2a:	mov    %rax,%rsi
 1091d2d:	mov    %r10,%rdx
 1091d30:	call   103d4c0 <myl_core_trap>
 1091d35:	lea    0x5fbf4(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091d3c:	mov    $0x1,%edx
 1091d41:	mov    %r12,%rsi
 1091d44:	call   103d4c0 <myl_core_trap>
 1091d49:	lea    0x5fc10(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091d50:	mov    $0x1,%edx
 1091d55:	call   103d4c0 <myl_core_trap>
 1091d5a:	lea    0x5fc5f(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091d61:	mov    %rax,%rsi
 1091d64:	mov    %r10,%rdx
 1091d67:	call   103d4c0 <myl_core_trap>
 1091d6c:	lea    0x5fb8d(%rip),%rdi        # 10f1900 <core_durable_error.verbs+0x6300>
 1091d73:	mov    %rax,%rsi
 1091d76:	mov    %r10,%rdx
 1091d79:	call   103d4c0 <myl_core_trap>
 1091d7e:	lea    0x5fbab(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091d85:	mov    $0x1,%edx
 1091d8a:	call   103d4c0 <myl_core_trap>
 1091d8f:	lea    0x5fbca(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091d96:	mov    $0x1,%edx
 1091d9b:	mov    %r14,%rsi
 1091d9e:	call   103d4c0 <myl_core_trap>
 1091da3:	lea    0x5fb26(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091daa:	mov    %rax,%rsi
 1091dad:	mov    %r10,%rdx
 1091db0:	call   103d4c0 <myl_core_trap>
 1091db5:	lea    0x5fc04(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091dbc:	mov    %r10,%rdx
 1091dbf:	call   103d4c0 <myl_core_trap>
 1091dc4:	lea    0x5fb95(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091dcb:	mov    $0x1,%edx
 1091dd0:	mov    %r14,%rsi
 1091dd3:	call   103d4c0 <myl_core_trap>
 1091dd8:	lea    0x5fb81(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ddf:	mov    $0x1,%edx
 1091de4:	call   103d4c0 <myl_core_trap>
 1091de9:	lea    0x5fb70(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091df0:	mov    $0x1,%edx
 1091df5:	call   103d4c0 <myl_core_trap>
 1091dfa:	mov    0x20(%rsp),%r12
 1091dff:	lea    0x5fb2a(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091e06:	mov    $0x1,%edx
 1091e0b:	mov    %r12,%rsi
 1091e0e:	call   103d4c0 <myl_core_trap>
 1091e13:	lea    0x5fba6(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e1a:	mov    %rbp,%rsi
 1091e1d:	mov    %r10,%rdx
 1091e20:	call   103d4c0 <myl_core_trap>
 1091e25:	lea    0x5fb34(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091e2c:	mov    $0x1,%edx
 1091e31:	call   103d4c0 <myl_core_trap>
 1091e36:	lea    0x5fb83(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e3d:	mov    %r10,%rdx
 1091e40:	call   103d4c0 <myl_core_trap>
 1091e45:	lea    0x5fb74(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e4c:	mov    0x40(%rsp),%rsi
 1091e51:	mov    %r10,%rdx
 1091e54:	call   103d4c0 <myl_core_trap>
 1091e59:	lea    0x5fb60(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e60:	mov    %r10,%rdx
 1091e63:	call   103d4c0 <myl_core_trap>
 1091e68:	lea    0x5faf1(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091e6f:	mov    $0x1,%edx
 1091e74:	mov    %rcx,%rsi
 1091e77:	call   103d4c0 <myl_core_trap>
 1091e7c:	lea    0x5fb3d(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e83:	mov    %r12,%rsi
 1091e86:	mov    %r10,%rdx
 1091e89:	call   103d4c0 <myl_core_trap>
 1091e8e:	lea    0x5fb2b(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e95:	mov    %r10,%rdx
 1091e98:	call   103d4c0 <myl_core_trap>
 1091e9d:	lea    0x5fabc(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ea4:	mov    $0x1,%edx
 1091ea9:	call   103d4c0 <myl_core_trap>
 1091eae:	lea    0x5fb0b(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091eb5:	mov    %r10,%rdx
 1091eb8:	call   103d4c0 <myl_core_trap>
 1091ebd:	lea    0x5fafc(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091ec4:	mov    %r12,%rsi
 1091ec7:	mov    %r10,%rdx
 1091eca:	call   103d4c0 <myl_core_trap>
 1091ecf:	lea    0x5fa8a(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ed6:	mov    $0x1,%edx
 1091edb:	mov    0x28(%rsp),%rsi
 1091ee0:	call   103d4c0 <myl_core_trap>
 1091ee5:	lea    0x5fa74(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091eec:	mov    $0x1,%edx
 1091ef1:	mov    %r10,%rsi
 1091ef4:	call   103d4c0 <myl_core_trap>
 1091ef9:	lea    0x5fac0(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091f00:	mov    %r12,%rsi
 1091f03:	mov    %r10,%rdx
 1091f06:	call   103d4c0 <myl_core_trap>

Disassembly of section .plt:
