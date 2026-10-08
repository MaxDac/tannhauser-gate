defmodule TannhauserGateWeb.ForumLive.Topic do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Accounts
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Forum

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    topic = Forum.get_topic!(id)

    {:ok,
     socket
     |> assign(:page_title, topic.title)
     |> assign(:topic, topic)
     |> assign(:form_id, 0)
     |> assign(:form, to_form(%{"body" => ""}, as: "post"))
     |> stream(:posts, Forum.list_posts(topic))}
  end

  @impl true
  def handle_event("create_post", %{"post" => params}, socket) do
    case Forum.create_post(socket.assigns.current_user, socket.assigns.topic, params) do
      {:ok, post} ->
        {:noreply,
         socket
         |> stream_insert(:posts, post)
         |> update(:form_id, &(&1 + 1))
         |> assign(:form, to_form(%{"body" => ""}, as: "post"))}

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(params, as: "post", errors: changeset.errors, action: :insert)
         )}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    if Accounts.admin?(socket.assigns.current_user) do
      post = Forum.get_post!(id)
      {:ok, _} = Forum.delete_post(post)
      {:noreply, stream_delete(socket, :posts, post)}
    else
      {:noreply, put_flash(socket, :error, "Admins only.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <div class="mb-4">
        <.link
          navigate={~p"/forum/sections/#{@topic.section_id}"}
          class="text-sm font-semibold text-mint hover:text-phosphor"
        >
          <.icon name="hero-arrow-left-solid" class="h-3 w-3" /> {@topic.section.name}
        </.link>
      </div>

      <.header>
        {@topic.title}
        <:subtitle>
          Started by {User.handle(@topic.user)} · {format_time(@topic.inserted_at)}
        </:subtitle>
      </.header>

      <ol id="forum-posts" phx-update="stream" class="mt-8 space-y-4">
        <li
          :for={{dom_id, post} <- @streams.posts}
          id={dom_id}
          class="forum-post rounded-xl border border-mint/20 bg-ink/80 p-4"
        >
          <div class="mb-2 flex items-center justify-between gap-3 text-xs text-fog-500">
            <span>
              <span class="font-bold text-mint">{User.handle(post.user)}</span>
              · {format_time(post.inserted_at)}
            </span>
            <button
              :if={TannhauserGate.Accounts.admin?(@current_user)}
              type="button"
              phx-click="delete_post"
              phx-value-id={post.id}
              data-confirm="Delete this post?"
              class="text-red-400 hover:underline"
            >
              Delete
            </button>
          </div>
          <p class="whitespace-pre-line break-words text-fog-200">{post.body}</p>
        </li>
      </ol>

      <div class="mt-8 max-w-3xl rounded-xl border border-mint/20 bg-ink/80 p-6">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-mint">Reply</h2>
        <.form for={@form} id={"post-form-#{@form_id}"} phx-submit="create_post">
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
