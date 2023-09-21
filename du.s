* du - print disk usage
*
* Itagaki Fumihiko 12-Dec-92  Create.
* 1.0
* Itagaki Fumihiko 10-Jan-93  GETPDB -> lea $10(a0),a0
* Itagaki Fumihiko 20-Jan-93  引数 - と -- の扱いの変更
* Itagaki Fumihiko 22-Jan-93  スタックを拡張
* 1.1
* Itagaki Fumihiko 04-Jan-94  -B <size> は -B<size> と書いてもよい
* Itagaki Fumihiko 04-Jan-94  \ が \/ と表示される不具合を修正
* 1.2
*
* Usage: du [ -DLSacsx ] [ -B blocksize ] [ -- ] [ file ] ...

.include doscall.h
.include error.h
.include limits.h
.include stat.h
.include chrcode.h

.xref DecodeHUPAIR
.xref getlnenv
.xref issjis
.xref toupper
.xref atou
.xref utoa
.xref strlen
.xref strcpy
.xref stpcpy
.xref strbot
.xref strfor1
.xref divul
.xref strip_excessive_slashes
.xref contains_dos_wildcard
.xref skip_root

REQUIRED_OSVER		equ	$200			*  2.00以降

MAXRECURSE	equ	64	*  サブディレクトリを検索するために再帰する回数の上限．
				*  MAXDIR （パス名のディレクトリ部 "/1/2/3/../" の長さ）
				*  が 64 であるから、31で充分であるが，
				*  シンボリック・リンクを考慮して 64 とする．
				*  スタック量にかかわる．

FATCHK_STATIC	equ	256	*  静的バッファでfatchkできるようにしておくFATチェイン数

FLAG_a		equ	0
FLAG_s		equ	1
FLAG_S		equ	2
FLAG_c		equ	3
FLAG_D		equ	4
FLAG_L		equ	5
FLAG_B		equ	6
FLAG_x		equ	7

LNDRV_O_CREATE		equ	4*2
LNDRV_O_OPEN		equ	4*3
LNDRV_O_DELETE		equ	4*4
LNDRV_O_MKDIR		equ	4*5
LNDRV_O_RMDIR		equ	4*6
LNDRV_O_CHDIR		equ	4*7
LNDRV_O_CHMOD		equ	4*8
LNDRV_O_FILES		equ	4*9
LNDRV_O_RENAME		equ	4*10
LNDRV_O_NEWFILE		equ	4*11
LNDRV_O_FATCHK		equ	4*12
LNDRV_realpathcpy	equ	4*16
LNDRV_LINK_FILES	equ	4*17
LNDRV_OLD_LINK_FILES	equ	4*18
LNDRV_link_nest_max	equ	4*19
LNDRV_getrealpath	equ	4*20

****************************************************************
.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom,a7			*  A7 := スタックの底
		DOS	_VERNUM
		cmp.w	#REQUIRED_OSVER,d0
		bcs	dos_version_mismatch

		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
	*  lndrv常駐チェック
	*
		bsr	getlnenv
		move.l	d0,lndrv
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.L : フラグ
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		tst.b	1(a0)
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		moveq	#FLAG_a,d1
		cmp.b	#'a',d0
		beq	set_option

		moveq	#FLAG_s,d1
		cmp.b	#'s',d0
		beq	set_option

		moveq	#FLAG_S,d1
		cmp.b	#'S',d0
		beq	set_option

		moveq	#FLAG_c,d1
		cmp.b	#'c',d0
		beq	set_option

		moveq	#FLAG_x,d1
		cmp.b	#'x',d0
		beq	set_option

		moveq	#FLAG_D,d1
		cmp.b	#'D',d0
		beq	set_option

		cmp.b	#'L',d0
		beq	set_option_L

		move.l	#1024,d1
		cmp.b	#'k',d0
		beq	set_blocksize

		cmp.b	#'B',d0
		beq	parse_blocksize

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

parse_blocksize:
		tst.b	(a0)
		bne	parse_blocksize_1

		subq.l	#1,d7
		bcs	too_few_args

		addq.l	#1,a0
