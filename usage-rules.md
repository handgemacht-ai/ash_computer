# AshComputer Usage Rules

Reactive computation models with Spark-powered DSL for Elixir applications.

## Understanding AshComputer

AshComputer provides a declarative DSL for building reactive computational models that automatically update when their inputs change. It consists of:

1. **Computers**: Named computational models containing inputs, computed values (vals), and events
2. **Inputs**: External values that can be changed to trigger recomputation
3. **Vals**: Derived values computed from inputs and other vals
4. **Events**: Named handlers that mutate the computer state

Values are automatically recomputed in dependency order when inputs change.

## Basic Computer Definition

### Setting Up a Computer Module

Always use the AshComputer module to define computers:

```elixir
defmodule MyApp.Calculator do
  use AshComputer

  computer :calculator do
    input :x do
      initial 0
      description "First operand"
    end

    input :y do
      initial 0
      description "Second operand"
    end

    val :sum do
      description "Sum of x and y"
      compute fn %{x: x, y: y} -> x + y end
    end

    val :product do
      description "Product of x and y"
      compute fn %{x: x, y: y} -> x * y end
    end

    event :reset do
      handle fn _values, _payload ->
        %{x: 0, y: 0}
      end
    end
  end
end
```

### Input Definitions

Inputs represent external values that drive the computation:

```elixir
input :temperature do
  initial 20  # Initial value when computer is built
  description "Temperature in Celsius"
  options %{}  # Optional metadata
end
```

**Important**: Initial values are required for inputs to ensure the computer can be built immediately.

### Val Definitions

Vals are computed values that automatically update when their dependencies change:

```elixir
val :fahrenheit do
  description "Temperature in Fahrenheit"
  compute fn %{temperature: c} -> c * 9/5 + 32 end
  # Dependencies are auto-detected from the function's pattern match
end
```

**Dependency detection**: Dependencies are automatically inferred from the pattern match in the compute function. You can also specify them explicitly:

```elixir
val :derived do
  compute fn values -> values[:a] + values[:b] end
  depends_on [:a, :b]  # Explicit dependencies when pattern matching isn't used
end
```

### Chained Computations

Vals can depend on other vals, creating computation chains:

```elixir
computer :chain do
  input :base do
    initial 10
  end

  val :doubled do
    compute fn %{base: base} -> base * 2 end
  end

  val :quadrupled do
    compute fn %{doubled: doubled} -> doubled * 2 end
    # Automatically depends on :doubled
  end
end
```

## Working with Computers

### Building and Evaluating

```elixir
# Build a computer (evaluates all vals)
computer = AshComputer.computer(MyModule)  # Uses default computer
computer = AshComputer.computer(MyModule, :calculator)  # Named computer

# Access computed values
computer.values[:sum]  # => computed sum
computer.values[:x]    # => input value
```

### Updating Inputs

Use `AshComputer.Runtime.handle_input/3` to update inputs and trigger recomputation:

```elixir
# Update an input value
computer = AshComputer.Runtime.handle_input(computer, :x, 42)

# All dependent vals are automatically recomputed
computer.values[:sum]     # => new sum with x=42
computer.values[:product]  # => new product with x=42
```

**Cascade updates**: When an input changes, all dependent vals are recomputed in dependency order automatically.

## Events

Events provide named handlers for complex state mutations. Event handlers receive all current values (inputs and vals) and can return a map of input changes.

### Defining Events

Event handlers use pattern matching to access current values:

```elixir
event :load_preset do
  handle fn _values, %{preset: preset} ->
    case preset do
      :default ->
        %{x: 10, y: 5}
      :test ->
        %{x: 100, y: 50}
    end
  end
end

# Pattern matching on specific values
event :scale do
  handle fn %{x: x, y: y}, %{factor: factor} ->
    %{x: x * factor, y: y * factor}
  end
end

# Using computed vals to determine input changes
event :adjust_based_on_sum do
  handle fn %{x: x, y: y, sum: sum}, _payload ->
    if sum > 100 do
      %{x: x / 2, y: y / 2}
    else
      %{}  # No changes
    end
  end
end
```

### Event Handler Signatures

Events support two handler arities:

```elixir
# Arity 1: No payload needed
event :reset do
  handle fn values ->
    %{x: 0, y: 0}  # Return input changes
  end
end

# Arity 2: With payload
event :update do
  handle fn values, payload ->
    %{x: payload[:new_x], y: values[:y]}  # Mix payload and current values
  end
end
```

**Important Rules**:
- Handlers receive all values (inputs + vals) for pattern matching
- Handlers MUST return a map of input changes (not the full computer)
- Only inputs can be modified in the returned map
- Vals are read-only and automatically recomputed
- Return an empty map `%{}` for no changes

