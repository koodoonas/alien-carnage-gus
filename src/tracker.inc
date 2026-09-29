; Four-channel MOD sequencing. Only register updates run at 50Hz; GF1 mixes.
tracker_tick:
    cmp byte [tick_index],0
    jne .effects
    mov byte [jump_order],255
    mov byte [break_row],255
    xor bx,bx
    mov bl,[tracker_order]
    mov al,[module_buffer+952+bx]
    xor ah,ah
    shl ax,10
    mov si,module_buffer+MOD_HEADER_BYTES
    add si,ax
    mov ax,[tracker_row]
    shl ax,4
    add si,ax
    xor di,di
.row_channel:
    call tracker_process_cell
    add si,4
    inc di
    cmp di,4
    jb .row_channel
    jmp .clock
.effects:
    xor di,di
.effect_channel:
    call tracker_effect
    inc di
    cmp di,4
    jb .effect_channel
.clock:
    inc byte [tick_index]
    mov al,[tick_index]
    cmp al,[tracker_speed]
    jb .done
    mov byte [tick_index],0
    inc word [tracker_row]
    cmp byte [jump_order],255
    je .break
    mov al,[jump_order]
    mov [tracker_order],al
    mov word [tracker_row],0
.break:
    cmp byte [break_row],255
    je .normal
    xor ax,ax
    mov al,[break_row]
    mov [tracker_row],ax
    cmp byte [jump_order],255
    jne .wrap
    inc byte [tracker_order]
    jmp .wrap
.normal:
    cmp word [tracker_row],64
    jb .wrap
    mov word [tracker_row],0
    inc byte [tracker_order]
.wrap:
    mov al,[tracker_order]
    cmp al,[mod_song_length]
    jb .done
    cmp byte [music_one_shot],1
    jne .repeat_song
    mov byte [music_active],0
    call mute_music_voices
    jmp .done
.repeat_song:
    mov byte [tracker_order],0
.done:
    ret

tracker_process_cell:
    pusha
    mov bx,di
    shl bx,1
    mov al,[si+2]
    and al,15
    mov [channel_effect+di],al
    mov al,[si+3]
    mov [channel_param+di],al
    mov ah,[si]
    and ah,15
    mov al,[si+1]
    mov [temp_period],ax
    mov al,[si]
    and al,0f0h
    mov ah,[si+2]
    shr ah,4
    or al,ah
    jz .no_sample
    dec al
    cmp al,30
    ja .no_sample
    mov [channel_sample+di],al
    push bx
    xor bx,bx
    mov bl,al
    mov al,[sample_volume+bx]
    mov [channel_volume+di],al
    pop bx
.no_sample:
    mov ax,[temp_period]
    or ax,ax
    jz .setup_effect
    cmp byte [channel_effect+di],3
    je .target
    mov [channel_period+bx],ax
    mov byte [vibrato_phase+di],0
    call trigger_music_channel
    jmp .setup_effect
.target:
    mov [porta_target+bx],ax
.setup_effect:
    mov al,[channel_effect+di]
    mov ah,[channel_param+di]
    cmp al,3
    jne .vibrato
    or ah,ah
    jz .volume
    mov [porta_speed+di],ah
.vibrato:
    cmp al,4
    jne .jump
    mov dl,ah
    and dl,15
    jz .vib_speed
    mov [vibrato_depth+di],dl
.vib_speed:
    shr ah,4
    jz .volume
    mov [vibrato_speed+di],ah
    jmp .volume
.jump:
    cmp al,11
    jne .setvolume
    mov [jump_order],ah
    jmp .volume
.setvolume:
    cmp al,12
    jne .break
    cmp ah,64
    jbe .vol_ok
    mov ah,64
.vol_ok:
    mov [channel_volume+di],ah
    jmp .volume
.break:
    cmp al,13
    jne .speed
    mov al,ah
    and al,15
    shr ah,4
    mov dl,ah
    shl ah,1
    shl dl,3
    add al,ah
    add al,dl
    cmp al,63
    jbe .break_ok
    xor al,al
