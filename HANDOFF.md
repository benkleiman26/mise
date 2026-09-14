# Handoff: finish the Mealime rescue

## How to start

Repository: <https://github.com/benkleiman26/mise>, public. Clone it, or pull if
you already have it:

```sh
git clone https://github.com/benkleiman26/mise && cd mise
# or: cd ~/mise && git pull
```

Then give your agent this:

> Read `HANDOFF.md` and finish the Mealime rescue. I am signed in to Mealime in
> Chrome, so drive that session yourself over the DevTools protocol rather than
> asking me to paste things into a console. The deadline is October 21, when
> Mealime deletes everything. Ask me only if you are truly blocked.

The rest of this file is the brief.

---

You are picking up a task that is blocked and has a hard external deadline. Read
this whole file before touching anything. Everything here was learned the hard
way; do not re-derive it.

## The situation

Mealime shuts down on **October 21, 2026** and deletes all account data. The
owner has roughly 30 favorites and roughly 150 recipes he imported himself, and
none of it is off their servers yet. Today is around September 14, 2026, so
there are about five weeks left.

Your job: get those recipes onto the owner's disk. Nothing else in this
repository matters until that is done.

The owner does not have time to sit in a console pasting snippets. Automate as
much as you can and ask him for the minimum.

## Where things stand

The repository is `benkleiman26/mise`, public, cloned at `~/mise`. The tool is
`tools/mealime-export/`. 73 tests pass, run them with `npm test` from that
directory.

The pipeline is deliberately split in two, and this split is why the project
survived three wrong assumptions already. Keep it.

1. **Rescue**: get raw recipe JSON onto disk, byte for byte, unmodified.
2. **Normalize**: turn raw files into `mealime-export.json`. Pure, offline,
   re-runnable. Fully tested.

Normalize works and is not your problem. Rescue is your problem.

## What has been established

Do not retry any of these.

**There is no Mealime REST API.** `api.mealime.com/api/v2` was the spec's claim.
All six plausible identity routes returned 404 under all five auth schemes
(bearer, token header, two custom headers, query param). A capture of the web
app's own network traffic on 2026-09-14 recorded three requests in total: one
Cloudflare analytics beacon and two recipe fetches. `my.mealime.com` is server
rendered, so its lists live in page HTML, not in XHR.

**Recipe content comes from a CDN.** The web app fetches
`https://cdn-recipes.mealime.com/<uuid>.json`. In the capture those requests
carried **no authorization headers at all**. One uuid is confirmed to work in
the owner's browser: `d30ce24f-a45e-42c6-9ade-1291ca6c79d0`.

**A browser script was built to exploit that.** `browser/rescue.js` harvests
uuids from page HTML, crawls the owner's other pages, then fetches each recipe
from the CDN and downloads one file. It collected **295 uuids**.

**The fetches all failed with 403 Forbidden.** Every one. Not 404.

That is the wall you are hitting.

## The open question

S3 and CloudFront answer **403 rather than 404** for an object the caller may
not list, so a blanket 403 is ambiguous. Three hypotheses, none yet ruled out
because the owner ran out of time before reporting the diagnostic:

1. **Credentials.** The app's successful fetch carried something ours does not.
   `rescue.js` already retries `omit`, `same-origin` and `include` in turn, so
   if this were the whole story the current code might already work. Worth one
   run before anything else.
2. **The uuids are not recipe ids.** 295 is far more than the roughly 180
   recipes he has. The scan takes every uuid in the page HTML, and most may be
   component, image, or tracking ids. If so, the real recipe uuids live
   somewhere the scan is not looking and finding them is the task.
3. **Rate limiting.** 295 requests went out in a burst. A CDN firewall
   answering 403 to a flood is ordinary. Fetches are now paced at 3 at a time
   with a 150ms delay, so a clean retry tests this.

**Start by running this in the console on my.mealime.com and reading the one
line it prints.** It fetches the known good uuid three ways and says whether
that uuid is among the 295 collected:

```js
(async()=>{const K='d30ce24f-a45e-42c6-9ade-1291ca6c79d0';const s={};for(const c of ['omit','same-origin','include']){try{s[c]=(await fetch('https://cdn-recipes.mealime.com/'+K+'.json',{credentials:c})).status}catch(e){s[c]='ERR'}}let n=0,has=false;try{const i=Object.keys(JSON.parse(sessionStorage.getItem('__miseRescue')).ids);n=i.length;has=i.includes(K)}catch(e){}console.log(`omit=${s.omit} same-origin=${s['same-origin']} include=${s.include} | collected=${n} | knownIdCollected=${has}`)})()
```

