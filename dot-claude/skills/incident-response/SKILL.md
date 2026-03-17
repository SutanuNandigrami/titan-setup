---
name: incident-response
description: Structured incident response workflow, evidence collection, and forensic CLI commands. Use when investigating security incidents, breaches, or anomalies.
paths: ["**/incident*", "**/runbook*", "**/playbook*", "**/ir/**", "**/*-runbook*", "**/*_incident*"]
---

# Incident Response Workflow

## Phases (in order — do NOT skip)

1. **Detect** → Confirm alert is real, note exact timestamp + timezone, scope (host/service/account)
2. **Contain** → Stop spread, preserve evidence — **NEVER reboot**
3. **Collect** → Logs, processes, network state, file hashes
4. **Investigate** → Root cause, attack vector, what was accessed
5. **Eradicate** → Remove attacker, patch, rotate ALL credentials
6. **Recover** → Restore from clean backup, re-harden, verify
7. **Review** → Timeline doc, root cause, action items with owner + deadline

## Contain (Phase 2)

```bash
# FIRST: Snapshot before any changes
virsh snapshot-create-as <vm> before-incident

# Isolate at firewall (don't stop services — preserves volatile state)
sudo iptables -A INPUT -s <attacker-ip> -j DROP
sudo iptables -A OUTPUT -d <attacker-ip> -j DROP
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# Revoke access
passwd -l <compromised-user>           # Lock account
loginctl list-sessions                 # See active sessions
loginctl terminate-user <username>     # Force logout
```

## Evidence Collection (Phase 3)

### Logs

```bash
lnav /var/log/auth.log                                              # SSH + sudo
grep "FAILED\|Invalid" /var/log/auth.log | sort | uniq -c | sort -rn
journalctl -b -p err                                                # Errors since boot
journalctl -n 1000 -u <service>                                     # Service logs
journalctl -S "2 hours ago" -p warning                              # Recent warnings+
find /var/log -name "*.log" -mtime -1                               # Logs changed today
```

### Processes

```bash
procs --tree                                      # Full process tree
ss -tlnp                                          # Listening ports + owning PID
lsof -p <pid>                                     # Files + sockets by PID
cat /proc/<pid>/cmdline | tr '\0' ' '             # Full command (binary-safe)
cat /proc/<pid>/environ | tr '\0' '\n'            # Process environment
strings /proc/<pid>/exe | grep -i "password\|secret"  # Hardcoded creds
```

### Network State

```bash
ss -antp                                # All TCP + PIDs
ss -anup                                # All UDP
ss -tulnp                               # Listening only
netstat -rn                             # Routing table
arp -a                                  # ARP cache (lateral movement clues)
tcpdump -i eth0 -w /tmp/capture.pcap "host <attacker-ip>"  # Start packet capture
```

### File Integrity

```bash
sudo aide --check                                          # Compare against baseline
find / -newer /tmp/timestamp -type f 2>/dev/null           # Files modified since marker
sha256sum /usr/bin/ssh /usr/bin/sudo /usr/bin/bash         # Verify critical binaries
debsums -c                                                 # Verify Debian packages
find / -perm -002 -type f 2>/dev/null | grep -v "/proc\|/sys\|/tmp"  # World-writable files
```

### Cloud-Specific

```bash
# AWS CloudTrail
aws cloudtrail lookup-events --max-results 50 | jq '.Events[] | {Time, EventName, Username}'

# GCP Audit Logs
gcloud logging read "resource.type=gce_instance" --limit 100 --format json

# Azure Activity Log
az monitor activity-log list --offset 6h --query "[].{time:eventTimestamp, operation:operationName}"
```

## Investigate (Phase 4)

**Answer these first:**
- Attack vector? (phishing / public exploit / weak password / supply chain / insider)
- What access gained? (user shell / root / data read / exfil capability)
- What systems touched? (lateral movement — check auth.log across all hosts)
- What data accessed? (DB logs, file access, S3 object logs)

```bash
last -F <username>                     # Login history with timestamps
ausearch -ua <uid> -i                  # All audit events for uid (auditd)
# Build timeline:
grep "Mar 17 14:" /var/log/auth.log | sort -k3 > timeline.txt
```

## Eradicate (Phase 5)

```bash
sudo clamscan -r / --infected --log=/tmp/clamscan.log  # Malware scan
sudo rkhunter --check --skip-warnings                  # Rootkit check
sudo chkrootkit                                        # Alternative

# Rotate ALL credentials (not just compromised ones):
# SSH keys, DB passwords, API tokens, JWT secrets, service account keys
```

## Network Forensics (Packet Capture)

```bash
tshark -r capture.pcap -T fields -e ip.src -e ip.dst -e tcp.dstport | sort | uniq
tshark -r capture.pcap -q -z follow,tcp,ascii,0       # Follow TCP stream
tshark -r capture.pcap -Y http -T fields -e http.cookie  # HTTP cookies
```

## Forensic CLI Reference

| Task | Command |
|------|---------|
| Log tailing | `lnav /var/log/<file>` |
| Process tree | `procs --tree` |
| Open files | `lsof -p <pid>` |
| Network state | `ss -antp` |
| File changes | `find / -newer /timestamp -type f` |
| Binary verify | `sha256sum <binary>` |
| File integrity | `sudo aide --check` |
| Malware scan | `sudo clamscan -r /` |
| Login history | `last -F <user>` |
| Packet capture | `tcpdump -i eth0 -w cap.pcap` |
| PCAP analysis | `tshark -r cap.pcap` |

## Rules

- **NEVER reboot** during active incident — volatile RAM/swap forensics lost
- **NEVER delete evidence** — logs and snapshots are legal evidence
- **ALWAYS snapshot** before any cleanup (VM snapshot or disk image)
- **ALWAYS document** exact timestamps with timezone (not "around 3pm")
- **ALWAYS rotate ALL credentials**, not just the confirmed-compromised ones
- **ALWAYS preserve chain of custody** — log who touched what and when
