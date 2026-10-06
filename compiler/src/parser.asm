; ==============================================================================
; c_compiler_asm - Pure x86-64 Assembly C Compiler
; parser.asm - Recursive descent parser & syntax-directed code generator
; ==============================================================================

section .text

; ------------------------------------------------------------------------------
; Forward declarations & helpers
; ------------------------------------------------------------------------------
; expect: verify current token is expected type, then advance
; Input: RCX = expected token type
; ------------------------------------------------------------------------------
expect:
    push rbx
    mov rbx, rcx
    cmp [rel tok_type], rbx
    jne .unexpected
    call next_token
    pop rbx
    ret
.unexpected:
    lea rcx, [rel str_err_unexpected_tok]
    jmp compile_error

; ------------------------------------------------------------------------------
; Loop and switch label stacks
; ------------------------------------------------------------------------------
push_break:
    mov rax, [rel break_stack_depth]
    cmp rax, MAX_LOOP_DEPTH
    jae .err
    lea r10, [rel break_stack_labels]
    mov [r10 + rax * 8], rcx
    inc qword [rel break_stack_depth]
    ret
.err:
    lea rcx, [rel str_err_loop_depth]
    jmp compile_error

pop_break:
    dec qword [rel break_stack_depth]
    ret

push_loop:
    ; RCX = cont_label, RDX = break_label
    push rdx
    mov rax, [rel loop_depth]
    cmp rax, MAX_LOOP_DEPTH
    jae .err
    lea r10, [rel loop_cont_labels]
    mov [r10 + rax * 8], rcx
    lea r10, [rel loop_break_labels]
    mov [r10 + rax * 8], rdx
    inc qword [rel loop_depth]
    pop rcx
    call push_break
    ret
.err:
    pop rdx
    lea rcx, [rel str_err_loop_depth]
    jmp compile_error

pop_loop:
    call pop_break
    dec qword [rel loop_depth]
    ret

push_switch:
    ; RCX = break_label, RDX = dispatch_label
    push rcx
    mov rax, [rel switch_depth]
    cmp rax, MAX_LOOP_DEPTH
    jae .err
    lea r10, [rel switch_break_labels]
    mov [r10 + rax * 8], rcx
    lea r10, [rel switch_dispatch_labels]
    mov [r10 + rax * 8], rdx
    lea r10, [rel switch_default_labels]
    mov qword [r10 + rax * 8], 0
    mov r8, [rel case_count]
    lea r10, [rel switch_case_starts]
    mov [r10 + rax * 8], r8
    inc qword [rel switch_depth]
    pop rcx
    call push_break
    ret
.err:
    pop rcx
    lea rcx, [rel str_err_loop_depth]
    jmp compile_error

pop_switch:
    call pop_break
    dec qword [rel switch_depth]
    ret

; ------------------------------------------------------------------------------
; parse_type: Parse type specifier and pointer stars
; Output: RCX points to filled TYPE_DESC structure
; ------------------------------------------------------------------------------
parse_type:
    push rbx
    push rsi
    push rdi
    sub rsp, 48

    ; Temporary type descriptor on stack or in type_tmp
    lea rdi, [rel type_tmp]
    mov rcx, rdi
    mov dl, 0
    mov r8, TYPE_DESC_SIZE
    call mem_set

.qual_loop:
    mov rax, [rel tok_type]
    cmp rax, TOK_CONST
    je .skip_qual
    cmp rax, TOK_STATIC
    je .skip_qual
    cmp rax, TOK_UNSIGNED
    je .skip_qual
    cmp rax, TOK_SIGNED
    je .skip_qual
    jmp .chk_type
.skip_qual:
    call next_token
    jmp .qual_loop

.chk_type:
    mov rax, [rel tok_type]
    cmp rax, TOK_INT
    je .is_int
    cmp rax, TOK_LONG
    je .is_long
    cmp rax, TOK_CHAR
    je .is_char
    cmp rax, TOK_VOID
    je .is_void
    cmp rax, TOK_STRUCT
    je .is_struct
    ; Default to int if identifier or unrecognized
    mov qword [rdi + 0], TYPE_INT
    jmp .stars

.is_long:
    mov qword [rdi + 0], TYPE_INT
    call next_token
    cmp qword [rel tok_type], TOK_LONG
    je .eat_long2
    cmp qword [rel tok_type], TOK_INT
    jne .stars
.eat_long2:
    call next_token
    jmp .stars

.is_int:
    mov qword [rdi + 0], TYPE_INT
    call next_token
    jmp .stars

.is_char:
    mov qword [rdi + 0], TYPE_CHAR
    call next_token
    jmp .stars

.is_void:
    mov qword [rdi + 0], TYPE_VOID
    call next_token
    jmp .stars

.is_struct:
    call next_token         ; consume 'struct'
    ; Next must be struct name (TOK_IDENT)
    cmp qword [rel tok_type], TOK_IDENT
    jne .err_struct
    ; Look up struct in table
    lea rcx, [rel tok_str]
    call struct_lookup
    cmp rax, -1
    je .err_unknown_struct
    mov qword [rdi + 0], TYPE_STRUCT
    mov [rdi + 32], rax     ; struct_id
    call next_token
    jmp .stars

.err_struct:
    lea rcx, [rel str_err_expected_struct_name]
    jmp compile_error

.err_unknown_struct:
    lea rcx, [rel str_err_unknown_struct]
    jmp compile_error

.stars:
    ; Parse pointer indirection '*'
    cmp qword [rel tok_type], '*'
    jne .done
    inc qword [rdi + 8]     ; ptr_level++
    call next_token
    jmp .stars

.done:
    ; Compute size
    mov rcx, rdi
    call compute_type_size
    lea rax, [rel type_tmp]
    add rsp, 48
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_primary: Parse primary expression
; Output: result in RAX, type recorded in expr_type
; ------------------------------------------------------------------------------
parse_primary:
    push rbx
    push rsi
    push rdi
    sub rsp, 48

    mov rax, [rel tok_type]
    cmp rax, TOK_NUM
    je .num
    cmp rax, TOK_CHAR_LIT
    je .num
    cmp rax, TOK_STR
    je .str
    cmp rax, TOK_IDENT
    je .ident
    cmp rax, '('
    je .paren
    cmp rax, TOK_SIZEOF
    je .sizeof_expr

    ; Syntax error
    lea rcx, [rel str_err_expected_expr]
    jmp compile_error

.num:
    mov rcx, [rel tok_num]
    call emit_load_imm
    ; Set expr_type = int
    mov qword [rel expr_type + 0], TYPE_INT
    mov qword [rel expr_type + 8], 0
    mov qword [rel expr_type + 16], 0
    mov qword [rel expr_type + 40], 8
    call next_token
    jmp .ret

.str:
    ; Add string to literal pool
    lea rcx, [rel tok_str]
    mov rdx, [rel tok_len]
    call string_pool_add
    mov rcx, rax            ; string id
    call emit_load_str_addr
    ; Set expr_type = char*
    mov qword [rel expr_type + 0], TYPE_CHAR
    mov qword [rel expr_type + 8], 1
    mov qword [rel expr_type + 16], 0
    mov qword [rel expr_type + 40], 8
    call next_token
    jmp .ret

