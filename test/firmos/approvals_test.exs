defmodule Firmos.ApprovalsTest do
  use Firmos.DataCase, async: true

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox

  alias Firmos.Activity
  alias Firmos.Approvals
  alias Firmos.Approvals.Approval
  alias Firmos.Plans
  alias Firmos.Repo
  alias Firmos.Sites

  setup :verify_on_exit!

  setup do
    scope = user_scope_fixture()
    %{scope: scope, company: company_with_draft(scope)}
  end

  # A company whose site has version 1 as its current draft (no slug).
  defp company_with_draft(scope) do
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, company).id)
    {:ok, site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, site_json()})
    {:ok, _version} = Sites.generate_site(site.id, 1)
    company
  end

  defp site(scope, company), do: Sites.get_site(scope, company)

  # Version 1 live at `slug`, version 2 the current draft.
  defp published_then_edited(scope, company, slug \\ "piekarnia") do
    {:ok, site} = Sites.set_slug(scope, site(scope, company), slug)
    {:ok, site} = Sites.publish(scope, site)
    edit(scope, site, "Wersja druga")
  end

  defp edit(scope, site, headline) do
    {:ok, site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => headline}})
    site
  end

  defp request!(scope, company) do
    {:ok, approval} = Approvals.request_publish(company, site(scope, company).current_version)
    approval
  end

  defp status(scope, approval) do
    {:ok, %Approval{status: status}} = Approvals.get_approval(scope, approval.id)
    status
  end

  defp latest(scope, company, action),
    do: Activity.latest_for_company(scope, company, [action])

  describe "request_publish/2" do
    test "queues a pending request by the agent for the current version",
         %{scope: scope, company: company} do
      approval = request!(scope, company)

      assert %Approval{status: :pending, requested_by: :agent, kind: :publish_site_version} =
               approval

      assert approval.site_version_id == site(scope, company).current_version_id
    end

    test "records approval_requested by the agent", %{scope: scope, company: company} do
      approval = request!(scope, company)
      entry = latest(scope, company, :approval_requested)

      assert %{actor: :agent, subject_type: "site_version", metadata: %{"version" => 1}} = entry
      assert entry.subject_id == approval.site_version_id
    end

    test "doesn't broadcast (the caller may not have committed yet)",
         %{scope: scope, company: company} do
      :ok = Approvals.subscribe(scope, company)
      request!(scope, company)

      refute_received {:approvals_updated, _company}
    end

    test "broadcast_updated/1 notifies the company's approvals topic",
         %{scope: scope, company: company} do
      :ok = Approvals.subscribe(scope, company)
      :ok = Approvals.broadcast_updated(company.id)
      company_id = company.id

      assert_receive {:approvals_updated, %{company_id: ^company_id}}
    end

    test "refuses the version that is already published", %{scope: scope, company: company} do
      {:ok, site} = Sites.set_slug(scope, site(scope, company), "piekarnia")
      {:ok, site} = Sites.publish(scope, site)

      assert Approvals.request_publish(company, site.current_version) ==
               {:error, :already_published}
    end

    test "supersedes the previous pending request", %{scope: scope, company: company} do
      first = request!(scope, company)
      second = request!(scope, company)

      assert {status(scope, first), status(scope, second)} == {:superseded, :pending}
    end

    test "works inside the caller's transaction", %{scope: scope, company: company} do
      version = site(scope, company).current_version

      assert {:ok, {:ok, %Approval{}}} =
               Repo.transact(fn -> {:ok, Approvals.request_publish(company, version)} end)
    end

    test "refuses a version that is no longer current", %{scope: scope, company: company} do
      old = site(scope, company).current_version
      edit(scope, site(scope, company), "Nowszy")

      assert Approvals.request_publish(company, old) == {:error, :outdated}
    end

    test "refuses another company's version", %{company: company} do
      other_scope = user_scope_fixture()
      other_version = site(other_scope, company_with_draft(other_scope)).current_version

      assert Approvals.request_publish(company, other_version) == {:error, :not_found}
    end
  end

  describe "the partial unique index" do
    test "allows one pending request per company and kind", %{scope: scope, company: company} do
      approval = request!(scope, company)

      assert {:error, changeset} =
               company.id
               |> Approval.publish_request_changeset(approval.site_version_id)
               |> Repo.insert()

      assert "already has a pending request" in errors_on(changeset).company_id
    end

    test "allows a new request once the previous one is decided",
         %{scope: scope, company: company} do
      {:ok, _rejected} = Approvals.reject(scope, request!(scope, company))

      assert %Approval{status: :pending} = request!(scope, company)
    end
  end

  describe "a request outdated by the owner's own site changes" do
    setup %{scope: scope, company: company} do
      {:ok, _site} = Sites.set_slug(scope, site(scope, company), "piekarnia")
      %{approval: request!(scope, company)}
    end

    defp pending_ids(scope, company),
      do: scope |> Approvals.list_pending(company) |> Enum.map(& &1.id)

    defp decided_ids(scope, company),
      do: scope |> Approvals.list_decided(company) |> Enum.map(& &1.id)

    test "is listed and counted while it applies",
         %{scope: scope, company: company, approval: approval} do
      assert {pending_ids(scope, company), Approvals.count_pending(scope, company)} ==
               {[approval.id], 1}
    end

    test "a direct publication outdates it", %{scope: scope, company: company} do
      {:ok, _site} = Sites.publish(scope, site(scope, company))

      assert {pending_ids(scope, company), Approvals.count_pending(scope, company)} == {[], 0}
    end

    test "an edit outdates it", %{scope: scope, company: company} do
      edit(scope, site(scope, company), "Zmiana")

      assert {pending_ids(scope, company), Approvals.count_pending(scope, company)} == {[], 0}
    end

    test "an undo outdates it", %{scope: scope, company: company} do
      edit(scope, site(scope, company), "Zmiana")
      approval = request!(scope, company)
      entry = Sites.undoable_entry(scope, company)
      {:ok, _site} = Sites.undo(scope, company, entry.id)

      assert {pending_ids(scope, company), Approvals.approve(scope, approval)} ==
               {[], {:error, :outdated}}
    end

    test "is shown in the history", %{scope: scope, company: company, approval: approval} do
      edit(scope, site(scope, company), "Zmiana")

      assert approval.id in decided_ids(scope, company)
    end

    test "approving it after a direct publication is refused",
         %{scope: scope, company: company, approval: approval} do
      {:ok, _site} = Sites.publish(scope, site(scope, company))

      assert Approvals.approve(scope, approval) == {:error, :outdated}
    end

    test "approving it marks it superseded", %{scope: scope, company: company, approval: approval} do
      edit(scope, site(scope, company), "Zmiana")
      {:error, :outdated} = Approvals.approve(scope, approval)

      assert status(scope, approval) == :superseded
    end

    test "rejecting it is refused as outdated",
         %{scope: scope, company: company, approval: approval} do
      edit(scope, site(scope, company), "Zmiana")

      assert Approvals.reject(scope, approval) == {:error, :outdated}
    end
  end

  describe "approve/2" do
    setup %{scope: scope, company: company} do
      published_then_edited(scope, company)
      %{approval: request!(scope, company)}
    end

    test "publishes the requested version", %{scope: scope, company: company, approval: approval} do
      {:ok, _approved} = Approvals.approve(scope, approval)

      assert site(scope, company).published_version_id == approval.site_version_id
    end

    test "marks the request approved by the owner",
         %{scope: scope, approval: approval} do
      assert {:ok, %Approval{status: :approved, decided_by_user_id: user_id, decided_at: %{}}} =
               Approvals.approve(scope, approval)

      assert user_id == scope.user.id
    end

    test "records site_published with the previously published version",
         %{scope: scope, company: company, approval: approval} do
      previous = site(scope, company).published_version_id
      {:ok, _approved} = Approvals.approve(scope, approval)

      assert latest(scope, company, :site_published).metadata["previous_published_version_id"] ==
               previous
    end

    test "records approval_approved by the owner",
         %{scope: scope, company: company, approval: approval} do
      {:ok, _approved} = Approvals.approve(scope, approval)

      assert %{actor: :owner, metadata: %{"version" => 2}} =
               latest(scope, company, :approval_approved)
    end

    test "refuses a second approval", %{scope: scope, approval: approval} do
      {:ok, _approved} = Approvals.approve(scope, approval)

      assert Approvals.approve(scope, approval) == {:error, :already_decided}
    end

    test "refuses a rejected request", %{scope: scope, approval: approval} do
      {:ok, _rejected} = Approvals.reject(scope, approval)

      assert Approvals.approve(scope, approval) == {:error, :already_decided}
    end

    test "the approved publication can be undone",
         %{scope: scope, company: company, approval: approval} do
      {:ok, _approved} = Approvals.approve(scope, approval)
      entry = Sites.undoable_entry(scope, company)
      {:ok, site} = Sites.undo(scope, company, entry.id)

      assert {site.published_version_id, site.current_version.content.hero.headline} ==
               {site.current_version_id, site_attrs()["hero"]["headline"]}
    end

    test "is refused as outdated after the owner edited the draft",
         %{scope: scope, company: company, approval: approval} do
      edit(scope, site(scope, company), "Poprawka")

      assert Approvals.approve(scope, approval) == {:error, :outdated}
    end

    test "publishes nothing when outdated",
         %{scope: scope, company: company, approval: approval} do
      published = site(scope, company).published_version_id
      edit(scope, site(scope, company), "Poprawka")
      {:error, :outdated} = Approvals.approve(scope, approval)

      assert site(scope, company).published_version_id == published
    end

    test "refuses another owner's request", %{approval: approval} do
      assert Approvals.approve(user_scope_fixture(), approval) == {:error, :not_found}
    end
  end

  describe "approve/2 without a slug" do
    setup %{scope: scope, company: company}, do: %{approval: request!(scope, company)}

    test "is refused with :no_slug", %{scope: scope, approval: approval} do
      assert Approvals.approve(scope, approval) == {:error, :no_slug}
    end

    test "leaves the request pending", %{scope: scope, approval: approval} do
      {:error, :no_slug} = Approvals.approve(scope, approval)

      assert status(scope, approval) == :pending
    end
  end

  describe "reject/2" do
    setup %{scope: scope, company: company} do
      published_then_edited(scope, company)
      %{approval: request!(scope, company)}
    end

    test "marks the request rejected and publishes nothing",
         %{scope: scope, company: company, approval: approval} do
      published = site(scope, company).published_version_id

      assert {:ok, %Approval{status: :rejected}} = Approvals.reject(scope, approval)
      assert site(scope, company).published_version_id == published
    end

    test "records approval_rejected", %{scope: scope, company: company, approval: approval} do
      {:ok, _rejected} = Approvals.reject(scope, approval)

      assert %{actor: :owner, subject_id: version_id} = latest(scope, company, :approval_rejected)
      assert version_id == approval.site_version_id
    end

    test "refuses another owner's request", %{approval: approval} do
      assert Approvals.reject(user_scope_fixture(), approval) == {:error, :not_found}
    end
  end

  describe "listing" do
    test "lists pending and decided requests apart", %{scope: scope, company: company} do
      first = request!(scope, company)
      second = request!(scope, company)

      assert {Enum.map(Approvals.list_pending(scope, company), & &1.id),
              Enum.map(Approvals.list_decided(scope, company), & &1.id)} ==
               {[second.id], [first.id]}
    end

    test "raises for another owner's company", %{company: company} do
      assert_raise FunctionClauseError, fn ->
        Approvals.list_pending(user_scope_fixture(), company)
      end
    end
  end

  test "deleting the company deletes its requests", %{scope: scope, company: company} do
    approval = request!(scope, company)
    {:ok, _company} = Repo.delete(company)

    refute Repo.get(Approval, approval.id)
  end
end
