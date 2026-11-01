# STORY-002 — Polish UI
#
# Entry point: `GET /` through the router (PageController + root layout),
# and the `FirmosWeb.Gettext` backend for the fallback behaviour.
# Copy text is asserted here on purpose: the language IS the behaviour.
defmodule FirmosWeb.Features.PolishUiTest do
  @moduledoc "Feature: the owner uses the whole interface in Polish"
  use FirmosWeb.ConnCase, async: true

  defp text_of(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
  end

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — a visitor opens the home page" do
    setup %{conn: conn} do
      document =
        conn
        |> get(~p"/")
        |> html_response(200)
        |> LazyHTML.from_document()

      %{document: document}
    end

    test "declares the page language as Polish", %{document: document} do
      assert document |> LazyHTML.query("html") |> LazyHTML.attribute("lang") == ["pl"]
    end

    test "renders the headline in Polish", %{document: document} do
      assert text_of(document, "#home-hero h1") =~ "Zespół AI, który prowadzi Twoją małą firmę"
    end

    test "renders the navigation in Polish", %{document: document} do
      assert text_of(document, "#auth-nav") =~ "Zaloguj się"
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC2 — rendering a message with no Polish translation" do
    setup do
      plain = Gettext.gettext(FirmosWeb.Gettext, "This sentence has no Polish translation")

      interpolated =
        Gettext.gettext(FirmosWeb.Gettext, "Untranslated greeting for %{name}", name: "Ada")

      %{plain: plain, interpolated: interpolated, locale: Gettext.get_locale(FirmosWeb.Gettext)}
    end

    test "is rendered under the Polish locale", %{locale: locale} do
      assert locale == "pl"
    end

    test "shows the English source string", %{plain: plain} do
      assert plain == "This sentence has no Polish translation"
    end

    test "still interpolates bindings into the English source", %{interpolated: interpolated} do
      assert interpolated == "Untranslated greeting for Ada"
    end
  end
end
