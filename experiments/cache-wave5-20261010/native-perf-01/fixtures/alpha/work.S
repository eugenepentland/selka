.include "step.inc"
.global _start
.section .text
_start:
    mov $65569, %ecx
    xor %eax, %eax
.Lwork:
    step
    dec %ecx
    jnz .Lwork
    mov %al, result(%rip)
    mov $1, %eax
    mov $1, %edi
    lea result(%rip), %rsi
    mov $2, %edx
    syscall
    mov $60, %eax
    xor %edi, %edi
    syscall
.section .data
result:
    .byte 0, 10
.section .note.GNU-stack,"",@progbits
