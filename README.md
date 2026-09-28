# claude-whatsapp

Chat with Claude over WhatsApp. This project runs Claude Code in a Docker
container with the
[WhatsApp channel plugin](https://github.com/Rich627/whatsapp-claude-plugin).
It's linked to a dedicated WhatsApp number, and a list of approved people can
message it. Everything you'd want to change (packages, plugins, skills, MCP
servers, instructions, secrets) lives in plain files on your Mac, and all state
survives restarts and rebuilds.

## Contents

- [How it works](#how-it-works)
- [Folder layout](#folder-layout)
- [First-time setup](#first-time-setup)
- [Everyday use](#everyday-use)
- [When do changes take effect?](#when-do-changes-take-effect)
- [Configuration reference](#configuration-reference)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Chrome](#chrome)

## How it works

```
 WhatsApp (phones)
        │  Baileys / WhatsApp Web protocol, linked as a device on the bot's number
        ▼
┌──────────────────────── container: claude-whatsapp ─────────────────────────┐
│ tini → entrypoint.sh                                                         │
│          ├─ prepares ~/.claude from defaults + /config                       │
│          ├─ runtime-install.sh (marketplaces, plugins, skills, MCP)          │
│          └─ tmux session "claude"                                            │
│               └─ run-claude.sh (restart loop)                                │
│                    ├─ sync-mcp.sh          (before every launch)             │
│                    ├─ auto-confirm dev-channels warning                      │
│                    ├─ daily reset watcher  (CLAUDE_DAILY_RESET)              │
│                    └─ claude --dangerously-skip-permissions                  │
│                              --dangerously-load-development-channels …       │
│                              --remote-control [name] [--continue]            │
│                         ├─ whatsapp-channel MCP server (Bun)                 │
│                         └─ Claude in Chrome tools (--chrome) ──────┐         │
└────────────────────────────────────────────────────────────────────┼─────────┘
        ▲                                   ▲                        │ wss
        │ tmux attach                       │ Remote Control         ▼
   you, in a terminal                claude.ai/code or the     Anthropic browser
                                     Claude app                bridge (claude.ai
                                                               account)
                                                                     ▲ wss
┌──────────────────────── container: claude-whatsapp-chrome ─────────┼─────────┐
│ linuxserver/chrome: Google Chrome on a web desktop                 │         │
│   └─ Claude in Chrome extension, signed in to the same account ────┘         │
└──────────────────────────────────────────────────────────────────────────────┘
        ▲
        │ https://localhost:3001 (this Mac only)
   you, logging in to sites, watching Claude browse
```

**One long-lived interactive session.** The WhatsApp plugin is a Claude Code
*channel*: an MCP server that pushes incoming messages into a running
interactive session. So instead of calling Claude once per message, the
container keeps one `claude` session open in `tmux`. Messages from everyone on
the allowlist arrive in that session, and Claude replies through the plugin's
tools. The default instructions tell Claude to keep each person's conversations
separate.

**Startup sequence.** When the container starts, `entrypoint.sh`:

1. Creates any missing files in `/config` from the templates.
2. Marks onboarding (including the Claude in Chrome intro) complete and
   `/workspace` as trusted in `.claude.json`, so no first-run screens block the
   session.
3. Rebuilds `settings.json` from three layers: what Claude saved itself, then
   `defaults/settings.json`, then `local/config/settings.json`. Later layers win.
4. Links the memory files: `defaults/CLAUDE.md` becomes Claude's user memory, and
   `local/config/CLAUDE.md` becomes `/workspace/CLAUDE.md`, the project memory.
5. Links skills from `defaults/skills/` and `local/config/skills/`.
6. Runs `runtime-install.sh` to add marketplaces, install plugins, clone and pull
   git skills, and sync MCP servers.
7. Starts `run-claude.sh` in tmux session `claude`, then waits in the foreground
   for as long as that session exists.

**Restart loop.** `run-claude.sh` relaunches Claude whenever it exits, whether
from `/exit` or a crash. Before each launch it re-syncs MCP servers from
`install.yaml`. It resumes the previous conversation (`--continue`) and, in the
background, accepts the "Loading development channels" warning so no one has to
be at the terminal.

**Daily reset.** With `CLAUDE_DAILY_RESET=04:00` (the default in the template),
the first launch after 04:00 each day starts a new conversation instead of
resuming. If Claude is already running then, a background watcher ends it once
the chat has been quiet for 10 minutes, and the loop starts it fresh. That keeps
the context small and stops different people's threads from building up in one
long conversation. Nothing durable is lost: the `CLAUDE.md` files and the notes
in `/workspace` are reloaded, and old conversations stay in
`local/data/claude/projects/`. If the container was down at the reset time, the
reset happens on its next start. The date of the last reset is kept in
`local/data/claude/.last-daily-reset`.

Between resets, Claude compacts the conversation automatically when it nears
the context limit, and you can run `/compact` yourself at any time.

**Chrome.** A second container runs a real Google Chrome that you view in your
browser. Claude drives it through the Claude in Chrome extension. The two
containers don't talk to each other directly: Claude Code and the extension both
connect to Anthropic's browser bridge using the same claude.ai account, and the
bridge pairs them. See [Chrome](#chrome).

**Public vs private.** The git repo (`repo/`) holds only generic, shareable
material. Everything personal lives in a sibling `local/` folder that is never
committed: phone numbers, names, tokens, the Claude login and the WhatsApp link.
`install.yaml`, `settings.json`, `CLAUDE.md` and skills each exist in both places
and are merged, with local taking priority.

## Folder layout

```
claude-whatsapp/
├── repo/                        git repository (public-safe)
│   ├── docker-compose.yml
│   ├── .env.example             documents every env option
│   ├── chrome.env.example       documents the Chrome container's options
│   ├── claude/
│   │   ├── Dockerfile           Debian + Homebrew, Node, Bun, uv, tmux, Claude Code
│   │   └── scripts/             entrypoint, installers, restart loop, MCP sync
│   ├── chrome/
│   │   ├── Dockerfile           linuxserver/chrome, extension policy, user-agent wrapper
│   │   └── root/                files copied into the Chrome image
│   └── defaults/                baked into the image at /opt/defaults
│       ├── install.yaml         base packages, WhatsApp marketplace and plugin
│       ├── CLAUDE.md            generic WhatsApp assistant behaviour
│       ├── settings.json
│       ├── skills/              shareable skills
│       └── templates/           starting files for local/config
└── local/                       private: never committed
    ├── .env                     options and secrets → claude container env vars
    ├── chrome.env               Chrome container options (never sees .env)
    ├── config/        → /config           install.yaml, CLAUDE.md, settings.json, skills/
    ├── data/claude/   → ~/.claude         login, plugins, MCP config, conversations
    ├── data/whatsapp/ → ~/.whatsapp-channel   WhatsApp link, allowlist, inbox
    ├── data/chrome/   → Chrome's /config  Chrome profile: logins, cookies, extension
    └── workspace/     → /workspace        Claude's working directory and notes
```

To keep `local/` somewhere else, set `LOCAL_DIR=/path/to/local` in your shell or
in a gitignored `repo/.env`.

## First-time setup

You need Docker Desktop (or Docker Engine with Compose v2.24+), a Claude Pro or
Max plan, and a spare WhatsApp number for Claude.

```bash
cd repo
claude/scripts/init-local.sh
```

That creates `../local` from the templates. Then:

1. Edit `local/config/CLAUDE.md`: who the users are, their numbers, and anything
   Claude should know about your household.
2. Optionally, edit `local/.env` and `local/config/install.yaml`.
3. Build and start:

   ```bash
   docker compose up -d --build
   ```

4. Attach to the session:

   ```bash
   docker compose exec claude tmux attach -t claude
   ```

5. Run `/login` and sign in with your Claude account, then `/exit`. The loop
   restarts Claude signed in. Don't use `claude setup-token`: channels,
   Remote Control and Chrome integration need a full login.
6. Run `/whatsapp-channel:configure 447700900123`, using the bot's number with
   country code and no `+`. On the bot phone, go to **Settings → Linked devices →
   Link a device → Link with phone number instead** and enter the code shown.
7. Run `/whatsapp-channel:access` to allowlist the numbers that may talk to Claude.
8. Detach with `Ctrl-b d`. Claude keeps running.
9. Optionally, set up [Chrome](#chrome).

## Everyday use

| Task | How |
| --- | --- |
| Talk to Claude | Message the bot's WhatsApp number |
| Open the session in a browser or the app | Remote Control: look for the session in claude.ai/code or the Claude app |
| Open the session in a terminal | `docker compose exec claude tmux attach -t claude`, detach with `Ctrl-b d` |
| Restart just Claude | Type `/exit` in the session |
| See startup and install logs | `docker compose logs -f claude` |
| Get a shell in the container | `docker compose exec claude bash` |
| See or use Claude's Chrome | Open https://localhost:3001 (accept the self-signed certificate) |
| Update Claude Code | `docker compose build --no-cache && docker compose up -d` (the auto-updater is off) |
| Stop or start everything | `docker compose down` / `docker compose up -d` |

## When do changes take effect?

| You changed… | `/exit` | `docker compose restart claude` | `docker compose up -d` | `docker compose up -d --build` |
| --- | :-: | :-: | :-: | :-: |
| `install.yaml` → `runtime.mcp` | ✓ | ✓ | ✓ | ✓ |
| `install.yaml` → other `runtime` (plugins, skills), `settings.json`, skills folders | | ✓ | ✓ | ✓ |
| `CLAUDE.md` files | ✓\* | ✓ | ✓ | ✓ |
| `local/.env` | | | ✓ (recreates) | ✓ |
| `local/chrome.env` | | | ✓ (recreates Chrome) | ✓ |
| `install.yaml` → `build`, anything in `repo/` | | | | ✓ |

\* `CLAUDE.md` files are read when a session starts, so an `/exit` picks them up.

Environment variables are fixed when a container is created, so `restart` never
reloads `.env`, but `up -d` detects the change and recreates the container. If in
doubt, run `docker compose up -d --build`: unchanged layers come from the cache,
and nothing in `local/` is lost.

## Configuration reference

### install.yaml

`repo/defaults/install.yaml` and `local/config/install.yaml` use the same
schema. Lists are merged, and for `mcp` the local entry wins when a name appears
in both.

```yaml
build:                 # baked into the image
  apt:  [htop]
  brew: [gh]           # Homebrew on Linux (arm64 bottles available)
  npm:  [some-cli]     # npm install -g
  pip:  [httpie]       # Python CLIs, installed in isolation with `uv tool install`
runtime:               # applied when the container starts
  marketplaces: [owner/marketplace-repo]
  plugins:      [plugin-name@marketplace-name]
  skills:
    - git: https://github.com/owner/skills-repo
      path: skills/my-skill      # one skill, or a folder of skills
      ref: main                  # optional branch or tag
  mcp:                           # MCP servers, same shape as .mcp.json
    home-assistant:
      command: uvx
      args: [fastmcp-remote, "${HA_MCP_URL}"]
    github:
      type: http
      url: https://api.githubcopilot.com/mcp/
      headers:
        Authorization: Bearer ${GITHUB_TOKEN}
```

- **YAML, not JSON.** Don't put commas after values. If the file doesn't parse,
  the logs show `!! /config/install.yaml is not valid YAML …` and nothing is
  changed.
- **MCP servers.** They're written to Claude's user scope in
  `local/data/claude/.claude.json`. `${VAR}` placeholders are filled from
  `local/.env`, so secrets never go in `install.yaml`. If you remove a server from
  `install.yaml`, it's removed too. Servers added by hand with `claude mcp add`
  are left alone.
- **Local skills.** To add one, put a folder containing a `SKILL.md` in
  `local/config/skills/`. Shareable skills go in `repo/defaults/skills/`.
- **Tools available to MCP servers:** `npx`, `uvx`, `bun` and `brew`. Anything
  installed ad hoc inside the container is lost on rebuild, so declare it under
  `build:` instead.

### Environment options (`local/.env`)

| Variable | Default | Meaning |
| --- | --- | --- |
| `TZ` | `Europe/London` | Container time zone |
| `CLAUDE_CONTINUE` | `1` | Resume the previous conversation when Claude restarts |
| `CLAUDE_DAILY_RESET` | | `HH:MM` (container `TZ`): start a fresh conversation once a day, after 10 quiet minutes. Empty disables it. The template sets `04:00` |
| `CLAUDE_CHANNELS` | WhatsApp plugin | Space-separated channel plugins to load |
| `CLAUDE_AUTO_CONFIRM_CHANNELS` | `1` | Accept the development-channels warning automatically |
| `CLAUDE_REMOTE_CONTROL` | `1` | Enable Remote Control |
| `CLAUDE_REMOTE_CONTROL_NAME` | | Remote Control session name |
| `CLAUDE_CHROME` | `0` | Start with `--chrome` so Claude can drive the Chrome container |
| `CLAUDE_CHROME_PAIRED_DEVICE_ID` | | Pin Claude to one browser by its extension device id (see [Chrome](#chrome)) |
| `CLAUDE_EXTRA_ARGS` | | Extra arguments for `claude` |
| *anything else* | | Available to MCP `${VAR}` placeholders and to Claude's shell, for example `HA_MCP_URL` |

### Chrome options (`local/chrome.env`)

| Variable | Default | Meaning |
| --- | --- | --- |
| `TZ` | `Europe/London` | Chrome's time zone (keep it the same as yours) |
| `CHROME_MAC_UA` | `0` | Give Chrome a macOS user agent matching its real version (see the caveat in [Chrome](#chrome)) |
| `CHROME_CLI` | | Extra Chrome flags. Values can't contain spaces |
| `CUSTOM_USER`, `PASSWORD` | | Basic auth for the web desktop |
| `CHROME_PORT` | `3001` | Host port, set in your shell or `repo/.env` (not `chrome.env`) |

### Memory and settings

| File | Role |
| --- | --- |
| `repo/defaults/CLAUDE.md` | User memory: how to behave as a WhatsApp assistant, formatting, privacy |
| `local/config/CLAUDE.md` | Project memory (`/workspace/CLAUDE.md`): the people, their numbers, household context |
| `repo/defaults/settings.json` | Generic Claude settings, for example skipping the bypass-permissions prompt |
| `local/config/settings.json` | Your overrides, applied last |

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| "Channels are not currently available" | Not logged in. Attach, `/login`, then `/exit`. |
| WhatsApp keeps reconnecting, or "a second session attached" | Something else started the plugin's MCP server. Don't run `claude mcp list` or a second `claude` inside the container; use `/mcp` in the attached session instead. |
| New MCP server missing | Check `docker compose logs claude` for `!! … not valid YAML`. Otherwise `/exit` to re-sync. |
| `.env` change ignored | Run `docker compose up -d` (a restart doesn't reload env). |
| Session stuck on a prompt | Attach with `tmux attach -t claude` and answer it. |
| Claude forgot something from yesterday | The daily reset started a new conversation. Ask Claude to keep lasting facts in `/workspace` notes or `CLAUDE.md`, or clear `CLAUDE_DAILY_RESET`. |
| Claude says "Browser extension is not connected" | Open https://localhost:3001 and check that Chrome is running, the extension is installed and signed in to the same claude.ai account as Claude Code. If several browsers are connected, set `CLAUDE_CHROME_PAIRED_DEVICE_ID`. |
| Claude drove the Chrome on your Mac | Both browsers are signed in to the same account. Pin the container's browser with `CLAUDE_CHROME_PAIRED_DEVICE_ID`. |
| Extension missing from Chrome | It installs a few seconds after Chrome starts and needs access to the Chrome Web Store. Check `chrome://policy` in that Chrome for the `ExtensionSettings` policy. |
| Chrome says the profile is in use | Chrome didn't shut down cleanly. `docker compose restart chrome`. |
| Container unhealthy | The health check needs both the tmux session and a `claude` process. Check `docker compose logs claude`. |

## Security

- Claude runs with `--dangerously-skip-permissions`. The container is the
  sandbox: it can see only the mounted `local/` folders, and it has network
  access and passwordless `sudo` inside the container.
- Anyone on the WhatsApp allowlist can get Claude to run commands, so only
  allowlist people you trust.
- `CLAUDE_AUTO_CONFIRM_CHANNELS=1` accepts Claude Code's warning about running a
  channel plugin downloaded from the internet. Only list channel plugins you trust.
- Only one client can hold a WhatsApp link at a time. Don't run the plugin
  anywhere else with the same number.
- Secrets belong in `local/.env` and are referenced as `${VAR}`. Never put them
  in `repo/`.
- Whatever you log in to in Claude's Chrome, anyone on the WhatsApp allowlist can
  use through Claude. Log in only to accounts you're happy to share that way.
- The Chrome web desktop has no password by default and is published on
  `127.0.0.1` only. Set `CUSTOM_USER`/`PASSWORD` in `local/chrome.env` if other
  users share your Mac. The desktop has a terminal with passwordless `sudo`.
- Chrome runs with `--no-sandbox` (required in the container), so the container
  is the only isolation. Don't use it for general browsing.

## Chrome

The `chrome` service runs Google Chrome
([linuxserver/chrome](https://docs.linuxserver.io/images/docker-chrome/)) on a
desktop you open at https://localhost:3001. Its profile, including logins,
cookies and the extension, lives in `local/data/chrome`, so it survives rebuilds.
Claude drives it with the Claude in Chrome tools.

### How Claude reaches it

Claude Code and the extension each open a WebSocket to Anthropic's browser bridge
(`bridge.claudeusercontent.com`), authenticated with the same claude.ai account,
and the bridge pairs them. The containers don't need to reach each other, and
the Chrome container needs no Claude Code install. Claude Code chooses the
bridge itself; current versions don't offer a local-socket alternative.

Because pairing is by account, Chrome on your Mac is also a candidate if it's
signed in to the same account. Pin Claude to the container's browser, as in step 5
below.

### Setup

1. Start Chrome (it's part of `docker compose up -d`) and open
   https://localhost:3001. Accept the self-signed certificate.
2. The Claude extension is installed and pinned to the toolbar automatically.
   Click it and sign in with the same claude.ai account Claude Code uses.
3. Log in to any sites you want Claude to use. The logins persist.
4. Set `CLAUDE_CHROME=1` in `local/.env` and run `docker compose up -d`.
5. Pin the browser. In the Claude session, ask it to list connected browsers.
   Put the container Chrome's `deviceId` in `CLAUDE_CHROME_PAIRED_DEVICE_ID` in
   `local/.env`, then run `docker compose up -d`.

The extension is force-installed by a Chrome policy baked into the image
(`chrome/root/etc/opt/chrome/policies/managed/claude-extension.json`) and updates
itself from the Chrome Web Store. Because of that policy, Chrome shows "Managed by
your organization" and won't let you remove the extension. That's expected.

Claude runs with `--dangerously-skip-permissions`, so it doesn't ask before acting
in the browser. Sites you block in the extension's settings stay blocked.

### Looking less like a bot

This is a normal, headed Google Chrome with a persistent profile and real logins,
which already looks far more like a person than headless automation does.

`CHROME_MAC_UA=1` in `local/chrome.env` swaps the user agent string for a
macOS one with Chrome's real major version. It changes only that string:
`navigator.platform`, client hints and fonts still say Linux. Some bot detection
scores that mismatch as more suspicious than an honest Linux Chrome, so try each
setting on the sites you care about. Apply it with `docker compose up -d chrome`.