parse_blocksize_1:
		bsr	atou
		bne	bad_blocksize

		tst.l	d1
		beq	bad_blocksize

		tst.b	(a0)
		bne	bad_blocksize
set_blocksize:
		move.l	d1,blocksize
		bset	#FLAG_B,d5
		bra	set_option_done

set_option_L:
		bset	#FLAG_L,d5
set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
	*
	*  ファイル引数を検査する
	*
		tst.l	d7
		bne	args_ok

		lea	default_arg(pc),a0
		moveq	#1,d7
args_ok:
	*
	*  引数をstatするループ
	*
		moveq	#0,d6				*  D6.W : 終了ステータス
		moveq	#0,d1
du_args_loop:
		movea.l	a0,a1
		bsr	strfor1
		exg	a0,a1
		move.b	(a0),d0
		beq	du_args_1

		cmpi.b	#':',1(a0)
		bne	du_args_1

		bsr	toupper
		move.b	d0,(a0)
du_args_1:
		bsr	strip_excessive_slashes
		bsr	du_arg
		add.l	d0,d1
		movea.l	a1,a0
		subq.l	#1,d7
		bne	du_args_loop

		btst	#FLAG_c,d5
		beq	exit_program

		lea	str_total(pc),a0
		move.l	d1,d0
		bsr	output
exit_program:
		move.w	d6,-(a7)
		DOS	_EXIT2

bad_blocksize:
		lea	msg_bad_blocksize(pc),a0
		bra	werror_usage

too_few_args:
		lea	msg_too_few_args(pc),a0
werror_usage:
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

dos_version_mismatch:
		lea	msg_dos_version_mismatch(pc),a0
		bra	error_exit_3

insufficient_memory:
		lea	msg_no_memory(pc),a0
error_exit_3:
		bsr	werror_myname_and_msg
		moveq	#3,d6
		bra	exit_program
****************************************************************
* du_arg - 1つの引数を処理する
*
* CALL
*      A0     引数の先頭アドレス
*
* RETURN
*      D0.L   サイズ
****************************************************************
du_arg:
		movem.l	d1/a0-a3,-(a7)
		movea.l	a0,a3
		moveq	#-1,d0
		bsr	strlen
		cmp.l	#MAXPATH,d0
		bhi	du_arg_too_long_path

		bsr	contains_dos_wildcard
		bne	du_arg_nofile

		btst	#FLAG_D,d5
		bsr	xstat
		bsr	stat2
		bmi	du_arg_nofile
		bne	du_arg_dir

		lea	filesbuf(pc),a1
		btst.b	#MODEBIT_DIR,ST_MODE(a1)
		bne	du_arg_dir

		move.l	a0,-(a7)
		lea	stat_pathname(pc),a0
		bsr	filesize
		movea.l	(a7)+,a0
		bsr	output
		bra	du_arg_return

du_arg_dir:
		movea.l	a0,a1
		btst	#FLAG_x,d5
		beq	du_arg_dir_1

		lea	stat_pathname(pc),a0
		bsr	get_driveno
		move.w	d0,drive
du_arg_dir_1:
		lea	pathname(pc),a0
		bsr	stpcpy
		exg	a0,a1
		bsr	skip_root
		exg	a0,a1
		beq	du_arg_dir_2

		move.b	#'/',(a0)+
du_arg_dir_2:
		lea	stat_pathname(pc),a1
		bsr	du_directory
		lea	pathname(pc),a0
		bsr	output
du_arg_return:
		movem.l	(a7)+,d1/a0-a3
		rts

du_arg_nofile:
		movea.l	a3,a0
		bsr	werror_myname_and_msg
		lea	msg_nofile(pc),a0
		bsr	werror
		moveq	#2,d6
du_arg_return_0:
		moveq	#0,d0
		bra	du_arg_return

du_arg_too_long_path:
		movea.l	a3,a0
		bsr	too_long_path
		bra	du_arg_return_0
