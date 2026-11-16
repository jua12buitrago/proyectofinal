defmodule Trivia.Bot do
  @moduledoc """
  Jugador automático que participa en una partida como un proceso `GenServer`
  en el nodo del servidor.

  Recibe las mismas notificaciones que un cliente humano y programa su respuesta
  con `Process.send_after/3`. La función `decidir/4` es pura (desacoplada del
  proceso) y es la que se prueba con ExUnit.

    - autor: Juan Manuel Castaño Buitrago, Christian David Lopera Castaño, Samuel Mejia Guerrero
    - fecha: Noviembre del 2026
  """

  use GenServer

  alias Trivia.Partida

  @letras ["A", "B", "C", "D"]

  # ── API pública ──────────────────────────────────────────────────────

  @doc "Arranca el proceso del bot con sus datos iniciales."
  def start_link(datos), do: GenServer.start_link(__MODULE__, datos)

  # ── Funciones puras ──────────────────────────────────────────────────

  @doc """
  Calcula la letra elegida y el retardo (en milisegundos) antes de responder.

  Según la dificultad del bot y el nivel de la pregunta, decide si acierta o
  elige al azar una de las tres opciones incorrectas dentro de su ventana de tiempo.
  """
  def decidir(dificultad, nivel, correcta, tiempo) do
    {desde, hasta} = ventana(dificultad)
    retardo = round(tiempo * 1000 * (desde + :rand.uniform() * (hasta - desde)))

    letra =
      if :rand.uniform() <= probabilidad(dificultad, nivel),
        do: correcta,
        else: Enum.random(@letras -- [correcta])

    {letra, retardo}
  end

  # ── Funciones privadas ───────────────────────────────────────────────

  # Probabilidad de acierto según la dificultad del bot y el nivel de la pregunta.
  defp probabilidad(:facil, :basico), do: 0.4
  defp probabilidad(:facil, :intermedio), do: 0.3
  defp probabilidad(:facil, :avanzado), do: 0.2
  defp probabilidad(:dificil, :basico), do: 0.8
  defp probabilidad(:dificil, :intermedio), do: 0.7
  defp probabilidad(:dificil, :avanzado), do: 0.6

  # Rango porcentual del tiempo de ronda en el que responde según su dificultad.
  defp ventana(:facil), do: {0.4, 0.9}
  defp ventana(:dificil), do: {0.1, 0.4}

  # ── Callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(datos), do: {:ok, datos}

  @impl true
  def handle_info({:trivia, {:pregunta, %{nivel: nivel, correcta: correcta, tiempo: tiempo}}}, %{dificultad: dificultad} = bot) do
    {letra, retardo} = decidir(dificultad, nivel, correcta, tiempo)
    Process.send_after(self(), {:responder, letra}, retardo)
    {:noreply, bot}
  end

  def handle_info({:responder, letra}, %{partida: partida, nombre: nombre} = bot) do
    Partida.responder(partida, nombre, letra)
    {:noreply, bot}
  end

  def handle_info(:terminar, bot), do: {:stop, :normal, bot}

  def handle_info(_otro, bot), do: {:noreply, bot}
end
