defmodule ContextEX do
  @agentName ContextEXAgent
  @noneGroup :noneGroup

  defmacro __using__(options) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      Module.register_attribute __MODULE__, :layeredFunc, accumulate: true, persist: false
      Module.register_attribute __MODULE__, :requiredLayer, accumulate: true, persist: false

      Agent.start(fn -> %{} end, name: unquote(@agentName))
    end
  end

  defmacro __before_compile__(env) do
    attrs = Module.get_attribute(env.module, :layeredFunc)
    defList = attrs |> Enum.map(&(genGenericFunctionAST(&1, env.module)))

    # return AST
    {:__block__, [], defList}
  end

  defmacro initLayer(arg \\ nil) do
    quote do
      group = if unquote(arg) == nil do
        unquote(@noneGroup)
      else
        unquote(arg)
      end


      selfPid = self
      {:ok, layerPid} = Agent.start_link(fn -> %{} end)
      Agent.update(unquote(@agentName), fn(state) ->
        Map.put(state, {group, selfPid}, layerPid)
      end)
    end
  end

  defmacro getActiveLayers() do
    quote do
      selfPid = self
      {_, layerPid} = Agent.get(unquote(@agentName), fn(state) ->
        state |> Enum.find(fn(x) ->
          {{_, p}, _} = x
          p == selfPid
        end)
      end)
      Agent.get(layerPid, fn(state) -> state end)
    end
  end

  defmacro activateLayer(map) do
    quote do
      selfPid = self
      {_, layerPid} = Agent.get(unquote(@agentName), fn(state) ->
        state |> Enum.find(fn(x) ->
          {{_, p}, _} = x
          p == selfPid
        end)
      end)
      Agent.update(layerPid, fn(state) ->
        Map.merge(state, unquote(map))
      end)
    end
  end

  defmacro activateLayer(group, map) do
    quote do
      pids = Agent.get(unquote(@agentName), fn(state) ->
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

  defmacro isActive?(layer) do
    quote do
      map = getActiveLayers
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
    layerMap =
      case mapExp do
        %{} -> []
        {:%{}, _, []} -> []
        {:%{}, _, keywordList} -> keywordList
      end
    module = __CALLER__.module
    body = genBody(bodyExp, module)
    ast = {:defp, [context: module, import: Kernel],
            [genPartialFuncAST(func, layerMap, module),
             [do: body]]}

    quote bind_quoted: [name: name, arity: arity, layer: layerMap, ast: ast] do
      # register layered func
      if @layeredFunc[name] != arity do
        @layeredFunc {name, arity}
      end
      @requiredLayer {name, arity, layer}
      ast
    end
  end

  defp genPartialFuncAST(func, layerMap, module) do
    {funcName, _, argsExpression} = func
    args = genArgs(argsExpression, module)
    {partialFuncName(funcName), [context: module],
      # insert arg, which is activated layers
      List.insert_at(args, 0, genArgsLayer(layerMap))}
  end

  defp partialFuncName(funcName) do
    String.to_atom("_partial_" <> Atom.to_string(funcName))
  end

  defp genArgs(args, module) do
    Enum.map(args, fn(arg) ->
      case arg do
        atom when is_atom(atom) -> atom
        {name, _, _} -> {name, [], module}
      end
    end)
  end

  defp genArgsLayer(layerMap) do
    {:%{}, [], layerMap}
  end

  defp genBody(expression, module) do
    case expression do
      {:__block__, meta, list} ->
        trList = list |> Enum.map(&(translate(&1, module)))
        {:__block__, meta, trList}
      tupple -> translate(tupple, module)
    end
  end

  defp translate(tupple, module) do
    case tupple do
      {atom, _, nil} -> {atom, [], module}
      {atom, _, list} when is_list(list) ->
        {atom, [context: module, import: Kernel],
          list |> Enum.map(&(translate(&1, module)))}
      _ -> tupple
    end
  end

  defp genGenericFunctionAST({funcName, arity}, module) do
    args = genDummyArgs(arity, module)
    {:def, [context: module, import: Kernel],
      [{funcName, [context: module], args},
       [do:
         {:__block__, [],[
          {:=, [], [{:layer, [], module}, {:getActiveLayers, [], module}]},
          {partialFuncName(funcName), [context: module],
            # pass activated layers for first arg
            List.insert_at(args, 0, {:layer, [], module})}
         ]}]]}
  end

  defp genDummyArgs(0, _), do: []
  defp genDummyArgs(num, module) do
    Enum.map(1.. num, fn(x) ->
      {String.to_atom("var" <> Integer.to_string(x)), [], module}
    end)
  end
end
