defmodule Ricqchet.Tenants.Tenant do
  @moduledoc """
  Schema for tenants.

  Each tenant represents a user/organization that can publish messages through Ricqchet.
  Tenants authenticate using API keys, which are stored as Argon2 hashes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Length of the API key prefix used for O(1) lookup
  @api_key_prefix_length 8

  schema "tenants" do
    field :name, :string
    field :api_key_hash, :binary
    field :api_key_prefix, :string
    field :status, :string, default: "active"
    field :default_max_retries, :integer, default: 3

    # Virtual field for the plaintext API key (only set on creation)
    field :api_key, :string, virtual: true

    has_many :messages, Ricqchet.Messages.Message

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Returns the prefix length used for API key lookups.
  """
  def api_key_prefix_length, do: @api_key_prefix_length

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
  end

  @doc """
  Changeset for creating a new tenant with an API key.
  """
  def create_changeset(tenant, attrs) do
    tenant
    |> changeset(attrs)
    |> put_api_key()
  end

  defp put_api_key(changeset) do
    api_key = generate_api_key()
    api_key_hash = Argon2.hash_pwd_salt(api_key)
    api_key_prefix = String.slice(api_key, 0, @api_key_prefix_length)

    changeset
    |> put_change(:api_key, api_key)
    |> put_change(:api_key_hash, api_key_hash)
    |> put_change(:api_key_prefix, api_key_prefix)
  end

  defp generate_api_key do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
