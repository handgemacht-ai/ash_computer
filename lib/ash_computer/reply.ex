defmodule AshComputer.Reply do
  @moduledoc """
  What an event asks for, as plain data.

  A reply holds the input `changes` the event wants and the outcomes the host
  should carry out: flash messages, a navigation, a patch, a redirect and
  client events. The core never performs the outcomes; an adapter such as
  `AshComputer.LiveView` does.

  Build replies with the functions in this module:

      Reply.new(result: value)
      |> Reply.flash(:info, "Saved")
      |> Reply.navigate("/orders")
  """

  @type flash_kind :: atom() | String.t()

  @type t :: %__MODULE__{
          changes: %{optional(atom()) => term()},
          flash: [{flash_kind(), String.t()}],
          navigate: String.t() | nil,
          patch: String.t() | nil,
          redirect: String.t() | nil,
          push_events: [{String.t(), map()}]
        }

  defstruct changes: %{}, flash: [], navigate: nil, patch: nil, redirect: nil, push_events: []

  @doc "A reply that changes the given inputs (keyword list or map)."
  @spec new(keyword() | map()) :: t()
  def new(changes \\ %{}) when is_list(changes) or is_map(changes) do
    %__MODULE__{changes: Map.new(changes)}
  end

  @doc "Adds input changes; later changes win."
  @spec change(t(), keyword() | map()) :: t()
  def change(%__MODULE__{} = reply, changes) when is_list(changes) or is_map(changes) do
    %{reply | changes: Map.merge(reply.changes, Map.new(changes))}
  end

  @doc "Adds a flash message."
  @spec flash(t(), flash_kind(), String.t()) :: t()
  def flash(%__MODULE__{} = reply, kind, message) when is_binary(message) do
    %{reply | flash: reply.flash ++ [{kind, message}]}
  end

  @doc "Asks to navigate to a path."
  @spec navigate(t(), String.t()) :: t()
  def navigate(%__MODULE__{} = reply, to) when is_binary(to), do: %{reply | navigate: to}

  @doc "Asks to patch the current page to a path."
  @spec patch(t(), String.t()) :: t()
  def patch(%__MODULE__{} = reply, to) when is_binary(to), do: %{reply | patch: to}

  @doc "Asks to redirect to a path."
  @spec redirect(t(), String.t()) :: t()
  def redirect(%__MODULE__{} = reply, to) when is_binary(to), do: %{reply | redirect: to}

  @doc "Asks to push a client event with a payload."
  @spec push_event(t(), String.t(), map()) :: t()
  def push_event(%__MODULE__{} = reply, name, payload \\ %{})
      when is_binary(name) and is_map(payload) do
    %{reply | push_events: reply.push_events ++ [{name, payload}]}
  end
end
