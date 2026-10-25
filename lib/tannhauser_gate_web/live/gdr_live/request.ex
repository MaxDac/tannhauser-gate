defmodule TannhauserGateWeb.GdrLive.Request do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Accounts, GdrRequests, Stories}
  alias TannhauserGate.GdrRequests.GdrRequest

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, dgettext("player", "My GDR"))
     |> assign(:story, Stories.get_owned_story(user))
     |> assign(:latest, GdrRequests.latest_request(user))
     |> assign(:form, to_form(GdrRequests.change_request(%GdrRequest{})))}
  end

  @impl true
  def handle_event("validate", %{"gdr_request" => params}, socket) do
    changeset =
      %GdrRequest{} |> GdrRequests.change_request(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"gdr_request" => params}, socket) do
    case GdrRequests.create_request(socket.assigns.current_user, params) do
      {:ok, request} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("player", "Request sent. An admin will review it."))
         |> assign(:latest, request)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, message(reason))}
    end
  end

  defp message(:not_gm), do: dgettext("player", "Only game masters can request a GDR.")
  defp message(:already_has_gdr), do: dgettext("player", "You already run a GDR.")
  defp message(:pending), do: dgettext("player", "You already have a pending request.")

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :admin?, Accounts.admin?(assigns.current_user))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      current_story={@current_story}
      story_role={@story_role}
    >
      <.header>
        {dgettext("player", "My GDR")}
        <:subtitle>
          {dgettext("player", "Game masters run one GDR each, approved by an admin.")}
        </:subtitle>
      </.header>

      <div class="mt-6 max-w-2xl">
        <div
          :if={@story}
          id="owned-gdr"
          class="rounded-xl border border-secondary/20 bg-base-200/80 p-6"
        >
          <p class="text-lg font-bold text-primary">{@story.name}</p>

          <p class="mt-1 text-sm text-base-content/70">
            {dgettext("player", "Status:")} {story_status_label(@story.status)}
          </p>

          <.button id="open-dashboard" navigate={~p"/g/#{@story}/gm"} class="mt-4">
            {dgettext("player", "Open GM dashboard")}
          </.button>
        </div>

        <p
          :if={!@story && !@current_user.gm}
          id="not-gm"
          class="rounded-lg border border-dashed border-secondary/30 p-6 text-base-content/70"
        >
          {dgettext("player", "You are not a game master. Ask an admin to grant you the GM role.")}
        </p>

        <div
          :if={!@story && @latest && @latest.status == "pending"}
          id="request-pending"
          class="rounded-lg border border-secondary/30 p-6"
        >
          {dgettext("player", "Your request for \"%{name}\" is waiting for an admin.",
            name: @latest.name
          )}
        </div>

        <p
          :if={!@story && @latest && @latest.status == "rejected"}
          id="request-rejected"
          class="mb-4 text-error"
        >
          {dgettext("player", "Your last request (\"%{name}\") was rejected. You can send a new one.",
            name: @latest.name
          )}
        </p>

        <div
          :if={!@story && @current_user.gm && !(@latest && @latest.status == "pending")}
          class="rounded-xl border border-secondary/20 bg-base-200/80 p-6"
        >
          <.form for={@form} id="gdr-request-form" phx-change="validate" phx-submit="save">
            <.input field={@form[:name]} type="text" label={dgettext("player", "GDR name")} required />
            <.input
              field={@form[:pitch]}
              type="textarea"
              label={dgettext("player", "Pitch")}
              rows="6"
            />
            <.button phx-disable-with={dgettext("player", "Sending...")}>{dgettext(
              "player",
              "Request my GDR"
            )}</.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp story_status_label("draft"), do: dgettext("player", "draft")
  defp story_status_label("published"), do: dgettext("player", "published")
  defp story_status_label(status), do: status
end
