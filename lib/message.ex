defmodule GenAMQP.Message do
  @moduledoc """
  Information about a RabbitMQ message
  """

  @enforce_keys [:attributes,
                 :payload,
                 :state]
  defstruct [:attributes,
             :payload,
             :state]

  def create(attributes, payload, state) do
    %__MODULE__{
      attributes: attributes,
      payload: payload,
      state: state
    }
  end
end
