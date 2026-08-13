defmodule AshComputer.Result do
  @moduledoc """
  A typed compute-fn return value.

  Replaces the bare `{:ok, value}` / `{:error, reason}` 2-tuples that
  `normalize_result/1` previously produced and the executor pattern-matched
  on. Carrying `kind` removes the need to discriminate by first-atom magic at
  the call site, and `value` / `reason` name the positional payload.

  The compute-fn contract is unchanged at the boundary: a user compute fn may
  still return a bare value, `{:ok, value}`, or `{:error, reason}`. `normalize/1`
  accepts exactly those three legacy shapes and yields a `Result.t()`, so
  existing user compute fns, their assertions, and the public error boundary
  (`current_errors/2`, `pending_errors/2`) are unaffected.
  """

  @type kind :: :ok | :error
  @type t :: %__MODULE__{kind: kind(), value: term() | nil, reason: term() | nil}

  defstruct [:kind, :value, :reason]

  @spec ok(term()) :: t()
  def ok(value), do: %__MODULE__{kind: :ok, value: value}

  @spec error(term()) :: t()
  def error(reason), do: %__MODULE__{kind: :error, reason: reason}

  @doc """
  Normalize a compute-fn return into a `Result.t()`.

  Accepts the legacy boundary shapes — a bare value, `{:ok, value}`, or
  `{:error, reason}` — identical to the prior `normalize_result/1` acceptance,
  so user compute fns and their assertions are unchanged.

  Note that, as before, a return of `{:ok, _}` or `{:error, _}` is interpreted as
  an explicit ok/error result rather than as a bare value that happens to be a
  2-tuple.
  """
  @spec normalize(term()) :: t()
  def normalize({:ok, value}), do: ok(value)
  def normalize({:error, reason}), do: error(reason)
  def normalize(value), do: ok(value)

  @spec ok?(t()) :: boolean()
  def ok?(%__MODULE__{kind: :ok}), do: true
  def ok?(%__MODULE__{}), do: false

  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{kind: :error}), do: true
  def error?(%__MODULE__{}), do: false
end
