defmodule Trivia.GestorJugadoresTest do
  @moduledoc """
  Prueba 5: estadísticas calculadas desde el historial (secciones 4.2, 6.6 y 9).
  """
  use ExUnit.Case, async: true

  alias Trivia.GestorJugadores

  # Líneas de historial: fecha|id|tema|nivel|ganadores|puntajes
  # (Se retira la 'Z' de la fecha para coincidir con la actualización a hora local)
  @lineas [
    "2026-10-01T10:00:00|P-1001|ciencia|basico|pedro|pedro=48,bot_1=22,bot_2=-11",
    "2026-10-02T10:00:00|P-1002|historia|basico|bot_1|pedro=13,bot_1=30,bot_2=5",
    "2026-10-03T10:00:00|P-1003|ciencia|basico|ana|ana=60,pedro=-10,bot_1=40",
    "2026-10-04T10:00:00|P-1004|ciencia|basico|bot_2|ana=5,bot_2=50,bot_1=8"
  ]

  describe "prueba 5: estadísticas desde el historial" do
    test "calcula el puntaje acumulado por tema" do
      assert GestorJugadores.puntaje_por_tema(@lineas, "pedro") ==
               %{"ciencia" => 38, "historia" => 13}
    end

    test "calcula las partidas jugadas correctamente" do
      casos = [{"pedro", 3}, {"ana", 2}, {"nadie", 0}]

      for {jugador, esperado} <- casos do
        assert GestorJugadores.partidas_jugadas(@lineas, jugador) == esperado
      end
    end

    test "el puntaje negativo resta del acumulado" do
      lineas = ["2026-10-01T10:00:00|P-1001|ciencia|basico|bot_1|pedro=-15,bot_1=20,bot_2=0"]
      assert GestorJugadores.puntaje_por_tema(lineas, "pedro") == %{"ciencia" => -15}
    end

    test "las entradas de bots se ignoran en estadísticas globales" do
      assert GestorJugadores.puntaje_por_tema(@lineas, "bot_1") == %{}
      assert GestorJugadores.partidas_jugadas(@lineas, "bot_1") == 0

      jugadores = Enum.map(GestorJugadores.ranking_desde(@lineas, nil), &(&1.jugador))
      assert jugadores == ["ana", "pedro"]
    end

    test "una línea mal formada no rompe el cálculo" do
      lineas = ["esto no es una línea válida" | @lineas]
      assert GestorJugadores.partidas_jugadas(lineas, "pedro") == 3
    end
  end

  describe "ranking histórico" do
    test "global, de mayor a menor puntaje" do
      assert GestorJugadores.ranking_desde(@lineas, nil) == [
               %{jugador: "ana", puntaje: 65, partidas: 2},
               %{jugador: "pedro", puntaje: 51, partidas: 3}
             ]
    end

    test "filtrado por tema cuenta solo partidas de ese tema (o vacío si no hay)" do
      casos = [
        {"historia", [%{jugador: "pedro", puntaje: 13, partidas: 1}]},
        {"ciencia", [
          %{jugador: "ana", puntaje: 65, partidas: 2},
          %{jugador: "pedro", puntaje: 38, partidas: 2}
        ]},
        {"geografia", []}
      ]

      for {tema, esperado} <- casos do
        assert GestorJugadores.ranking_desde(@lineas, tema) == esperado
      end
    end
  end

  describe "nombres de bot" do
    test "es_bot? reconoce el prefijo reservado correctamente" do
      casos = [{"bot_1", true}, {"BOT_7", true}, {"pedro", false}, {"robot", false}]

      for {nombre, esperado} <- casos do
        assert GestorJugadores.es_bot?(nombre) == esperado
      end
    end
  end
end
