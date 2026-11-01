defmodule Firmos.Sites.ContentTest do
  use ExUnit.Case, async: true

  import Firmos.SitesFixtures

  alias Firmos.Sites.Content
  alias Firmos.Sites.Content.Contact

  describe "from_json/2" do
    test "decodes every section" do
      assert {:ok, %Content{hero: hero, offer: offer, pricing: pricing, contact: contact}} =
               Content.from_json(site_json())

      assert hero.cta_label == "Zamów pieczywo"
      assert length(offer.items) == 2
      assert hd(pricing.items).note == "800 g"
      assert contact.title == "Zamów u nas"
    end

    test "tolerates a Markdown code fence" do
      assert {:ok, %Content{}} = Content.from_json("```json\n" <> site_json() <> "\n```")
    end

    test "replaces the contact fields with the given details" do
      assert {:ok, %{contact: %{email: "a@b.pl", phone: nil}}} =
               Content.from_json(
                 site_json(%{"contact" => %{"title" => "K", "text" => "T", "phone" => "1"}}),
                 %{"email" => "a@b.pl", "phone" => nil}
               )
    end

    test "rejects text that isn't a JSON object" do
      assert {:error, :invalid_json} = Content.from_json("[1, 2]")
      assert {:error, :invalid_json} = Content.from_json("nie JSON")
    end

    for section <- ["hero", "offer", "pricing", "contact"] do
      test "rejects a missing #{section} section" do
        json = site_attrs() |> Map.delete(unquote(section)) |> Jason.encode!()
        assert {:error, :invalid_shape} = Content.from_json(json)
      end
    end

    test "rejects a section of the wrong type" do
      assert {:error, :invalid_shape} = Content.from_json(site_json(%{"pricing" => "79 zł"}))
    end

    test "rejects a blank required field" do
      hero = Map.put(site_attrs()["hero"], "headline", "   ")
      assert {:error, :invalid_shape} = Content.from_json(site_json(%{"hero" => hero}))
    end

    test "rejects a too long field" do
      hero = Map.put(site_attrs()["hero"], "headline", String.duplicate("a", 121))
      assert {:error, :invalid_shape} = Content.from_json(site_json(%{"hero" => hero}))
    end

    test "rejects an empty item list" do
      offer = %{"title" => "Oferta", "items" => []}
      assert {:error, :invalid_shape} = Content.from_json(site_json(%{"offer" => offer}))
    end
  end

  describe "Contact.mailto/1" do
    test "links a plain address" do
      assert Contact.mailto("kontakt@piekarnia.pl") == "mailto:kontakt@piekarnia.pl"
    end

    test "refuses anything that could add headers or another scheme" do
      for email <- [
            "a@b.pl?bcc=x@y.pl",
            "a b@c.pl",
            "javascript:alert(1)",
            "<a@b.pl>",
            "a@b",
            nil
          ] do
        assert Contact.mailto(email) == nil, "expected no link for #{inspect(email)}"
      end
    end
  end

  describe "Contact.tel/1" do
    test "links a phone number with digits and a leading + only" do
      assert Contact.tel("+48 600 100 200") == "tel:+48600100200"
    end

    test "refuses anything that isn't a phone number" do
      for phone <- ["javascript:alert(1)", "zadzwoń", "12", nil] do
        assert Contact.tel(phone) == nil, "expected no link for #{inspect(phone)}"
      end
    end
  end
end
