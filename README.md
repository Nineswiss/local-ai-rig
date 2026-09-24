# local-ai-rig

Offline-capable AI, running on a GPU-equipped Windows PC, reachable from
anywhere on your LAN two ways:

- **Browser chat** ([Open WebUI](https://openwebui.com)) — open a URL, no
  install, works from any device on your network (phone included). Supports
  image uploads for vision-capable models.
- **[Aider](https://aider.chat)** — for real file editing, run from whichever
  machine actually has your project files.

No internet required once the PC is set up — works over your home/office
network even with WAN internet down.

## Requirements

- **PC**: Windows, NVIDIA GPU (tested on RTX 3060 12GB), PowerShell
- **Browser chat**: nothing — any device on your LAN with a web browser
- **Aider (file editing)**: macOS or Linux (tested on macOS) — this is the
  machine with your actual project files

## Setup

**1. On the PC** (PowerShell, doesn't need to be Administrator):

```powershell
.\setup-pc.ps1
```

This one script does everything on the PC side:

- Installs Ollama, binds it to your LAN with a proper context window (see
  [Known issues](#known-issues)), opens the firewall, and pulls **three**
  models — a fast one, a bigger one for complex requests, and a
  vision-capable one for images (see [Choosing a model](#choosing-a-model)).
- Installs and configures [Open WebUI](https://openwebui.com) (its own
  Python venv, its own firewall rule) and applies known-good per-model
  settings automatically — see [Browser chat](#browser-chat) for what that
  means and the one manual step it can't do for you.

Override the models with `.\setup-pc.ps1 -Model ... -BigModel ...
-VisionModel ...`. Skip Open WebUI entirely with `.\setup-pc.ps1
-SkipWebUI` if you only want Aider.

The script is **idempotent** — safe to re-run any time (after a reboot, to
pick up a config change, to recover from a crash). It prints the PC's
`.local` hostname at the end (and its current IP, for reference) — **use
the hostname, not the IP**, everywhere below. See
[Known issues](#known-issues) for why.

**2. Browser chat needs nothing further** — see
[Browser chat](#browser-chat) below.

**2b. For Aider (file editing), on your client machine** (the one with your
project files):

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

## Browser chat

Open `http://<pc-host>.local:8080` from any device on your LAN — phone,
laptop, whatever. No install, nothing to run first.

**First time only:** the PC's admin account for Open WebUI is a fully local
account (nothing leaves the PC) that only *you* can create — `setup-pc.ps1`
opens the moment for it and waits, but deliberately does not create it for
you. Everything else — which models show up, their descriptions, and the
settings each one needs — is configured automatically by the script.

Specifically, `setup-pc.ps1` writes known-good settings directly into Open
WebUI's own config for each model, so you don't have to click through its
admin UI by hand:

- **`qwen2.5vl:7b`** is set to `Function Calling: Legacy` (its default mode
  throws a "does not support tools" error the moment you attach an image —
  a real bug in how Open WebUI probes tool support, not a model
  limitation), is renamed to "qwen2.5vl:7b 📷" so it's obvious at a glance
  in the model picker which one can see images, and has web search
  disabled for it specifically (see below) to keep it simple.
- **`qwen2.5:14b`** and **`devstral:24b`** get descriptions explaining
  what each is best for (see [Choosing a model](#choosing-a-model)) —
  visible by clicking a model's ⓘ icon in the picker.

Re-running `setup-pc.ps1` re-applies these settings — safe to do any time,
including after pulling a different model.

**Web search** is also enabled by default, using DuckDuckGo — free, no API
key or signup needed, so it doesn't cost `setup-pc.ps1` its clone-and-run
simplicity. Trigger it either by asking something that needs current info
(the model decides whether to search), or force it by clicking the `+`
icon next to the message box and toggling **Web Search** on before you
send.

**Use `devstral:24b` for anything that needs search** — verified working
end-to-end (search executes, results get cited). **`qwen2.5:14b` currently
doesn't work for this**: verified live, both automatic and forced, and
instead of calling the tool it dumps raw
`{"name": "search_web", "arguments": {...}}` text into the chat as if it
were part of the answer. Ollama itself handles tool-calling for this model
correctly (confirmed by calling its native API directly) and the context
window is fine, so this isn't a config problem — it's Open WebUI failing
to parse qwen2.5's particular tool-call format during a streamed response,
which matches several currently-open upstream Open WebUI issues around
tool-calls leaking as text mid-stream. Nothing to fix on our end; revisit
if/when Open WebUI ships a fix.

**This is the one feature in this repo that needs real internet** —
everything else works fully offline over your LAN, but web search
obviously can't, since it has to reach the actual web. If you're offline
and the model tries to search, the search itself will fail; we haven't
specifically tested how gracefully the model handles that failure, so
don't assume it'll clearly tell you rather than answering from its own
(possibly outdated) knowledge instead.

## Image generation

Not wired into Open WebUI's chat — deliberately. `qwen2.5:14b` alone
already uses ~10GB of a 12GB card, so running an LLM and a FLUX-class
image model at the same time doesn't really work, and Open WebUI has no
real separation between "chat" and "image" beyond a per-message toggle in
the same conversation (there's no standalone image section in its UI —
getting one would mean forking and hand-rebuilding its frontend on every
update, a much bigger commitment than anything else here).

Instead, `image-gate.py` is a tiny standalone page (stdlib Python, nothing
to install) that answers one question: is the GPU actually free right
now? It polls Ollama's own `/api/ps` and shows a waiting message while a
model is loaded, then reveals a link to ComfyUI once it's clear:

```powershell
.\image-gate.bat    # double-click, or run from PowerShell
```

Opens at `http://localhost:8189` and checks every few seconds. ComfyUI
itself (assumed to already be installed — this repo doesn't set it up)
is a normal desktop app; open it yourself as usual once the gate says
it's clear. Ollama unloads idle models automatically after a few
minutes, so in practice you don't need to manually stop anything —
just wait for the page to go green.

## Starting and stopping the services

**Easiest:** double-click `start-pc.bat` / `stop-pc.bat` in File Explorer.
No terminal needed — a window opens showing what happened, and waits for
a key press so you can read it before it closes.

Useful for freeing GPU VRAM when you're not using AI, or a clean restart
after a config change. Both are safe to run any time — starting when
already running (or stopping when already stopped) just says so and does
nothing. Unlike `setup-pc.ps1`, `start-pc.bat` doesn't reinstall anything,
pull models, or need internet — it just turns the already-installed
services back on, so it works fine offline.

From PowerShell, the same thing with more control:

```powershell
.\start-pc.ps1             # start both, shows status before/after
.\stop-pc.ps1              # stop both, shows status before/after
.\stop-pc.ps1 -OllamaOnly  # leave Open WebUI running
.\stop-pc.ps1 -WebUIOnly   # leave Ollama running (Aider still works)
```

Useful for freeing GPU VRAM when you're not using AI, or for a clean
restart after a config change. Safe to run any time, whether or not
either is actually running. Re-run `setup-pc.ps1` to start them again.

## GPU-busy indicator

This PC's one GPU is shared with [forge-ui](https://github.com/Nineswiss/forge-ui)
(image/video generation) - if both run at once, Ollama gets slower or
outright fails, silently, with no obvious reason why. `gpu-banner-watcher.ps1`
watches for that and shows a warning banner ("Forge is generating an image
or video right now - chat responses may be slower or fail") at the top of
the Open WebUI chat UI whenever Forge specifically is busy - started
automatically by `start-pc.ps1`, stopped by `stop-pc.ps1`. It's a nicety
layered on top, not a dependency - everything else here works fine if it's
not running.

Deliberately only flags Forge, not "anything else with a GPU handle open" -
nearly every desktop app holds one just for normal compositing (Notepad
included), and surfacing that would just be noise with nothing to act on.

**One manual step to enable it - API keys are off by default in Open
WebUI:**

1. Log in as admin, go to **Admin Panel → Settings → Authentication**, turn
   on the **API Keys** toggle, and Save. (Not the personal Settings →
   General - this is the admin-only System section.)
2. Now go to **Settings → Account** (personal settings this time) - an
   **API keys** section has appeared. Generate one there (not the "JWT
   Token" under Secrets a bit further down - that's your session token,
   expires with your login, and isn't meant for this).
3. Save the key (no quotes, no trailing newline - watch out for Notepad
   silently adding a `.txt` extension if you "Save As" without selecting
   "All Files") to a file named `.openwebui-api-key` in this folder.

Without that file the watcher just logs a warning and keeps retrying every
10s - nothing breaks, the banner just never appears. Check
`gpu-banner-watcher.log` (also in this folder, gitignored) if it's still
not showing up after adding the key - it logs every check, including any
API error. One thing that looks like a bug but isn't: a banner that's set
*while* you already have Open WebUI open in a tab won't appear there until
you load the page fresh (new tab, or navigate to the bare
`http://<host>.local:8080` URL rather than an already-open chat) - Open
WebUI only fetches banners on page load, not live.

## UI/UX design generation (UIGEN-FX)

`uigen-fx:4b` ([Tesslate/UIGEN-FX-4B-Preview](https://huggingface.co/Tesslate/UIGEN-FX-4B-Preview),
Qwen3-4B fine-tuned specifically on frontend code) generates working
HTML/CSS/Tailwind/React markup for a UI from a plain description - it
outputs *code*, not an image, so the deliverable is a page/component you
paste into a project, not a picture (that's forge-ui's job - see its
README if you want an actual rendered mockup image instead).

**Not part of `setup-pc.ps1`** - pulled manually since it's not on Ollama's
own registry, only Hugging Face:

```
ollama pull hf.co/QuantFactory/UIGEN-FX-4B-Preview-GGUF:Q4_K_M
ollama cp hf.co/QuantFactory/UIGEN-FX-4B-Preview-GGUF:Q4_K_M uigen-fx:4b
ollama rm hf.co/QuantFactory/UIGEN-FX-4B-Preview-GGUF:Q4_K_M
```

Small (2.7GB Q4_K_M quant, fully GPU-resident alongside anything else here)
and fast. Verified end-to-end: generated a complete, valid Tailwind pricing
card component from a one-line prompt. Pick it from the model picker in
[Browser chat](#browser-chat) like any other model - no special Open WebUI
config needed (no vision, no tool-calling, so none of the settings
`setup-pc.ps1` applies to the other models are relevant here).

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
- **`qwen2.5vl:7b`** — the vision-capable model, for browser chat with
  images. Smaller (6GB) than the others since it has to share VRAM budget
  with its vision tower. Not tuned for agentic file editing — use it in
  Open WebUI, not with Aider.

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
directory for review if all attempts fail. `aider-retry.sh` runs
`check-connection.sh` first and fails fast with a clear reason if the PC
isn't reachable, instead of burning through several minutes of retries
against a dead connection.

## Checking connectivity

```bash
./check-connection.sh <pc-host>
# e.g. ./check-connection.sh adampc.local
```

Run this any time something seems broken — it turns a cryptic
"connection refused" buried in Aider's stack trace into a specific,
actionable answer (PC asleep? wrong network? stale IP instead of the
`.local` hostname? Ollama itself crashed?). It's also run automatically
by `aider-retry.sh` before every batch of attempts.

## Known issues

- **Use the PC's `.local` hostname, never its raw LAN IP.** The IP is
  DHCP-assigned by your router and *will* change eventually (router reboot,
  lease expiry, the PC reconnecting after sleep) — anything with the IP
  hardcoded (`OLLAMA_API_BASE`, `aider-retry.sh`'s default, etc.) then
  breaks silently, with no obvious error pointing at the real cause.
  `<hostname>.local` resolves via mDNS, which is already built into both
  Windows and macOS — no setup needed — and keeps resolving correctly no
  matter what IP the PC currently has. `setup-pc.ps1` prints this hostname
  for you; `setup-client.sh`, `aider-retry.sh`, and `check-connection.sh`
  all expect it (an IP still works, it's just one router reboot away from
  silently breaking). Verify yours resolves with `ping <hostname>.local`
  (or `./check-connection.sh <hostname>.local`) before relying on it — it's
  near-universal on home networks but not guaranteed on locked-down
  corporate/guest networks.
- **Ollama's default context window is too small.** It auto-sizes from
  free VRAM and often lands around 4096 tokens — enough for a single-file
  edit, not for a big multi-file response, which then gets silently cut
  off mid-generation. `setup-pc.ps1` sets `OLLAMA_CONTEXT_LENGTH=16384`
  persistently to fix this.
- **Ollama or Open WebUI can die on a network blip or PC reboot.** If
  either stops responding, just re-run `setup-pc.ps1` — it's idempotent and
  safe to run again; it'll skip anything already installed/configured and
  just restart the services.
- If `aider`/`aider-big` can't reach Ollama, run `./check-connection.sh
  <pc-host>` first — it'll tell you exactly what's wrong. Common causes:
  both machines not on the same LAN, the PC's firewall rule missing
  (`setup-pc.ps1` creates one named `Ollama LAN (local-ai-rig)`), or
  `$OLLAMA_API_BASE` not actually set in your current terminal (open a
  **new** terminal after running `setup-client.sh` if it's empty).

## FAQ

**Is there anything to set up on the Mac (or other client) for a fresh
install?** For browser chat, no — open the URL `setup-pc.ps1` prints and
you're done, from any device. For Aider (real file editing), yes: run
`setup-client.sh` once on the machine with your project files (step 2b
above) — that's what installs Aider itself and wires up the `aider` /
`aider-big` commands.

**Is there an IP/connectivity check, and where does it run?**
`check-connection.sh` checks both Ollama and Open WebUI reachability with
specific, actionable failure messages. It's wired into `aider-retry.sh`,
which runs it before every batch of attempts, so a dead connection fails
in seconds with a clear reason instead of burning through several minutes
of retries. Run it manually any time with `./check-connection.sh
<pc-host>`.

**Is it easy to clone, set up, and run?** On the PC: clone the repo, run
`.\setup-pc.ps1`, create the Open WebUI admin account when prompted (the
one manual step — a local account only you can create). That's Ollama, all
three models, and Open WebUI fully installed and configured. On a client
machine, for Aider: clone the repo, run `./setup-client.sh <pc-host>`. For
browser chat: nothing to clone at all — just open the URL from any device.

## Repo layout

| File | Runs on | Purpose |
|---|---|---|
| `setup-pc.ps1` | PC | One-shot setup: Ollama, models, Open WebUI, firewall rules |
| `start-pc.ps1` / `start-pc.bat` | PC | Starts Ollama/Open WebUI if not already running (no install/network needed) |
| `stop-pc.ps1` / `stop-pc.bat` | PC | Stops Ollama/Open WebUI (frees GPU VRAM, clean restarts) |
| `image-gate.py` / `image-gate.bat` | PC | Standalone page: waits for the GPU to free up, then links to ComfyUI |
| `seed-model-config.py` | PC (called by `setup-pc.ps1`) | Writes known-good per-model settings into Open WebUI's database |
| `enable-web-search.py` | PC (called by `setup-pc.ps1`) | Turns on web search (DuckDuckGo) in Open WebUI's database |
| `check-admin-exists.py` | PC (called by `setup-pc.ps1`) | Checks whether the Open WebUI admin account has been created yet |
| `setup-client.sh` | Client | Installs Aider, configures it to use the PC over LAN |
| `aider-retry.sh` | Client | Runs an Aider request with connectivity preflight + fresh-retry-on-failure |
| `check-connection.sh` | Client | Diagnoses PC/Ollama/Open WebUI reachability |

## Roadmap

- [x] Browser-based interface (Open WebUI, with automated per-model config)
- [ ] Image support in chat (vision model is wired up; UI walkthrough/polish TBD)
- [x] Web search (DuckDuckGo, no API key needed - see [Browser chat](#browser-chat))
- [x] Image generation (not wired into chat - see [Image generation](#image-generation).
      `image-gate.py` gates access to an already-installed ComfyUI by GPU
      availability instead)
- [ ] More features as we go
