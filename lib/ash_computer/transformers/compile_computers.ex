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
      {updated_computers, updated_dsl_state} =
        Enum.map_reduce(computers, dsl_state, fn computer, acc_dsl_state ->
          generate_computer_functions(computer, acc_dsl_state)
        end)

      # Update DSL state with computers containing function names instead of AST
      updated_dsl_state =
        Enum.reduce(updated_computers, updated_dsl_state, fn computer, acc_state ->
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

  defp generate_computer_functions(computer, dsl_state) do
    # Generate functions for all vals in this computer
    {updated_vals, updated_dsl_state} =
      Enum.map_reduce(computer.vals, dsl_state, fn val, acc_dsl_state ->
        generate_val_function(val, computer.name, acc_dsl_state)
      end)

    {%{computer | vals: updated_vals}, updated_dsl_state}
  end

  defp generate_val_function(val, computer_name, dsl_state) do
    # Generate a unique function name
    func_name = :"__compute_#{computer_name}_#{val.name}__"

    # Parse dependencies from AST if not already done
    val_with_deps = ensure_dependencies_parsed(val)

    # Extract function args and body from the quoted AST
    case val_with_deps.compute do
      {:fn, _meta, [{:->, _arrow_meta, [args, body]}]} ->
        # Use Spark's recommended eval pattern to inject the function
        # This preserves module context (aliases, imports) and avoids deprecation
        updated_dsl_state = Transformer.eval(
          dsl_state,
          [func_name: func_name, args: args, body: body],
          quote do
            def unquote(func_name)(unquote_splicing(args)) do
              unquote(body)
            end
          end
        )

        # Store the function name instead of the AST
        {%{val_with_deps | compute: func_name}, updated_dsl_state}

      _ ->
        # If it's not a function AST, keep it as is (shouldn't happen)
        {val_with_deps, dsl_state}
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

end
