defmodule Ricqchet.Channels.TelemetryTest do
  use Ricqchet.DataCase, async: true

  alias Ricqchet.Channels.EventPublisher
  alias Ricqchet.Channels.Namespaces

  setup do
    {:ok, %{tenant: tenant, application: app}} =
      create_tenant_with_api_key(%{}, %{channels_enabled: true})

    %{tenant: tenant, application: app}
  end

  describe "event published telemetry" do
    test "emits telemetry on event publish", %{application: app} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:ricqchet, :channels, :event, :published]
        ])

      {:ok, _result} = EventPublisher.publish(app.id, "test-channel", "test-event", %{msg: "hi"})

      assert_received {[:ricqchet, :channels, :event, :published], ^ref, measurements, metadata}
      assert is_integer(measurements.data_size)
      assert measurements.data_size > 0
      assert metadata.application_id == app.id
      assert metadata.channel == "test-channel"
      assert metadata.event == "test-event"
    end
  end

  describe "event size check" do
    test "rejects events exceeding max size", %{application: app, tenant: tenant} do
      {:ok, _ns} =
        Namespaces.create_namespace(
          %{pattern: "limited-*", max_event_size_bytes: 10},
          app.id,
          tenant.id
        )

      large_data = %{payload: String.duplicate("x", 100)}

      assert {:error, :event_too_large} =
               EventPublisher.publish(app.id, "limited-channel", "test-event", large_data)
    end

    test "allows events within size limit", %{application: app, tenant: tenant} do
      {:ok, _ns} =
        Namespaces.create_namespace(
          %{pattern: "limited-*", max_event_size_bytes: 10_000},
          app.id,
          tenant.id
        )

      small_data = %{msg: "hi"}

      assert {:ok, _result} =
               EventPublisher.publish(app.id, "limited-channel", "test-event", small_data)
    end

    test "allows events when no size limit configured", %{application: app} do
      data = %{payload: String.duplicate("x", 1000)}

      assert {:ok, _result} =
               EventPublisher.publish(app.id, "no-limit-channel", "test-event", data)
    end
  end
end
