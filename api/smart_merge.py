import argparse
import difflib
from dataclasses import dataclass, field
from typing import List, Dict, Tuple


def _normalize_style(s: str) -> str:
    """Normalize for style-only comparison: trim, collapse spaces, normalize quotes."""
    s = s.strip()
    s = s.replace('"', "'")
    parts = s.split()
    return " ".join(parts)


def _is_comment(line: str) -> bool:
    """Detect simple comment lines."""
    stripped = line.lstrip()
    return stripped.startswith("#") or stripped.startswith("//")


@dataclass
class ConflictRecord:
    kind: str
    base: List[str]
    local: List[str]
    remote: List[str]
    auto_resolved: bool = False


@dataclass
class ConflictAnalyzer:
    """Collects and classifies conflicts for reporting."""

    conflicts: List[ConflictRecord] = field(default_factory=list)

    def add(self, kind: str, base: List[str], local: List[str], remote: List[str], auto_resolved: bool):
        self.conflicts.append(
            ConflictRecord(kind=kind, base=base, local=local, remote=remote, auto_resolved=auto_resolved)
        )

    def summary(self) -> Dict[str, object]:
        total = len(self.conflicts)
        auto = sum(1 for c in self.conflicts if c.auto_resolved)
        unresolved = total - auto

        by_type = {}
        for c in self.conflicts:
            by_type.setdefault(c.kind, {"total": 0, "auto_resolved": 0, "needs_manual": 0})
            by_type[c.kind]["total"] += 1
            if c.auto_resolved:
                by_type[c.kind]["auto_resolved"] += 1
            else:
                by_type[c.kind]["needs_manual"] += 1

        return {
            "total_conflicts": total,
            "auto_resolved_conflicts": auto,
            "unresolved_conflicts": unresolved,
            "by_type": by_type,
        }


def _build_diff_maps(base: List[str], other: List[str]) -> Tuple[List[Tuple[str, int]], Dict[int, List[str]]]:
    """Build per-line change map base->other plus insertions before base index."""
    matcher = difflib.SequenceMatcher(a=base, b=other)
    status: List[Tuple[str, int]] = [(None, -1)] * len(base)  # (tag, j_index)
    inserts: Dict[int, List[str]] = {}

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            for offset in range(i2 - i1):
                i = i1 + offset
                status[i] = ("equal", j1 + offset)
        elif tag == "replace":
            overlap = min(i2 - i1, j2 - j1)
            for offset in range(overlap):
                i = i1 + offset
                status[i] = ("replace", j1 + offset)
            for i in range(i1 + overlap, i2):
                status[i] = ("delete", -1)
            if j1 + overlap < j2:
                inserts.setdefault(i2, []).extend(other[j1 + overlap : j2])
        elif tag == "delete":
            for i in range(i1, i2):
                status[i] = ("delete", -1)
        elif tag == "insert":
            inserts.setdefault(i1, []).extend(other[j1:j2])

    for i in range(len(base)):
        if status[i][0] is None:
            status[i] = ("equal", status[i][1])

    return status, inserts


