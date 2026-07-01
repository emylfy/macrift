#!/usr/bin/env python3
"""Launchpad: create category folders from third-party apps.
Called by macrift/customize/launchpad.sh — not standalone."""

import subprocess
import sqlite3
import shutil
import os
import uuid
import sys
from collections import Counter, defaultdict

CATEGORY_OVERRIDES = {
    "dev.zed.Zed": "Developer Tools",
    "com.rogueamoeba.soundsource": "Utilities",
    "com.crystalidea.macsfancontrol": "Utilities",
    "com.image-line.fl-cloud-plugins": "Media",
    "com.image-line.flstudio": "Media",
    "com.anthropic.claude-code-url-handler": "Developer Tools",
    "com.logi.pluginservice": "Utilities",
}

CATEGORY_ALIASES = {
    "Music": "Media",
    "Video": "Media",
    "Photo & Video": "Media",
    "Entertainment": "Media",
}

MIN_CATEGORY_SIZE = 2

TRIGGERS_SQL = """
CREATE TRIGGER update_items_order BEFORE UPDATE OF ordering ON items WHEN new.ordering > old.ordering AND 0 == (SELECT value FROM dbinfo WHERE key='ignore_items_update_triggers')
BEGIN
    UPDATE dbinfo SET value=1 WHERE key='ignore_items_update_triggers';
    UPDATE items SET ordering = ordering - 1 WHERE parent_id = old.parent_id AND ordering BETWEEN old.ordering and new.ordering;
    UPDATE dbinfo SET value=0 WHERE key='ignore_items_update_triggers';
END;
CREATE TRIGGER update_items_order_backwards BEFORE UPDATE OF ordering ON items WHEN new.ordering < old.ordering AND 0 == (SELECT value FROM dbinfo WHERE key='ignore_items_update_triggers')
BEGIN
    UPDATE dbinfo SET value=1 WHERE key='ignore_items_update_triggers';
    UPDATE items SET ordering = ordering + 1 WHERE parent_id = old.parent_id AND ordering BETWEEN new.ordering and old.ordering;
    UPDATE dbinfo SET value=0 WHERE key='ignore_items_update_triggers';
END;
CREATE TRIGGER update_item_parent AFTER UPDATE OF parent_id ON items WHEN 0 == (SELECT value FROM dbinfo WHERE key='ignore_items_update_triggers')
BEGIN
    UPDATE dbinfo SET value=1 WHERE key='ignore_items_update_triggers';
    UPDATE items SET ordering = (SELECT ifnull(MAX(ordering),0)+1 FROM items WHERE parent_id=new.parent_id AND ROWID!=old.rowid) WHERE ROWID=old.rowid;
    UPDATE items SET ordering = ordering - 1 WHERE parent_id = old.parent_id and ordering > old.ordering;
    UPDATE dbinfo SET value=0 WHERE key='ignore_items_update_triggers';
END;
CREATE TRIGGER insert_item AFTER INSERT on items WHEN 0 == (SELECT value FROM dbinfo WHERE key='ignore_items_update_triggers')
BEGIN
    UPDATE dbinfo SET value=1 WHERE key='ignore_items_update_triggers';
    UPDATE items SET ordering = (SELECT ifnull(MAX(ordering),0)+1 FROM items WHERE parent_id=new.parent_id) WHERE ROWID=new.rowid;
    UPDATE dbinfo SET value=0 WHERE key='ignore_items_update_triggers';
END;
CREATE TRIGGER app_inserted AFTER INSERT ON items WHEN new.type = 4 OR new.type = 5
BEGIN
    INSERT INTO image_cache VALUES (new.rowid,0,0,NULL,NULL);
END;
CREATE TRIGGER app_deleted AFTER DELETE ON items WHEN old.type = 4 OR old.type = 5
BEGIN
    DELETE FROM image_cache WHERE item_id=old.rowid;
END;
CREATE TRIGGER item_deleted AFTER DELETE ON items
BEGIN
    DELETE FROM apps WHERE rowid=old.rowid;
    DELETE FROM groups WHERE item_id=old.rowid;
    DELETE FROM downloading_apps WHERE item_id=old.rowid;
    UPDATE dbinfo SET value=1 WHERE key='ignore_items_update_triggers';
    UPDATE items SET ordering = ordering - 1 WHERE old.parent_id = parent_id AND ordering > old.ordering;
    UPDATE dbinfo SET value=0 WHERE key='ignore_items_update_triggers';
END;
"""

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()

