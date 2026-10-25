defmodule TannhauserGateWeb.MasterLive.Sanctions do
  @moduledoc """
  The sanctions of the `:reports` module (moderators only): the issue form
  (warning, mute or ban, with a duration and a reason) and the audit log of
  every sanction of the GDR, filterable by user (a user's history), kind and
  status, with the revoke action. `?user_id=` (and `?report_id=` from the
  reports queue) prefill the form.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Accounts
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Sanctions
  alias TannhauserGate.Sanctions.Sanction

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :reports}}
  on_mount {TannhauserGateWeb.UserAuth, {:require_permission, :can_moderate}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, dgettext("management", "Sanctions"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = history_user(params["user_id"])

    filters = %{
      "user_id" => if(user, do: to_string(user.id), else: ""),
      "kind" => if(params["kind"] in Sanction.kinds(), do: params["kind"], else: ""),
      "status" => if(params["status"] == "active", do: "active", else: "")
    }

    form =
      to_form(
        %{
          "username" => if(user, do: user.username, else: ""),
          "kind" => "warning",
          "duration" => "24",
          "reason" => "",
          "report_id" => to_string(params["report_id"] || "")
        },
        as: :sanction
      )

    {:noreply,
     socket
     |> assign(:history_user, user)
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:form, form)
     |> load_sanctions()}
  end

  defp history_user(id) when is_binary(id) and id != "" do
    case Integer.parse(id) do
      {id, ""} -> Accounts.get_user(id)
      _ -> nil
    end
  end

  defp history_user(_), do: nil

  defp load_sanctions(socket) do
    sanctions = Sanctions.list_sanctions(socket.assigns.current_story, socket.assigns.filters)

    socket
    |> assign(:sanctions_count, length(sanctions))
    |> stream(:sanctions, sanctions, reset: true)
  end

  defp self_path(socket, query) do
    query = Enum.reject(query, fn {_k, v} -> v in [nil, ""] end)
    ~p"/g/#{socket.assigns.current_story}/master/sanctions?#{query}"
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    query =
      Map.take(params, ["kind", "status"])
      |> Map.put("user_id", socket.assigns.filters["user_id"])

    {:noreply, push_patch(socket, to: self_path(socket, query))}
  end

  def handle_event("validate", %{"sanction" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :sanction))}
  end

  def handle_event("issue", %{"sanction" => params}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    case Sanctions.issue(user, story, params) do
      {:ok, sanction} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext(
             "management",
             "%{string_capitalize_sanction_kind} issued to %{user_handle_sanction_user}.",
             string_capitalize_sanction_kind: sanction_kind_label(sanction.kind),
             user_handle_sanction_user: User.handle(sanction.user)
           )
         )
         |> push_patch(to: self_path(socket, [{"user_id", sanction.user_id}]))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(params, as: :sanction, errors: changeset.errors, action: :insert)
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Sanctions.error_message(reason))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    with %Sanction{} = sanction <- Sanctions.get_sanction(story, id) || {:error, :not_found},
         {:ok, sanction} <- Sanctions.revoke(user, story, sanction) do
      {:noreply,
       socket
       |> put_flash(:info, dgettext("management", "Sanction revoked."))
       |> stream_insert(:sanctions, sanction)}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, Sanctions.error_message(reason))}
    end
  end

  defp revocable?(%Sanction{kind: "warning"}), do: false
  defp revocable?(%Sanction{} = s), do: Sanction.active?(s, DateTime.utc_now())

  defp sanction_kind_label("warning"), do: dgettext("management", "Warning")
  defp sanction_kind_label("mute"), do: dgettext("management", "Mute")
  defp sanction_kind_label("ban"), do: dgettext("management", "Ban")

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
      my_characters={@my_characters}
      active_character={@active_character}
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <.header>
        {dgettext("management", "Sanctions")}
        <:subtitle>
          {dgettext(
            "management",
            "Warnings, mutes and bans of %{current_story_name}. Muted members cannot write; banned members cannot enter. Sanctions are never deleted: revoke them instead.",
            current_story_name: @current_story.name
          )}
        </:subtitle>

        <:actions>
          <.link
            navigate={~p"/g/#{@current_story}/master/reports"}
            class="btn btn-ghost btn-sm console-action"
          >
            <.icon name="hero-flag" class="size-4" /> {dgettext("management", "Reports")}
          </.link>

          <.link
            navigate={~p"/g/#{@current_story}/master"}
            class="btn btn-ghost btn-sm console-action"
          >
            <.icon name="hero-arrow-left" class="size-4" /> {dgettext("management", "Master tools")}
          </.link>
        </:actions>
      </.header>

      <div class="mt-8 grid gap-8 lg:grid-cols-[22rem_1fr]">
        <section>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {dgettext("management", "Issue a sanction")}
          </h2>

          <.form
            for={@form}
            id="sanction-form"
            phx-change="validate"
            phx-submit="issue"
            class="mt-3 rounded-xl border border-error/30 bg-base-200/70 p-5"
          >
            <input type="hidden" name={@form[:report_id].name} value={@form[:report_id].value} />
            <p
              :if={@form[:report_id].value not in [nil, ""]}
              class="mb-2 text-xs text-base-content/60"
            >
              <.icon name="hero-flag" class="size-3" /> {dgettext(
                "management",
                "Linked to report #%{form__report_id__value}",
                form__report_id__value: @form[:report_id].value
              )}
            </p>

            <.input
              field={@form[:username]}
              type="text"
              label={dgettext("management", "Username")}
              required
            />
            <.input
              field={@form[:kind]}
              type="select"
              label={dgettext("management", "Kind")}
              options={[
                {dgettext("management", "Warning"), "warning"},
                {dgettext("management", "Mute"), "mute"},
                {dgettext("management", "Ban"), "ban"}
              ]}
            />
            <.input
              :if={@form[:kind].value != "warning"}
              field={@form[:duration]}
              type="select"
              label={dgettext("management", "Duration")}
              options={Sanctions.duration_options()}
            />
            <.input
              field={@form[:reason]}
              type="textarea"
              rows="3"
              label={dgettext("management", "Reason")}
              required
            />
            <div class="flex justify-end">
              <.button
                id="issue-sanction"
                class="btn btn-error btn-sm console-action"
                phx-disable-with={dgettext("management", "Issuing...")}
                data-confirm={
                  dgettext("management", "Issue this sanction? The member will be notified.")
                }
              >
                <.icon name="hero-no-symbol" class="size-4" /> {dgettext("management", "Issue")}
              </.button>
            </div>
          </.form>
        </section>

        <section>
          <div class="flex flex-wrap items-end justify-between gap-3">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              <%= if @history_user do %>
                {dgettext("management", "History of %{user_handle__history_user}",
                  user_handle__history_user: User.handle(@history_user)
                )}
                <.link
                  id="clear-user-filter"
                  patch={~p"/g/#{@current_story}/master/sanctions"}
                  class="ml-2 normal-case tracking-normal text-xs font-normal text-base-content/60 hover:underline"
                >
                  {dgettext("management", "(everyone)")}
                </.link>
              <% else %>
                {dgettext("management", "Audit log")}
              <% end %>
            </h2>

            <.form for={@filter_form} id="sanctions-filters" phx-change="filter" class="flex gap-2">
              <.input
                field={@filter_form[:kind]}
                type="select"
                prompt={dgettext("management", "Any kind")}
                options={[
                  {dgettext("management", "Warning"), "warning"},
                  {dgettext("management", "Mute"), "mute"},
                  {dgettext("management", "Ban"), "ban"}
                ]}
              />
              <.input
                field={@filter_form[:status]}
                type="select"
                prompt={dgettext("management", "Any status")}
                options={[{dgettext("management", "Active"), "active"}]}
              />
            </.form>
          </div>

          <p
            :if={@sanctions_count == 0}
            id="sanctions-empty"
            class="mt-6 text-center text-base-content/60"
          >
            {dgettext("management", "No sanctions.")}
          </p>

          <ul id="sanctions" phx-update="stream" class="mt-3 space-y-3">
            <li
              :for={{dom_id, sanction} <- @streams.sanctions}
              id={dom_id}
              class={[
                "rounded-xl border bg-base-200/70 p-4 transition-colors",
                if(sanction.revoked_at, do: "border-base-300 opacity-70", else: "border-error/30")
              ]}
            >
              <div class="flex flex-wrap items-center gap-2 text-sm">
                <.sanction_kind_badge id={"sanction-#{sanction.id}-kind"} kind={sanction.kind} />
                <.link
                  patch={~p"/g/#{@current_story}/master/sanctions?#{[user_id: sanction.user_id]}"}
                  class="font-semibold hover:underline"
                >
                  {User.handle(sanction.user)}
                </.link>

                <span id={"sanction-#{sanction.id}-status"} class="text-xs text-base-content/60">
                  {Sanctions.status_label(sanction)}
                </span>

                <button
                  :if={revocable?(sanction)}
                  type="button"
                  id={"revoke-sanction-#{sanction.id}"}
                  phx-click="revoke"
                  phx-value-id={sanction.id}
                  data-confirm={dgettext("management", "Revoke this sanction?")}
                  class="btn btn-ghost btn-xs console-action ml-auto"
                >
                  <.icon name="hero-arrow-uturn-left" class="size-3" /> {dgettext(
                    "management",
                    "Revoke"
                  )}
                </button>
              </div>

              <p class="mt-2 whitespace-pre-line text-sm text-base-content/80">{sanction.reason}</p>

              <p class="mt-2 text-xs text-base-content/50">
                {dgettext(
                  "management",
                  "Issued by %{user_handle_sanction_issued_by} on %{sanctions_format_sanction_starts_at}",
                  user_handle_sanction_issued_by: User.handle(sanction.issued_by),
                  sanctions_format_sanction_starts_at: Sanctions.format(sanction.starts_at)
                )}
                <span :if={sanction.kind != "warning"}>
                  · {if(sanction.ends_at,
                    do:
                      dgettext("management", "ends %{sanctions_format_sanction_ends_at}",
                        sanctions_format_sanction_ends_at: Sanctions.format(sanction.ends_at)
                      ),
                    else: dgettext("management", "permanent")
                  )}
                </span>

                <span :if={sanction.revoked_at}>
                  {dgettext(
                    "management",
                    "· revoked by %{user_handle_sanction_revoked_by} on %{value}",
                    user_handle_sanction_revoked_by: User.handle(sanction.revoked_by),
                    value: Sanctions.format(sanction.revoked_at)
                  )}
                </span>
              </p>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
