defmodule TannhauserGate.Stories.Story do
  @moduledoc """
  A story is a GDR (role playing game): its world, rules, theme and map. It is
  run by a game master (the owner), or by the platform when it has no owner.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.{Location, Themes}

  @statuses ~w(draft published)

  schema "stories" do
    field :name, :string
    field :summary, :string
    field :world_background, :string
    field :rules, :string
    field :customs, :string
    field :map_svg, :string
    field :map_width, :integer, default: 1000
    field :map_height, :integer, default: 700
    field :is_default, :boolean, default: false
    field :status, :string, default: "published"
    field :theme, :string, default: "tannhauser"
    field :theme_overrides, :map, default: %{}
    field :currency_name, :string, default: "credits"
    field :pay_interval_hours, :integer, default: 24

    belongs_to :owner, User
    has_many :locations, Location, preload_order: [asc: :name]

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @gm_fields [
    :name,
    :summary,
    :world_background,
    :rules,
    :customs,
    :map_svg,
    :map_width,
    :map_height,
    :status,
    :theme,
    :theme_overrides,
    :currency_name,
    :pay_interval_hours
  ]

  @doc """
  Admin changeset: everything a game master can edit plus the platform flags.
  """
  def changeset(story, attrs) do
    story
    |> cast(attrs, @gm_fields ++ [:is_default])
    |> validate_story()
  end

  @doc """
  Changeset for game masters editing their own GDR.
  """
  def gm_changeset(story, attrs) do
    story
    |> cast(attrs, @gm_fields)
    |> validate_story()
  end

  defp validate_story(changeset) do
    changeset
    |> validate_required([:name, :map_width, :map_height, :currency_name])
    |> validate_length(:name, max: 120)
    |> validate_length(:currency_name, max: 30)
    |> validate_length(:rules, max: 50_000)
    |> validate_length(:world_background, max: 50_000)
    |> validate_number(:map_width, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:map_height, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:pay_interval_hours, greater_than: 0, less_than_or_equal_to: 720)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:theme, Themes.presets())
    |> update_change(:theme_overrides, &Themes.sanitize_overrides/1)
    |> validate_map_svg()
    |> unique_constraint(:name)
    |> unique_constraint(:owner_id, message: "already runs a GDR")
  end

  # The map artwork is rendered as an inert SVG image (see
  # `Stories.map_artwork_src/1`); this check is only a backstop.
  defp validate_map_svg(changeset) do
    validate_change(changeset, :map_svg, fn :map_svg, svg ->
      if svg =~ ~r/<\s*script|<\s*foreignObject|<\s*iframe|[\s\/"']on[a-z]+\s*=|javascript:/i do
        [map_svg: "must not contain scripts, event handlers or foreignObject"]
      else
        []
      end
    end)
  end
end
