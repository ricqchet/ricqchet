defmodule RelayWeb.ErrorJSONTest do
  use RelayWeb.ConnCase, async: true

  test "renders 404" do
    assert RelayWeb.ErrorJSON.render("404.json", %{}) ==
             %{error: "not_found", message: "Resource not found"}
  end

  test "renders 500" do
    assert RelayWeb.ErrorJSON.render("500.json", %{}) ==
             %{error: "internal_error", message: "Internal server error"}
  end

  test "renders custom error" do
    assert RelayWeb.ErrorJSON.render("error.json", %{error: "test_error", message: "Test message"}) ==
             %{error: "test_error", message: "Test message"}
  end
end
