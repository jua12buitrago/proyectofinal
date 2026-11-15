# Trivia Concurrente — Proyecto Final de Programación III

Universidad del Quindío · Programa de Ingeniería de Sistemas y Computación
Docente: Carlos Andrés Florez V.

## Integrantes

- Juan Manuel Castaño Buitrago
- Christian David Lopera Castaño
- Samuel Mejía Guerrero

## Descripción

Juego de preguntas y respuestas por consola. Un **servidor central** (un nodo Elixir)
guarda el estado del juego y los datos. Cada jugador abre un **cliente** (otro nodo
Elixir, en otra consola) que solo envía peticiones y muestra lo que recibe. Cada cliente
juega su propia partida contra 2 o 3 bots, y varias partidas corren al mismo tiempo,
cada una en su propio `GenServer` bajo un `DynamicSupervisor`.

Alcance: secciones 1 a 14 del enunciado. La extensión opcional de la sección 15
(varios humanos en la misma partida) no se implementó.

## Compilación

```
mix deps.get
```

## Cómo levantar el servidor y los clientes

```
# Consola 1: servidor (el nodo DEBE llamarse "servidor")
iex --sname servidor -S mix

# Consola 2: cliente de Pedro
iex --sname pedro -S mix
iex> Trivia.Cliente.iniciar()

# Consola 3: cliente de Carlos
iex --sname carlos -S mix
iex> Trivia.Cliente.iniciar()
```

## Comandos del cliente

| Comando | Descripción |
|---|---|
| `connect <usuario> <clave>` | Inicia sesión; si el usuario no existe, lo registra |
| `disconnect` | Cierra la sesión (si hay una partida en curso, termina y se registra) |
| `create_game tema=<tema> preguntas=<n> tiempo=<s>` | Crea una partida y responde con su id y el nivel del jugador en el tema |
| `add_bot <facil\|dificil>` | Agrega un bot (la partida admite 3 o 4 jugadores) |
| `start_game` | Inicia la partida (necesita al menos 2 bots) |
| `leave_game` | Abandona la partida |
| `answer <A\|B\|C\|D>` | Responde la pregunta abierta |
| `score` | Puntaje acumulado, partidas jugadas, y puntaje y nivel por tema |
| `ranking` | Ranking histórico global |
| `ranking [tema]` | Ranking de un tema |
| `help` / `exit` | Muestra la ayuda / cierra la sesión y sale |



