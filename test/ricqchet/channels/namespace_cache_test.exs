defmodule Ricqchet.Channels.NamespaceCacheTest do
  use ExUnit.Case, async: false

  alias Ricqchet.Channels.NamespaceCache

  setup do
    NamespaceCache.invalidate_all()
    :ok
  end

  describe "get/put" do
    test "returns :miss for uncached entry" do
      assert :miss = NamespaceCache.get("app1", "channel1")
    end

    test "returns cached value after put" do
      NamespaceCache.put("app1", "channel1", %{pattern: "test"})
      assert {:ok, %{pattern: "test"}} = NamespaceCache.get("app1", "channel1")
    end

    test "caches nil values" do
      NamespaceCache.put("app1", "no-match", nil)
      assert {:ok, nil} = NamespaceCache.get("app1", "no-match")
    end

    test "different app_id+channel combinations are independent" do
      NamespaceCache.put("app1", "channel1", :value1)
      NamespaceCache.put("app2", "channel1", :value2)

      assert {:ok, :value1} = NamespaceCache.get("app1", "channel1")
      assert {:ok, :value2} = NamespaceCache.get("app2", "channel1")
    end
  end

  describe "invalidate/1" do
    test "removes all entries for an application" do
      NamespaceCache.put("app1", "channel1", :val1)
      NamespaceCache.put("app1", "channel2", :val2)
      NamespaceCache.put("app2", "channel1", :val3)

      NamespaceCache.invalidate("app1")

      assert :miss = NamespaceCache.get("app1", "channel1")
      assert :miss = NamespaceCache.get("app1", "channel2")
      assert {:ok, :val3} = NamespaceCache.get("app2", "channel1")
    end
  end

  describe "invalidate_all/0" do
    test "clears all entries" do
      NamespaceCache.put("app1", "channel1", :val1)
      NamespaceCache.put("app2", "channel2", :val2)

      NamespaceCache.invalidate_all()

      assert :miss = NamespaceCache.get("app1", "channel1")
      assert :miss = NamespaceCache.get("app2", "channel2")
    end
  end
end
