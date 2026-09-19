# Hand-written x86-64 scan for the sexpr benchmark, syscall-only (no libc).
#
#   as --defsym VARIANT=N -o scan.o scan.s && ld -s -o scan scan.o
#
#   VARIANT 0  open + read the file, count nothing      ("read floor")
#   VARIANT 1  read + scalar byte loop                  count '('/')'
#   VARIANT 2  read + SSE2 16-byte blocks (unrolled 4x)
#   VARIANT 3  read + AVX2 32-byte blocks (unrolled 2x, needs AVX2)
#
# Prints the same `bytes=<n> delims=<m>` line as `zig-bench --scan`, so its
# stdout digest is directly comparable. Static, no dynamic loader.

	.set BUFSZ,     16777216
	.set SYS_read,  0
	.set SYS_write, 1
	.set SYS_open,  2
	.set SYS_exit,  60

# One 16-byte SSE2 block at offset \off from (%rbx,%rax): compare against the
# '(' and ')' masks, keep 1 per match, and accumulate the byte sums.
.macro SSE_BLOCK off
	movdqu \off(%rbx,%rax), %xmm0
	movdqa %xmm0, %xmm1
	pcmpeqb %xmm6, %xmm0
	pcmpeqb %xmm7, %xmm1
	por %xmm1, %xmm0
	pand %xmm3, %xmm0
	psadbw %xmm2, %xmm0
	paddq %xmm0, %xmm5
.endm

# One 32-byte AVX2 block.
.macro AVX_BLOCK off
	vmovdqu \off(%rbx,%rax), %ymm0
	vpcmpeqb %ymm6, %ymm0, %ymm1
	vpcmpeqb %ymm7, %ymm0, %ymm0
	vpor %ymm1, %ymm0, %ymm0
	vpand %ymm3, %ymm0, %ymm0
	vpsadbw %ymm2, %ymm0, %ymm0
	vpaddq %ymm0, %ymm5, %ymm5
.endm

	.section .rodata
msg_bytes:  .ascii "bytes="
msg_delims: .ascii " delims="
newline:    .byte 10
	.balign 32
ones32:   .fill 32, 1, 1
opens32:  .fill 32, 1, 40
closes32: .fill 32, 1, 41

	.section .bss
	.balign 64
buf:    .zero BUFSZ
outbuf: .zero 64

	.section .text
	.globl _start
_start:
	movq (%rsp), %rax          # argc
	cmpq $2, %rax
	jl .Lusage
	movq 16(%rsp), %rdi        # argv[1]
	movl $SYS_open, %eax
	xorl %esi, %esi            # O_RDONLY
	xorl %edx, %edx
	syscall
	testq %rax, %rax
	js .Lfail
	movq %rax, %r8             # fd
	leaq buf(%rip), %rbx
	xorq %r9, %r9              # bytes read
.Lread:
	xorl %eax, %eax            # SYS_read
	movq %r8, %rdi
	leaq (%rbx,%r9), %rsi
	movq $BUFSZ, %rdx
	subq %r9, %rdx
	syscall
	testq %rax, %rax
	jle .Lread_done
	addq %rax, %r9
	cmpq $BUFSZ, %r9
	jb .Lread
.Lread_done:
	xorq %rcx, %rcx            # delimiters

.if VARIANT == 1
	xorq %rax, %rax
.Ls_loop:
	cmpq %r9, %rax
	jge .Lprint
	movzbl (%rbx,%rax), %edx
	cmpb $40, %dl
	je .Ls_inc
	cmpb $41, %dl
	jne .Ls_next
.Ls_inc:
	incq %rcx
.Ls_next:
	incq %rax
	jmp .Ls_loop
.endif

.if VARIANT == 2
	movdqa ones32(%rip), %xmm3
	movdqa opens32(%rip), %xmm6
	movdqa closes32(%rip), %xmm7
	pxor %xmm2, %xmm2
	pxor %xmm5, %xmm5
	xorq %rax, %rax
