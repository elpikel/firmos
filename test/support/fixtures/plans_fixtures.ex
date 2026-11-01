defmodule Firmos.PlansFixtures do
  @moduledoc """
  Test helpers for AI business plans: a valid plan as the AI returns it, and
  a Mox expectation that answers the next completion with it.
  """

  @doc "A plan in the JSON shape the AI is asked for (string keys)."
  def plan_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "offer" => "Chleb na zakwasie i drożdżówki z dostawą rano.",
        "target_customer" => "Rodziny z Krakowa, które cenią świeże pieczywo.",
        "competitors" => ["Lajkonik", "Piekarnia Mojego Taty"],
        "pricing" => "Bochenek 14 zł, abonament tygodniowy 79 zł.",
        "channels" => ["Instagram", "Grupy sąsiedzkie na Facebooku"],
        "tasks_30_days" => [
          %{"when" => "Tydzień 1", "task" => "Upiec próbną partię i zebrać opinie."},
          %{"when" => "Tydzień 2", "task" => "Założyć profil na Instagramie."}
        ]
      },
      overrides
    )
  end

  @doc "The plan as the raw text the AI completion returns."
  def plan_json(overrides \\ %{}), do: overrides |> plan_attrs() |> Jason.encode!()

  @doc "Expects one AI completion and answers it with `reply`."
  def expect_ai_reply(reply) do
    Mox.expect(Firmos.AI.Mock, :complete, fn _prompt, _opts -> reply end)
  end
end
