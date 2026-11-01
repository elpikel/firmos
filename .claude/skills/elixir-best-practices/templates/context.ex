defmodule Firmos.Carts do
  @moduledoc """
  The Carts context — the only public entry point to carts and their items.

  Template rules encoded here:
    * web layer calls these functions, never `Repo` (idioms.md §8)
    * untrusted attrs enter only through changesets (§9)
    * programmatic fields (`cart_id`, `user_id`) are set, never cast (§9)
    * named bindings in every query (§10), preloads in the context (§11)
    * expected failures return tagged tuples (§1); `!` only where 404 is right (§3)
    * multi-write operations use `Ecto.Multi` (§12)
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Firmos.Carts.Cart
  alias Firmos.Carts.Item
  alias Firmos.Repo

  @type id :: pos_integer()

  # -- Queries --------------------------------------------------------------

  @doc "Lists a user's carts, newest first, with items preloaded."
  @spec list_carts(id()) :: [Cart.t()]
  def list_carts(user_id) do
    base_query()
    |> where([cart: c], c.user_id == ^user_id)
    |> order_by([cart: c], desc: c.inserted_at)
    |> preload(:items)
    |> Repo.all()
  end

  @doc "Gets a cart or raises `Ecto.NoResultsError` (rendered as 404 by Phoenix)."
  @spec get_cart!(id()) :: Cart.t()
  def get_cart!(id), do: base_query() |> preload(:items) |> Repo.get!(id)

  @doc "Fetches a cart; for call sites where absence is an expected outcome."
  @spec fetch_cart(id()) :: {:ok, Cart.t()} | {:error, :not_found}
  def fetch_cart(id) do
    case base_query() |> preload(:items) |> Repo.get(id) do
      nil -> {:error, :not_found}
      %Cart{} = cart -> {:ok, cart}
    end
  end

  defp base_query, do: from(c in Cart, as: :cart)

  # -- Commands -------------------------------------------------------------

  @spec create_cart(id(), map()) :: {:ok, Cart.t()} | {:error, Ecto.Changeset.t()}
  def create_cart(user_id, attrs \\ %{}) do
    %Cart{user_id: user_id}
    |> Cart.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_cart(Cart.t(), map()) :: {:ok, Cart.t()} | {:error, Ecto.Changeset.t()}
  def update_cart(%Cart{} = cart, attrs) do
    cart
    |> Cart.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_cart(Cart.t()) :: {:ok, Cart.t()} | {:error, Ecto.Changeset.t()}
  def delete_cart(%Cart{} = cart), do: Repo.delete(cart)

  @doc "Returns a changeset for forms (`to_form/1` in the LiveView)."
  @spec change_cart(Cart.t(), map()) :: Ecto.Changeset.t()
  def change_cart(%Cart{} = cart, attrs \\ %{}), do: Cart.changeset(cart, attrs)

  @spec add_item(Cart.t(), map()) :: {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def add_item(%Cart{id: cart_id}, attrs) do
    %Item{cart_id: cart_id}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Checks a cart out: marks it as ordered and empties its items, atomically.
  Returns the step that failed so callers can pattern-match on it.
  """
  @spec checkout(Cart.t()) ::
          {:ok, Cart.t()} | {:error, :empty_cart} | {:error, Ecto.Changeset.t()}
  def checkout(%Cart{items: []}), do: {:error, :empty_cart}

  def checkout(%Cart{} = cart) do
    items_query = from(i in Item, as: :item, where: i.cart_id == ^cart.id)

    Multi.new()
    |> Multi.update(:cart, Cart.checkout_changeset(cart))
    |> Multi.delete_all(:items, items_query)
    |> Repo.transact()
    |> case do
      {:ok, %{cart: cart}} -> {:ok, %{cart | items: []}}
      {:error, :cart, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
    end
  end
end
