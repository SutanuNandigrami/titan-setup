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
paths: "**/*.service,**/*.timer,**/systemd/**,**/supervisord*"
---

# Process Supervisor (systemd user units)

Manage persistent background processes without root.

## Setup
```bash
loginctl enable-linger $(whoami)
mkdir -p ~/.config/systemd/user/
```

## Service Template
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

## Management
```bash
systemctl --user daemon-reload              # after creating/editing units
systemctl --user start|stop|restart <name>  # control
systemctl --user enable <name>              # start on boot
systemctl --user status <name>              # check status
journalctl --user -u <name> -f             # follow logs
journalctl --user -u <name> --since today  # today's logs
systemctl --user list-units --type=service # list all

# Remove
systemctl --user disable <name> && systemctl --user stop <name>
rm ~/.config/systemd/user/<name>.service && systemctl --user daemon-reload
```

## Rules
1. Always `--user` — never system-level services
2. Use `%h` for home dir in unit files
3. Set `Restart=on-failure` for auto-recovery
4. Run `daemon-reload` after any unit file change
5. Check `journalctl --user -u <name>` for debugging
6. For one-off tasks, prefer `pueue`
