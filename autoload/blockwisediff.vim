" blockwisediff.vim: A block-oriented diff to compare selected lines virtually
"
" Last Change:	2020/09/04
" Version:		1.0
" Author:		Rick Howe <rdcxy754@ybb.ne.jp>
" Copyright:	(c) 2020 by Rick Howe

let s:save_cpo = &cpoptions
set cpo&vim

function! blockwisediff#Diffthis(sl, el, sb) abort
	if !exists('t:BDiff')
		let t:BDiff = {}
	elseif 2 <= len(t:BDiff)
		call execute(['echohl Error',
						\'echo "2 blocks already selected in this tab page!"',
														\'echohl None'], '')
		return
	endif
	" get line range and initialize the 1st or 2nd block
	let [k, j] = !has_key(t:BDiff, 1) ? [1, 2] : [2, 1]
	if len(t:BDiff) == 1
		if t:BDiff[j].wid == win_getid() &&
					\a:sl <= t:BDiff[j].sel[1] && t:BDiff[j].sel[0] <= a:el
			call execute(['echohl Error',
						\'echo "This range already selected in this window!"',
														\'echohl None'], '')
			return
		endif
	endif
	let t:BDiff[k] = {'wid': win_getid(), 'sel': [a:sl, a:el],
								\'txt': [], 'pos': [], 'lid': [], 'uid': []}
	for ln in range(a:sl, a:el)
		let t:BDiff[k].lid += [matchaddpos('DiffChange', [ln], 0)]
	endfor
	call s:ToggleEvent(1)
	if len(t:BDiff) < 2 | return | endif
	" get diffopt flags for icase/iwhite
	let do = split(&diffopt, ',')
	let ic = (index(do, 'icase') != -1)
	let iw = (index(do, 'iwhiteall') != -1) ? 1 :
									\(index(do, 'iwhite') != -1) ? 2 :
									\(index(do, 'iwhiteeol') != -1) ? 3 : 0
	" get a diff unit and set its regular expression
	let du = get(t:, 'DiffUnit', get(g:, 'DiffUnit', 'Word1'))
	if du == 'Char'
		let ur = (iw == 1 || iw == 2) ? '\%(\s\+\|.\)\zs' : '\zs'
	elseif du == 'Word2'
		let ur = '\%(\s\+\|\S\+\)\zs'
	elseif du == 'Word3'
		let ur = '\<\|\>'
	else
		let ur = (iw == 1 || iw == 2) ?
								\'\%(\s\+\|\w\+\|\W\)\zs' : '\%(\w\+\|\W\)\zs'
	endif
	let lb = nr2char(0x0a)
	for k in [1, 2]
		" split all line and get its position
		for ln in range(t:BDiff[k].sel[0], t:BDiff[k].sel[1])
			let tc = 1
			for tx in split(getbufline(winbufnr(t:BDiff[k].wid), ln)[0], ur)
				let t:BDiff[k].txt += [tx]
				let tl = len(tx)
				let t:BDiff[k].pos += [[ln, tc, tl]]
				let tc += tl
			endfor
			" add a linebreak dummy txt/pos if not show linebreak positions
			if !a:sb	
				if ln < t:BDiff[k].sel[1]
					let t:BDiff[k].txt += [lb]
					let t:BDiff[k].pos += [[ln, tc, 1]]
				endif
			endif
		endfor
		" change the dummy to space if prev/next are 0x21-0x7e, or remove it
		if !a:sb
			for ix in filter(range(len(t:BDiff[k].txt) - 1, 0, -1),
											\'t:BDiff[k].txt[v:val] == lb')
				if 0 < ix && ix < len(t:BDiff[k].txt) - 1 &&
								\t:BDiff[k].txt[ix - 1] =~ '[\x21-\x7e]$' &&
									\t:BDiff[k].txt[ix + 1] =~ '^[\x21-\x7e]'
					let t:BDiff[k].txt[ix] = ' '
				else
					unlet t:BDiff[k].txt[ix]
					unlet t:BDiff[k].pos[ix]
				endif
			endfor
		endif
		" adjust spaces based on iwhite
		if iw == 1
			for ix in filter(range(len(t:BDiff[k].txt) - 1, 0, -1),
									\'t:BDiff[k].txt[v:val] =~ "^\\s\\+$"')
				unlet t:BDiff[k].txt[ix]
				unlet t:BDiff[k].pos[ix]
			endfor
		elseif iw == 2
			call map(t:BDiff[k].txt, 'substitute(v:val, "\\s\\+", " ", "g")')
		endif
		if iw == 2 || iw == 3
			if t:BDiff[k].txt[-1] =~ '^\s\+$'
				unlet t:BDiff[k].txt[-1]
				unlet t:BDiff[k].pos[-1]
			endif
		endif
	endfor
	" compare txt
	let sc = &ignorecase | let &ignorecase = ic
	let es = s:TraceDiffChar(t:BDiff[1].txt, t:BDiff[2].txt)
	let &ignorecase = sc
	" set highlight colors for changed units
	let cn = 0
	let ch = ['DiffText']
	let dc = get(t:, 'DiffColors', get(g:, 'DiffColors', 0))
	if 1 <= dc && dc <= 3
		let ch += ['SpecialKey', 'Search', 'CursorLineNr',
						\'Visual', 'WarningMsg', 'StatusLineNC', 'MoreMsg',
						\'ErrorMsg', 'LineNr', 'Conceal', 'NonText',
						\'ColorColumn', 'ModeMsg', 'PmenuSel', 'Title']
									\[: ((dc == 1) ? 2 : (dc == 2) ? 6 : -1)]
	endif
	" set highlight positions
	let [m1, m2] = [[], []]
	let [p1, p2] = [0, 0]
	for ed in split(es, '\%(=\+\|[+-]\+\)\zs')
		let qn = len(ed)
		if ed[0] == '='
			let [p1, p2] += [qn, qn]
		else
			let q1 = len(substitute(ed, '+', '', 'g'))
			let q2 = qn - q1
			let k = (q1 == 0) ? 1 : (q2 == 0) ? 2 : 0
			if k == 0		" change
				let hl = ch[cn % len(ch)]
				let cn += 1
			else			" delete and add
				let hl = 'bwDiffErase'
				if 0 < p{k}
					let po = t:BDiff[k].pos[p{k} - 1]
					let bl = len(matchstr(t:BDiff[k].txt[p{k} - 1], '.$'))
					let m{k} += [[hl, [po[0], po[1] + po[2] - bl, bl]]]
				endif
				if p{k} < len(t:BDiff[k].pos)
					let po = t:BDiff[k].pos[p{k}]
					let bl = len(matchstr(t:BDiff[k].txt[p{k}], '^.'))
					let m{k} += [[hl, [po[0], po[1], bl]]]
				endif
				let hl = 'DiffAdd'
			endif
			for k in [1, 2]
				while 0 < q{k}
					let m{k} += [[hl, t:BDiff[k].pos[p{k}]]]
					let p{k} += 1
					let q{k} -= 1
				endwhile
			endfor
		endif
	endfor
	" draw highlights
	let cw = win_getid()
	for k in [1, 2]
		noautocmd call win_gotoid(t:BDiff[k].wid)
		for [hl, po] in m{k}
			let t:BDiff[k].uid += [matchaddpos(hl, [po], 10)]
		endfor
	endfor
	noautocmd call win_gotoid(cw)
