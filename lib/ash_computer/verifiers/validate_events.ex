defmodule AshComputer.Verifiers.ValidateEvents do
  @moduledoc """
  Validates event definitions.

  Every event has exactly one of `handle` (pure) or `run` (effect). An event
  with `run` needs a `handle_result`, and `handle_result` is only allowed with
  `run`. Captures must have the right arity: `handle` 1 or 2, `run` 3,
  `handle_result` 3.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    errors =
      dsl_state
      |> Verifier.get_entities([:computers])
      |> Enum.flat_map(fn computer ->
        Enum.flat_map(computer.events, &validate_event(&1, computer.name))
      end)

    case errors do
      [] -> :ok
      [error] -> {:error, error}
      errors -> {:error, errors}
    end
  end

  defp validate_event(event, computer_name) do
    cond do
      is_nil(event.handle) and is_nil(event.run) ->
        [error(computer_name, event, "needs either `handle` (pure) or `run` (effect)")]

      not is_nil(event.handle) and not is_nil(event.run) ->
        [error(computer_name, event, "cannot have both `handle` and `run`; use one")]

      not is_nil(event.handle) ->
        validate_pure(event, computer_name)

      true ->
        validate_effect(event, computer_name)
    end
  end

  defp validate_pure(event, computer_name) do
    check_arity(event, computer_name, :handle, event.handle, [1, 2]) ++
      if is_nil(event.handle_result) do
        []
      else
        [
          error(
            computer_name,
            event,
            "has `handle_result` but no `run`; `handle_result` only works with `run`"
          )
        ]
      end
  end

  defp validate_effect(event, computer_name) do
    missing =
      if is_nil(event.handle_result) do
        [
          error(
            computer_name,
            event,
            "has `run` but no `handle_result`; add a pure `handle_result` that matches `{:ok, _}` and `{:error, _}`"
          )
        ]
      else
        check_arity(event, computer_name, :handle_result, event.handle_result, [3])
      end

    check_arity(event, computer_name, :run, event.run, [3]) ++ missing
  end

  defp check_arity(event, computer_name, option, fun, arities) do
    if is_function(fun) do
      {:arity, arity} = Function.info(fun, :arity)

      if arity in arities do
        []
      else
        [
          error(
            computer_name,
            event,
            "`#{option}` must have arity #{Enum.join(arities, " or ")}, got arity #{arity}"
          )
        ]
      end
    else
      [
        error(
          computer_name,
          event,
          "`#{option}` must be a function capture, got: #{inspect(fun)}"
        )
      ]
    end
  end

  defp error(computer_name, event, message) do
    DslError.exception(
      path: [:computers, computer_name, :events, event.name],
      message: "Event `#{event.name}` #{message}"
    )
  end
end
