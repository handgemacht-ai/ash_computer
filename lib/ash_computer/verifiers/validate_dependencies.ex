defmodule AshComputer.Verifiers.ValidateDependencies do
  @moduledoc """
  Validates that all val dependencies reference existing inputs or vals.
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    computers = Verifier.get_entities(dsl_state, [:computers])

    errors =
      computers
      |> Enum.flat_map(&validate_computer/1)

    case errors do
      [] -> :ok
      [error] -> {:error, error}
      errors -> {:error, errors}
    end
  end

  defp validate_computer(computer) do
    # Collect all available input and val names for this computer
    available_names =
      MapSet.new()
      |> add_input_names(computer.inputs)
      |> add_val_names(computer.vals)

    # Validate each val's dependencies and collect errors
    computer.vals
    |> Enum.flat_map(&validate_val_dependencies(&1, available_names, computer.name))
  end

  defp add_input_names(set, inputs) do
    Enum.reduce(inputs, set, fn input, acc ->
      MapSet.put(acc, input.name)
    end)
  end

  defp add_val_names(set, vals) do
    Enum.reduce(vals, set, fn val, acc ->
      MapSet.put(acc, val.name)
    end)
  end

  defp validate_val_dependencies(val, available_names, computer_name) do
    # depends_on is a list of atoms after parsing
    case val.depends_on do
      nil ->
        []

      dependencies when is_list(dependencies) ->
        validate_dependencies_list(dependencies, available_names, val, computer_name)

      _ ->
        []
    end
  end

  defp validate_dependencies_list(dependencies, available_names, val, computer_name) do
    dependencies
    |> Enum.flat_map(&validate_single_dependency(&1, available_names, val, computer_name))
  end

  defp validate_single_dependency(dep, available_names, val, computer_name) do
    if MapSet.member?(available_names, dep) do
      []
    else
      [
        Spark.Error.DslError.exception(
          path: [:computers, computer_name, :vals, val.name],
          message: "Val `#{val.name}` references non-existent input or val `#{dep}`"
        )
      ]
    end
  end
end