### Applying Events

```elixir
# Apply event without payload (arity 1 handler)
computer = AshComputer.apply_event(MyModule, :reset, computer)

# Apply event with payload (arity 2 handler)
payload = %{preset: :default}
computer = AshComputer.apply_event(MyModule, :load_preset, computer, payload)

# With explicit computer name
computer = AshComputer.apply_event(MyModule, :calculator, :reset, computer)
```

## Stateful Computers

Computers can be stateful to access previous values during computation:

```elixir
computer :stateful_example do
  stateful? true  # Enable stateful mode

  input :new_value do
    initial 0
  end

  val :average do
    compute fn %{new_value: new}, all_values ->
      # Second argument contains all current values including previous computations
      previous = all_values[:average] || 0
      (previous + new) / 2
    end
  end
end
```

**Stateful compute functions**: When `stateful?` is true and compute function has arity 2, the second argument provides access to all current values.

## GenServer Instances

Computers can be wrapped in GenServer processes for concurrent state management:

```elixir
# Create a GenServer instance
{:ok, pid} = AshComputer.make_instance(MyModule)
{:ok, pid} = AshComputer.make_instance(MyModule, :calculator)
{:ok, pid} = AshComputer.make_instance(MyModule, :calculator, name: MyServer)

# The GenServer handles the computer state internally
# Use GenServer.call/cast to interact with it
```

## LiveView Integration

### Setup in LiveView

Use `AshComputer.LiveView` to integrate computers with Phoenix LiveView:

```elixir
defmodule MyAppWeb.CalculatorLive do
  use Phoenix.LiveView
  use AshComputer.LiveView  # Adds helper functions

  computer :calculator do
    input :x do
      initial 0
    end

    val :squared do
      compute fn %{x: x} -> x * x end
    end

    event :set_x do
      handle fn computer, %{value: value} ->
        AshComputer.Runtime.handle_input(computer, :x, value)
      end
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, mount_computers(socket)}  # Helper from AshComputer.LiveView
  end
end
```

### Generated Event Handlers

LiveView integration automatically generates `handle_event/3` callbacks for each computer event:

```elixir
# Event :set_x generates handler for "calculator_set_x" event
# Event :reset generates handler for "calculator_reset" event
```

**Event naming pattern**: `{computer_name}_{event_name}`

### Compile-Time Safe Event References

**Always use the `event/2` macro** instead of hardcoded strings in templates:

```heex
<!-- ✅ ALWAYS do this - compile-time safe -->
<form phx-submit={event(:calculator, :set_x)}>
  <input name="value" value={@calculator_x} />
  <button type="submit">Update</button>
</form>

<button phx-click={event(:calculator, :reset)}>Reset</button>

<!-- ❌ NEVER do this - error-prone hardcoded strings -->
<form phx-submit="calculator_set_x">
  <input name="value" value={@calculator_x} />
  <button type="submit">Update</button>
</form>

<button phx-click="calculator_reset">Reset</button>
```

The `event/2` macro provides:
- **Compile-time validation**: Ensures computer and event exist
- **Error prevention**: Typos cause compilation failures, not runtime errors
- **Refactoring safety**: Renaming events causes compile errors in templates
- **IDE support**: Better auto-completion and navigation

**Error example**: Using `event(:calculator, :nonexistent)` produces:
```
** (CompileError) Event :nonexistent not found in computer :calculator
Available events: [:set_x, :reset]
```

## API Functions

### Module-Level Functions

```elixir
# List all computers in a module
AshComputer.computers(MyModule)  # => [:calculator, :other]

# Get default computer name
AshComputer.Info.default_computer_name(MyModule)  # => :calculator

# Build computers
computer = AshComputer.computer(MyModule)  # Default computer
computer = AshComputer.computer(MyModule, :specific)

# List events for a computer
AshComputer.events(MyModule)  # => [:reset, :load]
AshComputer.events(MyModule, :calculator)  # => [:reset, :load]
```

### Runtime Functions

```elixir
# Update inputs
computer = AshComputer.Runtime.handle_input(computer, :input_name, value)

# Create GenServer instance
{:ok, pid} = AshComputer.Runtime.make_instance(computer, options)
```

## Best Practices

1. **Always provide initial values**: All inputs must have initial values for immediate computation
2. **Use meaningful names**: Name computers, inputs, vals, and events descriptively
3. **Prefer pattern matching**: Use pattern matching in compute functions for automatic dependency detection
4. **Return computers from events**: Event handlers must always return an updated computer struct
5. **Use events for complex updates**: Encapsulate multi-input updates in named events
6. **Leverage dependency chains**: Build complex computations through chained vals
7. **Consider stateful mode carefully**: Only use stateful computers when previous values are needed
8. **Document with descriptions**: Use description fields for clarity
9. **Test computation chains**: Verify that updates cascade correctly through dependencies

