# History
HISTCONTROL=ignoreboth

shopt -s histappend
shopt -s cmdhist
shopt -s lithist

HISTSIZE=1000
HISTFILESIZE=2000

# Terminal dimensions and recursive globs
shopt -s checkwinsize

shopt -s globstar

# Prompt and terminal title
case "$TERM" in
  xterm-color | *-256color) color_prompt=yes ;;
esac

if [ "$color_prompt" = yes ]; then
  PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
  PS1='\u@\h:\w\$ '
fi
unset color_prompt

case "$TERM" in
  xterm* | rxvt*) PS1="\[\e]0;\u@\h: \w\a\]$PS1" ;;
esac

# Colors and aliases
eval "$(dircolors -b)"
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

alias ls="ls -a --color=auto"
alias la='ls -A'
alias l="ls -l"
alias g="git"

alias ..='cd ..'
alias ...='cd ../..'

# Python virtual environment
if [ -f "$HOME/.venv/bin/activate" ] && [ -z "$VIRTUAL_ENV" ]; then
  . "$HOME/.venv/bin/activate"
fi
