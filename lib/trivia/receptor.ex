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
  def iniciar do
    spawn_link(fn -> bucle() end)
  end

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
  def formatear({:pregunta, info}) do
    encabezado =
      "═══ Pregunta #{info.numero} de #{info.total} - #{String.capitalize(info.tema)} " <>
        "- Nivel #{nivel_texto(info.nivel)} ═══"

    opciones =
      info.opciones
      |> Enum.map(fn {letra, texto} -> "#{letra}) #{texto}" end)
      |> Enum.join("   ")

    Enum.join(
      [
        "",
        encabezado,
        info.enunciado,
        " " <> opciones,
        "Tiempo: #{info.tiempo} segundos",
        "Responda con: answer <A|B|C|D>"
      ],
      "\n"
    )
  end

  def formatear({:cierre_ronda, info}) do
    filas =
      Enum.map(info.resultados, fn fila ->
        " #{fila.jugador} #{con_signo(fila.puntos)} (total #{fila.total})"
      end)

    Enum.join(["", "Respuesta correcta: #{info.correcta}) #{info.texto}" | filas], "\n")
  end

  def formatear({:fin_partida, info}) do
    encabezado =
      "═══ Fin de la partida #{info.id} (#{info.tema}, nivel #{nivel_texto(info.nivel)}) ═══"

    filas =
      info.ranking
      |> Enum.with_index(1)
      |> Enum.map(fn {{jugador, puntos}, posicion} ->
        String.pad_trailing("#{posicion}", 4) <> String.pad_trailing(jugador, 14) <> "#{puntos}"
      end)

    ganador =
      case info.ganadores do
        [uno] -> "Ganador: #{uno}"
        varios -> "Ganadores (empate): #{Enum.join(varios, ", ")}"
      end

    aviso =
      if info.motivo == :abandono do
        ["La partida terminó antes de tiempo porque el jugador la abandonó."]
      else
        []
      end

    Enum.join(["", encabezado, "#   Jugador       Puntaje"] ++ filas ++ [ganador] ++ aviso, "\n")
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
