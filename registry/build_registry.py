import json
import re
from pathlib import Path

RAW = Path(__file__).resolve().parent / 'projects-scan.raw.json'
OUT = Path(__file__).resolve().parent / 'projects.json'

BAD_PATTERNS = [
    r"\\AppData\\",
    r"\\Program Files",
    r"\\ProgramData\\",
    r"\\Windows\\",
    r"\\npm-cache\\",
    r"\\Temp\\",
    r"\\games\\UE_",
]
rx = re.compile("|".join(BAD_PATTERNS), re.I)


def keep(path: str) -> bool:
    return rx.search(path) is None


def main():
    data = json.loads(RAW.read_text(encoding='utf-8'))
    projects = [p for p in data['projects'] if keep(p['path'])]

    # score & basic normalization
    for p in projects:
        p['score'] = (10 if 'git' in p['kinds'] else 0) + len(p['kinds'])
        p['name'] = Path(p['path']).name
        p['priority'] = 'normal'

    # sort
    projects.sort(key=lambda x: (-x['score'], x['path'].lower()))

    out = {
        'generatedAt': __import__('datetime').datetime.utcnow().replace(microsecond=0).isoformat() + 'Z',
        'source': str(RAW),
        'count': len(projects),
        'projects': projects,
    }

    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'count': len(projects), 'out': str(OUT)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
