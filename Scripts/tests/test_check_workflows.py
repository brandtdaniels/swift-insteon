"""Tests for Scripts/check-workflows.py, on made-up workflows in a temporary directory.

Usage: python3 -m unittest discover -s Scripts/tests
"""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import textwrap
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "check-workflows.py"

spec = importlib.util.spec_from_file_location("check_workflows", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

SHA = "11d5960a326750d5838078e36cf38b85af677262"

DIGEST = "sha256:" + "0123456789abcdef" * 4

PINNED = textwrap.dedent(f"""\
    name: CI
    on: [push]
    jobs:
      lint:
        name: Lint
        runs-on: ubuntu-latest
        timeout-minutes: 10
        steps:
          - uses: actions/checkout@{SHA} # v4.4.0
          - uses: ./.github/actions/local
          - name: Run
            run: echo "uses: actions/checkout@v4"
      linux:
        runs-on: ubuntu-latest
        container: swift:6.3.3@{DIGEST}
        timeout-minutes: 30
        services:
          cache:
            image: redis:7@{DIGEST}
        steps:
          - uses: docker://alpine:3.20@{DIGEST}
    """)


class CheckWorkflowsTests(unittest.TestCase):

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)
        self.workflows = self.root / ".github" / "workflows"
        self.workflows.mkdir(parents=True)

    def tearDown(self):
        self.directory.cleanup()

    def problems(self, workflow):
        (self.workflows / "ci.yml").write_text(workflow, encoding="utf-8")

        return check.problems(self.root)

    def test_accepts_pinned_actions_and_images_and_jobs_with_limits(self):
        self.assertEqual(self.problems(PINNED), [])

    def test_refuses_an_action_by_tag_or_short_sha(self):
        workflow = PINNED.replace(f"actions/checkout@{SHA} # v4.4.0", "actions/checkout@v4")
        workflow = workflow.replace("./.github/actions/local", "actions/cache@11d5960")

        found = self.problems(workflow)

        self.assertEqual(len(found), 2)
        self.assertIn("ci.yml:9: actions/checkout@v4: pin the action", found[0])
        self.assertIn("ci.yml:10: actions/cache@11d5960: pin the action", found[1])

    def test_asks_for_the_version_of_a_pinned_action(self):
        found = self.problems(PINNED.replace(" # v4.4.0", ""))

        self.assertEqual(len(found), 1)
        self.assertIn("add the version the SHA is", found[0])

    def test_refuses_an_image_by_tag(self):
        workflow = PINNED.replace(f"swift:6.3.3@{DIGEST}", "swift:6.3.3")
        workflow = workflow.replace(f"redis:7@{DIGEST}", "redis:7")
        workflow = workflow.replace(f"alpine:3.20@{DIGEST}", "alpine:3.20")

        found = self.problems(workflow)

        self.assertEqual([problem.split(": ")[1] for problem in found], ["swift:6.3.3", "redis:7", "docker://alpine:3.20"])

    def test_refuses_a_job_without_a_time_limit(self):
        found = self.problems(PINNED.replace("    timeout-minutes: 10\n", ""))

        self.assertEqual(found, [".github/workflows/ci.yml:4: job lint has no timeout-minutes"])

    def test_doesnt_count_a_steps_time_limit_for_its_job(self):
        workflow = PINNED.replace("    timeout-minutes: 10\n", "").replace(
            "        run: echo", "        timeout-minutes: 5\n        run: echo"
        )

        found = self.problems(workflow)

        self.assertEqual(found, [".github/workflows/ci.yml:4: job lint has no timeout-minutes"])

    def test_exits_with_status_1_on_a_problem_and_0_without(self):
        (self.workflows / "ci.yml").write_text(PINNED.replace(" # v4.4.0", ""), encoding="utf-8")

        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check.main(["--root", str(self.root)]), 1)

        (self.workflows / "ci.yml").write_text(PINNED, encoding="utf-8")

        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check.main(["--root", str(self.root)]), 0)


if __name__ == "__main__":
    unittest.main()
