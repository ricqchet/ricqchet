defmodule Ricqchet.FlowControl.Destination do
  @moduledoc """
  Schema for destination flow control configuration.

  Destinations define per-URL flow control settings for a tenant:
  - `parallelism` - Max concurrent in-flight messages (nil = unlimited)
  - `rate_limit` - Max requests per second (nil = unlimited)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ricqchet.UrlValidator

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "destinations" do
    field :destination_url, :string
    field :parallelism, :integer
    field :rate_limit, :integer

    belongs_to :tenant, Ricqchet.Tenants.Tenant
    has_many :messages, Ricqchet.Messages.Message
    has_one :state, Ricqchet.FlowControl.State

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(destination, attrs) do
    destination
    |> cast(attrs, [:destination_url, :parallelism, :rate_limit])
    |> validate_required([:destination_url])
    |> validate_destination_url()
    |> validate_number(:parallelism, greater_than: 0, less_than_or_equal_to: 1000)
    |> validate_number(:rate_limit, greater_than: 0, less_than_or_equal_to: 10_000)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:tenant_id, :destination_url])
  end

  @doc """
  Changeset for creating a new destination within a tenant.
  """
  def create_changeset(destination, tenant, attrs) do
    destination
    |> changeset(attrs)
    |> put_assoc(:tenant, tenant)
  end

  defp validate_destination_url(changeset) do
    validate_change(changeset, :destination_url, fn :destination_url, url ->
      case UrlValidator.validate_url(url) do
        :ok -> []
        {:error, reason} -> [destination_url: reason]
      end
    end)
  end
end
