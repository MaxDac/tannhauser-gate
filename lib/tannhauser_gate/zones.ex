defmodule TannhauserGate.Zones do
  @moduledoc """
  Zones group the locations of a GDR (a location belongs to at most one
  zone). The GDR admin defines the zone properties (numeric, e.g. danger,
  resonance) and sets their value on every zone; masters post zone events
  that players see on the zone's locations.

  This context performs no permission checks.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Repo
  alias TannhauserGate.Stories.{Location, Story}
  alias TannhauserGate.Zones.{Event, Property, Zone}

  ## Properties

  def list_properties(%Story{id: story_id}) do
    Repo.all(
      from p in Property,
        where: p.story_id == ^story_id,
        order_by: [asc: p.position, asc: p.name, asc: p.id]
    )
  end

  @doc "The property slugs of the story."
  def property_slugs(%Story{} = story), do: story |> list_properties() |> Enum.map(& &1.slug)

  def get_property!(%Story{id: story_id}, id),
    do: Repo.get_by!(Property, id: id, story_id: story_id)

  def create_property(%Story{} = story, attrs),
    do: %Property{story_id: story.id} |> Property.changeset(attrs) |> Repo.insert()

  def update_property(%Property{} = property, attrs),
    do: property |> Property.changeset(attrs) |> Repo.update()

  def delete_property(%Property{} = property), do: Repo.delete(property)

  def change_property(%Property{} = property, attrs \\ %{}),
    do: Property.changeset(property, attrs)

  ## Zones

  def list_zones(%Story{id: story_id}) do
    Repo.all(
      from z in Zone,
        where: z.story_id == ^story_id,
        order_by: [asc: z.name],
        preload: [locations: ^from(l in Location, order_by: l.name)]
    )
  end

  def get_zone!(%Story{id: story_id}, id), do: Repo.get_by!(Zone, id: id, story_id: story_id)

  @doc "The zone of a location, or nil."
  def zone_of(%Location{zone_id: nil}), do: nil
  def zone_of(%Location{zone_id: zone_id}), do: Repo.get(Zone, zone_id)

  def create_zone(%Story{} = story, attrs) do
    %Zone{story_id: story.id}
    |> Zone.changeset(attrs, property_slugs(story))
    |> Repo.insert()
  end

  def update_zone(%Zone{} = zone, attrs) do
    zone
    |> Zone.changeset(attrs, property_slugs(%Story{id: zone.story_id}))
    |> Repo.update()
  end

  def delete_zone(%Zone{} = zone), do: Repo.delete(zone)

  def change_zone(%Zone{} = zone, attrs \\ %{}),
    do: Zone.changeset(zone, attrs, property_slugs(%Story{id: zone.story_id}))

  @doc """
  The value of a property on a zone, falling back to the property's default
  value. Returns nil when the story has no such property.
  """
  def value(%Zone{} = zone, slug) do
    case Repo.get_by(Property, story_id: zone.story_id, slug: slug) do
      nil -> nil
      property -> Map.get(zone.values, slug, property.default_value)
    end
  end

  @doc """
  The `{property, value}` pairs of a zone, in property order. Pass
  `public_only: true` to hide the properties reserved to masters.
  """
  def zone_values(%Zone{} = zone, opts \\ []) do
    %Story{id: zone.story_id}
    |> list_properties()
    |> Enum.filter(&(&1.public or not Keyword.get(opts, :public_only, false)))
    |> Enum.map(&{&1, Map.get(zone.values, &1.slug, &1.default_value)})
  end

  ## Events

  @doc "The latest events of a zone, newest first."
  def list_events(%Zone{id: zone_id}, limit \\ 20) do
    Repo.all(
      from e in Event,
        where: e.zone_id == ^zone_id,
        order_by: [desc: e.happened_on, desc: e.id],
        limit: ^limit,
        preload: :user
    )
  end

  @doc "The latest events of every zone of the story, newest first."
  def list_story_events(%Story{id: story_id}, limit \\ 50) do
    Repo.all(
      from e in Event,
        join: z in assoc(e, :zone),
        where: z.story_id == ^story_id,
        order_by: [desc: e.happened_on, desc: e.id],
        limit: ^limit,
        preload: [:user, :zone]
    )
  end

  def get_event!(%Story{id: story_id}, id) do
    Repo.one!(
      from e in Event,
        join: z in assoc(e, :zone),
        where: e.id == ^id and z.story_id == ^story_id
    )
  end

  def create_event(%Zone{} = zone, user, attrs) do
    %Event{zone_id: zone.id, user_id: user && user.id}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  def delete_event(%Event{} = event), do: Repo.delete(event)

  def change_event(%Event{} = event, attrs \\ %{}), do: Event.changeset(event, attrs)
end
