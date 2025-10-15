# AshComputer

[![Hex.pm](https://img.shields.io/hexpm/v/ash_computer.svg)](https://hex.pm/packages/ash_computer)
[![Hex Docs](https://img.shields.io/badge/hex-docs-purple.svg)](https://hexdocs.pm/ash_computer)
[![License](https://img.shields.io/hexpm/l/ash_computer.svg)](https://github.com/marot/ash_computer/blob/main/LICENSE)

A reactive computation DSL for Elixir, powered by [Spark](https://github.com/ash-project/spark). Based on [Lucassifoni/computer](https://github.com/Lucassifoni/computer).

AshComputer provides a declarative way to define computational models that automatically update when their inputs change. Perfect for building calculators, form validations, reactive UIs, and any system requiring cascading computations.

## Features

- 🔄 **Reactive Computations** - Values automatically update when dependencies change
- 🎯 **Declarative DSL** - Define computers with a clean, readable syntax
- ⚡ **Automatic Dependency Resolution** - Dependencies are inferred from your compute functions
- 🎭 **Event System** - Named events for complex state mutations
- 🖥️ **LiveView Integration** - First-class support for Phoenix LiveView
- 🧮 **Chained Computations** - Build complex calculations through dependent values

## Installation

Add `ash_computer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_computer, "~> 0.6.0"}
  ]
end
```

## Quick Start

### Basic Calculator

```elixir
defmodule MyApp.Calculator do
  use AshComputer

  computer :calculator do
    input :x do
      initial 10
    end

    input :y do
      initial 5
    end

    val :sum do
      compute fn %{x: x, y: y} -> x + y end
    end

    val :product do
      compute fn %{x: x, y: y} -> x * y end
    end
  end
end

# Use the calculator with Executor
executor =
  AshComputer.Executor.new()
  |> AshComputer.Executor.add_computer(MyApp.Calculator, :calculator)
  |> AshComputer.Executor.initialize()

values = AshComputer.Executor.current_values(executor, :calculator)
values[:sum]     # => 15
values[:product] # => 50

# Update inputs
executor =
  executor
  |> AshComputer.Executor.start_frame()
  |> AshComputer.Executor.set_input(:calculator, :x, 20)
  |> AshComputer.Executor.commit_frame()

values = AshComputer.Executor.current_values(executor, :calculator)
values[:sum]     # => 25
values[:product] # => 100
```

### With Events

```elixir
defmodule MyApp.TemperatureConverter do
  use AshComputer

  computer :converter do
    input :celsius do
      initial 0
      description "Temperature in Celsius"
    end

    val :fahrenheit do
      description "Temperature in Fahrenheit"
      compute fn %{celsius: c} -> c * 9/5 + 32 end
    end

    val :kelvin do
      description "Temperature in Kelvin"
      compute fn %{celsius: c} -> c + 273.15 end
    end

    event :set_from_fahrenheit do
      handle fn _values, %{fahrenheit: f} ->
        celsius = (f - 32) * 5/9
        %{celsius: celsius}
      end
    end
  end
end

# Use events with Executor
executor =
  AshComputer.Executor.new()
  |> AshComputer.Executor.add_computer(MyApp.TemperatureConverter, :converter)
  |> AshComputer.Executor.initialize()

executor = AshComputer.apply_event(
  MyApp.TemperatureConverter,
  :set_from_fahrenheit,
  executor,
  %{fahrenheit: 100}
)

values = AshComputer.Executor.current_values(executor, :converter)
values[:celsius] # => 37.78
```

## LiveView Integration

AshComputer integrates seamlessly with Phoenix LiveView:

```elixir
defmodule MyAppWeb.CalculatorLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  computer :calculator do
    input :amount do
      initial 100
    end

    input :tax_rate do
      initial 0.08
    end

    val :tax do
      compute fn %{amount: amount, tax_rate: rate} ->
        amount * rate
      end
    end

    val :total do
      compute fn %{amount: amount, tax: tax} ->
        amount + tax
      end
    end

    event :update_amount do
      handle fn _values, %{"value" => value} ->
        {amount, _} = Float.parse(value)
        %{amount: amount}
      end
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, mount_computers(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form phx-submit={event(:calculator, :update_amount)}>
        <label>
          Amount: $
          <input
            type="number"
            name="value"
            value={@calculator_amount}
            step="0.01"
          />
        </label>
        <button type="submit">Update</button>
      </form>

      <p>Tax (8%): $<%= Float.round(@calculator_tax, 2) %></p>
      <p>Total: $<%= Float.round(@calculator_total, 2) %></p>
    </div>
    """
  end
end
```

### Compile-Time Safe Event References

AshComputer provides compile-time validation for event names in templates:

```heex
<!-- ✅ Compile-time safe - validates computer and event exist -->
<button phx-click={event(:calculator, :reset)}>Reset</button>
<form phx-submit={event(:calculator, :update_amount)}>...</form>

<!-- ❌ Old way - error-prone hardcoded strings -->
<button phx-click="calculator_reset">Reset</button>
<form phx-submit="calculator_update_amount">...</form>
```

If you reference a non-existent computer or event, you'll get a helpful compile-time error:

```
** (CompileError) Event :nonexistent not found in computer :calculator
Available events: [:update_amount, :reset]
```

This prevents typos and ensures your templates stay in sync with your computer definitions.

### Custom Event Handlers and Manual Updates

While AshComputer automatically generates event handlers, you can also create custom handlers that update computer inputs manually:

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  computer :sidebar do
    input :refresh_trigger do
      initial 0
    end

    input :filter do
      initial "all"
    end

    val :items do
      compute fn %{refresh_trigger: _trigger, filter: filter} ->
        # Fetch items from database based on filter
        fetch_items(filter)
      end
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, mount_computers(socket)}
  end

  # Custom handler that updates a single computer
  @impl true
  def handle_event("create_item", params, socket) do
    # Your business logic
    {:ok, _item} = create_item(params)

    # Trigger sidebar refresh by updating inputs
    updated_socket = update_computer_inputs(socket, :sidebar, %{
      refresh_trigger: System.monotonic_time()
    })

    {:noreply, updated_socket}
  end

  # Update multiple computers at once
  @impl true
  def handle_event("reset_all", _params, socket) do
    updated_socket = update_computers(socket, %{
      sidebar: %{filter: "all", refresh_trigger: 0},
      main_content: %{page: 1}
    })

    {:noreply, updated_socket}
  end
end
```

The `update_computer_inputs/3` and `update_computers/2` helper functions allow you to manually trigger recomputations from any custom event handler, making it easy to integrate AshComputer with existing business logic.

## Advanced Features

### Chained Computations

Values can depend on other computed values, creating computation chains:

```elixir
computer :physics do
  input :mass do
    initial 10  # kg
  end

  input :velocity do
    initial 5  # m/s
  end

  val :momentum do
    compute fn %{mass: m, velocity: v} -> m * v end
  end

  val :kinetic_energy do
    compute fn %{mass: m, velocity: v} -> 0.5 * m * v * v end
  end

  val :de_broglie_wavelength do
    compute fn %{momentum: p} ->
      # h = Planck's constant
      6.626e-34 / p
    end
  end
end
```

### Stateful Computers

For computations that need access to previous values:

```elixir
computer :moving_average do
  stateful? true

  input :new_value do
    initial 0
  end

  val :average do
    compute fn %{new_value: new}, all_values ->
      previous = all_values[:average] || 0
      count = (all_values[:count] || 0) + 1
      ((previous * (count - 1)) + new) / count
    end
  end

  val :count do
    compute fn _deps, all_values ->
      (all_values[:count] || 0) + 1
    end
  end
end
```

## Key Concepts

- **Inputs**: External values that can be updated
- **Vals**: Computed values that automatically update when dependencies change
- **Events**: Named handlers for complex state mutations
- **Dependencies**: Automatically detected from pattern matches in compute functions

## Why AshComputer?

- **Declarative**: Focus on what to compute, not how to manage updates
- **Reactive**: Changes cascade automatically through your computation graph
- **Testable**: Pure computation functions are easy to test
- **Composable**: Build complex systems from simple, reusable computers
- **Integrated**: Works seamlessly with Phoenix LiveView and other Elixir libraries

## Documentation

For detailed documentation, see [HexDocs](https://hexdocs.pm/ash_computer).

For AI assistance with this library, see [usage-rules.md](usage-rules.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.