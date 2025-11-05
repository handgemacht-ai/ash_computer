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

### Building and Using an Executor

```elixir
# Create an executor and add a computer
executor =
  AshComputer.Executor.new()
  |> AshComputer.Executor.add_computer(MyModule, :calculator)
  |> AshComputer.Executor.initialize()

# Access computed values
values = AshComputer.Executor.current_values(executor, :calculator)
values[:sum]  # => computed sum
values[:x]    # => input value
```

### Updating Inputs

Use frame-based execution to batch input changes:

```elixir
# Update input values in a frame
executor =
  executor
  |> AshComputer.Executor.start_frame()
  |> AshComputer.Executor.set_input(:calculator, :x, 42)
  |> AshComputer.Executor.commit_frame()

# All dependent vals are automatically recomputed
values = AshComputer.Executor.current_values(executor, :calculator)
values[:sum]     # => new sum with x=42
values[:product]  # => new product with x=42
```

**Cascade updates**: When inputs change, all dependent vals are recomputed in dependency order automatically.
**Batched execution**: Multiple input changes in a frame are processed efficiently in a single pass.

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
executor = AshComputer.apply_event(MyModule, :reset, executor)

# Apply event with payload (arity 2 handler)
payload = %{preset: :default}
executor = AshComputer.apply_event(MyModule, :load_preset, executor, payload)

# With explicit computer name
executor = AshComputer.apply_event(MyModule, :calculator, :reset, executor)
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
      handle fn _values, %{value: value} ->
        %{x: value}
      end
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, mount_computers(socket)}  # Helper from AshComputer.LiveView
  end
end
```

### Attaching External Computers

Use the `attach_computer/3` macro to reuse computers defined in external modules. This is useful for sharing common computer logic across multiple LiveViews without duplicating code:

```elixir
defmodule MyApp.Computers.Cart do
  use AshComputer

  computer :shopping_cart do
    input :items do
      initial []
    end

    input :discount_percent do
      initial 0
    end

    val :subtotal do
      compute fn %{items: items} -> Enum.sum(items) end
    end

    val :total do
      compute fn %{subtotal: subtotal, discount_percent: discount} ->
        subtotal * (1 - discount / 100)
      end
    end

    event :add_item do
      handle fn %{items: items}, %{"price" => price} ->
        %{items: [String.to_integer(price) | items]}
      end
    end

    event :clear do
      handle fn _values, _params -> %{items: []} end
    end
  end
end

