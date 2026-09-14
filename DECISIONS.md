# Decisions

Choices made while building that the spec did not settle. Section 11 asks for
the simplest option that fits the principles in section 2, recorded here, with
work continuing rather than blocking.

Newest last.

## The spec is not mirrored into the repository

`SPEC.md` links to the Google Doc rather than copying it. The document is under
active revision. A copy would drift and the repository would end up with two
specs that disagree. The link is the single source of truth, as the document
itself asks.

## The Mealime export rescues raw responses first, then normalizes separately

Section 5.7 asks for one JSON file per recipe. The export is split into two
commands instead: `export` writes every API response to `raw/` exactly as the
server sent it, and `normalize` turns those files into the documented shape.

The reason is the deadline. Mealime deletes all account data on 2026-10-21. If
an assumption about the JSON turns out to be wrong, the normalizer can be fixed
and re-run against the saved raw files in November. Re-fetching in November is
not possible. Parsing mistakes are recoverable, missing data is not.

## The export probes for endpoints instead of hard coding them

Mealime's v2 API is not publicly documented and cannot be tested without a live
account, which the build environment does not have. The script tries a list of
plausible routes and auth schemes, reports what answered, and writes the result
to `raw/_discovery.json`. It then uses whatever was found.

A hard coded route that turned out to be wrong would fail at the worst moment,
close to the deadline, with no way to tell why.

## The export does not parse ingredient text

Quantity strings stay exactly as Mealime wrote them, including awkward ones like
`2 (15 oz) cans`. The app's `IngredientParser` handles them later, which is the
same parser used for URL imports, with one review screen for the lines it is
unsure about.

Parsing in the export script would mean two parsers to keep in agreement, and
the export script is throwaway while the app parser is not.

## Recipe provenance is assumed to be Mealime's unless there is a signal

Section 5.7 draws a line between recipes the user imported themselves, which
travel in full, and recipes Mealime wrote, which travel as a reference only.
Nothing in the data states which is which, so the export infers it from the
collection the recipe appeared in, the presence of a source URL, and any
ownership fields.

When the signals are absent the export assumes Mealime wrote it. That is the
choice that withholds rather than copies. Each recipe carries the reasoning in
`provenance_reasons` so a wrong call is visible rather than silent, and
`--include-mealime-content` produces a complete private copy for the owner.

## The interchange format is versioned from the start

`mealime-export.json` declares `format` and `version`. People will save these
files before the shutdown and import them months later, so the reader has to be
able to recognize an old file. Changes to a field's meaning bump the version
rather than being made in place.

## Images are downloaded, not just referenced

The spec does not ask for this. The rescued JSON references images by URL on
Mealime's servers, and those URLs stop working when the service does, so a
rescue that keeps only links loses every photo on 2026-10-21.

`npm run images` is a separate command rather than part of the export, because
it is slow, it is the part most likely to be interrupted, and it should be
resumable on its own. No auth header is sent when fetching images: they sit on
third party hosts, including blogs a user imported from, and the Mealime token
has no business going there.

## The tool ships in the main repository rather than its own

Section 9 asks for the export script to be public so other Mealime users can run
it before the shutdown. The `mise` repository is public, so the script is
already public at `tools/mealime-export/` and a second repository would be one
more thing to keep in sync for no gain.

If Mise later needs to go private, the tool moves out then.

## The rescue runs in the browser, because there is no API

Section 5.7 says to pull the data from `api.mealime.com/api/v2` with an auth
token. There is no such API. A capture of the web app's own network traffic on
2026-09-14 showed three requests in total: one analytics beacon and two fetches
of `cdn-recipes.mealime.com/<uuid>.json`, sent with no authentication headers.
`my.mealime.com` is server rendered, so the recipe list is in the page HTML.

So `browser/rescue.js` is the primary path: it harvests recipe ids from the
pages the user visits, fetches each recipe from the CDN, and downloads one file.
No token is needed anywhere, which also makes it far easier for a stranger to
run before the shutdown.

The Node code is unchanged in shape and still does the normalizing. The browser
produces raw recipe JSON, `browser/convert.mjs` lays it out the way the API path
would have, and `npm run normalize` runs exactly as before. Splitting rescue
from normalize is what made this survivable: only the fetching had to be
rewritten.

