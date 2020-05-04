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
        connection: "amqp://guest:guest@localhost:5672",
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
      payload = Jason.decode!(message.payload)
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
        connection: "amqp://guest:guest@localhost:5672",
        concurrency: false,
        queue_ttl: 1000
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithoutConcurrency"
    end

    def handle_message(message) do
      consuming_process = self()
      payload = Jason.decode!(message.payload)

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
        connection: "amqp://guest:guest@localhost:5672",
        reconnect: false,
        queue_ttl: 1000
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
        connection: "amqp://guest:guest@localhost:5672",
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

  defmodule WithQueueOptions do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue_options",
        queue_options: [
          durable: false,
          arguments: [
            {"x-expires", :long, 1000}
          ]
        ],
        exchange: "gen_rmq_in_exchange_queue_options",
        routing_key: "#",
        prefetch_count: "10",
        connection: "amqp://guest:guest@localhost:5672",
        deadletter_queue: "dl_queue_options",
        deadletter_queue_options: [
          durable: false,
          arguments: [
            {"x-expires", :long, 1000}
          ]
        ],
        deadletter_exchange: "dl_exchange_options",
        deadletter_routing_key: "dl_routing_key_options"
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithQueueOptions"
    end

    def handle_message(%GenRMQ.Message{payload: "\"reject\""} = message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
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
        connection: "amqp://guest:guest@localhost:5672",
        queue_ttl: 1000,
        deadletter_queue: "dl_queue",
        deadletter_exchange: "dl_exchange",
        deadletter_routing_key: "dl_routing_key"
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
        connection: "amqp://guest:guest@localhost:5672",
        queue_ttl: 1000,
        queue_max_priority: 100
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithPriority"
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end
  end

  defmodule WithTopicExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_wt_in_queue",
        exchange: {:topic, "gen_rmq_in_wt_exchange"},
        routing_key: "#",
        prefetch_count: "10",
        connection: "amqp://guest:guest@localhost:5672",
        queue_ttl: 1000
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithTopicExchange"
    end

    def handle_message(%GenRMQ.Message{payload: "\"reject\""} = message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end
  end

  defmodule WithDirectExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_wd_in_queue",
        exchange: {:direct, "gen_rmq_in_wd_exchange"},
        routing_key: "#",
        prefetch_count: "10",
        connection: "amqp://guest:guest@localhost:5672",
        queue_ttl: 1000
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithDirectExchange"
    end

    def handle_message(%GenRMQ.Message{payload: "\"reject\""} = message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end
  end

  defmodule WithFanoutExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_wf_in_queue",
        exchange: {:fanout, "gen_rmq_in_wf_exchange"},
        routing_key: "#",
        prefetch_count: "10",
        connection: "amqp://guest:guest@localhost:5672",
        queue_ttl: 1000
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithDirectExchange"
    end

    def handle_message(%GenRMQ.Message{payload: "\"reject\""} = message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end
  end

  defmodule WithMultiBindingExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_mb_in_queue",
        exchange: {:direct, "gen_rmq_in_mb_exchange"},
        routing_key: ["routing_key_1", "routing_key_2"],
        prefetch_count: "10",
        connection: "amqp://guest:guest@localhost:5672",
        queue_ttl: 1000
      ]
    end

    def consumer_tag() do
      "TestConsumer.WithMultiBindingExchange"
    end

    def handle_message(%GenRMQ.Message{payload: "\"reject\""} = message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end
  end

  defmodule RedeclaringExistingExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def existing_exchange, do: "existing_direct_exchange"

    def init() do
      [
        queue: "gen_rmq_in_queue_" <> existing_exchange(),
        exchange: existing_exchange(),
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672",
        queue_ttl: 1000
      ]
    end

    def consumer_tag() do
      "TestConsumer.RedeclaringExistingExchange"
    end

    def handle_message(_), do: :ok
  end

  defmodule ErrorInConsumer do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue",
        exchange: "gen_rmq_in_exchange",
        routing_key: "#",
        prefetch_count: "10",
        connection: "amqp://guest:guest@localhost:5672",
        queue_ttl: 1000
      ]
    end

    def consumer_tag() do
      "TestConsumer.ErrorInConsumer"
    end

    def handle_message(message) do
      %{"value" => value} = Jason.decode!(message.payload)

      result = Float.to_string(1 / value)
      updated_message = Map.put(message, :payload, result)

      GenRMQ.Consumer.ack(updated_message)
    end
  end
end
