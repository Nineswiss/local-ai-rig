#!/usr/bin/env python3
"""enable-web-search.py
Enables Open WebUI's web search feature using DuckDuckGo - free, no API
key or signup needed, which keeps setup-pc.ps1 fully clone-and-run.
Writes directly into the SQLite config table for the same reason
seed-model-config.py bypasses the REST API: no authenticated admin
session exists yet at setup time.

qwen2.5:14b and devstral:24b pick this up automatically (a model gets
every builtin tool unless its own meta.builtinTools explicitly disables
it - see seed-model-config.py, which does exactly that for the vision
model to keep it simple there).

Must run while Open WebUI is NOT running (avoids writing to the DB file
while its own process has it open).

Usage:
  python enable-web-search.py <path-to-webui.db>
"""
import json
import sqlite3
import sys
import time

CONFIG = {
    "web.search.enable": True,
    "web.search.engine": "duckduckgo",
}


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path-to-webui.db>")
        sys.exit(1)

    db_path = sys.argv[1]
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    now = int(time.time())

    for key, value in CONFIG.items():
        cur.execute(
            "INSERT INTO config (key, value, updated_at) VALUES (?, ?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
            (key, json.dumps(value), now),
        )

    conn.commit()
    conn.close()
    print(f"Enabled web search (engine: duckduckgo).")


if __name__ == "__main__":
    main()
