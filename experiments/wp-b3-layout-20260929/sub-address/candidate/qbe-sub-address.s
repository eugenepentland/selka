.text
.balign 16
.globl addr_load
addr_load:
	endbr64
	movq -32(%rdi), %rax
	ret
.type addr_load, @function
.size addr_load, .-addr_load
/* end function addr_load */

.text
.balign 16
.globl addr_store
addr_store:
	endbr64
	movq %rsi, -32(%rdi)
	movl $0, %eax
	ret
.type addr_store, @function
.size addr_store, .-addr_store
/* end function addr_store */

.text
.balign 16
.globl addr_hold
addr_hold:
	endbr64
	movq -24(%rdi), %rax
	ret
.type addr_hold, @function
.size addr_hold, .-addr_hold
/* end function addr_hold */

.text
.balign 16
.globl addr_mark
addr_mark:
	endbr64
	movq -16(%rdi), %rax
	ret
.type addr_mark, @function
.size addr_mark, .-addr_mark
/* end function addr_mark */

.text
.balign 16
.globl addr_scaled
addr_scaled:
	endbr64
	movq -32(%rdi, %rsi, 8), %rax
	ret
.type addr_scaled, @function
.size addr_scaled, .-addr_scaled
/* end function addr_scaled */

.text
.balign 16
.globl addr_scaled_sub
addr_scaled_sub:
	endbr64
	movq -8(%rdi, %rsi, 8), %rax
	ret
.type addr_scaled_sub, @function
.size addr_scaled_sub, .-addr_scaled_sub
/* end function addr_scaled_sub */

.text
.balign 16
.globl addr_min
addr_min:
	endbr64
	movq -2147483648(%rdi), %rax
	ret
.type addr_min, @function
.size addr_min, .-addr_min
/* end function addr_min */

.text
.balign 16
.globl addr_max
addr_max:
	endbr64
	movq 2147483647(%rdi), %rax
	ret
.type addr_max, @function
.size addr_max, .-addr_max
/* end function addr_max */

.text
.balign 16
.globl addr_outside
addr_outside:
	endbr64
	movl $2147483649, %eax
	negq %rax
	addq %rdi, %rax
	movq (%rax), %rax
	ret
.type addr_outside, @function
.size addr_outside, .-addr_outside
/* end function addr_outside */

.text
.balign 16
.globl addr_composed_outside
addr_composed_outside:
	endbr64
	movl $2147483649, %eax
	negq %rax
	addq %rdi, %rax
	movq (%rax), %rax
	ret
.type addr_composed_outside, @function
.size addr_composed_outside, .-addr_composed_outside
/* end function addr_composed_outside */

.text
.balign 16
.globl addr_composed_cancel
addr_composed_cancel:
	endbr64
	movq -2147483647(%rdi), %rax
	ret
.type addr_composed_cancel, @function
.size addr_composed_cancel, .-addr_composed_cancel
/* end function addr_composed_cancel */

.text
.balign 16
.globl addr_scaled_outside
addr_scaled_outside:
	endbr64
	movl $2147483648, %eax
	negq %rax
	addq %rsi, %rax
	movq (%rdi, %rax, 8), %rax
	ret
.type addr_scaled_outside, @function
.size addr_scaled_outside, .-addr_scaled_outside
/* end function addr_scaled_outside */

.text
.balign 16
.globl addr_negative
addr_negative:
	endbr64
	movq %rdi, %rax
	subq $-32, %rax
	movq (%rax), %rax
	ret
.type addr_negative, @function
.size addr_negative, .-addr_negative
/* end function addr_negative */

.text
.balign 16
.globl addr_dynamic
addr_dynamic:
	endbr64
	movq %rdi, %rax
	subq %rsi, %rax
	movq (%rax), %rax
	ret
.type addr_dynamic, @function
.size addr_dynamic, .-addr_dynamic
/* end function addr_dynamic */

.text
.balign 16
.globl addr_swapped
addr_swapped:
	endbr64
	movl $32, %eax
	subq %rdi, %rax
	movq (%rax), %rax
	ret
.type addr_swapped, @function
.size addr_swapped, .-addr_swapped
/* end function addr_swapped */

.text
.balign 16
.globl addr_multi
addr_multi:
	endbr64
	movq %rdi, %rax
	subq $32, %rax
	movq %rax, (%rsi)
	movq -32(%rdi), %rax
	ret
.type addr_multi, @function
.size addr_multi, .-addr_multi
/* end function addr_multi */

.text
.balign 16
.globl addr_word
addr_word:
	endbr64
	movl %edi, %eax
	subl $32, %eax
	ret
.type addr_word, @function
.size addr_word, .-addr_word
/* end function addr_word */

.text
.balign 16
.globl addr_float
addr_float:
	endbr64
	subsd ".Lfp0"(%rip), %xmm0
	ret
.type addr_float, @function
.size addr_float, .-addr_float
/* end function addr_float */

.text
.balign 16
.globl addr_large
addr_large:
	endbr64
	movq $9223372036854775807, %rax
	negq %rax
	addq %rdi, %rax
	movq (%rax), %rax
	ret
.type addr_large, @function
.size addr_large, .-addr_large
/* end function addr_large */

.text
.balign 16
.globl addr_negative_min
addr_negative_min:
	endbr64
	movq $-9223372036854775808, %rax
	negq %rax
	addq %rdi, %rax
	movq (%rax), %rax
	ret
.type addr_negative_min, @function
.size addr_negative_min, .-addr_negative_min
/* end function addr_negative_min */

.text
.balign 16
.globl addr_flags
addr_flags:
	endbr64
	movq %rdi, %rax
	subq $32, %rax
	jz .Lbb42
	movq %rax, (%rsi)
	movl $0, %eax
	jmp .Lbb43
.Lbb42:
	movq $0, (%rsi)
	movl $1, %eax
.Lbb43:
	ret
.type addr_flags, @function
.size addr_flags, .-addr_flags
/* end function addr_flags */

.text
.balign 16
.globl addr_loaded_flags
addr_loaded_flags:
	endbr64
	movq %rdi, %rcx
	subq $32, %rcx
	movq -32(%rdi), %rax
	cmpq $0, %rcx
	jnz .Lbb46
	movl $0, %eax
.Lbb46:
	ret
.type addr_loaded_flags, @function
.size addr_loaded_flags, .-addr_loaded_flags
/* end function addr_loaded_flags */

/* floating point constants */
.section .rodata
.p2align 3
.Lfp0:
	.quad 4629700416936869888 /* 32.000000 */

.section .note.GNU-stack,"",@progbits
