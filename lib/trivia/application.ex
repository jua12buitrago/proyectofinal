defmodule Trivia.Application do
  @moduledoc """
  Arranque de la aplicación y rol de cada nodo (sección 8.2).

  El mismo proyecto Mix se ejecuta en todas las consolas, pero cada nodo
  arranca en un papel distinto:

  - **servidor**: el nodo que se llama `servidor`
    (`iex --sname servidor -S mix`). Levanta los procesos del juego.
  - **cliente**: cualquier otro nodo (`iex --sname pedro -S mix`). No levanta
    ningún proceso del juego, así que no tiene su propia copia del estado y
    tiene que usar el servidor central.

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use Application

  @impl true
  def start(_tipo, _argumentos) do
    # rest_for_one: si cae un proceso, se reinician los que se crearon después.
    Supervisor.start_link(hijos(rol()), strategy: :rest_for_one, name: Trivia.Supervisor)
  end

  @doc "Rol del nodo actual: `:servidor`, `:cliente` o `:ninguno` (en las pruebas)."
  def rol do
    case Application.get_env(:trivia, :rol, :auto) do
      :auto -> rol_del_nodo()
      otro_rol -> otro_rol
    end
  end

  # El nombre del nodo es algo como :"servidor@mi-pc"; se mira lo que va antes de la @.
  defp rol_del_nodo do
    nombre = node() |> Atom.to_string() |> String.split("@") |> hd()

    if nombre == "servidor" do
      :servidor
    else
      :cliente
    end
  end

  # El orden importa: cada proceso solo usa a los que están antes que él.
  defp hijos(:servidor) do
    [
      Trivia.Persistencia,
      Trivia.BancoPreguntas,
      Trivia.GestorJugadores,
      Trivia.SupervisorPartidas,
      Trivia.GestorPartidas,
      Trivia.Servidor
    ]
  end

  defp hijos(_otro_rol), do: []
end
