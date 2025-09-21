defmodule AshComputer.RuntimeDoubleBufferTest do
  use ExUnit.Case, async: false

  defmodule FailureComputer do
    use AshComputer

    computer :double_buffer do
      input :count do
        initial 2
      end

      val :double do
        compute fn %{count: count} ->
          cond do
            is_integer(count) and count >= 0 ->
              {:ok, count * 2}

            is_integer(count) ->
              {:error, :negative_count}

            true ->
              {:error, :invalid_type}
          end
        end
      end
    end
  end

  test "handle_input retains last successful snapshot when compute fails" do
    computer = AshComputer.computer(FailureComputer)

    assert AshComputer.Runtime.current_values(computer)[:count] == 2
    assert AshComputer.Runtime.current_values(computer)[:double] == 4

    computer = AshComputer.Runtime.handle_input(computer, :count, 3)

    assert AshComputer.Runtime.success?(computer)

    assert AshComputer.Runtime.current_values(computer)[:count] == 3
    assert AshComputer.Runtime.current_values(computer)[:double] == 6

    failed = AshComputer.Runtime.handle_input(computer, :count, -5)

    refute AshComputer.Runtime.success?(failed)

    assert AshComputer.Runtime.current_values(failed)[:count] == 3
    assert AshComputer.Runtime.current_values(failed)[:double] == 6

    assert AshComputer.Runtime.pending_values(failed)[:count] == -5
    assert AshComputer.Runtime.pending_errors(failed)[:double] == {:expected, :negative_count}
  end
end
