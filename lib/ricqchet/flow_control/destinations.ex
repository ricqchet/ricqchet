defmodule Ricqchet.FlowControl.Destinations do
  @moduledoc """
  Context module for destination flow control configuration.
  """

  import Ecto.Query

  alias Ricqchet.FlowControl.Destination
  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Tenant

  @doc """
  Gets a destination by ID.
  """
  def get(id), do: Repo.get(Destination, id)

  @doc """
  Gets a destination by tenant and URL.
  """
  def get_by_url(%Tenant{id: tenant_id}, destination_url) do
    Destination
    |> where([d], d.tenant_id == ^tenant_id and d.destination_url == ^destination_url)
    |> Repo.one()
  end

  @doc """
  Lists all destinations for a tenant.
  """
  def list_by_tenant(%Tenant{id: tenant_id}) do
    Destination
    |> where([d], d.tenant_id == ^tenant_id)
    |> order_by([d], asc: d.destination_url)
    |> Repo.all()
  end

  @doc """
  Creates a new destination for a tenant.
  """
  def create(%Tenant{} = tenant, attrs) do
    %Destination{}
    |> Destination.create_changeset(tenant, attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a destination's flow control settings.
  """
  def update(%Destination{} = destination, attrs) do
    destination
    |> Destination.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets or creates a destination for the given tenant and URL.

  If the destination exists and flow_control settings are provided,
  updates the existing destination with those settings.
  """
  def get_or_create(%Tenant{} = tenant, destination_url, flow_control \\ nil) do
    case get_by_url(tenant, destination_url) do
      nil ->
        attrs = build_attrs(destination_url, flow_control)
        create(tenant, attrs)

      %Destination{} = destination ->
        maybe_update_settings(destination, flow_control)
    end
  end

  @doc """
  Upserts a destination - creates if not exists, updates if flow_control provided.

  Uses database-level upsert for atomicity.
  """
  def upsert(%Tenant{} = tenant, destination_url, flow_control \\ nil) do
    now = DateTime.utc_now()
    attrs = build_attrs(destination_url, flow_control)

    conflict_updates =
      if flow_control do
        [
          set: [
            parallelism: flow_control[:parallelism],
            rate_limit: flow_control[:rate_limit],
            updated_at: now
          ]
        ]
      else
        [set: [updated_at: now]]
      end

    result =
      %Destination{}
      |> Destination.create_changeset(tenant, attrs)
      |> Repo.insert(
        on_conflict: conflict_updates,
        conflict_target: [:tenant_id, :destination_url],
        returning: true
      )

    case result do
      {:ok, destination} -> {:ok, destination}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a destination.
  """
  def delete(%Destination{} = destination) do
    Repo.delete(destination)
  end

  # Private

  defp build_attrs(destination_url, nil) do
    %{destination_url: destination_url}
  end

  defp build_attrs(destination_url, flow_control) do
    %{
      destination_url: destination_url,
      parallelism: flow_control[:parallelism],
      rate_limit: flow_control[:rate_limit]
    }
  end

  defp maybe_update_settings(destination, nil), do: {:ok, destination}

  defp maybe_update_settings(destination, flow_control) do
    destination
    |> Destination.changeset(%{
      parallelism: flow_control[:parallelism],
      rate_limit: flow_control[:rate_limit]
    })
    |> Repo.update()
  end
end
