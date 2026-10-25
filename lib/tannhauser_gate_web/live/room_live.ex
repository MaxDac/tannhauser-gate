defmodule TannhauserGateWeb.RoomLive do
  @moduledoc """
  A chat room (a location of a GDR): in character and OFF messages, master
  narration and room status, dice rolls with rerolls, older history and, for
  private locations, bookings.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.ChatComponents
  import TannhauserGateWeb.ZoneComponents

  alias TannhauserGate.{
    Boards,
    Bookings,
    Characters,
    Chat,
    Dice,
    Guilds,
    Items,
    PeriodicActions,
    Sheet,
    Stories,
    Weather,
    Zones
  }

  alias TannhauserGate.Chat.Message
  alias TannhauserGateWeb.GdrPresence

  @page_size 50
  # Rechecks private access at least this often (ms).
  @max_recheck 60 * 60 * 1000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    location = Stories.get_location!(id)
    story = socket.assigns.current_story

    if location.story_id != story.id do
      {:ok,
       socket
       |> put_flash(:error, dgettext("player", "That room does not exist in this GDR."))
       |> push_navigate(to: ~p"/g/#{story}/map")}
    else
      {:ok, load(socket, location)}
    end
  end

  defp load(socket, location) do
    %{current_user: user, current_story: story} = socket.assigns
    characters = Characters.playable_characters(user, story)
    own = Characters.active_character(user, story)
    speakers = if own && own not in characters, do: characters ++ [own], else: characters

    viewer = if socket.assigns.master?, do: :all, else: user
    rp? = Stories.module_enabled?(story, :chat_rp)

    if connected?(socket) do
      Chat.subscribe(location.id)
      if rp?, do: Chat.subscribe_whispers(location.id, viewer)
      Bookings.subscribe(location.id)
      if Weather.enabled?(story), do: Weather.subscribe(story.id)
    end

    socket
    |> assign(:page_title, location.name)
    |> assign(:location, location)
    |> assign(:shops, Items.list_location_shops(location))
    |> assign(:room_guild, room_guild(user, story, location))
    |> assign(:characters, characters)
    |> assign(:speakers, speakers)
    |> assign(:own_character, own)
    |> assign(:viewer, viewer)
    |> assign(:rp?, rp?)
    |> assign(:chat_limits, {story.chat_min_length, story.chat_max_length})
    |> assign(:recipient_options, recipient_options(story, speakers, rp?))
    |> assign(:body_length, 0)
    |> assign(:dice_config, Dice.config(story))
    |> assign(:sheet_items, Sheet.list_items(story))
    |> assign(:form_id, 0)
    |> assign(:form, new_form(speakers))
    |> assign(:dice_form, new_dice_form(characters))
    |> assign(:recheck_ref, nil)
    |> stream(:messages, [])
    |> assign(:access?, nil)
    |> assign(:guild_locked?, false)
    |> GdrPresence.enter_location(location)
    |> load_zone()
    |> assign(:periodic_actions, PeriodicActions.list_actions(story))
    |> assign(:action_result, nil)
    |> load_cooldowns()
    |> load_bookings()
    |> load_boards()
    |> refresh_access()
  end

  defp load_boards(socket) do
    boards = Boards.boards_for_location(socket.assigns.location, socket.assigns.current_user)

    socket
    |> assign(:room_boards, boards)
    |> assign(:room_notices, Boards.notices_by_board(boards))
  end

  ## Zone and periodic actions

  defp load_zone(socket) do
    case Zones.zone_of(socket.assigns.location) do
      nil ->
        assign(socket, zone: nil, zone_values: [], zone_events: [], zone_weather: nil)

      zone ->
        socket
        |> assign(
          zone: zone,
          zone_values: Zones.zone_values(zone, public_only: !socket.assigns.master?),
          zone_events: Zones.list_events(zone, 5)
        )
        |> load_weather()
    end
  end

  defp load_weather(%{assigns: %{zone: zone, current_story: story}} = socket) do
    weather = if zone && Weather.enabled?(story), do: Weather.zone_weather(zone)
    assign(socket, :zone_weather, weather)
  end

  defp load_cooldowns(socket) do
    now = DateTime.utc_now()

    cooldowns =
      for action <- socket.assigns.periodic_actions,
          character <- socket.assigns.characters,
          into: %{},
          do:
            {{action.id, character.id},
             PeriodicActions.cooldown_remaining(action, character, now)}

    assign(socket, :cooldowns, cooldowns)
  end

  defp new_form(speakers, params \\ %{}) do
    character_id = params["character_id"] || (List.first(speakers) || %{id: nil}).id
    kind = params["kind"] || "speech"

    to_form(
      %{
        "character_id" => character_id,
        "kind" => kind,
        "body" => "",
        "tag" => params["tag"] || "",
        "recipient_character_id" => params["recipient_character_id"] || ""
      },
      as: "message"
    )
  end

  # The characters one can whisper to (chat roleplay module): the approved
  # characters of the GDR but one's own.
  defp recipient_options(_story, _speakers, false), do: []

  defp recipient_options(story, speakers, true) do
    own = MapSet.new(speakers, & &1.id)

    story.id
    |> Characters.list_story_characters(%{"approval_status" => "approved"})
    |> Enum.reject(&MapSet.member?(own, &1.id))
    |> Enum.map(&{&1.name, &1.id})
  end

  defp new_dice_form(characters, params \\ %{}) do
    character_id = params["character_id"] || (List.first(characters) || %{id: nil}).id

    to_form(
      %{
        "character_id" => character_id,
        "items" => [],
        "modifier" => "",
        "difficulty" => "",
        "expression" => "",
        "label" => ""
      },
      as: "dice"
    )
  end

  defp booking_form, do: to_form(%{}, as: "booking")

  ## Private locations

  defp load_bookings(%{assigns: %{location: %{private: true} = location}} = socket) do
    socket
    |> assign(:bookings, Bookings.list_upcoming(location))
    |> assign_new(:booking_form, fn -> booking_form() end)
    |> assign_new(:invite_options, fn ->
      socket.assigns.current_story.id
      |> Characters.list_story_characters(%{"approval_status" => "approved"})
      |> Enum.map(&{&1.name, &1.id})
    end)
  end

  defp load_bookings(socket), do: assign(socket, :bookings, [])

  # The guild a room is reserved to (guilds module): `{name, guild}` where
  # the name is hidden for secret guilds the user cannot see.
  defp room_guild(_user, _story, %{guild_id: nil}), do: nil

  defp room_guild(user, story, location) do
    with true <- Guilds.enabled?(story),
         %{} = guild <- Guilds.get_guild(story, location.guild_id) do
      if Guilds.visible?(user, story, guild),
        do: guild.name,
        else: dgettext("player", "Guild members")
    else
      _ -> nil
    end
  end

  # Shows or hides the conversation when the access to a private location
  # changes, and schedules the next check at the next booking boundary.
  defp refresh_access(socket) do
    %{current_user: user, location: location} = socket.assigns
    access? = Bookings.can_access?(user, location)

    socket =
      cond do
        access? == socket.assigns.access? -> socket
        access? -> load_messages(socket)
        true -> socket |> stream(:messages, [], reset: true) |> assign(:more?, false)
      end

    socket
    |> assign(:access?, access?)
    |> assign(:guild_locked?, Bookings.guild_locked?(user, location))
    |> assign(:active_booking, location.private && Bookings.active_booking(location))
    |> schedule_recheck()
  end

  defp load_messages(socket) do
    {messages, more?} =
      Chat.page_messages(socket.assigns.location.id,
        limit: @page_size,
        viewer: socket.assigns.viewer
      )

    socket
    |> assign(:more?, more?)
    |> assign(:oldest, List.first(messages))
    |> stream(:messages, messages, reset: true)
  end

  defp schedule_recheck(%{assigns: %{location: %{private: true}}} = socket) do
    if connected?(socket) do
      if ref = socket.assigns.recheck_ref, do: Process.cancel_timer(ref)
      now = DateTime.utc_now()

      next =
        socket.assigns.bookings
        |> Enum.flat_map(&[&1.starts_at, &1.ends_at])
        |> Enum.filter(&(DateTime.compare(&1, now) == :gt))
        |> Enum.map(&(DateTime.diff(&1, now, :millisecond) + 500))
        |> Enum.min(fn -> @max_recheck end)
        |> min(@max_recheck)

      assign(socket, :recheck_ref, Process.send_after(self(), :recheck_access, next))
    else
      socket
    end
  end

  defp schedule_recheck(socket), do: socket

  ## Events

  @impl true
  def handle_event("send", %{"message" => params}, socket) do
    %{current_user: user, location: location} = socket.assigns

    result =
      case params["kind"] do
        "narration" -> Chat.narrate(user, location, params["body"])
        "status" -> status_result(Chat.set_room_status(user, location, params["body"]))
        _ -> Chat.create_message(user, location, params)
      end

    case result do
      {:ok, _message} ->
        # The new message arrives through PubSub; reset the form by giving it
        # a new id while keeping the selected character, kind, tag and recipient.
        {:noreply,
         socket
         |> update(:form_id, &(&1 + 1))
         |> assign(:body_length, 0)
         |> assign(:form, new_form(socket.assigns.speakers, params))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:body_length, body_length(params))
         |> assign(
           :form,
           to_form(params, as: "message", errors: changeset.errors, action: :insert)
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Chat.error_message(reason))}
    end
  end

  # Keeps the composer in sync while typing: the selected kind (whisper
  # recipient field) and the length counter.
  def handle_event("change_message", %{"message" => params}, socket) do
    {:noreply,
     socket
     |> assign(:body_length, body_length(params))
     |> assign(:form, to_form(params, as: "message"))}
  end

  def handle_event("clear_status", _params, socket) do
    %{current_user: user, location: location} = socket.assigns

    case Chat.set_room_status(user, location, "") do
      {:ok, _location, _message} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Chat.error_message(reason))}
    end
  end

  def handle_event("roll", %{"dice" => params}, socket) do
    %{current_user: user, location: location, current_story: story} = socket.assigns

    case Chat.roll_dice(user, location, params, story: story) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> update(:form_id, &(&1 + 1))
         |> assign(:dice_form, new_dice_form(socket.assigns.characters, params))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Chat.error_message(reason))}
    end
  end

  def handle_event(
        "perform_action",
        %{"action_id" => action_id, "character_id" => character_id},
        socket
      ) do
    %{current_user: user, location: location} = socket.assigns
    action = Enum.find(socket.assigns.periodic_actions, &(to_string(&1.id) == action_id))
    character = Enum.find(socket.assigns.characters, &(to_string(&1.id) == character_id))

    with true <- socket.assigns.access? == true and action != nil and character != nil,
         true <- Characters.can_act_as?(user, character),
         {:ok, log} <- PeriodicActions.perform(action, character, location, user: user) do
      {:noreply, socket |> assign(:action_result, log) |> load_cooldowns()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, PeriodicActions.error_message(reason))}

      _ ->
        {:noreply,
         put_flash(socket, :error, dgettext("player", "You cannot perform this action here."))}
    end
  end

  def handle_event("reroll", %{"id" => id}, socket) do
    %{current_user: user, location: location, current_story: story} = socket.assigns

    with %{} = message <- Chat.get_location_message(location.id, id),
         {:ok, _message} <- Chat.reroll(user, message, nil, story: story) do
      {:noreply, socket}
    else
      nil -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Chat.error_message(reason))}
    end
  end

  def handle_event("load_older", _params, %{assigns: %{access?: true}} = socket) do
    {messages, more?} =
      Chat.page_messages(socket.assigns.location.id,
        limit: @page_size,
        before: socket.assigns.oldest,
        viewer: socket.assigns.viewer
      )

    socket =
      messages
      |> Enum.reverse()
      |> Enum.reduce(socket, &stream_insert(&2, :messages, &1, at: 0))

    {:noreply,
     socket
     |> assign(:more?, more?)
     |> assign(:oldest, List.first(messages) || socket.assigns.oldest)}
  end

  def handle_event("load_older", _params, socket), do: {:noreply, socket}

  def handle_event("delete_message", %{"id" => id}, socket) do
    story = socket.assigns.current_story

    with %{} = message <- Chat.get_story_message(story.id, id),
         {:ok, _} <- Chat.delete_message(socket.assigns.current_user, message) do
      {:noreply, socket}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("player", "Only the GDR moderators can delete messages.")
         )}
    end
  end

  def handle_event("validate_booking", %{"booking" => params}, socket) do
    changeset = params |> normalize_times() |> Bookings.change_booking()
    form = to_form(params, as: "booking", errors: changeset.errors, action: :validate)

    {:noreply, assign(socket, :booking_form, form)}
  end

  def handle_event("book", %{"booking" => params}, socket) do
    %{current_user: user, location: location} = socket.assigns

    case Bookings.create_booking(user, location, normalize_times(params)) do
      {:ok, _booking} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("player", "Location booked."))
         |> assign(:booking_form, booking_form())}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :booking_form,
           to_form(params, as: "booking", errors: changeset.errors, action: :insert)
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Bookings.error_message(reason))}
    end
  end

  def handle_event("cancel_booking", %{"id" => id}, socket) do
    %{current_user: user, location: location} = socket.assigns

    with %{} = booking <- Bookings.get_booking(location, id),
         {:ok, _} <- Bookings.cancel_booking(user, booking) do
      {:noreply, put_flash(socket, :info, dgettext("player", "Booking cancelled."))}
    else
      nil -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Bookings.error_message(reason))}
    end
  end

  defp status_result({:ok, _location, message}), do: {:ok, message}
  defp status_result(error), do: error

  # `datetime-local` inputs send no seconds and no zone: times are UTC.
  defp normalize_times(params) do
    Enum.reduce(["starts_at", "ends_at"], params, fn key, params ->
      case params[key] do
        <<_::binary-size(16)>> = value -> Map.put(params, key, value <> ":00Z")
        _ -> params
      end
    end)
  end

  ## PubSub

  @impl true
  def handle_info({event, message}, %{assigns: %{access?: true}} = socket)
      when event in [:new_message, :updated_message] do
    if Chat.visible?(message, socket.assigns.viewer),
      do: {:noreply, stream_insert(socket, :messages, message)},
      else: {:noreply, socket}
  end

  def handle_info({:deleted_message, message}, socket) do
    {:noreply, stream_delete(socket, :messages, message)}
  end

  def handle_info({:room_status, location}, socket) do
    {:noreply,
     update(
       socket,
       :location,
       &%{&1 | status: location.status, status_updated_at: location.status_updated_at}
     )}
  end

  def handle_info({:bookings_changed, _location_id}, socket) do
    {:noreply, socket |> load_bookings() |> refresh_access()}
  end

  def handle_info({:boards, event, _payload}, socket) when event in [:board, :notice] do
    {:noreply, load_boards(socket)}
  end

  def handle_info({:weather_changed, _story_id}, socket), do: {:noreply, load_weather(socket)}

  def handle_info(:recheck_access, socket) do
    {:noreply, socket |> assign(:recheck_ref, nil) |> load_bookings() |> refresh_access()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  ## Rendering helpers

  defp room_calendar(%{calendar: %TannhauserGate.Calendar.Config{} = calendar} = story),
    do: if(Stories.module_enabled?(story, :calendar), do: calendar)

  defp room_calendar(_story), do: nil

  defp speaker_label(%{is_npc: true, name: name}),
    do: dgettext("player", "%{name} (NPC)", name: name)

  defp speaker_label(%{name: name}), do: name

  defp kind_options(master?, rp?) do
    base = [
      {dgettext("player", "In character"), "speech"},
      {dgettext("player", "OFF (out of character)"), "ooc"}
    ]

    base = if rp?, do: base ++ [{dgettext("player", "Whisper"), "whisper"}], else: base

    if master?,
      do:
        base ++
          [
            {dgettext("player", "Narration"), "narration"},
            {dgettext("player", "Room status"), "status"}
          ],
      else: base
  end

  defp body_length(params),
    do: params |> Map.get("body", "") |> to_string() |> String.trim() |> String.length()

  # The length counter of the composer applies to in-character entries.
  defp counter?(form, rp?), do: rp? and form[:kind].value in [nil, "", "speech", "whisper"]

  defp counter_ok?(length, {min, max}),
    do: (is_nil(min) or length >= min) and (is_nil(max) or length <= max)

  defp counter_text(length, {_min, max}) when is_integer(max), do: "#{length} / #{max}"
  defp counter_text(length, _limits), do: "#{length}"

  defp can_reroll?(message, user, master?, config) do
    message.kind == "dice" and (master? or message.user_id == user.id) and
      Dice.rerollable?(config, message.data || %{})
  end

  defp can_cancel?(booking, user, master?), do: master? or booking.user_id == user.id

  defp format_slot(%{starts_at: starts_at, ends_at: ends_at}) do
    "#{format_local_date(starts_at, "%d %b %H:%M")} – #{Calendar.strftime(ends_at, "%H:%M")} UTC"
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
          navigate={~p"/g/#{@current_story}/map"}
          class="text-sm font-semibold text-mint hover:text-phosphor"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> {dgettext("player", "Back to the map")}
        </.link>
      </div>

      <.header>
        <span class="phosphor-text">{@location.name}</span>
        <span
          :if={@location.private}
          id="private-badge"
          class="ml-2 inline-flex items-center gap-1 rounded bg-error/15 px-2 py-0.5 align-middle text-xs font-bold uppercase tracking-widest text-error"
        >
          <.icon name="hero-lock-closed" class="size-3" /> {dgettext("player", "Private")}
        </span>

        <span
          :if={@room_guild}
          id="guild-badge"
          class="ml-2 inline-flex items-center gap-1 rounded bg-primary/15 px-2 py-0.5 align-middle text-xs font-bold uppercase tracking-widest text-primary"
        >
          <.icon name="hero-flag" class="size-3" /> {@room_guild}
        </span>

        <:subtitle>
          <span
            :if={@zone_weather || room_calendar(@current_story)}
            id="room-conditions"
            class="mb-1 flex flex-wrap items-center gap-2 text-xs"
          >
            <.game_clock
              id="room-game-clock"
              calendar={room_calendar(@current_story)}
              class="rounded border border-secondary/30 bg-secondary/5 px-2 py-0.5 font-semibold text-secondary"
            /> <.weather_badge id="room-weather" weather={@zone_weather} />
          </span>
          {@location.description}
        </:subtitle>

        <:actions :if={@shops != []}>
          <div id="room-shops" class="flex flex-wrap justify-end gap-2">
            <.link
              :for={shop <- @shops}
              id={"room-shop-#{shop.id}"}
              navigate={~p"/g/#{@current_story}/market/#{shop}"}
              class="inline-flex items-center gap-1.5 rounded-md border border-primary/40 px-3 py-1.5 text-xs font-bold uppercase tracking-wider text-primary transition hover:-translate-y-0.5 hover:bg-primary/10 hover:shadow-phosphor"
            >
              <.icon name="hero-building-storefront" class="size-4" /> {shop.name}
            </.link>
          </div>
        </:actions>
      </.header>

      <div
        :if={@location.status}
        id="room-status"
        class="mt-4 flex items-start gap-3 rounded-lg border border-info/30 bg-info/5 px-4 py-3 text-sm text-fog-200"
      >
        <.icon name="hero-sparkles" class="mt-0.5 size-4 shrink-0 text-info" />
        <p class="flex-1 whitespace-pre-line">{@location.status}</p>

        <button
          :if={@master?}
          id="clear-status"
          type="button"
          phx-click="clear_status"
          class="console-link-action text-xs text-fog-400 hover:text-error"
        >
          {dgettext("player", "Clear")}
        </button>
      </div>

      <.bookings_panel
        :if={@location.private}
        bookings={@bookings}
        active_booking={@active_booking}
        booking_form={@booking_form}
        invite_options={@invite_options}
        characters={@characters}
        current_user={@current_user}
        master?={@master?}
      /> <.zone_panel :if={@zone} zone={@zone} values={@zone_values} events={@zone_events} />
      <.boards_panel
        :if={@room_boards != []}
        boards={@room_boards}
        notices={@room_notices}
        story={@current_story}
      />
      <section
        :if={!@access?}
        id="private-locked"
        class="mt-6 rounded-xl border border-error/30 bg-ink/80 p-8 text-center"
      >
        <.icon name="hero-lock-closed" class="size-8 text-error" />
        <%= if @guild_locked? do %>
          <p id="guild-locked" class="mt-3 font-semibold text-fog-100">
            {dgettext("player", "This location is reserved to the members of a guild.")}
          </p>

          <p class="mt-1 text-sm text-fog-400">
            {dgettext("player", "Only the players of its active members and the masters can be here.")}
          </p>
        <% else %>
          <p class="mt-3 font-semibold text-fog-100">
            {dgettext("player", "This private location is not booked for you.")}
          </p>

          <p class="mt-1 text-sm text-fog-400">
            {dgettext(
              "player",
              "Only whoever booked it, the invited characters and the masters can be here during a booking."
            )}
          </p>
        <% end %>
      </section>

      <section
        :if={@access?}
        class="mt-6 flex h-[75vh] min-h-[38rem] flex-col overflow-hidden rounded-xl border border-base-content/15 bg-base-100"
      >
        <div :if={@more?} class="border-b border-mint/10 p-2 text-center">
          <button
            id="load-older"
            type="button"
            phx-click="load_older"
            phx-disable-with={dgettext("player", "Loading...")}
            class="console-link-action text-xs font-semibold text-mint hover:text-phosphor"
          >
            <.icon name="hero-chevron-double-up" class="size-3" /> {dgettext(
              "player",
              "Load older messages"
            )}
          </button>
        </div>

        <ol
          id="messages"
          phx-update="stream"
          phx-hook=".ScrollBottom"
          class="flex-1 space-y-4 overflow-y-auto p-4"
        >
          <li class="hidden only:block py-10 text-center text-sm text-fog-500" id="messages-empty">
            {dgettext("player", "The room is quiet. Only the rain is talking.")}
          </li>

          <li
            :for={{dom_id, message} <- @streams.messages}
            id={dom_id}
            class={["chat-message flex gap-3", "chat-#{message.kind}"]}
          >
            <.avatar
              :if={message.character}
              character={message.character}
              class={
                if(message.kind == "ooc",
                  do: "h-8 w-8 shrink-0 text-sm opacity-70",
                  else: "h-11 w-11 shrink-0 text-lg"
                )
              }
            />
            <span
              :if={!message.character}
              class={[
                "grid h-11 w-11 shrink-0 place-items-center rounded-full ring-2",
                if(message.kind == "status",
                  do: "bg-info/10 text-info ring-info/40",
                  else: "bg-warning/10 text-warning ring-warning/40"
                )
              ]}
            >
              <.icon
                name={if message.kind == "status", do: "hero-sparkles", else: "hero-book-open"}
                class="size-5"
              />
            </span>

            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-baseline gap-x-3">
                <.character_quick_links
                  :if={message.character}
                  id={"message-#{message.id}-speaker"}
                  story={@current_story}
                  character={message.character}
                  location={GdrPresence.character_location(@online, message.character.id, @master?)}
                  status={GdrPresence.character_status(@online, message.character.id)}
                  class={[
                    "chat-name font-bold",
                    if(message.kind == "ooc", do: "text-fog-300", else: "text-phosphor")
                  ]}
                />
                <span
                  :if={!message.character}
                  class={[
                    "chat-name font-bold",
                    if(message.kind == "status", do: "text-info", else: "text-warning")
                  ]}
                >
                  {Chat.speaker_name(message)}
                </span>
                <.kind_badge kind={message.kind} />
                <span
                  :if={message.kind == "whisper"}
                  id={"message-#{message.id}-recipient"}
                  class="inline-flex items-center gap-1 text-xs text-secondary"
                >
                  <.icon name="hero-arrow-long-right-micro" class="size-3" /> {(message.recipient_character &&
                                                                                  message.recipient_character.name) ||
                    dgettext("player", "a vanished character")}
                </span>

                <time class="text-xs text-fog-500" datetime={DateTime.to_iso8601(message.inserted_at)}>
                  {format_time(message.inserted_at)}
                </time>

                <button
                  :if={can_reroll?(message, @current_user, @master?, @dice_config)}
                  type="button"
                  id={"reroll-#{message.id}"}
                  phx-click="reroll"
                  phx-value-id={message.id}
                  data-confirm={
                    dgettext(
                      "player",
                      "Spend %{reroll_cost} to reroll up to %{reroll_max_dice} failed dice?",
                      reroll_cost: @dice_config.reroll_cost,
                      reroll_max_dice: @dice_config.reroll_max_dice
                    )
                  }
                  class="console-link-action text-xs font-semibold text-warning hover:underline"
                >
                  <.icon name="hero-arrow-path" class="size-3" /> {dgettext("player", "Reroll")}
                </button>

                <.report_link
                  :if={
                    Stories.module_enabled?(@current_story, :reports) and
                      message.user_id != @current_user.id
                  }
                  id={"report-message-#{message.id}"}
                  story={@current_story}
                  type="chat"
                  target_id={message.id}
                  return_to={~p"/g/#{@current_story}/rooms/#{@location}"}
                />
                <button
                  :if={MapSet.member?(@permissions, :can_moderate)}
                  type="button"
                  id={"delete-message-#{message.id}"}
                  phx-click="delete_message"
                  phx-value-id={message.id}
                  data-confirm={dgettext("player", "Delete this message?")}
                  class="console-link-action text-xs text-error/70 hover:text-error"
                  aria-label={dgettext("player", "Delete message")}
                >
                  <.icon name="hero-trash" class="size-3" />
                </button>
              </div>

              <.dice_result
                :if={message.kind == "dice" && message.data}
                id={"dice-result-#{message.id}"}
                result={message.data}
              />
              <.chat_body
                :if={message.kind != "dice"}
                id={"message-#{message.id}-body"}
                body={message.body}
                kind={message.kind}
                tag={@rp? && message.tag}
                highlight={@rp?}
                class={[
                  message.kind == "speech" && "text-fog-200",
                  message.kind == "whisper" &&
                    "rounded-md border-l-2 border-secondary/50 bg-secondary/5 px-2 py-1 text-fog-200",
                  message.kind == "ooc" && "text-sm italic text-fog-400",
                  message.kind == "narration" && "font-serif italic text-warning/90",
                  message.kind == "status" && "text-sm text-info/90"
                ]}
              />
            </div>
          </li>
        </ol>

        <div class="chat-composer border-t border-base-content/10 bg-base-200/35 p-4 sm:px-5">
          <p :if={@speakers == [] and !@master?} class="text-sm text-fog-400">
            {dgettext("player", "You need a character in this GDR to speak.")} <.link
              navigate={~p"/g/#{@current_story}/characters/new"}
              class="font-semibold text-mint hover:underline"
            >{dgettext("player", "Create one")}</.link>.
          </p>

          <p
            :if={@own_character && !Characters.can_play?(@own_character)}
            id="cannot-play-notice"
            class="mb-3 text-sm text-fog-400"
          >
            {@own_character.name} {dgettext(
              "player",
              "cannot speak in character yet (OFF messages are allowed): a master must approve it and its state must allow playing."
            )} <.link
              navigate={~p"/g/#{@current_story}/characters/#{@own_character}"}
              class="font-semibold text-mint hover:underline"
            >{dgettext("player", "Open the sheet")}</.link>.
          </p>

          <.form
            :if={@speakers != [] or @master?}
            for={@form}
            id={"message-form-#{@form_id}"}
            phx-change="change_message"
            phx-submit="send"
            class="grid grid-cols-1 gap-x-4 gap-y-1 sm:grid-cols-2 xl:grid-cols-4"
          >
            <div :if={@speakers != []}>
              <.input
                field={@form[:character_id]}
                type="select"
                label={dgettext("player", "Speak as")}
                options={Enum.map(@speakers, &{speaker_label(&1), &1.id})}
              />
            </div>

            <div>
              <.input
                field={@form[:kind]}
                type="select"
                label={dgettext("player", "Type")}
                options={
                  if @speakers == [],
                    do: [
                      {dgettext("player", "Narration"), "narration"},
                      {dgettext("player", "Room status"), "status"}
                    ],
                    else: kind_options(@master?, @rp?)
                }
              />
            </div>

            <div :if={@rp? && @form[:kind].value == "whisper"}>
              <.input
                field={@form[:recipient_character_id]}
                type="select"
                label={dgettext("player", "Whisper to")}
                prompt={dgettext("player", "Choose a character")}
                options={@recipient_options}
              />
            </div>

            <div :if={@rp? && @speakers != [] && counter?(@form, @rp?)}>
              <.input
                field={@form[:tag]}
                type="text"
                label={dgettext("player", "Action tag")}
                maxlength={Message.tag_max()}
                placeholder={dgettext("player", "at the bar")}
              />
            </div>

            <div class="relative col-span-full min-w-0">
              <.input
                field={@form[:body]}
                type="textarea"
                label={dgettext("player", "Message")}
                rows="3"
                placeholder={dgettext("player", "Let the scene unfold...")}
                phx-debounce="250"
                required
              />
              <p
                :if={@speakers != [] && counter?(@form, @rp?)}
                id="message-counter"
                class={[
                  "absolute right-0 top-1 font-mono text-[0.7rem] tabular-nums transition-colors",
                  if(counter_ok?(@body_length, @chat_limits),
                    do: "text-fog-500",
                    else: "text-error"
                  )
                ]}
              >
                <span :if={(elem(@chat_limits, 0) || 0) > 0} class="mr-2">{dgettext("player", "min")} {elem(
                  @chat_limits,
                  0
                )}</span> {counter_text(@body_length, @chat_limits)}
              </p>
            </div>

            <.button
              id="chat-send"
              phx-disable-with={dgettext("player", "Sending...")}
              class="btn btn-primary console-action col-span-full justify-self-end"
            >
              {dgettext("player", "Send")} <.icon name="hero-arrow-right-micro" class="size-4" />
            </.button>
          </.form>

          <details :if={@characters != []} id="dice-panel" class="group mt-3">
            <summary class="cursor-pointer select-none text-sm font-semibold text-mint hover:text-phosphor">
              <.icon name="hero-cube-transparent" class="size-4" /> {dgettext("player", "Roll dice")}
              <span class="ml-1 text-xs font-normal text-fog-500">
                ({system_name(@dice_config)})
              </span>
            </summary>

            <.form
              for={@dice_form}
              id={"dice-form-#{@form_id}"}
              phx-submit="roll"
              class="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
            >
              <.input
                field={@dice_form[:character_id]}
                type="select"
                label={dgettext("player", "Roll as")}
                options={Enum.map(@characters, &{speaker_label(&1), &1.id})}
              />
              <.input
                :if={@sheet_items != []}
                field={@dice_form[:items]}
                type="select"
                multiple
                label={
                  if @dice_config.system == "pool",
                    do: dgettext("player", "Pool (sheet items)"),
                    else: dgettext("player", "Add sheet items")
                }
                options={Enum.map(@sheet_items, &{&1.name, &1.slug})}
              />
              <.input
                :if={@dice_config.system == "expression"}
                field={@dice_form[:expression]}
                type="text"
                label={dgettext("player", "Expression")}
                placeholder={@dice_config.default_expression}
              />
              <.input
                field={@dice_form[:modifier]}
                type="number"
                label={
                  if @dice_config.system == "pool",
                    do: dgettext("player", "Extra dice"),
                    else: dgettext("player", "Modifier")
                }
              />
              <.input
                field={@dice_form[:difficulty]}
                type="number"
                label={dgettext("player", "Difficulty")}
                placeholder={
                  @dice_config.default_difficulty && to_string(@dice_config.default_difficulty)
                }
              />
              <.input
                field={@dice_form[:label]}
                type="text"
                label={dgettext("player", "Label")}
                placeholder={dgettext("player", "Optional")}
              />
              <div class="flex items-end">
                <.button
                  id="roll-dice"
                  phx-disable-with={dgettext("player", "Rolling...")}
                  class="btn btn-primary console-action mb-2 w-full"
                >
                  {dgettext("player", "Roll")}
                </.button>
              </div>
            </.form>
          </details>
        </div>
      </section>

      <.actions_panel
        :if={@access? && @periodic_actions != [] && @characters != []}
        actions={@periodic_actions}
        characters={@characters}
        cooldowns={@cooldowns}
        result={@action_result}
      />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollBottom">
        // Keeps the chat scrolled to the newest message unless the reader scrolled up,
        // and keeps the reading position when older messages are loaded on top.
        export default {
          mounted() {
            this.el.scrollTop = this.el.scrollHeight
            this.height = this.el.scrollHeight
            this.observer = new MutationObserver(() => {
              const previous = this.height
              this.height = this.el.scrollHeight
              if (this.older) {
                this.el.scrollTop = this.el.scrollHeight - previous
                this.older = false
                return
              }
              const nearBottom = previous - this.el.scrollTop - this.el.clientHeight < 200
              if (nearBottom || this.pending) this.el.scrollTop = this.el.scrollHeight
              this.pending = false
            })
            this.observer.observe(this.el, {childList: true})
            const section = this.el.closest("section")
            section?.addEventListener("submit", () => (this.pending = true))
            section?.addEventListener("click", e => {
              if (e.target.closest("#load-older")) this.older = true
            })
          },
          destroyed() {
            this.observer && this.observer.disconnect()
          }
        }
      </script>
    </Layouts.app>
    """
  end

  defp system_name(%{system: "pool"} = config),
    do:
      dgettext("player", "pool of d%{die_size}, success on %{success_threshold}+",
        die_size: config.die_size,
        success_threshold: config.success_threshold
      )

  defp system_name(%{system: "d20"}), do: dgettext("player", "d20 + modifier")

  defp system_name(%{system: "expression"} = config),
    do:
      dgettext("player", "dice expression, e.g. %{default_expression}",
        default_expression: config.default_expression
      )

  attr :bookings, :list, required: true
  attr :active_booking, :any, default: nil
  attr :booking_form, :any, required: true
  attr :invite_options, :list, required: true
  attr :characters, :list, required: true
  attr :current_user, :any, required: true
  attr :master?, :boolean, default: false

  defp bookings_panel(assigns) do
    ~H"""
    <section id="bookings" class="mt-4 rounded-xl border border-mint/20 bg-ink/60 p-4">
      <h2 class="flex items-center gap-2 text-sm font-bold uppercase tracking-widest text-fog-300">
        <.icon name="hero-calendar-days" class="size-4 text-mint" /> {dgettext("player", "Bookings")}
        <span
          :if={@active_booking}
          id="active-booking"
          class="ml-auto rounded bg-mint/15 px-2 py-0.5 text-[0.65rem] text-mint"
        >
          {dgettext("player", "Booked now by")} {@active_booking.character.name}
        </span>
      </h2>

      <ul class="mt-3 space-y-2 text-sm">
        <li :if={@bookings == []} class="text-fog-500">{dgettext("player", "No bookings yet.")}</li>

        <li
          :for={booking <- @bookings}
          id={"booking-#{booking.id}"}
          class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-fog-700/50 px-3 py-2"
        >
          <span class="font-mono text-xs text-fog-300">{format_slot(booking)}</span>
          <span class="font-semibold text-phosphor">{booking.character.name}</span>
          <span :if={booking.invited_characters != []} class="text-xs text-fog-400">
            {dgettext("player", "with")} {Enum.map_join(booking.invited_characters, ", ", & &1.name)}
          </span>

          <button
            :if={can_cancel?(booking, @current_user, @master?)}
            id={"cancel-booking-#{booking.id}"}
            type="button"
            phx-click="cancel_booking"
            phx-value-id={booking.id}
            data-confirm={dgettext("player", "Cancel this booking?")}
            class="console-link-action ml-auto text-xs text-error/80 hover:text-error"
          >
            {dgettext("player", "Cancel")}
          </button>
        </li>
      </ul>

      <details :if={@characters != []} id="booking-panel" class="mt-3">
        <summary class="cursor-pointer select-none text-sm font-semibold text-mint hover:text-phosphor">
          <.icon name="hero-plus" class="size-4" /> {dgettext("player", "Book this location")}
        </summary>

        <.form
          for={@booking_form}
          id="booking-form"
          phx-change="validate_booking"
          phx-submit="book"
          class="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
        >
          <.input
            field={@booking_form[:character_id]}
            type="select"
            label={dgettext("player", "Book as")}
            options={Enum.map(@characters, &{&1.name, &1.id})}
          />
          <.input
            field={@booking_form[:starts_at]}
            type="datetime-local"
            label={dgettext("player", "From (UTC)")}
            required
          />
          <.input
            field={@booking_form[:ends_at]}
            type="datetime-local"
            label={dgettext("player", "To (UTC)")}
            required
          />
          <.input
            field={@booking_form[:invitee_ids]}
            type="select"
            multiple
            label={dgettext("player", "Invite")}
            options={@invite_options}
          />
          <div class="sm:col-span-2 lg:col-span-4">
            <.button
              id="book-location"
              phx-disable-with={dgettext("player", "Booking...")}
              class="btn btn-primary console-action"
            >
              {dgettext("player", "Book")}
            </.button>
          </div>
        </.form>
      </details>
    </section>
    """
  end

  attr :boards, :list, required: true
  attr :notices, :map, required: true
  attr :story, :map, required: true

  defp boards_panel(assigns) do
    ~H"""
    <details
      id="room-boards-panel"
      class="group/boards mt-6 rounded-xl border border-secondary/25 bg-base-200/60 shadow-lg transition open:border-secondary/50"
    >
      <summary class="flex cursor-pointer select-none items-center gap-2 px-5 py-3 text-sm font-bold uppercase tracking-[0.2em] text-secondary transition hover:text-primary">
        <.icon name="hero-clipboard-document-list" class="size-4" /> {dgettext(
          "player",
          "Notice boards"
        )}
        <span class="rounded-full bg-secondary/15 px-2 text-xs tabular-nums">
          {@notices |> Map.values() |> Enum.map(&length/1) |> Enum.sum()}
        </span>

        <.icon
          name="hero-chevron-down-micro"
          class="ml-auto size-4 transition group-open/boards:rotate-180"
        />
      </summary>

      <div class="grid gap-4 px-5 pb-5 md:grid-cols-2">
        <section :for={board <- @boards} id={"room-board-#{board.id}"}>
          <header class="flex items-baseline justify-between gap-2">
            <h3 class="font-semibold text-primary">{board.name}</h3>

            <.link
              navigate={~p"/g/#{@story}/boards?board=#{board.id}"}
              class="text-xs text-secondary hover:text-primary"
            >
              {dgettext("player", "Pin a notice")}
              <.icon name="hero-arrow-right-micro" class="size-3" />
            </.link>
          </header>

          <p class="text-xs text-base-content/50">{Boards.place_label(board)}</p>

          <p
            :if={Map.get(@notices, board.id, []) == []}
            class="mt-2 text-sm text-base-content/50"
          >
            {dgettext("player", "Nothing pinned here.")}
          </p>

          <ul class="mt-2 space-y-2">
            <li
              :for={notice <- Map.get(@notices, board.id, [])}
              id={"room-notice-#{notice.id}"}
              class="board-notice"
            >
              <TannhauserGateWeb.BoardLive.Index.notice_card notice={notice} />
            </li>
          </ul>
        </section>
      </div>
    </details>
    """
  end
end
