# Trivia Concurrente — Proyecto Final de Programación III

Universidad del Quindío · Programa de Ingeniería de Sistemas y Computación
Docente: Carlos Andrés Florez V.

## Integrantes

- Juan Manuel Castaño Buitrago
- (agregar aquí a los demás integrantes del grupo)

## Descripción

Juego de preguntas y respuestas por consola. Un **servidor central** (un nodo Elixir)
guarda el estado del juego y los datos. Cada jugador abre un **cliente** (otro nodo
Elixir, en otra consola) que solo envía peticiones y muestra lo que recibe. Cada cliente
juega su propia partida contra 2 o 3 bots, y varias partidas corren al mismo tiempo,
cada una en su propio `GenServer` bajo un `DynamicSupervisor`.

Alcance: secciones 1 a 14 del enunciado. La extensión opcional de la sección 15
(varios humanos en la misma partida) no se implementó.

## Requisitos

- Erlang/OTP y Elixir 1.15 o superior (`elixir -v`).
- Internet la primera vez, para descargar la dependencia `jason`.

## Compilación

```
mix deps.get
mix compile
```

## Cómo levantar el servidor y los clientes

Todas las consolas se abren en la carpeta del proyecto, en el mismo equipo.

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

El rol lo decide el nombre del nodo: `servidor` levanta el juego y cualquier otro nombre
arranca como cliente, sin levantar ningún proceso del juego. En Windows use CMD (en
PowerShell escriba `iex.bat`). Para un servidor en otro equipo:
`Trivia.Cliente.iniciar("servidor@nombre-del-equipo")`.

Si el cliente se abre antes que el servidor, los comandos responden "Servidor no
disponible" y basta repetirlos cuando el servidor ya esté levantado.

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
| `ranking [tema]` | Ranking histórico global o de un tema |
| `help` / `exit` | Muestra la ayuda / cierra la sesión y sale |

Temas incluidos en `data/questions.json`: `ciencia`, `historia`, `geografia` y
`tecnologia` (8 preguntas o más por nivel en cada uno). Para agregar temas o preguntas
basta con editar ese archivo, sin cambiar código.

## Ejemplo de uso

```
trivia> connect pedro 1234
trivia> create_game tema=ciencia preguntas=5 tiempo=15
trivia> add_bot dificil
trivia> add_bot facil
trivia> start_game
trivia> answer B
trivia> score
trivia> ranking ciencia
```

## Demostración del reinicio de una partida (sección 8.5)

En la consola del servidor, con una partida creada:

```
iex> Trivia.GestorPartidas.simular_falla("pedro")
```

El supervisor reinicia la partida desde cero y el cliente de Pedro recibe el aviso. Hay
que agregar de nuevo los bots y ejecutar `start_game`.

## Pruebas

```
mix test
```

Incluye las 7 pruebas de la sección 12: puntaje (`partida_test.exs`), sorteo
(`banco_preguntas_test.exs`), validación de respuestas y armado de la partida
(`partida_test.exs`), estadísticas desde el historial (`gestor_jugadores_test.exs`),
decisión del bot (`bot_test.exs`) y nivel del jugador (`nivel_test.exs`).

## Estructura

```
lib/trivia/
  servidor.ex             SERVIDOR  recibe las peticiones y las enruta
  gestor_jugadores.ex     SERVIDOR  registro, sesiones, puntajes y ranking
  gestor_partidas.ex      SERVIDOR  creación, ubicación y aviso de reinicio
  partida.ex              SERVIDOR  GenServer de partida
  supervisor_partidas.ex  SERVIDOR  DynamicSupervisor de partidas
  bot.ex                  SERVIDOR  jugador automático
  banco_preguntas.ex      SERVIDOR  carga y sorteo de preguntas por tema y nivel
  nivel.ex                SERVIDOR  nivel del jugador y reparto por nivel
  persistencia.ex         SERVIDOR  lectura y escritura de archivos
  cliente.ex              CLIENTE   consola del jugador y envío de peticiones
  receptor.ex             CLIENTE   recepción de las notificaciones de la partida
  application.ex          arranque de la aplicación (rol del nodo)
  errores.ex              errores propios del juego (sección 10)
data/                     questions.json (semilla); users.json y results.log se generan solos
test/                     pruebas ExUnit
```

## Uso de inteligencia artificial

Ver `docs/USO_IA.md`.
