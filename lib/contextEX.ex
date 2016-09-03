defmodule ContextEX do
  @topAgent :ContextEXAgent
  @noneGroup :noneGroup

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
    quote do
      deflf(unquote(func), %{}, do: unquote(bodyExp))
    end
  end

  defmacro deflf(func, mapExp \\ %{}, do: bodyExp) do
    {name, _, argsExp} = func
    arity = length(argsExp)
    body = gen_body(bodyExp, __CALLER__.module)
    pfName = partialfunc_name(name)
    args = gen_args(argsExp, __CALLER__.module)

    quote bind_quoted: [name: name, arity: arity, body: Macro.escape(body), map: mapExp, pfName: pfName, args: Macro.escape(args)] do
      # register layered func
      if @layeredFunc[name] != arity do
        @layeredFunc {name, arity}
      end

      # defp partialFunc in Caller module
      layer = {:%{}, [], Map.to_list(map)}
      partialFuncAST = {:defp, [context: __MODULE__, import: Kernel],
        [{pfName, [context: __MODULE__], List.insert_at(args, 0, layer)}, [do: body]]}
      Module.eval_quoted __MODULE__, partialFuncAST
    end
  end


  defp partialfunc_name(funcName) do
    String.to_atom("_partial_" <> Atom.to_string(funcName))
  end

  defp gen_args(args, module) do
    Enum.map(args, fn(arg) -> _gen_arg(arg, module) end)
  end
  defp _gen_arg(atom, _) when is_atom(atom), do: atom
  defp _gen_arg(num, _) when is_number(num), do: num
  defp _gen_arg({name, _, _}, module), do: {name, [], module}
  defp _gen_arg(tuple, module) when is_tuple(tuple), do: tuple

  defp gen_body(expression, module) do
    case expression do
      {:__block__, meta, list} ->
        trList = list |> Enum.map(&(translate(&1, module)))
        {:__block__, meta, trList}
      tuple -> translate(tuple, module)
    end
  end

  defp translate(atom, _) when is_atom(atom), do: atom
  defp translate(tuple, module) when is_tuple(tuple) do
    case tuple do
      # make tupple of size = 2
      {t1, t2} when is_tuple(t1) and is_tuple(t2) ->
        {translate(t1, module), translate(t2, module)}
      # variable
      {atom, _, nil} when is_atom(atom) -> {atom, [], module}
      # apply function
      {atom, _, list} when is_atom(atom) and is_list(list) ->
        {atom, [context: module, import: Kernel], translate(list, module)}
      # inner tuple
      {tp, _, nil} when is_tuple(tp) ->
        {translate(tp, module), [context: module, import: Kernel], []}
      {tp, _, list} when is_tuple(tp) and is_list(list) ->
        {translate(tp, module), [context: module, import: Kernel], translate(list, module)}
      # other
      tuple -> tuple
    end
  end
  defp translate(list, module) when is_list(list) do
    list |> Enum.map(&(translate(&1, module)))
  end
  defp translate(any, _), do: any

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
      {String.to_atom("var" <> Integer.to_string(x)), [], module}
    end)
  end
end
