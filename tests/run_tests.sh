#!/usr/bin/env bash
# Offline functional tests: runs the real playbooks against a mock cli_command module
# and canned fixtures. No controller is contacted. Usage: bash tests/run_tests.sh
set -uo pipefail

cd "$(dirname "$0")/.."

export ANSIBLE_COLLECTIONS_PATH="$PWD/tests/mock_collections"
export ANSIBLE_HOST_KEY_CHECKING=False
export MOCK_FIXTURES="$PWD/tests/fixtures/controller.yml"

failures=0

check() {
  local description="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS: ${description}"
  else
    echo "FAIL: ${description}"
    failures=$((failures + 1))
  fi
}

run() {
  ansible-playbook -i tests/inventory.yml "$@" 2>&1
}

rm -f reports/mock-mc01_*

# --- client_status: client stuck at the captive portal
out=$(run playbooks/client_status.yml -e client_mac=aa:bb:cc:dd:ee:ff); rc=$?
check "client_status succeeds" test "$rc" -eq 0
check "logon role is flagged as captive portal" grep -q "waiting at the captive portal" <<< "$out"
check "client report written" grep -q "Looks like captive portal role: True" reports/mock-mc01_aa-bb-cc-dd-ee-ff_client_status.txt

# --- client_status: expected role must match exactly (guest is not guest-logon)
out=$(run playbooks/client_status.yml -e client_mac=aa:bb:cc:dd:ee:ff -e expected_role=guest); rc=$?
check "guest-logon is not mistaken for guest (SSID is also named Guest)" grep -q "ROLE MISMATCH" <<< "$out"

# --- client_status: healthy client in the expected role
out=$(run playbooks/client_status.yml -e client_mac=aa:bb:cc:dd:ee:01 -e expected_role=guest); rc=$?
check "healthy client succeeds" test "$rc" -eq 0
check "healthy client is not flagged" bash -c '! grep -Eq "waiting at the captive portal|ROLE MISMATCH|is not in the user table|Could not read" <<< "$0"' "$out"

# --- client_status: unknown client
out=$(run playbooks/client_status.yml -e client_mac=aa:bb:cc:00:00:99); rc=$?
check "unknown client run succeeds" test "$rc" -eq 0
check "unknown client is reported" grep -q "is not in the user table" <<< "$out"

# --- client_status: bad MAC format rejected
out=$(run playbooks/client_status.yml -e client_mac=not-a-mac); rc=$?
check "bad MAC is rejected" test "$rc" -ne 0

# --- role_vlan_check: wrong VLAN and role
out=$(run playbooks/role_vlan_check.yml -e client_mac=aa:bb:cc:dd:ee:ff -e expected_vlan=100 -e expected_role=guest); rc=$?
check "role_vlan_check succeeds when a mismatch exists" test "$rc" -eq 0
check "vlan mismatch is flagged" grep -q "VLAN MISMATCH: client is on VLAN 20, expected 100" <<< "$out"
check "role mismatch is flagged" grep -q "ROLE MISMATCH" <<< "$out"
check "role/vlan report records what was found" grep -q "Found role: guest-logon   Expected role: guest" reports/mock-mc01_aa-bb-cc-dd-ee-ff_role_vlan.txt

out=$(run playbooks/role_vlan_check.yml -e client_mac=aa:bb:cc:dd:ee:ff -e expected_vlan=100 -e fail_on_mismatch=true); rc=$?
check "fail_on_mismatch fails the run" test "$rc" -ne 0

# --- role_vlan_check: client correct
out=$(run playbooks/role_vlan_check.yml -e client_mac=aa:bb:cc:dd:ee:01 -e expected_vlan=100 -e expected_role=guest -e fail_on_mismatch=true); rc=$?
check "correct client passes even with fail_on_mismatch" test "$rc" -eq 0
check "correct client is not flagged" bash -c '! grep -q "MISMATCH" <<< "$0"' "$out"

# --- ap_uplink_health
out=$(run playbooks/ap_uplink_health.yml -e ap_name=AP-Lobby-01); rc=$?
check "ap_uplink_health succeeds" test "$rc" -eq 0
check "down AP is reported" grep -q "AP-Store-02" <<< "$out"
check "AP report includes the switch neighbour" grep -q "access-sw01" reports/mock-mc01_ap_health.txt

echo
if [ "$failures" -eq 0 ]; then
  echo "All tests passed."
else
  echo "${failures} test(s) failed."
fi
exit "$failures"
