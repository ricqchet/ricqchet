defmodule RicqchetWeb.Integration.DeliveryTest do
  @moduledoc """
  Integration tests for the complete message delivery flow.

  These tests verify the full path from API request to HTTP delivery,
  using Bypass as the destination endpoint.
  """

  use RicqchetWeb.ConnCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  alias Ricqchet.Batches
  alias Ricqchet.Delivery.BatchWorker
  alias Ricqchet.Delivery.Worker
  alias Ricqchet.Messages

  # Helper to simulate the Dispatcher: claim message and deliver via Oban
  defp dispatch_pending_message do
    case Messages.claim_next_pending() do
      {:ok, message} ->
        {:ok, _job} =
          %{message_id: message.id}
          |> Worker.new()
          |> Oban.insert()

        {:ok, Messages.get!(message.id)}

      {:error, :none_available} ->
        {:error, :none_available}
    end
  end

  # Helper to simulate the BatchDispatcher: claim batch and deliver via Oban
  defp dispatch_ready_batch do
    case Batches.claim_next_ready() do
      {:ok, batch} ->
        {:ok, _job} =
          %{batch_id: batch.id}
          |> BatchWorker.new()
          |> Oban.insert()

        {:ok, Batches.get!(batch.id)}

      {:error, :none_available} ->
        {:error, :none_available}
    end
  end

  describe "single message delivery flow" do
    setup %{conn: conn} do
      {:ok, %{api_key: api_key, tenant: tenant}} = create_tenant_with_api_key()
      bypass = Bypass.open()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{api_key.api_key}")
        |> put_req_header("content-type", "application/json")

      %{conn: conn, tenant: tenant, bypass: bypass, api_key: api_key}
    end

    test "successful delivery from API to destination", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == ~s({"event":"test"})
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
        assert Plug.Conn.get_req_header(conn, "x-ricqchet-attempt") == ["1"]
        Plug.Conn.resp(conn, 200, "OK")
      end)

      conn =
        conn
        |> put_req_header("ricqchet-destination", "http://localhost:#{bypass.port}/webhook")
        |> post("/v1/publish", ~s({"event":"test"}))

      response = json_response(conn, 202)
      message_id = response["message_id"]
      assert message_id

      {:ok, delivered_message} = dispatch_pending_message()

      assert delivered_message.id == message_id
      assert delivered_message.status == "delivered"
      assert delivered_message.attempts == 1
      assert delivered_message.last_response_status == 200
      assert delivered_message.completed_at != nil
    end

    test "failed delivery schedules retry with backoff", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      conn =
        conn
        |> put_req_header("ricqchet-destination", "http://localhost:#{bypass.port}/webhook")
        |> post("/v1/publish", ~s({"event":"test"}))

      message_id = json_response(conn, 202)["message_id"]

      {:ok, failed_message} = dispatch_pending_message()

      assert failed_message.id == message_id
      # Scheduled for retry (back to pending with future scheduled_at)
      assert failed_message.status == "pending"
      assert failed_message.attempts == 1
      assert failed_message.last_response_status == 500
      assert failed_message.last_error == "HTTP 500"
      # First retry backoff is 10 seconds
      assert DateTime.diff(failed_message.scheduled_at, DateTime.utc_now()) >= 9
    end

    test "delivery fails permanently after max retries", %{conn: conn, bypass: bypass} do
      Bypass.stub(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      # Create message with max_retries=1 (only 1 attempt allowed)
      conn =
        conn
        |> put_req_header("ricqchet-destination", "http://localhost:#{bypass.port}/webhook")
        |> put_req_header("ricqchet-retries", "1")
        |> post("/v1/publish", ~s({"event":"test"}))

      message_id = json_response(conn, 202)["message_id"]

      {:ok, failed_message} = dispatch_pending_message()

      assert failed_message.id == message_id
      # No more retries - permanently failed
      assert failed_message.status == "failed"
      assert failed_message.attempts == 1
      assert failed_message.completed_at != nil
    end

    test "forwards custom headers to destination", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-custom-header") == ["custom-value"]
        assert Plug.Conn.get_req_header(conn, "x-trace-id") == ["trace-123"]
        Plug.Conn.resp(conn, 200, "OK")
      end)

      conn =
        conn
        |> put_req_header("ricqchet-destination", "http://localhost:#{bypass.port}/webhook")
        |> put_req_header("ricqchet-forward-x-custom-header", "custom-value")
        |> put_req_header("ricqchet-forward-x-trace-id", "trace-123")
        |> post("/v1/publish", ~s({"event":"test"}))

      assert json_response(conn, 202)["message_id"]

      {:ok, message} = dispatch_pending_message()
      assert message.status == "delivered"
    end
  end

  describe "batch delivery flow" do
    setup %{conn: conn} do
      {:ok, %{api_key: api_key, tenant: tenant}} = create_tenant_with_api_key()
      bypass = Bypass.open()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{api_key.api_key}")
        |> put_req_header("content-type", "application/json")

      %{conn: conn, tenant: tenant, bypass: bypass, api_key: api_key}
    end

    test "delivers batch as JSON array when size reached", %{
      conn: conn,
      bypass: bypass,
      api_key: api_key
    } do
      test_pid = self()

      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:received_body, body})
        assert Plug.Conn.get_req_header(conn, "x-ricqchet-batch-size") == ["2"]
        Plug.Conn.resp(conn, 200, "OK")
      end)

      destination = "http://localhost:#{bypass.port}/webhook"

      # First message
      conn1 =
        conn
        |> put_req_header("ricqchet-destination", destination)
        |> put_req_header("ricqchet-batch-key", "test-batch")
        |> put_req_header("ricqchet-batch-size", "2")
        |> post("/v1/publish", ~s({"event":"first"}))

      msg1_id = json_response(conn1, 202)["message_id"]

      # Second message (triggers batch)
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key.api_key}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("ricqchet-destination", destination)
        |> put_req_header("ricqchet-batch-key", "test-batch")
        |> put_req_header("ricqchet-batch-size", "2")
        |> post("/v1/publish", ~s({"event":"second"}))

      msg2_id = json_response(conn2, 202)["message_id"]

      # Both messages should be in the same batch
      msg1 = Messages.get!(msg1_id)
      msg2 = Messages.get!(msg2_id)
      assert msg1.batch_id == msg2.batch_id

      # Dispatch batch
      {:ok, delivered_batch} = dispatch_ready_batch()

      assert delivered_batch.status == "delivered"
      assert delivered_batch.message_count == 2

      # Verify payload was JSON array
      assert_receive {:received_body, body}
      decoded = Jason.decode!(body)
      assert is_list(decoded)
      assert length(decoded) == 2
      events = Enum.map(decoded, & &1["event"])
      assert "first" in events
      assert "second" in events
    end

    test "delivers batch when timeout reached", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 200, "OK")
      end)

      destination = "http://localhost:#{bypass.port}/webhook"

      # Single message with 1 second timeout (minimum allowed)
      conn =
        conn
        |> put_req_header("ricqchet-destination", destination)
        |> put_req_header("ricqchet-batch-key", "timeout-batch")
        |> put_req_header("ricqchet-batch-timeout", "1")
        |> put_req_header("ricqchet-batch-size", "100")
        |> post("/v1/publish", ~s({"event":"test"}))

      assert json_response(conn, 202)["message_id"]

      # Wait for timeout to elapse (1s timeout + 100ms buffer for processing)
      Process.sleep(1100)

      # Batch should be ready due to timeout
      {:ok, batch} = dispatch_ready_batch()
      assert batch.status == "delivered"
    end

    test "batch retry on failure", %{conn: conn, bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/webhook", fn conn ->
        Plug.Conn.resp(conn, 503, "Service Unavailable")
      end)

      destination = "http://localhost:#{bypass.port}/webhook"

      # Use batch_size: 1 to trigger immediately when first message is added
      conn =
        conn
        |> put_req_header("ricqchet-destination", destination)
        |> put_req_header("ricqchet-batch-key", "retry-batch")
        |> put_req_header("ricqchet-batch-size", "1")
        |> post("/v1/publish", ~s({"event":"test"}))

      assert json_response(conn, 202)["message_id"]

      {:ok, batch} = dispatch_ready_batch()

      # Scheduled for retry (back to pending with future scheduled_at)
      assert batch.status == "pending"
      assert batch.attempts == 1
      assert batch.last_error == "HTTP 503"
    end
  end

  describe "fan-out delivery flow" do
    setup %{conn: conn} do
      {:ok, %{api_key: api_key}} = create_tenant_with_api_key()
      bypass1 = Bypass.open()
      bypass2 = Bypass.open()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{api_key.api_key}")
        |> put_req_header("content-type", "application/json")

      %{conn: conn, bypass1: bypass1, bypass2: bypass2}
    end

    test "delivers to multiple destinations", %{conn: conn, bypass1: bypass1, bypass2: bypass2} do
      Bypass.expect_once(bypass1, "POST", "/webhook", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == ~s({"event":"broadcast"})
        Plug.Conn.resp(conn, 200, "OK")
      end)

      Bypass.expect_once(bypass2, "POST", "/webhook", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == ~s({"event":"broadcast"})
        Plug.Conn.resp(conn, 200, "OK")
      end)

      destinations =
        "http://localhost:#{bypass1.port}/webhook, http://localhost:#{bypass2.port}/webhook"

      conn =
        conn
        |> put_req_header("ricqchet-fan-out", destinations)
        |> post("/v1/publish", ~s({"event":"broadcast"}))

      response = json_response(conn, 202)
      assert length(response["message_ids"]) == 2

      # Dispatch both messages
      {:ok, msg1} = dispatch_pending_message()
      {:ok, msg2} = dispatch_pending_message()

      assert msg1.status == "delivered"
      assert msg2.status == "delivered"
    end
  end
end
