%%%-----------------------------------------------------------------------------
%%% @title Servidor do Jogo Duelo
%%% @author João Barbosa, Diogo Silva, Pedro Oliveira
%%% @doc Servidor para o jogo multiplayer "Duelo" implementado como projeto
%%%      da disciplina de Programação Concorrente na Universidade do Minho.
%%%      O servidor gerencia autenticação, matchmaking, múltiplas partidas
%%%      simultâneas e sistema de ranking dos jogadores.
%%% @version 1.0
%%%-----------------------------------------------------------------------------
-module(server).
-export([start_server/0, ceiling/1]).

%%% Constantes do servidor
-define(Port, 5555).                 % Porta TCP utilizada para conexões
-define(ModifierSpawnInterval, 5000).% Intervalo (ms) entre spawn de modificadores
-define(MaxModifiersPerType, 3).     % Número máximo de modificadores de cada tipo por jogo

%%%=============================================================================
%%% API e Funções de Inicialização
%%%=============================================================================

%% @doc Inicia o servidor, configurando as tabelas ETS e escutando conexões
%% na porta definida. Esta é a função principal que deve ser chamada
%% para iniciar o servidor.
start_server() ->
    % Criação das tabelas ETS (Erlang Term Storage) para armazenar os dados do jogo
    % Cada tabela é pública para permitir acesso de diferentes processos
    ets:new(users, [named_table, public]),           % Armazena credenciais e estatísticas dos utilizadores
    ets:new(players, [named_table, public]),         % Jogadores atualmente conectados
    ets:new(waiting_players, [named_table, public]), % Jogadores à espera de uma partida (matchmaking)
    ets:new(active_games, [named_table, public]),    % Jogos atualmente ativos
    ets:new(modifiers, [named_table, public]),       % Modificadores ativos em cada jogo
    
    % Carrega utilizadores existentes do ficheiro
    load_users(),
    
    % Inicia a escuta de conexões TCP
    {ok, LSocket} = gen_tcp:listen(?Port, [binary, {packet, line}, {active, false}, {reuseaddr, true}]),
    io:format("Servidor iniciado na porta ~p...~n", [?Port]),
    
    % Inicia o loop de aceitação de conexões
    accept_loop(LSocket).

%% @doc Loop de aceitação de novas conexões. Para cada nova conexão,
%% cria um processo separado para lidar com o cliente.
accept_loop(LSocket) ->
    % Aguarda por uma nova conexão de cliente
    {ok, ASocket} = gen_tcp:accept(LSocket),
    
    % Cria um novo processo para tratar este cliente (concorrência)
    spawn(fun() -> handler(ASocket) end),
    
    % Continua à escuta de novas conexões
    accept_loop(LSocket).

%%%=============================================================================
%%% Funções de Gestão de Clientes
%%%=============================================================================

%% @doc Manipulador principal para uma conexão de cliente.
%% Inicia o processo de autenticação para um novo cliente.
handler(ASocket) ->
    % Obtém o PID do processo atual
    Pid = self(),
    io:format("Cliente ~p conectou...~n", [Pid]),
    
    % Configura o socket com timeout para deteção rápida de desconexão
    inet:setopts(ASocket, [{packet, line}, {send_timeout, 5000}]),
    
    % Inicia o loop de autenticação para este cliente
    auth_loop(ASocket, Pid).

%% @doc Loop de autenticação que processa comandos de login/registo.
%% Uma vez autenticado, o cliente passa para o main_loop.
auth_loop(ASocket, Pid) ->
    case gen_tcp:recv(ASocket, 0) of
        {ok, Data} ->
            Message = binary_to_list(Data),
            % Remove caracteres de nova linha
            CleanMessage = string:trim(Message),
            io:format("Recebido do cliente ~p: ~p~n", [Pid, CleanMessage]),
            
            % Processa comandos de autenticação
            case string:split(CleanMessage, ";", all) of
                ["LOGIN", Username, Password | _] ->
                    handle_login(ASocket, Pid, Username, Password);
                ["REGISTER", Username, Password | _] ->
                    handle_register(ASocket, Pid, Username, Password);
                _ ->
                    % Comando desconhecido no modo de autenticação
                    Response = "LOGIN_FAILED;Comando inválido",
                    gen_tcp:send(ASocket, list_to_binary(Response ++ "\n")),
                    auth_loop(ASocket, Pid)
            end;
            
        {error, closed} ->
            io:format("Cliente ~p desconectou durante a autenticação~n", [Pid])
    end.

