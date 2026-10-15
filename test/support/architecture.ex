defmodule AshComputer.Architecture do
  @moduledoc """
  Module-boundary checks over compiled BEAM files.

  The core does not depend on Phoenix: only `lib/ash_computer/live_view.ex`
  may reference Phoenix modules. Reading the BEAM atom table catches
  references made through macros (`use`, `import`, aliases) too.
  """

  @lib Path.expand("../../lib", __DIR__)
  @phoenix_allowed [Path.join(@lib, "ash_computer/live_view.ex")]

  @doc "Absolute path of the library's `lib/` directory."
  def lib_dir, do: @lib

  @doc "All modules of the `:ash_computer` application compiled from `lib/`."
  def lib_modules do
    {:ok, modules} = :application.get_key(:ash_computer, :modules)
    Enum.filter(modules, &String.starts_with?(source_of(&1), @lib <> "/"))
  end

  @doc """
  Returns the modules that reference Phoenix outside the allowed files,
  as `{module, source, phoenix_modules}`.
  """
  def phoenix_offenders(modules) do
    for module <- modules,
        source = source_of(module),
        source not in @phoenix_allowed,
        phoenix = phoenix_references(module),
        phoenix != [] do
      {module, source, phoenix}
    end
  end

  @doc "Source file a module was compiled from."
  def source_of(module) do
    module.module_info(:compile) |> Keyword.fetch!(:source) |> List.to_string()
  end

  defp phoenix_references(module) do
    {^module, beam, _} = :code.get_object_code(module)
    {:ok, {^module, [atoms: atoms]}} = :beam_lib.chunks(beam, [:atoms])

    atoms
    |> Enum.map(fn {_, atom} -> atom end)
    |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "Elixir.Phoenix."))
    |> Enum.uniq()
    |> Enum.sort()
  end
end

defmodule AshComputer.Architecture.PhoenixViolation do
  @moduledoc false
  # Test-only module that breaks the Phoenix boundary, so the check is shown
  # to catch a violation.
  def flash(socket), do: Phoenix.LiveView.put_flash(socket, :info, "violation")
end
