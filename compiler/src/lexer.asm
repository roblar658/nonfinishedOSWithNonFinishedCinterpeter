; ==============================================================================
; c_compiler_asm - Pure x86-64 Assembly C Compiler
; lexer.asm - Lexical analyzer (tokenizer) and preprocessor handling
; ==============================================================================

section .text

; ------------------------------------------------------------------------------
; peek_char: Peek at current character in source buffer
; Output: AL = character, or 0 if EOF
; ------------------------------------------------------------------------------
peek_char:
    mov rdx, [rel src_ptr]
    cmp rdx, [rel src_end]
    jae .eof
    mov al, [rdx]
    ret
.eof:
    xor eax, eax
    ret

; ------------------------------------------------------------------------------
; peek_char_at: Peek at char at src_ptr + RCX
; Output: AL = character, or 0 if EOF
; ------------------------------------------------------------------------------
peek_char_at:
    mov rdx, [rel src_ptr]
    add rdx, rcx
    cmp rdx, [rel src_end]
    jae .eof
    mov al, [rdx]
    ret
.eof:
    xor eax, eax
    ret

; ------------------------------------------------------------------------------
; next_char: Consume and return current character
; Output: AL = character
; Updates: src_ptr, cur_line, cur_col
; ------------------------------------------------------------------------------
next_char:
    mov rdx, [rel src_ptr]
    cmp rdx, [rel src_end]
    jae .eof
    mov al, [rdx]
    inc qword [rel src_ptr]
    cmp al, 10              ; newline?
    je .newline
    inc qword [rel cur_col]
    ret
.newline:
    inc qword [rel cur_line]
    mov qword [rel cur_col], 1
    ret
.eof:
    xor eax, eax
    ret

; ------------------------------------------------------------------------------
; skip_whitespace_and_comments:
; Skips spaces, tabs, newlines, // comments, /* */ comments, and # preprocessor lines
; ------------------------------------------------------------------------------
skip_whitespace_and_comments:
.loop:
    call peek_char
    test al, al
    jz .done

    ; Whitespace?
    call is_space
    test eax, eax
    jz .check_slash
    call next_char
    jmp .loop

.check_slash:
    call peek_char
    cmp al, '/'
    jne .check_hash
    mov rcx, 1
    call peek_char_at
    cmp al, '/'
    je .line_comment
    cmp al, '*'
    je .block_comment
    jmp .check_hash

.line_comment:
    call next_char  ; skip first '/'
    call next_char  ; skip second '/'
.line_comm_loop:
    call peek_char
    test al, al
    jz .done
    cmp al, 10
    je .line_comm_done
    call next_char
    jmp .line_comm_loop
.line_comm_done:
    call next_char  ; consume newline
    jmp .loop

.block_comment:
    call next_char  ; skip '/'
    call next_char  ; skip '*'
.block_comm_loop:
    call peek_char
    test al, al
    jz .unclosed_comment
    cmp al, '*'
    jne .block_comm_next
    mov rcx, 1
    call peek_char_at
    cmp al, '/'
    je .block_comm_end
.block_comm_next:
    call next_char
    jmp .block_comm_loop
.block_comm_end:
    call next_char  ; skip '*'
    call next_char  ; skip '/'
    jmp .loop

.unclosed_comment:
    lea rcx, [rel str_err_unclosed_comment]
    jmp compile_error

.check_hash:
    ; Preprocessor line starts with '#'
    call peek_char
    cmp al, '#'
    jne .done
    ; Process preprocessor directive
    call handle_preprocessor
    jmp .loop

.done:
    ret

; ------------------------------------------------------------------------------
; handle_preprocessor: Handle lines starting with '#'
; Supports: #include (skip), #define IDENT VALUE (store in macro table)
; ------------------------------------------------------------------------------
handle_preprocessor:
    push rbx
    push rsi
    push rdi
    call next_char          ; consume '#'
    ; skip any spaces after '#'
.skip_s1:
    call peek_char
    cmp al, ' '
    je .c_s1
    cmp al, 9
    jne .check_dir
.c_s1:
    call next_char
    jmp .skip_s1

.check_dir:
    ; Read directive name into tok_str
    lea rdi, [rel tok_str]
    xor ebx, ebx
