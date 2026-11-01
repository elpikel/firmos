defmodule Firmos.Sites.Version do
  @moduledoc """
  One immutable version of a site's content, numbered per site.

  Versions are only ever inserted: a generation, an edit (STORY-009) or an
  undo (STORY-010) adds version n+1 with its `source`, and the site's
  pointers move. Every field is set by `Firmos.Sites`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Sites.Content
  alias Firmos.Sites.Site

  @type source :: :generated | :edited | :undo

  @type t :: %__MODULE__{
          id: integer() | nil,
          site_id: integer() | nil,
          site: Site.t() | Ecto.Association.NotLoaded.t() | nil,
          number: pos_integer() | nil,
          content: Content.t() | nil,
          source: source() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "site_versions" do
    field :number, :integer
    embeds_one :content, Content, on_replace: :update
    field :source, Ecto.Enum, values: [:generated, :edited, :undo]

    belongs_to :site, Site

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Version `number` of `site_id` with `content`, made by `source`."
  @spec new_changeset(integer(), pos_integer(), Content.t(), source()) :: Ecto.Changeset.t()
  def new_changeset(site_id, number, %Content{} = content, source) do
    %__MODULE__{}
    |> change(site_id: site_id, number: number, source: source)
    |> put_embed(:content, content)
    |> validate_required([:site_id, :number, :content, :source])
    |> validate_number(:number, greater_than: 0)
    |> foreign_key_constraint(:site_id)
    |> unique_constraint(:number, name: :site_versions_site_id_number_index)
    |> check_constraint(:number, name: :site_versions_number_positive)
    |> check_constraint(:content, name: :site_versions_content_object)
  end
end
