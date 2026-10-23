"""Run with: python3 zsh.d/herdr.test.py"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ZSHRC = (Path(__file__).resolve().parent.parent / "zshrc").read_text()
UPDATE = "function update {" + ZSHRC.split("function update {", 1)[1].split(
    "\nalias cleanup", 1
)[0]
HOOK = ZSHRC.split("# Updates retain old installs;", 1)[1].split("\n# jenv", 1)[0]
HOOK = "# Updates retain old installs;" + HOOK


class HerdrTests(unittest.TestCase):
    def run_zsh(self, script, **env):
        return subprocess.run(
            ["zsh", "-f", "-c", script],
            env={**os.environ, **env},
            text=True,
            capture_output=True,
            check=True,
        ).stdout

    def test_update_plugins_on_both_platforms(self):
        mocks = """
        brew() { :; }; npm() { :; }; pi() { :; }; android() { :; }
        sdkmanager() { :; }; sudo() { :; }; xcodes() { :; }
        herdr() { print -r -- "$*"; }
        """
        for platform in ("darwin24", "linux-gnu"):
            with self.subTest(platform=platform):
                output = self.run_zsh(mocks + UPDATE + f"\nOSTYPE={platform}; update")
                self.assertEqual(output.strip(), "plugin update --yes")

    def test_update_reports_plugin_failure(self):
        result = subprocess.run(
            ["zsh", "-f", "-c", 'herdr() { return 1; }\n' + UPDATE + '\nOSTYPE=other; update'],
            capture_output=True,
        )
        self.assertEqual(result.returncode, 1)

    def test_hook_uses_registered_install_and_skips_missing_plugin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "current plugin"
            (root / "shell").mkdir(parents=True)
            (root / "shell/hook.zsh").write_text('print -r -- "current hook"\n')
            plugin = {"plugin_id": "herdr-automatic-rename", "source": {"managed_path": str(root)}}
            for plugins, inside, expected in (
                ([plugin], "1", "current hook\n"),
                ([], "1", ""),
                ([plugin], "", ""),
            ):
                with self.subTest(plugins=plugins, inside=inside):
                    output = self.run_zsh(
                        'herdr() { print -r -- "$PLUGIN_LIST"; }\n' + HOOK,
                        HERDR_ENV=inside,
                        PLUGIN_LIST=json.dumps({"result": {"plugins": plugins}}),
                    )
                    self.assertEqual(output, expected)


if __name__ == "__main__":
    unittest.main()
