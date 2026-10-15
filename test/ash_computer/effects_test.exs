defmodule AshComputer.EffectsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AshComputer.Context
  alias AshComputer.Executor
  alias AshComputer.Reply
  alias AshComputer.Verifiers.ValidateEvents

  defmodule Orders do
    use AshComputer

    computer :order do
      input :status do
        initial :idle
      end

      input :error do
        initial nil
      end

      input :attempts do
        initial 0
      end

      val :label do
        compute fn %{status: status} -> "status: #{inspect(status)}" end
      end

      event :reset, handle: &__MODULE__.reset/1

      event :submit,
        run: &__MODULE__.submit/3,
        handle_result: &__MODULE__.submitted/3

      event :crash,
        run: &__MODULE__.crash/3,
        handle_result: &__MODULE__.submitted/3

      event :bad_result,
        run: &__MODULE__.bad_result/3,
        handle_result: &__MODULE__.submitted/3

      event :bad_reply,
        run: &__MODULE__.submit/3,
        handle_result: &__MODULE__.not_a_reply/3

      event :touches_val,
        run: &__MODULE__.submit/3,
        handle_result: &__MODULE__.touches_val/3

      event :all_outcomes,
        run: &__MODULE__.submit/3,
        handle_result: &__MODULE__.all_outcomes/3
    end

    def reset(_values), do: %{status: :idle}

    def submit(values, %{"fail" => reason}, _ctx), do: {:error, {reason, values.attempts}}

    def submit(values, params, %Context{} = ctx) do
      {:ok,
       %{
         actor: ctx.actor,
         tenant: ctx.tenant,
         extra: ctx.extra,
         params: params,
         attempts: values.attempts
       }}
    end

    def crash(_values, _params, _ctx), do: raise("effect exploded")

    def bad_result(_values, _params, _ctx), do: :not_a_tuple

    def submitted({:ok, %{actor: actor}}, values, _params) do
      Reply.new(status: {:done, actor}, error: nil, attempts: values.attempts + 1)
      |> Reply.flash(:info, "Submitted")
    end

    def submitted({:error, {reason, _}}, values, _params) do
      Reply.new(status: :failed, error: reason, attempts: values.attempts + 1)
      |> Reply.flash(:error, "Failed: #{reason}")
    end

    def not_a_reply(_result, _values, _params), do: %{status: :nope}

    def touches_val(_result, _values, _params), do: Reply.new(label: "x")

    def all_outcomes(_result, _values, _params) do
      Reply.new(status: :done)
      |> Reply.flash(:info, "a")
      |> Reply.flash(:error, "b")
      |> Reply.navigate("/orders")
      |> Reply.patch("/orders?x=1")
      |> Reply.redirect("/elsewhere")
      |> Reply.push_event("ping", %{id: 1})
    end
  end

  defp executor do
    Executor.new()
    |> Executor.add_computer(Orders, :order)
    |> Executor.initialize()
  end

  defp values(executor), do: Executor.current_values(executor, :order)

  describe "dispatch_event/6 with an effect event" do
    test "runs the effect with values, params and context and applies the ok reply" do
      ctx = %Context{actor: :alice, tenant: "acme", extra: %{request: 1}}

      {executor, reply} =
        AshComputer.dispatch_event(Orders, :order, :submit, executor(), %{"a" => 1}, ctx)

      assert values(executor).status == {:done, :alice}
      assert values(executor).attempts == 1
      assert values(executor).label == "status: {:done, :alice}"
      assert %Reply{flash: [info: "Submitted"]} = reply
      assert reply.changes.status == {:done, :alice}
    end

    test "passes actor, tenant and extra to run" do
      defmodule Probe do
        use AshComputer

        computer :probe do
          input(:seen)

          event :look, run: &__MODULE__.look/3, handle_result: &__MODULE__.keep/3
        end

        def look(_values, params, ctx), do: {:ok, {params, ctx}}
        def keep({:ok, seen}, _values, _params), do: Reply.new(seen: seen)
      end

      executor =
        Executor.new() |> Executor.add_computer(Probe, :probe) |> Executor.initialize()

      {executor, _reply} =
        AshComputer.dispatch_event(Probe, :probe, :look, executor, %{p: 1},
          actor: :bob,
          tenant: :t1,
          extra: %{k: :v}
        )

      assert %{seen: {%{p: 1}, %Context{actor: :bob, tenant: :t1, extra: %{k: :v}}}} =
               Executor.current_values(executor, :probe)
    end

    test "turns an error result into input changes through handle_result" do
      {executor, reply} =
        AshComputer.dispatch_event(
          Orders,
          :order,
          :submit,
          executor(),
          %{"fail" => "boom"},
          %Context{}
        )

      assert values(executor).status == :failed
      assert values(executor).error == "boom"
      assert reply.flash == [error: "Failed: boom"]
    end

    test "returns every outcome as data" do
      {_executor, reply} =
        AshComputer.dispatch_event(Orders, :order, :all_outcomes, executor(), %{}, %Context{})

      assert reply.flash == [info: "a", error: "b"]
      assert reply.navigate == "/orders"
      assert reply.patch == "/orders?x=1"
      assert reply.redirect == "/elsewhere"
      assert reply.push_events == [{"ping", %{id: 1}}]
    end

    test "a crash in run propagates" do
      assert_raise RuntimeError, "effect exploded", fn ->
        AshComputer.dispatch_event(Orders, :order, :crash, executor(), %{}, %Context{})
      end
    end

    test "run must return ok or error" do
      assert_raise ArgumentError, ~r/must return \{:ok, _\} or \{:error, _\}/, fn ->
        AshComputer.dispatch_event(Orders, :order, :bad_result, executor(), %{}, %Context{})
      end
    end

    test "handle_result must return a Reply" do
      assert_raise ArgumentError, ~r/must return an %AshComputer.Reply\{\}/, fn ->
        AshComputer.dispatch_event(Orders, :order, :bad_reply, executor(), %{}, %Context{})
      end
    end

    test "handle_result can only change inputs" do
      assert_raise ArgumentError, ~r/tried to modify non-input values: \[:label\]/, fn ->
        AshComputer.dispatch_event(Orders, :order, :touches_val, executor(), %{}, %Context{})
      end
    end

    test "unknown computer and event raise" do
      assert_raise ArgumentError, ~r/Unknown computer :nope/, fn ->
        AshComputer.dispatch_event(Orders, :nope, :submit, executor(), %{}, %Context{})
      end

      assert_raise ArgumentError, ~r/Unknown event :nope/, fn ->
        AshComputer.dispatch_event(Orders, :order, :nope, executor(), %{}, %Context{})
      end
    end
  end

  describe "dispatch_event/6 with a pure event" do
    test "behaves like apply_event and returns a reply holding the changes" do
      {executor, _} =
        AshComputer.dispatch_event(Orders, :order, :submit, executor(), %{}, %Context{})

      {executor, reply} =
        AshComputer.dispatch_event(Orders, :order, :reset, executor, %{}, %Context{})

      assert values(executor).status == :idle
      assert reply == %Reply{changes: %{status: :idle}}
    end
  end

  describe "map_result/6" do
    test "maps an ok result without running the effect" do
      {executor, reply} =
        AshComputer.map_result(Orders, :order, :submit, executor(), {:ok, %{actor: :zed}}, %{})

      assert values(executor).status == {:done, :zed}
      assert reply.flash == [info: "Submitted"]
    end

    test "maps an error result" do
      {executor, reply} =
        AshComputer.map_result(Orders, :order, :submit, executor(), {:error, {"nope", 0}}, %{})

      assert values(executor).error == "nope"
      assert reply.flash == [error: "Failed: nope"]
    end

    test "rejects results that are neither ok nor error" do
      assert_raise ArgumentError, ~r/must return \{:ok, _\} or \{:error, _\}/, fn ->
        AshComputer.map_result(Orders, :order, :submit, executor(), :ok, %{})
      end
    end

    test "rejects a pure event" do
      assert_raise ArgumentError, ~r/has no `run`/, fn ->
        AshComputer.map_result(Orders, :order, :reset, executor(), {:ok, 1}, %{})
      end
    end
  end

  describe "apply_event/4 and /5" do
    test "raise a clear error on an effect event" do
      assert_raise ArgumentError, ~r/has a side effect.*dispatch_event\/6/s, fn ->
        AshComputer.apply_event(Orders, :submit, executor())
      end

      assert_raise ArgumentError, ~r/has a side effect/, fn ->
        AshComputer.apply_event(Orders, :order, :submit, executor(), %{})
      end
    end
  end

  describe "event verifier" do
    defp verify(module),
      do: ValidateEvents.verify(module.spark_dsl_config())

    defp message({:error, %Spark.Error.DslError{message: message}}), do: message

    test "accepts pure and effect events" do
      assert :ok = verify(Orders)
    end

    test "requires handle_result when run is set" do
      capture_io(:stderr, fn ->
        defmodule NoHandleResult do
          use AshComputer

          computer :c do
            input(:a)
            event :go, run: &__MODULE__.go/3
          end

          def go(_, _, _), do: {:ok, 1}
        end
      end)

      assert {:error, %Spark.Error.DslError{path: path}} = verify(__MODULE__.NoHandleResult)
      assert path == [:computers, :c, :events, :go]

      assert message(verify(__MODULE__.NoHandleResult)) =~
               "Event `go` has `run` but no `handle_result`"
    end

    test "rejects handle_result without run" do
      capture_io(:stderr, fn ->
        defmodule OrphanHandleResult do
          use AshComputer

          computer :c do
            input(:a)
            event :go, handle: &__MODULE__.go/1, handle_result: &__MODULE__.hr/3
          end

          def go(_), do: %{}
          def hr(_, _, _), do: AshComputer.Reply.new()
        end
      end)

      assert message(verify(__MODULE__.OrphanHandleResult)) =~ "has `handle_result` but no `run`"
    end

    test "rejects both handle and run" do
      capture_io(:stderr, fn ->
        defmodule BothHandleAndRun do
          use AshComputer

          computer :c do
            input(:a)

            event :go,
              handle: &__MODULE__.go/1,
              run: &__MODULE__.run/3,
              handle_result: &__MODULE__.hr/3
          end

          def go(_), do: %{}
          def run(_, _, _), do: {:ok, 1}
          def hr(_, _, _), do: AshComputer.Reply.new()
        end
      end)

      assert message(verify(__MODULE__.BothHandleAndRun)) =~ "cannot have both `handle` and `run`"
    end

    test "rejects an event with neither handle nor run" do
      capture_io(:stderr, fn ->
        defmodule NeitherHandleNorRun do
          use AshComputer

          computer :c do
            input(:a)
            event :go, description: "does nothing"
          end
        end
      end)

      assert message(verify(__MODULE__.NeitherHandleNorRun)) =~
               "needs either `handle` (pure) or `run` (effect)"
    end

    test "checks capture arity" do
      capture_io(:stderr, fn ->
        defmodule WrongArity do
          use AshComputer

          computer :c do
            input(:a)
            event :go, run: &__MODULE__.run/2, handle_result: &__MODULE__.hr/2
            event :pure, handle: &__MODULE__.pure/3
          end

          def run(_, _), do: {:ok, 1}
          def hr(_, _), do: AshComputer.Reply.new()
          def pure(_, _, _), do: %{}
        end
      end)

      assert {:error, errors} = verify(__MODULE__.WrongArity)
      messages = Enum.map(errors, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "`run` must have arity 3, got arity 2"))
      assert Enum.any?(messages, &(&1 =~ "`handle_result` must have arity 3, got arity 2"))
      assert Enum.any?(messages, &(&1 =~ "`handle` must have arity 1 or 2, got arity 3"))
    end

    test "rejects non-function values" do
      capture_io(:stderr, fn ->
        defmodule NotAFunction do
          use AshComputer

          computer :c do
            input(:a)
            event :go, run: :nope, handle_result: &__MODULE__.hr/3
          end

          def hr(_, _, _), do: AshComputer.Reply.new()
        end
      end)

      assert message(verify(__MODULE__.NotAFunction)) =~ "`run` must be a function capture"
    end
  end

  describe "Context" do
    test "defaults" do
      assert %Context{actor: nil, tenant: nil, extra: %{}} = Context.new([])
    end

    test "builds from keyword list, map or context" do
      assert %Context{actor: 1, tenant: 2} = Context.new(actor: 1, tenant: 2)
      assert %Context{extra: %{a: 1}} = Context.new(%{extra: %{a: 1}})
      ctx = %Context{actor: :x}
      assert Context.new(ctx) == ctx
    end

    test "rejects unknown keys and other values" do
      assert_raise ArgumentError, ~r/Unknown context keys \[:foo\]/, fn -> Context.new(foo: 1) end
      assert_raise ArgumentError, ~r/Context must be built/, fn -> Context.new(:nope) end
    end
  end

  describe "Reply" do
    test "starts empty" do
      assert %Reply{
               changes: %{},
               flash: [],
               navigate: nil,
               patch: nil,
               redirect: nil,
               push_events: []
             } =
               Reply.new()
    end

    test "change/2 merges and later changes win" do
      reply = Reply.new(a: 1, b: 2) |> Reply.change(b: 3, c: 4)
      assert reply.changes == %{a: 1, b: 3, c: 4}
    end

    test "push_event/3 defaults to an empty payload" do
      assert Reply.push_event(Reply.new(), "ping").push_events == [{"ping", %{}}]
    end
  end
end
