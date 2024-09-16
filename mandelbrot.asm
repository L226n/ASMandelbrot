%include	"define.asm"
section	.data
	window_size:
		window_height	dw	0
		window_width	dw	0
		double_row	dq	0
		guard	dd	0
	termios:
		c_iflag	dd	0
		c_oflag	dd	0
		c_cflag	dd	0
		c_lflag	dd	0
		c_line	db	0
		c_cc	db	0
	handler_int:
		dq	f_int
		dd	0x04000000
		dq	0
	escape_home:
		db	27, "[0m", 10, 10, 10, 10
	escape_data:	
		db	27, "[48;5;000m"
		db	27, "[38;5;000m"
		dd	"▄"
	colorbuf	db	"255"
	screen_size	dq	0
	framebuf	dq	0
	zoom	dd	0.5
	point1	dd	0.1
	align	16
	top_left	dq	-3.0, -1.0
	current_pixel	dq	0, 0
	pixel_increment	dq	0.0
	align	16
	buf1	dq	0, 0, 0, 0
	color_seg	dd	23.0
section	.text
	global	_start
_start:
	mov	rax, 16
	mov	rdi, 1
	mov	rsi, 21505
	mov	rdx, termios
	syscall
	and	dword[c_lflag], ~(1 << 1)
	and	dword[c_lflag], ~(1 << 3)
	mov	rax, 16
	mov	rdi, 1
	mov	rsi, 21506
	mov	rdx, termios
	syscall
	mov	rax, 13
	mov	rdi, 2
	mov	rsi, handler_int
	mov	rdx, 0
	mov	r10, 8
	syscall
	mov	rax, 13
	mov	rdi, 11
	mov	rsi, handler_int
	syscall
	mov	rax, 16
	mov	rdi, 1
	mov	rsi, 21523
	mov	rdx, window_size
	syscall

	movzx	rax, word[window_height]
	movzx	rbx, word[window_width]
	imul	rbx, UNIT_SIZE
	mov	qword[double_row], rbx
	mul	rbx
	add	rax, TOP_SIZE
	mov	qword[screen_size], rax
	shl	word[window_height], 1

	mov	rax, 9
	mov	rdi, 0
	mov	rsi, qword[screen_size]
	mov	rdx, 3
	mov	r10, 2 | 32
	mov	r8, -1
	mov	r9, 0
	syscall
	mov	qword[framebuf], rax
	
	call	f_init_screen
.renderloop:
	call	f_render_mandelbrot
	mov	rax, 1
	mov	rdi, 1
	mov	rsi, qword[framebuf]
	mov	rdx, qword[screen_size]
	syscall
	mov	rax, 0
	mov	rdi, 0
	mov	rsi, buf1
	mov	rdx, 4
	syscall
	cmp	byte[buf1], "+"
	jnz	.cont_a
	fld	dword[zoom]
	fld1
	fdiv	st1
	fst	dword[buf1]
	fld	dword[zoom]
	fld	dword[point1]
	fmul	st1
	fadd	st1
	fst	dword[zoom]
	%macro	calc_readjust	0
		fld1
		fdiv	st1
		fld	dword[buf1]
		fsubr	st1
		fst	dword[buf1]
		emms
		fld	dword[buf1]
		fld	qword[top_left]
		fsub	st1
		fst	qword[top_left]
		fild	word[window_height]
		fdivr	st2
		fld1
		fadd	st0
		fadd	st0
		fdivr	st1
		fild	word[window_width]
		fmul	st1
		fld	qword[top_left+8]
		fsub	st1
		fst	qword[top_left+8]
		emms
	%endmacro
	calc_readjust
	jmp	.renderloop
.cont_a:
	cmp	byte[buf1], "-"
	jnz	.cont_b
	fld	dword[zoom]
	fld1
	fdiv	st1
	fst	dword[buf1]
	fld	dword[zoom]
	fld	dword[point1]
	fmul	st1
	fsubr	st1
	fst	dword[zoom]
	calc_readjust
	jmp	.renderloop
.cont_b:
	cmp	byte[buf1], 27
	jnz	.cont_c
	fld	dword[zoom]
	fld1
	fdiv	st1
	fld	dword[point1]
	fmul	st1
	cmp	word[buf1+1], "[D"
	jz	.pan_left
	cmp	word[buf1+1], "[C"
	jz	.pan_right
	cmp	word[buf1+1], "[A"
	jz	.pan_up
	cmp	word[buf1+1], "[B"
	jz	.pan_down
.cont_c:
	jmp	.renderloop
	jmp	f_int
.pan_left:
	fld	qword[top_left]
	fsub	st1
	fst	qword[top_left]
	emms
	jmp	.renderloop
.pan_right:
	fld	qword[top_left]
	fadd	st1
	fst	qword[top_left]
	emms
	jmp	.renderloop
.pan_up:
	fld	qword[top_left+8]
	fsub	st1
	fst	qword[top_left+8]
	emms
	jmp	.renderloop
