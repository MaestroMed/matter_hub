import json
import time
import urllib.request

BASE = 'http://127.0.0.1:11434'

def post(path, payload):
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(BASE + path, data=data, headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.loads(r.read().decode('utf-8'))


def main():
    t0 = time.time()
    emb = post('/api/embeddings', {
        'model': 'nomic-embed-text:latest',
        'prompt': 'Bonjour Monsieur. Ceci est un test embeddings.'
    })
    v = emb.get('embedding') or []
    print('embeddings_dim', len(v))

    gen = post('/api/generate', {
        'model': 'llama3.1:8b',
        'prompt': 'Réponds en une phrase en français: qui es-tu ?',
        'stream': False
    })
    print('generate_response', (gen.get('response') or '').strip())
    print('seconds', round(time.time()-t0, 2))

if __name__ == '__main__':
    main()
