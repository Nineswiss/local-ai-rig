#!/usr/bin/env python3
"""seed-model-config.py
Applies known-good per-model settings to Open WebUI's own SQLite database
directly, bypassing its REST API (which needs an authenticated admin
session we don't have at setup time - the admin account doesn't exist
until the operator completes first-run signup in the browser).

Must run AFTER the operator has created their admin account (the script
looks up that user's id itself - no credentials needed) and while
Open WebUI is NOT running (avoids writing to the DB file while its own
process has it open).

Usage:
  python seed-model-config.py <path-to-webui.db>
"""
import json
import sqlite3
import sys
import time

MODEL_CONFIG = {
    "qwen2.5vl:7b": {
        "params": {"function_calling": "legacy"},
        "meta": {
            "description": "\U0001F4F7 Vision-capable — can see and describe uploaded images.",
            "builtinTools": {
                "web_search": False,
                "image_generation": False,
                "code_interpreter": False,
                "tasks": False,
                "automations": False,
                "calendar": False,
                "subagents": False,
            },
        },
    },
    "qwen2.5:14b": {
        "meta": {
            "description": "⚡ Fast, fully GPU-resident text model. Best for quick, single-file edits.",
        },
    },
    "devstral:24b": {
        "meta": {
            "description": "\U0001F9E0 Best for complex, multi-file requests (built for agentic coding). Slower — partially CPU-offloaded on 12GB VRAM.",
        },
    },
}

DEFAULT_META = {
    "profile_image_url": "/static/favicon.png",
    "capabilities": {},
    "knowledge": None,
    "suggestion_prompts": None,
    "tags": [],
}


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path-to-webui.db>")
        sys.exit(1)

    db_path = sys.argv[1]
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("SELECT id FROM user WHERE role = 'admin' LIMIT 1")
    row = cur.fetchone()
    if not row:
        print("No admin user found yet. Complete the first-run signup in the")
        print("browser, then re-run this script.")
        sys.exit(1)
    user_id = row[0]

    now = int(time.time())
    applied = []
    skipped = []

    for model_id, cfg in MODEL_CONFIG.items():
        cur.execute("SELECT params, meta FROM model WHERE id = ?", (model_id,))
        existing = cur.fetchone()

        if existing:
            params = json.loads(existing[0]) if existing[0] else {}
            meta = json.loads(existing[1]) if existing[1] else {}
        else:
            params = {}
            meta = dict(DEFAULT_META)

        params.update(cfg.get("params", {}))
        meta.update(cfg.get("meta", {}))

        if existing:
            cur.execute(
                "UPDATE model SET params = ?, meta = ?, updated_at = ? WHERE id = ?",
                (json.dumps(params), json.dumps(meta), now, model_id),
            )
        else:
            cur.execute(
                "INSERT INTO model (id, user_id, base_model_id, name, params, meta, "
                "updated_at, created_at, is_active) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, 1)",
                (model_id, user_id, model_id, json.dumps(params), json.dumps(meta), now, now),
            )
        applied.append(model_id)

    conn.commit()
    conn.close()

    print(f"Applied config to: {', '.join(applied)}")
    if skipped:
        print(f"Skipped (not found in Ollama yet): {', '.join(skipped)}")


if __name__ == "__main__":
    main()
