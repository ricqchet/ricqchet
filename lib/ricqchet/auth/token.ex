defmodule Ricqchet.Auth.Token do
  @moduledoc """
  JWT token generation and verification.

  Handles access tokens (short-lived, 15 minutes) for API authentication.
  Uses HS256 signing algorithm with the configured JWT secret.

  ## Token Claims

  Access tokens include:
  - `sub` - User ID
  - `tid` - Tenant ID
  - `ver` - Token version (for invalidation)
  - `role` - User role
  - `typ` - Token type ("access")
  - `exp` - Expiration timestamp
  - `iat` - Issued at timestamp
  """

  use Joken.Config

  alias Ricqchet.Users.User

  @impl Joken.Config
  def token_config do
    default_claims(skip: [:aud, :iss, :jti, :nbf])
  end

  @doc """
  Generates an access token for a user.

  Returns `{:ok, token, claims}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> Token.generate_access_token(user)
      {:ok, "eyJ...", %{"sub" => "user-id", ...}}
  """
  @spec generate_access_token(User.t()) :: {:ok, String.t(), map()} | {:error, term()}
  def generate_access_token(%User{} = user) do
    ttl = Application.get_env(:ricqchet, :jwt_access_token_ttl, 15 * 60)

    claims = %{
      "sub" => user.id,
      "tid" => user.tenant_id,
      "ver" => user.token_version,
      "role" => user.role,
      "typ" => "access"
    }

    generate_and_sign(claims, signer(), exp: ttl)
  end

  @doc """
  Verifies an access token and returns its claims.

  Returns `{:ok, claims}` if the token is valid, or `{:error, reason}` if invalid.

  ## Examples

      iex> Token.verify_access_token("eyJ...")
      {:ok, %{"sub" => "user-id", "ver" => 1, ...}}

      iex> Token.verify_access_token("invalid")
      {:error, :invalid_token}
  """
  @spec verify_access_token(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_access_token(token) when is_binary(token) do
    case verify_and_validate(token, signer()) do
      {:ok, %{"typ" => "access"} = claims} ->
        {:ok, claims}

      {:ok, _claims} ->
        {:error, :invalid_token_type}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp signer do
    secret = Application.fetch_env!(:ricqchet, :jwt_secret)
    Joken.Signer.create("HS256", secret)
  end

  defp generate_and_sign(claims, signer, opts) do
    exp = Keyword.get(opts, :exp, 900)
    now = DateTime.to_unix(DateTime.utc_now())

    claims =
      claims
      |> Map.put("iat", now)
      |> Map.put("exp", now + exp)

    {:ok, token} = Joken.Signer.sign(claims, signer)
    {:ok, token, claims}
  end
end
