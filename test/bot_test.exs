defmodule Trivia.BotTest do
  @moduledoc """
  Prueba 6: decisión de un bot (sección 6.6).
  """
  use ExUnit.Case, async: true

  alias Trivia.Bot

  @letras ["A", "B", "C", "D"]

  describe "prueba 6: decisión de un bot" do
    test "devuelve una de las cuatro letras" do
      for _vez <- 1..50 do
        {letra, _retardo} = Bot.decidir(:facil, :basico, "C", 15)
        assert letra in @letras
      end
    end

    test "el bot fácil responde entre el 40 % y el 90 % del tiempo" do
      # Con 15 s: entre 6 000 y 13 500 ms
      for _vez <- 1..100 do
        {_letra, retardo} = Bot.decidir(:facil, :basico, "B", 15)
        assert retardo in 6_000..13_500
      end
    end

    test "el bot difícil responde entre el 10 % y el 40 % del tiempo" do
      # Con 15 s: entre 1 500 y 6 000 ms
      for _vez <- 1..100 do
        {_letra, retardo} = Bot.decidir(:dificil, :avanzado, "D", 15)
        assert retardo in 1_500..6_000
      end
    end

    test "el retardo se ajusta al tiempo de la pregunta" do
      for _vez <- 1..100 do
        {_letra, retardo} = Bot.decidir(:dificil, :basico, "A", 30)
        assert retardo in 3_000..12_000
      end
    end

    test "cuando falla escoge una de las tres opciones incorrectas" do
      # Si acertara siempre o fallara siempre, la letra no variaría. Con muchas
      # decisiones se ve que nunca devuelve algo fuera de A-D.
      letras = for _vez <- 1..200, do: elem(Bot.decidir(:facil, :avanzado, "A", 15), 0)
      assert Enum.all?(letras, fn letra -> letra in @letras end)
      # El bot fácil falla casi siempre en avanzada (acierta el 20 %).
      assert Enum.any?(letras, fn letra -> letra != "A" end)
    end

    test "el bot difícil acierta mucho más que el fácil en preguntas básicas" do
      aciertos_facil = Enum.count(1..2000, fn _ -> elem(Bot.decidir(:facil, :basico, "A", 15), 0) == "A" end)
      aciertos_dificil = Enum.count(1..2000, fn _ -> elem(Bot.decidir(:dificil, :basico, "A", 15), 0) == "A" end)

      # Esperado: 40 % (800) contra 80 % (1600). Se dejan márgenes amplios.
      assert aciertos_facil in 600..1000
      assert aciertos_dificil in 1400..1800
      assert aciertos_dificil > aciertos_facil
    end
  end
end
