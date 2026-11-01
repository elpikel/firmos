defmodule Firmos.Sites.Content do
  @moduledoc """
  The body of a landing page: hero, offer, pricing and contact sections,
  stored in the `site_versions.content` jsonb column.

  It is structured text only, never HTML or URLs: the page is rendered by
  `FirmosWeb.SiteComponents.landing/1`, which escapes every field.
  `from_json/2` is the one way in for AI output: it decodes the raw text and
  checks every section, so a version is never stored half-formed.
  `edit_changeset/2` is the one way in for the owner's edits (STORY-009).
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

  @sections [:hero, :offer, :pricing, :contact]

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

  @doc """
  The owner's edit of `content`: every text field except the contact
  email, phone and city, which come from the company profile. The params
  are merged onto the existing sections, so a section left out stays as it
  is; a list of items sent replaces the stored list.
  """
  @spec edit_changeset(t(), map()) :: Ecto.Changeset.t()
  def edit_changeset(%__MODULE__{} = content, attrs) when is_map(attrs) do
    changeset(content, attrs, &Contact.edit_changeset/2)
  end

  @doc """
  The `"section.field"` paths whose value differs between `old` and `new`
  (a list of items counts as one field), in section order.
  """
  @spec changed_paths(t(), t()) :: [String.t()]
  def changed_paths(%__MODULE__{} = old, %__MODULE__{} = new) do
    Enum.flat_map(@sections, fn section ->
      old
      |> Map.fetch!(section)
      |> changed_fields(Map.fetch!(new, section))
      |> Enum.map(&"#{section}.#{&1}")
    end)
  end

  defp changed_fields(%module{} = old, %module{} = new) do
    Enum.reject(module.__schema__(:fields), &(Map.fetch!(old, &1) == Map.fetch!(new, &1)))
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

  defp changeset(content, attrs, contact_changeset \\ &Contact.changeset/2) do
    content
    |> cast(attrs, [])
    |> cast_embed(:hero, required: true)
    |> cast_embed(:offer, required: true)
    |> cast_embed(:pricing, required: true)
    |> cast_embed(:contact, required: true, with: contact_changeset)
  end

  defp strip_code_fence(text) do
    text
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*(.*?)\s*```\z/s, "\\1")
  end
end
