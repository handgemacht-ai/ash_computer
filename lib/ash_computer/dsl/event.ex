defmodule AshComputer.Dsl.Event do
  @moduledoc false

  @type name :: atom()
  @type handler :: function()

  @type t :: %__MODULE__{
          __identifier__: name(),
          name: name(),
          handle: handler(),
          description: String.t() | nil
        }

  defstruct [:__identifier__, :name, :handle, :description]
end
