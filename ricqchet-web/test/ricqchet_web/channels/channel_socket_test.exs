defmodule RicqchetWeb.Channels.ChannelSocketTest do
  use RicqchetWeb.ChannelCase, async: false

  import Ricqchet.DataCase, only: [create_tenant_with_api_key: 0]

  alias Ricqchet.ApiKeys
  alias RicqchetWeb.Channels.ChannelSocket

  setup do
    {:ok, %{tenant: tenant, application: app, api_key: api_key}} =
      create_tenant_with_api_key()

    # Enable channels for the application
    {:ok, application} =
      app
      |> Ecto.Changeset.change(channels_enabled: true)
      |> Ricqchet.Repo.update()

    %{tenant: tenant, application: application, api_key: api_key}
  end

  describe "connect/3" do
    test "connects with valid API key", %{api_key: api_key, application: application} do
      assert {:ok, socket} =
               connect(ChannelSocket, %{
                 "api_key" => api_key.api_key,
                 "user_id" => "user_123"
               })

      assert socket.assigns.application_id == application.id
      assert socket.assigns.user_id == "user_123"
    end

    test "connects with a browser-safe subscribe-scoped API key", %{application: application} do
      {:ok, sub_key} =
        ApiKeys.create_api_key(application, %{name: "Browser Key", scope: "subscribe"})

      assert {:ok, socket} =
               connect(ChannelSocket, %{
                 "api_key" => sub_key.api_key,
                 "user_id" => "user_123"
               })

      assert socket.assigns.application_id == application.id
    end

    test "assigns a stable socket_id and a server-generated connection_id", %{
      api_key: api_key,
      application: application
    } do
      {:ok, socket} =
        connect(ChannelSocket, %{"api_key" => api_key.api_key, "user_id" => "user_123"})

      assert socket.assigns.socket_id == "channel_socket:#{application.id}:user_123"
      # connection_id is server-generated, opaque, and independent of user_id
      assert is_binary(socket.assigns.connection_id)
      refute socket.assigns.connection_id =~ "user_123"
    end

    test "assigns default user_id when not provided", %{api_key: api_key} do
      assert {:ok, socket} =
               connect(ChannelSocket, %{"api_key" => api_key.api_key})

      assert socket.assigns.user_id == "anonymous"
    end

    test "parses user_info JSON", %{api_key: api_key} do
      user_info = Jason.encode!(%{"name" => "Test User", "avatar" => "url"})

      assert {:ok, socket} =
               connect(ChannelSocket, %{
                 "api_key" => api_key.api_key,
                 "user_id" => "user_123",
                 "user_info" => user_info
               })

      assert socket.assigns.user_info == %{"name" => "Test User", "avatar" => "url"}
    end

    test "rejects missing api_key" do
      assert :error = connect(ChannelSocket, %{})
    end

    test "rejects invalid api_key" do
      assert :error =
               connect(ChannelSocket, %{"api_key" => "invalid_key_here"})
    end

    test "rejects when channels_enabled is false", %{
      application: application,
      api_key: api_key
    } do
      {:ok, _} =
        application
        |> Ecto.Changeset.change(channels_enabled: false)
        |> Ricqchet.Repo.update()

      assert :error =
               connect(ChannelSocket, %{"api_key" => api_key.api_key})
    end
  end

  describe "id/1" do
    test "returns socket id with application and user", %{
      api_key: api_key,
      application: application
    } do
      {:ok, socket} =
        connect(ChannelSocket, %{
          "api_key" => api_key.api_key,
          "user_id" => "user_456"
        })

      assert ChannelSocket.id(socket) ==
               "channel_socket:#{application.id}:user_456"
    end
  end
end
