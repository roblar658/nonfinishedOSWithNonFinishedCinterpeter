; ==============================================================================
; CustomC-OS - Pure x86-64 Assembly C Compiler
; codegen.asm - x86-64 assembly code generation for CustomC-OS (SysV ABI)
; ==============================================================================

section .text

; ------------------------------------------------------------------------------
; gen_new_label: Allocate a new unique label ID
; Output: RAX = label number
; ------------------------------------------------------------------------------
gen_new_label:
    mov rax, [rel label_counter]
    inc qword [rel label_counter]
    ret

; ------------------------------------------------------------------------------
; emit_label: Emit ".L{id}:"
; Input: RCX = label number
; ------------------------------------------------------------------------------
emit_label:
    push rbx
    push rcx
    lea rcx, [rel str_label_prefix]     ; ".L"
    call emit_str
    pop rcx
    call emit_u64
    lea rcx, [rel str_colon_nl]         ; ":\n"
    call emit_str
    pop rbx
    ret

; ------------------------------------------------------------------------------
; emit_named_label: Emit "{name}:\n"
; Input: RCX = label name pointer
; ------------------------------------------------------------------------------
emit_named_label:
    push rcx
    call emit_str
    lea rcx, [rel str_colon_nl]
    call emit_str
    pop rcx
    ret

; ------------------------------------------------------------------------------
; emit_jmp: Emit "    jmp .L{id}\n"
; Input: RCX = label number
; ------------------------------------------------------------------------------
emit_jmp:
    push rcx
    emit_indent
    lea rcx, [rel str_op_jmp]           ; "jmp .L"
    call emit_str
    pop rcx
    call emit_u64
    call emit_nl
    ret

; ------------------------------------------------------------------------------
; emit_jz: Emit "    test rax, rax\n    jz .L{id}\n"
; Input: RCX = label number
; ------------------------------------------------------------------------------
emit_jz:
    push rcx
    emit_indent
    lea rcx, [rel str_op_test_rax]      ; "test rax, rax\n"
    call emit_str
    emit_indent
    lea rcx, [rel str_op_jz]            ; "jz .L"
    call emit_str
    pop rcx
    call emit_u64
    call emit_nl
    ret

; ------------------------------------------------------------------------------
; emit_jnz: Emit "    test rax, rax\n    jnz .L{id}\n"
; Input: RCX = label number
; ------------------------------------------------------------------------------
emit_jnz:
    push rcx
    emit_indent
    lea rcx, [rel str_op_test_rax]      ; "test rax, rax\n"
    call emit_str
    emit_indent
    lea rcx, [rel str_op_jnz]           ; "jnz .L"
    call emit_str
    pop rcx
    call emit_u64
    call emit_nl
    ret

; ------------------------------------------------------------------------------
; emit_push_rax: Emit "    push rax\n"
; ------------------------------------------------------------------------------
emit_push_rax:
    emit_indent
    lea rcx, [rel str_op_push_rax]
    jmp emit_str

; ------------------------------------------------------------------------------
; emit_pop_rcx: Emit "    pop rcx\n"
; ------------------------------------------------------------------------------
emit_pop_rcx:
    emit_indent
    lea rcx, [rel str_op_pop_rcx]
    jmp emit_str

; ------------------------------------------------------------------------------
; emit_pop_rdx: Emit "    pop rdx\n"
; ------------------------------------------------------------------------------
emit_pop_rdx:
    emit_indent
    lea rcx, [rel str_op_pop_rdx]
    jmp emit_str

; ------------------------------------------------------------------------------
; emit_pop_rdi: Emit "    pop rdi\n" (SysV Arg 1)
; ------------------------------------------------------------------------------
emit_pop_rdi:
    emit_indent
    lea rcx, [rel str_op_pop_rdi]
    jmp emit_str

; ------------------------------------------------------------------------------
; emit_pop_rsi: Emit "    pop rsi\n" (SysV Arg 2)
; ------------------------------------------------------------------------------
emit_pop_rsi:
    emit_indent
    lea rcx, [rel str_op_pop_rsi]
    jmp emit_str

; ------------------------------------------------------------------------------
; emit_pop_r8: Emit "    pop r8\n" (SysV Arg 5)
; ------------------------------------------------------------------------------
emit_pop_r8:
    emit_indent
    lea rcx, [rel str_op_pop_r8]
    jmp emit_str

; ------------------------------------------------------------------------------
; emit_pop_r9: Emit "    pop r9\n" (SysV Arg 6)
; ------------------------------------------------------------------------------
emit_pop_r9:
    emit_indent
    lea rcx, [rel str_op_pop_r9]
    jmp emit_str

