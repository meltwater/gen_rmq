defmodule GenRMQ.Processor do
  @moduledoc """
  Behaviour module for implementing a RabbitMQ message processor.

  A message processor is typically used to separate out business logic from a consumer,
  to let the consumer only deal with RabbitMQ specifics.
  """

  @callback process(message :: %GenRMQ.Message{}) :: :ok | {:error, term}
end
