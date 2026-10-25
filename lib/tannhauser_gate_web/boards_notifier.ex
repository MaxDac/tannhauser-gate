defmodule TannhauserGateWeb.BoardsNotifier do
  @moduledoc """
  Keeps the `:announcements_unread` assign (the unread badge of the Home link
  in the GDR nav) up to date when the boards module is enabled.

  Mounted with `on_mount {TannhauserGateWeb.BoardsNotifier, :subscribe}` after
  `UserAuth`'s `:load_story`. It subscribes to `TannhauserGate.Boards.topic/1`
  and passes the board broadcasts on to the LiveViews that show boards or
  announcements (`@listeners`); the others only get the badge updated.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias TannhauserGate.Boards

  @listeners [
    TannhauserGateWeb.GdrLive.Home,
    TannhauserGateWeb.RoomLive,
    TannhauserGateWeb.BoardLive.Index,
    TannhauserGateWeb.MasterLive.Boards
  ]

  def on_mount(:subscribe, _params, _session, socket) do
    %{current_story: story, current_user: user} = socket.assigns
    enabled? = Boards.enabled?(story)

    socket =
      assign(
        socket,
        :announcements_unread,
        if(enabled?, do: Boards.unread_count(user, story), else: 0)
      )

    if enabled? and connected?(socket) do
      Boards.subscribe(story.id)
      {:cont, attach_hook(socket, :boards_notifier, :handle_info, &handle_info/2)}
    else
      {:cont, socket}
    end
  end

  defp handle_info({:boards, event, payload}, socket) do
    socket = refresh_badge(socket, event, payload)

    if socket.view in @listeners,
      do: {:cont, socket},
      else: {:halt, socket}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp refresh_badge(socket, :announcement, _announcement), do: refresh(socket)

  defp refresh_badge(socket, :read, %{user_id: user_id}) do
    if user_id == socket.assigns.current_user.id, do: refresh(socket), else: socket
  end

  defp refresh_badge(socket, _event, _payload), do: socket

  defp refresh(socket) do
    %{current_story: story, current_user: user} = socket.assigns
    assign(socket, :announcements_unread, Boards.unread_count(user, story))
  end
end
