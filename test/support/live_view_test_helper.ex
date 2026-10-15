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
