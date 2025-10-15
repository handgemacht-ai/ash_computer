defmodule AshComputer.LiveViewAttachmentsTest do
  @moduledoc """
  Tests for LiveView computer attachment functionality.
  """
  use ExUnit.Case
  use AshComputer.LiveViewTestHelper

  describe "attach_computer/3 macro" do
    defmodule BasicAttachmentLive do
      use Phoenix.LiveView
      use AshComputer.LiveView

      attach_computer AshComputer.TestComputers.Counter, :counter

      @impl true
      def mount(_params, _session, socket) do
        {:ok, mount_computers(socket)}
      end

      @impl true
      def render(assigns) do
        ~H"""
        <div>
          <span data-testid="count"><%= @counter_count %></span>
          <span data-testid="doubled"><%= @counter_doubled %></span>
          <button phx-click={event(:counter, :increment)} id="increment-btn">+</button>
          <button phx-click={event(:counter, :decrement)} id="decrement-btn">-</button>
          <button phx-click={event(:counter, :reset)} id="reset-btn">Reset</button>
        </div>
        """
      end
    end

    test "attaches computer from external module" do
      view = live_mount(BasicAttachmentLive)

      # Initial state
      assert has_element?(view, "[data-testid='count']", "0")
      assert has_element?(view, "[data-testid='doubled']", "0")

      # Increment
      view |> element("#increment-btn") |> render_click()
      assert has_element?(view, "[data-testid='count']", "1")
      assert has_element?(view, "[data-testid='doubled']", "2")

      # Decrement
      view |> element("#decrement-btn") |> render_click()
      assert has_element?(view, "[data-testid='count']", "0")
      assert has_element?(view, "[data-testid='doubled']", "0")

      # Reset
      view |> element("#increment-btn") |> render_click()
      view |> element("#increment-btn") |> render_click()
      assert has_element?(view, "[data-testid='count']", "2")
      view |> element("#reset-btn") |> render_click()
      assert has_element?(view, "[data-testid='count']", "0")
    end
  end

  describe "attach_computer with :as option" do
    defmodule AliasedAttachmentLive do
      use Phoenix.LiveView
      use AshComputer.LiveView

      attach_computer AshComputer.TestComputers.Sidebar, :sidebar, as: :main_sidebar

      @impl true
      def mount(_params, _session, socket) do
        {:ok, mount_computers(socket)}
      end

      @impl true
      def render(assigns) do
        ~H"""
        <div>
          <span data-testid="collapsed"><%= @main_sidebar_collapsed %></span>
          <span data-testid="width"><%= @main_sidebar_visible_width %></span>
          <span data-testid="section"><%= @main_sidebar_active_section %></span>
          <button phx-click={event(:main_sidebar, :toggle)} id="toggle-btn">Toggle</button>
          <form phx-submit={event(:main_sidebar, :set_active_section)} id="section-form">
            <input name="section" type="text" />
            <button type="submit">Set Section</button>
          </form>
        </div>
        """
      end
    end

    test "uses alias name for events and assigns" do
      view = live_mount(AliasedAttachmentLive)

      # Initial state
      assert has_element?(view, "[data-testid='collapsed']", "false")
      assert has_element?(view, "[data-testid='width']", "240")
      assert has_element?(view, "[data-testid='section']", "home")

      # Toggle
      view |> element("#toggle-btn") |> render_click()
      assert has_element?(view, "[data-testid='collapsed']", "true")
      assert has_element?(view, "[data-testid='width']", "60")

      # Set section
      view
      |> form("#section-form", %{"section" => "settings"})
      |> render_submit()

      assert has_element?(view, "[data-testid='section']", "settings")
    end
  end

  describe "multiple attachments" do
    defmodule MultipleAttachmentsLive do
      use Phoenix.LiveView
      use AshComputer.LiveView

      attach_computer AshComputer.TestComputers.Counter, :counter
      attach_computer AshComputer.TestComputers.Sidebar, :sidebar

      @impl true
      def mount(_params, _session, socket) do
        {:ok, mount_computers(socket)}
      end

      @impl true
      def render(assigns) do
        ~H"""
        <div>
          <div id="counter-section">
            <span data-testid="count"><%= @counter_count %></span>
            <button phx-click={event(:counter, :increment)} id="counter-increment">+</button>
          </div>
          <div id="sidebar-section">
            <span data-testid="collapsed"><%= @sidebar_collapsed %></span>
            <button phx-click={event(:sidebar, :toggle)} id="sidebar-toggle">Toggle</button>
          </div>
        </div>
        """
      end
    end

    test "multiple attached computers work independently" do
      view = live_mount(MultipleAttachmentsLive)

      # Initial state
      assert has_element?(view, "[data-testid='count']", "0")
      assert has_element?(view, "[data-testid='collapsed']", "false")

      # Update counter
      view |> element("#counter-increment") |> render_click()
      assert has_element?(view, "[data-testid='count']", "1")
      assert has_element?(view, "[data-testid='collapsed']", "false")

      # Update sidebar
      view |> element("#sidebar-toggle") |> render_click()
      assert has_element?(view, "[data-testid='count']", "1")
      assert has_element?(view, "[data-testid='collapsed']", "true")
    end
  end

  describe "mixing local and attached computers" do
    defmodule MixedComputersLive do
      use Phoenix.LiveView
      use AshComputer.LiveView

      attach_computer AshComputer.TestComputers.Counter, :counter

      computer :local_state do
        input :message do
          initial "Hello"
        end

        val :uppercase do
          compute fn %{message: message} -> String.upcase(message) end
        end

        event :set_message do
          handle fn _values, %{"text" => text} ->
            %{message: text}
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
          <div id="counter-section">
            <span data-testid="count"><%= @counter_count %></span>
            <button phx-click={event(:counter, :increment)} id="counter-increment">+</button>
          </div>
          <div id="local-section">
            <span data-testid="message"><%= @local_state_message %></span>
            <span data-testid="uppercase"><%= @local_state_uppercase %></span>
            <form phx-submit={event(:local_state, :set_message)} id="message-form">
              <input name="text" type="text" />
              <button type="submit">Set</button>
            </form>
          </div>
        </div>
        """
      end
    end

    test "local and attached computers work together" do
      view = live_mount(MixedComputersLive)

      # Initial state
      assert has_element?(view, "[data-testid='count']", "0")
      assert has_element?(view, "[data-testid='message']", "Hello")
      assert has_element?(view, "[data-testid='uppercase']", "HELLO")

      # Update attached computer
      view |> element("#counter-increment") |> render_click()
      assert has_element?(view, "[data-testid='count']", "1")

      # Update local computer
      view
      |> form("#message-form", %{"text" => "World"})
      |> render_submit()

      assert has_element?(view, "[data-testid='message']", "World")
      assert has_element?(view, "[data-testid='uppercase']", "WORLD")
      assert has_element?(view, "[data-testid='count']", "1")
    end
  end

  describe "initial inputs with attached computers" do
    defmodule InitialInputsLive do
      use Phoenix.LiveView
      use AshComputer.LiveView

      attach_computer AshComputer.TestComputers.Cart, :shopping_cart, as: :cart

      @impl true
      def mount(_params, _session, socket) do
        initial_inputs = %{
          cart: %{
            items: [100, 200, 300],
            discount_percent: 10
          }
        }

        {:ok, mount_computers(socket, initial_inputs)}
      end

      @impl true
      def render(assigns) do
        ~H"""
        <div>
          <span data-testid="count"><%= @cart_item_count %></span>
          <span data-testid="subtotal"><%= @cart_subtotal %></span>
          <span data-testid="discount"><%= @cart_discount_amount %></span>
          <span data-testid="total"><%= @cart_total %></span>
          <form phx-submit={event(:cart, :add_item)} id="add-form">
            <input name="price" type="number" value="50" />
            <button type="submit">Add</button>
          </form>
          <button phx-click={event(:cart, :clear)} id="clear-btn">Clear</button>
        </div>
        """
      end
    end

    test "initial inputs work with attached computers using alias" do
      view = live_mount(InitialInputsLive)

      # Check initial state with custom inputs
      assert has_element?(view, "[data-testid='count']", "3")
      assert has_element?(view, "[data-testid='subtotal']", "600")
      assert has_element?(view, "[data-testid='discount']", "60")
      assert has_element?(view, "[data-testid='total']", "540")

      # Add item
      view
      |> form("#add-form", %{"price" => "150"})
      |> render_submit()

      assert has_element?(view, "[data-testid='count']", "4")
      assert has_element?(view, "[data-testid='subtotal']", "750")
      assert has_element?(view, "[data-testid='total']", "675")

      # Clear
      view |> element("#clear-btn") |> render_click()
      assert has_element?(view, "[data-testid='count']", "0")
      assert has_element?(view, "[data-testid='total']", "0")
    end
  end

  describe "get_all_computers/1" do
    test "returns local computers only" do
      defmodule LocalOnlyLive do
        use Phoenix.LiveView
        use AshComputer.LiveView

        computer :test do
          input :x do
            initial 0
          end
        end
      end

      all_computers = AshComputer.LiveView.get_all_computers(LocalOnlyLive)
      assert all_computers == [{:test, LocalOnlyLive, :test}]
    end

    test "returns attached computers only" do
      defmodule AttachedOnlyLive do
        use Phoenix.LiveView
        use AshComputer.LiveView

        attach_computer AshComputer.TestComputers.Counter, :counter
      end

      all_computers = AshComputer.LiveView.get_all_computers(AttachedOnlyLive)

      assert all_computers == [
               {:counter, AshComputer.TestComputers.Counter, :counter}
             ]
    end

    test "returns both local and attached computers" do
      defmodule MixedLive do
        use Phoenix.LiveView
        use AshComputer.LiveView

        attach_computer AshComputer.TestComputers.Counter, :counter
        attach_computer AshComputer.TestComputers.Sidebar, :sidebar, as: :main_sidebar

        computer :local do
          input :x do
            initial 0
          end
        end
      end

      all_computers = AshComputer.LiveView.get_all_computers(MixedLive)

      assert {:local, MixedLive, :local} in all_computers
      assert {:counter, AshComputer.TestComputers.Counter, :counter} in all_computers
      assert {:main_sidebar, AshComputer.TestComputers.Sidebar, :sidebar} in all_computers
      assert length(all_computers) == 3
    end
  end
end
