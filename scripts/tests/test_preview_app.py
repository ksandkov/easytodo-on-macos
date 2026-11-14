import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class PreviewAppTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        (self.root / "home").mkdir()
        source = Path(__file__).resolve().parents[1] / "preview_app.sh"
        shutil.copy2(source, self.root / "scripts/preview_app.sh")
        self.log = self.root / "commands.log"
        self.environment = dict(
            os.environ,
            HOME=str(self.root / "home"),
            PATH=str(self.root / "bin") + ":/usr/bin:/bin",
            PREVIEW_COMMAND_LOG=str(self.log),
            FAIL_SWIFT="",
            FAIL_PACKAGE="0",
        )
        self.command("swift", '''printf 'swift %s\\n' "$*" >> "$PREVIEW_COMMAND_LOG"
if [ "$1" = "$FAIL_SWIFT" ]; then exit 2; fi
''')
        self.command("pgrep", "exit 1\n")
        self.command("defaults", "exit 1\n")
        self.command("open", '''printf 'open %s\\n' "$*" >> "$PREVIEW_COMMAND_LOG"
''')
        (self.root / "scripts/package_app.sh").write_text('''#!/bin/bash
printf 'package\\n' >> "$PREVIEW_COMMAND_LOG"
exit "$FAIL_PACKAGE"
''')

    def command(self, name, body):
        path = self.root / "bin" / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    def run_preview(self):
        result = subprocess.run(
            ["/bin/bash", "scripts/preview_app.sh"],
            cwd=self.root,
            env=self.environment,
            text=True,
            capture_output=True,
        )
        commands = self.log.read_text().splitlines() if self.log.exists() else []
        return result, commands

    def test_build_failure_stops_before_tests_packaging_and_launch(self):
        self.environment["FAIL_SWIFT"] = "build"
        result, commands = self.run_preview()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, ["swift build"])

    def test_test_failure_stops_before_packaging_and_launch(self):
        self.environment["FAIL_SWIFT"] = "test"
        result, commands = self.run_preview()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, ["swift build", "swift test"])

    def test_packaging_failure_does_not_launch(self):
        self.environment["FAIL_PACKAGE"] = "3"
        result, commands = self.run_preview()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, ["swift build", "swift test", "package"])

    def test_success_backs_up_tasks_and_launches_only_the_local_bundle(self):
        store = self.root / "home/Library/Application Support/EasyTODO/EasyTODO.store"
        store.parent.mkdir(parents=True)
        store.write_text("Existing tasks")
        result, commands = self.run_preview()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(commands, [
            "swift build", "swift test", "package", f"open -n {self.root}/dist/EasyTODO.app"
        ])
        backups = list((self.root / "dist").glob("data-backup-*/EasyTODO/EasyTODO.store"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "Existing tasks")
        self.assertEqual(store.read_text(), "Existing tasks")


if __name__ == "__main__":
    unittest.main()
