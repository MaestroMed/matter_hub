"""Gmail connector (headers-first).

- OAuth Desktop flow (stores token.json locally)
- Fetches message metadata: From/To/Cc/Bcc/Date/Subject + snippet + labelIds
- Stores into SQLite with FTS5 for fast search

Prereqs:
- Place OAuth client secret at: connectors/google/client_secret.json

Run:
  python connectors/google/gmail_index_headers.py --max 500

Notes:
- First run opens browser for consent.
- Ledger logging will be added via hub/action_log.py (later).
"""

import argparse
import base64
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials

SCOPES = ['https://www.googleapis.com/auth/gmail.readonly']

ROOT = Path(__file__).resolve().parent
SECRET = ROOT / 'client_secret.json'
TOKEN = ROOT / 'token.json'
DB = ROOT / 'gmail.sqlite'


def ensure_db():
    con = sqlite3.connect(str(DB))
    con.execute('PRAGMA journal_mode=WAL;')
    con.execute('PRAGMA synchronous=NORMAL;')
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS emails(
          id TEXT PRIMARY KEY,
          thread_id TEXT,
          internal_date INTEGER,
          date TEXT,
          subject TEXT,
          from_addr TEXT,
          to_addr TEXT,
          cc TEXT,
          snippet TEXT,
          label_ids TEXT,
          raw_headers_json TEXT
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS emails_fts USING fts5(
          id,
          subject,
          from_addr,
          to_addr,
          snippet,
          tokenize='unicode61'
        );
        """
    )
    return con


def get_service():
    if not SECRET.exists():
        raise SystemExit(f"Missing OAuth secret: {SECRET}")

    creds = None
    if TOKEN.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN), SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(str(SECRET), SCOPES)
            creds = flow.run_local_server(port=0)
        TOKEN.write_text(creds.to_json(), encoding='utf-8')

    return build('gmail', 'v1', credentials=creds)


def header_map(headers):
    out = {}
    for h in headers or []:
        name = (h.get('name') or '').lower()
        if not name:
            continue
        out[name] = h.get('value')
    return out


def upsert_email(con, msg):
    mid = msg['id']
    thread_id = msg.get('threadId')
    internal_date = int(msg.get('internalDate') or 0)

    payload = msg.get('payload') or {}
    headers = payload.get('headers') or []
    hm = header_map(headers)

    date = hm.get('date')
    subject = hm.get('subject')
    from_addr = hm.get('from')
    to_addr = hm.get('to')
    cc = hm.get('cc')

    snippet = msg.get('snippet')
    label_ids = json.dumps(msg.get('labelIds') or [], ensure_ascii=False)
    raw_headers = json.dumps(hm, ensure_ascii=False)

    con.execute(
        """
        INSERT OR REPLACE INTO emails
        (id, thread_id, internal_date, date, subject, from_addr, to_addr, cc, snippet, label_ids, raw_headers_json)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
        """,
        (mid, thread_id, internal_date, date, subject, from_addr, to_addr, cc, snippet, label_ids, raw_headers),
    )

    con.execute(
        "INSERT OR REPLACE INTO emails_fts(id, subject, from_addr, to_addr, snippet) VALUES (?,?,?,?,?)",
        (mid, subject, from_addr, to_addr, snippet),
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--query', default='')
    ap.add_argument('--max', type=int, default=500)
    args = ap.parse_args()

    con = ensure_db()
    svc = get_service()

    n = 0
    page_token = None

    while True:
        resp = svc.users().messages().list(userId='me', q=args.query, maxResults=min(500, args.max - n), pageToken=page_token).execute()
        mids = resp.get('messages') or []
        if not mids:
            break

        for item in mids:
            mid = item['id']
            msg = svc.users().messages().get(userId='me', id=mid, format='metadata', metadataHeaders=['From','To','Cc','Date','Subject']).execute()
            upsert_email(con, msg)
            n += 1
            if n % 50 == 0:
                con.commit()
                print(f"... {n}")
            if n >= args.max:
                break

        con.commit()
        if n >= args.max:
            break

        page_token = resp.get('nextPageToken')
        if not page_token:
            break

    con.commit()
    print(json.dumps({'indexed': n, 'db': str(DB)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
