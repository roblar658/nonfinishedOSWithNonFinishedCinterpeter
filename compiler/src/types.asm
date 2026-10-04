; ==============================================================================
; c_compiler_asm - Pure x86-64 Assembly C Compiler
; types.asm - Type descriptors, sizing, and struct table management
; ==============================================================================

section .text

; ------------------------------------------------------------------------------
; compute_type_size: Computes and stores total byte size in type_desc
; Input:  RCX = pointer to TYPE_DESC (48 bytes)
; Output: RAX = size in bytes
; ------------------------------------------------------------------------------
compute_type_size:
    push rbx
    mov rbx, rcx

    ; If pointer (ptr_level > 0), single element size is always 8 bytes
    mov rax, [rbx + 8]      ; ptr_level
    test rax, rax
    jz .check_base
    mov rax, 8
    jmp .apply_array

.check_base:
    mov rax, [rbx + 0]      ; kind
    cmp rax, TYPE_CHAR
    jne .check_int
    mov rax, 1
    jmp .apply_array

.check_int:
    cmp rax, TYPE_INT
    jne .check_struct
    mov rax, 8
    jmp .apply_array

.check_struct:
    cmp rax, TYPE_STRUCT
    jne .is_void
    mov rax, [rbx + 32]     ; struct_id
    imul rax, STRUCT_ENTRY_SIZE
    lea rdx, [rel struct_table]
    add rdx, rax
    mov rax, [rdx + 64]     ; total_size
    jmp .apply_array

.is_void:
    xor eax, eax

.apply_array:
    mov r8, [rbx + 16]      ; is_array
    test r8, r8
    jz .done
    imul rax, [rbx + 24]    ; multiply by array_len

.done:
    mov [rbx + 40], rax     ; store computed size in type_desc.size
    pop rbx
    ret

; ------------------------------------------------------------------------------
; get_elem_size: Returns the size of the element pointed to or array element
; Input:  RCX = pointer to TYPE_DESC
; Output: RAX = element size in bytes
; ------------------------------------------------------------------------------
get_elem_size:
    push rbx
    mov rbx, rcx

    mov rax, [rbx + 8]      ; ptr_level
    cmp rax, 1
    ja .ptr_to_ptr          ; **ptr -> elem is 8 bytes
    je .ptr_to_base         ; *ptr -> elem is base type size

    ; Not pointer: check if array
    mov rax, [rbx + 16]     ; is_array
    test rax, rax
    jz .scalar

    ; Array: return size of one element
    mov rax, [rbx + 0]      ; kind
    cmp rax, TYPE_CHAR
    jne .arr_int
    mov eax, 1
    pop rbx
    ret
.arr_int:
    cmp rax, TYPE_INT
    jne .arr_struct
    mov eax, 8
    pop rbx
    ret
.arr_struct:
    mov rax, [rbx + 32]     ; struct_id
    imul rax, STRUCT_ENTRY_SIZE
    lea rdx, [rel struct_table]
    add rdx, rax
    mov rax, [rdx + 64]     ; total_size
    pop rbx
    ret

.ptr_to_ptr:
    mov eax, 8
    pop rbx
    ret

.ptr_to_base:
    mov rax, [rbx + 0]      ; kind
    cmp rax, TYPE_CHAR
    jne .p_int
    mov eax, 1
    pop rbx
    ret
.p_int:
    cmp rax, TYPE_INT
    jne .p_struct
    mov eax, 8
    pop rbx
    ret
.p_struct:
    mov rax, [rbx + 32]     ; struct_id
    imul rax, STRUCT_ENTRY_SIZE
    lea rdx, [rel struct_table]
    add rdx, rax
    mov rax, [rdx + 64]     ; total_size
    pop rbx
    ret

.scalar:
    mov rax, [rbx + 40]     ; just return its size
    pop rbx
    ret

; ------------------------------------------------------------------------------
; struct_lookup: Find struct index by name
; Input:  RCX = struct name pointer
; Output: RAX = struct_id (0..MAX_STRUCTS-1) or -1 if not found
; ------------------------------------------------------------------------------
struct_lookup:
    push rbx
    push rsi
    push rdi
    sub rsp, 32
    mov rsi, rcx
    xor ebx, ebx
.loop:
    cmp rbx, [rel struct_count]
    jae .not_found
    mov rax, rbx
    imul rax, STRUCT_ENTRY_SIZE
    lea rcx, [rel struct_table]
    add rcx, rax
    mov rdx, rsi
    call str_cmp
    test eax, eax
    jz .found
    inc rbx
    jmp .loop
.found:
    mov rax, rbx
    jmp .ret
.not_found:
    mov rax, -1
