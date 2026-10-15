defmodule AshComputer.EventRunner do
  @moduledoc """
  Runs events, including events with side effects.

  `dispatch_event/7` runs an event and returns the new executor with an
  `AshComputer.Reply`. A pure event (`handle`) yields a reply that only holds
  its input changes. An effect event (`run` and `handle_result`) runs its
  effect synchronously, hands the result to `handle_result` and applies the
  reply's input changes. A crash inside `run` or `handle_result` propagates.

  The runner never touches Phoenix; carrying out the outcomes in the reply is
  up to an adapter.
  """

  alias AshComputer.Context
  alias AshComputer.Executor
  alias AshComputer.Info
  alias AshComputer.Reply

  @doc """
  Runs an event and returns `{executor, reply}`.

  `ctx` is an `AshComputer.Context` (or anything `Context.new/1` accepts).
  Input changes are applied to the executor; only inputs may change.

  ## Options

    * `:as` - the name the computer has in the executor, when it differs from
      `computer_name` (a computer attached under an alias). Defaults to
      `computer_name`, which is also where the event is looked up in `module`.
  """
  @spec dispatch_event(
          module(),
          atom(),
          atom(),
          struct(),
          term(),
          Context.t() | keyword(),
          keyword()
        ) :: {struct(), Reply.t()}
  def dispatch_event(module, computer_name, event_name, executor, params, ctx, opts \\ []) do
    ctx = Context.new(ctx)
    key = Keyword.get(opts, :as, computer_name)
    event = fetch_event!(module, computer_name, event_name)
    values = Executor.current_values(executor, key)

    if is_nil(event.run) do
      changes = run_pure!(event, computer_name, values, params)
      finish(executor, key, computer_name, event, Reply.new(changes))
    else
      result = event.run.(values, params, ctx)
      map_result(module, computer_name, event_name, executor, result, params, opts)
    end
  end

  @doc """
  Turns the result of an event's `run` into `{executor, reply}`.

  Calls the event's `handle_result` with the result, the current values and
  the params, then applies the reply's input changes. The result must be
  `{:ok, _}` or `{:error, _}`. Takes the same `:as` option as `dispatch_event/7`.
  """
  @spec map_result(module(), atom(), atom(), struct(), term(), term(), keyword()) ::
          {struct(), Reply.t()}
  def map_result(module, computer_name, event_name, executor, result, params, opts \\ []) do
    key = Keyword.get(opts, :as, computer_name)
    event = fetch_event!(module, computer_name, event_name)

    if is_nil(event.run) do
      raise ArgumentError,
            "Event #{inspect(event_name)} for #{inspect(computer_name)} has no `run`; there is no result to map"
    end

    unless match?({:ok, _}, result) or match?({:error, _}, result) do
      raise ArgumentError,
            "Event #{inspect(event_name)} for #{inspect(computer_name)} must return {:ok, _} or {:error, _} from `run`, got: #{inspect(result)}"
    end

    values = Executor.current_values(executor, key)

    case event.handle_result.(result, values, params) do
      %Reply{} = reply ->
        finish(executor, key, computer_name, event, reply)

      other ->
        raise ArgumentError,
              "`handle_result` of event #{inspect(event_name)} for #{inspect(computer_name)} must return an %AshComputer.Reply{}, got: #{inspect(other)}"
    end
  end

  defp fetch_event!(module, computer_name, event_name) do
    case Info.computer(module, computer_name) do
      nil ->
        raise ArgumentError,
              "Unknown computer #{inspect(computer_name)} for #{inspect(module)}. " <>
                "Known computers: #{inspect(Info.computer_names(module))}"

      definition ->
        Enum.find(definition.events, &(&1.name == event_name)) ||
          raise ArgumentError,
                "Unknown event #{inspect(event_name)} for #{inspect(computer_name)} in #{inspect(module)}. " <>
                  "Known events: #{inspect(Enum.map(definition.events, & &1.name))}"
    end
  end

  defp run_pure!(%{handle: handler} = event, computer_name, values, params) do
    changes =
      cond do
        is_function(handler, 1) ->
          handler.(values)

        is_function(handler, 2) ->
          handler.(values, params)

        true ->
          raise ArgumentError,
                "Event #{inspect(event.name)} for #{inspect(computer_name)} expects a capture of arity 1 or 2, got: #{inspect(handler)}"
      end

    unless is_map(changes) do
      raise ArgumentError,
            "Event #{inspect(event.name)} for #{inspect(computer_name)} must return a map of input changes, got: #{inspect(changes)}"
    end

    changes
  end

  defp finish(executor, key, computer_name, event, %Reply{changes: changes} = reply) do
    inputs = Map.keys(executor.computers[key].inputs)
    invalid_keys = Map.keys(changes) -- inputs

    unless invalid_keys == [] do
      raise ArgumentError,
            "Event #{inspect(event.name)} for #{inspect(computer_name)} tried to modify non-input values: #{inspect(invalid_keys)}. " <>
              "Only inputs can be modified. Available inputs: #{inspect(inputs)}"
    end

    executor =
      changes
      |> Enum.reduce(Executor.start_frame(executor), fn {input_name, value}, acc ->
        Executor.set_input(acc, key, input_name, value)
      end)
      |> Executor.commit_frame()

    {executor, reply}
  end
end
