defmodule Ricqchet.Config do
  @moduledoc """
  Configuration helpers for Ricqchet client and verification modules.
  """

  @doc """
  Resolves a configuration value that may reference an environment variable.

  ## Examples

      iex> Ricqchet.Config.resolve("direct_value")
      "direct_value"

      iex> System.put_env("MY_API_KEY", "secret123")
      iex> Ricqchet.Config.resolve({:system, "MY_API_KEY"})
      "secret123"

  """
  @spec resolve(String.t() | {:system, String.t()}) :: String.t() | nil
  def resolve({:system, env_var}) when is_binary(env_var) do
    System.get_env(env_var)
  end

  def resolve(value) when is_binary(value), do: value
  def resolve(nil), do: nil
end
