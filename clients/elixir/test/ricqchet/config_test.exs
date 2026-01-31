defmodule Ricqchet.ConfigTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Config

  describe "resolve/1" do
    test "returns string values directly" do
      assert Config.resolve("direct_value") == "direct_value"
    end

    test "resolves system env tuple" do
      System.put_env("RICQCHET_TEST_KEY", "env_value")
      assert Config.resolve({:system, "RICQCHET_TEST_KEY"}) == "env_value"
      System.delete_env("RICQCHET_TEST_KEY")
    end

    test "returns nil for unset env var" do
      assert Config.resolve({:system, "RICQCHET_UNSET_VAR"}) == nil
    end

    test "returns nil for nil input" do
      assert Config.resolve(nil) == nil
    end
  end
end