.read_dir:
    call peek_char
    call is_alpha
    test eax, eax
    jz .read_dir_done
    call next_char
    mov [rdi + rbx], al
    inc rbx
    cmp rbx, MAX_IDENT_LEN - 1
    jb .read_dir
.read_dir_done:
    mov byte [rdi + rbx], 0

    ; Check if directive is "define"
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_define]
    call str_cmp
    test eax, eax
    jz .do_define

    ; Otherwise skip entire rest of line until \n or EOF
.skip_line:
    call peek_char
    test al, al
    jz .pp_done
    cmp al, 10
    je .pp_nl
    call next_char
    jmp .skip_line
.pp_nl:
    call next_char
.pp_done:
    pop rdi
    pop rsi
    pop rbx
    ret

.do_define:
    ; Skip spaces
.skip_def_s:
    call peek_char
    cmp al, ' '
    je .c_ds
    cmp al, 9
    jne .def_ident
.c_ds:
    call next_char
    jmp .skip_def_s

.def_ident:
    ; Read macro name
    lea rdi, [rel macro_tmp_name]
    xor ebx, ebx
.read_mi:
    call peek_char
    call is_alnum
    test eax, eax
    jz .read_mi_done
    call next_char
    mov [rdi + rbx], al
    inc rbx
    cmp rbx, MAX_IDENT_LEN - 1
    jb .read_mi
.read_mi_done:
    mov byte [rdi + rbx], 0

    ; Skip spaces before value
.skip_val_s:
    call peek_char
    cmp al, ' '
    je .c_vs
    cmp al, 9
    jne .def_val
.c_vs:
    call next_char
    jmp .skip_val_s

.def_val:
    ; Read integer value or 0 if none
    call peek_char
    cmp al, 10
    je .def_no_val
    test al, al
    jz .def_no_val

    ; Check if hex or dec number
    xor rsi, rsi
    call peek_char
    cmp al, '0'
    jne .parse_dec_macro
    mov rcx, 1
    call peek_char_at
    cmp al, 'x'
    je .parse_hex_macro
    cmp al, 'X'
    je .parse_hex_macro

.parse_dec_macro:
    xor rsi, rsi
.p_dec_loop:
    call peek_char
    call is_digit
    test eax, eax
    jz .store_macro
    call next_char
    sub al, '0'
    movzx rax, al
    imul rsi, 10
    add rsi, rax
    jmp .p_dec_loop

.parse_hex_macro:
    call next_char  ; '0'
    call next_char  ; 'x'
    xor rsi, rsi
.p_hex_loop:
    call peek_char
    cmp al, '0'
    jb .store_macro
    cmp al, '9'
    jbe .h_digit
    cmp al, 'a'
    jb .h_check_upper
    cmp al, 'f'
    jbe .h_lower
.h_check_upper:
    cmp al, 'A'
    jb .store_macro
    cmp al, 'F'
    ja .store_macro
    sub al, 'A'
    add al, 10
    jmp .h_add
.h_lower:
    sub al, 'a'
    add al, 10
    jmp .h_add
.h_digit:
    sub al, '0'
.h_add:
    movzx rax, al
    shl rsi, 4
    add rsi, rax
    call next_char
    jmp .p_hex_loop

.def_no_val:
    mov rsi, 1      ; default macro value is 1

.store_macro:
    ; Store in macro table
    mov rax, [rel macro_count]
    cmp rax, 64
    jae .skip_line
    ; Each macro entry: name (64 bytes), val (8 bytes) = 72 bytes
    imul rax, 72
    lea r10, [rel macro_table]
    lea rcx, [r10 + rax]
    lea rdx, [rel macro_tmp_name]
    push r10
    push rax
    call str_copy
    pop rax
    pop r10
    mov [r10 + rax + 64], rsi
    inc qword [rel macro_count]
    jmp .skip_line

; ------------------------------------------------------------------------------
; next_token: Read the next token from source into tok_type, tok_num, tok_str
; ------------------------------------------------------------------------------
next_token:
    push rbx
    push rsi
    push rdi
    sub rsp, 32

    call skip_whitespace_and_comments

    ; Record token start position
    mov rax, [rel cur_line]
    mov [rel tok_line], rax
    mov rax, [rel cur_col]
    mov [rel tok_col], rax

    call peek_char
    test al, al
    jnz .check_ident
    mov qword [rel tok_type], TOK_EOF
    jmp .ret

