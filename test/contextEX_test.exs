defmodule ContextEXTest do
  use ExUnit.Case
  doctest ContextEX
  import ContextEX

  defmodule Caller do
    use ContextEX
    @context1 %{:categoryA => :layer1}

    def start(groupName \\ nil) do
      spawn(fn ->
        initLayer(groupName)
        routine
      end)
    end

    def routine() do
      receive do
        {:func, caller} ->
          send caller, func
          routine
        {:end, caller} -> send caller, :end
      end
    end

    deflf func(), %{:categoryA => :layer1, :categoryB => :layer2}, do: 2
    deflf func(), %{:categoryB => :layer3}, do: 3
    deflf func(), @context1, do: 1
    deflf func(), do: 0
  end


  test "layer test" do
    p = Caller.start
    Process.sleep 100
    assert getActiveLayers(p) == %{}

    activateLayer(p, %{:categoryA => :layer1})
    Process.sleep 100
    assert getActiveLayers(p) == %{:categoryA => :layer1}

    activateLayer(p, %{:categoryB => :layer2})
    Process.sleep 100
    assert getActiveLayers(p) == %{:categoryA => :layer1, :categoryB => :layer2}

    activateLayer(p, %{:categoryB => :layer3})
    Process.sleep 100
    assert getActiveLayers(p) == %{:categoryA => :layer1, :categoryB => :layer3}
  end

  test "spawn test" do
    p1 = Caller.start
    Process.sleep 100
    activateLayer(p1, %{:categoryA => :layer1})
    assert getActiveLayers(p1) == %{:categoryA => :layer1}

    p2 = Caller.start
    Process.sleep 100
    activateLayer(p2, %{:categoryA => :layer2})
    assert getActiveLayers(p2) == %{:categoryA => :layer2}
    assert getActiveLayers(p1) == %{:categoryA => :layer1}
  end

  test "layered function test" do
    p = Caller.start
    send p, {:func, self}
    assert_receive 0

    activateLayer(p, %{:categoryA => :layer1})
    send p, {:func, self}
    assert_receive 1

    activateLayer(p, %{:categoryB => :layer2})
    send p, {:func, self}
    assert_receive 2

    activateLayer(p, %{:categoryB => :layer3})
    send p, {:func, self}
    assert_receive 3
  end

  test "group activation test" do
    p1 = Caller.start(:groupA)
    p2 = Caller.start(:groupA)
    p3 = Caller.start(:groupB)
    Process.sleep 100

    activateGroup(:groupA, %{:categoryA => :layer1})
    Process.sleep 100
    assert getActiveLayers(p1) == %{:categoryA => :layer1}
    assert getActiveLayers(p2) == %{:categoryA => :layer1}
    assert getActiveLayers(p3) == %{}
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
