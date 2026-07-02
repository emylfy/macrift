#!/usr/bin/env python3
# macrift engine helpers — the JSON side of the journal/manifest engine.
# Each subcommand replaces a former bash heredoc; the wire formats (\x1f-joined
# rows, __CHANNEL__ markers, exit codes) are a contract with lib/engine.sh —
# keep them byte-identical.
import collections
import json
import os
import sys

# Join on US (\x1f), not tab: tab is IFS whitespace in bash and would
# collapse empty fields, shifting later columns.
SEP = "\x1f"


def iter_journal(path):
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except Exception:
            continue


def ident(d):
    # dotfile keys on dest; brew on name+source; plist on domain; command on
    # id (or run); the defaults family on (domain, key).
    k = d.get("kind")
    if k == "dotfile":
        return ("dotfile", d.get("dest"))
    if k == "brew":
        return ("brew", d.get("name"), d.get("source"))
    if k == "plist":
        return ("plist", d.get("domain"))
    if k == "command":
        return ("command", d.get("id") or d.get("run"))
    return (k, d.get("domain"), d.get("key"))


def label_of(d):
    k = d.get("kind")
    if k == "dotfile":
        return d.get("label") or os.path.basename(d.get("dest", "")) or d.get("dest", "")
    if k == "brew":
        return d.get("name", "")
    if k == "plist":
        return d.get("domain", "")
    if k == "command":
        return d.get("id") or d.get("run", "")[:24]
    return d.get("label", "") or d.get("key", "")


def emit_rows(entries):
    for d in entries:
        old = d.get("old")
        print(SEP.join([
            d.get("kind", ""), d.get("domain", ""), d.get("key", ""),
            d.get("type", ""), str(d.get("value", "")),
            "" if old is None else str(old),
            "1" if old is None else "0",
            label_of(d),
            d.get("dest", ""), d.get("src", ""),
            d.get("name", ""), d.get("source", ""), str(d.get("id", "")),
            d.get("undo") or "",
        ]))


# journal-latest <journal> — dedup to the latest entry per identity (drift).
def cmd_journal_latest(args):
    latest = collections.OrderedDict()
    for d in iter_journal(args[0]):
        latest[ident(d)] = d
    emit_rows(latest.values())


# journal-first <journal> <session> — first entry per identity in the session
# (= pre-session state, feeds undo).
def cmd_journal_first(args):
    target = args[1]
    first = collections.OrderedDict()
    for d in iter_journal(args[0]):
        if d.get("session") != target:
            continue
        k = ident(d)
        if k in first:
            continue
        first[k] = d
    emit_rows(first.values())


# journal-last-session <journal> — session id of the last recorded entry.
def cmd_journal_last_session(args):
    last = ""
    for d in iter_journal(args[0]):
        last = d.get("session", last)
    print(last)


def _sessions_agg(path, want_macos):
    agg = collections.OrderedDict()
    for d in iter_journal(path):
        s = d.get("session", "?")
        if s not in agg:
            agg[s] = {"n": 0, "ts": d.get("ts", "")}
            if want_macos:
                agg[s]["macos"] = d.get("macos", "")
        agg[s]["n"] += 1
    return agg


# journal-sessions <journal> — human list for `macrift undo list` (oldest first).
def cmd_journal_sessions(args):
    for s, v in _sessions_agg(args[0], True).items():
        print(f"    {s}   {v['n']:>3} changes   {v['ts']}   macOS {v['macos']}")


# journal-sessions-tsv <journal> — "sid\tlabel" for the snapshots menu (newest first).
def cmd_journal_sessions_tsv(args):
    for s, v in reversed(_sessions_agg(args[0], False).items()):
        ts = v["ts"].replace("T", " ").replace("Z", "")
        print(f"{s}\t{s}  ·  {v['n']} change(s)  ·  {ts}")


