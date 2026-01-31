defmodule RicqchetWeb.ErrorJSONTest do
  use RicqchetWeb.ConnCase, async: true

  test "renders 404" do
    assert RicqchetWeb.ErrorJSON.render("404.json", %{}) ==
             %{error: "not_found", message: "Resource not found"}
  end

  test "renders 500" do
    assert RicqchetWeb.ErrorJSON.render("500.json", %{}) ==
             %{error: "internal_error", message: "Internal server error"}
  end

  test "renders custom error" do
    assert RicqchetWeb.ErrorJSON.render("error.json", %{
             error: "test_error",
             message: "Test message"
           }) ==
             %{error: "test_error", message: "Test message"}
  end
end
