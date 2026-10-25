defmodule TannhauserGateWeb.GmLive.Weather do
  @moduledoc """
  GM config for the weather module: the weather table (conditions with an
  icon, a weight and an optional temperature range per season) and how often
  the weather of the zones is rolled.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.GmNav

  alias TannhauserGate.{Stories, Weather}
  alias TannhauserGate.Weather.Condition

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :weather}}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, "GM dashboard")
     |> assign(:seasons, Weather.seasons(story))
     |> assign(:interval_form, interval_form(story))
     |> reload()
     |> edit_condition(%Condition{})}
  end

  defp story(socket), do: socket.assigns.current_story

  defp interval_form(story), do: to_form(Stories.change_story_as_gm(story), as: :settings)

  defp reload(socket), do: assign(socket, :conditions, Weather.list_conditions(story(socket)))

  defp edit_condition(socket, condition) do
    assign(socket,
      condition: condition,
      form: to_form(Weather.change_condition(condition))
    )
  end

  @impl true
  def handle_event("validate", %{"condition" => params}, socket) do
    changeset =
      socket.assigns.condition
      |> Weather.change_condition(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"condition" => params}, socket) do
    story = story(socket)

    result =
      case socket.assigns.condition do
        %Condition{id: nil} -> Weather.create_condition(story, params)
        condition -> Weather.update_condition(story, condition, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Weather condition saved.")
         |> reload()
         |> edit_condition(%Condition{})}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Weather.get_condition(story(socket), id) do
      nil -> {:noreply, socket}
      condition -> {:noreply, edit_condition(socket, condition)}
    end
  end

  def handle_event("cancel", _, socket), do: {:noreply, edit_condition(socket, %Condition{})}

  def handle_event("delete", %{"id" => id}, socket) do
    case Weather.get_condition(story(socket), id) do
      nil ->
        {:noreply, socket}

      condition ->
        {:ok, _} = Weather.delete_condition(story(socket), condition)

        {:noreply,
         socket
         |> put_flash(:info, "Weather condition deleted.")
         |> reload()
         |> edit_condition(%Condition{})}
    end
  end

  def handle_event("save_interval", %{"settings" => params}, socket) do
    story = story(socket)
    attrs = %{"weather_interval_hours" => params["weather_interval_hours"]}

    case Stories.update_story_as_gm(story, attrs) do
      {:ok, updated} ->
        updated = %{updated | calendar: story.calendar}

        {:noreply,
         socket
         |> put_flash(:info, "Weather interval saved.")
         |> assign(:current_story, updated)
         |> assign(:interval_form, interval_form(updated))}

      {:error, changeset} ->
        {:noreply, assign(socket, :interval_form, to_form(changeset, as: :settings))}
    end
  end

  defp season_value(form, field, season) do
    case form[field].value do
      %{} = map -> Map.get(map, season)
      _ -> nil
    end
  end

  # The chance (in %) of each condition per season.
  defp chance(conditions, condition, season) do
    total = Enum.sum_by(conditions, &Condition.weight(&1, season))

    if total > 0,
      do: "#{round(Condition.weight(condition, season) * 100 / total)}%",
      else: "—"
  end

  defp range_label(condition, season) do
    case Condition.temperature_range(condition, season) do
      {min, max} -> "#{min}…#{max}°C"
      nil -> nil
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
      <.gm_header story={@current_story} />
      <.gm_tabs story={@current_story} tab="weather" />

      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_24rem]">
        <section id="weather-conditions" class="space-y-3">
          <p class="text-sm text-base-content/60">
            Seasons: <strong>{Enum.join(@seasons, ", ")}</strong>
            <span :if={@seasons == ["default"]}>
              (enable the calendar module and give its months a season to weigh conditions by
              season).
            </span>
          </p>
          <p :if={@conditions == []} id="weather-empty" class="text-sm text-base-content/60">
            No conditions yet: without a table the zones keep the weather the masters set.
          </p>

          <article
            :for={condition <- @conditions}
            id={"weather-condition-#{condition.id}"}
            class="rounded-xl border border-secondary/20 bg-base-200/60 p-4 transition hover:border-secondary/40"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="flex min-w-0 items-center gap-2">
                <span class="grid size-8 shrink-0 place-items-center rounded-md bg-info/10 text-info">
                  <.icon name={condition.icon} class="size-5" />
                </span>
                <div class="min-w-0">
                  <h3 class="truncate font-semibold text-primary">{condition.name}</h3>
                  <p :if={condition.description} class="truncate text-xs text-base-content/60">
                    {condition.description}
                  </p>
                </div>
              </div>
              <div class="flex shrink-0 gap-1">
                <button
                  id={"edit-weather-condition-#{condition.id}"}
                  phx-click="edit"
                  phx-value-id={condition.id}
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-secondary"
                  title="Edit"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  id={"delete-weather-condition-#{condition.id}"}
                  phx-click="delete"
                  phx-value-id={condition.id}
                  data-confirm="Delete this condition?"
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-error"
                  title="Delete"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
            <div class="mt-3 flex flex-wrap gap-2 text-xs">
              <span
                :for={season <- @seasons}
                class="rounded border border-secondary/20 bg-base-100/40 px-2 py-0.5"
              >
                <span class="text-base-content/60">{season}:</span>
                <strong class="tabular-nums">{Condition.weight(condition, season)}</strong>
                <span class="text-base-content/50">({chance(@conditions, condition, season)})</span>
                <span :if={range_label(condition, season)} class="text-info">
                  · {range_label(condition, season)}
                </span>
              </span>
            </div>
          </article>
        </section>

        <div class="space-y-6">
          <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {if @condition.id, do: "Edit condition", else: "New condition"}
            </h2>
            <.form
              for={@form}
              id="weather-condition-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-4"
            >
              <.input field={@form[:name]} type="text" label="Name" required />
              <.input
                field={@form[:icon]}
                type="select"
                label="Icon"
                options={Condition.icons()}
              />
              <.input field={@form[:description]} type="text" label="Description (optional)" />

              <div class="mt-2 space-y-2">
                <p class="text-xs font-bold uppercase tracking-wider text-base-content/60">
                  Weight and temperature (°C) per season
                </p>
                <div
                  :for={{season, index} <- Enum.with_index(@seasons)}
                  class="grid grid-cols-3 gap-2"
                >
                  <.input
                    id={"condition-weight-#{index}"}
                    name={"condition[weights][#{season}]"}
                    value={season_value(@form, :weights, season)}
                    type="number"
                    min="0"
                    max="1000"
                    label={"#{season} weight"}
                  />
                  <.input
                    id={"condition-min-#{index}"}
                    name={"condition[temp_min][#{season}]"}
                    value={season_value(@form, :temp_min, season)}
                    type="number"
                    label="Min"
                  />
                  <.input
                    id={"condition-max-#{index}"}
                    name={"condition[temp_max][#{season}]"}
                    value={season_value(@form, :temp_max, season)}
                    type="number"
                    label="Max"
                  />
                </div>
                <.error :for={msg <- Enum.map(@form[:weights].errors, &translate_error/1)}>
                  {msg}
                </.error>
                <.error :for={
                  msg <-
                    Enum.map(@form[:temp_min].errors ++ @form[:temp_max].errors, &translate_error/1)
                }>
                  {msg}
                </.error>
              </div>

              <div class="flex gap-2">
                <.button id="save-weather-condition" phx-disable-with="Saving...">
                  {if @condition.id, do: "Update condition", else: "Add condition"}
                </.button>
                <.button
                  :if={@condition.id}
                  type="button"
                  id="cancel-weather-condition"
                  phx-click="cancel"
                >
                  Cancel
                </.button>
              </div>
            </.form>
          </section>

          <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Schedule</h2>
            <.form
              for={@interval_form}
              id="weather-interval-form"
              phx-submit="save_interval"
              class="mt-4"
            >
              <.input
                field={@interval_form[:weather_interval_hours]}
                type="number"
                min="1"
                max="168"
                label="Roll a new weather every (real hours)"
              />
              <p class="-mt-1 mb-3 text-xs text-base-content/60">
                A weather set by a master is kept for one interval.
              </p>
              <.button id="save-weather-interval" phx-disable-with="Saving...">Save</.button>
            </.form>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
