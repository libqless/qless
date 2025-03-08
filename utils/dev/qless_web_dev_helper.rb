module QlessWebDevHelper
  class NoPerformJob; end
  class << self
    def create_mock_jobs(client)
      queues = []

      num_queues = 5
      num_queues.times do |_i|
        random_queue_name = 'foo-' + random_jid
        queues << client.queues[random_queue_name]
      end

      num_jobs = 100
      num_jobs.times do
        queues.sample.put('Qless::Job', {}, jid: random_jid)
      end
      num_jobs.times do
        queue = queues.sample
        queue.put(NoPerformJob, {}, jid: random_jid)
        queue.pop.perform
      end
      # successfully complete 10% of jobs
      (num_jobs * 0.1).to_i.times do
        job = queues.sample.pop
        job.perform if job
      end
    end

    private

    def random_jid
      ('a'..'z').to_a.sample(8).join
    end
  end
end
