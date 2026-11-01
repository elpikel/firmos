defmodule FirmosWeb.SiteDomainTest do
  use ExUnit.Case, async: true

  alias FirmosWeb.SiteDomain

  describe "slug_from_host/1" do
    test "takes one valid label in front of the base domain" do
      assert SiteDomain.slug_from_host("piekarnia.localhost") == {:ok, "piekarnia"}
    end

    test "is case-insensitive and ignores a trailing dot" do
      assert SiteDomain.slug_from_host("PieKarnia.LOCALHOST.") == {:ok, "piekarnia"}
    end

    for host <- [
          "localhost",
          "www.localhost",
          "app.localhost",
          "a.b.localhost",
          "piekarnia.localhost.evil.com",
          "piekarnialocalhost",
          "pie_karnia.localhost",
          "-piekarnia.localhost",
          ".localhost",
          "xn--pekarnia-9ib.localhost",
          "example.com"
        ] do
      test "leaves #{inspect(host)} to the app" do
        assert SiteDomain.slug_from_host(unquote(host)) == :error
      end
    end
  end

  describe "slug_from_host/2 with the app on a subdomain" do
    test "never reads the app's own host as a site" do
      assert SiteDomain.slug_from_host("moja-firma.firmos.pl",
               base_domain: "firmos.pl",
               app_host: "Moja-Firma.firmos.pl."
             ) == :error
    end

    test "still serves other sites under the same base domain" do
      assert SiteDomain.slug_from_host("piekarnia.firmos.pl",
               base_domain: "firmos.pl",
               app_host: "moja-firma.firmos.pl"
             ) == {:ok, "piekarnia"}
    end
  end

  test "public_url/1 uses the endpoint's scheme and port" do
    assert SiteDomain.public_url("piekarnia") =~ ~r{\Ahttp://piekarnia\.localhost(:\d+)?\z}
  end
end
