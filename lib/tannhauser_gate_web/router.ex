defmodule TannhauserGateWeb.Router do
  use TannhauserGateWeb, :router

  import TannhauserGateWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TannhauserGateWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TannhauserGateWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", TannhauserGateWeb do
  #   pipe_through :api
  # end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:tannhauser_gate, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TannhauserGateWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{TannhauserGateWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TannhauserGateWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {TannhauserGateWeb.UserAuth, :ensure_authenticated},
        {TannhauserGateWeb.UserAuth, :assign_current_path}
      ] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email

      live "/characters", CharacterLive.Index, :index
      live "/characters/new", CharacterLive.Form, :new
      live "/characters/:id", CharacterLive.Show, :show
      live "/characters/:id/edit", CharacterLive.Form, :edit

      live "/map", MapLive, :index
      live "/stories/:story_id/map", MapLive, :show
      live "/rooms/:id", RoomLive, :show

      live "/forum", ForumLive.Index, :index
      live "/forum/sections/:id", ForumLive.Section, :show
      live "/forum/topics/:id", ForumLive.Topic, :show
    end
  end

  scope "/admin", TannhauserGateWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [
        {TannhauserGateWeb.UserAuth, :ensure_admin},
        {TannhauserGateWeb.UserAuth, :assign_current_path}
      ] do
      live "/", DashboardLive, :index
      live "/stories", StoryLive.Index, :index
      live "/stories/new", StoryLive.Form, :new
      live "/stories/:id/edit", StoryLive.Form, :edit
      live "/characters", CharactersLive, :index
      live "/rooms", RoomsLive, :index
      live "/rooms/:id", RoomsLive, :show
      live "/users", UsersLive, :index
      live "/forum", ForumLive, :index
    end
  end

  scope "/", TannhauserGateWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TannhauserGateWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
