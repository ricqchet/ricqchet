defmodule RicqchetWeb.PublishControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.Batches
  alias Ricqchet.Messages

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  setup %{conn: conn} do
    {:ok, %{tenant: tenant, api_key: api_key}} = create_tenant_with_api_key()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{api_key.api_key}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, tenant: tenant, api_key: api_key}
  end

  describe "create/2 without batching" do
    test "publishes a message", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> post("/v1/publish", ~s({"event": "test"}))

      assert json_response(conn, 202)["message_id"]
    end

    test "publishes with delay header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> put_req_header("ricqchet-delay", "30s")
        |> post("/v1/publish", ~s({"event": "test"}))

      response = json_response(conn, 202)
      message = Messages.get!(response["message_id"])
      assert message.status == "pending"
    end

    test "returns 401 without auth header", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> post("/v1/publish", ~s({"event": "test"}))

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 422 when destination header is missing", %{conn: conn} do
      conn = post(conn, "/v1/publish", ~s({"event": "test"}))

      assert json_response(conn, 422)["error"] == "validation_error"
      assert json_response(conn, 422)["message"] =~ "Ricqchet-Destination or Ricqchet-Fan-Out"
    end

    test "returns 422 for invalid destination url", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-destination", "not-a-url")
        |> post("/v1/publish", ~s({"event": "test"}))

      assert json_response(conn, 422)["error"] == "validation_error"
    end

    test "returns 422 for private IP destination", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-destination", "http://192.168.1.1/api")
        |> post("/v1/publish", ~s({"event": "test"}))

      assert json_response(conn, 422)["error"] == "validation_error"
      assert json_response(conn, 422)["message"] =~ "blocked IP"
    end
  end

  describe "create/2 with batching" do
    # BatchCollector is now a stateless module, no setup needed

    test "publishes message to a batch", %{conn: conn, tenant: tenant} do
      conn =
        conn
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> put_req_header("ricqchet-batch-key", "order-events")
        |> post("/v1/publish", ~s({"event": "order.created"}))

      response = json_response(conn, 202)
      message = Messages.get!(response["message_id"])

      assert message.batch_id != nil
      batch = Batches.get(message.batch_id)
      assert batch.batch_key == "order-events"
      assert batch.tenant_id == tenant.id
    end

    test "groups messages with same batch key", %{conn: conn} do
      # First message
      conn1 =
        conn
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> put_req_header("ricqchet-batch-key", "order-events")
        |> post("/v1/publish", ~s({"event": "first"}))

      response1 = json_response(conn1, 202)
      msg1 = Messages.get!(response1["message_id"])

      # Second message (need fresh conn)
      auth_header =
        conn
        |> get_req_header("authorization")
        |> List.first()

      conn2 =
        build_conn()
        |> put_req_header("authorization", auth_header)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> put_req_header("ricqchet-batch-key", "order-events")
        |> post("/v1/publish", ~s({"event": "second"}))

      response2 = json_response(conn2, 202)
      msg2 = Messages.get!(response2["message_id"])

      # Both should be in the same batch
      assert msg1.batch_id == msg2.batch_id
    end

    test "respects custom batch size header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> put_req_header("ricqchet-batch-key", "order-events")
        |> put_req_header("ricqchet-batch-size", "50")
        |> post("/v1/publish", ~s({"event": "test"}))

      response = json_response(conn, 202)
      message = Messages.get!(response["message_id"])

      batch = Batches.get(message.batch_id)
      assert batch.max_size == 50
    end

    test "respects custom batch timeout header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> put_req_header("ricqchet-batch-key", "order-events")
        |> put_req_header("ricqchet-batch-timeout", "30")
        |> post("/v1/publish", ~s({"event": "test"}))

      response = json_response(conn, 202)
      message = Messages.get!(response["message_id"])

      batch = Batches.get(message.batch_id)
      assert batch.timeout_seconds == 30
    end

    test "creates separate batches for different destinations", %{conn: conn} do
      # First message to api1
      conn1 =
        conn
        |> put_req_header("ricqchet-destination", "https://example.com/api1")
        |> put_req_header("ricqchet-batch-key", "events")
        |> post("/v1/publish", ~s({"event": "first"}))

      response1 = json_response(conn1, 202)
      msg1 = Messages.get!(response1["message_id"])

      # Second message to api2 (need fresh conn)
      auth_header =
        conn
        |> get_req_header("authorization")
        |> List.first()

      conn2 =
        build_conn()
        |> put_req_header("authorization", auth_header)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("ricqchet-destination", "https://example.com/api2")
        |> put_req_header("ricqchet-batch-key", "events")
        |> post("/v1/publish", ~s({"event": "second"}))

      response2 = json_response(conn2, 202)
      msg2 = Messages.get!(response2["message_id"])

      # Should be in different batches
      assert msg1.batch_id != msg2.batch_id
    end

    test "forwards headers to batch", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> put_req_header("ricqchet-batch-key", "order-events")
        |> put_req_header("ricqchet-forward-x-custom", "custom-value")
        |> post("/v1/publish", ~s({"event": "test"}))

      response = json_response(conn, 202)
      message = Messages.get!(response["message_id"])

      assert message.headers["x-custom"] == "custom-value"
    end
  end

  describe "create/2 with fan-out" do
    test "creates multiple messages for fan-out destinations", %{conn: conn} do
      conn =
        conn
        |> put_req_header(
          "ricqchet-fan-out",
          "https://api1.example.com/webhook, https://api2.example.com/webhook, https://api3.example.com/webhook"
        )
        |> post("/v1/publish", ~s({"event": "test"}))

      response = json_response(conn, 202)
      assert is_list(response["message_ids"])
      assert length(response["message_ids"]) == 3

      # Verify each message was created with correct destination
      destinations =
        response["message_ids"]
        |> Enum.map(fn id -> Messages.get!(id).destination_url end)
        |> Enum.sort()

      assert destinations == [
               "https://api1.example.com/webhook",
               "https://api2.example.com/webhook",
               "https://api3.example.com/webhook"
             ]
    end

    test "all fan-out messages share the same payload", %{conn: conn} do
      conn =
        conn
        |> put_req_header(
          "ricqchet-fan-out",
          "https://api1.example.com/webhook, https://api2.example.com/webhook"
        )
        |> post("/v1/publish", ~s({"event": "broadcast"}))

      response = json_response(conn, 202)
      messages = Enum.map(response["message_ids"], &Messages.get!/1)

      # All messages should have the same payload
      payloads = Enum.map(messages, & &1.payload)
      [first_payload | rest] = payloads
      assert Enum.all?(rest, &(&1 == first_payload))
      assert first_payload =~ "broadcast"
    end

    test "returns 422 when using both destination and fan-out", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-destination", "https://example.com/api")
        |> put_req_header(
          "ricqchet-fan-out",
          "https://api1.example.com, https://api2.example.com"
        )
        |> post("/v1/publish", ~s({"event": "test"}))

      assert json_response(conn, 422)["error"] == "validation_error"
      assert json_response(conn, 422)["message"] =~ "Cannot use both"
    end

    test "returns 422 when using fan-out with batching", %{conn: conn} do
      conn =
        conn
        |> put_req_header(
          "ricqchet-fan-out",
          "https://api1.example.com, https://api2.example.com"
        )
        |> put_req_header("ricqchet-batch-key", "my-batch")
        |> post("/v1/publish", ~s({"event": "test"}))

      assert json_response(conn, 422)["error"] == "validation_error"
      assert json_response(conn, 422)["message"] =~ "cannot be used with"
    end

    test "returns 422 for invalid fan-out url", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-fan-out", "https://api1.example.com, not-a-url")
        |> post("/v1/publish", ~s({"event": "test"}))

      assert json_response(conn, 422)["error"] == "validation_error"
      assert json_response(conn, 422)["message"] =~ "Invalid fan-out URL"
    end

    test "returns 422 for empty fan-out header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("ricqchet-fan-out", "")
        |> post("/v1/publish", ~s({"event": "test"}))

      assert json_response(conn, 422)["error"] == "validation_error"
      assert json_response(conn, 422)["message"] =~ "cannot be empty"
    end

    test "applies delay to all fan-out messages", %{conn: conn} do
      conn =
        conn
        |> put_req_header(
          "ricqchet-fan-out",
          "https://api1.example.com/webhook, https://api2.example.com/webhook"
        )
        |> put_req_header("ricqchet-delay", "30s")
        |> post("/v1/publish", ~s({"event": "test"}))

      response = json_response(conn, 202)
      messages = Enum.map(response["message_ids"], &Messages.get!/1)

      # All messages should have same scheduled delay
      assert Enum.all?(messages, &(&1.status == "pending"))
    end
  end
end
