require "dbcron/version"
require "parse-cron"
require "active_record"
require "active_support/time"
require "celluloid/current"

# nodoc
module DBcron
  GRACE_TIME = 5.minutes
  SLEEPY_TIME = 3.seconds
  HOST_ALIVE_TIME = 15.seconds
  UTC = ActiveSupport::TimeZone["UTC"]

  # nodoc
  module Actor
    def self.included(klass)
      klass.__send__(:include, Celluloid)
      klass.__send__(:include, Celluloid::Internals::Logger)
    end
  end

  class << self
    def schedule(**opts)
      Celluloid.logger = opts[:logger] if opts[:logger]

      Class.new(Celluloid::Supervision::Container) do
        supervise type: Clock, as: :clock
        pool TaskRunner, as: :task_runners
      end.run!

      Celluloid::Actor[:clock].configure(opts)

      yield(Celluloid::Actor[:clock])
    end

    def start
      fail "You must run `dbcron.schedule` first" unless Celluloid::Actor[:clock]
      Celluloid::Actor[:clock].start
    end
  end

  # nodoc
  class Host < ActiveRecord::Base
    self.table_name = "dbcron_hosts"
  end

  # nodoc
  class Entry < ActiveRecord::Base
    self.table_name = "dbcron_entries"
  end

  # nodoc
  class CrontabEntry
    attr_accessor :name, :last, :task

    def initialize(name, cron:, task:)
      @name = name
      @cron = CronParser.new(cron, Celluloid::Actor[:clock].tz)
      @task = task
      @last = nil
    end

    def ready?(time)
      return false if @cron.next(time) > time + GRACE_TIME # is it time for the task?
      return false if @last && (time - @last) < interval # running too often?
      return false if !@last && time.sec > 2 * SLEEPY_TIME # for new tasks, start it as close as possible to the top of the minute

      true
    end

    def run!(time)
      @last = time

      Celluloid::Actor[:task_runners].async.dispatch(@task)
    end

    private

    def interval
      @interval ||= ((@cron.next - @cron.last) / 2).seconds
    end
  end

  # nodoc
  class TaskRunner
    include Actor

    def dispatch(task)
      task.call
    rescue => boom
      error "failed: #{boom}"
    end
  end

  # nodoc
  class Clock
    include Actor

    attr_accessor :stop
    attr_reader :tz

    finalizer :finalize

    def initialize
      @tasks = {}
      @last_refresh = nil
      @tz = UTC
      @uuid = SecureRandom.uuid
    end

    def configure(opts = {})
      @tz = opts[:tz] if opts[:tz]
    end

    def add_entry(name, cron, task)
      @tasks[name] = CrontabEntry.new(name, cron: cron, task: task)
    end

    def ready_tasks(time)
      task_array.select { |e| e.ready?(time) }
    end

    def task_array
      @task_array ||= @tasks.values
    end

    def start
      started_at = now

      host = Host.where(uuid: @uuid).first_or_create!(
        hostname: Socket.gethostname,
        pid: Process.pid,
        started: started_at,
        last_seen: started_at
      )

      create(task_array)
      refresh(task_array)

      info "dbcron starting with #{worker_pool_size} workers"

      loop do
        start = now

        if start >= host.last_seen + HOST_ALIVE_TIME
          host.update_column(:last_seen, start)
        end

        tick(start)

        finish = now

        sleep_until_next_tick(finish)

        break if @stop
      end
    end

    private

    def finalize
      @stop = true
    end

    def create(tasks)
      tasks.each do |task|
        begin
          Entry.transaction do
            Entry.where(task: task.name).first_or_create!
          end
        rescue ActiveRecord::RecordNotUnique => _ # rubocop:disable Lint/HandleExceptions
          # this is fine - the record already exists
        end
      end
    end

    def refresh(tasks)
      Entry.where(task: tasks.map(&:name)).each do |t|
        @tasks[t.task].last = t.last
      end
    end

    def tick(time)
      ready_tasks(time).shuffle.each_slice(worker_pool_size) do |tasks|
        task_names = tasks.map(&:name)

        Entry.transaction do
          Entry.where(task: task_names).lock(true).pluck(:id)

          info "running #{task_names.join(', ')}"

          refresh(tasks)

          ran_tasks = run_tasks(tasks, time)

          if ran_tasks.size != task_names.size
            info "did not run #{(task_names - ran_tasks.map(&:name)).join(', ')}"
          end

          unless ran_tasks.empty?
            Entry.where(task: ran_tasks.map(&:name)).update_all("last = CURRENT_TIMESTAMP")
          end
        end
      end
    end

    def run_tasks(tasks, time)
      tasks.select do |task|
        if task.ready?(time)
          task.run!(time)
          true
        else
          false
        end
      end
    end

    def sleep_until_next_tick(time)
      sleep_time = SLEEPY_TIME - time.subsec - (time.sec % SLEEPY_TIME)
      sleep(sleep_time)
    end

    def now
      timestamp = ActiveRecord::Base.connection.execute("SELECT CURRENT_TIMESTAMP")
      UTC.parse(timestamp.first.values.first).in_time_zone(@tz)
    end

    def worker_pool_size
      @worker_pool_size ||= Celluloid::Actor[:task_runners].size
    end
  end
end
