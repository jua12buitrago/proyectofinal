defmodule Trivia.Persistencia do
  @moduledoc """
  Único proceso del servidor que toca el sistema de archivos (secciones 7, 8.1
  y 9).

  Como todas las lecturas y escrituras pasan por este GenServer, dos partidas
  que terminan al mismo tiempo, o dos jugadores que se registran a la vez, no
  mezclan sus escrituras sobre users.json o results.log.

  Archivos (dentro de la carpeta data/):
  - users.json: lista de objetos con usuario y clave
  - questions.json: banco de preguntas
  - results.log: una línea de texto por partida terminada

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use GenServer

  # Carpeta data/ del proyecto, calculada a partir de este archivo.
  @carpeta Path.expand("../../data", _DIR_)

  # ── API pública ──────────────────────────────────────────────────────

  def start_link(opciones \\ []), do: GenServer.start_link(_MODULE, opciones, name: __MODULE_)

  def usuarios, do: GenServer.call(_MODULE_, :usuarios)
  def guardar_usuario(usuario, clave), do: GenServer.call(_MODULE_, {:guardar_usuario, usuario, clave})
  def preguntas, do: GenServer.call(_MODULE_, :preguntas)
  def agregar_resultado(linea), do: GenServer.call(_MODULE_, {:agregar_resultado, linea})
  def historial, do: GenServer.call(_MODULE_, :historial)

  # ── Callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(opciones) do
    carpeta = Keyword.get(opciones, :carpeta, @carpeta)
    File.mkdir_p!(carpeta)
    {:ok, carpeta}
  end

  @impl true
  def handle_call(:usuarios, _from, carpeta) do
    {:reply, leer_usuarios(carpeta), carpeta}
  end

  def handle_call({:guardar_usuario, usuario, clave}, _from, carpeta) do
    usuarios = Map.put(leer_usuarios(carpeta), usuario, clave)
    lista = for {nombre, pass} <- usuarios, do: %{"usuario" => nombre, "clave" => pass}

    carpeta
    |> Path.join("users.json")
    |> File.write!(Jason.encode!(lista, pretty: true))

    {:reply, :ok, carpeta}
  end

  def handle_call(:preguntas, _from, carpeta) do
    preguntas =
      carpeta
      |> Path.join("questions.json")
      |> File.read!()
      |> Jason.decode!()

    {:reply, preguntas, carpeta}
  end

  def handle_call({:agregar_resultado, linea}, _from, carpeta) do
    resultado =
      carpeta
      |> Path.join("results.log")
      |> File.write(linea <> "\n", [:append])

    {:reply, resultado, carpeta}
  end

  def handle_call(:historial, _from, carpeta) do
    ruta = Path.join(carpeta, "results.log")

    case File.read(ruta) do
      {:ok, _contenido} ->
        lineas =
          ruta
          |> File.stream!()
          |> Stream.map(&String.trim/1)
          |> Stream.reject(&(&1 == ""))
          |> Enum.to_list()

        {:reply, lineas, carpeta}

      {:error, :enoent} ->
        {:reply, [], carpeta}
    end
  end

  # ── Funciones privadas ───────────────────────────────────────────────

  # Si users.json todavía no existe, no hay usuarios registrados.
  defp leer_usuarios(carpeta) do
    ruta = Path.join(carpeta, "users.json")

    case File.read(ruta) do
      {:ok, contenido} ->
        contenido
        |> Jason.decode!()
        |> Map.new(&{&1["usuario"], &1["clave"]})

      {:error, :enoent} ->
        %{}
    end
  end
end
