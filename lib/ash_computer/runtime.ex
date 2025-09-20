defmodule AshComputer.Runtime do
  @moduledoc false

  defstruct ~w(name inputs vals values dependencies stateful?)a

  def new(name) do
    %__MODULE__{
      name: name,
      inputs: %{},
      vals: %{},
      values: %{},
      dependencies: %{},
      stateful?: false
    }
  end

  def new_stateful(name) do
    %__MODULE__{
      name: name,
      inputs: %{},
      vals: %{},
      values: %{},
      dependencies: %{},
      stateful?: true
    }
  end

  def add_input(computer, name, initial, _description, _options) do
    computer
    |> put_in([Access.key(:inputs), name], initial)
    |> put_in([Access.key(:values), name], initial)
  end

  def add_val(computer, name, _description, compute_fn, dependencies) do
    computer
    |> put_in([Access.key(:vals), name], compute_fn)
    |> put_in([Access.key(:dependencies), name], dependencies)
    |> compute_val(name)
  end

  def handle_input(computer, input_name, value) do
    computer
    |> put_in([Access.key(:values), input_name], value)
    |> recompute_dependents(input_name)
  end

  def make_instance(computer, options \\ []) do
    GenServer.start_link(AshComputer.Runtime.Instance, computer, options)
  end

  defp compute_val(computer, val_name) do
    compute_fn = computer.vals[val_name]
    deps = computer.dependencies[val_name] || []

    args = Map.take(computer.values, deps)

    result =
      if computer.stateful? and :erlang.fun_info(compute_fn)[:arity] == 2 do
        compute_fn.(args, computer.values)
      else
        compute_fn.(args)
      end

    put_in(computer, [Access.key(:values), val_name], result)
  end

  defp recompute_dependents(computer, changed_key) do
    # Find all vals that depend on this key
    dependents =
      computer.dependencies
      |> Enum.filter(fn {_val, deps} -> changed_key in deps end)
      |> Enum.map(fn {val, _} -> val end)

    # Recompute each dependent val
    Enum.reduce(dependents, computer, fn val_name, acc ->
      acc
      |> compute_val(val_name)
      |> recompute_dependents(val_name)
    end)
  end
end
