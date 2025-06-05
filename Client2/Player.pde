///////////////////////////////////////////////////////////////////////////////
// Classe Player
// 
// Implementa a lógica de movimento e estado dos jogadores, incluindo física com
// aceleração, inércia e fricção. Gerencia também os modificadores aplicados
// aos jogadores e suas estatísticas de jogo.
///////////////////////////////////////////////////////////////////////////////

public class Player {
  
  private int score;  // Pontuação do jogador
  
  // Constantes de direção
  final int UP = 0;
  final int DOWN = 1;
  final int LEFT = 2;
  final int RIGHT = 3;
  
  // Propriedades físicas do jogador
  private float x, y;                  // Posição
  private int player_size = 50;        // Tamanho do avatar (diâmetro)
  private int direction = DOWN;        // Direção inicial
  private float ax = 0;                // Aceleração X
  private float ay = 0;                // Aceleração Y
  private float vx = 0;                // Velocidade X
  private float vy = 0;                // Velocidade Y
  
  // Constantes de movimento
  private float max_speed = 5;         // Velocidade máxima
  private float accelerationRate = 0.3; // Taxa de aceleração
  private float friction = 0.1;        // Coeficiente de fricção
  
  // Estado de teclas pressionadas
  private boolean upHeld = false;
  private boolean downHeld = false;
  private boolean leftHeld = false;
  private boolean rightHeld = false;
  
  // Efeitos de modificadores
  private float projectileSpeedModifier = 1.0;  // Modificador de velocidade de projéteis (1.0 = normal)
  private float cooldownModifier = 1.0;         // Modificador de cooldown (1.0 = normal)
  private int lastModifierTime = 0;             // Momento da última aplicação de modificador
  private int modifierDuration = 5000;          // Duração do modificador (5 segundos)
  private boolean modifierActive = false;       // Flag indicando se há modificador ativo
  private String activeModifierText = "";       // Texto descritivo do modificador ativo
  private color modifierColor = color(255);     // Cor do modificador ativo
  
  // Flag para detectar colisões com paredes
  private boolean wasWallCollision = false;
    
  /**
   * Construtor do jogador.
   * @param x Posição inicial X
   * @param y Posição inicial Y
   */
  public Player(float x, float y) {
    this.x = x;
    this.y = y;
    this.score = 0;
  }
  
  /**
   * Reinicia a posição e velocidade do jogador.
   * @param resetX Nova posição X
   * @param resetY Nova posição Y
   */
  public void resetPlayer(float resetX, float resetY) {
    this.x = resetX;
    this.y = resetY;
    vx = 0;
    vy = 0;
    ax = 0;
    ay = 0;
  }
  
  /**
   * Atualiza o estado físico do jogador e aplica lógica de movimento.
   * Esta função é chamada a cada frame para simular física e verificar colisões.
   */
  public void update() {
    // Zera aceleração para recalcular com base nas teclas pressionadas
    ax = 0;
    ay = 0;

    // Define aceleração com base nas teclas pressionadas
    if (upHeld) ay = -1;
    if (downHeld) ay = 1;
    if (leftHeld) ax = -1;
    if (rightHeld) ax = 1;

    // Normaliza o vetor de aceleração para evitar movimento mais rápido na diagonal
    float mag = dist(0, 0, ax, ay);
    if (mag > 0) {
      ax = (ax / mag) * accelerationRate;
      ay = (ay / mag) * accelerationRate;
    }

    // Aplica aceleração à velocidade
    vx += ax;
    vy += ay;

    // Limita a velocidade final
    float speed = dist(0, 0, vx, vy);
    if (speed > max_speed) {
      float scale = max_speed / speed;
      vx *= scale;
      vy *= scale;
    }

    // Aplica fricção para desacelerar gradualmente
    vx *= (1 - friction);
    vy *= (1 - friction);

    // Atualiza posição com base na velocidade
    x += vx;
    y += vy;

    // Mantém o jogador dentro da tela e detecta colisões com paredes
    wasWallCollision = false;
    if (x < player_size / 2) {
      x = player_size / 2;
      wasWallCollision = true;
    }
    if (x > width - player_size / 2) {
      x = width - player_size / 2;
      wasWallCollision = true;
    }
    if (y < player_size / 2) {
      y = player_size / 2;
      wasWallCollision = true;
    }
    if (y > height - player_size / 2) {
      y = height - player_size / 2;
      wasWallCollision = true;
    }

    // Determina a direção que o jogador está olhando com base na velocidade
    if (abs(vx) > abs(vy)) {
      if (vx > 0) direction = RIGHT;
      else if (vx < 0) direction = LEFT;
    } else {
      if (vy > 0) direction = DOWN;
      else if (vy < 0) direction = UP;
    }
  
    // Verifica se o efeito do modificador deve expirar
    int currentTime = millis();
    if (modifierActive && currentTime - lastModifierTime > modifierDuration) {
      modifierActive = false;
      projectileSpeedModifier = 1.0;
      cooldownModifier = 1.0;
    }
  }

