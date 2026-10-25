defmodule TannhauserGateWeb.EsitoLive.Index do
  @moduledoc """
  The player's esiti (esiti module): the action requests filed by the user's
  characters with their status, and the form to file a new one for a master
  to resolve, within the GDR limits (open requests per character, minimum
  earned XP).
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.EsitiComponents

  alias TannhauserGate.{Characters, Esiti, Stories, Zones}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :esiti}}

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user, current_story: story} = socket.assigns
    if connected?(socket), do: Esiti.subscribe(story.id)
    characters = Esiti.requester_characters(user, story)

    {:ok,
     socket
     |> assign(:page_title, dgettext("player", "Esiti · %{name}", name: story.name))
     |> assign(:characters, characters)
     |> assign(:locations, Stories.list_locations(story))
     |> assign(:zones, Zones.list_zones(story))
     |> assign(:related_options, related_options(story, characters))
     |> reset_form()
     |> load()}
  end

  defp related_options(story, characters) do
    own = MapSet.new(characters, & &1.id)

    story.id
    |> Characters.list_story_characters(%{"approval_status" => "approved"})
    |> Enum.reject(&MapSet.member?(own, &1.id))
    |> Enum.map(&{&1.name, &1.id})
  end

  defp reset_form(socket) do
    character_id =
      case socket.assigns.characters do
        [character | _] -> character.id
        [] -> nil
      end

    assign(socket, :form, to_form(%{"character_id" => character_id}, as: :esito))
  end

  defp load(socket) do
    %{current_user: user, current_story: story} = socket.assigns
    esiti = Esiti.list_user_esiti(user, story)

    socket
    |> assign(:esiti_empty?, esiti == [])
    |> assign(
      :limits,
      Map.new(socket.assigns.characters, &{to_string(&1.id), Esiti.check_limits(story, &1)})
    )
    |> stream(:esiti, esiti, reset: true)
  end

  @impl true
  def handle_event("validate", %{"esito" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :esito))}
  end

  def handle_event("save", %{"esito" => params}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    case Esiti.create_esito(user, story, params) do
      {:ok, esito} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("player", "Request filed: the masters have been notified."))
         |> push_navigate(to: ~p"/g/#{story}/esiti/#{esito.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :esito))}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Esiti.error_message(reason))
         |> assign(:form, to_form(params, as: :esito))}
    end
  end

  @impl true
  def handle_info({:esiti, _event, %{user_id: user_id}}, socket)
      when user_id == socket.assigns.current_user.id,
      do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp limits_hint(story) do
    [
      story.esiti_max_open &&
        dgettext("player", "at most %{esiti_max_open} open requests per character",
          esiti_max_open: story.esiti_max_open
        ),
      story.esiti_min_xp &&
        dgettext("player", "at least %{esiti_min_xp} earned XP to file one",
          esiti_min_xp: story.esiti_min_xp
        )
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> nil
      parts -> dgettext("player", "Limits of this GDR: ") <> Enum.join(parts, ", ") <> "."
    end
  end

  defp limit_error(limits, character_id) do
    case Map.get(limits, to_string(character_id)) do
      {:error, reason} -> Esiti.error_message(reason)
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:hint, limits_hint(assigns.current_story))
      |> assign(:limit_error, limit_error(assigns.limits, assigns.form[:character_id].value))

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
        {dgettext("player", "Esiti")}
        <:subtitle>
          {dgettext(
            "player",
            "Ask the masters to resolve an action of your character: an investigation, a crafting job, a deal in the shadows. A master picks it up, talks it through with you and writes the outcome."
          )}
        </:subtitle>

        <:actions :if={MapSet.member?(@permissions, :can_manage_esiti_quests)}>
          <.link
            id="esiti-master-queue"
            navigate={~p"/g/#{@current_story}/master/esiti"}
            class="btn btn-sm btn-secondary btn-soft"
          >
            <.icon name="hero-inbox-stack" class="size-4" /> {dgettext("player", "Master queue")}
          </.link>
        </:actions>
      </.header>

      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_26rem]">
        <section>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {dgettext("player", "Your requests")}
          </h2>

          <p :if={@esiti_empty?} id="esiti-empty" class="mt-3 text-sm text-base-content/60">
            {dgettext("player", "No requests yet.")}
          </p>

          <ul id="my-esiti" phx-update="stream" class="mt-3 space-y-2">
            <li
              :for={{dom_id, esito} <- @streams.esiti}
              id={dom_id}
              class="rounded-xl border border-secondary/20 bg-base-200/60 transition hover:-translate-y-0.5 hover:border-primary/40"
            >
              <.link
                navigate={~p"/g/#{@current_story}/esiti/#{esito.id}"}
                class="flex items-start justify-between gap-3 p-4"
              >
                <div class="min-w-0">
                  <p class="truncate font-semibold text-primary">{esito.title}</p>

                  <p class="text-xs text-base-content/60">
                    {esito.character.name} <span :if={place(esito)}>· {place(esito)}</span>
                    · {when_label(esito.inserted_at)}
                    <span :if={esito.claimed_by && esito.status == "claimed"}>
                      {dgettext("player", "· handled by")} {esito.claimed_by.username}
                    </span>
                  </p>
                </div>
                <.status_badge status={esito.status} />
              </.link>
            </li>
          </ul>
        </section>

        <section
          id="new-esito"
          class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5"
        >
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {dgettext("player", "New request")}
          </h2>

          <p :if={@hint} id="esiti-limits" class="mt-1 text-xs text-base-content/60">{@hint}</p>

          <p
            :if={@characters == []}
            id="esiti-no-characters"
            class="mt-3 text-sm text-base-content/60"
          >
            {dgettext("player", "You need an approved character in this GDR to file a request.")}
          </p>

          <.form
            :if={@characters != []}
            for={@form}
            id="esito-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-4"
          >
            <.input
              field={@form[:character_id]}
              type="select"
              label={dgettext("player", "Character")}
              options={Enum.map(@characters, &{&1.name, &1.id})}
            />
            <p :if={@limit_error} id="esiti-limit-warning" class="-mt-1 mb-2 text-xs text-warning">
              <.icon name="hero-exclamation-triangle-micro" class="size-3" /> {@limit_error}
            </p>

            <.input
              field={@form[:title]}
              type="text"
              label={dgettext("player", "Title")}
              maxlength="120"
              required
            />
            <.input
              field={@form[:body]}
              type="textarea"
              label={dgettext("player", "What does your character do? (Markdown)")}
              rows="6"
              required
            />
            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@form[:location_id]}
                type="select"
                label={dgettext("player", "Room (optional)")}
                prompt="—"
                options={Enum.map(@locations, &{&1.name, &1.id})}
              />
              <.input
                field={@form[:zone_id]}
                type="select"
                label={dgettext("player", "Or zone (optional)")}
                prompt="—"
                options={Enum.map(@zones, &{&1.name, &1.id})}
              />
            </div>

            <.input
              :if={@related_options != []}
              field={@form[:related_ids]}
              type="select"
              multiple
              label={dgettext("player", "Other characters involved (optional)")}
              options={@related_options}
            />
            <.button
              id="file-esito"
              phx-disable-with={dgettext("player", "Filing...")}
              class="btn btn-primary mt-2 w-full"
            >
              <.icon name="hero-paper-airplane" class="size-4" /> {dgettext("player", "File request")}
            </.button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
