; Bridge ABI: AX=AC00h+operation; BP is game Pascal frame, DS game data.
; Original game parameter words are addressed through SS:BP.
int65_handler:
    cmp ah,0ACh
    je .ours
    jmp far [cs:old_int65]
.ours:
    mov [cs:bridge_op],al
    mov [cs:caller_ds],ds
    pusha
    push ds
    push es
    push fs
    push gs
    push cs
    pop ds
    push cs
    pop es
    cld
    mov byte [patch_installed],1
    cmp al,0
    je .initialize
    cmp al,1
    je .song
    cmp al,2
    je .sfx
    cmp al,3
    je .shutdown
    cmp al,4
    je .pause
    cmp al,5
    je .resume
    jmp .done
.initialize:
    ; BX is the sound configuration byte's offset in caller DS.
    mov ax,[caller_ds]
    mov es,ax
    mov byte [es:bx],2
    mov word [sfx_cache_count],0
    mov dword [sfx_next_address],40000h
    mov dword [music_dram_end],0
    mov word [request_module],0
    mov byte [music_active],0
    call gus_timer_stop
    call gus_quiet
    call gus_timer_start
    jmp .done
.song:
    mov ax,[ss:bp+6]
    mov [request_module],ax
    mov dx,[caller_ds]
    mov es,dx
    mov [es:bx],ax
    sti
    call load_memory_module
    jmp .done
.sfx:
    mov ax,[ss:bp+6]
    mov [request_sfx_segment],ax
    mov ax,[ss:bp+8]
    mov [request_sfx_pitch],ax
    mov ax,[ss:bp+10]
    mov [request_sfx_volume],ax
    xor ax,ax
    mov al,[ss:bp+12]
    mov [request_sfx_channel],ax
    cmp byte [diag_mode],1
    jne .sfx_no_before
    mov al,81h
    call diag_log_hardware
    call diag_log_music_positions
.sfx_no_before:
    call play_memory_sfx
    cmp byte [diag_mode],1
    jne .done
    mov al,82h
    call diag_log_hardware
    call diag_log_music_positions
    jmp .done
.shutdown:
    mov byte [music_active],0
    call gus_timer_stop
    call gus_quiet
    jmp .done
.pause:
    mov ax,[caller_ds]
    mov es,ax
    mov byte [es:bx],1
    mov byte [music_active],0
    call mute_music_voices
    jmp .done
.resume:
    mov ax,[caller_ds]
    mov es,ax
    mov byte [es:bx],0
    cmp word [request_module],0
    je .done
    mov byte [music_active],1
    call gus_timer_start
    call restore_music_voices
.done:
    cmp byte [diag_mode],1
    jne .no_diag_event
    mov al,[bridge_op]
    call diag_log_event
.no_diag_event:
%ifdef TRACE
    mov ax,[total_ticks]
    mov [trace_record],ax
    mov ax,[songs_loaded]
    mov [trace_record+2],ax
    mov ax,[sfx_played]
    mov [trace_record+4],ax
    mov al,[bridge_op]
    mov [trace_record+6],al
    mov al,[song_error]
    mov [trace_record+7],al
    mov ax,[request_module]
    mov [trace_record+8],ax
    mov al,[mod_song_length]
    mov [trace_record+10],al
    mov ax,[sample_length]
    mov [trace_record+11],ax
    mov ax,[sample_length+2]
    mov [trace_record+13],ax
    mov al,[module_buffer+952]
    mov [trace_record+15],al
    mov al,[music_active]
    mov [trace_record+16],al
    mov al,[timer_started]
    mov [trace_record+17],al
    mov al,[tracker_order]
    mov [trace_record+18],al
    mov ax,[tracker_row]
    mov [trace_record+19],ax
    mov al,[sfx_round_robin]
    mov [trace_record+21],al
    mov ax,[request_sfx_segment]
    mov [trace_record+22],ax
    mov bx,[trace_handle]
    mov dx,trace_record
    mov cx,24
    mov ah,40h
    int 21h
%endif
    cli
    pop gs
    pop fs
    pop es
    pop ds
    popa
    iret

load_memory_module:
    mov byte [music_active],0
    call mute_music_voices
    mov si,4
.stop_old_effects:
    mov ax,si
    call gf1_stop_voice
    inc si
    cmp si,14
    jb .stop_old_effects
    mov ax,[request_module]
    test ax,ax
    jz .empty
    cmp ax,100h
    jb .invalid
    mov es,ax
    mov al,[es:119h]
    test al,al
    jz .invalid
    cmp al,128
    ja .invalid
    mov [mod_song_length],al
    mov [module_buffer+950],al
    xor bx,bx
    xor dx,dx
.orders:
    mov al,[es:11ah+bx]
    mov [module_buffer+952+bx],al
    cmp bl,[mod_song_length]
    jae .ignore_max
    cmp al,dl
    jbe .ignore_max
    mov dl,al
.ignore_max:
    inc bx
    cmp bx,128
    jb .orders
    inc dx
    cmp dx,32
    ja .invalid
    mov [mod_num_patterns],dl
    shl dx,10
    mov [mod_pattern_bytes],dx
    xor bx,bx
.headers:
    mov ax,[es:bx+2]
    mov [sample_segments+bx],ax
    mov ax,[es:bx+40h]
    mov [sample_length+bx],ax
    mov ax,[es:bx+7eh]
    mov [sample_loop_start+bx],ax
    mov ax,[es:bx+0bch]
    mov [sample_loop_length+bx],ax
    mov si,bx
    shr si,1
    mov al,[es:si+0fah]
    cmp al,64
    jbe .vol_ok
    mov al,64
