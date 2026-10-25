defmodule TannhauserGateWeb.Admin.RequestsLive do
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.Admin.Components

  alias TannhauserGate.GdrRequests

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: dgettext("management", "GDR requests"),
       requests: GdrRequests.list_requests()
     )}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    request = GdrRequests.get_request!(id)

    case GdrRequests.approve_request(request, socket.assigns.current_user) do
      {:ok, _story} ->
        {:noreply,
         refresh(socket, dgettext("management", "Request approved. The GDR is now a draft."))}

      {:error, :not_gm} ->
        {:noreply,
         refresh_error(
           socket,
           dgettext("management", "The requester is no longer a game master.")
         )}

      {:error, :not_pending} ->
        {:noreply,
         refresh_error(socket, dgettext("management", "That request was already reviewed."))}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("management", "Could not approve the request."))}
    end
  end

  def handle_event("reject", %{"id" => id}, socket) do
    request = GdrRequests.get_request!(id)

    case GdrRequests.reject_request(request, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, refresh(socket, dgettext("management", "Request rejected."))}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("management", "Could not reject the request."))}
    end
  end

  defp refresh(socket, message) do
    socket
    |> put_flash(:info, message)
    |> assign(:requests, GdrRequests.list_requests())
  end

  defp refresh_error(socket, message) do
    socket
    |> put_flash(:error, message)
    |> assign(:requests, GdrRequests.list_requests())
  end

  defp request_status("pending"), do: dgettext("management", "pending")
  defp request_status("approved"), do: dgettext("management", "approved")
  defp request_status("rejected"), do: dgettext("management", "rejected")
  defp request_status(status), do: status

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>
        {dgettext("management", "GDR requests")}
        <:subtitle>
          {dgettext("management", "Game masters ask permission to run their own GDR.")}
        </:subtitle>
      </.header>

      <.table id="admin-requests" rows={@requests}>
        <:col :let={r} label={dgettext("management", "GM")}>{r.user.username}</:col>

        <:col :let={r} label={dgettext("management", "Name")}>{r.name}</:col>

        <:col :let={r} label={dgettext("management", "Pitch")}>{r.pitch}</:col>

        <:col :let={r} label={dgettext("management", "Status")}>{request_status(r.status)}</:col>

        <:action :let={r}>
          <.link
            :if={r.status == "pending"}
            id={"approve-#{r.id}"}
            phx-click="approve"
            phx-value-id={r.id}
          >
            {dgettext("management", "Approve")}
          </.link>
        </:action>

        <:action :let={r}>
          <.link
            :if={r.status == "pending"}
            id={"reject-#{r.id}"}
            phx-click="reject"
            phx-value-id={r.id}
          >
            {dgettext("management", "Reject")}
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
