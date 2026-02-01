defmodule Ricqchet.ApiKeys do
  @moduledoc """
  Context module for API key operations.
  """

  import Ecto.Query

  alias Ricqchet.ApiKeys.ApiKey
  alias Ricqchet.Applications.Application
  alias Ricqchet.Repo

  @doc """
  Creates a new API key for an application.

  Returns `{:ok, %ApiKey{api_key: "..."}}` with the plaintext API key
  available in the `api_key` virtual field. This is the only time the
  plaintext key is available - it is not stored in the database.

  ## Examples

      iex> create_api_key(application, %{name: "Production Key"})
      {:ok, %ApiKey{api_key: "generated_key_here"}}

  """
  def create_api_key(%Application{} = application, attrs \\ %{}) do
    %ApiKey{}
    |> ApiKey.create_changeset(application, attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an API key by ID.
  """
  def get_api_key(id), do: Repo.get(ApiKey, id)

  @doc """
  Gets an API key by ID, raising if not found.
  """
  def get_api_key!(id), do: Repo.get!(ApiKey, id)

  @doc """
  Gets an API key by its plaintext value, with preloaded application and tenant.

  Uses a prefix-based O(1) lookup to find the candidate API key,
  then performs constant-time Argon2 verification.

  Returns a map with `%{api_key: %ApiKey{}, application: %Application{}, tenant: %Tenant{}}`
  or `nil` if no matching active key is found.

  ## Examples

      iex> get_by_api_key("valid_key")
      %{api_key: %ApiKey{}, application: %Application{}, tenant: %Tenant{}}

      iex> get_by_api_key("invalid_key")
      nil

  """
  def get_by_api_key(api_key) when is_binary(api_key) do
    prefix_length = ApiKey.api_key_prefix_length()
    prefix = String.slice(api_key, 0, prefix_length)

    # O(1) lookup using the prefix index, with preloaded associations
    result =
      ApiKey
      |> where([k], k.api_key_prefix == ^prefix)
      |> where([k], k.status == "active")
      |> where([k], is_nil(k.expires_at) or k.expires_at > ^DateTime.utc_now())
      |> join(:inner, [k], a in assoc(k, :application))
      |> where([k, a], a.status == "active")
      |> join(:inner, [k, a], t in assoc(a, :tenant))
      |> where([k, a, t], t.status == "active")
      |> preload([k, a, t], application: {a, tenant: t})
      |> Repo.one()

    # Constant-time verification to prevent timing attacks
    verify_api_key(result, api_key)
  end

  def get_by_api_key(_), do: nil

  @doc """
  Lists all API keys for an application.
  """
  def list_api_keys_for_application(%Application{id: application_id}) do
    ApiKey
    |> where([k], k.application_id == ^application_id)
    |> order_by([k], desc: k.inserted_at)
    |> Repo.all()
  end

  @doc """
  Revokes an API key.
  """
  def revoke_api_key(%ApiKey{} = api_key) do
    api_key
    |> ApiKey.revoke_changeset()
    |> Repo.update()
  end

  @doc """
  Updates the last_used_at timestamp for an API key.

  This is a non-blocking operation that can be called asynchronously.
  """
  def touch_last_used(%ApiKey{} = api_key) do
    api_key
    |> ApiKey.touch_changeset()
    |> Repo.update()
  end

  @doc """
  Rotates an API key by revoking the old one and creating a new one.

  Returns `{:ok, %ApiKey{api_key: "..."}}` with the new plaintext value,
  or `{:error, reason}` on failure.
  """
  def rotate_api_key(%ApiKey{} = old_api_key) do
    application = Repo.preload(old_api_key, :application).application

    Repo.transaction(fn ->
      {:ok, _revoked} = revoke_api_key(old_api_key)

      case create_api_key(application, %{name: old_api_key.name}) do
        {:ok, new_api_key} -> new_api_key
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # Always perform the hash comparison to ensure constant timing
  defp verify_api_key(nil, _api_key) do
    # Perform a dummy verification to prevent timing attacks
    Argon2.no_user_verify()
    nil
  end

  defp verify_api_key(api_key_record, api_key) do
    if Argon2.verify_pass(api_key, api_key_record.api_key_hash) do
      %{
        api_key: api_key_record,
        application: api_key_record.application,
        tenant: api_key_record.application.tenant
      }
    else
      nil
    end
  end
end
