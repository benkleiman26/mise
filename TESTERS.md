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

1. **TestFlight → Test Information** and fill it in. External testing stays
   hidden until this is complete.
2. **Internal Testing → +** and make a group with just you in it. This is a
   prerequisite, not optional: App Store Connect does not show the External
   Testing section at all until one internal group exists. It is useful on its
   own too, because internal builds skip Beta App Review entirely.
3. **External Testing → +** to make a group, call it something like
   "Other households"
4. Either add their email addresses, or turn on the group's **public link**
   and send them the URL. If you use the link, set the tester limit low. These
   links are public, they get scraped, and anyone who installs from one is
   somebody you never got to tell about the database.
5. Attach the build, fill in the test notes, submit for review
6. When it passes, they get an email with a link, or the public link starts
   working

**Only one build per version can sit in Beta App Review at a time.** If 0.1 (2)
is in review, 0.1 (3) cannot be submitted until 2 is approved or expired. Expire
the one you do not want rather than waiting it out.

## What they should expect, and what to tell them

**It works offline and alone.** They do not have to sign in. The plan, the
list and the pantry all work on one phone.

**They start with 45 built-in recipes**, not your 427. Yours are your own
rescued library and most of them are New York Times recipes, which are not
yours to redistribute. They can add their own by pasting links.

**Sharing is new.** It runs between two phones in one household and has done
so for a while, but it has not had many hands on it. Ask them to send you the
message from Settings when something goes wrong, not just "it didn't work".

**The invite code is a key.** Whoever has it, plus any account, can read and
change that household's list. One code per household, sent to one person.

## What to ask them

Not "what do you think". Ask:

- Did you shop from it? What happened in the aisle?
- What did you look for and not find?
- What made you go back to your old way of doing this?

The useful answers come from the third one.

## What to send them

The one thing they can get wrong is joining **your** household instead of
making their own. If they paste your invite code they get your grocery list
and your recipe library, which is both wrong for them and not yours to hand
over: most of that library is the New York Times's.

So the order matters. One of them starts a household, the other joins it with
*that* code.

Copy from here down.

---

**Mise, a meal planner and grocery list**

You will get an email from TestFlight. Install the TestFlight app from the App
Store first, then open the email on your phone and tap View in TestFlight.

Once Mise is installed, one of you sets up sharing and the other joins.

**One of you, first:**

1. Open Mise, tap the gear on the Plan tab
2. Create an account with your email
3. Tap **Start sharing**
4. Send the invite code to the other person

**The other one, after that:**

1. Open Mise, tap the gear on the Plan tab
2. Create an account with **your own** email, not the same one
3. Tap **Join another household** and paste the code you were sent
4. Tap **Sync now**

From then on the week, the grocery list, the pantry and the recipes are
shared. Tick
something off in the shop and it ticks on the other phone within about half a
minute, or as soon as either of you opens the app.

**What is in it**

45 recipes to start with. Add your own from a link: Recipes tab, the plus at
the top left, paste a URL from almost any recipe site.

Plan the week on the Plan tab, then tap **Make the list**. It merges what the
recipes share, sorts it by aisle, and leaves out whatever your pantry says you
already have.

**Two things worth knowing**

Your data sits in a database on my account. Row level security means the app
cannot show my household's list to yours, but I own the project, so I could go
and read it if I wanted to. Saying so plainly rather than letting you assume
otherwise.

It only syncs while the app is open, being opened, or being closed. Nothing
moves between two phones that are both shut. If something you added has not
appeared, open the app on both and give it a moment.

---
