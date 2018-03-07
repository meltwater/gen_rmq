defmodule GenRMQ.ConsumerTest do
  use ExUnit.Case, async: false
  use GenRMQ.RabbitCase

  alias GenRMQ.Test.Assert

  alias TestConsumer.Default
  alias TestConsumer.WithoutConcurrency

  @uri "amqp://guest:guest@localhost:5672"
  @exchange "gen_rmq_exchange"
  @out_queue "gen_rmq_out_queue"

  setup_all do
    {:ok, conn} = rmq_open(@uri)
    :ok = setup_out_queue(conn, @out_queue, @exchange)
    {:ok, rabbit_conn: conn, out_queue: @out_queue, exchange: @exchange}
  end

  setup do
    purge_queues(@uri, [@out_queue])
  end

  describe "GenRMQ.Consumer" do
    test "should start new consumer" do
      {:ok, pid} = GenRMQ.Consumer.start_link(Default, name: Default)
      assert pid == Process.whereis(Default)
    end

    test "should return consumer config" do
      {:ok, config} = GenRMQ.Consumer.init(%{module: Default})

      assert Default.init() == config[:config]
    end

    test "should receive a message", context do
      message = %{"msg" => "some message"}

      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: Default)
      {:ok, _} = GenRMQ.Consumer.start_link(Default, name: :consumer)
      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(Default, fn set -> message in set end) == true
      end)
    end

    test "should receive a message and handle it in the same consumer process", context do
      message = %{"msg" => "handled in the same process"}

      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: WithoutConcurrency)
      {:ok, pid} = GenRMQ.Consumer.start_link(WithoutConcurrency, name: :consumer_no_concurrency)
      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(WithoutConcurrency, fn set -> {message, pid} in set end) == true
      end)
    end

    test "should reconnect after connection failure", context do
      message = %{"msg" => "disconnect"}

      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: Default)
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(Default, name: :consumer)

      state = :sys.get_state(consumer_pid)
      Process.exit(state.conn.pid, :kill)

      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(Default, fn set -> message in set end) == true
      end)
    end
  end
end
