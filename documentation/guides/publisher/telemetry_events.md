# Publisher Telemetry events

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
