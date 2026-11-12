defmodule Trivia.GestorPartidas do
  @moduledoc """
  Creación, ubicación y aviso de reinicio de las partidas (secciones 5, 8.4 y
  8.5).

  Lleva la cuenta de qué partida está jugando cada usuario y cuál es el PID
  actual de cada partida. Ese PID cambia cuando el supervisor reinicia una
  partida, así que la partida, al arrancar, le reporta su id y su PID con un
  cast (un call desde init dejaría bloqueado al gestor, que está
  esperando a que el supervisor termine de arrancarla). Si el gestor ya tenía
  ese id con otro PID, sabe que fue un reinicio: guarda el PID nuevo y le
  avisa al creador.

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use GenServer

  alias Trivia.{BancoPreguntas, Errores, GestorJugadores, Partida, SupervisorPartidas}

  # ── API pública ──────────────────────────────────────────────────────

  def start_link(_opciones \\ []) do
    GenServer.start_link(_MODULE, :ok, name: __MODULE_)
  end

  @doc """
  Crea una partida y deja al creador dentro de ella.

  Devuelve {:ok, %{id: _, nivel: _, tema: _, preguntas: _, tiempo: _}} o
  {:error, error}.
  """
  def crear(usuario, cliente_pid, tema, total_preguntas, tiempo_pregunta) do
    GenServer.call(_MODULE_, {:crear, usuario, cliente_pid, tema, total_preguntas, tiempo_pregunta})
  end

  @doc "PID de la partida en la que está el usuario: {:ok, pid} o {:error, error}."
  def ubicar(usuario), do: GenServer.call(_MODULE_, {:ubicar, usuario})

  @doc "Agrega un bot a la partida del usuario."
  def agregar_bot(usuario, dificultad) do
    with {:ok, pid} <- ubicar(usuario), do: Partida.agregar_bot(pid, dificultad)
  end

  @doc "Inicia la partida del usuario."
  def iniciar(usuario) do
    with {:ok, pid} <- ubicar(usuario), do: Partida.iniciar(pid)
  end

  @doc "Envía la respuesta del usuario a su partida."
  def responder(usuario, letra) do
    with {:ok, pid} <- ubicar(usuario), do: Partida.responder(pid, usuario, letra)
  end

  @doc "El usuario abandona su partida (leave_game o disconnect)."
  def abandonar(usuario) do
    with {:ok, pid} <- ubicar(usuario), do: Partida.abandonar(pid, usuario)
  end

  @doc "Reporte de una partida: su id y su PID actual (se envía con cast)."
  def reportar(id, pid), do: GenServer.cast(_MODULE_, {:reportar, id, pid})

  @doc "Aviso de que una partida terminó (se envía con cast)."
  def finalizada(id), do: GenServer.cast(_MODULE_, {:finalizada, id})

  @doc "Aviso de que el cliente de un usuario desapareció."
  def cliente_caido(usuario), do: GenServer.cast(_MODULE_, {:cliente_caido, usuario})

  @doc """
  Mata el proceso de la partida del usuario para comprobar el reinicio de la
  sección 8.5. Se ejecuta desde la consola del servidor.
  """
  def simular_falla(usuario) do
    with {:ok, pid} <- ubicar(usuario) do
      Process.exit(pid, :kill)
      :ok
    end
  end

  # ── Callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(:ok) do
    {:ok, %{partidas: %{}, por_usuario: %{}, contador: 1000}}
  end

  @impl true
  def handle_call({:crear, usuario, cliente_pid, tema, total, tiempo}, _from, %{contador: contador, partidas: partidas, por_usuario: por_usuario} = estado) do
    tema = tema |> String.trim() |> String.downcase()

    case preparar(estado, usuario, tema, total, tiempo) do
      {:ok, nivel} ->
        id = "P-#{contador + 1}"

        argumentos = %{
          id: id,
          creador: usuario,
          tema: tema,
          nivel: nivel,
          total_preguntas: total,
          tiempo_pregunta: tiempo,
          cliente_pid: cliente_pid
        }

        case SupervisorPartidas.iniciar_partida(argumentos) do
          {:ok, pid} ->
            entrada = %{pid: pid, creador: usuario, cliente_pid: cliente_pid}

            nuevo_estado = %{
              partidas: Map.put(partidas, id, entrada),
              por_usuario: Map.put(por_usuario, usuario, id),
              contador: contador + 1
            }

            respuesta = %{id: id, nivel: nivel, tema: tema, preguntas: total, tiempo: tiempo}
            {:reply, {:ok, respuesta}, nuevo_estado}

          {:error, razon} ->
            {:reply, {:error, %Errores.ErrorInterno{detalle: inspect(razon)}}, estado}
        end

      {:error, error} ->
        {:reply, {:error, error}, estado}
    end
  end

  def handle_call({:ubicar, usuario}, _from, %{por_usuario: por_usuario, partidas: partidas} = estado) do
    id = Map.get(por_usuario, usuario)

    case Map.get(partidas, id) do
      nil -> {:reply, {:error, %Errores.SinPartida{}}, estado}
      entrada -> {:reply, {:ok, entrada.pid}, estado}
    end
  end

  @impl true
  def handle_cast({:reportar, id, pid}, %{partidas: partidas} = estado) do
    case Map.get(partidas, id) do
      nil ->
        {:noreply, estado}

      %{pid: ^pid} ->
        {:noreply, estado}

      entrada ->
        send(entrada.cliente_pid, {:trivia, {:reinicio, id}})
        nueva_entrada = %{entrada | pid: pid}
        {:noreply, %{estado | partidas: Map.put(partidas, id, nueva_entrada)}}
    end
  end

  def handle_cast({:finalizada, id}, %{partidas: partidas, por_usuario: por_usuario} = estado) do
    case Map.get(partidas, id) do
      nil ->
        {:noreply, estado}

      entrada ->
        nuevo_estado = %{
          estado
          | partidas: Map.delete(partidas, id),
            por_usuario: Map.delete(por_usuario, entrada.creador)
        }

        {:noreply, nuevo_estado}
    end
  end

  def handle_cast({:cliente_caido, usuario}, %{partidas: partidas, por_usuario: por_usuario} = estado) do
    entrada = Map.get(partidas, Map.get(por_usuario, usuario))

    if entrada, do: send(entrada.pid, :cliente_caido)

    {:noreply, estado}
  end

  # ── Funciones privadas ───────────────────────────────────────────────

  defp preparar(estado, usuario, tema, total, tiempo) do
    with :ok <- verificar_libre(estado, usuario),
         :ok <- validar_numeros(total, tiempo),
         nivel = GestorJugadores.nivel_en_tema(usuario, tema),
         :ok <- BancoPreguntas.verificar(tema, nivel, total) do
      {:ok, nivel}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp verificar_libre(%{por_usuario: por_usuario, partidas: partidas}, usuario) do
    id = Map.get(por_usuario, usuario)

    case Map.get(partidas, id) do
      nil -> :ok
      entrada ->
        if Process.alive?(entrada.pid),
          do: {:error, %Errores.YaEnPartida{id: id}},
          else: :ok
    end
  end

  defp validar_numeros(total, tiempo) do
    if is_integer(total) and total > 0 and is_integer(tiempo) and tiempo > 0,
      do: :ok,
      else:
        {:error,
         %Errores.ArgumentosInvalidos{
           detalle: "preguntas y tiempo deben ser números enteros mayores que cero"
         }}
  end
end
