defmodule AshComputer.Dsl do
  @moduledoc false

  @input %Spark.Dsl.Entity{
    name: :input,
    describe: "Declare an external value fed into the computer.",
    args: [:name],
    target: AshComputer.Dsl.Input,
    schema: [
      name: [type: :atom, required: true, doc: "The name of the input."],
      description: [type: :string, doc: "Human readable description."],
      initial: [type: :any, doc: "Initial value provided when the computer is built."],
      options: [type: :any, doc: "Domain specific metadata passed to Computer.Input."]
    ]
  }

  @val %Spark.Dsl.Entity{
    name: :val,
    describe: "Declare a derived value computed from inputs and other vals.",
    args: [:name],
    target: AshComputer.Dsl.Val,
    schema: [
      name: [type: :atom, doc: "The name of the val."],
      description: [type: :string, doc: "Human readable description."],
      compute: [type: :quoted, required: true, doc: "Function that computes the value."],
      depends_on: [
        type: {:list, :atom},
        doc: "Explicit dependencies (auto-detected if not provided)."
      ]
    ]
  }

  @event %Spark.Dsl.Entity{
    name: :event,
    describe: "Declare an event that changes inputs, optionally through a side effect.",
    args: [:name],
    target: AshComputer.Dsl.Event,
    schema: [
      name: [type: :atom, doc: "The name of the event."],
      handle: [
        type: :any,
        doc:
          "Pure event. Captured function (arity 1 or 2) that receives the values and optional params and returns a map of input changes. Exactly one of `handle` or `run` is required."
      ],
      run: [
        type: :any,
        doc:
          "Effect event. Captured function of arity 3 that receives the values, the params and an `AshComputer.Context`, and returns `{:ok, _}` or `{:error, _}`. Runs synchronously; a crash is not rescued. Requires `handle_result`."
      ],
      handle_result: [
        type: :any,
        doc:
          "Required when `run` is set. Pure captured function of arity 3 that receives `{:ok, _} | {:error, _}`, the values and the params, and returns an `AshComputer.Reply`."
      ],
      description: [type: :string, doc: "Human readable description of the event."]
    ]
  }

  @computer %Spark.Dsl.Entity{
    name: :computer,
    describe: "Define a named computer made of inputs, vals, and events.",
    identifier: :name,
    args: [:name],
    target: AshComputer.Dsl.Computer,
    schema: [
      name: [type: :atom, required: true, doc: "The name of the computer."],
      description: [type: :string, doc: "Description of what the computer does."],
      stateful?: [
        type: :boolean,
        default: false,
        doc: "Whether the computer should retain previous values when computing."
      ]
    ],
    entities: [inputs: [@input], vals: [@val], events: [@event]]
  }

  @computers %Spark.Dsl.Section{
    top_level?: true,
    name: :computers,
    describe: "Top level section for declaring computers.",
    entities: [@computer],
    schema: [],
    imports: []
  }

  use Spark.Dsl.Extension,
    sections: [@computers],
    transformers: [
      AshComputer.Transformers.ParseDependencies,
      AshComputer.Transformers.CompileComputers
    ],
    verifiers: [
      AshComputer.Verifiers.ValidateDependencies,
      AshComputer.Verifiers.ValidateEvents
    ]
end
