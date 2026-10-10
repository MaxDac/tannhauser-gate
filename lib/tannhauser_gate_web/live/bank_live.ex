defmodule TannhauserGateWeb.BankLive do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Bank, Characters}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    case Characters.get_user_story_character(socket.assigns.current_user, story.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:info, "Create a character to open a bank account.")
         |> push_navigate(to: ~p"/g/#{story}/characters/new")}

      character ->
        {:ok,
         socket
         |> assign(:page_title, "Bank · #{story.name}")
         |> assign(:form, to_form(%{"to" => "", "amount" => "", "note" => ""}, as: :transfer))
         |> load(character)}
    end
  end

  defp load(socket, character) do
    character = Characters.get_character!(character.id)

    socket
    |> assign(:character, character)
    |> assign(:recipients, Bank.list_recipients(character))
    |> stream(:transactions, Bank.list_transactions(character), reset: true)
  end

  @impl true
  def handle_event("transfer", %{"transfer" => params}, socket) do
    case Bank.transfer(socket.assigns.character, params["to"], params["amount"], params["note"]) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transfer sent.")
         |> assign(:form, to_form(%{"to" => "", "amount" => "", "note" => ""}, as: :transfer))
         |> load(socket.assigns.character)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Bank.error_message(reason))
         |> assign(:form, to_form(params, as: :transfer))}
    end
  end

  defp describe(t, character) do
    cond do
      t.kind == "pay" -> "Pay"
      t.kind == "adjustment" -> "GM adjustment"
      t.from_character_id == character.id -> "To #{t.to_character && t.to_character.name}"
      true -> "From #{t.from_character && t.from_character.name}"
    end
  end

  defp signed(t, character) do
    if t.from_character_id == character.id, do: -t.amount, else: t.amount
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      current_story={@current_story}
    >
      <.header>
        Bank
        <:subtitle>{@character.name}'s account</:subtitle>
      </.header>

      <div class="mt-6 grid gap-6 lg:grid-cols-2">
        <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-6">
          <p class="text-xs uppercase tracking-[0.2em] text-secondary">Balance</p>

          <p id="balance" class="mt-1 text-4xl font-bold text-primary">
            {@character.balance} <span class="text-lg">{@current_story.currency_name}</span>
          </p>

          <p id="bank-job" class="mt-2 text-sm text-base-content/70">
            <%= if @character.job do %>
              {@character.job.name}: {@character.job.pay} {@current_story.currency_name} every {@current_story.pay_interval_hours}h
            <% else %>
              No job.
              <.link navigate={~p"/g/#{@current_story}/jobs"} class="underline">Pick one</.link>
            <% end %>
          </p>

          <.form for={@form} id="transfer-form" phx-submit="transfer" class="mt-6">
            <.input
              field={@form[:to]}
              type="select"
              label="Send to"
              prompt="Choose a character"
              options={Enum.map(@recipients, &{&1.name, &1.id})}
            /> <.input field={@form[:amount]} type="number" label="Amount" min="1" />
            <.input field={@form[:note]} type="text" label="Note" />
            <.button phx-disable-with="Sending...">Send money</.button>
          </.form>
        </section>

        <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-6">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">History</h2>

          <ul id="transactions" phx-update="stream" class="mt-3 divide-y divide-secondary/10">
            <li id="no-transactions" class="hidden only:block text-sm text-base-content/60">
              No transactions yet.
            </li>

            <li
              :for={{dom_id, t} <- @streams.transactions}
              id={dom_id}
              class="flex items-center justify-between gap-3 py-2 text-sm"
            >
              <span class="min-w-0 truncate">
                {describe(t, @character)}
                <span :if={t.note} class="text-base-content/50">· {t.note}</span>
              </span>

              <span class={[
                "font-bold",
                if(signed(t, @character) < 0, do: "text-error", else: "text-success")
              ]}>
                {signed(t, @character)}
              </span>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
