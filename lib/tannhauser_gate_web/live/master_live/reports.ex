defmodule TannhauserGateWeb.MasterLive.Reports do
  @moduledoc """
  The reports queue of the `:reports` module (moderators only): the reports
  filed by the members, filterable by status, content type and category.
  Each open report can be resolved or dismissed with notes, optionally
  deleting the reported content, and its author can be sanctioned.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Reports
  alias TannhauserGate.Reports.Report

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :reports}}
  on_mount {TannhauserGateWeb.UserAuth, {:require_permission, :can_moderate}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reports")
     |> assign(:resolution_form, to_form(%{}, as: :resolution))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      "status" => valid(params["status"], ["all" | Report.statuses()], "open"),
      "target_type" => valid(params["target_type"], Report.target_types(), ""),
      "category" => valid(params["category"], Report.categories(), "")
    }

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> load_reports()}
  end

  defp valid(value, allowed, default), do: if(value in allowed, do: value, else: default)

  defp load_reports(socket) do
    reports = Reports.list_reports(socket.assigns.current_story, socket.assigns.filters)

    socket
    |> assign(:reports_count, length(reports))
    |> assign(:open_count, Reports.open_count(socket.assigns.current_story))
    |> stream(:reports, reports, reset: true)
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    query =
      params
      |> Map.take(["status", "target_type", "category"])
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    {:noreply,
     push_patch(socket, to: ~p"/g/#{socket.assigns.current_story}/master/reports?#{query}")}
  end

  def handle_event("resolve", %{"resolution" => params}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    with %Report{} = report <-
           Reports.get_report(story, params["report_id"]) || {:error, :not_found},
         {:ok, report} <- Reports.resolve(user, story, report, params) do
      message =
        "Report #{Reports.status_label(report.status) |> String.downcase()}" <>
          if(report.content_deleted, do: ": the content was deleted.", else: ".")

      {:noreply, socket |> put_flash(:info, message) |> load_reports()}
    else
      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Pick whether to resolve or dismiss the report.")}

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
      <.header>
        Reports
        <span
          :if={@open_count > 0}
          id="reports-open-count"
          class="badge badge-warning badge-sm ml-2 align-middle"
        >
          {@open_count} open
        </span>
        <:subtitle>
          Content flagged by the members. Resolve or dismiss each report; snapshots keep the
          reported text even if it was deleted.
        </:subtitle>
        <:actions>
          <.link
            navigate={~p"/g/#{@current_story}/master/sanctions"}
            class="btn btn-ghost btn-sm console-action"
          >
            <.icon name="hero-no-symbol" class="size-4" /> Sanctions
          </.link>
          <.link
            navigate={~p"/g/#{@current_story}/master"}
            class="btn btn-ghost btn-sm console-action"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Master tools
          </.link>
        </:actions>
      </.header>

      <.form
        for={@filter_form}
        id="reports-filters"
        phx-change="filter"
        class="mt-6 grid gap-x-3 rounded-xl border border-base-300 bg-base-200/60 px-4 pt-3 sm:grid-cols-3"
      >
        <.input
          field={@filter_form[:status]}
          type="select"
          label="Status"
          options={[
            {"Open", "open"},
            {"Resolved", "resolved"},
            {"Dismissed", "dismissed"},
            {"All", "all"}
          ]}
        />
        <.input
          field={@filter_form[:target_type]}
          type="select"
          label="Content"
          prompt="Any content"
          options={Enum.map(Report.target_types(), &{Reports.target_type_label(&1), &1})}
        />
        <.input
          field={@filter_form[:category]}
          type="select"
          label="Category"
          prompt="Any category"
          options={Reports.category_options()}
        />
      </.form>

      <p :if={@reports_count == 0} id="reports-empty" class="mt-10 text-center text-base-content/60">
        <.icon name="hero-check-badge" class="size-8 text-success/70" />
        <br /> No reports here.
      </p>

      <div id="reports" phx-update="stream" class="mt-6 space-y-4">
        <article
          :for={{dom_id, report} <- @streams.reports}
          id={dom_id}
          class={[
            "rounded-xl border bg-base-200/70 p-5 shadow-sm transition-colors",
            if(report.status == "open",
              do: "border-warning/40 hover:border-warning/70",
              else: "border-base-300 opacity-90"
            )
          ]}
        >
          <header class="flex flex-wrap items-center gap-2 text-sm">
            <.report_status_badge id={"report-#{report.id}-status"} status={report.status} />
            <span class="badge badge-sm badge-outline">{Reports.target_type_label(report.target_type)}</span>
            <span class="badge badge-sm badge-soft badge-secondary">
              {Reports.category_label(report.category)}
            </span>
            <span class="text-base-content/70">{report.target_label}</span>
            <time
              class="ml-auto text-xs text-base-content/50"
              datetime={DateTime.to_iso8601(report.inserted_at)}
            >
              {Calendar.strftime(report.inserted_at, "%d %b %Y, %H:%M")}
            </time>
          </header>

          <p class="mt-2 text-xs text-base-content/60">
            Reported by <strong>{TannhauserGate.Accounts.User.handle(report.reporter)}</strong>
            <span :if={report.target_user}>
              · author
              <.link
                navigate={
                  ~p"/g/#{@current_story}/master/sanctions?#{[user_id: report.target_user_id]}"
                }
                class="font-semibold hover:underline"
              >
                {TannhauserGate.Accounts.User.handle(report.target_user)}
              </.link>
            </span>
          </p>

          <blockquote class="mt-3 max-h-48 overflow-y-auto whitespace-pre-line border-l-2 border-warning/40 pl-3 text-sm text-base-content/80">
            {report.content_snapshot}
          </blockquote>

          <p :if={report.reason not in [nil, ""]} class="mt-3 text-sm italic text-base-content/70">
            “{report.reason}”
          </p>

          <div :if={report.status != "open"} class="mt-3 text-xs text-base-content/60">
            {Reports.status_label(report.status)} by {TannhauserGate.Accounts.User.handle(
              report.handled_by
            )}
            <span :if={report.handled_at}>on {Calendar.strftime(report.handled_at, "%d %b %Y")}</span>
            <span :if={report.content_deleted} class="text-error">· content deleted</span>
            <p :if={report.resolution_notes} class="mt-1 whitespace-pre-line">
              {report.resolution_notes}
            </p>
          </div>

          <div class="mt-4 flex flex-wrap items-end gap-3">
            <.form
              :if={report.status == "open"}
              for={@resolution_form}
              id={"resolve-form-#{report.id}"}
              phx-submit="resolve"
              class="flex-1"
            >
              <input type="hidden" name="resolution[report_id]" value={report.id} />
              <.input
                id={"resolution-notes-#{report.id}"}
                field={@resolution_form[:resolution_notes]}
                type="textarea"
                rows="2"
                label="Resolution notes"
              />
              <.input
                :if={Reports.deletable?(report)}
                id={"resolution-delete-#{report.id}"}
                field={@resolution_form[:delete_content]}
                type="checkbox"
                label="Delete the reported content"
              />
              <div class="flex gap-2">
                <.button
                  id={"resolve-report-#{report.id}"}
                  name="resolution[status]"
                  value="resolved"
                  class="btn btn-success btn-sm console-action"
                >
                  <.icon name="hero-check" class="size-4" /> Resolve
                </.button>
                <.button
                  id={"dismiss-report-#{report.id}"}
                  name="resolution[status]"
                  value="dismissed"
                  class="btn btn-ghost btn-sm console-action"
                >
                  Dismiss
                </.button>
              </div>
            </.form>

            <.link
              :if={report.target_user_id}
              id={"sanction-author-#{report.id}"}
              navigate={
                ~p"/g/#{@current_story}/master/sanctions?#{[user_id: report.target_user_id, report_id: report.id]}"
              }
              class="btn btn-error btn-outline btn-sm console-action"
            >
              <.icon name="hero-no-symbol" class="size-4" /> Sanction author
            </.link>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
