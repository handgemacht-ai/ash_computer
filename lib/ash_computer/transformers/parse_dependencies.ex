defmodule AshComputer.Transformers.ParseDependencies do
  @moduledoc """
  Transformer that parses compute functions at compile time to extract dependencies.

  This transformer analyzes the quoted AST of compute functions and populates
  the depends_on field of vals, making dependencies available at compile time.
  """

  use Spark.Dsl.Transformer

  alias AshComputer.AstParser
  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    computers = Transformer.get_entities(dsl_state, [:computers])

    # Process each computer and update its vals with parsed dependencies
    updated_dsl_state =
      Enum.reduce(computers, dsl_state, fn computer, acc_state ->
        update_computer_vals(acc_state, computer)
      end)

    {:ok, updated_dsl_state}
  end

  @impl true
  def before?(AshComputer.Transformers.CompileComputers), do: true
  def before?(_), do: false

  @impl true
  def after?(_), do: true

  defp update_computer_vals(dsl_state, computer) do
    updated_vals =
      Enum.map(computer.vals, fn val ->
        parse_val_dependencies(val)
      end)

    # Create updated computer with parsed dependencies
    updated_computer = %{computer | vals: updated_vals}

    # Replace the specific computer entity in the DSL state
    Transformer.replace_entity(
      dsl_state,
      [:computers],
      updated_computer,
      fn entity -> entity.name == computer.name end
    )
  end

  defp parse_val_dependencies(val) do
    case val.depends_on do
      nil ->
        # Parse dependencies from the quoted AST
        dependencies = AstParser.parse_quoted_function(val.compute)
        %{val | depends_on: dependencies}

      _existing ->
        # Dependencies were explicitly set, use them as-is
        val
    end
  end
end
