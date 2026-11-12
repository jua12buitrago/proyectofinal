defmodule Trivia.Bot do
  use GenServer

  alias Trivia.Partida

  @letras ["A", "B", "C", "D"]

  # ── API pública ──────────────────────────────────────────────────────

  def start_link(datos), do: GenServer.start_link(__MODULE__, datos)

  def decidir(dificultad, nivel, correcta, tiempo) do
    {desde, hasta} = ventana(dificultad)
    retardo = round(tiempo * 1000 * (desde + :rand.uniform() * (hasta - desde)))

    letra =
      if :rand.uniform() <= probabilidad(dificultad, nivel),
        do: correcta,
        else: Enum.random(@letras -- [correcta])

    {letra, retardo}
  end

  defp probabilidad(:facil, :basico), do: 0.4
  defp probabilidad(:facil, :intermedio), do: 0.3
  defp probabilidad(:facil, :avanzado), do: 0.2
  defp probabilidad(:dificil, :basico), do: 0.8
  defp probabilidad(:dificil, :intermedio), do: 0.7
  defp probabilidad(:dificil, :avanzado), do: 0.6

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