# manifest-parse <manifest> <os_ver> — desugar a manifest JSON into change-unit
# rows for manifest_apply_cli: audit rows first, then __DOTFILE__/__BREW__/
# __PLIST__/__COMMAND__ channels, then a __META__ trailer. Exit 2 on bad JSON.
def cmd_manifest_parse(args):
    TYPE_MAP = {"bool": "-bool", "int": "-int", "float": "-float", "string": "-string"}

    def os_major(v):
        try:
            return int(str(v).split(".")[0])
        except Exception:
            return None

    run_major = os_major(args[1]) if len(args) > 1 else None

    def nval(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        return str(v)

    def version_ok(u):
        if run_major is None:
            return True
        mn, mx = u.get("min_macos"), u.get("max_macos")
        if mn is not None and (m := os_major(mn)) is not None and run_major < m:
            return False
        if mx is not None and (m := os_major(mx)) is not None and run_major > m:
            return False
        return True

    try:
        with open(args[0]) as f:
            m = json.load(f)
    except Exception as e:
        sys.stderr.write("parse error: %s\n" % e)
        sys.exit(2)

    units = []
    skipped = [0]

    def add(kind, domain, key, vtype, value, label, unit=None):
        if unit is not None and not version_ok(unit):
            skipped[0] += 1
            return
        units.append((kind, domain, key, vtype, value, label))

    for d in m.get("defaults", []):
        add("default", d["domain"], d["key"],
            TYPE_MAP.get(d.get("type", "string"), "-string"),
            nval(d["value"]), d.get("label") or d.get("id") or d["key"], d)

    fin = m.get("finder", {})
    if "sort" in fin:
        add("finder_sort", "finder_sort", "sort", "", str(fin["sort"]), "Finder sort")
    if "hidden_files" in fin:
        add("default", "com.apple.finder", "AppleShowAllFiles", "-bool",
            nval(fin["hidden_files"]), "Show hidden files")

    boot = m.get("boot", {})
    if "startup_sound" in boot:
        add("nvram", "nvram", "StartupMute", "-bool", nval(boot["startup_sound"]), "Startup sound")

    lib = m.get("library", {})
    if "visible" in lib:
        add("chflags", "chflags", "nohidden", "-bool", nval(lib["visible"]), "Show Library folder")

    # dotfile units are file copies, not audit-table entries — emit on a separate
    # channel (__DOTFILE__ marker) and let the bash side route them to copy_config.
    dots = []
    for df in m.get("dotfile", []):
        if not version_ok(df):
            skipped[0] += 1
            continue
        src, dest = df.get("src", ""), df.get("dest", "")
        if not src or not dest:
            continue
        label = df.get("label") or df.get("id") or os.path.basename(dest) or dest
        dots.append(("__DOTFILE__", src, dest, str(df.get("mode") or ""), label))

    # brew units (formula/cask/mas) — installed outside the audit table, on their
    # own channel like dotfiles. Columns reused: domain=name, key=source, vtype=id.
    brews = []
    for b in m.get("brew", []):
        if not version_ok(b):
            skipped[0] += 1
            continue
        name = b.get("name", "")
        if not name:
            continue
        brews.append(("__BREW__", name, b.get("source", "formula"), str(b.get("id") or "")))

    # plist units (whole-domain defaults import) — opaque third-party domains, own
    # channel. Columns reused: domain=domain, key=file.
    plists = []
    for pl in m.get("plist", []):
        if not version_ok(pl):
            skipped[0] += 1
            continue
        dom, fil = pl.get("domain", ""), pl.get("file", "")
        if not dom or not fil:
            continue
        plists.append(("__PLIST__", dom, fil))

    # command units (arbitrary shell escape hatch) — own channel. Columns reused:
    # domain=id, key=run, vtype=undo, value=label.
    commands = []
    for c in m.get("command", []):
        if not version_ok(c):
            skipped[0] += 1
            continue
        run = c.get("run", "")
        if not run:
            continue
        cid = c.get("id", "") or ""
        commands.append(("__COMMAND__", cid, run, c.get("undo", "") or "", c.get("label") or cid or "command"))

    # Every kind is now applied; nothing is reported as unsupported.
    unsupported = []

    for row in units + dots + brews + plists + commands:
        print(SEP.join(row))
    print("__META__" + SEP + str(skipped[0]) + SEP + ",".join(unsupported))


# manifest-build <name> <ver> <osv> <entries> <brew> <dotfile> <plist> <command>
# — assemble a manifest JSON from capture temp files (any path may be ""/missing).
def cmd_manifest_build(args):
    name, ver, osv = args[0], args[1], args[2]
    entries_p, brew_p, dot_p, plist_p, cmd_p = args[3:8]
    TYPE = {"-bool": "bool", "-int": "int", "-float": "float", "-string": "string"}

    def conv(t, v):
        # Only bool becomes a JSON boolean; others keep the raw `defaults read`
        # string so a save→apply round-trip compares byte-identical.
        return (v == "true") if t == "-bool" else v

    def rows(p):
        if not p:
            return []
        try:
            return [l.rstrip("\n") for l in open(p) if l.strip()]
        except Exception:
            return []

    defaults, finder, boot, library = [], {}, {}, {}
    for line in rows(entries_p):
        p = line.split("|")
        if len(p) < 6:
            continue
        label, current, new_val, domain, key, vtype = p[:6]
        label = label.split("~", 1)[0]
        if label == "---" or current == "default":
            continue
        if domain == "finder_sort":
            finder["sort"] = current
        elif domain == "nvram" and key == "StartupMute":
            boot["startup_sound"] = (current == "true")
        elif domain == "chflags":
            library["visible"] = (current == "true")
        else:
            defaults.append({"label": label, "domain": domain, "key": key,
                             "type": TYPE.get(vtype, "string"), "value": conv(vtype, current)})

    brew = []
    for line in rows(brew_p):
        p = line.split("\t")
        if len(p) < 2 or not p[0]:
            continue
        e = {"name": p[0], "source": p[1]}
        if p[1] == "mas" and len(p) > 2 and p[2]:
            e["id"] = p[2]
        brew.append(e)

    dotfile = [{"src": p[0], "dest": p[1]}
               for p in (l.split("\t") for l in rows(dot_p)) if len(p) >= 2]
    plist = [{"domain": p[0], "file": p[1]}
             for p in (l.split("\t") for l in rows(plist_p)) if len(p) >= 2]

    command = []
    for line in rows(cmd_p):
        p = line.split("\t")
        if len(p) < 2:
            continue
        c = {"run": p[1]}
        if p[0]:
            c["id"] = p[0]
        if len(p) > 2 and p[2]:
            c["undo"] = p[2]
        if len(p) > 3 and p[3]:
            c["label"] = p[3]
        command.append(c)

    m = {"meta": {"name": name, "macrift": ver, "source_macos": osv}, "defaults": defaults}
    if finder:
        m["finder"] = finder
    if boot:
        m["boot"] = boot
    if library:
        m["library"] = library
    if brew:
        m["brew"] = brew
    if dotfile:
        m["dotfile"] = dotfile
    if plist:
        m["plist"] = plist
    if command:
        m["command"] = command
    print(json.dumps(m, indent=2))


# manifest-filter <manifest> <key>... — keep meta + the chosen top-level sections.
def cmd_manifest_filter(args):
    m = json.load(open(args[0]))
    keep = set(args[1:])
    out = {"meta": m.get("meta", {})}
    for k in keep:
        if k in m:
            out[k] = m[k]
    print(json.dumps(out, indent=2))


# changelog — GitHub compare/commits JSON on stdin → "- subject" lines plus
# "M: action" for Manual-Action trailers. Exit 1 on anything unexpected.
def cmd_changelog(args):
    def emit(commits):
        for c in commits:
            msg = c["commit"]["message"]
            lines = msg.splitlines()
            print("- " + lines[0])
            for line in lines[1:]:
                if line.startswith("Manual-Action:"):
                    action = line.split(":", 1)[1].strip()
                    if action:
                        print("M: " + action)

    try:
        d = json.load(sys.stdin)
        if isinstance(d, dict):
            if "commits" not in d:
                sys.exit(1)
            emit(d["commits"])
        else:
            emit(d)
    except Exception:
        sys.exit(1)


COMMANDS = {
    "journal-latest": cmd_journal_latest,
    "journal-first": cmd_journal_first,
    "journal-last-session": cmd_journal_last_session,
    "journal-sessions": cmd_journal_sessions,
    "journal-sessions-tsv": cmd_journal_sessions_tsv,
    "manifest-parse": cmd_manifest_parse,
    "manifest-build": cmd_manifest_build,
    "manifest-filter": cmd_manifest_filter,
    "changelog": cmd_changelog,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.stderr.write("usage: engine.py <%s> [args]\n" % "|".join(COMMANDS))
        sys.exit(2)
    COMMANDS[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
