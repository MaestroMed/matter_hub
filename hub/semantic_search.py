"""Semantic search over local Ollama embeddings stored in semantic.sqlite.

Usage:
  python hub/semantic_search.py "ton texte" --top 8

Notes:
- Brute-force cosine over N vectors. OK for ~5k-50k; later we'll add ANN.
"""

import argparse
import json
import math
import sqlite3
import struct
import urllib.request

BASE = 'http://127.0.0.1:11434'
EMBED_MODEL = 'nomic-embed-text:latest'


def ollama_embed(text: str):
    payload = json.dumps({'model': EMBED_MODEL, 'prompt': text}).encode('utf-8')
    req = urllib.request.Request(BASE + '/api/embeddings', data=payload, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=600) as r:
        out = json.loads(r.read().decode('utf-8'))
    v = out.get('embedding')
    if not v:
        raise RuntimeError('empty embedding')
    return [float(x) for x in v]


def unpack_f32(blob: bytes):
    n = len(blob) // 4
    return list(struct.unpack('<' + 'f' * n, blob))


def cosine(a, b):
    dot = 0.0
    na = 0.0
    nb = 0.0
    for x, y in zip(a, b):
        dot += x * y
        na += x * x
        nb += y * y
    if na == 0.0 or nb == 0.0:
        return 0.0
    return dot / (math.sqrt(na) * math.sqrt(nb))


def main():
    from action_log import log_event

    ap = argparse.ArgumentParser()
    ap.add_argument('query')
    ap.add_argument('--db', default=r'D:\\PROJECTS\\matter-hub\\hub\\semantic.sqlite')
    ap.add_argument('--top', type=int, default=8)
    args = ap.parse_args()

    with log_event('semantic_search', params={'query': args.query, 'top': args.top, 'db': args.db}, message='Semantic search', tags=['search']) as ev:
        qv = ollama_embed(args.query)

        con = sqlite3.connect(args.db)
    rows = con.execute('SELECT v.id, v.dim, v.v, d.meta_json, d.text FROM vecs v JOIN docs d ON d.id=v.id').fetchall()

    scored = []
    for mid, dim, blob, meta_json, text in rows:
        v = unpack_f32(blob)
        s = cosine(qv, v)
        scored.append((s, mid, meta_json, text))

    scored.sort(key=lambda x: x[0], reverse=True)

    out = []
    for s, mid, meta_json, text in scored[: args.top]:
        meta = json.loads(meta_json) if meta_json else {}
        out.append({
            'score': round(float(s), 4),
            'id': mid,
            'meta': meta,
            'text': (text[:400] + '…') if text and len(text) > 400 else text,
        })

        ev.ok(extra={'results': len(out)})
        print(json.dumps({'query': args.query, 'top': out}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
