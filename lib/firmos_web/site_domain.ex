defmodule FirmosWeb.SiteDomain do
  @moduledoc """
  Public site addresses: `<slug>.<base domain>`.

  The base domain is runtime config (`config :firmos, :sites_base_domain`:
  `localhost` in dev and test, `SITES_BASE_DOMAIN` or `PHX_HOST` in prod).
  `slug_from_host/1` decides which hosts are sites; `public_url/1` builds a
  site's address with the endpoint's scheme and port.
  """

  alias Firmos.Sites.Slug

  @doc "The domain sites live under, e.g. `firmos.pl`."
  @spec base_domain() :: String.t()
  def base_domain, do: Application.fetch_env!(:firmos, :sites_base_domain)

  @doc """
  The slug a request `host` addresses: `{:ok, slug}` only for exactly one
  label in front of the base domain that could be a site's slug
  (`Firmos.Sites.Slug.public?/1`). The endpoint's own host, the bare base
  domain, reserved and punycode labels, deeper names and other hosts are
  `:error`: they belong to the app. `opts` override the configured
  `:base_domain` and `:app_host` (for tests).
  """
  @spec slug_from_host(String.t(), base_domain: String.t(), app_host: String.t() | nil) ::
          {:ok, String.t()} | :error
  def slug_from_host(host, opts \\ []) when is_binary(host) do
    base = Keyword.get_lazy(opts, :base_domain, &base_domain/0)
    app_host = opts |> Keyword.get_lazy(:app_host, &app_host/0) |> normalize_host()
    suffix = "." <> base
    host = normalize_host(host)

    with false <- host == app_host,
         true <- String.ends_with?(host, suffix),
         label = binary_part(host, 0, byte_size(host) - byte_size(suffix)),
         true <- Slug.public?(label) do
      {:ok, label}
    else
      _app_host -> :error
    end
  end

  # The endpoint's own host is always the app, even when it looks like
  # `<label>.<base domain>` (e.g. the app on `panel.firmos.pl`).
  defp app_host, do: FirmosWeb.Endpoint.config(:url)[:host]

  defp normalize_host(nil), do: nil
  defp normalize_host(host), do: host |> String.trim_trailing(".") |> String.downcase()

  @doc "The public address of the site at `slug`, e.g. `https://piekarnia.firmos.pl`."
  @spec public_url(String.t()) :: String.t()
  def public_url(slug) when is_binary(slug) do
    FirmosWeb.Endpoint.struct_url()
    |> Map.put(:host, "#{slug}.#{base_domain()}")
    |> URI.to_string()
  end
end
