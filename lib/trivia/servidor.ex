defmodule Trivia.Servidor do
  @moduledoc """
  Proceso del servidor que recibe las peticiones de los clientes y las enruta
  (secciones 8.1 y 8.3).

  Está registrado con su nombre (Trivia.Servidor), de modo que el cliente lo
  ubica con {Trivia.Servidor, nodo} sin conocer su PID.

  Cada petición llega como {:peticion, pid_cliente, comando}. El
  pid_cliente es el proceso receptor del cliente y es lo que identifica su
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

  def start_link(_opciones \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

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

  defp procesar(cliente_pid, {:connect, usuario, clave}) do
    GestorJugadores.conectar(usuario, clave, cliente_pid)
  end

  defp procesar(cliente_pid, comando) do
    with {:ok, usuario} <- GestorJugadores.usuario_de(cliente_pid) do
      ejecutar(usuario, cliente_pid, comando)
    end
  end

  defp ejecutar(usuario, cliente_pid, :disconnect) do
    GestorJugadores.desconectar(cliente_pid)
    GestorPartidas.abandonar(usuario)
    {:ok, :desconectado}
  end

  defp ejecutar(usuario, cliente_pid, {:create_game, tema, preguntas, tiempo}),
    do: GestorPartidas.crear(usuario, cliente_pid, tema, preguntas, tiempo)

  defp ejecutar(usuario, _, {:add_bot, dificultad}), do: GestorPartidas.agregar_bot(usuario, dificultad)
  defp ejecutar(usuario, _, :start_game), do: GestorPartidas.iniciar(usuario)
  defp ejecutar(usuario, _, :leave_game), do: GestorPartidas.abandonar(usuario)
  defp ejecutar(usuario, _, {:answer, letra}), do: GestorPartidas.responder(usuario, letra)
  defp ejecutar(usuario, _, :score), do: {:ok, GestorJugadores.score(usuario)}
  defp ejecutar(_, _, {:ranking, nil}), do: {:ok, GestorJugadores.ranking(nil)}

  defp ejecutar(_, _, {:ranking, tema}) do
    tema_limpio = tema |> String.trim() |> String.downcase()

    if tema_limpio in BancoPreguntas.temas(),
      do: {:ok, GestorJugadores.ranking(tema_limpio)},
      else: {:error, %Errores.TemaInexistente{tema: tema_limpio}}
  end

  defp ejecutar(_, _, comando) do
    {:error, %Errores.ComandoInvalido{detalle: "Comando desconocido: #{inspect(comando)}"}}
  end
end
