# macrift — zsh config (zinit + starship)

# Zinit
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]] && command -v git &>/dev/null; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "$ZINIT_HOME/zinit.zsh"

# Plugins (turbo mode — loads async after prompt)
zinit light-mode for \
    atinit"zicompinit; zicdreplay" \
        zdharma-continuum/fast-syntax-highlighting \
    atload"_zsh_autosuggest_start" \
        zsh-users/zsh-autosuggestions \
    blockf atpull"zinit creinstall -q ." \
        zsh-users/zsh-completions \
    Aloxaf/fzf-tab

# Autosuggestions — fish-style (history first, then completion)
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=8"

# PATH
export PATH="$HOME/.local/bin:$PATH"

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null

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
zstyle ':completion:*' menu no
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':fzf-tab:*' fzf-min-height 10

# Key bindings
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^W' backward-kill-word
bindkey '^[[1;3C' forward-word  # Alt+→  accept word (like Fish)
bindkey '^[f' forward-word      # Alt+F  accept word (like Fish)

# Aliases — files
if command -v eza &>/dev/null; then
    alias ls="eza --icons --group-directories-first"
    alias ll="eza -la --icons --group-directories-first"
    alias lt="eza --tree --level=2 --icons"
fi
command -v bat &>/dev/null && alias cat="bat --style=auto"
command -v rg &>/dev/null && alias grep="rg"
command -v fd &>/dev/null && alias find="fd"

# Aliases — git
alias g="git"
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gl="git log --oneline -20"
alias gd="git diff"
alias gco="git checkout"
alias gb="git branch"
command -v lazygit &>/dev/null && alias lg="lazygit"

# Aliases — nav
alias c="clear"
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias mkd="mkdir -p"

# Aliases — quick
alias reload="exec zsh"
alias path='echo $PATH | tr ":" "\n"'
alias ip="curl -s ifconfig.me"
alias ports="lsof -i -P -n | grep LISTEN"

# Theme
[ -f "$HOME/.config/zsh/theme.zsh" ] && source "$HOME/.config/zsh/theme.zsh"

# FZF
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Starship prompt
eval "$(starship init zsh)" 2>/dev/null

