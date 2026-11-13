defmodule Trivia.Partida do
  @moduledoc """
  Partida de trivia: un GenServer por partida (secciones 5, 6, 7, 8.4 y 8.5).

  Cada partida vive en su propio proceso, bajo el DynamicSupervisor, y atiende
  al mismo tiempo el temporizador de la ronda, la respuesta del jugador y las
  de sus bots. Se registra con restart: :transient: si falla se reinicia
  desde cero con los mismos argumentos, y si termina bien no.

  La partida entrega sus notificaciones con send/2 a los PID de sus
  jugadores (el cliente del creador y los bots), sin distinguir uno de otro.
  Las notificaciones son mensajes {:trivia, evento}:

  - {:pregunta, info}: enunciado, opciones y tiempo de la ronda
  - {:cierre_ronda, info}: respuesta correcta y puntajes de la ronda
  - {:fin_partida, info}: ranking final y ganador

  Los bots viven en el servidor, así que a ellos se les agrega a la pregunta
  la respuesta correcta (:correcta) para que puedan decidir. Esa información
  nunca se envía a los clientes.

  Las reglas (validar respuestas, armar la partida, puntuar una ronda) están en
  funciones públicas puras para poder probarlas sin procesos.

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use GenServer, restart: :transient
  require Logger

  alias Trivia.{BancoPreguntas, Bot, Errores, GestorPartidas, Persistencia}

  @letras ["A", "B", "C", "D"]
  @pausa_ms 3000
  @max_jugadores 4
  @min_bots 2

  @enforce_keys [:id, :creador, :cliente_pid, :tema, :nivel, :total_preguntas, :tiempo_pregunta]
  defstruct [
    :id,
    :creador,
    :cliente_pid,
    :tema,
    :nivel,
    :total_preguntas,
    :tiempo_pregunta,
    :ronda,
    estado: :esperando,
    pregunta_actual: 0,
    jugadores: [],
    puntajes: %{},
    preguntas: []
  ]

  # ── API pública ──────────────────────────────────────────────────────

  def start_link(argumentos), do: GenServer.start_link(_MODULE_, argumentos)

  def agregar_bot(pid, dificultad), do: GenServer.call(pid, {:agregar_bot, dificultad})
  def iniciar(pid), do: GenServer.call(pid, :iniciar)
  def responder(pid, jugador, letra), do: GenServer.call(pid, {:responder, jugador, letra})
  def abandonar(pid, jugador), do: GenServer.call(pid, {:abandonar, jugador})

  # ── Funciones puras ──────────────────────────────────────────────────

  def nueva(argumentos) do
    creador = %{nombre: argumentos.creador, tipo: :humano, pid: argumentos.cliente_pid}

    %_MODULE_{
      id: argumentos.id,
      creador: argumentos.creador,
      cliente_pid: argumentos.cliente_pid,
      tema: argumentos.tema,
      nivel: argumentos.nivel,
      total_preguntas: argumentos.total_preguntas,
      tiempo_pregunta: argumentos.tiempo_pregunta,
      jugadores: [creador],
      puntajes: %{argumentos.creador => 0}
    }
  end

  def contar_bots(partida) do
    Enum.count(partida.jugadores, &(&1.tipo == :bot))
  end

  def validar_agregar_bot(partida, dificultad) do
    cond do
      partida.estado != :esperando -> {:error, %Errores.PartidaYaIniciada{id: partida.id}}
      length(partida.jugadores) >= @max_jugadores -> {:error, %Errores.PartidaLlena{id: partida.id}}
      dificultad not in [:facil, :dificil] -> {:error, %Errores.DificultadInvalida{dificultad: dificultad}}
      true -> :ok
    end
  end

  def validar_inicio(partida) do
    bots = contar_bots(partida)

    cond do
      partida.estado != :esperando -> {:error, %Errores.PartidaYaIniciada{id: partida.id}}
      bots < @min_bots -> {:error, %Errores.BotsInsuficientes{bots: bots}}
      true -> :ok
    end
  end

  def registrar_respuesta(partida, jugador, letra, ahora_ms) do
    with {:ok, ronda} <- ronda_abierta(partida),
         {:ok, letra} <- validar_letra(letra) do
      if Map.has_key?(ronda.respuestas, jugador) do
        {:ok, :ignorada, partida}
      else
        restantes_ms = max(ronda.limite_ms - ahora_ms, 0)
        respuesta = %{letra: letra, restantes_ms: restantes_ms}
        ronda = %{ronda | respuestas: Map.put(ronda.respuestas, jugador, respuesta)}
        {:ok, :registrada, %{partida | ronda: ronda}}
      end
    end
  end

  defp ronda_abierta(%{ronda: ronda}) do
    if ronda, do: {:ok, ronda}, else: {:error, %Errores.SinRondaAbierta{}}
  end

  defp validar_letra(letra) do
    normalizada = letra |> String.trim() |> String.upcase()

    if normalizada in @letras,
      do: {:ok, normalizada},
      else: {:error, %Errores.LetraInvalida{letra: letra}}
  end

  def calcular_puntaje(nivel, :correcta, restantes, tiempo) do
    puntos_correcta(nivel) + trunc(5 * restantes / tiempo)
  end

  def calcular_puntaje(nivel, :incorrecta, _restantes, _tiempo), do: puntos_incorrecta(nivel)
  def calcular_puntaje(_nivel, :sin_responder, _restantes, _tiempo), do: 0

  defp puntos_correcta(:basico), do: 10
  defp puntos_correcta(:intermedio), do: 15
  defp puntos_correcta(:avanzado), do: 20

  defp puntos_incorrecta(:basico), do: -5
  defp puntos_incorrecta(:intermedio), do: -8
  defp puntos_incorrecta(:avanzado), do: -10

  def cerrar_ronda(%{ronda: ronda, jugadores: jugadores, puntajes: puntajes, tiempo_pregunta: tiempo} = partida) do
    nivel = ronda.pregunta.nivel
    correcta = ronda.pregunta.respuesta

    filas =
      for %{nombre: nombre} <- jugadores do
        respuesta = Map.get(ronda.respuestas, nombre)
        puntos = puntos_de_respuesta(respuesta, correcta, nivel, tiempo)
        total = Map.get(puntajes, nombre) + puntos
        %{jugador: nombre, puntos: puntos, total: total}
      end

    nuevos_puntajes = Map.new(filas, &{&1.jugador, &1.total})
    nueva = %{partida | puntajes: nuevos_puntajes, ronda: nil, pregunta_actual: ronda.numero}
    {Enum.sort_by(filas, &(-&1.puntos)), nueva}
  end

  defp puntos_de_respuesta(respuesta, correcta, nivel, tiempo) do
    case respuesta do
      nil -> calcular_puntaje(nivel, :sin_responder, 0, tiempo)
      %{letra: ^correcta, restantes_ms: ms} -> calcular_puntaje(nivel, :correcta, ms / 1000, tiempo)
      _otra_letra -> calcular_puntaje(nivel, :incorrecta, 0, tiempo)
    end
  end

  def linea_resultado(partida, ganadores, fecha) do
    puntajes = Enum.map_join(partida.jugadores, ",", &"#{&1.nombre}=#{partida.puntajes[&1.nombre]}")
    Enum.join([fecha, partida.id, partida.tema, partida.nivel, Enum.join(ganadores, ";"), puntajes], "|")
  end

  # ── Callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(argumentos) do
    partida = nueva(argumentos)
    GestorPartidas.reportar(partida.id, self())
    {:ok, partida}
  end

  @impl true
  def handle_call({:agregar_bot, dificultad}, _from, %{jugadores: jugadores, puntajes: puntajes} = partida) do
    case validar_agregar_bot(partida, dificultad) do
      :ok ->
        nombre = "bot_#{contar_bots(partida) + 1}"
        {:ok, bot_pid} = Bot.start_link(%{partida: self(), nombre: nombre, dificultad: dificultad})
        bot = %{nombre: nombre, tipo: :bot, pid: bot_pid}

        nueva_partida = %{
          partida
          | jugadores: jugadores ++ [bot],
            puntajes: Map.put(puntajes, nombre, 0)
        }

        respuesta = %{id: partida.id, bot: nombre, dificultad: dificultad, jugadores: length(nueva_partida.jugadores)}
        {:reply, {:ok, respuesta}, nueva_partida}

      {:error, error} ->
        {:reply, {:error, error}, partida}
    end
  end

  def handle_call(:iniciar, _from, %{jugadores: jugadores} = partida) do
    with :ok <- validar_inicio(partida),
         {:ok, preguntas} <- BancoPreguntas.sortear(partida.tema, partida.nivel, partida.total_preguntas) do
      nueva_partida = %{partida | estado: :en_curso, preguntas: preguntas}
      nombres = Enum.map(jugadores, &(&1.nombre))
      respuesta = %{id: partida.id, jugadores: nombres, preguntas: length(preguntas)}

      send(self(), :abrir_ronda)
      {:reply, {:ok, respuesta}, nueva_partida}
    else
      {:error, error} -> {:reply, {:error, error}, partida}
    end
  end

  def handle_call({:responder, jugador, letra}, _from, partida) do
    case registrar_respuesta(partida, jugador, letra, System.monotonic_time(:millisecond)) do
      {:ok, tipo, nueva_partida} ->
        if tipo == :registrada and todos_respondieron?(nueva_partida),
          do: send(self(), {:vence_ronda, nueva_partida.ronda.numero})

        {:reply, {:ok, tipo}, nueva_partida}

      {:error, error} ->
        {:reply, {:error, error}, partida}
    end
  end

  def handle_call({:abandonar, jugador}, _from, partida) do
    cond do
      jugador != partida.creador ->
        {:reply, {:error, %Errores.SinPartida{}}, partida}

      partida.estado == :esperando ->
        GestorPartidas.finalizada(partida.id)
        {:stop, :normal, {:ok, :cancelada}, partida}

      true ->
        {:stop, :normal, {:ok, :finalizada}, finalizar(partida, :abandono)}
    end
  end

  @impl true
  def handle_info(:abrir_ronda, partida) do
    if partida.estado == :en_curso and is_nil(partida.ronda),
      do: {:noreply, abrir_ronda(partida)},
      else: {:noreply, partida}
  end

  def handle_info({:vence_ronda, numero}, %{ronda: ronda} = partida) do
    if ronda && ronda.numero == numero,
      do: cerrar_y_avanzar(partida),
      else: {:noreply, partida}
  end

  def handle_info(:cliente_caido, partida) do
    if partida.estado == :en_curso do
      {:stop, :normal, finalizar(partida, :abandono)}
    else
      GestorPartidas.finalizada(partida.id)
      {:stop, :normal, partida}
    end
  end

  def handle_info(_otro, partida), do: {:noreply, partida}

  @impl true
  def terminate(_razon, partida) do
    for %{tipo: :bot, pid: pid} <- partida.jugadores, do: send(pid, :terminar)
  end

  # ── Funciones privadas ───────────────────────────────────────────────

  defp todos_respondieron?(%{ronda: ronda, jugadores: jugadores}) do
    map_size(ronda.respuestas) == length(jugadores)
  end

  defp abrir_ronda(partida) do
    numero = partida.pregunta_actual + 1
    pregunta = Enum.at(partida.preguntas, numero - 1)
    inicio = System.monotonic_time(:millisecond)
    duracion = partida.tiempo_pregunta * 1000
    temporizador = Process.send_after(self(), {:vence_ronda, numero}, duracion)

    ronda = %{
      numero: numero,
      pregunta: pregunta,
      inicio_ms: inicio,
      limite_ms: inicio + duracion,
      respuestas: %{},
      temporizador: temporizador
    }

    nueva_partida = %{partida | ronda: ronda, pregunta_actual: numero}
    enviar_pregunta(nueva_partida)
    nueva_partida
  end

  defp enviar_pregunta(%{ronda: %{numero: numero, pregunta: pregunta}, total_preguntas: total, tema: tema, tiempo_pregunta: tiempo, jugadores: jugadores}) do
    info = %{
      numero: numero,
      total: total,
      tema: tema,
      nivel: pregunta.nivel,
      enunciado: pregunta.enunciado,
      opciones: pregunta.opciones,
      tiempo: tiempo
    }

    info_bot = Map.put(info, :correcta, pregunta.respuesta)

    for %{tipo: tipo, pid: pid} <- jugadores do
      send(pid, {:trivia, {:pregunta, if(tipo == :bot, do: info_bot, else: info)}})
    end
  end

  defp cerrar_y_avanzar(%{ronda: ronda, total_preguntas: total} = partida) do
    Process.cancel_timer(ronda.temporizador)
    {filas, nueva_partida} = cerrar_ronda(partida)
    correcta = ronda.pregunta.respuesta
    {_letra, texto} = List.keyfind(ronda.pregunta.opciones, correcta, 0)

    notificar(
      nueva_partida,
      {:cierre_ronda, %{numero: ronda.numero, correcta: correcta, texto: texto, resultados: filas}}
    )

    if ronda.numero >= total do
      {:stop, :normal, finalizar(nueva_partida, :completa)}
    else
      Process.send_after(self(), :abrir_ronda, @pausa_ms)
      {:noreply, nueva_partida}
    end
  end

  defp finalizar(partida, motivo) do
    terminada = %{partida | estado: :finalizada}

    ranking =
      terminada.jugadores
      |> Enum.map(&{&1.nombre, terminada.puntajes[&1.nombre]})
      |> Enum.sort_by(fn {_nombre, puntos} -> -puntos end)

    {_lider, mayor} = hd(ranking)
    ganadores = for {nombre, puntos} <- ranking, puntos == mayor, do: nombre

    fecha = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    case Persistencia.agregar_resultado(linea_resultado(terminada, ganadores, fecha)) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se pudo guardar el resultado: #{inspect(razon)}")
    end

    GestorPartidas.finalizada(terminada.id)

    notificar(
      terminada,
      {:fin_partida,
       %{
         id: terminada.id,
         tema: terminada.tema,
         nivel: terminada.nivel,
         ranking: ranking,
         ganadores: ganadores,
         motivo: motivo
       }}
    )

    terminada
  end

  defp notificar(partida, evento) do
    for %{pid: pid} <- partida.jugadores, do: send(pid, {:trivia, evento})
  end
end
