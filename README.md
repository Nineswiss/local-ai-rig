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

This installs Ollama, binds it to your LAN, opens the firewall for it, and
pulls `qwen2.5:14b` (override with `.\setup-pc.ps1 -Model qwen2.5:32b` if
you have more VRAM to spare — see [Choosing a model](#choosing-a-model)).

The script prints the PC's LAN IP at the end. You'll need it for step 2.

**2. On your client machine** (the one with your project files):

```bash
./setup-client.sh <pc-ip>
# e.g. ./setup-client.sh 192.168.1.3
```

This installs Aider, points it at the PC over your LAN, and configures it
to auto-approve file edits without prompting per file (`yes-always`) and
skip the colorized formatting (`pretty: false`) — edit
`~/.aider.conf.yml` if you'd rather review each change first (drop
`yes-always`).

**3. Use it:**

```bash
cd your-project
aider
```

## Choosing a model

12GB VRAM comfortably fits `qwen2.5:14b` at 4-bit quant, fully GPU-resident.
More VRAM, more headroom for a bigger/smarter model — but bigger isn't
automatically better here:

- **Use plain `qwen2.5` or `llama3.1`, not `-coder` variants.** The coder
  variants return tool-call-shaped text output the harness can't always act
  on reliably — plain `qwen2.5:14b` was specifically verified (twice, with
  real file create + edit tasks) to work correctly with Aider.
- Aider doesn't need native function-calling like some agent frameworks do
  — it works off diffs in the model's text output, which is why it's more
  forgiving of smaller/local models than more complex tool-calling agents.

## Known issues

- **Ollama can die on a network blip or PC reboot.** `setup-pc.ps1` sets a
  persistent LAN-binding env var, but if Ollama's own background process
  dies (e.g. mid-driver-update reboot), just re-run `setup-pc.ps1` — it's
  idempotent and safe to run again.
- If `aider` can't reach Ollama, check: both machines on the same LAN, the
  PC's firewall rule exists (`setup-pc.ps1` creates one named
  `Ollama LAN (local-ai-rig)`), and `$OLLAMA_API_BASE` is actually set in
  your current terminal (`echo $OLLAMA_API_BASE` — open a **new** terminal
  after running `setup-client.sh` if it's empty).

## Roadmap

- [ ] Browser-based interface (starting from Open WebUI, customized)
- [ ] Image support in chat
- [ ] More features as we go
