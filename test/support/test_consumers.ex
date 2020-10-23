defmodule TestConsumer do
  def common_config() do
    [
      queue: "gen_rmq_in_queue",
      exchange: "gen_rmq_in_exchange",
      routing_key: "#",
      prefetch_count: "10",
      connection: "amqp://guest:guest@localhost:5672",
      queue_options: [
        arguments: [
          {"x-expires", :long, 1_000}
        ]
      ],
      deadletter_queue_options: [
        arguments: [
          {"x-expires", :long, 1_000}
        ]
      ]
    ]
  end

  def config(config), do: Keyword.merge(common_config(), config)

  defmodule Default do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [] |> TestConsumer.config()
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

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithoutConcurrency do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue_no_concurrency",
        exchange: "gen_rmq_in_exchange_no_concurrency",
        concurrency: false
      ] |> TestConsumer.config()
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

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule ErrorWithoutConcurrency do
    use Agent

    @moduledoc false
    @behaviour GenRMQ.Consumer

    def start_link(test_pid) do
      Agent.start_link(fn -> test_pid end, name: __MODULE__)
    end

    def init() do
      [
        queue: "error_no_concurrency_queue",
        exchange: "error_no_concurrency_exchange",
        concurrency: false
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.ErrorWithoutConcurrency"
    end

    def handle_message(message) do
      %{"value" => value} = Jason.decode!(message.payload)

      if value == 0, do: raise("Can't divide by zero!")

      result = Float.to_string(1 / value)
      updated_message = Map.put(message, :payload, result)

      GenRMQ.Consumer.ack(updated_message)
    end

    def handle_error(message, reason) do
      __MODULE__
      |> Agent.get(& &1)
      |> send({:synchronous_error, reason})

      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithoutReconnection do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "does_not_matter_queue",
        exchange: "does_not_matter_exchange",
        reconnect: false
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.WithoutReconnection"
    end

    def handle_message(_message) do
    end

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithoutDeadletter do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue_no_deadletter",
        exchange: "gen_rmq_in_exchange_no_deadletter",
        deadletter: false
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.WithoutDeadletter"
    end

    def handle_message(message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_error(message, _reason) do
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
            {"x-expires", :long, 1_000}
          ]
        ],
        exchange: "gen_rmq_in_exchange_queue_options",
        deadletter_queue: "dl_queue_options",
        deadletter_queue_options: [
          durable: false,
          arguments: [
            {"x-expires", :long, 1_000}
          ]
        ],
        deadletter_exchange: "dl_exchange_options",
        deadletter_routing_key: "dl_routing_key_options"
      ] |> TestConsumer.config()
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

    def handle_error(message, _reason) do
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
        deadletter_queue: "dl_queue",
        deadletter_exchange: "dl_exchange",
        deadletter_routing_key: "dl_routing_key"
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.WithCustomDeadletter"
    end

    def handle_message(message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithCustomDeadletterExchangeType do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue_custom_fanout_deadletter",
        exchange: "gen_rmq_in_exchange_custom_deadletter",
        deadletter_queue: "dl_queue",
        deadletter_exchange: {:fanout, "dl_fanout_exchange"},
        deadletter_routing_key: "dl_routing_key"
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.WithCustomDeadletterExchangeType"
    end

    def handle_message(message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_error(message, _reason) do
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
        queue_options: [
          arguments: [
            {"x-expires", :long, 1_000},
            {"x-max-priority", :long, 100}
          ]
        ]
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.WithPriority"
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithTopicExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_wt_in_queue",
        exchange: {:topic, "gen_rmq_in_wt_exchange"}
      ] |> TestConsumer.config()
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

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithDirectExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_wd_in_queue",
        exchange: {:direct, "gen_rmq_in_wd_exchange"}
      ] |> TestConsumer.config()
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

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithFanoutExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_wf_in_queue",
        exchange: {:fanout, "gen_rmq_in_wf_exchange"}
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.WithFanoutExchange"
    end

    def handle_message(%GenRMQ.Message{payload: "\"reject\""} = message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithMultiBindingExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_mb_in_queue",
        exchange: {:direct, "gen_rmq_in_mb_exchange"},
        routing_key: ["routing_key_1", "routing_key_2"]
      ] |> TestConsumer.config()
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

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithDefaultExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_with_default_exchange",
        exchange: :default
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.WithDefaultExchange"
    end

    def handle_message(%GenRMQ.Message{payload: "\"reject\""} = message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule RedeclaringExistingExchange do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def existing_exchange, do: "existing_direct_exchange"

    def init() do
      [
        queue: "gen_rmq_in_queue_" <> existing_exchange(),
        exchange: existing_exchange()
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.RedeclaringExistingExchange"
    end

    def handle_message(_), do: :ok

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule WithQueueOptionsWithoutArguments do
    @moduledoc false
    @behaviour GenRMQ.Consumer

    def init() do
      [
        queue: "gen_rmq_in_queue_options_no_args",
        queue_options: [durable: true],
        exchange: {:topic, "gen_rmq_in_exchange_queue_options_no_args"},
        deadletter: false
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.WithQueueOptionsWithoutArguments"
    end

    def handle_message(%GenRMQ.Message{payload: "\"reject\""} = message) do
      GenRMQ.Consumer.reject(message)
    end

    def handle_message(message) do
      payload = Jason.decode!(message.payload)
      Agent.update(__MODULE__, &MapSet.put(&1, payload))
      GenRMQ.Consumer.ack(message)
    end

    def handle_error(message, _reason) do
      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule ErrorInConsumer do
    use Agent

    @moduledoc false
    @behaviour GenRMQ.Consumer

    def start_link(test_pid) do
      Agent.start_link(fn -> test_pid end, name: __MODULE__)
    end

    def init() do
      [
        queue: "gen_rmq_error_in_consume_queue",
        exchange: "gen_rmq_error_in_consume_exchange"
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.ErrorInConsumer"
    end

    def handle_message(message) do
      %{"value" => value} = Jason.decode!(message.payload)

      if value == 0, do: raise("Can't divide by zero!")

      result = Float.to_string(1 / value)
      updated_message = Map.put(message, :payload, result)

      GenRMQ.Consumer.ack(updated_message)
    end

    def handle_error(message, reason) do
      __MODULE__
      |> Agent.get(& &1)
      |> send({:task_error, reason})

      GenRMQ.Consumer.reject(message)
    end
  end

  defmodule SlowConsumer do
    use Agent

    @moduledoc false
    @behaviour GenRMQ.Consumer
    def start_link(test_pid) do
      Agent.start_link(fn -> test_pid end, name: __MODULE__)
    end

    def init() do
      [
        queue: "slow_consumer_queue",
        exchange: "slow_consumer_exchange",
        handle_message_timeout: 500
      ] |> TestConsumer.config()
    end

    def consumer_tag() do
      "TestConsumer.SlowConsumer"
    end

    def handle_message(message) do
      %{"value" => value} = Jason.decode!(message.payload)

      result = Float.to_string(1 / value)
      updated_message = Map.put(message, :payload, result)

      Process.sleep(value)

      GenRMQ.Consumer.ack(updated_message)
    end

    def handle_error(message, reason) do
      __MODULE__
      |> Agent.get(& &1)
      |> send({:task_error, reason})

      GenRMQ.Consumer.reject(message)
    end
  end
end
