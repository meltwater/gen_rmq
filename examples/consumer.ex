defmodule MyApp.ExampleConsumer do
  @moduledoc """
  Example GenRMQ.Consumer implementation
  """
  @behaviour GenRMQ.Consumer

  require Logger

  alias Mix.Project
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
    Application.get_env(:my_app, __MODULE__)
  end

  def handle_message(%Message{} = message) do
    # Implement your logic here.
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, System.stacktrace()))
      reject(message, false)
  end

  def consumer_tag() do
    {:ok, hostname} = :inet.gethostname()
    app = Project.config() |> Keyword.get(:app)
    version = Project.config() |> Keyword.get(:version)
    "#{hostname}-#{app}-#{version}-consumer"
  end
end
