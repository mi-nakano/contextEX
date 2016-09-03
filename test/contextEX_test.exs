defmodule ContextEXTest do
  use ExUnit.Case
  doctest ContextEX
  import ContextEX

  defmodule Caller do
    use ContextEX
    @context1 %{:categoryA => :layer1}

    def start(groupName \\ nil) do
      spawn(fn ->
        init_context(groupName)
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
    deflf func(), @context1, do: 1 # enable @
    deflf func(), do: 0
  end


  test "layer" do
    context1 = %{:categoryA => :layer1}
    context2 = %{:categoryB => :layer2}
    context3 = %{:categoryB => :layer3}

    p = Caller.start
    Process.sleep 100
    assert get_activelayers(p) == %{}

    activate_layer(p, context1)
    Process.sleep 100
    assert get_activelayers(p) == context1

    activate_layer(p, context2)
    Process.sleep 100
    context4 = Map.merge(context1, context2)
    assert get_activelayers(p) == context4

    activate_layer(p, context3)
    Process.sleep 100
    assert get_activelayers(p) == Map.merge(context4, context3)
  end

  test "spawn" do
    context1 = %{:categoryA => :layer1}
    p1 = Caller.start
    Process.sleep 100
    activate_layer(p1, context1)
    assert get_activelayers(p1) == context1

    context2 = %{:categoryA => :layer2}
    p2 = Caller.start
    Process.sleep 100
    activate_layer(p2, context2)
    assert get_activelayers(p2) == context2
    assert get_activelayers(p1) == context1
  end

  test "layered function" do
    p = Caller.start
    send p, {:func, self}
    assert_receive 0

    activate_layer(p, %{:categoryA => :layer1})
    send p, {:func, self}
    assert_receive 1

    activate_layer(p, %{:categoryB => :layer2})
    send p, {:func, self}
    assert_receive 2

    activate_layer(p, %{:categoryB => :layer3})
    send p, {:func, self}
    assert_receive 3
  end

  test "group activation" do
    p1 = Caller.start(:groupA)
    p2 = Caller.start(:groupA)
    p3 = Caller.start(:groupB)
    Process.sleep 100

    activate_group(:groupA, %{:categoryA => :layer1})
    Process.sleep 100
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
    deflf f({1, 2}), do: 0
    deflf f(struct), do: {struct.name, struct.value}
  end

  test "Match" do
    pid = MatchTest.start(self)
    send pid, 1
    assert_receive 1

    send pid, :atom
    assert_receive :atom

    send pid, {1, 2}
    assert_receive 0

    send pid, %MyStruct{name: :n, value: :val}
    assert_receive {:n, :val}
  end
end
