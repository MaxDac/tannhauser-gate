defmodule TannhauserGate.Guide do
  @moduledoc """
  The per-GDR guide: ordered sections, each holding ordered Markdown pages.
  The GDR admin authors it in GM config; members (and visitors of a public
  GDR) read it. It replaces the old story background/rules/customs fields,
  which a data migration turned into a default "The world" section.

  Markdown is rendered with `to_html/1`, which sanitizes the output.
  This context performs no permission checks.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Guide.{Page, Section}
  alias TannhauserGate.Repo
  alias TannhauserGate.Stories.Story

  @doc "The sections of a story with their pages, in order."
  def list_sections(%Story{id: story_id}) do
    Repo.all(
      from s in Section,
        where: s.story_id == ^story_id,
        order_by: [asc: s.position, asc: s.id],
        preload: :pages
    )
  end

  @doc "The first page of the guide, or nil when the guide is empty."
  def first_page(%Story{} = story) do
    story |> list_sections() |> Enum.flat_map(& &1.pages) |> List.first()
  end

  def get_section!(%Story{id: story_id}, id),
    do: Repo.get_by!(Section, id: id, story_id: story_id)

  @doc "A page of the story's guide; raises if it belongs to another story."
  def get_page!(%Story{id: story_id}, id) do
    Repo.one!(
      from p in Page,
        join: s in assoc(p, :section),
        where: p.id == ^id and s.story_id == ^story_id
    )
  end

  def create_section(%Story{} = story, attrs) do
    %Section{story_id: story.id} |> Section.changeset(attrs) |> Repo.insert()
  end

  def update_section(%Section{} = section, attrs),
    do: section |> Section.changeset(attrs) |> Repo.update()

  def delete_section(%Section{} = section), do: Repo.delete(section)

  def change_section(%Section{} = section, attrs \\ %{}), do: Section.changeset(section, attrs)

  @doc "Creates a page; its section must belong to the story."
  def create_page(%Story{} = story, attrs) do
    %Page{} |> Page.changeset(attrs) |> validate_section(story) |> Repo.insert()
  end

  def update_page(%Story{} = story, %Page{} = page, attrs) do
    page |> Page.changeset(attrs) |> validate_section(story) |> Repo.update()
  end

  def delete_page(%Page{} = page), do: Repo.delete(page)

  def change_page(%Page{} = page, attrs \\ %{}), do: Page.changeset(page, attrs)

  defp validate_section(changeset, %Story{id: story_id}) do
    section_id = Ecto.Changeset.get_field(changeset, :section_id)

    if is_nil(section_id) or
         Repo.exists?(from s in Section, where: s.id == ^section_id and s.story_id == ^story_id),
       do: changeset,
       else: Ecto.Changeset.add_error(changeset, :section_id, "is not a section of this guide")
  end

  @doc "Renders Markdown to sanitized HTML (raw HTML and unsafe links are dropped)."
  @spec to_html(String.t() | nil) :: String.t()
  def to_html(nil), do: ""

  def to_html(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown,
      extension: [strikethrough: true, table: true, autolink: true, tasklist: true],
      sanitize: MDEx.Document.default_sanitize_options()
    )
  end
end
