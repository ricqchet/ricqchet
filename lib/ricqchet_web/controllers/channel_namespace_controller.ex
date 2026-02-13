defmodule RicqchetWeb.ChannelNamespaceController do
  @moduledoc """
  Controller for channel namespace configuration.

  Namespaces define pattern-based configuration for channels within an application.
  They control features like history, authentication, and member limits.

  ## Authorization

  - **List**: Any authenticated tenant member
  - **Create/Update/Delete**: Tenant admin only
  """

  use RicqchetWeb, :controller

  alias Ricqchet.Applications
  alias Ricqchet.Channels.NamespaceConfig
  alias Ricqchet.Channels.Namespaces
  alias Ricqchet.Users.User

  action_fallback RicqchetWeb.FallbackController

  def index(conn, %{"application_id" => app_id}) do
    tenant = conn.assigns.current_tenant

    with {:ok, application} <- get_application_or_error(tenant, app_id) do
      namespaces = Namespaces.list_namespaces(application.id)
      render(conn, :index, namespaces: namespaces)
    end
  end

  def create(conn, %{"application_id" => app_id} = params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, application} <- get_application_or_error(tenant, app_id),
         {:ok, namespace} <-
           Namespaces.create_namespace(
             Map.drop(params, ["application_id"]),
             application.id,
             tenant.id
           ) do
      NamespaceConfig.invalidate_cache(application.id)

      conn
      |> put_status(:created)
      |> render(:show, namespace: namespace)
    end
  end

  def update(conn, %{"application_id" => app_id, "id" => id} = params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, application} <- get_application_or_error(tenant, app_id),
         {:ok, namespace} <- get_namespace_or_error(id, application.id),
         {:ok, updated} <-
           Namespaces.update_namespace(namespace, Map.drop(params, ["application_id", "id"])) do
      NamespaceConfig.invalidate_cache(application.id)
      render(conn, :show, namespace: updated)
    end
  end

  def delete(conn, %{"application_id" => app_id, "id" => id}) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, application} <- get_application_or_error(tenant, app_id),
         {:ok, namespace} <- get_namespace_or_error(id, application.id),
         {:ok, _deleted} <- Namespaces.delete_namespace(namespace) do
      NamespaceConfig.invalidate_cache(application.id)
      send_resp(conn, :no_content, "")
    end
  end

  defp authorize_admin(%User{role: "admin"}), do: :ok
  defp authorize_admin(_user), do: {:error, :forbidden}

  defp get_application_or_error(tenant, app_id) do
    case Applications.get_application_by_tenant(tenant, app_id) do
      nil -> {:error, :not_found}
      application -> {:ok, application}
    end
  end

  defp get_namespace_or_error(id, application_id) do
    case Namespaces.get_namespace(id, application_id) do
      nil -> {:error, :not_found}
      namespace -> {:ok, namespace}
    end
  end
end
