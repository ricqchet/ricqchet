defmodule RelayWeb.ErrorJSON do
  @moduledoc """
  JSON error responses for the API.
  """

  @doc """
  Renders error responses in JSON format.

  Supports custom errors with error code and message, as well as
  standard HTTP error codes like 404 and 500.
  """
  def render("error.json", %{error: error, message: message}) do
    %{error: error, message: message}
  end

  def render("404.json", _assigns) do
    %{error: "not_found", message: "Resource not found"}
  end

  def render("500.json", _assigns) do
    %{error: "internal_error", message: "Internal server error"}
  end

  def render(template, _assigns) do
    %{error: "error", message: Phoenix.Controller.status_message_from_template(template)}
  end
end
