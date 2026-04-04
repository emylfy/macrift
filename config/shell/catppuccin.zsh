# Catppuccin Mocha — shell colors

# fzf
export FZF_DEFAULT_OPTS=" \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--color=selected-bg:#45475a \
--color=border:#313244,label:#cdd6f4"

# bat
export BAT_THEME="Catppuccin Mocha"

# zsh-autosuggestions (overlay0)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6c7086"

# eza
export EZA_COLORS="\
di=1;34:\
ln=36:\
ex=1;32:\
fi=0:\
*.md=33:\
*.json=33:\
*.toml=33:\
*.yml=33:\
*.yaml=33:\
*.ts=34:\
*.js=33:\
*.py=32:\
*.rs=31:\
*.go=36:\
*.sh=32"

# fast-syntax-highlighting (applies after plugin loads via precmd hook)
_catppuccin_fsh() {
    [[ -z "${FAST_HIGHLIGHT_STYLES[*]+set}" ]] && return
    local t="${FAST_THEME_NAME}"

    # commands / builtins
    FAST_HIGHLIGHT_STYLES[${t}command]="fg=#89b4fa"            # blue
    FAST_HIGHLIGHT_STYLES[${t}builtin]="fg=#89b4fa"            # blue
    FAST_HIGHLIGHT_STYLES[${t}function]="fg=#89b4fa"           # blue
    FAST_HIGHLIGHT_STYLES[${t}alias]="fg=#a6e3a1"              # green
    FAST_HIGHLIGHT_STYLES[${t}precommand]="fg=#a6e3a1,italic"  # green (sudo, env)
    FAST_HIGHLIGHT_STYLES[${t}unknown-token]="fg=#f38ba8"      # red

    # arguments / paths
    FAST_HIGHLIGHT_STYLES[${t}path]="fg=#cdd6f4,underline"     # text
    FAST_HIGHLIGHT_STYLES[${t}path_pathseparator]="fg=#f5c2e7,underline" # pink
    FAST_HIGHLIGHT_STYLES[${t}globbing]="fg=#f5c2e7"           # pink
    FAST_HIGHLIGHT_STYLES[${t}single-hyphen-option]="fg=#f2cdcd"  # flamingo
    FAST_HIGHLIGHT_STYLES[${t}double-hyphen-option]="fg=#f2cdcd"  # flamingo

    # strings
    FAST_HIGHLIGHT_STYLES[${t}single-quoted-argument]="fg=#a6e3a1"  # green
    FAST_HIGHLIGHT_STYLES[${t}double-quoted-argument]="fg=#a6e3a1"  # green
    FAST_HIGHLIGHT_STYLES[${t}dollar-quoted-argument]="fg=#a6e3a1"  # green
    FAST_HIGHLIGHT_STYLES[${t}back-quoted-argument]="fg=#cba6f7"    # mauve

    # variables / numbers
    FAST_HIGHLIGHT_STYLES[${t}variable]="fg=#fab387"           # peach
    FAST_HIGHLIGHT_STYLES[${t}assign]="fg=#fab387"             # peach
    FAST_HIGHLIGHT_STYLES[${t}numeric]="fg=#fab387"            # peach

    # operators / separators
    FAST_HIGHLIGHT_STYLES[${t}commandseparator]="fg=#f5c2e7"   # pink (;, &&, ||)
    FAST_HIGHLIGHT_STYLES[${t}redirection]="fg=#f5c2e7"        # pink (>, <, >>)
    FAST_HIGHLIGHT_STYLES[${t}reserved-word]="fg=#cba6f7"      # mauve (if, then, for)
    FAST_HIGHLIGHT_STYLES[${t}comment]="fg=#6c7086"            # overlay0

    add-zsh-hook -d precmd _catppuccin_fsh
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _catppuccin_fsh
