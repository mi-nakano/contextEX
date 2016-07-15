defmodule ContextEXTest do
  use ExUnit.Case
  doctest ContextEX

  defmodule Caller do
    use ContextEX

    def start() do
      spawn(fn ->
        initLayer
        routine
      end)
    end

    def routine() do
      receive do
        {:activate, map} ->
          activateLayer(map)
          routine
        {:getLayer, caller} ->
          send caller, getActiveLayers
          routine
        {:func, caller} ->
          send caller, func
          routine
        {:end, caller} -> send caller, :end
      end
    end

    deflf func(), %{:categoryA => :layer1, :categoryB => :layer2}, do: 2
    deflf func(), %{:categoryB => :layer3}, do: 3
    deflf func(), %{:categoryA => :layer1}, do: 1
    deflf func(), %{}, do: 0
  end


  test "layer test" do
    p = Caller.start
    send p, {:getLayer, self}
    receive do
      result -> assert result = %{}
    end

    send p, {:activate, %{:categoryA => :layer1}}
    send p, {:getLayer, self}
    receive do
      result -> assert result = %{:categoryA => :layer1}
    end

    send p, {:activate, %{:categoryB => :layer2}}
    send p, {:getLayer, self}
    receive do
      result -> assert result = %{:categoryA => :layer1, :categoryB => :layer2}
    end

    send p, {:activate, %{:categoryB => :layer3}}
    send p, {:getLayer, self}
    receive do
      result -> assert result = %{:categoryA => :layer1, :categoryB => :layer3}
    end

    send p, {:end, self}
    receive do
      :end -> IO.puts "end"
    end
  end

  test "spawn test" do
    p1 = Caller.start
    send p1, {:activate, %{:categoryA => :layer1}}
    send p1, {:getLayer, self}
    receive do
      result -> assert result = %{:categoryA => :layer1}
    end

    p2 = Caller.start
    send p2, {:activate, %{:categoryA => :layer2}}
    send p2, {:getLayer, self}
    receive do
      result -> assert result = %{:categoryA => :layer2}
    end

    send p1, {:getLayer, self}
    receive do
      result -> assert result = %{:categoryA => :layer1}
    end
  end

  test "layered function test" do
    p = Caller.start
    send p, {:func, self}
    receive do
      result -> assert result == 0
    end

    send p, {:activate, %{:categoryA => :layer1}}
    send p, {:func, self}
    receive do
      result -> assert result == 1
    end

    send p, {:activate, %{:categoryB => :layer2}}
    send p, {:func, self}
    receive do
      result -> assert result == 2
    end

    send p, {:activate, %{:categoryB => :layer3}}
    send p, {:func, self}
    receive do
      result -> assert result == 3
    end
  end
end
