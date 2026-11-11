defmodule Trivia.Errores do
  @moduledoc """
  Errores propios del juego.

  Cada situación inválida de la sección 10 del enunciado tiene su propia
  excepción. Las funciones no las lanzan: las devuelven dentro de una tupla
  `{:error, %Trivia.Errores.Algo{}}`, y quien las recibe usa
  `Exception.message/1` para obtener el texto que se muestra al jugador.

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
end

defmodule Trivia.Errores.SinSesion do
  @moduledoc "Comando ejecutado sin haber iniciado sesión."
  defexception message: "Debe iniciar sesión primero con: connect <usuario> <clave>"
end

defmodule Trivia.Errores.ClaveIncorrecta do
  @moduledoc "Clave incorrecta al conectarse con un usuario existente."
  defexception [:usuario]

  @impl true
  def message(%{usuario: usuario}), do: "Clave incorrecta para el usuario #{usuario}."
end

defmodule Trivia.Errores.SesionDuplicada do
  @moduledoc "El usuario ya tiene una sesión abierta en otro cliente."
  defexception [:usuario]

  @impl true
  def message(%{usuario: usuario}),
    do: "El usuario #{usuario} ya tiene una sesión abierta en otro cliente."
end

defmodule Trivia.Errores.SesionYaIniciada do
  @moduledoc "Este cliente ya tiene una sesión abierta con otro usuario."
  defexception [:usuario]

  @impl true
  def message(%{usuario: usuario}),
    do: "Este cliente ya tiene la sesión abierta como #{usuario}. Use disconnect primero."
end

defmodule Trivia.Errores.UsuarioReservado do
  @moduledoc "El usuario empieza por el prefijo reservado bot_."
  defexception [:usuario]

  @impl true
  def message(%{usuario: usuario}),
    do: "El usuario #{usuario} no es válido: el prefijo bot_ está reservado para los bots."
end

defmodule Trivia.Errores.UsuarioInvalido do
  @moduledoc "El nombre de usuario está vacío o tiene caracteres no permitidos."
  defexception [:usuario]

  @impl true
  def message(%{usuario: usuario}),
    do:
      "El usuario #{inspect(usuario)} no es válido: no puede estar vacío ni " <>
        "contener espacios ni los caracteres | = , ;"
end

defmodule Trivia.Errores.ServidorNoDisponible do
  @moduledoc "El cliente no pudo comunicarse con el nodo del servidor."
  defexception [:nodo]

  @impl true
  def message(%{nodo: nodo}),
    do:
      "Servidor no disponible (nodo #{nodo}). Verifique que esté levantado " <>
        "y que este nodo se haya iniciado con --sname."
end

defmodule Trivia.Errores.YaEnPartida do
  @moduledoc "create_game ejecutado por un jugador que ya está en una partida."
  defexception [:id]

  @impl true
  def message(%{id: id}),
    do: "Ya está en la partida #{id}. Termínela o use leave_game antes de crear otra."
end

defmodule Trivia.Errores.TemaInexistente do
  @moduledoc "El tema solicitado no existe en el banco de preguntas."
  defexception [:tema]

  @impl true
  def message(%{tema: tema}),
    do: "El tema #{inspect(tema)} no existe en el banco de preguntas."
end

defmodule Trivia.Errores.PreguntasInsuficientes do
  @moduledoc "El tema no tiene suficientes preguntas de algún nivel para el reparto."
  defexception [:tema, :nivel, :necesarias, :disponibles]

  @impl true
  def message(%{tema: tema, nivel: nivel, necesarias: necesarias, disponibles: disponibles}),
    do:
      "El tema #{tema} no tiene suficientes preguntas de nivel #{nivel}: " <>
        "se necesitan #{necesarias} y hay #{disponibles}."
end

defmodule Trivia.Errores.SinPartida do
  @moduledoc "Comando de partida ejecutado sin estar en una partida."
  defexception message:
                 "No está en ninguna partida. Cree una con: create_game tema=<tema> preguntas=<n> tiempo=<s>"
end

defmodule Trivia.Errores.PartidaLlena do
  @moduledoc "add_bot con la partida llena."
  defexception [:id]

  @impl true
  def message(%{id: id}), do: "La partida #{id} ya tiene 4 jugadores; no admite más bots."
end

defmodule Trivia.Errores.PartidaYaIniciada do
  @moduledoc "La operación no es válida porque la partida ya fue iniciada."
  defexception [:id]

  @impl true
  def message(%{id: id}), do: "La partida #{id} ya fue iniciada."
end

defmodule Trivia.Errores.BotsInsuficientes do
  @moduledoc "start_game con menos de dos bots en la partida."
  defexception [:bots]

  @impl true
  def message(%{bots: bots}),
    do: "Para iniciar la partida se necesitan al menos 2 bots y hay #{bots}. Use add_bot."
end

defmodule Trivia.Errores.LetraInvalida do
  @moduledoc "La respuesta no es una de las letras A, B, C o D."
  defexception [:letra]

  @impl true
  def message(%{letra: letra}),
    do: "La letra #{inspect(letra)} no es válida. Responda con A, B, C o D."
end

defmodule Trivia.Errores.SinRondaAbierta do
  @moduledoc "Respuesta enviada cuando no hay una ronda abierta."
  defexception message: "No hay una ronda abierta: la respuesta se rechaza."
end

defmodule Trivia.Errores.DificultadInvalida do
  @moduledoc "La dificultad del bot no es facil ni dificil."
  defexception [:dificultad]

  @impl true
  def message(%{dificultad: dificultad}),
    do: "La dificultad #{inspect(dificultad)} no es válida. Use facil o dificil."
end

defmodule Trivia.Errores.ArgumentosInvalidos do
  @moduledoc "Los argumentos de un comando no cumplen las reglas del juego."
  defexception [:detalle]

  @impl true
  def message(%{detalle: detalle}), do: "Argumentos inválidos: #{detalle}"
end

defmodule Trivia.Errores.ComandoInvalido do
  @moduledoc "El texto escrito en la consola no corresponde a un comando."
  defexception [:detalle]

  @impl true
  def message(%{detalle: detalle}), do: detalle
end

defmodule Trivia.Errores.ErrorInterno do
  @moduledoc "Falla inesperada al atender una petición; el servidor sigue operando."
  defexception [:detalle]

  @impl true
  def message(%{detalle: detalle}),
    do: "Ocurrió un error interno al atender la petición (#{detalle}). El servidor sigue activo."
end
