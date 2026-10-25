defmodule TannhauserGate.Origins.Option do
  @moduledoc """
  An option of an origin group (e.g. "Human", "Replicant"): a Markdown
  description, an optional image and sheet bonuses, a map of sheet item
  slugs to (possibly negative) integers added to the character's values.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Origins.Group

  @max_bonus 20

  schema "origin_options" do
    field :name, :string
    field :description, :string
    field :image_path, :string
    field :requires_approval, :boolean, default: false
    field :bonuses, :map, default: %{}
    field :position, :integer, default: 0

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :group, Group

    timestamps(type: :utc_datetime)
  end

  @doc """
  `slugs` are the sheet item keys of the GDR: bonuses may only reference them.
  Blank and zero bonuses are dropped.
  """
  def changeset(option, attrs, slugs) do
    option
    |> cast(attrs, [:name, :description, :requires_approval, :position, :group_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :group_id])
    |> validate_length(:name, max: 60)
    |> validate_length(:description, max: 20_000)
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> cast_bonuses(attrs, slugs)
    |> unique_constraint(:name, name: :origin_options_group_id_name_index)
    |> foreign_key_constraint(:group_id)
  end

  def image_changeset(option_or_changeset, path),
    do: change(option_or_changeset, image_path: path)

  defp cast_bonuses(changeset, attrs, slugs) do
    case fetch(attrs, :bonuses) do
      :error ->
        changeset

      {:ok, raw} when is_map(raw) ->
        Enum.reduce(raw, {%{}, changeset}, fn {slug, value}, {acc, cs} ->
          slug = to_string(slug)

          case parse(value) do
            :blank ->
              {acc, cs}

            {:ok, 0} ->
              {acc, cs}

            {:ok, int} when abs(int) <= @max_bonus ->
              if slug in slugs,
                do: {Map.put(acc, slug, int), cs},
                else: {acc, add_error(cs, :bonuses, "references unknown sheet item #{slug}")}

            {:ok, _} ->
              {acc,
               add_error(cs, :bonuses, "#{slug} must be between -#{@max_bonus} and #{@max_bonus}")}

            :error ->
              {acc, add_error(cs, :bonuses, "#{slug} must be a whole number")}
          end
        end)
        |> then(fn {bonuses, cs} -> put_change(cs, :bonuses, bonuses) end)

      {:ok, _} ->
        add_error(changeset, :bonuses, "is invalid")
    end
  end

  defp fetch(attrs, key) do
    case Map.fetch(attrs, to_string(key)) do
      :error -> Map.fetch(attrs, key)
      found -> found
    end
  end

  defp parse(value) when is_integer(value), do: {:ok, value}
  defp parse(nil), do: :blank

  defp parse(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        :blank

      trimmed ->
        case Integer.parse(trimmed) do
          {int, ""} -> {:ok, int}
          _ -> :error
        end
    end
  end

  defp parse(_), do: :error
end
