import argparse
import json
import sqlite3
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', default=str(Path(__file__).resolve().parent / 'actions.sqlite'))
    ap.add_argument('--kind', default=None)
    ap.add_argument('--status', default=None)
    ap.add_argument('--limit', type=int, default=50)
    args = ap.parse_args()

    con = sqlite3.connect(args.db)
    q = "SELECT id, ts_start, ts_end, kind, status, seconds, params_json, extra_json, error FROM events"
    where = []
    params = []
    if args.kind:
        where.append('kind=?')
        params.append(args.kind)
    if args.status:
        where.append('status=?')
        params.append(args.status)
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
            'params': json.loads(r[6] or '{}'),
            'extra': json.loads(r[7] or '{}'),
            'error': r[8],
        })

    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
