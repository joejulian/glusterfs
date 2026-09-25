"""Exercise Python 3 SELinux command output without changing host policy."""

import importlib.util
import pathlib
import subprocess
import sys
import types
import unittest
from unittest.mock import patch


SOURCE = pathlib.Path(__file__).resolve().parents[2] / "extras/snap_scheduler/snap_scheduler.py"
spec = importlib.util.spec_from_file_location("snap_scheduler", SOURCE)
scheduler = importlib.util.module_from_spec(spec)
conf = types.ModuleType("conf")
conf.GLUSTERFS_LIBEXECDIR = "/nonexistent/test-gluster"
with patch.dict(sys.modules, {"conf": conf}), patch.object(sys, "path", sys.path[:]):
    spec.loader.exec_module(scheduler)


class SelinuxOutputTests(unittest.TestCase):
    def run_policy(self, status, boolean="on"):
        real_popen = subprocess.Popen
        commands = []
        processes = []

        def popen(argv, **kwargs):
            commands.append(argv[0])
            if argv[0] == "getenforce":
                argv = [sys.executable, "-c", "print(%r)" % status]
            elif argv[0] == "getsebool":
                argv = [sys.executable, "-c",
                        "print('cron_system_cronjob_use_shares --> %s')" % boolean]
            elif argv[0] == "setsebool":
                argv = [sys.executable, "-c", "pass"]
            process = real_popen(argv, **kwargs)
            processes.append(process)
            return process

        try:
            with patch.object(scheduler.subprocess, "Popen", side_effect=popen):
                result = scheduler.set_cronjob_user_share()
        finally:
            for process in processes:
                process.wait()
                for stream in (process.stdout, process.stderr):
                    if stream is not None:
                        stream.close()
        return result, commands

    def test_disabled_does_not_query_or_change_policy(self):
        result, commands = self.run_policy("Disabled")
        self.assertEqual(result, 0)
        self.assertEqual(commands, ["getenforce"])

    def test_enabled_policy_is_preserved(self):
        result, commands = self.run_policy("Enforcing", "on")
        self.assertEqual(result, 0)
        self.assertNotIn("setsebool", commands)

    def test_failed_policy_change_is_reported(self):
        result, commands = self.run_policy("Enforcing", "off")
        self.assertEqual(result, -1)
        self.assertIn("setsebool", commands)


if __name__ == "__main__":
    unittest.main()
