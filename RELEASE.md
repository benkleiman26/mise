# Getting Mise onto a phone

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

### Every build

```sh
cd ~/mise
xcodebuild -scheme Mise -destination 'generic/platform=iOS' \
  -archivePath ~/Desktop/Mise.xcarchive archive
```

Then in Xcode: **Window → Organizer → Archives**, select the newest, click
**Distribute App → TestFlight & App Store → Upload**.

Processing takes ten to twenty minutes. Then in App Store Connect:
**TestFlight → Internal Testing**, add yourself and your wife by Apple ID
email. Internal testers need no review and get it within minutes.

**Raise the build number before every upload**, or the upload is rejected for
reusing one:

```sh
cd ~/mise
agvtool next-version -all
```

`MARKETING_VERSION` is the version people see, currently `0.1`. Raise it by
hand in Xcode when it is worth calling something new.

## What she will and will not get

She gets the whole app: the library, the plan, the list, the pantry.

She does not get **your** library. There is no sync yet, so her copy starts
with the 45 built-in recipes and an empty plan, and the two of you keep
separate lists. For one shared shop that is worse than one phone.

So the order that actually works is: you use it for a week and find what is
wrong, sync gets built, and then she installs. Putting it on her phone before
sync gets her a demo and a disappointment.

## Known gaps before anyone relies on it

- No sync, so one household means one device.
- Nothing marks a meal as cooked, so the plan does not clear itself.
- A recipe cannot be written down or edited beyond its serving count.
- The aisle order is the spec's default, not your store's.
