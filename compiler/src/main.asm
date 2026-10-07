; ==============================================================================
; c_compiler_asm - Pure x86-64 Assembly C Compiler
; main.asm - CLI entry point, file I/O, data section emission, and compiler driver
; ==============================================================================

default rel

; ------------------------------------------------------------------------------
; External C runtime / Win64 symbols
; ------------------------------------------------------------------------------
extern printf
extern fopen
extern fread
extern fwrite
extern fclose
extern exit

; ------------------------------------------------------------------------------
; Include compiler modules
; ------------------------------------------------------------------------------
%include "src/defs.inc"
%include "src/utils.asm"
%include "src/lexer.asm"
%include "src/types.asm"
%include "src/symtab.asm"
%include "src/codegen.asm"
%include "src/parser.asm"

; ------------------------------------------------------------------------------
; Data Section: Constants, Strings, Keywords, and Templates
; ------------------------------------------------------------------------------
section .data
str_banner              db "=== CustomC-OS: Pure x86-64 Assembly C Compiler ===", 10, 0
str_usage               db "Usage: c_compiler <input.c> [-o <output.asm>]", 10, 0
str_reading             db "[+] Compiling: %s -> %s", 10, 0
str_compiled_success    db "[+] Successfully compiled! Output: %s", 10, 0
str_mode_rb             db "rb", 0
str_mode_wb             db "wb", 0
str_err_open_in         db "Error: Failed to open input file: %s", 10, 0
str_err_open_out        db "Error: Failed to open output file: %s", 10, 0
str_default_out         db "out.asm", 0

; Error messages
str_err_prefix          db "Compiler Error at ", 0
str_err_pos             db "line %lld, col %lld: ", 0
str_debug_parse_stmt   db "[DEBUG parse_stmt] tok_type=%lld, tok_str='%s'", 10, 0
str_err_msg             db "%s [tok_type=%lld, tok_str='%s']", 10, 0
str_err_out_overflow    db "Output buffer overflow", 0
str_err_unclosed_comment db "Unclosed block comment", 0
str_err_unclosed_str    db "Unclosed string literal", 0
str_err_str_overflow    db "String literal too long", 0
str_err_char_lit        db "Invalid character literal", 0
str_err_too_many_structs db "Maximum struct definitions exceeded", 0
str_err_too_many_members db "Maximum struct members exceeded", 0
str_err_too_many_globals db "Maximum global variables exceeded", 0
str_err_too_many_locals  db "Maximum local variables exceeded", 0
str_err_too_many_strings db "Maximum string literals exceeded", 0
str_err_loop_depth      db "Maximum loop/switch nesting depth exceeded", 0
str_err_unexpected_tok  db "Unexpected token", 0
str_err_expected_expr   db "Expected expression", 0
str_err_undeclared_var  db "Undeclared variable or identifier", 0
str_err_expected_struct_name db "Expected struct name", 0
str_err_unknown_struct  db "Unknown struct type", 0
str_err_expected_member db "Expected member identifier", 0
str_err_unknown_member  db "Struct has no such member", 0
str_err_expected_lvalue db "Expected lvalue for & operator", 0
str_err_expected_ident  db "Expected identifier", 0
str_err_break_outside   db "'break' statement outside of loop or switch", 0
str_err_continue_outside db "'continue' statement outside of loop", 0

; C Keywords
kw_int                  db "int", 0
kw_char                 db "char", 0
kw_void                 db "void", 0
kw_struct               db "struct", 0
kw_if                   db "if", 0
kw_else                 db "else", 0
kw_while                db "while", 0
kw_for                  db "for", 0
kw_do                   db "do", 0
kw_return               db "return", 0
kw_sizeof               db "sizeof", 0
kw_break                db "break", 0
kw_continue             db "continue", 0
kw_switch               db "switch", 0
kw_case                 db "case", 0
kw_default              db "default", 0
kw_extern               db "extern", 0
kw_long                 db "long", 0
kw_const                db "const", 0
kw_static               db "static", 0
kw_unsigned             db "unsigned", 0
kw_signed               db "signed", 0
kw_define               db "define", 0

