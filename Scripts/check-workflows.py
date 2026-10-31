#!/usr/bin/env python3
"""Checks that the GitHub Actions workflows pin what they run and bound how long they run.

Usage: python3 Scripts/check-workflows.py [--root DIR]

A tag such as `actions/checkout@v4` or `swift:6.3.3` can be moved to point at other code, so:

- each `uses:` names an action by a full 40-digit commit SHA, followed by a comment with the
  version it is, such as `actions/checkout@<sha> # v4.4.0`; a local action, `./...`, is fine;
- each `container:` or `image:` names its image by digest, `name:tag@sha256:<64 digits>`;
- and each job sets `timeout-minutes`, so a job that hangs fails in minutes rather than after
  GitHub's six-hour limit.

It reads `.github/workflows/*.yml` and `*.yaml` under the root, the repository by default, line
by line rather than as YAML, so it needs nothing beyond Python, and prints each line that
breaks a rule. It exits with status 1 if it finds any.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

USES = re.compile(r"^\s*(?:-\s+)?uses:\s*(?P<value>[^\s#]+)\s*(?P<comment>#.*)?$")

PINNED_ACTION = re.compile(r"^[\w.-]+/[\w./-]+@[0-9a-f]{40}$")

VERSION_COMMENT = re.compile(r"^#\s*v?\d+(?:\.\d+)*\b")

IMAGE = re.compile(r"^\s*(?:-\s+)?(?:container|image):\s*(?P<value>[^\s#]+)")

PINNED_IMAGE = re.compile(r"@sha256:[0-9a-f]{64}$")


def problems_in(path, relative):
    """Each line of a workflow that breaks a rule, as a message."""

    lines = path.read_text(encoding="utf-8").split("\n")
    found = []

    for number, line in enumerate(lines, start=1):
        if line.lstrip().startswith("#"):
            continue

        if uses := USES.match(line):
            value = uses.group("value").strip("'\"")
            comment = (uses.group("comment") or "").strip()

            if value.startswith("./"):
                pass
            elif value.startswith("docker://"):
                if not PINNED_IMAGE.search(value):
                    found.append(f"{relative}:{number}: {value}: pin the image by digest, as name:tag@sha256:<digest>")
            elif not PINNED_ACTION.match(value):
                found.append(f"{relative}:{number}: {value}: pin the action to a full commit SHA, with its version in a comment")
            elif not VERSION_COMMENT.match(comment):
                found.append(f"{relative}:{number}: {value}: add the version the SHA is, as a comment such as # v4.4.0")

            continue

        if image := IMAGE.match(line):
            value = image.group("value").strip("'\"")

            # `container:` on its own line has its image on the next, which this checks then.
            if value and not value.startswith("${{") and not PINNED_IMAGE.search(value):
                found.append(f"{relative}:{number}: {value}: pin the image by digest, as name:tag@sha256:<digest>")

    found.extend(jobs_without_timeouts(lines, relative))

    return found


def jobs_without_timeouts(lines, relative):
    """Each job, in the workflow's `jobs:` map, that doesn't set `timeout-minutes`."""

    found = []
    in_jobs = False
    job = None
    job_indent = None

    def finish():
        if job is not None and not job["timeout"]:
            found.append(f"{relative}:{job['line']}: job {job['name']} has no timeout-minutes")

    for number, line in enumerate(lines, start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        indent = len(line) - len(line.lstrip())

        if indent == 0:
            finish()
            job = None
            in_jobs = line.rstrip() == "jobs:"
            continue

        if not in_jobs:
            continue

        if job_indent is None:
            job_indent = indent

        if indent == job_indent:
            finish()
            name = line.strip().rstrip(":")
            job = {"name": name, "line": number, "timeout": False, "key_indent": None}
            continue

        if job is None:
            continue

        # The job's own keys are at the indentation of its first line; a step's keys are deeper.
        if job["key_indent"] is None:
            job["key_indent"] = indent

        if indent == job["key_indent"] and re.match(r"^\s*timeout-minutes:\s*\S", line):
            job["timeout"] = True

    finish()

    return found


def problems(root):
    """Every problem in the workflows under the root."""

    found = []
    workflows = root / ".github" / "workflows"

    for path in sorted(list(workflows.glob("*.yml")) + list(workflows.glob("*.yaml"))):
        found.extend(problems_in(path, path.relative_to(root).as_posix()))

    return found


def main(arguments=None):
    parser = argparse.ArgumentParser(description="Checks the workflows' pins and job limits.")
    parser.add_argument("--root", type=pathlib.Path, default=ROOT, help="the repository")
    options = parser.parse_args(arguments)

    found = problems(options.root)

    print("\n".join(found) or "Every action and image is pinned, and every job has a time limit.")

    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