%% @doc Loop principal que processa mensagens de jogo após autenticação.
%% Este loop trata todos os comandos de jogo como movimentos, tiros e colisões.
main_loop(ASocket, Pid, Username) ->
    case gen_tcp:recv(ASocket, 0) of
        {ok, Data} ->
            Message = binary_to_list(Data),
            % Remove caracteres de nova linha
            CleanMessage = string:trim(Message),
            
            % Processa mensagens relacionadas ao jogo
            case string:split(CleanMessage, ";", all) of
                ["LOGOUT" | _] ->
                    % Limpa o estado do jogador no logout explícito
                    handle_logout(ASocket, Pid, Username);
                
                ["MATCHMAKE" | _] ->
                    % Inicia processo de matchmaking
                    handle_matchmaking(ASocket, Pid, Username),
                    main_loop(ASocket, Pid, Username);
                
                ["FORFEIT", PlayerPid | _] ->
                    % Trata solicitação de desistência
                    handle_forfeit(Pid, list_to_pid(PlayerPid)),
                    main_loop(ASocket, Pid, Username);
                
                ["LEADERBOARD" | _] ->
                    % Envia tabela de classificação
                    send_leaderboard(ASocket),
                    main_loop(ASocket, Pid, Username);
                
                ["BULLET", _X, _Y, _TargetX, _TargetY, _ShooterPid | _] ->
                    % Repassa informação de disparo para todos os clientes no mesmo jogo
                    broadcast_to_game(Pid, Data),
                    main_loop(ASocket, Pid, Username);
                
                ["HIT", X, Y, ShooterPid | _] ->
                    % Processa acerto de tiro e atualiza pontuações
                    handle_hit(Pid, X, Y, ShooterPid),
                    broadcast_to_game(Pid, Data),
                    main_loop(ASocket, Pid, Username);
                
                ["MODIFIER_PICKUP", X, Y, PlayerPid | _] ->
                    % Processa coleta de modificador
                    handle_modifier_pickup(Pid, X, Y, PlayerPid),
                    broadcast_to_game(Pid, Data),
                    main_loop(ASocket, Pid, Username);
                
                ["WALL_COLLISION", PlayerPid | _] ->
                    % Processa colisão com parede - adiciona 2 pontos ao oponente
                    handle_wall_collision(Pid, PlayerPid),
                    broadcast_to_game(Pid, Data),
                    main_loop(ASocket, Pid, Username);
                
                ["CANCEL_MATCHMAKING" | _] ->
                    % Remove jogador da fila de espera
                    ets:delete(waiting_players, Pid),
                    io:format("Jogador ~p (~p) cancelou matchmaking~n", [Pid, Username]),
                    main_loop(ASocket, Pid, Username);
                
                [_ClientPid, _X, _Y | _] ->
                    % Atualização de posição do jogador
                    broadcast_to_game(Pid, Data),
                    main_loop(ASocket, Pid, Username);
                
                _ ->
                    % Comando desconhecido
                    main_loop(ASocket, Pid, Username)
            end;
            
        {error, closed} ->
            % Trata desconexão do cliente
            handle_disconnect(Pid, Username),
            io:format("Cliente ~p (~p) desconectou~n", [Pid, Username])
    end.

%%%=============================================================================
%%% Funções de Autenticação e Gestão de Utilizadores
%%%=============================================================================

%% @doc Processa tentativa de login verificando credenciais
%% Se bem-sucedido, transiciona para o loop principal
handle_login(ASocket, Pid, Username, Password) ->
    case ets:lookup(users, Username) of
        [{Username, StoredPassword, Level, Streak}] ->
            case StoredPassword =:= Password of
                true ->
                    % Verifica se o usuário já está conectado
                    ActiveSessions = ets:match_object(players, {'_', '_', Username}),
                    case ActiveSessions of
                        [] ->
                            % Usuário não está conectado, login bem-sucedido
                            ets:insert(players, {Pid, ASocket, Username}),
                            
                            % Envia resposta de sucesso com estatísticas do jogador
                            Response = io_lib:format("LOGIN_SUCCESS;~p;~p;~p;~p", 
                                                    [Level, max(0, Streak), min(0, Streak), Pid]),
                            gen_tcp:send(ASocket, list_to_binary(Response ++ "\n")),
                            
                            % Envia tabela de classificação
                            send_leaderboard(ASocket),
                            
                            % Muda para o loop principal
                            main_loop(ASocket, Pid, Username);
                        
                        _ ->
                            % Usuário já está conectado
                            Response = "LOGIN_FAILED;User already logged in elsewhere",
                            gen_tcp:send(ASocket, list_to_binary(Response ++ "\n")),
                            auth_loop(ASocket, Pid)
                    end;
                
                false ->
                    % Senha incorreta
                    Response = "LOGIN_FAILED;Nome de utilizador ou senha inválidos",
                    gen_tcp:send(ASocket, list_to_binary(Response ++ "\n")),
                    auth_loop(ASocket, Pid)
            end;
        
        [] ->
            % Utilizador não encontrado
            Response = "LOGIN_FAILED;Nome de utilizador ou senha inválidos",
            gen_tcp:send(ASocket, list_to_binary(Response ++ "\n")),
            auth_loop(ASocket, Pid)
    end.

