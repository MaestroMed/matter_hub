"""Extract universe fragments from ChatGPT archive.

- Uses FTS (chatgpt.sqlite / messages_fts) for keyword hits
- Uses semantic search (semantic.sqlite) for broader recall

Outputs markdown bundles under hub/_canon/<slug>/

Usage:
  python hub/extract_universe.py --slug universe-draft --terms Aristote Nyx Kami
"""

import argparse
import json
import os
import re
import sqlite3
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import urllib.request
import math
import struct

# Ollama embeddings
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


def sanitize_slug(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"[^a-z0-9\-]+", "-", s)
    s = re.sub(r"-+", "-", s).strip('-')
    return s or 'canon'


def fts_query(chat_db: Path, term: str, limit: int):
    con = sqlite3.connect(str(chat_db))
    # messages_fts columns: message_id, conversation_id, author_role, created_at, content_text
    q = """
      SELECT message_id, conversation_id, author_role, created_at, snippet(messages_fts, 4, '[', ']', '…', 18) as snip
      FROM messages_fts
      WHERE messages_fts MATCH ?
      ORDER BY created_at DESC
      LIMIT ?
    """
    # quote term for FTS when it has spaces
    match = '"%s"' % term.replace('"','') if ' ' in term else term
    return con.execute(q, (match, limit)).fetchall()


def semantic_query(sem_db: Path, query: str, limit: int):
    con = sqlite3.connect(str(sem_db))
    qv = ollama_embed(query)
    rows = con.execute('SELECT v.id, v.v, d.meta_json, d.text FROM vecs v JOIN docs d ON d.id=v.id').fetchall()
    scored = []
    for mid, blob, meta_json, text in rows:
        v = unpack_f32(blob)
        s = cosine(qv, v)
        scored.append((s, mid, meta_json, text))
    scored.sort(key=lambda x: x[0], reverse=True)
    out = []
    for s, mid, meta_json, text in scored[:limit]:
        meta = json.loads(meta_json) if meta_json else {}
        out.append((float(s), mid, meta, text))
    return out


def main():
    from action_log import log_event

    ap = argparse.ArgumentParser()
    ap.add_argument('--slug', required=True)
    ap.add_argument('--terms', nargs='+', required=True)
    ap.add_argument('--chat-db', default=r'D:\\PROJECTS\\matter-hub\\hub\\chatgpt.sqlite')
    ap.add_argument('--sem-db', default=r'D:\\PROJECTS\\matter-hub\\hub\\semantic.sqlite')
    ap.add_argument('--fts-limit', type=int, default=40)
    ap.add_argument('--sem-limit', type=int, default=12)
    args = ap.parse_args()

    slug = sanitize_slug(args.slug)
    outdir = Path(r'D:\\PROJECTS\\matter-hub\\hub\\_canon') / slug
    outdir.mkdir(parents=True, exist_ok=True)

    chat_db = Path(args.chat_db)
    sem_db = Path(args.sem_db)

    generated = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    # 1) FTS results per term
    fts_md = [f"# FTS hits — {slug}", f"Generated: {generated}", ""]
    for term in args.terms:
        fts_md.append(f"## {term}")
        try:
            rows = fts_query(chat_db, term, args.fts_limit)
        except Exception as e:
            fts_md.append(f"(error: {e})\n")
            continue
        if not rows:
            fts_md.append("(no hits)\n")
            continue
        for mid, cid, role, created_at, snip in rows:
            fts_md.append(f"- [{role}] {created_at} convo={cid} id={mid}\n  - {snip}")
        fts_md.append("")

    (outdir / 'fts_hits.md').write_text("\n".join(fts_md), encoding='utf-8')

    # 2) Semantic results per query
    sem_md = [f"# Semantic recall — {slug}", f"Generated: {generated}", ""]
    for term in args.terms:
        sem_md.append(f"## {term}")
        try:
            hits = semantic_query(sem_db, term, args.sem_limit)
        except Exception as e:
            sem_md.append(f"(error: {e})\n")
            continue
        for score, mid, meta, text in hits:
            cid = meta.get('conversation_id')
            role = meta.get('author_role')
            created_at = meta.get('created_at')
            preview = (text or '').replace('\n',' ')[:300]
            sem_md.append(f"- score={score:.4f} [{role}] {created_at} convo={cid} id={mid}\n  - {preview}…")
        sem_md.append("")

    (outdir / 'semantic_hits.md').write_text("\n".join(sem_md), encoding='utf-8')

    # 3) Seed canon draft (empty placeholders)
    canon = [
        f"# Canon draft — {slug}",
        f"Generated: {generated}",
        "",
        "## Anchors fournis",
    ]
    for t in args.terms:
        canon.append(f"- {t}")
    canon += [
        "",
        "## Hypothèses initiales (à valider)",
        "- (à remplir)",
        "",
        "## Personnages", "- (à remplir)",
        "", "## Lieux", "- (à remplir)",
        "", "## Factions / groupes", "- (à remplir)",
        "", "## Objets / artefacts (cristaux, etc.)", "- (à remplir)",
        "", "## Timeline", "- (à remplir)",
        "", "## Style / tonalité", "- (à remplir)",
    ]
    (outdir / 'canon_draft.md').write_text("\n".join(canon), encoding='utf-8')

    print(json.dumps({'outdir': str(outdir)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
