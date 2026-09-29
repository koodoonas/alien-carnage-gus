; ACGUS - Alien Carnage GF1 bridge; based on PRE2GUS/ACGUS original patch code.
; No original executable or audio data is embedded.
bits 16
org 100h

%define MOD_HEADER_BYTES    1084
%define MOD_PATTERN_LIMIT   32768
%define MUSIC_DRAM_LOW      0000h
%define MUSIC_DRAM_HIGH     0001h       ; 0x10000
%define SFX_BANK_BYTES      60498
%define IO_BUFFER_BYTES     512
%define SELFTEST_TICKS      250
%define SELFTEST_BIOS_TICKS 128

%define PATCH_SFX_OFF       03DDh
%define PATCH_SONG_OFF      4814h
%define PATCH_INIT_OFF      4075h
%define PATCH_SIG_OFF       0003h

    jmp start

; ---------------------------------------------------------------------------
; Startup and DOS launcher

start:
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    sti
    mov ds, ax
    mov es, ax
    cld
    mov [psp_segment], ax

    mov dx, msg_banner
    call print_dos
    call parse_command_line
    jc fatal_args
    call show_music_pan
    call parse_ultrasnd
    jc fatal_config
    call setup_gus_ports

    ; Put our stack inside the retained block, then return unused DOS memory.
    mov bx, RESIDENT_PARAS
    mov ah, 4Ah
    int 21h
    jc fatal_memory

    mov ax, [psp_segment]
    add ax, RESIDENT_PARAS
    mov [patch_scan_start], ax
    add ax, 1000h                ; child PSP/code must be in the next 64 KiB
    cmp ax, 0A000h
    jbe .scan_limit_ready
    mov ax, 0A000h
.scan_limit_ready:
    mov [patch_scan_limit], ax

    call gus_reset
    call gus_probe
    jc fatal_gus
    call gus_probe_512k
    jc fatal_gus_memory
    call gus_set_interface
    mov dx,msg_preload
    call print_dos
    call install_vectors
%ifdef TRACE
    mov dx,trace_name
    xor cx,cx
    mov ah,3ch
    int 21h
    mov [trace_handle],ax
%endif

    cmp byte [test_mode], 0
    jne run_selftest

    call exec_game
    mov [exec_error], ax
    mov byte [exec_failed], 0
    jnc .child_returned
    mov byte [exec_failed], 1
    jmp .after_child
.child_returned:
    mov ah, 4Dh
    int 21h
    mov [child_exit_code], al
.after_child:
    call cleanup
%ifdef DUMP_CODE
    call write_code_dump
%endif

    cmp byte [exec_failed], 0
    je .report_patch
    mov dx, msg_exec_failed
    call print_dos
    mov ax, [exec_error]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
    mov al, 1
    jmp exit_dos

.report_patch:
    cmp byte [patch_installed], 1
    jne .not_patched
    mov dx, msg_patch_ok
    call print_dos
    jmp .report_song
.not_patched:
    mov dx, msg_patch_missing
    call print_dos
.report_song:
%ifdef DUMP_CODE
    mov dx, msg_patch_trigger
    call print_dos
    mov ax, [patch_trigger_ax]
    call print_hex_word
    mov dx, msg_patch_trigger_ip
    call print_dos
    mov ax, [patch_trigger_ip]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
%endif
    cmp byte [song_error], 0
    je .report_counts
    mov dx, msg_song_error
    call print_dos
.report_counts:
    mov dx, msg_audio_counts
    call print_dos
    mov ax, [songs_loaded]
    call print_hex_word
    mov dx, msg_audio_sfx
    call print_dos
    mov ax, [sfx_played]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
    mov al, [child_exit_code]
    jmp exit_dos

run_selftest:
    mov dx,msg_test_start
    call print_dos
    call gus_timer_start
    mov bx,[total_ticks]
    add bx,250
.wait:
    cmp [total_ticks],bx
    jae .done
    sti
    hlt
    jmp .wait
.done:
    call cleanup
    mov dx,msg_test_ok
    call print_dos
    xor al,al
    jmp exit_dos

fatal_config:
    mov dx, msg_bad_config
    jmp fatal_plain
fatal_args:
    mov dx, msg_bad_args
    jmp fatal_plain
fatal_memory:
    mov dx, msg_no_memory
    jmp fatal_plain
fatal_gus:
    call gus_quiet
    mov dx, msg_no_gus
    call print_dos
    mov dx, msg_probe_detail
    call print_dos
    mov ax, [gus_base]
    call print_hex_word
    mov dx, msg_probe_values
    call print_dos
    xor ax, ax
    mov al, [probe_value0]
    call print_hex_word
    mov dl, '/'
    mov ah, 02h
    int 21h
    xor ax, ax
    mov al, [probe_value1]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
    mov al, 1
    jmp exit_dos
fatal_gus_memory:
    mov dx, msg_gus_memory
    jmp fatal_quiet
fatal_quiet:
    push dx
    call gus_quiet
    pop dx
fatal_plain:
    call print_dos
    mov al, 1

exit_dos:
    mov ah, 4Ch
    int 21h

print_dos:
    mov ah, 09h
    int 21h
    ret

; Optional /D diagnostics: small in-memory ring, written only after the game
; returns to DOS. No DOS call is made from the GF1 IRQ or game audio hook.
diag_log_event:
    push ax
    push bx
    push di
    mov bx,[diag_count]
    and bx,255
    shl bx,4
    mov di,diag_records
    add di,bx
    mov [di+2],al
    mov ax,[total_ticks]
    mov [di],ax
    mov al,[music_active]
    mov [di+3],al
    mov al,[timer_started]
    mov [di+4],al
    mov al,[tracker_order]
    mov [di+5],al
    mov ax,[tracker_row]
    mov [di+6],ax
    mov ax,[songs_loaded]
    mov [di+8],ax
    mov ax,[sfx_played]
    mov [di+10],ax
    mov ax,[request_sfx_segment]
    mov [di+12],ax
    mov al,[sfx_round_robin]
    mov [di+14],al
    mov al,[music_one_shot]
    mov [di+15],al
    inc word [diag_count]
    pop di
    pop bx
    pop ax
    ret

