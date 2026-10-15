# AshComputer

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/handgemacht-ai/ash_computer/blob/main/LICENSE)

A reactive computation DSL for Elixir, powered by [Spark](https://github.com/ash-project/spark). Based on [Lucassifoni/computer](https://github.com/Lucassifoni/computer).

AshComputer provides a declarative way to define computational models that automatically update when their inputs change. Perfect for building calculators, form validations, reactive UIs, and any system requiring cascading computations.

## Features

- 🔄 **Reactive Computations** - Values automatically update when dependencies change
- 🎯 **Declarative DSL** - Define computers with a clean, readable syntax
- ⚡ **Automatic Dependency Resolution** - Dependencies are inferred from your compute functions
- 🎭 **Event System** - Named events for complex state mutations
- 💥 **Side Effects** - Events can run an effect and turn its result into input changes, flash messages and navigation
- 🖥️ **LiveView Integration** - First-class support for Phoenix LiveView
- 🧮 **Chained Computations** - Build complex calculations through dependent values
- 🔗 **Multi-Computer Composition** - Wire multiple computers together for separation of concerns

## Installation

AshComputer is not published on Hex. Add it to your list of dependencies in `mix.exs` from GitHub:

```elixir
def deps do
  [
    {:ash_computer, github: "handgemacht-ai/ash_computer", tag: "v0.3.0"}
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

## Effects

A pure event (`handle`) only turns values and params into input changes. An event can instead run a side effect, such as sending an e-mail or calling an API, and turn the result into input changes. For that, declare it with two options:

- `run` is a function of arity 3. It receives the current values, the event params and an `AshComputer.Context`, and returns `{:ok, result}` or `{:error, reason}`.
- `handle_result` is a pure function of arity 3. It receives that `{:ok, _}` or `{:error, _}`, the current values and the params, and returns an `AshComputer.Reply`.

An event has either `handle` or `run`, never both. `handle_result` is required with `run` and not allowed without it. The compiler checks this and the arities of the captures.

A reply is plain data: the input changes the event wants, plus the outcomes the host should carry out (flash messages, a navigation, a patch, a redirect and client events). The core never performs the outcomes; the LiveView adapter does.

### Example computer

```elixir
defmodule MyApp.Invoices do
  use AshComputer

  alias AshComputer.Context
  alias AshComputer.Reply

  computer :invoice do
    input :status do
      initial :draft
    end

    input :error do
      initial nil
    end

    val :label do
      compute fn %{status: status} -> "Invoice is #{status}" end
    end

    event :send,
      run: &__MODULE__.send_invoice/3,
      handle_result: &__MODULE__.sent/3

    event :delivery_confirmed, handle: &__MODULE__.delivery_confirmed/1
  end

  # The effect: runs synchronously, gets the actor and tenant from the context.
  def send_invoice(_values, %{"to" => to}, %Context{} = ctx) do
    ctx.extra.mailer.deliver(ctx.tenant, ctx.actor, to)
  end

  # The result handler: pure, returns a Reply.
  def sent({:ok, _receipt}, _values, _params) do
    Reply.new(status: :sent, error: nil)
    |> Reply.flash(:info, "Invoice sent")
  end

  def sent({:error, reason}, _values, _params) do
    Reply.new(error: reason)
    |> Reply.flash(:error, "Could not send the invoice")
  end

  def delivery_confirmed(_values), do: %{status: :delivered}
end
```

`AshComputer.Context` has the fields `actor`, `tenant` and `extra`. Build one with `AshComputer.Context.new/1` from a keyword list or map; any other key raises `ArgumentError`.

### Reply

Build a reply with `AshComputer.Reply`:

| Function | Effect on the socket |
|---|---|
| `Reply.new(changes)` / `Reply.change(reply, changes)` | Sets inputs (keyword list or map; later changes win) |
| `Reply.flash(reply, kind, message)` | `Phoenix.LiveView.put_flash/3`; may be called repeatedly |
| `Reply.navigate(reply, path)` | `Phoenix.LiveView.push_navigate/2` |
| `Reply.patch(reply, path)` | `Phoenix.LiveView.push_patch/2` |
| `Reply.redirect(reply, path)` | `Phoenix.LiveView.redirect/2` |
| `Reply.push_event(reply, name, payload \\ %{})` | `Phoenix.LiveView.push_event/3`, for a JS hook |

A reply may ask for at most one of `navigate`, `patch` and `redirect`; the LiveView raises `ArgumentError` if it holds more than one.

### Using it in a LiveView

```elixir
defmodule MyAppWeb.InvoiceLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  attach_computer MyApp.Invoices, :invoice

  # Optional. Called with the socket for every event; the result is handed to `run` only.
  @impl AshComputer.LiveView
  def computer_context(socket) do
    [
      actor: socket.assigns.current_user,
      tenant: socket.assigns.current_tenant,
      extra: %{mailer: MyApp.Mailer}
    ]
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, mount_computers(socket)}
  end

  # A message from elsewhere runs an event the same way a click does.
  @impl true
  def handle_info({:delivery_confirmed, _invoice_id}, socket) do
    {:noreply, run_event(socket, :invoice, :delivery_confirmed, %{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <p>{@invoice_label}</p>
    <p :if={@invoice_error}>Error: {inspect(@invoice_error)}</p>

    <form phx-submit={event(:invoice, :send)}>
      <input type="email" name="to" />
      <button type="submit">Send</button>
    </form>
    """
  end
end
```

- `computer_context/1` is an optional callback. It receives the socket and returns an `AshComputer.Context`, or a keyword list or map with `:actor`, `:tenant` and `:extra`. Without it, the context is empty (`actor` and `tenant` are `nil`, `extra` is `%{}`).
- The context is built from the socket for every event and handed to `run`. It is not stored in the executor or in the socket assigns.
- `run_event(socket, computer, event, params)` does what a `phx-click` on the event does and returns the socket. Use it in `mount/3`, `handle_info/2` or any other callback, after `mount_computers/1`. `computer` is the computer's name, or its alias for an attached computer. It also works for pure events.
- For every event the adapter first syncs the reply's input changes to the assigns, then applies the flash messages, client events and the navigation, patch or redirect.

### Rules to know

- **Effects run synchronously.** `run` runs in the LiveView process and blocks it until it returns.
- **A crash in `run` stays a crash.** Exceptions in `run` and `handle_result` are not rescued into `{:error, _}`. Return `{:error, reason}` for failures you expect. A `run` that returns anything other than `{:ok, _}` or `{:error, _}`, or a `handle_result` that returns something other than an `%AshComputer.Reply{}`, raises `ArgumentError`.
- **Events may change only inputs.** This holds for pure and effect events, in `apply_event`, `dispatch_event` and in the LiveView. A change to a val raises `ArgumentError` naming the offending keys.
- **`apply_event` is for pure events.** It raises for an effect event; use `AshComputer.dispatch_event/6` instead.

### Known limitation: nil and false fall back to the initial value

Setting an input to `nil` or `false` does not keep that value. The executor resolves an input as the connected value, else the current value, else the `initial` value, using `||`. A `nil` or `false` input therefore takes its `initial` value again. This applies to every way of setting an input, including `Reply.new/1`, pure event results and `update_computer_inputs/3`.

For an input whose `initial` is `nil` (or that has none), `nil` works as expected. An input with `initial true` cannot be set to `false`, and an input with a non-nil `initial` cannot be reset to `nil`. Inputs that carry results or errors, like `:error` above, should start as `nil`, and booleans should be modelled as atoms such as `:on` and `:off`. This is planned to be fixed in a later release.

### Running effects without a LiveView

`AshComputer.dispatch_event/6` runs an event on an executor and returns `{executor, reply}`. It takes the module, the computer name, the event name, the executor, the params and the context (an `AshComputer.Context` or a keyword list). The option `as:` (7th argument) names the computer in the executor when it differs from the name in the module, as for an attached computer. `AshComputer.map_result/6` runs only the `handle_result` half from a result you already have.

### Testing an effect event

Pass a fake collaborator through the context's `extra` field, then check the values and the reply:

```elixir
defmodule MyApp.InvoicesTest do
  use ExUnit.Case, async: true

  alias AshComputer.Executor

  defmodule FakeMailer do
    def deliver(_tenant, _actor, "broken@example.com"), do: {:error, :mailbox_full}
    def deliver(tenant, actor, to), do: {:ok, %{tenant: tenant, actor: actor, to: to}}
  end

  defp executor do
    Executor.new()
    |> Executor.add_computer(MyApp.Invoices, :invoice)
    |> Executor.initialize()
  end

  defp ctx do
    AshComputer.Context.new(actor: "alice", tenant: "acme", extra: %{mailer: FakeMailer})
  end

  test "a delivered invoice becomes sent and asks for a flash" do
    {executor, reply} =
      AshComputer.dispatch_event(
        MyApp.Invoices, :invoice, :send, executor(), %{"to" => "a@example.com"}, ctx()
      )

    values = Executor.current_values(executor, :invoice)
    assert values.status == :sent
    assert values.label == "Invoice is sent"
    assert reply.flash == [info: "Invoice sent"]
  end

  test "a failed delivery keeps the status and stores the error" do
    {executor, reply} =
      AshComputer.dispatch_event(
        MyApp.Invoices, :invoice, :send, executor(), %{"to" => "broken@example.com"}, ctx()
      )

    values = Executor.current_values(executor, :invoice)
    assert values.status == :draft
    assert values.error == :mailbox_full
    assert reply.flash == [error: "Could not send the invoice"]
  end

  test "handle_result can be tested without running the effect" do
    {executor, _reply} =
      AshComputer.map_result(MyApp.Invoices, :invoice, :send, executor(), {:error, :timeout}, %{})

    assert Executor.current_values(executor, :invoice).error == :timeout
  end
end
```

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

### Multi-Computer Composition

For complex systems, you can compose multiple computers together by wiring outputs from one computer to inputs of another:

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
      end
    end
  end
end

defmodule MyApp.QueryComputer do
  use AshComputer

  computer :query do
    # No initial value - will be connected from filters computer
    input :filters

    input :page do
      initial 1
    end

    val :results do
      compute fn %{filters: filters, page: page} ->
        # Build and execute query using filters
        Database.query(filters, page: page)
      end
    end
  end
end

# Wire the computers together
executor =
  AshComputer.Executor.new()
  |> AshComputer.Executor.add_computer(MyApp.FilterComputer, :filters)
  |> AshComputer.Executor.add_computer(MyApp.QueryComputer, :query)
  |> AshComputer.Executor.connect(
      from: {:filters, :filter_spec},
      to: {:query, :filters}
  )
  |> AshComputer.Executor.initialize()

# Update filter, query automatically recomputes
executor =
  executor
  |> AshComputer.Executor.start_frame()
  |> AshComputer.Executor.set_input(:filters, :status, "active")
  |> AshComputer.Executor.commit_frame()

values = AshComputer.Executor.current_values(executor, :query)
# results are automatically updated based on new filters
```

**Benefits**:
- Clean separation of concerns between computers
- Efficient batched execution across all connected computers
- Each computer remains independently testable
- Changes propagate automatically through connections

For detailed documentation on multi-computer composition patterns, see [usage-rules.md](usage-rules.md).

## Key Concepts

- **Inputs**: External values that can be updated
- **Vals**: Computed values that automatically update when dependencies change
- **Events**: Named handlers for complex state mutations; pure (`handle`) or with a side effect (`run` and `handle_result`)
- **Dependencies**: Automatically detected from pattern matches in compute functions
- **Connections**: Wire outputs from one computer to inputs of another for composition

## Why AshComputer?

- **Declarative**: Focus on what to compute, not how to manage updates
- **Reactive**: Changes cascade automatically through your computation graph
- **Testable**: Pure computation functions are easy to test
- **Composable**: Build complex systems from simple, reusable computers that can be wired together
- **Integrated**: Works seamlessly with Phoenix LiveView and other Elixir libraries
- **Efficient**: Batched execution across multiple computers with automatic topological sorting

## Documentation

Module docs can be built locally with `mix docs`.

For AI assistance with this library, see [usage-rules.md](usage-rules.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.