****************************************************************
* du_directory
*
* CALL
*      (pathname)   パス名（そのまま *.* を cat できる形であること）
*      A0           (pathname)の末尾のアドレス（NULでなくてもよい）
*      A1           fatchkすべきパス名
*
* RETURN
*      D0.L         サイズ
*      D1/A0-A2     破壊
*
* NOTE
*      再帰する．スタックに注意
****************************************************************
du_directory_filesbuf       = -((STATBUFSIZE+1)>>1<<1)
du_directory_corrected_name = du_directory_filesbuf-128
du_directory_namebottom     = du_directory_corrected_name-4
du_directory_tailptr        = du_directory_namebottom-4
du_directory_total          = du_directory_tailptr-4
du_directory_numentry       = du_directory_total-4
du_directory_autosize       = -du_directory_numentry

du_recurse_stacksize	equ	du_directory_autosize+4*2	* 4*2 ... A6/PC

du_directory:
		link	a6,#du_directory_numentry
		clr.l	du_directory_total(a6)
		move.l	a0,du_directory_namebottom(a6)
		move.l	a0,-(a7)
		lea	du_directory_corrected_name(a6),a0
		bsr	strcpy
		movea.l	(a7)+,a0
		lea	pathname(pc),a1
		move.l	a0,d0
		sub.l	a1,d0
		cmp.l	#MAXHEAD,d0
		bhi	du_directory_too_long_path

		move.l	a0,du_directory_tailptr(a6)
		lea	str_dos_allfile(pc),a1
		bsr	strcpy
		move.w	#MODEVAL_ALL,-(a7)
		pea	pathname(pc)
		pea	du_directory_filesbuf(a6)
		DOS	_FILES
		lea	10(a7),a7
				*  chdir で降りながら files("*.*") する方が速いことが実験で
				*  確かめられたが，速くなるとは言っても高々全体の5%程度であ
				*  るし，条件によっては逆に遅くなることも考えられる．それに，
				*
				*  o ディレクトリへのシンボリック・リンクに降りると
				*    chdir("..") では戻れないので，その場合はカレント・ディ
				*    レクトリを保存しておく処理
				*
				*  o ディレクトリ引数の処理後はどこにも戻らない処理
				*
				*  o ^Cが押されたら作業ディレクトリに復帰してから終了する処
				*    理
				*
				*  などを行わねばならず，プログラムが複雑になる．これらの処
				*  理を‘必要な場合だけ’行うようにすると，プログラムはさら
				*  に複雑になる．
				*
				*  また，‘ディレクトリへのシンボリック・リンク’のパス名で
				*  も chdir できるという前提が，将来にわたって保証されないか
				*  も知れない（気がしないでもない）．そもそも chdir は‘指定
				*  ドライブのカレント・ディレクトリを変更する’ファンクショ
				*  ンであるから，ドライブをまたがって chdir する lndrv 1.00
				*  の仕様は，Human68k の本来の仕様から少々逸脱している．この
				*  ような観点から，lndrv の chdir の仕様に依存するのは少々危
				*  険と見た．ならば lndrv の chdir を直接は呼ばずに，目的の
				*  ディレクトリのパス名を readlink により読み取って chdir す
				*  れば良い（この処理は，このルーチンに到達するまでに既に行
				*  われている筈であるから，時間的に損することはない）のだが，
				*  それもまたプログラムを複雑にしてしまう．
				*
				*  というわけで，chdir方式は捨てた．
				*
				*  将来の Human68k では，このままでも速くなる可能性もある．
		clr.l	du_directory_numentry(a6)
du_directory_loop:
		tst.l	d0
		bmi	du_directory_done

		addq.l	#1,du_directory_numentry(a6)
		lea	du_directory_filesbuf+ST_NAME(a6),a0
		bsr	is_reldir
		beq	du_directory_next

		movea.l	a0,a1
		movea.l	du_directory_tailptr(a6),a0
		bsr	stpcpy

		moveq	#0,d0
		lea	du_directory_filesbuf(a6),a1
		lea	pathname(pc),a2
		btst	#FLAG_L,d5
		beq	du_directory_not_link

		btst.b	#MODEBIT_LNK,ST_MODE(a1)
		beq	du_directory_not_link

		exg	a0,a2
		bsr	stat
		exg	a0,a2
		bsr	stat2
		bmi	du_directory_next

		lea	stat_pathname(pc),a2
		lea	filesbuf(pc),a1
