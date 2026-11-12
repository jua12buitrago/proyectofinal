defmodule Trivia.BancoPreguntas do
  @moduledoc """
  Banco de preguntas en memoria y sorteo por tema y nivel (secciones 3.2, 6.1
  y 8.1).

  Al arrancar pide a Trivia.Persistencia el contenido de data/questions.json
  y lo guarda en memoria. Cada pregunta es un mapa con las claves :tema,
  :nivel (átomo), :enunciado, :opciones (lista [{"A", texto}, ...]) y
  :respuesta (una de las letras A, B, C o D).

  Las funciones que terminan en _en son puras (reciben el banco como
  argumento) y son las que se prueban con ExUnit.

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use GenServer

  alias Trivia.{Errores, Nivel, Persistencia}

  # ── API pública ──────────────────────────────────────────────────────

  @doc "Arranca el banco. Con banco: lista usa esa lista en vez del archivo."
  def start_link(opciones \\ []) do
    GenServer.start_link(_MODULE, opciones, name: __MODULE_)
  end

  @doc "Revisa que el tema exista y tenga preguntas suficientes para el reparto."
  def verificar(tema, nivel, total) do
    GenServer.call(_MODULE_, {:verificar, tema, nivel, total})
  end

  @doc "Sortea las preguntas de una partida: {:ok, lista} o {:error, error}."
  def sortear(tema, nivel, total) do
    GenServer.call(_MODULE_, {:sortear, tema, nivel, total})
  end

  @doc "Lista de los temas del banco, en orden alfabético."
  def temas, do: GenServer.call(_MODULE_, :temas)

  # ── Funciones puras ──────────────────────────────────────────────────

  @doc "Convierte una pregunta leída del JSON en el formato interno."
  def convertir(cruda) do
    opciones = cruda["opciones"]

    %{
      tema: cruda["tema"] |> String.trim() |> String.downcase(),
      nivel: Nivel.de_texto(cruda["nivel"]),
      enunciado: cruda["enunciado"],
      opciones: [
        {"A", opciones["A"]},
        {"B", opciones["B"]},
        {"C", opciones["C"]},
        {"D", opciones["D"]}
      ],
      respuesta: cruda["respuesta"]
    }
  end

  @doc """
  Revisa sobre un banco dado que el tema exista y que tenga, de cada nivel,
  al menos las preguntas que pide el reparto.
  """
  def verificar_en(banco, tema, nivel, total) do
    del_tema = Enum.filter(banco, fn pregunta -> pregunta.tema == tema end)

    case del_tema do
      [] -> {:error, %Errores.TemaInexistente{tema: tema}}
      _ ->
        necesarias = Nivel.reparto(nivel, total)
        revisar_niveles(del_tema, tema, necesarias, Nivel.niveles())
    end
  end

  # Revisa los niveles uno por uno; se detiene en el primero que no alcanza.
  defp revisar_niveles(_del_tema, _tema, _necesarias, []), do: :ok

  defp revisar_niveles(del_tema, tema, necesarias, [nivel | resto]) do
    hay = Enum.count(del_tema, fn pregunta -> pregunta.nivel == nivel end)
    necesita = Map.get(necesarias, nivel)

    cond do
      hay < necesita ->
        {:error,
         %Errores.PreguntasInsuficientes{
           tema: tema,
           nivel: nivel,
           necesarias: necesita,
           disponibles: hay
         }}
      true ->
        revisar_niveles(del_tema, tema, necesarias, resto)
    end
  end

  @doc """
  Sortea sobre un banco dado las preguntas de una partida.

  Toma al azar, sin repetir, la cantidad de cada nivel que indica el reparto y
  las entrega ordenadas de menor a mayor nivel.
  """
  def sortear_en(banco, tema, nivel, total) do
    with :ok <- verificar_en(banco, tema, nivel, total) do
      reparto = Nivel.reparto(nivel, total)

      preguntas =
        for nivel_actual <- Nivel.niveles(),
            cantidad = Map.get(reparto, nivel_actual),
            cantidad > 0,
            reduce: [] do
          acc ->
            seleccionadas =
              banco
              |> Enum.filter(&(&1.tema == tema and &1.nivel == nivel_actual))
              |> Enum.shuffle()
              |> Enum.take(cantidad)

            acc ++ seleccionadas
        end

      {:ok, preguntas}
    end
  end

  # ── Callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(opciones) do
    case Keyword.get(opciones, :banco) do
      nil -> {:ok, cargar_banco()}
      banco -> {:ok, banco}
    end
  end

  @impl true
  def handle_call({:verificar, tema, nivel, total}, _from, banco) do
    {:reply, verificar_en(banco, tema, nivel, total), banco}
  end

  def handle_call({:sortear, tema, nivel, total}, _from, banco) do
    {:reply, sortear_en(banco, tema, nivel, total), banco}
  end

  def handle_call(:temas, _from, banco) do
    temas =
      banco
      |> Enum.map(&(&1.tema))
      |> Enum.uniq()
      |> Enum.sort()

    {:reply, temas, banco}
  end

  # ── Funciones privadas ───────────────────────────────────────────────

  defp cargar_banco do
    Persistencia.preguntas()
    |> Enum.filter(&valida?/1)
    |> Enum.map(&convertir/1)
  end

  # Una pregunta sirve si tiene opciones, un nivel conocido y una letra de respuesta válida.
  defp valida?(cruda) do
    is_map(cruda["opciones"]) and Nivel.de_texto(cruda["nivel"]) != nil and
      cruda["respuesta"] in ["A", "B", "C", "D"]
  end
end
