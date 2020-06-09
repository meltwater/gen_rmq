Consumer with custom exchange type
==================================

By default consumer creates `topic` exchanges. This can be modified by
specyfying exchange type: `exchange: {:fanout, "custom_exchange"}`.

# Example

~~~elixir
defmodule WithCustomExchangeType do
  @behaviour GenRMQ.Consumer

  def init() do
    [
      connection: "amqp://guest:guest@localhost:5672",
      queue: "example_queue",
      exchange: {:fanout, "custom_exchange"},
      routing_key: "routing_key.#",
      prefetch_count: "10"
    ]
  end

  def handle_message(%GenRMQ.Message{} = message), do: GenRMQ.Consumer.ack(message)

  def handle_error(%GenRMQ.Message{} = message, _reason), do: GenRMQ.Consumer.reject(message, false)

  def consumer_tag(), do: "consumer-tag"

  def start_link(), do: GenRMQ.Consumer.start_link(__MODULE__, name: __MODULE__)
end
~~~

# Outcome:

- durable `example_exchange.deadletter` exchange created or redeclared
- durable `example_queue_error` queue created or redeclared and bound to `example_exchange.deadletter` exchange
- durable fanout `custom_exchange` exchange created or redeclared
- durable `example_queue` queue created or redeclared and bound to `custom_exchange` exchange
- queue `example_queue` has a deadletter exchange set to `example_exchange.deadletter`
- every `handle_message` callback will be executed in a separate process (supervised task)
- on failed rabbitmq connection it will wait for a bit and then reconnect