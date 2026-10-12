# Aruba mobility controller troubleshooting playbooks

Read-only diagnostic playbooks for a standalone Aruba mobility controller running AOS 8.x (written for 8.13),
driven over SSH (`network_cli`). Nothing in here changes controller configuration.

This repo is deliberately separate from the AOS-CX switch repo (`aoscx-switch-troubleshooting`).

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

1. Edit `inventory/lab.yml` (and later `inventory/production.yml`) with your controller address.
2. Create the encrypted credentials file:

   ```bash
   cp inventory/group_vars/all/vault.yml.example inventory/group_vars/all/vault.yml
   # edit it, then:
   ansible-vault encrypt inventory/group_vars/all/vault.yml
   ```

3. Use a read-only account on the controller.

## Running

```bash
# Where is this client stuck?
ansible-playbook playbooks/client_status.yml -e client_mac=aa:bb:cc:dd:ee:ff --ask-vault-pass

# Did the guest client get the right role and VLAN?
ansible-playbook playbooks/role_vlan_check.yml -e client_mac=aa:bb:cc:dd:ee:ff \
  -e expected_vlan=100 -e expected_role=guest --ask-vault-pass

# Are all APs up? And which switch port is this AP on?
ansible-playbook playbooks/ap_uplink_health.yml -e ap_name=AP-Lobby-01 --ask-vault-pass
```

Production is always explicit: add `-i inventory/production.yml`.

Typical guest-splash workflow across both repos: `client_status.yml` shows the client is in a logon role or missing,
`ap_uplink_health.yml -e ap_name=...` tells you the switch and port, then the switch repo's `vlan_port_check.yml` confirms the VLAN on that port.

## GitHub Actions

* `ci.yml` runs on every push and pull request: yamllint, ansible-lint, a syntax check of every playbook, and the offline functional tests. It never touches the controller.
* `lab-run.yml` is a manual workflow that runs one playbook against the lab controller. GitHub-hosted runners cannot reach your network, so register a self-hosted runner inside it with the label `lab-network`, create a `lab` environment in the repo settings, and add the vault password as the secret `ANSIBLE_VAULT_PASSWORD`. The encrypted `vault.yml` must be committed for this to work.

Suggested path to production: develop on a branch, let CI pass, run against the lab, merge to `main`, then run against production with `-i inventory/production.yml`.

## Offline tests

`bash tests/run_tests.sh` runs the real playbooks against a mock `cli_command` module that answers from canned output in `tests/fixtures/controller.yml`. It proves the logic (role and VLAN comparison, captive-portal detection, failure handling, report contents) without any hardware. It cannot prove that your controller prints output in exactly that shape, so after your first real run, replace or extend the fixture with real output.

## Verify these on first run (important)

These playbooks were written without access to a real controller. The connection method and the output parsing are the most likely things to need adjusting:

* **Connection:** `inventory/group_vars/mobility_controllers.yml` uses `ansible_network_os: community.network.aruba` with enable-mode escalation. If the SSH login fails or prompts are not recognised, send back the error and the controller's prompt style.
* **Commands:** `show user-table mac`, `show user mac`, `show station-table mac`, `show ap lldp neighbor ap-name` and `show vlan status` should all exist on AOS 8.13, but confirm. Failures are tolerated and shown as `[command failed: ...]` in the report.
* **Parsing:** role and VLAN are extracted from `show user mac` with regular expressions in `role_vlan_check.yml`. If the playbook warns that it could not parse them, send back the raw output from the report and the patterns can be tightened.
