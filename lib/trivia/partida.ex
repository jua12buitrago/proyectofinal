defmodule Trivia.Partida do
  @moduledoc """
  Partida de trivia: un GenServer por partida (secciones 5, 6, 7, 8.4 y 8.5).

  Cada partida vive en su propio proceso, bajo el `DynamicSupervisor`, y atiende
  al mismo tiempo el temporizador de la ronda, la respuesta del jugador y las
  de sus bots. Se registra con `restart: :transient`: si falla se reinicia
  desde cero con los mismos argumentos, y si termina bien no.

  La partida entrega sus notificaciones con `send/2` a los PID de sus
  jugadores (el cliente del creador y los bots), sin distinguir uno de otro.
  Las notificaciones son mensajes `{:trivia, evento}`:

  - `{:pregunta, info}`: enunciado, opciones y tiempo de la ronda
  - `{:cierre_ronda, info}`: respuesta correcta y puntajes de la ronda
  - `{:fin_partida, info}`: ranking final y ganador

  Los bots viven en el servidor, así que a ellos se les agrega a la pregunta
  la respuesta correcta (`:correcta`) para que puedan decidir. Esa información
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

  # Modelo de datos de la sección 3.3. Cada jugador es un mapa con
  # :nombre, :tipo (:humano o :bot) y :pid. La ronda abierta es un mapa
  # (o nil cuando no hay ronda abierta).
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

  @doc """
  Arranca una partida. `argumentos` es un mapa con `:id`, `:creador`, `:tema`,
  `:nivel`, `:total_preguntas`, `:tiempo_pregunta` y `:cliente_pid`.
  """
  def start_link(argumentos), do: GenServer.start_link(__MODULE__, argumentos)

  @doc "Agrega un bot (`:facil` o `:dificil`). Devuelve `{:ok, datos}` o `{:error, error}`."
  def agregar_bot(pid, dificultad), do: GenServer.call(pid, {:agregar_bot, dificultad})

  @doc "Inicia la partida: sortea las preguntas y abre la primera ronda."
  def iniciar(pid), do: GenServer.call(pid, :iniciar)

  @doc "Registra la respuesta de un jugador en la ronda abierta."
  def responder(pid, jugador, letra), do: GenServer.call(pid, {:responder, jugador, letra})

  @doc "El creador abandona la partida (se cancela o termina con lo jugado)."
  def abandonar(pid, jugador), do: GenServer.call(pid, {:abandonar, jugador})

  # ── Funciones puras ──────────────────────────────────────────────────

  @doc "Crea la partida inicial: en espera y solo con el creador."
  def nueva(argumentos) do
    creador = %{nombre: argumentos.creador, tipo: :humano, pid: argumentos.cliente_pid}

    %__MODULE__{
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

  @doc "Cantidad de bots que hay en la partida."
  def contar_bots(partida) do
    Enum.count(partida.jugadores, fn jugador -> jugador.tipo == :bot end)
  end

  @doc """
  Valida `add_bot`: la partida no debe estar iniciada ni llena y la dificultad
  debe ser `:facil` o `:dificil`. Devuelve `:ok` o `{:error, error}`.
  """
  def validar_agregar_bot(partida, dificultad) do
    cond do
      partida.estado != :esperando ->
        {:error, %Errores.PartidaYaIniciada{id: partida.id}}

      length(partida.jugadores) >= @max_jugadores ->
        {:error, %Errores.PartidaLlena{id: partida.id}}

      dificultad not in [:facil, :dificil] ->
        {:error, %Errores.DificultadInvalida{dificultad: dificultad}}

      true ->
        :ok
    end
  end

  @doc "Valida `start_game`: la partida debe estar en espera y tener al menos dos bots."
  def validar_inicio(partida) do
    bots = contar_bots(partida)

    cond do
      partida.estado != :esperando -> {:error, %Errores.PartidaYaIniciada{id: partida.id}}
      bots < @min_bots -> {:error, %Errores.BotsInsuficientes{bots: bots}}
      true -> :ok
    end
  end

  @doc """
  Registra la respuesta de un jugador (sección 6.3).

  `ahora_ms` es el instante en que la partida recibió la respuesta, en
  milisegundos. Devuelve:

  - `{:ok, :registrada, partida}`: era la primera respuesta del jugador
  - `{:ok, :ignorada, partida}`: ya había respondido; no cambia nada
  - `{:error, error}`: no hay ronda abierta o la letra no es A, B, C o D
  """
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

  defp ronda_abierta(partida) do
    case partida.ronda do
      nil -> {:error, %Errores.SinRondaAbierta{}}
      ronda -> {:ok, ronda}
    end
  end

  # La letra se acepta en mayúscula o minúscula. Cualquier otro valor se rechaza.
  defp validar_letra(letra) do
    normalizada = letra |> String.trim() |> String.upcase()

    if normalizada in @letras do
      {:ok, normalizada}
    else
      {:error, %Errores.LetraInvalida{letra: letra}}
    end
  end

  @doc """
  Puntos de un jugador en una ronda (sección 6.4).

  `resultado` es `:correcta`, `:incorrecta` o `:sin_responder`. `restantes` son
  los segundos que faltaban para que venciera el tiempo cuando llegó la
  respuesta y `tiempo` es el tiempo de la pregunta. Una respuesta correcta
  suma además la bonificación `trunc(5 * restantes / tiempo)`.
  """
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

  @doc """
  Cierra la ronda abierta: calcula los puntos de cada jugador (el que no
  respondió suma 0), actualiza los puntajes de la partida y deja la ronda en
  `nil`.

  Devuelve `{filas, partida}`. Cada fila es un mapa con `:jugador`, `:puntos`
  (de la ronda) y `:total` (acumulado), ordenadas por los puntos de la ronda.
  """
  def cerrar_ronda(partida) do
    ronda = partida.ronda
    nivel = ronda.pregunta.nivel
    correcta = ronda.pregunta.respuesta

    filas =
      Enum.map(partida.jugadores, fn jugador ->
        respuesta = Map.get(ronda.respuestas, jugador.nombre)
        puntos = puntos_de_respuesta(respuesta, correcta, nivel, partida.tiempo_pregunta)
        total = Map.get(partida.puntajes, jugador.nombre) + puntos
        %{jugador: jugador.nombre, puntos: puntos, total: total}
      end)

    puntajes = Map.new(filas, fn fila -> {fila.jugador, fila.total} end)
    nueva = %{partida | puntajes: puntajes, ronda: nil, pregunta_actual: ronda.numero}
    {Enum.sort_by(filas, fn fila -> -fila.puntos end), nueva}
  end

  defp puntos_de_respuesta(respuesta, correcta, nivel, tiempo) do
    case respuesta do
      nil ->
        calcular_puntaje(nivel, :sin_responder, 0, tiempo)

      %{letra: ^correcta, restantes_ms: ms} ->
        calcular_puntaje(nivel, :correcta, ms / 1000, tiempo)

      _otra_letra ->
        calcular_puntaje(nivel, :incorrecta, 0, tiempo)
    end
  end

  @doc """
  Línea de `results.log` para una partida terminada:
  `fecha|id|tema|nivel|ganadores|jugador=puntos,jugador=puntos`.
  """
  def linea_resultado(partida, ganadores, fecha) do
    puntajes =
      partida.jugadores
      |> Enum.map(fn jugador -> "#{jugador.nombre}=#{Map.get(partida.puntajes, jugador.nombre)}" end)
      |> Enum.join(",")

    Enum.join(
      [fecha, partida.id, partida.tema, Atom.to_string(partida.nivel), Enum.join(ganadores, ";"), puntajes],
      "|"
    )
  end

  # ── Callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(argumentos) do
    partida = nueva(argumentos)
    # Se usa cast y no call: el gestor está esperando a que el supervisor
    # termine de arrancar esta partida y un call lo dejaría bloqueado.
    GestorPartidas.reportar(partida.id, self())
    {:ok, partida}
  end

  @impl true
  def handle_call({:agregar_bot, dificultad}, _from, partida) do
    case validar_agregar_bot(partida, dificultad) do
      :ok ->
        nombre = "bot_#{contar_bots(partida) + 1}"

        # Bot.start_link enlaza el bot a esta partida: si ella muere, el bot muere con ella.
        {:ok, bot_pid} = Bot.start_link(%{partida: self(), nombre: nombre, dificultad: dificultad})

        bot = %{nombre: nombre, tipo: :bot, pid: bot_pid}

        nueva_partida = %{
          partida
          | jugadores: partida.jugadores ++ [bot],
            puntajes: Map.put(partida.puntajes, nombre, 0)
        }

        respuesta = %{
          id: partida.id,
          bot: nombre,
          dificultad: dificultad,
          jugadores: length(nueva_partida.jugadores)
        }

        {:reply, {:ok, respuesta}, nueva_partida}

      {:error, error} ->
        {:reply, {:error, error}, partida}
    end
  end

  def handle_call(:iniciar, _from, partida) do
    with :ok <- validar_inicio(partida),
         {:ok, preguntas} <-
           BancoPreguntas.sortear(partida.tema, partida.nivel, partida.total_preguntas) do
      nueva_partida = %{partida | estado: :en_curso, preguntas: preguntas}
      nombres = Enum.map(partida.jugadores, fn jugador -> jugador.nombre end)
      respuesta = %{id: partida.id, jugadores: nombres, preguntas: length(preguntas)}

      # La primera ronda se abre con un mensaje, para que la respuesta salga primero.
      send(self(), :abrir_ronda)
      {:reply, {:ok, respuesta}, nueva_partida}
    else
      {:error, error} -> {:reply, {:error, error}, partida}
    end
  end

  def handle_call({:responder, jugador, letra}, _from, partida) do
    case registrar_respuesta(partida, jugador, letra, System.monotonic_time(:millisecond)) do
      {:ok, tipo, nueva_partida} ->
        # Si ya respondieron todos, la ronda se cierra sin esperar al temporizador.
        if tipo == :registrada and todos_respondieron?(nueva_partida) do
          send(self(), {:vence_ronda, nueva_partida.ronda.numero})
        end

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
        # Si el creador abandona antes de iniciar, la partida se cancela.
        GestorPartidas.finalizada(partida.id)
        {:stop, :normal, {:ok, :cancelada}, partida}

      true ->
        # Sección 6.5: termina de inmediato y se registra lo obtenido hasta ahora.
        {:stop, :normal, {:ok, :finalizada}, finalizar(partida, :abandono)}
    end
  end

  @impl true
  def handle_info(:abrir_ronda, partida) do
    if partida.estado == :en_curso and partida.ronda == nil do
      {:noreply, abrir_ronda(partida)}
    else
      {:noreply, partida}
    end
  end

  def handle_info({:vence_ronda, numero}, partida) do
    # Se ignora si ya no hay una ronda con ese número (por ejemplo, el
    # temporizador de una ronda que se cerró porque todos respondieron).
    if partida.ronda != nil and partida.ronda.numero == numero do
      cerrar_y_avanzar(partida)
    else
      {:noreply, partida}
    end
  end

  # El cliente del creador desapareció (sección 6.5 y 8.2).
  def handle_info(:cliente_caido, partida) do
    if partida.estado == :en_curso do
      {:stop, :normal, finalizar(partida, :abandono)}
    else
      GestorPartidas.finalizada(partida.id)
      {:stop, :normal, partida}
    end
  end

  def handle_info(_otro, partida), do: {:noreply, partida}

  # Cuando la partida termina bien, se le avisa a sus bots para que también terminen.
  @impl true
  def terminate(_razon, partida) do
    Enum.each(partida.jugadores, fn jugador ->
      if jugador.tipo == :bot do
        send(jugador.pid, :terminar)
      end
    end)
  end

  # ── Funciones privadas ───────────────────────────────────────────────

  defp todos_respondieron?(partida) do
    map_size(partida.ronda.respuestas) == length(partida.jugadores)
  end

  # Abre la ronda siguiente y envía la pregunta a todos los jugadores.
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

  defp enviar_pregunta(partida) do
    pregunta = partida.ronda.pregunta

    info = %{
      numero: partida.ronda.numero,
      total: partida.total_preguntas,
      tema: partida.tema,
      nivel: pregunta.nivel,
      enunciado: pregunta.enunciado,
      opciones: pregunta.opciones,
      tiempo: partida.tiempo_pregunta
    }

    Enum.each(partida.jugadores, fn jugador ->
      if jugador.tipo == :bot do
        send(jugador.pid, {:trivia, {:pregunta, Map.put(info, :correcta, pregunta.respuesta)}})
      else
        send(jugador.pid, {:trivia, {:pregunta, info}})
      end
    end)
  end

  # Cierra la ronda, anuncia el resultado y decide si sigue otra ronda o termina.
  # Devuelve lo que necesita handle_info: {:noreply, partida} o {:stop, :normal, partida}.
  defp cerrar_y_avanzar(partida) do
    ronda = partida.ronda
    Process.cancel_timer(ronda.temporizador)
    {filas, nueva_partida} = cerrar_ronda(partida)
    correcta = ronda.pregunta.respuesta
    {_letra, texto} = List.keyfind(ronda.pregunta.opciones, correcta, 0)

    notificar(
      nueva_partida,
      {:cierre_ronda, %{numero: ronda.numero, correcta: correcta, texto: texto, resultados: filas}}
    )

    if ronda.numero >= nueva_partida.total_preguntas do
      {:stop, :normal, finalizar(nueva_partida, :completa)}
    else
      # Durante la pausa de 3 segundos no hay ronda abierta.
      Process.send_after(self(), :abrir_ronda, @pausa_ms)
      {:noreply, nueva_partida}
    end
  end

  # Anuncia el ranking final y guarda el resultado en el historial.
  defp finalizar(partida, motivo) do
    terminada = %{partida | estado: :finalizada}

    # Orden estable: si hay empate se conserva el orden de ingreso a la partida.
    ranking =
      terminada.jugadores
      |> Enum.map(fn jugador -> {jugador.nombre, Map.get(terminada.puntajes, jugador.nombre)} end)
      |> Enum.sort_by(fn {_nombre, puntos} -> -puntos end)

    {_lider, mayor} = hd(ranking)
    ganadores = for {nombre, puntos} <- ranking, puntos == mayor, do: nombre

    fecha = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    case Persistencia.agregar_resultado(linea_resultado(terminada, ganadores, fecha)) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se pudo guardar el resultado: #{inspect(razon)}")
    end

    # El jugador queda libre para crear otra partida.
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

  # Envía un evento a todos los jugadores de la partida.
  defp notificar(partida, evento) do
    Enum.each(partida.jugadores, fn jugador ->
      send(jugador.pid, {:trivia, evento})
    end)
  end
end
