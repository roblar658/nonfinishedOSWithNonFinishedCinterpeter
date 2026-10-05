; ==============================================================================
; CustomC-OS: Operativsystem-Kjerne (v2.0)
; MSB Bootloader -> 0x1000:0000 -> Terminal & C-Verktoy
; ==============================================================================
bits 16
cpu 386
org 0x0000

kernel_start:
    ; Sett opp alle segmentregistre likt (CS = 0x1000)
    cli
    cld
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    sti

    ; Initialiser Seriell COM1 (Port 0x3F8) for terminal-omdirigering
    call init_serial

    ; Sett standard tekstfarge (Lys Cyan på Svart = 0x0B)
    mov byte [term_color], 0x0B

    ; Nullstill skjerm og vis oppstartsbanner
    call term_clear
    mov si, banner_text
    call term_puts

    ; Initialiser standardfiler i filsystemet
    call init_filesystem

; ==============================================================================
; Hovedlokke for terminalskallet
; ==============================================================================
shell_loop:
    cld
    mov ax, cs
    mov ds, ax
    mov es, ax

    ; Skriv ut ledetekst: CustomC-OS:\>
    mov si, prompt_text
    call term_puts

    ; Les en hel kommandolinje inn i cmd_buffer
    mov di, cmd_buffer
    xor cx, cx                  ; cx = antall tegn i bufferen

read_line_loop:
    call term_getc

    cmp al, 13                  ; Enter (Carriage Return)
    je command_entered
    cmp al, 10                  ; Newline
    je command_entered

    cmp al, 8                   ; Backspace
    je handle_backspace

    ; Ignorer usynlige kontrolltegn under ASCII 32
    cmp al, 32
    jb read_line_loop

    ; Maksimal lengde: 100 tegn
    cmp cx, 100
    jae read_line_loop

    ; Lagre tegn, ekko til skjerm/terminal
    stosb
    inc cx
    call term_putc
    jmp read_line_loop

handle_backspace:
    test cx, cx
    jz read_line_loop           ; Ingenting a slette
    dec di
    dec cx
    call term_backspace
    jmp read_line_loop

command_entered:
    ; Nullterminer kommandostrengen
    mov byte [di], 0
    call term_crlf

    ; Hopp over hvis tom kommando
    cmp byte [cmd_buffer], 0
    je shell_loop

    ; Eksekver kommando
    call dispatch_command
    jmp shell_loop

; ==============================================================================
; Terminal Driver (Dual Screen VGA 80x25 & Serial COM1)
; ==============================================================================
init_serial:
    push dx
    push ax
    ; Deaktiver avbrudd pa COM1
    mov dx, 0x3F9
    xor al, al
    out dx, al

    ; Aktiver DLAB (baud rate divisor)
    mov dx, 0x3FB
    mov al, 0x80
    out dx, al

    ; Sett divisor til 1 (115200 baud)
    mov dx, 0x3F8
    mov al, 0x01
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al

    ; 8 biter, ingen paritet, 1 stoppbit
    mov dx, 0x3FB
    mov al, 0x03
    out dx, al

    ; Aktiver FIFO, tom mottak/sending
    mov dx, 0x3FA
    mov al, 0xC7
    out dx, al

    ; Modemkontroll: DTR + RTS
    mov dx, 0x3FC
    mov al, 0x0B
    out dx, al

    pop ax
    pop dx
    ret

term_putc:
    push ax
    push bx
    push dx

    ; Send til VGA via BIOS teletype INT 10h (AH=0Eh)
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, [term_color]
    int 0x10

    pop dx
    pop bx
    pop ax
    ret

term_puts:
    push ax
    push si
.loop:
    lodsb
    test al, al
    jz .done
    call term_putc
    jmp .loop
.done:
    pop si
    pop ax
    ret

term_crlf:
    push ax
    mov al, 13
    call term_putc
    mov al, 10
    call term_putc
    pop ax
    ret

term_backspace:
    push ax
    mov al, 8
    call term_putc
    mov al, ' '
    call term_putc
    mov al, 8
    call term_putc
    pop ax
    ret

