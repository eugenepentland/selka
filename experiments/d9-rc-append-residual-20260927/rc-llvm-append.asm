 100ab58:	xor    %eax,%eax
 100ab5a:	cmp    $0xf423ff,%r14
 100ab61:	lea    0x1(%r14),%r14
 100ab65:	setb   %al
 100ab68:	mov    %rax,-0x30(%rbp)
 100ab6c:	cmp    $0xf42400,%r14
 100ab73:	je     100acfb <entry_run+0xcab>
 100ab79:	mov    %r14,-0x30(%rbp)
 100ab7d:	mov    -0x40(%rbp),%rsi
 100ab81:	mov    (%rsi),%rcx
 100ab84:	mov    0x10(%rsi),%rax
 100ab88:	cmp    0x8(%rsi),%rcx
 100ab8c:	setae  %dil
 100ab90:	cmp    $0xffffffffffffffff,%rax
 100ab94:	sete   %r8b
 100ab98:	or     %dil,%r8b
 100ab9b:	jne    100ab40 <entry_run+0xaf0>
 100ab9d:	mov    $0x1,%edi
 100aba2:	test   %edx,%edx
 100aba4:	je     100abbf <entry_run+0xb6f>
 100aba6:	mov    0x20(%rsi),%rdx
 100abaa:	mov    %r14,(%rdx,%rcx,8)
 100abae:	inc    %rcx
 100abb1:	mov    %rcx,(%rsi)
 100abb4:	inc    %rax
 100abb7:	mov    %rax,0x10(%rsi)
 100abbb:	mov    %edi,%edx
 100abbd:	jmp    100ab58 <entry_run+0xb08>
