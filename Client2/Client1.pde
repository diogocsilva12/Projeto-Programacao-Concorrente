///////////////////////////////////////////////////////////////////////////////
// Cliente do Jogo Duelo
// Autores: Diogo Silva, João Barbosa, Pedro Oliveira
//
// Este cliente implementa a interface gráfica e lógica de apresentação para o 
// jogo Duelo, utilizando Processing como framework gráfico e comunicando
// com um servidor Erlang através de sockets TCP.
///////////////////////////////////////////////////////////////////////////////

import java.net.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.locks.*;

// Server connection settings
String SERVER_IP = "127.0.0.1";  // Change to "localhost" or your server IP
int SERVER_PORT = 5555;          // Server port

///////////////////////////////////////////////////////////////////////////////
// Definição de Estados do Jogo
// O cliente utiliza uma máquina de estados para controlar diferentes telas
// e comportamentos durante a execução.
///////////////////////////////////////////////////////////////////////////////
enum GameState {
  LOGIN,        // Ecrã de autenticação
  REGISTER,     // Ecrã de registo de novos utilizadores
  MAIN_MENU,    // Menu principal com opções de jogo
  LEADERBOARD,  // Visualização dedicada à tabela de classificação
  WAITING,      // Sala de espera durante o matchmaking
  INGAME        // Estado ativo de jogo
}

///////////////////////////////////////////////////////////////////////////////
// Monitores para Concorrência
// Estas classes implementam mecanismos de sincronização entre threads
///////////////////////////////////////////////////////////////////////////////

/**
 * Monitor para gerir o estado do jogo.
 * Utiliza ReentrantLock e variáveis de condição para coordenar threads
 * que precisam aguardar o início ou fim de uma partida.
 */
class GameStateMonitor {
  private final Lock lock = new ReentrantLock();
  private final Condition gameStarted = lock.newCondition();
  private final Condition gameEnded = lock.newCondition();
  private boolean isRunning = false;
  
  /**
   * Sinaliza que o jogo começou e notifica todas as threads em espera.
   */
  public void startGame() {
    lock.lock();
    try {
      isRunning = true;
      gameStarted.signalAll();
    } finally {
      lock.unlock();
    }
  }
  
  /**
   * Sinaliza que o jogo terminou e notifica todas as threads em espera.
   */
  public void endGame() {
    lock.lock();
    try {
      isRunning = false;
      gameEnded.signalAll();
    } finally {
      lock.unlock();
    }
  }
  
  /**
   * Verifica se o jogo está em execução.
   * @return Verdadeiro se o jogo estiver em execução, falso caso contrário.
   */
  public boolean isGameRunning() {
    lock.lock();
    try {
      return isRunning;
    } finally {
      lock.unlock();
    }
  }
  
  /**
   * Faz a thread atual aguardar até que o jogo comece.
   * @throws InterruptedException Se a thread for interrompida enquanto aguarda.
   */
  public void waitForGameStart() throws InterruptedException {
    lock.lock();
    try {
      while (!isRunning) {
        gameStarted.await();
      }
    } finally {
      lock.unlock();
    }
  }
  
  /**
   * Faz a thread atual aguardar até que o jogo termine.
   * @throws InterruptedException Se a thread for interrompida enquanto aguarda.
   */
  public void waitForGameEnd() throws InterruptedException {
    lock.lock();
    try {
      while (isRunning) {
        gameEnded.await();
      }
    } finally {
      lock.unlock();
    }
  }
}

/**
 * Monitor para gerir conexões com o servidor.
 * Utiliza o mecanismo nativo de monitores Java para coordenar threads
 * que precisam aguardar respostas do servidor.
 */
class ConnectionMonitor {
  private final Object lock = new Object();
  private boolean connected = false;
  private String serverResponse = null;
  
  /**
   * Define o estado de conexão e notifica threads em espera.
   * @param status Novo estado de conexão.
   */
  public void setConnected(boolean status) {
    synchronized(lock) {
      connected = status;
      lock.notifyAll();
    }
  }
  
  /**
   * Verifica se o cliente está conectado ao servidor.
   * @return Verdadeiro se conectado, falso caso contrário.
   */
  public boolean isConnected() {
    synchronized(lock) {
      return connected;
    }
  }
  
  /**
   * Define uma resposta recebida do servidor e notifica threads em espera.
   * @param response Resposta recebida do servidor.
   */
  public void setResponse(String response) {
    synchronized(lock) {
      serverResponse = response;
      lock.notifyAll();
    }
  }
  
  /**
   * Obtém e limpa a resposta atual do servidor.
   * @return A resposta do servidor ou null se não houver resposta.
   */
  public String getResponse() {
    synchronized(lock) {
      String response = serverResponse;
      serverResponse = null;
      return response;
    }
  }
  
  /**
   * Faz a thread atual aguardar até que o cliente se conecte ao servidor.
   * @throws InterruptedException Se a thread for interrompida enquanto aguarda.
   */
  public void waitForConnection() throws InterruptedException {
    synchronized(lock) {
      while (!connected) {
        lock.wait();
      }
    }
  }
  