; Snapshot music voice control and volume around an effect (81h/82h).
diag_log_hardware:
    pushf
    cli
    push ax
    push bx
    push cx
    push dx
    push di
    mov bl,al
    mov di,[diag_count]
    and di,255
    shl di,4
    add di,diag_records
    mov ax,[total_ticks]
    mov [di],ax
    mov [di+2],bl
    xor cx,cx
.control:
    mov dx,[gus_voice_port]
    mov ax,cx
    out dx,al
    mov dx,[gus_command_port]
    mov al,80h
    out dx,al
    mov dx,[gus_data_high_port]
    in al,dx
    mov bx,cx
    mov [di+3+bx],al
    mov dx,[gus_command_port]
    mov al,89h
    out dx,al
    mov dx,[gus_data_low_port]
    in ax,dx
    shl bx,1
    mov [di+7+bx],ax
    inc cx
    cmp cx,4
    jb .control
    mov al,[sfx_round_robin]
    mov [di+15],al
    inc word [diag_count]
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret

; First byte read back from GF1 DRAM after a new effect upload (83h).
; ES still points one paragraph before the game's decoded sample.
diag_log_sample:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov di,[diag_count]
    and di,255
    shl di,4
    add di,diag_records
    mov ax,[total_ticks]
    mov [di],ax
    mov byte [di+2],83h
    mov ax,[request_sfx_segment]
    mov [di+3],ax
    mov [di+5],cx
    shl bx,2
    mov ax,[sfx_cache_address+bx]
    mov [di+7],ax
    mov [dram_addr_low],ax
    mov ax,[sfx_cache_address+bx+2]
    mov [di+9],ax
    mov [dram_addr_high],ax
    mov al,[es:10h]
    mov [di+11],al
    call gus_peek
    mov [di+12],al
    mov ax,[sfx_next_address]
    mov [di+13],ax
    mov byte [di+15],0
    mov dx,cx
    shr dx,4
    jnz .stride_ready
    inc dx
.stride_ready:
    xor si,si
    mov bp,16
.spot:
    mov ax,[sfx_cache_address+bx]
    add ax,si
    mov [dram_addr_low],ax
    mov ax,[sfx_cache_address+bx+2]
    adc ax,0
    mov [dram_addr_high],ax
    call gus_peek
    cmp al,[es:si+10h]
    je .spot_ok
    inc byte [di+15]
.spot_ok:
    add si,dx
    dec bp
    jnz .spot
    inc word [diag_count]
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Capture the ten effect voices' hardware stop bits as music continues.
; A voice still running long after its sample should have ended indicates
; an address, frequency, or stop-control problem on the physical GF1.
diag_log_effect_voices:
    pushf
    cli
    push ax
    push bx
    push cx
    push dx
    push di
    mov di,[diag_count]
    and di,255
    shl di,4
    add di,diag_records
    mov ax,[total_ticks]
    mov [di],ax
    mov byte [di+2],84h
    mov cx,4
.voice:
    mov dx,[gus_voice_port]
    mov ax,cx
    out dx,al
    mov dx,[gus_command_port]
    mov al,80h
    out dx,al
    mov dx,[gus_data_high_port]
    in al,dx
    mov bx,cx
    dec bx
    mov [di+bx],al          ; voice 4 -> byte 3, voice 13 -> byte 12
    inc cx
    cmp cx,14
    jb .voice
    mov al,[music_active]
    mov [di+13],al
    mov ax,[sfx_played]
    mov [di+14],ax
    inc word [diag_count]
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret

; Music upload end and the selected effect cache base (86h).
diag_log_memory_map:
    push ax
    push bx
    push di
    mov di,[diag_count]
    and di,255
    shl di,4
    add di,diag_records
    mov ax,[total_ticks]
    mov [di],ax
    mov byte [di+2],86h
    mov eax,[music_dram_end]
    mov [di+3],eax
    mov eax,[sfx_next_address]
    mov [di+7],eax
    mov ax,[request_module]
    mov [di+11],ax
    mov al,[mod_song_length]
    mov [di+13],al
    mov al,[song_error]
    mov [di+14],al
    mov byte [di+15],0
    inc word [diag_count]
    pop di
    pop bx
    pop ax
    ret

; Current frequency of all four tracker voices and current high address of
; voices 0 and 1. Called around effects and on periodic GF1 timer records.
diag_log_music_positions:
    pushf
    cli
    push ax
    push bx
    push cx
    push dx
    push di
    mov di,[diag_count]
    and di,255
    shl di,4
    add di,diag_records
    mov ax,[total_ticks]
    mov [di],ax
    mov byte [di+2],87h
    xor cx,cx
.voice:
    mov dx,[gus_voice_port]
    mov ax,cx
    out dx,al
    mov dx,[gus_command_port]
    mov al,81h
    out dx,al
    mov dx,[gus_data_low_port]
    in ax,dx
    mov bx,cx
    shl bx,1
    mov [di+3+bx],ax
    cmp cx,2
    jae .next
    mov dx,[gus_command_port]
    mov al,8Ah
    out dx,al
    mov dx,[gus_data_low_port]
    in ax,dx
    mov [di+11+bx],ax
.next:
    inc cx
    cmp cx,4
    jb .voice
    mov al,[music_active]
    mov [di+15],al
    inc word [diag_count]
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret

write_diag:
    cmp byte [diag_mode],1
    jne .done
    mov dx,diag_name
    xor cx,cx
    mov ah,3ch
    int 21h
    jc .done
    mov bx,ax
    mov dx,diag_header
    mov cx,diag_records_end-diag_header
    mov ah,40h
    int 21h
    mov ah,3eh
    int 21h
.done:
    ret

print_hex_word:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    mov cx, 4
.digit:
    rol bx, 4
    mov dl, bl
    and dl, 0Fh
    add dl, '0'
    cmp dl, '9'
    jbe .emit
    add dl, 7
.emit:
    mov ah, 02h
    int 21h
    loop .digit
    pop dx
    pop cx
    pop bx
    pop ax
    ret

%ifdef DUMP_CODE
write_code_dump:
    cmp byte [code_dumped], 1
    jne .done
    mov dx, code_dump_filename
    xor cx, cx
    mov ah, 3Ch
    int 21h
    jc .done
    mov bx, ax
    mov dx, code_dump
    mov cx, 1000h
    mov ah, 40h
    int 21h
    mov ah, 3Eh
    int 21h
.done:
    ret
%endif

