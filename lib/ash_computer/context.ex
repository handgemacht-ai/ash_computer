defmodule AshComputer.Context do
  @moduledoc """
  Who an effect runs for.

  A context carries the `actor`, the `tenant` and any `extra` data the host
  application wants to hand to effects. It is passed to an event's `run`
  function and is never stored in the executor.
  """

  @type t :: %__MODULE__{actor: term(), tenant: term(), extra: map()}

  defstruct actor: nil, tenant: nil, extra: %{}

  @doc """
  Builds a context from a keyword list or map with `:actor`, `:tenant` and `:extra`.

  Raises `ArgumentError` for any other key.
  """
  @spec new(keyword() | map() | t()) :: t()
  def new(%__MODULE__{} = context), do: context

  def new(fields) when is_list(fields) or is_map(fields) do
    fields = Map.new(fields)

    case Map.keys(fields) -- [:actor, :tenant, :extra] do
      [] ->
        struct!(__MODULE__, fields)

      unknown ->
        raise ArgumentError,
              "Unknown context keys #{inspect(unknown)}. Allowed keys: [:actor, :tenant, :extra]"
    end
  end

  def new(other) do
    raise ArgumentError,
          "Context must be built from a keyword list, a map or an %AshComputer.Context{}, got: #{inspect(other)}"
  end
end
