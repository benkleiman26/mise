# The sync server

One Supabase project holds one household's records. This is two phones and a
few thousand small rows, so the free tier is ample.

Every table, index and function is prefixed `mise_`, so it does **not** need a
project of its own. Free plans allow two projects per organisation, and sharing
a database with an unrelated app is fine here: the names cannot collide and row
level security means neither app can read the other's rows.

## Setting it up

1. Use a project you already have, or make a new one at
   <https://supabase.com/dashboard>. If you are out of free projects, either
   reuse one, or create a second **organisation**, which gets its own free
   allowance.
2. **SQL Editor → New query**, paste the whole of [`schema.sql`](schema.sql),
   **Run**. It is safe to run again later, and safe to run in a project that is
   already being used.
3. **Project Settings → API**. You need the **Project URL** and the
   **anon public** key.
4. Put them in `Secrets.xcconfig` at the repository root, which git ignores:

   ```
   SUPABASE_URL = https:/$()/abcdefgh.supabase.co
   SUPABASE_ANON_KEY = eyJhbGciOi...
   ```

   The `/$()/` is not a typo. Xcode config files treat `//` as a comment, and
   that is the standard way to write a url in one.

## Why the schema looks like this

**One table for everything, with the fields as JSON.** The two phones in a
household will not be running the same version of the app. A column per field
would mean a migration every time the app learns a new field, and an older
phone refusing a row it could have mostly understood. Postgres here is holding
records for one household, not answering questions about them.

**The server's clock decides the cursor.** Devices page through changes by
`server_at`, not by when the phone thought the edit happened. Two phones'
clocks disagree, sometimes by minutes, and a cursor taken from the wrong clock
loses changes without anything looking wrong.

**Deletions are their own table.** The absence of a row is not information. A
meal deleted on one phone would otherwise come back the next time the other
phone pushed its copy.

**Pushes refuse to go backwards.** Both upserts only overwrite when the
incoming record is newer, so a push can be retried safely and two phones
pushing out of order cannot leave the older copy on top.

**Row level security is not optional.** The anon key ships inside the app, so
without these policies every signed in user of every Supabase project could
read this household's recipes.