; Code generator templates
str_label_prefix        db ".L", 0
str_colon_nl            db ":", 10, 0
str_op_jmp              db "jmp .L", 0
str_op_test_rax         db "test rax, rax", 10, 0
str_op_jz               db "jz .L", 0
str_op_jnz              db "jnz .L", 0
str_op_push_rax         db "push rax", 10, 0
str_op_pop_rcx          db "pop rcx", 10, 0
str_op_pop_rdx          db "pop rdx", 10, 0
str_op_pop_r8           db "pop r8", 10, 0
str_op_pop_r9           db "pop r9", 10, 0
str_op_mov_rax          db "mov rax, ", 0
str_op_lea_str          db "lea rax, [LC", 0
str_op_lea_local        db "lea rax, [rbp - ", 0
str_op_lea_global       db "lea rax, [", 0
str_close_bracket_nl    db "]", 10, 0
str_op_mov_rax_ptr      db "mov rax, [rax]", 10, 0
str_op_movzx_rax_byte   db "movzx eax, byte [rax]", 10, 0
str_op_mov_ptr_rax      db "mov [rdx], rax", 10, 0
str_op_mov_byte_ptr_al  db "mov byte [rdx], al", 10, 0
str_op_add              db "add rax, rcx", 10, 0
str_op_sub              db "sub rcx, rax", 10, "    mov rax, rcx", 10, 0
str_op_imul             db "imul rax, rcx", 10, 0
str_op_div              db "mov rbx, rax", 10, "    mov rax, rcx", 10, "    cqo", 10, "    idiv rbx", 10, 0
str_op_mod              db "mov rbx, rax", 10, "    mov rax, rcx", 10, "    cqo", 10, "    idiv rbx", 10, "    mov rax, rdx", 10, 0
str_op_and              db "and rax, rcx", 10, 0
str_op_or               db "or rax, rcx", 10, 0
str_op_xor              db "xor rax, rcx", 10, 0
str_op_shl              db "xchg rax, rcx", 10, "    shl rax, cl", 10, 0
str_op_shr              db "xchg rax, rcx", 10, "    sar rax, cl", 10, 0
str_op_cmp_sete         db "cmp rcx, rax", 10, "    sete al", 10, "    movzx eax, al", 10, 0
str_op_cmp_setne        db "cmp rcx, rax", 10, "    setne al", 10, "    movzx eax, al", 10, 0
str_op_cmp_setl         db "cmp rcx, rax", 10, "    setl al", 10, "    movzx eax, al", 10, 0
str_op_cmp_setle        db "cmp rcx, rax", 10, "    setle al", 10, "    movzx eax, al", 10, 0
str_op_cmp_setg         db "cmp rcx, rax", 10, "    setg al", 10, "    movzx eax, al", 10, 0
str_op_cmp_setge        db "cmp rcx, rax", 10, "    setge al", 10, "    movzx eax, al", 10, 0
str_op_neg              db "neg rax", 10, 0
str_op_not              db "not rax", 10, 0
str_op_bang             db "test rax, rax", 10, "    setz al", 10, "    movzx eax, al", 10, 0
str_global_prefix       db "global ", 0
str_prologue            db "push rbp", 10, "    mov rbp, rsp", 10, 0
str_sub_rsp             db "sub rsp, ", 0
str_add_rsp             db "add rsp, ", 0
str_epilogue            db "mov rsp, rbp", 10, "    pop rbp", 10, "    ret", 10, 0
str_call_prefix         db "call ", 0
str_call_sub_32         db "sub rsp, 32", 10, 0
str_call_add_32         db "add rsp, 32", 10, 0
str_op_imul_imm         db "imul rax, ", 0
str_op_add_rax_imm      db "add rax, ", 0
str_op_inc_rax          db "inc qword [rax]", 10, 0
str_op_dec_rax          db "dec qword [rax]", 10, 0
str_sub_rsp_lbl         db "sub rsp, .L_STK_", 0
str_spill_start         db "mov [rbp - ", 0
str_spill_end_rdi       db "], rdi", 10, 0
str_spill_end_rsi       db "], rsi", 10, 0
str_op_pop_rdi          db "pop rdi", 10, 0
str_op_pop_rsi          db "pop rsi", 10, 0
str_op_xor_eax          db "xor eax, eax", 10, 0
str_spill_end_rcx       db "], rcx", 10, 0
str_spill_end_rdx       db "], rdx", 10, 0
str_spill_end_r8        db "], r8", 10, 0
str_spill_end_r9        db "], r9", 10, 0
str_stk_equ_lbl         db ".L_STK_", 0
str_equ_space           db " equ ", 0
str_op_mov_r11_rax      db "mov r11, rax", 10, 0
str_op_push_r11         db "push r11", 10, 0
str_op_inc_r11_ptr      db "inc qword [r11]", 10, 0
str_op_dec_r11_ptr      db "dec qword [r11]", 10, 0
str_op_mov_rax_r11_ptr  db "mov rax, [r11]", 10, 0
str_cmp_rsp_val         db "cmp qword [rsp], ", 0
str_op_je               db "je .L", 0
str_err_too_many_cases  db "Maximum switch cases exceeded", 0

