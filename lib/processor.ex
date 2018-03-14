defmodule GenRMQ.Processor do
  @moduledoc """
  Defines functions to implement by any AMQP processor
  """
  @callback process(message :: GenRMQ.Message.t()) :: :ok | {:error, Any.t()}
end
