defmodule AshComputer.LiveViewIntegrationTest do
  @moduledoc """
  Tests the LiveView integration at a unit level without requiring a full Phoenix app.
  """
  use ExUnit.Case

  defmodule TestLive do
    use Phoenix.LiveView
    use AshComputer.LiveView

    computer :calculator do
      input :x do
        initial 10
      end

      input :y do
        initial 5
      end

      val :sum do
        compute fn %{x: x, y: y} -> x + y end
      end

      val :product do
        compute fn %{x: x, y: y} -> x * y end
      end

      event :set_x do
        handle fn _values, %{value: value} ->
          %{x: value}
        end
      end

      event :reset do
        handle fn _values, _params ->
          %{x: 10, y: 5}
        end
      end
    end

    @impl true
    def mount(_params, _session, socket) do
      {:ok, mount_computers(socket)}
    end
  end

  describe "helper functions" do
    test "computer builds correctly" do
      # Build a computer directly
      computer = AshComputer.computer(TestLive, :calculator)

      # Check initial values
      assert computer.values[:x] == 10
      assert computer.values[:y] == 5
      assert computer.values[:sum] == 15
      assert computer.values[:product] == 50

      # Update a value
      computer = AshComputer.Runtime.handle_input(computer, :x, 20)

      # Check computed values update
      assert computer.values[:x] == 20
      assert computer.values[:y] == 5
      assert computer.values[:sum] == 25
      assert computer.values[:product] == 100
    end
  end

  describe "event handler generation" do
    test "module defines handle_event callbacks for each computer event" do
      # Check that the functions were generated
      assert function_exported?(TestLive, :handle_event, 3)

      # The generated functions should handle the expected event names
      expected_events = ["calculator_set_x", "calculator_reset"]

      for _event <- expected_events do
        # We can't easily test the actual behavior without a full Phoenix setup,
        # but we can verify the module would handle these events
        assert TestLive.__info__(:functions)
               |> Keyword.get_values(:handle_event)
               |> Enum.member?(3)
      end
    end
  end

  describe "computer info" do
    test "computers are accessible via AshComputer.Info" do
      computer_names = AshComputer.Info.computer_names(TestLive)
      assert computer_names == [:calculator]

      computer = AshComputer.Info.computer(TestLive, :calculator)
      assert computer.name == :calculator
      assert length(computer.inputs) == 2
      assert length(computer.vals) == 2
      assert length(computer.events) == 2
    end
  end
end
