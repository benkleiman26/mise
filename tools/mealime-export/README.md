# mealime-export

Export your own Mealime data before it is deleted.

Mealime shuts down on **October 21, 2026**, and all account data goes with it.
This script copies your recipes, favorites, manual grocery items, and eating
preferences out of your account and onto your own disk, as JSON.

It is read only. It only ever issues GET requests, only to mealime.com, and it
cannot change or delete anything in your account. Both guards are enforced in
code and covered by tests.

Nothing is uploaded anywhere. Your token and your data stay on your machine.

## Requirements

Node 20 or newer. No dependencies to install.

```sh
node --version
```

## Getting your token

Mealime's web app keeps your session token in the browser.

1. Sign in at <https://my.mealime.com>.
2. Open developer tools (F12, or Cmd+Option+I on a Mac) and go to the Console.
3. Paste this and press enter:

   ```js
   copy(localStorage.getItem('mealimeAuthToken'))
   ```

   The token is now on your clipboard. If that returns `null`, look through
   `localStorage` for a similar key:

   ```js
   Object.keys(localStorage).filter(k => /token|auth|jwt|session/i.test(k))
   ```

   Still nothing? Open the **Network** tab, reload the page, click any request
   to `api.mealime.com`, and read the `Authorization` request header. That shows
   both the token and the scheme the API expects, which is the most reliable
   way to find it.

4. Put it in your shell. Do not paste it into a file in this repository.

   ```sh
   export MEALIME_AUTH_TOKEN='paste-it-here'
   ```

The token is short lived. If the script stops authenticating part way through,
grab a fresh one and run the same command again. The export resumes where it
stopped.

## Running it

```sh
cd tools/mealime-export

# 1. Check that the API answers and see roughly how much is there. Safe.
npm run discover

# 2. Pull everything down. Resumable, so re-run it freely.
npm run export

# 3. Turn the raw responses into the import file.
npm run normalize

# 4. Download the recipe photos. Do this before the shutdown.
npm run images
```

By default everything lands in `data/mealime/` at the repository root. Use
`--out <dir>` to put it somewhere else.

When it finishes, check the counts it prints against what my.mealime.com shows.
If they do not match, re-run **before** the shutdown date. After October 21
there is nothing left to fetch.

## What you get

```
data/mealime/
  mealime-export.json     the file to keep, and to import into Mise later
  recipes/<id>.json       one file per recipe
  favorites.json          your favorited recipe ids
  manual_items.json       grocery items you added by hand
  images/<id>/0.jpg       downloaded recipe photos
  raw/                    untouched API responses, kept on purpose
```

Run `npm run images` before the shutdown. The export stores image URLs, and
those URLs point at Mealime's servers, so they will almost certainly stop
working when the service does. The download step saves the actual files and
records their paths in `mealime-export.json`. It skips anything already on disk,
so re-running it only retries what failed.

`raw/` is the important one. The script saves every response exactly as the
server sent it before interpreting any of it. If it turns out something was
parsed wrongly, `npm run normalize` can be fixed and re-run against `raw/`
afterwards. Re-fetching will not be possible.

### A note on recipe content

Recipes **you** imported into Mealime are yours, and the export carries them in
full.

Recipes **Mealime wrote** belong to Mealime's owner, Albertsons. For those the
export keeps a reference only: the id, the name, and the image URL, so an app
can offer you something comparable later without copying their text. They are
listed under `withheld` in `mealime-export.json`.

If you want a complete private copy of everything for your own use, pass
`--include-mealime-content` to the normalize step. That copy is for you, not for
sharing or republishing.

## If the API does not work

The API is not documented publicly, and the script probes for the right
endpoints rather than assuming them. Two fallbacks live in
[`browser/`](browser/):

- `capture-api-calls.js` records the calls the web app actually makes, so the
  candidate routes can be corrected. Start here if `discover` returns 404 for
  everything.
- `collect-localstorage.js` rescues recipes straight out of the web app's own
  cache, for when the API cannot be made to work at all.

## Troubleshooting

**"MEALIME_AUTH_TOKEN is not set"**
The variable is not in this shell. Run the `export` line again in the same
terminal window.

**Every route returns 404**
The paths the script tries are guesses, and they are wrong. A fresh token will
not help. Record the real ones with
[`browser/capture-api-calls.js`](browser/capture-api-calls.js) and either send
them in or fix the candidate lists in `src/discover.mjs`.

**"The server rejected the token"**
The token is stale or was copied incompletely. They are short lived, so get a
fresh one. If it still fails, use the browser fallback in `browser/`.

**Counts look too low**
`npm run discover` prints what each endpoint returned. If your recipes are not
showing up, open an issue with that output (with the token removed) and the
counts you see on the website.

## License

MIT. Use it, fork it, and share it with anyone who needs their data out.
