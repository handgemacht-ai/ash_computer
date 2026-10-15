defmodule AshComputer.LiveViewRouterTest do
  use ExUnit.Case
  use AshComputer.LiveViewTestHelper

  test "live/2 mounts a routed LiveView" do
    {:ok, _view, html} = live(build_conn(), "/navigation")
    assert html =~ "page:"
  end

  test "assert_patch sees a push_patch" do
    {:ok, view, _html} = live(build_conn(), "/navigation")
    render_click(view, "patch")
    assert_patch(view, "/navigation/patched")
  end

  test "assert_redirect sees a push_navigate" do
    {:ok, view, _html} = live(build_conn(), "/navigation")
    render_click(view, "redirect")
    assert_redirect(view, "/elsewhere")
  end
end
