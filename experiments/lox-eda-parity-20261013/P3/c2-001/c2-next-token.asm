
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/P6/native-002/eda/zero-rc:     file format elf64-x86-64


Disassembly of section .text:

0000000001090640 <my.sexpr_parser::next_token>:
 1090640:	55                   	push   %rbp
 1090641:	41 57                	push   %r15
 1090643:	41 56                	push   %r14
 1090645:	41 55                	push   %r13
 1090647:	41 54                	push   %r12
 1090649:	53                   	push   %rbx
 109064a:	48 83 ec 48          	sub    $0x48,%rsp
 109064e:	4d 89 cd             	mov    %r9,%r13
 1090651:	49 89 cb             	mov    %rcx,%r11
 1090654:	49 89 f4             	mov    %rsi,%r12
 1090657:	48 89 7c 24 38       	mov    %rdi,0x38(%rsp)
 109065c:	4c 8b bc 24 80 00 00 	mov    0x80(%rsp),%r15
 1090663:	00 
 1090664:	4c 8b 56 08          	mov    0x8(%rsi),%r10
 1090668:	48 8b 1a             	mov    (%rdx),%rbx
 109066b:	48 8d 7e 20          	lea    0x20(%rsi),%rdi
 109066f:	48 b8 00 26 00 00 01 	movabs $0x100002600,%rax
 1090676:	00 00 00 
 1090679:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1090680:	48 c7 c1 ff ff ff ff 	mov    $0xffffffffffffffff,%rcx
 1090687:	4c 39 d3             	cmp    %r10,%rbx
 109068a:	7d 28                	jge    10906b4 <my.sexpr_parser::next_token+0x74>
 109068c:	48 89 d9             	mov    %rbx,%rcx
 109068f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1090693:	4c 21 d1             	and    %r10,%rcx
 1090696:	48 01 d9             	add    %rbx,%rcx
 1090699:	4c 39 d1             	cmp    %r10,%rcx
 109069c:	0f 83 e3 14 00 00    	jae    1091b85 <my.sexpr_parser::next_token+0x1545>
 10906a2:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10906a9:	1f 84 00 00 00 00 00 
 10906b0:	0f b6 0c 0f          	movzbl (%rdi,%rcx,1),%ecx
 10906b4:	48 83 f9 3b          	cmp    $0x3b,%rcx
 10906b8:	0f 87 19 01 00 00    	ja     10907d7 <my.sexpr_parser::next_token+0x197>
 10906be:	48 0f a3 c8          	bt     %rcx,%rax
 10906c2:	73 4c                	jae    1090710 <my.sexpr_parser::next_token+0xd0>
 10906c4:	4c 39 d3             	cmp    %r10,%rbx
 10906c7:	0f 8d dd 00 00 00    	jge    10907aa <my.sexpr_parser::next_token+0x16a>
 10906cd:	48 89 d9             	mov    %rbx,%rcx
 10906d0:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10906d4:	4c 21 d1             	and    %r10,%rcx
 10906d7:	48 01 d9             	add    %rbx,%rcx
 10906da:	4c 39 d1             	cmp    %r10,%rcx
 10906dd:	0f 83 5c 14 00 00    	jae    1091b3f <my.sexpr_parser::next_token+0x14ff>
 10906e3:	80 3c 0f 0a          	cmpb   $0xa,(%rdi,%rcx,1)
 10906e7:	0f 85 a3 00 00 00    	jne    1090790 <my.sexpr_parser::next_token+0x150>
 10906ed:	48 8b 72 08          	mov    0x8(%rdx),%rsi
 10906f1:	48 89 f1             	mov    %rsi,%rcx
 10906f4:	48 ff c1             	inc    %rcx
 10906f7:	0f 80 66 14 00 00    	jo     1091b63 <my.sexpr_parser::next_token+0x1523>
 10906fd:	48 89 4a 08          	mov    %rcx,0x8(%rdx)
 1090701:	b9 01 00 00 00       	mov    $0x1,%ecx
 1090706:	e9 95 00 00 00       	jmp    10907a0 <my.sexpr_parser::next_token+0x160>
 109070b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1090710:	48 83 f9 3b          	cmp    $0x3b,%rcx
 1090714:	0f 85 bd 00 00 00    	jne    10907d7 <my.sexpr_parser::next_token+0x197>
 109071a:	4c 39 d3             	cmp    %r10,%rbx
 109071d:	0f 8d 5d ff ff ff    	jge    1090680 <my.sexpr_parser::next_token+0x40>
 1090723:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109072a:	0f 1f 84 00 00 00 00 
 1090731:	00 
 1090732:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090739:	1f 84 00 00 00 00 00 
 1090740:	48 89 d9             	mov    %rbx,%rcx
 1090743:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1090747:	4c 21 d1             	and    %r10,%rcx
 109074a:	48 8d 34 19          	lea    (%rcx,%rbx,1),%rsi
 109074e:	4c 39 d6             	cmp    %r10,%rsi
 1090751:	0f 83 bc 12 00 00    	jae    1091a13 <my.sexpr_parser::next_token+0x13d3>
 1090757:	48 01 f9             	add    %rdi,%rcx
 109075a:	80 3c 0b 0a          	cmpb   $0xa,(%rbx,%rcx,1)
 109075e:	0f 84 1c ff ff ff    	je     1090680 <my.sexpr_parser::next_token+0x40>
 1090764:	48 8b 72 10          	mov    0x10(%rdx),%rsi
 1090768:	48 89 f1             	mov    %rsi,%rcx
 109076b:	48 ff c1             	inc    %rcx
 109076e:	0f 80 b1 12 00 00    	jo     1091a25 <my.sexpr_parser::next_token+0x13e5>
 1090774:	48 89 4a 10          	mov    %rcx,0x10(%rdx)
 1090778:	48 ff c3             	inc    %rbx
 109077b:	48 89 1a             	mov    %rbx,(%rdx)
 109077e:	49 39 da             	cmp    %rbx,%r10
 1090781:	75 bd                	jne    1090740 <my.sexpr_parser::next_token+0x100>
 1090783:	4c 89 d3             	mov    %r10,%rbx
 1090786:	e9 f5 fe ff ff       	jmp    1090680 <my.sexpr_parser::next_token+0x40>
 109078b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1090790:	48 8b 72 10          	mov    0x10(%rdx),%rsi
 1090794:	48 89 f1             	mov    %rsi,%rcx
 1090797:	48 ff c1             	inc    %rcx
 109079a:	0f 80 d4 13 00 00    	jo     1091b74 <my.sexpr_parser::next_token+0x1534>
 10907a0:	48 89 4a 10          	mov    %rcx,0x10(%rdx)
 10907a4:	48 ff c3             	inc    %rbx
 10907a7:	48 89 1a             	mov    %rbx,(%rdx)
 10907aa:	4c 39 d3             	cmp    %r10,%rbx
 10907ad:	7d 28                	jge    10907d7 <my.sexpr_parser::next_token+0x197>
 10907af:	48 89 d9             	mov    %rbx,%rcx
 10907b2:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10907b6:	4c 21 d1             	and    %r10,%rcx
 10907b9:	48 01 d9             	add    %rbx,%rcx
 10907bc:	4c 39 d1             	cmp    %r10,%rcx
 10907bf:	0f 82 eb fe ff ff    	jb     10906b0 <my.sexpr_parser::next_token+0x70>
 10907c5:	48 8d 3d 04 11 06 00 	lea    0x61104(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 10907cc:	48 89 de             	mov    %rbx,%rsi
 10907cf:	4c 89 d2             	mov    %r10,%rdx
 10907d2:	e8 e9 cc fa ff       	call   103d4c0 <myl_core_trap>
 10907d7:	48 8b 42 08          	mov    0x8(%rdx),%rax
 10907db:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 10907e0:	4c 8b 72 10          	mov    0x10(%rdx),%r14
 10907e4:	41 b9 08 00 00 00    	mov    $0x8,%r9d
 10907ea:	48 89 d8             	mov    %rbx,%rax
 10907ed:	48 89 d9             	mov    %rbx,%rcx
 10907f0:	4c 39 d3             	cmp    %r10,%rbx
 10907f3:	0f 8d ae 02 00 00    	jge    1090aa7 <my.sexpr_parser::next_token+0x467>
 10907f9:	48 89 d8             	mov    %rbx,%rax
 10907fc:	48 c1 f8 3f          	sar    $0x3f,%rax
 1090800:	4c 21 d0             	and    %r10,%rax
 1090803:	48 01 d8             	add    %rbx,%rax
 1090806:	4c 39 d0             	cmp    %r10,%rax
 1090809:	0f 83 2b 14 00 00    	jae    1091c3a <my.sexpr_parser::next_token+0x15fa>
 109080f:	0f b6 0c 07          	movzbl (%rdi,%rax,1),%ecx
 1090813:	83 f9 22             	cmp    $0x22,%ecx
 1090816:	4c 89 74 24 08       	mov    %r14,0x8(%rsp)
 109081b:	74 4c                	je     1090869 <my.sexpr_parser::next_token+0x229>
 109081d:	83 f9 29             	cmp    $0x29,%ecx
 1090820:	74 22                	je     1090844 <my.sexpr_parser::next_token+0x204>
 1090822:	83 f9 28             	cmp    $0x28,%ecx
 1090825:	0f 85 90 01 00 00    	jne    10909bb <my.sexpr_parser::next_token+0x37b>
 109082b:	4c 89 f0             	mov    %r14,%rax
 109082e:	48 ff c0             	inc    %rax
 1090831:	0f 80 4f 14 00 00    	jo     1091c86 <my.sexpr_parser::next_token+0x1646>
 1090837:	48 89 42 10          	mov    %rax,0x10(%rdx)
 109083b:	4c 8d 63 01          	lea    0x1(%rbx),%r12
 109083f:	45 31 c9             	xor    %r9d,%r9d
 1090842:	eb 1a                	jmp    109085e <my.sexpr_parser::next_token+0x21e>
 1090844:	4c 89 f0             	mov    %r14,%rax
 1090847:	48 ff c0             	inc    %rax
 109084a:	0f 80 4a 14 00 00    	jo     1091c9a <my.sexpr_parser::next_token+0x165a>
 1090850:	48 89 42 10          	mov    %rax,0x10(%rdx)
 1090854:	4c 8d 63 01          	lea    0x1(%rbx),%r12
 1090858:	41 b9 01 00 00 00    	mov    $0x1,%r9d
 109085e:	4c 89 e0             	mov    %r12,%rax
 1090861:	48 89 d9             	mov    %rbx,%rcx
 1090864:	e9 3b 02 00 00       	jmp    1090aa4 <my.sexpr_parser::next_token+0x464>
 1090869:	4d 89 f4             	mov    %r14,%r12
 109086c:	49 ff c4             	inc    %r12
 109086f:	0f 80 39 14 00 00    	jo     1091cae <my.sexpr_parser::next_token+0x166e>
 1090875:	4c 89 62 10          	mov    %r12,0x10(%rdx)
 1090879:	48 8d 4b 01          	lea    0x1(%rbx),%rcx
 109087d:	48 89 0a             	mov    %rcx,(%rdx)
 1090880:	4c 39 d1             	cmp    %r10,%rcx
 1090883:	0f 8d 63 04 00 00    	jge    1090cec <my.sexpr_parser::next_token+0x6ac>
 1090889:	4d 89 de             	mov    %r11,%r14
 109088c:	4d 89 e9             	mov    %r13,%r9
 109088f:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 1090894:	48 89 c8             	mov    %rcx,%rax
 1090897:	eb 51                	jmp    10908ea <my.sexpr_parser::next_token+0x2aa>
 1090899:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10908a0:	0f 1f 84 00 00 00 00 
 10908a7:	00 
 10908a8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10908af:	0f 1f 84 00 00 00 00 
 10908b6:	00 
 10908b7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10908be:	00 00 
 10908c0:	4d 89 e5             	mov    %r12,%r13
 10908c3:	49 ff c5             	inc    %r13
 10908c6:	0f 80 05 13 00 00    	jo     1091bd1 <my.sexpr_parser::next_token+0x1591>
 10908cc:	bd 01 00 00 00       	mov    $0x1,%ebp
 10908d1:	4c 89 6a 10          	mov    %r13,0x10(%rdx)
 10908d5:	48 01 c5             	add    %rax,%rbp
 10908d8:	48 89 2a             	mov    %rbp,(%rdx)
 10908db:	4d 89 ec             	mov    %r13,%r12
 10908de:	48 89 e8             	mov    %rbp,%rax
 10908e1:	4c 39 d5             	cmp    %r10,%rbp
 10908e4:	0f 8d 02 04 00 00    	jge    1090cec <my.sexpr_parser::next_token+0x6ac>
 10908ea:	48 89 c6             	mov    %rax,%rsi
 10908ed:	48 c1 fe 3f          	sar    $0x3f,%rsi
 10908f1:	4c 21 d6             	and    %r10,%rsi
 10908f4:	48 01 c6             	add    %rax,%rsi
 10908f7:	4c 39 d6             	cmp    %r10,%rsi
 10908fa:	0f 83 51 12 00 00    	jae    1091b51 <my.sexpr_parser::next_token+0x1511>
 1090900:	0f b6 34 37          	movzbl (%rdi,%rsi,1),%esi
 1090904:	83 fe 5c             	cmp    $0x5c,%esi
 1090907:	74 37                	je     1090940 <my.sexpr_parser::next_token+0x300>
 1090909:	83 fe 22             	cmp    $0x22,%esi
 109090c:	0f 84 6d 01 00 00    	je     1090a7f <my.sexpr_parser::next_token+0x43f>
 1090912:	40 80 fe 0a          	cmp    $0xa,%sil
 1090916:	75 a8                	jne    10908c0 <my.sexpr_parser::next_token+0x280>
 1090918:	4c 89 de             	mov    %r11,%rsi
 109091b:	48 ff c6             	inc    %rsi
 109091e:	0f 80 87 12 00 00    	jo     1091bab <my.sexpr_parser::next_token+0x156b>
 1090924:	48 89 72 08          	mov    %rsi,0x8(%rdx)
 1090928:	41 bd 01 00 00 00    	mov    $0x1,%r13d
 109092e:	49 89 f3             	mov    %rsi,%r11
 1090931:	eb 99                	jmp    10908cc <my.sexpr_parser::next_token+0x28c>
 1090933:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 109093a:	84 00 00 00 00 00 
 1090940:	4d 89 e5             	mov    %r12,%r13
 1090943:	49 ff c5             	inc    %r13
 1090946:	0f 80 4b 12 00 00    	jo     1091b97 <my.sexpr_parser::next_token+0x1557>
 109094c:	4c 89 6a 10          	mov    %r13,0x10(%rdx)
 1090950:	48 8d 68 01          	lea    0x1(%rax),%rbp
 1090954:	48 89 2a             	mov    %rbp,(%rdx)
 1090957:	4c 39 d5             	cmp    %r10,%rbp
 109095a:	0f 8d 7b ff ff ff    	jge    10908db <my.sexpr_parser::next_token+0x29b>
 1090960:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 1090964:	be 00 00 00 00       	mov    $0x0,%esi
 1090969:	49 0f 4c f2          	cmovl  %r10,%rsi
 109096d:	48 01 ee             	add    %rbp,%rsi
 1090970:	4c 39 d6             	cmp    %r10,%rsi
 1090973:	0f 83 46 12 00 00    	jae    1091bbf <my.sexpr_parser::next_token+0x157f>
 1090979:	80 3c 37 0a          	cmpb   $0xa,(%rdi,%rsi,1)
 109097d:	75 23                	jne    10909a2 <my.sexpr_parser::next_token+0x362>
 109097f:	4c 89 de             	mov    %r11,%rsi
 1090982:	48 ff c6             	inc    %rsi
 1090985:	0f 80 5a 12 00 00    	jo     1091be5 <my.sexpr_parser::next_token+0x15a5>
 109098b:	48 89 72 08          	mov    %rsi,0x8(%rdx)
 109098f:	bd 02 00 00 00       	mov    $0x2,%ebp
 1090994:	41 bd 01 00 00 00    	mov    $0x1,%r13d
 109099a:	49 89 f3             	mov    %rsi,%r11
 109099d:	e9 2f ff ff ff       	jmp    10908d1 <my.sexpr_parser::next_token+0x291>
 10909a2:	4c 89 ee             	mov    %r13,%rsi
 10909a5:	48 ff c6             	inc    %rsi
 10909a8:	0f 80 4b 12 00 00    	jo     1091bf9 <my.sexpr_parser::next_token+0x15b9>
 10909ae:	bd 02 00 00 00       	mov    $0x2,%ebp
 10909b3:	49 89 f5             	mov    %rsi,%r13
 10909b6:	e9 16 ff ff ff       	jmp    10908d1 <my.sexpr_parser::next_token+0x291>
 10909bb:	8d 71 d0             	lea    -0x30(%rcx),%esi
 10909be:	4d 89 f1             	mov    %r14,%r9
 10909c1:	48 89 d8             	mov    %rbx,%rax
 10909c4:	40 80 fe 09          	cmp    $0x9,%sil
 10909c8:	4c 89 44 24 10       	mov    %r8,0x10(%rsp)
 10909cd:	4c 89 1c 24          	mov    %r11,(%rsp)
 10909d1:	0f 87 29 01 00 00    	ja     1090b00 <my.sexpr_parser::next_token+0x4c0>
 10909d7:	b9 04 00 00 00       	mov    $0x4,%ecx
 10909dc:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
 10909e1:	48 89 c5             	mov    %rax,%rbp
 10909e4:	4c 29 d5             	sub    %r10,%rbp
 10909e7:	0f 8d 04 05 00 00    	jge    1090ef1 <my.sexpr_parser::next_token+0x8b1>
 10909ed:	4d 89 e8             	mov    %r13,%r8
 10909f0:	4d 8d 1c 04          	lea    (%r12,%rax,1),%r11
 10909f4:	31 c9                	xor    %ecx,%ecx
 10909f6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 10909fd:	00 00 00 
 1090a00:	4c 8d 3c 08          	lea    (%rax,%rcx,1),%r15
 1090a04:	4d 89 fd             	mov    %r15,%r13
 1090a07:	49 c1 fd 3f          	sar    $0x3f,%r13
 1090a0b:	4d 21 d5             	and    %r10,%r13
 1090a0e:	4b 8d 34 2f          	lea    (%r15,%r13,1),%rsi
 1090a12:	4c 39 d6             	cmp    %r10,%rsi
 1090a15:	0f 83 f2 11 00 00    	jae    1091c0d <my.sexpr_parser::next_token+0x15cd>
 1090a1b:	49 8d 34 09          	lea    (%r9,%rcx,1),%rsi
 1090a1f:	4d 01 dd             	add    %r11,%r13
 1090a22:	46 0f b6 6c 29 20    	movzbl 0x20(%rcx,%r13,1),%r13d
 1090a28:	45 8d 75 d0          	lea    -0x30(%r13),%r14d
 1090a2c:	41 80 fe 09          	cmp    $0x9,%r14b
 1090a30:	0f 87 3e 03 00 00    	ja     1090d74 <my.sexpr_parser::next_token+0x734>
 1090a36:	48 ff c6             	inc    %rsi
 1090a39:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1090a3e:	0f 80 db 11 00 00    	jo     1091c1f <my.sexpr_parser::next_token+0x15df>
 1090a44:	48 89 72 10          	mov    %rsi,0x10(%rdx)
 1090a48:	48 8d 34 08          	lea    (%rax,%rcx,1),%rsi
 1090a4c:	48 ff c6             	inc    %rsi
 1090a4f:	48 89 32             	mov    %rsi,(%rdx)
 1090a52:	48 ff c1             	inc    %rcx
 1090a55:	48 89 ee             	mov    %rbp,%rsi
 1090a58:	48 01 ce             	add    %rcx,%rsi
 1090a5b:	75 a3                	jne    1090a00 <my.sexpr_parser::next_token+0x3c0>
 1090a5d:	41 b9 04 00 00 00    	mov    $0x4,%r9d
 1090a63:	4c 89 d0             	mov    %r10,%rax
 1090a66:	48 89 d9             	mov    %rbx,%rcx
 1090a69:	4c 8b bc 24 80 00 00 	mov    0x80(%rsp),%r15
 1090a70:	00 
 1090a71:	4d 89 c5             	mov    %r8,%r13
 1090a74:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1090a79:	4c 8b 1c 24          	mov    (%rsp),%r11
 1090a7d:	eb 28                	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 1090a7f:	4c 89 e6             	mov    %r12,%rsi
 1090a82:	48 ff c6             	inc    %rsi
 1090a85:	0f 80 39 12 00 00    	jo     1091cc4 <my.sexpr_parser::next_token+0x1684>
 1090a8b:	48 89 72 10          	mov    %rsi,0x10(%rdx)
 1090a8f:	4c 8d 60 01          	lea    0x1(%rax),%r12
 1090a93:	4d 89 cd             	mov    %r9,%r13
 1090a96:	41 b9 03 00 00 00    	mov    $0x3,%r9d
 1090a9c:	4d 89 f3             	mov    %r14,%r11
 1090a9f:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1090aa4:	4c 89 22             	mov    %r12,(%rdx)
 1090aa7:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 1090aac:	4d 89 4c 24 08       	mov    %r9,0x8(%r12)
 1090ab1:	49 89 4c 24 10       	mov    %rcx,0x10(%r12)
 1090ab6:	49 89 44 24 18       	mov    %rax,0x18(%r12)
 1090abb:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 1090ac0:	49 89 44 24 20       	mov    %rax,0x20(%r12)
 1090ac5:	4d 89 74 24 28       	mov    %r14,0x28(%r12)
 1090aca:	49 89 5c 24 30       	mov    %rbx,0x30(%r12)
 1090acf:	49 c7 04 24 00 00 00 	movq   $0x0,(%r12)
 1090ad6:	00 
 1090ad7:	4d 89 5c 24 68       	mov    %r11,0x68(%r12)
 1090adc:	4d 89 44 24 70       	mov    %r8,0x70(%r12)
 1090ae1:	4d 89 6c 24 78       	mov    %r13,0x78(%r12)
 1090ae6:	4d 89 bc 24 80 00 00 	mov    %r15,0x80(%r12)
 1090aed:	00 
 1090aee:	4c 89 e0             	mov    %r12,%rax
 1090af1:	48 83 c4 48          	add    $0x48,%rsp
 1090af5:	5b                   	pop    %rbx
 1090af6:	41 5c                	pop    %r12
 1090af8:	41 5d                	pop    %r13
 1090afa:	41 5e                	pop    %r14
 1090afc:	41 5f                	pop    %r15
 1090afe:	5d                   	pop    %rbp
 1090aff:	c3                   	ret
 1090b00:	83 f9 2d             	cmp    $0x2d,%ecx
 1090b03:	75 59                	jne    1090b5e <my.sexpr_parser::next_token+0x51e>
 1090b05:	48 8d 43 01          	lea    0x1(%rbx),%rax
 1090b09:	4c 39 d0             	cmp    %r10,%rax
 1090b0c:	0f 8d 68 03 00 00    	jge    1090e7a <my.sexpr_parser::next_token+0x83a>
 1090b12:	31 f6                	xor    %esi,%esi
 1090b14:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 1090b18:	49 0f 4c f2          	cmovl  %r10,%rsi
 1090b1c:	48 01 c6             	add    %rax,%rsi
 1090b1f:	4c 39 d6             	cmp    %r10,%rsi
 1090b22:	0f 83 32 12 00 00    	jae    1091d5a <my.sexpr_parser::next_token+0x171a>
 1090b28:	0f b6 34 37          	movzbl (%rdi,%rsi,1),%esi
 1090b2c:	40 80 c6 d0          	add    $0xd0,%sil
 1090b30:	40 80 fe 0a          	cmp    $0xa,%sil
 1090b34:	0f 83 40 03 00 00    	jae    1090e7a <my.sexpr_parser::next_token+0x83a>
 1090b3a:	4c 89 f1             	mov    %r14,%rcx
 1090b3d:	48 ff c1             	inc    %rcx
 1090b40:	0f 80 7e 12 00 00    	jo     1091dc4 <my.sexpr_parser::next_token+0x1784>
 1090b46:	48 89 4a 10          	mov    %rcx,0x10(%rdx)
 1090b4a:	48 89 02             	mov    %rax,(%rdx)
 1090b4d:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1090b52:	4c 8b 1c 24          	mov    (%rsp),%r11
 1090b56:	49 89 c9             	mov    %rcx,%r9
 1090b59:	e9 79 fe ff ff       	jmp    10909d7 <my.sexpr_parser::next_token+0x397>
 1090b5e:	89 c8                	mov    %ecx,%eax
 1090b60:	83 e0 df             	and    $0xffffffdf,%eax
 1090b63:	83 c0 bf             	add    $0xffffffbf,%eax
 1090b66:	83 f8 1a             	cmp    $0x1a,%eax
 1090b69:	0f 83 ef 02 00 00    	jae    1090e5e <my.sexpr_parser::next_token+0x81e>
 1090b6f:	c5 f9 6e 05 09 37 f7 	vmovd  -0x8c8f7(%rip),%xmm0        # 1004280 <__anon_1393+0x50>
 1090b76:	ff 
 1090b77:	4c 8b 5c 24 20       	mov    0x20(%rsp),%r11
 1090b7c:	4d 89 f4             	mov    %r14,%r12
 1090b7f:	48 89 d8             	mov    %rbx,%rax
 1090b82:	eb 63                	jmp    1090be7 <my.sexpr_parser::next_token+0x5a7>
 1090b84:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090b8b:	0f 1f 84 00 00 00 00 
 1090b92:	00 
 1090b93:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090b9a:	0f 1f 84 00 00 00 00 
 1090ba1:	00 
 1090ba2:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090ba9:	0f 1f 84 00 00 00 00 
 1090bb0:	00 
 1090bb1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090bb8:	0f 1f 84 00 00 00 00 
 1090bbf:	00 
 1090bc0:	4c 89 e1             	mov    %r12,%rcx
 1090bc3:	48 ff c1             	inc    %rcx
 1090bc6:	0f 80 a6 10 00 00    	jo     1091c72 <my.sexpr_parser::next_token+0x1632>
 1090bcc:	49 89 cc             	mov    %rcx,%r12
 1090bcf:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1090bd4:	4c 89 62 10          	mov    %r12,0x10(%rdx)
 1090bd8:	48 ff c0             	inc    %rax
 1090bdb:	48 89 02             	mov    %rax,(%rdx)
 1090bde:	49 39 c2             	cmp    %rax,%r10
 1090be1:	0f 84 df 04 00 00    	je     10910c6 <my.sexpr_parser::next_token+0xa86>
 1090be7:	48 89 c1             	mov    %rax,%rcx
 1090bea:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1090bee:	4c 21 d1             	and    %r10,%rcx
 1090bf1:	48 8d 34 01          	lea    (%rcx,%rax,1),%rsi
 1090bf5:	4c 39 d6             	cmp    %r10,%rsi
 1090bf8:	0f 83 4e 10 00 00    	jae    1091c4c <my.sexpr_parser::next_token+0x160c>
 1090bfe:	48 01 f9             	add    %rdi,%rcx
 1090c01:	0f b6 0c 08          	movzbl (%rax,%rcx,1),%ecx
 1090c05:	41 89 c8             	mov    %ecx,%r8d
 1090c08:	41 81 e0 df 00 00 00 	and    $0xdf,%r8d
 1090c0f:	41 83 c0 bf          	add    $0xffffffbf,%r8d
 1090c13:	40 b6 01             	mov    $0x1,%sil
 1090c16:	41 83 f8 1a          	cmp    $0x1a,%r8d
 1090c1a:	0f 83 a0 00 00 00    	jae    1090cc0 <my.sexpr_parser::next_token+0x680>
 1090c20:	c5 f9 6e c9          	vmovd  %ecx,%xmm1
 1090c24:	c4 e2 79 78 c9       	vpbroadcastb %xmm1,%xmm1
 1090c29:	c5 f1 74 c8          	vpcmpeqb %xmm0,%xmm1,%xmm1
 1090c2d:	c4 e2 79 21 c9       	vpmovsxbd %xmm1,%xmm1
 1090c32:	c5 f8 50 e9          	vmovmskps %xmm1,%ebp
 1090c36:	85 ed                	test   %ebp,%ebp
 1090c38:	75 2c                	jne    1090c66 <my.sexpr_parser::next_token+0x626>
 1090c3a:	41 89 ce             	mov    %ecx,%r14d
 1090c3d:	41 83 e6 fd          	and    $0xfffffffd,%r14d
 1090c41:	41 83 fe 2d          	cmp    $0x2d,%r14d
 1090c45:	74 1f                	je     1090c66 <my.sexpr_parser::next_token+0x626>
 1090c47:	41 89 ce             	mov    %ecx,%r14d
 1090c4a:	41 83 e6 fb          	and    $0xfffffffb,%r14d
 1090c4e:	41 83 fe 2a          	cmp    $0x2a,%r14d
 1090c52:	74 12                	je     1090c66 <my.sexpr_parser::next_token+0x626>
 1090c54:	8d 69 d5             	lea    -0x2b(%rcx),%ebp
 1090c57:	40 80 fd 02          	cmp    $0x2,%bpl
 1090c5b:	72 09                	jb     1090c66 <my.sexpr_parser::next_token+0x626>
 1090c5d:	40 84 f6             	test   %sil,%sil
 1090c60:	0f 84 44 04 00 00    	je     10910aa <my.sexpr_parser::next_token+0xa6a>
 1090c66:	83 f9 0a             	cmp    $0xa,%ecx
 1090c69:	0f 85 51 ff ff ff    	jne    1090bc0 <my.sexpr_parser::next_token+0x580>
 1090c6f:	4c 89 d9             	mov    %r11,%rcx
 1090c72:	48 ff c1             	inc    %rcx
 1090c75:	0f 80 e3 0f 00 00    	jo     1091c5e <my.sexpr_parser::next_token+0x161e>
 1090c7b:	48 89 4a 08          	mov    %rcx,0x8(%rdx)
 1090c7f:	41 bc 01 00 00 00    	mov    $0x1,%r12d
 1090c85:	49 89 cb             	mov    %rcx,%r11
 1090c88:	e9 42 ff ff ff       	jmp    1090bcf <my.sexpr_parser::next_token+0x58f>
 1090c8d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090c94:	0f 1f 84 00 00 00 00 
 1090c9b:	00 
 1090c9c:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090ca3:	0f 1f 84 00 00 00 00 
 1090caa:	00 
 1090cab:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1090cb2:	0f 1f 84 00 00 00 00 
 1090cb9:	00 
 1090cba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1090cc0:	48 83 f9 2a          	cmp    $0x2a,%rcx
 1090cc4:	0f 84 56 ff ff ff    	je     1090c20 <my.sexpr_parser::next_token+0x5e0>
 1090cca:	83 f9 5f             	cmp    $0x5f,%ecx
 1090ccd:	0f 84 4d ff ff ff    	je     1090c20 <my.sexpr_parser::next_token+0x5e0>
 1090cd3:	83 f9 7e             	cmp    $0x7e,%ecx
 1090cd6:	0f 84 44 ff ff ff    	je     1090c20 <my.sexpr_parser::next_token+0x5e0>
 1090cdc:	8d 71 d0             	lea    -0x30(%rcx),%esi
 1090cdf:	40 80 fe 0a          	cmp    $0xa,%sil
 1090ce3:	40 0f 92 c6          	setb   %sil
 1090ce7:	e9 34 ff ff ff       	jmp    1090c20 <my.sexpr_parser::next_token+0x5e0>
 1090cec:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 1090cf1:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 1090cf6:	4c 89 6a 18          	mov    %r13,0x18(%rdx)
 1090cfa:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1090cff:	4c 89 72 20          	mov    %r14,0x20(%rdx)
 1090d03:	48 89 5a 28          	mov    %rbx,0x28(%rdx)
 1090d07:	48 8d 3d 82 0c 06 00 	lea    0x60c82(%rip),%rdi        # 10f1990 <core_durable_error.verbs+0x6390>
 1090d0e:	e8 6d eb fd ff       	call   106f880 <myl_core_err_trace_origin_preserve_most>
 1090d13:	48 8d 3d 66 fe 05 00 	lea    0x5fe66(%rip),%rdi        # 10f0b80 <core_durable_error.verbs+0x5580>
 1090d1a:	e8 a1 eb fd ff       	call   106f8c0 <myl_core_err_trace_append_preserve_most>
 1090d1f:	48 8d 05 3a b7 f8 ff 	lea    -0x748c6(%rip),%rax        # 101c460 <core_number_pairs+0x14f10>
 1090d26:	48 89 04 24          	mov    %rax,(%rsp)
 1090d2a:	bd 03 00 00 00       	mov    $0x3,%ebp
 1090d2f:	48 8d 3d 1a ec 05 00 	lea    0x5ec1a(%rip),%rdi        # 10ef950 <core_durable_error.verbs+0x4350>
 1090d36:	e8 85 eb fd ff       	call   106f8c0 <myl_core_err_trace_append_preserve_most>
 1090d3b:	4c 89 ff             	mov    %r15,%rdi
 1090d3e:	e8 fd b9 fa ff       	call   103c740 <myl_core_drop_owned>
 1090d43:	48 8d 3d d6 d9 05 00 	lea    0x5d9d6(%rip),%rdi        # 10ee720 <core_durable_error.verbs+0x3120>
 1090d4a:	e8 31 eb fd ff       	call   106f880 <myl_core_err_trace_origin_preserve_most>
 1090d4f:	49 c7 04 24 01 00 00 	movq   $0x1,(%r12)
 1090d56:	00 
 1090d57:	49 89 6c 24 08       	mov    %rbp,0x8(%r12)
 1090d5c:	4d 89 6c 24 68       	mov    %r13,0x68(%r12)
 1090d61:	4d 89 74 24 70       	mov    %r14,0x70(%r12)
 1090d66:	49 89 5c 24 78       	mov    %rbx,0x78(%r12)
 1090d6b:	4c 8b 3c 24          	mov    (%rsp),%r15
 1090d6f:	e9 72 fd ff ff       	jmp    1090ae6 <my.sexpr_parser::next_token+0x4a6>
 1090d74:	41 80 fd 2e          	cmp    $0x2e,%r13b
 1090d78:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1090d7d:	0f 85 54 01 00 00    	jne    1090ed7 <my.sexpr_parser::next_token+0x897>
 1090d83:	48 8d 2c 08          	lea    (%rax,%rcx,1),%rbp
 1090d87:	48 ff c5             	inc    %rbp
 1090d8a:	4c 39 d5             	cmp    %r10,%rbp
 1090d8d:	0f 8d 44 01 00 00    	jge    1090ed7 <my.sexpr_parser::next_token+0x897>
 1090d93:	45 31 ed             	xor    %r13d,%r13d
 1090d96:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 1090d9a:	4d 0f 4c ea          	cmovl  %r10,%r13
 1090d9e:	4e 8d 34 28          	lea    (%rax,%r13,1),%r14
 1090da2:	49 01 ce             	add    %rcx,%r14
 1090da5:	49 ff c6             	inc    %r14
 1090da8:	4d 39 d6             	cmp    %r10,%r14
 1090dab:	0f 83 62 10 00 00    	jae    1091e13 <my.sexpr_parser::next_token+0x17d3>
 1090db1:	4d 01 eb             	add    %r13,%r11
 1090db4:	46 0f b6 5c 19 21    	movzbl 0x21(%rcx,%r11,1),%r11d
 1090dba:	41 80 c3 d0          	add    $0xd0,%r11b
 1090dbe:	41 80 fb 0a          	cmp    $0xa,%r11b
 1090dc2:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1090dc7:	0f 83 0a 01 00 00    	jae    1090ed7 <my.sexpr_parser::next_token+0x897>
 1090dcd:	49 89 f3             	mov    %rsi,%r11
 1090dd0:	49 ff c3             	inc    %r11
 1090dd3:	4d 89 c5             	mov    %r8,%r13
 1090dd6:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1090ddb:	0f 80 44 10 00 00    	jo     1091e25 <my.sexpr_parser::next_token+0x17e5>
 1090de1:	4c 01 c9             	add    %r9,%rcx
 1090de4:	48 ff c1             	inc    %rcx
 1090de7:	4c 89 5a 10          	mov    %r11,0x10(%rdx)
 1090deb:	49 83 c4 21          	add    $0x21,%r12
 1090def:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 1090df3:	be 00 00 00 00       	mov    $0x0,%esi
 1090df8:	49 0f 4c f2          	cmovl  %r10,%rsi
 1090dfc:	4c 8d 1c 2e          	lea    (%rsi,%rbp,1),%r11
 1090e00:	4d 39 d3             	cmp    %r10,%r11
 1090e03:	0f 83 e1 0e 00 00    	jae    1091cea <my.sexpr_parser::next_token+0x16aa>
 1090e09:	4c 01 e6             	add    %r12,%rsi
 1090e0c:	41 0f b6 34 37       	movzbl (%r15,%rsi,1),%esi
 1090e11:	40 80 c6 d0          	add    $0xd0,%sil
 1090e15:	40 80 fe 09          	cmp    $0x9,%sil
 1090e19:	4c 8b 1c 24          	mov    (%rsp),%r11
 1090e1d:	77 1f                	ja     1090e3e <my.sexpr_parser::next_token+0x7fe>
 1090e1f:	48 ff c1             	inc    %rcx
 1090e22:	0f 80 d7 0e 00 00    	jo     1091cff <my.sexpr_parser::next_token+0x16bf>
 1090e28:	48 89 4a 10          	mov    %rcx,0x10(%rdx)
 1090e2c:	48 ff c5             	inc    %rbp
 1090e2f:	49 ff c7             	inc    %r15
 1090e32:	4c 39 d5             	cmp    %r10,%rbp
 1090e35:	7c b8                	jl     1090def <my.sexpr_parser::next_token+0x7af>
 1090e37:	4c 89 d5             	mov    %r10,%rbp
 1090e3a:	4c 8b 1c 24          	mov    (%rsp),%r11
 1090e3e:	48 89 2a             	mov    %rbp,(%rdx)
 1090e41:	b8 05 00 00 00       	mov    $0x5,%eax
 1090e46:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 1090e4b:	49 89 c9             	mov    %rcx,%r9
 1090e4e:	48 89 e8             	mov    %rbp,%rax
 1090e51:	4c 8b bc 24 80 00 00 	mov    0x80(%rsp),%r15
 1090e58:	00 
 1090e59:	e9 93 00 00 00       	jmp    1090ef1 <my.sexpr_parser::next_token+0x8b1>
 1090e5e:	48 83 f9 2a          	cmp    $0x2a,%rcx
 1090e62:	0f 84 07 fd ff ff    	je     1090b6f <my.sexpr_parser::next_token+0x52f>
 1090e68:	83 f9 5f             	cmp    $0x5f,%ecx
 1090e6b:	0f 84 fe fc ff ff    	je     1090b6f <my.sexpr_parser::next_token+0x52f>
 1090e71:	83 f9 7e             	cmp    $0x7e,%ecx
 1090e74:	0f 84 f5 fc ff ff    	je     1090b6f <my.sexpr_parser::next_token+0x52f>
 1090e7a:	89 c8                	mov    %ecx,%eax
 1090e7c:	83 e0 fb             	and    $0xfffffffb,%eax
 1090e7f:	83 f8 2b             	cmp    $0x2b,%eax
 1090e82:	74 22                	je     1090ea6 <my.sexpr_parser::next_token+0x866>
 1090e84:	89 c8                	mov    %ecx,%eax
 1090e86:	83 e0 f7             	and    $0xfffffff7,%eax
 1090e89:	83 f8 25             	cmp    $0x25,%eax
 1090e8c:	74 18                	je     1090ea6 <my.sexpr_parser::next_token+0x866>
 1090e8e:	80 f9 21             	cmp    $0x21,%cl
 1090e91:	74 13                	je     1090ea6 <my.sexpr_parser::next_token+0x866>
 1090e93:	80 f9 3d             	cmp    $0x3d,%cl
 1090e96:	74 0e                	je     1090ea6 <my.sexpr_parser::next_token+0x866>
 1090e98:	89 c8                	mov    %ecx,%eax
 1090e9a:	83 e0 fd             	and    $0xfffffffd,%eax
 1090e9d:	83 f8 3c             	cmp    $0x3c,%eax
 1090ea0:	0f 85 c8 05 00 00    	jne    109146e <my.sexpr_parser::next_token+0xe2e>
 1090ea6:	83 f9 0a             	cmp    $0xa,%ecx
 1090ea9:	0f 85 31 02 00 00    	jne    10910e0 <my.sexpr_parser::next_token+0xaa0>
 1090eaf:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 1090eb4:	48 89 f0             	mov    %rsi,%rax
 1090eb7:	48 ff c0             	inc    %rax
 1090eba:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1090ebf:	4c 8b 1c 24          	mov    (%rsp),%r11
 1090ec3:	0f 80 b5 0e 00 00    	jo     1091d7e <my.sexpr_parser::next_token+0x173e>
 1090ec9:	48 89 42 08          	mov    %rax,0x8(%rdx)
 1090ecd:	be 01 00 00 00       	mov    $0x1,%esi
 1090ed2:	e9 1e 02 00 00       	jmp    10910f5 <my.sexpr_parser::next_token+0xab5>
 1090ed7:	49 89 f1             	mov    %rsi,%r9
 1090eda:	4c 89 f8             	mov    %r15,%rax
 1090edd:	4c 8b bc 24 80 00 00 	mov    0x80(%rsp),%r15
 1090ee4:	00 
 1090ee5:	4d 89 c5             	mov    %r8,%r13
 1090ee8:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1090eed:	4c 8b 1c 24          	mov    (%rsp),%r11
 1090ef1:	4c 39 d0             	cmp    %r10,%rax
 1090ef4:	0f 8d a3 01 00 00    	jge    109109d <my.sexpr_parser::next_token+0xa5d>
 1090efa:	49 89 c4             	mov    %rax,%r12
 1090efd:	49 c1 fc 3f          	sar    $0x3f,%r12
 1090f01:	4d 21 d4             	and    %r10,%r12
 1090f04:	49 01 c4             	add    %rax,%r12
 1090f07:	4d 39 d4             	cmp    %r10,%r12
 1090f0a:	0f 83 13 0e 00 00    	jae    1091d23 <my.sexpr_parser::next_token+0x16e3>
 1090f10:	42 0f b6 2c 27       	movzbl (%rdi,%r12,1),%ebp
 1090f15:	89 e9                	mov    %ebp,%ecx
 1090f17:	83 c1 b9             	add    $0xffffffb9,%ecx
 1090f1a:	83 f9 2e             	cmp    $0x2e,%ecx
 1090f1d:	4c 89 4c 24 28       	mov    %r9,0x28(%rsp)
 1090f22:	0f 87 8e 03 00 00    	ja     10912b6 <my.sexpr_parser::next_token+0xc76>
 1090f28:	48 be 41 00 00 00 90 	movabs $0x429000000041,%rsi
 1090f2f:	42 00 00 
 1090f32:	48 0f a3 ce          	bt     %rcx,%rsi
 1090f36:	0f 83 13 02 00 00    	jae    109114f <my.sexpr_parser::next_token+0xb0f>
 1090f3c:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
 1090f41:	48 8d 70 01          	lea    0x1(%rax),%rsi
 1090f45:	41 b1 01             	mov    $0x1,%r9b
 1090f48:	4c 39 d6             	cmp    %r10,%rsi
 1090f4b:	0f 8d 1a 04 00 00    	jge    109136b <my.sexpr_parser::next_token+0xd2b>
 1090f51:	31 c9                	xor    %ecx,%ecx
 1090f53:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 1090f57:	49 0f 4c ca          	cmovl  %r10,%rcx
 1090f5b:	48 01 f1             	add    %rsi,%rcx
 1090f5e:	4c 39 d1             	cmp    %r10,%rcx
 1090f61:	0f 83 4e 0e 00 00    	jae    1091db5 <my.sexpr_parser::next_token+0x1775>
 1090f67:	0f b6 0c 0f          	movzbl (%rdi,%rcx,1),%ecx
 1090f6b:	41 89 cb             	mov    %ecx,%r11d
 1090f6e:	41 81 e3 df 00 00 00 	and    $0xdf,%r11d
 1090f75:	41 83 c3 bf          	add    $0xffffffbf,%r11d
 1090f79:	41 b1 01             	mov    $0x1,%r9b
 1090f7c:	40 b6 01             	mov    $0x1,%sil
 1090f7f:	41 83 fb 1a          	cmp    $0x1a,%r11d
 1090f83:	0f 83 01 03 00 00    	jae    109128a <my.sexpr_parser::next_token+0xc4a>
 1090f89:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
 1090f8d:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1090f92:	c5 f9 74 05 e6 32 f7 	vpcmpeqb -0x8cd1a(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 1090f99:	ff 
 1090f9a:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 1090f9f:	c5 78 50 d8          	vmovmskps %xmm0,%r11d
 1090fa3:	45 85 db             	test   %r11d,%r11d
 1090fa6:	75 2d                	jne    1090fd5 <my.sexpr_parser::next_token+0x995>
 1090fa8:	41 89 cb             	mov    %ecx,%r11d
 1090fab:	41 83 e3 fd          	and    $0xfffffffd,%r11d
 1090faf:	41 83 fb 2d          	cmp    $0x2d,%r11d
 1090fb3:	74 20                	je     1090fd5 <my.sexpr_parser::next_token+0x995>
 1090fb5:	41 89 cb             	mov    %ecx,%r11d
 1090fb8:	41 83 e3 fb          	and    $0xfffffffb,%r11d
 1090fbc:	41 83 fb 2a          	cmp    $0x2a,%r11d
 1090fc0:	74 13                	je     1090fd5 <my.sexpr_parser::next_token+0x995>
 1090fc2:	44 8d 59 d5          	lea    -0x2b(%rcx),%r11d
 1090fc6:	41 80 fb 02          	cmp    $0x2,%r11b
 1090fca:	72 09                	jb     1090fd5 <my.sexpr_parser::next_token+0x995>
 1090fcc:	40 84 f6             	test   %sil,%sil
 1090fcf:	0f 84 96 03 00 00    	je     109136b <my.sexpr_parser::next_token+0xd2b>
 1090fd5:	89 ce                	mov    %ecx,%esi
 1090fd7:	83 e6 ef             	and    $0xffffffef,%esi
 1090fda:	83 fe 46             	cmp    $0x46,%esi
 1090fdd:	74 1a                	je     1090ff9 <my.sexpr_parser::next_token+0x9b9>
 1090fdf:	83 c1 bf             	add    $0xffffffbf,%ecx
 1090fe2:	83 f9 11             	cmp    $0x11,%ecx
 1090fe5:	0f 87 f8 04 00 00    	ja     10914e3 <my.sexpr_parser::next_token+0xea3>
 1090feb:	be 81 00 02 00       	mov    $0x20081,%esi
 1090ff0:	0f a3 ce             	bt     %ecx,%esi
 1090ff3:	0f 83 ea 04 00 00    	jae    10914e3 <my.sexpr_parser::next_token+0xea3>
 1090ff9:	48 8d 70 02          	lea    0x2(%rax),%rsi
 1090ffd:	4c 39 d6             	cmp    %r10,%rsi
 1091000:	0f 8d 8f 00 00 00    	jge    1091095 <my.sexpr_parser::next_token+0xa55>
 1091006:	31 c9                	xor    %ecx,%ecx
 1091008:	48 83 f8 fe          	cmp    $0xfffffffffffffffe,%rax
 109100c:	49 0f 4c ca          	cmovl  %r10,%rcx
 1091010:	48 01 f1             	add    %rsi,%rcx
 1091013:	4c 39 d1             	cmp    %r10,%rcx
 1091016:	0f 83 1a 0e 00 00    	jae    1091e36 <my.sexpr_parser::next_token+0x17f6>
 109101c:	0f b6 0c 0f          	movzbl (%rdi,%rcx,1),%ecx
 1091020:	41 89 cb             	mov    %ecx,%r11d
 1091023:	41 81 e3 df 00 00 00 	and    $0xdf,%r11d
 109102a:	41 83 c3 bf          	add    $0xffffffbf,%r11d
 109102e:	40 b6 01             	mov    $0x1,%sil
 1091031:	41 83 fb 1a          	cmp    $0x1a,%r11d
 1091035:	0f 83 6a 04 00 00    	jae    10914a5 <my.sexpr_parser::next_token+0xe65>
 109103b:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
 109103f:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1091044:	c5 f9 74 05 34 32 f7 	vpcmpeqb -0x8cdcc(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 109104b:	ff 
 109104c:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 1091051:	c5 78 50 d8          	vmovmskps %xmm0,%r11d
 1091055:	45 85 db             	test   %r11d,%r11d
 1091058:	0f 85 85 04 00 00    	jne    10914e3 <my.sexpr_parser::next_token+0xea3>
 109105e:	41 89 cb             	mov    %ecx,%r11d
 1091061:	41 83 e3 fd          	and    $0xfffffffd,%r11d
 1091065:	41 83 fb 2d          	cmp    $0x2d,%r11d
 1091069:	0f 84 74 04 00 00    	je     10914e3 <my.sexpr_parser::next_token+0xea3>
 109106f:	41 89 cb             	mov    %ecx,%r11d
 1091072:	41 83 e3 fb          	and    $0xfffffffb,%r11d
 1091076:	41 83 fb 2a          	cmp    $0x2a,%r11d
 109107a:	0f 84 63 04 00 00    	je     10914e3 <my.sexpr_parser::next_token+0xea3>
 1091080:	83 c1 d5             	add    $0xffffffd5,%ecx
 1091083:	80 f9 02             	cmp    $0x2,%cl
 1091086:	0f 82 57 04 00 00    	jb     10914e3 <my.sexpr_parser::next_token+0xea3>
 109108c:	40 84 f6             	test   %sil,%sil
 109108f:	0f 85 4e 04 00 00    	jne    10914e3 <my.sexpr_parser::next_token+0xea3>
 1091095:	45 31 c9             	xor    %r9d,%r9d
 1091098:	e9 ce 02 00 00       	jmp    109136b <my.sexpr_parser::next_token+0xd2b>
 109109d:	48 89 d9             	mov    %rbx,%rcx
 10910a0:	4c 8b 4c 24 30       	mov    0x30(%rsp),%r9
 10910a5:	e9 fd f9 ff ff       	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 10910aa:	48 89 d9             	mov    %rbx,%rcx
 10910ad:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 10910b2:	4c 8b 1c 24          	mov    (%rsp),%r11
 10910b6:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 10910bb:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 10910c1:	e9 e1 f9 ff ff       	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 10910c6:	4c 89 d0             	mov    %r10,%rax
 10910c9:	48 89 d9             	mov    %rbx,%rcx
 10910cc:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 10910d1:	4c 8b 1c 24          	mov    (%rsp),%r11
 10910d5:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 10910db:	e9 c7 f9 ff ff       	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 10910e0:	4c 89 f6             	mov    %r14,%rsi
 10910e3:	48 ff c6             	inc    %rsi
 10910e6:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 10910eb:	4c 8b 1c 24          	mov    (%rsp),%r11
 10910ef:	0f 80 9a 0c 00 00    	jo     1091d8f <my.sexpr_parser::next_token+0x174f>
 10910f5:	48 89 72 10          	mov    %rsi,0x10(%rdx)
 10910f9:	48 8d 43 01          	lea    0x1(%rbx),%rax
 10910fd:	48 89 02             	mov    %rax,(%rdx)
 1091100:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 1091106:	4c 39 d0             	cmp    %r10,%rax
 1091109:	7d 3c                	jge    1091147 <my.sexpr_parser::next_token+0xb07>
 109110b:	31 c9                	xor    %ecx,%ecx
 109110d:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 1091111:	49 0f 4c ca          	cmovl  %r10,%rcx
 1091115:	48 01 c1             	add    %rax,%rcx
 1091118:	4c 39 d1             	cmp    %r10,%rcx
 109111b:	0f 83 82 0c 00 00    	jae    1091da3 <my.sexpr_parser::next_token+0x1763>
 1091121:	80 3c 0f 3d          	cmpb   $0x3d,(%rdi,%rcx,1)
 1091125:	48 89 d9             	mov    %rbx,%rcx
 1091128:	0f 85 79 f9 ff ff    	jne    1090aa7 <my.sexpr_parser::next_token+0x467>
 109112e:	48 89 f0             	mov    %rsi,%rax
 1091131:	48 ff c0             	inc    %rax
 1091134:	0f 80 af 0c 00 00    	jo     1091de9 <my.sexpr_parser::next_token+0x17a9>
 109113a:	48 89 42 10          	mov    %rax,0x10(%rdx)
 109113e:	4c 8d 63 02          	lea    0x2(%rbx),%r12
 1091142:	e9 17 f7 ff ff       	jmp    109085e <my.sexpr_parser::next_token+0x21e>
 1091147:	48 89 d9             	mov    %rbx,%rcx
 109114a:	e9 58 f9 ff ff       	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 109114f:	48 83 f9 26          	cmp    $0x26,%rcx
 1091153:	0f 85 5d 01 00 00    	jne    10912b6 <my.sexpr_parser::next_token+0xc76>
 1091159:	48 8d 48 01          	lea    0x1(%rax),%rcx
 109115d:	40 b6 01             	mov    $0x1,%sil
 1091160:	41 b9 6d 00 00 00    	mov    $0x6d,%r9d
 1091166:	4c 39 d1             	cmp    %r10,%rcx
 1091169:	0f 8d 1e 06 00 00    	jge    109178d <my.sexpr_parser::next_token+0x114d>
 109116f:	48 89 ce             	mov    %rcx,%rsi
 1091172:	31 c9                	xor    %ecx,%ecx
 1091174:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 1091178:	49 0f 4c ca          	cmovl  %r10,%rcx
 109117c:	48 89 74 24 40       	mov    %rsi,0x40(%rsp)
 1091181:	48 01 f1             	add    %rsi,%rcx
 1091184:	4c 39 d1             	cmp    %r10,%rcx
 1091187:	0f 83 b8 0c 00 00    	jae    1091e45 <my.sexpr_parser::next_token+0x1805>
 109118d:	0f b6 0c 0f          	movzbl (%rdi,%rcx,1),%ecx
 1091191:	83 f9 69             	cmp    $0x69,%ecx
 1091194:	0f 84 d7 03 00 00    	je     1091571 <my.sexpr_parser::next_token+0xf31>
 109119a:	83 f9 6d             	cmp    $0x6d,%ecx
 109119d:	0f 85 05 05 00 00    	jne    10916a8 <my.sexpr_parser::next_token+0x1068>
 10911a3:	4c 8d 60 02          	lea    0x2(%rax),%r12
 10911a7:	4d 39 d4             	cmp    %r10,%r12
 10911aa:	0f 8d 9b 00 00 00    	jge    109124b <my.sexpr_parser::next_token+0xc0b>
 10911b0:	31 c9                	xor    %ecx,%ecx
 10911b2:	48 83 f8 fe          	cmp    $0xfffffffffffffffe,%rax
 10911b6:	49 0f 4c ca          	cmovl  %r10,%rcx
 10911ba:	4c 01 e1             	add    %r12,%rcx
 10911bd:	4c 39 d1             	cmp    %r10,%rcx
 10911c0:	0f 83 b6 0c 00 00    	jae    1091e7c <my.sexpr_parser::next_token+0x183c>
 10911c6:	0f b6 0c 0f          	movzbl (%rdi,%rcx,1),%ecx
 10911ca:	41 89 ce             	mov    %ecx,%r14d
 10911cd:	41 81 e6 df 00 00 00 	and    $0xdf,%r14d
 10911d4:	41 83 c6 bf          	add    $0xffffffbf,%r14d
 10911d8:	40 b6 01             	mov    $0x1,%sil
 10911db:	41 b3 01             	mov    $0x1,%r11b
 10911de:	41 83 fe 1a          	cmp    $0x1a,%r14d
 10911e2:	0f 83 bb 07 00 00    	jae    10919a3 <my.sexpr_parser::next_token+0x1363>
 10911e8:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
 10911ec:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10911f1:	c5 f9 74 05 87 30 f7 	vpcmpeqb -0x8cf79(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 10911f8:	ff 
 10911f9:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10911fe:	c5 78 50 f0          	vmovmskps %xmm0,%r14d
 1091202:	45 85 f6             	test   %r14d,%r14d
 1091205:	0f 85 35 08 00 00    	jne    1091a40 <my.sexpr_parser::next_token+0x1400>
 109120b:	41 89 ce             	mov    %ecx,%r14d
 109120e:	41 83 e6 fd          	and    $0xfffffffd,%r14d
 1091212:	41 83 fe 2d          	cmp    $0x2d,%r14d
 1091216:	0f 84 24 08 00 00    	je     1091a40 <my.sexpr_parser::next_token+0x1400>
 109121c:	41 89 ce             	mov    %ecx,%r14d
 109121f:	41 83 e6 fb          	and    $0xfffffffb,%r14d
 1091223:	41 83 fe 2a          	cmp    $0x2a,%r14d
 1091227:	0f 84 13 08 00 00    	je     1091a40 <my.sexpr_parser::next_token+0x1400>
 109122d:	83 c1 d5             	add    $0xffffffd5,%ecx
 1091230:	80 f9 02             	cmp    $0x2,%cl
 1091233:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1091238:	0f 82 e2 08 00 00    	jb     1091b20 <my.sexpr_parser::next_token+0x14e0>
 109123e:	45 84 db             	test   %r11b,%r11b
 1091241:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091245:	0f 85 42 05 00 00    	jne    109178d <my.sexpr_parser::next_token+0x114d>
 109124b:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 1091250:	48 89 ce             	mov    %rcx,%rsi
 1091253:	48 ff c6             	inc    %rsi
 1091256:	0f 80 0c 0c 00 00    	jo     1091e68 <my.sexpr_parser::next_token+0x1828>
 109125c:	48 89 72 10          	mov    %rsi,0x10(%rdx)
 1091260:	48 8d 48 01          	lea    0x1(%rax),%rcx
 1091264:	48 89 0a             	mov    %rcx,(%rdx)
 1091267:	48 89 f1             	mov    %rsi,%rcx
 109126a:	48 ff c1             	inc    %rcx
 109126d:	41 b9 06 00 00 00    	mov    $0x6,%r9d
 1091273:	0f 81 5e 08 00 00    	jno    1091ad7 <my.sexpr_parser::next_token+0x1497>
 1091279:	48 8d 3d e0 06 06 00 	lea    0x606e0(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091280:	ba 01 00 00 00       	mov    $0x1,%edx
 1091285:	e8 36 c2 fa ff       	call   103d4c0 <myl_core_trap>
 109128a:	48 83 f9 2a          	cmp    $0x2a,%rcx
 109128e:	0f 84 f5 fc ff ff    	je     1090f89 <my.sexpr_parser::next_token+0x949>
 1091294:	83 f9 5f             	cmp    $0x5f,%ecx
 1091297:	0f 84 ec fc ff ff    	je     1090f89 <my.sexpr_parser::next_token+0x949>
 109129d:	83 f9 7e             	cmp    $0x7e,%ecx
 10912a0:	0f 84 e3 fc ff ff    	je     1090f89 <my.sexpr_parser::next_token+0x949>
 10912a6:	8d 71 d0             	lea    -0x30(%rcx),%esi
 10912a9:	40 80 fe 0a          	cmp    $0xa,%sil
 10912ad:	40 0f 92 c6          	setb   %sil
 10912b1:	e9 d3 fc ff ff       	jmp    1090f89 <my.sexpr_parser::next_token+0x949>
 10912b6:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
 10912bb:	89 e9                	mov    %ebp,%ecx
 10912bd:	80 e1 ef             	and    $0xef,%cl
 10912c0:	80 f9 46             	cmp    $0x46,%cl
 10912c3:	0f 85 8c 01 00 00    	jne    1091455 <my.sexpr_parser::next_token+0xe15>
 10912c9:	48 8d 70 01          	lea    0x1(%rax),%rsi
 10912cd:	41 b1 01             	mov    $0x1,%r9b
 10912d0:	4c 39 d6             	cmp    %r10,%rsi
 10912d3:	0f 8d 92 00 00 00    	jge    109136b <my.sexpr_parser::next_token+0xd2b>
 10912d9:	31 c9                	xor    %ecx,%ecx
 10912db:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 10912df:	49 0f 4c ca          	cmovl  %r10,%rcx
 10912e3:	48 01 f1             	add    %rsi,%rcx
 10912e6:	4c 39 d1             	cmp    %r10,%rcx
 10912e9:	0f 83 6a 0b 00 00    	jae    1091e59 <my.sexpr_parser::next_token+0x1819>
 10912ef:	0f b6 0c 0f          	movzbl (%rdi,%rcx,1),%ecx
 10912f3:	41 89 cb             	mov    %ecx,%r11d
 10912f6:	41 81 e3 df 00 00 00 	and    $0xdf,%r11d
 10912fd:	41 83 c3 bf          	add    $0xffffffbf,%r11d
 1091301:	41 b1 01             	mov    $0x1,%r9b
 1091304:	40 b6 01             	mov    $0x1,%sil
 1091307:	41 83 fb 1a          	cmp    $0x1a,%r11d
 109130b:	0f 83 34 02 00 00    	jae    1091545 <my.sexpr_parser::next_token+0xf05>
 1091311:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
 1091315:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 109131a:	c5 f9 74 05 5e 2f f7 	vpcmpeqb -0x8d0a2(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 1091321:	ff 
 1091322:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 1091327:	c5 78 50 d8          	vmovmskps %xmm0,%r11d
 109132b:	45 85 db             	test   %r11d,%r11d
 109132e:	0f 85 af 01 00 00    	jne    10914e3 <my.sexpr_parser::next_token+0xea3>
 1091334:	41 89 cb             	mov    %ecx,%r11d
 1091337:	41 83 e3 fd          	and    $0xfffffffd,%r11d
 109133b:	41 83 fb 2d          	cmp    $0x2d,%r11d
 109133f:	0f 84 9e 01 00 00    	je     10914e3 <my.sexpr_parser::next_token+0xea3>
 1091345:	41 89 cb             	mov    %ecx,%r11d
 1091348:	41 83 e3 fb          	and    $0xfffffffb,%r11d
 109134c:	41 83 fb 2a          	cmp    $0x2a,%r11d
 1091350:	0f 84 8d 01 00 00    	je     10914e3 <my.sexpr_parser::next_token+0xea3>
 1091356:	83 c1 d5             	add    $0xffffffd5,%ecx
 1091359:	80 f9 02             	cmp    $0x2,%cl
 109135c:	0f 82 81 01 00 00    	jb     10914e3 <my.sexpr_parser::next_token+0xea3>
 1091362:	40 84 f6             	test   %sil,%sil
 1091365:	0f 85 78 01 00 00    	jne    10914e3 <my.sexpr_parser::next_token+0xea3>
 109136b:	4c 39 d0             	cmp    %r10,%rax
 109136e:	7d 37                	jge    10913a7 <my.sexpr_parser::next_token+0xd67>
 1091370:	4d 39 d4             	cmp    %r10,%r12
 1091373:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 1091378:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 109137d:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091381:	0f 83 e5 09 00 00    	jae    1091d6c <my.sexpr_parser::next_token+0x172c>
 1091387:	42 80 3c 27 0a       	cmpb   $0xa,(%rdi,%r12,1)
 109138c:	75 2e                	jne    10913bc <my.sexpr_parser::next_token+0xd7c>
 109138e:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 1091393:	49 ff c4             	inc    %r12
 1091396:	0f 80 5e 0a 00 00    	jo     1091dfa <my.sexpr_parser::next_token+0x17ba>
 109139c:	4c 89 62 08          	mov    %r12,0x8(%rdx)
 10913a0:	b9 01 00 00 00       	mov    $0x1,%ecx
 10913a5:	eb 2b                	jmp    10913d2 <my.sexpr_parser::next_token+0xd92>
 10913a7:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 10913ac:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 10913b1:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 10913b6:	4c 8b 1c 24          	mov    (%rsp),%r11
 10913ba:	eb 25                	jmp    10913e1 <my.sexpr_parser::next_token+0xda1>
 10913bc:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 10913c1:	48 89 f1             	mov    %rsi,%rcx
 10913c4:	48 ff c1             	inc    %rcx
 10913c7:	0f 80 0b 0a 00 00    	jo     1091dd8 <my.sexpr_parser::next_token+0x1798>
 10913cd:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 10913d2:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
 10913d7:	48 89 4a 10          	mov    %rcx,0x10(%rdx)
 10913db:	48 ff c0             	inc    %rax
 10913de:	48 89 02             	mov    %rax,(%rdx)
 10913e1:	45 84 c9             	test   %r9b,%r9b
 10913e4:	75 43                	jne    1091429 <my.sexpr_parser::next_token+0xde9>
 10913e6:	4c 39 d0             	cmp    %r10,%rax
 10913e9:	7d 3e                	jge    1091429 <my.sexpr_parser::next_token+0xde9>
 10913eb:	48 89 c1             	mov    %rax,%rcx
 10913ee:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10913f2:	4c 21 d1             	and    %r10,%rcx
 10913f5:	48 01 c1             	add    %rax,%rcx
 10913f8:	4c 39 d1             	cmp    %r10,%rcx
 10913fb:	41 b9 07 00 00 00    	mov    $0x7,%r9d
 1091401:	0f 83 65 09 00 00    	jae    1091d6c <my.sexpr_parser::next_token+0x172c>
 1091407:	80 3c 0f 0a          	cmpb   $0xa,(%rdi,%rcx,1)
 109140b:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 1091410:	75 25                	jne    1091437 <my.sexpr_parser::next_token+0xdf7>
 1091412:	4c 89 e1             	mov    %r12,%rcx
 1091415:	48 ff c1             	inc    %rcx
 1091418:	0f 80 e1 09 00 00    	jo     1091dff <my.sexpr_parser::next_token+0x17bf>
 109141e:	48 89 4a 08          	mov    %rcx,0x8(%rdx)
 1091422:	b9 01 00 00 00       	mov    $0x1,%ecx
 1091427:	eb 1a                	jmp    1091443 <my.sexpr_parser::next_token+0xe03>
 1091429:	48 89 d9             	mov    %rbx,%rcx
 109142c:	41 b9 07 00 00 00    	mov    $0x7,%r9d
 1091432:	e9 70 f6 ff ff       	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 1091437:	48 89 f1             	mov    %rsi,%rcx
 109143a:	48 ff c1             	inc    %rcx
 109143d:	0f 80 95 09 00 00    	jo     1091dd8 <my.sexpr_parser::next_token+0x1798>
 1091443:	48 89 4a 10          	mov    %rcx,0x10(%rdx)
 1091447:	48 ff c0             	inc    %rax
 109144a:	48 89 02             	mov    %rax,(%rdx)
 109144d:	48 89 d9             	mov    %rbx,%rcx
 1091450:	e9 52 f6 ff ff       	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 1091455:	83 fd 47             	cmp    $0x47,%ebp
 1091458:	7f 77                	jg     10914d1 <my.sexpr_parser::next_token+0xe91>
 109145a:	83 fd 25             	cmp    $0x25,%ebp
 109145d:	0f 84 98 03 00 00    	je     10917fb <my.sexpr_parser::next_token+0x11bb>
 1091463:	83 fd 41             	cmp    $0x41,%ebp
 1091466:	0f 84 5d fe ff ff    	je     10912c9 <my.sexpr_parser::next_token+0xc89>
 109146c:	eb 75                	jmp    10914e3 <my.sexpr_parser::next_token+0xea3>
 109146e:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
 1091473:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 1091478:	4c 89 6a 18          	mov    %r13,0x18(%rdx)
 109147c:	4c 89 72 20          	mov    %r14,0x20(%rdx)
 1091480:	48 89 5a 28          	mov    %rbx,0x28(%rdx)
 1091484:	48 8d 3d 25 f7 05 00 	lea    0x5f725(%rip),%rdi        # 10f0bb0 <core_durable_error.verbs+0x55b0>
 109148b:	e8 f0 e3 fd ff       	call   106f880 <myl_core_err_trace_origin_preserve_most>
 1091490:	48 8d 05 89 af f8 ff 	lea    -0x75077(%rip),%rax        # 101c420 <core_number_pairs+0x14ed0>
 1091497:	48 89 04 24          	mov    %rax,(%rsp)
 109149b:	bd 02 00 00 00       	mov    $0x2,%ebp
 10914a0:	e9 8a f8 ff ff       	jmp    1090d2f <my.sexpr_parser::next_token+0x6ef>
 10914a5:	48 83 f9 2a          	cmp    $0x2a,%rcx
 10914a9:	0f 84 8c fb ff ff    	je     109103b <my.sexpr_parser::next_token+0x9fb>
 10914af:	83 f9 5f             	cmp    $0x5f,%ecx
 10914b2:	0f 84 83 fb ff ff    	je     109103b <my.sexpr_parser::next_token+0x9fb>
 10914b8:	83 f9 7e             	cmp    $0x7e,%ecx
 10914bb:	0f 84 7a fb ff ff    	je     109103b <my.sexpr_parser::next_token+0x9fb>
 10914c1:	8d 71 d0             	lea    -0x30(%rcx),%esi
 10914c4:	40 80 fe 0a          	cmp    $0xa,%sil
 10914c8:	40 0f 92 c6          	setb   %sil
 10914cc:	e9 6a fb ff ff       	jmp    109103b <my.sexpr_parser::next_token+0x9fb>
 10914d1:	83 fd 48             	cmp    $0x48,%ebp
 10914d4:	0f 84 ef fd ff ff    	je     10912c9 <my.sexpr_parser::next_token+0xc89>
 10914da:	83 fd 52             	cmp    $0x52,%ebp
 10914dd:	0f 84 e6 fd ff ff    	je     10912c9 <my.sexpr_parser::next_token+0xc89>
 10914e3:	89 e9                	mov    %ebp,%ecx
 10914e5:	83 e1 df             	and    $0xffffffdf,%ecx
 10914e8:	83 c1 bf             	add    $0xffffffbf,%ecx
 10914eb:	40 b6 01             	mov    $0x1,%sil
 10914ee:	83 f9 1a             	cmp    $0x1a,%ecx
 10914f1:	73 16                	jae    1091509 <my.sexpr_parser::next_token+0xec9>
 10914f3:	49 89 e9             	mov    %rbp,%r9
 10914f6:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 10914fb:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1091500:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091504:	e9 84 02 00 00       	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091509:	48 83 fd 2a          	cmp    $0x2a,%rbp
 109150d:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 1091512:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1091517:	4c 8b 1c 24          	mov    (%rsp),%r11
 109151b:	49 89 e9             	mov    %rbp,%r9
 109151e:	0f 84 69 02 00 00    	je     109178d <my.sexpr_parser::next_token+0x114d>
 1091524:	83 fd 5f             	cmp    $0x5f,%ebp
 1091527:	0f 84 60 02 00 00    	je     109178d <my.sexpr_parser::next_token+0x114d>
 109152d:	83 fd 7e             	cmp    $0x7e,%ebp
 1091530:	0f 84 57 02 00 00    	je     109178d <my.sexpr_parser::next_token+0x114d>
 1091536:	8d 4d d0             	lea    -0x30(%rbp),%ecx
 1091539:	80 f9 0a             	cmp    $0xa,%cl
 109153c:	40 0f 92 c6          	setb   %sil
 1091540:	e9 48 02 00 00       	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091545:	48 83 f9 2a          	cmp    $0x2a,%rcx
 1091549:	0f 84 c2 fd ff ff    	je     1091311 <my.sexpr_parser::next_token+0xcd1>
 109154f:	83 f9 5f             	cmp    $0x5f,%ecx
 1091552:	0f 84 b9 fd ff ff    	je     1091311 <my.sexpr_parser::next_token+0xcd1>
 1091558:	83 f9 7e             	cmp    $0x7e,%ecx
 109155b:	0f 84 b0 fd ff ff    	je     1091311 <my.sexpr_parser::next_token+0xcd1>
 1091561:	8d 71 d0             	lea    -0x30(%rcx),%esi
 1091564:	40 80 fe 0a          	cmp    $0xa,%sil
 1091568:	40 0f 92 c6          	setb   %sil
 109156c:	e9 a0 fd ff ff       	jmp    1091311 <my.sexpr_parser::next_token+0xcd1>
 1091571:	48 8d 70 02          	lea    0x2(%rax),%rsi
 1091575:	4c 39 d6             	cmp    %r10,%rsi
 1091578:	0f 8d 0c 02 00 00    	jge    109178a <my.sexpr_parser::next_token+0x114a>
 109157e:	31 c9                	xor    %ecx,%ecx
 1091580:	48 83 f8 fe          	cmp    $0xfffffffffffffffe,%rax
 1091584:	49 0f 4c ca          	cmovl  %r10,%rcx
 1091588:	48 01 f1             	add    %rsi,%rcx
 109158b:	4c 39 d1             	cmp    %r10,%rcx
 109158e:	0f 83 fa 08 00 00    	jae    1091e8e <my.sexpr_parser::next_token+0x184e>
 1091594:	80 3c 0f 6c          	cmpb   $0x6c,(%rdi,%rcx,1)
 1091598:	0f 85 ec 01 00 00    	jne    109178a <my.sexpr_parser::next_token+0x114a>
 109159e:	4c 8d 60 03          	lea    0x3(%rax),%r12
 10915a2:	4d 39 d4             	cmp    %r10,%r12
 10915a5:	0f 8d a5 00 00 00    	jge    1091650 <my.sexpr_parser::next_token+0x1010>
 10915ab:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
 10915b0:	31 c9                	xor    %ecx,%ecx
 10915b2:	48 83 f8 fd          	cmp    $0xfffffffffffffffd,%rax
 10915b6:	49 0f 4c ca          	cmovl  %r10,%rcx
 10915ba:	4c 01 e1             	add    %r12,%rcx
 10915bd:	4c 39 d1             	cmp    %r10,%rcx
 10915c0:	0f 83 33 09 00 00    	jae    1091ef9 <my.sexpr_parser::next_token+0x18b9>
 10915c6:	0f b6 0c 0f          	movzbl (%rdi,%rcx,1),%ecx
 10915ca:	41 89 ce             	mov    %ecx,%r14d
 10915cd:	41 81 e6 df 00 00 00 	and    $0xdf,%r14d
 10915d4:	41 83 c6 bf          	add    $0xffffffbf,%r14d
 10915d8:	41 b3 01             	mov    $0x1,%r11b
 10915db:	41 83 fe 1a          	cmp    $0x1a,%r14d
 10915df:	0f 83 fb 04 00 00    	jae    1091ae0 <my.sexpr_parser::next_token+0x14a0>
 10915e5:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
 10915e9:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10915ee:	c5 f9 74 05 8a 2c f7 	vpcmpeqb -0x8d376(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 10915f5:	ff 
 10915f6:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10915fb:	c5 78 50 f0          	vmovmskps %xmm0,%r14d
 10915ff:	45 85 f6             	test   %r14d,%r14d
 1091602:	0f 85 21 05 00 00    	jne    1091b29 <my.sexpr_parser::next_token+0x14e9>
 1091608:	41 89 ce             	mov    %ecx,%r14d
 109160b:	41 83 e6 fd          	and    $0xfffffffd,%r14d
 109160f:	41 83 fe 2d          	cmp    $0x2d,%r14d
 1091613:	0f 84 10 05 00 00    	je     1091b29 <my.sexpr_parser::next_token+0x14e9>
 1091619:	41 89 ce             	mov    %ecx,%r14d
 109161c:	41 83 e6 fb          	and    $0xfffffffb,%r14d
 1091620:	41 83 fe 2a          	cmp    $0x2a,%r14d
 1091624:	0f 84 ff 04 00 00    	je     1091b29 <my.sexpr_parser::next_token+0x14e9>
 109162a:	83 c1 d5             	add    $0xffffffd5,%ecx
 109162d:	80 f9 02             	cmp    $0x2,%cl
 1091630:	0f 82 f3 04 00 00    	jb     1091b29 <my.sexpr_parser::next_token+0x14e9>
 1091636:	45 84 db             	test   %r11b,%r11b
 1091639:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 109163e:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091642:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1091647:	40 b6 01             	mov    $0x1,%sil
 109164a:	0f 85 3d 01 00 00    	jne    109178d <my.sexpr_parser::next_token+0x114d>
 1091650:	4c 8b 54 24 28       	mov    0x28(%rsp),%r10
 1091655:	49 ff c2             	inc    %r10
 1091658:	0f 80 71 08 00 00    	jo     1091ecf <my.sexpr_parser::next_token+0x188f>
 109165e:	4c 89 52 10          	mov    %r10,0x10(%rdx)
 1091662:	48 8d 48 01          	lea    0x1(%rax),%rcx
 1091666:	48 89 0a             	mov    %rcx,(%rdx)
 1091669:	4c 89 d6             	mov    %r10,%rsi
 109166c:	48 ff c6             	inc    %rsi
 109166f:	0f 80 70 08 00 00    	jo     1091ee5 <my.sexpr_parser::next_token+0x18a5>
 1091675:	48 89 72 10          	mov    %rsi,0x10(%rdx)
 1091679:	48 8d 48 02          	lea    0x2(%rax),%rcx
 109167d:	48 89 0a             	mov    %rcx,(%rdx)
 1091680:	48 89 f1             	mov    %rsi,%rcx
 1091683:	48 ff c1             	inc    %rcx
 1091686:	41 b9 06 00 00 00    	mov    $0x6,%r9d
 109168c:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1091691:	0f 81 40 04 00 00    	jno    1091ad7 <my.sexpr_parser::next_token+0x1497>
 1091697:	48 8d 3d c2 02 06 00 	lea    0x602c2(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 109169e:	ba 01 00 00 00       	mov    $0x1,%edx
 10916a3:	e8 18 be fa ff       	call   103d4c0 <myl_core_trap>
 10916a8:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
 10916ad:	41 89 cb             	mov    %ecx,%r11d
 10916b0:	41 80 e3 ef          	and    $0xef,%r11b
 10916b4:	41 80 fb 46          	cmp    $0x46,%r11b
 10916b8:	74 1c                	je     10916d6 <my.sexpr_parser::next_token+0x1096>
 10916ba:	83 c1 bf             	add    $0xffffffbf,%ecx
 10916bd:	83 f9 11             	cmp    $0x11,%ecx
 10916c0:	0f 87 37 03 00 00    	ja     10919fd <my.sexpr_parser::next_token+0x13bd>
 10916c6:	41 bb 81 00 02 00    	mov    $0x20081,%r11d
 10916cc:	41 0f a3 cb          	bt     %ecx,%r11d
 10916d0:	0f 83 27 03 00 00    	jae    10919fd <my.sexpr_parser::next_token+0x13bd>
 10916d6:	48 8d 70 02          	lea    0x2(%rax),%rsi
 10916da:	4c 39 d6             	cmp    %r10,%rsi
 10916dd:	0f 8d b2 f9 ff ff    	jge    1091095 <my.sexpr_parser::next_token+0xa55>
 10916e3:	31 c9                	xor    %ecx,%ecx
 10916e5:	48 83 f8 fe          	cmp    $0xfffffffffffffffe,%rax
 10916e9:	49 0f 4c ca          	cmovl  %r10,%rcx
 10916ed:	48 01 f1             	add    %rsi,%rcx
 10916f0:	4c 39 d1             	cmp    %r10,%rcx
 10916f3:	0f 83 b5 07 00 00    	jae    1091eae <my.sexpr_parser::next_token+0x186e>
 10916f9:	0f b6 0c 0f          	movzbl (%rdi,%rcx,1),%ecx
 10916fd:	41 89 ce             	mov    %ecx,%r14d
 1091700:	41 81 e6 df 00 00 00 	and    $0xdf,%r14d
 1091707:	41 83 c6 bf          	add    $0xffffffbf,%r14d
 109170b:	40 b6 01             	mov    $0x1,%sil
 109170e:	41 b3 01             	mov    $0x1,%r11b
 1091711:	41 83 fe 1a          	cmp    $0x1a,%r14d
 1091715:	0f 83 b5 02 00 00    	jae    10919d0 <my.sexpr_parser::next_token+0x1390>
 109171b:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
 109171f:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1091724:	c5 f9 74 05 54 2b f7 	vpcmpeqb -0x8d4ac(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 109172b:	ff 
 109172c:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 1091731:	c5 78 50 f0          	vmovmskps %xmm0,%r14d
 1091735:	45 85 f6             	test   %r14d,%r14d
 1091738:	0f 85 f8 02 00 00    	jne    1091a36 <my.sexpr_parser::next_token+0x13f6>
 109173e:	41 89 ce             	mov    %ecx,%r14d
 1091741:	41 83 e6 fd          	and    $0xfffffffd,%r14d
 1091745:	41 83 fe 2d          	cmp    $0x2d,%r14d
 1091749:	0f 84 e7 02 00 00    	je     1091a36 <my.sexpr_parser::next_token+0x13f6>
 109174f:	41 89 ce             	mov    %ecx,%r14d
 1091752:	41 83 e6 fb          	and    $0xfffffffb,%r14d
 1091756:	41 83 fe 2a          	cmp    $0x2a,%r14d
 109175a:	0f 84 d6 02 00 00    	je     1091a36 <my.sexpr_parser::next_token+0x13f6>
 1091760:	83 c1 d5             	add    $0xffffffd5,%ecx
 1091763:	80 f9 02             	cmp    $0x2,%cl
 1091766:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 109176b:	0f 82 85 fd ff ff    	jb     10914f6 <my.sexpr_parser::next_token+0xeb6>
 1091771:	45 84 db             	test   %r11b,%r11b
 1091774:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 1091779:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 109177e:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091782:	0f 84 0d f9 ff ff    	je     1091095 <my.sexpr_parser::next_token+0xa55>
 1091788:	eb 03                	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 109178a:	40 b6 01             	mov    $0x1,%sil
 109178d:	c5 f9 6e c5          	vmovd  %ebp,%xmm0
 1091791:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1091796:	c5 f9 74 05 e2 2a f7 	vpcmpeqb -0x8d51e(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 109179d:	ff 
 109179e:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10917a3:	c5 f8 50 c8          	vmovmskps %xmm0,%ecx
 10917a7:	85 c9                	test   %ecx,%ecx
 10917a9:	0f 85 d4 00 00 00    	jne    1091883 <my.sexpr_parser::next_token+0x1243>
 10917af:	44 89 c9             	mov    %r9d,%ecx
 10917b2:	83 e1 fd             	and    $0xfffffffd,%ecx
 10917b5:	83 f9 2d             	cmp    $0x2d,%ecx
 10917b8:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 10917bd:	0f 84 b9 00 00 00    	je     109187c <my.sexpr_parser::next_token+0x123c>
 10917c3:	41 83 e1 fb          	and    $0xfffffffb,%r9d
 10917c7:	41 83 f9 2a          	cmp    $0x2a,%r9d
 10917cb:	0f 84 be 00 00 00    	je     109188f <my.sexpr_parser::next_token+0x124f>
 10917d1:	41 89 f1             	mov    %esi,%r9d
 10917d4:	8d 4d d5             	lea    -0x2b(%rbp),%ecx
 10917d7:	80 f9 02             	cmp    $0x2,%cl
 10917da:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 10917df:	0f 82 e1 00 00 00    	jb     10918c6 <my.sexpr_parser::next_token+0x1286>
 10917e5:	48 89 d9             	mov    %rbx,%rcx
 10917e8:	45 84 c9             	test   %r9b,%r9b
 10917eb:	4c 8b 4c 24 30       	mov    0x30(%rsp),%r9
 10917f0:	0f 84 b1 f2 ff ff    	je     1090aa7 <my.sexpr_parser::next_token+0x467>
 10917f6:	e9 cb 00 00 00       	jmp    10918c6 <my.sexpr_parser::next_token+0x1286>
 10917fb:	4c 8d 60 01          	lea    0x1(%rax),%r12
 10917ff:	4d 39 d4             	cmp    %r10,%r12
 1091802:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 1091807:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 109180c:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091810:	0f 8d a7 02 00 00    	jge    1091abd <my.sexpr_parser::next_token+0x147d>
 1091816:	31 c9                	xor    %ecx,%ecx
 1091818:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 109181c:	49 0f 4c ca          	cmovl  %r10,%rcx
 1091820:	4c 01 e1             	add    %r12,%rcx
 1091823:	4c 39 d1             	cmp    %r10,%rcx
 1091826:	0f 83 91 06 00 00    	jae    1091ebd <my.sexpr_parser::next_token+0x187d>
 109182c:	0f b6 0c 0f          	movzbl (%rdi,%rcx,1),%ecx
 1091830:	41 89 cb             	mov    %ecx,%r11d
 1091833:	41 81 e3 df 00 00 00 	and    $0xdf,%r11d
 109183a:	41 83 c3 bf          	add    $0xffffffbf,%r11d
 109183e:	40 b6 01             	mov    $0x1,%sil
 1091841:	41 83 fb 1a          	cmp    $0x1a,%r11d
 1091845:	0f 82 08 02 00 00    	jb     1091a53 <my.sexpr_parser::next_token+0x1413>
 109184b:	48 83 f9 2a          	cmp    $0x2a,%rcx
 109184f:	0f 84 f9 01 00 00    	je     1091a4e <my.sexpr_parser::next_token+0x140e>
 1091855:	83 f9 5f             	cmp    $0x5f,%ecx
 1091858:	0f 84 f0 01 00 00    	je     1091a4e <my.sexpr_parser::next_token+0x140e>
 109185e:	83 f9 7e             	cmp    $0x7e,%ecx
 1091861:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1091866:	0f 84 e7 01 00 00    	je     1091a53 <my.sexpr_parser::next_token+0x1413>
 109186c:	8d 71 d0             	lea    -0x30(%rcx),%esi
 109186f:	40 80 fe 0a          	cmp    $0xa,%sil
 1091873:	40 0f 92 c6          	setb   %sil
 1091877:	e9 d7 01 00 00       	jmp    1091a53 <my.sexpr_parser::next_token+0x1413>
 109187c:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 1091881:	eb 43                	jmp    10918c6 <my.sexpr_parser::next_token+0x1286>
 1091883:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 1091888:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 109188d:	eb 37                	jmp    10918c6 <my.sexpr_parser::next_token+0x1286>
 109188f:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 1091894:	eb 30                	jmp    10918c6 <my.sexpr_parser::next_token+0x1286>
 1091896:	48 89 f1             	mov    %rsi,%rcx
 1091899:	48 ff c1             	inc    %rcx
 109189c:	0f 80 a7 04 00 00    	jo     1091d49 <my.sexpr_parser::next_token+0x1709>
 10918a2:	48 89 ce             	mov    %rcx,%rsi
 10918a5:	4d 89 f3             	mov    %r14,%r11
 10918a8:	48 89 72 10          	mov    %rsi,0x10(%rdx)
 10918ac:	48 ff c0             	inc    %rax
 10918af:	48 89 02             	mov    %rax,(%rdx)
 10918b2:	49 39 c2             	cmp    %rax,%r10
 10918b5:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 10918ba:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 10918c0:	0f 84 d2 00 00 00    	je     1091998 <my.sexpr_parser::next_token+0x1358>
 10918c6:	48 89 c1             	mov    %rax,%rcx
 10918c9:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10918cd:	4c 21 d1             	and    %r10,%rcx
 10918d0:	4c 8d 0c 01          	lea    (%rcx,%rax,1),%r9
 10918d4:	4d 39 d1             	cmp    %r10,%r9
 10918d7:	0f 83 fb 03 00 00    	jae    1091cd8 <my.sexpr_parser::next_token+0x1698>
 10918dd:	4d 89 de             	mov    %r11,%r14
 10918e0:	48 01 f9             	add    %rdi,%rcx
 10918e3:	0f b6 0c 08          	movzbl (%rax,%rcx,1),%ecx
 10918e7:	41 89 cb             	mov    %ecx,%r11d
 10918ea:	41 81 e3 df 00 00 00 	and    $0xdf,%r11d
 10918f1:	41 83 c3 bf          	add    $0xffffffbf,%r11d
 10918f5:	40 b5 01             	mov    $0x1,%bpl
 10918f8:	41 83 fb 1a          	cmp    $0x1a,%r11d
 10918fc:	73 6e                	jae    109196c <my.sexpr_parser::next_token+0x132c>
 10918fe:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
 1091902:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1091907:	c5 f9 74 05 71 29 f7 	vpcmpeqb -0x8d68f(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 109190e:	ff 
 109190f:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 1091914:	c5 78 50 d8          	vmovmskps %xmm0,%r11d
 1091918:	45 85 db             	test   %r11d,%r11d
 109191b:	75 29                	jne    1091946 <my.sexpr_parser::next_token+0x1306>
 109191d:	41 89 cb             	mov    %ecx,%r11d
 1091920:	41 83 e3 fd          	and    $0xfffffffd,%r11d
 1091924:	41 83 fb 2d          	cmp    $0x2d,%r11d
 1091928:	74 1c                	je     1091946 <my.sexpr_parser::next_token+0x1306>
 109192a:	41 89 cb             	mov    %ecx,%r11d
 109192d:	41 83 e3 fb          	and    $0xfffffffb,%r11d
 1091931:	41 83 fb 2a          	cmp    $0x2a,%r11d
 1091935:	74 0f                	je     1091946 <my.sexpr_parser::next_token+0x1306>
 1091937:	44 8d 59 d5          	lea    -0x2b(%rcx),%r11d
 109193b:	41 80 fb 02          	cmp    $0x2,%r11b
 109193f:	72 05                	jb     1091946 <my.sexpr_parser::next_token+0x1306>
 1091941:	40 84 ed             	test   %bpl,%bpl
 1091944:	74 47                	je     109198d <my.sexpr_parser::next_token+0x134d>
 1091946:	83 f9 0a             	cmp    $0xa,%ecx
 1091949:	0f 85 47 ff ff ff    	jne    1091896 <my.sexpr_parser::next_token+0x1256>
 109194f:	4c 89 e1             	mov    %r12,%rcx
 1091952:	48 ff c1             	inc    %rcx
 1091955:	0f 80 da 03 00 00    	jo     1091d35 <my.sexpr_parser::next_token+0x16f5>
 109195b:	48 89 4a 08          	mov    %rcx,0x8(%rdx)
 109195f:	be 01 00 00 00       	mov    $0x1,%esi
 1091964:	49 89 cc             	mov    %rcx,%r12
 1091967:	e9 39 ff ff ff       	jmp    10918a5 <my.sexpr_parser::next_token+0x1265>
 109196c:	48 83 f9 2a          	cmp    $0x2a,%rcx
 1091970:	74 8c                	je     10918fe <my.sexpr_parser::next_token+0x12be>
 1091972:	83 f9 5f             	cmp    $0x5f,%ecx
 1091975:	74 87                	je     10918fe <my.sexpr_parser::next_token+0x12be>
 1091977:	83 f9 7e             	cmp    $0x7e,%ecx
 109197a:	74 82                	je     10918fe <my.sexpr_parser::next_token+0x12be>
 109197c:	44 8d 59 d0          	lea    -0x30(%rcx),%r11d
 1091980:	41 80 fb 0a          	cmp    $0xa,%r11b
 1091984:	40 0f 92 c5          	setb   %bpl
 1091988:	e9 71 ff ff ff       	jmp    10918fe <my.sexpr_parser::next_token+0x12be>
 109198d:	48 89 d9             	mov    %rbx,%rcx
 1091990:	4d 89 f3             	mov    %r14,%r11
 1091993:	e9 1e f7 ff ff       	jmp    10910b6 <my.sexpr_parser::next_token+0xa76>
 1091998:	4c 89 d0             	mov    %r10,%rax
 109199b:	48 89 d9             	mov    %rbx,%rcx
 109199e:	e9 04 f1 ff ff       	jmp    1090aa7 <my.sexpr_parser::next_token+0x467>
 10919a3:	48 83 f9 2a          	cmp    $0x2a,%rcx
 10919a7:	0f 84 3b f8 ff ff    	je     10911e8 <my.sexpr_parser::next_token+0xba8>
 10919ad:	83 f9 5f             	cmp    $0x5f,%ecx
 10919b0:	0f 84 32 f8 ff ff    	je     10911e8 <my.sexpr_parser::next_token+0xba8>
 10919b6:	83 f9 7e             	cmp    $0x7e,%ecx
 10919b9:	0f 84 29 f8 ff ff    	je     10911e8 <my.sexpr_parser::next_token+0xba8>
 10919bf:	44 8d 59 d0          	lea    -0x30(%rcx),%r11d
 10919c3:	41 80 fb 0a          	cmp    $0xa,%r11b
 10919c7:	41 0f 92 c3          	setb   %r11b
 10919cb:	e9 18 f8 ff ff       	jmp    10911e8 <my.sexpr_parser::next_token+0xba8>
 10919d0:	48 83 f9 2a          	cmp    $0x2a,%rcx
 10919d4:	0f 84 41 fd ff ff    	je     109171b <my.sexpr_parser::next_token+0x10db>
 10919da:	83 f9 5f             	cmp    $0x5f,%ecx
 10919dd:	0f 84 38 fd ff ff    	je     109171b <my.sexpr_parser::next_token+0x10db>
 10919e3:	83 f9 7e             	cmp    $0x7e,%ecx
 10919e6:	0f 84 2f fd ff ff    	je     109171b <my.sexpr_parser::next_token+0x10db>
 10919ec:	44 8d 59 d0          	lea    -0x30(%rcx),%r11d
 10919f0:	41 80 fb 0a          	cmp    $0xa,%r11b
 10919f4:	41 0f 92 c3          	setb   %r11b
 10919f8:	e9 1e fd ff ff       	jmp    109171b <my.sexpr_parser::next_token+0x10db>
 10919fd:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 1091a02:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1091a07:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091a0b:	40 b6 01             	mov    $0x1,%sil
 1091a0e:	e9 7a fd ff ff       	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091a13:	48 8d 3d b6 fe 05 00 	lea    0x5feb6(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091a1a:	48 89 de             	mov    %rbx,%rsi
 1091a1d:	4c 89 d2             	mov    %r10,%rdx
 1091a20:	e8 9b ba fa ff       	call   103d4c0 <myl_core_trap>
 1091a25:	48 8d 3d 34 ff 05 00 	lea    0x5ff34(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091a2c:	ba 01 00 00 00       	mov    $0x1,%edx
 1091a31:	e8 8a ba fa ff       	call   103d4c0 <myl_core_trap>
 1091a36:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 1091a3b:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1091a40:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091a44:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1091a49:	e9 3f fd ff ff       	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091a4e:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1091a53:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
 1091a57:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 1091a5c:	c5 f9 74 05 1c 28 f7 	vpcmpeqb -0x8d7e4(%rip),%xmm0,%xmm0        # 1004280 <__anon_1393+0x50>
 1091a63:	ff 
 1091a64:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 1091a69:	c5 78 50 d8          	vmovmskps %xmm0,%r11d
 1091a6d:	41 b9 25 00 00 00    	mov    $0x25,%r9d
 1091a73:	45 85 db             	test   %r11d,%r11d
 1091a76:	0f 85 91 00 00 00    	jne    1091b0d <my.sexpr_parser::next_token+0x14cd>
 1091a7c:	41 89 cb             	mov    %ecx,%r11d
 1091a7f:	41 83 e3 fd          	and    $0xfffffffd,%r11d
 1091a83:	41 83 fb 2d          	cmp    $0x2d,%r11d
 1091a87:	0f 84 80 00 00 00    	je     1091b0d <my.sexpr_parser::next_token+0x14cd>
 1091a8d:	41 89 cb             	mov    %ecx,%r11d
 1091a90:	41 83 e3 fb          	and    $0xfffffffb,%r11d
 1091a94:	41 83 fb 2a          	cmp    $0x2a,%r11d
 1091a98:	74 73                	je     1091b0d <my.sexpr_parser::next_token+0x14cd>
 1091a9a:	83 c1 d5             	add    $0xffffffd5,%ecx
 1091a9d:	80 f9 02             	cmp    $0x2,%cl
 1091aa0:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 1091aa5:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1091aaa:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091aae:	0f 82 82 fa ff ff    	jb     1091536 <my.sexpr_parser::next_token+0xef6>
 1091ab4:	40 84 f6             	test   %sil,%sil
 1091ab7:	0f 85 79 fa ff ff    	jne    1091536 <my.sexpr_parser::next_token+0xef6>
 1091abd:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 1091ac2:	48 89 f1             	mov    %rsi,%rcx
 1091ac5:	48 ff c1             	inc    %rcx
 1091ac8:	41 b9 07 00 00 00    	mov    $0x7,%r9d
 1091ace:	4c 89 e0             	mov    %r12,%rax
 1091ad1:	0f 80 c6 03 00 00    	jo     1091e9d <my.sexpr_parser::next_token+0x185d>
 1091ad7:	48 89 4a 10          	mov    %rcx,0x10(%rdx)
 1091adb:	e9 81 ed ff ff       	jmp    1090861 <my.sexpr_parser::next_token+0x221>
 1091ae0:	48 83 f9 2a          	cmp    $0x2a,%rcx
 1091ae4:	0f 84 fb fa ff ff    	je     10915e5 <my.sexpr_parser::next_token+0xfa5>
 1091aea:	83 f9 5f             	cmp    $0x5f,%ecx
 1091aed:	0f 84 f2 fa ff ff    	je     10915e5 <my.sexpr_parser::next_token+0xfa5>
 1091af3:	83 f9 7e             	cmp    $0x7e,%ecx
 1091af6:	0f 84 e9 fa ff ff    	je     10915e5 <my.sexpr_parser::next_token+0xfa5>
 1091afc:	44 8d 59 d0          	lea    -0x30(%rcx),%r11d
 1091b00:	41 80 fb 0a          	cmp    $0xa,%r11b
 1091b04:	41 0f 92 c3          	setb   %r11b
 1091b08:	e9 d8 fa ff ff       	jmp    10915e5 <my.sexpr_parser::next_token+0xfa5>
 1091b0d:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 1091b12:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1091b17:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091b1b:	e9 16 fa ff ff       	jmp    1091536 <my.sexpr_parser::next_token+0xef6>
 1091b20:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091b24:	e9 64 fc ff ff       	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091b29:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 1091b2e:	4c 8b 1c 24          	mov    (%rsp),%r11
 1091b32:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1091b37:	40 b6 01             	mov    $0x1,%sil
 1091b3a:	e9 4e fc ff ff       	jmp    109178d <my.sexpr_parser::next_token+0x114d>
 1091b3f:	48 8d 3d ba fd 05 00 	lea    0x5fdba(%rip),%rdi        # 10f1900 <core_durable_error.verbs+0x6300>
 1091b46:	48 89 de             	mov    %rbx,%rsi
 1091b49:	4c 89 d2             	mov    %r10,%rdx
 1091b4c:	e8 6f b9 fa ff       	call   103d4c0 <myl_core_trap>
 1091b51:	48 8d 3d 78 fd 05 00 	lea    0x5fd78(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091b58:	48 89 c6             	mov    %rax,%rsi
 1091b5b:	4c 89 d2             	mov    %r10,%rdx
 1091b5e:	e8 5d b9 fa ff       	call   103d4c0 <myl_core_trap>
 1091b63:	48 8d 3d c6 fd 05 00 	lea    0x5fdc6(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091b6a:	ba 01 00 00 00       	mov    $0x1,%edx
 1091b6f:	e8 4c b9 fa ff       	call   103d4c0 <myl_core_trap>
 1091b74:	48 8d 3d e5 fd 05 00 	lea    0x5fde5(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091b7b:	ba 01 00 00 00       	mov    $0x1,%edx
 1091b80:	e8 3b b9 fa ff       	call   103d4c0 <myl_core_trap>
 1091b85:	48 8d 3d 44 fd 05 00 	lea    0x5fd44(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091b8c:	48 89 de             	mov    %rbx,%rsi
 1091b8f:	4c 89 d2             	mov    %r10,%rdx
 1091b92:	e8 29 b9 fa ff       	call   103d4c0 <myl_core_trap>
 1091b97:	48 8d 3d c2 fd 05 00 	lea    0x5fdc2(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091b9e:	ba 01 00 00 00       	mov    $0x1,%edx
 1091ba3:	4c 89 e6             	mov    %r12,%rsi
 1091ba6:	e8 15 b9 fa ff       	call   103d4c0 <myl_core_trap>
 1091bab:	48 8d 3d 7e fd 05 00 	lea    0x5fd7e(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091bb2:	ba 01 00 00 00       	mov    $0x1,%edx
 1091bb7:	4c 89 de             	mov    %r11,%rsi
 1091bba:	e8 01 b9 fa ff       	call   103d4c0 <myl_core_trap>
 1091bbf:	48 8d 3d 3a fd 05 00 	lea    0x5fd3a(%rip),%rdi        # 10f1900 <core_durable_error.verbs+0x6300>
 1091bc6:	48 89 ee             	mov    %rbp,%rsi
 1091bc9:	4c 89 d2             	mov    %r10,%rdx
 1091bcc:	e8 ef b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091bd1:	48 8d 3d 88 fd 05 00 	lea    0x5fd88(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091bd8:	ba 01 00 00 00       	mov    $0x1,%edx
 1091bdd:	4c 89 e6             	mov    %r12,%rsi
 1091be0:	e8 db b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091be5:	48 8d 3d 44 fd 05 00 	lea    0x5fd44(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091bec:	ba 01 00 00 00       	mov    $0x1,%edx
 1091bf1:	4c 89 de             	mov    %r11,%rsi
 1091bf4:	e8 c7 b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091bf9:	48 8d 3d 60 fd 05 00 	lea    0x5fd60(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091c00:	ba 01 00 00 00       	mov    $0x1,%edx
 1091c05:	4c 89 ee             	mov    %r13,%rsi
 1091c08:	e8 b3 b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091c0d:	48 8d 3d bc fc 05 00 	lea    0x5fcbc(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091c14:	4c 89 fe             	mov    %r15,%rsi
 1091c17:	4c 89 d2             	mov    %r10,%rdx
 1091c1a:	e8 a1 b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091c1f:	48 8d 3d 3a fd 05 00 	lea    0x5fd3a(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091c26:	48 be ff ff ff ff ff 	movabs $0x7fffffffffffffff,%rsi
 1091c2d:	ff ff 7f 
 1091c30:	ba 01 00 00 00       	mov    $0x1,%edx
 1091c35:	e8 86 b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091c3a:	48 8d 3d 8f fc 05 00 	lea    0x5fc8f(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091c41:	48 89 de             	mov    %rbx,%rsi
 1091c44:	4c 89 d2             	mov    %r10,%rdx
 1091c47:	e8 74 b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091c4c:	48 8d 3d 7d fc 05 00 	lea    0x5fc7d(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091c53:	48 89 c6             	mov    %rax,%rsi
 1091c56:	4c 89 d2             	mov    %r10,%rdx
 1091c59:	e8 62 b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091c5e:	48 8d 3d cb fc 05 00 	lea    0x5fccb(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091c65:	ba 01 00 00 00       	mov    $0x1,%edx
 1091c6a:	4c 89 de             	mov    %r11,%rsi
 1091c6d:	e8 4e b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091c72:	48 8d 3d e7 fc 05 00 	lea    0x5fce7(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091c79:	ba 01 00 00 00       	mov    $0x1,%edx
 1091c7e:	4c 89 e6             	mov    %r12,%rsi
 1091c81:	e8 3a b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091c86:	48 8d 3d d3 fc 05 00 	lea    0x5fcd3(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091c8d:	ba 01 00 00 00       	mov    $0x1,%edx
 1091c92:	4c 89 f6             	mov    %r14,%rsi
 1091c95:	e8 26 b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091c9a:	48 8d 3d bf fc 05 00 	lea    0x5fcbf(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ca1:	ba 01 00 00 00       	mov    $0x1,%edx
 1091ca6:	4c 89 f6             	mov    %r14,%rsi
 1091ca9:	e8 12 b8 fa ff       	call   103d4c0 <myl_core_trap>
 1091cae:	48 8d 3d ab fc 05 00 	lea    0x5fcab(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091cb5:	ba 01 00 00 00       	mov    $0x1,%edx
 1091cba:	48 8b 74 24 08       	mov    0x8(%rsp),%rsi
 1091cbf:	e8 fc b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091cc4:	48 8d 3d 95 fc 05 00 	lea    0x5fc95(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ccb:	ba 01 00 00 00       	mov    $0x1,%edx
 1091cd0:	4c 89 e6             	mov    %r12,%rsi
 1091cd3:	e8 e8 b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091cd8:	48 8d 3d f1 fb 05 00 	lea    0x5fbf1(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091cdf:	48 89 c6             	mov    %rax,%rsi
 1091ce2:	4c 89 d2             	mov    %r10,%rdx
 1091ce5:	e8 d6 b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091cea:	48 89 2a             	mov    %rbp,(%rdx)
 1091ced:	48 8d 3d dc fb 05 00 	lea    0x5fbdc(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091cf4:	48 89 ee             	mov    %rbp,%rsi
 1091cf7:	4c 89 d2             	mov    %r10,%rdx
 1091cfa:	e8 c1 b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091cff:	4c 29 c8             	sub    %r9,%rax
 1091d02:	48 be ff ff ff ff ff 	movabs $0x7fffffffffffffff,%rsi
 1091d09:	ff ff 7f 
 1091d0c:	48 01 f0             	add    %rsi,%rax
 1091d0f:	48 89 02             	mov    %rax,(%rdx)
 1091d12:	48 8d 3d 47 fc 05 00 	lea    0x5fc47(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091d19:	ba 01 00 00 00       	mov    $0x1,%edx
 1091d1e:	e8 9d b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091d23:	48 8d 3d a6 fb 05 00 	lea    0x5fba6(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091d2a:	48 89 c6             	mov    %rax,%rsi
 1091d2d:	4c 89 d2             	mov    %r10,%rdx
 1091d30:	e8 8b b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091d35:	48 8d 3d f4 fb 05 00 	lea    0x5fbf4(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091d3c:	ba 01 00 00 00       	mov    $0x1,%edx
 1091d41:	4c 89 e6             	mov    %r12,%rsi
 1091d44:	e8 77 b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091d49:	48 8d 3d 10 fc 05 00 	lea    0x5fc10(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091d50:	ba 01 00 00 00       	mov    $0x1,%edx
 1091d55:	e8 66 b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091d5a:	48 8d 3d 5f fc 05 00 	lea    0x5fc5f(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091d61:	48 89 c6             	mov    %rax,%rsi
 1091d64:	4c 89 d2             	mov    %r10,%rdx
 1091d67:	e8 54 b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091d6c:	48 8d 3d 8d fb 05 00 	lea    0x5fb8d(%rip),%rdi        # 10f1900 <core_durable_error.verbs+0x6300>
 1091d73:	48 89 c6             	mov    %rax,%rsi
 1091d76:	4c 89 d2             	mov    %r10,%rdx
 1091d79:	e8 42 b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091d7e:	48 8d 3d ab fb 05 00 	lea    0x5fbab(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091d85:	ba 01 00 00 00       	mov    $0x1,%edx
 1091d8a:	e8 31 b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091d8f:	48 8d 3d ca fb 05 00 	lea    0x5fbca(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091d96:	ba 01 00 00 00       	mov    $0x1,%edx
 1091d9b:	4c 89 f6             	mov    %r14,%rsi
 1091d9e:	e8 1d b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091da3:	48 8d 3d 26 fb 05 00 	lea    0x5fb26(%rip),%rdi        # 10f18d0 <core_durable_error.verbs+0x62d0>
 1091daa:	48 89 c6             	mov    %rax,%rsi
 1091dad:	4c 89 d2             	mov    %r10,%rdx
 1091db0:	e8 0b b7 fa ff       	call   103d4c0 <myl_core_trap>
 1091db5:	48 8d 3d 04 fc 05 00 	lea    0x5fc04(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091dbc:	4c 89 d2             	mov    %r10,%rdx
 1091dbf:	e8 fc b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091dc4:	48 8d 3d 95 fb 05 00 	lea    0x5fb95(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091dcb:	ba 01 00 00 00       	mov    $0x1,%edx
 1091dd0:	4c 89 f6             	mov    %r14,%rsi
 1091dd3:	e8 e8 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091dd8:	48 8d 3d 81 fb 05 00 	lea    0x5fb81(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ddf:	ba 01 00 00 00       	mov    $0x1,%edx
 1091de4:	e8 d7 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091de9:	48 8d 3d 70 fb 05 00 	lea    0x5fb70(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091df0:	ba 01 00 00 00       	mov    $0x1,%edx
 1091df5:	e8 c6 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091dfa:	4c 8b 64 24 20       	mov    0x20(%rsp),%r12
 1091dff:	48 8d 3d 2a fb 05 00 	lea    0x5fb2a(%rip),%rdi        # 10f1930 <core_durable_error.verbs+0x6330>
 1091e06:	ba 01 00 00 00       	mov    $0x1,%edx
 1091e0b:	4c 89 e6             	mov    %r12,%rsi
 1091e0e:	e8 ad b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091e13:	48 8d 3d a6 fb 05 00 	lea    0x5fba6(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e1a:	48 89 ee             	mov    %rbp,%rsi
 1091e1d:	4c 89 d2             	mov    %r10,%rdx
 1091e20:	e8 9b b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091e25:	48 8d 3d 34 fb 05 00 	lea    0x5fb34(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091e2c:	ba 01 00 00 00       	mov    $0x1,%edx
 1091e31:	e8 8a b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091e36:	48 8d 3d 83 fb 05 00 	lea    0x5fb83(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e3d:	4c 89 d2             	mov    %r10,%rdx
 1091e40:	e8 7b b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091e45:	48 8d 3d 74 fb 05 00 	lea    0x5fb74(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e4c:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 1091e51:	4c 89 d2             	mov    %r10,%rdx
 1091e54:	e8 67 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091e59:	48 8d 3d 60 fb 05 00 	lea    0x5fb60(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e60:	4c 89 d2             	mov    %r10,%rdx
 1091e63:	e8 58 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091e68:	48 8d 3d f1 fa 05 00 	lea    0x5faf1(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091e6f:	ba 01 00 00 00       	mov    $0x1,%edx
 1091e74:	48 89 ce             	mov    %rcx,%rsi
 1091e77:	e8 44 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091e7c:	48 8d 3d 3d fb 05 00 	lea    0x5fb3d(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e83:	4c 89 e6             	mov    %r12,%rsi
 1091e86:	4c 89 d2             	mov    %r10,%rdx
 1091e89:	e8 32 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091e8e:	48 8d 3d 2b fb 05 00 	lea    0x5fb2b(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091e95:	4c 89 d2             	mov    %r10,%rdx
 1091e98:	e8 23 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091e9d:	48 8d 3d bc fa 05 00 	lea    0x5fabc(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ea4:	ba 01 00 00 00       	mov    $0x1,%edx
 1091ea9:	e8 12 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091eae:	48 8d 3d 0b fb 05 00 	lea    0x5fb0b(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091eb5:	4c 89 d2             	mov    %r10,%rdx
 1091eb8:	e8 03 b6 fa ff       	call   103d4c0 <myl_core_trap>
 1091ebd:	48 8d 3d fc fa 05 00 	lea    0x5fafc(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091ec4:	4c 89 e6             	mov    %r12,%rsi
 1091ec7:	4c 89 d2             	mov    %r10,%rdx
 1091eca:	e8 f1 b5 fa ff       	call   103d4c0 <myl_core_trap>
 1091ecf:	48 8d 3d 8a fa 05 00 	lea    0x5fa8a(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091ed6:	ba 01 00 00 00       	mov    $0x1,%edx
 1091edb:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 1091ee0:	e8 db b5 fa ff       	call   103d4c0 <myl_core_trap>
 1091ee5:	48 8d 3d 74 fa 05 00 	lea    0x5fa74(%rip),%rdi        # 10f1960 <core_durable_error.verbs+0x6360>
 1091eec:	ba 01 00 00 00       	mov    $0x1,%edx
 1091ef1:	4c 89 d6             	mov    %r10,%rsi
 1091ef4:	e8 c7 b5 fa ff       	call   103d4c0 <myl_core_trap>
 1091ef9:	48 8d 3d c0 fa 05 00 	lea    0x5fac0(%rip),%rdi        # 10f19c0 <core_durable_error.verbs+0x63c0>
 1091f00:	4c 89 e6             	mov    %r12,%rsi
 1091f03:	4c 89 d2             	mov    %r10,%rdx
 1091f06:	e8 b5 b5 fa ff       	call   103d4c0 <myl_core_trap>

Disassembly of section .plt:
