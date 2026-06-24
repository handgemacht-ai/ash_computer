defmodule AshComputer.Dsl.Input do
  @moduledoc false

  @type name :: String.t() | atom()

  @type t :: %__MODULE__{
          __identifier__: name(),
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil,
          name: name(),
          description: String.t() | nil,
          initial: any(),
          options: keyword() | map() | nil
        }

  defstruct [:__identifier__, :__spark_metadata__, :name, :description, :initial, :options]
end
