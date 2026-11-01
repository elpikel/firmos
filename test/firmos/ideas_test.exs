defmodule Firmos.IdeasTest do
  use Firmos.DataCase, async: true

  import Firmos.AccountsFixtures

  alias Firmos.Accounts.Scope
  alias Firmos.Ideas
  alias Firmos.Ideas.Idea

  @valid_text "Sklep z rowerami cargo dla rodzin w Gdańsku."

  defp errors(changeset), do: errors_on(changeset).text

  describe "create_draft/1" do
    test "saves an unattached draft with a URL-safe token" do
      assert {:ok, %Idea{user_id: nil, token: token, text: @valid_text}} =
               Ideas.create_draft(%{"text" => @valid_text})

      assert token =~ ~r/\A[A-Za-z0-9_-]{43}\z/
    end

    test "trims surrounding whitespace" do
      assert {:ok, %Idea{text: @valid_text}} =
               Ideas.create_draft(%{"text" => "  \n#{@valid_text}\t "})
    end

    test "accepts exactly 20 and 2000 characters" do
      assert {:ok, _} = Ideas.create_draft(%{"text" => String.duplicate("ą", 20)})
      assert {:ok, _} = Ideas.create_draft(%{"text" => String.duplicate("ą", 2000)})
    end

    test "rejects 19 characters, counted after trimming" do
      padded = "   " <> String.duplicate("a", 19) <> "   "
      assert {:error, changeset} = Ideas.create_draft(%{"text" => padded})

      assert errors(changeset) == [
               "is too short, please give more detail (at least 20 characters)"
             ]
    end

    test "rejects 2001 characters" do
      assert {:error, changeset} = Ideas.create_draft(%{"text" => String.duplicate("a", 2001)})
      assert errors(changeset) == ["is too long, maximum 2000 characters"]
    end

    test "rejects a NUL byte instead of crashing on insert" do
      text = "Piekarnia w Krakowie" <> <<0>> <> " z dostawą"
      assert {:error, changeset} = Ideas.create_draft(%{"text" => text})
      assert errors(changeset) == ["contains characters that are not allowed"]
    end

    test "rejects a blank idea" do
      assert {:error, changeset} = Ideas.create_draft(%{"text" => "   "})
      assert errors(changeset) == ["can't be blank"]
    end

    test "ignores user_id and token from params" do
      user = user_fixture()

      assert {:ok, idea} =
               Ideas.create_draft(%{"text" => @valid_text, "user_id" => user.id, "token" => "x"})

      assert idea.user_id == nil
      refute idea.token == "x"
    end
  end

  describe "get_draft_by_token/1" do
    test "returns the unattached draft" do
      {:ok, idea} = Ideas.create_draft(%{"text" => @valid_text})
      assert %Idea{id: id} = Ideas.get_draft_by_token(idea.token)
      assert id == idea.id
    end

    test "returns nil for unknown, blank or non-string tokens" do
      refute Ideas.get_draft_by_token("nope")
      refute Ideas.get_draft_by_token("")
      refute Ideas.get_draft_by_token(nil)
      refute Ideas.get_draft_by_token(["x"])
    end

    test "returns nil once the draft is attached" do
      {:ok, idea} = Ideas.create_draft(%{"text" => @valid_text})
      {:ok, _} = Ideas.attach_to_user(Scope.for_user(user_fixture()), idea.token)

      refute Ideas.get_draft_by_token(idea.token)
    end
  end

  describe "attach_to_user/2" do
    test "attaches the draft to the scope's user" do
      user = user_fixture()
      {:ok, idea} = Ideas.create_draft(%{"text" => @valid_text})

      assert {:ok, %Idea{id: id, user_id: user_id}} =
               Ideas.attach_to_user(Scope.for_user(user), idea.token)

      assert {id, user_id} == {idea.id, user.id}
    end

    test "cannot steal a draft already attached to another user" do
      {:ok, idea} = Ideas.create_draft(%{"text" => @valid_text})
      owner = user_fixture()
      {:ok, _} = Ideas.attach_to_user(Scope.for_user(owner), idea.token)

      assert {:error, :not_found} =
               Ideas.attach_to_user(Scope.for_user(user_fixture()), idea.token)

      assert Repo.get!(Idea, idea.id).user_id == owner.id
    end

    test "returns :not_found for an unknown or missing token" do
      scope = Scope.for_user(user_fixture())
      assert {:error, :not_found} = Ideas.attach_to_user(scope, "nope")
      assert {:error, :not_found} = Ideas.attach_to_user(scope, nil)
    end
  end

  describe "create_for_user/2 and latest_unclaimed_for_user/1" do
    test "attaches the idea to the owner and returns the latest unclaimed one" do
      scope = Scope.for_user(user_fixture())
      {:ok, _older} = Ideas.create_for_user(scope, %{"text" => @valid_text})

      {:ok, newer} =
        Ideas.create_for_user(scope, %{"text" => "Druga firma: kawiarnia z książkami."})

      assert Ideas.latest_unclaimed_for_user(scope).id == newer.id
    end

    test "skips claimed ideas" do
      scope = Scope.for_user(user_fixture())
      {:ok, idea} = Ideas.create_for_user(scope, %{"text" => @valid_text})
      idea |> Ecto.Changeset.change(claimed_at: DateTime.utc_now(:second)) |> Repo.update!()

      refute Ideas.latest_unclaimed_for_user(scope)
    end

    test "never returns another owner's idea" do
      {:ok, _} = Ideas.create_for_user(Scope.for_user(user_fixture()), %{"text" => @valid_text})

      refute Ideas.latest_unclaimed_for_user(Scope.for_user(user_fixture()))
    end
  end

  test "inspect does not leak the token" do
    {:ok, idea} = Ideas.create_draft(%{"text" => @valid_text})
    refute inspect(idea) =~ idea.token
  end
end
