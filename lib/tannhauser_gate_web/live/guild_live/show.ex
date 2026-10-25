defmodule TannhauserGateWeb.GuildLive.Show do
  @moduledoc """
  A guild page (guilds module): description, ranks with salaries and members
  (hidden for secret guilds from non-members). The user's character asks to
  join, answers an invitation or leaves; leaders and masters approve or
  reject requests, invite characters, change ranks, expel members and read
  the guild log; masters also enrol any character directly.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Guilds}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :guilds}}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: user, current_story: story} = socket.assigns
    guild = Guilds.get_guild(story, id)

    if guild && Guilds.visible?(user, story, guild) do
      {:ok, socket |> assign(:page_title, guild.name) |> load(guild)}
    else
      {:ok,
       socket
       |> put_flash(:error, Guilds.error_message(:guild_not_found))
       |> push_navigate(to: ~p"/g/#{story}/guilds")}
    end
  end

  defp load(socket, guild) do
    %{current_user: user, current_story: story, master?: master?} = socket.assigns
    character = Characters.active_character(user, story)
    manager? = Guilds.manager?(user, story, guild)
    members_visible? = Guilds.members_visible?(user, story, guild)

    socket
    |> assign(:guild, guild)
    |> assign(:character, character)
    |> assign(:membership, character && Guilds.membership_for(character, guild))
    |> assign(:can_play?, character != nil and Characters.can_play?(character))
    |> assign(:manager?, manager?)
    |> assign(:leader?, Guilds.leader?(user, guild))
    |> assign(:members_visible?, members_visible?)
    |> assign(:members, if(members_visible?, do: Guilds.list_members(guild), else: []))
    |> assign(:pending, if(manager?, do: Guilds.list_pending(guild), else: []))
    |> assign(:candidates, if(manager?, do: Guilds.invite_candidates(guild), else: []))
    |> assign(:enrol_candidates, if(master?, do: Guilds.enrol_candidates(guild), else: []))
    |> assign(:invite_form, to_form(%{"character_id" => ""}, as: :invite))
    |> assign(:enrol_form, to_form(%{"character_id" => "", "rank_id" => ""}, as: :enrol))
    |> stream(:logs, if(manager?, do: Guilds.list_logs(guild), else: []), reset: true)
  end

  defp reload(socket) do
    %{current_user: user, current_story: story} = socket.assigns

    case Guilds.get_guild(story, socket.assigns.guild.id) do
      nil ->
        push_navigate(socket, to: ~p"/g/#{story}/guilds")

      guild ->
        if Guilds.visible?(user, story, guild),
          do: load(socket, guild),
          else: push_navigate(socket, to: ~p"/g/#{story}/guilds")
    end
  end

  defp membership(socket, id), do: Guilds.get_membership(socket.assigns.guild, id)

  defp reply(socket, result, message) do
    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, message) |> reload()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Guilds.error_message(reason)) |> reload()}
    end
  end

  # Runs `fun` with the membership `id` of this guild, or fails.
  defp with_membership(socket, id, fun) do
    case membership(socket, id) do
      nil -> {:error, :membership_not_found}
      membership -> fun.(membership)
    end
  end

  ## Own character

  @impl true
  def handle_event("request", _params, socket) do
    %{current_user: user, guild: guild, character: character} = socket.assigns

    result =
      if character,
        do: Guilds.request_join(user, guild, character),
        else: {:error, :character_not_found}

    reply(socket, result, "Request sent to the guild.")
  end

  def handle_event("own", %{"op" => op}, socket) do
    %{current_user: user, guild: guild, membership: membership} = socket.assigns
    membership = membership && membership(socket, membership.id)

    {result, message} =
      case {op, membership} do
        {_, nil} -> {{:error, :membership_not_found}, nil}
        {"cancel", m} -> {Guilds.cancel_request(user, guild, m), "Request withdrawn."}
        {"accept", m} -> {Guilds.accept_invitation(user, guild, m), "Welcome to the guild."}
        {"decline", m} -> {Guilds.decline_invitation(user, guild, m), "Invitation declined."}
        {"leave", m} -> {Guilds.leave(user, guild, m), "You left the guild."}
        _ -> {{:error, :invalid_status}, nil}
      end

    reply(socket, result, message)
  end

  ## Management

  def handle_event("approve", %{"id" => id}, socket) do
    %{current_user: user, current_story: story, guild: guild} = socket.assigns

    result = with_membership(socket, id, &Guilds.approve_request(user, story, guild, &1))
    reply(socket, result, "Request approved.")
  end

  def handle_event("reject", %{"id" => id}, socket) do
    %{current_user: user, current_story: story, guild: guild} = socket.assigns

    result = with_membership(socket, id, &Guilds.reject_request(user, story, guild, &1))
    reply(socket, result, "Removed.")
  end

  def handle_event("invite", %{"invite" => %{"character_id" => character_id}}, socket) do
    %{current_user: user, current_story: story, guild: guild} = socket.assigns
    reply(socket, Guilds.invite(user, story, guild, character_id), "Invitation sent.")
  end

  def handle_event("enrol", %{"enrol" => params}, socket) do
    %{current_user: user, current_story: story, guild: guild} = socket.assigns

    reply(
      socket,
      Guilds.enrol(user, story, guild, params["character_id"], params["rank_id"]),
      "Character enrolled."
    )
  end

  def handle_event("set_rank", %{"membership_id" => id, "rank_id" => rank_id}, socket) do
    %{current_user: user, current_story: story, guild: guild} = socket.assigns

    result = with_membership(socket, id, &Guilds.set_rank(user, story, guild, &1, rank_id))
    reply(socket, result, "Rank updated.")
  end

  def handle_event("expel", %{"id" => id}, socket) do
    %{current_user: user, current_story: story, guild: guild} = socket.assigns

    result = with_membership(socket, id, &Guilds.expel(user, story, guild, &1))
    reply(socket, result, "Member expelled.")
  end

  # Whether the viewer can change the rank of (and expel) the member.
  defp can_manage?(assigns, member) do
    assigns.master? or
      (assigns.leader? and not (member.rank && member.rank.leader) and
         member.character.user_id != assigns.current_user.id)
  end

  defp rank_options(assigns) do
    ranks =
      if assigns.master?,
        do: assigns.guild.ranks,
        else: Enum.reject(assigns.guild.ranks, & &1.leader)

    Enum.map(ranks, &{&1.name, &1.id})
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
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/guilds"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Guilds
        </.link>
      </div>

      <section
        id="guild-header"
        class="flex flex-col gap-5 rounded-xl border border-secondary/20 bg-base-200/60 p-5 sm:flex-row"
      >
        <.guild_emblem guild={@guild} id="guild-emblem" class="size-24 text-4xl" />
        <div class="min-w-0 flex-1">
          <h1 class="text-2xl font-bold text-primary">{@guild.name}</h1>
          <div class="mt-2 flex flex-wrap gap-1 text-xs">
            <span :if={@guild.secret} class="badge badge-soft badge-sm badge-error">
              <.icon name="hero-eye-slash-micro" class="size-3" /> secret
            </span>
            <span class={[
              "badge badge-soft badge-sm",
              if(@guild.open_join, do: "badge-success", else: "badge-warning")
            ]}>
              {if @guild.open_join, do: "open to requests", else: "invitation only"}
            </span>
            <span
              :if={@membership}
              id="my-membership"
              class="badge badge-soft badge-sm badge-primary"
            >
              {@character.name}: {Guilds.status_label(@membership.status)}
              <span :if={@membership.rank}>· {@membership.rank.name}</span>
            </span>
          </div>
          <.markdown
            :if={@guild.description}
            id="guild-description"
            content={@guild.description}
            class="mt-3 text-sm"
          />
        </div>

        <div id="guild-actions" class="flex shrink-0 flex-col gap-2 sm:w-44">
          <button
            :if={is_nil(@membership) and @guild.open_join and @can_play?}
            id="request-join"
            phx-click="request"
            phx-disable-with="Sending..."
            class="btn btn-primary btn-sm transition hover:-translate-y-0.5"
          >
            <.icon name="hero-hand-raised" class="size-4" /> Ask to join
          </button>
          <%= if @membership do %>
            <%= case @membership.status do %>
              <% "requested" -> %>
                <button
                  id="cancel-request"
                  phx-click="own"
                  phx-value-op="cancel"
                  class="btn btn-ghost btn-sm"
                >
                  Withdraw request
                </button>
              <% "invited" -> %>
                <button
                  id="accept-invitation"
                  phx-click="own"
                  phx-value-op="accept"
                  class="btn btn-primary btn-sm"
                >
                  Accept invitation
                </button>
                <button
                  id="decline-invitation"
                  phx-click="own"
                  phx-value-op="decline"
                  class="btn btn-ghost btn-sm"
                >
                  Decline
                </button>
              <% _ -> %>
                <button
                  id="leave-guild"
                  phx-click="own"
                  phx-value-op="leave"
                  data-confirm="Leave this guild?"
                  class="btn btn-ghost btn-sm text-error"
                >
                  <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Leave
                </button>
            <% end %>
          <% end %>
        </div>
      </section>

      <div class="mt-6 grid gap-6 lg:grid-cols-[18rem_1fr]">
        <section
          id="guild-ranks"
          class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5"
        >
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Ranks</h2>
          <p :if={@guild.ranks == []} class="mt-2 text-sm text-base-content/60">No ranks yet.</p>
          <ol class="mt-3 space-y-1.5 text-sm">
            <li
              :for={rank <- @guild.ranks}
              id={"guild-rank-#{rank.id}"}
              class="flex items-center justify-between gap-2"
            >
              <span class="flex items-center gap-1.5">
                <.icon :if={rank.leader} name="hero-star-micro" class="size-3 text-primary" />
                {rank.name}
              </span>
              <span class="text-xs tabular-nums text-base-content/60">
                {rank.salary} {@current_story.currency_name}
              </span>
            </li>
          </ol>
        </section>

        <div class="space-y-6">
          <section
            id="guild-members"
            class="rounded-xl border border-secondary/20 bg-base-200/80 p-5"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Members</h2>
            <p
              :if={!@members_visible?}
              id="members-hidden"
              class="mt-2 flex items-center gap-2 text-sm text-base-content/60"
            >
              <.icon name="hero-eye-slash" class="size-4" />
              The members of this guild are known only to its members.
            </p>
            <p
              :if={@members_visible? and @members == []}
              id="members-empty"
              class="mt-2 text-sm text-base-content/60"
            >
              No members yet.
            </p>
            <ul class="mt-3 divide-y divide-secondary/10 text-sm">
              <li
                :for={member <- @members}
                id={"member-#{member.id}"}
                class="flex flex-wrap items-center gap-3 py-2 transition-colors hover:bg-base-100/30"
              >
                <.link
                  navigate={~p"/g/#{@current_story}/characters/#{member.character_id}"}
                  class="font-semibold text-primary hover:underline"
                >
                  {member.character.name}
                </.link>
                <span class="text-xs text-base-content/60">
                  <.icon
                    :if={member.rank && member.rank.leader}
                    name="hero-star-micro"
                    class="size-3 text-primary"
                  />
                  {(member.rank && member.rank.name) || "No rank"}
                </span>
                <span :if={@manager? and can_manage?(assigns, member)} class="ml-auto flex gap-2">
                  <form
                    id={"rank-form-#{member.id}"}
                    phx-change="set_rank"
                    class="flex items-center"
                  >
                    <input type="hidden" name="membership_id" value={member.id} />
                    <select
                      name="rank_id"
                      class="select select-xs"
                      aria-label={"Rank of #{member.character.name}"}
                    >
                      <option value="" disabled selected={is_nil(member.rank_id)}>Rank</option>
                      <option
                        :for={{name, id} <- rank_options(assigns)}
                        value={id}
                        selected={id == member.rank_id}
                      >
                        {name}
                      </option>
                    </select>
                  </form>
                  <button
                    id={"expel-#{member.id}"}
                    phx-click="expel"
                    phx-value-id={member.id}
                    data-confirm={"Expel #{member.character.name}?"}
                    class="rounded p-0.5 text-base-content/60 transition-colors hover:text-error"
                    title="Expel"
                  >
                    <.icon name="hero-user-minus" class="size-4" />
                  </button>
                </span>
              </li>
            </ul>
          </section>

          <section
            :if={@manager?}
            id="guild-management"
            class="rounded-xl border border-primary/30 bg-base-200/80 p-5"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-primary">Recruitment</h2>

            <ul id="guild-pending" class="mt-3 divide-y divide-secondary/10 text-sm">
              <li :if={@pending == []} class="py-2 text-base-content/60">
                No pending requests or invitations.
              </li>
              <li
                :for={pending <- @pending}
                id={"pending-#{pending.id}"}
                class="flex flex-wrap items-center gap-3 py-2"
              >
                <span class="font-semibold">{pending.character.name}</span>
                <span class="badge badge-soft badge-sm">
                  {Guilds.status_label(pending.status)}
                </span>
                <span class="ml-auto flex gap-2">
                  <button
                    :if={pending.status == "requested"}
                    id={"approve-#{pending.id}"}
                    phx-click="approve"
                    phx-value-id={pending.id}
                    class="btn btn-xs btn-primary"
                  >
                    Approve
                  </button>
                  <button
                    id={"reject-#{pending.id}"}
                    phx-click="reject"
                    phx-value-id={pending.id}
                    class="btn btn-xs btn-ghost"
                  >
                    {if pending.status == "requested", do: "Reject", else: "Withdraw"}
                  </button>
                </span>
              </li>
            </ul>

            <.form
              for={@invite_form}
              id="invite-form"
              phx-submit="invite"
              class="mt-4 flex flex-wrap items-end gap-2"
            >
              <div class="min-w-48 flex-1">
                <.input
                  field={@invite_form[:character_id]}
                  type="select"
                  label="Invite a character"
                  prompt="Choose a character"
                  options={Enum.map(@candidates, &{&1.name, &1.id})}
                />
              </div>
              <.button id="send-invite" class="mb-2" phx-disable-with="Sending...">
                <.icon name="hero-paper-airplane" class="size-4" /> Invite
              </.button>
            </.form>

            <.form
              :if={@master?}
              for={@enrol_form}
              id="enrol-form"
              phx-submit="enrol"
              class="mt-2 flex flex-wrap items-end gap-2 border-t border-secondary/10 pt-3"
            >
              <div class="min-w-40 flex-1">
                <.input
                  field={@enrol_form[:character_id]}
                  type="select"
                  label="Enrol directly (masters)"
                  prompt="Choose a character"
                  options={Enum.map(@enrol_candidates, &{&1.name, &1.id})}
                />
              </div>
              <div class="w-36">
                <.input
                  field={@enrol_form[:rank_id]}
                  type="select"
                  label="Rank"
                  prompt="Default"
                  options={Enum.map(@guild.ranks, &{&1.name, &1.id})}
                />
              </div>
              <.button id="enrol-character" class="mb-2" phx-disable-with="Saving...">
                Enrol
              </.button>
            </.form>

            <h3 class="mt-6 text-xs font-bold uppercase tracking-[0.2em] text-secondary">
              Guild log
            </h3>
            <ul id="guild-logs" phx-update="stream" class="mt-2 space-y-1 text-xs">
              <li id="guild-logs-empty" class="hidden text-base-content/60 only:block">
                Nothing recorded yet.
              </li>
              <li
                :for={{dom_id, log} <- @streams.logs}
                id={dom_id}
                class="flex flex-wrap gap-x-1.5 text-base-content/80"
              >
                <span class="font-semibold text-primary">
                  {(log.character && log.character.name) || "—"}
                </span>
                <span>{Guilds.action_label(log.action)}</span>
                <span :if={log.rank_name} class="font-semibold">{log.rank_name}</span>
                <span class="ml-auto text-base-content/50">
                  {(log.user && log.user.username) || "system"} · {Calendar.strftime(
                    log.inserted_at,
                    "%d/%m/%Y %H:%M"
                  )}
                </span>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
