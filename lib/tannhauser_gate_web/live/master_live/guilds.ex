defmodule TannhauserGateWeb.MasterLive.Guilds do
  @moduledoc """
  Masters manage the guilds and factions of the GDR (guilds module): name,
  Markdown description, emblem, secret membership, join by request or by
  invitation only, and the ranks of each guild with their salary and leader
  flag. Memberships are managed from each guild's page.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Guilds, Storage}
  alias TannhauserGate.Guilds.{Guild, Rank}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :guilds}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Guilds")
     |> allow_upload(:emblem,
       accept: Storage.allowed_extensions(),
       max_entries: 1,
       max_file_size: 5_000_000
     )
     |> reload()
     |> edit_guild(%Guild{ranks: []})}
  end

  defp story(socket), do: socket.assigns.current_story

  defp reload(socket) do
    story = story(socket)

    socket
    |> assign(:guilds, Guilds.list_guilds(story))
    |> assign(:counts, Guilds.member_counts(story))
  end

  defp edit_guild(socket, guild) do
    socket
    |> assign(:guild, guild)
    |> assign(:form, to_form(Guilds.change_guild(guild)))
    |> edit_rank(%Rank{})
  end

  defp edit_rank(socket, rank) do
    position = if rank.id, do: rank.position, else: length(socket.assigns.guild.ranks)
    rank = if rank.id, do: rank, else: %{rank | position: position}
    assign(socket, rank: rank, rank_form: to_form(Guilds.change_rank(rank)))
  end

  defp refresh_guild(socket) do
    socket = reload(socket)

    case socket.assigns.guild do
      %Guild{id: nil} -> socket
      guild -> assign(socket, :guild, Guilds.get_guild!(story(socket), guild.id))
    end
  end

  defp fetch_guild(socket, id), do: Guilds.get_guild(story(socket), id)

  @impl true
  def handle_event("validate", %{"guild" => params}, socket) do
    changeset =
      socket.assigns.guild |> Guilds.change_guild(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"guild" => params}, socket) do
    emblem_path =
      socket
      |> consume_uploaded_entries(:emblem, fn %{path: path}, entry ->
        {:ok, Storage.store_upload!(path, entry.client_name)}
      end)
      |> List.first()

    result =
      case socket.assigns.guild do
        %Guild{id: nil} -> Guilds.create_guild(story(socket), params, emblem_path)
        guild -> Guilds.update_guild(guild, params, emblem_path)
      end

    case result do
      {:ok, guild} ->
        {:noreply,
         socket
         |> put_flash(:info, "Guild saved.")
         |> reload()
         |> edit_guild(Guilds.get_guild!(story(socket), guild.id))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case fetch_guild(socket, id) do
      nil -> {:noreply, put_flash(socket, :error, Guilds.error_message(:guild_not_found))}
      guild -> {:noreply, edit_guild(socket, guild)}
    end
  end

  def handle_event("cancel", _, socket), do: {:noreply, edit_guild(socket, %Guild{ranks: []})}

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :emblem, ref)}

  def handle_event("remove_emblem", _, socket) do
    case socket.assigns.guild do
      %Guild{id: id} = guild when is_integer(id) ->
        {:ok, _} = Guilds.remove_emblem(guild)
        {:noreply, socket |> reload() |> edit_guild(Guilds.get_guild!(story(socket), id))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case fetch_guild(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, Guilds.error_message(:guild_not_found))}

      guild ->
        {:ok, _} = Guilds.delete_guild(guild)

        {:noreply,
         socket
         |> put_flash(:info, "Guild deleted.")
         |> reload()
         |> edit_guild(%Guild{ranks: []})}
    end
  end

  ## Ranks

  def handle_event("save_rank", %{"rank" => params}, socket) do
    %{guild: guild, rank: rank} = socket.assigns

    result =
      cond do
        is_nil(guild.id) -> {:error, :guild_not_found}
        rank.id -> Guilds.update_rank(rank, params)
        true -> Guilds.create_rank(guild, params)
      end

    case result do
      {:ok, _} ->
        socket = refresh_guild(socket)
        {:noreply, socket |> put_flash(:info, "Rank saved.") |> edit_rank(%Rank{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :rank_form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Guilds.error_message(reason))}
    end
  end

  def handle_event("edit_rank", %{"id" => id}, socket) do
    case Guilds.get_rank(socket.assigns.guild, id) do
      nil -> {:noreply, put_flash(socket, :error, Guilds.error_message(:rank_not_found))}
      rank -> {:noreply, edit_rank(socket, rank)}
    end
  end

  def handle_event("cancel_rank", _, socket), do: {:noreply, edit_rank(socket, %Rank{})}

  def handle_event("delete_rank", %{"id" => id}, socket) do
    case Guilds.get_rank(socket.assigns.guild, id) do
      nil ->
        {:noreply, put_flash(socket, :error, Guilds.error_message(:rank_not_found))}

      rank ->
        {:ok, _} = Guilds.delete_rank(rank)
        socket = refresh_guild(socket)
        {:noreply, socket |> put_flash(:info, "Rank deleted.") |> edit_rank(%Rank{})}
    end
  end

  defp upload_error(:too_large), do: "The image is too large (max 5 MB)"
  defp upload_error(:not_accepted), do: "Unsupported file type"
  defp upload_error(:too_many_files), do: "Only one image is allowed"
  defp upload_error(other), do: "Upload error: #{inspect(other)}"

  @impl true
  def render(assigns) do
    errors =
      upload_errors(assigns.uploads.emblem) ++
        Enum.flat_map(assigns.uploads.emblem.entries, &upload_errors(assigns.uploads.emblem, &1))

    assigns = assign(assigns, :emblem_errors, Enum.map(errors, &upload_error/1))

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
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/master"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Master tools
        </.link>
      </div>

      <.header>
        Guilds
        <:subtitle>
          Factions, gangs and corporations: their ranks, salaries and who leads them.
          Memberships are managed from each guild's page.
        </:subtitle>
      </.header>

      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_26rem]">
        <section id="guild-list" class="space-y-3">
          <p :if={@guilds == []} id="guilds-empty" class="text-sm text-base-content/60">
            No guilds yet: add the factions of your world.
          </p>

          <ul class="grid gap-3 sm:grid-cols-2">
            <li
              :for={guild <- @guilds}
              id={"master-guild-#{guild.id}"}
              class={[
                "flex gap-3 rounded-xl border bg-base-200/60 p-4 transition hover:-translate-y-0.5 hover:border-primary/40",
                if(@guild.id == guild.id, do: "border-primary/60", else: "border-secondary/20")
              ]}
            >
              <.guild_emblem guild={guild} class="size-14" />
              <div class="min-w-0 flex-1">
                <div class="flex items-start justify-between gap-2">
                  <.link
                    navigate={~p"/g/#{@current_story}/guilds/#{guild}"}
                    class="truncate font-semibold text-primary hover:underline"
                  >
                    {guild.name}
                  </.link>
                  <span class="flex shrink-0 gap-1">
                    <button
                      id={"edit-guild-#{guild.id}"}
                      phx-click="edit"
                      phx-value-id={guild.id}
                      class="rounded p-0.5 text-base-content/60 transition-colors hover:text-secondary"
                      title="Edit"
                    >
                      <.icon name="hero-pencil" class="size-4" />
                    </button>
                    <button
                      id={"delete-guild-#{guild.id}"}
                      phx-click="delete"
                      phx-value-id={guild.id}
                      data-confirm="Delete this guild with its ranks, members and log?"
                      class="rounded p-0.5 text-base-content/60 transition-colors hover:text-error"
                      title="Delete"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </span>
                </div>
                <p class="text-xs text-base-content/60">
                  {Map.get(@counts, guild.id, 0)} members · {length(guild.ranks)} ranks
                </p>
                <div class="mt-2 flex flex-wrap gap-1 text-xs">
                  <span :if={guild.secret} class="badge badge-soft badge-sm badge-error">
                    <.icon name="hero-eye-slash-micro" class="size-3" /> secret
                  </span>
                  <span class={[
                    "badge badge-soft badge-sm",
                    if(guild.open_join, do: "badge-success", else: "badge-warning")
                  ]}>
                    {if guild.open_join, do: "open to requests", else: "invitation only"}
                  </span>
                </div>
              </div>
            </li>
          </ul>
        </section>

        <div class="space-y-6">
          <section class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {if @guild.id, do: "Edit guild", else: "New guild"}
            </h2>
            <.form
              for={@form}
              id="guild-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-4"
            >
              <.input field={@form[:name]} type="text" label="Name" required />
              <.input
                field={@form[:description]}
                type="textarea"
                label="Description (Markdown)"
                rows="4"
              />
              <.input field={@form[:position]} type="number" label="Position" min="0" />

              <div phx-drop-target={@uploads.emblem.ref} class="mb-2 space-y-2">
                <label for={@uploads.emblem.ref} class="console-label">Emblem (optional)</label>
                <div class="flex flex-wrap items-center gap-3">
                  <img
                    :if={@guild.emblem_path && @uploads.emblem.entries == []}
                    id="guild-emblem"
                    src={@guild.emblem_path}
                    alt=""
                    class="size-14 rounded object-cover"
                  />
                  <button
                    :if={@guild.emblem_path && @uploads.emblem.entries == []}
                    type="button"
                    id="remove-guild-emblem"
                    phx-click="remove_emblem"
                    class="text-xs text-error hover:underline"
                  >
                    Remove
                  </button>
                  <div :for={entry <- @uploads.emblem.entries} class="flex items-center gap-2">
                    <.live_img_preview entry={entry} class="size-14 rounded object-cover" />
                    <button
                      type="button"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                      class="text-xs text-error hover:underline"
                    >
                      Remove
                    </button>
                  </div>
                  <.live_file_input
                    upload={@uploads.emblem}
                    class="file-input file-input-secondary console-field w-full max-w-xs"
                  />
                </div>
                <.error :for={error <- @emblem_errors}>{error}</.error>
              </div>

              <.input
                field={@form[:secret]}
                type="checkbox"
                label="Secret (only members and masters see the guild and its members)"
              />
              <.input
                field={@form[:open_join]}
                type="checkbox"
                label="Characters can ask to join (otherwise invitation only)"
              />

              <div class="mt-4 flex gap-2">
                <.button id="save-guild" phx-disable-with="Saving...">
                  {if @guild.id, do: "Update guild", else: "Add guild"}
                </.button>
                <.button :if={@guild.id} type="button" id="cancel-guild" phx-click="cancel">
                  Done
                </.button>
              </div>
            </.form>
          </section>

          <section
            :if={@guild.id}
            id="guild-ranks"
            class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              Ranks of {@guild.name}
            </h2>
            <p class="mt-1 text-xs text-base-content/60">
              Salaries are paid every pay interval of the GDR. Leaders accept requests, invite,
              and change the rank of or expel the non-leader members.
            </p>
            <ul class="mt-3 divide-y divide-secondary/10 text-sm">
              <li :if={@guild.ranks == []} class="py-2 text-base-content/60">No ranks yet.</li>
              <li
                :for={rank <- @guild.ranks}
                id={"rank-#{rank.id}"}
                class="flex items-center justify-between gap-2 py-1.5"
              >
                <span class="flex items-center gap-2">
                  <span class="w-6 text-right text-xs tabular-nums text-base-content/50">
                    {rank.position}
                  </span>
                  <span class="font-semibold">{rank.name}</span>
                  <span :if={rank.leader} class="badge badge-xs badge-primary badge-soft">
                    <.icon name="hero-star-micro" class="size-3" /> leader
                  </span>
                  <span class="text-xs text-base-content/60">
                    {rank.salary} {@current_story.currency_name}
                  </span>
                </span>
                <span class="flex gap-1">
                  <button
                    id={"edit-rank-#{rank.id}"}
                    phx-click="edit_rank"
                    phx-value-id={rank.id}
                    class="rounded p-0.5 text-base-content/60 transition-colors hover:text-secondary"
                    title="Edit"
                  >
                    <.icon name="hero-pencil" class="size-4" />
                  </button>
                  <button
                    id={"delete-rank-#{rank.id}"}
                    phx-click="delete_rank"
                    phx-value-id={rank.id}
                    data-confirm="Delete this rank? Its members keep their membership without a rank."
                    class="rounded p-0.5 text-base-content/60 transition-colors hover:text-error"
                    title="Delete"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </span>
              </li>
            </ul>

            <.form for={@rank_form} id="rank-form" phx-submit="save_rank" class="mt-4">
              <div class="grid grid-cols-[1fr_5rem] gap-3">
                <.input field={@rank_form[:name]} type="text" label="Rank name" required />
                <.input field={@rank_form[:position]} type="number" label="Order" min="0" />
              </div>
              <.input field={@rank_form[:salary]} type="number" label="Salary" min="0" />
              <.input field={@rank_form[:leader]} type="checkbox" label="Leader rank" />
              <div class="flex gap-2">
                <.button id="save-rank" phx-disable-with="Saving...">
                  {if @rank.id, do: "Update rank", else: "Add rank"}
                </.button>
                <.button :if={@rank.id} type="button" id="cancel-rank" phx-click="cancel_rank">
                  Cancel
                </.button>
              </div>
            </.form>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
