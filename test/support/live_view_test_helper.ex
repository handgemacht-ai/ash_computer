defmodule AshComputer.LiveViewTestHelper do
  @moduledoc """
  Test helper for Phoenix LiveView integration tests.
  """

  defmacro __using__(_) do
    quote do
      import Plug.Conn
      import Plug.Test
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import AshComputer.LiveViewTestHelper

      @endpoint AshComputer.TestEndpoint
    end
  end

  @doc """
  Helper to mount a LiveView for testing.
  """
  defmacro live_mount(live_view, session \\ quote(do: %{})) do
    quote do
      require Phoenix.LiveViewTest

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(unquote(session))

      {:ok, view, _html} =
        Phoenix.LiveViewTest.live_isolated(conn, unquote(live_view), session: unquote(session))

      view
    end
  end
end

defmodule AshComputer.TestLive.Navigation do
  @moduledoc false
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, Phoenix.Component.assign(socket, :page, params["page"])}

  @impl true
  def handle_event("patch", _params, socket),
    do: {:noreply, push_patch(socket, to: "/navigation/patched")}

  def handle_event("redirect", _params, socket),
    do: {:noreply, push_navigate(socket, to: "/elsewhere")}

  @impl true
  def render(assigns), do: ~H"<p>page: {@page}</p>"
end

defmodule AshComputer.TestLive.Effects do
  @moduledoc false
  use Phoenix.LiveView
  use AshComputer.LiveView

  alias AshComputer.Context
  alias AshComputer.Reply

  @secret_actor %{name: "Alice", token: "s3cret-actor-token"}
  @secret_tenant "s3cret-tenant-id"

  def secret_actor, do: @secret_actor
  def secret_tenant, do: @secret_tenant

  computer :shop do
    input :status do
      initial :idle
    end

    input :error do
      initial nil
    end

    input :seen do
      initial nil
    end

    input :ticks do
      initial 0
    end

    val :label do
      compute fn %{status: status} -> "status: #{status}" end
    end

    event :reset, handle: &__MODULE__.reset/1
    event :set, handle: &__MODULE__.set/2
    event :pay, run: &__MODULE__.pay/3, handle_result: &__MODULE__.paid/3
    event :boot, run: &__MODULE__.pay/3, handle_result: &__MODULE__.booted/3
    event :tick, run: &__MODULE__.pay/3, handle_result: &__MODULE__.ticked/3
    event :outcome, run: &__MODULE__.pay/3, handle_result: &__MODULE__.outcome/3
    event :crash, run: &__MODULE__.crash/3, handle_result: &__MODULE__.paid/3
    event :touch_val, run: &__MODULE__.pay/3, handle_result: &__MODULE__.touch_val/3
  end

  def reset(_values), do: %{status: :idle, error: nil, seen: nil}
  def set(_values, %{"status" => status}), do: %{status: String.to_existing_atom(status)}

  def pay(_values, %{"fail" => reason}, %Context{}), do: {:error, reason}

  def pay(_values, _params, %Context{} = ctx) do
    {:ok, %{who: ctx.actor && ctx.actor.name, extra: ctx.extra, tenant_set: ctx.tenant != nil}}
  end

  def crash(_values, _params, _ctx), do: raise("effect exploded")

  def paid({:ok, seen}, _values, _params) do
    Reply.new(status: :paid, error: nil, seen: seen) |> Reply.flash(:info, "Paid")
  end

  def paid({:error, reason}, _values, _params) do
    Reply.new(status: :failed, error: reason) |> Reply.flash(:error, "Failed: #{reason}")
  end

  def booted({:ok, seen}, _values, _params), do: Reply.new(status: :booted, seen: seen)

  def ticked({:ok, _seen}, values, %{"id" => id}),
    do: Reply.new(status: :ticked, ticks: values.ticks + 1, error: id)

  def touch_val(_result, _values, _params), do: Reply.new(label: "nope")

  def outcome({:ok, _seen}, _values, %{"kind" => kind}) do
    reply = Reply.new(status: :outcome)

    case kind do
      "navigate" -> Reply.navigate(reply, "/elsewhere")
      "patch" -> Reply.patch(reply, "/effects/next")
      "redirect" -> Reply.redirect(reply, "/elsewhere")
      "push_event" -> reply |> Reply.push_event("pinged", %{id: 1}) |> Reply.push_event("again")
      "flash" -> reply |> Reply.flash(:info, "one") |> Reply.flash(:error, "two")
      "navigate_and_patch" -> reply |> Reply.navigate("/elsewhere") |> Reply.patch("/effects/x")
    end
  end

  @impl true
  def computer_context(socket) do
    [
      actor: socket.private[:actor],
      tenant: socket.private[:tenant],
      extra: %{view: socket.view}
    ]
  end

  @impl true
  def mount(params, session, socket) do
    socket =
      if session["signed_in"] do
        socket
        |> put_private(:actor, @secret_actor)
        |> put_private(:tenant, @secret_tenant)
      else
        socket
      end

    socket = mount_computers(socket)
    socket = if params["boot"], do: run_event(socket, :shop, :boot, %{}), else: socket
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, :page, params["page"])}

  @impl true
  def handle_info({:tick, id}, socket),
    do: {:noreply, run_event(socket, :shop, :tick, %{"id" => id})}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <p id="label">{@shop_label}</p>
      <p id="status">{@shop_status}</p>
      <p id="error">{inspect(@shop_error)}</p>
      <p id="seen">{inspect(@shop_seen)}</p>
      <p id="ticks">{@shop_ticks}</p>
      <p id="page">{@page}</p>
      <p :if={msg = Phoenix.Flash.get(@flash, :info)} id="flash-info">{msg}</p>
      <p :if={msg = Phoenix.Flash.get(@flash, :error)} id="flash-error">{msg}</p>
    </div>
    """
  end
end

defmodule AshComputer.TestRouter do
  @moduledoc """
  Routes for LiveView tests that need `live/2`, `assert_patch` and
  `assert_redirect`. Add a `live` route per test LiveView.
  """
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)

    live("/navigation", AshComputer.TestLive.Navigation)
    live("/navigation/:page", AshComputer.TestLive.Navigation)
    live("/effects", AshComputer.TestLive.Effects)
    live("/effects/:page", AshComputer.TestLive.Effects)
  end
end

defmodule AshComputer.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :ash_computer

  # Basic configuration for testing
  @session_options [
    store: :cookie,
    key: "_ash_computer_test_key",
    signing_salt: "test_salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: true, longpoll: false)

  plug(Plug.Session, @session_options)
  plug(AshComputer.TestRouter)
end
