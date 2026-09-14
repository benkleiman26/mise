# Spec

The build spec for Mise lives in a Google Doc and that document is the single
source of truth:

<https://docs.google.com/document/d/11xXFBZrQxdpB-XnxpqPGV71n2Sxlkd2PdANPpr2aov0/edit>

It is not mirrored here on purpose. It is still being edited, and a copy in the
repository would quietly go stale and start contradicting the original. Read the
document before starting work.

## Orientation

Section numbers referred to in commit messages and code comments:

| Section | Subject |
| --- | --- |
| 0 | Vision and positioning. Store neutral, bring your own recipes. |
| 1a | What Mealime does today, and where it falls short. |
| 2 | Principles to apply when the spec does not cover a decision. |
| 3 | Stack. iOS 17+, SwiftUI, SwiftData local, Supabase backend. |
| 4 | Domain model. |
| 5.1 | Recipe library, collections, tags, smart lists. |
| 5.3 | Grocery list generation rules. This is the hero feature. |
| 5.6a | NYT Cooking import, share extension, bulk URL import. |
| 5.7 | Mealime migration, public and owner specific. |
| 8 | Project structure. |
| 9 | Build plan and phase checkpoints. |
| 11 | Conventions, including no em dashes anywhere. |
| 12 | What the owner still needs to provide, per phase. |

## House rules worth repeating

- No em dashes in UI copy, comments, docs, or commit messages.
- Stop at each phase checkpoint and wait for review.
- Decisions the spec does not cover go in `DECISIONS.md`, and work continues.
- Known gaps go in `TODO.md`.
