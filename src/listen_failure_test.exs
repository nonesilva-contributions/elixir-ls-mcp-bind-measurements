defmodule ListenFailureProbeTest do
  # Sends the language server a configuration that turns MCP on with a listen
  # that fails, and checks if the language server process is still alive.
  use ElixirLS.Utils.MixTest.Case, async: false
  use ElixirLS.LanguageServer.Protocol
  import ElixirLS.LanguageServer.Test.ServerTestHelpers
  alias ElixirLS.LanguageServer.{MixProjectCache, Parser, Server, Tracer}

  # EXPECTED_PORT_80 is "down" on master and "alive" with the patch.
  @cases [
    {1, "mcpPort 80", %{"mcpPort" => 80}, :from_env},
    {2, "mcpHost 192.0.2.1", %{"mcpPort" => 4300, "mcpHost" => "192.0.2.1"}, "alive"}
  ]

  for {offset, name, mcp, expected} <- @cases do
    test name do
      n = String.to_integer(System.fetch_env!("CASE_BASE")) + unquote(offset)
      version = System.fetch_env!("VERSION")

      expected =
        case unquote(expected) do
          :from_env -> System.fetch_env!("EXPECTED_PORT_80")
          value -> value
        end

      precondition =
        case unquote(name) do
          "mcpPort 80" ->
            row("listen on port 80 as this user", inspect(:gen_tcp.listen(80, [])))

          _ ->
            row("listen on 192.0.2.1", inspect(:gen_tcp.listen(0, ip: {192, 0, 2, 1})))
        end

      {:ok, server} = Server.start_link()
      start_server(server)
      {:ok, _} = start_supervised(Tracer)
      {:ok, _} = start_supervised(MixProjectCache)
      {:ok, _} = start_supervised(Parser)
      Process.flag(:trap_exit, true)

      in_fixture(__DIR__, "clean", fn ->
        Server.receive_packet(server, initialize_req(1, root_uri(), %{}))
        Server.receive_packet(server, notification("initialized", %{}))

        config =
          Map.merge(
            %{"mcpEnabled" => true, "dialyzerEnabled" => false, "autoBuild" => false},
            unquote(Macro.escape(mcp))
          )

        Server.receive_packet(server, did_change_configuration(%{"elixirLS" => config}))

        # A call is served only after the configuration, so it tells if the server survived it.
        {state, detail} =
          try do
            :sys.get_state(server)
            {"alive", ""}
          catch
            :exit, {reason, _call} -> {"down", ": " <> inspect(reason)}
          end

        mismatch =
          if state == expected, do: "", else: "  MISMATCH case #{n}: expected #{expected}\n"

        # One write keeps the block together in the output of the test run.
        IO.write(
          "\n## #{n}. #{version}, #{unquote(name)}\n" <>
            precondition <> row("language server", state <> detail) <> mismatch
        )

        assert state == expected
      end)
    end
  end

  defp row(label, value), do: "  -> #{String.pad_trailing(label, 34)} -> #{value}\n"
end
