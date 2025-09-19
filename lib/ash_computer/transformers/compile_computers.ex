defmodule AshComputer.Transformers.CompileComputers do
  @moduledoc false

  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    computers = Spark.Dsl.Transformer.get_entities(dsl_state, [:computers])

    if Enum.empty?(computers) do
      module = Spark.Dsl.Transformer.get_persisted(dsl_state, :module)

      {:error,
       Spark.Error.DslError.exception(
         module: module,
         path: [:computers],
         message: "define at least one computer"
       )}
    else
      # Only persist the default computer name
      default_name =
        computers
        |> List.first()
        |> Map.fetch!(:name)

      dsl_state
      |> Spark.Dsl.Transformer.persist(:ash_computer_default_name, default_name)
      |> then(&{:ok, &1})
    end
  end
end