defmodule AshComputer.Verifiers.ValidateDependencies do
  @moduledoc """
  Validates that all val dependencies reference existing inputs or vals.
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    computers = Verifier.get_entities(dsl_state, [:computers])

    Enum.each(computers, &validate_computer/1)

    :ok
  end

  defp validate_computer(computer) do
    # Collect all available input and val names for this computer
    available_names =
      MapSet.new()
      |> add_input_names(computer.inputs)
      |> add_val_names(computer.vals)

    # Validate each val's dependencies
    Enum.each(computer.vals, fn val ->
      validate_val_dependencies(val, available_names, computer.name)
    end)
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
      nil -> :ok
      dependencies when is_list(dependencies) ->
        Enum.each(dependencies, fn dep ->
          unless MapSet.member?(available_names, dep) do
            raise Spark.Error.DslError,
              path: [:computers, computer_name, :vals, val.name],
              message: "Val `#{val.name}` references non-existent input or val `#{dep}`"
          end
        end)
      _ -> :ok
    end
  end
end