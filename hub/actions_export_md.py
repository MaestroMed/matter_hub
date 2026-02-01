"""Export a slice of the ledger to Markdown.

Usage:
  python hub/actions_export_md.py --out hub/_reports/actions.md --limit 200
"""

import argparse
import json
import sqlite3
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', default=str(Path(__file__).resolve().parent / 'actions.sqlite'))
    ap.add_argument('--out', required=True)
    ap.add_argument('--limit', type=int, default=200)
    args = ap.parse_args()

    # ensure schema
    try:
        from action_log import ensure_db
        ensure_db(Path(args.db))
    except Exception:
        pass

    con = sqlite3.connect(args.db)
    rows = con.execute(
        "SELECT id, ts_start, ts_end, kind, status, seconds, message FROM events ORDER BY id DESC LIMIT ?",
        (args.limit,),
    ).fetchall()

    lines = [
        '# Actions report',
        '',
        f"DB: `{args.db}`",
        f"Count: {len(rows)}",
        '',
        '| id | ts_start | status | kind | seconds | message |',
        '|---:|---|---|---|---:|---|',
    ]

    for rid, ts_start, ts_end, kind, status, seconds, message in rows:
        msg = (message or '').replace('\n', ' ')[:120]
        lines.append(f"| {rid} | {ts_start} | {status} | {kind} | {seconds or 0:.2f} | {msg} |")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({'out': str(out), 'rows': len(rows)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
