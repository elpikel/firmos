defmodule Firmos.SitesTest do
  use Firmos.DataCase, async: true
  use Oban.Testing, repo: Firmos.Repo

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox

  alias Firmos.Activity
  alias Firmos.Companies
  alias Firmos.Plans
  alias Firmos.Sites
  alias Firmos.Sites.GenerateWorker
  alias Firmos.Sites.Site
  alias Firmos.Sites.Version

  setup :verify_on_exit!

  setup do
    scope = user_scope_fixture()
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, company).id)
    %{scope: scope, company: company}
  end

  defp request!(scope, company) do
    {:ok, site} = Sites.request_generation(scope, company)
    site
  end

  # Stand-in Oban job ids (the claim tokens).
  @job_id 1
  @newer_job_id 2

  defp generate(site, reply) do
    expect_ai_reply(reply)
    Sites.generate_site(site.id, @job_id)
  end

  defp generated_site(scope, company) do
    site = request!(scope, company)
    {:ok, _version} = generate(site, {:ok, site_json()})
    Sites.get_site(scope, company)
  end

  # Puts the site in `generating` for job `@job_id`, last touched
  # `minutes_ago` minutes ago.
  defp generating_since(site, minutes_ago) do
    at = DateTime.add(DateTime.utc_now(:second), -minutes_ago, :minute)

    Repo.update_all(from(s in Site, where: s.id == ^site.id),
      set: [generation_status: :generating, generation_job_id: @job_id, updated_at: at]
    )

    Repo.get!(Site, site.id)
  end

  describe "request_generation/2" do
    test "creates a pending draft site and enqueues its job", %{scope: scope, company: company} do
      site = request!(scope, company)

      assert %{status: :draft, generation_status: :pending, current_version_id: nil} = site
      assert_enqueued(worker: GenerateWorker, args: %{site_id: site.id}, queue: :ai)
    end

    test "reuses the company's site", %{scope: scope, company: company} do
      first = generated_site(scope, company)
      again = request!(scope, company)

      assert again.id == first.id
      assert Repo.aggregate(from(s in Site, where: s.company_id == ^company.id), :count) == 1
    end

    test "refuses while a generation is pending", %{scope: scope, company: company} do
      request!(scope, company)
      assert {:error, :generation_in_progress} = Sites.request_generation(scope, company)
    end

    test "allows a new request once the generation has stalled",
         %{scope: scope, company: company} do
      site = scope |> request!(company) |> generating_since(121)

      assert Sites.stalled?(site)
      assert {:ok, %{generation_status: :pending}} = Sites.request_generation(scope, company)
    end

    test "re-requesting a stalled pending site restarts its stall clock",
         %{scope: scope, company: company} do
      site = request!(scope, company)
      at = DateTime.add(DateTime.utc_now(:second), -121, :minute)
      Repo.update_all(from(s in Site, where: s.id == ^site.id), set: [updated_at: at])
      assert scope |> Sites.get_site(company) |> Sites.stalled?()

      {:ok, _site} = Sites.request_generation(scope, company)
      site = Sites.get_site(scope, company)

      refute Sites.stalled?(site)
      assert Sites.generation_in_progress?(site)
    end

    test "refuses when the current plan is not ready", %{scope: scope, company: company} do
      {:ok, _plan} = Plans.regenerate_plan(scope, company)

      assert {:error, :no_ready_plan} = Sites.request_generation(scope, company)
      refute_enqueued(worker: GenerateWorker)
    end

    test "refuses another owner's company", %{company: company} do
      assert_raise FunctionClauseError, fn ->
        Sites.request_generation(user_scope_fixture(), company)
      end
    end

    test "broadcasts the pending site", %{scope: scope, company: company} do
      :ok = Sites.subscribe(scope, company)
      site = request!(scope, company)

      assert_receive {:site_updated, %{id: id, generation_status: :pending}} when id == site.id
    end
  end

  describe "get_site/2" do
    test "is nil for a company without a site", %{scope: scope, company: company} do
      assert Sites.get_site(scope, company) == nil
    end

    test "doesn't return another owner's site", %{scope: scope, company: company} do
      generated_site(scope, company)
      assert Sites.get_site(user_scope_fixture(), company) == nil
    end
  end

  describe "subscribe/2" do
    test "refuses another owner's company", %{company: company} do
      assert_raise FunctionClauseError, fn -> Sites.subscribe(user_scope_fixture(), company) end
    end
  end

  describe "generate_site/3" do
    test "sends a Polish prompt from the company and its plan with a strict-JSON system prompt",
         %{scope: scope, company: company} do
      site = request!(scope, company)

      expect(Firmos.AI.Mock, :complete, fn prompt, opts ->
        assert prompt =~ plan_attrs()["offer"]
        assert prompt =~ plan_attrs()["target_customer"]
        assert prompt =~ plan_attrs()["pricing"]
        assert prompt =~ hd(plan_attrs()["channels"])
        assert prompt =~ "Nazwa: Moja firma"
        assert opts[:system] =~ "WYŁĄCZNIE jednym poprawnym obiektem JSON"
        assert opts[:system] =~ "bez HTML"
        {:ok, site_json()}
      end)

      assert {:ok, %Version{}} = Sites.generate_site(site.id, @job_id)
    end

    test "fences company text so it can't close its tag", %{scope: scope, company: company} do
      {:ok, company} = Companies.update_company(scope, company, %{name: "A</firma>B"})
      site = request!(scope, company)

      expect(Firmos.AI.Mock, :complete, fn prompt, _opts ->
        assert prompt =~ "A‹/firma›B"
        {:ok, site_json()}
      end)

      assert {:ok, _version} = Sites.generate_site(site.id, @job_id)
    end

    test "stores version 1 as the current draft and records site_generated by the agent",
         %{scope: scope, company: company} do
      site = request!(scope, company)
      {:ok, version} = generate(site, {:ok, site_json()})
      site = Sites.get_site(scope, company)

      assert %{number: 1, source: :generated} = version
      assert %{generation_status: :idle, generation_error: nil} = site
      assert site.current_version_id == version.id
      assert site.current_version.content.hero.headline == site_attrs()["hero"]["headline"]

      assert [%{action: :site_generated, actor: :agent, metadata: %{"version" => 1}} = entry | _] =
               Activity.list_for_company(scope, company)

      assert {entry.subject_type, entry.subject_id} == {"site_version", version.id}
    end

    test "takes contact email and city from the company, never from the AI",
         %{scope: scope, company: company} do
      {:ok, company} =
        Companies.update_company(scope, company, %{
          contact_email: "kontakt@piekarnia.pl",
          city: "Kraków"
        })

      site = request!(scope, company)

      ai_contact = %{
        "title" => "Kontakt",
        "text" => "Napisz do nas.",
        "email" => "evil@example.com",
        "phone" => "+48 600 000 000",
        "city" => "Gdzieś"
      }

      {:ok, version} = generate(site, {:ok, site_json(%{"contact" => ai_contact})})

      assert %{email: "kontakt@piekarnia.pl", phone: nil, city: "Kraków"} =
               version.content.contact
    end

    test "regenerating adds a new version and keeps the older one",
         %{scope: scope, company: company} do
      first = generated_site(scope, company)
      site = request!(scope, company)
      {:ok, second} = generate(site, {:ok, site_json()})

      assert second.number == 2
      assert Sites.get_site(scope, company).current_version_id == second.id
      assert Repo.get!(Version, first.current_version_id).number == 1
    end

    test "on an AI error stores failed with a safe code and no version",
         %{scope: scope, company: company} do
      site = request!(scope, company)

      assert {:error, {:generation_failed, "http_status:500"}} =
               generate(site, {:error, {:http_status, 500, "secret provider body"}})

      assert %{generation_status: :failed, generation_error: "http_status:500"} =
               Sites.get_site(scope, company)

      assert Repo.aggregate(Version, :count) == 0
    end

    test "on content in the wrong shape stores failed", %{scope: scope, company: company} do
      site = request!(scope, company)
      reply = {:ok, site_json(%{"offer" => %{"title" => "Oferta", "items" => []}})}

      assert {:error, {:generation_failed, "invalid_shape"}} = generate(site, reply)
    end

    test "on non-JSON content stores failed", %{scope: scope, company: company} do
      site = request!(scope, company)
      assert {:error, {:generation_failed, "invalid_json"}} = generate(site, {:ok, "Oto strona"})
    end

    test "fails without calling the AI when the plan is no longer ready",
         %{scope: scope, company: company} do
      site = request!(scope, company)
      {:ok, _plan} = Plans.regenerate_plan(scope, company)

      assert {:error, {:generation_failed, "no_ready_plan"}} =
               Sites.generate_site(site.id, @job_id)
    end

    test "doesn't claim a site that isn't pending", %{scope: scope, company: company} do
      site = generated_site(scope, company)
      assert {:error, :not_claimable} = Sites.generate_site(site.id, @job_id)
    end

    test "resume takes over the site its own job left generating",
         %{scope: scope, company: company} do
      site = scope |> request!(company) |> generating_since(1)
      expect_ai_reply({:ok, site_json()})

      assert {:ok, _version} = Sites.generate_site(site.id, @job_id, resume: true)
    end

    test "resume doesn't take a site another job is generating",
         %{scope: scope, company: company} do
      site = scope |> request!(company) |> generating_since(1)

      assert {:error, :not_claimable} =
               Sites.generate_site(site.id, @newer_job_id, resume: true)
    end

    test "a stale job's draft is dropped after the owner asked again, and the newer job's wins",
         %{scope: scope, company: company} do
      site = request!(scope, company)
      stale_hero = Map.put(site_attrs()["hero"], "headline", "Stara wersja")
      newer_hero = Map.put(site_attrs()["hero"], "headline", "Nowa wersja")

      # The stale job's AI call outlives its claim: meanwhile the generation
      # stalls, the owner asks again and the newer job finishes first.
      expect(Firmos.AI.Mock, :complete, fn _prompt, _opts ->
        generating_since(site, 121)
        {:ok, _pending} = Sites.request_generation(scope, company)
        {:ok, _version} = Sites.generate_site(site.id, @newer_job_id)
        {:ok, site_json(%{"hero" => stale_hero})}
      end)

      expect_ai_reply({:ok, site_json(%{"hero" => newer_hero})})

      assert {:error, :not_claimable} = Sites.generate_site(site.id, @job_id)

      site = Sites.get_site(scope, company)
      assert site.current_version.content.hero.headline == "Nowa wersja"
      assert %{generation_status: :idle} = site
      assert Repo.aggregate(Version, :count) == 1
    end

    test "a stale job's failure doesn't fail the newer generation",
         %{scope: scope, company: company} do
      site = request!(scope, company)

      expect(Firmos.AI.Mock, :complete, fn _prompt, _opts ->
        generating_since(site, 121)
        {:ok, _pending} = Sites.request_generation(scope, company)
        {:error, :timeout}
      end)

      assert {:error, :not_claimable} = Sites.generate_site(site.id, @job_id)
      assert %{generation_status: :pending} = Sites.get_site(scope, company)
    end
  end

  describe "mark_failed/3" do
    test "fails a generating site", %{scope: scope, company: company} do
      site = scope |> request!(company) |> generating_since(1)

      assert {:ok, %{generation_status: :failed, generation_error: "crashed"}} =
               Sites.mark_failed(site.id, @job_id, "crashed")
    end

    test "leaves a site another job is generating alone", %{scope: scope, company: company} do
      site = scope |> request!(company) |> generating_since(1)
      assert {:error, :not_found} = Sites.mark_failed(site.id, @newer_job_id, "crashed")
    end

    test "leaves an idle site alone", %{scope: scope, company: company} do
      site = generated_site(scope, company)
      assert {:error, :not_found} = Sites.mark_failed(site.id, @job_id, "crashed")
    end
  end

  describe "GenerateWorker" do
    test "generates the site", %{scope: scope, company: company} do
      site = request!(scope, company)
      expect_ai_reply({:ok, site_json()})

      assert :ok = perform_job(GenerateWorker, %{site_id: site.id})
    end

    test "cancels on a generation failure", %{scope: scope, company: company} do
      site = request!(scope, company)
      expect_ai_reply({:error, :timeout})

      assert {:cancel, "timeout"} = perform_job(GenerateWorker, %{site_id: site.id})
    end

    test "marks the site failed when the final attempt crashes",
         %{scope: scope, company: company} do
      site = request!(scope, company)
      expect(Firmos.AI.Mock, :complete, fn _prompt, _opts -> raise "boom" end)

      assert_raise RuntimeError, fn ->
        perform_job(GenerateWorker, %{site_id: site.id}, attempt: 2)
      end

      assert %{generation_status: :failed, generation_error: "crashed"} =
               Sites.get_site(scope, company)
    end
  end

  describe "update_content/3" do
    setup %{scope: scope, company: company} do
      %{site: generated_site(scope, company)}
    end

    test "leaves the published version and the generation status alone",
         %{scope: scope, company: company, site: site} do
      {:ok, site} = Sites.set_slug(scope, site, "piekarnia")
      {:ok, published} = Sites.publish(scope, site)

      Repo.update_all(from(s in Site, where: s.id == ^site.id),
        set: [generation_status: :failed, generation_error: "timeout"]
      )

      {:ok, edited} =
        Sites.update_content(scope, published, %{"hero" => %{"headline" => "Nowy"}})

      assert %{
               published_version_id: published_id,
               generation_status: :failed,
               current_version: %{number: 2}
             } = edited

      assert published_id == published.published_version_id
      assert Sites.unpublished_changes?(Sites.get_site(scope, company))
    end

    test "records every changed field, items as one", %{scope: scope, site: site} do
      attrs = %{
        "offer" => %{"items" => %{"0" => %{"name" => "Bagietki", "description" => "Chrupiące."}}},
        "contact" => %{"text" => "Zadzwoń!"}
      }

      {:ok, edited} = Sites.update_content(scope, site, attrs)
      entry = Repo.get_by!(Firmos.Activity.Entry, subject_id: edited.current_version_id)

      assert entry.metadata == %{"version" => 2, "fields" => ["offer.items", "contact.text"]}
      assert [%{name: "Bagietki"}] = edited.current_version.content.offer.items
    end

    test "an unchanged edit stores no version and no activity",
         %{scope: scope, company: company, site: site} do
      headline = site.current_version.content.hero.headline

      assert {:ok, %{current_version_id: id}} =
               Sites.update_content(scope, site, %{"hero" => %{"headline" => headline}})

      assert id == site.current_version_id
      refute Enum.any?(Activity.list_for_company(scope, company), &(&1.action == :site_updated))
    end

    test "never casts the contact email or city from the edit", %{scope: scope, site: site} do
      contact = site.current_version.content.contact

      {:ok, edited} =
        Sites.update_content(scope, site, %{
          "contact" => %{"text" => "Nowy tekst", "email" => "evil@example.com", "city" => "X"}
        })

      assert %{email: email, city: city, text: "Nowy tekst"} =
               edited.current_version.content.contact

      assert {email, city} == {contact.email, contact.city}
    end

    test "returns the content changeset for an invalid edit", %{scope: scope, site: site} do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Sites.update_content(scope, site, %{"hero" => %{"headline" => ""}})
    end

    test "refuses while a generation is in progress",
         %{scope: scope, company: company, site: site} do
      {:ok, _pending} = Sites.request_generation(scope, company)

      assert {:error, :generation_in_progress} =
               Sites.update_content(scope, site, %{"hero" => %{"headline" => "Nowy"}})
    end

    test "refuses an edit based on a version the site moved away from",
         %{scope: scope, company: company, site: site} do
      {:ok, _other_tab} =
        Sites.update_content(scope, site, %{"hero" => %{"headline" => "Z karty"}})

      assert {:error, :stale} =
               Sites.update_content(scope, site, %{"hero" => %{"headline" => "Stary edytor"}})

      assert Sites.get_site(scope, company).current_version.content.hero.headline == "Z karty"
    end
  end

  describe "set_slug/3" do
    setup %{scope: scope, company: company} do
      %{site: generated_site(scope, company)}
    end

    for {slug, field_error} <- [
          {"ab", "should be at least %{count} character(s)"},
          {"-piekarnia",
           "may only contain lowercase letters, digits and hyphens, not at the start or end"},
          {"piekarnia_krakow",
           "may only contain lowercase letters, digits and hyphens, not at the start or end"},
          {"api", "is reserved"},
          {"xn--pekarnia-9ib", "can't start with xn--"},
          {"   ", "can't be blank"}
        ] do
      test "rejects #{inspect(slug)}", %{scope: scope, site: site} do
        assert {:error, %Ecto.Changeset{errors: [slug: {unquote(field_error), _}]}} =
                 Sites.set_slug(scope, site, unquote(slug))
      end
    end

    test "moving a published site frees its old slug", %{scope: scope, site: site} do
      {:ok, site} = Sites.set_slug(scope, site, "piekarnia")
      {:ok, site} = Sites.publish(scope, site)
      {:ok, _moved} = Sites.set_slug(scope, site, "piekarnia-krakow")

      assert {:error, :not_found} = Sites.get_published_by_slug("piekarnia")
      assert {:ok, _site} = Sites.get_published_by_slug("piekarnia-krakow")
    end
  end

  describe "publish/2" do
    test "refuses a site without content", %{scope: scope, company: company} do
      site = request!(scope, company)
      {:ok, site} = Sites.set_slug(scope, site, "piekarnia")

      assert {:error, :no_content} = Sites.publish(scope, site)
    end

    test "refuses a site without a slug", %{scope: scope, company: company} do
      assert {:error, :slug_required} = Sites.publish(scope, generated_site(scope, company))
    end

    test "republishing the published version records nothing",
         %{scope: scope, company: company} do
      {:ok, site} = Sites.set_slug(scope, generated_site(scope, company), "piekarnia")
      {:ok, site} = Sites.publish(scope, site)
      {:ok, _site} = Sites.publish(scope, site)

      assert [_one] =
               Enum.filter(
                 Activity.list_for_company(scope, company),
                 &(&1.action == :site_published)
               )
    end

    test "broadcasts the published site", %{scope: scope, company: company} do
      {:ok, site} = Sites.set_slug(scope, generated_site(scope, company), "piekarnia")
      :ok = Sites.subscribe(scope, company)
      {:ok, _site} = Sites.publish(scope, site)

      assert_receive {:site_updated, %{id: id}} when id == site.id
    end
  end

  describe "get_published_by_slug/1" do
    test "doesn't return a draft site", %{scope: scope, company: company} do
      {:ok, _site} = Sites.set_slug(scope, generated_site(scope, company), "piekarnia")

      assert {:error, :not_found} = Sites.get_published_by_slug("piekarnia")
    end

    test "serves the published version, not the newer draft",
         %{scope: scope, company: company} do
      {:ok, site} = Sites.set_slug(scope, generated_site(scope, company), "piekarnia")
      {:ok, site} = Sites.publish(scope, site)
      {:ok, _edited} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Nowy"}})

      assert {:ok, %{published_version: %{number: 1}}} = Sites.get_published_by_slug("piekarnia")
    end
  end

  describe "undo/3" do
    setup %{scope: scope, company: company} do
      site = generated_site(scope, company)
      {:ok, edited} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Nowy"}})
      %{site: edited, entry: latest(scope, company, :site_updated)}
    end

    defp latest(scope, company, action) do
      scope |> Activity.list_for_company(company) |> Enum.find(&(&1.action == action))
    end

    test "restores the previous content as a new undo version",
         %{scope: scope, company: company, entry: entry} do
      assert {:ok, %{current_version: %{number: 3, source: :undo, content: content}}} =
               Sites.undo(scope, company, entry.id)

      assert content.hero.headline == site_attrs()["hero"]["headline"]
    end

    test "records the undo with the reverted entry",
         %{scope: scope, company: company, entry: entry} do
      {:ok, site} = Sites.undo(scope, company, entry.id)
      undo = latest(scope, company, :site_undone)

      assert %{
               actor: :owner,
               subject_type: "site_version",
               metadata: %{
                 "version" => 3,
                 "restored_from_version" => 1,
                 "reverts_entry_id" => reverted_id
               }
             } = undo

      assert {reverted_id, undo.subject_id} == {entry.id, site.current_version_id}
    end

    test "offers the latest change, then nothing after the undo",
         %{scope: scope, company: company, entry: entry} do
      assert %{id: id} = Sites.undoable_entry(scope, company)
      assert id == entry.id
      {:ok, _site} = Sites.undo(scope, company, entry.id)
      assert Sites.undoable_entry(scope, company) == nil
    end

    test "a second click is not undoable", %{scope: scope, company: company, entry: entry} do
      {:ok, _site} = Sites.undo(scope, company, entry.id)

      assert {:error, :not_undoable} = Sites.undo(scope, company, entry.id)
    end

    test "refuses an older change", %{scope: scope, company: company} do
      generated = latest(scope, company, :site_generated)

      assert {:error, :not_undoable} = Sites.undo(scope, company, generated.id)
    end

    test "refuses an entry that isn't a site change", %{scope: scope, company: company} do
      created = latest(scope, company, :company_created)

      assert {:error, :not_undoable} = Sites.undo(scope, company, created.id)
    end

    test "refuses while a generation is in progress",
         %{scope: scope, company: company, entry: entry} do
      {:ok, _pending} = Sites.request_generation(scope, company)

      assert {:error, :generation_in_progress} = Sites.undo(scope, company, entry.id)
      assert Sites.undoable_entry(scope, company) == nil
    end

    test "a single version offers nothing to undo" do
      scope = user_scope_fixture()
      company = company_fixture(scope)
      expect_ai_reply({:ok, plan_json()})
      {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, company).id)
      generated_site(scope, company)
      generated = latest(scope, company, :site_generated)

      assert Sites.undoable_entry(scope, company) == nil
      assert {:error, :not_undoable} = Sites.undo(scope, company, generated.id)
    end

    test "refuses another owner's entry", %{company: company, entry: entry} do
      other_scope = user_scope_fixture()
      other_company = company_fixture(other_scope)
      expect_ai_reply({:ok, plan_json()})
      {:ok, _plan} = Plans.generate_plan(Plans.current_plan(other_scope, other_company).id)
      other_site = generated_site(other_scope, other_company)

      {:ok, _edited} =
        Sites.update_content(other_scope, other_site, %{"hero" => %{"headline" => "Inny"}})

      assert {:error, :not_found} = Sites.undo(other_scope, other_company, entry.id)
      assert {:error, :not_found} = Sites.undo(other_scope, company, entry.id)
      assert Sites.undoable_entry(other_scope, company) == nil
    end

    test "refuses the owner's entry from another of their companies",
         %{scope: scope, company: company, entry: entry} do
      other_company = company_fixture(scope, "Kawiarnia z wypiekami w Gdańsku, otwarta od rana.")
      expect_ai_reply({:ok, plan_json()})
      {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, other_company).id)
      generated_site(scope, other_company)

      assert {:error, :not_found} = Sites.undo(scope, other_company, entry.id)
      assert Sites.get_site(scope, company).current_version.number == 2
    end

    test "undoing a draft-only edit keeps the published version",
         %{scope: scope, company: company, site: site} do
      {:ok, site} = Sites.set_slug(scope, site, "piekarnia")
      {:ok, published} = Sites.publish(scope, site)

      {:ok, _draft} =
        Sites.update_content(scope, published, %{"hero" => %{"headline" => "Szkic"}})

      draft_entry = latest(scope, company, :site_updated)

      {:ok, undone} = Sites.undo(scope, company, draft_entry.id)

      assert undone.published_version_id == published.published_version_id
      assert undone.current_version.content.hero.headline == "Nowy"
    end

    test "undoing a publish puts back the previously published content",
         %{scope: scope, company: company, site: site} do
      {:ok, site} = Sites.set_slug(scope, site, "piekarnia")
      {:ok, site} = Sites.publish(scope, site)
      {:ok, site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Trzeci"}})
      {:ok, _published} = Sites.publish(scope, site)
      published_entry = latest(scope, company, :site_published)

      {:ok, undone} = Sites.undo(scope, company, published_entry.id)
      {:ok, public} = Sites.get_published_by_slug("piekarnia")

      assert undone.published_version_id == undone.current_version_id
      assert public.published_version.content.hero.headline == "Nowy"
    end

    test "the first publication can't be undone", %{scope: scope, company: company, site: site} do
      {:ok, site} = Sites.set_slug(scope, site, "piekarnia")
      {:ok, _published} = Sites.publish(scope, site)
      published_entry = latest(scope, company, :site_published)

      assert published_entry.metadata["previous_published_version_id"] == nil
      assert Sites.undoable_entry(scope, company) == nil
      assert {:error, :not_undoable} = Sites.undo(scope, company, published_entry.id)
    end

    test "falls back to the previous publication for entries without the metadata",
         %{scope: scope, company: company, site: site} do
      {:ok, site} = Sites.set_slug(scope, site, "piekarnia")
      {:ok, site} = Sites.publish(scope, site)
      {:ok, site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Trzeci"}})
      {:ok, _published} = Sites.publish(scope, site)
      entry = latest(scope, company, :site_published)

      Repo.update_all(from(e in Firmos.Activity.Entry, where: e.id == ^entry.id),
        set: [metadata: %{"slug" => "piekarnia", "version" => 3}]
      )

      {:ok, undone} = Sites.undo(scope, company, entry.id)

      assert undone.current_version.content.hero.headline == "Nowy"
    end

    test "the exact repro: edit, undo, publish, undo never makes the bad edit live" do
      scope = user_scope_fixture()
      company = company_fixture(scope)
      expect_ai_reply({:ok, plan_json()})
      {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, company).id)
      {:ok, site} = Sites.set_slug(scope, generated_site(scope, company), "probe")
      {:ok, _v1_live} = Sites.publish(scope, site)

      {:ok, _v2} =
        Sites.update_content(scope, Sites.get_site(scope, company), %{
          "hero" => %{"headline" => "BAD EDIT"}
        })

      {:ok, _v3} = Sites.undo(scope, company, Sites.undoable_entry(scope, company).id)
      {:ok, _v3_live} = Sites.publish(scope, Sites.get_site(scope, company))
      {:ok, _v4} = Sites.undo(scope, company, Sites.undoable_entry(scope, company).id)
      {:ok, public} = Sites.get_published_by_slug("probe")

      assert public.published_version.content.hero.headline == site_attrs()["hero"]["headline"]
    end

    test "broadcasts the restored site", %{scope: scope, company: company, entry: entry} do
      :ok = Sites.subscribe(scope, company)
      {:ok, site} = Sites.undo(scope, company, entry.id)

      assert_receive {:site_updated, %{current_version_id: id}} when id == site.current_version_id
    end
  end

  describe "sites table" do
    test "deleting the company deletes its site and versions", %{scope: scope, company: company} do
      generated_site(scope, company)
      Repo.delete!(company)

      assert Repo.aggregate(Site, :count) == 0
      assert Repo.aggregate(Version, :count) == 0
    end

    test "a site can't point at another site's version", %{scope: scope, company: company} do
      other_scope = user_scope_fixture()
      other_company = company_fixture(other_scope)
      expect_ai_reply({:ok, plan_json()})
      {:ok, _plan} = Plans.generate_plan(Plans.current_plan(other_scope, other_company).id)
      other = generated_site(other_scope, other_company)
      site = generated_site(scope, company)

      assert {:error, changeset} =
               site
               |> Site.current_version_changeset(%Version{id: other.current_version_id})
               |> Repo.update()

      assert %{current_version_id: [_]} = errors_on(changeset)
    end

    test "rejects a slug that isn't a valid subdomain", %{scope: scope, company: company} do
      site = generated_site(scope, company)

      assert_raise Postgrex.Error, ~r/sites_slug_format/, fn ->
        Repo.update_all(from(s in Site, where: s.id == ^site.id), set: [slug: "Zła_nazwa"])
      end
    end
  end
end
