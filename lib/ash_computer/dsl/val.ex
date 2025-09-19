defmodule AshComputer.Dsl.Val do
  @moduledoc false

  @type name :: String.t() | atom()

  @type t :: %__MODULE__{
          __identifier__: name(),
          name: name(),
          type: atom() | nil,
          description: String.t() | nil,
          compute: Macro.t(),
          depends_on: [name()] | nil
        }

  defstruct [:__identifier__, :name, :type, :description, :compute, :depends_on]
end
