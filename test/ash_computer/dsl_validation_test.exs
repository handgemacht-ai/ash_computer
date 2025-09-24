defmodule AshComputer.DslValidationTest do
  use ExUnit.Case

  describe "val reference validation" do
    test "raises error when val references non-existent input" do
      # Define a module with invalid DSL (this will compile but have verification errors)
      defmodule InvalidInputReference do
        use AshComputer

        computer :test do
          input :a do
          end

          val :result do
            compute(fn %{a: a, b: b} ->
              a + b
            end)
          end
        end
      end

      # Test the verifier directly
      dsl_state = InvalidInputReference.spark_dsl_config()
      verifier = AshComputer.Verifiers.ValidateDependencies

      assert {:error, %Spark.Error.DslError{} = error} = verifier.verify(dsl_state)
      assert error.message =~ "references non-existent input or val `b`"
    end

    test "passes validation when all dependencies exist" do
      defmodule ValidInputReference do
        use AshComputer

        computer :test do
          input :a do
          end

          input :b do  
          end

          val :result do
            compute(fn %{a: a, b: b} ->
              a + b
            end)
          end
        end
      end

      # Test the verifier directly
      dsl_state = ValidInputReference.spark_dsl_config()
      verifier = AshComputer.Verifiers.ValidateDependencies

      assert :ok = verifier.verify(dsl_state)
    end
  end
end
