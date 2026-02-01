"""Search v2 — unified recall over ChatGPT archive.

Goals:
- One command to retrieve the past.
- FTS (exact keyword) + semantic (conceptual)
- Filters: role, time range, project tags
- Better ranking + optional grouping by conversation

Usage:
  python hub/search.py "Primerium Aristote cristaux" --project Universe-01 --top 10
  python hub/search.py "monologue abbaye" --role user --since 2024-01-01 --top 10
  python hub/search.py "colonies rouges" --group --convos 8

Time args accept:
- unix seconds (e.g. 1769959655.922)
- ISO (e.g. 2026-02-01T00:00:00+00:00)
- YYYY-MM-DD (treated as UTC midnight)

Returns JSON.
"""

from __future__ import annotations

import argparse
import json
import math
import sqlite3
import struct
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from action_log import log_event

BASE = 'http://127.0.0.1:11434'
EMBED_MODEL = 'nomic-embed-text:latest'

CHAT_DB = Path(__file__).resolve().parent / 'chatgpt.sqlite'
SEM_DB = Path(__file__).resolve().parent / 'semantic.sqlite'
TAGS_RULES = Path(__file__).resolve().parent / 'project_tags.json'


def _parse_time(s: str | None) -> float | None:
    if not s:
        return None
    s = s.strip()
    # unix seconds
    try:
        return float(s)
    except Exception:
        pass

    # YYYY-MM-DD
    try:
        if len(s) == 10 and s[4] == '-' and s[7] == '-':
            dt = datetime.fromisoformat(s).replace(tzinfo=timezone.utc)
            return dt.timestamp()
    except Exception:
        pass

    # ISO
    try:
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    except Exception:
        return None


def _load_project_rules():
    if not TAGS_RULES.exists():
        return []
    try:
        data = json.loads(TAGS_RULES.read_text(encoding='utf-8'))
        return data.get('projects', [])
    except Exception:
        return []


def _detect_projects(text: str) -> list[str]:
    low = (text or '').lower()
    tags: list[str] = []
    for proj in _load_project_rules():
        tag = proj.get('tag')
        for pat in proj.get('patterns', []):
            if pat and pat.lower() in low:
                if tag and tag not in tags:
                    tags.append(tag)
                break
    return tags


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


def fts_search(con, query: str, role: str | None, since: float | None, until: float | None, limit: int):
    # messages_fts: message_id, conversation_id, author_role, created_at, content_text
    sql = (
        "SELECT message_id, conversation_id, author_role, created_at, "
        "snippet(messages_fts, 4, '[', ']', '…', 18) AS snip, bm25(messages_fts) AS bm25 "
        "FROM messages_fts WHERE messages_fts MATCH ?"
    )
    params: list[object] = []

    # quote if query has spaces
    match = '"%s"' % query.replace('"', '') if ' ' in query else query
    params.append(match)

    if role:
        sql += " AND author_role=?"
        params.append(role)

    if since is not None:
        sql += " AND CAST(created_at AS REAL) >= ?"
        params.append(float(since))

    if until is not None:
        sql += " AND CAST(created_at AS REAL) <= ?"
        params.append(float(until))

    # better ranking: bm25 first, then recency
    sql += " ORDER BY bm25 ASC, CAST(created_at AS REAL) DESC LIMIT ?"
    params.append(int(limit))

    return con.execute(sql, params).fetchall()


def semantic_search(query: str, role: str | None, since: float | None, until: float | None, top: int, min_len: int = 120):
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
        rrole = meta.get('author_role')
        created_at = meta.get('created_at')

        if role and rrole != role:
            continue

        try:
            ts = float(created_at) if created_at is not None else None
        except Exception:
            ts = None

        if since is not None and ts is not None and ts < since:
            continue
        if until is not None and ts is not None and ts > until:
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
            'text': (text[:700] + '…') if len(text) > 700 else text,
        })
    return out


def _normalize_bm25(bm25: float) -> float:
    # bm25: lower is better; turn into (0..1] score
    bm25 = max(0.0, float(bm25))
    return 1.0 / (1.0 + bm25)


