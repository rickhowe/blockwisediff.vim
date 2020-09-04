" blockwisediff.vim: A block-oriented diff to compare selected lines virtually
"
" Last Change:	2020/09/04
" Version:		1.0
" Author:		Rick Howe <rdcxy754@ybb.ne.jp>
" Copyright:	(c) 2020 by Rick Howe

if exists('g:loaded_blockwisediff') || !has('diff') || v:version < 800
	finish
endif
let g:loaded_blockwisediff = 1.0

let s:save_cpo = &cpoptions
set cpo&vim

command! -range -bar
				\ BWDiffthis call blockwisediff#Diffthis(<line1>, <line2>, 0)
command! -bang -bar BWDiffoff call blockwisediff#Diffoff(<bang>0)
command! -bang -bar BWDiffupdate call blockwisediff#Diffupdate(<bang>0)

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=4 sw=4
