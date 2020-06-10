defmodule ExampleConsumer do
  @moduledoc """
  Example GenRMQ.Consumer implementation.

  Sample usage:
  ```
  MIX_ENV=test iex -S mix
  iex(1)> ExampleConsumer.start_link()
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

  @impl GenRMQ.Consumer
  def init() do
    [
      queue: "example_queue",
      exchange: "example_exchange",
      routing_key: "routing_key.#",
      prefetch_count: "10",
      connection: "amqp://guest:guest@localhost:5672"
    ]
  end

  @impl GenRMQ.Consumer
  def handle_message(%Message{} = message) do
    Logger.info("Received message: #{inspect(message)}")
    ack(message)
  end

  @impl GenRMQ.Consumer
  def handle_error(%Message{attributes: attributes, payload: payload} = message, reason) do
    Logger.error("Rejecting message due to consumer task error: #{inspect([reason: reason, msg_attributes: attributes, msg_payload: payload])}")
    GenRMQ.Consumer.reject(message, false)
  end

  @impl GenRMQ.Consumer
  def consumer_tag() do
    {:ok, hostname} = :inet.gethostname()
    "#{hostname}-example-consumer"
  end
end
