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
        # The description (below) only shows if you click a model's (i)
        # icon - easy to miss. Putting the emoji in the display name means
        # it shows right in the model picker list, no click needed.
        "name": "qwen2.5vl:7b \U0001F4F7",
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
    "uigen-fx:4b": {
        # Same "does not support tools" bug as qwen2.5vl:7b above - Open
        # WebUI misdetects tool-calling support on this GGUF import (pulled
        # via hf.co, not Ollama's own registry - see README). Not a model
        # limitation, same fix.
        #
        # The system prompt forces raw output into a single fenced ```html
        # block - confirmed live that without this, the model's raw HTML
        # (no fence) just renders as plain escaped text in the chat instead
        # of Open WebUI's live-preview Artifact panel. Open WebUI's
        # Artifacts feature also only renders complete single-file
        # HTML/SVG, not React/JSX, so this steers the model away from the
        # React output its own docs otherwise advertise.
        "params": {
            "function_calling": "legacy",
            "system": (
                "You generate complete, single-file HTML UI mockups (inline "
                "Tailwind via the CDN script tag, inline CSS/JS as needed - "
                "no React/JSX, no build step). Always wrap the ENTIRE output "
                "in exactly one fenced markdown code block starting with "
                "```html and ending with ```, with no other text before or "
                "after the fence - this is required to trigger Open WebUI's "
                "live preview."
            ),
        },
        "meta": {
            "description": "\U0001F3A8 Generates HTML/CSS/Tailwind UI mockups with a live preview. Not an image model.",
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
        cur.execute("SELECT name, params, meta FROM model WHERE id = ?", (model_id,))
        existing = cur.fetchone()

        if existing:
            existing_name, existing_params, existing_meta = existing
            params = json.loads(existing_params) if existing_params else {}
            meta = json.loads(existing_meta) if existing_meta else {}
            name = cfg.get("name", existing_name)
        else:
            params = {}
            meta = dict(DEFAULT_META)
            name = cfg.get("name", model_id)

        params.update(cfg.get("params", {}))
        meta.update(cfg.get("meta", {}))

        if existing:
            cur.execute(
                "UPDATE model SET name = ?, params = ?, meta = ?, updated_at = ? WHERE id = ?",
                (name, json.dumps(params), json.dumps(meta), now, model_id),
            )
        else:
            cur.execute(
                "INSERT INTO model (id, user_id, base_model_id, name, params, meta, "
                "updated_at, created_at, is_active) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, 1)",
                (model_id, user_id, name, json.dumps(params), json.dumps(meta), now, now),
            )
        applied.append(model_id)

    conn.commit()
    conn.close()

    print(f"Applied config to: {', '.join(applied)}")
    if skipped:
        print(f"Skipped (not found in Ollama yet): {', '.join(skipped)}")


if __name__ == "__main__":
    main()
