defmodule TannhauserGate.Modules do
  @moduledoc """
  The optional feature modules a GDR admin can turn on for their GDR from the
  GM dashboard ("Modules" tab). The core features (characters, map, chat,
  guide, forum, mail, bank, jobs...) are always on.

  The enabled modules are stored in `stories.modules`, a map of module keys
  (strings) to booleans. Use `TannhauserGate.Stories.module_enabled?/2` to check
  them and the `{TannhauserGateWeb.UserAuth, {:require_module, key}}` on_mount
  hook to guard a LiveView.
  """

  @modules [
    %{
      key: :origins,
      name: "Races & classes",
      icon: "hero-finger-print",
      description: "Origin groups (race, class...) picked at creation, with sheet bonuses."
    },
    %{
      key: :items,
      name: "Items & market",
      icon: "hero-shopping-bag",
      description: "Item catalog, inventory, equipment with dice modifiers and shops."
    },
    %{
      key: :guilds,
      name: "Guilds",
      icon: "hero-flag",
      description: "Guilds and factions with ranks, salaries, guild boards and rooms."
    },
    %{
      key: :chat_rp,
      name: "Chat roleplay",
      icon: "hero-chat-bubble-oval-left-ellipsis",
      description: "Whispers, action tags, speech highlighting and entry length limits."
    },
    %{
      key: :auto_xp,
      name: "Automatic XP",
      icon: "hero-bolt",
      description: "XP for in-character chat entries, with a minimum length and a daily cap."
    },
    %{
      key: :esiti,
      name: "Esiti",
      icon: "hero-inbox-stack",
      description: "Players file action requests that the masters resolve with outcomes."
    },
    %{
      key: :quests,
      name: "Quests",
      icon: "hero-trophy",
      description: "Masters log quests with their participants and hand out rewards."
    },
    %{
      key: :diary,
      name: "Diaries",
      icon: "hero-book-open",
      description: "In-character diaries and a picture gallery on every character sheet."
    },
    %{
      key: :boards,
      name: "Bulletin boards",
      icon: "hero-clipboard-document-list",
      description: "Master announcements on the GDR home and in-game notice boards."
    },
    %{
      key: :calendar,
      name: "Game calendar",
      icon: "hero-calendar-days",
      description: "An in-game date and clock running at a configurable speed."
    },
    %{
      key: :weather,
      name: "Weather",
      icon: "hero-cloud",
      description: "Weather per zone, set by the masters or rolled from a seasonal table."
    },
    %{
      key: :reports,
      name: "Reports & sanctions",
      icon: "hero-flag",
      description: "Players report content; masters warn, mute or ban within the GDR."
    }
  ]

  @keys Enum.map(@modules, & &1.key)
  @string_keys Enum.map(@keys, &Atom.to_string/1)

  @doc "Every optional module, in display order."
  def all, do: @modules

  @doc "The module keys (atoms)."
  def keys, do: @keys

  @doc "Whether `key` (atom or string) names a module."
  def module?(key) when is_atom(key), do: key in @keys
  def module?(key) when is_binary(key), do: key in @string_keys
  def module?(_), do: false

  @doc "The module definition for `key`."
  def get(key) when is_binary(key), do: if(module?(key), do: get(String.to_existing_atom(key)))
  def get(key) when is_atom(key), do: Enum.find(@modules, &(&1.key == key))

  @doc """
  Keeps only known module keys with boolean values, as string keys. Used to
  sanitize `stories.modules` before saving.
  """
  def sanitize(modules) when is_map(modules) do
    for {key, value} <- modules, module?(to_string(key)), into: %{} do
      {to_string(key), value in [true, "true"]}
    end
  end

  def sanitize(_), do: %{}

  @doc "Whether `key` is enabled in the `modules` map."
  def enabled?(modules, key) when is_map(modules) do
    Map.get(modules, to_string(key)) == true
  end

  def enabled?(_, _), do: false
end
