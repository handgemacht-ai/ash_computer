defmodule AshComputer.LiveViewIntegrationTest do
  @moduledoc """
  Tests the LiveView integration at a unit level without requiring a full Phoenix app.
  """
  use ExUnit.Case
  use AshComputer.LiveViewTestHelper

  defmodule TestLive do
    use Phoenix.LiveView
    use AshComputer.LiveView

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

      event :set_x do
        handle fn _values, %{"value" => value} ->
          %{x: String.to_integer(value)}
        end
      end

      event :reset do
        handle fn _values, _params ->
          %{x: 10, y: 5}
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
        <div id="calculator-values">
          <span data-testid="x-value"><%=@calculator_x%></span>
          <span data-testid="y-value"><%=@calculator_y%></span>
          <span data-testid="sum-value"><%=@calculator_sum%></span>
          <span data-testid="product-value"><%=@calculator_product%></span>
        </div>

        <form phx-submit={event(:calculator, :set_x)} id="set-x-form">
          <input name="value" type="number" value={@calculator_x} />
          <button type="submit">Set X</button>
        </form>

        <button phx-click={event(:calculator, :reset)} id="reset-button">Reset</button>
      </div>
      """
    end
  end

  describe "helper functions" do
    test "computer builds correctly" do
      # Build a computer directly
      computer = AshComputer.computer(TestLive, :calculator)

      # Check initial values
      assert computer.values[:x] == 10
      assert computer.values[:y] == 5
      assert computer.values[:sum] == 15
      assert computer.values[:product] == 50

      # Update a value
      computer = AshComputer.Runtime.handle_input(computer, :x, 20)

      # Check computed values update
      assert computer.values[:x] == 20
      assert computer.values[:y] == 5
      assert computer.values[:sum] == 25
      assert computer.values[:product] == 100
    end
  end

  describe "event handler generation" do
    test "module defines handle_event callbacks for each computer event" do
      # Check that the functions were generated
      assert function_exported?(TestLive, :handle_event, 3)

      # Get expected event names using compile-time safe functions
      expected_events = AshComputer.Info.event_names(TestLive, :calculator)

      # Verify the expected events match what we define in the computer
      assert "calculator_set_x" in expected_events
      assert "calculator_reset" in expected_events
      assert length(expected_events) == 2

      # Test that specific event names can be retrieved
      assert AshComputer.Info.event_name(TestLive, :calculator, :set_x) == "calculator_set_x"
      assert AshComputer.Info.event_name(TestLive, :calculator, :reset) == "calculator_reset"

      # Test that non-existent events return nil (runtime check)
      assert AshComputer.Info.event_name(TestLive, :calculator, :nonexistent) == nil

      for _event <- expected_events do
        # We can't easily test the actual behavior without a full Phoenix setup,
        # but we can verify the module would handle these events
        assert TestLive.__info__(:functions)
               |> Keyword.get_values(:handle_event)
               |> Enum.member?(3)
      end
    end
  end

  describe "LiveView rendering and events" do
    test "renders initial state correctly" do
      view = live_mount(TestLive)
      html = render(view)

      # Initial x value
      assert html =~ "10"
      # Initial y value
      assert html =~ "5"
      # Initial sum
      assert html =~ "15"
      # Initial product
      assert html =~ "50"

      # Verify specific elements exist
      assert has_element?(view, "[data-testid='x-value']", "10")
      assert has_element?(view, "[data-testid='y-value']", "5")
      assert has_element?(view, "[data-testid='sum-value']", "15")
      assert has_element?(view, "[data-testid='product-value']", "50")
    end

    test "handles set_x event correctly" do
      view = live_mount(TestLive)

      # Trigger the set_x event
      view
      |> form("#set-x-form", %{"value" => "20"})
      |> render_submit()

      # Verify the values were updated
      assert has_element?(view, "[data-testid='x-value']", "20")
      # Unchanged
      assert has_element?(view, "[data-testid='y-value']", "5")
      # 20 + 5
      assert has_element?(view, "[data-testid='sum-value']", "25")
      # 20 * 5
      assert has_element?(view, "[data-testid='product-value']", "100")
    end

    test "handles reset event correctly" do
      view = live_mount(TestLive)

      # First change x to something else
      view
      |> form("#set-x-form", %{"value" => "99"})
      |> render_submit()

      # Verify it changed
      assert has_element?(view, "[data-testid='x-value']", "99")

      # Now reset
      view |> element("#reset-button") |> render_click()

      # Verify values are back to defaults
      assert has_element?(view, "[data-testid='x-value']", "10")
      assert has_element?(view, "[data-testid='y-value']", "5")
      assert has_element?(view, "[data-testid='sum-value']", "15")
      assert has_element?(view, "[data-testid='product-value']", "50")
    end
  end

  describe "computer info" do
    test "computers are accessible via AshComputer.Info" do
      computer_names = AshComputer.Info.computer_names(TestLive)
      assert computer_names == [:calculator]

      computer = AshComputer.Info.computer(TestLive, :calculator)
      assert computer.name == :calculator
      assert length(computer.inputs) == 2
      assert length(computer.vals) == 2
      assert length(computer.events) == 2
    end

    test "event names are accessible via compile-time safe functions" do
      # Test event_names/2 function
      event_names = AshComputer.Info.event_names(TestLive, :calculator)
      assert event_names == ["calculator_set_x", "calculator_reset"]

      # Test event_name/3 function
      assert AshComputer.Info.event_name(TestLive, :calculator, :set_x) == "calculator_set_x"
      assert AshComputer.Info.event_name(TestLive, :calculator, :reset) == "calculator_reset"

      # Test non-existent event returns nil
      assert AshComputer.Info.event_name(TestLive, :calculator, :nonexistent) == nil

      # Test non-existent computer returns nil/empty list
      assert AshComputer.Info.event_names(TestLive, :nonexistent) == []
      assert AshComputer.Info.event_name(TestLive, :nonexistent, :any) == nil
    end

    test "event/2 macro works correctly in templates" do
      # The real test of the event/2 macro is that the templates compile successfully
      # and produce the correct event names. This is already proven by the rendering tests
      # above which use event(:calculator, :set_x) and event(:calculator, :reset)

      # We can verify that the event names in the rendered HTML match what we expect
      view = live_mount(TestLive)
      html = render(view)

      # The form should have the correct phx-submit value
      assert html =~ ~s(phx-submit="calculator_set_x")

      # The button should have the correct phx-click value
      assert html =~ ~s(phx-click="calculator_reset")

      # Note: If we had used invalid event names like event(:calculator, :nonexistent)
      # or event(:nonexistent, :reset), the template compilation would have failed
      # with a helpful compile-time error message listing available events/computers.
    end
  end
end
