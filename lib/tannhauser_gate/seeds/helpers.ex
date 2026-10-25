defmodule TannhauserGate.Seeds.Helpers do
  @moduledoc """
  Idempotent building blocks shared by the per-GDR seed modules
  (`TannhauserGate.Seeds.DefaultGdr`, `TannhauserGate.Seeds.NeonRepublic`).

  Every helper creates data only when it is missing, so re-running the seeds
  never overwrites what admins and GDR admins changed later.
  """

  alias TannhauserGate.{Accounts, PeriodicActions, Repo, Stories, Trackers}
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.Story

  @doc """
  Resolves seeded credentials: `spec` holds the defaults (`:email`,
  `:username`, `:password`) and an `:env` prefix, so e.g. `"TG_GM"` reads
  `TG_GM_EMAIL`, `TG_GM_USERNAME` and `TG_GM_PASSWORD`.
  """
  def credentials(%{env: env} = spec) do
    %{
      email: System.get_env("#{env}_EMAIL") || spec.email,
      username: System.get_env("#{env}_USERNAME") || spec.username,
      password: System.get_env("#{env}_PASSWORD") || spec.password
    }
  end

  @doc """
  Creates the account described by `spec` (see `credentials/1`) when no
  account uses its email yet, confirmed and flagged to change its password at
  the first access. `flags` (`:admin`, `:gm`) are always (re)applied; an
  existing account keeps its password and `must_change_password` state.
  """
  def seed_user(spec, flags) do
    %{email: email, username: username, password: password} = credentials(spec)

    user =
      case Accounts.get_user_by_email(email) do
        nil ->
          {:ok, user} =
            Accounts.register_user(%{
              username: username,
              email: email,
              password: password,
              terms_accepted: true
            })

          {:ok, user} = Accounts.set_must_change_password(user, true)
          user |> User.confirm_changeset() |> Repo.update!()

        %User{confirmed_at: nil} = user ->
          user |> User.confirm_changeset() |> Repo.update!()

        user ->
          user
      end

    flags = Map.merge(%{admin: user.admin, gm: user.gm}, Map.new(flags))
    {:ok, user} = Accounts.set_user_flags(user, flags)
    user
  end

  @doc """
  Makes `user` the owner (GDR admin) of `story` when the story has none and
  the user does not run another GDR yet.
  """
  def assign_owner(%Story{owner_id: nil} = story, %User{} = user) do
    if Stories.get_owned_story(user) do
      story
    else
      story |> Ecto.Changeset.change(owner_id: user.id) |> Repo.update!()
    end
  end

  def assign_owner(%Story{} = story, _user), do: story

  @doc "Creates the trackers when the story has none."
  def seed_trackers(story, trackers) do
    if Trackers.list_trackers(story) == [] do
      trackers
      |> Enum.with_index()
      |> Enum.each(fn {attrs, index} ->
        {:ok, _} = Trackers.create_tracker(story, Map.put_new(attrs, :position, index))
      end)
    end

    :ok
  end

  @doc "Sets the dice system when the GDR admin never chose one."
  def seed_dice(%Story{dice_config: nil} = story, config) do
    {:ok, story} = Stories.update_story(story, %{dice_config: config})
    story
  end

  def seed_dice(%Story{} = story, _config), do: story

  @doc "Creates the periodic actions when the story has none."
  def seed_actions(story, actions) do
    if PeriodicActions.list_actions(story) == [] do
      actions
      |> Enum.with_index()
      |> Enum.each(fn {attrs, index} ->
        {:ok, _} = PeriodicActions.create_action(story, Map.put_new(attrs, :position, index))
      end)
    end

    :ok
  end
end
