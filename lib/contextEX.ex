defmodule ContextEX do
  @topAgent :ContextEXAgent
  @noneGroup :noneGroup

  @partial_prefix "_partial_"
  @arg_name "arg"

  defmacro __using__(_options) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      Module.register_attribute __MODULE__, :layeredFunc, accumulate: true, persist: false

      defp get_activelayers(), do: get_activelayers(self)
      defp activate_layer(map), do: activate_layer(self, map)
      defp is_active?(layer), do: is_active?(self, layer)
    end
  end

  defmacro __before_compile__(env) do
    attrs = Module.get_attribute(env.module, :layeredFunc)
    defList = attrs |> Enum.map(&(gen_genericfunction_ast(&1, env.module)))

    # return AST
    {:__block__, [], defList}
  end

  defmacro init_context(arg \\ nil) do
    quote do
      group = if unquote(arg) == nil do
        unquote(@noneGroup)
      else
        unquote(arg)
      end

      if !(unquote(@topAgent) in Process.registered) do
        {:ok, pid} = Agent.start(fn -> %{} end)
        try do
          Process.register pid, unquote(@topAgent)
        rescue
          ArgumentError ->
            IO.puts "(Warn) ArgumentError! at initializing TopAgent"
        end
      end

      selfPid = self
      {:ok, layerPid} = Agent.start_link(fn -> %{} end)
      topAgent = Process.whereis unquote(@topAgent)
      Agent.update(topAgent, fn(state) ->
        Map.put(state, {group, selfPid}, layerPid)
      end)
    end
  end

  @doc """
  return nil when pid isn't registered
  """
  defmacro get_activelayers(pid) do
    quote do
      selfPid = unquote(pid)
      topAgent = Process.whereis unquote(@topAgent)
      res = Agent.get(topAgent, fn(state) ->
        state |> Enum.find(fn(x) ->
          {{_, p}, _} = x
          p == selfPid
        end)
      end)
      if res == nil do
        nil
      else
        {_, layerPid} = res
        Agent.get(layerPid, fn(state) -> state end)
      end
    end
  end

  @doc """
  return nil when pid isn't registered
  """
  defmacro activate_layer(pid, map) do
    quote do
      selfPid = unquote(pid)
      topAgent = Process.whereis unquote(@topAgent)
      res = Agent.get(topAgent, fn(state) ->
        state |> Enum.find(fn(x) ->
          {{_, p}, _} = x
          p == selfPid
        end)
      end)
      if res == nil do
        nil
      else
        {_, layerPid} = res
        Agent.update(layerPid, fn(state) ->
          Map.merge(state, unquote(map))
        end)
      end
    end
  end

  defmacro activate_group(group, map) do
    quote do
      topAgent = Process.whereis unquote(@topAgent)
      pids = Agent.get(topAgent, fn(state) ->
        state |> Enum.filter(fn(x) ->
          {{g, _}, _} = x
          g == unquote(group)
        end) |> Enum.map(fn(x) ->
          {_, pid} = x
          pid
        end)
      end)
      pids |> Enum.each(fn(pid) ->
        Agent.update(pid, fn(state) ->
          Map.merge(state, unquote(map))
        end)
      end)
    end
  end

  defmacro is_active?(pid, layer) do
    quote do
      map = get_activelayers unquote(pid)
      unquote(layer) in Map.values(map)
    end
  end

  defmacro deflf(func, do: bodyExp) do
    quote do: deflf(unquote(func), %{}, do: unquote(bodyExp))
  end

  defmacro deflf({name, meta, argsExp}, mapExp \\ %{}, do: bodyExp) do
    arity = length(argsExp)
    pf_name = partialfunc_name(name)
    new_args = List.insert_at(argsExp, 0, mapExp)
    new_definition = {pf_name, meta, new_args}

    quote bind_quoted: [name: name, arity: arity, body: Macro.escape(bodyExp), definition: Macro.escape(new_definition)] do
      # register layered function
      if @layeredFunc[name] != arity do
        @layeredFunc {name, arity}
      end

      # define partialFunc in Caller module
      Kernel.defp(unquote(definition)) do
        unquote(body)
      end
    end
  end


  defp partialfunc_name(funcName) do
    String.to_atom(@partial_prefix <> Atom.to_string(funcName))
  end

  defp gen_genericfunction_ast({funcName, arity}, module) do
    args = gen_dummy_args(arity, module)
    {:def, [context: module, import: Kernel],
      [{funcName, [context: module], args},
       [do:
         {:__block__, [],[
          {:=, [], [{:layer, [], module}, {:get_activelayers, [], module}]},
          {partialfunc_name(funcName), [context: module],
            # pass activated layers for first arg
            List.insert_at(args, 0, {:layer, [], module})}
         ]}]]}
  end

  defp gen_dummy_args(0, _), do: []
  defp gen_dummy_args(num, module) do
    Enum.map(1.. num, fn(x) ->
      {String.to_atom(@arg_name <> Integer.to_string(x)), [], module}
    end)
  end
end
