defmodule ExampleConsumerOptions do
  @moduledoc """
  Example GenRMQ.Consumer implementation.

  Sample usage:
  ```
  MIX_ENV=test iex -S mix
  iex(1)> ExampleConsumerOptions.start_link()
  ```
  """
  @behaviour GenRMQ.Consumer

  require Logger

  alias GenRMQ.Message

  ##############################################################################
  # Consumer API
  ##############################################################################

  def start_link() do
    GenRMQ.Consumer.start_link(__MODULE__, name: __MODULE__)
  end

  def ack(%Message{attributes: %{delivery_tag: tag}} = message) do
    Logger.debug("Message successfully processed. Tag: #{tag}")
    GenRMQ.Consumer.ack(message)
  end

  def reject(%Message{attributes: %{delivery_tag: tag}} = message, requeue \\ true) do
    Logger.info("Rejecting message, tag: #{tag}, requeue: #{requeue}")
    GenRMQ.Consumer.reject(message, requeue)
  end

  ##############################################################################
  # GenRMQ.Consumer callbacks
  ##############################################################################

  def init() do
    [
      queue: "example_queue",
      queue_options: [
        durable: true,
        arguments: [
          {"x-queue-type", :longstr ,"quorum"},
        ]
      ],
      exchange: "example_exchange",
      routing_key: "routing_key.#",
      prefetch_count: "10",
      uri: "amqp://guest:guest@localhost:5672",
      deadletter_queue_options: [
        durable: true,
        arguments: [
          {"x-queue-type", :longstr ,"quorum"},
        ]
      ],
      deadletter_exchange: "deadletter_exchange",
      deadletter_routing_key: "rk",
    ]
  end

  def handle_message(%Message{} = message) do
    Logger.info("Received message: #{inspect(message)}")
    ack(message)
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, System.stacktrace()))
      reject(message, false)
  end

  def consumer_tag() do
    {:ok, hostname} = :inet.gethostname()
    "#{hostname}-example-consumer"
  end
end
