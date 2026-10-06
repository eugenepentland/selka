
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-applications/.mylang-cache/s3-a/word-dict-store-04/row_word_count_new:     file format elf64-x86-64


Disassembly of section .text:

0000000001032740 <main>:
 1032740:	push   %rbp
 1032741:	push   %r15
 1032743:	push   %r14
 1032745:	push   %r13
 1032747:	push   %r12
 1032749:	push   %rbx
 103274a:	sub    $0xd8,%rsp
 1032751:	call   10099b0 <myl_core_args>
 1032756:	mov    %rax,%rbx
 1032759:	call   1022380 <myl_core_host_grant>
 103275e:	mov    %rbx,%rdi
 1032761:	mov    $0x2,%ebx
 1032766:	cmpq   $0x3,0x8(%rdi)
 103276b:	jne    10327fa <main+0xba>
 1032771:	mov    %rax,0x40(%rsp)
 1032776:	mov    %rdi,0x8(%rsp)
 103277b:	mov    0x8(%rsp),%rax
 1032780:	mov    0x20(%rax),%rdi
 1032784:	call   1032540 <my.row_word_count::number>
 1032789:	mov    %rax,%r14
 103278c:	mov    0x8(%rsp),%rax
 1032791:	mov    0x8(%rax),%rdx
 1032795:	cmp    $0x1,%rdx
 1032799:	jbe    10333fb <main+0xcbb>
 103279f:	mov    0x8(%rsp),%rax
 10327a4:	mov    0x28(%rax),%rdi
 10327a8:	call   1032540 <my.row_word_count::number>
 10327ad:	mov    %rax,%r15
 10327b0:	mov    0x8(%rsp),%rax
 10327b5:	mov    0x8(%rax),%rdx
 10327b9:	cmp    $0x2,%rdx
 10327bd:	jbe    103340a <main+0xcca>
 10327c3:	mov    0x8(%rsp),%rax
 10327c8:	mov    0x30(%rax),%rdi
 10327cc:	call   1032540 <my.row_word_count::number>
 10327d1:	mov    0x8(%rsp),%rdi
 10327d6:	cmp    $0x2,%r14
 10327da:	setl   %dl
 10327dd:	test   %r15,%r15
 10327e0:	setle  %cl
 10327e3:	or     %dl,%cl
 10327e5:	lea    -0xf4241(%rax),%rdx
 10327ec:	cmp    $0xfffffffffff0bdc0,%rdx
 10327f3:	setb   %dl
 10327f6:	or     %cl,%dl
 10327f8:	je     1032819 <main+0xd9>
 10327fa:	call   1009980 <myl_core_release>
 10327ff:	mov    %rbx,%rdi
 1032802:	call   100a2d0 <myl_core_exit>
 1032807:	add    $0xd8,%rsp
 103280e:	pop    %rbx
 103280f:	pop    %r12
 1032811:	pop    %r13
 1032813:	pop    %r14
 1032815:	pop    %r15
 1032817:	pop    %rbp
 1032818:	ret
 1032819:	mov    %r15,0x88(%rsp)
 1032821:	lea    0xb0(%rsp),%rdi
 1032829:	mov    %r14,%rsi
 103282c:	mov    %rax,0x48(%rsp)
 1032831:	mov    %rax,%rdx
 1032834:	call   1033440 <my.row_word_count::inputs>
 1032839:	mov    $0x9,%edi
 103283e:	call   100a2c0 <myl_core_io_at>
 1032843:	mov    0x40(%rsp),%rdi
 1032848:	call   10223b0 <myl_core_host_check>
 103284d:	call   1033cd0 <runtime_bench_now>
 1032852:	mov    %rax,0x78(%rsp)
 1032857:	xor    %r14d,%r14d
 103285a:	mov    0xb8(%rsp),%rax
 1032862:	xor    %edx,%edx
 1032864:	mov    %rax,0x80(%rsp)
 103286c:	nopl   0x0(%rax)
 1032870:	mov    0x48(%rsp),%rsi
 1032875:	add    %rdx,%rsi
 1032878:	jo     10333df <main+0xc9f>
 103287e:	mov    %rdx,0x90(%rsp)
 1032886:	mov    %r14,0x98(%rsp)
 103288e:	and    $0x1,%esi
 1032891:	mov    0x8(%rax),%rdx
 1032895:	cmp    %rdx,%rsi
 1032898:	jae    10333d5 <main+0xc95>
 103289e:	mov    0x20(%rax,%rsi,8),%rbx
 10328a3:	xor    %edi,%edi
 10328a5:	lea    0x2e74(%rip),%rsi        # 1035720 <myl_core_sites+0x500>
 10328ac:	call   100f770 <myl_core_dict_new>
 10328b1:	mov    %rax,%r14
 10328b4:	mov    %rbx,%rdi
 10328b7:	xor    %esi,%esi
 10328b9:	call   1013b20 <myl_core_split_ws_start>
 10328be:	mov    %rax,%r15
 10328c1:	mov    0x8(%rbx),%rax
 10328c5:	mov    %rax,0x20(%rsp)
 10328ca:	cmp    %rax,%r15
 10328cd:	jge    1032c30 <main+0x4f0>
 10328d3:	lea    0x20(%rbx),%rax
 10328d7:	mov    %rax,0x60(%rsp)
 10328dc:	mov    %rbx,0x18(%rsp)
 10328e1:	jmp    103296a <main+0x22a>
 10328e6:	cs nopw 0x0(%rax,%rax,1)
 10328f0:	cmpq   $0x0,0x18(%rcx)
 10328f5:	je     1032ba5 <main+0x465>
 10328fb:	mov    (%rsp),%rdi
 10328ff:	lea    0x38(%rsp),%rsi
 1032904:	mov    %rbp,%rdx
 1032907:	call   100f400 <myl_core_dict_find>
 103290c:	mov    %rax,%r12
 103290f:	mov    0x10(%rsp),%rax
 1032914:	mov    %rax,0xa8(%rsp)
 103291c:	movq   $0x1,0xa0(%rsp)
 1032928:	mov    (%rsp),%rdi
 103292c:	mov    %r12,%rsi
 103292f:	lea    0xa8(%rsp),%rdx
 1032937:	lea    0xa0(%rsp),%rcx
 103293f:	xor    %r8d,%r8d
 1032942:	call   100f960 <myl_core_dict_insert>
 1032947:	mov    %rax,%r14
 103294a:	mov    0x18(%rsp),%rbx
 103294f:	mov    %rbx,%rdi
 1032952:	mov    0x28(%rsp),%rsi
 1032957:	call   1013b20 <myl_core_split_ws_start>
 103295c:	mov    %rax,%r15
 103295f:	cmp    0x20(%rsp),%rax
 1032964:	jge    1032c30 <main+0x4f0>
 103296a:	mov    %rbx,%rdi
 103296d:	mov    %r15,%rsi
 1032970:	call   1013b70 <myl_core_split_ws_end>
 1032975:	test   %r15,%r15
 1032978:	js     1033366 <main+0xc26>
 103297e:	mov    %rax,%rbp
 1032981:	sub    %r15,%rbp
 1032984:	jo     1033375 <main+0xc35>
 103298a:	js     1033385 <main+0xc45>
 1032990:	mov    %rax,0x28(%rsp)
 1032995:	add    0x60(%rsp),%r15
 103299a:	mov    0x18(%r14),%rbx
 103299e:	mov    0x8(%rbx),%rax
 10329a2:	or     0x18(%rbx),%rax
 10329a6:	mov    %r14,(%rsp)
 10329aa:	mov    %r15,0x10(%rsp)
 10329af:	jne    1032a70 <main+0x330>
 10329b5:	mov    %r15,%rdi
 10329b8:	mov    %rbp,%rsi
 10329bb:	call   1010a60 <myl_core_span_hash>
 10329c0:	mov    0x20(%rbx),%r14
 10329c4:	test   %r14,%r14
 10329c7:	je     1032a86 <main+0x346>
 10329cd:	mov    %eax,%eax
 10329cf:	movabs $0x9e3779b97f4a7c15,%rcx
 10329d9:	imul   %rcx,%rax
 10329dd:	mov    %rax,%r15
 10329e0:	shr    $0x20,%r15
 10329e4:	xor    %rax,%r15
 10329e7:	mov    0x10(%rbx),%rbx
 10329eb:	mov    (%rsp),%rax
 10329ef:	lea    0x20(%rax),%r13
 10329f3:	xor    %r12d,%r12d
 10329f6:	jmp    1032a0c <main+0x2cc>
 10329f8:	nopl   0x0(%rax,%rax,1)
 1032a00:	inc    %r12
 1032a03:	add    $0x10,%r13
 1032a07:	cmp    %r12,%r14
 1032a0a:	je     1032a86 <main+0x346>
 1032a0c:	cmp    %r15,(%rbx,%r12,8)
 1032a10:	jne    1032a00 <main+0x2c0>
 1032a12:	mov    0x0(%r13),%rdi
 1032a16:	cmp    %rbp,0x8(%rdi)
 1032a1a:	jne    1032a00 <main+0x2c0>
 1032a1c:	add    $0x20,%rdi
 1032a20:	mov    0x10(%rsp),%rsi
 1032a25:	mov    %rbp,%rdx
 1032a28:	call   1033e10 <bcmp@plt>
 1032a2d:	test   %eax,%eax
 1032a2f:	jne    1032a00 <main+0x2c0>
 1032a31:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032a40:	test   %r12,%r12
 1032a43:	js     1032a86 <main+0x346>
 1032a45:	shl    $0x4,%r12
 1032a49:	mov    (%rsp),%r14
 1032a4d:	mov    0x28(%r14,%r12,1),%rsi
 1032a52:	mov    %rsi,%rax
 1032a55:	inc    %rax
 1032a58:	jo     1033394 <main+0xc54>
 1032a5e:	mov    %rax,0x28(%r14,%r12,1)
 1032a63:	jmp    103294a <main+0x20a>
 1032a68:	nopl   0x0(%rax,%rax,1)
 1032a70:	mov    %r14,%rdi
 1032a73:	mov    %r15,%rsi
 1032a76:	mov    %rbp,%rdx
 1032a79:	call   10106c0 <myl_core_dict_find_span>
 1032a7e:	mov    %rax,%r12
 1032a81:	test   %r12,%r12
 1032a84:	jns    1032a45 <main+0x305>
 1032a86:	mov    0x10(%rsp),%rdi
 1032a8b:	mov    %rbp,%rsi
 1032a8e:	call   1011370 <myl_core_ir_str_from_view>
 1032a93:	mov    %rax,0x38(%rsp)
 1032a98:	testb  $0x2,0x5(%rax)
 1032a9c:	mov    %rax,0x10(%rsp)
 1032aa1:	jne    1032ab0 <main+0x370>
 1032aa3:	mov    %rax,%rdi
 1032aa6:	call   1010b70 <myl_core_str_hash>
 1032aab:	jmp    1032ab3 <main+0x373>
 1032aad:	nopl   (%rax)
 1032ab0:	mov    0x18(%rax),%eax
 1032ab3:	mov    (%rsp),%rdx
 1032ab7:	mov    %eax,%eax
 1032ab9:	movabs $0x9e3779b97f4a7c15,%rcx
 1032ac3:	imul   %rcx,%rax
 1032ac7:	mov    %rax,%rbp
 1032aca:	shr    $0x20,%rbp
 1032ace:	xor    %rax,%rbp
 1032ad1:	mov    0x18(%rdx),%rcx
 1032ad5:	mov    0x8(%rcx),%rax
 1032ad9:	test   %rax,%rax
 1032adc:	je     10328f0 <main+0x1b0>
 1032ae2:	mov    (%rax),%ecx
 1032ae4:	tzcnt  %ecx,%edx
 1032ae8:	neg    %dl
 1032aea:	shrx   %rdx,%rbp,%r14
 1032aef:	lea    -0x1(%rcx),%r15d
 1032af3:	vmovdqu 0x10(%rax,%r14,1),%xmm1
 1032afa:	mov    %ebp,%edx
 1032afc:	and    $0x7f,%dl
 1032aff:	vmovd  %edx,%xmm0
 1032b03:	vpbroadcastb %xmm0,%xmm0
 1032b08:	vmovdqa %xmm1,0x50(%rsp)
 1032b0e:	vpcmpeqb %xmm0,%xmm1,%xmm0
 1032b12:	vpmovmskb %xmm0,%edx
 1032b16:	test   %edx,%edx
 1032b18:	je     1032b78 <main+0x438>
 1032b1a:	add    $0x1e,%ecx
 1032b1d:	and    $0xfffffff0,%ecx
 1032b20:	lea    (%rax,%rcx,1),%rbx
 1032b24:	add    $0x10,%rbx
 1032b28:	movzwl %dx,%r13d
 1032b2c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032b3b:	nopl   0x0(%rax,%rax,1)
 1032b40:	tzcnt  %r13d,%eax
 1032b45:	add    %r14d,%eax
 1032b48:	and    %r15d,%eax
 1032b4b:	mov    (%rbx,%rax,4),%r12d
 1032b4f:	mov    %r12,%rax
 1032b52:	shl    $0x4,%rax
 1032b56:	mov    (%rsp),%rcx
 1032b5a:	mov    0x20(%rcx,%rax,1),%rdi
 1032b5f:	mov    0x38(%rsp),%rsi
 1032b64:	call   1010cd0 <myl_core_str_eq>
 1032b69:	test   %al,%al
 1032b6b:	jne    103290f <main+0x1cf>
 1032b71:	blsr   %r13d,%r13d
 1032b76:	jne    1032b40 <main+0x400>
 1032b78:	vmovdqa 0x50(%rsp),%xmm0
 1032b7e:	vpcmpeqb -0x2f366(%rip),%xmm0,%xmm0        # 1003820 <core_io_raw_layout+0x2a0>
 1032b86:	vpmovmskb %xmm0,%eax
 1032b8a:	test   %eax,%eax
 1032b8c:	je     10328fb <main+0x1bb>
 1032b92:	tzcnt  %eax,%r12d
 1032b97:	add    %r14d,%r12d
 1032b9a:	and    %r15d,%r12d
 1032b9d:	not    %r12
 1032ba0:	jmp    103290f <main+0x1cf>
 1032ba5:	mov    0x20(%rcx),%rbx
 1032ba9:	mov    $0xffffffffffffffff,%r12
 1032bb0:	test   %rbx,%rbx
 1032bb3:	je     103290f <main+0x1cf>
 1032bb9:	mov    0x10(%rcx),%r14
 1032bbd:	mov    (%rsp),%rax
 1032bc1:	lea    0x20(%rax),%r15
 1032bc5:	xor    %r13d,%r13d
 1032bc8:	jmp    1032c10 <main+0x4d0>
 1032bca:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032bd9:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032be8:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032bf7:	nopw   0x0(%rax,%rax,1)
 1032c00:	inc    %r13
 1032c03:	add    $0x10,%r15
 1032c07:	cmp    %r13,%rbx
 1032c0a:	je     103290f <main+0x1cf>
 1032c10:	cmp    %rbp,(%r14,%r13,8)
 1032c14:	jne    1032c00 <main+0x4c0>
 1032c16:	mov    (%r15),%rdi
 1032c19:	mov    0x38(%rsp),%rsi
 1032c1e:	call   1010cd0 <myl_core_str_eq>
 1032c23:	test   %al,%al
 1032c25:	je     1032c00 <main+0x4c0>
 1032c27:	mov    %r13,%r12
 1032c2a:	jmp    103290f <main+0x1cf>
 1032c2f:	nop
 1032c30:	mov    0x8(%r14),%rax
 1032c34:	mov    %rax,0x18(%rsp)
 1032c39:	test   %rax,%rax
 1032c3c:	je     10330c0 <main+0x980>
 1032c42:	lea    0x20(%r14),%rax
 1032c46:	mov    %rax,0x50(%rsp)
 1032c4b:	xor    %eax,%eax
 1032c4d:	xor    %esi,%esi
 1032c4f:	mov    %r14,(%rsp)
 1032c53:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032c60:	mov    %rax,0x28(%rsp)
 1032c65:	mov    %r14,%rdi
 1032c68:	mov    %rsi,0x20(%rsp)
 1032c6d:	call   10102b0 <myl_core_dict_ordinal>
 1032c72:	shl    $0x4,%rax
 1032c76:	mov    0x20(%r14,%rax,1),%rdi
 1032c7b:	mov    0x8(%rdi),%rax
 1032c7f:	mov    %rax,%rcx
 1032c82:	sar    $0x3f,%rcx
 1032c86:	andn   %rax,%rcx,%rcx
 1032c8b:	mov    %rax,%r13
 1032c8e:	movabs $0x7fffffffffffffe0,%rdx
 1032c98:	and    %rdx,%rcx
 1032c9b:	movabs $0x10000000000,%r9
 1032ca5:	vpxor  %xmm2,%xmm2,%xmm2
 1032ca9:	je     1032d38 <main+0x5f8>
 1032caf:	xor    %edx,%edx
 1032cb1:	mov    %rax,%r13
 1032cb4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cc0:	mov    %rdx,%r8
 1032cc3:	lea    (%rdx,%r9,1),%rsi
 1032cc7:	cmp    %rcx,%rsi
 1032cca:	mov    %rcx,%rdx
 1032ccd:	cmovb  %rsi,%rdx
 1032cd1:	vpxor  %xmm0,%xmm0,%xmm0
 1032cd5:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032ce4:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032cf3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032d00:	vpsadbw 0x20(%rdi,%r8,1),%ymm2,%ymm1
 1032d07:	vpaddq %ymm0,%ymm1,%ymm0
 1032d0b:	add    $0x20,%r8
 1032d0f:	cmp    %rdx,%r8
 1032d12:	jb     1032d00 <main+0x5c0>
 1032d14:	vextracti128 $0x1,%ymm0,%xmm1
 1032d1a:	vpaddq %xmm1,%xmm0,%xmm0
 1032d1e:	vpshufd $0xee,%xmm0,%xmm1
 1032d23:	vpaddq %xmm1,%xmm0,%xmm0
 1032d27:	vmovq  %xmm0,%r8
 1032d2c:	add    %r8,%r13
 1032d2f:	cmp    %rcx,%rsi
 1032d32:	jb     1032cc0 <main+0x580>
 1032d38:	mov    %rax,%rdx
 1032d3b:	sub    %rcx,%rdx
 1032d3e:	jbe    1032ed0 <main+0x790>
 1032d44:	cmp    $0x4,%rdx
 1032d48:	jae    1032d60 <main+0x620>
 1032d4a:	mov    %rcx,%rdx
 1032d4d:	jmp    1032ec0 <main+0x780>
 1032d52:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032d60:	cmp    $0x10,%rdx
 1032d64:	jae    1032d6d <main+0x62d>
 1032d66:	xor    %esi,%esi
 1032d68:	jmp    1032e2c <main+0x6ec>
 1032d6d:	mov    %eax,%r8d
 1032d70:	and    $0xf,%r8d
 1032d74:	mov    %rdx,%rsi
 1032d77:	sub    %r8,%rsi
 1032d7a:	vmovq  %r13,%xmm0
 1032d7f:	mov    %rax,%r9
 1032d82:	and    $0xfffffffffffffff0,%r9
 1032d86:	vpxor  %xmm1,%xmm1,%xmm1
 1032d8a:	mov    %rcx,%r10
 1032d8d:	vpxor  %xmm2,%xmm2,%xmm2
 1032d91:	vpxor  %xmm3,%xmm3,%xmm3
 1032d95:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032da4:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032db3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032dc0:	vpmovzxbq 0x20(%rdi,%r10,1),%ymm4
 1032dc7:	vpaddq %ymm4,%ymm0,%ymm0
 1032dcb:	vpmovzxbq 0x24(%rdi,%r10,1),%ymm4
 1032dd2:	vpaddq %ymm4,%ymm1,%ymm1
 1032dd6:	vpmovzxbq 0x28(%rdi,%r10,1),%ymm4
 1032ddd:	vpaddq %ymm4,%ymm2,%ymm2
 1032de1:	vpmovzxbq 0x2c(%rdi,%r10,1),%ymm4
 1032de8:	vpaddq %ymm4,%ymm3,%ymm3
 1032dec:	add    $0x10,%r10
 1032df0:	cmp    %r10,%r9
 1032df3:	jne    1032dc0 <main+0x680>
 1032df5:	vpaddq %ymm0,%ymm1,%ymm0
 1032df9:	vpaddq %ymm0,%ymm2,%ymm0
 1032dfd:	vpaddq %ymm0,%ymm3,%ymm0
 1032e01:	vextracti128 $0x1,%ymm0,%xmm1
 1032e07:	vpaddq %xmm1,%xmm0,%xmm0
 1032e0b:	vpshufd $0xee,%xmm0,%xmm1
 1032e10:	vpaddq %xmm1,%xmm0,%xmm0
 1032e14:	vmovq  %xmm0,%r13
 1032e19:	test   %r8,%r8
 1032e1c:	je     1032ed0 <main+0x790>
 1032e22:	cmp    $0x4,%r8d
 1032e26:	jb     10330af <main+0x96f>
 1032e2c:	mov    %eax,%r8d
 1032e2f:	and    $0x3,%r8d
 1032e33:	sub    %r8,%rdx
 1032e36:	add    %rcx,%rdx
 1032e39:	vmovq  %r13,%xmm0
 1032e3e:	add    %rcx,%rsi
 1032e41:	mov    %rax,%rcx
 1032e44:	and    $0xfffffffffffffffc,%rcx
 1032e48:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032e57:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032e66:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032e75:	data16 cs nopw 0x0(%rax,%rax,1)
 1032e80:	vpmovzxbq 0x20(%rdi,%rsi,1),%ymm1
 1032e87:	vpaddq %ymm1,%ymm0,%ymm0
 1032e8b:	add    $0x4,%rsi
 1032e8f:	cmp    %rsi,%rcx
 1032e92:	jne    1032e80 <main+0x740>
 1032e94:	vextracti128 $0x1,%ymm0,%xmm1
 1032e9a:	vpaddq %xmm1,%xmm0,%xmm0
 1032e9e:	vpshufd $0xee,%xmm0,%xmm1
 1032ea3:	vpaddq %xmm1,%xmm0,%xmm0
 1032ea7:	vmovq  %xmm0,%r13
 1032eac:	test   %r8,%r8
 1032eaf:	je     1032ed0 <main+0x790>
 1032eb1:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032ec0:	movzbl 0x20(%rdi,%rdx,1),%ecx
 1032ec5:	add    %rcx,%r13
 1032ec8:	inc    %rdx
 1032ecb:	cmp    %rax,%rdx
 1032ece:	jb     1032ec0 <main+0x780>
 1032ed0:	mov    %rdi,0x30(%rsp)
 1032ed5:	testb  $0x2,0x5(%rdi)
 1032ed9:	jne    1032ef0 <main+0x7b0>
 1032edb:	vzeroupper
 1032ede:	call   1010b70 <myl_core_str_hash>
 1032ee3:	jmp    1032ef3 <main+0x7b3>
 1032ee5:	data16 cs nopw 0x0(%rax,%rax,1)
 1032ef0:	mov    0x18(%rdi),%eax
 1032ef3:	mov    %eax,%eax
 1032ef5:	movabs $0x9e3779b97f4a7c15,%rcx
 1032eff:	imul   %rcx,%rax
 1032f03:	mov    %rax,%rbp
 1032f06:	shr    $0x20,%rbp
 1032f0a:	xor    %rax,%rbp
 1032f0d:	mov    0x18(%r14),%rcx
 1032f11:	mov    0x8(%rcx),%rax
 1032f15:	test   %rax,%rax
 1032f18:	je     1032fd0 <main+0x890>
 1032f1e:	mov    (%rax),%ecx
 1032f20:	tzcnt  %ecx,%edx
 1032f24:	neg    %dl
 1032f26:	shrx   %rdx,%rbp,%rdx
 1032f2b:	mov    %rdx,0x10(%rsp)
 1032f30:	vmovdqu 0x10(%rax,%rdx,1),%xmm1
 1032f36:	mov    %ebp,%edx
 1032f38:	and    $0x7f,%dl
 1032f3b:	vmovd  %edx,%xmm0
 1032f3f:	vpbroadcastb %xmm0,%xmm0
 1032f44:	vmovdqa %xmm1,0x60(%rsp)
 1032f4a:	vpcmpeqb %xmm0,%xmm1,%xmm0
 1032f4e:	vpmovmskb %xmm0,%edx
 1032f52:	test   %edx,%edx
 1032f54:	je     1032fb5 <main+0x875>
 1032f56:	lea    -0x1(%rcx),%r15d
 1032f5a:	add    $0x1e,%ecx
 1032f5d:	and    $0xfffffff0,%ecx
 1032f60:	lea    (%rax,%rcx,1),%rbx
 1032f64:	add    $0x10,%rbx
 1032f68:	movzwl %dx,%r14d
 1032f6c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1032f7b:	nopl   0x0(%rax,%rax,1)
 1032f80:	tzcnt  %r14d,%eax
 1032f85:	add    0x10(%rsp),%eax
 1032f89:	and    %r15d,%eax
 1032f8c:	mov    (%rbx,%rax,4),%r12d
 1032f90:	shl    $0x4,%r12
 1032f94:	mov    (%rsp),%rax
 1032f98:	mov    0x20(%rax,%r12,1),%rdi
 1032f9d:	mov    0x30(%rsp),%rsi
 1032fa2:	vzeroupper
 1032fa5:	call   1010cd0 <myl_core_str_eq>
 1032faa:	test   %al,%al
 1032fac:	jne    1032ffb <main+0x8bb>
 1032fae:	blsr   %r14d,%r14d
 1032fb3:	jne    1032f80 <main+0x840>
 1032fb5:	vmovdqa 0x60(%rsp),%xmm0
 1032fbb:	vpcmpeqb -0x2f7a3(%rip),%xmm0,%xmm0        # 1003820 <core_io_raw_layout+0x2a0>
 1032fc3:	vpmovmskb %xmm0,%eax
 1032fc7:	test   %eax,%eax
 1032fc9:	je     1032fd7 <main+0x897>
 1032fcb:	jmp    1033331 <main+0xbf1>
 1032fd0:	cmpq   $0x0,0x18(%rcx)
 1032fd5:	je     103304a <main+0x90a>
 1032fd7:	mov    (%rsp),%rdi
 1032fdb:	lea    0x30(%rsp),%rsi
 1032fe0:	mov    %rbp,%rdx
 1032fe3:	vzeroupper
 1032fe6:	call   100f400 <myl_core_dict_find>
 1032feb:	mov    %rax,%r12
 1032fee:	test   %r12,%r12
 1032ff1:	js     1033331 <main+0xbf1>
 1032ff7:	shl    $0x4,%r12
 1032ffb:	mov    (%rsp),%r14
 1032fff:	mov    0x28(%r14,%r12,1),%rdx
 1033004:	mov    %r13,%rsi
 1033007:	imul   %rdx,%rsi
 103300b:	jo     1033359 <main+0xc19>
 1033011:	mov    %rsi,%rax
 1033014:	imul   %rdx,%rax
 1033018:	jo     103334f <main+0xc0f>
 103301e:	mov    0x28(%rsp),%rsi
 1033023:	mov    %rsi,%r12
 1033026:	add    %rax,%r12
 1033029:	jo     1033342 <main+0xc02>
 103302f:	mov    0x20(%rsp),%rsi
 1033034:	inc    %rsi
 1033037:	mov    %r12,%rax
 103303a:	cmp    0x18(%rsp),%rsi
 103303f:	jne    1032c60 <main+0x520>
 1033045:	jmp    10330c3 <main+0x983>
 103304a:	mov    0x20(%rcx),%rbx
 103304e:	test   %rbx,%rbx
 1033051:	je     1033331 <main+0xbf1>
 1033057:	mov    0x10(%rcx),%r14
 103305b:	mov    0x50(%rsp),%r15
 1033060:	xor    %r12d,%r12d
 1033063:	jmp    1033090 <main+0x950>
 1033065:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033074:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033080:	inc    %r12
 1033083:	add    $0x10,%r15
 1033087:	cmp    %r12,%rbx
 103308a:	je     1033331 <main+0xbf1>
 1033090:	cmp    %rbp,(%r14,%r12,8)
 1033094:	jne    1033080 <main+0x940>
 1033096:	mov    (%r15),%rdi
 1033099:	mov    0x30(%rsp),%rsi
 103309e:	vzeroupper
 10330a1:	call   1010cd0 <myl_core_str_eq>
 10330a6:	test   %al,%al
 10330a8:	je     1033080 <main+0x940>
 10330aa:	jmp    1032fee <main+0x8ae>
 10330af:	add    %rsi,%rcx
 10330b2:	jmp    1032d4a <main+0x60a>
 10330b7:	nopw   0x0(%rax,%rax,1)
 10330c0:	xor    %r12d,%r12d
 10330c3:	mov    (%r14),%eax
 10330c6:	cmp    $0xffffffff,%eax
 10330c9:	je     103310b <main+0x9cb>
 10330cb:	dec    %eax
 10330cd:	je     10330e0 <main+0x9a0>
 10330cf:	mov    %eax,(%r14)
 10330d2:	jmp    103310b <main+0x9cb>
 10330d4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10330e0:	movzbl 0x7(%r14),%eax
 10330e5:	test   %rax,%rax
 10330e8:	je     103317e <main+0xa3e>
 10330ee:	cmpq   $0x0,0x18(%r14)
 10330f3:	jne    103317e <main+0xa3e>
 10330f9:	lea    0x26550(%rip),%rdx        # 1059650 <myl_core_free_lists>
 1033100:	mov    (%rdx,%rax,8),%rcx
 1033104:	mov    %rcx,(%r14)
 1033107:	mov    %r14,(%rdx,%rax,8)
 103310b:	mov    0x98(%rsp),%rsi
 1033113:	mov    %rsi,%rcx
 1033116:	add    %r12,%rcx
 1033119:	jo     10333ee <main+0xcae>
 103311f:	mov    %rcx,%rax
 1033122:	movabs $0x89705f3112a28fe5,%rdx
 103312c:	imul   %rdx
 103312f:	add    %rcx,%rdx
 1033132:	mov    %rdx,%rax
 1033135:	shr    $0x3f,%rax
 1033139:	sar    $0x1d,%rdx
 103313d:	add    %rax,%rdx
 1033140:	imul   $0x3b9aca07,%rdx,%rax
 1033147:	sub    %rax,%rcx
 103314a:	mov    %rcx,%r14
 103314d:	sar    $0x3f,%r14
 1033151:	and    $0x3b9aca07,%r14d
 1033158:	add    %rcx,%r14
 103315b:	mov    0x90(%rsp),%rdx
 1033163:	inc    %rdx
 1033166:	cmp    0x88(%rsp),%rdx
 103316e:	mov    0x80(%rsp),%rax
 1033176:	jne    1032870 <main+0x130>
 103317c:	jmp    1033188 <main+0xa48>
 103317e:	mov    %r14,%rdi
 1033181:	call   1031f50 <myl_core_free_block>
 1033186:	jmp    103310b <main+0x9cb>
 1033188:	mov    0xb0(%rsp),%rdi
 1033190:	mov    (%rdi),%eax
 1033192:	cmp    $0xffffffff,%eax
 1033195:	je     10331c9 <main+0xa89>
 1033197:	dec    %eax
 1033199:	je     103319f <main+0xa5f>
 103319b:	mov    %eax,(%rdi)
 103319d:	jmp    10331c9 <main+0xa89>
 103319f:	movzbl 0x7(%rdi),%eax
 10331a3:	test   %rax,%rax
 10331a6:	je     10333a3 <main+0xc63>
 10331ac:	cmpq   $0x0,0x18(%rdi)
 10331b1:	jne    10333a3 <main+0xc63>
 10331b7:	lea    0x26492(%rip),%rdx        # 1059650 <myl_core_free_lists>
 10331be:	mov    (%rdx,%rax,8),%rcx
 10331c2:	mov    %rcx,(%rdi)
 10331c5:	mov    %rdi,(%rdx,%rax,8)
 10331c9:	mov    0xb8(%rsp),%rdi
 10331d1:	mov    (%rdi),%eax
 10331d3:	cmp    $0xffffffff,%eax
 10331d6:	je     103320a <main+0xaca>
 10331d8:	dec    %eax
 10331da:	je     10331e0 <main+0xaa0>
 10331dc:	mov    %eax,(%rdi)
 10331de:	jmp    103320a <main+0xaca>
 10331e0:	movzbl 0x7(%rdi),%eax
 10331e4:	test   %rax,%rax
 10331e7:	je     10333ad <main+0xc6d>
 10331ed:	cmpq   $0x0,0x18(%rdi)
 10331f2:	jne    10333ad <main+0xc6d>
 10331f8:	lea    0x26451(%rip),%rdx        # 1059650 <myl_core_free_lists>
 10331ff:	mov    (%rdx,%rax,8),%rcx
 1033203:	mov    %rcx,(%rdi)
 1033206:	mov    %rdi,(%rdx,%rax,8)
 103320a:	mov    0xc0(%rsp),%rdi
 1033212:	mov    (%rdi),%eax
 1033214:	cmp    $0xffffffff,%eax
 1033217:	je     103324b <main+0xb0b>
 1033219:	dec    %eax
 103321b:	je     1033221 <main+0xae1>
 103321d:	mov    %eax,(%rdi)
 103321f:	jmp    103324b <main+0xb0b>
 1033221:	movzbl 0x7(%rdi),%eax
 1033225:	test   %rax,%rax
 1033228:	je     10333b7 <main+0xc77>
 103322e:	cmpq   $0x0,0x18(%rdi)
 1033233:	jne    10333b7 <main+0xc77>
 1033239:	lea    0x26410(%rip),%rdx        # 1059650 <myl_core_free_lists>
 1033240:	mov    (%rdx,%rax,8),%rcx
 1033244:	mov    %rcx,(%rdi)
 1033247:	mov    %rdi,(%rdx,%rax,8)
 103324b:	mov    0xc8(%rsp),%rdi
 1033253:	mov    (%rdi),%eax
 1033255:	cmp    $0xffffffff,%eax
 1033258:	je     103328c <main+0xb4c>
 103325a:	dec    %eax
 103325c:	je     1033262 <main+0xb22>
 103325e:	mov    %eax,(%rdi)
 1033260:	jmp    103328c <main+0xb4c>
 1033262:	movzbl 0x7(%rdi),%eax
 1033266:	test   %rax,%rax
 1033269:	je     10333c1 <main+0xc81>
 103326f:	cmpq   $0x0,0x18(%rdi)
 1033274:	jne    10333c1 <main+0xc81>
 103327a:	lea    0x263cf(%rip),%rdx        # 1059650 <myl_core_free_lists>
 1033281:	mov    (%rdx,%rax,8),%rcx
 1033285:	mov    %rcx,(%rdi)
 1033288:	mov    %rdi,(%rdx,%rax,8)
 103328c:	mov    0xd0(%rsp),%rdi
 1033294:	mov    (%rdi),%eax
 1033296:	cmp    $0xffffffff,%eax
 1033299:	je     10332cd <main+0xb8d>
 103329b:	dec    %eax
 103329d:	je     10332a3 <main+0xb63>
 103329f:	mov    %eax,(%rdi)
 10332a1:	jmp    10332cd <main+0xb8d>
 10332a3:	movzbl 0x7(%rdi),%eax
 10332a7:	test   %rax,%rax
 10332aa:	je     10333cb <main+0xc8b>
 10332b0:	cmpq   $0x0,0x18(%rdi)
 10332b5:	jne    10333cb <main+0xc8b>
 10332bb:	lea    0x2638e(%rip),%rdx        # 1059650 <myl_core_free_lists>
 10332c2:	mov    (%rdx,%rax,8),%rcx
 10332c6:	mov    %rcx,(%rdi)
 10332c9:	mov    %rdi,(%rdx,%rax,8)
 10332cd:	mov    $0xa,%edi
 10332d2:	call   100a2c0 <myl_core_io_at>
 10332d7:	mov    0x40(%rsp),%rdi
 10332dc:	call   10223b0 <myl_core_host_check>
 10332e1:	call   1033cd0 <runtime_bench_now>
 10332e6:	mov    %rax,%rbx
 10332e9:	mov    0x78(%rsp),%rdx
 10332ee:	sub    %rdx,%rbx
 10332f1:	jo     1033419 <main+0xcd9>
 10332f7:	mov    $0x1,%edi
 10332fc:	mov    %r14,%rsi
 10332ff:	call   100a9c0 <myl_core_print_i64>
 1033304:	mov    $0x1,%edi
 1033309:	call   10091c0 <myl_core_print_sep>
 103330e:	mov    $0x1,%edi
 1033313:	mov    %rbx,%rsi
 1033316:	call   100a9c0 <myl_core_print_i64>
 103331b:	mov    $0x1,%edi
 1033320:	call   1009280 <myl_core_print_end>
 1033325:	xor    %ebx,%ebx
 1033327:	mov    0x8(%rsp),%rdi
 103332c:	jmp    10327fa <main+0xba>
 1033331:	mov    $0x24,%edi
 1033336:	xor    %esi,%esi
 1033338:	xor    %edx,%edx
 103333a:	vzeroupper
 103333d:	call   1009b40 <myl_core_trap>
 1033342:	mov    $0x26,%edi
 1033347:	mov    %rax,%rdx
 103334a:	call   1009b40 <myl_core_trap>
 103334f:	mov    $0x25,%edi
 1033354:	call   1009b40 <myl_core_trap>
 1033359:	mov    $0x23,%edi
 103335e:	mov    %r13,%rsi
 1033361:	call   1009b40 <myl_core_trap>
 1033366:	mov    $0x1e,%edi
 103336b:	mov    %r15,%rsi
 103336e:	xor    %edx,%edx
 1033370:	call   1009b40 <myl_core_trap>
 1033375:	mov    $0x1f,%edi
 103337a:	mov    %rax,%rsi
 103337d:	mov    %r15,%rdx
 1033380:	call   1009b40 <myl_core_trap>
 1033385:	mov    $0x20,%edi
 103338a:	mov    %rbp,%rsi
 103338d:	xor    %edx,%edx
 103338f:	call   1009b40 <myl_core_trap>
 1033394:	mov    $0x1,%edx
 1033399:	mov    $0x21,%edi
 103339e:	call   1009b40 <myl_core_trap>
 10333a3:	call   1031f50 <myl_core_free_block>
 10333a8:	jmp    10331c9 <main+0xa89>
 10333ad:	call   1031f50 <myl_core_free_block>
 10333b2:	jmp    103320a <main+0xaca>
 10333b7:	call   1031f50 <myl_core_free_block>
 10333bc:	jmp    103324b <main+0xb0b>
 10333c1:	call   1031f50 <myl_core_free_block>
 10333c6:	jmp    103328c <main+0xb4c>
 10333cb:	call   1031f50 <myl_core_free_block>
 10333d0:	jmp    10332cd <main+0xb8d>
 10333d5:	mov    $0x1c,%edi
 10333da:	call   1009b40 <myl_core_trap>
 10333df:	mov    $0x19,%edi
 10333e4:	mov    0x48(%rsp),%rsi
 10333e9:	call   1009b40 <myl_core_trap>
 10333ee:	mov    $0x1d,%edi
 10333f3:	mov    %r12,%rdx
 10333f6:	call   1009b40 <myl_core_trap>
 10333fb:	mov    $0x1,%esi
 1033400:	mov    $0x5,%edi
 1033405:	call   1009b40 <myl_core_trap>
 103340a:	mov    $0x2,%esi
 103340f:	mov    $0x8,%edi
 1033414:	call   1009b40 <myl_core_trap>
 1033419:	mov    $0xb,%edi
 103341e:	mov    %rax,%rsi
 1033421:	call   1009b40 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
