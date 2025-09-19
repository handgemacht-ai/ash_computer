defmodule AshComputer.Dsl.Computer do
  @moduledoc false

  alias AshComputer.Dsl.Event
  alias AshComputer.Dsl.Input
  alias AshComputer.Dsl.Val

  @type name :: atom()

  @type t :: %__MODULE__{
          __identifier__: name(),
          name: name(),
          description: String.t() | nil,
          stateful?: boolean(),
          inputs: [Input.t()],
          vals: [Val.t()],
          events: [Event.t()]
        }

  defstruct [
    :__identifier__,
    :name,
    :description,
    stateful?: false,
    inputs: [],
    vals: [],
    events: []
  ]
end
