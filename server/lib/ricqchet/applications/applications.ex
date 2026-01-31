defmodule Ricqchet.Applications do
  @moduledoc """
  Context module for application operations.
  """

  import Ecto.Query

  alias Ricqchet.Applications.Application
  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Tenant

  @doc """
  Creates a new application for a tenant.

  ## Examples

      iex> create_application(tenant, %{name: "My App"})
      {:ok, %Application{}}

  """
  def create_application(%Tenant{} = tenant, attrs \\ %{}) do
    %Application{}
    |> Application.create_changeset(tenant, attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an application by ID.
  """
  def get_application(id), do: Repo.get(Application, id)

  @doc """
  Gets an application by ID, raising if not found.
  """
  def get_application!(id), do: Repo.get!(Application, id)

  @doc """
  Gets an application by ID, scoped to a tenant.

  Returns `nil` if the application doesn't exist or doesn't belong to the tenant.
  """
  def get_application_by_tenant(%Tenant{id: tenant_id}, application_id) do
    Application
    |> where([a], a.id == ^application_id and a.tenant_id == ^tenant_id)
    |> Repo.one()
  end

  @doc """
  Lists all applications for a tenant.
  """
  def list_applications_for_tenant(%Tenant{id: tenant_id}) do
    Application
    |> where([a], a.tenant_id == ^tenant_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Updates an application.
  """
  def update_application(%Application{} = application, attrs) do
    application
    |> Application.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an application.
  """
  def delete_application(%Application{} = application) do
    Repo.delete(application)
  end

  @doc """
  Gets the DLQ destination URL for an application.

  Returns `nil` if not configured or the application doesn't exist.
  """
  def get_dlq_destination(%Application{dlq_destination_url: url}), do: url
  def get_dlq_destination(nil), do: nil
end
