defmodule AshComputer.DslTest do
  use ExUnit.Case, async: false

  alias AshComputer.Runtime, as: CoreComputer

  defmodule PaceComputer do
    use AshComputer

    alias AshComputer.Runtime, as: CoreComputer

    computer :pace do
      input :time do
        initial 30
        description "Running time in minutes"
      end

      input :distance do
        initial 10
        description "Running distance in km"
      end

      val :pace do
        description "Minutes per kilometer"
        compute fn %{time: time, distance: distance} -> time / distance end
      end

      event :reset, handle: &__MODULE__.reset/1
      event :load, handle: &__MODULE__.load/2
    end

    def reset(_values) do
      %{time: 30, distance: 10}
    end

    def load(_values, payload) do
      %{time: payload[:time], distance: payload[:distance]}
    end
  end

  test "builds and evaluates a computer" do
    computer = AshComputer.computer(PaceComputer)

    assert computer.name == "Pace"
    assert computer.values[:pace] == 3.0

    computer = CoreComputer.handle_input(computer, :time, 40)

    assert computer.values[:pace] == 4.0
  end

  test "runs events" do
    computer = AshComputer.computer(PaceComputer)

    assert [:reset, :load] == AshComputer.events(PaceComputer, :pace)

    computer =
      computer
      |> CoreComputer.handle_input(:time, 100)
      |> CoreComputer.handle_input(:distance, 50)

    computer = AshComputer.apply_event(PaceComputer, :reset, computer)
    assert computer.values[:time] == 30
    assert computer.values[:distance] == 10
    assert computer.values[:pace] == 3.0

    payload = %{time: 45, distance: 9}
    computer = AshComputer.apply_event(PaceComputer, :pace, :load, computer, payload)
    assert computer.values[:time] == 45
    assert computer.values[:distance] == 9
    assert computer.values[:pace] == 5.0
  end

  defmodule ChainedComputer do
    use AshComputer

    computer :chained do
      input :base_value do
        initial 10
        description "Base value for calculations"
      end

      val :doubled do
        description "Double the base value"
        compute fn %{base_value: base} -> base * 2 end
      end

      val :quadrupled do
        description "Double the doubled value"
        compute fn %{doubled: doubled} -> doubled * 2 end
      end
    end
  end

  test "vals can depend on other vals" do
    computer = AshComputer.computer(ChainedComputer)

    # Initial values should be computed correctly through the chain
    assert computer.values[:base_value] == 10
    assert computer.values[:doubled] == 20
    assert computer.values[:quadrupled] == 40

    # Update the input and verify the chain updates
    computer = CoreComputer.handle_input(computer, :base_value, 5)

    assert computer.values[:base_value] == 5
    assert computer.values[:doubled] == 10
    assert computer.values[:quadrupled] == 20
  end

  defmodule PatternMatchComputer do
    use AshComputer

    computer :pattern_match do
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

      event :scale do
        handle fn %{x: x, y: y}, %{factor: factor} ->
          %{x: x * factor, y: y * factor}
        end
      end

      event :adjust_based_on_sum do
        handle fn %{x: x, y: y, sum: sum}, _payload ->
          if sum > 100 do
            %{x: x / 2, y: y / 2}
          else
            %{}
          end
        end
      end

      event :set_from_product do
        handle fn %{product: product}, _payload ->
          # Can read vals but only modify inputs
          %{x: product / 10, y: 10}
        end
      end

      event :no_changes do
        handle fn _values, _payload ->
          %{}
        end
      end
    end
  end

  test "event handlers can pattern match on inputs and vals" do
    computer = AshComputer.computer(PatternMatchComputer)

    # Test scaling event
    computer = AshComputer.apply_event(PatternMatchComputer, :pattern_match, :scale, computer, %{factor: 2})
    assert computer.values[:x] == 20
    assert computer.values[:y] == 10
    assert computer.values[:sum] == 30
    assert computer.values[:product] == 200

    # Test conditional logic based on computed vals
    computer = CoreComputer.handle_input(computer, :x, 60)
    computer = CoreComputer.handle_input(computer, :y, 50)
    assert computer.values[:sum] == 110

    computer = AshComputer.apply_event(PatternMatchComputer, :pattern_match, :adjust_based_on_sum, computer, nil)
    assert computer.values[:x] == 30.0
    assert computer.values[:y] == 25.0
    assert computer.values[:sum] == 55.0

    # Test using vals to compute input changes
    computer = AshComputer.apply_event(PatternMatchComputer, :pattern_match, :set_from_product, computer, nil)
    assert computer.values[:x] == 75.0  # product was 750, so 750/10
    assert computer.values[:y] == 10

    # Test empty changes
    old_values = computer.values
    computer = AshComputer.apply_event(PatternMatchComputer, :pattern_match, :no_changes, computer, nil)
    assert computer.values == old_values
  end

  defmodule ValidationComputer do
    use AshComputer

    computer :validation do
      input :input_value do
        initial 5
      end

      val :computed_value do
        compute fn %{input_value: v} -> v * 2 end
      end

      event :try_modify_val do
        handle fn _values, _payload ->
          # This should raise an error
          %{computed_value: 100}
        end
      end

      event :return_non_map do
        handle fn _values, _payload ->
          # This should raise an error
          "not a map"
        end
      end
    end
  end

  test "event handlers cannot modify vals" do
    computer = AshComputer.computer(ValidationComputer)

    assert_raise ArgumentError, ~r/tried to modify non-input values.*computed_value/, fn ->
      AshComputer.apply_event(ValidationComputer, :validation, :try_modify_val, computer, nil)
    end
  end

  test "event handlers must return a map" do
    computer = AshComputer.computer(ValidationComputer)

    assert_raise ArgumentError, ~r/must return a map of input changes/, fn ->
      AshComputer.apply_event(ValidationComputer, :validation, :return_non_map, computer, nil)
    end
  end
end
