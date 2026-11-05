# Giving Mise to another household

Everything here is TestFlight's external testing route, which is the right one
for another household: internal testing needs a seat in your Apple developer
account, and that is reasonable for your wife and not for friends. Her path is
in [RELEASE.md](RELEASE.md).

## Before you can send it

**1. The app icon exists now.** TestFlight refuses a build without one. It is
a list on a plate, generated rather than designed, and replacing it with
something better costs nothing: drop a 1024x1024 png at
`Mise/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`.

**2. Beta App Review.** The first external build is reviewed by Apple, usually
within a day. They need:

- What to test, in a sentence or two
- A contact email
- Working sign-in details if the app needs an account to be useful. Mise does
  not: everything except sharing works signed out. Say that in the notes, or
  review will ask.

**3. The privacy questions** in App Store Connect. Answer them honestly:

- Mise collects an **email address**, for the account, and only if someone
  turns sharing on
- It stores **user content**: recipes, meal plans, grocery lists. All of it
  travels once sharing is on, apart from recipe photographs, which never
  leave the phone that downloaded them
- None of it is used for tracking or advertising
- It is all in your Supabase project

## The thing you have to tell them

**Their data goes into your database.** Their grocery lists and meal plans land
in the Supabase project on your account. Row level security means the app
cannot show your household's data to theirs or the other way round, but you are
the project owner: you can open the SQL editor and read everything in it.

That is fine between people who know it. It is not fine as a surprise. Tell
them before they sign up, in those words.

If that is awkward, the alternative is for them to run their own Supabase
project and their own build, which is more than a casual tester will do.

## Sending it

```sh
cd ~/mise
agvtool next-version -all
xcodebuild -scheme Mise -destination 'generic/platform=iOS' \
  -archivePath ~/Desktop/Mise.xcarchive archive
```

Then **Xcode → Window → Organizer → Archives**, newest archive,
**Distribute App → TestFlight & App Store → Upload**.

In App Store Connect, once it has processed:

1. **TestFlight → External Testing → +** to make a group, call it something
   like "Other households"
2. Add their email addresses
3. Attach the build, fill in the test notes, submit for review
4. When it passes, they get an email with a link and install TestFlight

## What they should expect, and what to tell them

**It works offline and alone.** They do not have to sign in. The plan, the
list and the pantry all work on one phone.

**They start with 45 built-in recipes**, not your 427. Yours are your own
rescued library and most of them are New York Times recipes, which are not
yours to redistribute. They can add their own by pasting links.

**Sharing is brand new and has never run against the real server.** Expect it
to break. Ask them to send you the message from Settings when it does, not just
"it didn't work".

**The invite code is a key.** Whoever has it, plus any account, can read and
change that household's list. One code per household, sent to one person.

## What to ask them

Not "what do you think". Ask:

- Did you shop from it? What happened in the aisle?
- What did you look for and not find?
- What made you go back to your old way of doing this?

The useful answers come from the third one.