; Assembly file header & section templates
str_asm_header          db "default rel", 10, "section .data", 10, 0
str_asm_text_sec        db 10, "section .text", 10, 0
str_asm_extern_pfx      db "extern ", 0
str_asm_dq              db " dq ", 0
str_asm_times_db        db " times ", 0
str_asm_db_zero         db " db 0", 10, 0
str_asm_lc_pfx          db "LC", 0
str_asm_db_space        db " db ", 0
str_comma_space         db ", ", 0

; ------------------------------------------------------------------------------
; BSS Section: Global buffers, compiler state, and symbol tables
; ------------------------------------------------------------------------------
section .bss
in_filename             resq 1
out_filename            resq 1
file_handle             resq 1

; Source & output buffers
src_buf                 resb SRC_BUF_SIZE
out_buf                 resb OUT_BUF_SIZE
src_ptr                 resq 1
src_end                 resq 1
out_pos                 resq 1

; Lexer state
cur_line                resq 1
cur_col                 resq 1
tok_type                resq 1
tok_num                 resq 1
tok_len                 resq 1
tok_line                resq 1
tok_col                 resq 1
tok_str                 resb MAX_STR_LEN

; Macros
macro_count             resq 1
macro_tmp_name          resb 64
macro_table             resb (64 * 72)

; Symbol Tables
global_count            resq 1
global_table            resb (MAX_GLOBALS * GLOBAL_ENTRY_SIZE)

local_count             resq 1
cur_stack_offset        resq 1
local_table             resb (MAX_LOCALS * LOCAL_ENTRY_SIZE)

struct_count            resq 1
struct_table            resb (MAX_STRUCTS * STRUCT_ENTRY_SIZE)

member_count            resq 1
member_table            resb (MAX_MEMBERS * MEMBER_ENTRY_SIZE)

extern_count            resq 1
extern_table            resb (MAX_EXTERNS * 64)

string_count            resq 1
str_pool_bytes          resq 1
str_pool_offsets        resb (MAX_STRINGS * 16)
str_pool_buf            resb 65536

; Loop / Switch / Labels
label_counter           resq 1
loop_depth              resq 1
loop_cont_labels        resq MAX_LOOP_DEPTH
loop_break_labels       resq MAX_LOOP_DEPTH
switch_depth            resq 1
switch_break_labels     resq MAX_LOOP_DEPTH
switch_dispatch_labels  resq MAX_LOOP_DEPTH
switch_default_labels   resq MAX_LOOP_DEPTH
switch_case_starts      resq MAX_LOOP_DEPTH
case_count              resq 1
case_vals               resq MAX_SWITCH_CASES
case_labels             resq MAX_SWITCH_CASES
break_stack_depth       resq 1
break_stack_labels      resq MAX_LOOP_DEPTH

; Function state
cur_func_name           resb 64
cur_func_ret_label      resq 1
cur_func_id             resq 1
func_counter            resq 1
defined_func_count      resq 1
defined_func_table      resb (256 * 64)

; L-value tracking for assignments
last_lval_kind          resq 1
last_lval_offset        resq 1
last_lval_size          resq 1
last_lval_name          resb 64

