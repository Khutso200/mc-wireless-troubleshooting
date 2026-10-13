# Aruba mobility controller troubleshooting playbooks

Read-only diagnostic playbooks for a standalone Aruba mobility controller running AOS 8.x (written for 8.13),
driven over SSH (`network_cli`). Nothing in here changes controller configuration.

This repo is deliberately separate from the AOS-CX switch repo (`Aruba-aoscx-switch-troubleshooting`).

| Playbook | Use it when |
|---|---|
| `playbooks/client_status.yml` | A user says they cannot connect or get the splash page and you need to see where the client is stuck. |
| `playbooks/ap_uplink_health.yml` | You want to know if APs are up, and which switch port a given AP is plugged into. |
| `playbooks/role_vlan_check.yml` | You need to confirm the role and VLAN a client was assigned against what you expect. |

Every run writes a text report to `reports/` (git-ignored) and prints a short summary of findings.
Reports contain client MAC addresses and IPs, so treat them as sensitive.

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install ansible ansible-lint yamllint
ansible-galaxy collection install -r requirements.yml
```

1. Edit `inventory/lab.yml` and `inventory/production.yml` with your real controller address.
   The addresses shipped in the repo (`192.0.2.x`) are documentation placeholders.
2. Create the credentials file (plain text, no Ansible Vault):

   ```bash
   cp inventory/group_vars/all/credentials.yml.example inventory/group_vars/all/credentials.yml
   chmod 600 inventory/group_vars/all/credentials.yml
   # edit it and set mc_user, mc_password and mc_enable_password
   ```

3. Use a read-only account on the controller.

### About plain-text credentials

`credentials.yml` is listed in `.gitignore` so it is never committed, and CI fails if a file with that name is ever tracked.
Keep it only on the machine that runs the playbooks, keep it `chmod 600`, and never paste it into issues or chat.
Only `credentials.yml.example` (with placeholder values) lives in git. Ansible Vault can be added back later without changing the playbooks.

If this repository is public, do not commit your real controller or switch management IPs into `inventory/production.yml`; keep the repo private or keep the real inventory out of git.

## Running

```bash
# Where is this client stuck?
ansible-playbook playbooks/client_status.yml -e client_mac=aa:bb:cc:dd:ee:ff

# Did the guest client get the right role and VLAN?
ansible-playbook playbooks/role_vlan_check.yml -e client_mac=aa:bb:cc:dd:ee:ff \
  -e expected_vlan=100 -e expected_role=guest

# Are all APs up? And which switch port is this AP on?
ansible-playbook playbooks/ap_uplink_health.yml -e ap_name=AP-Lobby-01
```

Production is always explicit: add `-i inventory/production.yml`, for example:

```bash
ansible-playbook -i inventory/production.yml playbooks/client_status.yml -e client_mac=aa:bb:cc:dd:ee:ff
```

Typical guest-splash workflow across both repos: `client_status.yml` shows the client is in a logon role or missing,
`ap_uplink_health.yml -e ap_name=...` tells you the switch and port, then the switch repo's `vlan_port_check.yml` confirms the VLAN on that port.

## GitHub Actions

* `ci.yml` runs on every push and pull request: a check that no credentials file is committed, yamllint, ansible-lint, a syntax check of every playbook, and the offline functional tests. It never touches the controller.
* `lab-run.yml` is a manual workflow that runs one playbook against the lab controller. GitHub-hosted runners cannot reach your network, so register a self-hosted runner inside it with the label `lab-network`, create a `lab` environment in the repo settings, and add the secrets `MC_USER`, `MC_PASSWORD` and `MC_ENABLE_PASSWORD` to that environment. The workflow writes them to the git-ignored `credentials.yml` for the duration of the run and deletes the file afterwards.

Suggested path to production: develop on a branch, let CI pass, run against the lab, merge to `main`, then run against production with `-i inventory/production.yml`.

## Offline tests

`bash tests/run_tests.sh` runs the real playbooks against a mock `cli_command` module that answers from canned output in `tests/fixtures/controller.yml`. It proves the logic (role and VLAN comparison, captive-portal detection, failure handling, report contents) without any hardware. It cannot prove that your controller prints output in exactly that shape, so after your first real run, replace or extend the fixture with real output.

## Verify these on first run (important)

These playbooks were written without access to a real controller. The connection method and the output parsing are the most likely things to need adjusting:

* **Connection:** `inventory/group_vars/mobility_controllers.yml` uses `ansible_network_os: community.network.aruba` with enable-mode escalation. If the SSH login fails or prompts are not recognised, send back the error and the controller's prompt style.
* **Commands:** `show user-table mac`, `show user mac`, `show station-table mac`, `show ap lldp neighbor ap-name` and `show vlan status` should all exist on AOS 8.13, but confirm. Failures are tolerated and shown as `[command failed: ...]` in the report.
* **Parsing:** role and VLAN are extracted from `show user mac` with regular expressions in `role_vlan_check.yml`. If the playbook warns that it could not parse them, send back the raw output from the report and the patterns can be tightened.
