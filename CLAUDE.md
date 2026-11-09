# Mise

A personal meal planning and grocery list app for iOS, built by one person for
his household and lent to two friends. Not a product. Swift, SwiftUI,
SwiftData locally, Supabase for sharing a household between phones.

Shipped: on TestFlight, syncing between two iPhones, 428 recipes.

## Read these before changing anything

In this order, and do not skip the first two:

- `TODO.md` opens with "Where it stands", which is the current state and the
  open items in the order they are worth taking. Start here.
- `DECISIONS.md` is 1,300 lines of why things are the way they are. Most
  surprising choices in this codebase are deliberate and explained there. Check
  before you "fix" something that looks wrong.
- `ANDROID.md` if anything touches the sync wire format. It lists what is load
  bearing across clients and what is already known to be broken.
- `RELEASE.md` for shipping, `TESTERS.md` for giving it to another household,
  `SPEC.md` for the original requirements.

The comments in `Mise/Sync/` and `Mise/Domain/Services/StableID.swift` carry
the real reasoning for the parts that have bitten hardest. They are long on
purpose.

## Standing rules

**Never commit anything under `data/`.** This repository is public and `data/`
holds the owner's rescued personal recipe library.

**Never redistribute the recipe library.** Most of it is New York Times
recipes. They are the owner's to keep and not his to hand to other households.
Other households start with the 45 seeded recipes.

**No em dashes.** Not in UI copy, comments, documentation or commit messages.

**`Mise/Resources/supabase.json` and `scripts/appstore.env` are gitignored and
stay that way.** The app carries the publishable key only. The Supabase secret
and `service_role` keys never go near the client.

**The export tools are read only and stay that way.** `tools/mealime-export`
issues GET and HEAD against mealime.com hosts only; `tools/nyt-export` issues
GET against cooking.nytimes.com only. Auth tokens come from environment
variables, never from the repository.

**Another household's data lands in the owner's Supabase project**, where he
can read it in the SQL editor. Anyone invited is told that before they sign up,
in those words. See `TESTERS.md`.

**Do not open a pull request** unless asked for one in the current
conversation.

## Building and shipping

There is no Swift toolchain in a cloud session. Changes written there are
unverified until they are built on the Mac. Say so rather than implying a
change compiles.

```sh
./scripts/update.sh     # always first: parks Xcode's pbxproj churn, pulls, rebases
./scripts/release.sh    # tests, bumps the build number, archives, uploads
```

`release.sh` raises the build number before it archives, so **every run burns a
build number whether or not it finishes**. Run it once. Do not suggest it again
in a later message without checking whether it has already run.

Quick compile check without a device:

```sh
xcodebuild build -scheme Mise -destination 'platform=iOS Simulator,name=iPhone 17e' -quiet
```

## Shape of the code

| Path | What it is |
| --- | --- |
| `Mise/App` | Entry point, `AppContainer`, root tab bar, first launch seeding |
| `Mise/Features` | One folder per feature, each a SwiftUI view over an `@Observable` store |
| `Mise/Domain/Models` | SwiftData `@Model` classes. Property names collide with `NSManagedObject`'s own: see `Deletion.swift` |
| `Mise/Domain/Services` | Pure logic. No SwiftUI, no SwiftData |
| `Mise/Domain/Repositories` | Protocols plus SwiftData implementations |
| `Mise/Sync` | The Supabase client, the wire mapper and the engine |
| `supabase/` | `schema.sql` and a Postgres test harness under `tests/` |
| `tools/` | One off exports and linters that run without Xcode |
| `data/` | Rescued personal data. Git ignored, never committed |

Records carry derived ids (`StableID`, RFC 4122 v5) so two devices compute the
same id for the same logical row without talking to each other. Anything that
changes how an id is derived changes which rows two phones agree about.
