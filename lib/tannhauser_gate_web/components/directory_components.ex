defmodule TannhauserGateWeb.DirectoryComponents do
  @moduledoc """
  Building blocks of the portal pages (directory, GDR profile, ranking):
  banners, lifecycle and content rating badges, genre chips and scores.
  """
  use Phoenix.Component
  use Gettext, backend: TannhauserGateWeb.Gettext

  import TannhauserGateWeb.CoreComponents, only: [icon: 1]

  alias TannhauserGate.Directory

  attr :story, :map, required: true
  attr :class, :string, default: "h-36"
  slot :inner_block

  @doc "The GDR banner, or a gradient with its initial when it has none."
  def banner(assigns) do
    ~H"""
    <div class={["relative overflow-hidden bg-base-300", @class]}>
      <img
        :if={@story.banner_path}
        src={@story.banner_path}
        alt=""
        loading="lazy"
        class="absolute inset-0 size-full object-cover transition duration-500 group-hover:scale-105"
      />
      <div
        :if={!@story.banner_path}
        class="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-primary/25 via-base-300 to-secondary/25"
      >
        <span class="font-mono text-5xl font-bold text-primary/40 transition duration-500 group-hover:scale-110">
          {@story.name |> String.first() |> String.upcase()}
        </span>
      </div>

      <div class="absolute inset-0 bg-gradient-to-t from-base-200 via-base-200/10 to-transparent" /> {render_slot(
        @inner_block
      )}
    </div>
    """
  end

  attr :lifecycle, :string, required: true
  attr :id, :string, default: nil

  def lifecycle_badge(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-wider backdrop-blur",
        lifecycle_class(@lifecycle)
      ]}
    >
      <span class="size-1.5 rounded-full bg-current" /> {Directory.lifecycle_label(@lifecycle)}
    </span>
    """
  end

  defp lifecycle_class("alpha"), do: "border-warning/50 bg-warning/15 text-warning"
  defp lifecycle_class("beta"), do: "border-info/50 bg-info/15 text-info"
  defp lifecycle_class("closed"), do: "border-error/50 bg-error/15 text-error"
  defp lifecycle_class(_), do: "border-success/50 bg-success/15 text-success"

  attr :rating, :string, required: true
  attr :id, :string, default: nil

  def rating_badge(assigns) do
    ~H"""
    <span
      id={@id}
      title={
        dgettext("player", "Content rating: %{value}", value: Directory.content_rating_label(@rating))
      }
      class={[
        "inline-flex min-w-9 items-center justify-center rounded-md border px-1.5 py-0.5 font-mono text-[0.7rem] font-bold backdrop-blur",
        rating_class(@rating)
      ]}
    >
      {Directory.content_rating_label(@rating)}
    </span>
    """
  end

  defp rating_class("18"), do: "border-error/60 bg-base-100/70 text-error"
  defp rating_class("16"), do: "border-warning/60 bg-base-100/70 text-warning"
  defp rating_class("12"), do: "border-info/60 bg-base-100/70 text-info"
  defp rating_class(_), do: "border-success/60 bg-base-100/70 text-success"

  attr :genres, :list, required: true

  def genre_chips(assigns) do
    ~H"""
    <ul :if={@genres != []} class="flex flex-wrap gap-1.5" aria-label={dgettext("player", "Genres")}>
      <li
        :for={genre <- @genres}
        class="rounded-full border border-secondary/30 bg-secondary/10 px-2 py-0.5 text-[0.7rem] text-secondary"
      >
        {Directory.genre_label(genre)}
      </li>
    </ul>
    """
  end

  attr :score, :any, required: true
  attr :count, :integer, default: nil
  attr :class, :string, default: nil

  @doc "An average score out of 5 with a star, or a dash without reviews."
  def score(assigns) do
    ~H"""
    <span
      class={["inline-flex items-center gap-1", @class]}
      title={
        if @score,
          do: dgettext("player", "Average review score"),
          else: dgettext("player", "No reviews yet")
      }
    >
      <.icon
        name="hero-star-solid"
        class={["size-4", if(@score, do: "text-warning", else: "text-base-content/30")]}
      /> <span class="font-mono font-bold">{format_score(@score)}</span>
      <span :if={@count} class="text-base-content/50">({@count})</span>
    </span>
    """
  end

  @doc "A score with one decimal, or a dash."
  def format_score(nil), do: "–"
  def format_score(score), do: :erlang.float_to_binary(score / 1, decimals: 1)
end
