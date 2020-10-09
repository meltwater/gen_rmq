defmodule ConsumerSharedTests do
  @moduledoc """
  Shared tests used by multiple consumers.
  """

  defmacro receive_message_test(mod) do
    quote do
      test "should receive a message", context do
        message = %{"msg" => "some message"}

        publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message), context[:routing_key])

        GenRMQ.Test.Assert.repeatedly(fn ->
          assert Agent.get(unquote(mod), fn set -> message in set end) == true
        end)
      end
    end
  end

  defmacro reject_message_test do
    quote do
      test "should reject a message", %{state: state} = context do
        message = "reject"

        publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message), context[:routing_key])

        GenRMQ.Test.Assert.repeatedly(fn ->
          assert queue_count(context[:rabbit_conn], state.config[:queue][:dead_letter][:name]) == {:ok, 1}
        end)
      end
    end
  end

  defmacro reconnect_after_connection_failure_test(mod) do
    quote do
      test "should reconnect after connection failure", %{state: state} = context do
        message = "disconnect"
        AMQP.Connection.close(state.conn)

        publish_message(context[:rabbit_conn], context[:exchange], Jason.encode!(message), context[:routing_key])

        GenRMQ.Test.Assert.repeatedly(fn ->
          assert Agent.get(unquote(mod), fn set -> message in set end) == true
        end)
      end
    end
  end

  defmacro terminate_after_queue_deletion_test do
    quote do
      test "should terminate after queue deletion", %{consumer: consumer_pid, state: state} do
        AMQP.Queue.delete(state.out, state[:config][:queue].name)

        GenRMQ.Test.Assert.repeatedly(fn ->
          assert Process.alive?(consumer_pid) == false
        end)
      end
    end
  end

  defmacro exit_signal_after_queue_deletion_test do
    quote do
      test "should send exit signal after queue deletion", %{consumer: consumer_pid, state: state} do
        AMQP.Queue.delete(state.out, state.config[:queue].name)

        assert_receive({:EXIT, ^consumer_pid, :cancelled})
      end
    end
  end

  defmacro close_connection_and_channels_after_deletion_test do
    quote do
      test "should close connection and channels after queue deletion", %{state: state} do
        AMQP.Queue.delete(state.out, state.config[:queue].name)

        GenRMQ.Test.Assert.repeatedly(fn ->
          assert Process.alive?(state.conn.pid) == false
          assert Process.alive?(state.in.pid) == false
          assert Process.alive?(state.out.pid) == false
        end)
      end
    end
  end

  defmacro close_connection_and_channels_after_shutdown_test do
    quote do
      test "should close connection and channels after shutdown signal", %{consumer: consumer_pid, state: state} do
        Process.exit(consumer_pid, :shutdown)

        GenRMQ.Test.Assert.repeatedly(fn ->
          assert Process.alive?(state.conn.pid) == false
          assert Process.alive?(state.in.pid) == false
          assert Process.alive?(state.out.pid) == false
        end)
      end
    end
  end
end
