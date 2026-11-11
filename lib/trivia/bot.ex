defmodule Trivia.Bot do
  @moduledoc """
  Jugador automático (sección 6.6).

  Cada bot vive en su propio proceso, dentro del servidor, y está enlazado a la
  partida que lo creó. Recibe las mismas notificaciones que el cliente de un
  jugador humano. Cuando le llega una pregunta decide qué contestar, programa
  su respuesta con `Process.send_after/3` y la envía a la partida con
  `Trivia.Partida.responder/3`, igual que lo hace un jugador humano.

  La decisión está separada del proceso, en `decidir/4`, para poder probarla.

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use GenServer

  alias Trivia.Partida

  @letras ["A", "B", "C", "D"]

  # ── API pública ──────────────────────────────────────────────────────

  @doc """
  Arranca un bot enlazado al proceso que lo llama (la partida). Recibe un mapa
  con `:partida` (pid), `:nombre` y `:dificultad`.
  """
  def start_link(datos), do: GenServer.start_link(__MODULE__, datos)

  @doc """
  Decide qué responde un bot y cuándo.

  Solo necesita la dificultad del bot, el nivel de la pregunta, la respuesta
  correcta y el tiempo de la pregunta en segundos. Devuelve
  `{letra, retardo_en_milisegundos}`. Si el bot falla, escoge al azar una de
  las tres opciones incorrectas.
  """
  def decidir(dificultad, nivel, correcta, tiempo) do
    {desde, hasta} = ventana(dificultad)
    fraccion = desde + :rand.uniform() * (hasta - desde)
    retardo = round(tiempo * 1000 * fraccion)

    letra =
      if :rand.uniform() <= probabilidad(dificultad, nivel) do
        correcta
      else
        Enum.random(@letras -- [correcta])
      end

    {letra, retardo}
  end

  # Probabilidad de acertar según la dificultad del bot y el nivel de la pregunta.
  defp probabilidad(:facil, :basico), do: 0.4
  defp probabilidad(:facil, :intermedio), do: 0.3
  defp probabilidad(:facil, :avanzado), do: 0.2
  defp probabilidad(:dificil, :basico), do: 0.8
  defp probabilidad(:dificil, :intermedio), do: 0.7
  defp probabilidad(:dificil, :avanzado), do: 0.6

  # Momento de la respuesta, como fracción del tiempo de la pregunta.
  defp ventana(:facil), do: {0.4, 0.9}
  defp ventana(:dificil), do: {0.1, 0.4}

  # ── Callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(datos), do: {:ok, datos}

  @impl true
  def handle_info({:trivia, {:pregunta, info}}, bot) do
    {letra, retardo} = decidir(bot.dificultad, info.nivel, info.correcta, info.tiempo)
    Process.send_after(self(), {:responder, letra}, retardo)
    {:noreply, bot}
  end

  def handle_info({:responder, letra}, bot) do
    # Si la ronda ya cerró, la partida rechaza la respuesta y no pasa nada.
    Partida.responder(bot.partida, bot.nombre, letra)
    {:noreply, bot}
  end

  # La partida terminó: el bot también.
  def handle_info(:terminar, bot), do: {:stop, :normal, bot}

  # Cierres de ronda, ranking final y demás notificaciones no requieren acción.
  def handle_info(_otro, bot), do: {:noreply, bot}
end
