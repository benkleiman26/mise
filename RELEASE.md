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

## What she will and will not get

She gets the whole app: the library, the plan, the list, the pantry.

She does not get **your** library. There is no sync yet, so her copy starts
with the 45 built-in recipes and an empty plan, and the two of you keep
separate lists. For one shared shop that is worse than one phone.

So the order that actually works is: you use it for a week and find what is
wrong, sync gets built, and then she installs. Putting it on her phone before
sync gets her a demo and a disappointment.

## Giving it to someone outside the household

See [TESTERS.md](TESTERS.md). External TestFlight needs Apple's beta review and
an honest answer to the privacy questions, and the other household's data lands
in your Supabase project, which they should be told before they sign up.

## Known gaps before anyone relies on it

- No sync, so one household means one device.
- Nothing marks a meal as cooked, so the plan does not clear itself.
- A recipe cannot be written down or edited beyond its serving count.
- The aisle order is the spec's default, not your store's.
