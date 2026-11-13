defmodule Trivia.Persistencia do
  @moduledoc """

  Único proceso del servidor que toca el sistema de archivos (secciones 7, 8.1

  y 9).



  Como todas las lecturas y escrituras pasan por este GenServer, dos partidas

  que terminan al mismo tiempo, o dos jugadores que se registran a la vez, no

  mezclan sus escrituras sobre `users.json` o `results.log`.



  Archivos (dentro de la carpeta `data/`):

  - `users.json`: lista de objetos con `usuario` y `clave`

  - `questions.json`: banco de preguntas

  - `results.log`: una línea de texto por partida terminada



  - autor: Juan Manuel Castaño Buitrago

  - fecha: Noviembre del 2026

  """

  use GenServer

  # Carpeta data/ del proyecto, calculada a partir de este archivo.

  @carpeta Path.expand("../../data", __DIR__)

  # ── API pública ──────────────────────────────────────────────────────

  def start_link(opciones \\ []) do
    GenServer.start_link(__MODULE__, opciones, name: __MODULE__)
  end

  @doc "Mapa con los usuarios registrados: `%{usuario => clave}`."

  def usuarios, do: GenServer.call(__MODULE__, :usuarios)

  @doc "Guarda un usuario nuevo en users.json."

  def guardar_usuario(usuario, clave) do
    GenServer.call(__MODULE__, {:guardar_usuario, usuario, clave})
  end

  @doc "Lista de preguntas tal como están en questions.json."

  def preguntas, do: GenServer.call(__MODULE__, :preguntas)

  @doc "Agrega una línea al final de results.log."

  def agregar_resultado(linea) do
    GenServer.call(__MODULE__, {:agregar_resultado, linea})
  end

  @doc "Lista de líneas del historial (results.log)."

  def historial, do: GenServer.call(__MODULE__, :historial)

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

    File.write!(Path.join(carpeta, "users.json"), Jason.encode!(lista, pretty: true))

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
    resultado = File.write(Path.join(carpeta, "results.log"), linea <> "\n", [:append])

    {:reply, resultado, carpeta}
  end

  def handle_call(:historial, _from, carpeta) do
    ruta = Path.join(carpeta, "results.log")

    lineas =
      if File.exists?(ruta) do
        ruta
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(fn linea -> linea == "" end)
        |> Enum.to_list()
      else
        []
      end

    {:reply, lineas, carpeta}
  end

  # ── Funciones privadas ───────────────────────────────────────────────

  # Si users.json todavía no existe, no hay usuarios registrados.

  defp leer_usuarios(carpeta) do
    ruta = Path.join(carpeta, "users.json")

    if File.exists?(ruta) do
      ruta
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(fn u -> {u["usuario"], u["clave"]} end)
      |> Map.new()
    else
      %{}
    end
  end
end
