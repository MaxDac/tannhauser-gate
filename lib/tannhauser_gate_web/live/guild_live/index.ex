defmodule TannhauserGateWeb.GuildLive.Index do
  @moduledoc """
  The guilds of a GDR (guilds module): every guild the user can see (secret
  ones only for their members and the masters), with the user's membership
  status, and the pending invitations of the user's character to accept or
  decline.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Guilds

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :guilds}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       :page_title,
       dgettext("player", "Guilds · %{name}", name: socket.assigns.current_story.name)
     )
     |> load()}
  end

  defp load(socket) do
    %{current_user: user, current_story: story, master?: master?} = socket.assigns
    memberships = Guilds.user_memberships(user, story)
    guilds = Guilds.list_visible_guilds(user, story)
    active = for m <- memberships, m.status == "active", into: MapSet.new(), do: m.guild_id

    socket
    |> assign(:guilds, guilds)
    |> assign(:counts, Guilds.member_counts(story))
    |> assign(:mine, Map.new(memberships, &{&1.guild_id, &1}))
    |> assign(:invitations, Enum.filter(memberships, &(&1.status == "invited")))
    |> assign(
      :counted,
      MapSet.new(
        for g <- guilds, not g.secret or master? or MapSet.member?(active, g.id), do: g.id
      )
    )
  end

  @impl true
  def handle_event("respond", %{"guild_id" => guild_id, "id" => id, "answer" => answer}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    result =
      with %{} = guild <- Guilds.get_guild(story, guild_id),
           %{} = membership <- Guilds.get_membership(guild, id) do
        if answer == "accept",
          do: Guilds.accept_invitation(user, guild, membership),
          else: Guilds.decline_invitation(user, guild, membership)
      else
        nil -> {:error, :membership_not_found}
      end

    case result do
      {:ok, _} ->
        message =
          if answer == "accept",
            do: dgettext("player", "Welcome to the guild."),
            else: dgettext("player", "Invitation declined.")

        {:noreply, socket |> put_flash(:info, message) |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Guilds.error_message(reason)) |> load()}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      current_story={@current_story}
      story_role={@story_role}
      online={@online}
      last_location={@last_location}
      my_characters={@my_characters}
      active_character={@active_character}
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <.header>
        {dgettext("player", "Guilds")}
        <:subtitle>
          {dgettext("player", "The factions of")} {@current_story.name}{dgettext(
            "player",
            ": who they are and who they answer to."
          )}
        </:subtitle>

        <:actions :if={@master?}>
          <.button id="manage-guilds" navigate={~p"/g/#{@current_story}/master/guilds"}>
            <.icon name="hero-adjustments-horizontal" class="size-4" /> {dgettext(
              "player",
              "Manage guilds"
            )}
          </.button>
        </:actions>
      </.header>

      <section
        :if={@invitations != []}
        id="guild-invitations"
        class="mt-6 rounded-xl border border-primary/40 bg-primary/5 p-5"
      >
        <h2 class="flex items-center gap-2 text-sm font-bold uppercase tracking-[0.2em] text-primary">
          <.icon name="hero-envelope-open" class="size-4" /> {dgettext("player", "Invitations")}
        </h2>

        <ul class="mt-3 space-y-2">
          <li
            :for={invitation <- @invitations}
            id={"invitation-#{invitation.id}"}
            class="flex flex-wrap items-center gap-3 rounded-lg bg-base-200/60 px-3 py-2 transition-colors hover:bg-base-200"
          >
            <.guild_emblem guild={invitation.guild} class="size-9" />
            <p class="min-w-0 flex-1 text-sm">
              <strong>{invitation.guild.name}</strong> {dgettext("player", "invites")}
              <span class="text-primary">{invitation.character.name}</span>
            </p>

            <button
              id={"accept-invitation-#{invitation.id}"}
              phx-click="respond"
              phx-value-guild_id={invitation.guild_id}
              phx-value-id={invitation.id}
              phx-value-answer="accept"
              phx-disable-with={dgettext("player", "...")}
              class="btn btn-sm btn-primary"
            >
              {dgettext("player", "Accept")}
            </button>

            <button
              id={"decline-invitation-#{invitation.id}"}
              phx-click="respond"
              phx-value-guild_id={invitation.guild_id}
              phx-value-id={invitation.id}
              phx-value-answer="decline"
              phx-disable-with={dgettext("player", "...")}
              class="btn btn-sm btn-ghost"
            >
              {dgettext("player", "Decline")}
            </button>
          </li>
        </ul>
      </section>

      <p :if={@guilds == []} id="guilds-empty" class="mt-8 text-sm text-base-content/60">
        {dgettext("player", "No guilds to show yet.")}
      </p>

      <ul id="guilds" class="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <li :for={guild <- @guilds} id={"guild-#{guild.id}"}>
          <.link
            navigate={~p"/g/#{@current_story}/guilds/#{guild}"}
            class="group flex h-full gap-4 rounded-xl border border-secondary/20 bg-base-200/60 p-4 transition hover:-translate-y-0.5 hover:border-primary/50 hover:shadow-phosphor"
          >
            <.guild_emblem guild={guild} class="size-16 transition-transform group-hover:scale-105" />
            <div class="min-w-0 flex-1">
              <p class="truncate font-semibold text-primary">{guild.name}</p>

              <p :if={MapSet.member?(@counted, guild.id)} class="text-xs text-base-content/60">
                {Map.get(@counts, guild.id, 0)} {dgettext("player", "members")}
              </p>

              <div class="mt-2 flex flex-wrap gap-1 text-xs">
                <span :if={guild.secret} class="badge badge-soft badge-sm badge-error">
                  <.icon name="hero-eye-slash-micro" class="size-3" /> {dgettext("player", "secret")}
                </span>

                <span :if={!guild.open_join} class="badge badge-soft badge-sm badge-warning">
                  {dgettext("player", "invitation only")}
                </span>

                <span
                  :if={@mine[guild.id]}
                  id={"guild-status-#{guild.id}"}
                  class="badge badge-soft badge-sm badge-success"
                >
                  {Guilds.status_label(@mine[guild.id].status)}
                </span>
              </div>
            </div>
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
