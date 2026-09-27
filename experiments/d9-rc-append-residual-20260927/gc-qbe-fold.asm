 1005260:	mov    %rax,-0x38(%rbp)
 1005264:	cmp    %rax,%rcx
 1005267:	jge    10052b2 <calloc@plt-0xa61e>
 1005269:	mov    (%r8,%rcx,8),%r10
 100526d:	mov    %r10,-0x38(%rbp)
 1005271:	mov    %rdx,%r9
 1005274:	add    %r10,%rdx
 1005277:	mov    %r9,%r11
 100527a:	xor    %rdx,%r11
 100527d:	mov    %r10,%rbx
 1005280:	xor    %rdx,%rbx
 1005283:	and    %rbx,%r11
 1005286:	cmp    $0x0,%r11
 100528a:	jl     100529a <calloc@plt-0xa636>
 100528c:	movq   $0x1,-0x38(%rbp)
 1005294:	add    $0x1,%rcx
 1005298:	jmp    1005260 <calloc@plt-0xa670>
