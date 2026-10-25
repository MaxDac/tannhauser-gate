defmodule TannhauserGate.BackgroundWorkersTest do
  # The workers are registered under their module name: run serially.
  use ExUnit.Case, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias TannhauserGate.{Bank, Characters, Repo, Weather, Zones}
  alias TannhauserGate.Bank.Payer
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Chat.{Archiver, Message}
  alias TannhauserGate.Weather.Roller

  @workers [Payer, Archiver, Roller]

  # A private (non shared) sandbox connection: the workers only reach the
  # database when explicitly allowed.
  setup do
    :ok = Sandbox.checkout(Repo)

    # The workers log their results at :info, below the test log level.
    for worker <- @workers, do: Logger.put_module_level(worker, :info)
    on_exit(fn -> for worker <- @workers, do: Logger.delete_module_level(worker) end)
  end

  defp start_worker!(worker, allow? \\ true) do
    pid = start_supervised!({worker, interval: :timer.hours(1)})
    if allow?, do: Sandbox.allow(Repo, self(), pid)
    pid
  end

  # Runs one tick and waits for the worker to handle it.
  defp tick(pid) do
    send(pid, :tick)
    :sys.get_state(pid)
  end

  describe "Bank.Payer" do
    test "starts with the given interval and reschedules itself" do
      pid = start_worker!(Payer)

      assert :sys.get_state(pid) == %{interval: :timer.hours(1)}
      assert Process.whereis(Payer) == pid
    end

    test "logs nothing when nobody is due" do
      pid = start_worker!(Payer)

      refute capture_log(fn -> tick(pid) end) =~ "Bank"
    end

    test "pays the due characters" do
      {story, _gm} = gdr_fixture()
      character = character_fixture(user_fixture(), story)
      {:ok, _} = Bank.set_job(character, job_fixture(story, %{pay: 15}).id)
      # Taking a job starts the pay interval: pretend it started long ago.
      long_ago = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.truncate(:second)

      Repo.update_all(from(c in Character, where: c.id == ^character.id),
        set: [last_paid_at: long_ago]
      )

      pid = start_worker!(Payer)

      assert capture_log(fn -> tick(pid) end) =~ "Bank paid 1 characters"
      assert Characters.get_character!(character.id).balance == 15
    end

    test "survives database errors" do
      pid = start_worker!(Payer, false)

      assert capture_log(fn -> tick(pid) end) =~ "Bank payer failed"
      assert Process.whereis(Payer) == pid
    end
  end

  describe "Chat.Archiver" do
    test "logs nothing when no message is old enough" do
      pid = start_worker!(Archiver)

      refute capture_log(fn -> tick(pid) end) =~ "Chat"
    end

    test "archives the old messages" do
      {story, _gm} = gdr_fixture(%{archive_after_days: 30})
      location = location_fixture(story)
      player = user_fixture()
      old = message_fixture(player, location, character_fixture(player, story), "Ancient")
      at = DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.truncate(:second)
      Repo.update_all(from(m in Message, where: m.id == ^old.id), set: [inserted_at: at])
      pid = start_worker!(Archiver)

      assert capture_log(fn -> tick(pid) end) =~ "Chat archived 1 messages"
      refute Repo.get(Message, old.id)
    end

    test "survives database errors" do
      pid = start_worker!(Archiver, false)

      assert capture_log(fn -> tick(pid) end) =~ "Chat archiver failed"
      assert Process.whereis(Archiver) == pid
    end
  end

  describe "Weather.Roller" do
    test "logs nothing when no zone is due" do
      pid = start_worker!(Roller)

      assert :sys.get_state(pid) == %{interval: :timer.hours(1)}
      refute capture_log(fn -> tick(pid) end) =~ "Weather"
    end

    test "rolls the weather of the due zones" do
      {story, _gm} = gdr_fixture()
      story = enable_modules(story, [:weather])
      {:ok, zone} = Zones.create_zone(story, %{name: "Docks"})

      {:ok, _} =
        Weather.create_condition(story, %{
          "name" => "Acid rain",
          "icon" => "hero-cloud",
          "weights" => %{"default" => "1"}
        })

      pid = start_worker!(Roller)

      assert capture_log(fn -> tick(pid) end) =~ "Weather rolled for 1 zones"
      assert %{condition: "Acid rain", set_by: "generated"} = Weather.zone_weather(zone)
    end

    test "survives database errors" do
      pid = start_worker!(Roller, false)

      assert capture_log(fn -> tick(pid) end) =~ "Weather roller failed"
      assert Process.whereis(Roller) == pid
    end
  end
end
