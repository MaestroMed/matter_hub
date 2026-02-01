"""Build a local semantic index using Ollama embeddings.

MVP design:
- Source: hub/chatgpt.sqlite (messages table)
- Target: hub/semantic.sqlite
  - docs(id TEXT PRIMARY KEY, source TEXT, text TEXT, meta_json TEXT)
  - vecs(id TEXT PRIMARY KEY, dim INT, v BLOB)

Vector format: float32 little-endian bytes.
Resume: skips ids already present.

Usage:
  python hub/semantic_index.py --limit 5000
  python hub/semantic_index.py --limit 5000 --where "author_role='user'"
"""

import argparse
import json
import sqlite3
import struct
import time
import urllib.request

BASE = 'http://127.0.0.1:11434'
EMBED_MODEL = 'nomic-embed-text:latest'


def ollama_embed(text: str, retries: int = 5):
    last_err = None
    for i in range(retries):
        try:
            payload = json.dumps({'model': EMBED_MODEL, 'prompt': text}).encode('utf-8')
            req = urllib.request.Request(BASE + '/api/embeddings', data=payload, headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=600) as r:
                out = json.loads(r.read().decode('utf-8'))
            v = out.get('embedding')
            if not v:
                raise RuntimeError('empty embedding')
            # small throttle helps stability
            time.sleep(0.05)
            return v
        except Exception as e:
            last_err = e
            time.sleep(min(2 ** i, 10))

    raise last_err


def pack_f32(vec):
    return struct.pack('<' + 'f' * len(vec), *map(float, vec))


def ensure_target(db_path: str):
    con = sqlite3.connect(db_path)
    con.execute('PRAGMA journal_mode=WAL;')
    con.execute('PRAGMA synchronous=NORMAL;')
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS docs(
          id TEXT PRIMARY KEY,
          source TEXT,
          text TEXT,
          meta_json TEXT
        );
        CREATE TABLE IF NOT EXISTS vecs(
          id TEXT PRIMARY KEY,
          dim INTEGER,
          v BLOB
        );
        CREATE INDEX IF NOT EXISTS idx_docs_source ON docs(source);
        """
    )
    return con


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=r'D:\\PROJECTS\\matter-hub\\hub\\chatgpt.sqlite')
    ap.add_argument('--dst', default=r'D:\\PROJECTS\\matter-hub\\hub\\semantic.sqlite')
    ap.add_argument('--limit', type=int, default=2000)
    ap.add_argument('--where', default="content_text IS NOT NULL AND length(content_text) > 0")
    args = ap.parse_args()

    src = sqlite3.connect(args.src)
    dst = ensure_target(args.dst)

    # attach dst to src so we can filter out already-embedded ids in one query
    src.execute("ATTACH DATABASE ? AS dst", (args.dst,))

    # choose candidates not yet embedded
    q = f"""
      SELECT m.id, m.conversation_id, m.author_role, m.created_at, m.content_text
      FROM messages m
      LEFT JOIN dst.vecs v ON v.id = m.id
      WHERE v.id IS NULL AND ({args.where})
      ORDER BY m.created_at
      LIMIT ?
    """

    rows = src.execute(q, (args.limit,)).fetchall()
    print(json.dumps({'candidates': len(rows)}, ensure_ascii=False))

    n = 0
    t0 = time.time()

    for mid, cid, role, created_at, text in rows:
        # keep text reasonably sized for embeddings
        snippet = (text or '').replace('\x00', ' ')
        # keep text reasonably sized for embeddings
        if len(snippet) > 2000:
            snippet = snippet[:2000]

        try:
            vec = ollama_embed(snippet)
        except Exception as e:
            # skip problematic docs but keep going
            print(f"WARN embedding failed id={mid}: {type(e).__name__}: {e}")
            continue
        blob = pack_f32(vec)

        meta = {'conversation_id': cid, 'author_role': role, 'created_at': created_at}
        dst.execute('INSERT OR REPLACE INTO docs(id, source, text, meta_json) VALUES (?,?,?,?)', (mid, 'chatgpt.messages', snippet, json.dumps(meta, ensure_ascii=False)))
        dst.execute('INSERT OR REPLACE INTO vecs(id, dim, v) VALUES (?,?,?)', (mid, len(vec), blob))

        n += 1
        if n % 100 == 0:
            dst.commit()
            dt_s = time.time() - t0
            print(f"... embedded {n}/{len(rows)} in {dt_s:.1f}s ({n/dt_s:.2f} docs/s)")

    dst.commit()
    dt_s = time.time() - t0
    print(json.dumps({'embedded': n, 'seconds': round(dt_s, 2), 'docs_per_s': round(n/dt_s, 3) if dt_s else None, 'dst': args.dst}, ensure_ascii=False))


if __name__ == '__main__':
    main()
