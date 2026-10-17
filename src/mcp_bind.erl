%% Uses the listen options of the elixir-ls MCP TCP server on master, in the first version of the pull request and with the patch.
%% Checks from inside the BEAM which addresses can connect. Run it in its own network namespace, as src/run-bind.sh does.
%% Ports print as <port> and the bridge address as <bridge-ip>, so two runs on the same image give the same output.
-module(mcp_bind).
-export([main/0]).

-define(LOOP4, {127, 0, 0, 1}).
-define(LOOP6, {0, 0, 0, 0, 0, 0, 0, 1}).
-define(BRIDGE_OPTS, [binary, {active, false}, {packet, line}, {buffer, 65536}]).

main() ->
    {ok, Ifs} = inet:getifaddrs(),
    [Eth | _] = [A || {_, Os} <- Ifs, {addr, A = {A1, _, _, _}} <- Os, A1 =/= 127],
    {ok, Otp} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])),
    io:format("environment~n  image: ~s~n  OTP ~s, erts ~s~n  non-loopback IPv4: <bridge-ip>~n",
              [os:getenv("IMAGE", "unknown"), string:trim(Otp), erlang:system_info(version)]),
    Pre = [binary, {packet, line}, {active, false}, {reuseaddr, true}],

    section(1, "master at 68df44b6: the listen options of tcp_server.ex:135, no {ip, _}"),
    {ok, L1} = gen_tcp:listen(0, Pre),
    {B1, P1} = sock({ok, L1}),
    Ok1 = check(1, [{"bound address", {0, 0, 0, 0}, B1},
                    {"connect from <bridge-ip>", ok, connect(Eth, P1, [binary])},
                    {"connect ::1", {error, econnrefused}, connect(?LOOP6, P1, [binary, inet6])}]),
    close({ok, L1}),

    section(2, "first version of the pull request: the same options plus {ip, {127,0,0,1}}"),
    L2 = gen_tcp:listen(0, [{ip, ?LOOP4} | Pre]),
    {B2, P2} = sock(L2),
    Ok2 = check(2, [{"bound address", ?LOOP4, B2},
                    {"connect from <bridge-ip>", {error, econnrefused}, connect(Eth, P2, [binary])},
                    {"connect 127.0.0.1", ok, connect(?LOOP4, P2, [binary])}]),
    close(L2),

    section(3, "bridge script: gen_tcp:connect by the name \"localhost\", no family option"),
    L3 = gen_tcp:listen(0, [{ip, ?LOOP4} | Pre]),
    {_, P3} = sock(L3),
    Ok3 = check(3, [{"inet_db:res_option(inet6)", false, inet_db:res_option(inet6)},
                    {"inet:getaddr(\"localhost\", inet)", {ok, ?LOOP4}, inet:getaddr("localhost", inet)},
                    {"connect by the name \"localhost\"", ok, connect("localhost", P3, ?BRIDGE_OPTS)}]),
    close(L3),

    section(4, "the patch: mcpHost \"localhost\", the default"),
    {Res4, L4} = listen_host("localhost"),
    {B4, P4} = sock(L4),
    Ok4 = check(4, [{"resolve(\"localhost\")", {ok, ?LOOP4}, Res4},
                    {"bound address", ?LOOP4, B4},
                    {"connect from <bridge-ip>", {error, econnrefused}, connect(Eth, P4, [binary])},
                    {"connect 127.0.0.1", ok, connect(?LOOP4, P4, [binary])},
                    {"connect by the name \"localhost\"", ok, connect("localhost", P4, ?BRIDGE_OPTS)}]),
    close(L4),

    section(5, "the patch: mcpHost \"0.0.0.0\", a value that a user must choose"),
    {Res5, L5} = listen_host("0.0.0.0"),
    {B5, P5} = sock(L5),
    Ok5 = check(5, [{"resolve(\"0.0.0.0\")", {ok, {0, 0, 0, 0}}, Res5},
                    {"bound address", {0, 0, 0, 0}, B5},
                    {"connect from <bridge-ip>", ok, connect(Eth, P5, [binary])}]),
    close(L5),

    section(6, "the patch: mcpHost \"::1\", an 8-tuple, so the listen options get inet6"),
    {Res6, L6} = listen_host("::1"),
    {B6, P6} = sock(L6),
    Ok6 = check(6, [{"resolve(\"::1\")", {ok, ?LOOP6}, Res6},
                    {"bound address", ?LOOP6, B6},
                    {"connect ::1", ok, connect(?LOOP6, P6, [binary, inet6])},
                    {"connect 127.0.0.1", {error, econnrefused}, connect(?LOOP4, P6, [binary])}]),
    close(L6),

    Verdicts = [{1, Ok1}, {2, Ok2}, {3, Ok3}, {4, Ok4}, {5, Ok5}, {6, Ok6}],
    io:format("~nsummary: ~s~n", [lists:join(", ", [io_lib:format("case ~w ~s", [N, verdict(Ok)]) || {N, Ok} <- Verdicts])]),
    case lists:all(fun({_, Ok}) -> Ok end, Verdicts) of
        true -> io:format("done~n"), halt();
        false -> io:format("MISMATCH~n"), halt(1)
    end.

section(N, Title) -> io:format("~n## ~w. ~s~n", [N, Title]).

%% The patch resolves the setting mcpHost, default "localhost", exactly like this.
resolve(Name) ->
    case inet:getaddr(Name, inet) of
        {ok, IP} -> {ok, IP};
        {error, _} -> inet:getaddr(Name, inet6)
    end.

listen_host(Name) ->
    case resolve(Name) of
        {ok, IP} = Res ->
            Opts = [binary, {ip, IP}, {packet, line}, {active, false}, {reuseaddr, true}],
            {Res, gen_tcp:listen(0, Opts ++ [inet6 || tuple_size(IP) =:= 8])};
        Error ->
            {Error, Error}
    end.

%% A failed listen is recorded in place of the bound address, so a missing IPv6 loopback shows in the output.
sock({ok, L}) ->
    case inet:sockname(L) of
        {ok, {A, P}} -> {A, P};
        Error -> {Error, none}
    end;
sock(Error) -> {Error, none}.

connect(_, none, _) -> no_listener;
connect(Addr, Port, Opts) ->
    case gen_tcp:connect(Addr, Port, Opts, 800) of
        {ok, S} -> gen_tcp:close(S), ok;
        Other -> Other
    end.

close({ok, L}) -> gen_tcp:close(L);
close(_) -> ok.

check(N, Rows) ->
    lists:foldl(fun({Label, Want, Got}, Acc) ->
                        io:format("  -> ~ts -> ~w~n", [string:pad(Label, 34), Got]),
                        case Got of
                            Want -> Acc;
                            _ -> io:format("  MISMATCH case ~w: expected ~w~n", [N, Want]), false
                        end
                end, true, Rows).

verdict(true) -> "match";
verdict(false) -> "MISMATCH".
