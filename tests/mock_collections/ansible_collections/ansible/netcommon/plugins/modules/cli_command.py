#!/usr/bin/python
"""Test double for ansible.netcommon.cli_command.

Answers from a YAML fixture file (path in $MOCK_FIXTURES) that maps an exact
command string to canned output. An unknown command fails, like a device
rejecting a command. Used only by tests/run_tests.sh; never by real runs.
"""
from __future__ import annotations

import os

import yaml
from ansible.module_utils.basic import AnsibleModule


def main():
    module = AnsibleModule(
        argument_spec=dict(
            command=dict(type="str", required=True),
            prompt=dict(type="list", elements="str"),
            answer=dict(type="list", elements="str"),
            sendonly=dict(type="bool", default=False),
            newline=dict(type="bool", default=True),
            check_all=dict(type="bool", default=False),
        ),
        supports_check_mode=True,
    )

    path = os.environ.get("MOCK_FIXTURES")
    if not path:
        module.fail_json(msg="MOCK_FIXTURES is not set")
    with open(path, encoding="utf-8") as handle:
        fixtures = yaml.safe_load(handle)

    command = module.params["command"]
    if command not in fixtures:
        module.fail_json(msg="% Unknown command: " + command)

    output = fixtures[command]
    module.exit_json(changed=False, stdout=output, stdout_lines=output.splitlines())


if __name__ == "__main__":
    main()