du_directory_not_link:
		move.l	d0,d1
		btst	#FLAG_x,d5
		beq	du_directory_drive_ok

		exg	a0,a2
		bsr	get_driveno
		exg	a0,a2
		cmp.w	drive,d0
		bne	du_directory_next
du_directory_drive_ok:
		tst.l	d1
		bne	du_directory_dir

		btst.b	#MODEBIT_VOL,ST_MODE(a1)
		bne	du_directory_vol

		btst.b	#MODEBIT_DIR,ST_MODE(a1)
		bne	du_directory_dir
		bra	du_directory_file

du_directory_vol:
		btst	#FLAG_B,d5
		bne	du_directory_next
du_directory_file:
		movea.l	a2,a0
		bsr	filesize
		btst	#FLAG_a,d5
		beq	du_directory_continue

		lea	pathname(pc),a0
		bsr	output
		bra	du_directory_continue

du_directory_dir:
		btst	#FLAG_S,d5
		beq	du_directory_recurse

		btst	#FLAG_s,d5
		beq	du_directory_recurse

		btst	#FLAG_a,d5
		beq	du_directory_next
du_directory_recurse:
		cmpa.l	#stack_lower+du_recurse_stacksize,a7	*  再帰に備えてスタックレベルをチェック
		bhs	recurse_ok

		lea	pathname(pc),a0
		bsr	werror_myname_and_msg
		lea	msg_dir_too_deep(pc),a0
		bsr	werror
		moveq	#2,d6
		bra	du_directory_next

recurse_ok:
		move.b	#'/',(a0)+
		movea.l	a2,a1
		bsr	du_directory			* ［再帰］
		btst	#FLAG_s,d5
		bne	du_directory_dir_1

		lea	pathname(pc),a0
		bsr	output
du_directory_dir_1:
		btst	#FLAG_S,d5
		bne	du_directory_next
du_directory_continue:
		add.l	d0,du_directory_total(a6)
du_directory_next:
		pea	du_directory_filesbuf(a6)
		DOS	_NFILES
		addq.l	#4,a7
		bra	du_directory_loop

du_directory_done:
		lea	pathname(pc),a0
		movea.l	du_directory_namebottom(a6),a1
		clr.b	(a1)
		lea	du_directory_corrected_name(a6),a0
		move.l	du_directory_numentry(a6),d0
		bsr	dirsize
		add.l	d0,du_directory_total(a6)
du_directory_return:
		move.l	du_directory_total(a6),d0
		unlk	a6
		rts

du_directory_too_long_path:
		bsr	too_long_path
		bra	du_directory_done
*****************************************************************
* output
*
* CALL
*      A0     パス名
*      D0.L   サイズ
*
* RETURN
*      none
*****************************************************************
output:
		movem.l	d0/a0,-(a7)
		move.l	a0,-(a7)
		lea	utoabuf(pc),a0
		bsr	utoa
		move.l	a0,-(a7)
		DOS	_PRINT
		move.w	#HT,(a7)
		DOS	_PUTCHAR
		addq.l	#4,a7
		DOS	_PRINT
		pea	str_newline(pc)
		DOS	_PRINT
		addq.l	#8,a7
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
* filesize - 非ディレクトリのサイズを求める
*
* CALL
*      A0     パス名
*      A1     filebuf
*      CCR    リンクを追うなら NE
*
* RETURN
*      D0.L   サイズ
*      (fatchkbuf)   破壊
*****************************************************************
filesize:
		btst	#FLAG_B,d5
		beq	sectorsize

		move.l	ST_SIZE(a1),d0
*****************************************************************
* pseudosize - エントリを複製するのに必要なブロック数を求める
*
* CALL
*      D0.L   バイト数
*
* RETURN
*      D0.L   ブロック数
*****************************************************************
pseudosize:
		move.l	d1,-(a7)
		move.l	blocksize,d1
		bsr	divul
		addq.l	#1,d0
		move.l	(a7)+,d1
		rts
*****************************************************************
* dirsize - ディレクトリのサイズを求める
*
* CALL
*      A0     パス名
*      D0.L   エントリ数
*
* RETURN
*      D0.L   サイズ
*      (fatchkbuf), (nameck_buffer)   破壊
*****************************************************************
dirsize:
		lsl.l	#5,d0				*  x32
		btst	#FLAG_B,d5
		bne	pseudosize
