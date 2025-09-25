defmodule AshComputer.MultiComputerTest do
  use ExUnit.Case, async: false

  defmodule FilterComputer do
    use AshComputer

    computer :filters do
      input :status do
        initial "active"
      end

      input :category do
        initial "electronics"
      end

      val :filter_spec do
        compute fn %{status: status, category: category} ->
          [
            %{field: :status, value: status},
            %{field: :category, value: category}
          ]
        end
      end
    end
  end

  defmodule QueryComputer do
    use AshComputer

    computer :query do
      input :filters do
        initial []
      end

      input :page do
        initial 1
      end

      val :sql do
        compute fn %{filters: filters, page: page} ->
          where_clause =
            filters
            |> Enum.map(fn %{field: field, value: value} -> "#{field} = '#{value}'" end)
            |> Enum.join(" AND ")

          "SELECT * FROM items WHERE #{where_clause} LIMIT 10 OFFSET #{(page - 1) * 10}"
        end
      end
    end
  end

  test "connects two computers and propagates changes" do
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(FilterComputer, :filters)
      |> AshComputer.Executor.add_computer(QueryComputer, :query)
      |> AshComputer.Executor.connect(from: {:filters, :filter_spec}, to: {:query, :filters})
      |> AshComputer.Executor.initialize()

    query_values = AshComputer.Executor.current_values(executor, :query)

    assert query_values[:sql] ==
             "SELECT * FROM items WHERE status = 'active' AND category = 'electronics' LIMIT 10 OFFSET 0"

    executor =
      executor
      |> AshComputer.Executor.start_frame()
      |> AshComputer.Executor.set_input(:filters, :status, "archived")
      |> AshComputer.Executor.set_input(:query, :page, 2)
      |> AshComputer.Executor.commit_frame()

    query_values = AshComputer.Executor.current_values(executor, :query)

    assert query_values[:sql] ==
             "SELECT * FROM items WHERE status = 'archived' AND category = 'electronics' LIMIT 10 OFFSET 10"
  end

  test "batches multiple changes across computers efficiently" do
    executor =
      AshComputer.Executor.new()
      |> AshComputer.Executor.add_computer(FilterComputer, :filters)
      |> AshComputer.Executor.add_computer(QueryComputer, :query)
      |> AshComputer.Executor.connect(from: {:filters, :filter_spec}, to: {:query, :filters})
      |> AshComputer.Executor.initialize()

    executor =
      executor
      |> AshComputer.Executor.start_frame()
      |> AshComputer.Executor.set_input(:filters, :status, "pending")
      |> AshComputer.Executor.set_input(:filters, :category, "books")
      |> AshComputer.Executor.set_input(:query, :page, 3)
      |> AshComputer.Executor.commit_frame()

    filter_values = AshComputer.Executor.current_values(executor, :filters)
    query_values = AshComputer.Executor.current_values(executor, :query)

    assert filter_values[:status] == "pending"
    assert filter_values[:category] == "books"
    assert query_values[:page] == 3

    assert query_values[:sql] ==
             "SELECT * FROM items WHERE status = 'pending' AND category = 'books' LIMIT 10 OFFSET 20"
  end
end