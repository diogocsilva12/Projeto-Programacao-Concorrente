///////////////////////////////////////////////////////////////////////////////
// Classe Modifier
// 
// Implementa os diferentes tipos de modificadores que os jogadores podem coletar
// durante uma partida. Cada modificador altera temporariamente alguma 
// característica do jogador que o coleta.
///////////////////////////////////////////////////////////////////////////////

public class Modifier {
  private float x, y;  // Posição do modificador
  private int type;    // Tipo de modificador
  
  // Constantes de tipo de modificador
  public static final int GREEN = 0;  // Aumenta velocidade de projéteis (+50%)
  public static final int ORANGE = 1; // Diminui velocidade de projéteis (-30%)
  public static final int BLUE = 2;   // Diminui tempo entre disparos (-30%)
  public static final int RED = 3;    // Aumenta tempo entre disparos (+50%)
  
  /**
   * Construtor de modificador.
   * 
   * @param x Posição X onde o modificador aparece
   * @param y Posição Y onde o modificador aparece
   * @param type Tipo de modificador, conforme constantes definidas
   */
  public Modifier(float x, float y, int type) {
    this.x = x;
    this.y = y;
    this.type = type;
  }
  
  /**
   * Renderiza o modificador na tela.
   * Cada tipo de modificador tem uma cor distinta para identificação visual.
   */
  public void display() {
    // Define cor baseada no tipo
    switch (type) {
      case GREEN:  // Verde: projéteis mais rápidos
        fill(0, 255, 0);
        break;
      case ORANGE: // Laranja: projéteis mais lentos
        fill(255, 165, 0);
        break;
      case BLUE:   // Azul: disparo mais rápido
        fill(0, 0, 255);
        break;
      case RED:    // Vermelho: disparo mais lento
        fill(255, 0, 0);
        break;
    }
    
    // Desenha como um círculo
    ellipse(x, y, 15, 15);
  }
  
  /**
   * Retorna a coordenada X do modificador.
   * @return Posição X
   */
  public float getX() {
    return x;
  }
  
  /**
   * Retorna a coordenada Y do modificador.
   * @return Posição Y
   */
  public float getY() {
    return y;
  }
  
  /**
   * Retorna o tipo deste modificador.
   * @return Tipo do modificador
   */
  public int getType() {
    return type;
  }
  
  /**
   * Verifica se o jogador colidiu com este modificador.
   * 
   * @param p Jogador a verificar colisão
   * @return true se houve colisão, false caso contrário
   */
  public boolean checkCollision(Player p) {
    float distance = dist(x, y, p.getX(), p.getY());
    return distance < (10 + p.getPlayerSize() / 2);
  }
}