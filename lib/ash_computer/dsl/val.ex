defmodule AshComputer.Dsl.Val do
  @moduledoc false

  @type name :: String.t() | atom()

  @type t :: %__MODULE__{
          __identifier__: name(),
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil,
          name: name(),
          description: String.t() | nil,
          compute: Macro.t(),
          depends_on: [name()] | nil
        }

  defstruct [:__identifier__, :__spark_metadata__, :name, :description, :compute, :depends_on]
end
