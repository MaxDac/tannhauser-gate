defmodule TannhauserGate.Stories.Story do
  @moduledoc """
  A story is a GDR (role playing game): its theme, map and settings. Its world,
  rules and customs live in its guide (`TannhauserGate.Guide`). It is
  configured by its GDR admin (the owner, a game master), or by the platform
  when it has no owner, and narrated by its masters.

  The legacy `world_background`, `rules` and `customs` columns are deprecated:
  they were migrated to guide pages, are no longer mapped and will be dropped.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.{Location, StoryMaster, Themes}

  @statuses ~w(draft published)

  schema "stories" do
    field :name, :string
    field :summary, :string
    field :map_svg, :string
    field :map_width, :integer, default: 1000
    field :map_height, :integer, default: 700
    field :is_default, :boolean, default: false
    field :status, :string, default: "published"
    field :theme, :string, default: "tannhauser"
    field :theme_overrides, :map, default: %{}
    field :currency_name, :string, default: "credits"
    field :pay_interval_hours, :integer, default: 24
    field :archive_after_days, :integer, default: 30
    field :community_url, :string
    field :community_label, :string
    field :modules, :map, default: %{}
    field :max_guilds_per_character, :integer, default: 1
    field :chat_min_length, :integer
    field :chat_max_length, :integer
    field :auto_xp_amount, :integer
    field :auto_xp_min_length, :integer
    field :auto_xp_daily_cap, :integer
    field :auto_xp_cooldown_minutes, :integer
    field :esiti_max_open, :integer, default: 2
    field :esiti_min_xp, :integer
    field :sheet_template, :string

    embeds_one :dice_config, TannhauserGate.Dice.Config, on_replace: :update

    belongs_to :owner, User
    has_many :locations, Location, preload_order: [asc: :name]

    many_to_many :masters, User,
      join_through: StoryMaster,
      preload_order: [asc: :username]

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @gm_fields [
    :name,
    :summary,
    :map_svg,
    :map_width,
    :map_height,
    :status,
    :theme,
    :theme_overrides,
    :currency_name,
    :pay_interval_hours,
    :archive_after_days,
    :community_url,
    :community_label,
    :max_guilds_per_character,
    :chat_min_length,
    :chat_max_length,
    :auto_xp_amount,
    :auto_xp_min_length,
    :auto_xp_daily_cap,
    :auto_xp_cooldown_minutes,
    :esiti_max_open,
    :esiti_min_xp,
    :sheet_template
  ]

  @doc """
  Admin changeset: everything a game master can edit plus the platform flags.
  """
  def changeset(story, attrs) do
    story
    |> cast(attrs, @gm_fields ++ [:is_default])
    |> cast_embed(:dice_config)
    |> validate_story()
  end

  @doc """
  Changeset for game masters editing their own GDR.
  """
  def gm_changeset(story, attrs) do
    story
    |> cast(blank_to_nil(attrs, :esiti_max_open), @gm_fields)
    |> cast_embed(:dice_config)
    |> validate_story()
  end

  @doc """
  Changeset for the optional feature modules (`TannhauserGate.Modules`) of
  the GDR. Unknown keys and non-boolean values are dropped.
  """
  def modules_changeset(story, modules) do
    story
    |> change(modules: TannhauserGate.Modules.sanitize(modules))
  end

  # A blank field would be cast to the field's default: blank means "no limit".
  defp blank_to_nil(attrs, field) do
    key = if Map.has_key?(attrs, field), do: field, else: to_string(field)

    case Map.get(attrs, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: Map.put(attrs, key, nil), else: attrs

      _ ->
        attrs
    end
  end

  defp validate_story(changeset) do
    changeset
    |> validate_required([
      :name,
      :map_width,
      :map_height,
      :currency_name,
      :max_guilds_per_character
    ])
    |> validate_length(:name, max: 120)
    |> validate_length(:currency_name, max: 30)
    |> validate_number(:map_width, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:map_height, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:pay_interval_hours, greater_than: 0, less_than_or_equal_to: 720)
    |> validate_number(:archive_after_days, greater_than: 0, less_than_or_equal_to: 3650)
    |> validate_number(:max_guilds_per_character,
      greater_than: 0,
      less_than_or_equal_to: 20
    )
    |> validate_number(:chat_min_length, greater_than_or_equal_to: 0, less_than_or_equal_to: 4000)
    |> validate_number(:chat_max_length, greater_than: 0, less_than_or_equal_to: 4000)
    |> validate_chat_limits()
    |> validate_number(:auto_xp_amount, greater_than: 0, less_than_or_equal_to: 1000)
    |> validate_number(:auto_xp_min_length,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 4000
    )
    |> validate_number(:auto_xp_daily_cap, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:auto_xp_cooldown_minutes,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1440
    )
    |> validate_number(:esiti_max_open, greater_than: 0, less_than_or_equal_to: 50)
    |> validate_number(:esiti_min_xp,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1_000_000
    )
    |> validate_length(:sheet_template, max: 20_000)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:theme, Themes.presets())
    |> update_change(:theme_overrides, &Themes.sanitize_overrides/1)
    |> validate_map_svg()
    |> validate_length(:community_url, max: 500)
    |> validate_length(:community_label, max: 60)
    |> validate_change(:community_url, &validate_http_url/2)
    |> unique_constraint(:name)
    |> unique_constraint(:owner_id, message: "already runs a GDR")
  end

  defp validate_chat_limits(changeset) do
    min = get_field(changeset, :chat_min_length)
    max = get_field(changeset, :chat_max_length)

    if is_integer(min) and is_integer(max) and min > max,
      do: add_error(changeset, :chat_max_length, "must be at least the minimum length"),
      else: changeset
  end

  # The community link (e.g. a Discord invite) is rendered as an external link.
  defp validate_http_url(field, url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        if String.match?(url, ~r/\s/), do: [{field, "must not contain spaces"}], else: []

      _ ->
        [{field, "must be an http(s) URL"}]
    end
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
