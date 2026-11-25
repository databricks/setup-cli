#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github/scripts/publish-release.sh"
BASE = "a" * 40
MIDDLE = "b" * 40
HEAD = "c" * 40
UNCHANGED = "d" * 40
RUN_ID = "12345"
BOT_NAME = "user.name=github-actions[bot]"
BOT_EMAIL = "user.email=41898282+github-actions[bot]@users.noreply.github.com"
TAG_FORMAT = "%(refname)%09%(objecttype)%09%(*objecttype)%09%(*objectname)"


def provenance(tag, revision, run_id=RUN_ID):
    return f"setup-cli-release:v1 run={run_id} tag={tag} target={revision}"


def mock_command(tool, arguments):
    state_path = Path(os.environ["RELEASE_TEST_STATE"])
    state = json.loads(state_path.read_text())
    state["calls"].append([tool, *arguments])
    output, error, status = "", "", 0
    if tool == "git":
        if arguments[:1] == ["-c"]:
            assert arguments[:4] == ["-c", BOT_NAME, "-c", BOT_EMAIL], arguments
            arguments = arguments[4:]
            assert arguments[:1] == ["tag"], arguments
        if arguments[:3] == ["rev-list", "-1", "--first-parent"]:
            assert arguments[4:] == ["--", "VERSION"], arguments
            revision = arguments[3]
            if revision == "HEAD":
                revision = state.get("checkout_revision", HEAD)
            output = state["last_version_revision"].get(revision, revision)
        elif arguments[:3] == ["rev-list", "--reverse", "--first-parent"]:
            assert arguments[4:] == ["--", "VERSION"], arguments
            output = "\n".join(state["range_revisions"])
            status = state.get("range_status", 0)
        elif arguments == ["log", "--format=%H", "--", "VERSION"]:
            output = "\n".join(state["history_revisions"])
            status = state.get("history_status", 0)
        elif arguments[:2] == ["merge-base", "--is-ancestor"]:
            setting = "provenance_ancestor" if arguments[-1] == "HEAD" else "ancestor"
            status = 0 if state.get(setting, True) else 1
        elif arguments[:1] == ["for-each-ref"]:
            assert len(arguments) == 3, arguments
            if arguments[1:] == [f"--format={TAG_FORMAT}", "refs/tags"]:
                records = []
                for tag, revision in sorted(state["local_tags"].items()):
                    if tag in state["local_annotations"]:
                        target_type = state.get("target_types", {}).get(tag, "commit")
                        records.append(f"refs/tags/{tag}\ttag\t{target_type}\t{revision}")
                    else:
                        records.append(f"refs/tags/{tag}\tcommit\t\t")
                output = "\n".join(records)
                status = state.get("tag_scan_status", 0)
            else:
                assert arguments[1] == "--format=%(contents:subject)", arguments
                tag = arguments[2].removeprefix("refs/tags/")
                output = state["local_annotations"][tag].split("\n\n", 1)[0]
                output = output.replace("\n", " ")
        elif arguments[:1] == ["show"]:
            assert arguments[1].endswith(":VERSION"), arguments
            output = state["versions"][arguments[1].split(":")[0]]
        elif arguments[:3] == ["show-ref", "--verify", "--quiet"]:
            tag = arguments[3].removeprefix("refs/tags/")
            status = 0 if tag in state["local_tags"] else 1
        elif arguments[:1] == ["tag"]:
            assert arguments[1] == "-a" and arguments[4] == "-m", arguments
            tag, revision, message = arguments[2], arguments[3], arguments[5]
            assert message == provenance(tag, revision), arguments
            assert tag not in state["local_tags"], arguments
            state["local_tags"][tag] = revision
            state["local_annotations"][tag] = message
        elif arguments[:2] == ["push", "origin"]:
            assert len(arguments) == 3, arguments
            assert arguments[2].startswith("refs/tags/"), arguments
            tag = arguments[2].removeprefix("refs/tags/")
            revision = state["local_tags"][tag]
            if state.get("fail_push_once") == tag:
                del state["fail_push_once"]
                error, status = "Mock push failure", 1
            elif tag in state["remote_tags"] and state["remote_tags"][tag] != revision:
                error, status = "Mock tag conflict", 1
            else:
                state["remote_tags"][tag] = revision
                if tag in state["local_annotations"]:
                    state["remote_annotations"][tag] = state["local_annotations"][tag]
                if state.get("fail_after_push_once") == tag:
                    del state["fail_after_push_once"]
                    error, status = "Mock lost push response", 1
        else:
            raise AssertionError(("unexpected Git invocation", arguments))
    elif tool == "gh":
        if arguments[:1] == ["api"]:
            endpoint = arguments[-1]
            if "/releases/tags/" in endpoint:
                assert arguments[1:3] == ["--include", "--silent"], arguments
                tag = endpoint.rsplit("/", 1)[1]
                code = state.get("lookup_errors", {}).get(tag)
                if code is None:
                    code = 200 if tag in state["releases"] else 404
                if code:
                    reason = "Not Found" if code == 404 else "Mock response"
                    output = f"HTTP/2.0 {code} {reason}\r\n"
                if code != 200:
                    error, status = f"Mock lookup failure: {code}", 1
            elif endpoint.endswith("/contents/VERSION?ref=main"):
                assert arguments[1:3] == [
                    "--header", "Accept: application/vnd.github.raw+json"
                ], arguments
                if state.get("main_lookup_error"):
                    error, status = "Mock main lookup failure", 1
                else:
                    output = state["main_version"]
            else:
                raise AssertionError(("unexpected API endpoint", endpoint))
        elif arguments[:2] == ["release", "create"]:
            tag = arguments[2]
            assert "--verify-tag" in arguments, arguments
            assert "--latest=false" in arguments, arguments
            assert tag in state["remote_tags"], arguments
            if state.get("fail_create_once") == tag:
                del state["fail_create_once"]
                error, status = "Mock release creation failure", 1
            elif tag in state["releases"]:
                error, status = "Mock duplicate release", 1
            else:
                state["releases"].append(tag)
                if state.get("fail_after_create_once") == tag:
                    del state["fail_after_create_once"]
                    error, status = "Mock lost publication response", 1
        elif arguments[:2] == ["release", "edit"]:
            tag = arguments[2]
            assert arguments[3:] == ["--latest"], arguments
            assert tag in state["releases"], arguments
            if state.get("fail_edit_once"):
                del state["fail_edit_once"]
                error, status = "Mock Latest failure", 1
            else:
                state["latest"] = tag
        else:
            raise AssertionError(("unexpected GitHub invocation", arguments))
    else:
        raise AssertionError(("unexpected tool", tool))
    state_path.write_text(json.dumps(state))
    if output:
        print(output)
    if error:
        print(error, file=sys.stderr)
    return status


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="setup-cli-release-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        (self.directory / "bin").mkdir()
        (self.directory / "home").mkdir()
        for tool in ("git", "gh"):
            stub = self.directory / "bin" / tool
            stub.write_text(
                f"#!{sys.executable}\nimport runpy\n"
                f"runpy.run_path({str(Path(__file__).resolve())!r}, "
                f"init_globals={{'_MOCK_TOOL': {tool!r}}}, run_name='__main__')\n"
            )
            stub.chmod(0o755)
        self.state_path = self.directory / "state.json"
        self.state = {
            "versions": {BASE: "1.0.0", MIDDLE: "1.1.0", HEAD: "1.2.0"},
            "last_version_revision": {},
            "range_revisions": [MIDDLE, HEAD],
            "history_revisions": [HEAD, MIDDLE, BASE],
            "local_tags": {"v1.0.0": BASE},
            "remote_tags": {"v1.0.0": BASE},
            "local_annotations": {},
            "remote_annotations": {},
            "releases": ["v1.0.0"],
            "latest": "v1.0.0",
            "main_version": "1.2.0",
            "calls": [],
        }

    def run_release(self, **overrides):
        self.state_path.write_text(json.dumps(self.state))
        environment = {
            "PATH": str(self.directory / "bin") + os.pathsep + os.defpath,
            "HOME": str(self.directory / "home"),
            "GH_CONFIG_DIR": str(self.directory / "home" / "gh"),
            "GH_NO_UPDATE_NOTIFIER": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
            "LC_ALL": "C",
            "RELEASE_TEST_STATE": str(self.state_path),
            "GH_REPO": "test/setup-cli",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_RUN_ID": RUN_ID,
            "EVENT_NAME": "push",
            "BEFORE": BASE,
            "AFTER": HEAD,
        }
        environment.update(overrides)
        result = subprocess.run(
            ["/bin/bash", str(SCRIPT)],
            cwd=self.directory,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        self.state = json.loads(self.state_path.read_text())
        return result

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def fresh_checkout(self):
        self.state["local_tags"] = dict(self.state["remote_tags"])
        self.state["local_annotations"] = dict(self.state["remote_annotations"])

    def add_annotation(self, tag, revision, message):
        self.state["local_tags"][tag] = revision
        self.state["remote_tags"][tag] = revision
        self.state["local_annotations"][tag] = message
        self.state["remote_annotations"][tag] = message

    def creates(self):
        return [
            call[3] for call in self.state["calls"]
            if call[:3] == ["gh", "release", "create"]
        ]

    def assert_no_publication(self):
        for call in self.state["calls"]:
            self.assertNotEqual(call[:2], ["git", "push"])
            self.assertNotEqual(call[:3], ["gh", "release", "create"])
            self.assertNotEqual(call[:3], ["gh", "release", "edit"])

    def test_push_batch_and_successful_rerun(self):
        self.assert_success(self.run_release())
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["latest"], "v1.2.0")
        self.assertEqual(self.state["remote_tags"]["v1.1.0"], MIDDLE)
        self.assert_success(self.run_release())
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])

    def test_batch_retry_after_tag_push(self):
        self.state["fail_create_once"] = "v1.1.0"
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertIn("v1.1.0", self.state["remote_tags"])
        self.assertNotIn("v1.1.0", self.state["releases"])
        self.assert_success(self.run_release())
        self.assertEqual(self.state["releases"], ["v1.0.0", "v1.1.0", "v1.2.0"])

    def test_partial_publication_retry(self):
        self.state["fail_create_once"] = "v1.2.0"
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertIn("v1.1.0", self.state["releases"])
        self.assertEqual(self.state["latest"], "v1.0.0")
        self.assert_success(self.run_release())
        self.assertEqual(self.creates().count("v1.1.0"), 1)
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_lost_success_response_retry(self):
        self.state["fail_after_create_once"] = "v1.1.0"
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertIn("v1.1.0", self.state["releases"])
        self.assert_success(self.run_release())
        self.assertEqual(self.creates().count("v1.1.0"), 1)

    def test_push_failure_retry(self):
        self.state["fail_push_once"] = "v1.1.0"
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertNotIn("v1.1.0", self.state["remote_tags"])
        self.assert_success(self.run_release())
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_latest_failure_retry(self):
        self.state["fail_edit_once"] = True
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertEqual(self.state["latest"], "v1.0.0")
        self.assert_success(self.run_release())
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_main_lookup_failure_retry(self):
        self.state["main_lookup_error"] = True
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertEqual(self.state["latest"], "v1.0.0")
        self.state["main_lookup_error"] = False
        self.assert_success(self.run_release())
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_lookup_failures_do_not_publish(self):
        for code in (0, 401, 403, 429, 500, 503):
            with self.subTest(code=code):
                self.state["calls"] = []
                self.state["lookup_errors"] = {"v1.1.0": code}
                result = self.run_release()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("release lookup failed", result.stderr)
                self.assertIn(f"Mock lookup failure: {code}", result.stderr)
                self.assert_no_publication()

    def test_unrelated_history_is_not_backfilled(self):
        historical = "9" * 40
        self.state["remote_tags"]["v0.9.0"] = historical
        self.state["local_tags"]["v0.9.0"] = historical
        self.state["versions"][historical] = "0.9.0"
        self.state["history_revisions"].append(historical)
        self.assert_success(self.run_release())
        self.assertNotIn("v0.9.0", self.state["releases"])
        self.assertFalse(any(
            call[0] == "gh" and "v0.9.0" in " ".join(call)
            for call in self.state["calls"]
        ))
        self.assertNotIn(
            ["git", "push", "origin", "refs/tags/v0.9.0"], self.state["calls"]
        )

    def test_replaced_pending_event_missing_tags_are_published_oldest_first(self):
        missed = "e" * 40
        self.state["versions"][missed] = "1.0.1"
        self.state["history_revisions"] = [HEAD, MIDDLE, missed, BASE]
        self.state["range_revisions"] = [HEAD]
        self.assert_success(self.run_release(BEFORE=MIDDLE))
        self.assertEqual(self.creates(), ["v1.0.1", "v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["remote_tags"]["v1.0.1"], missed)
        self.assertEqual(self.state["remote_tags"]["v1.1.0"], MIDDLE)
        self.assertEqual(self.state["latest"], "v1.2.0")
        self.assert_success(self.run_release(BEFORE=MIDDLE))
        self.assertEqual(self.creates(), ["v1.0.1", "v1.1.0", "v1.2.0"])

    def test_repeated_historical_version_uses_newest_version_commit(self):
        repeated = "e" * 40
        self.state["versions"][repeated] = "1.1.0"
        self.state["history_revisions"] = [HEAD, repeated, MIDDLE, BASE]
        self.state["range_revisions"] = [HEAD]
        self.assert_success(self.run_release(BEFORE=MIDDLE))
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["remote_tags"]["v1.1.0"], repeated)

    def test_catch_up_publication_failure_recovers_in_same_run_without_original_event(self):
        self.state["range_revisions"] = [HEAD]
        self.state["fail_create_once"] = "v1.1.0"
        self.assertNotEqual(self.run_release(BEFORE=MIDDLE).returncode, 0)
        self.assertIn("v1.1.0", self.state["remote_tags"])
        self.assertNotIn("v1.1.0", self.state["releases"])
        self.fresh_checkout()
        self.assert_success(self.run_release(BEFORE=MIDDLE, GITHUB_RUN_ATTEMPT="2"))
        self.assertEqual(self.state["range_revisions"], [HEAD])
        self.assertEqual(self.state["releases"], ["v1.0.0", "v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_catch_up_lost_push_response_recovers_from_remote_annotation(self):
        self.state["range_revisions"] = [HEAD]
        self.state["fail_after_push_once"] = "v1.1.0"
        self.assertNotEqual(self.run_release(BEFORE=MIDDLE).returncode, 0)
        self.assertIn("v1.1.0", self.state["remote_annotations"])
        self.fresh_checkout()
        self.assert_success(self.run_release(BEFORE=MIDDLE))
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])

    def test_catch_up_lost_publication_response_is_idempotent(self):
        self.state["range_revisions"] = [HEAD]
        self.state["fail_after_create_once"] = "v1.1.0"
        self.assertNotEqual(self.run_release(BEFORE=MIDDLE).returncode, 0)
        self.fresh_checkout()
        self.assert_success(self.run_release(BEFORE=MIDDLE))
        self.assert_success(self.run_release(BEFORE=MIDDLE))
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_unrelated_and_different_run_annotations_are_not_recovered(self):
        for message in (
            provenance("v1.1.0", MIDDLE, run_id=RUN_ID + "9"),
            f"Unrelated annotation mentioning {RUN_ID}",
            "Release notes\n\n" + provenance("v1.1.0", MIDDLE),
        ):
            with self.subTest(message=message):
                self.state["calls"] = []
                self.state["range_revisions"] = [HEAD]
                self.add_annotation("v1.1.0", MIDDLE, message)
                self.assert_success(self.run_release(BEFORE=MIDDLE))
                self.assertNotIn("v1.1.0", self.state["releases"])
                self.assertFalse(any(
                    call[0] == "gh" and "v1.1.0" in " ".join(call)
                    for call in self.state["calls"]
                ))

    def test_same_run_annotation_identity_mismatch_fails_closed(self):
        for message in (
            provenance("v9.9.9", MIDDLE),
            provenance("v1.1.0", BASE),
            provenance("v1.1.0", MIDDLE) + " extra",
        ):
            with self.subTest(message=message):
                self.state["calls"] = []
                self.add_annotation("v1.1.0", MIDDLE, message)
                result = self.run_release()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid release provenance", result.stderr)
                self.assert_no_publication()

    def test_same_run_annotation_requires_a_strict_versioned_tag_ref(self):
        for tag in ("v1.1.0-rc.1", "1.1.0", "v1.1.0/extra"):
            with self.subTest(tag=tag):
                self.state["calls"] = []
                self.add_annotation(tag, MIDDLE, provenance(tag, MIDDLE))
                self.assertNotEqual(self.run_release().returncode, 0)
                self.assert_no_publication()
                for mapping in ("local_tags", "remote_tags", "local_annotations",
                                "remote_annotations"):
                    del self.state[mapping][tag]

    def test_existing_tags_are_never_rewritten_or_reannotated(self):
        message = "Existing maintainer annotation"
        self.add_annotation("v1.1.0", MIDDLE, message)
        self.assert_success(self.run_release())
        self.assert_success(self.run_release())
        self.assertEqual(self.state["remote_annotations"]["v1.1.0"], message)
        self.assertNotIn("v1.0.0", self.state["remote_annotations"])
        tag_calls = [
            call for call in self.state["calls"] if call[0] == "git" and "tag" in call
        ]
        self.assertEqual(len(tag_calls), 1)
        self.assertIn("v1.2.0", tag_calls[0])

    def test_same_run_annotation_version_target_and_ancestry_are_validated(self):
        self.add_annotation("v1.1.0", MIDDLE, provenance("v1.1.0", MIDDLE))
        for setting, value in (("target_types", {"v1.1.0": "tag"}),
                               ("provenance_ancestor", False)):
            with self.subTest(setting=setting):
                self.state["calls"] = []
                self.state[setting] = value
                self.assertNotEqual(self.run_release().returncode, 0)
                self.assert_no_publication()
                del self.state[setting]
        self.state["versions"][MIDDLE] = "9.9.9"
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assert_no_publication()

    def test_invalid_or_missing_run_id_fails_before_publication(self):
        for run_id in ("", "0", "01", "-1", "1; false", "123\n456"):
            with self.subTest(run_id=run_id):
                self.state["calls"] = []
                result = self.run_release(GITHUB_RUN_ID=run_id)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("run ID", result.stderr)
                self.assertEqual(self.state["calls"], [])

    def test_tag_scan_failure_does_not_publish(self):
        self.state["tag_scan_status"] = 1
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assert_no_publication()

    def test_manual_retry_recovers_its_previous_current_version_after_main_advances(self):
        self.state["fail_create_once"] = "v1.2.0"
        self.assertNotEqual(self.run_release(EVENT_NAME="workflow_dispatch").returncode, 0)
        self.fresh_checkout()
        newer = "e" * 40
        self.state["versions"][newer] = "1.3.0"
        self.state["checkout_revision"] = newer
        self.state["main_version"] = "1.3.0"
        self.assert_success(self.run_release(EVENT_NAME="workflow_dispatch"))
        self.assertEqual(self.state["releases"], ["v1.0.0", "v1.2.0", "v1.3.0"])
        self.assertEqual(self.state["latest"], "v1.3.0")
        self.assertNotIn("v1.1.0", self.state["remote_tags"])

    def test_annotation_command_uses_bot_identity_and_preserves_signing_policy(self):
        self.assert_success(self.run_release())
        command = next(
            call[1:] for call in self.state["calls"]
            if call[0] == "git" and "tag" in call
        )
        real_git = shutil.which("git")
        environment = {
            "PATH": os.defpath,
            "HOME": str(self.directory / "home"),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
        }

        def run_git(*arguments, check=True):
            return subprocess.run(
                [real_git, *arguments], env=environment, text=True,
                capture_output=True, check=check,
            )

        revision = run_git("-C", str(ROOT), "rev-parse", "HEAD").stdout.strip()
        objects = run_git("-C", str(ROOT), "rev-parse", "--git-path", "objects").stdout.strip()
        environment["GIT_ALTERNATE_OBJECT_DIRECTORIES"] = str((ROOT / objects).resolve())
        version = run_git("-C", str(ROOT), "show", f"{revision}:VERSION").stdout.strip()
        tag = f"v{version}"
        tag_offset = command.index("tag")
        command[tag_offset + 2] = tag
        command[tag_offset + 3] = revision
        command[tag_offset + 5] = provenance(tag, revision)
        signer = self.directory / "signer"
        signer.write_text('#!/bin/sh\necho invoked > "$SIGNER_CALLS"\nexit 1\n')
        signer.chmod(0o755)
        environment["SIGNER_CALLS"] = str(self.directory / "signer-calls")
        for signed in (False, True):
            with self.subTest(signed=signed):
                repository = self.directory / f"tag-fixture-{signed}"
                run_git("init", "--bare", str(repository))
                prefix = [f"--git-dir={repository}"]
                if signed:
                    run_git(*prefix, "config", "tag.gpgSign", "true")
                    run_git(*prefix, "config", "gpg.program", str(signer))
                result = run_git(*prefix, *command, check=False)
                if signed:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertTrue(Path(environment["SIGNER_CALLS"]).exists())
                    self.assertNotEqual(
                        run_git(*prefix, "show-ref", "--verify", f"refs/tags/{tag}",
                                check=False).returncode, 0,
                    )
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    annotation = run_git(*prefix, "cat-file", "-p", f"refs/tags/{tag}").stdout
                    self.assertIn(
                        "tagger github-actions[bot] "
                        "<41898282+github-actions[bot]@users.noreply.github.com>", annotation,
                    )
                    record = run_git(
                        *prefix, "for-each-ref", f"--format={TAG_FORMAT}", "refs/tags"
                    ).stdout.strip()
                    self.assertEqual(record, f"refs/tags/{tag}\ttag\tcommit\t{revision}")
                    subject = run_git(
                        *prefix, "for-each-ref", "--format=%(contents:subject)",
                        f"refs/tags/{tag}",
                    ).stdout.strip()
                    self.assertEqual(subject, provenance(tag, revision))

    def test_missing_tag_with_existing_release_is_restored_without_republication(self):
        del self.state["local_tags"]["v1.0.0"]
        del self.state["remote_tags"]["v1.0.0"]
        self.assert_success(self.run_release())
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["remote_tags"]["v1.0.0"], BASE)

    def test_history_scan_failure_does_not_publish(self):
        self.state["history_status"] = 1
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assert_no_publication()

    def test_manual_dispatch_current_version_only(self):
        self.assert_success(self.run_release(EVENT_NAME="workflow_dispatch", BEFORE=""))
        self.assertEqual(self.creates(), ["v1.2.0"])
        self.assertNotIn("v1.1.0", self.state["remote_tags"])
        self.assertFalse(any(call[:2] == ["git", "log"] for call in self.state["calls"]))

    def test_initial_branch_tags_missing_versions_without_a_retry_range(self):
        self.assert_success(self.run_release(BEFORE="0" * 40))
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])

    def test_no_version_change_tags_the_version_commit(self):
        self.state["range_revisions"] = []
        self.state["checkout_revision"] = UNCHANGED
        self.state["last_version_revision"][UNCHANGED] = HEAD
        self.assert_success(self.run_release(AFTER=UNCHANGED))
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["remote_tags"]["v1.2.0"], HEAD)

    def test_non_main_dispatch_rejected(self):
        result = self.run_release(
            EVENT_NAME="workflow_dispatch", GITHUB_REF="refs/heads/feature"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("only be published from main", result.stderr)
        self.assertEqual(self.state["calls"], [])

    def test_invalid_or_unavailable_push_range_rejected(self):
        self.state["ancestor"] = False
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("push range is unavailable", result.stderr)
        self.assert_no_publication()
        self.state["ancestor"] = True
        self.state["range_status"] = 1
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assert_no_publication()

    def test_invalid_version_rejected_before_publication(self):
        self.state["versions"][HEAD] = "2.0.0-rc.1"
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assert_no_publication()

    def test_out_of_order_push_and_older_rerun_do_not_downgrade_latest(self):
        self.state["local_tags"]["v1.1.0"] = MIDDLE
        self.state["remote_tags"]["v1.1.0"] = MIDDLE
        self.state["range_revisions"] = [HEAD]
        self.assert_success(self.run_release(BEFORE=MIDDLE))
        self.assertEqual(self.state["latest"], "v1.2.0")
        self.state["range_revisions"] = [MIDDLE]
        self.assert_success(self.run_release(AFTER=MIDDLE))
        self.assertEqual(self.creates(), ["v1.2.0", "v1.1.0"])
        self.assertEqual(self.state["latest"], "v1.2.0")
        self.assert_success(self.run_release(AFTER=MIDDLE))
        self.assertEqual(self.creates(), ["v1.2.0", "v1.1.0"])
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_older_manual_dispatch_does_not_downgrade_latest(self):
        self.state["releases"].append("v1.2.0")
        self.state["latest"] = "v1.2.0"
        self.assert_success(self.run_release(EVENT_NAME="workflow_dispatch", AFTER=MIDDLE))
        self.assertEqual(self.creates(), [])
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_replaced_newer_pending_event_still_publishes_fresh_current_version(self):
        self.state["range_revisions"] = [MIDDLE]
        self.assert_success(self.run_release(AFTER=MIDDLE))
        self.assertEqual(self.creates(), ["v1.1.0", "v1.2.0"])
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_original_batch_retry_after_main_advances(self):
        self.state["fail_create_once"] = "v1.1.0"
        self.assertNotEqual(self.run_release().returncode, 0)
        newer = "e" * 40
        self.state["versions"][newer] = "1.3.0"
        self.state["history_revisions"].insert(0, newer)
        self.state["checkout_revision"] = newer
        self.state["main_version"] = "1.3.0"
        self.assert_success(self.run_release())
        self.assertEqual(
            self.state["releases"], ["v1.0.0", "v1.1.0", "v1.2.0", "v1.3.0"]
        )
        self.assertEqual(self.state["latest"], "v1.3.0")

    def test_main_advanced_during_batch_does_not_relabel_old_release_latest(self):
        self.state["main_version"] = "1.3.0"
        self.state["latest"] = "v1.3.0"
        self.assert_success(self.run_release())
        self.assertEqual(self.state["latest"], "v1.3.0")
        self.assertFalse(any(
            call[:3] == ["gh", "release", "edit"] for call in self.state["calls"]
        ))

    def test_existing_current_release_still_becomes_latest_after_batch(self):
        self.state["releases"].append("v1.2.0")
        self.assert_success(self.run_release())
        self.assertEqual(self.creates(), ["v1.1.0"])
        self.assertEqual(self.state["latest"], "v1.2.0")

    def test_workflow_contract(self):
        workflow = (ROOT / ".github/workflows/tag.yml").read_text()
        self.assertIn("run: bash .github/scripts/publish-release.sh", workflow)
        self.assertIn("if: github.ref == 'refs/heads/main'", workflow)
        self.assertIn("github.event.deleted != true", workflow)
        self.assertIn("          ref: main\n", workflow)
        self.assertIn("permissions:\n      contents: write\n", workflow)
        self.assertNotIn("write-all", workflow)
        self.assertIn("GH_TOKEN: ${{ github.token }}", workflow)
        self.assertIn("BEFORE: ${{ github.event.before }}", workflow)
        self.assertIn("AFTER: ${{ github.sha }}", workflow)
        self.assertIn("group: release-workflow", workflow)


if __name__ == "__main__":
    mock_tool = globals().get("_MOCK_TOOL")
    if mock_tool:
        raise SystemExit(mock_command(mock_tool, sys.argv[1:]))
    unittest.main(verbosity=2)
