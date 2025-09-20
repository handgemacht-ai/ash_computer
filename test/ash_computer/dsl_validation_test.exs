defmodule AshComputer.DslValidationTest do
  use ExUnit.Case

  describe "val reference validation" do
    test "raises error when val references non-existent input" do
      assert_raise Spark.Error.DslError, ~r/references non-existent input/, fn ->
        defmodule InvalidInputReference do
          use AshComputer

          computer :test do
            input :a do
            end

            val :result do
              compute(fn %{"a" => a, "b" => b} ->
                a + b
              end)
            end
          end
        end
      end
    end
  end
end
