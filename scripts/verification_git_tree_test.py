#!/usr/bin/env python3
"""Whole-tree Git authority, mutation history and unsupported-provider boundaries."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import verification_git_tree as subject


class GitTree(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="guardian-git-tree-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        # The fixture HOME stands for the whole user configuration: git reads XDG_CONFIG_HOME before HOME/.config, and
        # since lane NP1 the gate passes XDG_CONFIG_HOME on (a placement variable), so a developer's own would leak in.
        self.env = {name: value for name, value in os.environ.items() if not name.startswith("GIT_") and name != "XDG_CONFIG_HOME"}
        self.env.update(HOME=str(self.root.parent / "home"),
                        GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null", GIT_CONFIG_NOSYSTEM="1",
                        GIT_AUTHOR_NAME="test", GIT_AUTHOR_EMAIL="test@example.invalid",
                        GIT_COMMITTER_NAME="test", GIT_COMMITTER_EMAIL="test@example.invalid")
        self.git("init", "-q", "-b", "main")
        self.write("src/check.zig", "const x = 1;\n")
        self.write("docs/notes.md", "unchanged\n")
        self.write(".gitignore", "cache/\n__pycache__/\n")
        self.git("add", ".")
        self.git("commit", "-qm", "base")

    def git(self, *args):
        # `git commit` starts `git maintenance run --auto --detach`, which creates and removes objects/maintenance.lock some
        # milliseconds after the commit returns: on a loaded machine that lands inside a test's watch installation.
        return subprocess.check_output(["git", "-c", "maintenance.auto=false", *args], cwd=self.root, env=self.env)

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def authority(self):
        return subject.GitTreeAuthority(self.root, self.env)

    def test_a_fixture_commit_starts_no_detached_git_maintenance(self):
        # A commit runs `git maintenance run --auto --detach` unless told not to; that process writes the object store
        # (objects/maintenance.lock) at a moment the test does not control. The trace names every command git starts.
        trace = self.root.parent / "git-trace"
        self.env["GIT_TRACE"] = str(trace)
        self.git("commit", "--allow-empty", "-qm", "traced")
        self.assertNotIn("maintenance", trace.read_text())

    def test_object_diagnostics_report_changed_object_without_revalidating(self):
        objects = self.root / ".git/objects"
        known = self.write(".git/objects/known-object", "installed transport")
        with subject.ObjectStoreAuthority(objects) as guard:
            self.assertTrue(guard.unchanged())
            known.write_text("changed transport")
            self.assertFalse(guard.unchanged())
            before = guard.statistics
            with patch.object(guard.watcher, "drain", side_effect=AssertionError("diagnostic poll")), patch.object(Path, "lstat", side_effect=AssertionError("diagnostic stat")):
                diagnostic = guard.stability_diagnostics()
                self.assertEqual(diagnostic, guard.stability_diagnostics())
            self.assertEqual(before, guard.statistics)
            self.assertTrue(any(row["name"] == str(known) and row["reason"] == "inotify:modify" for row in diagnostic["reasons"]))
            self.assertFalse(guard.events_unchanged())

    def test_object_diagnostics_clean_observation_does_not_certify_or_poll(self):
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            before = guard.statistics
            with patch.object(guard.watcher, "drain", side_effect=AssertionError("diagnostic poll")), patch.object(Path, "lstat", side_effect=AssertionError("diagnostic stat")):
                self.assertEqual([], guard.stability_diagnostics()["reasons"])
            self.assertEqual(before, guard.statistics)
            self.assertTrue(guard.unchanged())
        self.assertTrue(any(row["reason"] == "Git object-store authority closed" for row in guard.stability_diagnostics()["reasons"]))
        self.assertFalse(guard.unchanged())

    def test_object_diagnostics_metadata_fallback_and_read_failure(self):
        source = self.write(".git/objects/diagnostic-object", "original")
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            source.write_text("changed transport")
            with patch.object(guard.watcher, "drain", return_value=True):
                self.assertFalse(guard.unchanged())
            self.assertTrue(any(row["name"] == str(source) and row["reason"] == "Git object-store metadata changed" for row in guard.stability_diagnostics()["reasons"]))
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            original_stat = Path.lstat
            def unreadable(path):
                if path == source:
                    raise PermissionError(13, "private transport unavailable", str(path))
                return original_stat(path)
            with patch.object(Path, "lstat", unreadable):
                self.assertFalse(guard.unchanged())
            diagnostic = guard.stability_diagnostics()
            self.assertTrue(diagnostic["unknown"])
            self.assertTrue(any("metadata unavailable" in row["reason"] for row in diagnostic["reasons"]))

    def test_object_diagnostics_interruption_is_sticky_and_named(self):
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            with patch.object(guard.watcher, "drain", side_effect=KeyboardInterrupt):
                self.assertRaises(KeyboardInterrupt, guard.events_unchanged)
            self.assertFalse(guard.unchanged())
            self.assertTrue(any("event validation interrupted" in row["reason"] for row in guard.stability_diagnostics()["reasons"]))
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            with patch.object(Path, "lstat", side_effect=KeyboardInterrupt):
                self.assertRaises(KeyboardInterrupt, guard.unchanged)
            self.assertFalse(guard.unchanged())
            self.assertTrue(any("metadata validation interrupted" in row["reason"] for row in guard.stability_diagnostics()["reasons"]))

    def test_object_diagnostics_event_flood_is_bounded(self):
        known = [self.write(".git/objects/known-" + str(index), "transport") for index in range(100)]
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            for path in known:
                path.write_text("changed transport")
            self.assertFalse(guard.unchanged())
            diagnostic = guard.stability_diagnostics()
            self.assertLessEqual(len(diagnostic["reasons"]), 64)
            self.assertTrue(diagnostic["truncated"])
            self.assertFalse(guard.events_unchanged())

    def worktree(self):
        """A second checkout sharing this repository's object store, as every lane's worktree does."""
        other = self.root.parent / "other"
        self.git("worktree", "add", "-q", "-b", "lane", str(other))
        return other

    def other_git(self, other, *args):
        return subprocess.check_output(["git", "-c", "maintenance.auto=false", *args], cwd=other, env=self.env)

    def loose_object(self, name="loose"):
        """A loose object that exists before any authority starts, writable so tests can damage it."""
        oid = subprocess.check_output(["git", "hash-object", "-w", "--stdin"], cwd=self.root, env=self.env,
                                      input=name.encode()).decode().strip()
        path = self.root / ".git/objects" / oid[:2] / oid[2:]
        path.chmod(0o644)
        return oid, path

    def test_objects_added_by_another_worktree_do_not_revoke_object_availability(self):
        # F21: every commit or `git add` in any worktree of a shared repository creates objects in its one store.
        # The gate holds this authority for minutes, so it failed with "inputs changed while awaiting admitted work".
        other = self.worktree()
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            (other / "added.txt").write_text("added by another worktree\n")
            self.other_git(other, "add", "added.txt")
            self.other_git(other, "commit", "-qm", "lane")
            self.assertTrue(guard.events_unchanged())
            self.assertTrue(guard.unchanged())
            self.assertFalse(any(row["facet"] == "watch" for row in guard.stability_diagnostics()["reasons"]))

    def test_new_names_in_the_object_store_are_tolerated_but_the_info_directory_is_not(self):
        objects = self.root / ".git/objects"
        with subject.ObjectStoreAuthority(objects) as guard:
            self.write(".git/objects/ab/cdef", "a loose object in a fan-out directory created later")
            self.write(".git/objects/pack/tmp_pack_x", "git's temporary pack")
            os.rename(objects / "pack/tmp_pack_x", objects / "pack/pack-new.pack")
            self.write(".git/objects/maintenance.lock", "").unlink()
            self.assertTrue(guard.unchanged())
        info = self.write(".git/objects/info/commit-graph", "installed graph")
        with subject.ObjectStoreAuthority(objects) as guard:
            self.write(".git/objects/info/alternates", "/elsewhere/objects\n")
            self.assertFalse(guard.unchanged())
        with subject.ObjectStoreAuthority(objects) as guard:
            info.unlink()
            self.assertFalse(guard.unchanged())

    def test_a_freshened_object_keeps_availability_but_a_changed_one_does_not(self):
        # Git writes an object it already has by touching the file (`utime`); a local clone hard-links it.
        _, path = self.loose_object()
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            os.utime(path, ns=(1_000_000_000, 1_000_000_000))
            os.link(path, self.root.parent / "clone-link")
            self.assertTrue(guard.events_unchanged())
            self.assertTrue(guard.unchanged())
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            path.chmod(0o000)
            self.assertFalse(guard.unchanged())
        path.chmod(0o644)
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            os.chown(path, os.getuid(), os.getgid())  # a no-op chown is an attribute event with the same identity
            self.assertTrue(guard.unchanged())

    def test_every_change_to_an_installed_object_still_revokes_object_availability(self):
        objects = self.root / ".git/objects"
        _, loose = self.loose_object("installed")
        pack = objects / "pack/provider.pack"
        held = self.root.parent / "held-object"
        def delete(): loose.unlink()
        def rewrite(): loose.write_bytes(b"corrupt")
        def replace():
            loose.rename(held)
            self.write(".git/objects/" + loose.parent.name + "/" + loose.name, "another file in its place")
        def rename_away_and_back():
            loose.rename(held)
            held.rename(loose)
        def delete_pack(): pack.unlink()
        def truncate_pack(): pack.write_bytes(b"")
        for action in (delete, rewrite, replace, rename_away_and_back, delete_pack, truncate_pack):
            with self.subTest(action=action.__name__):
                for stale in (held, loose, pack):
                    stale.unlink(missing_ok=True)
                _, loose = self.loose_object("installed")
                self.write(".git/objects/pack/provider.pack", "installed pack")
                with subject.ObjectStoreAuthority(objects) as guard:
                    action()
                    self.assertFalse(guard.events_unchanged())
                    self.assertFalse(guard.unchanged())

    def test_object_availability_binds_pack_and_commit_graph_hardlink_aba(self):
        for name in ("pack/provider.pack", "pack/provider.idx", "info/commit-graph",
                     "info/commit-graphs/graph-fixture.graph"):
            with self.subTest(name=name):
                source = self.write(".git/objects/" + name, "private transport fixture")
                alias = Path(self.temporary.name) / "outside-object-alias"
                os.link(source, alias)
                try:
                    with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
                        before = alias.stat()
                        original = alias.read_bytes()
                        alias.write_bytes(b"transient transport corruption")
                        alias.write_bytes(original)
                        os.utime(alias, ns=(before.st_atime_ns, before.st_mtime_ns))
                        with patch.object(Path, "lstat", side_effect=AssertionError("event-only metadata rescan")):
                            self.assertFalse(guard.events_unchanged())
                        self.assertFalse(guard.unchanged())
                finally:
                    alias.unlink()

    def test_object_availability_hashes_no_object_or_pack_content(self):
        objects = self.root / ".git/objects"
        with patch.object(Path, "open", side_effect=AssertionError("object content opened")):
            with subject.ObjectStoreAuthority(objects) as guard:
                self.assertTrue(guard.unchanged())
                self.assertEqual(0, guard.statistics["files_hashed"])
                self.assertEqual(0, guard.statistics["bytes_hashed"])
                self.assertLessEqual(guard.statistics["object_store_watches"], subject.MAX_OBJECT_STORE_WATCHES)

    def test_object_availability_bound_failure_releases_partial_watches(self):
        guard = subject.ObjectStoreAuthority(self.root / ".git/objects", max_watches=1)
        self.assertRaisesRegex(subject.UnsupportedGit, "watch bound exceeded", guard.__enter__)
        self.assertFalse(guard.events_unchanged())
        self.assertEqual(-1, guard.watcher.fd)

    def test_object_availability_unknown_filesystem_is_unsupported(self):
        with patch.object(subject, "_timestamp_granularity_ns", return_value=None):
            guard = subject.ObjectStoreAuthority(self.root / ".git/objects")
            self.assertRaisesRegex(subject.UnsupportedGit, "filesystem", guard.__enter__)
        self.assertFalse(guard.events_unchanged())

    def test_object_availability_interrupted_poll_cannot_revive(self):
        with subject.ObjectStoreAuthority(self.root / ".git/objects") as guard:
            with patch.object(guard.watcher, "drain", side_effect=KeyboardInterrupt):
                self.assertRaises(KeyboardInterrupt, guard.events_unchanged)
            self.assertFalse(guard.events_unchanged())

    def test_unchanged_identity_is_stable(self):
        with self.authority() as first:
            original = first.identity
            self.assertTrue(first.unchanged())
        with self.authority() as second:
            self.assertEqual(original, second.identity)

    def test_event_poll_avoids_git_commands_and_detects_aba(self):
        with self.authority() as guard:
            with patch.object(subject, "command", side_effect=AssertionError("Git rescan")):
                self.assertTrue(guard.events_unchanged())
                self.write("docs/notes.md", "transient\n")
                self.write("docs/notes.md", "unchanged\n")
                self.assertFalse(guard.events_unchanged())
        with self.assertRaises(subject.SnapshotError):
            guard.events_unchanged()

    def test_event_poll_rejects_fork_without_consuming_parent_events(self):
        with self.authority() as guard:
            with patch("verification_snapshot.os.getpid", return_value=os.getpid() + 1):
                with self.assertRaises(subject.SnapshotError):
                    guard.events_unchanged()
            self.assertTrue(guard.events_unchanged())

    def test_nested_snapshot_work_is_reported(self):
        self.write("docs/notes.md", "dirty\n")
        with self.authority() as guard:
            self.assertGreater(guard.statistics["files_hashed"], 0)
            self.assertGreater(guard.statistics["bytes_hashed"], 0)
            before = guard.statistics
            guard.events_unchanged()
            self.assertEqual(guard.statistics, before)

    def test_stale_index_stat_observation_does_not_rewrite_index(self):
        source = self.root / "docs/notes.md"
        metadata = source.stat()
        os.utime(source, ns=(metadata.st_atime_ns, metadata.st_mtime_ns - 2_000_000_000))
        index = self.root / ".git/index"
        before, inode = index.read_bytes(), index.stat().st_ino
        with self.authority() as guard:
            self.assertTrue(guard.unchanged())
            self.assertEqual(subject.digest(b""), guard.identity["diff"])
        self.assertEqual(index.read_bytes(), before)
        self.assertEqual(index.stat().st_ino, inode)

    def test_external_index_replacement_remains_invalidating(self):
        index = self.root / ".git/index"
        with self.authority() as guard:
            replacement = index.with_name("index-replacement")
            replacement.write_bytes(index.read_bytes())
            os.replace(replacement, index)
            self.assertFalse(guard.unchanged())

    def test_outside_source_tracked_dirty_clean_aba_revokes(self):
        with self.authority() as guard:
            self.write("docs/notes.md", "transient\n")
            self.write("docs/notes.md", "unchanged\n")
            self.assertEqual(b"", self.git("diff", "HEAD"))
            self.assertFalse(guard.unchanged())

    def test_untracked_file_arrival_and_removal_revokes(self):
        with self.authority() as guard:
            self.write("untracked", "arrival").unlink()
            self.assertEqual(b"", self.git("ls-files", "--others", "--exclude-standard"))
            self.assertFalse(guard.unchanged())

    def test_worktree_git_indirection_retarget_restore_revokes(self):
        metadata = self.root.parent / "metadata"
        (self.root / ".git").rename(metadata)
        marker = self.write(".git", "gitdir: " + str(metadata) + "\n")
        original = marker.read_text()
        with self.authority() as guard:
            marker.write_text("gitdir: /missing/transient\n")
            marker.write_text(original)
            self.assertFalse(guard.unchanged())

    def test_new_directory_arrival_and_removal_revokes(self):
        with self.authority() as guard:
            path = self.write("new/child", "arrival")
            path.unlink()
            path.parent.rmdir()
            self.assertFalse(guard.unchanged())

    def test_git_indirection_ignored_hardlink_retarget_restore_revokes(self):
        metadata = self.root.parent / "metadata"
        (self.root / ".git").rename(metadata)
        marker = self.write(".git", "gitdir: " + str(metadata) + "\n")
        original = marker.read_text()
        (self.root / "cache").mkdir()
        alias = self.root / "cache/marker-alias"
        os.link(marker, alias)
        with self.authority() as guard:
            alias.write_text("gitdir: /missing/transient\n")
            alias.write_text(original)
            self.assertFalse(guard.unchanged())

    def test_git_indirection_symlink_refuses(self):
        metadata = self.root.parent / "metadata"
        (self.root / ".git").rename(metadata)
        (self.root / ".git").symlink_to(metadata, target_is_directory=True)
        with self.assertRaises(subject.UnsupportedGit):
            with self.authority():
                pass

    def test_existing_empty_directory_is_watched(self):
        (self.root / "empty").mkdir()
        with self.authority() as guard:
            self.write("empty/child", "arrival").unlink()
            self.assertFalse(guard.unchanged())

    def test_existing_ignored_output_churn_remains_stable(self):
        self.write("cache/output", "before")
        with self.authority() as guard:
            self.write("cache/output", "after")
            self.write("cache/new/child", "arrival")
            self.assertTrue(guard.unchanged())

    def test_tracked_file_inside_ignored_directory_is_watched(self):
        self.write("cache/tracked", "before")
        self.git("add", "-f", "cache/tracked")
        self.git("commit", "-qm", "tracked ignored path")
        with self.authority() as guard:
            self.write("cache/tracked", "after")
            self.assertFalse(guard.unchanged())

    def test_tracked_hardlink_written_through_ignored_alias_aba_revokes(self):
        (self.root / "cache").mkdir()
        alias = self.root / "cache/alias"
        os.link(self.root / "docs/notes.md", alias)
        with self.authority() as guard:
            alias.write_text("transient ignored alias write\n")
            alias.write_text("unchanged\n")
            self.assertEqual(b"", self.git("diff", "HEAD"))
            self.assertFalse(guard.unchanged())

    def test_dirty_outside_source_bytes_enter_identity(self):
        self.write("docs/notes.md", "first dirty\n")
        with self.authority() as first:
            previous = first.identity
            self.assertEqual(["docs/notes.md"], [row["path"] for row in previous["dirty_files"]])
        self.write("docs/notes.md", "other dirty\n")
        with self.authority() as second:
            self.assertNotEqual(previous, second.identity)

    def test_dirty_binary_bytes_are_bound_beyond_git_binary_marker(self):
        binary = self.root / "docs/binary"
        binary.write_bytes(b"\0original")
        self.git("add", "docs/binary")
        self.git("commit", "-qm", "binary")
        binary.write_bytes(b"\0first")
        with self.authority() as first:
            previous = first.identity
        binary.write_bytes(b"\0other")
        with self.authority() as second:
            self.assertNotEqual(previous["dirty_files"], second.identity["dirty_files"])

    def test_repository_ignore_and_attributes_aba_revoke(self):
        for name in (".gitignore", ".gitattributes"):
            path = self.write(name, "# original\n")
            with self.authority() as guard:
                path.write_text("# changed\n")
                path.write_text("# original\n")
                self.assertFalse(guard.unchanged())

    def test_global_ignore_missing_arrival_revokes(self):
        path = Path(self.env["HOME"]) / ".config/git/ignore"
        with self.authority() as guard:
            path.parent.mkdir(parents=True)
            path.write_text("docs/\n")
            self.assertFalse(guard.unchanged())

    def test_untracked_or_ignored_policy_hardlink_aba_revokes(self):
        (self.root / "cache").mkdir()
        for ignored in (False, True):
            self.write(".gitignore", "cache/\n" + ("docs/.gitignore\ndocs/.gitattributes\n" if ignored else ""))
            for name in (".gitignore", ".gitattributes"):
                policy = self.write("docs/" + name, "# original\n")
                alias = self.root / "cache" / (name + "-alias-" + str(ignored))
                os.link(policy, alias)
                with self.authority() as guard:
                    alias.write_text("* -diff\n" if name == ".gitattributes" else "*\n")
                    alias.write_text("# original\n")
                    self.assertFalse(guard.unchanged())

    def test_dangling_policy_ancestor_alias_refuses(self):
        home = Path(self.env["HOME"])
        home.mkdir()
        (home / ".config").symlink_to(self.root.parent / "missing-config", target_is_directory=True)
        with self.assertRaises(subject.UnsupportedGit):
            with self.authority():
                pass

    def test_git_output_is_bounded_while_reading(self):
        with patch.object(subject, "MAX_OUTPUT", 40):
            with self.assertRaises(subject.UnsupportedGit):
                subject.command(self.root, self.env, "log", "-1")

    def test_config_include_external_diff_filter_and_stat_weakening_refuse(self):
        for name, value in (("include.path", "missing"), ("diff.external", "custom"),
                            ("filter.custom.clean", "custom"), ("core.trustctime", "false"),
                            ("core.checkstat", "minimal"), ("core.fsmonitor", "true")):
            self.git("config", name, value)
            try:
                with self.assertRaises(subject.UnsupportedGit):
                    with self.authority():
                        pass
            finally:
                self.git("config", "--unset", name)

    def test_dirty_symlink_provider_refuses(self):
        (self.root / "alias").symlink_to("docs/notes.md")
        self.git("add", "alias")
        self.git("commit", "-qm", "alias")
        (self.root / "alias").unlink()
        (self.root / "alias").symlink_to("src/check.zig")
        with self.assertRaises(subject.UnsupportedGit):
            with self.authority():
                pass

    def test_assume_unchanged_index_entry_refuses(self):
        self.git("update-index", "--assume-unchanged", "docs/notes.md")
        with self.assertRaises(subject.UnsupportedGit):
            with self.authority():
                pass

    def test_split_index_provider_refuses(self):
        self.git("update-index", "--split-index")
        with self.assertRaises(subject.UnsupportedGit):
            with self.authority():
                pass

    def test_chained_symbolic_head_refuses(self):
        self.git("symbolic-ref", "refs/heads/alias", "refs/heads/main")
        self.git("symbolic-ref", "HEAD", "refs/heads/alias")
        with self.assertRaises(subject.UnsupportedGit):
            with self.authority():
                pass

    def test_watch_installation_race_is_rejected(self):
        original = subject.command
        changed = False
        def command(root, env, *args, **kwargs):
            nonlocal changed
            result = original(root, env, *args, **kwargs)
            if args[0] == "check-ignore" and b"docs/notes.md" in kwargs.get("input", b"") and not changed:
                changed = True
                self.write("docs/notes.md", "racing change\n")
            return result
        with patch.object(subject, "command", side_effect=command):
            with self.assertRaises(subject.UnsupportedGit):
                with self.authority():
                    pass

    def test_global_config_values_are_not_in_identity(self):
        self.env.pop("GIT_CONFIG_GLOBAL")
        path = Path(self.env["HOME"]) / ".gitconfig"
        path.parent.mkdir(parents=True)
        path.write_text('[user]\nname = unrelated-private-value\n')
        with self.authority() as guard:
            self.assertNotIn("unrelated-private-value", repr(guard.identity))


if __name__ == "__main__":
    unittest.main()
