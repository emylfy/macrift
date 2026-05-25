# macrift manifest & journal — spec (draft)

Status: design draft. No code yet. This describes the data model that would let
macrift reproduce a setup (`apply`), roll it back (`undo`), and detect drift —
all on top of the existing audit/apply engine in `common.sh`.

## Why this exists

macrift today is interactive-only: you click through menus, apply tweaks, and
nothing records what you chose. There is no way to re-apply a setup on a fresh
Mac, undo a whole session, or see what drifted from default.

The three missing features — reproducibility, undo/drift, restore-with-preview —
are all projections of one missing thing: a **persistent record of one "unit of
change."** Design that union once and the three features collapse onto a single
code path.

## Three surfaces, one model

| Surface | Format | Audience | Has `old`? |
| :------ | :----- | :------- | :--------- |
| **Manifest** | JSON | hand-edited / machine-written, committed to a repo | no (desired state) |
| **Journal** | JSONL | machine-written/read, append-only | yes (for undo) |
| **Change-unit** | in-memory | internal — what the engine actually executes | n/a |

The manifest is a friendly *surface* that desugars into change-units. The journal
is a change-unit plus what-was-there-before plus metadata. Both speak the same
union.

## The change-unit union

Discriminated on `kind`. This is the canonical thing — `apply`, `undo`, and
`restore` all build a list of these and run it through the existing
`show_audit_table` (common.sh:1027) and `apply_audited_defaults` (common.sh:1117).

### Common fields (any kind)

| Field | Required | Notes |
| :---- | :------- | :---- |
| `kind` | yes | one of: `default` `finder_sort` `nvram` `chflags` `brew` `dotfile` `plist` `command` |
| `id` | recommended | stable slug, e.g. `dock.autohide`. New concept — today tweaks are keyed only by `label`. Lets manifest, journal, and drift reference the same logical change even if the label is reworded. |
| `label` | optional | human text shown in the audit table (existing behavior). Defaults to `key`/`name`/`id`. |
| `min_macos` / `max_macos` | optional | version guard. Unit is skipped (status `skipped`, reason `version`) if the running macOS is out of range. Closes the "key valid on Sonoma, no-op on Tahoe" gap. |

### Per-kind fields

#### `kind: default`
The common case — a single `defaults write`.

