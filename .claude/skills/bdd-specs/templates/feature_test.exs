# STORY-003 — Customer builds a shopping cart
#
# BDD specification — ExUnit, context level (Firmos.DataCase)
#
# Path: test/features/customer_builds_a_shopping_cart_test.exs
# Run:  mix test test/features
#
# Structure (ExUnit has no nested describe):
#   Feature        -> this module, one per file, from a user story
#     Scenario     -> describe "Scenario: …"; `setup` arranges ALL its data
#                     (and performs the action), returning it in context
#       Specification -> test; EXACTLY ONE assertion per test
#
# Happy-path scenarios first and exhaustive.
# Sad-path scenarios in their OWN separate describes, below.
#
# Pending: every Scenario carries `@describetag :skip`. The builder removes
# it when implementing; the spec must then fail first (red).
#
# `Firmos.Carts` and `Firmos.CartsFixtures` do not need to exist yet — these
# specs are the design. Don't pattern-match on structs that don't exist yet
# (`%Firmos.Carts.Cart{}` would fail compilation); match tuples/maps instead.
defmodule Firmos.Features.CustomerBuildsAShoppingCartTest do
  @moduledoc "Feature: a customer builds a shopping cart"
  use Firmos.DataCase, async: true

  # Fixture module in test/support/fixtures/carts_fixtures.ex (phx.gen style).
  # With ExMachina installed, `insert(:cart)` is an acceptable alternative.
  import Firmos.CartsFixtures

  alias Firmos.Carts

  # ---------------------------------------------------------------------
  # HAPPY PATH — exhaustive success outcomes, first.
  # ---------------------------------------------------------------------

  describe "Scenario: adding two distinct items" do
    @describetag :skip

    # Arrange everything this scenario needs, here.
    setup do
      cart = cart_fixture()
      {:ok, _} = Carts.add_item(cart, %{sku: "widget", unit_price: 500, quantity: 2})
      {:ok, _} = Carts.add_item(cart, %{sku: "gadget", unit_price: 1000, quantity: 1})

      %{cart: Carts.get_cart!(cart.id)}
    end

    test "holds two line items", %{cart: cart} do
      assert length(cart.items) == 2
    end

    test "sums the widget line", %{cart: cart} do
      assert Carts.line_total(cart, "widget") == 1000
    end

    test "sums the gadget line", %{cart: cart} do
      assert Carts.line_total(cart, "gadget") == 1000
    end

    test "totals the whole cart", %{cart: cart} do
      assert Carts.total(cart) == 2000
    end

    test "is not empty", %{cart: cart} do
      refute Carts.empty?(cart)
    end
  end

  describe "Scenario: adding the same SKU twice merges quantities" do
    @describetag :skip

    setup do
      cart = cart_fixture()
      {:ok, _} = Carts.add_item(cart, %{sku: "widget", unit_price: 500, quantity: 1})
      {:ok, _} = Carts.add_item(cart, %{sku: "widget", unit_price: 500, quantity: 3})

      %{cart: Carts.get_cart!(cart.id)}
    end

    test "keeps a single line item", %{cart: cart} do
      assert length(cart.items) == 1
    end

    test "accumulates the quantity", %{cart: cart} do
      assert Carts.quantity_of(cart, "widget") == 4
    end

    test "prices the merged quantity", %{cart: cart} do
      assert Carts.total(cart) == 2000
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH — segregated. Each failure mode is its own Scenario.
  # ---------------------------------------------------------------------

  describe "Scenario: rejecting a non-positive quantity" do
    @describetag :skip

    # The action happens in setup; tests only assert on its outcome.
    setup do
      cart = cart_fixture()
      %{result: Carts.add_item(cart, %{sku: "widget", unit_price: 500, quantity: 0})}
    end

    test "returns an error changeset", %{result: result} do
      assert {:error, %Ecto.Changeset{}} = result
    end

    test "explains the quantity must be positive", %{result: {:error, changeset}} do
      assert "must be greater than 0" in errors_on(changeset).quantity
    end
  end

  describe "Scenario: rejecting a negative unit price" do
    @describetag :skip

    setup do
      cart = cart_fixture()
      %{result: Carts.add_item(cart, %{sku: "widget", unit_price: -1, quantity: 1})}
    end

    test "explains the unit price cannot be negative", %{result: {:error, changeset}} do
      assert "must be greater than or equal to 0" in errors_on(changeset).unit_price
    end
  end

  describe "Scenario: adding to a cart that was already checked out" do
    @describetag :skip

    setup do
      cart = cart_fixture(%{status: :ordered})
      %{result: Carts.add_item(cart, %{sku: "widget", unit_price: 500, quantity: 1})}
    end

    test "is rejected as closed", %{result: result} do
      assert {:error, :cart_closed} = result
    end
  end
end
