# local-ai-rig

Offline-capable AI coding assistant: a GPU-equipped Windows PC runs the model
(via [Ollama](https://ollama.com)), and any machine on your LAN drives it
with [Aider](https://aider.chat) for real file editing — no internet
required once both machines are set up. Works over your home/office network
even with WAN internet down.

## Requirements

- **PC**: Windows, NVIDIA GPU (tested on RTX 3060 12GB), PowerShell
- **Client**: macOS or Linux (tested on macOS) — this is the machine with
  your actual project files

## Setup

**1. On the PC** (PowerShell, doesn't need to be Administrator):

```powershell
.\setup-pc.ps1
```

Installs Ollama, binds it to your LAN with a proper context window (see
[Known issues](#known-issues)), opens the firewall, and pulls **two**
models — a fast one for everyday edits and a bigger one for complex,
multi-file requests (see [Choosing a model](#choosing-a-model) for why you
want both). Override either with `.\setup-pc.ps1 -Model ... -BigModel ...`.

The script prints the PC's `.local` hostname at the end (and its current IP,
for reference) — **use the hostname, not the IP**, in step 2. See
[Known issues](#known-issues) for why.

**2. On your client machine** (the one with your project files):

```bash
./setup-client.sh <pc-host>
# e.g. ./setup-client.sh adampc.local
```

Installs Aider, points it at the PC over your LAN, and sets up two commands:

- `aider` — the fast model, `yes-always` (no per-file confirmation prompts)
- `aider-big` — the bigger model, for new projects / big scaffolds

Edit `~/.aider.conf.yml` if you'd rather review each change before it's
applied (drop `yes-always`).

**3. Use it:**

```bash
cd your-project
git init       # see the warning below - do this if the folder isn't a repo yet
aider          # quick edits to existing files
aider-big      # starting something new, multiple files at once
```

> **Always start a new project with its own `git init` first.** If the
> folder you launch Aider from isn't itself a git repo, but some *ancestor*
> directory is (e.g. because an earlier Aider session was accidentally run
> one level up and auto-created a repo there), Aider treats that ancestor
> as the project root and writes files relative to *it* — not the folder
> you're actually in. This happens silently: Aider reports success, the
> files just land somewhere else entirely, potentially mixed in with
> unrelated projects. `aider-retry.sh` does this for you automatically;
> plain `aider`/`aider-big` do not.

## Choosing a model

12GB VRAM comfortably fits a 14B model at 4-bit quant, fully GPU-resident.
We tested this extensively, so this isn't a guess:

- **For single, well-scoped edits to existing files**, any reasonable local
  14B model works reliably — `qwen2.5:14b` was verified repeatedly. Fast,
  fully GPU-resident.
- **For complex, multi-file requests** (scaffold a whole app, wire up
  several new files at once), 14-16B models — including `-coder` variants
  — consistently struggled: they'd narrate a "how to run this" section
  with example shell commands, or otherwise break Aider's strict file-edit
  parser somewhere in a long response, even though the actual code content
  was usually fine. This wasn't fixed by prompt tweaks, forcing a different
  edit format, or Aider's architect/editor split mode — we tried all three
  before concluding it's a real ceiling for this model class on big
  requests specifically.
- **`devstral:24b`** — a model Mistral specifically built for *agentic*
  coding (not just code completion) — noticeably more reliable at this than
  the 14-16B models: one verified run produced a real multi-file scaffold
  (React + Vite frontend, Node/Express backend, MongoDB, auth routes — 14
  files, all correct, consistent naming across routes/controllers/models).
  It's 14GB, so on a 12GB card it partially spills to CPU/system RAM —
  noticeably slower (~4 tok/s) than the fully GPU-resident 14B models.
  **It's not 100% reliable either** — it can hit the same narrate-instead-
  of-write failure. Use `aider-retry.sh` (below) rather than letting Aider
  argue with itself in place when that happens.
- Don't assume "coder" variants beat general instruct models for *agentic*
  editing specifically — in our testing, `qwen2.5-coder:14b` also
  intermittently refused login/auth-related requests outright (a
  false-positive safety trigger, not a capability gap), on top of the same
  format-adherence issues as the non-coder model.

## When it fails: retry fresh, don't let it argue with itself

If Aider gets the format wrong, it auto-retries in place ("reflection") —
but that feeds the model a growing, increasingly confused conversation
history, and each cycle on `devstral:24b` can take 5-6+ minutes on a
partially-CPU-offloaded 12GB card. We watched one real session do this for
30+ minutes across 5 cycles without ever converging. **If you see it
repeating a generic acknowledgment like "Understood, let's proceed..." and
starting over, stop it (Ctrl+C) rather than waiting it out.**

Use `aider-retry.sh` instead — it runs the request, checks whether real
files actually landed (ignoring Aider's own bookkeeping files), and if not,
retries with a **completely fresh attempt** rather than continuing the
failed conversation. These failures aren't deterministic — a clean retry
has a real chance of just working:

```bash
cd your-project
~/Documents/dev/local-ai-rig/aider-retry.sh "create a react + vite app with node backend, mongodb, a login page, and a secured page that says 'welcome!'. call it ReactTest"
# optional: [max_attempts] [model], defaults to 3 attempts on devstral:24b
```

Each attempt's full log is saved under `.aider-retry-logs/` in your project
directory for review if all attempts fail.

## Known issues

- **Use the PC's `.local` hostname, never its raw LAN IP.** The IP is
  DHCP-assigned by your router and *will* change eventually (router reboot,
  lease expiry, the PC reconnecting after sleep) — anything with the IP
  hardcoded (`OLLAMA_API_BASE`, `aider-retry.sh`'s default, etc.) then
  breaks silently, with no obvious error pointing at the real cause.
  `<hostname>.local` resolves via mDNS, which is already built into both
  Windows and macOS — no setup needed — and keeps resolving correctly no
  matter what IP the PC currently has. `setup-pc.ps1` prints this hostname
  for you; `setup-client.sh` and `aider-retry.sh` both expect it (an IP
  still works, it's just one router reboot away from silently breaking).
  Verify yours resolves with `ping <hostname>.local` before relying on it —
  it's near-universal on home networks but not guaranteed on locked-down
  corporate/guest networks.
- **Ollama's default context window is too small.** It auto-sizes from
  free VRAM and often lands around 4096 tokens — enough for a single-file
  edit, not for a big multi-file response, which then gets silently cut
  off mid-generation. `setup-pc.ps1` sets `OLLAMA_CONTEXT_LENGTH=16384`
  persistently to fix this.
- **Ollama can die on a network blip or PC reboot.** If it stops
  responding, just re-run `setup-pc.ps1` — it's idempotent and safe to run
  again.
- If `aider`/`aider-big` can't reach Ollama, check: both machines on the
  same LAN, the PC's firewall rule exists (`setup-pc.ps1` creates one
  named `Ollama LAN (local-ai-rig)`), and `$OLLAMA_API_BASE` is actually
  set in your current terminal (`echo $OLLAMA_API_BASE` — open a **new**
  terminal after running `setup-client.sh` if it's empty).

## Roadmap

- [ ] Browser-based interface (starting from Open WebUI, customized)
- [ ] Image support in chat
- [ ] More features as we go
