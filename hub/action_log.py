"""Local action ledger (SQLite) for monitoring Greydawn/matter-hub actions.

Goal: one place to record what ran, when, with status, params, durations, and errors.

Usage:
  from action_log import log_event
  with log_event('semantic_index', params={'limit': 5000}) as ev:
      ...
      ev.ok(extra={'embedded': 123})

DB location default: hub/actions.sqlite
"""

from __future__ import annotations

import json
import os
import sqlite3
import time
import traceback
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_DB = Path(__file__).resolve().parent / 'actions.sqlite'


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def ensure_db(db_path: Path = DEFAULT_DB) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(db_path))
    con.execute('PRAGMA journal_mode=WAL;')
    con.execute('PRAGMA synchronous=NORMAL;')
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS events(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts_start TEXT,
          ts_end TEXT,
          kind TEXT,
          status TEXT,
          seconds REAL,
          params_json TEXT,
          extra_json TEXT,
          error TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind);
        CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
        CREATE INDEX IF NOT EXISTS idx_events_ts_start ON events(ts_start);
        """
    )
    return con


@dataclass
class _EventHandle:
    con: sqlite3.Connection
    row_id: int
    kind: str
    t0: float

    def ok(self, extra: dict | None = None):
        self._finish('ok', extra=extra)

    def warn(self, extra: dict | None = None, error: str | None = None):
        self._finish('warn', extra=extra, error=error)

    def fail(self, error: str, extra: dict | None = None):
        self._finish('error', extra=extra, error=error)

    def _finish(self, status: str, extra: dict | None = None, error: str | None = None):
        t1 = time.time()
        ts_end = _utcnow_iso()
        seconds = t1 - self.t0
        self.con.execute(
            "UPDATE events SET ts_end=?, status=?, seconds=?, extra_json=?, error=? WHERE id=?",
            (
                ts_end,
                status,
                float(seconds),
                json.dumps(extra or {}, ensure_ascii=False),
                error,
                self.row_id,
            ),
        )
        self.con.commit()


@contextmanager
def log_event(kind: str, params: dict | None = None, db_path: Path = DEFAULT_DB):
    con = ensure_db(db_path)
    ts_start = _utcnow_iso()
    t0 = time.time()
    cur = con.execute(
        "INSERT INTO events(ts_start, kind, status, params_json, extra_json) VALUES (?,?,?,?,?)",
        (ts_start, kind, 'running', json.dumps(params or {}, ensure_ascii=False), json.dumps({}, ensure_ascii=False)),
    )
    con.commit()
    ev = _EventHandle(con=con, row_id=int(cur.lastrowid), kind=kind, t0=t0)

    try:
        yield ev
    except Exception as e:
        ev.fail(error=str(e) + "\n" + traceback.format_exc())
        raise
