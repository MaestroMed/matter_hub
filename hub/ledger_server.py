"""Ledger v2: local web UI + API for actions.sqlite.

Run:
  python hub/ledger_server.py
Then open:
  http://127.0.0.1:8899/

API:
  GET /api/events?limit=100&kind=...&status=...&q=...&since=...&until=...
  GET /api/events/{id}

Notes:
- Local-only by default.
- Designed to be simple and robust (no auth on localhost).
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Optional

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse

from action_log import ensure_db

DB = Path(__file__).resolve().parent / 'actions.sqlite'

app = FastAPI(title='matter-hub ledger')


def _connect():
    ensure_db(DB)
    con = sqlite3.connect(str(DB))
    con.row_factory = sqlite3.Row
    return con


@app.get('/', response_class=HTMLResponse)
def index():
    return HTMLResponse(
        """<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>matter-hub — Ledger</title>
  <style>
    body { font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif; margin: 20px; }
    .row { display:flex; gap:12px; flex-wrap:wrap; align-items:center; }
    input, select { padding: 6px 8px; }
    table { border-collapse: collapse; width: 100%; margin-top: 16px; }
    th, td { border: 1px solid #ddd; padding: 8px; font-size: 13px; }
    th { background: #f6f6f6; text-align: left; }
    tr:hover { background:#fafafa; }
    .pill { display:inline-block; padding:2px 8px; border-radius: 999px; font-size: 12px; }
    .ok { background:#e7f7ee; color:#0b6b2f; }
    .warn { background:#fff6e6; color:#8a5a00; }
    .error { background:#fdeaea; color:#9a1b1b; }
    pre { white-space: pre-wrap; }
    .muted { color:#666; }
  </style>
</head>
<body>
  <h1>Ledger</h1>
  <div class="row">
    <label>kind <input id="kind" placeholder="semantic_index"/></label>
    <label>status
      <select id="status">
        <option value="">(any)</option>
        <option value="ok">ok</option>
        <option value="warn">warn</option>
        <option value="error">error</option>
        <option value="running">running</option>
      </select>
    </label>
    <label>q <input id="q" placeholder="Universe-01"/></label>
    <label>since <input id="since" placeholder="2026-02-01T00:00:00+00:00" size="26"/></label>
    <label>until <input id="until" placeholder="" size="26"/></label>
    <label>limit <input id="limit" type="number" value="100" min="1" max="2000"/></label>
    <button onclick="loadEvents()">Refresh</button>
    <span class="muted" id="meta"></span>
  </div>

  <table>
    <thead>
      <tr>
        <th>id</th><th>ts_start</th><th>status</th><th>kind</th><th>seconds</th><th>message</th>
      </tr>
    </thead>
    <tbody id="tbody"></tbody>
  </table>

  <h2>Details</h2>
  <div id="details" class="muted">Click an event row.</div>

<script>
async function api(url){
  const r = await fetch(url);
  if(!r.ok) throw new Error(await r.text());
  return await r.json();
}

function pill(status){
  const cls = status || '';
  return `<span class="pill ${cls}">${status}</span>`;
}

async function loadEvents(){
  const kind = document.getElementById('kind').value;
  const status = document.getElementById('status').value;
  const q = document.getElementById('q').value;
  const since = document.getElementById('since').value;
  const until = document.getElementById('until').value;
  const limit = document.getElementById('limit').value;

  const params = new URLSearchParams();
  if(kind) params.set('kind', kind);
  if(status) params.set('status', status);
  if(q) params.set('q', q);
  if(since) params.set('since', since);
  if(until) params.set('until', until);
  params.set('limit', limit || '100');

  const t0 = performance.now();
  const rows = await api('/api/events?' + params.toString());
  const t1 = performance.now();

  document.getElementById('meta').textContent = `${rows.length} events • ${(t1-t0).toFixed(0)}ms`;

  const tbody = document.getElementById('tbody');
  tbody.innerHTML = '';
  for(const e of rows){
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${e.id}</td>
      <td>${e.ts_start}</td>
      <td>${pill(e.status)}</td>
      <td>${e.kind}</td>
      <td>${(e.seconds ?? 0).toFixed(2)}</td>
      <td>${e.message ?? ''}</td>
    `;
    tr.style.cursor = 'pointer';
    tr.onclick = async () => {
      const full = await api('/api/events/' + e.id);
      document.getElementById('details').innerHTML = `
        <div><b>#${full.id}</b> ${full.ts_start} → ${full.ts_end ?? ''}</div>
        <div><b>kind</b>: ${full.kind} • <b>status</b>: ${full.status} • <b>seconds</b>: ${(full.seconds ?? 0).toFixed(2)}</div>
        <div><b>tags</b>: ${(full.tags||[]).join(', ')}</div>
        <div><b>message</b>: ${full.message ?? ''}</div>
        <h3>params</h3><pre>${JSON.stringify(full.params||{}, null, 2)}</pre>
        <h3>extra</h3><pre>${JSON.stringify(full.extra||{}, null, 2)}</pre>
        <h3>error</h3><pre>${full.error ?? ''}</pre>
      `;
    };
    tbody.appendChild(tr);
  }
}

loadEvents();
setInterval(loadEvents, 5000);
</script>
</body>
</html>"""
    )


@app.get('/api/events')
def api_events(
    limit: int = 100,
    kind: Optional[str] = None,
    status: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    q: Optional[str] = None,
):
    limit = max(1, min(int(limit), 2000))
    con = _connect()

    sql = "SELECT id, ts_start, ts_end, kind, status, seconds, message, tags, params_json, extra_json, error FROM events"
    where = []
    params = []

    if kind:
        where.append('kind=?')
        params.append(kind)
    if status:
        where.append('status=?')
        params.append(status)
    if since:
        where.append('ts_start>=?')
        params.append(since)
    if until:
        where.append('ts_start<=?')
        params.append(until)
    if q:
        where.append('(kind LIKE ? OR message LIKE ? OR params_json LIKE ? OR extra_json LIKE ? OR error LIKE ?)')
        like = f"%{q}%"
        params.extend([like, like, like, like, like])

    if where:
        sql += ' WHERE ' + ' AND '.join(where)

    sql += ' ORDER BY id DESC LIMIT ?'
    params.append(limit)

    rows = con.execute(sql, params).fetchall()

    out = []
    for r in rows:
        out.append({
            'id': r['id'],
            'ts_start': r['ts_start'],
            'ts_end': r['ts_end'],
            'kind': r['kind'],
            'status': r['status'],
            'seconds': r['seconds'],
            'message': r['message'],
            'tags': json.loads(r['tags'] or '[]'),
        })

    return JSONResponse(out)


@app.get('/api/events/{event_id}')
def api_event(event_id: int):
    con = _connect()
    r = con.execute(
        'SELECT id, ts_start, ts_end, kind, status, seconds, message, tags, params_json, extra_json, error FROM events WHERE id=?',
        (event_id,),
    ).fetchone()
    if not r:
        return JSONResponse({'error': 'not_found'}, status_code=404)
    return JSONResponse({
        'id': r['id'],
        'ts_start': r['ts_start'],
        'ts_end': r['ts_end'],
        'kind': r['kind'],
        'status': r['status'],
        'seconds': r['seconds'],
        'message': r['message'],
        'tags': json.loads(r['tags'] or '[]'),
        'params': json.loads(r['params_json'] or '{}'),
        'extra': json.loads(r['extra_json'] or '{}'),
        'error': r['error'],
    })


def main():
    import uvicorn

    uvicorn.run(app, host='127.0.0.1', port=8899, log_level='warning')


if __name__ == '__main__':
    main()
