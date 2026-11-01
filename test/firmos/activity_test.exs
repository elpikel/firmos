defmodule Firmos.ActivityTest do
  use Firmos.DataCase, async: true

  import Ecto.Query
  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures

  alias Firmos.Activity
  alias Firmos.Activity.Entry
  alias Firmos.Companies.Company
  alias Firmos.Repo

  setup do
    scope = user_scope_fixture()
    %{scope: scope, company: company_fixture(scope)}
  end

  describe "record/4" do
    test "records an owner action with the owner's user id", %{scope: scope, company: company} do
      assert {:ok, entry} = Activity.record(company, scope, :company_updated)
      assert entry.actor == :owner
      assert entry.actor_user_id == scope.user.id
      assert entry.company_id == company.id
      assert entry.metadata == %{}
    end

    test "records agent and system actions without a user", %{company: company} do
      assert {:ok, %{actor: :agent, actor_user_id: nil}} =
               Activity.record(company, :agent, :company_updated)

      assert {:ok, %{actor: :system, actor_user_id: nil}} =
               Activity.record(company, :system, :company_updated)
    end

    test "stores metadata with string keys, as a later read loads it", %{company: company} do
      assert {:ok, entry} =
               Activity.record(company, :agent, :company_updated,
                 metadata: %{changes: %{city: %{from: nil, to: "Kraków"}}}
               )

      expected = %{"changes" => %{"city" => %{"from" => nil, "to" => "Kraków"}}}
      assert entry.metadata == expected
      assert Repo.get!(Entry, entry.id).metadata == expected
    end

    test "stores the subject", %{company: company} do
      assert {:ok, entry} =
               Activity.record(company, :agent, :company_updated, subject: {"site_version", 42})

      assert {entry.subject_type, entry.subject_id} == {"site_version", 42}
    end

    test "rejects an unknown action", %{company: company} do
      assert {:error, changeset} = Activity.record(company, :agent, :site_exploded)
      assert %{action: ["is invalid"]} = errors_on(changeset)
    end

    test "refuses an owner recording on another owner's company", %{company: company} do
      assert_raise FunctionClauseError, fn ->
        Activity.record(company, user_scope_fixture(), :company_updated)
      end
    end

    test "refuses an unknown actor", %{company: company} do
      assert_raise FunctionClauseError, fn ->
        Activity.record(company, :hacker, :company_updated)
      end
    end
  end

  describe "list_for_company/2" do
    test "lists entries newest first, by time before id", %{scope: scope, company: company} do
      [created] = Activity.list_for_company(scope, company)
      {:ok, later_id} = Activity.record(company, :agent, :company_updated)

      # The higher id is older, so time must decide the order.
      backdated = DateTime.add(created.inserted_at, -3600, :second)

      Repo.update_all(from(e in Entry, where: e.id == ^later_id.id),
        set: [inserted_at: backdated]
      )

      assert Enum.map(Activity.list_for_company(scope, company), & &1.id) == [
               created.id,
               later_id.id
             ]
    end

    test "breaks timestamp ties by newest id", %{scope: scope, company: company} do
      {:ok, first} = Activity.record(company, :agent, :company_updated)
      {:ok, second} = Activity.record(company, :agent, :company_updated)

      assert [%{id: id1}, %{id: id2} | _] = Activity.list_for_company(scope, company)
      assert {id1, id2} == {second.id, first.id}
    end

    test "only lists the given company's entries", %{scope: scope, company: company} do
      other = company_fixture(scope, "Drugi pomysł: warsztat rowerowy na Kazimierzu.")
      {:ok, _} = Activity.record(other, :agent, :company_updated)

      assert Enum.all?(Activity.list_for_company(scope, company), &(&1.company_id == company.id))
    end

    test "refuses another owner's company", %{company: company} do
      assert_raise FunctionClauseError, fn ->
        Activity.list_for_company(user_scope_fixture(), company)
      end
    end

    test "reads nothing through a forged company struct", %{company: company} do
      intruder = user_scope_fixture()
      forged = %Company{company | user_id: intruder.user.id}

      assert Activity.list_for_company(intruder, forged) == []
    end
  end

  describe "list_for_company/3 paging" do
    setup %{company: company} do
      for _ <- 1..4, do: {:ok, _} = Activity.record(company, :agent, :company_updated)
      :ok
    end

    test "limits the page", %{scope: scope, company: company} do
      assert length(Activity.list_for_company(scope, company, limit: 2)) == 2
    end

    test "walks every entry exactly once, newest first", %{scope: scope, company: company} do
      all = Activity.list_for_company(scope, company)
      first = Activity.list_for_company(scope, company, limit: 2)
      cursor = first |> List.last() |> Activity.cursor()
      second = Activity.list_for_company(scope, company, limit: 2, before: cursor)

      third =
        Activity.list_for_company(scope, company,
          limit: 2,
          before: Activity.cursor(List.last(second))
        )

      assert first ++ second ++ third == all
    end

    test "orders across different timestamps by the cursor", %{scope: scope, company: company} do
      [newest | _] = Activity.list_for_company(scope, company)
      backdated = DateTime.add(newest.inserted_at, -3600, :second)
      Repo.update_all(from(e in Entry, where: e.id == ^newest.id), set: [inserted_at: backdated])

      [now_first | _] = Activity.list_for_company(scope, company)
      rest = Activity.list_for_company(scope, company, before: Activity.cursor(now_first))

      assert List.last(rest).id == newest.id
    end
  end
end
