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
      unquote_splicing(event_handlers)
    end
  end

  defp generate_event_handler(module, computer_name, event_name) do
    event_string = "#{computer_name}_#{event_name}"

    quote do
      @impl true
      def handle_event(unquote(event_string), params, socket) do
        # Get or build the current computer from assigns
        computer = get_computer_from_assigns(socket, unquote(computer_name), unquote(module))

        # Apply the event
        updated_computer = AshComputer.apply_event(
          unquote(module),
          unquote(computer_name),
          unquote(event_name),
          computer,
          params
        )

        # Sync updated values back to assigns
        updated_socket = sync_computer_to_assigns(socket, unquote(computer_name), updated_computer)

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
  Initializes all computers and syncs their values to socket assigns.

  Call this in your mount callback:

      def mount(_params, _session, socket) do
        {:ok, mount_computers(socket)}
      end
  """
  def mount_computers(socket) do
    module = socket.view
    computers = AshComputer.Info.computer_names(module)

    Enum.reduce(computers, socket, fn computer_name, acc ->
      computer = AshComputer.computer(module, computer_name)
      sync_computer_to_assigns(acc, computer_name, computer)
    end)
  end

  @doc """
  Syncs a computer's values to socket assigns using flat naming.

  All values are assigned as `computer_name_value_name`.
  """
  def sync_computer_to_assigns(socket, computer_name, computer) do
    assigns =
      computer.values
      |> Enum.map(fn {key, value} ->
        # Convert atom key to string for concatenation, then back to atom
        key_str = if is_atom(key), do: Atom.to_string(key), else: key
        assign_name = String.to_atom("#{computer_name}_#{key_str}")
        {assign_name, value}
      end)

    Phoenix.Component.assign(socket, assigns)
  end

  @doc """
  Gets the current computer from socket assigns or builds a new one.

  Reconstructs the computer from the flat assigns structure.
  """
  def get_computer_from_assigns(socket, computer_name, module) do
    # Build a fresh computer
    computer = AshComputer.computer(module, computer_name)

    # Update it with current assign values
    computer_name_str = Atom.to_string(computer_name)

    # Find all assigns that belong to this computer
    current_values =
      socket.assigns
      |> Enum.filter(fn {key, _value} ->
        key_str = Atom.to_string(key)
        String.starts_with?(key_str, "#{computer_name_str}_")
      end)
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        key_str = Atom.to_string(key)
        value_name_str = String.replace_prefix(key_str, "#{computer_name_str}_", "")
        value_name = String.to_atom(value_name_str)

        # Only update inputs, not computed vals
        if Map.has_key?(computer.values, value_name) do
          Map.put(acc, value_name, value)
        else
          acc
        end
      end)

    # Apply input updates to the computer
    Enum.reduce(current_values, computer, fn {input_name, value}, acc ->
      # Check if this is an input (not a val)
      if Map.has_key?(acc.inputs, input_name) do
        AshComputer.Runtime.handle_input(acc, input_name, value)
      else
        acc
      end
    end)
  end
end