; The PSP tail belongs to the launcher, not to CARNAGE.EXE.  Parse switches in
; either order, and reject typos before touching the GF1.  OCP's -vp spelling
; is accepted as an alias; negative percentages reverse L/R music channels.
parse_command_line:
    mov byte [test_mode], 0
    mov byte [pan_percent], 60    ; v1.1's fixed GF1 positions were 3/12
    mov byte [pan_reverse], 0
    mov byte [pan_seen], 0
    xor cx, cx
    mov cl, [80h]
    mov si, 81h
.next:
    or cx, cx
    jz .success
    mov al, [si]
    dec cx
    inc si
    cmp al, ' '
    je .next
    cmp al, 9
    je .next
    cmp al, '/'
    je .switch
    cmp al, '-'
    jne .fail
.switch:
    or cx, cx
    jz .fail
    mov al, [si]
    inc si
    dec cx
    and al, 0DFh
    xor bh, bh
    cmp al, 'V'
    jne .kind
    mov bh, 1
    or cx, cx
    jz .fail
    mov al, [si]
    inc si
    dec cx
    and al, 0DFh
.kind:
    cmp al, 'T'
    je .test
    cmp al, 'P'
    je .pan
    cmp al, 'D'
    je .diagnostic
    jmp .fail
.test:
    or bh, bh
    jnz .fail
    cmp byte [test_mode], 0
    jne .fail
    mov byte [test_mode], 1
    jmp .token_end
.diagnostic:
    or bh,bh
    jnz .fail
    cmp byte [diag_mode],0
    jne .fail
    mov byte [diag_mode],1
    jmp .token_end
.pan:
    cmp byte [pan_seen], 0
    jne .fail
    mov byte [pan_seen], 1
    jcxz .fail
    mov al, [si]
    cmp al, '='
    je .separator
    cmp al, ':'
    jne .sign
.separator:
    inc si
    dec cx
    jcxz .fail
.sign:
    mov al, [si]
    cmp al, '-'
    jne .plus
    mov byte [pan_reverse], 1
    jmp .skip_sign
.plus:
    cmp al, '+'
    jne .first_digit
.skip_sign:
    inc si
    dec cx
    jcxz .fail
.first_digit:
    mov di, si
    xor bx, bx
.digits:
    jcxz .number_done
    mov al, [si]
    cmp al, '0'
    jb .number_done
    cmp al, '9'
    ja .number_done
    sub al, '0'
    mov dl, al
    mov ax, bx
    shl bx, 1
    shl ax, 3
    add bx, ax
    xor dh, dh
    add bx, dx
    cmp bx, 100
    ja .fail
    inc si
    dec cx
    jmp .digits
.number_done:
    cmp si, di
    je .fail
    mov [pan_percent], bl
.token_end:
    jcxz .success
    mov al, [si]
    cmp al, ' '
    je .next
    cmp al, 9
    je .next
    jmp .fail
.success:
    call set_music_pan
    clc
    ret
.fail:
    stc
    ret

; Map a signed 0..100 percent width to GF1's discrete 0..15 pan register.
; Zero uses 7/7 (both channels centered).  +60 gives 3/12, exactly v1.1.
set_music_pan:
    mov al, [pan_percent]
    or al, al
    jnz .scale
    mov bl, 7
    mov bh, 7
    jmp .store
.scale:
    mov bl, 100
    sub bl, al
    mov al, bl
    mov bl, 15
    mul bl                      ; (100 - width) * 15
    add ax, 100                 ; rounded to nearest GF1 pan step
    xor dx, dx
    mov bx, 200
    div bx
    mov bl, al
    mov bh, 15
    sub bh, bl
    cmp byte [pan_reverse], 0
    je .store
    xchg bl, bh
.store:
    mov [music_pan], bl
    mov [music_pan+1], bh
    mov [music_pan+2], bh
    mov [music_pan+3], bl
    ret

show_music_pan:
    mov dx, msg_pan
    call print_dos
    mov dl, '+'
    cmp byte [pan_reverse], 0
    je .sign_ready
    mov dl, '-'
.sign_ready:
    mov ah, 02h
    int 21h
    mov al, [pan_percent]
    call print_decimal_byte
    mov dx, msg_pan_end
    call print_dos
    ret

print_decimal_byte:
    xor ah, ah
    mov bl, 10
    div bl
    mov bl, ah                   ; ones digit
    xor ah, ah
    mov dl, 10
    div dl
    mov bh, ah                   ; tens digit
    or al, al
    jz .tens
    add al, '0'
    mov dl, al
    mov ah, 02h
    int 21h
.tens:
    cmp bh, 0
    jne .print_tens
    cmp byte [pan_percent], 100
    jne .ones
.print_tens:
    mov dl, bh
    add dl, '0'
    mov ah, 02h
    int 21h
.ones:
    mov dl, bl
    add dl, '0'
    mov ah, 02h
    int 21h
    ret

exec_game:
    push cs
    pop ds
    push cs
    pop es
    mov word [exec_params], 0
    mov ax, [psp_segment]
    mov word [exec_params+2], exec_tail
    mov word [exec_params+4], ax
    mov word [exec_params+6], 5Ch
    mov word [exec_params+8], ax
    mov word [exec_params+10], 6Ch
    mov word [exec_params+12], ax
    mov dx, game_filename
    mov bx, exec_params
    mov ax, 4B00h
    int 21h
    ret

; ---------------------------------------------------------------------------
; ULTRASND parsing

parse_ultrasnd:
    push es
    mov ax, [2Ch]
    or ax, ax
    jz .fail
    mov es, ax
    xor di, di
.next_string:
    cmp byte [es:di], 0
    jne .compare
    cmp byte [es:di+1], 0
    je .fail
    inc di
    jmp .next_string
.compare:
    push di
    mov si, ultrasnd_key
    mov cx, 9
.compare_char:
    mov al, [es:di]
    cmp al, 'a'
    jb .already_upper
    cmp al, 'z'
    ja .already_upper
    sub al, 20h
