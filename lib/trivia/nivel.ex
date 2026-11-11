defmodule Trivia.Nivel do
  @moduledoc """
  Nivel del jugador y reparto de preguntas por nivel (sección 6.1).

  Todas las funciones son puras: el cálculo del nivel recibe las líneas del
  historial en lugar de abrir el archivo por su cuenta.

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """

  alias Trivia.GestorJugadores

  @niveles [:basico, :intermedio, :avanzado]

  @doc "Los niveles de menor a mayor."
  def niveles, do: @niveles

  @doc "Convierte un texto en nivel. Si no es un nivel válido devuelve `nil`."
  def de_texto("basico"), do: :basico
  def de_texto("intermedio"), do: :intermedio
  def de_texto("avanzado"), do: :avanzado
  def de_texto(_otro), do: nil

  @doc """
  Nivel que corresponde a un puntaje acumulado en un tema.

  Menos de 60 es básico, de 60 a 179 intermedio y 180 o más avanzado.
  """
  def por_puntaje(puntaje) when puntaje < 60, do: :basico
  def por_puntaje(puntaje) when puntaje < 180, do: :intermedio
  def por_puntaje(_puntaje), do: :avanzado

  @doc """
  Nivel de un usuario en un tema, calculado desde las líneas del historial.
  Un tema nunca jugado cuenta como 0 puntos, así que es básico.
  """
  def nivel_en_tema(lineas, usuario, tema) do
    puntajes = GestorJugadores.puntaje_por_tema(lineas, usuario)
    por_puntaje(Map.get(puntajes, tema, 0))
  end

  @doc """
  Cantidad de preguntas de cada nivel para una partida.

  Para los dos niveles distintos al del jugador la cantidad es
  `trunc(total * porcentaje / 100)`; las que sobran son del nivel del jugador.

  ## Ejemplos
      iex> Trivia.Nivel.reparto(:basico, 5)
      %{basico: 4, intermedio: 1, avanzado: 0}
      iex> Trivia.Nivel.reparto(:avanzado, 10)
      %{basico: 0, intermedio: 3, avanzado: 7}
  """
  def reparto(nivel, total) do
    {p_basico, p_intermedio, p_avanzado} = porcentajes(nivel)

    basico = div(total * p_basico, 100)
    intermedio = div(total * p_intermedio, 100)
    avanzado = div(total * p_avanzado, 100)
    sobran = total - basico - intermedio - avanzado

    case nivel do
      :basico -> %{basico: basico + sobran, intermedio: intermedio, avanzado: avanzado}
      :intermedio -> %{basico: basico, intermedio: intermedio + sobran, avanzado: avanzado}
      :avanzado -> %{basico: basico, intermedio: intermedio, avanzado: avanzado + sobran}
    end
  end

  # Porcentajes {básico, intermedio, avanzado} según el nivel del jugador.
  defp porcentajes(:basico), do: {70, 30, 0}
  defp porcentajes(:intermedio), do: {20, 60, 20}
  defp porcentajes(:avanzado), do: {0, 30, 70}
end
