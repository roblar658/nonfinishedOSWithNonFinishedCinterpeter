; ==============================================================================
; CustomC-OS: C-tolk
; Tolker et C-subsett direkte fra kildeteksten.
; Stotter: int/char (32-bit), 1D int-arrays, funksjoner med parametre og
; rekursjon, globale variabler, if/else, while, for, break, continue, return,
; printf (%d %i %c %s %x %% + bredde), putchar, puts
; Operatorer: + - * / % == != < > <= >= && || ! = += -= *= /= %= ++ --
; ==============================================================================

T_EOF       equ 0
T_NUM       equ 1
T_IDENT     equ 2
T_STR       equ 3
T_BAD       equ 4
T_EQ        equ 128
T_NE        equ 129
T_LE        equ 130
T_GE        equ 131
T_AND       equ 132
T_OR        equ 133
T_INC       equ 134
T_DEC       equ 135
T_ADDEQ     equ 136
T_SUBEQ     equ 137
T_MULEQ     equ 138
T_DIVEQ     equ 139
T_MODEQ     equ 140
T_ARROW     equ 141
K_INT       equ 150
K_CHAR      equ 151
K_VOID      equ 152
K_IF        equ 153
K_ELSE      equ 154
K_WHILE     equ 155
K_FOR       equ 156
K_RETURN    equ 157
K_BREAK     equ 158
K_CONTINUE  equ 159
K_DO        equ 160
K_DOUBLE    equ 161
K_FLOAT     equ 162
T_FLOAT     equ 145

K_STATIC    equ 163
K_CONST     equ 164
K_EXTERN    equ 165
K_VOLATILE  equ 166
K_INLINE    equ 167
K_AUTO      equ 168
K_REGISTER  equ 169
K_SIGNED    equ 170
K_UNSIGNED  equ 171
K_LONG      equ 172
K_SHORT     equ 173
K_BOOL      equ 174
K_STRUCT    equ 175
K_UNION     equ 176
K_ENUM      equ 177
K_TYPEDEF   equ 178

; Minnekart for tolken (offset i kjernesegmentet 0x1000)
CI_VARS         equ 0xA000      ; variabeltabell (3 KB: 0xA000..0xAC00)
CI_VAR_SIZE     equ 24          ; navn[16], verdi dd, arr_ptr dw, arr_len dw
CI_MAX_VARS     equ 128
CI_FUNCS        equ 0xAC00      ; funksjonstabell (1 KB: 0xAC00..0xB000)
CI_FUNC_SIZE    equ 20          ; navn[16], posisjon dw, pad dw
CI_MAX_FUNCS    equ 32
CI_HEAP         equ 0xB000      ; array-minne (2 KB: 0xB000..0xB800)
CI_HEAP_END     equ 0xB800
FS_POOL         equ 0xB800      ; lagrede filer fra editoren (14 KB: 0xB800..0xF000)
FS_POOL_END     equ 0xF000
CI_STACK_MIN    equ 0xF000      ; stakkgrense (rekursjonsvern, 4 KB stakk 0xF000..0xFFFE)

%macro EXPECT 1
    cmp byte [tok_type], %1
    je %%ok
    mov byte [ci_e_expect_ch], %1
    mov si, ci_e_expect
    jmp ci_error
%%ok:
    call ci_lex
%endmacro

; ------------------------------------------------------------------------------
; ci_run: SI = kildetekst. Kjorer main(). CF=0 ok (EAX = returkode), CF=1 feil
; ------------------------------------------------------------------------------
ci_run:
    mov [ci_err_sp], sp
    call ci_reset
    call ci_prepass
    mov si, ci_s_main
    call ci_find_func
    jc .nomain
    mov byte [ci_exec], 1
    mov byte [ci_ctl], 0
    mov ax, [bx+16]
    call ci_lex_at
    EXPECT '('
.params:
    cmp byte [tok_type], ')'
    je .params_done
    call ci_lex
    jmp .params
.params_done:
    EXPECT ')'
    mov ax, [ci_var_count]
    mov [ci_frame_base], ax
    cmp byte [tok_type], '{'
    jne .nobody
    call ci_statement
    xor eax, eax
    cmp byte [ci_ctl], 1
    jne .done
    mov eax, [ci_ret]
.done:
    clc
    ret
.nomain:
    mov si, ci_e_nomain
    jmp ci_error
.nobody:
    mov si, ci_e_body
    jmp ci_error

; ------------------------------------------------------------------------------
; ci_check: SI = kildetekst. Syntakssjekk uten kjoring. CF=1 ved feil
; ------------------------------------------------------------------------------
ci_check:
    mov [ci_err_sp], sp
    call ci_reset
    call ci_prepass
    mov si, ci_s_main
    call ci_find_func
    jc .nomain
    clc
    ret
.nomain:
    mov si, ci_e_nomain
    jmp ci_error

ci_reset:
    finit
    fnstcw [ci_fpu_cw]
    mov ax, [ci_fpu_cw]
    or ah, 0x0C
    mov [ci_fpu_cw_trunc], ax
    mov [ci_src], si
    xor ax, ax
    mov [ci_var_count], ax
    mov [ci_frame_base], ax
    mov [ci_global_count], ax
    mov [ci_func_count], ax
    mov [ci_lv], ax
    mov byte [ci_exec], 0
    mov byte [ci_ctl], 0
    mov byte [ci_last_char], 10
    mov word [ci_heap_top], CI_HEAP
    ret

; ------------------------------------------------------------------------------
; Feilhandtering: SI = melding. Skriver linjenummer og avbryter tolken.
; ------------------------------------------------------------------------------
ci_error:
    push si
    mov si, ci_m_err
    call term_puts
    mov di, [ci_src]
    mov bx, [tok_start]
    mov eax, 1
.ln:
    cmp di, bx
    jae .lnd
    cmp byte [di], 10
    jne .lnn
    inc eax
.lnn:
    inc di
    jmp .ln
.lnd:
    call print_sdec32
    mov si, ci_m_colon
    call term_puts
    pop si
    call term_puts
    cmp byte [ci_err_name], 0
    je .noname
    mov si, ci_m_q1
    call term_puts
    mov si, ci_err_name
    call term_puts
    mov si, ci_m_q2
    call term_puts
    mov byte [ci_err_name], 0
.noname:
    call term_crlf
    mov sp, [ci_err_sp]
    stc
    ret

; SI = navn, BX = melding
ci_error_name:
    push di
    mov di, ci_err_name
    call copy_str
    mov byte [ci_err_name+15], 0
    pop di
    mov si, bx
    jmp ci_error

ci_div_zero:
    mov si, ci_e_div0
    jmp ci_error

ci_check_abort:
    push ax
    push dx
    mov ah, 0x01
    int 0x16
    jz .ser
    cmp al, 27
    jne .ser
    mov ah, 0x00
    int 0x16
    jmp .abort
.ser:
    mov dx, 0x3FD
    in al, dx
    test al, 1
    jz .ok
    mov dx, 0x3F8
    in al, dx
    cmp al, 27
    je .abort
    cmp al, 3
    je .abort
.ok:
    pop dx
    pop ax
    ret
.abort:
    mov si, ci_e_abort
    jmp ci_error

; ------------------------------------------------------------------------------
; Leksikalsk analyse. ci_lex bevarer alle registre.
; ------------------------------------------------------------------------------
ci_lex_at:                      ; AX = posisjon i kildeteksten
    mov [ci_pos], ax
ci_lex:
    push eax
    push ebx
    push cx
    push si
    push di
    mov si, [ci_pos]
.skip:
    mov al, [si]
    cmp al, ' '
    je .ws
    cmp al, 9
    je .ws
    cmp al, 13
    je .ws
    cmp al, 10
    je .ws
    cmp al, '#'
    je .linec
    cmp al, '/'
    jne .start
    cmp byte [si+1], '/'
    je .linec
    cmp byte [si+1], '*'
    jne .start
    add si, 2
.blockc:
    mov al, [si]
    test al, al
    jz .start
    cmp al, '*'
    jne .bnext
    cmp byte [si+1], '/'
    jne .bnext
    add si, 2
    jmp .skip
.bnext:
    inc si
    jmp .blockc
.linec:
    mov al, [si]
    test al, al
    jz .start
    cmp al, 92                  ; backslash '\'
    jne .chk_nl
    inc si
    mov al, [si]
    cmp al, 13
    jne .chk_nl10
    inc si
    mov al, [si]
.chk_nl10:
    cmp al, 10
    jne .linec
    inc si
    jmp .linec
.chk_nl:
    cmp al, 10
    je .skip
    inc si
    jmp .linec
.ws:
    inc si
    jmp .skip

.start:
    mov [tok_start], si
    mov al, [si]
    test al, al
    jnz .not_eof
    mov byte [tok_type], T_EOF
    jmp .done
.not_eof:
    cmp al, '0'
    jb .not_num
    cmp al, '9'
    ja .not_num
    xor eax, eax
.num_loop:
    movzx ebx, byte [si]
    sub bl, '0'
    jb .num_end
    cmp bl, 9
    ja .num_end
    imul eax, eax, 10
    add eax, ebx
    inc si
    jmp .num_loop
.num_end:
    cmp byte [si], '.'
    je .read_float
.skip_suffix:
    mov bl, [si]
    cmp bl, 'u'
    je .inc_suffix
    cmp bl, 'U'
    je .inc_suffix
    cmp bl, 'l'
    je .inc_suffix
    cmp bl, 'L'
    je .inc_suffix
    jmp .suffix_done
.inc_suffix:
    inc si
    jmp .skip_suffix
.suffix_done:
    mov [tok_num], eax
    mov byte [tok_type], T_NUM
    jmp .done
.read_float:
    inc si
    mov [ci_f_tmp1], eax
    xor eax, eax
    mov ecx, 1
.frac_loop:
    movzx ebx, byte [si]
    sub bl, '0'
    jb .frac_end
    cmp bl, 9
    ja .frac_end
    imul eax, eax, 10
    add eax, ebx
    imul ecx, ecx, 10
    inc si
    jmp .frac_loop
.frac_end:
    mov [ci_f_tmp2], eax
    mov [ci_f_tmp3], ecx
    fild dword [ci_f_tmp2]
    fild dword [ci_f_tmp3]
    fdivp st1, st0
    fild dword [ci_f_tmp1]
    faddp st1, st0
    fstp dword [tok_num]
    mov byte [tok_type], T_FLOAT
    jmp .done

.not_num:
    cmp al, '.'
    jne .not_dot_flt
    cmp byte [si+1], '0'
    jb .not_dot_flt
    cmp byte [si+1], '9'
    ja .not_dot_flt
    inc si
    xor eax, eax
    mov [ci_f_tmp1], eax
    xor eax, eax
    mov ecx, 1
    jmp .frac_loop
.not_dot_flt:
    call ci_is_alpha
    jc .not_ident
    mov di, tok_name
    xor cx, cx
