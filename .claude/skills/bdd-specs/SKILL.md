---
name: bdd-specs
description: >-
  Behavior-driven design: write executable specifications BEFORE any
  implementation code. Reads /docs/PLAN.md for the build plan and
  /docs/STORIES.md for user stories, and stops to ask for either if it is
  missing. Generates ExUnit feature tests shaped Feature > Scenario >
  Specification — one test module per Feature, a `describe "Scenario: …"`
  per acceptance criterion whose `setup` arranges all of its data, and a
  `test` per outcome with exactly one assertion; happy-path scenarios first
  and exhaustively, sad-path scenarios in their own describes. Generated
  specs are pending (`@tag :skip`) until implemented. Uses `Firmos.DataCase`
  for context-level features and `FirmosWeb.ConnCase` + Phoenix.LiveViewTest
  for LiveView features. Use when starting a new project or feature, when
  asked to "spec out", "write the tests first", do BDD/TDD, or turn a plan
  or user stories into a test suite. Ships PLAN.md and STORIES.md scaffolds
  plus ready-to-copy ExUnit context and LiveView feature templates.
---

# Behavior-Driven Design — Specifications First

Specifications are written **before** implementation. The spec is the
design artifact: it encodes the intended behavior from the plan and the
user stories, fails first, and is the definition of done. Do not write
implementation code under this skill until the specs exist and the user
has seen them.

## 🎯 Why: Design for Change

The goal of writing software is to be able to **change it safely**. Specs
are the safety net that makes change possible — without them, every edit
is a guess. One assertion per Specification means a failing spec names
exactly what broke; happy/sad-path separation means you can change one
behavior without re-reading the whole suite. The spec suite *is* the
change-budget for the codebase.

## The non-negotiable workflow

Run these gates **in order**. Do not skip ahead.

### 1. Require the plan

Look for the build plan at `/docs/PLAN.md` (also accept
`docs/PLAN.md`, `PLAN.md`, or an obvious `docs/plan.*`).

- **If it is missing:** stop. Ask the user to provide a `PLAN.md` in
  `/docs`. Offer to scaffold one from `templates/PLAN.md` and let them
  fill it in, or to draft it from their description and write it to
  `/docs/PLAN.md` for approval. Do not proceed to specs without an
  approved plan.
- **If it exists:** read it fully. It defines the features and the
  technical boundaries the specs must cover.

### 2. Require the user stories

Look for user stories at `/docs/STORIES.md` (also accept
`docs/STORIES.md`, `STORIES.md`).

- **If it is missing:** stop. Ask the user for the user stories. Offer
  to scaffold `templates/STORIES.md`, or to derive draft stories from
  `PLAN.md` and write them to `/docs/STORIES.md` for approval. Do not
  proceed without stories — they are the source of every Scenario.
- **If it exists:** read it fully. Each story maps to one Feature; each
  acceptance criterion / "so that" outcome maps to a Scenario.

### 3. Pick the case template per feature

The runner is always ExUnit (`mix test`). Choose the case per feature:

- **`use Firmos.DataCase, async: true`** — the feature is a domain
  behavior exercised through a context's public API (`Firmos.Carts`).
- **`use FirmosWeb.ConnCase, async: true`** + `import
  Phoenix.LiveViewTest` — the feature is user-facing through a LiveView
  or controller. Drive it with `live/2`, `element/2`, `render_click/1`,
  `render_submit/2`, and assert with `has_element?/2` on DOM IDs
  (AGENTS.md "LiveView tests").

Test data comes from context fixture modules (`Firmos.CartsFixtures`,
the `mix phx.gen.*` pattern in `test/support/fixtures/`). ExMachina is
optional — use `insert(:cart)` only if it is already in `mix.exs`.

### 4. Generate the specs

For every story, produce a spec file built from the templates. Map
stories to features 1:1, write the file, then stop and let the user
review before any implementation. Run them with `mix test test/features`
— every new spec must show up as **skipped**.

## The spec structure (mandatory shape)

ExUnit has **no nested `describe`**, so the hierarchy maps to:
**Feature → test module (one per file) · Scenario → `describe` ·
Specification → `test`**.

