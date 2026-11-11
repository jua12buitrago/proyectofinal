import Config

# El rol del nodo se decide al arrancar:
#   :auto     -> servidor si el nodo se llama "servidor", cliente en otro caso
#   :ninguno  -> no arranca ningún proceso (se usa en las pruebas)
config :trivia, rol: :auto

if config_env() == :test do
  config :trivia, rol: :ninguno
end
