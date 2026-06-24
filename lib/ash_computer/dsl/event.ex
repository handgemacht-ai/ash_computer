defmodule AshComputer.Dsl.Event do
  @moduledoc false

  @type name :: atom()
  @type handler :: function()

  @type t :: %__MODULE__{
          __identifier__: name(),
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil,
          name: name(),
          handle: handler(),
          description: String.t() | nil
        }

  defstruct [:__identifier__, :__spark_metadata__, :name, :handle, :description]
end
