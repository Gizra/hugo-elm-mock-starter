#!/usr/bin/env python3
"""Keep new comments short.

Only comment blocks a change touches are measured, so the long ones already
in the tree stay as they are and no baseline file goes stale.
"""

import argparse
import ast
import fnmatch
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# Words, not lines: a wrapped paragraph and a one-liner saying the same thing
# should score the same, and a short column of names is not slop.
CODE_LIMIT = 30
# Prose has a constant of its own, so either can move without the other.
DOC_LIMIT = 30

# Upstream's own files, vendored whole. Their comments are not ours to shorten.
SKIP = ("*/.stylish-haskell.yaml", "*/static/vendor/*")

LINE_COMMENT = {
    ".cabal": ("--",),
    ".css": (),
    ".elm": ("--",),
    ".hs": ("--",),
    ".js": ("//",),
    ".mjs": ("//",),
    ".cjs": ("//",),
    ".mk": ("#",),
    ".nix": ("#",),
    ".py": ("#",),
    ".sh": ("#",),
    ".sql": ("--",),
    ".ts": ("//",),
    ".yaml": ("#",),
    ".yml": ("#",),
}

BLOCK_COMMENT = {
    ".css": ("/*", "*/"),
    ".elm": ("{-", "-}"),
    ".hs": ("{-", "-}"),
    ".js": ("/*", "*/"),
    ".mjs": ("/*", "*/"),
    ".cjs": ("/*", "*/"),
    ".nix": ("/*", "*/"),
    ".sql": ("/*", "*/"),
    ".ts": ("/*", "*/"),
}

# Files a suffix does not name.
BY_NAME = {
    ".env.example": ("#",),
    ".envrc": ("#",),
    ".ghci": ("--",),
    ".gitattributes": ("#",),
    ".gitignore": ("#",),
    "Dockerfile": ("#",),
    "Makefile": ("#",),
    "requirements.txt": ("#",),
}

DOC_SUFFIXES = (".md",)

