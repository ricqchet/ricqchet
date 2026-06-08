defmodule Ricqchet.ChannelsTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Channels

  describe "validate_channel_name/1" do
    test "accepts alphanumeric, dash, and underscore names" do
      assert Channels.validate_channel_name("chat-room") == :ok
      assert Channels.validate_channel_name("room_42") == :ok
      assert Channels.validate_channel_name("Room1") == :ok
    end

    test "accepts type-prefixed names" do
      assert Channels.validate_channel_name("private-orders") == :ok
      assert Channels.validate_channel_name("presence-lobby") == :ok
    end

    test "accepts hierarchical dotted names" do
      assert Channels.validate_channel_name("orders.us.west") == :ok
      assert Channels.validate_channel_name("a.b.c.d") == :ok
    end

    test "accepts a name at the maximum length" do
      name = String.duplicate("a", 164)
      assert Channels.validate_channel_name(name) == :ok
    end

    test "rejects a name over the maximum length" do
      name = String.duplicate("a", 165)
      assert {:error, _} = Channels.validate_channel_name(name)
    end

    test "rejects an empty name" do
      assert {:error, _} = Channels.validate_channel_name("")
    end

    test "rejects names with disallowed characters" do
      assert {:error, _} = Channels.validate_channel_name("invalid name!")
      # ":" must stay disallowed so a name is always a single internal-topic segment.
      assert {:error, _} = Channels.validate_channel_name("channels:bad")
      assert {:error, _} = Channels.validate_channel_name("a/b")
    end

    test "rejects the reserved \"phoenix\" name" do
      assert {:error, reason} = Channels.validate_channel_name("phoenix")
      assert reason =~ "reserved"
    end

    test "rejects degenerate names with no alphanumeric character" do
      assert {:error, _} = Channels.validate_channel_name(".")
      assert {:error, _} = Channels.validate_channel_name("..")
      assert {:error, _} = Channels.validate_channel_name("--")
      assert {:error, _} = Channels.validate_channel_name("__")
    end

    test "rejects non-string input" do
      assert {:error, _} = Channels.validate_channel_name(nil)
      assert {:error, _} = Channels.validate_channel_name(123)
    end
  end
end
