defmodule Ricqchet.Client.HTTPTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Client.HTTP

  setup do
    bypass = Bypass.open()

    config = %{
      base_url: "http://localhost:#{bypass.port}",
      api_key: "test_api_key",
      timeout: 5000
    }

    {:ok, bypass: bypass, config: config}
  end

  describe "publish/4" do
    test "publishes a message successfully", %{bypass: bypass, config: config} do
      message_id = "550e8400-e29b-41d4-a716-446655440000"

      Bypass.expect_once(bypass, "POST", "/v1/publish", fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test_api_key"]
        assert Plug.Conn.get_req_header(conn, "ricqchet-destination") == ["https://example.com"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"event" => "test"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(202, Jason.encode!(%{message_id: message_id}))
      end)

      assert {:ok, %{message_id: ^message_id}} =
               HTTP.publish(config, "https://example.com", %{event: "test"}, [])
    end

    test "includes delay header when provided", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/publish", fn conn ->
        assert Plug.Conn.get_req_header(conn, "ricqchet-delay") == ["5m"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(202, Jason.encode!(%{message_id: "test-id"}))
      end)

      HTTP.publish(config, "https://example.com", %{event: "test"}, delay: "5m")
    end

    test "includes dedup headers when provided", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/publish", fn conn ->
        assert Plug.Conn.get_req_header(conn, "ricqchet-dedup-key") == ["order-123"]
        assert Plug.Conn.get_req_header(conn, "ricqchet-dedup-ttl") == ["3600"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(202, Jason.encode!(%{message_id: "test-id"}))
      end)

      HTTP.publish(config, "https://example.com", %{event: "test"},
        dedup_key: "order-123",
        dedup_ttl: 3600
      )
    end

    test "includes forward headers when provided", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/publish", fn conn ->
        assert Plug.Conn.get_req_header(conn, "ricqchet-forward-x-custom") == ["value"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(202, Jason.encode!(%{message_id: "test-id"}))
      end)

      HTTP.publish(config, "https://example.com", %{event: "test"},
        forward_headers: %{"x-custom" => "value"}
      )
    end

    test "returns error for 422 response", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/publish", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          422,
          Jason.encode!(%{error: "validation_error", message: "Invalid URL"})
        )
      end)

      assert {:error, error} = HTTP.publish(config, "invalid", %{event: "test"}, [])
      assert error.type == :validation_error
      assert error.status == 422
    end

    test "returns error for 401 response", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/publish", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, Jason.encode!(%{error: "unauthorized"}))
      end)

      assert {:error, error} = HTTP.publish(config, "https://example.com", %{event: "test"}, [])
      assert error.type == :unauthorized
    end
  end

  describe "publish_fan_out/4" do
    test "publishes to multiple destinations", %{bypass: bypass, config: config} do
      message_ids = ["id1", "id2", "id3"]

      Bypass.expect_once(bypass, "POST", "/v1/publish", fn conn ->
        [fan_out] = Plug.Conn.get_req_header(conn, "ricqchet-fan-out")
        assert fan_out =~ "https://a.example.com"
        assert fan_out =~ "https://b.example.com"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(202, Jason.encode!(%{message_ids: message_ids}))
      end)

      assert {:ok, %{message_ids: ^message_ids}} =
               HTTP.publish_fan_out(
                 config,
                 ["https://a.example.com", "https://b.example.com"],
                 %{event: "broadcast"},
                 []
               )
    end
  end

  describe "get_message/2" do
    test "gets message status", %{bypass: bypass, config: config} do
      message_id = "test-message-id"

      Bypass.expect_once(bypass, "GET", "/v1/messages/#{message_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            id: message_id,
            status: "delivered",
            attempts: 1
          })
        )
      end)

      assert {:ok, message} = HTTP.get_message(config, message_id)
      assert message["id"] == message_id
      assert message["status"] == "delivered"
    end

    test "returns not_found for 404", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/v1/messages/unknown", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(%{error: "not_found"}))
      end)

      assert {:error, :not_found} = HTTP.get_message(config, "unknown")
    end
  end

  describe "cancel_message/2" do
    test "cancels a pending message", %{bypass: bypass, config: config} do
      message_id = "test-message-id"

      Bypass.expect_once(bypass, "DELETE", "/v1/messages/#{message_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{cancelled: true}))
      end)

      assert {:ok, %{"cancelled" => true}} = HTTP.cancel_message(config, message_id)
    end

    test "returns already_dispatched for 409", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "DELETE", "/v1/messages/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(409, Jason.encode!(%{error: "already_dispatched"}))
      end)

      assert {:error, :already_dispatched} = HTTP.cancel_message(config, "test")
    end
  end

  describe "get_signing_secret/1" do
    test "gets the signing secret", %{bypass: bypass, config: config} do
      secret = :crypto.strong_rand_bytes(32)
      encoded = Base.encode64(secret)

      Bypass.expect_once(bypass, "GET", "/v1/signing-secret", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{signing_secret: encoded}))
      end)

      assert {:ok, ^secret} = HTTP.get_signing_secret(config)
    end
  end
end
