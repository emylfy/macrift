#!/usr/bin/env bash
# macrift — version check + self-update

# true if $1 is a strictly newer dotted calver (YY.MM.N) than $2.
# Component-wise numeric compare; 10# forces base-10 so "05" isn't read as octal.
_macrift_version_gt() {
    [[ "$1" == "$2" ]] && return 1
    local IFS=. i x y
    # shellcheck disable=SC2206  # intentional split on IFS='.' into version components
    local -a a=($1) b=($2)
    for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
        x=${a[i]:-0}
        y=${b[i]:-0}
        x=${x//[^0-9]/}
        y=${y//[^0-9]/}
        ((10#${x:-0} > 10#${y:-0})) && return 0
        ((10#${x:-0} < 10#${y:-0})) && return 1
    done
    return 1
}

# True when this checkout was installed by Homebrew (lives under the brew Cellar/
# opt prefix). Brew owns updates for these, so self-update + the version nag defer
# to `brew upgrade`. Path-only check — no `brew` subprocess, works even off-PATH.
_macrift_is_brew() {
    [[ "$MACRIFT_DIR" == */Cellar/macrift/* || "$MACRIFT_DIR" == */opt/macrift/* ]]
}

# Resolve the latest published release, download its checksummed tarball, verify
# the sha256, and extract into $1 (yielding $1/macrift). Pinned + verified — never
# floating `main`; fails loud. Mirrors install.sh's fetch (which runs before this
# file exists, so it can't be shared).
_macrift_fetch_release() {
    local dest="$1" url tag ver fname asset_url
    url=$(curl -fsSL -I -o /dev/null -w '%{url_effective}' \
        "https://github.com/$MACRIFT_REPO/releases/latest" 2>/dev/null) || true
    tag="${url##*/}"
    if [[ -z "$tag" || "$tag" == "latest" ]]; then
        log_err "Could not resolve a published release"
        return 1
    fi
    ver="${tag#v}"
    fname="macrift-$ver.tar.gz"
    asset_url="https://github.com/$MACRIFT_REPO/releases/download/$tag/$fname"
    if ! curl -fsSL -o "$dest/$fname" "$asset_url"; then
        log_err "Download failed — release asset missing or no connection"
        return 1
    fi
    if ! curl -fsSL -o "$dest/$fname.sha256" "$asset_url.sha256"; then
        log_err "No checksum published for $tag — refusing to update unverified"
        return 1
    fi
    if ! ( cd "$dest" && shasum -a 256 -c "$fname.sha256" ) >/dev/null 2>&1; then
        log_err "Checksum mismatch — refusing to update"
        return 1
    fi
    if ! tar -xzf "$dest/$fname" -C "$dest" || [[ ! -d "$dest/macrift" ]]; then
        log_err "Extract failed or unexpected archive layout"
        return 1
    fi
}

# Check for updates (2s timeout, silent on failure)
check_update() {
    [[ "${MACRIFT_NO_UPDATE:-}" == true ]] && return 0
    _macrift_is_brew && return 0
    local remote
    remote=$(curl -fsSL --connect-timeout 2 --max-time 2 "$MACRIFT_VERSION_URL" 2>/dev/null) || return 0
    # Only offer an update when remote is strictly NEWER — never a downgrade
    # (during development the local VERSION is ahead of main's).
    if [[ -n "$remote" ]] && _macrift_version_gt "$remote" "$MACRIFT_VERSION"; then
        MACRIFT_UPDATE="$remote"
    fi
}

# Fetch changelog for the pending update.
# Prefers GitHub compare API (precise, tag-based); falls back to recent commits.
_fetch_update_changelog() {
    local current_tag="v$MACRIFT_VERSION"
    local commits

    # Precise path: requires `v<VERSION>` tag pushed for the current release
    commits=$(curl -fsSL --max-time 5 \
        "https://api.github.com/repos/${MACRIFT_REPO}/compare/${current_tag}...main" 2>/dev/null \
        | python3 "$MACRIFT_DIR/lib/engine.py" changelog 2>/dev/null)

    if [[ -n "$commits" ]]; then
        printf '%s\n' "$commits"
        return 0
    fi

    # Fallback: last 10 commits (may include ones the user already has)
    commits=$(curl -fsSL --max-time 5 \
        "https://api.github.com/repos/${MACRIFT_REPO}/commits?per_page=10" 2>/dev/null \
        | python3 "$MACRIFT_DIR/lib/engine.py" changelog 2>/dev/null)
    [[ -n "$commits" ]] && printf '%s\n' "$commits"
    return 1   # signals 'imprecise' (caller may note this)
}

# Download and apply update
macrift_update() {
    # Refuse to clobber a git checkout. The atomic swap below rm -rf's the install
    # dir, which would destroy .git, uncommitted work, and untracked files. If you
    # run macrift from a clone, update with git, not this command.
    if [[ -e "$MACRIFT_DIR/.git" ]]; then
        log_err "Refusing to update: $MACRIFT_DIR is a git checkout."
        log_info "Update with git instead:  git -C \"$MACRIFT_DIR\" pull --ff-only"
        return 1
    fi

    # Homebrew owns updates for brew installs — defer to it.
    if _macrift_is_brew; then
        log_info "Installed via Homebrew — update with:  brew upgrade macrift"
        return 1
    fi

    # Show changelog first, then ask
    if [[ -n "$MACRIFT_UPDATE" ]]; then
        printf '\n'
        log_info "Update available: $MACRIFT_VERSION → $MACRIFT_UPDATE"
        printf '\n'
        local changelog precise=0
        if changelog=$(_fetch_update_changelog); then
            precise=1
        fi
        if [[ -n "$changelog" ]]; then
            local manual_actions log_lines
            manual_actions=$(printf '%s\n' "$changelog" | sed -n 's/^M: //p')
            log_lines=$(printf '%s\n' "$changelog" | grep '^- ' || true)

            if [[ -n "$manual_actions" ]]; then
                log_warn "Manual action required:"
                printf '%s\n' "$manual_actions" | while IFS= read -r line; do
                    printf '  %b%s%b\n' "$YELLOW" "$line" "$RESET"
                done
                printf '\n'
            fi

            if [[ $precise -eq 1 ]]; then
                log_info "Changes since v$MACRIFT_VERSION:"
            else
                log_info "Recent commits (no tag for current version — may include ones you have):"
            fi
            printf '%s\n' "$log_lines" | while IFS= read -r line; do
                printf '  %b%s%b\n' "$DIM" "$line" "$RESET"
            done
            printf '\n'
        fi
        if ! confirm "Continue with update?" "y"; then
            return 1
        fi
    fi

    log_info "Downloading latest release..."
    local tmp
    tmp="$(mktemp -d)"
    # Pinned + sha256-verified release tarball (never floating main). The helper
    # logs the specific failure; here we just clean up and report.
    if _macrift_fetch_release "$tmp"; then
        # Atomic swap: backup old → move new → remove backup.
        # Clear any stale .bak from a prior interrupted run first, or the backup
        # mv would nest the install inside it and the restore path would be wrong.
        rm -rf "$MACRIFT_DIR.bak"
        mv "$MACRIFT_DIR" "$MACRIFT_DIR.bak"
        if mv "$tmp/macrift" "$MACRIFT_DIR"; then
            # User data (undo journal, plugins, logs) lives inside ~/.macrift
            # for curl installs — move it into the new tree instead of deleting
            # it with the backup. Release tarballs never ship these paths.
            local _keep
            for _keep in state plugins plugins.lock.json macrift.log; do
                if [[ -e "$MACRIFT_DIR.bak/$_keep" && ! -e "$MACRIFT_DIR/$_keep" ]]; then
                    mv "$MACRIFT_DIR.bak/$_keep" "$MACRIFT_DIR/$_keep"
                fi
            done
            chmod +x "$MACRIFT_DIR/macrift.sh"
            find "$MACRIFT_DIR" -name "*.sh" -exec chmod +x {} +
            rm -rf "$MACRIFT_DIR.bak"
            log_ok "Updated to $(cat "$MACRIFT_DIR/VERSION" 2>/dev/null || echo 'latest')"
        else
            log_err "Failed to replace install directory"
            mv "$MACRIFT_DIR.bak" "$MACRIFT_DIR"
            rm -rf "$tmp"
            return 1
        fi
    else
        # Don't fall through to `return 0` — the caller treats success as "update
        # applied" and re-execs, so a failed download must report failure.
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    return 0
}