; Array descriptor table for N-dimensional arrays
MAX_ARR_DESCS           equ 128
ARR_DESC_ENTRY_SIZE     equ 80          ; sym_ptr(8), dim_count(8), dims(8*8=64)
arr_desc_count          resq 1
arr_desc_table          resb (MAX_ARR_DESCS * ARR_DESC_ENTRY_SIZE)
cur_arr_sym             resq 1
cur_dim_idx             resq 1
arr_dim_buf             resq 16

; Temporary structs
type_tmp                resb TYPE_DESC_SIZE
expr_type               resb TYPE_DESC_SIZE
ident_tmp               resb MAX_IDENT_LEN
struct_tmp_name         resb MAX_IDENT_LEN

; ------------------------------------------------------------------------------
; Main Compiler Entry Point
; ------------------------------------------------------------------------------
section .text
global main

main:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 48

    ; Support both Win64 (RCX/RDX) and SysV (RDI/RSI)
    test rcx, rcx
    jle .try_sysv
    cmp rcx, 100
    jg .try_sysv
    test rdx, rdx
    jz .try_sysv
    mov r12, rcx
    mov r13, rdx
    jmp .args_done
.try_sysv:
    mov r12, rdi
    mov r13, rsi
.args_done:

    ; Check argc >= 2
    cmp r12, 2
    jge .args_ok
    sub rsp, 32
    lea rcx, [rel str_usage]
    call printf
    add rsp, 32
    mov eax, 1
    jmp .exit

.args_ok:
    ; argv[1] is input file
    mov rax, [r13 + 8]
    mov [rel in_filename], rax

    ; Default output file is "out.asm"
    lea rax, [rel str_default_out]
    mov [rel out_filename], rax

    ; Check if -o specified in argv[2]
    cmp r12, 4
    jl .open_input
    mov rax, [r13 + 16]     ; argv[2]
    cmp byte [rax], '-'
    jne .open_input
    cmp byte [rax + 1], 'o'
    jne .open_input
    mov rax, [r13 + 24]     ; argv[3]
    mov [rel out_filename], rax

.open_input:
    mov rdx, [rel out_filename]
    mov rcx, [rel in_filename]
    lea r8, [rel str_reading]
    sub rsp, 32
    mov rdx, [rel in_filename]
    mov r8, [rel out_filename]
    lea rcx, [rel str_reading]
    call printf
    add rsp, 32

    ; fopen(in_filename, "rb")
    sub rsp, 32
    mov rcx, [rel in_filename]
    lea rdx, [rel str_mode_rb]
    call fopen
    add rsp, 32
    test rax, rax
    jnz .opened_in
    sub rsp, 32
    lea rcx, [rel str_err_open_in]
    mov rdx, [rel in_filename]
    call printf
    add rsp, 32
    mov eax, 1
    jmp .exit

.opened_in:
    mov [rel file_handle], rax

    ; fread(src_buf, 1, SRC_BUF_SIZE - 1, file_handle)
    sub rsp, 32
    lea rcx, [rel src_buf]
    mov rdx, 1
    mov r8, SRC_BUF_SIZE - 1
    mov r9, [rel file_handle]
    call fread
    add rsp, 32

    ; Null-terminate input buffer
    lea rdx, [rel src_buf]
    mov byte [rdx + rax], 0
    mov [rel src_ptr], rdx
    add rdx, rax
    mov [rel src_end], rdx

    ; fclose(file_handle)
    sub rsp, 32
    mov rcx, [rel file_handle]
    call fclose
    add rsp, 32

    ; Initialize compiler state
    mov qword [rel cur_line], 1
    mov qword [rel cur_col], 1
    mov qword [rel out_pos], 0
    mov qword [rel macro_count], 0
    mov qword [rel global_count], 0
    mov qword [rel struct_count], 0
    mov qword [rel member_count], 0
    mov qword [rel extern_count], 0
    mov qword [rel string_count], 0
    mov qword [rel str_pool_bytes], 0
    mov qword [rel label_counter], 0
    mov qword [rel func_counter], 0
    mov qword [rel defined_func_count], 0
    mov qword [rel loop_depth], 0
    mov qword [rel switch_depth], 0
    mov qword [rel case_count], 0
    mov qword [rel break_stack_depth], 0
    mov qword [rel last_lval_kind], 0
    mov qword [rel arr_desc_count], 0
    mov qword [rel cur_arr_sym], 0
    mov qword [rel cur_dim_idx], 0

    ; Prime lexer
    call next_token

    ; Parse top-level program
