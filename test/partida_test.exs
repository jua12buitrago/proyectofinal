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
    bots =
      Enum.map(1..cantidad//1, fn n ->
        %{nombre: "bot_#{n}", tipo: :bot, pid: self()}
      end)

    puntajes =
      Enum.reduce(bots, partida.puntajes, fn bot, acumulado ->
        Map.put(acumulado, bot.nombre, 0)
      end)

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

    partida = con_bots(partida_nueva(), 2)
    %{partida | estado: :en_curso, ronda: ronda, preguntas: [pregunta]}
  end

  describe "prueba 1: puntaje de una ronda" do
    test "respuesta correcta en los tres niveles, con distintas bonificaciones" do
      # tiempo_pregunta = 15: 14 s restantes -> 4, 11 -> 3, 6 -> 2, 1 -> 0
      assert Partida.calcular_puntaje(:basico, :correcta, 14, 15) == 14
      assert Partida.calcular_puntaje(:basico, :correcta, 11, 15) == 13
      assert Partida.calcular_puntaje(:basico, :correcta, 6, 15) == 12
      assert Partida.calcular_puntaje(:basico, :correcta, 1, 15) == 10

      assert Partida.calcular_puntaje(:intermedio, :correcta, 14, 15) == 19
      assert Partida.calcular_puntaje(:avanzado, :correcta, 14, 15) == 24
      assert Partida.calcular_puntaje(:avanzado, :correcta, 1, 15) == 20
    end

    test "la bonificación va de 0 a 5 sin importar el nivel" do
      assert Partida.calcular_puntaje(:basico, :correcta, 15, 15) == 15
      assert Partida.calcular_puntaje(:intermedio, :correcta, 0, 15) == 15
      assert Partida.calcular_puntaje(:avanzado, :correcta, 15, 15) == 25
    end

    test "la bonificación usa el tiempo de la pregunta (30 segundos)" do
      # Con 30 s, tener 15 s restantes equivale a tener 7,5 s con 15 s
      assert Partida.calcular_puntaje(:basico, :correcta, 15, 30) == 12
      assert Partida.calcular_puntaje(:basico, :correcta, 29, 30) == 14
      assert Partida.calcular_puntaje(:intermedio, :correcta, 29, 30) == 19
    end

    test "respuesta incorrecta resta según el nivel, sin bonificación" do
      assert Partida.calcular_puntaje(:basico, :incorrecta, 14, 15) == -5
      assert Partida.calcular_puntaje(:intermedio, :incorrecta, 14, 15) == -8
      assert Partida.calcular_puntaje(:avanzado, :incorrecta, 14, 15) == -10
    end

    test "sin responder vale 0 en los tres niveles" do
      assert Partida.calcular_puntaje(:basico, :sin_responder, 0, 15) == 0
      assert Partida.calcular_puntaje(:intermedio, :sin_responder, 0, 15) == 0
      assert Partida.calcular_puntaje(:avanzado, :sin_responder, 0, 15) == 0
    end

    test "al cerrar la ronda se puntúa a cada jugador y se acumula" do
      # bot_1 acierta a los 3 s (12 s restantes), bot_2 falla y pedro no responde
      {:ok, :registrada, partida} =
        Partida.registrar_respuesta(con_ronda_abierta(), "bot_1", "B", 3_000)

      {:ok, :registrada, partida} = Partida.registrar_respuesta(partida, "bot_2", "A", 9_000)

      {filas, cerrada} = Partida.cerrar_ronda(partida)

      assert cerrada.ronda == nil
      assert cerrada.pregunta_actual == 1
      assert cerrada.puntajes == %{"pedro" => 0, "bot_1" => 14, "bot_2" => -5}
      assert Enum.map(filas, fn fila -> fila.jugador end) == ["bot_1", "pedro", "bot_2"]
    end
  end

  describe "prueba 3: validación de respuestas" do
    test "acepta la primera respuesta de cada jugador" do
      assert {:ok, :registrada, partida} =
               Partida.registrar_respuesta(con_ronda_abierta(), "pedro", "B", 4_000)

      assert partida.ronda.respuestas["pedro"] == %{letra: "B", restantes_ms: 11_000}
    end

    test "acepta la letra en minúscula" do
      assert {:ok, :registrada, partida} =
               Partida.registrar_respuesta(con_ronda_abierta(), "pedro", "b", 1_000)

      assert partida.ronda.respuestas["pedro"].letra == "B"
    end

    test "ignora las respuestas siguientes sin cambiar la primera" do
      {:ok, :registrada, primera} =
        Partida.registrar_respuesta(con_ronda_abierta(), "pedro", "B", 4_000)

      assert {:ok, :ignorada, segunda} = Partida.registrar_respuesta(primera, "pedro", "C", 6_000)
      assert segunda.ronda.respuestas["pedro"] == primera.ronda.respuestas["pedro"]
    end

    test "rechaza una letra inválida y no consume la respuesta" do
      partida = con_ronda_abierta()

      assert {:error, %Errores.LetraInvalida{letra: "E"}} =
               Partida.registrar_respuesta(partida, "pedro", "E", 2_000)

      assert {:error, %Errores.LetraInvalida{}} =
               Partida.registrar_respuesta(partida, "pedro", "AB", 2_000)

      # La partida no cambió, así que la corrección posterior sí cuenta.
      assert {:ok, :registrada, _} = Partida.registrar_respuesta(partida, "pedro", "A", 6_000)
    end

    test "rechaza la respuesta cuando no hay ronda abierta" do
      en_pausa = %{con_ronda_abierta() | ronda: nil}

      assert {:error, %Errores.SinRondaAbierta{}} =
               Partida.registrar_respuesta(en_pausa, "pedro", "B", 16_000)

      assert {:error, %Errores.SinRondaAbierta{}} =
               Partida.registrar_respuesta(partida_nueva(), "pedro", "B", 0)
    end
  end

  describe "prueba 4: armado de la partida" do
    test "rechaza add_bot con la partida llena" do
      llena = con_bots(partida_nueva(), 3)
      assert length(llena.jugadores) == 4

      assert {:error, %Errores.PartidaLlena{id: "P-1001"}} =
               Partida.validar_agregar_bot(llena, :facil)
    end

    test "rechaza add_bot con la partida ya iniciada" do
      iniciada = %{con_bots(partida_nueva(), 2) | estado: :en_curso}

      assert {:error, %Errores.PartidaYaIniciada{}} =
               Partida.validar_agregar_bot(iniciada, :dificil)
    end

    test "acepta add_bot en una partida en espera con cupo" do
      assert :ok = Partida.validar_agregar_bot(partida_nueva(), :facil)
      assert :ok = Partida.validar_agregar_bot(con_bots(partida_nueva(), 2), :dificil)
    end

    test "rechaza una dificultad desconocida" do
      assert {:error, %Errores.DificultadInvalida{}} =
               Partida.validar_agregar_bot(partida_nueva(), :imposible)
    end

    test "rechaza start_game con menos de dos bots" do
      assert {:error, %Errores.BotsInsuficientes{bots: 0}} =
               Partida.validar_inicio(partida_nueva())

      assert {:error, %Errores.BotsInsuficientes{bots: 1}} =
               Partida.validar_inicio(con_bots(partida_nueva(), 1))
    end

    test "acepta start_game con dos o tres bots y rechaza iniciar dos veces" do
      assert :ok = Partida.validar_inicio(con_bots(partida_nueva(), 2))
      assert :ok = Partida.validar_inicio(con_bots(partida_nueva(), 3))

      iniciada = %{con_bots(partida_nueva(), 2) | estado: :en_curso}
      assert {:error, %Errores.PartidaYaIniciada{}} = Partida.validar_inicio(iniciada)
    end
  end

  describe "línea del historial" do
    test "tiene el formato fecha|id|tema|nivel|ganadores|puntajes" do
      partida = %{con_bots(partida_nueva(), 2) | puntajes: %{"pedro" => 48, "bot_1" => 22, "bot_2" => -11}}
      linea = Partida.linea_resultado(partida, ["pedro"], "2026-11-10T10:00:00Z")

      assert linea == "2026-11-10T10:00:00Z|P-1001|ciencia|basico|pedro|pedro=48,bot_1=22,bot_2=-11"
    end
  end
end
