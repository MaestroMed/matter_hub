"""Unified search over ChatGPT archive.

Combines:
- FTS (chatgpt.sqlite / messages_fts)
- Semantic (semantic.sqlite vectors via Ollama embeddings)

Usage examples:
  python hub/search.py "Primerium Aristote" --top 8
  python hub/search.py "monologue abbaye" --role user --top 8

Returns JSON.
"""

import argparse
import json
import math
import sqlite3
import struct
import time
import urllib.request

from pathlib import Path

BASE = 'http://127.0.0.1:11434'
EMBED_MODEL = 'nomic-embed-text:latest'

CHAT_DB = Path(__file__).resolve().parent / 'chatgpt.sqlite'
SEM_DB = Path(__file__).resolve().parent / 'semantic.sqlite'


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


def fts_search(con, query: str, role: str | None, limit: int):
    # messages_fts: message_id, conversation_id, author_role, created_at, content_text
    base = (
        "SELECT message_id, conversation_id, author_role, created_at, snippet(messages_fts, 4, '[', ']', '…', 18) "
        "FROM messages_fts WHERE messages_fts MATCH ?"
    )
    params = []
    # quote if query has spaces
    match = '"%s"' % query.replace('"', '') if ' ' in query else query
    params.append(match)

    if role:
        base += " AND author_role=?"
        params.append(role)

    base += " ORDER BY created_at DESC LIMIT ?"
    params.append(limit)

    return con.execute(base, params).fetchall()


def semantic_search(query: str, role: str | None, top: int, min_len: int = 120):
    qv = ollama_embed(query)
    con = sqlite3.connect(str(SEM_DB))
    rows = con.execute(
        "SELECT v.id, v.v, d.meta_json, d.text FROM vecs v JOIN docs d ON d.id=v.id"
    ).fetchall()

    scored = []
    for mid, blob, meta_json, text in rows:
        if not text or len(text) < min_len:
            continue
        meta = json.loads(meta_json) if meta_json else {}
        if role and meta.get('author_role') != role:
            continue
        v = unpack_f32(blob)
        s = cosine(qv, v)
        scored.append((s, mid, meta, text))

    scored.sort(key=lambda x: x[0], reverse=True)
    out = []
    for s, mid, meta, text in scored[:top]:
        out.append({
            'score': round(float(s), 4),
            'id': mid,
            'conversation_id': meta.get('conversation_id'),
            'author_role': meta.get('author_role'),
            'created_at': meta.get('created_at'),
            'text': (text[:500] + '…') if len(text) > 500 else text,
        })
    return out


def main():
    from action_log import log_event

    ap = argparse.ArgumentParser()
    ap.add_argument('query')
    ap.add_argument('--role', default=None, help="user|assistant|tool|system")
    ap.add_argument('--fts', type=int, default=12)
    ap.add_argument('--sem', type=int, default=12)
    ap.add_argument('--top', type=int, default=10)
    args = ap.parse_args()

    with log_event('search', params={'query': args.query, 'role': args.role, 'fts': args.fts, 'sem': args.sem, 'top': args.top}) as ev:
        t0 = time.time()
        chat = sqlite3.connect(str(CHAT_DB))
        fts = fts_search(chat, args.query, args.role, args.fts)
        sem = semantic_search(args.query, args.role, args.sem)

        out = {
            'query': args.query,
            'role': args.role,
            'fts': [
                {
                    'message_id': mid,
                    'conversation_id': cid,
                    'author_role': role,
                    'created_at': created_at,
                    'snippet': snip,
                }
                for (mid, cid, role, created_at, snip) in fts
            ],
            'semantic': sem,
            'seconds': round(time.time() - t0, 3),
        }
        ev.ok(extra={'fts': len(fts), 'semantic': len(sem), 'seconds': out['seconds']})
        print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
