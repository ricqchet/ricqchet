defmodule Ricqchet.ApiKeys.ScopeTest do
  use ExUnit.Case, async: true

  alias Ricqchet.ApiKeys.ApiKey
  alias Ricqchet.ApiKeys.Scope

  describe "scopes/0 and default/0" do
    test "lists the known scopes" do
      assert Scope.scopes() == ["relay", "subscribe"]
    end

    test "defaults to relay" do
      assert Scope.default() == "relay"
    end
  end

  describe "valid?/1" do
    test "accepts known scopes" do
      assert Scope.valid?("relay")
      assert Scope.valid?("subscribe")
    end

    test "rejects unknown values" do
      refute Scope.valid?("god")
      refute Scope.valid?(nil)
      refute Scope.valid?("")
    end
  end

  describe "can_relay?/1 (fail-closed)" do
    test "true only for an exact relay scope" do
      assert Scope.can_relay?("relay")
      assert Scope.can_relay?(%ApiKey{scope: "relay"})
    end

    test "false for subscribe" do
      refute Scope.can_relay?("subscribe")
      refute Scope.can_relay?(%ApiKey{scope: "subscribe"})
    end

    test "false for nil, missing, or unknown scope (no fail-open)" do
      refute Scope.can_relay?(nil)
      refute Scope.can_relay?(%ApiKey{scope: nil})
      refute Scope.can_relay?(%ApiKey{scope: "future-scope"})
      refute Scope.can_relay?(:relay)
    end
  end

  describe "can_subscribe?/1" do
    test "true for both scopes (relay is a superset of subscribe)" do
      assert Scope.can_subscribe?("relay")
      assert Scope.can_subscribe?("subscribe")
      assert Scope.can_subscribe?(%ApiKey{scope: "relay"})
      assert Scope.can_subscribe?(%ApiKey{scope: "subscribe"})
    end

    test "false for unknown scope" do
      refute Scope.can_subscribe?("nope")
      refute Scope.can_subscribe?(nil)
    end
  end
end
