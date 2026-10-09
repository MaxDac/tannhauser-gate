defmodule TannhauserGateWeb.JobsLive do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Bank, Characters}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    case Characters.get_user_story_character(socket.assigns.current_user, story.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:info, "Create a character to take a job.")
         |> push_navigate(to: ~p"/g/#{story}/characters/new")}

      character ->
        {:ok,
         socket
         |> assign(:page_title, "Jobs · #{story.name}")
         |> assign(:character, character)
         |> assign(:jobs, Bank.list_jobs(story))}
    end
  end

  @impl true
  def handle_event("take", %{"id" => id}, socket), do: set_job(socket, id)
  def handle_event("quit", _params, socket), do: set_job(socket, nil)

  defp set_job(socket, job_id) do
    case Bank.set_job(socket.assigns.character, job_id) do
      {:ok, character} ->
        {:noreply,
         socket
         |> put_flash(:info, if(job_id, do: "Job taken.", else: "You quit your job."))
         |> assign(:character, character)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Bank.error_message(reason))}
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
    >
      <.header>
        Jobs
        <:subtitle>
          Paid every {@current_story.pay_interval_hours}h in {@current_story.currency_name}.
        </:subtitle>

        <:actions>
          <.button :if={@character.job_id} id="quit-job" phx-click="quit">Quit current job</.button>
        </:actions>
      </.header>

      <p :if={@jobs == []} id="no-jobs" class="mt-10 text-center text-base-content/60">
        The game master hasn't defined any jobs yet.
      </p>

      <div class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div
          :for={job <- @jobs}
          id={"job-#{job.id}"}
          class={[
            "flex flex-col gap-2 rounded-xl border bg-base-200/80 p-5",
            if(@character.job_id == job.id, do: "border-primary", else: "border-secondary/20")
          ]}
        >
          <p class="text-lg font-bold text-primary">{job.name}</p>

          <p class="text-sm text-base-content/70">{job.description}</p>

          <p class="mt-auto text-sm font-semibold text-secondary">
            {job.pay} {@current_story.currency_name}
          </p>

          <.button
            :if={@character.job_id != job.id}
            id={"take-job-#{job.id}"}
            phx-click="take"
            phx-value-id={job.id}
          >
            Take this job
          </.button>
          <span :if={@character.job_id == job.id} class="badge badge-primary">Current job</span>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
