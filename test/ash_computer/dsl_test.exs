defmodule AshComputer.DslTest do
  use ExUnit.Case, async: false

  defmodule PaceComputer do
    use AshComputer

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
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(PaceComputer, :pace)
      |> AshComputer.Executor.initialize()

    values = AshComputer.Executor.current_values(executor, :pace)
    assert values[:pace] == 3.0

    executor =
      executor
      |> AshComputer.Executor.start_frame()
      |> AshComputer.Executor.set_input(:pace, :time, 40)
      |> AshComputer.Executor.commit_frame()

    values = AshComputer.Executor.current_values(executor, :pace)
    assert values[:pace] == 4.0
  end

  test "runs events" do
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(PaceComputer, :pace)
      |> AshComputer.Executor.initialize()

    assert [:reset, :load] == AshComputer.events(PaceComputer, :pace)

    executor =
      executor
      |> AshComputer.Executor.start_frame()
      |> AshComputer.Executor.set_input(:pace, :time, 100)
      |> AshComputer.Executor.set_input(:pace, :distance, 50)
      |> AshComputer.Executor.commit_frame()

    executor = AshComputer.apply_event(PaceComputer, :reset, executor)
    values = AshComputer.Executor.current_values(executor, :pace)
    assert values[:time] == 30
    assert values[:distance] == 10
    assert values[:pace] == 3.0

    payload = %{time: 45, distance: 9}
    executor = AshComputer.apply_event(PaceComputer, :pace, :load, executor, payload)
    values = AshComputer.Executor.current_values(executor, :pace)
    assert values[:time] == 45
    assert values[:distance] == 9
    assert values[:pace] == 5.0
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

  defmodule AliasedComputer do
    use AshComputer

    # This alias is used in the compute function to test alias resolution
    alias Enum, as: MyEnum

    computer :aliased do
      input :numbers do
        initial [1, 2, 3]
        description "A list of numbers"
      end

      val :sum do
        description "Sum using aliased Enum"
        compute fn %{numbers: numbers} ->
          # This uses the alias and should work after our fix
          MyEnum.sum(numbers)
        end
      end
    end
  end

  test "vals can depend on other vals" do
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(ChainedComputer, :chained)
      |> AshComputer.Executor.initialize()

    values = AshComputer.Executor.current_values(executor, :chained)
    assert values[:base_value] == 10
    assert values[:doubled] == 20
    assert values[:quadrupled] == 40

    executor =
      executor
      |> AshComputer.Executor.start_frame()
      |> AshComputer.Executor.set_input(:chained, :base_value, 5)
      |> AshComputer.Executor.commit_frame()

    values = AshComputer.Executor.current_values(executor, :chained)
    assert values[:base_value] == 5
    assert values[:doubled] == 10
    assert values[:quadrupled] == 20
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
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(PatternMatchComputer, :pattern_match)
      |> AshComputer.Executor.initialize()

    executor =
      AshComputer.apply_event(PatternMatchComputer, :pattern_match, :scale, executor, %{
        factor: 2
      })

    values = AshComputer.Executor.current_values(executor, :pattern_match)
    assert values[:x] == 20
    assert values[:y] == 10
    assert values[:sum] == 30
    assert values[:product] == 200

    executor =
      executor
      |> AshComputer.Executor.start_frame()
      |> AshComputer.Executor.set_input(:pattern_match, :x, 60)
      |> AshComputer.Executor.set_input(:pattern_match, :y, 50)
      |> AshComputer.Executor.commit_frame()

    values = AshComputer.Executor.current_values(executor, :pattern_match)
    assert values[:sum] == 110

    executor =
      AshComputer.apply_event(
        PatternMatchComputer,
        :pattern_match,
        :adjust_based_on_sum,
        executor,
        nil
      )

    values = AshComputer.Executor.current_values(executor, :pattern_match)
    assert values[:x] == 30.0
    assert values[:y] == 25.0
    assert values[:sum] == 55.0

    executor =
      AshComputer.apply_event(
        PatternMatchComputer,
        :pattern_match,
        :set_from_product,
        executor,
        nil
      )

    values = AshComputer.Executor.current_values(executor, :pattern_match)
    assert values[:x] == 75.0
    assert values[:y] == 10

    old_values = values

    executor =
      AshComputer.apply_event(PatternMatchComputer, :pattern_match, :no_changes, executor, nil)

    values = AshComputer.Executor.current_values(executor, :pattern_match)
    assert values == old_values
  end

  test "aliased modules work in compute functions" do
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(AliasedComputer, :aliased)
      |> AshComputer.Executor.initialize()

    values = AshComputer.Executor.current_values(executor, :aliased)
    assert values[:sum] == 6
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
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(ValidationComputer, :validation)
      |> AshComputer.Executor.initialize()

    assert_raise ArgumentError, ~r/tried to modify non-input values.*computed_value/, fn ->
      AshComputer.apply_event(ValidationComputer, :validation, :try_modify_val, executor, nil)
    end
  end

  test "event handlers must return a map" do
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(ValidationComputer, :validation)
      |> AshComputer.Executor.initialize()

    assert_raise ArgumentError, ~r/must return a map of input changes/, fn ->
      AshComputer.apply_event(ValidationComputer, :validation, :return_non_map, executor, nil)
    end
  end
end