LIST_ITEM = re.compile(r"^([-*+]|\d+[.)])\s+")
HUNK = re.compile(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@")
# Git ends a path holding a space with a tab.
DIFF_FILE = re.compile(r"^\+\+\+ b/(.*?)\t?$")
# A docblock's `/**`, `*/` and the `*` starting each of its lines.
GUTTER = re.compile(r"^/?\*+/?\s?")
# Haddock and Elm mark the thing a doc comment documents; not a word.
DOC_MARK = re.compile(r"^[|^]\s*")
# The pair only a C-family comment is written with.
SLASH_STAR = ("/*", "*/")
# Make's recipe prefixes: `@` silences a line, `-` ignores its errors, `+` runs
# it under -n. A comment inside a recipe wears them, so ours start `@#`.
RECIPE_PREFIX = re.compile(r"^[-@+]+\s*")
# Files whose recipe lines carry that prefix. Elsewhere `@#` is not a comment.
RECIPE_FILES = ("Makefile",)
RECIPE_SUFFIXES = (".mk",)


@dataclass
class Block:
    """A run of comment lines, with the line numbers it covers."""

    path: str
    start: int
    end: int
    text: str
    limit: int

    @property
    def words(self):
        return len(self.text.split())


def syntax(path):
    """The line-comment tokens and block-comment pair a file uses."""
    name = Path(path).name
    if name in BY_NAME:
        return BY_NAME[name], None
    suffix = Path(path).suffix
    if suffix in LINE_COMMENT or suffix in BLOCK_COMMENT:
        return LINE_COMMENT.get(suffix, ()), BLOCK_COMMENT.get(suffix)
    return None, None


def wrote(written, block):
    """Whether the change wrote any line of `block`; None stands for all."""
    if written is None:
        return True
    return any(n in written for n in range(block.start, block.end + 1))


def join(pieces, written):
    """Pieces a blank line split, joined where the change wrote both.

    Splitting a new comment gains nothing, and an old one above it stays apart.
    """
    joined = None
    for piece in pieces:
        if joined and wrote(written, joined) and wrote(written, piece):
            joined.end = piece.end
            joined.text += " " + piece.text
            continue
        if joined:
            yield joined
        joined = piece
    if joined:
        yield joined


def prose(block, lines):
    """The words of a block comment, without its gutter.

    In `/* */` the leading `*` is punctuation, and reading stops at the
    first `@param`-style tag: API detail, not prose.
    """
    if block != SLASH_STAR:
        return " ".join(lines)
    kept = []
    for line in lines:
        line = GUTTER.sub("", line.strip())
        if line.startswith("@"):
            break
        kept.append(line)
    return " ".join(kept)


def _strip(raw, recipe):
    stripped = raw.strip()
    if recipe:
        return RECIPE_PREFIX.sub("", stripped)
    return stripped


def _opens(block, stripped):
    # `{-#` opens a Haskell pragma, which is code.
    return bool(block) and stripped.startswith(block[0]) and not stripped.startswith("{-#")


def _block_comment(path, block, stripped, number, numbered, recipe):
    """The block comment opening on this line, read on to its close.

    Takes its lines from `numbered`, the caller's iterator. None when the
    file ends before the comment does.
    """
    held, end = [DOC_MARK.sub("", stripped[len(block[0]):])], number
    while block[1] not in held[-1]:
        try:
            end, raw = next(numbered)
        except StopIteration:
            return None
        held.append(_strip(raw, recipe))
    # What follows the closing token is code again.
    held[-1] = held[-1].split(block[1])[0]
    return Block(path, number, end, prose(block, held), CODE_LIMIT)


def _line_comment(line_tokens, stripped):
    """The words of a line comment, or None when the line is not one."""
    token = next((t for t in line_tokens if stripped.startswith(t)), None)
    if not token or stripped.startswith("#!"):
        return None
    return DOC_MARK.sub("", stripped[len(token):].strip())


def _add_line(run, blank, path, number, body):
    """Add a line comment to the last piece, or start one after a blank line."""
    if run and not blank:
        run[-1].end = number
        run[-1].text += " " + body
        return
    run.append(Block(path, number, number, body, CODE_LIMIT))


def code_blocks(path, lines, written=None):
    """Comment blocks in a source file.

    A blank line inside a run of comments starts a new piece; `join` decides
    which pieces are one block.
    """
    line_tokens, block = syntax(path)
    if line_tokens is None and block is None:
        return
    recipe = Path(path).name in RECIPE_FILES or Path(path).suffix in RECIPE_SUFFIXES
    run, blank = [], False
    numbered = enumerate(lines, 1)
    for number, raw in numbered:
        stripped = _strip(raw, recipe)
        if _opens(block, stripped):
            found = _block_comment(path, block, stripped, number, numbered, recipe)
            if found:
                yield found
            continue
        body = _line_comment(line_tokens, stripped)
        if body is not None:
            _add_line(run, blank, path, number, body)
            blank = False
        elif stripped:
            yield from join(run, written)
            run = []
        elif run:
            blank = True
    yield from join(run, written)


def docstrings(path, text):
    """Python's docstrings, which carry the prose a `#` comment would."""
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return
    documented = (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
    for node in ast.walk(tree):
        if not isinstance(node, documented):
            continue
        body = ast.get_docstring(node)
        if body:
            first = node.body[0]
            yield Block(path, first.lineno, first.end_lineno, body, CODE_LIMIT)


def _markdown_kind(stripped):
    """What a stripped Markdown line does to the paragraph around it."""
    if stripped.startswith(("```", "~~~")):
        return "fence"
    if not stripped or stripped.startswith(("|", "<")):
        return "break"
    if stripped.startswith("#"):
        return "heading"
    if LIST_ITEM.match(stripped):
        return "item"
    return "text"


def _unfenced(lines):
    """Numbered Markdown lines with their kind, leaving out fenced code."""
    fence = None
    for number, raw in enumerate(lines, 1):
        stripped = raw.strip()
        if fence:
            if stripped.startswith(fence):
                fence = None
            continue
        kind = _markdown_kind(stripped)
        if kind == "fence":
            fence = stripped[:3]
        yield number, raw, stripped, kind


def _paragraph(path, run):
    """A block from (line number, text) pairs."""
    return Block(path, run[0][0], run[-1][0], " ".join(t for _, t in run), DOC_LIMIT)


def doc_blocks(path, lines):
    """Paragraphs in a Markdown file.

    A list item is its own paragraph. Fenced code, tables, headings and
    indented code outside a list are not prose.
    """
    run, in_list = [], False
    for number, raw, stripped, kind in _unfenced(lines):
        if kind == "text":
            indent = len(raw) - len(raw.lstrip())
            in_list = in_list and indent > 0
            if run or indent < 4 or in_list:
                run.append((number, re.sub(r"^>\s?", "", stripped)))
            continue
        if run:
            yield _paragraph(path, run)
        run = []
        if kind in ("heading", "item"):
            in_list = kind == "item"
        if kind == "item":
            run = [(number, LIST_ITEM.sub("", stripped))]
    if run:
        yield _paragraph(path, run)


def blocks_of(path, text, written=None):
    """Every comment block in a file, whatever the file is written in."""
    if any(fnmatch.fnmatch("/" + path, pattern) for pattern in SKIP):
        return
    lines = text.splitlines()
    if Path(path).suffix in DOC_SUFFIXES:
        yield from doc_blocks(path, lines)
        return
    yield from code_blocks(path, lines, written)
    if Path(path).suffix == ".py":
        yield from docstrings(path, text)


def added_lines(diff):
    """The lines a diff adds, per file, read from its hunk headers."""
    touched = {}
    path = None
    for line in diff.splitlines():
        match = DIFF_FILE.match(line)
        if match:
            path = match.group(1)
            touched.setdefault(path, set())
            continue
        hunk = HUNK.match(line)
        if hunk and path:
            first = int(hunk.group(1))
            count = int(hunk.group(2) or 1)
            touched[path].update(range(first, first + count))
    return touched


def git(*args):
    return subprocess.run(
        ("git", "-c", "core.quotepath=false") + args,
        capture_output=True, text=True, check=True,
    ).stdout


def ls_files(*args):
    return [path for path in git("ls-files", "-z", *args).split("\0") if path]


def changed(base):
    """What the working tree adds on top of its merge base with `base`."""
    try:
        point = git("merge-base", base, "HEAD").strip()
    except subprocess.CalledProcessError:
        point = base
    # Pinned, so no one's diff config changes what `added_lines` reads.
    diff = git(
        "diff", "--unified=0", "--diff-filter=ACMR", "--no-color",
        "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", point,
    )
    touched = added_lines(diff)
    # A file git has never seen is new whole. CI has none of these; someone
    # running this before `git add` does.
    for path in ls_files("--others", "--exclude-standard"):
        touched[path] = range(1, sys.maxsize)
    return touched


def report(block):
    """Print one block over the limit, as a PR annotation too when CI is reading."""
    print(
        f"{block.path}:{block.start}: {block.words} words, "
        f"limit {block.limit} — {block.text[:60]}…"
    )
    if os.environ.get("GITHUB_ACTIONS"):
        print(
            f"::error file={block.path},line={block.start}::"
            f"{block.words} words, limit {block.limit}. Shorten it."
        )


def _paths(explicit, touched):
    if explicit:
        return explicit
    if touched is not None:
        return sorted(touched)
    return ls_files()


def _read(path):
    """A file's text, or None when it cannot be read as UTF-8."""
    try:
        return Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        # Otherwise a mistyped path passes quietly.
        print(f"{path}: no such file", file=sys.stderr)
    except (OSError, UnicodeDecodeError):
        pass
    return None


def _over(paths, touched):
    """Blocks the change wrote that are over their limit."""
    over = []
    for path in paths:
        text = _read(path)
        if text is None:
            continue
        written = None if touched is None else touched.get(path, ())
        over += [
            block for block in blocks_of(path, text, written)
            if block.words > block.limit and wrote(written, block)
        ]
    return over


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", help="measure only what this ref does not have")
    parser.add_argument("paths", nargs="*", help="files to read (default: all)")
    args = parser.parse_args(argv)

    # Git names paths from the repo root, so read them from there.
    top = git("rev-parse", "--show-toplevel").strip()
    explicit = [os.path.relpath(os.path.abspath(p), top) for p in args.paths]
    os.chdir(top)

    touched = changed(args.base) if args.base else None
    over = _over(_paths(explicit, touched), touched)

    for block in sorted(over, key=lambda b: (b.path, b.start)):
        report(block)
    if over:
        print(f"\n{len(over)} comment(s) over the limit. Say it in fewer words.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
