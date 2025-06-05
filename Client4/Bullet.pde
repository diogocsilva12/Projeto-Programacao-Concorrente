///////////////////////////////////////////////////////////////////////////////
// Classe Bullet
// 
// Implementa a lógica dos projéteis disparados pelos jogadores.
// Gerencia movimento, colisões e aplicação de modificadores.
///////////////////////////////////////////////////////////////////////////////

public class Bullet {
  private float x, y;       // Posição atual do projétil
  private float vx, vy;     // Componentes do vetor velocidade
  private float speed = 10; // Velocidade base do projétil

  private Player shooter;   // Referência ao jogador que disparou o projétil

  /**
   * Construtor de projétil.
   * Cria um projétil que se move do ponto (x,y) em direção a (targetX,targetY).
   * 
   * @param x Posição inicial X do projétil
   * @param y Posição inicial Y do projétil
   * @param targetX Coordenada X do alvo (direção do movimento)
   * @param targetY Coordenada Y do alvo (direção do movimento)
   * @param shooter Referência ao jogador que disparou
   */
  public Bullet(float x, float y, float targetX, float targetY, Player shooter) {
    this.x = x;
    this.y = y;
    this.shooter = shooter;

    // Calcula vetor direção
    float dx = targetX - x;
    float dy = targetY - y;
    float h = sqrt(dx * dx + dy * dy); // Hipotenusa (distância)

    // Aplica o modificador de velocidade do atirador
    float adjustedSpeed = speed * shooter.getProjectileSpeedModifier();
    
    // Calcula componentes da velocidade
    vx = (dx / h) * adjustedSpeed;
    vy = (dy / h) * adjustedSpeed;
  }

  /**
   * Atualiza a posição do projétil baseado na sua velocidade.
   * Esta função é chamada a cada frame.
   */
  public void update() {
    x += vx;
    y += vy;
  }
  
  /**
   * Retorna a coordenada X atual do projétil.
   * @return Posição X
   */
  public float getX() {
    return this.x;
  }
    
  /**
   * Retorna a coordenada Y atual do projétil.
   * @return Posição Y
   */
  public float getY() {
    return this.y;
  }

  /**
   * Renderiza o projétil na tela.
   * Desenha o projétil como um pequeno círculo.
   */
  public void display() {
    ellipse(x, y, 10, 10);
  }

  /**
   * Verifica se o projétil colidiu com um jogador.
   * O projétil não pode colidir com o jogador que o disparou.
   * 
   * @param p Jogador a verificar colisão
   * @return true se houve colisão, false caso contrário
   */
  public boolean checkCollision(Player p) {
    // Ignora colisão com o próprio atirador
    if (p == shooter) return false;
    
    // Verifica distância entre o projétil e o jogador
    float distance = dist(x, y, p.getX(), p.getY());
    return distance < (5 + p.getPlayerSize() / 2);
  }

  /**
   * Verifica se o projétil saiu dos limites da tela.
   * Projéteis fora da tela são removidos para economizar recursos.
   * 
   * @return true se o projétil está fora da tela, false caso contrário
   */
  public boolean isOffScreen() {
    return x < 0 || x > width || y < 0 || y > height;
  }

  /**
   * Retorna o jogador que disparou este projétil.
   * Utilizado para atribuir pontuação e evitar auto-colisão.
   * 
   * @return Referência ao jogador que disparou
   */
  public Player getShooter() {
    return this.shooter;
  }
}