endfunction

function! blockwisediff#Diffoff(all) abort
	if !exists('t:BDiff') | return | endif
	let cw = win_getid()
	for k in [1, 2]
		if has_key(t:BDiff, k) && (a:all || t:BDiff[k].wid == win_getid())
			noautocmd call win_gotoid(t:BDiff[k].wid)
			call map(t:BDiff[k].lid, 'matchdelete(v:val)')
			call map(t:BDiff[k].uid, 'matchdelete(v:val)')
			unlet t:BDiff[k]
		endif
	endfor
	if len(t:BDiff) < 2
		if len(t:BDiff) == 1
			" resume back to the initial state
			let k = has_key(t:BDiff, 1) ? 1 : 2
			noautocmd call win_gotoid(t:BDiff[k].wid)
			call map(t:BDiff[k].uid, 'matchdelete(v:val)')
			let t:BDiff[k].uid = []
			let t:BDiff[k].txt = []
			let t:BDiff[k].pos = []
		else
			unlet t:BDiff
		endif
	endif
	noautocmd call win_gotoid(cw)
	call s:ToggleEvent(0)
endfunction

function! blockwisediff#Diffupdate(sb) abort
	if !exists('t:BDiff') || len(t:BDiff) != 2 | return | endif
	let bw = copy(t:BDiff)
	call blockwisediff#Diffoff(1)
	let cw = win_getid()
	for k in [1, 2]
		if has_key(bw, k)
			noautocmd call win_gotoid(bw[k].wid)
			if bw[k].pos[-1][0] <= line('$')
				call blockwisediff#Diffthis(bw[k].pos[0][0],
													\bw[k].pos[-1][0], a:sb)
			endif
		endif
	endfor
	noautocmd call win_gotoid(cw)
