defmodule AshComputer.LiveView do
  @moduledoc """
  Phoenix LiveView integration for AshComputer.

  Provides automatic event handler generation and socket assigns management
  for computers defined in LiveView modules.

  ## Usage

      defmodule MyAppWeb.CartLive do
        use Phoenix.LiveView
        use AshComputer.LiveView

        computer :cart do
          input :items do
            initial []
          end

          val :total do
            compute(fn %{items: items} -> Enum.sum(items) end)
          end

          event :add_item do
            handle fn computer, params ->
              # Update computer
            end
          end
        end

        @impl true
        def mount(_params, _session, socket) do
          {:ok, mount_computers(socket)}
        end
      end

  This will:
  - Generate `handle_event("cart_add_item", params, socket)` callbacks
  - Create flat assigns like `cart_items` and `cart_total`
  - Automatically sync computer state to socket assigns
  """

  defmacro __using__(_opts) do
    quote do
      use AshComputer
      import AshComputer.LiveView
      import AshComputer.LiveView.Helpers

      Module.register_attribute(__MODULE__, :ash_computer_live_view_attachments, accumulate: true)
      @before_compile AshComputer.LiveView
    end
  end

  @doc """
  Attach a computer from an external module to this LiveView.

  This allows you to reuse computers defined in standalone modules across
  multiple LiveViews.

  ## Options

  - `:as` - Alias name for the computer (defaults to the computer name from the source module)

  ## Examples

      defmodule MyAppWeb.CheckoutLive do
        use Phoenix.LiveView
        use AshComputer.LiveView

        # Attach with default name
        attach_computer MyApp.Computers.Cart, :shopping_cart

        # Attach with alias
        attach_computer MyApp.Computers.Sidebar, :sidebar, as: :main_sidebar

        # Local computer alongside attachments
        computer :page_state do
          input :step do
            initial 1
          end
        end
      end

  The attached computer's events will be available as `alias_name_event_name`
  and assigns will be created as `alias_name_value_name`.
  """
  defmacro attach_computer(source_module, computer_name, opts \\ []) do
    # Validate that the source module and computer exist at compile time
    quote bind_quoted: [source_module: source_module, computer_name: computer_name, opts: opts] do
      # Expand the source module alias
      expanded_module =
        case source_module do
          {:__aliases__, _, _} = alias_ast ->
            Macro.expand(alias_ast, __ENV__)

          module when is_atom(module) ->
            module

          _ ->
            raise CompileError,
              description: "Expected a module name, got: #{inspect(source_module)}",
              file: __ENV__.file,
              line: __ENV__.line
        end

      # Validate that the source module has computers
      unless AshComputer.Info.has_computers?(expanded_module) do
        raise CompileError,
          description:
            "Module #{inspect(expanded_module)} does not define any computers. " <>
              "Make sure the module uses AshComputer and defines at least one computer.",
          file: __ENV__.file,
          line: __ENV__.line
      end

      # Validate that the specific computer exists
      computer = AshComputer.Info.computer(expanded_module, computer_name)

      unless computer do
        available_computers = AshComputer.Info.computer_names(expanded_module)

        raise CompileError,
          description:
            "Computer #{inspect(computer_name)} not found in module #{inspect(expanded_module)}. " <>
              "Available computers: #{inspect(available_computers)}",
          file: __ENV__.file,
          line: __ENV__.line
      end

      # Get the alias name (defaults to computer name)
      alias_name = Keyword.get(opts, :as, computer_name)

      # Store the attachment metadata
      @ash_computer_live_view_attachments {alias_name, expanded_module, computer_name, opts}
    end
  end

  @doc """
  Get all computers (local and attached) for a LiveView module.

  Returns a list of tuples: `{alias_name, source_module, computer_name}`

  - `alias_name` is the name used for events and assigns
  - `source_module` is the module where the computer is defined
  - `computer_name` is the computer name in the source module

  For local computers, `alias_name` equals `computer_name` and `source_module`
  is the LiveView module itself.
  """
  def get_all_computers(module) do
    # Get local computers
    local_computers =
      try do
        AshComputer.Info.computer_names(module)
      rescue
        _ -> []
      end
      |> Enum.map(fn name -> {name, module, name} end)

    # Get attached computers from the runtime function if it exists
    attached_computers =
      if function_exported?(module, :__ash_computer_attachments__, 0) do
        module.__ash_computer_attachments__()
      else
        []
      end

    local_computers ++ attached_computers
  end

  defmacro __before_compile__(env) do
    # Get local computers
    local_computers =
      try do
        AshComputer.Info.computer_names(env.module)
      rescue
        _ -> []
      end
      |> Enum.map(fn name -> {name, env.module, name} end)

    # Get attached computers from compile-time module attribute
    attached_computers =
      (Module.get_attribute(env.module, :ash_computer_live_view_attachments) || [])
      |> Enum.map(fn {alias_name, source_module, computer_name, _opts} ->
        {alias_name, source_module, computer_name}
      end)

    all_computers = local_computers ++ attached_computers

    event_handlers =
      for {alias_name, source_module, computer_name} <- all_computers do
        computer = AshComputer.Info.computer(source_module, computer_name)

        if computer && computer.events do
          for event <- computer.events do
            generate_event_handler(alias_name, source_module, computer_name, event.name)
          end
        else
          []
        end
      end
      |> List.flatten()

    quote do
      # Store the attachments for runtime access
      def __ash_computer_attachments__ do
        unquote(Macro.escape(attached_computers))
      end

      (unquote_splicing(event_handlers))
    end
  end

  defp generate_event_handler(alias_name, source_module, computer_name, event_name) do
    # Event handler name uses alias, and we look up the computer in the executor by alias
    event_string = "#{alias_name}_#{event_name}"

    quote do
      @impl true
      def handle_event(unquote(event_string), params, socket) do
        executor = AshComputer.LiveView.Helpers.get_executor_from_assigns(socket)

        # Get the event handler from the source module
        computer_def = AshComputer.Info.computer(unquote(source_module), unquote(computer_name))
        event = Enum.find(computer_def.events, &(&1.name == unquote(event_name)))

        unless event do
          raise ArgumentError,
                "Event #{inspect(unquote(event_name))} not found in computer #{inspect(unquote(computer_name))}"
        end

        # Get current values using alias name (which is how it's stored in the executor)
        values = AshComputer.Executor.current_values(executor, unquote(alias_name))

        # Call the event handler
        changes =
          cond do
            is_function(event.handle, 1) ->
              event.handle.(values)

            is_function(event.handle, 2) ->
              event.handle.(values, params)

            true ->
              raise ArgumentError,
                    "Event handler must be a function of arity 1 or 2"
          end

        unless is_map(changes) do
          raise ArgumentError,
                "Event handler must return a map of input changes"
        end

        # Apply the changes using alias name
        updated_executor =
          executor
          |> AshComputer.Executor.start_frame()
          |> then(fn exec ->
            Enum.reduce(changes, exec, fn {input_name, value}, acc ->
              AshComputer.Executor.set_input(acc, unquote(alias_name), input_name, value)
            end)
          end)
          |> AshComputer.Executor.commit_frame()

        updated_socket =
          socket
          |> Phoenix.Component.assign(:__executor__, updated_executor)
          |> AshComputer.LiveView.Helpers.sync_executor_to_assigns()

        {:noreply, updated_socket}
      end
    end
  end
