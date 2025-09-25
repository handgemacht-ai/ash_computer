defmodule AshComputer.ExecutorDoubleBufferTest do
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

  test "commit_frame retains last successful snapshot when compute fails" do
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(FailureComputer, :double_buffer)
      |> AshComputer.Executor.initialize()

    assert AshComputer.Executor.current_values(executor, :double_buffer)[:count] == 2
    assert AshComputer.Executor.current_values(executor, :double_buffer)[:double] == 4

    executor =
      executor
      |> AshComputer.Executor.start_frame()
      |> AshComputer.Executor.set_input(:double_buffer, :count, 3)
      |> AshComputer.Executor.commit_frame()

    assert AshComputer.Executor.success?(executor)

    assert AshComputer.Executor.current_values(executor, :double_buffer)[:count] == 3
    assert AshComputer.Executor.current_values(executor, :double_buffer)[:double] == 6

    failed =
      executor
      |> AshComputer.Executor.start_frame()
      |> AshComputer.Executor.set_input(:double_buffer, :count, -5)
      |> AshComputer.Executor.commit_frame()

    refute AshComputer.Executor.success?(failed)

    assert AshComputer.Executor.current_values(failed, :double_buffer)[:count] == 3
    assert AshComputer.Executor.current_values(failed, :double_buffer)[:double] == 6

    assert AshComputer.Executor.pending_values(failed, :double_buffer)[:count] == -5

    assert AshComputer.Executor.pending_errors(failed, :double_buffer)[:double] ==
             {:expected, :negative_count}
  end
end