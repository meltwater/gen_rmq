defmodule GenRMQ.Consumer.Telemetry do
  @moduledoc """
  GenRMQ emits [Telemetry][telemetry] events for consumers. It currently exposes the following events:

  - `[:gen_rmq, :consumer, :message, :ack]` - Dispatched by a GenRMQ consumer when a message has been acknowledged

    - Measurement: `%{system_time: integer}`
    - Metadata: `%{message: String.t}`

  - `[:gen_rmq, :consumer, :message, :reject]` - Dispatched by a GenRMQ consumer when a message has been rejected

    - Measurement: `%{system_time: integer}`
    - Metadata: `%{message: String.t, requeue: boolean}`

  - `[:gen_rmq, :consumer, :message, :start]` - Dispatched by a GenRMQ consumer when the processing of a message has begun

    - Measurement: `%{system_time: integer}`
    - Metadata: `%{message: String.t, module: atom}`

  - `[:gen_rmq, :consumer, :message, :stop]` - Dispatched by a GenRMQ consumer when the processing of a message has completed

    - Measurement: `%{duration: native_time}`
    - Metadata: `%{message: String.t, module: atom}`

  - `[:gen_rmq, :consumer, :message, :error]` - Dispatched by a GenRMQ consumer when a message fails to be processed

    - Measurement: `%{duration: native_time}`
    - Metadata: `%{module: atom, reason: tuple, message: GenRMQ.Message.t}`

  - `[:gen_rmq, :consumer, :connection, :start]` - Dispatched by a GenRMQ consumer when a connection to RabbitMQ is started

    - Measurement: `%{system_time: integer}`
    - Metadata: `%{module: atom, attempt: integer, queue: String.t, exchange: String.t, routing_key: String.t}`

  - `[:gen_rmq, :consumer, :connection, :stop]` - Dispatched by a GenRMQ consumer when a connection to RabbitMQ has been established

    - Measurement: `%{duration: native_time}`
    - Metadata: `%{module: atom, attempt: integer, queue: String.t, exchange: String.t, routing_key: String.t}`

  - `[:gen_rmq, :consumer, :connection, :error]` - Dispatched by a GenRMQ consumer when a connection to RabbitMQ could not be made

    - Measurement: `%{system_time: integer}`
    - Metadata: `%{module: atom, attempt: integer, queue: String.t, exchange: String.t, routing_key: String.t, error: any}`

  - `[:gen_rmq, :consumer, :connection, :down]` - Dispatched by a GenRMQ consumer when a connection to RabbitMQ has been lost

    - Measurement: `%{system_time: integer}`
    - Metadata: `%{module: atom, reason: atom}`

  [telemetry]: https://github.com/beam-telemetry/telemetry
  """

  @doc false
  def emit_message_ack_event(message) do
    measurements = %{system_time: System.system_time()}
    metadata = %{message: message}

    :telemetry.execute([:gen_rmq, :consumer, :message, :ack], measurements, metadata)
  end

  @doc false
  def emit_message_reject_event(message, requeue) do
    measurements = %{system_time: System.system_time()}
    metadata = %{message: message, requeue: requeue}

    :telemetry.execute([:gen_rmq, :consumer, :message, :reject], measurements, metadata)
  end

  @doc false
  def emit_message_start_event(message, module) do
    measurements = %{system_time: System.system_time()}
    metadata = %{message: message, module: module}

    :telemetry.execute([:gen_rmq, :consumer, :message, :start], measurements, metadata)
  end

  @doc false
  def emit_message_stop_event(start_time, message, module) do
    stop_time = System.monotonic_time()
    measurements = %{duration: stop_time - start_time}
    metadata = %{message: message, module: module}

    :telemetry.execute([:gen_rmq, :consumer, :message, :stop], measurements, metadata)
  end

  @doc false
  def emit_message_error_event(module, reason, message, start_time) do
    stop_time = System.monotonic_time()
    measurements = %{duration: stop_time - start_time}
    metadata = %{module: module, reason: reason, message: message}

    :telemetry.execute([:gen_rmq, :consumer, :message, :error], measurements, metadata)
  end

  @doc false
  def emit_connection_down_event(module, reason) do
    measurements = %{system_time: System.system_time()}
    metadata = %{module: module, reason: reason}

    :telemetry.execute([:gen_rmq, :consumer, :connection, :down], measurements, metadata)
  end

  @doc false
  def emit_connection_start_event(module, attempt, queue, exchange, routing_key) do
    measurements = %{system_time: System.system_time()}

    metadata = %{
      module: module,
      attempt: attempt,
      queue: queue,
      exchange: exchange,
      routing_key: routing_key
    }

    :telemetry.execute([:gen_rmq, :consumer, :connection, :start], measurements, metadata)
  end

  @doc false
  def emit_connection_stop_event(start_time, module, attempt, queue, exchange, routing_key) do
    stop_time = System.monotonic_time()
    measurements = %{duration: stop_time - start_time}

    metadata = %{
      module: module,
      attempt: attempt,
      queue: queue,
      exchange: exchange,
      routing_key: routing_key
    }

    :telemetry.execute([:gen_rmq, :consumer, :connection, :stop], measurements, metadata)
  end

  @doc false
  def emit_connection_error_event(start_time, module, attempt, queue, exchange, routing_key, error) do
    stop_time = System.monotonic_time()
    measurements = %{duration: stop_time - start_time}

    metadata = %{
      module: module,
      attempt: attempt,
      queue: queue,
      exchange: exchange,
      routing_key: routing_key,
      error: error
    }

    :telemetry.execute([:gen_rmq, :consumer, :connection, :error], measurements, metadata)
  end
end
