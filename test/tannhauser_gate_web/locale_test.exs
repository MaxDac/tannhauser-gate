defmodule TannhauserGateWeb.LocaleTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGateWeb.{CoreComponents, Locale}

  @languages [
    {"en", "en", "Support on Ko-fi", "Change language"},
    {"it", "it", "Sostieni su Ko-fi", "Cambia lingua"},
    {"es", "es", "Apoya en Ko-fi", "Cambiar idioma"},
    {"pt_PT", "pt-PT", "Apoiar no Ko-fi", "Alterar idioma"}
  ]

  for {locale, html_lang, support, change} <- @languages do
    test "#{locale} persists through HTTP, connected LiveView, and reconnects", %{conn: conn} do
      conn =
        post(conn, ~p"/locale", locale: unquote(locale), return_to: "/users/log_in")

      assert get_session(conn, :locale) == unquote(locale)
      assert redirected_to(conn) == "/users/log_in"

      conn = get(recycle(conn), ~p"/users/log_in")
      document = conn |> html_response(200) |> LazyHTML.from_document()
      assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == [unquote(html_lang)]

      {:ok, view, _html} = live(conn)

      assert has_element?(
               view,
               "#donation-link[href='https://ko-fi.com/maxdac']",
               unquote(support)
             )

      assert has_element?(view, "#language-submit", unquote(change))
      assert has_element?(view, "#language-select option[value='#{unquote(locale)}'][selected]")
      assert has_element?(view, "#login_form")
      assert has_element?(view, "#donation-link[target='_blank'][rel='noopener noreferrer']")

      login =
        Gettext.with_locale(TannhauserGateWeb.Gettext, unquote(locale), fn ->
          Gettext.dgettext(TannhauserGateWeb.Gettext, "player", "Log in")
        end)

      assert has_element?(view, "h1", login)
      if unquote(locale) != "en", do: refute(login == "Log in")

      {:ok, reconnected, _html} = live(recycle(conn), ~p"/users/log_in")
      assert has_element?(reconnected, "#language-submit", unquote(change))
    end
  end

  test "signed-in navigation includes donations and all language choices", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> put_session(:locale, "it")
    {:ok, view, _html} = live(conn, ~p"/gdrs")

    assert has_element?(view, "#drawer #donation-link", "Sostieni su Ko-fi")
    assert has_element?(view, "#drawer #language-form[action='/locale'][method='post']")
    assert has_element?(view, "#language-form input[name='_csrf_token']")
    assert has_element?(view, "#language-form input[name='return_to'][value='/gdrs']")

    for {_label, locale} <- Locale.languages() do
      assert has_element?(view, "#language-select option[value='#{locale}']")
    end
  end

  test "locale survives login and logout session renewal without preserving unrelated data", %{
    conn: conn
  } do
    user = user_fixture()

    conn =
      conn
      |> init_test_session(%{locale: "pt_PT", discarded: "value"})
      |> post(~p"/users/log_in", user: %{login: user.username, password: valid_user_password()})

    assert get_session(conn, :locale) == "pt_PT"
    refute get_session(conn, :discarded)
    assert get_session(conn, :user_token)

    conn = conn |> recycle() |> delete(~p"/users/log_out")
    assert get_session(conn, :locale) == "pt_PT"
    refute get_session(conn, :user_token)
  end

  test "missing and unsupported locales fall back to English", %{conn: conn} do
    assert Locale.normalize(nil) == "en"
    assert Locale.normalize(["it"]) == "en"

    for params <- [%{}, %{locale: "xx"}, %{locale: "pt-BR"}] do
      response = post(conn, ~p"/locale", params)
      assert get_session(response, :locale) == "en"
      assert redirected_to(response) == "/"
    end

    conn = conn |> init_test_session(%{locale: "unsupported"}) |> get(~p"/terms")
    assert conn.assigns.locale == "en"
    assert get_session(conn, :locale) == "en"
  end

  test "language changes only redirect to safe local paths", %{conn: conn} do
    for path <- [
          "https://example.org",
          "//example.org",
          "/\\example.org",
          "/\t/example.org",
          "/hello\r\nLocation: https://example.org",
          "not-a-path",
          ["invalid"]
        ] do
      response = post(conn, ~p"/locale", locale: "es", return_to: path)
      assert redirected_to(response) == "/"
    end

    conn = post(conn, ~p"/locale", locale: "es", return_to: "/gdrs?genre=noir")
    assert redirected_to(conn) == "/gdrs?genre=noir"
  end

  test "anonymous forms return to the same-origin referrer including query params", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/users/register?from=terms")
      |> post(~p"/locale", locale: "it")

    assert redirected_to(conn) == "/users/register?from=terms"
  end

  test "foreign, malformed and different-port referrers are ignored", %{conn: conn} do
    for referrer <- [
          "https://elsewhere.example/evil",
          "/users/register",
          "http://www.example.com:81/evil"
        ] do
      response =
        conn
        |> put_req_header("referer", referrer)
        |> post(~p"/locale", locale: "it")

      assert redirected_to(response) == "/"
    end
  end

  test "a same-origin referrer without a path returns home", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://www.example.com")
      |> post(~p"/locale", locale: "es")

    assert redirected_to(conn) == "/"
  end

  for locale <- ~w(it es pt_PT) do
    test "#{locale} is applied across player, GM, master and platform-admin live sessions" do
      {story, gm} = gdr_fixture(%{name: "Untranslated City"})
      admin = admin_fixture()
      player = user_fixture()
      character_fixture(player, story, %{"name" => "Untranslated Character"})

      for {user, path, selector} <- [
            {player, "/g/#{story.id}/characters", "#characters"},
            {gm, "/g/#{story.id}/gm", "#app-shell"},
            {gm, "/g/#{story.id}/master", "#app-shell"},
            {admin, "/admin", "#app-shell"}
          ] do
        conn =
          build_conn()
          |> log_in_user(user)
          |> put_session(:locale, unquote(locale))

        {:ok, view, _html} = live(conn, path)
        assert has_element?(view, selector)
        assert has_element?(view, "#language-select option[value='#{unquote(locale)}'][selected]")

        support =
          Gettext.with_locale(TannhauserGateWeb.Gettext, unquote(locale), fn ->
            Gettext.dgettext(TannhauserGateWeb.Gettext, "shared", "Support on Ko-fi")
          end)

        refute support == "Support on Ko-fi"
        assert has_element?(view, "#donation-link", support)

        if user == player do
          assert has_element?(view, "#characters", "Untranslated Character")
          assert has_element?(view, "#current-gdr-name", "Untranslated City")

          heading =
            Gettext.with_locale(TannhauserGateWeb.Gettext, unquote(locale), fn ->
              Gettext.dgettext(TannhauserGateWeb.Gettext, "player", "Characters")
            end)

          refute heading == "Characters"
          assert has_element?(view, "h1", heading)
        else
          {selector, msgid} =
            cond do
              path == "/admin" -> {"h1", "Control room"}
              String.ends_with?(path, "/gm") -> {"#gm-master-tools-link", "Master tools"}
              true -> {"#master-characters", "Character dashboard"}
            end

          label =
            Gettext.with_locale(TannhauserGateWeb.Gettext, unquote(locale), fn ->
              Gettext.dgettext(TannhauserGateWeb.Gettext, "management", msgid)
            end)

          refute label == msgid
          assert has_element?(view, selector, label)
        end
      end
    end
  end

  for locale <- ~w(it es pt_PT) do
    test "#{locale} translates appearance controls while preserving stored preset keys" do
      {story, gm} = gdr_fixture()

      conn =
        build_conn()
        |> log_in_user(gm)
        |> put_session(:locale, unquote(locale))

      {:ok, view, _html} = live(conn, ~p"/g/#{story}/gm/theme")

      for {selector, message} <- [
            {"#theme-save", "Save theme"},
            {"label[for='control-corners']", "Corners"},
            {"#preview-primary", "Primary action"}
          ] do
        translated =
          Gettext.with_locale(TannhauserGateWeb.Gettext, unquote(locale), fn ->
            Gettext.dgettext(TannhauserGateWeb.Gettext, "shared", message)
          end)

        refute translated == message
        assert has_element?(view, selector, translated)
      end

      view |> element("#theme-preset-nocturne") |> render_click()
      assert has_element?(view, "#theme-preview[data-theme='nocturne']")
      assert TannhauserGate.Stories.get_story!(story.id).theme == story.theme

      view |> form("#theme-form") |> render_submit()
      assert TannhauserGate.Stories.get_story!(story.id).theme == "nocturne"
      assert has_element?(view, "#language-select option[value='#{unquote(locale)}'][selected]")
    end
  end

  test "locale is applied before authentication denial flashes", %{conn: conn} do
    conn = conn |> init_test_session(%{locale: "it"}) |> get(~p"/gdrs")
    assert redirected_to(conn) == "/users/log_in"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Devi accedere per visualizzare questa pagina."
  end

  test "validation interpolation and plural messages honor the active locale" do
    Gettext.with_locale(TannhauserGateWeb.Gettext, "it", fn ->
      refute CoreComponents.translate_error({"can't be blank", []}) == "can't be blank"

      message =
        CoreComponents.translate_error({"should be at least %{count} character(s)", count: 3})

      assert message =~ "3"
      refute message =~ "%{count}"
      refute message =~ "should be at least"

      assert Gettext.dngettext(
               TannhauserGateWeb.Gettext,
               "shared",
               "%{count} open esito",
               "%{count} open esiti",
               1
             ) ==
               "1 esito aperto"

      assert Gettext.dngettext(
               TannhauserGateWeb.Gettext,
               "shared",
               "%{count} open esito",
               "%{count} open esiti",
               2
             ) ==
               "2 esiti aperti"
    end)
  end
end