.check_ident:
    call is_alpha
    test eax, eax
    jz .check_num
    call lex_ident_or_keyword
    jmp .ret

.check_num:
    call peek_char
    call is_digit
    test eax, eax
    jz .check_str
    call lex_number
    jmp .ret

.check_str:
    call peek_char
    cmp al, '"'
    jne .check_char_lit
    call lex_string
    jmp .ret

.check_char_lit:
    cmp al, "'"
    jne .check_operators
    call lex_char_literal
    jmp .ret

.check_operators:
    call lex_operator

.ret:
    add rsp, 32
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; lex_ident_or_keyword: Read identifier and classify
; ------------------------------------------------------------------------------
lex_ident_or_keyword:
    lea rdi, [rel tok_str]
    xor ebx, ebx
.loop:
    call peek_char
    call is_alnum
    test eax, eax
    jz .done
    call next_char
    mov [rdi + rbx], al
    inc rbx
    cmp rbx, MAX_IDENT_LEN - 1
    jb .loop
.loop_drain:
    call peek_char
    call is_alnum
    test eax, eax
    jz .done
    call next_char
    jmp .loop_drain
.done:
    mov byte [rdi + rbx], 0
    mov [rel tok_len], rbx

    ; Check if it matches a defined macro
    xor r8, r8
.macro_loop:
    cmp r8, [rel macro_count]
    jae .check_keywords
    mov rax, r8
    imul rax, 72
    lea r10, [rel macro_table]
    lea rcx, [r10 + rax]
    lea rdx, [rel tok_str]
    push r8
    call str_cmp
    pop r8
    test eax, eax
    jz .found_macro
    inc r8
    jmp .macro_loop

.found_macro:
    mov rax, r8
    imul rax, 72
    lea r10, [rel macro_table]
    mov rax, [r10 + rax + 64]
    mov [rel tok_num], rax
    mov qword [rel tok_type], TOK_NUM
    ret

.check_keywords:
    ; Match against C keywords
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_int]
    call str_cmp
    test eax, eax
    jnz .k1
    mov qword [rel tok_type], TOK_INT
    ret
.k1:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_char]
    call str_cmp
    test eax, eax
    jnz .k2
    mov qword [rel tok_type], TOK_CHAR
    ret
.k2:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_void]
    call str_cmp
    test eax, eax
    jnz .k3
    mov qword [rel tok_type], TOK_VOID
    ret
.k3:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_struct]
    call str_cmp
    test eax, eax
    jnz .k4
    mov qword [rel tok_type], TOK_STRUCT
    ret
.k4:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_if]
    call str_cmp
    test eax, eax
    jnz .k5
    mov qword [rel tok_type], TOK_IF
    ret
.k5:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_else]
    call str_cmp
    test eax, eax
    jnz .k6
    mov qword [rel tok_type], TOK_ELSE
    ret
.k6:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_while]
    call str_cmp
    test eax, eax
    jnz .k7
    mov qword [rel tok_type], TOK_WHILE
    ret
.k7:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_for]
    call str_cmp
    test eax, eax
    jnz .k8
    mov qword [rel tok_type], TOK_FOR
    ret
.k8:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_do]
    call str_cmp
    test eax, eax
    jnz .k9
    mov qword [rel tok_type], TOK_DO
    ret
.k9:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_return]
    call str_cmp
    test eax, eax
    jnz .k10
    mov qword [rel tok_type], TOK_RETURN
    ret
.k10:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_sizeof]
    call str_cmp
    test eax, eax
    jnz .k11
    mov qword [rel tok_type], TOK_SIZEOF
    ret
.k11:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_break]
    call str_cmp
    test eax, eax
    jnz .k12
    mov qword [rel tok_type], TOK_BREAK
    ret
.k12:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_continue]
    call str_cmp
    test eax, eax
    jnz .k13
    mov qword [rel tok_type], TOK_CONTINUE
    ret
.k13:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_switch]
    call str_cmp
    test eax, eax
    jnz .k14
    mov qword [rel tok_type], TOK_SWITCH
    ret
