# Tokyo Night (Night) — shell colors

# fzf
export FZF_DEFAULT_OPTS=" \
--color=bg+:#292e42,bg:#1a1b26,spinner:#bb9af7,hl:#f7768e \
--color=fg:#c0caf5,header:#f7768e,info:#7aa2f7,pointer:#bb9af7 \
--color=marker:#9ece6a,fg+:#c0caf5,prompt:#7aa2f7,hl+:#f7768e \
--color=selected-bg:#283457 \
--color=border:#292e42,label:#c0caf5"

# bat — requires install (apply_tokyo_night downloads it)
export BAT_THEME="tokyonight_night"

# zsh-autosuggestions (comment color)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#565f89"

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
_tokyonight_fsh() {
    [[ -z "${FAST_HIGHLIGHT_STYLES[*]+set}" ]] && return
    local t="${FAST_THEME_NAME}"

    # commands / builtins
    FAST_HIGHLIGHT_STYLES[${t}command]="fg=#7aa2f7"            # blue
    FAST_HIGHLIGHT_STYLES[${t}builtin]="fg=#7aa2f7"            # blue
    FAST_HIGHLIGHT_STYLES[${t}function]="fg=#7aa2f7"           # blue
    FAST_HIGHLIGHT_STYLES[${t}alias]="fg=#9ece6a"              # green
    FAST_HIGHLIGHT_STYLES[${t}precommand]="fg=#9ece6a,italic"  # green
    FAST_HIGHLIGHT_STYLES[${t}unknown-token]="fg=#f7768e"      # red

    # arguments / paths
    FAST_HIGHLIGHT_STYLES[${t}path]="fg=#c0caf5,underline"
    FAST_HIGHLIGHT_STYLES[${t}path_pathseparator]="fg=#7dcfff,underline"  # cyan
    FAST_HIGHLIGHT_STYLES[${t}globbing]="fg=#7dcfff"           # cyan
    FAST_HIGHLIGHT_STYLES[${t}single-hyphen-option]="fg=#ff9e64"   # orange
    FAST_HIGHLIGHT_STYLES[${t}double-hyphen-option]="fg=#ff9e64"   # orange

    # strings
    FAST_HIGHLIGHT_STYLES[${t}single-quoted-argument]="fg=#9ece6a"   # green
    FAST_HIGHLIGHT_STYLES[${t}double-quoted-argument]="fg=#9ece6a"   # green
    FAST_HIGHLIGHT_STYLES[${t}dollar-quoted-argument]="fg=#9ece6a"   # green
    FAST_HIGHLIGHT_STYLES[${t}back-quoted-argument]="fg=#bb9af7"     # purple

    # variables / numbers
    FAST_HIGHLIGHT_STYLES[${t}variable]="fg=#ff9e64"           # orange
    FAST_HIGHLIGHT_STYLES[${t}assign]="fg=#ff9e64"             # orange
    FAST_HIGHLIGHT_STYLES[${t}numeric]="fg=#ff9e64"            # orange

    # operators / separators
    FAST_HIGHLIGHT_STYLES[${t}commandseparator]="fg=#7dcfff"   # cyan
    FAST_HIGHLIGHT_STYLES[${t}redirection]="fg=#7dcfff"        # cyan
    FAST_HIGHLIGHT_STYLES[${t}reserved-word]="fg=#bb9af7"      # purple
    FAST_HIGHLIGHT_STYLES[${t}comment]="fg=#565f89"            # comment

    add-zsh-hook -d precmd _tokyonight_fsh
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _tokyonight_fsh
