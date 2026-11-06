"""What the comment limit counts, and what it leaves alone."""

import contextlib
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_comments as checker


def words_at(path, text, line):
    """The size of the block starting at `line`, or None if there is none."""
    for block in checker.blocks_of(path, text):
        if block.start == line:
            return block.words
    return None


def sizes(path, text):
    return [block.words for block in checker.blocks_of(path, text)]


class CodeComments(unittest.TestCase):
    def test_a_run_of_lines_is_one_block(self):
        source = "-- one two\n-- three four\nmain = pure ()\n"
        self.assertEqual(sizes("a.hs", source), [4])

    def test_a_blank_line_keeps_the_block_open(self):
        source = "# one two\n\n# three four\n"
        self.assertEqual(sizes("a.sh", source), [4])

    def test_a_blank_line_the_change_wrote_both_sides_of_keeps_it_open(self):
        blocks = checker.blocks_of("a.sh", "# one two\n\n# three four\n", {1, 3})
        self.assertEqual([block.words for block in blocks], [4])

    def test_a_new_comment_under_an_old_one_is_its_own_block(self):
        blocks = checker.blocks_of("a.sh", "# one two three\n\n# four\n", {3})
        self.assertEqual([block.words for block in blocks], [3, 1])

    def test_code_between_two_comments_splits_them(self):
        source = "# one two\nrun\n# three four\n"
        self.assertEqual(sizes("a.sh", source), [2, 2])

    def test_a_shebang_is_not_a_comment(self):
        self.assertEqual(sizes("a.sh", "#!/bin/sh\nrun\n"), [])

    def test_a_haskell_pragma_is_not_a_comment(self):
        self.assertEqual(sizes("a.hs", "{-# LANGUAGE OverloadedStrings #-}\n"), [])

    def test_a_block_comment_is_read_whole(self):
        source = "{-| one two\nthree four\n-}\nmain = pure ()\n"
        self.assertEqual(sizes("a.elm", source), [4])

    def test_haddock_marks_are_not_words(self):
        self.assertEqual(sizes("a.hs", "-- | one two\n"), [2])

    def test_a_trailing_comment_is_not_read(self):
        self.assertEqual(sizes("a.hs", "main = pure () -- one two three\n"), [])

    def test_a_python_docstring_counts(self):
        self.assertEqual(sizes("a.py", '"""one two three"""\n'), [3])

    def test_an_elm_line_comment_counts(self):
        self.assertEqual(sizes("a.elm", "-- one two\nx =\n    1\n"), [2])

    def test_the_bar_of_an_elm_doc_comment_is_not_a_word(self):
        source = "{-| one two\nthree\n-}\nx =\n    1\n"
        self.assertEqual(sizes("a.elm", source), [3])

    def test_a_typescript_comment_counts(self):
        source = "// one two\nconst a = 1;\n/**\n * three\n * @param four\n */\n"
        self.assertEqual(sizes("a.ts", source), [2, 1])

    def test_a_docblock_gutter_is_not_words(self):
        source = "/**\n * one two\n * three\n */\nconst a = 1;\n"
        self.assertEqual(sizes("a.js", source), [3])

    def test_a_star_opening_a_haskell_comment_line_is_a_word(self):
        source = "{- one\n* two\n-}\nmain = pure ()\n"
        self.assertEqual(sizes("a.hs", source), [3])

    def test_an_unknown_file_type_has_no_comments(self):
        self.assertEqual(sizes("a.docx", "# one two\n"), [])

    def test_a_skipped_file_is_not_read(self):
        source = "# one two\n"
        self.assertEqual(sizes("NadavLev/web/.stylish-haskell.yaml", source), [])

    def test_a_comment_inside_a_make_recipe_counts(self):
        source = "dev:\n\t@# one two\n\t@# three four\n\t@echo hi\n"
        self.assertEqual(sizes("Makefile", source), [4])

    def test_every_recipe_prefix_make_allows_is_stripped(self):
        source = "dev:\n\t-@+# one two three\n"
        self.assertEqual(sizes("Makefile", source), [3])

    def test_a_silenced_recipe_line_is_still_code(self):
        source = "dev:\n\t@# one two\n\t@echo hi\n\t@# three\n"
        self.assertEqual(sizes("Makefile", source), [2, 1])

    def test_a_help_line_and_the_recipe_comment_under_it_are_two_blocks(self):
        source = "## one two\ndev:\n\t@# three four five\n"
        self.assertEqual(sizes("Makefile", source), [3, 3])

    def test_an_at_sign_outside_a_makefile_is_not_a_comment(self):
        self.assertEqual(sizes("a.sh", "@# one two\n"), [])

    def test_an_included_mk_file_is_read_like_a_makefile(self):
        source = "# one two\ndev:\n\t@# three four five\n"
        self.assertEqual(sizes("tools/make/common.mk", source), [2, 3])


