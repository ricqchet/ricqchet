defmodule RicqchetWeb.Plugs.RequireScope do
  @moduledoc """
  Plug that restricts the REST relay surface to full `relay` API keys.

  Runs *after* `RicqchetWeb.Plugs.Authenticate` (which sets `:current_api_key`)
  in the `:authenticated` pipeline. Browser-safe `subscribe` keys are rejected
  with `403 Forbidden` on every key-authenticated REST endpoint, so a key that
  is safe to embed in a browser can never publish, read the webhook signing
  secret, or disconnect users over REST. Those keys are only usable on the
  channels WebSocket.

  ## Usage

      plug RicqchetWeb.Plugs.RequireScope, scope: :relay

  Fails closed: if the authenticated key is missing or its scope is anything
  other than the exact `relay` value, the request is rejected.
  """

  import Plug.Conn

  alias Ricqchet.ApiKeys.Scope

  @behaviour Plug

  @impl Plug
  def init(opts), do: Keyword.put_new(opts, :scope, :relay)

  @impl Plug
  def call(conn, opts) do
    case Keyword.fetch!(opts, :scope) do
      :relay -> require_relay(conn)
    end
  end

  defp require_relay(conn) do
    if Scope.can_relay?(conn.assigns[:current_api_key]) do
      conn
    else
      forbidden(conn)
    end
  end

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.put_view(json: RicqchetWeb.ErrorJSON)
    |> Phoenix.Controller.render(:error,
      error: "forbidden",
      message: "This API key is not permitted to use the REST API (subscribe-only key)."
    )
    |> halt()
  end
end
