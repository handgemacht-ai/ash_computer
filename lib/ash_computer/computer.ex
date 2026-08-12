defmodule AshComputer.Computer do
  @moduledoc """
  The compiled form of a computer: inputs, vals (compute functions), and
  dependencies. Returned by `AshComputer.Builder` and stored in the executor
  under `executor.computers[name]`.

  Replaces the bare `%{inputs: _, vals: _, dependencies: _}` map. Field access
  (`computer.inputs`, etc.) and the `%{inputs: _, ...} = computer` pattern
  match behave exactly as on the prior map because structs are maps.
  """

  @type t :: %__MODULE__{
          inputs: %{atom() => term()},
          vals: %{atom() => (map() -> term())},
          dependencies: %{atom() => [atom()]}
        }

  defstruct [:inputs, :vals, :dependencies]

  @doc "Construct a compiled computer from its three maps."
  @spec new(map(), map(), map()) :: t()
  def new(inputs, vals, dependencies) do
    %__MODULE__{inputs: inputs, vals: vals, dependencies: dependencies}
  end
end
