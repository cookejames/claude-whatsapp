# claude-whatsapp

Is OpenClaw or Hermes just too heavyweight for your needs but you still want to 
chat to Claude over WhatsApp? This is a very simple bridge runs Claude CLI in a
docker and bridges WhatsApp to it. 

The motivation is simple, OpenClaw or Hermes are complex, frequently changing,
and breaking projects. My needs are much simpler and on the desktop Claude can 
now handle most of them. I wanted to share that setup with my wife and family to
answer practical problems such as grab a recipe from our family notion database
and add it to our online shopping basket. This does that while keeping Claude in
a safe docker all of its own alongside a browser (Camoufox) so that it only has 
access to volumes shared with it and no other credentials. The agent has its own
WhatsApp number and it will only respond to people or in groups that have been 
whitelisted.

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
- [Browser](#browser)
- [Google Workspace](#google-workspace)
- [Backups](#backups)

## How it works

```
 WhatsApp (phones)
        │  Baileys / WhatsApp Web protocol, linked as a device on the bot's number
        ▼
┌──────────────────────── container: claude-whatsapp ─────────────────────────┐
│ tini → entrypoint.sh                                                         │
│          ├─ prepares ~/.claude from defaults + /config                       │
│          ├─ runtime-install.sh (marketplaces, plugins, skills, MCP)          │
│          ├─ whisper model download (background)                              │
│          ├─ cron daemon ← /config/crontab ─┐                                 │
│          └─ tmux session "claude" ◀────────┘ claude-prompt.sh                │
│               └─ run-claude.sh (restart loop)                                │
│                    ├─ sync-mcp.sh          (before every launch)             │
│                    ├─ auto-confirm dev-channels warning                      │
│                    ├─ daily reset watcher  (CLAUDE_DAILY_RESET)              │
│                    └─ claude --dangerously-skip-permissions                  │
│                              --dangerously-load-development-channels …       │
│                              --remote-control [name] [--continue]            │
│                         ├─ whatsapp-channel MCP server (Bun)                 │
│                         │    └─ ~/whisper-transcribe.sh (voice notes)        │
│                         └─ browser MCP client ─────────────────────┐         │
└────────────────────────────────────────────────────────────────────┼─────────┘
        ▲                                   ▲                        │ HTTP, private
        │ tmux attach                       │ Remote Control         │ network only
   you, in a terminal                claude.ai/code or the           ▼
                                     Claude app
┌──────────────────────── container: claude-whatsapp-camoufox ─────────────────┐
│ web desktop (Selkies)                                                        │
│   └─ browser-session → Playwright MCP (:8931) → Camoufox                     │
│                        fixed fingerprint, persistent profile                 │
└──────────────────────────────────────────────────────────────────────────────┘
        ▲
        │ https://localhost:3002 (this Mac only)
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
2. Marks onboarding complete and `/workspace` as trusted in `.claude.json`, so
   no first-run screens block the session.
3. Rebuilds `settings.json` from three layers: what Claude saved itself, then
   `defaults/settings.json`, then `local/config/settings.json`. Later layers win.
4. Links the memory files: `defaults/CLAUDE.md` becomes Claude's user memory, and
   `local/config/CLAUDE.md` becomes `/workspace/CLAUDE.md`, the project memory.
5. Links skills from `defaults/skills/` and `local/config/skills/`.
6. Runs `runtime-install.sh` to add marketplaces, install plugins, clone and pull
   git skills, and sync MCP servers.
7. Starts downloading the voice transcription model in the background, if it
   isn't cached yet (see *Voice notes* below).
8. Sets the system time zone from `TZ`, loads `local/config/crontab` as user
   `claude`'s crontab and starts cron (see *Scheduled jobs* below).
9. Starts `run-claude.sh` in tmux session `claude`, then waits in the foreground
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

**Voice notes.** The plugin transcribes each incoming voice note by running
`~/whisper-transcribe.sh <file>`, and Claude receives the text with the audio
attached. In this image that script runs
[faster-whisper](https://github.com/SYSTRAN/faster-whisper) on the CPU, entirely
inside the container: no audio leaves your Mac. (The plugin's own reference
script uses mlx-whisper, which needs macOS on Apple Silicon and can't run in a
Linux container.) The default model, `large-v3-turbo` (about 1.6 GB, cached in
`local/data/whisper/`), is multilingual and transcribes at roughly real-time
speed, so a 30-second note takes about 30 seconds. Set `WHISPER_MODEL=small` for
about 4× faster but less accurate transcription. A note that takes longer than
`WHISPER_TIMEOUT_MS` (180 s by default) to transcribe arrives as plain audio. To
test it:

```bash
docker compose exec claude whisper-transcribe.sh /path/to/note.ogg
```

**Scheduled jobs.** `local/config/crontab` holds recurring jobs, in the
container's `TZ`. It's a normal crontab (the template has an example) and is
loaded when the container starts, so jobs survive restarts and rebuilds, unlike
Claude's own `CronCreate` jobs, which end with the session. A job can run any
command, and `claude-prompt.sh '<prompt>'` types a prompt into the running
session so Claude does the work with all its tools, MCP servers and WhatsApp:

```
0 6 * * 6 claude-prompt.sh 'Write the weekly summary and send it to Sam on WhatsApp.'
```

The prompt arrives as if typed at the terminal: if Claude is busy it's queued,
and if Claude is restarting the script waits up to 10 minutes. Say in the prompt
who the result is for, since it doesn't come from a WhatsApp chat. Each prompt
sent is logged in `local/data/claude/cron.log`. To apply an edited crontab
without restarting:

```bash
docker compose exec claude crontab /config/crontab
```

**Browser.** A second container runs Camoufox, a Firefox build that presents a
consistent, realistic device fingerprint, on a desktop you view in your browser.
Claude drives it through the Playwright MCP server in that container. See
[Browser](#browser).

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
│   ├── camoufox.env.example     documents the browser container's options
│   ├── claude/
│   │   ├── Dockerfile           Debian + Homebrew, Node, Bun, uv, tmux, Claude Code
│   │   └── scripts/             entrypoint, installers, restart loop, MCP sync
│   ├── camoufox/
│   │   ├── Dockerfile           web desktop + Camoufox + Playwright MCP
│   │   └── root/                browser-session and browser-mcp.py launchers
│   ├── backup/                  daily S3 backup of local/ (runs on the Mac, not in Docker)
│   └── defaults/                baked into the image at /opt/defaults
│       ├── install.yaml         base packages, WhatsApp marketplace and plugin
│       ├── CLAUDE.md            generic WhatsApp assistant behaviour
│       ├── settings.json
│       ├── skills/              shareable skills
│       └── templates/           starting files for local/config
└── local/                       private: never committed
    ├── .env                     options and secrets → claude container env vars
    ├── camoufox.env             browser container options (never sees .env)
    ├── config/        → /config           install.yaml, CLAUDE.md, settings.json, crontab, skills/
    ├── data/claude/   → ~/.claude         login, plugins, MCP config, conversations
    ├── data/whatsapp/ → ~/.whatsapp-channel   WhatsApp link, allowlist, inbox
    ├── data/gws/      → ~/.config/gws     Google Workspace CLI OAuth client and login
    ├── data/whisper/  → ~/.cache/whisper  voice transcription models
    ├── data/ssh/      → ~/.ssh            SSH known_hosts and config (keep keys in workspace/.secrets)
    ├── data/camoufox/ → browser /config   desktop settings; browser/ holds the
    │                                      profile (logins, cookies) and fingerprint
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
   Remote Control need a full login.
6. Run `/whatsapp-channel:configure 447700900123`, using the bot's number with
   country code and no `+`. On the bot phone, go to **Settings → Linked devices →
   Link a device → Link with phone number instead** and enter the code shown.
7. Run `/whatsapp-channel:access` to allowlist the numbers that may talk to Claude.
8. Detach with `Ctrl-b d`. Claude keeps running.
9. Log in to the sites Claude should use in the [Browser](#browser).

## Everyday use

| Task | How |
| --- | --- |
| Talk to Claude | Message the bot's WhatsApp number |
| Open the session in a browser or the app | Remote Control: look for the session in claude.ai/code or the Claude app |
| Open the session in a terminal | `docker compose exec claude tmux attach -t claude`, detach with `Ctrl-b d` |
| Restart just Claude | Type `/exit` in the session |
| See startup and install logs | `docker compose logs -f claude` |
| Get a shell in the container | `docker compose exec claude bash` |
| See or use Claude's browser | Open https://localhost:3002 (accept the self-signed certificate) |
| Update Claude Code | `docker compose build --no-cache && docker compose up -d` (the auto-updater is off) |
| Stop or start everything | `docker compose down` / `docker compose up -d` |

## When do changes take effect?

| You changed… | `/exit` | `docker compose restart claude` | `docker compose up -d` | `docker compose up -d --build` |
| --- | :-: | :-: | :-: | :-: |
| `install.yaml` → `runtime.mcp` | ✓ | ✓ | ✓ | ✓ |
| `crontab` (or run `crontab /config/crontab` in the container) | | ✓ | ✓ | ✓ |
| `install.yaml` → other `runtime` (plugins, skills), `settings.json`, skills folders | | ✓ | ✓ | ✓ |
| `CLAUDE.md` files | ✓\* | ✓ | ✓ | ✓ |
| `local/.env` | | | ✓ (recreates) | ✓ |
| `local/camoufox.env` | | | ✓ (recreates the browser) | ✓ |
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
- **Git skills.** Each entry clones the repo into `local/data/claude/skill-repos/`
  (once per run, however many entries share it) and links the skill into
  `~/.claude/skills`. For a repo with many skills, list one entry per skill you
  want, as in [Google Workspace](#google-workspace).
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
| `CLAUDE_EXTRA_ARGS` | | Extra arguments for `claude` |
| `GWS_SCOPES` | Gmail read-only | Comma-separated OAuth scope URLs that `gws-login.sh` requests (see [Google Workspace](#google-workspace)) |
| `WHISPER_MODEL` | `large-v3-turbo` | faster-whisper model for voice notes, e.g. `small`, `medium`, `distil-large-v3` (English only). A new model downloads when the container starts |
| `WHISPER_LANGUAGE` | | Language code such as `en`. Empty detects it from each note |
| `WHISPER_TIMEOUT_MS` | `180000` | Read by the plugin: how long a transcription may take before the note arrives untranscribed |
| `TRANSCRIPTION_PROVIDER` | `local` | Read by the plugin: `groq` or `openai` sends voice notes to that cloud API instead (with `GROQ_API_KEY` or `OPENAI_API_KEY`) |
| *anything else* | | Available to MCP `${VAR}` placeholders and to Claude's shell, for example `HA_MCP_URL` |

### Browser options (`local/camoufox.env`)

| Variable | Default | Meaning |
| --- | --- | --- |
| `TZ` | `Europe/London` | The browser's time zone (keep it the same as yours) |
| `BROWSER_OS` | `macos` | Fingerprint OS: `macos`, `windows` or `linux`. Used only when the fingerprint is first created |
| `BROWSER_LOCALE` | `en-GB` | Fingerprint locale. Used only when the fingerprint is first created |
| `BROWSER_PASSWORD_MANAGER` | `1` | Let Firefox save and fill site passwords. Camoufox turns this off by default |
| `BROWSER_START_URL` | `about:home` | Page opened when the container starts |
| `SELKIES_MANUAL_WIDTH`, `SELKIES_MANUAL_HEIGHT` | 1920×1080 in the template | Fixed desktop size. Unset, it follows the size of the window you view it in |
| `CUSTOM_USER`, `PASSWORD` | | Basic auth for the web desktop |
| `BROWSER_PORT` | `3002` | Host port, set in your shell or `repo/.env` (not `camoufox.env`) |

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
| Browser window closed or missing | Ask Claude to open any page, or run `docker compose restart camoufox`. |
| Browser tools fail with "Failed to launch the browser" | The profile is locked or the browser crashed. `docker compose restart camoufox`, and check `docker compose logs camoufox`. |
| A site starts blocking the browser | Delete that site's cookies in the browser and retry. If it persists, a new fingerprint may help: delete `local/data/camoufox/browser/fingerprint.json` and restart (sites will see a new device). |
| `gws` says it isn't logged in, or `invalid_grant` | The login was revoked or expired, or the scopes changed. Run `docker compose exec -it claude gws-login.sh` again. |
| `gws-login.sh` hangs after pasting the URL | The pasted address must be the whole `http://localhost:…/?code=…` URL from the same login attempt. Run the script again and use the new URL. |
| Sign-in fails with `Error 400: invalid_scope` naming a Keep scope | Google doesn't allow Keep scopes through a user sign-in; the Keep API only works with a Workspace service account and domain-wide delegation. Remove the Keep scope from `GWS_SCOPES`. |
| Voice notes arrive as audio with no transcript | Run `docker compose exec claude whisper-transcribe.sh <file>` on a note and read the error. Check `docker compose logs claude` for `whisper model ready`, and `~/.whatsapp-channel/diag.log` for `whisper transcription failed` (a timeout means the note was too long for the model: raise `WHISPER_TIMEOUT_MS` or use a smaller `WHISPER_MODEL`). |
| A scheduled job didn't run | Check `docker compose exec claude crontab -l` shows it and `docker compose logs claude` has `crontab loaded` (not `!! /config/crontab is not valid`). Times follow `TZ`. Cron keeps no output, so test the command by hand in `docker compose exec claude bash`; for `claude-prompt.sh` jobs, check `local/data/claude/cron.log`. |
| Container unhealthy | The health check needs both the tmux session and a `claude` process. Check `docker compose logs claude`. |
| Backup log says "no access key in Keychain" | `backup/setup.sh` hasn't run, or the Keychain item was deleted. Run `backup/setup.sh` again; it creates a new key if none is stored. |
| Backup fails with `AccessDenied` | The stored key was deleted or deactivated in IAM, or the `local/` prefix was changed. Delete the Keychain items (`security delete-generic-password -s claude-whatsapp-backup -a access-key-id`, then `-a secret-access-key`), remove the old key in IAM, and run `backup/setup.sh`. |

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
- The Google Workspace login gives Claude your account's access for the granted
  scopes. Per-person rules (who may read mail, whose calendar new events go
  to) are instructions in `local/config/CLAUDE.md`, not limits Google enforces,
  because everyone's requests run through one login. Emails, invites and notes
  are untrusted input. The login and its encryption key are in `local/data/gws`.
- Secrets belong in `local/.env` and are referenced as `${VAR}`. Never put them
  in `repo/`.
- Whatever you log in to in Claude's browser, anyone on the WhatsApp allowlist
  can use through Claude. Log in only to accounts you're happy to share that way.
- The browser desktop has no password by default and is published on
  `127.0.0.1` only. Set `CUSTOM_USER`/`PASSWORD` in `local/camoufox.env` if other
  users share your Mac. The desktop has a terminal with passwordless `sudo`.
- Saved passwords are in the profile (`local/data/camoufox/browser/profile`),
  encrypted with a key stored next to them, because there's no primary password
  (one would lock the browser after every restart until you typed it). Anyone who
  can read that folder can recover them, so keep FileVault on and don't sync it
  to cloud storage.
- The Playwright MCP endpoint (`camoufox:8931`) has no authentication. It's only
  on the private compose network and isn't published to the Mac; keep it that way.

## Browser

The `camoufox` service runs [Camoufox](https://github.com/daijro/camoufox), a
Firefox build for automation that presents a realistic, self-consistent device
fingerprint (platform, GPU, screen, fonts and so on), on a desktop you open at
https://localhost:3002. Claude drives it with the Playwright MCP server
([@playwright/mcp](https://github.com/microsoft/playwright-mcp)) running in the
same container, which the `claude` container reaches at
`http://camoufox:8931/mcp` as the `browser` MCP server (declared in
`defaults/install.yaml`).

### Why Camoufox

Sites with strict bot management (Tesco's Akamai check, for example) block a
stock Chrome in Docker even when a person logs in by hand: with no GPU, Arm
hardware and few fonts, the environment itself looks automated. Camoufox fakes
those properties inside the browser engine, where page scripts can't see the
change, and hides the automation protocol from the page. It still isn't
guaranteed; if a site blocks it, see Troubleshooting.

### How it works

- `browser-session` runs from the desktop's autostart. It keeps
  `browser-mcp.py` running and opens the browser at `BROWSER_START_URL`, so the
  window is there for you to use even before Claude has.
- `browser-mcp.py` starts Playwright MCP pointed at the Camoufox binary. On first
  run it generates a fingerprint for `BROWSER_OS` and `BROWSER_LOCALE` and saves
  it to `local/data/camoufox/browser/fingerprint.json`. Every later start reuses
  it, so sites always see the same device.
- The profile (`local/data/camoufox/browser/profile`) keeps logins, cookies and
  saved passwords across restarts and rebuilds.
- Every MCP connection shares that one browser (`--shared-browser-context`), so
  Claude restarting doesn't open a second browser.
- Camoufox ships with Firefox's password manager disabled by policy. With
  `BROWSER_PASSWORD_MANAGER=1`, `browser-mcp.py` re-enables it on each start
  (the `PasswordManagerEnabled` and `OfferToSaveLogins` policies, plus the
  `signon.*` prefs in the profile's `user.js`).
- Camoufox and Playwright MCP are pinned in `camoufox/Dockerfile`
  (`CAMOUFOX_VERSION`, `PLAYWRIGHT_MCP_VERSION`). Upgrade them together and
  test, since Playwright and Camoufox must stay compatible.

### Logging in to sites

1. Open https://localhost:3002 and accept the self-signed certificate.
2. Log in to each site by hand, ticking "keep me signed in" where offered.
3. If a site logs you out often, let Firefox save the password when it offers,
   or choose "Never save" for sites Claude shouldn't be able to log in to.
   Firefox fills the login form itself, so Claude clicks "Sign in" without ever
   seeing the password.
4. Tell Claude what the site is for. If it later needs a login, a 2FA code or a
   human check, it asks you on WhatsApp to do it on this desktop.

You can use the desktop while Claude isn't browsing. Avoid clicking around while
Claude is working, since you'd both be driving the same window.

## Google Workspace

The [Google Workspace CLI](https://github.com/googleworkspace/cli) (`gws`) gives
Claude Gmail, Calendar and the other Workspace APIs from the shell, and
its [agent skills](https://github.com/googleworkspace/cli/blob/main/docs/skills.md)
teach Claude how to use it. It's optional: declare it in
`local/config/install.yaml`.

```yaml
build:
  npm:
    - "@googleworkspace/cli@0.22.5"
runtime:
  skills:   # one entry per skill you want; the repo is cloned once
    - {git: https://github.com/googleworkspace/cli, path: skills/gws-shared}
    - {git: https://github.com/googleworkspace/cli, path: skills/gws-gmail}
    - {git: https://github.com/googleworkspace/cli, path: skills/gws-calendar}
```

Pick skills that match the scopes you grant, and leave out ones Claude shouldn't
use (for example `gws-gmail-send` if it may only draft). `gws-shared` is needed
by all of them.

### One-time Google Cloud setup

1. In the [Google Cloud Console](https://console.cloud.google.com/), create a
   project (under your Workspace organisation if you have one).
2. Enable the APIs you'll use, for example the Gmail API and Google Calendar API.
   (Google Keep isn't available this way: its scopes can't be granted by a user
   sign-in.)
3. Configure the OAuth consent screen. With Google Workspace choose **Internal**:
   no verification, and logins don't expire. With a personal Gmail account it has
   to be **External**; add yourself as a test user and set the app to **In
   production**, because logins made in Testing mode expire after 7 days.
4. Create an OAuth client ID of type **Desktop app** and download its JSON as
   `local/data/gws/client_secret.json`.

### Logging in

Set `GWS_SCOPES` in `local/.env` (full scope URLs, comma-separated; see
`.env.example`), run `docker compose up -d`, then:

```bash
docker compose exec -it claude gws-login.sh
```

It prints a Google sign-in URL. Open it on the Mac and approve. Google then
redirects to a `http://localhost:…` page that fails to load: `gws` is waiting
for it inside the container, where the Mac's browser can't reach. Copy that
whole address, paste it into the script, and it completes the login. The login is
kept (encrypted, with a file-based key since the container has no keyring) in
`local/data/gws` and survives rebuilds.

To change what Claude may do, edit `GWS_SCOPES`, recreate the container
(`docker compose up -d`) and run `gws-login.sh` again. Adjust the skills and
your `CLAUDE.md` rules to match.

### Drafts without sending

Gmail has no scope for drafts that doesn't also allow sending (`gmail.compose`
covers both). To keep Claude to drafts, add deny rules for the sending commands
to `local/config/settings.json`. Claude Code enforces deny rules even with
`--dangerously-skip-permissions`:

```json
{
  "permissions": {
    "deny": [
      "Bash(gws gmail +send:*)", "Bash(gws gmail +reply:*)",
      "Bash(gws gmail +reply-all:*)", "Bash(gws gmail +forward:*)",
      "Bash(gws gmail users messages send:*)", "Bash(gws gmail users drafts send:*)"
    ]
  }
}
```

They match command prefixes, so they're a guardrail against mistakes, not a
security boundary: a determined workaround (a script, another tool) could still
send. Say in your `CLAUDE.md` that Claude must never send, too.

## Backups

`backup/` copies `local/` to a private S3 bucket once a day. The bucket keeps
every version of every file for 30 days, so you can restore a file as it was on
any recent day, or see how a skill changed. It runs on the Mac through launchd,
not in Docker. The containers never get the bucket name or the keys, and the
`backup/` folder is kept out of the image.

What it covers: everything in `local/` (`.env`, `config/`, `data/`,
`workspace/`) except caches that rebuild themselves, which are listed in
`backup/excludes.txt` (the browser cache and the voice transcription models). Files are stored one object per
file, uncompressed, and encrypted at rest by S3 (SSE-S3). Uploads use TLS only.

| Piece | What it does |
| --- | --- |
| `backup-infra.yaml` | CloudFormation: versioned bucket `claude-whatsapp-backup-<account id>` with public access blocked, and an IAM user that can only list, read and write under `local/`. That user can't delete old versions or change the bucket, so a leaked key can't erase the history. |
| `setup.sh` | Deploys the stack with your admin AWS credentials, writes `backup/backup.env` (gitignored), stores the backup user's access key in the macOS Keychain (service `claude-whatsapp-backup`), and schedules `backup.sh` daily at 02:00. Safe to re-run. |
| `backup.sh` | `aws s3 sync --delete` of `local/` using only the Keychain key. Only changed files upload. A deleted file gets a delete marker and its earlier versions stay. Logs to `~/Library/Logs/claude-whatsapp-backup.log`. |

Set up (needs the AWS CLI and an admin login, e.g. `aws login`):

```bash
backup/setup.sh      # deploy, store the key, schedule
backup/backup.sh     # first backup now
```

A missed 02:00 run happens when the Mac next wakes. To run it on demand later:
`launchctl kickstart gui/$(id -u)/local.claude-whatsapp.backup`.

Restore (with your admin credentials):

```bash
# Everything, latest versions
aws s3 sync s3://<bucket>/local/ ./restored-local/

# One file's history, then a specific version
aws s3api list-object-versions --bucket <bucket> --prefix local/config/skills/<skill>/SKILL.md \
  --query 'Versions[].[LastModified,VersionId]' --output text
aws s3api get-object --bucket <bucket> --key local/config/skills/<skill>/SKILL.md \
  --version-id <id> SKILL.md
```

You can also browse versions in the S3 console with "Show versions".
`aws s3 sync` doesn't keep file permissions, symlinks or empty folders. It
spots changes by size and timestamp, not by content.

Cost: under a few cents a month for a few hundred MB plus 30 days of old
versions. To change how long old versions are kept, set `BACKUP_RETENTION_DAYS`
in `backup/backup.env` and run `backup/setup.sh` again.
