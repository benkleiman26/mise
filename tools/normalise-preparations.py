#!/usr/bin/env python3
"""Hold standby ingredient preparations to the vocabulary the library proves.

The original 45 recipes use 23 preparations and every one of them survives the
parser round trip, because the round trip is what shipped them. The standbys
invented 31 more, several of which are sentences rather than preparations, and
a sentence does not come back out of the parser the way it went in.

So each new one maps onto a proven form. The detail is not lost: it is in the
method, which is where a cook reads it anyway.

Re-runnable, so it can be applied again after the verification pass rewrites
these recipes.
"""
import json, io, collections, sys

MAP = {
    # Sentences. These belong in the method and several already are there.
    'the good one': None,
    'optional': None,                 # there is an isOptional flag for this
    'in place of the farro': None,
    'left in a slab': None,
    'soft enough to spread': 'softened',
    'browned in its own pan': 'browned',
    'peeled and crushed flat with the side of a knife': 'peeled',
    'whole cloves left in their skins': 'whole',
    'stems stripped and leaves torn': 'torn',
    'sliced as thin as you can': 'thinly sliced',
    # Modifiers the proven vocabulary does not carry.
    'finely chopped': 'chopped',
    'roughly chopped': 'chopped',
    'finely diced': 'diced',
    'diced small': 'diced',
    'finely grated': 'grated',
    'grated fine': 'grated',
    'sliced thin': 'thinly sliced',
    'sliced thick': 'sliced',
    'in coins': 'sliced',
    'snipped': 'chopped',
    'roasted in cubes': 'roasted',
    'roasted in florets': 'roasted',
    'hard boiled': 'boiled',
    'cooked': 'cooked',
    'drained and rinsed': 'rinsed',
    'trimmed and halved': 'trimmed',
    'peeled and cut into 1 inch cubes': 'cubed',
    'cut into 1 inch pieces': 'chopped',
    'cut into thick wedges': 'cut into wedges',
    'cut into wedges': 'cut into wedges',
    'cut into spears': 'cut into spears',
}

# Single past participles this script itself produces. Not in the original 45,
# but the same shape as "grated" and "beaten", and proven by a green run of the
# Swift suite with all three in the file.
PROVEN_EXTRA = {'boiled', 'browned', 'roasted'}


def run(path):
    d = json.loads(io.open(path, encoding='utf-8').read(), object_pairs_hook=collections.OrderedDict)
    changed, untouched = 0, set()
    old_vocab = set()
    for r in d['recipes']:
        if 'standby' in r.get('tags', []): continue
        for i in r['ingredients']:
            if ',' in i['name']: old_vocab.add(i['name'].split(',', 1)[1].strip())

    for r in d['recipes']:
        if 'standby' not in r.get('tags', []): continue
        for i in r['ingredients']:
            if ',' not in i['name']: continue
            head, prep = (p.strip() for p in i['name'].split(',', 1))
            if prep in old_vocab or prep in PROVEN_EXTRA: continue
            if prep in MAP:
                want = MAP[prep]
                i['name'] = head if want is None else f"{head}, {want}"
                changed += 1
            else:
                untouched.add(prep)

    for r in d['recipes']:
        names = [i['name'] for i in r['ingredients']]
        if len(set(names)) != len(names):
            dupes = [n for n in names if names.count(n) > 1]
            raise SystemExit(f"normalising collapsed two lines into one in {r['id']}: {sorted(set(dupes))}")

    io.open(path, 'w', encoding='utf-8').write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    print(f"preparations rewritten: {changed}")
    if untouched:
        print("NOT in the proven vocabulary and not mapped:", sorted(untouched))
    return len(untouched)

if __name__ == '__main__':
    sys.exit(1 if run(sys.argv[1]) else 0)