# In your LiveView, attach the external computer
defmodule MyAppWeb.CheckoutLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  attach_computer MyApp.Computers.Cart, :shopping_cart

  @impl true
  def mount(_params, _session, socket) do
    {:ok, mount_computers(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <p>Items: <%= @shopping_cart_subtotal %></p>
      <p>Total: <%= @shopping_cart_total %></p>
      <button phx-click={event(:shopping_cart, :clear)}>Clear Cart</button>
    </div>
    """
  end
end
```

**Aliasing Attached Computers**: Use the `:as` option to customize the name used for events and assigns:

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  # Attach the same computer with a custom alias
  attach_computer MyApp.Computers.Sidebar, :sidebar, as: :main_sidebar

  @impl true
  def mount(_params, _session, socket) do
    {:ok, mount_computers(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Access using the alias name --%>
      <aside :if={not @main_sidebar_collapsed}>
        <button phx-click={event(:main_sidebar, :toggle)}>Toggle</button>
      </aside>
    </div>
    """
  end
end
```

**Key Points**:
- Attached computers work identically to inline computers
- Events are namespaced: `{alias_name}_{event_name}`
- Assigns follow the same pattern: `@{alias_name}_{input_or_val_name}`
- Use `event/2` macro for compile-time safe event references
- Multiple LiveViews can attach the same computer independently
- Each attachment maintains its own state

### Connecting Multiple Computers

For complex applications, you can compose multiple computers by wiring the output values (vals) from one computer to the input values of another. This is different from "attaching external computers" (which is about code reuse in LiveView modules) - connecting is about **data flow between independent computers**.

#### When to Use Connections vs Attachments

| Feature | Connecting Computers | Attaching External Computers |
|---------|---------------------|------------------------------|
| **Purpose** | Compose data flow between computers | Reuse computer definitions across LiveViews |
| **API** | `Executor.connect/2` | `attach_computer/3` macro |
| **Scope** | Programmatic, works with Executor | LiveView only |
| **Use Case** | Separation of concerns, complex pipelines | DRY principle for LiveView code |
| **State** | Single executor manages all computers | Each LiveView has independent state |

#### Basic Connection Setup

Use `Executor.connect/2` to wire computers together:

```elixir
defmodule MyApp.FilterComputer do
  use AshComputer

  computer :filters do
    input :status do
      initial "all"
    end

    input :category do
      initial "all"
    end

    val :filter_spec do
      compute fn %{status: status, category: category} ->
        [
          %{field: :status, value: status},
          %{field: :category, value: category}
        ]
        |> Enum.reject(fn %{value: v} -> v == "all" end)
      end
    end
  end
end

defmodule MyApp.QueryComputer do
  use AshComputer

  computer :query do
    # No initial value - will be connected from another computer
    input :filters

    input :page do
      initial 1
    end

    input :page_size do
      initial 20
    end

    val :results do
      compute fn %{filters: filters, page: page, page_size: size} ->
        # Execute database query using the filters
        Database.query(filters, page: page, page_size: size)
      end
    end

    val :total_count do
      compute fn %{filters: filters} ->
        Database.count(filters)
      end
    end
  end
end

# Wire the computers together with Executor
executor =
  AshComputer.Executor.new()
  |> AshComputer.Executor.add_computer(MyApp.FilterComputer, :filters)
  |> AshComputer.Executor.add_computer(MyApp.QueryComputer, :query)
  |> AshComputer.Executor.connect(
      from: {:filters, :filter_spec},
      to: {:query, :filters}
  )
  |> AshComputer.Executor.initialize()

# Access values from any computer
filter_values = AshComputer.Executor.current_values(executor, :filters)
query_values = AshComputer.Executor.current_values(executor, :query)
```

#### Required Inputs (No Initial Values)

When an input will be connected from another computer, you can omit the `initial` value:

```elixir
computer :downstream do
  # Required input - no initial value
  input :data_from_upstream

  input :local_setting do
    initial "default"
  end

  val :result do
    compute fn %{data_from_upstream: data, local_setting: setting} ->
      process(data, setting)
    end
  end
end
```

**Benefits**:
- Makes dependencies explicit
- Avoids specifying redundant initial values
- Computer won't initialize until connected input is provided
- Clear contract about what must be provided externally

#### Chaining Multiple Computers

You can create pipelines by chaining connections:

```elixir
defmodule MyApp.DashboardComputers do
  use AshComputer

  # Step 1: Filter management
  computer :filter_manager do
    input :selected_filters do
      initial %{}
    end

    val :filter_spec do
      compute fn %{selected_filters: filters} ->
        build_filter_spec(filters)
      end
    end
  end

  # Step 2: Data query
  computer :data_query do
    input :filters  # Connected from filter_manager

    val :raw_data do
      compute fn %{filters: filters} ->
        Database.query(filters)
      end
    end
  end

  # Step 3: Data processing
  computer :data_processor do
    input :raw_data  # Connected from data_query
    input :processing_mode do
      initial :summary
    end

    val :processed_data do
      compute fn %{raw_data: data, processing_mode: mode} ->
        process_data(data, mode)
      end
    end
  end

  # Step 4: Visualization
  computer :visualizer do
    input :data  # Connected from data_processor
    input :chart_type do
      initial :bar
    end

    val :chart_config do
      compute fn %{data: data, chart_type: type} ->
        build_chart(data, type)
      end
    end
  end
end

# Wire them all together
executor =
  AshComputer.Executor.new()
  |> AshComputer.Executor.add_computer(MyApp.DashboardComputers, :filters)
  |> AshComputer.Executor.add_computer(MyApp.DashboardComputers, :query)
  |> AshComputer.Executor.add_computer(MyApp.DashboardComputers, :processor)
  |> AshComputer.Executor.add_computer(MyApp.DashboardComputers, :viz)
  |> AshComputer.Executor.connect(
      from: {:filters, :filter_spec},
      to: {:query, :filters}
  )
  |> AshComputer.Executor.connect(
      from: {:query, :raw_data},
      to: {:processor, :raw_data}
  )
  |> AshComputer.Executor.connect(
      from: {:processor, :processed_data},
      to: {:viz, :data}
  )
  |> AshComputer.Executor.initialize()
```

#### Batched Execution Across Computers

Changes propagate efficiently through all connected computers using frame-based batching:

```elixir
# Update multiple inputs across different computers
executor =
  executor
  |> AshComputer.Executor.start_frame()
  |> AshComputer.Executor.set_input(:filters, :selected_filters, %{status: "active"})
  |> AshComputer.Executor.set_input(:processor, :processing_mode, :detailed)
  |> AshComputer.Executor.set_input(:viz, :chart_type, :line)
  |> AshComputer.Executor.commit_frame()

# All dependent vals across all computers are recomputed in a single pass
# Execution order is automatically determined by topological sorting
```

**How Batched Execution Works**:
1. `start_frame()` begins collecting input changes
2. `set_input()` records changes without computing
3. `commit_frame()` triggers computation:
   - Builds dependency graph across all computers
   - Topologically sorts affected nodes
   - Computes each val exactly once in correct order
   - Propagates changes through connections

#### Connection Rules and Best Practices

**Valid Connections**:
- Any val can connect to any input (same or different computer)
- Multiple vals can connect to different inputs of the same computer
- Cannot connect multiple vals to the same input

**Best Practices**:
1. **Separation of Concerns**: Each computer should handle one logical concern
   - Filters computer: manages filter state
   - Query computer: handles data fetching
   - Display computer: formats for UI

2. **Required Inputs**: Don't specify `initial` for inputs that will be connected

3. **Testing**: Each computer can be tested independently:
   ```elixir
   test "query computer handles filters correctly" do
     executor =
       AshComputer.Executor.new()
       |> AshComputer.Executor.add_computer(MyApp.QueryComputer, :query,
         initial: %{filters: [%{field: :status, value: "active"}]}
       )
       |> AshComputer.Executor.initialize()

     values = AshComputer.Executor.current_values(executor, :query)
     assert length(values[:results]) > 0
   end
   ```

4. **Batch Updates**: Always use frames when updating multiple inputs for efficiency

#### Using Connected Computers in LiveView

You can use the Executor with connected computers in LiveView by storing it in assigns:

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(MyApp.FilterComputer, :filters)
      |> AshComputer.Executor.add_computer(MyApp.QueryComputer, :query)
      |> AshComputer.Executor.connect(
          from: {:filters, :filter_spec},
          to: {:query, :filters}
      )
      |> AshComputer.Executor.initialize()

    {:ok, assign(socket, :executor, executor)}
  end

  def handle_event("update_filter", %{"status" => status}, socket) do
    executor =
      socket.assigns.executor
      |> AshComputer.Executor.start_frame()
      |> AshComputer.Executor.set_input(:filters, :status, status)
      |> AshComputer.Executor.commit_frame()

    # Extract values for template
    query_values = AshComputer.Executor.current_values(executor, :query)

    socket =
      socket
      |> assign(:executor, executor)
      |> assign(:results, query_values[:results])
      |> assign(:total_count, query_values[:total_count])

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <p>Total: <%= @total_count %></p>
      <div :for={item <- @results}>
        <%= item.name %>
      </div>
    </div>
    """
  end
end
```

**Note**: When using Executor directly in LiveView (not with `use AshComputer.LiveView`), you manage the executor manually in assigns and extract values as needed.

#### Benefits of Connecting Computers

1. **Separation of Concerns**: Each computer handles a single responsibility
2. **Reusability**: Computers can be tested and used independently
3. **Efficiency**: Batched execution with topological sorting
4. **Clear Data Flow**: Connections make dependencies explicit
5. **Maintainability**: Changes to one computer don't require touching others
6. **Composability**: Build complex systems from simple building blocks

#### Common Patterns

**Filter → Query → Display Pipeline**:
```elixir
executor
|> Executor.connect(from: {:filters, :filter_spec}, to: {:query, :filters})
|> Executor.connect(from: {:query, :results}, to: {:display, :data})
```

**Parallel Processing**:
```elixir
# Multiple computers consume the same data
executor
|> Executor.connect(from: {:source, :data}, to: {:processor_a, :input})
|> Executor.connect(from: {:source, :data}, to: {:processor_b, :input})
|> Executor.connect(from: {:source, :data}, to: {:processor_c, :input})
```

**Fan-in Pattern**:
```elixir
# Multiple sources feed into aggregator
# (Must use different input names)
executor
|> Executor.connect(from: {:source_a, :result}, to: {:aggregator, :input_a})
|> Executor.connect(from: {:source_b, :result}, to: {:aggregator, :input_b})
|> Executor.connect(from: {:source_c, :result}, to: {:aggregator, :input_c})
```

### Initializing Computers with Custom Input Values

To initialize computers with values from mount parameters (e.g., URL params) or session data, pass an initial inputs map to `mount_computers/2`:

```elixir
defmodule MyAppWeb.ProductLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  computer :cart do
    input :product_id do
      initial nil
    end

    input :quantity do
      initial 1
    end

    val :total_price do
      compute fn %{product_id: id, quantity: qty} ->
        # Fetch product price and calculate total
        case get_product_price(id) do
          nil -> 0
          price -> price * qty
        end
      end
    end
  end

  @impl true
  def mount(%{"product_id" => product_id}, _session, socket) do
    initial_inputs = %{
      cart: %{
        product_id: String.to_integer(product_id),
        quantity: 1
      }
    }
    {:ok, mount_computers(socket, initial_inputs)}
  end

  # Handle case where no product_id is provided
  def mount(_params, _session, socket) do
    {:ok, mount_computers(socket)}
  end
end
```

The initial inputs map structure is: `%{computer_name => %{input_name => value}}`

#### Multiple Computers with Initial Values

When you have multiple computers, you can initialize them independently:

```elixir
def mount(%{"user_id" => user_id, "cart_id" => cart_id}, _session, socket) do
  initial_inputs = %{
    user_profile: %{
      user_id: String.to_integer(user_id),
      preferences: load_user_preferences(user_id)
    },
    shopping_cart: %{
      cart_id: cart_id,
      items: []
    }
  }
  {:ok, mount_computers(socket, initial_inputs)}
end
```

#### Partial Input Overrides

You can override only specific inputs while leaving others at their default values:

```elixir
def mount(%{"theme" => theme}, session, socket) do
  initial_inputs = %{
    settings: %{
      theme: theme,
      # quantity keeps its default initial value of 1
      # Other inputs keep their defaults too
    }
  }
  {:ok, mount_computers(socket, initial_inputs)}
end
```

### Generated Event Handlers

LiveView integration automatically generates `handle_event/3` callbacks for each computer event:

```elixir
# Event :set_x generates handler for "calculator_set_x" event
# Event :reset generates handler for "calculator_reset" event
```

**Event naming pattern**: `{computer_name}_{event_name}`

### Manual Computer Updates from Custom Handlers

While AshComputer generates event handlers automatically, you can also update computer inputs manually from any custom event handler using the helper functions:

#### Update a Single Computer's Inputs

Use `update_computer_inputs/3` to update multiple inputs for a single computer:

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

    val :items_count do
      compute fn %{refresh_trigger: _trigger, filter: filter} ->
        # Recomputes whenever refresh_trigger or filter changes
        fetch_item_count(filter)
      end
    end
  end

  # Custom handler that triggers recomputation
  @impl true
  def handle_event("item_created", params, socket) do
    # Your business logic
    {:ok, _item} = create_item(params)

    # Trigger sidebar refresh by updating inputs
    updated_socket = update_computer_inputs(socket, :sidebar, %{
      refresh_trigger: System.monotonic_time(),
      filter: "recent"
    })

    {:noreply, updated_socket}
  end
end
```

#### Update Multiple Computers at Once

Use `update_computers/2` to update inputs across multiple computers:

```elixir
@impl true
def handle_event("reset_dashboard", _params, socket) do
  updated_socket = update_computers(socket, %{
    sidebar: %{
      filter: "all",
      refresh_trigger: 0
    },
    main_content: %{
      page: 1,
      sort_by: "date"
    },
    stats: %{
      period: "month"
    }
  })

  {:noreply, updated_socket}
end
```

**Use Cases for Manual Updates**:
- Triggering recomputation after external actions (database writes, API calls)
- Updating multiple computers in response to a single user action
- Integrating AshComputer with existing business logic
- Implementing custom refresh patterns not covered by defined events

**Important**: These helpers follow the same rules as events:
- Only input values can be updated (not vals)
- All dependent vals automatically recompute
- Updates are batched in a single frame for efficiency

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

# Build computer specs (used internally)
spec = AshComputer.computer_spec(MyModule)  # Default computer spec
spec = AshComputer.computer_spec(MyModule, :specific)

# List events for a computer
AshComputer.events(MyModule)  # => [:reset, :load]
AshComputer.events(MyModule, :calculator)  # => [:reset, :load]
```

### Executor Functions

```elixir
# Create an executor
executor = AshComputer.Executor.new()

# Add computers
executor = AshComputer.Executor.add_computer(executor, MyModule, :computer_name)

# Initialize (compute all initial values)
executor = AshComputer.Executor.initialize(executor)

# Update inputs with frames
executor =
  executor
  |> AshComputer.Executor.start_frame()
  |> AshComputer.Executor.set_input(:computer_name, :input_name, value)
  |> AshComputer.Executor.commit_frame()

# Get current values
values = AshComputer.Executor.current_values(executor, :computer_name)
```

## Best Practices

1. **Always provide initial values**: All inputs must have initial values for immediate computation
2. **Use meaningful names**: Name computers, inputs, vals, and events descriptively
3. **Prefer pattern matching**: Use pattern matching in compute functions for automatic dependency detection
4. **Return input changes from events**: Event handlers must return a map of input changes, not the full executor
5. **Use events for complex updates**: Encapsulate multi-input updates in named events
6. **Leverage dependency chains**: Build complex computations through chained vals
7. **Consider stateful mode carefully**: Only use stateful computers when previous values are needed
8. **Document with descriptions**: Use description fields for clarity
9. **Test computation chains**: Verify that updates cascade correctly through dependencies
10. **Use frames for batching**: Use start_frame/commit_frame to batch multiple input changes efficiently

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
    handle fn _values, %{"field" => field, "value" => value} ->
      field_atom = String.to_existing_atom(field)
      %{field_atom => value}
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
    handle fn _values, %{name: name} ->
      presets = %{
        low: %{setting_a: 10, setting_b: 20},
        medium: %{setting_a: 50, setting_b: 50},
        high: %{setting_a: 90, setting_b: 100}
      }

      Map.get(presets, name, presets.low)
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
# Error: Event must return a map of input changes
event :bad do
  handle fn values, _payload ->
    :ok  # Wrong return type
  end
end

# Fix: Always return a map of input changes
event :good do
  handle fn values, _payload ->
    %{x: values[:x] + 1}  # Returns map of input changes
  end
end

# Or return empty map for no changes
event :noop do
  handle fn _values, _payload ->
    %{}  # No changes
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
executor = AshComputer.Executor.add_computer(executor, MyModule, :missing)

# Fix: Check available computers first
AshComputer.computers(MyModule)  # => [:calculator]
executor = AshComputer.Executor.add_computer(executor, MyModule, :calculator)
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

### Removed Features

The following features were present in earlier versions but have been removed:

**Stateful Computers**: The `stateful?` option and arity-2 compute functions are no longer supported. If you need to track historical state, consider:
- Storing state in inputs and updating them via events
- Using a separate data store (database, ETS table)
- Implementing custom state management outside the computer

```elixir
# No longer works (removed feature)
computer :example do
  stateful? true  # This option has no effect

  val :average do
    compute fn %{value: v}, all_values ->  # Arity-2 not supported
      previous = all_values[:average] || 0
      (previous + v) / 2
    end
  end
end

# Modern approach: use inputs to track state
computer :example do
  input :values do
    initial []
  end

  val :average do
    compute fn %{values: values} ->
      if values == [], do: 0, else: Enum.sum(values) / length(values)
    end
  end

  event :add_value do
    handle fn %{values: values}, %{"value" => value} ->
      %{values: [value | values]}
    end
  end
end
```

**GenServer Instances**: `AshComputer.make_instance/1-3` no longer exists. Use:
- The Executor API directly for programmatic use
- LiveView integration for UI-driven computers
- Standard GenServer patterns if you need custom process management