| Field | Required | Notes |
| :---- | :------- | :---- |
| `domain` | yes | e.g. `com.apple.dock` |
| `key` | yes | e.g. `autohide` |
| `type` | yes | `bool` `int` `float` `string`. Maps to the `defaults write` flag by prefixing `-` (`bool` → `-bool`). |
| `value` | yes | typed value. Bools normalize to `true`/`false` (the engine maps `defaults read`'s 1/0 in `audit_default`, common.sh:1007). |
| `sudo` | optional | `true` forces sudo. Even without it, `_defaults_cmd` (common.sh:1089) auto-retries with sudo on a permission failure, so this is a hint, not a hard requirement. |

Arrays/dicts (e.g. hot corners) are **not** covered by `kind: default` — the
current `audit_default` takes a single scalar. Use `kind: plist` for now; a
future `kind: defaults_array` can be added if needed.

#### `kind: finder_sort`
Pseudo-domain. Writes the same sort criterion across all four Finder view
subdicts via PlistBuddy (`_finder_sort_write`, common.sh:1199).

| Field | Required | Notes |
| :---- | :------- | :---- |
| `value` | yes | `name` `kind` `dateModified` `dateCreated` `size` etc. |

`old` capture: read one subdict (`FK_StandardViewSettings:ExtendedListViewSettingsV2:sortColumn`)
via PlistBuddy; default to `name` if unset (matches the existing reset path).

#### `kind: nvram`
Raw NVRAM byte (e.g. `StartupMute`).

| Field | Required | Notes |
| :---- | :------- | :---- |
| `key` | yes | e.g. `StartupMute` |
| `value` | yes | bool. **Engine mapping (common.sh:1148):** `value=true → %00` (sound on), `value=false → %01` (muted). Friendly surface key is `boot.startup_sound` (decided — see Decisions made). |

#### `kind: chflags`
Currently only `~/Library` visibility.

| Field | Required | Notes |
| :---- | :------- | :---- |
| `value` | yes | bool. `true` → `nohidden` (visible), `false` → `hidden` (common.sh:1133). |
| `path` | optional | defaults to `~/Library`. |

#### `kind: brew`
A single package (the manifest can carry many).

| Field | Required | Notes |
| :---- | :------- | :---- |
| `name` | yes | formula/cask name, or app name for `mas` |
| `source` | yes | `formula` `cask` `mas` |
| `id` | required for `mas` | App Store numeric id |

#### `kind: dotfile`
File copy with backup (`copy_config` → `backup_file`, common.sh:1279).

| Field | Required | Notes |
| :---- | :------- | :---- |
| `src` | yes | path relative to the manifest/profile directory |
| `dest` | yes | absolute, `~` allowed |
| `mode` | optional | chmod after copy, e.g. `600` for `~/.ssh/config` |

#### `kind: plist`
Whole-domain `defaults import` — coarse, no per-key diff possible (iTerm2 etc.).

| Field | Required | Notes |
| :---- | :------- | :---- |
| `domain` | yes | e.g. `com.googlecode.iterm2` |
| `file` | yes | exported plist, relative to manifest dir |

In the audit table this renders as a single honest line —
`replace domain com.googlecode.iterm2 (~340 keys) — wholesale` — with a warning,
**not** silently and not pretending to be a key-level diff (the current
`_profile_import` defect).

#### `kind: command`
Escape hatch for user-defined tweaks (`~/.config/macrift/custom.sh` territory).

| Field | Required | Notes |
| :---- | :------- | :---- |
| `run` | yes | shell to execute |
| `undo` | optional | inverse shell. Without it the unit is **not reversible** — `undo`/`drift` mark it accordingly. |

## Journal — JSONL

Path: `~/.macrift/state/journal.jsonl`. Append-only, one JSON object per line.
JSONL because records are heterogeneous (fields vary by `kind`) — a fixed-column
TSV breaks down here, and python3 is already a dependency
(`customize/launchpad_sort.py`, the changelog parser in `common.sh`).

A journal entry = change-unit + capture/metadata fields:

| Field | Notes |
| :---- | :---- |
| `session` | groups one run, for `undo --session` |
| `ts` | ISO 8601 UTC |
| `macos` | running macOS version at apply time |
| `status` | `applied` `failed` `skipped` |
| `old` | prior state — the whole point of undo (semantics below) |

### `old` semantics per kind

| kind | `old` holds | undo action |
| :--- | :---------- | :---------- |
| `default` | prior value, or `null` if the key was unset | write `old`, or `delete` if `null` |
| `finder_sort` | prior criterion (or `name`) | re-write via `_finder_sort_write` |
| `nvram` | prior raw byte (`%00`/`%01`) | `sudo nvram key=<old>` |
| `chflags` | prior bool | `chflags` back |
| `dotfile` | path to the `.bak` (or `null` if dest didn't exist) | restore `.bak`, or remove dest |
| `plist` | path to a pre-import backup export | re-import backup |
| `brew` | `installed` / `absent` | uninstall only if `absent` before **and** not a dependency (see caution) |
| `command` | n/a | run `undo` if present, else mark irreversible |

Example:

```jsonl
{"session":"2605-a1b2","ts":"2026-05-25T14:03:11Z","macos":"26.1","status":"applied","kind":"default","id":"dock.autohide","domain":"com.apple.dock","key":"autohide","type":"bool","value":"true","old":"false"}
{"session":"2605-a1b2","ts":"2026-05-25T14:03:11Z","macos":"26.1","status":"applied","kind":"default","id":"finder.hidden_files","domain":"com.apple.finder","key":"AppleShowAllFiles","type":"bool","value":"true","old":null}
{"session":"2605-a1b2","ts":"2026-05-25T14:03:12Z","macos":"26.1","status":"applied","kind":"nvram","id":"boot.sound","key":"StartupMute","value":"true","old":"%01"}
{"session":"2605-a1b2","ts":"2026-05-25T14:03:12Z","macos":"26.1","status":"applied","kind":"dotfile","id":"git.config","src":"dotfiles/.gitconfig","dest":"~/.gitconfig","old":"~/.gitconfig.bak"}
{"session":"2605-a1b2","ts":"2026-05-25T14:03:13Z","macos":"26.1","status":"failed","kind":"brew","id":"pkg.ripgrep","name":"ripgrep","source":"formula","old":"absent"}
```

## Manifest — JSON

Path (default): `~/.config/macrift/macrift.json`. Hand-editable, no `old`/`ts`.

**Why JSON, not TOML** (the spec originally proposed TOML): the only python on a
stock Mac is `/usr/bin/python3` 3.9, which has no `tomllib` (3.11+) and no
`tomli`, and the project forbids new runtime deps. JSON parses with the stdlib
`json` module everywhere. The manifest's primary producer is `save_profile`
(machine-written), so the loss of comments matters less than zero-dep
robustness. The friendly sections still desugar to the change-unit union at
load — surface and internal model stay deliberately different.

```json
{
  "meta": {
    "name": "stone-mbp",
    "created": "2026-05-25",
    "macrift": "26.05.3",
    "source_host": "Stones-MacBook-Pro",
    "source_macos": "26.1"
  },

  "defaults": [
    { "id": "dock.autohide", "domain": "com.apple.dock",
      "key": "autohide", "type": "bool", "value": true },
    { "id": "screenshots.location", "domain": "com.apple.screencapture",
      "key": "location", "type": "string",
      "value": "~/Pictures/Screenshots", "min_macos": "13" }
  ],

  "finder":  { "sort": "kind", "hidden_files": true },
  "boot":    { "startup_sound": true },
  "library": { "visible": true },

  "brew": [
    { "name": "ripgrep", "source": "formula" },
    { "name": "raycast", "source": "cask" },
    { "name": "Things",  "source": "mas", "id": "904280696" }
  ],

  "dotfile": [
    { "src": "dotfiles/.gitconfig", "dest": "~/.gitconfig" },
    { "src": "dotfiles/.ssh/config", "dest": "~/.ssh/config", "mode": "600" }
  ],

  "plist": [
    { "domain": "com.googlecode.iterm2", "file": "iterm2.plist" }
  ],

  "command": [
    { "id": "custom.no_ext_change_warning",
      "run":  "defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false",
      "undo": "defaults delete com.apple.finder FXEnableExtensionChangeWarning" }
  ]
}
```

### Desugaring rules (surface → union)

| Manifest surface | Change-unit | In `apply` v1? |
| :--------------- | :---------- | :------------- |
| `defaults[]` element | `kind=default` (1:1) | yes |
| `finder.sort` | `kind=finder_sort` | yes |
| `finder.hidden_files` | `kind=default` com.apple.finder AppleShowAllFiles | yes |
| `boot.startup_sound` | `kind=nvram` StartupMute | yes |
| `library.visible` | `kind=chflags` ~/Library | yes |
| `brew[]`, `dotfile[]`, `plist[]`, `command[]` | matching kind | no — reported as "not yet applied" |

Sugar covers only the handful of well-known pseudo-domains. Anything else goes
through explicit `defaults[]` elements — no magic.

**Implemented:** `manifest_apply_cli` (common.sh) parses the JSON via a stdlib
`json` heredoc, desugars the defaults family into `AUDIT_ENTRIES` (reading live
current via `_journal_live_value`), previews through `show_audit_table`, and
applies via `apply_audited_defaults` — so every applied change is journaled for
free. `min_macos`/`max_macos` are enforced (major-version compare). brew/dotfile/
plist/command are counted and reported, not applied.

## How it flows through the existing engine

The payoff: restore-with-preview is nearly free because the diff already exists.

1. **Build** — `apply`, `restore`, and the interactive wizard each produce a list
   of change-units (from a JSON file, a saved profile, or the menu).
2. **Diff** — feed them through `show_audit_table` (common.sh:1027). It already
   does per-key `old → value` comparison, `(no change)` detection, and red/green
   rendering. `restore` stops *bypassing* this diff (its current defect) instead
   of needing a new one.
3. **Apply** — `apply_audited_defaults` (common.sh:1117) already routes by domain
   (`finder_sort`, `nvram`, `chflags`, plain defaults). Extend it to `dotfile` /
   `plist` / `brew` / `command`, and append each result to `journal.jsonl`.
4. **Undo / drift** — read the journal back. No new diff logic.

One union, three features, mostly reusing code that already ships.

## Commands enabled

| Command | Behavior | Status |
| :------ | :------- | :----- |
| `macrift apply [<file.json>]` | load manifest → desugar → audit table → apply → journal. Honors `--dry-run` / `--no-confirm`. | done (defaults family) |
| `macrift undo [<session>\|list]` | read the session in reverse, invert each unit via `old`. Default: last session. `list` shows sessions. (Positional, not `--flags`: the global flag parser drops unknown `--flags`.) | done (defaults family) |
| `macrift drift` | for each journaled unit, compare current system value to `value`; report held / drifted / reverted / unknown. | done |
| profile `save` | emit a JSON manifest with `meta` populated + the referenced files (dotfiles, plists). | todo |
| profile `restore` | load that manifest exactly like `apply` — through the audit table. | todo |

## Edge cases & cautions

- **bool normalization** — `defaults read` returns `1`/`0`; `audit_default`
  already maps to `true`/`false`. Journal and manifest store `true`/`false`.
- **sudo domains** — `sudo` is a hint; `_defaults_cmd` auto-retries with sudo on
  failure and warns. Manifest `sudo = true` just front-loads the prompt.
- **dotfile backups** — `backup_file` uses `cp -n`, keeping the *first* `.bak`
  across repeated runs. So `old` may point at a backup from an earlier session;
  document that undo restores the earliest captured state.
- **brew undo is dangerous** — uninstalling can break dependents. Undo of a
  `brew` unit should be opt-in and skip anything that's now a dependency. Default
  to *not* uninstalling.
- **plist is coarse by nature** — `defaults import` replaces the whole domain.
  Surface it as a single wholesale line with a warning; never silently.
- **version guard** — units out of `[min_macos, max_macos]` are recorded as
  `skipped`/`version`, not applied.

## Decisions made

- **Format: JSON, not TOML** — system python 3.9 has no `tomllib`; no new deps allowed.
- **nvram polarity** — friendly key is `boot.startup_sound` (`value=true` → sound on
  → `%00`), matching the engine's existing mapping. No `mute` (would invert).
- **Manifest location** — `macrift apply <path>` positional arg; default
  `~/.config/macrift/macrift.json`. (Global flag parser drops unknown `--flags`,
  so subcommand options must be positional.)

## Open questions

1. **`id` namespace — deferred (YAGNI).** A dotted convention (`dock.autohide`)
   was considered, but journal/manifest/drift already key on `domain`/`key`/`dest`
   and nothing consumes a slug yet. `id` stays empty (`label` is the human ref)
   until a concrete need appears (e.g. a key renamed across macOS versions).
2. **Journal rotation.** Append-only grows forever. Cap by size or session count?
3. **Custom tweaks loading.** Does `kind: command` fully cover
   `~/.config/macrift/custom.sh`, or should custom units be sourced separately
   and merged into the manifest model?
4. **apply for brew/dotfile/plist/command.** v1 reports these as not-applied;
   they need handling outside the audit-table path (brew install, file copy,
   wholesale plist import with a coarse warning).
