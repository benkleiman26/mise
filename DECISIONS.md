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

## Dependencies

None so far. The export tool is plain Node with the built in test runner, and
Node 20 is the only requirement.
