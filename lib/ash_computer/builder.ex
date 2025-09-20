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
      # Parse dependencies from the quoted AST if not explicitly set
      dependencies = get_dependencies(val)

      # Compile the quoted AST into a function
      compute_fun = compile_compute_function(val.compute)

      val_struct =
        Computer.Val.new(
          normalize_name(val.name),
          val.description,
          val.type,
          compute_fun
        )

      Computer.add_val(acc, val_struct, dependencies)
    end)
  end

  defp get_dependencies(%Val{depends_on: depends_on}) when is_list(depends_on) do
    Enum.map(depends_on, &normalize_name/1)
  end

  defp get_dependencies(%Val{depends_on: nil, compute: compute_ast}) do
    # Parse dependencies from the quoted AST
    AshComputer.AstParser.parse_quoted_function(compute_ast)
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

  defp compile_compute_function(quoted_ast) do
    # Convert quoted AST to a function
    {fun, _binding} = Code.eval_quoted(quoted_ast)
    fun
  end
end