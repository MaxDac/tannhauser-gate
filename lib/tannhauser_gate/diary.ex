defmodule TannhauserGate.Diary do
  @moduledoc """
  Character diaries and galleries, the `:diary` optional module.

  ## Diary entries

  In-character entries (`TannhauserGate.Diary.Entry`) with a Markdown body
  and a visibility:

    * `public` - every member of the GDR reads it;
    * `masters` - the owner and the masters;
    * `private` - the owner only. The masters (and the GDR admin and platform
      admins) can still read private entries **for moderation**: they are
      responsible for what is published in their GDR.

  The owner of a player character writes its diary; the masters write the
  diaries of the NPCs. The masters can delete any entry.

  ## Gallery

  Up to `max_images/0` pictures per character (PNG, JPEG or WebP, checked by
  their content, at most `max_image_size/0` bytes), each with a caption. The
  owner and the masters manage it; everyone sees it on the sheet.

  Every function is a no-op (empty lists, `{:error, :module_disabled}`) when
  the module is disabled for the character's GDR.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.{Characters, Repo, Sanctions, Storage, Stories}
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Diary.{Entry, Image}
  alias TannhauserGate.Stories.Story

  @max_images 12
  @max_image_size 5_000_000
  @image_types [:png, :jpeg, :webp]

  def max_images, do: @max_images
  def max_image_size, do: @max_image_size

  @doc "The file extensions accepted by gallery uploads."
  def image_extensions, do: ~w(.png .jpg .jpeg .webp)

  @doc "Whether the diary module is enabled for the story (or story id)."
  def enabled?(%Story{} = story), do: Stories.module_enabled?(story, :diary)
  def enabled?(story_id) when is_integer(story_id), do: enabled?(Stories.get_story(story_id))
  def enabled?(_), do: false

  defp character_enabled?(%Character{story: %Story{} = story}), do: enabled?(story)
  defp character_enabled?(%Character{story_id: story_id}), do: enabled?(story_id)

  ## Permissions

  @doc "Whether the user writes the character's diary: its owner, or a master for NPCs."
  def can_write?(user, %Character{is_npc: true} = character),
    do: Characters.can_view_master_notes?(user, character)

  def can_write?(%{id: user_id}, %Character{user_id: user_id}), do: true
  def can_write?(_, _), do: false

  @doc "Whether the user reads every entry of the character (owner and masters)."
  def can_read_all?(user, %Character{} = character), do: Characters.can_edit?(user, character)

  @doc "Whether the user can delete the entry: its writers and the masters."
  def can_delete?(user, %Character{} = character),
    do: can_write?(user, character) or Characters.can_view_master_notes?(user, character)

  @doc "Whether the user manages the character's gallery: the owner and the masters."
  def can_manage_gallery?(user, %Character{} = character),
    do: Characters.can_edit?(user, character)

  @doc "Whether the user can read the entry."
  def visible?(%Entry{visibility: "public"}, _user, _character), do: true
  def visible?(%Entry{}, user, character), do: can_read_all?(user, character)

  ## Entries

  @doc "The entries of the character the user can read, newest first."
  def list_entries(%Character{} = character, user, opts \\ []) do
    if character_enabled?(character) do
      from(e in Entry,
        where: e.character_id == ^character.id,
        order_by: [desc: e.inserted_at, desc: e.id]
      )
      |> visible_query(user, character)
      |> maybe_limit(opts[:limit])
      |> Repo.all()
    else
      []
    end
  end

  defp visible_query(query, user, character) do
    if can_read_all?(user, character),
      do: query,
      else: where(query, [e], e.visibility == "public")
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  @doc "An entry of the character, or nil (entries of other characters are never found)."
  def get_entry(%Character{id: character_id}, id) do
    case Integer.parse(to_string(id)) do
      {id, ""} ->
        Repo.get_by(Entry, id: id, character_id: character_id)

      _ ->
        nil
    end
  end

  def change_entry(%Entry{} = entry, attrs \\ %{}), do: Entry.changeset(entry, attrs)

  @doc "Writes a new entry in the character's diary."
  def create_entry(user, %Character{} = character, attrs) do
    with :ok <- check_enabled(character),
         :ok <- authorize(can_write?(user, character)),
         :ok <- Sanctions.check_not_muted(user, character.story_id) do
      %Entry{story_id: character.story_id, character_id: character.id, user_id: user.id}
      |> Entry.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc "Updates an entry of the character."
  def update_entry(user, %Character{} = character, %Entry{} = entry, attrs) do
    with :ok <- check_enabled(character),
         :ok <- authorize(entry.character_id == character.id and can_write?(user, character)),
         :ok <- Sanctions.check_not_muted(user, character.story_id) do
      entry |> Entry.changeset(attrs) |> Repo.update()
    end
  end

  @doc "Deletes an entry: its writers and the masters."
  def delete_entry(user, %Character{} = character, %Entry{} = entry) do
    with :ok <- check_enabled(character),
         :ok <- authorize(entry.character_id == character.id and can_delete?(user, character)) do
      Repo.delete(entry)
    end
  end

  ## Gallery

  @doc "The gallery of the character, oldest first. Empty when the module is off."
  def list_images(%Character{} = character) do
    if character_enabled?(character) do
      Repo.all(
        from i in Image,
          where: i.character_id == ^character.id,
          order_by: [asc: i.inserted_at, asc: i.id]
      )
    else
      []
    end
  end

  @doc "How many more pictures fit in the gallery."
  def free_slots(%Character{id: id}) do
    max(@max_images - Repo.aggregate(from(i in Image, where: i.character_id == ^id), :count), 0)
  end

  @doc """
  Adds the uploaded file at `source_path` to the gallery. The file must be a
  PNG, JPEG or WebP image (checked from its content) of at most
  `max_image_size/0` bytes, and the gallery must have room.
  """
  def add_image(user, %Character{} = character, source_path, attrs \\ %{}) do
    changeset = Image.changeset(%Image{}, attrs)

    with :ok <- check_enabled(character),
         :ok <- authorize(can_manage_gallery?(user, character)),
         :ok <- Sanctions.check_not_muted(user, character.story_id),
         :ok <- check_room(character),
         {:ok, type} <- check_image(source_path),
         true <- changeset.valid? || {:error, changeset} do
      path = Storage.store_upload!(source_path, "image.#{type}")

      changeset
      |> Ecto.Changeset.change(
        story_id: character.story_id,
        character_id: character.id,
        path: path
      )
      |> Repo.insert()
    end
  end

  defp check_room(character),
    do: if(free_slots(character) > 0, do: :ok, else: {:error, :gallery_full})

  defp check_image(path) do
    with {:ok, %File.Stat{size: size}} <- File.stat(path),
         true <- size <= @max_image_size || {:error, :too_large},
         type when type in @image_types <- Storage.image_type(path) do
      {:ok, type}
    else
      {:error, :too_large} -> {:error, :too_large}
      _ -> {:error, :invalid_image}
    end
  end

  @doc "Removes a picture of the character's gallery."
  def delete_image(user, %Character{} = character, image_id) do
    with :ok <- check_enabled(character),
         :ok <- authorize(can_manage_gallery?(user, character)),
         %Image{} = image <- get_image(character, image_id) do
      Repo.delete(image)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp get_image(%Character{id: character_id}, id) do
    case Integer.parse(to_string(id)) do
      {id, ""} ->
        Repo.get_by(Image, id: id, character_id: character_id)

      _ ->
        nil
    end
  end

  defp check_enabled(character),
    do: if(character_enabled?(character), do: :ok, else: {:error, :module_disabled})

  defp authorize(true), do: :ok
  defp authorize(_), do: {:error, :unauthorized}

  ## Labels

  def visibility_label("public"), do: "Public"
  def visibility_label("masters"), do: "Masters only"
  def visibility_label("private"), do: "Private"

  def visibility_options,
    do: [
      {"Public — everyone in the GDR", "public"},
      {"Masters — you and the masters", "masters"},
      {"Private — only you (masters may moderate)", "private"}
    ]

  def error_message(:module_disabled), do: "Diaries are not enabled in this GDR."
  def error_message(:muted), do: "You cannot write in this GDR right now."
  def error_message(:unauthorized), do: "You can't do that on this character."
  def error_message(:not_found), do: "That item does not exist."
  def error_message(:gallery_full), do: "The gallery is full (#{@max_images} pictures)."
  def error_message(:too_large), do: "The image is too large (max 5 MB)."
  def error_message(:invalid_image), do: "Only PNG, JPEG and WebP images are allowed."
  def error_message(%Ecto.Changeset{}), do: "Check the caption (max 140 characters)."
  def error_message(_), do: "Something went wrong."
end
