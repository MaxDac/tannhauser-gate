defmodule TannhauserGateWeb.GdrLive.Profile do
  @moduledoc """
  The public page of a GDR in the portal: its listing, summary, review
  scores per criterion, the reviews (with the GDR admin's replies), the
  monthly vote and the way in. Eligible players write or edit their review
  here, the GDR admin replies and platform admins hide reviews.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.DirectoryComponents

  alias TannhauserGate.{Accounts, Directory}
  alias TannhauserGate.Directory.Review
  alias TannhauserGateWeb.GdrLive.Index

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Directory.get_visible_story(user, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "GDR not found.")
         |> push_navigate(to: ~p"/gdrs")}

      story ->
        {:ok,
         socket
         |> assign(:page_title, story.name)
         |> assign(:story, story)
         |> assign(:admin?, Accounts.admin?(user))
         |> assign(:can_reply?, Directory.can_reply?(user, story))
         |> assign(:show_review_form?, false)
         |> assign(:replying_id, nil)
         |> assign(:reply_form, nil)
         |> load_summary()
         |> load_reviews()
         |> assign_review_form()}
    end
  end

  defp load_summary(socket) do
    %{story: story, current_user: user} = socket.assigns

    socket
    |> assign(:entry, Directory.listing(story, online: &Index.online_count/1))
    |> assign(:aggregate, Directory.review_aggregate(story))
    |> assign(:voted?, Directory.voted?(user, story))
  end

  defp load_reviews(socket) do
    reviews = Directory.list_reviews(socket.assigns.story, include_hidden: socket.assigns.admin?)

    socket
    |> assign(:reviews_empty?, reviews == [])
    |> stream(:reviews, reviews, reset: true)
  end

  defp assign_review_form(socket, changeset \\ nil) do
    %{story: story, current_user: user} = socket.assigns
    my_review = Directory.get_user_review(user, story)
    changeset = changeset || Directory.change_review(my_review || %Review{})

    socket
    |> assign(:my_review, my_review)
    |> assign(:eligibility, Directory.review_eligibility(user, story))
    |> assign(:review_form, to_form(changeset))
  end

  ## Votes

  @impl true
  def handle_event("vote", _params, socket) do
    case Directory.vote(socket.assigns.current_user, socket.assigns.story) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Thanks for your vote!") |> load_summary()}

      {:error, :already_voted} ->
        {:noreply, put_flash(socket, :error, "You already voted for this GDR this month.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Draft GDRs cannot be voted.")}
    end
  end

  ## Reviews

  def handle_event("toggle_review_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_review_form?, !socket.assigns.show_review_form?)
     |> assign_review_form()}
  end

  def handle_event("validate_review", %{"review" => params}, socket) do
    changeset =
      (socket.assigns.my_review || %Review{})
      |> Directory.change_review(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :review_form, to_form(changeset))}
  end

  def handle_event("save_review", %{"review" => params}, socket) do
    %{current_user: user, story: story} = socket.assigns

    case Directory.save_review(user, story, params) do
      {:ok, _review} ->
        {:noreply,
         socket
         |> put_flash(:info, "Review saved.")
         |> assign(:show_review_form?, false)
         |> load_summary()
         |> load_reviews()
         |> assign_review_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_review_form(socket, changeset)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Directory.eligibility_message(reason))}
    end
  end

  ## GM replies

  def handle_event("edit_reply", %{"id" => id}, socket) do
    case socket.assigns.can_reply? && Directory.get_story_review(socket.assigns.story, id) do
      %Review{} = review ->
        {:noreply,
         socket
         |> assign(:replying_id, review.id)
         |> assign(:reply_form, to_form(Ecto.Changeset.change(review), as: :reply))
         |> load_reviews()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_reply", _params, socket) do
    {:noreply, socket |> assign(:replying_id, nil) |> load_reviews()}
  end

  def handle_event("save_reply", %{"review_id" => id, "reply" => params}, socket) do
    %{current_user: user, story: story} = socket.assigns

    case Directory.reply_to_review(user, story, id, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Reply saved.")
         |> assign(:replying_id, nil)
         |> load_reviews()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket |> assign(:reply_form, to_form(changeset, as: :reply)) |> load_reviews()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Only the GDR admin can reply to its reviews.")}
    end
  end

  ## Moderation

  def handle_event("set_hidden", %{"id" => id, "hidden" => hidden}, socket) do
    with %Review{} <- Directory.get_story_review(socket.assigns.story, id),
         {:ok, review} <-
           Directory.set_review_hidden(socket.assigns.current_user, id, hidden == "true") do
      {:noreply,
       socket
       |> put_flash(:info, if(review.hidden_at, do: "Review hidden.", else: "Review restored."))
       |> load_summary()
       |> load_reviews()}
    else
      _ -> {:noreply, put_flash(socket, :error, "You cannot moderate this review.")}
    end
  end

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      current_story={@current_story}
      story_role={@story_role}
    >
      <.link
        navigate={~p"/gdrs"}
        id="back-to-directory"
        class="inline-flex items-center gap-1 text-xs uppercase tracking-wider text-base-content/60 transition hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="size-3.5" /> Directory
      </.link>

      <section
        id="gdr-profile"
        class="group mt-3 overflow-hidden rounded-2xl border border-primary/20 bg-base-200 shadow-sm"
      >
        <.banner story={@story} class="h-48 sm:h-64">
          <div class="absolute inset-x-4 top-4 flex items-start justify-between gap-2">
            <div class="flex flex-wrap gap-1.5">
              <.lifecycle_badge id="profile-lifecycle" lifecycle={@story.lifecycle} />
              <span
                :if={@story.status == "draft"}
                class="rounded-full border border-warning/50 bg-base-100/70 px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-wider text-warning"
              >
                Draft
              </span>
            </div>
            <.rating_badge id="profile-rating" rating={@story.content_rating} />
          </div>
        </.banner>

        <div class="-mt-16 relative flex flex-wrap items-end justify-between gap-6 px-6 pb-6 sm:px-8">
          <div class="max-w-2xl">
            <h1 class="text-3xl font-bold text-primary sm:text-4xl">{@story.name}</h1>
            <p :if={@story.pitch} id="profile-pitch" class="mt-1 text-base text-base-content/80">
              {@story.pitch}
            </p>
            <div class="mt-3"><.genre_chips genres={@story.genres} /></div>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <button
              :if={@story.status == "published"}
              id="vote-button"
              type="button"
              phx-click="vote"
              disabled={@voted?}
              class={[
                "inline-flex items-center gap-2 rounded-lg border px-4 py-2 text-sm font-bold uppercase tracking-wider transition",
                if(@voted?,
                  do: "cursor-default border-success/40 bg-success/10 text-success",
                  else:
                    "border-secondary/50 text-secondary hover:-translate-y-0.5 hover:bg-secondary hover:text-secondary-content"
                )
              ]}
            >
              <.icon
                name={if @voted?, do: "hero-check-circle", else: "hero-hand-thumb-up"}
                class="size-4"
              />
              {if @voted?, do: "Voted this month", else: "Vote"}
            </button>
            <.link
              id="enter-gdr"
              navigate={~p"/g/#{@story}"}
              class="inline-flex items-center gap-2 rounded-lg bg-primary px-5 py-2 text-sm font-bold uppercase tracking-wider text-primary-content shadow-phosphor transition hover:-translate-y-0.5 hover:brightness-110"
            >
              Enter <.icon name="hero-arrow-right" class="size-4" />
            </.link>
          </div>
        </div>

        <dl class="grid grid-cols-2 gap-px border-t border-base-content/10 bg-base-content/10 sm:grid-cols-4">
          <div class="bg-base-200 px-6 py-4">
            <dt class="text-[0.65rem] uppercase tracking-wider text-base-content/50">Score</dt>
            <dd id="profile-score" class="mt-1 text-lg">
              <.score score={@entry.score} count={@entry.review_count} />
            </dd>
          </div>
          <div class="bg-base-200 px-6 py-4">
            <dt class="text-[0.65rem] uppercase tracking-wider text-base-content/50">Members</dt>
            <dd id="profile-members" class="mt-1 font-mono text-lg font-bold">{@entry.members}</dd>
          </div>
          <div class="bg-base-200 px-6 py-4">
            <dt class="text-[0.65rem] uppercase tracking-wider text-base-content/50">Online now</dt>
            <dd id="profile-online" class="mt-1 font-mono text-lg font-bold">{@entry.online}</dd>
          </div>
          <div class="bg-base-200 px-6 py-4">
            <dt class="text-[0.65rem] uppercase tracking-wider text-base-content/50">
              Votes this month
            </dt>
            <dd id="profile-votes" class="mt-1 font-mono text-lg font-bold">{@entry.votes}</dd>
          </div>
        </dl>
      </section>

      <div class="mt-8 grid gap-8 lg:grid-cols-[1fr_22rem]">
        <div class="min-w-0 space-y-8">
          <section :if={@story.summary not in [nil, ""]} id="profile-summary">
            <h2 class="text-xs font-bold uppercase tracking-[0.25em] text-secondary">About</h2>
            <p class="mt-3 whitespace-pre-line text-sm leading-relaxed text-base-content/80">
              {@story.summary}
            </p>
            <p class="mt-3 text-xs text-base-content/50">
              GM {(@story.owner && @story.owner.username) || "Platform"}
              <span :if={@story.masters != []}>
                · Masters: {Enum.map_join(@story.masters, ", ", & &1.username)}
              </span>
            </p>
          </section>

          <section id="profile-reviews">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="text-xs font-bold uppercase tracking-[0.25em] text-secondary">Reviews</h2>
              <button
                :if={@my_review || @eligibility == :ok}
                id="toggle-review-form"
                type="button"
                phx-click="toggle_review_form"
                class="inline-flex items-center gap-1 rounded-lg border border-primary/40 px-3 py-1.5 text-xs font-bold uppercase tracking-wider text-primary transition hover:bg-primary hover:text-primary-content"
              >
                <.icon
                  name={if @show_review_form?, do: "hero-x-mark", else: "hero-pencil-square"}
                  class="size-3.5"
                />
                {cond do
                  @show_review_form? -> "Close"
                  @my_review -> "Edit your review"
                  true -> "Write a review"
                end}
              </button>
            </div>

            <p
              :if={!@my_review && match?({:error, _}, @eligibility)}
              id="review-eligibility"
              class="mt-3 rounded-lg border border-base-content/10 bg-base-200/60 px-4 py-3 text-xs text-base-content/60"
            >
              <.icon name="hero-information-circle" class="mr-1 size-4 align-text-bottom" />
              {Directory.eligibility_message(elem(@eligibility, 1))}
            </p>

            <.review_form :if={@show_review_form?} form={@review_form} />

            <p
              :if={@reviews_empty?}
              id="no-reviews"
              class="mt-4 rounded-xl border border-dashed border-secondary/30 p-8 text-center text-sm text-base-content/60"
            >
              No reviews yet.
            </p>

            <ul id="reviews" phx-update="stream" class="mt-4 space-y-4">
              <li
                :for={{dom_id, review} <- @streams.reviews}
                id={dom_id}
                class={[
                  "rounded-xl border bg-base-200 p-5 transition hover:border-primary/30",
                  if(review.hidden_at,
                    do: "border-error/40 opacity-70",
                    else: "border-base-content/10"
                  )
                ]}
              >
                <.review_card
                  review={review}
                  admin?={@admin?}
                  can_reply?={@can_reply?}
                  replying?={@replying_id == review.id}
                  reply_form={@reply_form}
                />
              </li>
            </ul>
          </section>
        </div>

        <aside
          id="profile-aggregate"
          class="h-fit rounded-2xl border border-base-content/10 bg-base-200 p-5 lg:sticky lg:top-6"
        >
          <div class="flex items-baseline justify-between">
            <h2 class="text-xs font-bold uppercase tracking-[0.25em] text-secondary">Scores</h2>
            <p class="text-xs text-base-content/50">
              {@aggregate.count} {if @aggregate.count == 1, do: "review", else: "reviews"}
            </p>
          </div>
          <p class="mt-3 flex items-baseline gap-2">
            <span id="aggregate-overall" class="font-mono text-4xl font-bold text-primary">
              {format_score(@aggregate.overall)}
            </span>
            <span class="text-sm text-base-content/50">/ 5</span>
          </p>
          <ul class="mt-4 space-y-3">
            <li :for={{field, label, italian, avg} <- @aggregate.criteria} id={"aggregate-#{field}"}>
              <div class="flex items-baseline justify-between text-xs">
                <span class="text-base-content/80">
                  {label} <span class="text-base-content/40">· {italian}</span>
                </span>
                <span class="font-mono font-bold">{format_score(avg)}</span>
              </div>
              <div class="mt-1 h-1.5 overflow-hidden rounded-full bg-base-300">
                <div
                  class="h-full rounded-full bg-gradient-to-r from-secondary to-primary transition-all duration-700"
                  style={"width: #{bar_width(avg)}%"}
                />
              </div>
            </li>
          </ul>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  defp bar_width(nil), do: 0
  defp bar_width(avg), do: round(avg / 5 * 100)

  attr :form, :map, required: true

  defp review_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="review-form"
      phx-change="validate_review"
      phx-submit="save_review"
      class="mt-4 rounded-xl border border-primary/30 bg-base-200 p-5"
    >
      <p class="mb-4 text-xs text-base-content/60">
        Score each aspect from 1 (poor) to 5 (excellent). Be fair and specific: the staff can
        reply and abusive reviews are hidden.
      </p>
      <div class="grid gap-x-6 gap-y-3 sm:grid-cols-2">
        <fieldset :for={{field, label, italian} <- Directory.criteria()} id={"review-#{field}"}>
          <legend class="text-xs text-base-content/80">
            {label} <span class="text-base-content/40">· {italian}</span>
          </legend>
          <div class="mt-1 flex gap-1">
            <label
              :for={n <- 1..5}
              class="flex size-8 cursor-pointer items-center justify-center rounded-md border border-base-content/15 font-mono text-sm text-base-content/60 transition hover:border-primary/60 hover:text-base-content has-checked:border-primary has-checked:bg-primary has-checked:text-primary-content has-focus-visible:ring-2 has-focus-visible:ring-primary/50"
            >
              <input
                type="radio"
                id={"review-#{field}-#{n}"}
                name={@form[field].name}
                value={n}
                checked={to_string(@form[field].value) == to_string(n)}
                class="sr-only"
              />
              {n}
            </label>
          </div>
          <.error :for={msg <- Enum.map(@form[field].errors, &translate_error/1)}>{msg}</.error>
        </fieldset>
      </div>
      <div class="mt-4">
        <.input
          field={@form[:advice]}
          type="textarea"
          label="Advice to the staff (optional)"
          rows="3"
        />
        <.input field={@form[:conclusion]} type="textarea" label="Conclusions" rows="4" required />
      </div>
      <.button phx-disable-with="Saving...">Save review</.button>
    </.form>
    """
  end

  attr :review, :map, required: true
  attr :admin?, :boolean, required: true
  attr :can_reply?, :boolean, required: true
  attr :replying?, :boolean, required: true
  attr :reply_form, :map, default: nil

  defp review_card(assigns) do
    ~H"""
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <p class="text-sm font-bold">{@review.user.username}</p>
        <p class="text-xs text-base-content/50">
          {Calendar.strftime(@review.inserted_at, "%d %b %Y")}
          <span :if={@review.updated_at != @review.inserted_at}>· edited</span>
        </p>
      </div>
      <div class="flex items-center gap-2">
        <span
          :if={@review.hidden_at}
          id={"review-hidden-#{@review.id}"}
          class="rounded-full border border-error/50 px-2 py-0.5 text-[0.65rem] font-bold uppercase text-error"
        >
          Hidden
        </span>
        <span class="rounded-lg bg-primary/15 px-2 py-1 font-mono text-sm font-bold text-primary">
          {format_score(Review.overall(@review))}
        </span>
        <button
          :if={@admin?}
          id={"review-toggle-hidden-#{@review.id}"}
          type="button"
          phx-click="set_hidden"
          phx-value-id={@review.id}
          phx-value-hidden={to_string(is_nil(@review.hidden_at))}
          class="rounded-md border border-base-content/20 px-2 py-1 text-[0.65rem] font-bold uppercase tracking-wider text-base-content/60 transition hover:border-error hover:text-error"
        >
          {if @review.hidden_at, do: "Unhide", else: "Hide"}
        </button>
      </div>
    </div>

    <dl class="mt-3 grid grid-cols-2 gap-x-4 gap-y-1 text-xs sm:grid-cols-4">
      <div :for={{field, label, _} <- Directory.criteria()} class="flex justify-between gap-2">
        <dt class="truncate text-base-content/50">{label}</dt>
        <dd class="font-mono font-bold">{Map.fetch!(@review, field)}</dd>
      </div>
    </dl>

    <div :if={@review.advice not in [nil, ""]} class="mt-3">
      <p class="text-[0.65rem] uppercase tracking-wider text-base-content/50">Advice</p>
      <p class="mt-1 whitespace-pre-line text-sm text-base-content/80">{@review.advice}</p>
    </div>
    <div class="mt-3">
      <p class="text-[0.65rem] uppercase tracking-wider text-base-content/50">Conclusions</p>
      <p class="mt-1 whitespace-pre-line text-sm text-base-content/90">{@review.conclusion}</p>
    </div>

    <div
      :if={@review.gm_reply && !@replying?}
      id={"review-reply-#{@review.id}"}
      class="mt-4 rounded-lg border-l-2 border-secondary bg-secondary/5 px-4 py-3"
    >
      <p class="text-[0.65rem] font-bold uppercase tracking-wider text-secondary">
        Reply from the GDR admin
      </p>
      <p class="mt-1 whitespace-pre-line text-sm text-base-content/80">{@review.gm_reply}</p>
    </div>

    <button
      :if={@can_reply? && !@replying?}
      id={"review-reply-button-#{@review.id}"}
      type="button"
      phx-click="edit_reply"
      phx-value-id={@review.id}
      class="mt-3 inline-flex items-center gap-1 text-xs font-bold uppercase tracking-wider text-secondary transition hover:text-primary"
    >
      <.icon name="hero-chat-bubble-left-ellipsis" class="size-3.5" />
      {if @review.gm_reply, do: "Edit reply", else: "Reply"}
    </button>

    <.form
      :if={@can_reply? && @replying?}
      for={@reply_form}
      id={"review-reply-form-#{@review.id}"}
      phx-submit="save_reply"
      class="mt-4"
    >
      <input type="hidden" name="review_id" value={@review.id} />
      <.input field={@reply_form[:gm_reply]} type="textarea" label="Your reply" rows="3" required />
      <div class="flex items-center gap-3">
        <.button phx-disable-with="Saving...">Save reply</.button>
        <button
          type="button"
          phx-click="cancel_reply"
          class="text-xs text-base-content/60 hover:text-primary"
        >
          Cancel
        </button>
      </div>
    </.form>
    """
  end
end
