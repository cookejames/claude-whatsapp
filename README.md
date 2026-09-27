# claude-whatsapp

Run Claude Code in Docker with the
[WhatsApp channel plugin](https://github.com/Rich627/whatsapp-claude-plugin), so
people can chat with Claude from WhatsApp.

Claude runs as a long-lived interactive session inside `tmux` in the container.
The WhatsApp plugin is a Claude Code *channel*, so incoming messages wake that
session. A loop restarts Claude if it exits.

## Layout

```
claude-whatsapp/
├── repo/     this git repository: generic, safe to publish
└── local/    your private config and state: never committed
```

| Path | Mounted at | What it holds |
| --- | --- | --- |
| `repo/defaults/` | `/opt/defaults` (baked in) | Default packages, plugins, CLAUDE.md, settings |
| `local/config/` | `/config` | Your `install.yaml`, `CLAUDE.md`, `settings.json`, `skills/` |
| `local/data/claude/` | `~/.claude` | Claude login, plugins, conversations |
| `local/data/whatsapp/` | `~/.whatsapp-channel` | WhatsApp link, allowlist, inbox |
| `local/workspace/` | `/workspace` | Claude's working directory and notes |
| `local/.env` | env vars | `TZ`, `CLAUDE_*` options (see `.env.example`) |

To keep `local/` somewhere else, set `LOCAL_DIR=/path/to/local`, either in your
shell or in a gitignored `repo/.env`.

## First run

Requires Docker Desktop (or another Docker engine with Compose v2.24+), a
Claude Pro or Max plan, and a spare WhatsApp number for Claude.

```bash
cd repo
claude/scripts/init-local.sh          # creates ../local from templates
$EDITOR ../local/config/CLAUDE.md     # who the users are
docker compose up -d --build
docker compose exec claude tmux attach -t claude
```

In the Claude session:

1. `/login` and sign in with your Claude account. Credentials persist in
   `local/data/claude`. Don't use `claude setup-token`, because Chrome
   integration needs a full login.
2. `/whatsapp-channel:configure 447700900123`: the bot's number with country
   code and no `+`. On the bot phone, go to **Settings → Linked devices → Link a
   device → Link with phone number instead** and enter the code shown.
3. `/whatsapp-channel:access` to allowlist the numbers that may talk to Claude.

Detach with `Ctrl-b d`. Claude keeps running.

## Day-to-day

| Task | Command |
| --- | --- |
| Watch or talk to the session | `docker compose exec claude tmux attach -t claude` |
| Logs (startup, installs) | `docker compose logs -f claude` |
| Apply `runtime:` / CLAUDE.md / settings changes | `docker compose restart claude` |
| Apply `build:` package changes, update Claude | `docker compose up -d --build` |
| Shell in the container | `docker compose exec claude bash` |

## Installing things

`repo/defaults/install.yaml` and `local/config/install.yaml` share one schema,
and their lists are merged:

```yaml
build:                 # baked into the image (rebuild to apply)
  apt:  [htop]
  brew: [gh]
  npm:  [some-cli]
  pip:  [httpie]       # installed as isolated tools with `uv tool install`
runtime:               # applied at every container start (restart to apply)
  marketplaces: [owner/marketplace-repo]
  plugins:      [plugin-name@marketplace-name]
  skills:
    - git: https://github.com/owner/skills-repo
      path: skills/my-skill      # one skill, or a folder of skills
      ref: main                  # optional
```

To add local skills, drop a folder containing a `SKILL.md` into
`local/config/skills/`. Shareable skills go in `repo/defaults/skills/`.

## Settings and memory

- `~/.claude/settings.json` is rebuilt at start in three layers: what Claude saved
  itself, then `defaults/settings.json`, then `local/config/settings.json`.
  Later layers win.
- `defaults/CLAUDE.md` is Claude's user memory and holds generic WhatsApp
  behaviour. `local/config/CLAUDE.md` is linked as `/workspace/CLAUDE.md` and
  holds your people and household context.

## Environment options (`local/.env`)

| Variable | Default | Meaning |
| --- | --- | --- |
| `TZ` | `Europe/London` | Container time zone |
| `CLAUDE_CONTINUE` | `1` | Resume the last conversation after a restart |
| `CLAUDE_CHANNELS` | WhatsApp plugin | Space-separated channel plugins to load |
| `CLAUDE_AUTO_CONFIRM_CHANNELS` | `1` | Accept the development-channels warning automatically on start |
| `CLAUDE_REMOTE_CONTROL` | `1` | Enable Remote Control (open the session from claude.ai or the Claude app) |
| `CLAUDE_REMOTE_CONTROL_NAME` | | Remote Control session name |
| `CLAUDE_CHROME` | `0` | Start with `--chrome` (phase 2) |
| `CLAUDE_EXTRA_ARGS` | | Extra `claude` arguments |

## Security notes

- Claude runs with `--dangerously-skip-permissions`. The container is the
  sandbox: it can only reach the mounted `local/` folders and the network.
- Anyone on the allowlist can make Claude run commands in the container, so
  only allowlist people you trust.
- Only one client can hold a WhatsApp link at a time. Don't run the plugin
  anywhere else with the same number.

## Phase 2: Chrome (planned)

`docker-compose.yml` has a commented-out `chrome` service
(`lscr.io/linuxserver/chrome`) that you can view over web VNC on
`localhost:3000`. The goal is for Claude to drive it through the Claude in Chrome
extension. The extension's native-messaging Unix socket would be shared with the
`claude` container over a shared volume, or relayed with socat as in
[claude-code-remote-chrome](https://github.com/vaclavpavek/claude-code-remote-chrome).