def smart_merge(base_text: str, local_text: str, remote_text: str) -> Dict[str, object]:
    """
    Smart 3-way merge with simple heuristics and conflict analysis.
    Returns dict with merged_text, conflict_summary and quality report.
    """
    base_lines = base_text.splitlines(keepends=True)
    local_lines = local_text.splitlines(keepends=True)
    remote_lines = remote_text.splitlines(keepends=True)

    local_status, local_inserts = _build_diff_maps(base_lines, local_lines)
    remote_status, remote_inserts = _build_diff_maps(base_lines, remote_lines)

    analyzer = ConflictAnalyzer()
    merged: List[str] = []

    def emit_raw_conflict(base_block: List[str], local_block: List[str], remote_block: List[str]):
        """Emit unresolved git-style conflict markers."""
        merged.append("<<<<<<< LOCAL\n")
        merged.extend(local_block)
        if local_block and not local_block[-1].endswith("\n"):
            merged[-1] = merged[-1] + "\n"
        merged.append("=======\n")
        merged.extend(remote_block)
        if remote_block and not remote_block[-1].endswith("\n"):
            merged[-1] = merged[-1] + "\n"
        merged.append(">>>>>>> REMOTE\n")

    def classify_conflict(base_block: List[str], local_block: List[str], remote_block: List[str]) -> str:
        """Rough conflict type classification."""
        base_norm = "".join(base_block).strip()
        local_norm = "".join(local_block).strip()
        remote_norm = "".join(remote_block).strip()

        if _normalize_style(local_norm) == _normalize_style(remote_norm):
            return "Formatting Only"

        if (not local_norm and remote_norm) or (local_norm and not remote_norm):
            return "Deletion Conflict"

        return "Logic Overlap"

    def handle_inserts(i: int):
        l_ins = local_inserts.get(i, [])
        r_ins = remote_inserts.get(i, [])
        if not l_ins and not r_ins:
            return

        # Additive heuristic: both added, different -> append both, mark as auto-resolved
        if l_ins and r_ins and l_ins != r_ins:
            analyzer.add(
                kind="Logic Overlap",
                base=[],
                local=l_ins,
                remote=r_ins,
                auto_resolved=True,
            )
            merged.extend(l_ins + r_ins)
            return

        if l_ins and not r_ins:
            merged.extend(l_ins)
        elif r_ins and not l_ins:
            merged.extend(r_ins)
        else:
            # Same insertion on both sides
            merged.extend(l_ins)

    for i in range(len(base_lines) + 1):
        handle_inserts(i)

        if i == len(base_lines):
            break

        base_line = base_lines[i]
        l_tag, l_j = local_status[i]
        r_tag, r_j = remote_status[i]

        local_line = None
        if l_tag != "delete" and l_j is not None and l_j >= 0 and l_j < len(local_lines):
            local_line = local_lines[l_j]

        remote_line = None
        if r_tag != "delete" and r_j is not None and r_j >= 0 and r_j < len(remote_lines):
            remote_line = remote_lines[r_j]

        # No changes
        if l_tag == "equal" and r_tag == "equal":
            merged.append(base_line)
            continue

        # Only LOCAL changed
        if l_tag != "equal" and r_tag == "equal":
            if l_tag == "delete":
                continue
            merged.append(local_line if local_line is not None else base_line)
            continue

        # Only REMOTE changed
        if l_tag == "equal" and r_tag != "equal":
            if r_tag == "delete":
                continue
            merged.append(remote_line if remote_line is not None else base_line)
            continue

        # Both changed -> apply heuristics
        base_block = [base_line]
        local_block = [] if l_tag == "delete" else ([local_line] if local_line is not None else [])
        remote_block = [] if r_tag == "delete" else ([remote_line] if remote_line is not None else [])

        local_norm = _normalize_style("".join(local_block))
        remote_norm = _normalize_style("".join(remote_block))

        # Style heuristic: only whitespace/quotes differences
        if local_norm == remote_norm:
            analyzer.add("Formatting Only", base_block, local_block, remote_block, auto_resolved=True)
            merged.extend(local_block)
            continue

        # Semantic hint: comment vs code
        local_is_comment = all(_is_comment(l) or not l.strip() for l in local_block) and any(
            _is_comment(l) for l in local_block
        )
        remote_is_comment = all(_is_comment(l) or not l.strip() for l in remote_block) and any(
            _is_comment(l) for l in remote_block
        )

        if local_is_comment and not remote_is_comment:
            # Keep code change (remote) and keep new comment (local)
            analyzer.add("Logic Overlap", base_block, local_block, remote_block, auto_resolved=True)
            merged.extend(local_block + remote_block)
            continue

        if remote_is_comment and not local_is_comment:
            analyzer.add("Logic Overlap", base_block, local_block, remote_block, auto_resolved=True)
            merged.extend(remote_block + local_block)
            continue

        # Deletion vs modification
        if (l_tag == "delete" and r_tag != "delete") or (r_tag == "delete" and l_tag != "delete"):
            kind = "Deletion Conflict"
        else:
            kind = classify_conflict(base_block, local_block, remote_block)

        analyzer.add(kind, base_block, local_block, remote_block, auto_resolved=False)
        emit_raw_conflict(base_block, local_block, remote_block)

    merged_text = "".join(merged)
    quality = evaluate_merge(merged_text)

    return {
        "merged_text": merged_text,
        "conflicts": analyzer.summary(),
        "quality": quality,
    }


def evaluate_merge(text: str) -> Dict[str, object]:
    """Very lightweight quality check: bracket balance and conflict markers."""
    markers = text.count("<<<<<<<") + text.count(">>>>>>>") + text.count("=======")

    # Simple bracket balance check
    pairs = {"(": ")", "[": "]", "{": "}"}
    opens = set(pairs.keys())
    closes = set(pairs.values())
    stack: List[str] = []

    for ch in text:
        if ch in opens:
            stack.append(ch)
        elif ch in closes:
            if not stack:
                stack.append("?")
                break
            top = stack.pop()
            if pairs[top] != ch:
                stack.append("?")
                break

    balanced = len(stack) == 0

    return {
        "balanced_brackets": balanced,
        "unresolved_markers": markers,
        "ok": balanced and markers == 0,
    }


def _cli():
    """CLI helper to run smart_merge with three strings or files."""
    parser = argparse.ArgumentParser(description="Smart 3-way merge tester (base, local, remote).")
    parser.add_argument("--base", help="Base text or @path/to/file", required=True)
    parser.add_argument("--local", help="Local text or @path/to/file", required=True)
    parser.add_argument("--remote", help="Remote text or @path/to/file", required=True)
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Print conflict summary and quality report to stderr.",
    )
    args = parser.parse_args()

    def read_arg(value: str) -> str:
        if value.startswith("@"):
            path = value[1:]
            with open(path, "r", encoding="utf-8") as f:
                return f.read()
        return value

    base = read_arg(args.base)
    local = read_arg(args.local)
    remote = read_arg(args.remote)

    result = smart_merge(base, local, remote)
    print(result["merged_text"], end="")

    if args.stats:
        import sys as _sys
        import json as _json

        meta = {k: v for k, v in result.items() if k != "merged_text"}
        print("\n\n--- SMART MERGE META ---", file=_sys.stderr)
        print(_json.dumps(meta, indent=2, ensure_ascii=False), file=_sys.stderr)


if __name__ == "__main__":
    _cli()

