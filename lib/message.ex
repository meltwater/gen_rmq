defmodule GenRMQ.Message do
  @moduledoc """
  Struct wrapping details of the consumed message

  Defines:
  * `:attributes` - message attributes
  * `:payload` - message raw payload
  * `:state` - consumer state
  """

  @enforce_keys [:attributes, :payload, :state]
  defstruct [:attributes, :payload, :state]

  @doc false
  def create(attributes, payload, state) do
    %__MODULE__{
      attributes: attributes,
      payload: payload,
      state: state
    }
  end
end
