# wallpaper-links

> Minimum-viable [macrift](https://github.com/emylfy/macrift) plugin — a one-screen "Quick-open wallpaper sources" menu.

This is the **smallest meaningful plugin** in the macrift ecosystem.
~30 lines of bash, no journaled state, no install steps — just `show_menu` +
`open`. Use it as a starting template for any "links / shortcuts" plugin:
fork it, replace the URLs and entry labels, ship.

## Install

Once `macrift plugin add` ships:

```sh
macrift plugin add github.com/emylfy/wallpaper-links
```

For now (symlink era):

```sh
mkdir -p ~/.macrift/plugins
ln -s "$(pwd)/vendor/wallpaper-links" ~/.macrift/plugins/wallpaper-links
```

The plugin registers under macrift's **Customize** section as
**`Wallpaper links`**.

## What it does

Opens curated wallpaper sources in the default browser:

- [Wallhaven](https://wallhaven.cc) — general
- [Catppuccin wallpapers](https://github.com/zhichaoh/catppuccin-wallpapers) — themed
- [Gruvbox wallpapers](https://github.com/AngelJumworworbo/gruvbox-wallpapers) — themed
- [Curated collection](https://raindrop.io/emalfai/wallpaper-69077386) — author's pick

No `defaults write`, no state, nothing to undo. The journal stays clean.

## What it shows plugin authors

- The minimum `plugin.json` (no `lifecycle`, no `macos_min` — both optional)
- A `menu.sh` that defines exactly one function (the one named in
  `menu.function`)
- Use of macrift's `show_menu`, `crumb_push`/`crumb_pop`, `log_ok`,
  `log_warn`
- Guarding `open` with `|| log_warn` so a missing URL scheme can't take
  the menu down under `set -e`

See macrift's [PLUGINS.md](https://github.com/emylfy/macrift/blob/main/PLUGINS.md)
for the full author contract.
