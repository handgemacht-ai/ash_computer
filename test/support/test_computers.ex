defmodule AshComputer.TestComputers.Cart do
  @moduledoc """
  Reusable shopping cart computer for testing LiveView attachments.
  """
  use AshComputer

  computer :shopping_cart do
    input :items do
      initial []
    end

    input :discount_percent do
      initial 0
    end

    val :item_count do
      compute fn %{items: items} -> length(items) end
    end

    val :subtotal do
      compute fn %{items: items} ->
        Enum.sum(items)
      end
    end

    val :discount_amount do
      compute fn %{subtotal: subtotal, discount_percent: discount_percent} ->
        subtotal * discount_percent / 100
      end
    end

    val :total do
      compute fn %{subtotal: subtotal, discount_amount: discount_amount} ->
        subtotal - discount_amount
      end
    end

    event :add_item do
      handle fn %{items: items}, %{"price" => price} ->
        %{items: [String.to_integer(price) | items]}
      end
    end

    event :clear do
      handle fn _values, _params ->
        %{items: []}
      end
    end

    event :apply_discount do
      handle fn _values, %{"percent" => percent} ->
        %{discount_percent: String.to_integer(percent)}
      end
    end
  end
end

defmodule AshComputer.TestComputers.Sidebar do
  @moduledoc """
  Reusable sidebar state computer for testing LiveView attachments.
  """
  use AshComputer

  computer :sidebar do
    input :collapsed do
      initial false
    end

    input :active_section do
      initial "home"
    end

    val :visible_width do
      compute fn %{collapsed: collapsed} ->
        if collapsed, do: 60, else: 240
      end
    end

    event :toggle do
      handle fn %{collapsed: collapsed}, _params ->
        %{collapsed: not collapsed}
      end
    end

    event :set_active_section do
      handle fn _values, %{"section" => section} ->
        %{active_section: section}
      end
    end
  end
end

defmodule AshComputer.TestComputers.Counter do
  @moduledoc """
  Simple counter computer for testing basic attachment functionality.
  """
  use AshComputer

  computer :counter do
    input :count do
      initial 0
    end

    val :doubled do
      compute fn %{count: count} -> count * 2 end
    end

    event :increment do
      handle fn %{count: count}, _params ->
        %{count: count + 1}
      end
    end

    event :decrement do
      handle fn %{count: count}, _params ->
        %{count: count - 1}
      end
    end

    event :reset do
      handle fn _values, _params ->
        %{count: 0}
      end
    end
  end
end
