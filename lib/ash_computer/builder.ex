defmodule AshComputer.Builder do
  @moduledoc false

  alias AshComputer.Dsl.Computer, as: ComputerDefinition
  alias AshComputer.Dsl.Input
  alias AshComputer.Dsl.Val

  def build_builder(%ComputerDefinition{} = definition, _module) do
    fn ->
      build_computer(definition)
    end
  end

  defp build_computer(%ComputerDefinition{stateful?: true} = definition) do
    display_name = definition.description || default_display_name(definition.name)

    Computer.new_stateful(display_name)
    |> add_inputs(definition.inputs)
    |> add_vals(definition.vals)
  end

  defp build_computer(%ComputerDefinition{} = definition) do
    display_name = definition.description || default_display_name(definition.name)

    Computer.new(display_name)
    |> add_inputs(definition.inputs)
    |> add_vals(definition.vals)
  end

  defp add_inputs(computer, inputs) do
    Enum.reduce(inputs, computer, fn %Input{} = input, acc ->
      input_struct =
        Computer.Input.new(
          normalize_name(input.name),
          input.description,
          input.type,
          input.initial,
          Map.get(input, :options, [])
        )

      Computer.add_input(acc, input_struct)
    end)
  end

  defp add_vals(computer, vals) do
    Enum.reduce(vals, computer, fn %Val{} = val, acc ->
      val_struct =
        Computer.Val.new(
          normalize_name(val.name),
          val.description,
          val.type,
          val.compute
        )

      dependencies = get_dependencies(val)
      Computer.add_val(acc, val_struct, dependencies)
    end)
  end

  defp get_dependencies(%Val{depends_on: depends_on}) when is_list(depends_on) do
    Enum.map(depends_on, &normalize_name/1)
  end

  defp get_dependencies(%Val{depends_on: nil, compute: compute}) do
    infer_dependencies(compute) || []
  end

  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name) when is_binary(name), do: name
  defp normalize_name(name), do: to_string(name)

  defp default_display_name(nil), do: ""

  defp default_display_name(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp default_display_name(name) when is_binary(name), do: name

  defp infer_dependencies(compute) when is_function(compute) do
    # Try to infer dependencies from function info
    case Function.info(compute, :env) do
      [] ->
        # No captured variables, try to check arity and assume pattern matching
        case Function.info(compute, :arity) do
          1 -> []  # Assume it pattern matches on arguments
          2 -> []  # Assume it pattern matches on arguments
          _ -> []
        end

      _ ->
        # Has captured variables, can't easily infer
        []
    end
  end

  defp infer_dependencies(_), do: []
end