The API client is kept rather than deleted. It costs nothing, it is tested, and
if Mealime does have an internal API on another host it is a small edit to point
at it.

## Dependencies

None so far. The export tool is plain Node with the built in test runner, and
Node 20 is the only requirement.

## The rescue reads the web app's state instead of scraping pages

The earlier browser rescue scraped every uuid out of page HTML and got 295 of
them, then hit 403 on all of them. The uuids were not recipes. S3 answers 403,
not 404, for keys it will not list, so the wall looked like an auth problem
and was really a wrong-id problem.

The web app is a React app that loads the entire account with one call
(`api/v2/get_user`, so there is an API, just not one worth probing) and keeps
the result in component state. `browser/rescue-state.js` walks the React tree,
takes that object, strips the secrets, and fetches the 54 favourites from
`cdn-recipes.mealime.com` by their `published_recipe_uuid`, all of which
answered 200 with no credentials. The user's own 159 recipes are inline in
the account object, so they need no fetch at all.

This is fragile in the way any dependence on React internals is, and Mealime
will not change its bundle again before it shuts down, so that is acceptable.

## Images are rescued through the browser, as a zip

`cdn-uploads.mealime.com` refuses everything that is not the owner's browser
(403 from the cloud, connection refused from the laptop VM) and sends no CORS
headers, so pages on my.mealime.com cannot fetch it either. A tab opened on
that origin can fetch same-origin, so `browser/rescue-images.js` runs there,
packs the files into a stored zip written by hand (no third party script
loaded into the page), and `images --from-zip` feeds that zip to the same
download code through its `fetchImpl` hook. Chrome only honors a download
from a non-HTML document on a real click, which is why the script draws a
button instead of clicking for you.

## Preferences are decoded from observed ids

The account's profile stores `recipe_type_id: 4` and `dislike_ids: [10]`; the
lookup tables live only in the app bundle. The settings page for this account
showed Pescetarian, olives, 4 servings, US units on 2026-09-14, so
`convert.mjs` carries exactly those id to name pairs and leaves any other id
labeled as an id rather than guessing.

## The NYT export collects in the browser and converts in Node

Same split as the Mealime rescue, for the same reason: the collecting depends on
a page structure nobody has verified, and the converting does not. When NYT's
markup turns out to differ from what was assumed, only `browser/collect.js`
changes, and `src/convert.mjs` keeps its tests.

The collector tries three strategies in order and reports which fired: the
Next.js hydration payload, the rendered DOM, and raw matching of
`/recipes/<id>-<slug>` anywhere in the markup. That last one is crude and will
work even if the first two are wrong, which is the point. `__nyt.probe()` exists
so the first move on an unknown page is to look rather than to guess, which is
the lesson from spending a day on a Mealime API that did not exist.

## Recipe Box folders become tags, but status folders do not

Section 5.6a asks for folders to be mapped to tags. Some folder names describe a
status rather than a topic: Cooked Recipes, Recipe Box, Saved. Those become the
`cooked` flag or nothing at all, never a tag, because a tag named "cooked" would
compete with the real cooked count the app keeps.

Filler words are dropped too, so "Easy Kid-Friendly Recipes" becomes
"kid friendly" rather than "easy kid friendly recipes". Tags are flat and
lowercase per section 5.1.

## The bookmarks parser lives in tools, not just in the app

Section 8 lists two tools, and this adds a third, `tools/bulk-import/`. The
bulk URL import is an app feature and stays one; what lives here is the Netscape
bookmarks parser and an inventory built on it.

The format is awkward (invalid HTML, missing closing tags, folders implied by
nesting) and getting it wrong is silent: a mis-parsed folder stack quietly files
recipes under the wrong tag. Writing it in Node first means it is tested
exhaustively where tests are cheap, and Phase 4 ports known-good logic against
the same fixture rather than starting from the spec.

The inventory also answers a planning question that cannot wait for Phase 4: how
many of the bookmarks sit on hosts without JSON-LD, which is what sizes the AI
extraction work in Phase 4b.
