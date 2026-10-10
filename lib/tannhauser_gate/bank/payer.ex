defmodule TannhauserGate.Bank.Payer do
  @moduledoc """
  Periodically credits the pay of every character's job. Disabled in tests
  (`config :tannhauser_gate, :start_payer, false`); call `Bank.pay_due/1`
  directly there.
  """

  use GenServer

  require Logger

  @interval :timer.minutes(1)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @interval)
    schedule(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:tick, %{interval: interval} = state) do
    try do
      case TannhauserGate.Bank.pay_due() do
        0 -> :ok
        count -> Logger.info("Bank paid #{count} characters")
      end
    rescue
      error -> Logger.error("Bank payer failed: #{Exception.message(error)}")
    end

    schedule(interval)
    {:noreply, state}
  end

  defp schedule(interval), do: Process.send_after(self(), :tick, interval)
end