.already_upper:
    cmp al, [si]
    jne .not_this
    inc di
    inc si
    loop .compare_char
    pop bx                       ; discard original string offset

    call parse_hex_component
    jc .fail
    mov [gus_base], ax
    call require_comma
    jc .fail
    call parse_dec_component
    jc .fail
    mov [gus_dma1], ax
    call require_comma
    jc .fail
    call parse_dec_component
    jc .fail
    mov [gus_dma2], ax
    call require_comma
    jc .fail
    call parse_dec_component
    jc .fail
    mov [gus_irq], ax
    call require_comma
    jc .fail
    call parse_dec_component
    jc .fail
    mov [gus_midi_irq], ax
    cmp byte [es:di], 0
    jne .fail

    mov ax, [gus_base]
    cmp ax, 210h
    jb .fail
    cmp ax, 260h
    ja .fail
    test al, 0Fh
    jnz .fail

    mov bx, [gus_dma1]
    cmp bx, 7
    ja .fail
    cmp byte [dma_lut+bx], 0
    je .fail
    mov bx, [gus_dma2]
    cmp bx, 7
    ja .fail
    cmp byte [dma_lut+bx], 0
    je .fail
    mov bx, [gus_irq]
    cmp bx, 15
    ja .fail
    cmp byte [irq_lut+bx], 0
    je .fail
    mov bx, [gus_midi_irq]
    cmp bx, 15
    ja .fail
    cmp byte [irq_lut+bx], 0
    je .fail
    pop es
    clc
    ret

.not_this:
    pop di
.skip_string:
    cmp byte [es:di], 0
    je .past_string
    inc di
    jmp .skip_string
.past_string:
    inc di
    jmp .next_string
.fail:
    pop es
    stc
    ret

require_comma:
    cmp byte [es:di], ','
    jne .bad
    inc di
    clc
    ret
.bad:
    stc
    ret

parse_hex_component:
    xor bx, bx
    xor cx, cx
.loop:
    mov al, [es:di]
    cmp al, ','
    je .end
    or al, al
    jz .end
    cmp al, '0'
    jb .bad
    cmp al, '9'
    jbe .number
    and al, 0DFh
    cmp al, 'A'
    jb .bad
    cmp al, 'F'
    ja .bad
    sub al, 'A'-10
    jmp .add
.number:
    sub al, '0'
.add:
    shl bx, 4
    xor ah, ah
    add bx, ax
    inc di
    inc cx
    jmp .loop
.end:
    jcxz .bad
    mov ax, bx
    clc
    ret
.bad:
    stc
    ret

parse_dec_component:
    xor bx, bx
    xor cx, cx
.loop:
    mov al, [es:di]
    cmp al, ','
    je .end
    or al, al
    jz .end
    cmp al, '0'
    jb .bad
    cmp al, '9'
    ja .bad
    sub al, '0'
    xor ah, ah
    push ax
    mov ax, bx
    mov dx, 10
    mul dx
    mov bx, ax
    pop ax
    add bx, ax
    inc di
    inc cx
    jmp .loop
.end:
    jcxz .bad
    mov ax, bx
    clc
    ret
.bad:
    stc
    ret

; ---------------------------------------------------------------------------
; GF1 low-level setup

setup_gus_ports:
    mov ax, [gus_base]
    mov dx, ax
    add dx, 102h
    mov [gus_voice_port], dx
    inc dx
    mov [gus_command_port], dx
    inc dx
    mov [gus_data_low_port], dx
    inc dx
    mov [gus_data_high_port], dx
    mov dx, ax
    add dx, 006h
    mov [gus_status_port], dx
    add dx, 2
    mov [gus_timer_control_port], dx
    inc dx
    mov [gus_timer_data_port], dx
    mov dx, ax
    add dx, 107h
    mov [gus_dram_port], dx
    ret

gus_set_interface:
    pushf
    cli
    xor cx, cx
    mov bx, [gus_irq]
    mov cl, [irq_lut+bx]
    mov bx, [gus_midi_irq]
    mov al, [irq_lut+bx]
    shl al, 3
    or cl, al
    mov ax, [gus_irq]
    cmp ax, [gus_midi_irq]
    jne .irq_ready
    or cl, 40h
.irq_ready:
    mov [irq_latch], cl

    xor cx, cx
    mov bx, [gus_dma1]
    mov cl, [dma_lut+bx]
    mov bx, [gus_dma2]
    mov al, [dma_lut+bx]
    shl al, 3
    or cl, al
    mov ax, [gus_dma1]
    cmp ax, [gus_dma2]
    jne .dma_ready
    or cl, 40h
.dma_ready:
    mov [dma_latch], cl

    ; Unlock and reset the original GF1 digital ASIC interface.
    mov dx, [gus_base]
    add dx, 0Fh
    mov al, 05h
    out dx, al
    mov dx, [gus_base]
    mov al, 0Bh                  ; line/mic/output off, GF1 IRQ enabled
    out dx, al
    add dx, 0Bh
    xor al, al
    out dx, al
    mov dx, [gus_base]
    add dx, 0Fh
    xor al, al
    out dx, al

    ; Program the DRAM/ADC DMA and GF1/MIDI IRQ latches twice, as
    ; prescribed by the GF1 hardware interface sequence.
    mov dx, [gus_base]
    mov al, 0Bh
    out dx, al
    add dx, 0Bh
    mov al, [dma_latch]
    or al, 80h
    out dx, al
    mov dx, [gus_base]
    mov al, 4Bh
    out dx, al
    add dx, 0Bh
    mov al, [irq_latch]
    out dx, al
    mov dx, [gus_base]
    mov al, 0Bh
    out dx, al
    add dx, 0Bh
    mov al, [dma_latch]
    out dx, al
    mov dx, [gus_base]
    mov al, 4Bh
    out dx, al
    add dx, 0Bh
    mov al, [irq_latch]
    out dx, al
    mov dx, [gus_voice_port]
    xor al, al
    out dx, al
    mov dx, [gus_base]
    mov al, 08h                  ; line input, output and GF1 IRQ on; mic off
    out dx, al
    mov dx, [gus_voice_port]
    xor al, al
    out dx, al
    popf
    ret

gus_reset:
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 4Ch
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    call gf1_delay
    call gf1_delay
    mov dx, [gus_command_port]
    mov al, 4Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 01h
    out dx, al
    call gf1_delay
    call gf1_delay

    mov dx, [gus_base]
    add dx, 100h
    mov al, 03h
    out dx, al
    call gf1_delay
    xor al, al
    out dx, al

    mov dx, [gus_command_port]
    mov al, 41h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov dx, [gus_command_port]
    mov al, 49h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al

    mov dx, [gus_command_port]
    mov al, 0Eh
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 0CDh                  ; 14 active voices: (14-1) | C0
    out dx, al

    call gus_clear_pending
    xor si, si