.parse_loop:
    cmp qword [rel tok_type], TOK_EOF
    je .parse_done
    call parse_global_decl_or_func
    jmp .parse_loop

.parse_done:
    ; Write output file
    call write_output_file

    ; Print success
    sub rsp, 32
    lea rcx, [rel str_compiled_success]
    mov rdx, [rel out_filename]
    call printf
    add rsp, 32

    xor eax, eax

.exit:
    add rsp, 48
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; write_output_file: Write the generated assembly to out_filename
; Structure:
;   default rel
;   section .data
;   string pool .LC0, .LC1...
;   global variables
;   section .text
;   externs
;   functions in out_buf
; ------------------------------------------------------------------------------
write_output_file:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 48

    ; fopen(out_filename, "wb")
    sub rsp, 32
    mov rcx, [rel out_filename]
    lea rdx, [rel str_mode_wb]
    call fopen
    add rsp, 32
    test rax, rax
    jnz .opened_out
    sub rsp, 32
    lea rcx, [rel str_err_open_out]
    mov rdx, [rel out_filename]
    call printf
    add rsp, 32
    sub rsp, 32
    mov rcx, 1
    call exit
    add rsp, 32

.opened_out:
    mov [rel file_handle], rax
    mov r12, rax            ; file pointer

    ; Write header: "default rel\nsection .data\n"
    lea rcx, [rel str_asm_header]
    mov rdx, r12
    call write_file_str

    ; Write String Literals
    xor r13, r13            ; string index = 0
.str_loop:
    cmp r13, [rel string_count]
    jae .str_done

    ; Write ".LC{id} db "
    lea rcx, [rel str_asm_lc_pfx]
    mov rdx, r12
    call write_file_str

    mov rcx, r13
    mov rdx, r12
    call write_file_u64

    lea rcx, [rel str_asm_db_space]
    mov rdx, r12
    call write_file_str

    ; Get string offset and length
    mov rax, r13
    imul rax, 16
    lea r10, [rel str_pool_offsets]
    mov rdi, [r10 + rax]     ; offset in str_pool_buf
    mov rbx, [r10 + rax + 8] ; length
    lea r10, [rel str_pool_buf]
    lea rsi, [r10 + rdi]

    ; Write bytes separated by comma
    xor ecx, ecx            ; byte index
.str_bytes_loop:
    cmp rcx, rbx
    jae .str_bytes_done
    push rcx
    push rbx
    movzx rax, byte [rsi + rcx]
    mov rcx, rax
    mov rdx, r12
    call write_file_u64

    lea rcx, [rel str_comma_space]
    mov rdx, r12
    call write_file_str
    pop rbx
    pop rcx
    inc rcx
    jmp .str_bytes_loop

.str_bytes_done:
    ; Null terminator: "0\n"
    mov rcx, 0
    mov rdx, r12
    call write_file_u64
    lea rcx, [rel str_colon_nl + 1] ; "\n"
    mov rdx, r12
    call write_file_str

    inc r13
    jmp .str_loop

.str_done:
    ; Write Global Variables
    xor r13, r13
.glob_loop:
    cmp r13, [rel global_count]
    jae .glob_done

    mov rax, r13
    imul rax, GLOBAL_ENTRY_SIZE
    lea r10, [rel global_table]
    lea rsi, [r10 + rax]

    ; Write name
    mov rcx, rsi
    mov rdx, r12
    call write_file_str

    ; Check if array
    cmp qword [rsi + 64 + 16], 1
    je .glob_array

    ; Scalar or pointer: " dq "
    lea rcx, [rel str_asm_dq]
    mov rdx, r12
    call write_file_str

    ; Check if string literal pointer
    mov rax, [rsi + 64 + 48 + 16] ; str_label
    cmp rax, -1
    je .glob_num_init

    ; It's a string pointer: ".LC{id}\n"
    lea rcx, [rel str_asm_lc_pfx]
    mov rdx, r12
    call write_file_str
    mov rcx, [rsi + 64 + 48 + 16]
    mov rdx, r12
    call write_file_u64
    lea rcx, [rel str_colon_nl + 1]
    mov rdx, r12
    call write_file_str
    jmp .glob_next

