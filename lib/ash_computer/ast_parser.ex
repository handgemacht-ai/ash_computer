defmodule AshComputer.AstParser do
  @moduledoc """
  Parses function AST to extract dependencies from compute functions.

  This module analyzes the pattern matching in compute functions to automatically
  determine which inputs and vals a compute function depends on.
  """

  @doc """
  Parses a quoted function expression to extract dependencies.

  This is the main function used by the builder at compile time.

  ## Examples

      iex> ast = quote do: fn %{a: a, b: b} -> a + b end
      iex> AshComputer.AstParser.parse_quoted_function(ast)
      [:a, :b]

      iex> ast = quote do: fn %{x: x} -> x * 2 end
      iex> AshComputer.AstParser.parse_quoted_function(ast)
      [:x]
  """
  def parse_quoted_function({:fn, _, clauses}) when is_list(clauses) do
    # Extract dependencies from all clauses and combine them
    clauses
    |> Enum.flat_map(&parse_function_clause/1)
    |> Enum.uniq()
  end

  def parse_quoted_function(_), do: []

  # Parse a single function clause
  defp parse_function_clause({:->, _meta, [args, _body]}) do
    # We're interested in the first argument's pattern
    case args do
      [first_arg | _] -> extract_dependencies_from_pattern(first_arg)
      _ -> []
    end
  end

  defp parse_function_clause(_), do: []

  # Extract dependencies from various pattern types
  defp extract_dependencies_from_pattern({:%{}, _meta, pairs}) when is_list(pairs) do
    # Map pattern matching with atom keys
    Enum.flat_map(pairs, fn
      {key, _var} when is_atom(key) -> [key]
      # Support legacy string keys if needed
      {key, _var} when is_binary(key) -> [String.to_atom(key)]
      _ -> []
    end)
  end

  defp extract_dependencies_from_pattern({:%, _meta, [_struct, {:%{}, _, pairs}]})
       when is_list(pairs) do
    # Struct pattern matching (if values come from a struct)
    Enum.flat_map(pairs, fn
      {key, _var} when is_atom(key) -> [key]
      _ -> []
    end)
  end

  defp extract_dependencies_from_pattern(_), do: []
end
