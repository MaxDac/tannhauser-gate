defmodule TannhauserGateWeb.UserAuth do
  @moduledoc """
  Session and remember-me cookie authentication plugs and LiveView on_mount`n  hooks, including the admin guard.
  """
  use TannhauserGateWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias TannhauserGate.Accounts
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_tannhauser_gate_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      TannhauserGateWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule TannhauserGateWeb.PageLive do
        use TannhauserGateWeb, :live_view

        on_mount {TannhauserGateWeb.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{TannhauserGateWeb.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  # Gates the email-based pages (reset password, confirmation) behind FEATURE_EMAIL_AUTH.
  def on_mount(:require_email_auth, _params, _session, socket) do
    if TannhauserGate.Features.email_auth?() do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Email features are currently disabled.")
       |> Phoenix.LiveView.redirect(to: ~p"/users/log_in")}
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log_in")

      {:halt, socket}
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    socket = mount_current_user(socket, session)

    cond do
      is_nil(socket.assigns.current_user) ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
         |> Phoenix.LiveView.redirect(to: ~p"/users/log_in")}

      Accounts.admin?(socket.assigns.current_user) ->
        {:cont, socket}

      true ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Admins only.")
         |> Phoenix.LiveView.redirect(to: ~p"/gdrs")}
    end
  end

  # Loads the GDR (story) from the `story_id` route param and makes sure the
  # user can enter it: it is published, or the user is its GDR admin, one of its
  # masters, or a platform admin. Assigns the user's role in the GDR.
  def on_mount(:load_story, params, _session, socket) do
    user = socket.assigns.current_user

    with {id, ""} <- Integer.parse(to_string(params["story_id"])),
         %Story{} = story <- Stories.get_story(id),
         role when not is_nil(role) <- Stories.role(user, story) do
      {:cont,
       socket
       |> Phoenix.Component.assign(:current_story, story)
       |> assign_story_role(role)}
    else
      _ ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "That GDR does not exist or is not open.")
         |> Phoenix.LiveView.redirect(to: ~p"/gdrs")}
    end
  end

  # Only the GDR admin (or a platform admin) may configure the GDR.
  def on_mount(:ensure_gdr_admin, _params, _session, socket) do
    if socket.assigns.gdr_admin? do
      {:cont, socket}
    else
      deny_story_access(socket, "Only the GDR admin can do that.")
    end
  end

  # Guards the pages of an optional module (`TannhauserGate.Modules`): when the
  # GDR has not enabled it, the user is sent back to the GDR home page.
  def on_mount({:require_module, key}, _params, _session, socket) do
    if Stories.module_enabled?(socket.assigns.current_story, key) do
      {:cont, socket}
    else
      deny_story_access(socket, "That feature is not enabled in this GDR.")
    end
  end

  # Masters, the GDR admin and platform admins may use the master tools.
  def on_mount(:ensure_master, _params, _session, socket) do
    if socket.assigns.master? do
      {:cont, socket}
    else
      deny_story_access(socket, "Only the GDR masters can do that.")
    end
  end

  # Tracks the current path so the navigation drawer can highlight the
  # active section.
  def on_mount(:assign_current_path, _params, _session, socket) do
    {:cont,
     socket
     |> Phoenix.Component.assign(:current_path, nil)
     |> Phoenix.Component.assign(:current_story, nil)
     |> assign_story_role(nil)
     |> Phoenix.LiveView.attach_hook(:current_path, :handle_params, fn _params, url, socket ->
       {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(url).path)}
     end)}
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  defp assign_story_role(socket, role) do
    socket
    |> Phoenix.Component.assign(:story_role, role)
    |> Phoenix.Component.assign(:gdr_admin?, Stories.admin_role?(role))
    |> Phoenix.Component.assign(:master?, Stories.master_role?(role))
  end

  defp deny_story_access(socket, message) do
    {:halt,
     socket
     |> Phoenix.LiveView.put_flash(:error, message)
     |> Phoenix.LiveView.redirect(to: ~p"/g/#{socket.assigns.current_story.id}")}
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  @doc """
  Used for routes that require an admin user.
  """
  def require_admin(conn, _opts) do
    if Accounts.admin?(conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_flash(:error, "Admins only.")
      |> redirect(to: ~p"/gdrs")
      |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/gdrs"
end
