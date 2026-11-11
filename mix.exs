defmodule Trivia.MixProject do
  @moduledoc """
  Definición del proyecto Mix de la Trivia Concurrente.
  - autor: Juan Manuel Castaño Buitrago
  - fecha: Noviembre del 2026
  """
  use Mix.Project

  def project do
    [
      app: :trivia,
      version: "1.0.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Trivia.Application decide, según el nombre del nodo, si el nodo arranca
  # como servidor o como cliente.
  def application do
    [
      extra_applications: [:logger],
      mod: {Trivia.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end
end
