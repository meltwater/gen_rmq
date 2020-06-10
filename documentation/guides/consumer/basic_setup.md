Consumer basic setup
====================

# Example

~~~elixir
defmodule ConsumerBasicSetup do
  @behaviour GenRMQ.Consumer

  def init() do
    [
      connection: "amqp://guest:guest@localhost:5672",
      queue: "example_queue",
      exchange: "example_exchange",
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
- durable topic `example_exchange` exchange created or redeclared
- durable `example_queue` queue created or redeclared and bound to `example_exchange` exchange
- queue `example_queue` has a deadletter exchange set to `example_exchange.deadletter`
- every `handle_message` callback will be executed in a separate [supervised task](https://hexdocs.pm/elixir/1.10.3/Task.html#module-supervised-tasks). If the task fails `handle_error/2` will be called
- on failed rabbitmq connection it will wait for a bit and then reconnect
