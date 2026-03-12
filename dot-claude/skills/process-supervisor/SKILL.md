---
description: Manage long-running processes with systemd user units — dev servers, daemons, watchers
triggers:
  - systemd
  - service
  - keep running
  - daemon
  - supervisor
  - background service
  - auto restart
  - user unit
paths: ["**/*.service", "**/*.timer", "**/systemd/**", "**/supervisord*"]
---

# Process Supervisor (systemd user units)

Manage persistent background processes without root using systemd user units.

## Setup
```bash
# Enable lingering (services run even when logged out)
loginctl enable-linger $(whoami)

# Unit files go here
mkdir -p ~/.config/systemd/user/
```

## Creating a Service

### Template
```ini
# ~/.config/systemd/user/<name>.service
[Unit]
Description=<description>
After=network.target

[Service]
Type=simple
ExecStart=<command>
Restart=on-failure
RestartSec=5
WorkingDirectory=%h/<project-dir>
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
```

### Example: Dev Server
```ini
[Unit]
Description=Next.js Dev Server
After=network.target

[Service]
Type=simple
ExecStart=/home/user/.bun/bin/bun dev
WorkingDirectory=%h/projects/my-app
Restart=on-failure

[Install]
WantedBy=default.target
```

### Example: File Watcher
```ini
[Unit]
Description=Auto-lint on file change

[Service]
Type=simple
ExecStart=/usr/bin/inotifywait -m -r -e modify --format '%%w%%f' src/ | while read f; do ruff check "$f" --fix 2>/dev/null; done
WorkingDirectory=%h/projects/my-app
Restart=on-failure

[Install]
WantedBy=default.target
```

## Management Commands
```bash
# Reload after creating/editing units
systemctl --user daemon-reload

# Start/stop/restart
systemctl --user start <name>
systemctl --user stop <name>
systemctl --user restart <name>

# Enable on boot
systemctl --user enable <name>

# Check status and logs
systemctl --user status <name>
journalctl --user -u <name> -f        # follow logs
journalctl --user -u <name> --since today

# List all user units
systemctl --user list-units --type=service

# Disable and remove
systemctl --user disable <name>
systemctl --user stop <name>
rm ~/.config/systemd/user/<name>.service
systemctl --user daemon-reload
```

## Rules
1. Always use `--user` flag — never create system-level services.
2. Use `%h` for home directory in unit files (expands automatically).
3. Set `Restart=on-failure` for services that should auto-recover.
4. Use `WorkingDirectory` to set the correct project path.
5. Run `daemon-reload` after any unit file changes.
6. Check `journalctl --user -u <name>` for debugging.
7. For one-off tasks, prefer `pueue` over systemd.
