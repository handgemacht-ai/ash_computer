defmodule AshComputer.Runtime.Instance do
  @moduledoc false

  use GenServer

  @impl true
  def init(computer) do
    {:ok, computer}
  end

  def handle_input(pid, name, value) do
    GenServer.call(pid, {:handle_input, name, value})
  end

  @impl true
  def handle_call({:handle_input, name, value}, _from, computer) do
    updated = AshComputer.Runtime.handle_input(computer, name, value)
    {:reply, {:ok, updated.values}, updated}
  end
end