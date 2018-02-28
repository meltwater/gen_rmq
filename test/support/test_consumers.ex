defmodule TestConsumer do
  defmodule Default do
    @moduledoc false
    @behaviour GenAMQP.Consumer

    def init() do
      [
        queue: "gen_amqp_in_queue",
        exchange: "gen_amqp_exchange",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672"
      ]
    end

    def consumer_tag() do
      "TestConsumer.Default"
    end

    def handle_message(message) do
      payload = Poison.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenAMQP.Consumer.ack(message)
    end
  end

  defmodule WithoutConcurrency do
    @moduledoc false
    @behaviour GenAMQP.Consumer

    def init() do
      [
        queue: "gen_amqp_in_queue",
        exchange: "gen_amqp_exchange",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672",
        concurrency: false
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithoutConcurrency"
    end

    def handle_message(message) do
      consuming_process = self()
      payload = Poison.decode!(message.payload)

      Agent.update(__MODULE__, &MapSet.put(&1, {payload, consuming_process}))
      GenAMQP.Consumer.ack(message)
    end
  end
end
