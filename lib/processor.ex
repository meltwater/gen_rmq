defmodule GenRMQ.Processor do
  @moduledoc """
  Defines functions to implement by any AMQP processor
  """
  @callback process(message :: %GenRMQ.Message{}) :: :ok | {:error, term}
end
