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

  @doc "One activity entry: actor, action, time and summary."
  attr :id, :string, required: true
  attr :entry, Entry, required: true

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
          <.summary entry={@entry} />
        </div>
      </div>
    </article>
    """
  end

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

  defp summary(%{entry: %Entry{action: action}} = assigns) do
    assigns = assign(assigns, :text, fallback_summary(action))

    ~H"""
    <p>{@text}</p>
    """
  end

  defp fallback_summary(:company_created), do: gettext("Created the company.")
  defp fallback_summary(:company_updated), do: gettext("Updated the company profile.")
  # An action without a renderer yet must not break the whole log page; the
  # test over `Entry.actions/0` catches the missing clause.
  defp fallback_summary(_action), do: ""

  @doc """
  The translated label for an action; an action without a label yet shows
  as stored rather than crashing the log.
  """
  @spec action_label(Entry.action()) :: String.t()
  def action_label(:company_created), do: gettext("Company created")
  def action_label(:company_updated), do: gettext("Profile updated")
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

  # No tz database in deps, so times show in UTC with a label (#14).
  defp format_timestamp(%DateTime{} = at) do
    gettext("%{time} UTC", time: Calendar.strftime(at, "%d.%m.%Y, %H:%M"))
  end
end