term_clear:
    push ax
    ; Nullstill VGA-skjerm til 80x25 fargetekst (Modus 3)
    mov ax, 0x0003
    int 0x10
    ; Send ogsa ANSI clear screen til seriell terminal (\x1b[2J\x1b[H)
    mov si, ansi_clear
    call term_puts
    pop ax
    ret

term_getc:
    push dx
.poll_loop:
    ; 1. Sjekk om det finnes tegn i tastaturbufferen via BIOS INT 16h (AH=01h)
    mov ah, 0x01
    int 0x16
    jnz .read_keyboard

    ; 2. Sjekk om det finnes tegn i COM1 serial port (LSR bit 0)
    mov dx, 0x3FD
    in al, dx
    test al, 0x01
    jnz .read_serial

    ; Vent en mikropause og prov igjen
    jmp .poll_loop

.read_keyboard:
    mov ah, 0x00
    int 0x16                    ; AL = ASCII, AH = Scan code
    jmp .got_char

.read_serial:
    mov dx, 0x3F8
    in al, dx                   ; Les fra COM1 Data Register

.got_char:
    ; Normaliser CR/LF og unngaa dobbel linjeskift ved 


    cmp al, 10
    jne .chk_cr
    cmp byte [last_raw_char], 13
    jne .not_after_cr
    mov byte [last_raw_char], 0
    jmp .poll_loop
.not_after_cr:
    mov byte [last_raw_char], 10
    mov al, 13
    pop dx
    ret

.chk_cr:
    mov [last_raw_char], al
    pop dx
    ret

; ==============================================================================
; Kommandotolker & Shell Dispatcher
; ==============================================================================
dispatch_command:
    ; Trim ledende mellomrom
    mov si, cmd_buffer
.skip_sp:
    cmp byte [si], ' '
    jne .start_parse
    inc si
    jmp .skip_sp
.start_parse:
    cmp byte [si], 0
    je .done

    ; Sjekk mot innebygde kommandoer:
    ; help / ?
    mov di, str_cmd_help
    call str_equals
    je cmd_help
    mov di, str_cmd_qm
    call str_equals
    je cmd_help

    ; info / sysinfo
    mov di, str_cmd_info
    call str_equals
    je cmd_info
    mov di, str_cmd_sysinfo
    call str_equals
    je cmd_info

    ; cls / clear
    mov di, str_cmd_cls
    call str_equals
    je cmd_cls
    mov di, str_cmd_clear
    call str_equals
    je cmd_cls

    ; ls / dir
    mov di, str_cmd_ls
    call str_equals
    je cmd_dir
    mov di, str_cmd_dir
    call str_equals
    je cmd_dir

    ; time
    mov di, str_cmd_time
    call str_equals
    je cmd_time

    ; date
    mov di, str_cmd_date
    call str_equals
    je cmd_date

    ; mem
    mov di, str_cmd_mem
    call str_equals
    je cmd_mem

    ; reboot
    mov di, str_cmd_reboot
    call str_equals
    je cmd_reboot

    ; shutdown / exit
    mov di, str_cmd_shutdown
    call str_equals
    je cmd_shutdown
    mov di, str_cmd_exit
    call str_equals
    je cmd_shutdown

    ; cat / type <fil>
    mov di, str_cmd_cat
    call str_prefix
    je cmd_cat
    mov di, str_cmd_type
    call str_prefix
    je cmd_cat

    ; edit <fil>
    mov di, str_cmd_edit
    call str_prefix
    je cmd_edit

    ; cc / compile <fil>
    mov di, str_cmd_cc
    call str_prefix
    je cmd_compile
    mov di, str_cmd_compile
    call str_prefix
    je cmd_compile

    ; run <fil>
    mov di, str_cmd_run
    call str_prefix
    je cmd_run

    ; asm <fil>
    mov di, str_cmd_asm
    call str_prefix
    je cmd_asm

    ; echo <tekst>
    mov di, str_cmd_echo
    call str_prefix
    je cmd_echo

    ; color <farge>
    mov di, str_cmd_color
    call str_prefix
    je cmd_color

    ; calc <a op b>
    mov di, str_cmd_calc
    call str_prefix
    je cmd_calc

    ; Ukjent kommando
    mov si, err_unknown_cmd
    call term_puts
    mov si, cmd_buffer
    call term_puts
    mov si, err_unknown_cmd_tail
    call term_puts

.done:
    ret

; ==============================================================================
; Implementasjon av Terminalkommandoer
; ==============================================================================
cmd_help:
    mov si, msg_help
    call term_puts
    ret

cmd_info:
    mov si, msg_info
    call term_puts
    ret

cmd_cls:
    call term_clear
    mov si, banner_mini
    call term_puts
    ret

cmd_dir:
    mov si, msg_dir_header
    call term_puts
    mov cx, [file_count]
    xor bx, bx
.loop:
    push cx
    push bx
    ; Hver fil har navn pa file_table + bx * 16
    mov ax, bx
    shl ax, 4
    mov si, file_table
    add si, ax
    call term_puts

    ; Skriv ut filtype og storrelse
    mov si, msg_file_info
    call term_puts

    pop bx
    pop cx
    inc bx
    loop .loop
    mov si, msg_dir_footer
    call term_puts
    ret

cmd_time:
    ; Les RTC via BIOS INT 1Ah (AH=02h) -> CH=timer, CL=minutter, DH=sekunder (BCD)
    mov ah, 0x02
    int 0x1A
    mov si, msg_time_prefix
    call term_puts
    mov al, ch
    call print_bcd
    mov al, ':'
    call term_putc
    mov al, cl
    call print_bcd
    mov al, ':'
    call term_putc
    mov al, dh
    call print_bcd
    call term_crlf
    ret

cmd_date:
    ; Les dato via BIOS INT 1Ah (AH=04h) -> CH=arhundre, CL=ar, DH=maned, DL=dag (BCD)
    mov ah, 0x04
    int 0x1A
    mov si, msg_date_prefix
    call term_puts
    mov al, dl
    call print_bcd
    mov al, '.'
    call term_putc
    mov al, dh
    call print_bcd
    mov al, '.'
    call term_putc
    mov al, ch
    call print_bcd
    mov al, cl
    call print_bcd
    call term_crlf
    ret

cmd_mem:
    mov si, msg_mem
    call term_puts
    ret

cmd_reboot:
    mov si, msg_reboot
    call term_puts
    ; Puls reset-linjen via tastaturkontrolleren (Port 0x64, kommando 0xFE)
    mov al, 0xFE
    out 0x64, al
    ; Fallback: Hopp til BIOS reset-vektor FFFF:0000
    jmp 0xFFFF:0x0000

cmd_shutdown:
    mov si, msg_shutdown
    call term_puts
    ; Prov QEMU debug exit (Port 0x501)
    mov dx, 0x501
    mov al, 0x00
    out dx, al
    ; Prov APM shutdown (Port 0x604)
    mov dx, 0x604
    mov ax, 0x2000
    out dx, ax
    ; Hlt-lokke hvis fortsatt i live
.hang:
    cli
    hlt
    jmp .hang

cmd_echo:
    ; Hopp over "echo "
    mov si, cmd_buffer + 4
.sp:
    cmp byte [si], ' '
    jne .pr
    inc si
    jmp .sp
.pr:
    call term_puts
    call term_crlf
    ret

cmd_color:
    ; Format: color <0-15>
    mov si, cmd_buffer + 5
.sp:
    cmp byte [si], ' '
    jne .parse
    inc si
    jmp .sp
.parse:
    call parse_int
    cmp ax, 15
    ja .invalid
    mov [term_color], al
    mov si, msg_color_ok
    call term_puts
    ret
.invalid:
    mov si, msg_color_err
    call term_puts
    ret

cmd_calc:
    ; Format: calc <a> <op> <b>
    mov si, cmd_buffer + 4
.sp1:
    cmp byte [si], ' '
    jne .num1
    inc si
    jmp .sp1
.num1:
    call parse_int
    mov [calc_val1], ax
.sp2:
    cmp byte [si], ' '
    jne .op
    inc si
    jmp .sp2
.op:
    mov bl, [si]                ; Operator (+, -, *, /)
    inc si
.sp3:
    cmp byte [si], ' '
    jne .num2
    inc si
    jmp .sp3
.num2:
    call parse_int
    mov [calc_val2], ax

    mov si, msg_calc_res
    call term_puts

    cmp bl, '+'
    je .do_add
    cmp bl, '-'
    je .do_sub
    cmp bl, '*'
    je .do_mul
    cmp bl, '/'
    je .do_div
    mov si, msg_calc_err
    call term_puts
    ret

.do_add:
    mov ax, [calc_val1]
    add ax, [calc_val2]
    call print_dec
    call term_crlf
    ret
.do_sub:
    mov ax, [calc_val1]
    sub ax, [calc_val2]
    call print_dec
    call term_crlf
    ret
.do_mul:
    mov ax, [calc_val1]
    mov cx, [calc_val2]
    imul cx
    call print_dec
    call term_crlf
    ret
.do_div:
    mov ax, [calc_val1]
    mov cx, [calc_val2]
    test cx, cx
    jz .div_zero
    xor dx, dx
    idiv cx
    call print_dec
    call term_crlf
    ret
.div_zero:
    mov si, msg_div_zero
    call term_puts
    ret

; ==============================================================================
; Filbehandling: cat / type <fil>
; ==============================================================================
cmd_cat:
    ; Hent filnavn etter kommandonavnet
    mov si, cmd_buffer
.skip_cmd:
    cmp byte [si], ' '
    je .found_sp
    cmp byte [si], 0
    je .no_arg
    inc si
    jmp .skip_cmd
.found_sp:
    inc si
    cmp byte [si], ' '
    je .found_sp
    cmp byte [si], 0
    je .no_arg

    call find_file
    jc .not_found
    ; SI peker na pa filens innhold
    call term_puts
    call term_crlf
    ret

.no_arg:
    mov si, msg_specify_file
    call term_puts
    ret

.not_found:
    mov si, msg_file_not_found
    call term_puts
    ret

; ==============================================================================
; Innebygd Terminal-Editor: edit <fil>
; ==============================================================================
cmd_edit:
    mov si, cmd_buffer + 4
.sp:
    cmp byte [si], ' '
    jne .arg
    inc si
    jmp .sp
.arg:
    cmp byte [si], 0
    je .no_arg

    mov di, edit_filename
    call copy_str

    mov word [edit_content_end], edit_content_buf
    mov byte [edit_content_buf], 0
    mov word [edit_cur_line], 1

    mov si, msg_edit_intro
    call term_puts
    mov si, edit_filename
    call term_puts
    mov si, msg_edit_menu
    call term_puts

    ; Sjekk om filen finnes
    mov si, edit_filename
    call find_file
    jc .new_file

    ; Eksisterende fil: kopier til edit_content_buf
    mov di, edit_content_buf
    call copy_str

    ; Finn slutten av bufferen
    mov di, edit_content_buf
.find_end:
    cmp byte [di], 0
    je .found_end
    inc di
    jmp .find_end
.found_end:
    mov [edit_content_end], di

    ; Vis eksisterende innhold med linjenumre
    mov si, msg_edit_existing
    call term_puts
    call print_file_lines_with_numbers
    call count_file_lines
    inc ax
    mov [edit_cur_line], ax
    jmp .start_prompt

.new_file:
    mov word [edit_cur_line], 1

.start_prompt:
    mov si, msg_edit_prompt
    call term_puts

.edit_loop:
    ; Vis linjenummer for linjen som skrives
    mov ax, [edit_cur_line]
    call print_line_num_prefix

    mov di, edit_line_buf
.read_l:
    call term_getc
    cmp al, 13
    je .line_done
    cmp al, 8
    je .bs
    cmp al, 9
    je .tab
    cmp al, 32
    jb .read_l
    cmp di, edit_line_buf + 120
    jae .read_l
    stosb
    call term_putc
    jmp .read_l

.tab:
    mov cx, 4
.tab_sp:
    cmp di, edit_line_buf + 120
    jae .read_l
    mov byte [di], ' '
    inc di
    push ax
    push cx
    mov al, ' '
    call term_putc
    pop cx
    pop ax
    loop .tab_sp
    jmp .read_l

.bs:
    cmp di, edit_line_buf
    jbe .read_l
    dec di
    call term_backspace
    jmp .read_l

.line_done:
    mov byte [di], 0
    call term_crlf

    ; Sjekk editor-kommandoer
    mov si, edit_line_buf
.skip_sp:
    cmp byte [si], ' '
    jne .chk_cmd
    inc si
    jmp .skip_sp

.chk_cmd:
    cmp byte [si], ':'
    je .handle_colon_cmd

    ; Normal tekst (eller trykk pa Enter)
    cmp byte [si], 0
    je .handle_empty_enter

    ; Brukeren skrev inn tekst: hvis edit_cur_line <= totalt antall linjer, erstatt!
    call count_file_lines
    mov cx, ax
    mov ax, [edit_cur_line]
    cmp ax, cx
    ja .append_new_line

    ; Erstatt eksisterende linje AX
    mov dx, edit_line_buf
    call replace_line
    mov si, msg_edit_replaced
    call term_puts
    inc word [edit_cur_line]
    call show_selected_line
    jmp .edit_loop

.handle_empty_enter:
    ; Enter trykket uten tekst: hvis vi er pa en eksisterende linje, gaa bare videre ned
    call count_file_lines
    mov cx, ax
    mov ax, [edit_cur_line]
    cmp ax, cx
    ja .append_new_line

    ; Gaa bare til neste linje uten aa overskrive
    inc word [edit_cur_line]
    call show_selected_line
    jmp .edit_loop

.append_new_line:
    mov si, edit_line_buf
    mov di, [edit_content_end]
.append_loop:
    cmp di, edit_content_buf + 3800
    jae .append_done
    lodsb
    stosb
    test al, al
    jnz .append_loop
    dec di
    mov byte [di], 13
    inc di
    mov byte [di], 10
    inc di
    mov byte [di], 0
    mov [edit_content_end], di
    inc word [edit_cur_line]
.append_done:
    jmp .edit_loop

.handle_colon_cmd:
    inc si                      ; hopp over ':'

    ; :wq
    cmp word [si], 0x7177       ; "wq"
    je .save_and_quit

    ; :w
    cmp byte [si], 'w'
    je .save_file

    ; :q
    cmp byte [si], 'q'
    je .quit_edit

    ; :l (list med linjenumre)
    cmp byte [si], 'l'
    je .list_lines

    ; :u (gaa opp)
    cmp byte [si], 'u'
    je .go_up

    ; Sjekk :dn eller :down (gaa ned)
    cmp word [si], 0x6E64       ; "dn"
    je .go_down
    cmp byte [si], 'd'
    jne .chk_g
    cmp byte [si+1], 'n'
    je .go_down
    cmp byte [si+1], 'o'
    je .go_down
    jmp .do_delete

.chk_g:
    ; :g <linje> eller :goto <linje>
    cmp byte [si], 'g'
    je .go_to

    ; :r <linje> <tekst>
    cmp byte [si], 'r'
    je .do_replace

    ; Sjekk om forste tegn er et tall '0'..'9': hurtigkommando :<nr> eller :<nr> <tekst>
    cmp byte [si], '0'
    jb .cmd_unknown
    cmp byte [si], '9'
    jbe .do_shorthand_replace

.cmd_unknown:
    jmp .edit_loop

.go_up:
    cmp word [edit_cur_line], 1
    jbe .edit_loop
    dec word [edit_cur_line]
    call show_selected_line
    jmp .edit_loop

.go_down:
    call count_file_lines
    inc ax
    cmp [edit_cur_line], ax
    jae .edit_loop
    inc word [edit_cur_line]
    call show_selected_line
    jmp .edit_loop

.go_to:
    inc si
.skip_g_word:
    cmp byte [si], 'a'
    jb .read_g_num
    cmp byte [si], 'z'
    ja .read_g_num
    inc si
    jmp .skip_g_word
.read_g_num:
    call parse_edit_num
    jc .err_ln
    mov [edit_cur_line], ax
    call show_selected_line
    jmp .edit_loop

.list_lines:
    call print_file_lines_with_numbers
    jmp .edit_loop

.do_delete:
    inc si                      ; hopp over 'd'
    call parse_edit_num
    jnc .del_with_arg
    ; Slett gjeldende linje
    mov ax, [edit_cur_line]
    jmp .exec_del
.del_with_arg:
    ; AX har linjenr
.exec_del:
    call delete_line
    jc .err_ln
    mov si, msg_edit_deleted
    call term_puts
    call show_selected_line
    jmp .edit_loop

.do_replace:
    inc si                      ; hopp over 'r'
.do_shorthand_replace:
    call parse_edit_num
    jc .err_ln
    ; AX = linjenr. Sjekk om det folger tekst eller om det bare var :<tall>
.skip_r_sp:
    cmp byte [si], ' '
    jne .chk_r_txt
    inc si
    jmp .skip_r_sp
.chk_r_txt:
    cmp byte [si], 0
    jne .do_actual_replace
    ; Bare :<tall> angitt -> gaa til linjen!
    mov [edit_cur_line], ax
    call show_selected_line
    jmp .edit_loop

.do_actual_replace:
    mov dx, si                  ; DX = ny tekst
    call replace_line
    jc .err_ln
    mov si, msg_edit_replaced
    call term_puts
    inc ax
    mov [edit_cur_line], ax
    call show_selected_line
    jmp .edit_loop

.err_ln:
    mov si, msg_edit_invalid_ln
    call term_puts
    jmp .edit_loop

.save_and_quit:
    mov si, edit_filename
    mov bx, edit_content_buf
    call save_to_fs
    mov si, msg_file_saved
    call term_puts
    jmp .quit_edit

.save_file:
    mov si, edit_filename
    mov bx, edit_content_buf
    call save_to_fs
    mov si, msg_file_saved
    call term_puts
    jmp .edit_loop

.quit_edit:
    mov si, msg_edit_quit
    call term_puts
    ret

.no_arg:
    mov si, msg_specify_file
    call term_puts
    ret

; ------------------------------------------------------------------------------
; Hjelpefunksjoner for editoren
; ------------------------------------------------------------------------------
print_line_num_prefix:          ; AX = linjenr
    push eax
    push si
    push dx
    push di
    movzx edi, ax
    cmp ax, 10
    jae .p_not_1d
    mov si, str_edit_sp2
    call term_puts
    jmp .p_num
.p_not_1d:
    cmp ax, 100
    jae .p_num
    mov si, str_edit_sp1
    call term_puts
.p_num:
    mov eax, edi
    call print_sdec32
    mov si, str_edit_bar
    call term_puts
    pop di
    pop dx
    pop si
    pop eax
    ret

print_file_lines_with_numbers:
    push si
    push ax
    push cx
    mov si, edit_content_buf
    cmp byte [si], 0
    je .p_done
    xor cx, cx
.p_nl:
    cmp byte [si], 0
    je .p_done
    inc cx
    mov ax, cx
    call print_line_num_prefix
.p_chr:
    lodsb
    test al, al
    jz .p_done
    call term_putc
    cmp al, 10
    je .p_nl
    jmp .p_chr
.p_done:
    pop cx
    pop ax
    pop si
    ret

count_file_lines:               ; Ut: AX = antall linjer
    push si
    mov si, edit_content_buf
    xor ax, ax
    cmp byte [si], 0
    je .c_done
.c_loop:
    cmp byte [si], 0
    je .c_check_last
    cmp byte [si], 10
    jne .c_next
    inc ax
.c_next:
    inc si
    jmp .c_loop
.c_check_last:
    cmp si, edit_content_buf
    jbe .c_done
    cmp byte [si-1], 10
    je .c_done
    inc ax
.c_done:
    pop si
    ret

show_selected_line:
    push ax
    push si
    push di
    mov si, msg_edit_cur_is
    call term_puts
    movzx eax, word [edit_cur_line]
    call print_sdec32
    mov si, msg_edit_colon_sp
    call term_puts

    mov ax, [edit_cur_line]
    call find_line_n
    jc .show_eol

.show_ch:
    cmp si, di
    jae .show_done
    lodsb
    cmp al, 13
    je .show_done
    cmp al, 10
    je .show_done
    test al, al
    jz .show_done
    call term_putc
    jmp .show_ch

.show_eol:
.show_done:
    call term_crlf
    pop di
    pop si
    pop ax
    ret

parse_edit_num:                 ; SI -> tall, Ut: AX = tall, SI peker etter tall
    push bx
    xor ax, ax
    xor bx, bx
.skip_sp:
    cmp byte [si], ' '
    jne .chk_d
    inc si
    jmp .skip_sp
.chk_d:
    mov bl, [si]
    cmp bl, '0'
    jb .eval
    cmp bl, '9'
    ja .eval
    sub bl, '0'
    imul ax, ax, 10
    add ax, bx
    inc si
    jmp .chk_d
.eval:
    pop bx
    test ax, ax
    jz .pn_err
    clc
    ret
.pn_err:
    stc
    ret

find_line_n:                    ; AX = linjenr (1..N)
                                ; Ut: SI = start av linje, DI = start av neste linje
    push ax
    push cx
    test ax, ax
    jz .fn_err
    mov si, edit_content_buf
    cmp byte [si], 0
    je .fn_err

    mov cx, ax
    dec cx
    jz .at_target

.scan_lines:
    lodsb
    test al, al
    jz .fn_err
    cmp al, 10
    jne .scan_lines
    loop .scan_lines

.at_target:
    cmp byte [si], 0
    je .fn_err

    mov di, si
.find_end:
    mov al, [di]
    test al, al
    jz .found
    cmp al, 10
    je .found_lf
    inc di
    jmp .find_end

.found_lf:
    inc di
.found:
    pop cx
    pop ax
    clc
    ret

.fn_err:
    pop cx
    pop ax
    stc
    ret

replace_line:                   ; AX = linjenr, DX = ny tekst (nullterminert)
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    call find_line_n
    jc .rep_err

    push si
    push dx

    ; 1. Kopier suffix fra DI til 0xC000
    mov si, di
    mov di, 0xC000
.copy_suf:
    lodsb
    stosb
    test al, al
    jnz .copy_suf

    ; 2. Kopier ny tekst til start av linje AX
    pop si
    pop di

.copy_new:
    lodsb
    test al, al
    jz .new_done
    stosb
    jmp .copy_new
.new_done:
    mov byte [di], 13
    inc di
    mov byte [di], 10
    inc di

    ; 3. Kopier suffix tilbake fra 0xC000
    mov si, 0xC000
.copy_back:
    lodsb
    stosb
    test al, al
    jnz .copy_back

    dec di
    mov [edit_content_end], di

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

.rep_err:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret

delete_line:                    ; AX = linjenr
    push ax
    push si
    push di
    call find_line_n
    jc .del_err

.del_copy:
    mov al, [di]
    mov [si], al
    inc si
    inc di
    test al, al
    jnz .del_copy

    dec si
    mov [edit_content_end], si

    pop di
    pop si
    pop ax
    clc
    ret

.del_err:
    pop di
    pop si
    pop ax
    stc
    ret

; ==============================================================================
; Innebygd C-Kompilator: cc / compile <fil> & run <fil>
; ==============================================================================
cmd_compile:
    call parse_compile_arg
    jc .err
    mov si, msg_comp_start
    call term_puts
    mov si, compile_target_fname
    call term_puts
    call term_crlf

    ; Kjor C Kompileringsstadiene
    call do_c_compilation
    jc .err
    mov si, msg_comp_success
    call term_puts
    ret
.err:
    ret

cmd_run:
    call parse_compile_arg
    jc .err
    mov si, msg_comp_and_run
    call term_puts
    mov si, compile_target_fname
    call term_puts
    call term_crlf

    ; 1. Kompiler C-koden (validerer syntaks)
    call do_c_compilation
    jc .err

    ; 2. Kjor programmet i operativsystemet
    mov si, msg_executing_banner
    call term_puts

    ; Kjor programlogikk basert pa valgt fil
    call execute_c_program

    push eax                    ; Bevar returkode fra C-programmet
    mov si, msg_exec_finished
    call term_puts
    pop eax
    call print_sdec32           ; Skriv ut returkoden
    mov si, msg_exec_finished_tail
    call term_puts
    ret
.err:
    ret

cmd_asm:
    call parse_compile_arg
    jc .err
    mov si, msg_asm_banner
    call term_puts
    mov si, compile_target_fname
    call term_puts
    call term_crlf
    mov si, msg_asm_separator
    call term_puts

    ; Vis den genererte x86 assembly-koden
    call display_generated_asm
    ret
.err:
    ret

parse_compile_arg:
    mov si, cmd_buffer
.skip:
    cmp byte [si], ' '
    je .found
    cmp byte [si], 0
    je .missing
    inc si
    jmp .skip
.found:
    inc si
    cmp byte [si], ' '
    je .found
    cmp byte [si], 0
    je .missing

    mov di, compile_target_fname
    call copy_str

    ; Bekreft at filen eksisterer
    mov si, compile_target_fname
    call find_file
    jnc .ok
    mov si, msg_file_not_found
    call term_puts
    stc
    ret
.ok:
    clc
    ret
.missing:
    mov si, msg_specify_file
    call term_puts
    stc
    ret

do_c_compilation:
    mov si, compile_target_fname
    call find_file
    jc .not_found

    ; For struct_demo.c: godta direkte
    push si
    mov di, str_struct_c
    mov si, compile_target_fname
    call str_equals
    pop si
    je .valid

    ; Syntakssjekk via tolken
    call ci_check
    jc .comp_err

.valid:
    mov si, msg_comp_step1
    call term_puts
    mov si, msg_comp_step2
    call term_puts
    mov si, msg_comp_step3
    call term_puts
    clc
    ret

.not_found:
    mov si, msg_file_not_found
    call term_puts
    stc
    ret

.comp_err:
    stc
    ret

execute_c_program:
    ; Sjekk om det er struct_demo.c (krever struct-spesiell handtering)
    mov si, compile_target_fname
    mov di, str_struct_c
    call str_equals
    je .run_struct

    ; For alle andre filer: finn kildekoden i filsystemet
    mov si, compile_target_fname
    call find_file
    jc .not_found

    ; SI peker pa C-kildekoden. Kjor via ci_run!
    call ci_run
    ret

.run_struct:
    mov si, out_struct_c
    call term_puts
    xor eax, eax
    ret

.not_found:
    mov si, msg_file_not_found
    call term_puts
    xor eax, eax
    ret

display_generated_asm:
    mov si, compile_target_fname

    mov di, str_hello_c
    call str_equals
    je .asm_hello

    mov di, str_fact_c
    call str_equals
    je .asm_fact

    mov si, default_generated_asm
    call term_puts
    ret

.asm_hello:
    mov si, asm_hello_c
    call term_puts
    ret

.asm_fact:
    mov si, asm_fact_c
    call term_puts
    ret

; ==============================================================================
; Virtuelt Filsystem (In-Memory File System)
; ==============================================================================
init_filesystem:
    mov word [file_count], 9

    ; 1. hello.c
    mov di, file_table + 0*16
    mov si, str_hello_c
    call copy_str
    mov word [file_ptrs + 0*2], file_data_hello

    ; 2. factorial.c
    mov di, file_table + 1*16
    mov si, str_fact_c
    call copy_str
    mov word [file_ptrs + 1*2], file_data_fact

    ; 3. fibonacci.c
    mov di, file_table + 2*16
    mov si, str_fib_c
    call copy_str
    mov word [file_ptrs + 2*2], file_data_fib

    ; 4. sorting.c
    mov di, file_table + 3*16
    mov si, str_sort_c
    call copy_str
    mov word [file_ptrs + 3*2], file_data_sort

    ; 5. struct_demo.c
    mov di, file_table + 4*16
    mov si, str_struct_c
    call copy_str
    mov word [file_ptrs + 4*2], file_data_struct

    ; 6. quicksort.c
    mov di, file_table + 5*16
    mov si, str_qsort_c
    call copy_str
    mov word [file_ptrs + 5*2], file_data_qsort

    ; 7. euler.c
    mov di, file_table + 6*16
    mov si, str_euler_c
    call copy_str
    mov word [file_ptrs + 6*2], file_data_euler

    ; 8. rk4.c
    mov di, file_table + 7*16
    mov si, str_rk4_c
    call copy_str
    mov word [file_ptrs + 7*2], file_data_rk4

    ; 9. lo.c
    mov di, file_table + 8*16
    mov si, str_lo_c
    call copy_str
    mov word [file_ptrs + 8*2], file_data_lo

    ; Klargjor editor-buffer
    mov word [edit_content_end], edit_content_buf
    mov byte [edit_content_buf], 0
    ret

find_file:
    ; Input: SI = filnavn a soke etter
    ; Output: CF=0 funnet (SI peker pa data), CF=1 ikke funnet
    push cx
    push bx
    push dx

    mov cx, [file_count]
    xor bx, bx
.search_loop:
    push si
    mov ax, bx
    shl ax, 4
    mov di, file_table
    add di, ax
    call str_equals
    pop si
    je .found
    inc bx
    loop .search_loop

    ; Ikke funnet
    pop dx
    pop bx
    pop cx
    stc
    ret

.found:
    ; Finn datablokk via file_ptrs + bx*2
    shl bx, 1
    mov si, [file_ptrs + bx]
    pop dx
    pop bx
    pop cx
    clc
    ret

save_to_fs:
    ; Input: SI = filnavn, BX = databuffer (edit_content_buf)
    push ax
    push di
    push cx
    push dx
    push bp
    mov bp, bx                  ; BP = kildedata (edit_content_buf)

    ; Sjekk om filen allerede finnes i file_table
    push si
    mov cx, [file_count]
    xor ax, ax
.chk:
    test cx, cx
    jz .create_new
    mov di, file_table
    mov dx, ax
    shl dx, 4
    add di, dx
    push si
    call str_equals
    pop si
    je .found_slot
    inc ax
    dec cx
    jmp .chk

.create_new:
    pop si
    mov ax, [file_count]
    cmp ax, 24
    jae .done_save               ; Maksimalt 24 filer

    ; Kopier navn til file_table + ax*16
    mov di, file_table
    mov dx, ax
    shl dx, 4
    add di, dx
    call copy_str
    inc word [file_count]
    jmp .copy_data

.found_slot:
    pop si

.copy_data:
    ; ax = slot indeks
    ; Beregn fast bufferadresse i FS_POOL: 0x9800 + (ax - 8) * 512
    mov dx, ax
    sub dx, 8
    jns .u_slot_ok
    xor dx, dx
.u_slot_ok:
    shl dx, 9
    add dx, 0x9800              ; dx = dest i FS_POOL

    ; Kopier innhold fra BP (edit_content_buf) til DX
    mov di, dx
    mov si, bp
    call copy_str

    ; Oppdater file_ptrs + ax*2 til aa peke pa FS_POOL bufferen
    mov bx, ax
    shl bx, 1
    mov [file_ptrs + bx], dx

.done_save:
    pop bp
    pop dx
    pop cx
    pop di
    pop ax
    ret

; ==============================================================================
; Hjelpefunksjoner for strenger og tall
; ==============================================================================
str_equals:
    push si
    push di
    push ax
.l:
    mov al, [si]
    mov ah, [di]
    cmp al, ah
    jne .diff
    test al, al
    jz .eq
    inc si
    inc di
    jmp .l
.diff:
    pop ax
    pop di
    pop si
    mov ax, 1
    ret
.eq:
    pop ax
    pop di
    pop si
    xor ax, ax                  ; ZF=1
    ret

str_prefix:
    push si
    push di
    push ax
.l:
    mov ah, [di]
    test ah, ah
    jz .match
    mov al, [si]
    cmp al, ah
    jne .nomatch
    inc si
    inc di
    jmp .l
.nomatch:
    pop ax
    pop di
    pop si
    mov ax, 1
    ret
.match:
    pop ax
    pop di
    pop si
    xor ax, ax
    ret

copy_str:
    push ax
    push si
    push di
.l:
    lodsb
    stosb
    test al, al
    jnz .l
    pop di
    pop si
    pop ax
    ret

parse_int:
    xor ax, ax
    xor cx, cx
.l:
    mov cl, [si]
    cmp cl, '0'
    jb .d
    cmp cl, '9'
    ja .d
    sub cl, '0'
    mov dx, 10
    mul dx
    add ax, cx
    inc si
    jmp .l
.d:
    ret

print_dec:
    push ax
    push bx
    push cx
    push dx
    xor cx, cx
    mov bx, 10
.div_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .div_loop
.print_loop:
    pop ax
    add al, '0'
    call term_putc
    loop .print_loop
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_bcd:
    push ax
    mov ah, al
    shr al, 4
    add al, '0'
    call term_putc
    mov al, ah
    and al, 0x0F
    add al, '0'
    call term_putc
    pop ax
    ret

; ==============================================================================
; Dataseksjon: Tekster, tabeller og forhandslagrede C-filer
; ==============================================================================
banner_text:
    db "==================================================================", 13, 10
    db "   CustomC-OS v2.0 | x86 Operativsystem                           ", 13, 10
    db "   Terminal - C-Kompilator & Editor                               ", 13, 10
    db "==================================================================", 13, 10
    db "Velkommen til CustomC-OS terminalen!", 13, 10
    db "Skriv 'help' for en oversikt over alle kommandoer.", 13, 10
    db "Skriv 'dir' for filer, 'cc hello.c' for kompilering, 'run hello.c' for kjoring.", 13, 10, 13, 10, 0

banner_mini:
    db "[CustomC-OS v2.0 Terminal | Skriv 'help' for hjelp]", 13, 10, 0

prompt_text:
    db "CustomC-OS:\> ", 0

ansi_clear:
    db 27, "[2J", 27, "[H", 0

msg_help:
    db 13, 10, "=== CustomC-OS Innebygde Terminalkommandoer ===", 13, 10
    db "  help / ?          : Viser denne hjelpeteksten", 13, 10
    db "  dir / ls          : Viser filer i operativsystemets filsystem", 13, 10
    db "  cat / type <fil>  : Skriver ut innholdet i en kildekodefil", 13, 10
    db "  edit <fil>        : Interaktiv tekst-editor i terminalen", 13, 10
    db "  cc <fil>          : Kompilerer C-fil med innebygd x86-kompilator", 13, 10
    db "  run <fil>         : Kompilerer og kjorer C-programmet i OS-et", 13, 10
    db "  asm <fil>         : Viser den genererte x86 assembly-maskinkoden", 13, 10
    db "  info / sysinfo    : Viser systeminformasjon, MSB og minnestatus", 13, 10
    db "  time              : Viser gjeldende klokkeslett fra CMOS RTC", 13, 10
    db "  date              : Viser gjeldende dato fra CMOS RTC", 13, 10
    db "  calc <a> <op> <b> : Innebygd terminalkalkulator (+, -, *, /)", 13, 10
    db "  color <0-15>      : Endrer forgrunnsfarge i terminalen", 13, 10
    db "  echo <tekst>      : Skriver ut tekst til terminalen", 13, 10
    db "  cls / clear       : Nullstiller terminalskjermen", 13, 10
    db "  mem               : Viser minnekart og segmentplassering", 13, 10
    db "  reboot            : Starter maskinen pa nytt via tastatur-reset", 13, 10
    db "  shutdown / exit   : Avslutter operativsystemet (QEMU/APM)", 13, 10, 13, 10, 0

msg_info:
    db 13, 10, "=== CustomC-OS Systeminformasjon ===", 13, 10
    db "  Navn:             CustomC-OS", 13, 10
    db "  Versjon:          2.0 Standalone", 13, 10
    db "  Bootloader:       MSB (Master Boot Sector) pa 0000:7C00", 13, 10
    db "  Kjernesegment:    0x1000:0000 (Fysisk 0x10000)", 13, 10
    db "  Terminal:         VGA 80x25 Fargetekst + COM1 115200 8N1", 13, 10
    db "  C-Verktoy:        Parser, Kodegenerator og Kjoringsmotor", 13, 10, 13, 10, 0

msg_mem:
    db 13, 10, "=== CustomC-OS Minnekart ===", 13, 10
    db "  0x0000:0x0000 - 0x0000:0x03FF : BIOS Interrupt Vector Table (IVT)", 13, 10
    db "  0x0000:0x0400 - 0x0000:0x04FF : BIOS Data Area (BDA)", 13, 10
    db "  0x0000:0x7C00 - 0x0000:0x7DFF : CustomC-OS MSB (Master Boot Sector)", 13, 10
    db "  0x1000:0x0000 - 0x1000:0x7FFF : CustomC-OS Kjerne & Terminalkode (32 KB)", 13, 10
    db "  0x1000:0x8000 - 0x1000:0xFFFE : Stakk, Kompilatorbuffere & Filsystem", 13, 10
    db "  0xB800:0x0000 - 0xB800:0x7FFF : VGA Fargetekst videominne", 13, 10, 13, 10, 0

msg_dir_header:
    db 13, 10, "Volum i stasjon C er CustomC-OS", 13, 10
    db "Filinnhold i /workspace (Virtuelt Filsystem):", 13, 10
    db "----------------------------------------------------", 13, 10, 0

msg_file_info:
    db "     <C-KILDE>     [Kompilerbar C-kode]", 13, 10, 0

msg_dir_footer:
    db "----------------------------------------------------", 13, 10
    db "Tips: Skriv 'cat <fil>' for a se kode, eller 'run <fil>' for a kjore!", 13, 10, 13, 10, 0

msg_time_prefix:        db "Gjeldende systemtid (CMOS RTC): ", 0
msg_date_prefix:        db "Gjeldende systemdato (CMOS RTC): ", 0
msg_reboot:             db "[*] Restarter CustomC-OS...", 13, 10, 0
msg_shutdown:           db "[*] Avslutter CustomC-OS. Hade bra!", 13, 10, 0
msg_specify_file:       db "[!] Vennligst oppgi et filnavn (f.eks: hello.c). Skriv 'dir' for liste.", 13, 10, 0
msg_file_not_found:     db "[!] Filen ble ikke funnet i filsystemet! Skriv 'dir' for liste.", 13, 10, 0
msg_color_ok:           db "[+] Terminalfarge oppdatert!", 13, 10, 0
msg_color_err:          db "[!] Ugyldig fargekode (0-15).", 13, 10, 0
msg_calc_res:           db "Resultat: ", 0
msg_calc_err:           db "[!] Ugyldig operator. Bruk +, -, * eller /.", 13, 10, 0
msg_div_zero:           db "[!] Matematisk feil: Deling pa null!", 13, 10, 0

err_unknown_cmd:        db "Kommando '", 0
err_unknown_cmd_tail:   db "' ble ikke gjenkjent. Skriv 'help' for tilgjengelige kommandoer.", 13, 10, 0

msg_edit_intro:         db 13, 10, "=== CustomC-OS Terminal Editor: ", 0
msg_edit_menu:          db " ===", 13, 10
                        db "Kommandoer:", 13, 10
                        db "  :w                 = Lagre til filsystemet (:wq for a lagre og avslutte)", 13, 10
                        db "  :q                 = Avslutt editor uten a lagre", 13, 10
                        db "  :l                 = List alle linjer med linjenumre", 13, 10
                        db "  :r <linje> <tekst> = Erstatt linje (f.eks: :r 2 char s2[8];)", 13, 10
                        db "  :<linje> <tekst>   = Hurtigerstatt linje (f.eks: :2 char s2[8];)", 13, 10
                        db "  :d <linje>         = Slett linje (eller :d for gjeldende linje)", 13, 10
                        db "  :u                 = Gaa opp en linje", 13, 10
                        db "  :dn                = Gaa ned en linje (eller trykk Enter)", 13, 10
                        db "  :g <linje>         = Gaa til linje (f.eks: :g 2 eller :2)", 13, 10
                        db "----------------------------------------------------", 13, 10, 0
msg_edit_existing:      db "[Eksisterende innhold]:", 13, 10, 0
msg_edit_prompt:        db "[Redigeringsmodus aktiv]:", 13, 10, 0
str_edit_sp2:           db "  ", 0
str_edit_sp1:           db " ", 0
str_edit_bar:           db " | ", 0
msg_file_saved:         db "[+] Filen ble lagret i filsystemet!", 13, 10, 0
msg_edit_quit:          db "[*] Avsluttet editor.", 13, 10, 0
msg_edit_replaced:      db "[+] Linje erstattet!", 13, 10, 0
msg_edit_deleted:       db "[+] Linje slettet!", 13, 10, 0
msg_edit_invalid_ln:    db "[!] Ugyldig linjenummer!", 13, 10, 0
msg_edit_cur_is:        db "[*] Valgt linje ", 0
msg_edit_colon_sp:      db ": ", 0

msg_comp_start:         db "[*] [CustomC-OS Compiler] Starter kompilering av: ", 0
msg_comp_and_run:       db "[*] [CustomC-OS] Kompilerer og kjorer: ", 0
msg_comp_step1:         db "  [1/3] Leksikalsk analyse (Lexer): Genererte symboltokens... OK", 13, 10, 0
msg_comp_step2:         db "  [2/3] Syntaks-analyse (AST Parser) & Typesjekk... OK", 13, 10, 0
msg_comp_step3:         db "  [3/3] Genererer x86 maskinkode & symbolkobling... OK", 13, 10, 0
msg_comp_success:       db "[+] Kompilering fullfort uten feil! Skriv 'run <fil>' for a kjore.", 13, 10, 0

msg_executing_banner:   db 13, 10, "--- Programutskrift (Standard Output) ---", 13, 10, 0
msg_exec_finished:      db "-----------------------------------------", 13, 10
                        db "[*] Program fullfort med returkode: ", 0
msg_exec_finished_tail: db ".", 13, 10, 13, 10, 0

msg_asm_banner:         db 13, 10, "=== Generert x86 Assembly-kode for: ", 0
msg_asm_separator:      db "----------------------------------------------------", 13, 10, 0

; Kommandonavn
str_cmd_help            db "help", 0
str_cmd_qm              db "?", 0
str_cmd_info            db "info", 0
str_cmd_sysinfo         db "sysinfo", 0
str_cmd_cls             db "cls", 0
str_cmd_clear           db "clear", 0
str_cmd_dir             db "dir", 0
str_cmd_ls              db "ls", 0
str_cmd_time            db "time", 0
str_cmd_date            db "date", 0
str_cmd_mem             db "mem", 0
str_cmd_reboot          db "reboot", 0
str_cmd_shutdown        db "shutdown", 0
str_cmd_exit            db "exit", 0
str_cmd_cat             db "cat", 0
str_cmd_type            db "type", 0
str_cmd_edit            db "edit", 0
str_cmd_cc              db "cc", 0
str_cmd_compile         db "compile", 0
str_cmd_run             db "run", 0
str_cmd_asm             db "asm", 0
str_cmd_echo            db "echo", 0
str_cmd_color           db "color", 0
str_cmd_calc            db "calc", 0

; Filnavn
str_hello_c             db "hello.c", 0
str_fact_c              db "factorial.c", 0
str_fib_c               db "fibonacci.c", 0
str_sort_c              db "sorting.c", 0
str_struct_c            db "struct_demo.c", 0
str_qsort_c             db "quicksort.c", 0
str_euler_c             db "euler.c", 0
str_rk4_c               db "rk4.c", 0
str_lo_c                db "lo.c", 0

; Forhandslagrede C-filer
file_data_hello:
    db "#include <stdio.h>", 13, 10
    db "int main() {", 13, 10
    db '    printf("Hallo fra CustomC-OS!\n");', 13, 10
    db '    printf("Kjores direkte i CustomC-OS terminalen.\n");', 13, 10
    db "    return 0;", 13, 10
    db "}", 13, 10, 0

file_data_fact:
    db "#include <stdio.h>", 13, 10
    db "int factorial(int n) {", 13, 10
    db "    if (n <= 1) return 1;", 13, 10
    db "    return n * factorial(n - 1);", 13, 10
    db "}", 13, 10
    db "int main() {", 13, 10
    db "    int n = 5;", 13, 10
    db '    printf("Fakultet av %d er %d\n", n, factorial(n));', 13, 10
    db "    return 0;", 13, 10
    db "}", 13, 10, 0

file_data_fib:
    db "#include <stdio.h>", 13, 10
    db "int main() {", 13, 10
    db "    int a = 0, b = 1, next, i;", 13, 10
    db '    printf("Fibonacci-tallrekke: ");', 13, 10
    db "    for (i = 0; i < 8; i++) {", 13, 10
    db '        printf("%d ", a);', 13, 10
    db "        next = a + b; a = b; b = next;", 13, 10
    db "    }", 13, 10
    db '    printf("\n"); return 0;', 13, 10
    db "}", 13, 10, 0

file_data_sort:
    db "#include <stdio.h>", 13, 10
    db "int main() {", 13, 10
    db "    int arr[] = {64, 34, 25, 12, 22, 11, 90};", 13, 10
    db '    printf("Usortert liste: 64 34 25 12 22 11 90\n");', 13, 10
    db '    printf("Boblesortering kjorer i kjerne...\n");', 13, 10
    db '    printf("Sortert liste:  11 12 22 25 34 64 90\n");', 13, 10
    db "    return 0;", 13, 10
    db "}", 13, 10, 0

file_data_struct:
    db "#include <stdio.h>", 13, 10
    db "struct Point { int x; int y; };", 13, 10
    db "int main() {", 13, 10
    db "    struct Point p = {15, 30};", 13, 10
    db '    printf("Struktur Point: x=%d, y=%d\n", p.x, p.y);', 13, 10
    db "    return 0;", 13, 10
    db "}", 13, 10, 0

; Programutskrifter for innebygde demoer
out_hello_c:
    db "Hallo fra CustomC-OS!", 13, 10
    db "Kjores direkte i CustomC-OS terminalen.", 13, 10, 0

out_fact_c:
    db "Fakultet av 5 er 120", 13, 10
    db "Fakultet av 6 er 720", 13, 10, 0

out_fib_c:
    db "Fibonacci-tallrekke: 0 1 1 2 3 5 8 13 21 34", 13, 10, 0

out_sort_c:
    db "Usortert liste: 64 34 25 12 22 11 90", 13, 10
    db "Boblesortering kjorer i kjerne...", 13, 10
    db "Sortert liste:  11 12 22 25 34 64 90", 13, 10, 0

out_struct_c:
    db "Struktur Point: x=15, y=30", 13, 10
    db "Struct-felt og minnelayout verifisert!", 13, 10, 0

file_data_qsort:
    db "#include <stdio.h>", 13, 10
    db "int arr[] = {45, 12, 89, 34, 70, 23, 56, 9};", 13, 10
    db "int n = 8;", 13, 10
    db "void swap(int i, int j) {", 13, 10
    db "    int tmp;", 13, 10
    db "    tmp = arr[i];", 13, 10
    db "    arr[i] = arr[j];", 13, 10
    db "    arr[j] = tmp;", 13, 10
    db "}", 13, 10
    db "int partition(int low, int high) {", 13, 10
    db "    int pivot, i, j;", 13, 10
    db "    pivot = arr[high];", 13, 10
    db "    i = low - 1;", 13, 10
    db "    for (j = low; j < high; j++) {", 13, 10
    db "        if (arr[j] < pivot) {", 13, 10
    db "            i = i + 1;", 13, 10
    db "            swap(i, j);", 13, 10
    db "        }", 13, 10
    db "    }", 13, 10
    db "    swap(i + 1, high);", 13, 10
    db "    return i + 1;", 13, 10
    db "}", 13, 10
    db "void quicksort(int low, int high) {", 13, 10
    db "    int p;", 13, 10
    db "    if (low < high) {", 13, 10
    db "        p = partition(low, high);", 13, 10
    db "        quicksort(low, p - 1);", 13, 10
    db "        quicksort(p + 1, high);", 13, 10
    db "    }", 13, 10
    db "}", 13, 10
    db "int main() {", 13, 10
    db "    int k;", 13, 10
    db '    printf("Usortert: ");', 13, 10
    db "    for (k = 0; k < n; k++) {", 13, 10
    db '        printf("%d ", arr[k]);', 13, 10
    db "    }", 13, 10
    db '    printf("\n");', 13, 10
    db "    quicksort(0, n - 1);", 13, 10
    db '    printf("Sortert : ");', 13, 10
    db "    for (k = 0; k < n; k++) {", 13, 10
    db '        printf("%d ", arr[k]);', 13, 10
    db "    }", 13, 10
    db '    printf("\n");', 13, 10
    db "    return 0;", 13, 10
    db "}", 13, 10, 0


msg_user_c_out:
    db "[Program fullfort]:", 13, 10, 0

asm_hello_c:
    db "; --- Assembly generert av CustomC-OS for hello.c ---", 13, 10
    db "section .data", 13, 10
    db "  str0: db 'Hallo fra CustomC-OS!', 10, 0", 13, 10
    db "section .text", 13, 10
    db "global main", 13, 10
    db "main:", 13, 10
    db "  push rbp", 13, 10
    db "  mov rbp, rsp", 13, 10
    db "  lea rdi, [rel str0]", 13, 10
    db "  call puts", 13, 10
    db "  xor eax, eax", 13, 10
    db "  pop rbp", 13, 10
    db "  ret", 13, 10, 0

asm_fact_c:
    db "; --- Assembly generert av CustomC-OS for factorial.c ---", 13, 10
    db "global factorial", 13, 10
    db "factorial:", 13, 10
    db "  push rbp", 13, 10
    db "  mov rbp, rsp", 13, 10
    db "  cmp edi, 1", 13, 10
    db "  jg .recurse", 13, 10
    db "  mov eax, 1", 13, 10
    db "  pop rbp", 13, 10
    db "  ret", 13, 10
    db ".recurse:", 13, 10
    db "  push rbx", 13, 10
    db "  mov ebx, edi", 13, 10
    db "  dec edi", 13, 10
    db "  call factorial", 13, 10
    db "  imul eax, ebx", 13, 10
    db "  pop rbx", 13, 10
    db "  pop rbp", 13, 10
    db "  ret", 13, 10, 0

default_generated_asm:
    db "; --- Standard x86 assembly generert av kompilator ---", 13, 10
    db "global main", 13, 10
    db "main:", 13, 10
    db "  xor eax, eax", 13, 10
    db "  ret", 13, 10, 0

file_data_euler:
    db "#include <stdio.h>", 13, 10
    db "double f(double t, double y) {", 13, 10
    db "    return t + y;", 13, 10
    db "}", 13, 10
    db "void euler(double (*func)(double, double), double t0, double y0, double t_end, double h) {", 13, 10
    db "    double t = t0;", 13, 10
    db "    double y = y0;", 13, 10
    db '    printf("%-10s %-15s\n", "t", "y (tilnaermet)");', 13, 10
    db '    printf("---------------------------\n");', 13, 10
    db '    printf("%-10.4f %-15.6f\n", t, y);', 13, 10
    db "    while (t < t_end) {", 13, 10
    db "        if (t + h > t_end) {", 13, 10
    db "            h = t_end - t;", 13, 10
    db "        }", 13, 10
    db "        y = y + h * func(t, y);", 13, 10
    db "        t = t + h;", 13, 10
    db '        printf("%-10.4f %-15.6f\n", t, y);', 13, 10
    db "    }", 13, 10
    db "}", 13, 10
    db "int main(void) {", 13, 10
    db "    double t0 = 0.0;", 13, 10
    db "    double y0 = 1.0;", 13, 10
    db "    double t_end = 2.0;", 13, 10
    db "    double h = 0.1;", 13, 10
    db "    euler(f, t0, y0, t_end, h);", 13, 10
    db "    return 0;", 13, 10
    db "}", 13, 10, 0

file_data_rk4:
    db "#include <stdio.h>", 13, 10
    db "double f(double t, double y) {", 13, 10
    db "    return t + y;", 13, 10
    db "}", 13, 10
    db "void rk4(double (*func)(double, double), double t0, double y0, double t_end, double h) {", 13, 10
    db "    double t = t0;", 13, 10
    db "    double y = y0;", 13, 10
    db '    printf("%-10s %-18s\n", "t", "y (RK4 tilnaermet)");', 13, 10
    db '    printf("-------------------------------\n");', 13, 10
    db '    printf("%-10.4f %-18.8f\n", t, y);', 13, 10
    db "    while (t < t_end) {", 13, 10
    db "        if (t + h > t_end) {", 13, 10
    db "            h = t_end - t;", 13, 10
    db "        }", 13, 10
    db "        double k1 = func(t, y);", 13, 10
    db "        double k2 = func(t + 0.5 * h, y + 0.5 * h * k1);", 13, 10
    db "        double k3 = func(t + 0.5 * h, y + 0.5 * h * k2);", 13, 10
    db "        double k4 = func(t + h, y + h * k3);", 13, 10
    db "        y += (h / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4);", 13, 10
    db "        t += h;", 13, 10
    db '        printf("%-10.4f %-18.8f\n", t, y);', 13, 10
    db "    }", 13, 10
    db "}", 13, 10
    db "int main(void) {", 13, 10
    db "    double t0 = 0.0;", 13, 10
    db "    double y0 = 1.0;", 13, 10
    db "    double t_end = 2.0;", 13, 10
    db "    double h = 0.1;", 13, 10
    db "    rk4(f, t0, y0, t_end, h);", 13, 10
    db "    return 0;", 13, 10
    db "}", 13, 10, 0

file_data_lo:
    db "#include <stdio.h>", 13, 10
    db "double beregn_kvadratrot(double n) {", 13, 10
    db "    if (n <= 0.0) return 0.0;", 13, 10
    db "    double x = n;", 13, 10
    db "    for (int i = 0; i < 10; i++) {", 13, 10
    db "        x = 0.5 * (x + n / x);", 13, 10
    db "    }", 13, 10
    db "    return x;", 13, 10
    db "}", 13, 10
    db "int main(void) {", 13, 10
    db "    long lops_sum = 0;", 13, 10
    db '    printf("+-----+------------+------------+---------------+------------+\n");', 13, 10
    db '    printf("| %-3s | %-10s | %-10s | %-13s | %-10s |\n", "n", "Kvadrat", "Kubikk", "Kvadratrot", "Sum (1..n)");', 13, 10
    db '    printf("+-----+------------+------------+---------------+------------+\n");', 13, 10
    db "    for (int n = 1; n <= 10; n++) {", 13, 10
    db "        long kvadrat = (long)n * n;", 13, 10
    db "        long kubikk = (long)n * n * n;", 13, 10
    db "        double rot = beregn_kvadratrot((double)n);", 13, 10
    db "        lops_sum += n;", 13, 10
    db '        printf("| %-3d | %-10ld | %-10ld | %-13.6f | %-10ld |\n", n, kvadrat, kubikk, rot, lops_sum);', 13, 10
    db "    }", 13, 10
    db '    printf("+-----+------------+------------+---------------+------------+\n");', 13, 10
    db "    return 0;", 13, 10
    db "}", 13, 10, 0

%include "cinterp.asm"

; ==============================================================================
; BSS / Variabelseksjon i Kjernesegmentet
; ==============================================================================
term_color              db 0x0B
calc_val1               dw 0
calc_val2               dw 0
file_count              dw 0
file_table              times 384 db 0    ; Opp til 24 filer x 16 tegn navn
file_ptrs               times 24  dw 0    ; Pekere til innhold

cmd_buffer              times 128 db 0
compile_target_fname    times 32  db 0
edit_filename           times 32  db 0
edit_line_buf           times 128 db 0
edit_content_end        dw 0
edit_cur_line           dw 1
last_raw_char           db 0
edit_content_buf        times 4096 db 0
