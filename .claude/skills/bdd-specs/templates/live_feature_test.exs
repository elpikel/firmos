# STORY-004 — Customer manages the cart in the browser
#
# BDD specification — ExUnit, LiveView level (FirmosWeb.ConnCase + Phoenix.LiveViewTest)
#
# Path: test/features/customer_manages_cart_in_browser_test.exs
# Run:  mix test test/features
#
# Structure (ExUnit has no nested describe):
#   Feature        -> this module, one per file, from a user story
#     Scenario     -> describe "Scenario: …"; `setup` arranges ALL its data,
#                     mounts the LiveView and performs the interaction
#       Specification -> test; EXACTLY ONE assertion per test
#
# This is the entry-point spec: it goes through the router (`live/2` on a
# verified route), not by calling handle_event/3 directly.
#
# Per AGENTS.md: assert on DOM IDs with has_element?/2, never on raw HTML
# or copy text. The IDs below (#cart-items, #add-item-form, …) are part of
# the design — the LiveView must render them.
#
# Pending: every Scenario carries `@describetag :skip` until implemented.
defmodule FirmosWeb.Features.CustomerManagesCartInBrowserTest do
  @moduledoc "Feature: a customer manages the cart in the browser"
  use FirmosWeb.ConnCase, async: true

  import Firmos.CartsFixtures
  import Phoenix.LiveViewTest

  # If the route needs a logged-in user (phx.gen.auth), arrange it in each
  # setup with `register_and_log_in_user/1` from ConnCase:
  #   setup :register_and_log_in_user

  # ---------------------------------------------------------------------
  # HAPPY PATH — exhaustive success outcomes, first.
  # ---------------------------------------------------------------------

  describe "Scenario: viewing an empty cart" do
    @describetag :skip

    setup %{conn: conn} do
      cart = cart_fixture()
      {:ok, view, _html} = live(conn, ~p"/carts/#{cart}")

      %{view: view}
    end

    test "shows the empty-state message", %{view: view} do
      assert has_element?(view, "#cart-empty")
    end

    test "renders the add-item form", %{view: view} do
      assert has_element?(view, "#add-item-form")
    end
  end

  describe "Scenario: adding an item through the form" do
    @describetag :skip

    setup %{conn: conn} do
      cart = cart_fixture()
      {:ok, view, _html} = live(conn, ~p"/carts/#{cart}")

      view
      |> form("#add-item-form", item: %{sku: "widget", quantity: 2})
      |> render_submit()

      %{view: view}
    end

    test "lists the new line item", %{view: view} do
      assert has_element?(view, "#cart-items [data-sku='widget']")
    end

    test "shows the updated total", %{view: view} do
      assert has_element?(view, "#cart-total", "10.00")
    end

    test "hides the empty-state message", %{view: view} do
      refute has_element?(view, "#cart-empty")
    end
  end

  describe "Scenario: removing an item" do
    @describetag :skip

    setup %{conn: conn} do
      cart = cart_fixture()
      item = item_fixture(cart, %{sku: "widget", quantity: 1})
      {:ok, view, _html} = live(conn, ~p"/carts/#{cart}")

      view |> element("#remove-item-#{item.id}") |> render_click()

      %{view: view, item: item}
    end

    test "drops the line from the list", %{view: view, item: item} do
      refute has_element?(view, "#items-#{item.id}")
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH — segregated. Each failure mode is its own Scenario.
  # ---------------------------------------------------------------------

  describe "Scenario: submitting a zero quantity" do
    @describetag :skip

    setup %{conn: conn} do
      cart = cart_fixture()
      {:ok, view, _html} = live(conn, ~p"/carts/#{cart}")

      view
      |> form("#add-item-form", item: %{sku: "widget", quantity: 0})
      |> render_submit()

      %{view: view}
    end

    test "shows a quantity error on the form", %{view: view} do
      # <.input> renders field errors as <p> inside the form
      assert has_element?(view, "#add-item-form p", "must be greater than 0")
    end

    test "does not add a line item", %{view: view} do
      refute has_element?(view, "#cart-items [data-sku='widget']")
    end
  end

  describe "Scenario: opening a cart that does not exist" do
    @describetag :skip

    # Nothing to arrange beyond ConnCase's `conn`; the missing id is the data.
    test "responds with not found", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/carts/0") end
    end
  end
end
