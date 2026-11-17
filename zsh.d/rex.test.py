"""Run with: python3 zsh.d/rex.test.py"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
ZSHRC = (ROOT / "zshrc").read_text()
UPDATE = "function update {" + ZSHRC.split("function update {", 1)[1].split(
    "\nalias cleanup", 1
)[0]


class RexTests(unittest.TestCase):
    def test_worktree_tabs(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "calls.jsonl"
            rex = Path(directory) / "rex"
            rex.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "args = sys.argv[1:]\n"
                "with open(os.environ['REX_TEST_LOG'], 'a') as log:\n"
                "    log.write(json.dumps(args) + '\\n')\n"
                "if args[:2] == ['window', 'ls']:\n"
                "    print(os.environ['REX_TEST_WINDOWS'])\n"
                "operation = args[1] if args[0] == 'window' else args[0]\n"
                "sys.exit(1 if os.environ.get('REX_TEST_FAIL') == operation else 0)\n"
            )
            rex.chmod(0o755)
            worktree = "/projects/repo with 'quotes'/feature"
            listing = ["window", "ls", "-s", "session:project", "--json"]
            create = [
                "window", "new", "-s", "session:project", worktree, "-c", worktree
            ]
            for session, windows, fail, expected in (
                ("", {"windows": []}, "0", []),
                ("session:project", {"windows": []}, "0", [listing, create]),
                (
                    "session:project",
                    {"windows": [
                        {"label": "/other/feature", "window_id": "window:other"},
                        {"label": worktree, "window_id": "window:existing"},
                    ]},
                    "0",
                    [listing, ["focus", "-s", "session:project", "window:existing"]],
                ),
                ("session:project", {"windows": []}, "ls", [listing]),
                ("session:project", {"windows": []}, "new", [listing, create]),
                (
                    "session:project",
                    {"windows": [{"label": worktree, "window_id": "window:existing"}]},
                    "focus",
                    [listing, ["focus", "-s", "session:project", "window:existing"]],
                ),
                ("session:project", {}, "0", [listing]),
            ):
                with self.subTest(session=session, windows=windows, fail=fail):
                    log.unlink(missing_ok=True)
                    subprocess.run(
                        ["zsh", "-f", "-e", "-c",
                         'source "$1"; _gw_rex_open_worktree "$2"',
                         "zsh", str(ROOT / "zsh.d/git-functions.zsh"), worktree],
                        env={
                            **os.environ,
                            "PATH": f"{directory}:{os.environ['PATH']}",
                            "REX_SESSION": session,
                            "REX_TEST_LOG": str(log),
                            "REX_TEST_WINDOWS": json.dumps(windows),
                            "REX_TEST_FAIL": fail,
                        },
                        check=True,
                    )
                    calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
                    self.assertEqual(calls, expected)

    def test_update_refreshes_rex_skill_on_both_platforms(self):
        mocks = """
        brew() { :; }; npm() { :; }; pi() { :; }; android() { :; }
        xcodes() { :; }
        gh() { print -r -- "gh $*"; }
        rex() { print -r -- "rex $*"; }
        """
        with tempfile.TemporaryDirectory() as directory:
            sudo = Path(directory) / "sudo"
            sudo.write_text('#!/bin/sh\nprintf "sudo %s\\n" "$*"\n')
            sudo.chmod(0o755)
            for platform in ("darwin24", "linux-gnu"):
                with self.subTest(platform=platform):
                    output = subprocess.check_output(
                        ["zsh", "-f", "-c", mocks + UPDATE + f"\nOSTYPE={platform}; update"],
                        env={**os.environ, "PATH": f"{directory}:{os.environ['PATH']}"},
                        text=True,
                    )
                    expected = (
                        "sudo mas upgrade\n" if platform.startswith("darwin")
                        else "sudo apt update\nsudo apt upgrade -y\nsudo apt autoremove -y\n"
                    )
                    self.assertEqual(
                        output,
                        expected + "gh extension upgrade stack\ngh skill update --all\n"
                        "rex skill setup --agent pi --session-naming\n",
                    )

    def test_update_reports_rex_failure(self):
        result = subprocess.run(
            ["zsh", "-f", "-c", 'gh() { :; }; rex() { return 1; }\n' + UPDATE + '\nOSTYPE=other; update'],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