  /**
   * Processa comandos de movimento do jogador.
   * @param key Tecla pressionada ou liberada
   * @param isPressed true se a tecla foi pressionada, false se liberada
   */
  public void move(char key, boolean isPressed) {
    // Atualiza estado das teclas
    if (key == 'w') upHeld = isPressed;
    if (key == 's') downHeld = isPressed;
    if (key == 'a') leftHeld = isPressed;
    if (key == 'd') rightHeld = isPressed;
  
    // Atualiza direção imediatamente ao pressionar uma tecla
    if (isPressed) {
      if (key == 'w') direction = UP;
      if (key == 's') direction = DOWN;
      if (key == 'a') direction = LEFT;
      if (key == 'd') direction = RIGHT;
    }
  }

  /**
   * Retorna a direção atual do jogador.
   * @return Constante de direção (UP, DOWN, LEFT, RIGHT)
   */
  public int getDirection() {
    return this.direction;
  }
  
  /**
   * Retorna a coordenada X atual do jogador.
   * @return Posição X
   */
  public float getX() {
    return this.x;
  }
  
  /**
   * Retorna a coordenada Y atual do jogador.
   * @return Posição Y
   */
  public float getY() {
    return this.y;
  }
  
  /**
   * Define a coordenada X do jogador.
   * @param newX Nova posição X
   */
  public void setX(float newX) {
    this.x = newX;
  }
  
  /**
   * Define a coordenada Y do jogador.
   * @param newY Nova posição Y
   */
  public void setY(float newY) {
    this.y = newY;
  }
  
  /**
   * Retorna o tamanho (diâmetro) do jogador.
   * @return Tamanho do jogador
   */
  public int getPlayerSize() {
    return this.player_size;
  }
  
  /**
   * Retorna a pontuação atual do jogador.
   * @return Pontuação
   */
  public int getScore() {
    return this.score;
  }
  
  /**
   * Define a pontuação do jogador.
   * @param newScore Nova pontuação
   */
  public void setScore(int newScore) {
    this.score = newScore;
  }
  
  /**
   * Incrementa a pontuação do jogador em 1 ponto.
   */
  public void incrementScore() {
    this.score++;
  }
  
  /**
   * Para imediatamente a aceleração do jogador.
   * Útil para situações como colisões ou reset.
   */
  public void stopAcceleration() {
    ax = 0;
    ay = 0;
  }