; ------------------------------------------------------------------------------
; emit_load_imm: Emit "    mov rax, {imm}\n"
; Input: RCX = immediate value
; ------------------------------------------------------------------------------
emit_load_imm:
    push rcx
    emit_indent
    lea rcx, [rel str_op_mov_rax]       ; "mov rax, "
    call emit_str
    pop rcx
    call emit_i64
    call emit_nl
    ret

; ------------------------------------------------------------------------------
; emit_load_str_addr: Emit "    lea rax, [LC{id}]\n"
; Input: RCX = string id
; ------------------------------------------------------------------------------
emit_load_str_addr:
    push rcx
    emit_indent
    lea rcx, [rel str_op_lea_str]       ; "lea rax, [LC"
    call emit_str
    pop rcx
    call emit_u64
    lea rcx, [rel str_close_bracket_nl] ; "]\n"
    call emit_str
    ret

; ------------------------------------------------------------------------------
; emit_load_local_addr: Emit "    lea rax, [rbp - {offset}]\n"
; Input: RCX = stack offset
; ------------------------------------------------------------------------------
emit_load_local_addr:
    push rcx
    emit_indent
    lea rcx, [rel str_op_lea_local]     ; "lea rax, [rbp - "
    call emit_str
    pop rcx
    call emit_u64
    lea rcx, [rel str_close_bracket_nl] ; "]\n"
    call emit_str
    ret

; ------------------------------------------------------------------------------
; emit_load_global_addr: Emit "    lea rax, [{name}]\n"
; Input: RCX = global name pointer
; ------------------------------------------------------------------------------
emit_load_global_addr:
    push rcx
    emit_indent
    lea rcx, [rel str_op_lea_global]    ; "lea rax, ["
    call emit_str
    pop rcx
    call emit_str
    lea rcx, [rel str_close_bracket_nl] ; "]\n"
    call emit_str
    ret

; ------------------------------------------------------------------------------
; emit_deref: Dereference pointer in RAX to value in RAX based on byte size
; Input: RCX = size in bytes (1 for byte, 8 for qword)
; ------------------------------------------------------------------------------
emit_deref:
    push rcx
    emit_indent
    lea rcx, [rel str_op_mov_r11_rax]   ; "mov r11, rax\n"
    call emit_str
    pop rcx

    cmp rcx, 1
    je .byte_deref
    ; 64-bit dereference
    emit_indent
    lea rcx, [rel str_op_mov_rax_ptr]   ; "mov rax, [rax]\n"
    jmp emit_str
.byte_deref:
    emit_indent
    lea rcx, [rel str_op_movzx_rax_byte] ; "movzx eax, byte [rax]\n"
    jmp emit_str

; ------------------------------------------------------------------------------
; emit_store: Store value in RAX to address in RDX based on byte size
; Input: RCX = size in bytes (1 for byte, 8 for qword)
; ------------------------------------------------------------------------------
emit_store:
    cmp rcx, 1
    je .byte_store
    emit_indent
    lea rcx, [rel str_op_mov_ptr_rax]   ; "mov [rdx], rax\n"
    jmp emit_str
.byte_store:
    emit_indent
    lea rcx, [rel str_op_mov_byte_ptr_al]    ; "mov [rdx], al\n"
    jmp emit_str

; ------------------------------------------------------------------------------
; emit_binary_op: Generate binary operation
; Left operand in RCX, Right operand in RAX
; Result placed in RAX
; Input: R8 = operator token ('+', '-', '*', '/', '%', '&', '|', '^',
;                          TOK_SHL, TOK_SHR, TOK_EQ, TOK_NE, TOK_LE, TOK_GE, '<', '>')
; ------------------------------------------------------------------------------
emit_binary_op:
    push rbx
    push r8

    cmp r8, '+'
    je .do_add
    cmp r8, '-'
    je .do_sub
    cmp r8, '*'
    je .do_mul
    cmp r8, '/'
    je .do_div
    cmp r8, '%'
    je .do_mod
    cmp r8, '&'
    je .do_and
    cmp r8, '|'
    je .do_or
    cmp r8, '^'
    je .do_xor
    cmp r8, TOK_SHL
    je .do_shl
    cmp r8, TOK_SHR
    je .do_shr
    cmp r8, TOK_EQ
    je .do_eq
    cmp r8, TOK_NE
    je .do_ne
    cmp r8, '<'
    je .do_lt
    cmp r8, TOK_LE
    je .do_le
    cmp r8, '>'
    je .do_gt
    cmp r8, TOK_GE
    je .do_ge
    jmp .done

