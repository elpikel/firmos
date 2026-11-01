defmodule Firmos.Sites.Slug do
  @moduledoc """
  The rules for a site's slug, the label of its public address
  (`<slug>.firmos.pl`).

  One place for both sides of the address: `Firmos.Sites.Site` validates an
  owner's slug with them, and the public host plug only takes a host label
  that is `public?/1`, so a reserved name (`www`, `app`, ...) always reaches
  the app, never a site.

  The format matches the `sites_slug_format` CHECK (lowercase letters,
  digits and inner hyphens, at most 63 characters), plus a minimum length
  of three characters, so short names stay free. Punycode labels
  (`xn--...`) are refused: they render as Unicode in browsers and could
  imitate another site's address.
  """

  @format ~r/\A[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?\z/
  @min_length 3
  @max_length 63

  @reserved ~w(
    www app api admin administrator mail email smtp imap pop ftp static assets cdn
    media img images files firmos help support status blog docs dev test staging
    beta demo dashboard account accounts login logout auth oauth sso panel
    root system webmail ns ns1 ns2 mx localhost
  )

  @doc "The slug format (the database CHECK, as a regex)."
  @spec format() :: Regex.t()
  def format, do: @format

  @doc "The minimum slug length."
  @spec min_length() :: pos_integer()
  def min_length, do: @min_length

  @doc "The maximum slug length (a DNS label)."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc "Names no site can take: they belong to the platform."
  @spec reserved() :: [String.t()]
  def reserved, do: @reserved

  @doc "Trims and downcases what the owner typed."
  @spec normalize(String.t()) :: String.t()
  def normalize(slug) when is_binary(slug), do: slug |> String.trim() |> String.downcase()

  @doc "Whether `slug` is a reserved name."
  @spec reserved?(String.t()) :: boolean()
  def reserved?(slug) when is_binary(slug), do: slug in @reserved

  @doc "Whether `slug` is a punycode (internationalized, `xn--`) label."
  @spec punycode?(String.t()) :: boolean()
  def punycode?(slug) when is_binary(slug), do: String.starts_with?(slug, "xn--")

  @doc """
  Whether `label` (already lowercase) could be a site's slug: the right
  format and length, not punycode and not reserved.
  """
  @spec public?(String.t()) :: boolean()
  def public?(label) when is_binary(label) do
    String.length(label) >= @min_length and label =~ @format and not punycode?(label) and
      not reserved?(label)
  end
end
