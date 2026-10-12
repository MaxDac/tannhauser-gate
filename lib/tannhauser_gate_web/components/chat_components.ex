defmodule TannhauserGateWeb.ChatComponents do
  @moduledoc """
  Rendering of chat entries: kind badges and dice results (shared by the
  rooms and the master chat log).
  """
  use Phoenix.Component

  import TannhauserGateWeb.CoreComponents, only: [icon: 1]

  alias TannhauserGate.Dice

  @doc "A small badge naming an entry kind (nothing for in-character speech)."
  attr :kind, :string, required: true

  def kind_badge(%{kind: "speech"} = assigns), do: ~H""

  def kind_badge(assigns) do
    ~H"""
    <span class={[
      "chat-kind rounded px-1.5 py-0.5 text-[0.65rem] font-bold uppercase tracking-widest",
      @kind == "ooc" && "bg-fog-700/60 text-fog-300",
      @kind == "narration" && "bg-warning/15 text-warning",
      @kind == "status" && "bg-info/15 text-info",
      @kind == "dice" && "bg-mint/15 text-mint"
    ]}>
      {kind_label(@kind)}
    </span>
    """
  end

  @doc "Human readable label of an entry kind."
  def kind_label("speech"), do: "In character"
  def kind_label("ooc"), do: "OFF"
  def kind_label("narration"), do: "Narration"
  def kind_label("status"), do: "Room status"
  def kind_label("dice"), do: "Dice"
  def kind_label(kind), do: kind

  @doc "The full breakdown of a dice result (see `TannhauserGate.Dice`)."
  attr :id, :string, required: true
  attr :result, :map, required: true

  def dice_result(assigns) do
    ~H"""
    <div
      id={@id}
      class="dice-result mt-1 rounded-lg border border-mint/25 bg-night/70 p-3 text-sm"
    >
      <p class="flex flex-wrap items-center gap-2">
        <.icon name="hero-cube-transparent" class="size-4 text-mint" />
        <span :if={@result["label"]} class="font-semibold text-fog-100">{@result["label"]}</span>
        <span class="text-fog-400">{system_label(@result)}</span>
        <span
          :if={Dice.outcome_label(@result["outcome"])}
          class={[
            "dice-outcome ml-auto rounded px-2 py-0.5 text-xs font-bold uppercase tracking-wider",
            outcome_class(@result["outcome"])
          ]}
        >
          {Dice.outcome_label(@result["outcome"])}
        </span>
      </p>

      <ul class="mt-2 flex flex-wrap gap-1.5" aria-label="Dice">
        <li
          :for={{die, index} <- Enum.with_index(@result["dice"] || group_dice(@result))}
          class={[
            "dice-face grid size-8 place-items-center rounded-md border font-mono text-sm font-bold transition-transform hover:-translate-y-0.5",
            die_class(die),
            index in (@result["rerolled_indexes"] || []) && "ring-2 ring-warning/60"
          ]}
          title={die_title(die)}
        >
          {die["value"]}
        </li>
      </ul>

      <p class="mt-2 text-xs text-fog-400">
        <span :for={item <- @result["items"] || []} class="mr-2">
          {item["name"]} <span class="text-fog-200">{item["value"]}</span>
        </span>

        <span :if={(@result["modifier"] || 0) != 0} class="mr-2">
          modifier <span class="text-fog-200">{signed(@result["modifier"])}</span>
        </span>

        <span :if={@result["special_count"] && @result["special_count"] > 0} class="mr-2">
          special dice <span class="text-error">{@result["special_count"]}</span>
        </span>

        <span :if={@result["rerolled"]} class="mr-2 text-warning">
          rerolled ({@result["reroll_tracker"]})
        </span>
      </p>

      <p class="dice-summary mt-1 font-semibold text-fog-100">{@result["summary"]}</p>
    </div>
    """
  end

  defp system_label(%{"system" => "pool", "pool" => pool}), do: "pool of #{pool}"
  defp system_label(%{"system" => "d20"}), do: "d20"
  defp system_label(%{"system" => "expression", "expression" => e}), do: e
  defp system_label(_), do: nil

  defp group_dice(%{"groups" => groups}) do
    for group <- groups, value <- group["rolls"], do: %{"value" => value}
  end

  defp group_dice(_), do: []

  defp die_class(%{"special" => true, "success" => true}),
    do: "border-error/70 bg-error/20 text-error"

  defp die_class(%{"special" => true}), do: "border-error/40 bg-error/5 text-error/80"
  defp die_class(%{"success" => true}), do: "border-mint/70 bg-mint/15 text-mint"
  defp die_class(%{"success" => false}), do: "border-fog-700 bg-ink text-fog-500"
  defp die_class(_), do: "border-mint/40 bg-ink text-fog-100"

  defp die_title(%{"special" => true}), do: "Special die"
  defp die_title(%{"success" => true}), do: "Success"
  defp die_title(%{"success" => false}), do: "Failure"
  defp die_title(_), do: nil

  defp outcome_class(outcome) when outcome in ["critical", "success"],
    do: "bg-mint/20 text-mint"

  defp outcome_class("messy_critical"), do: "bg-warning/20 text-warning"
  defp outcome_class(_), do: "bg-error/20 text-error"

  defp signed(value) when value > 0, do: "+#{value}"
  defp signed(value), do: to_string(value)
end
