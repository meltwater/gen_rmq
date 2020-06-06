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
      durable: Keyword.get(config, :queue_durable, true),
      max_priority: Keyword.get(config, :queue_max_priority, nil),
      ttl: Keyword.get(config, :queue_ttl, nil)
    ]
    |> combine_options(Keyword.get(config, queue_opts_word, []))
  end

  defp combine_options(word_list, []) do
    word_list
  end

  defp combine_options(word_list, option_list) do
    # Combine two keyword lists together.
    #
    # Since queue_options and dead_letter_queue_options
    # keywords on init can contain queue ttl and max
    # priority as arguments, and these options will
    # be used instead of queue_ttl and queue_max_priority
    # keywords, we must check if these arguments
    # are present.
    #
    # If option_list's arguments has "x-expires" and
    # word_list has "ttl", then remove "ttl"
    #
    # If option_list's arguments has "x-max-priority" and
    # word_list has "max_priority", then remove "max_priority"
    #
    # This is done in order to be backwards compatible.
    # If one day those two keywords are removed from the
    # init, then this function can be removed as well.
    queue_option_arguments = Keyword.get(option_list, :arguments, [])

    word_list
    |> remove_keyword(queue_option_arguments, %{name: "x-expires", word: :ttl})
    |> remove_keyword(queue_option_arguments, %{name: "x-max-priority", word: :max_priority})
    |> Keyword.merge(option_list)
  end

  defp remove_keyword(word_list, [], _argument), do: word_list

  defp remove_keyword(word_list, option_arguments, argument) do
    case Enum.find(option_arguments, fn arg -> elem(arg, 0) == argument.name end) do
      nil -> word_list
      _ -> Keyword.delete(word_list, argument.word)
    end
  end

  defp return(name, options, dead_letter) do
    # dead_letter_options and options variables can contain
    # queue declare options as defined in
    # https://hexdocs.pm/amqp/AMQP.Queue.html#declare/3
    dead_letter_options =
      dead_letter[:options]
      |> build_arguments()
      |> Keyword.delete(:ttl)
      |> Keyword.delete(:max_priority)

    dead_letter = Keyword.put(dead_letter, :options, dead_letter_options)

    options =
      options
      |> build_arguments(dead_letter)
      |> Keyword.delete(:ttl)
      |> Keyword.delete(:max_priority)

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
