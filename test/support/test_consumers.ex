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
        queue_ttl: 1000
      ]
    end

    def consumer_tag() do
      "TestConsumer.Default"
    end

    def handle_message(%GenRMQ.Message{payload: "\"reject\""} = message) do
      GenRMQ.Consumer.reject(message)
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
        queue_ttl: 1000
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

  defmodule WithoutDeadletter do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue_no_deadletter",
        exchange: "gen_rmq_in_exchange_no_deadletter",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672",
        queue_ttl: 1000,
        deadletter: false
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithoutDeadletter"
    end

    def handle_message(message) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithCustomDeadletter do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue_custom_deadletter",
        exchange: "gen_rmq_in_exchange_custom_deadletter",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672",
        queue_ttl: 100,
        deadletter_queue: "dl_queue",
        deadletter_exchange: "dl_exchange"
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithCustomDeadletter"
    end

    def handle_message(message) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithPriority do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue_with_prio",
        exchange: "gen_rmq_in_exchange_with_prio",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672",
        queue_ttl: 100,
        queue_max_priority: 100
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithPriority"
    end

    def handle_message(message) do
      payload = Poison.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end
  end
end