class DocParagraphs(unittest.TestCase):
    def test_a_paragraph_is_a_block(self):
        self.assertEqual(sizes("a.md", "one two three\nfour five\n"), [5])

    def test_a_blank_line_ends_a_paragraph(self):
        self.assertEqual(sizes("a.md", "one two\n\nthree four five\n"), [2, 3])

    def test_a_list_item_is_its_own_paragraph(self):
        source = "- one two\n- three four five\n"
        self.assertEqual(sizes("a.md", source), [2, 3])

    def test_a_list_item_keeps_its_continuation(self):
        source = "- one two\n  three four\n"
        self.assertEqual(sizes("a.md", source), [4])

    def test_fenced_code_is_not_prose(self):
        source = "one two\n\n```\nmake dev  # three four\n```\n"
        self.assertEqual(sizes("a.md", source), [2])

    def test_headings_and_tables_are_not_prose(self):
        source = "## one two three\n\n| four | five |\n"
        self.assertEqual(sizes("a.md", source), [])

    def test_an_indented_code_block_is_not_prose(self):
        source = "## Running things\n\n    make dev one two\n"
        self.assertEqual(sizes("a.md", source), [])

    def test_an_indented_line_under_a_list_is_prose(self):
        source = "- one two\n\n    three four five\n"
        self.assertEqual(words_at("a.md", source, 3), 3)

    def test_a_doc_gets_its_own_limit(self):
        # Its own constant, whatever number it stands at.
        blocks = list(checker.blocks_of("a.md", "one two\n"))
        self.assertEqual(blocks[0].limit, checker.DOC_LIMIT)

    def test_code_gets_the_code_limit(self):
        blocks = list(checker.blocks_of("a.sh", "# one two\n"))
        self.assertEqual(blocks[0].limit, checker.CODE_LIMIT)


class ChangedLines(unittest.TestCase):
    def test_hunk_headers_name_the_added_lines(self):
        diff = (
            "diff --git a/x.hs b/x.hs\n"
            "--- a/x.hs\n"
            "+++ b/x.hs\n"
            "@@ -3,0 +4,2 @@\n"
            "+-- one\n"
            "+-- two\n"
        )
        self.assertEqual(checker.added_lines(diff), {"x.hs": {4, 5}})

    def test_a_hunk_without_a_count_adds_one_line(self):
        diff = "+++ b/x.hs\n@@ -3 +3 @@\n"
        self.assertEqual(checker.added_lines(diff), {"x.hs": {3}})

    def test_a_deletion_adds_nothing(self):
        diff = "+++ b/x.hs\n@@ -3,2 +2,0 @@\n"
        self.assertEqual(checker.added_lines(diff), {"x.hs": set()})

    def test_a_path_with_a_space_loses_the_tab_git_ends_it_with(self):
        diff = "+++ b/a b.hs\t\n@@ -3 +3 @@\n"
        self.assertEqual(checker.added_lines(diff), {"a b.hs": {3}})


class AgainstGit(unittest.TestCase):
    """The whole checker, run the way CI and a developer run it."""

    LONG = "# " + " ".join(["word"] * 40) + "\n"

    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.addCleanup(os.chdir, os.getcwd())
        self.repo = Path(scratch.name)
        (self.repo / "sub").mkdir()
        self.git("init", "-q")
        self.commit({"sub/a.sh": "run\n", "sub/a b.sh": "run\n"})

    def git(self, *args):
        subprocess.run(
            ("git", "-c", "user.name=t", "-c", "user.email=t@t",
             "-c", "commit.gpgsign=false") + args,
            cwd=self.repo, check=True, capture_output=True,
        )

    def commit(self, files):
        for name, text in files.items():
            (self.repo / name).write_text(text)
        self.git("add", ".")
        self.git("commit", "-q", "--no-verify", "-m", "base")

    def check(self, where="."):
        os.chdir(self.repo / where)
        with contextlib.redirect_stdout(io.StringIO()):
            return checker.main(["--base", "HEAD"])

    def test_a_long_comment_in_a_changed_file_is_over(self):
        (self.repo / "sub/a.sh").write_text("run\n" + self.LONG)
        self.assertEqual(self.check(), 1)

    def test_a_file_git_has_never_seen_is_new_whole(self):
        (self.repo / "sub/new file.sh").write_text(self.LONG)
        self.assertEqual(self.check(), 1)

    def test_a_space_in_a_changed_file_name_is_read(self):
        (self.repo / "sub/a b.sh").write_text("run\n" + self.LONG)
        self.assertEqual(self.check(), 1)

    def test_a_subdirectory_reads_what_the_root_does(self):
        (self.repo / "sub/a.sh").write_text("run\n" + self.LONG)
        self.assertEqual(self.check("sub"), 1)

    def test_diff_config_does_not_change_what_is_read(self):
        (self.repo / "sub/a.sh").write_text("run\n" + self.LONG)
        for key, value in (
            ("diff.mnemonicPrefix", "true"),
            ("diff.noprefix", "true"),
            ("color.diff", "always"),
        ):
            config = {
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": key,
                "GIT_CONFIG_VALUE_0": value,
            }
            with self.subTest(key), mock.patch.dict(os.environ, config):
                self.assertEqual(self.check(), 1)

    def test_a_short_comment_under_an_old_long_one_passes(self):
        self.commit({"sub/a.sh": self.LONG + "run\n"})
        (self.repo / "sub/a.sh").write_text(self.LONG + "\n# new\nrun\n")
        self.assertEqual(self.check(), 0)


if __name__ == "__main__":
    unittest.main()
