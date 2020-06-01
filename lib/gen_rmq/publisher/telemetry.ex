defmodule GenRMQ.Publisher.Telemetry do
  @moduledoc """
  GenRMQ emits [Telemetry][telemetry] events for publishers. It exposes several events for RabbitMQ connections, and message
  publishing.

  ### Connection events

  - `[:gen_rmq, :publisher, :connection, :start]` - Dispatched by a GenRMQ publisher when a connection to RabbitMQ is started. The
     `system_time` value is generated via `System.system_time()`.

    - Measurement: `%{system_time: integer}`
    - Metadata: `%{exchange: String.t}`

  - `[:gen_rmq, :publisher, :connection, :stop]` - Dispatched by a GenRMQ publisher when a connection to RabbitMQ has been established.

    - Measurement: `%{duration: native_time}`
    - Metadata: `%{exchange: String.t}`

  - `[:gen_rmq, :publisher, :connection, :down]` - Dispatched by a GenRMQ publisher when a connection to RabbitMQ has been lost. The
     `system_time` value is generated via `System.system_time()`.

    - Measurement: `%{system_time: integer}`
    - Metadata: `%{module: atom, reason: atom}`

  ### Message events

  - `[:gen_rmq, :publisher, :message, :start]` - Dispatched by a GenRMQ publisher when a message is about to be published to RabbitMQ. The
     `system_time` value is generated via `System.system_time()`.

    - Measurement: `%{system_time: integer}`
    - Metadata: `%{exchange: String.t, message: String.t}`

  - `[:gen_rmq, :publisher, :message, :stop]` - Dispatched by a GenRMQ publisher when a message has been published to RabbitMQ.

    - Measurement: `%{duration: native_time}`
    - Metadata: `%{exchange: String.t, message: String.t}`

  - `[:gen_rmq, :publisher, :message, :error]` - Dispatched by a GenRMQ publisher when a message failed to be published to RabbitMQ.

    - Measurement: `%{duration: native_time}`
    - Metadata: `%{exchange: String.t, message: String.t, kind: atom, reason: atom}`

  [telemetry]: https://github.com/beam-telemetry/telemetry
  """

  @doc false
  def emit_connection_down_event(module, reason) do
    measurements = %{system_time: System.system_time()}
    metadata = %{module: module, reason: reason}

    :telemetry.execute([:gen_rmq, :publisher, :connection, :down], measurements, metadata)
  end

  @doc false
  def emit_connection_start_event(exchange) do
    measurements = %{system_time: System.system_time()}
    metadata = %{exchange: exchange}

    :telemetry.execute([:gen_rmq, :publisher, :connection, :start], measurements, metadata)
  end

  @doc false
  def emit_connection_stop_event(start_time, exchange) do
    stop_time = System.monotonic_time()
    measurements = %{duration: stop_time - start_time}
    metadata = %{exchange: exchange}

    :telemetry.execute([:gen_rmq, :publisher, :connection, :stop], measurements, metadata)
  end

  @doc false
  def emit_publish_start_event(exchange, message) do
    measurements = %{system_time: System.system_time()}
    metadata = %{exchange: exchange, message: message}

    :telemetry.execute([:gen_rmq, :publisher, :message, :start], measurements, metadata)
  end

  @doc false
  def emit_publish_stop_event(start_time, exchange, message) do
    stop_time = System.monotonic_time()
    measurements = %{duration: stop_time - start_time}
    metadata = %{exchange: exchange, message: message}

    :telemetry.execute([:gen_rmq, :publisher, :message, :stop], measurements, metadata)
  end

  @doc false
  def emit_publish_error_event(start_time, exchange, message, kind, reason) do
    stop_time = System.monotonic_time()
    measurements = %{duration: stop_time - start_time}
    metadata = %{exchange: exchange, message: message, kind: kind, reason: reason}

    :telemetry.execute([:gen_rmq, :publisher, :message, :error], measurements, metadata)
  end
end