.id_loop:
    mov al, [si]
    call ci_is_alnum
    jc .id_end
    cmp cx, 15
    jae .id_skip
    mov [di], al
    inc di
    inc cx
.id_skip:
    inc si
    jmp .id_loop
.id_end:
    mov byte [di], 0
    mov byte [tok_type], T_IDENT
    push si
    mov bx, ci_keywords
.kw_loop:
    mov di, [bx]
    test di, di
    jz .kw_done
    mov si, tok_name
    call str_equals
    je .kw_found
    add bx, 3
    jmp .kw_loop
.kw_found:
    mov al, [bx+2]
    mov [tok_type], al
.kw_done:
    pop si
    jmp .done

.not_ident:
    cmp al, '"'
    jne .not_str
    inc si
    mov [tok_sptr], si
.str_loop:
    mov al, [si]
    test al, al
    jz .err_str
    cmp al, 10
    je .err_str
    inc si
    cmp al, '\'
    jne .str_chk
    cmp byte [si], 0
    je .err_str
    inc si
    jmp .str_loop
.str_chk:
    cmp al, '"'
    jne .str_loop
    mov byte [tok_type], T_STR
    jmp .done
.err_str:
    mov si, ci_e_str
    jmp ci_error

.not_str:
    cmp al, 39
    jne .not_chr
    inc si
    mov al, [si]
    cmp al, '\'
    jne .chr_plain
    inc si
    mov al, [si]
    call ci_escape
.chr_plain:
    movzx eax, al
    inc si
    cmp byte [si], 39
    jne .err_chr
    inc si
    mov [tok_num], eax
    mov byte [tok_type], T_NUM
    jmp .done
.err_chr:
    mov si, ci_e_chr
    jmp ci_error

.not_chr:
    cmp al, 128
    jae .bad
    cmp al, 32
    jb .bad
    mov bx, ci_ops2
.op_loop:
    mov ah, [bx]
    test ah, ah
    jz .single
    cmp ah, al
    jne .op_next
    mov ah, [bx+1]
    cmp ah, [si+1]
    jne .op_next
    mov ah, [bx+2]
    mov [tok_type], ah
    add si, 2
    jmp .done
.op_next:
    add bx, 3
    jmp .op_loop
.single:
    mov [tok_type], al
    inc si
    jmp .done
.bad:
    mov byte [tok_type], T_BAD
    inc si
.done:
    mov [ci_pos], si
    pop di
    pop si
    pop cx
    pop ebx
    pop eax
    ret

ci_is_alpha:                    ; AL -> CF=0 hvis bokstav eller '_'
    cmp al, '_'
    je .yes
    push ax
    or al, 0x20
    cmp al, 'a'
    jb .no
    cmp al, 'z'
    ja .no
    pop ax
.yes:
    clc
    ret
.no:
    pop ax
    stc
    ret

ci_is_alnum:                    ; AL -> CF=0 hvis bokstav, siffer eller '_'
    cmp al, '0'
    jb ci_is_alpha
    cmp al, '9'
    ja ci_is_alpha
    clc
    ret

ci_escape:                      ; AL = tegn etter '\' -> AL = verdi
    cmp al, 'n'
    jne .e1
    mov al, 10
    ret
.e1:
    cmp al, 't'
    jne .e2
    mov al, 9
    ret
.e2:
    cmp al, 'r'
    jne .e3
    mov al, 13
    ret
.e3:
    cmp al, '0'
    jne .e4
    xor al, al
.e4:
    ret

; ------------------------------------------------------------------------------
; Symboltabeller
; ------------------------------------------------------------------------------
ci_find_var:                    ; SI = navn -> BX = oppforing, CF=1 ikke funnet
    push ax
    push cx
    push di
    mov cx, [ci_var_count]
.loc:
    cmp cx, [ci_frame_base]
    jbe .glob_init
    dec cx
    imul bx, cx, CI_VAR_SIZE
    add bx, CI_VARS
    mov di, bx
    call str_equals
    je .found
    jmp .loc
.glob_init:
    mov cx, [ci_global_count]
.glob:
    test cx, cx
    jz .nf
    dec cx
    imul bx, cx, CI_VAR_SIZE
    add bx, CI_VARS
    mov di, bx
    call str_equals
    je .found
    jmp .glob
.nf:
    pop di
    pop cx
    pop ax
    stc
    ret
.found:
    pop di
    pop cx
    pop ax
    clc
    ret

ci_add_var:                     ; SI = navn, EAX = verdi -> BX = oppforing
    push di
    mov bx, [ci_var_count]
    cmp bx, CI_MAX_VARS
    jae .full
    imul bx, bx, CI_VAR_SIZE
    add bx, CI_VARS
    mov di, bx
    call copy_str
    mov byte [bx+15], 0
    mov [bx+16], eax
    mov word [bx+20], 0
    mov word [bx+22], 0
    inc word [ci_var_count]
    pop di
    ret
.full:
    mov si, ci_e_vars
    jmp ci_error

ci_find_func:                   ; SI = navn -> BX = oppforing, CF=1 ikke funnet
    push ax
    push cx
    push di
    xor cx, cx
.l:
    cmp cx, [ci_func_count]
    jae .nf
    imul bx, cx, CI_FUNC_SIZE
    add bx, CI_FUNCS
    mov di, bx
    call str_equals
    je .found
    inc cx
    jmp .l
.nf:
    pop di
    pop cx
    pop ax
    stc
    ret
.found:
    pop di
    pop cx
    pop ax
    clc
    ret

; ------------------------------------------------------------------------------
; Forhandsgjennomgang: registrer funksjoner, opprett globale variabler og
; syntakssjekk alle funksjonskropper (uten a kjore dem).
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; ci_consume_type:
; Gjenkjenner og spiser en type inkludert:
;  - lagringsklasser / kvalifikatorer (static, const, extern, volatile, inline, etc.)
;  - heltallsvarianter (unsigned, signed, long, short, bool, size_t, etc.)
;  - flyttall (double, float)
;  - pekersymboler ('*')
;  - struct/union/enum brukt som type (f.eks. struct Point p;)
;  - implisitt int (f.eks. main() { ... })
; Ut:
;  CF = 0: Gyldig type funnet. AL = basetype (K_INT, K_CHAR, K_DOUBLE, K_FLOAT, K_VOID)
;          tok_type peker na pa forste token etter typen (typisk T_IDENT).
;  CF = 1: Ikke en type.
; ------------------------------------------------------------------------------
ci_consume_type:
.qual_loop:
    mov al, [tok_type]
    cmp al, K_STATIC
    je .skip_q
    cmp al, K_CONST
    je .skip_q
    cmp al, K_VOLATILE
    je .skip_q
    cmp al, K_INLINE
    je .skip_q
    cmp al, K_AUTO
    je .skip_q
    cmp al, K_REGISTER
    je .skip_q
    cmp al, K_SIGNED
    je .skip_q
    cmp al, K_EXTERN
    jne .check_unsigned
    call ci_lex
    cmp byte [tok_type], T_STR
    jne .qual_loop
    call ci_lex
    jmp .qual_loop
.skip_q:
    call ci_lex
    jmp .qual_loop

.check_unsigned:
    mov dl, K_INT
    cmp al, K_UNSIGNED
    jne .check_basic
    call ci_lex
    mov al, [tok_type]
    cmp al, K_CHAR
    jne .u_not_char
    mov dl, K_CHAR
    call ci_lex
    jmp .skip_ptrs
.u_not_char:
    cmp al, K_INT
    je .u_eat
    cmp al, K_LONG
    je .u_eat
    cmp al, K_SHORT
    je .u_eat
    jmp .skip_ptrs
.u_eat:
    call ci_lex
.u_eat_loop:
    cmp byte [tok_type], K_LONG
    je .u_eat_extra
    cmp byte [tok_type], K_INT
    je .u_eat_extra
    jmp .skip_ptrs
.u_eat_extra:
    call ci_lex
    jmp .u_eat_loop

.check_basic:
    cmp al, K_INT
    je .is_int
    cmp al, K_CHAR
    je .is_char
    cmp al, K_VOID
    je .is_void
    cmp al, K_DOUBLE
    je .is_flt
    cmp al, K_FLOAT
    je .is_flt
    cmp al, K_LONG
    je .is_int
    cmp al, K_SHORT
    je .is_int
    cmp al, K_BOOL
    je .is_int
    cmp al, K_STRUCT
    je .type_struct
    cmp al, K_UNION
    je .type_struct
    cmp al, K_ENUM
    je .type_struct

    ; Sjekk om T_IDENT er fulgt av '(' (implisitt int funksjon)
    ; eller av '*' / T_IDENT (typedef-type)
    cmp al, T_IDENT
    jne .not_a_type

    push word [ci_pos]
    push word [tok_start]
    push dword [tok_num]
    push word [tok_sptr]
    push word [tok_name]
    push word [tok_name+2]
    push word [tok_name+4]
    push word [tok_name+6]
    push word [tok_name+8]
    push word [tok_name+10]
    push word [tok_name+12]
    push word [tok_name+14]
    push word [tok_type]
    call ci_lex
    mov bl, [tok_type]
    pop word [tok_type]
    pop word [tok_name+14]
    pop word [tok_name+12]
    pop word [tok_name+10]
    pop word [tok_name+8]
    pop word [tok_name+6]
    pop word [tok_name+4]
    pop word [tok_name+2]
    pop word [tok_name]
    pop word [tok_sptr]
    pop dword [tok_num]
    pop word [tok_start]
    pop word [ci_pos]

    cmp bl, '*'
    je .typedef_use
    cmp bl, T_IDENT
    je .typedef_use
    jmp .not_a_type

.typedef_use:
    call ci_lex
    mov dl, K_INT
    jmp .skip_ptrs

.type_struct:
    ; Sjekk om det er struct definisjon med kropp '{' (f.eks. struct Foo { ... };)
    ; I sa fall ma den handteres av struct-deklarasjonshandtereren, ikke her
    push word [ci_pos]
    push word [tok_start]
    push dword [tok_num]
    push word [tok_sptr]
    push word [tok_name]
    push word [tok_name+2]
    push word [tok_name+4]
    push word [tok_name+6]
    push word [tok_name+8]
    push word [tok_name+10]
    push word [tok_name+12]
    push word [tok_name+14]
    push word [tok_type]
    call ci_lex
    cmp byte [tok_type], T_IDENT
    jne .ts_chk_brace
    call ci_lex
.ts_chk_brace:
    cmp byte [tok_type], '{'
    pop word [tok_type]
    pop word [tok_name+14]
    pop word [tok_name+12]
    pop word [tok_name+10]
    pop word [tok_name+8]
    pop word [tok_name+6]
    pop word [tok_name+4]
    pop word [tok_name+2]
    pop word [tok_name]
    pop word [tok_sptr]
    pop dword [tok_num]
    pop word [tok_start]
    pop word [ci_pos]
    je .not_a_type              ; la .handle_struct_decl ta den!

    call ci_lex                 ; spis 'struct'
    cmp byte [tok_type], T_IDENT
    jne .not_a_type
    call ci_lex                 ; spis navnet pa strukturen
    mov dl, K_INT
    jmp .skip_ptrs

