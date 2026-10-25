defmodule TannhauserGate.Directory do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  The portal: the platform-level directory of GDRs, with their listing
  metadata (genres, lifecycle, content rating, pitch and banner, stored on
  the story), player reviews on a fixed rubric and monthly votes.

    * **Directory** - `list_directory/3` filters the GDRs a user can see by
      genre, lifecycle, rating and text, and sorts them by score, votes,
      activity, age or name.
    * **Reviews** - a user with an approved, non-NPC character created at least
      `review_min_days/0` days ago can review a published GDR they do not run
      (one review each, editable). The GDR admin can reply and platform admins
      hide reviews; hidden reviews never count in the aggregates.
    * **Votes** - one vote per user, GDR and calendar month (UTC), for
      published GDRs; `ranking/2` lists the most voted ones.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.{Accounts, Repo, Storage, Stories}
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Directory.{Review, Vote}
  alias TannhauserGate.Stories.{Story, StoryMaster}

  @genres [
    {"cyberpunk", dgettext_noop("domain", "Cyberpunk")},
    {"fantasy", dgettext_noop("domain", "Fantasy")},
    {"dark_fantasy", dgettext_noop("domain", "Dark fantasy")},
    {"sci_fi", dgettext_noop("domain", "Sci-fi")},
    {"horror", dgettext_noop("domain", "Horror")},
    {"historical", dgettext_noop("domain", "Historical")},
    {"modern", dgettext_noop("domain", "Modern")},
    {"urban_fantasy", dgettext_noop("domain", "Urban fantasy")},
    {"anime_manga", dgettext_noop("domain", "Anime / manga")},
    {"post_apocalyptic", dgettext_noop("domain", "Post-apocalyptic")},
    {"steampunk", dgettext_noop("domain", "Steampunk")},
    {"superheroes", dgettext_noop("domain", "Superheroes")},
    {"mystery_noir", dgettext_noop("domain", "Mystery / noir")},
    {"other", dgettext_noop("domain", "Other")}
  ]

  @lifecycles [
    {"alpha", dgettext_noop("domain", "Alpha test")},
    {"beta", dgettext_noop("domain", "Beta test")},
    {"open", dgettext_noop("domain", "Open")},
    {"closed", dgettext_noop("domain", "Closed")}
  ]

  @content_ratings [
    {"all", dgettext_noop("domain", "All ages")},
    {"12", dgettext_noop("domain", "12+")},
    {"16", dgettext_noop("domain", "16+")},
    {"18", dgettext_noop("domain", "18+")}
  ]

  @criteria [
    {:graphics, dgettext_noop("domain", "Graphics"), "Grafica"},
    {:setting, dgettext_noop("domain", "Setting"), "Ambientazione"},
    {:play_level, dgettext_noop("domain", "In-game play level"), "Livello di gioco interno"},
    {:technical, dgettext_noop("domain", "Code & server"), "Codice e server"},
    {:features, dgettext_noop("domain", "Features"), "Funzionalità"},
    {:documentation, dgettext_noop("domain", "Documentation"), "Documentazione"},
    {:management, dgettext_noop("domain", "Management"), "Gestione"}
  ]

  @sorts [
    {"top", dgettext_noop("domain", "Top rated")},
    {"votes", dgettext_noop("domain", "Most voted this month")},
    {"active", dgettext_noop("domain", "Most active")},
    {"newest", dgettext_noop("domain", "Newest")},
    {"name", dgettext_noop("domain", "Name")}
  ]

  @ranking_size 25

  ## Listing metadata

  @doc "The genres a GDR can be listed under, as `{value, label}`."
  def genres, do: translate_options(@genres)
  def genre_values, do: Enum.map(@genres, &elem(&1, 0))
  def genre_label(value), do: label(@genres, value)

  @doc "The lifecycle statuses (independent from draft/published), as `{value, label}`."
  def lifecycles, do: translate_options(@lifecycles)
  def lifecycle_values, do: Enum.map(@lifecycles, &elem(&1, 0))
  def lifecycle_label(value), do: label(@lifecycles, value)

  @doc "The PEGI-like content ratings, as `{value, label}`."
  def content_ratings, do: translate_options(@content_ratings)
  def content_rating_values, do: Enum.map(@content_ratings, &elem(&1, 0))
  def content_rating_label(value), do: label(@content_ratings, value)

  @doc "The review rubric, as `{field, localized label, legacy Italian label}`."
  def criteria do
    for {field, label, italian} <- @criteria do
      translated = Gettext.dgettext(TannhauserGateWeb.Gettext, "domain", label)

      {field, translated,
       if(Gettext.get_locale(TannhauserGateWeb.Gettext) == "en", do: italian, else: translated)}
    end
  end

  @doc "The directory sort orders, as `{value, label}`."
  def sorts, do: translate_options(@sorts)

  defp translate_options(options) do
    for {value, label} <- options,
        do: {value, Gettext.dgettext(TannhauserGateWeb.Gettext, "domain", label)}
  end

  defp label(list, value) do
    case List.keyfind(list, value, 0) do
      {_, label} -> Gettext.dgettext(TannhauserGateWeb.Gettext, "domain", label)
      nil -> value
    end
  end

  @banner_types [:png, :jpeg, :webp]
  @banner_extensions ~w(.png .jpg .jpeg .webp)

  @doc "The file extensions accepted for directory banners."
  def banner_extensions, do: @banner_extensions

  @doc """
  Stores an uploaded banner when it really is a PNG, JPEG or WebP image
  (sniffed from its bytes): `{:ok, public_path}` or `{:error, :invalid_image}`.
  """
  def store_banner(path, client_name) do
    if Storage.image_type(path) in @banner_types,
      do: {:ok, Storage.store_upload!(path, client_name)},
      else: {:error, :invalid_image}
  end

  ## Directory

  @doc """
  Keeps only the known directory filters with valid values: `"genre"`,
  `"lifecycle"`, `"rating"`, `"q"` (text search) and `"sort"` (default
  `"top"`).
  """
  def normalize_filters(params) when is_map(params) do
    q = params |> Map.get("q", "") |> to_string() |> String.trim() |> String.slice(0, 100)

    %{
      "genre" => valid(params["genre"], genre_values()),
      "lifecycle" => valid(params["lifecycle"], lifecycle_values()),
      "rating" => valid(params["rating"], content_rating_values()),
      "q" => q,
      "sort" => valid(params["sort"], Enum.map(@sorts, &elem(&1, 0))) || "top"
    }
  end

  defp valid(value, allowed), do: if(value in allowed, do: value)

  @doc """
  The GDRs the user can see (see `Stories.visible_stories_query/1`) matching
  the filters (see `normalize_filters/1`), each as a listing entry (see
  `listing/2`), sorted by the `"sort"` filter.

  Options: `:today` (the date of the monthly vote count) and `:online`, a
  function returning the number of users online in a GDR id.
  """
  def list_directory(user, filters \\ %{}, opts \\ []) do
    filters = normalize_filters(filters)

    user
    |> Stories.visible_stories_query()
    |> filter_query(filters)
    |> preload([:owner, :masters])
    |> Repo.all()
    |> entries(opts)
    |> sort_entries(filters["sort"])
  end

  defp filter_query(query, filters) do
    Enum.reduce(filters, query, fn
      {_key, nil}, query ->
        query

      {"genre", genre}, query ->
        where(query, [s], ^genre in s.genres)

      {"lifecycle", lifecycle}, query ->
        where(query, [s], s.lifecycle == ^lifecycle)

      {"rating", rating}, query ->
        where(query, [s], s.content_rating == ^rating)

      {"q", ""}, query ->
        query

      {"q", text}, query ->
        like = "%" <> escape_like(text) <> "%"

        where(
          query,
          [s],
          ilike(s.name, ^like) or ilike(s.pitch, ^like) or ilike(s.summary, ^like)
        )

      _, query ->
        query
    end)
  end

  defp escape_like(text), do: String.replace(text, ~r/[\\%_]/, "\\\\\\0")

  defp sort_entries(entries, sort) do
    Enum.sort_by(entries, fn entry ->
      name = String.downcase(entry.story.name)
      score = entry.score || -1.0

      case sort do
        "votes" -> {-entry.votes, -score, name}
        "active" -> {-entry.online, -entry.members, name}
        "newest" -> {-DateTime.to_unix(entry.story.inserted_at), -entry.id}
        "name" -> {name, entry.id}
        _ -> {-score, -entry.review_count, name}
      end
    end)
  end

  @doc """
  The GDR the user can see with the given id (with its owner and masters),
  or nil.
  """
  def get_visible_story(user, id) do
    case parse_id(id) do
      nil ->
        nil

      id ->
        Repo.one(
          from s in Stories.visible_stories_query(user),
            where: s.id == ^id,
            preload: [:owner, :masters]
        )
    end
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  @doc """
  A listing entry for a story: `%{id, story, score, review_count, members,
  votes, online}`, where `score` is the average overall review score (nil
  without reviews), `members` the distinct users with a non-NPC character,
  `votes` this month's votes. Takes the options of `list_directory/3`.
  """
  def listing(%Story{} = story, opts \\ []), do: [story] |> entries(opts) |> hd()

  defp entries(stories, opts) do
    ids = Enum.map(stories, & &1.id)
    month = month_start(opts[:today] || Date.utc_today())
    online = opts[:online] || fn _ -> 0 end
    scores = review_stats(ids)
    members = member_counts(ids)
    votes = vote_counts(ids, month, month)

    Enum.map(stories, fn story ->
      {score, count} = Map.get(scores, story.id, {nil, 0})

      %{
        id: story.id,
        story: story,
        score: score,
        review_count: count,
        members: Map.get(members, story.id, 0),
        votes: Map.get(votes, story.id, 0),
        online: online.(story.id)
      }
    end)
  end

  defp review_stats([]), do: %{}

  defp review_stats(ids) do
    Repo.all(
      from r in visible_reviews(),
        where: r.story_id in ^ids,
        group_by: r.story_id,
        select:
          {r.story_id,
           avg(
             fragment(
               "(? + ? + ? + ? + ? + ? + ?)::float / 7",
               r.graphics,
               r.setting,
               r.play_level,
               r.technical,
               r.features,
               r.documentation,
               r.management
             )
           ), count(r.id)}
    )
    |> Map.new(fn {id, avg, count} -> {id, {avg, count}} end)
  end

  defp member_counts([]), do: %{}

  defp member_counts(ids) do
    Repo.all(
      from c in Character,
        where: c.story_id in ^ids and not c.is_npc and not is_nil(c.user_id),
        group_by: c.story_id,
        select: {c.story_id, count(c.user_id, :distinct)}
    )
    |> Map.new()
  end

  defp vote_counts([], _, _), do: %{}

  defp vote_counts(ids, from_month, to_month) do
    Repo.all(
      from v in Vote,
        where: v.story_id in ^ids and v.month >= ^from_month and v.month <= ^to_month,
        group_by: v.story_id,
        select: {v.story_id, count(v.id)}
    )
    |> Map.new()
  end

  ## Reviews

  @doc "Days an approved character must exist before its player can review the GDR."
  def review_min_days, do: Application.get_env(:tannhauser_gate, :review_min_days, 14)

  @doc """
  Whether the user can write a review of the story: `:ok` or
  `{:error, reason}`, with reason `:not_published`, `:staff` (its GDR admin
  or a master) or `:no_character` (no approved non-NPC character created at
  least `review_min_days/0` days ago).
  """
  def review_eligibility(user, story, now \\ DateTime.utc_now())

  def review_eligibility(%User{} = user, %Story{} = story, now) do
    cond do
      story.status != "published" -> {:error, :not_published}
      staff?(user, story) -> {:error, :staff}
      not seasoned_character?(user, story, now) -> {:error, :no_character}
      true -> :ok
    end
  end

  def review_eligibility(_, _, _), do: {:error, :no_character}

  def eligibility_message(:not_published),
    do: dgettext("domain", "Draft GDRs cannot be reviewed.")

  def eligibility_message(:staff), do: dgettext("domain", "Staff cannot review their own GDR.")

  def eligibility_message(:no_character) do
    dgettext(
      "domain",
      "You can review this GDR once you have an approved character there that is at least %{days} days old.",
      days: review_min_days()
    )
  end

  @doc "Whether the user runs the story: its owner or one of its masters."
  def staff?(%User{id: user_id}, %Story{owner_id: user_id}), do: true

  def staff?(%User{id: user_id}, %Story{id: story_id}) do
    Repo.exists?(from m in StoryMaster, where: m.story_id == ^story_id and m.user_id == ^user_id)
  end

  defp seasoned_character?(%User{id: user_id}, %Story{id: story_id}, now) do
    cutoff = DateTime.add(now, -review_min_days() * 86_400, :second)

    Repo.exists?(
      from c in Character,
        where:
          c.story_id == ^story_id and c.user_id == ^user_id and not c.is_npc and
            c.approval_status == "approved" and c.inserted_at <= ^cutoff
    )
  end

  defp visible_reviews, do: from(r in Review, where: is_nil(r.hidden_at))

  @doc "The user's review of the story, or nil."
  def get_user_review(%User{id: user_id}, %Story{id: story_id}),
    do: Repo.get_by(Review, story_id: story_id, user_id: user_id)

  def get_user_review(_, _), do: nil

  def change_review(%Review{} = review, attrs \\ %{}), do: Review.changeset(review, attrs)

  @doc """
  Creates the user's review of the story (when eligible, see
  `review_eligibility/3`) or updates it when it exists.
  """
  def save_review(%User{} = user, %Story{} = story, attrs, now \\ DateTime.utc_now()) do
    case get_user_review(user, story) do
      nil ->
        with :ok <- review_eligibility(user, story, now) do
          %Review{story_id: story.id, user_id: user.id}
          |> Review.changeset(attrs)
          |> Repo.insert()
        end

      review ->
        review |> Review.changeset(attrs) |> Repo.update()
    end
  end

  @doc """
  The reviews of the story, newest first, with their authors. Hidden ones
  are included only with `include_hidden: true` (for platform admins).
  """
  def list_reviews(%Story{id: story_id}, opts \\ []) do
    query = if opts[:include_hidden], do: Review, else: visible_reviews()

    Repo.all(
      from r in query,
        where: r.story_id == ^story_id,
        order_by: [desc: r.inserted_at, desc: r.id],
        preload: [:user]
    )
  end

  @doc "Every review on the platform, newest first, for the admins."
  def list_all_reviews do
    Repo.all(
      from r in Review, order_by: [desc: r.inserted_at, desc: r.id], preload: [:user, :story]
    )
  end

  @doc """
  The per-criterion averages of the story's visible reviews:
  `%{count: n, overall: float | nil, criteria: [{field, label, italian, avg}]}`.
  """
  def review_aggregate(%Story{id: story_id}) do
    row =
      Repo.one(
        from r in visible_reviews(),
          where: r.story_id == ^story_id,
          select: %{
            count: count(r.id),
            graphics: avg(r.graphics),
            setting: avg(r.setting),
            play_level: avg(r.play_level),
            technical: avg(r.technical),
            features: avg(r.features),
            documentation: avg(r.documentation),
            management: avg(r.management)
          }
      )

    criteria =
      for {field, label, italian} <- @criteria do
        {field, label, italian, to_float(row[field])}
      end

    averages = for {_, _, _, avg} <- criteria, avg, do: avg

    %{
      count: row.count,
      overall: if(averages == [], do: nil, else: Enum.sum(averages) / length(averages)),
      criteria: criteria
    }
  end

  defp to_float(nil), do: nil
  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value), do: value / 1

  @doc """
  Whether the user can reply to the story's reviews: its GDR admin (or a
  platform admin when the platform runs it).
  """
  def can_reply?(%User{} = user, %Story{} = story) do
    case Stories.role(user, story) do
      :gdr_admin -> true
      :platform_admin -> is_nil(story.owner_id)
      _ -> false
    end
  end

  def can_reply?(_, _), do: false

  @doc """
  The GDR admin replies to (or edits the reply to) a review of their GDR.
  Returns `{:error, :unauthorized}` for anyone else and `{:error, :not_found}`
  for reviews of other GDRs.
  """
  def reply_to_review(user, %Story{} = story, review_id, attrs) do
    with true <- can_reply?(user, story) || {:error, :unauthorized},
         %Review{} = review <- get_story_review(story, review_id) || {:error, :not_found} do
      review |> Review.reply_changeset(attrs) |> Repo.update()
    end
  end

  @doc "A review of the story by id, or nil."
  def get_story_review(%Story{id: story_id}, id) do
    case parse_id(id) do
      nil -> nil
      id -> Repo.one(from r in Review, where: r.id == ^id and r.story_id == ^story_id)
    end
  end

  @doc "A platform admin hides (or shows again) a review (returned with its user and story)."
  def set_review_hidden(admin, review_id, hidden?) when is_boolean(hidden?) do
    with true <- Accounts.admin?(admin) || {:error, :unauthorized},
         %Review{} = review <-
           (parse_id(review_id) && Repo.get(Review, parse_id(review_id))) ||
             {:error, :not_found} do
      review
      |> Ecto.Changeset.change(
        hidden_at: if(hidden?, do: DateTime.utc_now(:second)),
        hidden_by_id: if(hidden?, do: admin.id)
      )
      |> Repo.update()
      |> case do
        {:ok, review} -> {:ok, Repo.preload(review, [:user, :story])}
        error -> error
      end
    end
  end

  ## Votes

  @doc "The first day of the month of the date (the key of monthly votes)."
  def month_start(%Date{} = date), do: Date.beginning_of_month(date)

  @doc """
  The user votes for a published GDR they can see, once per calendar month
  (UTC). Errors: `:not_published`, `:not_found`, `:already_voted`.
  """
  def vote(user, %Story{} = story, today \\ Date.utc_today()) do
    cond do
      not Stories.accessible?(user, story) ->
        {:error, :not_found}

      story.status != "published" ->
        {:error, :not_published}

      true ->
        %Vote{story_id: story.id, user_id: user.id, month: month_start(today)}
        |> Vote.changeset()
        |> Repo.insert()
        |> case do
          {:ok, vote} -> {:ok, vote}
          {:error, _changeset} -> {:error, :already_voted}
        end
    end
  end

  @doc "Whether the user already voted for the story in the month of `today`."
  def voted?(user, story, today \\ Date.utc_today())

  def voted?(%User{id: user_id}, %Story{id: story_id}, today) do
    month = month_start(today)

    Repo.exists?(
      from v in Vote,
        where: v.story_id == ^story_id and v.user_id == ^user_id and v.month == ^month
    )
  end

  def voted?(_, _, _), do: false

  @doc """
  The top #{@ranking_size} published GDRs by votes in the period, ties broken
  by average review score: `:month` (the month of `today`) or `:year` (the
  last 12 months, the current one included). Each entry is a listing entry
  (see `listing/2`) where `votes` counts the period, plus its `rank`.
  """
  def ranking(period, today \\ Date.utc_today()) when period in [:month, :year] do
    to_month = month_start(today)
    from_month = if period == :month, do: to_month, else: Date.shift(to_month, month: -11)

    totals =
      Repo.all(
        from v in Vote,
          join: s in Story,
          on: s.id == v.story_id,
          where: s.status == "published" and v.month >= ^from_month and v.month <= ^to_month,
          group_by: v.story_id,
          select: {v.story_id, count(v.id)}
      )
      |> Map.new()

    stories = Repo.all(from s in Story, where: s.id in ^Map.keys(totals))

    stories
    |> entries(today: today)
    |> Enum.map(&%{&1 | votes: Map.fetch!(totals, &1.id)})
    |> Enum.sort_by(&{-&1.votes, -(&1.score || -1.0), String.downcase(&1.story.name)})
    |> Enum.take(@ranking_size)
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, rank} -> Map.put(entry, :rank, rank) end)
  end
end
