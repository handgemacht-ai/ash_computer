defmodule AshComputer.DslTest do
  use ExUnit.Case, async: false

  alias Computer, as: CoreComputer

  defmodule PaceComputer do
    use AshComputer

    alias Computer, as: CoreComputer

    computer :pace do
      input :time do
        type :number
        initial 30
        description "Running time in minutes"
      end

      input :distance do
        type :number
        initial 10
        description "Running distance in km"
      end

      val :pace do
        type :number
        description "Minutes per kilometer"
        compute(fn %{"time" => time, "distance" => distance} -> time / distance end)
      end

      event(:reset, handle: &__MODULE__.reset/1)
      event(:load, handle: &__MODULE__.load/2)
    end

    def reset(computer) do
      computer
      |> CoreComputer.handle_input("time", 30)
      |> CoreComputer.handle_input("distance", 10)
    end

    def load(computer, payload) do
      computer
      |> CoreComputer.handle_input("time", payload["time"])
      |> CoreComputer.handle_input("distance", payload["distance"])
    end
  end

  test "builds and evaluates a computer" do
    computer = AshComputer.computer(PaceComputer)

    assert computer.name == "Pace"
    assert computer.values["pace"] == 3.0

    computer = CoreComputer.handle_input(computer, "time", 40)

    assert computer.values["pace"] == 4.0
  end

  test "runs events" do
    computer = AshComputer.computer(PaceComputer)

    assert [:reset, :load] == AshComputer.events(PaceComputer, :pace)

    computer =
      computer
      |> CoreComputer.handle_input("time", 100)
      |> CoreComputer.handle_input("distance", 50)

    computer = AshComputer.apply_event(PaceComputer, :reset, computer)
    assert computer.values["time"] == 30
    assert computer.values["distance"] == 10
    assert computer.values["pace"] == 3.0

    payload = %{"time" => 45, "distance" => 9}
    computer = AshComputer.apply_event(PaceComputer, :pace, :load, computer, payload)
    assert computer.values["time"] == 45
    assert computer.values["distance"] == 9
    assert computer.values["pace"] == 5.0
  end
end
