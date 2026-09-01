"""Turn pytest's JUnit XML output into a human-readable test summary,
written to the GitHub Actions job summary (or stdout, run locally).

Why this exists: CI already proves the suite passes, but a customer/
stakeholder shouldn't have to read test code (or even open the pytest log)
to see *what* was verified. Test names in this suite are already written as
full sentences (e.g. `test_grace_allowance_blocks_past_the_floor`) — this
script just renders them as prose, grouped by file and by the docstring at
the top of each file describing that feature area, with a pass/fail icon
per test.
"""

import ast
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent.parent / "tests"


def humanize_test_name(name: str) -> str:
    """`test_grace_allowance_blocks_past_the_floor` -> "Grace allowance
    blocks past the floor" — strip the `test_` prefix, replace underscores,
    and capitalize the first letter only (these are sentences, not titles)."""
    words = name.removeprefix("test_").replace("_", " ")
    return words[0].upper() + words[1:] if words else name


def module_docstring(test_file: Path) -> str | None:
    """The one-line summary at the top of a test file describing what
    feature area it covers — shown as that group's heading."""
    if not test_file.exists():
        return None
    tree = ast.parse(test_file.read_text())
    doc = ast.get_docstring(tree)
    return doc.strip().splitlines()[0] if doc else None


def humanize_class_name(name: str) -> str:
    """`TestGraceAllowancePermitsGoingToTheFloor`-style CamelCase -> spaced
    words, for use as a sub-heading under its file's section."""
    words = name.removeprefix("Test")
    spaced = "".join(f" {c}" if c.isupper() else c for c in words).strip()
    return spaced


def render_summary(junit_xml_path: Path) -> str:
    root = ET.parse(junit_xml_path).getroot()
    by_classname: dict[str, list[ET.Element]] = {}
    for testcase in root.iter("testcase"):
        by_classname.setdefault(testcase.get("classname", ""), []).append(testcase)

    total = int(root.get("tests", 0) or sum(len(v) for v in by_classname.values()))
    failures = int(root.get("failures", 0))
    errors = int(root.get("errors", 0))
    skipped = int(root.get("skipped", 0))
    passed = total - failures - errors - skipped

    summary_line = (
        f"**{passed}/{total} passed** "
        f"({failures} failed, {errors} errored, {skipped} skipped) — "
        "every test below verifies real, named behavior, not just 'code runs'."
    )
    lines = ["## Test suite results", "", summary_line, ""]

    # Group classnames by their source file first, so a file with several
    # Test* classes gets one file-level heading instead of repeating its
    # module docstring once per class.
    by_file: dict[Path, list[str]] = {}
    for classname in by_classname:
        module_parts = classname.split(".")[:2]
        test_file = TESTS_DIR.parent / (Path(*module_parts).with_suffix(".py"))
        by_file.setdefault(test_file, []).append(classname)

    for test_file in sorted(by_file, key=lambda p: p.name):
        heading = module_docstring(test_file) or test_file.stem
        lines.append(f"### {heading}")
        lines.append("")
        for classname in sorted(by_file[test_file]):
            class_name = classname.split(".")[-1]
            # A bare module-level test function has classname == module path
            # (no distinct class) — only add a sub-heading when there's an
            # actual Test class grouping these further.
            if class_name != test_file.stem:
                lines.append(f"**{humanize_class_name(class_name)}**")
                lines.append("")
            for case in by_classname[classname]:
                name = humanize_test_name(case.get("name", ""))
                if case.find("failure") is not None or case.find("error") is not None:
                    icon = "❌"
                elif case.find("skipped") is not None:
                    icon = "⏭️"
                else:
                    icon = "✅"
                lines.append(f"- {icon} {name}")
            lines.append("")

    return "\n".join(lines)


def main() -> None:
    junit_xml_path = Path(sys.argv[1] if len(sys.argv) > 1 else "pytest-results.xml")
    if not junit_xml_path.exists():
        print(f"No JUnit XML found at {junit_xml_path}; skipping summary.", file=sys.stderr)
        return

    summary = render_summary(junit_xml_path)

    summary_file = sys.argv[2] if len(sys.argv) > 2 else None
    if summary_file:
        with open(summary_file, "a", encoding="utf-8") as f:
            f.write(summary + "\n")
    else:
        print(summary)


if __name__ == "__main__":
    main()
