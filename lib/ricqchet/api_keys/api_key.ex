defmodule Ricqchet.ApiKeys.ApiKey do
  @moduledoc """
  Schema for API keys.

  API keys are used to authenticate requests to the Ricqchet API.
  Each API key belongs to an application and uses Argon2 hashing
  with a prefix-based O(1) lookup for efficient authentication.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Length of the API key prefix used for O(1) lookup
  @api_key_prefix_length 8

  schema "api_keys" do
    field :name, :string
    field :api_key_hash, :binary
    field :api_key_prefix, :string
    field :status, :string, default: "active"
    field :last_used_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    # Virtual field for the plaintext API key (only set on creation)
    field :api_key, :string, virtual: true

    belongs_to :application, Ricqchet.Applications.Application

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Returns the prefix length used for API key lookups.
  """
  def api_key_prefix_length, do: @api_key_prefix_length

  @doc false
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :status, :expires_at])
    |> validate_required([:name])
    |> validate_inclusion(:status, ["active", "revoked"])
    |> foreign_key_constraint(:application_id)
  end

  @doc """
  Changeset for creating a new API key for an application.
  Generates the API key and stores its hash.
  """
  def create_changeset(api_key, application, attrs) do
    api_key
    |> changeset(attrs)
    |> put_assoc(:application, application)
    |> put_api_key()
  end

  @doc """
  Changeset for revoking an API key.
  """
  def revoke_changeset(api_key) do
    change(api_key, %{status: "revoked"})
  end

  @doc """
  Changeset for updating last_used_at timestamp.
  """
  def touch_changeset(api_key) do
    change(api_key, %{last_used_at: DateTime.utc_now()})
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