.voice_loop:
    mov dx, [gus_voice_port]
    mov ax, si
    out dx, al
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    mov dx, [gus_command_port]
    mov al, 0Dh
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay

    mov dx, [gus_command_port]
    mov al, 01h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, 0400h
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    xor ax, ax
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 0Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 07h
    out dx, al
    inc si
    cmp si, 14
    jb .voice_loop

    call gus_clear_pending
    mov dx, [gus_command_port]
    mov al, 4Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 07h                  ; reset released, DAC and master IRQ enabled
    out dx, al
    popf
    ret

gus_clear_pending:
    push ax
    push dx
    mov dx, [gus_status_port]
    in al, dx
    mov dx, [gus_command_port]
    mov al, 41h
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx
    mov dx, [gus_command_port]
    mov al, 49h
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx
    mov dx, [gus_command_port]
    mov al, 8Fh
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx
    pop dx
    pop ax
    ret

gf1_delay:
    push ax
    push cx
    push dx
    mov dx, [gus_dram_port]
    mov cx, 7
.wait:
    in al, dx
    loop .wait
    pop dx
    pop cx
    pop ax
    ret

gus_probe:
    mov word [dram_addr_low], 0
    mov word [dram_addr_high], 0
    mov bl, 0AAh
    call gus_poke
    mov word [dram_addr_low], 1
    mov bl, 055h
    call gus_poke
    mov word [dram_addr_low], 0
    call gus_peek
    mov [probe_value0], al
    cmp al, 0AAh
    jne .fail
    mov word [dram_addr_low], 1
    call gus_peek
    mov [probe_value1], al
    cmp al, 055h
    jne .fail
    clc
    ret
.fail:
    stc
    ret

; Conservative 512 KiB DRAM probe, retained despite the lower 256 KiB layout.
gus_probe_512k:
    mov word [dram_addr_low],0
    mov word [dram_addr_high],0
    mov bl,0aah
    call gus_poke
    mov word [dram_addr_high],4
    mov bl,055h
    call gus_poke
    call gus_peek
    cmp al,055h
    jne .fail
    mov word [dram_addr_high],0
    call gus_peek
    cmp al,0aah
    jne .fail
    mov word [dram_addr_low],0ffffh
    mov word [dram_addr_high],7
    mov bl,066h
    call gus_poke
    call gus_peek
    cmp al,066h
    jne .fail
    clc
    ret
.fail:
    stc
    ret

gus_poke:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [dram_addr_low]
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov ax, [dram_addr_high]
    out dx, al
    mov dx, [gus_dram_port]
    mov al, bl
    out dx, al
    popf
    pop dx
    pop ax
    ret

gus_peek:
    push dx
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [dram_addr_low]
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov ax, [dram_addr_high]
    out dx, al
    mov dx, [gus_dram_port]
    in al, dx
    mov [peek_value], al
    popf
    pop dx
    mov al, [peek_value]
    ret

