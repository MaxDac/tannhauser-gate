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
    Bookings,
    Characters,
    Chat,
    Dice,
    Items,
    PeriodicActions,
    Sheet,
    Stories,
    Zones
  }

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
       |> put_flash(:error, "That room does not exist in this GDR.")
       |> push_navigate(to: ~p"/g/#{story}/map")}
    else
      {:ok, load(socket, location)}
    end
  end

  defp load(socket, location) do
    %{current_user: user, current_story: story} = socket.assigns
    characters = Characters.playable_characters(user, story)
    own = Characters.get_user_story_character(user, story.id)
    speakers = if own && own not in characters, do: characters ++ [own], else: characters

    if connected?(socket) do
      Chat.subscribe(location.id)
      Bookings.subscribe(location.id)
    end

    socket
    |> assign(:page_title, location.name)
    |> assign(:location, location)
    |> assign(:shops, Items.list_location_shops(location))
    |> assign(:characters, characters)
    |> assign(:speakers, speakers)
    |> assign(:own_character, own)
    |> assign(:dice_config, Dice.config(story))
    |> assign(:sheet_items, Sheet.list_items(story))
    |> assign(:form_id, 0)
    |> assign(:form, new_form(speakers))
    |> assign(:dice_form, new_dice_form(characters))
    |> assign(:recheck_ref, nil)
    |> stream(:messages, [])
    |> assign(:access?, nil)
    |> GdrPresence.enter_location(location)
    |> load_zone()
    |> assign(:periodic_actions, PeriodicActions.list_actions(story))
    |> assign(:action_result, nil)
    |> load_cooldowns()
    |> load_bookings()
    |> refresh_access()
  end

  ## Zone and periodic actions

  defp load_zone(socket) do
    case Zones.zone_of(socket.assigns.location) do
      nil ->
        assign(socket, zone: nil, zone_values: [], zone_events: [])

      zone ->
        assign(socket,
          zone: zone,
          zone_values: Zones.zone_values(zone, public_only: !socket.assigns.master?),
          zone_events: Zones.list_events(zone, 5)
        )
    end
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
    to_form(%{"character_id" => character_id, "kind" => kind, "body" => ""}, as: "message")
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
    |> assign(:active_booking, location.private && Bookings.active_booking(location))
    |> schedule_recheck()
  end

  defp load_messages(socket) do
    {messages, more?} = Chat.page_messages(socket.assigns.location.id, limit: @page_size)

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
        # a new id while keeping the selected character and kind.
        {:noreply,
         socket
         |> update(:form_id, &(&1 + 1))
         |> assign(:form, new_form(socket.assigns.speakers, params))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :form, to_form(params, as: "message", errors: changeset.errors))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Chat.error_message(reason))}
    end
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
        {:noreply, put_flash(socket, :error, "You cannot perform this action here.")}
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
        before: socket.assigns.oldest
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

    with true <- socket.assigns.master?,
         %{} = message <- Chat.get_story_message(story.id, id) do
      {:ok, _} = Chat.delete_message(message)
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Only the GDR masters can delete messages.")}
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
         |> put_flash(:info, "Location booked.")
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
      {:noreply, put_flash(socket, :info, "Booking cancelled.")}
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
  def handle_info({:new_message, message}, %{assigns: %{access?: true}} = socket) do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  def handle_info({:updated_message, message}, %{assigns: %{access?: true}} = socket) do
    {:noreply, stream_insert(socket, :messages, message)}
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

  def handle_info(:recheck_access, socket) do
    {:noreply, socket |> assign(:recheck_ref, nil) |> load_bookings() |> refresh_access()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  ## Rendering helpers

  defp speaker_label(%{is_npc: true, name: name}), do: "#{name} (NPC)"
  defp speaker_label(%{name: name}), do: name

  defp kind_options(master?) do
    base = [{"In character", "speech"}, {"OFF (out of character)", "ooc"}]
    if master?, do: base ++ [{"Narration", "narration"}, {"Room status", "status"}], else: base
  end

  defp can_reroll?(message, user, master?, config) do
    message.kind == "dice" and (master? or message.user_id == user.id) and
      Dice.rerollable?(config, message.data || %{})
  end

  defp can_cancel?(booking, user, master?), do: master? or booking.user_id == user.id

  defp format_slot(%{starts_at: starts_at, ends_at: ends_at}) do
    "#{Calendar.strftime(starts_at, "%d %b %H:%M")} – #{Calendar.strftime(ends_at, "%H:%M")} UTC"
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
      mail_unread={@mail_unread}
    >
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/map"}
          class="text-sm font-semibold text-mint hover:text-phosphor"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Back to the map
        </.link>
      </div>

      <.header>
        <span class="phosphor-text">{@location.name}</span>
        <span
          :if={@location.private}
          id="private-badge"
          class="ml-2 inline-flex items-center gap-1 rounded bg-error/15 px-2 py-0.5 align-middle text-xs font-bold uppercase tracking-widest text-error"
        >
          <.icon name="hero-lock-closed" class="size-3" /> Private
        </span>

        <:subtitle>{@location.description}</:subtitle>
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
          Clear
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
      />
      <.zone_panel :if={@zone} zone={@zone} values={@zone_values} events={@zone_events} />
      <section
        :if={!@access?}
        id="private-locked"
        class="mt-6 rounded-xl border border-error/30 bg-ink/80 p-8 text-center"
      >
        <.icon name="hero-lock-closed" class="size-8 text-error" />
        <p class="mt-3 font-semibold text-fog-100">This private location is not booked for you.</p>

        <p class="mt-1 text-sm text-fog-400">
          Only whoever booked it, the invited characters and the masters can be here during a booking.
        </p>
      </section>

      <section
        :if={@access?}
        class="mt-6 flex h-[65vh] flex-col overflow-hidden rounded-xl border border-mint/30 bg-ink/80"
      >
        <div :if={@more?} class="border-b border-mint/10 p-2 text-center">
          <button
            id="load-older"
            type="button"
            phx-click="load_older"
            phx-disable-with="Loading..."
            class="console-link-action text-xs font-semibold text-mint hover:text-phosphor"
          >
            <.icon name="hero-chevron-double-up" class="size-3" /> Load older messages
          </button>
        </div>

        <ol
          id="messages"
          phx-update="stream"
          phx-hook=".ScrollBottom"
          class="flex-1 space-y-4 overflow-y-auto p-4"
        >
          <li class="hidden only:block py-10 text-center text-sm text-fog-500" id="messages-empty">
            The room is quiet. Only the rain is talking.
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
                <time class="text-xs text-fog-500" datetime={DateTime.to_iso8601(message.inserted_at)}>
                  {format_time(message.inserted_at)}
                </time>

                <button
                  :if={can_reroll?(message, @current_user, @master?, @dice_config)}
                  type="button"
                  id={"reroll-#{message.id}"}
                  phx-click="reroll"
                  phx-value-id={message.id}
                  data-confirm={"Spend #{@dice_config.reroll_cost} to reroll up to #{@dice_config.reroll_max_dice} failed dice?"}
                  class="console-link-action text-xs font-semibold text-warning hover:underline"
                >
                  <.icon name="hero-arrow-path" class="size-3" /> Reroll
                </button>

                <button
                  :if={@master?}
                  type="button"
                  id={"delete-message-#{message.id}"}
                  phx-click="delete_message"
                  phx-value-id={message.id}
                  data-confirm="Delete this message?"
                  class="console-link-action text-xs text-error/70 hover:text-error"
                  aria-label="Delete message"
                >
                  <.icon name="hero-trash" class="size-3" />
                </button>
              </div>

              <.dice_result
                :if={message.kind == "dice" && message.data}
                id={"dice-result-#{message.id}"}
                result={message.data}
              />
              <p
                :if={message.kind != "dice"}
                class={[
                  "chat-body whitespace-pre-line break-words",
                  message.kind == "speech" && "text-fog-200",
                  message.kind == "ooc" && "text-sm italic text-fog-400",
                  message.kind == "narration" && "font-serif italic text-warning/90",
                  message.kind == "status" && "text-sm text-info/90"
                ]}
              >
                {message.body}
              </p>
            </div>
          </li>
        </ol>

        <div class="border-t border-mint/20 bg-night/60 p-4">
          <p :if={@speakers == [] and !@master?} class="text-sm text-fog-400">
            You need a character in this GDR to speak. <.link
              navigate={~p"/g/#{@current_story}/characters/new"}
              class="font-semibold text-mint hover:underline"
            >Create one</.link>.
          </p>

          <p
            :if={@own_character && !Characters.can_play?(@own_character)}
            id="cannot-play-notice"
            class="mb-3 text-sm text-fog-400"
          >
            {@own_character.name} cannot speak in character yet (OFF messages are allowed):
            a master must approve it and its state must allow playing. <.link
              navigate={~p"/g/#{@current_story}/characters/#{@own_character}"}
              class="font-semibold text-mint hover:underline"
            >Open the sheet</.link>.
          </p>

          <.form
            :if={@speakers != [] or @master?}
            for={@form}
            id={"message-form-#{@form_id}"}
            phx-submit="send"
            class="flex flex-col gap-3 sm:flex-row sm:items-end"
          >
            <div :if={@speakers != []} class="sm:w-52">
              <.input
                field={@form[:character_id]}
                type="select"
                label="Speak as"
                options={Enum.map(@speakers, &{speaker_label(&1), &1.id})}
              />
            </div>

            <div class="sm:w-44">
              <.input
                field={@form[:kind]}
                type="select"
                label="Type"
                options={
                  if @speakers == [],
                    do: tl(tl(kind_options(true))),
                    else: kind_options(@master?)
                }
              />
            </div>

            <div class="flex-1">
              <.input
                field={@form[:body]}
                type="textarea"
                label="Message"
                rows="2"
                placeholder="Say something..."
                required
              />
            </div>

            <.button
              phx-disable-with="Sending..."
              class="btn btn-primary console-action sm:mb-[1.125rem]"
            >
              Send
            </.button>
          </.form>

          <details :if={@characters != []} id="dice-panel" class="group mt-3">
            <summary class="cursor-pointer select-none text-sm font-semibold text-mint hover:text-phosphor">
              <.icon name="hero-cube-transparent" class="size-4" /> Roll dice
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
                label="Roll as"
                options={Enum.map(@characters, &{speaker_label(&1), &1.id})}
              />
              <.input
                :if={@sheet_items != []}
                field={@dice_form[:items]}
                type="select"
                multiple
                label={
                  if @dice_config.system == "pool", do: "Pool (sheet items)", else: "Add sheet items"
                }
                options={Enum.map(@sheet_items, &{&1.name, &1.slug})}
              />
              <.input
                :if={@dice_config.system == "expression"}
                field={@dice_form[:expression]}
                type="text"
                label="Expression"
                placeholder={@dice_config.default_expression}
              />
              <.input
                field={@dice_form[:modifier]}
                type="number"
                label={if @dice_config.system == "pool", do: "Extra dice", else: "Modifier"}
              />
              <.input
                field={@dice_form[:difficulty]}
                type="number"
                label="Difficulty"
                placeholder={
                  @dice_config.default_difficulty && to_string(@dice_config.default_difficulty)
                }
              />
              <.input field={@dice_form[:label]} type="text" label="Label" placeholder="Optional" />
              <div class="flex items-end">
                <.button
                  id="roll-dice"
                  phx-disable-with="Rolling..."
                  class="btn btn-primary console-action mb-2 w-full"
                >
                  Roll
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
    do: "pool of d#{config.die_size}, success on #{config.success_threshold}+"

  defp system_name(%{system: "d20"}), do: "d20 + modifier"

  defp system_name(%{system: "expression"} = config),
    do: "dice expression, e.g. #{config.default_expression}"

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
        <.icon name="hero-calendar-days" class="size-4 text-mint" /> Bookings
        <span
          :if={@active_booking}
          id="active-booking"
          class="ml-auto rounded bg-mint/15 px-2 py-0.5 text-[0.65rem] text-mint"
        >
          Booked now by {@active_booking.character.name}
        </span>
      </h2>

      <ul class="mt-3 space-y-2 text-sm">
        <li :if={@bookings == []} class="text-fog-500">No bookings yet.</li>

        <li
          :for={booking <- @bookings}
          id={"booking-#{booking.id}"}
          class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-fog-700/50 px-3 py-2"
        >
          <span class="font-mono text-xs text-fog-300">{format_slot(booking)}</span>
          <span class="font-semibold text-phosphor">{booking.character.name}</span>
          <span :if={booking.invited_characters != []} class="text-xs text-fog-400">
            with {Enum.map_join(booking.invited_characters, ", ", & &1.name)}
          </span>

          <button
            :if={can_cancel?(booking, @current_user, @master?)}
            id={"cancel-booking-#{booking.id}"}
            type="button"
            phx-click="cancel_booking"
            phx-value-id={booking.id}
            data-confirm="Cancel this booking?"
            class="console-link-action ml-auto text-xs text-error/80 hover:text-error"
          >
            Cancel
          </button>
        </li>
      </ul>

      <details :if={@characters != []} id="booking-panel" class="mt-3">
        <summary class="cursor-pointer select-none text-sm font-semibold text-mint hover:text-phosphor">
          <.icon name="hero-plus" class="size-4" /> Book this location
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
            label="Book as"
            options={Enum.map(@characters, &{&1.name, &1.id})}
          />
          <.input field={@booking_form[:starts_at]} type="datetime-local" label="From (UTC)" required />
          <.input field={@booking_form[:ends_at]} type="datetime-local" label="To (UTC)" required />
          <.input
            field={@booking_form[:invitee_ids]}
            type="select"
            multiple
            label="Invite"
            options={@invite_options}
          />
          <div class="sm:col-span-2 lg:col-span-4">
            <.button
              id="book-location"
              phx-disable-with="Booking..."
              class="btn btn-primary console-action"
            >
              Book
            </.button>
          </div>
        </.form>
      </details>
    </section>
    """
  end
end
