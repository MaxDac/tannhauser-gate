defmodule TannhauserGateWeb.ForumLive.Section do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.{Characters, Forum}
  alias TannhauserGateWeb.ForumLive.Index

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: user, current_story: story} = socket.assigns
    section = Forum.get_section!(id)

    if section.story_id == story.id and Forum.can_view_section?(user, story, section) do
      {:ok, load(socket, section)}
    else
      {:ok,
       socket
       |> put_flash(:error, dgettext("player", "That section does not exist in this GDR."))
       |> push_navigate(to: ~p"/g/#{story}/forum")}
    end
  end

  defp load(socket, section) do
    %{current_user: user, current_story: story} = socket.assigns

    characters =
      if section.on_game,
        do: user |> Characters.playable_characters(story) |> Enum.map(&character_option/1),
        else: []

    socket
    |> assign(:page_title, section.name)
    |> assign(:section, section)
    |> assign(:characters, characters)
    |> assign(:topics, Forum.list_topics(section, user))
    |> assign(:form, to_form(new_topic(characters), as: "topic"))
  end

  defp new_topic(characters) do
    %{"title" => "", "body" => "", "character_id" => default_character(characters)}
  end

  @doc false
  def character_option(character),
    do:
      {if(character.is_npc,
         do: dgettext("player", "%{name} (NPC)", name: character.name),
         else: character.name
       ), character.id}

  @doc false
  def default_character([{_, id} | _]), do: to_string(id)
  def default_character(_), do: ""

  @impl true
  def handle_event("create_topic", %{"topic" => params}, socket) do
    case Forum.create_topic(socket.assigns.current_user, socket.assigns.section, params) do
      {:ok, topic} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("player", "Topic created"))
         |> push_navigate(to: ~p"/g/#{socket.assigns.current_story}/forum/topics/#{topic}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(params, as: "topic", errors: changeset.errors, action: :insert)
         )}

      {:error, :muted} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           TannhauserGate.Sanctions.muted_message(
             socket.assigns.current_user,
             socket.assigns.current_story
           )
         )}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("player", "You cannot write in this section."))}
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
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/forum"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="h-3 w-3" /> {dgettext("player", "Forum")}
        </.link>
      </div>

      <.header>
        <span class="flex flex-wrap items-center gap-2">
          {@section.name} <Index.section_badges section={@section} />
        </span>

        <:subtitle>{@section.description}</:subtitle>
      </.header>

      <ul
        id="forum-topics"
        class="mt-8 divide-y divide-secondary/10 overflow-hidden rounded-xl border border-secondary/20 bg-base-200/80"
      >
        <li :if={@topics == []} class="p-4 text-sm text-base-content/60">
          {dgettext("player", "No topics yet. Start the first one.")}
        </li>

        <li :for={topic <- @topics} id={"forum-topic-#{topic.id}"}>
          <.link
            navigate={~p"/g/#{@current_story}/forum/topics/#{topic}"}
            class="group flex items-center justify-between gap-4 p-4 transition hover:bg-base-300/50"
          >
            <div class="flex min-w-0 items-center gap-3">
              <span
                :if={topic.unread}
                id={"topic-unread-#{topic.id}"}
                class="size-2 shrink-0 rounded-full bg-secondary shadow-[0_0_8px] shadow-secondary/70"
                title={dgettext("player", "New posts")}
              ></span>
              <div class="min-w-0">
                <p class={[
                  "flex items-center gap-2 truncate group-hover:text-primary",
                  if(topic.unread, do: "font-bold", else: "font-semibold text-base-content/80")
                ]}>
                  <.icon
                    :if={topic.pinned}
                    name="hero-bookmark-solid"
                    class="size-4 shrink-0 text-secondary"
                  />
                  <.icon
                    :if={topic.locked}
                    name="hero-lock-closed-solid"
                    class="size-4 shrink-0 text-warning"
                  /> <span class="truncate">{topic.title}</span>
                </p>

                <p class="text-xs text-base-content/50">
                  {dgettext("player", "by")} {Forum.author_name(topic)} · {format_time(
                    topic.inserted_at
                  )}
                </p>
              </div>
            </div>

            <span class="shrink-0 text-xs uppercase tracking-wider text-secondary">
              {dngettext("player", "%{count} post", "%{count} posts", topic.post_count)}
            </span>
          </.link>
        </li>
      </ul>

      <div class="mt-10 max-w-2xl rounded-xl border border-secondary/20 bg-base-200/80 p-6">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("player", "New topic")}
        </h2>

        <p
          :if={@section.on_game and @characters == []}
          id="forum-no-character"
          class="mt-3 text-sm text-base-content/70"
        >
          {dgettext(
            "player",
            "This section is on game: you need a character that can play to write here."
          )}
        </p>

        <.form
          :if={!@section.on_game or @characters != []}
          for={@form}
          id="topic-form"
          phx-submit="create_topic"
        >
          <.input
            :if={@section.on_game}
            field={@form[:character_id]}
            type="select"
            label={dgettext("player", "Write as")}
            options={@characters}
          />
          <p :if={!@section.on_game} class="mt-2 text-xs text-base-content/60">
            {dgettext("player", "Writing as")} {User.handle(@current_user)} {dgettext(
              "player",
              "(off game)."
            )}
          </p>
          <.input field={@form[:title]} type="text" label={dgettext("player", "Title")} required />
          <.input
            field={@form[:body]}
            type="textarea"
            label={dgettext("player", "First post")}
            rows="5"
            required
          />
          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <.button phx-disable-with={dgettext("player", "Posting...")}>{dgettext(
              "player",
              "Create topic"
            )}</.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
