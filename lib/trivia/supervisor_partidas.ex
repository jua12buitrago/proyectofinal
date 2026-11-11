defmodule Trivia.SupervisorPartidas do
  @moduledoc """
  DynamicSupervisor de las partidas (secciones 8.4 y 8.5).

  Cada partida se registra como hijo con `restart: :transient`: si termina de
  forma anormal el supervisor la reinicia con los mismos argumentos con los
  que se creó, y si termina bien no la vuelve a levantar. La falla de una
  partida nunca afecta a las demás.

  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use DynamicSupervisor

  def start_link(_opciones \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Levanta una partida nueva. `argumentos` es el mapa con el que se crea la partida."
  def iniciar_partida(argumentos) do
    DynamicSupervisor.start_child(__MODULE__, {Trivia.Partida, argumentos})
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