  /**
   * Faz a thread atual aguardar até que uma resposta do servidor seja recebida
   * ou até que o timeout especificado expire.
   * @param timeout Tempo máximo de espera em milissegundos.
   * @throws InterruptedException Se a thread for interrompida enquanto aguarda.
   */
  public void waitForResponse(long timeout) throws InterruptedException {
    synchronized(lock) {
      if (serverResponse == null) {
        lock.wait(timeout);
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
// Variáveis Globais
///////////////////////////////////////////////////////////////////////////////

// Estado atual do jogo
GameState state = GameState.LOGIN;

// Conexão com o servidor
Socket socket;
BufferedReader input;
PrintWriter output;

// Monitores para sincronização
GameStateMonitor gameStateMon = new GameStateMonitor();
ConnectionMonitor connectionMon = new ConnectionMonitor();

// Coleções thread-safe para objetos de jogo
private final List<Bullet> bullets = Collections.synchronizedList(new ArrayList<Bullet>());
private final List<Modifier> modifiers = Collections.synchronizedList(new ArrayList<Modifier>());

// Objetos de bloqueio para proteção de recursos compartilhados
private final Object bulletsLock = new Object();
private final Object modifiersLock = new Object();

// Objetos dos jogadores com acesso sincronizado
Player p1 = new Player(400, 300);  // Jogador local
Player p2 = new Player(200, 100);  // Oponente
private final Object p1Lock = new Object();
private final Object p2Lock = new Object();
float otherX = 200, otherY = 100;  // Posição do oponente

// Informações do utilizador com acesso sincronizado
private final Object userInfoLock = new Object();
String clientPID = "UNASSIGNED";   // ID único do cliente
String username = "";              // Nome de utilizador
String password = "";              // Senha (armazenada apenas temporariamente)
int playerLevel = 1;               // Nível atual do jogador
int consecutiveWins = 0;           // Sequência de vitórias
int consecutiveLosses = 0;         // Sequência de derrotas

// Variáveis de interface
boolean loginError = false;
boolean registerError = false;
String errorMessage = "";
private final Object leaderboardLock = new Object();
String[] leaderboard = new String[10];  // Top 10 jogadores

// Campos de entrada
String inputUsername = "";
String inputPassword = "";
boolean focusUsername = true;

// Variáveis de jogo
int startTime = 0;                  // Tempo de início da partida
int gameDuration = 120000;          // Duração da partida: 2 minutos

// Coordenadas dos botões
int buttonX, buttonY, buttonWidth, buttonHeight;
int secondButtonX, secondButtonY;

// Coordenadas de spawn do jogador
float spawnX = 400;                 // Coordenadas padrão de spawn
float spawnY = 300;

// Variáveis de cooldown para disparos
int lastShotTime = 0;               // Último momento em que foi disparado
int shotCooldown = 250;             // Cooldown base: 250ms entre disparos

// Controle de threads
private Thread serverListener;      // Thread para escutar mensagens do servidor
private boolean running = true;     // Flag para controlar execução de threads

///////////////////////////////////////////////////////////////////////////////
// Inicialização e Ciclo Principal
///////////////////////////////////////////////////////////////////////////////

/**
 * Configura o ambiente inicial do cliente.
 * Inicializa dimensões, conexão com servidor e thread de escuta.
 */
void setup() {
  size(800, 600);
  frameRate(60);
  
  // Inicializa dimensões dos botões
  buttonWidth = 200;
  buttonHeight = 50;
  buttonX = width/2 - buttonWidth/2;
  buttonY = height/2 + 50;
  secondButtonX = buttonX;
  secondButtonY = buttonY + buttonHeight + 20;
  
  // Estabelece conexão com o servidor
  try {
    socket = new Socket(SERVER_IP, SERVER_PORT);
    input = new BufferedReader(new InputStreamReader(socket.getInputStream()));
    output = new PrintWriter(socket.getOutputStream(), true);
    connectionMon.setConnected(true);
    
    // Inicia thread para escutar respostas do servidor
    serverListener = new Thread(new Runnable() {
      public void run() {
        while (running) {
          try {
            readServerMessages();
            Thread.sleep(10);  // Pequena pausa para evitar uso excessivo de CPU
          } catch (Exception e) {
            println("Server listener error: " + e.getMessage());
            e.printStackTrace();
            connectionMon.setConnected(false);
            
            // Tenta reconectar após falha
            try {
              Thread.sleep(5000);  // Aguarda 5 segundos antes de tentar novamente
              socket = new Socket(SERVER_IP, SERVER_PORT);
              input = new BufferedReader(new InputStreamReader(socket.getInputStream()));
              output = new PrintWriter(socket.getOutputStream(), true);
              connectionMon.setConnected(true);
            } catch (Exception reconnectError) {
              println("Reconnection failed: " + reconnectError.getMessage());
            }
          }
        }
      }
    });
    serverListener.start();
  } catch (Exception e) {
    e.printStackTrace();
    errorMessage = "Server connection failed. Please try again later.";
    connectionMon.setConnected(false);
  }
}

/**
 * Função principal de renderização, chamada a cada frame.
 * Processa o estado atual e renderiza a tela correspondente.
 */
void draw() {
  background(150);

  // Renderiza o estado atual
  switch (state) {
    case LOGIN:
      handleLoginState();
      break;
    case REGISTER:
      handleRegisterState();
      break;
    case MAIN_MENU:
      handleMainMenuState();
      break;
    case LEADERBOARD:
      handleLeaderboardState();
      break;
    case WAITING:
      handleWaitingState();
      break;
    case INGAME:
      handleInGameState();
      break;
  }
  
  // Exibe status de conexão quando desconectado
  if (!connectionMon.isConnected()) {
    fill(255, 0, 0);
    textAlign(CENTER, TOP);
    textSize(14);
    text("Connection lost. Trying to reconnect...", width/2, 5);
  }
}

///////////////////////////////////////////////////////////////////////////////
// Gestão de Estados da Interface
///////////////////////////////////////////////////////////////////////////////

/**
 * Renderiza e gerencia o estado de visualização da tabela de classificação.
 */
void handleLeaderboardState() {
  // Título
  textAlign(CENTER, CENTER);
  textSize(36);
  fill(0);
  text("Duelo - Leaderboard", width/2, 80);
  
  // Desenha entradas da tabela de classificação
  textSize(24);
  textAlign(CENTER, TOP);
  text("Top Players", width/2, 130);
  
  textSize(18);
  textAlign(LEFT, CENTER);
  int yPos = 180;
  boolean hasEntries = false;
  
  synchronized(leaderboardLock) {
    for (int i = 0; i < leaderboard.length; i++) {
      if (leaderboard[i] != null) {
        hasEntries = true;
        fill(i < 3 ? color(255, 215, 0) : color(0)); // Cor dourada para o top 3
        text(leaderboard[i], width/2 - 200, yPos);
        yPos += 30;
      }
    }
  }
  
  if (!hasEntries) {
    fill(100);
    textAlign(CENTER, CENTER);
    text("No leaderboard data available", width/2, height/2);
  }
  
  // Botão de voltar
  fill(150, 150, 150);
  rect(buttonX, height - 100, buttonWidth, buttonHeight);
  fill(255);
  textAlign(CENTER, CENTER);
  text("Back to Menu", buttonX + buttonWidth/2, height - 100 + buttonHeight/2);
}

/**
 * Renderiza e gerencia o estado de login.
 */
void handleLoginState() {
  // Título
  textAlign(CENTER, CENTER);
  textSize(36);
  fill(0);
  text("Duelo - Login", width/2, 100);
  
  // Campo de nome de utilizador
  textSize(18);
  text("Username:", width/2, height/2 - 80);
  
  fill(255);
  rect(buttonX, height/2 - 60, buttonWidth, 40);
  
  fill(0);
  textAlign(LEFT, CENTER);
  text(inputUsername, buttonX + 10, height/2 - 40);
  
  // Cursor para campo de utilizador
  if (focusUsername && frameCount % 60 < 30) {
    text("|", buttonX + 10 + textWidth(inputUsername), height/2 - 40);
  }
  
  // Campo de senha
  textAlign(CENTER, CENTER);
  text("Password:", width/2, height/2 - 10);
  
  fill(255);
  rect(buttonX, height/2 + 10, buttonWidth, 40);
  
  fill(0);
  textAlign(LEFT, CENTER);
  // Mostra asteriscos para senha
  String displayPass = "";
  for (int i = 0; i < inputPassword.length(); i++) {
    displayPass += "*";
  }
  text(displayPass, buttonX + 10, height/2 + 30);
  
  // Cursor para campo de senha
  if (!focusUsername && frameCount % 60 < 30) {
    text("|", buttonX + 10 + textWidth(displayPass), height/2 + 30);
  }
  
  // Botão de login
  fill(100, 150, 200);
  rect(buttonX, buttonY, buttonWidth, buttonHeight);
  
  fill(255);
  textAlign(CENTER, CENTER);
  text("Login", buttonX + buttonWidth/2, buttonY + buttonHeight/2);
  
  // Botão de registo
  fill(100, 200, 150);
  rect(secondButtonX, secondButtonY, buttonWidth, buttonHeight);
  
  fill(255);
  textAlign(CENTER, CENTER);
  text("Register", secondButtonX + buttonWidth/2, secondButtonY + buttonHeight/2);
  
  // Mostra erro, se houver
  if (loginError) {
    fill(255, 0, 0);
    textSize(16);
    text(errorMessage, width/2, height/2 + 150);
  }
}

/**
 * Renderiza e gerencia o estado de registo.
 */
void handleRegisterState() {
  // Título
  textAlign(CENTER, CENTER);
  textSize(36);
  fill(0);
  text("Duelo - Register", width/2, 100);
  
  // Campo de nome de utilizador
  textSize(18);
  text("Choose a Username:", width/2, height/2 - 80);
  
  fill(255);
  rect(buttonX, height/2 - 60, buttonWidth, 40);
  
  fill(0);
  textAlign(LEFT, CENTER);
  text(inputUsername, buttonX + 10, height/2 - 40);
  
  // Cursor para campo de utilizador
  if (focusUsername && frameCount % 60 < 30) {
    text("|", buttonX + 10 + textWidth(inputUsername), height/2 - 40);
  }
  
  // Campo de senha
  textAlign(CENTER, CENTER);
  text("Choose a Password:", width/2, height/2 - 10);
  
  fill(255);
  rect(buttonX, height/2 + 10, buttonWidth, 40);
  
  fill(0);
  textAlign(LEFT, CENTER);
  // Mostra asteriscos para senha
  String displayPass = "";
  for (int i = 0; i < inputPassword.length(); i++) {
    displayPass += "*";
  }
  text(displayPass, buttonX + 10, height/2 + 30);
  
  // Cursor para campo de senha
  if (!focusUsername && frameCount % 60 < 30) {
    text("|", buttonX + 10 + textWidth(displayPass), height/2 + 30);
  }
  
  // Botão de registo
  fill(100, 200, 150);
  rect(buttonX, buttonY, buttonWidth, buttonHeight);
  
  fill(255);
  textAlign(CENTER, CENTER);
  text("Register", buttonX + buttonWidth/2, buttonY + buttonHeight/2);
  
  // Botão de voltar para login
  fill(150, 150, 150);
  rect(secondButtonX, secondButtonY, buttonWidth, buttonHeight);
  
  fill(255);
  textAlign(CENTER, CENTER);
  text("Back to Login", secondButtonX + buttonWidth/2, secondButtonY + buttonHeight/2);
  
  // Mostra erro, se houver
  if (registerError) {
    fill(255, 0, 0);
    textSize(16);
    text(errorMessage, width/2, height/2 + 150);
  }
}

/**
 * Renderiza e gerencia o estado de menu principal.
 */
void handleMainMenuState() {
  // Título
  textAlign(CENTER, CENTER);
  textSize(36);
  fill(0);
  text("Duelo - Main Menu", width/2, 100);
  
  // Exibe informações do jogador
  textSize(20);
  synchronized(userInfoLock) {
    text("Welcome, " + username + "!", width/2, height/4);
    text("Level: " + playerLevel, width/2, height/4 + 30);
    
    // Mostra sequência de vitórias/derrotas
    String streakDisplay = consecutiveWins > 0 ? 
                          "Win Streak: " + consecutiveWins : 
                          (consecutiveLosses > 0 ? "Loss Streak: " + consecutiveLosses : "No Streak");
    text(streakDisplay, width/2, height/4 + 60);
  }
  
  // Botão jogar
  fill(100, 150, 200);
  rect(buttonX, height/2 - 30, buttonWidth, buttonHeight);
  fill(255);
  textAlign(CENTER, CENTER);
  text("Play Game", buttonX + buttonWidth/2, height/2 - 30 + buttonHeight/2);
  
  // Botão leaderboard
  fill(100, 200, 100);
  rect(buttonX, height/2 + 40, buttonWidth, buttonHeight);
  fill(255);
  text("View Leaderboard", buttonX + buttonWidth/2, height/2 + 40 + buttonHeight/2);
  
  // Botão sair
  fill(200, 100, 100);
  rect(buttonX, height/2 + 110, buttonWidth, buttonHeight);
  fill(255);
  text("Exit Game", buttonX + buttonWidth/2, height/2 + 110 + buttonHeight/2);
  
  // Botão logout
  fill(150, 150, 150);
  rect(buttonX, height/2 + 180, buttonWidth, buttonHeight);
  fill(255);
  textAlign(CENTER, CENTER);
  text("Logout", buttonX + buttonWidth/2, height/2 + 180 + buttonHeight/2);
}

/**
 * Renderiza e gerencia o estado de espera por partida.
 */
void handleWaitingState() {
  textAlign(CENTER, CENTER);
  textSize(24);
  fill(0);
  synchronized(userInfoLock) {
    text("Welcome, " + username + "!", width/2, height/3 - 50);
    text("Level: " + playerLevel, width/2, height/3);
  }
  text("Waiting for a match...", width/2, height/2);
  
  // Exibe um spinner ou animação
  float angle = frameCount * 0.1;
  float radius = 20;
  float x = width/2 + cos(angle) * radius;
  float y = height/2 + 50 + sin(angle) * radius;
  fill(100, 150, 200);
  ellipse(x, y, 10, 10);
  
  // Botão para cancelar matchmaking
  fill(200, 100, 100);
  rect(buttonX, height - 100, buttonWidth, buttonHeight);
  fill(255);
  textAlign(CENTER, CENTER);
  text("Cancel Matchmaking", buttonX + buttonWidth/2, height - 100 + buttonHeight/2);
}

/**
 * Renderiza e gerencia o estado de jogo ativo.
 * Atualiza e renderiza jogadores, projéteis e modificadores.
 */
void handleInGameState() {
  displayGameInfo();
  updateAndRenderPlayers();
  updateAndRenderBullets();
  updateAndRenderModifiers();

  // Envia posição do jogador se conectado e jogo em execução
  if (!clientPID.equals("UNASSIGNED") && gameStateMon.isGameRunning() && connectionMon.isConnected()) {
    synchronized(p1Lock) {
      output.println(clientPID + ";" + p1.getX() + ";" + p1.getY());
    }
  }
  
  // Adiciona botão de desistência
  if (gameStateMon.isGameRunning()) {
    // Posiciona o botão de desistência no canto superior direito
    fill(200, 100, 100);
    rect(width - 120, 10, 100, 30);
    fill(255);
    textAlign(CENTER, CENTER);
    textSize(14);
    text("Forfeit", width - 70, 25);
    textAlign(LEFT, TOP); // Restaura alinhamento do texto
  }
}

/**
 * Exibe informações do jogo como pontuações, tempo e status de modificadores.
 */
void displayGameInfo() {
  // Temporizador do jogo
  fill(0);
  textSize(16);
  textAlign(LEFT, TOP);
  
  if (gameStateMon.isGameRunning()) {
    int elapsed = millis() - startTime;
    int remaining = max(0, gameDuration - elapsed);
    
    // Informações básicas do jogo (lado esquerdo)
    synchronized(p1Lock) {
      text("Your Score: " + p1.getScore(), 10, 10);
    }
    synchronized(p2Lock) {
      text("Opponent Score: " + p2.getScore(), 10, 35);
    }
    text("Time Left: " + (remaining / 1000) + "s", 10, 60);
    
    // Exibe informações de cooldown
    float cooldownPercentage;
    synchronized(p1Lock) {
      cooldownPercentage = min(1.0, (millis() - lastShotTime) / (shotCooldown * p1.getCooldownModifier()));
    }
    
    // Mostra status de cooldown
    fill(lerp(255, 0, cooldownPercentage), lerp(0, 255, cooldownPercentage), 0);
    text("Fire Ready: " + int(cooldownPercentage * 100) + "%", 10, 85);
    
    // Mostra status dos modificadores no lado direito com melhor espaçamento
    textAlign(RIGHT, TOP);
    int yOffset = 10;
    boolean hasModifiers = false;
    
    synchronized(p1Lock) {
      if (p1.getProjectileSpeedModifier() != 1.0) {
        hasModifiers = true;
        if (p1.getProjectileSpeedModifier() > 1.0) {
          fill(0, 255, 0);
          text("Projectile Speed: +" + int((p1.getProjectileSpeedModifier() - 1.0) * 100) + "%", width - 130, yOffset);
        } else {
          fill(255, 165, 0);
          text("Projectile Speed: " + int((p1.getProjectileSpeedModifier() - 1.0) * 100) + "%", width - 130, yOffset);
        }
        yOffset += 25;
      }
      
      if (p1.getCooldownModifier() != 1.0) {
        hasModifiers = true;
        if (p1.getCooldownModifier() < 1.0) {
          fill(0, 0, 255);
          text("Fire Rate: +" + int((1.0 - p1.getCooldownModifier()) * 100) + "%", width - 130, yOffset);
        } else {
          fill(255, 0, 0);
          text("Fire Rate: -" + int((p1.getCooldownModifier() - 1.0) * 100) + "%", width - 130, yOffset);
        }
      }
    }
    
    // Se o jogador tiver modificadores ativos, adiciona um cabeçalho
    if (hasModifiers) {
      fill(255);
      text("ACTIVE MODIFIERS", width - 130, yOffset - 50);
    }
    
    // Reset do alinhamento do texto
    textAlign(LEFT, TOP);
  } else {
    text("Waiting for game to start...", 10, 70);
  }
  
  fill(255);
}

///////////////////////////////////////////////////////////////////////////////
// Comunicação com o Servidor e Processamento de Mensagens
///////////////////////////////////////////////////////////////////////////////

/**
 * Lê e processa mensagens recebidas do servidor.
 * Esta função é chamada continuamente pela thread serverListener.
 */
void readServerMessages() {
  try {
    while (input.ready()) {
      String data = input.readLine();
      if (data == null) break;
      
      // Saída de debug
      println("Received from server: " + data);

      String[] parts = data.split(";");
      
      // Processa os diferentes tipos de mensagens do servidor
      switch (parts[0]) {
        case "START":
          // Inicia uma nova partida
          println("DEBUG: Received START command");
          startTime = millis();
          gameStateMon.startGame();
          state = GameState.INGAME;
          
          // reinicia pontuações
          synchronized(p1Lock) {
            p1.setScore(0);
          }
          synchronized(p2Lock) {
            p2.setScore(0);
          }
          
          println("Game started!");
          break;

        case "MATCH_FOUND":
          // Partida encontrada, prepara para início
          if (parts.length == 3) {
            state = GameState.WAITING;
            // Armazena coordenadas de spawn para identificação do jogador
            spawnX = Float.parseFloat(parts[1]);
            spawnY = Float.parseFloat(parts[2]);
            // reinicia posição do jogador para as coordenadas de spawn
            synchronized(p1Lock) {
              p1.resetPlayer(spawnX, spawnY);
            }
          }
          break;
          
        case "END":
          // Fim da partida
          gameStateMon.endGame();
          println("Game ended by server.");
          
          // reinicia estado de movimento do jogador
          synchronized(p1Lock) {
            p1.resetMovement();
          }
          
          // Atualiza estatísticas do jogador com base no resultado
          synchronized(userInfoLock) {
            if (parts.length >= 4) {
              playerLevel = Integer.parseInt(parts[1]);
              // Analisa sequências de vitórias e derrotas corretamente
              int wins = Integer.parseInt(parts[2]);
              int losses = Integer.parseInt(parts[3]);
              consecutiveWins = wins;
              consecutiveLosses = Math.abs(losses); // Garante que derrotas sejam positivas para exibição
            }
          }
          
          // Retorna ao menu principal ao invés de espera
          state = GameState.MAIN_MENU;
          
          // Solicita atualização da tabela de classificação
          requestLeaderboard();
          break;
          
        case "LEADERBOARD":
          // Atualiza a tabela de classificação
          updateLeaderboard(parts);
          break;
          
        case "BULLET":
          // Novo projétil criado por um jogador
          if (parts.length == 6) {
            float bx = float(parts[1]);
            float by = float(parts[2]);
            float tx = float(parts[3]);
            float ty = float(parts[4]);
            String shooterPID = parts[5];
            
            // Determina o objeto de jogador do atirador
            Player shooter;
            synchronized(p1Lock) {
              synchronized(p2Lock) {
                shooter = shooterPID.equals(clientPID) ? p1 : p2;
              }
            }
            
            // Adiciona o projétil à lista thread-safe
            synchronized(bulletsLock) {
              bullets.add(new Bullet(bx, by, tx, ty, shooter));
            }
          }
          break;

        case "HIT":
          // Colisão de jogador com projétil
          if (parts.length == 4) {
            float hitX = float(parts[1]);
            float hitY = float(parts[2]);
            String shooterPID = parts[3];

            // Remove quaisquer projéteis próximos ao ponto de colisão
            synchronized(bulletsLock) {
              Iterator<Bullet> iter = bullets.iterator();
              while (iter.hasNext()) {
                Bullet b = iter.next();
                if (dist(b.getX(), b.getY(), hitX, hitY) < 10) {
                  iter.remove();
                }
              }
            }
          }
          break;
          
        case "MODIFIER":
          // Novo modificador gerado
          if (parts.length == 4) {
            float mx = float(parts[1]);
            float my = float(parts[2]);
            int type = Integer.parseInt(parts[3]);
            
            synchronized(modifiersLock) {
              modifiers.add(new Modifier(mx, my, type));
            }
          }
          break;
          
        case "MODIFIER_PICKUP":
          // Coleta de modificador por um jogador
          if (parts.length == 4) {
            float mx = float(parts[1]);
            float my = float(parts[2]);
            String playerID = parts[3];
            
            // Remove o modificador da lista
            synchronized(modifiersLock) {
              Iterator<Modifier> modIter = modifiers.iterator();
              while (modIter.hasNext()) {
                Modifier m = modIter.next();
                if (dist(m.getX(), m.getY(), mx, my) < 10) {
                  modIter.remove();
                  
                  // Aplica efeito ao jogador correto
                  if (playerID.equals(clientPID)) {
                    synchronized(p1Lock) {
                      p1.applyModifier(m.getType());
                    }
                  } else {
                    synchronized(p2Lock) {
                      p2.applyModifier(m.getType());
                    }
                  }
                }
              }
            }
          }
          break;

        case "RESET_POSITIONS":
          // reinicia posições dos jogadores
          if (state == GameState.INGAME) {
            synchronized(p1Lock) {
              p1.resetPlayer(spawnX, spawnY);
              p1.resetMovement();
            }
          }
          break;
          
        case "SCORES":
          // Atualização de pontuações
          if (parts.length == 5) {  // Formato: SCORES;player1;player1Score;player2;player2Score
            // O servidor usa "player1"/"player2" genéricos em vez de PIDs
            int player1Score = Integer.parseInt(parts[2]);
            int player2Score = Integer.parseInt(parts[4]);
            
            // Informação de debug
            println("Score update - player1: " + player1Score + ", player2: " + player2Score);
            println("My spawn position: " + spawnX + "," + spawnY);
            
            // Usa coordenadas de spawn para determinar qual jogador somos
            if (isPlayerOne()) {
              // Somos o jogador 1 - define pontuações diretamente
              synchronized(p1Lock) {
                p1.setScore(player1Score);
              }
              synchronized(p2Lock) {
                p2.setScore(player2Score);
              }
            } else {
              // Somos o jogador 2 - pontuações são invertidas
              synchronized(p1Lock) {
                p1.setScore(player2Score);
              }
              synchronized(p2Lock) {
                p2.setScore(player1Score);
              }
            }
          }
          break;

        case "FORFEIT_CONFIRM":
          // Confirmação de desistência
          gameStateMon.endGame();
          println("Game forfeited.");
          
          // reinicia estado de movimento do jogador
          synchronized(p1Lock) {
            p1.resetMovement();
          }
          
          // Atualiza estatísticas do jogador com base na desistência
          synchronized(userInfoLock) {
            if (parts.length >= 4) {
              playerLevel = Integer.parseInt(parts[1]);
              consecutiveWins = Integer.parseInt(parts[2]);
              consecutiveLosses = Math.abs(Integer.parseInt(parts[3]));
            }
          }
          
          // Retorna ao menu principal
          state = GameState.MAIN_MENU;
          
          // Solicita atualização da tabela de classificação
          requestLeaderboard();
          break;
          
        case "LOGIN_SUCCESS":
          // Login bem-sucedido
          if (parts.length >= 5) {
            synchronized(userInfoLock) {
              username = inputUsername;
              playerLevel = Integer.parseInt(parts[1]);
              consecutiveWins = Integer.parseInt(parts[2]);
              consecutiveLosses = Integer.parseInt(parts[3]);
              clientPID = parts[4];
            }
            
            // reinicia erros
            loginError = false;
            errorMessage = "";
            
            // Obtém tabela de classificação
            requestLeaderboard();
            
            // Vai para o menu principal
            state = GameState.MAIN_MENU;
            println("Login successful for: " + username);
            
            // Sinaliza resposta de login bem-sucedido
            connectionMon.setResponse("LOGIN_SUCCESS");
          }
          break;
          
        case "LOGIN_FAILED":
          // Falha no login
          if (parts.length >= 2) {
            loginError = true;
            errorMessage = parts[1];
            println("Login failed: " + errorMessage);
            
            // Sinaliza resposta de login falho
            connectionMon.setResponse("LOGIN_FAILED");
          }
          break;
          
        case "REGISTER_SUCCESS":
          // registo bem-sucedido
          registerError = false;
          errorMessage = "";
          resetInputFields(); // Adiciona esta linha para garantir que os campos sejam reiniciados
          state = GameState.LOGIN;
          
          // Sinaliza resposta de registo bem-sucedido
          connectionMon.setResponse("REGISTER_SUCCESS");
          break;
          
        case "REGISTER_FAILED":
          // Falha no registo
          if (parts.length >= 2) {
            registerError = true;
            errorMessage = parts[1];
            
            // Sinaliza resposta de registo falho
            connectionMon.setResponse("REGISTER_FAILED");
          }
          break;
          
        default:
          // Atualização de posição do outro jogador
          if (parts.length == 3 && !parts[0].equals(clientPID)) {
            otherX = float(parts[1]);
            otherY = float(parts[2]);
          }
          break;
      }
    }
  } catch (Exception e) {
    println("Error reading: " + e.getMessage());
    e.printStackTrace(); // Adiciona stack trace para melhor depuração
  }
}

/**
 * Atualiza a tabela de classificação com dados recebidos do servidor.
 * @param parts Array de strings contendo informações da tabela de classificação.
 */
void updateLeaderboard(String[] parts) {
  synchronized(leaderboardLock) {
    // reinicia tabela de classificação
    for (int i = 0; i < leaderboard.length; i++) {
      leaderboard[i] = null;
    }
    
    // Formato atualizado: LEADERBOARD;username1;level1;streak1;wins1;losses1;username2;...
    for (int i = 1; i < parts.length; i += 5) {
      int index = (i - 1) / 5;
      if (index < leaderboard.length) {
        String user = parts[i];
        int level = Integer.parseInt(parts[i+1]);
        int streak = Integer.parseInt(parts[i+2]);
        int wins = Integer.parseInt(parts[i+3]);
        int losses = Integer.parseInt(parts[i+4]);
        
        // Formata a entrada da tabela de classificação com informações de vitórias/derrotas
        String streakString = streak > 0 ? "+" + streak : "" + streak;
        leaderboard[index] = (index + 1) + ". " + user + " (Level " + level + ", " + streakString + ", W-L: " + wins + "-" + losses + ")";
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
// Atualização e Renderização de Elementos do Jogo
///////////////////////////////////////////////////////////////////////////////

/**
 * Atualiza e renderiza os jogadores.
 * Lida com movimentos do jogador local e atualiza a posição do oponente.
 */
void updateAndRenderPlayers() {
  if (gameStateMon.isGameRunning()) {
    synchronized(p1Lock) {
      p1.update();
      
      // Verifica se o jogador colidiu com uma parede
      if (p1.checkAndClearWallCollision()) {
        // Notifica o servidor sobre colisão com parede
        output.println("WALL_COLLISION;" + clientPID);
      }
    }
  }
  
  // Jogador 1 (jogador local)
  synchronized(p1Lock) {
    if (isPlayerOne()) {
      fill(255, 255, 0); // Amarelo para Jogador 1
    } else {
      fill(0, 255, 255); // Ciano para Jogador 2
    }
    p1.display();
  }

  // Jogador 2 (oponente)
  synchronized(p2Lock) {
    p2.setX(otherX);
    p2.setY(otherY);
    if (isPlayerOne()) {
      fill(0, 255, 255); // Se somos Jogador 1, oponente é Jogador 2 (ciano)
    } else {
      fill(255, 255, 0); // Se somos Jogador 2, oponente é Jogador 1 (amarelo)
    }
    p2.display();
  }
}

/**
 * Função auxiliar para determinar se o jogador local é o Jogador 1.
 * @return Verdadeiro se o jogador local for o Jogador 1, falso caso contrário.
 */
boolean isPlayerOne() {
  // O servidor atribui pontos de spawn específicos para cada jogador
  // Jogador 1 aparece em (200,100), Jogador 2 aparece em (600,500)
  return (spawnX == 200 && spawnY == 100);
}

/**
 * Atualiza e renderiza os projéteis.
 * Gerencia movimento e colisões de projéteis.
 */
void updateAndRenderBullets() {
  synchronized(bulletsLock) {
    for (int i = bullets.size() - 1; i >= 0; i--) {
      Bullet b = bullets.get(i);
      b.update();
      
      fill(255); // Projéteis brancos
      b.display();
      
      // Remove projéteis que saem da tela
      if (b.isOffScreen()) {
        bullets.remove(i);
        continue;
      }
      
      // Verifica colisões de projéteis com jogadores
      if (gameStateMon.isGameRunning()) {
        Player shooter = b.getShooter();
        boolean bulletFromLocalPlayer;
        
        synchronized(p1Lock) {
          bulletFromLocalPlayer = (shooter == p1);
        }
        
        // Só detecta acertos para projéteis do jogador local ou oponente atingindo jogador local
        if (bulletFromLocalPlayer) {
          synchronized(p2Lock) {
            if (b.checkCollision(p2)) {
              // Projétil do jogador local atingiu oponente - apenas notifica servidor
              output.println("HIT;" + b.getX() + ";" + b.getY() + ";" + clientPID);
              bullets.remove(i);
            }
          }
        } else {
          synchronized(p1Lock) {
            if (b.checkCollision(p1)) {
              // Projétil do oponente atingiu jogador local - apenas remove projétil
              bullets.remove(i);
            }
          }
        }
      }
    }
  }
}

/**
 * Atualiza e renderiza os modificadores.
 * Gerencia colisões entre jogador e modificadores.
 */
void updateAndRenderModifiers() {
  synchronized(modifiersLock) {
    for (int i = modifiers.size() - 1; i >= 0; i--) {
      Modifier m = modifiers.get(i);
      
      // Exibe o modificador
      m.display();
      
      // Verifica colisão com jogador
      if (gameStateMon.isGameRunning()) {
        boolean collision;
        synchronized(p1Lock) {
          collision = m.checkCollision(p1);
          if (collision) {
            // Aplica efeito do modificador
            p1.applyModifier(m.getType());
          }
        }
        
        if (collision) {
          // Notifica servidor sobre coleta de modificador
          output.println("MODIFIER_PICKUP;" + m.getX() + ";" + m.getY() + ";" + clientPID);
          
          // Remove modificador
          modifiers.remove(i);
        }
      }
    }
  }
}

/**
 * Solicita atualização da tabela de classificação ao servidor.
 */
void requestLeaderboard() {
  if (output != null && connectionMon.isConnected()) {
    output.println("LEADERBOARD");
  }
}

///////////////////////////////////////////////////////////////////////////////
// Funções de Autenticação
///////////////////////////////////////////////////////////////////////////////

/**
 * Processa tentativa de login.
 * Valida informações básicas e envia solicitação ao servidor.
 */
void login() {
  if (inputUsername.length() < 3 || inputPassword.length() < 3) {
    loginError = true;
    errorMessage = "Username and password must be at least 3 characters";
    return;
  }
  
  // reinicia erros anteriores
  loginError = false;
  errorMessage = "";
  
  // Inicia uma thread para tratar login e evitar bloqueio da UI
  new Thread(new Runnable() {
    public void run() {
      try {
        // Envia solicitação de login ao servidor
        output.println("LOGIN;" + inputUsername + ";" + inputPassword);
        
        // Aguarda resposta com timeout
        connectionMon.waitForResponse(5000); // 5 segundos de timeout
        
        // Resposta processada assincronamente em readServerMessages
        // Os casos LOGIN_SUCCESS ou LOGIN_FAILED atualizarão a UI
      } catch (Exception e) {
        loginError = true;
        errorMessage = "Error: " + e.getMessage();
        e.printStackTrace();
      }
    }
  }).start();
}

/**
 * Processa tentativa de registo.
 * Valida informações básicas e envia solicitação ao servidor.
 */
void register() {
  if (inputUsername.length() < 3 || inputPassword.length() < 3) {
    registerError = true;
    errorMessage = "Username and password must be at least 3 characters";
    return;
  }
  
  // reinicia erros anteriores
  registerError = false;
  errorMessage = "";
  
  // Armazena temporariamente o nome de usuário e senha
  final String tempUsername = inputUsername;
  final String tempPassword = inputPassword;
  
  // Inicia uma thread para tratar registo e evitar bloqueio da UI
  new Thread(new Runnable() {
    public void run() {
      try {
        // Envia solicitação de registo ao servidor
        output.println("REGISTER;" + tempUsername + ";" + tempPassword);
        
        // Aguarda resposta com timeout
        connectionMon.waitForResponse(5000); // 5 segundos de timeout
        
        // Após o registo bem-sucedido, reinicia os campos
        if (connectionMon.getResponse() != null && 
            connectionMon.getResponse().equals("REGISTER_SUCCESS")) {
          resetInputFields();
        }
        
        // Resposta processada assincronamente em readServerMessages
        // Os casos REGISTER_SUCCESS ou REGISTER_FAILED atualizarão a UI
      } catch (Exception e) {
        registerError = true;
        errorMessage = "Error: " + e.getMessage();
        e.printStackTrace();
      }
    }
  }).start();
}

/**
 * reinicia os campos de entrada.
 * Usado ao trocar entre telas de login/registo.
 */
void resetInputFields() {
  inputUsername = "";
  inputPassword = "";
  focusUsername = true;
  loginError = false;
  registerError = false;
  errorMessage = "";
}

///////////////////////////////////////////////////////////////////////////////
// Tratamento de Entrada do Usuário
///////////////////////////////////////////////////////////////////////////////

/**
 * Processa eventos de clique do mouse.
 * Gerencia interações do usuário com botões e elementos da interface.
 */
void mousePressed() {
  switch (state) {
    case LOGIN:
      // Verifica se o campo de usuário foi clicado
      if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
          mouseY >= height/2 - 60 && mouseY <= height/2 - 20) {
        focusUsername = true;
      }
      // Verifica se o campo de senha foi clicado
      else if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
               mouseY >= height/2 + 10 && mouseY <= height/2 + 50) {
        focusUsername = false;
      }
      // Verifica se o botão de login foi clicado
      else if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
               mouseY >= buttonY && mouseY <= buttonY + buttonHeight) {
        login();
      }
      // Verifica se o botão de registo foi clicado
      else if (mouseX >= secondButtonX && mouseX <= secondButtonX + buttonWidth && 
               mouseY >= secondButtonY && mouseY <= secondButtonY + buttonHeight) {
        resetInputFields();
        state = GameState.REGISTER;
      }
      break;
      
    case REGISTER:
      // Verifica se o campo de usuário foi clicado
      if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
          mouseY >= height/2 - 60 && mouseY <= height/2 - 20) {
        focusUsername = true;
      }
      // Verifica se o campo de senha foi clicado
      else if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
               mouseY >= height/2 + 10 && mouseY <= height/2 + 50) {
        focusUsername = false;
      }
      // Verifica se o botão de registo foi clicado
      else if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
               mouseY >= buttonY && mouseY <= buttonY + buttonHeight) {
        register();
      }
      // Verifica se o botão de voltar foi clicado
      else if (mouseX >= secondButtonX && mouseX <= secondButtonX + buttonWidth && 
               mouseY >= secondButtonY && mouseY <= secondButtonY + buttonHeight) {
        resetInputFields();
        state = GameState.LOGIN;
      }
      break;
      
    case MAIN_MENU:
      // Botão jogar
      if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
          mouseY >= height/2 - 30 && mouseY <= height/2 - 30 + buttonHeight) {
        // Inicia matchmaking
        output.println("MATCHMAKE");
        state = GameState.WAITING;
      }
      // Botão leaderboard
      else if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
               mouseY >= height/2 + 40 && mouseY <= height/2 + 40 + buttonHeight) {
        // Solicita tabela de classificação atualizada
        requestLeaderboard();
        // Muda para a visualização dedicada de leaderboard
        state = GameState.LEADERBOARD;
      }
      // Botão sair
      else if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
               mouseY >= height/2 + 110 && mouseY <= height/2 + 110 + buttonHeight) {
        // Encerra threads adequadamente antes de sair
        running = false;
        try {
          if (serverListener != null && serverListener.isAlive()) {
            serverListener.join(1000); // Aguarda até 1 segundo para a thread terminar
          }
        } catch (InterruptedException e) {
          e.printStackTrace();
        }
        exit(); // Fecha a aplicação
      }
      // Botão logout
      else if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
               mouseY >= height/2 + 180 && mouseY <= height/2 + 180 + buttonHeight) {
        // reinicia dados do usuário
        synchronized(userInfoLock) {
          username = "";
          clientPID = "UNASSIGNED";
          playerLevel = 1;
          consecutiveWins = 0;
          consecutiveLosses = 0;
        }
        
        // Notifica servidor sobre logout
        if (output != null && connectionMon.isConnected()) {
          output.println("LOGOUT");
        }
        
        // reinicia campos de entrada e retorna à tela de login
        resetInputFields();
        state = GameState.LOGIN;
      }
      break;
      
    case WAITING:
      // Verifica se o botão de cancelar matchmaking foi clicado
      if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
          mouseY >= height - 100 && mouseY <= height - 100 + buttonHeight) {
        // Envia mensagem de cancelamento de matchmaking ao servidor
        output.println("CANCEL_MATCHMAKING");
        println("Canceling matchmaking...");
        
        // Retorna ao menu principal
        state = GameState.MAIN_MENU;
      }
      break;
      
    case LEADERBOARD:
      if (mouseX >= buttonX && mouseX <= buttonX + buttonWidth && 
          mouseY >= height - 100 && mouseY <= height - 100 + buttonHeight) {
        state = GameState.MAIN_MENU;
      }
      break;
      
    case INGAME:
      if (gameStateMon.isGameRunning()) {
        // Verifica se o botão de desistência foi clicado
        if (mouseX >= width - 120 && mouseX <= width - 20 && 
            mouseY >= 10 && mouseY <= 40) {
          // Envia mensagem de desistência ao servidor
          output.println("FORFEIT;" + clientPID);
          println("Forfeit requested");
        } else {
          // Aplica modificador de cooldown para determinar se podemos disparar
          int currentTime = millis();
          boolean canShoot = false;
          
          synchronized(p1Lock) {
            int adjustedCooldown = int(shotCooldown * p1.getCooldownModifier());
            canShoot = currentTime - lastShotTime >= adjustedCooldown;
          }
          
          if (canShoot) {
            // Cria novo projétil de maneira thread-safe
            float playerX, playerY;
            synchronized(p1Lock) {
              playerX = p1.getX();
              playerY = p1.getY();
              lastShotTime = currentTime;
            }
            
            synchronized(bulletsLock) {
              Bullet b = new Bullet(playerX, playerY, mouseX, mouseY, p1);
              bullets.add(b);
            }
            
            // Notifica servidor
            if (!clientPID.equals("UNASSIGNED")) {
              output.println("BULLET;" + playerX + ";" + playerY + ";" + mouseX + ";" + mouseY + ";" + clientPID);
            }
          }
        }
      }
      break;
  }
}

