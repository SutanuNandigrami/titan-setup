---
name: ansible-ops
description: Ansible operations, playbook best practices, idempotency patterns, and vault workflows. Use when writing, testing, or running Ansible playbooks.
paths: ["**/playbooks/**", "**/roles/**", "**/inventory/**", "**/group_vars/**", "**/host_vars/**", "**/ansible.cfg", "**/*.yml", "**/*.yaml"]
---

# Ansible Operations

## Pre-Run Checks

```bash
ansible-lint --nocolor                                   # Lint + best practices
ansible-playbook -i inventory --syntax-check site.yml   # Syntax check
ansible-playbook -i inventory site.yml --check --diff   # Dry-run + diff
ansible -i inventory all -m ping                        # Verify connectivity
```

## Running Playbooks

```bash
ansible-playbook -i inventory site.yml                              # Default run
ansible-playbook -i inventory site.yml -vvv                         # Debug verbosity
ansible-playbook -i inventory site.yml --tags=<tag>                 # Single role/tag
ansible-playbook -i inventory site.yml -l <host>                    # Limit to host
ansible-playbook -i inventory site.yml --step                       # Approve each task
ansible-playbook -i inventory site.yml --start-at-task="Task Name" # Resume from task
```

## Idempotency Patterns

**Broken (fails on re-run):**
```yaml
- shell: git clone {{ repo }}  # Fails if dir exists
- cron: job="backup.sh"        # Creates duplicate (no name)
```

**Correct:**
```yaml
- git:
    repo: "{{ repo_url }}"
    dest: "{{ repo_path }}"
    update: yes                # Pulls if already cloned

- cron:
    name: "backup-db-daily"    # Name = idempotency key
    special_time: daily
    job: "/opt/scripts/backup.sh"
    user: backup

- copy:
    src: config.yml
    dest: /etc/app/config.yml
    mode: "0600"
    backup: yes

- shell: grep -q "setting" /etc/app.conf || echo "setting=value" >> /etc/app.conf
  changed_when: false          # Shell always reports changed unless explicitly set
```

## Handlers (Service Restarts)

```yaml
- name: Update config
  copy:
    src: app.conf
    dest: /etc/app/app.conf
  notify: restart app          # Only triggers if task reports changed

handlers:
  - name: restart app
    service:
      name: app
      state: restarted
```

## Vault (Secrets) Workflow

```bash
ansible-vault create group_vars/all/vault.yml    # New encrypted file
ansible-vault edit group_vars/all/vault.yml      # Edit in place
ansible-vault encrypt existing.yml               # Encrypt existing
ansible-vault rekey vault.yml                    # Change vault password
ansible-vault view vault.yml                     # View without editing

# Run with vault
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file=.vault-pass
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault-pass  # Skip interactive prompt
```

**Convention:** Prefix vault vars with `vault_`, reference in plain vars:
```yaml
# group_vars/all/vars.yml
db_password: "{{ vault_db_password }}"

# group_vars/all/vault.yml (encrypted)
vault_db_password: "supersecret"
```

## Molecule Testing (Role Testing)

```bash
cd roles/myrole
molecule init                  # Create molecule/ structure
molecule converge              # Run playbook in container
molecule verify                # Run assertions (verify.yml)
molecule destroy               # Cleanup
molecule test                  # Full cycle: create→converge→verify→destroy
molecule login                 # SSH into test instance for debugging
```

## Dynamic Inventory

```bash
ansible-inventory -i aws_ec2.yml --graph   # List AWS inventory
ansible-inventory --list-inventory-sources  # Show available plugins
ansible-playbook -i ./get_hosts.py site.yml  # Custom Python inventory
```

## Common Mistakes

- `shell:` without `changed_when:` → always reports changed
- Hardcoded paths → use `ansible_user_dir`, `ansible_home`
- No `become: yes` on privileged tasks → silent failure
- Missing `handlers:` for service restart → config change has no effect
- No `name:` on cron tasks → creates duplicates on re-run

## Rules

- ALWAYS lint before commit (`ansible-lint`)
- ALWAYS dry-run first (`--check --diff`)
- ALWAYS use vault for secrets — never plaintext vars
- ALWAYS name cron/at/etc tasks (idempotency key)
- NEVER use `ignore_errors: yes` without a comment
- NEVER hardcode hostnames/IPs — use variables + inventory
