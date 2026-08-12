defmodule AshComputer.Executor.Node do
  @moduledoc """
  A typed identity for a single node in the reactive graph.

  Replaces the bare `{computer_name, name}` 2-tuple that previously threaded
  through the executor. Carrying `kind` removes the need to re-derive whether
  a node is an input or a val at compute time (the `Map.has_key?(computer.inputs,
  node_name)` re-derivation tell).

  The value/error stores stay keyed by the 2-tuple returned from `key/1` so that
  their keys remain identical to the previous representation.
  """

  @type kind :: :input | :val
  @type t :: %__MODULE__{computer: atom(), name: atom(), kind: kind()}

  defstruct [:computer, :name, kind: :val]

  @doc "Construct a node. `kind` defaults to `:val`; pass `:input` for inputs."
  @spec new(atom(), atom(), kind()) :: t()
  def new(computer, name, kind \\ :val), do: %__MODULE__{computer: computer, name: name, kind: kind}

  @doc "The 2-tuple used to key the value/error stores. Identical to the prior key."
  @spec key(t()) :: {atom(), atom()}
  def key(%__MODULE__{computer: computer, name: name}), do: {computer, name}
end
