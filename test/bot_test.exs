defmodule Trivia.BotTest do
  @moduledoc """
  Prueba 6: decisión de un bot (sección 6.6).
  """
  use ExUnit.Case, async: true

  alias Trivia.Bot

  @letras ["A", "B", "C", "D"]

  describe "prueba 6: decisión de un bot" do
    test "devuelve una de las cuatro letras" do
      for _ <- 1..50 do
        {letra, _retardo} = Bot.decidir(:facil, :basico, "C", 15)
        assert letra in @letras
      end
    end

    test "el retardo respeta los porcentajes de dificultad y se ajusta al tiempo total" do
      casos = [
        # {dificultad, nivel, correcta, tiempo, rango_ms_esperado}
        {:facil, :basico, "B", 15, 6_000..13_500},
        {:dificil, :avanzado, "D", 15, 1_500..6_000},
        {:dificil, :basico, "A", 30, 3_000..12_000}
      ]

      for {dificultad, nivel, correcta, tiempo, rango} <- casos do
        for _ <- 1..100 do
          {_letra, retardo} = Bot.decidir(dificultad, nivel, correcta, tiempo)
          assert retardo in rango
        end
      end
    end

    test "cuando falla escoge una de las tres opciones incorrectas" do
      letras = for _ <- 1..200, do: elem(Bot.decidir(:facil, :avanzado, "A", 15), 0)

      assert Enum.all?(letras, &(&1 in @letras))
      assert Enum.any?(letras, &(&1 != "A"))
    end

    test "el bot difícil acierta mucho más que el fácil en preguntas básicas" do
      aciertos_facil = Enum.count(1..2000, fn _ -> match?({"A", _}, Bot.decidir(:facil, :basico, "A", 15)) end)
      aciertos_dificil = Enum.count(1..2000, fn _ -> match?({"A", _}, Bot.decidir(:dificil, :basico, "A", 15)) end)

      assert aciertos_facil in 600..1000
      assert aciertos_dificil in 1400..1800
      assert aciertos_dificil > aciertos_facil
    end
  end
end