.is_char:
    mov dl, K_CHAR
    call ci_lex
    jmp .skip_ptrs
.is_void:
    mov dl, K_VOID
    call ci_lex
    jmp .skip_ptrs
.is_flt:
    mov dl, al
    call ci_lex
    jmp .skip_ptrs
.is_int:
    mov dl, K_INT
    call ci_lex
.eat_int_loop:
    cmp byte [tok_type], K_INT
    je .eat_extra
    cmp byte [tok_type], K_LONG
    je .eat_extra
    jmp .skip_ptrs
.eat_extra:
    call ci_lex
    jmp .eat_int_loop
.skip_ptrs:
    xor dh, dh
.sp_loop:
    cmp byte [tok_type], '*'
    jne .type_done
    mov dh, 1
    call ci_lex
    jmp .sp_loop
.type_done:
    mov al, dl
    mov ah, dh
    clc
    ret
.not_a_type:
    stc
    ret

ci_skip_braces:                 ; Hopper over matchende { ... }
    push cx
    xor cx, cx
.sb_loop:
    mov al, [tok_type]
    cmp al, T_EOF
    je .sb_eof
    cmp al, '{'
    jne .sb_chk_close
    inc cx
    jmp .sb_next
.sb_chk_close:
    cmp al, '}'
    jne .sb_next
    dec cx
    jz .sb_done
.sb_next:
    call ci_lex
    jmp .sb_loop
.sb_done:
    call ci_lex
    pop cx
    ret
.sb_eof:
    mov si, ci_e_brace
    jmp ci_error

ci_skip_until_semi:             ; Hopper over tokens til og med ';'
.sus_loop:
    mov al, [tok_type]
    cmp al, T_EOF
    je .sus_eof
    cmp al, '{'
    jne .sus_chk_semi
    call ci_skip_braces
    jmp .sus_loop
.sus_chk_semi:
    cmp al, ';'
    je .sus_done
    call ci_lex
    jmp .sus_loop
.sus_done:
    call ci_lex
    ret
.sus_eof:
    ret

ci_prepass:
    mov ax, [ci_src]
    call ci_lex_at
.top:
    mov al, [tok_type]
    cmp al, T_EOF
    je .done
    cmp al, ';'
    jne .not_semi
    call ci_lex
    jmp .top
