# Duelo - Jogo multiplayer

## Visão Geral

Duelo é um jogo multiplayer online desenvolvido como projeto para a Unidade Curricular de Programação Concorrente do 3º ano de Licenciatura em Ciências da Computação da Universidade do Minho. O jogo implementa uma arquitetura cliente-servidor, onde o cliente é desenvolvido em Java (Processing) e o servidor em Erlang.

## Funcionalidades Principais

- **Sistema de Autenticação**: Registo e login de utilizadores
- **Matchmaking**: Emparelhamento de jogadores de nível semelhante
- **Níveis e Progressão**: Sistema de níveis baseado no desempenho do jogador
- **Múltiplas Partidas**: Suporte para várias partidas simultâneas
- **Leaderboard**: Classificação dos melhores jogadores

## Gameplay

- Jogadores controlam avatares num espaço 2D
- O movimento tem inércia e aceleração progressiva
- Jogadores podem disparar projéteis contra adversários
- Modificadores aparecem aleatoriamente e alteram as capacidades do jogador:
  - **Verde**: Aumenta velocidade dos projéteis
  - **Laranja**: Diminui velocidade dos projéteis
  - **Azul**: Reduz tempo entre disparos
  - **Vermelho**: Aumenta tempo entre disparos
- Sistema de pontuação:
  - +1 ponto por acertar no adversário
  - +2 pontos quando o adversário colide com paredes
- Partidas duram 2 minutos

## Arquitetura Técnica

### Cliente (Java/Processing)
- Interface gráfica com múltiplos estados (login, menu, jogo, etc.)
- Sistema de física para movimento com inércia
- Comunicação com o servidor via sockets TCP
- deteção de colisões local

### Servidor (Erlang)
- Gestão de utilizadores e suas estatísticas
- Coordenação de partidas e matchmaking
- Geração de modificadores
- Processamento de pontuação
- Atualização do sistema de níveis

## Protocolos de Comunicação

O cliente e servidor comunicam através de mensagens de texto simples separadas por ponto e vírgula (`;`), permitindo autenticação, envio de comandos e sincronização do estado do jogo.

## Como Jogar

1. Registe-se ou faça login
2. No menu principal, clique em "Play Game" para iniciar matchmaking
3. Controle seu avatar usando as teclas WASD ou setas
4. Clique para disparar projéteis na direção do cursor
5. Colete modificadores para obter vantagens
6. Evite colidir com paredes ou projéteis inimigos
7. Ganhe pontos acertando no adversário ou fazendo-o colidir com paredes
8. O jogador com mais pontos após 2 minutos vence

## Requisitos do Sistema

- Java 8 ou superior com Processing 3
- Erlang OTP 24 ou superior (para o servidor)
- Conexão de rede

### Demo
![Demo](https://github.com/diogocsilva12/ProjetoPC/blob/1cadea4fd0b33f715e814022bfd221e6b27c5238/Demo.gif)