%% @doc Processa tentativa de registo de novo utilizador
%% Verifica se nome de utilizador está disponível
handle_register(ASocket, Pid, Username, Password) ->
    case ets:lookup(users, Username) of
        [] ->
            % Nome de utilizador disponível, regista novo utilizador
            ets:insert(users, {Username, Password, 1, 0}), % Nível 1, Streak 0
            save_users(), % Guarda lista de utilizadores atualizada
            
            Response = "REGISTER_SUCCESS",
            gen_tcp:send(ASocket, list_to_binary(Response ++ "\n")),
            auth_loop(ASocket, Pid);
        
        _ ->
            % Nome de utilizador já existe
            Response = "REGISTER_FAILED;Nome de utilizador já existe",
            gen_tcp:send(ASocket, list_to_binary(Response ++ "\n")),
            auth_loop(ASocket, Pid)
    end.

%% @doc Processa logout explícito de um utilizador
%% Limpa todos os estados associados e retorna ao loop de autenticação
handle_logout(ASocket, Pid, Username) ->
    % Remove da fila de espera se presente
    ets:delete(waiting_players, Pid),
    
    % Trata desistência se estiver num jogo
    case get_game_id(Pid) of
        {ok, _GameId} -> 
            handle_forfeit(Pid, Pid),  % Usa o próprio Pid como PlayerPid
            ok;
        _ -> ok
    end,
    
    % Atualiza registo do jogador para remover associação com jogo
    case ets:lookup(players, Pid) of
        [{Pid, _Socket, Username, _GameIdUnused}] ->
            % Use a different variable name to avoid the unsafe variable error
            ets:insert(players, {Pid, ASocket, Username});
        _ -> ok
    end,
    
    io:format("Jogador ~p (~p) fez logout~n", [Pid, Username]),
    
    % Retorna ao loop de autenticação
    auth_loop(ASocket, Pid).

%%%=============================================================================
%%% Funções de Matchmaking e Gestão de Jogos
%%%=============================================================================

%% @doc Inicia o processo de matchmaking para um jogador
%% Adiciona o jogador à fila de espera e tenta encontrar uma correspondência
handle_matchmaking(ASocket, Pid, Username) ->
    % Obtém o nível deste jogador
    [{Username, _, Level, _}] = ets:lookup(users, Username),
    
    % Adiciona jogador à fila de espera
    ets:insert(waiting_players, {Pid, ASocket, Username, Level}),
    io:format("Jogador ~p (~p) entrou na fila de matchmaking (Nível ~p)~n", [Pid, Username, Level]),
    
    % Tenta encontrar uma correspondência
    find_match().

%% @doc Tenta encontrar correspondências entre jogadores na fila de espera
%% Busca jogadores com diferença máxima de um nível
find_match() ->
    % Obtém todos os jogadores em espera
    WaitingPlayers = ets:tab2list(waiting_players),
    
    % Encontra correspondências possíveis (jogadores com diferença de nível <= 1)
    find_possible_match(WaitingPlayers).

%% @doc Função recursiva que tenta encontrar pares compatíveis de jogadores
find_possible_match([]) ->
    % Nenhuma correspondência encontrada
    ok;
find_possible_match([{Pid1, Socket1, Username1, Level1} | Rest]) ->
    % Tenta encontrar uma correspondência para o primeiro jogador
    PossibleMatch = lists:search(
        fun({Pid2, _, _, Level2}) ->
            (Pid1 =/= Pid2) and (abs(Level1 - Level2) =< 1)
        end,
        Rest
    ),
    
    case PossibleMatch of
        {value, {Pid2, Socket2, Username2, Level2}} ->
            % Correspondência encontrada, inicia um jogo
            start_game(Pid1, Socket1, Username1, Level1, Pid2, Socket2, Username2, Level2);
        
        false ->
            % Nenhuma correspondência para este jogador, tenta o próximo
            find_possible_match(Rest)
    end.

