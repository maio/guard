require 'bundler'

module Guard

  autoload :UI,         'guard/ui'
  autoload :Dsl,        'guard/dsl'
  autoload :Interactor, 'guard/interactor'
  autoload :Listener,   'guard/listener'
  autoload :Watcher,    'guard/watcher'
  autoload :Notifier,   'guard/notifier'

  class << self
    attr_accessor :options, :guards, :listener

    # initialize this singleton
    def setup(options = {})
      @options  = options
      @listener = Listener.select_and_init
      @guards   = []
      self
    end

    def start(options = {})
      setup(options)

      Interactor.init_signal_traps
      Dsl.evaluate_guardfile(options)

      if guards.empty?
        UI.error "No guards found in Guardfile, please add at least one."
      else
        listener.on_change do |files|
          if Watcher.match_files?(guards, files)
            run { run_on_change_for_all_guards(files) }
          end
        end

        UI.info "Guard is now watching at '#{Dir.pwd}'"
        guards.each { |guard| supervised_task(guard, :start) }
        listener.start
      end
    end

    def run_on_change_for_all_guards(files)
      guards.each do |guard|
        paths = Watcher.match_files(guard, files)
        supervised_task(guard, :run_on_change, paths) unless paths.empty?
      end
      # Reparse the whole directory to catch new files modified during the guards run
      new_modified_files = listener.modified_files([Dir.pwd + '/'], :all => true)
      listener.update_last_event
      unless new_modified_files.empty?
        run_on_change_for_all_guards(new_modified_files)
      end
    end

    # Let a guard execute its task but
    # fire it if his work leads to a system failure
    def supervised_task(guard, task_to_supervise, *args)
      guard.send(task_to_supervise, *args)
    rescue Exception
      UI.error("#{guard.class.name} guard failed to achieve its <#{task_to_supervise.to_s}> command: #{$!}")
      ::Guard.guards.delete guard
      UI.info("Guard #{guard.class.name} has just been fired")
      return $!
    end

    def run
      listener.stop
      UI.clear if options[:clear]
      begin
        yield
      rescue Interrupt
      end
      listener.start
    end

    def add_guard(name, watchers = [], options = {})
      guard_class = get_guard_class(name)
      @guards << guard_class.new(watchers, options)
    end

    def get_guard_class(name)
      require "guard/#{name.downcase}"
      klasses = []
      ObjectSpace.each_object(Class) do |klass|
        klasses << klass if klass.to_s.downcase.match(/^guard::#{name.downcase}/)
      end
      klasses.first
    rescue LoadError
      UI.error "Could not find gem 'guard-#{name}', please add it in your Gemfile."
    end

    def locate_guard(name)
      `gem open guard-#{name} --latest --command echo`.chomp
    rescue
      UI.error "Could not find 'guard-#{name}' gem path."
    end

  end
end