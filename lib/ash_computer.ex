defmodule AshComputer do
  @moduledoc """
  Spark-powered DSL that wraps the `Computer` library with an Ash-style interface.

  Use this module to declare computers inside an Elixir module. Each computer definition
  is translated into helper functions that build the underlying `Computer` struct and
  optionally spawn instances or run events that mutate it.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshComputer.Dsl]]

  alias AshComputer.Info
  alias AshComputer.Builder

  @doc "Computer names declared in this module."
  def computers(module) do
    Info.computer_names(module)
  end

  @doc "Build the default computer."
  def computer(module) do
    name = Info.default_computer_name(module)
    computer(module, name)
  end

  @doc "Build a specific computer by name."
  def computer(module, name) do
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

  @doc "Create a computer instance with options."
  def make_instance(module, opts \\ []) do
    name = Info.default_computer_name(module)
    make_instance(module, name, opts)
  end

  def make_instance(module, name, opts) do
    computer(module, name)
    |> AshComputer.Runtime.make_instance(opts)
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

  @doc "Apply an event to a computer."
  def apply_event(module, event_name, computer, payload \\ nil) do
    name = Info.default_computer_name(module)
    do_apply_event(module, name, event_name, computer, payload)
  end

  def apply_event(module, name, event_name, computer, payload) do
    do_apply_event(module, name, event_name, computer, payload)
  end

  defp do_apply_event(module, name, event_name, computer, payload) do
    case Info.computer(module, name) do
      nil ->
        raise ArgumentError,
              "Unknown computer #{inspect(name)} for #{inspect(module)}. " <>
                "Known computers: #{inspect(Info.computer_names(module))}"

      definition ->
        event = Enum.find(definition.events, &(&1.name == event_name))

        unless event do
          known_events = Enum.map(definition.events, & &1.name)

          raise ArgumentError,
                "Unknown event #{inspect(event_name)} for #{inspect(name)} in #{inspect(module)}. " <>
                  "Known events: #{inspect(known_events)}"
        end

        apply_event_handler(event.handle, computer, payload, name, event_name)
    end
  end

  defp apply_event_handler(handler, computer, payload, name, event_name) do
    result =
      cond do
        is_function(handler, 1) ->
          handler.(computer)

        is_function(handler, 2) ->
          handler.(computer, payload)

        true ->
          raise ArgumentError,
                "Event #{inspect(event_name)} for #{inspect(name)} expects a capture of arity 1 or 2, got: #{inspect(handler)}"
      end

    ensure_computer!(result, name, event_name)
  end

  defp ensure_computer!(%AshComputer.Runtime{} = computer, _name, _event_name), do: computer

  defp ensure_computer!(_other, name, event_name) do
    raise ArgumentError,
          "Event #{inspect(event_name)} for #{inspect(name)} must return a Computer struct"
  end
end
