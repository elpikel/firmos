defmodule FirmosWeb.SiteComponentsTest do
  use ExUnit.Case, async: true

  import Firmos.SitesFixtures
  import Phoenix.LiveViewTest

  alias Firmos.Sites.Content
  alias FirmosWeb.SiteComponents

  @script "<script>alert('xss')</script>"

  defp content(overrides \\ %{}, contact \\ %{}) do
    {:ok, content} = overrides |> site_json() |> Content.from_json(contact)
    content
  end

  defp render_landing(content, name \\ "Piekarnia") do
    (&SiteComponents.landing/1)
    |> render_component(content: content, name: name)
    |> LazyHTML.from_fragment()
  end

  defp query(document, selector), do: LazyHTML.query(document, selector)

  test "renders the four sections" do
    document = render_landing(content())

    for id <- ["#site-hero", "#site-offer", "#site-pricing", "#site-contact"] do
      refute Enum.empty?(query(document, id)), "missing #{id}"
    end
  end

  test "the call to action links to the contact section" do
    assert content() |> render_landing() |> query("#site-cta") |> LazyHTML.attribute("href") ==
             ["#site-contact"]
  end

  test "escapes a script the AI put in a field" do
    hero = Map.put(site_attrs()["hero"], "headline", @script)
    document = render_landing(content(%{"hero" => hero}), @script)

    assert Enum.empty?(query(document, "script"))
    assert document |> query("#site-hero h1") |> LazyHTML.text() =~ @script
  end

  test "links a valid email and phone" do
    document =
      render_landing(
        content(%{}, %{"email" => "kontakt@piekarnia.pl", "phone" => "+48 600 100 200"})
      )

    assert document |> query("#site-contact-email a") |> LazyHTML.attribute("href") ==
             ["mailto:kontakt@piekarnia.pl"]

    assert document |> query("#site-contact-phone a") |> LazyHTML.attribute("href") ==
             ["tel:+48600100200"]
  end

  test "shows an invalid email as plain text, without a link" do
    document = render_landing(content(%{}, %{"email" => "javascript:alert(1)//@x.pl"}))

    assert Enum.empty?(query(document, "#site-contact-email a"))
    assert document |> query("#site-contact-email") |> LazyHTML.text() =~ "javascript:alert(1)"
  end
end
