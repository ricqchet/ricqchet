defmodule RicqchetWeb.ApplicationControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.ApiKeys
  alias Ricqchet.Applications
  alias Ricqchet.Repo

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0, create_tenant_with_api_key: 3]

  setup %{conn: conn} do
    {:ok, %{tenant: tenant, application: application, api_key: api_key}} =
      create_tenant_with_api_key()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{api_key.api_key}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, tenant: tenant, application: application, api_key: api_key}
  end

  describe "index/2" do
    test "returns list of applications for tenant", %{conn: conn, application: application} do
      conn = get(conn, "/v1/applications")

      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert response["meta"]["total"] >= 1

      app_ids = Enum.map(response["data"], & &1["id"])
      assert application.id in app_ids
    end

    test "includes api_key_count in response", %{conn: conn, application: application} do
      # Create additional API key
      {:ok, _} = ApiKeys.create_api_key(application, %{name: "Second Key"})

      conn = get(conn, "/v1/applications")

      response = json_response(conn, 200)
      app = Enum.find(response["data"], &(&1["id"] == application.id))

      assert app["api_key_count"] == 2
    end

    test "returns 401 without auth header", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get("/v1/applications")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "only returns applications for current tenant", %{conn: conn, application: application} do
      # Create another tenant with applications
      {:ok, %{application: other_app}} =
        create_tenant_with_api_key(%{name: "Other Tenant"}, %{name: "Other App"}, %{})

      conn = get(conn, "/v1/applications")

      response = json_response(conn, 200)
      app_ids = Enum.map(response["data"], & &1["id"])

      assert application.id in app_ids
      refute other_app.id in app_ids
    end
  end

  describe "show/2" do
    test "returns application details with api keys", %{conn: conn, application: application} do
      conn = get(conn, "/v1/applications/#{application.id}")

      response = json_response(conn, 200)
      assert response["id"] == application.id
      assert response["name"] == application.name
      assert response["status"] == application.status
      assert is_list(response["api_keys"])
    end

    test "api keys include prefix but not full key", %{conn: conn, application: application} do
      conn = get(conn, "/v1/applications/#{application.id}")

      response = json_response(conn, 200)
      api_key = List.first(response["api_keys"])

      assert api_key["prefix"]
      assert String.length(api_key["prefix"]) == 8
      refute Map.has_key?(api_key, "api_key")
      refute Map.has_key?(api_key, "api_key_hash")
    end

    test "returns 404 for non-existent application", %{conn: conn} do
      conn = get(conn, "/v1/applications/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 404 for application belonging to another tenant", %{conn: conn} do
      {:ok, %{application: other_app}} =
        create_tenant_with_api_key(%{name: "Other Tenant"}, %{name: "Other App"}, %{})

      conn = get(conn, "/v1/applications/#{other_app.id}")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 401 without auth header", %{conn: conn, application: application} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get("/v1/applications/#{application.id}")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  describe "create/2" do
    test "creates application with default api key", %{conn: conn, tenant: tenant} do
      conn =
        post(conn, "/v1/applications", %{
          name: "New Application",
          description: "Test description"
        })

      response = json_response(conn, 201)
      assert response["id"]
      assert response["name"] == "New Application"
      assert response["description"] == "Test description"
      assert response["status"] == "active"
      assert response["api_key"]

      # Verify application was created
      app =
        tenant
        |> Applications.get_application_by_tenant(response["id"])
        |> Repo.preload(:api_keys)

      assert app.name == "New Application"

      # Verify API key was created
      assert length(app.api_keys) == 1
      assert List.first(app.api_keys).name == "Default"
    end

    test "returns api key only on creation", %{conn: conn} do
      # Create
      conn1 = post(conn, "/v1/applications", %{name: "App With Key"})
      response1 = json_response(conn1, 201)
      assert response1["api_key"]

      # Fetch - no api_key field
      auth_header =
        conn
        |> get_req_header("authorization")
        |> List.first()

      conn2 =
        build_conn()
        |> put_req_header("authorization", auth_header)
        |> put_req_header("content-type", "application/json")
        |> get("/v1/applications/#{response1["id"]}")

      response2 = json_response(conn2, 200)
      refute Map.has_key?(response2, "api_key")
    end

    test "returns 422 when name is missing", %{conn: conn} do
      conn = post(conn, "/v1/applications", %{description: "No name"})

      assert json_response(conn, 422)["error"] == "validation_error"
    end

    test "creates application with dlq_destination_url", %{conn: conn} do
      conn =
        post(conn, "/v1/applications", %{
          name: "App with DLQ",
          dlq_destination_url: "https://example.com/dlq"
        })

      response = json_response(conn, 201)
      assert response["dlq_destination_url"] == "https://example.com/dlq"
    end

    test "returns 422 for invalid dlq_destination_url", %{conn: conn} do
      conn =
        post(conn, "/v1/applications", %{
          name: "App with bad DLQ",
          dlq_destination_url: "http://example.com/dlq"
        })

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
      assert response["message"] =~ "HTTPS"
    end

    test "returns 401 without auth header", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> post("/v1/applications", %{name: "Test"})

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  describe "update/2" do
    test "updates application name", %{conn: conn, application: application} do
      conn =
        patch(conn, "/v1/applications/#{application.id}", %{
          name: "Updated Name"
        })

      response = json_response(conn, 200)
      assert response["name"] == "Updated Name"

      # Verify in database
      updated = Applications.get_application!(application.id)
      assert updated.name == "Updated Name"
    end

    test "updates application description", %{conn: conn, application: application} do
      conn =
        patch(conn, "/v1/applications/#{application.id}", %{
          description: "New description"
        })

      response = json_response(conn, 200)
      assert response["description"] == "New description"
    end

    test "updates application status", %{conn: conn, application: application} do
      conn =
        patch(conn, "/v1/applications/#{application.id}", %{
          status: "suspended"
        })

      response = json_response(conn, 200)
      assert response["status"] == "suspended"
    end

    test "updates dlq_destination_url", %{conn: conn, application: application} do
      conn =
        patch(conn, "/v1/applications/#{application.id}", %{
          dlq_destination_url: "https://new-dlq.example.com/errors"
        })

      response = json_response(conn, 200)
      assert response["dlq_destination_url"] == "https://new-dlq.example.com/errors"
    end

    test "returns 404 for non-existent application", %{conn: conn} do
      conn =
        patch(conn, "/v1/applications/#{Ecto.UUID.generate()}", %{
          name: "Updated"
        })

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 404 for application belonging to another tenant", %{conn: conn} do
      {:ok, %{application: other_app}} =
        create_tenant_with_api_key(%{name: "Other Tenant"}, %{name: "Other App"}, %{})

      conn =
        patch(conn, "/v1/applications/#{other_app.id}", %{
          name: "Hijacked"
        })

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 422 for invalid status", %{conn: conn, application: application} do
      conn =
        patch(conn, "/v1/applications/#{application.id}", %{
          status: "invalid_status"
        })

      assert json_response(conn, 422)["error"] == "validation_error"
    end

    test "returns 401 without auth header", %{conn: conn, application: application} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> patch("/v1/applications/#{application.id}", %{name: "Updated"})

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  describe "delete/2" do
    test "deletes application and revokes api keys", %{conn: conn, tenant: tenant} do
      # Create a fresh application for this test
      {:ok, app} = Applications.create_application(tenant, %{name: "To Delete"})
      {:ok, key1} = ApiKeys.create_api_key(app, %{name: "Key 1"})
      {:ok, _key2} = ApiKeys.create_api_key(app, %{name: "Key 2"})

      conn = delete(conn, "/v1/applications/#{app.id}")

      response = json_response(conn, 200)
      assert response["deleted"] == true
      assert response["id"] == app.id
      assert response["api_keys_revoked"] == 2

      # Verify application is deleted
      assert Applications.get_application(app.id) == nil

      # Verify API keys are removed (keys are revoked first, then deleted with the app)
      assert ApiKeys.get_api_key(key1.id) == nil
    end

    test "returns 404 for non-existent application", %{conn: conn} do
      conn = delete(conn, "/v1/applications/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 404 for application belonging to another tenant", %{conn: conn} do
      {:ok, %{application: other_app}} =
        create_tenant_with_api_key(%{name: "Other Tenant"}, %{name: "Other App"}, %{})

      conn = delete(conn, "/v1/applications/#{other_app.id}")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 401 without auth header", %{conn: conn, application: application} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> delete("/v1/applications/#{application.id}")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end
end
