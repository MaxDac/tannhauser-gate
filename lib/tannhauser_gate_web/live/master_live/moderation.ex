defmodule TannhauserGateWeb.MasterLive.Moderation do
  @moduledoc """
  Moderation for the masters of a GDR: the latest chat messages and forum posts
  of every room and topic, each of which can be deleted.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Chat, Forum}

  @impl true
  def mount(_params, _session, socket) do
    story_id = socket.assigns.current_story.id

    {:ok,
     socket
     |> assign(:page_title, "Moderation")
     |> stream(:messages, Chat.list_story_messages(story_id))
     |> stream(:posts, Forum.list_story_posts(story_id))}
  end

  @impl true
  def handle_event("delete_message", %{"id" => id}, socket) do
    case Chat.get_story_message(socket.assigns.current_story.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Message not found.")}

      message ->
        {:ok, _} = Chat.delete_message(message)

        {:noreply,
         socket |> stream_delete(:messages, message) |> put_flash(:info, "Message deleted")}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    case Forum.get_story_post(socket.assigns.current_story.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Post not found.")}

      post ->
        {:ok, _} = Forum.delete_post(post)
        {:noreply, socket |> stream_delete(:posts, post) |> put_flash(:info, "Post deleted")}
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
          navigate={~p"/g/#{@current_story}/master"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Master tools
        </.link>
      </div>

      <.header>
        Moderation
        <:subtitle>The latest chat messages and forum posts of {@current_story.name}.</:subtitle>
      </.header>

      <div class="mt-8 grid gap-8 lg:grid-cols-2">
        <section>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Chat messages</h2>
          <ul id="moderation-messages" phx-update="stream" class="mt-3 space-y-2">
            <li id="moderation-messages-empty" class="hidden text-sm text-base-content/60 only:block">
              No messages yet.
            </li>
            <li
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              class="flex items-start gap-3 rounded-lg border border-secondary/20 bg-base-200/80 p-3 transition hover:border-secondary/50"
            >
              <div class="min-w-0 flex-1">
                <p class="text-xs text-base-content/60">
                  <span class="font-semibold text-primary">
                    {(message.character && message.character.name) || message.user.username}
                  </span>
                  in {message.location.name}
                </p>
                <p class="mt-1 whitespace-pre-line break-words text-sm">{message.body}</p>
              </div>
              <button
                type="button"
                id={"delete-message-#{message.id}"}
                phx-click="delete_message"
                phx-value-id={message.id}
                data-confirm="Delete this message?"
                aria-label="Delete message"
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </li>
          </ul>
        </section>

        <section>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Forum posts</h2>
          <ul id="moderation-posts" phx-update="stream" class="mt-3 space-y-2">
            <li id="moderation-posts-empty" class="hidden text-sm text-base-content/60 only:block">
              No posts yet.
            </li>
            <li
              :for={{dom_id, post} <- @streams.posts}
              id={dom_id}
              class="flex items-start gap-3 rounded-lg border border-secondary/20 bg-base-200/80 p-3 transition hover:border-secondary/50"
            >
              <div class="min-w-0 flex-1">
                <p class="text-xs text-base-content/60">
                  <span class="font-semibold text-primary">{post.user.username}</span>
                  in
                  <.link
                    navigate={~p"/g/#{@current_story}/forum/topics/#{post.topic_id}"}
                    class="hover:underline"
                  >
                    {post.topic.title}
                  </.link>
                </p>
                <p class="mt-1 whitespace-pre-line break-words text-sm">{post.body}</p>
              </div>
              <button
                type="button"
                id={"delete-forum-post-#{post.id}"}
                phx-click="delete_post"
                phx-value-id={post.id}
                data-confirm="Delete this post?"
                aria-label="Delete post"
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
