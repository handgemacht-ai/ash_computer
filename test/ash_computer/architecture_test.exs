defmodule AshComputer.ArchitectureTest do
  use ExUnit.Case, async: true

  alias AshComputer.Architecture
  alias AshComputer.Architecture.PhoenixViolation

  test "only lib/ash_computer/live_view.ex references Phoenix" do
    offenders = Architecture.phoenix_offenders(Architecture.lib_modules())

    assert offenders == [],
           "Phoenix referenced outside lib/ash_computer/live_view.ex:\n" <>
             Enum.map_join(offenders, "\n", fn {module, source, phoenix} ->
               "#{Path.relative_to(source, Path.dirname(Architecture.lib_dir()))} " <>
                 "(#{inspect(module)}): " <> Enum.map_join(phoenix, ", ", &inspect/1)
             end)
  end

  test "the check reports a module that references Phoenix" do
    modules = Architecture.lib_modules() ++ [PhoenixViolation]

    assert {PhoenixViolation, _source, [Phoenix.LiveView]} =
             List.keyfind(Architecture.phoenix_offenders(modules), PhoenixViolation, 0)
  end

  test "the check allows Phoenix in lib/ash_computer/live_view.ex" do
    assert AshComputer.LiveView in Architecture.lib_modules()
    assert Architecture.phoenix_offenders([AshComputer.LiveView]) == []
  end

  test "the check sees the core modules" do
    sources = MapSet.new(Architecture.lib_modules(), &Architecture.source_of/1)

    for file <- ["ash_computer.ex", "ash_computer/dsl.ex", "ash_computer/dsl/event.ex"] do
      assert Path.join(Architecture.lib_dir(), file) in sources
    end
  end
end
