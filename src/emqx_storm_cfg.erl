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

-module(emqx_storm_cfg).

-include("emqx_storm.hrl").
-include_lib("stdlib/include/qlc.hrl").

-export([init/0,
         all_bridges/0,
         add_bridge/2,
         insert_bridge/1,
         update_bridge/2,
         do_update_bridge/1,
         remove_bridge/1,
         lookup_bridge/1,
         ret/1]).

init() ->
    ok = ekka_mnesia:create_table(?TAB,
                                  [{disc_copies, [node()]},
                                   {attributes, record_info(fields, ?TAB)}]),
    ok = ekka_mnesia:copy_table(?TAB, disc_copies).

-spec(all_bridges() -> list()).
all_bridges() -> mnesia:dirty_all_keys(?TAB).

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

%% @doc Lookup bridge by id
-spec(lookup_bridge(atom()) -> list()).
lookup_bridge(Id) ->
    mnesia:dirty_read(?TAB, Id).

-spec ret(Args :: {atomic, ok} | {aborted, any()})
            -> ok | {error, Error :: any()}.
ret({atomic, ok})     -> ok;
ret({aborted, Error}) -> {error, Error}.
