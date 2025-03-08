# Standard stuff
require 'time'
require 'logger'

# Qless requires
require 'qless'
require 'qless/subscriber'

module Qless
  module Workers
    JobLockLost = Class.new(StandardError)

    class BaseWorker
      attr_accessor :output, :reserver, :interval, :paused,
                    :options, :sighup_handler

      def initialize(reserver, options = {})
        # Our job reserver and options
        @reserver = reserver
        @options = options

        # SIGHUP handler
        @sighup_handler = options.fetch(:sighup_handler) { -> {} }

        # Our logger
        @log = options.fetch(:logger) do
          @output = options.fetch(:output, $stdout)
          Logger.new(output).tap do |logger|
            logger.level = options.fetch(:log_level, Logger::WARN)
            logger.formatter = options.fetch(:log_formatter) do
              proc { |_severity, datetime, _progname, msg| "#{datetime}: #{msg}\n" }
            end
          end
        end

        # The interval for checking for new jobs
        @interval = options.fetch(:interval, 5.0)
        @current_job_mutex = Mutex.new
        @current_job = nil

        # Default behavior when a lock is lost: stop after the current job.
        on_current_job_lock_lost { shutdown(false) }
      end

      def log_level
        @log.level
      end

      def safe_trap(signal_name, &cblock)
        trap(signal_name, cblock)
      rescue ArgumentError
        warn "Signal #{signal_name} not supported."
      end

      # The meaning of these signals is meant to closely mirror resque
      #
      # TERM: Shutdown immediately, stop processing jobs.
      #  INT: Shutdown immediately, stop processing jobs.
      # QUIT: Shutdown after the current job has finished processing.
      # USR1: Kill the forked children immediately, continue processing jobs.
      # USR2: Pause after this job
      # CONT: Start processing jobs again after a USR2
      #  HUP: Print current stack to log and continue
      def register_signal_handlers
        # Otherwise, we want to take the appropriate action
        trap('TERM') { exit! }
        trap('INT')  { exit! }
        safe_trap('HUP') { sighup_handler.call }
        safe_trap('QUIT') { shutdown(true) }
        begin
          trap('CONT') { unpause(true) }
          trap('USR2') { pause(true) }
        rescue ArgumentError
          warn 'Signals USR2, and/or CONT not supported.'
        end
      end

      # Return an enumerator to each of the jobs provided by the reserver
      def jobs
        Enumerator.new do |enum|
          loop do
            # So long as we're paused, we should wait
            if paused
              log(:debug, 'Paused...')
              sleep interval
            else
              begin
                job = reserver.reserve
              rescue Exception => e
                # We want workers to durably stay up, so we don't want errors
                # during job reserving (e.g. network timeouts, etc) to kill the
                # worker.
                log(:error,
                    "Error reserving job: #{e.class}: #{e.message}")
              end

              # If we ended up getting a job, yield it. Otherwise, we wait
              if job.nil?
                no_job_available
              else
                self.current_job = job
                enum.yield(job)
                self.current_job = nil
              end
            end

            break if @shutdown
          end
        end
      end

      # Actually perform the job
      def perform(job)
        start_time = Time.now.to_f
        around_perform(job)
      rescue JobLockLost
        log(:warn, "Lost lock for job #{job.jid}")
      rescue Exception => e
        fail_job(job, e, caller)
      else
        try_complete(job)
      ensure
        elapsed_time = Time.now.to_f - start_time
        log(:info, "Job #{job.description} took #{elapsed_time} seconds")
      end

      # Allow middleware modules to be mixed in and override the
      # definition of around_perform while providing a default
      # implementation so our code can assume the method is present.
      module SupportsMiddlewareModules
        def around_perform(job)
          job.perform
        end

        def after_fork; end
      end

      include SupportsMiddlewareModules

      # Stop processing after this job
      def shutdown(_in_signal_handler = true)
        @shutdown = true
      end
      alias stop! shutdown # so we can call `stop!` regardless of the worker type

      # Pause the worker -- take no more new jobs
      def pause(in_signal_handler = true)
        @paused = true
        procline("Paused -- #{reserver.description}", in_signal_handler)
      end

      # Continue taking new jobs
      def unpause(_in_signal_handler = true)
        @paused = false
      end

      # Set the procline. Not supported on all systems
      def procline(value, in_signal_handler = true)
        $0 = "Qless-#{Qless::VERSION}: #{value} at #{Time.now.iso8601}"
        log(:debug, $PROGRAM_NAME) unless in_signal_handler
      end

      # Complete the job unless the worker has already put it into another state
      # by completing / failing / etc. the job
      def try_complete(job)
        job.complete unless job.state_changed?
      rescue Job::CantCompleteError => e
        # There's not much we can do here. Complete fails in a few cases:
        #   - The job is already failed (i.e. by another worker)
        #   - The job is being worked on by another worker
        #   - The job has been cancelled
        #
        # We don't want to (or are able to) fail the job with this error in
        # any of these cases, so the best we can do is log the failure.
        log(:warn, "Failed to complete #{job.inspect}: #{e.message}")
      end

      def fail_job(job, error, worker_backtrace)
        failure = Qless.failure_formatter.format(job, error, worker_backtrace)
        log(:error, "Got #{failure.group} failure from #{job.inspect}\n#{failure.message}")
        job.fail(*failure)
      rescue Job::CantFailError => e
        # There's not much we can do here. Another worker may have cancelled it,
        # or we might not own the job, etc. Logging is the best we can do.
        log(:error, "Failed to fail #{job.inspect}: #{e.message}")
      end

      def deregister
        uniq_clients.each do |client|
          client.deregister_workers(client.worker_name)
        end
      end

      def uniq_clients
        @uniq_clients ||= reserver.queues.map(&:client).uniq
      end

      def on_current_job_lock_lost(&block)
        @on_current_job_lock_lost = block
      end

      def listen_for_lost_lock
        subscribers = uniq_clients.map do |client|
          Subscriber.start(client, "ql:w:#{client.worker_name}", log: @log) do |_, message|
            if message['event'] == 'lock_lost'
              with_current_job do |job|
                @on_current_job_lock_lost.call(job) if job && message['jid'] == job.jid
              end
            end
          end
        end

        yield
      ensure
        subscribers.each(&:stop)
      end

      private

      def log(type, msg)
        @log.public_send(type, "#{Process.pid}: #{msg}")
      end

      def no_job_available
        return if interval.zero?

        procline("Waiting for #{reserver.description}", false)
        log(:debug, "Sleeping for #{interval} seconds")
        sleep interval
      end

      def with_current_job
        @current_job_mutex.synchronize do
          yield @current_job
        end
      end

      def current_job=(job)
        @current_job_mutex.synchronize do
          @current_job = job
        end
      end

      def reconnect_each_client
        uniq_clients.each { |client| client.redis._client.reconnect }
      end
    end
  end
end
