defmodule ContextEXTest do
  use ExUnit.Case
  doctest ContextEX

  defmodule Caller do
    use ContextEX

    def start(groupName \\ nil) do
      spawn(fn ->
        initLayer(groupName)
        routine
      end)
    end

    def routine() do
      receive do
        {:activate, map} ->
          activateLayer(map)
          routine
        {:activateGroup, groupName, map} ->
          activateLayer(groupName, map)
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
    deflf func(), do: 0
  end


  test "layer test" do
    p = Caller.start
    send p, {:getLayer, self}
    assert_receive %{}

    send p, {:activate, %{:categoryA => :layer1}}
    send p, {:getLayer, self}
    assert_receive %{:categoryA => :layer1}

    send p, {:activate, %{:categoryB => :layer2}}
    send p, {:getLayer, self}
    assert_receive %{:categoryA => :layer1, :categoryB => :layer2}

    send p, {:activate, %{:categoryB => :layer3}}
    send p, {:getLayer, self}
    assert_receive %{:categoryA => :layer1, :categoryB => :layer3}
  end

  test "spawn test" do
    p1 = Caller.start
    send p1, {:activate, %{:categoryA => :layer1}}
    send p1, {:getLayer, self}
    assert_receive %{:categoryA => :layer1}

    p2 = Caller.start
    send p2, {:activate, %{:categoryA => :layer2}}
    send p2, {:getLayer, self}
    assert_receive %{:categoryA => :layer2}

    send p1, {:getLayer, self}
    assert_receive %{:categoryA => :layer1}
  end

  test "layered function test" do
    p = Caller.start
    send p, {:func, self}
    assert_receive 0

    send p, {:activate, %{:categoryA => :layer1}}
    send p, {:func, self}
    assert_receive 1

    send p, {:activate, %{:categoryB => :layer2}}
    send p, {:func, self}
    assert_receive 2

    send p, {:activate, %{:categoryB => :layer3}}
    send p, {:func, self}
    assert_receive 3
  end

  test "group activation test" do
    p1 = Caller.start(:groupA)
    p2 = Caller.start(:groupA)
    p3 = Caller.start(:groupB)

    send p1, {:activateGroup, :groupA, %{:categoryA => :layer1}}
    send p1, {:getLayer, self}
    assert_receive %{:categoryA => :layer1}
    send p2, {:getLayer, self}
    assert_receive %{:categoryA => :layer1}
    send p3, {:getLayer, self}
    assert_receive %{}
  end


  defmodule MyStruct do
    defstruct name: "", value: ""
  end

  defmodule StructTest do
    use ContextEX

    def start(pid) do
      spawn(fn ->
        initLayer
        receive do
          struct -> send pid, f(struct)
        end
      end)
    end
    deflf f(struct) do
      {struct.name, struct.value}
    end
  end

  test "Struct test" do
    pid = StructTest.start(self)
    send pid, %MyStruct{name: :n, value: :val}
    #assert_receive 1
      assert_receive {:n, :val}
  end
end
