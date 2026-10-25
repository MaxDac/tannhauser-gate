defmodule TannhauserGateWeb.Admin.ReviewsLive do
  @moduledoc "Platform moderation of the GDR reviews of the portal directory."
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.Admin.Components

  alias TannhauserGate.Directory
  alias TannhauserGate.Directory.Review

  @impl true
  def mount(_params, _session, socket) do
    reviews = Directory.list_all_reviews()

    {:ok,
     socket
     |> assign(:page_title, dgettext("management", "Reviews"))
     |> assign(:empty?, reviews == [])
     |> stream(:reviews, reviews)}
  end

  @impl true
  def handle_event("set_hidden", %{"id" => id, "hidden" => hidden}, socket) do
    case Directory.set_review_hidden(socket.assigns.current_user, id, hidden == "true") do
      {:ok, review} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           if(review.hidden_at,
             do: dgettext("management", "Review hidden"),
             else: dgettext("management", "Review restored")
           )
         )
         |> stream_insert(:reviews, review)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("management", "Review not found."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>
        {dgettext("management", "Reviews")}
        <:subtitle>
          {dgettext(
            "management",
            "Hide abusive or off-topic reviews: hidden reviews leave the scores and the public pages."
          )}
        </:subtitle>
      </.header>

      <p
        :if={@empty?}
        id="no-reviews"
        class="mt-8 rounded-lg border border-dashed border-mint/30 p-8 text-center text-fog-400"
      >
        {dgettext("management", "No reviews yet.")}
      </p>

      <ul id="admin-reviews" phx-update="stream" class="mt-6 space-y-3">
        <li
          :for={{dom_id, review} <- @streams.reviews}
          id={dom_id}
          class={[
            "rounded-xl border bg-ink/80 p-4 transition",
            if(review.hidden_at, do: "border-error/40 opacity-70", else: "border-mint/20")
          ]}
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <p class="text-sm">
              <.link navigate={~p"/gdrs/#{review.story_id}"} class="font-bold text-phosphor">
                {review.story.name}
              </.link>

              <span class="text-fog-400">
                · {review.user.username} · {Calendar.strftime(review.inserted_at, "%Y-%m-%d")}
              </span>

              <span class="ml-2 font-mono text-mint">
                {TannhauserGateWeb.DirectoryComponents.format_score(Review.overall(review))}/5
              </span>

              <span :if={review.hidden_at} class="badge badge-error badge-sm ml-2">{dgettext(
                "management",
                "Hidden"
              )}</span>
            </p>

            <button
              id={"admin-review-toggle-#{review.id}"}
              type="button"
              phx-click="set_hidden"
              phx-value-id={review.id}
              phx-value-hidden={to_string(is_nil(review.hidden_at))}
              class="btn btn-xs btn-outline"
            >
              {if review.hidden_at,
                do: dgettext("management", "Unhide"),
                else: dgettext("management", "Hide")}
            </button>
          </div>

          <p class="mt-2 line-clamp-3 whitespace-pre-line text-sm text-fog-300">
            {review.conclusion}
          </p>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
