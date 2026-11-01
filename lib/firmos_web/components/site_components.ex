defmodule FirmosWeb.SiteComponents do
  @moduledoc """
  Renders a company's landing page from its `Firmos.Sites.Content`.

  `landing/1` is the one renderer for a site: the owner's draft preview and
  the public page on `<slug>.firmos.pl` (STORY-009) both use it, so the
  preview shows exactly what customers see.

  The content is AI- or owner-written text, so it is only ever interpolated
  (HEEx escapes it); there is no `raw/1` here. The only links are our own
  `#site-contact` anchor and `mailto:` / `tel:` URLs built by
  `Firmos.Sites.Content.Contact` from validated values.
  """
  use FirmosWeb, :html

  alias Firmos.Sites.Content
  alias Firmos.Sites.Content.Contact

  @doc "The full landing page: hero, offer, pricing and contact sections."
  attr :content, Content, required: true
  attr :name, :string, required: true, doc: "the company's name"

  def landing(assigns) do
    ~H"""
    <div id="site-landing" class="min-h-screen bg-stone-50 text-stone-900 antialiased">
      <.hero hero={@content.hero} name={@name} />
      <.offer offer={@content.offer} />
      <.pricing pricing={@content.pricing} />
      <.contact contact={@content.contact} name={@name} />
    </div>
    """
  end

  attr :hero, Content.Hero, required: true
  attr :name, :string, required: true

  defp hero(assigns) do
    ~H"""
    <section id="site-hero" class="relative isolate overflow-hidden bg-stone-950 text-white">
      <div
        aria-hidden="true"
        class="absolute -top-40 left-1/2 -z-10 size-[42rem] -translate-x-1/2 rounded-full bg-gradient-to-br from-amber-400/30 via-rose-500/20 to-transparent blur-3xl"
      >
      </div>
      <div class="mx-auto max-w-5xl px-6 py-24 sm:py-32">
        <p class="text-sm font-semibold uppercase tracking-[0.2em] text-amber-300">{@name}</p>
        <h1 class="mt-6 max-w-3xl text-4xl font-semibold tracking-tight text-balance sm:text-6xl">
          {@hero.headline}
        </h1>
        <p class="mt-6 max-w-2xl text-lg leading-relaxed text-stone-300">{@hero.subheadline}</p>
        <a
          id="site-cta"
          href="#site-contact"
          class="mt-10 inline-flex items-center gap-2 rounded-full bg-amber-400 px-6 py-3 text-sm font-semibold text-stone-950 shadow-lg shadow-amber-500/20 transition hover:-translate-y-0.5 hover:bg-amber-300 active:translate-y-0"
        >
          {@hero.cta_label}
          <.icon name="hero-arrow-right" class="size-4" />
        </a>
      </div>
    </section>
    """
  end

  attr :offer, Content.Offer, required: true

  defp offer(assigns) do
    ~H"""
    <section id="site-offer" class="mx-auto max-w-5xl px-6 py-20">
      <h2 class="text-3xl font-semibold tracking-tight">{@offer.title}</h2>
      <ul class="mt-10 grid gap-6 sm:grid-cols-2">
        <li
          :for={item <- @offer.items}
          class="rounded-2xl border border-stone-200 bg-white p-6 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
        >
          <h3 class="text-lg font-semibold">{item.name}</h3>
          <p class="mt-2 leading-relaxed text-stone-600">{item.description}</p>
        </li>
      </ul>
    </section>
    """
  end

  attr :pricing, Content.Pricing, required: true

  defp pricing(assigns) do
    ~H"""
    <section id="site-pricing" class="border-y border-stone-200 bg-white">
      <div class="mx-auto max-w-5xl px-6 py-20">
        <h2 class="text-3xl font-semibold tracking-tight">{@pricing.title}</h2>
        <ul class="mt-10 divide-y divide-stone-200">
          <li
            :for={item <- @pricing.items}
            class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1 py-5"
          >
            <div>
              <p class="font-semibold">{item.name}</p>
              <p :if={item.note} class="text-sm text-stone-500">{item.note}</p>
            </div>
            <p class="text-xl font-semibold tabular-nums text-amber-700">{item.price}</p>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  attr :contact, Contact, required: true
  attr :name, :string, required: true

  defp contact(assigns) do
    assigns =
      assigns
      |> assign(:mailto, Contact.mailto(assigns.contact.email))
      |> assign(:tel, Contact.tel(assigns.contact.phone))

    ~H"""
    <section id="site-contact" class="mx-auto max-w-5xl px-6 py-20">
      <div class="rounded-3xl bg-stone-950 px-8 py-12 text-white sm:px-12">
        <h2 class="text-3xl font-semibold tracking-tight">{@contact.title}</h2>
        <p class="mt-4 max-w-2xl text-lg leading-relaxed text-stone-300">{@contact.text}</p>
        <ul class="mt-8 flex flex-wrap gap-3 text-sm">
          <.contact_detail
            :if={@contact.email}
            id="site-contact-email"
            icon="hero-envelope"
            href={@mailto}
            text={@contact.email}
          />
          <.contact_detail
            :if={@contact.phone}
            id="site-contact-phone"
            icon="hero-phone"
            href={@tel}
            text={@contact.phone}
          />
          <.contact_detail
            :if={@contact.city}
            id="site-contact-city"
            icon="hero-map-pin"
            text={@contact.city}
          />
        </ul>
      </div>
      <footer class="mt-12 text-center text-sm text-stone-500">© {@name}</footer>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :href, :string, default: nil, doc: "a validated mailto:/tel: URL, or nil for plain text"
  attr :text, :string, required: true

  defp contact_detail(assigns) do
    ~H"""
    <li id={@id}>
      <a
        :if={@href}
        href={@href}
        class="inline-flex items-center gap-2 rounded-full bg-white/10 px-4 py-2 font-medium transition hover:bg-white/20"
      >
        <.icon name={@icon} class="size-4" /> {@text}
      </a>
      <span
        :if={is_nil(@href)}
        class="inline-flex items-center gap-2 rounded-full bg-white/5 px-4 py-2 text-stone-300"
      >
        <.icon name={@icon} class="size-4" /> {@text}
      </span>
    </li>
    """
  end
end
