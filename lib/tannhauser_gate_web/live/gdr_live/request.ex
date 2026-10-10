defmodule TannhauserGateWeb.GdrLive.Request do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Accounts, GdrRequests, Stories}
  alias TannhauserGate.GdrRequests.GdrRequest

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "My GDR")
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
         |> put_flash(:info, "Request sent. An admin will review it.")
         |> assign(:latest, request)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, message(reason))}
    end
  end

  defp message(:not_gm), do: "Only game masters can request a GDR."
  defp message(:already_has_gdr), do: "You already run a GDR."
  defp message(:pending), do: "You already have a pending request."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :admin?, Accounts.admin?(assigns.current_user))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      current_story={@current_story}
    >
      <.header>
        My GDR
        <:subtitle>Game masters run one GDR each, approved by an admin.</:subtitle>
      </.header>

      <div class="mt-6 max-w-2xl">
        <div
          :if={@story}
          id="owned-gdr"
          class="rounded-xl border border-secondary/20 bg-base-200/80 p-6"
        >
          <p class="text-lg font-bold text-primary">{@story.name}</p>

          <p class="mt-1 text-sm text-base-content/70">Status: {@story.status}</p>

          <.button id="open-dashboard" navigate={~p"/g/#{@story}/gm"} class="mt-4">
            Open GM dashboard
          </.button>
        </div>

        <p
          :if={!@story && !@current_user.gm}
          id="not-gm"
          class="rounded-lg border border-dashed border-secondary/30 p-6 text-base-content/70"
        >
          You are not a game master. Ask an admin to grant you the GM role.
        </p>

        <div
          :if={!@story && @latest && @latest.status == "pending"}
          id="request-pending"
          class="rounded-lg border border-secondary/30 p-6"
        >
          Your request for "{@latest.name}" is waiting for an admin.
        </div>

        <p
          :if={!@story && @latest && @latest.status == "rejected"}
          id="request-rejected"
          class="mb-4 text-error"
        >
          Your last request ("{@latest.name}") was rejected. You can send a new one.
        </p>

        <div
          :if={!@story && @current_user.gm && !(@latest && @latest.status == "pending")}
          class="rounded-xl border border-secondary/20 bg-base-200/80 p-6"
        >
          <.form for={@form} id="gdr-request-form" phx-change="validate" phx-submit="save">
            <.input field={@form[:name]} type="text" label="GDR name" required />
            <.input field={@form[:pitch]} type="textarea" label="Pitch" rows="6" />
            <.button phx-disable-with="Sending...">Request my GDR</.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
