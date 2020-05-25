defmodule GenRMQ.ConsumerTest do
  use ExUnit.Case, async: false
  use GenRMQ.RabbitCase

  import ConsumerSharedTests

  alias GenRMQ.Test.Assert
  alias GenRMQ.Consumer

  alias TestConsumer.{
    Default,
    ErrorInConsumer,
    RedeclaringExistingExchange,
    SlowConsumer,
    WithCustomDeadletter,
    WithDirectExchange,
    WithFanoutExchange,
    WithMultiBindingExchange,
    WithPriority,
    WithQueueOptions,
    WithQueueOptionsWithoutArguments,
    WithTopicExchange,
    WithoutConcurrency,
    WithoutDeadletter,
    WithoutReconnection
  }

  @connection "amqp://guest:guest@localhost:5672"

  setup_all do
    {:ok, conn} = rmq_open(@connection)
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

    test "should fail when try to redeclare an exchange with different type", %{rabbit_conn: conn} do
      Process.flag(:trap_exit, true)
      {:ok, chan} = open_channel(conn)

      GenRMQ.Binding.declare_exchange(chan, {:direct, RedeclaringExistingExchange.existing_exchange()})
      {:ok, pid} = Consumer.start_link(RedeclaringExistingExchange, name: RedeclaringExistingExchange)

      assert_receive {:EXIT, ^pid, {{:shutdown, {:server_initiated_close, _, _}}, _}}
    end
  end

  describe "GenRMQ.Consumer.stop/2" do
    setup do
      with_test_consumer(Default)
    end

    test "should close connection after normal termination", %{consumer: consumer_pid, state: state} do
      Consumer.stop(consumer_pid, :normal)

      assert_receive({:EXIT, ^consumer_pid, :normal})
      assert Process.alive?(state.conn.pid) == false
    end

    test "should close connection after abnormal termination", %{consumer: consumer_pid, state: state} do
      Consumer.stop(consumer_pid, :unexpected_reason)

      assert_receive({:EXIT, ^consumer_pid, :unexpected_reason})
      assert Process.alive?(state.conn.pid) == false
    end
  end

  describe "TestConsumer.Default" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: Default)
      with_test_consumer(Default)
    end

    receive_message_test(Default)

    reject_message_test()

    reconnect_after_connection_failure_test(Default)

    terminate_after_queue_deletion_test()

    exit_signal_after_queue_deletion_test()

    close_connection_and_channels_after_deletion_test()

    close_connection_and_channels_after_shutdown_test()
  end

  describe "TestConsumer.ErrorInConsumer" do
    setup :attach_telemetry_handlers

    setup do
      ErrorInConsumer.start_link(self())
      with_test_consumer(ErrorInConsumer)
    end

    test "should invoke the user's handle_error callback if an error occurs",
         %{consumer: consumer_pid, state: state} = context do
      clear_mailbox()

      # Pass in a value that will raise
      message = %{"value" => 0}

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], state[:config][:queue].name) == {:ok, 0}
      end)

      assert_receive {:telemetry_event, [:gen_rmq, :consumer, :message, :error], %{time: _, duration: _},
                      %{reason: {%RuntimeError{message: "Can't divide by zero!"}, _}, module: _, message: _}}

      assert_receive {:task_error, {%RuntimeError{message: "Can't divide by zero!"}, _}}

      # Check that the message made it to the deadletter queue
      dl_queue = state.config[:queue][:dead_letter][:name]

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], dl_queue) == {:ok, 1}
        {:ok, _, _} = get_message_from_queue(context[:rabbit_conn], dl_queue)
      end)
    end

    test "should not invoke the user's handle_error callback if an error does not occur",
         %{consumer: consumer_pid, state: state} = context do
      clear_mailbox()

      # Pass in a value that will not raise
      message = %{"value" => 1}

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], state[:config][:queue].name) == {:ok, 0}
      end)

      refute_receive {:telemetry_event, [:gen_rmq, :consumer, :message, :error], %{time: _}, %{reason: _, module: _}}
      refute_receive {:task_error, :error}
    end
  end

  describe "TestConsumer.SlowConsumer" do
    setup :attach_telemetry_handlers

    setup do
      SlowConsumer.start_link(self())
      with_test_consumer(SlowConsumer)
    end

    test "should wait for the in progress tasks to complete processing before terminating consumer",
         %{consumer: consumer_pid, state: state} = context do
      # Time to sleep consumer
      message = %{"value" => 500}

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], state[:config][:queue].name) == {:ok, 0}
      end)

      GenServer.stop(consumer_pid)

      refute_receive {:telemetry_event, [:gen_rmq, :consumer, :message, :error], %{time: _}, %{reason: _, module: _}}

      assert_receive(
        {:telemetry_event, [:gen_rmq, :consumer, :message, :start], %{time: _}, %{message: _, module: _}},
        1_000
      )

      assert_receive(
        {:telemetry_event, [:gen_rmq, :consumer, :message, :stop], %{time: _, duration: _}, %{message: _, module: _}},
        1_000
      )

      refute_receive {:task_error, :error}
    end

    test "should error out the task if it takes too long",
         %{consumer: consumer_pid, state: state} = context do
      # Time to sleep consumer
      message = %{"value" => 500}

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], state[:config][:queue].name) == {:ok, 0}
      end)

      assert_receive {:telemetry_event, [:gen_rmq, :consumer, :message, :start], %{time: _}, %{message: _, module: _}}

      refute_receive(
        {:telemetry_event, [:gen_rmq, :consumer, :message, :stop], %{time: _, duration: _}, %{message: _, module: _}},
        500
      )

      assert_receive {:telemetry_event, [:gen_rmq, :consumer, :message, :error], %{time: _, duration: _},
                      %{reason: :killed, module: _, message: _}}

      assert_receive {:task_error, :killed}

      # Check that the message made it to the deadletter queue
      dl_queue = state.config[:queue][:dead_letter][:name]

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], dl_queue) == {:ok, 1}
        {:ok, _, _} = get_message_from_queue(context[:rabbit_conn], dl_queue)
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

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(WithoutConcurrency, fn set -> {message, consumer_pid} in set end) == true
      end)
    end
  end

  describe "TestConsumer.WithoutReconnection" do
    setup do
      with_test_consumer(WithoutReconnection)
    end

    test "should terminate after connection failure", %{consumer: consumer_pid, state: state} do
      AMQP.Connection.close(state.conn)

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == false
        assert Process.whereis(WithoutReconnection) == nil
      end)
    end

    test "should send exit signal after connection failure", %{consumer: consumer_pid, state: state} do
      AMQP.Connection.close(state.conn)

      assert_receive({:EXIT, ^consumer_pid, :connection_closed})
    end
  end

  describe "TestConsumer.WithoutDeadletter" do
    setup do
      with_test_consumer(WithoutDeadletter)
    end

    test "should skip deadletter setup", %{consumer: consumer_pid, state: state} = context do
      message = %{"msg" => "some message"}

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], state[:config][:queue].name) == {:ok, 0}
        assert queue_count(context[:rabbit_conn], state.config[:queue][:dead_letter][:name]) == {:error, :not_found}
      end)
    end
  end

  describe "TestConsumer.WithQueueOptions" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: WithQueueOptions)
      with_test_consumer(WithQueueOptions)
    end

    receive_message_test(WithQueueOptions)

    reject_message_test()

    reconnect_after_connection_failure_test(WithQueueOptions)

    terminate_after_queue_deletion_test()

    exit_signal_after_queue_deletion_test()

    close_connection_and_channels_after_deletion_test()

    close_connection_and_channels_after_shutdown_test()
  end

  describe "TestConsumer.WithCustomDeadletter" do
    setup do
      with_test_consumer(WithCustomDeadletter)
    end

    test "should deadletter a message to a custom queue", %{consumer: consumer_pid, state: state} = context do
      message = %{"msg" => "some message"}
      dl_queue = state.config[:queue][:dead_letter][:name]

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message))

      Assert.repeatedly(fn ->
        assert Process.alive?(consumer_pid) == true
        assert queue_count(context[:rabbit_conn], dl_queue) == {:ok, 1}
        {:ok, _, meta} = get_message_from_queue(context[:rabbit_conn], dl_queue)
        assert meta[:routing_key] == "dl_routing_key"
        assert meta[:exchange] == "dl_exchange"
      end)
    end
  end

  describe "TestConsumer.WithPriority" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: WithPriority)
      with_test_consumer(WithPriority)
    end

    test "should receive a message", context do
      message = %{"msg" => "message with prio"}

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message), "", priority: 5)

      Assert.repeatedly(fn ->
        assert Agent.get(WithPriority, fn set -> message in set end) == true
      end)
    end
  end

  describe "TestConsumer.WithTopicExchange" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: WithTopicExchange)
      with_test_consumer(WithTopicExchange)
    end

    receive_message_test(WithTopicExchange)

    reject_message_test()

    reconnect_after_connection_failure_test(WithTopicExchange)

    terminate_after_queue_deletion_test()

    exit_signal_after_queue_deletion_test()

    close_connection_and_channels_after_deletion_test()

    close_connection_and_channels_after_shutdown_test()
  end

  describe "TestConsumer.WithDirectExchange" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: WithDirectExchange)
      with_test_consumer(WithDirectExchange)
    end

    receive_message_test(WithDirectExchange)

    reject_message_test()

    reconnect_after_connection_failure_test(WithDirectExchange)

    terminate_after_queue_deletion_test()

    exit_signal_after_queue_deletion_test()

    close_connection_and_channels_after_deletion_test()

    close_connection_and_channels_after_shutdown_test()
  end

  describe "TestConsumer.WithFanoutExchange" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: WithFanoutExchange)
      with_test_consumer(WithFanoutExchange)
    end

    test "should receive a message, no matter the routing key", context do
      message = %{"msg" => "some message"}

      publish_message(
        context[:rabbit_conn],
        context[:exchange],
        Jason.encode!(message),
        "sdlkjkjlefberBogusKEYWHatever"
      )

      Assert.repeatedly(fn ->
        assert Agent.get(WithFanoutExchange, fn set -> message in set end) == true
      end)
    end

    reject_message_test()

    reconnect_after_connection_failure_test(WithFanoutExchange)

    terminate_after_queue_deletion_test()

    exit_signal_after_queue_deletion_test()

    close_connection_and_channels_after_deletion_test()

    close_connection_and_channels_after_shutdown_test()
  end

  describe "TestConsumer.WithMultiBindingExchange" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: WithMultiBindingExchange)
      with_test_consumer(WithMultiBindingExchange)
    end

    test "should receive a message under the first key", context do
      message = %{"msg" => "some message"}

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message), "routing_key_2")

      Assert.repeatedly(fn ->
        assert Agent.get(WithMultiBindingExchange, fn set -> message in set end) == true
      end)
    end

    test "should receive a message under the second key", context do
      message = %{"msg" => "some message"}

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message), "routing_key_2")

      Assert.repeatedly(fn ->
        assert Agent.get(WithMultiBindingExchange, fn set -> message in set end) == true
      end)
    end

    test "should reject a message", %{state: state} = context do
      message = "reject"

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message), "routing_key_1")

      Assert.repeatedly(fn ->
        assert queue_count(context[:rabbit_conn], state.config[:queue][:dead_letter][:name]) == {:ok, 1}
      end)
    end

    test "should reconnect after connection failure", %{state: state} = context do
      message = "disconnect"
      AMQP.Connection.close(state.conn)

      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message), "routing_key_1")

      Assert.repeatedly(fn ->
        assert Agent.get(WithMultiBindingExchange, fn set -> message in set end) == true
      end)
    end

    terminate_after_queue_deletion_test()

    exit_signal_after_queue_deletion_test()

    close_connection_and_channels_after_deletion_test()

    close_connection_and_channels_after_shutdown_test()
  end

  describe "TestConsumer.WithQueueOptionsWithoutArguments" do
    setup do
      Agent.start_link(fn -> MapSet.new() end, name: WithQueueOptionsWithoutArguments)
      with_test_consumer(WithQueueOptionsWithoutArguments)
    end

    receive_message_test(WithQueueOptionsWithoutArguments)

    reconnect_after_connection_failure_test(WithQueueOptionsWithoutArguments)

    terminate_after_queue_deletion_test()

    exit_signal_after_queue_deletion_test()

    close_connection_and_channels_after_deletion_test()

    close_connection_and_channels_after_shutdown_test()
  end

  describe "Telemetry events" do
    setup :attach_telemetry_handlers

    setup do
      Agent.start_link(fn -> MapSet.new() end, name: WithoutConcurrency)
      with_test_consumer(WithoutConcurrency)
    end

    test "should be emitted when the consumer starts and completes setup" do
      assert_receive {:telemetry_event, [:gen_rmq, :consumer, :connection, :start], %{time: _},
                      %{module: _, attempt: _, queue: _, exchange: _, routing_key: _}}

      assert_receive {:telemetry_event, [:gen_rmq, :consumer, :connection, :stop], %{time: _, duration: _},
                      %{module: _, attempt: _, queue: _, exchange: _, routing_key: _}}
    end

    test "should be emitted when the consumer starts and stops processing the message",
         %{consumer: consumer_pid} = context do
      message = %{"msg" => "handled in the same process"}
      publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(WithoutConcurrency, fn set -> {message, consumer_pid} in set end) == true
      end)

      assert_receive {:telemetry_event, [:gen_rmq, :consumer, :message, :start], %{time: _}, %{message: _, module: _}}

      assert_receive {:telemetry_event, [:gen_rmq, :consumer, :message, :stop], %{time: _, duration: _},
                      %{message: _, module: _}}
    end
  end

  defp attach_telemetry_handlers(%{test: test}) do
    self = self()

    :ok =
      :telemetry.attach_many(
        "#{test}",
        [
          [:gen_rmq, :consumer, :message, :start],
          [:gen_rmq, :consumer, :message, :stop],
          [:gen_rmq, :consumer, :connection, :start],
          [:gen_rmq, :consumer, :connection, :stop],
          [:gen_rmq, :consumer, :message, :error]
        ],
        fn name, measurements, metadata, _ ->
          send(self, {:telemetry_event, name, measurements, metadata})
        end,
        nil
      )
  end

  defp with_test_consumer(module) do
    Process.flag(:trap_exit, true)
    {:ok, consumer_pid} = Consumer.start_link(module)

    state = :sys.get_state(consumer_pid)
    exchange = state.config[:exchange]

    on_exit(fn -> Process.exit(consumer_pid, :normal) end)
    {:ok, %{consumer: consumer_pid, exchange: exchange, state: state}}
  end

  defp clear_mailbox do
    receive do
      _lingering_message -> clear_mailbox()
    after
      100 -> :ok
    end
  end
end