; DS:SI = bytes, CX = count.  dram_addr_* is advanced by count.
gus_upload:
    push ax
    push bx
    push cx
    push dx
    push si
    pushf
    cli
    mov dx, [cs:gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [cs:gus_data_high_port]
    mov ax, [cs:dram_addr_high]
    out dx, al
    mov bx, 256
.byte:
    mov dx, [cs:gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [cs:gus_data_low_port]
    mov ax, [cs:dram_addr_low]
    out dx, ax
    mov dx, [cs:gus_dram_port]
    lodsb
    out dx, al
    inc word [cs:dram_addr_low]
    jnz .next
    inc word [cs:dram_addr_high]
    mov dx, [cs:gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [cs:gus_data_high_port]
    mov ax, [cs:dram_addr_high]
    out dx, al
.next:
    ; The game invokes effects through an interrupt, with IF cleared.
    ; Service pending GF1 ticks between complete DRAM writes. The music
    ; tracker does not touch DRAM addressing, and SFX voice setup follows
    ; only after this routine has restored the caller's interrupt state.
    dec bx
    jnz .continue
    mov bx, 256
    cmp byte [cs:music_active],1
    jne .continue
    sti
    nop
    cli
.continue:
    loop .byte
    popf
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; Initial SFX bank upload

install_vectors:
    mov ax, 3521h
    int 21h
    mov [old_int21], bx
    mov [old_int21+2], es
    mov ax, 3565h
    int 21h
    mov [old_int65], bx
    mov [old_int65+2], es
    mov ax, 3566h
    int 21h
    mov [old_int66], bx
    mov [old_int66+2], es

    mov ax, [gus_irq]
    cmp ax, 7
    jbe .master_vector
    add ax, 68h
    jmp .vector_ready
.master_vector:
    add ax, 08h
.vector_ready:
    mov [irq_vector], al
    mov ah, 35h
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es

    in al, 21h
    mov [old_pic_master], al
    in al, 0A1h
    mov [old_pic_slave], al

    push ds
    push cs
    pop ds
    mov dx, int65_handler
    mov ax, 2565h
    int 21h
    mov dx, int66_handler
    mov ax, 2566h
    int 21h
    mov dx, gus_irq_handler
    mov ah, 25h
    mov al, [irq_vector]
    int 21h
    mov dx, int21_handler
    mov ax, 2521h
    int 21h
    pop ds

    pushf
    cli
    mov ax, [gus_irq]
    cmp ax, 7
    ja .unmask_slave
    mov cl, al
    mov bl, 1
    shl bl, cl
    not bl
    in al, 21h
    and al, bl
    out 21h, al
    jmp .unmask_done
.unmask_slave:
    sub al, 8
    mov cl, al
    mov bl, 1
    shl bl, cl
    not bl
    in al, 0A1h
    and al, bl
    out 0A1h, al
    in al, 21h
    and al, 0FBh
    out 21h, al
.unmask_done:
    popf
    mov byte [vectors_installed], 1
    ret

restore_vectors:
    cmp byte [vectors_installed], 1
    jne .done
    call gus_timer_stop

    pushf
    cli
    mov al, [old_pic_master]
    out 21h, al
    mov al, [old_pic_slave]
    out 0A1h, al
    popf

    mov dx, [old_irq]
    mov ax, [old_irq+2]
    mov ds, ax
    mov ah, 25h
    mov al, [cs:irq_vector]
    int 21h
    mov dx, [cs:old_int65]
    mov ax, [cs:old_int65+2]
    mov ds, ax
    mov ax, 2565h
    int 21h
    mov dx, [cs:old_int66]
    mov ax, [cs:old_int66+2]
    mov ds, ax
    mov ax, 2566h
    int 21h
    mov dx, [cs:old_int21]
    mov ax, [cs:old_int21+2]
    mov ds, ax
    mov ax, 2521h
    int 21h
    push cs
    pop ds
    mov byte [vectors_installed], 0
.done:
    ret

cleanup:
    mov byte [music_active], 0
    call gus_quiet
    call restore_vectors
    ; Return the SB16-to-GUS analog pass-through to its launcher-time state.
    mov dx, [gus_base]
    mov al, 08h
    out dx, al
    call write_diag
    ret

; Search the child allocation at DOS calls for the unpacked supported image.
; Once patched, this hook immediately chains without scanning again.
int21_handler:
    jmp far [cs:old_int21]

int66_handler:
    iret

%include "bridge.inc"

dos_read_exact:
    mov ah, 3Fh
    int 21h
    jc .fail
    cmp ax, cx
    jne .fail
    clc
    ret
.fail:
    stc
    ret

tracker_reset:
    mov byte [tick_index],0
    xor ax,ax
    mov di,channel_effect
    mov cx,(effect_state_end-channel_effect)
    rep stosb
    mov byte [tracker_tick_count], 1
    mov byte [tracker_speed], 6
    mov byte [tracker_order], 0
    mov word [tracker_row], 0
    mov byte [channel_sample+0], 0FFh
    mov byte [channel_sample+1], 0FFh
    mov byte [channel_sample+2], 0FFh
    mov byte [channel_sample+3], 0FFh
    xor ax, ax
    mov di, channel_period
    mov cx, 4
    rep stosw
    mov di, channel_volume
    mov cx, 4
    rep stosb
    mov di, channel_slide
    mov cx, 4
    rep stosb
    call mute_music_voices
    ret

; ---------------------------------------------------------------------------
; GF1 timer IRQ and four-channel tracker

gus_timer_start:
    cmp byte [timer_started], 1
    je .done
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 46h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 6                    ; (256-6) * 80 us = 20 ms
    out dx, al
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 04h
    out dx, al
    mov byte [timer_control_shadow], 04h
    mov dx, [gus_timer_control_port]
    mov al, 04h
    out dx, al
    mov dx, [gus_timer_data_port]
    mov al, 01h
    out dx, al
    mov byte [timer_started], 1
    popf
.done:
    ret

gus_timer_stop:
    cmp byte [timer_started], 1
    jne .done
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov byte [timer_control_shadow], 0
    mov dx, [gus_timer_control_port]
    mov al, 04h
    out dx, al
    mov dx, [gus_timer_data_port]
    xor al, al
    out dx, al
    mov byte [timer_started], 0
    popf
.done:
    ret

gus_irq_handler:
    pushf
    push ax
    push dx
    mov dx, [cs:gus_status_port]
    in al, dx
    test al, 04h
    jnz .ours
    pop dx
    pop ax
    popf
    jmp far [cs:old_irq]
.ours:
    push bx
    push cx
    push si
    push di
    push bp
    push ds
    push es
    push cs
    pop ds

    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [timer_control_shadow]
    and al, 0FBh
    out dx, al
    or al, 04h
    out dx, al

    inc word [total_ticks]
    cmp byte [music_active], 1
    jne .clear_voice_irq
    call tracker_tick
.clear_voice_irq:
    cmp byte [diag_mode],1
    jne .no_diag_tick
    mov ax,[total_ticks]
    test al,31
    jnz .no_diag_tick
    mov al,80h
    call diag_log_event
    cmp word [sfx_played],0
    je .no_diag_tick
    call diag_log_effect_voices
    call diag_log_music_positions
.no_diag_tick:
    mov dx, [gus_command_port]
    mov al, 8Fh
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx

    cmp word [gus_irq], 7
    jbe .master_eoi
    mov al, 20h
    out 0A0h, al
.master_eoi:
    mov al, 20h
    out 20h, al
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop cx
    pop bx
    pop dx
    pop ax
    popf
    iret

%include "tracker.inc"

trigger_music_channel:
    push ax
    push bx
    push cx
    push dx
    push si
    xor bx, bx
    mov bl, [channel_sample+di]
    cmp bl, 30
    ja .stop
    shl bx, 1
    mov ax, [sample_length+bx]
    or ax, ax
    jz .stop
    mov [voice_sample_length], ax
    mov ax, [sample_start_low+bx]
    mov [voice_begin_low], ax
    mov [voice_loop_low], ax
    mov ax, [sample_start_high+bx]
    mov [voice_begin_high], ax
    mov [voice_loop_high], ax

    mov ax, [sample_loop_length+bx]
    cmp ax, 2
    jbe .no_loop
    mov [voice_loop_length], ax
    mov ax, [sample_loop_start+bx]
    add [voice_loop_low], ax
    adc word [voice_loop_high], 0
    mov ax, [voice_loop_low]
    mov [voice_end_low], ax
    mov ax, [voice_loop_high]
    mov [voice_end_high], ax
    mov ax, [voice_loop_length]
    dec ax                          ; GF1 end addresses are inclusive
    add [voice_end_low], ax
    adc word [voice_end_high], 0
    mov byte [voice_mode], 08h
    jmp .address_ready
.no_loop:
    mov ax, [voice_begin_low]
    mov [voice_end_low], ax
    mov ax, [voice_begin_high]
    mov [voice_end_high], ax
    mov ax, [voice_sample_length]
    dec ax
    add [voice_end_low], ax
    adc word [voice_end_high], 0
    mov byte [voice_mode], 0
.address_ready:
    mov bx, di
    shl bx, 1
    mov ax, [channel_period+bx]
    or ax, ax
    jz .stop
    call period_to_frequency
    mov [voice_frequency], ax
    mov ax, di
    mov [voice_number], al
    mov bx, di
    mov al, [music_pan+bx]
    mov [voice_pan], al
    mov al, [channel_volume+di]
    call music_volume_word
    mov [voice_volume], ax
    call gf1_start_voice
    jmp .done
.stop:
    mov ax, di
    call gf1_stop_voice
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

update_music_frequency:
    push ax
    push bx
    mov bx, di
    shl bx, 1
    mov ax, [channel_period+bx]
    or ax, ax
    jz .done
    call period_to_frequency
    mov bx, ax
    mov ax, di
    call gf1_voice_frequency
.done:
    pop bx
    pop ax
    ret

update_music_volume:
    push ax
    push bx
    mov al, [channel_volume+di]
    call music_volume_word
    mov bx, ax
    mov ax, di
    call gf1_voice_volume
    pop bx
    pop ax
    ret

period_to_frequency:
    push bx
    push cx
    push dx
    mov bx, ax
    or bx, bx
    jz .zero
    mov ax, bx
    shr ax, 1
    add ax, 41179               ; round((3546895/period)*512/44100)
    xor dx, dx
    div bx
    shl ax, 1                  ; GF1 frequency bit 0 is unused
    jmp .done
.zero:
    xor ax, ax
.done:
    pop dx
    pop cx
    pop bx
    ret

music_volume_word:
    push bx
    push cx
    xor ah, ah
    mov bl, [music_master]
    mul bl
    mov cl, 6
    shr ax, cl
    cmp ax, 64
    jbe .index
    mov ax, 64
.index:
    shl ax, 1
    mov bx, ax
    mov ax, [volume_table+bx]
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
; GF1 voice operations

gf1_start_voice:
    pushf
    cli
    push ax
    push bx
    push cx
    push dx
    mov dx, [gus_voice_port]
    mov al, [voice_number]
    out dx, al

    mov dx, [gus_command_port]
    mov al, 0Dh
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al

    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    xor ax, ax
    out dx, ax

    mov byte [voice_addr_register], 0Ah
    mov ax, [voice_begin_low]
    mov [voice_addr_low], ax
    mov ax, [voice_begin_high]
    mov [voice_addr_high], ax
    call gf1_write_voice_address
    mov byte [voice_addr_register], 02h
    mov ax, [voice_loop_low]
    mov [voice_addr_low], ax
    mov ax, [voice_loop_high]
    mov [voice_addr_high], ax
    call gf1_write_voice_address
    mov byte [voice_addr_register], 04h
    mov ax, [voice_end_low]
    mov [voice_addr_low], ax
    mov ax, [voice_end_high]
    mov [voice_addr_high], ax
    call gf1_write_voice_address

    mov dx, [gus_command_port]
    mov al, 01h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [voice_frequency]
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 0Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [voice_pan]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [voice_volume]
    out dx, ax

    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [voice_mode]
    and al, 0FCh
    out dx, al
    call gf1_delay
    out dx, al
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret

gf1_write_voice_address:
    push ax
    push bx
    push cx
    push dx
    mov ax, [voice_addr_low]
    mov cx, [voice_addr_high]
    mov bx, cx
    shr ax, 7
    shr cx, 7
    shl bx, 9
    or ax, bx
    mov bx, ax
    mov dx, [gus_command_port]
    mov al, [voice_addr_register]
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, bx
    out dx, ax
    mov dx, [gus_command_port]
    mov al, [voice_addr_register]
    inc al
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [voice_addr_low]
    shl ax, 9
    out dx, ax
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; AL = voice, BX = frequency word
gf1_voice_frequency:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_voice_port]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 01h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, bx
    out dx, ax
    popf
    pop dx
    pop ax
    ret

; AL = voice, BX = GF1 current-volume register word
gf1_voice_volume:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_voice_port]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, bx
    out dx, ax
    popf
    pop dx
    pop ax
    ret

; AL = voice
gf1_stop_voice:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_voice_port]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    xor ax, ax
    out dx, ax
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al
    popf
    pop dx
    pop ax
    ret