.ret:
    add rsp, 32
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; struct_add: Allocate new struct definition entry
; Input:  RCX = struct name pointer
; Output: RAX = struct_id (0..MAX_STRUCTS-1)
; ------------------------------------------------------------------------------
struct_add:
    push rbx
    push rsi
    sub rsp, 40
    mov rsi, rcx
    mov rbx, [rel struct_count]
    cmp rbx, MAX_STRUCTS
    jae .overflow
    imul rax, rbx, STRUCT_ENTRY_SIZE
    lea rcx, [rel struct_table]
    add rcx, rax
    mov rdx, rsi
    call str_copy

    imul rax, rbx, STRUCT_ENTRY_SIZE
    lea rdx, [rel struct_table]
    add rdx, rax
    mov qword [rdx + 64], 0     ; total_size = 0
    mov qword [rdx + 72], 0     ; member_count = 0
    mov rax, [rel member_count]
    mov [rdx + 80], rax         ; first_member_idx

    inc qword [rel struct_count]
    mov rax, rbx
    add rsp, 40
    pop rsi
    pop rbx
    ret
.overflow:
    lea rcx, [rel str_err_too_many_structs]
    jmp compile_error

; ------------------------------------------------------------------------------
; struct_add_member: Add a field to a struct
; Input:  RCX = struct_id
;         RDX = member name pointer
;         R8  = pointer to TYPE_DESC
; ------------------------------------------------------------------------------
struct_add_member:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 48

    mov rbx, rcx            ; struct_id
    mov rsi, rdx            ; name
    mov r12, r8             ; type_desc

    mov r13, [rel member_count]
    cmp r13, MAX_MEMBERS
    jae .overflow

    ; Get struct table entry
    mov rax, rbx
    imul rax, STRUCT_ENTRY_SIZE
    lea rdi, [rel struct_table]
    add rdi, rax

    ; Current struct total_size becomes this member's offset (aligned)
    mov rax, [rdi + 64]     ; current total_size
    ; Align member offset to 8 bytes if member size > 1
    mov rdx, [r12 + 40]     ; member size
    cmp rdx, 1
    jbe .no_align
    add rax, 7
    and rax, -8
.no_align:
    mov r9, rax             ; member offset

    ; Update struct total_size: offset + member size BEFORE mem_copy clobbers r9!
    mov rax, r9
    add rax, [r12 + 40]
    ; Align total struct size to 8 bytes
    add rax, 7
    and rax, -8
    mov [rdi + 64], rax     ; update total_size
    inc qword [rdi + 72]    ; inc member_count
    inc qword [rel member_count]

    ; Store in member_table[r13]
    imul rax, r13, MEMBER_ENTRY_SIZE
    lea rcx, [rel member_table]
    add rcx, rax
    mov rdx, rsi
    push r9
    call str_copy
    pop r9

    imul rax, r13, MEMBER_ENTRY_SIZE
    lea rcx, [rel member_table]
    add rcx, rax
    mov [rcx + 64], r9      ; offset

    ; Copy type_desc (48 bytes)
    lea rcx, [rcx + 72]
    mov rdx, r12
    mov r8, TYPE_DESC_SIZE
    call mem_copy

    add rsp, 48
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
.overflow:
    lea rcx, [rel str_err_too_many_members]
    jmp compile_error

; ------------------------------------------------------------------------------
; struct_find_member: Look up a member in a struct by name
; Input:  RCX = struct_id
;         RDX = member name pointer
; Output: RAX = pointer to MEMBER_ENTRY, or 0 if not found
; ------------------------------------------------------------------------------
struct_find_member:
    push rbx
    push rsi
    push rdi
    push r12
    sub rsp, 40

    mov rbx, rcx            ; struct_id
    mov rsi, rdx            ; target name

    mov rax, rbx
    imul rax, STRUCT_ENTRY_SIZE
    lea rdi, [rel struct_table]
    add rdi, rax

    mov r12, [rdi + 72]     ; member_count
    mov rbx, [rdi + 80]     ; first_member_idx
    xor edx, edx            ; loop counter
.loop:
    cmp rdx, r12
    jae .not_found

    lea rax, [rbx + rdx]
    imul rax, MEMBER_ENTRY_SIZE
    lea rcx, [rel member_table]
    add rcx, rax
    push rdx
    mov rdx, rsi
    call str_cmp
    pop rdx
    test eax, eax
    jz .found

    inc rdx
    jmp .loop

.found:
    lea rax, [rbx + rdx]
    imul rax, MEMBER_ENTRY_SIZE
    lea r10, [rel member_table]
    lea rax, [r10 + rax]
    jmp .ret

.not_found:
    xor eax, eax

.ret:
    add rsp, 40
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
