# Consumer Telemetry events

GenRMQ emits [Telemetry][telemetry] events for consumers. It currently exposes the following events:

- `[:gen_rmq, :consumer, :message, :ack]` - Dispatched by a GenRMQ consumer when a message has been acknowledged

  - Measurement: `%{time: System.monotonic_time}`
  - Metadata: `%{message: String.t}`

- `[:gen_rmq, :consumer, :message, :reject]` - Dispatched by a GenRMQ consumer when a message has been rejected

  - Measurement: `%{time: System.monotonic_time}`
  - Metadata: `%{message: String.t, requeue: boolean}`

- `[:gen_rmq, :consumer, :message, :start]` - Dispatched by a GenRMQ consumer when the processing of a message has begun

  - Measurement: `%{time: System.monotonic_time}`
  - Metadata: `%{message: String.t, module: atom}`

- `[:gen_rmq, :consumer, :message, :stop]` - Dispatched by a GenRMQ consumer when the processing of a message has completed

  - Measurement: `%{time: System.monotonic_time, duration: native_time}`
  - Metadata: `%{message: String.t, module: atom}`

- `[:gen_rmq, :consumer, :connection, :start]` - Dispatched by a GenRMQ consumer when a connection to RabbitMQ is started

  - Measurement: `%{time: System.monotonic_time}`
  - Metadata: `%{module: atom, attempt: integer, queue: String.t, exchange: String.t, routing_key: String.t}`

- `[:gen_rmq, :consumer, :connection, :stop]` - Dispatched by a GenRMQ consumer when a connection to RabbitMQ has been established

  - Measurement: `%{time: System.monotonic_time, duration: native_time}`
  - Metadata: `%{module: atom, attempt: integer, queue: String.t, exchange: String.t, routing_key: String.t}`

- `[:gen_rmq, :consumer, :connection, :error]` - Dispatched by a GenRMQ consumer when a connection to RabbitMQ could not be made

  - Measurement: `%{time: System.monotonic_time}`
  - Metadata: `%{module: atom, attempt: integer, queue: String.t, exchange: String.t, routing_key: String.t, error: any}`

- `[:gen_rmq, :consumer, :connection, :down]` - Dispatched by a GenRMQ consumer when a connection to RabbitMQ has been lost

  - Measurement: `%{time: System.monotonic_time}`
  - Metadata: `%{module: atom, reason: atom}`

- `[:gen_rmq, :consumer, :task, :error]` - Dispatched by a GenRMQ consumer when a supervised Task fails to process a message

  - Measurement: `%{time: System.monotonic_time}`
  - Metadata: `%{module: atom, reason: tuple}`

[telemetry]: https://github.com/beam-telemetry/telemetry