/**
 * Processa eventos de tecla pressionada.
 * Gerencia entrada de texto e controles do jogo.
 */
void keyPressed() {
  switch(state) {
    case LOGIN:
    case REGISTER:
      if (key == TAB) {
        // Alterna entre campos de usuário e senha
        focusUsername = !focusUsername;
      } else if (key == ENTER) {
        // Envia formulário quando Enter é pressionado
        if (state == GameState.LOGIN) {
          login();
        } else {
          register();
        }
      } else if (key == BACKSPACE) {
        // Trata backspace para apagar o texto
        if (focusUsername && inputUsername.length() > 0) {
          inputUsername = inputUsername.substring(0, inputUsername.length() - 1);
        } else if (!focusUsername && inputPassword.length() > 0) {
          inputPassword = inputPassword.substring(0, inputPassword.length() - 1);
        }
      } else if (key >= ' ' && key <= '~') { // Verifica caracteres ASCII imprimíveis
        // Adiciona o caractere digitado ao campo apropriado
        if (focusUsername) {
          inputUsername += key;
        } else {
          inputPassword += key;
        }
      }
      break;
    case INGAME:
      if (gameStateMon.isGameRunning()) {
        synchronized(p1Lock) {
          p1.move(key, true);
        }
      }
      break;
  }
}

/**
 * Processa eventos de tecla liberada.
 * Gerencia controles de movimento do jogo.
 */
void keyReleased() {
  if (state == GameState.INGAME && gameStateMon.isGameRunning()) {
    synchronized(p1Lock) {
      p1.move(key, false);
    }
  }
}

/**
 * Chamado quando a aplicação é fechada.
 * Gerencia o encerramento seguro dos recursos de rede e threads.
 */
void dispose() {
  // Encerra threads adequadamente antes de sair
  running = false;
  try {
    if (serverListener != null && serverListener.isAlive()) {
      serverListener.join(1000); // Aguarda até 1 segundo para a thread terminar
    }
  } catch (InterruptedException e) {
    e.printStackTrace();
  }
  
  // Fecha recursos de rede
  try {
    if (output != null) {
      output.close();
    }
    if (input != null) {
      input.close();
    }
    if (socket != null && !socket.isClosed()) {
      socket.close();
    }
  } catch (Exception e) {
    e.printStackTrace();
  }
}