endfunction

function! s:ToggleEvent(on) abort
	let bd = 'blockwisediff'
	let tv = filter(map(range(1, tabpagenr('$')),
							\'gettabvar(v:val, "BDiff")'), '!empty(v:val)')
	call execute(['augroup ' . bd, 'autocmd!', 'augroup END'])
	let bn = 0
	for tb in tv
		for k in [1, 2]
			if has_key(tb, k)
				call execute('autocmd! ' . bd .
							\' BufWinLeave <buffer=' . winbufnr(tb[k].wid) .
						\'>  call s:ClearBlockwiseDiff(' . tb[k].wid . ')')
				let bn += 1
			endif
		endfor
	endfor
	if bn == 0
		call execute('augroup! ' . bd)
	endif
	if bn == 1 && a:on || bn == 0 && !a:on
		call s:ToggleHL(a:on)
	endif
endfunction

function! s:ToggleHL(on) abort
	let [fh, th, ta] = ['DiffChange', 'bwDiffErase', 'bold,underline']
	call execute('highlight clear ' . th)
	if a:on
		let at = {}
		let id = hlID(fh)
		for hm in ['term', 'cterm', 'gui']
			for hc in ['fg', 'bg', 'sp']
				let at[hm . hc] = synIDattr(id, hc, hm)
			endfor
			let at[hm] = join(filter(['bold', 'italic', 'reverse', 'inverse',
					\'standout', 'underline', 'undercurl', 'strikethrough'],
									\'synIDattr(id, v:val, hm) == 1'), ',')
			let at[hm] .= (!empty(at[hm]) ? ',' : '') . ta
		endfor
		call execute('highlight ' . th . ' ' .
								\join(map(items(filter(at, '!empty(v:val)')),
											\'v:val[0] . "=" . v:val[1]')))
	endif
endfunction

function! s:ClearBlockwiseDiff(wid) abort
	let cw = win_getid()
	noautocmd call win_gotoid(a:wid)
	call blockwisediff#Diffoff(0)
	noautocmd call win_gotoid(cw)
endfunction

function! s:TraceDiffChar(u1, u2) abort
	" An O(NP) Sequence Comparison Algorithm
	let [n1, n2] = [len(a:u1), len(a:u2)]
	if a:u1 == a:u2 | return repeat('=', n1)
	elseif n1 == 0 | return repeat('+', n2)
	elseif n2 == 0 | return repeat('-', n1)
	endif
	" reverse to be N >= M
	let [N, M, u1, u2, e1, e2] = (n1 >= n2) ?
			\[n1, n2, a:u1, a:u2, '+', '-'] : [n2, n1, a:u2, a:u1, '-', '+']
	let D = N - M
	let fp = repeat([-1], M + N + 1)
	let etree = []		" [next edit, previous p, previous k]
	let p = -1
	while fp[D] != N
		let p += 1
		let epk = repeat([[]], p * 2 + D + 1)
		for k in range(-p, D - 1, 1) + range(D + p, D, -1)
			let [y, epk[k]] = (fp[k - 1] < fp[k + 1]) ?
							\[fp[k + 1], [e1, (k < D) ? p - 1 : p, k + 1]] :
							\[fp[k - 1] + 1, [e2, (k > D) ? p - 1 : p, k - 1]]
			let x = y - k
			while x < M && y < N && u2[x] == u1[y]
				let epk[k][0] .= '='
				let [x, y] += [1, 1]
			endwhile
			let fp[k] = y
		endfor
		let etree += [epk]
	endwhile
	" create a shortest edit script (SES) from last p and k
	let ses = ''
	while 1
		let ses = etree[p][k][0] . ses
		if p == 0 && k == 0 | return ses[1 :] | endif
		let [p, k] = etree[p][k][1 : 2]
	endwhile
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=4 sw=4
