"""Run a command, capture stdout/stderr to a log file, and record to ledger.

Usage:
  python hub/run_logged.py --kind semantic_index -- message "Index" -- python hub/semantic_index.py --limit 5000

Example:
  python hub/run_logged.py --kind universe_extract --tag canon --tag Universe-01 -- \
    python hub/extract_universe.py --slug universe-01 --terms Aristote Nyx

Notes:
- Creates logs under hub/_logs/YYYY-MM-DD/...
- Stores log_path in actions.sqlite
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from action_log import log_event


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--kind', required=True)
    ap.add_argument('--message', default=None)
    ap.add_argument('--tag', action='append', default=[])
    ap.add_argument('--cwd', default=None)
    ap.add_argument('--env', action='append', default=[])
    ap.add_argument('cmd', nargs=argparse.REMAINDER)
    args = ap.parse_args()

    if not args.cmd or args.cmd[0] != '--':
        raise SystemExit('Usage: run_logged.py --kind X -- <command...>')
    cmd = args.cmd[1:]

    day = datetime.utcnow().strftime('%Y-%m-%d')
    ts = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
    logs_dir = Path(__file__).resolve().parent / '_logs' / day
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_path = logs_dir / f"{ts}-{args.kind}.log"

    env = os.environ.copy()
    for kv in args.env:
        if '=' in kv:
            k, v = kv.split('=', 1)
            env[k] = v

    with log_event(args.kind, params={'cmd': cmd, 'cwd': args.cwd}, message=args.message, tags=args.tag, log_path=str(log_path)) as ev:
        with open(log_path, 'w', encoding='utf-8', errors='replace') as f:
            f.write(f"$ {' '.join(cmd)}\n")
            f.flush()
            p = subprocess.Popen(cmd, cwd=args.cwd, env=env, stdout=f, stderr=subprocess.STDOUT, text=True)
            rc = p.wait()
            if rc == 0:
                ev.ok(extra={'returncode': rc})
            else:
                ev.fail(error=f"returncode={rc}")
                raise SystemExit(rc)


if __name__ == '__main__':
    main()