%% @doc Inicia uma nova partida entre dois jogadores
%% Configura o estado inicial da partida e envia mensagens de início
start_game(Pid1, Socket1, Username1, Level1, Pid2, Socket2, Username2, Level2) ->
    % Remove jogadores da fila de espera
    ets:delete(waiting_players, Pid1),
    ets:delete(waiting_players, Pid2),
    
    % Gera um ID único para o jogo
    GameId = erlang:system_time(),
    
    % Cria um novo jogo com pontuações inicializadas em 0
    ets:insert(active_games, {GameId, [{Pid1, Username1, 0}, {Pid2, Username2, 0}]}),
    
    % Associa jogadores ao jogo
    ets:insert(players, {Pid1, Socket1, Username1, GameId}),
    ets:insert(players, {Pid2, Socket2, Username2, GameId}),
    
    io:format("Iniciando jogo ~p entre ~p (Nível ~p) e ~p (Nível ~p)~n", 
              [GameId, Username1, Level1, Username2, Level2]),
    
    % Envia mensagem de correspondência encontrada para ambos os jogadores com posições de spawn
    Message1 = io_lib:format("MATCH_FOUND;200;100", []),
    Message2 = io_lib:format("MATCH_FOUND;600;500", []),
    gen_tcp:send(Socket1, list_to_binary(Message1 ++ "\n")),
    gen_tcp:send(Socket2, list_to_binary(Message2 ++ "\n")),
    
    % Aguarda um momento antes de iniciar o jogo
    timer:sleep(3000),
    
    % Inicia geração de modificadores para este jogo
    spawn(fun() -> modifier_generator(GameId) end),
    
    % Envia mensagem de início para ambos os jogadores
    StartMessage = "START",
    gen_tcp:send(Socket1, list_to_binary(StartMessage ++ "\n")),
    gen_tcp:send(Socket2, list_to_binary(StartMessage ++ "\n")),
    
    % Envia atualização de pontuação inicial para sincronizar (0-0)
    send_score_update(GameId),
    
    % Agenda o fim do jogo após 2 minutos
    spawn(fun() ->
        timer:sleep(120000), % 2 minutos
        end_game(GameId)
    end).

%% @doc Finaliza uma partida, atualiza estatísticas e notifica os jogadores
%% Chamada automaticamente após o tempo da partida ou por desistência
end_game(GameId) ->
    case ets:lookup(active_games, GameId) of
        [{GameId, Players}] ->
            % Obtém pontuações
            [{Pid1, Username1, Score1}, {Pid2, Username2, Score2}] = Players,
            
            io:format("Jogo ~p terminado: ~p (~p) vs ~p (~p)~n", 
                      [GameId, Username1, Score1, Username2, Score2]),
            
            % Determina vencedor e atualiza estatísticas
            if
                Score1 > Score2 ->
                    update_stats(Username1, win),
                    update_stats(Username2, loss),
                    _Winner = Username1;  % Prefixo com underscore para indicar não utilizado intencionalmente
                Score2 > Score1 ->
                    update_stats(Username1, loss),
                    update_stats(Username2, win),
                    _Winner = Username2;
                true ->
                    % Empate - sem alteração de estatísticas
                    _Winner = "tie"
            end,
            
            % Envia mensagem de fim para ambos os jogadores
            % Resolve problemas de escopo das variáveis socket usando consultas separadas
            case ets:lookup(players, Pid1) of
                [{Pid1, Socket1, _, _}] ->
                    case ets:lookup(users, Username1) of
                        [{Username1, _, Level1, Streak1}] ->
                            % Calcula valores de streak adequados - positivo para vitórias, negativo para derrotas
                            WinStreak = max(0, Streak1),
                            LossStreak = min(0, Streak1),
                            EndMessage1 = io_lib:format("END;~p;~p;~p", [Level1, WinStreak, LossStreak]),
                            gen_tcp:send(Socket1, list_to_binary(EndMessage1 ++ "\n"));
                        _ -> ok
                    end;
                _ -> ok
            end,
            
            case ets:lookup(players, Pid2) of
                [{Pid2, Socket2, _, _}] ->
                    case ets:lookup(users, Username2) of
                        [{Username2, _, Level2, Streak2}] ->
                            EndMessage2 = io_lib:format("END;~p;~p;~p", [Level2, max(0, Streak2), min(0, Streak2)]),
                            gen_tcp:send(Socket2, list_to_binary(EndMessage2 ++ "\n"));
                        _ -> ok
                    end;
                _ -> ok
            end,
            
            % Limpa dados do jogo
            ets:delete(active_games, GameId),
            
            % Atualiza registos de jogadores para remover associação com o jogo
            case ets:lookup(players, Pid1) of
                [{Pid1, Socket1a, Username1, _}] ->
                    ets:insert(players, {Pid1, Socket1a, Username1});
                _ -> ok
            end,
            
            case ets:lookup(players, Pid2) of
                [{Pid2, Socket2a, Username2, _}] ->
                    ets:insert(players, {Pid2, Socket2a, Username2});
                _ -> ok
            end,
            
            % Limpa quaisquer modificadores associados a este jogo
            ets:match_delete(modifiers, {'_', GameId, '_', '_', '_'});
        
        [] ->
            % Jogo não encontrado, já finalizado
            ok
    end.

