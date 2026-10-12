defmodule TannhauserGate.Chat.Archiver do
  @moduledoc """
  Periodically moves the chat messages older than the archive age of their
  GDR into the archive (`Chat.archive_old_messages/1`). Disabled in tests
  (`config :tannhauser_gate, :start_archiver, false`); call
  `Chat.archive_old_messages/1` directly there.
  """

  use GenServer

  require Logger

  @interval :timer.hours(1)

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
      case TannhauserGate.Chat.archive_old_messages() do
        0 -> :ok
        count -> Logger.info("Chat archived #{count} messages")
      end
    rescue
      error -> Logger.error("Chat archiver failed: #{Exception.message(error)}")
    end

    schedule(interval)
    {:noreply, state}
  end

  defp schedule(interval), do: Process.send_after(self(), :tick, interval)
end