end

defmodule AshComputer.LiveView.Helpers do
  @moduledoc """
  Helper functions for LiveView integration.
  """

  @doc """
  Compile-time safe event name reference for use in HEEx templates.

  Returns the properly formatted event name string and validates that
  both the computer and event exist at compile-time.

  Works with both local computers and attached computers (using their alias names).

  ## Examples

      # In templates:
      <button phx-click={event(:calculator, :reset)}>Reset</button>
      <form phx-submit={event(:shopping_cart, :add_item)}>...</form>

  ## Compile-time validation

  If the computer or event doesn't exist, compilation will fail with
  a helpful error message listing available options.
  """
  defmacro event(computer_name, event_name) do
    # We need to get the calling module to look up computers
    caller_module = __CALLER__.module

    # Get local computers
    local_computers =
      try do
        AshComputer.Info.computer_names(caller_module)
      rescue
        _ -> []
      end
      |> Enum.map(fn name -> {name, caller_module, name} end)

    # Get attached computers from compile-time module attribute
    attached_computers =
      (Module.get_attribute(caller_module, :ash_computer_live_view_attachments) || [])
      |> Enum.map(fn {alias_name, source_module, computer_name_in_source, _opts} ->
        {alias_name, source_module, computer_name_in_source}
      end)

    all_computers = local_computers ++ attached_computers

    computer_tuple =
      Enum.find(all_computers, fn {alias_name, _source_module, _computer_name} ->
        alias_name == computer_name
      end)

    unless computer_tuple do
      available_aliases = Enum.map(all_computers, fn {alias_name, _, _} -> alias_name end)

      raise CompileError,
        description:
          "Computer #{inspect(computer_name)} not found in module #{inspect(caller_module)}. " <>
            "Available computers: #{inspect(available_aliases)}",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    {_alias_name, source_module, source_computer_name} = computer_tuple

    # Get the computer definition from the source module
    computer = AshComputer.Info.computer(source_module, source_computer_name)

    unless computer do
      raise CompileError,
        description:
          "Internal error: Computer #{inspect(source_computer_name)} not found in source module #{inspect(source_module)}",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    # Validate the event exists in the computer
    event_exists = Enum.any?(computer.events, fn event -> event.name == event_name end)

    unless event_exists do
      available_events = Enum.map(computer.events, & &1.name)

      raise CompileError,
        description:
          "Event #{inspect(event_name)} not found in computer #{inspect(computer_name)} " <>
            "(from #{inspect(source_module)}.#{inspect(source_computer_name)}). " <>
            "Available events: #{inspect(available_events)}",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    # Return the correctly formatted event string using alias name
    event_string = "#{computer_name}_#{event_name}"

    quote do
      unquote(event_string)
    end
  end

  @doc """
  Initializes all computers and syncs their values to socket assigns.

  Call this in your mount callback:

      def mount(_params, _session, socket) do
        {:ok, mount_computers(socket)}
      end

  To initialize computers with custom input values, pass an initial inputs map.
  Use the alias name (or computer name for local computers) as the key:

      def mount(%{"product_id" => product_id}, _session, socket) do
        initial_inputs = %{
          shopping_cart: %{  # Use alias name for attached computers
            product_id: String.to_integer(product_id),
            quantity: 1
          }
        }
        {:ok, mount_computers(socket, initial_inputs)}
      end

  The initial inputs map has the structure: `%{alias_name => %{input_name => value}}`
  """
  def mount_computers(socket, initial_inputs \\ %{}) do
    module = socket.view
    all_computers = AshComputer.LiveView.get_all_computers(module)

    executor =
      Enum.reduce(all_computers, AshComputer.Executor.new(), fn {alias_name, source_module, computer_name}, acc ->
        # Add computer to executor using alias name as the key
        # This is a bit of a hack - we're calling add_computer with the source module
        # and computer name to get the spec, but storing it under alias_name
        spec = AshComputer.computer_spec(source_module, computer_name)
        %{inputs: inputs, vals: vals, dependencies: dependencies} = spec

        computer = %{
          inputs: inputs,
          vals: vals,
          dependencies: dependencies
        }

        %{acc | computers: Map.put(acc.computers, alias_name, computer)}
      end)
      |> AshComputer.Executor.initialize()

    executor =
      if map_size(initial_inputs) > 0 do
        executor
        |> AshComputer.Executor.start_frame()
        |> apply_initial_inputs(initial_inputs)
        |> AshComputer.Executor.commit_frame()
      else
        executor
      end

    socket
    |> Phoenix.Component.assign(:__executor__, executor)
    |> sync_executor_to_assigns()
  end

  defp apply_initial_inputs(executor, initial_inputs) do
    Enum.reduce(initial_inputs, executor, fn {computer_name, inputs_map}, acc ->
      Enum.reduce(inputs_map, acc, fn {input_name, value}, exec ->
        AshComputer.Executor.set_input(exec, computer_name, input_name, value)
      end)
    end)
  end

  @doc """
  Syncs all computers in the executor to socket assigns using flat naming.

  All values are assigned as `computer_name_value_name`.
  """
  def sync_executor_to_assigns(socket) do
    executor = socket.assigns[:__executor__]

    if executor do
      assigns =
        for {computer_name, _computer} <- executor.computers,
            {{^computer_name, key}, value} <- executor.values do
          key_str = if is_atom(key), do: Atom.to_string(key), else: key
          assign_name = String.to_atom("#{computer_name}_#{key_str}")
          {assign_name, value}
        end

      Phoenix.Component.assign(socket, assigns)
    else
      socket
    end
  end

  @doc """
  Gets the current executor from socket assigns.
  """
  def get_executor_from_assigns(socket) do
    socket.assigns[:__executor__]
  end

  @doc """
  Updates multiple inputs for a single computer and syncs the result back to the socket.

  This helper allows you to manually trigger computer recomputation from
  custom event handlers by updating input values.

  ## Examples

      def handle_event("custom_action", _params, socket) do
        # Your custom logic here
        ...

        # Update multiple inputs for a computer
        updated_socket = update_computer_inputs(socket, :sidebar, %{
          refresh_trigger: System.monotonic_time(),
          filter: "active"
        })

        {:noreply, updated_socket}
      end

  ## Parameters

    - `socket` - The LiveView socket
    - `computer_name` - The name of the computer (atom)
    - `inputs` - Map of input names to values: `%{input_name => value}`

  ## Returns

  The updated socket with the new executor state synced to assigns.
  """
  def update_computer_inputs(socket, computer_name, inputs) when is_map(inputs) do
    update_computers(socket, %{computer_name => inputs})
  end

  @doc """
  Updates inputs across multiple computers and syncs the result back to the socket.

  This is the most general form that allows updating any number of inputs
  across any number of computers in a single operation.

  ## Examples

      def handle_event("refresh_all", _params, socket) do
        updated_socket = update_computers(socket, %{
          sidebar: %{refresh_trigger: System.monotonic_time()},
          main_content: %{page: 1, filter: "all"}
        })

        {:noreply, updated_socket}
      end

  ## Parameters

    - `socket` - The LiveView socket
    - `updates` - Nested map: `%{computer_name => %{input_name => value}}`

  ## Returns

  The updated socket with the new executor state synced to assigns.
  """
  def update_computers(socket, updates) when is_map(updates) do
    executor = get_executor_from_assigns(socket)

    unless executor do
      raise ArgumentError, "No executor found in socket assigns. Did you call mount_computers/1?"
    end

    updated_executor =
      executor
      |> AshComputer.Executor.start_frame()
      |> apply_initial_inputs(updates)
      |> AshComputer.Executor.commit_frame()

    socket
    |> Phoenix.Component.assign(:__executor__, updated_executor)
    |> sync_executor_to_assigns()
  end
end