%% @doc Processa desistência de um jogador
%% Atualiza estatísticas e finaliza o jogo
handle_forfeit(Pid, _PlayerPid) ->
    % Verifica se o jogador está num jogo
    case get_game_id(Pid) of
        {ok, GameId} ->
            case ets:lookup(active_games, GameId) of
                [{GameId, Players}] ->
                    % Obtém ambos os jogadores
                    [{Pid1, Username1, _}, {Pid2, Username2, _}] = Players,
                    
                    io:format("Jogador ~p (~p) desistiu do jogo ~p contra ~p~n", 
                              [Pid, 
                               if Pid =:= Pid1 -> Username1; true -> Username2 end,
                               GameId,
                               if Pid =:= Pid1 -> Username2; true -> Username1 end]),
                    
                    % Determina vencedor e perdedor
                    {WinnerPid, WinnerUsername, LoserPid, LoserUsername} = 
                        if 
                            Pid =:= Pid1 -> {Pid2, Username2, Pid1, Username1};
                            true -> {Pid1, Username1, Pid2, Username2}
                        end,
                    
                    % Atualiza estatísticas - vencedor recebe uma vitória, desistente recebe uma derrota
                    update_stats(WinnerUsername, win),
                    update_stats(LoserUsername, loss),
                    
                    % Envia confirmação de desistência para ambos os jogadores
                    send_forfeit_confirmation(WinnerPid, LoserPid),
                    
                    % Limpa o jogo
                    ets:delete(active_games, GameId),
                    
                    % Atualiza registos de jogadores para remover associação com o jogo
                    case ets:lookup(players, Pid1) of
                        [{Pid1, Socket1, Username1, _}] ->
                            ets:insert(players, {Pid1, Socket1, Username1});
                        _ -> ok
                    end,
                    
                    case ets:lookup(players, Pid2) of
                        [{Pid2, Socket2, Username2, _}] ->
                            ets:insert(players, {Pid2, Socket2, Username2});
                        _ -> ok
                    end,
                    
                    % Limpa modificadores
                    ets:match_delete(modifiers, {'_', GameId, '_', '_', '_'});
                
                [] ->
                    % Jogo não encontrado
                    ok
            end;
        
        _ ->
            % Jogador não está num jogo
            ok
    end.

%% @doc Envia mensagem de confirmação de desistência para ambos os jogadores
send_forfeit_confirmation(WinnerPid, LoserPid) ->
    % Envia para o vencedor
    case ets:lookup(players, WinnerPid) of
        [{WinnerPid, WinnerSocket, WinnerUsername, _}] ->
            case ets:lookup(users, WinnerUsername) of
                [{WinnerUsername, _, WinnerLevel, WinnerStreak}] ->
                    WinMessage = io_lib:format("FORFEIT_CONFIRM;~p;~p;~p", 
                                              [WinnerLevel, max(0, WinnerStreak), min(0, WinnerStreak)]),
                    gen_tcp:send(WinnerSocket, list_to_binary(WinMessage ++ "\n"));
                _ -> ok
            end;
        _ -> ok
    end,
    
    % Envia para o perdedor
    case ets:lookup(players, LoserPid) of
        [{LoserPid, LoserSocket, LoserUsername, _}] ->
            case ets:lookup(users, LoserUsername) of
                [{LoserUsername, _, LoserLevel, LoserStreak}] ->
                    LoseMessage = io_lib:format("FORFEIT_CONFIRM;~p;~p;~p", 
                                               [LoserLevel, max(0, LoserStreak), min(0, LoserStreak)]),
                    gen_tcp:send(LoserSocket, list_to_binary(LoseMessage ++ "\n"));
                _ -> ok
            end;
        _ -> ok
    end.

%%%=============================================================================
%%% Funções de Eventos do Jogo
%%%=============================================================================

%% @doc Processa acerto de projétil e atualiza pontuações
handle_hit(Pid, _X, _Y, ShooterPid) ->
    % Incrementa pontuação para o atirador
    case get_game_id(Pid) of
        {ok, GameId} ->
            case ets:lookup(active_games, GameId) of
                [{GameId, Players}] ->
                    % Encontra o atirador na lista de jogadores e incrementa pontuação
                    UpdatedPlayers = lists:map(
                        fun({PlayerPid, PlayerName, Score}) ->
                            case PlayerPid =:= list_to_pid(ShooterPid) of
                                true -> {PlayerPid, PlayerName, Score + 1};
                                false -> {PlayerPid, PlayerName, Score}
                            end
                        end,
                        Players
                    ),
                    ets:insert(active_games, {GameId, UpdatedPlayers}),
                    
                    % Envia atualização de pontuação para todos os jogadores
                    send_score_update(GameId);
                
                [] ->
                    % Jogo não encontrado
                    ok
            end;
        
        _ ->
            % Jogador não está num jogo
            ok
    end.

