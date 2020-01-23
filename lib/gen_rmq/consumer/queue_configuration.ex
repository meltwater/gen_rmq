defmodule GenRMQ.Consumer.QueueConfiguration do
  @moduledoc """
  Represents configuration of a Consumer queue.

  While this module exists to make management of Consumer queue configurations
  easier, right now it should be considered a private implementation detail
  with respect to the consumer configuration API.
  """

  defstruct name: nil,
            ttl: nil,
            max_priority: nil,
            durable: true

  @type t :: %__MODULE__{
          name: String.t(),
          ttl: nil | pos_integer,
          max_priority: nil | pos_integer,
          durable: boolean
        }

  @type queue_options ::
          []
          | [durable: boolean]
          | [durable: boolean, max_priority: pos_integer]
          | [durable: boolean, ttl: pos_integer]
          | [max_priority: pos_integer]
          | [max_priority: pos_integer, ttl: pos_integer]
          | [durable: boolean, max_priority: pos_integer, ttl: pos_integer]

  @spec new(String.t(), queue_options) :: t
  def new(name, args \\ []) do
    queue_ttl = Keyword.get(args, :ttl, nil)
    queue_mp = Keyword.get(args, :max_priority, nil)
    durable = Keyword.get(args, :durable, true)

    %__MODULE__{
      name: name,
      ttl: queue_ttl,
      max_priority: set_max_priority_to_highest_value(queue_mp),
      durable: durable
    }
  end

  @spec new(String.t(), boolean, nil | pos_integer, nil | pos_integer) :: t
  def new(name, durable, ttl, mp) do
    %__MODULE__{
      name: name,
      ttl: ttl,
      max_priority: set_max_priority_to_highest_value(mp),
      durable: durable
    }
  end

  @spec name(t) :: String.t()
  def name(%__MODULE__{name: n}), do: n

  @spec durable(t) :: boolean
  def durable(%__MODULE__{durable: d}), do: d

  @spec ttl(t) :: nil | pos_integer
  def ttl(%__MODULE__{ttl: ttl_v}), do: ttl_v

  @spec max_priority(t) :: nil | pos_integer
  def max_priority(%__MODULE__{max_priority: mp}), do: mp

  def build_queue_arguments(%__MODULE__{} = qc, arguments) do
    args_with_priority = setup_priority(arguments, qc.max_priority)

    qc
    |> build_ttl_arguments(args_with_priority)
  end

  def build_ttl_arguments(%__MODULE__{} = qc, arguments) do
    setup_ttl(arguments, qc.ttl)
  end

  defp setup_ttl(arguments, nil), do: arguments
  defp setup_ttl(arguments, ttl), do: [{"x-expires", :long, ttl} | arguments]

  defp setup_priority(arguments, max_priority) when is_integer(max_priority),
    do: [{"x-max-priority", :long, max_priority} | arguments]

  defp setup_priority(arguments, _), do: arguments

  @max_priority 255

  defp set_max_priority_to_highest_value(nil), do: nil

  defp set_max_priority_to_highest_value(mp)
       when is_integer(mp) and mp > @max_priority do
    255
  end

  defp set_max_priority_to_highest_value(mp) when is_integer(mp), do: mp
end
