defmodule GenRMQ.ConsumerTest do
  use ExUnit.Case, async: false
  use GenRMQ.RabbitCase

  alias GenRMQ.Test.Assert

  alias TestConsumer.Default
  alias TestConsumer.WithoutConcurrency
  alias TestConsumer.WithoutReconnection

  @uri "amqp://guest:guest@localhost:5672"
  @exchange "gen_rmq_in_exchange"

  setup_all do
    {:ok, conn} = rmq_open(@uri)
    {:ok, rabbit_conn: conn, exchange: @exchange}
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
      AMQP.Connection.close(state.conn)

      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(Default, fn set -> message in set end) == true
      end)
    end

    test "should terminate after connection failure when reconnection disabled" do
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(WithoutReconnection, name: :consumer_no_reconnection)

      state = :sys.get_state(consumer_pid)
      AMQP.Connection.close(state.conn)

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == false
        assert Process.whereis(WithoutReconnection) == nil
      end)
    end

    test "should terminate after queue deletion" do
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(Default, name: :consumer)

      state = :sys.get_state(consumer_pid)
      AMQP.Queue.delete(state.out, state[:config][:queue])

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == false
        assert Process.whereis(Default) == nil
      end)
    end
  end
end
