defmodule AshComputer.FunctionGenerationTest do
  use ExUnit.Case, async: false

  describe "function generation for compute expressions" do
    defmodule SimpleComputer do
      use AshComputer

      computer :simple do
        input :x do
          initial 10
        end

        val :doubled do
          compute fn %{x: x} -> x * 2 end
        end
      end
    end

    test "generates functions with correct names" do
      # Check if the function was actually generated
      assert function_exported?(SimpleComputer, :__compute_simple_doubled__, 1),
             "Expected function __compute_simple_doubled__/1 to be generated"

      # List all generated compute functions
      functions = SimpleComputer.__info__(:functions)
      compute_functions = functions
        |> Enum.filter(fn {name, _arity} ->
          String.contains?(to_string(name), "__compute_")
        end)
        |> Enum.map(fn {name, arity} -> "#{name}/#{arity}" end)

      IO.puts("Generated functions in SimpleComputer: #{inspect(compute_functions)}")
    end

    test "generated functions can be called directly" do
      if function_exported?(SimpleComputer, :__compute_simple_doubled__, 1) do
        # Call the generated function directly
        result = SimpleComputer.__compute_simple_doubled__(%{x: 5})
        assert result == 10, "Direct function call should return 10"
      else
        flunk("Function __compute_simple_doubled__/1 was not generated")
      end
    end

    defmodule AliasComputer do
      use AshComputer

      # Create an alias to test
      alias Enum, as: E
      alias String, as: S

      computer :alias_test do
        input :numbers do
          initial [1, 2, 3]
        end

        input :words do
          initial ["hello", "world"]
        end

        val :sum do
          compute fn %{numbers: numbers} ->
            E.sum(numbers)
          end
        end

        val :joined do
          compute fn %{words: words} ->
            S.upcase(Enum.join(words, " "))
          end
        end
      end
    end

    test "generated functions with aliases" do
      # Check function generation
      assert function_exported?(AliasComputer, :__compute_alias_test_sum__, 1),
             "Expected function __compute_alias_test_sum__/1 to be generated"

      assert function_exported?(AliasComputer, :__compute_alias_test_joined__, 1),
             "Expected function __compute_alias_test_joined__/1 to be generated"

      # List all functions for debugging
      functions = AliasComputer.__info__(:functions)
      compute_functions = functions
        |> Enum.filter(fn {name, _arity} ->
          String.contains?(to_string(name), "__compute_")
        end)

      IO.puts("Generated functions in AliasComputer: #{inspect(compute_functions)}")
    end

    test "computer works with generated functions" do
      computer = AshComputer.computer(SimpleComputer)
      assert computer.values[:doubled] == 20
    end

    test "computer works with aliased modules" do
      computer = AshComputer.computer(AliasComputer)
      assert computer.values[:sum] == 6
      assert computer.values[:joined] == "HELLO WORLD"
    end

    defmodule RealWorldComputer do
      use AshComputer

      # Simulate a real scenario with Ash
      defmodule User do
        defstruct [:id, :name]
      end

      alias __MODULE__.User, as: U

      computer :users_table do
        input :page do
          initial 1
        end

        input :page_size do
          initial 10
        end

        val :offset do
          compute fn %{page: page, page_size: page_size} ->
            (page - 1) * page_size
          end
        end

        val :mock_query do
          compute fn %{offset: offset, page_size: page_size} ->
            # Simulate what would happen with User |> Ash.Query...
            %{
              module: U,
              offset: offset,
              limit: page_size
            }
          end
        end
      end
    end

    test "real world scenario with module aliases" do
      assert function_exported?(RealWorldComputer, :__compute_users_table_offset__, 1),
             "Expected function __compute_users_table_offset__/1 to be generated"

      assert function_exported?(RealWorldComputer, :__compute_users_table_mock_query__, 1),
             "Expected function __compute_users_table_mock_query__/1 to be generated"

      computer = AshComputer.computer(RealWorldComputer)

      assert computer.values[:offset] == 0
      assert %{module: RealWorldComputer.User, offset: 0, limit: 10} = computer.values[:mock_query]

      # Test with different page
      computer = AshComputer.Runtime.handle_input(computer, :page, 3)
      assert computer.values[:offset] == 20
      assert %{offset: 20} = computer.values[:mock_query]
    end

    test "inspect generated function source (if available)" do
      # This helps debug what the actual generated function looks like
      if function_exported?(SimpleComputer, :__compute_simple_doubled__, 1) do
        # Try to get function info
        fun_info = Function.info(&SimpleComputer.__compute_simple_doubled__/1)
        IO.puts("\nFunction info for __compute_simple_doubled__/1:")
        IO.inspect(fun_info, limit: :infinity)
      end
    end
  end

  describe "debugging function generation" do
    test "verify transformer is running" do
      # Create a module that logs during transformation
      defmodule DebugTransformerComputer do
        use AshComputer

        computer :debug do
          input :value do
            initial 1
          end

          val :result do
            compute fn %{value: v} ->
              IO.puts("This should not print during compilation")
              v * 2
            end
          end
        end
      end

      # Check if function exists
      exists = function_exported?(DebugTransformerComputer, :__compute_debug_result__, 1)
      assert exists, "Function should have been generated by transformer"

      # If it exists, verify it works
      if exists do
        result = DebugTransformerComputer.__compute_debug_result__(%{value: 5})
        assert result == 10
      end
    end
  end
end