.paren:
    call next_token         ; consume '('
    call parse_expr
    mov rcx, ')'
    call expect
    jmp .ret

.sizeof_expr:
    call parse_sizeof
    jmp .ret

.ident:
    ; Identifier: can be variable or function call
    lea rcx, [rel ident_tmp]
    lea rdx, [rel tok_str]
    call str_copy
    call next_token         ; consume ident

    cmp qword [rel tok_type], '('
    je .func_call

    ; It's a variable reference
    ; Search local first
    lea rcx, [rel ident_tmp]
    call local_lookup
    test rax, rax
    jnz .is_local

    ; Search global
    lea rcx, [rel ident_tmp]
    call global_lookup
    test rax, rax
    jnz .is_global

    ; Undeclared variable error
    lea rcx, [rel str_err_undeclared_var]
    jmp compile_error

.is_local:
    mov rsi, rax            ; LOCAL_ENTRY pointer
    ; Record last l-value
    mov qword [rel last_lval_kind], 1
    mov r8, [rsi + 64 + 48]
    mov [rel last_lval_offset], r8
    mov r8, [rsi + 64 + 40]
    mov [rel last_lval_size], r8

    ; Copy type to expr_type
    lea rcx, [rel expr_type]
    lea rdx, [rsi + 64]
    mov r8, TYPE_DESC_SIZE
    call mem_copy

    ; Check if array: array name evaluates to its base address
    cmp qword [rsi + 64 + 16], 1
    je .arr_addr_local
    cmp qword [rsi + 64 + 0], TYPE_STRUCT
    jne .not_struct_local
    cmp qword [rsi + 64 + 8], 0
    je .struct_addr_local
.not_struct_local:

    ; Load address, then dereference
    mov rcx, [rsi + 64 + 48] ; stack_offset
    call emit_load_local_addr
    mov rcx, [rel expr_type + 40] ; size
    call emit_deref
    jmp .ret

.struct_addr_local:
    mov rcx, [rsi + 64 + 48]
    call emit_load_local_addr
    jmp .ret

.arr_addr_local:
    mov rcx, [rsi + 64 + 48]
    call emit_load_local_addr
    ; Array evaluates to pointer to elements
    mov qword [rel expr_type + 8], 1
    jmp .ret

.is_global:
    mov rsi, rax            ; GLOBAL_ENTRY pointer
    ; Record last l-value
    mov qword [rel last_lval_kind], 2
    mov r8, [rsi + 64 + 40]
    mov [rel last_lval_size], r8
    push rsi
    lea rcx, [rel last_lval_name]
    lea rdx, [rel ident_tmp]
    call str_copy
    pop rsi

    lea rcx, [rel expr_type]
    lea rdx, [rsi + 64]
    mov r8, TYPE_DESC_SIZE
    call mem_copy

    cmp qword [rsi + 64 + 16], 1
    je .arr_addr_global
    cmp qword [rsi + 64 + 0], TYPE_STRUCT
    jne .not_struct_global
    cmp qword [rsi + 64 + 8], 0
    je .struct_addr_global
.not_struct_global:

    lea rcx, [rel ident_tmp]
    call emit_load_global_addr
    mov rcx, [rel expr_type + 40]
    call emit_deref
    jmp .ret

.struct_addr_global:
    lea rcx, [rel ident_tmp]
    call emit_load_global_addr
    jmp .ret

.arr_addr_global:
    lea rcx, [rel ident_tmp]
    call emit_load_global_addr
    mov qword [rel expr_type + 8], 1
    jmp .ret

.func_call:
    ; Function call: ident_tmp(args...)
    call next_token         ; consume '('
    call parse_func_call_args
    ; Return type of function: int
    mov qword [rel expr_type + 0], TYPE_INT
    mov qword [rel expr_type + 8], 0
    mov qword [rel expr_type + 16], 0
    mov qword [rel expr_type + 40], 8

.ret:
    add rsp, 48
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_func_call_args: Parse arguments for function call to ident_tmp
; Win64 ABI: First 4 in RCX, RDX, R8, R9. 5th+ on stack. 32-byte shadow space.
; ------------------------------------------------------------------------------
parse_func_call_args:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 48

    ; Register function in extern list
    lea rcx, [rel ident_tmp]
    call extern_add

    ; Save function name
    lea rdi, [rsp]
    lea rdx, [rel ident_tmp]
    mov rcx, rdi
    call str_copy

    xor r12, r12            ; argc = 0
    cmp qword [rel tok_type], ')'
    je .args_done

.arg_loop:
    call parse_assign_expr  ; result in RAX
    call emit_push_rax      ; push arg on stack
    inc r12
    cmp qword [rel tok_type], ','
    jne .args_done
    call next_token         ; consume ','
    jmp .arg_loop

.args_done:
    mov rcx, ')'
    call expect

.no_args:
    ; Now we have r12 arguments on stack
    ; SysV calling convention (CustomC-OS):
    ; Up to 6 arguments in registers: RDI, RSI, RDX, RCX, R8, R9
    cmp r12, 6
    ja .many_args

    cmp r12, 6
    jne .c5
    call emit_pop_r9
.c5:
    cmp r12, 5
    jb .c4
    call emit_pop_r8
.c4:
    cmp r12, 4
    jb .c3
    call emit_pop_rcx
.c3:
    cmp r12, 3
    jb .c2
    call emit_pop_rdx
.c2:
    cmp r12, 2
    jb .c1
    call emit_pop_rsi
.c1:
    cmp r12, 1
    jb .call_0
    call emit_pop_rdi

.call_0:
    emit_indent
    lea rcx, [rel str_op_xor_eax]
    call emit_str

    emit_indent
    lea rcx, [rel str_call_prefix]
    call emit_str
    mov rcx, rsp
    call emit_str
    call emit_nl
    jmp .done

.many_args:
    call emit_pop_r9
    call emit_pop_r8
    call emit_pop_rcx
    call emit_pop_rdx
    call emit_pop_rsi
    call emit_pop_rdi

    emit_indent
    lea rcx, [rel str_op_xor_eax]
    call emit_str

    emit_indent
    lea rcx, [rel str_call_prefix]
    call emit_str
    mov rcx, rsp
    call emit_str
    call emit_nl

    mov rax, r12
    sub rax, 6
    imul rax, 8
    emit_indent
    lea rcx, [rel str_add_rsp]
    call emit_str
    mov rcx, rax
    call emit_u64
    call emit_nl
.done:
    add rsp, 48
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret



; ------------------------------------------------------------------------------
; parse_postfix: Handle array indexing [i], member access ., ->, post inc/dec
; ------------------------------------------------------------------------------
parse_postfix:
    push rbx
    push rsi
    push rdi
    sub rsp, 48

    call parse_primary

.loop:
    mov rax, [rel tok_type]
    cmp rax, '['
    je .index
    cmp rax, '.'
    je .dot
    cmp rax, TOK_ARROW
    je .arrow
    cmp rax, TOK_INC
    je .post_inc
    cmp rax, TOK_DEC
    je .post_dec
    jmp .done

