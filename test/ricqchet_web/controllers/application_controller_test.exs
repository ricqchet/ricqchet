defmodule RicqchetWeb.ApplicationControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.ApiKeys
  alias Ricqchet.Applications
  alias Ricqchet.Auth
  alias Ricqchet.Auth.Token
  alias Ricqchet.Repo
  alias Ricqchet.Users

  setup %{conn: conn} do
    # Create and verify an admin user
    {:ok, %{user: _user, verification_token: token}} =
      Auth.register_user(%{
        "email" => "admin#{System.unique_integer()}@example.com",
        "password" => "secure_password_123",
        "tenant_name" => "Test Org #{System.unique_integer()}"
      })

    {:ok, verified_user} = Auth.verify_email(token)
    {:ok, access_token, _claims} = Token.generate_access_token(verified_user)

    user = Repo.preload(verified_user, :tenant)
    tenant = user.tenant

    # Create a test application
    {:ok, application} = Applications.create_application(tenant, %{name: "Test Application"})
    {:ok, _api_key} = ApiKeys.create_api_key(application, %{name: "Test API Key"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> put_req_header("content-type", "application/json")

    %{
      conn: conn,
      user: user,
      tenant: tenant,
      application: application,
      access_token: access_token
    }
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

    test "allows member role to list applications", %{tenant: tenant} do
      # Create a member user
      {:ok, unconfirmed_member} =
        Users.create_user(tenant, %{
          email: "member#{System.unique_integer()}@example.com",
          password: "secure_password_123",
          role: "member"
        })

      {:ok, member} = Users.confirm_user(unconfirmed_member)
      {:ok, member_token, _claims} = Token.generate_access_token(member)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> put_req_header("content-type", "application/json")
        |> get("/v1/applications")

      response = json_response(conn, 200)
      assert is_list(response["data"])
    end

    test "allows viewer role to list applications", %{tenant: tenant} do
      # Create a viewer user
      {:ok, unconfirmed_viewer} =
        Users.create_user(tenant, %{
          email: "viewer#{System.unique_integer()}@example.com",
          password: "secure_password_123",
          role: "viewer"
        })

      {:ok, viewer} = Users.confirm_user(unconfirmed_viewer)
      {:ok, viewer_token, _claims} = Token.generate_access_token(viewer)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{viewer_token}")
        |> put_req_header("content-type", "application/json")
        |> get("/v1/applications")

      response = json_response(conn, 200)
      assert is_list(response["data"])
    end

    test "supports cursor-based pagination with first param", %{conn: conn, tenant: tenant} do
      # Create additional applications
      for i <- 1..5 do
        Applications.create_application(tenant, %{name: "App #{i}"})
      end

      conn = get(conn, "/v1/applications", %{first: 2})

      response = json_response(conn, 200)
      assert length(response["data"]) == 2
      assert response["meta"]["has_next_page"] == true
      assert response["meta"]["end_cursor"] != nil
    end

    test "supports forward pagination with after cursor", %{conn: conn, tenant: tenant} do
      # Create additional applications
      for i <- 1..5 do
        Applications.create_application(tenant, %{name: "App #{i}"})
      end

      # Get first page
      conn1 = get(conn, "/v1/applications", %{first: 2})
      response1 = json_response(conn1, 200)
      end_cursor = response1["meta"]["end_cursor"]

      # Get second page using cursor
      [auth_header] = get_req_header(conn, "authorization")

      conn2 =
        build_conn()
        |> put_req_header("authorization", auth_header)
        |> get("/v1/applications", %{first: 2, after: end_cursor})

      response2 = json_response(conn2, 200)
      assert length(response2["data"]) == 2
      assert response2["meta"]["has_previous_page"] == true

      # Ensure no overlap between pages
      ids1 = MapSet.new(response1["data"], & &1["id"])
      ids2 = MapSet.new(response2["data"], & &1["id"])
      assert MapSet.disjoint?(ids1, ids2)
    end

    test "supports backward pagination with last/before cursor", %{conn: conn, tenant: tenant} do
      # Create additional applications
      for i <- 1..5 do
        Applications.create_application(tenant, %{name: "App #{i}"})
      end

      [auth_header] = get_req_header(conn, "authorization")

      # Get last page first
      conn1 = get(conn, "/v1/applications", %{last: 2})
      response1 = json_response(conn1, 200)
      assert length(response1["data"]) == 2
      assert response1["meta"]["has_previous_page"] == true
      start_cursor = response1["meta"]["start_cursor"]

      # Get previous page using before cursor
      conn2 =
        build_conn()
        |> put_req_header("authorization", auth_header)
        |> get("/v1/applications", %{last: 2, before: start_cursor})

      response2 = json_response(conn2, 200)
      assert length(response2["data"]) == 2
      assert response2["meta"]["has_next_page"] == true

      # Ensure no overlap between pages
      ids1 = MapSet.new(response1["data"], & &1["id"])
      ids2 = MapSet.new(response2["data"], & &1["id"])
      assert MapSet.disjoint?(ids1, ids2)
    end

    test "supports offset-based pagination", %{conn: conn, tenant: tenant} do
      # Create additional applications
      for i <- 1..5 do
        Applications.create_application(tenant, %{name: "App #{i}"})
      end

      conn = get(conn, "/v1/applications", %{offset: 2, limit: 2})

      response = json_response(conn, 200)
      assert length(response["data"]) == 2
      assert response["meta"]["current_offset"] == 2
      assert response["meta"]["total_pages"] != nil
    end

    test "supports filtering by status", %{conn: conn, tenant: tenant} do
      # Create applications with different statuses
      {:ok, active_app} = Applications.create_application(tenant, %{name: "Active App"})
      {:ok, suspended_app} = Applications.create_application(tenant, %{name: "Suspended App"})

      Applications.update_application(suspended_app, %{status: "suspended"})

      # Filter for active only using query string format
      conn = get(conn, "/v1/applications?filters[0][field]=status&filters[0][value]=active")

      response = json_response(conn, 200)
      statuses = Enum.map(response["data"], & &1["status"])
      assert Enum.all?(statuses, &(&1 == "active"))
      assert active_app.id in Enum.map(response["data"], & &1["id"])
    end

    test "supports sorting by name", %{conn: conn, tenant: tenant} do
      # Create applications with specific names
      Applications.create_application(tenant, %{name: "Zebra"})
      Applications.create_application(tenant, %{name: "Apple"})
      Applications.create_application(tenant, %{name: "Mango"})

      conn =
        get(conn, "/v1/applications", %{
          "order_by" => ["name"],
          "order_directions" => ["asc"]
        })

      response = json_response(conn, 200)
      names = Enum.map(response["data"], & &1["name"])
      assert names == Enum.sort(names)
    end

    test "returns validation error for invalid pagination params", %{conn: conn} do
      conn = get(conn, "/v1/applications", %{limit: 1000})

      response = json_response(conn, 422)
      assert response["error"] == "validation_error"
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
      # Create another tenant with application
      {:ok, %{user: _other_user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "other#{System.unique_integer()}@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Other Org"
        })

      {:ok, verified_other_user} = Auth.verify_email(token)
      other_user = Repo.preload(verified_other_user, :tenant)
      {:ok, other_app} = Applications.create_application(other_user.tenant, %{name: "Other App"})

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

    test "returns api key only on creation", %{conn: conn, access_token: access_token} do
      # Create
      conn1 = post(conn, "/v1/applications", %{name: "App With Key"})
      response1 = json_response(conn1, 201)
      assert response1["api_key"]

      # Fetch - no api_key field
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{access_token}")
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

    test "returns 403 for non-admin user", %{tenant: tenant} do
      # Create a member user
      {:ok, unconfirmed_member} =
        Users.create_user(tenant, %{
          email: "member_create#{System.unique_integer()}@example.com",
          password: "secure_password_123",
          role: "member"
        })

      {:ok, member} = Users.confirm_user(unconfirmed_member)
      {:ok, member_token, _claims} = Token.generate_access_token(member)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> put_req_header("content-type", "application/json")
        |> post("/v1/applications", %{name: "Not Allowed"})

      assert json_response(conn, 403)["error"] == "forbidden"
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
      # Create another tenant with application
      {:ok, %{user: _other_user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "other_update#{System.unique_integer()}@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Other Org Update"
        })

      {:ok, verified_other} = Auth.verify_email(token)
      other_user = Repo.preload(verified_other, :tenant)
      {:ok, other_app} = Applications.create_application(other_user.tenant, %{name: "Other App"})

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

    test "returns 403 for non-admin user", %{tenant: tenant, application: application} do
      # Create a member user
      {:ok, unconfirmed_member} =
        Users.create_user(tenant, %{
          email: "member_update#{System.unique_integer()}@example.com",
          password: "secure_password_123",
          role: "member"
        })

      {:ok, member} = Users.confirm_user(unconfirmed_member)
      {:ok, member_token, _claims} = Token.generate_access_token(member)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> put_req_header("content-type", "application/json")
        |> patch("/v1/applications/#{application.id}", %{name: "Not Allowed"})

      assert json_response(conn, 403)["error"] == "forbidden"
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
      # Create another tenant with application
      {:ok, %{user: _other_user, verification_token: token}} =
        Auth.register_user(%{
          "email" => "other_delete#{System.unique_integer()}@example.com",
          "password" => "secure_password_123",
          "tenant_name" => "Other Org Delete"
        })

      {:ok, verified_other} = Auth.verify_email(token)
      other_user = Repo.preload(verified_other, :tenant)
      {:ok, other_app} = Applications.create_application(other_user.tenant, %{name: "Other App"})

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

    test "returns 403 for non-admin user", %{tenant: tenant} do
      # Create an application to try to delete
      {:ok, app} = Applications.create_application(tenant, %{name: "To Not Delete"})

      # Create a member user
      {:ok, unconfirmed_member} =
        Users.create_user(tenant, %{
          email: "member_delete#{System.unique_integer()}@example.com",
          password: "secure_password_123",
          role: "member"
        })

      {:ok, member} = Users.confirm_user(unconfirmed_member)
      {:ok, member_token, _claims} = Token.generate_access_token(member)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> put_req_header("content-type", "application/json")
        |> delete("/v1/applications/#{app.id}")

      assert json_response(conn, 403)["error"] == "forbidden"

      # Verify application was NOT deleted
      assert Applications.get_application(app.id) != nil
    end
  end
end
