# claude-whatsapp: development notes

Claude Code + the WhatsApp channel plugin in Docker. See README.md for how it
works.

## Keep the README current (required)

README.md is the user manual. Any change that adds, removes or changes behaviour
must update README.md in the same commit:

- New or changed env var: update the table in "Environment options" and `.env.example`.
- New `install.yaml` key or merge behaviour: update "install.yaml" and
  `defaults/templates/install.yaml`.
- New script or startup step: update the diagram and "Startup sequence" in
  "How it works".
- Anything that changes what `/exit`, restart, `up -d` or `--build` picks up:
  update "When do changes take effect?".
- New failure mode found while debugging: add a row to "Troubleshooting".
- Browser container (`camoufox/`) change: update "Browser" and `camoufox.env.example`.

Before committing, re-read the README sections you touched against the code.

## Rules

- `repo/` must stay safe to publish. Never commit names, phone numbers, domains,
  tokens or anything from `../local/`. Secrets go in `local/.env` and are
  referenced as `${VAR}`.
- Scripts in `claude/scripts/` are baked into the image, so rebuild with
  `docker compose up -d --build` to test changes, and run
  `shellcheck -S warning claude/scripts/*.sh`.
- Don't run `claude mcp list` or a second `claude` inside the running container:
  it starts a second WhatsApp connection.
