defmodule AshComputer.Dsl.Input do
  @moduledoc false

  @type name :: String.t() | atom()

  @type t :: %__MODULE__{
          __identifier__: name(),
          name: name(),
          description: String.t() | nil,
          initial: any(),
          options: keyword() | map() | nil
        }

  defstruct [:__identifier__, :name, :description, :initial, :options]
end
