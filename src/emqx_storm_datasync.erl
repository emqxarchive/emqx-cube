%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(emqx_storm_datasync).

-include("emqx_storm.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").
-include_lib("emqx/include/logger.hrl").
-include_lib("stdlib/include/qlc.hrl").

-export([mnesia/1]).

-export([list/1,
         update/1,
         lookup/1,
         add/1,
         delete/1,
         start/1,
         stop/1,
         status/1]).

-boot_mnesia({mnesia, [boot]}).
-copy_mnesia({mnesia, [copy]}).


%%------------------------------------------------------------------------------
%% Mnesia bootstrap
%%------------------------------------------------------------------------------

mnesia(boot) ->
    ok = ekka_mnesia:create_table(?TAB, [
                {type, set},
                {disc_copies, [node()]},
                {record_name, route},
                {attributes, record_info(fields, ?TAB)},
                {storage_properties, [{ets, [{read_concurrency, true},
                                             {write_concurrency, true}]}]}]);
mnesia(copy) ->
    ok = ekka_mnesia:copy_table(?TAB).

list(_Bindings) ->
    {ok, all_bridges()}.

update(#{id := Id, options := Options}) ->
    update_bridge(Id, Options).

lookup(#{id := Id}) ->
    {ok, lookup_bridge(Id)}.

add(#{id := Id, options := Options}) ->
    add_bridge(Id, Options).

delete(#{id := Id}) ->
    remove_bridge(Id).

start(#{id := Id}) ->
    start_bridge(Id).

stop(#{id := Id}) ->
    stop_bridge(Id).

status(_Bindings) ->
    bridge_status().


-spec(all_bridges() -> list()).
all_bridges() -> 
    ets:tab2list(?TAB).

-spec add_bridge(Id :: atom() | list(), Options :: tuple()) 
                -> ok | {error, any()}.
add_bridge(Id, Options) ->
    Config = #?TAB{id = Id, options = Options},
    ret(mnesia:transaction(fun insert_bridge/1, [Config])).

-spec insert_bridge(Bridge :: ?TAB()) ->  ok | no_return().
insert_bridge(Bridge = #?TAB{id = Id}) ->
    case mnesia:read(?TAB, Id) of
        [] -> mnesia:write(Bridge);
        [_ | _] -> mnesia:abort(existed)
    end.

-spec(update_bridge(atom(), list()) -> ok | {error, any()}).
update_bridge(Id, Options) ->
    Bridge = #?TAB{id = Id, options = Options},
    ret(mnesia:transaction(fun do_update_bridge/1, [Bridge])).

do_update_bridge(Bridge = #?TAB{id = Id}) ->
    case mnesia:read(?TAB, Id) of
        [_|_] -> mnesia:write(Bridge);
        [] -> mnesia:abort(noexisted)
    end.

-spec(remove_bridge(atom()) -> ok | {error, any()}).
remove_bridge(Id) ->
    ret(mnesia:transaction(fun mnesia:delete/1, 
                           [{?TAB, Id}])).

-spec(start_bridge(atom()) -> ok | {error, any()}).
start_bridge(Id) ->
    case lookup_bridge(Id) of
        {Id, Option} ->
            emqx_bridge_sup:create_bridge(Id, Option),
            emqx_bridge:ensure_started(Id);
        _ ->
            {error, bridge_not_found}
    end.

-spec(bridge_status() -> list()).
bridge_status() ->
    emqx_bridge_sup:bridges().

-spec(stop_bridge(atom()) -> ok| {error, any()}).
stop_bridge(Id) ->
    emqx_bridge_sup:drop_bridge(Id).

%% @doc Lookup bridge by id
-spec(lookup_bridge(atom()) -> tuple()).
lookup_bridge(Id) ->
    case mnesia:dirty_read(?TAB, Id) of
        [{?TAB, Id, Option}] ->
            {Id, Option};
        _ ->
            []
    end.

-spec ret(Args :: {atomic, ok} | {aborted, any()})
            -> ok | {error, Error :: any()}.
ret({atomic, ok})     -> ok;
ret({aborted, Error}) -> {error, Error}.
