defmodule FirmosWeb.ActivityComponents do
  @moduledoc """
  Renders activity log entries (`Firmos.Activity.Entry`).

  Entries store an `action` and structured `metadata`, never a sentence; the
  actor, action label and summary are rendered here through gettext, so the
  log follows the UI language. A new action needs a clause in
  `action_label/1` and `fallback_summary/1` (and in `summary/1` when its
  metadata has details); `test/firmos_web/components/activity_components_test.exs`
  fails until it has them.
  """
  use FirmosWeb, :html

  alias Firmos.Activity.Entry

  @site_actions [:site_generated, :site_updated, :site_published, :site_undone]

  @doc """
  One activity entry: actor, action, time and summary, with the optional
  `actions` (e.g. an undo button the page decides to offer) under it.
  """
  attr :id, :string, required: true
  attr :entry, Entry, required: true
  slot :actions

  def activity_entry(assigns) do
    ~H"""
    <article
      id={@id}
      class="group flex gap-4 rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm transition hover:border-zinc-300 hover:shadow-md"
    >
      <span class="flex size-10 shrink-0 items-center justify-center rounded-full bg-zinc-100 text-zinc-600 transition group-hover:bg-zinc-900 group-hover:text-white">
        <.icon name={actor_icon(@entry.actor)} class="size-5" />
      </span>
      <div class="min-w-0 flex-1 space-y-2">
        <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
          <p class="text-sm text-zinc-900">
            <span data-role="action" class="font-semibold">{action_label(@entry.action)}</span>
            <span class="text-zinc-400">·</span>
            <span data-role="actor" class="text-zinc-600">{actor_label(@entry.actor)}</span>
          </p>
          <time
            datetime={DateTime.to_iso8601(@entry.inserted_at)}
            class="text-xs tabular-nums text-zinc-500"
          >
            {format_timestamp(@entry.inserted_at)}
          </time>
        </div>
        <div data-role="summary" class="text-sm text-zinc-600">
          <.summary id={@id} entry={@entry} />
        </div>
        <div :if={@actions != []} class="flex flex-wrap items-center gap-2 pt-1">
          {render_slot(@actions)}
        </div>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :entry, Entry, required: true

  defp summary(%{entry: %Entry{action: :company_created, metadata: %{"name" => name}}} = assigns)
       when is_binary(name) do
    assigns = assign(assigns, :name, name)

    ~H"""
    <p>{gettext("Created the company “%{name}”.", name: @name)}</p>
    """
  end

  defp summary(
         %{entry: %Entry{action: :company_updated, metadata: %{"changes" => changes}}} = assigns
       )
       when is_map(changes) and map_size(changes) > 0 do
    assigns = assign(assigns, :changes, Enum.sort(changes))

    ~H"""
    <ul class="space-y-1">
      <li :for={{field, change} <- @changes} class="flex flex-wrap items-baseline gap-x-2">
        <span class="font-medium text-zinc-700">{field_label(field)}:</span>
        <span class="text-zinc-400 line-through decoration-zinc-300">
          {format_value(change["from"])}
        </span>
        <.icon name="hero-arrow-right" class="size-3 self-center text-zinc-400" />
        <span class="text-zinc-900">{format_value(change["to"])}</span>
      </li>
    </ul>
    """
  end

  defp summary(%{entry: %Entry{action: action, metadata: %{"version" => version}}} = assigns)
       when action in [:plan_generated, :plan_regenerated] and is_integer(version) do
    assigns = assign(assigns, :text, plan_summary(action, version))

    ~H"""
    <p>{@text}</p>
    """
  end

  # An undo names the change it reverted and links to its entry in the log.
  defp summary(
         %{
           entry: %Entry{
             action: :site_undone,
             metadata: %{
               "version" => version,
               "restored_from_version" => restored,
               "reverts_entry_id" => reverted_id,
               "reverts_entry_at" => reverted_at
             }
           }
         } = assigns
       )
       when is_integer(version) and is_integer(restored) and is_integer(reverted_id) do
    assigns =
      assign(assigns,
        reverted_id: reverted_id,
        text:
          gettext(
            "Undid the change from %{time}: the content of version %{restored} is back as version %{version}.",
            time: format_iso_timestamp(reverted_at),
            restored: restored,
            version: version
          )
      )

    ~H"""
    <p>{@text}</p>
    <.link
      id={"#{@id}-reverts"}
      href={"#activities-#{@reverted_id}"}
      class="mt-1 inline-flex items-center gap-1 text-xs font-medium text-zinc-500 underline-offset-4 transition hover:text-zinc-900 hover:underline"
    >
      <.icon name="hero-arrow-uturn-left" class="size-3" />
      {gettext("Show the undone change")}
    </.link>
    """
  end

  defp summary(%{entry: %Entry{action: action, metadata: %{"version" => version}}} = assigns)
       when action in @site_actions and is_integer(version) do
    assigns = assign(assigns, :text, site_summary(action, version))

    ~H"""
    <p>{@text}</p>
    """
  end

  defp summary(%{entry: %Entry{action: action}} = assigns) do
    assigns = assign(assigns, :text, fallback_summary(action))

    ~H"""
    <p>{@text}</p>
    """
  end

  defp fallback_summary(:company_created), do: gettext("Created the company.")
  defp fallback_summary(:company_updated), do: gettext("Updated the company profile.")
  defp fallback_summary(:plan_generated), do: gettext("Generated the business plan.")
  defp fallback_summary(:plan_regenerated), do: gettext("Requested a new business plan.")
  defp fallback_summary(:site_generated), do: gettext("Generated the website draft.")
  defp fallback_summary(:site_updated), do: gettext("Edited the website.")
  defp fallback_summary(:site_published), do: gettext("Published the website.")
  defp fallback_summary(:site_undone), do: gettext("Undid a website change.")
  # An action without a renderer yet must not break the whole log page; the
  # test over `Entry.actions/0` catches the missing clause.
  defp fallback_summary(_action), do: ""

  defp plan_summary(:plan_generated, version),
    do: gettext("Generated version %{version} of the business plan.", version: version)

  defp plan_summary(:plan_regenerated, version),
    do: gettext("Requested version %{version} of the business plan.", version: version)

  defp site_summary(:site_generated, version),
    do: gettext("Generated version %{version} of the website.", version: version)

  defp site_summary(:site_updated, version),
    do: gettext("Saved version %{version} of the website.", version: version)

  defp site_summary(:site_published, version),
    do: gettext("Published version %{version} of the website.", version: version)

  defp site_summary(:site_undone, version),
    do: gettext("Restored the website as version %{version}.", version: version)

  @doc """
  The translated label for an action; an action without a label yet shows
  as stored rather than crashing the log.
  """
  @spec action_label(Entry.action()) :: String.t()
  def action_label(:company_created), do: gettext("Company created")
  def action_label(:company_updated), do: gettext("Profile updated")
  def action_label(:plan_generated), do: gettext("Plan generated")
  def action_label(:plan_regenerated), do: gettext("New plan requested")
  def action_label(:site_generated), do: gettext("Website generated")
  def action_label(:site_updated), do: gettext("Website edited")
  def action_label(:site_published), do: gettext("Website published")
  def action_label(:site_undone), do: gettext("Website change undone")
  def action_label(action) when is_atom(action), do: Atom.to_string(action)

  @doc "The translated label for an actor."
  @spec actor_label(Entry.actor()) :: String.t()
  def actor_label(:owner), do: gettext("Owner")
  def actor_label(:agent), do: gettext("AI agent")
  def actor_label(:system), do: gettext("System")

  defp actor_icon(:owner), do: "hero-user"
  defp actor_icon(:agent), do: "hero-sparkles"
  defp actor_icon(:system), do: "hero-cog-6-tooth"

  # Field names come from the stored metadata; unknown ones show as stored.
  defp field_label("name"), do: gettext("Company name")
  defp field_label("industry"), do: gettext("Industry")
  defp field_label("city"), do: gettext("City")
  defp field_label("contact_email"), do: gettext("Contact email")
  defp field_label(field), do: field

  defp format_value(nil), do: gettext("(empty)")
  defp format_value(""), do: gettext("(empty)")
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: Jason.encode!(value)

  defp format_iso_timestamp(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> format_timestamp(at)
      {:error, _invalid} -> iso
    end
  end

  defp format_iso_timestamp(_missing), do: gettext("(unknown)")

  # No tz database in deps, so times show in UTC with a label (#14).
  defp format_timestamp(%DateTime{} = at) do
    gettext("%{time} UTC", time: Calendar.strftime(at, "%d.%m.%Y, %H:%M"))
  end
end
