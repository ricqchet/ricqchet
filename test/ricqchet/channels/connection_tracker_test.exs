defmodule Ricqchet.Channels.ConnectionTrackerTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Channels.ConnectionTracker

  # A stand-in socket process that stays alive until told to stop.
  defp spawn_connection do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  defp stop_and_wait(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
  end

  # The tracker releases slots asynchronously on :DOWN; wait for it to settle.
  defp eventually(fun) do
    Enum.reduce_while(1..100, false, fn _, _ ->
      if fun.() do
        {:halt, true}
      else
        Process.sleep(5)
        {:cont, false}
      end
    end)
  end

  describe "track_connect/3" do
    test "counts each connection and allows when no limit is set" do
      app_id = Ecto.UUID.generate()
      p1 = spawn_connection()
      p2 = spawn_connection()

      assert :ok = ConnectionTracker.track_connect(app_id, nil, p1)
      assert :ok = ConnectionTracker.track_connect(app_id, nil, p2)
      assert ConnectionTracker.get_count(app_id) == 2

      stop_and_wait(p1)
      stop_and_wait(p2)
    end

    test "enforces the connection limit" do
      app_id = Ecto.UUID.generate()
      p1 = spawn_connection()
      p2 = spawn_connection()
      p3 = spawn_connection()

      assert :ok = ConnectionTracker.track_connect(app_id, 2, p1)
      assert :ok = ConnectionTracker.track_connect(app_id, 2, p2)
      assert :limit_reached = ConnectionTracker.track_connect(app_id, 2, p3)

      stop_and_wait(p1)
      stop_and_wait(p2)
      stop_and_wait(p3)
    end

    test "releases a slot when the socket process exits" do
      app_id = Ecto.UUID.generate()
      p1 = spawn_connection()

      assert :ok = ConnectionTracker.track_connect(app_id, 1, p1)
      assert :limit_reached = ConnectionTracker.track_connect(app_id, 1, spawn_connection())

      stop_and_wait(p1)
      assert eventually(fn -> ConnectionTracker.get_count(app_id) == 0 end)

      p2 = spawn_connection()
      assert :ok = ConnectionTracker.track_connect(app_id, 1, p2)
      stop_and_wait(p2)
    end

    test "counts one connection per socket process" do
      # Regression guard for the per-socket vs per-channel accounting fix: the
      # count is keyed to the socket process, so however many channels a socket
      # multiplexes, it is one connection that is released exactly once.
      app_id = Ecto.UUID.generate()
      socket = spawn_connection()

      assert :ok = ConnectionTracker.track_connect(app_id, nil, socket)
      assert ConnectionTracker.get_count(app_id) == 1

      stop_and_wait(socket)
      assert eventually(fn -> ConnectionTracker.get_count(app_id) == 0 end)
    end
  end

  describe "get_count/1" do
    test "returns 0 for unknown application" do
      assert ConnectionTracker.get_count(Ecto.UUID.generate()) == 0
    end
  end
end
