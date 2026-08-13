defmodule AshComputer.Executor.Error do
  @moduledoc """
  A typed compute failure.

  Replaces the bare `{:expected, reason}` / `{:blocked, blocked_dep}` 2-tuples
  that previously threaded through the executor's error store. Carrying `kind`
  removes the need to discriminate by first-atom magic, and `blocked_node` keeps
  the blocked dependency as a typed `Node.t()` instead of a positional
  `{computer, name}` tuple (which itself wrapped another positional node-tuple).

  The value/error stores continue to hold `Error` structs internally; the public
  error boundary (`current_errors/2`, `pending_errors/2`) converts back to the
  legacy 2-tuple via `to_tuple/1` so existing consumers and assertions are
  unchanged.
  """

  alias AshComputer.Executor.Node

  @type kind :: :expected | :blocked
  @type t :: %__MODULE__{
          kind: kind(),
          reason: term() | nil,
          blocked_node: Node.t() | nil
        }

  defstruct [:kind, :reason, :blocked_node]

  @spec expected(term()) :: t()
  def expected(reason), do: %__MODULE__{kind: :expected, reason: reason}

  @spec blocked(Node.t()) :: t()
  def blocked(%Node{} = node), do: %__MODULE__{kind: :blocked, blocked_node: node}

  @doc """
  The legacy 2-tuple representation used at the public error boundary
  (`current_errors/2`, `pending_errors/2`).

  Identical to the prior `{:expected, reason}` / `{:blocked, {computer, name}}`
  shape so existing consumers and assertions are unchanged.
  """
  @spec to_tuple(t()) :: {:expected, term()} | {:blocked, {atom(), atom()}}
  def to_tuple(%__MODULE__{kind: :expected, reason: reason}), do: {:expected, reason}
  def to_tuple(%__MODULE__{kind: :blocked, blocked_node: %Node{} = node}), do: {:blocked, Node.key(node)}
end
