defmodule RicqchetWeb.CorsConfigTest do
  use ExUnit.Case, async: true

  alias RicqchetWeb.CorsConfig

  describe "allowed_origin?/2" do
    test "returns true for allowed origin from config" do
      assert CorsConfig.allowed_origin?(nil, "http://localhost:3000")
    end

    test "returns false for disallowed origin" do
      refute CorsConfig.allowed_origin?(nil, "http://evil.com")
    end
  end

  describe "get_allowed_origins/0" do
    test "returns origins from config when env var not set" do
      origins = CorsConfig.get_allowed_origins()
      assert "http://localhost:3000" in origins
      assert "http://localhost:4000" in origins
    end

    test "returns origins from env var when set" do
      System.put_env(
        "CORS_ALLOWED_ORIGINS",
        "https://app.example.com,https://dashboard.example.com"
      )

      try do
        origins = CorsConfig.get_allowed_origins()
        assert origins == ["https://app.example.com", "https://dashboard.example.com"]
      after
        System.delete_env("CORS_ALLOWED_ORIGINS")
      end
    end

    test "handles whitespace in env var" do
      System.put_env(
        "CORS_ALLOWED_ORIGINS",
        " https://app.example.com , https://dashboard.example.com "
      )

      try do
        origins = CorsConfig.get_allowed_origins()
        assert origins == ["https://app.example.com", "https://dashboard.example.com"]
      after
        System.delete_env("CORS_ALLOWED_ORIGINS")
      end
    end

    test "filters empty strings from env var" do
      System.put_env(
        "CORS_ALLOWED_ORIGINS",
        "https://app.example.com,,https://dashboard.example.com,"
      )

      try do
        origins = CorsConfig.get_allowed_origins()
        assert origins == ["https://app.example.com", "https://dashboard.example.com"]
      after
        System.delete_env("CORS_ALLOWED_ORIGINS")
      end
    end
  end
end
