defmodule TannhauserGate.Stories do
  @moduledoc """
  Stories describe a world (background, customs) and its map of locations.
  Each location doubles as a chat room.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Repo
  alias TannhauserGate.Stories.{Location, Story}

  ## Stories

  def list_stories do
    Repo.all(from s in Story, order_by: [desc: s.is_default, asc: s.name])
  end

  def get_story!(id), do: Story |> Repo.get!(id) |> Repo.preload(:locations)

  @doc """
  Returns the default story (the one flagged `is_default`, or the oldest one).
  """
  def get_default_story do
    query =
      from s in Story, order_by: [desc: s.is_default, asc: s.inserted_at, asc: s.id], limit: 1

    case Repo.one(query) do
      nil -> nil
      story -> Repo.preload(story, :locations)
    end
  end

  def get_story_by_name(name), do: Repo.get_by(Story, name: name)

  def create_story(attrs \\ %{}) do
    %Story{}
    |> Story.changeset(attrs)
    |> Repo.insert()
    |> tap_default()
  end

  def update_story(%Story{} = story, attrs) do
    story
    |> Story.changeset(attrs)
    |> Repo.update()
    |> tap_default()
  end

  def delete_story(%Story{} = story), do: Repo.delete(story)

  def change_story(%Story{} = story, attrs \\ %{}), do: Story.changeset(story, attrs)

  # Only one story can be the default: unset the flag on all the others.
  defp tap_default({:ok, %Story{is_default: true, id: id}} = result) do
    Repo.update_all(from(s in Story, where: s.id != ^id and s.is_default),
      set: [is_default: false]
    )

    result
  end

  defp tap_default(result), do: result

  ## Locations

  def list_locations(%Story{id: story_id}) do
    Repo.all(from l in Location, where: l.story_id == ^story_id, order_by: [asc: l.name])
  end

  def list_all_locations do
    Repo.all(from l in Location, order_by: [asc: l.story_id, asc: l.name], preload: :story)
  end

  def get_location!(id), do: Location |> Repo.get!(id) |> Repo.preload(:story)

  def create_location(%Story{} = story, attrs \\ %{}) do
    %Location{story_id: story.id}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  def update_location(%Location{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> Repo.update()
  end

  def delete_location(%Location{} = location), do: Repo.delete(location)

  def change_location(%Location{} = location, attrs \\ %{}),
    do: Location.changeset(location, attrs)
end
