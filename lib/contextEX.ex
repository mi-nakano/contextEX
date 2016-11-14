defmodule ContextEX do
  @top_agent_name :ContextEXAgent
  @none_group :none_group

  @partial_prefix "_partial_"
  @arg_name "arg"

  defmacro __using__(_options) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      Module.register_attribute __MODULE__, :layered_function, accumulate: true, persist: false

      defp get_activelayers(), do: get_activelayers(self)
      defp cast_activate_layer(map), do: cast_activate_layer(self, map)
      defp is_active?(layer), do: is_active?(self, layer)
    end
  end

  defmacro __before_compile__(env) do
    attrs = Module.get_attribute(env.module, :layered_function)
    defList = attrs |> Enum.map(&(gen_genericfunction_ast(&1, env.module)))

    # return AST
    {:__block__, [], defList}
  end

  def start(_type, _args) do
    unless (is_pid :global.whereis_name(@top_agent_name)) do
      try do
        Agent.start(fn -> %{} end, [name: {:global, @top_agent_name}])
      rescue
        e -> e
      end
    end
  end

  defmacro init_context(arg \\ nil) do
    quote do
      with  self_pid = self,
            {:ok, layer_pid} = Agent.start_link(fn -> %{} end),
            top_agent = :global.whereis_name(unquote(@top_agent_name)),
            group = if(unquote(arg) == nil, do: nil, else: unquote(arg)),
      do:
            Agent.update(top_agent, fn(state) ->
              Map.put(state, {group, self_pid}, layer_pid)
            end)
    end
  end

  @doc """
  return nil when pid isn't registered
  """
  defmacro get_activelayers(pid) do
    quote do
      res =
        with  self_pid = unquote(pid),
              top_agent = :global.whereis_name(unquote(@top_agent_name)),
        do:
              Agent.get(top_agent, fn(state) ->
                state |> Enum.find(fn(x) ->
                  {{_, p}, _} = x
                  p == self_pid
                end)
              end)
      if res == nil do
        nil
      else
        {_, layer_pid} = res
        Agent.get(layer_pid, fn(state) -> state end)
      end
    end
  end

  @doc """
  return nil when pid isn't registered
  """
  defmacro cast_activate_layer(pid, map) do
    quote do
      res =
        with  self_pid = unquote(pid),
              top_agent = :global.whereis_name(unquote(@top_agent_name)),
        do:
              Agent.get(top_agent, fn(state) ->
                state |> Enum.find(fn(x) ->
                  {{_, p}, _} = x
                  p == self_pid
                end)
              end)
      if res == nil do
        nil
      else
        {_, layer_pid} = res
        Agent.update(layer_pid, fn(state) ->
          Map.merge(state, unquote(map))
        end)
      end
    end
  end

  defmacro cast_activate_group(group, map) do
    quote do
      top_agent = :global.whereis_name unquote(@top_agent_name)
      pids = Agent.get(top_agent, fn(state) ->
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

  defmacro deflf(func, do: body_exp) do
    quote do: deflf(unquote(func), %{}, do: unquote(body_exp))
  end

  defmacro deflf({name, meta, args_exp}, map_exp \\ %{}, do: body_exp) do
    new_definition =
      with  pf_name = partialfunc_name(name),
            new_args = List.insert_at(args_exp, 0, map_exp),
      do: {pf_name, meta, new_args}

    quote bind_quoted: [name: name, arity: length(args_exp), body: Macro.escape(body_exp), definition: Macro.escape(new_definition)] do
      # register layered function
      if @layered_function[name] != arity do
        @layered_function {name, arity}
      end

      # define partialFunc in Caller module
      Kernel.defp(unquote(definition)) do
        unquote(body)
      end
    end
  end


  defp partialfunc_name(func_name) do
    String.to_atom(@partial_prefix <> Atom.to_string(func_name))
  end

  defp gen_genericfunction_ast({func_name, arity}, module) do
    args = gen_dummy_args(arity, module)
    {:def, [context: module, import: Kernel],
      [{func_name, [context: module], args},
       [do:
         {:__block__, [],[
          {:=, [], [{:layer, [], module}, {:get_activelayers, [], module}]},
          {partialfunc_name(func_name), [context: module],
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
