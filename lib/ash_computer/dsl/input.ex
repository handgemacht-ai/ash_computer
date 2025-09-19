defmodule AshComputer.Dsl.Input do
  @moduledoc false

  @type name :: String.t() | atom()

  @type t :: %__MODULE__{
          __identifier__: name(),
          name: name(),
          type: atom(),
          description: String.t() | nil,
          initial: any(),
          options: keyword() | map() | nil
        }

  defstruct [:__identifier__, :name, :type, :description, :initial, :options]
end
