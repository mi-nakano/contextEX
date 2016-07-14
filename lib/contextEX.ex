defmodule ContextEX do
  @agentName ContextEXAgent

  defmacro __using__(options) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      Agent.start(fn -> %{} end, name: unquote(@agentName))
    end
  end

  defmacro __before_compile__(env) do
  end

  defmacro initLayer() do
    quote do
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      Agent.update(unquote(@agentName), fn(state) ->
        Map.put(state, self, pid)
      end)
    end
  end

  defmacro getActiveLayers() do
    quote do
      pid = Agent.get(unquote(@agentName), fn(state) -> state[self] end)
      Agent.get(pid, fn(state) -> state end)
    end
  end

  defmacro activateLayer(map) do
    quote do
      pid = Agent.get(unquote(@agentName), fn(state) -> state[self] end)
      Agent.update(pid, fn(state) ->
        Map.merge(state, unquote(map))
      end)
    end
  end

  defmacro isActive?(layer) do
    quote do
      map = getActiveLayers
      unquote(layer) in Map.values(map)
    end
  end
end
