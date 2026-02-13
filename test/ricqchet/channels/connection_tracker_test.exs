defmodule Ricqchet.Channels.ConnectionTrackerTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Channels.ConnectionTracker

  describe "track_connect/2" do
    test "allows connections without limit" do
      app_id = Ecto.UUID.generate()

      assert :ok = ConnectionTracker.track_connect(app_id)
      assert :ok = ConnectionTracker.track_connect(app_id)
      assert ConnectionTracker.get_count(app_id) == 2

      ConnectionTracker.track_disconnect(app_id)
      ConnectionTracker.track_disconnect(app_id)
    end

    test "enforces connection limit" do
      app_id = Ecto.UUID.generate()

      assert :ok = ConnectionTracker.track_connect(app_id, 2)
      assert :ok = ConnectionTracker.track_connect(app_id, 2)
      assert :limit_reached = ConnectionTracker.track_connect(app_id, 2)

      ConnectionTracker.track_disconnect(app_id)
      ConnectionTracker.track_disconnect(app_id)
    end

    test "allows connection after disconnect frees slot" do
      app_id = Ecto.UUID.generate()

      assert :ok = ConnectionTracker.track_connect(app_id, 1)
      assert :limit_reached = ConnectionTracker.track_connect(app_id, 1)

      ConnectionTracker.track_disconnect(app_id)
      assert :ok = ConnectionTracker.track_connect(app_id, 1)

      ConnectionTracker.track_disconnect(app_id)
    end
  end

  describe "track_disconnect/1" do
    test "decrements count" do
      app_id = Ecto.UUID.generate()

      ConnectionTracker.track_connect(app_id)
      ConnectionTracker.track_connect(app_id)
      assert ConnectionTracker.get_count(app_id) == 2

      ConnectionTracker.track_disconnect(app_id)
      assert ConnectionTracker.get_count(app_id) == 1

      ConnectionTracker.track_disconnect(app_id)
      assert ConnectionTracker.get_count(app_id) == 0
    end

    test "does not go below zero" do
      app_id = Ecto.UUID.generate()

      ConnectionTracker.track_disconnect(app_id)
      assert ConnectionTracker.get_count(app_id) == 0
    end
  end

  describe "get_count/1" do
    test "returns 0 for unknown application" do
      assert ConnectionTracker.get_count(Ecto.UUID.generate()) == 0
    end
  end
end
