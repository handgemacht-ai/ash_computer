defmodule AshComputer.Builder do
  @moduledoc false

  alias AshComputer.Dsl.Computer, as: ComputerDefinition
  alias AshComputer.Dsl.Input
  alias AshComputer.Dsl.Val
  alias AshComputer.Runtime

  def build_builder(%ComputerDefinition{} = definition, module) do
    fn ->
      build_computer(definition, module)
    end
  end

  defp build_computer(%ComputerDefinition{} = definition, module) do
    display_name = definition.description || default_display_name(definition.name)

    Runtime.new(display_name)
    |> add_inputs(definition.inputs)
    |> add_vals(definition.vals, module)
  end

  defp add_inputs(computer, inputs) do
    Enum.reduce(inputs, computer, fn %Input{} = input, acc ->
      Runtime.add_input(
        acc,
        input.name,
        input.initial,
        input.description,
        Map.get(input, :options, [])
      )
    end)
  end

  defp add_vals(computer, vals, module) do
    Enum.reduce(vals, computer, fn %Val{} = val, acc ->
      # Dependencies are parsed at compile time by the transformer
      dependencies = get_dependencies(val)

      # Create function reference (val.compute is now a function name)
      compute_fun = compile_compute_function(val.compute, module)

      Runtime.add_val(
        acc,
        val.name,
        val.description,
        compute_fun,
        dependencies
      )
    end)
  end

  defp get_dependencies(%Val{depends_on: depends_on}) do
    # Always use compile-time parsed dependencies
    depends_on || []
  end

  # No longer needed - we keep atoms as atoms
  # defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  # defp normalize_name(name) when is_binary(name), do: name
  # defp normalize_name(name), do: to_string(name)

  defp default_display_name(nil), do: ""

  defp default_display_name(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp default_display_name(name) when is_binary(name), do: name

  defp compile_compute_function(func_name, module) when is_atom(func_name) do
    # Create a function reference to the generated function in the module
    fn values ->
      apply(module, func_name, [values])
    end
  end

  defp compile_compute_function(quoted_ast, _module) do
    # Fallback for any remaining AST (backwards compatibility)
    {fun, _binding} = Code.eval_quoted(quoted_ast)
    fun
  end
end
