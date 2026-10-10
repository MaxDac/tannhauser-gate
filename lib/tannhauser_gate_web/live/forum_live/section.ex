defmodule TannhauserGateWeb.ForumLive.Section do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Forum

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    section = Forum.get_section!(id)
    story = socket.assigns.current_story

    if section.story_id != story.id do
      {:ok,
       socket
       |> put_flash(:error, "That section does not exist in this GDR.")
       |> push_navigate(to: ~p"/g/#{story}/forum")}
    else
      {:ok, load(socket, section)}
    end
  end

  defp load(socket, section) do
    socket
    |> assign(:page_title, section.name)
    |> assign(:section, section)
    |> assign(:topics, Forum.list_topics(section))
    |> assign(:form, to_form(%{"title" => "", "body" => ""}, as: "topic"))
  end

  @impl true
  def handle_event("create_topic", %{"topic" => params}, socket) do
    case Forum.create_topic(socket.assigns.current_user, socket.assigns.section, params) do
      {:ok, topic} ->
        {:noreply,
         socket
         |> put_flash(:info, "Topic created")
         |> push_navigate(to: ~p"/g/#{socket.assigns.current_story}/forum/topics/#{topic}")}

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(params, as: "topic", errors: changeset.errors, action: :insert)
         )}
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
    >
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/forum"}
          class="text-sm font-semibold text-mint hover:text-phosphor"
        >
          <.icon name="hero-arrow-left-solid" class="h-3 w-3" /> Forum
        </.link>
      </div>

      <.header>
        {@section.name}
        <:subtitle>{@section.description}</:subtitle>
      </.header>

      <ul
        id="forum-topics"
        class="mt-8 divide-y divide-mint/10 rounded-xl border border-mint/20 bg-ink/80"
      >
        <li :if={@topics == []} class="p-4 text-sm text-fog-400">
          No topics yet. Start the first one.
        </li>
        <li :for={topic <- @topics}>
          <.link
            navigate={~p"/g/#{@current_story}/forum/topics/#{topic}"}
            class="flex items-center justify-between gap-4 p-4 hover:bg-white/5"
          >
            <div class="min-w-0">
              <p class="truncate font-bold text-fog-100">{topic.title}</p>
              <p class="text-xs text-fog-500">
                by {User.handle(topic.user)} · {format_time(topic.inserted_at)}
              </p>
            </div>
            <span class="shrink-0 text-xs uppercase tracking-wider text-mint">
              {topic.post_count} {if topic.post_count == 1, do: "post", else: "posts"}
            </span>
          </.link>
        </li>
      </ul>

      <div class="mt-10 max-w-2xl rounded-xl border border-mint/20 bg-ink/80 p-6">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-mint">New topic</h2>
        <.form for={@form} id="topic-form" phx-submit="create_topic">
          <.input field={@form[:title]} type="text" label="Title" required />
          <.input field={@form[:body]} type="textarea" label="First post" rows="5" required />
          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <.button phx-disable-with="Posting...">Create topic</.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
