; Exact-build DOS installer with an embedded, independently built GF1 launcher.
bits 16
org 100h
jmp start
%include "install_tables.inc"
start:
    cld
    push cs
    pop ds
    push cs
    pop es
    cmp byte [80h],0
    je .args_ok
    cmp byte [82h],'/'
    jne usage
    mov al,[83h]
    and al,0dfh
    cmp al,'R'
    jne usage
    mov byte [restore_mode],1
.args_ok:
    mov dx,banner
    call print
    ; Both supported builds have the same first filename but distinct CRCs.
    ; Select a whole-version table before the preflight can write anything.
    mov dx,[targets12]
    call crc_file
    jc failed
    mov word [target_table],targets12
    cmp eax,[targets12+4]
    je .selected
    cmp eax,[targets12+8]
    je .selected
    mov word [target_table],targets10
    cmp eax,[targets10+4]
    je .selected
    cmp eax,[targets10+8]
    jne unsupported
.selected:
    mov si,[target_table]
    xor di,di
.preflight:
    mov dx,[si]
    call crc_file
    jc failed
    mov byte [file_patched],0
    cmp eax,[si+4]
    je .known
    cmp eax,[si+8]
    jne unsupported
    mov byte [file_patched],1
.known:
    mov dx,[si+2]
    call crc_file
    jnc .have_backup
    cmp word [io_error],2
    jne failed
    cmp byte [restore_mode],1
    je missing_backup
    cmp byte [file_patched],1
    je missing_backup
    mov byte [backup_present+di],0
    jmp .next_check
.have_backup:
    cmp eax,[si+4]
    jne bad_backup
    mov byte [backup_present+di],1
.next_check:
    add si,TARGET_SIZE
    inc di
    cmp di,TARGET_COUNT
    jb .preflight
    mov si,[target_table]
    xor di,di
.write:
    cmp byte [restore_mode],1
    jne .install
    mov dx,[si+2]
    mov bx,[si]
    call copy_file
    jc failed
    jmp .verify
.install:
    cmp byte [backup_present+di],1
    je .patch
    mov dx,[si]
    mov bx,[si+2]
    call copy_file
    jc failed
.patch:
    mov dx,[si]
    mov ax,3d02h
    int 21h
    jc failed
    mov [file_handle],ax
    mov bp,[si+12]
    mov ax,[si+14]
    mov [patch_count],ax
.patch_loop:
    mov bx,[file_handle]
    mov dx,[bp]
    mov cx,[bp+2]
    mov ax,4200h
    int 21h
    jc failed
    mov cx,[bp+4]
    lea dx,[bp+6]
    mov ah,40h
    int 21h
    jc failed
    cmp ax,cx
    jne failed
    add bp,6
    add bp,cx
    dec word [patch_count]
    jnz .patch_loop
    mov bx,[file_handle]
    mov ah,3eh
    int 21h
.verify:
    mov dx,[si]
    call crc_file
    jc failed
    cmp byte [restore_mode],1
    je .check_original
    cmp eax,[si+8]
    jne failed
    jmp .next_write
.check_original:
    cmp eax,[si+4]
    jne failed
.next_write:
    add si,TARGET_SIZE
    inc di
    cmp di,TARGET_COUNT
    jb .write
    cmp byte [restore_mode],1
    je .restore_report
    call write_launcher
    jc failed
    mov dx,installed
    jmp .report
.restore_report:
    mov dx,restored
.report:
    call print
    mov ax,4c00h
    int 21h
unsupported:
    mov dx,msg_unsupported
    jmp error
missing_backup:
    mov dx,msg_missing
    jmp error
bad_backup:
    mov dx,msg_backup
    jmp error
failed:
    mov dx,msg_io
error:
    call print
    mov ax,4c01h
    int 21h
usage:
    mov dx,msg_usage
    jmp error
print:
    mov ah,09h
    int 21h
    ret

