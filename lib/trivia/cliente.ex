defmodule Trivia.Cliente do
  @moduledoc """
  Consola del jugador (secciones 8.2 y 8.3).

  El cliente no tiene lógica de juego: lee lo que escribe el jugador, lo
  traduce en una petición, se la envía al proceso `Trivia.Servidor` del nodo
  central y muestra lo que llega de vuelta. Tampoco toca archivos: todo lo que
  muestra lo obtiene del servidor.

  Para conectarse enlaza su nodo con el del servidor (`Node.connect/1`) y
  ubica el proceso del servidor por su nombre, `{Trivia.Servidor, nodo}`, sin
  conocer su PID. Las notificaciones de la partida las recibe `Trivia.Receptor`,
  un proceso distinto del que lee el teclado.

  Uso, desde un nodo iniciado con `iex --sname <nombre> -S mix`:

      Trivia.Cliente.iniciar()

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """

  alias Trivia.{Errores, Receptor}

  # ── Arranque y ciclo de lectura ──────────────────────────────────────

  @doc """
  Abre la consola del jugador.

  Sin argumentos busca el servidor en el nodo `servidor@<mi-equipo>`. Para un
  servidor en otro equipo se pasa su nombre completo, por ejemplo
  `Trivia.Cliente.iniciar("servidor@mi-pc")`.
  """
  def iniciar(servidor \\ nil) do
    cond do
      Trivia.Application.rol() == :servidor ->
        IO.puts("Este nodo es el servidor. Abra otra consola con: iex --sname <nombre> -S mix")

      not Node.alive?() ->
        IO.puts("Este nodo no está en red. Inicie IEx con: iex --sname <nombre> -S mix")

      true ->
        nodo = nodo_servidor(servidor)
        receptor = Receptor.iniciar()
        contexto = %{nodo: nodo, receptor: receptor}

        IO.puts("""

        ═══ Trivia Concurrente ═══
        Servidor: #{nodo}
        Escriba help para ver los comandos.
        """)

        bucle(contexto)
        Receptor.detener(receptor)
        IO.puts("Hasta pronto.")
    end
  end

  # Nodo del servidor: el indicado, o servidor@<equipo de este nodo>.
  defp nodo_servidor(nil) do
    equipo = node() |> Atom.to_string() |> String.split("@") |> List.last()
    String.to_atom("servidor@" <> equipo)
  end

  defp nodo_servidor(nombre) when is_binary(nombre), do: String.to_atom(nombre)
  defp nodo_servidor(nodo) when is_atom(nodo), do: nodo

  # Lee una línea, la ejecuta y vuelve a leer, hasta que el jugador salga.
  defp bucle(contexto) do
    case IO.gets("trivia> ") do
      :eof ->
        cerrar(contexto)

      {:error, _razon} ->
        cerrar(contexto)

      linea ->
        case ejecutar_linea(String.trim(linea), contexto) do
          :salir -> cerrar(contexto)
          :seguir -> bucle(contexto)
        end
    end
  end

  # Al salir se cierra la sesión para liberar al usuario y su partida.
  defp cerrar(contexto), do: peticion(contexto, :disconnect)

  defp ejecutar_linea("", _contexto), do: :seguir

  defp ejecutar_linea(linea, contexto) do
    case parsear(linea) do
      :ayuda ->
        IO.puts(ayuda())
        :seguir

      :salir ->
        :salir

      {:ok, comando} ->
        resultado = peticion(contexto, comando)
        IO.puts(formatear(comando, resultado))
        :seguir

      {:error, error} ->
        IO.puts("✖ " <> Exception.message(error))
        :seguir
    end
  end

  # ── Comunicación con el servidor ─────────────────────────────────────

  @doc """
  Envía una petición al servidor y espera su respuesta.

  Si el servidor no está disponible devuelve
  `{:error, %Trivia.Errores.ServidorNoDisponible{}}` en lugar de fallar.
  """
  def peticion(contexto, comando) do
    if Node.connect(contexto.nodo) == true do
      try do
        GenServer.call(
          {Trivia.Servidor, contexto.nodo},
          {:peticion, contexto.receptor, comando},
          15_000
        )
      catch
        :exit, _razon -> {:error, %Errores.ServidorNoDisponible{nodo: contexto.nodo}}
      end
    else
      {:error, %Errores.ServidorNoDisponible{nodo: contexto.nodo}}
    end
  end

  # ── Interpretación de lo que escribe el jugador ──────────────────────

  @doc """
  Traduce una línea escrita en la consola a un comando para el servidor.

  Devuelve `{:ok, comando}`, `:ayuda`, `:salir` o `{:error, error}` si la línea
  no tiene la forma de ningún comando.
  """
  def parsear(linea) do
    case String.split(linea) do
      ["help"] -> :ayuda
      ["exit"] -> :salir
      ["quit"] -> :salir
      ["connect", usuario, clave] -> {:ok, {:connect, usuario, clave}}
      ["connect" | _] -> uso("connect <usuario> <clave>")
      ["disconnect"] -> {:ok, :disconnect}
      ["create_game" | argumentos] -> parsear_create_game(argumentos)
      ["add_bot", dificultad] -> parsear_add_bot(dificultad)
      ["add_bot" | _] -> uso("add_bot <facil|dificil>")
      ["start_game"] -> {:ok, :start_game}
      ["leave_game"] -> {:ok, :leave_game}
      ["answer", letra] -> {:ok, {:answer, letra}}
      ["answer" | _] -> uso("answer <A|B|C|D>")
      ["score"] -> {:ok, :score}
      ["ranking"] -> {:ok, {:ranking, nil}}
      ["ranking", tema] -> {:ok, {:ranking, String.downcase(tema)}}
      ["ranking" | _] -> uso("ranking [tema]")
      [comando | _] -> {:error, %Errores.ComandoInvalido{detalle: "Comando desconocido: #{comando}. Escriba help."}}
      [] -> uso("help")
    end
  end

  defp parsear_add_bot(dificultad) do
    case String.downcase(dificultad) do
      "facil" -> {:ok, {:add_bot, :facil}}
      "dificil" -> {:ok, {:add_bot, :dificil}}
      _otra -> uso("add_bot <facil|dificil>")
    end
  end

  # create_game tema=<tema> preguntas=<n> tiempo=<segundos>, en cualquier orden.
  defp parsear_create_game(argumentos) do
    pares = Enum.map(argumentos, fn argumento -> String.split(argumento, "=") end)
    tema = valor_de(pares, "tema")
    preguntas = a_entero(valor_de(pares, "preguntas"))
    tiempo = a_entero(valor_de(pares, "tiempo"))

    if tema in [nil, ""] or preguntas == nil or tiempo == nil do
      uso("create_game tema=<tema> preguntas=<n> tiempo=<segundos>")
    else
      {:ok, {:create_game, String.downcase(tema), preguntas, tiempo}}
    end
  end

  # Busca el valor de una clave en la lista de pares [clave, valor].
  defp valor_de(pares, clave) do
    case Enum.find(pares, fn par -> hd(par) == clave end) do
      [_clave, valor] -> valor
      _otro -> nil
    end
  end

  defp a_entero(nil), do: nil

  defp a_entero(texto) do
    case Integer.parse(texto) do
      {numero, ""} -> numero
      _otro -> nil
    end
  end

  defp uso(forma) do
    {:error, %Errores.ComandoInvalido{detalle: "Uso: #{forma}"}}
  end

  # ── Presentación de las respuestas del servidor ──────────────────────

  @doc "Texto que se muestra al jugador como respuesta a un comando."
  def formatear(_comando, {:error, error}), do: "✖ " <> Exception.message(error)

  def formatear({:connect, _usuario, _clave}, {:ok, %{usuario: usuario, tipo: tipo}}) do
    case tipo do
      :registrado -> "✔ Usuario #{usuario} registrado. Sesión iniciada."
      :autenticado -> "✔ Sesión iniciada. Bienvenido, #{usuario}."
      :ya_conectado -> "Ya tiene la sesión iniciada como #{usuario}."
    end
  end

  def formatear(:disconnect, {:ok, :desconectado}), do: "✔ Sesión cerrada."

  def formatear({:create_game, _tema, _n, _s}, {:ok, datos}) do
    "✔ Partida #{datos.id} creada (#{datos.tema}, #{datos.preguntas} preguntas, " <>
      "#{datos.tiempo} s por pregunta).\n" <>
      "  Su nivel en #{datos.tema} es #{Receptor.nivel_texto(datos.nivel)}.\n" <>
      "  Agregue al menos dos bots con: add_bot <facil|dificil>"
  end

  def formatear({:add_bot, _dificultad}, {:ok, datos}) do
    "✔ #{datos.bot} (#{datos.dificultad}) se unió a la partida #{datos.id}. " <>
      "Jugadores: #{datos.jugadores}/4."
  end

  def formatear(:start_game, {:ok, datos}) do
    "✔ Partida #{datos.id} iniciada con #{Enum.join(datos.jugadores, ", ")}. " <>
      "Son #{datos.preguntas} preguntas."
  end

  def formatear(:leave_game, {:ok, :cancelada}), do: "✔ Partida cancelada. Ya puede crear otra."

  def formatear(:leave_game, {:ok, :finalizada}) do
    "✔ Abandonó la partida; el resultado quedó registrado con los puntos obtenidos."
  end

  def formatear({:answer, _letra}, {:ok, :registrada}), do: "✔ Respuesta registrada."

  def formatear({:answer, _letra}, {:ok, :ignorada}) do
    "Ya había respondido esta pregunta; la respuesta se ignora (sin penalización)."
  end

  def formatear(:score, {:ok, datos}) do
    encabezado = [
      "=== #{datos.usuario} ===",
      "Puntaje acumulado: #{datos.puntaje}",
      "Partidas jugadas: #{datos.partidas}"
    ]

    if datos.temas == [] do
      Enum.join(encabezado ++ ["(todavía no ha jugado ningún tema)"], "\n")
    else
      titulos = String.pad_trailing("Tema", 14) <> String.pad_trailing("Puntaje", 10) <> "Nivel"

      filas =
        Enum.map(datos.temas, fn fila ->
          String.pad_trailing(fila.tema, 14) <>
            String.pad_trailing("#{fila.puntaje}", 10) <> "#{fila.nivel}"
        end)

      Enum.join(encabezado ++ [titulos | filas], "\n")
    end
  end

  def formatear({:ranking, _tema}, {:ok, %{tema: tema, filas: filas}}) do
    titulo = if tema == nil, do: "=== Ranking global ===", else: "=== Ranking #{tema} ==="

    if filas == [] do
      titulo <> "\nNo hay partidas registradas."
    else
      titulos =
        String.pad_trailing("#", 4) <>
          String.pad_trailing("Jugador", 16) <> String.pad_trailing("Puntaje", 10) <> "Partidas"

      cuerpo =
        filas
        |> Enum.with_index(1)
        |> Enum.map(fn {fila, posicion} ->
          String.pad_trailing("#{posicion}", 4) <>
            String.pad_trailing(fila.jugador, 16) <>
            String.pad_trailing("#{fila.puntaje}", 10) <> "#{fila.partidas}"
        end)

      Enum.join([titulo, titulos | cuerpo], "\n")
    end
  end

  def formatear(_comando, otro), do: inspect(otro)

  defp ayuda do
    """
    Comandos disponibles:
      connect <usuario> <clave>                        inicia sesión (registra si no existe)
      disconnect                                       cierra la sesión
      create_game tema=<tema> preguntas=<n> tiempo=<s> crea una partida
      add_bot <facil|dificil>                          agrega un bot a la partida
      start_game                                       inicia la partida
      leave_game                                       abandona la partida
      answer <A|B|C|D>                                 responde la pregunta abierta
      score                                            su puntaje, partidas y nivel por tema
      ranking [tema]                                   ranking histórico (global o por tema)
      help                                             muestra esta ayuda
      exit                                             cierra la sesión y sale
    """
  end
end
