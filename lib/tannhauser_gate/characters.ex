defmodule TannhauserGate.Characters do
  @moduledoc """
  Player characters. Each character belongs to a user and to a story.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Repo

  def list_characters do
    Repo.all(
      from c in Character,
        order_by: [asc: c.name, asc: c.id],
        preload: [:user, :story]
    )
  end

  def list_user_characters(%User{id: user_id}, story_id \\ nil) do
    query =
      from c in Character,
        where: c.user_id == ^user_id,
        order_by: [asc: c.name, asc: c.id],
        preload: [:story]

    query = if story_id, do: where(query, [c], c.story_id == ^story_id), else: query

    Repo.all(query)
  end

  def get_character!(id), do: Character |> Repo.get!(id) |> Repo.preload([:user, :story])

  @doc """
  Creates a character owned by `user`. `avatar_path` (optional) is the public
  path of an already stored avatar image.
  """
  def create_character(%User{} = user, attrs, avatar_path \\ nil) do
    %Character{user_id: user.id}
    |> Character.changeset(attrs)
    |> maybe_put_avatar(avatar_path)
    |> Repo.insert()
  end

  def update_character(%Character{} = character, attrs, avatar_path \\ nil) do
    character
    |> Character.changeset(attrs)
    |> maybe_put_avatar(avatar_path)
    |> Repo.update()
  end

  def delete_character(%Character{} = character), do: Repo.delete(character)

  def change_character(%Character{} = character, attrs \\ %{}),
    do: Character.changeset(character, attrs)

  @doc """
  Owners and admins can edit a character.
  """
  def can_edit?(%User{} = user, %Character{} = character) do
    character.user_id == user.id or Accounts.admin?(user)
  end

  def can_edit?(_, _), do: false

  defp maybe_put_avatar(changeset, nil), do: changeset
  defp maybe_put_avatar(changeset, path), do: Character.avatar_changeset(changeset, path)
end
