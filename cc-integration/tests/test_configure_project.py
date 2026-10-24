import json
import os
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "configure-project.sh"


class ConfigureProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="upskill project config ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home with spaces"
        self.project = self.root / "project with spaces"
        self.settings = self.project / ".claude" / "settings.local.json"
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.home)

    def run_configure(self):
        bash = os.environ.get("BASH", "bash")
        return subprocess.run(
            [bash, str(SCRIPT), str(self.project)],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def upskill_entry(self, script_name):
        script_path = self.home / ".claude" / "hooks" / script_name
        return {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"bash {shlex.quote(str(script_path))}",
                }
            ],
        }

    def test_merges_hooks_without_replacing_existing_settings(self):
        existing_prompt_hook = {
            "matcher": "Submit",
            "hooks": [{"type": "command", "command": "echo keep-prompt"}],
        }
        existing_start_hook = {
            "matcher": "startup",
            "hooks": [{"type": "command", "command": "echo keep-start"}],
        }
        existing_end_hook = {
            "matcher": "",
            "hooks": [{"type": "command", "command": "echo keep-end"}],
        }
        existing_pre_tool = [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo keep-tool"}]}]
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text(
            json.dumps(
                {
                    "claudeMd": "project-specific.md",
                    "customSetting": {"keep": True},
                    "hooks": {
                        "UserPromptSubmit": [existing_prompt_hook],
                        "SessionStart": [existing_start_hook],
                        "SessionEnd": [existing_end_hook],
                        "PreToolUse": existing_pre_tool,
                    },
                }
            ),
            encoding="utf-8",
        )

        first_run = self.run_configure()
        self.assertEqual(first_run.returncode, 0, first_run.stderr)
        configured = json.loads(self.settings.read_text(encoding="utf-8"))

        self.assertEqual(configured["claudeMd"], "project-specific.md")
        self.assertEqual(configured["customSetting"], {"keep": True})
        self.assertEqual(configured["hooks"]["UserPromptSubmit"][0], existing_prompt_hook)
        self.assertEqual(configured["hooks"]["SessionStart"][0], existing_start_hook)
        self.assertEqual(configured["hooks"]["SessionEnd"][0], existing_end_hook)
        self.assertEqual(configured["hooks"]["PreToolUse"], existing_pre_tool)

        expected_scripts = {
            "UserPromptSubmit": "capture-prompt.sh",
            "SessionStart": "before-session.sh",
            "SessionEnd": "after-session.sh",
        }
        for hook_type, script_name in expected_scripts.items():
            self.assertEqual(
                configured["hooks"][hook_type].count(self.upskill_entry(script_name)),
                1,
            )

        second_run = self.run_configure()
        self.assertEqual(second_run.returncode, 0, second_run.stderr)
        configured_again = json.loads(self.settings.read_text(encoding="utf-8"))
        for hook_type, script_name in expected_scripts.items():
            self.assertEqual(
                configured_again["hooks"][hook_type].count(self.upskill_entry(script_name)),
                1,
            )
        self.assertEqual(configured_again["hooks"]["SessionStart"][0], existing_start_hook)

    def test_creates_missing_settings(self):
        result = self.run_configure()
        self.assertEqual(result.returncode, 0, result.stderr)
        configured = json.loads(self.settings.read_text(encoding="utf-8"))

        self.assertEqual(
            Path(configured["claudeMd"]),
            self.home / ".claude" / "upskill-store" / "CLAUDE.md",
        )
        self.assertEqual(
            configured["hooks"]["UserPromptSubmit"],
            [self.upskill_entry("capture-prompt.sh")],
        )
        self.assertEqual(
            configured["hooks"]["SessionStart"],
            [self.upskill_entry("before-session.sh")],
        )
        self.assertEqual(
            configured["hooks"]["SessionEnd"],
            [self.upskill_entry("after-session.sh")],
        )

    def test_invalid_existing_json_is_preserved(self):
        self.settings.parent.mkdir(parents=True)
        invalid_settings = '{"hooks": invalid\n'
        self.settings.write_text(invalid_settings, encoding="utf-8")

        result = self.run_configure()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot read existing settings as JSON", result.stderr)
        self.assertEqual(self.settings.read_text(encoding="utf-8"), invalid_settings)


if __name__ == "__main__":
    unittest.main()