```elixir
# STORY-003 — Customer builds a shopping cart
defmodule Firmos.Features.CustomerBuildsAShoppingCartTest do
  @moduledoc "Feature: a customer builds a shopping cart"
  use Firmos.DataCase, async: true

  import Firmos.CartsFixtures

  alias Firmos.Carts

  describe "Scenario: adding two widgets to an empty cart" do
    @describetag :skip

    # Arrange ALL data this scenario needs, here, and return it in context:
    setup do
      cart = cart_fixture()
      {:ok, _} = Carts.add_item(cart, %{sku: "widget", unit_price: 500, quantity: 2})
      %{cart: Carts.get_cart!(cart.id)}
    end

    # Specification = one `test` = exactly ONE assertion:
    test "has one line item", %{cart: cart} do
      assert length(cart.items) == 1
    end

    test "totals the cart", %{cart: cart} do
      assert Carts.total(cart) == 1000
    end
  end
end
```

Hard rules — every generated file must obey all of them:

1. **Feature** is the test module: `Firmos.Features.<Name>Test` (web:
   `FirmosWeb.Features.<Name>Test`) with `@moduledoc "Feature: …"` — a
   short human-readable name, **no story id**. One feature per file,
   sourced from a user story. File name is a readable snake_case slug
   under `test/features/`, also without an id prefix (e.g.
   `test/features/atomic_create_user_order_entitlements_test.exs`).
   The story id lives only in one comment on the first line
   (`# STORY-007 — Atomic create of user, order, entitlements`).
2. **Scenario** is a `describe "Scenario: …"`. Every Scenario arranges
   **all** of its data in its own `setup` block and returns it in the
   context map. No arrange logic inside `test` bodies. (`setup` runs
   before each test — that is what keeps specs isolated in the SQL
   sandbox; `setup_all` is module-wide and cannot touch the sandbox, so
   don't use it for data.)
3. **Specification** is a `test`. **Exactly one assertion per test.**
   A single `assert`/`refute`/`assert_raise`/`assert_receive`; a match
   assertion like `assert {:error, %Ecto.Changeset{}} = result` counts as
   one. No `Enum.each` of asserts. Need another assertion → another test.
4. **Happy path first, and exhaustive.** Cover every success outcome
   the story implies before any failure case.
5. **Sad path is segregated.** Error, validation, and edge-case specs go
   in their own `describe "Scenario: rejecting …"` blocks, placed after
   all happy-path describes — never interleaved.
6. **Pending by default.** Generated specs carry `@describetag :skip`
   per Scenario (or `@tag :skip` per test) so ExUnit reports them as
   skipped. They must not accidentally pass; the builder removes the tag
   when it implements the behavior. Don't pattern-match on structs that
   don't exist yet (`%Firmos.Carts.Cart{}` fails compilation) — match on
   tuples/maps or field values instead.
7. **At least one Scenario per Feature exercises the real entry point.**
   For domain features that is the context's public function, never a
   schema or internal module. For user-facing features it is the routed
   LiveView/controller via `live(conn, ~p"/...")` — not calling
   `handle_event/3` directly. Replace external services with Mox mocks of
   their behaviour (`elixir-best-practices` idioms §14), never by
   stubbing internals. Unit-level tests are fine *in addition*, never
   *instead*.
8. **Follow AGENTS.md test rules**: assert on element IDs with
   `has_element?/2`, not raw HTML; no `Process.sleep/1`;
   `start_supervised!/1` for processes; `errors_on/1` for changeset errors.

## Templates

Copy the file that matches the feature and adapt it — do not hand-write
the scaffold:

- `templates/feature_test.exs` — context-level feature (`Firmos.DataCase`),
  full Feature/Scenario/Specification shape with happy + segregated sad
  paths.
- `templates/live_feature_test.exs` — LiveView feature (`FirmosWeb.ConnCase`
  + `Phoenix.LiveViewTest`), same shape, asserting on DOM IDs.
- `templates/PLAN.md` — build-plan scaffold to hand the user when
  `/docs/PLAN.md` is missing.
- `templates/STORIES.md` — user-story scaffold (story + acceptance
  criteria) to hand the user when `/docs/STORIES.md` is missing.

See `references/workflow.md` for the story→feature→scenario mapping
worked through end to end, and the exhaustiveness checklist.