def build_category_map():
    result = {}
    for entry in os.scandir("/Applications"):
        if entry.name.endswith(".app") and entry.is_dir(follow_symlinks=True):
            bid = run(["mdls", "-name", "kMDItemCFBundleIdentifier", "-raw", entry.path])
            if not bid or bid == "(null)":
                continue
            if bid in CATEGORY_OVERRIDES:
                result[bid] = CATEGORY_OVERRIDES[bid]
            else:
                cat = run(["mdls", "-name", "kMDItemAppStoreCategory", "-raw", entry.path])
                if cat and cat != "(null)":
                    result[bid] = CATEGORY_ALIASES.get(cat, cat)
    return result

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "apply"
    selected_cats = set(sys.argv[2:]) if mode == "apply" and len(sys.argv) > 2 else None
    darwin_dir = run(["getconf", "DARWIN_USER_DIR"])
    lp_db = os.path.join(darwin_dir, "com.apple.dock.launchpad", "db", "db")

    if not os.path.exists(lp_db):
        print("ERROR: DB not found", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(lp_db)
    conn.execute("PRAGMA busy_timeout = 5000")
    cur = conn.cursor()

    cat_map = build_category_map()

    # Find pages to modify (skip Apple-only)
    cur.execute("""
        SELECT rowid FROM items
        WHERE type=3 AND parent_id=1 AND uuid NOT LIKE 'HOLDING%'
        ORDER BY ordering
    """)
    all_pages = [r[0] for r in cur.fetchall()]

    sort_pages = []
    for pid in all_pages:
        cur.execute("SELECT COUNT(*) FROM apps a JOIN items i ON a.item_id=i.rowid WHERE i.parent_id=? AND a.bundleid NOT LIKE 'com.apple.%'", (pid,))
        non_apple = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM items WHERE type=4 AND parent_id=?", (pid,))
        total = cur.fetchone()[0]
        if total > 0 and non_apple == 0:
            continue
        sort_pages.append(pid)

    # Collect apps
    apps = []
    for pid in sort_pages:
        cur.execute("SELECT a.item_id, a.bundleid, a.title FROM apps a JOIN items i ON a.item_id=i.rowid WHERE i.parent_id=?", (pid,))
        apps.extend(cur.fetchall())

    # Assign categories, merge small
    app_data = [(iid, t, cat_map.get(bid, "Other")) for iid, bid, t in apps]
    cat_counts = Counter(c for _, _, c in app_data)
    small = {c for c, n in cat_counts.items() if n < MIN_CATEGORY_SIZE and c != "Other"}
    app_data = [(iid, t, "Other" if c in small else c) for iid, t, c in app_data]

    # Group
    groups = defaultdict(list)
    for iid, t, c in app_data:
        groups[c].append((iid, t))
    for c in groups:
        groups[c].sort(key=lambda x: (x[1] or "").lower())

    # Preview mode — just print and exit
    if mode == "preview":
        for c in sorted(groups):
            print(f"{c}|{len(groups[c])}")
        conn.close()
        sys.exit(0)

    # Apply: filter groups by user selection, rest become loose apps on the page
    loose_apps = []
    if selected_cats is not None:
        kept = {}
        for c, items in groups.items():
            if c in selected_cats:
                kept[c] = items
            else:
                loose_apps.extend(items)
        groups = kept

    if not sort_pages:
        print("ERROR: No pages with third-party apps", file=sys.stderr)
        conn.close()
        sys.exit(1)

    target_page = sort_pages[0]

    # File backup before any schema/data change — trigger drop below auto-commits,
    # so a crash between it and the data transaction is otherwise unrecoverable
    shutil.copy2(lp_db, lp_db + ".bak")

    # Drop triggers (executescript auto-commits — safe, no data changes yet)
    drop_sql = "\n".join(f"DROP TRIGGER IF EXISTS {t};" for t in [
        "update_items_order", "update_items_order_backwards", "update_item_parent",
        "insert_item", "app_inserted", "app_deleted", "item_deleted"])
    cur.executescript(drop_sql)

    # Data mutations in a single transaction
    cur.execute("BEGIN IMMEDIATE")

    # Delete extra pages (+ manual groups cleanup since triggers are dropped)
    for pid in sort_pages[1:]:
        cur.execute("DELETE FROM groups WHERE item_id=?", (pid,))
        cur.execute("DELETE FROM items WHERE rowid=?", (pid,))

    # Next rowid
    cur.execute("SELECT MAX(rowid) FROM items")
    next_id = cur.fetchone()[0] + 1

    # Create folders
    for folder_order, cat in enumerate(sorted(groups)):
        folder_id = next_id
        next_id += 1
        inner_page_id = next_id
        next_id += 1

        cur.execute("INSERT INTO items (rowid,uuid,flags,type,parent_id,ordering) VALUES (?,?,1,2,?,?)",
                    (folder_id, str(uuid.uuid4()).upper(), target_page, folder_order))
        cur.execute("INSERT INTO groups (item_id,category_id,title) VALUES (?,NULL,?)", (folder_id, cat))

        cur.execute("INSERT INTO items (rowid,uuid,flags,type,parent_id,ordering) VALUES (?,?,0,3,?,0)",
                    (inner_page_id, str(uuid.uuid4()).upper(), folder_id))
        cur.execute("INSERT INTO groups (item_id,category_id,title) VALUES (?,NULL,'')", (inner_page_id,))

        for app_order, (iid, _) in enumerate(groups[cat]):
            cur.execute("UPDATE items SET parent_id=?,ordering=? WHERE rowid=?", (inner_page_id, app_order, iid))

    # Place unselected apps loose on the target page after the folders
    loose_apps.sort(key=lambda x: (x[1] or "").lower())
    base_order = len(groups)
    for offset, (iid, _) in enumerate(loose_apps):
        cur.execute("UPDATE items SET parent_id=?,ordering=? WHERE rowid=?",
                    (target_page, base_order + offset, iid))

    cur.execute("COMMIT")

    # Restore triggers (executescript auto-commits — safe, data already committed)
    cur.executescript(TRIGGERS_SQL)

    conn.close()

    run(["killall", "Dock"])
    print(f"OK|{len(groups)}")

if __name__ == "__main__":
    main()