## Common Patterns

### Multi-Step Calculations

Build complex calculations through chained vals:

```elixir
computer :physics do
  input :mass do
    initial 10  # kg
  end

  input :velocity do
    initial 5  # m/s
  end

  val :kinetic_energy do
    compute fn %{mass: m, velocity: v} -> 0.5 * m * v * v end
  end

  val :momentum do
    compute fn %{mass: m, velocity: v} -> m * v end
  end

  val :energy_ratio do
    compute fn %{kinetic_energy: ke, momentum: p} ->
      if p != 0, do: ke / p, else: 0
    end
  end
end
```

### Form Handling in LiveView

Integrate with forms using events:

```elixir
computer :form do
  input :email do
    initial ""
  end

  input :name do
    initial ""
  end

  val :valid? do
    compute fn %{email: email, name: name} ->
      email != "" and name != ""
    end
  end

  event :update_field do
    handle fn computer, %{"field" => field, "value" => value} ->
      field_atom = String.to_existing_atom(field)
      AshComputer.Runtime.handle_input(computer, field_atom, value)
    end
  end
end
```

### Preset Management

Use events to manage preset configurations:

```elixir
computer :config do
  input :setting_a do
    initial 0
  end

  input :setting_b do
    initial 0
  end

  event :load_preset do
    handle fn computer, %{name: name} ->
      presets = %{
        low: %{setting_a: 10, setting_b: 20},
        medium: %{setting_a: 50, setting_b: 50},
        high: %{setting_a: 90, setting_b: 100}
      }

      settings = Map.get(presets, name, presets.low)

      Enum.reduce(settings, computer, fn {key, value}, acc ->
        AshComputer.Runtime.handle_input(acc, key, value)
      end)
    end
  end
end
```

## Common Issues

### Missing Dependencies
```elixir
# Error: Dependencies not detected
val :computed do
  compute fn values ->
    # Accessing values dynamically doesn't auto-detect dependencies
    values[:a] + values[:b]
  end
end

# Fix: Use pattern matching or explicit dependencies
val :computed do
  compute fn %{a: a, b: b} -> a + b end
end

# Or:
val :computed do
  compute fn values -> values[:a] + values[:b] end
  depends_on [:a, :b]
end
```

### Event Handler Return Value
```elixir
# Error: Event must return a computer
event :bad do
  handle fn computer, _payload ->
    :ok  # Wrong return type
  end
end

# Fix: Always return the computer
event :good do
  handle fn computer, _payload ->
    computer  # Returns the computer struct
  end
end
```

### Circular Dependencies
```elixir
# Error: Circular dependency detected
val :a do
  compute fn %{b: b} -> b + 1 end
end

val :b do
  compute fn %{a: a} -> a + 1 end
end

# Fix: Restructure to avoid cycles
val :base do
  compute fn %{input: i} -> i end
end

val :derived_a do
  compute fn %{base: b} -> b + 1 end
end

val :derived_b do
  compute fn %{base: b} -> b + 2 end
end
```

### Undefined Computer
```elixir
# Error: Unknown computer :missing
computer = AshComputer.computer(MyModule, :missing)

# Fix: Check available computers first
AshComputer.computers(MyModule)  # => [:calculator]
computer = AshComputer.computer(MyModule, :calculator)
```

### LiveView Event Naming
```elixir
# Error: Event handler not triggered or typos in event names
# Wrong hardcoded event name in template
<button phx-click="reset">Reset</button>
<button phx-click="calculator_rset">Reset</button>  # Typo!

# Fix: Always use the event/2 macro for compile-time safety
<button phx-click={event(:calculator, :reset)}>Reset</button>
```

The `event/2` macro prevents these common errors:
- Typos in computer or event names (caught at compile-time)
- Using wrong event name patterns
- Forgetting to update template when renaming events

### Event Reference Errors
```elixir
# Error: Compile-time error for invalid event reference
<button phx-click={event(:calculator, :nonexistent)}>Invalid</button>
# => ** (CompileError) Event :nonexistent not found in computer :calculator

# Error: Compile-time error for invalid computer reference
<button phx-click={event(:nonexistent, :reset)}>Invalid</button>
# => ** (CompileError) Computer :nonexistent not found in module MyLive

# Fix: Use valid computer and event names
<button phx-click={event(:calculator, :reset)}>Reset</button>
```
