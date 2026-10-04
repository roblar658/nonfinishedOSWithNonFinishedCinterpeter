; ==============================================================================
; c_compiler_asm - Pure x86-64 Assembly C Compiler
; utils.asm - String manipulation, formatting, and buffer emitter helpers
; ==============================================================================

section .text

; ------------------------------------------------------------------------------
; str_len: Compute length of null-terminated string
; Input:  RCX = string pointer
; Output: RAX = length (excluding null terminator)
; Clobbers: RDX
; ------------------------------------------------------------------------------
str_len:
    xor eax, eax
.loop:
    cmp byte [rcx + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ------------------------------------------------------------------------------
; str_cmp: Compare two null-terminated strings
; Input:  RCX = str1, RDX = str2
; Output: RAX = 0 if equal, non-zero if different
; Clobbers: R8, R9
; ------------------------------------------------------------------------------
str_cmp:
    xor r8d, r8d
.loop:
    mov al, [rcx + r8]
    mov r10b, [rdx + r8]
    cmp al, r10b
    jne .diff
    test al, al
    jz .equal
    inc r8
    jmp .loop
.diff:
    movzx eax, al
    movzx r10d, r10b
    sub eax, r10d
    ret
.equal:
    xor eax, eax
    ret

; ------------------------------------------------------------------------------
; str_copy: Copy null-terminated string from RDX to RCX
; Input:  RCX = dest, RDX = src
; Output: RAX = dest (RCX)
; Clobbers: R8, R9
; ------------------------------------------------------------------------------
str_copy:
    push rcx
    xor r8d, r8d
.loop:
    mov al, [rdx + r8]
    mov [rcx + r8], al
    test al, al
    jz .done
    inc r8
    jmp .loop
.done:
    pop rax
    ret

; ------------------------------------------------------------------------------
; mem_set: Fill memory with byte value
; Input:  RCX = dest, DL = value, R8 = byte count
; ------------------------------------------------------------------------------
mem_set:
    test r8, r8
    jz .done
    xor rax, rax
.loop:
    mov [rcx + rax], dl
    inc rax
    cmp rax, r8
    jb .loop
.done:
    ret

; ------------------------------------------------------------------------------
; mem_copy: Copy memory
; Input:  RCX = dest, RDX = src, R8 = byte count
; ------------------------------------------------------------------------------
mem_copy:
    test r8, r8
    jz .done
    xor rax, rax
.loop:
    mov r9b, [rdx + rax]
    mov [rcx + rax], r9b
    inc rax
    cmp rax, r8
    jb .loop
.done:
    ret

; ------------------------------------------------------------------------------
; is_space: Check if AL is whitespace (' ', '\t', '\r', '\n')
; Output: RAX = 1 if true, 0 if false
; ------------------------------------------------------------------------------
is_space:
    cmp al, ' '
    je .yes
    cmp al, 9
    je .yes
    cmp al, 10
    je .yes
    cmp al, 13
    je .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; ------------------------------------------------------------------------------
; is_alpha: Check if AL is 'a'..'z' or 'A'..'Z' or '_'
; Output: RAX = 1 if true, 0 if false
; ------------------------------------------------------------------------------
is_alpha:
    cmp al, '_'
    je .yes
    cmp al, 'a'
    jb .check_upper
    cmp al, 'z'
    jbe .yes
.check_upper:
    cmp al, 'A'
    jb .no
    cmp al, 'Z'
    jbe .yes
.no:
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; ------------------------------------------------------------------------------
; is_digit: Check if AL is '0'..'9'
; Output: RAX = 1 if true, 0 if false
; ------------------------------------------------------------------------------
is_digit:
    cmp al, '0'
    jb .no
    cmp al, '9'
    ja .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; ------------------------------------------------------------------------------
; is_alnum: Check if AL is alpha, digit, or '_'
; Output: RAX = 1 if true, 0 if false
; ------------------------------------------------------------------------------
is_alnum:
    cmp al, '_'
    je .yes
    cmp al, '0'
    jb .no
    cmp al, '9'
    jbe .yes
    cmp al, 'A'
    jb .no
    cmp al, 'Z'
    jbe .yes
    cmp al, 'a'
    jb .no
    cmp al, 'z'
    jbe .yes
.no:
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret


; ------------------------------------------------------------------------------
; emit_char: Append single character in AL to out_buf
; ------------------------------------------------------------------------------
emit_char:
    push rbx
    lea rbx, [rel out_buf]
    mov rdx, [rel out_pos]
    cmp rdx, OUT_BUF_SIZE - 4
    jae .overflow
    mov [rbx + rdx], al
    inc qword [rel out_pos]
    pop rbx
    ret
.overflow:
    lea rcx, [rel str_err_out_overflow]
    jmp compile_error

; ------------------------------------------------------------------------------
; emit_str: Append null-terminated string in RCX to out_buf
; ------------------------------------------------------------------------------
emit_str:
    push rbx
    push rsi
    mov rsi, rcx
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    call emit_char
    inc rsi
    jmp .loop
.done:
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; emit_nl: Emit newline (LF: 10)
; ------------------------------------------------------------------------------
emit_nl:
    mov al, 10
    jmp emit_char

; ------------------------------------------------------------------------------
; emit_indent: Emit 4 spaces
; ------------------------------------------------------------------------------
do_emit_indent:
    push rbx
    mov al, ' '
    call emit_char
    mov al, ' '
    call emit_char
    mov al, ' '
    call emit_char
    mov al, ' '
    call emit_char
    pop rbx
    ret

; ------------------------------------------------------------------------------
; emit_u64: Append unsigned 64-bit integer in RCX to out_buf in decimal
; ------------------------------------------------------------------------------
emit_u64:
    push rbx
    push rdi
    sub rsp, 40
    mov rax, rcx
    lea rdi, [rsp + 32]
    mov byte [rdi], 0       ; null terminator
    mov rbx, 10
.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    test rax, rax
    jnz .loop
    mov rcx, rdi
    call emit_str
    add rsp, 40
    pop rdi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; emit_i64: Append signed 64-bit integer in RCX to out_buf in decimal
; ------------------------------------------------------------------------------
emit_i64:
    cmp rcx, 0
    jge emit_u64
    push rcx
    mov al, '-'
    call emit_char
    pop rcx
    neg rcx
    jmp emit_u64

; ------------------------------------------------------------------------------
; compile_error: Report fatal error and exit
; Input: RCX = error message string
; ------------------------------------------------------------------------------
compile_error:
    mov rbx, rcx            ; save error message
    and rsp, -16            ; force 16-byte stack alignment
    sub rsp, 16

    lea rdi, [rel str_err_prefix]
    xor eax, eax
    call printf

    lea rdi, [rel str_err_pos]
    mov rsi, [rel cur_line]
    mov rdx, [rel cur_col]
    xor eax, eax
    call printf

    lea rdi, [rel str_err_msg]
    mov rsi, rbx
    mov rdx, [rel tok_type]
    lea rcx, [rel tok_str]
    xor eax, eax
    call printf

    mov rdi, 1
    call exit