.pan_down:
	fld	qword[top_left+8]
	fadd	st1
	fst	qword[top_left+8]
	emms
	jmp	.renderloop
f_render_mandelbrot:
	fld	dword[zoom]
	fld1
	fdiv	st1
	fild	word[window_height]
	fdivr	st1
	fst	qword[pixel_increment]
	movaps	xmm0, [top_left]
	movaps	[current_pixel], xmm0
	xor	rax, rax
	xor	rbx, rbx
	movzx	r13, word[window_width]
	movzx	r14, word[window_height]
.loop:
	cmp	rax, r13
	jz	.inc_y
	call	f_test_set
	mov	dword[buf1], ecx
	mov	dword[buf1+4], MAX_ITERATIONS
	fild	dword[buf1+4]
	fild	dword[buf1]
	fdiv	st1
	fld1
	fsub	st1
	fld	dword[color_seg]
	fmul	st1
	fist	dword[buf1]
	emms
	push	rax
	push	rbx
	movsx	rax, dword[buf1]
	add	rax, 232
	cmp	rax, 232
	xor	rdx, rdx
	mov	rbx, 10
	idiv	rbx
	push	rdx
	xor	rdx, rdx
	idiv	rbx
	add	rax, 48
	mov	byte[colorbuf], al
	add	rdx, 48
	mov	byte[colorbuf+1], dl
	pop	rdx
	add	rdx, 48
	mov	byte[colorbuf+2], dl
	pop	rbx
	pop	rax
	mov	rsi, colorbuf
	call	f_draw_pixel
	inc	rax
	fld	qword[current_pixel]
	fld	qword[pixel_increment]
	fadd	st1
	fst	qword[current_pixel]
	emms
	jmp	.loop
.inc_y:
	inc	rbx
	cmp	rbx, r14
	jz	.end
	fld	qword[current_pixel+8]
	fld	qword[pixel_increment]
	fadd	st1
	fst	qword[current_pixel+8]
	emms
	xor	rax, rax
	mov	r8, qword[top_left]
	mov	qword[current_pixel], r8
	jmp	.loop
.end:
	ret
f_test_set:
	xor	rcx, rcx
	xorps	xmm0, xmm0
	movaps	[buf1], xmm0
	movaps	[buf1+16], xmm0
.loop:
	fld1
	fadd	st0
	fadd	st0
	fld	qword[buf1+16]
	fld	qword[buf1+24]
	fadd	st1
	fcomi	st2
	emms
	ja	.end
	cmp	rcx, MAX_ITERATIONS
	jz	.end
	inc	rcx
	fld	qword[buf1]
	fadd	st0
	fld	qword[buf1+8]
	fmul	st1
	fld	qword[current_pixel+8]
	fadd	st1
	fst	qword[buf1+8]
	emms	
	fld	qword[buf1+24]
	fld	qword[buf1+16]
	fsub	st1
	fld	qword[current_pixel]
	fadd	st1
	fst	qword[buf1]
	fmul	st0
	fst	qword[buf1+16]
	fld	qword[buf1+8]
	fmul	st0
	fst	qword[buf1+24]
	emms
	jmp	.loop
.end:
	ret
f_draw_pixel:
	push	rax
	push	rbx
	shr	rbx, 1
	jc	.use_fg
	%macro	calc_offset	0
		imul	rax, UNIT_SIZE
		imul	rbx, qword[double_row]
		lea	r15, [rax+rbx+TOP_SIZE]
		add	r15, qword[framebuf]
	%endmacro
.use_bg:
	calc_offset
	mov	r8w, word[rsi]
	mov	word[r15+7], r8w
	mov	r8b, byte[rsi+2]
	mov	byte[r15+9], r8b
	jmp	.end
.use_fg:
	calc_offset
	mov	r8w, word[rsi]
	mov	word[r15+18], r8w
	mov	r8b, byte[rsi+2]
	mov	byte[r15+20], r8b
.end:
	pop	rbx
	pop	rax
	ret
f_init_screen:
	mov	rax, qword[framebuf]
	mov	r8, qword[escape_home]
	mov	qword[rax], r8
	add	rax, TOP_SIZE
	mov	rbx, qword[screen_size]
	add	rbx, qword[framebuf]
	mov	r8, qword[escape_data]
	mov	r9, qword[escape_data+8]
	mov	r10, qword[escape_data+16]
	mov	r11w, word[escape_data+24]
.loop:
	cmp	rax, rbx
	jz	.end
	mov	qword[rax], r8
	mov	qword[rax+8], r9
	mov	qword[rax+16], r10
	mov	word[rax+24], r11w
	add	rax, UNIT_SIZE
	jmp	.loop
.end:
	ret
f_int:
	mov	rax, 1
	mov	rdi, 1
	mov	rsi, escape_home
	mov	rdx, 8
	syscall
	mov	rax, 11
	mov	rdi, qword[framebuf]
	mov	rsi, qword[screen_size]
	syscall
	mov	rax, 60
	mov	rdi, 101
	syscall
