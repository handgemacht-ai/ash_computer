defmodule AshComputer do
  @moduledoc """
  Spark-powered DSL that wraps the `Computer` library with an Ash-style interface.

  Use this module to declare computers inside an Elixir module. Each computer definition
  is translated into helper functions that build the underlying `Computer` struct and
  optionally spawn instances or run events that mutate it.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshComputer.Dsl]]

  alias AshComputer.Builder
  alias AshComputer.Info

  @doc "Computer names declared in this module."
  def computers(module) do
    Info.computer_names(module)
  end

  @doc "Build a computer spec for the default computer."
  def computer_spec(module) do
    name = Info.default_computer_name(module)
    computer_spec(module, name)
  end

  @doc "Build a computer spec by name."
  def computer_spec(module, name) do
    case Info.computer(module, name) do
      nil ->
        raise ArgumentError,
              "Unknown computer #{inspect(name)} for #{inspect(module)}. " <>
                "Known computers: #{inspect(Info.computer_names(module))}"

      definition ->
        builder = Builder.build_builder(definition, module)
        builder.()
    end
  end

  @doc "Get event names for a computer."
  def events(module, name \\ nil) do
    name = name || Info.default_computer_name(module)

    case Info.computer(module, name) do
      nil ->
        raise ArgumentError,
              "Unknown computer #{inspect(name)} for #{inspect(module)}. " <>
                "Known computers: #{inspect(Info.computer_names(module))}"

      definition ->
        Enum.map(definition.events, & &1.name)
    end
  end

  @doc "Apply an event to an executor."
  def apply_event(module, event_name, executor, payload \\ nil) do
    name = Info.default_computer_name(module)
    do_apply_event(module, name, event_name, executor, payload)
  end

  def apply_event(module, name, event_name, executor, payload) do
    do_apply_event(module, name, event_name, executor, payload)
  end

  defp do_apply_event(module, computer_name, event_name, executor, payload) do
    case Info.computer(module, computer_name) do
      nil ->
        raise ArgumentError,
              "Unknown computer #{inspect(computer_name)} for #{inspect(module)}. " <>
                "Known computers: #{inspect(Info.computer_names(module))}"

      definition ->
        event = Enum.find(definition.events, &(&1.name == event_name))

        unless event do
          known_events = Enum.map(definition.events, & &1.name)

          raise ArgumentError,
                "Unknown event #{inspect(event_name)} for #{inspect(computer_name)} in #{inspect(module)}. " <>
                  "Known events: #{inspect(known_events)}"
        end

        apply_event_handler(event.handle, executor, computer_name, payload, event_name)
    end
  end

  defp apply_event_handler(handler, executor, computer_name, payload, event_name) do
    values = AshComputer.Executor.current_values(executor, computer_name)

    changes =
      cond do
        is_function(handler, 1) ->
          handler.(values)

        is_function(handler, 2) ->
          handler.(values, payload)

        true ->
          raise ArgumentError,
                "Event #{inspect(event_name)} for #{inspect(computer_name)} expects a capture of arity 1 or 2, got: #{inspect(handler)}"
      end

    unless is_map(changes) do
      raise ArgumentError,
            "Event #{inspect(event_name)} for #{inspect(computer_name)} must return a map of input changes, got: #{inspect(changes)}"
    end

    computer = executor.computers[computer_name]
    invalid_keys = Map.keys(changes) -- Map.keys(computer.inputs)

    unless invalid_keys == [] do
      raise ArgumentError,
            "Event #{inspect(event_name)} for #{inspect(computer_name)} tried to modify non-input values: #{inspect(invalid_keys)}. " <>
              "Only inputs can be modified. Available inputs: #{inspect(Map.keys(computer.inputs))}"
    end

    executor
    |> AshComputer.Executor.start_frame()
    |> apply_changes(computer_name, changes)
    |> AshComputer.Executor.commit_frame()
  end

  defp apply_changes(executor, computer_name, changes) do
    Enum.reduce(changes, executor, fn {input_name, value}, acc ->
      AshComputer.Executor.set_input(acc, computer_name, input_name, value)
    end)
  end
end
