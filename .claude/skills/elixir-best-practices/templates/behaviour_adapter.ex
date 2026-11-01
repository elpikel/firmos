# Behaviour + Req adapter + Mox — idioms.md §14.
#
# AGENTS.md: one module per file. Split this template into:
#   lib/firmos/payments/gateway.ex        (behaviour + dispatch)
#   lib/firmos/payments/stripe_gateway.ex (Req implementation)
#
# ---------------------------------------------------------------------------
# lib/firmos/payments/gateway.ex
# ---------------------------------------------------------------------------
defmodule Firmos.Payments.Gateway do
  @moduledoc """
  Contract for charging money. The domain depends on this, never on HTTP.

  The implementation is chosen by config (compile-time static choice is fine;
  credentials are runtime):

      # config/config.exs
      config :firmos, :payment_gateway, Firmos.Payments.StripeGateway

      # config/test.exs
      config :firmos, :payment_gateway, Firmos.Payments.GatewayMock

      # config/runtime.exs
      if config_env() == :prod do
        config :firmos, Firmos.Payments.StripeGateway,
          base_url: "https://api.stripe.com",
          api_key: System.fetch_env!("STRIPE_API_KEY")
      end

  Tests (add `{:mox, "~> 1.2", only: :test}` to mix.exs):

      # test/test_helper.exs
      Mox.defmock(Firmos.Payments.GatewayMock, for: Firmos.Payments.Gateway)

      # in a test
      import Mox
      setup :verify_on_exit!

      test "charges the order total" do
        expect(Firmos.Payments.GatewayMock, :charge, fn 2000, "EUR", _opts ->
          {:ok, %{id: "ch_1"}}
        end)

        assert {:ok, _order} = Orders.pay(order)
      end
  """

  @type charge :: %{id: String.t()}
  @type error :: :card_declined | :upstream_unavailable

  @callback charge(amount :: pos_integer(), currency :: String.t(), opts :: keyword()) ::
              {:ok, charge()} | {:error, error()}

  @doc "Dispatches to the configured implementation."
  @spec charge(pos_integer(), String.t(), keyword()) :: {:ok, charge()} | {:error, error()}
  def charge(amount, currency, opts \\ []), do: impl().charge(amount, currency, opts)

  defp impl, do: Application.fetch_env!(:firmos, :payment_gateway)
end

# ---------------------------------------------------------------------------
# lib/firmos/payments/stripe_gateway.ex
# ---------------------------------------------------------------------------
defmodule Firmos.Payments.StripeGateway do
  @moduledoc """
  Req implementation of `Firmos.Payments.Gateway`.
  Translates HTTP results into domain reasons — `%Req.Response{}` never escapes.
  """

  @behaviour Firmos.Payments.Gateway

  require Logger

  @impl Firmos.Payments.Gateway
  def charge(amount, currency, opts) do
    case Req.post(client(), url: "/v1/charges", form: [amount: amount, currency: currency]) do
      {:ok, %Req.Response{status: 200, body: %{"id" => id}}} ->
        {:ok, %{id: id}}

      {:ok, %Req.Response{status: 402}} ->
        {:error, :card_declined}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("payment gateway error", status: status, ref: opts[:ref])
        {:error, :upstream_unavailable}

      {:error, exception} ->
        Logger.warning("payment gateway unreachable", reason: Exception.message(exception))
        {:error, :upstream_unavailable}
    end
  end

  # Config is read at call time, so runtime.exs values apply (idioms.md §15).
  defp client do
    config = Application.fetch_env!(:firmos, __MODULE__)

    Req.new(
      base_url: Keyword.fetch!(config, :base_url),
      auth: {:bearer, Keyword.fetch!(config, :api_key)},
      receive_timeout: 10_000,
      retry: :transient,
      max_retries: 2
    )
  end
end
