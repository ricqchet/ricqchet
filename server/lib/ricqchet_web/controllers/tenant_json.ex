defmodule RicqchetWeb.TenantJSON do
  @moduledoc """
  JSON views for tenant endpoints.
  """

  @doc """
  Renders the signing secret as base64-encoded string.
  """
  def render("signing_secret.json", %{signing_secret: signing_secret}) do
    %{
      signing_secret: Base.encode64(signing_secret)
    }
  end
end
