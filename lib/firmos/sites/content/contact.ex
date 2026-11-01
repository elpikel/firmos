defmodule Firmos.Sites.Content.Contact do
  @moduledoc """
  The contact section: a title, a short invitation and the business's
  email, phone and city (each optional).

  Stored email and phone are plain text. They become `mailto:` / `tel:` links
  only through `mailto/1` and `tel/1`, which return `nil` for anything that
  isn't a plain address or number, so no stored value can smuggle in another
  URL scheme or extra mail headers.
  """
  use Ecto.Schema

  alias Firmos.Sites.Content.Text

  @limits %{title: 80, text: 1_000, email: 160, phone: 40, city: 160}

  # Deliberately narrower than RFC 5322: no quotes, spaces, `?`, `&` or `%`,
  # so the address can go into a mailto: URL as it is.
  @email_format ~r/\A[A-Za-z0-9._+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\z/
  @phone_format ~r/\A\+?[0-9][0-9 ()-]{5,24}\z/

  @type t :: %__MODULE__{
          title: String.t() | nil,
          text: String.t() | nil,
          email: String.t() | nil,
          phone: String.t() | nil,
          city: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :title, :string
    field :text, :string
    field :email, :string
    field :phone, :string
    field :city, :string
  end

  @doc "Validates the contact section as decoded from JSON."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs), do: Text.cast_text(contact, attrs, @limits, [:title, :text])

  @doc """
  The owner's edit: the title and text only. The email, phone and city come
  from the company profile and are never cast from the form.
  """
  @spec edit_changeset(t(), map()) :: Ecto.Changeset.t()
  def edit_changeset(contact, attrs),
    do: Text.cast_text(contact, attrs, Map.take(@limits, [:title, :text]), [:title, :text])

  @doc "A `mailto:` URL for a plain email address, else `nil`."
  @spec mailto(String.t() | nil) :: String.t() | nil
  def mailto(email) when is_binary(email) do
    if email =~ @email_format, do: "mailto:" <> email
  end

  def mailto(_none), do: nil

  @doc "A `tel:` URL (digits and a leading `+` only) for a plain phone number, else `nil`."
  @spec tel(String.t() | nil) :: String.t() | nil
  def tel(phone) when is_binary(phone) do
    if phone =~ @phone_format, do: "tel:" <> String.replace(phone, ~r/[^0-9+]/, "")
  end

  def tel(_none), do: nil
end
