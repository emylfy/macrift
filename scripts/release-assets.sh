#!/usr/bin/env bash
# Finalize a macrift release: build a checksummed tarball asset, attach it to the
# GitHub Release, and bump the Homebrew formula in the tap.
#
# This runs ON TOP of the existing release flow (.githooks/publish bumps VERSION
# and pushes; .githooks/pre-push tags v<VERSION>, pushes the tag, and creates the
# GitHub Release). pre-push calls this right after creating the release; it is
# also runnable by hand to (re)finalize a tag:
#
#   bash scripts/release-assets.sh v26.07            # build + upload + bump formula
#   bash scripts/release-assets.sh --dry-run v26.07  # print actions, change nothing
#
# The formula bump needs a local checkout of the tap (emylfy/homebrew-macrift)
# at $MACRIFT_TAP_DIR (default: ../homebrew-macrift next to this repo). If it's
# absent the asset still ships and the formula step is skipped with a notice.

set -euo pipefail

# The pre-push hook exports an absolute GIT_DIR (notably under git worktrees),
# and environment beats `git -C`: every git call below — including the
# `git -C "$TAP_DIR"` ones — would silently operate on THIS repo and push the
# formula commit to macrift's main instead of the tap. Rediscover from cwd.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

DRY=false
TAG=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=true ;;
        v*)        TAG="$arg" ;;
        *)         printf 'release-assets: unknown arg: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

if [[ -z "$TAG" ]]; then
    printf 'usage: release-assets.sh [--dry-run] v<version>\n' >&2
    exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
VER="${TAG#v}"
TMPL="$REPO_ROOT/packaging/homebrew/macrift.rb.tmpl"
DIST="$REPO_ROOT/dist"
ASSET="$DIST/macrift-$VER.tar.gz"
SUMFILE="macrift-$VER.tar.gz.sha256"
TAP_DIR="${MACRIFT_TAP_DIR:-$REPO_ROOT/../homebrew-macrift}"
ASSET_URL="https://github.com/emylfy/macrift/releases/download/$TAG/macrift-$VER.tar.gz"

run() {
    if $DRY; then
        printf '  [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    printf 'release-assets: tag %s does not exist — run publish first\n' "$TAG" >&2
    exit 1
fi

# Build the asset from the tag (reproducible; stable macrift/ top dir for the
# installer/self-update, independent of version).
printf 'release-assets: building %s from %s\n' "macrift-$VER.tar.gz" "$TAG"
run mkdir -p "$DIST"
run git archive --format=tar.gz --prefix=macrift/ -o "$ASSET" "$TAG"

# Checksum file references the bare basename so `shasum -c` works from the
# download dir (install.sh / self-update verify against this).
printf 'release-assets: writing %s\n' "$SUMFILE"
if $DRY; then
    printf '  [dry-run] (cd %s && shasum -a 256 macrift-%s.tar.gz > %s)\n' "$DIST" "$VER" "$SUMFILE"
    SHA="<computed-at-release>"
else
    ( cd "$DIST" && shasum -a 256 "macrift-$VER.tar.gz" > "$SUMFILE" )
    SHA="$(awk '{print $1}' "$DIST/$SUMFILE")"
    printf 'release-assets: sha256 %s\n' "$SHA"
fi

# Attach both to the release (idempotent: --clobber replaces a prior upload).
printf 'release-assets: uploading assets to release %s\n' "$TAG"
run gh release upload "$TAG" "$ASSET" "$DIST/$SUMFILE" --clobber

# Bump the Homebrew formula in the tap (optional).
if [[ ! -f "$TMPL" ]]; then
    printf 'release-assets: %s missing — cannot render formula, skipping\n' "$TMPL" >&2
elif [[ ! -d "$TAP_DIR/.git" ]]; then
    printf 'release-assets: tap not found at %s — skipping formula bump\n' "$TAP_DIR" >&2
    printf '  (set MACRIFT_TAP_DIR or clone emylfy/homebrew-macrift there)\n' >&2
else
    printf 'release-assets: bumping formula in %s\n' "$TAP_DIR"
    run mkdir -p "$TAP_DIR/Formula"
    if $DRY; then
        printf '  [dry-run] render %s -> %s (url=%s sha256=%s)\n' \
            "$TMPL" "$TAP_DIR/Formula/macrift.rb" "$ASSET_URL" "$SHA"
    else
        sed -e "s|@URL@|$ASSET_URL|" -e "s|@SHA256@|$SHA|" "$TMPL" \
            > "$TAP_DIR/Formula/macrift.rb"
    fi
    run git -C "$TAP_DIR" add Formula/macrift.rb
    run git -C "$TAP_DIR" commit -q -m "macrift $VER"
    run git -C "$TAP_DIR" push
fi

printf 'release-assets: done (%s)\n' "$TAG"
