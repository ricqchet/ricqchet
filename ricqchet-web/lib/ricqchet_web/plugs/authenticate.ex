defmodule RicqchetWeb.Plugs.Authenticate do
  @moduledoc """
  Plug for authenticating API requests using Bearer tokens.

  Extracts the API key from the Authorization header and looks up the
  corresponding tenant and application. If authentication succeeds,
  assigns are set for:
  - `current_tenant` - the tenant owning the application
  - `current_application` - the application the API key belongs to
  - `current_api_key` - the API key record used for authentication

  ## Usage

      plug RicqchetWeb.Plugs.Authenticate

  """

  import Plug.Conn

  alias Ricqchet.ApiKeys

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, api_key} <- extract_api_key(conn),
         %{tenant: tenant, application: application, api_key: api_key_record} <-
           ApiKeys.get_by_api_key(api_key) do
      conn
      |> assign(:current_tenant, tenant)
      |> assign(:current_application, application)
      |> assign(:current_api_key, api_key_record)
    else
      _ -> unauthorized(conn)
    end
  end

  defp extract_api_key(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> api_key] -> {:ok, api_key}
      _ -> :error
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.put_view(json: RicqchetWeb.ErrorJSON)
    |> Phoenix.Controller.render(:error,
      error: "unauthorized",
      message: "Invalid or missing API key"
    )
    |> halt()
  end
end
