defmodule Trivia.Servidor do
  @moduledoc """
  Proceso del servidor que recibe las peticiones de los clientes y las enruta
  (secciones 8.1 y 8.3).

  Está registrado con su nombre (`Trivia.Servidor`), de modo que el cliente lo
  ubica con `{Trivia.Servidor, nodo}` sin conocer su PID.

  Cada petición llega como `{:peticion, pid_cliente, comando}`. El
  `pid_cliente` es el proceso receptor del cliente y es lo que identifica su
  sesión. Cualquier falla al atender una petición se convierte en un error que
  se devuelve al cliente: el error de un jugador no tumba el servidor.

  Comandos que entiende:

      {:connect, usuario, clave}      :disconnect
      {:create_game, tema, preguntas, tiempo}
      {:add_bot, :facil | :dificil}   :start_game   :leave_game
      {:answer, letra}                :score   {:ranking, tema | nil}

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use GenServer
  require Logger

  alias Trivia.{BancoPreguntas, Errores, GestorJugadores, GestorPartidas}

  def start_link(_opciones \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    IO.puts("""

    ═══ Servidor Trivia ═══
    Nodo: #{node()}
    Esperando clientes. En otra consola ejecute:
      iex --sname <nombre> -S mix
      Trivia.Cliente.iniciar()
    """)

    {:ok, %{}}
  end

  @impl true
  def handle_call({:peticion, cliente_pid, comando}, _from, estado) do
    {:reply, resolver(cliente_pid, comando), estado}
  end

  def handle_call(_otro, _from, estado) do
    {:reply, {:error, %Errores.ComandoInvalido{detalle: "Petición desconocida."}}, estado}
  end

  # ── Procesamiento de peticiones ──────────────────────────────────────

  # Atiende la petición y garantiza que siempre haya una respuesta.
  defp resolver(cliente_pid, comando) do
    try do
      procesar(cliente_pid, comando)
    rescue
      excepcion ->
        Logger.error("Falla al atender #{inspect(comando)}: #{Exception.message(excepcion)}")
        {:error, %Errores.ErrorInterno{detalle: Exception.message(excepcion)}}
    catch
      :exit, razon ->
        Logger.error("Falla al atender #{inspect(comando)}: #{inspect(razon)}")
        {:error, %Errores.ErrorInterno{detalle: inspect(razon)}}
    end
  end

  # connect es el único comando que no exige haber iniciado sesión.
  defp procesar(cliente_pid, {:connect, usuario, clave}) do
    GestorJugadores.conectar(usuario, clave, cliente_pid)
  end

  defp procesar(cliente_pid, comando) do
    case GestorJugadores.usuario_de(cliente_pid) do
      {:ok, usuario} -> ejecutar(usuario, cliente_pid, comando)
      {:error, error} -> {:error, error}
    end
  end

  defp ejecutar(usuario, cliente_pid, :disconnect) do
    # Primero se cierra la sesión. Después, si el jugador está en una partida,
    # esta termina según la sección 6.5.
    GestorJugadores.desconectar(cliente_pid)
    GestorPartidas.abandonar(usuario)
    {:ok, :desconectado}
  end

  defp ejecutar(usuario, cliente_pid, {:create_game, tema, preguntas, tiempo}) do
    GestorPartidas.crear(usuario, cliente_pid, tema, preguntas, tiempo)
  end

  defp ejecutar(usuario, _cliente_pid, {:add_bot, dificultad}) do
    GestorPartidas.agregar_bot(usuario, dificultad)
  end

  defp ejecutar(usuario, _cliente_pid, :start_game), do: GestorPartidas.iniciar(usuario)

  defp ejecutar(usuario, _cliente_pid, :leave_game), do: GestorPartidas.abandonar(usuario)

  defp ejecutar(usuario, _cliente_pid, {:answer, letra}) do
    GestorPartidas.responder(usuario, letra)
  end

  defp ejecutar(usuario, _cliente_pid, :score), do: {:ok, GestorJugadores.score(usuario)}

  defp ejecutar(_usuario, _cliente_pid, {:ranking, nil}) do
    {:ok, GestorJugadores.ranking(nil)}
  end

  defp ejecutar(_usuario, _cliente_pid, {:ranking, tema}) do
    tema = tema |> String.trim() |> String.downcase()

    if tema in BancoPreguntas.temas() do
      {:ok, GestorJugadores.ranking(tema)}
    else
      {:error, %Errores.TemaInexistente{tema: tema}}
    end
  end

  defp ejecutar(_usuario, _cliente_pid, comando) do
    {:error, %Errores.ComandoInvalido{detalle: "Comando desconocido: #{inspect(comando)}"}}
  end
end