.vol_ok:
    mov [sample_volume+si],al
    add bx,2
    cmp bx,62
    jb .headers
    ; The short APOGEE logo cue is a fanfare, not a background loop.
    ; Identify it from the game's already decoded module metadata.
    mov byte [music_one_shot],0
    cmp byte [mod_song_length],2
    jne .ordinary_song
    cmp word [sample_length],5290
    jne .ordinary_song
    cmp word [sample_length+2],3144
    jne .ordinary_song
    cmp byte [module_buffer+952],0
    jne .ordinary_song
    cmp byte [module_buffer+953],1
    jne .ordinary_song
    mov byte [music_one_shot],1
.ordinary_song:
    mov ax,[es:0]
    mov es,ax
    xor si,si
    mov di,module_buffer+1084
    mov cx,[mod_pattern_bytes]
    shr cx,2
.patterns:
    xor dx,dx
    mov al,[es:si]
    cmp al,7fh
    je .no_note
    add al,12
    cmp al,36
    jae .no_note
    xor ah,ah
    mov bx,ax
    shl bx,1
    mov dx,[bridge_periods+bx]
.no_note:
    mov al,[es:si+1]
    and al,0f0h
    or al,dh
    mov [di],al
    mov [di+1],dl
    mov al,[es:si+1]
    shl al,4
    or al,[es:si+2]
    mov [di+2],al
    mov al,[es:si+3]
    mov [di+3],al
    add si,4
    add di,4
    loop .patterns
    mov word [dram_addr_low],0
    mov word [dram_addr_high],0
    xor di,di
.samples:
    mov ax,[dram_addr_low]
    mov [sample_start_low+di],ax
    mov ax,[dram_addr_high]
    mov [sample_start_high+di],ax
    mov cx,[sample_length+di]
    jcxz .next_sample
    mov ax,[sample_segments+di]
    push ds
    mov ds,ax
    xor si,si
    call gus_upload
    pop ds
.next_sample:
    add di,2
    cmp di,62
    jb .samples
    ; Each module can have a different expanded sample footprint. Keep the
    ; effect cache above that footprint when it reaches our default bank.
    movzx eax,word [dram_addr_high]
    shl eax,16
    mov ax,[dram_addr_low]
    mov [music_dram_end],eax
    add eax,0FFFh
    and eax,0FFFFF000h
    cmp eax,40000h
    ja .effect_above_music
    mov eax,40000h
.effect_above_music:
    mov [sfx_next_address],eax
    mov word [sfx_cache_count],0
    cmp byte [diag_mode],1
    jne .no_map_log
    call diag_log_memory_map
.no_map_log:
    push cs
    pop es
    call tracker_reset
    inc word [songs_loaded]
    mov byte [music_active],1
    call gus_timer_start
    ret
.invalid:
    mov byte [song_error],2
.empty:
    ret

play_memory_sfx:
    mov ax,[request_sfx_segment]
    cmp ax,100h
    jb .done
    dec ax
    mov es,ax
    mov cx,[es:0eh]
    test cx,cx
    jz .done
    xor bx,bx
.find:
    cmp bx,[sfx_cache_count]
    jae .new
    mov si,bx
    shl si,1
    mov ax,[request_sfx_segment]
    cmp ax,[sfx_cache_segment+si]
    jne .not_this
    cmp cx,[sfx_cache_length+si]
    je .cached
.not_this:
    inc bx
    jmp .find
.new:
    cmp bx,64
    jae .done
    mov eax,[sfx_next_address]
    movzx edx,cx
    add edx,eax
    cmp edx,80000h
    ja .done
    mov [sfx_next_address],edx
    mov si,bx
    shl si,2
    mov [sfx_cache_address+si],eax
    mov [dram_addr_low],ax
    shr eax,16
    mov [dram_addr_high],ax
    mov si,bx
    shl si,1
    mov ax,[request_sfx_segment]
    mov [sfx_cache_segment+si],ax
    mov [sfx_cache_length+si],cx
    inc word [sfx_cache_count]
    push ds
    mov ds,ax
    xor si,si
    call gus_upload
    pop ds
    cmp byte [diag_mode],1
    jne .cached
    call diag_log_sample
.cached:
    mov si,bx
    shl si,1
    mov ax,[sfx_cache_length+si]
    mov [voice_sample_length],ax
    shl si,1
    mov eax,[sfx_cache_address+si]
    mov [voice_begin_low],ax
    mov [voice_loop_low],ax
    mov [voice_end_low],ax
    shr eax,16
    mov [voice_begin_high],ax
    mov [voice_loop_high],ax
    mov [voice_end_high],ax
    mov ax,[voice_sample_length]
    dec ax
    add [voice_end_low],ax
    adc word [voice_end_high],0
    mov al,[request_sfx_pitch]
    add al,12
    cmp al,36
    jae .done
    xor ah,ah
    mov bx,ax
    shl bx,1
    mov ax,[bridge_periods+bx]
    call period_to_frequency
    mov [voice_frequency],ax
    mov byte [voice_mode],0
    mov ax,[request_sfx_channel]
    cmp ax,4
    jae .done
    mov [sfx_round_robin],al
    add al,4
    mov [voice_number],al
    mov byte [voice_pan],7
    mov ax,[request_sfx_volume]
    and ax,0ffh
    cmp ax,64
    jbe .volume_ok
    mov ax,64
.volume_ok:
    mov bx,ax
    shl bx,1
    mov ax,[volume_table+bx]
    mov [voice_volume],ax
    call gf1_start_voice
    inc word [sfx_played]
.done:
    ret
