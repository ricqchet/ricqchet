defmodule Ricqchet.Channels.ClientEventRateLimiterTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Channels.ClientEventRateLimiter

  describe "check_rate/3" do
    test "allows events within limit" do
      app_id = Ecto.UUID.generate()
      user_id = "user_#{System.unique_integer([:positive])}"

      assert :ok = ClientEventRateLimiter.check_rate(app_id, user_id, 5)
      assert :ok = ClientEventRateLimiter.check_rate(app_id, user_id, 5)
      assert :ok = ClientEventRateLimiter.check_rate(app_id, user_id, 5)
    end

    test "rejects events exceeding limit" do
      app_id = Ecto.UUID.generate()
      user_id = "user_#{System.unique_integer([:positive])}"

      for _ <- 1..3, do: ClientEventRateLimiter.check_rate(app_id, user_id, 3)

      assert :rate_limited = ClientEventRateLimiter.check_rate(app_id, user_id, 3)
    end

    test "tracks separately per user" do
      app_id = Ecto.UUID.generate()
      user_a = "user_a_#{System.unique_integer([:positive])}"
      user_b = "user_b_#{System.unique_integer([:positive])}"

      for _ <- 1..2, do: ClientEventRateLimiter.check_rate(app_id, user_a, 2)

      assert :rate_limited = ClientEventRateLimiter.check_rate(app_id, user_a, 2)
      assert :ok = ClientEventRateLimiter.check_rate(app_id, user_b, 2)
    end

    test "tracks separately per application" do
      app_a = Ecto.UUID.generate()
      app_b = Ecto.UUID.generate()
      user_id = "user_#{System.unique_integer([:positive])}"

      for _ <- 1..2, do: ClientEventRateLimiter.check_rate(app_a, user_id, 2)

      assert :rate_limited = ClientEventRateLimiter.check_rate(app_a, user_id, 2)
      assert :ok = ClientEventRateLimiter.check_rate(app_b, user_id, 2)
    end

    test "uses default limit of 10" do
      app_id = Ecto.UUID.generate()
      user_id = "user_#{System.unique_integer([:positive])}"

      for _ <- 1..10, do: ClientEventRateLimiter.check_rate(app_id, user_id)

      assert :rate_limited = ClientEventRateLimiter.check_rate(app_id, user_id)
    end
  end
end