| Result | Diagnosis | Next |
| --- | --- | --- |
| any status 200 | credentials | re-run `__mise.rescue()`, it already handles this |
| all 403, knownIdCollected false | wrong uuids | hypothesis 2, see below |
| all 403, knownIdCollected true | rate limited | wait, then re-run at the slower pace |

## Automate the browser

The owner is signed in to Mealime in Chrome on this Mac. Drive that session
rather than asking him to paste things.

Attach to his existing Chrome over the DevTools protocol, which keeps his
logged-in session:

```sh
# Quit Chrome first, then:
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 --user-data-dir="$HOME/Library/Application Support/Google/Chrome"
```

Then connect with Playwright over CDP (`chromium.connectOverCDP('http://localhost:9222')`)
and you can evaluate JavaScript in the page, read the DOM, and watch the network
yourself. Install Playwright locally in a scratch directory, not into this
repository, and do not add it as a project dependency.

If that is blocked, the fallback is to have the owner export cookies once, but
prefer CDP. **Never commit cookies, tokens, or any `data/` content.** The
repository is public. `data/` is already git ignored.

## If the uuids are wrong (hypothesis 2)

This is the likeliest case. The goal becomes: find where a recipe's real uuid
appears in the owner's pages.

Things to try, roughly in order:

- Open one recipe in the browser with the network panel recording. Note the
  `cdn-recipes` uuid, then search the page HTML, the JS bundles, and every
  request payload for that exact string. Wherever it first appears is the
  mapping you need.
- Compare the recipe page's own URL to the CDN uuid. If the page URL carries a
  different id or a slug, there is a lookup step between them.
- Check whether the list pages embed a JSON blob (a `<script type="application/json">`,
  a `window.__` global, or a data attribute) holding the real ids. Server
  rendered apps usually hydrate from one.
- Compare the 295 collected uuids against the known good one. If it is absent,
  the scan is reading the wrong part of the page entirely.

Once you know the shape, fix `scan()` and `crawl()` in `browser/rescue.js` to
target it, rather than scraping every uuid in the HTML.

## Fallback that cannot really fail

`browser/collect-localstorage.js`. The web app caches each recipe the user opens
under `localStorage["mealime/recipes/<uuid>"]`. Opening every recipe once and
dumping localStorage rescues the same content without touching the CDN.

It is tedious by hand, but you can automate it: drive the browser to visit each
recipe, wait, and then dump. If you are more than a few hours into the CDN
problem with no progress, switch to this. **A tedious rescue that works beats an
elegant one that misses the deadline.** The owner would much rather have the
data than a clean solution.

## When the rescue works

```sh
cd ~/mise/tools/mealime-export
node browser/convert.mjs --in ~/Downloads/mealime-rescue.json
node src/cli.mjs normalize --include-mealime-content
npm run images
```

`--include-mealime-content` is right for the owner's private copy. Without it,
recipes judged to be Mealime's own content are reduced to a reference, which is
correct for a file shared with others and wrong for his own rescue. See
`DECISIONS.md`.

Then check `data/mealime/_normalize_report.json` for warnings. The real CDN JSON
shape has never been seen, so the normalizer's field mapping is written against
the shape documented in the spec, section 1a, and may need correcting. Fix it
and re-run normalize, which never touches the network.

Run `npm run images` before the deadline too. Image URLs point at Mealime's
servers and will die with the service.

## Done means

- `data/mealime/mealime-export.json` exists, with a recipe count close to 180.
- Recipes have names, ingredients, and instructions, verified by eye on a few.
- `data/mealime/images/` has photos.
- `_normalize_report.json` has no widespread warnings.
- `npm test` passes and the work is committed and pushed to `main`.
- The owner has a copy backed up somewhere off this machine.

## Conventions

From the build spec, section 11, and they are enforced:

- **No em dashes** anywhere: code, comments, docs, commit messages, UI copy.
  Use commas, colons, or periods.
- Commit after each meaningful unit of work, with a message explaining why, not
  just what.
- Decisions the spec does not cover go in `DECISIONS.md`. Known gaps go in
  `TODO.md`.
- No third party dependencies in the repository without a line in `DECISIONS.md`.
- The tool is read only against Mealime. GET and HEAD only. Never write to,
  modify, or delete anything in the account, and never follow links that look
  like sign out, delete, or cancel.

## Context you may want

- Build spec (the source of truth, still being edited):
  <https://docs.google.com/document/d/11xXFBZrQxdpB-XnxpqPGV71n2Sxlkd2PdANPpr2aov0/edit>
- `DECISIONS.md` explains why the pipeline is split and why provenance defaults
  to withholding.
- `TODO.md` lists what is known to be missing.
- `tools/mealime-export/browser/README.md` covers all three browser scripts.

Report back with what the 403 actually was, what you changed, and the final
counts.
