# Fixtures

Hand written stand ins for a raw Mealime export, shaped after the JSON described
in spec section 1a. They exist because the real API cannot be reached from a
build machine, and because a rescue script that has never been run end to end is
not a rescue script.

Once the real export has run, drop a couple of genuine (anonymized) responses in
here and point the pipeline test at them instead.