  /**
   * Renderiza o jogador na tela.
   * Mostra o jogador como um círculo, sua pontuação e efeitos de modificadores ativos.
   */
  public void display() {
    // Desenha o jogador como um círculo
    ellipse(x, y, player_size, player_size);
    
    // Exibe a pontuação do jogador acima dele
    fill(0);
    textAlign(CENTER, CENTER);
    textSize(14);
    text(score, x, y - player_size/2 - 15);
    
    // Mostra efeito de modificador ativo, se houver
    if (modifierActive) {
      // Verifica se o modificador expirou
      if (millis() - lastModifierTime > modifierDuration) {
        modifierActive = false;
        projectileSpeedModifier = 1.0;
        cooldownModifier = 1.0;
      } else {
        // Exibe texto indicando o modificador ativo
        fill(modifierColor);
        textSize(12);
        text(activeModifierText, x, y + player_size/2 + 15);
        
        // Desenha indicador do efeito de modificador (círculo brilhante ao redor do jogador)
        noFill();
        stroke(modifierColor, 150);
        strokeWeight(3);
        ellipse(x, y, player_size + 10, player_size + 10);
        strokeWeight(1);
        noStroke();
      }
    }
  }
  
  // Objeto de bloqueio para sincronização de acesso aos modificadores
  private final Object modifierLock = new Object();
  
  /**
   * Aplica um modificador ao jogador.
   * @param type Tipo de modificador (conforme definido na classe Modifier)
   */
  public void applyModifier(int type) {
    synchronized(modifierLock) {
      lastModifierTime = millis();
      modifierActive = true;
      
      // Aplica efeito de acordo com o tipo de modificador
      switch (type) {
        case Modifier.GREEN:
          projectileSpeedModifier = 1.5; // Projéteis 50% mais rápidos
          activeModifierText = "Faster Projectiles!";
          modifierColor = color(0, 255, 0);
          break;
        case Modifier.ORANGE:
          projectileSpeedModifier = 0.7; // Projéteis 30% mais lentos
          activeModifierText = "Slower Projectiles";
          modifierColor = color(255, 165, 0);
          break;
        case Modifier.BLUE:
          cooldownModifier = 0.7; // 30% menos cooldown (tiros mais rápidos)
          activeModifierText = "Faster Firing!";
          modifierColor = color(0, 0, 255);
          break;
        case Modifier.RED:
          cooldownModifier = 1.5; // 50% mais cooldown (tiros mais lentos)
          activeModifierText = "Slower Firing";
          modifierColor = color(255, 0, 0);
          break;
      }
    }
  }
  
  /**
   * Retorna o modificador atual de velocidade de projéteis.
   * @return Fator multiplicador de velocidade (1.0 = normal)
   */
  public float getProjectileSpeedModifier() {
    synchronized(modifierLock) {
      return projectileSpeedModifier;
    }
  }
  
  /**
   * Retorna o modificador atual de cooldown entre disparos.
   * @return Fator multiplicador de cooldown (1.0 = normal)
   */
  public float getCooldownModifier() {
    synchronized(modifierLock) {
      return cooldownModifier;
    }
  }
  
  /**
   * reinicia todos os modificadores ao estado padrão.
   * Utilizado ao fazer logout ou reiniciar o jogo.
   */
  public void resetModifiers() {
    synchronized(modifierLock) {
      projectileSpeedModifier = 1.0;
      cooldownModifier = 1.0;
      modifierActive = false;
    }
  }
  
  /**
   * reinicia o estado de movimento do jogador.
   * Usado quando uma partida termina ou o jogador é reposicionado.
   */
  public void resetMovement() {
    upHeld = false;
    downHeld = false;
    leftHeld = false;
    rightHeld = false;
    vx = 0;
    vy = 0;
    ax = 0;
    ay = 0;
  }

  /**
   * Verifica se houve colisão com parede e limpa o flag.
   * @return true se houve colisão com parede desde a última verificação
   */
  public boolean checkAndClearWallCollision() {
    if (wasWallCollision) {
      wasWallCollision = false;
      return true;
    }
    return false;
  }

  /**
   * Método interno para marcar uma colisão com parede.
   * Chamado automaticamente por update() quando ocorre colisão.
   */
  private void handleWallCollision() {
    wasWallCollision = true;
  }
}