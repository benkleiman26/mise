# The sync server

One Supabase project holds one household's records. Free tier is ample: this is
two phones and a few thousand small rows.

## Setting it up

1. <https://supabase.com/dashboard> → **New project**. Name it `mise`, pick a
   region near you, and save the database password somewhere.
2. **SQL Editor → New query**, paste the whole of [`schema.sql`](schema.sql),
   **Run**. It is safe to run again later.
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