.glob_num_init:
    mov rcx, [rsi + 64 + 48]        ; init_val
    mov rdx, r12
    call write_file_i64
    lea rcx, [rel str_colon_nl + 1]
    mov rdx, r12
    call write_file_str
    jmp .glob_next

.glob_array:
    ; " times {size} db 0\n"
    lea rcx, [rel str_asm_times_db]
    mov rdx, r12
    call write_file_str

    mov rcx, [rsi + 64 + 40]        ; total size in bytes
    mov rdx, r12
    call write_file_u64

    lea rcx, [rel str_asm_db_zero]
    mov rdx, r12
    call write_file_str

.glob_next:
    inc r13
    jmp .glob_loop

.glob_done:
    ; Write Section .text:
    lea rcx, [rel str_asm_text_sec]
    mov rdx, r12
    call write_file_str

    ; Write Externs
    xor r13, r13
.extern_loop:
    cmp r13, [rel extern_count]
    jae .extern_done

    mov rax, r13
    imul rax, 64
    lea r10, [rel extern_table]
    lea rsi, [r10 + rax]

    ; Check if defined locally
    xor ebx, ebx
.check_defined_loop:
    cmp rbx, [rel defined_func_count]
    jae .not_defined_locally
    mov rax, rbx
    imul rax, 64
    lea r10, [rel defined_func_table]
    lea rcx, [r10 + rax]
    mov rdx, rsi
    push rbx
    push rsi
    call str_cmp
    pop rsi
    pop rbx
    test eax, eax
    jz .skip_extern
    inc rbx
    jmp .check_defined_loop

.not_defined_locally:
    lea rcx, [rel str_asm_extern_pfx]   ; "extern "
    mov rdx, r12
    call write_file_str

    mov rcx, rsi
    mov rdx, r12
    call write_file_str

    lea rcx, [rel str_colon_nl + 1]     ; "\n"
    mov rdx, r12
    call write_file_str

.skip_extern:
    inc r13
    jmp .extern_loop

.extern_done:
    ; Write generated function code from out_buf
    mov rax, [rel out_pos]
    test rax, rax
    jz .close_file

    sub rsp, 32
    lea rcx, [rel out_buf]
    mov rdx, 1
    mov r8, [rel out_pos]
    mov r9, r12
    call fwrite
    add rsp, 32

.close_file:
    sub rsp, 32
    mov rcx, r12
    call fclose
    add rsp, 32

    add rsp, 48
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------------------------
; File writing helpers
; ------------------------------------------------------------------------------
write_file_str:
    push rbx
    push rsi
    push rdi
    sub rsp, 48
    mov rsi, rcx            ; string
    mov rbx, rdx            ; file handle
    call str_len
    mov rdx, rax            ; byte count in rdx
    test rdx, rdx
    jz .done
    ; fwrite(buffer, 1, count, file)
    mov rcx, rsi            ; buffer
    mov r8, rdx             ; count
    mov rdx, 1              ; size = 1
    mov r9, rbx             ; file
    sub rsp, 32
    call fwrite
    add rsp, 32
.done:
    add rsp, 48
    pop rdi
    pop rsi
    pop rbx
    ret

write_file_u64:
    push rbx
    push rsi
    push rdi
    sub rsp, 80
    mov rax, rcx            ; value
    mov rsi, rdx            ; file handle
    lea rdi, [rsp + 72]
    mov byte [rdi], 0
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
    mov rdx, rsi
    call write_file_str
    add rsp, 80
    pop rdi
    pop rsi
    pop rbx
    ret

write_file_i64:
    cmp rcx, 0
    jge write_file_u64
    push rcx
    push rdx
    push rbx
    sub rsp, 48
    mov rbx, rdx
    lea rcx, [rel str_neg_sign]
    mov rdx, 1
    mov r8, 1
    mov r9, rbx
    sub rsp, 32
    call fwrite
    add rsp, 32
    add rsp, 48
    pop rbx
    pop rdx
    pop rcx
    neg rcx
    jmp write_file_u64

section .data
str_neg_sign db "-", 0
