defmodule TannhauserGate.GameFixtures do
  @moduledoc """
  Test helpers for stories, locations, characters, chat and forum.
  """

  alias TannhauserGate.{Accounts, Characters, Chat, Forum, Stories}

  import TannhauserGate.AccountsFixtures

  def admin_fixture(attrs \\ %{}) do
    {:ok, admin} = attrs |> user_fixture() |> Accounts.set_user_role("admin")
    admin
  end

  def story_fixture(attrs \\ %{}) do
    {:ok, story} =
      attrs
      |> Enum.into(%{
        name: "Story #{System.unique_integer([:positive])}",
        summary: "A rainy city.",
        world_background: "Long ago...",
        customs: "Bow politely.",
        map_svg: ~s(<rect width="1000" height="700" fill="#000"/>)
      })
      |> Stories.create_story()

    story
  end

  def location_fixture(story \\ nil, attrs \\ %{}) do
    story = story || story_fixture()

    {:ok, location} =
      Stories.create_location(
        story,
        Enum.into(attrs, %{
          name: "Room #{System.unique_integer([:positive])}",
          description: "Neon and steam.",
          area: "100,100 300,100 300,300 100,300",
          color: "#ff7a1a"
        })
      )

    location
  end

  def character_fixture(user \\ nil, story \\ nil, attrs \\ %{}) do
    user = user || user_fixture()
    story = story || story_fixture()

    {:ok, character} =
      Characters.create_character(
        user,
        Enum.into(attrs, %{
          "name" => "Rick #{System.unique_integer([:positive])}",
          "description" => "A tired detective.",
          "background" => "Retired, then not.",
          "story_id" => story.id
        })
      )

    Characters.get_character!(character.id)
  end

  def message_fixture(user, location, character, body \\ "Hello from the rain") do
    {:ok, message} =
      Chat.create_message(user, location, %{"character_id" => character.id, "body" => body})

    message
  end

  def section_fixture(attrs \\ %{}) do
    {:ok, section} =
      attrs
      |> Enum.into(%{name: "Section #{System.unique_integer([:positive])}", description: "Talk."})
      |> Forum.create_section()

    section
  end

  def topic_fixture(user, section, attrs \\ %{}) do
    {:ok, topic} =
      Forum.create_topic(
        user,
        section,
        Enum.into(attrs, %{"title" => "A topic", "body" => "The opening post"})
      )

    topic
  end

  # 1x1 transparent PNG
  def png_fixture do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
    )
  end
end