.do_add:
    emit_indent
    lea rcx, [rel str_op_add]           ; "add rax, rcx\n"
    call emit_str
    jmp .done

.do_sub:
    ; Left was in RCX, Right in RAX. We want Left - Right:
    emit_indent
    lea rcx, [rel str_op_sub]
    call emit_str
    jmp .done

.do_mul:
    emit_indent
    lea rcx, [rel str_op_imul]          ; "imul rax, rcx\n"
    call emit_str
    jmp .done

.do_div:
    ; Left in RCX, Right in RAX. We want Left / Right:
    emit_indent
    lea rcx, [rel str_op_div]
    call emit_str
    jmp .done

.do_mod:
    ; Left in RCX, Right in RAX. We want Left % Right:
    emit_indent
    lea rcx, [rel str_op_mod]
    call emit_str
    jmp .done

.do_and:
    emit_indent
    lea rcx, [rel str_op_and]           ; "and rax, rcx\n"
    call emit_str
    jmp .done

.do_or:
    emit_indent
    lea rcx, [rel str_op_or]            ; "or rax, rcx\n"
    call emit_str
    jmp .done

.do_xor:
    emit_indent
    lea rcx, [rel str_op_xor]           ; "xor rax, rcx\n"
    call emit_str
    jmp .done

.do_shl:
    emit_indent
    lea rcx, [rel str_op_shl]
    call emit_str
    jmp .done

.do_shr:
    emit_indent
    lea rcx, [rel str_op_shr]
    call emit_str
    jmp .done

.do_eq:
    emit_indent
    lea rcx, [rel str_op_cmp_sete]
    call emit_str
    jmp .done

.do_ne:
    emit_indent
    lea rcx, [rel str_op_cmp_setne]
    call emit_str
    jmp .done

.do_lt:
    emit_indent
    lea rcx, [rel str_op_cmp_setl]
    call emit_str
    jmp .done

.do_le:
    emit_indent
    lea rcx, [rel str_op_cmp_setle]
    call emit_str
    jmp .done

.do_gt:
    emit_indent
    lea rcx, [rel str_op_cmp_setg]
    call emit_str
    jmp .done

.do_ge:
    emit_indent
    lea rcx, [rel str_op_cmp_setge]
    call emit_str
    jmp .done

.done:
    pop r8
    pop rbx
    ret

; ------------------------------------------------------------------------------
; emit_unary_op: Generate unary operation on RAX
; Input: RCX = operator token ('-', '~', '!')
; ------------------------------------------------------------------------------
emit_unary_op:
    cmp rcx, '-'
    jne .check_not
    emit_indent
    lea rcx, [rel str_op_neg]           ; "neg rax\n"
    jmp emit_str
.check_not:
    cmp rcx, '~'
    jne .check_bang
    emit_indent
    lea rcx, [rel str_op_not]           ; "not rax\n"
    jmp emit_str
.check_bang:
    cmp rcx, '!'
    jne .done
    emit_indent
    lea rcx, [rel str_op_bang]          ; "test rax, rax\n    setz al\n    movzx eax, al\n"
    jmp emit_str
.done:
    ret

; ------------------------------------------------------------------------------
; emit_func_prologue: Start of function
; Input: RCX = function name pointer
; ------------------------------------------------------------------------------
emit_func_prologue:
    push rbx
    push rsi
    sub rsp, 40
    mov rsi, rcx

    call emit_nl
    ; Emit "global {name}"
    lea rcx, [rel str_global_prefix]    ; "global "
    call emit_str
    mov rcx, rsi
    call emit_str
    call emit_nl

    ; Emit "{name}:"
    mov rcx, rsi
    call emit_named_label

    ; Emit "    push rbp\n    mov rbp, rsp\n"
    emit_indent
    lea rcx, [rel str_prologue]
    call emit_str

    add rsp, 40
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; emit_func_alloc_stack: Reserve local variable space
; Input: RCX = total local stack bytes (aligned to 16 bytes)
; ------------------------------------------------------------------------------
emit_func_alloc_stack:
    push rcx
    test rcx, rcx
    jz .done
    emit_indent
    lea rcx, [rel str_sub_rsp]          ; "sub rsp, "
    call emit_str
    pop rcx
    call emit_u64
    call emit_nl
    ret
.done:
    pop rcx
    ret

; ------------------------------------------------------------------------------
; emit_func_epilogue: Function exit label and return
; Input: RCX = function return label ID
; ------------------------------------------------------------------------------
emit_func_epilogue:
    push rcx
    call emit_label
    emit_indent
    lea rcx, [rel str_epilogue]         ; "mov rsp, rbp\n    pop rbp\n    ret\n"
    call emit_str
    pop rcx
    ret
