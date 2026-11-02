# Handoff: fetch the NYT Cooking library

For whoever is driving the browser. Everything below happens on Ben's Mac, in
his signed-in Chrome, with the repository already cloned at `~/mise`.

## What this is for

Mise is a meal planning app. Ben's 213 Mealime recipes are already imported.
His 169 saved NYT Cooking recipes are not: the earlier export captured only
urls, folders and "cooked" flags, because the Recipe Box renders client side
and NYT has no public API for it.

The recipe text itself is behind his subscription, so it has to be fetched from
a browser that is signed in as him. That is this job.

**Success looks like:** `~/mise/data/mise/nyt_import.json` exists and contains
close to 169 recipes with their ingredients and steps.

## Rules

- **Read only.** The script issues GET requests to `cooking.nytimes.com` only,
  and both of those are enforced in its code. Do not change, save, unsave or
  rate anything in his Recipe Box.
- **Nothing leaves the machine.** The recipes go from the page to a file on his
  disk. Do not upload them anywhere, and do not paste recipe content into a
  chat.
- **Do not commit anything from `data/`.** That folder is git-ignored and the
  repository is public.
- If something does not work, **report what you saw** rather than improvising a
  different approach. The failure modes below are the ones worth knowing about,
  and an unexpected one is information.

## Step 1: get the command to paste

In Terminal:

```sh
cd ~/mise && git pull
cd tools/nyt-import
npm test
npm run urls | pbcopy
```

- `npm test` should print `# pass 10`, `# fail 0`.
- `npm run urls` prints to stderr how many recipes it found, which should be
  around 169, and pipes the actual command to the clipboard.

**If it says no urls were found**, the Recipe Box export is missing or in an
unexpected shape. Run `ls -la ~/mise/data/nyt/` and report what is there.

## Step 2: fetch, in the browser

1. Open Chrome and go to <https://cooking.nytimes.com>. Confirm he is signed
   in: there should be a Recipe Box in the account menu, and opening any saved
   recipe should show the full ingredient list rather than a subscribe wall.
2. Open the console: **Cmd+Option+J**.
3. Open `~/mise/tools/nyt-export/browser/fetch-recipes.js`, copy the whole
   file, paste it into the console, press enter. It should print
   `Ready. Paste the __nyt.fetchAll([...]) line that npm run urls printed.`
4. Paste from the clipboard. That is the `__nyt.fetchAll([...])` line from
   step 1. Press enter.

It now fetches about two and a half recipes a second and prints progress every
ten, like `40/169  kept 39  failed 1`. Expect roughly 90 seconds. **Leave the
tab in the foreground and do not navigate away.**

When it finishes:

```js
__nyt.status()          // how many it has
__nyt.retryFailures()   // retries only the ones that failed
__nyt.rescue()          // downloads nyt-recipes.json
```

Run `retryFailures()` if there are any failures, then `status()` again, then
`rescue()`. The file lands in `~/Downloads/nyt-recipes.json`.

## Step 3: convert

```sh
cd ~/mise/tools/nyt-import && npm run convert
```

It prints how many it converted, how many are marked cooked, and anything it
skipped, then writes `~/mise/data/mise/nyt_import.json`.

## Step 4: report back

Send these, and nothing else:

- the counts from `__nyt.status()`
- any failure urls and their reasons, from the table the script prints
- the full output of `npm run convert`

Ben imports the file into the app himself.

## Failure modes worth knowing

**Every page fails with HTTP 403 or returns a subscribe wall.** He is not
signed in, or is signed into a different account. Check by opening one saved
recipe by hand.

**Every page fails with "no schema.org Recipe in the page".** NYT has changed
how it publishes the recipe. Do not guess at a DOM scrape. Open one recipe,
run this, and send the output:

```js
[...document.querySelectorAll('script[type="application/ld+json"]')]
  .map(s => JSON.parse(s.textContent))
  .map(d => d['@type'] ?? Object.keys(d))
```

**Failures start partway through and then every page fails.** Likely rate
limiting. Wait ten minutes, then `__nyt.retryFailures()`. If it happens again,
stop and say so; the pause between requests needs raising and that is a code
change.

**A handful fail and the rest work.** Normal. Those are usually recipes that
have been taken down. `retryFailures()` once, then carry on with what you have.

**`__nyt` is not defined.** The script was not pasted, or the page was
reloaded after pasting. Paste it again.

## What not to do

- Do not scrape the rendered DOM as a fallback. The JSON-LD is the contract; if
  it is gone, that is worth knowing rather than working around.
- Do not raise the request rate.
- Do not fetch anything outside `cooking.nytimes.com`. The script refuses, and
  the refusal is the point.
- Do not re-run `fetchAll` from scratch after a partial success. Use
  `retryFailures()`, which keeps what has already been collected.
