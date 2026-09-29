bridge_op db 0
music_one_shot db 0
caller_ds dw 0
request_module dw 0
sample_segments times 31 dw 0
sfx_next_address dd 40000h
music_dram_end dd 0
sfx_cache_count dw 0
sfx_cache_segment times 64 dw 0
sfx_cache_length times 64 dw 0
sfx_cache_address times 64 dd 0
request_sfx_segment dw 0
request_sfx_pitch dw 0
request_sfx_volume dw 0
request_sfx_channel dw 0
bridge_periods dw 856,808,762,720,678,640,604,570,538,508,480,453
               dw 428,404,381,360,339,320,302,285,269,254,240,226
               dw 214,202,190,180,170,160,151,143,135,127,120,113

%ifdef TRACE
trace_name db "TRACE.BIN",0
trace_handle dw 0
trace_record times 24 db 0
%endif