%% @doc Processa coleta de modificador
handle_modifier_pickup(Pid, X, Y, _PlayerPid) ->
    % Encontra e remove o modificador
    case get_game_id(Pid) of
        {ok, GameId} ->
            ModifierId = {X, Y, GameId},
            case ets:lookup(modifiers, ModifierId) of
                [{ModifierId, GameId, X, Y, _Type}] ->
                    % Remove o modificador
                    ets:delete(modifiers, ModifierId);
                
                [] ->
                    % Modificador não encontrado
                    ok
            end;
        
        _ ->
            % Jogador não está num jogo
            ok
    end.

%% @doc Processa colisão com parede, adiciona pontos ao oponente
handle_wall_collision(Pid, _PlayerPid) ->
    % Encontra o jogo e o outro jogador
    case get_game_id(Pid) of
        {ok, GameId} ->
            case ets:lookup(active_games, GameId) of
                [{GameId, Players}] ->
                    % Encontra o outro jogador e adiciona 2 pontos
                    UpdatedPlayers = lists:map(
                        fun({PlayerPid, PlayerName, Score}) ->
                            case PlayerPid =:= Pid of
                                true -> {PlayerPid, PlayerName, Score};
                                false -> {PlayerPid, PlayerName, Score + 2}
                            end
                        end,
                        Players
                    ),
                    ets:insert(active_games, {GameId, UpdatedPlayers}),
                    
                    % Envia atualização de pontuação para todos os jogadores
                    send_score_update(GameId),
                    
                    % Envia mensagem de resetpositions para todos os jogadores
                    send_reset_positions(GameId);
                
                [] ->
                    % Jogo não encontrado
                    ok
            end;
        
        _ ->
            % Jogador não está num jogo
            ok
    end.

%% @doc Envia comando para restaurar posições dos jogadores após colisão com parede
send_reset_positions(GameId) ->
    % Obtém todos os jogadores no jogo
    case ets:lookup(active_games, GameId) of
        [{GameId, Players}] ->
            % Envia mensagem de reset para ambos os jogadores
            Message = "RESET_POSITIONS",
            lists:foreach(
                fun({PlayerPid, _, _}) ->
                    case ets:lookup(players, PlayerPid) of
                        [{PlayerPid, Socket, _, _}] ->
                            gen_tcp:send(Socket, list_to_binary(Message ++ "\n"));
                        _ -> ok
                    end
                end,
                Players
            );
        
        [] ->
            % Jogo não encontrado
            ok
    end.

%% @doc Processa desconexão de cliente, atualiza estado do jogo se necessário
handle_disconnect(Pid, Username) ->
    % Remove de todas as estruturas possíveis
    ets:delete(players, Pid),
    ets:delete(waiting_players, Pid),
    
    % Verifica se o jogador estava num jogo
    case get_game_id(Pid) of
        {ok, GameId} ->
            % Finaliza o jogo se ainda estiver ativo
            case ets:lookup(active_games, GameId) of
                [{GameId, Players}] ->
                    % Encontra oponente e envia notificação de desistência
                    [{OppPid, OppName, _}] = [P || P = {PPid, _, _} <- Players, PPid =/= Pid],
                    io:format("Jogador ~p (~p) desconectou durante jogo contra ~p~n", 
                              [Pid, Username, OppName]),
                    
                    % Atualiza estatísticas (desconexão conta como desistência)
                    update_stats(OppName, win),
                    update_stats(Username, loss),
                    
                    % Envia confirmação de desistência ao oponente
                    case ets:lookup(players, OppPid) of
                        [{OppPid, OppSocket, _, _}] ->
                            case ets:lookup(users, OppName) of
                                [{OppName, _, Level, Streak}] ->
                                    Message = io_lib:format("FORFEIT_CONFIRM;~p;~p;~p", 
                                                          [Level, max(0, Streak), min(0, Streak)]),
                                    gen_tcp:send(OppSocket, list_to_binary(Message ++ "\n"));
                                _ -> ok
                            end;
                        _ -> ok
                    end;
                [] -> ok
            end,
            
            % Limpa o jogo
            ets:delete(active_games, GameId),
            ets:match_delete(modifiers, {'_', GameId, '_', '_', '_'});
        _ -> ok
    end.

%%%=============================================================================
%%% Funções de Atualização de Estado e Estatísticas
%%%=============================================================================

