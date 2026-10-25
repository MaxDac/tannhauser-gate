defmodule TannhauserGate.Weather.Roller do
  @moduledoc """
  Periodically rolls a new weather for the due zones of the GDRs with the
  weather module on (`TannhauserGate.Weather.roll_due/2`). Disabled in tests
  (`config :tannhauser_gate, :start_weather_roller, false`); call
  `Weather.roll_due/2` directly there.
  """

  use GenServer

  require Logger

  # Zones expire on their own GDR interval: checking often keeps them fresh.
  @interval :timer.minutes(15)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @interval)
    Process.send_after(self(), :tick, :timer.seconds(30))
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:tick, %{interval: interval} = state) do
    try do
      case TannhauserGate.Weather.roll_due() do
        0 -> :ok
        count -> Logger.info("Weather rolled for #{count} zones")
      end
    rescue
      error -> Logger.error("Weather roller failed: #{Exception.message(error)}")
    end

    Process.send_after(self(), :tick, interval)
    {:noreply, state}
  end
end
