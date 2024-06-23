#!/bin/bash

function rg_fzf() {
	local search_pattern="$1"
	rg --line-number --no-heading --color=always "$search_pattern" |
		fzf --ansi --preview 'echo {} | awk -F: "{print \$1}" | xargs bat --style=numbers --color=always --line-range=:500' |
		awk -F: '{print $1 " +" $2}' |
		xargs -r nvim
}
