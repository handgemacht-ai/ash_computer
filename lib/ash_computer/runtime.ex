defmodule AshComputer.Runtime do
  @moduledoc false

  defstruct name: nil,
            inputs: %{},
            vals: %{},
            dependencies: %{},
            values: %{},
            errors: %{},
            pending: nil

  @doc false
  def new(name) do
    %__MODULE__{
      name: name
    }
  end

  @doc "Return the committed values for this computer."
  def current_values(%__MODULE__{values: values}), do: values

  @doc "Return the committed errors for this computer."
  def current_errors(%__MODULE__{errors: errors}), do: errors

  @doc "Return the tentative values from the most recent failed attempt."
  def pending_values(%__MODULE__{pending: %{values: values}}), do: values
  def pending_values(_), do: %{}

  @doc "Return the tentative errors from the most recent failed attempt."
  def pending_errors(%__MODULE__{pending: %{errors: errors}}), do: errors
  def pending_errors(_), do: %{}

  @doc "Returns true when the last update attempt succeeded."
  def success?(%__MODULE__{pending: nil}), do: true
  def success?(_), do: false

  @doc "Clear any saved tentative state."
  def clear_pending(%__MODULE__{} = computer) do
    %{computer | pending: nil}
  end

  def add_input(%__MODULE__{} = computer, name, initial, _description, _options) do
    computer
    |> put_in([Access.key(:inputs), name], initial)
    |> update_in([Access.key(:values)], &Map.put(&1, name, initial))
    |> update_in([Access.key(:errors)], &Map.delete(&1, name))
  end

  def add_val(%__MODULE__{} = computer, name, _description, compute_fn, dependencies) do
    computer =
      computer
      |> put_in([Access.key(:vals), name], compute_fn)
      |> put_in([Access.key(:dependencies), name], dependencies)

    {status, values, errors} =
      compute_value_snapshot(computer, name, computer.values, computer.errors)

    case status do
      :ok ->
        %{computer | values: values, errors: errors}

      :error ->
        reason = Map.get(errors, name, :unknown_failure)

        raise ArgumentError,
              "Failed to compute initial value for #{inspect(name)}: #{inspect(reason)}"
    end
  end

  def handle_input(%__MODULE__{} = computer, input_name, value) do
    working_values = Map.put(computer.values, input_name, value)
    working_errors = Map.delete(computer.errors, input_name)

    case recompute_dependents(computer, input_name, working_values, working_errors) do
      {:ok, values, errors} ->
        %{computer | values: values, errors: errors, pending: nil}

      {:error, values, errors} ->
        %{computer | pending: %{values: values, errors: errors}}
    end
  end


  defp recompute_dependents(computer, changed_key, values, errors) do
    {status, values, errors, _visited} =
      do_recompute_dependents(computer, changed_key, values, errors, MapSet.new())

    {status, values, errors}
  end

  defp do_recompute_dependents(computer, changed_key, values, errors, visited) do
    dependents = dependents_of(computer, changed_key)

    Enum.reduce(dependents, {:ok, values, errors, visited}, fn val_name,
                                                               {status, values, errors, visited} ->
      if MapSet.member?(visited, val_name) do
        {status, values, errors, visited}
      else
        visited = MapSet.put(visited, val_name)

        {val_status, values, errors} =
          compute_value_snapshot(computer, val_name, values, errors)

        {child_status, values, errors, visited} =
          do_recompute_dependents(computer, val_name, values, errors, visited)

        combined_status =
          status
          |> combine_status(val_status)
          |> combine_status(child_status)

        {combined_status, values, errors, visited}
      end
    end)
  end

  defp dependents_of(computer, key) do
    for {val, deps} <- computer.dependencies, key in deps, do: val
  end

  defp combine_status(:error, _other), do: :error
  defp combine_status(_other, :error), do: :error
  defp combine_status(_left, _right), do: :ok

  defp compute_value_snapshot(computer, val_name, values, errors) do
    deps = Map.get(computer.dependencies, val_name, [])

    case Enum.find(deps, &Map.has_key?(errors, &1)) do
      nil ->
        compute_fn = computer.vals[val_name]
        args = Map.take(values, deps)
        result = compute_fn.(args)

        case normalize_result(result) do
          {:ok, value} ->
            values = Map.put(values, val_name, value)
            errors = Map.delete(errors, val_name)
            {:ok, values, errors}

          {:error, reason} ->
            errors = Map.put(errors, val_name, {:expected, reason})
            {:error, values, errors}
        end

      blocked_dep ->
        errors = Map.put(errors, val_name, {:blocked, blocked_dep})
        {:error, values, errors}
    end
  end

  defp normalize_result({:ok, value}), do: {:ok, value}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result(value), do: {:ok, value}
end
