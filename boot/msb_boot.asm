; ==============================================================================
; CustomC-OS: Master Boot Sector (MSB / MBR)
; Loaded by BIOS at 0000:7C00h
; Size: Exactly 512 bytes with boot signature 0xAA55
; ==============================================================================
bits 16
org 0x7C00

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [boot_drive], dl

    ; Sett 80x25 tekstmodus (VGA modus 3)
    mov ax, 0x0003
    int 0x10

    ; Skriv ut MSB oppstart
    mov si, msg_banner
    call print_str

    ; Nullstill disk
    mov ah, 0x00
    mov dl, [boot_drive]
    int 0x13
    jc disk_err

    ; Last kjerne: 64 sektorer fra Sektor 2 til 0x1000:0000
    mov ax, 0x1000
    mov es, ax
    xor bx, bx

    mov ah, 0x02        ; Les sektorer
    mov al, 64          ; Antall sektorer (32 KB)
    mov ch, 0           ; Sylinder 0
    mov cl, 2           ; Sektor 2
    mov dh, 0           ; Hode 0
    mov dl, [boot_drive]
    int 0x13
    jc disk_err

    mov si, msg_ok
    call print_str

    ; Hopp til CustomC-OS Kjernen
    jmp 0x1000:0000

disk_err:
    mov si, msg_err
    call print_str
hang:
    hlt
    jmp hang

print_str:
    push ax
    push bx
.l:
    lodsb
    test al, al
    jz .d
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x0B
    int 0x10
    jmp .l
.d:
    pop bx
    pop ax
    ret

boot_drive db 0
msg_banner db "[MSB] CustomC-OS Master Boot Sector v2.0", 13, 10
           db "[MSB] Laster kjerne fra disk...", 13, 10, 0
msg_ok     db "[MSB] Boot OK! Starter terminal...", 13, 10, 13, 10, 0
msg_err    db "[MSB] Diskfeil!", 13, 10, 0

times 510-($-$$) db 0
dw 0xAA55
