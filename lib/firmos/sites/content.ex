defmodule Firmos.Sites.Content do
  @moduledoc """
  The body of a landing page: hero, offer, pricing and contact sections,
  stored in the `site_versions.content` jsonb column.

  It is structured text only, never HTML or URLs: the page is rendered by
  `FirmosWeb.SiteComponents.landing/1`, which escapes every field.
  `from_json/2` is the one way in for AI output: it decodes the raw text and
  checks every section, so a version is never stored half-formed.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Sites.Content.Contact
  alias Firmos.Sites.Content.Hero
  alias Firmos.Sites.Content.Offer
  alias Firmos.Sites.Content.Pricing

  @type t :: %__MODULE__{
          hero: Hero.t() | nil,
          offer: Offer.t() | nil,
          pricing: Pricing.t() | nil,
          contact: Contact.t() | nil
        }

  @typedoc """
  Contact fields that override whatever the AI wrote (string keys), e.g.
  `%{"email" => company.contact_email, "phone" => nil, "city" => company.city}`.
  """
  @type contact_details :: %{optional(String.t()) => String.t() | nil}

  @primary_key false
  embedded_schema do
    embeds_one :hero, Hero, on_replace: :update
    embeds_one :offer, Offer, on_replace: :update
    embeds_one :pricing, Pricing, on_replace: :update
    embeds_one :contact, Contact, on_replace: :update
  end

  @doc """
  Decodes the AI's reply into validated content, with `contact_details`
  replacing the contact fields of the same name.

  Tolerates a Markdown code fence around the JSON. Returns
  `{:error, :invalid_json}` when the text is not a JSON object and
  `{:error, :invalid_shape}` when a section is missing, empty, too long or
  of the wrong type.
  """
  @spec from_json(String.t(), contact_details()) ::
          {:ok, t()} | {:error, :invalid_json | :invalid_shape}
  def from_json(text, contact_details \\ %{}) when is_binary(text) and is_map(contact_details) do
    case text |> strip_code_fence() |> Jason.decode() do
      {:ok, %{} = attrs} -> attrs |> put_contact_details(contact_details) |> validate()
      _not_an_object -> {:error, :invalid_json}
    end
  end

  defp put_contact_details(%{"contact" => %{} = contact} = attrs, details),
    do: %{attrs | "contact" => Map.merge(contact, details)}

  defp put_contact_details(attrs, _details), do: attrs

  defp validate(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:validate)
    |> case do
      {:ok, content} -> {:ok, content}
      {:error, _changeset} -> {:error, :invalid_shape}
    end
  end

  defp changeset(content, attrs) do
    content
    |> cast(attrs, [])
    |> cast_embed(:hero, required: true)
    |> cast_embed(:offer, required: true)
    |> cast_embed(:pricing, required: true)
    |> cast_embed(:contact, required: true)
  end

  defp strip_code_fence(text) do
    text
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*(.*?)\s*```\z/s, "\\1")
  end
end