.Lv64:
	leaq 64(%rax), %rdx
	cmpq %r9, %rdx
	jg .Lv16
	SSE_BLOCK 0
	SSE_BLOCK 16
	SSE_BLOCK 32
	SSE_BLOCK 48
	addq $64, %rax
	jmp .Lv64
.Lv16:
	leaq 16(%rax), %rdx
	cmpq %r9, %rdx
	jg .Lvtail
	SSE_BLOCK 0
	addq $16, %rax
	jmp .Lv16
.Lvtail:
	cmpq %r9, %rax
	jge .Lvsum
	movzbl (%rbx,%rax), %edx
	cmpb $40, %dl
	je .Lvt_inc
	cmpb $41, %dl
	jne .Lvt_next
.Lvt_inc:
	incq %rcx
.Lvt_next:
	incq %rax
	jmp .Lvtail
.Lvsum:
	movdqa %xmm5, %xmm0
	psrldq $8, %xmm0
	paddq %xmm0, %xmm5
	movq %xmm5, %rdx
	addq %rdx, %rcx
.endif

.if VARIANT == 3
	vmovdqa ones32(%rip), %ymm3
	vmovdqa opens32(%rip), %ymm6
	vmovdqa closes32(%rip), %ymm7
	vpxor %ymm2, %ymm2, %ymm2
	vpxor %ymm5, %ymm5, %ymm5
	xorq %rax, %rax
.La64:
	leaq 64(%rax), %rdx
	cmpq %r9, %rdx
	jg .La32
	AVX_BLOCK 0
	AVX_BLOCK 32
	addq $64, %rax
	jmp .La64
.La32:
	leaq 32(%rax), %rdx
	cmpq %r9, %rdx
	jg .Latail
	AVX_BLOCK 0
	addq $32, %rax
	jmp .La32
.Latail:
	cmpq %r9, %rax
	jge .Lasum
	movzbl (%rbx,%rax), %edx
	cmpb $40, %dl
	je .Lat_inc
	cmpb $41, %dl
	jne .Lat_next
.Lat_inc:
	incq %rcx
.Lat_next:
	incq %rax
	jmp .Latail
.Lasum:
	vextracti128 $1, %ymm5, %xmm0
	paddq %xmm0, %xmm5
	movdqa %xmm5, %xmm0
	psrldq $8, %xmm0
	paddq %xmm0, %xmm5
	movq %xmm5, %rdx
	addq %rdx, %rcx
	vzeroupper
.endif

.Lprint:
	movq %rcx, %r12
	leaq outbuf(%rip), %rdi
	leaq msg_bytes(%rip), %rsi
	movl $6, %ecx
	rep movsb
	movq %r9, %rax
	call .Lappend_u64
	leaq msg_delims(%rip), %rsi
	movl $8, %ecx
	rep movsb
	movq %r12, %rax
	call .Lappend_u64
	movb $10, (%rdi)
	incq %rdi
	leaq outbuf(%rip), %rsi
	movq %rdi, %rdx
	subq %rsi, %rdx
	movl $SYS_write, %eax
	movl $1, %edi
	syscall
	xorl %edi, %edi
	movl $SYS_exit, %eax
	syscall

# append the decimal spelling of %rax at %rdi; clobbers rax, rdx, rsi, r10, r11
.Lappend_u64:
	leaq -32(%rsp), %rsi
	movq %rsi, %r10
	movl $10, %r11d
.Lau_digits:
	xorl %edx, %edx
	divq %r11
	addb $48, %dl
	movb %dl, (%rsi)
	incq %rsi
	testq %rax, %rax
	jne .Lau_digits
.Lau_copy:
	decq %rsi
	movb (%rsi), %dl
	movb %dl, (%rdi)
	incq %rdi
	cmpq %r10, %rsi
	jne .Lau_copy
	ret

.Lusage:
	movl $2, %edi
	jmp .Lexit
.Lfail:
	movl $1, %edi
.Lexit:
	movl $SYS_exit, %eax
	syscall
