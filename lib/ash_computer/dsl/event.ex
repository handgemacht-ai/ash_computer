defmodule AshComputer.Dsl.Event do
  @moduledoc false

  @type name :: atom()
  @type handler :: function() | nil

  @type t :: %__MODULE__{
          __identifier__: name(),
          __spark_metadata__: term(),
          name: name(),
          handle: handler(),
          run: function() | nil,
          handle_result: function() | nil,
          description: String.t() | nil
        }

  defstruct [
    :__identifier__,
    :__spark_metadata__,
    :name,
    :handle,
    :run,
    :handle_result,
    :description
  ]
end
