defmodule RicqchetWeb.Plugs.Authenticate do
  @moduledoc """
  Plug for authenticating API requests using Bearer tokens.

  Extracts the API key from the Authorization header and looks up the
  corresponding tenant. If authentication succeeds, the tenant is assigned
  to `conn.assigns.current_tenant`.

  ## Usage

      plug RicqchetWeb.Plugs.Authenticate

  """

  import Plug.Conn

  alias Ricqchet.Tenants

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, api_key} <- extract_api_key(conn),
         %{} = tenant <- Tenants.get_by_api_key(api_key) do
      assign(conn, :current_tenant, tenant)
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
