defmodule RicqchetWeb.ApiKeyControllerTest do
  use RicqchetWeb.ConnCase, async: false

  alias Ricqchet.ApiKeys
  alias Ricqchet.Applications

  setup %{conn: conn} do
    # Create an admin user
    {:ok, %{user: user, tenant: tenant}} =
      create_tenant_and_user(email: "admin#{System.unique_integer()}@example.com")

    access_token = access_token_for(user)

    # Create a test application with an API key
    {:ok, application} = Applications.create_application(tenant, %{name: "Test Application"})
    {:ok, api_key} = ApiKeys.create_api_key(application, %{name: "Test API Key"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> put_req_header("content-type", "application/json")

    %{
      conn: conn,
      user: user,
      tenant: tenant,
      application: application,
      api_key: api_key,
      access_token: access_token
    }
  end

  describe "index/2" do
    test "returns list of API keys for application", %{
      conn: conn,
      application: application,
      api_key: api_key
    } do
      conn = get(conn, "/v1/applications/#{application.id}/api-keys")

      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert response["meta"]["total"] >= 1

      key_ids = Enum.map(response["data"], & &1["id"])
      assert api_key.id in key_ids
    end

    test "returns keys with prefix but not full key", %{
      conn: conn,
      application: application,
      api_key: api_key
    } do
      conn = get(conn, "/v1/applications/#{application.id}/api-keys")

      response = json_response(conn, 200)
      key = Enum.find(response["data"], &(&1["id"] == api_key.id))

      assert key["prefix"]
      assert String.length(key["prefix"]) == 8
      refute Map.has_key?(key, "api_key")
      refute Map.has_key?(key, "api_key_hash")
    end

    test "includes status and timestamps", %{conn: conn, application: application} do
      conn = get(conn, "/v1/applications/#{application.id}/api-keys")

      response = json_response(conn, 200)
      key = List.first(response["data"])

      assert key["status"]
      assert key["created_at"]
      assert Map.has_key?(key, "last_used_at")
      assert Map.has_key?(key, "expires_at")
    end

    test "returns 404 for non-existent application", %{conn: conn} do
      conn = get(conn, "/v1/applications/#{Ecto.UUID.generate()}/api-keys")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 404 for application belonging to another tenant", %{conn: conn} do
      # Create another tenant with application
      {:ok, %{tenant: other_tenant}} = create_tenant_and_user()
      {:ok, other_app} = Applications.create_application(other_tenant, %{name: "Other App"})

      conn = get(conn, "/v1/applications/#{other_app.id}/api-keys")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 401 without auth header", %{conn: conn, application: application} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get("/v1/applications/#{application.id}/api-keys")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "allows member role to list API keys", %{tenant: tenant, application: application} do
      {:ok, %{user: member}} = create_tenant_and_user(tenant: tenant, role: "member")
      member_token = access_token_for(member)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> put_req_header("content-type", "application/json")
        |> get("/v1/applications/#{application.id}/api-keys")

      response = json_response(conn, 200)
      assert is_list(response["data"])
    end

    test "allows viewer role to list API keys", %{tenant: tenant, application: application} do
      {:ok, %{user: viewer}} = create_tenant_and_user(tenant: tenant, role: "viewer")
      viewer_token = access_token_for(viewer)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{viewer_token}")
        |> put_req_header("content-type", "application/json")
        |> get("/v1/applications/#{application.id}/api-keys")

      response = json_response(conn, 200)
      assert is_list(response["data"])
    end
  end

  describe "create/2" do
    test "creates API key and returns full key", %{conn: conn, application: application} do
      conn =
        post(conn, "/v1/applications/#{application.id}/api-keys", %{
          name: "New API Key"
        })

      response = json_response(conn, 201)
      assert response["id"]
      assert response["name"] == "New API Key"
      assert response["api_key"]
      assert response["prefix"]
      assert String.length(response["prefix"]) == 8
      assert response["status"] == "active"
      assert response["created_at"]
    end

    test "full key is only returned on creation", %{
      conn: conn,
      application: application,
      access_token: access_token
    } do
      # Create
      conn1 = post(conn, "/v1/applications/#{application.id}/api-keys", %{name: "New Key"})
      response1 = json_response(conn1, 201)
      assert response1["api_key"]

      # List - no full key
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("content-type", "application/json")
        |> get("/v1/applications/#{application.id}/api-keys")

      response2 = json_response(conn2, 200)
      new_key = Enum.find(response2["data"], &(&1["id"] == response1["id"]))

      refute Map.has_key?(new_key, "api_key")
    end

    test "created key can be used for authentication", %{conn: conn, application: application} do
      conn1 =
        post(conn, "/v1/applications/#{application.id}/api-keys", %{
          name: "Auth Test Key"
        })

      response = json_response(conn1, 201)
      new_api_key = response["api_key"]

      # Test authentication with new key
      auth_result = ApiKeys.get_by_api_key(new_api_key)
      assert auth_result
      assert auth_result.api_key.id == response["id"]
    end

    test "returns 422 when name is missing", %{conn: conn, application: application} do
      conn = post(conn, "/v1/applications/#{application.id}/api-keys", %{})

      assert json_response(conn, 422)["error"] == "validation_error"
    end

    test "returns 404 for non-existent application", %{conn: conn} do
      conn =
        post(conn, "/v1/applications/#{Ecto.UUID.generate()}/api-keys", %{
          name: "New Key"
        })

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 404 for application belonging to another tenant", %{conn: conn} do
      {:ok, %{tenant: other_tenant}} = create_tenant_and_user()
      {:ok, other_app} = Applications.create_application(other_tenant, %{name: "Other App"})

      conn =
        post(conn, "/v1/applications/#{other_app.id}/api-keys", %{
          name: "Hijack Key"
        })

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 401 without auth header", %{conn: conn, application: application} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> post("/v1/applications/#{application.id}/api-keys", %{name: "New Key"})

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "allows member role to create API key", %{tenant: tenant, application: application} do
      {:ok, %{user: member}} = create_tenant_and_user(tenant: tenant, role: "member")
      member_token = access_token_for(member)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> put_req_header("content-type", "application/json")
        |> post("/v1/applications/#{application.id}/api-keys", %{name: "Member Key"})

      response = json_response(conn, 201)
      assert response["id"]
      assert response["name"] == "Member Key"
    end

    test "returns 403 for viewer role", %{tenant: tenant, application: application} do
      {:ok, %{user: viewer}} = create_tenant_and_user(tenant: tenant, role: "viewer")
      viewer_token = access_token_for(viewer)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{viewer_token}")
        |> put_req_header("content-type", "application/json")
        |> post("/v1/applications/#{application.id}/api-keys", %{name: "Not Allowed"})

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end

  describe "delete/2 (revoke)" do
    test "revokes API key", %{conn: conn, application: application} do
      # Create a key to revoke
      {:ok, key} = ApiKeys.create_api_key(application, %{name: "To Revoke"})

      conn = delete(conn, "/v1/api-keys/#{key.id}")

      response = json_response(conn, 200)
      assert response["id"] == key.id
      assert response["status"] == "revoked"
      assert response["revoked"] == true
      assert response["revoked_at"]
    end

    test "revoked key cannot authenticate", %{conn: conn, application: application} do
      # Create a key to revoke
      {:ok, key} = ApiKeys.create_api_key(application, %{name: "To Revoke Auth"})
      plaintext_key = key.api_key

      # Verify it works before revocation
      assert ApiKeys.get_by_api_key(plaintext_key)

      # Revoke
      _conn = delete(conn, "/v1/api-keys/#{key.id}")

      # Verify it no longer works
      refute ApiKeys.get_by_api_key(plaintext_key)
    end

    test "returns 404 for non-existent key", %{conn: conn} do
      conn = delete(conn, "/v1/api-keys/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 404 for key belonging to another tenant", %{conn: conn} do
      {:ok, %{tenant: other_tenant}} = create_tenant_and_user()
      {:ok, other_app} = Applications.create_application(other_tenant, %{name: "Other App"})
      {:ok, other_key} = ApiKeys.create_api_key(other_app, %{name: "Other Key"})

      conn = delete(conn, "/v1/api-keys/#{other_key.id}")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 401 without auth header", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> delete("/v1/api-keys/#{api_key.id}")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "allows member role to revoke API key", %{tenant: tenant, application: application} do
      {:ok, key} = ApiKeys.create_api_key(application, %{name: "Member Revoke"})

      {:ok, %{user: member}} = create_tenant_and_user(tenant: tenant, role: "member")
      member_token = access_token_for(member)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> put_req_header("content-type", "application/json")
        |> delete("/v1/api-keys/#{key.id}")

      response = json_response(conn, 200)
      assert response["id"] == key.id
      assert response["status"] == "revoked"
    end

    test "returns 403 for viewer role", %{tenant: tenant, application: application} do
      {:ok, key} = ApiKeys.create_api_key(application, %{name: "To Not Revoke"})

      {:ok, %{user: viewer}} = create_tenant_and_user(tenant: tenant, role: "viewer")
      viewer_token = access_token_for(viewer)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{viewer_token}")
        |> put_req_header("content-type", "application/json")
        |> delete("/v1/api-keys/#{key.id}")

      assert json_response(conn, 403)["error"] == "forbidden"

      # Verify key was not revoked
      assert ApiKeys.get_api_key(key.id).status == "active"
    end
  end

  describe "rotate/2" do
    test "rotates API key atomically", %{conn: conn, application: application} do
      # Create a key to rotate
      {:ok, old_key} = ApiKeys.create_api_key(application, %{name: "To Rotate"})

      conn = post(conn, "/v1/api-keys/#{old_key.id}/rotate")

      response = json_response(conn, 200)

      # Old key info
      assert response["old_api_key"]["id"] == old_key.id
      assert response["old_api_key"]["status"] == "revoked"

      # New key info
      assert response["new_api_key"]["id"]
      assert response["new_api_key"]["id"] != old_key.id
      assert response["new_api_key"]["name"] == old_key.name
      assert response["new_api_key"]["api_key"]
      assert response["new_api_key"]["status"] == "active"
    end

    test "old key is revoked after rotation", %{conn: conn, application: application} do
      {:ok, old_key} = ApiKeys.create_api_key(application, %{name: "To Rotate Auth"})
      old_plaintext = old_key.api_key

      # Verify old key works
      assert ApiKeys.get_by_api_key(old_plaintext)

      # Rotate
      _conn = post(conn, "/v1/api-keys/#{old_key.id}/rotate")

      # Verify old key no longer works
      refute ApiKeys.get_by_api_key(old_plaintext)
    end

    test "new key can authenticate after rotation", %{conn: conn, application: application} do
      {:ok, old_key} = ApiKeys.create_api_key(application, %{name: "To Rotate New Auth"})

      conn1 = post(conn, "/v1/api-keys/#{old_key.id}/rotate")
      response = json_response(conn1, 200)
      new_plaintext = response["new_api_key"]["api_key"]

      # Verify new key works
      auth_result = ApiKeys.get_by_api_key(new_plaintext)
      assert auth_result
      assert auth_result.api_key.id == response["new_api_key"]["id"]
    end

    test "returns 404 for non-existent key", %{conn: conn} do
      conn = post(conn, "/v1/api-keys/#{Ecto.UUID.generate()}/rotate")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 404 for key belonging to another tenant", %{conn: conn} do
      {:ok, %{tenant: other_tenant}} = create_tenant_and_user()
      {:ok, other_app} = Applications.create_application(other_tenant, %{name: "Other App"})
      {:ok, other_key} = ApiKeys.create_api_key(other_app, %{name: "Other Key"})

      conn = post(conn, "/v1/api-keys/#{other_key.id}/rotate")

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 401 without auth header", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> post("/v1/api-keys/#{api_key.id}/rotate")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "allows member role to rotate API key", %{tenant: tenant, application: application} do
      {:ok, key} = ApiKeys.create_api_key(application, %{name: "Member Rotate"})

      {:ok, %{user: member}} = create_tenant_and_user(tenant: tenant, role: "member")
      member_token = access_token_for(member)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{member_token}")
        |> put_req_header("content-type", "application/json")
        |> post("/v1/api-keys/#{key.id}/rotate")

      response = json_response(conn, 200)
      assert response["old_api_key"]["id"] == key.id
      assert response["new_api_key"]["id"] != key.id
    end

    test "returns 403 for viewer role", %{tenant: tenant, application: application} do
      {:ok, key} = ApiKeys.create_api_key(application, %{name: "To Not Rotate"})

      {:ok, %{user: viewer}} = create_tenant_and_user(tenant: tenant, role: "viewer")
      viewer_token = access_token_for(viewer)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{viewer_token}")
        |> put_req_header("content-type", "application/json")
        |> post("/v1/api-keys/#{key.id}/rotate")

      assert json_response(conn, 403)["error"] == "forbidden"

      # Verify key was not rotated
      assert ApiKeys.get_api_key(key.id).status == "active"
    end
  end
end
