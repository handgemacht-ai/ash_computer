defmodule AshComputer.InfoAndHelpersTest do
  use ExUnit.Case, async: true

  alias AshComputer.AstParser
  alias AshComputer.Executor.Error
  alias AshComputer.Executor.Node
  alias AshComputer.Info
  alias AshComputer.Result
  alias AshComputer.TestComputers.{Cart, Counter}

  describe "Info" do
    test "lists computers and their names" do
      assert Info.computer_names(Cart) == [:shopping_cart]
      assert [%{name: :shopping_cart}] = Info.computers(Cart)
      assert Info.has_computers?(Cart)
    end

    test "finds a computer by name" do
      assert %{name: :counter} = Info.computer(Counter, :counter)
      assert Info.computer(Counter, :nope) == nil
    end

    test "default computer name is the first computer" do
      assert Info.default_computer_name(Counter) == :counter
    end

    test "event names for a computer" do
      assert Info.event_names(Counter, :counter) ==
               ["counter_increment", "counter_decrement", "counter_reset"]

      assert Info.event_names(Counter, :nope) == []
    end

    test "single event name" do
      assert Info.event_name(Counter, :counter, :reset) == "counter_reset"
      assert Info.event_name(Counter, :counter, :nope) == nil
      assert Info.event_name(Counter, :nope, :reset) == nil
    end

    test "compile-time event name macros" do
      require Info

      assert Info.event_names!(AshComputer.TestComputers.Counter, :counter) ==
               ["counter_increment", "counter_decrement", "counter_reset"]

      assert Info.event_name!(AshComputer.TestComputers.Counter, :counter, :reset) ==
               "counter_reset"
    end

    test "compile-time event name macros fail for unknown computers and events" do
      assert_raise CompileError, ~r/Computer :nope not found/, fn ->
        Code.eval_string("""
        require AshComputer.Info
        AshComputer.Info.event_names!(AshComputer.TestComputers.Counter, :nope)
        """)
      end

      assert_raise CompileError, ~r/Event :nope not found/, fn ->
        Code.eval_string("""
        require AshComputer.Info
        AshComputer.Info.event_name!(AshComputer.TestComputers.Counter, :counter, :nope)
        """)
      end

      assert_raise CompileError, ~r/Invalid module reference/, fn ->
        Code.eval_string("""
        require AshComputer.Info
        AshComputer.Info.event_names!("not a module", :counter)
        """)
      end
    end
  end

  describe "AstParser" do
    test "extracts keys from map patterns across clauses" do
      ast = quote do: fn %{a: a} -> a end
      assert AstParser.parse_quoted_function(ast) == [:a]

      ast =
        quote do
          fn
            %{a: a, b: b} -> a + b
            %{b: b, c: c} -> b + c
          end
        end

      assert AstParser.parse_quoted_function(ast) == [:a, :b, :c]
    end

    test "extracts keys from struct patterns and string keys" do
      ast = quote do: fn %Foo{x: x} -> x end
      assert AstParser.parse_quoted_function(ast) == [:x]

      ast = quote do: fn %{"name" => name} -> name end
      assert AstParser.parse_quoted_function(ast) == [:name]
    end

    test "returns no dependencies for other patterns" do
      assert AstParser.parse_quoted_function(quote(do: fn x -> x end)) == []
      assert AstParser.parse_quoted_function(quote(do: fn -> 1 end)) == []
      assert AstParser.parse_quoted_function(quote(do: :not_a_function)) == []
    end
  end

  describe "Result" do
    test "normalizes the three accepted shapes" do
      assert Result.normalize({:ok, 1}) == Result.ok(1)
      assert Result.normalize({:error, :bad}) == Result.error(:bad)
      assert Result.normalize(5) == Result.ok(5)
    end

    test "tells ok from error" do
      assert Result.ok?(Result.ok(1))
      refute Result.ok?(Result.error(1))
      assert Result.error?(Result.error(1))
      refute Result.error?(Result.ok(1))
    end
  end

  describe "Executor.Error" do
    test "converts to the legacy tuple" do
      assert Error.to_tuple(Error.expected(:boom)) == {:expected, :boom}

      node = Node.new(:c, :n)
      assert Error.to_tuple(Error.blocked(node)) == {:blocked, Node.key(node)}
    end
  end
end
