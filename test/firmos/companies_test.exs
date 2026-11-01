defmodule Firmos.CompaniesTest do
  use Firmos.DataCase, async: true

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures

  alias Firmos.Companies
  alias Firmos.Ideas

  @default_name "Moja firma"

  setup do
    %{scope: user_scope_fixture()}
  end

  describe "ensure_company_from_idea/2" do
    test "creates a company from an unclaimed idea", %{scope: scope} do
      {:ok, idea} = Ideas.create_for_user(scope, %{text: valid_idea_text()})

      assert {:ok, [company]} = Companies.ensure_company_from_idea(scope, @default_name)
      assert company.idea_id == idea.id
      assert company.description == valid_idea_text()
      assert company.user_id == scope.user.id
      assert company.name == @default_name
    end

    test "turns every unclaimed idea into a company in one call, newest first", %{scope: scope} do
      {:ok, older} = Ideas.create_for_user(scope, %{text: "Starszy pomysł na sklep z rowerami."})
      {:ok, newer} = Ideas.create_for_user(scope, %{text: valid_idea_text()})

      assert {:ok, [_, _]} = Companies.ensure_company_from_idea(scope, @default_name)
      assert Enum.map(Companies.list_companies(scope), & &1.idea_id) == [newer.id, older.id]
      assert Companies.latest_company(scope).idea_id == newer.id
    end

    test "returns no companies without an unclaimed idea", %{scope: scope} do
      assert Companies.ensure_company_from_idea(scope, @default_name) == {:ok, []}
      assert Companies.list_companies(scope) == []
    end

    test "is idempotent", %{scope: scope} do
      {:ok, _idea} = Ideas.create_for_user(scope, %{text: valid_idea_text()})

      assert {:ok, [_company]} = Companies.ensure_company_from_idea(scope, @default_name)
      assert Companies.ensure_company_from_idea(scope, @default_name) == {:ok, []}
      assert length(Companies.list_companies(scope)) == 1
    end

    test "skips ideas another caller claimed first", %{scope: scope} do
      {:ok, idea} = Ideas.create_for_user(scope, %{text: valid_idea_text()})
      # Simulates the losing side of the race: the idea was read as unclaimed,
      # but someone else claimed it before this transaction did.
      {:ok, _claimed} = Ideas.claim(scope, idea)

      assert {:error, :already_claimed} = Ideas.claim(scope, idea)
      assert Companies.ensure_company_from_idea(scope, @default_name) == {:ok, []}
      assert Companies.list_companies(scope) == []
    end

    test "ignores other owners' ideas", %{scope: scope} do
      other_scope = user_scope_fixture()
      {:ok, _idea} = Ideas.create_for_user(other_scope, %{text: valid_idea_text()})

      assert Companies.ensure_company_from_idea(scope, @default_name) == {:ok, []}
    end
  end

  describe "latest_company/1" do
    test "is nil without companies", %{scope: scope} do
      refute Companies.latest_company(scope)
    end

    test "ignores other owners' companies", %{scope: scope} do
      _other = company_fixture(user_scope_fixture())

      refute Companies.latest_company(scope)
    end
  end

  describe "Ideas.claim/2" do
    test "refuses another owner's idea", %{scope: scope} do
      {:ok, idea} = Ideas.create_for_user(user_scope_fixture(), %{text: valid_idea_text()})

      assert {:error, :already_claimed} = Ideas.claim(scope, idea)
    end
  end

  describe "list_companies/1" do
    test "returns only the owner's companies, newest first", %{scope: scope} do
      first = company_fixture(scope)
      second = company_fixture(scope, "Drugi pomysł: kawiarnia z planszówkami w Poznaniu.")
      _other = company_fixture(user_scope_fixture())

      assert Enum.map(Companies.list_companies(scope), & &1.id) == [second.id, first.id]
    end
  end

  describe "get_company!/2" do
    test "returns the owner's company", %{scope: scope} do
      company = company_fixture(scope)

      assert Companies.get_company!(scope, company.id).id == company.id
    end

    test "raises for another owner's company", %{scope: scope} do
      company = company_fixture(user_scope_fixture())

      assert_raise Ecto.NoResultsError, fn -> Companies.get_company!(scope, company.id) end
    end
  end

  describe "update_company/3" do
    setup %{scope: scope} do
      %{company: company_fixture(scope)}
    end

    test "updates and trims the profile basics", %{scope: scope, company: company} do
      assert {:ok, updated} =
               Companies.update_company(scope, company, %{
                 name: "  Piekarnia Pod Wawelem ",
                 industry: "Piekarnictwo",
                 city: "Kraków",
                 contact_email: "kontakt@piekarnia.pl"
               })

      assert updated.name == "Piekarnia Pod Wawelem"
      assert updated.contact_email == "kontakt@piekarnia.pl"
    end

    test "requires a name", %{scope: scope, company: company} do
      assert {:error, changeset} = Companies.update_company(scope, company, %{name: "   "})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a malformed contact email", %{scope: scope, company: company} do
      assert {:error, changeset} =
               Companies.update_company(scope, company, %{contact_email: "not an email"})

      assert %{contact_email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "caps field length", %{scope: scope, company: company} do
      assert {:error, changeset} =
               Companies.update_company(scope, company, %{city: String.duplicate("ż", 161)})

      assert %{city: ["should be at most 160 character(s)"]} = errors_on(changeset)
    end

    test "never casts ownership or the idea", %{scope: scope, company: company} do
      other_scope = user_scope_fixture()

      {:ok, updated} =
        Companies.update_company(scope, company, %{
          "user_id" => other_scope.user.id,
          "idea_id" => nil,
          "description" => "Podmieniony opis"
        })

      assert {updated.user_id, updated.idea_id, updated.description} ==
               {company.user_id, company.idea_id, company.description}
    end

    test "refuses another owner's company", %{company: company} do
      assert_raise FunctionClauseError, fn ->
        Companies.update_company(user_scope_fixture(), company, %{name: "Przejęta"})
      end
    end
  end
end
