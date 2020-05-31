defmodule GenRMQ.Publisher.Telemetry do
  @moduledoc """
  GenRMQ emits [Telemetry][telemetry] events for publishers. It currently exposes the following events:

  - `[:gen_rmq, :publisher, :connection, :start]` - Dispatched by a GenRMQ publisher when a connection to RabbitMQ is started

    - Measurement: `%{time: System.monotonic_time}`
    - Metadata: `%{exchange: String.t}`

  - `[:gen_rmq, :publisher, :connection, :stop]` - Dispatched by a GenRMQ publisher when a connection to RabbitMQ has been established

    - Measurement: `%{time: System.monotonic_time, duration: native_time}`
    - Metadata: `%{exchange: String.t}`

  - `[:gen_rmq, :publisher, :connection, :down]` - Dispatched by a GenRMQ publisher when a connection to RabbitMQ has been lost

    - Measurement: `%{time: System.monotonic_time}`
    - Metadata: `%{module: atom, reason: atom}`

  - `[:gen_rmq, :publisher, :message, :start]` - Dispatched by a GenRMQ publisher when a message is about to be published to RabbitMQ

    - Measurement: `%{time: System.monotonic_time}`
    - Metadata: `%{exchange: String.t, message: String.t}`

  - `[:gen_rmq, :publisher, :message, :stop]` - Dispatched by a GenRMQ publisher when a message has been published to RabbitMQ

    - Measurement: `%{time: System.monotonic_time, duration: native_time}`
    - Metadata: `%{exchange: String.t, message: String.t}`

  - `[:gen_rmq, :publisher, :message, :error]` - Dispatched by a GenRMQ publisher when a message failed to be published to RabbitMQ

    - Measurement: `%{time: System.monotonic_time, duration: native_time}`
    - Metadata: `%{exchange: String.t, message: String.t, kind: atom, reason: atom}`

  [telemetry]: https://github.com/beam-telemetry/telemetry
  """

  @doc false
  def emit_connection_down_event(module, reason) do
    start_time = System.monotonic_time()
    measurements = %{time: start_time}
    metadata = %{module: module, reason: reason}

    :telemetry.execute([:gen_rmq, :publisher, :connection, :down], measurements, metadata)
  end

  @doc false
  def emit_connection_start_event(start_time, exchange) do
    measurements = %{time: start_time}
    metadata = %{exchange: exchange}

    :telemetry.execute([:gen_rmq, :publisher, :connection, :start], measurements, metadata)
  end

  @doc false
  def emit_connection_stop_event(start_time, exchange) do
    stop_time = System.monotonic_time()
    measurements = %{time: stop_time, duration: stop_time - start_time}
    metadata = %{exchange: exchange}

    :telemetry.execute([:gen_rmq, :publisher, :connection, :stop], measurements, metadata)
  end

  @doc false
  def emit_publish_start_event(start_time, exchange, message) do
    measurements = %{time: start_time}
    metadata = %{exchange: exchange, message: message}

    :telemetry.execute([:gen_rmq, :publisher, :message, :start], measurements, metadata)
  end

  @doc false
  def emit_publish_stop_event(start_time, exchange, message) do
    stop_time = System.monotonic_time()
    measurements = %{time: stop_time, duration: stop_time - start_time}
    metadata = %{exchange: exchange, message: message}

    :telemetry.execute([:gen_rmq, :publisher, :message, :stop], measurements, metadata)
  end

  @doc false
  def emit_publish_error_event(start_time, exchange, message, kind, reason) do
    stop_time = System.monotonic_time()
    measurements = %{time: stop_time, duration: stop_time - start_time}
    metadata = %{exchange: exchange, message: message, kind: kind, reason: reason}

    :telemetry.execute([:gen_rmq, :publisher, :message, :error], measurements, metadata)
  end
end
