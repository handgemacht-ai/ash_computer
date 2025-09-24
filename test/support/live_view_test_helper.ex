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
end
