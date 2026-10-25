defmodule TannhauserGateWeb.EsitiComponents do
  @moduledoc "Shared pieces of the esiti pages (esiti module)."
  use Phoenix.Component

  alias TannhauserGate.Esiti

  attr :id, :string, default: nil
  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "badge badge-soft badge-sm whitespace-nowrap",
        case @status do
          "open" -> "badge-warning"
          "claimed" -> "badge-info"
          "resolved" -> "badge-success"
          _ -> "badge-neutral"
        end
      ]}
    >
      {Esiti.status_label(@status)}
    </span>
    """
  end

  @doc "Where the esito takes place: its room or zone, if any."
  def place(%{location: %{name: name}}), do: name
  def place(%{zone: %{name: name}}), do: name
  def place(_), do: nil

  def when_label(%DateTime{} = at), do: Calendar.strftime(at, "%d/%m/%Y %H:%M")
  def when_label(_), do: ""
end
