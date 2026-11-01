defmodule Firmos.SitesFixtures do
  @moduledoc """
  Test helpers for landing pages: valid site content as the AI returns it.
  Pair with `Firmos.PlansFixtures.expect_ai_reply/1` to answer a completion.
  """

  @doc "Landing page content in the JSON shape the AI is asked for (string keys)."
  def site_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "hero" => %{
          "headline" => "Świeży chleb na zakwasie pod Twoimi drzwiami",
          "subheadline" => "Rzemieślnicza piekarnia z Krakowa z poranną dostawą.",
          "cta_label" => "Zamów pieczywo"
        },
        "offer" => %{
          "title" => "Co pieczemy",
          "items" => [
            %{"name" => "Chleb na zakwasie", "description" => "Pieczony codziennie o świcie."},
            %{"name" => "Drożdżówki", "description" => "Z sezonowymi owocami."}
          ]
        },
        "pricing" => %{
          "title" => "Cennik",
          "items" => [
            %{"name" => "Bochenek", "price" => "14 zł", "note" => "800 g"},
            %{"name" => "Abonament tygodniowy", "price" => "79 zł", "note" => "Dostawa 6 dni"}
          ]
        },
        "contact" => %{
          "title" => "Zamów u nas",
          "text" => "Napisz do nas, a dostarczymy pieczywo jutro rano."
        }
      },
      overrides
    )
  end

  @doc "The site content as the raw text the AI completion returns."
  def site_json(overrides \\ %{}), do: overrides |> site_attrs() |> Jason.encode!()
end