*****************************************************************
* sectorsize - エントリの実際の論理セクタ数を求める
*
* CALL
*      A0     パス名
*
* RETURN
*      D0.L   サイズ
*      (fatchkbuf)   破壊
*****************************************************************
sectorsize:
		movem.l	d1-d2/a1,-(a7)
		moveq	#0,d2
		lea	fatchkbuf(pc),a1
		move.w	#2+8*FATCHK_STATIC+4,-(a7)
		move.l	a1,d0
		bset	#31,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_FATCHK
		lea	10(a7),a7
		cmp.l	#EBADPARAM,d0
		bne	fatchk_success

		move.l	#65520,d0
		move.l	d0,d1
		bsr	malloc
		move.l	d0,d2
		bpl	fatchk_malloc_ok

		sub.l	#$81000000,d0
		cmp.l	#2+8*FATCHK_STATIC+4+4,d0
		blo	insufficient_memory

		move.l	d0,d1
		bsr	malloc
		move.l	d0,d2
		bmi	insufficient_memory
fatchk_malloc_ok:
		subq.w	#4,d1
		move.w	d1,-(a7)
		bset	#31,d2
		move.l	d2,-(a7)
		bclr	#31,d2
		move.l	a0,-(a7)
		DOS	_FATCHK
		lea	10(a7),a7
		cmp.l	#EBADPARAM,d0
		beq	insufficient_memory

		movea.l	d2,a1
fatchk_success:
		moveq	#0,d1
		tst.l	d0
		bmi	calc_sector_size_done

		addq.l	#2,a1
calc_sector_size_loop:
		tst.l	(a1)+
		beq	calc_sector_size_done

		add.l	(a1)+,d1
		bra	calc_sector_size_loop

calc_sector_size_done:
		move.l	d2,d0
		beq	sector_size_ok

		bsr	free
sector_size_ok:
		move.l	d1,d0
		movem.l	(a7)+,d1-d2/a1
		rts
*****************************************************************
xstat:
		bne	stat
lstat:
		movem.l	d1-d7/a0-a6,-(a7)
		move.l	#LNDRV_realpathcpy,d1
		bra	xstat_1

stat:
		movem.l	d1-d7/a0-a6,-(a7)
		move.l	#LNDRV_getrealpath,d1
xstat_1:
		tst.l	lndrv
		beq	xstat_3

		clr.l	-(a7)
		DOS	_SUPER				*  スーパーバイザ・モードに切り換える
		addq.l	#4,a7
		move.l	d0,-(a7)			*  前の SSP の値
		movea.l	lndrv,a1
		movea.l	(a1,d1.l),a1
		move.l	a0,-(a7)
		pea	stat_pathname(pc)
		jsr	(a1)
		addq.l	#8,a7
		moveq	#-1,d1
		tst.l	d0
		bmi	xstat_2

		movea.l	lndrv,a1
		movea.l	LNDRV_O_FILES(a1),a1
		move.w	#MODEVAL_ALL,-(a7)
		pea	stat_pathname(pc)
		pea	filesbuf(pc)
		movea.l	a7,a6
		jsr	(a1)
		lea	10(a7),a7
		move.l	d0,d1
xstat_2:
		DOS	_SUPER				*  ユーザ・モードに戻す
		addq.l	#4,a7
		move.l	d1,d0
		bra	xstat_return

xstat_3:
		move.l	a0,a1
		lea	stat_pathname(pc),a0
		bsr	strcpy
		move.w	#MODEVAL_ALL,-(a7)
		move.l	a1,-(a7)
		pea	filesbuf(pc)
		DOS	_FILES
		lea	10(a7),a7
xstat_return:
		movem.l	(a7)+,d1-d7/a0-a6
		tst.l	d0
		rts
