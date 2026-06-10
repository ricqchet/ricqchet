defmodule Ricqchet.Tenants.Tenant do
  @moduledoc """
  Schema for tenants.

  Each tenant represents a user/organization that can publish messages through Ricqchet.
  Tenants have applications which contain API keys for authentication.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @signing_secret_bytes 32

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          status: String.t(),
          default_max_retries: integer(),
          signing_secret: binary() | nil,
          messages: [Ricqchet.Messages.Message.t()] | Ecto.Association.NotLoaded.t(),
          batches: [Ricqchet.Batches.Batch.t()] | Ecto.Association.NotLoaded.t(),
          applications: [Ricqchet.Applications.Application.t()] | Ecto.Association.NotLoaded.t(),
          users: [Ricqchet.Users.User.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "tenants" do
    field :name, :string
    field :status, :string, default: "active"
    field :default_max_retries, :integer, default: 3
    field :signing_secret, :binary

    has_many :messages, Ricqchet.Messages.Message
    has_many :batches, Ricqchet.Batches.Batch
    has_many :applications, Ricqchet.Applications.Application
    has_many :users, Ricqchet.Users.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :status, :default_max_retries])
    |> validate_required([:name])
    |> validate_inclusion(:status, ["active", "suspended"])
    |> validate_number(:default_max_retries,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10
    )
    |> maybe_generate_signing_secret()
  end

  defp maybe_generate_signing_secret(changeset) do
    case get_field(changeset, :signing_secret) do
      nil -> put_change(changeset, :signing_secret, generate_signing_secret())
      _ -> changeset
    end
  end

  defp generate_signing_secret do
    :crypto.strong_rand_bytes(@signing_secret_bytes)
  end
end
