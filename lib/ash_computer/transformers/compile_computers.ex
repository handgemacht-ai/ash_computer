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
      # Only persist the default computer name
      default_name =
        computers
        |> List.first()
        |> Map.fetch!(:name)

      dsl_state
      |> Transformer.persist(:ash_computer_default_name, default_name)
      |> then(&{:ok, &1})
    end
  end
end