*****************************************************************
stat2:
		bpl	stat2_return_0

		addq.l	#1,d0
		beq	stat2_fail

		pea	nameck_buffer(pc)
		pea	stat_pathname(pc)
		DOS	_NAMECK
		addq.l	#8,a7
		tst.l	d0
		bmi	stat2_fail

		tst.b	nameck_buffer+67
		bne	stat2_fail

		move.l	a0,-(a7)
		lea	nameck_buffer(pc),a0
		bsr	strip_excessive_slashes
		bsr	lstat
		movea.l	(a7)+,a0
		bpl	stat2_return_0

		addq.l	#1,d0
		beq	stat2_fail

		tst.b	nameck_buffer+3
		beq	stat2_return_1
stat2_fail:
		moveq	#-1,d0
		rts

stat2_return_1:
		moveq	#1,d0
		rts

stat2_return_0:
		moveq	#0,d0
		rts
****************************************************************
get_driveno:
		tst.l	d0
		bne	get_driveno_root

		move.l	a1,-(a7)
		lea	fatchkbuf(pc),a1
		move.l	a1,d0
		bset	#31,d0
		move.w	#14,-(a7)
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_FATCHK
		lea	10(a7),a7
		move.w	(a1),d0
		movea.l	(a7)+,a1
		rts

get_driveno_root:
		moveq	#0,d0
		move.b	(a0),d0
		sub.w	#'A'-1,d0
		rts
****************************************************************
* is_reldir - 名前が . か .. であるかどうかを調べる
*
* CALL
*      A0     名前
*
* RETURN
*      CCR    名前が . か .. ならば EQ
****************************************************************
is_reldir:
		moveq	#0,d0
		cmpi.b	#'.',(a0)
		bne	is_reldir_return

		tst.b	1(a0)
		beq	is_reldir_return

		cmpi.b	#'.',1(a0)
		bne	is_reldir_return

		tst.b	2(a0)
is_reldir_return:
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
free:
		move.l	d0,-(a7)
		DOS	_MFREE
		addq.l	#4,a7
		rts
*****************************************************************
werror_myname_and_msg:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
werror:
		move.l	d0,-(a7)
		bsr	strlen
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		move.l	(a7)+,d0
		rts
*****************************************************************
too_long_path:
		bsr	werror_myname_and_msg
		move.l	a0,-(a7)
		lea	msg_too_long_path(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		moveq	#2,d6
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## du 1.2 ##  Copyright(C)1992-94 by Itagaki Fumihiko',0

**
**  定数
**

msg_myname:			dc.b	'du: ',0
msg_dos_version_mismatch:	dc.b	'バージョン2.00以降のHuman68kが必要です',CR,LF,0
msg_too_long_path:		dc.b	': パス名が長過ぎます',CR,LF,0
msg_nofile:			dc.b	': このようなファイルやディレクトリはありません',CR,LF,0
msg_dir_too_deep:		dc.b	': ディレクトリが深過ぎて処理できません',CR,LF,0
msg_no_memory:			dc.b	'メモリが足りません',CR,LF,0
msg_illegal_option:		dc.b	'不正なオプション -- ',0
msg_bad_blocksize:		dc.b	'ブロック長の指定が正しくありません',0
msg_too_few_args:		dc.b	'引数が足りません',0
msg_usage:			dc.b	CR,LF
				dc.b	'使用法:  du [-DLSacksx] [-B <ブロック長>] [--] [<パス名>] ...'
str_newline:			dc.b	CR,LF,0
default_arg:			dc.b	'.',0
str_dos_allfile:		dc.b	'*.*',0
str_total:			dc.b	'合計',0
*****************************************************************
.bss

.even
lndrv:			ds.l	1
blocksize:		ds.l	1
drive:			ds.w	1
utoabuf:		ds.b	11
.even
filesbuf:		ds.b	STATBUFSIZE
nameck_buffer:		ds.b	91
pathname:		ds.b	MAXPATH+1
stat_pathname:		ds.b	128
.even
fatchkbuf:		ds.b	2+8*FATCHK_STATIC+4
.even
		ds.b	16384
		*  マージンとスーパーバイザ・スタックとを兼ねて16KB確保しておく．
stack_lower:
		ds.b	du_recurse_stacksize*(MAXRECURSE+1)
		*  必要なスタック量は，再帰の度に消費されるスタック量とその回数とで決まる．
		ds.b	16
.even
stack_bottom:
*****************************************************************

.end start
