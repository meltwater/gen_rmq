defmodule GenRMQ.Queue do
  @moduledoc """
  This module defines utility functions for queues
  """

  defdelegate consumer_count(channel, queue), to: AMQP.Queue
  defdelegate empty?(channel, queue), to: AMQP.Queue
  defdelegate message_count(channel, queue), to: AMQP.Queue
  defdelegate purge(channel, queue), to: AMQP.Queue
  defdelegate status(channel, queue), to: AMQP.Queue
end
