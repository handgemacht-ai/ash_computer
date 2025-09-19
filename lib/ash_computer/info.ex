defmodule AshComputer.Info do
  @moduledoc """
  Runtime introspection functions for accessing computer information from modules.
  """

  @doc """
  Get all computers defined in a module.
  """
  def computers(module) do
    Spark.Dsl.Extension.get_entities(module, [:computers]) || []
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
    case Spark.Dsl.Extension.get_persisted(module, :ash_computer_default_name) do
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
end