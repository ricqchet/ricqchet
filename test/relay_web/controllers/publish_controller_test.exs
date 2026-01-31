defmodule RelayWeb.PublishControllerTest do
  use RelayWeb.ConnCase, async: false

  alias Relay.BatchCollector
  alias Relay.Batches
  alias Relay.Messages
  alias Relay.Tenants

  setup %{conn: conn} do
    {:ok, tenant} = Tenants.create_tenant(%{name: "Test Tenant"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tenant.api_key}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, tenant: tenant}
  end

  describe "create/2 without batching" do
    test "publishes a message", %{conn: conn} do
      conn = post(conn, "/v1/publish/https://example.com/api", ~s({"event": "test"}))

      assert json_response(conn, 202)["message_id"]
    end

    test "publishes with delay header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("relay-delay", "30s")
        |> post("/v1/publish/https://example.com/api", ~s({"event": "test"}))

      response = json_response(conn, 202)
      message = Messages.get!(response["message_id"])
      assert message.status == "pending"
    end

    test "returns 401 without auth header", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> post("/v1/publish/https://example.com/api", ~s({"event": "test"}))

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  describe "create/2 with batching" do
    setup do
      # Start BatchCollector for batch tests
      {:ok, pid} = BatchCollector.start_link([])

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      :ok
    end

    test "publishes message to a batch", %{conn: conn, tenant: tenant} do
      conn =
        conn
        |> put_req_header("relay-batch-key", "order-events")
        |> post("/v1/publish/https://example.com/api", ~s({"event": "order.created"}))

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
        |> put_req_header("relay-batch-key", "order-events")
        |> post("/v1/publish/https://example.com/api", ~s({"event": "first"}))

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
        |> put_req_header("relay-batch-key", "order-events")
        |> post("/v1/publish/https://example.com/api", ~s({"event": "second"}))

      response2 = json_response(conn2, 202)
      msg2 = Messages.get!(response2["message_id"])

      # Both should be in the same batch
      assert msg1.batch_id == msg2.batch_id
    end

    test "respects custom batch size header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("relay-batch-key", "order-events")
        |> put_req_header("relay-batch-size", "50")
        |> post("/v1/publish/https://example.com/api", ~s({"event": "test"}))

      response = json_response(conn, 202)
      message = Messages.get!(response["message_id"])

      batch = Batches.get(message.batch_id)
      assert batch.max_size == 50
    end

    test "respects custom batch timeout header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("relay-batch-key", "order-events")
        |> put_req_header("relay-batch-timeout", "30")
        |> post("/v1/publish/https://example.com/api", ~s({"event": "test"}))

      response = json_response(conn, 202)
      message = Messages.get!(response["message_id"])

      batch = Batches.get(message.batch_id)
      assert batch.timeout_seconds == 30
    end

    test "creates separate batches for different destinations", %{conn: conn} do
      # First message to api1
      conn1 =
        conn
        |> put_req_header("relay-batch-key", "events")
        |> post("/v1/publish/https://example.com/api1", ~s({"event": "first"}))

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
        |> put_req_header("relay-batch-key", "events")
        |> post("/v1/publish/https://example.com/api2", ~s({"event": "second"}))

      response2 = json_response(conn2, 202)
      msg2 = Messages.get!(response2["message_id"])

      # Should be in different batches
      assert msg1.batch_id != msg2.batch_id
    end

    test "forwards headers to batch", %{conn: conn} do
      conn =
        conn
        |> put_req_header("relay-batch-key", "order-events")
        |> put_req_header("relay-forward-x-custom", "custom-value")
        |> post("/v1/publish/https://example.com/api", ~s({"event": "test"}))

      response = json_response(conn, 202)
      message = Messages.get!(response["message_id"])

      assert message.headers["x-custom"] == "custom-value"
    end
  end
end
