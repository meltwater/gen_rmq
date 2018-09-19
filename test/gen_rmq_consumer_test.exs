defmodule GenRMQ.ConsumerTest do
  use ExUnit.Case, async: false
  use GenRMQ.RabbitCase

  alias GenRMQ.Test.Assert

  alias GenRMQ.Consumer
  alias TestConsumer.Default
  alias TestConsumer.WithCustomDeadletter
  alias TestConsumer.WithoutConcurrency
  alias TestConsumer.WithoutDeadletter
  alias TestConsumer.WithoutReconnection

  @uri "amqp://guest:guest@localhost:5672"

  setup_all do
    {:ok, conn} = rmq_open(@uri)
    {:ok, rabbit_conn: conn}
  end

  describe "GenRMQ.Consumer.start_link/2" do
    test "should start a new consumer" do
      {:ok, pid} = Consumer.start_link(Default)
      assert Process.alive?(pid)
      assert Consumer.stop(pid, :normal) == :ok
    end

    test "should start a new consumer registered by name" do
      {:ok, pid} = Consumer.start_link(Default, name: Default)
      assert pid == Process.whereis(Default)
      assert Consumer.stop(pid, :normal) == :ok
    end
  end

  describe "GenRMQ.Consumer.stop/2" do
    test "should close connection after being stopped" do
      {:ok, consumer_pid} = Consumer.start_link(Default, name: Default)
      state = :sys.get_state(consumer_pid)

      Consumer.stop(Default, :normal)

      Assert.repeatedly(fn ->
        assert Process.alive?(state.conn.pid) == false
      end)
    end

    test "should send exit signal after abnormal termination" do
      Process.flag(:trap_exit, true)
      {:ok, consumer_pid} = Consumer.start_link(Default, name: Default)

      Consumer.stop(Default, :not_normal)

      assert_receive({:EXIT, ^consumer_pid, :not_normal})
    end
  end

  describe "TestConsumer.Default" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: Default)
      with_test_consumer(Default)
    end

    test "should receive a message", context do
      message = %{"msg" => "some message"}

      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(Default, fn set -> message in set end) == true
      end)
    end

    test "should reject a message", %{consumer: consumer_pid} = context do
      message = "reject"
      state = :sys.get_state(consumer_pid)

      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert queue_count(context[:rabbit_conn], "#{state.config[:queue]}_error") == {:ok, 1}
      end)
    end

    test "should reconnect after connection failure", %{consumer: consumer_pid} = context do
      message = "disconnect"
      state = :sys.get_state(consumer_pid)

      AMQP.Connection.close(state.conn)
      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(Default, fn set -> message in set end) == true
      end)
    end

    test "should terminate after queue deletion", %{consumer: consumer_pid} do
      Process.flag(:trap_exit, true)
      state = :sys.get_state(consumer_pid)

      AMQP.Queue.delete(state.out, state[:config][:queue])

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == false
      end)
    end

    test "should send exit signal after queue deletion", %{consumer: consumer_pid} do
      Process.flag(:trap_exit, true)
      state = :sys.get_state(consumer_pid)

      AMQP.Queue.delete(state.out, state[:config][:queue])

      assert_receive({:EXIT, ^consumer_pid, :cancelled})
    end

    test "should close connection and channels after queue deletion", %{consumer: consumer_pid} do
      Process.flag(:trap_exit, true)
      state = :sys.get_state(consumer_pid)

      AMQP.Queue.delete(state.out, state[:config][:queue])

      Assert.repeatedly(fn ->
        assert Process.alive?(state.conn.pid) == false
        assert Process.alive?(state.in.pid) == false
        assert Process.alive?(state.out.pid) == false
      end)
    end
  end

  describe "TestConsumer.WithoutConcurrency" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: WithoutConcurrency)
      with_test_consumer(WithoutConcurrency)
    end

    test "should receive a message and handle it in the same consumer process", %{consumer: consumer_pid} = context do
      message = %{"msg" => "handled in the same process"}

      publish_message(context[:rabbit_conn], context[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(WithoutConcurrency, fn set -> {message, consumer_pid} in set end) == true
      end)
    end
  end

  describe "TestConsumer.WithoutReconnection" do
    setup do
      with_test_consumer(WithoutReconnection)
    end

    test "should terminate after connection failure", %{consumer: consumer_pid} do
      Process.flag(:trap_exit, true)
      state = :sys.get_state(consumer_pid)

      AMQP.Connection.close(state.conn)

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == false
        assert Process.whereis(WithoutReconnection) == nil
      end)
    end

    test "should send exit signal after connection failure", %{consumer: consumer_pid} do
      Process.flag(:trap_exit, true)
      state = :sys.get_state(consumer_pid)

      AMQP.Connection.close(state.conn)

      assert_receive({:EXIT, ^consumer_pid, :connection_closed})
    end
  end

  describe "TestConsumer.WithoutDeadletter" do
    setup do
      with_test_consumer(WithoutDeadletter)
    end

    test "should skip deadletter setup", %{consumer: consumer_pid} = context do
      message = %{"msg" => "some message"}
      state = :sys.get_state(consumer_pid)

      publish_message(context[:rabbit_conn], state.config[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], "#{state.config[:queue]}_error") == {:error, :not_found}
      end)
    end
  end

  describe "TestConsumer.WithCustomDeadletter" do
    setup do
      with_test_consumer(WithCustomDeadletter)
    end

    test "should deadletter a message to a custom queue", %{consumer: consumer_pid} = context do
      message = %{"msg" => "some message"}
      state = :sys.get_state(consumer_pid)

      publish_message(context[:rabbit_conn], state.config[:exchange], Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], "dl_queue") == {:ok, 1}
      end)
    end
  end

  defp with_test_consumer(module) do
    {:ok, consumer_pid} = Consumer.start_link(module)

    exchange =
      module
      |> :erlang.apply(:init, [])
      |> Keyword.get(:exchange)

    on_exit(fn ->
      if Process.alive?(consumer_pid) do
        Consumer.stop(consumer_pid, :normal)
      end
    end)

    {:ok, %{consumer: consumer_pid, exchange: exchange}}
  end
end
