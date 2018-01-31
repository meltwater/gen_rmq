defmodule GenAMQP.Processor do
  @moduledoc """
  Defines functions to implement by any AMQP processor
  """
  @callback process(GenAMQP.Message.t()) :: :ok | {:error, Any.t()}
end