.k14:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_case]
    call str_cmp
    test eax, eax
    jnz .k15
    mov qword [rel tok_type], TOK_CASE
    ret
.k15:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_default]
    call str_cmp
    test eax, eax
    jnz .k16
    mov qword [rel tok_type], TOK_DEFAULT
    ret
.k16:
    lea rcx, [rel tok_str]
    lea rdx, [rel kw_extern]
    call str_cmp
    test eax, eax
    jnz .not_kw
    mov qword [rel tok_type], TOK_EXTERN
    ret
.not_kw:
    mov qword [rel tok_type], TOK_IDENT
    ret

; ------------------------------------------------------------------------------
; lex_number: Parse decimal or hexadecimal integer
; ------------------------------------------------------------------------------
lex_number:
    call peek_char
    cmp al, '0'
    jne .parse_dec
    mov rcx, 1
    call peek_char_at
    cmp al, 'x'
    je .parse_hex
    cmp al, 'X'
    je .parse_hex

.parse_dec:
    xor rsi, rsi
.dec_loop:
    call peek_char
    call is_digit
    test eax, eax
    jz .num_done
    call next_char
    sub al, '0'
    movzx rax, al
    imul rsi, 10
    add rsi, rax
    jmp .dec_loop

.parse_hex:
    call next_char  ; '0'
    call next_char  ; 'x'
    xor rsi, rsi
.hex_loop:
    call peek_char
    cmp al, '0'
    jb .num_done
    cmp al, '9'
    jbe .h_dig
    cmp al, 'a'
    jb .h_upper
    cmp al, 'f'
    jbe .h_low
.h_upper:
    cmp al, 'A'
    jb .num_done
    cmp al, 'F'
    ja .num_done
    sub al, 'A'
    add al, 10
    jmp .h_val
.h_low:
    sub al, 'a'
    add al, 10
    jmp .h_val
.h_dig:
    sub al, '0'
.h_val:
    movzx rax, al
    shl rsi, 4
    add rsi, rax
    call next_char
    jmp .hex_loop

.num_done:
    ; Skip integer suffixes like U, L, LL
.skip_suffix:
    call peek_char
    cmp al, 'u'
    je .c_suf
    cmp al, 'U'
    je .c_suf
    cmp al, 'l'
    je .c_suf
    cmp al, 'L'
    jne .finish_num
.c_suf:
    call next_char
    jmp .skip_suffix

.finish_num:
    mov [rel tok_num], rsi
    mov qword [rel tok_type], TOK_NUM
    ret

; ------------------------------------------------------------------------------
; parse_escape_char: Decode escape sequence after '\'
; Output: AL = decoded character
; ------------------------------------------------------------------------------
parse_escape_char:
    call next_char  ; consume char after '\'
    cmp al, 'n'
    je .ret_nl
    cmp al, 't'
    je .ret_tab
    cmp al, 'r'
    je .ret_cr
    cmp al, '0'
    je .ret_null
    cmp al, '\'
    je .ret_same
    cmp al, '"'
    je .ret_same
    cmp al, "'"
    je .ret_same
    ret
.ret_nl:
    mov al, 10
    ret
.ret_tab:
    mov al, 9
    ret
.ret_cr:
    mov al, 13
    ret
.ret_null:
    xor al, al
    ret
.ret_same:
    ret

; ------------------------------------------------------------------------------
; lex_string: Parse string literal "..."
; ------------------------------------------------------------------------------
lex_string:
    call next_char          ; consume opening '"'
    lea rdi, [rel tok_str]
    xor ebx, ebx
.loop:
    call peek_char
    test al, al
    jz .unclosed
    cmp al, '"'
    je .done
    cmp al, '\'
    jne .regular
    call next_char          ; consume '\'
    call parse_escape_char
    jmp .append
.regular:
    call next_char
.append:
    cmp ebx, MAX_STR_LEN - 1
    jae .overflow
    mov [rdi + rbx], al
    inc rbx
    jmp .loop
.done:
    call next_char          ; consume closing '"'
    mov byte [rdi + rbx], 0
    mov [rel tok_len], rbx
    mov qword [rel tok_type], TOK_STR
    ret
.unclosed:
    lea rcx, [rel str_err_unclosed_str]
    jmp compile_error
.overflow:
    lea rcx, [rel str_err_str_overflow]
    jmp compile_error

