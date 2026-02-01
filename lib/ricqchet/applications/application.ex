defmodule Ricqchet.Applications.Application do
  @moduledoc """
  Schema for applications.

  Applications represent software/services within a tenant that can use the Ricqchet API.
  Each application can have multiple API keys for authentication.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ricqchet.UrlValidator

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:name, :status],
    sortable: [:name, :status, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  @type t :: %__MODULE__{}

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
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 255)
    |> validate_inclusion(:status, ["active", "suspended"])
    |> validate_dlq_destination_url()
    |> foreign_key_constraint(:tenant_id)
  end

  defp validate_dlq_destination_url(changeset) do
    validate_change(changeset, :dlq_destination_url, fn :dlq_destination_url, url ->
      case validate_dlq_url(url) do
        :ok -> []
        {:error, reason} -> [dlq_destination_url: reason]
      end
    end)
  end

  defp validate_dlq_url(nil), do: :ok
  defp validate_dlq_url(""), do: :ok

  defp validate_dlq_url(url) when is_binary(url) do
    url = String.trim(url)

    case URI.parse(url) do
      %URI{scheme: "https"} ->
        UrlValidator.validate_url(url)

      %URI{scheme: "http"} ->
        {:error, "DLQ destination must use HTTPS for security"}

      _ ->
        {:error, "DLQ destination must be a valid HTTPS URL"}
    end
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
