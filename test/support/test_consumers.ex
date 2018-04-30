defmodule TestConsumer do
  defmodule Default do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue",
        exchange: "gen_rmq_in_exchange",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672",
        queue_ttl: 100
      ]
    end

    def consumer_tag() do
      "TestConsumer.Default"
    end

    def handle_message(message) do
      payload = Poison.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end
  end

  defmodule WithoutConcurrency do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue",
        exchange: "gen_rmq_in_exchange",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672",
        concurrency: false,
        queue_ttl: 100
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithoutConcurrency"
    end

    def handle_message(message) do
      consuming_process = self()
      payload = Poison.decode!(message.payload)

      Agent.update(__MODULE__, &MapSet.put(&1, {payload, consuming_process}))
      GenRMQ.Consumer.ack(message)
    end
  end

  defmodule WithoutReconnection do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "does_not_matter_queue",
        exchange: "does_not_matter_exchange",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672",
        reconnect: false,
        queue_ttl: 100
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithoutReconnection"
    end

    def handle_message(_message) do
    end
  end

  defmodule WithConnectionProvided do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue",
        exchange: "gen_rmq_in_exchange",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672",
        queue_ttl: 100
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithConnectionProvided"
    end

    def handle_message(message) do
      payload = Poison.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end
  end
end
