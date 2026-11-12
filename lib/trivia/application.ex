defmodule Trivia.Application do
  @moduledoc """
  Arranque de la aplicación y rol de cada nodo (sección 8.2).
  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use Application

  @impl true
  def start(_tipo, _argumentos) do
    Supervisor.start_link(hijos(rol()), strategy: :rest_for_one, name: Trivia.Supervisor)
  end

  @doc "Rol del nodo actual: :servidor, :cliente o :ninguno (en las pruebas)."
  def rol do
    case Application.get_env(:trivia, :rol, :auto) do
      :auto ->
        if String.starts_with?(to_string(node()), "servidor@"), do: :servidor, else: :cliente
      otro_rol ->
        otro_rol
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

  # Para cualquier otro rol, no arranca procesos
  defp hijos(_), do: []
end
