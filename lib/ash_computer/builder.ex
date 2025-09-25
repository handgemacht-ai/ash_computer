defmodule AshComputer.Builder do
  @moduledoc false

  alias AshComputer.Dsl.Computer, as: ComputerDefinition
  alias AshComputer.Dsl.Input
  alias AshComputer.Dsl.Val

  def build_builder(%ComputerDefinition{} = definition, module) do
    fn ->
      build_computer_spec(definition, module)
    end
  end

  defp build_computer_spec(%ComputerDefinition{} = definition, module) do
    inputs = build_inputs(definition.inputs)
    {vals, dependencies} = build_vals(definition.vals, module)

    %{
      inputs: inputs,
      vals: vals,
      dependencies: dependencies
    }
  end

  defp build_inputs(inputs) do
    for %Input{} = input <- inputs, into: %{} do
      {input.name, input.initial}
    end
  end

  defp build_vals(vals, module) do
    vals_map =
      for %Val{} = val <- vals, into: %{} do
        compute_fun = compile_compute_function(val.compute, module)
        {val.name, compute_fun}
      end

    dependencies_map =
      for %Val{} = val <- vals, into: %{} do
        dependencies = get_dependencies(val)
        {val.name, dependencies}
      end

    {vals_map, dependencies_map}
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
