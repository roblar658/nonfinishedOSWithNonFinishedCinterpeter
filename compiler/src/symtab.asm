; ==============================================================================
; c_compiler_asm - Pure x86-64 Assembly C Compiler
; symtab.asm - Global and local symbol tables, string pool, extern functions
; ==============================================================================

section .text

; ------------------------------------------------------------------------------
; global_lookup: Search for global symbol by name
; Input:  RCX = symbol name pointer
; Output: RAX = pointer to GLOBAL_ENTRY or 0 if not found
; ------------------------------------------------------------------------------
global_lookup:
    push rbx
    push rsi
    sub rsp, 40
    mov rsi, rcx
    xor ebx, ebx
.loop:
    cmp rbx, [rel global_count]
    jae .not_found
    mov rax, rbx
    imul rax, GLOBAL_ENTRY_SIZE
    lea r10, [rel global_table]
    lea rcx, [r10 + rax]
    mov rdx, rsi
    call str_cmp
    test eax, eax
    jz .found
    inc rbx
    jmp .loop
.found:
    mov rax, rbx
    imul rax, GLOBAL_ENTRY_SIZE
    lea r10, [rel global_table]
    lea rax, [r10 + rax]
    jmp .ret
.not_found:
    xor eax, eax
.ret:
    add rsp, 40
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; global_add: Add a global symbol
; Input:  RCX = symbol name
;         RDX = pointer to TYPE_DESC
;         R8  = init_val (integer)
;         R9  = is_defined
; Output: RAX = pointer to created GLOBAL_ENTRY
; ------------------------------------------------------------------------------
global_add:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    sub rsp, 56

    mov rsi, rcx            ; name
    mov r12, rdx            ; type_desc
    mov r13, r8             ; init_val
    mov r14, r9             ; is_defined

    mov rbx, [rel global_count]
    cmp rbx, MAX_GLOBALS
    jae .overflow

    imul rax, rbx, GLOBAL_ENTRY_SIZE
    lea rdi, [rel global_table]
    add rdi, rax

    ; Copy name
    mov rcx, rdi
    mov rdx, rsi
    call str_copy

    ; Copy type_desc
    lea rcx, [rdi + 64]
    mov rdx, r12
    mov r8, TYPE_DESC_SIZE
    call mem_copy

    ; Set init_val, is_defined, str_label = -1
    mov [rdi + 64 + 48], r13        ; init_val
    mov [rdi + 64 + 48 + 8], r14    ; is_defined
    mov qword [rdi + 64 + 48 + 16], -1 ; str_label

    inc qword [rel global_count]
    mov rax, rdi
    add rsp, 56
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
.overflow:
    lea rcx, [rel str_err_too_many_globals]
    jmp compile_error

; ------------------------------------------------------------------------------
; local_scope_enter: Reset local symbol table for a new function
; ------------------------------------------------------------------------------
local_scope_enter:
    mov qword [rel local_count], 0
    mov qword [rel cur_stack_offset], 0
    ret

; ------------------------------------------------------------------------------
; local_scope_exit: End of function scope
; ------------------------------------------------------------------------------
local_scope_exit:
    mov qword [rel local_count], 0
    ret

; ------------------------------------------------------------------------------
; local_lookup: Search local symbols (backwards)
; Input:  RCX = symbol name pointer
; Output: RAX = pointer to LOCAL_ENTRY or 0 if not found
; ------------------------------------------------------------------------------
local_lookup:
    push rbx
    push rsi
    sub rsp, 40
    mov rsi, rcx
    mov rbx, [rel local_count]
    test rbx, rbx
    jz .not_found
.loop:
    dec rbx
    mov rax, rbx
    imul rax, LOCAL_ENTRY_SIZE
    lea r10, [rel local_table]
    lea rcx, [r10 + rax]
    mov rdx, rsi
    call str_cmp
    test eax, eax
    jz .found
    test rbx, rbx
    jnz .loop
.not_found:
    xor eax, eax
    jmp .ret
.found:
    mov rax, rbx
    imul rax, LOCAL_ENTRY_SIZE
    lea r10, [rel local_table]
    lea rax, [r10 + rax]
