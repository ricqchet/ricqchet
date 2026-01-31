defmodule Ricqchet.UrlValidator do
  @moduledoc """
  Validates URLs to prevent SSRF (Server-Side Request Forgery) attacks.

  This module provides URL validation that blocks requests to:
  - Private/internal IP ranges (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
  - Loopback addresses (127.x.x.x, ::1)
  - Link-local addresses (169.254.x.x, fe80::)
  - Cloud metadata endpoints (169.254.169.254)
  - localhost and other local hostnames
  """

  import Bitwise

  @blocked_hostnames ~w(
    localhost
    localhost.localdomain
    ip6-localhost
    ip6-loopback
  )

  @blocked_suffixes ~w(.local .localhost .internal)

  @doc """
  Validates that a URL is safe to request.

  Returns `:ok` if the URL is valid and safe, or `{:error, reason}` otherwise.

  ## Examples

      iex> validate_url("https://example.com/api")
      :ok

      iex> validate_url("http://127.0.0.1/admin")
      {:error, "URL resolves to blocked IP address"}

      iex> validate_url("http://169.254.169.254/metadata")
      {:error, "URL resolves to blocked IP address"}
  """
  def validate_url(url) when is_binary(url) do
    with {:ok, uri} <- parse_uri(url),
         :ok <- validate_scheme(uri) do
      validate_host(uri)
    end
  end

  def validate_url(_), do: {:error, "URL must be a string"}

  defp parse_uri(url) do
    case URI.parse(url) do
      %URI{scheme: nil} -> {:error, "URL must have a scheme"}
      %URI{host: nil} -> {:error, "URL must have a host"}
      %URI{host: ""} -> {:error, "URL must have a host"}
      uri -> {:ok, uri}
    end
  end

  defp validate_scheme(%URI{scheme: scheme}) when scheme in ["http", "https"], do: :ok
  defp validate_scheme(_), do: {:error, "URL scheme must be http or https"}

  defp validate_host(%URI{host: host}) do
    host = String.downcase(host)

    if blocked_hostname?(host) do
      {:error, "URL host is not allowed"}
    else
      validate_host_resolution(host)
    end
  end

  defp blocked_hostname?(host) do
    host in @blocked_hostnames or
      Enum.any?(@blocked_suffixes, &String.ends_with?(host, &1))
  end

  defp validate_host_resolution(host) do
    case parse_ip_address(host) do
      {:ok, ip} ->
        check_ip_blocked(ip)

      :error ->
        resolve_and_check_hostname(host)
    end
  end

  defp check_ip_blocked(ip) do
    if blocked_ip?(ip) do
      {:error, "URL resolves to blocked IP address"}
    else
      :ok
    end
  end

  defp resolve_and_check_hostname(host) do
    case resolve_hostname(host) do
      {:ok, ips} ->
        if Enum.any?(ips, &blocked_ip?/1) do
          {:error, "URL resolves to blocked IP address"}
        else
          :ok
        end

      {:error, _reason} ->
        # Allow unresolvable hostnames - they'll fail at request time
        # This is safer than blocking legitimate hosts with temporary DNS issues
        :ok
    end
  end

  defp parse_ip_address(host) do
    host_charlist = String.to_charlist(host)

    case :inet.parse_address(host_charlist) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> :error
    end
  end

  defp resolve_hostname(host) do
    host_charlist = String.to_charlist(host)

    case :inet.getaddr(host_charlist, :inet) do
      {:ok, ip4} ->
        case :inet.getaddr(host_charlist, :inet6) do
          {:ok, ip6} -> {:ok, [ip4, ip6]}
          {:error, _} -> {:ok, [ip4]}
        end

      {:error, _} ->
        case :inet.getaddr(host_charlist, :inet6) do
          {:ok, ip6} -> {:ok, [ip6]}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # IPv4 blocked ranges
  defp blocked_ip?({127, _, _, _}), do: true
  defp blocked_ip?({10, _, _, _}), do: true
  defp blocked_ip?({172, b, _, _}) when b >= 16 and b <= 31, do: true
  defp blocked_ip?({192, 168, _, _}), do: true
  defp blocked_ip?({169, 254, _, _}), do: true
  defp blocked_ip?({255, 255, 255, 255}), do: true
  defp blocked_ip?({0, _, _, _}), do: true

  # IPv6 blocked ranges
  defp blocked_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp blocked_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp blocked_ip?({a, _, _, _, _, _, _, _}) when a >= 0xFE80 and a <= 0xFEBF, do: true
  defp blocked_ip?({a, _, _, _, _, _, _, _}) when a >= 0xFC00 and a <= 0xFDFF, do: true

  # IPv4-mapped IPv6 addresses (::ffff:x.x.x.x)
  defp blocked_ip?({0, 0, 0, 0, 0, 0xFFFF, high, low}) do
    ipv4 = {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}
    blocked_ip?(ipv4)
  end

  defp blocked_ip?(_), do: false
end
