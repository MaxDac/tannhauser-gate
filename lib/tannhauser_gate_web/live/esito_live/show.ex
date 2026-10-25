defmodule TannhauserGateWeb.EsitoLive.Show do
  @moduledoc """
  An esito (esiti module): the request, its thread between the requester's
  player and the masters, and the outcome once resolved. Only the requester's
  owner and the masters can open it. Masters claim, release, dismiss and
  resolve it here: the outcome with an optional dice roll and its effects
  (XP, money, item, tracker) applied in one transaction.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.EsitiComponents
  import TannhauserGateWeb.ChatComponents, only: [dice_result: 1]

  alias TannhauserGate.{Dice, Esiti, Items, Sheet, Trackers}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :esiti}}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: user, current_story: story} = socket.assigns
    esito = Esiti.get_esito(story, id)

    if esito && Esiti.can_view?(user, story, esito) do
      if connected?(socket), do: Esiti.subscribe(story.id)

      {:ok,
       socket
       |> assign(:page_title, "#{esito.title} · Esiti")
       |> assign(:owner?, Esiti.owner?(user, esito))
       |> assign(:manager?, MapSet.member?(socket.assigns.permissions, :can_manage_esiti_quests))
       |> assign_master_options()
       |> assign_esito(esito)
       |> assign(:message_form, to_form(%{"as" => "masters"}, as: :message))
       |> assign(:resolve_form, to_form(%{"item_quantity" => "1"}, as: :resolution))}
    else
      {:ok,
       socket
       |> put_flash(:error, Esiti.error_message(:esito_not_found))
       |> push_navigate(to: ~p"/g/#{story}/esiti")}
    end
  end

  defp assign_master_options(%{assigns: %{manager?: true, current_story: story}} = socket) do
    socket
    |> assign(:dice_config, Dice.config(story))
    |> assign(:sheet_items, Sheet.list_items(story))
    |> assign(:trackers, Trackers.list_trackers(story))
    |> assign(:items, if(Items.enabled?(story), do: Items.list_items(story), else: []))
  end

  defp assign_master_options(socket), do: socket

  defp assign_esito(socket, esito) do
    socket
    |> assign(:esito, esito)
    |> assign(
      :can_post?,
      Esiti.can_post?(socket.assigns.current_user, socket.assigns.current_story, esito)
    )
    |> stream(:messages, Esiti.list_messages(esito), reset: true)
  end

  defp reload(socket) do
    case Esiti.get_esito(socket.assigns.current_story, socket.assigns.esito.id) do
      nil -> push_navigate(socket, to: ~p"/g/#{socket.assigns.current_story}/esiti")
      esito -> assign_esito(socket, esito)
    end
  end

  @impl true
  def handle_event("post", %{"message" => params}, socket) do
    %{current_user: user, current_story: story, esito: esito} = socket.assigns

    case Esiti.post_message(user, story, esito, params) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> assign(:message_form, to_form(%{"as" => params["as"]}, as: :message))
         |> reload()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :message_form, to_form(changeset, as: :message))}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Esiti.error_message(reason)) |> reload()}
    end
  end

  def handle_event("withdraw", _, socket) do
    run(socket, &Esiti.withdraw/3, "Request withdrawn.")
  end

  def handle_event("claim", _, socket), do: run(socket, &Esiti.claim/3, "You took this request.")

  def handle_event("release", _, socket),
    do: run(socket, &Esiti.release/3, "Request back in the queue.")

  def handle_event("dismiss", _, socket), do: run(socket, &Esiti.dismiss/3, "Request dismissed.")

  def handle_event("validate_resolution", %{"resolution" => params}, socket) do
    {:noreply, assign(socket, :resolve_form, to_form(params, as: :resolution))}
  end

  def handle_event("resolve", %{"resolution" => params}, socket) do
    %{current_user: user, current_story: story, esito: esito} = socket.assigns

    case Esiti.resolve(user, story, esito, params) do
      {:ok, esito} ->
        {:noreply,
         socket
         |> put_flash(:info, "Esito resolved: the outcome was sent to the player.")
         |> assign_esito(esito)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Esiti.error_message(reason))
         |> assign(:resolve_form, to_form(params, as: :resolution))}
    end
  end

  defp run(socket, fun, message) do
    %{current_user: user, current_story: story, esito: esito} = socket.assigns

    case fun.(user, story, esito) do
      {:ok, esito} ->
        {:noreply, socket |> put_flash(:info, message) |> assign_esito(esito)}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Esiti.error_message(reason)) |> reload()}
    end
  end

  @impl true
  def handle_info({:esiti, _event, %{id: id}}, %{assigns: %{esito: %{id: id}}} = socket),
    do: {:noreply, reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp selected_tracker(trackers, slug), do: Enum.find(trackers, &(&1.slug == slug))

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :tracker,
        assigns[:trackers] &&
          selected_tracker(assigns.trackers, assigns.resolve_form[:tracker].value)
      )

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
      <div class="mb-4 flex flex-wrap gap-4">
        <.link
          :if={@owner?}
          navigate={~p"/g/#{@current_story}/esiti"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Your esiti
        </.link>
        <.link
          :if={@manager?}
          navigate={~p"/g/#{@current_story}/master/esiti"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Master queue
        </.link>
      </div>

      <.header>
        <span id="esito-title">{@esito.title}</span>
        <:subtitle>
          <span class="inline-flex flex-wrap items-center gap-2">
            <.status_badge id="esito-status" status={@esito.status} />
            <.link
              navigate={~p"/g/#{@current_story}/characters/#{@esito.character}"}
              class="font-semibold hover:text-primary"
            >
              {@esito.character.name}
            </.link>
            <span :if={place(@esito)}>
              <.icon name="hero-map-pin-micro" class="size-3" /> {place(@esito)}
            </span>
            <span>· filed {when_label(@esito.inserted_at)}</span>
            <span :if={@esito.game_date_label} id="esito-game-date">
              · <.icon name="hero-calendar-days-micro" class="size-3" /> {@esito.game_date_label}
            </span>
            <span :if={@esito.claimed_by}>· handled by {@esito.claimed_by.username}</span>
          </span>
        </:subtitle>
        <:actions>
          <div class="flex flex-wrap gap-2">
            <button
              :if={@owner? && TannhauserGate.Esiti.Esito.active?(@esito)}
              id="withdraw-esito"
              phx-click="withdraw"
              data-confirm="Withdraw this request?"
              class="btn btn-sm btn-ghost text-error"
            >
              <.icon name="hero-x-circle" class="size-4" /> Withdraw
            </button>
            <button
              :if={@manager? && @esito.status == "open"}
              id="claim-esito"
              phx-click="claim"
              class="btn btn-sm btn-secondary"
            >
              <.icon name="hero-hand-raised" class="size-4" /> Claim
            </button>
            <button
              :if={@manager? && @esito.status == "claimed"}
              id="release-esito"
              phx-click="release"
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Release
            </button>
            <button
              :if={@manager? && TannhauserGate.Esiti.Esito.active?(@esito)}
              id="dismiss-esito"
              phx-click="dismiss"
              data-confirm="Dismiss this request without an outcome?"
              class="btn btn-sm btn-ghost text-error"
            >
              <.icon name="hero-no-symbol" class="size-4" /> Dismiss
            </button>
          </div>
        </:actions>
      </.header>

      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_28rem]">
        <div class="space-y-6">
          <section
            id="esito-request"
            class="rounded-xl border border-secondary/20 bg-base-200/60 p-5"
          >
            <.markdown id="esito-body" content={@esito.body} class="prose-sm" />
            <p :if={@esito.related_characters != []} class="mt-3 text-xs text-base-content/60">
              Also involved:
              <span id="esito-related">
                {Enum.map_join(@esito.related_characters, ", ", & &1.name)}
              </span>
            </p>
          </section>

          <section
            :if={@esito.status == "resolved"}
            id="esito-outcome"
            class="rounded-xl border border-success/40 bg-success/5 p-5"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-success">
              <.icon name="hero-check-badge" class="size-4" /> Outcome
            </h2>
            <p class="mt-1 text-xs text-base-content/60">
              By {(@esito.resolved_by && @esito.resolved_by.username) || "the masters"} · {when_label(
                @esito.resolved_at
              )}
            </p>
            <.markdown id="esito-outcome-body" content={@esito.outcome} class="prose-sm mt-3" />
            <div :if={@esito.dice_result} class="mt-3">
              <.dice_result id="esito-dice" result={@esito.dice_result} />
            </div>
            <ul
              :if={Esiti.effect_lines(@esito.effects) != []}
              id="esito-effects"
              class="mt-3 space-y-0.5 text-sm"
            >
              <li :for={line <- Esiti.effect_lines(@esito.effects)}>
                <.icon name="hero-sparkles-micro" class="size-3 text-success" /> {line}
              </li>
            </ul>
          </section>

          <p
            :if={@esito.status == "closed"}
            id="esito-closed"
            class="rounded-xl border border-base-content/10 p-4 text-sm text-base-content/60"
          >
            This request was closed on {when_label(@esito.closed_at)}.
          </p>

          <section id="esito-thread">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Thread</h2>
            <ol id="esito-messages" phx-update="stream" class="mt-3 space-y-3">
              <li id="esito-messages-empty" class="hidden text-sm text-base-content/60 only:block">
                No messages yet.
              </li>
              <li
                :for={{dom_id, message} <- @streams.messages}
                id={dom_id}
                class={[
                  "rounded-xl border p-3",
                  if(message.from_masters,
                    do: "border-primary/30 bg-primary/5",
                    else: "border-secondary/20 bg-base-200/60"
                  )
                ]}
              >
                <p class="flex items-center justify-between text-xs">
                  <span class={[
                    "font-semibold",
                    if(message.from_masters, do: "text-primary", else: "text-secondary")
                  ]}>
                    {message.author_name}
                  </span>
                  <span class="text-base-content/50">{when_label(message.inserted_at)}</span>
                </p>
                <.markdown
                  id={"#{dom_id}-body"}
                  content={message.body}
                  class="prose-sm mt-1"
                />
              </li>
            </ol>

            <.form
              :if={@can_post?}
              for={@message_form}
              id="esito-message-form"
              phx-submit="post"
              class="mt-4"
            >
              <.input
                field={@message_form[:body]}
                type="textarea"
                label="Reply (Markdown)"
                rows="3"
                required
              />
              <div class="flex flex-wrap items-end gap-3">
                <div :if={@master?} class="w-56">
                  <.input
                    field={@message_form[:as]}
                    type="select"
                    label="Sign as"
                    options={[
                      {"The masters", "masters"},
                      {"#{@current_user.username} (master)", "self"}
                    ]}
                  />
                </div>
                <.button
                  id="post-esito-message"
                  phx-disable-with="Sending..."
                  class="btn btn-primary mb-2"
                >
                  <.icon name="hero-chat-bubble-left-right" class="size-4" /> Send
                </.button>
              </div>
            </.form>
          </section>
        </div>

        <section
          :if={@manager? && TannhauserGate.Esiti.Esito.active?(@esito)}
          id="esito-resolve"
          class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5"
        >
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Resolve</h2>
          <p class="mt-1 text-xs text-base-content/60">
            Everything below is applied at once: if an effect fails (e.g. not enough money to
            take) nothing changes.
          </p>
          <.form
            for={@resolve_form}
            id="esito-resolve-form"
            phx-change="validate_resolution"
            phx-submit="resolve"
            class="mt-4"
          >
            <.input
              field={@resolve_form[:outcome]}
              type="textarea"
              label="Outcome (Markdown)"
              rows="6"
              required
            />

            <fieldset class="mt-2 rounded-lg border border-secondary/20 p-3">
              <legend class="px-1 text-xs font-semibold uppercase tracking-wider text-secondary">
                Dice
              </legend>
              <.input field={@resolve_form[:roll]} type="checkbox" label="Roll for the requester" />
              <div
                :if={@resolve_form[:roll].value in ["true", true]}
                class="grid gap-2 sm:grid-cols-2"
              >
                <.input
                  :if={@sheet_items != []}
                  field={@resolve_form[:dice_items]}
                  name="resolution[dice][items][]"
                  value={get_in(@resolve_form.params, ["dice", "items"])}
                  type="select"
                  multiple
                  label={
                    if @dice_config.system == "pool", do: "Pool (sheet items)", else: "Sheet items"
                  }
                  options={Enum.map(@sheet_items, &{&1.name, &1.slug})}
                />
                <.input
                  :if={@dice_config.system == "expression"}
                  field={@resolve_form[:dice_expression]}
                  name="resolution[dice][expression]"
                  value={get_in(@resolve_form.params, ["dice", "expression"])}
                  type="text"
                  label="Expression"
                  placeholder={@dice_config.default_expression}
                />
                <.input
                  field={@resolve_form[:dice_modifier]}
                  name="resolution[dice][modifier]"
                  value={get_in(@resolve_form.params, ["dice", "modifier"])}
                  type="number"
                  label={if @dice_config.system == "pool", do: "Extra dice", else: "Modifier"}
                />
                <.input
                  field={@resolve_form[:dice_difficulty]}
                  name="resolution[dice][difficulty]"
                  value={get_in(@resolve_form.params, ["dice", "difficulty"])}
                  type="number"
                  label="Difficulty"
                />
                <.input
                  field={@resolve_form[:dice_label]}
                  name="resolution[dice][label]"
                  value={get_in(@resolve_form.params, ["dice", "label"])}
                  type="text"
                  label="Label"
                  placeholder="Optional"
                />
              </div>
            </fieldset>

            <fieldset class="mt-3 rounded-lg border border-secondary/20 p-3">
              <legend class="px-1 text-xs font-semibold uppercase tracking-wider text-secondary">
                Rewards &amp; effects
              </legend>
              <div class="grid gap-2 sm:grid-cols-2">
                <.input field={@resolve_form[:xp]} type="number" label="XP" min="-1000" max="1000" />
                <.input
                  field={@resolve_form[:money]}
                  type="number"
                  label={"Money (#{@current_story.currency_name})"}
                />
              </div>
              <div :if={@items != []} class="grid grid-cols-[1fr_6rem] gap-2">
                <.input
                  field={@resolve_form[:item_id]}
                  type="select"
                  label="Item"
                  prompt="—"
                  options={Enum.map(@items, &{&1.name, &1.id})}
                />
                <.input
                  field={@resolve_form[:item_quantity]}
                  type="number"
                  label="Qty"
                  min="1"
                />
              </div>
              <div :if={@trackers != []} class="grid grid-cols-[1fr_6rem] gap-2">
                <.input
                  field={@resolve_form[:tracker]}
                  type="select"
                  label="Tracker"
                  prompt="—"
                  options={Enum.map(@trackers, &{&1.name, &1.slug})}
                />
                <.input field={@resolve_form[:tracker_delta]} type="number" label="Change" />
              </div>
              <.input
                :if={@tracker && @tracker.damage_types != []}
                field={@resolve_form[:tracker_damage_type]}
                type="select"
                label="Damage type"
                prompt="—"
                options={@tracker.damage_types}
              />
              <.input
                :if={@esito.related_characters != []}
                field={@resolve_form[:also_related]}
                type="checkbox"
                label="Also apply to the related characters"
              />
            </fieldset>

            <.button
              id="resolve-esito"
              phx-disable-with="Resolving..."
              data-confirm="Resolve this esito and apply its effects?"
              class="btn btn-primary mt-4 w-full"
            >
              <.icon name="hero-check-badge" class="size-4" /> Resolve
            </.button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
