defmodule AshComputer.LiveViewEffectsTest do
  use ExUnit.Case
  use AshComputer.LiveViewTestHelper

  import ExUnit.CaptureLog

  alias AshComputer.LiveView.Helpers
  alias AshComputer.TestLive.Effects

  defp signed_in_conn, do: Plug.Test.init_test_session(build_conn(), %{"signed_in" => true})

  defp text(view, id), do: view |> element("##{id}") |> render()

  defp send_event(view, name, params \\ %{}), do: render_click(view, "shop_#{name}", params)

  defp socket_for(view_module) do
    %Phoenix.LiveView.Socket{view: view_module, assigns: %{__changed__: %{}, flash: %{}}}
    |> Helpers.mount_computers()
  end

  describe "an effect event end to end" do
    test "runs the effect, changes inputs and syncs assigns" do
      {:ok, view, html} = live(signed_in_conn(), "/effects")
      assert html =~ "status: idle"

      send_event(view, :pay)

      assert text(view, "status") =~ "paid"
      assert text(view, "label") =~ "status: paid"
      assert text(view, "flash-info") =~ "Paid"
    end

    test "turns an error result into inputs and an error flash" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :pay, %{"fail" => "card declined"})

      assert text(view, "status") =~ "failed"
      assert text(view, "error") =~ "card declined"
      assert text(view, "flash-error") =~ "Failed: card declined"
    end
  end

  describe "context from computer_context/1" do
    test "the effect sees actor, tenant and extra" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :pay)

      seen = text(view, "seen")
      assert seen =~ "Alice"
      assert seen =~ "tenant_set: true"
      assert seen =~ inspect(Effects)
    end

    test "the context is empty when the LiveView has no computer_context/1" do
      defmodule NoContextLive do
        use Phoenix.LiveView
        use AshComputer.LiveView

        computer :c do
          input :seen do
            initial nil
          end

          event :look, run: &__MODULE__.look/3, handle_result: &__MODULE__.looked/3
        end

        def look(_values, _params, ctx), do: {:ok, ctx}
        def looked({:ok, ctx}, _values, _params), do: AshComputer.Reply.new(seen: ctx)

        @impl true
        def mount(_params, _session, socket), do: {:ok, mount_computers(socket)}

        @impl true
        def render(assigns), do: ~H"<p id='seen'>{inspect(@c_seen)}</p>"
      end

      view = live_mount(NoContextLive)
      render_click(view, "c_look", %{})

      assert text(view, "seen") =~ "actor: nil"
      assert text(view, "seen") =~ "tenant: nil"
      assert text(view, "seen") =~ "extra: %{}"
    end

    test "an invalid computer_context/1 result raises" do
      defmodule BadContextLive do
        use Phoenix.LiveView
        use AshComputer.LiveView

        computer :c do
          input :a do
            initial 0
          end

          event :go, run: &__MODULE__.go/3, handle_result: &__MODULE__.went/3
        end

        def go(_values, _params, _ctx), do: {:ok, 1}
        def went({:ok, _}, _values, _params), do: AshComputer.Reply.new(a: 1)

        @impl true
        def computer_context(_socket), do: :nope

        @impl true
        def mount(_params, _session, socket), do: {:ok, mount_computers(socket)}

        @impl true
        def render(assigns), do: ~H"<p>{@c_a}</p>"
      end

      assert_raise ArgumentError, ~r/Context must be built/, fn ->
        BadContextLive |> socket_for() |> Helpers.run_event(:c, :go, %{})
      end
    end

    test "actor and tenant never end up in assigns, state or logs" do
      actor_token = Effects.secret_actor().token
      tenant = Effects.secret_tenant()

      log =
        capture_log([level: :debug], fn ->
          {:ok, view, _html} = live(signed_in_conn(), "/effects")
          send_event(view, :pay)
          send_event(view, :pay, %{"fail" => "declined"})
          send(view.pid, {:tick, "t1"})
          render(view)

          state = :sys.get_state(view.pid)
          dumped = inspect(state.socket.assigns, limit: :infinity)
          executor = inspect(state.socket.assigns.__executor__, limit: :infinity)

          refute dumped =~ actor_token
          refute dumped =~ tenant
          refute executor =~ actor_token
          refute executor =~ tenant
          refute html_of(view) =~ actor_token
        end)

      refute log =~ actor_token
      refute log =~ tenant
      assert log =~ "shop_pay"
    end

    defp html_of(view), do: render(view)
  end

  describe "reply outcomes" do
    test "flash messages" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :outcome, %{"kind" => "flash"})

      assert text(view, "flash-info") =~ "one"
      assert text(view, "flash-error") =~ "two"
    end

    test "navigate" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :outcome, %{"kind" => "navigate"})

      assert_redirect(view, "/elsewhere")
    end

    test "patch" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :outcome, %{"kind" => "patch"})

      assert_patch(view, "/effects/next")
      assert text(view, "page") =~ "next"
    end

    test "redirect" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :outcome, %{"kind" => "redirect"})

      assert_redirect(view, "/elsewhere")
    end

    test "push_event" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :outcome, %{"kind" => "push_event"})

      assert_push_event(view, "pinged", %{id: 1})
      assert_push_event(view, "again", %{})
    end

    test "the input changes of the reply are synced before the outcomes" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :outcome, %{"kind" => "flash"})

      assert text(view, "status") =~ "outcome"
    end

    test "asking for more than one of navigate, patch and redirect raises" do
      socket = socket_for(Effects)

      assert_raise ArgumentError, ~r/at most one of navigate, patch and redirect/, fn ->
        Helpers.run_event(socket, :shop, :outcome, %{"kind" => "navigate_and_patch"})
      end
    end
  end

  describe "run_event/4" do
    test "runs an event from mount" do
      {:ok, view, html} = live(signed_in_conn(), "/effects?boot=1")

      assert html =~ "status: booted"
      assert text(view, "seen") =~ "Alice"
    end

    test "runs an event from handle_info" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send(view.pid, {:tick, "msg-1"})

      assert render(view) =~ "status: ticked"
      assert text(view, "ticks") =~ "1"
      assert text(view, "error") =~ "msg-1"

      send(view.pid, {:tick, "msg-2"})
      render(view)
      assert text(view, "ticks") =~ "2"
    end

    test "raises for an unknown computer" do
      assert_raise ArgumentError, ~r/Unknown computer :nope.*Known computers: \[:shop\]/, fn ->
        Helpers.run_event(socket_for(Effects), :nope, :pay, %{})
      end
    end

    test "raises for an unknown event" do
      assert_raise ArgumentError, ~r/Unknown event :nope/, fn ->
        Helpers.run_event(socket_for(Effects), :shop, :nope, %{})
      end
    end

    test "raises when the computers were not mounted" do
      socket = %Phoenix.LiveView.Socket{view: Effects, assigns: %{__changed__: %{}}}

      assert_raise ArgumentError, ~r/Did you call mount_computers/, fn ->
        Helpers.run_event(socket, :shop, :pay, %{})
      end
    end
  end

  describe "errors stay errors" do
    test "a crash in an effect crashes the LiveView" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")
      Process.flag(:trap_exit, true)

      capture_log(fn ->
        assert {{%RuntimeError{message: "effect exploded"}, _stack}, _} =
                 catch_exit(send_event(view, :crash))
      end)
    end

    test "a crash in an effect raises from run_event/4" do
      assert_raise RuntimeError, "effect exploded", fn ->
        Helpers.run_event(socket_for(Effects), :shop, :crash, %{})
      end
    end

    test "an event cannot change a non-input" do
      assert_raise ArgumentError, ~r/tried to modify non-input values: \[:label\]/, fn ->
        Helpers.run_event(socket_for(Effects), :shop, :touch_val, %{})
      end
    end
  end

  describe "pure events" do
    test "with handle arity 1 and 2 behave as before" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :set, %{"status" => "paid"})
      assert text(view, "status") =~ "paid"

      send_event(view, :reset)
      assert text(view, "status") =~ "idle"
    end

    test "return no flash, navigation or push" do
      {:ok, view, _html} = live(signed_in_conn(), "/effects")

      send_event(view, :set, %{"status" => "paid"})

      refute has_element?(view, "#flash-info")
      refute has_element?(view, "#flash-error")
    end

    test "can run from run_event/4" do
      socket = socket_for(Effects) |> Helpers.run_event(:shop, :set, %{"status" => "paid"})

      assert socket.assigns.shop_status == :paid
      assert socket.assigns.shop_label == "status: paid"
    end
  end

  describe "attached under another name" do
    defmodule EffectComputer do
      use AshComputer

      computer :job do
        input :done do
          initial false
        end

        event :finish, run: &__MODULE__.finish/3, handle_result: &__MODULE__.finished/3
      end

      def finish(_values, _params, _ctx), do: {:ok, true}
      def finished({:ok, done}, _values, _params), do: AshComputer.Reply.new(done: done)
    end

    defmodule AliasedLive do
      use Phoenix.LiveView
      use AshComputer.LiveView

      attach_computer(EffectComputer, :job, as: :task)
      attach_computer(EffectComputer, :job)

      @impl true
      def mount(_params, _session, socket), do: {:ok, mount_computers(socket)}

      @impl true
      def render(assigns), do: ~H"<p>{@job_done}</p>"
    end

    test "an effect event works under its own name" do
      socket = socket_for(AliasedLive) |> Helpers.run_event(:job, :finish, %{})
      assert socket.assigns.job_done == true
    end

    test "an effect event is refused under another name" do
      assert_raise ArgumentError, ~r/attached as :task/, fn ->
        socket_for(AliasedLive) |> Helpers.run_event(:task, :finish, %{})
      end
    end
  end
end