mute_music_voices:
    xor si, si
.loop:
    mov ax, si
    call gf1_stop_voice
    inc si
    cmp si, 4
    jb .loop
    ret

restore_music_voices:
    xor di,di
.loop:
    cmp byte [channel_sample+di],30
    ja .next
    mov bx,di
    shl bx,1
    cmp word [channel_period+bx],0
    je .next
    call trigger_music_channel
.next:
    inc di
    cmp di,4
    jb .loop
    ret

gus_quiet:
    pushf
    cli
    push ax
    push si
    cmp word [gus_base], 0
    je .done
    xor si, si
.voice:
    mov ax, si
    call gf1_stop_voice
    inc si
    cmp si, 14
    jb .voice
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
.done:
    pop si
    pop ax
    popf
    ret

; ---------------------------------------------------------------------------
; Polyphonic SFX

; ---------------------------------------------------------------------------
; Data


msg_preload db 'Starting GF1 bridge...',13,10,'$'
msg_banner       db 13,10,'ACGUS 1.0 - native Gravis UltraSound GF1 audio',13,10,'$'
msg_bad_args     db 'Usage: ACGUS [/T] [/D] [/P-100..100]  (or -vp-100..100)',13,10,'$'
msg_pan          db 'GF1 music stereo width: $'
msg_pan_end      db '%',13,10,'$'
msg_bad_config   db 'ERROR: ULTRASND must contain a supported base,DMA,DMA,IRQ,IRQ setting.',13,10,'$'
msg_no_memory    db 'ERROR: DOS could not resize the launcher memory block.',13,10,'$'
msg_no_gus       db 'ERROR: no writable GF1 DRAM found at the ULTRASND base port.',13,10,'$'
msg_gus_memory    db 'ERROR: at least 512 KiB of GF1 DRAM is required.',13,10,'$'
msg_probe_detail  db 'Probe base/readback: $'
msg_probe_values  db ' / $'
msg_exec_failed  db 'ERROR: DOS could not execute CARNAGE.EXE; DOS code 0x','$'
msg_patch_ok     db 'ACGUS: audio hooks used; vectors restored.',13,10,'$'
msg_patch_missing db 'WARNING: no audio hook was used.',13,10,'$'
msg_song_error   db 'WARNING: at least one music module could not be loaded or validated.',13,10,'$'
msg_audio_counts db 'GF1 events serviced: songs=$'
msg_audio_sfx    db ' sfx=$'
%ifdef DUMP_CODE
msg_patch_trigger db 'Patch trigger DOS AX=$'
msg_patch_trigger_ip db ' return IP=$'
%endif
msg_test_start   db 'Self-test: checking GF1 timer for five seconds...',13,10,'$'
msg_test_ok      db 'Self-test passed: GF1 timer interrupts were received.',13,10,'$'
msg_test_fail    db 'Self-test failed: no GF1 timer interrupts were received.',13,10,'$'
msg_crlf         db 13,10,'$'

