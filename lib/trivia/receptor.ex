defmodule Trivia.Receptor do
  @moduledoc """
  Recepción de las notificaciones de la partida en el cliente (sección 8.3).

  Es el proceso cuyo PID se registra en el servidor al conectarse y al crear la
  partida. Las notificaciones (una pregunta, el cierre de una ronda, el ranking
  final) llegan sin que nadie las pida, en cualquier momento. Por eso este
  proceso es distinto del que lee el teclado: un mensaje que llega se muestra
  de inmediato, aunque el jugador todavía no haya escrito nada.

  Solo muestra lo que recibe; no tiene lógica de juego y nunca ve la respuesta
  correcta de una pregunta abierta.

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """

  @doc "Crea el proceso receptor (enlazado al que lo llama) y devuelve su PID."
  def iniciar, do: spawn_link(&bucle/0)

  @doc "Detiene el receptor."
  def detener(pid), do: send(pid, :detener)

  # Espera mensajes de la partida y los muestra; termina con :detener.
  defp bucle do
    receive do
      {:trivia, evento} ->
        IO.puts(formatear(evento))
        bucle()

      :detener ->
        :ok
    end
  end

  @doc "Convierte un evento de la partida en el texto que se muestra al jugador."
  def formatear({:pregunta, %{numero: num, total: tot, tema: tema, nivel: nivel, opciones: ops, enunciado: enunciado, tiempo: tiempo}}) do
    encabezado = "═══ Pregunta #{num} de #{tot} #{String.capitalize(tema)} - Nivel #{nivel_texto(nivel)} ═══"

    opciones = Enum.map_join(ops, "   ", fn {letra, texto} -> "#{letra}) #{texto}" end)

    Enum.join(
      [
        "",
        encabezado,
        enunciado,
        " " <> opciones,
        "Tiempo: #{tiempo} segundos",
        "Responda con: answer <A|B|C|D>"
      ],
      "\n"
    )
  end

  def formatear({:cierre_ronda, %{correcta: correcta, texto: texto, resultados: resultados}}) do
    filas = Enum.map_join(resultados, "\n", &(" #{&1.jugador} #{con_signo(&1.puntos)} (total #{&1.total})"))
    "\nRespuesta correcta: #{correcta}) #{texto}\n#{filas}"
  end

  def formatear({:fin_partida, %{id: id, tema: tema, nivel: nivel, ranking: ranking, ganadores: ganadores, motivo: motivo}}) do
    encabezado = "═══ Fin de la partida #{id} (#{tema}, nivel #{nivel_texto(nivel)}) ═══"

    filas =
      ranking
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{jugador, puntos}, posicion} ->
        String.pad_trailing("#{posicion}", 4) <> String.pad_trailing(jugador, 14) <> "#{puntos}"
      end)

    ganador =
      case ganadores do
        [uno] -> "Ganador: #{uno}"
        varios -> "Ganadores (empate): #{Enum.join(varios, ", ")}"
      end

    aviso =
      if motivo == :abandono,
        do: ["La partida terminó antes de tiempo porque el jugador la abandonó."],
        else: []

    Enum.join(["", encabezado, "#   Jugador       Puntaje", filas, ganador] ++ aviso, "\n")
  end

  def formatear({:reinicio, id}) do
    "\nLa partida #{id} falló y se reinició sin su progreso. " <>
      "Agregue los bots y ejecute start_game para jugar de nuevo."
  end

  def formatear(otro), do: "\n" <> inspect(otro)

  @doc "Texto de un nivel: `:basico` -> `\"básico\"`."
  def nivel_texto(:basico), do: "básico"
  def nivel_texto(:intermedio), do: "intermedio"
  def nivel_texto(:avanzado), do: "avanzado"

  @doc "Puntos con signo explícito para los positivos: `14` -> `\"+14\"`."
  def con_signo(puntos) when puntos > 0, do: "+#{puntos}"
  def con_signo(puntos), do: "#{puntos}"
end
