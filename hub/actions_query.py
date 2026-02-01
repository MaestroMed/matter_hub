import argparse
import json
import sqlite3
from datetime import datetime
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', default=str(Path(__file__).resolve().parent / 'actions.sqlite'))
    ap.add_argument('--kind', default=None)
    ap.add_argument('--status', default=None)
    ap.add_argument('--since', default=None, help='ISO datetime (UTC recommended)')
    ap.add_argument('--until', default=None, help='ISO datetime (UTC recommended)')
    ap.add_argument('--q', default=None, help='substring search over kind/message/params/extra/error')
    ap.add_argument('--limit', type=int, default=50)
    ap.add_argument('--format', default='json', choices=['json', 'compact'])
    args = ap.parse_args()

    # ensure schema exists
    try:
        from action_log import ensure_db
        ensure_db(Path(args.db))
    except Exception:
        pass

    con = sqlite3.connect(args.db)

    q = "SELECT id, ts_start, ts_end, kind, status, seconds, message, tags, params_json, extra_json, error FROM events"
    where = []
    params = []

    if args.kind:
        where.append('kind=?')
        params.append(args.kind)
    if args.status:
        where.append('status=?')
        params.append(args.status)
    if args.since:
        where.append('ts_start>=?')
        params.append(args.since)
    if args.until:
        where.append('ts_start<=?')
        params.append(args.until)
    if args.q:
        where.append('(kind LIKE ? OR message LIKE ? OR params_json LIKE ? OR extra_json LIKE ? OR error LIKE ?)')
        like = f"%{args.q}%"
        params.extend([like, like, like, like, like])

    if where:
        q += ' WHERE ' + ' AND '.join(where)

    q += ' ORDER BY id DESC LIMIT ?'
    params.append(args.limit)

    rows = con.execute(q, params).fetchall()

    out = []
    for r in rows:
        out.append({
            'id': r[0],
            'ts_start': r[1],
            'ts_end': r[2],
            'kind': r[3],
            'status': r[4],
            'seconds': r[5],
            'message': r[6],
            'tags': json.loads(r[7] or '[]'),
            'params': json.loads(r[8] or '{}'),
            'extra': json.loads(r[9] or '{}'),
            'error': r[10],
        })

    if args.format == 'json':
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return

    # compact (human)
    for e in out:
        msg = (e['message'] or '').strip()
        if msg:
            msg = ' — ' + msg
        print(f"#{e['id']} {e['ts_start']} [{e['status']}] {e['kind']} {e['seconds']:.2f}s{msg}")


if __name__ == '__main__':
    main()