ultrasnd_key     db 'ULTRASND='
game_filename    db 'CARNAGE.EXE',0
exec_tail        db 0,13      ; consume our switches; child receives no arguments
%ifdef DUMP_CODE
code_dump_filename db 'CODEDUMP.BIN',0
%endif
sfx_filename     db 'BB2BANK.RAW',0
name_almost db 'BB2M0.MOD',0
name_every db 'BB2M1.MOD',0
name_bartende db 'BB2M2.MOD',0
name_petergun db 'BB2M3.MOD',0
name_shoot db 'BB2M4.MOD',0
song_filename_table:
    dw name_almost,name_every,name_bartende,name_petergun,name_shoot

irq_lut          db 0,0,1,3,0,2,0,4,0,0,0,5,6,0,0,7
dma_lut          db 0,1,0,2,0,3,4,5
music_pan        db 3,12,12,3     ; populated by set_music_pan at startup

patch_signature:
    db 0FAh,0FCh,0BEh,080h,000h,0ACh,098h,08Bh,0C8h,0E3h,036h
patch_signature_len equ $-patch_signature


; Independently derived linear 0..64 -> GF1 exponent/mantissa values.
volume_table:
    dw 00000h,09FF0h,0AFF0h,0B800h,0BFF0h,0C400h,0C800h,0CC00h
    dw 0CFF0h,0D200h,0D400h,0D600h,0D800h,0DA00h,0DC00h,0DE00h
    dw 0DFF0h,0E100h,0E200h,0E300h,0E400h,0E500h,0E600h,0E700h
    dw 0E800h,0E900h,0EA00h,0EB00h,0EC00h,0ED00h,0EE00h,0EF00h
    dw 0EFF0h,0F080h,0F100h,0F180h,0F200h,0F280h,0F300h,0F380h
    dw 0F400h,0F480h,0F500h,0F580h,0F600h,0F680h,0F700h,0F780h
    dw 0F800h,0F880h,0F900h,0F980h,0FA00h,0FA80h,0FB00h,0FB80h
    dw 0FC00h,0FC80h,0FD00h,0FD80h,0FE00h,0FE80h,0FF00h,0FF80h
    dw 0FFF0h

bank_remaining dd 0
music_addresses dd 65536,88910,116860,148598,192644
expected_orders db 19,23,17,23,25
psp_segment       dw 0
gus_base          dw 0
gus_dma1          dw 0
gus_dma2          dw 0
gus_irq           dw 0
gus_midi_irq      dw 0
gus_voice_port    dw 0
gus_command_port  dw 0
gus_data_low_port dw 0
gus_data_high_port dw 0
gus_status_port   dw 0
gus_timer_control_port dw 0
gus_timer_data_port dw 0
gus_dram_port     dw 0
irq_latch         db 0
dma_latch         db 0
old_pic_master    db 0
old_pic_slave     db 0
pan_percent       db 60
pan_reverse       db 0
pan_seen          db 0
irq_vector        db 0
vectors_installed db 0
timer_started     db 0
timer_control_shadow db 0
test_mode         db 0
diag_mode         db 0
patch_installed   db 0
game_line_muted   db 0
patch_segment     dw 0
patch_scan_start  dw 0
patch_scan_limit  dw 0
exec_failed       db 0
exec_error        dw 0
child_exit_code   db 0
bios_tick_start   dw 0
total_ticks       dw 0
songs_loaded      dw 0
sfx_played        dw 0
song_error        db 0
music_active      db 0
current_song      db 0FFh
requested_song    db 0
requested_sfx     db 0
sfx_round_robin   db 0
music_master      db 52
diag_name         db 'ACGUS.LOG',0
diag_header       db 'AGD5'
diag_count        dw 0
diag_records      times 256*16 db 0
diag_records_end:

old_int21         dd 0
old_int65         dd 0
old_int66         dd 0
old_irq           dd 0
exec_params       times 14 db 0

file_handle       dw 0FFFFh
bytes_remaining   dw 0
dram_addr_low     dw 0
dram_addr_high    dw 0
peek_value        db 0
probe_value0      db 0
probe_value1      db 0

mod_song_length   db 0
mod_num_patterns  db 0
mod_pattern_bytes dw 0
tracker_tick_count db 1
tracker_speed     db 6
tracker_order     db 0
tracker_row       dw 0
channel_sample    times 4 db 0FFh
channel_period    times 4 dw 0
channel_volume    times 4 db 0
channel_slide     times 4 db 0

sample_start_low  times 31 dw 0
sample_start_high times 31 dw 0
sample_length     times 31 dw 0
sample_loop_start times 31 dw 0
sample_loop_length times 31 dw 0
sample_volume     times 31 db 0

temp_sample       db 0
temp_effect       db 0
temp_param        db 0
temp_period       dw 0
temp_trigger      db 0
temp_freq_changed db 0
temp_volume_changed db 0

voice_number      db 0
voice_mode        db 0
voice_pan         db 7
voice_frequency   dw 0
voice_volume      dw 0
voice_begin_low   dw 0
voice_begin_high  dw 0
voice_loop_low    dw 0
voice_loop_high   dw 0
voice_end_low     dw 0
voice_end_high    dw 0
voice_sample_length dw 0
voice_loop_length dw 0
voice_addr_register db 0
voice_addr_low    dw 0
voice_addr_high   dw 0

io_buffer         times IO_BUFFER_BYTES db 0
%ifdef DUMP_CODE
code_dumped       db 0
patch_trigger_ax  dw 0
patch_trigger_ip  dw 0
code_dump         times 1000h db 0
%endif
%include "bridge_data.inc"

module_buffer     times MOD_HEADER_BYTES+MOD_PATTERN_LIMIT db 0
stack_space       times 1024 db 0
stack_top:
resident_end:

; Flat-binary labels are relocatable to ORG 100h; subtracting the section base
; makes the file length scalar, then add the PSP prefix retained in memory.
RESIDENT_PARAS equ ((resident_end - $$ + 100h + 15) / 16)
