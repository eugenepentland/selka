.text
.balign 16
.globl review_pin_entry_truth
review_pin_entry_truth:
	endbr64
	cmpl $0, %edi
	jnz .Lbb2
	movl $0, %eax
	jmp .Lbb3
.Lbb2:
	movl $1, %eax
.Lbb3:
	ret
.type review_pin_entry_truth, @function
.size review_pin_entry_truth, .-review_pin_entry_truth
/* end function review_pin_entry_truth */

.section .note.GNU-stack,"",@progbits
