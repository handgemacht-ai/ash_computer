defmodule AshComputer.Info do
  @moduledoc """
  Runtime introspection functions for accessing computer information from modules.
  """

  alias Spark.Dsl.Extension

  @doc """
  Get all computers defined in a module.
  """
  def computers(module) do
    Extension.get_entities(module, [:computers]) || []
  end

  @doc """
  Get a specific computer by name from a module.
  """
  def computer(module, name) do
    computers(module)
    |> Enum.find(fn
      %AshComputer.Dsl.Computer{name: ^name} -> true
      _ -> false
    end)
  end

  @doc """
  Get all computer names from a module.
  """
  def computer_names(module) do
    computers(module)
    |> Enum.map(& &1.name)
  end

  @doc """
  Get the default computer name for a module.
  """
  def default_computer_name(module) do
    case Extension.get_persisted(module, :ash_computer_default_name) do
      nil ->
        # Fall back to the first computer if no default was persisted
        case computers(module) do
          [%{name: name} | _] -> name
          [] -> nil
        end

      name ->
        name
    end
  end

  @doc """
  Check if a module has any computers defined.
  """
  def has_computers?(module) do
    computers(module) != []
  end

  @doc """
  Get all event names for a computer as they appear in handle_event callbacks.

  Returns a list of strings like ["computer_name_event_name"].
  This uses the same naming logic as the actual event handler generation,
  ensuring compile-time consistency.

  ## Examples

      event_names(MyLive, :calculator)
      #=> ["calculator_set_x", "calculator_reset"]

  """
  def event_names(module, computer_name) do
    case computer(module, computer_name) do
      nil ->
        []

      computer ->
        computer.events
        |> Enum.map(fn event -> "#{computer_name}_#{event.name}" end)
    end
  end

  @doc """
  Get a single event name as it appears in handle_event callbacks.

  Returns a string like "computer_name_event_name".
  This uses the same naming logic as the actual event handler generation,
  ensuring compile-time consistency.

  ## Examples

      event_name(MyLive, :calculator, :set_x)
      #=> "calculator_set_x"

  """
  def event_name(module, computer_name, event_name) do
    case computer(module, computer_name) do
      nil -> nil
      computer -> generate_event_name(computer, computer_name, event_name)
    end
  end

  defp generate_event_name(computer, computer_name, event_name) do
    if event_exists?(computer.events, event_name) do
      "#{computer_name}_#{event_name}"
    else
      nil
    end
  end

  defp event_exists?(events, event_name) do
    Enum.any?(events, fn event -> event.name == event_name end)
  end

  @doc """
  Compile-time safe version of event_names/2.

  Validates that the module and computer exist at compile time and returns
  event names. Will cause compilation failure if the computer doesn't exist.

  ## Examples

      # This will compile and return ["calculator_set_x", "calculator_reset"]
      AshComputer.Info.event_names!(MyLive, :calculator)

      # This will fail compilation
      AshComputer.Info.event_names!(MyLive, :nonexistent)

  """
  defmacro event_names!(module_ast, computer_name) do
    # Get the actual module atom from the AST
    module =
      case module_ast do
        {:__aliases__, _, parts} ->
          Module.concat(parts)

        module_atom when is_atom(module_atom) ->
          module_atom

        _ ->
          raise CompileError,
            description: "Invalid module reference",
            file: __CALLER__.file,
            line: __CALLER__.line
      end

    # Validate at compile time
    computer = computer(module, computer_name)

    unless computer do
      raise CompileError,
        description: "Computer #{inspect(computer_name)} not found in module #{inspect(module)}",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    event_names = Enum.map(computer.events, fn event -> "#{computer_name}_#{event.name}" end)

    quote do
      unquote(event_names)
    end
  end

  @doc """
  Compile-time safe version of event_name/3.

  Validates that the module, computer, and event exist at compile time.
  Will cause compilation failure if any don't exist.

  ## Examples

      # This will compile and return "calculator_set_x"
      AshComputer.Info.event_name!(MyLive, :calculator, :set_x)

      # This will fail compilation
      AshComputer.Info.event_name!(MyLive, :calculator, :nonexistent)

  """
  defmacro event_name!(module_ast, computer_name, event_name) do
    # Get the actual module atom from the AST
    module =
      case module_ast do
        {:__aliases__, _, parts} ->
          Module.concat(parts)

        module_atom when is_atom(module_atom) ->
          module_atom

        _ ->
          raise CompileError,
            description: "Invalid module reference",
            file: __CALLER__.file,
            line: __CALLER__.line
      end

    # Validate at compile time
    computer = computer(module, computer_name)

    unless computer do
      raise CompileError,
        description: "Computer #{inspect(computer_name)} not found in module #{inspect(module)}",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    event_exists = Enum.any?(computer.events, fn event -> event.name == event_name end)

    unless event_exists do
      available_events = Enum.map(computer.events, & &1.name)

      raise CompileError,
        description:
          "Event #{inspect(event_name)} not found in computer #{inspect(computer_name)} of module #{inspect(module)}. Available events: #{inspect(available_events)}",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    event_string = "#{computer_name}_#{event_name}"

    quote do
      unquote(event_string)
    end
  end
end
