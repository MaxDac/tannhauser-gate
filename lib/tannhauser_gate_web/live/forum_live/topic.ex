defmodule TannhauserGateWeb.ForumLive.Topic do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.{Characters, Forum}
  alias TannhauserGateWeb.ForumLive.{Index, Section}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: user, current_story: story} = socket.assigns
    topic = Forum.get_topic!(id)

    if topic.section.story_id == story.id and
         Forum.can_view_section?(user, story, topic.section) do
      Forum.mark_topic_read(user, topic)
      {:ok, load(socket, topic)}
    else
      {:ok,
       socket
       |> put_flash(:error, "That topic does not exist in this GDR.")
       |> push_navigate(to: ~p"/g/#{story}/forum")}
    end
  end

  defp load(socket, topic) do
    %{current_user: user, current_story: story} = socket.assigns

    characters =
      if topic.section.on_game,
        do:
          user |> Characters.playable_characters(story) |> Enum.map(&Section.character_option/1),
        else: []

    socket
    |> assign(:page_title, topic.title)
    |> assign(:topic, topic)
    |> assign(:characters, characters)
    |> assign(:editing_post_id, nil)
    |> assign(:edit_form, nil)
    |> assign(:title_form, nil)
    |> assign(:form_id, 0)
    |> assign(:form, new_post_form(characters))
    |> stream(:posts, Forum.list_posts(topic))
  end

  defp new_post_form(characters) do
    to_form(%{"body" => "", "character_id" => Section.default_character(characters)}, as: "post")
  end

  defp can_edit?(%{user_id: user_id}, %User{id: user_id}, _master?), do: true
  defp can_edit?(_, _, master?), do: master?

  defp can_reply?(topic, master?), do: master? or not topic.locked

  @impl true
  def handle_event("create_post", %{"post" => params}, socket) do
    %{current_user: user, topic: topic} = socket.assigns

    case Forum.create_post(user, topic, params) do
      {:ok, post} ->
        {:noreply,
         socket
         |> stream_insert(:posts, post)
         |> update(:form_id, &(&1 + 1))
         |> assign(:form, new_post_form(socket.assigns.characters))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(params, as: "post", errors: changeset.errors, action: :insert)
         )}

      {:error, :locked} ->
        {:noreply, put_flash(socket, :error, "This topic is locked.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You cannot write in this section.")}
    end
  end

  def handle_event("edit_post", %{"id" => id}, socket) do
    with {:ok, post} <- fetch_post(socket, id),
         true <- can_edit?(post, socket.assigns.current_user, socket.assigns.master?) do
      {:noreply,
       socket
       |> restream_editing()
       |> assign(:editing_post_id, post.id)
       |> assign(:edit_form, to_form(%{"body" => post.body}, as: "edit"))
       |> stream_insert(:posts, post)}
    else
      _ -> {:noreply, put_flash(socket, :error, "You cannot edit that post.")}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:edit_form, nil) |> restream_editing()}
  end

  def handle_event("save_post", %{"edit" => params}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    with {:ok, post} <- fetch_post(socket, socket.assigns.editing_post_id),
         {:ok, updated} <- Forum.update_post(user, story, post, params) do
      updated = TannhauserGate.Repo.preload(updated, [:user, :character])

      {:noreply,
       socket
       |> assign(:editing_post_id, nil)
       |> assign(:edit_form, nil)
       |> put_flash(:info, "Post updated")
       |> stream_insert(:posts, updated)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(params, as: "edit", errors: changeset.errors, action: :update)
        {:ok, post} = fetch_post(socket, socket.assigns.editing_post_id)
        {:noreply, socket |> assign(:edit_form, form) |> stream_insert(:posts, post)}

      _ ->
        {:noreply, put_flash(socket, :error, "You cannot edit that post.")}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    with {:ok, post} <- fetch_post(socket, id),
         {:ok, _} <- Forum.delete_post(user, story, post) do
      {:noreply, stream_delete(socket, :posts, post)}
    else
      _ -> {:noreply, put_flash(socket, :error, "You cannot delete that post.")}
    end
  end

  def handle_event("toggle_flag", %{"flag" => flag}, socket) when flag in ~w(locked pinned) do
    %{current_user: user, current_story: story, topic: topic} = socket.assigns
    value = !Map.fetch!(topic, String.to_existing_atom(flag))

    case Forum.set_topic_flags(user, story, topic, %{flag => value}) do
      {:ok, updated} ->
        {:noreply,
         assign(socket, :topic, %{topic | locked: updated.locked, pinned: updated.pinned})}

      _ ->
        {:noreply, put_flash(socket, :error, "Only the GDR masters can do that.")}
    end
  end

  def handle_event("edit_topic", _params, socket) do
    {:noreply,
     assign(socket, :title_form, to_form(%{"title" => socket.assigns.topic.title}, as: "topic"))}
  end

  def handle_event("cancel_topic", _params, socket),
    do: {:noreply, assign(socket, :title_form, nil)}

  def handle_event("save_topic", %{"topic" => params}, socket) do
    %{current_user: user, current_story: story, topic: topic} = socket.assigns

    case Forum.update_topic(user, story, topic, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:topic, %{topic | title: updated.title})
         |> assign(:page_title, updated.title)
         |> assign(:title_form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :title_form,
           to_form(params, as: "topic", errors: changeset.errors, action: :update)
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "You cannot edit this topic.")}
    end
  end

  def handle_event("delete_topic", _params, socket) do
    %{current_user: user, current_story: story, topic: topic} = socket.assigns

    case Forum.delete_topic(user, story, topic) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Topic deleted")
         |> push_navigate(to: ~p"/g/#{story}/forum/sections/#{topic.section_id}")}

      _ ->
        {:noreply, put_flash(socket, :error, "You cannot delete this topic.")}
    end
  end

  # Re-renders the post being edited (if any) out of edit mode.
  defp restream_editing(socket) do
    socket =
      case fetch_post(socket, socket.assigns.editing_post_id) do
        {:ok, post} -> socket |> assign(:editing_post_id, nil) |> stream_insert(:posts, post)
        _ -> socket
      end

    assign(socket, :editing_post_id, nil)
  end

  defp fetch_post(socket, id) do
    with {int, ""} <- Integer.parse(to_string(id)),
         %{} = post <- TannhauserGate.Repo.get(TannhauserGate.Forum.Post, int),
         true <- post.topic_id == socket.assigns.topic.id do
      {:ok, TannhauserGate.Repo.preload(post, [:user, :character])}
    else
      _ -> {:error, :not_found}
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
      mail_unread={@mail_unread}
    >
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/forum/sections/#{@topic.section_id}"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="h-3 w-3" /> {@topic.section.name}
        </.link>
      </div>

      <.header>
        <span class="flex flex-wrap items-center gap-2">
          <.icon :if={@topic.pinned} name="hero-bookmark-solid" class="size-5 text-secondary" />
          <.icon :if={@topic.locked} name="hero-lock-closed-solid" class="size-5 text-warning" />
          {@topic.title}
          <Index.section_badges section={@topic.section} />
        </span>
        <:subtitle>
          Started by {Forum.author_name(@topic)} · {format_time(@topic.inserted_at)}
        </:subtitle>
        <:actions>
          <div class="flex flex-wrap gap-2">
            <button
              :if={@master?}
              id="toggle-pin"
              type="button"
              phx-click="toggle_flag"
              phx-value-flag="pinned"
              class="btn btn-ghost btn-xs console-action"
            >
              <.icon name="hero-bookmark" class="size-3" /> {if @topic.pinned,
                do: "Unpin",
                else: "Pin"}
            </button>
            <button
              :if={@master?}
              id="toggle-lock"
              type="button"
              phx-click="toggle_flag"
              phx-value-flag="locked"
              class="btn btn-ghost btn-xs console-action"
            >
              <.icon name="hero-lock-closed" class="size-3" />
              {if @topic.locked, do: "Unlock", else: "Lock"}
            </button>
            <button
              :if={can_edit?(@topic, @current_user, @master?)}
              id="edit-topic"
              type="button"
              phx-click="edit_topic"
              class="btn btn-ghost btn-xs console-action"
            >
              <.icon name="hero-pencil" class="size-3" /> Rename
            </button>
            <button
              :if={can_edit?(@topic, @current_user, @master?)}
              id="delete-topic"
              type="button"
              phx-click="delete_topic"
              data-confirm="Delete this topic and all its posts?"
              class="btn btn-ghost btn-xs text-error console-action"
            >
              <.icon name="hero-trash" class="size-3" /> Delete topic
            </button>
          </div>
        </:actions>
      </.header>

      <.form
        :if={@title_form}
        for={@title_form}
        id="topic-title-form"
        phx-submit="save_topic"
        class="mt-4 flex max-w-2xl items-end gap-2"
      >
        <div class="flex-1">
          <.input field={@title_form[:title]} type="text" label="Title" required />
        </div>
        <.button variant="primary" class="mb-2">Save</.button>
        <button type="button" phx-click="cancel_topic" class="btn btn-ghost mb-2">Cancel</button>
      </.form>

      <ol id="forum-posts" phx-update="stream" class="mt-8 space-y-4">
        <li
          :for={{dom_id, post} <- @streams.posts}
          id={dom_id}
          class="forum-post rounded-xl border border-secondary/20 bg-base-200/80 p-4 transition hover:border-secondary/40"
        >
          <div class="mb-2 flex items-center justify-between gap-3 text-xs text-base-content/50">
            <span>
              <span class="font-bold text-secondary">{Forum.author_name(post)}</span>
              · {format_time(post.inserted_at)}
              <span :if={post.edited_at} class="italic">· edited</span>
            </span>
            <span :if={can_edit?(post, @current_user, @master?)} class="flex gap-3">
              <button
                id={"edit-post-#{post.id}"}
                type="button"
                phx-click="edit_post"
                phx-value-id={post.id}
                class="console-link-action hover:text-primary hover:underline"
              >
                Edit
              </button>
              <button
                id={"delete-post-#{post.id}"}
                type="button"
                phx-click="delete_post"
                phx-value-id={post.id}
                data-confirm="Delete this post?"
                class="console-link-action text-error hover:underline"
              >
                Delete
              </button>
            </span>
          </div>
          <%= if @editing_post_id == post.id do %>
            <.form for={@edit_form} id={"edit-post-form-#{post.id}"} phx-submit="save_post">
              <.input field={@edit_form[:body]} type="textarea" label="Edit post" rows="4" required />
              <div class="mt-2 flex gap-2">
                <.button variant="primary">Save</.button>
                <button type="button" phx-click="cancel_edit" class="btn btn-ghost">Cancel</button>
              </div>
            </.form>
          <% else %>
            <p class="whitespace-pre-line break-words">{post.body}</p>
          <% end %>
        </li>
      </ol>

      <div class="mt-8 max-w-3xl rounded-xl border border-secondary/20 bg-base-200/80 p-6">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Reply</h2>
        <p
          :if={!can_reply?(@topic, @master?)}
          id="topic-locked"
          class="mt-3 text-sm text-base-content/70"
        >
          <.icon name="hero-lock-closed" class="size-4" /> This topic is locked.
        </p>
        <p
          :if={can_reply?(@topic, @master?) and @topic.section.on_game and @characters == []}
          id="forum-no-character"
          class="mt-3 text-sm text-base-content/70"
        >
          This section is on game: you need a character that can play to write here.
        </p>
        <.form
          :if={can_reply?(@topic, @master?) and (!@topic.section.on_game or @characters != [])}
          for={@form}
          id={"post-form-#{@form_id}"}
          phx-submit="create_post"
        >
          <.input
            :if={@topic.section.on_game}
            field={@form[:character_id]}
            type="select"
            label="Write as"
            options={@characters}
          />
          <.input field={@form[:body]} type="textarea" label="Your post" rows="4" required />
          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <.button phx-disable-with="Posting...">Post reply</.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
