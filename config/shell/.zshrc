# macrift — zsh config

# PATH
export PATH="$HOME/.local/bin:$PATH"

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null

# Aliases
if command -v eza &>/dev/null; then
    alias ls="eza --icons --group-directories-first"
    alias ll="eza -la --icons --group-directories-first"
    alias lt="eza --tree --level=2 --icons"
fi
command -v bat &>/dev/null && alias cat="bat --style=auto"
command -v rg &>/dev/null && alias grep="rg"
command -v fd &>/dev/null && alias find="fd"
command -v lazygit &>/dev/null && alias lg="lazygit"
alias g="git"
alias c="clear"
alias ..="cd .."
alias ...="cd ../.."

# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# Options
setopt AUTO_CD
setopt CORRECT
setopt NO_BEEP

# Completions
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# FZF
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Starship prompt
eval "$(starship init zsh)" 2>/dev/null

# FastFetch
fastfetch 2>/dev/null
