defmodule GenRMQ.Binding do
  @moduledoc """
  This module defines common methods for
  declaring consumer bindings and exchanges.
  """

  @type exchange :: String.t() | {exchange_kind(), String.t()} | :default
  @type exchange_kind :: :topic | :direct | :fanout

  use AMQP

  @default_exchange ""

  @doc false
  def bind_exchange_and_queue(chan, exchange, queue, routing_key) do
    declare_exchange(chan, exchange)
    declare_binding(chan, queue, exchange, routing_key)
  end

  @doc false
  def declare_binding(chan, queue, {:fanout, exchange}, _) do
    bind_queue(chan, queue, exchange, "")
  end

  def declare_binding(chan, queue, {_, exchange}, routing_key) do
    bind_queue(chan, queue, exchange, routing_key)
  end

  def declare_binding(chan, queue, exchange, routing_key) do
    bind_queue(chan, queue, exchange, routing_key)
  end

  @doc false
  def declare_exchange(_chan, :default), do: :ok

  def declare_exchange(chan, {:direct, exchange}) do
    Exchange.direct(chan, exchange, durable: true)
  end

  def declare_exchange(chan, {:fanout, exchange}) do
    Exchange.fanout(chan, exchange, durable: true)
  end

  def declare_exchange(chan, {:topic, exchange}) do
    Exchange.topic(chan, exchange, durable: true)
  end

  def declare_exchange(chan, {:headers, exchange}) do
    Exchange.fanout(chan, exchange, durable: true)
  end

  def declare_exchange(chan, exchange) do
    Exchange.declare(chan, exchange, :headers, durable: true)
  end

  def exchange_name(:default) do
    @default_exchange
  end

  def exchange_name({_, exchange}) do
    exchange
  end

  @doc false
  def exchange_name(exchange) do
    exchange
  end

  defp bind_queue(chan, queue, exchange_name, routing_key) when is_list(routing_key) do
    Enum.reduce_while(routing_key, :ok, fn rk, acc ->
      case bind_queue(chan, queue, exchange_name, rk) do
        :ok -> {:cont, acc}
        err -> {:halt, err}
      end
    end)
  end

  defp bind_queue(_chan, _queue, :default, _routing_key), do: :ok

  defp bind_queue(chan, queue, exchange_name, routing_key) do
    Queue.bind(chan, queue, exchange_name, routing_key: routing_key)
  end
end
