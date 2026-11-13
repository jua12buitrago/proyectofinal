defmodule Trivia.BancoPreguntasTest do
  @moduledoc """
  Prueba 2: sorteo de preguntas (secciones 6.1 y 9).
  """
  use ExUnit.Case, async: true

  alias Trivia.{BancoPreguntas, Errores}

  # Crea una pregunta de prueba con un enunciado distinto para cada una.
  defp pregunta(tema, nivel, numero) do
    %{
      tema: tema,
      nivel: nivel,
      enunciado: "Pregunta #{tema} #{nivel} #{numero}",
      opciones: [{"A", "uno"}, {"B", "dos"}, {"C", "tres"}, {"D", "cuatro"}],
      respuesta: "A"
    }
  end

  # Banco con 12 preguntas de cada nivel en ciencia y 12 de básicas en historia.
  defp banco do
    ciencia =
      for nivel <- [:basico, :intermedio, :avanzado],
          n <- 1..12,
          do: pregunta("ciencia", nivel, n)

    historia = for n <- 1..12, do: pregunta("historia", :basico, n)
    ciencia ++ historia
  end

  defp indice(:basico), do: 1
  defp indice(:intermedio), do: 2
  defp indice(:avanzado), do: 3

  describe "prueba 2: sorteo" do
    test "devuelve la cantidad pedida, del tema pedido y sin repetir" do
      {:ok, preguntas} = BancoPreguntas.sortear_en(banco(), "ciencia", :basico, 10)

      assert length(preguntas) == 10
      assert Enum.all?(preguntas, &(&1.tema == "ciencia"))

      enunciados = Enum.map(preguntas, & &1.enunciado)
      assert length(Enum.uniq(enunciados)) == 10
    end

    test "respeta el reparto por nivel del jugador según la cantidad solicitada" do
      casos = [
        {:basico, 10, %{basico: 7, intermedio: 3}},
        {:intermedio, 10, %{basico: 2, intermedio: 6, avanzado: 2}},
        {:avanzado, 10, %{intermedio: 3, avanzado: 7}},
        {:basico, 5, %{basico: 4, intermedio: 1}}
      ]

      for {nivel, cantidad, esperado} <- casos do
        {:ok, preguntas} = BancoPreguntas.sortear_en(banco(), "ciencia", nivel, cantidad)
        assert Enum.frequencies_by(preguntas, & &1.nivel) == esperado
      end
    end

    test "las entrega ordenadas de menor a mayor nivel" do
      {:ok, preguntas} = BancoPreguntas.sortear_en(banco(), "ciencia", :intermedio, 10)
      indices = Enum.map(preguntas, &indice(&1.nivel))
      assert indices == Enum.sort(indices)
    end

    test "dos sorteos del mismo tema pueden dar preguntas distintas" do
      sorteos =
        for _vez <- 1..10 do
          {:ok, preguntas} = BancoPreguntas.sortear_en(banco(), "ciencia", :basico, 5)
          Enum.map(preguntas, & &1.enunciado)
        end

      assert length(Enum.uniq(sorteos)) > 1
    end

    test "rechaza un tema que no existe" do
      assert {:error, %Errores.TemaInexistente{tema: "cine"}} =
               BancoPreguntas.sortear_en(banco(), "cine", :basico, 5)
    end

    test "rechaza un tema sin preguntas suficientes de algún nivel" do
      assert {:error, %Errores.PreguntasInsuficientes{nivel: :intermedio}} =
               BancoPreguntas.sortear_en(banco(), "historia", :basico, 10)
    end
  end

  describe "archivo semilla data/questions.json" do
    test "tiene al menos 4 temas con 8 preguntas de cada nivel" do
      banco_real =
        Path.expand("../data/questions.json", __DIR__)
        |> File.read!()
        |> Jason.decode!()
        |> Enum.map(&BancoPreguntas.convertir/1)

      temas = banco_real |> Enum.map(& &1.tema) |> Enum.uniq()
      assert length(temas) >= 4

      for tema <- temas, nivel <- [:basico, :intermedio, :avanzado] do
        cantidad = Enum.count(banco_real, &(&1.tema == tema and &1.nivel == nivel))
        assert cantidad >= 8, "#{tema} tiene solo #{cantidad} preguntas de nivel #{nivel}"
      end
    end
  end
end
