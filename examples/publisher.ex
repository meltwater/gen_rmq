defmodule MyApp.ExamplePublisher do
  @moduledoc """
  Example GenRMQ.Publisher implementation
  """

  @behaviour GenRMQ.Publisher

  require Logger

  def start_link() do
    GenRMQ.Publisher.start_link(__MODULE__, name: __MODULE__)
  end

  def publish_message(message) do
    Logger.info("Publishing message #{inspect(message)}")
    GenRMQ.Publisher.publish(__MODULE__, message)
  end

  def init() do
    Application.get_env(:my_app, __MODULE__)
  end
end