.not_semi:
    ; Losrevne krollparenteser (f.eks. extern "C" { eller tomme blokker)
    cmp al, '{'
    je .skip_stray_brace
    cmp al, '}'
    je .skip_stray_brace

    ; struct / union / enum definisjoner
    cmp al, K_STRUCT
    je .handle_struct_decl
    cmp al, K_UNION
    je .handle_struct_decl
    cmp al, K_ENUM
    je .handle_struct_decl

    ; typedef
    cmp al, K_TYPEDEF
    je .handle_typedef

    ; Parse type (inkl. static, const, unsigned, long, pointers, etc.)
    call ci_consume_type
    jnc .typ

    ; Sjekk om det er en toppnivaa-funksjon med implisitt int (f.eks. main() { ... })
    mov al, [tok_type]
    cmp al, T_IDENT
    jne .err_toplevel
    push word [ci_pos]
    push word [tok_start]
    push dword [tok_num]
    push word [tok_sptr]
    push word [tok_name]
    push word [tok_name+2]
    push word [tok_name+4]
    push word [tok_name+6]
    push word [tok_name+8]
    push word [tok_name+10]
    push word [tok_name+12]
    push word [tok_name+14]
    push word [tok_type]
    call ci_lex
    mov bl, [tok_type]
    pop word [tok_type]
    pop word [tok_name+14]
    pop word [tok_name+12]
    pop word [tok_name+10]
    pop word [tok_name+8]
    pop word [tok_name+6]
    pop word [tok_name+4]
    pop word [tok_name+2]
    pop word [tok_name]
    pop word [tok_sptr]
    pop dword [tok_num]
    pop word [tok_start]
    pop word [ci_pos]
    cmp bl, '('
    jne .err_toplevel
    mov al, K_INT
    jmp .typ

.err_toplevel:
    mov si, ci_e_toplevel
    jmp ci_error

.skip_stray_brace:
    call ci_lex
    jmp .top

.handle_typedef:
    call ci_lex
    call ci_skip_until_semi
    jmp .top

.handle_struct_decl:
    call ci_lex
    cmp byte [tok_type], T_IDENT
    jne .sd_noname
    call ci_lex
.sd_noname:
    cmp byte [tok_type], '{'
    jne .sd_semi
    call ci_skip_braces
.sd_semi:
    call ci_skip_until_semi
    jmp .top

.typ:
    mov [ci_cur_decl_type], al
    cmp byte [tok_type], T_IDENT
    jne .name_err
    mov si, tok_name
    mov di, ci_tmpname
    call copy_str
    push word [tok_start]
    call ci_lex
    cmp byte [tok_type], '('
    je .func
    ; global variabel: gjenparse fra identifikatoren
    pop ax
    call ci_lex_at
    mov byte [ci_exec], 1
    call ci_decl_rest
    mov byte [ci_exec], 0
    mov ax, [ci_var_count]
    mov [ci_global_count], ax
    jmp .top
.func:
    add sp, 2
    mov bx, [ci_func_count]
    cmp bx, CI_MAX_FUNCS
    jae .too_many
    imul bx, bx, CI_FUNC_SIZE
    add bx, CI_FUNCS
    mov di, bx
    mov si, ci_tmpname
    call copy_str
    mov ax, [tok_start]
    mov [bx+16], ax
    mov al, [ci_cur_decl_type]
    mov [bx+18], al
    inc word [ci_func_count]
    call ci_skip_parens
    cmp byte [tok_type], ';'
    je .proto
    cmp byte [tok_type], '{'
    jne .body_err
    mov byte [ci_exec], 0
    mov ax, [ci_var_count]
    mov [ci_frame_base], ax
    call ci_block
    jmp .top
.proto:
    dec word [ci_func_count]
    call ci_lex
    jmp .top
.done:
    mov ax, [ci_var_count]
    mov [ci_global_count], ax
    ret
.name_err:
    mov si, ci_e_name
    jmp ci_error
.too_many:
    mov si, ci_e_funcs
    jmp ci_error
.body_err:
    mov si, ci_e_body
    jmp ci_error

ci_skip_parens:                 ; tok = '(' -> hopper til etter matchende ')'
    push cx
    xor cx, cx
.l:
    mov al, [tok_type]
    cmp al, T_EOF
    je .eof
    cmp al, '('
    jne .n1
    inc cx
    jmp .nx
.n1:
    cmp al, ')'
    jne .nx
    dec cx
.nx:
    call ci_lex
    test cx, cx
    jnz .l
    pop cx
    ret
.eof:
    mov si, ci_e_eof
    jmp ci_error

; ------------------------------------------------------------------------------
; Setninger
; ------------------------------------------------------------------------------
ci_statement:
    cmp sp, CI_STACK_MIN
    jb .overflow
    mov al, [tok_type]
    cmp al, '{'
    je ci_block
    cmp al, ';'
    je .empty
    cmp al, T_EOF
    je .eof
    cmp al, K_STRUCT
    je .stmt_struct
    cmp al, K_UNION
    je .stmt_struct
    cmp al, K_ENUM
    je .stmt_struct
    cmp al, K_TYPEDEF
    je .stmt_typedef

    call ci_consume_type
    jnc .decl_typed

    mov al, [tok_type]
    cmp al, K_IF
    je ci_if
    cmp al, K_WHILE
    je ci_while
    cmp al, K_DO
    je ci_do
    cmp al, K_FOR
    je ci_for
    cmp al, K_RETURN
    je ci_return
    cmp al, K_BREAK
    je .brk
    cmp al, K_CONTINUE
    je .cont
    call ci_expr
    EXPECT ';'
    ret
.decl_typed:
    mov [ci_cur_decl_type], al
    jmp ci_decl_rest
.stmt_typedef:
    call ci_lex
    call ci_skip_until_semi
    ret
.stmt_struct:
    call ci_lex
    cmp byte [tok_type], T_IDENT
    jne .ss_noname
    call ci_lex
.ss_noname:
    cmp byte [tok_type], '{'
    jne .ss_semi
    call ci_skip_braces
.ss_semi:
    call ci_skip_until_semi
    ret
.brk:
    call ci_lex
    EXPECT ';'
    cmp byte [ci_exec], 0
    je .r
    mov byte [ci_ctl], 2
    mov byte [ci_exec], 0
.r:
    ret
.cont:
    call ci_lex
    EXPECT ';'
    cmp byte [ci_exec], 0
    je .r
    mov byte [ci_ctl], 3
    mov byte [ci_exec], 0
    ret
.empty:
    call ci_lex
    ret
.eof:
    mov si, ci_e_eof
    jmp ci_error
.overflow:
    mov si, ci_e_stack
    jmp ci_error

ci_block:
    call ci_lex
    push word [ci_var_count]
    push word [ci_heap_top]
.loop:
    mov al, [tok_type]
    cmp al, '}'
    je .end
    cmp al, T_EOF
    je .eof
    call ci_statement
    jmp .loop
.end:
    call ci_lex
    pop word [ci_heap_top]
    pop word [ci_var_count]
    ret
.eof:
    mov si, ci_e_brace
    jmp ci_error

; Etter typenokkelord: navn [= uttrykk] | navn[N] [= {..}] , ... ;
ci_decl_rest:
.skip_p_decl:
    cmp byte [tok_type], '*'
    jne .not_ptr_decl
    call ci_lex
    jmp .skip_p_decl
.not_ptr_decl:
    cmp byte [tok_type], T_IDENT
    jne .name_err
    sub sp, 16
    mov di, sp
    mov si, tok_name
    call copy_str
    call ci_lex
    cmp byte [tok_type], '['
    je .array
    xor eax, eax
    cmp byte [tok_type], '='
    jne .sc_add
    call ci_lex
    call ci_expr
.sc_add:
    cmp byte [ci_exec], 0
    je .next
    mov si, sp
    call ci_add_var
    mov al, [ci_cur_decl_type]
    cmp al, K_DOUBLE
    je .sc_set_flt
    cmp al, K_FLOAT
    je .sc_set_flt
    jmp .next
.sc_set_flt:
    mov byte [bx+15], 2
    jmp .next

.array:
    call ci_lex
    xor ecx, ecx
    cmp byte [tok_type], ']'
    je .arr_nosize
    call ci_expr
    mov ecx, eax
.arr_nosize:
    EXPECT ']'
    mov word [ci_tmp_dim2], 0
    cmp byte [tok_type], '['
    jne .not_2d_decl
    call ci_lex
    push ecx
    call ci_expr
    mov [ci_tmp_dim2], ax
    EXPECT ']'
    pop ecx
    movzx edx, word [ci_tmp_dim2]
    imul ecx, edx
.not_2d_decl:
    mov di, [ci_heap_top]
    xor dx, dx
    cmp byte [tok_type], '='
    jne .arr_fill
    call ci_lex
    EXPECT '{'
    cmp byte [tok_type], '}'
    je .init_end
.init_loop:
    push ecx
    push di
    push dx
    call ci_expr
    pop dx
    pop di
    pop ecx
    cmp byte [ci_exec], 0
    je .init_skip
    mov bx, dx
    shl bx, 2
    add bx, di
    cmp bx, CI_HEAP_END - 4
    ja .mem_err
    mov [bx], eax
.init_skip:
    inc dx
    cmp byte [tok_type], ','
    jne .init_end
    call ci_lex
    jmp .init_loop
.init_end:
    EXPECT '}'
.arr_fill:
    test ecx, ecx
    jnz .have_len
    movzx ecx, dx
.have_len:
    cmp byte [ci_exec], 0
    je .next
    cmp ecx, 0
    jle .size_err
    cmp ecx, 1024
    jg .size_err
    movzx ebx, dx
    cmp ecx, ebx
    jb .size_err
    mov bx, cx
    shl bx, 2
    add bx, di
    cmp bx, CI_HEAP_END
    ja .mem_err
    mov bx, dx
.zero:
    cmp bx, cx
    jae .zdone
    push bx
    shl bx, 2
    add bx, di
    mov dword [bx], 0
    pop bx
    inc bx
    jmp .zero
.zdone:
    mov si, sp
    xor eax, eax
    call ci_add_var
    mov ax, [ci_tmp_dim2]
    mov [bx+16], ax
    mov [bx+20], di
    mov [bx+22], cx
    shl cx, 2
    add [ci_heap_top], cx

.next:
    add sp, 16
    cmp byte [tok_type], ','
    jne .end
    call ci_lex
    jmp ci_decl_rest
.end:
    EXPECT ';'
    ret
.ptr_err:
    mov si, ci_e_ptr
    jmp ci_error
.name_err:
    mov si, ci_e_name
    jmp ci_error
.size_err:
    mov si, ci_e_size
    jmp ci_error
.mem_err:
    mov si, ci_e_mem
    jmp ci_error

ci_if:
    call ci_lex
    EXPECT '('
    call ci_expr
    EXPECT ')'
    mov bl, [ci_exec]
    test bl, bl
    jz .skip_then
    test eax, eax
    jz .skip_then
    call ci_statement
    cmp byte [tok_type], K_ELSE
    jne .done
    call ci_lex
    mov bl, [ci_exec]
    push bx
    mov byte [ci_exec], 0
    call ci_statement
    pop bx
    mov [ci_exec], bl
.done:
    ret
.skip_then:
    push bx
    mov byte [ci_exec], 0
    call ci_statement
    pop bx
    mov [ci_exec], bl
    cmp byte [tok_type], K_ELSE
    jne .done
    call ci_lex
    jmp ci_statement

ci_while:
    call ci_lex
    mov al, [ci_exec]
    push ax                     ; [sp+2] = lagret exec
    push word [tok_start]       ; [sp]   = posisjon til '('
.loop:
    call ci_check_abort
    mov bx, sp
    mov ax, [bx]
    call ci_lex_at
    EXPECT '('
    call ci_expr
    EXPECT ')'
    mov bx, sp
    cmp byte [bx+2], 0
    je .skip_body
    test eax, eax
    jz .skip_body
    call ci_statement
    mov al, [ci_ctl]
    cmp al, 2
    je .brk
    cmp al, 1
    je .exit
    cmp al, 3
    jne .loop
    mov byte [ci_ctl], 0
    mov byte [ci_exec], 1
    jmp .loop
.brk:
    mov byte [ci_ctl], 0
    mov byte [ci_exec], 1
    jmp .exit
.skip_body:
    mov byte [ci_exec], 0
    call ci_statement
    mov bx, sp
    mov al, [bx+2]
    mov [ci_exec], al
.exit:
    add sp, 4
    ret

ci_do:
    call ci_lex                 ; hopp over 'do'
    mov al, [ci_exec]
    push ax                     ; [sp+2] = lagret exec
    push word [tok_start]       ; [sp]   = posisjon til do-kropp
.loop:
    call ci_check_abort
    mov bx, sp
    mov ax, [bx]
    call ci_lex_at
    call ci_statement
    mov al, [ci_ctl]
    cmp al, 2                   ; break
    je .brk
    cmp al, 1                   ; return
    je .ret_exit
    cmp al, 3                   ; continue
    jne .check_while
    mov byte [ci_ctl], 0
    mov byte [ci_exec], 1
.check_while:
    cmp byte [tok_type], K_WHILE
    jne .err_while
    call ci_lex
    EXPECT '('
    call ci_expr
    EXPECT ')'
    EXPECT ';'
    mov bx, sp
    cmp byte [bx+2], 0          ; opprinnelig exec
    je .exit
    test eax, eax
    jnz .loop
    jmp .exit
.brk:
    mov byte [ci_ctl], 0
    mov byte [ci_exec], 0
    jmp .check_while
.ret_exit:
    mov byte [ci_exec], 0
    jmp .check_while
.err_while:
    mov si, ci_e_while
    jmp ci_error
.exit:
    mov bx, sp
    mov al, [bx+2]
    mov [ci_exec], al
    add sp, 4
    ret

ci_for:
    call ci_lex
    EXPECT '('
    mov al, [ci_exec]
    push ax                     ; [sp+6] = lagret exec
    push word [ci_var_count]    ; [sp+4]
    push word [ci_heap_top]     ; [sp+2]
    cmp byte [tok_type], ';'
    je .init_empty
    call ci_consume_type
    jnc .init_decl
    call ci_expr
    EXPECT ';'
    jmp .init_done
.init_decl:
    mov [ci_cur_decl_type], al
    call ci_decl_rest
    jmp .init_done
.init_empty:
    call ci_lex
.init_done:
    push word [tok_start]       ; [sp] = posisjon til betingelse
.loop:
    call ci_check_abort
    mov bx, sp
    mov ax, [bx]
    call ci_lex_at
    mov eax, 1
    cmp byte [tok_type], ';'
    je .cond_empty
    call ci_expr
.cond_empty:
    EXPECT ';'
    push eax
    push word [tok_start]       ; posisjon til steg-uttrykket
    mov al, [ci_exec]
    push ax
    mov byte [ci_exec], 0
    cmp byte [tok_type], ')'
    je .step_skipped
    call ci_expr
.step_skipped:
    EXPECT ')'
    pop ax
    mov [ci_exec], al
    pop dx
    pop eax
    mov bx, sp
    cmp byte [bx+6], 0
    je .skip_body
    test eax, eax
    jz .skip_body
    push dx
    call ci_statement
    pop dx
    mov al, [ci_ctl]
    cmp al, 2
    je .brk
    cmp al, 1
    je .exit
    cmp al, 3
    jne .step
    mov byte [ci_ctl], 0
    mov byte [ci_exec], 1
.step:
    mov ax, dx
    call ci_lex_at
    cmp byte [tok_type], ')'
    je .loop
    call ci_expr
    jmp .loop
.brk:
    mov byte [ci_ctl], 0
    mov byte [ci_exec], 1
    jmp .exit
.skip_body:
    mov byte [ci_exec], 0
    call ci_statement
    mov bx, sp
    mov al, [bx+6]
    mov [ci_exec], al
.exit:
    add sp, 2
    pop word [ci_heap_top]
    pop word [ci_var_count]
    add sp, 2
    ret

ci_return:
    call ci_lex
    xor eax, eax
    cmp byte [tok_type], ';'
    je .noval
    call ci_expr
.noval:
    EXPECT ';'
    cmp byte [ci_exec], 0
    je .r
    mov [ci_ret], eax
    mov byte [ci_ctl], 1
    mov byte [ci_exec], 0
.r:
    ret

; ------------------------------------------------------------------------------
; Uttrykk (resultat i EAX, [ci_lv] = adresse hvis uttrykket er en lvalue)
; ------------------------------------------------------------------------------
ci_expr:
ci_assign:
    call ci_lor
    mov bl, [tok_type]
    cmp bl, '='
    je .as
    cmp bl, T_ADDEQ
    jb .ret
    cmp bl, T_MODEQ
    ja .ret
.as:
    mov di, [ci_lv]
    test di, di
    jz .err
    push di
    push bx
    push word [ci_is_float]
    push eax
    call ci_lex
    call ci_assign
    mov ecx, eax
    pop eax
    pop dx
    pop bx
    pop di
    cmp bl, '='
    jne .not_simple_as
    mov eax, ecx
    jmp .store
.not_simple_as:
    mov dh, [ci_is_float]
    or dl, dh
    jz .int_compound
    mov byte [ci_is_float], 1
    call ci_to_float
    call ci_ecx_to_float
    mov [ci_f_tmp1], eax
    mov [ci_f_tmp2], ecx
    fld dword [ci_f_tmp1]
    cmp bl, T_ADDEQ
    jne .fc_sub
    fadd dword [ci_f_tmp2]
    jmp .fc_done
.fc_sub:
    cmp bl, T_SUBEQ
    jne .fc_mul
    fsub dword [ci_f_tmp2]
    jmp .fc_done
.fc_mul:
    cmp bl, T_MULEQ
    jne .fc_div
    fmul dword [ci_f_tmp2]
    jmp .fc_done
.fc_div:
    fdiv dword [ci_f_tmp2]
.fc_done:
    fstp dword [ci_f_tmp1]
    mov eax, [ci_f_tmp1]
    jmp .store
.int_compound:
    mov byte [ci_is_float], 0
    cmp bl, T_ADDEQ
    jne .n2
    add eax, ecx
    jmp .store
.n2:
    cmp bl, T_SUBEQ
    jne .n3
    sub eax, ecx
    jmp .store
.n3:
    cmp bl, T_MULEQ
    jne .n4
    imul eax, ecx
    jmp .store
.n4:
    cmp byte [ci_exec], 0
    je .store
    test ecx, ecx
    jz ci_div_zero
    cdq
    idiv ecx
    cmp bl, T_MODEQ
    jne .store
    mov eax, edx
.store:
    cmp byte [ci_exec], 0
    je .nost
    mov [di], eax
.nost:
    mov word [ci_lv], 0
.ret:
    ret
.err:
    mov si, ci_e_lvalue
    jmp ci_error

ci_lor:
    call ci_land
.l:
    cmp byte [tok_type], T_OR
    jne .r
    call ci_lex
    test eax, eax
    jnz .skipright
    call ci_land
    jmp .bool
.skipright:
    mov bl, [ci_exec]
    push bx
    mov byte [ci_exec], 0
    call ci_land
    pop bx
    mov [ci_exec], bl
    mov eax, 1
.bool:
    test eax, eax
    setnz al
    movzx eax, al
    mov word [ci_lv], 0
    mov word [ci_is_float], 0
    jmp .l
.r:
    ret

ci_land:
    call ci_equality
.l:
    cmp byte [tok_type], T_AND
    jne .r
    call ci_lex
    test eax, eax
    jz .skipright
    call ci_equality
    jmp .bool
.skipright:
    mov bl, [ci_exec]
    push bx
    mov byte [ci_exec], 0
    call ci_equality
    pop bx
    mov [ci_exec], bl
    xor eax, eax
.bool:
    test eax, eax
    setnz al
    movzx eax, al
    mov word [ci_lv], 0
    mov word [ci_is_float], 0
    jmp .l
.r:
    ret

ci_equality:
    call ci_relational
.l:
    mov bl, [tok_type]
    cmp bl, T_EQ
    je .op
    cmp bl, T_NE
    je .op
    ret
.op:
    push bx
    push word [ci_is_float]
    push eax
    call ci_lex
    call ci_relational
    mov ecx, eax
    pop eax
    pop dx
    pop bx
    mov dh, [ci_is_float]
    or dl, dh
    jz .int_eq
    mov word [ci_is_float], 0
    call ci_to_float
    call ci_ecx_to_float
    mov [ci_f_tmp1], eax
    mov [ci_f_tmp2], ecx
    fld dword [ci_f_tmp2]
    fld dword [ci_f_tmp1]
    fcompp
    fstsw ax
    sahf
    pushf
    cmp bl, T_EQ
    je .feq
    popf
    jne .ftrue
    jmp .ffalse
.feq:
    popf
    je .ftrue
    jmp .ffalse
.ftrue:
    mov eax, 1
    mov word [ci_lv], 0
    mov word [ci_is_float], 0
    jmp .l
.ffalse:
    xor eax, eax
    mov word [ci_lv], 0
    mov word [ci_is_float], 0
    jmp .l
.int_eq:
    mov word [ci_is_float], 0
    cmp eax, ecx
    sete al
    movzx eax, al
    cmp bl, T_NE
    jne .s
    xor eax, 1
.s:
    mov word [ci_lv], 0
    mov word [ci_is_float], 0
    jmp .l

ci_to_float:
    test dl, dl
    jnz .done
    mov [ci_f_tmp1], eax
    fild dword [ci_f_tmp1]
    fstp dword [ci_f_tmp1]
    mov eax, [ci_f_tmp1]
.done:
    ret

ci_ecx_to_float:
    test dh, dh
    jnz .done
    mov [ci_f_tmp2], ecx
    fild dword [ci_f_tmp2]
    fstp dword [ci_f_tmp2]
    mov ecx, [ci_f_tmp2]
.done:
    ret

ci_int_to_float:
    mov [ci_f_tmp1], eax
    fild dword [ci_f_tmp1]
    fstp dword [ci_f_tmp1]
    mov eax, [ci_f_tmp1]
    ret

ci_float_to_int:
    mov [ci_f_tmp1], eax
    fld dword [ci_f_tmp1]
    fldcw [ci_fpu_cw_trunc]
    fistp dword [ci_f_tmp1]
    fldcw [ci_fpu_cw]
    mov eax, [ci_f_tmp1]
    ret

ci_format_float:
    push di
    push si
    push bx
    push cx
    push dx
    mov di, ci_fmt_buf
    mov [ci_f_tmp1], ebx
    fld dword [ci_f_tmp1]
    ftst
    fstsw ax
    sahf
    jnc .f_pos
    mov byte [di], '-'
    inc di
    fchs
.f_pos:
    fldcw [ci_fpu_cw_trunc]
    fist dword [ci_f_tmp1]
    fild dword [ci_f_tmp1]
    fsubp st1, st0
    fldcw [ci_fpu_cw]
    mov eax, [ci_f_tmp1]
    call num_to_dec
.cpy_int:
    lodsb
    test al, al
    jz .dot
    stosb
    jmp .cpy_int
.dot:
    mov byte [di], '.'
    inc di
    mov cx, [ci_p_prec]
    cmp cx, 0
    je .f_pop
    cmp cx, 8
    jbe .prec_ok
    mov cx, 6
.prec_ok:
.f_loop:
    fmul dword [ci_f_ten]
    fldcw [ci_fpu_cw_trunc]
    fist dword [ci_f_tmp2]
    fild dword [ci_f_tmp2]
    fsubp st1, st0
    fldcw [ci_fpu_cw]
    mov al, byte [ci_f_tmp2]
    add al, '0'
    stosb
    loop .f_loop
.f_pop:
    fstp st0
    mov byte [di], 0
    pop dx
    pop cx
    pop bx
    pop si
    pop di
    ret

ci_strlen_buf:
    push si
    xor ax, ax
.l:
    cmp byte [si], 0
    je .d
    inc si
    inc ax
    jmp .l
.d:
    pop si
    ret

ci_relational:
    call ci_additive
.l:
    mov bl, [tok_type]
    cmp bl, '<'
    je .op
    cmp bl, '>'
    je .op
    cmp bl, T_LE
    je .op
    cmp bl, T_GE
    je .op
    ret
.op:
    push bx
    push word [ci_is_float]
    push eax
    call ci_lex
    call ci_additive
    mov ecx, eax
    pop eax
    pop dx
    pop bx
    mov dh, [ci_is_float]
    or dl, dh
    jz .int_rel
    mov byte [ci_is_float], 0
    call ci_to_float
    call ci_ecx_to_float
    mov [ci_f_tmp1], eax
    mov [ci_f_tmp2], ecx
    fld dword [ci_f_tmp2]
    fld dword [ci_f_tmp1]
    fcompp
    fstsw ax
    sahf
    pushf
    cmp bl, '<'
    je .f_lt
    cmp bl, '>'
    je .f_gt
    cmp bl, T_LE
    je .f_le
    popf
    jae .f_true
    jmp .f_false
.f_lt:
    popf
    jb .f_true
    jmp .f_false
.f_gt:
    popf
    ja .f_true
    jmp .f_false
.f_le:
    popf
    jbe .f_true
    jmp .f_false
    jmp .f_false
.f_true:
    mov eax, 1
    mov word [ci_lv], 0
    mov word [ci_is_float], 0
    jmp .l
.f_false:
    xor eax, eax
    mov word [ci_lv], 0
    mov word [ci_is_float], 0
    jmp .l
.int_rel:
    mov byte [ci_is_float], 0
    cmp bl, '<'
    je .lt
    cmp bl, '>'
    je .gt
    cmp bl, T_LE
    je .le
    cmp eax, ecx
    setge al
    jmp .s
.lt:
    cmp eax, ecx
    setl al
    jmp .s
.gt:
    cmp eax, ecx
    setg al
    jmp .s
.le:
    cmp eax, ecx
    setle al
.s:
    movzx eax, al
    mov word [ci_lv], 0
    mov word [ci_is_float], 0
    jmp .l

ci_additive:
    call ci_multiplicative
.l:
    mov bl, [tok_type]
    cmp bl, '+'
    je .op
    cmp bl, '-'
    je .op
    ret
.op:
    push bx
    push word [ci_is_float]
    push eax
    call ci_lex
    call ci_multiplicative
    mov ecx, eax
    pop eax
    pop dx
    pop bx
    mov dh, [ci_is_float]
    or dl, dh
    jz .int_add
    mov byte [ci_is_float], 1
    call ci_to_float
    call ci_ecx_to_float
    mov [ci_f_tmp1], eax
    mov [ci_f_tmp2], ecx
    fld dword [ci_f_tmp1]
    cmp bl, '+'
    jne .f_sub
    fadd dword [ci_f_tmp2]
    jmp .f_add_end
.f_sub:
    fsub dword [ci_f_tmp2]
.f_add_end:
    fstp dword [ci_f_tmp1]
    mov eax, [ci_f_tmp1]
    mov word [ci_lv], 0
    jmp .l
.int_add:
    mov byte [ci_is_float], 0
    cmp bl, '+'
    jne .sub
    add eax, ecx
    jmp .s
.sub:
    sub eax, ecx
.s:
    mov word [ci_lv], 0
    jmp .l

ci_multiplicative:
    call ci_unary
.l:
    mov bl, [tok_type]
    cmp bl, '*'
    je .op
    cmp bl, '/'
    je .op
    cmp bl, '%'
    je .op
    ret
.op:
    push bx
    push word [ci_is_float]
    push eax
    call ci_lex
    call ci_unary
    mov ecx, eax
    pop eax
    pop dx
    pop bx
    mov dh, [ci_is_float]
    or dl, dh
    jz .int_mul
    cmp bl, '%'
    je .int_mul
    mov byte [ci_is_float], 1
    call ci_to_float
    call ci_ecx_to_float
    mov [ci_f_tmp1], eax
    mov [ci_f_tmp2], ecx
    fld dword [ci_f_tmp1]
    cmp bl, '*'
    jne .f_div
    fmul dword [ci_f_tmp2]
    jmp .f_mul_end
.f_div:
    fdiv dword [ci_f_tmp2]
.f_mul_end:
    fstp dword [ci_f_tmp1]
    mov eax, [ci_f_tmp1]
    mov word [ci_lv], 0
    jmp .l
.int_mul:
    mov byte [ci_is_float], 0
    cmp bl, '*'
    jne .div
    imul eax, ecx
    jmp .s
.div:
    cmp byte [ci_exec], 0
    jne .dv
    xor eax, eax
    jmp .s
.dv:
    test ecx, ecx
    jz ci_div_zero
    cdq
    idiv ecx
    cmp bl, '%'
    jne .s
    mov eax, edx
.s:
    mov word [ci_lv], 0
    jmp .l

ci_unary:
    mov bl, [tok_type]
    cmp bl, '-'
    je .neg
    cmp bl, '+'
    je .pos
    cmp bl, '!'
    je .not
    cmp bl, '*'
    je .deref
    cmp bl, '&'
    je .addrof
    cmp bl, T_INC
    je .pre
    cmp bl, T_DEC
    je .pre
    jmp ci_primary
.deref:
    call ci_lex
    call ci_unary
    cmp byte [ci_exec], 0
    je .deref_skip
    mov di, ax
    mov eax, [di]
    mov [ci_lv], di
    ret
.deref_skip:
    mov di, ci_dummy
    xor eax, eax
    mov [ci_lv], di
    ret
.addrof:
    call ci_lex
    call ci_unary
    mov ax, [ci_lv]
    test ax, ax
    jz .err
    movzx eax, ax
    mov word [ci_lv], 0
    ret
.neg:
    call ci_lex
    call ci_unary
    neg eax
    mov word [ci_lv], 0
    ret
.pos:
    call ci_lex
    call ci_unary
    mov word [ci_lv], 0
    ret
.not:
    call ci_lex
    call ci_unary
    test eax, eax
    setz al
    movzx eax, al
    mov word [ci_lv], 0
    ret
.pre:
    push bx
    call ci_lex
    call ci_unary
    pop bx
    mov di, [ci_lv]
    test di, di
    jz .err
    cmp bl, T_INC
    jne .d
    inc eax
    jmp .st
.d:
    dec eax
.st:
    cmp byte [ci_exec], 0
    je .ns
    mov [di], eax
.ns:
    mov word [ci_lv], 0
    ret
.err:
    mov si, ci_e_lvalue
    jmp ci_error

is_type_token:
    mov al, [tok_type]
    cmp al, K_INT
    jb .it_no
    cmp al, K_VOID
    jbe .it_yes
    cmp al, K_DOUBLE
    jb .it_no
    cmp al, K_ENUM
    jbe .it_yes
.it_no:
    clc
    ret
.it_yes:
    stc
    ret

ci_primary:
    mov bl, [tok_type]
    cmp bl, T_FLOAT
    jne .n_flt
    mov eax, [tok_num]
    call ci_lex
    mov byte [ci_is_float], 1
    mov word [ci_lv], 0
    ret
.n_flt:
    cmp bl, T_NUM
    jne .n1
    mov eax, [tok_num]
    call ci_lex
    mov byte [ci_is_float], 0
    mov word [ci_lv], 0
    ret
.n1:
    cmp bl, T_STR
    jne .n2
    movzx eax, word [tok_sptr]
    call ci_lex
    mov word [ci_lv], 0
    ret
.n2:
    cmp bl, '('
    jne .n3
    call ci_lex
    call is_type_token
    jc .is_cast
    call ci_expr
    EXPECT ')'
    mov word [ci_lv], 0
    mov di, ci_dummy
    jmp .postfix_loop

.is_cast:
    call ci_consume_type
    push ax                     ; AL = basetype, AH = ptr flag
    EXPECT ')'
    call ci_unary               ; evaluer uttrykket som kastes
    pop cx                      ; CL = basetype, CH = ptr flag
    test ch, ch
    jnz .cast_int               ; enhver peker er et heltall (adresse)
    cmp cl, K_VOID
    je .cast_void
    cmp cl, K_DOUBLE
    je .cast_flt
    cmp cl, K_FLOAT
    je .cast_flt
.cast_int:
    cmp byte [ci_is_float], 0
    je .cast_done
    call ci_float_to_int
    mov byte [ci_is_float], 0
    jmp .cast_done
.cast_flt:
    cmp byte [ci_is_float], 0
    jne .cast_done
    call ci_int_to_float
    mov byte [ci_is_float], 1
    jmp .cast_done
.cast_void:
    xor eax, eax
    mov byte [ci_is_float], 0
.cast_done:
    mov word [ci_lv], 0
    ret
.n3:
    cmp bl, T_IDENT
    jne .err
    sub sp, 16
    mov di, sp
    mov si, tok_name
    call copy_str
    call ci_lex
    cmp byte [tok_type], '('
    je .call
    mov si, sp
    call ci_var_ref
    add sp, 16
    jmp .postfix_loop
.call:
    mov si, sp
    call ci_call
    add sp, 16
    mov word [ci_lv], 0
    mov di, ci_dummy
    jmp .postfix_loop

.postfix_loop:
    mov bl, [tok_type]
    cmp bl, '.'
    je .post_dot
    cmp bl, T_ARROW
    je .post_arrow
    cmp bl, '['
    je .post_index
    cmp bl, T_INC
    je .post_inc
    cmp bl, T_DEC
    je .post_dec
    mov [ci_lv], di
    ret

.post_dot:
    call ci_lex                 ; spis '.'
    cmp byte [tok_type], T_IDENT
    jne .err_name
    call ci_lex                 ; spis medlemsnavn
    cmp byte [ci_exec], 0
    jne .post_dot_live
    mov di, ci_dummy
    xor eax, eax
    jmp .postfix_loop
.post_dot_live:
    test di, di
    jnz .post_dot_ok
    mov di, ci_dummy
    xor eax, eax
    jmp .postfix_loop
.post_dot_ok:
    mov eax, [di]
    jmp .postfix_loop

.post_arrow:
    call ci_lex                 ; spis '->'
    cmp byte [tok_type], T_IDENT
    jne .err_name
    call ci_lex                 ; spis medlemsnavn
    cmp byte [ci_exec], 0
    jne .post_arrow_live
    mov di, ci_dummy
    xor eax, eax
    jmp .postfix_loop
.post_arrow_live:
    test eax, eax
    jz .post_arrow_null
    mov di, ax
    mov eax, [di]
    jmp .postfix_loop
.post_arrow_null:
    mov di, ci_dummy
    xor eax, eax
    jmp .postfix_loop

.post_index:
    push di
    push eax
    call ci_lex                 ; spis '['
    call ci_expr
    EXPECT ']'
    pop edx
    pop di
    cmp byte [ci_exec], 0
    jne .post_idx_live
    mov di, ci_dummy
    xor eax, eax
    jmp .postfix_loop
.post_idx_live:
    test edx, edx
    jz .post_idx_use_di
    mov di, dx
.post_idx_use_di:
    test di, di
    jz .post_idx_null
    shl ax, 2
    add di, ax
    mov eax, [di]
    jmp .postfix_loop
.post_idx_null:
    mov di, ci_dummy
    xor eax, eax
    jmp .postfix_loop

.post_inc:
    call ci_lex
    mov ecx, eax
    inc ecx
    cmp byte [ci_exec], 0
    je .pn_inc
    test di, di
    jz .pn_inc
    mov [di], ecx
.pn_inc:
    mov word [ci_lv], 0
    ret

.post_dec:
    call ci_lex
    mov ecx, eax
    dec ecx
    cmp byte [ci_exec], 0
    je .pn_dec
    test di, di
    jz .pn_dec
    mov [di], ecx
.pn_dec:
    mov word [ci_lv], 0
    ret

.err_name:
    mov si, ci_e_name
    jmp ci_error
.err:
    cmp bl, T_EOF
    je .eof
    mov si, ci_e_unexpected
    jmp ci_error
.eof:
    mov si, ci_e_eof
    jmp ci_error

; SI = variabelnavn -> DI = adresse til verdien, EAX = verdi
ci_var_ref:
    cmp byte [ci_exec], 0
    jne .live
    cmp byte [tok_type], '['
    jne .dum
    call ci_lex
    call ci_expr
    EXPECT ']'
    cmp byte [tok_type], '['
    jne .dum
    call ci_lex
    call ci_expr
    EXPECT ']'
.dum:
    mov di, ci_dummy
    xor eax, eax
    ret
.live:
    call ci_find_var
    jnc .have_v
    call ci_find_func
    jc .undef
    mov eax, ebx
    mov byte [ci_is_float], 0
    mov di, ci_dummy
    mov word [ci_lv], 0
    ret
.have_v:
    cmp byte [bx+15], 2
    sete al
    mov [ci_is_float], al
    cmp word [bx+20], 0
    jne .array
    cmp byte [tok_type], '['
    je .ptr_idx
    lea di, [bx+16]
    mov eax, [di]
    ret
.ptr_idx:
    push bx
    call ci_lex
    call ci_expr
    EXPECT ']'
    pop bx
    cmp byte [ci_exec], 0
    je .ptr_dum
    mov di, [bx+16]
    shl ax, 2
    add di, ax
    mov eax, [di]
    ret
.ptr_dum:
    mov di, ci_dummy
    xor eax, eax
    ret
.array:
    cmp byte [tok_type], '['
    jne .bare_arr
    push bx
    call ci_lex
    call ci_expr
    EXPECT ']'
    pop bx
    cmp byte [tok_type], '['
    jne .idx_1d
    push bx
    push eax                    ; lagre i (rad)
    call ci_lex
    call ci_expr                ; EAX = j (kolonne)
    EXPECT ']'
    pop edx                     ; EDX = i
    pop bx
    movzx ecx, word [bx+16]     ; ECX = dim2 (kolonner)
    test ecx, ecx
    jnz .have_stride
    mov ecx, 1
.have_stride:
    imul edx, ecx
    add eax, edx                ; EAX = i * dim2 + j
.idx_1d:
    cmp eax, 0
    jl .bounds
    movzx ecx, word [bx+22]
    cmp eax, ecx
    jge .bounds
    mov di, [bx+20]
    shl ax, 2
    add di, ax
    mov eax, [di]
    ret
.bare_arr:
    mov di, [bx+20]
    movzx eax, di
    mov word [ci_lv], 0
    ret
.undef:
    mov bx, ci_e_undef
    jmp ci_error_name
.notarr:
    mov bx, ci_e_notarr
    jmp ci_error_name
.noidx:
    mov bx, ci_e_noidx
    jmp ci_error_name
.bounds:
    mov si, ci_e_bounds
    jmp ci_error

; ------------------------------------------------------------------------------
; Funksjonskall. SI = navn, tok = '('
; ------------------------------------------------------------------------------
ci_call:
    mov di, ci_s_printf
    call str_equals
    je ci_printf
    mov di, ci_s_putchar
    call str_equals
    je ci_putchar
    mov di, ci_s_puts
    call str_equals
    je ci_puts

    push si
    call ci_lex
    xor cx, cx
    xor dx, dx                  ; DL = float mask
    cmp byte [tok_type], ')'
    je .args_done
.arg_loop:
    push dx
    push cx
    call ci_expr
    pop cx
    pop dx
    cmp byte [ci_is_float], 0
    je .arg_not_flt
    bts dx, cx
.arg_not_flt:
    push eax
    inc cx
    cmp cx, 8
    ja .too_many
    cmp byte [tok_type], ','
    jne .args_done
    call ci_lex
    jmp .arg_loop
.args_done:
    push dx                     ; bevar float bitmask for EXPECT
    EXPECT ')'
    pop dx                      ; gjenopprett float bitmask
    cmp byte [ci_exec], 0
    jne .do_call
    shl cx, 2
    add sp, cx
    pop si
    xor eax, eax
    ret

.do_call:
    call ci_check_abort
    mov bp, sp
    mov si, cx
    shl si, 2
    mov si, [bp+si]
    call ci_find_func
    jnc .have_fn
    call ci_find_var
    jc .nofunc
    cmp byte [bx+15], 3
    jne .nofunc
    mov bx, [bx+16]
.have_fn:
    push dx                     ; [bp-2]: float bitmask for argumenter
    push word [bx+18]
    push word [tok_start]
    push word [ci_frame_base]
    push word [ci_var_count]
    push word [ci_heap_top]
    push cx
    mov ax, [ci_var_count]
    mov [ci_frame_base], ax
    mov ax, [bx+16]
    call ci_lex_at
    EXPECT '('
    xor dx, dx
    cmp byte [tok_type], K_VOID
    jne .pchk
    call ci_lex
.pchk:
    cmp byte [tok_type], ')'
    je .params_done
.param_loop:
.p_qloop:
    mov al, [tok_type]
    cmp al, K_CONST
    je .p_qskip
    cmp al, K_VOLATILE
    je .p_qskip
    cmp al, K_REGISTER
    je .p_qskip
    cmp al, K_AUTO
    je .p_qskip
    cmp al, K_SIGNED
    je .p_qskip
    cmp al, K_STATIC
    je .p_qskip
    cmp al, K_UNSIGNED
    jne .p_chktype
    call ci_lex
    jmp .p_chktype
.p_qskip:
    call ci_lex
    jmp .p_qloop
.p_chktype:
    mov al, [tok_type]
    cmp al, K_LONG
    je .p_as_int
    cmp al, K_SHORT
    je .p_as_int
    cmp al, K_BOOL
    je .p_as_int
    cmp al, K_STRUCT
    je .p_as_struct
    cmp al, K_UNION
    je .p_as_struct
    cmp al, K_ENUM
    je .p_as_struct
    cmp al, T_IDENT
    je .p_as_typedef
    jmp .p_std
.p_as_typedef:
    call ci_lex
    mov al, K_INT
    mov [ci_cur_decl_type], al
    jmp .p_after_eat
.p_as_int:
    mov al, K_INT
.p_std:
    mov [ci_cur_decl_type], al
    cmp al, K_INT
    je .ptype
    cmp al, K_CHAR
    je .ptype
    cmp al, K_DOUBLE
    je .ptype
    cmp al, K_FLOAT
    je .ptype
    cmp al, K_VOID
    je .ptype
    jne .err_param
.p_as_struct:
    call ci_lex
    cmp byte [tok_type], T_IDENT
    jne .err_param
    call ci_lex
    mov al, K_INT
    mov [ci_cur_decl_type], al
    jmp .p_after_eat
.ptype:
    call ci_lex
.p_eat_extra:
    cmp byte [tok_type], K_LONG
    je .p_do_eat
    cmp byte [tok_type], K_INT
    jne .p_after_eat
.p_do_eat:
    call ci_lex
    jmp .p_eat_extra
.p_after_eat:
    cmp byte [tok_type], '('
    jne .pnot_fnp
    call ci_lex
    cmp byte [tok_type], '*'
    jne .err_param
    call ci_lex
    cmp byte [tok_type], T_IDENT
    jne .err_param
    mov bx, cx
    sub bx, dx
    dec bx
    js .err_args
    shl bx, 2
    add bx, bp
    mov eax, [bx]
    mov si, tok_name
    call ci_add_var
    mov byte [bx+15], 3
    call ci_lex
    EXPECT ')'
    call ci_skip_parens
    inc dx
    cmp byte [tok_type], ','
    jne .params_done
    call ci_lex
    jmp .param_loop
.pnot_fnp:
.pnot_ptr_loop:
    cmp byte [tok_type], '*'
    jne .pnot_ptr
    call ci_lex
    jmp .pnot_ptr_loop
.pnot_ptr:
    cmp byte [tok_type], T_IDENT
    jne .err_param
    mov bx, cx
    sub bx, dx
    dec bx
    js .err_args
    shl bx, 2
    add bx, bp
    mov eax, [bx]
    push bx
    mov bx, [bp-2]              ; bx = float bitmask
    bt bx, dx                   ; test bit DX (parameter-indeks!)
    pop bx
    jc .arg_was_flt

    ; Argument var heltall:
    cmp byte [ci_cur_decl_type], K_DOUBLE
    je .arg_to_flt
    cmp byte [ci_cur_decl_type], K_FLOAT
    jne .p_do_store
.arg_to_flt:
    call ci_int_to_float
    jmp .p_do_store

.arg_was_flt:
    ; Argument var flyttall:
    cmp byte [ci_cur_decl_type], K_DOUBLE
    je .p_do_store
    cmp byte [ci_cur_decl_type], K_FLOAT
    je .p_do_store
    call ci_float_to_int

.p_do_store:
    mov si, tok_name
    call ci_add_var
    cmp byte [ci_cur_decl_type], K_DOUBLE
    je .p_set_flt
    cmp byte [ci_cur_decl_type], K_FLOAT
    je .p_set_flt
    jmp .p_var_done
.p_set_flt:
    mov byte [bx+15], 2
.p_var_done:
    call ci_lex
    cmp byte [tok_type], '['
    jne .pnot_arr
    call ci_lex
    EXPECT ']'
.pnot_arr:
    inc dx
    cmp byte [tok_type], ','
    jne .params_done
    call ci_lex
    jmp .param_loop
.params_done:
    cmp dx, cx
    jne .err_args
    EXPECT ')'
    cmp byte [tok_type], '{'
    jne .err_body
    push bp
    call ci_statement
    pop bp
    xor eax, eax
    cmp byte [ci_ctl], 1
    jne .noret
    mov eax, [ci_ret]
.noret:
    mov byte [ci_ctl], 0
    mov byte [ci_exec], 1
    pop cx
    pop word [ci_heap_top]
    pop word [ci_var_count]
    pop word [ci_frame_base]
    pop bx
    pop dx
    add sp, 2                   ; fjern dx (float bitmask)
    push eax
    mov ax, bx
    call ci_lex_at
    pop eax
    shl cx, 2
    add sp, cx
    pop si
    cmp dl, K_DOUBLE
    je .ret_is_flt
    cmp dl, K_FLOAT
    je .ret_is_flt
    mov byte [ci_is_float], 0
    ret
.ret_is_flt:
    mov byte [ci_is_float], 1
    ret
.too_many:
    mov si, ci_e_args
    jmp ci_error
.nofunc:
    mov bx, ci_e_nofunc
    jmp ci_error_name
.err_param:
    mov si, ci_e_param
    jmp ci_error
.err_args:
    mov si, ci_e_args
    jmp ci_error
.err_body:
    mov si, ci_e_body
    jmp ci_error

; printf("format", argumenter...)
ci_printf:
    call ci_lex
    cmp byte [tok_type], T_STR
    jne .err_fmt
    push word [tok_sptr]
    call ci_lex
    xor cx, cx
.args:
    cmp byte [tok_type], ','
    jne .end_args
    call ci_lex
    push cx
    call ci_expr
    pop cx
    push eax
    inc cx
    cmp cx, 8
    ja .too_many
    jmp .args
.end_args:
    EXPECT ')'
    mov bp, sp
    mov si, cx
    shl si, 2
    mov si, [bp+si]
    cmp byte [ci_exec], 0
    je .cleanup
    xor dx, dx
.fmt_loop:
    mov al, [si]
    inc si
    cmp al, '"'
    je .cleanup
    test al, al
    jz .cleanup
    cmp al, '\'
    jne .not_esc
    mov al, [si]
    inc si
    call ci_escape
    call ci_outc
    jmp .fmt_loop
.not_esc:
    cmp al, '%'
    je .pct
    call ci_outc
    jmp .fmt_loop
.pct:
    xor di, di
    mov byte [ci_p_left], 0
    mov word [ci_p_prec], 6
    cmp byte [si], '-'
    jne .chk_w
    mov byte [ci_p_left], 1
    inc si
.chk_w:
    mov al, [si]
    cmp al, '0'
    jb .chk_dot
    cmp al, '9'
    ja .chk_dot
    imul di, di, 10
    sub al, '0'
    movzx ax, al
    add di, ax
    inc si
    jmp .chk_w
.chk_dot:
    cmp byte [si], '.'
    jne .wd
    inc si
    xor ax, ax
.prec_w:
    mov bl, [si]
    cmp bl, '0'
    jb .prec_done
    cmp bl, '9'
    ja .prec_done
    imul ax, ax, 10
    sub bl, '0'
    movzx bx, bl
    add ax, bx
    inc si
    jmp .prec_w
.prec_done:
    mov [ci_p_prec], ax
.wd:
    mov [ci_p_width], di
    mov al, [si]
    inc si
    cmp al, '%'
    jne .arg
    call ci_outc
    jmp .fmt_loop
.arg:
    cmp dx, cx
    jae .few
    mov bx, cx
    sub bx, dx
    dec bx
    shl bx, 2
    add bx, bp
    mov ebx, [bx]
    inc dx
.skip_len:
    cmp al, 'l'
    je .is_len
    cmp al, 'h'
    je .is_len
    cmp al, 'z'
    je .is_len
    cmp al, 'j'
    je .is_len
    cmp al, 't'
    je .is_len
    cmp al, 'L'
    je .is_len
    jmp .spec_ready
.is_len:
    mov al, [si]
    inc si
    jmp .skip_len
.spec_ready:
    cmp al, 'd'
    je .pd
    cmp al, 'i'
    je .pd
    cmp al, 'u'
    je .pu
    cmp al, 'c'
    je .pc
    cmp al, 's'
    je .ps
    cmp al, 'f'
    je .pf
    cmp al, 'g'
    je .pf
    cmp al, 'e'
    je .pf
    cmp al, 'x'
    je .px
    cmp al, 'X'
    je .px
    cmp al, 'p'
    je .px
    mov si, ci_e_spec
    jmp ci_error
.pu:
    push si
    mov eax, ebx
    call num_to_udec
    cmp byte [ci_p_left], 1
    je .pd_left
    mov di, [ci_p_width]
    call ci_pad
    call ci_outs
    pop si
    jmp .fmt_loop
.pd:
    push si
    mov eax, ebx
    call num_to_dec
    cmp byte [ci_p_left], 1
    je .pd_left
    mov di, [ci_p_width]
    call ci_pad
    call ci_outs
    pop si
    jmp .fmt_loop
.pd_left:
    call ci_outs
    mov di, [ci_p_width]
    sub di, ax
    jle .pd_done
.pd_pad:
    mov al, ' '
    call ci_outc
    dec di
    jnz .pd_pad
.pd_done:
    pop si
    jmp .fmt_loop
.px:
    push si
    mov eax, ebx
    call num_to_hex
    call ci_pad
    call ci_outs
    pop si
    jmp .fmt_loop
.pc:
    mov ax, 1
    call ci_pad
    mov al, bl
    call ci_outc
    jmp .fmt_loop
.ps:
    push si
    mov si, bx
    call ci_strlen_lit
    cmp byte [ci_p_left], 1
    je .ps_left
    mov di, [ci_p_width]
    call ci_pad
    call ci_out_lit
    pop si
    jmp .fmt_loop
.ps_left:
    call ci_out_lit
    mov di, [ci_p_width]
    sub di, ax
    jle .ps_done
.ps_pad:
    mov al, ' '
    call ci_outc
    dec di
    jnz .ps_pad
.ps_done:
    pop si
    jmp .fmt_loop
.pf:
    push si
    call ci_format_float
    mov si, ci_fmt_buf
    call ci_strlen_buf
    cmp byte [ci_p_left], 1
    je .pf_left
    mov di, [ci_p_width]
    call ci_pad
    mov si, ci_fmt_buf
    call ci_outs
    pop si
    jmp .fmt_loop
.pf_left:
    mov si, ci_fmt_buf
    call ci_outs
    mov di, [ci_p_width]
    sub di, ax
    jle .pf_done
.pf_pad:
    mov al, ' '
    call ci_outc
    dec di
    jnz .pf_pad
.pf_done:
    pop si
    jmp .fmt_loop
.cleanup:
    shl cx, 2
    add sp, cx
    add sp, 2
    xor eax, eax
    ret
.few:
    mov si, ci_e_few
    jmp ci_error
.too_many:
    mov si, ci_e_args
    jmp ci_error
.err_fmt:
    mov si, ci_e_fmt
    jmp ci_error

ci_putchar:
    call ci_lex
    call ci_expr
    EXPECT ')'
    cmp byte [ci_exec], 0
    je .r
    call ci_outc
.r:
    ret

ci_puts:
    call ci_lex
    call ci_expr
    EXPECT ')'
    cmp byte [ci_exec], 0
    je .r
    mov si, ax
    call ci_out_lit
    mov al, 10
    call ci_outc
.r:
    xor eax, eax
    ret

; ------------------------------------------------------------------------------
; Utskrift
; ------------------------------------------------------------------------------
ci_outc:                        ; AL = tegn
    mov [ci_last_char], al
    cmp al, 10
    jne .n
    jmp term_crlf
.n:
    cmp al, 9
    jne .p
    push ax
    mov al, ' '
    call term_putc
    call term_putc
    call term_putc
    call term_putc
    pop ax
    ret
.p:
    jmp term_putc

ci_outs:                        ; SI = nullterminert streng
    push ax
    push si
.l:
    lodsb
    test al, al
    jz .d
    call ci_outc
    jmp .l
.d:
    pop si
    pop ax
    ret

ci_out_lit:                     ; SI = strengliteral (etter ") -> skriv til "
    push ax
    push si
.l:
    mov al, [si]
    inc si
    test al, al
    jz .d
    cmp al, '"'
    je .d
    cmp al, '\'
    jne .o
    mov al, [si]
    inc si
    call ci_escape
.o:
    call ci_outc
    jmp .l
.d:
    pop si
    pop ax
    ret

ci_strlen_lit:                  ; SI = strengliteral -> AX = lengde
    push si
    xor ax, ax
.l:
    cmp byte [si], 0
    je .d
    cmp byte [si], '"'
    je .d
    cmp byte [si], '\'
    jne .n
    inc si
.n:
    inc si
    inc ax
    jmp .l
.d:
    pop si
    ret

ci_pad:                         ; DI = bredde, AX = lengde -> skriv mellomrom
    push di
    push ax
.l:
    cmp di, ax
    jle .d
    push ax
    mov al, ' '
    call ci_outc
    pop ax
    dec di
    jmp .l
.d:
    pop ax
    pop di
    ret

num_to_dec:                     ; EAX (signert) -> SI = streng, AX = lengde
    push ebx
    mov ebx, 10
    jmp num_conv
num_to_udec:                    ; EAX (usignert) -> SI = streng, AX = lengde
    push ebx
    mov ebx, 10
    push edx
    push di
    mov byte [num_neg], 0
    jmp num_conv.pos_loop
num_to_hex:                     ; EAX (usignert) -> SI = streng, AX = lengde
    push ebx
    mov ebx, 16
num_conv:
    push edx
    push di
    mov byte [num_neg], 0
    cmp ebx, 10
    jne .pos_loop
    test eax, eax
    jns .pos_loop
    neg eax
    mov byte [num_neg], 1
.pos_loop:
    mov di, numbuf + 15
    mov byte [di], 0
.loop:
    xor edx, edx
    div ebx
    add dl, '0'
    cmp dl, '9'
    jbe .dig
    add dl, 'a' - '9' - 1
.dig:
    dec di
    mov [di], dl
    test eax, eax
    jnz .loop
    cmp byte [num_neg], 0
    je .fin
    dec di
    mov byte [di], '-'
.fin:
    mov si, di
    mov ax, numbuf + 15
    sub ax, di
    pop di
    pop edx
    pop ebx
    ret

print_sdec32:                   ; EAX (signert) -> terminal
    push eax
    push si
    call num_to_dec
    call term_puts
    pop si
    pop eax
    ret

; ------------------------------------------------------------------------------
; Data for tolken
; ------------------------------------------------------------------------------
ci_keywords:
    dw kw_int
    db K_INT
    dw kw_char
    db K_CHAR
    dw kw_void
    db K_VOID
    dw kw_if
    db K_IF
    dw kw_else
    db K_ELSE
    dw kw_while
    db K_WHILE
    dw kw_for
    db K_FOR
    dw kw_return
    db K_RETURN
    dw kw_break
    db K_BREAK
    dw kw_continue
    db K_CONTINUE
    dw kw_do
    db K_DO
    dw kw_double
    db K_DOUBLE
    dw kw_float
    db K_FLOAT
    dw kw_static
    db K_STATIC
    dw kw_const
    db K_CONST
    dw kw_extern
    db K_EXTERN
    dw kw_volatile
    db K_VOLATILE
    dw kw_inline
    db K_INLINE
    dw kw_auto
    db K_AUTO
    dw kw_register
    db K_REGISTER
    dw kw_signed
    db K_SIGNED
    dw kw_unsigned
    db K_UNSIGNED
    dw kw_long
    db K_LONG
    dw kw_short
    db K_SHORT
    dw kw_bool
    db K_BOOL
    dw kw_Bool2
    db K_BOOL
    dw kw_size_t
    db K_LONG
    dw kw_ssize_t
    db K_LONG
    dw kw_int8_t
    db K_CHAR
    dw kw_uint8_t
    db K_CHAR
    dw kw_int16_t
    db K_INT
    dw kw_uint16_t
    db K_INT
    dw kw_int32_t
    db K_INT
    dw kw_uint32_t
    db K_INT
    dw kw_int64_t
    db K_INT
    dw kw_uint64_t
    db K_INT
    dw kw_struct
    db K_STRUCT
    dw kw_union
    db K_UNION
    dw kw_enum
    db K_ENUM
    dw kw_typedef
    db K_TYPEDEF
    dw 0

kw_int          db "int", 0
kw_char         db "char", 0
kw_void         db "void", 0
kw_if           db "if", 0
kw_else         db "else", 0
kw_while        db "while", 0
kw_for          db "for", 0
kw_return       db "return", 0
kw_break        db "break", 0
kw_continue     db "continue", 0
kw_do           db "do", 0
ci_e_while      db "forventet while etter do-kropp", 0
kw_double       db "double", 0
kw_float        db "float", 0
kw_static       db "static", 0
kw_const        db "const", 0
kw_extern       db "extern", 0
kw_volatile     db "volatile", 0
kw_inline       db "inline", 0
kw_auto         db "auto", 0
kw_register     db "register", 0
kw_signed       db "signed", 0
kw_unsigned     db "unsigned", 0
kw_long         db "long", 0
kw_short        db "short", 0
kw_bool         db "bool", 0
kw_Bool2        db "_Bool", 0
kw_size_t       db "size_t", 0
kw_ssize_t      db "ssize_t", 0
kw_int8_t       db "int8_t", 0
kw_uint8_t      db "uint8_t", 0
kw_int16_t      db "int16_t", 0
kw_uint16_t     db "uint16_t", 0
kw_int32_t      db "int32_t", 0
kw_uint32_t     db "uint32_t", 0
kw_int64_t      db "int64_t", 0
kw_uint64_t     db "uint64_t", 0
kw_struct       db "struct", 0
kw_union        db "union", 0
kw_enum         db "enum", 0
kw_typedef      db "typedef", 0

ci_ops2:
    db '=', '=', T_EQ
    db '!', '=', T_NE
    db '<', '=', T_LE
    db '>', '=', T_GE
    db '&', '&', T_AND
    db '|', '|', T_OR
    db '+', '+', T_INC
    db '-', '-', T_DEC
    db '-', '>', T_ARROW
    db '+', '=', T_ADDEQ
    db '-', '=', T_SUBEQ
    db '*', '=', T_MULEQ
    db '/', '=', T_DIVEQ
    db '%', '=', T_MODEQ
    db 0

ci_s_main       db "main", 0
ci_s_printf     db "printf", 0
ci_s_putchar    db "putchar", 0
ci_s_puts       db "puts", 0

ci_m_err        db 13, 10, "[!] Feil pa linje ", 0
ci_m_colon      db ": ", 0
ci_m_q1         db " '", 0
ci_m_q2         db "'", 0

ci_e_expect     db "forventet '"
ci_e_expect_ch  db "?", "'", 0
ci_e_str        db "uavsluttet streng", 0
ci_e_chr        db "ugyldig tegnkonstant", 0
ci_e_eof        db "uventet slutt pa filen", 0
ci_e_brace      db "mangler '}'", 0
ci_e_unexpected db "uventet symbol i uttrykk", 0
ci_e_lvalue     db "venstresiden kan ikke tilordnes", 0
ci_e_undef      db "ukjent variabel", 0
ci_e_notarr     db "variabelen er ikke en array", 0
ci_e_noidx      db "array ma brukes med indeks", 0
ci_e_bounds     db "array-indeks utenfor grensene", 0
ci_e_nofunc     db "ukjent funksjon", 0
ci_e_param      db "ugyldig parameterliste", 0
ci_e_args       db "feil antall argumenter (maks 8)", 0
ci_e_body       db "forventet funksjonskropp '{'", 0
ci_e_nomain     db "fant ingen main()", 0
ci_e_toplevel   db "forventet funksjon eller global variabel", 0
ci_e_name       db "forventet navn", 0
ci_e_funcs      db "for mange funksjoner (maks 32)", 0
ci_e_vars       db "for mange variabler (maks 128)", 0
ci_e_ptr        db "pekere stottes ikke", 0
ci_e_size       db "ugyldig array-storrelse", 0
ci_e_mem        db "tomt for array-minne", 0
ci_e_div0       db "deling pa null", 0
ci_e_stack      db "for dyp rekursjon (stakk full)", 0
ci_e_fmt        db "printf krever en formatstreng", 0
ci_e_few        db "for fa argumenter til printf", 0
ci_e_spec       db "ukjent printf-format (bruk %d %c %s %x)", 0
ci_e_abort      db "avbrutt av bruker (ESC)", 0

ci_tmp_dim2     dw 0
ci_src          dw 0
ci_pos          dw 0
tok_type        db 0
tok_start       dw 0
tok_num         dd 0
tok_sptr        dw 0
tok_name        times 16 db 0
ci_tmpname      times 16 db 0
ci_err_name     times 16 db 0
ci_exec         db 0
ci_ctl          db 0
ci_last_char    db 10
ci_ret          dd 0
ci_lv           dw 0
ci_var_count    dw 0
ci_frame_base   dw 0
ci_global_count dw 0
ci_func_count   dw 0
ci_heap_top     dw 0
ci_err_sp       dw 0
ci_dummy        dd 0
ci_is_float     dw 0
ci_cur_decl_type db 0
ci_f_tmp1       dd 0
ci_f_tmp2       dd 0
ci_f_tmp3       dd 0
ci_f_ten        dd 10.0
ci_fpu_cw       dw 0
ci_fpu_cw_trunc dw 0
ci_p_left       db 0
ci_p_width      dw 0
ci_p_prec       dw 6
ci_p_has_prec   db 0
ci_fmt_buf      times 48 db 0
num_neg         db 0
numbuf          times 16 db 0
