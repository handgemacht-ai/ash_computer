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
    describe: "Declare an event that mutates the computer when invoked.",
    args: [:name],
    target: AshComputer.Dsl.Event,
    schema: [
      name: [type: :atom, doc: "The name of the event."],
      handle: [
        type: :any,
        required: true,
        doc:
          "Captured function (arity 1 or 2) that receives the computer and optional payload, returning an updated computer."
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
      AshComputer.Verifiers.ValidateDependencies
    ]
end
