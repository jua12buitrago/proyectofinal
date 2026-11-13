defmodule Trivia.PartidaTest do
  @moduledoc """
  Prueba 1: puntaje de una ronda (sección 6.4).
  Prueba 3: validación de respuestas (sección 6.3).
  Prueba 4: reglas para armar una partida (sección 5).
  """
  use ExUnit.Case, async: true

  alias Trivia.{Errores, Partida}

  # Partida recién creada, solo con el creador.
  defp partida_nueva do
    Partida.nueva(%{
      id: "P-1001",
      creador: "pedro",
      cliente_pid: self(),
      tema: "ciencia",
      nivel: :basico,
      total_preguntas: 5,
      tiempo_pregunta: 15
    })
  end

  # Agrega bots a la partida sin crear procesos (solo para probar las reglas).
  defp con_bots(partida, cantidad) do
    bots = Enum.map(1..cantidad//1, &%{nombre: "bot_#{&1}", tipo: :bot, pid: self()})

    puntajes = Enum.reduce(bots, partida.puntajes, &Map.put(&2, &1.nombre, 0))

    %{partida | jugadores: partida.jugadores ++ bots, puntajes: puntajes}
  end

  # Partida en curso con la ronda 1 abierta (empezó en t=0 y vence en t=15000 ms).
  defp con_ronda_abierta do
    pregunta = %{
      tema: "ciencia",
      nivel: :basico,
      enunciado: "¿Cuál es el planeta más grande del sistema solar?",
      opciones: [{"A", "Marte"}, {"B", "Júpiter"}, {"C", "Saturno"}, {"D", "Neptuno"}],
      respuesta: "B"
    }

    ronda = %{
      numero: 1,
      pregunta: pregunta,
      inicio_ms: 0,
      limite_ms: 15_000,
      respuestas: %{},
      temporizador: nil
    }

    %{con_bots(partida_nueva(), 2) | estado: :en_curso, ronda: ronda, preguntas: [pregunta]}
  end

  describe "prueba 1: puntaje de una ronda" do
    test "respuesta correcta en los tres niveles, con distintas bonificaciones" do
      casos = [
        {:basico, 14, 15, 14},
        {:basico, 11, 15, 13},
        {:basico, 6, 15, 12},
        {:basico, 1, 15, 10},
        {:intermedio, 14, 15, 19},
        {:avanzado, 14, 15, 24},
        {:avanzado, 1, 15, 20}
      ]

      for {nivel, tiempo_restante, tiempo_pregunta, esperado} <- casos do
        assert Partida.calcular_puntaje(nivel, :correcta, tiempo_restante, tiempo_pregunta) == esperado
      end
    end

    test "la bonificación va de 0 a 5 y usa el tiempo de la pregunta base" do
      casos = [
        {:basico, 15, 15, 15},
        {:intermedio, 0, 15, 15},
        {:avanzado, 15, 15, 25},
        {:basico, 15, 30, 12},
        {:basico, 29, 30, 14},
        {:intermedio, 29, 30, 19}
      ]

      for {nivel, tiempo_restante, tiempo_pregunta, esperado} <- casos do
        assert Partida.calcular_puntaje(nivel, :correcta, tiempo_restante, tiempo_pregunta) == esperado
      end
    end

    test "respuesta incorrecta resta según el nivel y sin responder vale 0" do
      casos = [
        {:basico, :incorrecta, -5},
        {:intermedio, :incorrecta, -8},
        {:avanzado, :incorrecta, -10},
        {:basico, :sin_responder, 0},
        {:intermedio, :sin_responder, 0},
        {:avanzado, :sin_responder, 0}
      ]

      for {nivel, estado, esperado} <- casos do
        assert Partida.calcular_puntaje(nivel, estado, 14, 15) == esperado
      end
    end

    test "al cerrar la ronda se puntúa a cada jugador y se acumula" do
      partida =
        con_ronda_abierta()
        |> Partida.registrar_respuesta("bot_1", "B", 3_000)
        |> elem(2)
        |> Partida.registrar_respuesta("bot_2", "A", 9_000)
        |> elem(2)

      {filas, cerrada} = Partida.cerrar_ronda(partida)

      assert cerrada.ronda == nil
      assert cerrada.pregunta_actual == 1
      assert cerrada.puntajes == %{"pedro" => 0, "bot_1" => 14, "bot_2" => -5}
      assert Enum.map(filas, &(&1.jugador)) == ["bot_1", "pedro", "bot_2"]
    end
  end

  describe "prueba 3: validación de respuestas" do
    test "acepta la primera respuesta (incluso en minúscula) y rechaza las demás" do
      {:ok, :registrada, primera} = Partida.registrar_respuesta(con_ronda_abierta(), "pedro", "b", 4_000)
      assert primera.ronda.respuestas["pedro"] == %{letra: "B", restantes_ms: 11_000}

      assert {:ok, :ignorada, segunda} = Partida.registrar_respuesta(primera, "pedro", "C", 6_000)
      assert segunda.ronda.respuestas["pedro"] == primera.ronda.respuestas["pedro"]
    end

    test "rechaza respuestas con letras inválidas o cuando no hay ronda abierta" do
      partida = con_ronda_abierta()
      en_pausa = %{partida | ronda: nil}

      assert {:error, %Errores.LetraInvalida{letra: "E"}} = Partida.registrar_respuesta(partida, "pedro", "E", 2_000)
      assert {:error, %Errores.LetraInvalida{}} = Partida.registrar_respuesta(partida, "pedro", "AB", 2_000)

      assert {:error, %Errores.SinRondaAbierta{}} = Partida.registrar_respuesta(en_pausa, "pedro", "B", 16_000)
      assert {:error, %Errores.SinRondaAbierta{}} = Partida.registrar_respuesta(partida_nueva(), "pedro", "B", 0)
    end
  end

  describe "prueba 4: armado de la partida" do
    test "validaciones al agregar bots y al iniciar partida" do
      llena = con_bots(partida_nueva(), 3)
      iniciada = %{con_bots(partida_nueva(), 2) | estado: :en_curso}

      # Agregar bots
      assert :ok = Partida.validar_agregar_bot(partida_nueva(), :facil)
      assert {:error, %Errores.PartidaLlena{}} = Partida.validar_agregar_bot(llena, :facil)
      assert {:error, %Errores.PartidaYaIniciada{}} = Partida.validar_agregar_bot(iniciada, :dificil)
      assert {:error, %Errores.DificultadInvalida{}} = Partida.validar_agregar_bot(partida_nueva(), :imposible)

      # Iniciar partida
      assert :ok = Partida.validar_inicio(con_bots(partida_nueva(), 2))
      assert {:error, %Errores.BotsInsuficientes{bots: 1}} = Partida.validar_inicio(con_bots(partida_nueva(), 1))
      assert {:error, %Errores.PartidaYaIniciada{}} = Partida.validar_inicio(iniciada)
    end
  end

  describe "línea del historial" do
    test "tiene el formato fecha|id|tema|nivel|ganadores|puntajes sin letra Z" do
      partida = %{con_bots(partida_nueva(), 2) | puntajes: %{"pedro" => 48, "bot_1" => 22, "bot_2" => -11}}
      linea = Partida.linea_resultado(partida, ["pedro"], "2026-11-10T10:00:00")

      assert linea == "2026-11-10T10:00:00|P-1001|ciencia|basico|pedro|pedro=48,bot_1=22,bot_2=-11"
    end
  end
end
