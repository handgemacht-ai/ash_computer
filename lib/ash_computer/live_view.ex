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
      import AshComputer.LiveView.Helpers

      @before_compile AshComputer.LiveView
    end
  end

  defmacro __before_compile__(env) do
    # Get computer names from the module
    computer_names =
      try do
        AshComputer.Info.computer_names(env.module)
      rescue
        _ -> []
      end

    event_handlers =
      for computer_name <- computer_names do
        computer = AshComputer.Info.computer(env.module, computer_name)

        if computer && computer.events do
          for event <- computer.events do
            generate_event_handler(env.module, computer_name, event.name)
          end
        else
          []
        end
      end
      |> List.flatten()

    quote do
      (unquote_splicing(event_handlers))
    end
  end

  defp generate_event_handler(module, computer_name, event_name) do
    event_string = "#{computer_name}_#{event_name}"

    quote do
      @impl true
      def handle_event(unquote(event_string), params, socket) do
        executor = AshComputer.LiveView.Helpers.get_executor_from_assigns(socket)

        updated_executor =
          AshComputer.apply_event(
            unquote(module),
            unquote(computer_name),
            unquote(event_name),
            executor,
            params
          )

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

  ## Examples

      # In templates:
      <button phx-click={event(:calculator, :reset)}>Reset</button>
      <form phx-submit={event(:calculator, :set_x)}>...</form>

  ## Compile-time validation

  If the computer or event doesn't exist, compilation will fail with
  a helpful error message listing available options.
  """
  defmacro event(computer_name, event_name) do
    # We need to get the calling module to look up computers
    caller_module = __CALLER__.module

    # Validate the computer exists
    computer = AshComputer.Info.computer(caller_module, computer_name)

    unless computer do
      available_computers = AshComputer.Info.computer_names(caller_module)

      raise CompileError,
        description:
          "Computer #{inspect(computer_name)} not found in module #{inspect(caller_module)}. Available computers: #{inspect(available_computers)}",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    # Validate the event exists in the computer
    event_exists = Enum.any?(computer.events, fn event -> event.name == event_name end)

    unless event_exists do
      available_events = Enum.map(computer.events, & &1.name)

      raise CompileError,
        description:
          "Event #{inspect(event_name)} not found in computer #{inspect(computer_name)} of module #{inspect(caller_module)}. Available events: #{inspect(available_events)}",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    # Return the correctly formatted event string
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

  To initialize computers with custom input values, pass an initial inputs map:

      def mount(%{"product_id" => product_id}, _session, socket) do
        initial_inputs = %{
          cart: %{
            product_id: String.to_integer(product_id),
            quantity: 1
          }
        }
        {:ok, mount_computers(socket, initial_inputs)}
      end

  The initial inputs map has the structure: `%{computer_name => %{input_name => value}}`
  """
  def mount_computers(socket, initial_inputs \\ %{}) do
    module = socket.view
    computer_names = AshComputer.Info.computer_names(module)

    executor =
      Enum.reduce(computer_names, AshComputer.Executor.new(), fn computer_name, acc ->
        AshComputer.Executor.add_computer(acc, module, computer_name)
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
