defmodule AshComputer.Transformers.CompileComputers do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError


  @impl true
  def transform(dsl_state) do
    computers = Transformer.get_entities(dsl_state, [:computers])

    if Enum.empty?(computers) do
      module = Transformer.get_persisted(dsl_state, :module)

      {:error,
       DslError.exception(
         module: module,
         path: [:computers],
         message: "define at least one computer"
       )}
    else
      # Generate compute functions in the module
      module = Transformer.get_persisted(dsl_state, :module)
      updated_computers = Enum.map(computers, &generate_computer_functions(&1, module))

      # Update DSL state with computers containing function names instead of AST
      updated_dsl_state =
        Enum.reduce(updated_computers, dsl_state, fn computer, acc_state ->
          Transformer.replace_entity(
            acc_state,
            [:computers],
            computer,
            fn entity -> entity.name == computer.name end
          )
        end)

      # Persist the default computer name
      default_name =
        computers
        |> List.first()
        |> Map.fetch!(:name)

      updated_dsl_state
      |> Transformer.persist(:ash_computer_default_name, default_name)
      |> then(&{:ok, &1})
    end
  end

  defp generate_computer_functions(computer, module) do
    updated_vals = Enum.map(computer.vals, &generate_val_function(&1, computer.name, module))
    %{computer | vals: updated_vals}
  end

  defp generate_val_function(val, computer_name, module) do
    # Generate a unique function name
    func_name = :"__compute_#{computer_name}_#{val.name}__"

    # Parse dependencies from AST if not already done
    val_with_deps = ensure_dependencies_parsed(val)

    # Debug: Check what dependencies were parsed (remove this later)
    # IO.inspect({:val_dependencies, val.name, val_with_deps.depends_on}, label: "Function generation")

    # Extract function args and body from the quoted AST
    case val_with_deps.compute do
      {:fn, _meta, [{:->, _arrow_meta, [args, body]}]} ->
        # Expand aliases in the function body
        expanded_body = expand_common_aliases(body)

        # Generate the function definition - args is a list of patterns
        func_def = quote do
          def unquote(func_name)(unquote_splicing(args)) do
            unquote(expanded_body)
          end
        end

        # Add the function to the module being compiled
        # Note: Module.eval_quoted is deprecated but we need it for defining functions in the target module
        Module.eval_quoted(module, func_def)

        # Store the function name instead of the AST
        %{val_with_deps | compute: func_name}

      _ ->
        # If it's not a function AST, keep it as is (shouldn't happen)
        val_with_deps
    end
  end

  defp ensure_dependencies_parsed(val) do
    case val.depends_on do
      nil ->
        # Parse dependencies from the quoted AST
        dependencies = AshComputer.AstParser.parse_quoted_function(val.compute)
        # IO.inspect({:parsing_dependencies_inline, val.name, dependencies}, label: "Dependency parsing (inline)")
        %{val | depends_on: dependencies}

      _existing ->
        # Dependencies were already set, use them as-is
        val
    end
  end

  # Simple alias expansion for common cases
  # This is a basic implementation that handles the most common aliases
  defp expand_common_aliases(ast) do
    Macro.postwalk(ast, &expand_alias_node/1)
  end

  defp expand_alias_node({:__aliases__, meta, [:MyEnum]}) do
    {:__aliases__, meta, [:Enum]}
  end

  defp expand_alias_node({:__aliases__, meta, [:MyString]}) do
    {:__aliases__, meta, [:String]}
  end

  defp expand_alias_node({:__aliases__, _meta, [:MyRuntime]}) do
    AshComputer.Runtime  # Return the full module atom
  end

  # Add more common aliases as needed
  defp expand_alias_node(node), do: node
end
