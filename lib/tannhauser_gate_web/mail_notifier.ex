defmodule TannhauserGateWeb.MailNotifier do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  Keeps the `:mail_unread` assign (the unread badge of the GDR nav) up to date
  and flashes a notification when a message reaches the user's mailbox.

  Mounted with `on_mount {TannhauserGateWeb.MailNotifier, :subscribe}` after
  `UserAuth`'s `:load_story`. Mailbox broadcasts are also passed on to
  `TannhauserGateWeb.MailLive`, so it can refresh its lists.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, put_flash: 3]

  alias TannhauserGate.Mailbox
  alias TannhauserGate.Mailbox.Message

  def on_mount(:subscribe, _params, _session, socket) do
    story = socket.assigns.current_story
    identity = Mailbox.identity(socket.assigns.current_user, story)

    socket =
      socket
      |> assign(:mail_identity, identity)
      |> assign(:mail_unread, Mailbox.unread_count(story.id, identity))

    if connected?(socket) do
      Mailbox.subscribe(story.id)
      {:cont, attach_hook(socket, :mail_notifier, :handle_info, &handle_info/2)}
    else
      {:cont, socket}
    end
  end

  defp handle_info({:mailbox, event, message}, socket) do
    identity = socket.assigns.mail_identity

    socket =
      socket
      |> assign(:mail_unread, Mailbox.unread_count(socket.assigns.current_story.id, identity))
      |> maybe_notify(event, message, identity)

    if socket.view == TannhauserGateWeb.MailLive,
      do: {:cont, socket},
      else: {:halt, socket}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp maybe_notify(socket, :received, %Message{} = message, identity) do
    if Mailbox.in_inbox?(identity, message) and
         message.sender_user_id != socket.assigns.current_user.id do
      put_flash(
        socket,
        :info,
        dgettext("shared", "New message from %{sender}: %{subject}",
          sender: message.sender_name,
          subject: message.subject
        )
      )
    else
      socket
    end
  end

  defp maybe_notify(socket, _event, _message, _identity), do: socket
end
