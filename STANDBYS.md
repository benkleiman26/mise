# Standbys

What to have in the house so that a busy night ends in dinner rather than a
takeout order.

The household is four people. Two eat fish but not meat, two eat everything,
nobody has an allergy. That split decides more than it looks like it does:
make fish the default protein and meat an add-on that sits in its own bowl, and
almost nothing has to be cooked twice.

The other thing that decides the shape of this is that the children will eat
well from a table of components and badly from a plate someone else composed.
So the best standbys are assembled rather than served. Abendbrot is the model:
everything goes on the table, everyone takes what they want, nobody negotiates.

## Three layers, separated by when the work happened

The reason a weeknight fails is almost never that the cooking was too hard. It
is that the work needed to happen earlier and did not. So these are organised
by when the effort is spent, not by what the food is.

### Layer 1: the fire shelf

Work done months ago. The test for anything on this list: it combines into a
dinner with nothing fresh in the house.

Dried pasta, long and short. Rice, short grain and basmati. Tinned tomatoes.
Tinned tuna and sardines. Tinned chickpeas, cannellini and black beans. Red
lentils. Coconut milk. Good olive oil. Anchovies, which melt invisibly into
things and do more work per jar than anything else here. Parmesan, which keeps
for weeks. Garlic, onions, lemons. Soy sauce, fish sauce, tahini, peanut
butter. Chili flakes, cumin, smoked paprika, curry powder. Stock paste. Jarred
olives, capers, pickles, harissa and a tomato sauce worth eating.

The freezer counts as pantry: peas, spinach, corn, edamame, a spare loaf,
tortillas, dumplings.

### Layer 2: the standing fridge order

Work done at the shop. This is what makes an assembled dinner possible on no
notice, and it is the layer that quietly fails, because none of it is a meal
and so none of it ever makes the list.

Good bread. Butter. One hard cheese and one soft. Cucumbers, radishes,
tomatoes, carrots. Eggs. Hummus. Pickles or cornichons. Olives. Pita. Cold
cuts, which stay on their own plate. Scallions or a herb.

### Layer 3: Sunday prep that is never wrong

Five things, not a rotating menu. They are always a good idea because
everything above and below them is built out of them.

A pot of grains. Six hard boiled eggs. A pot of something legume: dal,
chickpeas or white beans. A sheet pan of roasted vegetables. A jar of sauce:
tahini and lemon, a peanut sauce, or a sharp vinaigrette.

Those five make grain bowls, fill pita, go on toast, sit on the board, and turn
a tin of tuna into dinner. Then one actual dish on top of them for the week:
dal, a soup, a baked pasta, a frittata.

## The twelve

**Cook ahead, eat on the busy night.** The criterion is not speed, it is that
it keeps for days and is as good or better on day three. Cooked fish reheats
badly, so this half leans legume, egg and dairy, which makes it pescatarian by
default anyway.

1. Red lentil dal. Better on day two, holds five days, freezes.
2. Frittata. Genuinely good cold, holds four days, and anyone can eat around
   whatever is in it.
3. Chana masala, or a coconut chickpea curry.
4. White bean and kale soup, or minestrone.
5. Baked pasta, assembled ahead and baked when wanted.
6. Shakshuka base. The sauce keeps a week; eggs go in fresh in eight minutes.

**Assembled, nothing to cook.** Four variations on one habit rather than four
unrelated meals.

7. Abendbrot. Bread, butter, cheese, cucumber, radishes, pickles, boiled eggs,
   cold cuts on their own plate.
8. Meze. Hummus, labneh, feta, olives, tomato, pita.
9. Grain bowl, built from the Sunday prep.
10. Nicoise plate. Boiled eggs, green beans, potatoes, olives, tomatoes, and
    tuna as one bowl among six.

**Nothing fresh in the house.** Layer 1 proving itself.

11. Pasta aglio e olio.
12. Rice with a fried egg and furikake.

With pasta with tomato and tuna, and white beans on toast, as the two obvious
extensions of the same shelf.

### On tinned fish

One of us likes it and the rest do not, which makes a tinned fish board a meal
for one. Tuna is the way in, as long as it never arrives announced as tuna. The
nicoise plate puts it on the table as one component among six. A tuna melt is
really a grilled cheese. Tuna with white beans, lemon, olive oil and parsley
eats cold and keeps, so it doubles as a make ahead. That is three points of
contact a week without a tin ever reaching the table.

## What this asks of the app

Layers 1 and 2 are not recipes. They are the `isStaple` flag in
`Mise/Resources/canonical_items.json`, which is what keeps something on the
grocery list whether or not a meal called for it.

Today 89 items carry that flag and they are almost entirely spices, condiments
and baking. Nothing in layer 1 or layer 2 is marked: not the tinned tuna, not
the bread, not the eggs on the board, not the cucumbers. The fire shelf is a
list of staples that the app does not yet think are staples.

Nearly everything named here is already in the catalogue, under its own name or
an alias. Five are missing and would need adding: sardines, cornichons, hummus,
furikake and dumplings.
