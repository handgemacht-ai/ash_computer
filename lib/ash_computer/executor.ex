defmodule AshComputer.Executor do
  @moduledoc false

  defstruct computers: %{},
            connections: [],
            values: %{},
            errors: %{},
            pending: nil,
            frame: nil,
            global_graph: %{}

  defmodule Frame do
    @moduledoc false
    defstruct pending_inputs: %{}, started: false
  end

  def new do
    %__MODULE__{}
  end

  def add_computer(%__MODULE__{} = executor, module, computer_name) do
    spec = AshComputer.computer_spec(module, computer_name)
    %{inputs: inputs, vals: vals, dependencies: dependencies} = spec

    computer = %{
      inputs: inputs,
      vals: vals,
      dependencies: dependencies
    }

    %{executor | computers: Map.put(executor.computers, computer_name, computer)}
  end

  def connect(%__MODULE__{} = executor, opts) do
    from = Keyword.fetch!(opts, :from)
    to = Keyword.fetch!(opts, :to)

    connection = %{source: from, target: to}
    %{executor | connections: [connection | executor.connections]}
  end

  def initialize(%__MODULE__{} = executor) do
    graph = build_global_graph(executor)
    sorted_nodes = topological_sort(graph)

    {values, errors} =
      Enum.reduce(sorted_nodes, {%{}, %{}}, fn node, {values, errors} ->
        compute_node(executor, node, values, errors)
      end)

    case map_size(errors) do
      0 ->
        %{executor | values: values, errors: errors, global_graph: graph, pending: nil}

      _ ->
        failed_nodes = Map.keys(errors) |> Enum.map(&inspect/1) |> Enum.join(", ")

        raise ArgumentError,
              "Failed to initialize executor. The following nodes have errors: #{failed_nodes}"
    end
  end

  def start_frame(%__MODULE__{frame: nil} = executor) do
    %{executor | frame: %Frame{}}
  end

  def start_frame(%__MODULE__{}) do
    raise ArgumentError, "Frame already started. Commit or rollback the current frame first."
  end

  def set_input(%__MODULE__{frame: %Frame{} = frame} = executor, computer_name, input_name, value) do
    key = {computer_name, input_name}
    pending_inputs = Map.put(frame.pending_inputs, key, value)
    %{executor | frame: %{frame | pending_inputs: pending_inputs}}
  end

  def set_input(%__MODULE__{frame: nil}, _, _, _) do
    raise ArgumentError, "No frame started. Call start_frame/1 first."
  end

  def commit_frame(%__MODULE__{frame: %Frame{pending_inputs: pending_inputs}} = executor) do
    working_values =
      Enum.reduce(pending_inputs, executor.values, fn {key, value}, values ->
        Map.put(values, key, value)
      end)

    working_errors =
      Enum.reduce(pending_inputs, executor.errors, fn {key, _value}, errors ->
        Map.delete(errors, key)
      end)

    affected_nodes = find_affected_nodes(executor, Map.keys(pending_inputs))
    sorted_affected = topological_sort_subgraph(executor.global_graph, affected_nodes)

    {final_values, final_errors} =
      Enum.reduce(sorted_affected, {working_values, working_errors}, fn node, {values, errors} ->
        compute_node(executor, node, values, errors)
      end)

    case Enum.any?(sorted_affected, fn node -> Map.has_key?(final_errors, node) end) do
      false ->
        %{executor | values: final_values, errors: final_errors, frame: nil, pending: nil}

      true ->
        %{executor | frame: nil, pending: %{values: final_values, errors: final_errors}}
    end
  end

  def commit_frame(%__MODULE__{frame: nil}) do
    raise ArgumentError, "No frame to commit. Call start_frame/1 first."
  end

  def current_values(%__MODULE__{} = executor, computer_name) do
    for {{^computer_name, key}, value} <- executor.values, into: %{} do
      {key, value}
    end
  end

  def current_errors(%__MODULE__{} = executor, computer_name) do
    for {{^computer_name, key}, error} <- executor.errors, into: %{} do
      {key, error}
    end
  end

  def pending_values(%__MODULE__{pending: %{values: values}}, computer_name) do
    for {{^computer_name, key}, value} <- values, into: %{} do
      {key, value}
    end
  end

  def pending_values(%__MODULE__{pending: nil}, _computer_name), do: %{}

  def pending_errors(%__MODULE__{pending: %{errors: errors}}, computer_name) do
    for {{^computer_name, key}, error} <- errors, into: %{} do
      {key, error}
    end
  end

  def pending_errors(%__MODULE__{pending: nil}, _computer_name), do: %{}

  def success?(%__MODULE__{pending: nil}), do: true
  def success?(%__MODULE__{}), do: false

  def clear_pending(%__MODULE__{} = executor) do
    %{executor | pending: nil}
  end

  defp build_global_graph(executor) do
    graph =
      for {comp_name, computer} <- executor.computers,
          {val_name, deps} <- computer.dependencies,
          reduce: %{} do
        graph ->
          node = {comp_name, val_name}

          local_deps =
            for dep <- deps do
              {comp_name, dep}
            end

          Map.put(graph, node, local_deps)
      end

    graph =
      for %{source: {source_comp, source_val}, target: {target_comp, target_input}} <-
            executor.connections,
          reduce: graph do
        graph ->
          source_node = {source_comp, source_val}
          target_node = {target_comp, target_input}

          Map.update(graph, target_node, [source_node], fn deps ->
            [source_node | deps]
          end)
      end

    # Ensure all inputs are in the graph (they may be used only by events/templates)
    for {comp_name, computer} <- executor.computers,
        input_name <- Map.keys(computer.inputs),
        reduce: graph do
      graph ->
        node = {comp_name, input_name}
        Map.put_new(graph, node, [])
    end
  end

  defp topological_sort(graph) do
    all_nodes = MapSet.new(Map.keys(graph))

    all_nodes_with_deps =
      graph
      |> Map.values()
      |> List.flatten()
      |> MapSet.new()
      |> MapSet.union(all_nodes)

    do_topological_sort(all_nodes_with_deps, graph, [], MapSet.new())
  end

  defp do_topological_sort(nodes, graph, sorted, visited) do
    case Enum.find(nodes, fn node -> not MapSet.member?(visited, node) end) do
      nil ->
        Enum.reverse(sorted)

      node ->
        {new_sorted, new_visited} = visit_node(node, graph, sorted, visited)
        remaining_nodes = MapSet.delete(nodes, node)
        do_topological_sort(remaining_nodes, graph, new_sorted, new_visited)
    end
  end

  defp visit_node(node, graph, sorted, visited) do
    if MapSet.member?(visited, node) do
      {sorted, visited}
    else
      visited = MapSet.put(visited, node)
      deps = Map.get(graph, node, [])

      {sorted, visited} =
        Enum.reduce(deps, {sorted, visited}, fn dep, {sorted, visited} ->
          visit_node(dep, graph, sorted, visited)
        end)

      {[node | sorted], visited}
    end
  end

  defp topological_sort_subgraph(graph, nodes) do
    subgraph =
      for node <- nodes, into: %{} do
        {node, Map.get(graph, node, [])}
      end

    do_topological_sort(MapSet.new(nodes), subgraph, [], MapSet.new())
  end

  defp find_affected_nodes(executor, changed_nodes) do
    changed_set = MapSet.new(changed_nodes)
    do_find_affected(executor.global_graph, changed_set, changed_set)
  end

  defp do_find_affected(graph, to_check, affected) do
    case Enum.find(to_check, fn _ -> true end) do
      nil ->
        MapSet.to_list(affected)

      node ->
        to_check = MapSet.delete(to_check, node)
        dependents = dependents_of(graph, node)

        new_affected =
          Enum.reduce(dependents, affected, fn dep, acc ->
            MapSet.put(acc, dep)
          end)

        new_to_check =
          Enum.reduce(dependents, to_check, fn dep, acc ->
            if MapSet.member?(affected, dep) do
              acc
            else
              MapSet.put(acc, dep)
            end
          end)

        do_find_affected(graph, new_to_check, new_affected)
    end
  end

  defp dependents_of(graph, node) do
    for {val, deps} <- graph, node in deps, do: val
  end

  defp compute_node(executor, {comp_name, node_name}, values, errors) do
    computer = executor.computers[comp_name]

    case Map.has_key?(computer.inputs, node_name) do
      true ->
        node = {comp_name, node_name}
        connected_value = find_connected_value(executor, node, values)
        current_value = Map.get(values, node)
        initial_value = Map.get(computer.inputs, node_name)

        value = connected_value || current_value || initial_value
        {Map.put(values, node, value), errors}

      false ->
        compute_val(executor, comp_name, node_name, values, errors)
    end
  end

  defp find_connected_value(executor, target_node, values) do
    case Enum.find(executor.connections, fn conn -> conn.target == target_node end) do
      nil -> nil
      %{source: source_node} -> Map.get(values, source_node)
    end
  end

  defp compute_val(executor, comp_name, val_name, values, errors) do
    computer = executor.computers[comp_name]
    deps = Map.get(computer.dependencies, val_name, [])

    dep_nodes =
      for dep <- deps do
        {comp_name, dep}
      end

    case Enum.find(dep_nodes, fn node -> Map.has_key?(errors, node) end) do
      nil ->
        compute_fn = computer.vals[val_name]

        args =
          for dep <- deps, into: %{} do
            {dep, Map.get(values, {comp_name, dep})}
          end

        result = compute_fn.(args)

        case normalize_result(result) do
          {:ok, value} ->
            node = {comp_name, val_name}
            {Map.put(values, node, value), Map.delete(errors, node)}

          {:error, reason} ->
            node = {comp_name, val_name}
            {values, Map.put(errors, node, {:expected, reason})}
        end

      blocked_dep ->
        node = {comp_name, val_name}
        {values, Map.put(errors, node, {:blocked, blocked_dep})}
    end
  end

  defp normalize_result({:ok, value}), do: {:ok, value}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result(value), do: {:ok, value}
end