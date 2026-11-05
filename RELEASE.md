# Getting Mise onto a phone

## Updating first

```sh
cd ~/mise && ./scripts/update.sh
```

Not plain `git pull`. Xcode rewrites `Mise.xcodeproj/project.pbxproj` whenever
files change on disk, so the next pull is refused for local changes and says so
in a line that scrolls past in a terminal full of build output. The result is
rebuilding code that did not change. This parks Xcode's edits, pulls, and
prints what actually arrived.

Signing is set in the project: team `NDM99C66D7`, bundle id
`com.benkleiman.mise`, automatic signing. Nothing to pick in Xcode.

## First, on your own iPhone

Plug the phone into the Mac, unlock it, and trust the computer if asked.

1. Open `~/mise/Mise.xcodeproj`.
2. In the toolbar, where it says `iPhone 17e`, choose your actual iPhone.
3. **Cmd+R**.

The first run asks you to trust the developer certificate on the phone:
**Settings → General → VPN & Device Management**, tap your Apple ID, tap Trust.
Once only.

This installs a debug build over the cable. It works, and it is how to check
something quickly, but it does not get the app to anyone else.

## Then, TestFlight, which is how your wife gets it

### One time: create the app record

1. <https://appstoreconnect.apple.com> → **Apps** → **+** → **New App**
2. Platform **iOS**, name **Mise**, primary language **English (U.S.)**
3. Bundle ID: pick `com.benkleiman.mise` from the list. If it is not there,
   register it first at
   <https://developer.apple.com/account/resources/identifiers/list> as an
   **App ID**, explicit, with that exact string.
4. SKU can be anything, `mise` is fine.

### One time: an upload key

So that shipping is a command rather than eight clicks in Xcode's Organizer.

1. <https://appstoreconnect.apple.com> → **Users and Access** →
   **Integrations** → **App Store Connect API** → **Team Keys** → **+**
2. Name it `mise-release`, role **App Manager**, Generate
3. Download the `.p8`. **It downloads once and never again.** Put it
   somewhere sensible:

   ```sh
   mkdir -p ~/private_keys
   mv ~/Downloads/AuthKey_*.p8 ~/private_keys/
   ```

4. Note the **Key ID** from that row and the **Issuer ID** from the top of the
   page, then:

   ```sh
   cd ~/mise
   cp scripts/appstore.env.example scripts/appstore.env
   open -e scripts/appstore.env
   ```

   Fill in the three values. That file is git ignored; the `.p8` is a
   credential that can upload builds under your name, so it stays out of the
   repository and out of chat.

### Every build

```sh
cd ~/mise && ./scripts/release.sh
```

It runs the tests, refuses to ship if they fail, raises the build number,
archives, and uploads. Ten minutes, mostly waiting.

Apple then takes ten to twenty minutes to process it. Internal testers get it
straight away. An external group's **first** build needs Apple's review,
usually within a day; after that one, later builds go out without review.

`MARKETING_VERSION` is the version people see, currently `0.1`. Raise it by
hand in Xcode when something is worth calling new.

## Getting it to your wife

Her phone does not have to be in the room. Add her as an **internal** tester
and she installs it herself from TestFlight.

Internal means a person with a seat in your App Store Connect account. For a
spouse that is right, and it is worth it for one reason: internal builds skip
Apple's beta review entirely and arrive within about twenty minutes of the
upload finishing. External testers wait a day for the first one.

1. <https://appstoreconnect.apple.com> → **Users and Access** → **+**
2. Her Apple ID email, role **Developer**, and tick access to the Mise app
3. She accepts the invitation by email
4. **Apps → Mise → TestFlight → Internal Testing → +**, make a group, add her
5. She installs **TestFlight** from the App Store and Mise appears in it

### What she gets, and what she has to do once

She gets the whole app, and since sync works she gets your library too, but
not automatically. On her phone:

1. **Settings → sign in**, with her own account rather than yours
2. **Join a household**, paste your invite code
3. **Sync now**, and leave it a minute

That first round pulls several thousand records: 427 recipes with their
ingredients and steps, the grocery table, the pantry and the week. Her recipe
count should end up matching yours.

She does not import the recipe files. Recipes sync now, so importing as well
would do the same work twice.

Photographs do not sync, deliberately: they are most of a free database
allowance spent on bytes both phones already have. A recipe that came from a
link keeps the picture's address and fetches it, so most of the library looks
right on her phone without the bytes ever crossing.

## Giving it to someone outside the household

See [TESTERS.md](TESTERS.md). External TestFlight needs Apple's beta review and
an honest answer to the privacy questions, and the other household's data lands
in your Supabase project, which they should be told before they sign up.

## Known gaps before anyone relies on it

- Nothing marks a meal as cooked, so the plan does not clear itself.
- A recipe cannot be written down from scratch, and editing one is limited to
  its serving count.
- The aisle order is the spec's default, not your store's.
- Sync runs while the app is open, when it is opened, and as it is closed.
  Nothing moves while both phones are shut, because there is no server pushing
  to them.
