defmodule Ricqchet.Channels.SubscriberTrackerTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Channels.SubscriberTracker

  setup do
    app_id = Ecto.UUID.generate()
    %{app_id: app_id}
  end

  describe "track_join/2" do
    test "returns :first_subscriber on first join", %{app_id: app_id} do
      assert :first_subscriber = SubscriberTracker.track_join(app_id, "chat-room")
    end

    test "returns :ok on subsequent joins", %{app_id: app_id} do
      SubscriberTracker.track_join(app_id, "chat-room2")
      assert :ok = SubscriberTracker.track_join(app_id, "chat-room2")
    end

    test "increments subscriber count", %{app_id: app_id} do
      SubscriberTracker.track_join(app_id, "counter-test")
      SubscriberTracker.track_join(app_id, "counter-test")
      SubscriberTracker.track_join(app_id, "counter-test")
      assert SubscriberTracker.get_count(app_id, "counter-test") == 3
    end
  end

  describe "track_leave/2" do
    test "returns :last_subscriber when count reaches 0", %{app_id: app_id} do
      SubscriberTracker.track_join(app_id, "leave-test")
      assert :last_subscriber = SubscriberTracker.track_leave(app_id, "leave-test")
    end

    test "returns :ok when subscribers remain", %{app_id: app_id} do
      SubscriberTracker.track_join(app_id, "leave-test2")
      SubscriberTracker.track_join(app_id, "leave-test2")
      assert :ok = SubscriberTracker.track_leave(app_id, "leave-test2")
    end

    test "does not go below 0", %{app_id: app_id} do
      SubscriberTracker.track_leave(app_id, "nonexistent")
      assert SubscriberTracker.get_count(app_id, "nonexistent") == 0
    end
  end

  describe "get_count/2" do
    test "returns 0 for unknown channel", %{app_id: app_id} do
      assert SubscriberTracker.get_count(app_id, "unknown") == 0
    end

    test "returns current count", %{app_id: app_id} do
      SubscriberTracker.track_join(app_id, "count-test")
      SubscriberTracker.track_join(app_id, "count-test")
      assert SubscriberTracker.get_count(app_id, "count-test") == 2
    end
  end

  describe "list_active/1" do
    test "returns empty list when no channels", %{app_id: app_id} do
      assert SubscriberTracker.list_active(app_id) == []
    end

    test "returns active channels with counts", %{app_id: app_id} do
      SubscriberTracker.track_join(app_id, "room-a")
      SubscriberTracker.track_join(app_id, "room-a")
      SubscriberTracker.track_join(app_id, "room-b")

      active = SubscriberTracker.list_active(app_id)
      active_map = Map.new(active)

      assert active_map["room-a"] == 2
      assert active_map["room-b"] == 1
    end

    test "does not return channels from other applications", %{app_id: app_id} do
      other_app_id = Ecto.UUID.generate()
      SubscriberTracker.track_join(other_app_id, "other-room")
      SubscriberTracker.track_join(app_id, "my-room")

      active = SubscriberTracker.list_active(app_id)
      names = Enum.map(active, &elem(&1, 0))

      assert "my-room" in names
      refute "other-room" in names
    end

    test "removes channels with 0 subscribers", %{app_id: app_id} do
      SubscriberTracker.track_join(app_id, "temp-room")
      SubscriberTracker.track_leave(app_id, "temp-room")

      assert SubscriberTracker.list_active(app_id) == []
    end
  end
end
