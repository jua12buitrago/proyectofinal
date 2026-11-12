defmodule Trivia.GestorJugadores do
  @moduledoc """
  Registro de jugadores, sesiones, puntajes y ranking (secciones 4 y 8.2).

  El proceso guarda dos cosas: los usuarios registrados (cargados de
  users.json) y las sesiones abiertas. Cada sesión se identifica con el PID
  del proceso receptor del cliente. El servidor monitorea ese PID: si el
  proceso desaparece, la sesión se cierra y la partida del jugador termina
  según la sección 6.5.

  El jugador no guarda estadísticas: su puntaje, sus partidas jugadas y el
  ranking se calculan recorriendo las líneas del historial (results.log).
  Esas funciones son puras: reciben las líneas como argumento.

  Cada línea del historial tiene este formato:

      fecha|id|tema|nivel|ganadores|jugador1=puntos,jugador2=puntos

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use GenServer

  alias Trivia.{Errores, GestorPartidas, Nivel, Persistencia}

  # ── API pública: sesiones ────────────────────────────────────────────

  def start_link(_opciones \\ []) do
    GenServer.start_link(_MODULE, :ok, name: __MODULE_)
  end

  @doc """
  Inicia sesión; si el usuario no existe, lo registra.

  Devuelve {:ok, %{usuario: usuario, tipo: tipo}} (el tipo es :registrado,
  :autenticado o :ya_conectado) o {:error, error}.
  """
  def conectar(usuario, clave, pid) do
    GenServer.call(_MODULE_, {:conectar, usuario, clave, pid})
  end

  @doc "Cierra la sesión que tiene ese PID."
  def desconectar(pid), do: GenServer.call(_MODULE_, {:desconectar, pid})

  @doc "Usuario que tiene la sesión abierta con ese PID: {:ok, usuario} o {:error, error}."
  def usuario_de(pid), do: GenServer.call(_MODULE_, {:usuario_de, pid})

  # ── API pública: consultas (se calculan desde el historial) ──────────

  @doc "Puntaje, partidas jugadas y puntaje y nivel por tema de un usuario."
  def score(usuario) do
    lineas = Persistencia.historial()
    por_tema = puntaje_por_tema(lineas, usuario)

    temas =
      por_tema
      |> Enum.sort_by(fn {tema, _puntos} -> tema end)
      |> Enum.map(fn {tema, puntos} ->
        %{tema: tema, puntaje: puntos, nivel: Nivel.por_puntaje(puntos)}
      end)

    %{
      usuario: usuario,
      puntaje: por_tema |> Map.values() |> Enum.sum(),
      partidas: partidas_jugadas(lineas, usuario),
      temas: temas
    }
  end

  @doc "Ranking histórico global, o de un solo tema si se indica."
  def ranking(tema) do
    %{tema: tema, filas: ranking_desde(Persistencia.historial(), tema)}
  end

  @doc "Nivel actual de un usuario en un tema."
  def nivel_en_tema(usuario, tema) do
    Nivel.nivel_en_tema(Persistencia.historial(), usuario, tema)
  end

  # ── Funciones puras sobre el historial ───────────────────────────────

  @doc "Indica si un nombre pertenece a un bot (empieza por bot_)."
  def es_bot?(nombre) do
    nombre |> String.downcase() |> String.starts_with?("bot_")
  end

  @doc "Convierte una línea del historial en un mapa. Devuelve nil si está mal formada."
  def leer_linea(linea) do
    case String.split(String.trim(linea), "|") do
      [_fecha, id, tema, nivel, ganadores, puntajes] ->
        %{
          id: id,
          tema: tema,
          nivel: nivel,
          ganadores: String.split(ganadores, ";"),
          puntajes: leer_puntajes(puntajes)
        }

      _otro ->
        nil
    end
  end

  defp leer_puntajes(texto) do
    texto
    |> String.split(",")
    |> Stream.map(&leer_par/1)
    |> Enum.reject(&is_nil/1)
  end

  defp leer_par(par) do
    case String.split(par, "=") do
      [jugador, valor] ->
        case Integer.parse(valor) do
          {puntos, ""} -> {jugador, puntos}
          _otro -> nil
        end

      _otro ->
        nil
    end
  end

  # Todas las partidas del historial que se pudieron leer (procesado perezosamente)
  defp leer_historial(lineas) do
    lineas
    |> Stream.map(&leer_linea/1)
    |> Stream.reject(&is_nil/1)
  end

  @doc """
  Puntaje acumulado de un usuario en cada tema: %{tema => puntaje}.
  Los puntajes negativos restan.
  """
  def puntaje_por_tema(lineas, usuario) do
    if es_bot?(usuario) do
      %{}
    else
      lineas
      |> leer_historial()
      |> Enum.reduce(%{}, fn partida, acumulado ->
        case List.keyfind(partida.puntajes, usuario, 0) do
          {_nombre, puntos} ->
            Map.update(acumulado, partida.tema, puntos, &(&1 + puntos))

          nil ->
            acumulado
        end
      end)
    end
  end

  @doc "Número de partidas en las que participó un usuario."
  def partidas_jugadas(lineas, usuario) do
    if es_bot?(usuario) do
      0
    else
      lineas
      |> leer_historial()
      |> Enum.count(&List.keymember?(&1.puntajes, usuario, 0))
    end
  end

  @doc """
  Ranking histórico de los jugadores humanos, de mayor a menor puntaje. Con un
  tema solo cuenta las partidas de ese tema (con nil cuenta todas).
  """
  def ranking_desde(lineas, tema) do
    lineas
    |> leer_historial()
    |> Stream.filter(&(is_nil(tema) or &1.tema == tema))
    |> Enum.reduce(%{}, fn partida, acumulado ->
      Enum.reduce(partida.puntajes, acumulado, fn
        {jugador, puntos}, interno when jugador == "bot" -> interno
        {jugador, puntos}, interno ->
          if es_bot?(jugador) do
            interno
          else
            Map.update(interno, jugador, {puntos, 1}, fn {total, n} -> {total + puntos, n + 1} end)
          end
      end)
    end)
    |> Enum.map(fn {jugador, {puntos, n}} ->
      %{jugador: jugador, puntaje: puntos, partidas: n}
    end)
    |> Enum.sort_by(&({-&1.puntaje, &1.jugador}))
  end

  # ── Callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(:ok) do
    {:ok, %{usuarios: Persistencia.usuarios(), sesiones: %{}}}
  end

  @impl true
  def handle_call({:conectar, usuario, clave, pid}, _from, %{sesiones: sesiones} = estado) do
    case Map.get(sesiones, pid) do
      nil ->
        conectar_nuevo(usuario, clave, pid, estado)

      ^usuario ->
        {:reply, {:ok, %{usuario: usuario, tipo: :ya_conectado}}, estado}

      otro_usuario ->
        {:reply, {:error, %Errores.SesionYaIniciada{usuario: otro_usuario}}, estado}
    end
  end

  def handle_call({:desconectar, pid}, _from, estado) do
    {:reply, :ok, %{estado | sesiones: Map.delete(estado.sesiones, pid)}}
  end

  def handle_call({:usuario_de, pid}, _from, %{sesiones: sesiones} = estado) do
    case Map.get(sesiones, pid) do
      nil -> {:reply, {:error, %Errores.SinSesion{}}, estado}
      usuario -> {:reply, {:ok, usuario}, estado}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _razon}, %{sesiones: sesiones} = estado) do
    case Map.get(sesiones, pid) do
      nil ->
        {:noreply, estado}

      usuario ->
        GestorPartidas.cliente_caido(usuario)
        {:noreply, %{estado | sesiones: Map.delete(sesiones, pid)}}
    end
  end

  def handle_info(_otro, estado), do: {:noreply, estado}

  # ── Funciones privadas ───────────────────────────────────────────────

  defp conectar_nuevo(usuario, clave, pid, estado) do
    with :ok <- validar_nombre(usuario),
         :ok <- validar_reservado(usuario),
         :ok <- validar_clave(estado.usuarios, usuario, clave),
         :ok <- validar_sesion_libre(estado.sesiones, usuario) do
      tipo = registrar_si_es_nuevo(estado.usuarios, usuario, clave)
      Process.monitor(pid)

      nuevo_estado = %{
        usuarios: Map.put(estado.usuarios, usuario, clave),
        sesiones: Map.put(estado.sesiones, pid, usuario)
      }

      {:reply, {:ok, %{usuario: usuario, tipo: tipo}}, nuevo_estado}
    else
      {:error, error} -> {:reply, {:error, error}, estado}
    end
  end

  defp validar_nombre(usuario) do
    prohibidos = ["|", "=", ",", ";"]
    tiene_prohibidos = Enum.any?(prohibidos, &String.contains?(usuario, &1))

    if String.split(usuario) != [usuario] or tiene_prohibidos,
      do: {:error, %Errores.UsuarioInvalido{usuario: usuario}},
      else: :ok
  end

  defp validar_reservado(usuario) do
    if es_bot?(usuario), do: {:error, %Errores.UsuarioReservado{usuario: usuario}}, else: :ok
  end

  defp validar_clave(usuarios, usuario, clave) do
    case Map.get(usuarios, usuario) do
      nil -> :ok
      ^clave -> :ok
      _otra -> {:error, %Errores.ClaveIncorrecta{usuario: usuario}}
    end
  end

  defp validar_sesion_libre(sesiones, usuario) do
    if usuario in Map.values(sesiones),
      do: {:error, %Errores.SesionDuplicada{usuario: usuario}},
      else: :ok
  end

  defp registrar_si_es_nuevo(usuarios, usuario, clave) do
    if Map.has_key?(usuarios, usuario) do
      :autenticado
    else
      Persistencia.guardar_usuario(usuario, clave)
      :registrado
    end
  end
end
