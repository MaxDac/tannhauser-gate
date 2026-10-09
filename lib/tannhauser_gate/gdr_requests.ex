defmodule TannhauserGate.GdrRequests do
  @moduledoc """
  Game masters ask an admin for permission to run their own GDR. Approving a
  request creates the GDR (as a draft) owned by the requesting game master.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias TannhauserGate.Accounts
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.GdrRequests.GdrRequest
  alias TannhauserGate.Repo
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  def change_request(%GdrRequest{} = request, attrs \\ %{}),
    do: GdrRequest.changeset(request, attrs)

  def get_request!(id), do: GdrRequest |> Repo.get!(id) |> Repo.preload([:user, :story])

  @doc "The latest request of a user, if any."
  def latest_request(%User{id: user_id}) do
    Repo.one(
      from r in GdrRequest,
        where: r.user_id == ^user_id,
        order_by: [desc: r.inserted_at, desc: r.id],
        limit: 1
    )
  end

  def list_requests(status \\ nil) do
    query = from r in GdrRequest, order_by: [desc: r.inserted_at, desc: r.id], preload: [:user]
    query = if status, do: where(query, [r], r.status == ^status), else: query
    Repo.all(query)
  end

  def count_pending,
    do: Repo.aggregate(from(r in GdrRequest, where: r.status == "pending"), :count)

  @doc """
  Files a request. Only game masters without a GDR (and without a pending
  request) can do so.
  """
  def create_request(%User{} = user, attrs) do
    cond do
      not Accounts.gm?(user) ->
        {:error, :not_gm}

      Stories.get_owned_story(user) ->
        {:error, :already_has_gdr}

      latest_pending?(user) ->
        {:error, :pending}

      true ->
        %GdrRequest{user_id: user.id}
        |> GdrRequest.changeset(attrs)
        |> Ecto.Changeset.unique_constraint(:user_id, name: :gdr_requests_one_pending_per_user)
        |> Repo.insert()
        |> case do
          {:error, %Ecto.Changeset{errors: [{:user_id, _} | _]}} -> {:error, :pending}
          result -> result
        end
    end
  end

  defp latest_pending?(user) do
    Repo.exists?(from r in GdrRequest, where: r.user_id == ^user.id and r.status == "pending")
  end

  @doc """
  Approves a pending request, creating the GDR for the requester.
  """
  def approve_request(%GdrRequest{status: "pending"} = request, %User{} = admin) do
    if Accounts.admin?(admin), do: do_approve(request, admin), else: {:error, :unauthorized}
  end

  def approve_request(_, _), do: {:error, :not_pending}

  defp do_approve(request, admin) do
    Multi.new()
    |> Multi.run(:claim, fn repo, _ -> claim_pending(repo, request, "approved", admin) end)
    |> Multi.run(:requester, fn repo, _ ->
      case repo.one(from u in User, where: u.id == ^request.user_id, lock: "FOR UPDATE") do
        %User{gm: true} = user -> {:ok, user}
        _ -> {:error, :not_gm}
      end
    end)
    |> Multi.insert(:story, fn _ ->
      %Story{owner_id: request.user_id, status: "draft"}
      |> Story.changeset(%{name: request.name, summary: request.pitch})
    end)
    |> Multi.run(:linked, fn repo, %{story: story} ->
      {1, _} =
        repo.update_all(from(r in GdrRequest, where: r.id == ^request.id),
          set: [story_id: story.id]
        )

      {:ok, story}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{story: story}} -> {:ok, story}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def reject_request(%GdrRequest{status: "pending"} = request, %User{} = admin) do
    if Accounts.admin?(admin) do
      Repo.transaction(fn ->
        case claim_pending(Repo, request, "rejected", admin) do
          {:ok, _} -> get_request!(request.id)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      {:error, :unauthorized}
    end
  end

  def reject_request(_, _), do: {:error, :not_pending}

  # Moves the request out of "pending" only if nobody else did it first, so
  # concurrent approve/reject clicks can't both win.
  defp claim_pending(repo, request, status, admin) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case repo.update_all(
           from(r in GdrRequest, where: r.id == ^request.id and r.status == "pending"),
           set: [status: status, reviewed_by_id: admin.id, updated_at: now]
         ) do
      {1, _} -> {:ok, status}
      {0, _} -> {:error, :not_pending}
    end
  end
end
