defmodule GenRMQ.RabbitCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the rabbit mq.
  """

  defmacro __using__([]) do
    quote do
      use AMQP

      def rmq_open(uri) do
        AMQP.Connection.open(uri)
      end

      def publish_message(conn, exchange, message, routing_key \\ "#", meta \\ []) do
        {:ok, channel} = AMQP.Channel.open(conn)
        GenRMQ.Binding.declare_exchange(channel, exchange)
        AMQP.Basic.publish(channel, GenRMQ.Binding.exchange_name(exchange), routing_key, message, meta)
        AMQP.Channel.close(channel)
      end

      def setup_out_queue(conn, out_queue, out_exchange) do
        {:ok, chan} = AMQP.Channel.open(conn)
        AMQP.Queue.declare(chan, out_queue)
        AMQP.Exchange.topic(chan, out_exchange, durable: true)
        AMQP.Queue.bind(chan, out_queue, out_exchange, routing_key: "#")
        AMQP.Channel.close(chan)
      end

      def get_message_from_queue(context) do
        get_message_from_queue(context[:rabbit_conn], context[:out_queue])
      end

      def get_message_from_queue(conn, queue) do
        {:ok, chan} = AMQP.Channel.open(conn)
        {:ok, payload, meta} = AMQP.Basic.get(chan, queue)
        {:ok, Jason.decode!(payload), meta}
      end

      def purge_queues(uri, queues) do
        {:ok, conn} = rmq_open(uri)
        Enum.each(queues, &purge_queue(conn, &1))
        AMQP.Connection.close(conn)
      end

      def purge_queues!(uri, queues) do
        {:ok, conn} = rmq_open(uri)
        Enum.each(queues, &purge_queue!(conn, &1))
        AMQP.Connection.close(conn)
      end

      def purge_queue(conn, queue) do
        try do
          purge_queue!(conn, queue)
        catch
          :exit, _ ->
            :ok
        end
      end

      def purge_queue!(conn, queue) do
        {:ok, chan} = AMQP.Channel.open(conn)
        AMQP.Queue.purge(chan, queue)
        AMQP.Channel.close(chan)
      end

      def out_queue_count(context) do
        queue_count!(context[:rabbit_conn], context[:out_queue])
      end

      def dl_queue_count(context) do
        queue_count!(context[:rabbit_conn], context[:dl_queue])
      end

      def queue_count!(conn, queue) do
        {:ok, chan} = AMQP.Channel.open(conn)
        {:ok, %{message_count: count}} = AMQP.Queue.declare(chan, queue, passive: true)
        AMQP.Channel.close(chan)
        count
      end

      def queue_count(conn, queue) do
        try do
          {:ok, queue_count!(conn, queue)}
        catch
          :exit, _ ->
            {:error, :not_found}
        end
      end
    end
  end
end
