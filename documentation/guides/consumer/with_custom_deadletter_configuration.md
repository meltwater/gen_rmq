Consumer with custom deadletter configuration
=============================================

Consumer with custom deadletter:

- queue name
- exchange name
- routing key
- queue arguments and type (transient instead of durable)

 `deadletter_queue_options` - Queue options for the deadletter queue as declared in
 [AMQP.Queue.declare/3](https://hexdocs.pm/amqp/AMQP.Queue.html#declare/3).

# Example

~~~elixir
defmodule ConsumerWithCustomDeadletterConfiguration do
  @behaviour GenRMQ.Consumer

  def init() do
    [
      connection: "amqp://guest:guest@localhost:5672",
      queue: "example_queue",
      exchange: "example_exchange",
      routing_key: "routing_key.#",
      prefetch_count: "10",
      deadletter_queue: "custom_deadletter_queue",
      deadletter_exchange: "custom_deadletter_exchange",
      deadletter_routing_key: "custom_deadletter_routing_key",
      deadletter_queue_options: [
        durable: false,
        arguments: [
          {"x-expires", :long, 3_600_000},
          {"x-max-priority", :long, 3}
        ]
      ]
    ]
  end

  def handle_message(%GenRMQ.Message{} = message), do: GenRMQ.Consumer.ack(message)

  def consumer_tag(), do: "consumer-tag"

  def start_link(), do: GenRMQ.Consumer.start_link(__MODULE__, name: __MODULE__)
end
~~~

# Outcome:

- durable `custom_deadletter_exchange` exchange created or redeclared
- transient, priority and with ttl `custom_deadletter_queue` queue created or redeclared and bound to `custom_deadletter_exchange` exchange
- durable topic `example_exchange` exchange created or redeclared
- durable `example_queue` queue created or redeclared and bound to `example_exchange` exchange
- queue `example_queue` has a deadletter exchange set to `custom_deadletter_exchange`
- every `handle_message` callback will be executed in a separate process
- on failed rabbitmq connection it will wait for a bit and then reconnect