.break_ok:
    mov [break_row],al
    jmp .volume
.speed:
    cmp al,15
    jne .volume
    or ah,ah
    jz .volume
    cmp ah,31
    ja .volume ; installer rejects tempo changes in unsupported assets
    mov [tracker_speed],ah
.volume:
    call update_music_volume
    ; Remove modulation from previous row at tick zero.
    call update_music_frequency
    popa
    ret

tracker_effect:
    pusha
    mov bx,di
    shl bx,1
    mov al,[channel_effect+di]
    xor cx,cx
    mov cl,[channel_param+di]
    cmp al,0
    je .arp
    cmp al,1
    je .up
    cmp al,2
    je .down
    cmp al,3
    je .porta
    cmp al,4
    je .vibrato
    cmp al,10
    je .volslide
    jmp .done
.up:
    mov ax,[channel_period+bx]
    sub ax,cx
    cmp ax,113
    jae .store
    mov ax,113
    jmp .store
.down:
    mov ax,[channel_period+bx]
    add ax,cx
    cmp ax,856
    jbe .store
    mov ax,856
.store:
    mov [channel_period+bx],ax
    call update_music_frequency
    jmp .done
.porta:
    xor cx,cx
    mov cl,[porta_speed+di]
    mov ax,[channel_period+bx]
    mov dx,[porta_target+bx]
    or dx,dx
    jz .done
    cmp ax,dx
    je .done
    jb .porta_down
    sub ax,cx
    cmp ax,dx
    jae .store
    mov ax,dx
    jmp .store
.porta_down:
    add ax,cx
    cmp ax,dx
    jbe .store
    mov ax,dx
    jmp .store
.vibrato:
    push bx
    xor bx,bx
    mov bl,[vibrato_phase+di]
    and bl,31
    mov al,[sine_table+bx]
    mul byte [vibrato_depth+di]
    shr ax,7
    test byte [vibrato_phase+di],32
    jz .positive
    neg ax
.positive:
    pop bx
    add ax,[channel_period+bx]
    call period_to_frequency
    mov bx,ax
    mov ax,di
    call gf1_voice_frequency
    mov al,[vibrato_speed+di]
    add [vibrato_phase+di],al
    jmp .done
.arp:
    or cx,cx
    jz .done
    mov ax,[channel_period+bx]
    push ax
    xor ax,ax
    mov al,[tick_index]
    mov dl,3
    div dl
    cmp ah,1
    je .arp_hi
    cmp ah,2
    je .arp_lo
    xor cx,cx
    jmp .arp_ratio
.arp_hi:
    shr cl,4
.arp_lo:
    and cx,15
.arp_ratio:
    mov bx,cx
    shl bx,1
    pop ax
    mul word [arp_ratio+bx]
    shrd ax,dx,12
    call period_to_frequency
    mov bx,ax
    mov ax,di
    call gf1_voice_frequency
    jmp .done
.volslide:
    mov al,cl
    shr al,4
    jnz .vol_up
    and cl,15
    mov al,[channel_volume+di]
    sub al,cl
    jnc .vol_store
    xor al,al
    jmp .vol_store
.vol_up:
    add al,[channel_volume+di]
    cmp al,64
    jbe .vol_store
    mov al,64
.vol_store:
    mov [channel_volume+di],al
    call update_music_volume
.done:
    popa
    ret

tick_index db 0
jump_order db 255
break_row db 255
channel_effect times 4 db 0
channel_param times 4 db 0
porta_target times 4 dw 0
porta_speed times 4 db 0
vibrato_phase times 4 db 0
vibrato_speed times 4 db 0
vibrato_depth times 4 db 0
effect_state_end:
sine_table db 0,24,49,74,97,120,141,161,180,197,212,224,235,244,250,253
           db 255,253,250,244,235,224,212,197,180,161,141,120,97,74,49,24
arp_ratio dw 4096,3866,3649,3444,3251,3069,2896,2734,2580,2435,2299,2170,2048,1933,1825,1722