%% @doc Atualiza estatísticas de um jogador após uma partida
%% Aplica regras do sistema de níveis e streaks
update_stats(Username, Result) ->
    case ets:lookup(users, Username) of
        [{Username, Password, Level, Streak}] ->
            % Calcula novo streak
            NewStreak = case {Result, Streak} of
                {win, S} when S >= 0 -> S + 1;  % Continua streak de vitórias ou inicia novo
                {win, _} -> 1;                  % reinicia streak negativo, inicia streak de vitórias
                {loss, S} when S =< 0 -> S - 1; % Continua streak de derrotas ou inicia novo
                {loss, _} -> -1                 % reinicia streak positivo, inicia streak de derrotas
            end,
            
            % Calcula o threshold para descer de nível (ceiling(Level/2))
            LevelDownThreshold = ceiling(Level/2),
            
            % Verifica mudanças de nível baseadas em streaks
            NewLevel = 
                if
                    % Sobe de nível quando consegue Level vitórias consecutivas
                    Result =:= win andalso NewStreak >= Level -> 
                        Level + 1;
                    
                    % Desce de nível quando perde ceiling(Level/2) partidas consecutivas
                    Result =:= loss andalso NewStreak =< 0 andalso abs(NewStreak) >= LevelDownThreshold -> 
                        max(1, Level - 1);
                    
                    % Sem mudança
                    true -> 
                        Level
                end,
            
            % NÃO reinicia o streak após mudança de nível - removida a lógica que reiniciava o streak
            FinalStreak = NewStreak,  % Mantém o streak independentemente da mudança de nível
            
            % Output de debug para ajudar a diagnosticar problemas
            io:format("Estatísticas atualizadas para ~p: Nível ~p->~p, Streak ~p->~p~n", 
                     [Username, Level, NewLevel, Streak, FinalStreak]),
            
            % Atualiza dados do utilizador
            ets:insert(users, {Username, Password, NewLevel, FinalStreak}),
            save_users();
        
        [] ->
            % Utilizador não encontrado, não deveria acontecer
            ok
    end.

%% @doc Envia atualização de pontuação para todos os jogadores em uma partida
send_score_update(GameId) ->
    case ets:lookup(active_games, GameId) of
        [{GameId, Players}] ->
            % Extrai informações dos jogadores
            [Player1, Player2] = Players,
            {_, _, Score1} = Player1,
            {_, _, Score2} = Player2,
            
            % Cria mensagem de atualização de pontuação que inclui PIDs
            Message = io_lib:format("SCORES;player1;~p;player2;~p", [Score1, Score2]),
            
            % Envia para ambos os jogadores
            lists:foreach(
                fun({PlayerPid, _, _}) ->
                    case ets:lookup(players, PlayerPid) of
                        [{PlayerPid, Socket, _, _}] ->
                            gen_tcp:send(Socket, list_to_binary(Message ++ "\n"));
                        _ -> ok
                    end
                end,
                Players
            );
        
        [] ->
            % Jogo não encontrado
            ok
    end.

%%%=============================================================================
%%% Funções de Comunicação
%%%=============================================================================

%% @doc Envia tabela de classificação para um cliente
send_leaderboard(Socket) ->
    % Obtém todos os utilizadores
    AllUsers = ets:tab2list(users),
    
    % Ordena por nível (decrescente) e depois por streak (decrescente)
    SortedUsers = lists:sort(
        fun({_, _, Level1, Streak1}, {_, _, Level2, Streak2}) ->
            if
                Level1 > Level2 -> true;
                Level1 < Level2 -> false;
                true -> Streak1 > Streak2  % Maior streak aparece primeiro (incluindo negativos)
            end
        end,
        AllUsers
    ),
    
    % Seleciona os 10 melhores
    TopUsers = lists:sublist(SortedUsers, 10),
    
    % Formata a mensagem da tabela de classificação - agora incluindo estatísticas de vitórias/derrotas
    % Calculamos vitórias como max(0, Streak) e derrotas como abs(min(0, Streak))
    Leaderboard = "LEADERBOARD" ++ lists:flatten([
        io_lib:format(";~s;~p;~p;~p;~p", [
            Username, 
            Level, 
            Streak,
            max(0, Streak),             % Vitórias: máximo entre 0 e streak
            abs(min(0, Streak))        % Derrotas: valor absoluto do mínimo entre 0 e streak
        ])
        || {Username, _, Level, Streak} <- TopUsers
    ]),
    
    % Envia ao cliente
    gen_tcp:send(Socket, list_to_binary(Leaderboard ++ "\n")).

%% @doc Transmite uma mensagem para todos os jogadores no mesmo jogo
broadcast_to_game(SenderPid, Data) ->
    case get_game_id(SenderPid) of
        {ok, GameId} ->
            % Obtém todos os jogadores no jogo
            case ets:lookup(active_games, GameId) of
                [{GameId, Players}] ->
                    % Obtém o socket para cada jogador e envia a mensagem
                    lists:foreach(
                        fun({PlayerPid, _, _}) ->
                            case ets:lookup(players, PlayerPid) of
                                [{PlayerPid, Socket, _, _}] ->
                                    if
                                        PlayerPid =/= SenderPid ->
                                            gen_tcp:send(Socket, Data);
                                        true -> ok
                                    end;
                                _ -> ok
                            end
                        end,
                        Players
                    );
                
                [] ->
                    % Jogo não encontrado
                    ok
            end;
        
        _ ->
            % Jogador não está num jogo
            ok
    end.