.ret:
    add rsp, 40
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; local_add: Add a local symbol
; Input:  RCX = name
;         RDX = pointer to TYPE_DESC
; Output: RAX = pointer to created LOCAL_ENTRY
; ------------------------------------------------------------------------------
local_add:
    push rbx
    push rsi
    push rdi
    push r12
    sub rsp, 40

    mov rsi, rcx
    mov r12, rdx

    mov rbx, [rel local_count]
    cmp rbx, MAX_LOCALS
    jae .overflow

    imul rax, rbx, LOCAL_ENTRY_SIZE
    lea rdi, [rel local_table]
    add rdi, rax

    ; Copy name
    mov rcx, rdi
    mov rdx, rsi
    call str_copy

    ; Copy type_desc
    lea rcx, [rdi + 64]
    mov rdx, r12
    mov r8, TYPE_DESC_SIZE
    call mem_copy

    ; Allocate space on stack for this local
    ; Align size to 8 bytes to keep stack 8-byte aligned
    mov rax, [r12 + 40]     ; size in bytes
    test rax, rax
    jnz .has_size
    mov rax, 8              ; default minimum 8 bytes
.has_size:
    add rax, 7
    and rax, -8
    add [rel cur_stack_offset], rax
    mov r8, [rel cur_stack_offset]
    mov [rdi + 64 + 48], r8 ; stack_offset (offset below RBP)

    inc qword [rel local_count]
    mov rax, rdi
    add rsp, 40
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
.overflow:
    lea rcx, [rel str_err_too_many_locals]
    jmp compile_error

; ------------------------------------------------------------------------------
; extern_add: Record an external function name
; Input:  RCX = function name pointer
; ------------------------------------------------------------------------------
extern_add:
    push rbx
    push rsi
    sub rsp, 40
    mov rsi, rcx
    ; Check if already in extern table
    xor ebx, ebx
.check_loop:
    cmp rbx, [rel extern_count]
    jae .add_new
    mov rax, rbx
    imul rax, 64
    lea r10, [rel extern_table]
    lea rcx, [r10 + rax]
    mov rdx, rsi
    call str_cmp
    test eax, eax
    jz .already_there
    inc rbx
    jmp .check_loop

.add_new:
    mov rbx, [rel extern_count]
    cmp rbx, MAX_EXTERNS
    jae .already_there
    imul rax, rbx, 64
    lea r10, [rel extern_table]
    lea rcx, [r10 + rax]
    mov rdx, rsi
    call str_copy
    inc qword [rel extern_count]

.already_there:
    add rsp, 40
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; string_pool_add: Add string to string literal pool
; Input:  RCX = string pointer, RDX = length
; Output: RAX = string literal ID (.LC0, .LC1, ...)
; ------------------------------------------------------------------------------
string_pool_add:
    push rbx
    push rsi
    push rdi
    push r12
    sub rsp, 40

    mov rsi, rcx            ; string pointer
    mov r12, rdx            ; length

    mov rbx, [rel string_count]
    cmp rbx, MAX_STRINGS
    jae .overflow

    ; Store string in str_pool_buf at str_pool_bytes
    mov rdi, [rel str_pool_bytes]
    lea r10, [rel str_pool_buf]
    lea rax, [r10 + rdi]

    ; Copy bytes + null terminator
    mov rcx, rax
    mov rdx, rsi
    mov r8, r12
    push r10
    call mem_copy
    pop r10

    mov rdi, [rel str_pool_bytes]
    lea rdx, [rdi + r12]
    mov byte [r10 + rdx], 0 ; null terminator

    ; Record offset and length in str_pool_offsets table
    mov rax, rbx
    imul rax, 16
    lea r11, [rel str_pool_offsets]
    mov [r11 + rax], rdi      ; offset
    mov [r11 + rax + 8], r12  ; length

    ; Advance pool bytes by length + 1
    lea rax, [r12 + 1]
    add [rel str_pool_bytes], rax
    inc qword [rel string_count]

    mov rax, rbx            ; return string ID
    add rsp, 40
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
.overflow:
    lea rcx, [rel str_err_too_many_strings]
    jmp compile_error
