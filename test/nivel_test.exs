defmodule Trivia.NivelTest do
  @moduledoc """
  Prueba 7: nivel del jugador (sección 6.1).
  """
  use ExUnit.Case, async: true

  alias Trivia.Nivel

  # Historial de un jugador en ciencia con el puntaje total indicado.
  defp historial(puntaje) do
    ["2026-10-01T10:00:00|P-1001|ciencia|basico|pedro|pedro=#{puntaje},bot_1=0,bot_2=0"]
  end

  describe "prueba 7" do
    test "evaluación de los valores justo en los umbrales" do
      umbrales = [{59, :basico}, {60, :intermedio}, {179, :intermedio}, {180, :avanzado}]

      for {puntos, esperado} <- umbrales do
        assert Nivel.nivel_en_tema(historial(puntos), "pedro", "ciencia") == esperado
        assert Nivel.por_puntaje(puntos) == esperado
      end
    end

    test "un puntaje negativo es nivel básico" do
      assert Nivel.nivel_en_tema(historial(-40), "pedro", "ciencia") == :basico
    end

    test "un tema nunca jugado es básico" do
      assert Nivel.nivel_en_tema(historial(500), "pedro", "historia") == :basico
      assert Nivel.nivel_en_tema([], "pedro", "ciencia") == :basico
    end

    test "suma las partidas del tema, incluidas las negativas, y baja de nivel" do
      lineas = [
        "2026-10-01T10:00:00|P-1001|ciencia|basico|pedro|pedro=70,bot_1=0,bot_2=0",
        "2026-10-02T10:00:00|P-1002|ciencia|intermedio|bot_1|pedro=-20,bot_1=30,bot_2=0",
        "2026-10-03T10:00:00|P-1003|historia|basico|pedro|pedro=200,bot_1=0,bot_2=0"
      ]

      # ciencia: 70 - 20 = 50 -> básico (aunque el 70 solo ya era intermedio)
      assert Nivel.nivel_en_tema(lineas, "pedro", "ciencia") == :basico
      assert Nivel.nivel_en_tema(lineas, "pedro", "historia") == :avanzado
    end
  end

  describe "reparto por nivel" do
    test "ejemplos del enunciado y jugador intermedio" do
      casos = [
        {:basico, 5, %{basico: 4, intermedio: 1, avanzado: 0}},
        {:avanzado, 10, %{basico: 0, intermedio: 3, avanzado: 7}},
        {:intermedio, 10, %{basico: 2, intermedio: 6, avanzado: 2}},
        {:intermedio, 7, %{basico: 1, intermedio: 5, avanzado: 1}}
      ]

      for {nivel, total, esperado} <- casos do
        assert Nivel.reparto(nivel, total) == esperado
      end
    end

    test "siempre suma el total de preguntas" do
      for nivel <- Nivel.niveles(), total <- 1..20 do
        assert Nivel.reparto(nivel, total) |> Map.values() |> Enum.sum() == total
      end
    end
  end
end
