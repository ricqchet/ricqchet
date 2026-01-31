defmodule Ricqchet.Applications.Application do
  @moduledoc """
  Schema for applications.

  Applications represent software/services within a tenant that can use the Ricqchet API.
  Each application can have multiple API keys for authentication.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "applications" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :dlq_destination_url, :string

    belongs_to :tenant, Ricqchet.Tenants.Tenant
    has_many :api_keys, Ricqchet.ApiKeys.ApiKey
    has_many :messages, Ricqchet.Messages.Message
    has_many :batches, Ricqchet.Batches.Batch

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(application, attrs) do
    application
    |> cast(attrs, [:name, :description, :status, :dlq_destination_url])
    |> validate_required([:name])
    |> validate_inclusion(:status, ["active", "suspended"])
    |> foreign_key_constraint(:tenant_id)
  end

  @doc """
  Changeset for creating a new application within a tenant.
  """
  def create_changeset(application, tenant, attrs) do
    application
    |> changeset(attrs)
    |> put_assoc(:tenant, tenant)
  end
end
