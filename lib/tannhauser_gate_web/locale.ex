defmodule TannhauserGateWeb.Locale do
  @moduledoc "Initializes the browser-session language for HTTP and LiveView processes."
  import Plug.Conn

  @locales ~w(en it es pt_PT)
  @languages [
    {"English", "en"},
    {"Italiano", "it"},
    {"Español", "es"},
    {"Português (Portugal)", "pt_PT"}
  ]

  def languages, do: @languages
  def normalize(locale) when locale in @locales, do: locale
  def normalize(_locale), do: "en"
  def current, do: Gettext.get_locale(TannhauserGateWeb.Gettext)
  def html_language, do: String.replace(current(), "_", "-")

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = normalize(get_session(conn, :locale))
    Gettext.put_locale(TannhauserGateWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = normalize(session["locale"])
    Gettext.put_locale(TannhauserGateWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
