"""Tests for Scripts/check-credentials.py, on made-up sources in a temporary directory.

Usage: python3 -m unittest discover -s Scripts/tests
"""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import textwrap
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "check-credentials.py"

spec = importlib.util.spec_from_file_location("check_credentials", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

# Credentials written into strings, one per line, several ways.
LEAKY = textwrap.dedent("""\
    struct Login {
      func lines(user: String, password: String, hub: Hub) -> [String] {
        let header = "Basic \\(user):\\(password)"
        print("Signing in with \\(hub.password)")
        let raw = #"token=\\#(apiToken)"#
        let note = \"\"\"
          Header: \\(authorizationHeader)
          \"\"\"
        return ["\\(Secrets.clientSecret.uppercased())", "\\("nested \\(bearerToken)")"]
      }
    }
    """)

# The same words where no credential is interpolated: in plain text, comments, and names
# that aren't interpolated.
CLEAN = textwrap.dedent("""\
    // print("\\(password)") in a comment.
    /* "\\(token)" in a block comment. */
    struct Login {
      func lines(user: String, password: String) -> [String] {
        let message = "The Hub's user name and password go in the environment."
        let header = makeHeader(user: user, password: password)
        let raw = #"\\(password) isn't an interpolation in a raw string"#
        return ["\\(user) signed in", message, header, raw]
      }
    }
    """)


class CheckCredentialsTests(unittest.TestCase):

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name) / "Packages"
        self.allowlist = pathlib.Path(self.directory.name) / "allowlist.txt"

    def tearDown(self):
        self.directory.cleanup()

    def write(self, relative, source):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")

    def run_check(self, *extra):
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            status = check.main(["--root", str(self.root), "--allowlist", str(self.allowlist), *extra])

        return status, output.getvalue()

    def test_finds_each_interpolated_credential(self):
        self.write("Lib/Sources/Lib/Login.swift", LEAKY)

        found = [(names, number) for _, names, number in check.violations(self.root)]

        self.assertEqual(found, [
            ("password", 3),
            ("password", 4),
            ("apiToken", 5),
            ("authorizationHeader", 7),
            ("Secrets,bearerToken,clientSecret", 9),
        ])

    def test_ignores_plain_text_comments_and_names_outside_interpolations(self):
        self.write("Lib/Sources/Lib/Login.swift", CLEAN)

        self.assertEqual(check.violations(self.root), [])

    def test_reads_the_command_but_not_tests(self):
        self.write("InsteonCLI/Sources/insteon/Login.swift", 'let line = "\\(password)"\n')
        self.write("Lib/Tests/LibTests/LoginTests.swift", 'let line = "\\(password)"\n')

        found = [path for path, _, _ in check.violations(self.root)]

        self.assertEqual(found, ["InsteonCLI/Sources/insteon/Login.swift"])

    def test_passes_with_every_line_allowed_and_fails_on_a_new_one(self):
        self.write("Lib/Sources/Lib/Auth.swift", 'let header = "\\(user):\\(password)"\n')
        self.allowlist.write_text("# Known.\nLib/Sources/Lib/Auth.swift\tpassword\tBuilds the header.\n", encoding="utf-8")

        self.assertEqual(self.run_check()[0], 0)

        self.write("Lib/Sources/Lib/Log.swift", 'print("\\(token)")\n')
        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("Lib/Sources/Lib/Log.swift:1: interpolates token", output)

    def test_fails_on_an_entry_that_no_longer_matches(self):
        self.write("Lib/Sources/Lib/Auth.swift", "let header = makeHeader()\n")
        self.allowlist.write_text("Lib/Sources/Lib/Auth.swift\tpassword\tBuilds the header.\n", encoding="utf-8")

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("no longer found, so remove it", output)

    def test_refuses_an_entry_without_a_reason(self):
        self.write("Lib/Sources/Lib/Auth.swift", 'let header = "\\(password)"\n')
        self.allowlist.write_text("Lib/Sources/Lib/Auth.swift\tpassword\t\n", encoding="utf-8")

        with self.assertRaises(SystemExit):
            self.run_check()

    def test_update_keeps_the_reasons_of_entries_that_remain(self):
        self.write("Lib/Sources/Lib/Auth.swift", 'let header = "\\(password)"\nprint("\\(token)")\n')
        self.allowlist.write_text("Lib/Sources/Lib/Auth.swift\tpassword\tBuilds the header.\n", encoding="utf-8")

        self.assertEqual(self.run_check("--update")[0], 0)

        entries = [line for line in self.allowlist.read_text(encoding="utf-8").split("\n") if line and not line.startswith("#")]

        self.assertEqual(entries, [
            "Lib/Sources/Lib/Auth.swift\tpassword\tBuilds the header.",
            "Lib/Sources/Lib/Auth.swift\ttoken\t",
        ])

    def test_restores_the_interpolation_reader_after_reading(self):
        interpolation = check._thin.interpolation

        list(check.interpolation_lines('let a = "\\(password)"\n'))

        self.assertIs(check._thin.interpolation, interpolation)

    def test_reads_names_as_words(self):
        matching = [
            "password", "hubPassword", "passwordPrompt", "INSTEON_PASSWORD", "passwd", "pwd", "userPwd",
            "passphrase", "token", "accessTokens", "bearerToken", "secret", "clientSecrets", "credential",
            "credentials", "creds", "authorization", "authorizationHeader", "bearer", "apiKey", "APIKey",
            "api_key", "apikey", "privateKey", "accessKey", "PRIVATE_KEY",
        ]
        other = ["tokenizer", "detokenize", "passage", "secretary", "keyPath", "privateMode", "accessLevel", "user", "host"]

        self.assertEqual([word for word in matching if not check.is_credential(word)], [])
        self.assertEqual([word for word in other if check.is_credential(word)], [])

    def test_reads_string_literals_inside_an_interpolation(self):
        self.write("Lib/Sources/Lib/Env.swift", textwrap.dedent("""\
            let a = "Hub \\(environment["INSTEON_PASSWORD"] ?? "")"
            let b = "Hub \\(environment["INSTEON_HUB_HOST"] ?? "")"
            let c = "INSTEON_PASSWORD isn't set, so \\(name) can't sign in."
            """))

        found = [(names, number) for _, names, number in check.violations(self.root)]

        self.assertEqual(found, [("INSTEON_PASSWORD", 1)])

    def test_fails_on_an_interpolation_not_closed_on_its_line(self):
        self.write("Lib/Sources/Lib/Long.swift", textwrap.dedent("""\
            let text = \"\"\"
              Signed in as \\(account.name(
                for: hub
              ))
              \"\"\"
            """))
        self.allowlist.write_text("", encoding="utf-8")

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("Lib/Sources/Lib/Long.swift:2: an interpolation isn't closed on its line", output)

        # An update doesn't allow it.
        self.run_check("--update")

        self.assertEqual(self.run_check()[0], 1)


if __name__ == "__main__":
    unittest.main()
