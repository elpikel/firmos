defmodule Firmos.CompaniesFixtures do
  @moduledoc """
  Test helpers for creating companies through the `Firmos.Companies` context.
  """

  alias Firmos.Accounts.Scope
  alias Firmos.Companies
  alias Firmos.Ideas

  def valid_idea_text, do: "Piekarnia rzemieślnicza w Krakowie z dostawą pieczywa na zamówienie."

  @doc "Creates an idea for the scope's owner and turns it into a company."
  def company_fixture(%Scope{} = scope, idea_text \\ valid_idea_text()) do
    {:ok, _idea} = Ideas.create_for_user(scope, %{text: idea_text})
    {:ok, company} = Companies.ensure_company_from_idea(scope)
    company
  end
end
