defmodule TannhauserGateWeb.ReportLive.New do
  @moduledoc """
  The report form (`:reports` module): reached from the flag icon next to a
  chat entry, forum post, received letter, notice or character sheet
  (`?type=...&id=...`). It previews the reported content and files the
  report with a category and an optional explanation.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Reports

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :reports}}

  @impl true
  def mount(params, _session, socket) do
    %{current_user: user, current_story: story} = socket.assigns
    type = to_string(params["type"])
    return_to = safe_return_to(params["return_to"], story)

    case Reports.preview(user, story, type, params["id"]) do
      {:ok, target} ->
        {:ok,
         socket
         |> assign(:page_title, "Report to the masters")
         |> assign(:type, type)
         |> assign(:target_id, params["id"])
         |> assign(:target, target)
         |> assign(:return_to, return_to)
         |> assign(:form, to_form(%{"category" => "", "reason" => ""}, as: :report))}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, Reports.error_message(reason))
         |> push_navigate(to: return_to)}
    end
  end

  # Only paths inside the current GDR are accepted (no open redirects).
  defp safe_return_to(path, story) when is_binary(path) do
    prefix = "/g/#{story.id}"

    if (path == prefix or String.starts_with?(path, prefix <> "/")) and
         not String.contains?(path, ["//", "\\", ".."]),
       do: path,
       else: ~p"/g/#{story}"
  end

  defp safe_return_to(_path, story), do: ~p"/g/#{story}"

  @impl true
  def handle_event("validate", %{"report" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :report))}
  end

  def handle_event("save", %{"report" => params}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    attrs =
      params
      |> Map.take(["category", "reason"])
      |> Map.merge(%{
        "target_type" => socket.assigns.type,
        "target_id" => socket.assigns.target_id
      })

    case Reports.create_report(user, story, attrs) do
      {:ok, _report} ->
        {:noreply,
         socket
         |> put_flash(:info, "Report sent: the masters will look into it. Thank you.")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(params, as: :report, errors: changeset.errors, action: :insert)
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Reports.error_message(reason))}
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
      last_location={@last_location}
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <div class="mx-auto max-w-2xl">
        <.header>
          <span class="inline-flex items-center gap-2">
            <.icon name="hero-flag" class="size-6 text-warning" /> Report to the masters
          </span>
          <:subtitle>
            Reports are private: only the masters of {@current_story.name} read them.
          </:subtitle>
          <:actions>
            <.link navigate={@return_to} class="btn btn-ghost btn-sm console-action">
              <.icon name="hero-arrow-left" class="size-4" /> Back
            </.link>
          </:actions>
        </.header>

        <figure
          id="report-preview"
          class="mt-6 rounded-xl border border-warning/30 bg-base-200/70 p-5 shadow-sm"
        >
          <figcaption class="flex items-center gap-2 text-xs font-bold uppercase tracking-[0.2em] text-warning">
            {Reports.target_type_label(@type)}
            <span class="font-normal normal-case tracking-normal text-base-content/60">
              · {@target.label}
            </span>
          </figcaption>
          <blockquote class="mt-3 max-h-60 overflow-y-auto whitespace-pre-line border-l-2 border-warning/40 pl-3 text-sm text-base-content/80">
            {@target.snapshot}
          </blockquote>
        </figure>

        <.form
          for={@form}
          id="report-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-6 rounded-xl border border-secondary/30 bg-base-200/70 p-5"
        >
          <.input
            field={@form[:category]}
            type="select"
            label="Why are you reporting it?"
            prompt="Pick a reason"
            options={Reports.category_options()}
            required
          />
          <.input
            field={@form[:reason]}
            type="textarea"
            rows="4"
            label="Details (optional)"
            placeholder="Tell the masters what happened."
          />
          <div class="flex justify-end">
            <.button
              id="report-submit"
              class="btn btn-warning console-action"
              phx-disable-with="Sending..."
            >
              <.icon name="hero-paper-airplane" class="size-4" /> Send report
            </.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
