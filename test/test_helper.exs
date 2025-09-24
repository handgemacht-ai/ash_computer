# Start Phoenix if available for LiveView tests
if Code.ensure_loaded?(Phoenix) do
  # Start the test endpoint
  Application.put_env(:ash_computer, AshComputer.TestEndpoint,
    http: [port: 4002],
    server: false,
    secret_key_base: String.duplicate("test", 16),
    live_view: [signing_salt: "test_salt_for_live_view"]
  )

  {:ok, _} = AshComputer.TestEndpoint.start_link()
end

ExUnit.start()
