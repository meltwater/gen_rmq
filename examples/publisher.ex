defmodule MyApp.ExamplePublisher do
  @moduledoc """
  Example GenAMQP.Publisher implementation
  """

  @behaviour GenAMQP.Publisher

  require Logger

  def start_link() do
    GenAMQP.Publisher.start_link(__MODULE__, name: __MODULE__)
  end

  def publish_message(message) do
    Logger.info("Publishing message #{inspect(message)}")
    GenAMQP.Publisher.publish(__MODULE__, message)
  end

  def init() do
    Application.get_env(:my_app, __MODULE__)
  end
end
