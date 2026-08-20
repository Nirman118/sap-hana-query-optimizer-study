"""
sanitize_plan_csv.py

Redacts instance-identifying values from SAP HANA Database Explorer plan CSV exports
before they get committed to a public GitHub repo.

Usage:
    python sanitize_plan_csv.py path/to/plan.csv
    python sanitize_plan_csv.py plans/*.csv          (on Mac/Linux/Git Bash, shell expands the wildcard)

What it redacts:
    - HOST column values that look like a UUID (8-4-4-4-12 hex pattern) -> [REDACTED-INSTANCE-ID]
    - SCHEMA_NAME value matching your known schema -> [STUDENT_SCHEMA]
    - CONNECTION_ID (any all-digit value in that column) -> [REDACTED]

Edit MY_SCHEMA_NAME below once, then reuse this on every new plan export.
"""

import sys
import re
import csv
import io

MY_SCHEMA_NAME = "NSHARMA"  # <-- change this if your schema/username differs

UUID_PATTERN = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


def sanitize_file(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    if not rows:
        print(f"  (empty file, skipped) {path}")
        return

    header = [h.strip() for h in rows[0]]
    col_index = {name: i for i, name in enumerate(header)}

    changed = 0
    for row in rows[1:]:
        for col_name in ("HOST",):
            idx = col_index.get(col_name)
            if idx is not None and idx < len(row) and UUID_PATTERN.match(row[idx].strip()):
                row[idx] = "[REDACTED-INSTANCE-ID]"
                changed += 1

        idx = col_index.get("SCHEMA_NAME")
        if idx is not None and idx < len(row) and row[idx].strip() == MY_SCHEMA_NAME:
            row[idx] = "[STUDENT_SCHEMA]"
            changed += 1

        idx = col_index.get("CONNECTION_ID")
        if idx is not None and idx < len(row) and row[idx].strip().isdigit():
            row[idx] = "[REDACTED]"
            changed += 1

    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerows(rows)

    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(out.getvalue())

    print(f"  sanitized {changed} value(s) in {path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python sanitize_plan_csv.py <file1.csv> [file2.csv ...]")
        sys.exit(1)

    for path in sys.argv[1:]:
        sanitize_file(path)

    print("Done. Review the files, then git add/commit as usual.")
