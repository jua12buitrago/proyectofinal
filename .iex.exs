# Este archivo lo carga IEx al abrir la consola. Solo muestra una pista
# según el rol del nodo; no ejecuta lógica del juego.
case Trivia.Application.rol() do
  :cliente ->
    IO.puts("""

    Nodo cliente listo. Para abrir la consola del juego ejecute:

        Trivia.Cliente.iniciar()
    """)

  _otro ->
    :ok
end
