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
