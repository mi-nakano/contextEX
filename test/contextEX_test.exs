defmodule ContextEXTest do
  use ExUnit.Case
  doctest ContextEX
  import ContextEX

  defmodule TestMod do
    use ContextEX
    @context1 %{:categoryA => :layer1}

    def start(groupName \\ nil) do
      pid = spawn(fn ->
        init_context(groupName)
        routine
      end)
      Process.sleep 100
      pid
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
    deflf func(), @context1, do: 1 # enable @
    deflf func(), do: 0
  end


  test "layer" do
    context1 = %{:categoryA => :layer1}
    context2 = %{:categoryB => :layer2}
    context3 = %{:categoryB => :layer3}

    p = TestMod.start
    assert get_activelayers(p) == %{}

    assert call_activate_layer(p, context1) == context1

    context4 = Map.merge(context1, context2)
    assert call_activate_layer(p, context2) == context4

    assert call_activate_layer(p, context3) == Map.merge(context4, context3)
  end

  test "spawn" do
    context1 = %{:categoryA => :layer1}
    p1 = TestMod.start
    assert call_activate_layer(p1, context1) == context1

    context2 = %{:categoryA => :layer2}
    p2 = TestMod.start
    assert call_activate_layer(p2, context2) == context2
    assert get_activelayers(p1) == context1
  end

  test "layered function" do
    p = TestMod.start
    send p, {:func, self}
    assert_receive 0

    cast_activate_layer(p, %{:categoryA => :layer1})
    send p, {:func, self}
    assert_receive 1

    cast_activate_layer(p, %{:categoryB => :layer2})
    send p, {:func, self}
    assert_receive 2

    cast_activate_layer(p, %{:categoryB => :layer3})
    send p, {:func, self}
    assert_receive 3
  end

  test "group activation" do
    p1 = TestMod.start(:groupA)
    p2 = TestMod.start(:groupA)
    p3 = TestMod.start(:groupB)

    cast_activate_group(:groupA, %{:categoryA => :layer1})
    assert get_activelayers(p1) == %{:categoryA => :layer1}
    assert get_activelayers(p2) == %{:categoryA => :layer1}
    assert get_activelayers(p3) == %{}
  end


  defmodule MyStruct do
    defstruct name: "", value: ""
  end

  defmodule MatchTest do
    use ContextEX

    def start(pid) do
      spawn(fn ->
        init_context
        receive_ret(pid)
      end)
    end
    defp receive_ret(pid) do
      receive do
        arg -> send pid, f(arg)
      end
      receive_ret pid
    end

    deflf f(1), do: 1
    deflf f(:atom), do: :atom
    deflf f({x, y}), do: x + y
    deflf f([_head | tail]), do: tail
    deflf f(struct), do: {struct.name, struct.value}
  end

  test "Match" do
    pid = MatchTest.start(self)
    send pid, 1
    assert_receive 1

    send pid, :atom
    assert_receive :atom

    send pid, {1, 2}
    assert_receive 3

    send pid, [1, 2, 3]
    assert_receive [2, 3]

    send pid, %MyStruct{name: :n, value: :val}
    assert_receive {:n, :val}
  end

  test "Unregister" do
    pid = TestMod.start()
    context = %{:status => :normal}
    call_activate_layer(pid, context)
    assert context == get_activelayers(pid)
    send pid, {:end, self}
    Process.sleep 10
    assert nil == get_activelayers(pid)
  end
end
