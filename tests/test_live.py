"""Opt-in acceptance against the configured Rex server; only own sessions are closed."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
REX = os.environ.get("REX_BIN") or shutil.which("rex") or str(
    Path.home() / "Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
)


def run(*args):
    return subprocess.check_output([REX, "--autostart=false", *args], text=True, timeout=15)


@unittest.skipUnless(os.environ.get("REX_LIVE_TEST") == "1", "requires configured plugin and live opt-in")
class LiveNumbering(unittest.TestCase):
    def test_titles_create_close_and_reload(self):
        status = json.loads(run("do", "rexpack_events_control", "op=status"))
        self.assertEqual(status["state"], "running", status)
        created = json.loads(run("new", "rex-tabnum-acceptance", "--json", "--shell=none",
                                 "--", shutil.which("python3"), str(ROOT / "tests/title_fixture.py")))
        session = created["session_id"]
        self.addCleanup(run, "kill", session)
        block = created["initial_windows"][0]["block_ids"][0]

        def wait_labels(expected):
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                view = json.loads(run("session", "inspect", session, "--json"))
                labels = [w["label"] for w in view["windows"]]
                if labels == expected:
                    return
                time.sleep(0.1)
            self.assertEqual(labels, expected)

        wait_labels(["0. dynamic-alpha"])
        run("send", "-s", session, "-b", block, "9. 中文 title")
        run("send-key", "-s", session, "-b", block, "enter")
        wait_labels(["0. 9. 中文 title"])
        second = json.loads(run("window", "new", "-s", session, "Second", "--focus=false",
                                "--json", "--shell=none", "--", shutil.which("python3"),
                                str(ROOT / "tests/title_fixture.py")))
        wait_labels(["0. 9. 中文 title", "1. dynamic-alpha"])
        run("window", "close", "-s", session, created["initial_windows"][0]["window_id"])
        wait_labels(["0. dynamic-alpha"])
        run("config", "reload")
        time.sleep(2)
        run("send", "-s", session, "-b", second["block_ids"][0], "after-reload")
        run("send-key", "-s", session, "-b", second["block_ids"][0], "enter")
        wait_labels(["0. after-reload"])
        self.assertEqual(json.loads(run("do", "rexpack_events_control", "op=status"))["state"], "running")


if __name__ == "__main__":
    unittest.main()