; ------------------------------------------------------------------------------
; lex_char_literal: Parse character literal 'c' or '\n'
; ------------------------------------------------------------------------------
lex_char_literal:
    call next_char          ; consume opening "'"
    call peek_char
    test al, al
    jz .err
    cmp al, '\'
    jne .norm
    call next_char          ; consume '\'
    call parse_escape_char
    jmp .got_char
.norm:
    call next_char
.got_char:
    movzx rsi, al
    call peek_char
    cmp al, "'"
    jne .err
    call next_char          ; consume closing "'"
    mov [rel tok_num], rsi
    mov qword [rel tok_type], TOK_CHAR_LIT
    ret
.err:
    lea rcx, [rel str_err_char_lit]
    jmp compile_error

; ------------------------------------------------------------------------------
; lex_operator: Parse single and multi-character operators
; ------------------------------------------------------------------------------
lex_operator:
    call next_char          ; consume first operator char
    mov bl, al
    movzx rax, al
    mov qword [rel tok_type], rax

    ; Check 2-character combinations
    cmp bl, '='
    jne .op_plus
    call peek_char
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_EQ
    ret

.op_plus:
    cmp bl, '+'
    jne .op_minus
    call peek_char
    cmp al, '+'
    jne .op_plus_eq
    call next_char
    mov qword [rel tok_type], TOK_INC
    ret
.op_plus_eq:
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_ADD_ASSIGN
    ret

.op_minus:
    cmp bl, '-'
    jne .op_star
    call peek_char
    cmp al, '-'
    jne .op_minus_arrow
    call next_char
    mov qword [rel tok_type], TOK_DEC
    ret
.op_minus_arrow:
    cmp al, '>'
    jne .op_minus_eq
    call next_char
    mov qword [rel tok_type], TOK_ARROW
    ret
.op_minus_eq:
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_SUB_ASSIGN
    ret

.op_star:
    cmp bl, '*'
    jne .op_slash
    call peek_char
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_MUL_ASSIGN
    ret

.op_slash:
    cmp bl, '/'
    jne .op_percent
    call peek_char
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_DIV_ASSIGN
    ret

.op_percent:
    cmp bl, '%'
    jne .op_amp
    call peek_char
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_MOD_ASSIGN
    ret

.op_amp:
    cmp bl, '&'
    jne .op_pipe
    call peek_char
    cmp al, '&'
    jne .op_amp_eq
    call next_char
    mov qword [rel tok_type], TOK_LOGAND
    ret
.op_amp_eq:
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_AND_ASSIGN
    ret

.op_pipe:
    cmp bl, '|'
    jne .op_caret
    call peek_char
    cmp al, '|'
    jne .op_pipe_eq
    call next_char
    mov qword [rel tok_type], TOK_LOGOR
    ret
.op_pipe_eq:
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_OR_ASSIGN
    ret

.op_caret:
    cmp bl, '^'
    jne .op_bang
    call peek_char
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_XOR_ASSIGN
    ret

.op_bang:
    cmp bl, '!'
    jne .op_less
    call peek_char
    cmp al, '='
    jne .done
    call next_char
    mov qword [rel tok_type], TOK_NE
    ret

.op_less:
    cmp bl, '<'
    jne .op_greater
    call peek_char
    cmp al, '='
    jne .op_shl
    call next_char
    mov qword [rel tok_type], TOK_LE
    ret
.op_shl:
    cmp al, '<'
    jne .done
    call next_char
    call peek_char
    cmp al, '='
    jne .ret_shl
    call next_char
    mov qword [rel tok_type], TOK_SHL_ASSIGN
    ret
.ret_shl:
    mov qword [rel tok_type], TOK_SHL
    ret

.op_greater:
    cmp bl, '>'
    jne .done
    call peek_char
    cmp al, '='
    jne .op_shr
    call next_char
    mov qword [rel tok_type], TOK_GE
    ret
.op_shr:
    cmp al, '>'
    jne .done
    call next_char
    call peek_char
    cmp al, '='
    jne .ret_shr
    call next_char
    mov qword [rel tok_type], TOK_SHR_ASSIGN
    ret
.ret_shr:
    mov qword [rel tok_type], TOK_SHR
    ret

.done:
    ret
