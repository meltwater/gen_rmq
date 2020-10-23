defmodule GenRMQ.Consumer.QueueConfiguration do
  @moduledoc """
  Represents configuration of a Consumer queue.

  While this module exists to make management of Consumer queue configurations
  easier, right now it should be considered a private implementation detail
  with respect to the consumer configuration API.
  """

  @max_priority 255

  def setup(queue_name, config) do
    exchange = GenRMQ.Binding.exchange_name(config[:exchange])
    options = options(:queue_options, config)

    dead_letter = [
      create: Keyword.get(config, :deadletter, true),
      name: Keyword.get(config, :deadletter_queue, "#{queue_name}_error"),
      exchange: Keyword.get(config, :deadletter_exchange, "#{exchange}.deadletter"),
      routing_key: Keyword.get(config, :deadletter_routing_key, "#"),
      options: options(:deadletter_queue_options, config)
    ]

    return(queue_name, options, dead_letter)
  end

  defp options(queue_opts_word, config) do
    [
      durable: true
    ]
    |> Keyword.merge(Keyword.get(config, queue_opts_word, []))
  end

  defp return(name, options, dead_letter) do
    # dead_letter_options and options variables can contain
    # queue declare options as defined in
    # https://hexdocs.pm/amqp/AMQP.Queue.html#declare/3
    dead_letter_options =
      dead_letter[:options]
      |> build_arguments()

    dead_letter = Keyword.put(dead_letter, :options, dead_letter_options)

    options =
      options
      |> build_arguments(dead_letter)

    %{
      name: name,
      options: options,
      dead_letter: dead_letter
    }
  end

  defp build_arguments(options, dead_letter \\ []) do
    create_dead_letter = dead_letter[:create]

    options
    |> setup_ttl()
    |> setup_priority()
    |> setup_dead_letter_exchange(dead_letter, create_dead_letter)
    |> setup_dead_letter_routing_key(dead_letter, create_dead_letter)
  end

  defp setup_ttl(options) do
    case options[:ttl] do
      nil ->
        options

      value ->
        args = Keyword.get(options, :arguments, [])
        Keyword.put(options, :arguments, [{"x-expires", :long, value} | args])
    end
  end

  defp setup_priority(options) do
    case options[:max_priority] do
      nil ->
        options

      value ->
        value = set_max_priority_to_highest_value(value)
        args = Keyword.get(options, :arguments, [])
        Keyword.put(options, :arguments, [{"x-max-priority", :long, value} | args])
    end
  end

  defp setup_dead_letter_exchange(options, _dead_letter, nil), do: options
  defp setup_dead_letter_exchange(options, _dead_letter, false), do: options

  defp setup_dead_letter_exchange(options, dead_letter, true) do
    args = Keyword.get(options, :arguments, [])

    Keyword.put(
      options,
      :arguments,
      [{"x-dead-letter-exchange", :longstr, GenRMQ.Binding.exchange_name(dead_letter[:exchange])} | args]
    )
  end

  defp setup_dead_letter_routing_key(options, _dead_letter, nil), do: options
  defp setup_dead_letter_routing_key(options, _dead_letter, false), do: options

  defp setup_dead_letter_routing_key(options, dead_letter, true) do
    case dead_letter[:routing_key] != "#" do
      true ->
        args = Keyword.get(options, :arguments, [])

        Keyword.put(
          options,
          :arguments,
          [{"x-dead-letter-routing-key", :longstr, dead_letter[:routing_key]} | args]
        )

      false ->
        options
    end
  end

  defp set_max_priority_to_highest_value(mp)
       when is_integer(mp) and mp > @max_priority do
    255
  end

  defp set_max_priority_to_highest_value(mp) when is_integer(mp), do: mp
end
