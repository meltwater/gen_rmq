defmodule GenRMQ.Message do
  @moduledoc """
  Struct wrapping details of the consumed message

  Defines:
  * `:attributes` - message attributes
  * `:payload` - message raw payload
  * `:channel` - the channel that the message came in from
  """

  @enforce_keys [:attributes, :payload, :channel]
  defstruct [:attributes, :payload, :channel]

  @doc false
  def create(attributes, payload, channel) do
    %__MODULE__{
      attributes: attributes,
      payload: payload,
      channel: channel
    }
  end
end

defimpl Inspect, for: GenRMQ.Message do
  import Inspect.Algebra

  def inspect(message_struct, opts) do
    inspect_fields =
      message_struct
      |> Map.delete(:channel)
      |> Map.delete(:__struct__)
      |> Map.to_list()

    concat(["#GenRMQ.Message<", to_doc(inspect_fields, opts), ">"])
  end
end
