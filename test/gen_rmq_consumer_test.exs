defmodule GenRMQ.ConsumerTest do
  use ExUnit.Case, async: false
  use GenRMQ.RabbitCase

  alias GenRMQ.Test.Assert

  alias TestConsumer.Default
  alias TestConsumer.WithoutConcurrency
  alias TestConsumer.WithoutReconnection
  alias TestConsumer.WithoutDeadletter
  alias TestConsumer.WithoutCustomDeadletter

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

    test "should close connection after being stopped" do
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(Default, name: Default)
      state = :sys.get_state(consumer_pid)

      GenRMQ.Consumer.stop(Default, :normal)

      Assert.repeatedly(fn ->
        assert Process.alive?(state.conn.pid) == false
      end)
    end

    test "should return consumer config" do
      {:ok, config} = GenRMQ.Consumer.init(%{module: Default})
      assert Default.init() == config[:config]
    end

    test "should receive a message", context do
      message = %{"msg" => "some message"}
      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: Default)
      {:ok, _} = GenRMQ.Consumer.start_link(Default)

      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(Default, fn set -> message in set end) == true
      end)
    end

    test "should reject a message", context do
      message = "reject"
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(Default)
      state = :sys.get_state(consumer_pid)

      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert queue_count(context[:rabbit_conn], "#{state.config[:queue]}_error") == {:ok, 1}
      end)
    end

    test "should reconnect after connection failure", context do
      message = %{"msg" => "disconnect"}
      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: Default)
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(Default)
      state = :sys.get_state(consumer_pid)

      AMQP.Connection.close(state.conn)
      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(Default, fn set -> message in set end) == true
      end)
    end

    test "should terminate after queue deletion" do
      Process.flag(:trap_exit, true)
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(Default)
      state = :sys.get_state(consumer_pid)

      AMQP.Queue.delete(state.out, state[:config][:queue])

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == false
      end)
    end

    test "should send exit signal after queue deletion" do
      Process.flag(:trap_exit, true)
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(Default)
      state = :sys.get_state(consumer_pid)

      AMQP.Queue.delete(state.out, state[:config][:queue])

      assert_receive({:EXIT, ^consumer_pid, :cancelled})
    end

    test "should close connection and channels after queue deletion" do
      Process.flag(:trap_exit, true)
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(Default)
      state = :sys.get_state(consumer_pid)

      AMQP.Queue.delete(state.out, state[:config][:queue])

      Assert.repeatedly(fn ->
        assert Process.alive?(state.conn.pid) == false
        assert Process.alive?(state.in.pid) == false
        assert Process.alive?(state.out.pid) == false
      end)
    end
  end

  describe "GenRMQ.Consumer with concurrency disabled" do
    test "should receive a message and handle it in the same consumer process", context do
      message = %{"msg" => "handled in the same process"}
      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: WithoutConcurrency)
      {:ok, pid} = GenRMQ.Consumer.start_link(WithoutConcurrency)

      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(WithoutConcurrency, fn set -> {message, pid} in set end) == true
      end)
    end
  end

  describe "GenRMQ.Consumer with reconnection disabled" do
    test "should terminate after connection failure" do
      Process.flag(:trap_exit, true)
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(WithoutReconnection)
      state = :sys.get_state(consumer_pid)

      AMQP.Connection.close(state.conn)

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == false
        assert Process.whereis(WithoutReconnection) == nil
      end)
    end

    test "should send exit signal after connection failure" do
      Process.flag(:trap_exit, true)
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(WithoutReconnection)
      state = :sys.get_state(consumer_pid)

      AMQP.Connection.close(state.conn)

      assert_receive({:EXIT, ^consumer_pid, :connection_closed})
    end
  end

  describe "GenRMQ.Consumer with custom deadletter setup" do
    test "should skip deadletter setup", context do
      message = %{"msg" => "some message"}
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(WithoutDeadletter)
      state = :sys.get_state(consumer_pid)

      publish_message(context[:rabbit_conn], state.config[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], "#{state.config[:queue]}_error") == {:error, :not_found}
      end)
    end

    test "should deadletter a message to a custom queue", context do
      message = %{"msg" => "some message"}
      {:ok, consumer_pid} = GenRMQ.Consumer.start_link(WithoutCustomDeadletter)
      state = :sys.get_state(consumer_pid)

      publish_message(context[:rabbit_conn], state.config[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], "dl_queue") == {:ok, 1}
      end)
    end
  end
end
