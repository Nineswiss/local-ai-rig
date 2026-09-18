#!/usr/bin/env python3
"""check-admin-exists.py
Read-only check: does Open WebUI's database already have an admin user?
Prints YES/NO. Used by setup-pc.ps1 to decide whether to prompt for
first-run signup, without needing inline Python passed through PowerShell
(which mangles embedded quotes - learned that the hard way).

Usage: python check-admin-exists.py <path-to-webui.db>
"""
import sqlite3
import sys

if len(sys.argv) != 2:
    print("NO")
    sys.exit(0)

try:
    conn = sqlite3.connect(sys.argv[1])
    cur = conn.cursor()
    cur.execute("SELECT 1 FROM user WHERE role = 'admin' LIMIT 1")
    print("YES" if cur.fetchone() else "NO")
except sqlite3.Error:
    print("NO")