; Create or replace ACGUS.COM after the game hooks have all verified.
; The launcher is embedded so the DOS installer works as a single file.
write_launcher:
    mov dx,launcher_name
    xor cx,cx
    mov ah,3ch
    int 21h
    jc .fail
    mov [file_handle],ax
    mov bx,ax
    mov dx,launcher_blob
    mov cx,launcher_end-launcher_blob
    mov ah,40h
    int 21h
    pushf
    push ax
    mov bx,[file_handle]
    mov ah,3eh
    int 21h
    setc byte [close_failed]
    pop ax
    popf
    jc .fail
    cmp ax,launcher_end-launcher_blob
    jne .fail
    cmp byte [close_failed],0
    jne .fail
    clc
    ret
.fail:
    stc
    ret

; DS:DX filename -> EAX CRC32, CF error. All 16-bit index registers preserved.
crc_file:
    pusha
    mov ax,3d00h
    int 21h
    jc .open_fail
    mov [file_handle],ax
    mov edi,0ffffffffh
.read:
    mov bx,[file_handle]
    mov dx,buffer
    mov cx,512
    mov ah,3fh
    int 21h
    jc .read_fail
    test ax,ax
    jz .end
    mov cx,ax
    mov si,buffer
.byte:
    movzx eax,byte [si]
    xor eax,edi
    and eax,255
    shl ax,2
    mov bx,ax
    mov eax,[crc_table+bx]
    shr edi,8
    xor edi,eax
    inc si
    loop .byte
    jmp .read
.end:
    xor edi,0ffffffffh
    mov [crc_result],edi
    mov bx,[file_handle]
    mov ah,3eh
    int 21h
    popa
    mov eax,[crc_result]
    clc
    ret
.read_fail:
    mov [io_error],ax
    mov bx,[file_handle]
    mov ah,3eh
    int 21h
    jmp .return_error
.open_fail:
    mov [io_error],ax
.return_error:
    popa
    stc
    ret

; DS:DX source, DS:BX destination. Preflight protects existing backups.
copy_file:
    pusha
    mov [dest_name],bx
    mov ax,3d00h
    int 21h
    jc .fail
    mov [source_handle],ax
    mov dx,[dest_name]
    xor cx,cx
    mov ah,3ch
    int 21h
    jc .close_source_fail
    mov [dest_handle],ax
.loop:
    mov bx,[source_handle]
    mov dx,buffer
    mov cx,512
    mov ah,3fh
    int 21h
    jc .close_both_fail
    test ax,ax
    jz .success
    mov cx,ax
    mov bx,[dest_handle]
    mov ah,40h
    int 21h
    jc .close_both_fail
    cmp ax,cx
    jne .close_both_fail
    jmp .loop
.success:
    call .close_both
    popa
    clc
    ret
.close_both_fail:
    call .close_both
    jmp .fail
.close_source_fail:
    mov bx,[source_handle]
    mov ah,3eh
    int 21h
.fail:
    popa
    stc
    ret
.close_both:
    mov bx,[dest_handle]
    mov ah,3eh
    int 21h
    mov bx,[source_handle]
    mov ah,3eh
    int 21h
    ret

banner db 'ACGUS 1.0 unified installer - exact build validation',13,10,'$'
installed db 'Installed ACGUS.COM. Start the game with ACGUS.',13,10,'$'
restored db 'Original game files restored. Backups retained.',13,10,'$'
msg_usage db 'Usage: INSTALL or INSTALL /R (restore)',13,10,'$'
msg_unsupported db 'ERROR: unsupported or modified game file. No installation performed.',13,10,'$'
msg_missing db 'ERROR: an original .ACB backup is required.',13,10,'$'
msg_backup db 'ERROR: backup checksum does not match the supported build.',13,10,'$'
msg_io db 'ERROR: file operation or verification failed. Retain .ACB backups.',13,10,'$'
restore_mode db 0
file_patched db 0
backup_present times TARGET_COUNT db 0
file_handle dw 0
source_handle dw 0
dest_handle dw 0
dest_name dw 0
io_error dw 0
patch_count dw 0
target_table dw 0
close_failed db 0
crc_result dd 0
buffer times 512 db 0
launcher_name db 'ACGUS.COM',0
launcher_blob:
incbin "../dist/ACGUS.COM"
launcher_end:
