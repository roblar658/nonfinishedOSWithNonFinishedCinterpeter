; ==============================================================================
; CustomC-OS - Pure x86-64 Assembly C Compiler
; defs.inc - Constants, Token Types, and Global Structures
; ==============================================================================

; ------------------------------------------------------------------------------
; Macros
; ------------------------------------------------------------------------------
%macro emit_indent 0
    call do_emit_indent
%endmacro

; ------------------------------------------------------------------------------
; Token Constants
; ------------------------------------------------------------------------------
TOK_EOF         equ 0

; Keywords (256..275)
TOK_INT         equ 256
TOK_CHAR        equ 257
TOK_VOID        equ 258
TOK_STRUCT      equ 259
TOK_IF          equ 260
TOK_ELSE        equ 261
TOK_WHILE       equ 262
TOK_FOR         equ 263
TOK_DO          equ 264
TOK_RETURN      equ 265
TOK_SIZEOF      equ 266
TOK_BREAK       equ 267
TOK_CONTINUE    equ 268
TOK_SWITCH      equ 269
TOK_CASE        equ 270
TOK_DEFAULT     equ 271
TOK_EXTERN      equ 272

; Literals & Identifiers (280..289)
TOK_IDENT       equ 280
TOK_NUM         equ 281
TOK_STR         equ 282
TOK_CHAR_LIT    equ 283

; Multi-character Operators (290..320)
TOK_EQ          equ 290  ; ==
TOK_NE          equ 291  ; !=
TOK_LE          equ 292  ; <=
TOK_GE          equ 293  ; >=
TOK_SHL         equ 294  ; <<
TOK_SHR         equ 295  ; >>
TOK_LOGAND      equ 296  ; &&
TOK_LOGOR       equ 297  ; ||
TOK_INC         equ 298  ; ++
TOK_DEC         equ 299  ; --
TOK_ARROW       equ 300  ; ->
TOK_ADD_ASSIGN  equ 301  ; +=
TOK_SUB_ASSIGN  equ 302  ; -=
TOK_MUL_ASSIGN  equ 303  ; *=
TOK_DIV_ASSIGN  equ 304  ; /=
TOK_MOD_ASSIGN  equ 305  ; %=
TOK_AND_ASSIGN  equ 306  ; &=
TOK_OR_ASSIGN   equ 307  ; |=
TOK_XOR_ASSIGN  equ 308  ; ^=
TOK_SHL_ASSIGN  equ 309  ; <<=
TOK_SHR_ASSIGN  equ 310  ; >>=

; Single-character tokens represent themselves by ASCII code:
; '+', '-', '*', '/', '%', '&', '|', '^', '~', '!', '<', '>', '=',
; '(', ')', '{', '}', '[', ']', ';', ',', ':', '?', '.'

; ------------------------------------------------------------------------------
; Type System Constants
; ------------------------------------------------------------------------------
TYPE_VOID       equ 0
TYPE_CHAR       equ 1   ; size = 1
TYPE_INT        equ 2   ; size = 8 (64-bit uniform integer)
TYPE_STRUCT     equ 3   ; size = variable (from struct table)

; ------------------------------------------------------------------------------
; Buffer Sizes & Limits
; ------------------------------------------------------------------------------
SRC_BUF_SIZE    equ 1048576     ; 1 MB source buffer
OUT_BUF_SIZE    equ 4194304     ; 4 MB output buffer
MAX_IDENT_LEN   equ 64
MAX_STR_LEN     equ 2048
MAX_GLOBALS     equ 512
MAX_LOCALS      equ 512
MAX_STRUCTS     equ 128
MAX_MEMBERS     equ 1024
MAX_EXTERNS     equ 256
MAX_STRINGS     equ 1024
MAX_LOOP_DEPTH  equ 64
MAX_SWITCH_CASES equ 128

; ------------------------------------------------------------------------------
; Structure Layouts (Sizes in bytes)
; ------------------------------------------------------------------------------
; Type Descriptor: (kind: 8, ptr_level: 8, is_array: 8, array_len: 8, struct_id: 8, size: 8)
TYPE_DESC_SIZE  equ 48

; Global Symbol Entry:
;   name: 64 bytes
;   type_desc: 48 bytes (kind, ptr_level, is_array, array_len, struct_id, size)
;   init_val: 8 bytes
;   is_defined: 8 bytes
;   str_label: 8 bytes (if string literal)
GLOBAL_ENTRY_SIZE equ (64 + 48 + 8 + 8 + 8)

; Local Symbol Entry:
;   name: 64 bytes
;   type_desc: 48 bytes
;   stack_offset: 8 bytes (offset below RBP)
LOCAL_ENTRY_SIZE equ (64 + 48 + 8)

; Struct Definition Entry:
;   name: 64 bytes
;   total_size: 8 bytes
;   member_count: 8 bytes
;   first_member_idx: 8 bytes
STRUCT_ENTRY_SIZE equ (64 + 8 + 8 + 8)

; Struct Member Entry:
;   name: 64 bytes
;   offset: 8 bytes
;   type_desc: 48 bytes
MEMBER_ENTRY_SIZE equ (64 + 8 + 48)
