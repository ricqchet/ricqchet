defmodule RicqchetWeb.OpenApiTest do
  use RicqchetWeb.ConnCase, async: true

  describe "GET /api/openapi" do
    test "returns OpenAPI spec as JSON", %{conn: conn} do
      conn = get(conn, "/api/openapi")

      response = json_response(conn, 200)

      assert response["openapi"] =~ "3."
      assert response["info"]["title"] == "Ricqchet API"
      assert response["info"]["version"]
      assert is_map(response["paths"])
      assert is_map(response["components"])
    end
  end

  describe "GET /api/docs" do
    test "returns Swagger UI HTML", %{conn: conn} do
      conn = get(conn, "/api/docs")

      assert html_response(conn, 200) =~ "swagger"
    end
  end
end
