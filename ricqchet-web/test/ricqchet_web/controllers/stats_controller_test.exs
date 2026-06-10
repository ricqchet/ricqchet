defmodule RicqchetWeb.StatsControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.Messages

  setup %{conn: conn} do
    # Create an active, confirmed admin user
    {:ok, %{user: user, tenant: tenant}} =
      create_tenant_and_user(
        email: "admin#{System.unique_integer()}@example.com",
        password: "secure_password_123"
      )

    access_token = access_token_for(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, user: user, tenant: tenant, access_token: access_token}
  end

  describe "GET /v1/stats/messages" do
    test "returns message counts by status", %{conn: conn, tenant: tenant} do
      # Create some test messages with different statuses
      {:ok, _} = create_message(tenant, %{status: "pending"})
      {:ok, _} = create_message(tenant, %{status: "delivered"})
      {:ok, _} = create_message(tenant, %{status: "delivered"})
      {:ok, _} = create_message(tenant, %{status: "failed"})

      conn = get(conn, "/v1/stats/messages")

      response = json_response(conn, 200)
      assert response["period"] == "1h"
      assert response["counts"]["pending"] >= 1
      assert response["counts"]["delivered"] >= 2
      assert response["counts"]["failed"] >= 1
      assert response["total"] >= 4
    end

    test "supports period parameter", %{conn: conn} do
      conn = get(conn, "/v1/stats/messages", %{period: "4h"})

      response = json_response(conn, 200)
      assert response["period"] == "4h"
    end

    test "returns 401 without auth", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get("/v1/stats/messages")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  describe "GET /v1/stats/message-sizes" do
    test "returns message size statistics", %{conn: conn, tenant: tenant} do
      # Create messages with different payload sizes
      {:ok, _} = create_message(tenant, %{payload: String.duplicate("a", 100)})
      {:ok, _} = create_message(tenant, %{payload: String.duplicate("b", 500)})
      {:ok, _} = create_message(tenant, %{payload: String.duplicate("c", 1000)})

      conn = get(conn, "/v1/stats/message-sizes")

      response = json_response(conn, 200)
      assert response["period"] == "1h"
      assert response["message_count"] >= 3
      assert response["total_bytes"] >= 1600
      assert is_integer(response["average_bytes"])
      assert is_map(response["percentiles"])
    end
  end

  describe "GET /v1/stats/delivery" do
    test "returns delivery performance statistics", %{conn: conn, tenant: tenant} do
      # Create delivered and failed messages
      {:ok, msg1} = create_message(tenant, %{status: "dispatched"})
      {:ok, _} = Messages.mark_delivered(msg1, %{status: 200, body: "OK"})

      {:ok, msg2} = create_message(tenant, %{status: "dispatched", max_retries: 1})
      {:ok, _} = Messages.mark_failed(msg2, "Connection refused")

      conn = get(conn, "/v1/stats/delivery")

      response = json_response(conn, 200)
      assert response["period"] == "1h"
      assert is_integer(response["total_completed"])
      assert is_number(response["success_rate"])
      assert is_number(response["retry_rate"])
      assert is_map(response["delivery_times"])
    end
  end

  describe "GET /v1/stats/errors" do
    test "returns error breakdown", %{conn: conn, tenant: tenant} do
      # Create failed messages with different error types
      {:ok, msg1} = create_message(tenant, %{status: "dispatched", max_retries: 1})
      {:ok, _} = Messages.mark_failed(msg1, "Connection refused")

      {:ok, msg2} = create_message(tenant, %{status: "dispatched", max_retries: 1})
      {:ok, _} = Messages.mark_failed(msg2, "Timeout waiting for response")

      conn = get(conn, "/v1/stats/errors")

      response = json_response(conn, 200)
      assert response["period"] == "1h"
      assert is_integer(response["total_errors"])
      assert is_map(response["by_type"])
      assert is_map(response["by_status_code"])
      assert is_list(response["top_failing_destinations"])
    end

    test "supports limit parameter", %{conn: conn} do
      conn = get(conn, "/v1/stats/errors", %{limit: 5})

      response = json_response(conn, 200)
      assert length(response["top_failing_destinations"]) <= 5
    end
  end

  describe "GET /v1/stats/destinations" do
    test "returns per-destination metrics", %{conn: conn, tenant: tenant} do
      # Create messages to different destinations
      {:ok, msg1} =
        create_message(tenant, %{
          destination_url: "https://example.com/webhook1",
          status: "dispatched"
        })

      {:ok, _} = Messages.mark_delivered(msg1, %{status: 200, body: "OK"})

      {:ok, msg2} =
        create_message(tenant, %{
          destination_url: "https://example.com/webhook2",
          status: "dispatched"
        })

      {:ok, _} = Messages.mark_delivered(msg2, %{status: 200, body: "OK"})

      conn = get(conn, "/v1/stats/destinations")

      response = json_response(conn, 200)
      assert response["period"] == "1h"
      assert is_list(response["destinations"])

      if response["destinations"] != [] do
        dest = hd(response["destinations"])
        assert Map.has_key?(dest, "url")
        assert Map.has_key?(dest, "volume")
        assert Map.has_key?(dest, "success_rate")
        assert Map.has_key?(dest, "avg_response_time_ms")
      end
    end
  end

  describe "GET /v1/stats/activity" do
    test "returns recent activity feed", %{conn: conn, tenant: tenant} do
      # Create some messages
      {:ok, _} = create_message(tenant, %{})
      {:ok, _} = create_message(tenant, %{})

      conn = get(conn, "/v1/stats/activity")

      response = json_response(conn, 200)
      assert response["period"] == "1h"
      assert is_list(response["data"])
      assert is_map(response["meta"])
      assert Map.has_key?(response["meta"], "has_more")
    end

    test "supports status filter", %{conn: conn, tenant: tenant} do
      {:ok, _} = create_message(tenant, %{status: "pending"})
      {:ok, _} = create_message(tenant, %{status: "delivered"})

      conn = get(conn, "/v1/stats/activity", %{status: "pending"})

      response = json_response(conn, 200)
      statuses = Enum.map(response["data"], & &1["status"])
      assert Enum.all?(statuses, &(&1 == "pending"))
    end

    test "supports pagination with limit", %{conn: conn, tenant: tenant} do
      for _i <- 1..5 do
        {:ok, _} = create_message(tenant, %{})
      end

      conn = get(conn, "/v1/stats/activity", %{limit: 2})

      response = json_response(conn, 200)
      assert length(response["data"]) <= 2
    end
  end

  # Helper to create test messages
  defp create_message(tenant, attrs) do
    base_attrs = %{
      destination_url:
        attrs[:destination_url] || "https://example.com/webhook#{System.unique_integer()}",
      payload: attrs[:payload] || "test payload",
      max_retries: attrs[:max_retries] || 3
    }

    {:ok, message} = Messages.create(tenant, base_attrs)

    # Update status if needed (create always creates as pending)
    if attrs[:status] && attrs[:status] != "pending" do
      updated =
        message
        |> Ecto.Changeset.change(%{
          status: attrs[:status],
          completed_at: if(attrs[:status] in ["delivered", "failed"], do: DateTime.utc_now()),
          dispatched_at: if(attrs[:status] != "pending", do: DateTime.utc_now())
        })
        |> Ricqchet.Repo.update!()

      {:ok, updated}
    else
      {:ok, message}
    end
  end
end