.index:
    ; Array indexing: RAX has base address/pointer, expr_type has base type
    call next_token         ; consume '['
    call emit_push_rax      ; push base address

    ; Save element size
    lea rcx, [rel expr_type]
    call get_elem_size
    mov rbx, rax            ; elem_size

    ; Parse index expression
    call parse_expr         ; index in RAX
    ; Scale index by elem_size if elem_size > 1
    cmp rbx, 1
    jbe .no_scale
    emit_indent
    lea rcx, [rel str_op_imul_imm]
    call emit_str
    mov rcx, rbx
    call emit_u64
    call emit_nl
.no_scale:
    ; Add index to base address
    call emit_pop_rcx      ; base address in RCX
    emit_indent
    lea rcx, [rel str_op_add] ; add rax, rcx -> rax now has element address
    call emit_str

    mov rcx, ']'
    call expect

    ; Dereference element address (unless it's an array/struct)
    cmp qword [rel expr_type + 8], 1
    ja .idx_deref_ptr
    cmp qword [rel expr_type + 0], TYPE_STRUCT
    je .idx_is_struct
    ; Dereference scalar element
    mov rcx, rbx            ; elem_size
    call emit_deref
    dec qword [rel expr_type + 8] ; ptr_level--
    jmp .loop

.idx_deref_ptr:
    mov rcx, 8
    call emit_deref
    dec qword [rel expr_type + 8]
    jmp .loop

.idx_is_struct:
    dec qword [rel expr_type + 8]
    jmp .loop

.dot:
    ; Struct member access: s.member
    call next_token         ; consume '.'
    cmp qword [rel tok_type], TOK_IDENT
    jne .err_member
    ; Member lookup
    mov rcx, [rel expr_type + 32] ; struct_id
    lea rdx, [rel tok_str]
    call struct_find_member
    test rax, rax
    jz .err_unknown_member

    mov rsi, rax            ; MEMBER_ENTRY pointer
    ; Add member offset to RAX
    mov r8, [rsi + 64]      ; member offset
    test r8, r8
    jz .no_dot_off
    emit_indent
    lea rcx, [rel str_op_add_rax_imm]
    call emit_str
    mov rcx, r8
    call emit_u64
    call emit_nl
.no_dot_off:
    ; Copy member type to expr_type
    lea rcx, [rel expr_type]
    lea rdx, [rsi + 72]
    mov r8, TYPE_DESC_SIZE
    call mem_copy

    ; If member is scalar, dereference
    cmp qword [rel expr_type + 16], 1 ; is_array?
    je .dot_next
    cmp qword [rel expr_type + 0], TYPE_STRUCT
    je .dot_next
    mov rcx, [rel expr_type + 40]
    call emit_deref

.dot_next:
    call next_token
    jmp .loop

.arrow:
    ; Pointer struct member access: p->member
    call next_token         ; consume '->'
    cmp qword [rel tok_type], TOK_IDENT
    jne .err_member
    mov rcx, [rel expr_type + 32]
    lea rdx, [rel tok_str]
    call struct_find_member
    test rax, rax
    jz .err_unknown_member

    mov rsi, rax
    mov r8, [rsi + 64]
    test r8, r8
    jz .no_arr_off
    emit_indent
    lea rcx, [rel str_op_add_rax_imm]
    call emit_str
    mov rcx, r8
    call emit_u64
    call emit_nl
.no_arr_off:
    lea rcx, [rel expr_type]
    lea rdx, [rsi + 72]
    mov r8, TYPE_DESC_SIZE
    call mem_copy

    cmp qword [rel expr_type + 16], 1
    je .arrow_next
    cmp qword [rel expr_type + 0], TYPE_STRUCT
    je .arrow_next
    mov rcx, [rel expr_type + 40]
    call emit_deref

.arrow_next:
    call next_token
    jmp .loop

.post_inc:
    ; Post-increment: x++
    call next_token
    emit_indent
    lea rcx, [rel str_op_inc_r11_ptr]
    call emit_str
    jmp .loop

.post_dec:
    ; Post-decrement: x--
    call next_token
    emit_indent
    lea rcx, [rel str_op_dec_r11_ptr]
    call emit_str
    jmp .loop

.done:
    add rsp, 48
    pop rdi
    pop rsi
    pop rbx
    ret

.err_member:
    lea rcx, [rel str_err_expected_member]
    jmp compile_error

.err_unknown_member:
    lea rcx, [rel str_err_unknown_member]
    jmp compile_error

; ------------------------------------------------------------------------------
; parse_unary: Prefix ++, --, &, *, +, -, ~, !, sizeof
; ------------------------------------------------------------------------------
parse_unary:
    push rbx
    push rsi
    sub rsp, 40

    mov rax, [rel tok_type]
    cmp rax, '+'
    je .unary_plus
    cmp rax, '-'
    je .unary_minus
    cmp rax, '~'
    je .unary_not
    cmp rax, '!'
    je .unary_bang
    cmp rax, '*'
    je .unary_deref
    cmp rax, '&'
    je .unary_addr
    cmp rax, TOK_INC
    je .unary_pre_inc
    cmp rax, TOK_DEC
    je .unary_pre_dec
    cmp rax, TOK_SIZEOF
    je .unary_sizeof

    ; Fall through to postfix
    call parse_postfix
    jmp .ret

.unary_plus:
    call next_token
    call parse_unary
    jmp .ret

.unary_minus:
    call next_token
    call parse_unary
    mov rcx, '-'
    call emit_unary_op
    jmp .ret

.unary_not:
    call next_token
    call parse_unary
    mov rcx, '~'
    call emit_unary_op
    jmp .ret

.unary_bang:
    call next_token
    call parse_unary
    mov rcx, '!'
    call emit_unary_op
    jmp .ret

.unary_deref:
    call next_token         ; consume '*'
    call parse_unary        ; address in RAX
    ; Dereference
    mov rcx, [rel expr_type + 40]
    test rcx, rcx
    jnz .do_d
    mov rcx, 8
.do_d:
    call emit_deref
    dec qword [rel expr_type + 8] ; ptr_level--
    jmp .ret

.unary_addr:
    call next_token         ; consume '&'
    ; Must be an L-value (identifier)
    cmp qword [rel tok_type], TOK_IDENT
    jne .err_lval
    ; Lookup variable
    lea rcx, [rel tok_str]
    call local_lookup
    test rax, rax
    jnz .addr_local
    lea rcx, [rel tok_str]
    call global_lookup
    test rax, rax
    jnz .addr_global
    lea rcx, [rel str_err_undeclared_var]
    jmp compile_error

.addr_local:
    mov rcx, [rax + 64 + 48]
    call emit_load_local_addr
    inc qword [rel expr_type + 8] ; ptr_level++
    call next_token
    jmp .ret

.addr_global:
    lea rcx, [rel tok_str]
    call emit_load_global_addr
    inc qword [rel expr_type + 8]
    call next_token
    jmp .ret

.unary_pre_inc:
    call next_token
    call parse_unary
    emit_indent
    lea rcx, [rel str_op_inc_r11_ptr]
    call emit_str
    emit_indent
    lea rcx, [rel str_op_mov_rax_r11_ptr]
    call emit_str
    jmp .ret

.unary_pre_dec:
    call next_token
    call parse_unary
    emit_indent
    lea rcx, [rel str_op_dec_r11_ptr]
    call emit_str
    emit_indent
    lea rcx, [rel str_op_mov_rax_r11_ptr]
    call emit_str
    jmp .ret

.unary_sizeof:
    call parse_sizeof
    jmp .ret

.ret:
    add rsp, 40
    pop rsi
    pop rbx
    ret

.err_lval:
    lea rcx, [rel str_err_expected_lvalue]
    jmp compile_error

; ------------------------------------------------------------------------------
; parse_sizeof: sizeof(type) or sizeof(expr)
; ------------------------------------------------------------------------------
parse_sizeof:
    push rbx
    sub rsp, 48
    call next_token         ; consume 'sizeof'
    mov rcx, '('
    call expect

    ; Check if type name
    mov rax, [rel tok_type]
    cmp rax, TOK_INT
    je .sz_type
    cmp rax, TOK_CHAR
    je .sz_type
    cmp rax, TOK_VOID
    je .sz_type
    cmp rax, TOK_STRUCT
    je .sz_type

    ; Otherwise parse expression
    call parse_expr
    mov rax, [rel expr_type + 40] ; size of expression
    jmp .sz_emit

.sz_type:
    call parse_type
    mov rax, [rel type_tmp + 40]

.sz_emit:
    mov rcx, ')'
    call expect
    mov rcx, rax
    call emit_load_imm
    mov qword [rel expr_type + 0], TYPE_INT
    mov qword [rel expr_type + 8], 0
    mov qword [rel expr_type + 40], 8
    add rsp, 48
    pop rbx
    ret

; ------------------------------------------------------------------------------
; Binary Expression Parsing: Precedence Hierarchy
; parse_multiplicative: *, /, %
; parse_additive: +, -
; parse_shift: <<, >>
; parse_relational: <, <=, >, >=
; parse_equality: ==, !=
; parse_bit_and: &
; parse_bit_xor: ^
; parse_bit_or: |
; parse_log_and: &&
; parse_log_or: ||
; parse_conditional: ? :
; parse_assign_expr: =, +=, -=, etc.
; parse_expr: , (comma)
; ------------------------------------------------------------------------------

parse_multiplicative:
    push rbx
    push rsi
    sub rsp, 40
    call parse_unary
.loop:
    mov rax, [rel tok_type]
    cmp rax, '*'
    je .do_op
    cmp rax, '/'
    je .do_op
    cmp rax, '%'
    je .do_op
    jmp .done
.do_op:
    mov rbx, rax            ; save operator
    call emit_push_rax      ; push LHS
    call next_token
    call parse_unary        ; RHS in RAX
    call emit_pop_rcx      ; LHS in RCX
    mov r8, rbx
    call emit_binary_op
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

parse_additive:
    push rbx
    push rsi
    sub rsp, 40
    call parse_multiplicative
.loop:
    mov rax, [rel tok_type]
    cmp rax, '+'
    je .do_op
    cmp rax, '-'
    je .do_op
    jmp .done
.do_op:
    mov rbx, rax
    call emit_push_rax
    call next_token
    call parse_multiplicative
    call emit_pop_rcx
    mov r8, rbx
    call emit_binary_op
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

parse_shift:
    push rbx
    push rsi
    sub rsp, 40
    call parse_additive
.loop:
    mov rax, [rel tok_type]
    cmp rax, TOK_SHL
    je .do_op
    cmp rax, TOK_SHR
    je .do_op
    jmp .done
.do_op:
    mov rbx, rax
    call emit_push_rax
    call next_token
    call parse_additive
    call emit_pop_rcx
    mov r8, rbx
    call emit_binary_op
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

parse_relational:
    push rbx
    push rsi
    sub rsp, 40
    call parse_shift
.loop:
    mov rax, [rel tok_type]
    cmp rax, '<'
    je .do_op
    cmp rax, TOK_LE
    je .do_op
    cmp rax, '>'
    je .do_op
    cmp rax, TOK_GE
    je .do_op
    jmp .done
.do_op:
    mov rbx, rax
    call emit_push_rax
    call next_token
    call parse_shift
    call emit_pop_rcx
    mov r8, rbx
    call emit_binary_op
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

parse_equality:
    push rbx
    push rsi
    sub rsp, 40
    call parse_relational
.loop:
    mov rax, [rel tok_type]
    cmp rax, TOK_EQ
    je .do_op
    cmp rax, TOK_NE
    je .do_op
    jmp .done
.do_op:
    mov rbx, rax
    call emit_push_rax
    call next_token
    call parse_relational
    call emit_pop_rcx
    mov r8, rbx
    call emit_binary_op
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

parse_bit_and:
    push rbx
    push rsi
    sub rsp, 40
    call parse_equality
.loop:
    cmp qword [rel tok_type], '&'
    jne .done
    mov rbx, '&'
    call emit_push_rax
    call next_token
    call parse_equality
    call emit_pop_rcx
    mov r8, rbx
    call emit_binary_op
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

parse_bit_xor:
    push rbx
    push rsi
    sub rsp, 40
    call parse_bit_and
.loop:
    cmp qword [rel tok_type], '^'
    jne .done
    mov rbx, '^'
    call emit_push_rax
    call next_token
    call parse_bit_and
    call emit_pop_rcx
    mov r8, rbx
    call emit_binary_op
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

parse_bit_or:
    push rbx
    push rsi
    sub rsp, 40
    call parse_bit_xor
.loop:
    cmp qword [rel tok_type], '|'
    jne .done
    mov rbx, '|'
    call emit_push_rax
    call next_token
    call parse_bit_xor
    call emit_pop_rcx
    mov r8, rbx
    call emit_binary_op
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_log_and: && with short-circuit evaluation
; ------------------------------------------------------------------------------
parse_log_and:
    push rbx
    push rsi
    sub rsp, 40
    call parse_bit_or
.loop:
    cmp qword [rel tok_type], TOK_LOGAND
    jne .done
    call gen_new_label
    mov rbx, rax            ; false_label
    call gen_new_label
    mov rsi, rax            ; end_label

    mov rcx, rbx
    call emit_jz            ; if LHS == 0, jump to false_label
    call next_token
    call parse_bit_or       ; RHS
    mov rcx, rbx
    call emit_jz            ; if RHS == 0, jump to false_label

    mov rcx, 1
    call emit_load_imm
    mov rcx, rsi
    call emit_jmp

    mov rcx, rbx
    call emit_label
    xor ecx, ecx
    call emit_load_imm

    mov rcx, rsi
    call emit_label
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_log_or: || with short-circuit evaluation
; ------------------------------------------------------------------------------
parse_log_or:
    push rbx
    push rsi
    sub rsp, 40
    call parse_log_and
.loop:
    cmp qword [rel tok_type], TOK_LOGOR
    jne .done
    call gen_new_label
    mov rbx, rax            ; true_label
    call gen_new_label
    mov rsi, rax            ; end_label

    mov rcx, rbx
    call emit_jnz           ; if LHS != 0, jump to true_label
    call next_token
    call parse_log_and      ; RHS
    mov rcx, rbx
    call emit_jnz           ; if RHS != 0, jump to true_label

    xor ecx, ecx
    call emit_load_imm
    mov rcx, rsi
    call emit_jmp

    mov rcx, rbx
    call emit_label
    mov rcx, 1
    call emit_load_imm

    mov rcx, rsi
    call emit_label
    jmp .loop
.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_conditional: Ternary operator cond ? true_expr : false_expr
; ------------------------------------------------------------------------------
parse_conditional:
    push rbx
    push rsi
    sub rsp, 40
    call parse_log_or
    cmp qword [rel tok_type], '?'
    jne .done

    call gen_new_label
    mov rbx, rax            ; false_label
    call gen_new_label
    mov rsi, rax            ; end_label

    mov rcx, rbx
    call emit_jz            ; if cond == 0, jump to false_label

    call next_token         ; consume '?'
    call parse_expr         ; true_expr
    mov rcx, rsi
    call emit_jmp

    mov rcx, ':'
    call expect

    mov rcx, rbx
    call emit_label
    call parse_conditional  ; false_expr

    mov rcx, rsi
    call emit_label

.done:
    add rsp, 40
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_assign_expr: =, +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=
; ------------------------------------------------------------------------------
parse_assign_expr:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 48

    call parse_conditional

    mov rax, [rel tok_type]
    cmp rax, '='
    je .simple_assign
    cmp rax, TOK_ADD_ASSIGN
    je .compound_assign
    cmp rax, TOK_SUB_ASSIGN
    je .compound_assign
    cmp rax, TOK_MUL_ASSIGN
    je .compound_assign
    cmp rax, TOK_DIV_ASSIGN
    je .compound_assign
    cmp rax, TOK_MOD_ASSIGN
    je .compound_assign
    cmp rax, TOK_AND_ASSIGN
    je .compound_assign
    cmp rax, TOK_OR_ASSIGN
    je .compound_assign
    cmp rax, TOK_XOR_ASSIGN
    je .compound_assign
    cmp rax, TOK_SHL_ASSIGN
    je .compound_assign
    cmp rax, TOK_SHR_ASSIGN
    je .compound_assign
    jmp .done

.simple_assign:
    mov r12, [rel expr_type + 40] ; target size
    emit_indent
    lea rcx, [rel str_op_push_r11] ; push target address
    call emit_str

.sa_eval_rhs:
    call next_token              ; consume '='
    call parse_assign_expr       ; RHS in RAX
    call emit_pop_rdx            ; target address in RDX
    mov rcx, r12
    test rcx, rcx
    jnz .sa_store
    mov rcx, 8
.sa_store:
    call emit_store              ; store RAX into [RDX]
    jmp .done

.compound_assign:
    mov r13, rax                 ; save compound operator
    mov r12, [rel expr_type + 40] ; target size
    emit_indent
    lea rcx, [rel str_op_push_r11] ; push target address
    call emit_str
    call emit_push_rax           ; push old value onto stack

.ca_eval_rhs:
    call next_token              ; consume compound op
    call parse_assign_expr       ; evaluate RHS into RAX
    call emit_pop_rcx            ; pop old value into RCX (Left operand)

    mov r8, '+'
    cmp r13, TOK_ADD_ASSIGN
    je .do_cop
    mov r8, '-'
    cmp r13, TOK_SUB_ASSIGN
    je .do_cop
    mov r8, '*'
    cmp r13, TOK_MUL_ASSIGN
    je .do_cop
    mov r8, '/'
    cmp r13, TOK_DIV_ASSIGN
    je .do_cop
    mov r8, '%'
    cmp r13, TOK_MOD_ASSIGN
    je .do_cop
    mov r8, '&'
    cmp r13, TOK_AND_ASSIGN
    je .do_cop
    mov r8, '|'
    cmp r13, TOK_OR_ASSIGN
    je .do_cop
    mov r8, '^'
    cmp r13, TOK_XOR_ASSIGN
    je .do_cop
    mov r8, TOK_SHL
    cmp r13, TOK_SHL_ASSIGN
    je .do_cop
    mov r8, TOK_SHR
    cmp r13, TOK_SHR_ASSIGN
    je .do_cop

.do_cop:
    call emit_binary_op          ; RAX = Left OP Right
    call emit_pop_rdx            ; pop target address into RDX
    mov rcx, r12
    test rcx, rcx
    jnz .ca_store
    mov rcx, 8
.ca_store:
    call emit_store              ; store result into [RDX]
    jmp .done

.done:
    add rsp, 48
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_expr: Comma operator
; ------------------------------------------------------------------------------
parse_expr:
    push rbx
    sub rsp, 48
    call parse_assign_expr
.loop:
    cmp qword [rel tok_type], ','
    jne .done
    call next_token
    call parse_assign_expr
    jmp .loop
.done:
    add rsp, 48
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_stmt: Parse any statement
; Supports: if, while, for, do-while, switch, return, break, continue, compound, expr
; ------------------------------------------------------------------------------
parse_stmt:
    push rbx
    push rsi
    push rdi
    sub rsp, 48

    mov rax, [rel tok_type]
    cmp rax, TOK_IF
    je .stmt_if
    cmp rax, TOK_WHILE
    je .stmt_while
    cmp rax, TOK_FOR
    je .stmt_for
    cmp rax, TOK_DO
    je .stmt_do
    cmp rax, TOK_SWITCH
    je .stmt_switch
    cmp rax, TOK_CASE
    je .stmt_case
    cmp rax, TOK_DEFAULT
    je .stmt_default
    cmp rax, TOK_RETURN
    je .stmt_return
    cmp rax, TOK_BREAK
    je .stmt_break
    cmp rax, TOK_CONTINUE
    je .stmt_continue
    cmp rax, '{'
    je .stmt_compound
    cmp rax, ';'
    je .stmt_empty

    ; Expression statement
    call parse_expr
    mov rcx, ';'
    call expect
    jmp .done

.stmt_empty:
    call next_token
    jmp .done

.stmt_if:
    call next_token         ; consume 'if'
    mov rcx, '('
    call expect
    call parse_expr         ; cond in RAX
    mov rcx, ')'
    call expect

    call gen_new_label
    mov rbx, rax            ; else_label
    call gen_new_label
    mov rsi, rax            ; end_label

    mov rcx, rbx
    call emit_jz            ; if cond == 0, goto else_label

    call parse_stmt         ; then block

    cmp qword [rel tok_type], TOK_ELSE
    jne .if_no_else

    ; Has 'else'
    mov rcx, rsi
    call emit_jmp           ; goto end_label
    mov rcx, rbx
    call emit_label         ; else_label:
    call next_token         ; consume 'else'
    call parse_stmt         ; else block
    mov rcx, rsi
    call emit_label         ; end_label:
    jmp .done

.if_no_else:
    mov rcx, rbx
    call emit_label         ; else_label:
    jmp .done

.stmt_while:
    call next_token         ; consume 'while'
    call gen_new_label
    mov rbx, rax            ; start_label
    call gen_new_label
    mov rsi, rax            ; end_label

    mov rcx, rbx
    mov rdx, rsi
    call push_loop

    mov rcx, rbx
    call emit_label         ; start_label:

    mov rcx, '('
    call expect
    call parse_expr         ; cond
    mov rcx, ')'
    call expect

    mov rcx, rsi
    call emit_jz            ; if cond == 0, goto end_label

    call parse_stmt         ; body

    mov rcx, rbx
    call emit_jmp           ; goto start_label

    mov rcx, rsi
    call emit_label         ; end_label:
    call pop_loop
    jmp .done

.stmt_do:
    call next_token         ; consume 'do'
    call gen_new_label
    mov rbx, rax            ; body_label
    call gen_new_label
    mov rsi, rax            ; cond_label
    call gen_new_label
    mov rdi, rax            ; end_label

    mov rcx, rsi
    mov rdx, rdi
    call push_loop

    mov rcx, rbx
    call emit_label         ; body_label:
    call parse_stmt         ; body

    mov rcx, TOK_WHILE
    call expect
    mov rcx, rsi
    call emit_label         ; cond_label:

    mov rcx, '('
    call expect
    call parse_expr
    mov rcx, ')'
    call expect

    mov rcx, rbx
    call emit_jnz           ; if cond != 0, goto body_label

    mov rcx, rdi
    call emit_label         ; end_label:
    mov rcx, ';'
    call expect
    call pop_loop
    jmp .done

.stmt_for:
    call next_token         ; consume 'for'
    mov rcx, '('
    call expect

    ; Init statement
    cmp qword [rel tok_type], ';'
    je .for_no_init
    call parse_expr
.for_no_init:
    mov rcx, ';'
    call expect

    call gen_new_label
    mov rbx, rax            ; start_label (cond check)
    call gen_new_label
    mov rsi, rax            ; step_label
    call gen_new_label
    mov rdi, rax            ; end_label

    mov rcx, rsi
    mov rdx, rdi
    call push_loop

    mov rcx, rbx
    call emit_label         ; start_label:

    ; Condition
    cmp qword [rel tok_type], ';'
    je .for_no_cond
    call parse_expr
    mov rcx, rdi
    call emit_jz            ; if cond == 0, goto end_label
.for_no_cond:
    mov rcx, ';'
    call expect

    ; Check if step expression exists
    cmp qword [rel tok_type], ')'
    je .for_no_step

    ; Trick: jump over step to body!
    call gen_new_label      ; body_label
    mov [rsp + 32], rax

    mov rcx, rax
    call emit_jmp           ; goto body_label

    mov rcx, rsi
    call emit_label         ; step_label:
    call parse_expr         ; step expression
    mov rcx, rbx
    call emit_jmp           ; goto start_label

    mov rcx, [rsp + 32]
    call emit_label         ; body_label:
    mov rcx, ')'
    call expect
    call parse_stmt         ; body
    mov rcx, rsi
    call emit_jmp           ; goto step_label
    jmp .for_finish

.for_no_step:
    mov rcx, ')'
    call expect
    call parse_stmt
    mov rcx, rbx
    call emit_jmp           ; goto start_label

.for_finish:
    mov rcx, rdi
    call emit_label         ; end_label:
    call pop_loop
    jmp .done

.stmt_switch:
    call next_token         ; consume 'switch'
    mov rcx, '('
    call expect
    call parse_expr         ; switch value in RAX
    mov rcx, ')'
    call expect

    call emit_push_rax      ; push switch value to runtime stack

    call gen_new_label
    mov rbx, rax            ; switch_end_label
    call gen_new_label
    mov rsi, rax            ; switch_dispatch_label

    mov rcx, rsi
    call emit_jmp           ; jump to dispatch

    mov rcx, rbx
    mov rdx, rsi
    call push_switch

    call parse_stmt         ; parse switch body

    mov rcx, rbx
    call emit_jmp           ; jump to switch_end_label

    mov rcx, rsi
    call emit_label         ; dispatch_label:

    mov rax, [rel switch_depth]
    dec rax
    lea r10, [rel switch_case_starts]
    mov r12, [r10 + rax * 8] ; start case index
    mov r13, [rel case_count] ; end case index

.sw_cases_loop:
    cmp r12, r13
    jae .sw_cases_done
    emit_indent
    lea rcx, [rel str_cmp_rsp_val] ; "cmp qword [rsp], "
    call emit_str
    lea r10, [rel case_vals]
    mov rcx, [r10 + r12 * 8]
    call emit_u64
    call emit_nl
    emit_indent
    lea rcx, [rel str_op_je]       ; "je .L"
    call emit_str
    lea r10, [rel case_labels]
    mov rcx, [r10 + r12 * 8]
    call emit_u64
    call emit_nl
    inc r12
    jmp .sw_cases_loop

.sw_cases_done:
    mov rax, [rel switch_depth]
    dec rax
    lea r10, [rel switch_default_labels]
    mov rcx, [r10 + rax * 8]
    test rcx, rcx
    jz .sw_no_default
    call emit_jmp           ; jmp default_label
    jmp .sw_after_dispatch

.sw_no_default:
    mov rcx, rbx
    call emit_jmp           ; jmp switch_end_label

.sw_after_dispatch:
    mov rcx, rbx
    call emit_label         ; switch_end_label:
    call emit_pop_rdx       ; remove switch value from stack

    call pop_switch
    jmp .done

.stmt_case:
    call next_token         ; consume 'case'
    xor rbx, rbx            ; negative flag = 0
    cmp qword [rel tok_type], '-'
    jne .case_pos
    inc rbx
    call next_token
.case_pos:
    mov rax, [rel tok_num]
    test rbx, rbx
    jz .case_not_neg
    neg rax
.case_not_neg:
    mov r12, rax            ; case value
    call next_token
    mov rcx, ':'
    call expect

    call gen_new_label
    mov r13, rax            ; case_label
    mov rcx, r13
    call emit_label

    mov rax, [rel case_count]
    cmp rax, MAX_SWITCH_CASES
    jae .err_too_many_cases
    lea r10, [rel case_vals]
    mov [r10 + rax * 8], r12
    lea r10, [rel case_labels]
    mov [r10 + rax * 8], r13
    inc qword [rel case_count]
    jmp .done

.err_too_many_cases:
    lea rcx, [rel str_err_too_many_cases]
    jmp compile_error

.stmt_default:
    call next_token         ; consume 'default'
    mov rcx, ':'
    call expect

    call gen_new_label
    mov r13, rax            ; default_label
    mov rcx, r13
    call emit_label

    mov rax, [rel switch_depth]
    test rax, rax
    jz .done
    dec rax
    lea r10, [rel switch_default_labels]
    mov [r10 + rax * 8], r13
    jmp .done

.stmt_return:
    call next_token         ; consume 'return'
    cmp qword [rel tok_type], ';'
    je .ret_no_val
    call parse_expr         ; result in RAX
.ret_no_val:
    mov rcx, ';'
    call expect
    ; Jump to function epilogue
    mov rcx, [rel cur_func_ret_label]
    call emit_jmp
    jmp .done

.stmt_break:
    call next_token         ; consume 'break'
    mov rcx, ';'
    call expect
    mov rax, [rel break_stack_depth]
    test rax, rax
    jz .err_brk
    dec rax
    lea r10, [rel break_stack_labels]
    mov rcx, [r10 + rax * 8]
    call emit_jmp
    jmp .done
.err_brk:
    lea rcx, [rel str_err_break_outside]
    jmp compile_error

.stmt_continue:
    call next_token         ; consume 'continue'
    mov rcx, ';'
    call expect
    cmp qword [rel loop_depth], 0
    jz .err_cont
    mov rax, [rel loop_depth]
    dec rax
    lea r10, [rel loop_cont_labels]
    mov rcx, [r10 + rax * 8]
    call emit_jmp
    jmp .done
.err_cont:
    lea rcx, [rel str_err_continue_outside]
    jmp compile_error

.stmt_compound:
    call next_token         ; consume '{'
.comp_loop:
    cmp qword [rel tok_type], '}'
    je .comp_done
    cmp qword [rel tok_type], TOK_EOF
    je .comp_done

    ; Check if declaration inside block
    mov rax, [rel tok_type]
    cmp rax, TOK_INT
    je .comp_decl
    cmp rax, TOK_LONG
    je .comp_decl
    cmp rax, TOK_CHAR
    je .comp_decl
    cmp rax, TOK_VOID
    je .comp_decl
    cmp rax, TOK_STRUCT
    je .comp_decl
    cmp rax, TOK_STATIC
    je .comp_decl
    cmp rax, TOK_CONST
    je .comp_decl
    cmp rax, TOK_UNSIGNED
    je .comp_decl
    cmp rax, TOK_SIGNED
    je .comp_decl

    call parse_stmt
    jmp .comp_loop

.comp_decl:
    call parse_local_decl
    jmp .comp_loop

.comp_done:
    mov rcx, '}'
    call expect

.done:
    add rsp, 48
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_local_decl: Parse local variable declaration inside a function
; Example: int a = 1, b[10], *c;
; ------------------------------------------------------------------------------
parse_local_decl:
    push rbx
    push rsi
    push rdi
    sub rsp, 48

    call parse_type         ; base type in type_tmp
    lea rdi, [rsp]
    lea rdx, [rel type_tmp]
    mov rcx, rdi
    mov r8, TYPE_DESC_SIZE
    call mem_copy

.item_loop:
    ; Pointer stars
    xor ebx, ebx
.star_loop:
    cmp qword [rel tok_type], '*'
    jne .got_stars
    inc rbx
    call next_token
    jmp .star_loop
.got_stars:
    mov rax, [rel type_tmp + 8]
    add rax, rbx
    mov [rdi + 8], rax      ; set ptr_level

    ; Name
    cmp qword [rel tok_type], TOK_IDENT
    jne .err_ident
    lea rcx, [rel ident_tmp]
    lea rdx, [rel tok_str]
    call str_copy
    call next_token

    ; Check if array [N]
    mov qword [rdi + 16], 0 ; is_array = 0
    cmp qword [rel tok_type], '['
    jne .no_array
    call next_token
    mov rax, [rel tok_num]
    mov [rdi + 24], rax     ; array_len
    mov qword [rdi + 16], 1 ; is_array = 1
    call next_token
    mov rcx, ']'
    call expect

.no_array:
    ; Recompute size
    mov rcx, rdi
    call compute_type_size

    ; Add to local symbol table
    lea rcx, [rel ident_tmp]
    mov rdx, rdi
    call local_add
    mov rsi, rax            ; LOCAL_ENTRY pointer

    ; Initializer?
    cmp qword [rel tok_type], '='
    jne .next_item
    call next_token         ; consume '='
    ; Target address
    mov rcx, [rsi + 64 + 48]
    call emit_load_local_addr
    call emit_push_rax
    call parse_assign_expr  ; RHS in RAX
    call emit_pop_rdx
    mov rcx, [rdi + 40]     ; size
    call emit_store

.next_item:
    cmp qword [rel tok_type], ','
    jne .decl_done
    call next_token
    jmp .item_loop

.decl_done:
    mov rcx, ';'
    call expect

    add rsp, 48
    pop rdi
    pop rsi
    pop rbx
    ret

.err_ident:
    lea rcx, [rel str_err_expected_ident]
    jmp compile_error

; ------------------------------------------------------------------------------
; parse_global_decl_or_func: Top-level declarations and function definitions
; ------------------------------------------------------------------------------
parse_global_decl_or_func:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    sub rsp, 72

    ; Check if 'extern'
    xor r14d, r14d
    cmp qword [rel tok_type], TOK_EXTERN
    jne .not_extern
    mov r14d, 1
    call next_token

.not_extern:
.glob_qual_loop:
    cmp qword [rel tok_type], TOK_STATIC
    je .skip_glob_qual
    cmp qword [rel tok_type], TOK_CONST
    je .skip_glob_qual
    jmp .chk_glob_struct
.skip_glob_qual:
    call next_token
    jmp .glob_qual_loop

.chk_glob_struct:
    ; Check if struct definition: struct Point { int x; int y; };
    cmp qword [rel tok_type], TOK_STRUCT
    jne .norm_decl
    mov rcx, 1
    call peek_char_at
    ; Check struct definition
    call parse_struct_def_if_any
    test eax, eax
    jnz .ret                ; struct was defined and semicolon consumed

.norm_decl:
    call parse_type         ; base type in type_tmp
    lea rdi, [rsp]
    lea rdx, [rel type_tmp]
    mov rcx, rdi
    mov r8, TYPE_DESC_SIZE
    call mem_copy

    ; Check for identifier name
    cmp qword [rel tok_type], TOK_IDENT
    jne .ret

    lea rcx, [rel ident_tmp]
    lea rdx, [rel tok_str]
    call str_copy
    call next_token

    ; Is it a function or global variable?
    cmp qword [rel tok_type], '('
    je .is_function

    ; Global variable:
    ; Optional array
    mov qword [rdi + 16], 0
    cmp qword [rel tok_type], '['
    jne .glob_no_arr
    call next_token
    mov rax, [rel tok_num]
    mov [rdi + 24], rax
    mov qword [rdi + 16], 1
    call next_token
    mov rcx, ']'
    call expect

.glob_no_arr:
    mov rcx, rdi
    call compute_type_size

    ; Initializer?
    xor r8, r8             ; init_val = 0
    cmp qword [rel tok_type], '='
    jne .add_glob
    call next_token
    ; Handle string literal initializer or number
    cmp qword [rel tok_type], TOK_STR
    je .glob_str_init
    mov r8, [rel tok_num]
    call next_token
    jmp .add_glob

.glob_str_init:
    lea rcx, [rel tok_str]
    mov rdx, [rel tok_len]
    call string_pool_add
    ; Store string label ID
    mov r8, rax
    call next_token

.add_glob:
    lea rcx, [rel ident_tmp]
    mov rdx, rdi
    mov r9, 1               ; is_defined = 1
    call global_add

    mov rcx, ';'
    call expect
    jmp .ret

.is_function:
    ; Function declaration or definition!
    call next_token         ; consume '('
    call local_scope_enter  ; prepare local scope

    ; Save function name
    lea rcx, [rel cur_func_name]
    lea rdx, [rel ident_tmp]
    call str_copy

    ; Allocate unique return label ID
    call gen_new_label
    mov [rel cur_func_ret_label], rax
    mov rax, [rel func_counter]
    mov [rel cur_func_id], rax
    inc qword [rel func_counter]

    ; Parse parameters: (int a, char* b, ...)
    xor r12, r12            ; param count = 0
    cmp qword [rel tok_type], ')'
    je .params_done

.param_loop:
    call parse_type         ; parameter type
    cmp qword [rel tok_type], TOK_IDENT
    jne .param_no_name
    ; Add parameter to local symbol table
    lea rcx, [rel tok_str]
    lea rdx, [rel type_tmp]
    call local_add
    inc r12
    call next_token
    jmp .param_next
.param_no_name:
    inc r12
.param_next:
    cmp qword [rel tok_type], ','
    jne .params_done
    call next_token
    jmp .param_loop

.params_done:
    mov rcx, ')'
    call expect

    ; Check if prototype or definition
    cmp qword [rel tok_type], ';'
    je .func_decl_only

    ; Function definition!
    ; Record defined function name
    mov rax, [rel defined_func_count]
    cmp rax, 256
    jae .func_table_full
    imul rax, 64
    lea r10, [rel defined_func_table]
    lea rcx, [r10 + rax]
    lea rdx, [rel cur_func_name]
    call str_copy
    inc qword [rel defined_func_count]
.func_table_full:

    ; Emit prologue
    lea rcx, [rel cur_func_name]
    call emit_func_prologue

    ; Emit stack allocation with forward equ label:
    ; "sub rsp, .L_STK_{func_id}"
    emit_indent
    lea rcx, [rel str_sub_rsp_lbl]      ; "sub rsp, .L_STK_"
    call emit_str
    mov rcx, [rel cur_func_id]
    call emit_u64
    call emit_nl

    ; Spill incoming register arguments to their local variable stack slots (SysV ABI)
    ; Param 1 -> RDI -> [rbp - local_table[0].stack_offset]
    ; Param 2 -> RSI -> [rbp - local_table[1].stack_offset]
    ; Param 3 -> RDX -> [rbp - local_table[2].stack_offset]
    ; Param 4 -> RCX -> [rbp - local_table[3].stack_offset]
    ; Param 5 -> R8  -> [rbp - local_table[4].stack_offset]
    ; Param 6 -> R9  -> [rbp - local_table[5].stack_offset]
    lea r10, [rel local_table]
    cmp r12, 1
    jb .spill_done
    ; Param 1 (RDI)
    mov r8, [r10 + 0 * LOCAL_ENTRY_SIZE + 64 + 48]
    emit_indent
    lea rcx, [rel str_spill_start]
    call emit_str
    mov rcx, r8
    call emit_u64
    lea rcx, [rel str_spill_end_rdi]
    call emit_str

    cmp r12, 2
    jb .spill_done
    ; Param 2 (RSI)
    mov r8, [r10 + 1 * LOCAL_ENTRY_SIZE + 64 + 48]
    emit_indent
    lea rcx, [rel str_spill_start]
    call emit_str
    mov rcx, r8
    call emit_u64
    lea rcx, [rel str_spill_end_rsi]
    call emit_str

    cmp r12, 3
    jb .spill_done
    ; Param 3 (RDX)
    mov r8, [r10 + 2 * LOCAL_ENTRY_SIZE + 64 + 48]
    emit_indent
    lea rcx, [rel str_spill_start]
    call emit_str
    mov rcx, r8
    call emit_u64
    lea rcx, [rel str_spill_end_rdx]
    call emit_str

    cmp r12, 4
    jb .spill_done
    ; Param 4 (RCX)
    mov r8, [r10 + 3 * LOCAL_ENTRY_SIZE + 64 + 48]
    emit_indent
    lea rcx, [rel str_spill_start]
    call emit_str
    mov rcx, r8
    call emit_u64
    lea rcx, [rel str_spill_end_rcx]
    call emit_str

    cmp r12, 5
    jb .spill_done
    ; Param 5 (R8)
    mov r8, [r10 + 4 * LOCAL_ENTRY_SIZE + 64 + 48]
    emit_indent
    lea rcx, [rel str_spill_start]
    call emit_str
    mov rcx, r8
    call emit_u64
    lea rcx, [rel str_spill_end_r8]
    call emit_str

    cmp r12, 6
    jb .spill_done
    ; Param 6 (R9)
    mov r8, [r10 + 5 * LOCAL_ENTRY_SIZE + 64 + 48]
    emit_indent
    lea rcx, [rel str_spill_start]
    call emit_str
    mov rcx, r8
    call emit_u64
    lea rcx, [rel str_spill_end_r9]
    call emit_str
.spill_done:
    ; Parse function body compound statement
    call parse_stmt

    ; Emit epilogue
    mov rcx, [rel cur_func_ret_label]
    call emit_func_epilogue

    ; Emit equ for stack size:
    ; ".L_STK_{func_id} equ {aligned_stack_offset}"
    lea rcx, [rel str_stk_equ_lbl]      ; ".L_STK_"
    call emit_str
    mov rcx, [rel cur_func_id]
    call emit_u64
    lea rcx, [rel str_equ_space]        ; " equ "
    call emit_str
    ; Align stack offset to 16 bytes, minimum 32
    mov rax, [rel cur_stack_offset]
    add rax, 15
    and rax, -16
    cmp rax, 32
    jae .has_min_stk
    mov rax, 32
.has_min_stk:
    mov rcx, rax
    call emit_u64
    call emit_nl

    call local_scope_exit
    jmp .ret

.func_decl_only:
    call next_token         ; consume ';'
    call local_scope_exit

.ret:
    add rsp, 72
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; parse_struct_def_if_any: Parse struct definition if next token is '{'
; Output: EAX = 1 if handled, 0 if not a struct definition
; ------------------------------------------------------------------------------
parse_struct_def_if_any:
    push rbx
    push rsi
    push rdi
    sub rsp, 48

    ; Current token is TOK_STRUCT
    call next_token         ; consume 'struct'
    cmp qword [rel tok_type], TOK_IDENT
    jne .not_def

    lea rcx, [rel struct_tmp_name]
    lea rdx, [rel tok_str]
    call str_copy
    call next_token

    cmp qword [rel tok_type], '{'
    jne .not_def_semi

    ; Struct definition!
    call next_token         ; consume '{'
    lea rcx, [rel struct_tmp_name]
    call struct_add
    mov rbx, rax            ; struct_id

.member_loop:
    cmp qword [rel tok_type], '}'
    je .members_end
    cmp qword [rel tok_type], TOK_EOF
    je .members_end

    call parse_type         ; member type
    cmp qword [rel tok_type], TOK_IDENT
    jne .err_m_ident

    lea rcx, [rel ident_tmp]
    lea rdx, [rel tok_str]
    call str_copy
    call next_token

    ; Optional array
    cmp qword [rel tok_type], '['
    jne .m_no_arr
    call next_token
    mov rax, [rel tok_num]
    mov [rel type_tmp + 24], rax
    mov qword [rel type_tmp + 16], 1
    call next_token
    mov rcx, ']'
    call expect

.m_no_arr:
    lea rcx, [rel type_tmp]
    call compute_type_size

    ; Add member
    mov rcx, rbx            ; struct_id
    lea rdx, [rel ident_tmp]
    lea r8, [rel type_tmp]
    call struct_add_member

    mov rcx, ';'
    call expect
    jmp .member_loop

.members_end:
    mov rcx, '}'
    call expect
    mov rcx, ';'
    call expect
    mov eax, 1
    jmp .ret

.not_def_semi:
    ; Just struct tag used as a type, handled in norm_decl
    xor eax, eax
    jmp .ret

.not_def:
    xor eax, eax
.ret:
    add rsp, 48
    pop rdi
    pop rsi
    pop rbx
    ret

.err_m_ident:
    lea rcx, [rel str_err_expected_ident]
    jmp compile_error