%% @doc Obtém o ID do jogo atual de um jogador
get_game_id(Pid) ->
    case ets:lookup(players, Pid) of
        [{Pid, _, _, GameId}] -> {ok, GameId};
        _ -> error
    end.

%%%=============================================================================
%%% Funções de Gestão de Modificadores
%%%=============================================================================

%% @doc Gera modificadores para um jogo em intervalos regulares
modifier_generator(GameId) ->
    % Verifica se o jogo ainda está ativo
    case ets:lookup(active_games, GameId) of
        [{GameId, _}] ->
            % Gera um modificador aleatório
            spawn_modifier(GameId),
            
            % Agenda próxima geração de modificador
            timer:sleep(?ModifierSpawnInterval),
            modifier_generator(GameId);
        
        [] ->
            % Jogo encerrado, para de gerar modificadores
            ok
    end.

%% @doc Cria um novo modificador no mapa, escolhendo um tipo disponível
%% e notificando os jogadores
spawn_modifier(GameId) ->
    % Conta quantos modificadores de cada tipo já existem
    ModifierCounts = lists:foldl(
        fun(Type, Acc) ->
            Count = length(ets:match(modifiers, {'_', GameId, '_', '_', Type})),
            [{Type, Count} | Acc]
        end,
        [],
        [0, 1, 2, 3] % Verde, Laranja, Azul, Vermelho
    ),
    
    % Encontra tipos que não atingiram seu limite
    AvailableTypes = [Type || {Type, Count} <- ModifierCounts, Count < ?MaxModifiersPerType],
    
    case AvailableTypes of
        [] ->
            % Todos os tipos de modificadores no máximo
            ok;
        
        Types ->
            % Escolhe um tipo aleatório dentre os disponíveis
            Type = lists:nth(rand:uniform(length(Types)), Types),
            
            % Gera posição aleatória dentro da área de jogo
            X = 50 + rand:uniform(700),
            Y = 50 + rand:uniform(500),
            
            % Cria o modificador
            ModifierId = {X, Y, GameId},
            ets:insert(modifiers, {ModifierId, GameId, X, Y, Type}),
            
            % Notifica todos os jogadores no jogo
            notify_modifier(GameId, X, Y, Type)
    end.

%% @doc Envia notificação sobre novo modificador para todos os jogadores num jogo
notify_modifier(GameId, X, Y, Type) ->
    % Obtém todos os jogadores no jogo
    case ets:lookup(active_games, GameId) of
        [{GameId, Players}] ->
            % Constrói mensagem de modificador
            Message = io_lib:format("MODIFIER;~p;~p;~p", [X, Y, Type]),
            
            % Envia para todos os jogadores
            lists:foreach(
                fun({PlayerPid, _, _}) ->
                    case ets:lookup(players, PlayerPid) of
                        [{PlayerPid, Socket, _, _}] ->
                            gen_tcp:send(Socket, list_to_binary(Message ++ "\n"));
                        _ -> ok
                    end
                end,
                Players
            );
        
        [] ->
            % Jogo não encontrado
            ok
    end.

%%%=============================================================================
%%% Funções de Persistência de Dados
%%%=============================================================================

%% @doc Carrega utilizadores do ficheiro
%% Restabelece o estado do servidor a partir de dados persistentes
load_users() ->
    case file:consult("users.dat") of
        {ok, [UserList]} when is_list(UserList) ->
            % O ficheiro contém um único termo que é uma lista de utilizadores
            lists:foreach(
                fun({Username, Password, Level, Streak}) ->
                    ets:insert(users, {Username, Password, Level, Streak})
                end,
                UserList
            ),
            io:format("Carregados ~p utilizadores do ficheiro~n", [length(UserList)]);
        
        {ok, Users} when is_list(Users) ->
            % O ficheiro contém uma lista de tuplas de utilizadores diretamente
            lists:foreach(
                fun({Username, Password, Level, Streak}) ->
                    ets:insert(users, {Username, Password, Level, Streak})
                end,
                Users
            ),
            io:format("Carregados ~p utilizadores do ficheiro~n", [length(Users)]);
        
        {error, _} ->
            io:format("Nenhum ficheiro de utilizadores encontrado ou erro ao ler. Iniciando com base de dados de utilizadores vazia.~n")
    end.

%% @doc Guarda utilizadores em ficheiro para persistência
save_users() ->
    Users = ets:tab2list(users),
    file:write_file("users.dat", io_lib:format("~p.~n", [Users])).

%% @doc Função auxiliar para calcular teto (já que não está disponível em todas as versões de Erlang)
ceiling(X) when X < 0 ->
    trunc(X);
ceiling(X) ->
    T = trunc(X),
    case X - T of
        0 -> T;
        _ -> T + 1
    end.
