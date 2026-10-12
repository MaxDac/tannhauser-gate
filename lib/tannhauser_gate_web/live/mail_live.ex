defmodule TannhauserGateWeb.MailLive do
  @moduledoc """
  The GDR mailbox: the inbox and sent messages of the user's characters
  (and, for masters, of the NPCs and of "The masters"), a message view with
  reply and delete, bulk delete, and the compose form (`?to=character_id`
  preselects the recipient, `?reply=message_id` fills in a reply).
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Mailbox

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    {:ok,
     socket
     |> assign(:sender_options, Mailbox.sender_options(user, story))
     |> assign(:recipient_options, Mailbox.recipient_options(user, story))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :inbox, _params) do
    socket
    |> assign(:page_title, "Inbox")
    |> load_messages()
  end

  defp apply_action(socket, :sent, _params) do
    socket
    |> assign(:page_title, "Sent messages")
    |> load_messages()
  end

  defp apply_action(socket, :new, params) do
    %{current_user: user, current_story: story} = socket.assigns

    attrs =
      with id when is_binary(id) <- params["reply"],
           %{} = message <- Mailbox.get_message(user, story, id) do
        Mailbox.reply_attrs(user, story, message)
      else
        _ ->
          %{
            "sender" => default_option(socket.assigns.sender_options),
            "recipient" => params["to"] || "",
            "subject" => "",
            "body" => ""
          }
      end

    socket
    |> assign(:page_title, "New message")
    |> assign(:reply_to_id, attrs["reply_to_id"])
    |> assign(:form, to_form(Mailbox.change_message(attrs)))
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    %{current_user: user, current_story: story} = socket.assigns

    case Mailbox.get_message(user, story, id) do
      nil ->
        socket
        |> put_flash(:error, "Message not found")
        |> push_navigate(to: ~p"/g/#{story}/mail")

      message ->
        {:ok, message} = Mailbox.mark_read(user, story, message)
        identity = socket.assigns.mail_identity
        in_inbox? = Mailbox.in_inbox?(identity, message) and is_nil(message.recipient_deleted_at)

        socket
        |> assign(:page_title, message.subject)
        |> assign(:message, message)
        |> assign(:message_side, if(in_inbox?, do: :inbox, else: :sent))
        |> assign(:can_reply?, in_inbox? and socket.assigns.sender_options != [])
    end
  end

  defp default_option([{_label, value} | _]), do: value
  defp default_option(_), do: ""

  defp load_messages(socket) do
    %{current_user: user, current_story: story, live_action: action} = socket.assigns

    messages =
      case action do
        :inbox -> Mailbox.list_inbox(user, story)
        :sent -> Mailbox.list_sent(user, story)
      end

    socket
    |> assign(:messages_count, length(messages))
    |> stream(:messages, messages, reset: true)
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    form = params |> Mailbox.change_message() |> Map.put(:action, :validate) |> to_form()
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("send", %{"message" => params}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    case Mailbox.send_message(user, story, params) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> put_flash(:info, "Message sent")
         |> push_navigate(to: ~p"/g/#{story}/mail/sent")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete_selected", params, socket) do
    %{current_user: user, current_story: story, live_action: side} = socket.assigns

    case Map.get(params, "ids", []) do
      [] ->
        {:noreply, put_flash(socket, :error, "Select the messages to delete")}

      ids ->
        count = Mailbox.delete_messages(user, story, ids, side)

        {:noreply,
         socket
         |> put_flash(:info, "#{count} #{if count == 1, do: "message", else: "messages"} deleted")
         |> load_messages()}
    end
  end

  def handle_event("delete_message", _params, socket) do
    %{current_user: user, current_story: story, message: message, message_side: side} =
      socket.assigns

    Mailbox.delete_messages(user, story, [message.id], side)
    path = if side == :inbox, do: ~p"/g/#{story}/mail", else: ~p"/g/#{story}/mail/sent"

    {:noreply,
     socket
     |> put_flash(:info, "Message deleted")
     |> push_navigate(to: path)}
  end

  @impl true
  def handle_info({:mailbox, _event, _message}, socket) do
    if socket.assigns.live_action in [:inbox, :sent],
      do: {:noreply, load_messages(socket)},
      else: {:noreply, socket}
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
      <.header>
        Mail
        <:subtitle>Letters between the characters of {@current_story.name}.</:subtitle>
        <:actions>
          <.button id="compose-mail" variant="primary" navigate={~p"/g/#{@current_story}/mail/new"}>
            <.icon name="hero-pencil-square" class="size-4" /> Compose
          </.button>
        </:actions>
      </.header>

      <nav class="mt-6 flex gap-2" aria-label="Mailbox">
        <.mail_tab
          id="mail-tab-inbox"
          navigate={~p"/g/#{@current_story}/mail"}
          active={@live_action == :inbox}
        >
          <.icon name="hero-inbox" class="size-4" /> Inbox
          <span :if={@mail_unread > 0} class="badge badge-xs badge-secondary">{@mail_unread}</span>
        </.mail_tab>
        <.mail_tab
          id="mail-tab-sent"
          navigate={~p"/g/#{@current_story}/mail/sent"}
          active={@live_action == :sent}
        >
          <.icon name="hero-paper-airplane" class="size-4" /> Sent
        </.mail_tab>
      </nav>

      <section :if={@live_action in [:inbox, :sent]} class="mt-6">
        <form id="mail-list-form" phx-submit="delete_selected">
          <div class="mb-3 flex items-center justify-between">
            <p class="text-xs uppercase tracking-[0.2em] text-base-content/60">
              {@messages_count} {if @messages_count == 1, do: "message", else: "messages"}
            </p>
            <button
              :if={@messages_count > 0}
              id="delete-selected"
              type="submit"
              class="btn btn-error btn-outline btn-xs console-action"
              data-confirm="Delete the selected messages?"
            >
              <.icon name="hero-trash" class="size-3" /> Delete selected
            </button>
          </div>

          <ul
            id={if @live_action == :inbox, do: "mail-inbox", else: "mail-sent"}
            phx-update="stream"
            class="divide-y divide-secondary/15 overflow-hidden rounded-xl border border-secondary/20 bg-base-200/80"
          >
            <li id="mail-empty" class="hidden p-6 text-center text-sm text-base-content/60 only:block">
              {if @live_action == :inbox, do: "Your inbox is empty.", else: "No messages sent yet."}
            </li>
            <li
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              class={[
                "group flex items-center gap-3 px-4 py-3 transition hover:bg-base-300/50",
                @live_action == :inbox && is_nil(message.read_at) && "border-l-2 border-secondary"
              ]}
            >
              <input
                type="checkbox"
                name="ids[]"
                value={message.id}
                id={"select-message-#{message.id}"}
                aria-label={"Select #{message.subject}"}
                class="checkbox checkbox-sm checkbox-secondary"
              />
              <.link
                id={"mail-message-#{message.id}"}
                navigate={~p"/g/#{@current_story}/mail/#{message.id}"}
                class="flex min-w-0 flex-1 items-center gap-3"
              >
                <span
                  :if={@live_action == :inbox && is_nil(message.read_at)}
                  class="size-2 shrink-0 rounded-full bg-secondary shadow-[0_0_8px] shadow-secondary/70"
                  title="Unread"
                ></span>
                <span class="w-40 shrink-0 truncate text-sm text-base-content/70">
                  <%= if @live_action == :inbox do %>
                    {message.sender_name} → {Mailbox.recipient_name(message)}
                  <% else %>
                    To {Mailbox.recipient_name(message)}
                  <% end %>
                </span>
                <span class={[
                  "min-w-0 flex-1 truncate group-hover:text-primary",
                  @live_action == :inbox && is_nil(message.read_at) && "font-bold"
                ]}>
                  {message.subject}
                </span>
                <time
                  class="shrink-0 text-xs text-base-content/50"
                  datetime={DateTime.to_iso8601(message.inserted_at)}
                >
                  {Calendar.strftime(message.inserted_at, "%d/%m %H:%M")}
                </time>
              </.link>
            </li>
          </ul>
        </form>
      </section>

      <section :if={@live_action == :show} id="mail-show" class="mt-6">
        <article class="rounded-xl border border-secondary/20 bg-base-200/80 p-6">
          <h2 id="mail-subject" class="text-xl font-bold text-primary">{@message.subject}</h2>
          <dl class="mt-2 grid grid-cols-[auto_1fr] gap-x-3 text-sm text-base-content/70">
            <dt class="font-semibold">From</dt>
            <dd id="mail-from">{@message.sender_name}</dd>
            <dt class="font-semibold">To</dt>
            <dd id="mail-to">{Mailbox.recipient_name(@message)}</dd>
            <dt class="font-semibold">Date</dt>
            <dd>{Calendar.strftime(@message.inserted_at, "%d/%m/%Y %H:%M")}</dd>
          </dl>
          <div id="mail-body" class="mt-6 whitespace-pre-line leading-relaxed">{@message.body}</div>
        </article>

        <div class="mt-4 flex gap-2">
          <.button
            :if={@can_reply?}
            id="reply-message"
            variant="primary"
            navigate={~p"/g/#{@current_story}/mail/new?reply=#{@message.id}"}
          >
            <.icon name="hero-arrow-uturn-left" class="size-4" /> Reply
          </.button>
          <button
            id="delete-message"
            type="button"
            phx-click="delete_message"
            data-confirm="Delete this message?"
            class="btn btn-error btn-outline console-action"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </button>
        </div>
      </section>

      <section :if={@live_action == :new} class="mt-6 max-w-2xl">
        <p
          :if={@sender_options == []}
          id="mail-no-sender"
          class="rounded-xl border border-warning/40 bg-warning/10 p-4 text-sm"
        >
          You need an approved character that can play to send messages.
        </p>

        <.form
          :if={@sender_options != []}
          for={@form}
          id="mail-form"
          phx-change="validate"
          phx-submit="send"
          class="rounded-xl border border-secondary/20 bg-base-200/80 p-6"
        >
          <input
            :if={@reply_to_id}
            type="hidden"
            name="message[reply_to_id]"
            value={@reply_to_id}
          />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:sender]} type="select" label="From" options={@sender_options} />
            <.input
              field={@form[:recipient]}
              type="select"
              label="To"
              prompt="Choose a recipient"
              options={@recipient_options}
            />
          </div>
          <.input field={@form[:subject]} type="text" label="Subject" />
          <.input field={@form[:body]} type="textarea" label="Message" rows="8" />
          <.button variant="primary" id="send-mail" phx-disable-with="Sending...">
            <.icon name="hero-paper-airplane" class="size-4" /> Send
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp mail_tab(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class={[
        "flex items-center gap-2 rounded-md px-3 py-1.5 text-sm font-semibold uppercase tracking-wider transition",
        @active && "bg-secondary/15 text-secondary",
        !@active && "text-base-content/60 hover:bg-secondary/10 hover:text-secondary"
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