def _merge_results(fts_rows, sem_rows, project: str | None):
    merged: dict[str, dict] = {}

    for mid, cid, role, created_at, snip, bm25 in fts_rows:
        score = _normalize_bm25(bm25)
        text = str(snip)
        tags = _detect_projects(text)
        if project and project not in tags:
            continue
        merged[mid] = {
            'id': mid,
            'conversation_id': cid,
            'author_role': role,
            'created_at': created_at,
            'score': round(float(score), 4),
            'source': ['fts'],
            'preview': text,
            'tags': tags,
        }

    for item in sem_rows:
        mid = item['id']
        text = item.get('text') or ''
        tags = _detect_projects(text)
        if project and project not in tags:
            continue
        if mid in merged:
            merged[mid]['source'].append('semantic')
            # combine scores: keep best
            merged[mid]['score'] = round(max(float(merged[mid]['score']), float(item['score'])), 4)
            # prefer semantic text as preview if longer
            if len(text) > len(merged[mid].get('preview') or ''):
                merged[mid]['preview'] = text
            # merge tags
            for t in tags:
                if t not in merged[mid]['tags']:
                    merged[mid]['tags'].append(t)
        else:
            merged[mid] = {
                'id': mid,
                'conversation_id': item.get('conversation_id'),
                'author_role': item.get('author_role'),
                'created_at': item.get('created_at'),
                'score': item['score'],
                'source': ['semantic'],
                'preview': text,
                'tags': tags,
            }

    # sort by score desc, then recency desc if numeric
    def key(x):
        ca = x.get('created_at')
        try:
            ts = float(ca)
        except Exception:
            ts = -1.0
        return (-float(x.get('score') or 0.0), -ts)

    items = list(merged.values())
    items.sort(key=key)
    return items


def _group_by_conversation(items: list[dict], convos: int, per_convo: int):
    by: dict[str, list[dict]] = {}
    for it in items:
        cid = it.get('conversation_id') or 'unknown'
        by.setdefault(cid, []).append(it)

    # rank convos by best score
    ranked = sorted(by.items(), key=lambda kv: max((x.get('score') or 0.0) for x in kv[1]), reverse=True)
    out = []
    for cid, msgs in ranked[:convos]:
        msgs_sorted = sorted(msgs, key=lambda x: -(x.get('score') or 0.0))[:per_convo]
        out.append({'conversation_id': cid, 'hits': msgs_sorted})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('query')
    ap.add_argument('--role', default=None, help='user|assistant|tool|system')
    ap.add_argument('--since', default=None)
    ap.add_argument('--until', default=None)
    ap.add_argument('--project', default=None, help='Universe-01|Iris|Dolores')
    ap.add_argument('--fts', type=int, default=25)
    ap.add_argument('--sem', type=int, default=25)
    ap.add_argument('--top', type=int, default=15)
    ap.add_argument('--group', action='store_true', help='group results by conversation_id')
    ap.add_argument('--convos', type=int, default=10)
    ap.add_argument('--per-convo', type=int, default=5)
    args = ap.parse_args()

    since = _parse_time(args.since)
    until = _parse_time(args.until)

    with log_event(
        'search',
        params={
            'query': args.query,
            'role': args.role,
            'since': args.since,
            'until': args.until,
            'project': args.project,
            'fts': args.fts,
            'sem': args.sem,
            'top': args.top,
            'group': args.group,
        },
        message=f"Search v2: {args.query}",
        tags=['search'] + ([args.project] if args.project else []),
    ) as ev:
        t0 = time.time()
        chat = sqlite3.connect(str(CHAT_DB))
        fts = fts_search(chat, args.query, args.role, since, until, args.fts)
        sem = semantic_search(args.query, args.role, since, until, args.sem)
        merged = _merge_results(fts, sem, args.project)

        out = {
            'query': args.query,
            'role': args.role,
            'since': args.since,
            'until': args.until,
            'project': args.project,
            'counts': {'fts': len(fts), 'semantic': len(sem), 'merged': len(merged)},
            'seconds': round(time.time() - t0, 3),
        }

        if args.group:
            out['grouped'] = _group_by_conversation(merged[: max(args.top, args.convos * args.per_convo)], args.convos, args.per_convo)
        else:
            out['hits'] = merged[: args.top]

        ev.ok(extra={'seconds': out['seconds'], **out['counts']})
        print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
