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
    get "/terms", PageController, :terms
  end

  scope "/", TannhauserGateWeb do
    pipe_through :api

    get "/health", HealthController, :show
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

      live "/gdrs", GdrLive.Index, :index
      live "/gdrs/request", GdrLive.Request, :new
    end

    live_session :gdr,
      on_mount: [
        {TannhauserGateWeb.UserAuth, :ensure_authenticated},
        {TannhauserGateWeb.UserAuth, :assign_current_path},
        {TannhauserGateWeb.UserAuth, :load_story},
        {TannhauserGateWeb.GdrPresence, :track},
        {TannhauserGateWeb.MailNotifier, :subscribe},
        {TannhauserGateWeb.BoardsNotifier, :subscribe}
      ] do
      live "/g/:story_id", GdrLive.Home, :show

      live "/g/:story_id/characters", CharacterLive.Index, :index
      live "/g/:story_id/characters/new", CharacterLive.Form, :new
      live "/g/:story_id/characters/:id", CharacterLive.Show, :show
      live "/g/:story_id/characters/:id/edit", CharacterLive.Form, :edit
      live "/g/:story_id/characters/:id/diary", DiaryLive, :index

      live "/g/:story_id/guide", GuideLive, :index
      live "/g/:story_id/guide/:page_id", GuideLive, :show

      live "/g/:story_id/map", MapLive, :index
      live "/g/:story_id/rooms/:id", RoomLive, :show

      live "/g/:story_id/forum", ForumLive.Index, :index
      live "/g/:story_id/forum/sections/:id", ForumLive.Section, :show
      live "/g/:story_id/forum/topics/:id", ForumLive.Topic, :show

      live "/g/:story_id/mail", MailLive, :inbox
      live "/g/:story_id/mail/sent", MailLive, :sent
      live "/g/:story_id/mail/new", MailLive, :new
      live "/g/:story_id/mail/:id", MailLive, :show

      live "/g/:story_id/bank", BankLive, :index
      live "/g/:story_id/jobs", JobsLive, :index

      live "/g/:story_id/market", MarketLive, :index
      live "/g/:story_id/market/:shop_id", MarketLive, :show

      live "/g/:story_id/guilds", GuildLive.Index, :index
      live "/g/:story_id/guilds/:id", GuildLive.Show, :show

      live "/g/:story_id/esiti", EsitoLive.Index, :index
      live "/g/:story_id/esiti/:id", EsitoLive.Show, :show
      live "/g/:story_id/quests", QuestLive.Index, :index
      live "/g/:story_id/boards", BoardLive.Index, :index
      live "/g/:story_id/report", ReportLive.New, :new
    end

    live_session :gdr_admin,
      on_mount: [
        {TannhauserGateWeb.UserAuth, :ensure_authenticated},
        {TannhauserGateWeb.UserAuth, :assign_current_path},
        {TannhauserGateWeb.UserAuth, :load_story},
        {TannhauserGateWeb.UserAuth, :ensure_gdr_admin},
        {TannhauserGateWeb.GdrPresence, :track},
        {TannhauserGateWeb.MailNotifier, :subscribe},
        {TannhauserGateWeb.BoardsNotifier, :subscribe}
      ] do
      live "/g/:story_id/gm", GmLive, :index
      live "/g/:story_id/gm/guide", GmLive.Guide, :index
      live "/g/:story_id/gm/zones", GmLive.Zones, :index
      live "/g/:story_id/gm/actions", GmLive.Actions, :index
      live "/g/:story_id/gm/origins", GmLive.Origins, :index
      live "/g/:story_id/gm/items", GmLive.Items, :index
      live "/g/:story_id/gm/shops", GmLive.Shops, :index
      live "/g/:story_id/gm/calendar", GmLive.Calendar, :index
      live "/g/:story_id/gm/weather", GmLive.Weather, :index
      live "/g/:story_id/gm/:tab", GmLive, :show
    end

    live_session :gdr_master,
      on_mount: [
        {TannhauserGateWeb.UserAuth, :ensure_authenticated},
        {TannhauserGateWeb.UserAuth, :assign_current_path},
        {TannhauserGateWeb.UserAuth, :load_story},
        {TannhauserGateWeb.UserAuth, :ensure_master},
        {TannhauserGateWeb.GdrPresence, :track},
        {TannhauserGateWeb.MailNotifier, :subscribe},
        {TannhauserGateWeb.BoardsNotifier, :subscribe}
      ] do
      live "/g/:story_id/master", MasterLive, :index
      live "/g/:story_id/master/characters", MasterLive.Characters, :index
      live "/g/:story_id/master/moderation", MasterLive.Moderation, :index
      live "/g/:story_id/master/chat-log", MasterLive.ChatLog, :index
      live "/g/:story_id/master/zones", MasterLive.Zones, :index
      live "/g/:story_id/master/actions", MasterLive.Actions, :index
      live "/g/:story_id/master/items", MasterLive.Items, :index
      live "/g/:story_id/master/guilds", MasterLive.Guilds, :index
      live "/g/:story_id/master/esiti", MasterLive.Esiti, :index
      live "/g/:story_id/master/quests", MasterLive.Quests, :index
      live "/g/:story_id/master/boards", MasterLive.Boards, :index
      live "/g/:story_id/master/calendar", MasterLive.Calendar, :index
      live "/g/:story_id/master/weather", MasterLive.Weather, :index
      live "/g/:story_id/master/reports", MasterLive.Reports, :index
      live "/g/:story_id/master/sanctions", MasterLive.Sanctions, :index
      live "/g/:story_id/master/npcs/new", CharacterLive.Form, :new_npc
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
      live "/requests", RequestsLive, :index
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
