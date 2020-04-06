Consumer with quorum queues
===========================

You can change from `classic` to a `quorum` queue type by specyfing corresponding
queue arguments. Read more about quorum queues [here](https://www.rabbitmq.com/quorum-queues.html).

# Example

~~~elixir
defmodule WithQuorumQueueType do
  @behaviour GenRMQ.Consumer

  def init() do
    [
      connection: "amqp://guest:guest@localhost:5672",
      queue: "example_queue",
      exchange: "example_exchange",
      routing_key: "routing_key.#",
      prefetch_count: "10",
      queue_options: [
        arguments: [
           {"x-queue-type", :longstr, "quorum"}
        ]
      ],
      deadletter_queue_options: [
        arguments: [
           {"x-queue-type", :longstr, "quorum"}
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

- durable `example_exchange.deadletter` exchange created or redeclared
- durable `example_queue_error` **quorum** queue created or redeclared and bound to `example_exchange.deadletter` exchange
- durable topic `example_exchange` exchange created or redeclared
- durable `example_queue` **quorum** queue created or redeclared and bound to `example_exchange` exchange
- queue `example_queue` has a deadletter exchange set to `example_exchange.deadletter`
- every `handle_message` callback will be executed in a separate process
- on failed rabbitmq connection it will wait for a bit and then reconnect
