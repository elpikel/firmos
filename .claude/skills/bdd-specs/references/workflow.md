# Story → Feature → Scenario → Specification, worked through

This is the mapping the skill applies. Read it before generating specs.

## The mapping

| Source artifact                         | Spec construct                    |
|-----------------------------------------|-----------------------------------|
| A user story in `STORIES.md`            | One test module (`@moduledoc "Feature: …"`) per file |
| An acceptance criterion of that story   | One `describe "Scenario: …"`      |
| The "then …" of a criterion             | One `test "…"` with ONE `assert`  |
| All "given …" + "when …" for a criterion | The Scenario's `setup` block, returned in context |
| A failure / edge "then"                 | A `test` in a *separate* sad-path Scenario |

## Worked example

Story from `/docs/STORIES.md`:

> **As a** customer
> **I want** to add items to a cart
> **So that** I can buy several things at once
>
> - Given an empty cart, when I add 2 widgets at $5, then the cart has 1
>   line item, the line totals $10, and the cart totals $10.
> - Given a cart with 1 widget, when I add 2 more widgets, then the cart
>   still has 1 line item and the quantity is 3.
> - Given an empty cart, when I add an item with quantity 0, then it is
>   rejected with a validation error on quantity.

Becomes:

`test/features/customer_builds_a_shopping_cart_test.exs`:

- `# STORY-003 — Customer builds a shopping cart` (first line, only id)
- `defmodule Firmos.Features.CustomerBuildsAShoppingCartTest`,
  `@moduledoc "Feature: a customer builds a shopping cart"` (the story)
  - `describe "Scenario: adding two widgets to an empty cart"` (criterion 1)
    - `setup`: `cart_fixture()`, add 2 widgets at 500 cents, reload →
      `%{cart: cart}`
    - `test "has one line item"` — 1 assertion
    - `test "totals the line at 1000"` — 1 assertion
    - `test "totals the cart at 1000"` — 1 assertion
  - `describe "Scenario: adding more of an existing item"` (criterion 2)
    - `setup`: cart with 1 widget, add 2 more, reload → `%{cart: cart}`
    - `test "still has one line item"` — 1 assertion
    - `test "has quantity three"` — 1 assertion
  - `describe "Scenario: rejecting a zero quantity"` (criterion 3 — SAD,
    separate describe, after all happy paths)
    - `setup`: call `Carts.add_item/2` with quantity 0 → `%{result: result}`
    - `test "returns an error changeset"` — 1 assertion
    - `test "explains the quantity must be positive"` — 1 assertion

Note how one criterion with three "then" clauses became three `test`s,
not one `test` with three `assert`s. That is the one-assertion rule.
Note too that the **action** ("when") happens in `setup`, and the
outcome is passed to the tests through the context — tests only assert.
Each Scenario starts `@describetag :skip` (pending) until implemented.

## Exhaustiveness checklist (happy path)

Before declaring the happy path done, confirm a Scenario exists for:

- The nominal/typical case.
- Each boundary the domain model allows (empty, single, many, max).
- Each distinct success *outcome* the story's "so that" implies.
- Idempotent / repeated actions, if the domain supports them.
- Each query/derived value the feature exposes (one `test` each).
- For LiveView features: each visible outcome (element present, flash,
  navigation) asserted by DOM ID, one `test` each.

## Sad-path checklist (segregated blocks)

A separate Scenario for each:

- Each invariant in `PLAN.md`'s domain model that can be violated.
- Each validation rule (type, range, required, format).
- Each documented error / rejection in the story's failure cases.
- Conflict / not-found / unauthorized states, where applicable
  (another user's `current_scope`, missing record → 404).

## Ordering rule

Within a Feature module: every happy-path `describe` first, then every sad-path
Scenario. Never interleave. A reader scanning top-to-bottom should see
the intended behavior fully before seeing how it fails.

## Stop point

After generating the spec files, stop. Present them for review. Do not
write implementation code until the user approves the specs — the specs
are the design. `mix test test/features` must report them as skipped;
once the builder removes `:skip` they are expected to fail first (red).
