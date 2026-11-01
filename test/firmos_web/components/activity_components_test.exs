defmodule FirmosWeb.ActivityComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Firmos.Activity.Entry
  alias FirmosWeb.ActivityComponents

  defp render_entry(action) do
    entry = %Entry{id: 1, actor: :system, action: action, inserted_at: ~U[2026-11-01 10:00:00Z]}

    (&ActivityComponents.activity_entry/1)
    |> render_component(id: "entry", entry: entry)
    |> LazyHTML.from_fragment()
  end

  for action <- Entry.actions() do
    test "#{action} has a translated label" do
      assert ActivityComponents.action_label(unquote(action)) != unquote(Atom.to_string(action))
    end

    test "#{action} has a summary without details" do
      summary =
        unquote(action)
        |> render_entry()
        |> LazyHTML.query("[data-role=summary]")
        |> LazyHTML.text()
        |> String.trim()

      assert summary != ""
    end
  end

  test "an action without a label shows as stored" do
    assert ActivityComponents.action_label(:site_published) == "site_published"
  end
end
