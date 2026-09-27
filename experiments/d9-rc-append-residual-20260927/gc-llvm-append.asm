 1008660:	mov    0x10(%r14),%rcx
 1008664:	mov    0x20(%r14),%rdx
 1008668:	mov    %r13,(%rdx,%rax,8)
 100866c:	inc    %rax
 100866f:	mov    %rax,(%r14)
 1008672:	inc    %rcx
 1008675:	mov    %rcx,0x10(%r14)
 1008679:	inc    %r13
 100867c:	cmp    $0xf42400,%r13
 1008683:	je     1008df2 <memset@plt-0xa7fe>
 1008689:	mov    (%r14),%rax
 100868c:	cmp    0x8(%r14),%rax
 1008690:	jb     1008660 <memset@plt-0xaf90>
